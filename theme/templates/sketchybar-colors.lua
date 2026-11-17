return {
  black       = 0xff{{island_hex}},
  white       = 0xff{{fg_hex}},
  red         = 0xff{{red_hex}},
  green       = 0xff{{green_hex}},
  blue        = 0xff{{blue_hex}},
  yellow      = 0xff{{yellow_hex}},
  orange      = 0xff{{orange_hex}},
  magenta     = 0xff{{accent_hex}},
  grey        = 0xff{{fg_muted_hex}},
  transparent = 0x00000000,

  -- Theme palette ({{theme_label}}, accent: {{accent}})
  lavender       = 0xff{{accent_hex}},
  lavender_light = 0xff{{accent_light_hex}},
  lavender_dim   = 0xff{{accent_dim_hex}},
  lilac          = 0xff{{lilac_hex}},
  arch           = 0xff{{accent_hex}},
  arch_dark      = 0xff{{bg2_hex}},

  -- Island pill background
  island         = 0xd9{{island_hex}},
  island_border  = 0x44{{accent_hex}},

  bar = {
    bg     = 0x00000000,
    border = 0x00000000,
  },
  popup = {
    bg     = 0xf2{{island_hex}},
    border = 0x55{{accent_hex}},
  },
  bg1 = 0xff{{bg1_hex}},
  bg2 = 0xff{{bg2_hex}},

  with_alpha = function(color, alpha)
    if alpha > 1.0 or alpha < 0.0 then return color end
    return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
  end,
}
