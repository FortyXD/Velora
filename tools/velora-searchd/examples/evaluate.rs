//! Reproducible synthetic retrieval evaluation. Never opens a personal index or keyring.
use anyhow::Result;
use serde_json::{json, Value};
use std::{
    io::Read,
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};
use velora_searchd::{
    config::Config,
    engine::{self, Engine},
    store::Store,
};

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let dataset = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("evaluation");
    let corpus: Vec<Value> = serde_json::from_slice(&std::fs::read(dataset.join("corpus.json"))?)?;
    let queries: Vec<Value> = std::fs::read_to_string(dataset.join("queries.jsonl"))?
        .lines()
        .map(serde_json::from_str)
        .collect::<Result<_, _>>()?;
    let temporary = tempfile::tempdir()?;
    let root = temporary.path().join("corpus");
    std::fs::create_dir(&root)?;
    for item in &corpus {
        let folder = root.join(item["id"].as_str().unwrap());
        std::fs::create_dir(&folder)?;
        std::fs::write(folder.join("README.md"), item["text"].as_str().unwrap())?;
        std::fs::write(
            folder.join("pyproject.toml"),
            "[project]\nname='evaluation-fixture'\n",
        )?;
    }
    let mut key = [0u8; 32];
    std::fs::File::open("/dev/urandom")?.read_exact(&mut key)?;
    let engine = Engine::new();
    let config = Config {
        roots: vec![root.clone()],
        semantic: true,
        media: false,
        ..Config::default()
    };
    let mut store = Store::open(&temporary.path().join("index.db"), &key)?;
    store.set_config(&config)?;
    {
        let mut s = engine.state.lock().unwrap();
        s.store = Some(store);
        s.config = config;
        s.battery = false;
        s.idle = true;
        s.pending.insert(root.clone());
    }
    let started = Instant::now();
    let background = tokio::spawn(engine::background(Arc::clone(&engine)));
    engine.wake.notify_one();
    tokio::time::timeout(Duration::from_secs(180), async {
        loop {
            let s = engine.status();
            if s["files"].as_u64().unwrap_or(0) >= corpus.len() as u64 * 3
                && s["pending"] == 0
                && s["scanning"] == false
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    })
    .await?;
    anyhow::ensure!(
        engine.status()["failed"] == 0,
        "Fixture indexing failed: {}",
        engine.status()
    );
    let indexing_ms = started.elapsed().as_secs_f64() * 1000.0;
    for item in &corpus {
        engine.record(
            &root.join(item["id"].as_str().unwrap()),
            "fixture",
            "terminal",
        )?;
    }
    let mut runs = vec![];
    for semantic in [false, true] {
        if semantic
            && !velora_searchd::data_dir()
                .join("models/manifest.json")
                .exists()
        {
            continue;
        }
        // Warm up separately. Cold start is measured by the media integration test.
        engine.search("папка нейронные сети", semantic).await?;
        for split in ["dev", "test"] {
            let mut recalls = 0.0;
            let mut ndcg = 0.0;
            let mut latency = vec![];
            let mut failures = vec![];
            for item in queries.iter().filter(|q| q["split"] == split) {
                let start = Instant::now();
                let answer = engine
                    .search(item["query"].as_str().unwrap(), semantic)
                    .await?;
                latency.push(start.elapsed().as_secs_f64() * 1000.0);
                let expected = item["expected"].as_array().unwrap();
                let found: Vec<String> = answer["results"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .take(10)
                    .filter_map(|h| {
                        PathBuf::from(h["path"].as_str()?)
                            .strip_prefix(&root)
                            .ok()
                            .map(|p| p.to_string_lossy().into_owned())
                    })
                    .collect();
                let rank = found
                    .iter()
                    .position(|p| expected.iter().any(|e| e.as_str() == Some(p)));
                if rank.is_some_and(|r| r < 5) {
                    recalls += 1.0;
                } else {
                    failures.push(json!({"query":item["query"],"expected":expected,"found":found}));
                }
                if let Some(rank) = rank {
                    ndcg += 1.0 / ((rank + 2) as f64).log2();
                }
            }
            latency.sort_by(f64::total_cmp);
            let count = latency.len();
            runs.push(json!({"mode":if semantic{"hybrid"}else{"lexical"},"split":split,"queries":count,"recall_at_5":recalls/count as f64,"ndcg_at_10":ndcg/count as f64,"p95_ms":latency[((count as f64*0.95).ceil() as usize-1).min(count-1)],"failures":failures}));
        }
    }
    let idle = if std::env::args().any(|arg| arg == "--idle") {
        // Let both model and ANN TTLs expire, then measure a quiet 30-second window.
        tokio::time::sleep(Duration::from_secs(95)).await;
        let ticks = || -> Result<u64> {
            let stat = std::fs::read_to_string("/proc/self/stat")?;
            let fields: Vec<_> = stat
                .rsplit_once(')')
                .unwrap()
                .1
                .split_whitespace()
                .collect();
            Ok(fields[11].parse::<u64>()? + fields[12].parse::<u64>()?)
        };
        let before = ticks()?;
        let start = Instant::now();
        tokio::time::sleep(Duration::from_secs(30)).await;
        let elapsed = start.elapsed().as_secs_f64();
        let cpu_seconds =
            (ticks()? - before) as f64 / unsafe { libc::sysconf(libc::_SC_CLK_TCK) } as f64;
        let status = std::fs::read_to_string("/proc/self/status")?;
        let rss_kib = status
            .lines()
            .find(|line| line.starts_with("VmRSS:"))
            .and_then(|line| line.split_whitespace().nth(1))
            .and_then(|n| n.parse::<u64>().ok());
        Some(
            json!({"after_ttl_seconds":95,"window_seconds":elapsed,"cpu_seconds":cpu_seconds,"one_core_percent":100.0*cpu_seconds/elapsed,"rss_kib":rss_kib,"worker_unloaded":engine.worker.lock().await.is_none(),"ann_unloaded":engine.state.lock().unwrap().ann.is_empty()}),
        )
    } else {
        None
    };
    println!(
        "{}",
        serde_json::to_string_pretty(
            &json!({"dataset":"synthetic-v1; not a personal-corpus benchmark","indexing_ms":indexing_ms,"status":engine.status(),"runs":runs,"idle":idle})
        )?
    );
    engine.lock();
    background.abort();
    Ok(())
}
