local _, ns = ...
local L = ns.L
local Core = ezCore

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezMap (Seite von ezCore):
-- Allgemein » Wegpunkte » Karte: was zeigen (Baum, Tree.lua) » Karte » Sammeln » Flugzeiten » Lehrer » Seltene Gegner »
-- Schlachtfeld » Minikarte » Erweitert. Jeder Schalter, der etwas auf Karte, Minikarte oder in den Kartenmenüs zeigt,
-- steht genau einmal im Baum (Wunsch des Nutzers vom 15.11.2026); die übrigen Abschnitte tragen Knöpfe, Regler und
-- Auswahlfelder ihres Themas.
local page

-- Gespeicherte Werte ohne eigene Zeile: die Seite zeigt sie über eine gemeinsame Auswahl (Einstellungs-Prüfung vom
-- 19.11.2026, Nr. 80 bis 83). Wert → Name der Auswahl (page:ProxyDropdown); die Tests prüfen damit, dass jeder Wert aus
-- ns.DEFAULTS auf der Seite erreichbar ist.
ns.SETTING_PROXY = { mapButton = "mapPlace", mapFilterSection = "mapPlace", wayAutoClearDelay = "wayAutoClear" }

-- Schieber mit „0 = aus“ und Mindestwert (Nr. 89 bis 92; Gegenprüfung des Pakets): eine Stellung zwischen 0 und dem
-- Mindestwert hätte keine eigene Wirkung (Gather.HideNear und MinimapZoom.Delay heben sie auf den Mindestwert). Sie
-- rastet deshalb ein – kommt der Schieber von unten, auf den Mindestwert, kommt er von oben, auf 0. Geschrieben wird
-- über Blizzards Setting-Objekt, damit der Schieber nachzieht. Schlüssel → Funktion, die den Mindestwert liefert.
ns.OFF_MIN = {
    gatherHideNearYards = function() return ns.Gather.HIDE_NEAR_MIN end,
    minimapAutoZoomDelay = function() return ns.MinimapZoom.MIN end,
}
local offMinLast = {}       -- [Schlüssel] = letzter eingerasteter Wert (Richtung des nächsten Schritts)
local offMinDrag = {}       -- [Schlüssel] = Ziel des Einrastens, solange die Maustaste beim Ziehen gedrückt bleibt

-- Zieht die Maus gerade (linke Taste gedrückt)? Ohne Abfrage bzw. bei gesperrter Antwort: nein
local function Dragging()
    local down = rawget(_G, "IsMouseButtonDown")
    if type(down) ~= "function" then return false end
    local ok, raw = pcall(down, "LeftButton")
    if not ok or ns.IsSecret(raw) then return false end
    return raw == true or raw == 1
end

-- → der Wert, der jetzt gilt (eingerastet oder unverändert); nil bei unbekanntem Schlüssel oder unlesbarem Wert.
-- Beim langsamen Ziehen im toten Bereich meldet der Schieber nach dem Einrasten wieder die Stellung unter der Maus;
-- ohne Sperre spränge er dann zwischen 0 und dem Mindestwert hin und her. Solange die Maustaste gedrückt bleibt, gilt
-- darum das Ziel des ersten Einrastens weiter, bis der Schieber den toten Bereich verlässt (Nachlauf des
-- code-reviewers vom 20.11.2026).
function ns.SnapOffMin(key)
    local minOf = ns.OFF_MIN[key]
    local value = minOf and ns.Num(ns.S and ns.S[key])
    if not value then return nil end
    local minValue = minOf()
    local dragging = Dragging()
    if not dragging then offMinDrag[key] = nil end
    if value > 0 and value < minValue then
        local last = offMinLast[key]
        local target = (last ~= nil and last > value) and 0 or minValue
        if dragging and offMinDrag[key] ~= nil then target = offMinDrag[key] end
        if dragging then offMinDrag[key] = target end
        offMinLast[key] = target
        local setting = type(ns.settingObjects) == "table" and ns.settingObjects[key] or nil
        if not (setting and pcall(setting.SetValue, setting, target) and ns.S[key] == target) then
            ns.SetSetting(key, target)
        end
        return target
    end
    -- außerhalb des toten Bereichs: die Rückmeldung des eigenen Einrastens hält die Sperre, alles andere löst sie
    if offMinDrag[key] ~= nil and value ~= offMinDrag[key] then offMinDrag[key] = nil end
    offMinLast[key] = value
    return value
