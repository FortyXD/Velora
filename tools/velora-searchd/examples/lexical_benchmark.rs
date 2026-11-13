//! `cargo run --release --offline -p velora-searchd --example lexical_benchmark -- 10000 100000`
//! Synthetic private temporary sources only. No model, network or personal files.
use anyhow::Result;
use serde_json::{json, Value};
use std::{
    path::Path,
    time::{Duration, Instant},
};
use velora_searchd::{config::Config, engine::Engine, store::Store};

fn cpu_seconds() -> f64 {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
    if unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) } != 0 {
        return 0.0;
    }
    let u = unsafe { usage.assume_init() };
    (u.ru_utime.tv_sec + u.ru_stime.tv_sec) as f64
        + (u.ru_utime.tv_usec + u.ru_stime.tv_usec) as f64 / 1e6
}
fn rss_kib() -> u64 {
    std::fs::read_to_string("/proc/self/status")
        .unwrap_or_default()
        .lines()
        .find_map(|l| {
            l.strip_prefix("VmRSS:")
                .and_then(|s| s.split_whitespace().next())
                .and_then(|n| n.parse().ok())
        })
        .unwrap_or(0)
}
fn distribution(mut samples: Vec<f64>) -> Value {
    samples.sort_by(f64::total_cmp);
    json!({"p50_ms":samples[samples.len()/2],"p95_ms":samples[((samples.len() as f64*0.95).ceil() as usize-1).min(samples.len()-1)],"max_ms":samples.last(),"samples":samples.len()})
}
fn insert(
    store: &mut Store,
    root: &Path,
    relative: &str,
    kind: &str,
    text: &str,
    ordinal: u64,
) -> Result<()> {
    let path = root.join(relative);
    if kind == "folder" {
        std::fs::create_dir_all(&path)?;
    } else {
        std::fs::create_dir_all(path.parent().unwrap())?;
        std::fs::write(&path, text)?;
    }
    let id = store.upsert(
        &path,
        kind,
        path.file_name().unwrap().to_str().unwrap(),
        1,
        text.len() as u64,
        1,
        ordinal,
    )?;
    if !text.is_empty() {
        // The enclosing benchmark transaction amortizes ordinary ingest commits.
        store.db.execute(
            "INSERT INTO chunks(file_id,text) VALUES(?1,?2)",
            rusqlite::params![id, text],
        )?;
        store.db.execute(
            "INSERT INTO content(rowid,text) VALUES(?1,?2)",
            rusqlite::params![store.db.last_insert_rowid(), text],
        )?;
        velora_searchd::lexical::index(&store.db, id, 1, text, false)?;
    }
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let sizes = if args.is_empty() {
        vec![10000, 100000]
    } else {
        args.iter()
            .map(|n| n.parse::<usize>())
            .collect::<std::result::Result<Vec<_>, _>>()?
    };
    let mut reports = Vec::new();
    for size in sizes {
        anyhow::ensure!((100..=100000).contains(&size), "Use 100..100000 objects");
        let temp = tempfile::tempdir()?;
        let root = temp.path().join("sources");
        let db = temp.path().join("index.db");
        let started = Instant::now();
        let mut store = Store::open(&db, &[57; 32])?;
        store.db.execute_batch("BEGIN IMMEDIATE;")?;
        let fixtures = [
            ("SHAD", "folder", ""),
            ("SHAD/NLP", "folder", ""),
            (
                "SHAD/NLP/task01/homework.ipynb",
                "file",
                "Word embeddings and token classification",
            ),
            ("SHAD/NLP/task10/homework.ipynb", "file", "Tenth assignment"),
            ("Other/NLP/hw1.ipynb", "file", "Unrelated assignment"),
            ("Velora", "folder", ""),
            ("Velora/.config/hypr", "folder", ""),
            (
                "Velora/.config/hypr/general.lua",
                "config",
                "font_hinting = true; kb_layout = 'us'",
            ),
            (
                "Other/.config/hypr/general.lua",
                "config",
                "font_hinting = false",
            ),
            ("Arcturus", "folder", ""),
            ("Arcturus/Rust", "folder", ""),
            (
                "Arcturus/Rust/lab02/instructions.md",
                "file",
                "Implement a concurrent queue",
            ),
            (
                "Arcturus/Rust/lab20/instructions.md",
                "file",
                "Advanced concurrency",
            ),
            (
                "Sirius/Rust/lab02/instructions.md",
                "file",
                "An unrelated concurrent queue",
            ),
        ];
        for (i, (path, kind, text)) in fixtures.iter().enumerate() {
            insert(&mut store, &root, path, kind, text, i as u64 + 1)?;
        }
        for i in fixtures.len()..size {
            insert(
                &mut store,
                &root,
                &format!("collections/Project{}/notes/item{i}.md", i % 100),
                "file",
                if i % 10 == 0 {
                    "Project notes about configuration, homework and concurrent systems"
                } else {
                    ""
                },
                i as u64 + 1,
            )?;
            if i % 10000 == 0 {
                eprintln!("Indexed {i}/{size} synthetic objects");
            }
        }
        store
            .db
            .execute_batch("COMMIT; PRAGMA wal_checkpoint(TRUNCATE);")?;
        let indexing_seconds = started.elapsed().as_secs_f64();
        drop(store);
        let cases = [
            ("shad nlp hw1", "SHAD/NLP/task01/homework.ipynb"),
            ("shad npl hw1", "SHAD/NLP/task01/homework.ipynb"),
            ("velora folder hupr config", "Velora/.config/hypr"),
            ("config hupr velora folder", "Velora/.config/hypr"),
            (
                "velora config font hnting",
                "Velora/.config/hypr/general.lua",
            ),
            ("arcturus rust lab2", "Arcturus/Rust/lab02/instructions.md"),
            (
                "arcturs rust concurrent queue",
                "Arcturus/Rust/lab02/instructions.md",
            ),
            ("shad word embeddings", "SHAD/NLP/task01/homework.ipynb"),
        ];
        let engine = Engine::new();
        let mut cold = Vec::new();
        let mut startup = Vec::new();
        let mut quality = Vec::new();
        for (query, expected) in cases {
            let start = Instant::now();
            let store = Store::open(&db, &[57; 32])?;
            startup.push(start.elapsed().as_secs_f64() * 1000.0);
            {
                let mut s = engine.state.lock().unwrap();
                s.store = Some(store);
                s.session_locked = false;
                s.config = Config {
                    roots: vec![root.clone()],
                    ..Default::default()
                };
            }
            let start = Instant::now();
            let result = engine.search(query, false).await?;
            cold.push(start.elapsed().as_secs_f64() * 1000.0);
            let wanted = root.join(expected).to_string_lossy().into_owned();
            let rank = result["results"]
                .as_array()
                .unwrap()
                .iter()
                .position(|h| h["path"] == wanted);
            quality.push(json!({"query":query,"rank":rank.map(|n|n+1),"recall5":rank.is_some_and(|n|n<5),"ndcg10":rank.filter(|n|*n<10).map_or(0.0,|n|1.0/((n+2)as f64).log2())}));
        }
        let mut uncached = Vec::new();
        let mut cached = Vec::new();
        for _ in 0..5 {
            for (query, _) in cases {
                engine
                    .state
                    .lock()
                    .unwrap()
                    .store
                    .as_ref()
                    .unwrap()
                    .clear_search_caches();
                let start = Instant::now();
                engine.search(query, false).await?;
                uncached.push(start.elapsed().as_secs_f64() * 1000.0);
                let start = Instant::now();
                engine.search(query, false).await?;
                cached.push(start.elapsed().as_secs_f64() * 1000.0);
            }
        }
        let rss = rss_kib();
        let cpu = cpu_seconds();
        let idle = Instant::now();
        tokio::time::sleep(Duration::from_secs(1)).await;
        reports.push(json!({"objects":size,"indexing_seconds":indexing_seconds,"index_bytes":std::fs::metadata(&db)?.len(),
            "cold_connection_first_query":distribution(cold),"connection_open":distribution(startup),"warm_index_without_query_cache":distribution(uncached),"cached_query":distribution(cached),
            "recall5":quality.iter().filter(|q|q["recall5"]==true).count()as f64/quality.len()as f64,"ndcg10":quality.iter().map(|q|q["ndcg10"].as_f64().unwrap()).sum::<f64>()/quality.len()as f64,
            "quality":quality,"rss_kib":rss,"idle_cpu_percent":100.0*(cpu_seconds()-cpu)/idle.elapsed().as_secs_f64(),"model_started":engine.worker.lock().await.is_some()}));
    }
    let cpu = std::fs::read_to_string("/proc/cpuinfo")
        .unwrap_or_default()
        .lines()
        .find_map(|l| {
            l.strip_prefix("model name")
                .map(|s| s.trim_start_matches([' ', ':', '\t']).to_owned())
        })
        .unwrap_or_default();
    println!(
        "{}",
        serde_json::to_string_pretty(
            &json!({"cpu":cpu,"debug_build":cfg!(debug_assertions),"notes":"Synthetic end-to-end lexical Engine queries, no models. Cold means fresh encrypted connection/application caches; OS page cache is not cleared. RSS is current process RSS after ingestion and search. Idle is this query engine only, not the desktop or power draw.","reports":reports})
        )?
    );
    Ok(())
}
