use super::{Sample, RETENTION, STATUSES};
use anyhow::{ensure, Result};
use rustix::{
    fs::{self, AtFlags, FlockOperation, Mode, OFlags},
    io::Errno,
};
use std::{
    collections::VecDeque,
    fs::File,
    io::{self, Write},
    os::unix::fs::{FileExt, MetadataExt},
    path::{Component, Path},
};

const CAPACITY: usize = 14400;
const SIZE: usize = 112;
const HEADER: &[u8; 16] = b"VPWR0001\x40\x38\0\0\x70\0\0\0";
const HISTORY: &str = "history.bin";

fn directory(path: &Path, create: bool) -> Result<Option<File>> {
    let mut fd = File::open("/")?;
    for part in std::path::absolute(path)?.components() {
        if part == Component::RootDir {
            continue;
        }
        let Component::Normal(name) = part else {
            anyhow::bail!("invalid state directory component");
        };
        let flags = OFlags::RDONLY | OFlags::CLOEXEC | OFlags::DIRECTORY | OFlags::NOFOLLOW;
        fd = match fs::openat(&fd, name, flags, Mode::empty()) {
            Ok(child) => child,
            Err(Errno::NOENT) if !create => return Ok(None),
            Err(Errno::NOENT) => {
                match fs::mkdirat(&fd, name, Mode::RWXU) {
                    Ok(()) | Err(Errno::EXIST) => {}
                    Err(e) => return Err(e.into()),
                }
                fs::openat(&fd, name, flags, Mode::empty())?
            }
            Err(e) => return Err(e.into()),
        }
        .into();
    }
    ensure!(
        fd.metadata()?.uid() == unsafe { libc::getuid() },
        "state directory must be owned by current user"
    );
    if create {
        fs::fchmod(&fd, Mode::RWXU)?;
    }
    Ok(Some(fd))
}

fn owned(dir: &File, name: &str, flags: OFlags) -> io::Result<File> {
    let file: File = fs::openat(
        dir,
        name,
        flags | OFlags::CLOEXEC | OFlags::NONBLOCK | OFlags::NOFOLLOW,
        Mode::RUSR | Mode::WUSR,
    )?
    .into();
    let m = file.metadata()?;
    if !m.is_file() || m.uid() != unsafe { libc::getuid() } || m.nlink() != 1 {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "unsafe telemetry file",
        ));
    }
    if flags.intersects(OFlags::RDWR | OFlags::WRONLY) {
        fs::fchmod(&file, Mode::RUSR | Mode::WUSR)?;
    }
    Ok(file)
}

fn encode(seq: u64, s: &Sample) -> [u8; SIZE] {
    let mut data = [0; SIZE];
    data[..8].copy_from_slice(&seq.to_le_bytes());
    for (chunk, value) in data[8..56]
        .as_chunks_mut::<8>()
        .0
        .iter_mut()
        .zip(std::iter::once(Some(s.time)).chain(s.metrics))
    {
        chunk.copy_from_slice(&value.unwrap_or(f64::NAN).to_le_bytes());
    }
    data[56] = s.status;
    data[57] = s.ac.map_or(2, u8::from);
    data[58] = u8::from(s.gap);
    let error = &s.error.as_bytes()[..s.error.len().min(48)];
    data[60..60 + error.len()].copy_from_slice(error);
    let crc = crc32fast::hash(&data[..108]);
    data[108..].copy_from_slice(&crc.to_le_bytes());
    data
}

fn decode(i: usize, r: &[u8; SIZE]) -> Option<(u64, Sample)> {
    let seq = u64::from_le_bytes(r[..8].try_into().unwrap());
    if seq == 0
        || (seq - 1) % CAPACITY as u64 != i as u64
        || crc32fast::hash(&r[..108]).to_le_bytes() != r[108..]
    {
        return None;
    }
    let value = |i: usize| f64::from_le_bytes(r[i..i + 8].try_into().unwrap());
    let time = value(8);
    if !time.is_finite() || r[56] as usize >= STATUSES.len() || r[57] > 2 {
        return None;
    }
    let metrics = std::array::from_fn(|i| {
        let n = value(16 + 8 * i);
        n.is_finite().then_some(n)
    });
    let error = String::from_utf8_lossy(r[60..108].split(|b| *b == 0).next().unwrap()).into_owned();
    Some((
        seq,
        Sample {
            time,
            metrics,
            status: r[56],
            ac: (r[57] < 2).then_some(r[57] == 1),
            gap: r[58] != 0,
            error,
        },
    ))
}

fn records(file: &File) -> Result<Vec<(u64, Sample)>> {
    ensure!(
        file.metadata()?.len() == (16 + CAPACITY * SIZE) as u64,
        "invalid telemetry ring size"
    );
    let mut head = [0; 16];
    file.read_exact_at(&mut head, 0)?;
    ensure!(&head == HEADER, "invalid telemetry ring header");
    let mut bytes = vec![0; CAPACITY * SIZE];
    file.read_exact_at(&mut bytes, 16)?;
    let mut result = Vec::new();
    for (i, r) in bytes.as_chunks::<SIZE>().0.iter().enumerate() {
        if let Some(entry) = decode(i, r) {
            result.push(entry);
        }
    }
    result.sort_unstable_by_key(|r| r.0);
    Ok(result)
}

#[derive(Default)]
pub(super) struct History {
    signature: Option<(u64, u64, i64, i64)>,
    entries: VecDeque<(u64, Sample)>,
}

