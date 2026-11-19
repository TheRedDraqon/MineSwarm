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
print("MineSwarm coordinate and overlap tests passed")
