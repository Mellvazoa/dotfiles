local colors = require("colors")

-- Floating island bar: fully transparent background.
-- topmost="off" is intentional: the menus helper (menus -s N) needs to
-- temporarily bring the macOS menu bar to front so app menus can open.
-- If topmost="window" is set, the system bar stays hidden and menus break.
sbar.bar({
  topmost      = "off",
  height       = 40,
  margin       = 8,
  y_offset     = 4,
  corner_radius = 0,
  color        = colors.transparent,
  border_color = colors.transparent,
  border_width = 0,
  padding_right = 4,
  padding_left  = 4,
  sticky       = true,
  shadow       = false,
})
