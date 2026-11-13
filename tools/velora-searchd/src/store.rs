use crate::{
    config::{scrub, Config, SourceFilter},
    query::{self, Query},
};
use anyhow::{Context, Result};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::{cell::RefCell, collections::HashMap, os::unix::fs::MetadataExt, path::Path};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Hit {
    pub id: i64,
    pub path: String,
    pub name: String,
    pub kind: String,
    pub reason: String,
    pub snippet: String,
    pub timestamp: Option<f64>,
    pub score: f64,
    pub activity_at: Option<i64>,
    pub preview: Option<String>,
    #[serde(default)]
    pub partial: bool,
    #[serde(default)]
    pub matched_terms: Vec<String>,
    #[serde(default)]
    pub unmatched_terms: Vec<String>,
    #[serde(default)]
    pub corrections: Vec<query::Correction>,
    #[serde(skip)]
    pub evidence: String,
    #[serde(skip)]
    pub lexical: bool,
    #[serde(skip)]
    pub similarity: Option<f64>,
    #[serde(skip)]
    pub evidence_path: String,
    #[serde(skip)]
    pub application_context: Option<i64>,
}

fn hit_row(r: &rusqlite::Row<'_>) -> rusqlite::Result<Hit> {
    Ok(Hit {
        id: r.get(0)?,
        path: r.get(1)?,
        name: r.get(2)?,
        kind: r.get(3)?,
        reason: String::new(),
        snippet: String::new(),
        timestamp: None,
        score: 0.0,
        activity_at: None,
        preview: None,
        partial: false,
        matched_terms: vec![],
        unmatched_terms: vec![],
        corrections: vec![],
        evidence: String::new(),
        lexical: false,
        similarity: None,
        evidence_path: r.get(1)?,
        application_context: None,
    })
}

pub struct Store {
    pub db: Connection,
    query_cache: RefCell<(u64, HashMap<String, Vec<Hit>>)>,
    pub(crate) spelling_cache: RefCell<(u64, HashMap<String, Vec<String>>)>,
}

pub type Chunk = (String, Option<f64>, Option<String>, Option<Vec<u8>>);
pub const WORK_PRIORITY: &str = "CASE WHEN kind='config' AND size<=131072 THEN 0 WHEN kind='file' AND (lower(substr(path,-4))='.pdf' OR lower(substr(path,-3))='.md' OR lower(substr(path,-6))='.ipynb') THEN 0 WHEN kind IN ('file','config','app') THEN 2 ELSE 3 END";

fn grams(name: &str) -> String {
    let mut words = Vec::new();
    for variant in query::variants(name) {
        let chars: Vec<_> = variant.chars().take(128).collect();
        words.extend(
            chars
                .iter()
                .filter(|c| c.is_alphanumeric())
                .map(|c| format!("u{:x}", *c as u32)),
        );
        words.extend(
            chars
                .windows(2)
                .map(|w| format!("b{:x}x{:x}", w[0] as u32, w[1] as u32)),
        );
    }
    words.sort();
    words.dedup();
    words.join(" ")
}

impl Store {
    /// Clear only ephemeral query data, including spelling suggestions. Useful
    /// for measuring a warm index without concealing work behind result caches.
    pub fn clear_search_caches(&self) {
        self.query_cache.borrow_mut().1.clear();
        self.spelling_cache.borrow_mut().1.clear();
    }
    pub fn open(path: &Path, key: &[u8]) -> Result<Self> {
        Self::open_cancellable(path, key, || false)
    }