end

local function Register()
    if page then return end
    page = Core.NewSettingsPage(ns)
    if not page then return end

    -- Allgemein: der sichtbare Weg zu /way ohne Chatbefehl
    page:Button(L.OPT_ENTER, L.OPT_ENTER_BUTTON, function() ns.Way.Ask() end, L.OPT_ENTER_TIP)
    page:MoverButton()      -- Flugleiste verschieben (ezCore.Mover)

    page:Header(L.OPT_HEADER_WAY)
    -- ezMap an der Weltkarte: Knopf / Blizzards Kartenfilter / beides – eine Auswahl über mapButton und
    -- mapFilterSection (Einstellungs-Prüfung vom 19.11.2026, Nr. 80, 81)
    page:ProxyDropdown("mapPlace", ns.MapButton.PlaceValues(), ns.MapButton.Place, ns.MapButton.SetPlace,
        { default = "button" })
    page:Checkbox("wayTrack")
    page:Checkbox("waySlash")
    -- Markierung bei Ankunft entfernen (Arrive.lua): eine Auswahl „Aus / nach 3 s / nach 5 s“ über wayAutoClear und
    -- wayAutoClearDelay (Nr. 82, 83)
    page:ProxyDropdown("wayAutoClear", ns.Arrive.ChoiceValues(), ns.Arrive.Choice, ns.Arrive.SetChoice,
        { default = tostring(ns.Arrive.DEFAULT_DELAY) })
    page:Button(L.OPT_HERE, L.OPT_HERE_BUTTON, function() ns.Way.SetHere(nil, true) end, L.OPT_HERE_TIP)
    page:Button(L.OPT_CLEAR, L.OPT_CLEAR_BUTTON, function() ns.Way.Clear(true) end, L.OPT_CLEAR_TIP)

    -- Karte: was zeigen – der Baum („Alles“ » Gruppen » Arten); Gruppen als Auswahl an, aus, teilweise
    ns.Tree.AddSettings(page)

    page:Header(L.OPT_HEADER_MAP, L.OPT_HEADER_MAP_TIP)
    page:Button(L.OPT_ENTRANCE_LIST, L.OPT_LIST_BUTTON, ns.Entrances.PrintList, L.OPT_ENTRANCE_LIST_TIP)
    page:Checkbox("pinsRound")    -- Symbole der Punkte rund (Weltkarte und Minikarte, ezCore MapPins)
    -- Nummern an allen Schritten der Routen (Sammel-Route und ezQuests Leveling-Route; ab Werk nur am nächsten,
    -- Spieltest 19.11.2026); derselbe Haken steht im Untermenü „Route durch diese Zone“
    page:Checkbox("routeNumbers")

    -- Sammeln (SAM-12): die Arten stehen im Baum (Gruppe „Sammeln“, Kisten unter „Entdecker-Wissen“); hier Modus je
    -- Art (in ezCore gespeichert, Core.Gathering.Visibility), Größe, Deckkraft und Abdunkeln; „Fundorte trotz
    -- GatherMate2/Gatherer zeigen“. Seit der Einstellungs-Prüfung vom 19.11.2026: „Nur, was ich abbauen kann“ ist der
    -- Eintrag „Rot“ im Filter „Nach Farbe“ des Baums (Nr. 88), „Wert je Ernte im Tooltip“ immer an (Nr. 44), die
    -- Auswahl „wann zeigen“ ohne „Nie“ und für Kisten gar nicht mehr (Nr. 2, 86, 87)
    page:Header(L.OPT_HEADER_GATHER, L.OPT_HEADER_GATHER_TIP)
    for _, kind in ipairs(ns.Gather.KINDS) do
        if ns.Gather.HasModes(kind) then
            local values = {}
            for _, mode in ipairs(ns.Gather.MODES[kind]) do values[#values + 1] = { mode, L["GMAP_MODE_" .. mode] } end
            page:ProxyDropdown("gatherMode", values, function() return ns.Gather.Mode(kind) end,
                function(mode) ns.Gather.SetMode(kind, mode) end, { format = ns.Gather.KindLabel(kind), id = kind })
        end
    end
    -- Minikarte (SAM-11): Modus je Art für die Fläche „minimap“ (ezCore), Größe und Deckkraft eigens
    for _, kind in ipairs(ns.Gather.KINDS) do
        if ns.Gather.HasModes(kind) then
            local values = {}
            for _, mode in ipairs(ns.Gather.MODES[kind]) do values[#values + 1] = { mode, L["GMAP_MODE_" .. mode] } end
            page:ProxyDropdown("gatherMiniMode", values, function() return ns.Gather.Mode(kind, "minimap") end,
                function(mode) ns.Gather.SetMode(kind, mode, "minimap") end,
                { format = ns.Gather.KindLabel(kind), id = kind })
        end
    end
    page:Slider("gatherSize", 8, 32, 1, function(value) return L.GMAP_PIXELS:format(value) end)
    page:Slider("gatherAlpha", 20, 100, 5, function(value) return Core.Percent(value) end)
    page:Slider("gatherDim", 0, 30, 1, function(value)
        if value == 0 then return L.GMAP_DIM_OFF end
        return Core.Minutes(value)
    end)
    page:Slider("gatherMiniSize", 8, 24, 1, function(value) return L.GMAP_PIXELS:format(value) end)
    page:Slider("gatherMiniAlpha", 20, 100, 5, function(value) return Core.Percent(value) end)
    -- in der Nähe auf der Minikarte ausblenden, damit Blizzards Symbol der Suche frei bleibt (Wunsch vom 18.11.2026);
    -- ein Schieber mit 0 = aus statt Haken und Schieber (Nr. 89, 90)
    page:Slider("gatherHideNearYards", 0, ns.Gather.HIDE_NEAR_MAX, 5, ns.Gather.HideNearLabel)
    page:Checkbox("gatherOverride")

    -- Flugzeiten: die Leiste während des Flugs steht hier statt im Baum der Karte – sie erscheint nicht auf der Karte
    -- (Abschnitt 3 der Einstellungs-Prüfung vom 19.11.2026)
    page:Header(L.OPT_HEADER_FLIGHTS)
    page:Checkbox("flightBar")
    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, ns.Flights.Preview, L.OPT_PREVIEW_TIP)
    page:Button(L.OPT_FLIGHT_LIST, L.OPT_LIST_BUTTON, ns.Flights.PrintList, L.OPT_FLIGHT_LIST_TIP)

    page:Header(L.OPT_HEADER_TRAINERS)
    page:Button(L.OPT_TRAINER_LIST, L.OPT_LIST_BUTTON, ns.Trainers.PrintList, L.OPT_TRAINER_LIST_TIP)

    -- Entdecker-Wissen: nur auf Wunsch (ab Werk aus)
    page:Header(L.OPT_HEADER_RARES, L.OPT_HEADER_RARES_TIP)
    page:Checkbox("rareAlert")
    page:Checkbox("rareSound", nil, { parent = "rareAlert" })   -- Ton nur zur Meldung (Rares.lua) (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    page:Checkbox("rareOverride")
    page:Button(L.OPT_RARE_PREVIEW, L.OPT_PREVIEW_BUTTON, ns.Rares.Preview, L.OPT_RARE_PREVIEW_TIP)
    page:Button(L.OPT_RARE_LAST, L.OPT_HERE_BUTTON, function() ns.Rares.GoLast(true) end, L.OPT_RARE_LAST_TIP)

    page:Header(L.OPT_HEADER_BG, L.OPT_HEADER_BG_TIP)
    page:Checkbox("bgTimers")
    page:Button(L.OPT_BG_PREVIEW, L.OPT_PREVIEW_BUTTON, ns.Battleground.Preview, L.OPT_BG_PREVIEW_TIP)

    page:Header(L.OPT_HEADER_MINIMAP, L.OPT_HEADER_MINIMAP_TIP)
    page:Checkbox("trackingMenu")
    -- Menü „Aufspüren“: Auswahl merken, Alle auswählen / Alle abwählen (Welle 16, TrackingMemory.lua)
    page:Checkbox("trackingRemember")
    -- gemerkte Such-Zauber selbst einschalten (ab Werk aus, Welle 29, NACH-27); derselbe Haken steht im Menü „Aufspüren“
    page:Checkbox("trackingSpellAuto")
    -- Blizzards Aufspür-Haken und ezMaps Gruppen gemeinsam schalten (Antwort des Nutzers vom 17.11.2026, TrackingCouple.lua)
    page:Checkbox("trackingCouple")
    page:Button(L.OPT_TRACK_ALL_ON, Core.Style.AllText(true), function() ns.TrackingMemory.SetAllAndSay(true) end,
        L.OPT_TRACK_ALL_ON_TIP)
    page:Button(L.OPT_TRACK_ALL_OFF, Core.Style.AllText(false), function() ns.TrackingMemory.SetAllAndSay(false) end,
        L.OPT_TRACK_ALL_OFF_TIP)
    page:Checkbox("minimapSquare")
    -- Koordinaten ins Zonenkästchen, Lupe und Kalender auf den Ring (Spieltest 20.11.2026, MinimapCompact.lua)
    page:Checkbox("minimapCompact")
    -- von selbst wieder herauszoomen: ein Schieber mit 0 = aus (Nr. 91, 92); der Haken im Menü „Aufspüren“ bleibt
    page:Slider("minimapAutoZoomDelay", 0, ns.MinimapZoom.MAX, 1, ns.MinimapZoom.Label)

    page:Advanced()
    page:StatusButton(L.OPT_STATUS_TIP)     -- „Status – Im Chat zeigen“ (ezCore, T9-2)
    -- Schlachtfeld: melden, was der Client im Schlachtfeld liefert (für den Spieltest)
    page:Button(L.OPT_BG_DIAGNOSE, L.OPT_BG_DIAGNOSE_BUTTON, ns.Battleground.Diagnose, L.OPT_BG_DIAGNOSE_TIP)
    page:MoverResetButton()
    -- Gelerntes vergessen lässt sich nicht rückgängig machen: Rückfrage mit Warnsymbol. Knopftext: Blizzards DELETE
    -- (T18-22) über Core.Word – den Rückfall hält ezCore.
    local delete = Core.Word("DELETE")
    page:Button(L.OPT_FLIGHT_RESET, delete, function()
        Core.Confirm(L.FLIGHT_RESET_CONFIRM, ns.Flights.Reset, { alert = true })
    end, L.OPT_FLIGHT_RESET_TIP)
    page:Button(L.OPT_TRAINER_FORGET, delete, function()
        Core.Confirm(L.TRAINER_FORGET_CONFIRM, ns.Trainers.Forget, { alert = true })
    end, L.OPT_TRAINER_FORGET_TIP)
    page:Button(L.OPT_ENTRANCE_FORGET, delete, function()
        Core.Confirm(L.ENTRANCE_FORGET_CONFIRM, ns.Entrances.Forget, { alert = true })
    end, L.OPT_ENTRANCE_FORGET_TIP)
    page:Button(L.OPT_HISTORY_CLEAR, delete, function()
        wipe(ns.db.way.history)
        ns.Print(L.WAY_HISTORY_CLEARED)
    end, L.OPT_HISTORY_CLEAR_TIP)
    page:ResetButton({ tip = L.OPT_DEFAULTS_TIP })   -- „Einstellungen zurücksetzen“ (ezCore)
    page:TourButton(ns.Guide.tour, L.OPT_TOUR_TIP)   -- Erklärblasen erneut zeigen
    page:Companions()                                -- Ergänzende Addons mit CurseForge-Link

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)
-- Ausgangslage für die Richtung: der gespeicherte Wert beim Einloggen
ns.OnReady(function()
    for key in pairs(ns.OFF_MIN) do offMinLast[key] = ns.Num(ns.S and ns.S[key]) end
end)
ns.OnSettingChanged(function(key)
    if ns.OFF_MIN[key] then ns.SnapOffMin(key) end
end)

-- „Symbole rund“ (pinsRound) an ezCores Punkteschicht geben: beschnitten werden Gegenstands- und Zaubersymbole immer
-- (MapPins.SetSymbol), rund maskiert nur auf Wunsch. Gilt für Weltkarte und Minikarte zugleich.
function ns.ApplyPinStyle()
    local P = Core.MapPins
    if type(P) ~= "table" or type(P.SetRoundIcons) ~= "function" then return false end
    return P.SetRoundIcons(ns.db ~= nil and ns.Enabled("pinsRound"))
end
ns.OnReady(function() ns.Try("PinStyle", ns.ApplyPinStyle) end)
ns.OnSettingChanged(function(key)
    if key == "pinsRound" then ns.ApplyPinStyle() end
end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
