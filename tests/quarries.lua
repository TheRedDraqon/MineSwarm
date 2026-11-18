local quarries = dofile("master/quarries.lua")

local bounds = { x1 = 0, x2 = 9, y1 = -21, y2 = -1, z1 = 0, z2 = 9 }
local touchingEdge = { x1 = 9, x2 = 18, y1 = -21, y2 = -1, z1 = 0, z2 = 9 }
local separateLayer = { x1 = 0, x2 = 9, y1 = -30, y2 = -22, z1 = 0, z2 = 9 }
local state = {
  quarries = {
    running = { id = "running", status = "MINING", bounds = bounds },
    done = { id = "done", status = "COMPLETE", bounds = touchingEdge },
  },
  job = { id = "complex", status = "RUNNING", bounds = separateLayer },
}

assert(quarries.intersects(bounds, touchingEdge), "shared X/Z boundary cell must overlap")
assert(not quarries.intersects(bounds, separateLayer), "separate Y ranges must not overlap")
assert(quarries.findOverlap(touchingEdge, state) == "running")
assert(quarries.findOverlap(separateLayer, state) == "complex")

local north = assert(quarries.fromHome({ x = 10, y = 64, z = 20, dir = 0 }, 3, 4, -21, -1))
assert(north.x1 == 10 and north.x2 == 12 and north.z1 == 19 and north.z2 == 22,
  "north-facing quarry must start one block in front of home")
local east = assert(quarries.fromHome({ x = 10, y = 64, z = 20, dir = 1 }, 3, 4, -21, -1))
assert(east.x1 == 11 and east.z1 == 20, "east-facing quarry must start one block ahead")
local invalidHome, homeReason = quarries.fromHome({ x = 1, y = 2, z = 3, dir = 4 }, 3, 4, -21, -1)
assert(invalidHome == nil and homeReason:find("valid saved GPS home", 1, true))

state.quarries.running.status = "INCOMPLETE"
assert(quarries.findOverlap(touchingEdge, state) == nil,
  "completed or explicitly incomplete jobs should not reserve the area")

print("MineSwarm quarry overlap tests passed")
