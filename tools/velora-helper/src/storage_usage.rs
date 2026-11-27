//! Scan once, keeping filenames and allocated sizes in this process. Settings asks for a
//! folder and offset on stdin and receives only the three rings it can display, as JSON lines.
use anyhow::{ensure, Context, Result};
use rustix::fs::{open, statat, AtFlags, FileType, Mode, OFlags, RawDir};
use serde_json::{json, Value};
use std::collections::HashSet;
use std::ffi::{OsStr, OsString};
use std::fs;
use std::io::{self, BufRead, Write};
use std::mem::MaybeUninit;
use std::os::unix::ffi::OsStringExt;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

const PAGE: usize = 7;
const RINGS: usize = 3;
const REPORT_INTERVAL: Duration = Duration::from_millis(200);

struct MeasuredEntry {
    name: OsString,
    bytes: u64,
    directory: bool,
    inode: Option<u64>,
}

#[derive(Default)]
struct Batch {
    entries: Vec<MeasuredEntry>,
    scanned: u64,
    skipped: u64,
    last: bool,
}

fn read_directory(
    path: &Path,
    root: bool,
    device: u64,
    buffer: &mut [MaybeUninit<u8>],
    output: &mpsc::SyncSender<io::Result<Batch>>,
) -> bool {
    let mut flags = OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC;
    if !root {
        flags |= OFlags::NOFOLLOW;
    }
    let fd = match open(path, flags, Mode::empty()) {
        Ok(fd) => fd,
        Err(err) => return output.send(Err(err.into())).is_ok(),
    };
    let mut dir = RawDir::new(&fd, buffer);
    let mut batch = Batch::default();
    while let Some(entry) = dir.next() {
        let entry = match entry {
            Ok(entry) => entry,
            Err(rustix::io::Errno::INTR) => continue,
            Err(_) => {
                batch.skipped += 1;
                break;
            }
        };
        let name = entry.file_name();
        if matches!(name.to_bytes(), b"." | b"..") {
            continue;
        }
        batch.scanned += 1;
        match statat(&fd, name, AtFlags::SYMLINK_NOFOLLOW | AtFlags::NO_AUTOMOUNT) {
            Ok(meta) if meta.st_dev == device => {
                let directory = FileType::from_raw_mode(meta.st_mode) == FileType::Directory;
                batch.entries.push(MeasuredEntry {
                    name: OsString::from_vec(name.to_bytes().to_vec()),
                    bytes: meta.st_blocks as u64 * 512,
                    directory,
                    inode: (directory || meta.st_nlink > 1).then_some(meta.st_ino),
                });
            }
            Ok(_) => {}
            Err(_) => batch.skipped += 1,
        }
        if batch.scanned == 512 && output.send(Ok(std::mem::take(&mut batch))).is_err() {
            return false;
        }
    }
    batch.last = true;
    output.send(Ok(batch)).is_ok()
}

enum Entry {
    Folder(usize),
    File(OsString, u64),
}

struct Folder {
    name: OsString,
    parent: Option<usize>,
    entries: Vec<Entry>,
    bytes: u64,
    own_bytes: u64,
    unreadable: bool,
}

impl Folder {
    fn new(name: OsString, parent: Option<usize>, bytes: u64) -> Self {
        Self {
            name,
            parent,
            entries: Vec::new(),
            bytes,
            own_bytes: bytes,
            unreadable: false,
        }
    }
}

struct Tree {
    folders: Vec<Folder>,
    device: u64,
    root_inode: u64,
    scanned: u64,
    skipped: u64,
}

impl Tree {
    fn new(path: &Path) -> Result<Self> {
        ensure!(path.is_absolute(), "Expected an absolute folder path");
        let meta = fs::metadata(path)?;
        ensure!(meta.is_dir(), "Expected a folder");
        Ok(Self {
            folders: vec![Folder::new(path.into(), None, meta.blocks() * 512)],
            device: meta.dev(),
            root_inode: meta.ino(),
            scanned: 0,
            skipped: 0,
        })
    }

