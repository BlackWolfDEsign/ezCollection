local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Meldungen auf ezPanels Leiste (Baustein „Meldungen“; Schnittstelle in ezPanel/API.lua, Entscheidung des Nutzers
    vom 14.11.2026 zu Frage 17 der Vollprüfung: „Ja, je Quelle abwählbar (Empfohlen)“).

    ezBuff meldet zwei Quellen an – jede lässt sich in ezPanels Menü „Quellen“ einzeln abwählen:
      ezBuff.missing   „Buffs auf dir“      Buff fehlt: <was> bzw. n Buffs fehlen (alles, was dir selbst fehlt)
      ezBuff.group     „Buffs der Gruppe“   Buff fehlt bei n Gruppenmitgliedern (dein Buff, Abschnitt „Gruppe“)
    Beide lesen nur die letzte Prüfung (Check.Tasks, Check.ByUnit) – nichts Teures, nichts Gesperrtes. Im Kampf und
    bei nicht lesbaren Auren melden sie nichts (nil). Nach jeder Prüfung (Nachricht EZBUFF_TASKS) und beim
    Kampfbeginn zeichnet ezPanel neu. Ob sie erscheinen, wählt man nur in ezPanels Menü „Quellen“ (Einstellungs-Prüfung
    19.11.2026, Nr. 76; bis dahin dazu der Schalter panelWarning). Läuft ezPanel nicht (oder eine alte Fassung ohne
    AddWarning), passiert nichts.
]]

local Panel = {}
ns.Panel = Panel

Panel.MISSING = "ezBuff.missing"
Panel.GROUP = "ezBuff.group"

-- ezPanels Schnittstelle; nil, wenn ezPanel nicht läuft oder die Fassung AddWarning nicht kennt.
function Panel.API()
    local api = Core.API and Core.API("ezPanel")
    if type(api) == "table" and type(api.AddWarning) == "function" then return api end
    return nil
end

-- Darf gerade gemeldet werden? Nicht im Kampf, Auren bei der letzten Prüfung lesbar.
local function Usable()
    return ns.S ~= nil and not ns.InCombat()
        and ns.Check ~= nil and ns.Check.Readable() == true
end

-- Quelle „Buffs auf dir“: alles, was dir selbst fehlt (eigene Buffs, Fläschchen, Essen, Lagerfeuer, Buffs anderer
-- Klassen). Nicht die Gruppe (eigene Quelle) und nicht „Buff zurückgeben“ (das fehlt nicht, es ist zu tun – solche
-- Aufgaben tragen auch kein Feld what, wie bei ns.PrintMissing; die Art wird trotzdem ausdrücklich ausgenommen).
function Panel.MissingText()
    if not Usable() then return nil end
    local count, first = 0, nil
    for _, task in ipairs(ns.Check.Tasks()) do
        if task.kind ~= "group" and task.kind ~= "rebuff" and type(task.what) == "string" then
            count = count + 1
            first = first or task.what
        end
    end
    if count == 0 then return nil end
    if count == 1 then return L.PANEL_MISSING_ONE:format(first) end
    return L.PANEL_MISSING_MANY:format(count)
end

-- Wie vielen Gruppenmitgliedern fehlt ein Buff von dir (oder läuft aus)? Aus der Zahl, die der Abschnitt „Gruppe“
-- führt (Check.ByUnit – gefüllt, wenn „Eigene Buffs auf der Gruppe“ oder das Symbol am Gruppenrahmen an ist);
-- auch Mitglieder außer Reichweite zählen, du selbst nicht.
function Panel.GroupCount()
    local count = 0
    for unit, member in pairs(ns.Check and ns.Check.ByUnit() or {}) do
        if unit ~= "player" and type(member) == "table" and type(member.needs) == "table" and #member.needs > 0 then
            count = count + 1
        end
    end
    return count
end

-- Quelle „Buffs der Gruppe“.
function Panel.GroupText()
    if not Usable() then return nil end
    local count = Panel.GroupCount()
    if count == 0 then return nil end
    if count == 1 then return L.PANEL_GROUP_ONE end
    return L.PANEL_GROUP_MANY:format(count)
end

local registered = false
function Panel.Registered() return registered end

-- Quellen anmelden, sobald ezPanel läuft (abwählen nur in ezPanels Menü „Quellen“). → true, wenn sie dort stehen.
function Panel.Sync()
    local api = Panel.API()
    if not api then
        registered = false
        return false
    end
    local want = ns.S ~= nil
    if want and not registered then
        local okMissing = Core.Call(api.AddWarning, Panel.MISSING, L.PANEL_SOURCE_MISSING, Panel.MissingText)
        local okGroup = Core.Call(api.AddWarning, Panel.GROUP, L.PANEL_SOURCE_GROUP, Panel.GroupText)
        registered = okMissing == true and okGroup == true
    elseif not want and registered then
        Core.Call(api.RemoveWarning, Panel.MISSING)
        Core.Call(api.RemoveWarning, Panel.GROUP)
        registered = false
    end
    return registered
end

-- ezPanel neu zeichnen lassen (nach einer Prüfung, beim Kampfbeginn).
function Panel.Refresh()
    if not registered then return end
    local api = Panel.API()
    if api then Core.Call(api.RefreshWarnings) end
end

-- Zeile für /ezbuff status; nil ohne ezPanel.
function Panel.StatusLine()
    if not Panel.API() then return nil end
    return registered and L.STATUS_PANEL or L.STATUS_PANEL_OFF
end

ns.OnReady(function()
    Panel.Sync()
    Core.Listen("EZBUFF_TASKS", Panel.Refresh, ADDON)
    ns.On("PLAYER_REGEN_DISABLED", Panel.Refresh)
    ns.OnSettingChanged(function()
        Panel.Sync()
        Panel.Refresh()
    end)
end)
