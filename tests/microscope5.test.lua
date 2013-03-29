#!/usr/bin/lua

package.path = [[../src/?.lua;]] .. package.path

local function f1() end
local function f2()
  return f2()
end
local t1 = { func1 = f1, func2 = f2 }
local t2 = { func1 = f1 }
local t = { t1, t2, {} }

local todot = require( "microscope" )
todot( "example5.dot", t )
todot( "example6.dot", t, "leaves" )

