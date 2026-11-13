use crate::{
    config::{self, Config, SourceFilter},
    query::Query,
    store::{Hit, Store},
    worker::Worker,
};
use anyhow::{Context, Result};
use base64::Engine as _;
use notify::Watcher;
use rusqlite::{params, OptionalExtension};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeSet, HashMap},
    io::Read,
    os::unix::fs::MetadataExt,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};
use tokio::sync::{watch, Notify};
use usearch::{Index, IndexOptions, MetricKind, ScalarKind};

// Dropping an aborted query also stops its CPU-side ANN construction.
struct SearchLifetime(Arc<AtomicBool>, Arc<Engine>);
impl Drop for SearchLifetime {
    fn drop(&mut self) {
        self.0.store(true, Ordering::Relaxed);
        {
            let mut state = self.1.state.lock().unwrap();
            state.active_searches = state.active_searches.saturating_sub(1);
        }
        self.1.wake.notify_one();
    }
}

pub struct State {
    pub store: Option<Store>,
    opening_generation: Option<u64>,
    pub session_locked: bool,
    pub config: Config,
    pub generation: u64,
    pub battery: bool,
    pub idle: bool,
    pub pending: BTreeSet<PathBuf>,
    pub pending_recent: bool,
    pub problem: String,
    pub budget_blocked: bool,
    pub last_query: Instant,
    pub active_searches: usize,
    pub assistant_busy: bool,
    pub query_cache: HashMap<String, Value>,
    pub last_model_use: Instant,
    pub ann: HashMap<String, Arc<Index>>,
    pub revision: u64,
    pub watched: Vec<PathBuf>,
    pub watch_dirs: BTreeSet<PathBuf>,
    pub watches_dirty: bool,
    pub scanning: bool,
    pub current_file: Option<(i64, String, Instant)>,
}

pub struct Engine {
    pub state: Mutex<State>,
    pub worker: tokio::sync::Mutex<Option<Worker>>,
    pub cancel: watch::Sender<u64>,
    pub wake: Notify,
    opening_gate: Arc<tokio::sync::Mutex<()>>,
}

impl Engine {
    pub fn new() -> Arc<Self> {
        let (cancel, _) = watch::channel(0);
        Arc::new(Self {
            state: Mutex::new(State {
                store: None,
                opening_generation: None,
                session_locked: true,
                config: Config::default(),
                generation: 0,
                battery: true,
                idle: false,
                pending: BTreeSet::new(),
                pending_recent: false,
                problem: String::new(),
                budget_blocked: false,
                last_query: Instant::now(),
                active_searches: 0,
                assistant_busy: false,
                query_cache: HashMap::new(),
                last_model_use: Instant::now(),
                ann: HashMap::new(),
                revision: 0,
                watched: vec![],
                watch_dirs: BTreeSet::new(),
                watches_dirty: false,
                scanning: false,
                current_file: None,
            }),
            worker: tokio::sync::Mutex::new(None),
            cancel,
            wake: Notify::new(),
            opening_gate: Arc::new(tokio::sync::Mutex::new(())),
        })
    }

    pub fn lock(&self) {
        let mut s = self.state.lock().unwrap();
        s.session_locked = true;
        s.generation += 1;
        self.cancel.send_replace(s.generation);
        s.store = None;
        s.opening_generation = None;
        s.current_file = None;
        s.ann.clear();
        s.query_cache.clear();
        s.assistant_busy = false;
        s.config = Config::default();
        s.pending.clear();
        s.problem.clear();
        s.budget_blocked = false;
        s.watch_dirs.clear();
        s.watches_dirty = true;
        self.wake.notify_one();
    }

    /// A control acknowledgement must not wait for schema migration: the same
    /// shell connection must remain able to deliver lock/cancel/status events.
    pub fn schedule_unlock(self: &Arc<Self>) {
        let generation = {
            let mut s = self.state.lock().unwrap();
            if s.store.is_some() || s.opening_generation == Some(s.generation) || s.session_locked {
                return;
            }
            s.opening_generation = Some(s.generation);
            s.problem.clear();
            s.generation
        };
        let engine = self.clone();
        tokio::spawn(async move {
            let result = engine.open_generation(generation).await;
            let mut s = engine.state.lock().unwrap();
            if s.opening_generation == Some(generation) {
                s.opening_generation = None;
                if s.generation == generation {
                    if let Err(error) = result {
                        s.problem = error.to_string();
                    }
                }
            }
            drop(s);
            engine.wake.notify_one();
        });
    }

    async fn open_generation(self: &Arc<Self>, generation: u64) -> Result<()> {
        // Move the owned gate into the blocking worker, so cancelling an async
        // waiter cannot start a second migration against the same database.
        let gate = self.opening_gate.clone().lock_owned().await;
        {
            let s = self.state.lock().unwrap();
            anyhow::ensure!(s.generation == generation && !s.session_locked, "Cancelled");
            if s.store.is_some() {
                return Ok(());
            }
        }
        let path = crate::data_dir().join("index.db");
        let key = crate::secret::key(!path.exists()).await?;
        let cancellation = self.cancel.subscribe();
        let (store, config) = tokio::task::spawn_blocking(move || -> Result<_> {
            let _gate = gate;
            let cancelled = || *cancellation.borrow() != generation;
            let mut store = Store::open_cancellable(&path, &key, cancelled)?;
            anyhow::ensure!(!cancelled(), "Cancelled");
            store.db.execute(
                "DELETE FROM activity WHERE at<?1",
                [chrono::Local::now().timestamp() - 90 * 86400],
            )?;
            let config = store.config()?;
            store.prune_excluded(&config)?;
            anyhow::ensure!(!cancelled(), "Cancelled");
            refresh_model_revision(&store)?;
            Ok((store, config))
        })
        .await
        .context("Index preparation worker failed")??;
        let mut s = self.state.lock().unwrap();
        anyhow::ensure!(s.generation == generation && !s.session_locked, "Cancelled");
        s.pending.extend(config.roots.clone());
        s.watch_dirs.extend(config.roots.clone());
        s.watches_dirty = true;
        s.pending_recent = true;
        if config.activity {
            if let Some(parent) = crate::recent::path().parent() {
                if parent.is_dir() {
                    s.watch_dirs.insert(parent.to_owned());
                }
            }
        }
        s.config = config;
        s.store = Some(store);
        s.problem.clear();
        s.budget_blocked = false;
        self.wake.notify_one();
        Ok(())
    }

