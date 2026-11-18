package.path = "/mineswarm/?.lua;/mineswarm/?/init.lua;" .. package.path

local config = require("shared.config")
local util = require("shared.util")
local net = require("shared.net")
local stateLib = require("shared.state")
local oreDb = require("master.ore_db")
local partition = require("master.partition")
local uiLib = require("master.ui")
local configEditor = require("master.config_editor")

local dataPath = config.stateFile
local state = stateLib.load(dataPath, {
  drones = {}, job = nil, waypoints = {}, yield = {}, events = {},
})
for label, drone in pairs(state.drones) do
  drone.online = false
  drone.lastSeen = 0
  local assignment = state.job and state.job.assignments and state.job.assignments[label]
  if assignment and assignment.status ~= "COMPLETE" and assignment.status ~= "ERROR" then
    assignment.status = "OFFLINE"
    state.job.status = "DEGRADED"
  end
end

local settingsPath = "/mineswarm/master_config"
local settingsDefaults = {
  configured = false,
  home = nil,
  origin = nil,
  deployerLabel = "Deployer",
}
local settings = stateLib.load(settingsPath, settingsDefaults)

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
      and (drone.state == "IDLE" or drone.state == "COMPLETE") then
      result[#result + 1] = label
    end
  end
  table.sort(result)
  return result
end

local function launch(mode, preset, width, length, depth)
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
  if width < 1 or length < 1 or width % 1 ~= 0 or length % 1 ~= 0 then
    ui.setMessage("Width and length must be positive whole numbers")
    return
  end
  local y1, y2 = oreDb.jobY(mode, preset, depth)
  if not y1 then ui.setMessage(y2); return end

  local labels = availableDrones()
  if #labels == 0 then ui.setMessage("No online idle drones are available"); return end
  local bounds = {
    x1 = origin.x,
    x2 = origin.x + width - 1,
    y1 = y1,
    y2 = y2,
    z1 = origin.z,
    z2 = origin.z + length - 1,
  }
  local sectors, reason = partition.divide(bounds, #labels)
  if not sectors then ui.setMessage(reason); return end

  local jobId = tostring(os.epoch("utc"))
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
  ui.setMessage("Master not configured - press C to set FOB coordinates")
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
  drone.fuel = packet.fuel
  drone.inventory = packet.inventory
  drone.state = packet.state or "UNKNOWN"
  drone.task = packet.task
  drone.sectorProgress = type(packet.sector_progress) == "number"
    and util.clamp(packet.sector_progress, 0, 1) or 0
  drone.error = packet.error
  state.drones[packet.label] = drone
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
