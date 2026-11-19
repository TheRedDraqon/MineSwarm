local pose
local slots, selected, drops, dug, pauses, alerts
local fillOnDig, chestPresent
local blocks

local function key(x, y, z) return x .. "," .. y .. "," .. z end

package.preload["shared.util"] = function() return dofile("shared/util.lua") end
package.preload["shared.pose"] = function()
  return {
    isProtected = function(block) return block.name == "allthemodium:ore" end,
    turnTo = function(current, direction) current.dir = direction end,
    moveTo = function(current, x, y, z, alert, _, tick)
      current.x, current.y, current.z = x, y, z
      if tick then tick(current) end
      return true
    end,
  }
end
turtle = {
  getFuelLevel = function() return "unlimited" end,
  getItemCount = function(slot) return slots[slot] or 0 end,
  inspect = function()
    if chestPresent then return true, { name = "minecraft:chest" } end
    return false
  end,
  select = function(slot) selected = slot end,
  drop = function()
    drops = drops + slots[selected]
    slots[selected] = 0
    return true
  end,
  inspectDown = function()
    local block = blocks[key(pose.x, pose.y - 1, pose.z)]
    return block ~= nil, block and { name = block }
  end,
  digDown = function()
    local blockKey = key(pose.x, pose.y - 1, pose.z)
    if not blocks[blockKey] then return false end
    blocks[blockKey] = nil
    dug = dug + 1
    if fillOnDig then
      for i = 1, 16 do slots[i] = 1 end
      fillOnDig = false
    end
    return true
  end,
  down = function() return true end,
}

local miner = dofile("drone/miner.lua")
local function reset()
  pose = { x = 0, y = 0, z = 0, dir = 0 }
  slots, selected, drops, dug, pauses, alerts = {}, 1, 0, 0, 0, 0
  blocks = {}
  fillOnDig = false
  chestPresent = true
end
local function callbacks()
  return {
    tick = function() end,
    setState = function() end,
    progress = function() end,
    alert = function() alerts = alerts + 1 end,
    waitForSpace = function()
      pauses = pauses + 1
      slots[1] = 0
    end,
  }
end
local function task(chest, y1, y2)
  return {
    bounds = { x1 = 0, x2 = 0, y1 = y1, y2 = y2, z1 = 0, z2 = 0 },
    home = { x = 0, y = 4, z = 0, dropDir = 2 }, chest = chest,
  }
end

reset()
for y = -21, -1 do blocks[key(0, y, 0)] = "minecraft:stone" end
for slot = 1, 16 do slots[slot] = 1 end
local ok, reason, progress = miner.run(pose, task(false, -21, -1), callbacks(), 0)
assert(ok, reason)
assert(pauses == 1 and drops == 0, "a full inventory without a chest must pause for manual clearing")
assert(dug == 21 and progress == 1, "inclusive Osmium range must mine 21 levels")

reset()
blocks[key(0, -1, 0)] = "minecraft:stone"
fillOnDig = true
ok, reason, progress = miner.run(pose, task(true, -1, -1), callbacks(), 0)
assert(ok, reason)
assert(drops == 16 and pauses == 0, "a full inventory must be deposited at the detected chest")
assert(dug == 1 and progress == 1)

reset()
for slot = 1, 16 do slots[slot] = 1 end
chestPresent = false
ok, reason = miner.run(pose, task(true, -1, -1), callbacks(), 0)
assert(not ok and reason:find("Chest is missing", 1, true) and drops == 0,
  "missing chest must not cause items to be dropped on the ground")

reset()
blocks[key(0, -1, 0)] = "allthemodium:ore"
ok, reason = miner.run(pose, task(false, -2, -1), callbacks(), 0)
assert(ok, reason)
assert(alerts == 1 and dug == 0, "protected ore must be reported and left intact")

print("MineSwarm mining and inventory tests passed")
