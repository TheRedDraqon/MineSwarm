package.path = "/mineswarm/?.lua;/mineswarm/?/init.lua;" .. package.path

local config = require("shared.config")
local util = require("shared.util")
local net = require("shared.net")
local stateLib = require("shared.state")
local oreDb = require("master.ore_db")
local partition = require("master.partition")
local quarries = require("master.quarries")
local uiLib = require("master.ui")
local configEditor = require("master.config_editor")

local dataPath = config.stateFile
local state = stateLib.load(dataPath, {
  drones = {}, job = nil, quarries = {}, waypoints = {}, yield = {}, events = {},
})
state.quarries = state.quarries or {}
for label, drone in pairs(state.drones) do
  drone.online = false
  drone.lastSeen = 0
  local assignment = state.job and state.job.assignments and state.job.assignments[label]
  if assignment and assignment.status ~= "COMPLETE" and assignment.status ~= "ERROR" then
    assignment.status = "OFFLINE"
    state.job.status = "DEGRADED"
  end
end
for _, quarry in pairs(state.quarries) do
  if quarries.active(quarry) then quarry.status = "OFFLINE" end
end

local settingsPath = "/mineswarm/master_config"
local settingsDefaults = {
  configured = false,
  mode = "simple",
  home = nil,
  origin = nil,
  deployerLabel = "Deployer",
}
local settings = stateLib.load(settingsPath, settingsDefaults)
if settings.mode ~= "simple" and settings.mode ~= "complex" then settings.mode = "simple" end

local monitor = peripheral.find("monitor")
if not monitor then error("No Advanced Monitor peripheral found") end
if type(monitor.isColor) == "function" and not monitor.isColor() then
  error("MineSwarm touchscreen requires an Advanced Monitor")
end
local monitorName = peripheral.getName(monitor)
local ui

local function save()
  stateLib.save(state, dataPath)
end

