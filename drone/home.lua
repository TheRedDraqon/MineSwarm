local poseLib = require("shared.pose")

local M = {}
local coreName = "advancedperipherals:end_automata_core"

function M.coreSlot()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item and item.name == coreName then return slot end
  end
end

local function equipped()
  local core = peripheral.wrap("right")
  if core and type(core.savePoint) == "function" and type(core.warpToPoint) == "function" then
    return core
  end
end

function M.restore(state, checkpoint)
  local slot = state.swapSlot
  if not slot then return true end
  local core = equipped()
  local item = turtle.getItemDetail(slot)
  if core then
    if item and item.name == coreName then
      return false, "Cannot restore mining upgrade: saved equipment slot changed"
    end
    turtle.select(slot)
    local ok, reason = turtle.equipRight()
    if not ok then return false, "Cannot restore mining upgrade: " .. tostring(reason) end
    item = turtle.getItemDetail(slot)
  end
  if not item or item.name ~= coreName then
    return false, "Cannot recover End Automata Core from saved equipment slot"
  end
  state.swapSlot = nil
  checkpoint()
  return true
end

function M.withCore(state, checkpoint, action)
  if state.swapSlot then
    local restored, reason = M.restore(state, checkpoint)
    if not restored then return false, reason end
  end
  local slot = M.coreSlot()
  if not slot then return false, "End Automata Core is missing" end
  local selected = turtle.getSelectedSlot()
  state.swapSlot = slot
  checkpoint()
  turtle.select(slot)
  local ok, reason = turtle.equipRight()
  if not ok then
    state.swapSlot = nil
    checkpoint()
    turtle.select(selected)
    return false, "Cannot equip End Automata Core: " .. tostring(reason)
  end
  local core = equipped()
  if not core then
    turtle.select(slot)
    local restored, restoreReason = turtle.equipRight()
    local item = turtle.getItemDetail(slot)
    if restored and item and item.name == coreName then
      state.swapSlot = nil
      checkpoint()
    else
      restored = false
    end
    turtle.select(selected)
    return false, restored and "Equipped core has no End Automata peripheral"
      or "Cannot restore mining upgrade: " .. tostring(restoreReason)
  end
  if not turtle.getItemDetail(slot) then
    local restored, restoreReason = M.restore(state, checkpoint)
    turtle.select(selected)
    return false, restored and "End Automata Core must replace a right-side mining upgrade" or restoreReason
  end
  local result, message = action(core)
  local restored, restoreReason = M.restore(state, checkpoint)
  turtle.select(selected)
  if not restored then return false, restoreReason end
  return result, message
end

function M.register(state, pose, checkpoint)
  if not M.coreSlot() then return true end
  return M.withCore(state, checkpoint, function(core)
    local points, pointsReason = core.points()
    if not points then return false, "Cannot read warp points: " .. tostring(pointsReason) end
    for _, point in pairs(points) do
      if point == "Home" then
        local distance, reason = core.distanceToPoint("Home")
        if distance == 0 then return true end
        return false, "Existing Home point is elsewhere; clear it or use another core: " .. tostring(reason or distance)
      end
    end
    local ok, reason = core.savePoint("Home")
    if not ok then return false, "Cannot save Home: " .. tostring(reason) end
    local distance, distanceReason = core.distanceToPoint("Home")
    if distance ~= 0 then return false, "Cannot verify Home: " .. tostring(distanceReason or distance) end
    return true
  end)
end

function M.warp(state, checkpoint, pose, destination, name, work, beforeWarp)
  return M.withCore(state, checkpoint, function(core)
    if work then
      local points, pointsReason = core.points()
      if not points then return false, "Cannot read warp points: " .. tostring(pointsReason) end
      for _, point in pairs(points) do
        if point == "MineSwarmWork" then
          local deleted, deleteReason = core.deletePoint("MineSwarmWork")
          if not deleted then return false, "Cannot replace work point: " .. tostring(deleteReason) end
          break
        end
      end
      local saved, saveReason = core.savePoint("MineSwarmWork")
      if not saved then return false, "Cannot save work point: " .. tostring(saveReason) end
    end
    local points, pointsReason = core.points()
    if not points then return false, "Cannot read warp points: " .. tostring(pointsReason) end
    local exists = false
    for _, point in pairs(points) do if point == name then exists = true; break end end
    if not exists then return false, "Warp point " .. name .. " is missing" end
    local distance, distanceReason = core.distanceToPoint(name)
    local expected = math.abs(pose.x - destination.x) + math.abs(pose.y - destination.y)
      + math.abs(pose.z - destination.z)
    if distance ~= expected then
      return false, "Warp point " .. name .. " is missing or incorrect: " .. tostring(distanceReason or distance)
    end
    local cost, costReason = core.estimateWarpCost(name)
    if type(cost) ~= "number" then return false, "Cannot estimate warp cost: " .. tostring(costReason) end
    local fuel = turtle.getFuelLevel()
    if fuel ~= "unlimited" and fuel < cost then return false, "Not enough fuel to warp to " .. name end
    local ok, reason
    while true do
      if beforeWarp then beforeWarp() end
      if type(core.getOperationCooldown) == "function" then
        local cooldown, cooldownReason = core.getOperationCooldown("warp")
        if type(cooldown) ~= "number" then
          return false, "Cannot read warp cooldown: " .. tostring(cooldownReason)
        end
        if cooldown > 0 then os.sleep(cooldown / 1000) end
      end
      if beforeWarp then beforeWarp() end
      ok, reason = core.warpToPoint(name)
      if ok then break end
      if type(reason) ~= "string" or not reason:lower():find("on cooldown", 1, true) then
        return false, "Cannot warp to " .. name .. ": " .. tostring(reason)
      end
      os.sleep(1)
    end
    local actual, gpsReason = poseLib.locate()
    if not actual then error("Warp succeeded but GPS failed; restart after restoring GPS: " .. tostring(gpsReason)) end
    pose.x, pose.y, pose.z = actual.x, actual.y, actual.z
    checkpoint()
    if actual.x ~= destination.x or actual.y ~= destination.y or actual.z ~= destination.z then
      return false, "Warp reached an unexpected position; check saved points"
    end
    return true
  end)
end

function M.cost(state, checkpoint, name)
  return M.withCore(state, checkpoint, function(core)
    local points, reason = core.points()
    if not points then return false, "Cannot read warp points: " .. tostring(reason) end
    for _, point in pairs(points) do
      if point == name then
        local cost, costReason = core.estimateWarpCost(name)
        if type(cost) ~= "number" then return false, "Cannot estimate warp cost: " .. tostring(costReason) end
        return true, cost
      end
    end
    return false, "Warp point " .. name .. " is missing"
  end)
end

return M
