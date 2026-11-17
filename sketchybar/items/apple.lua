local colors   = require("colors")
local settings = require("settings")
local island   = require("helpers.island")
local icons    = require("icons")

-- ── Apple menu button ────────────────────────────────────────────────────────
local apple = sbar.add("item", "apple", {
  position = "left",
  icon = {
    string        = icons.apple,
    font          = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 15.0,
    },
    color         = colors.lavender or colors.white,
    padding_left  = 10,
    padding_right = 10,
  },
  label         = { drawing = false },
  background    = { color = colors.transparent },
  padding_left  = 0,
  padding_right = 0,
})

apple:subscribe("mouse.clicked", function(env)
  if env and env.BUTTON == "right" then
    sbar.exec("osascript -e 'tell application \"System Events\" to tell process \"Finder\" to click menu bar item 1 of menu bar 1'")
  else
    sbar.exec("~/.local/bin/powermenu --toggle")
  end
end)

island({ apple.name }, "apple.island")
