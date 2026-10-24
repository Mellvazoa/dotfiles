return {
  paddings       = 4,
  group_paddings = 6,

  icons = "NerdFont",

  -- Island pill geometry
  pill = {
    height        = 30,
    corner_radius = 10,
    border_width  = 1,
  },

  -- MacBook Air M3 13" notch: the notch occupies roughly the middle 230 px.
  -- Items placed at "center" will be shifted if they would overlap this region.
  notch_width = 230,

  font = require("helpers.default_font"),
}
