package.path = "/mineswarm/?.lua;/mineswarm/?/init.lua;" .. package.path

local config = require("shared.config")
local util = require("shared.util")
local net = require("shared.net")
local stateLib = require("shared.state")
local poseLib = require("shared.pose")
local miner = require("drone.miner")

local dataPath = "/mineswarm/drone_state"
local state = stateLib.load(dataPath, {
  label = nil, pose = nil, task = nil, progress = 0, mode = "IDLE", lastError = nil,
})
local label = os.getComputerLabel()
if not label or label == "" then
  label = state.label or ("Miner_" .. tostring(os.getComputerID()))
  os.setComputerLabel(label)
end
state.label = label
local pose, poseReason = poseLib.calibrate()
if not pose then error(poseReason) end
state.pose = pose
if not state.task then
  state.home = {
    x = pose.x,
    y = pose.y,
    z = pose.z,
    dir = pose.dir,
    dropDir = (pose.dir + 2) % 4,
  }
elseif not state.home then
  state.home = state.task.home or {
    x = pose.x, y = pose.y, z = pose.z, dir = pose.dir, dropDir = (pose.dir + 2) % 4,
  }
end
stateLib.save(state, dataPath)

local paused = false
local recallRequested = false
local activeTask = state.task
local lastHeartbeat = 0

local function save()
  state.pose = pose
  stateLib.save(state, dataPath)
end

local function sendHeartbeat()
  local slots = util.slotCount()
  net.send({
    type = "HB",
    label = label,
    computerId = os.getComputerID(),
    pos = { x = pose.x, y = pose.y, z = pose.z },
    home = state.home,
    dir = pose.dir,
    fuel = turtle.getFuelLevel(),
    inventory = slots,
    state = state.mode,
    task = activeTask and activeTask.id or nil,
    sector_progress = activeTask and (state.progress / math.max(1, activeTask.total or 1)) or 0,
    error = state.lastError,
  })
  lastHeartbeat = os.clock()
end

local function handleCommand(packet)
  local target = packet.target or packet.target_label
  if target ~= "ALL" and target ~= label and target ~= os.getComputerID() then return end
  local action = packet.action
  if packet.type == "TASK" then
    if activeTask then
      net.send({ type = "NACK", label = label, reason = "Drone already has an active task" })
      return
    end
    activeTask = packet.task or packet
    activeTask.id = activeTask.id or packet.jobId or "job"
    state.task = activeTask
    state.progress = 0
    state.mode = "ASSIGNED"
    state.lastError = nil
    save()
    net.send({ type = "ACK", label = label, task = activeTask.id })
  elseif packet.type == "CMD" then
    if action == "PAUSE" then
      paused = true
      state.mode = "PAUSED"
    elseif action == "RESUME" then
      paused = false
      if activeTask then state.mode = "MINING" end
    elseif action == "RECALL" then
      if activeTask then recallRequested = true end
    elseif action == "REBOOT" then
      save()
      os.reboot()
    elseif action == "SET_LABEL" and type(packet.label) == "string" then
      label = packet.label
      os.setComputerLabel(label)
      state.label = label
    end
    save()
  end
end

local function listener()
  local timer = os.startTimer(1)
  while true do
    local event = { os.pullEventRaw() }
    if net.isModemMessage(event) then
      handleCommand(event[5])
    elseif event[1] == "timer" and event[2] == timer then
      if os.clock() - lastHeartbeat >= config.heartbeatSeconds then sendHeartbeat() end
      timer = os.startTimer(1)
    elseif event[1] == "mineswarm_task_complete" then
      return
    end
  end
end

local function runTask()
  if not activeTask then return end
  state.mode = "MINING"
  local callbacks = {
    alert = function(block, position)
      net.send({
        type = "ALERT", label = label, block = block,
        pos = { x = position.x, y = position.y, z = position.z },
      })
    end,
    yield = function(items)
      net.send({ type = "YIELD", label = label, items = items })
    end,
    setState = function(mode)
      state.mode = mode
      save()
      sendHeartbeat()
    end,
    progress = function(done, total, currentPose)
      state.progress = done
      pose = currentPose
      save()
      sendHeartbeat()
    end,
    tick = function(currentPose)
      pose = currentPose
      if paused then
        state.mode = "PAUSED"
        save()
        while paused do os.sleep(0.25) end
        state.mode = "MINING"
      end
      os.sleep(0)
    end,
    recallRequested = function() return recallRequested end,
  }
  local ok, reason, progress = miner.run(pose, activeTask, callbacks, state.progress)
  if progress then state.progress = progress end
  if ok then state.lastError = nil else state.lastError = tostring(reason) end
  state.mode = ok and (reason == "recalled" and "IDLE" or "COMPLETE") or "ERROR"
  state.task = nil
  activeTask = nil
  recallRequested = false
  paused = false
  save()
  sendHeartbeat()
  net.send({ type = ok and "TASK_DONE" or "TASK_ERROR", label = label, reason = reason })
  os.queueEvent("mineswarm_task_complete")
end

net.open()
util.log("Drone online as", label, "computer", os.getComputerID())
sendHeartbeat()

local idleTimer = os.startTimer(1)
while true do
  if activeTask then
    parallel.waitForAny(runTask, listener)
    idleTimer = os.startTimer(1)
  else
    local event = { os.pullEventRaw() }
    if net.isModemMessage(event) then handleCommand(event[5]) end
    if event[1] == "timer" and event[2] == idleTimer then
      sendHeartbeat()
      idleTimer = os.startTimer(1)
    end
  end
end
