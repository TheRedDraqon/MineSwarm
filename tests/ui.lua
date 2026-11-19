package.preload["shared.util"] = function() return dofile("shared/util.lua") end
package.preload["master.ore_db"] = function() return dofile("master/ore_db.lua") end
package.preload["master.quarries"] = function() return dofile("master/quarries.lua") end

colors = {
  black = 1, white = 2, gray = 3, blue = 4, cyan = 5, yellow = 7,
  red = 8, orange = 10, green = 11,
}
keys = { backspace = 1, enter = 2, numPadEnter = 3, escape = 4 }
local screen = {}
local monitor = {
  setTextScale = function() end, getSize = function() return 80, 30 end,
  setBackgroundColor = function() end, setTextColor = function() end,
  setCursorPos = function() end, clear = function() screen = {} end,
  write = function(value) screen[#screen + 1] = value end,
}
local state = {
  drones = { Drone1 = { online = true, state = "IDLE", pos = { x = 100, y = 100, z = 100 } } },
  jobs = {}, waypoints = {},
}
local called
local ui = dofile("master/ui.lua").new(monitor, state, {
  launch = function(...) called = { ... } end,
  command = function() end, clearWaypoint = function() end,
})
ui.draw()
ui.touch(3, 5)
assert(ui.selectedDrone == "Drone1")
ui.draw()
ui.touch(30, 1)
ui.draw()
assert(table.concat(screen):find("X 100..110  Y -21..-1  Z 100..110", 1, true))
ui.touch(3, 7)
for char in ("~-5"):gmatch(".") do ui.handleInput("char", char) end
ui.handleInput("key", keys.enter)
assert(ui.xInput == "~-5")
ui.draw()
ui.touch(3, 27)
assert(called and called[1] == "Drone1" and called[2] == "~-5" and called[4] == "Osmium")
print("MineSwarm monitor input tests passed")
