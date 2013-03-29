local up1 = false
local up2 = newproxy( true )
setfenv( up2, {} )
local t1 = { val = 1 }
local t2 = { val = 2 }
setmetatable( t1, { __index = function( t, k )
  if t2[ k ] ~= nil then
    return t2[ k ]
  else
    return up1 or up2 or print
  end
end } )
setmetatable( t2, { __index = t1 } )
return t1

