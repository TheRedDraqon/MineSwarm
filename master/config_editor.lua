local M = {}

local function promptInteger(label, current, minimum, maximum)
  while true do
    local suffix = current ~= nil and (" [" .. tostring(current) .. "]") or ""
    write(label .. suffix .. ": ")
    local input = read()
    local value
    if input == "" and current ~= nil then
      value = current
    else
      value = tonumber(input)
    end
    if value and value == math.floor(value) and math.abs(value) < 9007199254740992
      and (minimum == nil or value >= minimum) and (maximum == nil or value <= maximum) then
      return value
    end
    print("Enter a whole number" .. (minimum and (" from " .. minimum) or "")
      .. (maximum and (" through " .. maximum) or "") .. ".")
  end
end

local function promptText(label, current)
  write(label .. " [" .. tostring(current or "") .. "]: ")
  local value = read()
  if value == "" then return current end
  return value
end

function M.run(settings, save)
  local home = type(settings.home) == "table" and settings.home or {}
  local origin = type(settings.origin) == "table" and settings.origin or home

  term.clear()
  term.setCursorPos(1, 1)
  print("MineSwarm master configuration")
  print("Enter coordinates; press Enter to keep a shown value.")
  print("FOB is the miner parking/drop-off location.")
  local newHome = {
    x = promptInteger("FOB X", home.x),
    y = promptInteger("FOB Y", home.y),
    z = promptInteger("FOB Z", home.z),
    dir = promptInteger("FOB facing (0 North, 1 East, 2 South, 3 West)", home.dir or 0, 0, 3),
  }
  local newOrigin = {
    x = promptInteger("Quarry origin X", origin.x or newHome.x),
    z = promptInteger("Quarry origin Z", origin.z or newHome.z),
  }
  local deployerLabel = promptText("Deployer computer label", settings.deployerLabel or "Deployer")
  if type(deployerLabel) ~= "string" or deployerLabel == "" then
    error("Deployer computer label cannot be empty")
  end

  settings.home = newHome
  settings.origin = newOrigin
  settings.deployerLabel = deployerLabel
  settings.configured = true
  save(settings)
  print("Configuration saved. Press any key to return to the C2 monitor.")
  os.pullEvent("key")
end

return M
