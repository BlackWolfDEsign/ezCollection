local ADDON, ns = ...
local Core = ezCore

--[[
    Export und Import als Text (ezBag: Gruppen, ezMacro: Makros teilen, ezBars/ezPanel: Profile).
      ezCore.Serialize(wert)   → Text, oder nil und Grund ("type", "cycle", "number")
      ezCore.Deserialize(text, opts) → Wert, oder nil und Grund ("empty", "prefix", "version", "syntax", "depth", "size")
                                           Grenzen (Gesamtreview 18.11.2026, T6-7): höchstens opts.maxLength Zeichen
                                           (Standard Core.IMPORT_MAX_LENGTH) und opts.maxItems Einträge in allen
                                           Tabellen zusammen (Standard Core.IMPORT_MAX_ITEMS); mehr → "size"
      ezCore.Pack(kind, v, daten)        → Text, oder nil und Grund: der Export-Umschlag { kind, v, … } (W-14; vorher
                                           baute und prüfte ihn jedes Modul selbst, ezMacro ohne Versionsprüfung).
                                           daten ist eine Tabelle; ihre Felder stehen neben kind und v
                                           (Core.Pack("ezBag.groups", 1, { groups = … })). Gründe: "kind" (kein Name),
                                           "version" (keine ganze Zahl ab 1), "type" (keine Tabelle) und die von Serialize
      ezCore.Unpack(text, kind, maxV, opts) → Tabelle, v – oder nil und Grund: die von Deserialize (opts wie dort), dazu "shape" (kein
                                           Umschlag), "kind" (anderer Inhalt), "newer" (v ist größer als maxV: der Text
                                           stammt aus einer neueren Fassung) und "version" (v fehlt oder ist keine
                                           ganze Zahl ab 1). kind darf eine Liste erlaubter Namen sein; ohne maxV
                                           gilt jede Version.

    Sicher: kein loadstring, der Text wird Zeichen für Zeichen gelesen. Erlaubt sind nur Tabellen, Texte,
    endliche Zahlen und true/false. Der Text besteht nur aus druckbaren ASCII-Zeichen ohne Leerraum und
    ohne „|“ (Blizzards Eingabefelder deuten „|“ als Steuerzeichen). Beim Einfügen darf er umbrochen sein:
    Leerraum wird vor dem Lesen entfernt. Kennung und Formatversion stehen vorn („EZ1:“); was im Wert
    steckt (z. B. { kind = "ezBag.groups", v = 1, … }), prüft das Modul selbst.

    Aufbau: "Text"  #Zahl;  + (true)  - (false)  { Schlüssel Wert … }
    In Texten sind alle Zeichen außer Buchstaben, Ziffern und . _ - * / ( ) , : ! ? als %XX kodiert.
]]

local PREFIX, VERSION = "EZ", 1
local MAX_DEPTH = 40
-- Obergrenzen für eingefügte Texte (T6-7): reichen für die Sicherungen der Einstellungen und Profile und halten einen
-- manipulierten Riesentext heraus. Größere eigene Texte geben ihre Grenze als opts mit und prüfen sie schon beim
-- Sichern („Fundorte als Text sichern“: G.BACKUP_MAX_LENGTH/G.BACKUP_MAX_ITEMS in Gathering.lua).
Core.IMPORT_MAX_LENGTH = 4 * 1024 * 1024
Core.IMPORT_MAX_ITEMS = 400000

local format, byte, char, sub, find, gsub = string.format, string.byte, string.char, string.sub, string.find, string.gsub
local tconcat, floor = table.concat, math.floor

local function EscapeChar(c) return format("%%%02X", byte(c)) end
local function Escape(text) return (gsub(text, "[^%w%.%_%-%*/%(%),:!%?]", EscapeChar)) end
local function Unescape(text) return (gsub(text, "%%(%x%x)", function(hex) return char(tonumber(hex, 16)) end)) end

local function IsFinite(n) return n == n and n ~= math.huge and n ~= -math.huge end

local function NumberText(n)
    if floor(n) == n and n >= -2^53 and n <= 2^53 then return format("%d", n) end
    return format("%.17g", n)
