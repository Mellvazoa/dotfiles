local colors   = require("colors")
local island   = require("helpers.island")
local icons    = require("icons")

-- Stop any leftover bar cava helper if previously running
sbar.exec("pkill -x cava_load >/dev/null 2>&1; pkill -f 'cava_load/cava\\.conf' >/dev/null 2>&1")

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

-- Popup controls
sbar.add("item", { position = "popup." .. media_cover.name, icon = { string = icons.media.back },       label = { drawing = false }, click_script = "nowplaying-cli previous" })
sbar.add("item", { position = "popup." .. media_cover.name, icon = { string = icons.media.play_pause }, label = { drawing = false }, click_script = "nowplaying-cli togglePlayPause" })
sbar.add("item", { position = "popup." .. media_cover.name, icon = { string = icons.media.forward },    label = { drawing = false }, click_script = "nowplaying-cli next" })

-- Wrap in media island
island({ media_cover.name, media_artist.name, media_title.name }, "media.island")

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
  if not env or not env.INFO or not env.INFO.state then return end
  local is_playing = (env.INFO.state == "playing")
  if whitelist[env.INFO.app] or is_playing then
    media_artist:set({ drawing = is_playing, label = env.INFO.artist })
    media_title:set({  drawing = is_playing, label = env.INFO.title })
    media_cover:set({  drawing = is_playing })
    if is_playing then
      animate_detail(true)
      interrupt = interrupt + 1
      sbar.delay(5, animate_detail)
    else
      media_cover:set({ popup = { drawing = false } })
    end
  else
    media_cover:set({ popup = { drawing = false } })
  end
end)

media_cover:subscribe("mouse.entered",      function() interrupt = interrupt + 1; animate_detail(true)  end)
media_cover:subscribe("mouse.exited",       function() animate_detail(false) end)
media_cover:subscribe("mouse.clicked",      function() media_cover:set({ popup = { drawing = "toggle" } }) end)
media_title:subscribe("mouse.exited.global",function() media_cover:set({ popup = { drawing = false } }) end)
