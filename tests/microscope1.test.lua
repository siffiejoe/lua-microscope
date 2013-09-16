#!/usr/bin/lua

package.path = [[../src/?.lua;]] .. package.path
local newproxy = newproxy or require( "newproxy" )
local microscope = require( "microscope" )
local light = require( "light" )
local full  = newproxy()
local func  = function() end
local co  = coroutine.create( function() end )

local n = 0
local function dot( v, label, ... )
  local fname = string.format( "test%02d.dot", n )
  n = n + 1
  print( "", fname, tostring( v ) )
  microscope( fname, v, label, ... )
end


print( "testing all Lua types as direct arguments ..." )
dot( nil, "single nil value" )
dot( true, "single boolean value" )
dot( 123, "single number value" )
dot( "hello world", "single string value" )
dot( func, "plain function" )
dot( light, "plain light userdata value" )
dot( full, "plain full userdata value" )
dot( co, "plain coroutine/thread value" )
dot( {}, "plain empty table value" )

print( "testing all Lua types as table keys/values ..." )
dot( {
  [ true ] = false,
  [ 123 ] = 456,
  xyz = "abc",
  [ func ] = func,
  [ light ] = light,
  [ full ] = full,
  [ co ] = co,
  [ {} ] = {},
}, "all Lua types as table keys and values" )

print( "testing all Lua types as upvalues ..." )
do
  local _ = nil
  local a = true
  local b = 123
  local c = "hello world"
  local d = func
  local e = light
  local f = full
  local g = co
  local h = {}
  dot( function()
    return _, a, b, c, d, e, f, g, h
  end, "all Lua types as function upvalues" )
end

print( "testing all Lua types as environments ..." )
do
  local function makeuenv( val )
    local u = newproxy()
    if _VERSION == "Lua 5.1" then
      debug.setfenv( u, val )
    else
      debug.setuservalue( u, val )
    end
    return u
  end
  local function makefenv( val )
    local _VERSION = _VERSION
    local _ENV = val
    local function f() print( "bla" ) end
    if _VERSION == "Lua 5.1" then
      setfenv( f, _ENV )
    end
    return f
  end
  local function maketenv( val )
    if _VERSION == "Lua 5.1" then
      local c = coroutine.create( func )
      debug.setfenv( c, val )
      return c
    end
  end
  local function makefenvs( f )
    if _VERSION == "Lua 5.1" then
      return makefenv( {} )
    else
      return makefenv( nil ), makefenv( true ), makefenv( 123 ),
             makefenv( "hello" ), makefenv( func ), makefenv( light ),
             makefenv( full ), makefenv( co ), makefenv{}
    end
  end
  local t = {
    makeuenv{}, { makefenvs() }, maketenv{}
  }
  dot( t, "all possible Lua types as environments", "environments" )
end

