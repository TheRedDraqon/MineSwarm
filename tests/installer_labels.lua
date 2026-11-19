local existingLabel, newLabel, inputs, inputIndex, downloads
read = function()
  inputIndex = inputIndex + 1
  assert(inputs[inputIndex] ~= nil, "installer asked for an unexpected input")
  return inputs[inputIndex]
end
write = function() end
sleep = function() end
os.getComputerLabel = function() return existingLabel end
os.setComputerLabel = function(value) newLabel = value end
os.reboot = function() end
fs = {
  getDir = function(path) return path:match("^(.*)/[^/]+$") or "" end,
  exists = function() return true end,
  makeDir = function() end,
  open = function() return { write = function() end, close = function() end } end,
}
http = {
  get = function()
    assert(inputIndex == #inputs, "installer must validate the label before downloading")
    downloads = downloads + 1
    return { readAll = function() return "fixture" end, close = function() end }
  end,
}

existingLabel, newLabel, inputs, inputIndex, downloads =
  "Old_Name", nil, { "drone", "bad/name", 'bad"name', "", "Drone123" }, 0, 0
dofile("installer.lua")
assert(newLabel == "Drone123" and downloads > 0)

existingLabel, newLabel, inputs, inputIndex, downloads = "Drone5", nil, { "drone", "" }, 0, 0
dofile("installer.lua")
assert(newLabel == nil and downloads > 0, "blank must preserve an existing valid label")

existingLabel, newLabel, inputs, inputIndex, downloads = nil, nil, { "drone", "" }, 0, 0
dofile("installer.lua")
assert(newLabel == nil and downloads > 0, "blank must allow the drone to create its default label")

print("MineSwarm installer label tests passed")
