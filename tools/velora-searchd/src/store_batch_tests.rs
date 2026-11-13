//! Synthetic encrypted-content coverage and a repeatable opt-in SQL benchmark.
use super::*;
use std::time::Instant;

fn corpus(files: usize, passages: usize) -> (tempfile::TempDir, Store, Vec<i64>, i64) {
    let temporary = tempfile::tempdir().unwrap();
    let mut store = Store::open(&temporary.path().join("index.db"), &[31; 32]).unwrap();
    let project = temporary.path().join("Project");
    let folder = project.join("hypr");
    std::fs::create_dir_all(&folder).unwrap();
    store
        .upsert(&project, "folder", "Project", 0, 0, 1, 1)
        .unwrap();
    let folder_id = store.upsert(&folder, "folder", "hypr", 0, 0, 1, 2).unwrap();
    let mut ids = Vec::new();
    for index in 0..files {
        let name = format!("document{index}.conf");
        let id = store
            .upsert(
                &folder.join(&name),
                "config",
                &name,
                0,
                1,
                1,
                index as u64 + 3,
            )
            .unwrap();
        let chunks: Vec<_> = (0..passages)
            .map(|part| {
                (
                    format!(
                        "{} passage{part} {}",
                        "keyboard ".repeat(part + 1),
                        "ordinary configuration context ".repeat(24)
                    ),
                    None,
                    None,
                    None,
                )
            })
            .collect();
        store.replace_chunks(id, "synthetic", &chunks).unwrap();
        ids.push(id);
    }
    (temporary, store, ids, folder_id)
}

fn legacy_passages(store: &Store, ids: &[i64], terms: &str) -> HashMap<i64, String> {
    let mut result = HashMap::new();
    let mut statement = store
        .db
        .prepare_cached(
            "SELECT chunks.text FROM content JOIN chunks ON chunks.id=content.rowid
         WHERE chunks.file_id=?1 AND content MATCH ?2 ORDER BY rank LIMIT 8",
        )
        .unwrap();
    for id in ids {
        let mut text = String::new();
        for passage in statement
            .query_map(params![id, terms], |r| r.get::<_, String>(0))
            .unwrap()
        {
            text.extend(passage.unwrap().chars().take(8192));
            text.push('\n');
        }
        if !text.is_empty() {
            result.insert(*id, text);
        }
    }
    result
}

#[test]
fn batched_passages_preserve_per_file_rank_and_unicode_bounds() {
    let (_temporary, mut store, ids, _) = corpus(12, 11);
    let long = format!("keyboard {}", "я".repeat(10000));
    store
        .replace_chunks(ids[0], "long", &[(long, None, None, None)])
        .unwrap();
    let selected = [ids[0], ids[3], ids[8], -1];
    let expected = legacy_passages(&store, &selected, "keyboard");
    let batched = store.candidate_passages(&selected, "keyboard").unwrap();
    assert_eq!(batched, expected);
    assert!(batched
        .values()
        .all(|text| text.chars().count() <= 8 * (8192 + 1)));
    let stored: String = store.db.query_row(
        "SELECT text FROM chunks WHERE file_id=?1 ORDER BY id LIMIT 1",
        [ids[0]], |row| row.get(0),
    ).unwrap();
    assert_eq!(batched[&ids[0]].chars().count(), stored.chars().take(8192).count() + 1);
    assert!(store
        .candidate_passages(&[], "keyboard")
        .unwrap()
        .is_empty());
    assert!(store.candidate_passages(&selected, "").unwrap().is_empty());
    let metadata = store.candidate_metadata(&selected).unwrap();
    assert_eq!(metadata.len(), 3);
    for id in &selected[..3] {
        assert_eq!(metadata[id].path, store.hit(*id).unwrap().unwrap().path);
    }
}

#[test]
fn content_backed_folder_results_keep_coverage_and_source_evidence() {
    let (_temporary, store, _, folder) = corpus(24, 10);
    let query = Query::parse("Project folder keyboard config", chrono::Local::now());
    let hits = store.search(&query, &[], 30).unwrap();
    assert_eq!(hits[0].id, folder);
    assert!(hits
        .iter()
        .all(|hit| hit.kind == "folder" && hit.lexical && !hit.partial));
    assert!(hits.iter().all(|hit| hit.unmatched_terms.is_empty()));
    assert!(hits[0].evidence_path.ends_with(".conf"));
    assert!(hits[0].snippet.contains("keyboard"));
    assert!(hits[0].matched_terms.iter().any(|term| term == "keyboard"));
}

#[test]
#[ignore = "opt-in synthetic encrypted content benchmark"]
fn content_batch_benchmark() {
    let (_temporary, store, ids, folder) = corpus(1024, 8);
    let selected = &ids[..256];
    let expected = legacy_passages(&store, selected, "keyboard");
    assert_eq!(
        store.candidate_passages(selected, "keyboard").unwrap(),
        expected
    );
    let mut old = Vec::new();
    let mut batch = Vec::new();
    let mut searches = Vec::new();
    for _ in 0..5 {
        let started = Instant::now();
        assert_eq!(legacy_passages(&store, selected, "keyboard"), expected);
        old.push(started.elapsed().as_secs_f64() * 1000.0);
        let started = Instant::now();
        assert_eq!(
            store.candidate_passages(selected, "keyboard").unwrap(),
            expected
        );
        batch.push(started.elapsed().as_secs_f64() * 1000.0);
        store.clear_search_caches();
        let started = Instant::now();
        let hits = store
            .search(
                &Query::parse("Project folder keyboard config", chrono::Local::now()),
                &[],
                30,
            )
            .unwrap();
        assert_eq!(hits[0].id, folder);
        searches.push(started.elapsed().as_secs_f64() * 1000.0);
    }
    old.sort_by(f64::total_cmp);
    batch.sort_by(f64::total_cmp);
    searches.sort_by(f64::total_cmp);
    println!("content_batch_benchmark files=1024 passages=8192 candidates=256 legacy_passages_median_ms={:.3} batched_passages_median_ms={:.3} full_search_uncached_median_ms={:.3}", old[2], batch[2], searches[2]);
}
