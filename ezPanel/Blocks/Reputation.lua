local _, ns = ...
local L = ns.L

--[[
    Ruf (Titan Reputations): beobachtete oder zuletzt geänderte Fraktion,
    Gewinne dieser Sitzung, Liste aller Fraktionen.
    Verbesserungen: Einmal gesehene Fraktionen merkt sich ezCore je Charakter (Core.Factions.Known)
    und ezPanel liest sie über ihre ID – sie bleiben im Tooltip, auch wenn ihre Überschrift im
    Ruf-Fenster später eingeklappt wird. Die Liste im Ruf-Fenster wird dafür nie verändert.
    Kein OnUpdate, Sitzung übersteht /reload (ezCores Sitzung).
]]

local block = ns.RegisterBlock({
    id = "reputation",
    command = "ruf",
    name = L.REP_NAME,
    label = L.REP_LABEL,
    icon = "Interface\\Icons\\Achievement_Reputation_01",
    fallbackIcon = "Interface\\Icons\\INV_Misc_Note_02",
    events = { "UPDATE_FACTION" },
    colorable = true,
    defaults = {
        enabled = false, zone = "left", order = 70,
        mode = "watched",     -- watched | last
        format = "both",      -- values | percent | both
        showName = true,
        sessionOnBar = true,
        listAll = true,
        hideMax = false,
        hideLow = false,
    },
    hints = { L.REP_HINT_LEFT },
})

---------------------------------------------------------------------------
-- Fraktionen lesen (moderne API mit Rückfall auf die alte)
---------------------------------------------------------------------------

local R = C_Reputation or {}
local Factions = ezCore.Factions

local function Standing(reaction)
    local text = reaction and (GetText and GetText("FACTION_STANDING_LABEL" .. reaction, UnitSex("player")) or _G["FACTION_STANDING_LABEL" .. reaction])
    return text or "?"
end

local function ReactionColor(reaction)
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if not c then return ns.WHITE end
    return ezCore.ColorCode(c.r, c.g, c.b)   -- Blizzards Farbe der Stufe, Farbcode über ezCore (Design-System 2.5)
end

-- Den Ruf liest ezCore (Core.Factions, W-12, PANEL-02): ein Datensatz { id, name, reaction, min, max, value, isHeader,
-- hasRep, watched, friendText, maxed, secret } für alle Module, moderne API mit Rückfall auf die alte, gesperrte
-- Werte zuerst geprüft (Leitlinie 6). ezPanel zeigt nur Fraktionen mit lesbaren Zahlen: gesperrte (secret) oder
-- fehlende Zahlen lassen die Zeile weg, gerechnet wird damit nie.
local function Usable(f)
    if type(f) ~= "table" or f.secret then return nil end
    if not (ns.Num(f.min) and ns.Num(f.max) and ns.Num(f.value)) then return nil end
    return f
end

local function ByID(id)
    return Usable(Factions.Info(id))
end

local function Watched()
    return Usable(Factions.Watched())
end

---------------------------------------------------------------------------
-- Bekannte Fraktionen und Sitzungsgewinne
---------------------------------------------------------------------------

--[[
    Die bekannten Fraktionen (Namen und Kopfzeilen) merkt ezCore je Charakter (Frage 12, 14.11.2026: „Je Charakter in
    ezCore“): Core.Factions.Known(), gefüllt bei UPDATE_FACTION und beim Anmelden (Factions.Remember), einmal aus
    ezPanels früherer Liste übernommen (Factions.MigrateKnown liest block.cfg.known aus ezPanelDB; ezPanel lässt
    diese alte Liste deshalb liegen und schreibt sie nicht mehr). Die Auswahl „welche zeige ich“ (Beobachten, Auf der
    Leiste, Tooltip-Filter) bleibt im Profil. Ein Profilwechsel ändert die Liste nicht (V-075 entfällt damit).
    Die zuletzt geänderte Fraktion erkennt und merkt ezCore (Core.Factions.Scan, Core.LastFaction, Nachricht
    FACTION_CHANGED). Die Gewinne der Sitzung zählt ezPanel in seiner Tabelle der Sitzung (ns.session.rep).
]]
local EMPTY = {}

local function Known()
    return Factions.Known() or EMPTY
end

