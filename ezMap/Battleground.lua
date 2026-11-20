local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Schlachtfeld-Timer (Auftrag des Nutzers 13.11.2026: „ich glaube capping sollte auch nahtlos in ein passendes
    modul übernommen werden“). Capping selbst wird nicht übernommen, kein Code und keine Tabelle (Leitlinie 10);
    ezMap baut die Funktion mit Daten aus dem Client nach (Leitlinie 11). Keine eigene Dauer-Tabelle je Schlachtfeld:
    ezMap zeigt nur Zeiten, die das Spiel selbst nennt.

    Quellen (Blizzards Forever-Quelle, Gethe/wow-ui-source, Zweig forever):
      - Zeit bis zum Start: Ereignis START_TIMER (timerType, timeRemaining, totalTime) mit
        Enum.StartTimerType.PvPBeginTimer, Ende über STOP_TIMER_OF_TYPE; Blizzard verwirft den Zähler bei
        PLAYER_ENTERING_WORLD (Blizzard_FrameXML/Timer.lua, TimerTracker_OnEvent) – ezMap ebenso
      - Restzeit je Punkt der Schlachtfeldkarte: C_AreaPoiInfo.IsAreaPOITimed(id) und
        C_AreaPoiInfo.GetAreaPOISecondsLeft(id), genau wie Blizzards eigener Kartentooltip
        (Blizzard_FrameXMLUtil/AreaPoiUtil.lua, AreaPoiUtil.TryShowTooltip; „hideTimerInTooltip“ blendet auch hier aus);
        neu gelesen bei AREA_POIS_UPDATED. Nur in einem Schlachtfeld (IsInInstance → "pvp"), damit Zeiten der offenen
        Welt nicht auftauchen. Liefert der Client keine Restzeit (oder ist sie gesperrt), zeigt ezMap nichts
      - Ansage per Klick auf eine Zeile: ezCore.API("ezMacro").Announce(text, "group") – nie von selbst; ohne ezMacro
        nur eine Chatzeile für dich

    Anzeige: Zeilen direkt unter Blizzards Punkteanzeige oben in der Mitte (UIWidgetTopCenterContainerFrame), kein
    eigenes Fenster; fehlt Blizzards Anzeige, oben in der Mitte des Bildschirms. Vorschau und Diagnose (/ezmap bg)
    bleiben. Rücksicht: läuft ein Addon, das Schlachtfeld-Timer zeigt (Capping; Core.WhoHandles("battlegroundTimers")),
    zeichnet ezMap nur die Vorschau.

    Was auf den Spieltest wartet (docs/roadmap/ezMap.md, „Schlachtfeld“): ob Forevers Schlachtfeldpunkte überhaupt als
    „mit Zeit“ gelten, Flaggen-Rückkehr und Schätzung des Endstands (Blizzards Punkteanzeige, UPDATE_UI_WIDGET);
    die Warteschlangen-Zeit steht seit Welle 5 als ezPanel-Baustein in Queue.lua (MAP-12). Für Flaggen und
    Punktestand listet die Diagnose die Widgets der Punkteanzeige auf
    (C_UIWidgetManager, BG.WidgetLines) – welche Arten Forever dort nutzt, zeigt erst das Spiel.
]]
local BG = {}
ns.Battleground = BG

BG.ROW_WIDTH, BG.ROW_HEIGHT, BG.ROW_GAP, BG.MAX_ROWS = 180, 14, 3, 6
BG.ANCHOR_NAME = "UIWidgetTopCenterContainerFrame"
BG.START_KEY = "start"          -- Zeit bis zum Start
BG.POI_PREFIX = "poi:"          -- Restzeit je Kartenpunkt: "poi:<areaPoiID>"
BG.KEEP_SLACK = 2               -- Sekunden: so nah an der alten Restzeit gilt ein Punkt als derselbe Lauf
BG.COLORS = {
    start = { 0.2, 0.8, 0.2 },
    alliance = { 0.3, 0.5, 1 },
    horde = { 1, 0.25, 0.25 },
    other = { 1, 0.7, 0 },
}
-- Fraktion: Text für das Kürzel vor dem Namen und für den Tooltip (Farbenblind-Hilfe, EC-47)
BG.FACTION_MARKS = { alliance = "BG_MARK_ALLIANCE", horde = "BG_MARK_HORDE" }
BG.FACTION_NAMES = { alliance = "BG_FACTION_ALLIANCE", horde = "BG_FACTION_HORDE" }

