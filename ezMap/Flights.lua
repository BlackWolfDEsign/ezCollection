local _, ns = ...
local L = ns.L
local Core = ezCore

-- Flugzeiten: ezMap lernt jede Strecke beim Fliegen (keine mitgelieferte Tabelle) und zeigt sie im Tooltip
-- der Flugpunkte (Blizzards Flugkarte, beide Varianten) sowie während des Flugs in einer Leiste im Stil von
-- Blizzards Zauberleiste. Zeigt ein anderes Addon schon Flugzeiten (Erkennung über ezCore, ns.FlightTimesElsewhere), lernt
-- ezMap nur still mit.
local Flights = {}
ns.Flights = Flights

-- Forever: „Vielflieger“ macht Flüge 20 % schneller. Quelle ist der Client: Zauber 1225490 in seiner Zauberdatenbank
-- (C_Spell.GetSpellName nennt „Vielflieger“, C_Spell.GetSpellDescription die 20 %); ob du ihn hast, fragt
-- IsPlayerSpell zur Laufzeit. Bestätigung im Spiel und eigene Messung: Punkt 26 in docs/roadmap/ezMap.md.
-- Gespeichert wird immer die Zeit bei normaler Geschwindigkeit.
local FREQUENT_FLIER_SPELL, FREQUENT_FLIER_SPEED = 1225490, 1.2
local TOLERANCE = 15        -- Sekunden: kleinere Abweichungen melden sich nicht als „neu gelernt“
local MIN_FLIGHT = 5        -- kürzere „Flüge“ sind abgebrochen

local function Speed()
    if IsPlayerSpell and IsPlayerSpell(FREQUENT_FLIER_SPELL) then return FREQUENT_FLIER_SPEED end
    return 1
end

-- Zeichnet ezMap gerade Flugzeiten (Einstellung an und kein anderes Addon zuständig)?
local function Showing(key)
    return ns.Enabled(key) and not ns.FlightTimesElsewhere()
end

---------------------------------------------------------------------------
-- Flugpunkte und Strecken
---------------------------------------------------------------------------

-- Name ohne Zone: „Goldhain, Wald von Elwynn“ → „Goldhain“
local function NodeName(slot)
    local name = TaxiNodeName and TaxiNodeName(slot)
    if ns.IsSecret(name) or type(name) ~= "string" then return "?" end
    return name:match("^[^,]+") or name
end

-- Knoten-ID je Platz der offenen Flugkarte (stabil und sprachunabhängig); sonst zählt der Name.
local slotIDs = {}
local function ReadNodeIDs()
    wipe(slotIDs)
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then return end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, GetTaxiMapID())
    if not ok or type(nodes) ~= "table" then return end
    for _, node in ipairs(nodes) do
        if node.slotIndex and node.nodeID then slotIDs[node.slotIndex] = node.nodeID end
    end
end
ns.On("TAXIMAP_OPENED", ReadNodeIDs)

local function NodeKey(slot)
    if next(slotIDs) == nil then ReadNodeIDs() end
    local id = slotIDs[slot]
    if id then return tostring(id) end
    return "n:" .. NodeName(slot)
end

-- Rückgaben der Flug-Schnittstellen erst durch ezCore (Leitlinie 6): ein gesperrter Wert ist keine Antwort.
-- Art eines Platzes der offenen Flugkarte ("CURRENT", "REACHABLE" …) oder nil.
local function NodeType(slot)
    if type(TaxiNodeGetType) ~= "function" then return nil end
    return Core.Plain(TaxiNodeGetType(slot))
end
Flights.NodeType = NodeType

-- Sitzt du gerade auf einem Flugtier? Gesperrt oder unbekannt gilt als nein. Zweiter Wert: true, wenn die Antwort
-- gesperrt war (dann lernt ezMap aus dem Flug nichts – die Zeit ist nicht belegt).
local function OnTaxi()
    if type(UnitOnTaxi) ~= "function" then return false, false end
    local raw = UnitOnTaxi("player")
    if ns.IsSecret(raw) then return false, true end
    return Core.Bool(raw, false), false
end
Flights.OnTaxi = OnTaxi

local function CurrentSlot()
    if not (NumTaxiNodes and TaxiNodeGetType) then return nil end
    for slot = 1, (ns.Num(NumTaxiNodes()) or 0) do
        if NodeType(slot) == "CURRENT" then return slot end
    end
    return nil
end

