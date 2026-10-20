--[[ A build code as the site writes it (forever-armoury: public/content/build-code.js, #863), read and written here:

       FAT2-70170-warrior-Arms%20PvP-0a0a0a0b0b0b1c
       FAT <version> - <build> - <class> - <name> - <picks> { . <class> - <name> - <picks> }

     The build is the game client's build number the talents are from (GetBuildInfo's second answer, 70170 of
     1.60.1.70170): a talent that moves between the beta's builds changes what a cell means, so the site carries a
     code's picks to the trees it has by it (#1215). The addon writes the build it runs on and reads any: it applies a
     cell to the game's own trees, which are the truth in-game. The class is in lower case as the site names it
     (warrior, paladin, ...). The name has everything but letters and digits as %XX of its UTF-8 bytes, and is empty
     for a build with none. The picks are the build's points in the order spent, two characters a point: the tree
     (0-2) then the talent's cell, (tier - 1) * 4 + (column - 1), in base 36. Point n is taken at level n + 9. The
     cell is matched to a talent with the game's own tier and column (Builds.lua), so nothing here needs changing at
     a patch. Several builds join with ".".

     FA.Code.Read(text) reads every code in a pasted text, ignoring what's around it, and answers
       builds, nil, notes   builds: { { cls, name, picks, build }, ... }   notes: what was left out, to tell the person
       nil, error           error: why, in a sentence
     build is the game build the picks are from, or nil for a FAT1- code, from before the build was written in.
     FA.Code.Write(builds[, build]) is the code for a list of { cls, name, picks } from one game build: the game's own
     when build is nil, and a FAT1- code when it's false, for picks from a code from before the build was written in.
     FA.Code.GameBuild() is the build the game is on, as a code carries it.
     FA.Code.Points(picks) is a picks string as { { tab = 1..3, cell = 0..27 }, ... }, or nil for one that doesn't read.

     Each version has its own reader in READERS, so a code from an older site still reads when the format changes.
     Version 1 had no build: FAT1-<class>-<name>-<picks>{.<class>-<name>-<picks>}.

     Letters and digits are spelt out as A-Z, a-z and 0-9 rather than %w, which follows the locale: under a UTF-8 one
     it takes bytes above 127 for letters, and a name would pass them through unencoded; whitespace likewise, as
     SPACES, rather than %s. The reader keeps to the site's (forever-armoury#1539): a name is cut to MAX_NAME
     characters with a note, a name whose bytes aren't UTF-8 is refused, a code's version has three digits at most
     and its build eight, and a run of full stops after a code is cut back byte by byte, not with a pattern that
     tries every run (the site's #926). ]]

local _, FA = ...
local Code = {}
FA.Code = Code

Code.VERSION = 2
Code.MAX_NAME = 40
local MAX_NAME = Code.MAX_NAME
local CLASSES = { warrior = true, paladin = true, hunter = true, rogue = true, priest = true, shaman = true, mage = true, warlock = true, druid = true }
--[[ a code in a pasted text: its start, and everything after it that a code is made of ]]
local FIND = "FAT%d%d?%d?%-[A-Za-z0-9%%%.%-]*"
local NOT_A_CODE = "That isn't a build code. A build code starts with FAT2- (or FAT1-, from before)."

--[[ Whitespace as the site's \s has it: the ASCII kinds, then Unicode's, each as its UTF-8 bytes (no-break space,
     the ogham mark, the en quad to the hair space, the line and paragraph separators, the narrow no-break and the
     medium mathematical space, the ideographic space, and the byte order mark). ]]
local SPACES = { "[ \t\n\v\f\r]", "\194\160", "\225\154\128", "\226\128[\128-\138]", "\226\128\168", "\226\128\169", "\226\128\175",
  "\226\129\159", "\227\128\128", "\239\187\191" }
--[[ The name with its whitespace of every kind collapsed to single spaces and none at either end. ]]
local function clean(name)
  name = tostring(name or "")
  for _, pattern in ipairs(SPACES) do name = name:gsub(pattern, " ") end
  return (name:gsub("  +", " "):match("^ *(.-) *$"))
end
--[[ The first n characters of a UTF-8 string (a character being a lead byte and its continuation bytes). ]]
local function firstChars(s, n)
  local count, cut = 0, #s
  for pos in s:gmatch("()[^\128-\191]") do
    count = count + 1
    if count > n then cut = pos - 1; break end
  end
  return s:sub(1, cut), count > n
end
--[[ Whether every byte of s is part of a well-formed UTF-8 character: one byte under 128, or a lead byte followed by
     its continuation bytes, with overlong forms, surrogates and anything past U+10FFFF refused, as a browser's
     decodeURIComponent refuses them. ]]
local function utf8(s)
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    local len, min
    if c < 0x80 then len, min = 1, 0
    elseif c >= 0xC2 and c <= 0xDF then len, min = 2, 0x80
    elseif c >= 0xE0 and c <= 0xEF then len, min = 3, 0x800
    elseif c >= 0xF0 and c <= 0xF4 then len, min = 4, 0x10000
    else return false end
    if i + len - 1 > n then return false end
    local code = len == 1 and c or (c % (2 ^ (7 - len)))
    for j = i + 1, i + len - 1 do
      local b = s:byte(j)
      if b < 0x80 or b > 0xBF then return false end
      code = code * 64 + (b - 0x80)
    end
    if code < min or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then return false end
    i = i + len
  end
  return true
end
local function encodeName(name) return (name:gsub("[^A-Za-z0-9]", function(c) return string.format("%%%02X", c:byte()) end)) end
--[[ The name as text, or nil when it isn't a name (a broken or cut-off %XX, or bytes that aren't UTF-8). ]]
local function decodeName(s)
  for pos in s:gmatch("()%%") do if not s:sub(pos + 1, pos + 2):match("^%x%x$") then return nil end end
  local name = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  if not utf8(name) then return nil end
  return name
end
--[[ The game's build number, as the code carries it: 0 outside the game (the tests stub GetBuildInfo). ]]
local function gameBuild()
  local _, build = GetBuildInfo()
  return tonumber(build) or 0
end
Code.GameBuild = gameBuild

function Code.Points(picks)
  if type(picks) ~= "string" or #picks % 2 ~= 0 or #picks > 102 then return nil end
  local out = {}
  for i = 1, #picks, 2 do
    local pair = picks:sub(i, i + 1)
    if not pair:match("^[0-2][0-9a-r]$") then return nil end
    out[#out + 1] = { tab = tonumber(pair:sub(1, 1)) + 1, cell = tonumber(pair:sub(2, 2), 36) }
  end
  return out
end

function Code.Write(builds, build)
  local parts = {}
  for i, b in ipairs(builds) do parts[i] = b.cls .. "-" .. encodeName(clean(firstChars(clean(b.name), MAX_NAME))) .. "-" .. (b.picks or "") end
  if build == false then return "FAT1-" .. table.concat(parts, ".") end
  return "FAT" .. Code.VERSION .. "-" .. (build or gameBuild()) .. "-" .. table.concat(parts, ".")
end

--[[ Version 1: <class>-<name>-<picks>{.<class>-<name>-<picks>}, with no build. Adds to out.builds and out.empty, each
     build with the game build it's from (nil for none), and answers why it stopped, or nil once it has read them all. ]]
local function read1(body, out, build)
  for seg in (body .. "."):gmatch("(.-)%.") do
    local n = #out.builds + out.empty + 1
    local cls, name, picks = seg:match("^([a-z]+)%-([A-Za-z0-9%%]*)%-([0-9a-r]*)$")
    if not cls or not CLASSES[cls] or not Code.Points(picks) then
      return "Build " .. n .. " of that code doesn't read. It may be cut off: copy the whole code again."
    end
    name = decodeName(name)
    if not name then return "The name of build " .. n .. " in that code is cut off or changed. Copy the whole code again." end
    if picks == "" then out.empty = out.empty + 1
    else
      local cut
      name, cut = firstChars(clean(name), MAX_NAME)
      if cut then name = clean(name); out.notes[#out.notes + 1] = "The name of build " .. n .. " was cut to " .. MAX_NAME .. " characters." end
      out.builds[#out.builds + 1] = { cls = cls, name = name, picks = picks, build = build }
    end
  end
  return nil
end
--[[ Version 2: <build>- (eight digits at most), then as version 1. ]]
local function read2(body, out)
  local build, rest = body:match("^(%d+)%-(.*)$")
  if not build or #build > 8 then return "That code doesn't read. It may be cut off: copy the whole code again." end
  return read1(rest, out, tonumber(build))
end
local READERS = { [1] = read1, [2] = read2 }

function Code.Read(text)
  text = tostring(text or "")
  if not text:find("%S") then return nil, "Paste a build code first." end
  local out, found = { builds = {}, notes = {}, empty = 0 }, 0
  for m in text:gmatch(FIND) do
    found = found + 1
    local version = tonumber(m:match("^FAT(%d+)"))
    local reader = READERS[version]
    if not reader then
      if version > Code.VERSION then return nil, "That code is from a newer version of Forever Armoury than this addon. Update the addon and try again." end
      return nil, NOT_A_CODE
    end
    --[[ a sentence's full stops after the code aren't part of it: counted back from the end, since a pattern for a
         run of them at the end tries every run in the code first ]]
    local body = m:gsub("^FAT%d+%-", "")
    local last = #body
    while last > 0 and body:byte(last) == 46 do last = last - 1 end
    body = body:sub(1, last)
    local err = reader(body, out)
    if err then return nil, err end
  end
  if found == 0 then return nil, NOT_A_CODE end
  if #out.builds == 0 then return nil, out.empty == 1 and "That build has no talent points." or "Those builds have no talent points." end
  if out.empty > 0 then out.notes[#out.notes + 1] = "Left out " .. (out.empty == 1 and "a build" or out.empty .. " builds") .. " with no talent points." end
  return out.builds, nil, out.notes
end
