local config = require("shared.config")
local util = require("shared.util")

local M = {}
local modem
local modemName

function M.open()
  if modem then return modem end
  modem, modemName = util.findModem(config)
  if not modem.isOpen(config.channel) then modem.open(config.channel) end
  return modem
end

function M.side()
  M.open()
  return modemName
end

function M.send(packet)
  M.open()
  packet.protocol = config.protocol
  modem.transmit(config.channel, config.channel, packet)
end

function M.receive()
  M.open()
  while true do
    local event = { os.pullEvent("modem_message") }
    local channel, packet = event[3], event[5]
    if channel == config.channel and type(packet) == "table"
      and packet.protocol == config.protocol then
      return packet
    end
  end
end

function M.isModemMessage(event)
  return event[1] == "modem_message"
    and event[3] == config.channel
    and type(event[5]) == "table"
    and event[5].protocol == config.protocol
end

return M
