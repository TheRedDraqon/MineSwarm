local configPath = "/mineswarm/gps_config"
if not fs.exists(configPath) then error("Missing /mineswarm/gps_config") end
local file = fs.open(configPath, "r")
if not file then error("Cannot read " .. configPath) end
local settings = textutils.unserialize(file.readAll())
file.close()
if type(settings) ~= "table" then error("Invalid GPS host configuration") end
for _, axis in ipairs({ "x", "y", "z" }) do
  if type(settings[axis]) ~= "number" or settings[axis] % 1 ~= 0 then
    error("GPS host coordinate " .. axis .. " must be an integer")
  end
end
if not peripheral.find("modem") then error("GPS host requires a wireless modem") end
print(string.format("Hosting GPS at %d, %d, %d", settings.x, settings.y, settings.z))
local ok = shell.run("gps", "host", tostring(settings.x), tostring(settings.y), tostring(settings.z))
if not ok then error("The built-in gps host program failed") end
