-- generate a graphviz graph from a lua table structure

local max_label_length = 20

-- cache globals
local assert = assert
local require = assert( require )
local _VERSION = assert( _VERSION )
local type = assert( type )
local tostring = assert( tostring )
local select = assert( select )
local next = assert( next )
local rawget = assert( rawget )
local pcall = assert( pcall )
local string = require( "string" )
local ssub = assert( string.sub )
local sgsub = assert( string.gsub )
local sformat = assert( string.format )
local sbyte = assert( string.byte )
local table = require( "table" )
local tconcat = assert( table.concat )
-- optional ...
local getmetatable = getmetatable
local getfenv = getfenv
local debug, ioopen, corunning
do
  local ok, dbg = pcall( require, "debug" )
  if ok then debug = dbg end
  local ok, io = pcall( require, "io" )
  if ok and type( io ) == "table" and
     type( io.open ) == "function" then
    ioopen = io.open
  end
  local ok, co = pcall( require, "coroutine" )
  if ok and type( co ) == "table" and
     type( co.running ) == "function" then
    corunning = co.running
  end
end


local dottify
local get_metatable, get_environment, get_registry, get_locals, upvalues


-- select implementation of get_metatable depending on available API
if type( debug ) == "table" and
   type( debug.getmetatable ) == "function" then

  local get_mt = debug.getmetatable
  function get_metatable( val, enabled )
    if enabled then return get_mt( val ) end
  end

elseif type( getmetatable ) == "function" then

  function get_metatable( val, enabled )
    if enabled then return getmetatable( val ) end
  end

else

  function get_metatable() end

end


-- select implementation of get_environment depending on available API
if type( debug ) == "table" and
   type( debug.getfenv ) == "function" then

  local get_fe = debug.getfenv
  function get_environment( val, enabled )
    if enabled then return get_fe( val ) end
  end

elseif type( debug ) == "table" and
       type( debug.getuservalue ) == "function" then

  local get_uv = debug.getuservalue
  function get_environment( val, enabled )
    if enabled then
      -- getuservalue in Lua5.2 throws on light userdata!
      local ok, res = pcall( get_uv, val )
      if ok then return res end
    end
  end

elseif type( getfenv ) == "function" then

  function get_environment( val, enabled )
    if enabled and type( val ) == "function" then
      return getfenv( val )
    end
  end

else

  function get_environment() end

end


-- select implementation of get_registry
if type( debug ) == "table" and
   type( debug.getregistry ) == "function" then
  get_registry = debug.getregistry
else
  function get_registry() end
end


-- select implementation of get_locals
if type( debug ) == "table" and
   type( debug.getinfo ) == "function" and
   type( debug.getlocal ) == "function" then

  local getinfo, getlocal = debug.getinfo, debug.getlocal

  local function getinfo_nothread( _, func, what )
    return getinfo( func, what )
  end

  local function getlocal_nothread( _, level, loc )
    return getlocal( level, loc )
  end

  function get_locals( thread, enabled )
    if enabled then
      local locs = {}
      local start = 1
      local gi, gl = getinfo, getlocal
      if not thread then
        gi, gl = getinfo_nothread, getlocal_nothread
      end
      local info, i = gi( thread, 0, "nf" ), 0
      while info do
        local t = { name = info.name, func = info.func }
        local j, n,v = 1, gl( thread, i, 1 )
        while n ~= nil do
          t[ j ] = { n, v }
          j = j + 1
          n,v = gl( thread, i, j )
        end
        i = i + 1
        locs[ i ] = t
        if info.func == dottify then start = i+1 end
        info = gi( thread, i, "nf" )
      end
      return locs, start
    end
  end

else

  function get_locals() end

end


-- select implementation of upvalues depending on available API
local function dummy_iter() end
if type( debug ) == "table" and
   type( debug.getupvalue ) == "function" then

  local get_up, uv_iter = debug.getupvalue
  if _VERSION == "Lua 5.1" then

    function uv_iter( state )
      local name, uv = get_up( state.value, state.n )
      state.n = state.n + 1
      return name, uv, nil
    end

  else -- Lua 5.2 (and later) mixes upvalues and environments

    local get_upid
    if type( debug.upvalueid ) == "function" then
      get_upid = debug.upvalueid
    end

    function uv_iter( state )
      local name, uv = get_up( state.value, state.n )
      state.n = state.n + 1
      if name == "_ENV" and not state.show_env then
        return uv_iter( state )
      end
      local id = nil
      if get_upid ~= nil and name ~= nil then
        id = get_upid( state.value, state.n - 1 )
      end
      return name, uv, id
    end
  end

  function upvalues( val, enabled, show_env )
    if enabled then
      return uv_iter, { value = val, n = 1, show_env = show_env }
    else
      return dummy_iter
    end
  end

