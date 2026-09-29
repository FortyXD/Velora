local M = {}
local variables = require("custom.variables")

function M.expand(value)
    for name, replacement in pairs(variables) do
        if type(replacement) == "string" then
            value = value:gsub("%$" .. name, function()
                return replacement
            end)
        end
    end

    return value
end

function M.keys(modifiers, key)
    local normalized = modifiers:upper():gsub("%s*%+%s*", " + ")
    normalized = normalized:match("^%s*(.-)%s*$")

    if normalized == "" then
        return key
    end

    return normalized .. " + " .. key
end

function M.bind(modifiers, key, dispatcher, options)
    return hl.bind(M.keys(modifiers, key), dispatcher, options)
end

function M.unbind(modifiers, key)
    return hl.unbind(M.keys(modifiers, key))
end

function M.exec(command)
    return hl.dsp.exec_cmd(M.expand(command))
end

return M
