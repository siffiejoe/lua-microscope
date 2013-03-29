/***** taken almost literally from Lua 5.1.4 source, so: **********************
* Copyright (C) 1994-2008 Lua.org, PUC-Rio.  All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
******************************************************************************/


#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>


static int newproxy( lua_State* L ) {
  lua_settop( L, 1 );
  lua_newuserdata( L, 0 );
  if( lua_toboolean( L, 1 ) == 0 )   /* false value */
    return 1;
  else if( lua_isboolean( L, 1 ) ) { /* true */
    lua_newtable( L );
    lua_pushvalue( L, -1 );
    lua_pushboolean( L, 1 );
    lua_rawset( L, lua_upvalueindex( 1 ) );
  } else {                           /* rest (hopefully proxy) */
    int validproxy = 0;
    if( lua_getmetatable( L, 1 ) ) {
      lua_rawget( L, lua_upvalueindex( 1 ) );
      validproxy = lua_toboolean( L, -1 );
      lua_pop( L, 1 );
    }
    luaL_argcheck( L, validproxy, 1, "boolean or proxy expected" );
    lua_getmetatable( L, 1 );
  }
  lua_setmetatable( L, 2 );
  return 1;
}


LUALIB_API int luaopen_newproxy( lua_State* L ) {
  lua_createtable( L, 0, 1 );
  lua_pushvalue( L, -1 );
  lua_setmetatable( L, -2 );
  lua_pushliteral( L, "kv" );
  lua_setfield( L, -2, "__mode" );
  lua_pushcclosure( L, newproxy, 1 );
  return 1;
}

