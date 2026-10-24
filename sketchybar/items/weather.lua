local colors   = require("colors")
local settings = require("settings")
local island   = require("helpers.island")

-- ── Weather island (placed immediately to the left of calendar) ───────────────

local weather = sbar.add("item", "widgets.weather", {
  position = "right",
  icon = {
    string        = "󰖐",
    color         = colors.lavender,
    padding_left  = 10,
    padding_right = 4,
    font = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 14.0,
    },
  },
  label = {
    string        = "--°",
    color         = colors.white,
    padding_left  = 2,
    padding_right = 10,
    font = {
      family = settings.font.numbers,
      style  = settings.font.style_map["Bold"],
      size   = 12.0,
    },
  },
  update_freq   = 900, -- update every 15 minutes (virtually 0% CPU)
  padding_left  = 0,
  padding_right = 0,
})

local weather_island = island({ weather.name }, "widgets.weather.island", {
  popup = { align = "center" }
})

-- ── Weather condition code mapping (WWO / wttr.in codes) ──────────────────────
local weather_icons = {
  ["113"] = "󰖙", -- Sunny / Clear
  ["116"] = "󰖕", -- Partly cloudy
  ["119"] = "󰖐", -- Cloudy
  ["122"] = "󰖐", -- Overcast
  ["143"] = "󰖑", -- Mist
  ["248"] = "󰖑", -- Fog
  ["260"] = "󰖑", -- Freezing fog
  -- Rain / Drizzle
  ["176"] = "󰖗",
  ["263"] = "󰖗",
  ["266"] = "󰖗",
  ["293"] = "󰖗",
  ["296"] = "󰖗",
  ["299"] = "󰖗",
  ["302"] = "󰖗",
  ["305"] = "󰖗",
  ["308"] = "󰖖", -- Heavy rain
  ["353"] = "󰖗",
  ["356"] = "󰖗",
  ["359"] = "󰖖",
  -- Thunderstorm
  ["200"] = "󰙾",
  ["386"] = "󰙾",
  ["389"] = "󰙾",
  ["392"] = "󰙾",
  ["395"] = "󰙾",
  -- Hail / Sleet
  ["179"] = "󰖒",
  ["182"] = "󰖒",
  ["185"] = "󰖒",
  ["281"] = "󰖒",
  ["284"] = "󰖒",
  ["311"] = "󰖒",
  ["314"] = "󰖒",
  ["317"] = "󰖒",
  ["350"] = "󰖒",
  ["374"] = "󰖒",
  ["377"] = "󰖒",
  -- Snow / Blizzard
  ["227"] = "󰖘",
  ["230"] = "󰖘",
  ["320"] = "󰖘",
  ["323"] = "󰖘",
  ["326"] = "󰖘",
  ["329"] = "󰖘",
  ["332"] = "󰖘",
  ["335"] = "󰖘",
  ["338"] = "󰖘",
  ["368"] = "󰖘",
  ["371"] = "󰖘",
}

-- ── Popup items ───────────────────────────────────────────────────────────────
local popup_w = 250

local popup_city = sbar.add("item", {
  position   = "popup." .. weather_island.name,
  width      = popup_w,
  align      = "center",
  icon       = {
    string = "Погода",
    align  = "center",
    width  = popup_w,
    color  = colors.lavender_light,
    font   = { family = settings.font.text, style = settings.font.style_map["Bold"], size = 13.0 },
  },
  label      = { drawing = false },
  background = { height = 2, color = colors.island_border, y_offset = -12 },
})

local popup_cond = sbar.add("item", {
  position = "popup." .. weather_island.name,
  width    = popup_w,
  icon     = { string = "Состояние:", align = "left", width = 100, color = colors.grey, font = { size = 11 } },
  label    = { string = "Загрузка...", align = "right", width = popup_w - 100, color = colors.white, font = { size = 11 } },
})

