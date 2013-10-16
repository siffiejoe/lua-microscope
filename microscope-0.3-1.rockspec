package = "microscope"
version = "0.3-1"
source = {
  url = "${SRCURL}"
}
description = {
  summary = "Creates images of arbitrary Lua values using GraphViz",
  detailed = [[
    This Lua module dumps arbitrarily complex Lua datastructures as
    GraphViz .dot-files that can be transformed into a variety of
    image formats.
  ]],
  homepage = "${HPURL}",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1, <= 5.2"
}
build = {
  type = "builtin",
  modules = {
    microscope = "src/microscope.lua"
  }
}

