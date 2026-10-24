local colors   = require("colors")
local icons    = require("icons")
local settings = require("settings")
local island   = require("helpers.island")
local app_icons = require("helpers.app_icons")

-- ── Spaces island ─────────────────────────────────────────────────────────────
-- MacBook Air M3 13": screen is 2560×1664 logical → 1470px at default scaling.
-- Notch is centred and ~230 px wide → centre zone [620, 850] in logical px.
-- Spaces go on the LEFT side; they are safe.

local spaces = {}

for i = 1, 10 do
  local space = sbar.add("space", "space." .. i, {
    space    = i,
    position = "left",
    icon = {
      font = {
        family = settings.font.numbers,
        style  = settings.font.style_map["Bold"],
        size   = 12.0,
      },
      string        = i,
      padding_left  = 10,
      padding_right = 6,
      color         = colors.grey,
      highlight_color = colors.arch,
    },
    label = {
      padding_right = 10,
      color         = colors.grey,
      highlight_color = colors.arch,
      font = "sketchybar-app-font:Regular:14.0",
      y_offset = -1,
    },
    padding_right = 1,
    padding_left  = 1,
    background    = { color = colors.transparent },
    popup         = { background = { border_width = 1, border_color = colors.island_border } },
  })

  spaces[i] = space

  -- Popup: space preview thumbnail
  local space_popup = sbar.add("item", {
    position     = "popup." .. space.name,
    padding_left = 5,
    padding_right = 0,
    background   = {
      drawing = true,
      image   = { corner_radius = 9, scale = 0.2 },
    },
  })

  space:subscribe("space_change", function(env)
    local selected = env.SELECTED == "true"
    space:set({
      icon  = { highlight = selected, color = selected and colors.arch or colors.grey },
      label = { highlight = selected, color = selected and colors.arch or colors.grey },
    })
  end)

  space:subscribe("mouse.clicked", function(env)
    if env.BUTTON == "other" then
      space_popup:set({ background = { image = "space." .. env.SID } })
      space:set({ popup = { drawing = "toggle" } })
    else
      local op = (env.BUTTON == "right") and "--destroy" or "--focus"
      sbar.exec("yabai -m space " .. op .. " " .. env.SID)
    end
  end)

  space:subscribe("mouse.exited", function()
    space:set({ popup = { drawing = false } })
  end)
end

-- Wrap all spaces in a single pill island
island({ '/space\\.\\d+/' }, "spaces.island")

-- ── Front app (shown between spaces and centre) ───────────────────────────────
local front_app = sbar.add("item", "front_app", {
  position = "left",
  drawing  = true,
  icon     = { drawing = false },
  label = {
    font = {
      style = settings.font.style_map["Black"],
      size  = 12.0,
    },
    padding_left  = 12,
    padding_right = 12,
    color         = colors.white,
  },
  updates = true,
})

island({ front_app.name }, "front_app.island")

front_app:subscribe("front_app_switched", function(env)
  front_app:set({ label = { string = env.INFO } })
end)

front_app:subscribe("mouse.clicked", function()
  sbar.trigger("swap_menus_and_spaces")
end)

-- ── Window observer for space app-icons ──────────────────────────────────────
local space_window_observer = sbar.add("item", { drawing = false, updates = true })

space_window_observer:subscribe("space_windows_change", function(env)
  local icon_line = ""
  local no_app    = true
  for app, _ in pairs(env.INFO.apps) do
    no_app = false
    local lookup = app_icons[app]
    icon_line = icon_line .. " " .. (lookup or app_icons["default"])
  end
  if no_app then icon_line = " —" end
  sbar.animate("tanh", 10, function()
    spaces[env.INFO.space]:set({ label = icon_line })
  end)
end)
