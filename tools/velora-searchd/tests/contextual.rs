use std::path::Path;
use velora_searchd::{config::Config, engine::Engine, query::Query, store::Store};

fn fixture(root: &Path) -> Store {
    let mut store = Store::open(&root.join("index.db"), &[47; 32]).unwrap();
    let entries = [
        ("SHAD", "folder", ""),
        ("SHAD/NLP", "folder", ""),
        (
            "SHAD/NLP/task01/homework.ipynb",
            "file",
            "Word embeddings and token classification. Обработка естественного языка.",
        ),
        (
            "SHAD/NLP/task10/homework.ipynb",
            "file",
            "Tenth assignment about language.",
        ),
        ("other/NLP/hw1.ipynb", "file", "Unrelated homework."),
        ("Velora", "folder", ""),
        ("Velora/.config/hypr", "folder", ""),
        (
            "Velora/.config/hypr/general.lua",
            "config",
            "font_hinting = true; kb_layout = 'us'",
        ),
        (
            "other/.config/hypr/general.lua",
            "config",
            "font_hinting = false",
        ),
        (
            "Velora/notes/readme.md",
            "file",
            "An article mentioning Hypr configuration, not settings.",
        ),
        ("Arcturus", "folder", ""),
        ("Arcturus/Rust", "folder", ""),
        (
            "Arcturus/Rust/lab02/instructions.md",
            "file",
            "Implement a concurrent queue.",
        ),
        (
            "Arcturus/Rust/lab20/instructions.md",
            "file",
            "Advanced concurrency.",
        ),
        (
            "Sirius/Rust/lab02/instructions.md",
            "file",
            "Unrelated concurrency.",
        ),
        ("Atlas", "folder", ""),
        ("Atlas/unrelated.md", "file", "Unrelated content"),
        ("Boreal", "folder", ""),
        ("Boreal/manifest.md", "file", "ATLS shipping manifest"),
    ];
    for (n, (relative, kind, text)) in entries.iter().enumerate() {
        let path = root.join(relative);
        if *kind == "folder" {
            std::fs::create_dir_all(&path).unwrap();
        } else {
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, text).unwrap();
        }
        let id = store
            .upsert(
                &path,
                kind,
                path.file_name().unwrap().to_str().unwrap(),
                1,
                1,
                1,
                n as u64 + 1,
            )
            .unwrap();
        if !text.is_empty() {
            store
                .replace_chunks(id, "fixture", &[(text.to_string(), None, None, None)])
                .unwrap();
        }
    }
    store
}

#[tokio::test]
async fn fuzzy_contextual_queries_use_the_first_pass_without_a_model() {
    let temp = tempfile::tempdir().unwrap();
    let store = fixture(temp.path());
    let engine = Engine::new();
    {
        let mut s = engine.state.lock().unwrap();
        s.config = Config {
            roots: vec![temp.path().to_owned()],
            ..Default::default()
        };
        s.store = Some(store);
        s.session_locked = false;
    }
    for (query, expected) in [
        ("shad nlp hw1", "SHAD/NLP/task01/homework.ipynb"),
        ("shad nlp", "SHAD/NLP"),
        ("hw01 nlp shad", "SHAD/NLP/task01/homework.ipynb"),
        ("shad npl hw1", "SHAD/NLP/task01/homework.ipynb"),
        ("шад nlp домашняя 1", "SHAD/NLP/task01/homework.ipynb"),
        (
            "шад обработка языка первая домашка",
            "SHAD/NLP/task01/homework.ipynb",
        ),
        ("velora folder hupr config", "Velora/.config/hypr"),
        ("config hupr velora folder", "Velora/.config/hypr"),
        (
            "velora конфиг font hnting",
            "Velora/.config/hypr/general.lua",
        ),
        ("arcturus rust lab2", "Arcturus/Rust/lab02/instructions.md"),
        ("rust arcturus lab02", "Arcturus/Rust/lab02/instructions.md"),
        (
            "arcturs rust concurrent queue",
            "Arcturus/Rust/lab02/instructions.md",
        ),
        ("atls shipping", "Boreal/manifest.md"),
    ] {
        let result = engine.search(query, false).await.unwrap();
        assert_eq!(
            result["results"][0]["path"],
            temp.path().join(expected).to_string_lossy().as_ref(),
            "{query}: {result}"
        );
        assert_eq!(result["results"][0]["partial"], false, "{query}: {result}");
        assert!(engine.worker.lock().await.is_none());
    }
    let corrected = engine
        .search("velora folder hupr config", false)
        .await
        .unwrap();
    assert!(corrected["results"][0]["corrections"]
        .as_array()
        .unwrap()
        .iter()
        .any(|c| c["from"] == "hupr" && c["to"] == "hypr"));
    let partial = engine
        .search("velora hypr unavailablefeature", false)
        .await
        .unwrap();
    assert_eq!(partial["results"][0]["partial"], true, "{partial}");
    assert!(partial["results"][0]["unmatched_terms"]
        .as_array()
        .unwrap()
        .contains(&serde_json::json!("unavailablefeature")));
    for query in ["shad nlp hw100", "arcturus rust lab3"] {
        assert_eq!(
            engine.search(query, false).await.unwrap()["results"],
            serde_json::json!([]),
            "{query}"
        );
    }
}

