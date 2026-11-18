//! GLib-backed shell commands. Other invocations of velora-helper do not load GIO.
mod chat_store;
mod gtk_controls;
mod lens_setup;
mod platform;

use anyhow::Result;
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or_default();
    let result: Result<ExitCode> = match command.as_str() {
        "gtk-window-controls" => {
            gtk_controls::run(&args.next().unwrap_or_default()).map(|()| ExitCode::SUCCESS)
        }
        "chat-store" => chat_store::run(args.collect()).map(|()| ExitCode::SUCCESS),
        "lens-setup-status" => lens_setup::run(args.next().as_deref() == Some("--watch")),
        "--version" => {
            println!("velora-desktop-state {}", env!("CARGO_PKG_VERSION"));
            Ok(ExitCode::SUCCESS)
        }
        _ => Err(anyhow::anyhow!("unknown desktop state command {command}")),
    };
    result.unwrap_or_else(|error| {
        eprintln!("velora-helper {command}: {error:#}");
        ExitCode::FAILURE
    })
}
