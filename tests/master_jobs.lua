local files = {}
fs = {
  exists = function(path) return files[path] ~= nil end,
  getDir = function() return "/mineswarm" end,
  makeDir = function() end,
  delete = function(path) files[path] = nil end,
  move = function(from, to)
    assert(files[from] ~= nil)
    files[to], files[from] = files[from], nil
  end,
  open = function(path, mode)
    if mode == "r" then
      if not files[path] then return nil end
      return { readAll = function() return files[path] end, close = function() end }
    end
    local contents = ""
    return {
      write = function(value) contents = contents .. value end,
      close = function() files[path] = contents end,
    }
  end,
}

if not textutils then
  textutils = {}
  function textutils.serialize(value)
    local seen = {}
    local function encode(item)
      if type(item) == "string" then return string.format("%q", item) end
      if type(item) ~= "table" then return tostring(item) end
      if seen[item] then error("Cannot serialize table with repeated entries") end
      seen[item] = true
      local result = {}
      for key, entry in pairs(item) do
        result[#result + 1] = "[" .. encode(key) .. "]=" .. encode(entry)
      end
      return "{" .. table.concat(result, ",") .. "}"
    end
    return encode(value)
  end
  function textutils.unserialize(value)
    return assert(load("return " .. value))()
  end
end

local packets, callbacks, masterState = {}, nil, nil
package.preload["shared.net"] = function()
  return {
    open = function() end, side = function() return "left" end,
    isModemMessage = function(event) return event[1] == "modem_message" end,
    send = function(packet) packets[#packets + 1] = packet end,
  }
end
package.preload["master.ui"] = function()
  return {
    new = function(_, state, handlers)
      masterState, callbacks = state, handlers
      return {
        draw = function() end, setMessage = function() end,
        touch = function() handlers.launch("Drone1", "~10", "~10", "Osmium") end,
      }
    end,
  }
end
peripheral = {
  find = function() return { isColor = function() return true end } end,
  getName = function() return "monitor" end,
}
keys = { q = 16 }
os.epoch = function() return 12345 end
os.clock = function() return 10 end
os.startTimer = function() return 1 end
local events = {
  { "modem_message", nil, nil, nil, {
    type = "HB", label = "Drone1", pos = { x = 100, y = 100, z = 100 }, state = "IDLE",
  } },
  { "monitor_touch", "monitor", 1, 1 },
  { "modem_message", nil, nil, nil, {
    type = "HB", label = "Drone1", pos = { x = 100, y = 100, z = 100 },
    state = "MINING", task = "12345", progress = 1,
  } },
  { "key", keys.q },
}
os.pullEventRaw = function()
  local event = assert(table.remove(events, 1), "unexpected master event")
  return table.unpack(event, 1, 5)
end

assert(loadfile("master/main.lua", nil, _ENV))()
local job = assert(masterState.jobs["12345"])
assert(job.status == "MINING" and job.progress == 1)
assert(job.bounds.x1 == 100 and job.bounds.x2 == 110)
assert(job.bounds.y1 == -21 and job.bounds.y2 == -1)
assert(job.bounds.z1 == 100 and job.bounds.z2 == 110)
assert(#packets == 1 and packets[1].type == "TASK" and packets[1].target == "Drone1")
assert(packets[1].task.id == job.id and packets[1].task.bounds.x2 == job.bounds.x2)
local saved = assert(textutils.unserialize(files["/mineswarm/simple_master_state"]))
assert(saved.jobs[job.id].progress == 1 and saved.jobs[job.id].task.bounds.z2 == 110)
assert(callbacks ~= nil)
print("MineSwarm master job persistence tests passed")
