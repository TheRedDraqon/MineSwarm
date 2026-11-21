local poseLib = require("shared.pose")
local util = require("shared.util")
local homeLib = require("drone.home")

local M = {}
local fuelTarget, fuelReserve = 10000, 100

local function isChest(name)
  return type(name) == "string" and name:lower():match("chest$") ~= nil
end

function M.chestSlot()
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and isChest(detail.name) then return slot, detail.name end
  end
end

function M.refuel(required, fuelName, targetFuel)
  local level = turtle.getFuelLevel()
  if level == "unlimited" then return true end
  local limit = turtle.getFuelLimit()
  fuelName = fuelName or "minecraft:coal"
  local target = math.max(targetFuel or fuelTarget, required or 0)
  if type(limit) == "number" then target = math.min(target, limit) end
  local selected = turtle.getSelectedSlot()
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and detail.name == fuelName then
      turtle.select(slot)
      while turtle.getItemCount(slot) > 0 and turtle.getFuelLevel() < target do
        local before = turtle.getFuelLevel()
        local ok, reason = turtle.refuel(1)
        if not ok or turtle.getFuelLevel() <= before then
          turtle.select(selected)
          return false, "Cannot refuel with " .. fuelName .. ": " .. tostring(reason or "fuel did not increase")
        end
      end
    end
  end
  turtle.select(selected)
  return true
end

function M.takeFuel(required, fuelName, targetFuel)
  fuelName = fuelName or "minecraft:coal"
  local found, block = turtle.inspectUp()
  if not found or not isChest(block.name) then return false, "Fuel chest missing above the starting position" end
  local empty
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then empty = slot; break end
  end
  if not empty then return false, "Turtle inventory is full" end
  local selected = turtle.getSelectedSlot()
  turtle.select(empty)
  local sucked, reason = turtle.suckUp()
  if not sucked then
    turtle.select(selected)
    return false, "Cannot take fuel from supply chest: " .. tostring(reason or "empty")
  end
  local detail = turtle.getItemDetail(empty)
  if not detail or detail.name ~= fuelName then
    local returned, returnReason = turtle.dropUp()
    turtle.select(selected)
    if not returned then return false, "Cannot return wrong item to supply chest: " .. tostring(returnReason), true end
    return false, "Supply chest must contain only " .. (fuelName == "minecraft:coal" and "coal" or fuelName)
  end
  turtle.select(selected)
  local ok, refuelReason = M.refuel(required, fuelName, targetFuel)
  if not ok then return false, refuelReason, true end
  return true
end

function M.takeCoal(required)
  return M.takeFuel(required)
end

local function surfaceDistance(pose, task)
  local surface, startY = task.start, task.bounds.y2 + 1
  if pose.x == surface.x and pose.z == surface.z then return math.abs(pose.y - surface.y) end
  return math.abs(pose.y - startY) + math.abs(pose.x - surface.x)
    + math.abs(pose.z - surface.z) + math.abs(startY - surface.y)
end

local function fuelCheck(pose, task)
  if not task.logistics and task.format ~= 4 then return true end
  local limit = turtle.getFuelLimit()
  local target = task.format == 4 and type(limit) == "number"
    and math.ceil(limit * task.fuelPercent / 100) or nil
  local ok, reason = M.refuel(nil, task.format == 4 and "minecraft:charcoal" or nil, target)
  if not ok then return false, reason end
  local fuel = turtle.getFuelLevel()
  if fuel ~= "unlimited" and fuel <= surfaceDistance(pose, task) + fuelReserve then
    return false, "fuel_low"
  end
  return true
end

local function move(pose, x, y, z, callbacks, watchInventory, noDig, task)
  local ok, reason = poseLib.moveTo(pose, x, y, z, callbacks.alert, nil, function(current)
    callbacks.tick(current)
    if task then
      local ready, fuelReason = fuelCheck(current, task)
      if not ready then return false, fuelReason end
    end
    if watchInventory and util.inventoryFull() then return false, "inventory_full" end
  end, noDig)
  if not ok then return false, tostring(reason) end
  return true
end

local function returnMove(pose, x, y, z, callbacks)
  while true do
    local full = util.inventoryFull()
    local ok, reason = move(pose, x, y, z, callbacks, not full, full)
    if ok or (reason == "inventory_full" and pose.x == x and pose.y == y and pose.z == z) then
      return true
    end
    if reason == "inventory_full" or (full and reason:find("return path blocked by ", 1, true)) then
      callbacks.waitForSpace()
    else
      return false, reason
    end
  end
end

