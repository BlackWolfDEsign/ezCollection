local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Blizzards Menü „Aufspüren“ an der Minikarte um sinnvolle Punkte erweitern (Wunsch des Nutzers 13.11.2026).

    Geprüft in Blizzards Forever-Quelle (Blizzard_Minimap, Mainline Minimap.lua): MiniMapTrackingButtonMixin:OnLoad
    baut das Menü mit SetupMenu und gibt ihm das Tag MENU_MINIMAP_TRACKING. ezMap hängt sich über Blizzards
    Menu.ModifyMenu an und fügt unten einen Abschnitt „ezMap“ an; Blizzards Einträge bleiben unberührt.

    Aufgenommen – Ziele für Blizzards Markierung; Blizzards Pfeil dazu nur, wenn sie verfolgt wird
    (Schalter wayTrack oder Klick auf die Markierung; seit Welle 29, Entscheidung des Nutzers vom 17.11.2026
    „Nur mit Schalter (Empfohlen)“):
      - Nächster Flugmeister (C_TaxiMap.GetTaxiNodesForMap wie Blizzards Weltkarte; auch noch nicht entdeckte der
        eigenen Fraktion, gerade die sucht man); mit gesetzter Markierung dazu der Flugmeister am Ziel und die
        gelernte Flugzeit dorthin (kein Routenplaner)
      - Lehrer wie im Kartenmenü (nächster Klassenlehrer und alle besuchten)
      - Dungeoneingänge deiner Zone (nur, wenn der Client sie liefert)
      - Zuletzt gesetzte Markierungen, Markierung entfernen
      - Schalter „Von selbst herauszoomen“ (MinimapZoom.lua), „Eckige Minikarte“ (MinimapShape.lua), Einstellungen
      - seit Welle 15 (SAM-11): „Sammel-Fundorte auf der Minikarte“ je Art und „Nur bei aktiver Suche“
        (Gather.AddMiniMenu); fehlt ezCores Sichtradius, ausgegraut mit Erklärung
    Nicht aufgenommen (Begründung in der ROADMAP, Abschnitt ezMap): Quest-Ziele, Briefkasten, Gasthaus und Bank der
    Zone.

    Seit Welle 16 (Wunsch des Nutzers vom 15.11.2026 abends, TrackingMemory.lua): oben direkt unter Blizzards Eintrag
    UNCHECK_ALL (nimmt alle Haken heraus) das Gegenstück „Alle auswählen“ über ezCores Baustein Menu.AllToggle;
    fehlt Blizzards Eintrag (Client-Einstellung minimapTrackingShowAll), beide oben. Unabhängig vom Schalter
    trackingMenu (es ist kein Ziel, sondern Blizzards eigene Liste). Im Abschnitt „ezMap“ der Schalter „Auswahl oben
    merken“ (trackingRemember).

    Seit Welle 27 (Zweig modul/ezmap-menue; Wunsch des Nutzers vom 16.11.2026 mit Bildschirmfoto dieses Menüs,
    wörtlich „sollte sicherlich mit ezmap gekoppelt oder so sein... enterprise“): der Abschnitt „ezMap“ ist nach
    denselben Themen geordnet wie ezMaps Kartenfilter (Tree.lua) und trägt dieselben Symbole wie Blizzards Liste
    darüber – Lehrer mit Blizzards Bild „Lehrer für eine Klasse“, Flugmeister mit dem Bild „Flugmeister“, die
    Sammel-Arten mit Blizzards Such-Atlanten (Icons.lua liest sie zur Laufzeit aus C_Minimap.GetTrackingInfo).
    Abschnitte: „Dienste in der Stadt“, „Reise“, „Sammeln“, „Wegpunkte“, „Minikarte“, dann „Einstellungen“
    (Tracking.SECTIONS).

    Kopplung (Antwort des Nutzers vom 17.11.2026 auf die Frage A/B/C, wörtlich „alles davon“; Wortlaut im ROADMAP-Index):
      A) Optik und Ordnung wie oben.
      B) gleicher Platz: Einträge, die eine Blizzard-Art ergänzen (Tracking.BESIDE – „Lehrer“ zu „Lehrer für eine
         Klasse“, „Nächster Flugmeister“ und „Flugmeister am Ziel“ zu „Flugmeister“), stehen direkt unter Blizzards
         Eintrag. Gefunden wird er über den Namen der Art aus dem Client (C_Minimap.GetTrackingInfo(i).name der Art mit
         passender filterID, MenuUtil.GetElementText), eingefügt über ezCores Core.Menu.InsertRoot (Blizzards
         MenuUtil.Create… und root:Insert) – nur neue Einträge dazwischen, Blizzards Einträge und ihre Reihenfolge bleiben
         (Leitlinie 5). Fehlt Blizzards Eintrag (oder Insert), steht der Eintrag wie bisher im Abschnitt „ezMap“.
      C) gemeinsames Schalten: Schalter „Mit Blizzards Aufspüren gemeinsam schalten“ (trackingCouple, ab Werk aus) im
         Abschnitt „Minikarte“ und auf der Einstellungsseite; die Kopplung selbst in TrackingCouple.lua.
]]
local Tracking = {}
ns.Tracking = Tracking
Tracking.TAG = "MENU_MINIMAP_TRACKING"

