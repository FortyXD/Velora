-- Extra environment variables.
hl.env("SHELL", "/bin/zsh")
hl.env("TERMINAL", "kitty")

-- Avoid RT budget SIGKILL during NVIDIA HDMI hotplug (Hyprland #16648).
-- Hyprland 0.57.2 removes realtime scheduling upstream.
hl.env("HYPRLAND_NO_RT", "1")