-- Strecke vom aktuellen Flugpunkt zum Ziel über alle Zwischenhalte: Schlüssel („12>7>3“), Namen.
function Flights.Route(dest)
    local current = CurrentSlot()
    if not current or current == dest then return nil end
    local slots = { current }
    local hops = GetNumRoutes and GetNumRoutes(dest) or 0
    for i = 1, hops do
        local slot = TaxiGetNodeSlot(dest, i, false)
        if slot and slot ~= slots[#slots] then slots[#slots + 1] = slot end
    end
    if slots[#slots] ~= dest then slots[#slots + 1] = dest end
    local keys, names = {}, {}
    for i, slot in ipairs(slots) do
        keys[i], names[i] = NodeKey(slot), NodeName(slot)
    end
    return table.concat(keys, ">"), names
end

---------------------------------------------------------------------------
-- Gelernte Zeiten: ezCores Entdecker-Datenbank (Welle 10, DG-06)
---------------------------------------------------------------------------

--[[
    Seit Welle 10 liegen die Flugzeiten in ezCores Datenbank (Tabelle „route“: von-Knoten » nach-Knoten » Liste von
    Wegen { hops, sec, cnt, lo, hi, t }; Schreiber Core.Flights.Note, Leser Core.Flights.Time) – eine Quelle für alle
    Module. Die Strecke bleibt in ezMap die Kette „12>7>3“ (Flights.Route, laufender Flug in ezMapDB.inflight);
    Flights.Parts zerlegt sie in Start, Ziel und Zwischenhalte. Namen der Knoten stehen in ezCores Texten (Art
    „taxi“). Der alte Speicher ezMapDB.flights/flightNames wird einmal übergeben und bleibt liegen (Discovery.lua);
    ohne gespeicherte Ablage schreibt ezMap ihn weiter mit, ohne nutzbare Datenbank arbeitet ezMap allein damit.
]]

-- Knoten-Schlüssel der Datenbank zu einem Glied der Kette („12“ bzw. „n:Goldhain“) oder nil.
local function NodeOf(DB, part)
    if type(part) ~= "string" or part == "" then return nil end
    local name = part:match("^n:(.+)$")
    if name then return DB.Keys.Taxi(nil, name) end
    return DB.Keys.Taxi(tonumber(part))
end

-- Kette „12>7>3“ → Start, Ziel, Zwischenhalte (Knoten-Schlüssel der Datenbank) oder nil.
function Flights.Parts(key)
    local DB = ns.Discovery.DB()
    if not DB or type(key) ~= "string" then return nil end
    local nodes = {}
    for part in key:gmatch("[^>]+") do
        local node = NodeOf(DB, part)
        if node == nil then return nil end
        nodes[#nodes + 1] = node
    end
    if #nodes < 2 then return nil end
    local hops = {}
    for i = 2, #nodes - 1 do hops[#hops + 1] = nodes[i] end
    return nodes[1], nodes[#nodes], hops
end

-- Gelernte Dauer einer Strecke in Sekunden bei normaler Geschwindigkeit oder nil.
function Flights.Seconds(key)
    if not key then return nil end
    local seconds
    if ns.Discovery.Usable() then
        local from, to, hops = Flights.Parts(key)
        local way = from and Core.Flights.Time(from, to, hops)
        seconds = type(way) == "table" and ns.Num(way.sec) or nil
    else
        seconds = ns.Num(ns.db.flights[key])
    end
    if not seconds or seconds <= 0 then return nil end
    return seconds
end

-- Erwartete Dauer in Sekunden (mit Vielflieger) oder nil, wenn die Strecke noch nicht geflogen wurde.
function Flights.Expected(key)
    local seconds = Flights.Seconds(key)
    if not seconds then return nil end
    return seconds / Speed()
end

-- Alle gelernten Wege: { from, to, hops, sec } (Datenbank) bzw. { key, sec, name } (alter Speicher).
local function Ways()
    local list = {}
    local DB = ns.Discovery.DB()
    if DB then
        for _, from in ipairs(DB.KeysOf("route")) do
            for _, to in ipairs(DB.KeysOf("route", from)) do
                for _, way in ipairs(DB.Get("route", from, to) or {}) do
                    local sec = ns.Num(way.sec)
                    if sec and sec > 0 then
                        list[#list + 1] = { from = from, to = to, hops = way.hops or {}, sec = sec }
                    end
                end
            end
        end
    else
        for key, sec in pairs(ns.db.flights) do
            if ns.Num(sec) then list[#list + 1] = { key = key, sec = sec, name = ns.db.flightNames[key] } end
        end
    end
    return list
end
Flights.Ways = Ways

function Flights.Count()
    return #Ways()
end

-- Name eines Knotens aus ezCores Texten (beim Fliegen gemerkt), aus dem Notschlüssel oder „#nodeID“.
function Flights.NodeLabel(node)
    local DB = ns.Discovery.DB()
    if not DB then return tostring(node) end
    local text = DB.Text("taxi", node)
    if type(text) == "string" and text ~= "" then return text end
    local _, _, parts = DB.Keys.ParseFallback(node)
    if type(parts) == "table" and type(parts[#parts]) == "string" then return parts[#parts] end
    return "#" .. tostring(node)
end

-- Gelernte Zeit einer Strecke merken (Datenbank; ohne gespeicherte Ablage auch der alte Speicher).
-- names = Namen der Halte in der Reihenfolge der Kette.
function Flights.Learn(key, names, seconds)
    local DB = ns.Discovery.DB()
    if DB then
        local from, to, hops = Flights.Parts(key)
        if from then
            ns.Discovery.Own(Core.Flights.Note, from, to, hops, seconds)
            local nodes = { from }
            for _, hop in ipairs(hops) do nodes[#nodes + 1] = hop end
            nodes[#nodes + 1] = to
            for i, node in ipairs(nodes) do
                local name = type(names) == "table" and names[i] or nil
                if type(name) == "string" and name ~= "?" and not DB.Keys.IsFallback(node) then
                    ns.Discovery.Own(DB.SetText, "taxi", node, name)
                end
            end
        end
        if ns.Discovery.Moved("flights") then return end
    end
    ns.db.flights[key] = seconds
    if type(names) == "table" and names[1] then ns.db.flightNames[key] = names[1] .. " – " .. names[#names] end
    ns.Discovery.Dirty("flights")       -- die nächste gespeicherte Ablage übernimmt es
end

-- Übergabe des alten Speichers (einmal je Ablage, Discovery.lua): jede Kette bleibt ein eigener Weg; „Start – Ziel“
-- aus flightNames wird Name der beiden Endknoten. Einen Weg, den die Datenbank schon kennt, überspringt sie (nach einer
-- Sitzung ohne gespeicherte Ablage wird noch einmal übergeben, Discovery.Dirty – dann zählt nichts doppelt).
local function ImportOld()
    local DB = ns.Discovery.DB()
    if not DB then return 0 end
    local n = 0
    for key, sec in pairs(ns.db.flights) do
        local from, to, hops = Flights.Parts(key)
        sec = ns.Num(sec)
        if from and sec and sec > 0 and not Core.Flights.Time(from, to, hops) then
            ns.Discovery.Own(DB.Adopt, "route", { from, to }, { hops = hops, sec = sec, cnt = 1, lo = sec, hi = sec },
                ns.Discovery.OldContext())
            local label = ns.db.flightNames[key]
            local first, last
            if type(label) == "string" then first, last = label:match("^(.-) – (.+)$") end
            for node, name in pairs({ [from] = first, [to] = last }) do
                if type(name) == "string" and name ~= "" and not DB.Keys.IsFallback(node) then
                    ns.Discovery.Own(DB.SetText, "taxi", node, name)
                end
            end
            n = n + 1
        end
    end
    return n
end
Flights.ImportOld = ImportOld
ns.Discovery.AddImport("flights", ImportOld)

---------------------------------------------------------------------------
-- Tooltip der Flugpunkte
---------------------------------------------------------------------------

local function AddTooltipLine(dest)
    if not Showing("flightTimes") then return end
    local key = Flights.Route(dest)
    if not key then return end
    local seconds = Flights.Expected(key)
    if seconds then
        Core.TipLine(GameTooltip, L.FLIGHT_TIME:format(ns.Clock(seconds)), "highlight")
    else
        Core.TipLine(GameTooltip, L.FLIGHT_TIME_UNKNOWN, "hint", true)
    end
    GameTooltip:Show()
end
Flights.AddTooltipLine = AddTooltipLine

-- Klassische Flugkarte (TaxiFrame)
local function HookTaxiFrame()
    if type(TaxiNodeOnButtonEnter) ~= "function" then return false end
    hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
        local slot = button and button.GetID and button:GetID()
        if slot and NodeType(slot) == "REACHABLE" then ns.Try("FlightTooltip", AddTooltipLine, slot) end
    end)
    return true
end
if not HookTaxiFrame() then ns.WhenAddOnLoaded("Blizzard_UIPanels_Game", HookTaxiFrame) end

-- Neue Flugkarte (Blizzard_FlightMap, lädt bei Bedarf): Punkte entstehen erst nach dem Laden, deshalb
-- genügt der Haken an Blizzards Mixin.
ns.WhenAddOnLoaded("Blizzard_FlightMap", function()
    if not (FlightMap_FlightPointPinMixin and FlightMap_FlightPointPinMixin.OnMouseEnter) then return end
    local reachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable or 1
    hooksecurefunc(FlightMap_FlightPointPinMixin, "OnMouseEnter", function(pin)
        local data = pin and pin.taxiNodeData
        if ns.IsSecret(data) or type(data) ~= "table" then return end
        local slot = ns.Num(data.slotIndex)
        if slot and Core.Plain(data.state) == reachable then ns.Try("FlightTooltip", AddTooltipLine, slot) end
    end)
end)

---------------------------------------------------------------------------
-- Leiste während des Flugs (Blizzards Zauberleisten-Grafik)
---------------------------------------------------------------------------

local flight        -- { key, names, start (time()), began (Core.Uptime()), speed, expected, started, interrupted, hidden,
                    --   gained, offSince (Core.Uptime() des Ereignisses bzw. der ersten Antwort „kein Flugtier“), unsure }
local preview       -- dasselbe für die Vorschau
local bar

local function Active()
    return preview or (flight and flight.started and flight) or nil
end

local function Destination(f)
    return f.names and f.names[#f.names] or "?"
end

local function UpdateBar()
    -- Die laufende Leiste fragt in ihrem Takt selbst, ob der Flug noch läuft (MAP-N5); endet er, ist sie danach weg.
    if not preview and flight and flight.started then Flights.Check() end
    local f = Active()
    if not f or f.hidden then return bar:Hide() end
    local elapsed = Core.Uptime() - f.began
    if f.expected then
        local left = math.max(0, f.expected - elapsed)
        bar:SetMinMaxValues(0, f.expected)
        bar:SetValue(left)
        bar:SetRole("normal")
        bar.Text:SetText(L.FLIGHT_BAR:format(Destination(f), ns.Clock(left)))
    else
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar:SetRole("gray")
        bar.Text:SetText(L.FLIGHT_BAR_LEARNING:format(Destination(f), ns.Clock(elapsed)))
    end
end

-- Nur diesen Flug (bzw. die Vorschau) ausblenden: Knopf an der Leiste, Rechtsklick zusätzlich. Ganz abschalten
-- geht mit dem Schalter „Leiste während des Flugs“.
function Flights.HideForFlight()
    local f = Active()
    if f then f.hidden = true end
    if bar then bar:Hide() end
    GameTooltip:Hide()
end

-- Weg zum Schalter „Leiste während des Flugs“: seit der Einstellungs-Prüfung vom 19.11.2026 im Abschnitt „Flugzeiten“
-- der Seite (vorher ein Blatt im Baum „Karte: was zeigen“ – die Leiste erscheint nicht auf der Karte)
function Flights.BarSettingPath()
    return Core.SettingsPathText("ezMap", "OPT_HEADER_FLIGHTS", "OPT_flightBar", L)
end

local function BuildBar()
    if bar then return bar end
    -- ezCores Zeitbalken (Core.NewTimerBar, T9-8): Blizzards Statusleisten-Textur mit dem Rand der Zauberleiste;
    -- der Text sitzt wie bei Blizzards Zauberleiste im oberen Teil des Rahmens, in der Schrift wie vorher
    -- (Rolle „value“ = GameFontHighlight; Gegenprüfung D2)
    bar = Core.NewTimerBar(UIParent, { name = "ezMapFlightBar", width = 195, height = 13, border = true, font = "value" })
    bar:SetFrameStrata("MEDIUM")
    bar.Text:ClearAllPoints()
    bar.Text:SetPoint("TOP", bar, "TOP", 0, 5)
    bar.Text:SetSize(185, 16)
    -- Sichtbarer Knopf zum Ausblenden: Blizzards Schließen-Knopf rechts neben dem Rahmen (Leitlinie 3).
    local close = CreateFrame("Button", "ezMapFlightBarClose", bar, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("LEFT", bar, "RIGHT", 10, 0)
    close:SetScript("OnClick", function() Flights.HideForFlight() end)
    close:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, Core.TipAnchor(self))
        Core.TipTitle(GameTooltip, L.FLIGHT_BAR_HIDE)
        Core.TipText(GameTooltip, L.FLIGHT_BAR_HIDE_TIP)
        -- Weg zur Einstellung in ezCores Form (T18-18); der Haken steht im Baum „Karte: was zeigen“
        Core.TipLine(GameTooltip, Flights.BarSettingPath(), "hint", true)
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.CloseButton = close
    bar:EnableMouse(true)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then Flights.HideForFlight() end
    end)
    bar:SetScript("OnEnter", function(self)
        local f = Active()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        Core.TipTitle(GameTooltip, L.FLIGHT_BAR_TITLE)
        if f and f.names then Core.TipText(GameTooltip, table.concat(f.names, " › ")) end
        if f and not f.expected then Core.TipLine(GameTooltip, L.FLIGHT_TIME_UNKNOWN, "hint", true) end
        Core.TipClick(GameTooltip, L.FLIGHT_BAR_HINT)
        Core.TipLine(GameTooltip, L.FLIGHT_BAR_MOVE .. " " .. Core.SettingsPathText("ezMap", nil, "MOVER_BUTTON_LABEL", L),
            "hint", true)
        Core.TipClick(GameTooltip, L.FLIGHT_BAR_LIST)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local since = 0
    bar:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < 0.2 then return end
        since = 0
        UpdateBar()
    end)
    bar:Hide()
    return bar
end

-- Standardplatz: angedockt unter Blizzards Behälter für Atem-, Erschöpfungs- und Verstellen-Leiste
-- (MirrorTimerContainer, oben in der Mitte) – die Flugleiste wandert mit ihm und rutscht nach unten, wenn dort
-- eine Leiste erscheint (Entscheidung des Nutzers 13.11.2026: andocken, wo es passt). Fehlt der Behälter, bleibt
-- der alte feste Platz an derselben Stelle. Verschieben über ezCore.Mover (Bearbeitungsmodus oder Knopf „Teile
-- verschieben“ auf der Einstellungsseite); die Auswahl erscheint auch, solange die Leiste versteckt ist. Deshalb
-- entsteht sie schon beim Einloggen.
Flights.ANCHOR_MIRROR = { "TOP", "MirrorTimerContainer", "BOTTOM", 0, -24 }
Flights.ANCHOR_FALLBACK = { "TOP", "UIParent", "TOP", 0, -120 }
Flights.ANCHOR = Flights.ANCHOR_FALLBACK

function Flights.DefaultAnchor()
    local container = rawget(_G, "MirrorTimerContainer")
    if type(container) == "table" and type(container.GetObjectType) == "function" then return Flights.ANCHOR_MIRROR end
    return Flights.ANCHOR_FALLBACK
end

-- Blizzards Behälter ist leer, solange keine seiner Leisten läuft. Hätte er dann keine Fläche, hinge die Flugleiste
-- im Nichts (keine Oberkante): zurück auf den festen Platz. Eine verschobene Leiste hängt an UIParent und bleibt.
function Flights.CheckAnchor()
    if not (bar and bar.GetTop) then return false end
    local top = bar:GetTop()
    if ns.IsSecret(top) or top ~= nil then return false end
    local a = Flights.ANCHOR_FALLBACK
    bar:ClearAllPoints()
    bar:SetPoint(a[1], UIParent, a[3], a[4], a[5])
    return true
end

ns.OnReady(function()
    BuildBar()
    Flights.ANCHOR = Flights.DefaultAnchor()
    if ezCore.Mover and ezCore.Mover.Register then
        Flights.part = ezCore.Mover.Register(bar, { key = "ezMap.flight", label = L.MOVER_FLIGHT_BAR, owner = "ezMap",
            anchor = Flights.ANCHOR })
    else
        local a = Flights.ANCHOR
        bar:SetPoint(a[1], rawget(_G, a[2]) or UIParent, a[3], a[4], a[5])
    end
end)

function Flights.RefreshBar()
    local f = Active()
    if f and (preview or Showing("flightBar")) and not f.hidden then
        BuildBar():Show()
        Flights.CheckAnchor()
        UpdateBar()
    elseif bar then
        bar:Hide()
    end
end

-- Vorschau (Einstellungen): eine erfundene Strecke, zehn Sekunden lang.
function Flights.Preview()
    preview = { names = { L.PREVIEW_FROM, L.PREVIEW_TO }, began = Core.Uptime(), expected = 75 }
    Flights.RefreshBar()
    local mine = preview
    C_Timer.After(10, function()
        if preview == mine then
            preview = nil
            Flights.RefreshBar()
        end
    end)
end

function Flights.BarShown()
    return bar ~= nil and bar:IsShown()
end

function Flights.Bar() return bar end

---------------------------------------------------------------------------
-- Flug verfolgen und lernen
---------------------------------------------------------------------------

local function Save(f)
    ns.db.inflight = f and { key = f.key, names = f.names, start = f.start, speed = f.speed, expected = f.expected } or nil
end

local function Stop()
    flight = nil
    Save(nil)
    Flights.RefreshBar()
end

-- Eigener Takt während des Flugs (MAP-N5): fragt auch, wenn die Leiste aus oder ausgeblendet ist oder ein anderes
-- Addon die Flugzeiten zeigt. Endet, sobald dieser Flug vorbei ist.
local function Watch(f)
    C_Timer.After(Flights.WATCH_EVERY, function()
        if flight ~= f then return end
        ns.Try("FlightWatch", Flights.Check)
        if flight == f then Watch(f) end
    end)
end

local function Started()
    if not flight then return end
    flight.started = true
    Watch(flight)
    Flights.RefreshBar()
    if Flights.BarShown() then ns.Try("Guide", ns.Guide.Start) end     -- Erklärblase beim ersten Flug
end

-- Flug zu Ende: Zeit lernen (nicht nach einem Abbruch, nicht bei gesperrter Antwort) und die Leiste schließen.
-- at = Zeitpunkt der Landung (Core.Uptime), sonst jetzt.
local function Landed(at)
    local f = flight
    if not f then return end
    local taken = math.floor(((at or Core.Uptime()) - f.began) * (f.speed or 1) + 0.5)
    if not f.interrupted and not f.unsure and taken >= MIN_FLIGHT then
        local old = Flights.Seconds(f.key)
        Flights.Learn(f.key, f.names, taken)
        if type(old) ~= "number" or math.abs(old - taken) > TOLERANCE then
            ns.Print(L.FLIGHT_LEARNED:format(f.names[1], f.names[#f.names], ns.Clock(taken / (f.speed or 1))))
        end
    end
    Stop()
end

-- Start über Blizzards Flugkarte (beide Varianten rufen TakeTaxiNode).
local function OnTakeTaxi(slot)
    if type(UnitAffectingCombat) == "function" and Core.Bool(UnitAffectingCombat("player"), false) then return end
    local key, names = Flights.Route(slot)
    if not key then return end
    local speed = Speed()
    flight = { key = key, names = names, start = time(), began = Core.Uptime(), speed = speed,
        expected = Flights.Expected(key) }
    Save(flight)
    C_Timer.After(1, function()
        if not flight or flight.key ~= key then return end
        if OnTaxi() then Started() else Stop() end
    end)
end
if type(TakeTaxiNode) == "function" then
    hooksecurefunc("TakeTaxiNode", function(slot) ns.Try("TakeTaxiNode", OnTakeTaxi, slot) end)
end

-- Abbrüche: früher landen, Beschwörung, Schlachtfeld – die Zeit passt dann nicht zur Strecke.
local function Interrupted()
    if flight then flight.interrupted = true end
end
if type(TaxiRequestEarlyLanding) == "function" then hooksecurefunc("TaxiRequestEarlyLanding", Interrupted) end
if type(AcceptBattlefieldPort) == "function" then hooksecurefunc("AcceptBattlefieldPort", Interrupted) end
if C_SummonInfo and type(C_SummonInfo.ConfirmSummon) == "function" then
    hooksecurefunc(C_SummonInfo, "ConfirmSummon", Interrupted)
end

--[[
    Ende des Flugs (MAP-N5, Fund des Nutzers im Probe-Lauf 14.11.2026: die Leiste lief nach der Landung weiter).
    Früher hing es allein an PLAYER_CONTROL_GAINED mit „UnitOnTaxi nicht mehr wahr“ – meldete UnitOnTaxi in dem
    Augenblick noch wahr oder blieb das Ereignis aus, lief die Leiste weiter. Jetzt:
      - PLAYER_CONTROL_GAINED: ohne Flugtier sofort gelandet (wie bisher); meldet UnitOnTaxi noch wahr, fragt ezMap
        nach RECHECK Sekunden erneut – ist der Flug dann vorbei, zählt der Zeitpunkt des Ereignisses
      - die laufende Leiste (UpdateBar) und ein eigener Takt (Watch, alle WATCH_EVERY Sekunden) fragen selbst; zwei
        Antworten „kein Flugtier“ im Abstand von OFF_CONFIRM Sekunden beenden den Flug (Zeitpunkt: die erste)
      - Deckel: weit über der erwarteten Zeit (OVERDUE_FACTOR, mindestens OVERDUE_MIN Sekunden darüber; ohne
        erwartete Zeit FLIGHT_MAX) endet die Leiste und ezMap lernt nichts
      - gesperrte Antwort = kein Flugtier (Leitlinie 6); gelernt wird dann nichts (f.unsure)
]]
Flights.RECHECK = { 1, 3 }
Flights.WATCH_EVERY = 1
Flights.OFF_CONFIRM = 0.5
Flights.OVERDUE_FACTOR, Flights.OVERDUE_MIN = 1.5, 60
Flights.FLIGHT_MAX = 1800

-- Längste Dauer dieses Flugs, bevor der Deckel greift (Sekunden seit dem Start).
function Flights.Limit(f)
    if type(f) ~= "table" then return Flights.FLIGHT_MAX end
    local expected = f.expected
    if type(expected) ~= "number" or expected <= 0 then return Flights.FLIGHT_MAX end
    return expected + math.max(Flights.OVERDUE_MIN, expected * (Flights.OVERDUE_FACTOR - 1))
end

-- Läuft der Flug noch? Beendet ihn, wenn nicht. → true, wenn er damit endete.
function Flights.Check()
    local f = flight
    if not (f and f.started) then return false end
    local now = Core.Uptime()
    local onTaxi, secret = OnTaxi()
    if onTaxi then
        f.offSince, f.unsure = nil, nil     -- eine einzelne gesperrte Antwort mitten im Flug zählt nicht
        -- ein PLAYER_CONTROL_GAINED mitten im Flug zählt nach den erneuten Prüfungen nicht mehr als Landung
        if f.gained and now - f.gained > Flights.RECHECK[#Flights.RECHECK] + 0.5 then f.gained = nil end
        if now - f.began > Flights.Limit(f) then
            f.interrupted = true
            Landed()
            return true
        end
        return false
    end
    if secret then f.unsure = true end
    if f.gained then
        Landed(f.gained)
        return true
    end
    if not f.offSince then
        f.offSince = now
        return false
    end
    if now - f.offSince >= Flights.OFF_CONFIRM then
        Landed(f.offSince)
        return true
    end
    return false
end

ns.On("PLAYER_CONTROL_GAINED", function()
    local f = flight
    if not (f and f.started) then return end
    local onTaxi, secret = OnTaxi()
    if not onTaxi then
        if secret then f.unsure = true end
        return Landed()
    end
    f.gained = Core.Uptime()
    for _, delay in ipairs(Flights.RECHECK) do
        C_Timer.After(delay, function()
            if flight == f then ns.Try("FlightWatch", Flights.Check) end
        end)
    end
end)

-- Nach /reload mitten im Flug weiter messen (sekundengenau über time()).
ns.On("PLAYER_ENTERING_WORLD", function()
    local saved = ns.db and ns.db.inflight
    if type(saved) ~= "table" or not saved.key then return end
    if not OnTaxi() then return Stop() end
    flight = { key = saved.key, names = saved.names or { "?" }, start = saved.start, speed = saved.speed or 1,
        expected = saved.expected, began = Core.Uptime() - math.max(0, time() - (saved.start or time())) }
    Started()
end)

ns.OnSettingChanged(function(key)
    if key == "flightBar" then Flights.RefreshBar() end
end)

---------------------------------------------------------------------------
-- Nächster Flugmeister (Menü „Aufspüren“ der Minikarte, Tracking.lua)
---------------------------------------------------------------------------

-- Blizzards Flugpunkte einer Karte (C_TaxiMap.GetTaxiNodesForMap, so zeigt sie Blizzards Weltkarte):
-- eigene Fraktion und neutrale, auch noch nicht entdeckte – gerade die sucht man.
local function FitsFaction(node)
    local enum = Enum and Enum.FlightPathFaction
    if node.faction == (enum and enum.Horde or 1) then return ns.faction == nil or ns.faction == "Horde" end
    if node.faction == (enum and enum.Alliance or 2) then return ns.faction == nil or ns.faction == "Alliance" end
    return true
end

local function NodesOn(mapID)
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
    if not ok or ns.IsSecret(nodes) or type(nodes) ~= "table" then return {} end
    local out = {}
    for _, node in ipairs(nodes) do
        local x, y = Core.Map.XY(type(node) == "table" and node.position or nil)
        local name = node and node.name
        if x and y and not ns.IsSecret(name) and type(name) == "string" and FitsFaction(node) then
            out[#out + 1] = { name = name:match("^[^,]+") or name, map = mapID, x = x, y = y,
                id = ns.Num(node.nodeID), undiscovered = node.isUndiscovered == true }
        end
    end
    return out
end

-- Nächster Flugmeister zu einer Stelle (Karte, x, y von 0 bis 1): ihre Karte und die darüber bis zum Kontinent,
-- gemessen in Weltkoordinaten (ohne sie nur auf dieser einen Karte). Mit knownOnly zählen nur entdeckte Flugmeister
-- (von denen du abfliegen kannst). Rückgabe { name, map, x, y, id (Blizzards Knoten-ID oder nil), distance,
-- undiscovered } oder nil.
function Flights.NearestMasterTo(mapID, px, py, knownOnly)
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return nil end
    mapID, px, py = ns.Num(mapID), ns.Num(px), ns.Num(py)
    if not (mapID and px and py) then return nil end
    local continent, wx, wy = ns.WorldPos(mapID, px, py)
    local continentType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
    local best
    local id, depth = mapID, 0
    while id and depth < 6 do
        for _, node in ipairs(NodesOn(id)) do
            local d
            if continent then
                local c, nx, ny = ns.WorldPos(node.map, node.x, node.y)
                if c == continent then d = math.sqrt((nx - wx) ^ 2 + (ny - wy) ^ 2) end
            elseif id == mapID then
                d = math.sqrt((node.x - px) ^ 2 + (node.y - py) ^ 2)
            end
            if d and not (knownOnly and node.undiscovered) and (not best or d < best.distance) then
                node.distance = d
                best = node
            end
        end
        local info = Core.Map.Info(id)
        local mapType = info and ns.Num(info.mapType)
        if not continent or not info or (mapType and mapType <= continentType) then break end
        id, depth = ns.Num(info.parentMapID), depth + 1
    end
    return best
end

-- Nächster Flugmeister von deinem Standort aus (Menü „Aufspüren“: auch ein noch nicht entdeckter – gerade den
-- sucht man). Mit knownOnly der nächste entdeckte: der Start eines Flugs.
function Flights.NearestMaster(knownOnly)
    local mapID, px, py = ns.PlayerPosition()
    if not mapID then return nil end
    return Flights.NearestMasterTo(mapID, px, py, knownOnly)
end

function Flights.MasterLabel(master)
    local text = master.undiscovered and L.TRACK_FLIGHT_NEW or L.TRACK_FLIGHT
    return text:format(master.name)
end

function Flights.GoMaster(master)
    return ns.Way.Set(master.map, master.x, master.y, master.name, true)
end

---------------------------------------------------------------------------
-- Flugmeister am Ziel der Markierung und gelernte Flugzeit dorthin (Kartenmenü, Menü „Aufspüren“)
---------------------------------------------------------------------------

-- Kleine Stufe statt Routenplaner (Vollprüfung 14.11.2026, Frage 30 – Empfehlung umgesetzt, Antwort offen): ezMap
-- nennt den Flugmeister, der dem Ziel am nächsten liegt, und die Flugzeit von deinem nächsten entdeckten Flugmeister
-- dorthin (von einem unentdeckten kann keine Strecke gelernt sein) – aber nur, wenn du genau diese Strecke schon
-- geflogen bist (Quelle „bei dir gemessen“). Sonst „noch unbekannt“. Kein Umsteigen, keine Schätzung, keine Tabelle.

-- Erster und letzter Halt einer gelernten Strecke („12>7>3“ bzw. „n:Sturmwind>n:Goldhain“) oder nil.
local function RouteEnds(key)
    if type(key) ~= "string" or not key:find(">", 1, true) then return nil end
    return key:match("^([^>]+)"), key:match("([^>]+)$")
end

-- Ist dieser Halt der Flugmeister? Strecken merken die Knoten-ID, ohne sie den Namen („n:Name“, Flights.Route).
local function IsMaster(stop, master)
    if master.id ~= nil and stop == tostring(master.id) then return true end
    return type(master.name) == "string" and stop == "n:" .. master.name
end

-- Derselbe Flugmeister? (gleiche Knoten-ID, sonst gleicher Name auf derselben Karte)
function Flights.SameMaster(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if a.id ~= nil and b.id ~= nil then return a.id == b.id end
    return a.name == b.name and a.map == b.map
end

-- Gelernte Flugzeit vom einen Flugmeister zum anderen in Sekunden (mit Vielflieger, wie im Tooltip der Flugkarte)
-- oder nil, wenn du diese Strecke noch nicht geflogen bist. Gibt es sie mit verschiedenen Zwischenhalten, zählt
-- die kürzeste. Nur genau diese Richtung – der Rückflug kann anders lang sein.
function Flights.TimeBetween(from, to)
    if type(from) ~= "table" or type(to) ~= "table" then return nil end
    local best
    local DB = ns.Discovery.DB()
    if DB then
        -- Knoten-Schlüssel der Datenbank: die Knoten-ID, sonst der Notschlüssel aus dem Namen (Strecke ohne IDs)
        local function NodesOf(master)
            local list = {}
            local id = master.id ~= nil and DB.Keys.Taxi(master.id) or nil
            local byName = type(master.name) == "string" and DB.Keys.Taxi(nil, master.name) or nil
            if id ~= nil then list[#list + 1] = id end
            if byName ~= nil then list[#list + 1] = byName end
            return list
        end
        for _, a in ipairs(NodesOf(from)) do
            for _, b in ipairs(NodesOf(to)) do
                for _, way in ipairs(DB.Get("route", a, b) or {}) do
                    local seconds = ns.Num(way.sec)
                    if seconds and seconds > 0 then
                        seconds = seconds / Speed()
                        if not best or seconds < best then best = seconds end
                    end
                end
            end
        end
        return best
    end
    for key in pairs(ns.db.flights) do
        local first, last = RouteEnds(key)
        if first and IsMaster(first, from) and IsMaster(last, to) then
            local seconds = Flights.Expected(key)
            if seconds and (not best or seconds < best) then best = seconds end
        end
    end
    return best
end

-- Zur gesetzten Markierung: Flugmeister am Ziel, dein nächster entdeckter Flugmeister (oder nil) und die gelernte
-- Flugzeit zwischen beiden in Sekunden (oder nil). Ohne Markierung oder ohne Flugpunkte vom Client: nil.
function Flights.AtWaypoint()
    local mapID, x, y = ns.Way.Get()
    if not mapID then return nil end
    local dest = Flights.NearestMasterTo(mapID, x, y)
    if not dest then return nil end
    local own = Flights.NearestMaster(true)
    local seconds
    if own and not Flights.SameMaster(own, dest) then seconds = Flights.TimeBetween(own, dest) end
    return dest, own, seconds
end

-- „Flugmeister am Ziel: Späherkuppe“
function Flights.DestinationLabel(dest)
    local text = dest.undiscovered and L.MENU_FLIGHT_DEST_NEW or L.MENU_FLIGHT_DEST
    return text:format(dest.name)
end

-- Zeile darunter mit der Quelle der Angabe: „Flugzeit Goldhain – Späherkuppe: 3:20 (bei dir gemessen)“, „… noch
-- unbekannt (noch nicht geflogen)“ oder der Hinweis, dass es derselbe Flugmeister ist. Ohne eigenen Flugmeister nil.
function Flights.DestinationTimeLabel(dest, own, seconds)
    if not own then return nil end
    if Flights.SameMaster(own, dest) then return L.MENU_FLIGHT_DEST_SAME end
    if seconds then return L.MENU_FLIGHT_DEST_TIME:format(own.name, dest.name, ns.Clock(seconds)) end
    return L.MENU_FLIGHT_DEST_TIME_UNKNOWN:format(own.name, dest.name)
end

---------------------------------------------------------------------------
-- Liste und Status
---------------------------------------------------------------------------

function Flights.PrintList()
    local rows = {}
    for _, way in ipairs(Ways()) do
        local name = way.name or way.key
        if way.from ~= nil then name = Flights.NodeLabel(way.from) .. " – " .. Flights.NodeLabel(way.to) end
        rows[#rows + 1] = { name = tostring(name), seconds = way.sec }
    end
    if #rows == 0 then return ns.Print(L.FLIGHT_LIST_EMPTY) end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.seconds < b.seconds
    end)
    ns.Print(L.FLIGHT_LIST:format(#rows))
    for _, row in ipairs(rows) do ns.Print(("  %s: %s"):format(row.name, ns.Clock(row.seconds))) end
end

-- Alle gelernten Flugzeiten vergessen: in ezCores Datenbank und im alten Speicher (sonst kämen sie beim nächsten
-- Anmelden wieder).
function Flights.Reset()
    local DB = ns.Discovery.DB()
    if DB then
        for _, from in ipairs(DB.KeysOf("route")) do DB.Forget("route", from) end
    end
    wipe(ns.db.flights)
    wipe(ns.db.flightNames)
    ns.Print(L.FLIGHT_RESET_DONE)
end

ns.AddStatusLine(function()
    local other = ns.FlightTimesElsewhere()
    if other then return L.STATUS_FLIGHTS_OTHER:format(Flights.Count(), other) end
    return L.STATUS_FLIGHTS:format(Flights.Count())
end)
