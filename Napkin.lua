--[[ The Napkin part's engine: a sum as a person would scribble it, read and answered. No frames here; NapkinUI.lua
     draws the window, and the tests run this file against a stub of the game.

     A value has a kind: plain (a number), money (held in copper) or percent. The kinds decide what an operator does:
       12g 50s × 20 = 250g       money × plain is money; money ÷ money is a plain ratio; money × money is an error
       1000g - 5% = 950g         a ± p% scales a; p% of a and a × p% take the share; a bare p% is a percent
       20% of 1500 = 300         "of" and a lone "x" read as ×
     Numbers take thousands commas, k and m (1.5k, 2m), and g, s, c after them for coins (12g 50s 30c is one amount).
     An item link (|Hitem:…|h[Name]|h, or [Name] typed) is how many the character carries; vendor([Name]) its sell
     price and stack([Name]) its stack size. Words: pi; sqrt, floor, ceil, round, abs, min, max, avg; ans (the nearest
     answer above) and total (the rows above, added); the game's values in Napkin.values (gold, level, xp, ...); and
     the pad's own variables, kept by a row like "rent = 12g 50s".

     Napkin.Tokens(text)            the text as tokens, or an error for a character it can't read
     Napkin.Read(text, env)         value, readAs  or  nil, nil, error   (nil, nil for an empty text)
     Napkin.Format(value, icons)    250g / 12g 50s / 1,250 / 12.5%; icons: the game's coin icons for money
     Napkin.Pad(lines, env)         every row answered in order: { value, text, read, err } a row
     Napkin.Say(text, env)          "12g 50s × 20 = 250g" for chat, or nil, error

     env: { values = name -> function (the game's words; Napkin.values by default), item/vendor/stack = function (link),
            icons = true for coin icons }. The tests give their own, so the engine is checked without the game.

     Errors are short and in words: "250g × 20g?", "unknown word: rnt", "a bracket is open". ]]

local _, FA = ...
local Napkin = {}
FA.Napkin = Napkin

Napkin.MAX_LINES = 60

local function val(kind, v) return { kind = kind, v = v } end
local function fail(msg) error({ napkin = msg }, 0) end

--[[ ---- formatting ---- ]]
local function group(digits)
  local s, n = digits, 1
  while n > 0 do s, n = s:gsub("^(%d+)(%d%d%d)", "%1,%2") end
  return s
end
--[[ A plain number as text: thousands commas, up to `places` decimals (2), trailing zeros trimmed. ]]
local function number(x, places)
  if x ~= x then fail("that isn't a number") end
  if x == math.huge or x == -math.huge then fail("too big") end
  places = places or 2
  local neg = x < 0
  local m = 10 ^ places
  local r = math.floor(math.abs(x) * m + 0.5) / m
  local int = math.floor(r)
  local s = group(string.format("%.0f", int))
  local frac = r - int
  if frac > 0 then
    local f = string.format("%." .. places .. "f", frac):sub(3):gsub("0+$", "")
    if f ~= "" then s = s .. "." .. f end
  end
  return (neg and r ~= 0 and "-" or "") .. s
end
local function money(copper, icons)
  local c = math.floor(math.abs(copper) + 0.5)
  local neg = copper < 0 and c > 0
  local t
  if icons and GetCoinTextureString then t = GetCoinTextureString(c)
  else
    local g, s, cc = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = group(tostring(g)) .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if cc > 0 or #parts == 0 then parts[#parts + 1] = cc .. "c" end
    t = table.concat(parts, " ")
  end
  return (neg and "-" or "") .. t
end
function Napkin.Format(value, icons)
  if value.kind == "money" then return money(value.v, icons)
  elseif value.kind == "percent" then return number(value.v, value.places) .. "%"
  else return number(value.v, value.places) end
end
Napkin.Number = number

--[[ ---- tokens ---- ]]
local UNICODE = { ["\195\151"] = "*", ["\195\183"] = "/", ["\226\136\146"] = "-", ["\207\128"] = "pi" }   -- × ÷ − π
local COIN = { g = 10000, s = 100, c = 1 }

function Napkin.Tokens(text)
  local toks, i, n = {}, 1, #text
  local function push(t, v, u) toks[#toks + 1] = { t = t, v = v, u = u } end
  while i <= n do
    local ch = text:sub(i, i)
    if ch:match("%s") then i = i + 1
    elseif ch == "|" or ch == "[" then
      --[[ an item link as the game writes it, with or without its colour, or a name in brackets typed by hand ]]
      local a, b, link, name = text:find("^|c%x%x%x%x%x%x%x%x(|H[^|]+|h%[([^%]]+)%]|h)|r", i)
      if not a then a, b, link, name = text:find("^(|H[^|]+|h%[([^%]]+)%]|h)", i) end
      if not a then a, b, name = text:find("^%[([^%]]+)%]", i); link = name end
      if not a then fail("can't read '" .. ch .. "'") end
      push("item", link, name)
      i = b + 1
    elseif ch:match("[%d%.]") then
      --[[ digits, a comma before exactly three digits, one decimal point ]]
      local j, s = i, ""
      while j <= n do
        local c = text:sub(j, j)
        if c:match("%d") then s = s .. c; j = j + 1
        elseif c == "." and not s:find(".", 1, true) then s = s .. c; j = j + 1
        elseif c == "," and not s:find(".", 1, true) and text:sub(j + 1, j + 3):match("^%d%d%d$") and not text:sub(j + 4, j + 4):match("%d") then j = j + 1
        else break end
      end
      if s == "." then fail("can't read '.'") end
      local v = tonumber(s) or tonumber(s .. "0")
      local c, after = text:sub(j, j):lower(), text:sub(j + 1, j + 1)
      if (c == "k" or c == "m") and not after:match("[A-Za-z]") then
        v = v * (c == "k" and 1000 or 1000000)
        j = j + 1
        c, after = text:sub(j, j):lower(), text:sub(j + 1, j + 1)
      end
      local unit
      if c == "%" then unit = "%"; j = j + 1
      elseif COIN[c] and not after:match("[A-Za-z]") then unit = c; j = j + 1 end
      push("num", v, unit)
      i = j
    elseif ch:match("[A-Za-z_]") then
      local w = text:match("^[A-Za-z_][A-Za-z0-9_]*", i)
      push("id", w:lower(), w)
      i = i + #w
    elseif ch:match("[%+%-%*/%^%(%),=%%]") then push(ch); i = i + 1
    else
      local three, two = text:sub(i, i + 2), text:sub(i, i + 1)
      local sym = (UNICODE[three] and three) or (UNICODE[two] and two)
      if sym then
        if UNICODE[sym] == "pi" then push("id", "pi", "pi") else push(UNICODE[sym]) end
        i = i + #sym
      else
        local glyph = text:match("^[%z\1-\127\194-\244][\128-\191]*", i) or ch
        fail("can't read '" .. glyph .. "'")
      end
    end
  end
  return toks
end

--[[ ---- arithmetic by kind ---- ]]
local SYM = { ["+"] = "+", ["-"] = "-", ["*"] = "×", ["/"] = "÷", ["^"] = "^" }
local BP = { ["+"] = 10, ["-"] = 10, ["*"] = 20, ["/"] = 20, ["^"] = 30, ["%"] = 40 }

local function cant(op, a, b) fail(Napkin.Format(a) .. " " .. SYM[op] .. " " .. Napkin.Format(b) .. "?") end

local function apply(op, a, b)
  local ak, bk = a.kind, b.kind
  if op == "+" or op == "-" then
    local sign = op == "+" and 1 or -1
    if ak == bk then return val(ak, a.v + sign * b.v) end
    if bk == "percent" then return val(ak, a.v * (1 + sign * b.v / 100)) end
    cant(op, a, b)
  elseif op == "*" then
    if ak == "percent" and bk == "percent" then return val("percent", a.v * b.v / 100) end
    if ak == "percent" then return val(bk, b.v * a.v / 100) end
    if bk == "percent" then return val(ak, a.v * b.v / 100) end
    if ak == "money" and bk == "money" then cant(op, a, b) end
    return val(ak == "money" and "money" or bk, a.v * b.v)
  elseif op == "/" then
    if b.v == 0 then fail("divide by zero") end
    if bk == "percent" then
      if ak == "percent" then return val("plain", a.v / b.v) end
      return val(ak, a.v / (b.v / 100))
    end
    if ak == bk then return val(ak == "percent" and "percent" or "plain", a.v / b.v) end
    if ak == "money" and bk == "plain" then return val("money", a.v / b.v) end
    if ak == "percent" and bk == "plain" then return val("percent", a.v / b.v) end
    cant(op, a, b)
  elseif op == "^" then
    if ak ~= "plain" or bk ~= "plain" then cant(op, a, b) end
    return val("plain", a.v ^ b.v)
  end
end

local function same(name, args)
  local kind = args[1].kind
  for _, a in ipairs(args) do if a.kind ~= kind then fail(name .. " mixes " .. (kind == "money" and "gold and numbers" or "kinds")) end end
  return kind
end
local function plainOnly(name)
  return function(args)
    if #args ~= 1 then fail(name .. " takes one number") end
    if args[1].kind ~= "plain" then fail(name .. "(" .. Napkin.Format(args[1]) .. ")?") end
    return args[1]
  end
end
local FUNCS = {
  sqrt = function(args) local a = plainOnly("sqrt")(args); if a.v < 0 then fail("sqrt of a negative number") end return val("plain", math.sqrt(a.v)) end,
  floor = function(args) if #args ~= 1 then fail("floor takes one number") end return val(args[1].kind, math.floor(args[1].v)) end,
  ceil = function(args) if #args ~= 1 then fail("ceil takes one number") end return val(args[1].kind, math.ceil(args[1].v)) end,
  abs = function(args) if #args ~= 1 then fail("abs takes one number") end return val(args[1].kind, math.abs(args[1].v)) end,
  round = function(args)
    if #args < 1 or #args > 2 then fail("round takes a number, and how many places") end
    local places = args[2] and args[2].v or 0
    if args[2] and (args[2].kind ~= "plain" or places ~= math.floor(places) or places < 0 or places > 10) then fail("round's places must be a small whole number") end
    local m = 10 ^ places
    local r = val(args[1].kind, math.floor(args[1].v * m + 0.5) / m)
    r.places = places   -- shown with the places asked for, not the usual two
    return r
  end,
  min = function(args)
    if #args == 0 then fail("min needs numbers") end
    local kind, best = same("min", args), args[1].v
    for _, a in ipairs(args) do if a.v < best then best = a.v end end
    return val(kind, best)
  end,
  max = function(args)
    if #args == 0 then fail("max needs numbers") end
    local kind, best = same("max", args), args[1].v
    for _, a in ipairs(args) do if a.v > best then best = a.v end end
    return val(kind, best)
  end,
  avg = function(args)
    if #args == 0 then fail("avg needs numbers") end
    local kind, sum = same("avg", args), 0
    for _, a in ipairs(args) do sum = sum + a.v end
    return val(kind, sum / #args)
  end,
}
local ITEM_FUNCS = { vendor = true, stack = true }
local CONST = { pi = math.pi }
local KEYWORDS = { ans = true, total = true, of = true, x = true }
Napkin.FUNCS, Napkin.CONST, Napkin.KEYWORDS = FUNCS, CONST, KEYWORDS

--[[ Whether a word is free for a variable's name, or why not. ]]
function Napkin.NameTaken(name, env)
  local w = name:lower()
  if FUNCS[w] or ITEM_FUNCS[w] or CONST[w] or (KEYWORDS[w] and w ~= "x") then return name .. " is taken" end   -- x can be a variable; till it is, it multiplies
  local values = env and env.values or Napkin.values
  if values and values[w] then return name .. " is the game's word" end
  return nil
end

--[[ ---- the parser: Pratt, reading and answering as it goes, with the "read as" text beside the value ---- ]]
local function parse(toks, env)
  local p = 1
  local function peek() return toks[p] end
  local function take() p = p + 1; return toks[p - 1] end
  local function tokText(t) if t.t == "id" then return t.u elseif t.t == "num" then return number(t.v) elseif t.t == "item" then return "[" .. t.u .. "]" else return t.t end end
  local expr

  local function word(t)
    local name = t.v
    if CONST[name] then return val("plain", CONST[name]), "π" end
    if name == "ans" then local v = env.ans(); return v, Napkin.Format(v) end
    if name == "total" then local v = env.total(); return v, Napkin.Format(v) end
    if env.vars and env.vars[name] then local v = env.vars[name]; return v, Napkin.Format(v) end
    local values = env.values
    if values and values[name] then
      local ok, v = pcall(values[name])
      if not ok or not v then fail(t.u .. ": the game won't say") end
      return v, Napkin.Format(v)
    end
    fail("unknown word: " .. t.u)
  end

  local function call(t)
    local name = t.v
    take()   -- the (
    if ITEM_FUNCS[name] then
      local arg = peek()
      if not arg or arg.t ~= "item" then fail(name .. " needs an item link, like " .. name .. "([Linen Cloth])") end
      take()
      local close = take()
      if not close or close.t ~= ")" then fail("a bracket is open") end
      local f = env[name]
      local ok, v = false, nil
      if f then ok, v = pcall(f, arg.v) end
      if not ok or not v then fail("the game won't say about [" .. arg.u .. "]") end
      return val(name == "vendor" and "money" or "plain", v), name .. "([" .. arg.u .. "])"
    end
    local args, texts = {}, {}
    if peek() and peek().t == ")" then take()
    else
      while true do
        local v, s = expr(0)
        args[#args + 1], texts[#texts + 1] = v, s
        local nxt = take()
        if not nxt then fail("a bracket is open") end
        if nxt.t == ")" then break end
        if nxt.t ~= "," then fail("can't read '" .. tokText(nxt) .. "' in " .. name .. "(...)") end
      end
    end
    return FUNCS[name](args), name .. "(" .. table.concat(texts, ", ") .. ")"
  end

  local function prefix()
    local t = take()
    if not t then fail("the sum ends early") end
    if t.t == "num" then
      if COIN[t.u] then
        local copper, used = 0, {}
        local cur = t
        while cur do
          if used[cur.u] then fail("two " .. cur.u .. "s in one amount") end
          used[cur.u] = true
          copper = copper + cur.v * COIN[cur.u]
          local nxt = peek()
          if nxt and nxt.t == "num" and COIN[nxt.u] then cur = take() else cur = nil end
        end
        local v = val("money", copper)
        return v, Napkin.Format(v)
      elseif t.u == "%" then
        local v = val("percent", t.v)
        return v, Napkin.Format(v)
      end
      local v = val("plain", t.v)
      return v, number(t.v)
    elseif t.t == "(" then
      local v, s = expr(0)
      local close = take()
      if not close or close.t ~= ")" then fail("a bracket is open") end
      return v, "(" .. s .. ")"
    elseif t.t == "-" then
      local v, s = expr(29)
      return val(v.kind, -v.v), "-" .. s
    elseif t.t == "+" then
      return expr(29)
    elseif t.t == "id" then
      if (FUNCS[t.v] or ITEM_FUNCS[t.v]) and peek() and peek().t == "(" then return call(t) end
      if FUNCS[t.v] or ITEM_FUNCS[t.v] then fail(t.u .. " needs brackets: " .. t.u .. "(...)") end
      if t.v == "of" or t.v == "x" then
        if t.v == "x" and env.vars and env.vars.x then return word(t) end
        fail("can't read '" .. t.u .. "' there")
      end
      return word(t)
    elseif t.t == "item" then
      local f = env.item
      local ok, v = false, nil
      if f then ok, v = pcall(f, t.v) end
      if not ok or not v then fail("the game won't say about [" .. t.u .. "]") end
      return val("plain", v), "[" .. t.u .. "]"
    end
    fail("can't read '" .. tokText(t) .. "' there")
  end

  --[[ the operator a token is where one is expected: "*" for "of", a lone "x" that isn't a variable, and for a
       bracket, word or item straight after a value (2(3+4), 3 pi, 2 rent); nil where the sum ends ]]
  local function binary(t)
    if BP[t.t] then return t.t, true end
    if t.t == "id" then
      if t.v == "of" or (t.v == "x" and not (env.vars and env.vars.x)) then return "*", true end
      return "*", false
    end
    if t.t == "(" or t.t == "item" then return "*", false end
    return nil
  end

  expr = function(rbp)
    local left, text = prefix()
    while true do
      local t = peek()
      if not t then break end
      local op, explicit = binary(t)
      if not op then break end
      local lbp = BP[op]
      if lbp <= rbp then break end
      if explicit then take() end
      if op == "%" then
        if left.kind ~= "plain" then fail(Napkin.Format(left) .. "%?") end
        left = val("percent", left.v)
        text = text .. "%"
      else
        local right, rt = expr(op == "^" and lbp - 1 or lbp)
        left = apply(op, left, right)
        text = text .. " " .. SYM[op] .. " " .. rt
      end
    end
    return left, text
  end

  local v, text = expr(0)
  local rest = peek()
  if rest then
    if rest.t == ")" then fail("a bracket closes that never opened") end
    fail("can't read '" .. tokText(rest) .. "' there")
  end
  return v, text
end

local function env_(env)
  env = env or {}
  return {
    values = env.values or Napkin.values, item = env.item or Napkin.item, vendor = env.vendor or Napkin.vendor,
    stack = env.stack or Napkin.stack, vars = env.vars or {},
    ans = env.ans or function() fail("nothing above to answer") end,
    total = env.total or function() fail("nothing above to add") end,
  }
end

function Napkin.Read(text, env)
  local e = env_(env)
  local ok, v, read = pcall(function()
    local toks = Napkin.Tokens(tostring(text or ""))
    if #toks == 0 then return nil end
    return parse(toks, e)
  end)
  if not ok then return nil, nil, type(v) == "table" and v.napkin or tostring(v) end
  return v, read
end

--[[ The rows of a pad, answered top to bottom: each a { value, text, read } or { err }, or {} for an empty row. A row
     "name = sum" keeps a variable for the rows below; ans is the nearest answer above, total the answered rows above
     added (percent rows left out; gold and plain rows together make total an error). ]]
function Napkin.Pad(lines, env)
  env = env or {}
  local vars, results = {}, {}
  local last, sumKind, sum, counted, mixed = nil, nil, 0, 0, false
  local e = env_({
    values = env.values, item = env.item, vendor = env.vendor, stack = env.stack, vars = vars,
    ans = function() if not last then fail("nothing above to answer") end return last end,
    total = function()
      if counted == 0 then fail("nothing above to add") end
      if mixed then fail("total mixes gold and numbers") end
      return val(sumKind, sum)
    end,
  })
  for i, line in ipairs(lines) do
    local r = {}
    local name, body = tostring(line or ""):match("^%s*([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(.-)%s*$")
    if not name then body = line end
    if name then
      r.err = Napkin.NameTaken(name, e)
      if not r.err and not body:find("%S") then r.err = name .. " = what?" end
    end
    if not r.err and body:find("%S") then
      local v, read, err = Napkin.Read(body, e)
      if err then r.err = err
      elseif v then
        r.value, r.read = v, read
        local ok, text = pcall(Napkin.Format, v, env.icons)
        if ok then r.text = text else r.value, r.read, r.err = nil, nil, type(text) == "table" and text.napkin or tostring(text) end
      end
    end
    if r.value then
      if name then vars[name:lower()] = r.value end
      last = r.value
      if r.value.kind ~= "percent" then
        if counted > 0 and sumKind ~= r.value.kind then mixed = true
        else sumKind = r.value.kind; sum = sum + r.value.v end
        counted = counted + 1
      end
    end
    results[i] = r
  end
  return results
end

function Napkin.Say(text, env)
  local v, read, err = Napkin.Read(text, env)
  if err then return nil, err end
  if not v then return nil, "Type a sum, like 12g 50s * 20." end
  local ok, out = pcall(Napkin.Format, v, false)
  if not ok then return nil, type(out) == "table" and out.napkin or tostring(out) end
  return read .. " = " .. out
end

--[[ ---- the game's words ---- ]]
local function plain(f) return function() local n = f(); if n == nil then return nil end return val("plain", n) end end
local function freeSlots()
  local free, last = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
  local get = C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
  if not get then return nil end
  for bag = 0, last do local n = get(bag); free = free + (tonumber(n) or 0) end
  return free
end
Napkin.values = {
  gold = function() return GetMoney and val("money", GetMoney()) or nil end,
  level = plain(function() return UnitLevel and UnitLevel("player") end),
  xp = plain(function() return UnitXP and UnitXP("player") end),
  xpmax = plain(function() return UnitXPMax and UnitXPMax("player") end),
  xpleft = plain(function() if UnitXP and UnitXPMax then return UnitXPMax("player") - UnitXP("player") end end),
  rested = plain(function() return GetXPExhaustion and (GetXPExhaustion() or 0) end),
  hp = plain(function() return UnitHealth and UnitHealth("player") end),
  hpmax = plain(function() return UnitHealthMax and UnitHealthMax("player") end),
  mana = plain(function() return UnitPower and UnitPower("player", 0) end),
  manamax = plain(function() return UnitPowerMax and UnitPowerMax("player", 0) end),
  points = plain(function() return FA.Talents and FA.Talents.Unspent and FA.Talents.Unspent() end),
  bagfree = plain(freeSlots),
}
--[[ for /napkin words and the README: each word and what it is ]]
Napkin.WORDS = {
  { "gold", "the money you carry" }, { "level", "your level" }, { "xp", "your experience" }, { "xpmax", "the experience your level takes" },
  { "xpleft", "the experience to the next level" }, { "rested", "your rested experience" }, { "hp", "your health" }, { "hpmax", "your full health" },
  { "mana", "your mana" }, { "manamax", "your full mana" }, { "points", "your unspent talent points" }, { "bagfree", "free bag slots" },
  { "[item link]", "how many you carry (shift-click an item into a row)" }, { "vendor([item])", "its sell price" }, { "stack([item])", "its stack size" },
  { "ans", "the nearest answer above" }, { "total", "the rows above, added" }, { "pi", "3.14159..." },
  { "sqrt floor ceil round abs min max avg", "functions, with brackets" }, { "name = sum", "keeps a variable for the rows below" },
}
function Napkin.item(link) if GetItemCount then return GetItemCount(link) end return nil end
function Napkin.vendor(link)
  if not GetItemInfo then return nil end
  local sell = select(11, GetItemInfo(link))
  return sell
end
function Napkin.stack(link)
  if not GetItemInfo then return nil end
  local stack = select(8, GetItemInfo(link))
  return stack
end
