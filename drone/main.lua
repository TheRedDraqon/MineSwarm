package.path = "/mineswarm/?.lua;/mineswarm/?/init.lua;" .. package.path

local config = require("shared.config")
local util = require("shared.util")
local net = require("shared.net")
local stateLib = require("shared.state")
local poseLib = require("shared.pose")
local miner = require("drone.miner")

local dataPath = "/mineswarm/simple_drone_state"
local state = stateLib.load(dataPath, { progress = 0, mode = "IDLE" })
local label = os.getComputerLabel()
if not label or label == "" then
  label = "Miner_" .. os.getComputerID()
  os.setComputerLabel(label)
end
local pose, reason = poseLib.calibrate()
if not pose then error(reason) end
local activeTask = state.task
local paused = activeTask ~= nil and (state.mode == "PAUSED" or state.mode == "PAUSED_FULL")
if not activeTask then state.mode = "IDLE" end
local lastHeartbeat = 0

local function save()
  state.pose = { x = pose.x, y = pose.y, z = pose.z, dir = pose.dir }
  stateLib.save(state, dataPath)
end

local function heartbeat()
  net.send({
    type = "HB", label = label, computerId = os.getComputerID(),
    pos = { x = pose.x, y = pose.y, z = pose.z }, dir = pose.dir,
    fuel = turtle.getFuelLevel(), inventory = util.slotCount(), state = state.mode,
    task = activeTask and activeTask.id or nil, progress = state.progress,
    lastTask = state.lastTask, lastResult = state.lastResult, error = state.lastError,
  })
  lastHeartbeat = os.clock()
end

local function hasChestBehind()
  local direction = pose.dir
  poseLib.turnTo(pose, (direction + 2) % 4)
  local found, block = turtle.inspect()
  poseLib.turnTo(pose, direction)
  return found and type(block.name) == "string" and block.name:lower():match("chest$") ~= nil
end

local function reject(task, message)
  net.send({ type = "NACK", label = label, task = type(task) == "table" and task.id, reason = message })
end

local function validTask(task)
  if type(task) ~= "table" or task.format ~= 2 or type(task.id) ~= "string"
    or type(task.start) ~= "table" or type(task.bounds) ~= "table" then return false end
  for _, field in ipairs({ "x1", "x2", "y1", "y2", "z1", "z2" }) do
    local value = task.bounds[field]
    if type(value) ~= "number" or value % 1 ~= 0 or math.abs(value) >= 30000000 then return false end
  end
  for _, axis in ipairs({ "x", "y", "z" }) do
    local value = task.start[axis]
    if type(value) ~= "number" or value % 1 ~= 0 or math.abs(value) >= 30000000 then return false end
  end
  local b = task.bounds
  if b.x1 > b.x2 or b.y1 > b.y2 or b.z1 > b.z2 then return false end
  return task.start.x >= b.x1 and task.start.x <= b.x2
    and task.start.z >= b.z1 and task.start.z <= b.z2
    and task.total == (b.x2 - b.x1 + 1) * (b.z2 - b.z1 + 1)
end

local function handleCommand(packet)
  if packet.target ~= label and packet.target ~= os.getComputerID() then return end
  if packet.type == "TASK" then
    local task = packet.task
    if type(task) == "table" and type(task.id) == "string" then
      if activeTask and activeTask.id == task.id then
        net.send({ type = "ACK", label = label, task = task.id })
        return
      elseif not activeTask and state.lastTask == task.id then
        net.send({ type = state.lastResult == "COMPLETE" and "TASK_DONE" or "TASK_ERROR",
          label = label, task = task.id, reason = state.lastError })
        return
      end
    end
    if activeTask then reject(task, "Drone already has an active job"); return end
    if not validTask(task) then
      reject(task, "Invalid job"); return
    end
    if task.start.x ~= pose.x or task.start.y ~= pose.y or task.start.z ~= pose.z then
      reject(task, "GPS position changed; refresh and assign again"); return
    end
    task.home = { x = pose.x, y = pose.y, z = pose.z, dropDir = (pose.dir + 2) % 4 }
    task.chest = hasChestBehind()
    activeTask, state.task = task, task
    state.progress, state.mode, state.lastError = 0, "ASSIGNED", nil
    state.lastTask, state.lastResult = nil, nil
    paused = false
    save()
    net.send({ type = "ACK", label = label, task = task.id })
    heartbeat()
  elseif packet.type == "CMD" and activeTask then
    if packet.action == "PAUSE" then
      paused = true
      if state.mode ~= "PAUSED_FULL" then state.mode = "PAUSED" end
    elseif packet.action == "RESUME" then
      if state.mode == "PAUSED_FULL" and util.inventoryFull() then
        state.lastError = "Inventory still full; clear a slot before resuming"
      else
        paused, state.lastError, state.mode = false, nil, "MINING"
      end
    end
    save()
    heartbeat()
  end
end

local function listener()
  local timer = os.startTimer(1)
  while true do
    local event = { os.pullEventRaw() }
    if net.isModemMessage(event) then
      handleCommand(event[5])
    elseif event[1] == "timer" and event[2] == timer then
      if os.clock() - lastHeartbeat >= config.heartbeatSeconds then heartbeat() end
      timer = os.startTimer(1)
    elseif event[1] == "mineswarm_task_complete" then
      return
    end
  end
end

local function runTask()
  local task = activeTask
  local callbacks = {
    alert = function(block, pos)
      net.send({ type = "ALERT", label = label, block = block, pos = pos })
    end,
    setState = function(mode)
      if not paused then state.mode = mode end
      save()
      heartbeat()
    end,
    progress = function(done, total, currentPose)
      state.progress, pose = done, currentPose
      save()
      heartbeat()
    end,
    tick = function(currentPose)
      pose = currentPose
      while paused do os.sleep(0.25) end
      os.sleep(0)
    end,
    waitForSpace = function()
      paused, state.mode = true, "PAUSED_FULL"
      state.lastError = "Inventory full; clear a slot and press RESUME"
      save()
      heartbeat()
      while paused do os.sleep(0.25) end
    end,
  }
  local ok, taskReason, progress = miner.run(pose, task, callbacks, state.progress)
  if progress then state.progress = progress end
  state.mode = ok and "COMPLETE" or "ERROR"
  if ok then state.lastError = nil else state.lastError = tostring(taskReason) end
  state.lastTask, state.lastResult = task.id, state.mode
  state.task, activeTask = nil, nil
  paused = false
  save()
  heartbeat()
  net.send({ type = ok and "TASK_DONE" or "TASK_ERROR", label = label,
    task = task.id, reason = taskReason })
  os.queueEvent("mineswarm_task_complete")
end

save()
net.open()
util.log("Simple drone online as", label)
heartbeat()
local timer = os.startTimer(1)
while true do
  if activeTask then
    parallel.waitForAny(runTask, listener)
    timer = os.startTimer(1)
  else
    local event = { os.pullEventRaw() }
    if net.isModemMessage(event) then handleCommand(event[5]) end
    if event[1] == "timer" and event[2] == timer then
      heartbeat()
      timer = os.startTimer(1)
    end
  end
end
