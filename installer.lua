local roles = {
  master = {
    "shared/config.lua", "shared/util.lua", "shared/net.lua", "shared/state.lua",
    "master/ore_db.lua", "master/quarries.lua", "master/ui.lua",
    "master/main.lua", "update.lua",
  },
  drone = {
    "shared/config.lua", "shared/util.lua", "shared/net.lua", "shared/state.lua",
    "shared/pose.lua", "drone/miner.lua", "drone/main.lua", "update.lua",
  },
  gps = { "satellite/main.lua", "update.lua" },
}

local function prompt(text, default)
  write(text .. (default and (" [" .. default .. "]") or "") .. ": ")
  local value = read()
  if value == "" then return default end
  return value
end

local defaultBaseUrl = "https://raw.githubusercontent.com/TheRedDraqon/MineSwarm/refs/heads/Simple"
local baseUrl = defaultBaseUrl
if not baseUrl or baseUrl == "" then error("A source base URL is required") end
baseUrl = baseUrl:gsub("/+$", "")
local role = prompt("Install role (master/drone/gps)")
if not roles[role] then error("Role must be master, drone, or gps") end

local label
if role == "drone" then
  while true do
    label = prompt("Turtle label (letters/numbers only; blank keeps/creates a default)", "")
    local effectiveLabel = label ~= "" and label or os.getComputerLabel()
    if not effectiveLabel or effectiveLabel == "" or effectiveLabel:match("^[A-Za-z0-9]+$") then
      break
    end
    print("Invalid turtle label. Use only letters A-Z and numbers 0-9.")
  end
end
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

if role == "master" then
  writeFile("/startup.lua", 'shell.run("mineswarm/update.lua", "master")\nshell.run("mineswarm/master/main.lua")\n')
elseif role == "drone" then
  if label and label ~= "" then os.setComputerLabel(label) end
  writeFile("/startup.lua", 'shell.run("mineswarm/update.lua", "drone")\nshell.run("mineswarm/drone/main.lua")\n')
else
  writeFile("/mineswarm/gps_config", textutils.serialize(gpsPosition))
  writeFile("/startup.lua", 'shell.run("mineswarm/update.lua", "gps")\nshell.run("mineswarm/satellite/main.lua")\n')
end

print("Installed MineSwarm role: " .. role)
print("Rebooting in 3 seconds...")
sleep(3)
os.reboot()
