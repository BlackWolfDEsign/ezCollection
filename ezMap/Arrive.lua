local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Kartenmarkierung bei Ankunft entfernen (Wunsch des Nutzers vom 16.11.2026, wörtlich: „wenn man eine
    kartenmarkierung erreicht, dann sollte diese nach 3 oder 5sekunden verschwinden“). Gilt für Blizzards eigene
    Markierung (C_Map.SetUserWaypoint), egal wer sie gesetzt hat: /way, Kartenmenü, Strg+Klick auf die Karte,
    ezCraft „Wo“, Sammel-Fundorte, Lehrer …

    Erkennung (Leitlinie 11, der Client zuerst):
      - Blizzards Ereignis NAVIGATION_DESTINATION_REACHED (Forever-Quelle: Blizzard_APIDocumentationGenerated/
        InGameNavigationDocumentation.lua). Blizzards SuperTrackedFrame (Blizzard_QuestNavigation) beendet darauf nur die
        Zielverfolgung; die Markierung selbst bleibt auf der Karte stehen – deshalb dieses Modul. Das Ereignis kommt
        nur, solange die Markierung verfolgt wird; isWaypoint = true meint einen Zwischenpunkt des Weges und zählt nicht.
      - sonst die eigene Rechnung: eigene Position (Core.PlayerPosition) und Markierung in Blizzards Weltkoordinaten
        (Core.Map.WorldPos, Yards), alle Arrive.EVERY Sekunden – nur, solange eine Markierung steht und der Schalter an ist.
      C_Navigation.GetDistance nimmt ezMap nicht: Es misst zum Ziel der Zielverfolgung (auf einem Weg mit Zwischenpunkten
      zu diesem) und hat nichts mehr zu messen, sobald Blizzard die Zielverfolgung bei Ankunft beendet – also gerade in
      der Wartezeit, in der ezMap prüft, ob der Spieler wieder geht.
    Regeln:
      - Ankunft zählt erst, wenn der Spieler seit dem Setzen einmal weiter als Arrive.RADIUS weg war („erreichen“
        heißt hinlaufen): /way hier und „Eigene Position“ bleiben stehen, solange er dort ist; kommt er später zurück,
        verschwinden sie wie jede andere Markierung.
      - Wartezeit 3 oder 5 Sekunden (Einstellung wayAutoClearDelay); geht der Spieler vorher weiter als Arrive.LEAVE
        weg, bleibt die Markierung.
      - Jede neue Markierung beginnt von vorn (Arrive.Restart nach jedem C_Map.SetUserWaypoint, auch für dieselbe
        Stelle und von außen gesetzt; Blizzards USER_WAYPOINT_UPDATED mit neuer Lage): eine während der Wartezeit
        gesetzte wird nicht gelöscht.
      - Gilt Blizzards Ereignis etwas anderem (Quest, Vignette, Kartenpunkt), zählt es nicht; die Art merkt sich ezMap
        vorher (SUPER_TRACKING_CHANGED), weil Blizzard die Zielverfolgung bei Ankunft schon beendet hat.
      - Ohne eigene Position (Instanz, gesperrter Wert, Markierung auf einer Karte ohne Weltlage) löscht ezMap nichts;
        eine laufende Wartezeit endet.
      - Die Markierung einer Route, der du folgst, bleibt (Route.OwnsWaypoint): die Route rückt nach der Ernte selbst weiter.
        Ebenso jede Markierung mit Besitzer (Way.Owner, Welle 27 – etwa ezQuests Leveling-Route, die nach erfülltem Ziel
        bzw. der Abgabe selbst weiterrückt).
      - Rücksicht (Leitlinie 9): übernimmt ein fremdes Addon das Entfernen (ezCores Erkennung „wayArrival“, bisher ist
        keines belegt – TomTom verwaltet eigene Wegpunkte, nicht Blizzards Markierung), entfernt ezMap nichts.
      - Still: ezMap hat keine Einstellung „Meldungen“; Blizzard meldet die Ankunft selbst, wenn die Zielverfolgung lief.
    Taint-sicher (Leitlinie 5): nur C_Map.ClearUserWaypoint über Way.Clear (per pcall), nichts in Blizzards Tabellen.
    Mit der Markierung endet auch die Zielverfolgung; C_SuperTrack.SetSuperTrackedUserWaypoint ruft ezMap dafür nicht
    (V-183: laut Forevers Entwickler-Hinweisen nicht aus Addon-Code).
]]
local Arrive = {}
ns.Arrive = Arrive