fn at(file: &File, seq: u64) -> Result<Option<(u64, Sample)>> {
    let slot = ((seq - 1) % CAPACITY as u64) as usize;
    let mut bytes = [0; SIZE];
    file.read_exact_at(&mut bytes, offset(seq))?;
    Ok(decode(slot, &bytes).filter(|(n, _)| *n == seq))
}

impl History {
    fn append_new(&mut self, file: &File) -> Result<bool> {
        let Some((last, s)) = self.entries.back() else {
            return Ok(false);
        };
        if at(file, *last)?.is_none_or(|(_, record)| record.time != s.time) {
            return Ok(false);
        }
        let Some(mut seq) = last.checked_add(1) else {
            return Ok(false);
        };
        let mut count = 0;
        while let Some((_, sample)) = at(file, seq)? {
            if count >= 256
                || self
                    .entries
                    .back()
                    .is_some_and(|(_, s)| s.time > sample.time)
            {
                return Ok(false);
            }
            while self.entries.front().is_some_and(|(n, s)| {
                *n <= seq.saturating_sub(CAPACITY as u64) || s.time < sample.time - RETENTION
            }) {
                self.entries.pop_front();
            }
            self.entries.push_back((seq, sample));
            let Some(next) = seq.checked_add(1) else {
                break;
            };
            seq = next;
            count += 1;
        }
        Ok(count > 0)
    }

    pub fn read(&mut self, path: &Path) -> Result<&VecDeque<(u64, Sample)>> {
        let file = directory(path, false)?
            .map(|dir| owned(&dir, HISTORY, OFlags::RDONLY))
            .transpose();
        let file = match file {
            Ok(Some(file)) => Some(file),
            Ok(None) => None,
            Err(e) if e.kind() == io::ErrorKind::NotFound => None,
            Err(e) => return Err(e.into()),
        };
        if let Some(file) = file {
            let meta = file.metadata()?;
            let signature = (meta.dev(), meta.ino(), meta.mtime(), meta.mtime_nsec());
            if self.signature != Some(signature) {
                // After the first snapshot each collector tick normally adds one 112-byte record.
                let same_file = self
                    .signature
                    .is_some_and(|(dev, ino, _, _)| (dev, ino) == (meta.dev(), meta.ino()));
                if !same_file || !self.append_new(&file)? {
                    self.entries = records(&file)?.into();
                }
                self.signature = Some(signature);
            }
        } else {
            self.entries.clear();
            self.signature = None;
        }
        Ok(&self.entries)
    }
}

fn remove(dir: &File, name: &str) -> Result<()> {
    match fs::unlinkat(dir, name, AtFlags::empty()) {
        Ok(()) | Err(Errno::NOENT) => Ok(()),
        Err(e) => Err(e.into()),
    }
}
pub(super) fn clear(path: &Path) -> Result<()> {
    if let Some(dir) = directory(path, false)? {
        fs::flock(&dir, FlockOperation::NonBlockingLockExclusive)?;
        for name in [HISTORY, "latest.json", ".latest.tmp"] {
            remove(&dir, name)?;
        }
    }
    Ok(())
}

pub(super) struct Ring {
    dir: File,
    file: File,
    sequence: u64,
    entries: VecDeque<(u64, f64)>,
}
fn offset(seq: u64) -> u64 {
    16 + ((seq - 1) % CAPACITY as u64) * SIZE as u64
}
impl Ring {
    pub fn new(path: &Path) -> Result<Self> {
        let dir = directory(path, true)?.unwrap();
        fs::flock(&dir, FlockOperation::NonBlockingLockExclusive)?;
        let file = owned(&dir, HISTORY, OFlags::RDWR | OFlags::CREATE)?;
        if file.metadata()?.len() == 0 {
            file.set_len((16 + CAPACITY * SIZE) as u64)?;
            file.write_all_at(HEADER, 0)?;
        }
        let all = records(&file)?;
        Ok(Self {
            sequence: all.last().map_or(0, |r| r.0),
            entries: all.into_iter().map(|(n, s)| (n, s.time)).collect(),
            dir,
            file,
        })
    }
    pub fn append(&mut self, mut s: Sample) -> Result<()> {
        if self.entries.back().is_some_and(|(_, t)| *t > s.time) {
            for &(seq, t) in &self.entries {
                if t > s.time {
                    self.file.write_all_at(&[0; SIZE], offset(seq))?;
                }
            }
            self.entries.retain(|(_, t)| *t <= s.time);
            s.gap = true;
        }
        self.sequence = self
            .sequence
            .checked_add(1)
            .ok_or_else(|| anyhow::anyhow!("invalid telemetry sequence"))?;
        while let Some(&(seq, t)) = self.entries.front() {
            if t < s.time - RETENTION {
                self.file.write_all_at(&[0; SIZE], offset(seq))?;
            } else if seq > self.sequence.saturating_sub(CAPACITY as u64) {
                break;
            }
            self.entries.pop_front();
        }
        self.file
            .write_all_at(&encode(self.sequence, &s), offset(self.sequence))?;
        self.entries.push_back((self.sequence, s.time));
        remove(&self.dir, ".latest.tmp")?;
        let mut tmp = owned(
            &self.dir,
            ".latest.tmp",
            OFlags::WRONLY | OFlags::CREATE | OFlags::EXCL,
        )?;
        writeln!(tmp, "{}", s.json())?;
        fs::renameat(&self.dir, ".latest.tmp", &self.dir, "latest.json")?;
        Ok(())
    }
}
