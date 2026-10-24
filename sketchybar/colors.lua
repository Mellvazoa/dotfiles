return {
  black       = 0xff14172f,
  white       = 0xfff6f3f2,
  red         = 0xfffc5d7c,
  green       = 0xffa3e49b,
  blue        = 0xff9ccdfb,
  yellow      = 0xfff6df94,
  orange      = 0xfffca07a,
  magenta     = 0xfffaa889,
  grey        = 0xff8a8eb5,
  transparent = 0x00000000,

  -- Dynamic wallpaper palette (accent: #faa889)
  lavender       = 0xfffaa889,
  lavender_light = 0xfff8cdbd,
  lavender_dim   = 0xfff77544,
  lilac          = 0xfff9d075,
  arch           = 0xfffaa889,
  arch_dark      = 0xff412c24,

  -- Island pill background
  island         = 0xd9201612,
  island_border  = 0x44faa889,

  bar = {
    bg     = 0x00000000,
    border = 0x00000000,
  },
  popup = {
    bg     = 0xf2201612,
    border = 0x55faa889,
  },
  bg1 = 0xff2d1f19,
  bg2 = 0xff412c24,

  with_alpha = function(color, alpha)
    if alpha > 1.0 or alpha < 0.0 then return color end
    return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
  end,
}