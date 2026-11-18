package.preload["shared.config"] = function()
  return { gpsTimeout = 2, maxTravelSteps = 1000 }
end

local position = { x = 0, y = 64, z = 0 }
local direction = 0
local blockedDown
local blockedForward = {}
local blockNames = {}
local dugDirections = {}
local alerts = {}
local gpsStale = false
local vectors = {
  [0] = { x = 0, z = -1 },
  [1] = { x = 1, z = 0 },
  [2] = { x = 0, z = 1 },
  [3] = { x = -1, z = 0 },
}

turtle = {
  turnLeft = function() direction = (direction + 3) % 4; return true end,
  turnRight = function() direction = (direction + 1) % 4; return true end,
  forward = function()
    if blockedForward[direction] then return false end
    local delta = vectors[direction]
    position.x, position.z = position.x + delta.x, position.z + delta.z
    return true
  end,
  back = function()
    local delta = vectors[direction]
    position.x, position.z = position.x - delta.x, position.z - delta.z
    return true
  end,
  up = function() position.y = position.y + 1; return true end,
  down = function()
    if blockedDown and position.y - 1 == blockedDown.y then return false end
    position.y = position.y - 1
    return true
  end,
  detectDown = function() return blockedDown ~= nil end,
  inspectDown = function()
    if blockedDown and position.y - 1 == blockedDown.y then return true, blockedDown.data end
    return false
  end,
  digDown = function() return false end,
  inspectUp = function() return false end,
  digUp = function() return false end,
  detectUp = function() return false end,
  inspect = function()
    if blockedForward[direction] then
      return true, { name = blockNames[direction] or "minecraft:stone" }
    end
    return false
  end,
  dig = function()
    if not blockedForward[direction] then return false end
    dugDirections[#dugDirections + 1] = direction
    blockedForward[direction] = nil
    return true
  end,
  detect = function() return false end,
}
gps = {
  locate = function()
    if gpsStale then return 0, 64, 0 end
    return position.x, position.y, position.z
  end,
}
os.sleep = function() end

local poseLib = dofile("shared/pose.lua")
local pose = { x = 0, y = 64, z = 0, dir = 0 }
local ok, reason = poseLib.moveTo(pose, 3, 62, 2)
assert(ok, reason)
assert(pose.x == 3 and pose.y == 62 and pose.z == 2)
assert(position.x == pose.x and position.y == pose.y and position.z == pose.z)
assert(direction == pose.dir)

position = { x = 0, y = 64, z = 0 }
direction = 0
blockedForward[0] = true
local calibrated, calibrationReason = poseLib.calibrate()
assert(calibrated, calibrationReason)
assert(calibrated.dir == 0)
assert(position.x == 0 and position.y == 64 and position.z == 0)
assert(direction == 0, "calibration must restore the original turtle facing")
blockedForward = { [0] = true, [1] = true, [2] = true, [3] = true }
local fallbackCalibration, fallbackReason = poseLib.calibrate()
assert(fallbackCalibration, fallbackReason)
assert(fallbackCalibration.dir == 0)
assert(position.x == 0 and position.y == 64 and position.z == 0)
assert(direction == 0, "dig fallback must restore the original turtle facing")
assert(#dugDirections == 1 and dugDirections[1] == 0, "fallback should dig only the front block")

blockedForward = { [0] = true, [1] = true, [2] = true, [3] = true }
blockNames[0] = "allthemodium:allthemodium_ore"
local protectedCalibration, protectedReason = poseLib.calibrate()
assert(protectedCalibration == nil and protectedReason:find("protected block", 1, true))
assert(#dugDirections == 1, "calibration must not dig protected blocks")
blockNames[0] = nil
blockedForward = {}
gpsStale = true
local staleCalibration, staleReason = poseLib.calibrate()
assert(staleCalibration == nil and staleReason:find("GPS", 1, true))
assert(#dugDirections == 1, "calibration must not dig when GPS readings are stale")
gpsStale = false

position = { x = pose.x, y = pose.y, z = pose.z }
direction = pose.dir
blockedDown = { y = pose.y - 1, data = { name = "allthemodium:allthemodium_ore" } }
local alerted, alertReason = poseLib.moveTo(pose, pose.x, pose.y - 1, pose.z,
  function(block, target) alerts[#alerts + 1] = { block = block, pos = target } end)
assert(not alerted and alertReason == "protected block")
assert(#alerts == 1 and alerts[1].pos.y == blockedDown.y)
assert(position.y == pose.y)

print("MineSwarm pose movement tests passed")