    fn path(&self, mut id: usize) -> PathBuf {
        let mut parts = Vec::new();
        loop {
            let folder = &self.folders[id];
            parts.push(&folder.name);
            let Some(parent) = folder.parent else { break };
            id = parent;
        }
        parts.into_iter().rev().collect()
    }

    fn add_bytes(&mut self, mut id: usize, bytes: u64) {
        loop {
            self.folders[id].bytes += bytes;
            let Some(parent) = self.folders[id].parent else {
                break;
            };
            id = parent;
        }
    }

    fn scan(&mut self, mut report: impl FnMut(&Self) -> Result<bool>) -> Result<bool> {
        let count = thread::available_parallelism().map_or(1, |n| n.get().min(8));
        let device = self.device;
        thread::scope(|scope| {
            let mut readers = Vec::with_capacity(count);
            for _ in 0..count {
                let (jobs, paths) = mpsc::channel::<(usize, PathBuf)>();
                let (output, batches) = mpsc::sync_channel(2);
                scope.spawn(move || {
                    let mut buffer = [MaybeUninit::uninit(); 32 * 1024];
                    for (id, path) in paths {
                        if !read_directory(&path, id == 0, device, &mut buffer, &output) {
                            break;
                        }
                    }
                });
                readers.push((jobs, batches));
            }
            // Read ahead, then merge in discovery order so a hard link always belongs
            // to the same folder. Queues bound memory even for a million-file directory.
            let mut seen = HashSet::from([self.root_inode]);
            let mut scheduled = 0;
            let mut id = 0;
            while id < self.folders.len() {
                while scheduled < self.folders.len() && scheduled - id < 2 * count {
                    readers[scheduled % count]
                        .0
                        .send((scheduled, self.path(scheduled)))?;
                    scheduled += 1;
                }
                match readers[id % count].1.recv()? {
                    Ok(batch) => {
                        self.scanned += batch.scanned;
                        self.skipped += batch.skipped;
                        let mut added = 0;
                        for entry in batch.entries {
                            if entry.inode.is_some_and(|ino| !seen.insert(ino)) {
                                continue;
                            }
                            added += entry.bytes;
                            let child = if entry.directory {
                                let index = self.folders.len();
                                self.folders
                                    .push(Folder::new(entry.name, Some(id), entry.bytes));
                                Entry::Folder(index)
                            } else {
                                Entry::File(entry.name, entry.bytes)
                            };
                            self.folders[id].entries.push(child);
                        }
                        self.add_bytes(id, added);
                        if batch.last {
                            id += 1;
                        }
                    }
                    Err(err) if id == 0 => return Err(err).context("Could not read the scan root"),
                    Err(_) => {
                        self.folders[id].unreadable = true;
                        self.skipped += 1;
                        id += 1;
                    }
                }
                if !report(self)? {
                    return Ok(false);
                }
            }
            Ok(true)
        })
    }

