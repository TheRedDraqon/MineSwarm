local packets, saved, sentTask, registrations = {}, nil, false, 0
local task = {
  id = "home-test", format = 4, fuelPercent = 75, total = 1,
  start = { x = 100, y = 100, z = 100 },
  bounds = { x1 = 100, x2 = 100, y1 = -21, y2 = -1, z1 = 100, z2 = 100 },
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
  return {
    load = function() return { progress = 0, mode = "IDLE" } end,
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
    end,
  }
end
package.preload["shared.pose"] = function()
  return {
    calibrate = function() return { x = 100, y = 100, z = 100, dir = 0 } end,
    turnTo = function(pose, direction) pose.dir = direction end,
  }
end
package.preload["drone.home"] = function()
  return {
    coreSlot = function() return 1 end,
    register = function(state, pose)
      registrations = registrations + 1
      assert(state.home.x == pose.x and state.home.y == pose.y and state.home.z == pose.z)
      return true
    end,
  }
end
package.preload["drone.miner"] = function()
  return {
    refuel = function() return true end,
    run = function(_, current, callbacks)
      assert(current.format == 4 and current.fuelPercent == 75 and current.useCore)
      assert(current.home.x == 100 and current.home.dropDir == 2 and current.needsInitialFuel)
      callbacks.waitForService("Warp destination blocked")
      return true, nil, 1
    end,
  }
end
turtle = {
  getFuelLevel = function() return 100 end,
  inspectUp = function() return true, { name = "enderchests:ender_chest" } end,
  inspect = function() return true, { name = "enderchests:ender_chest" } end,
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
    assert(ok and why == "sleep" and saved.mode == "PAUSED_SERVICE")
    assert(saved.lastError == "Warp destination blocked")
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
assert(not ok and tostring(reason):find("test finished", 1, true), tostring(reason))
assert(registrations == 2 and saved.home.x == 100 and saved.lastResult == "COMPLETE",
  "registrations=" .. registrations .. " result=" .. tostring(saved.lastResult)
    .. " packet=" .. tostring(packets[#packets] and packets[#packets].reason))
assert(packets[#packets].type == "TASK_DONE")
print("MineSwarm home assignment and service pause tests passed")