else

  function upvalues()
    return dummy_iter
  end

end



-- scanning is done in breadth-first order using a linked list. the
-- nodes are appended in ascending order of depth. there is also a
-- lookup table by value (for reference types) or by upvalueid (for
-- value type upvalues) to ensure a single node for a value
local function new_db( proto )
  proto = proto or {}
  proto.n_nodes    = 0
  proto.list_begin = nil
  proto.list_end   = nil
  proto.key2node   = {}
  proto.max_depth  = 0
  proto.prune      = {}
  proto.edges      = {}
  return proto
end


local function db_node( db, val, depth, key )
  local node, t = nil, type( val )
  if t ~= "number" and t ~= "boolean" and t ~= "nil" then
    key = val
  end
  if key ~= nil then
    node = db.key2node[ key ]
  end
  if not node and
     (db.max_depth < 1 or depth <= db.max_depth) and
     (key == nil or not db.prune[ key ]) then
    db.n_nodes = db.n_nodes + 1
    node = {
      id = tostring( db.n_nodes ),
      value = val,
      depth = depth,
      shape = nil, label = nil, draw = nil, next = nil,
    }
    if key ~= nil then
      db.key2node[ key ] = node
    end
    if db.list_end ~= nil then
      db.list_end.next = node
    else
      db.list_begin = node
    end
    db.list_end = node
  end
  return node
end


