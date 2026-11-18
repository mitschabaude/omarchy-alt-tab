#!/bin/bash
# The switcher's checks, run in a hidden test desktop (hidden-desktop.sh) that
# this starts and stops: nothing on the desktop in use moves, gets focus or
# gets typed into. Screenshots of the panel land in $SHOTS (default: a temp
# directory), to look at.
#
#   run.sh            start a test desktop, run every check, stop it
#   KEEP=1 run.sh     leave the test desktop running afterwards
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
desktop="$here/hidden-desktop.sh"
shots=${SHOTS:-$(mktemp -d /tmp/switcher-shots.XDGXXXX)}
failed=0

d() { "$desktop" run "$@"; }

open_window() { # open_window <title> <workspace>
  d hyprctl dispatch "hl.dsp.exec_cmd(\"foot --title $1 -e sh -c 'echo window $1; sleep 3600'\", { workspace = \"$2\" })" >/dev/null
  for _ in $(seq 50); do
    d hyprctl clients -j | jq -e --arg t "$1" 'any(.title == $t)' >/dev/null && return
    sleep 0.1
  done
  echo "window $1 did not open" >&2
  exit 1
}

focused() { d hyprctl activewindow -j | jq -r '.title // "(none)"'; }
workspaces() { d hyprctl monitors -j | jq -r 'sort_by(.name) | map("\(.name)=\(.activeWorkspace.id)") | join(" ")'; }
workspace_of() { d hyprctl clients -j | jq -r --arg t "$1" '.[] | select(.title == $t) | .workspace.name'; }

check() { # check <what> <expected> <actual>
  if [[ $2 == "$3" ]]; then
    echo "ok    $1"
  else
    echo "FAIL  $1: expected '$2', got '$3'"
    failed=1
  fi
}

switch() { "$here/alt-tab.sh" --hold 300 "$@" >/dev/null; }

host_focused() { hyprctl activewindow -j | jq -r '.address // ""'; }
host_focus=$(host_focused)

"$desktop" start >/dev/null || exit 1
trap '[[ ${KEEP:-} ]] || "$desktop" stop >/dev/null' EXIT
sleep 1.5

# TEST-A shows workspace 3 (two), with one on hidden workspace 1; TEST-B
# shows three on workspace 2. four is minimized, five in the scratchpad.
open_window one 1
open_window two 3
open_window four "special:minimized silent"
open_window five "special:scratchpad silent"
open_window three 2
sleep 0.5
# Most recent first: three, two, one, then four and five, which never had the
# focus, in no particular order.

d hyprctl dispatch 'hl.dsp.global("alt-tab:next")' >/dev/null
sleep 0.3
order=$("$desktop" query order)
check "The switcher lists windows most recent first" "three two one" "$(cut -d' ' -f1-3 <<< "$order")"
check "  with the previous one selected" two "$("$desktop" query selected)"
check "  on the main monitor (TEST-A), though three is on TEST-B" TEST-A "$("$desktop" query panel)"
d wtype -k Escape
sleep 0.3
least_recent=${order##* }

"$here/alt-tab.sh" 1 --hold 800 --shot "$shots/panel.png" >/dev/null
check "Alt+Tab goes back to the previous window" two "$(focused)"
check "  and moves no other monitor" "TEST-A=3 TEST-B=2" "$(workspaces)"

switch 1
check "Alt+Tab again comes back" three "$(focused)"

switch 2
check "Alt+Tab+Tab goes two back, onto a hidden workspace" one "$(focused)"
check "  showing it on its own monitor only" "TEST-A=1 TEST-B=2" "$(workspaces)"

switch 1 --back
check "Shift+Alt+Tab starts from the least recent window" "$least_recent" "$(focused)"
switch --to five
check "A scratchpad window gets the focus" five "$(focused)"
check "  and comes up in the scratchpad" "special:scratchpad" "$(workspace_of five)"
switch 1
check "  after which Alt+Tab goes back" "$least_recent" "$(focused)"

switch --to four
check "A minimized window gets the focus" four "$(focused)"
check "  back on the workspace in front" 1 "$(workspace_of four)"

before=$(focused)
switch 2 --escape
check "Escape keeps the window in front" "$before" "$(focused)"

d hyprctl dispatch 'hl.dsp.global("alt-tab:next")' >/dev/null
sleep 0.3
read -r -a order <<< "$("$desktop" query order)"
d wtype -k Right
sleep 0.2
check "The Right arrow selects the next window too" "${order[2]}" "$("$desktop" query selected)"
d wtype -P Alt_L -p Alt_L
sleep 0.5
check "  and letting go of Alt, seen by the switcher itself, picks it" "${order[2]}" "$(focused)"

before=$(focused)
switch 1 --hold 0
switch 1 --hold 0
check "Two quick Alt+Tabs come back to the start" "$before" "$(focused)"

# A window's app id is up to the app. One naming a file that blocks when opened
# (here a FIFO nobody writes to) must not stall the switcher drawing its icon.
fifo=$(mktemp -u /tmp/alt-tab-fifo.XXXXXX)
mkfifo "$fifo"
trap '[[ ${KEEP:-} ]] || "$desktop" stop >/dev/null; timeout 1 sh -c "echo > $fifo"; rm -f "$fifo"' EXIT
d hyprctl dispatch "hl.dsp.exec_cmd(\"foot --app-id $fifo --title six -e sh -c 'sleep 3600'\", { workspace = \"3\" })" >/dev/null
for _ in $(seq 50); do
  d hyprctl clients -j | jq -e 'any(.title == "six")' >/dev/null && break
  sleep 0.1
done
d hyprctl dispatch 'hl.dsp.global("alt-tab:next")' >/dev/null
sleep 0.5
check "A window whose app id names a blocking file doesn't stall the switcher" yes \
  "$(timeout 3 "$desktop" query order >/dev/null && echo yes || echo no)"
d wtype -k Escape
sleep 0.3

check "The desktop in use kept its focused window" "$host_focus" "$(host_focused)"
check "  and the test desktop's window never had the focus" "" "$(hyprctl clients -j | jq -r '.[] | select(.workspace.name == "special:alt-tab-test" and .focusHistoryID == 0) | .class')"

echo "screenshot: $shots/panel.png"
exit $failed
