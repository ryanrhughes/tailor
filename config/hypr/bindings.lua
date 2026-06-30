-- Personal Hyprland application bindings.
--
-- Omarchy's Lua Hyprland config loads default WM/menu/media bindings from
-- default.hypr.omarchy, then loads this user file as `hypr.bindings`. The
-- application/webapp launcher set lives in Omarchy's config template, so load it
-- first and layer Tailor's personal overrides below.

local omarchy_path = os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
dofile(omarchy_path .. "/config/hypr/bindings.lua")

-- Override default Super+Shift+A (ChatGPT) to launch the user's WebUI.
hl.unbind("SUPER + SHIFT + A")
o.bind("SUPER + SHIFT + A", "WebUI", 'omarchy-launch-webapp "$webui_url"')

-- Override default Super+Shift+S (Google Maps) with Launchpad (37signals).
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Launchpad (37signals)", { webapp = "https://launchpad.37signals.com/" })

-- Gaming mode toggle — start/stop kanata homerow-mods service.
o.bind("SUPER + F12", "Gaming mode toggle", "~/.local/bin/kanata-gaming-toggle")

-- Voxtype dictation (push-to-talk on F5).
o.bind("F5", "Start dictation", "voxtype record start")
o.bind("F5", "Stop dictation", "voxtype record stop", { release = true })
