-- Items are loaded left → right for "left" position items,
-- and right → left for "right" position items.
-- So calendar (loaded first among right items) appears at the FAR RIGHT.

-- Toggle between native system menu trigger and custom styled popups:
local USE_CUSTOM_MENUS = true

require("items.apple")
if USE_CUSTOM_MENUS then
  require("items.custom_menus")
else
  require("items.menus")
end
require("items.spaces")   -- includes front_app

-- Right side (order = far-right first):
require("items.calendar") -- rightmost: clock/date (safe from notch)
require("items.keyboard") -- immediately to the left of calendar
require("items.weather")  -- to the left of keyboard
require("items.widgets")   -- cpu, wifi, battery, volume
require("items.media")
