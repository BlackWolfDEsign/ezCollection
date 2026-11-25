local ADDON, ns = ...
local Core = ezCore

--[[
    Makro anlegen – Core.Macro (Welle 15; Übergabe aus den Zusatzpaketen 14b: „gemeinsame Schnittstelle ‚Makro
    anlegen‘“ für ezBuff/Macro.lua, ezHeal/Macros.lua und ezMacro/Import.lua). Eine Stelle für Blizzards
    Makroverwaltung (CreateMacro/EditMacro, Leitlinie 1: das Original); Plätze, Suche nach Namen und Schreiben. Die
    Module stellen auf diesen Dienst um (Aufträge in docs/roadmap/ezCore.md); bis dahin bleiben ihre eigenen Fassungen.
    Geschützte Aktionen nur außerhalb des Kampfes (Leitlinie 5): im Kampf schreibt Core.Macro.Write nichts.

      Core.Macro.MAX_CHARS, MAX_NAME       255 bzw. 16 (Blizzards Grenzen für Text und Namen)
      Core.Macro.Available()               » sind CreateMacro, EditMacro, GetMacroIndexByName, GetMacroInfo, GetNumMacros da?
      Core.Macro.Limits()                  » Plätze allgemein, Plätze je Charakter (Constants.MacroConsts, sonst die
                                             Globalen MAX_ACCOUNT_MACROS/MAX_CHARACTER_MACROS, sonst 120 und 18)
      Core.Macro.Counts()                  » belegte allgemeine, belegte Charakter-Makros
      Core.Macro.Free(perChar)             » freie Plätze (perChar true: Charakter-Makros, sonst allgemeine)
      Core.Macro.Find(name, perChar)       » Index, Text | nil. perChar true: nur Charakter-Makros, false: nur
                                             allgemeine, nil: das erste. GetMacroIndexByName nennt nur den ersten Treffer
                                             (allgemeine kommen zuerst) – dann wird der andere Bereich einzeln gefragt.
      Core.Macro.NameLength(name)          » Länge in Zeichen (UTF-8), so misst Write die Grenze MAX_NAME
      Core.Macro.WeaponItem(itemID, platz) » „/use item:<id>“ und „/use <platz>“: Gegenstand auf die Waffe des Platzes
                                             (16 Waffenhand, 17 Schildhand; Form Core.Macro.WEAPON_ITEM)
      Core.Macro.Write(name, symbol, text, perChar, index)
                                           » Index | nil, Grund ("combat" | "api" | "long" | "name" | "full" | "failed").
                                             Mit index wird dieses Makro geändert (symbol nil: es behält seins), sonst
                                             angelegt.
    Viele Makros auf einmal (Leisten-Profile in ezCore, ezMacros Sicherung; Architektur-Review 22.11.2026 – vorher nur in
    ezMacro/Import.lua, das jetzt hierher weiterleitet):
      Core.Macro.CleanName(name)           » Name ohne Umbruch und „"“, getrimmt, auf MAX_NAME Zeichen gekürzt
      Core.Macro.CleanBody(text)           » Text mit „\n“ als Umbruch, ohne Leerraum am Ende
      Core.Macro.ScriptCommands(text)      » { "/run", … }: Befehle, die Lua-Code ausführen oder Client-Einstellungen
                                             ändern (Core.RunsCode), in der Reihenfolge ihres ersten Auftretens
      Core.Macro.Plan(liste, opts)         » { create, replace, same, full, invalid, changes } für liste =
                                             { { name, body, icon, perChar }, … }. opts.maxChars (Standard MAX_CHARS),
                                             opts.find(name, perChar) → Index (Standard Core.Macro.Find), opts.body(index)
                                             → ganzer Text eines vorhandenen Makros (Standard GetMacroInfo)
      Core.Macro.PlanText(plan)            » „9 neu, 2 ersetzen, 1 unverändert, 3 ohne Platz“ (Texte MACRO_PLAN_* aus ezCore)
]]

local Macro = {}
Core.Macro = Macro

Macro.MAX_CHARS = 255
Macro.MAX_NAME = 16
Macro.DEFAULT_ICON = Core.ICON_FALLBACK_ID   -- 134400, INV_Misc_QuestionMark: mit #showtooltip zeigt das Makro den Zauber selbst

