//! Read-only, on-demand catalogue accounting. Never prints the key or file contents.
use anyhow::Result;
use rusqlite::{Connection, OpenFlags};
use serde_json::json;
use std::{collections::BTreeMap, path::Path};
use velora_searchd::config::{Config, SourceFilter};

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    unsafe {
        libc::prctl(libc::PR_SET_DUMPABLE, 0);
    }
    let key = velora_searchd::secret::key(false).await?;
    let db = Connection::open_with_flags(
        velora_searchd::data_dir().join("index.db"),
        OpenFlags::SQLITE_OPEN_READ_ONLY,
    )?;
    let hex = zeroize::Zeroizing::new(key.iter().map(|b| format!("{b:02x}")).collect::<String>());
    let pragma = zeroize::Zeroizing::new(format!("x'{}'", *hex));
    db.pragma_update(None, "key", &*pragma)?;
    db.execute_batch("PRAGMA query_only=ON; PRAGMA temp_store=MEMORY;")?;
    let config: Config = serde_json::from_str(&db.query_row(
        "SELECT value FROM settings WHERE key='config'",
        [],
        |r| r.get::<_, String>(0),
    )?)?;
    let mut filter = SourceFilter::new(&config);
    let mut roots = BTreeMap::<String, usize>::new();
    let mut folders = BTreeMap::<String, usize>::new();
    let mut extensions = BTreeMap::<String, usize>::new();
    let mut datasets = BTreeMap::<String, BTreeMap<String, usize>>::new();
    let mut rejected = 0;
    let mut total = 0;
    let mut statement = db.prepare("SELECT path,kind FROM files WHERE kind!='app'")?;
    for row in statement.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))? {
        let (value, kind) = row?;
        let path = Path::new(&value);
        total += 1;
        rejected += usize::from(!filter.allows(path));
        for dataset in &config.dataset_folders {
            if path.starts_with(dataset) {
                let counts = datasets
                    .entry(dataset.to_string_lossy().into_owned())
                    .or_default();
                *counts.entry(kind.clone()).or_default() += 1;
                if path == dataset && kind == "folder" {
                    *counts.entry("root_searchable".into()).or_default() += 1;
                }
            }
        }
        *extensions
            .entry(if kind == "folder" {
                "<folder>".into()
            } else {
                path.extension()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .to_lowercase()
            })
            .or_default() += 1;
        if let Some(root) = config
            .roots
            .iter()
            .filter(|r| path.starts_with(r))
            .max_by_key(|r| r.components().count())
        {
            *roots
                .entry(root.to_string_lossy().into_owned())
                .or_default() += 1;
            for parent in path
                .parent()
                .into_iter()
                .flat_map(Path::ancestors)
                .take_while(|p| p.starts_with(root) && *p != root)
            {
                if parent.strip_prefix(root)?.components().count() <= 3 {
                    *folders
                        .entry(parent.to_string_lossy().into_owned())
                        .or_default() += 1;
                }
            }
        }
    }
    let mut folders = folders.into_iter().collect::<Vec<_>>();
    folders.sort_by_key(|(_, n)| std::cmp::Reverse(*n));
    folders.truncate(45);
    let mut extensions = extensions.into_iter().collect::<Vec<_>>();
    extensions.sort_by_key(|(_, n)| std::cmp::Reverse(*n));
    extensions.truncate(20);
    println!(
        "{}",
        serde_json::to_string_pretty(
            &json!({"total":total,"excluded_by_current_rules":rejected,"roots":roots,"largest_folders":folders,"extensions":extensions,"datasets":datasets})
        )?
    );
    Ok(())
}
