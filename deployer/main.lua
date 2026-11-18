local config = require("mineswarm.shared.config")
local util = require("mineswarm.shared.util")
local net = require("mineswarm.shared.net")
local stateLib = require("mineswarm.shared.state")

local configPath = "/mineswarm/deployer_config"
local settings = stateLib.load(configPath, {
  supplySide = "front",
  placeDirection = "down",
  labelPrefix = "Miner_",
})
local ownLabel = os.getComputerLabel()
if not ownLabel or ownLabel == "" then
  ownLabel = "Deployer"
  os.setComputerLabel(ownLabel)
end
if not turtle then error("The deployer must be a turtle with a modem and a supply chest") end
if settings.supplySide ~= "front" then
  error("Deployer supply chest must be in front for turtle.suckFromSlot")
end

local function isTurtleItem(name)
  name = tostring(name):lower()
  return name:find("turtle", 1, true) ~= nil
end

local function turtlePeripheralNames()
  local result = {}
  for _, name in ipairs(peripheral.getNames()) do
    local methods = peripheral.getMethods(name)
    local hasTurnOn, hasId = false, false
    for _, method in ipairs(methods or {}) do
      if method == "turnOn" then hasTurnOn = true end
      if method == "getID" then hasId = true end
    end
    if hasTurnOn and hasId then result[name] = true end
  end
  return result
end

local function waitForSpawn(before, timeout)
  local timer = os.startTimer(timeout)
  while true do
    for name in pairs(turtlePeripheralNames()) do
      if not before[name] then return name end
    end
    local event = { os.pullEventRaw() }
    if event[1] == "timer" and event[2] == timer then return nil end
  end
end

local function deployOne()
  local chest = peripheral.wrap(settings.supplySide)
  if not chest or type(chest.list) ~= "function" then
    error("No inventory is connected on the configured supply side")
  end
  local chosen
  for slot, item in pairs(chest.list()) do
    if item and isTurtleItem(item.name) then
      chosen = slot
      break
    end
  end
  if not chosen then error("No turtle item found in the supply chest") end

  local before = turtlePeripheralNames()
  turtle.select(1)
  if not turtle.suckFromSlot(chosen, 1) then error("Could not retrieve turtle from supply chest") end
  local placed
  if settings.placeDirection == "up" then placed = turtle.placeUp()
  elseif settings.placeDirection == "down" then placed = turtle.placeDown()
  elseif settings.placeDirection == "front" then placed = turtle.place()
  else error("placeDirection must be front, up, or down") end
  if not placed then error("Turtle placement failed; clear the configured deployment space") end

  local peripheralName = waitForSpawn(before, 10)
  if not peripheralName then
    error("Placed turtle was not exposed as an adjacent peripheral; turn it on manually")
  end
  local ok, reason = pcall(peripheral.call, peripheralName, "turnOn")
  if not ok then error("Could not turn on deployed turtle: " .. tostring(reason)) end
  local idOk, computerId = pcall(peripheral.call, peripheralName, "getID")
  if not idOk or type(computerId) ~= "number" then
    error("Could not identify the placed turtle; it is on but must be labeled manually")
  end
  util.log("Started turtle peripheral", peripheralName)

  local timer = os.startTimer(45)
  while true do
    local event = { os.pullEventRaw() }
    if net.isModemMessage(event) then
      local packet = event[5]
      if packet.type == "HB" and packet.computerId == computerId then
        local assignedLabel = settings.labelPrefix .. tostring(computerId)
        net.send({
          type = "CMD",
          target = computerId,
          action = "SET_LABEL",
          label = assignedLabel,
        })
        net.send({ type = "DEPLOYED", label = assignedLabel, computerId = computerId })
        return assignedLabel
      end
    elseif event[1] == "timer" and event[2] == timer then
      error("Deployed turtle did not send a heartbeat within 45 seconds")
    end
  end
end

net.open()
util.log("Deployer online as", ownLabel)
local timer = os.startTimer(1)
while true do
  local event = { os.pullEventRaw() }
  if net.isModemMessage(event) then
    local packet = event[5]
    if packet.type == "CMD" and packet.action == "DEPLOY"
      and (packet.target == ownLabel or packet.target == "ALL") then
      local ok, result = pcall(deployOne)
      if ok then
        util.log("Deployed", result)
      else
        util.log("Deployment failed:", result)
        net.send({ type = "DEPLOY_ERROR", label = ownLabel, reason = tostring(result) })
      end
      timer = os.startTimer(1)
    end
  elseif event[1] == "timer" and event[2] == timer then
    timer = os.startTimer(1)
  end
end
