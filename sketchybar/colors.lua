return {
  black       = 0xff14172f,
  white       = 0xfff6f2f4,
  red         = 0xfffc5d7c,
  green       = 0xffa3e49b,
  blue        = 0xff9ccdfb,
  yellow      = 0xfff6df94,
  orange      = 0xfffca07a,
  magenta     = 0xfffa89af,
  grey        = 0xff8a8eb5,
  transparent = 0x00000000,

  -- Dynamic wallpaper palette (accent: #fa89af)
  lavender       = 0xfffa89af,
  lavender_light = 0xfff8bdd1,
  lavender_dim   = 0xfff74480,
  lilac          = 0xfff98075,
  arch           = 0xfffa89af,
  arch_dark      = 0xff41242e,

  -- Island pill background
  island         = 0xd9201217,
  island_border  = 0x44fa89af,

  bar = {
    bg     = 0x00000000,
    border = 0x00000000,
  },
  popup = {
    bg     = 0xf2201217,
    border = 0x55fa89af,
  },
  bg1 = 0xff2d1920,
  bg2 = 0xff41242e,

  with_alpha = function(color, alpha)
    if alpha > 1.0 or alpha < 0.0 then return color end
    return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
  end,
}