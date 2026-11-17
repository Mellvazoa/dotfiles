return {
  black       = 0xff201412,
  white       = 0xfff6f3f2,
  red         = 0xfffc5d7c,
  green       = 0xffa3e49b,
  blue        = 0xff9ccdfb,
  yellow      = 0xfff6df94,
  orange      = 0xfffca07a,
  magenta     = 0xfffa9a89,
  grey        = 0xfff76044,
  transparent = 0x00000000,

  -- Theme palette (chainsaw_man_p9jx2e, accent: #fa9a89)
  lavender       = 0xfffa9a89,
  lavender_light = 0xfff8c6bd,
  lavender_dim   = 0xfff76044,
  lilac          = 0xfff9c075,
  arch           = 0xfffa9a89,
  arch_dark      = 0xff412924,

  -- Island pill background
  island         = 0xd9201412,
  island_border  = 0x44fa9a89,

  bar = {
    bg     = 0x00000000,
    border = 0x00000000,
  },
  popup = {
    bg     = 0xf2201412,
    border = 0x55fa9a89,
  },
  bg1 = 0xff2d1c19,
  bg2 = 0xff412924,

  with_alpha = function(color, alpha)
    if alpha > 1.0 or alpha < 0.0 then return color end
    return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
  end,
}
