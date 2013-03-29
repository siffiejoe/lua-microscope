#!/usr/bin/lua

package.path = [[../src/?.lua;]] .. package.path

local t = { { { { { {} } } } } }

local todot = require( "microscope" )
todot( "example3.dot", t )
todot( "example4.dot", t, 3 )

