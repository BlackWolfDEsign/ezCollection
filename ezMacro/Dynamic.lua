local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Vorlagen, deren Text erst beim Übernehmen entsteht (Platzhalter in ns.Resolve, Welle 2b; eigene Texte):
      {r:opener}  Eröffnung der gewählten Rotation aus ezCombat (ezCore.API("ezCombat").Sections, Abschnitt
                  „opener“): die gelernten, eingeschalteten Schritte als
                  „/castsequence [nochanneling] reset=target A, B, C“; wer einen Zauberstab angelegt hat (Fernkampf-
                  platz, ezCore.WeaponKind) und Schießen kennt, bekommt Schießen ans Ende. [nochanneling]: ein Druck während eines kanalisierten Zaubers bricht
                  ihn nicht ab. Die Folge kommt aus ezCombat, ezMacro führt keine eigene Liste.
      {g:shield}  Waffe und Schild für den Notfall: „/equipslot 16 Einhandwaffe“ und „/equipslot 17 Schild“ mit den
                  Namen vom Client – zuerst aus einem Ausrüstungsset von ezGear, das beides belegt
                  (ezCore.API("ezGear").Sets/SetItems), sonst das Angelegte, sonst aus den Taschen (die beste nach
                  ezGear, sonst die erste gefundene).
      {i:…}       bester Gegenstand bzw. Reittier einer Art für die Ein-Klick-Makros – melden sich aus OneClick.lua
                  über Dynamic.Register an.
    Fehlt die Grundlage (ezCombat nicht geladen, Rotation ohne Eröffnung, kein Schild oder keine Einhandwaffe),
    liefert der Platzhalter nil und ns.Resolve lässt die Zeile weg; Dynamic.Note nennt den Grund im Browser.
]]
local Dynamic = {}
ns.Dynamic = Dynamic

local WAND = 5019                -- Schießen (Zauberstab), Rang-1-ID wie in ezCombats Rotationen
local OPENER_PREFIX = "/castsequence [nochanneling] reset=target "
local OPENER_MAX = 200           -- Zeichen der Zeile; der Rest des Makros bleibt unter 255