    fn entry<'a>(&'a self, entry: &'a Entry) -> (u64, &'a OsStr) {
        match entry {
            Entry::Folder(id) => (self.folders[*id].bytes, &self.folders[*id].name),
            Entry::File(name, bytes) => (*bytes, name),
        }
    }

    fn rings(
        &self,
        id: usize,
        offset: usize,
        path: &Path,
        depth: usize,
        span: f64,
    ) -> (u64, Vec<Value>) {
        let folder = &self.folders[id];
        let mut ranked: Vec<_> = folder.entries.iter().collect();
        let end = (offset + PAGE).min(ranked.len());
        let by_size = |a: &&Entry, b: &&Entry| {
            let (a_size, a_name) = self.entry(a);
            let (b_size, b_name) = self.entry(b);
            b_size.cmp(&a_size).then_with(|| a_name.cmp(b_name))
        };
        if end < ranked.len() {
            ranked.select_nth_unstable_by(end, by_size);
            ranked.truncate(end);
        }
        ranked.sort_unstable_by(by_size);
        let preceding: u64 = ranked[..offset].iter().map(|e| self.entry(e).0).sum();
        let contents = folder.bytes - folder.own_bytes - preceding;
        let total = if offset == 0 { folder.bytes } else { contents };
        let mut remaining = contents;
        let mut sectors = Vec::new();
        for entry in &ranked[offset..] {
            let (bytes, name) = self.entry(entry);
            remaining -= bytes;
            let child_path = path.join(name);
            let mut sector = json!({"name": name.to_string_lossy(), "bytes": bytes});
            match entry {
                Entry::Folder(child) => {
                    sector["id"] = json!(child);
                    let arc = span * bytes as f64 / total.max(1) as f64;
                    if depth > 1 && arc >= 0.003 {
                        sector["children"] =
                            json!(self.rings(*child, 0, &child_path, depth - 1, arc).1);
                    }
                }
                Entry::File(..) => {
                    sector["uri"] = json!(url::Url::from_file_path(child_path).unwrap().as_str())
                }
            }
            sectors.push(sector);
        }
        if end < folder.entries.len() {
            sectors.push(json!({"id": id, "offset": end, "more": folder.entries.len() - end, "bytes": remaining}));
        }
        (total, sectors)
    }

    fn has_view(&self, (id, offset): (usize, usize)) -> bool {
        self.folders.get(id).is_some_and(|f| {
            offset == 0 || (offset.is_multiple_of(PAGE) && offset < f.entries.len())
        })
    }

    fn publish(
        &self,
        (id, offset): (usize, usize),
        done: bool,
        out: &mut impl Write,
    ) -> Result<()> {
        let folder = &self.folders[id];
        let path = self.path(id);
        let (bytes, children) = self.rings(id, offset, &path, RINGS, 1.0);
        let frame = json!({"id": id, "offset": offset, "parent": folder.parent, "previousOffset": offset.saturating_sub(PAGE),
            "path": path.to_string_lossy(), "uri": url::Url::from_file_path(&path).unwrap().as_str(),
            "bytes": bytes, "children": children, "unreadable": folder.unreadable,
            "scanned": self.scanned, "skipped": self.skipped, "done": done});
        write_frame(out, &frame)
    }
}

fn write_frame(out: &mut impl Write, frame: &Value) -> Result<()> {
    serde_json::to_writer(&mut *out, frame)?;
    out.write_all(b"\n")?;
    out.flush()?;
    Ok(())
}

