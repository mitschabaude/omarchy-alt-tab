#!/bin/bash
# Play an Alt+Tab in the hidden test desktop (hidden-desktop.sh) and report
# what it focused. Midway through the hold, a screenshot of the focused monitor
# can be saved, to look at the panel.
#
# Hyprland does not run its key bindings for simulated keys, so this sends
# what the bindings in bindings.lua send: the next or prev
# shortcut for each Tab, and commit for letting go of Alt. Keys the switcher
# reads itself (Escape, arrows, the Alt release it also watches) are typed
# with wtype, which does reach it.
#
#   alt-tab.sh [taps] [options]
#     taps        Tab presses while Alt is held (default 1)
#     --back      Shift+Tab instead of Tab
#     --hold MS   how long Alt stays held after the last Tab (default 600)
#     --escape    press Escape before letting go
#     --keys K..  type these keys (wtype -k names) after the Tabs
#     --alt-key   let go of Alt as a key the switcher sees, not via Hyprland
#     --to TITLE  Tab until the window titled TITLE is selected
#     --shot FILE save a screenshot midway through the hold
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
desktop="$here/hidden-desktop.sh"

taps=1 shortcut=next hold=600 escape=0 alt_key=0 shot="" to="" keys=()
while (($#)); do
  case $1 in
    --back) shortcut=prev ;;
    --hold) hold=$2; shift ;;
    --escape) escape=1 ;;
    --alt-key) alt_key=1 ;;
    --keys) shift; while (($#)) && [[ $1 != --* ]]; do keys+=("$1"); shift; done; continue ;;
    --shot) shot=$2; shift ;;
    --to) to=$2; shift ;;
    *) taps=$1 ;;
  esac
  shift
done

global() {
  "$desktop" run hyprctl dispatch "hl.dsp.global(\"alt-tab:$1\")" >/dev/null
}

seconds() {
  awk -v ms="$1" 'BEGIN { print ms / 1000 }'
}

if [[ -n $to ]]; then
  for _ in $(seq 30); do
    global "$shortcut"
    sleep 0.12
    [[ $("$desktop" query selected) == "$to" ]] && break
  done
else
  for ((i = 0; i < taps; i++)); do
    global "$shortcut"
    sleep 0.12
  done
fi
for key in "${keys[@]}"; do
  "$desktop" run wtype -k "$key"
  sleep 0.12
done

if [[ -n $shot ]]; then
  sleep "$(seconds $((hold / 2)))"
  # The monitor the panel opened on.
  monitor=$("$desktop" run hyprctl layers -j | jq -r 'to_entries[] | select([.value.levels[][] | .namespace] | index("alt-tab")) | .key')
  "$desktop" run grim -o "$monitor" "$shot"
  sleep "$(seconds $((hold / 2)))"
else
  sleep "$(seconds "$hold")"
fi

if ((escape)); then
  "$desktop" run wtype -k Escape
  sleep 0.1
fi
if ((alt_key)); then
  "$desktop" run wtype -P Alt_L -p Alt_L
else
  global commit
fi
sleep 0.4

echo "focused: $("$desktop" run hyprctl activewindow -j | jq -r '.title // "(none)"')"
"$desktop" run hyprctl monitors -j | jq -r '.[] | "\(.name): workspace \(.activeWorkspace.id)"'
