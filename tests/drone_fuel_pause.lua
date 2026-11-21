local packets, saved, sentTask = {}, nil, 0
local chestAvailable, supplyAvailable = false, false
local task = {
  id = "fuel-test", format = 3, total = 1,
  start = { x = 100, y = 100, z = 100 },
  bounds = { x1 = 100, x2 = 100, y1 = -21, y2 = -1, z1 = 100, z2 = 100 },
  dump = { x = 99, y = 0, z = 100, dropDir = 3 },
}
package.preload["shared.config"] = function() return { heartbeatSeconds = 5 } end
package.preload["shared.util"] = function()
  return {
    log = function() end, slotCount = function() return 1 end,
    inventoryFull = function() return false end,
    isDroneLabel = dofile("shared/util.lua").isDroneLabel,
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
    save = function(state)
      local seen = {}
      local function visit(value)
        if type(value) ~= "table" then return end
        assert(not seen[value], "drone state contains a repeated table")
        seen[value] = true
        for key, entry in pairs(value) do visit(key); visit(entry) end
      end
      visit(state)
      saved = state
    end }
end
package.preload["shared.pose"] = function()
  return {
    calibrate = function() return { x = 100, y = 100, z = 100, dir = 0 } end,
    directionDelta = function() return { x = -1, z = 0 } end,
  }
end
package.preload["drone.miner"] = function()
  return {
    refuel = function() return true end,
    chestSlot = function() return chestAvailable and 1 or nil end,
    run = function(_, current, callbacks)
      current.logistics.phase, current.chest = "READY", true
      callbacks.checkpoint()
      callbacks.waitForFuel("Supply chest needs coal")
      return true, nil, 1
    end,
  }
end
turtle = {
  getFuelLevel = function() return 100 end,
  inspectUp = function() return supplyAvailable, { name = "minecraft:chest" } end,
}
os.getComputerLabel = function() return "Drone1" end
os.getComputerID = function() return 1 end
os.startTimer = function() return 1 end
os.queueEvent = function() end
os.sleep = function() coroutine.yield("sleep") end
os.pullEventRaw = function()
  local _, isMain = coroutine.running()
  if isMain then
    if sentTask < 3 then
      if sentTask == 1 then
        assert(packets[#packets].type == "NACK" and packets[#packets].reason:find("dump chest", 1, true))
        chestAvailable = true
      elseif sentTask == 2 then
        assert(packets[#packets].type == "NACK" and packets[#packets].reason:find("supply chest", 1, true))
        supplyAvailable = true
      end
      sentTask = sentTask + 1
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
    assert(ok and why == "sleep" and saved.mode == "PAUSED_FUEL")
    assert(saved.lastError == "Supply chest needs coal" and saved.lastDump.x == 99)
    assert(coroutine.resume(receiver))
    assert(coroutine.resume(receiver, "modem_message", "right", 9001, 9001,
      { type = "CMD", target = "Drone1", action = "RESUME" }))
    assert(saved.mode == "MINING")
    ok, why = coroutine.resume(worker)
    assert(ok, why)
    assert(coroutine.status(worker) == "dead" and saved.mode == "COMPLETE")
  end,
}
local ok, reason = pcall(dofile, "drone/main.lua")
assert(not ok and tostring(reason):find("test finished", 1, true))
assert(saved.lastResult == "COMPLETE" and saved.lastDump.x == 99)
local found
for _, packet in ipairs(packets) do
  if packet.type == "HB" and packet.dump and packet.dump.x == 99 then found = true end
end
assert(found, "dump location must be reported to the master")
print("MineSwarm remote fuel pause/resume tests passed")
