local util = require("shared.util")
local oreDb = require("master.ore_db")
local quarries = require("master.quarries")

local M = {}

local function clipped(text, width)
  text = tostring(text or "")
  if #text > width then return text:sub(1, math.max(0, width - 3)) .. "..." end
  return text .. string.rep(" ", math.max(0, width - #text))
end

function M.new(monitor, state, actions)
  local ui = {
    tab = 1, buttons = {}, selectedDrone = nil, preset = "Osmium",
    xInput = "~10", zInput = "~10", minY = "-21", maxY = "-1",
    inputField = nil, inputBuffer = "", message = "Select a drone",
    dronePage = 0, waypointPage = 0,
  }
  local presets = { "Custom" }
  for _, name in ipairs(util.sortedKeys(oreDb.ores)) do
    if not oreDb.ores[name].logOnly then presets[#presets + 1] = name end
  end
  monitor.setTextScale(0.5)
  local width, height = monitor.getSize()
  if width < 48 or height < 19 then
    error("Monitor too small: MineSwarm requires at least 48x19 characters at text scale 0.5")
  end

  local function line(x, y, w, text, color)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(color or colors.white)
    monitor.setCursorPos(x, y)
    monitor.write(clipped(text, w))
  end

  local function button(x, y, w, text, callback, color, field)
    monitor.setBackgroundColor(color or colors.gray)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(x, y)
    monitor.write(clipped(text, w))
    ui.buttons[#ui.buttons + 1] = { x1 = x, x2 = x + w - 1, y = y, callback = callback, field = field }
  end

  local function input(x, y, w, label, field)
    local value = ui.inputField == field and ui.inputBuffer or ui[field]
    button(x, y, w, label .. ": " .. value, function()
      ui.inputField, ui.inputBuffer = field, ""
    end, ui.inputField == field and colors.orange or colors.gray, field)
  end

  local function droneJob(label)
    for _, job in pairs(state.jobs) do
      if job.label == label and quarries.active(job) then return job end
    end
  end

  local function drawDrones()
    line(2, 3, width - 3, "DRONES: select one to control or assign", colors.cyan)
    local labels = util.sortedKeys(state.drones)
    local listWidth = math.floor(width * 0.36)
    local pageSize = height - 8
    local maxPage = math.max(0, math.ceil(#labels / pageSize) - 1)
    ui.dronePage = math.min(ui.dronePage, maxPage)
    for row = 1, pageSize do
      local label = labels[ui.dronePage * pageSize + row]
      if not label then break end
      local drone = state.drones[label]
      button(2, row + 4, listWidth, (drone.online and "+ " or "- ") .. label,
        function() ui.selectedDrone = label end, ui.selectedDrone == label and colors.blue or colors.gray)
    end
    local x = listWidth + 4
    local drone = ui.selectedDrone and state.drones[ui.selectedDrone]
    if drone then
      local job = droneJob(ui.selectedDrone)
      line(x, 5, width - x + 1, "NAME: " .. ui.selectedDrone)
      line(x, 6, width - x + 1, "STATE: " .. (drone.online and tostring(drone.state) or "OFFLINE"))
      local pos = drone.pos
      line(x, 7, width - x + 1, pos and ("GPS: " .. pos.x .. "," .. pos.y .. "," .. pos.z) or "GPS: unavailable")
      line(x, 8, width - x + 1, "FUEL: " .. tostring(drone.fuel or "?"))
      line(x, 9, width - x + 1, "SLOTS: " .. tostring(drone.inventory or "?") .. "/16")
      line(x, 10, width - x + 1, job and ("COLUMNS: " .. job.progress .. "/" .. job.total) or "No active job")
      if drone.error then line(x, 11, width - x + 1, tostring(drone.error), colors.yellow) end
      local half = math.floor((width - x) / 2)
      button(x, 13, half, "PAUSE", function() actions.command(ui.selectedDrone, "PAUSE") end, colors.orange)
      button(x + half + 1, 13, width - x - half, "RESUME",
        function() actions.command(ui.selectedDrone, "RESUME") end, colors.green)
      button(x, 15, width - x + 1, "SET UP JOB", function() ui.tab = 2 end, colors.blue)
    else
      line(x, 5, width - x + 1, "Select a drone")
    end
    button(2, height - 2, 10, "< PREV", function() ui.dronePage = math.max(0, ui.dronePage - 1) end)
    button(13, height - 2, 10, "NEXT >", function() ui.dronePage = math.min(maxPage, ui.dronePage + 1) end)
  end

  local function drawSetup()
    line(2, 3, width - 3, "JOB SETUP - one drone per quarry", colors.cyan)
    local drone = ui.selectedDrone and state.drones[ui.selectedDrone]
    line(2, 4, width - 3, "DRONE: " .. tostring(ui.selectedDrone or "select on DRONES tab"))
    local pos = drone and drone.pos
    line(2, 5, width - 3, pos and ("START GPS: " .. pos.x .. "," .. pos.y .. "," .. pos.z) or "GPS unavailable")
    local fieldWidth = math.floor((width - 5) / 2)
    input(2, 7, fieldWidth, "END X", "xInput")
    input(fieldWidth + 3, 7, width - fieldWidth - 4, "END Z", "zInput")
    line(2, 8, width - 3, "Tap a field; type absolute or ~relative on computer.")
    local presetIndex = 1
    for i, name in ipairs(presets) do if name == ui.preset then presetIndex = i end end
    button(2, 10, 8, "< ORE", function()
      ui.preset = presets[(presetIndex - 2) % #presets + 1]
    end, colors.blue)
    button(11, 10, width - 21, "Y: " .. ui.preset, function()
      ui.preset = presets[presetIndex % #presets + 1]
    end, colors.gray)
    button(width - 9, 10, 8, "ORE >", function()
      ui.preset = presets[presetIndex % #presets + 1]
    end, colors.blue)
    local y1, y2
    if ui.preset == "Custom" then
      input(2, 12, fieldWidth, "MIN Y", "minY")
      input(fieldWidth + 3, 12, width - fieldWidth - 4, "MAX Y", "maxY")
      y1, y2 = tonumber(ui.minY), tonumber(ui.maxY)
    else
      y1, y2 = oreDb.jobY(ui.preset)
      line(2, 12, width - 3, "Y range: " .. y1 .. " .. " .. y2 .. " inclusive")
    end
    local bounds, reason = quarries.bounds(pos, ui.xInput, ui.zInput, y1, y2)
    if bounds then
      line(2, 14, width - 3, string.format("X %d..%d  Y %d..%d  Z %d..%d",
        bounds.x1, bounds.x2, bounds.y1, bounds.y2, bounds.z1, bounds.z2))
    else
      line(2, 14, width - 3, reason, colors.yellow)
    end
    if ui.inputField then
      line(2, 15, width - 3, "Enter to apply; Esc to cancel", colors.yellow)
    end
    button(2, height - 3, width - 3, "ASSIGN JOB", function()
      actions.launch(ui.selectedDrone, ui.xInput, ui.zInput, ui.preset, ui.minY, ui.maxY)
    end, colors.green)
  end

  local function drawWaypoints()
    line(2, 3, width - 3, "PROTECTED / UNDIGGABLE BLOCKS", colors.cyan)
    local pageSize = height - 8
    local maxPage = math.max(0, math.ceil(#state.waypoints / pageSize) - 1)
    ui.waypointPage = math.min(ui.waypointPage, maxPage)
    for row = 1, pageSize do
      local index = ui.waypointPage * pageSize + row
      local point = state.waypoints[index]
      if not point then break end
      line(2, row + 4, width - 12, string.format("%s @ %d,%d,%d (%s)",
        point.block, point.pos.x, point.pos.y, point.pos.z, point.label))
      button(width - 8, row + 4, 8, "CLEAR", function() actions.clearWaypoint(index) end, colors.red)
    end
    button(2, height - 2, 10, "< PREV", function() ui.waypointPage = math.max(0, ui.waypointPage - 1) end)
    button(13, height - 2, 10, "NEXT >", function() ui.waypointPage = math.min(maxPage, ui.waypointPage + 1) end)
  end

  function ui.draw()
    ui.buttons = {}
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    local names = { "DRONES", "JOB SETUP", "WAYPOINTS" }
    local tabWidth = math.floor(width / #names)
    for index, name in ipairs(names) do
      button((index - 1) * tabWidth + 1, 1, tabWidth, name,
        function() ui.tab = index end, ui.tab == index and colors.blue or colors.gray)
    end
    line(1, 2, width, "Q: quit master (does not stop drones)", colors.gray)
    if ui.tab == 1 then drawDrones()
    elseif ui.tab == 2 then drawSetup()
    else drawWaypoints() end
    line(1, height, width, ui.message, colors.yellow)
  end

  function ui.touch(x, y)
    for _, area in ipairs(ui.buttons) do
      if y == area.y and x >= area.x1 and x <= area.x2 then
        if ui.inputField and area.field ~= ui.inputField then
          ui.inputField, ui.inputBuffer = nil, ""
        end
        area.callback()
        return true
      end
    end
    return false
  end

  function ui.handleInput(event, value)
    if not ui.inputField then return false end
    if event == "char" then
      if type(value) == "string" and value:match("^[%d~+%-]$") and #ui.inputBuffer < 16 then
        ui.inputBuffer = ui.inputBuffer .. value
      end
    elseif event == "key" then
      if value == keys.backspace then ui.inputBuffer = ui.inputBuffer:sub(1, -2)
      elseif value == keys.escape then ui.inputField, ui.inputBuffer = nil, ""
      elseif value == keys.enter or value == keys.numPadEnter then
        local origin = ui.inputField == "xInput" or ui.inputField == "zInput"
        local valid = origin and quarries.coordinate(ui.inputBuffer, 0)
          or (not origin and ui.inputBuffer:match("^[+-]?%d+$") and tonumber(ui.inputBuffer))
        if valid then
          ui[ui.inputField] = ui.inputBuffer
          ui.inputField, ui.inputBuffer = nil, ""
          ui.message = "Value applied"
        else
          ui.message = "Enter a whole number or ~offset"
        end
      end
    end
    return true
  end

  function ui.setMessage(message) ui.message = tostring(message) end
  return ui
end

return M
