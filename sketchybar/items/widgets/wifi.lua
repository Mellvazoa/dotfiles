local icons    = require("icons")
local colors   = require("colors")
local settings = require("settings")
local island   = require("helpers.island")

-- ── Wi-Fi island (compact: icon only; expanded: speeds + network info) ────────
sbar.exec("killall network_load >/dev/null; $CONFIG_DIR/helpers/event_providers/network_load/bin/network_load en0 network_update 2.0")

local popup_w = 260

-- Compact: wifi signal icon
local wifi_icon = sbar.add("item", "widgets.wifi.icon", {
  position = "right",
  label    = { drawing = false },
  icon = {
    string        = icons.wifi.connected,
    font          = {
      family = settings.font.text,
      style  = settings.font.style_map["Bold"],
      size   = 14.0,
    },
    color         = colors.lavender,
    padding_left  = 8,
    padding_right = 8,
  },
  padding_left  = 0,
  padding_right = 0,
})

local wifi_island = island({ wifi_icon.name }, "widgets.wifi.island", {
  popup = { align = "center", height = 32 }
})

-- ── Popup: speed rows ─────────────────────────────────────────────────────────
sbar.add("item", {
  position  = "popup." .. wifi_island.name,
  width     = popup_w,
  align     = "center",
  icon      = { string = "Wi-Fi", align = "center", width = popup_w / 2 },
  label     = { drawing = false },
  background = { height = 2, color = colors.island_border, y_offset = -15 },
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
  icon  = { string = "IP:", align = "left", width = popup_w / 3, color = colors.grey, font = { size = 11 } },
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

-- ── Network speed update ──────────────────────────────────────────────────────
wifi_icon:subscribe("network_update", function(env)
  local up_color   = (env.upload   == "000 Bps") and colors.grey or colors.red
  local down_color = (env.download == "000 Bps") and colors.grey or colors.blue
  wifi_up_row:set({   label = { string = env.upload,   color = up_color   } })
  wifi_down_row:set({ label = { string = env.download, color = down_color } })
end)

-- ── Connectivity icon update ──────────────────────────────────────────────────
wifi_icon:subscribe({ "wifi_change", "system_woke" }, function()
  sbar.exec("ipconfig getifaddr en0", function(ip)
    local connected = ip ~= ""
    wifi_icon:set({
      icon = {
        string = connected and icons.wifi.connected or icons.wifi.disconnected,
        color  = connected and colors.lavender or colors.red,
      },
    })
  end)
end)

-- ── Popup toggle ──────────────────────────────────────────────────────────────
local function hide()
  wifi_island:set({ popup = { drawing = false } })
end

local function toggle()
  local open = wifi_island:query().popup.drawing == "off"
  wifi_island:set({ popup = { drawing = open } })
  if open then
    sbar.exec("ipconfig getsummary en0 | awk -F ' SSID : '  '/ SSID : / {print $2}'", function(r)
      ssid_row:set({ label = r })
    end)
    sbar.exec("ipconfig getifaddr en0", function(r)
      ip_row:set({ label = r ~= "" and r or "N/A" })
    end)
    sbar.exec("curl -s --max-time 2 ifconfig.me", function(r)
      pub_ip_row:set({ label = r ~= "" and r or "N/A" })
    end)
    sbar.exec("ifconfig | awk '/^[a-z]/ {iface=$1} /inet / {if(match(iface, \"^utun\")) {print $2; exit}}'", function(r)
      vpn_ip_row:set({ label = r ~= "" and r or "N/A" })
    end)
  end
end

wifi_icon:subscribe("mouse.clicked",        toggle)
wifi_island:subscribe("mouse.exited.global", hide)
