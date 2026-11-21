local util = dofile("shared/util.lua")
for _, label in ipairs({ "Drone1", "MINER123", "a", "123" }) do
  assert(util.isDroneLabel(label), "valid label rejected: " .. label)
end
for _, label in ipairs({ "", "Miner_1", "a b", "a'b", 'a"b', "a\\b", "a/b", "é" }) do
  assert(not util.isDroneLabel(label), "invalid label accepted: " .. label)
end
assert(not util.isDroneLabel(nil))

local label, calibrationCount, setLabel
package.preload["shared.config"] = function() return {} end
package.preload["shared.util"] = function() return util end
package.preload["shared.net"] = function() return { open = function() error("test stopped") end } end
package.preload["shared.state"] = function()
  return { load = function() return { progress = 0, mode = "IDLE" } end, save = function() end }
end
package.preload["shared.pose"] = function()
  return { calibrate = function()
    calibrationCount = calibrationCount + 1
    return { x = 0, y = 0, z = 0, dir = 0 }
  end }
end
package.preload["drone.miner"] = function() return { refuel = function() return true end } end
turtle = { getFuelLevel = function() return "unlimited" end }
os.getComputerLabel = function() return label end
os.setComputerLabel = function(value) setLabel, label = value, value end
os.getComputerID = function() return 123 end

label, calibrationCount = "Miner_123", 0
local ok, reason = pcall(dofile, "drone/main.lua")
assert(not ok and tostring(reason):find("Invalid turtle label", 1, true))
assert(calibrationCount == 0, "invalid existing label must be rejected before calibration")

label, setLabel, calibrationCount = nil, nil, 0
ok, reason = pcall(dofile, "drone/main.lua")
assert(not ok and tostring(reason):find("test stopped", 1, true))
assert(setLabel == "Miner123" and calibrationCount == 1, "default label must be alphanumeric")

print("MineSwarm drone label tests passed")
