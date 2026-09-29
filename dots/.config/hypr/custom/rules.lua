-- Telegram should not steal focus or switch workspaces for notifications.
local telegram = { class = [=[^(TelegramDesktop|telegram-desktop|org.telegram.desktop)$]=] }

hl.window_rule({
    match = telegram,
    suppress_event = "activate",
})

hl.window_rule({
    match = telegram,
    suppress_event = "activatefocus",
})
