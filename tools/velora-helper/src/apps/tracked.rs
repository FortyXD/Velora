use super::{expand_exec, home, parse_desktop_file, shell_split, spawn_detached, which, App, Apps};
use anyhow::{Context, Result};
use gio::glib::SpawnFlags;
use gio::prelude::AppLaunchContextExt;
use serde_json::{json, Value};
use std::path::Path;
use std::process::Command;

/// Keep desktop-file arguments as argv all the way through the terminal.
fn terminal_command(preferred: &str, app: &App, token: &str) -> Result<(Command, Option<String>)> {
    let preferred =
        shell_split(preferred).filter(|argv| argv.first().is_some_and(|s| which(s).is_some()));
    let argv = preferred
        .or_else(|| {
            [
                "kitty",
                "foot",
                "alacritty",
                "wezterm",
                "ghostty",
                "konsole",
                "kgx",
                "gnome-terminal",
                "xdg-terminal-exec",
                "xterm",
            ]
            .into_iter()
            .find(|name| which(name).is_some())
            .map(|name| vec![name.to_owned()])
        })
        .context("No terminal emulator is available for this application")?;
    let terminal = Path::new(&argv[0])
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("");
    let mut cmd = Command::new(&argv[0]);
    let id = app.id.trim_end_matches(".desktop");
    let args = &argv[1..];
    let mut initial_title = None;
    match terminal {
        "kitty" => {
            // A dedicated process gives the terminal program its own surface and lifecycle.
            cmd.args(args.iter().filter(|arg| {
                !matches!(
                    arg.as_str(),
                    "-1" | "--single-instance" | "--single-instance=yes"
                )
            }));
            cmd.args(["--class", id, "--"]);
        }
        "foot" | "footclient" => {
            cmd.args(args).args(["--app-id", id, "--"]);
        }
        "alacritty" => {
            cmd.args(args).args(["--class", id, "-e"]);
        }
        "wezterm" => {
            cmd.args(args);
            if !args.iter().any(|a| a == "start") {
                cmd.arg("start");
            }
            cmd.args(["--always-new-process", "--class", id, "--"]);
        }
        "xterm" => {
            cmd.args(args).args(["-class", id, "-e"]);
        }
        "konsole" => {
            cmd.args(args).args(["--separate", "-e"]);
        }
        "ghostty" => {
            cmd.args(args).args(["--gtk-single-instance=false", "-e"]);
        }
        "kgx" | "gnome-terminal" => {
            // These clients may forward to an existing process shared by unrelated windows.
            let title = format!("{} · {}", app.name, &token[..8]);
            cmd.args(args).args(["--title", &title, "--"]);
            initial_title = Some(title);
        }
        "xdg-terminal-exec" => {
            cmd.args(args);
        }
        _ => {
            cmd.args(args).arg("-e");
        }
    }
    Ok((cmd, initial_title))
}

pub(super) fn open(apps: &Apps, id: &str, terminal: &str) -> Result<Value> {
    let app = apps
        .get(id)
        .or_else(|| apps.get(&format!("{id}.desktop")))
        .context("Desktop entry is no longer installed")?;
    let token = std::fs::read_to_string("/proc/sys/kernel/random/uuid")?
        .trim()
        .to_owned();
    anyhow::ensure!(
        token.len() == 36 && token.is_ascii(),
        "Could not create a launch identifier"
    );
    if !app.terminal {
        // GIO preserves desktop activation, field codes and the entry's working directory.
        let entry = gio::DesktopAppInfo::from_filename(&app.path)
            .with_context(|| format!("Cannot load the desktop entry for {}", app.name))?;
        let launch = gio::AppLaunchContext::new();
        launch.setenv("VELORA_LAUNCH_ID", &token);
        let mut pid = None;
        std::env::set_current_dir(home())?;
        entry
            .launch_uris_as_manager(
                &[],
                Some(&launch),
                SpawnFlags::SEARCH_PATH
                    | SpawnFlags::STDOUT_TO_DEV_NULL
                    | SpawnFlags::STDERR_TO_DEV_NULL,
                None,
                Some(&mut |_, child| pid = u32::try_from(child.0).ok().filter(|pid| *pid > 0)),
            )
            .with_context(|| format!("Could not start {}", app.name))?;
        return Ok(json!({"token":token, "pid":pid}));
    }
    let arguments = expand_exec(app, &[])
        .into_iter()
        .next()
        .context("Desktop entry has no executable")?;
    let (program, args) = arguments
        .split_first()
        .context("Desktop entry has no executable")?;
    let directory = parse_desktop_file(&app.path)
        .and_then(|mut entry| entry.remove("Path"))
        .filter(|p| !p.is_empty())
        .map(std::path::PathBuf::from)
        .unwrap_or_else(home);
    let executable = if program.contains('/') {
        directory.join(program)
    } else {
        program.into()
    };
    anyhow::ensure!(
        executable.to_str().and_then(which).is_some(),
        "The executable {program} for {} is unavailable",
        app.name
    );
    let (mut cmd, initial_title) = terminal_command(terminal, app, &token)?;
    cmd.current_dir(directory)
        .arg(program)
        .args(args)
        .env("VELORA_LAUNCH_ID", &token);
    let child =
        spawn_detached(&mut cmd).with_context(|| format!("Could not start {}", app.name))?;
    Ok(json!({"token":token, "pid":child.id(), "initial_title":initial_title}))
}
