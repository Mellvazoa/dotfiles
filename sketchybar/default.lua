local settings = require("settings")
local colors   = require("colors")

-- Default item appearance – items sit inside transparent pill brackets
sbar.default({
  updates = "when_shown",
  icon = {
    font = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 13.0,
    },
    color         = colors.white,
    padding_left  = settings.paddings,
    padding_right = settings.paddings,
  },
  label = {
    font = {
      family = settings.font.text,
      style  = settings.font.style_map["Semibold"],
      size   = 12.0,
    },
    color         = colors.white,
    padding_left  = settings.paddings,
    padding_right = settings.paddings,
  },
  background = {
    height        = 28,  -- island height (30) minus 2×border (1px)
    corner_radius = 0,
    border_width  = 0,
    border_color  = colors.transparent,
    color         = colors.transparent,
  },
  popup = {
    background = {
      border_width  = 1,
      corner_radius = 4,
      border_color  = colors.popup.border,
      color         = colors.popup.bg,
      shadow        = { drawing = true },
    },
    blur_radius = 60,
  },
  padding_left  = 4,
  padding_right = 4,
  scroll_texts  = true,
})