local function Api(name)
    local fn = rawget(_G, name)
    return type(fn) == "function" and fn or nil
end

function Macro.Available()
    for _, name in ipairs({ "CreateMacro", "EditMacro", "GetMacroIndexByName", "GetMacroInfo", "GetNumMacros" }) do
        if not Api(name) then return false end
    end
    return true
end

function Macro.Limits()
    local consts = Core.Peek(rawget(_G, "Constants"), "MacroConsts")
    local maxAccount = Core.Num(Core.Peek(consts, "MAX_ACCOUNT_MACROS")) or Core.Num(rawget(_G, "MAX_ACCOUNT_MACROS")) or 120
    local maxChar = Core.Num(Core.Peek(consts, "MAX_CHARACTER_MACROS")) or Core.Num(rawget(_G, "MAX_CHARACTER_MACROS")) or 18
    return maxAccount, maxChar
end

function Macro.Counts()
    local account, perChar = Core.Call(Api("GetNumMacros"))
    return Core.Num(account) or 0, Core.Num(perChar) or 0
end

function Macro.Free(perChar)
    local maxAccount, maxChar = Macro.Limits()
    local account, char = Macro.Counts()
    if perChar then return math.max(0, maxChar - char) end
    return math.max(0, maxAccount - account)
end

local function Info(index)
    local name, _, body = Core.Call(Api("GetMacroInfo"), index)
    return Core.Plain(name), Core.Plain(body)
end

function Macro.Find(name, perChar)
    if type(name) ~= "string" or name == "" then return nil end
    local maxAccount = Macro.Limits()
    local index = Core.Num(Core.Call(Api("GetMacroIndexByName"), name))
    if not (index and index > 0) then return nil end
    local isChar = index > maxAccount
    if perChar == nil or perChar == isChar then
        local _, body = Info(index)
        return index, body
    end
    -- der erste Treffer liegt im anderen Bereich: den gewünschten einzeln fragen
    local account, char = Macro.Counts()
    local first, last = 1, account
    if perChar then first, last = maxAccount + 1, maxAccount + char end
    for i = first, last do
        local n, body = Info(i)
        if n == name then return i, body end
    end
    return nil
end

-- Gegenstand auf eine Waffe auftragen (Gift, Wetzstein, Öl): „/use item:<id>“ nimmt den Gegenstand, die zweite Zeile
-- „/use <platz>“ wählt die Waffe dieses Platzes als Ziel – wie Blizzards eigene Makros; ein Tastendruck, eine Aktion.
-- Eine Form für ezBuff (Weapon.Macro) und ezMacro (Vorlagen „Gift Waffenhand“/„Gift Schildhand“). → Text | nil
Macro.WEAPON_ITEM = "/use item:%d\n/use %d"
function Macro.WeaponItem(itemID, slot)
    itemID, slot = Core.Num(itemID), Core.Num(slot)
    if not (itemID and slot) then return nil end
    return Macro.WEAPON_ITEM:format(itemID, slot)
end

-- Länge eines Makronamens in Zeichen (UTF-8): Blizzards Makrofenster nimmt 16 Zeichen, „Großer Segen der“ hat
-- 16 Zeichen, aber 17 Bytes. Dieselbe Zählung wie Core.TruncateChars, mit dem die Module ihre Namen kürzen.
function Macro.NameLength(name)
    if type(name) ~= "string" then return 0 end
    local utf8len = rawget(_G, "strlenutf8")
    if type(utf8len) == "function" then
        local ok, n = pcall(utf8len, name)
        if ok and type(n) == "number" then return n end
    end
    local _, n = name:gsub("[^\128-\191]", "")
    return n
end

function Macro.Write(name, icon, body, perChar, index)
    if Core.InCombat() then return nil, "combat" end
    if not Macro.Available() then return nil, "api" end
    if type(name) ~= "string" or name == "" or Macro.NameLength(name) > Macro.MAX_NAME then return nil, "name" end
    if type(body) ~= "string" or #body > Macro.MAX_CHARS then return nil, "long" end
    local ok, result
    if index then
        ok, result = pcall(Api("EditMacro"), index, name, icon, body)
    else
        if Macro.Free(perChar) <= 0 then return nil, "full" end
        ok, result = pcall(Api("CreateMacro"), name, icon or Macro.DEFAULT_ICON, body, perChar and true or nil)
    end
    if not ok then return nil, "failed" end
    result = Core.Num(result)
    if result and result > 0 then return result end
    local found = Macro.Find(name, perChar and true or false)
    if found then return found end
    return nil, "failed"