local function unload(pose, task, callbacks)
  local home, startY = task.home, task.bounds.y2 + 1
  callbacks.setState("RETURNING")
  local ok, reason = true, nil
  if pose.x ~= home.x or pose.y ~= home.y or pose.z ~= home.z then
    ok, reason = returnMove(pose, home.x, startY, home.z, callbacks)
    if ok then ok, reason = returnMove(pose, home.x, home.y, home.z, callbacks) end
  end
  if not ok then return false, "Cannot return to chest: " .. reason end
  poseLib.turnTo(pose, home.dropDir)
  local found, block = turtle.inspect()
  if not found or not isChest(block.name) then
    return false, "Chest is missing at home; refusing to drop items"
  end
  for slot = 1, 16 do
    local detail = task.logistics and turtle.getItemDetail(slot)
    if turtle.getItemCount(slot) > 0 and not (detail and detail.name == "minecraft:coal") then
      turtle.select(slot)
      if not turtle.drop() then return false, "Chest unavailable or full at home" end
    end
  end
  for slot = 1, 16 do
    local detail = task.logistics and turtle.getItemDetail(slot)
    if turtle.getItemCount(slot) > 0 and not (detail and detail.name == "minecraft:coal") then
      return false, "Chest could not accept all items"
    end
  end
  callbacks.setState("MINING")
  return true
end

local function refuelAtSurface(pose, task, callbacks, returnDistance)
  local surface = task.start
  local startY = task.bounds.y2 + 1
  callbacks.setState("REFUELING")
  local ok, reason
  if pose.x ~= surface.x or pose.z ~= surface.z then
    ok, reason = returnMove(pose, surface.x, startY, surface.z, callbacks)
    if not ok then return false, "Cannot reach fuel shaft: " .. reason end
  end
  if task.chest and util.inventoryFull() and pose.y < startY then
    ok, reason = returnMove(pose, surface.x, startY, surface.z, callbacks)
    if not ok then return false, "Cannot reach dump before refueling: " .. reason end
  end
  if task.chest and util.inventoryFull() and pose.y == startY then
    ok, reason = unload(pose, task, callbacks)
    if not ok then return false, reason end
    callbacks.setState("REFUELING")
  end
  ok, reason = returnMove(pose, surface.x, surface.y, surface.z, callbacks)
  if not ok then return false, "Cannot reach surface fuel chest: " .. reason end

  local required = returnDistance * 2 + fuelReserve + 1
  while true do
    ok, reason = M.refuel(required + 1)
    if not ok then return false, reason end
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then return true end
    local found, block = turtle.inspectUp()
    if not found or not isChest(block.name) then
      callbacks.waitForFuel("Fuel chest missing above the starting position")
    else
      local limit = turtle.getFuelLimit()
      local target = math.max(fuelTarget, required + 1)
      if type(limit) == "number" then target = math.min(target, limit) end
      local shortage = "Supply chest needs coal"
      while turtle.getFuelLevel() < target do
        local empty
        for slot = 1, 16 do
          if turtle.getItemCount(slot) == 0 then empty = slot; break end
        end
        if not empty then
          callbacks.waitForSpace()
        else
          local fatal
          ok, reason, fatal = M.takeCoal(required + 1)
          if not ok then
            if fatal then return false, reason end
            shortage = reason
            break
          end
        end
      end
      fuel = turtle.getFuelLevel()
      if fuel >= target and fuel > required then return true end
      if fuel >= target then
        shortage = "Fuel capacity is too low for the return trip"
      end
      callbacks.waitForFuel(shortage .. "; need more than " .. required .. " fuel to resume safely")
    end
  end
end

local function samePosition(a, b)
  return a.x == b.x and a.y == b.y and a.z == b.z
end

