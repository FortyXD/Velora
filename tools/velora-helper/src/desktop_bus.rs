//! One-shot GeoClue location and event-driven lock prompt recovery.
use crate::subprocess::interruptible;
use anyhow::{ensure, Context, Result};
use futures_util::StreamExt;
use rustix::{
    fs::{flock, FlockOperation},
    process::{pidfd_open, Pid, PidfdFlags},
};
use std::{
    fs::OpenOptions,
    os::unix::{fs::OpenOptionsExt, process::CommandExt},
    path::PathBuf,
    process::{Command, ExitCode},
    time::Duration,
};
use tokio::io::unix::AsyncFd;
use zbus::{Connection, OwnedObjectPath, Proxy};

pub fn weather() -> Result<ExitCode> {
    interruptible(
        async {
            tokio::time::timeout(Duration::from_secs(25), async {
                let bus = Connection::system().await?;
                let service = "org.freedesktop.GeoClue2";
                let manager = Proxy::new(
                    &bus,
                    service,
                    "/org/freedesktop/GeoClue2/Manager",
                    "org.freedesktop.GeoClue2.Manager",
                )
                .await?;
                let path: OwnedObjectPath = manager.call("GetClient", &()).await?;
                let client =
                    Proxy::new(&bus, service, path, "org.freedesktop.GeoClue2.Client").await?;
                client.set_property("DesktopId", "org.quickshell").await?;
                client.set_property("RequestedAccuracyLevel", 8u32).await?;
                let mut updates = client.receive_signal("LocationUpdated").await?;
                client.call::<_, _, ()>("Start", &()).await?;
                let mut fix: OwnedObjectPath = client.get_property("Location").await?;
                if fix.as_str() == "/" {
                    let msg = updates
                        .next()
                        .await
                        .context("Location service disconnected")?;
                    fix = msg
                        .body()
                        .deserialize::<(OwnedObjectPath, OwnedObjectPath)>()?
                        .1;
                }
                let location =
                    Proxy::new(&bus, service, fix, "org.freedesktop.GeoClue2.Location").await?;
                let lat: f64 = location.get_property("Latitude").await?;
                let lon: f64 = location.get_property("Longitude").await?;
                ensure!(lat.is_finite() && lon.is_finite(), "Invalid coordinates");
                println!("{}", serde_json::json!({"lat":lat,"lon":lon}));
                Ok::<_, anyhow::Error>(())
            })
            .await
            .context("GeoClue timed out")??;
            Ok(ExitCode::SUCCESS)
        },
        || {},
    )
}

pub fn lock_recovery(args: Vec<String>) -> Result<ExitCode> {
    let pid = Pid::from_raw(args.first().context("missing shell pid")?.parse()?)
        .context("invalid shell pid")?;
    interruptible(
        async {
            let bus = Connection::session().await?;
            let saver = Proxy::new(
                &bus,
                "org.freedesktop.ScreenSaver",
                "/org/freedesktop/ScreenSaver",
                "org.freedesktop.ScreenSaver",
            )
            .await?;
            let mut changes = saver.receive_signal("ActiveChanged").await?;
            let active = || async {
                tokio::time::timeout(
                    Duration::from_millis(1500),
                    saver.call::<_, _, bool>("GetActive", &()),
                )
                .await
                .map_err(anyhow::Error::from)?
                .map_err(anyhow::Error::from)
            };
            if !active().await? {
                return Ok(ExitCode::SUCCESS);
            }
            match pidfd_open(pid, PidfdFlags::empty()) {
                Ok(fd) => {
                    // SAFETY: this owned pidfd cannot change while registered. It is only polled for exit.
                    let fd = unsafe { AsyncFd::register(fd) }?;
                    loop {
                        tokio::select! {
                            guard=fd.readable()=>{drop(guard?);break;}
                            msg=changes.next()=>{let msg=msg.context("lock service disconnected")?;if !msg.body().deserialize::<bool>()?{return Ok(ExitCode::SUCCESS);}}
                        }
                    }
                }
                Err(rustix::io::Errno::SRCH) => {}
                Err(e) => return Err(e.into()),
            }
            tokio::time::sleep(Duration::from_millis(250)).await;
            if active().await? {
                let dir = PathBuf::from(
                    std::env::var_os("XDG_RUNTIME_DIR").context("missing runtime directory")?,
                )
                .join("hypr")
                .join(
                    std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE")
                        .context("missing instance signature")?,
                );
                let lock = OpenOptions::new()
                    .create(true)
                    .append(true)
                    .mode(0o600)
                    .custom_flags(libc::O_NOFOLLOW)
                    .open(dir.join("velora-lock-recovery.lock"))?;
                match flock(&lock, FlockOperation::NonBlockingLockExclusive) {
                    Ok(()) => {}
                    Err(rustix::io::Errno::WOULDBLOCK) => return Ok(ExitCode::SUCCESS),
                    Err(e) => return Err(e.into()),
                }
                rustix::io::fcntl_setfd(&lock, rustix::io::FdFlags::empty())?;
                let err = Command::new("hyprlock")
                    .args(["--immediate-render", "--grace", "0"])
                    .exec();
                drop(lock);
                return Err(err.into());
            }
            Ok(ExitCode::SUCCESS)
        },
        || {},
    )
}