local function Scan()
    if not ns.ready or not ns.session then return end   -- frühe Events vor dem Login
    Factions.Remember()   -- dieselbe Liste, die ezCore sonst erst eine Sekunde später füllt
    local s = ns.session
    s.rep = s.rep or {}
    s.repStart = s.repStart or {}
    for id in pairs(Known()) do
        local f = ByID(id)
        if f then
            if s.repStart[id] == nil then s.repStart[id] = f.value end
            local gain = f.value - s.repStart[id]
            s.rep[id] = gain ~= 0 and gain or nil
        end
    end
end

-- Mehrere Ruf-Ereignisse kurz hintereinander: einmal je Sekunde neu lesen (ezCores Drossel ns.Throttle, Gesamtreview
-- 18.11.2026, T16-13 – vorher von Hand nachgebaut).
local ScheduleScan = ns.Throttle(function()
    Scan()
    ns.QueueUpdate(block)
end, 1)

ns.OnReady(function()
    C_Timer.After(2, Scan)
end)
ns.On("UPDATE_FACTION", ScheduleScan)
ns.On("CHAT_MSG_COMBAT_FACTION_CHANGE", ScheduleScan)
-- ezCore hat eine geänderte Fraktion erkannt: „zuletzt geändert“ auf der Leiste nachziehen.
ezCore.Listen("FACTION_CHANGED", function() ns.QueueUpdate(block) end, "ezPanel")
-- Neue Sitzung (Sitzung zurücksetzen): Startwerte des Rufs sofort neu merken.
ezCore.Listen("SESSION_RESET", function() Scan() end, "ezPanel")

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local function Current()
    local last = block.cfg.mode == "last" and ezCore.LastFaction()
    if last then
        local f = ByID(last)
        if f then return f end
    end
    return Watched()
end

local function ValueText(f, format)
    if f.maxed then return ReactionColor(f.reaction) .. (f.friendText or Standing(f.reaction)) .. "|r" end
    local cur, span = f.value - f.min, f.max - f.min
    local pct = span > 0 and cur / span * 100 or 100
    local text
    if format == "percent" then
        text = ezCore.Percent(pct)
    elseif format == "values" then
        text = ("%s/%s"):format(ns.Number(cur), ns.Number(span))
    else
        text = ("%s/%s (%s)"):format(ns.Number(cur), ns.Number(span), ezCore.Percent(pct))
    end
    return ReactionColor(f.reaction) .. text .. "|r"
end

function block:GetText()
    local cfg = self.cfg
    local f = Current()
    if not f then
        local locked = Factions.Watched()   -- beobachtet, aber die Zahlen sind gesperrt: Name mit Hinweis
        if locked and cfg.showName then return locked.name .. ": " .. ns.Grey(L.REP_LOCKED) end
        return ns.Grey(locked and L.REP_LOCKED or L.REP_NONE)
    end
    local text = ValueText(f, cfg.format)
    if cfg.showName then text = f.name .. ": " .. text end
    local gain = f.id and ns.session.rep and ns.session.rep[f.id]
    if cfg.sessionOnBar and gain then
        text = text .. (gain > 0 and (" " .. ns.GREEN .. "+") or (" " .. ns.RED)) .. ns.Number(gain) .. "|r"
    end
    return text
end

