local config = require("shared.config")
local M = {}

local delta = {
  [0] = { x = 0, z = -1 },
  [1] = { x = 1, z = 0 },
  [2] = { x = 0, z = 1 },
  [3] = { x = -1, z = 0 },
}

function M.locate()
  local x, y, z = gps.locate(config.gpsTimeout, false)
  if not x then return nil, "GPS locate failed; check the satellite cluster and modem" end
  return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
end

local function deriveDirection(dx, dz)
  for direction, vector in pairs(delta) do
    if vector.x == dx and vector.z == dz then return direction end
  end
  return nil
end

local protectedNames = { allthemodium = true, vibranium = true, unobtainium = true }

local function protectedToken(value)
  if type(value) ~= "string" then return false end
  local name = value:lower()
  if name:find("bedrock", 1, true) then return true end
  if name:match("chest$") then return true end
  for material in pairs(protectedNames) do
    if name:find(material, 1, true) then return true end
  end
  return false
end

local function isProtected(data)
  if not data then return false end
  if protectedToken(data.name) then return true end
  for tag, enabled in pairs(data.tags or {}) do
    if enabled and (protectedToken(tag) or protectedToken(enabled)) then return true end
  end
  return false
end

function M.calibrate()
  local origin, reason = M.locate()
  if not origin then return nil, reason end

  local failures = {}
  local allBlocked = true
  for offset = 0, 3 do
    local blocked, block = turtle.inspect()
    if blocked then
      failures[#failures + 1] = "blocked by " .. tostring(block and block.name or "unknown block")
    else
      allBlocked = false
      local before
      for attempt = 1, 3 do
        before = M.locate()
        if before then break end
        os.sleep(0.5)
      end
      if not before then
        failures[#failures + 1] = "GPS failed before movement"
      elseif not turtle.forward() then
        failures[#failures + 1] = "forward movement failed"
      else
        local moved
        for attempt = 1, 3 do
          moved = M.locate()
          if moved then break end
          os.sleep(0.5)
        end
        if not turtle.back() then
          return nil, "Calibration moved the turtle but it could not back up; recover its position manually"
        end
        if moved then
          local direction = deriveDirection(moved.x - before.x, moved.z - before.z)
          if direction and moved.y == before.y then
            for _ = 1, offset do turtle.turnLeft() end
            return {
              x = origin.x,
              y = origin.y,
              z = origin.z,
              dir = (direction - offset) % 4,
            }
          end
          failures[#failures + 1] = "GPS did not report a one-block horizontal move"
        else
          failures[#failures + 1] = "GPS could not locate the turtle after it moved"
        end
      end
    end
    turtle.turnRight()
  end

  if not allBlocked then
    return nil, "Unable to determine facing (" .. table.concat(failures, "; ")
      .. "); verify GPS coverage and turtle movement"
  end

  local blocked, block = turtle.inspect()
  if blocked and isProtected(block) then
    return nil, "Cannot calibrate through protected block " .. tostring(block.name)
  end
  if blocked then
    if not turtle.dig() then
      return nil, "All four sides are blocked and the front block could not be mined: "
        .. tostring(block and block.name or "unknown block")
    end
    local before
    for attempt = 1, 3 do
      before = M.locate()
      if before then break end
      os.sleep(0.5)
    end
    if not before then
      return nil, "Front block was mined, but GPS failed before calibration movement"
    end
    if not turtle.forward() then
      return nil, "Front block was mined, but the turtle could not move into the opening"
    end
    local moved
    for attempt = 1, 3 do
      moved = M.locate()
      if moved then break end
      os.sleep(0.5)
    end
    if not turtle.back() then
      return nil, "Calibration moved the turtle but it could not back up; recover its position manually"
    end
    if not moved then
      return nil, "Front block was mined and the turtle moved, but GPS failed afterward"
    end
    local direction = deriveDirection(moved.x - before.x, moved.z - before.z)
    if direction and moved.y == before.y then
      return { x = origin.x, y = origin.y, z = origin.z, dir = direction }
    end
    return nil, "GPS did not report a one-block horizontal move after mining the front block"
  end

  return nil, "Unable to determine facing; " .. table.concat(failures, "; ")
end

function M.turnTo(pose, direction)
  direction = direction % 4
  local right = (direction - pose.dir) % 4
  if right == 3 then
    turtle.turnLeft()
  else
    for _ = 1, right do turtle.turnRight() end
  end
  pose.dir = direction
end

local function isTurtle(data)
  return data and data.name and data.name:lower():find("turtle", 1, true) ~= nil
end

local function alert(blockName, position, onProtected)
  if onProtected then onProtected(blockName, position) end
end

local function blockAt(data, position)
  return tostring(data and data.name or "unknown block") .. " at "
    .. position.x .. "," .. position.y .. "," .. position.z
end

local function moveHorizontal(pose, direction, onProtected, onStep, noDig)
  M.turnTo(pose, direction)
  local vector = delta[direction]
  local destination = { x = pose.x + vector.x, y = pose.y, z = pose.z + vector.z }
  for _ = 1, 10 do
    if turtle.getFuelLevel and turtle.getFuelLevel() == 0 then return false, "out of fuel" end
    local found, data = turtle.inspect()
    if found then
      if isProtected(data) then
        alert(data.name, destination, onProtected)
        return false, "protected block " .. blockAt(data, destination)
      end
      if isTurtle(data) then
        os.sleep(math.random(5, 20) / 10)
      elseif noDig then
        return false, "return path blocked by " .. blockAt(data, destination)
      elseif not turtle.dig() then
        alert(data.name or "undiggable", destination, onProtected)
        return false, "dig failed: " .. blockAt(data, destination)
      end
    end
    if turtle.forward() then
      pose.x, pose.z = destination.x, destination.z
      if onStep then
        local ok, reason = onStep(pose)
        if ok == false then return false, reason end
      end
      return true
    end
    if not turtle.detect() then
      os.sleep(0.2)
    else
      local blocked, block = turtle.inspect()
      if blocked and isProtected(block) then
        alert(block.name, destination, onProtected)
        return false, "protected block " .. blockAt(block, destination)
      end
      if not blocked or isTurtle(block) then
        os.sleep(math.random(5, 20) / 10)
      elseif noDig then
        return false, "return path blocked by " .. blockAt(block, destination)
      elseif not turtle.dig() then
        alert(block.name or "undiggable", destination, onProtected)
        return false, "dig failed: " .. blockAt(block, destination)
      end
    end
  end
  return false, "movement retry limit reached"
end

local function moveVertical(pose, amount, onProtected, onStep, noDig)
  local direction = amount > 0 and "up" or "down"
  local move = amount > 0 and turtle.up or turtle.down
  local detect = amount > 0 and turtle.detectUp or turtle.detectDown
  local inspect = amount > 0 and turtle.inspectUp or turtle.inspectDown
  local dig = amount > 0 and turtle.digUp or turtle.digDown
  local dy = amount > 0 and 1 or -1
  for _ = 1, math.abs(amount) do
    local destination = { x = pose.x, y = pose.y + dy, z = pose.z }
    local moved = false
    for attempt = 1, 10 do
      if turtle.getFuelLevel and turtle.getFuelLevel() == 0 then return false, "out of fuel" end
      local found, data = inspect()
      if found then
        if isProtected(data) then
          alert(data.name, destination, onProtected)
          return false, "protected block " .. blockAt(data, destination)
        end
        if isTurtle(data) then
          os.sleep(math.random(5, 20) / 10)
        elseif noDig then
          return false, "return path blocked by " .. blockAt(data, destination)
        elseif not dig() then
          alert(data.name or "undiggable", destination, onProtected)
          return false, direction .. " dig failed: " .. blockAt(data, destination)
        end
      end
      if move() then
        pose.y = destination.y
        if onStep then
          local ok, reason = onStep(pose)
          if ok == false then return false, reason end
        end
        moved = true
        break
      end
      if not detect() then
        os.sleep(0.2)
      else
        local blocked, block = inspect()
        if blocked and isProtected(block) then
          alert(block.name, destination, onProtected)
          return false, "protected block " .. blockAt(block, destination)
        elseif blocked and isTurtle(block) then
          os.sleep(math.random(5, 20) / 10)
        elseif blocked and noDig then
          return false, "return path blocked by " .. blockAt(block, destination)
        elseif blocked and attempt == 10 then
          return false, direction .. " movement failed: " .. tostring(block.name)
        elseif not blocked then
          os.sleep(math.random(5, 20) / 10)
        end
      end
    end
    if not moved then return false, direction .. " movement retry limit reached" end
  end
  return true
end

function M.moveTo(pose, x, y, z, onProtected, maxSteps, onStep, noDig)
  local steps = 0
  local function horizontal(axis, target)
    while pose[axis] ~= target do
      steps = steps + 1
      if steps > (maxSteps or config.maxTravelSteps) then return false, "travel step limit reached" end
      local direction
      if axis == "x" then direction = target > pose.x and 1 or 3
      else direction = target > pose.z and 2 or 0 end
      local ok, reason = moveHorizontal(pose, direction, onProtected, onStep, noDig)
      if not ok then return false, reason end
    end
    return true
  end

  if pose.y ~= y then
    steps = steps + math.abs(y - pose.y)
    if steps > (maxSteps or config.maxTravelSteps) then return false, "travel step limit reached" end
    local ok, reason = moveVertical(pose, y - pose.y, onProtected, onStep, noDig)
    if not ok then return false, reason end
  end
  local ok, reason = horizontal("x", x)
  if not ok then return false, reason end
  return horizontal("z", z)
end

function M.directionDelta(direction)
  return delta[direction]
end

function M.isProtected(data)
  return isProtected(data)
end

return M