end

---------------------------------------------------------------------------
-- Viele Makros auf einmal: erst ein Plan, dann eine gesammelte Rückfrage (Architektur-Review 22.11.2026: die Leisten-
-- Profile wohnen in ezCore und legen fehlende Makros auch ohne ezMacro an; vorher ezMacro/Import.lua, das weiterleitet)
---------------------------------------------------------------------------

function Macro.CleanName(name)
    name = Core.Trim((tostring(name or ""):gsub("[\r\n\"]", "")))
    return Core.TruncateChars(name, Macro.MAX_NAME)
end

function Macro.CleanBody(body)
    body = tostring(body or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("%s+$", "")
    return body
end

-- Welche Befehle Lua-Code ausführen oder Client-Einstellungen ändern, entscheidet Core.RunsCode (Gesamtreview
-- 18.11.2026, T6-1). Ein Befehl zählt am Zeilenanfang; Doppelte fallen weg.
function Macro.ScriptCommands(body)
    local found, seen = {}, {}
    if type(body) ~= "string" then return found end
    for line in body:gmatch("[^\r\n]+") do
        local cmd = line:match("^%s*(/[^%s%[]+)")
        cmd = cmd and cmd:lower()
        if cmd and not seen[cmd] and Core.RunsCode(cmd) then
            seen[cmd] = true
            found[#found + 1] = cmd
        end
    end
    return found
end

local function RawBody(index)
    local _, body = Info(index)
    return body
end

function Macro.Plan(list, opts)
    opts = type(opts) == "table" and opts or {}
    local find = type(opts.find) == "function" and opts.find or function(name, perChar)
        return (Macro.Find(name, perChar))
    end
    local bodyOf = type(opts.body) == "function" and opts.body or RawBody
    local maxChars = Core.Num(opts.maxChars) or Macro.MAX_CHARS
    local plan = { create = {}, replace = {}, same = {}, full = {}, invalid = {} }
    local maxAccount, maxChar = Macro.Limits()
    local numAccount, numChar = Macro.Counts()
    local free = { [true] = maxChar - numChar, [false] = maxAccount - numAccount }
    local seen = {}
    for _, macro in ipairs(type(list) == "table" and list or {}) do
        local name, body = Macro.CleanName(macro.name), Macro.CleanBody(macro.body)
        local perChar = macro.perChar and true or false
        local item = { name = name, body = body, icon = macro.icon, perChar = perChar }
        local key = (perChar and "c:" or "a:") .. name
        if name == "" or body == "" or #body > maxChars then
            table.insert(plan.invalid, item)
        elseif not seen[key] then
            seen[key] = true
            local index = find(name, perChar)
            if index then
                if Macro.CleanBody(bodyOf(index)) == body then
                    table.insert(plan.same, item)
                else
                    table.insert(plan.replace, item)
                end
            elseif free[perChar] > 0 then
                free[perChar] = free[perChar] - 1
                table.insert(plan.create, item)
            else
                table.insert(plan.full, item)
            end
        end
    end
    plan.changes = #plan.create + #plan.replace
    return plan
end

function Macro.PlanText(plan)
    local L = Core.L
    local parts = {}
    if #plan.create > 0 then parts[#parts + 1] = L.MACRO_PLAN_CREATE:format(#plan.create) end
    if #plan.replace > 0 then parts[#parts + 1] = L.MACRO_PLAN_REPLACE:format(#plan.replace) end
    if #plan.same > 0 then parts[#parts + 1] = L.MACRO_PLAN_SAME:format(#plan.same) end
    if #plan.full > 0 then parts[#parts + 1] = L.MACRO_PLAN_FULL:format(#plan.full) end
    if #plan.invalid > 0 then parts[#parts + 1] = L.MACRO_PLAN_INVALID:format(#plan.invalid) end
    if #parts == 0 then return L.MACRO_PLAN_EMPTY end
    return table.concat(parts, ", ")
end