-- Ankunft: 10 Yards. Blizzards eigener Wert steckt im Client, nicht in der Lua-Quelle. 10 Yards sind einige Schritte:
-- genug für die Ungenauigkeit von /way-Koordinaten (eine Nachkommastelle ist auf einer Zone von 1000 Yards Breite
-- 1 Yard) und von selbst gesammelten Fundorten, die um ein paar Yards streuen; eng genug, dass man wirklich da ist.
Arrive.RADIUS = 10
-- Verlassen: 20 Yards (doppelter Umkreis). Wer um ein Kraut herumläuft oder dort kämpft, bricht die Wartezeit nicht ab,
-- und Blizzards Ereignis darf die Ankunft etwas außerhalb von RADIUS melden.
Arrive.LEAVE = 20
Arrive.EVERY = 0.5          -- Sekunden zwischen zwei Prüfungen (nur, solange eine Markierung steht)
Arrive.DELAYS = { 3, 5 }    -- Auswahl der Wartezeit in Sekunden (Wortlaut des Wunsches: „3 oder 5sekunden“)
Arrive.DEFAULT_DELAY = 5

-- Erlaubte Werte beim Einfügen einer Sicherung (Core.ValidSetting liest ns.CHOICES): wayAutoClearDelay hat keine eigene
-- Zeile auf der Seite (gemeinsame Auswahl „wayAutoClear“), darum meldet die Seite seine Werte nicht selbst an
-- (Nachlauf des code-reviewers vom 20.11.2026)
ns.CHOICES = ns.CHOICES or {}
ns.CHOICES.wayAutoClearDelay = {}
for i, seconds in ipairs(Arrive.DELAYS) do ns.CHOICES.wayAutoClearDelay[i] = tostring(seconds) end

-- key: welche Markierung; armed: der Spieler war seit dem Setzen einmal weiter als RADIUS weg; since: GetTime() der
-- Ankunft, solange die Wartezeit läuft
local state = {}
local ticker

local function Reset(key)
    state = { key = key }
end

-- Wartezeit in Sekunden: 3 oder 5 (gespeichert als Text, Blizzards Auswahlfeld kennt nur Text)
function Arrive.Delay()
    local value = tonumber(ns.S and ns.S.wayAutoClearDelay)
    for _, allowed in ipairs(Arrive.DELAYS) do
        if value == allowed then return value end
    end
    return Arrive.DEFAULT_DELAY
end

-- Auswahl für Blizzards Auswahlfeld: { { "3", "3 Sek." }, { "5", "5 Sek." } }
function Arrive.DelayValues()
    local values = {}
    for i, seconds in ipairs(Arrive.DELAYS) do values[i] = { tostring(seconds), Core.Seconds(seconds) } end
    return values
end

