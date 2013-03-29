#!/usr/bin/lua

package.path = [[../src/?.lua;]] .. package.path

local function f1() end
local function f2()
  return f2()
end
local t1 = { func1 = f1, func2 = f2 }
setmetatable( t1, { __metatable = false } )
local t2 = { func1 = f1, tab1 = t1, file = io.stdout }
setmetatable( t2, {
  __index = t1,
  __metatable = f2
} )

debug = nil -- disable debug module
package.preload.debug = nil
require( "microscope" )( "example8.dot", t2, "environments", 3 )

