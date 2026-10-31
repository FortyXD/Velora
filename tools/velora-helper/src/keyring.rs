//! Port of scripts/keyring/: is the login keyring open, what's stored for the shell, and opening it at unlock.

use anyhow::{bail, Result};
use std::io::{Read, Write};
use std::process::{Command, ExitCode, Stdio};

fn is_unlocked() -> bool {
    let output = Command::new("busctl")
        .args(["--user", "get-property", "org.freedesktop.secrets", "/org/freedesktop/secrets/collection/login", "org.freedesktop.Secret.Collection", "Locked"])
        .stderr(Stdio::null())
        .output();
    output.is_ok_and(|output| String::from_utf8_lossy(&output.stdout).trim() == "b false")
}

fn status() -> ExitCode {
    if is_unlocked() {
        eprintln!("Keyring is unlocked");
        ExitCode::SUCCESS
    } else {
        eprintln!("Keyring is locked");
        ExitCode::FAILURE
    }
}

/// What the shell stored, on stdout. Exit 1 means nothing is stored, 2 that the keyring is locked.
fn lookup() -> Result<ExitCode> {
    let output = Command::new("secret-tool").args(["lookup", "application", "illogical-impulse"]).stderr(Stdio::null()).output()?;
    if output.stdout.is_empty() {
        if is_unlocked() {
            println!("not found");
            return Ok(ExitCode::from(1));
        }
        println!("locked");
        return Ok(ExitCode::from(2));
    }
    std::io::stdout().write_all(&output.stdout)?;
    println!();
    Ok(ExitCode::SUCCESS)
}

/// Opens the keyring with the login password, from `UNLOCK_PASSWORD` or stdin. Exit 1 if it was open already.
fn unlock() -> Result<ExitCode> {
    if is_unlocked() {
        eprintln!("Keyring is unlocked");
        return Ok(ExitCode::from(1));
    }
    let password = match std::env::var("UNLOCK_PASSWORD") {
        Ok(password) if !password.is_empty() => password,
        _ => {
            let mut typed = String::new();
            std::io::stdin().read_to_string(&mut typed)?;
            typed.trim_end_matches('\n').to_string()
        }
    };
    let user = std::env::var("USER").unwrap_or_default();
    let _ = Command::new("killall").args(["-q", "-u", &user, "gnome-keyring-daemon"]).status();
    let mut daemon = Command::new("gnome-keyring-daemon").args(["--daemonize", "--login"]).stdin(Stdio::piped()).stdout(Stdio::null()).spawn()?;
    daemon.stdin.take().expect("stdin is piped").write_all(password.as_bytes())?;
    daemon.wait()?;
    Ok(ExitCode::SUCCESS)
}

pub fn run(argv: Vec<String>) -> Result<ExitCode> {
    match argv.first().map(String::as_str) {
        Some("status") => Ok(status()),
        Some("lookup") => lookup(),
        Some("unlock") => unlock(),
        _ => bail!("usage: velora-helper keyring <status|lookup|unlock>"),
    }
}
