local colors       = require("colors")
local icons        = require("icons")
local settings     = require("settings")
local island       = require("helpers.island")
local compact_mode = require("helpers.compact_mode")

-- ── Custom App Menus with styled popups (no native macOS menu bar popup) ─────
-- Speed strategy:
--   * ALL menus are fetched with ONE helper call (`-all`) when the menu bar is
--     expanded / the front app changes, and every popup is pre-built (hidden).
--   * Opening a menu is therefore a single `popup.drawing=on` command.
--   * A background refresh (`-items N`) then patches enabled-state/shortcut
--     changes in place (e.g. "Save" becoming enabled) without any flicker.

local HELPER = "$CONFIG_DIR/helpers/custom_menus/bin/custom_menus"

local menu_watcher    = sbar.add("item", "custom_menu.watcher", { drawing = false, updates = false })
local space_menu_swap = sbar.add("item", "custom_menu.swap", { drawing = false, updates = true })
sbar.add("event", "swap_menus_and_spaces")

local LEFT_SLOTS      = 9
local max_items       = 17
local menu_items      = {}
local slot_to_ax      = {}
local ax_to_slot      = {}
local active_menu_idx = nil
local pending_open    = nil
local pending_all     = nil
local layout_ready    = false
local generation      = 0

-- Notch bounds on the main display (x coordinates in screen/bar points; 0/0 when un-notched)
local notch_left      = 0
local notch_right     = 0
local NOTCH_LEFT_PAD  = 4 -- custom_menus.island bracket extends 4px past its last item
local NOTCH_RIGHT_PAD = 6 -- 4px bracket left overhang + 2px breathing room past notch

-- cache[ax] = { rows = { {kind, title, shortcut, enabled, has_sub, item} ... }, ready = bool }
local cache = {}

-- Dense popup metrics
local ROW_H      = 20
local FONT_SIZE  = 11.0
local CHAR_W     = 6.6    -- JetBrains Mono advance at 11pt
local SIDE_PAD   = 10
local MIN_W      = 170
local MAX_W      = 420
local HOVER      = colors.with_alpha(colors.lavender, 0.20)

-- ── helpers ──────────────────────────────────────────────────────────────────
local function ulen(s) return utf8.len(s) or #s end

local function parse_items(output)
  local rows = {}
  for line in string.gmatch(output, "[^\r\n]+") do
    local id, title, shortcut, en, sub =
      string.match(line, "^(%d+)\t([^\t]*)\t([^\t]*)\t(%d+)\t(%d+)")
    if id then
      rows[#rows + 1] = {
        id       = tonumber(id),
        title    = title,
        shortcut = shortcut,
        enabled  = (en == "1"),
        has_sub  = (sub == "1"),
        sep      = (title == "---" or title == ""),
      }
    end
  end
  return rows
end

