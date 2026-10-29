//! Native helpers for the Velora shell. Each subcommand replaces a script that ran in Python,
//! so a wallpaper or preset change spends its time on the screen instead of on interpreters.
//!
//!   scheme-for-image <image> [--colorfulness]   scheme name from the picture's colorfulness
//!   terminal-colors --source <hex> ...          material_colors.scss (terminal palette)
//!   theme stage ... / theme commit <dir>        generate every themed file aside, then put it in place at once
//!   region <image> ...                          free spot and text color for a desktop widget

mod args;
mod picture;
mod region;
mod scheme;
mod terminal;
mod theme;

use std::process::ExitCode;

fn main() -> ExitCode {
    let mut argv: Vec<String> = std::env::args().skip(1).collect();
    if argv.is_empty() {
        eprintln!("usage: velora-helper <scheme-for-image|terminal-colors|theme|region> ...");
        return ExitCode::from(2);
    }
    let command = argv.remove(0);
    let result = match command.as_str() {
        "scheme-for-image" => scheme::run(argv),
        "terminal-colors" => terminal::run(argv),
        "theme" => theme::run(argv),
        "region" => region::run(argv),
        "--version" => {
            println!("velora-helper {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        other => Err(anyhow::anyhow!("unknown command: {other}")),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("velora-helper {command}: {error:#}");
            ExitCode::FAILURE
        }
    }
}
