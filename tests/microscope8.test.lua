#!/usr/bin/lua

package.path = [[../src/?.lua;]] .. package.path
local todot = require( "microscope" )

todot( "example9.dot", package, "environments", todot, _G )

