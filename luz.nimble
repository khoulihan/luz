# Package

version       = "0.1.0"
author        = "Kevin Houlihan"
description   = "Displays information about electricity rate bands"
license       = "BSD-3-Clause"
srcDir        = "src"
bin           = @["luz"]


# Dependencies

requires "nim >= 1.6.6"
requires "docopt >= 0.6.8"
requires "parsetoml >= 0.6.0"
