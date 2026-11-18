local BASE_URL = "https://raw.githubusercontent.com/TheRedDraqon/MineSwarm/refs/heads/master"
local ROOT = "/mineswarm"

local function report(message)
  print("[MineSwarm updater] " .. message)
end

local function trim(value)
  return value:match("^%s*(.-)%s*$")
end

local function parseVersion(value)
  local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
  if not major then return nil end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function newer(remote, localVersion)
  local a, b = parseVersion(remote), parseVersion(localVersion)
  if not a then return nil, "Invalid remote version: " .. tostring(remote) end
  if not b then return nil, "Invalid local version: " .. tostring(localVersion) end
  for index = 1, 3 do
    if a[index] ~= b[index] then return a[index] > b[index] end
  end
  return false
end

local function safePath(path)
  if path == "" or path:sub(1, 1) == "/" or path:sub(-4) ~= ".lua"
    or not path:match("^[%w_/%-%.]+$") then
    return false
  end
  for component in path:gmatch("[^/]+") do
    if component == "." or component == ".." then return false end
  end
  return true
end

local function parseManifest(contents, role)
  local manifest = { files = {} }
  local section
  for rawLine in (contents .. "\n"):gmatch("(.-)\r?\n") do
    local line = trim(rawLine)
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local name = line:match("^%[([%w_%-]+)%]$")
      if name then
        if name ~= "common" and name ~= "master" and name ~= "deployer"
          and name ~= "drone" and name ~= "gps" then
          return nil, "Unknown manifest section: " .. name
        end
        section = name
      elseif line:match("^version=") then
        if manifest.version then return nil, "Duplicate version in manifest" end
        manifest.version = trim(line:sub(9))
      elseif section then
        if not safePath(line) then return nil, "Unsafe manifest path: " .. line end
        manifest[section] = manifest[section] or {}
        manifest[section][#manifest[section] + 1] = line
      else
        return nil, "Manifest entry outside a section: " .. line
      end
    end
  end

  if not parseVersion(manifest.version or "") then return nil, "Manifest has no valid semantic version" end
  if not manifest.common or not manifest[role] then
    return nil, "Manifest has no file list for role " .. role
  end

  local seen = {}
  for _, sectionName in ipairs({ "common", role }) do
    for _, path in ipairs(manifest[sectionName]) do
      if seen[path] then return nil, "Duplicate manifest path: " .. path end
      seen[path] = true
      manifest.files[#manifest.files + 1] = path
    end
  end
  if #manifest.files == 0 then return nil, "Manifest contains no files for " .. role end
  return manifest
end

local function fetch(url)
  local ok, response, reason = pcall(http.get, url)
  if not ok then return nil, tostring(response) end
  if not response then return nil, tostring(reason or "request failed") end
  local readOk, contents = pcall(response.readAll)
  response.close()
  if not readOk then return nil, tostring(contents) end
  return contents
end

local function readLocalVersion()
  local path = ROOT .. "/version"
  if not fs.exists(path) then return nil end
  local file = fs.open(path, "r")
  if not file then error("Cannot read " .. path) end
  local value = trim(file.readAll())
  file.close()
  return value
end

local function ensureParent(path)
  local parent = fs.getDir(path)
  if parent ~= "" and not fs.exists(parent) then fs.makeDir(parent) end
end

local function writeFile(path, contents)
  ensureParent(path)
  local file = fs.open(path, "w")
  if not file then error("Cannot write " .. path) end
  file.write(contents)
  file.close()
end

local function stageFile(path, contents)
  local destination = ROOT .. "/" .. path
  local temporary = destination .. ".update.tmp"
  local backup = destination .. ".update.bak"
  ensureParent(destination)
  if fs.exists(backup) then
    if fs.exists(destination) then fs.delete(backup) else fs.move(backup, destination) end
  end
  if fs.exists(temporary) then fs.delete(temporary) end
  writeFile(temporary, contents)
  return { destination = destination, temporary = temporary, backup = backup }
end

local function rollback(committed)
  for index = #committed, 1, -1 do
    local file = committed[index]
    if fs.exists(file.destination) then fs.delete(file.destination) end
    if fs.exists(file.backup) then fs.move(file.backup, file.destination) end
  end
end

local function applyFiles(staged)
  local committed = {}
  for _, file in ipairs(staged) do
    if fs.exists(file.destination) then fs.move(file.destination, file.backup) end
    local ok, reason = pcall(fs.move, file.temporary, file.destination)
    if not ok then
      if fs.exists(file.backup) then fs.move(file.backup, file.destination) end
      rollback(committed)
      error("Could not install " .. file.destination .. ": " .. tostring(reason))
    end
    committed[#committed + 1] = file
  end
  for _, file in ipairs(committed) do
    if fs.exists(file.backup) then fs.delete(file.backup) end
  end
end

local function update(role)
  if role ~= "master" and role ~= "deployer" and role ~= "drone" and role ~= "gps" then
    report("Unknown role; skipping update")
    return
  end
  if not http or not http.get then
    report("HTTP is disabled; continuing with installed version")
    return
  end

  local manifestText, reason = fetch(BASE_URL .. "/manifest.txt")
  if not manifestText then
    report("Could not fetch version manifest (" .. reason .. "); continuing with installed version")
    return
  end
  local manifest
  manifest, reason = parseManifest(manifestText, role)
  if not manifest then
    report("Invalid version manifest (" .. reason .. "); continuing with installed version")
    return
  end

  local localVersion = readLocalVersion()
  local shouldUpdate
  if localVersion == nil then
    shouldUpdate = true
  else
    shouldUpdate, reason = newer(manifest.version, localVersion)
    if shouldUpdate == nil then
      report("Version check failed (" .. reason .. "); continuing with installed files")
      return
    end
  end
  if not shouldUpdate then
    report("Current version " .. manifest.version)
    return
  end

  report("Updating " .. tostring(localVersion or "unversioned") .. " -> " .. manifest.version)
  local contents = {}
  for _, path in ipairs(manifest.files) do
    local data, downloadError = fetch(BASE_URL .. "/" .. path)
    if not data then
      report("Could not download " .. path .. " (" .. downloadError .. "); no files changed")
      return
    end
    contents[#contents + 1] = { path = path, data = data }
  end

  local staged = {}
  local stageOk, stageError = pcall(function()
    for _, item in ipairs(contents) do
      staged[#staged + 1] = stageFile(item.path, item.data)
    end
    staged[#staged + 1] = stageFile("version", manifest.version .. "\n")
    applyFiles(staged)
  end)
  if not stageOk then
    for _, file in ipairs(staged) do
      if fs.exists(file.temporary) then fs.delete(file.temporary) end
    end
    report("Update failed (" .. tostring(stageError) .. "); continuing with installed files")
    return
  end
  report("Updated to " .. manifest.version)
end

local role = ...
local ok, reason = pcall(update, role)
if not ok then
  report("Update check failed (" .. tostring(reason) .. "); continuing with installed files")
end
