//! Native helpers for the Velora shell. Each subcommand replaces a script that ran in Python,
//! for previews, palettes, Toolbox jobs and the shell’s background services.
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
//!   toolbox <convert|download|info|qr-encode|qr-scan|ocr|palette> ...
//!   quicklook PATH --directory DIR              bounded local file previews
//!   window-previews                             subscription-driven capture on stdin/stdout
//!   power-analytics <collect|watch|clear>        battery history and graphs
//!   recorder <toggle|stop|status|watch|sources>        screen and audio recording
//!   chat-store DIR / local-ollama [cpu|gpu]      local assistant services
//!   cloud-screen / cloud-token                  Google Cloud requests from stdin
//!   weather-location / lock-recovery PID         GeoClue and screen lock services
//!   create-archive / assistant-select            file manager actions
//!   terminal-apply / kde-theme / kvantum-theme   apply generated palettes
//!   tmux-open-link / wallpaper-filename          validate and handle desktop URLs
//!   gtk-window-controls MODE                     GTK decoration layout
//!   recorder-status                             what the screen recorder is doing, as JSON
//!   toolbox-caps / toolbox-detect files...      the toolbox's installed tools, and what files are

mod apps;
mod args;
mod backlight;
mod cloud;
mod color;
mod desktop_bus;
mod dolphin;
mod emoji;
mod hypr;
mod keyboard;
mod keyring;
mod links;
mod ollama;
mod palette;
mod picture;
mod platform;
mod power;
mod previews;
mod processes;
mod quicklook;
mod recorder;
mod region;
mod regions;
mod scheme;
mod subprocess;
mod terminal;
mod textcolor;
mod theme;
mod thumbnails;
mod toolbox;

use std::process::ExitCode;

fn main() -> ExitCode {
    let mut argv = std::env::args().skip(1);
    let Some(command) = argv.next() else {
        eprintln!("usage: velora-helper <command> ... (see the source's first lines for the list)");
        return ExitCode::from(2);
    };
    dispatch(&command, argv.collect()).unwrap_or_else(|error| {
        eprintln!("velora-helper {command}: {error:#}");
        ExitCode::FAILURE
    })
}

fn dispatch(command: &str, argv: Vec<String>) -> anyhow::Result<ExitCode> {
    match command {
        "gtk-window-controls" | "chat-store" | "lens-setup-status" => {
            use std::os::unix::process::CommandExt;
            let program = std::env::current_exe()?.with_file_name("velora-desktop-state");
            let error = std::process::Command::new(&program)
                .arg(command)
                .args(argv)
                .exec();
            return Err(
                anyhow::Error::new(error).context(format!("Could not start {}", program.display()))
            );
        }
        "keyring" => return keyring::run(argv),
        "toolbox-open" => return toolbox::open(argv),
        "toolbox-quick" => return toolbox::quick(argv),
        "toolbox" => return toolbox::job(argv),
        "recorder" => return recorder::control::run(argv),
        "tmux-open-link" => return links::tmux(&argv),
        "quicklook" => return quicklook::run(argv),
        "weather-location" => return desktop_bus::weather(),
        "lock-recovery" => return desktop_bus::lock_recovery(argv),
        "create-archive" => return dolphin::compress(argv),
        "local-ollama" => return ollama::run(argv),
        "power-analytics" => return power::run(argv),
        "window-previews" => return previews::run(),
        "pick-color" => return color::run(),
        "workspace" => return hypr::workspace(argv),
        "emoji" => return emoji::run(argv),
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
        "recorder-child-gate" => recorder::control::gate(argv),
        "toolbox-caps" => toolbox::caps(),
        "toolbox-detect" => toolbox::detect(argv),
        "wallpaper-filename" => links::wallpaper(argv.first().map_or("", String::as_str)),
        "terminal-apply" => palette::terminals(),
        "kde-theme" => palette::kde(),
        "kvantum-config" => palette::kvantum_config(),
        "kvantum-theme" => palette::kvantum(argv.first().map_or("", String::as_str)),
        "cloud-screen" => cloud::run(false),
        "cloud-token" => cloud::run(true),
        "assistant-select" => dolphin::select(argv),
        "--version" => {
            println!("velora-helper {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        other => Err(anyhow::anyhow!("unknown command: {other}")),
    }?;
    Ok(ExitCode::SUCCESS)
}
