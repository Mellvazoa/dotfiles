-- island.lua – helper that wraps a list of item names in a "pill" bracket
-- Usage:
--   local island = require("helpers.island")
--   island({ item1.name, item2.name }, "my.island")
--
-- Returns the bracket item so callers can attach popups to it.

local colors   = require("colors")
local settings = require("settings")

local function make_island(names, bracket_name, extra)
  extra = extra or {}
  local bg = {
    color         = colors.island,
    border_color  = colors.island_border,
    border_width  = settings.pill.border_width,
    corner_radius = settings.pill.corner_radius,
    height        = settings.pill.height,
  }
  -- merge extra background keys
  if extra.background then
    for k, v in pairs(extra.background) do bg[k] = v end
    extra.background = nil
  end
  local props = { background = bg }
  for k, v in pairs(extra) do props[k] = v end

  return sbar.add("bracket", bracket_name, names, props)
end

return make_island
