local roles = {
  master = {
    "shared/config.lua", "shared/util.lua", "shared/net.lua", "shared/state.lua",
    "shared/pose.lua", "master/ore_db.lua", "master/partition.lua",
    "master/ui.lua", "master/main.lua",
  },
  deployer = {
    "shared/config.lua", "shared/util.lua", "shared/net.lua", "shared/state.lua",
    "shared/pose.lua", "deployer/main.lua",
  },
  drone = {
    "shared/config.lua", "shared/util.lua", "shared/net.lua", "shared/state.lua",
    "shared/pose.lua", "drone/miner.lua", "drone/main.lua",
  },
  gps = { "satellite/main.lua" },
}

local function prompt(text, default)
  write(text .. (default and (" [" .. default .. "]") or "") .. ": ")
  local value = read()
  if value == "" then return default end
  return value
end

local baseUrl = prompt("Raw source base URL (ending in /MineSwarm)")
if not baseUrl or baseUrl == "" then error("A source base URL is required") end
baseUrl = baseUrl:gsub("/+$", "")
local role = prompt("Install role (master/deployer/drone/gps)")
if not roles[role] then error("Role must be master, deployer, drone, or gps") end

local label
if role == "deployer" then label = prompt("Computer label", "Deployer")
elseif role == "drone" then label = prompt("Turtle label (blank keeps/creates a default)", "") end
local gpsPosition
if role == "gps" then
  gpsPosition = {}
  for _, axis in ipairs({ "x", "y", "z" }) do
    local value = tonumber(prompt("GPS host world coordinate " .. axis))
    if not value or value % 1 ~= 0 then error("GPS coordinates must be whole numbers") end
    gpsPosition[axis] = value
  end
end

if not http or not http.get then
  error("HTTP API is disabled; enable it in the server's CC:Tweaked configuration")
end

local downloads = {}
for _, relativePath in ipairs(roles[role]) do
  local url = baseUrl .. "/" .. relativePath
  write("Downloading " .. relativePath .. " ... ")
  local response, reason = http.get(url)
  if not response then
    print("failed")
    error("Download failed for " .. url .. ": " .. tostring(reason))
  end
  downloads[relativePath] = response.readAll()
  response.close()
  print("ok")
end

local function writeFile(path, contents)
  local directory = fs.getDir(path)
  if directory ~= "" and not fs.exists(directory) then fs.makeDir(directory) end
  local file = fs.open(path, "w")
  if not file then error("Cannot write " .. path) end
  file.write(contents)
  file.close()
end

for relativePath, contents in pairs(downloads) do
  writeFile("/mineswarm/" .. relativePath, contents)
end

if role == "master" and not fs.exists("/mineswarm/master_config") then
  writeFile("/mineswarm/master_config", textutils.serialize({
    configured = false,
    home = { x = 0, y = 0, z = 0, dir = 0 },
    origin = { x = 0, z = 0 },
    deployerLabel = "Deployer",
  }))
elseif role == "deployer" and not fs.exists("/mineswarm/deployer_config") then
  writeFile("/mineswarm/deployer_config", textutils.serialize({
    supplySide = "front",
    placeDirection = "down",
    labelPrefix = "Miner_",
  }))
end

if role == "master" then
  writeFile("/startup.lua", 'shell.run("mineswarm/master/main.lua")\n')
elseif role == "deployer" then
  if label and label ~= "" then os.setComputerLabel(label) end
  writeFile("/startup.lua", 'shell.run("mineswarm/deployer/main.lua")\n')
elseif role == "drone" then
  if label and label ~= "" then os.setComputerLabel(label) end
  writeFile("/startup.lua", 'shell.run("mineswarm/drone/main.lua")\n')
else
  writeFile("/mineswarm/gps_config", textutils.serialize(gpsPosition))
  writeFile("/startup.lua", 'shell.run("mineswarm/satellite/main.lua")\n')
end

print("Installed MineSwarm role: " .. role)
if role == "master" then
  print("Edit /mineswarm/master_config and set configured=true plus the FOB home coordinates before launching jobs.")
end
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
