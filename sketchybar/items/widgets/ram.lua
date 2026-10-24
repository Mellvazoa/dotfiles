local colors   = require("colors")
local settings = require("settings")
local island   = require("helpers.island")

-- ── RAM / Memory island (Waybar / Arch style) ─────────────────────────────────
local ram = sbar.add("item", "widgets.ram", {
  position = "right",
  icon = {
    string        = "󰍛", -- Nerd Font RAM icon
    font          = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 14.0,
    },
    color         = colors.lavender,
    padding_left  = 8,
    padding_right = 4,
  },
  label = {
    string        = "??%",
    font          = {
      family = settings.font.numbers,
      style  = settings.font.style_map["Bold"],
      size   = 11.0,
    },
    color         = colors.white,
    padding_right = 8,
  },
  update_freq = 3,
  padding_left  = 0,
  padding_right = 0,
})

local ram_island = island({ ram.name }, "widgets.ram.island", {
  popup = { align = "center" }
})

local popup_w = 240

sbar.add("item", {
  position      = "popup." .. ram_island.name,
  width         = popup_w,
  align         = "center",
  icon          = { string = "Memory (RAM)", align = "center", width = popup_w / 2 },
  label         = { drawing = false },
  background    = {
    height       = 2,
    color        = colors.island_border,
    y_offset     = -15,
  },
})

local ram_used_row = sbar.add("item", {
  position = "popup." .. ram_island.name,
  width    = popup_w,
  align    = "center",
  icon = {
    string = "Used Memory:",
    align  = "left",
    width  = popup_w / 2,
    color  = colors.grey,
    font   = { size = 11 },
  },
  label = {
    string = "??%",
    align  = "right",
    width  = popup_w / 2,
    font   = { family = settings.font.numbers, size = 11 },
    color  = colors.white,
  },
})

ram:subscribe({ "routine", "forced" }, function()
  sbar.exec("memory_pressure | awk '/System-wide memory free percentage:/ { printf(\"%d\", 100 - $5) }'", function(used_str)
    local used = tonumber(used_str) or 0
    local color = colors.white
    if used > 85 then
      color = colors.red
    elseif used > 70 then
      color = colors.orange
    end

    ram:set({
      label = { string = used .. "%", color = color },
      icon  = { color = (used > 85 and colors.red) or colors.lavender },
    })
    ram_used_row:set({ label = used .. "%" })
  end)
end)

ram:subscribe("mouse.clicked", function()
  local open = ram_island:query().popup.drawing == "off"
  ram_island:set({ popup = { drawing = open } })
end)

ram_island:subscribe("mouse.exited.global", function()
  ram_island:set({ popup = { drawing = false } })
end)