#[tokio::test]
async fn explicit_paths_are_validated_and_never_broadened() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("numbered 2 source");
    std::fs::create_dir(&root).unwrap();
    let store = fixture(&root);
    let engine = Engine::new();
    {
        let mut s = engine.state.lock().unwrap();
        s.store = Some(store);
        s.config = Config {
            roots: vec![root.clone()],
            ..Default::default()
        };
        s.session_locked = false;
    }
    // A directory number outside the selected course cannot satisfy hw2.
    assert_eq!(
        engine.search("shad nlp hw2", false).await.unwrap()["results"],
        serde_json::json!([])
    );
    let selected = root.join("Velora");
    let request = format!("\"{}\" config hupr", selected.display());
    let hits = engine.search(&request, false).await.unwrap();
    assert_eq!(
        hits["results"][0]["path"],
        root.join("Velora/.config/hypr/general.lua")
            .to_string_lossy()
            .as_ref()
    );
    assert!(hits["results"]
        .as_array()
        .unwrap()
        .iter()
        .all(|hit| Path::new(hit["path"].as_str().unwrap()).starts_with(&selected)));
    assert_eq!(
        engine
            .search(
                &format!("'{}' impossiblefeature", selected.display()),
                false
            )
            .await
            .unwrap()["results"],
        serde_json::json!([])
    );
    assert!(engine
        .search(&format!("{} config", temp.path().display()), false)
        .await
        .is_err());
    assert!(engine
        .search(&format!("\"{}/missing\" config", root.display()), false)
        .await
        .is_err());
    let exact = root.join("SHAD/NLP/task01/homework.ipynb");
    assert_eq!(
        engine
            .search(&format!("\"{}\"", exact.display()), false)
            .await
            .unwrap()["results"][0]["path"],
        exact.to_string_lossy().as_ref()
    );
    let home = std::env::var_os("HOME").unwrap();
    let parsed = Query::parse("\"~/Project with spaces\" config", chrono::Local::now());
    assert_eq!(
        parsed.paths,
        vec![std::path::PathBuf::from(home).join("Project with spaces")]
    );
    assert_eq!(parsed.text, "");
    assert_eq!(parsed.kind.as_deref(), Some("config"));
}

#[test]
fn vocabulary_and_cached_results_follow_deletions_and_updates() {
    let temp = tempfile::tempdir().unwrap();
    let mut store = fixture(temp.path());
    let path = temp.path().join("Arcturus/Rust/lab02/instructions.md");
    let q = Query::parse("arcturus rust concurrent queue", chrono::Local::now());
    assert!(!store.search(&q, &[], 10).unwrap().is_empty());
    let id: i64 = store
        .db
        .query_row(
            "SELECT id FROM files WHERE path=?1",
            [path.to_str().unwrap()],
            |r| r.get(0),
        )
        .unwrap();
    store
        .replace_chunks(id, "changed", &[("Memory safety".into(), None, None, None)])
        .unwrap();
    assert!(store.search(&q, &[], 10).unwrap().is_empty());
    assert_eq!(
        store
            .db
            .query_row(
                "SELECT count(*) FROM lexemes WHERE word='concurrent'",
                [],
                |r| r.get::<_, i64>(0)
            )
            .unwrap(),
        0
    );
    store.db.execute("DELETE FROM files", []).unwrap();
    for table in ["lexemes", "lexeme_keys", "file_lexemes"] {
        assert_eq!(
            store
                .db
                .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r
                    .get::<_, i64>(0))
                .unwrap(),
            0,
            "{table}"
        );
    }
}

#[tokio::test]
async fn existing_metadata_navigation_matrix_does_not_need_a_model() {
    let suite: serde_json::Value =
        serde_json::from_str(include_str!("../evaluation/functional.json")).unwrap();
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("sources");
    for file in suite["files"].as_array().unwrap() {
        let path = root.join(file["path"].as_str().unwrap());
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, file["text"].as_str().unwrap()).unwrap();
    }
    let mut store = Store::open(&temp.path().join("index.db"), &[63; 32]).unwrap();
    for (n, entry) in walkdir::WalkDir::new(&root)
        .into_iter()
        .filter_map(Result::ok)
        .enumerate()
    {
        let path = entry.path();
        store
            .upsert(
                path,
                velora_searchd::config::kind(path),
                &entry.file_name().to_string_lossy(),
                1,
                1,
                1,
                n as u64 + 1,
            )
            .unwrap();
    }
    let engine = Engine::new();
    {
        let mut s = engine.state.lock().unwrap();
        s.store = Some(store);
        s.config = Config {
            roots: vec![root.clone()],
            ..Default::default()
        };
        s.session_locked = false;
    }
    for case in suite["queries"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|case| case["metadata"] == true)
    {
        let result = engine
            .search(case["q"].as_str().unwrap(), false)
            .await
            .unwrap();
        if let Some(expected) = case["expected"].as_str() {
            assert_eq!(
                result["results"][0]["path"],
                root.join(expected).to_string_lossy().as_ref(),
                "{}: {result}",
                case["q"]
            );
        } else {
            assert_eq!(
                result["results"],
                serde_json::json!([]),
                "{}: {result}",
                case["q"]
            );
        }
    }
    assert!(engine.worker.lock().await.is_none());
}

