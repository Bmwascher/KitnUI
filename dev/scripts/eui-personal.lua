-- ╔══════════════════════════════════════════════════════════════╗
-- ║  eui-personal.lua                                            ║
-- ║  Purpose: Find and clear personal data in the shipped        ║
-- ║           EllesmereUI profile string: the Raid Frames Extra  ║
-- ║           Frames block and any override that targets it.     ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Extra Frames lists members of one raid group by name, so a capture from the
-- author's own profile carries names that mean nothing to anyone else.
--
-- Run from the repo root:
--   lua dev/scripts/eui-personal.lua           report; exit 1 when anything is found
--   lua dev/scripts/eui-personal.lua --clean   rewrite Data/AddOns/EllesmereUI.lua
--
-- Decoding needs EllesmereUI's LibDeflate: KITNUI_LIBDEFLATE names the file,
-- otherwise the current EllesmereUI folder under References/ is used.
-- dev/tests/eui-personal-data.lua loads this file as a module.

local M = {}

M.DATA_PATH = "Data/AddOns/EllesmereUI.lua"
M.PREFIX = "!EUI_"

-- EllesmereUIRaidFrames' defaults for the block. A clean string carries exactly
-- these, never an absent block: the profile update reads a key the old string
-- had and the new one lacks as removed, and deletes the player's own value.
M.EXTRA_DEFAULTS = {
    showTanks = false,
    position = "right",
    freePos = { x = 100, y = -120 },
    freeHorizontal = false,
    players = {},
    extraWidth = 0,
    extraHeight = 0,
    wrapAfter = 0,
}

-- Override keys are folder .. "\31" .. path, path segments joined by "\30".
M.TARGET = "EllesmereUIRaidFrames\31extraFrames"

---------------------------------------------------------------------------------
-- EllesmereUI's serializer (type-tagged, length-prefixed strings)
---------------------------------------------------------------------------------

