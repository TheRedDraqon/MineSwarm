package.preload["mineswarm.shared.config"] = function()
  return { gpsTimeout = 2, maxTravelSteps = 1000 }
end

local position = { x = 0, y = 64, z = 0 }
local direction = 0
local blockedDown
local alerts = {}
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
    local delta = vectors[direction]
    position.x, position.z = position.x + delta.x, position.z + delta.z
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
  inspect = function() return false end,
  dig = function() return false end,
  detect = function() return false end,
}
os.sleep = function() end

local poseLib = dofile("shared/pose.lua")
local pose = { x = 0, y = 64, z = 0, dir = 0 }
local ok, reason = poseLib.moveTo(pose, 3, 62, 2)
assert(ok, reason)
assert(pose.x == 3 and pose.y == 62 and pose.z == 2)
assert(position.x == pose.x and position.y == pose.y and position.z == pose.z)
assert(direction == pose.dir)

blockedDown = { y = pose.y - 1, data = { name = "allthemodium:allthemodium_ore" } }
local alerted, alertReason = poseLib.moveTo(pose, pose.x, pose.y - 1, pose.z,
  function(block, target) alerts[#alerts + 1] = { block = block, pos = target } end)
assert(not alerted and alertReason == "protected block")
assert(#alerts == 1 and alerts[1].pos.y == blockedDown.y)
assert(position.y == pose.y)

print("MineSwarm pose movement tests passed")