local timers = {}       -- [key] = { key, label, duration, ends (GetTime), r, g, b, preview, source, poi, faction }
local holder, rows = nil, {}

-- Wer Schlachtfeld-Timer schon zeigt (Capping), sonst nil.
function BG.Elsewhere() return ns.OtherFor("battlegroundTimers") end

-- Echte Timer zeigen? Schalter an und kein anderes Addon zuständig.
function BG.Active() return ns.Enabled("bgTimers") and not BG.Elsewhere() end

-- In einem Schlachtfeld? Gesperrte oder fehlende Werte gelten als nein (Core.InInstance). Die Diagnose unten fragt
-- IsInInstance bewusst roh, damit sie zeigt, was der Client wirklich antwortet.
function BG.InBattleground()
    local inside, kind = Core.InInstance()
    return inside == true and kind == "pvp"
end

---------------------------------------------------------------------------
-- Timer-Modell
---------------------------------------------------------------------------

-- Timer starten bzw. ersetzen. opts: { r, g, b, preview, total (Gesamtdauer für die Leiste), source, poi,
-- faction ("alliance" oder "horde", sonst keine) }.
-- Rückgabe: der Timer oder nil.
function BG.Start(key, label, seconds, opts)
    seconds = ns.Num(seconds)
    if ns.IsSecret(key) or key == nil or ns.IsSecret(label) or type(label) ~= "string" or not seconds or seconds <= 0 then
        return nil
    end
    opts = opts or {}
    local total = ns.Num(opts.total)
    local timer = { key = key, label = label, duration = (total and total > seconds) and total or seconds,
        ends = Core.Uptime() + seconds, r = opts.r or 1, g = opts.g or 0.7, b = opts.b or 0, preview = opts.preview == true,
        source = type(opts.source) == "string" and opts.source or nil, poi = opts.poi,
        faction = BG.FACTION_MARKS[opts.faction] and opts.faction or nil }
    timers[key] = timer
    BG.Refresh()
    return timer
end

function BG.Stop(key)
    if key == nil or timers[key] == nil then return false end
    timers[key] = nil
    BG.Refresh()
    return true
end

function BG.Clear(previewOnly)
    for key, timer in pairs(timers) do
        if not previewOnly or timer.preview then timers[key] = nil end
    end
    BG.Refresh()
end

-- Alle echten Timer weg, die Vorschau bleibt (Schalter aus, neue Instanz).
function BG.ClearReal()
    for key, timer in pairs(timers) do
        if not timer.preview then timers[key] = nil end
    end
    BG.Refresh()
end

local function Copy(key, timer, now)
    return { key = key, label = timer.label, duration = timer.duration, remaining = timer.ends - now,
        r = timer.r, g = timer.g, b = timer.b, preview = timer.preview, source = timer.source, poi = timer.poi,
        faction = timer.faction }
end

-- Ein laufender Timer (Kopie mit frischer Restzeit) oder nil.
function BG.Get(key)
    local timer = key ~= nil and timers[key]
    if not timer then return nil end
    local copy = Copy(key, timer, Core.Uptime())
    if copy.remaining <= 0 then return nil end
    return copy
end

