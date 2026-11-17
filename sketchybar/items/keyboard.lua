local icons    = require("icons")
local colors   = require("colors")
local settings = require("settings")
local island   = require("helpers.island")

-- ── Keyboard Layout Island (Event-driven, 0% CPU polling) ────────────────────
sbar.exec("killall keyboard_load >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/keyboard_load/bin/keyboard_load keyboard_change &")

local kbd = sbar.add("item", "keyboard", {
  position = "right",
  icon = {
    string        = icons.keyboard or "󰌌",
    color         = colors.lavender,
    padding_left  = 8,
    padding_right = 3,
    font = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 12.0,
    },
  },
  label = {
    string        = "RU",
    color         = colors.white,
    padding_left  = 0,
    padding_right = 8,
    font = {
      family = settings.font.numbers,
      style  = settings.font.style_map["Bold"],
      size   = 11.0,
    },
  },
  padding_left  = 0,
  padding_right = 0,
})

island({ kbd.name }, "keyboard.island")

local function update_layout(layout)
  if not layout or layout == "" then return end
  layout = layout:gsub("%s+", "")
  local icon_color = (layout == "RU") and colors.lavender or colors.blue
  kbd:set({
    icon  = { color = icon_color },
    label = { string = layout },
  })
end

-- Subscribe to keyboard_change event triggered by keyboard_load C helper
kbd:subscribe("keyboard_change", function(env)
  update_layout(env.layout)
end)

-- Fetch current on startup / reload / wake
kbd:subscribe({ "forced", "system_woke" }, function()
  sbar.exec("$CONFIG_DIR/helpers/event_providers/keyboard_load/bin/keyboard_load current", function(layout)
    update_layout(layout)
  end)
end)

-- Click toggles layout
kbd:subscribe("mouse.clicked", function()
  sbar.exec("$CONFIG_DIR/helpers/event_providers/keyboard_load/bin/keyboard_load toggle")
end)
