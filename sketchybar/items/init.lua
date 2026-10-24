-- Items are loaded left → right for "left" position items,
-- and right → left for "right" position items.
-- So calendar (loaded first among right items) appears at the FAR RIGHT.

require("items.apple")
require("items.menus")
require("items.spaces")   -- includes front_app

-- Right side (order = far-right first):
require("items.calendar") -- rightmost: clock/date (safe from notch)
require("items.weather")  -- immediately to the left of calendar
require("items.widgets")   -- cpu, wifi, battery, volume
require("items.media")
