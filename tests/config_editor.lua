local answers = { "-120", "80", "55", "1", "-130", "53", "Deployer_01" }
local saved = false
write = function() end
read = function() return table.remove(answers, 1) end
term = {
  clear = function() end,
  setCursorPos = function() end,
}
local oldPullEvent = os.pullEvent
os.pullEvent = function(eventName)
  assert(eventName == "key")
  return "key", 1
end

local settings = { configured = false, deployerLabel = "Deployer" }
local editor = dofile("master/config_editor.lua")
editor.run(settings, function(updated)
  assert(updated == settings)
  saved = true
end)
os.pullEvent = oldPullEvent

assert(saved)
assert(settings.configured)
assert(settings.home.x == -120 and settings.home.y == 80 and settings.home.z == 55)
assert(settings.home.dir == 1)
assert(settings.origin.x == -130 and settings.origin.z == 53)
assert(settings.deployerLabel == "Deployer_01")
assert(#answers == 0)

print("MineSwarm configuration editor tests passed")