local Menu = Core.Menu

-- Zone, in der du stehst (über Kleinkarten wie Stadtvierteln hinweg), für die Dungeoneingänge: Elternkarte bis zur
-- Art „Zone“ aus ezCore (Core.Map.Parent, W-14); kennt der Client die Kette nicht, bleibt es deine Karte.
local function PlayerZone()
    local mapID = ns.PlayerPosition()
    if not mapID then return nil end
    return (Core.Map.Parent(mapID, "Zone")) or mapID
end

-- Stelle von Blizzards Eintrag UNCHECK_ALL in der Liste (Blizzard setzt ihn als ersten). → Stelle | nil, gefunden?
-- Lässt sich die Liste nicht durchsehen, gilt Blizzards Quelle: ohne minimapTrackingShowAll steht er oben.
function Tracking.BlizzardUncheckIndex(root)
    local util = rawget(_G, "MenuUtil")
    local blizzardText = rawget(_G, "UNCHECK_ALL")
    if type(root.EnumerateElementDescriptions) == "function" and type(util) == "table"
        and type(util.GetElementText) == "function" and type(blizzardText) == "string" and not Core.IsSecret(blizzardText) then
        local ok, found = pcall(function()
            for index, desc in root:EnumerateElementDescriptions() do
                local text = util.GetElementText(desc)
                if not Core.IsSecret(text) and text == blizzardText then return index end
            end
        end)
        if ok then return found, true end
    end
    if ns.TrackingMemory.ShowAll() then return nil, true end
    return 1, false
end

-- Text für „Alle auswählen“: Blizzards CHECK_ALL, sonst ezMaps eigener – nie derselbe Wortlaut wie Blizzards Eintrag
-- darüber (gleich bis auf Groß- und Kleinschreibung zählt als derselbe).
function Tracking.CheckAllText()
    local blizzardOff = rawget(_G, "UNCHECK_ALL")
    blizzardOff = type(blizzardOff) == "string" and not Core.IsSecret(blizzardOff) and blizzardOff:lower() or nil
    local candidates = { rawget(_G, "CHECK_ALL"), Core.L.ALL_CHECK, L.TRACK_CHECK_ALL_ALT }   -- erster kann nil sein
    for i = 1, 3 do
        local text = candidates[i]
        if type(text) == "string" and not Core.IsSecret(text) and text ~= "" and text:lower() ~= blizzardOff then
            return text
        end
    end
    return L.TRACK_CHECK_ALL_ALT
end

-- „Alle auswählen“ direkt unter Blizzards „Alle abwählen“; fehlt Blizzards Eintrag, beide oben (ezCores Baustein).
function Tracking.AddAllToggle(root)
    local Memory = ns.TrackingMemory
    if not (Memory.Available() and type(Menu.AllToggle) == "function") then return nil end
    local index, sure = Tracking.BlizzardUncheckIndex(root)
    local at = index and index + 1 or 1
    local entry = Menu.AllToggle(root, Memory.List, Memory.IsActive, Memory.Set,
        { off = false, onText = Tracking.CheckAllText(), onTip = L.TRACK_CHECK_ALL_TIP, skip = Memory.SkipOn, at = at,
          after = Memory.AfterOnSay })   -- ausgelassene Such-Zauber im Chat nennen (Spielbefund 18.11.2026)
    local offEntry
    if not index and sure then
        local _
        -- wie der Knopf der Einstellungsseite: ohne Blizzards Pflicht-Arten, Such-Zauber im Kampf erst danach
        _, offEntry = Menu.AllToggle(root, Memory.List, Memory.IsActive, Memory.Set,
            { on = false, offText = Core.Style.AllText(false), offTip = L.TRACK_UNCHECK_ALL_TIP, at = at + 1,
              skip = Memory.SkipOff, after = Memory.AfterOffSay })
    end
    return entry, offEntry
end

