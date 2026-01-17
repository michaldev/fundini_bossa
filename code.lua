function run(ctx)
  ctx.log("Bossa CSV importer start")

  local csv = ctx.file and ctx.file.content or ""
  if csv:gsub("%s+", "") == "" then
    return { transactions = {} }
  end

  local function parse_number(v)
    if v == nil then return nil end
    local s = tostring(v):gsub("%s+", ""):gsub(",", ".")
    return tonumber(s)
  end

  local function parse_datetime(str)
    local s = (str or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end

    local date_part, time_part = s:match("([^%s]+)%s*(.*)")
    time_part = time_part ~= "" and time_part or "00:00:00"

    local d, m, y = date_part:match("(%d+)%.(%d+)%.(%d+)")
    if not d or not m or not y then return nil end

    if #d == 1 then d = "0" .. d end
    if #m == 1 then m = "0" .. m end

    return y .. "-" .. m .. "-" .. d .. "T" .. time_part .. "Z"
  end

  local function parse_csv(text)
    local rows = {}
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    local header = true
    for line in text:gmatch("[^\n]+") do
      line = line:gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" then
        if header then
          header = false
        else
          local cols = {}
          for v in line:gmatch("([^;]+)") do
            table.insert(cols, v)
          end
          if #cols >= 10 then
            table.insert(rows, cols)
          end
        end
      end
    end

    return rows
  end

  local rows = parse_csv(csv)

  local transactions = {}

  for _, r in ipairs(rows) do
    local trade_datetime = parse_datetime(r[1])
    local instrument_name = (r[2] or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local isin = (r[3] or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local raw_units = parse_number(r[4])
    local side_raw = (r[5] or ""):gsub("%s+", "")
    local price_portfolio = parse_number(r[6])
    local total_portfolio = parse_number(r[7])
    local fee_portfolio = parse_number(r[8]) or 0

    local side = nil
    if side_raw == "S" then
      side = "sell"
    elseif side_raw == "K" or side_raw == "B" then
      side = "buy"
    end

    if not trade_datetime or instrument_name == "" or not raw_units or raw_units == 0 then
      goto continue
    end

    if side ~= "buy" and side ~= "sell" then
      goto continue
    end

    if not price_portfolio or price_portfolio <= 0 then
      goto continue
    end

    local units = math.abs(raw_units)
    if units <= 0 then
      goto continue
    end

    if not total_portfolio or total_portfolio <= 0 then
      total_portfolio = units * price_portfolio
    end

    table.insert(transactions, {
      ticker = "",
      trade_datetime = trade_datetime,
      side = side,
      units = units,

      instrument_currency = nil,
      price_instrument = nil,
      fx_rate = nil,

      price_portfolio = price_portfolio,
      total_portfolio = total_portfolio,
      fee_portfolio = fee_portfolio,
      tax_portfolio = 0,

      note = isin ~= "" and isin or nil,

      import_name = instrument_name
    })

    ::continue::
  end

  ctx.log("Parsed trades: " .. tostring(#transactions))

  return {
    transactions = transactions
  }
end
