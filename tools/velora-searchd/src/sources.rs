use crate::config::{Config, SourceFilter, SourceReview};
use anyhow::Result;
use std::path::Path;

pub const LARGE_FOLDER_FILES: usize = 10_000;

// Only metadata is read. Large repositories are counted as a unit, while ordinary
// source trees are inspected from the leaves so a large child need not block its
// siblings. Counting stops at the threshold and approved subtrees are skipped.
pub fn discover(
    root: &Path,
    config: &Config,
    threshold: usize,
    cancelled: impl Fn() -> bool,
) -> Result<Vec<SourceReview>> {
    struct Scan<'a, F> {
        config: &'a Config,
        filter: SourceFilter<'a>,
        threshold: usize,
        reviews: Vec<SourceReview>,
        cancelled: F,
    }
    impl<F: Fn() -> bool> Scan<'_, F> {
        fn eligible(&mut self, path: &Path) -> Result<bool> {
            anyhow::ensure!(!(self.cancelled)(), "Cancelled");
            Ok(!self
                .config
                .large_folders
                .iter()
                .any(|p| path.starts_with(p))
                && self.filter.readable(path))
        }

        fn repository_count(&mut self, path: &Path) -> Result<usize> {
            let mut count = 0;
            let mut entries = walkdir::WalkDir::new(path).follow_links(false).into_iter();
            while let Some(entry) = entries.next() {
                let Ok(entry) = entry else { continue };
                if entry.file_type().is_symlink() || !self.eligible(entry.path())? {
                    if entry.file_type().is_dir() {
                        entries.skip_current_dir();
                    }
                    continue;
                }
                if entry.file_type().is_file() {
                    count += 1;
                    if count >= self.threshold {
                        break;
                    }
                }
            }
            Ok(count)
        }

        fn directory(&mut self, path: &Path) -> Result<usize> {
            if !self.eligible(path)? {
                return Ok(0);
            }
            let mut count = 0;
            if path.join(".git").exists() || path.join(".hg").is_dir() || path.join(".svn").is_dir()
            {
                count = self.repository_count(path)?;
            } else if let Ok(entries) = std::fs::read_dir(path) {
                for entry in entries.flatten() {
                    let Ok(kind) = entry.file_type() else {
                        continue;
                    };
                    if kind.is_dir() {
                        count += self.directory(&entry.path())?;
                    } else if kind.is_file() && self.eligible(&entry.path())? {
                        count += 1;
                    }
                    if count >= self.threshold {
                        break;
                    }
                }
            }
            if count >= self.threshold {
                self.reviews.retain(|review| !review.path.starts_with(path));
                self.reviews.push(SourceReview {
                    path: path.to_owned(),
                    files: count,
                });
                return Ok(0);
            }
            Ok(count)
        }
    }
    let mut scan = Scan {
        config,
        filter: SourceFilter::new(config),
        threshold,
        reviews: vec![],
        cancelled,
    };
    scan.directory(root)?;
    Ok(scan.reviews)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn asks_about_large_projects_without_holding_siblings_or_counting_junk() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path();
        for name in [
            "llvm-project/.git",
            "notes",
            "small/node_modules",
            "small/.venv",
        ] {
            std::fs::create_dir_all(root.join(name)).unwrap();
        }
        for i in 0..12 {
            for name in ["llvm-project", "small/node_modules", "small/.venv"] {
                std::fs::write(root.join(name).join(format!("{i}.txt")), "example").unwrap();
            }
        }
        std::fs::write(root.join("notes/today.md"), "notes").unwrap();
        let mut config = Config {
            roots: vec![root.to_owned()],
            ..Config::default()
        };
        let reviews = discover(root, &config, 10, || false).unwrap();
        assert_eq!(
            reviews,
            vec![SourceReview {
                path: root.join("llvm-project"),
                files: 10
            }]
        );
        config.source_reviews = reviews;
        assert!(!config.readable(&root.join("llvm-project/0.txt")));
        assert!(config.readable(&root.join("notes/today.md")));
        assert!(discover(root, &config, 10, || false).unwrap().is_empty());
        config.source_reviews.clear();
        config.large_folders.push(root.join("llvm-project"));
        assert!(discover(root, &config, 10, || false).unwrap().is_empty());
        assert!(config.readable(&root.join("llvm-project/0.txt")));
        assert!(discover(root, &config, 10, || true).is_err());
    }

    #[test]
    fn large_non_repository_subfolders_are_reviewed_individually() {
        let temp = tempfile::tempdir().unwrap();
        let album = temp.path().join("Photos/Album");
        std::fs::create_dir_all(&album).unwrap();
        for i in 0..12 {
            std::fs::write(album.join(format!("{i}.jpg")), "image").unwrap();
        }
        let config = Config {
            roots: vec![temp.path().to_owned()],
            ..Config::default()
        };
        let reviews = discover(temp.path(), &config, 10, || false).unwrap();
        assert_eq!(
            reviews,
            vec![SourceReview {
                path: album,
                files: 10
            }]
        );
    }
}
