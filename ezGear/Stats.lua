local _, ns = ...
local Core = ezCore

--[[
    Werte eines Gegenstands – keine festen Tabellen je Gegenstand (Forever hat die Werte überarbeitet), sondern das,
    was das Spiel liefert. Gelesen wird nur noch ezCores Item-Wissen (Knowledge.Get(link).stats): dort stehen alle Werte
    aus C_Item.GetItemStats (Schlüssel über Knowledge.StatKey, eine Liste für alle Module) und die, die nur im Tooltip
    stehen („Anlegen: Erhöht Eure Chance auf einen kritischen Treffer um 1 %“).

    Schlüssel: STAMINA STRENGTH AGILITY INTELLECT SPIRIT MP5 HP5 AP RAP SPELL HEAL HIT CRIT SPELLHIT SPELLCRIT HASTE
    EXPERTISE ARMORPEN SPELLPEN MASTERY VERSATILITY DEFENSE DODGE PARRY BLOCK BLOCKVALUE ARMOR MELEEDPS RANGEDDPS
    und die Widerstände (…RES). Waffenschaden zählt getrennt als Nahkampf (MELEEDPS) oder Distanz (RANGEDDPS), wie bei
    Pawn – das entscheidet ezCore nach dem Platz.
]]

local Stats = {}
ns.Stats = Stats

-- Reihenfolge für Anzeigen (Status, Gewichtung)
Stats.ORDER = {
    "STRENGTH", "AGILITY", "STAMINA", "INTELLECT", "SPIRIT", "AP", "RAP", "SPELL", "HEAL", "HIT", "CRIT",
    "SPELLHIT", "SPELLCRIT", "HASTE", "EXPERTISE", "ARMORPEN", "SPELLPEN", "MASTERY", "VERSATILITY", "MP5", "HP5",
    "DEFENSE", "DODGE", "PARRY", "BLOCK", "BLOCKVALUE", "ARMOR", "MELEEDPS", "RANGEDDPS",
    "FIRERES", "FROSTRES", "NATURERES", "SHADOWRES", "ARCANERES", "HOLYRES",
}

local function Knowledge(link)
    local K = Core.Knowledge
    if not (K and K.Get) then return nil end
    return K.Get(link)
end
Stats.Facts = Knowledge

-- Ausrüstungsplatz (equipLoc) eines Gegenstands, auch wenn das Item-Wissen ihn noch nicht kennt.
function Stats.EquipLoc(link, facts)
    if facts and facts.equipLoc then return facts.equipLoc end
    local _, _, loc = Core.ItemClass(link)     -- ezCore liest GetItemInfoInstant (gesperrt oder leer → nil; V-177)
    return loc
end

--[[
    Stats.Read(link) → stats, facts
      stats: { STAMINA = 12, MELEEDPS = 21.5, … } (eigene Kopie) oder nil, solange die Daten noch nicht geladen sind
      facts: Eintrag aus dem Item-Wissen
]]
function Stats.Read(link)
    if type(link) ~= "string" or ns.IsSecret(link) then return nil end
    -- Erst wenn das Spiel den Gegenstand kennt (GetItemInfo fragt sonst beim Server nach → GET_ITEM_INFO_RECEIVED).
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local itemName = ns.Plain(ns.Call(info, link))
    if type(itemName) ~= "string" then return nil end
    local facts = Knowledge(link)
    if type(facts) ~= "table" then return nil end
    local out = {}
    if type(facts.stats) == "table" then
        for key, value in pairs(facts.stats) do
            value = ns.Num(value)
            if value and value ~= 0 then out[key] = value end
        end
    end
    return out, facts
end

-- Händlerpreis (Kupfer je Stück): ezCore.VendorPrice (Item-Wissen, sonst Client)
function Stats.SellPrice(link)
    return ns.Num(ns.Call(Core.VendorPrice, link))
end

-- Qualität aus dem Item-Wissen (dort einmal aus GetItemInfo gelesen)
function Stats.Quality(link)
    if ns.IsSecret(link) or link == nil then return nil end
    local facts = Knowledge(link)
    return type(facts) == "table" and ns.Num(facts.quality) or nil
end

-- Anzeigename eines Werts: aus dem Item-Wissen (Blizzards Texte), sonst ezGears eigener Text.
function Stats.Name(key)
    local K = Core.Knowledge
    local L = ns.L
    local own = rawget(L, "STAT_" .. key) or L["STAT_" .. key]
    if own and own ~= "STAT_" .. key then return own end
    if K and K.StatName then
        local name = K.StatName(key)
        if name and name ~= key then return name end
    end
    return key
end
