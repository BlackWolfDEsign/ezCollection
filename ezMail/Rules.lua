local _, ns = ...
local L = ns.L
local Menu = ezCore.Menu     -- Menüs an einer Stelle (Blizzards MenuUtil)

--[[
    Absender-Regeln (auslassen, zurückschicken, vertrauen). Je Absender eine Regel:
      "skip"   – bei „Alle öffnen“ (gefiltert) und beim Einsammeln am Briefkasten auslassen
      "return" – beim Öffnen des Briefkastens automatisch zurückschicken (nur, was zurückgehen kann)
      "trust"  – vertraut: auch dann öffnen, wenn „Alle anderen Briefe“ aus ist; Einsammeln nimmt alles
    Eigene Charaktere (ezCore) gelten immer als vertraut. Die Regeln gelten für alle Charaktere des
    Kontos (ezMailDB.rules, Schlüssel = voller Name klein, wie ezCore.FullName ihn liefert).
    Sichtbar: Pfeil im offenen Brief („Absender“), Pfeil neben „Alle öffnen“ („Absender-Regeln“),
    Zeile im Tooltip der Briefliste.
]]

local Rules = {}
ns.Rules = Rules

Rules.KINDS = { "trust", "skip", "return" }

local function Store()
    ns.db.rules = ns.db.rules or {}
    return ns.db.rules
end

-- Absender (Kopfzeile, Eingabe) → Schlüssel und Anzeigename.
function Rules.Key(sender)
    local full = type(sender) == "string" and ezCore.FullName(sender)
    if not full then return nil end
    return full:lower(), ezCore.ShortName(full)
end

function Rules.Get(sender)
    local key = Rules.Key(sender)
    local entry = key and Store()[key]
    return entry and entry.rule or nil
end

function Rules.IsOwn(sender)
    return ezCore.FindChar(sender) ~= nil
end

function Rules.IsTrusted(sender)
    return Rules.Get(sender) == "trust" or Rules.IsOwn(sender)
end

-- Bei „Alle öffnen“ und beim Einsammeln auslassen? („return“ geht ohnehin zurück.)
function Rules.IsBlocked(sender)
    local rule = Rules.Get(sender)
    return rule == "skip" or rule == "return"
end

-- rule = nil entfernt die Regel. Rückgabe: Anzeigename (nil bei ungültigem Namen).
function Rules.Set(sender, rule, silent)
    local key, name = Rules.Key(sender)
    if not key then return nil end
    local store = Store()
    if rule then
        store[key] = { name = name, rule = rule }
    else
        store[key] = nil
    end
    if not silent then
        ns.Print(rule and L.RULE_SET:format(name, L["RULE_" .. rule]) or L.RULE_CLEARED:format(name))
    end
    ns.Fire("RULES_CHANGED")
    return name
end

-- Alle Regeln, nach Name sortiert: { { key, name, rule } }
function Rules.List()
    local list = {}
    for key, entry in pairs(Store()) do
        if type(entry) == "table" and entry.rule then
            list[#list + 1] = { key = key, name = entry.name or key, rule = entry.rule }
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

function Rules.Count()
    return #Rules.List()
end

-- Text der Regel für Tooltips (nil ohne Regel); eigene Charaktere als „vertraut (eigener Charakter)“.
function Rules.Describe(sender)
    local rule = Rules.Get(sender)
    if rule then return L["RULE_" .. rule] end
    if Rules.IsOwn(sender) then return L.RULE_OWN end
    return nil
end

---------------------------------------------------------------------------
-- Menüs: Regel eines Absenders wählen (Brief-Menü) und alle Regeln verwalten („Alle öffnen“)
---------------------------------------------------------------------------

-- Untermenü mit Radioknöpfen „keine Regel / vertraut / auslassen / zurückschicken“.
function Rules.AddChoices(parent, sender)
    local function Get() return Rules.Get(sender) end
    local function Set(rule) Rules.Set(sender, rule) end
    Menu.Radio(parent, L.RULE_NONE, Get, Set, nil)
    for _, rule in ipairs(Rules.KINDS) do Menu.Radio(parent, L["RULE_" .. rule], Get, Set, rule) end
end

-- Eintrag „Absender: Name“ für das Menü am offenen Brief.
function Rules.AddSenderMenu(root, sender)
    local _, name = Rules.Key(sender)
    if not name then return end
    local sub = Menu.Button(root, L.RULE_MENU_SENDER:format(name))
    Rules.AddChoices(sub, sender)
end

-- Untermenü „Absender-Regeln (n)“ im Pfeil-Menü neben „Alle öffnen“.
function Rules.AddManageMenu(root)
    local list = Rules.List()
    local sub = Menu.Button(root, L.RULE_MENU_ALL:format(#list))
    if #list == 0 then
        Menu.Title(sub, L.RULE_EMPTY)
        return
    end
    if sub.SetScrollMode and #list > 20 then sub:SetScrollMode(20 * 20) end
    for _, entry in ipairs(list) do
        local item = Menu.Button(sub, L.RULE_LINE:format(entry.name, L["RULE_" .. entry.rule]))
        Rules.AddChoices(item, entry.name)
    end
end

---------------------------------------------------------------------------
-- Gesperrte Absender: zurückschicken beim Öffnen des Briefkastens
---------------------------------------------------------------------------

-- Briefe von Absendern mit Regel „zurückschicken“, die zurückgehen können (absteigend sortiert).
function Rules.ReturnTargets()
    local list = {}
    for index = 1, (ns.NumMails()) do
        local h = ns.Header(index)
        if h and not h.gm and Rules.Get(h.sender) == "return" and not InboxItemCanDelete(index) then
            list[#list + 1] = { index = index, sig = ns.Signature(h) }
        end
    end
    table.sort(list, function(a, b) return a.index > b.index end)
    return list
end

---------------------------------------------------------------------------
-- Slash: /ezm regel Name vertraut|auslassen|zurueck|weg, /ezm regeln
---------------------------------------------------------------------------

local WORDS = {
    vertraut = "trust", vertrauen = "trust", trust = "trust",
    auslassen = "skip", sperren = "skip", skip = "skip", block = "skip",
    zurueck = "return", ["zurück"] = "return", ["return"] = "return",
    weg = false, keine = false, none = false, clear = false,
}

function Rules.Slash(rest)
    rest = ezCore.Trim(rest or "")
    local name, word = rest:match("^(.-)%s+(%S+)$")
    local rule = word and WORDS[word:lower()]
    if not name or name == "" or rule == nil then
        ns.Print(ns.CmdText(L.RULE_USAGE))
        return
    end
    if not Rules.Set(name, rule or nil) then ns.Print(ns.CmdText(L.RULE_USAGE)) end
end

function Rules.PrintList()
    local list = Rules.List()
    if #list == 0 then return ns.Print(L.RULE_EMPTY) end
    ns.Print(L.RULE_LIST_HEADER)
    for _, entry in ipairs(list) do ns.Print("  " .. L.RULE_LINE:format(entry.name, L["RULE_" .. entry.rule])) end
end
