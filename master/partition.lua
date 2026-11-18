local M = {}

local function splitSpan(first, count, pieces)
  local spans, cursor = {}, first
  local base, remainder = math.floor(count / pieces), count % pieces
  for index = 1, pieces do
    local size = base + (index <= remainder and 1 or 0)
    spans[index] = { first = cursor, last = cursor + size - 1 }
    cursor = cursor + size
  end
  return spans
end

function M.divide(bounds, requested)
  if type(bounds) ~= "table" then return nil, "Bounds must be a table" end
  for _, key in ipairs({ "x1", "x2", "y1", "y2", "z1", "z2" }) do
    if type(bounds[key]) ~= "number" or bounds[key] % 1 ~= 0 then
      return nil, "Bounds must contain whole-number " .. key
    end
  end
  if bounds.y1 > bounds.y2 then return nil, "Y bounds must be ordered from low to high" end
  local width = bounds.x2 - bounds.x1 + 1
  local length = bounds.z2 - bounds.z1 + 1
  if width < 1 or length < 1 then return nil, "Area dimensions must be positive" end
  if type(requested) ~= "number" or requested < 1 or requested % 1 ~= 0 then
    return nil, "Turtle count must be a positive whole number"
  end
  if requested > width * length then
    return nil, "There are more turtles than X/Z blocks in the area"
  end

  local columns = 1
  local bestCost = math.huge
  for candidate = 1, requested do
    local rows = math.ceil(requested / candidate)
    if candidate <= width and rows <= length then
      local aspect = (width / candidate) / (length / rows)
      local cost = math.abs(math.log(aspect))
      if cost < bestCost then
        columns, bestCost = candidate, cost
      end
    end
  end

  local rows = math.ceil(requested / columns)
  local rowSpans = splitSpan(bounds.z1, length, rows)
  local sectors, assigned = {}, 0
  local rowBase, rowRemainder = math.floor(requested / rows), requested % rows
  for row = 1, rows do
    local rowCount = rowBase + (row <= rowRemainder and 1 or 0)
    local xSpans = splitSpan(bounds.x1, width, rowCount)
    for column = 1, rowCount do
      assigned = assigned + 1
      sectors[assigned] = {
        id = string.format("S%02d", assigned),
        x1 = xSpans[column].first,
        x2 = xSpans[column].last,
        y1 = bounds.y1,
        y2 = bounds.y2,
        z1 = rowSpans[row].first,
        z2 = rowSpans[row].last,
      }
    end
  end
  return sectors
end

return M