-- Abschnitt „ezMap“ als Tabelle (Welle 27): Abschnitte wie im Kartenfilter, je Eintrag Symbol und Baustein (siehe
-- MapButton.SECTIONS). Jeder Eintrag hat eine Erklärzeile mit Quelle (MAP-19, MapButton.Tip über ezCores Menu.Tip).
Tracking.SECTIONS = {
    { id = "town", title = "OPT_tree_town", icon = "town", tip = "TRACK_SEC_TOWN_TIP", entries = { "trainers" } },
    { id = "journey", title = "OPT_tree_journey", icon = "journey", entries = { "nearestFlight", "destFlight", "entrances" } },
    { id = "gather", title = "OPT_tree_gather", icon = "gather", entries = { "gatherMini" } },
    { id = "way", title = "MSEC_WAY", icon = "own", entries = { "recent", "clear" } },
    { id = "minimap", title = "TRACK_SEC_MINIMAP", icon = "menuMinimap",
      entries = { "remember", "couple", "autoZoom", "square" } },
}

-- Kopplung B: Eintrag » Blizzard-Art (Name aus Icons.FILTER), unter deren Eintrag er steht
Tracking.BESIDE = { trainers = "TrainerClass", nearestFlight = "TaxiNode", destFlight = "TaxiNode" }

Tracking.ENTRIES = {
    trainers = { icon = "trainers", build = function(root) ns.MapButton.AddTrainers(root) end },
    nearestFlight = { icon = "travel", build = function(root)
        local master = ns.Enabled("flightNearest") and ns.Flights.NearestMaster() or nil
        if master then
            local text = ns.Flights.MasterLabel(master)
            ns.MapButton.Tip(Menu.Button(root, text, function() ns.Flights.GoMaster(master) end), text, L.TRACK_FLIGHT_TIP)
        end
    end },
    -- mit gesetzter Markierung: Flugmeister am Ziel, gelernte Flugzeit
    destFlight = { icon = "travel", build = function(root) ns.MapButton.AddDestinationFlight(root) end },
    entrances = { icon = "dungeons", build = function(root) ns.MapButton.AddEntrances(root, PlayerZone()) end },
    -- Sammel-Fundorte auf der Minikarte (SAM-11); die Symbole je Art setzt Gather.AddMiniMenu selbst, die Vorgabe hier
    -- gilt für die übrigen Einträge (Fund des code-reviewers vom 17.11.2026: „Nur bei aktiver Suche“ ohne Symbol)
    gatherMini = { icon = "gatherMini", build = function(root) ns.Gather.AddMiniMenu(root) end },
    recent = { icon = "wayRecent", build = function(root) ns.MapButton.AddRecent(root) end },
    clear = { icon = "menuClear", build = function(root) if ns.Way.Get() then ns.MapButton.AddClear(root) end end },
    remember = { icon = "menuMinimap", build = function(root)
        local _, why, who = ns.TrackingMemory.Active()
        if why == "other" then
            ns.MapButton.OtherTitle(root, L.TRACK_REMEMBER_OTHER:format(who))
        elseif why ~= "api" then
            ns.MapButton.Toggle(root, L.TRACK_REMEMBER, "trackingRemember")   -- Auswahl oben merken (Welle 16)
        end
    end },
    -- Kopplung C (Antwort des Nutzers vom 17.11.2026): Blizzards Haken und ezMaps passende Gruppe gemeinsam schalten
    couple = { icon = "couple", build = function(root)
        if ns.TrackingMemory.Available() then ns.MapButton.Toggle(root, L.OPT_trackingCouple, "trackingCouple") end
    end },
    autoZoom = { icon = "menuMinimap", build = function(root)
        local other = ns.MinimapZoom.AutoElsewhere()
        if other then
            ns.MapButton.OtherTitle(root, L.TRACK_AUTOZOOM_OTHER:format(other))
        else
            -- Haken über dem Schieber minimapAutoZoomDelay (0 = aus; Nr. 91 der Einstellungs-Prüfung vom 19.11.2026)
            local Z = ns.MinimapZoom
            ns.MapButton.Toggle(root, L.TRACK_AUTOZOOM, "minimapAutoZoomDelay", Z.SetOn, Z.On)
        end
    end },
    square = { icon = "menuMinimap", build = function(root)
        local shaper = ns.MinimapShape.Elsewhere()
        if shaper then
            ns.MapButton.OtherTitle(root, L.TRACK_SQUARE_OTHER:format(shaper))
        else
            ns.MapButton.Toggle(root, L.TRACK_SQUARE, "minimapSquare")
        end
    end },
}

-- Name einer Blizzard-Art im Client (Kopplung B): GetTrackingInfo(i).name der gezeigten Art mit passender filterID
-- (TrackingMemory.List lässt gesperrte Antworten aus) → Text oder nil
function Tracking.TrackName(filterName)
    local want = ns.Icons.FilterID(filterName)
    if not want then return nil end
    for _, entry in ipairs(ns.TrackingMemory.List()) do
        if entry.filterID == want and entry.name ~= entry.key then return entry.name end
    end
    return nil