function block:OnTooltip(tooltip)
    local cfg = self.cfg
    local f = Current()
    if f then
        ns.TipLine(tooltip, f.name, "normal")
        tooltip:AddDoubleLine(L.REP_STANDING, ReactionColor(f.reaction) .. (f.friendText or Standing(f.reaction)) .. "|r")
        if not f.maxed then
            tooltip:AddDoubleLine(L.REP_PROGRESS, ValueText(f, "both"))
            ns.TipDoubleLine(tooltip, L.REP_TO_NEXT, ns.Number(f.max - f.value), "highlight", "highlight")
        end
    else
        local locked = Factions.Watched()
        if locked then
            ns.TipLine(tooltip, locked.name, "normal")
            ns.TipLine(tooltip, L.REP_LOCKED_TIP, "highlight", true)
        else
            ns.TipLine(tooltip, L.REP_NONE_TIP, "highlight", true)
        end
    end

    local known = Known()
    local gains = ns.session.rep or {}
    local sessionList = {}
    for id, gain in pairs(gains) do sessionList[#sessionList + 1] = { id = id, gain = gain } end
    if #sessionList > 0 then
        table.sort(sessionList, function(a, b) return a.gain > b.gain end)
        tooltip:AddLine(" ")
        ns.TipLine(tooltip, L.REP_SESSION, "normal")
        for _, e in ipairs(sessionList) do
            local name = known[e.id] and known[e.id].name or tostring(e.id)
            local color = e.gain > 0 and (ns.GREEN .. "+") or ns.RED
            ns.TipDoubleLine(tooltip, name, color .. ns.Number(e.gain) .. "|r", "highlight", "normal")
        end
    end

    if cfg.listAll then
        local list = {}
        for id, info in pairs(known) do
            local d = ByID(id)
            if d and not (cfg.hideMax and d.maxed) and not (cfg.hideLow and (d.reaction or 4) <= 4) then
                list[#list + 1] = { f = d, header = info.header or "" }
            end
        end
        table.sort(list, function(a, b)
            if a.header ~= b.header then return a.header < b.header end
            return a.f.name < b.f.name
        end)
        local header
        for _, e in ipairs(list) do
            if e.header ~= header then
                header = e.header
                tooltip:AddLine(" ")
                ns.TipLine(tooltip, header ~= "" and header or L.REP_OTHER, "normal")
            end
            ns.TipDoubleLine(tooltip, "  " .. e.f.name, ValueText(e.f, "values") .. " " .. ns.Grey(e.f.friendText or Standing(e.f.reaction)), "highlight", "normal")
        end
    end
end

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    ezCore.TogglePanel("character", "ReputationFrame")
end

-- Rückfall ohne SetWatchedFactionByID: die Zeilennummer des Ruf-Fensters. Seit Welle 23 trägt jeder Datensatz von
-- Factions.List seine Zeile (index, ezCore A47) – sie stimmt auch, wenn eine Zeile ohne lesbaren Namen in der Liste
-- fehlt. Ohne index (älteres ezCore) gilt die Nummer in der Liste nur, wenn keine Zeile fehlt (so viele Einträge wie
-- Factions.Count); sonst lieber keine Fraktion als eine falsche, mit Hinweis.
local function SetWatchedIndex(row)
    if R.SetWatchedFactionIndex then R.SetWatchedFactionIndex(row) elseif SetWatchedFactionIndex then SetWatchedFactionIndex(row) end
end

local function SetWatched(id)
    if R.SetWatchedFactionByID then
        R.SetWatchedFactionByID(id)
        return true
    end
    local list = Factions.List()   -- Zeilen des Ruf-Fensters in seiner Reihenfolge (ezCore)
    for i, f in ipairs(list) do
        if f.id == id then
            local row = ns.Num(f.index)
            if row and row > 0 then
                SetWatchedIndex(row)
                return true
            end
            if #list ~= Factions.Count() then break end
            SetWatchedIndex(i)
            return true
        end
    end
    if #list ~= Factions.Count() then ns.Print(L.REP_WATCH_NO_ROW) end
    return false
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(bar, L.REP_MODE_WATCHED, cfg, "mode", "watched", self)
    ns.MenuRadio(bar, L.REP_MODE_LAST, cfg, "mode", "last", self)
    bar:CreateDivider()
    ns.MenuRadio(bar, L.REP_FORMAT_BOTH, cfg, "format", "both", self)
    ns.MenuRadio(bar, L.REP_FORMAT_VALUES, cfg, "format", "values", self)
    ns.MenuRadio(bar, L.REP_FORMAT_PERCENT, cfg, "format", "percent", self)
    bar:CreateDivider()
    ns.MenuCheck(bar, L.REP_SHOW_NAME, cfg, "showName", self)
    ns.MenuCheck(bar, L.REP_SESSION_ON_BAR, cfg, "sessionOnBar", self)

    local tip = root:CreateButton(L.MENU_TOOLTIP)
    ns.MenuCheck(tip, L.REP_LIST_ALL, cfg, "listAll", self)
    ns.MenuCheck(tip, L.REP_HIDE_MAX, cfg, "hideMax", self)
    ns.MenuCheck(tip, L.REP_HIDE_LOW, cfg, "hideLow", self)

    local watch = root:CreateButton(L.REP_WATCH)
    local list = {}
    for id, info in pairs(Known()) do list[#list + 1] = { id = id, name = info.name or tostring(id) } end
    table.sort(list, function(a, b) return a.name < b.name end)
    local current = Factions.Watched()   -- auch mit gesperrten Zahlen ist klar, welche beobachtet wird
    for _, e in ipairs(list) do
        watch:CreateRadio(e.name, function() return current and current.id == e.id end, function()
            SetWatched(e.id)
            C_Timer.After(0.2, function() ns.QueueUpdate(self) end)
        end, e.id)
    end
end
