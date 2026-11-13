//! End-to-end relevance checks in both metadata-only and indexed states.
use serde_json::{json, Value};
use std::{
    sync::Arc,
    time::{Duration, Instant},
};
use velora_searchd::{
    config::{self, Config},
    engine::{self, Engine},
    store::Store,
};

#[tokio::test]
#[ignore = "requires installed offline models"]
async fn functional_search_matrix() {
    let suite: Value = serde_json::from_str(include_str!("../evaluation/functional.json")).unwrap();
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("sources");
    for file in suite["files"].as_array().unwrap() {
        let path = root.join(file["path"].as_str().unwrap());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        let text = file["text"].as_str().unwrap();
        let bytes = if path.extension().is_some_and(|e| e == "ipynb") {
            json!({"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[{"cell_type":"markdown","metadata":{},"source":[text]}]}).to_string()
        } else {
            text.into()
        };
        std::fs::write(path, bytes).unwrap();
    }
    for n in 0..60 {
        let path = root.join(format!("website/messages/{n}.json"));
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(
            path,
            "{\"message\":\"Адрес платежного терминала ресторана\"}",
        )
        .unwrap();
    }
    let config = Config {
        roots: vec![root.clone()],
        ..Config::default()
    };
    let mut store = Store::open(&temp.path().join("index.db"), &[29; 32]).unwrap();
    store.set_config(&config).unwrap();
    use std::os::unix::fs::MetadataExt;
    for entry in walkdir::WalkDir::new(&root)
        .into_iter()
        .filter_map(Result::ok)
    {
        let p = entry.path();
        let m = p.metadata().unwrap();
        let id = store
            .upsert(
                p,
                config::kind(p),
                &entry.file_name().to_string_lossy(),
                m.mtime(),
                m.len(),
                m.dev(),
                m.ino(),
            )
            .unwrap();
        if p.is_dir() {
            store
                .db
                .execute("UPDATE files SET state='ready' WHERE id=?1", [id])
                .unwrap();
        }
    }
    let engine = Engine::new();
    {
        let mut s = engine.state.lock().unwrap();
        s.store = Some(store);
        s.config = config;
        s.battery = false;
        s.idle = true;
    }
    engine.apps(&json!([{"id":"kitty.desktop","name":"kitty","genericName":"Terminal emulator","comment":"A fast terminal for the command line"}]),true,true).unwrap();
    let mut rows = vec![];
    let mut failures = vec![];
    for phase in ["metadata", "indexed"] {
        let background = if phase == "indexed" {
            let task = tokio::spawn(engine::background(Arc::clone(&engine)));
            engine.wake.notify_one();
            tokio::time::timeout(Duration::from_secs(180), async {
                while engine.status()["pending"] != 0 {
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
            })
            .await
            .unwrap();
            Some(task)
        } else {
            None
        };
        for case in suite["queries"].as_array().unwrap() {
            if phase == "metadata" && case["metadata"] != true {
                continue;
            }
            let q = case["q"].as_str().unwrap();
            let start = Instant::now();
            let result = engine.search_explained(q, true, true).await.unwrap();
            let found: Vec<_> = result["results"]
                .as_array()
                .unwrap()
                .iter()
                .take(10)
                .map(|h| {
                    std::path::Path::new(h["path"].as_str().unwrap())
                        .strip_prefix(&root)
                        .unwrap_or_else(|_| std::path::Path::new(h["path"].as_str().unwrap()))
                        .to_string_lossy()
                        .into_owned()
                })
                .collect();
            let expected = case["expected"].as_str();
            let pass = expected.map_or(found.is_empty(), |path| {
                found.first().is_some_and(|first| first == path)
            });
            let mut row = json!({"phase":phase,"query":q,"expected":expected,"found":found,"pass":pass,"ms":start.elapsed().as_millis(),"semantic":result["semantic"],"problem":result["problem"]});
            eprintln!("{row}");
            row["diagnostics"] = result["diagnostics"].clone();
            if !pass {
                failures.push(format!("{phase}: {q}"));
            }
            rows.push(row);
        }
        if let Some(task) = background {
            task.abort();
        }
    }
    if let Some(path) = std::env::var_os("VELORA_LENS_EVAL_REPORT") {
        std::fs::write(path, serde_json::to_vec_pretty(&rows).unwrap()).unwrap();
    }
    engine.lock();
    assert!(
        failures.is_empty(),
        "{} / {} failed: {failures:?}",
        failures.len(),
        rows.len()
    );
}
