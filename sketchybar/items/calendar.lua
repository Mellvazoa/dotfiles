local settings     = require("settings")
local colors       = require("colors")
local island       = require("helpers.island")
local compact_mode = require("helpers.compact_mode")

-- ── Calendar / Clock island (RIGHT side, first/outermost item) ───────────────
-- Placed at "right" to avoid the notch entirely; goes at the far-right edge.

local cal = sbar.add("item", "cal", {
  position = "right",
  icon = {
    color        = colors.lavender,
    padding_left = 10,
    padding_right = 4,
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

local function update_cal()
  if compact_mode.is_compact then
    cal:set({
      icon  = { drawing = false, string = "" },
      label = {
        string        = os.date("%H:%M"),
        padding_left  = 10,
        padding_right = 10,
      },
    })
  else
    cal:set({
      icon  = {
        drawing       = true,
        string        = os.date("󰃭 %a %d %b"),
        padding_left  = 10,
        padding_right = 4,
      },
      label = {
        string        = os.date("%H:%M"),
        padding_left  = 0,
        padding_right = 10,
      },
    })
  end
end

compact_mode.on_change(function()
  update_cal()
end)

cal:subscribe({ "forced", "routine", "system_woke" }, function()
  update_cal()
end)

cal:subscribe("mouse.clicked", function()
  sbar.exec("~/.local/bin/calendar_popup >/dev/null 2>&1 &")
end)
