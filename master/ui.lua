local util = require("mineswarm.shared.util")
local oreDb = require("mineswarm.master.ore_db")

local M = {}

local function clipped(text, width)
  text = tostring(text or "")
  if #text > width then return text:sub(1, math.max(0, width - 3)) .. "..." end
  return text .. string.rep(" ", math.max(0, width - #text))
end

function M.new(monitor, state, settings, actions)
  local ui = {
    monitor = monitor,
    state = state,
    settings = settings,
    actions = actions,
    tab = 1,
    buttons = {},
    selectedDrone = nil,
    mode = "ore",
    oreNames = util.sortedKeys(oreDb.ores),
    layerNames = util.sortedKeys(oreDb.layers),
    selectedPreset = "Osmium",
    width = 100,
    length = 100,
    depth = 50,
    scroll = 0,
    message = "Ready",
  }
  monitor.setTextScale(0.5)

  local function size()
    return monitor.getSize()
  end

  local function button(x, y, width, text, callback, color)
    if x < 1 or y < 1 then return end
    monitor.setBackgroundColor(color or colors.gray)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(x, y)
    monitor.write(clipped(text, width))
    ui.buttons[#ui.buttons + 1] = {
      x1 = x, y1 = y, x2 = x + width - 1, y2 = y, callback = callback,
    }
  end

  local function line(x, y, width, text, color)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(color or colors.white)
    monitor.setCursorPos(x, y)
    monitor.write(clipped(text, width))
  end

  local function tabBar(width)
    local names = { "OVERVIEW", "JOB SETUP", "DRONES", "LEDGER" }
    local tabWidth = math.floor(width / #names)
    for i, name in ipairs(names) do
      local tabIndex = i
      local x = (i - 1) * tabWidth + 1
      button(x, 1, tabWidth, name, function() ui.tab = tabIndex end,
        ui.tab == i and colors.blue or colors.gray)
    end
  end

  local function drawOverview(width, height)
    local job = ui.state.job
    line(1, 3, width, "MINE SWARM C2  |  "
      .. (job and ("JOB " .. job.id .. " " .. tostring(job.status)) or "NO ACTIVE JOB"),
      colors.cyan)
    local online, mining = 0, 0
    for _, drone in pairs(ui.state.drones) do
      if drone.online then
        online = online + 1
        if drone.state == "MINING" then mining = mining + 1 end
      end
    end
    line(1, 4, width, string.format("ONLINE %d   MINING %d   WAYPOINTS %d",
      online, mining, #ui.state.waypoints))
    if job then
      local progress = job.progress or 0
      local total = job.total or 1
      local eta = "--"
      if progress > 0 and job.started then
        local elapsed = math.max(1, (os.epoch("utc") - job.started) / 1000)
        local secondsLeft = math.max(0, math.floor(elapsed * (total - progress) / progress))
        eta = string.format("%dm%02ds", math.floor(secondsLeft / 60), secondsLeft % 60)
      end
      line(1, 5, width, string.format("AREA %dx%d  Y %d..%d  COLUMNS %d/%d %.1f%% ETA %s",
        job.bounds.x2 - job.bounds.x1 + 1, job.bounds.z2 - job.bounds.z1 + 1,
        job.bounds.y1, job.bounds.y2, progress, total, 100 * progress / total, eta))
      local mapTop = 7
      local mapHeight = math.max(1, math.min(height - 13, 14))
      local mapWidth = math.max(1, width - 4)
      for row = 0, mapHeight - 1 do
        line(2, mapTop + row, mapWidth, string.rep(".", mapWidth), colors.gray)
      end
      if job.bounds then
        local function mapX(worldX)
          return math.floor((worldX - job.bounds.x1)
            / math.max(1, job.bounds.x2 - job.bounds.x1) * (mapWidth - 1)) + 2
        end
        local function mapZ(worldZ)
          return math.floor((worldZ - job.bounds.z1)
            / math.max(1, job.bounds.z2 - job.bounds.z1) * (mapHeight - 1)) + mapTop
        end
        local function plot(x, y, glyph, color)
          x, y = util.clamp(x, 2, mapWidth + 1), util.clamp(y, mapTop, mapTop + mapHeight - 1)
          monitor.setCursorPos(x, y)
          monitor.setTextColor(color)
          monitor.write(glyph)
        end
        for _, assignment in pairs(job.assignments or {}) do
          local sector = assignment.sector
          if sector then
            local x1, x2 = mapX(sector.x1), mapX(sector.x2)
            local z1, z2 = mapZ(sector.z1), mapZ(sector.z2)
            for x = x1, x2 do plot(x, z1, "-", colors.gray); plot(x, z2, "-", colors.gray) end
            for z = z1, z2 do plot(x1, z, "|", colors.gray); plot(x2, z, "|", colors.gray) end
          end
        end
        for _, drone in pairs(ui.state.drones) do
          if drone.online and drone.pos then
            local x, y = mapX(drone.pos.x), mapZ(drone.pos.z)
            local color = drone.state == "MINING" and colors.lime
              or (drone.state == "RETURNING" and colors.yellow or colors.red)
            plot(x, y, "*", color)
          end
        end
        for _, point in ipairs(ui.state.waypoints) do
          if point.pos and point.pos.x >= job.bounds.x1 and point.pos.x <= job.bounds.x2
            and point.pos.z >= job.bounds.z1 and point.pos.z <= job.bounds.z2 then
            plot(mapX(point.pos.x), mapZ(point.pos.z), "!", colors.magenta)
          end
        end
      end
    else
      line(2, 7, width - 2, "Configure an ore range or layer and launch a job.")
    end
    local y = height - 4
    button(1, y, math.floor(width / 4), "PAUSE ALL", function() actions.command("ALL", "PAUSE") end, colors.orange)
    button(math.floor(width / 4) + 1, y, math.floor(width / 4), "RESUME ALL", function() actions.command("ALL", "RESUME") end, colors.green)
    button(math.floor(width / 2) + 1, y, math.floor(width / 4), "RECALL ALL", function() actions.command("ALL", "RECALL") end, colors.red)
    button(math.floor(3 * width / 4) + 1, y, width - math.floor(3 * width / 4), "DEPLOY +1", actions.deploy, colors.blue)
    line(1, height, width, ui.message, colors.yellow)
  end

  local function drawSetup(width, height)
    line(2, 3, width - 2, "JOB CONFIGURATION", colors.cyan)
    button(2, 5, 16, ui.mode == "ore" and "MODE: ORE" or "MODE: LAYER",
      function() ui.mode = ui.mode == "ore" and "layer" or "ore"; ui.scroll = 0 end, colors.blue)
    local names = ui.mode == "ore" and ui.oreNames or ui.layerNames
    local selected = ui.selectedPreset
    local found = false
    for _, name in ipairs(names) do if name == selected then found = true end end
    if not found then selected = names[1]; ui.selectedPreset = selected end
    button(20, 5, math.max(12, width - 21), "<  " .. selected .. "  >",
      function()
        local index = 1
        for i, name in ipairs(names) do if name == ui.selectedPreset then index = i end end
        ui.selectedPreset = names[index % #names + 1]
      end, colors.gray)
    local origin = ui.settings.origin or ui.settings.home
    local originText = "not configured"
    if type(origin) == "table" and origin.x ~= nil and origin.z ~= nil then
      originText = tostring(origin.x) .. ", " .. tostring(origin.z)
    end
    line(2, 7, width - 4, "X/Z origin: " .. originText .. "  (set in master_config)")
    line(2, 8, width - 4, "Automatic ore depth: sweet-range inclusive; layers use selected depth.")
    button(2, 10, 10, "-16 WIDTH", function() ui.width = math.max(1, ui.width - 16) end)
    button(13, 10, 10, "+16 WIDTH", function() ui.width = ui.width + 16 end)
    button(24, 10, 10, "+64 WIDTH", function() ui.width = ui.width + 64 end)
    button(35, 10, 10, "+100 WIDTH", function() ui.width = ui.width + 100 end)
    line(47, 10, width - 48, "WIDTH: " .. ui.width)
    button(2, 12, 10, "-16 LENGTH", function() ui.length = math.max(1, ui.length - 16) end)
    button(13, 12, 10, "+16 LENGTH", function() ui.length = ui.length + 16 end)
    button(24, 12, 10, "+64 LENGTH", function() ui.length = ui.length + 64 end)
    button(35, 12, 10, "+100 LENGTH", function() ui.length = ui.length + 100 end)
    line(47, 12, width - 48, "LENGTH: " .. ui.length)
    button(2, 14, 10, "-1 DEPTH", function() ui.depth = math.max(1, ui.depth - 1) end)
    button(13, 14, 10, "+1 DEPTH", function() ui.depth = ui.depth + 1 end)
    line(26, 14, 18, "DEPTH: " .. ui.depth)
    local y1, y2 = oreDb.jobY(ui.mode, selected, ui.depth)
    line(47, 14, width - 48, y1 and ("Y: " .. y1 .. ".." .. y2) or tostring(y2))
    button(2, math.max(17, height - 4), width - 3, "LAUNCH SWARM JOB",
      function() actions.launch(ui.mode, ui.selectedPreset, ui.width, ui.length, ui.depth) end, colors.green)
    line(2, height, width - 2, ui.message, colors.yellow)
  end

  local function drawDrones(width, height)
    line(2, 3, width - 2, "REGISTERED DRONES", colors.cyan)
    local labels = util.sortedKeys(ui.state.drones)
    local listWidth = math.max(14, math.floor(width * 0.35))
    for i, label in ipairs(labels) do
      local row = i + 4
      if row >= height - 3 then break end
      local droneLabel = label
      local drone = ui.state.drones[label]
      button(2, row, listWidth, (drone.online and "+" or "-") .. " " .. label,
        function() ui.selectedDrone = droneLabel end, ui.selectedDrone == label and colors.blue or colors.gray)
    end
    local label = ui.selectedDrone
    local drone = label and ui.state.drones[label]
    if drone then
      local x = listWidth + 4
      line(x, 5, width - x, "LABEL: " .. label, colors.white)
      line(x, 6, width - x, string.format("GPS: %s, %s, %s",
        drone.pos and drone.pos.x or "?", drone.pos and drone.pos.y or "?",
        drone.pos and drone.pos.z or "?"))
      local directions = { "NORTH", "EAST", "SOUTH", "WEST" }
      line(x, 7, width - x, "FACING: " .. tostring(directions[(drone.dir or -1) + 1] or "?"))
      line(x, 8, width - x, "STATE: " .. tostring(drone.state))
      line(x, 9, width - x, "FUEL: " .. tostring(drone.fuel) .. "/100000")
      line(x, 10, width - x, "SECTOR: " .. tostring(drone.task or "none"))
      line(x, 11, width - x, "INVENTORY: " .. tostring(drone.inventory or "?") .. "/16")
      if drone.error then line(x, 12, width - x, "ERROR: " .. drone.error, colors.red) end
      button(x, 13, 10, "PAUSE", function() actions.command(label, "PAUSE") end, colors.orange)
      button(x + 11, 13, 10, "RESUME", function() actions.command(label, "RESUME") end, colors.green)
      button(x, 15, 15, "RETURN & UNLOAD", function() actions.command(label, "RECALL") end, colors.yellow)
      button(x + 16, 15, 10, "REBOOT", function() actions.command(label, "REBOOT") end, colors.red)
    else
      line(listWidth + 4, 5, width - listWidth - 4, "Select a turtle to inspect.")
    end
    line(1, height, width, ui.message, colors.yellow)
  end

  local function drawLedger(width, height)
    line(2, 3, width - 2, "ORE LEDGER / UNBREAKABLE WAYPOINTS", colors.cyan)
    local split = math.floor(width / 2)
    line(2, 5, split - 3, "WAYPOINTS", colors.magenta)
    line(split + 1, 5, width - split - 1, "SWARM YIELD", colors.lime)
    for i, point in ipairs(ui.state.waypoints) do
      local row = i + 6
      if row >= height - 2 then break end
      local waypointIndex = i
      line(2, row, split - 4, string.format("%s @ %d,%d,%d",
        point.block, point.pos.x, point.pos.y, point.pos.z))
      button(split - 2, row, 8, "CLEAR", function() actions.clearWaypoint(waypointIndex) end, colors.red)
    end
    local row = 6
    for _, name in ipairs(util.sortedKeys(ui.state.yield)) do
      if row >= height - 2 then break end
      line(split + 1, row, width - split - 2,
        util.itemLabel(name) .. ": " .. tostring(ui.state.yield[name]))
      row = row + 1
    end
    line(1, height, width, ui.message, colors.yellow)
  end

  function ui.draw()
    local width, height = size()
    ui.buttons = {}
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    tabBar(width)
    if ui.tab == 1 then drawOverview(width, height)
    elseif ui.tab == 2 then drawSetup(width, height)
    elseif ui.tab == 3 then drawDrones(width, height)
    else drawLedger(width, height) end
  end

  function ui.touch(x, y)
    for _, area in ipairs(ui.buttons) do
      if x >= area.x1 and x <= area.x2 and y >= area.y1 and y <= area.y2 then
        area.callback()
        return true
      end
    end
    return false
  end

  function ui.setMessage(message)
    ui.message = tostring(message)
  end

  return ui
end

return M