local function define_edge( db, edge )
  local es = db.edges
  es[ #es+1 ] = edge
end


-- generate dot code for references
local function dottify_metatable_ref( src, port1, mt, port2, db )
  define_edge( db, {
    A = src, A_port = port1,
    B = mt, B_port = port2,
    style = "dashed",
    dir = "both",
    arrowtail = "odiamond",
    label = "metatable",
    color = "blue"
  } )
  src.draw, mt.draw = true, true
end

local function dottify_environment_ref( src, port1, env, port2, db )
  define_edge( db, {
    A = src, A_port = port1,
    B = env, B_port = port2,
    style = "dotted",
    dir = "both",
    arrowtail = "dot",
    label = "environment",
    color = "red"
  } )
  src.draw, env.draw = true, true
end

local function dottify_upvalue_ref( src, port1, upv, port2, db, name )
  define_edge( db, {
    A = src, A_port = port1,
    B = upv, B_port = port2,
    style = "dashed",
    label = name,
    color = "green"
  } )
  src.draw, upv.draw = true, true
end

local function dottify_ref( n1, port1, n2, port2, db )
  define_edge( db, {
    A = n1, A_port = port1,
    B = n2, B_port = port2,
    style = "solid"
  } )
end

local function dottify_stack_ref( th, port1, st, port2, db )
  define_edge( db, {
    A = th, A_port = port1,
    B = st, B_port = port2,
    style = "solid",
    arrowhead = "none",
    weight = 2,
    color = "lightgrey",
  } )
  th.draw = true
end


local function abbrev( str )
  if #str > max_label_length then
    str = ssub( str, 1, max_label_length-3 ) .. "..."
  end
  return str
end


-- escape and strings for graphviz labels
local html_escapes = {
  [ "\r" ] = "\\r",
  [ "\n" ] = "\\n",
  [ "\t" ] = "\\t",
  [ "\f" ] = "\\f",
  [ "\v" ] = "\\v",
  [ "\\" ] = "\\\\",
  [ "'" ] = "\\'",
  [ "<" ] = "&lt;",
  [ ">" ] = "&gt;",
  [ "&" ] = "&amp;",
  [ '"' ] = "&quot;",
}
local record_escapes = {
  [ "\r" ] = "\\\\r",
  [ "\n" ] = "\\\\n",
  [ "\t" ] = "\\\\t",
  [ "\f" ] = "\\\\f",
  [ "\v" ] = "\\\\v",
  [ "\\" ] = "\\\\\\\\",
  [ "'" ] = "\\\\'",
  [ "<" ] = "\\<",
  [ ">" ] = "\\>",
  [ '"' ] = '\\"',
  [ "{" ] = "\\{",
  [ "}" ] = "\\}",
  [ "|" ] = "\\|",
}

local function escape( str, use_html )
  local esc
  if use_html then
    esc = "\\"
    str = sgsub( str, "[\r\n\t\f\v\\'<>&\"]", html_escapes )
  else
    esc = "\\\\"
    str = sgsub( str, "[\r\n\t\f\v\\'<>\"{}|]", record_escapes )
  end
  str = sgsub( str, "[^][%w !\"#$%%&'()*+,./:;<=>?@\\^_`{|}~-]", function( c )
    return sformat( "%s%03d", esc, sbyte( c ) )
  end )
  return str
end


local function quote( str )
  return "'" .. str .. "'"
end


local function make_label_elem( tnode, v, db, subid, depth, alt )
  local t = type( v )
  if t == "number" or t == "boolean" then
    return escape( tostring( v ), db.use_html )
  elseif t == "string" then
    return quote( escape( abbrev( v ), db.use_html ) )
  else -- userdata, function, thread, table
    local n = db_node( db, v, depth+1 )
    if n then
      dottify_ref( tnode, subid, n, t == "table" and "0" or nil, db )
    end
    alt = alt or tostring( v )
    return alt or escape( abbrev( alt ), db.use_html )
  end
end


local function make_html_table( db, node, val )
  local depth = node.depth
  node.shape = "plaintext"
  node.is_html_label = true
  local label = [[<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0">
  <TR><TD PORT="0" COLSPAN="2" BGCOLOR="lightgrey">]] ..
    escape( abbrev( tostring( val ) ), true ) .. [[
</TD></TR>
]]
  local handled = {}
  -- first the array part
  local n, v = 1, rawget( val, 1 )
  while v ~= nil do
    local el_label = make_label_elem( node, v, db, tostring( n ), depth )
    label = label .. [[
  <TR><TD PORT="]] .. n .. [[" COLSPAN="2">]] .. el_label .. [[
</TD></TR>
]]
    handled[ n ] = true
    n = n + 1
    v = rawget( val, n )
  end
  -- and then the hash part
  for k,v in next, val do
    node.draw = true
    if not handled[ k ] then -- skip array part elements
      local k_label = make_label_elem( node, k, db, "k"..n, depth )
      local v_label = make_label_elem( node, v, db, "v"..n, depth )
      label = label .. [[
  <TR><TD PORT="k]] .. n .. [[">]] .. k_label .. [[
</TD><TD PORT="v]] .. n .. [[">]] .. v_label .. [[
</TD></TR>
]]
      n = n + 1
    end
  end
  node.label = label .. [[</TABLE>]]
end


local function make_record_table( db, node, val )
  local depth = node.depth
  node.shape = "record"
  local label = "{ <0> " .. escape( abbrev( tostring( val ) ), false )
  local handled = {}
  -- first the array part
  local n,v = 1, rawget( val, 1 )
  while v ~= nil do
    local el_label = make_label_elem( node, v, db, tostring( n ), depth )
    label = label .. " | <" .. n .. "> " .. el_label
    handled[ n ] = true
    n = n + 1
    v = rawget( val, n )
  end
  -- and then the hash part
  local keys, values = {}, {}
  for k,v in next, val do
    node.draw = true
    if not handled[ k ] then -- skip array part elements
      local k_label = make_label_elem( node, k, db, "k"..n, depth )
      local v_label = make_label_elem( node, v, db, "v"..n, depth )
      keys[ #keys+1 ] = "<k" .. n .. "> " .. k_label
      values[ #values+1 ] = "<v" .. n .. "> " .. v_label
      n = n + 1
    end
  end
  if next( keys ) ~= nil then
    label = label .. " | { { " .. tconcat( keys, " | " ) ..
            " } | { " .. tconcat( values, " | " ) .. " } }"
  end
  node.label = label .. " }"
end


local function make_html_stack( db, node )
  local frames, start = get_locals( node.thread, db.show_locals )
  if frames then
    local depth = node.depth
    local n = 0
    node.shape = "plaintext"
    node.is_html_label = true
    local label = [[
    <TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" COLOR="lightgrey">
  ]]
    for i = start, #frames do
      local frame = frames[ i ]
      local name, func = frame.name, frame.func
      if name == '' and i == #frames then name = "[coroutine init]" end
      label = label .. '  <TR><TD PORT="' .. n ..
              '" COLSPAN="3" BGCOLOR="lightgrey">' ..
              make_label_elem( node, func, db, n..":e", depth, name ) ..
              '</TD></TR>\n'
      n = n + 1
      for i = #frame, 1, -1 do
        label = label .. '  <TR><TD>' ..
                escape( tostring( i ), true ) .. '</TD><TD>' ..
                escape( abbrev( frame[ i ][ 1 ] ), true ) ..
                '</TD><TD PORT="' .. n .. '">' ..
                make_label_elem( node, frame[ i ][ 2 ], db, n, depth ) ..
                '</TD></TR>\n'
        n = n + 1
        node.draw = true
      end
    end
    node.label = label .. [[</TABLE>]]
  end
end


local function make_record_stack( db, node )
  local frames, start = get_locals( node.thread, db.show_locals )
  if frames then
    local depth = node.depth
    local n = 0
    node.shape = "Mrecord"
    node.color = "lightgrey"
    local label = "{"
    for i = start, #frames do
      local frame = frames[ i ]
      local name, func = frame.name, frame.func
      if name == '' and i == #frames then name = "[coroutine init]" end
      if n > 0 then label = label .. " |" end
      label = label .. " <" .. n .. "> " ..
              make_label_elem( node, func, db, n..":e", depth, name )
      n = n + 1
      local nums, keys, values = {}, {}, {}
      for i = #frame, 1, -1 do
        nums[ #nums+1 ] = escape( tostring( i ), false )
        keys[ #keys+1 ] = escape( abbrev( frame[ i ][ 1 ] ), false )
        values[ #values+1 ] = "<" .. n .. "> " ..
          make_label_elem( node, frame[ i ][ 2 ], db, n, depth )
        n = n + 1
        node.draw = true
      end
      if next( nums ) ~= nil then
        label = label .. " | { { " .. tconcat( nums, " | " ) ..
                " } | { " .. tconcat( keys, " | " ) .. " } | { " ..
                tconcat( values, " | " ) .. " } }"
      end
    end
    node.label = label .. " }"
  end
end


local function handle_metatable( db, node, val, port )
  local mt = get_metatable( val, db.show_metatables )
  if mt ~= nil then
    local mt_node = db_node( db, mt, node.depth+1 )
    if mt_node then
      local r = type( mt ) == "table" and "0" or nil
      dottify_metatable_ref( node, port, mt_node, r, db )
    end
  end
end

local function handle_environment( db, node, val )
  local env = get_environment( val, db.show_environments )
  if env ~= nil then
    local env_node = db_node( db, env, node.depth+1 )
    if env_node then
      local r = type( env ) == "table" and "0" or nil
      dottify_environment_ref( node, nil, env_node, r, db )
    end
  end
end

local function handle_upvalues( db, node, val )
  for na,uv,id in upvalues( val, db.show_upvalues, db.show_environments ) do
    local uv_node = db_node( db, uv, node.depth+1, id )
    if uv_node then
      local r = type( uv ) == "table" and "0" or nil
      dottify_upvalue_ref( node, nil, uv_node, r, db, na )
    end
  end
end

local function handle_stack( db, node, val )
  if db.show_locals then
    local id = db[ val ] or {}
    local st = db_node( db, id, node.depth )
    st.cb = "stack"
    st.thread = val
    dottify_stack_ref( node, nil, st, "0", db )
  end
end

local function handle_registry( db )
  if db.show_registry then
    local reg = get_registry()
    if type( reg ) == "table" then
      local re = db_node( db, reg, 1 )
      re.draw = true
    end
  end
end

local function handle_main_stack( db )
  if db.show_locals then
    local id = {}
    local st = db_node( db, id, 1 )
    if corunning then
      local th = corunning()
      if th then
        db[ th ] = id
      end
    end
    st.cb = "stack"
  end
end


local function dottify_table( db, node, val )
  if db.use_html then
    make_html_table( db, node, val )
  else
    make_record_table( db, node, val )
  end
  handle_metatable( db, node, val, "0" )
end


local function dottify_userdata( db, node, val )
  node.label = escape( abbrev( tostring( val ) ), false )
  node.shape = "box"
  handle_metatable( db, node, val )
  handle_environment( db, node, val )
end


local function dottify_thread( db, node, val )
  node.label = escape( abbrev( tostring( val ) ), false )
  node.group = node.label
  node.shape = "octagon"
  node.margin = "0.01"
  handle_environment( db, node, val )
  handle_stack( db, node, val )
end


local function dottify_function( db, node, val )
  node.label = escape( abbrev( tostring( val ) ), false )
  node.shape = "ellipse"
  node.margin = "0.01"
  handle_environment( db, node, val )
  handle_upvalues( db, node, val )
end


local function dottify_string( db, node, val )
  node.label = quote( escape( abbrev( val ), false ) )
  node.shape = "plaintext"
end


local function dottify_other( db, node, val )
  node.label = escape( abbrev( tostring( val ) ), false )
  node.shape = "plaintext"
end


local function dottify_stack( db, node )
  if node.thread then
    node.group = escape( abbrev( tostring( node.thread ) ), false )
  end
  if db.use_html then
    make_html_stack( db, node )
  else
    make_record_stack( db, node )
  end
end


local callbacks = {
  table = dottify_table,
  [ "function" ] = dottify_function,
  thread = dottify_thread,
  userdata = dottify_userdata,
  string = dottify_string,
  number = dottify_other,
  boolean = dottify_other,
  [ "nil" ] = dottify_other,
  stack = dottify_stack
}

local function dottify_go( db, val )
  handle_registry( db )
  handle_main_stack( db )
  db_node( db, val, 1 ).draw = true
  local node = db.list_begin
  while node do
    callbacks[ node.cb or type( node.value ) ]( db, node, node.value )
    node = node.next
  end
end


local function write_nodes( db, out_f )
  local node = db.list_begin
  while node do
    if db.show_leaves or node.draw then
      out_f( db, node )
    end
    node = node.next
  end
end


local function write_edges( db, out_f )
  for i = 1, #db.edges do
    local e = db.edges[ i ]
    local n1, n2 = e.A, e.B
    if db.show_leaves or (n1.draw and n2.draw) then
      out_f( db, e, n1, n2 )
    end
  end
end


local option_names = {
  "label", "shape", "style", "dir", "arrowhead", "arrowtail", "color",
  "margin", "group", "weight"
}

local function process_options_as_text( obj )
  local options = {}
  for i = 1, #option_names do
    local opt = option_names[ i ]
    if obj[ opt ] then
      local quote_on = "\""
      local quote_off = "\""
      if opt == "label" and obj.is_html_label then
        quote_on, quote_off = "<", ">"
      end
      options[ #options+1 ] = opt .. "=" .. quote_on ..
                              obj[ opt ] .. quote_off
    end
  end
  return options
end


local function write_graph_as_text( db, out )
  out( "digraph G {" )
  if db.label then
    out( "  label=\"" .. escape( db.label, false ) .. "\";" )
  end
  write_nodes( db, function( db, n )
    local options = process_options_as_text( n )
    out( "  " .. n.id .. " [" .. tconcat( options, "," ) .. "];" )
  end )
  write_edges( db, function( db, e, n1, n2 )
    local id1 = n1.id
    if e.A_port then id1 = id1 .. ":" .. e.A_port end
    local id2 = n2.id
    if e.B_port then id2 = id2 .. ":" .. e.B_port end
    local options = process_options_as_text( e )
    out( "  " .. id1 .. " -> " .. id2 ..  " [" ..
         tconcat( options, "," ) .. "];" )
  end )
  out( "}" )
end


local gvd_options = {
  metatables = function( db ) db.show_metatables = true end,
  nometatables = function( db ) db.show_metatables = nil end,
  upvalues = function( db ) db.show_upvalues = true end,
  noupvalues = function( db ) db.show_upvalues = nil end,
  environments = function( db ) db.show_environments = true end,
  noenvironments = function( db ) db.show_environments = nil end,
  html = function( db ) db.use_html = true end,
  nohtml = function( db ) db.use_html = nil end,
  leaves = function( db ) db.show_leaves = true end,
  noleaves = function( db ) db.show_leaves = nil end,
  registry = function( db ) db.show_registry = true end,
  noregistry = function( db ) db.show_registry = nil end,
  locals = function( db ) db.show_locals = true end,
  nolocals = function( db ) db.show_locals = nil end,
}

local function default_option( db, opt )
  local t = type( opt )
  if t == "number" then
    db.max_depth = opt
  elseif t == "table" or t == "userdata" or
         t == "function" or t == "thread" then
    db.prune[ opt ] = true
  elseif t == "string" then
    db.label = opt
  end
end


-- main function (predeclared above)
function dottify( output, val, ... )
  local db = new_db{
    show_metatables = true,
    show_upvalues = true,
    use_html = true,
  }
  for i = 1, select( '#', ... ) do
    local opt = select( i, ... );
    (gvd_options[ opt ] or default_option)( db, opt )
  end
  dottify_go( db, val )
  if type( output ) == "string" then
    assert( ioopen, "io.open needs to be defined for file output" )
    local file = assert( ioopen( output, "w" ) )
    write_graph_as_text( db, function( s )
        file:write( s, "\n" )
      end )
    file:close()
  else
    write_graph_as_text( db, output )
  end
end

return dottify

