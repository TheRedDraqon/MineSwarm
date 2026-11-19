local M = {}

function M.isDroneLabel(label)
  return type(label) == "string" and label:match("^[A-Za-z0-9]+$") ~= nil
end

function M.log(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  print(os.date("%H:%M:%S") .. " " .. table.concat(parts, " "))
end

function M.copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = M.copy(item) end
  return result
end

function M.clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function M.round(value)
  return math.floor(value + 0.5)
end

function M.sortedKeys(value)
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

function M.readTable(path)
  if not fs.exists(path) then return nil end
  local file = fs.open(path, "r")
  if not file then error("Cannot open " .. path .. " for reading") end
  local contents = file.readAll()
  file.close()
  local value, reason = textutils.unserialize(contents)
  if type(value) ~= "table" then
    error("Invalid serialized state in " .. path .. ": " .. tostring(reason))
  end
  return value
end

function M.writeTable(path, value)
  local parent = fs.getDir(path)
  if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
  local temporary = path .. ".tmp"
  local file = fs.open(temporary, "w")
  if not file then error("Cannot open " .. temporary .. " for writing") end
  file.write(textutils.serialize(value))
  file.close()
  local backup = path .. ".bak"
  if fs.exists(backup) then fs.delete(backup) end
  if fs.exists(path) then fs.move(path, backup) end
  local ok, reason = pcall(fs.move, temporary, path)
  if not ok then
    if fs.exists(backup) then fs.move(backup, path) end
    error("Cannot replace " .. path .. ": " .. tostring(reason))
  end
  if fs.exists(backup) then fs.delete(backup) end
end

function M.slotCount()
  local count = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then count = count + 1 end
  end
  return count
end

function M.inventoryFull()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) == 0 then return false end
  end
  return true
end

function M.findModem(config)
  if config.modemSide then
    if peripheral.getType(config.modemSide) == "modem" then
      return peripheral.wrap(config.modemSide), config.modemSide
    end
    error("Configured modem side is not a modem: " .. config.modemSide)
  end
  local modem = peripheral.find("modem")
  if not modem then error("No modem peripheral found") end
  return modem, peripheral.getName(modem)
end

function M.itemLabel(name)
  return tostring(name):match("([^:]+)$") or tostring(name)
end

return M
