package.path = "/mineswarm/?.lua;/mineswarm/?/init.lua;" .. package.path

local config = require("shared.config")
local util = require("shared.util")
local net = require("shared.net")
local stateLib = require("shared.state")
local oreDb = require("master.ore_db")
local quarries = require("master.quarries")
local uiLib = require("master.ui")

local dataPath = "/mineswarm/simple_master_state"
local state = stateLib.load(dataPath, { drones = {}, jobs = {}, waypoints = {} })
for _, drone in pairs(state.drones) do drone.online = false end
for _, job in pairs(state.jobs) do
  if quarries.active(job) then job.status = "OFFLINE" end
end

local monitor = peripheral.find("monitor")
if not monitor then error("Attach an Advanced Monitor") end
if type(monitor.isColor) == "function" and not monitor.isColor() then
  error("MineSwarm requires an Advanced Monitor")
end
local monitorName = peripheral.getName(monitor)
local ui

local function save()
  stateLib.save(state, dataPath)
end

local function activeJob(label)
  for _, job in pairs(state.jobs) do
    if job.label == label and quarries.active(job) then return job end
  end
end

local function launch(label, xInput, zInput, preset, minY, maxY)
  local drone = label and state.drones[label]
  if not drone or not drone.online or os.clock() - drone.lastSeen > config.heartbeatTimeout
    or (drone.state ~= "IDLE" and drone.state ~= "COMPLETE") or activeJob(label) then
    ui.setMessage("Select an online idle drone without an active job")
    return
  end
  local y1, y2
  if preset == "Custom" then
    y1, y2 = tonumber(minY), tonumber(maxY)
  else
    y1, y2 = oreDb.jobY(preset)
    if not y1 then ui.setMessage(y2); return end
  end
  local bounds, reason = quarries.bounds(drone.pos, xInput, zInput, y1, y2)
  if not bounds then ui.setMessage(reason); return end
  local overlap = quarries.findOverlap(bounds, state.jobs)
  if overlap then
    ui.setMessage("X/Z area overlaps active job " .. tostring(overlap))
    return
  end

  for oldId, job in pairs(state.jobs) do
    if job.label == label and not quarries.active(job) then state.jobs[oldId] = nil end
  end
  local id = os.epoch("utc")
  while state.jobs[tostring(id)] do id = id + 1 end
  id = tostring(id)
  local total = (bounds.x2 - bounds.x1 + 1) * (bounds.z2 - bounds.z1 + 1)
  local start = util.copy(drone.pos)
  local task = { id = id, bounds = bounds, start = start, total = total, format = 2 }
  state.jobs[id] = {
    id = id, label = label, bounds = bounds, preset = preset,
    status = "ASSIGNED", progress = 0, total = total,
    assignedAt = os.clock(), task = task,
  }
  save()
  net.send({ type = "TASK", target = label, task = task })
  ui.setMessage("Assigned " .. label .. " job " .. id)
  util.log("Assigned", label, "job", id)
end

local function command(label, action)
  if not label or not state.drones[label] then
    ui.setMessage("Select a drone first")
    return
  end
  net.send({ type = "CMD", target = label, action = action })
  ui.setMessage(action .. " requested for " .. label)
end

local function clearWaypoint(index)
  table.remove(state.waypoints, index)
  save()
end

ui = uiLib.new(monitor, state, {
  launch = launch, command = command, clearWaypoint = clearWaypoint,
})

local function handleHeartbeat(packet)
  if type(packet.label) ~= "string" or packet.label == "" then return end
  local drone = state.drones[packet.label] or {}
  drone.online, drone.lastSeen = true, os.clock()
  drone.computerId, drone.dir = packet.computerId, packet.dir
  if type(packet.pos) == "table" and type(packet.pos.x) == "number"
    and type(packet.pos.y) == "number" and type(packet.pos.z) == "number" then
    drone.pos = { x = packet.pos.x, y = packet.pos.y, z = packet.pos.z }
  else
    drone.pos = nil
  end
  drone.state, drone.task = packet.state or "UNKNOWN", packet.task
  drone.fuel, drone.inventory, drone.error = packet.fuel, packet.inventory, packet.error
  state.drones[packet.label] = drone
  local job = activeJob(packet.label)
  if job and packet.task == job.id then
    job.accepted = true
    job.status = drone.state
    if type(packet.progress) == "number" then
      job.progress = util.clamp(math.floor(packet.progress), 0, job.total)
    end
  elseif job and packet.lastTask == job.id then
    if packet.lastResult == "COMPLETE" then
      job.status, job.progress = "COMPLETE", job.total
    elseif packet.lastResult == "ERROR" then
      job.status, job.error = "ERROR", tostring(packet.error)
    end
  end
  save()
end

local function handlePacket(packet)
  if packet.type == "HB" then
    handleHeartbeat(packet)
  elseif packet.type == "ALERT" then
    local pos = packet.pos
    if type(pos) ~= "table" or type(pos.x) ~= "number"
      or type(pos.y) ~= "number" or type(pos.z) ~= "number" then
      util.log("Rejected malformed waypoint from", packet.label)
      return
    end
    for _, point in ipairs(state.waypoints) do
      if point.pos.x == pos.x and point.pos.y == pos.y and point.pos.z == pos.z
        and point.block == packet.block then return end
    end
    state.waypoints[#state.waypoints + 1] = {
      label = tostring(packet.label), block = tostring(packet.block),
      pos = { x = pos.x, y = pos.y, z = pos.z },
    }
    save()
    util.log("Waypoint", packet.block, pos.x, pos.y, pos.z)
  elseif packet.type == "ACK" or packet.type == "NACK"
    or packet.type == "TASK_DONE" or packet.type == "TASK_ERROR" then
    local job = activeJob(packet.label)
    if job and packet.task == job.id then
      if packet.type == "ACK" then job.accepted = true
      elseif packet.type == "TASK_DONE" then job.status, job.progress = "COMPLETE", job.total
      else job.status, job.error = "ERROR", tostring(packet.reason) end
      save()
      ui.setMessage(packet.label .. ": " .. (packet.reason or packet.type))
      util.log(packet.label, packet.type, packet.reason or "")
    end
  end
end

net.open()
ui.draw()
util.log("Simple master online; modem", net.side(), "monitor", monitorName)
local timer = os.startTimer(1)
while true do
  local event = { os.pullEventRaw() }
  if event[1] == "key" and event[2] == keys.q and not ui.inputField then
    print("MineSwarm master stopped; drones continue their jobs.")
    break
  elseif net.isModemMessage(event) then
    handlePacket(event[5])
    ui.draw()
  elseif event[1] == "monitor_touch" and event[2] == monitorName then
    ui.touch(event[3], event[4])
    ui.draw()
  elseif event[1] == "char" or event[1] == "key" then
    if ui.handleInput(event[1], event[2]) then ui.draw() end
  elseif event[1] == "timer" and event[2] == timer then
    local now = os.clock()
    for label, drone in pairs(state.drones) do
      if now - (drone.lastSeen or 0) > config.heartbeatTimeout then drone.online = false end
      local job = activeJob(label)
      if job and (not drone.online or (not job.accepted and job.assignedAt
        and now - job.assignedAt > config.heartbeatTimeout)) then
        job.status = "OFFLINE"
      end
      if job and drone.online and not job.accepted and job.task
        and now - (job.assignedAt or 0) >= config.heartbeatSeconds then
        net.send({ type = "TASK", target = label, task = job.task })
        job.assignedAt = now
      end
    end
    ui.draw()
    timer = os.startTimer(1)
  end
end