    pub fn open_cancellable(path: &Path, key: &[u8], cancelled: impl Fn() -> bool) -> Result<Self> {
        anyhow::ensure!(!cancelled(), "Index preparation cancelled");
        anyhow::ensure!(key.len() == 32, "Invalid database key");
        let db = Connection::open(path)?;
        let hex =
            zeroize::Zeroizing::new(key.iter().map(|b| format!("{b:02x}")).collect::<String>());
        let pragma = zeroize::Zeroizing::new(format!("x'{}'", *hex));
        db.pragma_update(None, "key", &*pragma)?;
        let cipher: String = db
            .pragma_query_value(None, "cipher_version", |r| r.get(0))
            .context("SQLCipher is required; refusing unencrypted storage")?;
        anyhow::ensure!(!cipher.is_empty(), "SQLCipher is required");
        db.execute_batch("PRAGMA temp_store=MEMORY; PRAGMA foreign_keys=ON; PRAGMA secure_delete=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA cache_size=-8192;")?;
        let version: i64 = db.pragma_query_value(None, "user_version", |r| r.get(0))?;
        anyhow::ensure!(version <= 3, "Index was created by a newer Lens version");
        db.execute_batch("CREATE TABLE IF NOT EXISTS files(
            id INTEGER PRIMARY KEY, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL, kind TEXT NOT NULL,
            mtime INTEGER NOT NULL, mtime_ns INTEGER NOT NULL DEFAULT 0, size INTEGER NOT NULL, dev INTEGER NOT NULL, ino INTEGER NOT NULL,
            fingerprint TEXT NOT NULL DEFAULT '', state TEXT NOT NULL DEFAULT 'pending', error TEXT NOT NULL DEFAULT '', offset INTEGER NOT NULL DEFAULT 0, project INTEGER NOT NULL DEFAULT 0);
            CREATE INDEX IF NOT EXISTS file_inode ON files(dev,ino);
            CREATE VIRTUAL TABLE IF NOT EXISTS names USING fts5(grams);
            CREATE TABLE IF NOT EXISTS chunks(id INTEGER PRIMARY KEY, file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                text TEXT NOT NULL DEFAULT '', timestamp REAL, space TEXT, vector BLOB);
            CREATE INDEX IF NOT EXISTS chunk_file ON chunks(file_id);
            CREATE TABLE IF NOT EXISTS ann(space TEXT PRIMARY KEY,snapshot BLOB NOT NULL);
            CREATE TABLE IF NOT EXISTS frames(file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE, at REAL NOT NULL, image TEXT NOT NULL, PRIMARY KEY(file_id,at));
            CREATE VIRTUAL TABLE IF NOT EXISTS content USING fts5(text, tokenize='unicode61');
            CREATE TRIGGER IF NOT EXISTS chunk_delete AFTER DELETE ON chunks BEGIN DELETE FROM content WHERE rowid=old.id; DELETE FROM ann; END;
            CREATE TRIGGER IF NOT EXISTS chunk_insert AFTER INSERT ON chunks BEGIN DELETE FROM ann; END;
            CREATE TRIGGER IF NOT EXISTS file_delete AFTER DELETE ON files BEGIN DELETE FROM names WHERE rowid=old.id; END;
            CREATE TABLE IF NOT EXISTS activity(file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                at INTEGER NOT NULL, app TEXT NOT NULL, source TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS activity_time ON activity(file_id,at);
            CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE VIRTUAL TABLE IF NOT EXISTS locations USING fts5(name,path,tokenize='unicode61');
            CREATE TRIGGER IF NOT EXISTS location_insert AFTER INSERT ON files BEGIN
                INSERT INTO locations(rowid,name,path) VALUES(new.id,new.name,new.path); END;
            CREATE TRIGGER IF NOT EXISTS location_update AFTER UPDATE OF name,path ON files BEGIN
                DELETE FROM locations WHERE rowid=old.id;
                INSERT INTO locations(rowid,name,path) VALUES(new.id,new.name,new.path); END;
            CREATE TRIGGER IF NOT EXISTS location_delete AFTER DELETE ON files BEGIN
                DELETE FROM locations WHERE rowid=old.id; END;")?;
        if version < 2 {
            db.execute_batch(
                "BEGIN; DELETE FROM locations;
                INSERT INTO locations(rowid,name,path) SELECT id,name,path FROM files;
                PRAGMA user_version=2; COMMIT;",
            )?;
        }
        crate::lexical::schema(&db)?;
        anyhow::ensure!(!cancelled(), "Index preparation cancelled");
        if version < 3 {
            db.execute_batch("BEGIN IMMEDIATE;")?;
            let migrate = (|| -> Result<()> {
                let mut files = db.prepare("SELECT id,path,name FROM files")?;
                for row in files.query_map([], |r| {
                    Ok((
                        r.get::<_, i64>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, String>(2)?,
                    ))
                })? {
                    anyhow::ensure!(!cancelled(), "Index preparation cancelled");
                    let (id, path, name) = row?;
                    crate::lexical::index(&db, id, 0, &format!("{path} {name}"), true)?;
                }
                let mut chunks =
                    db.prepare("SELECT file_id,text FROM chunks ORDER BY file_id,id")?;
                for row in
                    chunks.query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?
                {
                    anyhow::ensure!(!cancelled(), "Index preparation cancelled");
                    let (id, text) = row?;
                    crate::lexical::index(&db, id, 1, &text, false)?;
                }
                anyhow::ensure!(!cancelled(), "Index preparation cancelled");
                db.execute_batch("PRAGMA user_version=3; COMMIT;")?;
                Ok(())
            })();
            if migrate.is_err() {
                let _ = db.execute_batch("ROLLBACK;");
            }
            migrate?;
        }
        db.execute_batch(&format!(
            "DROP INDEX IF EXISTS file_work; CREATE INDEX IF NOT EXISTS file_work_v2 ON files(state, {WORK_PRIORITY}, id)"
        ))?;
        let extraction: Option<String> = db
            .query_row(
                "SELECT value FROM settings WHERE key='extraction_revision'",
                [],
                |r| r.get(0),
            )
            .optional()?;
        if extraction.as_deref() != Some("2") {
            // Keep old results usable while the corrected scrubber/parser
            // refreshes text. Unchanged passages retain their model vectors.
            db.execute_batch(
                "BEGIN;
                UPDATE files SET state='pending',offset=0 WHERE kind IN ('file','config');
                INSERT OR REPLACE INTO settings VALUES('extraction_revision','2');
                COMMIT;",
            )?;
        }
        Ok(Self {
            db,
            query_cache: RefCell::default(),
            spelling_cache: RefCell::default(),
        })
    }

    pub fn config(&self) -> Result<Config> {
        Ok(self
            .db
            .query_row("SELECT value FROM settings WHERE key='config'", [], |r| {
                r.get::<_, String>(0)
            })
            .optional()?
            .map(|s| serde_json::from_str(&s))
            .transpose()?
            .unwrap_or_default())
    }

    pub fn set_config(&mut self, config: &Config) -> Result<()> {
        let paths = self.paths()?;
        let previous = self.config()?;
        let tx = self.db.transaction()?;
        tx.execute(
            "INSERT OR REPLACE INTO settings VALUES('config',?1)",
            [serde_json::to_string(config)?],
        )?;
        Self::delete_excluded(&tx, paths, config)?;
        if !config.activity {
            tx.execute("DELETE FROM activity", [])?;
        }
        if !config.media {
            tx.execute("DELETE FROM chunks WHERE file_id IN (SELECT id FROM files WHERE kind IN ('photo','video'))",[])?;
            tx.execute("DELETE FROM frames", [])?;
        }
        if previous.media != config.media {
            tx.execute(
                "UPDATE files SET state=?1,offset=0,fingerprint='' WHERE kind IN ('photo','video')",
                [if config.media { "pending" } else { "ready" }],
            )?;
        }
        tx.commit()?;
        self.db.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
        Ok(())
    }

    // Reapply built-in rules after an upgrade, before old generated files can
    // consume the catalogue limit or be scheduled for extraction again.
    pub fn prune_excluded(&mut self, config: &Config) -> Result<usize> {
        let paths = self.paths()?;
        let tx = self.db.transaction()?;
        let removed = Self::delete_excluded(&tx, paths, config)?;
        tx.commit()?;
        if removed > 0 {
            self.db.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);")?;
        }
        Ok(removed)
    }

    fn delete_excluded(
        db: &Connection,
        paths: Vec<(i64, String)>,
        config: &Config,
    ) -> Result<usize> {
        let mut filter = SourceFilter::new(config);
        let mut removed = 0;
        for (id, path) in paths {
            if !filter.allows(Path::new(&path)) {
                removed += db.execute("DELETE FROM files WHERE id=?1", [id])?;
            }
        }
        if removed > 0 {
            db.execute("DELETE FROM ann", [])?;
        }
        Ok(removed)
    }

    pub fn paths(&self) -> Result<Vec<(i64, String)>> {
        Ok(self
            .db
            .prepare("SELECT id,path FROM files WHERE kind!='app'")?
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect::<rusqlite::Result<_>>()?)
    }

