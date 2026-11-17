local icons        = require("icons")
local colors       = require("colors")
local settings     = require("settings")
local island       = require("helpers.island")
local compact_mode = require("helpers.compact_mode")

-- ── Wi-Fi island (compact: icon + ping latency; expanded: speeds + ping + info) ─
sbar.exec("killall network_load >/dev/null 2>&1; exec $CONFIG_DIR/helpers/event_providers/network_load/bin/network_load en0 network_update 2.0")

local popup_w = 260

-- Compact: wifi signal icon + ping latency
local wifi_icon = sbar.add("item", "widgets.wifi.icon", {
  position = "right",
  icon = {
    string        = icons.wifi.connected,
    font          = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 13.0,
    },
    color         = colors.lavender,
    padding_left  = 8,
    padding_right = 4,
  },
  label = {
    string        = "-- ms",
    font          = {
      family = settings.font.numbers,
      style  = settings.font.style_map["Bold"],
      size   = 11.0,
    },
    color         = colors.white,
    padding_left  = 0,
    padding_right = 8,
  },
  update_freq   = 60, -- update ping every minute (and instantly on wifi_change/click)
  padding_left  = 0,
  padding_right = 0,
})

local wifi_island = island({ wifi_icon.name }, "widgets.wifi.island", {
  popup = { align = "center", height = 32 }
})

-- ── Popup items ───────────────────────────────────────────────────────────────
sbar.add("item", {
  position  = "popup." .. wifi_island.name,
  width     = popup_w,
  align     = "center",
  icon      = { string = "Wi-Fi & Network", align = "center", width = popup_w / 2 },
  label     = { drawing = false },
  background = { height = 2, color = colors.island_border, y_offset = -15 },
})

local ping_row = sbar.add("item", {
  position = "popup." .. wifi_island.name,
  width    = popup_w,
  icon = {
    string = "󰛳 Ping (DNS):",
    align  = "left",
    width  = popup_w / 2 + 10,
    color  = colors.grey,
    font   = { size = 11 },
  },
  label = {
    string = "-- ms",
    align  = "right",
    width  = popup_w / 2 - 10,
    color  = colors.lavender,
    font   = { family = settings.font.numbers, size = 11 },
  },
})

local wifi_up_row = sbar.add("item", {
  position = "popup." .. wifi_island.name,
  width    = popup_w,
  icon = {
    string = icons.wifi.upload .. " Upload:",
    align  = "left",
    width  = popup_w / 2,
    color  = colors.grey,
    font   = { size = 11 },
  },
  label = {
    string = "???",
    align  = "right",
    width  = popup_w / 2,
    color  = colors.red,
    font   = { family = settings.font.numbers, size = 11 },
  },
})

local wifi_down_row = sbar.add("item", {
  position = "popup." .. wifi_island.name,
  width    = popup_w,
  icon = {
    string = icons.wifi.download .. " Download:",
    align  = "left",
    width  = popup_w / 2,
    color  = colors.grey,
    font   = { size = 11 },
  },
  label = {
    string = "???",
    align  = "right",
    width  = popup_w / 2,
    color  = colors.blue,
    font   = { family = settings.font.numbers, size = 11 },
  },
})

local ssid_row = sbar.add("item", {
  position = "popup." .. wifi_island.name,
  width    = popup_w,
  icon = { string = "SSID:", align = "left", width = popup_w / 3, color = colors.grey, font = { size = 11 } },
  label = { string = "???", align = "right", width = popup_w * 2 / 3, max_chars = 20 },
})

local ip_row = sbar.add("item", {
  position = "popup." .. wifi_island.name,
  width    = popup_w,
  icon  = { string = "LAN IP:", align = "left", width = popup_w / 3, color = colors.grey, font = { size = 11 } },
  label = { string = "???", align = "right", width = popup_w * 2 / 3 },
})

local pub_ip_row = sbar.add("item", {
  position = "popup." .. wifi_island.name,
  width    = popup_w,
  icon  = { string = "Pub IP:", align = "left", width = popup_w / 3, color = colors.grey, font = { size = 11 } },
  label = { string = "???", align = "right", width = popup_w * 2 / 3 },
})

local vpn_ip_row = sbar.add("item", {
  position = "popup." .. wifi_island.name,
  width    = popup_w,
  icon  = { string = "VPN IP:", align = "left", width = popup_w / 3, color = colors.grey, font = { size = 11 } },
  label = { string = "???", align = "right", width = popup_w * 2 / 3 },
})

-- Separator before Choose Network button
sbar.add("item", {
  position  = "popup." .. wifi_island.name,
  width     = popup_w,
  icon      = { drawing = false },
  label     = { drawing = false },
  background = { height = 1, color = colors.island_border, y_offset = 0 },
})

local choose_net_btn = sbar.add("item", {
  position = "popup." .. wifi_island.name,
  width    = popup_w,
  icon     = { string = "󰤨  Choose Wi-Fi Network...", align = "center", width = popup_w, color = colors.lavender, font = { size = 11 } },
  label    = { drawing = false },
})

-- ── Network speed update ──────────────────────────────────────────────────────
wifi_icon:subscribe("network_update", function(env)
  local up_color   = (env.upload   == "000 Bps") and colors.grey or colors.red
  local down_color = (env.download == "000 Bps") and colors.grey or colors.blue
  wifi_up_row:set({   label = { string = env.upload,   color = up_color   } })
  wifi_down_row:set({ label = { string = env.download, color = down_color } })
end)