print( "testing escapes in string (and (no-)html option) ..." )
do
  local t = { "'N'n\\n\n'G\\G'l\\l" }
  for i = 0, 63 do
    local s = string.char( i*4, i*4+1, i*4+2, i*4+3 )
    if i < 32 then
      t[ #t+1 ] = s
    else
      t[ s ] = s
    end
  end
  dot( t, "all characters in labels (HTML version)", "html" )
  dot( t, "all characters in labels (plain version)", "nohtml" )
end

print( "testing abbreviation of long string ..." )
dot( "This is a very long string that should be cut off somewhere!",
     "string which is abbreviated as a label" )

print( "testing function with all features ..." )
do
  local f, env
  do
    env = {}
    local _ENV = env
    local a = nil
    local b = 123
    function f() return a or b or print end
  end
  if _VERSION == "Lua 5.1" then
    setfenv( f, env )
  end
  dot( f, "function with all features (upvalues+env)", "environments" )
end

print( "testing udata with all features ..." )
do
  local u = newproxy( true )
  if _VERSION == "Lua 5.1" then
    debug.setfenv( u, {} )
  else
    debug.setuservalue( u, {} )
  end
  dot( u, "userdata with all features (metatable+env)", "environments" )
end

print( "testing table with all features ..." )
do
  local function dummy() end
  local function len() return 0 end
  local t = {
    1, "2", 3,
    key1 = "val1",
    key2 = true
  }
  setmetatable( t, { __index = t, __ipairs = dummy, __pairs = dummy,
                     __len = len } )
  dot( t, "table with all features (array+hash part,metatable)" )
  dot( { 1, 2, 3, nil, 4, 5, 6, nil, nil, nil, 8, nil, 9, nil, nil, 10 },
       "array (table) with holes at positions 4,8,9,10,12,14,15" )
end

print( "testing thread with all features ..." )
do
  local c = coroutine.create( func )
  if _VERSION == "Lua 5.1" then
    debug.setfenv( c, {} )
  end
  dot( c, "thread with all features (env in Lua 5.1)", "environments" )
end

print( "testing shared upvalues ..." )
do
  local value = 1
  local reference = {}
  local distval = 2
  local function f1()
    return value, reference, distval
  end
  local distval = 2
  local function f2()
    return value, reference, distval
  end
  local t = {
    f1, f2
  }
  dot( t, "shared upvalues (in Lua5.1 only for reference types)" )
end

print( 'testing "(no-)environments" option ...' )
do
  local f
  do
    local _ENV = {}
    function f()
      print( "hello world" )
    end
    if _VERSION == "Lua 5.1" then
      setfenv( f, _ENV )
    end
  end
  local u, th = newproxy(), coroutine.create( f )
  if _VERSION == "Lua 5.1" then
    debug.setfenv( u, {} )
    debug.setfenv( th, {} )
  else
    debug.setuservalue( u, {} )
  end
  local t = { u, f, th }
  dot( t, "with environments", "environments" )
  dot( t, "without environments", "noenvironments" )
end

print( 'testing "(no-)leaves" option ...' )
do
  local t1 = {}
  local t2 = {}
  local t3 = {}
  local t4 = { t2 }
  setmetatable( t3, {} )
  local u1 = newproxy()
  local u2 = newproxy()
  if _VERSION == "Lua 5.1" then
    debug.setfenv( u2, {} )
  else
    debug.setuservalue( u2, {} )
  end
  local a, b = true, false
  local function f1() return true, false end
  local function f2() return a, b end
  local t = { t1, t2, t3, t4, u1, u2, f1, f2 }
  dot( t, "with leaf nodes (env, pruned at _G)", "leaves", "environments", _G )
  dot( t, "without leaf nodes (env, pruned at _G)", "noleaves", "environments", _G )
end

print( 'testing "(no-)upvalues" option ...' )
do
  local a, b, c, d, e = nil, true, 123, "hello", {}
  local function f()
    return a, b, c, d, e
  end
  dot( f, "with upvalues", "upvalues" )
  dot( f, "without upvalues", "noupvalues" )
end

print( 'testing "(no-)metatables" option ...' )
do
  local t1 = {}
  setmetatable( t1, {} )
  local t2 = { io.stdout, t1 }
  dot( t2, "with metatables", "metatables" )
  dot( t2, "without metatables", "nometatables" )
end

print( "testing max_depth ..." )
do
  local t1 = { 1 }
  local t2 = { { t1, { t1, { {} } } } }
  dot( t2, "nested tables, unlimited depth" )
  dot( t2, "nested tables, depth limited to 3", 3 )
end

print( "testing pruning ..." )
do
  local t0 = { 0 }
  local t1 = { t0 }
  local t2 = { t0, t1 }
  dot( t2, "nested tables without pruning" )
  dot( t2, "nested tables pruned at " .. tostring( t1 ), t1 )
end

print( "testing registry ..." )
dot( "dummy", "registry table with max_depth 2", "registry", 2 )

print( "testing locals and (no-)html option ..." )
do
  dot( "dummy", "locals from main thread", "locals", 3, microscope )

  local function f1( arg1 )
    dot( "dummy", "locals from main active coroutine",
         "locals", 3, microscope )
    coroutine.yield( arg1 )
  end

  local c1

  local function f2( ... )
    local a = {
      bool = true,
      num = 1.234,
      func = f1,
      co = c1,
    }
    a.a = a
    return f1( a )
  end

  local function f3( v, n )
    for i = 1, n do
      dot( v, "locals with max_depth 3 (html version)",
           "locals", 3, microscope )
      dot( v, "locals with max_depth 3 (nohtml version)",
           "locals", "nohtml", 3, microscope )
    end
  end

  c1 = coroutine.create( f2 )
  local f4 = coroutine.wrap( f3 )
  coroutine.resume( c1, 1, 2, 3 )
  f4( c1, 1 )
end

print( "testing stripped bytecode ..." )
do
  local stripped, nonstripped
  local env = { setmetatable = setmetatable, newproxy = newproxy }
  if _VERSION == "Lua 5.1" then
    nonstripped = assert( loadfile( "bytecode.n.luac" ) )
    stripped = assert( loadfile( "bytecode.s.luac" ) )
    env.setfenv = debug.setfenv
    setfenv( nonstripped, env )
    setfenv( stripped, env )
  else
    env.setfenv = debug.setuservalue
    nonstripped = assert( loadfile( "bytecode.n.luac", "b", env ) )
    stripped = assert( loadfile( "bytecode.s.luac", "b", env ) )
  end
    dot( nonstripped(), "using unstripped bytecode",
         "environments", env.setmetatable, env.newproxy, env.setfenv )
    dot( stripped(), "using stripped bytecode",
         "environments", env.setmetatable, env.newproxy, env.setfenv )
end

print( "testing without debug table ..." )
do
  local u = newproxy( true )
  if _VERSION == "Lua 5.1" then
    debug.setfenv( u, {} )
  else
    debug.setuservalue( u, {} )
  end
  local mt, f = getmetatable( u )
  do
    local _ENV = {}
    function f() return u, mt, print end
    if _VERSION == "Lua 5.1" then
      setfenv( f, _ENV )
    end
  end
  mt.__metatable = f
  local t = { u, mt, f }
  dot( t, "with debug module available", "environments" )
  local olddebug, olddebugpre = debug, package.preload.debug
  local oldmicroscope = microscope
  package.loaded.debug = nil
  package.preload.debug = nil
  package.loaded.microscope = nil
  debug = nil
  microscope = require( "microscope" )
  dot( t, "only get(metatable|fenv) available", "environments" )
  debug = olddebug
  package.loaded.debug = olddebug
  package.preload.debug = olddebugpre
  package.loaded.microscope = oldmicroscope
  microscope = oldmicroscope
end

print( "testing without debug and certain baselib functions ..." )
do
  local u = newproxy( true )
  if _VERSION == "Lua 5.1" then
    debug.setfenv( u, {} )
  else
    debug.setuservalue( u, {} )
  end
  local mt, f = getmetatable( u )
  do
    local _ENV = {}
    function f() return u, mt, print end
    if _VERSION == "Lua 5.1" then
      setfenv( f, _ENV )
    end
  end
  mt.__metatable = f
  local t = { u, mt, f }
  dot( t, "with debug module available", "environments" )
  local olddebug, olddebugpre = debug, package.preload.debug
  local oldmicroscope = microscope
  local ogetfenv, ogetmetatable = getfenv, getmetatable
  getfenv, getmetatable = nil, nil
  package.loaded.debug = nil
  package.preload.debug = nil
  package.loaded.microscope = nil
  debug = nil
  microscope = require( "microscope" )
  dot( t, "without debug module and get(metatable|fenv)", "environments" )
  getfenv, getmetatable = ogetfenv, ogetmetatable
  debug = olddebug
  package.loaded.debug = olddebug
  package.preload.debug = olddebugpre
  package.loaded.microscope = oldmicroscope
  microscope = oldmicroscope
end

print( "testing alternative output function ..." )
microscope( function( s ) print( ">", s ) end, nil )

print( "testing for old bugs ..." )
do
  local t = {}
  setmetatable( t, {
    __tostring = function( v )
      return "table: abcdefghijklmnopqrstuvwxyz0123456789"
    end
  } )
  local u = newproxy( true )
  getmetatable( u ).__tostring = function( u )
    return "udata: abcdefghijklmnopqrstuvwxyz0123456789"
  end
  dot( { t, u }, "abbreviation in table cells" )
end

-- TODO ;-)

