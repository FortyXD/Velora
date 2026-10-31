//! The Velora shell's connection to NetworkManager and BlueZ. It takes requests as JSON lines on stdin
//! and publishes state on stdout, and it exits when stdin closes.

use std::process::ExitCode;
use velora_connectivityd::app::{self, Options};

#[tokio::main(flavor = "current_thread")]
async fn main() -> ExitCode {
    let mut options = Options::default();
    for argument in std::env::args().skip(1) {
        match argument.as_str() {
            "--agents" => options.agents = true,
            "--version" => {
                println!("velora-connectivityd {}", env!("CARGO_PKG_VERSION"));
                return ExitCode::SUCCESS;
            }
            other => {
                eprintln!("velora-connectivityd: unknown option: {other}");
                return ExitCode::from(2);
            }
        }
    }
    match app::run(options).await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("velora-connectivityd: {error:#}");
            ExitCode::FAILURE
        }
    }
}