    #[allow(clippy::too_many_arguments)] // Keep filesystem metadata explicit at the indexing boundary.
    pub fn upsert(
        &mut self,
        path: &Path,
        kind: &str,
        name: &str,
        mtime: i64,
        size: u64,
        dev: u64,
        ino: u64,
    ) -> Result<i64> {
        let nanos = path.metadata().map(|m| m.mtime_nsec()).unwrap_or(0);
        let path = path.to_string_lossy();
        let unchanged=self.db.query_row("SELECT id FROM files WHERE path=?1 AND name=?2 AND kind=?3 AND mtime=?4 AND size=?5 AND dev=?6 AND ino=?7 AND mtime_ns=?8",params![path,name,kind,mtime,size,dev,ino,nanos],|r|r.get::<_,i64>(0)).optional()?;
        if let Some(id) = unchanged {
            return Ok(id);
        }
        let transaction = if self.db.is_autocommit() {
            Some(self.db.unchecked_transaction()?)
        } else {
            None
        };
        // Preserve identity, embeddings and history for a move on the same filesystem.
        let previous: Option<(i64, String)> = self
            .db
            .query_row(
                "SELECT id,path FROM files WHERE dev=?1 AND ino=?2 AND kind!='app' LIMIT 1",
                params![dev, ino],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        if let Some((id, old)) = previous {
            if old != path && !Path::new(&old).exists() {
                self.db.execute("UPDATE files SET path=?1,name=?2,state=CASE WHEN state='failed' THEN 'pending' ELSE state END WHERE id=?3", params![path,name,id])?;
            }
        }
        self.db.execute("INSERT INTO files(path,name,kind,mtime,size,dev,ino,mtime_ns) VALUES(?1,?2,?3,?4,?5,?6,?7,?8)
            ON CONFLICT(path) DO UPDATE SET name=excluded.name,kind=excluded.kind,
            state=CASE WHEN files.mtime!=excluded.mtime OR files.mtime_ns!=excluded.mtime_ns OR files.size!=excluded.size THEN 'pending' ELSE files.state END,
            offset=CASE WHEN files.mtime!=excluded.mtime OR files.mtime_ns!=excluded.mtime_ns OR files.size!=excluded.size THEN 0 ELSE files.offset END,
            mtime=excluded.mtime,mtime_ns=excluded.mtime_ns,size=excluded.size,dev=excluded.dev,ino=excluded.ino", params![path,name,kind,mtime,size,dev,ino,nanos])?;
        let id = self
            .db
            .query_row("SELECT id FROM files WHERE path=?1", [path.as_ref()], |r| {
                r.get::<_, i64>(0)
            })?;
        self.db.execute("DELETE FROM names WHERE rowid=?1", [id])?;
        self.db.execute(
            "INSERT INTO names(rowid,grams) VALUES(?1,?2)",
            params![id, grams(name)],
        )?;
        crate::lexical::index(&self.db, id, 0, &format!("{path} {name}"), true)?;
        if kind == "folder" {
            let project = [
                ".git",
                "pyproject.toml",
                "Cargo.toml",
                "package.json",
                "CMakeLists.txt",
            ]
            .iter()
            .any(|p| Path::new(path.as_ref()).join(p).exists());
            self.db.execute(
                "UPDATE files SET project=?1 WHERE id=?2",
                params![project, id],
            )?;
        }
        if let Some(tx) = transaction {
            tx.commit()?;
        }
        Ok(id)
    }

    pub fn replace_chunks(&mut self, id: i64, fingerprint: &str, chunks: &[Chunk]) -> Result<()> {
        let tx = self.db.transaction()?;
        tx.execute("DELETE FROM chunks WHERE file_id=?1", [id])?;
        tx.execute(
            "DELETE FROM file_lexemes WHERE file_id=?1 AND source=1",
            [id],
        )?;
        for (text, time, space, vector) in chunks {
            let text = scrub(text);
            tx.execute(
                "INSERT INTO chunks(file_id,text,timestamp,space,vector) VALUES(?1,?2,?3,?4,?5)",
                params![id, text, time, space, vector],
            )?;
            tx.execute(
                "INSERT INTO content(rowid,text) VALUES(?1,?2)",
                params![tx.last_insert_rowid(), text],
            )?;
            crate::lexical::index(&tx, id, 1, &text, false)?;
        }
        tx.execute(
            "UPDATE files SET fingerprint=?1,state='ready',error='' WHERE id=?2",
            params![fingerprint, id],
        )?;
        tx.commit()?;
        Ok(())
    }

    pub fn record(&self, path: &Path, app: &str, source: &str, at: i64) -> Result<()> {
        anyhow::ensure!(
            ["launcher", "terminal", "recent"].contains(&source),
            "Unknown activity source"
        );
        let id = self
            .db
            .query_row(
                "SELECT id FROM files WHERE path=?1",
                [path.to_string_lossy().as_ref()],
                |r| r.get::<_, i64>(0),
            )
            .optional()?;
        if let Some(id) = id {
            self.db.execute("INSERT INTO activity SELECT ?1,?2,?3,?4 WHERE NOT EXISTS(SELECT 1 FROM activity WHERE file_id=?1 AND at>?2-60 AND source=?4)", params![id,at,app.chars().take(128).collect::<String>(),source])?;
        }
        self.db
            .execute("DELETE FROM activity WHERE at<?1", [at - 90 * 86400])?;
        Ok(())
    }

    pub fn save_extraction(
        &mut self,
        id: i64,
        fingerprint: &str,
        chunks: &[Chunk],
        frames: &[(f64, String)],
        append: bool,
        next: Option<i64>,
    ) -> Result<()> {
        let tx = self.db.transaction()?;
        if !append {
            tx.execute("DELETE FROM chunks WHERE file_id=?1", [id])?;
            tx.execute("DELETE FROM frames WHERE file_id=?1", [id])?;
            tx.execute(
                "DELETE FROM file_lexemes WHERE file_id=?1 AND source=1",
                [id],
            )?;
        }
        for (text, time, space, vector) in chunks {
            tx.execute(
                "INSERT INTO chunks(file_id,text,timestamp,space,vector) VALUES(?1,?2,?3,?4,?5)",
                params![id, text, time, space, vector],
            )?;
            tx.execute(
                "INSERT INTO content(rowid,text) VALUES(?1,?2)",
                params![tx.last_insert_rowid(), text],
            )?;
            crate::lexical::index(&tx, id, 1, text, false)?;
        }
        for (time, image) in frames {
            tx.execute(
                "INSERT OR REPLACE INTO frames VALUES(?1,?2,?3)",
                params![id, time, image],
            )?;
        }
        tx.execute(
            "UPDATE files SET state=?1,offset=?2,fingerprint=?3,error='' WHERE id=?4",
            params![
                if next.is_some() { "pending" } else { "ready" },
                next.unwrap_or(0),
                fingerprint,
                id
            ],
        )?;
        tx.commit()?;
        Ok(())
    }

    pub fn hit(&self, id: i64) -> Result<Option<Hit>> {
        Ok(self
            .db
            .prepare_cached("SELECT id,path,name,kind FROM files WHERE id=?1")?
            .query_row([id], hit_row)
            .optional()?)
    }

    fn candidate_metadata(&self, ids: &[i64]) -> Result<HashMap<i64, Hit>> {
        if ids.is_empty() {
            return Ok(HashMap::new());
        }
        let mut statement = self.db.prepare_cached(
            "SELECT id,path,name,kind FROM files WHERE id IN (SELECT value FROM json_each(?1))",
        )?;
        let rows = statement.query_map([serde_json::to_string(ids)?], hit_row)?;
        let mut result = HashMap::new();
        for row in rows {
            let hit = row?;
            result.insert(hit.id, hit);
        }
        Ok(result)
    }

    /// Rank the matching passages once for the whole candidate set. Materialize
    /// only IDs/scores before the window, then load the same best eight passages
    /// per file that the former per-file FTS query returned.
    fn candidate_passages(&self, ids: &[i64], terms: &str) -> Result<HashMap<i64, String>> {
        if ids.is_empty() || terms.is_empty() {
            return Ok(HashMap::new());
        }
        let mut statement = self.db.prepare_cached(
            "WITH scored AS MATERIALIZED (
                SELECT chunks.id, chunks.file_id, content.rank AS relevance
                FROM content JOIN chunks ON chunks.id=content.rowid
                WHERE content MATCH ?1
                  AND chunks.file_id IN (SELECT value FROM json_each(?2))
             ), ranked AS (
                SELECT id,file_id,ROW_NUMBER() OVER (
                    PARTITION BY file_id ORDER BY relevance,id
                ) AS position FROM scored
             )
             SELECT ranked.file_id,chunks.text
             FROM ranked JOIN chunks ON chunks.id=ranked.id
             WHERE ranked.position<=8 ORDER BY ranked.file_id,ranked.position",
        )?;
        let rows = statement.query_map(params![terms, serde_json::to_string(ids)?], |r| {
            Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?))
        })?;
        let mut result = HashMap::<i64, String>::new();
        for row in rows {
            let (id, passage) = row?;
            let text = result.entry(id).or_default();
            text.extend(passage.chars().take(8192));
            text.push('\n');
        }
        Ok(result)
    }

    fn folder_metadata(&self, paths: &[String]) -> Result<HashMap<String, (Hit, bool)>> {
        if paths.is_empty() {
            return Ok(HashMap::new());
        }
        let mut statement = self.db.prepare_cached(
            "SELECT id,path,name,kind,project FROM files
             WHERE kind='folder' AND path IN (SELECT value FROM json_each(?1))",
        )?;
        let rows = statement.query_map([serde_json::to_string(paths)?], |r| {
            Ok((hit_row(r)?, r.get::<_, bool>(4)?))
        })?;
        let mut result = HashMap::new();
        for row in rows {
            let (hit, project) = row?;
            result.insert(hit.path.clone(), (hit, project));
        }
        Ok(result)
    }

    pub fn search(
        &self,
        q: &Query,
        semantic: &[(i64, f64, f64)],
        limit: usize,
    ) -> Result<Vec<Hit>> {
        if !semantic.is_empty() {
            return self.search_inner(q, semantic, limit, false);
        }
        let key = format!(
            "{}:{:?}:{:?}:{limit}",
            serde_json::to_string(q)?,
            q.scopes,
            q.source_roots
        );
        let revision = self.db.total_changes();
        {
            let mut cache = self.query_cache.borrow_mut();
            if cache.0 != revision {
                cache.0 = revision;
                cache.1.clear();
            }
            if let Some(hits) = cache.1.get(&key) {
                return Ok(hits.clone());
            }
        }
        let hits = self.search_inner(q, semantic, limit, false)?;
        let mut cache = self.query_cache.borrow_mut();
        if cache.1.len() >= 32 {
            cache.1.clear();
        }
        cache.1.insert(key, hits.clone());
        Ok(hits)
    }

    pub fn candidates(
        &self,
        q: &Query,
        semantic: &[(i64, f64, f64)],
        limit: usize,
    ) -> Result<Vec<Hit>> {
        self.search_inner(q, semantic, limit, true)
    }

    pub fn folder_scopes(&self, term: &str) -> Result<Vec<std::path::PathBuf>> {
        let mut names = query::variants(term);
        names.sort();
        names.dedup();
        let tokens = names
            .iter()
            .map(|w| format!("name: \"{w}\""))
            .collect::<Vec<_>>()
            .join(" OR ");
        if tokens.is_empty() {
            return Ok(vec![]);
        }
        let mut stmt=self.db.prepare("SELECT files.path,files.name FROM locations JOIN files ON files.id=locations.rowid WHERE locations MATCH ?1 AND files.kind='folder' ORDER BY rank LIMIT 512")?;
        let mut scopes = vec![];
        for row in stmt.query_map([tokens], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })? {
            let (path, name) = row?;
            if names.contains(&query::normalize(&name)) {
                scopes.push(std::path::PathBuf::from(path));
            }
        }
        // Very common names such as src do not establish an unambiguous scope.
        if scopes.len() > 16 {
            scopes.clear();
        }
        Ok(scopes)
    }

    fn application_configs(
        &self,
        app: &Hit,
        description: &str,
        similarity: f64,
    ) -> Result<Vec<Hit>> {
        let desktop = app
            .path
            .strip_prefix("app:")
            .unwrap_or(&app.path)
            .trim_end_matches(".desktop");
        let id = desktop.rsplit('.').next().unwrap_or(desktop);
        let name = query::normalize(&format!("{} {id}", app.name));
        let mut words: Vec<_> = name
            .split_whitespace()
            .filter(|w| w.chars().count() >= 3)
            .collect();
        words.sort();
        words.dedup();
        if words.is_empty() {
            return Ok(vec![]);
        }
        let terms = words
            .iter()
            .map(|w| format!("\"{w}\""))
            .collect::<Vec<_>>()
            .join(" OR ");
        let mut stmt = self.db.prepare("SELECT locations.rowid FROM locations JOIN files ON files.id=locations.rowid WHERE locations MATCH ?1 AND files.kind='config' ORDER BY rank LIMIT 100")?;
        let mut output = Vec::new();
        for id in stmt.query_map([terms], |r| r.get::<_, i64>(0))? {
            let Some(mut h) = self.hit(id?)? else {
                continue;
            };
            let parts: Vec<_> = Path::new(&h.path)
                .components()
                .filter_map(|c| c.as_os_str().to_str())
                .collect();
            let Some(directory) = parts
                .windows(2)
                .find(|p| p[0] == ".config")
                .map(|p| query::normalize(p[1]))
            else {
                continue;
            };
            if !words
                .iter()
                .any(|w| directory.split_whitespace().any(|p| p == *w))
            {
                continue;
            }
            let text = self
                .db
                .query_row(
                    "SELECT text FROM chunks WHERE file_id=?1 AND text<>'' ORDER BY id LIMIT 1",
                    [h.id],
                    |r| r.get::<_, String>(0),
                )
                .optional()?
                .unwrap_or_default();
            h.evidence = format!(
                "Application: {}. {}\n{}",
                app.name,
                description.chars().take(600).collect::<String>(),
                text.chars().take(1600).collect::<String>()
            );
            h.snippet = text.chars().take(240).collect();
            h.similarity = Some(similarity);
            h.application_context = Some(app.id);
            h.reason = "semantic".into();
            h.score = 0.03;
            output.push(h);
        }
        Ok(output)
    }

    fn search_inner(
        &self,
        q: &Query,
        semantic: &[(i64, f64, f64)],
        limit: usize,
        partial: bool,
    ) -> Result<Vec<Hit>> {
        let mut prepared = q.clone();
        self.prepare_query(&mut prepared)?;
        let q = &prepared;
        let mut hits: HashMap<i64, Hit> = HashMap::new();
        let scopes = serde_json::to_string(&q.scopes)?;
        let terms = q.fts_terms();
        // The postings intersection can combine independent name, parent and
        // content clues without enumerating every object below a project.
        let candidates = self.lexical_candidates(q)?;
        let mut metadata = self.candidate_metadata(&candidates)?;
        let mut lexical = Vec::new();
        let mut needs_content = Vec::new();
        for id in candidates {
            if let Some(h) = metadata.remove(&id) {
                if !q.matches_numbers(&h.path) {
                    continue;
                }
                let path_coverage = if q.text.is_empty() && !q.scopes.is_empty() {
                    1.0
                } else {
                    q.coverage(&h.path, "")
                };
                if path_coverage < 1.0 {
                    needs_content.push(id);
                }
                lexical.push((h, path_coverage));
            }
        }
        let mut passages = self.candidate_passages(&needs_content, &terms)?;
        for (mut h, path_coverage) in lexical {
            let text = passages.remove(&h.id).unwrap_or_default();
            let coverage = if path_coverage == 1.0 {
                1.0
            } else {
                q.coverage(&h.path, &text)
            };
            if coverage < 1.0 && !partial {
                continue;
            }
            h.lexical = coverage == 1.0;
            h.score = (if path_coverage == 1.0 { 0.16 } else { 0.14 }) * coverage * coverage;
            h.reason = if path_coverage == 1.0 {
                "name"
            } else {
                "content"
            }
            .into();
            h.snippet = text.chars().take(240).collect();
            h.evidence = text;
            hits.insert(h.id, h);
        }
        let tokens = grams(&q.text)
            .split_whitespace()
            .map(|w| format!("\"{w}\""))
            .collect::<Vec<_>>()
            .join(" OR ");
        if !tokens.is_empty() && q.text.split_whitespace().count() == 1 {
            let mut stmt = self
                .db
                .prepare("SELECT names.rowid FROM names JOIN files ON files.id=names.rowid WHERE names MATCH ?1 AND (?2='[]' OR EXISTS(SELECT 1 FROM json_each(?2) WHERE files.path>=value||'/' AND files.path<value||'0')) ORDER BY rank LIMIT 256")?;
            for row in stmt.query_map(params![tokens, scopes], |r| r.get::<_, i64>(0))? {
                if let Some(mut h) = self.hit(row?)? {
                    let score = query::name_score(&h.name, q);
                    if score > 0.0 {
                        h.score = 0.2 + score / 60.0;
                        h.reason = "name".into();
                        h.lexical = true;
                        hits.insert(h.id, h);
                    }
                }
            }
        }
        if !terms.is_empty() {
            let mut stmt = self.db.prepare(
                "SELECT locations.rowid FROM locations JOIN files ON files.id=locations.rowid
                WHERE locations MATCH ?1 AND (?2 IS NULL OR ?2='folder' OR files.kind=?2)
                AND (?3='[]' OR EXISTS(SELECT 1 FROM json_each(?3) WHERE files.path>=value||'/' AND files.path<value||'0'))
                ORDER BY bm25(locations,2.0,1.0) LIMIT 200",
            )?;
            for row in stmt.query_map(params![terms, q.kind, scopes], |r| r.get::<_, i64>(0))? {
                if let Some(mut h) = self.hit(row?)? {
                    let coverage = q.coverage(&h.path, "");
                    if coverage == 1.0
                        || (partial && coverage > 0.0)
                        || (!q.scopes.is_empty() && q.terms().len() >= 3 && coverage >= 0.66)
                    {
                        let path_weight = if h.kind == "folder" { 0.13 } else { 0.12 };
                        h.score = (path_weight * coverage * coverage)
                            .max(query::name_score(&h.name, q) / 60.0);
                        h.reason = "name".into();
                        h.lexical = coverage == 1.0;
                        hits.entry(h.id).or_insert(h);
                    }
                }
            }
        }
        let navigation = !partial
            && hits.values().any(|h| {
                (h.lexical && !h.evidence.is_empty())
                    || q.coverage(&h.path, "") == 1.0
                    || query::name_score(&h.name, q) >= 6.0
                    || (q.text.chars().count() <= 3 && query::name_score(&h.name, q) > 0.0)
            });
        if !terms.is_empty() && !navigation {
            let mut seen = std::collections::HashSet::new();
            let mut stmt=self.db.prepare("SELECT chunks.file_id,chunks.text,chunks.timestamp,snippet(content,0,'','',' … ',64) FROM content JOIN chunks ON chunks.id=content.rowid JOIN files ON files.id=chunks.file_id WHERE content MATCH ?1 AND (?2 IS NULL OR ?2='folder' OR files.kind=?2) AND (?3='[]' OR EXISTS(SELECT 1 FROM json_each(?3) WHERE files.path>=value||'/' AND files.path<value||'0')) ORDER BY rank LIMIT 200")?;
            for (rank, row) in stmt
                .query_map(params![terms, q.kind, scopes], |r| {
                    Ok((
                        r.get::<_, i64>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, Option<f64>>(2)?,
                        r.get::<_, String>(3)?,
                    ))
                })?
                .enumerate()
            {
                let (id, text, time, excerpt) = row?;
                if seen.contains(&id) {
                    continue;
                }
                if let Some(mut h) = self.hit(id)? {
                    let coverage = q.coverage(&h.path, &text);
                    if coverage < 1.0
                        && !partial
                        && (q.scopes.is_empty() || q.terms().len() < 3 || coverage < 0.66)
                    {
                        continue;
                    }
                    // A later passage can cover more of the query than the first FTS hit.
                    if coverage == 1.0 {
                        seen.insert(id);
                    }
                    h.score = 0.1 * coverage * coverage + 1.0 / (60.0 + rank as f64);
                    h.lexical = coverage == 1.0;
                    h.reason = "content".into();
                    h.snippet = excerpt.chars().take(240).collect();
                    h.evidence = excerpt.chars().take(2400).collect();
                    h.timestamp = time;
                    hits.entry(id)
                        .and_modify(|old| {
                            if h.score > old.score || old.evidence.is_empty() {
                                old.snippet = h.snippet.clone();
                                old.evidence = h.evidence.clone();
                                old.timestamp = time;
                            }
                            old.score = old.score.max(h.score);
                            old.lexical |= h.lexical;
                        })
                        .or_insert(h);
                }
            }
        }
        let mut seen = std::collections::HashSet::new();
        for (chunk, score, similarity) in semantic {
            let row = self
                .db
                .query_row(
                    "SELECT file_id,text,timestamp,space FROM chunks WHERE id=?1",
                    [chunk],
                    |r| {
                        Ok((
                            r.get::<_, i64>(0)?,
                            r.get::<_, String>(1)?,
                            r.get::<_, Option<f64>>(2)?,
                            r.get::<_, Option<String>>(3)?,
                        ))
                    },
                )
                .optional()?;
            if let Some((id, text, time, space)) = row {
                if !seen.insert((id, space.clone())) {
                    continue;
                }
                if let Some(mut h) = self.hit(id)? {
                    if h.kind == "app" && q.kind.as_deref() == Some("config") {
                        for candidate in self.application_configs(&h, &text, *similarity)? {
                            hits.entry(candidate.id)
                                .and_modify(|old| {
                                    old.evidence = candidate.evidence.clone();
                                    old.application_context = candidate.application_context;
                                    old.similarity =
                                        Some(old.similarity.unwrap_or(0.0).max(*similarity));
                                    old.score += candidate.score;
                                })
                                .or_insert(candidate);
                        }
                        continue;
                    }
                    h.score = *score;
                    h.reason = if space.as_deref() == Some("visual") {
                        "visual"
                    } else {
                        "semantic"
                    }
                    .into();
                    h.snippet = text.chars().take(240).collect();
                    h.evidence = text.chars().take(2400).collect();
                    h.lexical = q.coverage(&h.path, &text) == 1.0;
                    h.similarity = (space.as_deref() == Some("text")).then_some(*similarity);
                    h.timestamp = time;
                    hits.entry(id)
                        .and_modify(|old| {
                            old.score += h.score;
                            if old.evidence.is_empty() {
                                old.evidence = h.evidence.clone();
                            }
                            old.lexical |= h.lexical;
                            if let Some(similarity) = h.similarity {
                                old.similarity =
                                    Some(old.similarity.unwrap_or(0.0).max(similarity));
                            }
                            if h.reason == "visual" && old.reason == "semantic" {
                                old.timestamp = h.timestamp;
                                old.snippet = h.snippet.clone();
                                old.reason = h.reason.clone();
                            } else if old.timestamp.is_none() {
                                old.timestamp = h.timestamp;
                            }
                        })
                        .or_insert(h);
                }
            }
        }
        if let Some(extension) = &q.extension {
            let suffix = format!(".{extension}");
            hits.retain(|_, h| h.path.to_lowercase().ends_with(&suffix));
            if q.text.is_empty() {
                let mut stmt = self.db.prepare(
                    "SELECT id FROM files WHERE lower(path) LIKE ?1 ORDER BY mtime DESC LIMIT 200",
                )?;
                for id in stmt.query_map([format!("%{suffix}")], |r| r.get::<_, i64>(0))? {
                    if let Some(mut h) = self.hit(id?)? {
                        h.lexical = true;
                        hits.insert(h.id, h);
                    }
                }
            }
        }
        if let Some(content_kind) = &q.content_kind {
            if q.kind.as_deref() == Some("folder") {
                hits.retain(|_, h| &h.kind == content_kind);
            }
        }
        // Folder intent promotes matching descendants; evidence stays attached to the result.
        if q.kind.as_deref() == Some("folder") {
            let ancestors = |h: &Hit| {
                let path = Path::new(&h.path);
                let path = if h.kind == "folder" {
                    path
                } else {
                    path.parent().unwrap_or(path)
                };
                path.ancestors()
                    .take(8)
                    .map(|p| p.to_string_lossy().into_owned())
                    .collect::<Vec<_>>()
            };
            let mut paths = std::collections::BTreeSet::new();
            for h in hits.values() {
                paths.extend(ancestors(h));
            }
            let metadata = self.folder_metadata(&paths.into_iter().collect::<Vec<_>>())?;
            let mut winners = HashMap::<i64, (&Hit, &Hit, f64)>::new();
            for h in hits.values() {
                for (depth, ancestor) in ancestors(h).iter().enumerate() {
                    if let Some((folder, project)) = metadata.get(ancestor) {
                        let score =
                            h.score / (1.0 + 0.3 * depth as f64) * if *project { 1.5 } else { 1.0 };
                        if winners.get(&folder.id).is_none_or(|old| score > old.2) {
                            winners.insert(folder.id, (folder, h, score));
                        }
                    }
                }
            }
            // Clone large passages only once per winning folder, not for every
            // descendant/ancestor pair that is immediately discarded again.
            hits = winners
                .into_iter()
                .map(|(id, (template, source, score))| {
                    let mut folder = template.clone();
                    folder.score = score;
                    folder.reason = if id == source.id {
                        source.reason.clone()
                    } else {
                        "project".into()
                    };
                    folder.snippet = source.snippet.clone();
                    folder.evidence = source.evidence.clone();
                    folder.evidence_path = source.path.clone();
                    folder.lexical = source.lexical;
                    folder.similarity = source.similarity;
                    (id, folder)
                })
                .collect();
        }
        if q.text.is_empty() && q.since.is_some() {
            for (id, _) in self.paths()? {
                if let Some(h) = self.hit(id)? {
                    hits.entry(id).or_insert(h);
                }
            }
        }
        let mut output = Vec::new();
        let mut evidence_by_source = HashMap::new();
        for mut h in hits.into_values() {
            if !q.matches_numbers(&h.path) {
                continue;
            }
            if !q.scopes.is_empty()
                && !q
                    .scopes
                    .iter()
                    .any(|root| Path::new(&h.path).starts_with(root))
            {
                continue;
            }
            if q.kind.as_ref().is_some_and(|k| {
                k != &h.kind
                    && !(k == "file" && matches!(h.kind.as_str(), "file" | "config" | "name"))
            }) {
                continue;
            }
            if let Some(since) = q.since {
                if q.activity {
                    let activity: Option<i64> = if h.kind == "folder" {
                        self.db.query_row("SELECT max(a.at) FROM activity a JOIN files f ON f.id=a.file_id WHERE (f.id=?1 OR substr(f.path,1,length(?2)+1)=?2||'/') AND a.at>=?3 AND a.at<?4",params![h.id,h.path,since,q.until],|r|r.get(0))?
                    } else {
                        self.db.query_row(
                            "SELECT max(at) FROM activity WHERE file_id=?1 AND at>=?2 AND at<?3",
                            params![h.id, since, q.until],
                            |r| r.get(0),
                        )?
                    };
                    if activity.is_none() {
                        continue;
                    }
                    h.activity_at = activity;
                } else {
                    let at: i64 =
                        self.db
                            .query_row("SELECT mtime FROM files WHERE id=?1", [h.id], |r| {
                                r.get(0)
                            })?;
                    if at < since || q.until.is_some_and(|end| at >= end) {
                        continue;
                    }
                    h.reason = "modified".into();
                }
            }
            let evidence = evidence_by_source
                .entry(h.evidence_path.clone())
                .or_insert_with(|| q.evidence(&h.evidence_path, &h.evidence));
            h.matched_terms = evidence.matched.clone();
            h.unmatched_terms = evidence.missing.clone();
            h.corrections = evidence.corrections.clone();
            h.partial = !h.unmatched_terms.is_empty()
                && !matches!(h.reason.as_str(), "semantic" | "visual");
            // Keep bounded evidence in the query cache and neural candidate set;
            // explanations above were computed from the complete retrieved text.
            h.evidence = h.evidence.chars().take(2400).collect();
            if h.partial {
                h.score *= 0.35;
            }
            if !h.corrections.is_empty() {
                h.score *= 0.95;
            }
            output.push(h);
        }
        output.sort_by(|a, b| {
            b.score
                .total_cmp(&a.score)
                .then_with(|| a.path.cmp(&b.path))
        });
        let limit = limit.min(50);
        if partial {
            // Reserve half the reranker budget for vector retrieval. Otherwise a
            // frequent word in many text files can eliminate every neural candidate.
            let mut semantic: Vec<_> = output.iter().filter(|h| h.similarity.is_some()).collect();
            semantic.sort_by(|a, b| {
                b.similarity
                    .unwrap()
                    .total_cmp(&a.similarity.unwrap())
                    .then_with(|| {
                        Path::new(&a.path)
                            .components()
                            .count()
                            .cmp(&Path::new(&b.path).components().count())
                    })
                    .then_with(|| a.path.cmp(&b.path))
            });
            let mut applications = std::collections::HashSet::new();
            let mut chosen: std::collections::HashSet<_> = semantic
                .iter()
                .filter(|h| {
                    h.application_context
                        .is_some_and(|app| applications.insert(app))
                })
                .take(limit / 4)
                .map(|h| h.id)
                .collect();
            for h in semantic {
                if chosen.len() >= limit / 2 {
                    break;
                }
                chosen.insert(h.id);
            }
            for h in &output {
                if chosen.len() >= limit {
                    break;
                }
                chosen.insert(h.id);
            }
            output.retain(|h| chosen.contains(&h.id));
        } else {
            output.truncate(limit);
        }
        for h in &mut output {
            if h.evidence.is_empty() {
                h.evidence = self
                    .db
                    .query_row(
                        "SELECT text FROM chunks WHERE file_id=?1 AND text<>'' ORDER BY id LIMIT 1",
                        [h.id],
                        |r| r.get::<_, String>(0),
                    )
                    .optional()?
                    .unwrap_or_default()
                    .chars()
                    .take(2400)
                    .collect();
            }
            h.preview = self
                .db
                .query_row(
                    "SELECT image FROM frames WHERE file_id=?1 ORDER BY abs(at-?2) LIMIT 1",
                    params![h.id, h.timestamp.unwrap_or(0.0)],
                    |r| r.get::<_, String>(0),
                )
                .optional()?
                .map(|s| format!("data:image/png;base64,{s}"));
        }
        Ok(output)
    }
}

