local ADDON, ns = ...
local Core = ezCore
local L = ns.L
local Traits = ns.Traits
local Templates = ns.Templates

--[[
    Übersicht über die eigenen Charaktere (Punkt 9).

    Die Charakterliste ist ezCores (Core.CharacterList: Name, Klasse, Stufe; Berufe über Core.Professions.Of) – keine
    zweite Liste. ezTalent merkt je Twink nur, was ezCore nicht erfasst, unter ezTalentDB.chars[charKey]:
      { groups = { 12, 31, 8 }, primary = 2, template = "Name", legacy = { [treeID] = ausgegeben },
        legacyTemplate = { [treeID] = "Name" }, applied = { [scope] = "Name" }, t = Zeitpunkt }
    Gesichert beim Ausloggen und gebündelt nach jeder bestätigten Änderung. Ein vergessener Twink (CHAR_FORGOTTEN)
    verschwindet auch hier (Core.lua).
]]

local Roster = {}
ns.Roster = Roster

local function Record(create)
    local key = ns.charKey or Core.charKey
    if not (ns.db and key) then return nil end
    local c = ns.db.chars[key]
    if type(c) ~= "table" then
        if not create then return nil end
        c = {}
        ns.db.chars[key] = c
    end
    return c
end

-- Stand dieses Charakters merken (nur Bestätigtes, nie die Vorschau).
function Roster.Save()
    local c = Record(true)
    if not c then return false end
    local configID = Traits.ClassConfigID()
    local treeID = Traits.TreeOfConfig(configID)
    if configID and treeID then
        local groups = Traits.Groups(configID, treeID)
        c.groups = {}
        for i, g in ipairs(groups) do c.groups[i] = g.spent end
        c.primary = Traits.PrimaryTree(groups)
        local scope, snap = Templates.ClassScope(), Traits.Snapshot(configID, treeID, true)
        local applied = type(c.applied) == "table" and c.applied[scope]
        -- zuerst die zuletzt angewandte Vorlage, wenn sie noch passt; sonst die erste gleiche
        if applied and Templates.Same(Templates.Get(scope, applied), snap) then c.template = applied
        else c.template = Templates.Match(scope, snap) end
    end
    c.legacy, c.legacyTemplate = {}, {}
    for _, tree in ipairs(Traits.LegacyTrees()) do
        local legacyConfig = Traits.LegacyConfigID(tree.treeID)
        local _, spent = Traits.Currency(legacyConfig, tree.treeID)
        if spent then c.legacy[tree.treeID] = spent end
        if legacyConfig then
            c.legacyTemplate[tree.treeID] = Templates.Match(Templates.LegacyScope(tree.treeID),
                Traits.Snapshot(legacyConfig, tree.treeID, true))
        end
    end
    c.t = time and time() or 0
    return true
end

-- Zeilen der Übersicht: { { key, isMe, name, class, level, profs, talents, template, legacy } }
function Roster.List()
    local list = {}
    local mine = ns.db and ns.db.chars or {}
    for _, entry in ipairs(Core.CharacterList()) do
        local c, t = entry.c, mine[entry.key]
        t = type(t) == "table" and t or {}
        local profs = {}
        local known = Core.Professions and Core.Professions.Of and Core.Professions.Of(entry.key)
        for _, p in ipairs(type(known) == "table" and known or {}) do
            if p.name and p.primary ~= false then profs[#profs + 1] = p.name .. (p.rank and (" " .. p.rank) or "") end
        end
        local legacy = {}
        for _, tree in ipairs(Traits.LegacyTrees()) do
            local spent = t.legacy and t.legacy[tree.treeID]
            if spent then
                local name = t.legacyTemplate and t.legacyTemplate[tree.treeID]
                legacy[#legacy + 1] = L["LEGACY_TREE_" .. tree.key] .. " " .. spent .. (name and (" (" .. name .. ")") or "")
            end
        end
        local scope = c.class and Templates.ClassScope(c.class)
        list[#list + 1] = {
            key = entry.key, isMe = entry.isMe, name = Core.CharName(c, entry.key, nil, true), class = c.class,
            level = c.level, profs = profs,
            talents = type(t.groups) == "table" and #t.groups > 0 and table.concat(t.groups, " / ") or nil,
            template = t.template or (t.applied and scope and t.applied[scope]) or nil,
            legacy = legacy,
        }
    end
    return list
end

-- Kopf einer Zeile: „Stufe 60 Krieger“.
function Roster.Head(row)
    return L.ROSTER_LEVEL:format(row.level or "?") .. " "
        .. (Core.ClassName and row.class and Core.ClassName(row.class) or row.class or "?")
end

-- Einzelheiten eines Twinks als Zeilen (Talente samt Vorlage, Berufe, Vermächtnis) – für Text und Seitenteil.
function Roster.Details(row)
    return {
        L.ROSTER_TALENTS .. ": " .. (row.talents or L.ROSTER_UNKNOWN)
            .. (row.template and (" – " .. L.ROSTER_TEMPLATE:format(row.template)) or ""),
        L.ROSTER_PROFS .. ": " .. (#row.profs > 0 and table.concat(row.profs, ", ") or L.ROSTER_NONE),
        L.ROSTER_LEGACY .. ": " .. (#row.legacy > 0 and table.concat(row.legacy, ", ") or L.ROSTER_UNKNOWN),
    }
end

-- Mehrzeiliger Text der Übersicht (für den Dialog und den Chat).
function Roster.Text()
    local lines = {}
    for _, row in ipairs(Roster.List()) do
        lines[#lines + 1] = row.name .. " – " .. Roster.Head(row)
        for _, detail in ipairs(Roster.Details(row)) do lines[#lines + 1] = "   " .. detail end
    end
    if #lines == 0 then lines[1] = L.ROSTER_EMPTY end
    return table.concat(lines, "\n")
end

-- Sichtbarer Weg: Reiter „Twinks“ am Talentfenster, Knopf auf der Einstellungsseite und im Seitenteil „Vorlagen“
-- (/eztalent twinks zusätzlich). Öffnet das Seitenteil „Twinks“ am Talentfenster (TL-12); geht das nicht (Reiter
-- abgeschaltet, Fenster lässt sich nicht öffnen, Kampf), wie bisher als Text.
function Roster.Show()
    Roster.Save()
    local UI = ns.UI
    if UI and UI.ShowRoster and UI.ShowRoster() then return true end
    return Roster.ShowText()
end

-- Die Übersicht als Text zum Kopieren (Knopf „Als Text zeigen“ im Seitenteil; Rückfall von Roster.Show).
function Roster.ShowText()
    if Core.TextDialog then
        Core.TextDialog({ title = L.ROSTER_TITLE, hint = L.ROSTER_HINT, text = Roster.Text(), readOnly = true, owner = ADDON })
    else
        for line in Roster.Text():gmatch("[^\n]+") do ns.Print(line) end
    end
    return true
end

local saveSoon = ns.Throttle and ns.Throttle(function() Roster.Save() end, 2) or function() Roster.Save() end

ns.OnReady(function()
    ns.OnLogout(function() Roster.Save() end)
    ns.On("TRAIT_CONFIG_UPDATED", function() saveSoon() end)
    ns.On("ACTIVE_COMBAT_CONFIG_CHANGED", function() saveSoon() end)
    saveSoon()
end)

ns.API.Roster = function()
    local out = {}
    for i, row in ipairs(Roster.List()) do
        out[i] = { key = row.key, talents = row.talents, template = row.template }
    end
    return out
end
