-- How windows behave, from Settings → Desktop → Windows ("shell:windowMode" in custom/shell_settings.json):
--   "tiling"   windows share the screen without overlapping (default)
--   "floating" free windows that stay where you put them, as on Windows and macOS (modes/floating.lua)
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
    return text:match('"shell:windowMode"%s*:%s*"floating"') and "floating" or "tiling"
end

-- Called once per config load, before the default rules
function M.load()
    local mode = M.current()
    if mode == "floating" then
        require("hyprland.modes.floating")
        return mode
    end
    -- Back from free windows: the ones that mode floated join the layout again
    hl.on("config.reloaded", function()
        for _, window in ipairs(hl.get_windows()) do
            local tagged = false
            for _, tag in ipairs(window.tags or {}) do
                tagged = tagged or tag == "velora-free" or tag == "velora-free*"
            end
            if tagged and window.floating and not window.workspace.special then
                local target = "address:" .. window.address
                hl.dispatch(hl.dsp.window.float({ action = "unset", window = target }))
                pcall(function() hl.dispatch(hl.dsp.window.tag({ tag = "-velora-free", window = target })) end)
            end
        end
    end)
    return mode
end

return M