local popup_temp = sbar.add("item", {
  position = "popup." .. weather_island.name,
  width    = popup_w,
  icon     = { string = "Температура:", align = "left", width = 105, color = colors.grey, font = { size = 11 } },
  label    = { string = "...", align = "right", width = popup_w - 105, color = colors.lavender, font = { family = settings.font.numbers, size = 11 } },
})

local popup_feels = sbar.add("item", {
  position = "popup." .. weather_island.name,
  width    = popup_w,
  icon     = { string = "Ощущается:", align = "left", width = 105, color = colors.grey, font = { size = 11 } },
  label    = { string = "...", align = "right", width = popup_w - 105, color = colors.lavender_light, font = { family = settings.font.numbers, size = 11 } },
})

local popup_humidity = sbar.add("item", {
  position = "popup." .. weather_island.name,
  width    = popup_w,
  icon     = { string = "Влажность:", align = "left", width = 105, color = colors.grey, font = { size = 11 } },
  label    = { string = "...", align = "right", width = popup_w - 105, color = colors.blue, font = { family = settings.font.numbers, size = 11 } },
})

local popup_wind = sbar.add("item", {
  position = "popup." .. weather_island.name,
  width    = popup_w,
  icon     = { string = "Ветер:", align = "left", width = 105, color = colors.grey, font = { size = 11 } },
  label    = { string = "...", align = "right", width = popup_w - 105, color = colors.green, font = { family = settings.font.numbers, size = 11 } },
})

-- ── Weather update logic ──────────────────────────────────────────────────────
local function update_weather()
  local cmd = [[curl -s --max-time 4 "wttr.in/?format=j1&lang=ru" | jq -r '
    .nearest_area[0].areaName[0].value,
    .current_condition[0].temp_C,
    .current_condition[0].weatherCode,
    (.current_condition[0].lang_ru[0].value // .current_condition[0].weatherDesc[0].value),
    .current_condition[0].FeelsLikeC,
    .current_condition[0].humidity,
    .current_condition[0].windspeedKmph
  ']]

  sbar.exec(cmd, function(res)
    if not res or res == "" then return end

    local lines = {}
    for line in res:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end
    if #lines < 7 then return end

    local city     = lines[1]
    local temp_c   = tonumber(lines[2])
    local code     = lines[3]
    local desc     = lines[4]
    local feels_c  = tonumber(lines[5])
    local humidity = lines[6]
    local wind     = lines[7]

    -- Format temperature
    local temp_str = "--°"
    if temp_c then
      temp_str = (temp_c > 0 and ("+" .. temp_c) or tostring(temp_c)) .. "°"
    end

    -- Pick icon
    local icon = weather_icons[code] or "󰖐"
    if code == "113" then
      local hour = tonumber(os.date("%H")) or 12
      if hour < 6 or hour >= 21 then
        icon = "󰖚" -- Clear night
      end
    end

    weather:set({
      icon  = { string = icon },
      label = { string = temp_str },
    })

    -- Feels like formatted
    local feels_str = "--"
    if feels_c then
      feels_str = (feels_c > 0 and ("+" .. feels_c) or tostring(feels_c)) .. "°C"
    end

    popup_city:set({ icon = { string = icon .. "  " .. city } })
    popup_cond:set({ label = { string = desc } })
    popup_temp:set({ label = { string = temp_str .. "C" } })
    popup_feels:set({ label = { string = feels_str } })
    popup_humidity:set({ label = { string = humidity .. "%" } })
    popup_wind:set({ label = { string = wind .. " км/ч" } })
  end)
end

weather:subscribe({ "routine", "forced", "system_woke" }, function()
  update_weather()
end)

-- ── Popup toggle ──────────────────────────────────────────────────────────────
local function hide()
  weather_island:set({ popup = { drawing = false } })
end

local function toggle()
  local open = weather_island:query().popup.drawing == "off"
  weather_island:set({ popup = { drawing = open } })
  if open then
    update_weather()
  end
end

weather:subscribe("mouse.clicked", toggle)
weather_island:subscribe("mouse.exited.global", hide)