local function logEvent(message)
  state.events[#state.events + 1] = { time = os.epoch("utc"), message = tostring(message) }
  while #state.events > 100 do table.remove(state.events, 1) end
  util.log(message)
  save()
end

local function recountProgress()
  if not state.job then return end
  local progress = 0
  for _, assignment in pairs(state.job.assignments or {}) do
    progress = progress + math.min(assignment.total, assignment.progress or 0)
  end
  state.job.progress = progress
end

local function sendCommand(target, action)
  net.send({ type = "CMD", target = target, action = action })
end

local function assignedToActiveJob(label)
  local assignment = state.job and state.job.assignments and state.job.assignments[label]
  if assignment and assignment.status ~= "COMPLETE" and assignment.status ~= "ERROR"
    and assignment.status ~= "IDLE" then return true end
  for _, quarry in pairs(state.quarries) do
    if quarry.label == label and quarries.active(quarry) then return true end
  end
  return false
end

local function deploy()
  if type(settings.deployerLabel) ~= "string" or settings.deployerLabel == "" then
    ui.setMessage("Set deployerLabel in /mineswarm/master_config")
    return
  end
  net.send({ type = "CMD", target = settings.deployerLabel, action = "DEPLOY" })
  ui.setMessage("Deployment requested from " .. settings.deployerLabel)
end

local function availableDrones()
  local result = {}
  local now = os.clock()
  for label, drone in pairs(state.drones) do
    if drone.online and now - (drone.lastSeen or 0) <= config.heartbeatTimeout
      and (drone.state == "IDLE" or drone.state == "COMPLETE")
      and not assignedToActiveJob(label) then
      result[#result + 1] = label
    end
  end
  table.sort(result)
  return result
end

local function validDimensions(width, length)
  return type(width) == "number" and type(length) == "number"
    and width >= 1 and length >= 1
    and width % 1 == 0 and length % 1 == 0
end

local function jobBounds(originX, originZ, width, length, y1, y2)
  return {
    x1 = originX,
    x2 = originX + width - 1,
    y1 = y1,
    y2 = y2,
    z1 = originZ,
    z2 = originZ + length - 1,
  }
end

local function newJobId()
  local id = os.epoch("utc")
  while state.quarries[tostring(id)] ~= nil
    or (state.job and tostring(state.job.id) == tostring(id)) do
    id = id + 1
  end
  return tostring(id)
end

local function launchComplex(mode, preset, width, length, depth)
  if settings.configured ~= true or type(settings.home) ~= "table" or type(settings.home.x) ~= "number"
    or type(settings.home.y) ~= "number" or type(settings.home.z) ~= "number" then
    ui.setMessage("Set configured=true and FOB x/y/z in /mineswarm/master_config")
    return
  end
  if settings.home.x % 1 ~= 0 or settings.home.y % 1 ~= 0 or settings.home.z % 1 ~= 0
    or type(settings.home.dir) ~= "number" or settings.home.dir % 1 ~= 0
    or settings.home.dir < 0 or settings.home.dir > 3 then
    ui.setMessage("FOB coordinates must be whole numbers and dir must be 0..3")
    return
  end
  local origin = settings.origin or settings.home
  if type(origin) ~= "table" or type(origin.x) ~= "number" or type(origin.z) ~= "number"
    or origin.x % 1 ~= 0 or origin.z % 1 ~= 0 then
    ui.setMessage("Job origin X/Z must be whole numbers")
    return
  end
  if state.job and (state.job.status == "RUNNING" or state.job.status == "DEGRADED") then
    ui.setMessage("A job is already active; pause/recall it before launching another")
    return
  end
  if not validDimensions(width, length) then
    ui.setMessage("Width and length must be positive whole numbers")
    return
  end
  local y1, y2 = oreDb.jobY(mode, preset, depth)
  if not y1 then ui.setMessage(y2); return end

  local labels = availableDrones()
  if #labels == 0 then ui.setMessage("No online idle drones are available"); return end
  local bounds = jobBounds(origin.x, origin.z, width, length, y1, y2)
  local overlap = quarries.findOverlap(bounds, state)
  if overlap then
    ui.setMessage("Area overlaps active quarry/job " .. tostring(overlap))
    return
  end
  local sectors, reason = partition.divide(bounds, #labels)
  if not sectors then ui.setMessage(reason); return end

  local jobId = newJobId()
  local assignments = {}
  for index, sector in ipairs(sectors) do
    local label = labels[index]
    local columns = (sector.x2 - sector.x1 + 1) * (sector.z2 - sector.z1 + 1)
    local total = columns
    assignments[label] = {
      sector = sector, total = total, columns = columns, progress = 0,
      status = "ASSIGNED", taskId = jobId .. ":" .. sector.id, assignedAt = os.clock(),
    }
    net.send({
      type = "TASK",
      target = label,
      jobId = jobId,
      task = {
        id = jobId .. ":" .. sector.id,
        bounds = sector,
        home = util.copy(settings.home),
        access = { x = bounds.x1 - index, z = bounds.z1 - 1 },
        total = columns,
      },
    })
  end

  state.job = {
    id = jobId,
    mode = mode,
    preset = preset,
    status = "RUNNING",
    bounds = bounds,
    assignments = assignments,
    total = width * length,
    progress = 0,
    started = os.epoch("utc"),
  }
  ui.setMessage(string.format("Launched %s job with %d drones", preset, #labels))
  save()
  logEvent("Launched " .. preset .. " job " .. jobId .. " using " .. #labels .. " drones")
end

local function launchSimple(mode, preset, width, length, depth, label)
  if not validDimensions(width, length) then
    ui.setMessage("Width and length must be positive whole numbers")
    return
  end
  local drone = label and state.drones[label]
  if not drone or not drone.online or os.clock() - (drone.lastSeen or 0) > config.heartbeatTimeout
    or (drone.state ~= "IDLE" and drone.state ~= "COMPLETE")
    or assignedToActiveJob(label) then
    ui.setMessage("Select one online idle drone")
    return
  end
  local home = drone.home
  local y1, y2 = oreDb.jobY(mode, preset, depth)
  if not y1 then ui.setMessage(y2); return end
  local bounds, boundsReason = quarries.fromHome(home, width, length, y1, y2)
  if not bounds then
    ui.setMessage(boundsReason .. "; update/restart it at its deposit")
    return
  end
  local overlap = quarries.findOverlap(bounds, state)
  if overlap then
    ui.setMessage("Area overlaps active quarry/job " .. tostring(overlap))
    return
  end

  local jobId = newJobId()
  local taskId = jobId .. ":S01"
  local columns = width * length
  state.quarries[jobId] = {
    id = jobId,
    mode = mode,
    preset = preset,
    status = "ASSIGNED",
    bounds = bounds,
    label = label,
    taskId = taskId,
    total = columns,
    progress = 0,
    home = util.copy(home),
    started = os.epoch("utc"),
    assignedAt = os.clock(),
  }
  save()
  net.send({
    type = "TASK",
    target = label,
    jobId = jobId,
    task = {
      id = taskId,
      bounds = bounds,
      home = util.copy(home),
      access = { x = home.x, z = home.z },
      total = columns,
    },
  })
  ui.setMessage(string.format("Launched %s quarry %s on %s", preset, jobId, label))
  logEvent("Launched " .. preset .. " quarry " .. jobId .. " on " .. label)
end

local function launch(mode, preset, width, length, depth, selectedDrone)
  if settings.mode == "simple" then
    launchSimple(mode, preset, width, length, depth, selectedDrone)
  else
    launchComplex(mode, preset, width, length, depth)
  end
end

local function clearWaypoint(index)
  table.remove(state.waypoints, index)
  save()
  ui.setMessage("Waypoint cleared")
end

local actions = {
  launch = launch,
  command = sendCommand,
  deploy = deploy,
  clearWaypoint = clearWaypoint,
}

ui = uiLib.new(monitor, state, settings, actions)
if settings.configured ~= true then
  if settings.mode == "simple" then
    ui.setMessage("Simple mode ready - choose a drone and quarry in JOB SETUP")
  else
  ui.setMessage("Master not configured - press C to set FOB coordinates")
  end
end

local function recordWaypoint(packet)
  local pos = packet.pos or packet.position
  if type(pos) ~= "table" or type(pos.x) ~= "number"
    or type(pos.y) ~= "number" or type(pos.z) ~= "number" then
    logEvent("Rejected malformed alert from " .. tostring(packet.label))
    return
  end
  local block = tostring(packet.block or "unknown")
  for _, waypoint in ipairs(state.waypoints) do
    if waypoint.block == block and waypoint.pos.x == pos.x and waypoint.pos.y == pos.y
      and waypoint.pos.z == pos.z then return end
  end
  state.waypoints[#state.waypoints + 1] = {
    block = block,
    label = packet.label,
    pos = { x = pos.x, y = pos.y, z = pos.z },
    time = os.epoch("utc"),
  }
  logEvent("Waypoint: " .. block .. " @ " .. pos.x .. "," .. pos.y .. "," .. pos.z)
end

local function handleHeartbeat(packet)
  if type(packet.label) ~= "string" or packet.label == "" then return end
  local drone = state.drones[packet.label] or {}
  drone.online = true
  drone.lastSeen = os.clock()
  drone.computerId = packet.computerId
  if type(packet.pos) == "table" and type(packet.pos.x) == "number"
    and type(packet.pos.y) == "number" and type(packet.pos.z) == "number" then
    drone.pos = { x = packet.pos.x, y = packet.pos.y, z = packet.pos.z }
  else
    drone.pos = nil
  end
  drone.dir = type(packet.dir) == "number" and packet.dir or nil
  if type(packet.home) == "table" and type(packet.home.x) == "number"
    and type(packet.home.y) == "number" and type(packet.home.z) == "number"
    and type(packet.home.dir) == "number" then
    drone.home = util.copy(packet.home)
  end
  drone.fuel = packet.fuel
  drone.inventory = packet.inventory
  drone.state = packet.state or "UNKNOWN"
  drone.task = packet.task
  drone.sectorProgress = type(packet.sector_progress) == "number"
    and util.clamp(packet.sector_progress, 0, 1) or 0
  drone.error = packet.error
  state.drones[packet.label] = drone
  for _, quarry in pairs(state.quarries) do
    if quarry.label == packet.label and quarry.status ~= "COMPLETE"
      and quarry.status ~= "ERROR" and quarry.status ~= "INCOMPLETE" then
      if packet.task == quarry.taskId then
        quarry.accepted = true
        quarry.progress = math.floor(quarry.total * drone.sectorProgress)
        quarry.status = drone.state == "ERROR" and "ERROR" or drone.state
      elseif drone.state == "COMPLETE" and packet.task == nil then
        quarry.progress = quarry.total
        quarry.status = "COMPLETE"
      elseif drone.state == "ERROR" and packet.task == nil then
        quarry.status = "ERROR"
      elseif drone.state == "IDLE" and packet.task == nil and quarry.accepted then
        quarry.status = "INCOMPLETE"
      end
    end
  end
  if state.job and state.job.assignments then
    local assignment = state.job.assignments[packet.label]
    if assignment then
      if drone.state == "COMPLETE" and packet.task == nil then
        assignment.progress = assignment.total
      elseif packet.task == assignment.taskId then
        assignment.progress = math.floor(assignment.total * drone.sectorProgress)
        state.job.status = "RUNNING"
      elseif drone.state == "ERROR" then
        assignment.status = "ERROR"
      end
      if drone.state == "COMPLETE" and packet.task == nil then
        assignment.status = "COMPLETE"
      elseif drone.state == "IDLE" and assignment.status == "COMPLETE" then
        assignment.status = "COMPLETE"
      elseif assignment.status == "ASSIGNED" and packet.task ~= assignment.taskId then
        -- Wait for the worker's task heartbeat instead of treating a stale idle packet as completion.
      else
        assignment.status = drone.state
      end
      recountProgress()
    end
  end
  save()
end

local function handlePacket(packet)
  if packet.type == "HB" then handleHeartbeat(packet)
  elseif packet.type == "ALERT" then recordWaypoint(packet)
  elseif packet.type == "YIELD" and type(packet.items) == "table" then
    for name, count in pairs(packet.items) do
      if type(name) == "string" and type(count) == "number" and count > 0 then
        state.yield[name] = (state.yield[name] or 0) + count
      end
    end
    save()
  elseif packet.type == "TASK_ERROR" or packet.type == "NACK" then
    for _, quarry in pairs(state.quarries) do
      if quarry.label == packet.label and quarry.status ~= "COMPLETE" then
        quarry.status = "ERROR"
      end
    end
    logEvent(tostring(packet.label) .. " reported " .. packet.type .. ": " .. tostring(packet.reason))
  elseif packet.type == "TASK_DONE" then
    logEvent(tostring(packet.label) .. " completed its task")
  elseif packet.type == "DEPLOYED" then
    logEvent("Deployer placed " .. tostring(packet.label or "a turtle"))
  elseif packet.type == "DEPLOY_ERROR" then
    logEvent("Deployer error: " .. tostring(packet.reason))
  end
end

net.open()
ui.draw()
util.log("Master C2 online; modem", net.side(), "monitor", monitorName)
local timer = os.startTimer(1)

while true do
  local event = { os.pullEventRaw() }
  if event[1] == "key" and event[2] == keys.q then
    print("MineSwarm master stopped. Returned to the shell.")
    break
  elseif event[1] == "key" and event[2] == keys.c then
    configEditor.run(settings, function(updatedSettings)
      stateLib.save(updatedSettings, settingsPath)
    end)
    ui.setMessage("Master configuration saved")
    ui.draw()
  elseif event[1] == "key" and event[2] == keys.m and not ui.inputField then
    settings.mode = settings.mode == "simple" and "complex" or "simple"
    stateLib.save(settings, settingsPath)
    ui.setMessage("Switched to " .. string.upper(settings.mode) .. " mode")
    ui.draw()
  elseif net.isModemMessage(event) then
    handlePacket(event[5])
  elseif event[1] == "monitor_touch" and event[2] == monitorName then
    ui.touch(event[3], event[4])
    ui.draw()
  elseif event[1] == "char" or event[1] == "key" then
    if ui.handleInput(event[1], event[2]) then ui.draw() end
  elseif event[1] == "timer" and event[2] == timer then
    local now = os.clock()
    for label, drone in pairs(state.drones) do
      if now - (drone.lastSeen or 0) > config.heartbeatTimeout then
        drone.online = false
        local assignment = state.job and state.job.assignments and state.job.assignments[label]
        if assignment and assignment.status ~= "COMPLETE" and assignment.status ~= "ERROR" then
          assignment.status = "OFFLINE"
          state.job.status = "DEGRADED"
        end
        for _, quarry in pairs(state.quarries) do
          if quarry.label == label and quarries.active(quarry)
            and (not drone.online or (quarry.status == "ASSIGNED"
              and now - (quarry.assignedAt or now) > config.heartbeatTimeout)) then
            quarry.status = "OFFLINE"
          end
        end
      end
      if state.job and state.job.assignments then
        for label, assignment in pairs(state.job.assignments) do
          if assignment.status == "ASSIGNED"
            and now - (assignment.assignedAt or now) > config.heartbeatTimeout then
            assignment.status = "OFFLINE"
            state.job.status = "DEGRADED"
            local drone = state.drones[label]
            if drone then drone.online = false end
          end
        end
      end
    end
    if state.job then
      local allDone = true
      for _, assignment in pairs(state.job.assignments or {}) do
        if assignment.status ~= "COMPLETE" and assignment.status ~= "IDLE"
          and assignment.status ~= "ERROR" then allDone = false end
      end
      if allDone and (state.job.status == "RUNNING" or state.job.status == "DEGRADED") then
        state.job.status = state.job.progress >= state.job.total and "COMPLETE" or "INCOMPLETE"
      end
    end
    ui.draw()
    timer = os.startTimer(1)
  end
  if net.isModemMessage(event) then ui.draw() end
end
