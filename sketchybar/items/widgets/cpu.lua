local icons        = require("icons")
local colors       = require("colors")
local settings     = require("settings")
local island       = require("helpers.island")
local compact_mode = require("helpers.compact_mode")

-- ── CPU island with temperature and expandable detail panel ───────────────────
-- Event provider fires "cpu_update" every 2 s
sbar.exec("killall cpu_load >/dev/null 2>&1; exec $CONFIG_DIR/helpers/event_providers/cpu_load/bin/cpu_load cpu_update 2.0")

-- Temperature & SoC power streaming provider (macmon for Apple Silicon)
sbar.exec("pkill -f temp_load.py >/dev/null 2>&1; python3 $CONFIG_DIR/helpers/event_providers/temp_load/temp_load.py temp_update 2500 &")

-- ── Compact view items (ordered right-to-left in code) ────────────────────────
-- 1. Graph (far right)
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

-- 2. CPU Temperature (between label and graph)
local cpu_temp = sbar.add("item", "widgets.cpu.temp", {
  position = "right",
  icon = {
    string        = "󰔏",
    font          = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 11.0,
    },
    color         = colors.lavender,
    padding_left  = 3,
    padding_right = 1,
  },
  label = {
    string        = "--°",
    font   = {
      family = settings.font.numbers,
      style  = settings.font.style_map["Bold"],
      size   = 11.0,
    },
    color         = colors.white,
    padding_left  = 0,
    padding_right = 4,
  },
  padding_left  = 0,
  padding_right = 0,
})

-- 3. Percentage label
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

-- 4. CPU icon
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

-- 5. Expand/collapse arrow button (far left)
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

-- Main island bracket: toggle | icon | label | temp | graph
local cpu_island = island(
  { cpu_graph.name, cpu_temp.name, cpu_label.name, cpu_icon.name, cpu_toggle.name },
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
  icon          = { string = "CPU & SoC", align = "center", width = popup_w / 2 },
  label         = { drawing = false },
  background    = {
    height       = 2,
    color        = colors.island_border,
    y_offset     = -15,
  },
})

-- Total load row
local cpu_total_row = sbar.add("item", {
  position = "popup." .. cpu_island.name,
  width    = popup_w,
  align    = "center",
  icon = {
    string = "Total Load:",
    align  = "left",
    width  = popup_w / 2,
    font   = { style = settings.font.style_map["Semibold"], size = 11 },
    color  = colors.grey,
  },
  label = {
    string = "??%",
    align  = "right",
    width  = popup_w / 2,
    font   = { family = settings.font.numbers, style = settings.font.style_map["Bold"], size = 11 },
    color  = colors.white,
  },
})

-- CPU Temperature row
local cpu_temp_row = sbar.add("item", {
  position = "popup." .. cpu_island.name,
  width    = popup_w,
  align    = "center",
  icon = {
    string = "󰔏 CPU Temp:",
    align  = "left",
    width  = popup_w / 2,
    color  = colors.grey,
    font   = { size = 11 },
  },
  label = {
    string = "--°C",
    align  = "right",
    width  = popup_w / 2,
    font   = { family = settings.font.numbers, style = settings.font.style_map["Bold"], size = 11 },
    color  = colors.lavender,
  },
})

-- GPU Temperature row
local gpu_temp_row = sbar.add("item", {
  position = "popup." .. cpu_island.name,
  width    = popup_w,
  align    = "center",
  icon = {
    string = "󰢮 GPU Temp:",
    align  = "left",
    width  = popup_w / 2,
    color  = colors.grey,
    font   = { size = 11 },
  },
  label = {
    string = "--°C",
    align  = "right",
    width  = popup_w / 2,
    font   = { family = settings.font.numbers, style = settings.font.style_map["Bold"], size = 11 },
    color  = colors.blue,
  },
})