-- Gelernte Zauber der Eröffnung → Liste der IDs | nil, Grund ("noCombat" | "noOpener").
function Dynamic.OpenerSpells()
    local api = Core.API and Core.API("ezCombat")
    if type(api) ~= "table" or type(api.Sections) ~= "function" then return nil, "noCombat" end
    local ok, sections = pcall(api.Sections)
    if not ok or type(sections) ~= "table" then return nil, "noCombat" end
    local ids = {}
    for _, section in ipairs(sections) do
        if type(section) == "table" and section.key == "opener" and type(section.steps) == "table" then
            for _, step in ipairs(section.steps) do
                local id = type(step) == "table" and tonumber(step.id)
                if id and step.enabled ~= false and ns.IsSpellKnown(id) then ids[#ids + 1] = id end
            end
        end
    end
    if #ids == 0 then return nil, "noOpener" end
    return ids
end

-- Liegt ein Zauberstab im Fernkampfplatz? (ezCore.WeaponKind, geprüft über ns.CORE_NEEDS; geheim oder unbekannt
-- zählt als nein)
function Dynamic.WandEquipped()
    local kind = Core.WeaponKind("ranged")
    if Core.IsSecret(kind) then return false end
    return kind == "wand"
end

-- Zeile „/castsequence …“ der Eröffnung | nil, Grund.
function Dynamic.OpenerLine()
    local ids, why = Dynamic.OpenerSpells()
    if not ids then return nil, why end
    local names, hasWand = {}, false
    local function add(id)
        local name = ns.SpellName(id)
        if type(name) == "string" and name ~= "" then names[#names + 1] = name end
    end
    for _, id in ipairs(ids) do
        add(id)
        if id == WAND then hasWand = true end
    end
    if not hasWand and ns.IsSpellKnown(WAND) and Dynamic.WandEquipped() then add(WAND) end
    while #names > 1 and #(OPENER_PREFIX .. table.concat(names, ", ")) > OPENER_MAX do table.remove(names) end
    if #names == 0 then return nil, "noOpener" end
    return OPENER_PREFIX .. table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- Waffe und Schild
---------------------------------------------------------------------------

local ONEHAND = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
local SHIELD = { INVTYPE_SHIELD = true }
local MAINHAND, OFFHAND = 16, 17

local Plain = Core.Plain   -- Wert nur, wenn er nicht geheim ist (ezCore, Leitlinie 2)

local function Fits(item, locs)
    local _, _, equipLoc = Core.ItemClass(item)
    return equipLoc ~= nil and locs[equipLoc] == true
end

local function NameOf(link, itemID)
    return Core.ItemName(link) or (itemID and Core.ItemNameByID(itemID)) or nil
end

-- Name des besten Gegenstands für einen Platz: angelegt (passt er), sonst aus den Taschen.
local function BestFor(slot, locs)
    local equipped = Plain(GetInventoryItemLink and GetInventoryItemLink("player", slot))
    if type(equipped) == "string" and Fits(equipped, locs) then return NameOf(equipped) end
    local found = {}
    Core.ForEachBagItem(function(_, _, info)
        local link = Plain(info.hyperlink)
        local item = link or info.itemID
        if item and Fits(item, locs) then found[#found + 1] = { link = link, id = info.itemID } end
    end)
    if #found == 0 then return nil end
    local best, bestScore = found[1], nil
    local gear = Core.API and Core.API("ezGear")
    if type(gear) == "table" and type(gear.Score) == "function" then
        for _, candidate in ipairs(found) do
            local score = candidate.link and tonumber(Core.Call(gear.Score, candidate.link))
            if score and (bestScore == nil or score > bestScore) then best, bestScore = candidate, score end
        end
    end
    return NameOf(best.link, best.id)
end

-- Besitzt der Spieler den Gegenstand gerade? Angelegt in Platz 16 oder 17, sonst in den Taschen (Core.ItemCount).
-- Ein Set nennt nur Nummern (C_EquipmentSet.GetItemIDs) – auch von längst verkauften Gegenständen.
local function Owned(itemID)
    for _, slot in ipairs({ MAINHAND, OFFHAND }) do
        if tonumber(Plain(GetInventoryItemID and GetInventoryItemID("player", slot))) == itemID then return true end
    end
    return Core.ItemCount(itemID) > 0
end

-- Einhandwaffe und Schild aus einem Ausrüstungsset von ezGear (MACRO-25): das erste Set (nach Namen, wie
-- ezCore.API("ezGear").Sets sie liefert), das im Platz 16 eine Einhandwaffe und im Platz 17 einen Schild belegt
-- (SetItems) und dessen beide Gegenstände der Spieler noch hat (angelegt oder in den Taschen). → Waffe, Schild (Namen
-- vom Client), Name des Sets | nil (ohne ezGear, ohne passendes Set oder solange der Client die Namen noch nicht kennt).
function Dynamic.ShieldFromSet()
    local gear = Core.API and Core.API("ezGear")
    if type(gear) ~= "table" or type(gear.Sets) ~= "function" or type(gear.SetItems) ~= "function" then return nil end
    local sets = Core.Call(gear.Sets)
    if type(sets) ~= "table" then return nil end
    for _, set in ipairs(sets) do
        local name = type(set) == "table" and Plain(set.name)
        local items = type(name) == "string" and Core.Call(gear.SetItems, set.id or name)
        if type(items) == "table" then
            local weaponID, shieldID = tonumber(Plain(items[MAINHAND])), tonumber(Plain(items[OFFHAND]))
            if weaponID and shieldID and Fits(weaponID, ONEHAND) and Fits(shieldID, SHIELD) and Owned(weaponID)
                and Owned(shieldID) then
                local weapon, shield = NameOf(nil, weaponID), NameOf(nil, shieldID)
                if weapon and shield then return weapon, shield, name end
            end
        end
    end
    return nil
end

-- Zwei Zeilen „/equipslot 16 …“ und „/equipslot 17 …“ | nil, Grund ("noWeapon" | "noShield"). Zuerst aus einem
-- ezGear-Set mit Einhandwaffe und Schild, sonst das Angelegte bzw. das Beste aus den Taschen.
function Dynamic.ShieldLines()
    local weapon, shield = Dynamic.ShieldFromSet()
    if not weapon then
        weapon = BestFor(MAINHAND, ONEHAND)
        if not weapon then return nil, "noWeapon" end
        shield = BestFor(OFFHAND, SHIELD)
        if not shield then return nil, "noShield" end
    end
    return ("/equipslot %d %s\n/equipslot %d %s"):format(MAINHAND, weapon, OFFHAND, shield)
end

---------------------------------------------------------------------------
-- Für ns.Resolve, ns.IsEntryKnown und den Browser
---------------------------------------------------------------------------

local BUILDERS = { opener = Dynamic.OpenerLine, shield = Dynamic.ShieldLines }

-- Weitere Platzhalter melden sich hier an (OneClick.lua: {i:food}, {i:drink} … für die Ein-Klick-Makros).
-- build() → Text | nil, Grund (der Grund wird zum Hinweis L["DYN_" .. grund]).
function Dynamic.Register(arg, build)
    if type(arg) == "string" and type(build) == "function" then BUILDERS[arg] = build end
end

-- Text eines Platzhalters {r:opener}, {g:shield} bzw. {i:…} | nil, Grund.
function Dynamic.Line(_, arg)
    local build = BUILDERS[arg]
    if not build then return nil, "unknown" end
    return build()
end

-- Lässt sich der Text bauen? (entry.needs)
function Dynamic.Ready(arg)
    return Dynamic.Line(nil, arg) ~= nil
end

-- Hinweise zu einer Vorlage: je Platzhalter, der gerade nichts liefert, ein Satz (Grund).
function Dynamic.Notes(template)
    local notes = {}
    for _, arg in (template or ""):gmatch("{([rgi]):([^}]+)}") do
        local line, why = Dynamic.Line(nil, arg)
        if not line and why then notes[#notes + 1] = L["DYN_" .. why] end
    end
    return notes
end