    pub fn status(&self) -> Value {
        let s = self.state.lock().unwrap();
        let counts = s
            .store
            .as_ref()
            .and_then(|db| {
                db.db.query_row(
            "SELECT count(*),coalesce(sum(state='pending'),0),coalesce(sum(state='failed'),0),
             coalesce(sum(kind='app'),0),coalesce(sum(kind='app' AND state='pending'),0),
             coalesce(sum(kind='app' AND state='failed'),0) FROM files",
            [], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?,
                       r.get::<_, i64>(3)?, r.get::<_, i64>(4)?, r.get::<_, i64>(5)?))
        ).ok()
            })
            .unwrap_or_default();
        let current = s.current_file.as_ref().map(|(id, path, started)| {
            let seconds = s
                .store
                .as_ref()
                .and_then(|db| {
                    db.db
                        .query_row(
                            "SELECT offset FROM files WHERE id=?1 AND kind='video'",
                            [id],
                            |r| r.get::<_, i64>(0),
                        )
                        .ok()
                })
                .unwrap_or(0);
            let path = Path::new(path);
            json!({"name":path.file_name().unwrap_or_default().to_string_lossy(),
                "folder":path.parent().map(|p| p.to_string_lossy()),
                "elapsed_seconds":started.elapsed().as_secs(),"video_seconds":seconds})
        });
        let scanning = s.scanning || !s.pending.is_empty();
        json!({"locked":s.store.is_none(),"opening":s.opening_generation.is_some(),"session_locked":s.session_locked,"config":s.config,"files":counts.0,"pending":counts.1,"failed":counts.2,
            "ready":counts.0-counts.1-counts.2,"completed":counts.0-counts.1,"total_known":!scanning,"current":current,
            "applications":counts.3,"folder_stats":{"total":counts.0-counts.3,"pending":counts.1-counts.4,"failed":counts.2-counts.5},
            "on_battery":s.battery,"idle":s.idle,"scanning":scanning,"problem":s.problem,
            "models":crate::data_dir().join("models/manifest.json").is_file(),"protocol":1})
    }

    pub fn configure(&self, mut config: Config) -> Result<Value> {
        let mut s = self.state.lock().unwrap();
        // Reviews are produced by discovery. A settings window with an older
        // status must not accidentally dismiss a newly discovered large folder.
        config.source_reviews = s.config.source_reviews.clone();
        config.large_folders.extend(s.config.large_folders.clone());
        config.validate()?;
        self.apply_config(&mut s, config)?;
        drop(s);
        self.wake.notify_one();
        Ok(self.status())
    }

    pub fn review_source(&self, path: &Path, include: bool) -> Result<Value> {
        let mut s = self.state.lock().unwrap();
        let mut config = s.config.clone();
        anyhow::ensure!(
            config.source_reviews.iter().any(|r| r.path == path),
            "This folder no longer needs a decision"
        );
        config.source_reviews.retain(|r| r.path != path);
        if include {
            config.large_folders.push(path.to_owned());
        } else {
            config.excludes.push(path.to_owned());
        }
        config.validate()?;
        self.apply_config(&mut s, config)?;
        drop(s);
        self.wake.notify_one();
        Ok(self.status())
    }

    fn apply_config(&self, s: &mut State, config: Config) -> Result<()> {
        if config.semantic && !s.config.semantic {
            s.store
                .as_ref()
                .context("Lens is locked")?
                .db
                .execute("UPDATE files SET state='pending' WHERE state='text'", [])?;
        }
        s.store
            .as_mut()
            .context("Lens is locked")?
            .set_config(&config)?;
        s.generation += 1;
        self.cancel.send_replace(s.generation);
        s.current_file = None;
        s.ann.clear();
        s.query_cache.clear();
        s.pending.clear();
        s.pending.extend(config.roots.clone());
        s.config = config;
        s.problem.clear();
        s.budget_blocked = false;
        s.watch_dirs = s.config.roots.iter().cloned().collect();
        s.watches_dirty = true;
        s.pending_recent = true;
        if s.config.activity {
            if let Some(parent) = crate::recent::path().parent() {
                if parent.is_dir() {
                    s.watch_dirs.insert(parent.to_owned());
                }
            }
        }
        // Removing sources must also remove encrypted ANN snapshots containing their vectors.
        if let Some(db) = s.store.as_ref() {
            let _ = db.db.execute("DELETE FROM ann", []);
        }
        Ok(())
    }

    pub async fn encode(&self, request: Value, generation: u64) -> Result<Value> {
        let cache_key = if matches!(request["method"].as_str(), Some("query" | "rerank")) {
            let s = self.state.lock().unwrap();
            let key = format!("{}:{}:{}", generation, s.revision, request);
            if let Some(value) = s.query_cache.get(&key) {
                return Ok(value.clone());
            }
            Some(key)
        } else {
            None
        };
        let mut worker = self.worker.lock().await;
        let cancel = self.cancel.subscribe();
        anyhow::ensure!(*cancel.borrow() == generation, "Cancelled");
        let threads = {
            let s = self.state.lock().unwrap();
            crate::worker::inference_threads(
                s.config.fast_indexing && !s.battery,
                s.config.all_in && !s.battery,
            )
        };
        let mut active = match worker.take() {
            Some(worker) if worker.threads() == threads => worker,
            previous => {
                drop(previous);
                Worker::start(threads)?
            }
        };
        // Owning the child across this await makes cancellation kill it, not leave a stale reply on its pipe.
        match active.call(&request, cancel).await {
            Ok(value) => {
                *worker = Some(active);
                let mut s = self.state.lock().unwrap();
                s.last_model_use = Instant::now();
                if s.generation == generation {
                    if let Some(key) = cache_key {
                        if s.query_cache.len() >= 32 {
                            s.query_cache.clear();
                        }
                        s.query_cache.insert(key, value.clone());
                    }
                }
                Ok(value)
            }
            Err(error) => Err(error),
        }
    }

    pub async fn search(self: &Arc<Self>, input: &str, semantic: bool) -> Result<Value> {
        self.search_explained(input, semantic, false).await
    }

    pub async fn search_explained(
        self: &Arc<Self>,
        input: &str,
        semantic: bool,
        explain: bool,
    ) -> Result<Value> {
        let started = Instant::now();
        let mut trace = Vec::new();
        anyhow::ensure!(input.chars().count() <= 512, "Query is too long");
        let mut q = Query::parse(input, chrono::Local::now());
        let mut semantic = semantic && q.use_semantics();
        let (generation, models) = {
            let mut s = self.state.lock().unwrap();
            anyhow::ensure!(s.store.is_some(), "Lens is locked");
            s.last_query = Instant::now();
            s.active_searches += 1;
            semantic &= s.config.semantic;
            (
                s.generation,
                crate::data_dir().join("models/manifest.json").exists(),
            )
        };
        let lifetime = SearchLifetime(Arc::new(AtomicBool::new(false)), self.clone());
        {
            let s = self.state.lock().unwrap();
            q.source_roots = s.config.roots.clone();
            let mut filter = SourceFilter::new(&s.config);
            for path in &q.paths {
                anyhow::ensure!(
                    filter.readable(path),
                    "Explicit search path is outside selected sources or inaccessible"
                );
            }
            q.scopes = q.paths.clone();
            s.store
                .as_ref()
                .context("Lens is locked")?
                .prepare_query(&mut q)?;
        }
        // Resolve explicit folder names anywhere in the phrase. Compatible
        // ancestors narrow one another; numbered file labels are not scopes.
        if q.paths.is_empty() && q.text.split_whitespace().count() > 1 {
            let s = self.state.lock().unwrap();
            let mut filter = SourceFilter::new(&s.config);
            for word in q
                .text
                .split_whitespace()
                .filter(|w| w.chars().count() >= 2 && !w.chars().any(|c| c.is_ascii_digit()))
                .take(8)
            {
                let mut paths = vec![];
                for path in s
                    .store
                    .as_ref()
                    .context("Lens is locked")?
                    .folder_scopes(word)?
                {
                    if filter.readable(&path) {
                        paths.push(path);
                    }
                }
                if q.scopes.is_empty() {
                    q.scopes = paths;
                } else {
                    let mut narrower = vec![];
                    for old in &q.scopes {
                        for new in &paths {
                            if new.starts_with(old) {
                                narrower.push(new.clone());
                            } else if old.starts_with(new) {
                                narrower.push(old.clone());
                            }
                        }
                    }
                    narrower.sort();
                    narrower.dedup();
                    if !narrower.is_empty() {
                        q.scopes = narrower;
                    }
                }
            }
        }
        // Folder names are constraints, not document subject matter. Feeding an
        // unfamiliar project acronym into both neural models makes unrelated
        // files in that project look alike.
        let anchors: Vec<_> = q
            .scopes
            .iter()
            .filter_map(|p| p.file_name())
            .flat_map(|n| crate::query::variants(&n.to_string_lossy()))
            .collect();
        let remove_anchors = |text: &str| {
            text.split_whitespace()
                .filter(|word| {
                    !crate::query::variants(word)
                        .iter()
                        .any(|v| anchors.contains(v))
                })
                .collect::<Vec<_>>()
                .join(" ")
        };
        // Config keys are often terse syntax; retain the application context
        // that makes them interpretable to the multilingual models.
        let semantic_input = if q.kind.as_deref() == Some("config") {
            input.to_owned()
        } else {
            remove_anchors(input)
        };
        let semantic_subject = if q.kind.as_deref() == Some("config") {
            q.text.clone()
        } else {
            remove_anchors(&q.text)
        };
        let lexical = {
            let s = self.state.lock().unwrap();
            s.store
                .as_ref()
                .context("Lens is locked")?
                .search(&q, &[], 30)?
        };
        let navigation = lexical.iter().any(|hit| {
            crate::query::name_score(&hit.name, &q) >= 8.0
                || ((!q.numbered_labels().is_empty() || !q.ordinal_numbers().is_empty())
                    && q.coverage(&hit.path, "") == 1.0)
                || ((q.text.split_whitespace().count() == 1 || hit.kind == "folder")
                    && q.coverage(&hit.path, "") == 1.0)
        });
        let semantic_recommended =
            self.state.lock().unwrap().config.semantic && q.use_semantics() && !navigation;
        let lexical_ms = started.elapsed().as_millis();
        semantic &= semantic_recommended;
        let mut matches = vec![];
        let mut text_vector = None;
        let mut model_problem = None;
        if semantic && models && !q.text.is_empty() {
            let visual = matches!(q.kind.as_deref(), Some("photo" | "video"));
            match self
                .encode(
                    json!({"method":"query","text":semantic_input,"application_text":(q.kind.as_deref()==Some("config")).then_some(&semantic_subject),"visual":visual,"textual":!matches!(q.kind.as_deref(), Some("photo" | "video"))}),
                    generation,
                )
                .await
            {
                Ok(v) => {
                    for space in ["text", "visual"] {
                        // Explicit visual intent chooses frames in the visual space.
                        // Sparse OCR vectors must not beat the requested scene merely by being rank 1.
                        if space == "text" && matches!(q.kind.as_deref(), Some("photo" | "video")) {
                            continue;
                        }
                        let Some(values) = v[space].as_array() else {
                            continue;
                        };
                        let vector: Vec<f32> = values
                            .iter()
                            .filter_map(|n| n.as_f64().map(|v| v as f32))
                            .collect();
                        if space=="text" {text_vector=Some(vector.clone());}
                        // A project or explicit type is a small search space.
                        // Read those vectors directly instead of rebuilding the
                        // entire personal HNSW index after each background job.
                        if !q.scopes.is_empty() || matches!(q.kind.as_deref(),Some("app"|"config")) {
                            let bounded={
                                let s=self.state.lock().unwrap();
                                let db=s.store.as_ref().context("Locked")?;
                                retrieve_bounded(db,&q,&vector,space,200)?
                            };
                            if let Some(found)=bounded {
                                matches.extend(found);
                                if space=="text" && q.kind.as_deref()==Some("config") {
                                    let av:Vec<f32>=v["application"].as_array().map(|a|a.iter().filter_map(|n|n.as_f64().map(|n|n as f32)).collect()).unwrap_or_else(||vector.clone());
                                    let mut apps=q.clone();apps.kind=Some("app".into());apps.scopes.clear();
                                    let s=self.state.lock().unwrap();
                                    if let Some(found)=retrieve_bounded(s.store.as_ref().context("Locked")?,&apps,&av,space,6)? {matches.extend(found);}
                                }
                                continue;
                            }
                        }
                        let mut index = load_ann(
                            self.clone(),
                            space.to_string(),
                            vector.len(),
                            generation,
                            lifetime.0.clone(),
                        )
                        .await;
                        // An extraction that was already running may commit once
                        // after this query starts. Retry against its new revision;
                        // no further background job starts until the query ends.
                        if index.is_err() && self.state.lock().unwrap().generation == generation {
                            index = load_ann(self.clone(), space.to_string(), vector.len(), generation, lifetime.0.clone()).await;
                        }
                        // Application descriptions provide a general bridge from
                        // concepts such as "terminal" to directories such as kitty.
                        if space == "text" && q.kind.as_deref() == Some("config") {
                            if let Ok(index) = &index {
                                let app_chunks: std::collections::HashSet<u64> = {
                                    let s = self.state.lock().unwrap();
                                    let db = &s.store.as_ref().context("Locked")?.db;
                                    let mut stmt = db.prepare("SELECT chunks.id FROM chunks JOIN files ON files.id=chunks.file_id WHERE files.kind='app' AND chunks.space='text'")?;
                                    let ids = stmt.query_map([], |r| r.get::<_,i64>(0).map(|id| id as u64))?.collect::<rusqlite::Result<_>>()?;
                                    ids
                                };
                                let application_vector: Vec<f32> = v["application"].as_array().map(|values|values.iter().filter_map(|n|n.as_f64().map(|n|n as f32)).collect()).unwrap_or_else(||vector.clone());
                                if let Ok(apps) = retrieve_vectors(index, &application_vector, 6, Some(&app_chunks)) {
                                    matches.extend(apps);
                                }
                            }
                        }
                        let scope_chunks: Option<std::collections::HashSet<u64>> = if q.scopes.is_empty() { None } else {
                            let s=self.state.lock().unwrap();let db=&s.store.as_ref().context("Locked")?.db;
                            let mut stmt=db.prepare("SELECT chunks.id,files.path FROM chunks JOIN files ON files.id=chunks.file_id WHERE chunks.space=?1")?;
                            let mut ids=std::collections::HashSet::new();
                            for row in stmt.query_map([space],|r|Ok((r.get::<_,i64>(0)?,r.get::<_,String>(1)?)))? {
                                let (id,path)=row?;
                                if q.scopes.iter().any(|root|Path::new(&path).starts_with(root)) {ids.insert(id as u64);}
                            }
                            Some(ids)
                        };
                        let found = match index.and_then(|index|retrieve_vectors(&index,&vector,200,scope_chunks.as_ref())) {
                            Ok(found) => found,
                            Err(_) => {
                                // Indexing may invalidate an ANN snapshot while it is
                                // loading. Keep the current text/path results usable.
                                model_problem = Some("Semantic index unavailable; showing text matches");
                                continue;
                            }
                        };
                        // Each embedding space has its own ranking; do not compare raw cross-model distances.
                        matches.extend(found);
                    }
                    matches.sort_by(|a, b| b.1.total_cmp(&a.1));
                }
                Err(_) => {
                    model_problem = Some("Model unavailable; showing text matches");
                }
            }
        }
        let rerank = semantic
            && models
            && !q.text.is_empty()
            && !matches!(q.kind.as_deref(), Some("photo" | "video"));
        let mut hits: Vec<Hit> = {
            let s = self.state.lock().unwrap();
            anyhow::ensure!(s.generation == generation, "Cancelled");
            let store = s.store.as_ref().context("Lens is locked")?;
            let mut filter = SourceFilter::new(&s.config);
            let candidates = if rerank {
                store.candidates(&q, &matches, 32)?
            } else {
                if matches.is_empty() {
                    lexical
                } else {
                    store.search(&q, &matches, 30)?
                }
            };
            candidates
                .into_iter()
                .filter(|h| h.kind == "app" || filter.readable(Path::new(&h.path)))
                .filter(|h| {
                    !rerank
                        || h.kind != "folder"
                        || q.kind.as_deref() == Some("folder")
                        || q.coverage(&h.path, "") == 1.0
                        || crate::query::name_score(&h.name, &q) > 0.0
                })
                .collect()
        };
        let mut reranked = false;
        let retrieved_ms = started.elapsed().as_millis();
        if rerank && !hits.is_empty() {
            let documents: Vec<_> = {
                let s = self.state.lock().unwrap();
                hits.iter()
                    .map(|h| {
                        // Home names and temporary mount prefixes are not document meaning.
                        let path = Path::new(&h.evidence_path);
                        let root = s
                            .config
                            .roots
                            .iter()
                            .filter(|r| path.starts_with(r))
                            .max_by_key(|r| r.components().count())
                            .and_then(|r| r.parent());
                        let relative = root.and_then(|r| path.strip_prefix(r).ok()).unwrap_or(path);
                        let parent = relative.parent().unwrap_or(Path::new(""));
                        format!(
                            "Folder: {}\nFile: {}\n{}",
                            crate::query::semantic_words(&parent.to_string_lossy())
                                .chars()
                                .take(600)
                                .collect::<String>(),
                            crate::query::semantic_words(&h.name),
                            if h.kind == "config" {
                                crate::query::normalize(&h.evidence)
                            } else {
                                h.evidence.clone()
                            }
                        )
                    })
                    .collect()
            };
            if let Some(vector) = &text_vector {
                let missing: Vec<_> = hits
                    .iter()
                    .enumerate()
                    .filter(|(_, h)| {
                        h.application_context.is_none()
                            && (h.kind != "folder" || h.similarity.is_none())
                    })
                    .map(|(i, _)| i)
                    .collect();
                if !missing.is_empty() {
                    let pending: Vec<_> = missing
                        .iter()
                        .map(|i| documents[*i].lines().take(2).collect::<Vec<_>>().join("\n"))
                        .collect();
                    if let Ok(scores) = self
                        .encode(
                            json!({"method":"metadata","documents":pending,"query_vector":vector}),
                            generation,
                        )
                        .await
                    {
                        if let Some(scores) = scores["scores"]
                            .as_array()
                            .filter(|scores| scores.len() == missing.len())
                        {
                            for (index, score) in missing.into_iter().zip(scores) {
                                if let Some(cosine) = score.as_f64().filter(|v| v.is_finite()) {
                                    hits[index].similarity =
                                        Some(hits[index].similarity.unwrap_or(-1.0).max(cosine));
                                }
                            }
                        }
                    }
                }
            }
            match self
                .encode(
                    json!({"method":"rerank", "text":if q.kind.as_deref()==Some("config") {format!("{} {}",if semantic_subject.chars().any(|c|('а'..='я').contains(&c)) {"конфиг"} else {"configuration"},semantic_subject)} else {semantic_input.clone()},"documents":documents}),
                    generation,
                )
                .await
            {
                Ok(value) if value["available"] == true => {
                    if let Some(scores) =
                        value["scores"].as_array().filter(|v| v.len() == hits.len())
                    {
                        let competitors: Vec<_> = hits
                            .iter()
                            .map(|hit| {
                                hits.iter()
                                    .filter(|other| other.evidence_path != hit.evidence_path)
                                    // App-description similarity and file-content
                                    // similarity have different evidence; compare like with like.
                                    .filter(|other| {
                                        other.application_context.is_some()
                                            == hit.application_context.is_some()
                                    })
                                    .filter_map(|other| other.similarity)
                                    .max_by(f64::total_cmp)
                            })
                            .collect();
                        let mut ranked = Vec::new();
                        for ((mut hit, score), competitor) in
                            hits.into_iter().zip(scores).zip(competitors)
                        {
                            if let Some(logit) = score.as_f64().filter(|v| v.is_finite()) {
                                let relevance = crate::ranking::model().score(
                                    hit.similarity,
                                    logit,
                                    competitor,
                                );
                                if explain {
                                    trace.push(json!({"path":hit.path,"cosine":hit.similarity,"logit":logit,"competitor":competitor,"relevance":relevance,"lexical":hit.lexical,"application":hit.application_context}));
                                }
                                // A word inside an arbitrary JSON document does not
                                // establish that it configures the requested feature.
                                let lexical = hit.lexical
                                    && (q.kind.as_deref() != Some("config")
                                        || q.coverage(&hit.path, "") == 1.0);
                                if (relevance >= crate::ranking::model().threshold || lexical) && q.config_features_match(&hit.path, &hit.evidence) {
                                    let name = crate::query::name_score(&hit.name, &q);
                                    // A complete filename/folder-name match is direct
                                    // navigation intent, even without a document vector.
                                    // The calibrated score filters weak matches;
                                    // the cross-encoder orders complete requests.
                                    // Confidence contributes at most one logit:
                                    // it resolves uncertain reranker ties without
                                    // overpowering a clear full-query preference.
                                    hit.score=if name>0.0 {50.0+name+logit.tanh()} else {logit+relevance};
                                    if !matches!(hit.kind.as_str(),"app"|"folder") && crate::query::document_role(&q.text).is_some_and(|role|Some(role)==crate::query::document_role(&hit.name)) {hit.score+=0.5;}
                                    if hit.application_context.is_some()
                                        && Path::new(&hit.path).file_stem()
                                            == Path::new(&hit.path)
                                                .parent()
                                                .and_then(Path::file_name)
                                    {
                                        hit.score += 0.5;
                                    }
                                    ranked.push(hit);
                                }
                            }
                        }
                        hits = ranked;
                        // Stable ties retain the preference for a specific project
                        // over ancestors carrying evidence from the same file.
                        hits.sort_by(|a, b| b.score.total_cmp(&a.score));
                        reranked = true;
                    }
                }
                Ok(_) => {
                    model_problem = Some("Update Lens models to enable neural reranking");
                }
                Err(_) => {
                    model_problem = Some("Reranker unavailable; showing text matches");
                }
            }
            // Never turn an unavailable model into a list of unverified nearest neighbours.
            if !reranked {
                hits.retain(|h| h.lexical);
            }
        }
        hits.truncate(30);
        anyhow::ensure!(
            self.state.lock().unwrap().generation == generation,
            "Cancelled"
        );
        let mut response = json!({"results":hits,"query":q,"semantic":semantic && models,"semantic_recommended":semantic_recommended,"reranked":reranked,"problem":model_problem});
        if explain {
            response["diagnostics"] = json!({"candidates":trace,"timings":{"lexical_ms":lexical_ms,"retrieval_ms":retrieved_ms-lexical_ms,"rerank_ms":started.elapsed().as_millis()-retrieved_ms,"total_ms":started.elapsed().as_millis()}});
        }
        Ok(response)
    }

    pub fn record(&self, path: &Path, app: &str, source: &str) -> Result<()> {
        let s = self.state.lock().unwrap();
        if s.config.activity && s.config.readable(path) {
            if let Some(db) = s.store.as_ref() {
                db.record(path, app, source, chrono::Local::now().timestamp())?;
            }
        }
        Ok(())
    }

    pub fn validate_hit(&self, id: i64) -> Result<Hit> {
        let s = self.state.lock().unwrap();
        let hit = s
            .store
            .as_ref()
            .context("Lens is locked")?
            .hit(id)?
            .context("Result no longer exists")?;
        anyhow::ensure!(
            hit.kind == "app" || s.config.readable(Path::new(&hit.path)),
            "Result is no longer accessible"
        );
        Ok(hit)
    }

    pub fn apps(&self, items: &Value, begin: bool, end: bool) -> Result<()> {
        let items = items.as_array().context("Expected application list")?;
        anyhow::ensure!(items.len() <= 64, "Application batch limit exceeded");
        let mut s = self.state.lock().unwrap();
        let db = s.store.as_mut().context("Lens is locked")?;
        db.db
            .execute_batch("CREATE TEMP TABLE IF NOT EXISTS app_sync(path TEXT PRIMARY KEY)")?;
        if begin {
            db.db.execute("DELETE FROM app_sync", [])?;
        }
        let mut changed = false;
        for item in items {
            let app = item["id"].as_str().context("Application ID missing")?;
            anyhow::ensure!(app.len() <= 256 && !app.contains('/'), "Invalid desktop ID");
            let name = item["name"].as_str().unwrap_or(app);
            let text = config::scrub(&format!(
                "{} {} {} {}",
                name,
                item["comment"].as_str().unwrap_or(""),
                item["genericName"].as_str().unwrap_or(""),
                item["keywords"].as_str().unwrap_or("")
            ));
            let fingerprint = format!("{:x}", Sha256::digest(text.as_bytes()));
            let path = PathBuf::from(format!("app:{app}"));
            db.db.execute(
                "INSERT OR IGNORE INTO app_sync VALUES(?1)",
                [path.to_string_lossy().as_ref()],
            )?;
            let id = db.upsert(&path, "app", name, 0, 0, 0, 0)?;
            let previous: String =
                db.db
                    .query_row("SELECT fingerprint FROM files WHERE id=?1", [id], |r| {
                        r.get(0)
                    })?;
            if previous != fingerprint {
                changed = true;
                db.replace_chunks(id, &fingerprint, &[(text, None, None, None)])?;
                db.db
                    .execute("UPDATE files SET state='pending' WHERE id=?1", [id])?;
            }
        }
        if end {
            changed |= db.db.execute(
                "DELETE FROM files WHERE kind='app' AND path NOT IN (SELECT path FROM app_sync)",
                [],
            )? > 0;
        }
        if changed {
            invalidate(&mut s);
        }
        drop(s);
        self.wake.notify_one();
        Ok(())
    }
}

