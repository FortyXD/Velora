//! Bounded spelling repair over the encrypted index, never over the filesystem.
//! One-deletion signatures support a substitution, insertion/deletion or adjacent
//! transposition. Numbers are indexed literally and are never spelling-corrected.
use crate::{
    query::{self, Query},
    store::Store,
};
use anyhow::Result;
use rusqlite::{params, Connection, OptionalExtension};
use std::collections::BTreeSet;

pub const CANDIDATES: usize = 256;

fn signatures(word: &str) -> BTreeSet<String> {
    let mut keys = BTreeSet::new();
    for form in [word.to_owned(), query::transliterate(word)] {
        let chars: Vec<_> = form.chars().collect();
        if !(3..=32).contains(&chars.len()) || !chars.iter().all(|c| c.is_alphabetic()) {
            continue;
        }
        keys.insert(form);
        for removed in 0..chars.len() {
            keys.insert(
                chars
                    .iter()
                    .enumerate()
                    .filter_map(|(i, c)| (i != removed).then_some(*c))
                    .collect(),
            );
        }
    }
    keys
}

pub fn schema(db: &Connection) -> Result<()> {
    db.execute_batch("CREATE TABLE IF NOT EXISTS lexemes(id INTEGER PRIMARY KEY,word TEXT NOT NULL UNIQUE);
        CREATE TABLE IF NOT EXISTS lexeme_keys(signature TEXT NOT NULL,lexeme_id INTEGER NOT NULL REFERENCES lexemes(id) ON DELETE CASCADE,PRIMARY KEY(signature,lexeme_id)) WITHOUT ROWID;
        CREATE INDEX IF NOT EXISTS lexeme_key_owner ON lexeme_keys(lexeme_id);
        CREATE TABLE IF NOT EXISTS file_lexemes(file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,source INTEGER NOT NULL,lexeme_id INTEGER NOT NULL REFERENCES lexemes(id),PRIMARY KEY(file_id,source,lexeme_id)) WITHOUT ROWID;
        CREATE INDEX IF NOT EXISTS lexeme_files ON file_lexemes(lexeme_id,file_id);
        CREATE TRIGGER IF NOT EXISTS lexeme_release AFTER DELETE ON file_lexemes BEGIN
            DELETE FROM lexemes WHERE id=old.lexeme_id AND NOT EXISTS(SELECT 1 FROM file_lexemes WHERE lexeme_id=old.lexeme_id); END;
        CREATE TRIGGER IF NOT EXISTS chunk_lexeme_delete AFTER DELETE ON chunks BEGIN
            DELETE FROM file_lexemes WHERE file_id=old.file_id AND source=1; END;
        CREATE INDEX IF NOT EXISTS activity_expiration ON activity(at);")?;
    Ok(())
}

/// All inputs must already have passed the content scrubber. A file contributes
/// at most 4096 distinct vocabulary words; ordinary FTS remains available beyond
/// that budget. Deleting/excluding a file also removes its unshared vocabulary.
pub fn index(db: &Connection, file: i64, source: i64, text: &str, replace: bool) -> Result<()> {
    if replace {
        db.execute(
            "DELETE FROM file_lexemes WHERE file_id=?1 AND source=?2",
            params![file, source],
        )?;
    }
    let mut count: usize = db.query_row(
        "SELECT count(*) FROM file_lexemes WHERE file_id=?1 AND source=?2",
        params![file, source],
        |r| r.get(0),
    )?;
    if count >= 4096 {
        return Ok(());
    }
    let words: BTreeSet<_> = query::identifier_words(text)
        .into_iter()
        .filter(|w| !w.is_empty() && w.chars().count() <= 64)
        .take(16384)
        .collect();
    for word in words.into_iter().take(4096) {
        if count >= 4096 {
            break;
        }
        let existing: Option<i64> = db
            .prepare_cached("SELECT id FROM lexemes WHERE word=?1")?
            .query_row([&word], |r| r.get(0))
            .optional()?;
        let id = if let Some(id) = existing {
            id
        } else {
            db.prepare_cached("INSERT INTO lexemes(word) VALUES(?1)")?
                .execute([&word])?;
            let id = db.last_insert_rowid();
            for key in signatures(&word) {
                db.prepare_cached("INSERT INTO lexeme_keys VALUES(?1,?2)")?
                    .execute(params![key, id])?;
            }
            id
        };
        count += db
            .prepare_cached("INSERT OR IGNORE INTO file_lexemes VALUES(?1,?2,?3)")?
            .execute(params![file, source, id])?;
    }
    Ok(())
}

fn typo_match(word: &str, term: &str) -> bool {
    let chars = term.chars().count();
    if !(3..=32).contains(&chars) || !term.chars().all(char::is_alphabetic) {
        return false;
    }
    let word = query::transliterate(word);
    let term = query::transliterate(term);
    if chars >= 4 && query::distance(&word, &term) <= 1 {
        return true;
    }
    let a: Vec<_> = word.chars().collect();
    let b: Vec<_> = term.chars().collect();
    if a.len() != b.len() {
        return false;
    }
    let different: Vec<_> = a
        .iter()
        .zip(&b)
        .enumerate()
        .filter_map(|(i, (a, b))| (a != b).then_some(i))
        .collect();
    different.len() == 2
        && different[1] == different[0] + 1
        && a[different[0]] == b[different[1]]
        && a[different[1]] == b[different[0]]
}

fn script(word: &str) -> i64 {
    if word.chars().all(|c| c.is_ascii_lowercase()) {
        1
    } else if word.chars().all(|c| ('а'..='я').contains(&c)) {
        2
    } else {
        0
    }
}

impl Store {
    pub fn prepare_query(&self, query: &mut Query) -> Result<()> {
        if query.prepared {
            return Ok(());
        }
        // Repair only the user's spelling, never all generated alias/layout
        // variants: compounded repairs make short identifiers dangerously broad.
        for (index, word) in query.labels().iter().take(16).enumerate() {
            let revision = self.db.total_changes();
            let cached = {
                let mut cache = self.spelling_cache.borrow_mut();
                if cache.0 != revision {
                    cache.0 = revision;
                    cache.1.clear();
                }
                cache.1.get(word).cloned()
            };
            if let Some(candidates) = cached {
                for candidate in candidates {
                    query.add_alternative(index, candidate);
                }
                continue;
            }
            let keys = signatures(word);
            if keys.is_empty() {
                continue;
            }
            let keys = serde_json::to_string(&keys)?;
            // Short translated words must not consume the repair budget before
            // same-script identifiers (hupr -> hypr, not upr -> упр). The cap is
            // applied after script/length prioritization, never insertion order.
            let mut stmt = self.db.prepare_cached("SELECT DISTINCT l.id,l.word FROM lexeme_keys k JOIN lexemes l ON l.id=k.lexeme_id WHERE k.signature IN (SELECT value FROM json_each(?1)) ORDER BY CASE WHEN (?2=1 AND l.word NOT GLOB '*[^a-z]*') OR (?2=2 AND l.word NOT GLOB '*[^а-я]*') THEN 0 ELSE 1 END,abs(length(l.word)-?3),l.word LIMIT 64")?;
            let matches = stmt
                .query_map(params![keys, script(word), word.chars().count()], |r| {
                    Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?))
                })?
                .collect::<rusqlite::Result<Vec<_>>>()?
                .into_iter()
                .filter(|(_, candidate)| candidate == word || typo_match(candidate, word))
                .collect::<Vec<_>>();
            let ids: Vec<_> = matches.iter().map(|(id, _)| *id).collect();
            let metadata: BTreeSet<i64> = self.db.prepare_cached("SELECT DISTINCT lexeme_id FROM file_lexemes WHERE source=0 AND lexeme_id IN (SELECT value FROM json_each(?1))")?
                .query_map([serde_json::to_string(&ids)?],|r|r.get(0))?.collect::<rusqlite::Result<_>>()?;
            let has_local_name = matches
                .iter()
                .any(|(id, candidate)| metadata.contains(id) && script(candidate) == script(word));
            let mut ranked: Vec<_> = matches
                .into_iter()
                .filter(|(id, candidate)| {
                    candidate != word
                        && (!has_local_name
                            || metadata.contains(id)
                            || script(candidate) == script(word))
                })
                .map(|(id, candidate)| {
                    (
                        !metadata.contains(&id),
                        script(&candidate) != script(word),
                        candidate.chars().count().abs_diff(word.chars().count()),
                        query::distance(
                            &query::transliterate(&candidate),
                            &query::transliterate(word),
                        ),
                        candidate,
                    )
                })
                .collect();
            ranked.sort();
            let candidates: Vec<_> = ranked
                .into_iter()
                .take(4)
                .map(|(_, _, _, _, candidate)| candidate)
                .collect();
            for candidate in &candidates {
                query.add_alternative(index, candidate.clone());
            }
            let mut cache = self.spelling_cache.borrow_mut();
            if cache.1.len() >= 128 {
                cache.1.clear();
            }
            cache.1.insert(word.clone(), candidates);
        }
        query.prepared = true;
        Ok(())
    }

    /// Intersect indexed postings before loading files/content. The smallest
    /// posting list seeds retrieval; exact numbers and every clue stay present.
    pub fn lexical_candidates(&self, q: &Query) -> Result<Vec<i64>> {
        if q.terms().is_empty() && !q.scopes.is_empty() {
            return Ok(self
                .db
                .prepare_cached(
                    "SELECT id FROM files WHERE path IN (SELECT value FROM json_each(?1)) LIMIT 32",
                )?
                .query_map([serde_json::to_string(&q.scopes)?], |r| r.get(0))?
                .collect::<rusqlite::Result<Vec<_>>>()?);
        }
        let mut groups = Vec::<Vec<i64>>::new();
        for alternatives in q.terms().iter().take(16) {
            let mut exact = Vec::new();
            let mut prefixes = Vec::new();
            for word in alternatives.iter().filter(|w| !w.contains(' ')).take(24) {
                let prefix = word.chars().count() >= 3 && !word.chars().all(|c| c.is_ascii_digit());
                let mut stmt = self.db.prepare_cached(
                    "SELECT id,word FROM lexemes WHERE word>=?1 AND word<?2 ORDER BY word LIMIT 32",
                )?;
                let end = if prefix {
                    format!("{word}\u{10ffff}")
                } else {
                    format!("{word}\0")
                };
                let mut expanded = Vec::new();
                for row in stmt.query_map(params![word, end], |r| {
                    Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?))
                })? {
                    let (id, candidate) = row?;
                    if &candidate == word {
                        exact.push(id);
                    } else {
                        expanded.push(id);
                    }
                }
                prefixes.push(expanded);
            }
            // Reserve every exact alternative before prefix expansions. A low
            // insertion ID or a noisy prefix must not evict an exact repair.
            let mut seen = BTreeSet::new();
            let mut ids = Vec::new();
            for id in exact {
                if seen.insert(id) {
                    ids.push(id);
                }
            }
            'prefixes: for rank in 0..32 {
                for expansion in &prefixes {
                    if ids.len() >= 64 {
                        break 'prefixes;
                    }
                    if let Some(&id) = expansion.get(rank) {
                        if seen.insert(id) {
                            ids.push(id);
                        }
                    }
                }
            }
            // A phrase expansion is handled by the existing passage FTS path.
            if ids.is_empty() {
                return Ok(vec![]);
            }
            groups.push(ids);
        }
        if groups.is_empty() {
            return Ok(vec![]);
        }
        let mut costs = Vec::new();
        for (i, ids) in groups.iter().enumerate() {
            let count: i64 = self.db.query_row("SELECT count(*) FROM (SELECT 1 FROM file_lexemes WHERE lexeme_id IN(SELECT value FROM json_each(?1)) LIMIT 1024)", [serde_json::to_string(ids)?], |r| r.get(0))?;
            costs.push((count, i));
        }
        costs.sort_unstable();
        let seed = costs[0].1;
        let mut sql = String::from("SELECT DISTINCT f.id FROM file_lexemes seed JOIN files f ON f.id=seed.file_id WHERE seed.lexeme_id IN (SELECT value FROM json_each(?1,?2))");
        for i in 0..groups.len() {
            if i != seed {
                sql.push_str(&format!(" AND EXISTS(SELECT 1 FROM file_lexemes m WHERE m.file_id=f.id AND m.lexeme_id IN(SELECT value FROM json_each(?1,'$[{i}]')))"));
            }
        }
        sql.push_str(" AND (?3='[]' OR EXISTS(SELECT 1 FROM json_each(?3) WHERE f.path=value OR (f.path>=value||'/' AND f.path<value||'0'))) LIMIT ?4");
        let result = self
            .db
            .prepare_cached(&sql)?
            .query_map(
                params![
                    serde_json::to_string(&groups)?,
                    format!("$[{seed}]"),
                    serde_json::to_string(&q.scopes)?,
                    CANDIDATES
                ],
                |r| r.get(0),
            )?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(result)
    }
}
