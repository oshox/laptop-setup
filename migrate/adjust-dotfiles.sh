#!/usr/bin/bash
# Run once, after migrate/home-include.txt has been rsync'd into ~ on the
# new laptop. Applies the handful of dotfile edits needed for the new
# hardware / package set. See plan §D2 for the rationale for each edit.
set -euo pipefail

cd "$HOME"

sway_config=.config/sway/config
mime_apps=.config/mimeapps.list

if [[ ! -f "$sway_config" ]]; then
    echo "error: $sway_config not found — run this from \$HOME after the rsync migration" >&2
    exit 1
fi

cp "$sway_config" "$sway_config.orig"

# New 16" panel: native 2560x1600, scale 1.25 (your choice) -> 2048x1280
# logical pixels.
sed -i \
    -e 's/^output eDP-1 resolution 1920x1080 position 1920,0$/output eDP-1 resolution 2560x1600 scale 1.25 position 1920,0/' \
    "$sway_config"

# Shift the right-hand external monitor so it doesn't overlap the laptop
# panel's new (wider) logical width: 1920 (left monitor) + 2048 (eDP-1 at
# scale 1.25) = 3968.
sed -i \
    -e 's/^output DP-5 resolution 1920x1080 position 3840,0$/output DP-5 resolution 1920x1080 position 3968,0/' \
    "$sway_config"

# Zed removed: drop its border rule.
sed -i '/^for_window \[app_id="dev.zed.Zed"\] border pixel 0$/d' "$sway_config"

# Pre-existing paste typo on the source laptop
# ("...workspace number 3fedora sway atomic") that breaks $mod+Shift+3.
# Comment out / remove this block if you'd rather keep the file byte-for-byte
# identical to the source laptop.
sed -i \
    -e 's/move container to workspace number 3fedora sway atomic$/move container to workspace number 3/' \
    "$sway_config"

if ! diff -q "$sway_config.orig" "$sway_config" >/dev/null; then
    echo "updated $sway_config (backup at $sway_config.orig)"
else
    echo "warning: no changes applied to $sway_config — check its output/for_window lines match what this script expects" >&2
fi

if [[ -f "$mime_apps" ]]; then
    cp "$mime_apps" "$mime_apps.orig"
    sed -i \
        -e '/^application\/octet-stream=dev\.zed\.Zed\.desktop$/d' \
        -e 's/dev\.zed\.Zed\.desktop;//' \
        "$mime_apps"
    if ! diff -q "$mime_apps.orig" "$mime_apps" >/dev/null; then
        echo "updated $mime_apps (backup at $mime_apps.orig)"
    fi
fi

cat <<'EOF'

Done. Reminders:
  - Output names (HDMI-A-1/DP-8/DP-5) may differ on the new machine/dock.
    Run `swaymsg -t get_outputs` the first time you dock and adjust
    .config/sway/config if needed.
  - `sway reload` (mod+Shift+c) to apply without logging out.
EOF
