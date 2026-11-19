local root = "/home/alex/ComputerCraft/MineSwarm"
local baseUrl = "https://raw.githubusercontent.com/TheRedDraqon/MineSwarm/refs/heads/Simple"
local files, directories = {}, { ["/"] = true, ["/mineswarm"] = true }
local requests = 0
local failPath
local failMoveTo
local failWriteTo
local writes = {}
local closed = {}

local function ensureDirectory(path)
  if path == "" or path == "/" then directories["/"] = true; return end
  local parent = path:match("^(.*)/[^/]+$") or "/"
  ensureDirectory(parent)
  directories[path] = true
end

fs = {
  exists = function(path) return files[path] ~= nil or directories[path] == true end,
  getDir = function(path) return path:match("^(.*)/[^/]+$") or "" end,
  makeDir = ensureDirectory,
  delete = function(path) files[path] = nil; directories[path] = nil end,
  move = function(from, to)
    if failMoveTo == to and from:match("%.update%.tmp$") then
      failMoveTo = nil
      error("simulated filesystem failure")
    end
    assert(files[from] ~= nil, "missing move source " .. from)
    assert(directories[fs.getDir(to)], "missing destination directory " .. fs.getDir(to))
    files[to], files[from] = files[from], nil
  end,
  open = function(path, mode)
    if mode == "r" then
      local contents = files[path]
      if contents == nil then return nil end
      return {
        readAll = function() return contents end,
        close = function() end,
      }
    end
    local chunks = {}
    return {
      write = function(value)
        writes[#writes + 1] = path
        if path == failWriteTo then
          chunks[#chunks + 1] = tostring(value):sub(1, 10)
          error("Out of space")
        end
        chunks[#chunks + 1] = tostring(value)
      end,
      close = function()
        closed[path] = true
        files[path] = table.concat(chunks)
      end,
    }
  end,
}

http = {
  get = function(url)
    requests = requests + 1
    local path = url:sub(#baseUrl + 2)
    if path == failPath then return nil, "simulated download failure" end
    local file = io.open(root .. "/" .. path, "r")
    if not file then return nil, "missing fixture: " .. path end
    local contents = file:read("*a")
    file:close()
    return {
      readAll = function() return contents end,
      close = function() end,
    }
  end,
}

local function runUpdater(role)
  local chunk = assert(loadfile("update.lua"))
  chunk(role)
end

files["/mineswarm/version"] = "0.9.9\n"
runUpdater("drone")
assert(files["/mineswarm/version"] == "2.0.1\n")
assert(files["/mineswarm/drone/main.lua"] ~= nil)
assert(files["/mineswarm/shared/pose.lua"] ~= nil)
assert(files["/mineswarm/update.lua"] ~= nil)
local upgradedRequests = requests

files["/mineswarm/version"] = "2.0.1\n"
requests = 0
runUpdater("drone")
assert(files["/mineswarm/version"] == "2.0.1\n", "updater must not downgrade")
assert(requests == 1, "an up-to-date or newer client should fetch only the manifest")

files["/mineswarm/version"] = "1.0.0\n"
files["/mineswarm/drone/main.lua.update.tmp"] = "left over from previous failure"
writes = {}
runUpdater("drone")
assert(files["/mineswarm/version"] == "2.0.1\n")
assert(files["/mineswarm/drone/main.lua.update.tmp"] == nil)
assert(#writes == 1 and writes[1] == "/mineswarm/version.update.tmp",
  "unchanged installed files should not be staged again")

files = { ["/mineswarm/version"] = "0.9.9\n" }
requests = 0
failPath = "drone/main.lua"
runUpdater("drone")
assert(files["/mineswarm/version"] == "0.9.9\n", "failed downloads must not advance local version")
assert(files["/mineswarm/drone/main.lua"] == nil, "download failure must not partially install files")

failPath = nil
files = { ["/mineswarm/version"] = "0.9.9\n" }
failMoveTo = "/mineswarm/drone/main.lua"
runUpdater("drone")
assert(files["/mineswarm/version"] == "0.9.9\n", "failed file replacement must preserve local version")
assert(files["/mineswarm/shared/pose.lua"] == nil, "failed replacement must roll back earlier files")
assert(files["/mineswarm/drone/main.lua"] == nil)

files = { ["/mineswarm/version"] = "0.9.9\n" }
writes, closed = {}, {}
failWriteTo = "/mineswarm/drone/main.lua.update.tmp"
runUpdater("drone")
assert(files["/mineswarm/version"] == "0.9.9\n", "failed staging must not advance version")
assert(files[failWriteTo] == nil, "partial staged file must be removed after a write failure")
assert(closed[failWriteTo], "failed write handle must be closed before cleanup")
for path in pairs(files) do
  assert(not path:match("%.update%.tmp$"), "all staged files must be cleaned after failure")
end
failWriteTo = nil

print("MineSwarm updater version and transaction tests passed")