-- EINE Auswahl auf der Einstellungsseite statt Haken und Wartezeit (Einstellungs-Prüfung vom 19.11.2026, Nr. 82, 83;
-- der Wunsch vom 16.11.2026 „nach 3 oder 5 Sekunden“ bleibt): "0" = aus, sonst die Wartezeit. Gespeichert bleiben
-- wayAutoClear (Schlüssel der Einführung) und wayAutoClearDelay – „Aus“ lässt die gewählte Zeit stehen.
Arrive.OFF = "0"
function Arrive.ChoiceValues()
    local values = { { Arrive.OFF, L.ARRIVE_CHOICE_OFF } }
    for _, entry in ipairs(Arrive.DelayValues()) do
        values[#values + 1] = { entry[1], L.ARRIVE_CHOICE_AFTER:format(entry[2]) }
    end
    return values
end

-- Stand der Auswahl: "0" oder "3"/"5"
function Arrive.Choice()
    if not ns.Enabled("wayAutoClear") then return Arrive.OFF end
    return tostring(Arrive.Delay())
end

-- Auswahl setzen: "0" schaltet aus, eine erlaubte Wartezeit schaltet ein und merkt sie → true, wenn gültig
function Arrive.SetChoice(value)
    value = tostring(value)
    if value == Arrive.OFF then
        ns.SetSetting("wayAutoClear", false)
        return true
    end
    for _, allowed in ipairs(Arrive.DELAYS) do
        if value == tostring(allowed) then
            ns.SetSetting("wayAutoClearDelay", value)
            ns.SetSetting("wayAutoClear", true)
            return true
        end
    end
    return false
end

-- Markierung als Schlüssel (Karte und Lage) oder nil
local function Key()
    local m, x, y = ns.Way.Get()
    if not m then return nil end
    return ("%d:%.4f:%.4f"):format(m, x, y)
end

-- Weltlage der Markierung, gemerkt je Lage (die Markierung steht still; der Ticker fragt alle EVERY Sekunden)
local world = {}
local function WaypointWorld(wm, wx, wy)
    if world.m ~= wm or world.wx ~= wx or world.wy ~= wy then
        local c, x, y = Core.Map.WorldPos(wm, wx, wy)
        world = { m = wm, wx = wx, wy = wy, c = c, x = x, y = y }
    end
    return world.c, world.x, world.y
end

-- Entfernung zur Markierung in Yards. nil: nicht zu sagen (keine Markierung, keine eigene Position, keine Weltlage);
-- math.huge: auf einem anderen Kontinent.
function Arrive.Distance()
    local wm, wx, wy = ns.Way.Get()
    if not wm then return nil end
    local pm, px, py = Core.PlayerPosition()
    if not pm then return nil end
    local c1, ax, ay = Core.Map.WorldPos(pm, px, py)
    local c2, bx, by = WaypointWorld(wm, wx, wy)
    if not (c1 and c2) then return nil end
    if c1 ~= c2 then return math.huge end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Selber Ort? Die Weltlage kennt keine Höhe: in der Stadt über einer Unterstadt (Dalaran, Ruinen von Lordaeron), am
-- Hang über einer Höhle mit eigener Kleinkarte oder fliegend über der Stelle wäre die Entfernung klein, obwohl der
-- Spieler nicht dort ist (Fund des code-reviewers vor dem Merge, 16.11.2026). Darum zählt eine Ankunft nur, wenn die
-- Karte passt: Ist eine der beiden Karten ein Dungeon oder eine Kleinkarte (Enum.UIMapType 4 bzw. 5), müssen beide
-- gleich sein; sonst muss die Karte der Markierung die des Spielers oder eine ihrer Elternkarten sein. Unbekannte
-- Karten zählen nicht (lieber stehen lassen als falsch löschen). Fürs Verlassen bleibt allein die Entfernung.
local DEEP = { [4] = true, [5] = true }
local function MapTypeAndParent(mapID)
    local info = Core.Map.Info(mapID)
    if not info then return nil, nil end
    return ns.Num(info.mapType), ns.Num(info.parentMapID)
end

function Arrive.SamePlace(playerMap, wayMap)
    if not (playerMap and wayMap) then return false end
    if playerMap == wayMap then return true end
    local playerType = MapTypeAndParent(playerMap)
    local wayType = MapTypeAndParent(wayMap)
    if (playerType and DEEP[playerType]) or (wayType and DEEP[wayType]) then return false end
    local id = playerMap
    for _ = 1, Core.Map.MAX_DEPTH or 8 do
        local _, parent = MapTypeAndParent(id)
        if not parent or parent == 0 then return false end
        if parent == wayMap then return true end
        id = parent
    end
    return false
end

-- Fliegt der Spieler? (Blizzards IsFlying; gesperrt oder unbekannt: nein)
local function Flying()
    local query = rawget(_G, "IsFlying")
    if type(query) ~= "function" then return false end
    return Core.Bool(Core.Call(query), false) == true
end

-- Darf hier eine Ankunft zählen? Karte passt (Arrive.SamePlace) und der Spieler fliegt nicht.
function Arrive.Here()
    local wm = ns.Way.Get()
    local pm = Core.PlayerPosition()
    return Arrive.SamePlace(pm, wm) and not Flying()
end

-- Fremdes Addon, das das Entfernen übernimmt (Name) oder nil. Info: ohne Zählung (Statuszeile).
local function Elsewhere(info)
    if info then return Core.WhoHandlesInfo and Core.WhoHandlesInfo("wayArrival") or nil end
    return ns.OtherFor("wayArrival")
end

local function RouteOwns()
    local Route = ns.Route
    if Route ~= nil and type(Route.OwnsWaypoint) == "function" and Route.OwnsWaypoint() == true then return true end
    -- die Sammel-Route entscheidet selbst (folgt der Spieler ihr nicht mehr, darf die Markierung weg); jeder andere
    -- Besitzer hält sie (Welle 27)
    local owner = type(ns.Way.Owner) == "function" and ns.Way.Owner() or nil
    return owner ~= nil and not (Route ~= nil and owner == Route.PROVIDER)
end

-- Läuft gerade die Wartezeit? → Sekunden seit der Ankunft oder nil (für Tests und die Statuszeile)
function Arrive.Waiting()
    return state.since and (GetTime() - state.since) or nil
end

-- Ankunft festhalten (beide Wege): nur mit vorherigem Abstand, nicht bei Routen-Markierungen, nicht neben einem
-- Addon, das das Entfernen übernimmt. → true, wenn die Wartezeit läuft
local function Arrived()
    if state.since then return true end
    if not state.armed or RouteOwns() then return false end
    if Elsewhere() then
        state.armed = false     -- je Ankunft einmal weichen, nicht bei jeder Prüfung
        return false
    end
    state.since = GetTime()
    return true
end

-- Wartezeit abgelaufen: Markierung entfernen (Way.Clear, still)
local function Finish()
    Reset(nil)
    ns.Way.Clear()
end

-- Eine Prüfung (Ticker und Tests)
function Arrive.Check()
    if not (ns.db and ns.Enabled("wayAutoClear")) then return Arrive.Update() end
    local key = Key()
    if not key then return Arrive.Update() end
    if key ~= state.key then Reset(key) end
    local d = Arrive.Distance()
    if not d then
        state.since = nil       -- ohne Position nie löschen
        return
    end
    if d > Arrive.RADIUS then state.armed = true end
    if state.since and d > Arrive.LEAVE then state.since = nil end
    if not state.since and d <= Arrive.RADIUS and Arrive.Here() then Arrived() end
    if state.since and GetTime() - state.since >= Arrive.Delay() then Finish() end
end

-- Was verfolgt Blizzard gerade? → Enum.SuperTrackingType oder nil (nichts, unbekannt oder gesperrt)
local function TrackedKind()
    local query = C_SuperTrack and C_SuperTrack.GetHighestPrioritySuperTrackingType
    if type(query) ~= "function" then return nil end
    local ok, kind = pcall(query)
    return ok and ns.Num(kind) or nil
end

-- Zuletzt verfolgte Art. Blizzards SuperTrackedFrame (Forever-Quelle: Blizzard_QuestNavigation/SuperTrackedFrame.lua)
-- beendet bei NAVIGATION_DESTINATION_REACHED die Zielverfolgung (C_SuperTrack.ClearAllSuperTracked) für die
-- Kartenmarkierung, Vignetten und die meisten Kartenpunkte, bevor ezMap das Ereignis sieht (Blizzards Rahmen meldet
-- sich vor jedem Addon an). Dann meldet die Abfrage nichts mehr; was vorher verfolgt wurde, merkt sich ezMap bei
-- SUPER_TRACKING_CHANGED. Ein „nichts“ überschreibt die gemerkte Art nicht: das kommt gerade beim Beenden.
local lastKind
local function NoteKind()
    local kind = TrackedKind()
    if kind then lastKind = kind end
end

-- Blizzards Ereignis: Ziel erreicht (nur, wenn die Markierung verfolgt wurde). Zählt innerhalb von LEAVE, weil der
-- Client seinen eigenen Umkreis hat; vorheriger Abstand und Position bleiben Bedingung.
function Arrive.OnReached(isWaypoint)
    if ns.IsSecret(isWaypoint) or isWaypoint == true then return false end
    if not (ns.db and ns.Enabled("wayAutoClear")) then return false end
    -- verfolgt(e) Blizzard etwas anderes als die Markierung (Quest, Vignette, Kartenpunkt), gilt das Ereignis jenem;
    -- ohne bekannte Art trägt allein die Entfernungsgrenze LEAVE
    local kinds = Enum and Enum.SuperTrackingType
    if type(kinds) == "table" and type(kinds.UserWaypoint) == "number" then
        local kind = TrackedKind() or lastKind
        if kind and kind ~= kinds.UserWaypoint then return false end
    end
    local key = Key()
    if not key then return false end
    if key ~= state.key then Reset(key) end
    local d = Arrive.Distance()
    if not d or d > Arrive.LEAVE or not Arrive.Here() then return false end
    local started = Arrived()
    Arrive.Update()
    return started
end

-- Ticker nur, solange der Schalter an ist, eine Markierung steht und kein fremdes Addon das Entfernen übernimmt
function Arrive.Update()
    local want = ns.db ~= nil and ns.Enabled("wayAutoClear") and Key() ~= nil and not Elsewhere(true)
    if want and not ticker and C_Timer and type(C_Timer.NewTicker) == "function" then
        ticker = C_Timer.NewTicker(Arrive.EVERY, function() ns.Try("WayArrive", Arrive.Check) end)
    elseif not want then
        if ticker then ticker:Cancel() end
        ticker = nil
        Reset(nil)
    end
end

function Arrive.Running() return ticker ~= nil end

-- Eine neue Markierung beginnt von vorn: Way.Set meldet jede (auch dieselbe Stelle noch einmal), Blizzards Ereignis
-- jede andere (Strg+Klick auf die Karte, fremde Addons). Ein Ereignis ohne neue Lage lässt die Wartezeit stehen.
function Arrive.Restart()
    if not ns.db then return end
    Reset(Key())
    Arrive.Update()
end

ns.On("USER_WAYPOINT_UPDATED", function()
    if not ns.db then return end
    local key = Key()
    if key ~= state.key then Reset(key) end
    Arrive.Update()
end)

ns.On("NAVIGATION_DESTINATION_REACHED", function(_, isWaypoint)
    if ns.db then Arrive.OnReached(isWaypoint) end
end)

-- Verfolgt der Spieler die Markierung während der Wartezeit wieder (Klick auf die Markierung – Blizzard ruft dabei nur
-- C_SuperTrack.SetSuperTrackedUserWaypoint, nicht SetUserWaypoint), will er sie behalten: Wartezeit endet, und erst ein
-- neues Weggehen schaltet die Ankunft wieder scharf (Fund des code-reviewers vor dem Merge, 16.11.2026).
function Arrive.OnTrackingChanged()
    NoteKind()
    local kinds = Enum and Enum.SuperTrackingType
    if state.since and type(kinds) == "table" and type(kinds.UserWaypoint) == "number"
        and TrackedKind() == kinds.UserWaypoint then
        state.since, state.armed = nil, false
    end
end

ns.On("SUPER_TRACKING_CHANGED", function() Arrive.OnTrackingChanged() end)

-- Jede gesetzte Markierung beginnt von vorn, auch dieselbe Stelle noch einmal von außen (ezCraft „Wo“, Strg+Klick auf
-- die Karte, fremde Addons): USER_WAYPOINT_UPDATED allein ließe die Wartezeit bei gleicher Lage weiterlaufen.
-- Taint-sicher (Leitlinie 5): hooksecurefunc ruft nur nach Blizzards Funktion, nichts wird ersetzt.
if C_Map and type(C_Map.SetUserWaypoint) == "function" and type(hooksecurefunc) == "function" then
    hooksecurefunc(C_Map, "SetUserWaypoint", function() ns.Try("WayArriveSet", Arrive.Restart) end)
end

ns.OnReady(function()
    NoteKind()
    Reset(Key())
    Arrive.Update()
end)

ns.OnSettingChanged(function(key)
    if key == "wayAutoClear" then Arrive.Update() end
end)

ns.AddStatusLine(function()
    if not ns.Enabled("wayAutoClear") then return L.STATUS_ARRIVE_OFF end
    local who = Elsewhere(true)
    if who then return L.STATUS_ARRIVE_OTHER:format(who) end
    return L.STATUS_ARRIVE_ON:format(Core.Seconds(Arrive.Delay()), Arrive.RADIUS)
end)
