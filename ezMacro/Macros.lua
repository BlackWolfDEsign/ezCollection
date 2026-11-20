local _, ns = ...
local L = ns.L
local Core = ezCore

-- Die eigenen Makros in Blizzards Makroverwaltung: auflisten, finden, welche auf keiner Leiste liegen,
-- löschen und als Text teilen. Angelegt und geändert wird über Import.lua (eine Stelle für CreateMacro/EditMacro).
local Macros = {}
ns.Macros = Macros

-- Aktionsplätze liest ezCore (Core.ActionSlots, eine Stelle für ezMacro, ezBars und ezCombat), Klick-Zauber
-- ebenfalls (Core.ClickBindings).
local AS = Core.ActionSlots

-- Alle Makros: { index, name, icon, body, perChar }. scope: nil = beide, "account", "char".
-- body ist der Text in Blizzards Makro; für lange Makros liefert ns.Import.BodyOf(index) den ganzen Text.
function Macros.All(scope)
    local list = {}
    if type(GetMacroInfo) ~= "function" then return list end
    local numAccount, maxAccount, numChar = ns.Import.Counts()
    local function Add(index, perChar)
        local name, icon, body = GetMacroInfo(index)
        if type(name) == "string" then
            list[#list + 1] = { index = index, name = name, icon = icon, body = body or "", perChar = perChar }
        end
    end
    if scope ~= "char" then
        for index = 1, numAccount do Add(index, false) end
    end
    if scope ~= "account" then
        for index = maxAccount + 1, maxAccount + numChar do Add(index, true) end
    end
    return list
end

-- Index eines Makros mit diesem Namen, nur im gewünschten Bereich (Charakter oder allgemein).
function Macros.Find(name, perChar)
    for _, macro in ipairs(Macros.All(perChar and "char" or "account")) do
        if macro.name == name then return macro.index end
    end
    return nil
end

-- Namen der Makros, die auf einem Aktionsplatz liegen (alle 180, auch Sonderleisten). Neuere Clients melden
-- bei Makros, die einen Zauber zeigen, dessen ID statt des Makro-Index – deshalb zählt der Name (Text des Platzes).
function Macros.OnBars()
    local names, indexes = {}, {}
    for slot = 1, AS.MAX do
        local info = AS.Info(slot)
        if info and info.kind == "macro" then
            if info.text then names[info.text] = true end
            if type(info.id) == "number" and info.subType == nil then indexes[info.id] = true end
        end
    end
    return names, indexes
end

local function KeyBound(name)
    if type(GetBindingKey) ~= "function" then return false end
    local ok, key = pcall(GetBindingKey, "MACRO " .. name)
    return ok and key ~= nil
end

-- Makros, die als Blizzards Klick-Zauber belegt sind: { [Makronummer] = true }. Über ezCores Klick-Zauber-Dienst;
-- ein älteres ezCore ohne ihn liefert dasselbe über ActionSlots.
local function MacroClicks()
    local CB = Core.ClickBindings
    if type(CB) == "table" and type(CB.IDs) == "function" then return CB.IDs("macro") end
    return AS.ClickBindings("macro")
end

-- Makros, die auf keiner Leiste liegen und auch nicht per Taste oder Klick-Zauber belegt sind.
function Macros.Unused()
    local names, indexes = Macros.OnBars()
    local clicks = MacroClicks()   -- Makros als Blizzards Klick-Zauber
    local list = {}
    for _, macro in ipairs(Macros.All()) do
        if not names[macro.name] and not indexes[macro.index] and not clicks[macro.index] and not KeyBound(macro.name) then
            list[#list + 1] = macro
        end
    end
    return list
end

-- Löscht ein Makro nach Namen (der Index verschiebt sich, solange Fenster offen sind). Nur außerhalb des Kampfes.
function Macros.Delete(name, perChar)
    if ns.InCombat() then
        ns.CombatNotice()
        return false
    end
    local index = Macros.Find(name, perChar)
    if not index or type(DeleteMacro) ~= "function" then return false end
    local body = ns.Import.RawBody(index)
    DeleteMacro(index)
    if ns.Long then ns.Long.Release(body) end
    ns.Print(L.MSG_DELETED:format(name))
    ns.SettingChanged("macros")
    return true
end

-- Hängt ein vorhandenes Makro an den Mauszeiger (zum Ablegen auf einer Leiste).
function Macros.PickUp(name, perChar)
    if ns.InCombat() then
        ns.CombatNotice()
        return false
    end
    local index = Macros.Find(name, perChar)
    if not index or type(PickupMacro) ~= "function" then return false end
    ClearCursor()
    PickupMacro(index)
    return true
end

---------------------------------------------------------------------------
-- Als Text teilen: Die erste Zeile ist ein Kommentar mit dem Namen. Blizzard überspringt solche Zeilen,
-- der Text lässt sich also auch ohne ezMacro direkt in die Makroverwaltung kopieren.
---------------------------------------------------------------------------

local SHARE_PREFIX = "# ezMacro: "

function Macros.ShareText(name, body)
    return SHARE_PREFIX .. tostring(name or "") .. "\n" .. tostring(body or "")
end

-- Liefert Name (oder nil, wenn der Text keinen nennt) und Makrotext.
function Macros.ParseShareText(text)
    text = ns.Import.CleanBody(text):gsub("^%s*\n", "")
    local first, rest = text:match("^([^\n]*)\n?(.*)$")
    local name = first and first:match("^#%s*ezMacro:%s*(.-)%s*$")
    if name then
        return name ~= "" and name or nil, rest
    end
    return nil, text
end

-- Dialog mit dem Text zum Kopieren (Strg+C), z. B. für Gilde oder Discord.
function ns.Share(name, body)
    return ns.UI.TextDialog({
        title = L.SHARE_TITLE:format(name or ""),
        hint = L.SHARE_HINT,
        text = Macros.ShareText(name, body),
        select = true,
    })
end