local function homeService(pose, task, callbacks, finish)
  local home = task.home
  if not task.service then
    task.service = {
      stage = "HOME",
      work = { x = pose.x, y = pose.y, z = pose.z, dir = pose.dir },
      returnToWork = not finish and not samePosition(pose, home),
    }
    callbacks.checkpoint()
  end
  local service = task.service
  local function wait(message)
    callbacks.waitForService(message)
  end
  if service.stage == "HOME" then
    callbacks.setState("RETURNING")
    while not samePosition(pose, home) do
      callbacks.tick(pose)
      local ok, reason
      if task.useCore then
        if not samePosition(pose, service.work) then
          wait("Unexpected position during home warp; return turtle to its saved work point or home")
        else
          ok, reason = homeLib.warp(callbacks.equipment, callbacks.checkpoint, pose, home, "Home",
            service.returnToWork,
            function() callbacks.tick(pose) end)
          if not ok then wait(reason) end
        end
      else
        ok, reason = true, nil
        if pose.x ~= home.x or pose.z ~= home.z then
          ok, reason = returnMove(pose, home.x, task.bounds.y2 + 1, home.z, callbacks)
        end
        if ok then ok, reason = returnMove(pose, home.x, home.y, home.z, callbacks) end
        if not ok then wait("Cannot return home: " .. reason) end
      end
    end
    service.stage = "SERVICE"
    callbacks.checkpoint()
  end
  if service.stage == "SERVICE" then
    callbacks.setState("REFUELING")
    poseLib.turnTo(pose, home.dropDir)
    while true do
      callbacks.tick(pose)
      local found, block = turtle.inspect()
      if found and isChest(block.name) then break end
      wait("Item chest missing behind home")
    end
    for slot = 1, 16 do
      local item = turtle.getItemDetail(slot)
      if item and item.name ~= "minecraft:charcoal"
        and item.name ~= "advancedperipherals:end_automata_core" then
        turtle.select(slot)
        while turtle.getItemCount(slot) > 0 do
          callbacks.tick(pose)
          local ok, reason = turtle.drop()
          if not ok then wait("Cannot unload at home: " .. tostring(reason or "chest full")) end
        end
      end
    end
    local required = 0
    if service.returnToWork then
      if task.useCore then
        while true do
          callbacks.tick(pose)
          local ok, result = homeLib.cost(callbacks.equipment, callbacks.checkpoint, "MineSwarmWork")
          if ok then
            required = math.max(result * 2, surfaceDistance(service.work, task)) + fuelReserve + 1
            break
          end
          wait(result)
        end
      else
        required = surfaceDistance(service.work, task) * 2 + fuelReserve + 1
      end
    end
    local limit = turtle.getFuelLimit()
    local target = type(limit) == "number" and math.ceil(limit * task.fuelPercent / 100) or 0
    while true do
      callbacks.tick(pose)
      local ok, reason = M.refuel(required, "minecraft:charcoal", target)
      if not ok then wait(reason) end
      local level = turtle.getFuelLevel()
      if level == "unlimited" or (level >= target and level >= required) then break end
      if type(limit) == "number" and required > limit then
        callbacks.waitForFuel("Fuel capacity is too low for a safe return to work")
      else
        local fatal
        ok, reason, fatal = M.takeFuel(required, "minecraft:charcoal", target)
        if not ok then
          if fatal then wait(reason) else callbacks.waitForFuel(reason) end
        end
      end
    end
    service.stage = "WORK"
    callbacks.checkpoint()
  end
  if service.stage == "WORK" and service.returnToWork then
    while not samePosition(pose, service.work) do
      callbacks.tick(pose)
      local ok, reason
      if task.useCore then
        if not samePosition(pose, home) then
          wait("Unexpected position during return warp; return turtle to home or its saved work point")
        else
          ok, reason = homeLib.warp(callbacks.equipment, callbacks.checkpoint, pose,
            service.work, "MineSwarmWork", false, function() callbacks.tick(pose) end)
          if not ok then wait(reason) end
        end
      else
        ok, reason = true, nil
        if service.work.x ~= home.x or service.work.z ~= home.z then
          ok, reason = returnMove(pose, home.x, task.bounds.y2 + 1, home.z, callbacks)
        end
        if ok and (service.work.x ~= home.x or service.work.z ~= home.z) then
          ok, reason = returnMove(pose, service.work.x, task.bounds.y2 + 1, service.work.z, callbacks)
        end
        if ok then ok, reason = returnMove(pose, service.work.x, service.work.y, service.work.z, callbacks) end
        if not ok then wait("Cannot return to work: " .. reason) end
      end
    end
    poseLib.turnTo(pose, service.work.dir)
  end
  task.service, task.needsInitialFuel = nil, nil
  callbacks.checkpoint()
  return true
end

local function space(pose, task, callbacks)
  if task.format == 4 and (task.service or task.needsInitialFuel) then
    local ok, reason = homeService(pose, task, callbacks)
    if not ok then return false, reason end
  end
  local ready, reason = fuelCheck(pose, task)
  if not ready then
    if reason ~= "fuel_low" then return false, reason end
    if task.format == 4 then
      local ok, serviceReason = homeService(pose, task, callbacks)
      if not ok then return false, serviceReason end
      return true, true
    end
    local distance = surfaceDistance(pose, task)
    local ok, refuelReason = refuelAtSurface(pose, task, callbacks, distance)
    if not ok then return false, refuelReason end
    return true, true
  end
  if not util.inventoryFull() then return true, false end
  if task.format == 4 then
    local ok, serviceReason = homeService(pose, task, callbacks)
    if not ok then return false, serviceReason end
    if util.inventoryFull() then callbacks.waitForSpace() end
    return true, true
  end
  if task.chest then
    local ok, reason = unload(pose, task, callbacks)
    if not ok then return false, reason end
    if util.inventoryFull() then callbacks.waitForSpace() end
    return true, true
  end
  callbacks.waitForSpace()
  return true, false
end

local function moveToWork(pose, task, x, y, z, callbacks)
  while true do
    local ok, reason = space(pose, task, callbacks)
    if not ok then return false, reason end
    ok, reason = move(pose, x, y, z, callbacks, true, false, task)
    if ok then return true end
    if reason ~= "inventory_full" and reason ~= "fuel_low" then return false, reason end
  end
