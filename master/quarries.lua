local M = {}

function M.active(quarry)
  return quarry.status ~= "COMPLETE"
    and quarry.status ~= "ERROR"
    and quarry.status ~= "INCOMPLETE"
end

function M.intersects(first, second)
  return first.x1 <= second.x2 and first.x2 >= second.x1
    and first.y1 <= second.y2 and first.y2 >= second.y1
    and first.z1 <= second.z2 and first.z2 >= second.z1
end

function M.fromHome(home, width, length, y1, y2)
  local directions = {
    [0] = { x = 0, z = -1 },
    [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = 1 },
    [3] = { x = -1, z = 0 },
  }
  if type(home) ~= "table" or type(home.x) ~= "number" or type(home.y) ~= "number"
    or type(home.z) ~= "number" or type(home.dir) ~= "number"
    or home.x % 1 ~= 0 or home.y % 1 ~= 0 or home.z % 1 ~= 0
    or home.dir % 1 ~= 0 or not directions[home.dir] then
    return nil, "Drone has no valid saved GPS home and facing"
  end
  local direction = directions[home.dir]
  local x1, z1 = home.x + direction.x, home.z + direction.z
  return {
    x1 = x1, x2 = x1 + width - 1,
    y1 = y1, y2 = y2,
    z1 = z1, z2 = z1 + length - 1,
  }
end

function M.findOverlap(bounds, state)
  for _, quarry in pairs(state.quarries or {}) do
    if M.active(quarry) and M.intersects(bounds, quarry.bounds) then
      return quarry.id
    end
  end
  local job = state.job
  if job and M.active(job) and M.intersects(bounds, job.bounds) then
    return job.id
  end
  return nil
end

return M
