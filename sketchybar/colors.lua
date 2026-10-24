return {
  black       = 0xff14172f,
  white       = 0xfff0edfc,
  red         = 0xfffc5d7c,
  green       = 0xffa3e49b,
  blue        = 0xff9ccdfb,
  yellow      = 0xfff6df94,
  orange      = 0xfffca07a,
  magenta     = 0xffc8b4fa,
  grey        = 0xff8a8eb5,
  transparent = 0x00000000,

  -- Soft lavender & pastel lilac anime dusk palette
  lavender       = 0xffc8b4fa,
  lavender_light = 0xffe4d2fd,
  lavender_dim   = 0xffaba0f5,
  lilac          = 0xff928dfb,
  arch           = 0xffc8b4fa,  -- Used across items for active accents
  arch_dark      = 0xff3b3560,

  -- Island pill background: deep translucent twilight with subtle lavender border
  island         = 0xd9131630,
  island_border  = 0x44c8b4fa,

  bar = {
    bg     = 0x00000000,  -- fully transparent
    border = 0x00000000,
  },
  popup = {
    bg     = 0xf2131630,
    border = 0x55c8b4fa,
  },
  bg1 = 0xff1c203f,
  bg2 = 0xff292e59,

  with_alpha = function(color, alpha)
    if alpha > 1.0 or alpha < 0.0 then return color end
    return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
  end,
}
