#!/usr/bin/lua

package.path = [[../src/?.lua;]] .. package.path
local ms = require( "microscope" )

local t1 = { val = 1 }
local t2 = { 1, 2, 3, val = 2 }
setmetatable( t1, { __index = t2 } )
_ENV = t1
local function f1()
  print( val, t2.val )
end
if _VERSION == "Lua 5.1" then
  setfenv( f1, t1 )
end

ms( "example2.dot", f1, "environments" )

