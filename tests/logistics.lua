local world, position, slots, selected, fuel, fuelLimit, supply, supplyName, drops, pauses, checkpoints, fillOnDig
local upgrade, points, warps, failWarp, cooldowns
local vectors = {
  [0] = { x = 0, z = -1 }, [1] = { x = 1, z = 0 },
  [2] = { x = 0, z = 1 }, [3] = { x = -1, z = 0 },
}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
local function at(dx, dy, dz) return key(position.x + dx, position.y + dy, position.z + dz) end
local function front()
  local d = vectors[position.dir]
  return at(d.x, 0, d.z)
end
local function detail(slot)
  local item = slots[slot]
  return item and { name = item.name, count = item.count } or nil
end
local function dig(where)
  local block = world[where]
  if not block then return false, "Nothing to dig here" end
  if block.unbreakable then return false, "Cannot break unbreakable block" end
  local free = false
  for slot = 1, 16 do if not slots[slot] then free = true; break end end
  assert(free, "return route must not dig while inventory is full")
  world[where] = nil
  if fillOnDig and block.name == "minecraft:deepslate" then
    for slot = 1, 16 do
      if not slots[slot] then slots[slot] = { name = "minecraft:cobblestone", count = 1 } end
    end
    fillOnDig = false
  elseif block.name == "minecraft:deepslate" then
    for slot = 1, 16 do
      if not slots[slot] then
        slots[slot] = { name = "minecraft:cobbled_deepslate", count = 1 }
        break
      end
    end
  end
  return true
end
local function travel(dx, dy, dz)
  if world[at(dx, dy, dz)] then return false, "Movement obstructed" end
  if fuel ~= "unlimited" then
    if fuel < 1 then return false, "Out of fuel" end
    fuel = fuel - 1
  end
  position.x, position.y, position.z = position.x + dx, position.y + dy, position.z + dz
  return true
end
local function inspect(where)
  if world[where] then return true, { name = world[where].name } end
  return false, "No block to inspect"
end