local function parse_all(output)
  local menus, cur = {}, nil
  local buf = {}
  local function flush()
    if cur then menus[cur] = parse_items(table.concat(buf, "\n")) end
    buf = {}
  end
  for line in string.gmatch(output, "[^\r\n]+") do
    local h = string.match(line, "^#(%d+)$")
    if h then
      flush()
      cur = tonumber(h)
    else
      buf[#buf + 1] = line
    end
  end
  flush()
  return menus
end

local function row_name(idx, j) return "custom_menu.row." .. idx .. "." .. j end

-- Compute popup width + shortcut column width for a set of rows
local function metrics(rows)
  local title_w, sc_w = 0, 0
  for _, r in ipairs(rows) do
    if not r.sep then
      title_w = math.max(title_w, ulen(r.title) * CHAR_W)
      local s = r.has_sub and "›" or r.shortcut
      sc_w = math.max(sc_w, ulen(s) * CHAR_W)
    end
  end
  local gap = (sc_w > 0) and 18 or 0
  local w = math.floor(math.min(MAX_W, math.max(MIN_W, title_w + gap + sc_w + SIDE_PAD * 2)))
  local scw = math.ceil(sc_w)
  return w, scw
end

local function row_props(r, w, scw)
  local label_str = r.has_sub and "›" or r.shortcut
  return {
    enabled_color = r.enabled and colors.white or colors.with_alpha(colors.grey, 0.55),
    label_color   = r.has_sub and colors.grey
                    or (r.enabled and colors.lavender or colors.with_alpha(colors.grey, 0.55)),
    label_str     = label_str,
  }
end

local function slot_item(ax)
  local slot = ax_to_slot[ax]
  return slot and menu_items[slot] or nil
end

local function build_menu(idx, rows)
  local menu = slot_item(idx)
  if not menu then return end
  local w, scw = metrics(rows)
  local entry = cache[idx] or {}
  cache[idx] = entry

  -- drop previous rows of this menu only when rows were actually created
  if entry.has_rows then
    sbar.remove("/custom_menu\\.row\\." .. idx .. "\\..*/")
    entry.has_rows = false
  end

  -- A separator does not get its own row: it becomes a thin divider line drawn
  -- along the top edge of the next row (keeps the menu dense).
  local divider_next = false
  local divider_y    = ROW_H / 2 - 1
  for j, r in ipairs(rows) do
    if r.sep then
      divider_next = true
    else
      local p = row_props(r, w, scw)
      local line = { drawing = true, height = 1, color = colors.with_alpha(colors.lavender, 0.35), corner_radius = 0, y_offset = divider_y }
      local none = { drawing = false }
      r.item = sbar.add("item", row_name(idx, j), {
        position      = "popup." .. menu.name,
        width         = w,
        padding_left  = 0,
        padding_right = 0,
        background    = { height = ROW_H - 2, corner_radius = 5, color = colors.transparent },
        icon = {
          string        = r.title,
          align         = "left",
          width         = w - SIDE_PAD * 2 - scw,
          color         = p.enabled_color,
          font          = { style = settings.font.style_map["Regular"], size = FONT_SIZE },
          padding_left  = SIDE_PAD,
          padding_right = 0,
          background    = divider_next and line or none,
        },
        label = {
          string        = p.label_str,
          align         = "right",
          width         = scw,
          color         = p.label_color,
          font          = { family = settings.font.numbers,
                            style  = settings.font.style_map["Regular"], size = FONT_SIZE - 0.5 },
          padding_left  = 0,
          padding_right = SIDE_PAD,
          background    = divider_next and line or none,
        },
        click_script = r.enabled and (
          "sketchybar --set " .. menu.name .. " popup.drawing=off; " ..
          HELPER .. " -click " .. idx .. " " .. r.id
        ) or "",
      })
      entry.has_rows = true
      divider_next = false

      if r.enabled then
        local it = r.item
        it:subscribe("mouse.entered", function() it:set({ background = { color = HOVER } }) end)
        it:subscribe("mouse.exited",  function() it:set({ background = { color = colors.transparent } }) end)
      end
    end
  end

  entry.rows  = rows
  entry.ready = true
end

-- Patch an already built menu in place when only state changed; rebuild otherwise
local function refresh_menu(idx, fresh)
  local entry = cache[idx]
  if not entry or not entry.ready then return build_menu(idx, fresh) end
  local old = entry.rows

  local same_shape = (#old == #fresh)
  if same_shape then
    for j = 1, #old do
      if old[j].title ~= fresh[j].title or old[j].sep ~= fresh[j].sep then
        same_shape = false
        break
      end
    end
  end

  if not same_shape then return build_menu(idx, fresh) end

  local w, scw = metrics(old)
  for j = 1, #old do
    local o, f = old[j], fresh[j]
    if not o.sep and (o.enabled ~= f.enabled or o.shortcut ~= f.shortcut or o.has_sub ~= f.has_sub) then
      o.enabled, o.shortcut, o.has_sub = f.enabled, f.shortcut, f.has_sub
      local p = row_props(o, w, scw)
      local menu = slot_item(idx)
      o.item:set({
        icon  = { color = p.enabled_color },
        label = { string = p.label_str, color = p.label_color },
        click_script = (o.enabled and menu) and (
          "sketchybar --set " .. menu.name .. " popup.drawing=off; " ..
          HELPER .. " -click " .. idx .. " " .. o.id
        ) or "",
      })
    end
  end
end

-- ── open / close ─────────────────────────────────────────────────────────────
local function close_all_popups()
  if active_menu_idx then
    local menu = slot_item(active_menu_idx)
    if menu then menu:set({ popup = { drawing = false } }) end
  end
  active_menu_idx = nil
  pending_open    = nil
end

local function open_menu_popup(idx)
  local menu = slot_item(idx)
  if not menu then return end

  if active_menu_idx == idx then
    -- trust the real popup state in case an exit event was missed
    local real = menu:query()
    if real and real.popup and real.popup.drawing == "on" then
      close_all_popups()
      return
    end
    active_menu_idx = nil
  end

  if active_menu_idx then
    local prev = slot_item(active_menu_idx)
    if prev then prev:set({ popup = { drawing = false } }) end
  end

  local entry = cache[idx]
  if not (entry and entry.ready) then
    -- data still loading: open as soon as it lands
    pending_open    = idx
    active_menu_idx = nil
    return
  end

  menu:set({ popup = { drawing = true } })
  active_menu_idx = idx
  pending_open    = nil

  -- background refresh of enabled-state/shortcuts (no visible delay)
  local gen = generation
  sbar.exec(HELPER .. " -items " .. idx, function(out)
    if gen ~= generation or not out or out == "" then return end
    refresh_menu(idx, parse_items(out))
  end)
end

-- ── left-side menus (before the notch) ───────────────────────────────────────
local menu_close = sbar.add("item", "custom_menu.close", {
  position = "left",
  drawing  = false,
  icon = {
    string        = "<",
    font          = { style = settings.font.style_map["Bold"], size = 16.0 },
    padding_left  = 10,
    padding_right = 4,
    color         = colors.lavender,
  },
  label        = { drawing = false },
  click_script = "sketchybar --trigger swap_menus_and_spaces",
})

local function make_top_menu(i, font_style)
  local menu = sbar.add("item", "custom_menu." .. i, {
    position      = "left",
    drawing       = false,
    icon          = { drawing = false },
    label         = {
      font          = { style = settings.font.style_map[font_style] },
      padding_left  = 6,
      padding_right = 6,
    },
    click_script  = (i == 1) and "sketchybar --trigger swap_menus_and_spaces" or nil,
    padding_left  = settings.paddings,
    padding_right = settings.paddings,
    popup = {
      align      = "left",
      y_offset   = 2,
      height     = ROW_H,
      background = {
        color         = colors.popup.bg,
        border_color  = colors.popup.border,
        border_width  = 1,
        corner_radius = 8,
      },
    },
  })

  if i > 1 then
    menu:subscribe("mouse.clicked", function()
      local ax = slot_to_ax[i]
      if ax then open_menu_popup(ax) end
    end)

    menu:subscribe("mouse.entered", function()
      local ax = slot_to_ax[i]
      if ax and active_menu_idx and active_menu_idx ~= ax then
        open_menu_popup(ax)
      end
    end)

    -- fires when the pointer leaves the item AND its popup
    menu:subscribe("mouse.exited.global", function()
      local ax = slot_to_ax[i]
      if ax and active_menu_idx == ax then close_all_popups() end
    end)
  end

  menu_items[i] = menu
end

for i = 1, LEFT_SLOTS do make_top_menu(i, i == 1 and "Heavy" or "Semibold") end

-- Spacer bridging across the notch
local menu_notch_spacer = sbar.add("item", "custom_menu.notch_spacer", {
  position   = "left",
  drawing    = false,
  width      = 179,
  background = { drawing = false },
  icon       = { drawing = false },
  label      = { drawing = false },
})

-- right of the notch
for i = LEFT_SLOTS + 1, max_items do make_top_menu(i, "Semibold") end

local left_bracket_items = { "custom_menu.close" }
for i = 1, LEFT_SLOTS do table.insert(left_bracket_items, "custom_menu." .. i) end
island(left_bracket_items, "custom_menus.island")

local right_bracket_items = {}
for i = LEFT_SLOTS + 1, max_items do table.insert(right_bracket_items, "custom_menu." .. i) end
island(right_bracket_items, "custom_menus.island.right")

local menu_padding = sbar.add("item", "custom_menu.padding", {
  position = "left",
  drawing  = false,
  width    = 5,
})

-- ── notch & layout helpers ──────────────────────────────────────────────────
local function has_notch()
  return notch_right > notch_left and notch_right > 0
end

local function notch_width()
  return has_notch() and (notch_right - notch_left) or 0
end

local function init_notch_bounds()
  local displays = sbar.query("displays")
  if type(displays) == "table" and displays[1] and displays[1].frame then
    local f = displays[1].frame
    if math.floor(f.w + 0.5) == 1470 and math.floor(f.h + 0.5) == 956 then
      notch_left, notch_right = 646, 825
      return
    end
  end
  notch_left, notch_right = 0, 0
end

local function refresh_notch_bounds(on_done)
  sbar.exec([[swift -e 'import AppKit; if let s = NSScreen.screens.first, s.auxiliaryTopRightArea.width > 0 { print(Int(round(s.auxiliaryTopLeftArea.maxX - s.frame.minX)), Int(round(s.auxiliaryTopRightArea.minX - s.frame.minX))) } else { print("0 0") }' 2>/dev/null]], function(out)
    local l, r = string.match(out or "", "(%d+)%s+(%d+)")
    if l and r then
      notch_left, notch_right = tonumber(l), tonumber(r)
    end
    if on_done then on_done() end
  end)
end

local function item_rect(item)
  local q = item and item:query()
  local rects = q and q.bounding_rects
  if type(rects) ~= "table" then return nil end
  local r = rects["display-1"]
  if not r then
    for _, v in pairs(rects) do r = v; break end
  end
  if not r or not r.origin or not r.size or r.origin[1] < -9000 then return nil end
  return r.origin[1], r.size[1]
end

local function item_gap()
  return settings.paddings * 2
end

local function compute_spacer_width(left_end_x)
  local target_right_x = notch_right + NOTCH_RIGHT_PAD
  local spacer_x = left_end_x + item_gap()
  return math.max(notch_width(), math.ceil(target_right_x - spacer_x))
end

local function estimate_split(titles)
  local n = #titles
  if not has_notch() then
    return math.min(LEFT_SLOTS + 1, n + 1), 0
  end

  local limit = notch_left - NOTCH_LEFT_PAD
  local gap = item_gap()
  local x = 77
  local close_x, close_w = item_rect(menu_close)
  if close_x and close_w then x = close_x + close_w + gap end

  local split = math.min(LEFT_SLOTS + 1, n + 1)
  local last_left_end = x
  for i = 1, math.min(n, LEFT_SLOTS) do
    local w_est = (i == 1) and (20 + ulen(titles[i]) * 7.2) or (16 + ulen(titles[i]) * 6.5)
    if i > 1 and (x + w_est) > limit then
      split = i
      break
    end
    last_left_end = x + w_est
    x = last_left_end + gap
  end

  local spacer_w = (split <= n) and compute_spacer_width(last_left_end) or 0
  return split, spacer_w
end

local function apply_slot_layout(titles, split, spacer_w)
  slot_to_ax = {}
  ax_to_slot = {}
  local n = #titles
  local left_end = math.min(split - 1, LEFT_SLOTS, n)
  local has_right = (split <= n)

  sbar.begin_config()
  sbar.set('/custom_menu\\.[0-9].*/', { drawing = false })
  menu_padding:set({ drawing = true })
  menu_close:set({ drawing = true })

  for ax = 1, left_end do
    slot_to_ax[ax] = ax
    ax_to_slot[ax] = ax
    menu_items[ax]:set({ label = titles[ax], drawing = true })
  end

  if has_right then
    local slot = LEFT_SLOTS + 1
    for ax = split, n do
      if slot <= max_items then
        slot_to_ax[slot] = ax
        ax_to_slot[ax] = slot
        menu_items[slot]:set({ label = titles[ax], drawing = true })
        slot = slot + 1
      else
        break
      end
    end
  end

  local show_spacer = has_right and has_notch()
  if show_spacer then
    menu_notch_spacer:set({ width = spacer_w, drawing = true })
  else
    menu_notch_spacer:set({ width = 0, drawing = false })
  end
  sbar.end_config()

  compact_mode.set(has_right)
  return left_end, has_right
end

-- ── data loading ─────────────────────────────────────────────────────────────
local function reset_cache()
  generation = generation + 1
  for idx, entry in pairs(cache) do
    if entry.has_rows then
      sbar.remove("/custom_menu\\.row\\." .. idx .. "\\..*/")
    end
  end
  cache        = {}
  slot_to_ax   = {}
  ax_to_slot   = {}
  pending_open = nil
  pending_all  = nil
  layout_ready = false
end

local last_app = nil
local menus_expanded = false

local function schedule_build_all(all, gen)
  local order = {}
  for idx, _ in pairs(all) do
    if ax_to_slot[idx] and idx > 1 then order[#order + 1] = idx end
  end
  table.sort(order)

  -- a menu the user already asked for goes first
  if pending_open then
    for k, idx in ipairs(order) do
      if idx == pending_open then
        table.remove(order, k)
        table.insert(order, 1, idx)
        break
      end
    end
  end

  for k, idx in ipairs(order) do
    sbar.delay((k - 1) * 0.03, function()
      if gen ~= generation or not menus_expanded then return end
      sbar.begin_config()
      build_menu(idx, all[idx])
      sbar.end_config()
      if pending_open == idx then
        pending_open = nil
        open_menu_popup(idx)
      end
    end)
  end
end

local function finish_layout(gen)
  if gen ~= generation or not menus_expanded then return end
  layout_ready = true
  if pending_all then
    local all = pending_all
    pending_all = nil
    schedule_build_all(all, gen)
  end
end

local function settle_notch_layout(titles, split, left_end, spacer_w, gen, recheck_split)
  sbar.delay(0.03, function()
    if gen ~= generation or not menus_expanded then return end
    local n = #titles
    local left_limit = notch_left - NOTCH_LEFT_PAD
    local new_split = split

    if recheck_split then
      for slot = 2, left_end do
        local x, w = item_rect(menu_items[slot])
        if x and w and (x + w) > left_limit then
          new_split = slot
          break
        end
      end

      if new_split == split and split <= LEFT_SLOTS and split <= n then
        local lx, lw = item_rect(menu_items[left_end])
        local _, rw = item_rect(menu_items[LEFT_SLOTS + 1])
        if lx and lw and rw and (lx + lw + item_gap() + rw) <= left_limit then
          new_split = split + 1
        end
      end
    end

    if new_split ~= split then
      local left_tail_end = 0
      if new_split < split then
        local lx, lw = item_rect(menu_items[new_split - 1])
        if lx and lw then left_tail_end = lx + lw end
      else
        local lx, lw = item_rect(menu_items[left_end])
        local _, rw = item_rect(menu_items[LEFT_SLOTS + 1])
        if lx and lw and rw then left_tail_end = lx + lw + item_gap() + rw end
      end

      local next_spacer_w = (new_split <= n) and compute_spacer_width(left_tail_end) or 0
      local new_left_end = apply_slot_layout(titles, new_split, next_spacer_w)
      if new_split <= n then
        settle_notch_layout(titles, new_split, new_left_end, next_spacer_w, gen, false)
      else
        finish_layout(gen)
      end
      return
    end

    if split <= n then
      local rx = item_rect(menu_items[LEFT_SLOTS + 1])
      local target_right_x = notch_right + NOTCH_RIGHT_PAD
      if rx and math.abs(target_right_x - rx) > 1 then
        local adj_w = math.max(notch_width(), math.ceil(spacer_w + (target_right_x - rx)))
        menu_notch_spacer:set({ width = adj_w, drawing = true })
      end
    end

    finish_layout(gen)
  end)
end

local function update_menus(env)
  if not menus_expanded then return end

  local app = env and env.INFO or nil
  if app and app == last_app and next(cache) ~= nil then
    return -- same app re-activated, popups are still valid
  end
  last_app = app

  close_all_popups()
  reset_cache()
  local gen = generation

  -- 1) titles (fast: shows the bar immediately, notch-safe)
  sbar.exec(HELPER .. " -l", function(menus)
    if gen ~= generation or not menus_expanded then return end

    local titles = {}
    for menu in string.gmatch(menus, '[^\r\n]+') do
      if #titles < max_items then
        titles[#titles + 1] = menu
      else
        break
      end
    end

    local split, spacer_w = estimate_split(titles)
    local left_end = apply_slot_layout(titles, split, spacer_w)

    if has_notch() and #titles > 0 then
      settle_notch_layout(titles, split, left_end, spacer_w, gen, true)
    else
      finish_layout(gen)
    end
  end)

  -- 2) every menu's items in one go; popups wait until notch layout is settled
  sbar.exec(HELPER .. " -all", function(out)
    if gen ~= generation or not menus_expanded or not out or out == "" then return end
    local all = parse_all(out)
    if not layout_ready then
      pending_all = all
      return
    end
    schedule_build_all(all, gen)
  end)
end

init_notch_bounds()
refresh_notch_bounds()

menu_watcher:subscribe("front_app_switched", update_menus)

space_menu_swap:subscribe("display_change", function()
  refresh_notch_bounds(function()
    if menus_expanded then
      last_app = nil
      update_menus()
    end
  end)
end)

space_menu_swap:subscribe("swap_menus_and_spaces", function()
  close_all_popups()
  local is_open = menus_expanded or (menu_items[1]:query().geometry.drawing == "on")
  if is_open then
    menus_expanded = false
    generation = generation + 1
    last_app = nil
    pending_all = nil
    layout_ready = false
    menu_watcher:set({ updates = false })
    sbar.set("/custom_menu\\..*/", { drawing = false })
    sbar.set("/space\\..*/", { drawing = true })
    sbar.set("front_app", { drawing = true })
    compact_mode.set(false)
  else
    menus_expanded = true
    menu_watcher:set({ updates = true })
    sbar.set("/space\\..*/", { drawing = false })
    sbar.set("front_app", { drawing = false })
    update_menus()
  end
end)

-- Ensure initial hidden state on load/reload
sbar.set("/custom_menu\\..*/", { drawing = false })

return menu_watcher
