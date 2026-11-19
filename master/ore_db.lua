local M = {}

M.ores = {
  Coal = { minY = 146, maxY = 166, fullMinY = 65, fullMaxY = 247 },
  Iron = { minY = 146, maxY = 166, fullMinY = 65, fullMaxY = 247 },
  Copper = { minY = 146, maxY = 166, fullMinY = 65, fullMaxY = 247 },
  Emerald = { minY = 146, maxY = 166, fullMinY = 65, fullMaxY = 247 },
  Redstone = { minY = 128, maxY = 148, fullMinY = 71, fullMaxY = 205 },
  Diamond = { minY = 125, maxY = 145, fullMinY = 97, fullMaxY = 173 },
  Aluminum = { minY = 117, maxY = 137, fullMinY = 6, fullMaxY = 247 },
  ["Lapis Lazuli"] = { minY = 99, maxY = 119, fullMinY = 72, fullMaxY = 146 },
  Allthemodium = {
    minY = 86, maxY = 96, fullMinY = 70, fullMaxY = 114, logOnly = true,
  },
  Tin = { minY = 70, maxY = 90, fullMinY = -25, fullMaxY = 185 },
  Gold = { minY = 59, maxY = 79, fullMinY = 4, fullMaxY = 134 },
  Quartz = { minY = 61, maxY = 64, fullMinY = 61, fullMaxY = 64 },
  Uranium = { minY = 40, maxY = 80, fullMinY = 29, fullMaxY = 92 },
  ["Ancient Debris"] = { minY = 30, maxY = 50, fullMinY = 16, fullMaxY = 65 },
  Zinc = { minY = 17, maxY = 47, fullMinY = -53, fullMaxY = 118 },
  ["Crimson Iron"] = { minY = 17, maxY = 47, fullMinY = 1, fullMaxY = 64 },
  Platinum = { minY = 3, maxY = 19, fullMinY = -58, fullMaxY = 25 },
  Silver = { minY = -15, maxY = 20, fullMinY = -63, fullMaxY = 54 },
  Nickel = { minY = -17, maxY = 3, fullMinY = -61, fullMaxY = 46 },
  Osmium = { minY = -21, maxY = -1, fullMinY = -56, fullMaxY = 21 },
  Lead = { minY = -56, maxY = -26, fullMinY = -63, fullMaxY = -19 },
}

function M.jobY(preset)
  local range = M.ores[preset]
  if not range then return nil, "Unknown ore: " .. tostring(preset) end
  if range.logOnly then return nil, preset .. " is log-only and cannot be a mining target" end
  return range.minY, range.maxY
end

return M