turtle = {
  getFuelLevel = function() return fuel end,
  getFuelLimit = function() return fuelLimit end,
  getSelectedSlot = function() return selected end,
  select = function(slot) selected = slot; return true end,
  getItemCount = function(slot) return slots[slot] and slots[slot].count or 0 end,
  getItemDetail = detail,
  refuel = function()
    local item = slots[selected]
    if not item or (item.name ~= "minecraft:coal" and item.name ~= "minecraft:charcoal") then
      return false, "Not fuel"
    end
    item.count, fuel = item.count - 1, math.min(fuelLimit, fuel + 80)
    if item.count == 0 then slots[selected] = nil end
    return true
  end,
  turnLeft = function() position.dir = (position.dir + 3) % 4; return true end,
  turnRight = function() position.dir = (position.dir + 1) % 4; return true end,
  forward = function() local d = vectors[position.dir]; return travel(d.x, 0, d.z) end,
  up = function() return travel(0, 1, 0) end,
  down = function() return travel(0, -1, 0) end,
  detect = function() return world[front()] ~= nil end,
  detectUp = function() return world[at(0, 1, 0)] ~= nil end,
  detectDown = function() return world[at(0, -1, 0)] ~= nil end,
  inspect = function() return inspect(front()) end,
  inspectUp = function() return inspect(at(0, 1, 0)) end,
  inspectDown = function() return inspect(at(0, -1, 0)) end,
  dig = function() return dig(front()) end,
  digUp = function() return dig(at(0, 1, 0)) end,
  digDown = function() return dig(at(0, -1, 0)) end,
  place = function()
    if world[front()] or not slots[selected] then return false, "Cannot place" end
    world[front()] = { name = slots[selected].name }
    slots[selected].count = slots[selected].count - 1
    if slots[selected].count == 0 then slots[selected] = nil end
    return true
  end,
  drop = function()
    if not world[front()] or not world[front()].name:match("chest$") then return false end
    drops = drops + slots[selected].count
    slots[selected] = nil
    return true
  end,
  suckUp = function()
    if not world[at(0, 1, 0)] or supply == 0 or slots[selected] then return false, "No items to take" end
    local count = math.min(supply, 64)
    slots[selected], supply = { name = supplyName, count = count }, supply - count
    return true
  end,
  dropUp = function()
    if not slots[selected] then return false end
    supply = supply + slots[selected].count
    slots[selected] = nil
    return true
  end,
  equipRight = function()
    local item = slots[selected]
    if item and item.name ~= "advancedperipherals:end_automata_core"
      and item.name ~= "minecraft:diamond_pickaxe" then return false, "Not a valid upgrade" end
    slots[selected], upgrade = upgrade, item
    return true
  end,
}
local core
core = {
  points = function()
    local names = {}
    for name in pairs(points) do names[#names + 1] = name end
    return names
  end,
  savePoint = function(name)
    points[name] = { x = position.x, y = position.y, z = position.z }
    return true
  end,
  deletePoint = function(name) points[name] = nil; return true end,
  distanceToPoint = function(name)
    local p = points[name]
    if not p then return nil, "missing" end
    return math.abs(position.x - p.x) + math.abs(position.y - p.y) + math.abs(position.z - p.z)
  end,
  estimateWarpCost = function(name) return core.distanceToPoint(name) end,
  getOperationCooldown = function(name)
    assert(name == "warp")
    if cooldowns > 0 then cooldowns = cooldowns - 1; return 1000 end
    return 0
  end,
  warpToPoint = function(name)
    if failWarp then return nil, "simulated blocked warp" end
    local p = assert(points[name])
    warps[#warps + 1] = name
    if fuel ~= "unlimited" then fuel = fuel - core.distanceToPoint(name) end
    position.x, position.y, position.z = p.x, p.y, p.z
    return true
  end,
}
peripheral = { wrap = function(side)
  if side == "right" and upgrade and upgrade.name == "advancedperipherals:end_automata_core" then
    return core
  end
end }
gps = { locate = function() return position.x, position.y, position.z end }
os.sleep = function() end
local miner = dofile("drone/miner.lua")
local homeLib = require("drone.home")

local function reset(level)
  position, fuel, selected = { x = 0, y = 4, z = 0, dir = 0 }, level, 1
  world = { [key(0, 5, 0)] = { name = "minecraft:chest" },
    [key(0, 0, 0)] = { name = "minecraft:deepslate" } }
  slots, supply, drops, pauses, checkpoints, fillOnDig = {}, 0, 0, 0, 0, false
  supplyName = "minecraft:coal"
  fuelLimit = 20000
  upgrade, points, warps, failWarp, cooldowns =
    { name = "minecraft:diamond_pickaxe", count = 1 }, {}, {}, false, 0
end
local function task()
  return {
    format = 3, start = { x = 0, y = 4, z = 0 },
    bounds = { x1 = 0, x2 = 0, y1 = 0, y2 = 0, z1 = 0, z2 = 0 },
    dump = { x = -1, y = 1, z = 0, dropDir = 3 },
    home = { x = 0, y = 1, z = 0, dropDir = 3 },
    chest = false, logistics = { phase = "PENDING" },
  }
end
local function callbacks()
  return {
    tick = function() end, setState = function() end, progress = function() end,
    alert = function() error("unexpected waypoint") end,
    checkpoint = function() checkpoints = checkpoints + 1 end,
    waitForSpace = function() error("unexpected full-inventory pause") end,
    waitForFuel = function()
      assert(position.x == 0 and position.y == 4 and position.z == 0,
        "fuel shortage must pause at the surface chest")
      pauses = pauses + 1
      supply = 200
    end,
  }
end

reset(9800)
slots[3], selected = { name = "minecraft:coal", count = 4 }, 7
assert(miner.refuel())
assert(fuel == 10040 and slots[3].count == 1 and selected == 7,
  "refueling must reach 10000, consume only needed coal, and restore the selected slot")

reset(500)
slots[3] = { name = "minecraft:coal_block", count = 1 }
assert(miner.refuel() and fuel == 500 and slots[3].count == 1, "only coal should be consumed")

reset(10000)
slots[3] = { name = "minecraft:coal", count = 10 }
assert(miner.refuel(10300) and fuel == 10320 and slots[3].count == 6,
  "long returns must refuel beyond the usual target when needed")

reset(100)
supply, supplyName, selected = 5, "minecraft:diamond", 7
local taken, takeReason = miner.takeCoal()
assert(not taken and takeReason:find("only coal", 1, true) and supply == 5 and selected == 7,
  "non-coal supply items must be returned rather than consumed")

reset("unlimited")
slots[1], slots[2], fillOnDig = { name = "enderstorage:ender_chest", count = 1 },
  { name = "minecraft:coal", count = 3 }, true
local work = task()
local pose = { x = 0, y = 4, z = 0, dir = 0 }
local ok, reason, progress = miner.run(pose, work, callbacks(), 0)
assert(ok, reason)
assert(progress == 1 and work.logistics.phase == "READY" and checkpoints >= 2)
assert(world[key(-1, 1, 0)].name == "enderstorage:ender_chest", "dump chest must be placed underground")
assert(drops == 15 and slots[2].name == "minecraft:coal", "unloading must preserve carried coal")
assert(not world[key(0, 0, 0)], "quarry block must be mined")

reset(102)
slots[1], supply = { name = "minecraft:chest", count = 1 }, 1
work, pose = task(), { x = 0, y = 4, z = 0, dir = 0 }
ok, reason, progress = miner.run(pose, work, callbacks(), 0)
assert(ok, reason)
assert(pauses == 1 and fuel >= 9990 and work.logistics.phase == "READY" and drops == 1,
  "low fuel must return, pause for more coal, refuel, and continue the job")

reset(225)
position, world = { x = 125, y = 1, z = 0, dir = 0 }, {
  [key(0, 2, 0)] = { name = "minecraft:chest" },
  [key(-1, 1, 0)] = { name = "minecraft:chest" },
  [key(60, 1, 0)] = { name = "minecraft:stone" },
}
work, pose = task(), { x = 125, y = 1, z = 0, dir = 0 }
work.start.y, work.bounds.x2 = 1, 125
work.chest, work.logistics.phase = true, "READY"
local longCallbacks = callbacks()
longCallbacks.waitForFuel = function()
  assert(position.x == 0 and position.y == 1 and position.z == 0 and fuel == 100,
    "a 125-block return must start at 225 fuel and leave 100 at the surface")
  pauses, supply = pauses + 1, 200
end
ok, reason, progress = miner.run(pose, work, longCallbacks, 125)
assert(ok, reason)
assert(pauses == 1 and progress == 126, "the quarry must resume after replenishment")
assert(not world[key(60, 1, 0)], "a fuel return with inventory space must clear its route")

reset("unlimited")
position, world = { x = 2, y = 1, z = 0, dir = 0 }, {
  [key(0, 5, 0)] = { name = "minecraft:chest" },
  [key(-1, 1, 0)] = { name = "minecraft:chest" },
  [key(1, 1, 0)] = { name = "minecraft:stone" },
}
for slot = 1, 16 do slots[slot] = { name = "minecraft:cobblestone", count = 1 } end
work, pose = task(), { x = 2, y = 1, z = 0, dir = 0 }
work.bounds.x2, work.chest, work.logistics.phase = 2, true, "READY"
local blockedCallbacks = callbacks()
blockedCallbacks.waitForSpace = function() pauses = pauses + 1; slots[1] = nil end
ok, reason, progress = miner.run(pose, work, blockedCallbacks, 2)
assert(ok, reason)
assert(pauses == 1 and drops == 15 and not world[key(1, 1, 0)],
  "a full-inventory return must wait for space before clearing an obstructed route")

reset("unlimited")
slots[1] = { name = "minecraft:chest", count = 1 }
world[key(-1, 1, 0)] = { name = "minecraft:chest" }
work, pose = task(), { x = 0, y = 4, z = 0, dir = 0 }
ok, reason = miner.run(pose, work, callbacks(), 0)
assert(not ok and reason:find("already contains a chest", 1, true))
assert(world[key(-1, 1, 0)] and slots[1], "existing chests must not be dug or replaced")

reset("unlimited")
world[key(-1, 1, 0)] = { name = "minecraft:chest" }
work, pose = task(), { x = 0, y = 4, z = 0, dir = 0 }
work.logistics = { phase = "PLACING", chestName = "minecraft:chest" }
ok, reason = miner.run(pose, work, callbacks(), 0)
assert(ok, reason)
assert(work.logistics.phase == "READY", "a placed chest must be recovered after restart")

print("MineSwarm fuel and dump logistics tests passed")

local function homeTask(useCore)
  return {
    format = 4, fuelPercent = 50, useCore = useCore, needsInitialFuel = true,
    start = { x = 0, y = 4, z = 0 },
    home = { x = 0, y = 4, z = 0, dropDir = 2 },
    bounds = { x1 = 0, x2 = 0, y1 = 0, y2 = 0, z1 = 0, z2 = 0 },
  }
end
local function homeCallbacks(equipment)
  local cb = callbacks()
  cb.equipment = equipment
  cb.waitForFuel = function()
    assert(position.x == 0 and position.y == 4 and position.z == 0)
    pauses, supply = pauses + 1, 200
  end
  cb.waitForService = function(message) error("unexpected service pause: " .. message) end
  return cb
end

reset(1000)
world[key(0, 4, 1)] = { name = "enderchests:ender_chest" }
supplyName = "minecraft:charcoal"
work, pose = homeTask(false), { x = 0, y = 4, z = 0, dir = 0 }
fillOnDig = true
ok, reason, progress = miner.run(pose, work, homeCallbacks({}), 0)
assert(ok, reason)
assert(pauses == 1 and progress == 1 and drops == 15 and fuel >= 10000)
assert(position.y == 4 and position.dir == 0 and #warps == 0,
  "a turtle without a core must walk home, unload, refuel, and finish facing north")

reset(49800)
fuelLimit = 100000
slots[1] = { name = "minecraft:charcoal", count = 10 }
slots[2] = { name = "minecraft:coal", count = 10 }
assert(miner.refuel(nil, "minecraft:charcoal", math.ceil(fuelLimit * 0.5)))
assert(fuel == 50040 and slots[1].count == 7 and slots[2].count == 10,
  "50% of an advanced turtle's fuel limit must consume charcoal up to 50000, not coal")

reset(101)
position.y = 3
world[key(0, 4, 1)] = { name = "enderchests:ender_chest" }
supplyName = "minecraft:charcoal"
work, pose = homeTask(false), { x = 0, y = 3, z = 0, dir = 0 }
work.needsInitialFuel = nil
local verticalCallbacks = homeCallbacks({})
verticalCallbacks.waitForFuel = function()
  assert(position.y == 4 and fuel == 100, "return up the home shaft must use the direct route")
  pauses, supply = pauses + 1, 200
end
ok, reason, progress = miner.run(pose, work, verticalCallbacks, 0)
assert(ok, reason)
assert(pauses == 1 and progress == 1)

reset(12000)
world[key(0, 4, 1)] = { name = "enderchests:ender_chest" }
supplyName = "minecraft:charcoal"
slots[1] = { name = "advancedperipherals:end_automata_core", count = 1 }
slots[2] = { name = "minecraft:charcoal", count = 3 }
local equipment = {}
pose = { x = 0, y = 4, z = 0, dir = 0 }
assert(homeLib.register(equipment, pose, function() end))
assert(points.Home.y == 4 and upgrade.name == "minecraft:diamond_pickaxe")
fillOnDig, failWarp, cooldowns = true, true, 1
work = homeTask(true)
local cb = homeCallbacks(equipment)
cb.waitForService = function(message)
  assert(message:find("simulated blocked warp", 1, true))
  assert(upgrade.name == "minecraft:diamond_pickaxe" and slots[1].name == "advancedperipherals:end_automata_core")
  pauses, failWarp = pauses + 1, false
end
ok, reason, progress = miner.run(pose, work, cb, 0)
assert(ok, reason)
assert(pauses == 1 and progress == 1 and #warps == 3)
assert(warps[1] == "Home" and warps[2] == "MineSwarmWork" and warps[3] == "Home")
assert(upgrade.name == "minecraft:diamond_pickaxe" and slots[1].name == "advancedperipherals:end_automata_core")
assert(slots[2].name == "minecraft:charcoal" and drops == 14 and position.dir == 0,
  "home service must preserve the core, mining upgrade and charcoal")
assert(cooldowns == 0, "warp cooldown must be waited out automatically")

reset(12000)
world[key(0, 4, 1)] = { name = "enderchests:ender_chest" }
supplyName = "minecraft:charcoal"
slots[1] = { name = "advancedperipherals:end_automata_core", count = 1 }
equipment, pose = {}, { x = 0, y = 4, z = 0, dir = 0 }
assert(homeLib.register(equipment, pose, function() end))
fillOnDig, work = true, homeTask(true)
cb = homeCallbacks(equipment)
cb.checkpoint = function()
  if #warps == 1 and equipment.swapSlot then error("simulated reboot after warp") end
end
local ran, restartReason = pcall(miner.run, pose, work, cb, 0)
assert(not ran and restartReason:find("simulated reboot after warp", 1, true))
assert(work.service.stage == "HOME" and position.y == 4 and equipment.swapSlot == 1)
assert(homeLib.restore(equipment, function() end))
cb = homeCallbacks(equipment)
ok, reason, progress = miner.run(pose, work, cb, 0)
assert(ok, reason)
assert(progress == 1 and #warps == 3 and warps[2] == "MineSwarmWork" and warps[3] == "Home")
assert(upgrade.name == "minecraft:diamond_pickaxe" and slots[1].name == "advancedperipherals:end_automata_core",
  "restart after a home warp must resume service and restore equipment")

reset(1000)
slots[1] = { name = "advancedperipherals:end_automata_core", count = 1 }
equipment, pose = {}, { x = 0, y = 4, z = 0, dir = 0 }
local interrupted = pcall(homeLib.withCore, equipment, function() end, function() error("simulated reboot") end)
assert(not interrupted and equipment.swapSlot == 1 and upgrade.name == "advancedperipherals:end_automata_core")
assert(homeLib.restore(equipment, function() end))
assert(not equipment.swapSlot and upgrade.name == "minecraft:diamond_pickaxe"
  and slots[1].name == "advancedperipherals:end_automata_core",
  "reboot recovery must restore the mining upgrade without losing the core")
points.Home = { x = 1, y = 4, z = 0 }
local registered, registerReason = homeLib.register(equipment, pose, function() end)
assert(not registered and registerReason:find("elsewhere", 1, true) and points.Home.x == 1)

print("MineSwarm home and End Automata tests passed")
