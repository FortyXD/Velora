//! Native helpers for the Velora shell. Each subcommand replaces a script that ran in Python,
//! so a wallpaper or preset change spends its time on the screen instead of on interpreters.
//!
//!   scheme-for-image <image> [--colorfulness]   scheme name from the picture's colorfulness
//!   terminal-colors --source <hex> ...          material_colors.scss (terminal palette)
//!   theme stage ... / theme commit <dir>        generate every themed file aside, then put it in place at once
//!   region <image> ...                          free spot and text color for a desktop widget
//!   backlight <output>                          the backlight of a screen, as JSON
//!   keyring <status|lookup|unlock>              the login keyring
//!   toolbox-open [tab] [files...]               the toolbox, in its running window if there is one
//!   toolbox-quick <target> files...             converts from the file manager's menu
//!   top-apps                                    this user's processes, with CPU and memory
//!   layout-keys <layout> [variant]              what each key of a keyboard layout types, as JSON
//!   pick-color                                  picks a color on screen and remembers it
//!   zoom <reset|increase STEP|decrease STEP>    the screen zoom
//!   workspace <dispatcher> <target>             Win+number, by the monitor under the pointer
//!   emoji [type|copy]                           picks an emoji
//!   apps <list|set|launch|open|sync|...>        default apps and the "Open with" chooser
//!   find-regions --image <path> ...             content regions of a screenshot
//!   text-color                                  background and text color of the picture on stdin
//!   thumbnails --size <name> --directory <dir>  Freedesktop thumbnails for a folder
//!   hypr-config [--file <lua>] --set K V --reset K   edits the shell's Hyprland overrides
//!   recorder-status                             what the screen recorder is doing, as JSON
//!   toolbox-caps / toolbox-detect files...      the toolbox's installed tools, and what files are

mod apps;
mod args;
mod backlight;
mod color;
mod emoji;
mod hypr;
mod keyboard;
mod keyring;
mod picture;
mod processes;
mod recorder;
mod region;
mod regions;
mod scheme;
mod terminal;
mod textcolor;
mod theme;
mod thumbnails;
mod toolbox;

use std::process::ExitCode;

fn main() -> ExitCode {
    let mut argv: Vec<String> = std::env::args().skip(1).collect();
    if argv.is_empty() {
        eprintln!("usage: velora-helper <command> ... (see the source's first lines for the list)");
        return ExitCode::from(2);
    }
    let command = argv.remove(0);
    // These set an exit code of their own that callers go by
    let with_code = match command.as_str() {
        "keyring" => Some(keyring::run(argv.clone())),
        "toolbox-open" => Some(toolbox::open(argv.clone())),
        "toolbox-quick" => Some(toolbox::quick(argv.clone())),
        "pick-color" => Some(color::run()),
        "workspace" => Some(hypr::workspace(argv.clone())),
        "emoji" => Some(emoji::run(argv.clone())),
        _ => None,
    };
    if let Some(result) = with_code {
        return result.unwrap_or_else(|error| {
            eprintln!("velora-helper {command}: {error:#}");
            ExitCode::FAILURE
        });
    }
    let result = match command.as_str() {
        "scheme-for-image" => scheme::run(argv),
        "terminal-colors" => terminal::run(argv),
        "theme" => theme::run(argv),
        "region" => region::run(argv),
        "backlight" => backlight::run(argv),
        "top-apps" => processes::run(),
        "layout-keys" => keyboard::run(argv),
        "zoom" => hypr::zoom(argv),
        "apps" => apps::run(argv),
        "find-regions" => regions::run(argv),
        "text-color" => textcolor::run(),
        "thumbnails" => thumbnails::run(argv),
        "hypr-config" => hypr::config(argv),
        "recorder-status" => recorder::run(argv),
        "toolbox-caps" => toolbox::caps(),
        "toolbox-detect" => toolbox::detect(argv),
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