fn retrieve_bounded(
    store: &Store,
    q: &Query,
    query: &[f32],
    space: &str,
    count: usize,
) -> Result<Option<Vec<(i64, f64, f64)>>> {
    let scopes = serde_json::to_string(&q.scopes)?;
    let mut stmt=store.db.prepare("SELECT chunks.id,chunks.vector FROM files JOIN chunks ON chunks.file_id=files.id WHERE chunks.space=?1 AND chunks.vector IS NOT NULL AND (?2 IS NULL OR ?2='folder' OR files.kind=?2) AND (?3='[]' OR EXISTS(SELECT 1 FROM json_each(?3) WHERE files.path>=value||'/' AND files.path<value||'0')) LIMIT 20001")?;
    let rows = stmt
        .query_map(params![space, q.kind, scopes], |r| {
            Ok((r.get::<_, i64>(0)?, r.get::<_, Vec<u8>>(1)?))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    if rows.len() > 20000 {
        return Ok(None);
    }
    let query_norm = query.iter().map(|v| v * v).sum::<f32>().sqrt();
    let mut scores = Vec::new();
    for (id, bytes) in rows {
        if bytes.len() != query.len() * 2 {
            continue;
        }
        let vector: Vec<_> = bytes
            .chunks_exact(2)
            .map(|b| half::f16::from_bits(u16::from_le_bytes([b[0], b[1]])).to_f32())
            .collect();
        let norm = vector.iter().map(|v| v * v).sum::<f32>().sqrt() * query_norm;
        if norm > 0.0 {
            scores.push((
                id,
                query.iter().zip(vector).map(|(a, b)| a * b).sum::<f32>() as f64 / norm as f64,
            ));
        }
    }
    scores.sort_by(|a, b| b.1.total_cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    Ok(Some(
        scores
            .into_iter()
            .take(count)
            .enumerate()
            .map(|(rank, (id, cos))| (id, 1.0 / (60.0 + rank as f64), cos))
            .collect(),
    ))
}

fn retrieve_vectors(
    index: &Index,
    query: &[f32],
    count: usize,
    subset: Option<&std::collections::HashSet<u64>>,
) -> Result<Vec<(i64, f64, f64)>> {
    if let Some(ids) = subset.filter(|ids| ids.len() <= 4096) {
        let mut values = Vec::new();
        let query_norm = query.iter().map(|v| v * v).sum::<f32>().sqrt();
        let mut vector = vec![0f32; query.len()];
        for id in ids {
            if index.get(*id, &mut vector)? == 0 {
                continue;
            }
            let norm = vector.iter().map(|v| v * v).sum::<f32>().sqrt() * query_norm;
            if norm > 0.0 {
                let cosine = query.iter().zip(&vector).map(|(a, b)| a * b).sum::<f32>() / norm;
                values.push((*id, cosine as f64));
            }
        }
        values.sort_by(|a, b| b.1.total_cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
        return Ok(values
            .into_iter()
            .take(count)
            .enumerate()
            .map(|(rank, (id, cosine))| (id as i64, 1.0 / (60.0 + rank as f64), cosine))
            .collect());
    }
    let found = if let Some(ids) = subset {
        index.filtered_search(query, count, |id| ids.contains(&id))?
    } else if index.size() <= 4096 {
        index.exact_search(query, count)?
    } else {
        index.search(query, count)?
    };
    Ok(found
        .keys
        .into_iter()
        .zip(found.distances)
        .enumerate()
        .map(|(rank, (id, distance))| {
            (id as i64, 1.0 / (60.0 + rank as f64), 1.0 - distance as f64)
        })
        .collect())
}

async fn load_ann(
    engine: Arc<Engine>,
    space: String,
    dimension: usize,
    generation: u64,
    cancelled: Arc<AtomicBool>,
) -> Result<Arc<Index>> {
    {
        let s = engine.state.lock().unwrap();
        if let Some(index) = s.ann.get(&space) {
            return Ok(index.clone());
        }
    }
    tokio::task::spawn_blocking(move || {
        let revision = engine.state.lock().unwrap().revision;
        let check = |s: &State| -> Result<()> {
            anyhow::ensure!(!cancelled.load(Ordering::Relaxed), "Cancelled");
            anyhow::ensure!(s.generation == generation && s.revision == revision, "Index changed during loading");
            Ok(())
        };
        let index = Index::new(&IndexOptions {
            dimensions: dimension,
            metric: MetricKind::Cos,
            quantization: ScalarKind::F16,
            connectivity: 16,
            expansion_add: 128,
            expansion_search: 256,
            multi: false,
        })?;
        let (snapshot, count) = {
            let s = engine.state.lock().unwrap();
            check(&s)?;
            let store = s.store.as_ref().context("Locked")?;
            let snapshot = store.db.query_row("SELECT snapshot FROM ann WHERE space=?1", [&space], |r| r.get::<_, Vec<u8>>(0)).optional()?;
            let count: i64 = store.db.query_row("SELECT count(*) FROM chunks WHERE space=?1 AND vector IS NOT NULL", [&space], |r| r.get(0))?;
            (snapshot, count)
        };
        let restored = snapshot.as_ref().is_some_and(|bytes| index.load_from_buffer(bytes).is_ok());
        index.change_expansion_search(256);
        if !restored {
            let threads = {
                let s = engine.state.lock().unwrap();
                crate::worker::inference_threads(s.config.fast_indexing && !s.battery, s.config.all_in && !s.battery)
                    .min((count as usize).max(1))
            };
            index.reserve_capacity_and_threads(count as usize, threads)?;
            let mut after = 0;
            loop {
                let rows = {
                    let s = engine.state.lock().unwrap();
                    check(&s)?;
                    let store = s.store.as_ref().context("Locked")?;
                    let mut statement = store.db.prepare("SELECT id,vector FROM chunks WHERE space=?1 AND vector IS NOT NULL AND id>?2 ORDER BY id LIMIT 4096")?;
                    let rows = statement.query_map(params![space, after], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, Vec<u8>>(1)?)))?.collect::<rusqlite::Result<Vec<_>>>()?;
                    rows
                };
                if rows.is_empty() {
                    break;
                }
                after = rows.last().unwrap().0;
                std::thread::scope(|scope| -> Result<()> {
                    let mut jobs = Vec::new();
                    for batch in rows.chunks(rows.len().div_ceil(threads)) {
                        let index = &index;
                        let cancelled = &cancelled;
                        jobs.push(scope.spawn(move || -> Result<()> {
                            for (id, bytes) in batch {
                                anyhow::ensure!(!cancelled.load(Ordering::Relaxed), "Cancelled");
                                let vector: Vec<i16> = bytes.as_chunks::<2>().0.iter().map(|b| i16::from_le_bytes(*b)).collect();
                                if vector.len() == dimension { index.add(*id as u64, usearch::f16::from_i16s(&vector))?; }
                            }
                            Ok(())
                        }));
                    }
                    for job in jobs { job.join().map_err(|_|anyhow::anyhow!("Index worker stopped"))??; }
                    Ok(())
                })?;
            }
        }
        let mut bytes = if restored { vec![] } else { vec![0; index.serialized_length()] };
        if !restored {
            index.save_to_buffer(&mut bytes)?;
        }
        let mut s = engine.state.lock().unwrap();
        check(&s)?;
        if !restored {
            s.store.as_ref().context("Locked")?.db.execute("INSERT OR REPLACE INTO ann VALUES(?1,?2)", params![space, bytes])?;
        }
        let index = Arc::new(index);
        s.ann.insert(space, index.clone());
        Ok(index)
    }).await?
}

pub fn refresh_model_revision(store: &Store) -> Result<()> {
    // Model installation may finish while Settings is closed or the session is locked.
    if let Ok(manifest) = std::fs::read(crate::data_dir().join("models/manifest.json")) {
        let bundle: Value = serde_json::from_slice(&manifest)?;
        let revision = bundle["embedding_revision"]
            .as_str()
            .map(str::to_owned)
            .unwrap_or_else(|| format!("{:x}", Sha256::digest(&manifest)));
        let previous: Option<String> = store
            .db
            .query_row(
                "SELECT value FROM settings WHERE key='model_revision'",
                [],
                |r| r.get(0),
            )
            .optional()?;
        if previous.as_ref() != Some(&revision) {
            store.db.execute("UPDATE files SET state='pending',fingerprint='',offset=0 WHERE kind NOT IN ('folder','name')", [])?;
            store.db.execute(
                "INSERT OR REPLACE INTO settings VALUES('model_revision',?1)",
                [revision],
            )?;
        }
    }
    Ok(())
}

fn invalidate(s: &mut State) {
    s.query_cache.clear();
    if s.budget_blocked {
        s.problem.clear();
    }
    s.budget_blocked = false;
    s.revision += 1;
    s.ann.clear();
    if let Some(db) = s.store.as_ref() {
        let _ = db.db.execute("DELETE FROM ann", []);
    }
}

fn vector(v: &Value) -> Option<Vec<u8>> {
    base64::engine::general_purpose::STANDARD
        .decode(v.as_str()?)
        .ok()
}

fn text_chunks(text: &str) -> Vec<String> {
    let chars: Vec<_> = text.chars().take(128_000).collect();
    (0..chars.len())
        .step_by(700)
        .take(192)
        .map(|i| chars[i..(i + 850).min(chars.len())].iter().collect())
        .collect()
}

fn read_text(path: &Path) -> Result<(String, String)> {
    let metadata = path.metadata()?;
    anyhow::ensure!(metadata.len() <= 2 * 1024 * 1024, "Text file exceeds 2 MiB");
    let mut bytes = Vec::new();
    std::fs::File::open(path)?
        .take(2 * 1024 * 1024 + 1)
        .read_to_end(&mut bytes)?;
    anyhow::ensure!(
        !bytes.contains(&0) && bytes.len() <= 2 * 1024 * 1024,
        "Binary or oversized file"
    );
    let hash = format!("text-v2:{:x}", Sha256::digest(&bytes));
    let text = String::from_utf8(bytes).context("Only UTF-8 text is supported")?;
    let text = if path
        .extension()
        .is_some_and(|e| e.to_string_lossy().eq_ignore_ascii_case("ipynb"))
    {
        let notebook: Value = serde_json::from_str(&text)?;
        notebook["cells"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|cell| cell["source"].as_array())
            .map(|lines| {
                lines
                    .iter()
                    .filter_map(Value::as_str)
                    .collect::<Vec<_>>()
                    .join("")
            })
            .collect::<Vec<_>>()
            .join("\n\n")
    } else {
        text
    };
    Ok((config::scrub(&text), hash))
}

#[derive(Debug)]
struct IndexBudget;
impl std::fmt::Display for IndexBudget {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Index limit reached; exclude sources before retrying")
    }
}
impl std::error::Error for IndexBudget {}

fn ensure_budget(db: &Store, extra_chunks: usize) -> Result<()> {
    let count: i64 = db
        .db
        .query_row("SELECT count(*) FROM chunks", [], |r| r.get(0))?;
    let used: i64 = db.db.query_row("SELECT (p.page_count-f.freelist_count)*s.page_size FROM pragma_page_count p,pragma_freelist_count f,pragma_page_size s", [], |r| r.get(0))?;
    if count + extra_chunks as i64 >= 500_000 || used >= 5 * 1024 * 1024 * 1024 {
        return Err(IndexBudget.into());
    }
    Ok(())
}

async fn index_one(
    engine: &Arc<Engine>,
    id: i64,
    path: PathBuf,
    kind: String,
    generation: u64,
) -> Result<()> {
    let threads = {
        let s = engine.state.lock().unwrap();
        anyhow::ensure!(s.generation == generation, "Cancelled");
        ensure_budget(s.store.as_ref().context("Locked")?, 0)?;
        crate::worker::inference_threads(
            s.config.fast_indexing && !s.battery,
            s.config.all_in && !s.battery,
        )
    };
    if kind == "app" {
        let (text, hash) = {
            let s = engine.state.lock().unwrap();
            let db = s.store.as_ref().context("Locked")?;
            db.db.query_row("SELECT c.text,f.fingerprint FROM files f JOIN chunks c ON c.file_id=f.id WHERE f.id=?1 LIMIT 1",[id],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?)))?
        };
        let v = if crate::data_dir().join("models/manifest.json").exists() {
            let encoded = engine
                .encode(json!({"method":"encode","texts":[text]}), generation)
                .await?;
            vector(&encoded["text"][0])
        } else {
            None
        };
        let mut s = engine.state.lock().unwrap();
        anyhow::ensure!(s.generation == generation, "Cancelled");
        s.store.as_mut().context("Locked")?.replace_chunks(
            id,
            &hash,
            &[(text, None, v.as_ref().map(|_| "text".into()), v)],
        )?;
        invalidate(&mut s);
        return Ok(());
    }
    let offset = {
        let s = engine.state.lock().unwrap();
        anyhow::ensure!(
            s.generation == generation && s.config.readable(&path),
            "Cancelled"
        );
        s.store.as_ref().context("Locked")?.db.query_row(
            "SELECT offset FROM files WHERE id=?1",
            [id],
            |r| r.get::<_, i64>(0),
        )?
    };
    let before = path.metadata()?;
    let media = kind == "photo"
        || kind == "video"
        || path
            .extension()
            .is_some_and(|e| e.to_string_lossy().eq_ignore_ascii_case("pdf"));
    let mut pieces = Vec::new();
    let mut next = None;
    let fingerprint;
    if kind == "folder" || kind == "name" {
        let s = engine.state.lock().unwrap();
        if s.generation != generation {
            return Ok(());
        }
        s.store
            .as_ref()
            .context("Locked")?
            .db
            .execute("UPDATE files SET state='ready' WHERE id=?1", [id])?;
        return Ok(());
    }
    if media {
        let enabled = engine.state.lock().unwrap().config.media;
        if !enabled && kind != "file" {
            return Ok(());
        }
        let extraction = crate::worker::extract(
            &path,
            if kind == "file" { "pdf" } else { &kind },
            offset,
            threads,
            engine.cancel.subscribe(),
        )
        .await?;
        next = extraction["next"].as_i64();
        for chunk in extraction["chunks"].as_array().into_iter().flatten() {
            let text = config::scrub(chunk["text"].as_str().unwrap_or(""));
            let mut parts = text_chunks(&text);
            if parts.is_empty() {
                parts.push(String::new());
            }
            for (i, text) in parts.into_iter().enumerate() {
                pieces.push((
                    text,
                    chunk["timestamp"].as_f64(),
                    if i == 0 {
                        chunk["image"].as_str().map(str::to_owned)
                    } else {
                        None
                    },
                ));
            }
        }
        fingerprint = format!("extract-v2:{}:{}", before.mtime_nsec(), before.len());
    } else {
        let (text, hash) = read_text(&path)?;
        fingerprint = hash;
        let same = {
            let s = engine.state.lock().unwrap();
            s.store.as_ref().context("Locked")?.db.query_row(
                "SELECT fingerprint=?1 FROM files WHERE id=?2",
                params![fingerprint, id],
                |r| r.get::<_, bool>(0),
            )?
        };
        let semantic = engine.state.lock().unwrap().config.semantic;
        let has_vectors = {
            let s = engine.state.lock().unwrap();
            s.store.as_ref().context("Locked")?.db.query_row(
                "SELECT EXISTS(SELECT 1 FROM chunks WHERE file_id=?1 AND vector IS NOT NULL)",
                [id],
                |r| r.get::<_, bool>(0),
            )?
        };
        if same && (!semantic || has_vectors) {
            let s = engine.state.lock().unwrap();
            if s.generation == generation {
                s.store.as_ref().unwrap().db.execute(
                    "UPDATE files SET state=?2 WHERE id=?1",
                    params![id, if has_vectors { "ready" } else { "text" }],
                )?;
            }
            return Ok(());
        }
        pieces.extend(text_chunks(&text).into_iter().map(|t| (t, None, None)));
    }
    let semantic = engine.state.lock().unwrap().config.semantic;
    let models = semantic && crate::data_dir().join("models/manifest.json").is_file();
    // Parser upgrades recheck text, but unchanged passages can retain their
    // embeddings. A cleared fingerprint denotes a model revision and must not
    // reuse vectors from the previous embedding model.
    if offset == 0 && next.is_none() && pieces.iter().all(|p| p.2.is_none()) {
        let s = engine.state.lock().unwrap();
        anyhow::ensure!(s.generation == generation, "Cancelled");
        let db = s.store.as_ref().context("Locked")?;
        let previous: String =
            db.db
                .query_row("SELECT fingerprint FROM files WHERE id=?1", [id], |r| {
                    r.get(0)
                })?;
        let mut stmt = db.db.prepare(
            "SELECT text,timestamp,vector IS NOT NULL FROM chunks WHERE file_id=?1 ORDER BY id",
        )?;
        let old = stmt
            .query_map([id], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, Option<f64>>(1)?,
                    r.get::<_, bool>(2)?,
                ))
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        let current: Vec<_> = pieces.iter().filter(|p| !p.0.trim().is_empty()).collect();
        if !previous.is_empty()
            && old.len() == current.len()
            && old
                .iter()
                .zip(current)
                .all(|(a, b)| a.0 == b.0 && a.1 == b.1 && (!models || a.2))
        {
            let after = path.metadata()?;
            anyhow::ensure!(
                before.mtime() == after.mtime()
                    && before.mtime_nsec() == after.mtime_nsec()
                    && before.len() == after.len(),
                "File changed during extraction"
            );
            db.db.execute(
                "UPDATE files SET fingerprint=?1,state=?3,error='' WHERE id=?2",
                params![
                    fingerprint,
                    id,
                    if old.iter().all(|c| c.2) {
                        "ready"
                    } else {
                        "text"
                    }
                ],
            )?;
            return Ok(());
        }
    }
    let mut chunks = Vec::new();
    for batch in pieces.chunks(12) {
        let texts: Vec<_> = batch
            .iter()
            .filter(|p| !p.0.trim().is_empty())
            .map(|p| p.0.clone())
            .collect();
        let images: Vec<_> = batch.iter().filter_map(|p| p.2.clone()).collect();
        let encoded = if models {
            Some(
                engine
                    .encode(
                        json!({"method":"encode","texts":texts,"images":images}),
                        generation,
                    )
                    .await?,
            )
        } else {
            None
        };
        let mut image_i = 0;
        let mut text_i = 0;
        for (text, time, image) in batch {
            if !text.trim().is_empty() {
                let v = encoded.as_ref().and_then(|e| vector(&e["text"][text_i]));
                text_i += 1;
                chunks.push((text.clone(), *time, v.as_ref().map(|_| "text".into()), v));
            }
            if image.is_some() {
                let v = encoded.as_ref().and_then(|e| vector(&e["visual"][image_i]));
                image_i += 1;
                if let Some(v) = v {
                    chunks.push((text.clone(), *time, Some("visual".into()), Some(v)));
                }
            }
        }
    }
    let after = path.metadata()?;
    anyhow::ensure!(
        before.mtime() == after.mtime()
            && before.mtime_nsec() == after.mtime_nsec()
            && before.len() == after.len(),
        "File changed during extraction"
    );
    let mut s = engine.state.lock().unwrap();
    anyhow::ensure!(
        s.generation == generation && s.config.readable(&path),
        "Cancelled"
    );
    let db = s.store.as_mut().context("Locked")?;
    ensure_budget(db, chunks.len())?;
    let frames: Vec<_> = pieces
        .iter()
        .filter_map(|(_, time, image)| {
            image
                .as_ref()
                .map(|image| (time.unwrap_or(0.0), image.clone()))
        })
        .collect();
    db.save_extraction(id, &fingerprint, &chunks, &frames, offset > 0, next)?;
    if !semantic {
        db.db
            .execute("UPDATE files SET state='text' WHERE id=?1", [id])?;
    }
    invalidate(&mut s);
    Ok(())
}