-- Laufende Timer, der kürzeste zuerst: { key, label, duration, remaining, r, g, b, preview, source }.
-- Abgelaufene fallen weg.
function BG.List()
    local now, list = Core.Uptime(), {}
    for key, timer in pairs(timers) do
        if timer.ends - now <= 0 then
            timers[key] = nil
        else
            list[#list + 1] = Copy(key, timer, now)
        end
    end
    table.sort(list, function(a, b)
        if a.remaining ~= b.remaining then return a.remaining < b.remaining end
        return tostring(a.key) < tostring(b.key)
    end)
    return list
end

---------------------------------------------------------------------------
-- Quelle 1: Zeit bis zum Start (Blizzards Startzähler)
---------------------------------------------------------------------------

-- Blizzards Art „Schlachtfeld beginnt“ (Enum.StartTimerType.PvPBeginTimer) oder nil, wenn der Client sie nicht kennt.
function BG.PvPStartType()
    local types = type(Enum) == "table" and Enum.StartTimerType
    return type(types) == "table" and types.PvPBeginTimer or nil
end

local function IsPvPStart(timerType)
    local pvp = BG.PvPStartType()
    return pvp ~= nil and not ns.IsSecret(timerType) and timerType == pvp
end

-- START_TIMER: Restzeit 0 oder weniger beendet den Zähler (so behandelt Blizzard es auch). Rückgabe: der Timer oder nil.
function BG.OnStartTimer(timerType, remaining, total)
    if not IsPvPStart(timerType) then return nil end
    remaining = ns.Num(remaining)
    if not BG.Active() or not remaining or remaining <= 0 then
        BG.Stop(BG.START_KEY)
        return nil
    end
    local c = BG.COLORS.start
    return BG.Start(BG.START_KEY, L.BG_START, remaining,
        { total = total, r = c[1], g = c[2], b = c[3], source = L.BG_SOURCE_START })
end

function BG.OnStopTimer(timerType)
    if IsPvPStart(timerType) then return BG.Stop(BG.START_KEY) end
    return false
end

---------------------------------------------------------------------------
-- Quelle 2: Restzeit je Punkt der Schlachtfeldkarte (wie Blizzards Kartentooltip)
---------------------------------------------------------------------------

-- Fraktion nach Blizzards Symbolnamen des Punkts („…alliance…“, „…horde…“): "alliance", "horde" oder nil.
function BG.FactionOf(info)
    local names = {}
    if type(info) == "table" then
        for _, field in ipairs({ "atlasName", "uiTextureKit" }) do
            local value = Core.Plain(info[field])
            if type(value) == "string" then names[#names + 1] = value:lower() end
        end
    end
    local text = table.concat(names, " ")
    if text:find("alliance", 1, true) then return "alliance" end
    if text:find("horde", 1, true) then return "horde" end
    return nil
end

-- Farbe nach Blizzards Symbolnamen des Punkts: Blau (Allianz), Rot (Horde), sonst Orange.
function BG.ColorFor(info)
    return BG.COLORS[BG.FactionOf(info) or "other"]
end

-- Farbenblind-Hilfe (EC-47): Die Farbe der Zeile allein sagt nicht, wem ein Punkt gehört. Der Tooltip nennt die
-- Fraktion immer; ist in ezCore „Zeichen am Leuchten“ an, steht ihr Kürzel auch vor dem Namen. Leitet seit ezCore
-- 1.12.0 auf Core.MarksOn weiter (ein älteres ezCore ohne den Helfer: aus). GLOW_MARKS_CHANGED braucht es hier
-- nicht: Die Zeilen zeichnen sich alle 0,2 Sekunden neu (OnUpdate in Holder).
function BG.MarksEnabled()
    return type(Core.MarksOn) == "function" and Core.MarksOn() == true
end

-- Text der Zeile: der Name, mit Schalter und bekannter Fraktion davor ihr Kürzel („[A] Ställe“).
function BG.RowLabel(timer)
    local mark = timer.faction and BG.FACTION_MARKS[timer.faction]
    if mark and BG.MarksEnabled() then return L[mark]:format(timer.label) end
    return timer.label
end

-- Restzeit (Sekunden), Name und Kartenpunkt-Angaben eines Punkts – nur, wenn der Client ihn als „mit Zeit“ führt,
-- die Zeit nicht ausblendet und eine lesbare Restzeit über 0 nennt. Sonst nil.
function BG.PoiTime(mapID, id)
    local P = C_AreaPoiInfo
    if ns.IsSecret(id) or type(id) ~= "number" or not (P and P.IsAreaPOITimed and P.GetAreaPOISecondsLeft) then return nil end
    local ok, timed, hide = pcall(P.IsAreaPOITimed, id)
    if not ok or not Core.Bool(timed, false) or Core.Bool(hide, false) then return nil end
    local okLeft, seconds = pcall(P.GetAreaPOISecondsLeft, id)
    seconds = okLeft and ns.Num(seconds) or nil
    if not seconds or seconds <= 0 then return nil end
    local info
    if P.GetAreaPOIInfo then
        local okInfo, value = pcall(P.GetAreaPOIInfo, mapID, id)
        if okInfo and not ns.IsSecret(value) and type(value) == "table" then info = value end
    end
    local name = info and Core.Plain(info.name)
    if type(name) ~= "string" or name == "" then name = L.BG_POINT:format(id) end
    return seconds, name, info
end

-- Punkte der aktuellen Karte lesen und die Timer abgleichen: neue starten, laufende behalten (gleicher Lauf) oder
-- neu setzen, verschwundene entfernen. Rückgabe: Anzahl der Punkte mit Zeit.
function BG.ScanPois()
    local seen, count = {}, 0
    local P = C_AreaPoiInfo
    if BG.Active() and BG.InBattleground() and P and P.GetAreaPOIForMap then
        local mapID = ns.Num(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
        local ok, ids = false, nil
        if mapID then ok, ids = pcall(P.GetAreaPOIForMap, mapID) end
        if ok and not ns.IsSecret(ids) and type(ids) == "table" then
            for _, id in ipairs(ids) do
                local seconds, name, info = BG.PoiTime(mapID, id)
                if seconds then
                    local key = BG.POI_PREFIX .. id
                    seen[key], count = true, count + 1
                    local running = BG.Get(key)
                    local same = running and seconds <= running.remaining + BG.KEEP_SLACK
                    if not (same and math.abs(running.remaining - seconds) < BG.KEEP_SLACK and running.label == name) then
                        local c = BG.ColorFor(info)
                        BG.Start(key, name, seconds, { total = same and running.duration or nil,
                            r = c[1], g = c[2], b = c[3], source = L.BG_SOURCE_POI, poi = id, faction = BG.FactionOf(info) })
                    end
                end
            end
        end
    end
    local removed = false
    for key, timer in pairs(timers) do
        if timer.poi ~= nil and not seen[key] then
            timers[key] = nil
            removed = true
        end
    end
    if removed then BG.Refresh() end
    return count
end

---------------------------------------------------------------------------
-- Ansage per Klick (ezMacro)
---------------------------------------------------------------------------

-- „Hof in 0:45“
function BG.AnnounceText(timer)
    return L.BG_ANNOUNCE:format(timer.label, ns.Clock(math.max(0, math.floor(timer.remaining + 0.5))))
end

-- Klick auf eine Zeile: Ansage über ezMacros Ansagen (Kanal wählt ezMacro). Die Vorschau sendet nichts; ohne ezMacro
-- nur eine Chatzeile für dich. Rückgabe: true gesendet, sonst false und Grund.
function BG.Announce(timer)
    if type(timer) ~= "table" or not timer.remaining or timer.remaining <= 0 then return false, "none" end
    local text = BG.AnnounceText(timer)
    if timer.preview then
        ns.Print(L.BG_ANNOUNCE_PREVIEW:format(text))
        return false, "preview"
    end
    local api = Core.API("ezMacro")
    if not (api and type(api.Announce) == "function") then
        ns.Print(L.BG_ANNOUNCE_NO_MACRO:format(text))
        return false, "nomacro"
    end
    local ok, sent, why = pcall(api.Announce, text, "group")
    if not ok then return false, "failed" end
    return sent == true, why
end

---------------------------------------------------------------------------
-- Anzeige: Zeilen unter Blizzards Punkteanzeige
---------------------------------------------------------------------------

-- Blizzards Punkteanzeige oben in der Mitte, sonst nil.
function BG.AnchorFrame()
    local frame = rawget(_G, BG.ANCHOR_NAME)
    if type(frame) == "table" and type(frame.GetObjectType) == "function" then return frame end
    return nil
end

local function Holder()
    if holder then return holder end
    holder = CreateFrame("Frame", "ezMapBattlegroundTimers", UIParent)
    holder:SetSize(BG.ROW_WIDTH, BG.ROW_HEIGHT)
    holder:SetFrameStrata("MEDIUM")
    local since = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.2 then return end
        since = 0
        BG.Refresh()
    end)
    holder:Hide()
    return holder
end

-- Lage: unter Blizzards Punkteanzeige (wandert mit ihr), sonst oben in der Mitte. Hätte die leere Anzeige keine
-- Fläche (keine Unterkante), ebenfalls oben in der Mitte.
function BG.Place()
    local frame = Holder()
    local anchor = BG.AnchorFrame()
    frame:ClearAllPoints()
    if anchor then
        frame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        local top = frame.GetTop and frame:GetTop()
        if ns.IsSecret(top) or top ~= nil then return anchor end
        frame:ClearAllPoints()
    end
    frame:SetPoint("TOP", UIParent, "TOP", 0, -60)
    return UIParent
end

local function Row(index)
    local row = rows[index]
    if row then return row end
    row = Core.NewTimerBar(Holder(), { name = "ezMapBattlegroundTimer" .. index, width = BG.ROW_WIDTH,
        height = BG.ROW_HEIGHT })
    row:SetPoint("TOP", holder, "TOP", 0, -(index - 1) * (BG.ROW_HEIGHT + BG.ROW_GAP))
    -- links der Name (der Text des Bausteins), rechts die Restzeit in derselben Schrift-Rolle
    row.Label = row.Text
    row.Label:ClearAllPoints()
    row.Label:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.Time = row:CreateFontString(nil, "OVERLAY")
    row.Time:SetFontObject(row.Text:GetFontObject() or "GameFontHighlightSmall")
    row.Time:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        Core.TipTitle(GameTooltip, L.BG_ROW_TITLE)
        local timer = self.timer
        if timer then GameTooltip:AddLine(timer.label, nil, nil, nil, true) end
        if timer and BG.FACTION_NAMES[timer.faction] then
            Core.TipLine(GameTooltip, L.BG_ROW_FACTION:format(L[BG.FACTION_NAMES[timer.faction]]), "highlight", true)
        end
        Core.TipLine(GameTooltip, timer and timer.preview and L.BG_ROW_PREVIEW_TIP or L.BG_ROW_TIP, "hint", true)
        if timer and timer.source then Core.TipLine(GameTooltip, L.BG_ROW_SOURCE:format(timer.source), "hint", true) end
        Core.TipClick(GameTooltip, L.BG_ROW_CLICK)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Sichtbarer Knopf (Leitlinie 3): die Zeile selbst. Linksklick sagt die frische Restzeit an.
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not self.timer then return end
        ns.Try("Battleground", BG.Announce, BG.Get(self.timer.key))
    end)
    rows[index] = row
    return row
end

-- Zeilen neu zeichnen. Rückgabe: Anzahl sichtbarer Zeilen. Schalter aus oder ein anderes Timer-Addon: nur die Vorschau.
function BG.Refresh()
    local list = BG.List()
    if not BG.Active() then
        for i = #list, 1, -1 do
            if not list[i].preview then table.remove(list, i) end
        end
    end
    local shown = math.min(#list, BG.MAX_ROWS)
    if shown == 0 then
        if holder then holder:Hide() end
        return 0
    end
    local frame = Holder()
    if not frame:IsShown() then
        BG.Place()
        frame:Show()
    end
    for i = 1, shown do
        local timer, row = list[i], Row(i)
        row.timer = timer
        row:SetMinMaxValues(0, timer.duration)
        row:SetValue(timer.remaining)
        row:SetStatusBarColor(timer.r, timer.g, timer.b)
        row.Label:SetText(BG.RowLabel(timer))
        row.Time:SetText(ns.Clock(timer.remaining))
        row:Show()
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    frame:SetHeight(shown * (BG.ROW_HEIGHT + BG.ROW_GAP))
    return shown
end

function BG.Holder() return holder end
function BG.Rows() return rows end

-- Vorschau (Einstellungen): zwei Beispielzeilen, 20 Sekunden lang – zeigt den Platz unter Blizzards Punkteanzeige.
function BG.Preview()
    BG.Start("preview:1", L.BG_PREVIEW_ONE, 20, { preview = true })
    BG.Start("preview:2", L.BG_PREVIEW_TWO, 45, { preview = true, r = 0.3, g = 0.5, b = 1, faction = "alliance" })
    C_Timer.After(20, function() BG.Clear(true) end)
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("START_TIMER", function(_, timerType, remaining, total)
    ns.Try("Battleground", BG.OnStartTimer, timerType, remaining, total)
end)
ns.On("STOP_TIMER_OF_TYPE", function(_, timerType) ns.Try("Battleground", BG.OnStopTimer, timerType) end)
-- Neue Instanz (Ladebildschirm): Blizzard verwirft den Startzähler, ezMap alle echten Timer; dann neu lesen.
ns.On("PLAYER_ENTERING_WORLD", function()
    ns.Try("Battleground", function()
        BG.ClearReal()
        BG.ScanPois()
    end)
end)
ns.On("AREA_POIS_UPDATED", function() ns.Try("Battleground", BG.ScanPois) end)
ns.On("ZONE_CHANGED_NEW_AREA", function() ns.Try("Battleground", BG.ScanPois) end)

ns.OnSettingChanged(function(key)
    if key ~= "bgTimers" then return end
    if ns.Enabled("bgTimers") then BG.ScanPois() else BG.ClearReal() end
end)

---------------------------------------------------------------------------
-- Diagnose: was liefert der Client im Schlachtfeld? (Antworten für den Spieltest)
---------------------------------------------------------------------------

local function Show(value)
    if ns.IsSecret(value) then return L.BG_DIAG_SECRET end
    if value == nil then return "–" end
    return tostring(value)
end

-- Restzeit eines Punkts für die Diagnose: „1:05“, „ohne Zeit“, „ausgeblendet“ oder „(gesperrt)“.
local function DiagTime(id)
    local P = C_AreaPoiInfo
    if ns.IsSecret(id) or not (P and P.IsAreaPOITimed) then return "–" end
    local ok, timed, hide = pcall(P.IsAreaPOITimed, id)
    if not ok then return "–" end
    if ns.IsSecret(timed) then return L.BG_DIAG_SECRET end
    if not timed then return L.BG_DIAG_UNTIMED end
    local seconds
    if P.GetAreaPOISecondsLeft then
        local okLeft, value = pcall(P.GetAreaPOISecondsLeft, id)
        if okLeft and ns.IsSecret(value) then return L.BG_DIAG_SECRET end
        seconds = okLeft and ns.Num(value) or nil
    end
    local text = seconds and ns.Clock(seconds) or "–"
    if Core.Bool(hide, false) then text = text .. " " .. L.BG_DIAG_HIDDEN end
    return text
end

-- Widgets der Punkteanzeige ---------------------------------------------------------------------------------------
-- Blizzards Punkteanzeige oben in der Mitte besteht aus Widgets (Forever-Quelle Blizzard_UIWidgets/
-- Blizzard_UIWidgetManager.lua: C_UIWidgetManager.GetAllWidgetsBySetID liefert je Widget widgetID und widgetType;
-- je Art gibt es eine Abfrage der Anzeige-Daten). Die Diagnose listet sie roh auf, damit der Spieltest zeigt,
-- welche Arten Forever für Flaggen und Punktestand nutzt. Nur lesen; jeder Wert geht zuerst durch Core.IsSecret.
BG.DIAG_WIDGETS_MAX = 12        -- so viele Widgets nennt die Diagnose höchstens
BG.DIAG_FIELDS_MAX = 14         -- so viele Angaben je Widget
BG.DIAG_TEXT_MAX = 48           -- so viele Bytes je Wert

-- Wert für die Chatzeile: roh, einzeilig, gekürzt (nicht mitten in einem UTF-8-Zeichen); „|“ verdoppelt, damit
-- Blizzards Farb- und Bildkürzel als Text dastehen statt zu wirken.
local function Short(value)
    local text = Show(value):gsub("[\r\n]+", " "):gsub("|", "||")
    if #text > BG.DIAG_TEXT_MAX then
        local cut = BG.DIAG_TEXT_MAX
        while cut > 1 and text:byte(cut + 1) and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do cut = cut - 1 end
        if text:sub(cut, cut) == "|" and text:sub(cut + 1, cut + 1) == "|" then cut = cut - 1 end
        text = text:sub(1, cut) .. "…"
    end
    return text
end

-- Name einer Widget-Art aus Enum.UIWidgetVisualizationType („IconAndText“) oder nil.
local function WidgetTypeName(widgetType)
    local types = type(Enum) == "table" and Enum.UIWidgetVisualizationType
    if type(types) ~= "table" then return nil end
    for name, value in pairs(types) do
        if value == widgetType and type(name) == "string" then return name end
    end
    return nil
end

-- Blizzards Abfrage der Anzeige-Daten zu einer Widget-Art: zuerst die, die Blizzards Widget-Verwaltung für die Art
-- angemeldet hat (UIWidgetManager.widgetVisTypeInfo[Art].visInfoDataFunction – nur gelesen), sonst nach Blizzards
-- Namensregel C_UIWidgetManager.Get<Art>WidgetVisualizationInfo bzw. Get<Art>VisualizationInfo. widgetType ist hier
-- schon geprüft (nicht gesperrt).
local function WidgetInfoFunction(widgetType, name)
    local manager = rawget(_G, "UIWidgetManager")
    local infos = type(manager) == "table" and manager.widgetVisTypeInfo
    local entry = type(infos) == "table" and infos[widgetType]
    if type(entry) == "table" and type(entry.visInfoDataFunction) == "function" then return entry.visInfoDataFunction end
    local W = C_UIWidgetManager
    if type(name) == "string" and type(W) == "table" then
        local fn = W["Get" .. name .. "WidgetVisualizationInfo"] or W["Get" .. name .. "VisualizationInfo"]
        if type(fn) == "function" then return fn end
    end
    return nil
end

local function KeyOrder(a, b)
    if type(a) == "number" and type(b) == "number" then return a < b end
    return tostring(a) < tostring(b)
end

-- Angaben eines Widgets als „feld=wert“, nach Namen sortiert; Listen und Untertabellen bis zwei Ebenen tief als
-- „feld[1].unterfeld=wert“. Gesperrte Werte stehen als „(gesperrt)“ da, ohne dass mit ihnen verglichen wird.
function BG.WidgetFields(info)
    if ns.IsSecret(info) then return L.BG_DIAG_SECRET end
    if type(info) ~= "table" then return "–" end
    local parts = {}
    local function Add(prefix, tbl, depth)
        local keys = {}
        for key in pairs(tbl) do
            if not ns.IsSecret(key) and (type(key) == "string" or type(key) == "number") then keys[#keys + 1] = key end
        end
        table.sort(keys, KeyOrder)
        for _, key in ipairs(keys) do
            local value = tbl[key]
            local label
            if type(key) == "number" then
                label = prefix .. "[" .. key .. "]"
            else
                label = prefix ~= "" and (prefix .. "." .. key) or key
            end
            if ns.IsSecret(value) then
                parts[#parts + 1] = label .. "=" .. L.BG_DIAG_SECRET
            elseif type(value) == "table" then
                if depth < 2 then Add(label, value, depth + 1) else parts[#parts + 1] = label .. "={…}" end
            elseif type(value) ~= "function" and type(value) ~= "userdata" then
                parts[#parts + 1] = label .. "=" .. Short(value)
            end
        end
    end
    Add("", info, 0)
    if #parts == 0 then return "–" end
    local more = #parts - BG.DIAG_FIELDS_MAX
    if more > 0 then
        for i = #parts, BG.DIAG_FIELDS_MAX + 1, -1 do parts[i] = nil end
        parts[#parts + 1] = ezCore.More(more)
    end
    return table.concat(parts, ", ")
end

-- Zeilen der Diagnose zu den Widgets der Punkteanzeige: Satz, Anzahl, je Widget Nummer, Art und Angaben.
function BG.WidgetLines()
    local lines = {}
    local W = C_UIWidgetManager
    if not (type(W) == "table" and type(W.GetTopCenterWidgetSetID) == "function"
        and type(W.GetAllWidgetsBySetID) == "function") then
        lines[1] = L.BG_DIAG_WIDGETLIST_NONE
        return lines
    end
    local okSet, setID = pcall(W.GetTopCenterWidgetSetID)
    if not okSet then setID = nil end
    local widgets
    if not ns.IsSecret(setID) and setID ~= nil then
        local ok, list = pcall(W.GetAllWidgetsBySetID, setID)
        if ok and not ns.IsSecret(list) and type(list) == "table" then widgets = list end
    end
    if not widgets then
        lines[1] = L.BG_DIAG_WIDGETLIST_SECRET:format(Show(setID))
        return lines
    end
    lines[1] = L.BG_DIAG_WIDGETLIST:format(Show(setID), #widgets)
    for i = 1, math.min(#widgets, BG.DIAG_WIDGETS_MAX) do
        local widget = widgets[i]
        if ns.IsSecret(widget) or type(widget) ~= "table" then
            lines[#lines + 1] = L.BG_DIAG_WIDGET:format(L.BG_DIAG_SECRET, "–", "–")
        else
            local id, kind = widget.widgetID, widget.widgetType
            local readable = not ns.IsSecret(kind) and kind ~= nil
            local name = readable and WidgetTypeName(kind) or nil
            local kindText = name and ("%s (%s)"):format(name, Show(kind)) or Show(kind)
            local values = "–"
            if readable and not ns.IsSecret(id) and id ~= nil then
                local fn = WidgetInfoFunction(kind, name)
                if not fn then
                    values = L.BG_DIAG_WIDGET_NO_QUERY
                else
                    local okInfo, info = pcall(fn, id)
                    if not okInfo then
                        values = L.BG_DIAG_WIDGET_FAILED
                    elseif ns.IsSecret(info) then
                        values = L.BG_DIAG_SECRET
                    elseif type(info) == "table" then
                        values = BG.WidgetFields(info)
                    else
                        values = L.BG_DIAG_WIDGET_EMPTY
                    end
                end
            end
            lines[#lines + 1] = L.BG_DIAG_WIDGET:format(Show(id), kindText, values)
        end
    end
    if #widgets > BG.DIAG_WIDGETS_MAX then
        lines[#lines + 1] = ezCore.More(#widgets - BG.DIAG_WIDGETS_MAX)
    end
    return lines
end

-- Zeilen der Diagnose als Liste (für den Chat und die Prüfungen).
function BG.DiagnoseLines()
    local lines = {}
    local inside, kind = false, nil
    if type(IsInInstance) == "function" then inside, kind = IsInInstance() end
    lines[#lines + 1] = L.BG_DIAG_INSTANCE:format(Show(inside), Show(kind))
    local name
    if type(GetInstanceInfo) == "function" then name = GetInstanceInfo() end
    lines[#lines + 1] = L.BG_DIAG_NAME:format(Show(name))
    lines[#lines + 1] = L.BG_DIAG_WIDGETS:format(BG.AnchorFrame() and L.BG_DIAG_YES or L.BG_DIAG_NO)
    lines[#lines + 1] = L.BG_DIAG_START:format(Show(BG.PvPStartType()))
    local other = BG.Elsewhere()
    if other then lines[#lines + 1] = L.BG_DIAG_OTHER:format(other) end
    -- Widgets der Punkteanzeige (Flaggen, Punktestand): welche Arten Forever nutzt, zeigt erst das Spiel
    for _, line in ipairs(BG.WidgetLines()) do lines[#lines + 1] = line end
    local mapID = ns.Num(C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local P = C_AreaPoiInfo
    if not (mapID and P and P.GetAreaPOIForMap and P.GetAreaPOIInfo) then
        lines[#lines + 1] = L.BG_DIAG_NO_POIS
        return lines
    end
    local ok, ids = pcall(P.GetAreaPOIForMap, mapID)
    if not ok or ns.IsSecret(ids) or type(ids) ~= "table" then
        lines[#lines + 1] = L.BG_DIAG_POIS_SECRET:format(ns.MapName(mapID))
        return lines
    end
    lines[#lines + 1] = L.BG_DIAG_POIS:format(ns.MapName(mapID), #ids)
    for i = 1, math.min(#ids, 12) do
        local okInfo, info = pcall(P.GetAreaPOIInfo, mapID, ids[i])
        if okInfo and not ns.IsSecret(info) and type(info) == "table" then
            lines[#lines + 1] = L.BG_DIAG_POI:format(Show(ids[i]), Show(info.name), Show(info.atlasName),
                Show(info.textureIndex), Show(info.description), DiagTime(ids[i]))
        else
            lines[#lines + 1] = L.BG_DIAG_POI:format(Show(ids[i]), L.BG_DIAG_SECRET, "–", "–", "–", DiagTime(ids[i]))
        end
    end
    return lines
end

function BG.Diagnose()
    ns.Print(L.BG_DIAG_HEAD)
    for _, line in ipairs(BG.DiagnoseLines()) do ns.Print("  " .. line) end
    ns.Print(L.BG_DIAG_FOOT)
end

ns.AddStatusLine(function()
    local other = BG.Elsewhere()
    if other then return L.STATUS_BG_OTHER:format(other) end
    if ns.Enabled("bgTimers") then return L.STATUS_BG end
    return L.STATUS_BG_OFF
end)
