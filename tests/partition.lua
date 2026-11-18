local partition = dofile("master/partition.lua")
local oreDb = dofile("master/ore_db.lua")

local function checkArea(width, length, count)
  local bounds = { x1 = -31, x2 = -31 + width - 1, y1 = -21, y2 = -1, z1 = 47, z2 = 47 + length - 1 }
  local sectors, reason = partition.divide(bounds, count)
  assert(sectors, reason)
  assert(#sectors == count)

  local occupied, total = {}, 0
  for _, sector in ipairs(sectors) do
    for x = sector.x1, sector.x2 do
      for z = sector.z1, sector.z2 do
        local key = x .. ":" .. z
        assert(not occupied[key], "overlapping sector at " .. key)
        occupied[key] = true
        total = total + 1
      end
    end
    assert(sector.y1 == bounds.y1 and sector.y2 == bounds.y2)
  end
  assert(total == width * length, "sectors do not cover the whole area")
end

checkArea(100, 100, 4)
checkArea(101, 73, 7)
checkArea(5, 9, 5)

local osmiumMin, osmiumMax = oreDb.jobY("ore", "Osmium")
assert(osmiumMin == -21 and osmiumMax == -1)
local allthemodium, reason = oreDb.jobY("ore", "Allthemodium")
assert(allthemodium == nil and reason:find("log%-only"))
local layerMin, layerMax = oreDb.jobY("layer", "Stone", 50)
assert(layerMin == 198 and layerMax == 247)

local sectors = assert(partition.divide(
  { x1 = 0, x2 = 99, y1 = -21, y2 = -1, z1 = 0, z2 = 99 }, 4))
for _, sector in ipairs(sectors) do
  assert(sector.x2 - sector.x1 + 1 == 50)
  assert(sector.z2 - sector.z1 + 1 == 50)
end
local none = partition.divide(
  { x1 = 0, x2 = 1, y1 = 0, y2 = 1, z1 = 0, z2 = 1 }, 5)
assert(none == nil, "partition must reject more turtles than X/Z cells")

print("MineSwarm partition and ore-range tests passed")
