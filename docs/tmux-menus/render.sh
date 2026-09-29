#!/usr/bin/env bash
#
# Render the tmux-menus styling screenshots in docs/tmux-menus/images/.
#
# tmux menus are client overlays, so `capture-pane` cannot see them; instead
# each variant boots a hermetic tmux server (temp HOME, our .tmux.conf +
# .tmux.conf.local + a styling snippet, a private tmux-menus copy), and
# charmbracelet/vhs attaches a headless terminal, presses the keys and takes
# a PNG screenshot.
#
# Requirements: tmux, vhs (brew install vhs), a tmux-menus checkout:
#   git clone --depth 1 --branch v2.4.1 https://github.com/jaclu/tmux-menus /tmp/tmux-menus
#   TMUX_MENUS_SRC=/tmp/tmux-menus docs/tmux-menus/render.sh [variant ...]
#
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT_DIR="$REPO_ROOT/docs/tmux-menus/images"
MENUS_SRC=${TMUX_MENUS_SRC:-$HOME/.tmux/plugins/tmux-menus}
# Real binary, not an asdf/pyenv shim (shims break once HOME is overridden;
# same reasoning as _resolve_tmux_bin in tests/conftest.py).
TMUX_BIN=$(asdf which tmux 2>/dev/null || command -v tmux)

[ -f "$MENUS_SRC/scripts/plugin_init.sh" ] || {
    echo "tmux-menus checkout not found at $MENUS_SRC (set TMUX_MENUS_SRC)" >&2
    exit 1
}
command -v vhs >/dev/null || { echo "vhs not found (brew install vhs)" >&2; exit 1; }
mkdir -p "$OUT_DIR"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tmux-menus-shots.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Scripts spawned later by the server (oh-my-tmux's _apply_configuration, the
# tmux-menus trigger) call plain `tmux` from PATH; make that the real binary.
mkdir -p "$WORK/bin"
ln -s "$TMUX_BIN" "$WORK/bin/tmux"
export PATH="$WORK/bin:$PATH"
# Never inherit the caller's tmux context -- clear every TMUX* variable.
# TMUX_SOCKET would make oh-my-tmux apply its configuration to the caller's
# server, and TMUX_PLUGIN_MANAGER_PATH would make plugin install/uninstall act
# on the caller's real ~/.tmux/plugins.
for v in $(env | sed -n 's/^\(TMUX[A-Za-z_]*\)=.*/\1/p'); do unset "$v"; done

# variant name | vhs key steps after attaching | styling appended to .tmux.conf.local
#
# Key steps use vhs syntax, one command per ';'.  <prefix> is C-b.
OPEN='Ctrl+B;Sleep 300ms;Type `\`;Sleep 1500ms'

variant_keys() {
    case $1 in
        01-main-default)        echo "$OPEN" ;;
        02-panes-default)       echo "$OPEN"';Type `P`;Sleep 1500ms' ;;
        03-panes-commands)      echo "$OPEN"';Type `P`;Sleep 1500ms;Type `!`;Sleep 2s' ;;
        04-panes-keybinds)      echo "$OPEN"';Type `P`;Sleep 1500ms;Type `!`;Sleep 2s;Type `!`;Sleep 2s' ;;
        05-nav-colors)          echo "$OPEN" ;;
        06-tmux-menu-style)     echo "$OPEN"';Down;Sleep 300ms' ;;
        07-plugin-styles)       echo "$OPEN"';Down;Sleep 300ms' ;;
        08-danger-zone)         echo "$OPEN"';Type `P`;Sleep 1500ms' ;;
        *) echo "unknown variant $1" >&2; return 1 ;;
    esac
}

# vhs "Width Height FontSize".  The ! views list commands and bindings and
# need far more room than a normal menu (tmux-menus reports "Screen might be
# too small" otherwise), so they get a bigger terminal.
variant_size() {
    case $1 in
        03-panes-commands|04-panes-keybinds) echo "1700 1150 15" ;;
        *) echo "1100 680 16" ;;
    esac
}

variant_style() {
    case $1 in
        05-nav-colors) cat <<'EOF'
set -g @menus_nav_next "#[fg=colour220]-->"
set -g @menus_nav_prev "#[fg=colour71]<--"
set -g @menus_nav_home "#[fg=colour84]<=="
EOF
        ;;
        06-tmux-menu-style) cat <<'EOF'
