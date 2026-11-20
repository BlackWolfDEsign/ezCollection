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
      Core.Macro.Write(name, symbol, text, perChar, index)
                                           » Index | nil, Grund ("combat" | "api" | "long" | "name" | "full" | "failed").
                                             Mit index wird dieses Makro geändert (symbol nil: es behält seins), sonst
                                             angelegt.
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
