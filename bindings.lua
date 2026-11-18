-- Key bindings for the Alt+Tab plugin. Load this file from your Hyprland
-- config (~/.config/hypr/hyprland.lua):
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/mitschabaude.alt-tab/bindings.lua")
--
-- Holding Alt keeps the switcher open; each Tab (or Shift+Tab) moves the
-- selection. Letting go of Alt focuses the selected window. The keys reach
-- the shell as Hyprland global shortcuts, with no process spawned per press.
--
-- Uses hl.* only, without Omarchy's helpers, so the plugin's hidden test
-- desktop can load this file as is.

-- Omarchy binds these to cycle_next and bring_to_top.
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
hl.bind("ALT + TAB", hl.dsp.global("alt-tab:next"), { description = "Switch windows" })
hl.bind("ALT + SHIFT + TAB", hl.dsp.global("alt-tab:prev"), { description = "Switch windows backwards" })

-- Letting go of Alt picks the selected window. The release passes through to
-- apps as usual (non-consuming), and fires whatever else was pressed with Alt
-- (ignore_mods, transparent); the switcher ignores it while closed. Only left
-- Alt is bound, so right Alt stays free for other bindings; the switcher's
-- panel sees either Alt let go by itself too.
hl.bind("Alt_L", hl.dsp.global("alt-tab:commit"), {
  release = true,
  transparent = true,
  ignore_mods = true,
  non_consuming = true,
  description = "Pick the window selected in the switcher",
})
