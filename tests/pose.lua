package.preload["shared.config"] = function()
  return { gpsTimeout = 2, maxTravelSteps = 1000 }
end

local position = { x = 0, y = 64, z = 0 }
local direction = 0
local blockedDown, blockedUp
local blockedForward = {}
local blockNames = {}
local blockTags = {}
local digFailures = {}
local dugDirections = {}
local alerts = {}
local forwardInspections = 0
local downDigs = 0
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
  up = function()
    if blockedUp and position.y + 1 == blockedUp.y then return false end
    position.y = position.y + 1
    return true
  end,
  down = function()
    if blockedDown and position.y - 1 == blockedDown.y then return false end
    position.y = position.y - 1
    return true
  end,
  detectDown = function() return blockedDown ~= nil and position.y - 1 == blockedDown.y end,
  inspectDown = function()
    if blockedDown and position.y - 1 == blockedDown.y then return true, blockedDown.data end
    return false
  end,
  digDown = function()
    downDigs = downDigs + 1
    if blockedDown and blockedDown.reason then return false, blockedDown.reason end
    blockedDown = nil
    return true
  end,
  inspectUp = function()
    if blockedUp and position.y + 1 == blockedUp.y then return true, blockedUp.data end
    return false
  end,
  digUp = function()
    if blockedUp and blockedUp.reason then return false, blockedUp.reason end
    blockedUp = nil
    return true
  end,
  detectUp = function() return blockedUp ~= nil and position.y + 1 == blockedUp.y end,
  inspect = function()
    forwardInspections = forwardInspections + 1
    if blockedForward[direction] then
      return true, { name = blockNames[direction] or "minecraft:stone", tags = blockTags[direction] }
    end
    return false
  end,
  dig = function()
    if not blockedForward[direction] then return false end
    dugDirections[#dugDirections + 1] = direction
    if digFailures[direction] then return false, digFailures[direction] end
    blockedForward[direction] = nil
    return true
  end,
  detect = function() return blockedForward[direction] == true end,
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
digFailures[0] = "Cannot break unbreakable block"
local protectedCalibration, protectedReason = poseLib.calibrate()
assert(protectedCalibration == nil and protectedReason:find("Cannot break unbreakable block", 1, true))
assert(#dugDirections == 2, "calibration must try digging before reporting an unbreakable block")
blockNames[0] = nil
digFailures[0] = nil
blockedForward = {}
gpsStale = true
local staleCalibration, staleReason = poseLib.calibrate()
assert(staleCalibration == nil and staleReason:find("GPS", 1, true))
assert(#dugDirections == 2, "calibration must not dig when GPS readings are stale")
gpsStale = false

position = { x = pose.x, y = pose.y, z = pose.z }
direction = pose.dir
blockedDown = { y = pose.y - 1, data = { name = "allthemodium:allthemodium_ore" },
  reason = "Cannot break unbreakable block" }
local alerted, alertReason = poseLib.moveTo(pose, pose.x, pose.y - 1, pose.z,
  function(block, target) alerts[#alerts + 1] = { block = block, pos = target } end)
assert(not alerted and alertReason:find("Cannot break unbreakable block", 1, true))
assert(alertReason:find("allthemodium:allthemodium_ore", 1, true))
local blockedCoordinate = pose.x .. "," .. blockedDown.y .. "," .. pose.z
assert(alertReason:find(blockedCoordinate, 1, true),
  "movement errors should include the blocked coordinates")
assert(#alerts == 1 and alerts[1].pos.y == blockedDown.y)
assert(position.y == pose.y)

blockedDown = { y = pose.y - 1, data = { name = "minecraft:bedrock" },
  reason = "Cannot break unbreakable block" }
local bedrockOk, bedrockReason = poseLib.moveTo(pose, pose.x, pose.y - 1, pose.z,
  function(block, target) alerts[#alerts + 1] = { block = block, pos = target } end)
assert(not bedrockOk and bedrockReason:find("minecraft:bedrock", 1, true))
assert(#alerts == 1, "bedrock must not create a waypoint")

local beforeReturnDig = downDigs
local downReturn, downReturnReason = poseLib.moveTo(pose, pose.x, pose.y - 1, pose.z,
  nil, nil, nil, true)
assert(not downReturn and downReturnReason:find("return path blocked", 1, true))
assert(downDigs == beforeReturnDig, "a vertical return must not dig")

blockedUp = { y = pose.y + 1, data = { name = "allthemodium:allthemodium_slate_ore" },
  reason = "Cannot break unbreakable block" }
local slateOk = poseLib.moveTo(pose, pose.x, pose.y + 1, pose.z,
  function(block, target) alerts[#alerts + 1] = { block = block, pos = target } end)
assert(not slateOk and #alerts == 2 and alerts[2].pos.y == pose.y + 1)
blockedUp = nil

blockedDown = nil
blockedForward[1] = true
blockNames[1] = "minecraft:deepslate"
blockTags[1] = { ["allthemodium:blocks/blocklist"] = true, ["allthemodium:paxel_effective"] = true }
local inspectedBefore = forwardInspections
local mined, mineReason = poseLib.moveTo(pose, pose.x + 1, pose.y, pose.z)
assert(mined, mineReason)
assert(forwardInspections == inspectedBefore, "successful digging must not inspect block tags")
assert(#alerts == 2, "breakable deepslate must not create a waypoint")
blockNames[1], blockTags[1] = nil, nil

blockedForward[1] = true
blockNames[1] = "allthemodium:allthemodium_slate_ore"
digFailures[1] = "Cannot break unbreakable block"
local oreOk, oreReason = poseLib.moveTo(pose, pose.x + 1, pose.y, pose.z,
  function(block, target) alerts[#alerts + 1] = { block = block, pos = target } end)
assert(not oreOk and oreReason:find("allthemodium:allthemodium_slate_ore", 1, true))
assert(#alerts == 3 and alerts[3].pos.x == pose.x + 1)
blockedForward[1], blockNames[1], digFailures[1] = nil, nil, nil

local stepPose = { x = pose.x, y = pose.y, z = pose.z, dir = pose.dir }
local stopped, stopReason = poseLib.moveTo(stepPose, stepPose.x + 2, stepPose.y, stepPose.z,
  nil, nil, function() return false, "inventory_full" end)
assert(not stopped and stopReason == "inventory_full" and stepPose.x == pose.x + 1,
  "movement must stop after the step where inventory fills")

blockedForward[1] = true
local digCount = #dugDirections
local returned, returnReason = poseLib.moveTo(stepPose, stepPose.x + 1, stepPose.y, stepPose.z,
  nil, nil, nil, true)
assert(not returned and returnReason:find("return path blocked", 1, true))
assert(#dugDirections == digCount, "a full-inventory return must not dig additional blocks")

print("MineSwarm pose movement tests passed")
