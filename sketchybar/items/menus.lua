local colors   = require("colors")
local icons    = require("icons")
local settings = require("settings")
local island   = require("helpers.island")

-- ── Menus island (app menu bar items) ────────────────────────────────────────
local menu_watcher    = sbar.add("item", { drawing = false, updates = false })
local space_menu_swap = sbar.add("item", { drawing = false, updates = true })
sbar.add("event", "swap_menus_and_spaces")

local max_items  = 15
local menu_items = {}

local menu_close = sbar.add("item", "menu.close", {
  position = "left",
  drawing = false,
  icon = {
    string = "<",
    font = { style = settings.font.style_map["Bold"], size = 16.0 },
    padding_left = 10,
    padding_right = 4,
  },
  label = { drawing = false },
  click_script = "sketchybar --trigger swap_menus_and_spaces",
})

-- Left side menu items: 1 through 9 (fits before MacBook Air notch at x ~ 646)
for i = 1, 9 do
  local menu = sbar.add("item", "menu." .. i, {
    position     = "left",
    drawing      = false,
    icon         = { drawing = false },
    label = {
      font = { style = settings.font.style_map[i == 1 and "Heavy" or "Semibold"] },
      padding_left  = 6,
      padding_right = 6,
    },
    click_script = i == 1 and "sketchybar --trigger swap_menus_and_spaces" or "$CONFIG_DIR/helpers/menus/bin/menus -s " .. i,
    padding_left  = settings.paddings,
    padding_right = settings.paddings,
  })
  menu_items[i] = menu
end

-- Spacer bridging across the notch (from end of Window at x ~ 646 to past notch at x ~ 825)
local menu_notch_spacer = sbar.add("item", "menu.notch_spacer", {
  position   = "left",
  drawing    = false,
  width      = 179,
  background = { drawing = false },
  icon       = { drawing = false },
  label      = { drawing = false },
})

-- Right side menu items: 10 through max_items (starts after notch at x ~ 836)
for i = 10, max_items do
  local menu = sbar.add("item", "menu." .. i, {
    position     = "left",
    drawing      = false,
    icon         = { drawing = false },
    label = {
      font = { style = settings.font.style_map["Semibold"] },
      padding_left  = 6,
      padding_right = 6,
    },
    click_script = "$CONFIG_DIR/helpers/menus/bin/menus -s " .. i,
    padding_left  = settings.paddings,
    padding_right = settings.paddings,
  })
  menu_items[i] = menu
end

-- Left menu island (before notch)
local left_bracket_items = { "menu.close" }
for i = 1, 9 do
  table.insert(left_bracket_items, "menu." .. i)
end
local menu_left_bracket = island(left_bracket_items, "menus.island")

-- Right menu island (after notch)
local right_bracket_items = {}
for i = 10, max_items do
  table.insert(right_bracket_items, "menu." .. i)
end
local menu_right_bracket = island(right_bracket_items, "menus.island.right")

local menu_padding = sbar.add("item", "menu.padding", {
  position = "left",
  drawing  = false,
  width    = 5,
})

local function update_menus()
  sbar.exec("$CONFIG_DIR/helpers/menus/bin/menus -l", function(menus)
    sbar.set('/menu\\..*/', { drawing = false })
    menu_padding:set({ drawing = true })
    menu_close:set({ drawing = true })

    local id = 1
    local has_right_items = false
    for menu in string.gmatch(menus, '[^\r\n]+') do
      if id <= max_items then
        menu_items[id]:set({ label = menu, drawing = true })
        if id >= 10 then
          has_right_items = true
        end
      else break end
      id = id + 1
    end

    menu_notch_spacer:set({ drawing = has_right_items })
  end)
end

menu_watcher:subscribe("front_app_switched", update_menus)

space_menu_swap:subscribe("swap_menus_and_spaces", function()
  local drawing = menu_items[1]:query().geometry.drawing == "on"
  if drawing then
    menu_watcher:set({ updates = false })
    sbar.set("/menu\\..*/", { drawing = false })
    sbar.set("/space\\..*/", { drawing = true })
    sbar.set("front_app", { drawing = true })
  else
    menu_watcher:set({ updates = true })
    sbar.set("/space\\..*/", { drawing = false })
    sbar.set("front_app", { drawing = false })
    update_menus()
  end
end)

return menu_watcher
