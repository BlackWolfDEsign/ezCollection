local _, ns = ...
local L = ns.L
local Core = ezCore
local Buffs = ns.Buffs

--[[
    Aktionsknöpfe leuchten: Fehlt einer deiner Klassen-Buffs (auf dir oder in der Gruppe), leuchten alle
    Aktionsknöpfe dieses Buffs in ezCores Art „missing“ – in jedem Rang und auch als Gruppenfassung
    (Spieltest 13.11.2026: „nur der entsprechende lvl1 buff blinkt, nicht der lvl2 oder 3 oder höchste“).
    Bei Segen und Rüstungen leuchten alle der Wahl, denn jeder genügt.

    Gemeldet wird beim Leucht-Dienst von ezCore (EC-59, BF-14): Core.Glow.Set("ezBuff", "missing", { spell = ids,
    kind = "missing", tip = Tip }). Der Dienst sucht die Plätze (nach Namen verglichen, jeder Rang, auch Makros und
    andere Leistenseiten), folgt neuen und geleerten Knöpfen selbst und startet bei gleichem Grund nichts neu.
    Rangfolge der Arten: „fehlt“ (missing) geht vor ezMacros „neuerer Rang“ (rank) – auf einem Platz mit veraltetem
    Rang gewinnt „fehlt“ (so gewollt); dieselbe Meldung von ezCombat fällt mit dieser zusammen.
    Im Kampf und wenn nichts mehr fehlt: Core.Glow.Clear. Schalter: missingGlow.
    Vorher suchte ezBuff die Plätze selbst (ActionHighlight.SlotsFor/ShowSlots/ClearSlots), merkte sie in „shown“
    und hörte auf ACTIONBAR_SLOT_CHANGED – das macht jetzt der Dienst.
]]

local Glow = {}
ns.ActionGlow = Glow

Glow.KEY = "ezBuff.missing"                   -- frühere Kennung (ActionHighlight); bleibt als Name des Grundes
Glow.OWNER, Glow.REASON = "ezBuff", "missing" -- Grund beim Leucht-Dienst (Core.Glow)
local KINDS = { self = true, group = true }   -- eigene Klassen-Buffs (Checks.lua)

local function Highlight() return Core.ActionHighlight end

-- Zauber-IDs aller Ränge und Gruppenfassungen der fehlenden eigenen Klassen-Buffs.
function Glow.SpellIDs(tasks)
    local ids, seen = {}, {}
    local function AddList(list)
        for _, id in ipairs(type(list) == "table" and list or {}) do
            if type(id) == "number" and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    for _, task in ipairs(tasks or {}) do
        if KINDS[task.kind] then
            for _, key in ipairs(task.buffKeys or {}) do
                local info = Buffs.Info(key)
                if info then
                    AddList(info.spells)
                    AddList(info.group)
                end
            end
        end
    end
    return ids
end

-- Tooltip-Zeile am Aktionsknopf (ezCore setzt davor die Bedeutung der Farbe).
local function Tip(slot)
    local hl = Highlight()
    local name = hl and Core.Call(hl.SlotSpellName, slot)
    return L.GLOW_TIP:format(name or "?")
end
Glow.Tip = Tip

-- Abmelden. → true, wenn ein Grund lag.
function Glow.Clear()
    return Core.Glow.Clear(Glow.OWNER, Glow.REASON) > 0
end

-- Grund neu melden; Rückgabe: Anzahl gemeldeter Zauber-IDs (0 = nichts leuchtet). Ein gleicher Grund startet beim
-- Dienst nichts neu – das Pulsieren läuft weiter.
function Glow.Update()
    if ns.InCombat() or not ns.Enabled("missingGlow") then
        Glow.Clear()
        return 0
    end
    local ids = Glow.SpellIDs(ns.Check and ns.Check.Tasks())
    if #ids == 0 or not Core.Glow.Set(Glow.OWNER, Glow.REASON, { spell = ids, kind = "missing", tip = Tip }) then
        Glow.Clear()
        return 0
    end
    return #ids
end

-- Was gerade gemeldet ist: die Zaubernamen des Grundes als Text („Arkane Brillanz,Arkane Intelligenz“), sonst nil.
-- Liest beim Dienst nach (kein eigener Merker mehr).
function Glow.Shown()
    for _, reason in ipairs(Core.Glow.List()) do
        if reason.owner == Glow.OWNER and reason.key == Glow.REASON then
            return reason.names and table.concat(reason.names, ",") or ""
        end
    end
    return nil
end

ns.OnReady(function()
    ns.Listen("TASKS", Glow.Update)
    ns.On("PLAYER_REGEN_DISABLED", Glow.Clear)
    ns.OnSettingChanged(function() Glow.Update() end)
end)
