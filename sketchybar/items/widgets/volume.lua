local colors   = require("colors")
local icons    = require("icons")
local settings = require("settings")
local island   = require("helpers.island")

-- ── Volume island ──────────────────────────────────────────────────────────────
local popup_w = 260

-- Volume percentage (added first so it goes to the far right)
local volume_pct = sbar.add("item", "widgets.volume.pct", {
  position = "right",
  icon     = { drawing = false },
  label = {
    string = "??%",
    font   = { family = settings.font.numbers, size = 11.0 },
    color  = colors.white,
    padding_left  = 2,
    padding_right = 6,
  },
  padding_left  = 0,
  padding_right = 0,
})

-- Volume icon (added second so it goes to the left of percentage)
local volume_icon = sbar.add("item", "widgets.volume.icon", {
  position = "right",
  label    = { drawing = false },
  icon = {
    string        = icons.volume._100,
    font          = {
      family = settings.font.text,
      style  = settings.font.style_map["Regular"],
      size   = 14.0,
    },
    color         = colors.lavender,
    padding_left  = 6,
    padding_right = 2,
  },
  padding_left  = 0,
  padding_right = 0,
})

local volume_island = island(
  { volume_pct.name, volume_icon.name },
  "widgets.volume.island",
  { popup = { align = "center" } }
)

-- Popup: slider + output device list
local volume_slider = sbar.add("slider", popup_w, {
  position = "popup." .. volume_island.name,
  slider = {
    highlight_color = colors.lavender,
    background = {
      height        = 6,
      corner_radius = 3,
      color         = colors.bg2,
    },
    knob = { string = "􀀁", drawing = true },
  },
  background    = { color = colors.island, height = 2, y_offset = -20 },
  click_script  = 'osascript -e "set volume output volume $PERCENTAGE"',
})

-- ── Update ────────────────────────────────────────────────────────────────────
local function update_icon(volume)
  local icon = icons.volume._0
  if     volume > 60 then icon = icons.volume._100
  elseif volume > 30 then icon = icons.volume._66
  elseif volume > 10 then icon = icons.volume._33
  elseif volume > 0  then icon = icons.volume._10
  end
  return icon
end

volume_icon:subscribe("volume_change", function(env)
  local vol  = tonumber(env.INFO)
  local lead = vol < 10 and "0" or ""
  volume_icon:set({ icon  = { string = update_icon(vol) } })
  volume_pct:set({  label = lead .. vol .. "%" })
  volume_slider:set({ slider = { percentage = vol } })
end)

-- ── Popup toggle ──────────────────────────────────────────────────────────────
local current_device = ""

local function collapse()
  if volume_island:query().popup.drawing == "on" then
    volume_island:set({ popup = { drawing = false } })
    sbar.remove('/volume.device\\.*/')
  end
end

local function toggle(env)
  if env and env.BUTTON == "right" then
    sbar.exec("open /System/Library/PreferencePanes/Sound.prefpane")
    return
  end

  local open = volume_island:query().popup.drawing == "off"
  volume_island:set({ popup = { drawing = open } })

  if open then
    sbar.exec("SwitchAudioSource -t output -c", function(result)
      current_device = result:sub(1, -2)
      sbar.exec("SwitchAudioSource -a -t output", function(available)
        local counter = 0
        for device in string.gmatch(available, '[^\r\n]+') do
          local color = (current_device == device) and colors.white or colors.grey
          sbar.add("item", "volume.device." .. counter, {
            position     = "popup." .. volume_island.name,
            width        = popup_w,
            align        = "center",
            label        = { string = device, color = color },
            click_script = 'SwitchAudioSource -s "' .. device ..
              '" && sketchybar --set /volume.device\\.*/ label.color=' .. colors.grey ..
              ' --set $NAME label.color=' .. colors.white,
          })
          counter = counter + 1
        end
      end)
    end)
  else
    collapse()
  end
end

local function scroll(env)
  local delta = env.SCROLL_DELTA
  sbar.exec('osascript -e "set volume output volume (output volume of (get volume settings) + ' .. delta .. ')"')
end

volume_icon:subscribe("mouse.clicked",         toggle)
volume_icon:subscribe("mouse.scrolled",        scroll)
volume_pct:subscribe("mouse.clicked",          toggle)
volume_pct:subscribe("mouse.scrolled",         scroll)
volume_island:subscribe("mouse.exited.global", collapse)