local function SerializeValue(v, parts)
    local t = type(v)
    if t == "string" then
        parts[#parts + 1] = "s"
        parts[#parts + 1] = #v
        parts[#parts + 1] = ":"
        parts[#parts + 1] = v
    elseif t == "number" then
        parts[#parts + 1] = "n"
        parts[#parts + 1] = tostring(v)
        parts[#parts + 1] = ";"
    elseif t == "boolean" then
        parts[#parts + 1] = v and "T" or "F"
    elseif t == "nil" then
        parts[#parts + 1] = "N"
    elseif t == "table" then
        parts[#parts + 1] = "{"
        local n = #v
        for i = 1, n do
            SerializeValue(v[i], parts)
        end
        for k, val in pairs(v) do
            if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
                parts[#parts + 1] = "K"
                SerializeValue(k, parts)
                SerializeValue(val, parts)
            end
        end
        parts[#parts + 1] = "}"
    end
end

function M.Serialize(v)
    local parts = {}
    SerializeValue(v, parts)
    return table.concat(parts)
end

local function DeserializeValue(str, pos)
    local tag = str:sub(pos, pos)
    if tag == "s" then
        local colon = str:find(":", pos + 1, true)
        if not colon then return nil, pos end
        local len = tonumber(str:sub(pos + 1, colon - 1))
        if not len then return nil, pos end
        return str:sub(colon + 1, colon + len), colon + len + 1
    elseif tag == "n" then
        local semi = str:find(";", pos + 1, true)
        if not semi then return nil, pos end
        return tonumber(str:sub(pos + 1, semi - 1)), semi + 1
    elseif tag == "T" then
        return true, pos + 1
    elseif tag == "F" then
        return false, pos + 1
    elseif tag == "N" then
        return nil, pos + 1
    elseif tag == "{" then
        local tbl, idx, p = {}, 1, pos + 1
        while p <= #str do
            local c = str:sub(p, p)
            if c == "}" then
                return tbl, p + 1
            elseif c == "K" then
                local key, val
                key, p = DeserializeValue(str, p + 1)
                val, p = DeserializeValue(str, p)
                if key ~= nil then tbl[key] = val end
            else
                local val
                val, p = DeserializeValue(str, p)
                tbl[idx] = val
                idx = idx + 1
            end
        end
        return tbl, p
    end
    return nil, pos + 1
end

function M.Deserialize(str)
    return (DeserializeValue(str, 1))
end

---------------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------------

function M.DeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not M.DeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function DeepCopy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = DeepCopy(v) end
    return out
end

function M.IsTarget(fkey)
    return type(fkey) == "string"
        and (fkey == M.TARGET or fkey:sub(1, #M.TARGET + 1) == M.TARGET .. "\30")
end

local function OverrideStores(data)
    return { { "specOverrides", data.specOverrides }, { "condOverrides", data.condOverrides } }
end

-- One line per finding; an empty list means the payload is clean.
function M.Findings(payload)
    local found = {}
    local data = type(payload) == "table" and payload.data
    if type(data) ~= "table" then return found end
    local rf = type(data.addons) == "table" and data.addons.EllesmereUIRaidFrames
    local xf = type(rf) == "table" and rf.extraFrames
    if type(rf) == "table" and not M.DeepEqual(xf, M.EXTRA_DEFAULTS) then
        local names = type(xf) == "table" and type(xf.players) == "table" and #xf.players or 0
        found[#found + 1] = ("Raid Frames Extra Frames differs from its defaults (%d names)"):format(names)
    end
    for _, pair in ipairs(OverrideStores(data)) do
        local name, store = pair[1], pair[2]
        if type(store) == "table" then
            for i, entry in ipairs(store) do
                local vals = type(entry) == "table" and entry.values
                local hit = false
                if type(vals) == "table" then
                    for _, m in pairs(vals) do
                        if type(m) == "table" then
                            for fkey in pairs(m) do
                                if M.IsTarget(fkey) then hit = true end
                            end
                        end
                    end
                end
                if hit then
                    found[#found + 1] = ("%s entry %d targets Extra Frames (%s)"):format(
                        name, i, tostring(entry.crumb or entry.label))
                end
            end
        end
    end
    return found
end

-- Resets the block to its defaults and strips Extra Frames keys from every
-- override; an entry left with no default value goes, list order kept.
function M.Clean(payload)
    local data = payload.data
    local rf = type(data.addons) == "table" and data.addons.EllesmereUIRaidFrames
    if type(rf) == "table" then rf.extraFrames = DeepCopy(M.EXTRA_DEFAULTS) end
    for _, pair in ipairs(OverrideStores(data)) do
        local store = pair[2]
        if type(store) == "table" then
            for i = #store, 1, -1 do
                local vals = type(store[i]) == "table" and store[i].values
                if type(vals) == "table" then
                    local touched = false
                    for _, m in pairs(vals) do
                        if type(m) == "table" then
                            for fkey in pairs(m) do
                                if M.IsTarget(fkey) then m[fkey] = nil; touched = true end
                            end
                        end
                    end
                    if touched and (type(vals.default) ~= "table" or next(vals.default) == nil) then
                        table.remove(store, i)
                    end
                end
            end
        end
    end
    return payload
end

---------------------------------------------------------------------------------
-- The string and the data file
---------------------------------------------------------------------------------

local function ListDir(dir)
    local names = {}
    for _, cmd in ipairs({ 'dir /b /ad "' .. dir .. '" 2>nul', 'ls -1 "' .. dir .. '" 2>/dev/null' }) do
        local p = io.popen(cmd)
        if p then
            for line in p:lines() do names[#names + 1] = (line:gsub("[\r/]+$", "")) end
            p:close()
        end
        if #names > 0 then break end
    end
    return names
end

local function Exists(path)
    local f = io.open(path, "rb")
    if f then f:close() return true end
    return false
end

-- Returns LibDeflate, or nil and why.
function M.LoadLibDeflate()
    local path = os.getenv("KITNUI_LIBDEFLATE")
    if not path then
        for _, name in ipairs(ListDir("References")) do
            local candidate = "References/" .. name .. "/EllesmereUI/Libs/LibDeflate/LibDeflate.lua"
            if name:match("^EllesmereUI") and not name:match("_old$") and Exists(candidate) then
                path = candidate
                break
            end
        end
    end
    if not path then return nil, "no LibDeflate: set KITNUI_LIBDEFLATE or add EllesmereUI under References/" end
    local ok, lib = pcall(dofile, path)
    if not ok or type(lib) ~= "table" or not lib.DecodeForPrint then
        return nil, "LibDeflate did not load from " .. path
    end
    return lib
end

function M.Decode(lib, s)
    if type(s) ~= "string" or s:sub(1, #M.PREFIX) ~= M.PREFIX then return nil, "not an EllesmereUI string" end
    local raw = lib:DecodeForPrint(s:sub(#M.PREFIX + 1))
    raw = raw and lib:DecompressDeflate(raw)
    if not raw then return nil, "the string did not decode" end
    return M.Deserialize(raw)
end

function M.Encode(lib, payload)
    return M.PREFIX .. lib:EncodeForPrint(lib:CompressDeflate(M.Serialize(payload)))
end

-- The file text and the string literal's bounds inside it.
function M.ReadData(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    local _, open = text:find('ns%.data%.EllesmereUI = "')
    if not open then return nil, "no ns.data.EllesmereUI string in " .. path end
    local close = text:find('"', open + 1, true)
    return text, text:sub(open + 1, close - 1), open + 1, close - 1
end

local function Main(args)
    local clean = args[1] == "--clean"
    local lib, why = M.LoadLibDeflate()
    if not lib then
        print("skip: " .. why)
        return 0
    end
    local text, s, i, j = M.ReadData(M.DATA_PATH)
    if not text then print(s) return 1 end
    local payload, err = M.Decode(lib, s)
    if not payload then print(err) return 1 end
    local found = M.Findings(payload)
    if #found == 0 then
        print("clean: no Extra Frames data in the shipped EllesmereUI string")
        return 0
    end
    for _, line in ipairs(found) do print("found: " .. line) end
    if not clean then
        print("run: lua dev/scripts/eui-personal.lua --clean")
        return 1
    end
    local expected = M.Clean(payload)
    local out = M.Encode(lib, expected)
    local back = M.Decode(lib, out)
    if not M.DeepEqual(back, expected) or #M.Findings(back) > 0 then
        print("the cleaned string did not decode back to the cleaned profile; nothing written")
        return 1
    end
    local f = assert(io.open(M.DATA_PATH, "wb"))
    f:write(text:sub(1, i - 1), out, text:sub(j + 1))
    f:close()
    print("cleaned " .. M.DATA_PATH .. "; bump X-EllesmereUI-Version in KitnUI.toc")
    return 0
end

if arg and type(arg[0]) == "string" and arg[0]:find("eui%-personal%.lua$") then
    os.exit(Main(arg))
end

return M
