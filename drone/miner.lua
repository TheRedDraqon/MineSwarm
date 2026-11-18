local poseLib = require("mineswarm.shared.pose")
local util = require("mineswarm.shared.util")
local config = require("mineswarm.shared.config")

local M = {}

local function countItems()
  local items = {}
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail then
      items[detail.name] = (items[detail.name] or 0) + detail.count
    end
  end
  return items
end

local function autoRefuel(threshold)
  if turtle.getFuelLevel() == "unlimited" then return true end
  while turtle.getFuelLevel() < threshold do
    local fuelSlot
    for slot = 1, 16 do
      local detail = turtle.getItemDetail(slot)
      if detail and (detail.name:find("coal", 1, true) or detail.name:find("charcoal", 1, true)) then
        fuelSlot = slot
        break
      end
    end
    if not fuelSlot then return false end
    local before = turtle.getFuelLevel()
    turtle.select(fuelSlot)
    if not turtle.refuel(1) or turtle.getFuelLevel() <= before then return false end
  end
  return true
end

local function clearColumn(pose, task, callbacks)
  local depth = task.bounds.y2 - task.bounds.y1 + 1
  for _ = 1, depth do
    if util.inventoryFull() then return true, "inventory_full" end
    local found, data = turtle.inspectDown()
    if found then
      local target = { x = pose.x, y = pose.y - 1, z = pose.z }
      if poseLib.isProtected(data) then
        callbacks.alert(data.name, target)
        return true, "protected"
      end
      if not turtle.digDown() then
        if util.inventoryFull() then return true, "inventory_full" end
        callbacks.alert(data.name or "unknown_block", target)
        return true, "undiggable"
      end
    end
    if not turtle.down() then
      local blocked, block = turtle.inspectDown()
      if util.inventoryFull() then return true, "inventory_full" end
      if blocked and poseLib.isProtected(block) then
        callbacks.alert(block.name, { x = pose.x, y = pose.y - 1, z = pose.z })
        return true, "protected"
      end
      return false, "Could not descend at " .. pose.x .. "," .. (pose.y - 1) .. "," .. pose.z
    end
    pose.y = pose.y - 1
    if not autoRefuel(1) then return true, "fuel_low" end
    callbacks.tick(pose)
  end

  local ok, reason = poseLib.moveTo(pose, pose.x, task.bounds.y2 + 1, pose.z,
    callbacks.alert, nil, callbacks.tick)
  if not ok then return false, "Could not return above column: " .. tostring(reason) end
  return true
end

local function unloadAtHome(pose, task, callbacks, fuelTarget)
  if task.home.dir ~= nil then poseLib.turnTo(pose, task.home.dir) end
  local before = countItems()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      if not turtle.drop() then return false, "Drop-off chest unavailable or blocked" end
    end
  end
  if util.slotCount() > 0 then return false, "Not all inventory items were unloaded" end
  callbacks.yield(before)
  if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < fuelTarget then
    local chest = peripheral.wrap("front")
    if not chest or type(chest.list) ~= "function" then
      return false, "No refuel inventory is connected in front at the FOB"
    end
    while turtle.getFuelLevel() < fuelTarget do
      local fuelSlot
      for slot, item in pairs(chest.list()) do
        local name = tostring(item.name):lower()
        if name:find("coal", 1, true) or name:find("charcoal", 1, true) then
          fuelSlot = slot
          break
        end
      end
      if not fuelSlot then break end
      turtle.select(1)
      if not turtle.suckFromSlot(fuelSlot, 16) then break end
      autoRefuel(fuelTarget)
    end
    if not autoRefuel(fuelTarget) then return false, "No usable refuel item at the FOB" end
  end
  return true
end

local function maybeReturn(pose, task, callbacks, force, fuelTarget)
  if force or util.inventoryFull() or not autoRefuel(fuelTarget) then
    callbacks.setState("RETURNING")
    local home = task.home
    local ok, reason = poseLib.moveTo(pose, home.x, config.transitY, home.z,
      callbacks.alert, nil, callbacks.tick)
    if ok then
      ok, reason = poseLib.moveTo(pose, home.x, home.y, home.z,
        callbacks.alert, nil, callbacks.tick)
    end
    if not ok then return false, "Unable to return to FOB: " .. tostring(reason) end
    ok, reason = unloadAtHome(pose, task, callbacks, fuelTarget)
    if not ok then return false, reason end
    callbacks.setState("MINING")
    return true, true
  end
  callbacks.setState("MINING")
  return true, false
end

