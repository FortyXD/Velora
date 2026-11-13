//! Opt-in integration with the actual offline models and sandbox; no personal sources.
use std::{
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};
use velora_searchd::{
    config::Config,
    engine::{self, Engine},
    store::Store,
};

#[tokio::test]
#[ignore = "requires installed offline models including the reranker"]
async fn neural_search_rejects_distractors_and_understands_cross_language_queries() {
    let tmp = tempfile::tempdir().unwrap();
    let root = tmp.path().join("sources");
    let fixtures = [
        ("SHAD/DL/03.md", "Convolutional layers learn spatial filters for image classification. A convolution slides a kernel over input pixels, with padding and stride controlling the output shape."),
        ("SHAD/DL/02.md", "Gradient descent, Adam optimization, momentum and learning rate schedules."),
        ("SHAD/NLP/task01/homework.md", "First homework for the natural language processing course. Train word embeddings, tokenize sentences and classify text documents."),
        ("SHAD/NLP/task10/homework.md", "Tenth homework for natural language processing. Build a language model."),
        ("other/NLP/task01/homework.md", "First homework for a different natural language processing course."),
        ("Downloads/DL_movie.torrent", "Download a movie. Video release, subtitles, torrent file."),
        ("other/SHAD_DL_conv_layer.md", "Deployment logs for an unrelated web server."),
        ("notes/recipes.md", "Baking bread with flour, yeast and water. Knead the dough and let it rise."),
        ("notes/travel.md", "Train tickets and hotel reservations for a trip to Berlin."),
        (".config/hypr/keyboard.conf", "input { kb_layout = us,ru; kb_options = caps:escape; repeat_delay = 300 }"),
        (".config/kitty/kitty.conf", "font_size 12\nbackground #101010\nscrollback_lines 10000\n")
    ];
    for (path, text) in fixtures {
        let path = root.join(path);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }
    // A frequent word in localization data must not crowd out the app's config.
    for n in 0..40 {
        let path = root.join(format!("website/translations/{n}.json"));
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(
            path,
            "{\"message\":\"Адрес платежного терминала для оплаты заказа в ресторане\"}",
        )
        .unwrap();
    }
    let engine = Engine::new();
    let config = Config {
        roots: vec![root.clone()],
        ..Config::default()
    };
    let mut store = Store::open(&tmp.path().join("index.db"), &[17; 32]).unwrap();
    store.set_config(&config).unwrap();
    {
        let mut s = engine.state.lock().unwrap();
        s.store = Some(store);
        s.config = config;
        s.battery = false;
        s.idle = true;
        s.pending.insert(root.clone());
    }
    engine.apps(&serde_json::json!([{"id":"kitty.desktop","name":"kitty","genericName":"Terminal emulator","comment":"A fast terminal for the command line","keywords":"terminal console shell"}]), true, true).unwrap();
    let background = tokio::spawn(engine::background(Arc::clone(&engine)));
    engine.wake.notify_one();
    tokio::time::timeout(Duration::from_secs(120), async {
        loop {
            let status = engine.status();
            if status["files"].as_i64().unwrap_or(0) >= fixtures.len() as i64
                && status["pending"] == 0
                && status["scanning"] == false
            {
                assert_eq!(status["failed"], 0, "{status}");
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    })
    .await
    .unwrap();
    let mut report = vec![];
    for (query, expected) in [
        ("shad dl conv layer", Some("03.md")),
        ("шад обработка языка первая домашка", Some("homework.md")),
        (
            "как свертка обрабатывает пиксели изображения",
            Some("03.md"),
        ),
        ("config for keyboard hypr", Some("keyboard.conf")),
        ("folder DL", Some("DL")),
        ("shad dl", Some("DL")),
        ("конфиг терминала", Some("kitty.conf")),
        ("ингредиенты для выпечки хлеба", Some("recipes.md")),
        ("japanese tax return 2035", None),
    ] {
        let start = Instant::now();
        let result = engine.search(query, true).await.unwrap();
        let found: Vec<_> = result["results"]
            .as_array()
            .unwrap()
            .iter()
            .map(|h| (&h["name"], &h["score"]))
            .collect();
        eprintln!("{query}: {found:?} ({:?})", start.elapsed());
        report.push(serde_json::json!({"query":query,"expected_name":expected,"ms":start.elapsed().as_secs_f64()*1000.0,
            "semantic":result["semantic"],"reranked":result["reranked"],"problem":result["problem"],
            "found":result["results"].as_array().unwrap().iter().map(|h|std::path::Path::new(h["path"].as_str().unwrap()).strip_prefix(&root).unwrap().to_string_lossy()).collect::<Vec<_>>() }));
        // An explicit absent identifier (e.g. year 2035) can eliminate all
        // candidates before inference; there is then nothing left to rerank.
        if expected.is_some() {
            assert_eq!(
                result["reranked"],
                !matches!(query, "folder DL" | "shad dl"),
                "{result}"
            );
        }
        if let Some(expected) = expected {
            assert_eq!(result["results"][0]["name"], expected);
            if query == "шад обработка языка первая домашка" {
                assert_eq!(
                    result["results"][0]["path"],
                    root.join("SHAD/NLP/task01/homework.md")
                        .to_string_lossy()
                        .as_ref()
                );
            }
        } else {
            assert!(result["results"].as_array().unwrap().is_empty());
        }
        assert!(result["results"]
            .as_array()
            .unwrap()
            .iter()
            .all(|h| h["name"] != "DL_movie.torrent"));
        if query == "shad dl conv layer" {
            assert!(result["results"]
                .as_array()
                .unwrap()
                .iter()
                .all(|h| std::path::Path::new(h["path"].as_str().unwrap())
                    .starts_with(root.join("SHAD"))));
        }
    }
    if let Some(path) = std::env::var_os("VELORA_LENS_NEURAL_REPORT") {
        std::fs::write(path, serde_json::to_vec_pretty(&report).unwrap()).unwrap();
    }
    engine.lock();
    background.abort();
}

#[tokio::test]
#[ignore = "requires installed offline models and the Lens Python environment"]
async fn fast_mode_restarts_inference_with_the_selected_cpu_budget() {
    let engine = Engine::new();
    let mut previous = None;
    for (fast, all_in) in [(false, false), (true, false), (false, true), (false, false)] {
        {
            let mut state = engine.state.lock().unwrap();
            state.battery = false;
            state.config.fast_indexing = fast;
            state.config.all_in = all_in;
        }
        let result = engine
            .encode(
                serde_json::json!({"method":"query", "text":"test document", "visual":false}),
                0,
            )
            .await
            .unwrap();
        let values = result["text"].as_array().unwrap();
        assert_eq!(values.len(), 384);
        if let Some(before) = &previous {
            let before: &Vec<serde_json::Value> = before;
            assert!(values
                .iter()
                .zip(before)
                .all(|(a, b)| (a.as_f64().unwrap() - b.as_f64().unwrap()).abs() < 0.0001));
        }
        previous = Some(values.clone());
        assert_eq!(
            engine.worker.lock().await.as_ref().unwrap().threads(),
            velora_searchd::worker::inference_threads(fast, all_in)
        );
    }
}

#[tokio::test]
#[ignore = "requires exported models, VELORA_LENS_PYTHON and VELORA_LENS_FIXTURES"]
async fn real_text_images_video_ocr_and_encrypted_ann() {
    let fixtures =
        PathBuf::from(std::env::var_os("VELORA_LENS_FIXTURES").expect("Set VELORA_LENS_FIXTURES"));
    let tmp = tempfile::tempdir().unwrap();
    let engine = Engine::new();
    let config = Config {
        roots: vec![fixtures.clone()],
        ..Config::default()
    };
    let mut store = Store::open(&tmp.path().join("index.db"), &[17; 32]).unwrap();
    store.set_config(&config).unwrap();
    {
        let mut s = engine.state.lock().unwrap();
        s.store = Some(store);
        s.config = config;
        s.battery = false;
        s.idle = true;
        s.pending.insert(fixtures.clone());
    }
    let background = tokio::spawn(engine::background(Arc::clone(&engine)));
    engine.wake.notify_one();
    tokio::time::timeout(Duration::from_secs(180), async {
        loop {
            let status = engine.status();
            if status["files"].as_i64().unwrap_or(0) >= 6
                && status["pending"] == 0
                && status["scanning"] == false
            {
                assert_eq!(status["failed"], 0, "{status}");
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    })
    .await
    .unwrap();
    let start = Instant::now();
    let result = engine.search("фото красный круг", true).await.unwrap();
    assert_eq!(
        result["results"][0]["name"],
        "red.png",
        "{}",
        result["results"]
            .as_array()
            .unwrap()
            .iter()
            .map(|h| (&h["name"], &h["score"], &h["timestamp"]))
            .map(|x| format!("{:?}", x))
            .collect::<Vec<_>>()
            .join(", ")
    );
    assert!(result["results"][0]["preview"]
        .as_str()
        .unwrap()
        .starts_with("data:image/png;base64,"));
    eprintln!("First semantic image query: {:?}", start.elapsed());
    let start = Instant::now();
    let result = engine
        .search("папка обучение нейронных сетей", true)
        .await
        .unwrap();
    assert_eq!(
        result["results"][0]["name"],
        "Course",
        "{}",
        result["results"]
            .as_array()
            .unwrap()
            .iter()
            .map(|h| (&h["name"], &h["score"], &h["timestamp"]))
            .map(|x| format!("{:?}", x))
            .collect::<Vec<_>>()
            .join(", ")
    );
    eprintln!("Warm semantic folder query: {:?}", start.elapsed());
    let result = engine.search("GRADIENT DESCENT", false).await.unwrap();
    assert!(
        result["results"]
            .as_array()
            .unwrap()
            .iter()
            .any(|h| h["name"] == "red.png"),
        "OCR result: {result}"
    );
    let result = engine.search("видео синий квадрат", true).await.unwrap();
    assert_eq!(
        result["results"][0]["name"],
        "shapes.mp4",
        "{}",
        result["results"]
            .as_array()
            .unwrap()
            .iter()
            .map(|h| (&h["name"], &h["score"], &h["timestamp"]))
            .map(|x| format!("{:?}", x))
            .collect::<Vec<_>>()
            .join(", ")
    );
    assert_eq!(
        result["results"][0]["timestamp"],
        10.0,
        "{}",
        result["results"]
            .as_array()
            .unwrap()
            .iter()
            .map(|h| (&h["name"], &h["score"], &h["timestamp"]))
            .map(|x| format!("{:?}", x))
            .collect::<Vec<_>>()
            .join(", ")
    );
    engine.state.lock().unwrap().ann.clear();
    let restored = engine.search("фото красный круг", true).await.unwrap();
    assert_eq!(restored["results"][0]["name"], "red.png");
    engine.lock();
    assert!(engine.search("private", true).await.is_err());
    background.abort();
}