end

-- Blizzards Eintrag dieser Art im Menü (oben oder eine Ebene tiefer) → Beschreibung, die ihn enthält, und seine Stelle;
-- nil, wenn er fehlt oder sich dort nichts einfügen lässt (Insert, MenuUtil.CreateButton)
function Tracking.FindBlizzard(root, filterName)
    local util = rawget(_G, "MenuUtil")
    local name = Tracking.TrackName(filterName)
    if not name or type(util) ~= "table" or type(util.GetElementText) ~= "function"
        or type(util.CreateButton) ~= "function" then
        return nil
    end
    local function Search(parent, deeper)
        if type(parent) ~= "table" or type(parent.EnumerateElementDescriptions) ~= "function" then return nil end
        local subs = {}
        local ok, found = pcall(function()
            for index, desc in parent:EnumerateElementDescriptions() do
                local text = util.GetElementText(desc)
                if not Core.IsSecret(text) and text == name then return index end
                subs[#subs + 1] = desc
            end
        end)
        if ok and found then
            if type(parent.Insert) == "function" then return parent, found end
            return nil
        end
        if not (ok and deeper) then return nil end
        for _, desc in ipairs(subs) do
            local p, at = Search(desc, false)
            if p then return p, at end
        end
        return nil
    end
    return Search(root, true)
end

-- Einen Eintrag direkt unter Blizzards Eintrag seiner Art bauen (Kopplung B; mehrere Einträge derselben Art in ihrer
-- Reihenfolge). → true, wenn er dort steht; false: Blizzards Eintrag fehlt, der Eintrag gehört in den Abschnitt
function Tracking.BuildBeside(root, key, placed)
    local track = Tracking.BESIDE[key]
    local e = Tracking.ENTRIES[key]
    if not (track and e) then return false end
    local parent, index = Tracking.FindBlizzard(root, track)
    if not parent then return false end
    local n = placed[track] or 0
    local insert = Menu.InsertRoot(parent, index + 1 + n)
    ns.Try("TrackingMenu:" .. key, e.build, ns.Icons.Root(insert, e.icon))
    placed[track] = n + insert.Count()
    return true
end

function Tracking.Build(root)
    ns.Try("TrackingAllToggle", Tracking.AddAllToggle, root)   -- ein Fehler dort kostet nicht den Abschnitt darunter
    if not ns.Enabled("trackingMenu") then return end
    local Box = ns.MapButton
    -- Kopplung B zuerst: was neben Blizzards Eintrag steht, fehlt im Abschnitt darunter (kein Eintrag doppelt)
    -- (in der Reihenfolge der Abschnitte: „Nächster Flugmeister“ vor „Flugmeister am Ziel“)
    local beside, placed = {}, {}
    for _, section in ipairs(Tracking.SECTIONS) do
        for _, key in ipairs(section.entries) do
            if Tracking.BESIDE[key] then
                local ok, done = pcall(Tracking.BuildBeside, root, key, placed)
                beside[key] = ok and done or nil
            end
        end
    end
    Menu.Divider(root)
    Menu.Title(root, L.TRACK_TITLE)
    -- der erste Abschnitt, der etwas enthält, steht ohne Trenner direkt unter dem Titel – auch wenn „Dienste in der
    -- Stadt“ leer bleibt (alle Lehrer aus; Fund der Gegenprüfung 17.11.2026)
    local chain = {}
    for _, section in ipairs(Tracking.SECTIONS) do
        local sec = Menu.Section(root, L[section.title] or section.title, { icon = ns.Icons.For(section.icon),
            tip = section.tip and L[section.tip] or nil, chain = chain })
        for _, key in ipairs(section.entries) do
            local e = Tracking.ENTRIES[key]
            if e and not beside[key] then ns.Try("TrackingMenu:" .. key, e.build, ns.Icons.Root(sec, e.icon)) end
        end
    end
    Menu.Divider(root)
    Box.AddSettings(root)
end

-- Einmal anmelden; Blizzard ruft die Ergänzung bei jedem Öffnen des Menüs auf. Der Schalter wirkt sofort.
local registered = false
function Tracking.Register()
    local blizzardMenu = rawget(_G, "Menu")
    if registered or not (type(blizzardMenu) == "table" and type(blizzardMenu.ModifyMenu) == "function") then
        return registered
    end
    registered = pcall(blizzardMenu.ModifyMenu, Tracking.TAG, function(_, root)
        ns.Try("TrackingMenu", Tracking.Build, root)
    end)
    return registered
end

ns.OnReady(function() Tracking.Register() end)