end

local function setupDump(pose, task, callbacks)
  if task.logistics.phase == "READY" then return true end
  local home, dump = task.home, task.dump
  local ok, reason = moveToWork(pose, task, home.x, home.y, home.z, callbacks)
  if not ok then return false, "Cannot reach dump site: " .. reason end
  poseLib.turnTo(pose, dump.dropDir)
  local found, block = turtle.inspect()
  if task.logistics.phase == "PLACING" and found and block.name == task.logistics.chestName then
    task.logistics.phase, task.chest = "READY", true
    poseLib.turnTo(pose, (dump.dropDir + 2) % 4)
    callbacks.checkpoint()
    return true
  end
  if found and isChest(block.name) then return false, "Dump position already contains a chest" end
  if found then
    local dug, digReason = poseLib.digBlock(turtle.dig, turtle.inspect, dump, callbacks.alert)
    if not dug then return false, "Cannot clear dump position: " .. digReason end
  end
  local slot, chestName = M.chestSlot()
  if not slot then return false, "No chest in turtle inventory for the dump" end
  task.logistics.phase, task.logistics.chestName = "PLACING", chestName
  callbacks.checkpoint()
  turtle.select(slot)
  local placed, placeReason = turtle.place()
  if not placed then return false, "Cannot place dump chest: " .. tostring(placeReason) end
  found, block = turtle.inspect()
  if not found or not isChest(block.name) then return false, "Placed dump is not a chest" end
  task.logistics.phase, task.chest = "READY", true
  poseLib.turnTo(pose, (dump.dropDir + 2) % 4)
  callbacks.checkpoint()
  return true
end

function M.run(pose, task, callbacks, progress)
  local bounds = task.bounds
  local width = bounds.x2 - bounds.x1 + 1
  local length = bounds.z2 - bounds.z1 + 1
  local total = width * length
  local startY = bounds.y2 + 1
  local index = progress or 0

  if task.logistics then
    local ok, reason = setupDump(pose, task, callbacks)
    if not ok then return false, reason, index end
  end

  for xi = 0, width - 1 do
    local x = bounds.x1 + xi
    for zi = 0, length - 1 do
      local z = bounds.z1 + (xi % 2 == 0 and zi or length - 1 - zi)
      local column = xi * length + zi + 1
      if column > index then
        local finished = false
        while not finished do
          local ok, result = space(pose, task, callbacks)
          if not ok then return false, result, index end
          callbacks.setState("MINING")
          ok, result = moveToWork(pose, task, x, startY, z, callbacks)
          if not ok then return false, "Cannot reach column: " .. result, index end
          local returned = false
          while pose.y > bounds.y1 do
            callbacks.tick(pose)
            ok, result = space(pose, task, callbacks)
            if not ok then return false, result, index end
            if result then returned = true; break end
            if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 1 then
              return false, "Out of fuel at " .. pose.x .. "," .. pose.y .. "," .. pose.z, index
            end
            local target = { x = pose.x, y = pose.y - 1, z = pose.z }
            if turtle.detectDown() then
              local dug, digReason, unbreakable = poseLib.digBlock(
                turtle.digDown, turtle.inspectDown, target, callbacks.alert)
              if not dug then
                if unbreakable then break end
                return false, "Cannot dig column: " .. digReason, index
              end
            end
            if not turtle.down() then
              return false, "Cannot descend at " .. target.x .. "," .. target.y .. "," .. target.z, index
            end
            pose.y = pose.y - 1
            callbacks.tick(pose)
          end
          if not returned then
            ok, result = space(pose, task, callbacks)
            if not ok then return false, result, index end
            if not result then
              ok, result = moveToWork(pose, task, x, startY, z, callbacks)
              if not ok then return false, "Cannot leave column: " .. result, index end
              finished = true
            end
          end
        end
        index = column
        callbacks.progress(index, total, pose)
      end
    end
  end
  if task.format == 4 then
    local ok, reason = homeService(pose, task, callbacks, true)
    if not ok then return false, reason, index end
    if not samePosition(pose, task.home) then
      ok, reason = homeService(pose, task, callbacks, true)
      if not ok then return false, reason, index end
    end
    poseLib.turnTo(pose, 0)
    callbacks.checkpoint()
  elseif task.logistics then
    local ok, reason = space(pose, task, callbacks)
    if not ok then return false, reason, index end
    for slot = 1, 16 do
      local item = turtle.getItemDetail(slot)
      if item and item.name ~= "minecraft:coal" then
        ok, reason = unload(pose, task, callbacks)
        if not ok then return false, "Cannot unload completed quarry: " .. reason, index end
        break
      end
    end
  end
  return true, nil, index
end

return M