-- Power consumption row
local sys_pwr_row = sbar.add("item", {
  position = "popup." .. cpu_island.name,
  width    = popup_w,
  align    = "center",
  icon = {
    string = "⚡ SoC Power:",
    align  = "left",
    width  = popup_w / 2,
    color  = colors.grey,
    font   = { size = 11 },
  },
  label = {
    string = "-- W",
    align  = "right",
    width  = popup_w / 2,
    font   = { family = settings.font.numbers, style = settings.font.style_map["Bold"], size = 11 },
    color  = colors.green,
  },
})

-- Divider
sbar.add("item", {
  position   = "popup." .. cpu_island.name,
  width      = popup_w,
  icon       = { drawing = false },
  label      = { drawing = false },
  background = {
    height       = 1,
    color        = colors.island_border,
    y_offset     = -4,
  },
})

-- Per-core rows (Apple M3: 4 Performance + 4 Efficiency cores)
local core_rows = {}
for c = 0, 7 do
  local core_label = (c < 4) and ("E-Core " .. c .. ":") or ("P-Core " .. (c - 4) .. ":")
  core_rows[c] = sbar.add("item", {
    position = "popup." .. cpu_island.name,
    width    = popup_w,
    align    = "center",
    icon = {
      string = core_label,
      align  = "left",
      width  = popup_w / 2,
      color  = colors.grey,
      font   = { size = 11 },
    },
    label = {
      string = "??%",
      align  = "right",
      width  = popup_w / 2,
      font   = { family = settings.font.numbers, size = 11 },
      color  = colors.with_alpha(colors.white, 0.8),
    },
  })
end

-- ── State & Click handlers ────────────────────────────────────────────────────
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
cpu_temp:subscribe("mouse.clicked",   toggle_popup)

cpu_island:subscribe("mouse.exited.global", function()
  if expanded then
    expanded = false
    set_arrow(false)
    cpu_island:set({ popup = { drawing = false } })
  end
end)

local function render_cpu_compact()
  if compact_mode.is_compact then
    cpu_graph:set({ drawing = false })
    cpu_temp:set({ label = { padding_right = 8 } })
  else
    cpu_graph:set({ drawing = true, padding_right = 8 })
    cpu_temp:set({ label = { padding_right = 4 } })
  end
end

compact_mode.on_change(function()
  render_cpu_compact()
end)

-- ── Update Subscriptions ──────────────────────────────────────────────────────
-- CPU Load update
cpu_graph:subscribe("cpu_update", function(env)
  local load = math.max(0, math.min(100, tonumber(env.total_load) or 0))
  cpu_graph:push({ load / 100.0 })

  local icon_color = colors.lavender
  local text_color = colors.white
  if     load > 80 then icon_color = colors.red;    text_color = colors.red
  elseif load > 60 then icon_color = colors.orange; text_color = colors.orange
  end

  cpu_graph:set({
    graph   = { color = icon_color },
    drawing = not compact_mode.is_compact,
  })
  cpu_icon:set({ icon = { color = icon_color } })
  cpu_label:set({ label = { string = string.format("%02d%%", load), color = text_color } })
  cpu_total_row:set({ label = string.format("%02d%%", load) })

  for c = 0, 7 do
    local v = math.max(0, math.min(100, load + (c % 3) * 4 - 4))
    core_rows[c]:set({ label = { string = v .. "%" } })
  end
end)

-- Temperature & Power update (from temp_load event provider)
cpu_temp:subscribe("temp_update", function(env)
  local t = tonumber(env.cpu_temp) or 0
  local color = colors.white
  local icon_color = colors.lavender
  if t > 82 then
    color = colors.red
    icon_color = colors.red
  elseif t > 68 then
    color = colors.orange
    icon_color = colors.orange
  end

  cpu_temp:set({
    icon  = { color = icon_color },
    label = { string = t .. "°", color = color, padding_right = compact_mode.is_compact and 8 or 4 },
  })

  cpu_temp_row:set({ label = t .. "°C" })
  if env.gpu_temp then
    gpu_temp_row:set({ label = env.gpu_temp .. "°C" })
  end
  if env.sys_power then
    sys_pwr_row:set({ label = env.sys_power .. " W" })
  end
end)
