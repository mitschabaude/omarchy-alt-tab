.pragma library

// The switcher's ordering and selection, kept free of QML so they can be read
// and checked on their own.

// The recently focused list with address moved to the front.
function noteFocus(recent, address) {
  if (!address) return recent
  return [address].concat(recent.filter(function(other) { return other !== address }))
}

// Windows in most-recently-used order. A window the switcher saw focused
// sorts by when; one it never saw (focused before the shell started) sorts
// after those, by Hyprland's own focus history, and one with neither last.
function order(windows, recent) {
  function rank(window) {
    var seen = recent.indexOf(window.address)
    if (seen >= 0) return seen
    if (window.focusHistoryID >= 0) return 100000 + window.focusHistoryID
    return 1000000
  }
  return windows.slice().sort(function(a, b) { return rank(a) - rank(b) })
}

// Where the selection starts. Moving forward skips the window already in
// front, so a single Alt+Tab goes back to the previous window; with nothing
// focused, it starts on the most recent one. Moving backward starts at the
// least recent window.
function firstIndex(count, frontIsFocused, direction) {
  if (count <= 1) return 0
  if (direction < 0) return count - 1
  return frontIsFocused ? 1 : 0
}

// The selection moved one step, wrapping at both ends.
function step(index, count, direction) {
  if (count <= 0) return 0
  return ((index + direction) % count + count) % count
}

// Thumbnail scale that fits count cards of cardWidth x cardHeight, wrapped
// into rows, inside maxWidth x maxHeight. Never above 1.
function fitScale(count, cardWidth, cardHeight, maxWidth, maxHeight) {
  for (var scale = 1; scale > 0.2; scale -= 0.05) {
    var width = cardWidth * scale
    var height = cardHeight * scale
    var perRow = Math.max(1, Math.floor(maxWidth / width))
    var rows = Math.ceil(count / perRow)
    if (rows * height <= maxHeight) return scale
  }
  return 0.2
}