-- ── Ping & connectivity update ────────────────────────────────────────────────
-- Fallback ping across Yandex (77.88.8.8, extremely reliable in RU/CIS), Cloudflare (1.1.1.1), and Google (8.8.8.8)
local ping_cmd = [[ping -c 1 -W 800 77.88.8.8 2>&1 | awk -F '/' 'END {if ($5 ~ /^[0-9]+(\.[0-9]+)?$/) {printf "%d", $5; exit 0} else exit 1}' || ping -c 1 -W 800 1.1.1.1 2>&1 | awk -F '/' 'END {if ($5 ~ /^[0-9]+(\.[0-9]+)?$/) {printf "%d", $5; exit 0} else exit 1}' || ping -c 1 -W 800 8.8.8.8 2>&1 | awk -F '/' 'END {if ($5 ~ /^[0-9]+(\.[0-9]+)?$/) printf "%d", $5; else print ""}']]

local wifi_status_cmd = [[ipconfig getsummary en0 2>/dev/null | awk -F 'LinkStatusActive : ' '/LinkStatusActive : / {print $2}']]

local last_wifi_icon  = icons.wifi.connected
local last_icon_color = colors.lavender
local last_label_text = "-- ms"
local last_val_color  = colors.white

local function render_wifi()
  if compact_mode.is_compact then
    wifi_icon:set({
      icon  = {
        string        = last_wifi_icon,
        color         = last_icon_color,
        drawing       = true,
        padding_left  = 8,
        padding_right = 8,
      },
      label = {
        drawing       = false,
      },
    })
  else
    wifi_icon:set({
      icon  = {
        string        = last_wifi_icon,
        color         = last_icon_color,
        drawing       = true,
        padding_left  = 8,
        padding_right = 4,
      },
      label = {
        string        = last_label_text,
        color         = last_val_color,
        drawing       = true,
        padding_left  = 0,
        padding_right = 8,
      },
    })
  end
end

compact_mode.on_change(function()
  render_wifi()
end)

local function update_network()
  sbar.exec(wifi_status_cmd, function(link_status)
    local is_connected = link_status and (link_status:match("TRUE") ~= nil)

    if not is_connected then
      last_wifi_icon  = icons.wifi.disconnected
      last_icon_color = colors.red
      last_label_text = "--"
      last_val_color  = colors.grey

      render_wifi()
      ping_row:set({ label = { string = "Disconnected", color = colors.red } })
      return
    end

    -- Wi-Fi is physically connected to the access point:
    sbar.exec(ping_cmd, function(res)
      local ms = tonumber(res)
      if ms then
        local label_text = ms .. " ms"
        local val_color = colors.white
        local icon_color = colors.lavender
        if ms > 150 then
          val_color = colors.red
          icon_color = colors.red
        elseif ms > 60 then
          val_color = colors.orange
          icon_color = colors.orange
        end

        last_wifi_icon  = icons.wifi.connected
        last_icon_color = icon_color
        last_label_text = label_text
        last_val_color  = val_color

        render_wifi()
        ping_row:set({ label = { string = label_text, color = val_color } })
      else
        -- Connected to Wi-Fi, but internet ping did not respond
        last_wifi_icon  = icons.wifi.connected
        last_icon_color = colors.orange
        last_label_text = "? ms"
        last_val_color  = colors.orange

        render_wifi()
        ping_row:set({ label = { string = "No Ping", color = colors.orange } })
      end
    end)
  end)
end

wifi_icon:subscribe({ "routine", "forced", "wifi_change", "system_woke" }, function()
  update_network()
end)

-- ── Popup toggle ──────────────────────────────────────────────────────────────
local function hide()
  wifi_island:set({ popup = { drawing = false } })
end

local function toggle()
  local open = wifi_island:query().popup.drawing == "off"
  wifi_island:set({ popup = { drawing = open } })
  if open then
    update_network()
    sbar.exec("$CONFIG_DIR/helpers/net_info.py en0", function(r)
      if r and r ~= "" then
        local parts = {}
        for part in string.gmatch(r, "[^|\r\n]+") do
          table.insert(parts, part)
        end
        local ssid   = parts[1] or "N/A"
        local lan_ip = parts[2] or "N/A"
        local pub_ip = parts[3] or "N/A"
        local vpn_ip = parts[4] or "Disconnected"

        ssid_row:set({ label = { string = ssid, color = colors.white } })
        ip_row:set({ label = { string = lan_ip, color = colors.white } })
        pub_ip_row:set({ label = { string = pub_ip, color = colors.white } })
        
        local vpn_color = (vpn_ip == "Disconnected" or vpn_ip == "N/A") and colors.grey or colors.green
        vpn_ip_row:set({ label = { string = vpn_ip, color = vpn_color } })
      end
    end)
  end
end

wifi_icon:subscribe("mouse.clicked", toggle)
wifi_island:subscribe("mouse.exited.global", hide)

local function open_wifi_menu()
  hide()
  sbar.exec("python3 ~/.config/rofi/wifi_menu.py")
end

choose_net_btn:subscribe("mouse.clicked", open_wifi_menu)
ssid_row:subscribe("mouse.clicked", open_wifi_menu)
