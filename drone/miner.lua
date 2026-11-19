local poseLib = require("shared.pose")
local util = require("shared.util")

local M = {}

local function move(pose, x, y, z, callbacks, watchInventory, noDig)
  local ok, reason = poseLib.moveTo(pose, x, y, z, callbacks.alert, nil, function(current)
    callbacks.tick(current)
    if watchInventory and util.inventoryFull() then return false, "inventory_full" end
  end, noDig)
  if not ok then return false, tostring(reason) end
  return true
end

local function unload(pose, task, callbacks)
  local home, startY = task.home, task.bounds.y2 + 1
  callbacks.setState("RETURNING")
  local ok, reason = true, nil
  if pose.x ~= home.x or pose.y ~= home.y or pose.z ~= home.z then
    ok, reason = move(pose, home.x, startY, home.z, callbacks, false, true)
    if ok then ok, reason = move(pose, home.x, home.y, home.z, callbacks, false, true) end
  end
  if not ok then return false, "Cannot return to chest: " .. reason end
  poseLib.turnTo(pose, home.dropDir)
  local found, block = turtle.inspect()
  if not found or type(block.name) ~= "string" or not block.name:lower():match("chest$") then
    return false, "Chest is missing at home; refusing to drop items"
  end
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      if not turtle.drop() then return false, "Chest unavailable or full at home" end
    end
  end
  if util.slotCount() > 0 then return false, "Chest could not accept all items" end
  callbacks.setState("MINING")
  return true
end

local function space(pose, task, callbacks)
  if not util.inventoryFull() then return true, false end
  if task.chest then
    local ok, reason = unload(pose, task, callbacks)
    if not ok then return false, reason end
    return true, true
  end
  callbacks.waitForSpace()
  return true, false
end

local function moveToWork(pose, task, x, y, z, callbacks)
  while true do
    local ok, reason = space(pose, task, callbacks)
    if not ok then return false, reason end
    ok, reason = move(pose, x, y, z, callbacks, true)
    if ok then return true end
    if reason ~= "inventory_full" then return false, reason end
  end
end

function M.run(pose, task, callbacks, progress)
  local bounds = task.bounds
  local width = bounds.x2 - bounds.x1 + 1
  local length = bounds.z2 - bounds.z1 + 1
  local total = width * length
  local startY = bounds.y2 + 1
  local index = progress or 0

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
  return true, nil, index
end

return M
