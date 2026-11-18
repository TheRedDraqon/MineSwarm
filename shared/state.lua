local config = require("shared.config")
local util = require("shared.util")

local M = {}

function M.load(path, defaults)
  path = path or config.stateFile
  if not fs.exists(path) then return util.copy(defaults) end
  local ok, value = pcall(util.readTable, path)
  if ok then
    for key, defaultValue in pairs(defaults or {}) do
      if value[key] == nil then value[key] = util.copy(defaultValue) end
    end
    return value
  end
  util.log("State load failed:", value)
  local backup = path .. ".corrupt-" .. os.epoch("utc")
  fs.move(path, backup)
  util.log("Corrupt state preserved at", backup)
  return util.copy(defaults)
end

function M.save(value, path)
  util.writeTable(path or config.stateFile, value)
end

return M
