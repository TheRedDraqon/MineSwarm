local slots = {}
for i = 1, 16 do slots[i] = 1 end
local packets = {}
local saved
local task = {
  id = "test", format = 2, total = 1,
  start = { x = 100, y = 100, z = 100 },
  bounds = { x1 = 100, x2 = 100, y1 = -21, y2 = -1, z1 = 100, z2 = 100 },
}
local sentTask = false

package.preload["shared.config"] = function() return { heartbeatSeconds = 5 } end
package.preload["shared.util"] = function()
  return {
    log = function() end,
    slotCount = function()
      local count = 0
      for i = 1, 16 do if slots[i] > 0 then count = count + 1 end end
      return count
    end,
    inventoryFull = function()
      for i = 1, 16 do if slots[i] == 0 then return false end end
      return true
    end,
  }
end
package.preload["shared.net"] = function()
  return {
    open = function() end,
    send = function(packet) packets[#packets + 1] = packet end,
    isModemMessage = function(event) return event[1] == "modem_message" end,
  }
end
package.preload["shared.state"] = function()
  return { load = function() return { progress = 0, mode = "IDLE" } end,
    save = function(state) saved = state end }
end
package.preload["shared.pose"] = function()
  return {
    calibrate = function() return { x = 100, y = 100, z = 100, dir = 0 } end,
    turnTo = function(pose, direction) pose.dir = direction end,
  }
end
package.preload["drone.miner"] = function()
  return {
    run = function(_, _, callbacks)
      callbacks.waitForSpace()
      assert(slots[1] == 0, "miner resumed before the inventory was cleared")
      return true, nil, 1
    end,
  }
end
turtle = {
  getFuelLevel = function() return "unlimited" end,
  inspect = function() return false end,
}
os.getComputerLabel = function() return "Drone1" end
os.getComputerID = function() return 1 end
os.startTimer = function() return 1 end
os.queueEvent = function() end
os.sleep = function() coroutine.yield("sleep") end
os.pullEventRaw = function()
  local _, isMain = coroutine.running()
  if isMain then
    if not sentTask then
      sentTask = true
      return "modem_message", "right", 9001, 9001,
        { type = "TASK", target = "Drone1", task = task }
    end
    error("test finished")
  end
  return coroutine.yield("event")
end
parallel = {
  waitForAny = function(run, listener)
    local worker, receiver = coroutine.create(run), coroutine.create(listener)
    local ok, why = coroutine.resume(worker)
    assert(ok and why == "sleep" and saved.mode == "PAUSED_FULL")
    assert(coroutine.resume(receiver))
    local oldProgress = saved.progress
    assert(coroutine.resume(receiver, "modem_message", "right", 9001, 9001,
      { type = "TASK", target = "Drone1", task = task }))
    assert(saved.mode == "PAUSED_FULL" and saved.progress == oldProgress,
      "retransmitting a task must not reset or reject an active job")
    assert(packets[#packets].type == "ACK" and packets[#packets].task == task.id)
    local resume = { type = "CMD", target = "Drone1", action = "RESUME" }
    assert(coroutine.resume(receiver, "modem_message", "right", 9001, 9001, resume))
    assert(saved.mode == "PAUSED_FULL" and saved.lastError:find("still full", 1, true))
    slots[1] = 0
    assert(coroutine.resume(receiver, "modem_message", "right", 9001, 9001, resume))
    assert(saved.mode == "MINING")
    ok, why = coroutine.resume(worker)
    assert(ok, why)
    assert(coroutine.status(worker) == "dead" and saved.mode == "COMPLETE")
  end,
}

local ok, reason = pcall(dofile, "drone/main.lua")
assert(not ok and tostring(reason):find("test finished", 1, true))
assert(saved.lastError == nil and saved.lastResult == "COMPLETE")
local found
for _, packet in ipairs(packets) do
  if packet.type == "TASK_DONE" and packet.task == "test" then found = true end
end
assert(found, "completed task should be reported")
print("MineSwarm remote inventory pause/resume tests passed")
