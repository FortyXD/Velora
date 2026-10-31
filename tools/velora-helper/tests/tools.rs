//! The helper as the shell runs it, with stand-ins for the programs it calls.

use std::fs;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

struct Sandbox {
    root: PathBuf,
}

impl Sandbox {
    fn new(name: &str) -> Self {
        let root = std::env::temp_dir().join(format!("velora-helper-test-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(root.join("bin")).unwrap();
        Self { root }
    }

    /// A program that logs its arguments and stdin, prints this and exits with this code.
    fn tool(&self, name: &str, stdout: &str, code: i32) {
        let path = self.root.join("bin").join(name);
        let log = self.root.join("log");
        fs::write(&path, format!("#!/bin/sh\nprintf '%s' '{name}' >> '{log}'\nfor a in \"$@\"; do printf ' [%s]' \"$a\" >> '{log}'; done\nif [ ! -t 0 ]; then in=$(cat); [ -n \"$in\" ] && printf ' stdin=%s' \"$in\" >> '{log}'; fi\nprintf '\\n' >> '{log}'\nprintf '%s' '{stdout}'\nexit {code}\n", log = log.display())).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    }

    fn log(&self) -> String {
        fs::read_to_string(self.root.join("log")).unwrap_or_default()
    }

    fn command(&self, arguments: &[&str]) -> Command {
        let mut command = Command::new(env!("CARGO_BIN_EXE_velora-helper"));
        command
            .args(arguments)
            .env("PATH", format!("{}:/usr/bin:/bin", self.root.join("bin").display()))
            .env("HOME", &self.root)
            .env("XDG_STATE_HOME", self.root.join("state"))
            .env("XDG_CACHE_HOME", self.root.join("cache"))
            .env("VELORA_SHELL_DIR", self.root.join("shell"))
            .stdin(Stdio::null());
        command
    }

    fn run(&self, arguments: &[&str]) -> Output {
        self.command(arguments).output().unwrap()
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

fn text(output: &Output) -> String {
    String::from_utf8_lossy(&output.stdout).into_owned()
}

// ---- backlight ----

struct Sys {
    sandbox: Sandbox,
}

impl Sys {
    fn new(name: &str) -> Self {
        let sandbox = Sandbox::new(name);
        fs::create_dir_all(sandbox.root.join("backlight")).unwrap();
        fs::create_dir_all(sandbox.root.join("drm")).unwrap();
        Self { sandbox }
    }

    fn connector(&self, card: u32, output: &str, status: &str) -> (PathBuf, PathBuf) {
        let gpu = self.sandbox.root.join(format!("gpu{card}"));
        let card_path = gpu.join("drm").join(format!("card{card}"));
        fs::create_dir_all(&card_path).unwrap();
        if !card_path.join("device").exists() {
            symlink(&gpu, card_path.join("device")).unwrap();
        }
        let connector = card_path.join(format!("card{card}-{output}"));
        fs::create_dir_all(&connector).unwrap();
        fs::write(connector.join("status"), status).unwrap();
        symlink(&connector, self.sandbox.root.join("drm").join(format!("card{card}-{output}"))).unwrap();
        (connector, gpu)
    }

    fn device(&self, name: &str, parent: &Path, owner: &Path, current: i64, maximum: i64, kind: &str) {
        let device = parent.join(name);
        fs::create_dir_all(&device).unwrap();
        symlink(owner, device.join("device")).unwrap();
        fs::write(device.join("brightness"), current.to_string()).unwrap();
        fs::write(device.join("max_brightness"), maximum.to_string()).unwrap();
        fs::write(device.join("type"), kind).unwrap();
        symlink(&device, self.sandbox.root.join("backlight").join(name)).unwrap();
    }

    fn select(&self, output: &str) -> Output {
        self.sandbox.command(&["backlight", output]).env("VELORA_SYS_BACKLIGHT", self.sandbox.root.join("backlight")).env("VELORA_SYS_DRM", self.sandbox.root.join("drm")).output().unwrap()
    }
}

#[test]
fn a_hybrid_laptop_uses_the_connected_panel_instead_of_the_unused_gpu() {
    let sys = Sys::new("hybrid");
    let (panel, _) = sys.connector(1, "eDP-1", "connected");
    let (_, nvidia) = sys.connector(0, "eDP-2", "disconnected");
    sys.device("nvidia_0", &nvidia, &nvidia, 100, 100, "raw");
    sys.device("amdgpu_bl1", &panel, &panel, 200_000, 400_000, "raw");
    assert_eq!(text(&sys.select("eDP-1")).trim(), r#"{"device":"amdgpu_bl1","current":200000,"max":400000}"#);
}

#[test]
fn a_gpu_switch_selects_the_gpu_that_drives_the_panel() {
    let sys = Sys::new("switch");
    let (panel, _) = sys.connector(1, "eDP-1", "disconnected");
    let (_, nvidia) = sys.connector(0, "eDP-2", "connected");
    sys.device("amdgpu_bl1", &panel, &panel, 50, 100, "raw");
    sys.device("nvidia_0", &nvidia, &nvidia, 50, 100, "raw");
    assert!(text(&sys.select("eDP-2")).contains("nvidia_0"));
}

#[test]
fn a_platform_backlight_needs_no_drm_parent() {
    let sys = Sys::new("platform");
    sys.connector(0, "eDP-1", "connected");
    let platform = sys.sandbox.root.join("platform");
    fs::create_dir_all(&platform).unwrap();
    sys.device("acpi_video0", &platform, &platform, 50, 100, "firmware");
    assert!(text(&sys.select("eDP-1")).contains("acpi_video0"));
}

#[test]
fn an_external_screen_doesnt_control_the_internal_backlight() {
    let sys = Sys::new("external");
    let (panel, _) = sys.connector(1, "eDP-1", "connected");
    sys.connector(1, "DP-1", "connected");
    sys.device("amdgpu_bl1", &panel, &panel, 50, 100, "raw");
    let output = sys.select("DP-1");
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("No backlight for DP-1"));
}

#[test]
fn a_missing_or_invalid_backlight_reports_unavailable() {
    let sys = Sys::new("missing");
    let (panel, _) = sys.connector(1, "eDP-1", "connected");
    assert_eq!(sys.select("eDP-1").status.code(), Some(1));
    sys.device("amdgpu_bl1", &panel, &panel, 0, 0, "raw");
    let output = sys.select("eDP-1");
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("Invalid brightness"));
}

// ---- keyring ----

#[test]
fn the_keyring_status_comes_from_its_locked_property() {
    let sandbox = Sandbox::new("keyring-status");
    sandbox.tool("busctl", "b false", 0);
    assert_eq!(sandbox.run(&["keyring", "status"]).status.code(), Some(0));
    sandbox.tool("busctl", "b true", 0);
    assert_eq!(sandbox.run(&["keyring", "status"]).status.code(), Some(1));
    sandbox.tool("busctl", "", 1);
    assert_eq!(sandbox.run(&["keyring", "status"]).status.code(), Some(1));
}

#[test]
fn a_keyring_lookup_tells_nothing_stored_from_locked() {
    let sandbox = Sandbox::new("keyring-lookup");
    sandbox.tool("secret-tool", "{\"a\":1}", 0);
    let found = sandbox.run(&["keyring", "lookup"]);
    assert_eq!((found.status.code(), text(&found).trim()), (Some(0), "{\"a\":1}"));

    sandbox.tool("secret-tool", "", 1);
    sandbox.tool("busctl", "b false", 0);
    let absent = sandbox.run(&["keyring", "lookup"]);
    assert_eq!((absent.status.code(), text(&absent).trim()), (Some(1), "not found"));

    sandbox.tool("busctl", "b true", 0);
    let locked = sandbox.run(&["keyring", "lookup"]);
    assert_eq!((locked.status.code(), text(&locked).trim()), (Some(2), "locked"));
}

#[test]
fn unlocking_hands_the_password_over_stdin_only() {
    let sandbox = Sandbox::new("keyring-unlock");
    sandbox.tool("busctl", "b true", 0);
    sandbox.tool("killall", "", 0);
    sandbox.tool("gnome-keyring-daemon", "", 0);
    let output = sandbox.command(&["keyring", "unlock"]).env("UNLOCK_PASSWORD", "marker-pass").env("USER", "me").output().unwrap();
    assert_eq!(output.status.code(), Some(0));
    let log = sandbox.log();
    assert!(log.contains("killall [-q] [-u] [me] [gnome-keyring-daemon]"), "{log}");
    assert!(log.contains("gnome-keyring-daemon [--daemonize] [--login] stdin=marker-pass"), "{log}");
    assert!(!log.contains("[marker-pass]"));
}

#[test]
fn an_open_keyring_isnt_touched() {
    let sandbox = Sandbox::new("keyring-open");
    sandbox.tool("busctl", "b false", 0);
    sandbox.tool("killall", "", 0);
    sandbox.tool("gnome-keyring-daemon", "", 0);
    let output = sandbox.command(&["keyring", "unlock"]).env("UNLOCK_PASSWORD", "x").output().unwrap();
    assert_eq!(output.status.code(), Some(1));
    assert!(!sandbox.log().contains("killall"));
}

// ---- picking a color ----

#[test]
fn a_picked_color_is_printed_and_remembered() {
    let sandbox = Sandbox::new("color");
    sandbox.tool("hyprpicker", "#ab12cd\n", 0);
    let output = sandbox.run(&["pick-color"]);
    assert_eq!((output.status.code(), text(&output).trim()), (Some(0), "#AB12CD"));
    let file = sandbox.root.join("state/quickshell/user/color_history.json");
    assert_eq!(fs::read_to_string(&file).unwrap(), r##"["#AB12CD"]"##);
    sandbox.tool("hyprpicker", "#000000\n", 0);
    sandbox.run(&["pick-color"]);
    sandbox.tool("hyprpicker", "#ab12cd\n", 0);
    sandbox.run(&["pick-color"]);
    assert_eq!(fs::read_to_string(&file).unwrap(), r##"["#AB12CD","#000000"]"##);
}

#[test]
fn canceling_the_picker_changes_nothing() {
    let sandbox = Sandbox::new("color-cancel");
    sandbox.tool("hyprpicker", "", 1);
    assert_eq!(sandbox.run(&["pick-color"]).status.code(), Some(1));
    assert!(!sandbox.root.join("state").exists());
    sandbox.tool("hyprpicker", "nonsense", 0);
    assert_eq!(sandbox.run(&["pick-color"]).status.code(), Some(1));
}

// ---- zoom and workspaces ----

fn zoom_log(start: &str, arguments: &[&str]) -> String {
    let sandbox = Sandbox::new(&format!("zoom-{}-{}", start.replace('.', "_"), arguments.join("-")));
    sandbox.tool("hyprctl", &format!("{{\"option\":\"cursor:zoom_factor\",\"float\":{start},\"set\":true}}"), 0);
    let mut all = vec!["zoom"];
    all.extend_from_slice(arguments);
    assert_eq!(sandbox.run(&all).status.code(), Some(0));
    sandbox.log().lines().last().unwrap().to_string()
}

#[test]
fn zoom_steps_and_stays_in_range() {
    assert!(zoom_log("1.0", &["increase", "0.3"]).contains("zoom_factor = 1.3 "));
    assert!(zoom_log("1.3", &["decrease", "0.1"]).contains("zoom_factor = 1.2 "));
    assert!(zoom_log("2.9", &["increase", "0.3"]).contains("zoom_factor = 3 "));
    assert!(zoom_log("1.0", &["decrease", "0.3"]).contains("zoom_factor = 1 "));
    assert!(zoom_log("2.0", &["reset"]).contains("zoom_factor = 1 "));
}

#[test]
fn zoom_wants_a_step_and_a_known_action() {
    let sandbox = Sandbox::new("zoom-usage");
    sandbox.tool("hyprctl", "{\"float\":1.0}", 0);
    assert_eq!(sandbox.run(&["zoom", "increase"]).status.code(), Some(1));
    assert_eq!(sandbox.run(&["zoom", "sideways"]).status.code(), Some(1));
    assert_eq!(sandbox.run(&["zoom"]).status.code(), Some(1));
}

fn hyprctl_script(sandbox: &Sandbox) {
    let path = sandbox.root.join("bin/hyprctl");
    let log = sandbox.root.join("log");
    let monitors = r#"[{"name":"LEFT","x":0,"y":0,"width":1000,"height":1000,"scale":1.0,"transform":0,"focused":false,"activeWorkspace":{"id":3}},{"name":"RIGHT","x":1000,"y":0,"width":1000,"height":1000,"scale":1.0,"transform":0,"focused":true,"activeWorkspace":{"id":14}}]"#;
    fs::write(&path, format!("#!/bin/sh\ncase \"$1\" in\n cursorpos) echo '{{\"x\":1500,\"y\":10}}' ;;\n monitors) echo '{monitors}' ;;\n activeworkspace) echo '{{\"id\":24}}' ;;\n *) printf '%s\\n' \"$*\" >> '{}' ;;\nesac\n", log.display())).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
}

#[test]
fn win_number_goes_by_the_monitor_under_the_pointer() {
    let sandbox = Sandbox::new("workspace");
    hyprctl_script(&sandbox);
    assert_eq!(sandbox.run(&["workspace", "workspace", "3"]).status.code(), Some(0));
    assert_eq!(sandbox.log(), "dispatch hl.dsp.focus({ monitor = \"RIGHT\" })\ndispatch hl.dsp.focus({ workspace = \"13\" })\n");
}

#[test]
fn moving_a_window_goes_by_the_active_workspace_and_stays_put() {
    let sandbox = Sandbox::new("workspace-move");
    hyprctl_script(&sandbox);
    assert_eq!(sandbox.run(&["workspace", "movetoworkspacesilent", "5"]).status.code(), Some(0));
    assert_eq!(sandbox.log(), "dispatch hl.dsp.window.move({ workspace = \"25\", follow = false })\n");
}

#[test]
fn relative_and_named_workspaces_pass_through() {
    let sandbox = Sandbox::new("workspace-named");
    hyprctl_script(&sandbox);
    sandbox.run(&["workspace", "workspace", "r+1"]);
    assert!(sandbox.log().contains("workspace = \"r+1\""));
    sandbox.run(&["workspace", "workspace", "special:music"]);
    assert!(sandbox.log().contains("workspace = \"special:music\""));
}

#[test]
fn unknown_dispatchers_and_missing_targets_are_refused() {
    let sandbox = Sandbox::new("workspace-bad");
    hyprctl_script(&sandbox);
    assert_eq!(sandbox.run(&["workspace", "nonsense", "1"]).status.code(), Some(1));
    assert_eq!(sandbox.run(&["workspace", "workspace"]).status.code(), Some(1));
    assert_eq!(sandbox.log(), "");
}

// ---- the toolbox ----

#[test]
fn a_running_toolbox_gets_the_tab_and_files_over_ipc() {
    let sandbox = Sandbox::new("toolbox-ipc");
    sandbox.tool("qs", "", 0);
    sandbox.tool("hyprctl", "", 0);
    let file = sandbox.root.join("a.png");
    fs::write(&file, "").unwrap();
    let output = sandbox.run(&["toolbox-open", "qr", file.to_str().unwrap()]);
    assert_eq!(output.status.code(), Some(0));
    let log = sandbox.log();
    assert!(log.contains("[ipc] [call] [toolbox] [open] [qr]"), "{log}");
    assert!(log.contains("a.png"), "{log}");
    assert!(log.contains("hyprctl [dispatch]"), "{log}");
    assert_eq!(log.matches("qs ").count(), 1);
}

#[test]
fn without_a_running_toolbox_it_starts_one_with_the_tab() {
    let sandbox = Sandbox::new("toolbox-new");
    let path = sandbox.root.join("bin/qs");
    let log = sandbox.root.join("log");
    fs::write(&path, format!("#!/bin/sh\ncase \"$*\" in *ipc*) exit 1 ;; esac\nprintf 'tab=%s files=%s\\n' \"$TOOLBOX_TAB\" \"$TOOLBOX_FILES\" >> '{}'\n", log.display())).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    assert_eq!(sandbox.run(&["toolbox-open"]).status.code(), Some(0));
    assert_eq!(sandbox.log(), "tab=converter files=\n");
}

#[test]
fn a_quick_conversion_without_files_does_nothing() {
    let sandbox = Sandbox::new("quick-empty");
    assert_eq!(sandbox.run(&["toolbox-quick", "png"]).status.code(), Some(1));
    assert_eq!(sandbox.run(&["toolbox-quick"]).status.code(), Some(1));
}

// ---- layouts and processes ----

#[test]
fn a_cached_layout_comes_back_without_compiling() {
    let sandbox = Sandbox::new("layout");
    let cache = sandbox.root.join("cache/quickshell/keyboard");
    fs::create_dir_all(&cache).unwrap();
    fs::write(cache.join("xx-standard.json"), r#"{"cached":true}"#).unwrap();
    fs::write(cache.join("xx-v.json"), r#"{"variant":true}"#).unwrap();
    assert_eq!(text(&sandbox.run(&["layout-keys", "xx"])).trim(), r#"{"cached":true}"#);
    assert_eq!(text(&sandbox.run(&["layout-keys", "xx", "v"])).trim(), r#"{"variant":true}"#);
}

#[test]
fn a_bad_layout_name_never_reaches_the_compiler() {
    let sandbox = Sandbox::new("layout-bad");
    assert_eq!(sandbox.run(&["layout-keys", "x;rm"]).status.code(), Some(1));
    assert_eq!(sandbox.run(&["layout-keys", "us", "a b"]).status.code(), Some(1));
}

#[test]
fn processes_are_listed_with_the_cpu_count_first() {
    let output = Sandbox::new("top").run(&["top-apps"]);
    let report = text(&output);
    let mut lines = report.lines();
    assert!(lines.next().unwrap().starts_with("N "));
    let mine = std::process::id().to_string();
    let row: Vec<&str> = lines.find(|line| line.split('\t').next() == Some(mine.as_str())).expect("this test process is listed").split('\t').collect();
    assert_eq!(row.len(), 4);
    row[1].parse::<f64>().unwrap();
    row[2].parse::<i64>().unwrap();
}

#[test]
fn an_unknown_command_is_refused() {
    assert_eq!(Sandbox::new("unknown").run(&["nonsense"]).status.code(), Some(1));
}

// ---- default apps ----

/// A sandbox with its own XDG directories, a few apps, and stand-ins for what the tool starts.
fn apps_sandbox(name: &str) -> Sandbox {
    let sandbox = Sandbox::new(name);
    for tool in ["gio", "xdg-mime", "kwriteconfig6", "kbuildsycoca6", "update-desktop-database", "notify-send", "dolphin", "qs", "web"] {
        sandbox.tool(tool, "", 0);
    }
    let applications = sandbox.root.join("data/applications");
    fs::create_dir_all(&applications).unwrap();
    fs::create_dir_all(sandbox.root.join("config")).unwrap();
    fs::create_dir_all(sandbox.root.join("system/mime")).unwrap();
    fs::write(sandbox.root.join("system/mime/types"), "text/plain\ntext/x-new\ninode/directory\nimage/png\n").unwrap();
    fs::write(sandbox.root.join("system/mime/subclasses"), "text/x-new text/plain\n").unwrap();
    fs::write(sandbox.root.join("system/mime/aliases"), "text/x-old text/x-new\n").unwrap();
    let entry = |id: &str, body: &str| fs::write(applications.join(id), format!("[Desktop Entry]\nType=Application\n{body}\n")).unwrap();
    entry("editor.desktop", "Name=Editor\nName[ru]=Редактор\nExec=editor %F\nIcon=ed\nMimeType=text/plain;\nCategories=TextEditor;");
    entry("web.desktop", "Name=Web\nExec=web %u\nMimeType=x-scheme-handler/https;x-scheme-handler/http;text/html;\nCategories=WebBrowser;");
    entry("term.desktop", "Name=Term\nExec=term\nCategories=TerminalEmulator;");
    entry("hidden.desktop", "Name=Hidden\nExec=hidden\nNoDisplay=true\nMimeType=text/plain;");
    entry("gone.desktop", "Name=Gone\nExec=gone\nTryExec=/nonexistent/gone\nMimeType=text/plain;");
    sandbox
}

fn apps(sandbox: &Sandbox, arguments: &[&str]) -> Output {
    let mut all = vec!["apps"];
    all.extend_from_slice(arguments);
    sandbox.command(&all)
        .env("XDG_CONFIG_HOME", sandbox.root.join("config"))
        .env("XDG_DATA_HOME", sandbox.root.join("data"))
        .env("XDG_DATA_DIRS", sandbox.root.join("system"))
        .env("XDG_CONFIG_DIRS", sandbox.root.join("etc"))
        .env("XDG_CURRENT_DESKTOP", "Hyprland")
        .env("LANG", "ru_RU.UTF-8")
        .env_remove("LC_MESSAGES")
        .output()
        .unwrap()
}

/// What a detached child logged: it may finish just after the helper does.
fn wait_for_log(sandbox: &Sandbox, wanted: &str) -> String {
    for _ in 0..200 {
        let log = sandbox.log();
        if log.contains(wanted) {
            return log;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    sandbox.log()
}

#[test]
fn the_app_list_has_roles_names_in_the_language_and_hides_what_it_should() {
    let sandbox = apps_sandbox("apps-list");
    let output = apps(&sandbox, &["list", "ru_RU"]);
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    let list: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    let names: Vec<&str> = list["apps"].as_array().unwrap().iter().map(|app| app["name"].as_str().unwrap()).collect();
    assert_eq!(names, ["Term", "Web", "Редактор"]);
    let text = list["roles"].as_array().unwrap().iter().find(|role| role["id"] == "text").unwrap();
    assert_eq!(text["candidates"][0]["id"], "editor.desktop");
    assert_eq!(text["allowsAsk"], true);
    let terminal = list["roles"].as_array().unwrap().iter().find(|role| role["id"] == "terminal").unwrap();
    assert_eq!(terminal["current"]["app"]["id"], "term.desktop");
    assert_eq!(terminal["allowsCommand"], true);
}

#[test]
fn choosing_an_app_writes_mimeapps_and_keeps_the_rest_of_the_file() {
    let sandbox = apps_sandbox("apps-set");
    let list = sandbox.root.join("config/mimeapps.list");
    fs::write(&list, "[Other]\nkeep=me\n\n[Default Applications]\nimage/png=viewer.desktop\ntext/plain=old.desktop\n\n[Added Associations]\ntext/plain=old.desktop;\n").unwrap();
    assert!(apps(&sandbox, &["set", "text", "editor.desktop"]).status.success());
    let written = fs::read_to_string(&list).unwrap();
    assert!(written.contains("keep=me"), "{written}");
    assert!(written.contains("image/png=viewer.desktop"), "{written}");
    assert!(written.contains("\ntext/plain=editor.desktop\n"), "{written}");
    assert!(written.contains("text/plain=editor.desktop;old.desktop;"), "{written}");
}

#[test]
fn a_mimeapps_file_that_isnt_text_is_never_overwritten() {
    let sandbox = apps_sandbox("apps-binary");
    let list = sandbox.root.join("config/mimeapps.list");
    fs::write(&list, b"[Default Applications]\n\xff\xfe\n").unwrap();
    assert!(!apps(&sandbox, &["set", "text", "editor.desktop"]).status.success());
    assert_eq!(fs::read(&list).unwrap(), b"[Default Applications]\n\xff\xfe\n");
}

#[test]
fn a_command_role_is_stored_and_launched_through_the_shell() {
    let sandbox = apps_sandbox("apps-command");
    assert!(apps(&sandbox, &["set-command", "terminal", " web --here ", "Mine"]).status.success());
    let store: serde_json::Value = serde_json::from_str(&fs::read_to_string(sandbox.root.join("config/hypr/custom/default_apps.json")).unwrap()).unwrap();
    assert_eq!(store["terminal"], serde_json::json!({ "command": "web --here", "name": "Mine" }));
    assert!(sandbox.log().contains("kwriteconfig6"), "{}", sandbox.log());
    assert!(apps(&sandbox, &["launch", "terminal"]).status.success());
    assert!(wait_for_log(&sandbox, "web [--here]").contains("web [--here]"), "{}", sandbox.log());
    assert!(!apps(&sandbox, &["set-command", "text", "x"]).status.success());
}

#[test]
fn launching_goes_through_gio_with_the_desktop_file() {
    let sandbox = apps_sandbox("apps-launch");
    assert!(apps(&sandbox, &["set", "code", "editor.desktop"]).status.success());
    assert!(apps(&sandbox, &["launch", "code"]).status.success());
    let log = wait_for_log(&sandbox, "gio [launch]");
    assert!(log.contains(&format!("gio [launch] [{}]", sandbox.root.join("data/applications/editor.desktop").display())), "{log}");
}

#[test]
fn a_web_address_goes_straight_to_the_app_and_files_become_paths() {
    let sandbox = apps_sandbox("apps-open");
    assert!(apps(&sandbox, &["open", "web", "https://example.com/?a=b"]).status.success());
    assert!(wait_for_log(&sandbox, "web [https").contains("web [https://example.com/?a=b]"), "{}", sandbox.log());
    assert!(apps(&sandbox, &["open", "editor.desktop", "file:///tmp/a%20b.txt"]).status.success());
    assert!(wait_for_log(&sandbox, "a b.txt").contains("[/tmp/a b.txt]"), "{}", sandbox.log());
    assert!(!apps(&sandbox, &["open", "nope"]).status.success());
}

#[test]
fn a_missing_default_tells_the_user() {
    let sandbox = apps_sandbox("apps-none");
    assert!(apps(&sandbox, &["launch", "pdf"]).status.success());
    assert!(sandbox.log().contains("No default app"), "{}", sandbox.log());
    assert!(!apps(&sandbox, &["launch", "nope"]).status.success());
}

#[test]
fn sync_installs_the_chooser_and_hands_it_new_types_only() {
    let sandbox = apps_sandbox("apps-sync");
    fs::write(sandbox.root.join("config/mimeapps.list"), "[Default Applications]\nimage/png=mine.desktop\n").unwrap();
    assert!(apps(&sandbox, &["sync"]).status.success());
    let chooser = fs::read_to_string(sandbox.root.join("data/applications/folis-open-with.desktop")).unwrap();
    let launcher = sandbox.root.join("config/quickshell/ii/scripts/helper");
    assert!(chooser.contains(&format!("Exec={} apps open-with %U", launcher.display())), "{chooser}");
    let written = fs::read_to_string(sandbox.root.join("config/mimeapps.list")).unwrap();
    assert!(written.contains("image/png=mine.desktop"), "{written}");
    assert!(written.contains("text/x-new=folis-open-with.desktop"), "{written}");
    assert!(!written.contains("inode/directory=folis"), "{written}");
    let before = written.clone();
    assert!(apps(&sandbox, &["sync"]).status.success());
    assert_eq!(fs::read_to_string(sandbox.root.join("config/mimeapps.list")).unwrap(), before);
}

#[test]
fn remembering_and_forgetting_a_file_type() {
    let sandbox = apps_sandbox("apps-mime");
    assert!(apps(&sandbox, &["set-mime", "editor.desktop", "text/x-new"]).status.success());
    let list: serde_json::Value = serde_json::from_slice(&apps(&sandbox, &["list"]).stdout).unwrap();
    assert_eq!(list["types"][0]["mime"], "text/x-new");
    assert_eq!(list["types"][0]["app"]["id"], "editor.desktop");
    assert!(apps(&sandbox, &["unset-mime", "text/x-new"]).status.success());
    let list: serde_json::Value = serde_json::from_slice(&apps(&sandbox, &["list"]).stdout).unwrap();
    assert_eq!(list["types"], serde_json::json!([]));
    assert!(!apps(&sandbox, &["set-mime", "nope.desktop", "a/b"]).status.success());
}

#[test]
fn mail_links_open_in_the_chosen_web_mail() {
    let sandbox = apps_sandbox("apps-mail");
    assert!(apps(&sandbox, &["set", "mail", "web.desktop"]).status.success());
    assert!(apps(&sandbox, &["set-webmail", "proton"]).status.success());
    assert!(apps(&sandbox, &["mailto", "mailto:a@b.c"]).status.success());
    assert!(wait_for_log(&sandbox, "proton").contains("https://mail.proton.me/inbox/#mailto=mailto%3Aa%40b.c"), "{}", sandbox.log());
    assert!(!apps(&sandbox, &["set-webmail", "nope"]).status.success());
}

// ---- pictures ----

fn png_bytes(picture: &image::RgbImage) -> Vec<u8> {
    let mut bytes = std::io::Cursor::new(Vec::new());
    picture.write_to(&mut bytes, image::ImageFormat::Png).unwrap();
    bytes.into_inner()
}

fn with_stdin(mut command: Command, input: &[u8]) -> Output {
    use std::io::Write as _;
    let mut child = command.stdin(Stdio::piped()).stdout(Stdio::piped()).spawn().unwrap();
    child.stdin.take().unwrap().write_all(input).unwrap();
    child.wait_with_output().unwrap()
}

#[test]
fn text_color_reads_the_picture_from_stdin() {
    let sandbox = Sandbox::new("text-color");
    let picture = image::RgbImage::from_fn(50, 10, |x, _| if x % 10 == 5 { image::Rgb([1, 2, 3]) } else { image::Rgb([250, 250, 250]) });
    let output = with_stdin(sandbox.command(&["text-color"]), &png_bytes(&picture));
    let colors: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(colors, serde_json::json!({ "background": "#fafafa", "text": "#010203" }));
    let empty: serde_json::Value = serde_json::from_slice(&with_stdin(sandbox.command(&["text-color"]), b"").stdout).unwrap();
    assert_eq!(empty["error"], "No data received via stdin");
    let garbage: serde_json::Value = serde_json::from_slice(&with_stdin(sandbox.command(&["text-color"]), b"not a picture").stdout).unwrap();
    assert_eq!(garbage["error"], "Could not decode image data");
}

#[test]
fn regions_come_out_in_either_format_and_a_bad_file_fails() {
    let sandbox = Sandbox::new("regions");
    let picture = image::RgbImage::from_fn(1200, 800, |x, y| {
        if (200..1000).contains(&x) && (150..650).contains(&y) { image::Rgb([240, 240, 240]) } else { image::Rgb([15, 25, 35]) }
    });
    let path = sandbox.root.join("shot.png");
    fs::write(&path, png_bytes(&picture)).unwrap();
    let path = path.to_str().unwrap();
    let hyprctl: serde_json::Value = serde_json::from_slice(&sandbox.run(&["find-regions", "--hyprctl", "--image", path]).stdout).unwrap();
    assert!(hyprctl.as_array().unwrap().iter().all(|region| region["at"].is_array() && region["size"].is_array()), "{hyprctl}");
    let plain: serde_json::Value = serde_json::from_slice(&sandbox.run(&["find-regions", "--image", path, "--single"]).stdout).unwrap();
    assert_eq!(plain.as_array().unwrap().len(), 1, "{plain}");
    assert!(plain[0]["width"].is_i64());
    let output = sandbox.run(&["find-regions", "--image", "/nonexistent.png"]);
    assert_eq!(output.status.code(), Some(1));
    assert!(String::from_utf8_lossy(&output.stderr).contains("Could not load image"));
}

#[test]
fn thumbnails_land_where_the_shell_looks_and_are_redone_when_the_file_changes() {
    let sandbox = Sandbox::new("thumbnails");
    sandbox.tool("ffmpeg", "", 1);
    sandbox.tool("magick", "", 1);
    let folder = sandbox.root.join("my walls");
    fs::create_dir_all(&folder).unwrap();
    let picture = folder.join("a b.png");
    fs::write(&picture, png_bytes(&image::RgbImage::from_pixel(1000, 500, image::Rgb([200, 10, 10])))).unwrap();
    fs::write(folder.join("notes.txt"), "not a picture").unwrap();
    let canonical = fs::canonicalize(&picture).unwrap();
    let output = sandbox.run(&["thumbnails", "--size", "large", "--directory", folder.to_str().unwrap()]);
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    let stdout = text(&output);
    assert!(stdout.contains(&format!("FILE {}", canonical.display())), "{stdout}");
    assert!(stdout.contains("PROGRESS 2/2"), "{stdout}");

    let cache = sandbox.root.join("cache/thumbnails/large");
    let made: Vec<PathBuf> = fs::read_dir(&cache).unwrap().map(|entry| entry.unwrap().path()).collect();
    assert_eq!(made.len(), 1, "only the picture: {made:?}");
    let thumbnail = image::open(&made[0]).unwrap();
    assert_eq!((thumbnail.width(), thumbnail.height()), (256, 128));
    let bytes = fs::read(&made[0]).unwrap();
    let uri = format!("file://{}", canonical.display()).replace(' ', "%20");
    assert!(bytes.windows(uri.len()).any(|window| window == uri.as_bytes()), "the thumbnail names its source");
    use std::os::unix::fs::MetadataExt as _;
    assert_eq!(fs::metadata(&made[0]).unwrap().mode() & 0o777, 0o600);

    // Fresh: not touched. Changed: redone.
    let fresh = fs::metadata(&made[0]).unwrap().modified().unwrap();
    sandbox.run(&["thumbnails", "--size", "large", "--directory", folder.to_str().unwrap()]);
    assert_eq!(fs::metadata(&made[0]).unwrap().modified().unwrap(), fresh);
    fs::File::options().write(true).open(&picture).unwrap().set_modified(std::time::SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1000)).unwrap();
    sandbox.run(&["thumbnails", "--size", "large", "--directory", folder.to_str().unwrap()]);
    assert_ne!(fs::metadata(&made[0]).unwrap().modified().unwrap(), fresh);
}

#[test]
fn what_cant_be_decoded_goes_to_other_tools_and_a_failure_leaves_nothing() {
    let sandbox = Sandbox::new("thumbnails-tools");
    sandbox.tool("ffmpeg", "", 1);
    sandbox.tool("magick", "", 1);
    let folder = sandbox.root.join("walls");
    fs::create_dir_all(&folder).unwrap();
    fs::write(folder.join("clip.mp4"), "x").unwrap();
    fs::write(folder.join("pic.avif"), "x").unwrap();
    fs::write(folder.join("broken.png"), "not a png").unwrap();
    let output = sandbox.run(&["thumbnails", "--size", "normal", "--directory", folder.to_str().unwrap()]);
    assert!(output.status.success());
    assert!(text(&output).contains("PROGRESS 3/3"), "{}", text(&output));
    let log = sandbox.log();
    assert!(log.contains("[-ss] [1]") && log.contains("pic.avif") && log.contains("broken.png"), "{log}");
    let left = fs::read_dir(sandbox.root.join("cache/thumbnails/normal")).unwrap().count();
    assert_eq!(left, 0);
    assert!(!sandbox.run(&["thumbnails", "--size", "giant", "--directory", folder.to_str().unwrap()]).status.success());
}

#[test]
fn hyprland_overrides_change_only_the_keys_asked_for() {
    let sandbox = Sandbox::new("hypr-config");
    let file = sandbox.root.join("deep/main.lua");
    fs::create_dir_all(file.parent().unwrap()).unwrap();
    fs::write(&file, "-- mine\nhl.config({a={b=1}})\nhl.config({c=2})\nhl.config({ab=3})").unwrap();
    let path = file.to_str().unwrap();
    let output = sandbox.run(&["hypr-config", "--file", path, "--set", "a:b", "some text", "--set", "new:key", "1.5", "--reset", "c"]);
    assert!(output.status.success());
    assert_eq!(fs::read_to_string(&file).unwrap(), "-- mine\nhl.config({a={b=\"some text\"}})\nhl.config({ab=3})\nhl.config({new={key=1.5}})\n");
    assert!(text(&output).contains("Removed 'c'"));
    sandbox.run(&["hypr-config", "--file", path, "--set", "ab", "[[EMPTY]]"]);
    assert!(!fs::read_to_string(&file).unwrap().contains("ab="));
    assert_eq!(fs::read_dir(file.parent().unwrap()).unwrap().count(), 1, "no temporary file stays behind");
    assert!(text(&sandbox.run(&["hypr-config", "--file", path])).contains("Must specify"));
}

// ---- screen recorder status ----

fn recorder_status(sandbox: &Sandbox) -> serde_json::Value {
    let output = sandbox.command(&["recorder-status"]).env("VELORA_RECORDER_RUNTIME", sandbox.root.join("run")).output().unwrap();
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
    serde_json::from_slice(&output.stdout).unwrap()
}

fn start_time(pid: u32) -> String {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).unwrap();
    stat.rsplit_once(')').unwrap().1.split_whitespace().nth(19).unwrap().to_string()
}

#[test]
fn a_recorder_that_never_ran_is_idle() {
    let sandbox = Sandbox::new("recorder-idle");
    assert_eq!(recorder_status(&sandbox), serde_json::json!({ "state": "idle" }));
}

#[test]
fn a_dead_recorder_is_idle_but_keeps_its_error_and_file() {
    let sandbox = Sandbox::new("recorder-dead");
    fs::create_dir_all(sandbox.root.join("run")).unwrap();
    fs::write(sandbox.root.join("run/state.json"), r#"{"state":"recording","pid":999999999,"identity":"1","file":"/v/a.mp4"}"#).unwrap();
    let status = recorder_status(&sandbox);
    assert_eq!(status["state"], "idle");
    assert_eq!(status["file"], "/v/a.mp4");
    fs::write(sandbox.root.join("run/state.json"), r#"{"state":"error","pid":999999999,"identity":"1","error":"it broke"}"#).unwrap();
    let status = recorder_status(&sandbox);
    assert_eq!(status["state"], "error");
    assert_eq!(status["error"], "it broke");
}

#[test]
fn a_child_outliving_its_recorder_is_reported_as_orphaned() {
    let sandbox = Sandbox::new("recorder-orphan");
    fs::create_dir_all(sandbox.root.join("run")).unwrap();
    let mut child = Command::new("/bin/sleep").arg("30").spawn().unwrap();
    let identity = start_time(child.id());
    let state = |kind: &str, error: &str| format!(r#"{{"state":"x","pid":999999999,"identity":"1","childPid":{},"childIdentity":"{identity}","childKind":"{kind}","error":"{error}"}}"#, child.id());
    fs::write(sandbox.root.join("run/state.json"), state("recorder", "")).unwrap();
    let status = recorder_status(&sandbox);
    assert_eq!((status["state"].as_str(), status["orphaned"].as_bool()), (Some("recording"), Some(true)));
    fs::write(sandbox.root.join("run/state.json"), state("selector", "")).unwrap();
    assert_eq!(recorder_status(&sandbox)["state"], "selecting");
    fs::write(sandbox.root.join("run/state.json"), state("recorder", "bad")).unwrap();
    assert_eq!(recorder_status(&sandbox)["state"], "stopping");
    child.kill().unwrap();
    child.wait().unwrap();
    assert_eq!(recorder_status(&sandbox)["state"], "idle");
    fs::write(sandbox.root.join("run/state.json"), r#"{"state":"x","mixerSink":"s"}"#).unwrap();
    let status = recorder_status(&sandbox);
    assert_eq!((status["state"].as_str(), status["orphaned"].as_bool()), (Some("stopping"), Some(true)));
}

#[test]
fn a_held_lock_means_someone_owns_the_recording() {
    let sandbox = Sandbox::new("recorder-lock");
    fs::create_dir_all(sandbox.root.join("run")).unwrap();
    let lock = sandbox.root.join("run/owner.lock");
    // A process that really holds the lock, as the recorder does
    let mut holder = Command::new("/bin/sh").args(["-c", &format!("exec 9<>'{}'; flock 9; echo held; exec sleep 30", lock.display())])
        .stdout(Stdio::piped()).spawn().unwrap();
    let mut held = [0u8; 5];
    std::io::Read::read_exact(holder.stdout.as_mut().unwrap(), &mut held).unwrap();
    let identity = start_time(holder.id());
    fs::write(&lock, format!(r#"{{"pid":{},"identity":"{identity}"}}"#, holder.id())).unwrap();
    // Not published yet
    assert_eq!(recorder_status(&sandbox), serde_json::json!({ "state": "starting" }));
    fs::write(sandbox.root.join("run/state.json"), format!(r#"{{"state":"recording","pid":{},"identity":"{identity}","startedAt":5}}"#, holder.id())).unwrap();
    let status = recorder_status(&sandbox);
    assert_eq!((status["state"].as_str(), status["startedAt"].as_i64()), (Some("recording"), Some(5)));
    holder.kill().unwrap();
    holder.wait().unwrap();
    assert_eq!(recorder_status(&sandbox)["state"], "idle");
}

// ---- toolbox questions ----

#[test]
fn the_toolbox_learns_which_tools_exist() {
    let sandbox = Sandbox::new("toolbox-caps");
    sandbox.tool("magick", "", 0);
    let output = sandbox.command(&["toolbox-caps"]).env("PATH", sandbox.root.join("bin")).output().unwrap();
    let caps: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(caps["magick"], sandbox.root.join("bin/magick").to_str().unwrap());
    assert_eq!(caps["ffmpeg"], serde_json::Value::Null);
    assert_eq!(caps.as_object().unwrap().len(), 24);
}

#[test]
fn the_toolbox_learns_what_files_are() {
    let sandbox = Sandbox::new("toolbox-detect");
    sandbox.tool("ffprobe", "12.5", 0);
    let folder = sandbox.root.join("files");
    fs::create_dir_all(folder.join("sub")).unwrap();
    let file = |name: &str, mime: &str| {
        let path = folder.join(name);
        fs::write(&path, "12345").unwrap();
        (path.to_str().unwrap().to_string(), mime.to_string())
    };
    let cases = [file("a.mp4", "video/mp4"), file("b.tar.gz", "application/gzip"), file("c.PDF", "application/octet-stream"), file("d.txt", "text/plain"), file("e.bin", "application/octet-stream")];
    // `file` answers from a list of name and type
    let answers: String = cases.iter().map(|(path, mime)| format!("[ \"$4\" = '{path}' ] && echo {mime}\n")).collect();
    fs::write(sandbox.root.join("bin/file"), format!("#!/bin/sh\n{answers}\nexit 0\n")).unwrap();
    fs::set_permissions(sandbox.root.join("bin/file"), fs::Permissions::from_mode(0o755)).unwrap();
    let mut arguments = vec!["toolbox-detect"];
    arguments.extend(cases.iter().map(|(path, _)| path.as_str()));
    let directory = format!("{}/", folder.join("sub").display());
    arguments.push(&directory);
    let detected: serde_json::Value = serde_json::from_slice(&sandbox.run(&arguments).stdout).unwrap();
    let kinds: Vec<&str> = detected.as_array().unwrap().iter().map(|entry| entry["kind"].as_str().unwrap()).collect();
    assert_eq!(kinds, ["video", "archive", "pdf", "document", "other", "folder"]);
    assert_eq!(detected[0]["duration"], 12.5);
    assert_eq!(detected[0]["size"], 5);
    assert_eq!(detected[1]["ext"], "tar.gz");
    assert_eq!(detected[2]["ext"], "pdf");
    assert_eq!(detected[5]["name"], "sub");
    assert_eq!(detected[5]["mime"], "inode/directory");
    assert!(detected[3].get("duration").is_none());
}
