-- Add the sketchybar module to the package cpath
package.cpath = package.cpath .. ";/Users/" .. os.getenv("USER") .. "/.local/share/sketchybar_lua/?.so"

local required_bins = {
  "helpers/menus/bin/menus",
  "helpers/custom_menus/bin/custom_menus",
  "helpers/event_providers/cpu_load/bin/cpu_load",
  "helpers/event_providers/network_load/bin/network_load",
  "helpers/event_providers/keyboard_load/bin/keyboard_load",
  "helpers/event_providers/cava_load/bin/cava_load",
}

local needs_build = false
for _, path in ipairs(required_bins) do
  local f = io.open(path, "rb")
  if f then
    f:close()
  else
    needs_build = true
    break
  end
end

if needs_build then
  os.execute("(cd helpers && make)")
end
