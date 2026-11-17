local icons        = require("icons")
local colors       = require("colors")
local settings     = require("settings")
local island       = require("helpers.island")
local compact_mode = require("helpers.compact_mode")

-- ── Battery island ────────────────────────────────────────────────────────────
local battery = sbar.add("item", "widgets.battery", {
  position = "right",
  icon = {
    font = {
      family = settings.font.text,
      style  = settings.font.style_map["Regular"],
      size   = 17.0,
    },
    padding_left  = 8,
    padding_right = 4,
  },
  label = {
    font          = { family = settings.font.numbers },
    padding_right = 8,
  },
  update_freq = 120,
  padding_left  = 0,
  padding_right = 0,
})

local battery_island = island({ battery.name }, "widgets.battery.island", {
  popup = { align = "center" }
})

-- Popup: time remaining
local remaining_time = sbar.add("item", {
  position = "popup." .. battery_island.name,
  width    = 220,
  icon = { string = "Time remaining:", align = "left", width = 110, color = colors.grey },
  label = { string = "??:??h", align = "right", width = 110 },
})

local last_icon  = icons.battery._100
local last_color = colors.green
local last_label = "100%"

local function render_battery()
  if compact_mode.is_compact then
    battery:set({
      icon  = { drawing = false },
      label = {
        string        = last_label,
        padding_left  = 8,
        padding_right = 8,
      },
    })
  else
    battery:set({
      icon  = {
        string        = last_icon,
        color         = last_color,
        drawing       = true,
        padding_left  = 8,
        padding_right = 4,
      },
      label = {
        string        = last_label,
        padding_left  = 0,
        padding_right = 8,
      },
    })
  end
end

compact_mode.on_change(function()
  render_battery()
end)

-- ── Update ────────────────────────────────────────────────────────────────────
battery:subscribe({ "routine", "power_source_change", "system_woke" }, function()
  sbar.exec("pmset -g batt", function(batt_info)
    local icon  = "!"
    local label = "?"

    local found, _, charge = batt_info:find("(%d+)%%")
    if found then
      charge = tonumber(charge)
      label  = charge .. "%"
    end

    local color    = colors.green
    local charging = batt_info:find("AC Power")

    if charging then
      icon = icons.battery.charging
    else
      if found and charge > 80 then
        icon = icons.battery._100
      elseif found and charge > 60 then
        icon = icons.battery._75
      elseif found and charge > 40 then
        icon = icons.battery._50
      elseif found and charge > 20 then
        icon  = icons.battery._25
        color = colors.orange
      else
        icon  = icons.battery._0
        color = colors.red
      end
    end

    local lead = (found and charge < 10) and "0" or ""
    last_icon  = icon
    last_color = color
    last_label = lead .. label
    render_battery()
  end)
end)

battery:subscribe("mouse.clicked", function()
  local open = battery_island:query().popup.drawing == "off"
  battery_island:set({ popup = { drawing = open } })
  if open then
    sbar.exec("pmset -g batt", function(batt_info)
      local found, _, rem = batt_info:find(" (%d+:%d+) remaining")
      remaining_time:set({ label = found and rem .. "h" or "No estimate" })
    end)
  end
end)

battery_island:subscribe("mouse.exited.global", function()
  battery_island:set({ popup = { drawing = false } })
end)
