#include <stddef.h>
#include <lua.h>
#include <lauxlib.h>

int luaopen_light( lua_State* L ) {
  lua_pushlightuserdata( L, NULL );
  return 1;
}

