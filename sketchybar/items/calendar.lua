local settings = require("settings")
local colors   = require("colors")
local island   = require("helpers.island")

-- ── Calendar / Clock island (RIGHT side, first/outermost item) ───────────────
-- Placed at "right" to avoid the notch entirely; goes at the far-right edge.

local cal = sbar.add("item", "cal", {
  position = "right",
  icon = {
    color        = colors.lavender,
    padding_left = 10,
    font = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 12.0,
    },
  },
  label = {
    color         = colors.white,
    padding_right = 10,
    font          = {
      family = settings.font.numbers,
      style  = settings.font.style_map["Bold"],
      size   = 12.0,
    },
  },
  update_freq   = 30,
  padding_left  = 0,
  padding_right = 0,
  background    = { color = colors.transparent },
})

island({ cal.name }, "cal.island")

cal:subscribe({ "forced", "routine", "system_woke" }, function()
  cal:set({
    icon  = os.date("󰃭 %a %d %b"),
    label = os.date("%H:%M"),
  })
end)
