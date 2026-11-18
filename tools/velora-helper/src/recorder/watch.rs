//! Wake the shell on a state publication or owner/child exit. Idle recording has no timer.
use super::{control::matching_pid, read_state, status};
use anyhow::{bail, Result};
use rustix::{
    fs::inotify::{self, CreateFlags, ReadFlags, WatchFlags},
    io::Errno,
};
use serde_json::Value;
use std::{
    fs,
    mem::MaybeUninit,
    os::{fd::OwnedFd, unix::fs::DirBuilderExt},
    path::Path,
    process::ExitCode,
};
use tokio::io::unix::AsyncFd;

async fn exited(fd: &Option<AsyncFd<OwnedFd>>) -> Result<()> {
    if let Some(fd) = fd {
        drop(fd.readable().await?);
    } else {
        std::future::pending::<()>().await;
    }
    Ok(())
}
async fn changed(fd: &AsyncFd<OwnedFd>) -> Result<()> {
    let mut buf = [MaybeUninit::uninit(); 8192];
    loop {
        let mut ready = fd.readable().await?;
        let mut events = inotify::Reader::new(fd.get_ref(), &mut buf);
        let mut refresh = false;
        loop {
            match events.next() {
                Ok(event) => {
                    let mask = event.events();
                    if mask.intersects(
                        ReadFlags::IGNORED | ReadFlags::MOVE_SELF | ReadFlags::DELETE_SELF,
                    ) {
                        bail!("Recorder runtime directory moved");
                    }
                    refresh |= mask.contains(ReadFlags::QUEUE_OVERFLOW)
                        || event
                            .file_name()
                            .is_some_and(|s| matches!(s.to_bytes(), b"owner.lock" | b"state.json"));
                }
                Err(Errno::AGAIN) => break,
                Err(e) => return Err(e.into()),
            }
        }
        ready.clear_ready();
        if refresh {
            return Ok(());
        }
    }
}
pub async fn run(dir: &Path) -> Result<ExitCode> {
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir)?;
    let fd = inotify::init(CreateFlags::CLOEXEC | CreateFlags::NONBLOCK)?;
    inotify::add_watch(
        &fd,
        dir,
        WatchFlags::MOVED_TO
            | WatchFlags::CLOSE_WRITE
            | WatchFlags::CREATE
            | WatchFlags::DELETE
            | WatchFlags::MOVE_SELF
            | WatchFlags::DELETE_SELF,
    )?;
    // SAFETY: the owned nonblocking inotify descriptor stays registered only in this runtime.
    let files = unsafe { AsyncFd::register(fd) }?;
    let mut previous = None;
    loop {
        let raw = Value::Object(read_state(dir));
        let owner = matching_pid(&raw["pid"], &raw["identity"])?;
        let child = matching_pid(&raw["childPid"], &raw["childIdentity"])?;
        let value = Value::Object(status(dir));
        if previous.as_ref() != Some(&value) {
            println!("{value}");
            previous = Some(value);
        }
        tokio::select! {r=changed(&files)=>r?,r=exited(&owner)=>r?,r=exited(&child)=>r?}
    }
}
