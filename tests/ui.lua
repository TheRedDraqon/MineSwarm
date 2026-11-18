package.preload["shared.util"] = function()
  return dofile("shared/util.lua")
end
package.preload["master.ore_db"] = function()
  return dofile("master/ore_db.lua")
end

colors = {
  black = 1, white = 2, gray = 3, blue = 4, cyan = 5, lime = 6,
  yellow = 7, red = 8, magenta = 9, orange = 10, green = 11,
}
os.epoch = function() return os.time() * 1000 end

local monitor = {
  setTextScale = function() end,
  getSize = function() return 80, 30 end,
  setBackgroundColor = function() end,
  setTextColor = function() end,
  setCursorPos = function() end,
  write = function() end,
  clear = function() end,
}
local state = {
  job = {
    id = "test",
    status = "RUNNING",
    bounds = { x1 = 0, x2 = 99, y1 = -21, y2 = -1, z1 = 0, z2 = 99 },
    assignments = {
      Miner_1 = { sector = { x1 = 0, x2 = 49, y1 = -21, y2 = -1, z1 = 0, z2 = 49 } },
    },
    total = 10000,
    progress = 250,
    started = os.time() * 1000,
  },
  drones = {
    Miner_1 = {
      online = true, state = "MINING", pos = { x = 10, y = -1, z = 10 },
      dir = 0, fuel = 5000, inventory = 4, task = "test:S01",
    },
  },
  waypoints = {
    { block = "allthemodium", pos = { x = 20, y = 90, z = 20 } },
  },
  yield = { ["minecraft:iron_ore"] = 20 },
}
local calls = { cleared = false, launched = false }
local uiLib = dofile("master/ui.lua")
local ui = uiLib.new(monitor, state, { home = { x = 0, z = 0 }, origin = { x = 0, z = 0 } }, {
  command = function() end,
  deploy = function() end,
  launch = function() calls.launched = true end,
  clearWaypoint = function(index)
    assert(index == 1)
    calls.cleared = true
  end,
})

ui.draw()
ui.touch(45, 1)
ui.draw()
ui.touch(5, 5)
ui.draw()
ui.touch(25, 1)
ui.draw()
ui.touch(30, 5)
ui.draw()
ui.touch(10, 26)
assert(calls.launched)
ui.touch(65, 1)
ui.draw()
ui.touch(39, 7)
assert(calls.cleared)

print("MineSwarm UI rendering and interaction tests passed")