#[cfg(test)]
#[path = "store_batch_tests.rs"]
mod batch_tests;

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn extraction_upgrade_queues_once_and_preserves_searchable_content() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("index.db");
        let mut db = Store::open(&path, &[42; 32]).unwrap();
        let id = db
            .upsert(&dir.path().join("notes.md"), "file", "notes.md", 1, 1, 1, 1)
            .unwrap();
        db.replace_chunks(
            id,
            "old-hash",
            &[("word embeddings".into(), None, None, None)],
        )
        .unwrap();
        db.db
            .execute("DELETE FROM settings WHERE key='extraction_revision'", [])
            .unwrap();
        drop(db);
        let db = Store::open(&path, &[42; 32]).unwrap();
        let row: (String, String) = db
            .db
            .query_row(
                "SELECT state,fingerprint FROM files WHERE id=?1",
                [id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .unwrap();
        assert_eq!(row, ("pending".into(), "old-hash".into()));
        assert_eq!(
            db.search(
                &Query::parse("word embeddings", chrono::Local::now()),
                &[],
                10
            )
            .unwrap()[0]
                .id,
            id
        );
        db.db
            .execute("UPDATE files SET state='ready' WHERE id=?1", [id])
            .unwrap();
        drop(db);
        let db = Store::open(&path, &[42; 32]).unwrap();
        assert_eq!(
            db.db
                .query_row("SELECT state FROM files WHERE id=?1", [id], |r| r
                    .get::<_, String>(0))
                .unwrap(),
            "ready"
        );
    }
    #[test]
    fn search_combines_path_and_passage_without_unrelated_alias_hits() {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("index.db");
        let mut store = Store::open(&db, &[42; 32]).unwrap();
        let mut ids = vec![];
        for (index, (path, text)) in [
            (
                "SHAD/DL/03.md",
                "Convolutional layers learn spatial filters for image classification.",
            ),
            ("Downloads/DL_movie.torrent", "movie download"),
            ("SHAD/DL/02.md", "Gradient descent and optimizers."),
            ("other/03.md", "Convolutional layers learn spatial filters."),
        ]
        .iter()
        .enumerate()
        {
            let path = dir.path().join(path);
            let id = store
                .upsert(
                    &path,
                    "file",
                    path.file_name().unwrap().to_str().unwrap(),
                    1,
                    1,
                    1,
                    index as u64 + 1,
                )
                .unwrap();
            store
                .replace_chunks(id, "fixture", &[(text.to_string(), None, None, None)])
                .unwrap();
            ids.push(id);
        }
        let q = Query::parse("shad dl conv layer", chrono::Local::now());
        let hits = store.search(&q, &[], 10).unwrap();
        assert_eq!(hits.iter().map(|h| h.id).collect::<Vec<_>>(), vec![ids[0]]);
        assert!(store
            .search(
                &Query::parse("missingproject conv layer", chrono::Local::now()),
                &[],
                10
            )
            .unwrap()
            .is_empty());
        // Upgrade an existing metadata catalogue without re-extracting any content.
        store
            .db
            .execute_batch("DROP TABLE locations; PRAGMA user_version=1;")
            .unwrap();
        drop(store);
        let store = Store::open(&db, &[42; 32]).unwrap();
        assert_eq!(store.search(&q, &[], 10).unwrap()[0].id, ids[0]);
        store
            .db
            .execute("DELETE FROM files WHERE id=?1", [ids[0]])
            .unwrap();
        assert!(store.search(&q, &[], 10).unwrap().is_empty());
    }
    #[test]
    fn pruning_old_generated_entries_removes_all_derived_data_and_keeps_sources() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("project");
        std::fs::create_dir(&root).unwrap();
        let config = Config {
            roots: vec![root.clone()],
            dataset_folders: vec![root.join("Dataset")],
            ..Config::default()
        };
        let path = dir.path().join("index.db");
        let mut store = Store::open(&path, &[42; 32]).unwrap();
        store.set_config(&config).unwrap();
        for (index, relative) in [
            "Dataset/notes.md",
            ".venv/package.py",
            "node_modules/index.js",
            ".next/cache.json",
            "tools-env/lib/library.py",
            "generated-cache/old.txt",
            "data-output/old.csv",
            "samples/old.npy",
            "Dataset/train/image.jpg",
        ]
        .iter()
        .enumerate()
        {
            let file = root.join(relative);
            std::fs::create_dir_all(file.parent().unwrap()).unwrap();
            std::fs::write(&file, "fixture").unwrap();
            // Simulate a catalogue from a previous release, bypassing discovery.
            let id = store
                .upsert(&file, "file", relative, 0, 7, 1, index as u64 + 1)
                .unwrap();
            store
                .replace_chunks(
                    id,
                    "fixture",
                    &[("indexed content".into(), None, None, None)],
                )
                .unwrap();
            store
                .db
                .execute("INSERT INTO frames VALUES(?1,0,'preview')", [id])
                .unwrap();
            store.record(&file, "editor", "launcher", 10).unwrap();
        }
        store
            .db
            .execute("INSERT INTO ann VALUES('text',X'01')", [])
            .unwrap();
        std::fs::write(root.join("tools-env/pyvenv.cfg"), "home = /usr/bin").unwrap();
        std::fs::write(root.join(".gitignore"), "/generated-cache/\n").unwrap();
        std::fs::write(root.join(".ignore"), "/data-output/\n").unwrap();
        for n in 0..999 {
            std::fs::write(root.join(format!("samples/{n}.npy")), "array").unwrap();
        }
        drop(store);
        let mut store = Store::open(&path, &[42; 32]).unwrap();
        assert_eq!(store.prune_excluded(&store.config().unwrap()).unwrap(), 8);
        assert_eq!(store.paths().unwrap().len(), 1);
        assert_eq!(
            store.paths().unwrap()[0].1,
            root.join("Dataset/notes.md").to_string_lossy()
        );
        for table in ["files", "names", "chunks", "content", "frames", "activity"] {
            let count: i64 = store
                .db
                .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get(0))
                .unwrap();
            assert_eq!(count, 1, "{table}");
        }
        assert_eq!(
            store
                .db
                .query_row("SELECT count(*) FROM ann", [], |r| r.get::<_, i64>(0))
                .unwrap(),
            0
        );
        assert_eq!(
            store.prune_excluded(&config).unwrap(),
            0,
            "reconciliation is idempotent"
        );
    }

    #[test]
    fn encrypted_index_search_history_and_exclusion() {
        let dir = tempfile::tempdir().unwrap();
        let db = dir.path().join("index.db");
        let key = [42u8; 32];
        let mut s = Store::open(&db, &key).unwrap();
        let project = dir.path().join("SHAD");
        std::fs::create_dir(&project).unwrap();
        let folder = s.upsert(&project, "folder", "SHAD", 0, 0, 1, 1).unwrap();
        let file = project.join("lesson.ipynb");
        std::fs::write(&file, "example").unwrap();
        let id = s.upsert(&file, "file", "lesson.ipynb", 0, 1, 1, 2).unwrap();
        s.replace_chunks(
            id,
            "v1",
            &[(
                "Deep learning neural networks privatecanary42".into(),
                None,
                None,
                None,
            )],
        )
        .unwrap();
        let q = Query::parse("папка DL", chrono::Local::now());
        assert_eq!(s.search(&q, &[], 10).unwrap()[0].id, folder);
        let q = Query::parse("шаад", chrono::Local::now());
        assert_eq!(s.search(&q, &[], 10).unwrap()[0].id, folder);
        let q = Query::parse("папка где я делал DL сегодня", chrono::Local::now());
        assert!(s.search(&q, &[], 10).unwrap().is_empty());
        s.record(
            &file,
            "terminal",
            "terminal",
            chrono::Local::now().timestamp(),
        )
        .unwrap();
        assert_eq!(s.search(&q, &[], 10).unwrap()[0].id, folder);
        s.db.execute_batch("PRAGMA wal_checkpoint(TRUNCATE)")
            .unwrap();
        assert!(!std::fs::read(&db)
            .unwrap()
            .windows(15)
            .any(|w| w == b"privatecanary42"));
        assert!(Store::open(&db, &[43; 32]).is_err());
        s.set_config(&Config::default()).unwrap();
        assert!(s.search(&q, &[], 10).unwrap().is_empty());
    }
}
