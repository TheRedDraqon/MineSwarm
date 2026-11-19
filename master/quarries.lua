local M = {}

local function integer(value)
  return type(value) == "number" and value % 1 == 0 and math.abs(value) < 30000000
end

function M.coordinate(input, origin)
  if type(input) ~= "string" or not integer(origin) then
    return nil, "Invalid coordinate or drone position"
  end
  local relative = input:sub(1, 1) == "~"
  local number = relative and input:sub(2) or input
  if relative and number == "" then number = "0" end
  if not number:match("^[+-]?%d+$") then
    return nil, "Use a whole coordinate, ~, or a signed ~offset"
  end
  local result = tonumber(number)
  if relative then result = origin + result end
  if not integer(result) then return nil, "Coordinate is outside the supported range" end
  return result
end

function M.bounds(position, xInput, zInput, y1, y2)
  if type(position) ~= "table" or not integer(position.x) or not integer(position.z) then
    return nil, "Drone has no valid GPS position"
  end
  if not integer(y1) or not integer(y2) or y1 > y2 then
    return nil, "Enter a valid minimum and maximum Y"
  end
  local x, reason = M.coordinate(xInput, position.x)
  if not x then return nil, "X: " .. reason end
  local z
  z, reason = M.coordinate(zInput, position.z)
  if not z then return nil, "Z: " .. reason end
  return {
    x1 = math.min(position.x, x), x2 = math.max(position.x, x),
    y1 = y1, y2 = y2,
    z1 = math.min(position.z, z), z2 = math.max(position.z, z),
  }
end

function M.active(job)
  return job.status ~= "COMPLETE" and job.status ~= "ERROR"
    and job.status ~= "CANCELLED"
end

function M.findOverlap(bounds, jobs)
  for _, job in pairs(jobs) do
    local other = job.bounds
    if M.active(job) and bounds.x1 <= other.x2 and bounds.x2 >= other.x1
      and bounds.z1 <= other.z2 and bounds.z2 >= other.z1 then
      return job.id
    end
  end
end

return M