function M.run(pose, task, callbacks, progress)
  local width = task.bounds.x2 - task.bounds.x1 + 1
  local length = task.bounds.z2 - task.bounds.z1 + 1
  local total = width * length
  local index = progress or 0
  local startY = task.bounds.y2 + 1
  local depth = task.bounds.y2 - task.bounds.y1 + 1
  local home = task.home
  local access = task.access or { x = task.bounds.x1 - 1, z = task.bounds.z1 - 1 }
  local xDistance = math.max(math.abs(task.bounds.x1 - home.x), math.abs(task.bounds.x2 - home.x),
    math.abs(access.x - home.x))
  local zDistance = math.max(math.abs(task.bounds.z1 - home.z), math.abs(task.bounds.z2 - home.z),
    math.abs(access.z - home.z))
  local fuelTarget = math.abs(config.transitY - startY)
    + math.abs(config.transitY - home.y)
    + xDistance + zDistance
    + depth * 2 + 100
  fuelTarget = math.max(config.lowFuel, fuelTarget)

  local ready, reason = maybeReturn(pose, task, callbacks, false, fuelTarget)
  if not ready then return false, reason, index end
  callbacks.setState("TRANSIT")
  local ok
  ok, reason = poseLib.moveTo(pose, pose.x, config.transitY, pose.z,
    callbacks.alert, nil, callbacks.tick)
  if ok then
    ok, reason = poseLib.moveTo(pose, access.x, config.transitY, access.z,
      callbacks.alert, nil, callbacks.tick)
  end
  if ok then
    ok, reason = poseLib.moveTo(pose, access.x, startY, access.z,
      callbacks.alert, nil, callbacks.tick)
  end
  if ok then
    ok, reason = poseLib.moveTo(pose, task.bounds.x1, startY, task.bounds.z1,
      callbacks.alert, nil, callbacks.tick)
  end
  if not ok then return false, "Unable to reach sector: " .. tostring(reason) end
  callbacks.setState("MINING")

  local transitNeeded = false
  for xi = 0, width - 1 do
    local x = task.bounds.x1 + xi
    local zOffsetStart = (xi % 2 == 0) and 0 or length - 1
    local zStep = (xi % 2 == 0) and 1 or -1
    for zi = 0, length - 1 do
      local z = task.bounds.z1 + zOffsetStart + (zi * zStep)
      local columnNumber = xi * length + zi + 1
      if columnNumber > index then
        local columnDone = false
        while not columnDone do
          if transitNeeded then
            ok, reason = poseLib.moveTo(pose, pose.x, config.transitY, pose.z,
              callbacks.alert, nil, callbacks.tick)
            if ok then
              ok, reason = poseLib.moveTo(pose, access.x, config.transitY, access.z,
                callbacks.alert, nil, callbacks.tick)
            end
            if ok then
              ok, reason = poseLib.moveTo(pose, access.x, startY, access.z,
                callbacks.alert, nil, callbacks.tick)
            end
            if ok then
              ok, reason = poseLib.moveTo(pose, x, startY, z,
                callbacks.alert, nil, callbacks.tick)
            end
            transitNeeded = false
          else
            ok, reason = poseLib.moveTo(pose, x, startY, z,
              callbacks.alert, nil, callbacks.tick)
          end
          if not ok then return false, "Transit between columns failed: " .. tostring(reason) end
          ok, reason = clearColumn(pose, task, callbacks)
          if not ok then return false, reason end
          if reason == "inventory_full" or reason == "fuel_low" then
            local returned, returnReason = maybeReturn(pose, task, callbacks, true, fuelTarget)
            if not returned then return false, returnReason, index end
            transitNeeded = true
          else
            columnDone = true
          end
        end
        index = columnNumber
        callbacks.progress(index, total, pose)
        if callbacks.recallRequested() then
          callbacks.setState("RETURNING")
          ok, reason = poseLib.moveTo(pose, task.home.x, config.transitY, task.home.z,
            callbacks.alert, nil, callbacks.tick)
          if ok then
            ok, reason = poseLib.moveTo(pose, task.home.x, task.home.y, task.home.z,
              callbacks.alert, nil, callbacks.tick)
          end
          if not ok then return false, "Unable to recall to FOB: " .. tostring(reason), index end
          ok, reason = unloadAtHome(pose, task, callbacks, fuelTarget)
          if not ok then return false, reason, index end
          callbacks.setState("IDLE")
          return true, "recalled", index
        end
        local returned
        ok, returned = maybeReturn(pose, task, callbacks, false, fuelTarget)
        if not ok then return false, returned, index end
        if returned then transitNeeded = true end
      end
    end
  end
  callbacks.setState("RETURNING")
  ok, reason = poseLib.moveTo(pose, task.home.x, config.transitY, task.home.z,
    callbacks.alert, nil, callbacks.tick)
  if ok then
    ok, reason = poseLib.moveTo(pose, task.home.x, task.home.y, task.home.z,
      callbacks.alert, nil, callbacks.tick)
  end
  if not ok then return false, "Unable to return after mining: " .. tostring(reason), index end
  ok, reason = unloadAtHome(pose, task, callbacks, fuelTarget)
  if not ok then return false, reason, index end
  callbacks.setState("COMPLETE")
  return true, nil, index
end

return M