end

-- Schlüssel in fester Reihenfolge, damit derselbe Wert immer denselben Text ergibt: Core.SortedKeys (Util.lua).
local SortedKeys = Core.SortedKeys

local function Write(value, out, seen)
    local kind = type(value)
    if kind == "string" then
        out[#out + 1] = '"' .. Escape(value) .. '"'
    elseif kind == "number" then
        if not IsFinite(value) then return "number" end
        out[#out + 1] = "#" .. NumberText(value) .. ";"
    elseif kind == "boolean" then
        out[#out + 1] = value and "+" or "-"
    elseif kind == "table" then
        if seen[value] then return "cycle" end
        seen[value] = true
        out[#out + 1] = "{"
        for _, key in ipairs(SortedKeys(value)) do
            local err = Write(key, out, seen) or Write(value[key], out, seen)
            if err then return err end
        end
        out[#out + 1] = "}"
        seen[value] = nil
    else
        return "type"
    end
    return nil
end

function Core.Serialize(value)
    local out = { PREFIX .. VERSION .. ":" }
    local err = Write(value, out, {})
    if err then return nil, err end
    return tconcat(out)
end

-- Leser: pos zeigt auf das nächste Zeichen; jeder Fehler bricht mit error({ reason }) ab.
local function Fail(reason) error({ reason = reason }, 0) end

local Read
local function ReadString(text, pos)
    local close = find(text, '"', pos + 1, true)
    if not close then Fail("syntax") end
    local raw = sub(text, pos + 1, close - 1)
    if find((gsub(raw, "%%%x%x", "")), "%", 1, true) then Fail("syntax") end
    return Unescape(raw), close + 1
end

local function ReadNumber(text, pos)
    local close = find(text, ";", pos + 1, true)
    if not close then Fail("syntax") end
    local n = tonumber(sub(text, pos + 1, close - 1))
    if not n or not IsFinite(n) then Fail("syntax") end
    return n, close + 1
end

-- Zähler der Einträge eines Lesevorgangs (Deserialize ruft nie sich selbst auf, ein Wert genügt).
local items, maxItems = 0, 0

local function ReadTable(text, pos, depth)
    if depth > MAX_DEPTH then Fail("depth") end
    local t = {}
    pos = pos + 1
    while true do
        local c = sub(text, pos, pos)
        if c == "" then Fail("syntax") end
        if c == "}" then return t, pos + 1 end
        items = items + 1
        if items > maxItems then Fail("size") end
        local key
        key, pos = Read(text, pos, depth + 1)
        if type(key) == "table" then Fail("syntax") end
        local value
        value, pos = Read(text, pos, depth + 1)
        t[key] = value
    end
end

Read = function(text, pos, depth)
    local c = sub(text, pos, pos)
    if c == '"' then return ReadString(text, pos)
    elseif c == "#" then return ReadNumber(text, pos)
    elseif c == "+" then return true, pos + 1
    elseif c == "-" then return false, pos + 1
    elseif c == "{" then return ReadTable(text, pos, depth)
    end
    Fail("syntax")
end

-- Grenze aus opts oder der Standard; nur ganze Zahlen ab 1 zählen.
local function Limit(opts, key, default)
    local n = type(opts) == "table" and opts[key]
    if type(n) == "number" and n >= 1 and n == floor(n) then return n end
    return default
end

function Core.Deserialize(text, opts)
    if type(text) ~= "string" or Core.IsSecret(text) then return nil, "empty" end
    if #text > Limit(opts, "maxLength", Core.IMPORT_MAX_LENGTH) then return nil, "size" end
    text = gsub(text, "%s+", "")
    if text == "" then return nil, "empty" end
    local version, rest = text:match("^" .. PREFIX .. "(%d+):(.*)$")
    if not version then return nil, "prefix" end
    if tonumber(version) ~= VERSION then return nil, "version" end
    items, maxItems = 0, Limit(opts, "maxItems", Core.IMPORT_MAX_ITEMS)
    local ok, value, pos = pcall(Read, rest, 1, 0)
    if not ok then return nil, type(value) == "table" and value.reason or "syntax" end
    if pos ~= #rest + 1 then return nil, "syntax" end
    return value
end

---------------------------------------------------------------------------
-- Export-Umschlag { kind, v, … }
---------------------------------------------------------------------------

local function IsVersion(v)
    return type(v) == "number" and v >= 1 and v == floor(v)
end

function Core.Pack(kind, version, data)
    if type(kind) ~= "string" or kind == "" then return nil, "kind" end
    if not IsVersion(version) then return nil, "version" end
    if data ~= nil and type(data) ~= "table" then return nil, "type" end
    local envelope = {}
    for key, value in pairs(data or {}) do envelope[key] = value end
    envelope.kind, envelope.v = kind, version
    return Core.Serialize(envelope)
end

function Core.Unpack(text, kind, maxVersion, opts)
    local value, reason = Core.Deserialize(text, opts)
    if value == nil then return nil, reason end
    if type(value) ~= "table" or type(value.kind) ~= "string" then return nil, "shape" end
    local wanted = false
    if type(kind) == "table" then
        for _, name in ipairs(kind) do
            if name == value.kind then wanted = true end
        end
    else
        wanted = kind == nil or kind == value.kind
    end
    if not wanted then return nil, "kind" end
    if not IsVersion(value.v) then return nil, "version" end
    if type(maxVersion) == "number" and value.v > maxVersion then return nil, "newer" end
    return value, value.v
end

---------------------------------------------------------------------------
-- Prüfungen für eingefügte Texte (Gesamtreview 18.11.2026, T6-5, T6-6, T6-7, T6-8): eine Fassung für alle Importe
---------------------------------------------------------------------------
--[[
    Was ein fremder oder bearbeiteter Text mitbringt, ist nie vertrauenswürdig. Diese Helfer prüfen einzelne Werte;
    Art, Version, Länge und Zahl der Einträge prüft schon Core.Unpack bzw. Core.Deserialize.
      ezCore.FiniteNumber(wert, min, max)   → Zahl oder nil: Zahl oder Zahlentext, nicht geheim, endlich (kein NaN,
                                              kein „1e999“ = unendlich), mit min/max innerhalb der Grenzen
      ezCore.CleanImportName(text, maxChars)→ Name ohne Farb-, Link-, Textur- und sonstige „|“-Codes, ohne
                                              Steuerzeichen (Zeilenumbruch → Leerzeichen), getrimmt und UTF-8-sicher auf
                                              maxChars Zeichen gekürzt (Standard Core.IMPORT_NAME_MAX); nil, wenn leer
      ezCore.CleanScalar(wert, maxText)     → Wahrheitswert, endliche Zahl oder Text bis maxText Bytes (Standard
                                              Core.IMPORT_TEXT_MAX), sonst nil (Tabelle, geheim, zu lang)
      ezCore.CleanFlatTable(t, maxItems, maxText) → flache Kopie: nur Schlüssel und Werte, die CleanScalar besteht,
                                              höchstens maxItems Einträge (Standard Core.IMPORT_LIST_MAX); nil ohne Tabelle
      ezCore.Literal(text)                  → Text, in dem jedes „|“ verdoppelt ist: Blizzards Dialoge, Menüs und
                                              Tooltips zeigen ihn wörtlich, statt Farb- oder Link-Codes auszuführen
      ezCore.RunsCode(text)                 → true, wenn eine Zeile mit einem Befehl beginnt, der Lua-Code oder
                                              Konsolenbefehle ausführt (/run, /script, /dump, /console, /tinspect und
                                              ihre Übersetzungen laut SLASH_SCRIPT1 … des Clients)
      ezCore.PreviewCommand(text)           → Text für eine Rückfrage: Literal, jede solche Zeile dahinter rot
                                              gekennzeichnet (IMPORT_RUNS_CODE)
]]
Core.IMPORT_NAME_MAX = 40
Core.IMPORT_TEXT_MAX = 200
Core.IMPORT_LIST_MAX = 200

function Core.FiniteNumber(value, minValue, maxValue)
    if Core.IsSecret(value) then return nil end
    if type(value) == "string" then value = tonumber(value) end
    if type(value) ~= "number" or not IsFinite(value) then return nil end
    if type(minValue) == "number" and value < minValue then return nil end
    if type(maxValue) == "number" and value > maxValue then return nil end
    return value
end

function Core.CleanImportName(text, maxChars)
    if type(text) ~= "string" or Core.IsSecret(text) then return nil end
    text = Core.PlainText(text)
    text = gsub(text, "|n", " ")
    text = gsub(text, "|", "")
    text = gsub(text, "%c", " ")
    text = gsub(text, "%s+", " ")
    text = Core.Trim(text)
    maxChars = type(maxChars) == "number" and maxChars >= 1 and floor(maxChars) or Core.IMPORT_NAME_MAX
    text = Core.Trim(Core.TruncateChars(text, maxChars))
    if text == "" then return nil end
    return text
end

function Core.CleanScalar(value, maxText)
    if Core.IsSecret(value) then return nil end
    local kind = type(value)
    if kind == "boolean" then return value end
    if kind == "number" then return IsFinite(value) and value or nil end
    if kind == "string" then
        if #value > (type(maxText) == "number" and maxText or Core.IMPORT_TEXT_MAX) then return nil end
        return value
    end
    return nil
end

function Core.CleanFlatTable(tbl, maxItems, maxText)
    if type(tbl) ~= "table" or Core.IsSecret(tbl) then return nil end
    maxItems = type(maxItems) == "number" and maxItems or Core.IMPORT_LIST_MAX
    local out, n = {}, 0
    for _, key in ipairs(SortedKeys(tbl)) do
        local k, v = Core.CleanScalar(key, maxText), Core.CleanScalar(tbl[key], maxText)
        if k ~= nil and v ~= nil then
            if n >= maxItems then break end
            out[k], n = v, n + 1
        end
    end
    return out
end

function Core.Literal(text)
    if type(text) ~= "string" or Core.IsSecret(text) then return "" end
    return (gsub(text, "|", "||"))
end

-- Befehle, die Code ausführen: die festen englischen Namen und, was der Client unter SCRIPT, DUMP, CONSOLE und
-- TABLEINSPECT anmeldet (Blizzards Übersetzungen, z. B. /skript). TABLEINSPECT (/tinspect, /tableinspect) übersetzt
-- sein Argument mit loadstring("return " .. msg) und ruft es auf (Blizzards Forever-Quelle,
-- Blizzard_ChatFrameBase/Shared/SlashCommands.lua; Fund der Gegenprüfung zu T6-6). Gelesen bei jedem Aufruf, damit
-- spät angemeldete mitzählen.
local CODE_COMMANDS = { "/run", "/script", "/dump", "/console", "/tinspect", "/tableinspect" }
local CODE_HANDLERS = { "SCRIPT", "DUMP", "CONSOLE", "TABLEINSPECT" }

local function CodeCommand(word)
    word = word:lower()
    for _, cmd in ipairs(CODE_COMMANDS) do
        if word == cmd then return true end
    end
    for _, name in ipairs(CODE_HANDLERS) do
        for i = 1, 10 do
            local slash = rawget(_G, "SLASH_" .. name .. i)
            if type(slash) ~= "string" then break end
            if slash:lower() == word then return true end
        end
    end
    return false
end

local function LineRunsCode(line)
    local word = line:match("^%s*(/%S+)")
    return word ~= nil and CodeCommand(word)
end

function Core.RunsCode(text)
    if type(text) ~= "string" or Core.IsSecret(text) then return false end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        if LineRunsCode(line) then return true end
    end
    return false
end

function Core.PreviewCommand(text)
    if type(text) ~= "string" or Core.IsSecret(text) then return "" end
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local shown = Core.Literal(line)
        if LineRunsCode(line) then shown = shown .. " " .. Core.Red("(" .. Core.L.IMPORT_RUNS_CODE .. ")") end
        lines[#lines + 1] = shown
    end
    return tconcat(lines, "\n")
end
