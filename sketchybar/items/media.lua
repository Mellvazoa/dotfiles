local settings = require("settings")
local colors   = require("colors")
local island   = require("helpers.island")
local icons    = require("icons")

-- ── Launch Cava audio visualizer background provider ─────────────────────────
-- Listens to BlackHole 2ch; automatically shows media.visualizer when audio plays
sbar.exec("killall cava_load cava >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/cava_load/bin/cava_load media.visualizer &")

local whitelist = {
  ["Spotify"]       = true,
  ["Music"]         = true,
  ["Telegram"]      = true,
  ["Brave Browser"] = true,
  ["Google Chrome"] = true,
  ["Safari"]        = true,
}

-- Cover artwork (far right)
local media_cover = sbar.add("item", "media.cover", {
  position = "right",
  background = {
    image = { string = "media.artwork", scale = 0.85 },
    color = colors.transparent,
  },
  label   = { drawing = false },
  icon    = { drawing = false },
  drawing = false,
  updates = true,
  popup   = { align = "center", horizontal = true },
})

-- Artist label
local media_artist = sbar.add("item", "media.artist", {
  position      = "right",
  drawing       = false,
  padding_left  = 3,
  padding_right = 0,
  width         = 0,
  icon          = { drawing = false },
  label = {
    width     = 0,
    font      = { size = 9 },
    color     = colors.with_alpha(colors.white, 0.6),
    max_chars = 18,
    y_offset  = 6,
  },
})

-- Title label
local media_title = sbar.add("item", "media.title", {
  position      = "right",
  drawing       = false,
  padding_left  = 3,
  padding_right = 0,
  icon          = { drawing = false },
  label = {
    font      = { size = 11 },
    width     = 0,
    max_chars = 16,
    y_offset  = -5,
  },
})

-- Real-time Cava audio visualizer bars (works with Telegram, YouTube, Spotify, etc.)
local media_visualizer = sbar.add("item", "media.visualizer", {
  position      = "right",
  drawing       = false,
  padding_left  = 6,
  padding_right = 6,
  icon = {
    string        = "󰝚",
    font          = { family = settings.font.text, size = 12.0 },
    color         = colors.lavender,
    padding_left  = 2,
    padding_right = 4,
  },
  label = {
    font = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 12.0,
    },
    color     = colors.lavender,
    string    = "",
    y_offset  = 0,
  },
})

-- Popup controls
sbar.add("item", { position = "popup." .. media_cover.name, icon = { string = icons.media.back },       label = { drawing = false }, click_script = "nowplaying-cli previous" })
sbar.add("item", { position = "popup." .. media_cover.name, icon = { string = icons.media.play_pause }, label = { drawing = false }, click_script = "nowplaying-cli togglePlayPause" })
sbar.add("item", { position = "popup." .. media_cover.name, icon = { string = icons.media.forward },    label = { drawing = false }, click_script = "nowplaying-cli next" })

-- Wrap in media island
island({ media_cover.name, media_artist.name, media_title.name, media_visualizer.name }, "media.island")

local interrupt = 0
local function animate_detail(detail)
  if not detail then interrupt = interrupt - 1 end
  if interrupt > 0 and not detail then return end
  sbar.animate("tanh", 30, function()
    media_artist:set({ label = { width = detail and "dynamic" or 0 } })
    media_title:set({  label = { width = detail and "dynamic" or 0 } })
  end)
end

media_cover:subscribe("media_change", function(env)
  if whitelist[env.INFO.app] or env.INFO.state == "playing" then
    local drawing = env.INFO.state == "playing"
    media_artist:set({ drawing = drawing, label = env.INFO.artist })
    media_title:set({  drawing = drawing, label = env.INFO.title })
    media_cover:set({  drawing = drawing })
    if drawing then
      animate_detail(true)
      interrupt = interrupt + 1
      sbar.delay(5, animate_detail)
    else
      media_cover:set({ popup = { drawing = false } })
    end
  end
end)

media_cover:subscribe("mouse.entered",      function() interrupt = interrupt + 1; animate_detail(true)  end)
media_cover:subscribe("mouse.exited",       function() animate_detail(false) end)
media_cover:subscribe("mouse.clicked",      function() media_cover:set({ popup = { drawing = "toggle" } }) end)
media_title:subscribe("mouse.exited.global",function() media_cover:set({ popup = { drawing = false } }) end)
media_visualizer:subscribe("mouse.clicked", function() media_cover:set({ popup = { drawing = "toggle" } }) end)