#[tokio::test]
async fn path_typo_repairs_survive_noisy_translations_and_prefix_budgets() {
    fn add(
        store: &mut Store,
        root: &Path,
        path: &str,
        kind: &str,
        text: &str,
        ordinal: u64,
    ) -> i64 {
        let path = root.join(path);
        if kind == "folder" {
            std::fs::create_dir_all(&path).unwrap();
        } else {
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(&path, text).unwrap();
        }
        let id = store
            .upsert(
                &path,
                kind,
                path.file_name().unwrap().to_str().unwrap(),
                1,
                text.len() as u64,
                1,
                ordinal,
            )
            .unwrap();
        if !text.is_empty() {
            store
                .replace_chunks(id, "fixture", &[(text.to_owned(), None, None, None)])
                .unwrap();
        }
        id
    }
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let mut store = Store::open(&root.join("index.db"), &[71; 32]).unwrap();
    add(&mut store, root, "Velora", "folder", "", 1);
    add(
        &mut store,
        root,
        "Velora/.config/quickshell/translations",
        "folder",
        "",
        2,
    );
    let mut noise = String::from("hpr hur hup upr упр хпр хур хуп ");
    for letter in 'а'..='я' {
        noise.push_str(&format!("{letter}упр "));
    }
    // Insert many older prefix lexemes before the actual path word. The exact
    // repaired term must survive the shared64-ID expansion budget regardless
    // of insertion order or the number of unrelated prefix completions.
    for prefix in ["hpr", "hur", "hup", "upr"] {
        for n in 0..40_u8 {
            noise.push_str(&format!(
                "{prefix}prefix{}{} ",
                (b'a' + n / 26) as char,
                (b'a' + n % 26) as char
            ));
        }
    }
    for n in 0..48 {
        add(
            &mut store,
            root,
            &format!("Velora/.config/quickshell/translations/ru_{n}.json"),
            "config",
            &noise,
            n + 3,
        );
    }
    add(&mut store, root, "Velora/.config/hypr", "folder", "", 100);
    let target = add(
        &mut store,
        root,
        "Velora/.config/hypr/general.lua",
        "config",
        "kb_layout = us",
        101,
    );
    let mut q = Query::parse("velora hupr", chrono::Local::now());
    store.prepare_query(&mut q).unwrap();
    assert!(
        q.terms()
            .iter()
            .any(|group| group.iter().any(|word| word == "hypr")),
        "{:?}",
        q.terms()
    );
    assert!(
        store.lexical_candidates(&q).unwrap().contains(&target),
        "exact repairs must survive prefix saturation"
    );
    // Cross-script, path-backed transliteration remains available even with an
    // unrelated same-script content repair: otchett -> Отчёт.
    add(&mut store, root, "Velora/Отчёт", "folder", "", 102);
    add(
        &mut store,
        root,
        "Velora/notes.md",
        "file",
        "otchet report noise",
        103,
    );
    let engine = Engine::new();
    {
        let mut s = engine.state.lock().unwrap();
        s.store = Some(store);
        s.config = Config {
            roots: vec![root.to_owned()],
            ..Default::default()
        };
        s.session_locked = false;
    }
    for query in [
        "velora folder hupr config",
        "config hupr velora folder",
        "velora папка hupr конфиг",
    ] {
        let result = engine.search(query, false).await.unwrap();
        assert_eq!(
            result["results"][0]["path"],
            root.join("Velora/.config/hypr").to_string_lossy().as_ref(),
            "{query}: {result}"
        );
        assert!(
            result["results"][0]["corrections"]
                .as_array()
                .unwrap()
                .iter()
                .any(|c| c["from"] == "hupr" && c["to"] == "hypr"),
            "{result}"
        );
    }
    let result = engine.search("velora folder otchett", false).await.unwrap();
    assert_eq!(
        result["results"][0]["path"],
        root.join("Velora/Отчёт").to_string_lossy().as_ref(),
        "{result}"
    );
    assert!(engine.worker.lock().await.is_none());
}