set -g menu-style "fg=colour252,bg=colour236"
set -g menu-selected-style "fg=colour16,bg=colour39"
set -g menu-border-style "fg=colour39"
set -g menu-border-lines rounded
EOF
        ;;
        07-plugin-styles) cat <<'EOF'
set -g @menus_format_title "'#[align=centre] #[fg=colour220,bold]#{@menu_name} '"
set -g @menus_simple_style "fg=colour254,bg=colour17"
set -g @menus_simple_style_selected "fg=colour16,bg=colour220"
set -g @menus_simple_style_border "fg=colour220"
set -g @menus_border_type "double"
EOF
        ;;
        08-danger-zone) cat <<'EOF'
set -g @menus_danger_zone "#[fg=colour196,bold]"
EOF
        ;;
    esac
}

ALL=(01-main-default 02-panes-default 03-panes-commands 04-panes-keybinds
     05-nav-colors 06-tmux-menu-style 07-plugin-styles 08-danger-zone)
[ $# -gt 0 ] && ALL=("$@")

for name in "${ALL[@]}"; do
    keys=$(variant_keys "$name")
    home="$WORK/$name"
    sock="shots-$name"
    mkdir -p "$home/.tmux/plugins/tpm"
    ln -s "$REPO_ROOT/.tmux.conf" "$home/.tmux.conf"
    cp "$REPO_ROOT/.tmux.conf.local" "$home/.tmux.conf.local"
    variant_style "$name" >>"$home/.tmux.conf.local"
    printf '#!/bin/sh\nexit 0\n' >"$home/.tmux/plugins/tpm/tpm"    # no network
    chmod +x "$home/.tmux/plugins/tpm/tpm"
    rsync -a --exclude cache --exclude .git "$MENUS_SRC/" "$home/.tmux/plugins/tmux-menus/"

    "$TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true   # stale from a failed run

    # Boot detached, apply the local config synchronously, run plugin init
    # synchronously (same approach as tests/test_menus_plugin.py).
    HOME="$home" \
        "$TMUX_BIN" -L "$sock" -f "$home/.tmux.conf" new-session -d -s demo -x 110 -y 32 "PS1='$ ' bash --noprofile --norc"
    HOME="$home" "$TMUX_BIN" -L "$sock" source-file "$home/.tmux.conf.local"
    HOME="$home" "$TMUX_BIN" -L "$sock" run-shell \
        "TMUX_BIN='$TMUX_BIN' '$home/.tmux/plugins/tmux-menus/scripts/plugin_init.sh'"
    # oh-my-tmux applies its theme asynchronously (run -b _apply_configuration);
    # wait until the status line is no longer tmux's default, then settle.
    for _ in $(seq 1 60); do
        sl=$("$TMUX_BIN" -L "$sock" show -gv status-left 2>/dev/null || true)
        [ -n "$sl" ] && [ "$sl" != '[#{session_name}] ' ] && break
        sleep 0.5
    done
    sleep 2
    HOME="$home" "$TMUX_BIN" -L "$sock" send-keys -t demo:1 \
        "clear; echo '# tmux-menus styling demo: $name'" Enter || true
    sleep 1

    tape="$WORK/$name.tape"
    {
        echo 'Set Shell "bash"'
        read -r w h fs <<<"$(variant_size "$name")"
        echo "Set FontSize $fs"
        echo "Set Width $w"
        echo "Set Height $h"
        echo 'Set Padding 12'
        echo 'Set TypingSpeed 40ms'
        echo 'Hide'
        echo "Type \"env -u TMUX '$TMUX_BIN' -L $sock attach -t demo\""
        echo 'Enter'
        echo 'Sleep 2s'
        echo 'Show'
        printf '%s\n' "$keys" | tr ';' '\n'
        echo "Screenshot \"$OUT_DIR/$name.png\""
        echo 'Sleep 200ms'
    } >"$tape"

    echo ">> rendering $name"
    vhs -q "$tape" >/dev/null || vhs "$tape"
    "$TMUX_BIN" -L "$sock" kill-server 2>/dev/null || true
done

echo "screenshots written to $OUT_DIR"
