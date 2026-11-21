local quarries = dofile("master/quarries.lua")

local start = { x = 100, y = 100, z = 100 }
local bounds = assert(quarries.bounds(start, "~10", "~10", -21, -1))
assert(bounds.x1 == 100 and bounds.x2 == 110 and bounds.z1 == 100 and bounds.z2 == 110)
assert(bounds.y1 == -21 and bounds.y2 == -1 and bounds.y2 - bounds.y1 + 1 == 21)
local negative = assert(quarries.bounds(start, "90", "~-5", -10, 0))
assert(negative.x1 == 90 and negative.x2 == 100 and negative.z1 == 95 and negative.z2 == 100)
assert(quarries.coordinate("~", 100) == 100)
assert(quarries.coordinate("~+10", 100) == 110)
assert(quarries.coordinate("-12", 100) == -12)
assert(not quarries.coordinate("~1.5", 100))
assert(not quarries.coordinate("~--1", 100))
assert(not quarries.bounds(start, "~", "~", 4, -4))

local jobs = { a = { id = "a", status = "OFFLINE", bounds = bounds } }
assert(quarries.findOverlap(negative, jobs) == "a", "offline jobs must retain their footprint")
jobs.a.status = "COMPLETE"
assert(not quarries.findOverlap(negative, jobs), "completed jobs should release their footprint")
local dump = assert(quarries.dumpPosition(start, 0, bounds, {}, {}))
assert(dump.x == 99 and dump.z == 100 or dump.x == 100 and dump.z == 99,
  "dump must be outside the quarry even if the preferred direction is inside")
local reserved = { { kind = "DUMP", pos = { x = 111, y = 0, z = 100 } } }
assert(quarries.findOverlap({ x1 = 111, x2 = 111, z1 = 100, z2 = 100 }, {}, reserved))
local other = { b = { id = "b", status = "MINING",
  bounds = { x1 = 111, x2 = 120, z1 = 100, z2 = 110 }, dump = { x = 110, z = 99 } } }
assert(quarries.findOverlap({ x1 = 110, x2 = 110, z1 = 99, z2 = 99 }, other) == "b")
print("MineSwarm coordinate and overlap tests passed")