pub fn run(args: &[String]) -> Result<()> {
    let [path] = args else {
        anyhow::bail!("usage: storage-usage PATH")
    };
    let _ = rustix::process::nice(10);
    let mut tree = Tree::new(Path::new(path))?;
    let (sender, requests) = mpsc::channel();
    std::thread::spawn(move || {
        for line in io::stdin().lock().lines().map_while(Result::ok) {
            if let Ok(view) = serde_json::from_str::<(usize, usize)>(&line) {
                if sender.send(view).is_err() {
                    break;
                }
            }
        }
    });
    let mut view = (0, 0);
    let counts_only =
        std::env::var_os("VELORA_STORAGE_PROGRESS_ONLY").as_deref() == Some(OsStr::new("1"));
    let mut last = None;
    let mut out = io::BufWriter::new(io::stdout().lock());
    let finished = tree.scan(|tree| {
        let mut changed = false;
        loop {
            match requests.try_recv() {
                Ok(next) if tree.has_view(next) => {
                    view = next;
                    changed = true;
                }
                Ok(_) => {}
                Err(mpsc::TryRecvError::Empty) => break,
                Err(mpsc::TryRecvError::Disconnected) => return Ok(false),
            }
        }
        if changed || last.is_none_or(|t: Instant| t.elapsed() >= REPORT_INTERVAL) {
            if counts_only {
                write_frame(&mut out, &json!({"id": view.0, "offset": view.1, "scanned": tree.scanned, "done": false}))?;
            } else {
                tree.publish(view, false, &mut out)?;
            }
            last = Some(Instant::now());
        }
        Ok(true)
    })?;
    if finished {
        tree.publish(view, true, &mut out)?;
        for next in requests {
            if tree.has_view(next) {
                tree.publish(next, true, &mut out)?;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    #[test]
    fn partial_and_final_views_use_allocated_blocks_once() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("map");
        let child = root.join("nested");
        fs::create_dir_all(&child).unwrap();
        let file = child.join("a space #%.bin");
        fs::write(&file, [1; 8192]).unwrap();
        fs::hard_link(&file, child.join("second link")).unwrap();
        fs::File::create(child.join("sparse"))
            .unwrap()
            .set_len(1 << 30)
            .unwrap();
        symlink(temp.path(), root.join("loop")).unwrap();
        let allocated = |p: &Path| fs::symlink_metadata(p).unwrap().blocks() * 512;
        let expected = [
            &root,
            &child,
            &file,
            &child.join("sparse"),
            &root.join("loop"),
        ]
        .iter()
        .map(|p| allocated(p))
        .sum::<u64>();
        let mut tree = Tree::new(&root).unwrap();
        let mut partial = Vec::new();
        assert!(tree
            .scan(|t| {
                partial.push(t.folders[0].bytes);
                Ok(true)
            })
            .unwrap());
        assert!(partial[0] < expected);
        assert!(partial.windows(2).all(|w| w[0] <= w[1]));
        assert_eq!(tree.folders[0].bytes, expected);
        assert_eq!(tree.folders.len(), 2);
        let (_, entries) = tree.rings(1, 0, &child, RINGS, 1.0);
        assert_eq!(entries.len(), 2);
        let uri = url::Url::parse(entries[0]["uri"].as_str().unwrap()).unwrap();
        assert_eq!(allocated(&uri.to_file_path().unwrap()), allocated(&file));
    }

    #[test]
    fn parallel_readers_count_shared_files_once_and_cancel_with_work_queued() {
        let temp = tempfile::tempdir().unwrap();
        let file = temp.path().join("data");
        fs::write(&file, [1; 8192]).unwrap();
        for n in 0..4 {
            let dir = temp.path().join(n.to_string());
            fs::create_dir(&dir).unwrap();
            fs::hard_link(&file, dir.join("shared")).unwrap();
            for i in 0..520 {
                fs::File::create(dir.join(i.to_string())).unwrap();
            }
        }
        fs::remove_file(&file).unwrap();
        let mut tree = Tree::new(temp.path()).unwrap();
        assert!(!tree.scan(|tree| Ok(tree.scanned < 512)).unwrap());

        let scan = || {
            let mut tree = Tree::new(temp.path()).unwrap();
            assert!(tree.scan(|_| Ok(true)).unwrap());
            assert_eq!(tree.scanned, 4 + 4 * 521);
            let owners: Vec<_> = tree
                .folders
                .iter()
                .filter(|folder| {
                    folder
                        .entries
                        .iter()
                        .any(|entry| matches!(entry, Entry::File(name, _) if name == "shared"))
                })
                .collect();
            assert_eq!(owners.len(), 1);
            (owners[0].name.clone(), tree.folders[0].bytes)
        };
        assert_eq!(scan(), scan());
    }

    #[test]
    fn smaller_items_remain_reachable_and_add_up_to_the_parent() {
        let temp = tempfile::tempdir().unwrap();
        for i in 0..PAGE * 2 + 1 {
            fs::write(temp.path().join(format!("file {i:02}")), [1; 4096]).unwrap();
        }
        let mut tree = Tree::new(temp.path()).unwrap();
        tree.scan(|_| Ok(true)).unwrap();
        let mut names = Vec::new();
        let mut offset = 0;
        let mut contents = tree.folders[0].bytes - tree.folders[0].own_bytes;
        loop {
            assert!(tree.has_view((0, offset)));
            let (_, entries) = tree.rings(0, offset, temp.path(), RINGS, 1.0);
            assert_eq!(
                entries
                    .iter()
                    .map(|e| e["bytes"].as_u64().unwrap())
                    .sum::<u64>(),
                contents
            );
            names.extend(
                entries
                    .iter()
                    .filter_map(|e| e["name"].as_str().map(str::to_owned)),
            );
            let last = entries.last().unwrap();
            let Some(next) = last["offset"].as_u64() else {
                break;
            };
            offset = next as usize;
            contents = last["bytes"].as_u64().unwrap();
        }
        assert_eq!(
            names,
            (0..PAGE * 2 + 1)
                .map(|i| format!("file {i:02}"))
                .collect::<Vec<_>>()
        );
    }
}
