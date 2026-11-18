-- How windows behave, from Settings → Desktop → Windows ("shell:windowMode" in custom/shell_settings.json):
--   "tiling"   windows share the screen without overlapping (default)
--   "floating" free windows that stay where you put them, as on Windows and macOS (modes/floating.lua)
--   "canvas"   one shared plane, with an independent camera on each workspace and monitor
-- Read here rather than from the generated Lua because keybinds.lua needs it before that file loads.
local M = {}

function M.current()
    local config = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
    local file = io.open(config .. "/hypr/custom/shell_settings.json", "r")
    if not file then
        return "tiling"
    end
    local text = file:read("a") or ""
    file:close()
    local mode = text:match('"shell:windowMode"%s*:%s*"([^"]+)"')
    return (mode == "floating" or mode == "canvas") and mode or "tiling"
end

-- Called once per config load, before the default rules
function M.load()
    local mode = M.current()
    require("hyprland.window_actions").setup()
    hl.on("config.reloaded", function()
        local state = os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")
        local marker = io.open(state .. "/velora/gtk-window-controls.json")
        if marker then marker:close() elseif mode == "tiling" then return end
        local config = os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")
        local helper = config .. "/quickshell/ii/scripts/helper"
        hl.dispatch(hl.dsp.exec_cmd("'" .. helper:gsub("'", "'\\''") .. "' gtk-window-controls " .. mode))
    end)
    if mode ~= "tiling" then
        local data = os.getenv("XDG_DATA_HOME") or (os.getenv("HOME") .. "/.local/share")
        local plugin = data .. "/velora/hypr/libvelora-windows.so"
        local file = io.open(plugin, "rb")
        if file then
            file:close()
            hl.plugin.load(plugin)
        end
        hl.on("config.reloaded", function()
            local native = hl.plugin.velora
            if native and native.mode then native.mode(mode)
            elseif mode == "canvas" then
                local locale = os.getenv("LC_ALL") or os.getenv("LC_MESSAGES") or os.getenv("LANG") or ""
                local message = locale:match("^ru") and "Включены свободные окна. Для холста нужна сборка плагина под установленный Hyprland."
                    or "Using Free Windows. Rebuild the Velora plugin for the installed Hyprland version."
                hl.dispatch(hl.dsp.exec_cmd("notify-send -a Velora 'Velora Canvas' '" .. message .. "'"))
            end
        end)
        require("hyprland.modes.floating")
        return mode
    end
    if hl.plugin and hl.plugin.velora and hl.plugin.velora.mode then hl.plugin.velora.mode("tiling") end
    -- Back from free windows: the ones that mode floated join the layout again
    hl.on("config.reloaded", function()
        for _, window in ipairs(hl.get_windows()) do
            local tagged = false
            for _, tag in ipairs(window.tags or {}) do
                tagged = tagged or tag == "velora-free" or tag == "velora-free*"
            end
            if tagged and window.floating and window.workspace and not window.workspace.special then
                local target = "address:" .. window.address
                hl.dispatch(hl.dsp.window.float({ action = "unset", window = target }))
                pcall(function() hl.dispatch(hl.dsp.window.tag({ tag = "-velora-free", window = target })) end)
            end
        end
    end)
    return mode
end

return M
