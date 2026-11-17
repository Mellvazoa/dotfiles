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

local AUDIO_VOL = os.getenv("HOME") .. "/.local/bin/audio_vol"

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
  click_script  = AUDIO_VOL .. ' set "$PERCENTAGE"',
})

-- ── Update ────────────────────────────────────────────────────────────────────
local function update_icon(volume, muted)
  if muted or volume <= 0 then return icons.volume._0 end
  if volume > 60 then return icons.volume._100
  elseif volume > 30 then return icons.volume._66
  elseif volume > 10 then return icons.volume._33
  else return icons.volume._10
  end
end

local function apply_volume_ui(vol, muted)
  vol = math.max(0, math.min(100, math.floor((tonumber(vol) or 0) + 0.5)))
  local is_muted = muted or (vol == 0)
  local lead = vol < 10 and "0" or ""
  volume_icon:set({
    icon = {
      string = update_icon(vol, is_muted),
      color  = is_muted and colors.grey or colors.lavender,
    },
  })
  volume_pct:set({
    label = {
      string = is_muted and "MUTE" or (lead .. vol .. "%"),
      color  = is_muted and colors.grey or colors.white,
    },
  })
  volume_slider:set({ slider = { percentage = is_muted and 0 or vol } })
end

local function refresh_volume()
  sbar.exec(AUDIO_VOL .. " state", function(out)
    if not out then return end
    local pct_s, mute_s = out:match("^(%d+)\t([01])")
    if pct_s then
      apply_volume_ui(tonumber(pct_s), mute_s == "1")
    end
  end)
end

volume_icon:subscribe("volume_change", function(env)
  if env.MUTED ~= nil then
    local vol = tonumber(env.INFO)
    if vol then
      apply_volume_ui(vol, env.MUTED == "1")
      return
    end
  end
  -- Native Sketchybar volume_change reports 0 on Multi-Output devices;
  -- query audio_vol so aggregate sub-device volume stays accurate.
  refresh_volume()
end)

volume_icon:subscribe("system_woke", refresh_volume)
refresh_volume()

-- ── Popup toggle ──────────────────────────────────────────────────────────────
local function collapse()
  if volume_island:query().popup.drawing == "on" then
    volume_island:set({ popup = { drawing = false } })
    sbar.remove('/volume.device\\.*/')
  end
end

local function populate_devices(on_done)
  sbar.exec(AUDIO_VOL .. " devices", function(available)
    sbar.remove('/volume.device\\.*/')
    local counter = 0
    if available then
      for line in string.gmatch(available, '[^\r\n]+') do
        local uid, name, cur = line:match("^(.-)\t(.-)\t([01])$")
        if uid and name then
          local color = (cur == "1") and colors.white or colors.grey
          local esc_uid = uid:gsub('"', '\\"')
          sbar.add("item", "volume.device." .. counter, {
            position      = "popup." .. volume_island.name,
            width         = popup_w,
            scroll_texts  = false,
            updates       = true,
            icon          = { drawing = false, width = 0, padding_left = 0, padding_right = 0 },
            label         = {
              string        = name,
              color         = color,
              align         = "center",
              width         = popup_w,
              padding_left  = 0,
              padding_right = 0,
            },
            click_script  = AUDIO_VOL .. ' select "' .. esc_uid ..
              '" && sketchybar --set /volume.device\\.*/ label.color=' .. colors.grey ..
              ' --set $NAME label.color=' .. colors.white ..
              ' --trigger volume_change',
          })
          counter = counter + 1
        end
      end
    end
    if on_done then on_done() end
  end)
end

populate_devices()

local function toggle(env)
  if env and env.BUTTON == "right" then
    sbar.exec("open /System/Library/PreferencePanes/Sound.prefpane")
    return
  end

  local is_closed = volume_island:query().popup.drawing == "off"
  if is_closed then
    refresh_volume()
    populate_devices(function()
      volume_island:set({ popup = { drawing = true } })
    end)
  else
    collapse()
  end
end

local function scroll(env)
  local delta = tonumber(env.SCROLL_DELTA) or 0
  if delta ~= 0 then
    sbar.exec(AUDIO_VOL .. " step " .. delta)
  end
end

volume_icon:subscribe("mouse.clicked",         toggle)
volume_icon:subscribe("mouse.scrolled",        scroll)
volume_pct:subscribe("mouse.clicked",          toggle)
volume_pct:subscribe("mouse.scrolled",         scroll)
volume_island:subscribe("mouse.exited.global", collapse)
