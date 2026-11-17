local colors = require("colors")

-- Floating island bar: fully transparent background.
-- topmost="on" ensures Sketchybar is pinned above all application windows,
-- desktop layers, dialogs, and never drops behind when spaces change, after sleep,
-- or upon unlocking/logging back in.
-- show_in_fullscreen=true ensures it is never auto-hidden by macOS full-screen spaces.
sbar.bar({
  topmost             = "on",
  show_in_fullscreen  = true,
  hidden              = false,
  drawing             = true,
  height              = 40,
  margin              = 8,
  y_offset            = 4,
  corner_radius       = 0,
  color               = colors.transparent,
  border_color        = colors.transparent,
  border_width        = 0,
  padding_right       = 4,
  padding_left        = 4,
  sticky              = true,
  shadow              = false,
})

-- Bar health watcher:
-- Re-asserts visibility / topmost / fullscreen when properties drift AND detects
-- SketchyBar v2.24.0's display-off/on bug where _bar_manager_begin sees 0 active
-- displays and leaves bars_count == 0 (empty bounding_rects) even while
-- topmost=="on", hidden=="off", drawing=="on".
local bar_watcher = sbar.add("item", "bar.watcher", {
  drawing     = false,
  updates     = true,
  update_freq = 5,
})

local wake_gen = 0

local function has_live_bar_windows()
  local displays = sbar.query("displays")
  if type(displays) ~= "table" or #displays == 0 then
    return true -- Display is offline; wait until macOS reports an active display
  end
  local probe = sbar.query("apple")
  return type(probe) == "table"
    and type(probe.bounding_rects) == "table"
    and next(probe.bounding_rects) ~= nil
end

local function sync_bar_state(allow_reset)
  local state = sbar.query("bar")
  if type(state) ~= "table" then return end

  if allow_reset and state.drawing == "on" and not has_live_bar_windows() then
    -- Toggling topmost forces _bar_manager_reset -> _bar_manager_begin to rebuild windows.
    sbar.bar({ topmost = "window" })
    sbar.bar({
      topmost            = "on",
      hidden             = false,
      drawing            = true,
      show_in_fullscreen = true,
    })
    return
  end

  local patch = {}
  if state.hidden ~= "off" then
    patch.hidden = false
  end
  if state.drawing ~= "on" then
    patch.drawing = true
  end
  if state.show_in_fullscreen ~= "on" then
    patch.show_in_fullscreen = true
  end
  -- Setting topmost calls _bar_manager_reset (destroying and recreating bar windows),
  -- so only apply it if it genuinely drifted and after wake transitions settle.
  if allow_reset and state.topmost ~= "on" then
    patch.topmost = "on"
  end

  if next(patch) ~= nil then
    sbar.bar(patch)
  end
end

bar_watcher:subscribe({ "system_woke", "display_change" }, function()
  sync_bar_state(false)
  wake_gen = wake_gen + 1
  local gen = wake_gen
  sbar.delay(0.6, function()
    if gen ~= wake_gen then return end
    sync_bar_state(true)
  end)
  sbar.delay(2.0, function()
    if gen ~= wake_gen then return end
    sync_bar_state(true)
  end)
end)

bar_watcher:subscribe({ "routine", "forced" }, function()
  sync_bar_state(true)
end)
