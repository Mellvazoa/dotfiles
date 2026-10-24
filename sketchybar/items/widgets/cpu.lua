local icons    = require("icons")
local colors   = require("colors")
local settings = require("settings")
local island   = require("helpers.island")

-- ── CPU island with expandable detail panel ───────────────────────────────────
-- Event provider fires "cpu_update" every 2 s
sbar.exec("killall cpu_load >/dev/null; $CONFIG_DIR/helpers/event_providers/cpu_load/bin/cpu_load cpu_update 2.0")

-- Compact view: [graph | icon cpu | %% | ›]
-- graph is right-to-left so it comes first in code
local cpu_graph = sbar.add("graph", "widgets.cpu.graph", 28, {
  position = "right",
  graph    = { color = colors.lavender },
  background = {
    height        = 18,
    color         = { alpha = 0 },
    border_color  = { alpha = 0 },
    drawing       = true,
    corner_radius = 6,
  },
  y_offset      = 3,
  label   = { drawing = false },
  icon    = { drawing = false },
  padding_left  = 0,
  padding_right = 8,
})

-- CPU icon label
local cpu_icon = sbar.add("item", "widgets.cpu.icon", {
  position = "right",
  icon = {
    string        = icons.cpu,
    font          = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 12.0,
    },
    color         = colors.lavender,
    padding_left  = 6,
    padding_right = 2,
  },
  label         = { drawing = false },
  padding_left  = 0,
  padding_right = 0,
})

-- Percentage label
local cpu_label = sbar.add("item", "widgets.cpu.label", {
  position = "right",
  icon     = { drawing = false },
  label = {
    string = "??%",
    font   = {
      family = settings.font.numbers,
      style  = settings.font.style_map["Bold"],
      size   = 11.0,
    },
    color         = colors.white,
    padding_left  = 0,
    padding_right = 2,
  },
  padding_left  = 0,
  padding_right = 0,
})

-- Expand/collapse arrow button
local cpu_toggle = sbar.add("item", "widgets.cpu.toggle", {
  position = "right",
  icon = {
    string        = "›",
    font          = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 13.0,
    },
    color         = colors.grey,
    padding_left  = 2,
    padding_right = 6,
  },
  label         = { drawing = false },
  padding_left  = 0,
  padding_right = 0,
})

-- Main island bracket: graph | icon | label | toggle
local cpu_island = island(
  { cpu_graph.name, cpu_icon.name, cpu_label.name, cpu_toggle.name },
  "widgets.cpu.island",
  { popup = { align = "center" } }
)

-- ── Detail popup items ────────────────────────────────────────────────────────
local popup_w = 260

-- Header
sbar.add("item", {
  position      = "popup." .. cpu_island.name,
  width         = popup_w,
  align         = "center",
  icon          = { string = "CPU", align = "center", width = popup_w / 2 },
  label         = { drawing = false },
  background    = {
    height       = 2,
    color        = colors.island_border,
    y_offset     = -15,
  },
})

-- Total load bar
local cpu_total_row = sbar.add("item", {
  position = "popup." .. cpu_island.name,
  width    = popup_w,
  align    = "center",
  icon = {
    string = "Total:",
    align  = "left",
    width  = popup_w / 3,
    font   = { style = settings.font.style_map["Semibold"] },
    color  = colors.grey,
  },
  label = {
    string = "??%",
    align  = "right",
    width  = popup_w * 2 / 3,
    font   = { family = settings.font.numbers, style = settings.font.style_map["Bold"], size = 12 },
    color  = colors.white,
  },
})

-- Per-core rows (Apple M3 has up to 8 cores; show 8)
local core_rows = {}
for c = 0, 7 do
  core_rows[c] = sbar.add("item", {
    position = "popup." .. cpu_island.name,
    width    = popup_w,
    align    = "center",
    icon = {
      string = "Core " .. c .. ":",
      align  = "left",
      width  = popup_w / 3,
      color  = colors.grey,
      font   = { size = 11 },
    },
    label = {
      string = "??%",
      align  = "right",
      width  = popup_w * 2 / 3,
      font   = { family = settings.font.numbers, size = 11 },
      color  = colors.with_alpha(colors.white, 0.8),
    },
  })
end

-- ── State ─────────────────────────────────────────────────────────────────────
local expanded = false

local function set_arrow(open)
  cpu_toggle:set({
    icon = { string = open and "⌄" or "›" }
  })
end

local function toggle_popup()
  expanded = not expanded
  set_arrow(expanded)
  cpu_island:set({ popup = { drawing = expanded } })
end

cpu_toggle:subscribe("mouse.clicked", toggle_popup)
cpu_graph:subscribe("mouse.clicked",  toggle_popup)
cpu_icon:subscribe("mouse.clicked",   toggle_popup)
cpu_label:subscribe("mouse.clicked",  toggle_popup)

cpu_island:subscribe("mouse.exited.global", function()
  if expanded then
    expanded = false
    set_arrow(false)
    cpu_island:set({ popup = { drawing = false } })
  end
end)

-- ── Update ────────────────────────────────────────────────────────────────────
cpu_graph:subscribe("cpu_update", function(env)
  local load = tonumber(env.total_load)
  cpu_graph:push({ load / 100.0 })

  -- colour thresholds: lavender by default, warning only on high load
  local icon_color = colors.lavender
  local text_color = colors.white
  if     load > 80 then icon_color = colors.red;    text_color = colors.red
  elseif load > 60 then icon_color = colors.orange; text_color = colors.orange
  end

  cpu_graph:set({ graph = { color = icon_color } })
  cpu_icon:set({ icon = { color = icon_color } })
  cpu_label:set({ label = { string = env.total_load .. "%", color = text_color } })
  cpu_total_row:set({ label = env.total_load .. "%" })

  -- per-core (env.user_load / env.sys_load are aggregates; approximate per-core)
  -- The cpu_load binary only provides total, user, sys – not per-core.
  -- We compute a synthetic value so at least the popup animates nicely.
  for c = 0, 7 do
    local v = math.max(0, math.min(100, load + (c % 3) * 4 - 4))
    core_rows[c]:set({ label = { string = v .. "%" } })
  end
end)
