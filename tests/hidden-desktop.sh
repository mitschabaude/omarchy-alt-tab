#!/bin/bash
# A private Hyprland for testing the switcher without touching the desktop in
# use: it draws to two virtual monitors nobody sees, runs with its own D-Bus
# session, and loads only a minimal config plus the plugin's bindings.lua. The
# switcher plugin runs in it in a Quickshell of its own, not the Omarchy shell.
# Its host window sits on a hidden special workspace and never takes focus.
#
#   hidden-desktop.sh start   start it (TEST-A and TEST-B, 1920x1080 each)
#   hidden-desktop.sh run ... run a command inside it, e.g. foot, wtype, grim
#   hidden-desktop.sh reload  restart the switcher after editing the plugin
#   hidden-desktop.sh query Q while the switcher is open: "selected" (title)
#                             or "order" (titles, most recent first)
#   hidden-desktop.sh stop    stop it, and everything opened inside it
set -euo pipefail

plugin=$(cd "$(dirname "$0")/.." && pwd)
omarchy=${OMARCHY_PATH:-/usr/share/omarchy}
state=$XDG_RUNTIME_DIR/alt-tab-test

# Commands below talk to the test instance; the host stays on its own vars.
run() {
  # shellcheck disable=SC1091
  (source "$state/env" && "$@")
}

start_switcher() {
  # XDG_CONFIG_HOME points the plugin at the test's own shell.json.
  run hyprctl dispatch "hl.dsp.exec_cmd(\"env XDG_CONFIG_HOME=$state/config quickshell -p $state/shell/shell.qml > $state/quickshell.log 2>&1\")" >/dev/null
}

start() {
  if [[ -f $state/env ]]; then
    echo "already running (stop it first)" >&2
    exit 1
  fi
  mkdir -p "$state/shell" "$state/config/omarchy"
  # TEST-A stands in for the main monitor, set as a user would.
  echo '{ "plugins": [{ "id": "alt-tab", "monitor": "TEST-A" }] }' > "$state/config/omarchy/shell.json"

  # The plugin's qs.Commons imports resolve against this config root.
  ln -sfn "$omarchy/shell/Commons" "$state/shell/Commons"
  ln -sfn "$plugin" "$state/shell/plugin"
  # The switcher alone, plus a query hook for the tests:
  #   hidden-desktop.sh query selected|order|panel
  cat > "$state/shell/shell.qml" <<'EOF'
import Quickshell
import Quickshell.Io
import "plugin" as Plugin

ShellRoot {
  Plugin.Switcher { id: switcher }

  IpcHandler {
    target: "switcher"

    function selected(): string {
      var window = switcher.selected
      return window && window.toplevel ? String(window.toplevel.title) : ""
    }

    function panel(): string {
      return switcher.screen ? String(switcher.screen.name) : ""
    }

    function order(): string {
      return switcher.entries.map(function(window) { return String(window.toplevel.title) }).join(" ")
    }
  }
}
EOF

  cat > "$state/hyprland.lua" <<EOF
hl.config({
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
  ecosystem = { no_update_news = true, no_donation_nag = true },
})
-- Draw only on the virtual monitors, never into the host window.
hl.monitor({ output = "WAYLAND-1", disabled = true })
hl.monitor({ output = "TEST-A", mode = "1920x1080", position = "0x0", scale = 1 })
hl.monitor({ output = "TEST-B", mode = "1920x1080", position = "1920x0", scale = 1 })
dofile("$plugin/bindings.lua")
EOF

  local before
  before=$(hyprctl instances -j | jq -c '[.[].instance]')
  hyprctl dispatch "hl.dsp.exec_cmd(\"dbus-run-session -- Hyprland --config $state/hyprland.lua > $state/hyprland.log 2>&1\", { workspace = \"special:alt-tab-test silent\", no_initial_focus = true })" >/dev/null

  local instance=""
  for _ in $(seq 100); do
    instance=$(hyprctl instances -j | jq -r --argjson before "$before" \
      '[.[] | select(.instance as $i | $before | index($i) | not)][0] // empty | "\(.instance) \(.wl_socket) \(.pid)"')
    [[ -n $instance ]] && break
    sleep 0.1
  done
  if [[ -z $instance ]]; then
    echo "the test Hyprland did not start; see $state/hyprland.log" >&2
    exit 1
  fi

  local signature socket pid
  read -r signature socket pid <<< "$instance"
  cat > "$state/env" <<EOF
export HYPRLAND_INSTANCE_SIGNATURE=$signature WAYLAND_DISPLAY=$socket
TEST_PID=$pid
EOF

  for _ in $(seq 50); do
    run hyprctl monitors >/dev/null 2>&1 && break
    sleep 0.1
  done
  run hyprctl output create headless TEST-A >/dev/null
  run hyprctl output create headless TEST-B >/dev/null
  start_switcher
  echo "started: $socket (Hyprland pid $pid)"
}

reload() {
  run pkill -f "quickshell -p $state/shell/shell.qml" || true
  sleep 0.3
  start_switcher
}

stop() {
  [[ -f $state/env ]] || { echo "not running"; return; }
  # shellcheck disable=SC1091
  source "$state/env"
  # Exiting the test Hyprland closes what runs inside it, and ends its D-Bus.
  hyprctl dispatch 'hl.dsp.exit()' >/dev/null 2>&1 || true
  for _ in $(seq 50); do
    kill -0 "$TEST_PID" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$TEST_PID" 2>/dev/null; then kill "$TEST_PID"; fi
  rm -rf "$state"
  echo "stopped"
}

case ${1:-} in
  start) start ;;
  stop) stop ;;
  reload) reload ;;
  run) shift; run "$@" ;;
  query) run quickshell ipc -p "$state/shell/shell.qml" call switcher "$2" ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