fn scan_paths(engine: &Arc<Engine>, root: &Path, generation: u64) -> Result<()> {
    let mut config = {
        let s = engine.state.lock().unwrap();
        s.config.clone()
    };
    if root.is_dir() {
        let reviews =
            crate::sources::discover(root, &config, crate::sources::LARGE_FOLDER_FILES, || {
                *engine.cancel.borrow() != generation
            })?;
        if !reviews.is_empty() {
            let mut s = engine.state.lock().unwrap();
            anyhow::ensure!(s.generation == generation, "Cancelled");
            config
                .source_reviews
                .retain(|old| !reviews.iter().any(|new| old.path.starts_with(&new.path)));
            config.source_reviews.extend(reviews);
            s.store.as_mut().context("Locked")?.set_config(&config)?;
            s.config = config.clone();
            s.watch_dirs
                .retain(|path| !path.starts_with(root) || config.allows(path));
            s.watches_dirty = true;
            s.pending.retain(|path| config.allows(path));
            s.problem.clear();
            invalidate(&mut s);
        }
    }
    let mut filter = SourceFilter::new(&config);
    if !root.exists() || !filter.allows(root) {
        let mut s = engine.state.lock().unwrap();
        if s.generation != generation {
            return Ok(());
        }
        if let Some(db) = s.store.as_ref() {
            for (id, path) in db.paths()? {
                if Path::new(&path).starts_with(root)
                    && (!root.exists() || !filter.allows(Path::new(&path)))
                {
                    db.db.execute("DELETE FROM files WHERE id=?1", [id])?;
                }
            }
        }
        s.watch_dirs
            .retain(|path| !path.starts_with(root) || filter.allows(path));
        s.watches_dirty = true;
        invalidate(&mut s);
        return Ok(());
    }
    let mut entries = walkdir::WalkDir::new(root).follow_links(false).into_iter();
    let mut candidates = Vec::new();
    while let Some(entry) = entries.next() {
        let Ok(entry) = entry else { continue };
        if *engine.cancel.borrow() != generation {
            return Ok(());
        }
        if entry.file_type().is_symlink() || !filter.allows(entry.path()) {
            if entry.file_type().is_dir() {
                entries.skip_current_dir();
            }
            continue;
        }
        let kind = config::kind(entry.path());
        let priority = match kind {
            "folder" => 0,
            "config" => 1,
            "file"
                if entry.path().extension().is_some_and(|e| {
                    matches!(
                        e.to_str().unwrap_or(""),
                        "pdf" | "md" | "ipynb" | "org" | "rst"
                    )
                }) =>
            {
                2
            }
            "file" => 3,
            "name" => 4,
            _ => 5,
        };
        candidates.push((priority, entry));
    }
    // A large image dataset must not hide the next sibling course or its PDFs.
    // Catalogue folders and documents first; media fills the remaining capacity.
    candidates.sort_by(|(a, x), (b, y)| {
        a.cmp(b)
            .then_with(|| x.depth().cmp(&y.depth()))
            .then_with(|| x.path().cmp(y.path()))
    });
    let (mut existing, mut media_victims) = {
        let s = engine.state.lock().unwrap();
        let db = s.store.as_ref().context("Locked")?;
        let existing: std::collections::HashSet<_> =
            db.paths()?.into_iter().map(|(_, path)| path).collect();
        let mut stmt = db.db.prepare("SELECT id,path FROM files WHERE kind IN ('photo','video') ORDER BY (state='pending'),id")?;
        let victims = stmt
            .query_map([], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?)))?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        (existing, victims)
    };
    let mut limited = false;
    let mut evicted = false;
    for (priority, entry) in candidates {
        // Discovery is a long-running job too. Yield between files so a scan
        // cannot repeatedly take the database mutex ahead of a user query.
        while engine.state.lock().unwrap().active_searches > 0 {
            if *engine.cancel.borrow() != generation {
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let path = entry.path();
        if priority == 5 && limited && !existing.contains(path.to_string_lossy().as_ref()) {
            continue;
        }
        if !filter.readable(path) {
            continue;
        }
        let Ok(meta) = path.metadata() else { continue };
        if !meta.is_dir() && !meta.is_file() {
            continue;
        }
        let mut s = engine.state.lock().unwrap();
        if s.generation != generation {
            return Ok(());
        }
        if meta.is_dir() && s.watch_dirs.insert(path.to_path_buf()) {
            s.watches_dirty = true;
        }
        let db = s.store.as_mut().context("Locked")?;
        let count: i64 = db
            .db
            .query_row("SELECT count(*) FROM files", [], |r| r.get(0))?;
        if count >= config.max_files as i64 {
            let exists: bool = db.db.query_row(
                "SELECT EXISTS(SELECT 1 FROM files WHERE path=?1)",
                [path.to_string_lossy().as_ref()],
                |r| r.get(0),
            )?;
            if !exists {
                limited = true;
                s.problem = "File limit reached; choose fewer sources".into();
                if priority < 5 {
                    if let Some((id, old_path)) = media_victims.pop() {
                        s.store
                            .as_ref()
                            .context("Locked")?
                            .db
                            .execute("DELETE FROM files WHERE id=?1", [id])?;
                        existing.remove(&old_path);
                        evicted = true;
                    } else {
                        continue;
                    }
                } else {
                    continue;
                }
            }
        }
        let db = s.store.as_mut().context("Locked")?;
        let id = db.upsert(
            path,
            config::kind(path),
            &entry.file_name().to_string_lossy(),
            meta.mtime(),
            meta.len(),
            meta.dev(),
            meta.ino(),
        )?;
        existing.insert(path.to_string_lossy().into_owned());
        if matches!(config::kind(path), "folder" | "name") {
            db.db
                .execute("UPDATE files SET state='ready' WHERE id=?1", [id])?;
        }
        // Lightweight document text should be searchable before embeddings.
        // Notebook outputs are ignored; only source cells enter the catalogue.
        let quick_text = if config::kind(path) == "config" {
            meta.len() <= 128 * 1024
        } else {
            meta.len() <= 1024 * 1024
                && path
                    .extension()
                    .and_then(|e| e.to_str())
                    .is_some_and(|e| matches!(e, "ipynb" | "md" | "rst" | "org" | "txt"))
        };
        if !config.paused && quick_text {
            let (indexed, fingerprint, oversized_seed): (bool,String,bool) = db.db.query_row(
                "SELECT EXISTS(SELECT 1 FROM chunks WHERE file_id=?1),fingerprint,EXISTS(SELECT 1 FROM chunks WHERE file_id=?1 AND vector IS NULL AND length(text)>850) FROM files WHERE id=?1",
                [id],
                |r| Ok((r.get(0)?,r.get(1)?,r.get(2)?)),
            )?;
            if !indexed
                || (fingerprint.is_empty() && oversized_seed)
                || (!fingerprint.is_empty() && !fingerprint.starts_with("text-v2:"))
            {
                if let Ok((text, _)) = read_text(path) {
                    if indexed {
                        let mut stmt = db
                            .db
                            .prepare("SELECT text FROM chunks WHERE file_id=?1 ORDER BY id")?;
                        let old = stmt
                            .query_map([id], |r| r.get::<_, String>(0))?
                            .collect::<rusqlite::Result<Vec<_>>>()?;
                        if old == text_chunks(&text) {
                            continue;
                        }
                    }
                    let unchanged = path.metadata().is_ok_and(|after| {
                        after.mtime() == meta.mtime()
                            && after.mtime_nsec() == meta.mtime_nsec()
                            && after.len() == meta.len()
                            && after.ino() == meta.ino()
                            && after.dev() == meta.dev()
                    });
                    let chunks: Vec<_> = text_chunks(&text)
                        .into_iter()
                        .map(|text| (text, None, None, None))
                        .collect();
                    if unchanged && ensure_budget(db, chunks.len()).is_ok() {
                        db.replace_chunks(id, "", &chunks)?;
                        db.db
                            .execute("UPDATE files SET state='pending' WHERE id=?1", [id])?;
                    }
                }
            }
        }
        if !config.media && matches!(config::kind(path), "photo" | "video") {
            db.db
                .execute("UPDATE files SET state='ready' WHERE id=?1", [id])?;
        }
    }
    // Reconcile removals after downtime without mistaking unreadable files for deleted ones.
    let mut s = engine.state.lock().unwrap();
    if s.generation != generation {
        return Ok(());
    }
    let mut removed = false;
    if root.is_dir() {
        if let Some(db) = s.store.as_ref() {
            for (id, path) in db.paths()? {
                if Path::new(&path).starts_with(root)
                    && (!filter.allows(Path::new(&path))
                        || std::fs::symlink_metadata(&path)
                            .is_err_and(|e| e.kind() == std::io::ErrorKind::NotFound))
                {
                    db.db.execute("DELETE FROM files WHERE id=?1", [id])?;
                    removed = true;
                }
            }
        }
    }
    if removed {
        s.watch_dirs
            .retain(|path| !path.starts_with(root) || filter.allows(path));
        s.watches_dirty = true;
        if limited {
            s.pending.insert(root.to_owned());
            s.problem.clear();
        }
        invalidate(&mut s);
    }
    // Names and quick text also change retrieval, even without removals.
    let _ = evicted;
    invalidate(&mut s);
    Ok(())
}

pub async fn background(engine: Arc<Engine>) {
    let (events, mut receiver) = tokio::sync::mpsc::channel(256);
    let overflow = Arc::new(std::sync::atomic::AtomicBool::new(false));
    let lost = overflow.clone();
    let mut watcher = notify::recommended_watcher(move |event: notify::Result<notify::Event>| {
        if let Ok(ref event) = event {
            if matches!(event.kind, notify::EventKind::Access(_)) {
                return;
            }
        }
        if events.try_send(event).is_err() {
            lost.store(true, std::sync::atomic::Ordering::Relaxed);
        }
    })
    .ok();
    loop {
        tokio::select! {
            _=engine.wake.notified()=>{},
            event=receiver.recv()=>{
                let mut batch=vec![event];
                tokio::time::sleep(Duration::from_millis(250)).await;
                while let Ok(event)=receiver.try_recv(){batch.push(Some(event));}
                let mut s=engine.state.lock().unwrap();
                for event in batch {match event {
                    Some(Ok(event))=>{for path in event.paths{
                        if path==crate::recent::path(){s.pending_recent=true;}
                        else if s.config.allows(&path){
                            // Rule edits/removals and environment markers affect existing
                            // descendants as well as the changed file itself.
                            let path = if matches!(path.file_name().and_then(|s| s.to_str()), Some("pyvenv.cfg" | "conda-meta" | ".gitignore" | ".ignore")) || event.kind.is_create()
                                || path.extension().and_then(|s| s.to_str()).is_some_and(|ext| ext.eq_ignore_ascii_case("npy") || ext.eq_ignore_ascii_case("npz")) {
                                path.parent().unwrap_or(&path).to_path_buf()
                            } else { path };
                            s.pending.insert(path);
                        }
                    }},
                    _=>{let roots=s.config.roots.clone();s.pending.extend(roots);}
                }}
            },
            _=tokio::time::sleep(Duration::from_secs(30))=>{}
        }
        let (roots, old, closed, expired) = {
            let mut s = engine.state.lock().unwrap();
            if overflow.swap(false, std::sync::atomic::Ordering::Relaxed) {
                let roots = s.config.roots.clone();
                s.pending.extend(roots);
            }
            let old = if s.watches_dirty {
                s.watched.clone()
            } else {
                vec![]
            };
            let roots = if s.watches_dirty {
                s.watch_dirs.iter().cloned().collect::<Vec<_>>()
            } else {
                vec![]
            };
            if s.watches_dirty {
                s.watched = roots.clone();
                s.watches_dirty = false;
            }
            let expired = s.last_query.elapsed() > Duration::from_secs(60);
            if expired {
                s.ann.clear();
            }
            (
                roots,
                old,
                s.store.is_none(),
                !s.config.semantic
                    || s.assistant_busy
                    || s.last_model_use.elapsed() > Duration::from_secs(60),
            )
        };
        if roots != old {
            if let Some(w) = watcher.as_mut() {
                let current: BTreeSet<_> = roots.iter().collect();
                let previous: BTreeSet<_> = old.iter().collect();
                for root in previous.difference(&current) {
                    let _ = w.unwatch(root);
                }
                for root in current.difference(&previous) {
                    if w.watch(root, notify::RecursiveMode::NonRecursive).is_err() {
                        engine.state.lock().unwrap().problem =
                            "File watcher unavailable; rescan sources manually".into();
                    }
                }
            }
        }
        if closed || expired {
            if let Ok(mut w) = engine.worker.try_lock() {
                *w = None;
            }
        }
        if closed {
            continue;
        }
        if engine.state.lock().unwrap().active_searches > 0 {
            continue;
        }
        let next = {
            let mut s = engine.state.lock().unwrap();
            // Process rename destinations before removals so inode identity and history survive moves.
            let existing = s.pending.iter().find(|p| p.exists()).cloned();
            let next = if let Some(path) = existing {
                s.pending.remove(&path);
                Some(path)
            } else {
                s.pending.pop_first()
            };
            s.scanning = next.is_some();
            next.map(|p| (p, s.generation))
        };
        if let Some((path, generation)) = next {
            let e = engine.clone();
            let scan_path = path.clone();
            let result =
                tokio::task::spawn_blocking(move || scan_paths(&e, &scan_path, generation)).await;
            {
                let mut s = engine.state.lock().unwrap();
                s.scanning = false;
                if s.store.is_some() && s.generation != generation && s.config.allows(&path) {
                    s.pending.insert(path);
                } else if s.generation == generation && !matches!(result, Ok(Ok(()))) {
                    s.problem = "Could not scan a source folder; retry from Settings".into();
                }
            }
            engine.wake.notify_one();
            continue;
        }
        {
            let mut s = engine.state.lock().unwrap();
            if s.pending_recent && s.config.activity {
                if let Ok(entries) = crate::recent::read(&crate::recent::path()) {
                    let now = chrono::Local::now().timestamp();
                    for (path, at) in entries {
                        if at >= now - 90 * 86400 && at <= now && s.config.readable(&path) {
                            if let Some(db) = s.store.as_ref() {
                                let _ = db.record(&path, "desktop", "recent", at);
                            }
                        }
                    }
                }
            }
            s.pending_recent = false;
        }
        let job = {
            let s = engine.state.lock().unwrap();
            if s.active_searches > 0
                || s.assistant_busy
                || !s.config.indexing_allowed(s.battery, s.idle)
                || s.budget_blocked
            {
                None
            } else {
                s.store.as_ref().and_then(|db|db.db.query_row(&format!("SELECT id,path,kind FROM files WHERE state='pending' AND (?1 OR kind NOT IN ('photo','video')) AND (?2 OR kind NOT IN ('photo','video','app')) ORDER BY {},id LIMIT 1", crate::store::WORK_PRIORITY),params![s.config.media,s.config.semantic],|r|Ok((r.get::<_,i64>(0)?,r.get::<_,String>(1)?,r.get::<_,String>(2)?))).optional().ok().flatten()).map(|(id,p,k)|(id,PathBuf::from(p),k,s.generation))
            }
        };
        if let Some((id, path, kind, generation)) = job {
            {
                let mut s = engine.state.lock().unwrap();
                if s.generation == generation {
                    s.current_file =
                        Some((id, path.to_string_lossy().into_owned(), Instant::now()));
                }
            }
            if let Err(error) = index_one(&engine, id, path, kind, generation).await {
                let mut s = engine.state.lock().unwrap();
                if s.generation == generation {
                    if error.is::<IndexBudget>() {
                        s.budget_blocked = true;
                        s.problem = error.to_string();
                    } else if let Some(db) = s.store.as_ref() {
                        let _ = db.db.execute("UPDATE files SET state='failed',error='Extraction unavailable or file exceeded limits' WHERE id=?1", [id]);
                    }
                }
            }
            engine.state.lock().unwrap().current_file = None;
            engine.wake.notify_one();
        }
    }
}

#[cfg(test)]
mod source_tests {
    use super::*;

    #[tokio::test]
    async fn lexical_mode_preserves_vectors_and_lock_clears_query_cache() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("report.txt");
        std::fs::write(&path, "orbital mechanics").unwrap();
        let mut config = Config {
            roots: vec![dir.path().to_owned()],
            activity: false,
            ..Default::default()
        };
        let mut store = Store::open(&dir.path().join("index.db"), &[19; 32]).unwrap();
        store.set_config(&config).unwrap();
        let m = path.metadata().unwrap();
        let id = store
            .upsert(
                &path,
                "file",
                "report.txt",
                m.mtime(),
                m.len(),
                m.dev(),
                m.ino(),
            )
            .unwrap();
        store
            .replace_chunks(
                id,
                "fixture",
                &[(
                    "orbital mechanics".into(),
                    None,
                    Some("text".into()),
                    Some(vec![1, 2, 3, 4]),
                )],
            )
            .unwrap();
        let engine = Engine::new();
        {
            let mut state = engine.state.lock().unwrap();
            state.store = Some(store);
            state.config = config.clone();
            state.session_locked = false;
            state
                .query_cache
                .insert("old query".into(), json!({"vector":[1,2]}));
            config.semantic = false;
            engine.apply_config(&mut state, config.clone()).unwrap();
            assert!(state.query_cache.is_empty());
            let vector: Vec<u8> = state
                .store
                .as_ref()
                .unwrap()
                .db
                .query_row("SELECT vector FROM chunks WHERE file_id=?1", [id], |r| {
                    r.get(0)
                })
                .unwrap();
            assert_eq!(vector, vec![1, 2, 3, 4]);
        }
        let result = engine.search("orbital mechanics", true).await.unwrap();
        assert_eq!(result["results"][0]["name"], "report.txt");
        assert_eq!(result["semantic"], false);
        assert!(engine.worker.lock().await.is_none());
        engine
            .state
            .lock()
            .unwrap()
            .query_cache
            .insert("private query".into(), json!({}));
        engine.lock();
        assert!(engine.state.lock().unwrap().query_cache.is_empty());
    }

    #[test]
    fn full_image_catalogue_makes_room_for_folders_and_documents() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("sources");
        let images = root.join("images");
        std::fs::create_dir_all(&images).unwrap();
        let engine = Engine::new();
        let config = Config {
            roots: vec![root.clone()],
            max_files: 6,
            paused: true,
            ..Config::default()
        };
        let mut store = Store::open(&dir.path().join("index.db"), &[42; 32]).unwrap();
        store.set_config(&config).unwrap();
        for i in 0..6 {
            let path = images.join(format!("{i}.png"));
            std::fs::write(&path, "fixture").unwrap();
            store
                .upsert(
                    &path,
                    "photo",
                    path.file_name().unwrap().to_str().unwrap(),
                    0,
                    7,
                    1,
                    i + 1,
                )
                .unwrap();
        }
        let course = root.join("NLP");
        std::fs::create_dir(&course).unwrap();
        std::fs::write(course.join("lecture.pdf"), "fixture PDF").unwrap();
        {
            let mut s = engine.state.lock().unwrap();
            s.store = Some(store);
            s.config = config;
        }
        scan_paths(&engine, &root, 0).unwrap();
        let state = engine.state.lock().unwrap();
        let store = state.store.as_ref().unwrap();
        assert_eq!(store.paths().unwrap().len(), 6);
        assert_eq!(
            store
                .search(&Query::parse("npl", chrono::Local::now()), &[], 10)
                .unwrap()[0]
                .path,
            course.to_string_lossy()
        );
        assert_eq!(
            store
                .search(&Query::parse("pdf lecture", chrono::Local::now()), &[], 10)
                .unwrap()[0]
                .name,
            "lecture.pdf"
        );
    }

    #[test]
    fn selected_config_subfolder_is_searchable_while_parent_waits_for_review() {
        let dir = tempfile::tempdir().unwrap();
        let documents = dir.path().join("Documents");
        let hypr = documents.join("dotfiles/.config/hypr");
        std::fs::create_dir_all(&hypr).unwrap();
        std::fs::write(
            hypr.join("general.lua"),
            "input = { kb_layout = 'us,ru' }\napi_key = 'never-index-this'\n",
        )
        .unwrap();
        std::fs::write(hypr.join("colors.conf"), "background = 'blue'").unwrap();
        std::fs::write(documents.join("unapproved.txt"), "private document").unwrap();
        let mut config = Config {
            roots: vec![documents.clone(), hypr.clone()],
            source_reviews: vec![config::SourceReview {
                path: documents.clone(),
                files: 10_000,
            }],
            ..Config::default()
        };
        config.validate().unwrap();
        assert_eq!(config.roots.len(), 2);
        assert!(!config.readable(&documents.join("unapproved.txt")));
        assert!(config.readable(&hypr.join("general.lua")));
        assert_eq!(config::kind(&hypr.join("general.lua")), "config");
        let engine = Engine::new();
        let mut store = Store::open(&dir.path().join("index.db"), &[42; 32]).unwrap();
        store.set_config(&config).unwrap();
        {
            let mut state = engine.state.lock().unwrap();
            state.config = config;
            state.store = Some(store);
        }
        scan_paths(&engine, &hypr, 0).unwrap();
        scan_paths(&engine, &documents, 0).unwrap();
        assert_eq!(
            engine.status()["files"],
            3,
            "the held parent must not prune an explicitly selected child"
        );
        assert_eq!(
            engine.status()["pending"],
            2,
            "model inference still waits for its selected mode"
        );
        let state = engine.state.lock().unwrap();
        let store = state.store.as_ref().unwrap();
        let query = Query::parse("config for keyboard hypr", chrono::Local::now());
        let matches = store.search(&query, &[], 10).unwrap();
        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0].name, "general.lua");
        let secret = Query::parse("never-index-this", chrono::Local::now());
        assert!(store.search(&secret, &[], 10).unwrap().is_empty());
    }

    #[test]
    fn large_folder_waits_for_a_persistent_choice_and_old_entries_are_removed() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("Documents");
        let project = root.join("large-project");
        std::fs::create_dir_all(project.join(".git")).unwrap();
        std::fs::write(root.join("notes.md"), "notes").unwrap();
        for n in 0..crate::sources::LARGE_FOLDER_FILES {
            std::fs::write(project.join(format!("{n}.txt")), "source").unwrap();
        }
        let engine = Engine::new();
        let config = Config {
            roots: vec![root.clone()],
            ..Config::default()
        };
        let mut store = Store::open(&dir.path().join("index.db"), &[42; 32]).unwrap();
        store.set_config(&config).unwrap();
        store
            .upsert(&project.join("0.txt"), "file", "0.txt", 0, 6, 1, 1)
            .unwrap();
        {
            let mut s = engine.state.lock().unwrap();
            s.config = config.clone();
            s.store = Some(store);
        }
        scan_paths(&engine, &root, 0).unwrap();
        assert_eq!(
            engine.status()["files"],
            2,
            "held files must not consume the index"
        );
        assert_eq!(
            engine.status()["config"]["source_reviews"][0]["path"],
            project.to_string_lossy().as_ref()
        );
        {
            let s = engine.state.lock().unwrap();
            assert_eq!(
                s.store.as_ref().unwrap().config().unwrap().source_reviews,
                s.config.source_reviews
            );
            assert!(!s.watch_dirs.iter().any(|p| p.starts_with(&project)));
        }
        // A stale settings form changing a different option cannot dismiss the review.
        engine.configure(config).unwrap();
        assert_eq!(
            engine.status()["config"]["source_reviews"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        let included = engine.review_source(&project, true).unwrap();
        assert_eq!(included["config"]["source_reviews"], json!([]));
        assert_eq!(included["config"]["large_folders"], json!([project]));
        let generation = engine.state.lock().unwrap().generation;
        scan_paths(&engine, &project.join("0.txt"), generation).unwrap();
        assert_eq!(engine.status()["files"], 3);
        assert!(
            engine.review_source(&project, false).is_err(),
            "stale choices must not change the config"
        );
        let saved = engine
            .state
            .lock()
            .unwrap()
            .store
            .as_ref()
            .unwrap()
            .config()
            .unwrap();
        assert!(crate::sources::discover(
            &root,
            &saved,
            crate::sources::LARGE_FOLDER_FILES,
            || false
        )
        .unwrap()
        .is_empty());

        // Excluding a pending source persists the choice and prunes legacy data too.
        {
            let mut s = engine.state.lock().unwrap();
            s.config.large_folders.clear();
            s.config.source_reviews.push(config::SourceReview {
                path: project.clone(),
                files: 10_000,
            });
        }
        let excluded = engine.review_source(&project, false).unwrap();
        assert_eq!(excluded["files"], 2);
        assert_eq!(excluded["config"]["source_reviews"], json!([]));
        let saved = engine
            .state
            .lock()
            .unwrap()
            .store
            .as_ref()
            .unwrap()
            .config()
            .unwrap();
        assert_eq!(saved.excludes, vec![project]);
        assert!(crate::sources::discover(
            &root,
            &saved,
            crate::sources::LARGE_FOLDER_FILES,
            || false
        )
        .unwrap()
        .is_empty());
    }

    #[test]
    fn ignore_edits_remove_old_results_and_watches_and_can_be_undone() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("project");
        std::fs::create_dir_all(root.join("generated-cache/nested")).unwrap();
        std::fs::write(root.join("generated-cache/nested/copy.py"), "copy").unwrap();
        std::fs::write(root.join("notes.md"), "notes").unwrap();
        let engine = Engine::new();
        let config = Config {
            roots: vec![root.clone()],
            ..Config::default()
        };
        let mut store = Store::open(&dir.path().join("index.db"), &[42; 32]).unwrap();
        store.set_config(&config).unwrap();
        {
            let mut s = engine.state.lock().unwrap();
            s.config = config;
            s.store = Some(store);
        }
        scan_paths(&engine, &root, 0).unwrap();
        assert_eq!(engine.status()["files"], 5);
        std::fs::write(root.join(".gitignore"), "/generated-cache/\n").unwrap();
        scan_paths(&engine, &root, 0).unwrap();
        assert_eq!(engine.status()["files"], 3);
        assert_eq!(
            engine.state.lock().unwrap().watch_dirs,
            BTreeSet::from([root.clone()])
        );
        // A direct changed-file event must obey the same parent rules.
        scan_paths(&engine, &root.join("generated-cache/nested/copy.py"), 0).unwrap();
        assert_eq!(engine.status()["files"], 3);
        std::fs::remove_file(root.join(".gitignore")).unwrap();
        scan_paths(&engine, &root, 0).unwrap();
        assert_eq!(engine.status()["files"], 5);
        assert!(engine
            .state
            .lock()
            .unwrap()
            .watch_dirs
            .contains(&root.join("generated-cache/nested")));
    }

    #[test]
    fn generated_trees_do_not_consume_limits_or_directory_watches() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path().join("project");
        std::fs::create_dir_all(root.join("src")).unwrap();
        std::fs::write(root.join("README.md"), "project notes").unwrap();
        std::fs::write(root.join("src/main.py"), "print('source')").unwrap();
        for name in [
            "node_modules",
            ".venv",
            ".next",
            "artifacts",
            "python-tools",
            ".conda-eval",
        ] {
            let generated = root.join(name);
            std::fs::create_dir_all(generated.join("nested")).unwrap();
            for n in 0..32 {
                std::fs::write(generated.join(format!("nested/{n}.py")), "generated").unwrap();
            }
            if name == "python-tools" {
                std::fs::write(generated.join("pyvenv.cfg"), "home = /usr/bin").unwrap();
            }
            if name == ".conda-eval" {
                std::fs::create_dir(generated.join("conda-meta")).unwrap();
            }
        }
        let engine = Engine::new();
        let config = Config {
            roots: vec![root.clone()],
            max_files: 4,
            ..Config::default()
        };
        let mut store = Store::open(&dir.path().join("index.db"), &[42; 32]).unwrap();
        store.set_config(&config).unwrap();
        {
            let mut s = engine.state.lock().unwrap();
            s.config = config;
            s.store = Some(store);
        }
        scan_paths(&engine, &root, 0).unwrap();
        assert_eq!(engine.status()["files"], 4);
        assert_eq!(engine.status()["problem"], "");
        {
            let s = engine.state.lock().unwrap();
            assert_eq!(
                s.watch_dirs,
                BTreeSet::from([root.clone(), root.join("src")])
            );
            assert!(s
                .store
                .as_ref()
                .unwrap()
                .paths()
                .unwrap()
                .iter()
                .any(|(_, p)| p.ends_with("src/main.py")));
        }
        // Direct watcher notifications cannot bypass the excluded parent.
        scan_paths(&engine, &root.join("python-tools/nested/0.py"), 0).unwrap();
        assert_eq!(engine.status()["files"], 4);
        // An environment created in a previously indexed directory removes old entries and watches.
        std::fs::write(root.join("src/pyvenv.cfg"), "home = /usr/bin").unwrap();
        scan_paths(&engine, &root.join("src"), 0).unwrap();
        assert_eq!(engine.status()["files"], 2);
        assert_eq!(
            engine.state.lock().unwrap().watch_dirs,
            BTreeSet::from([root])
        );
    }
}
