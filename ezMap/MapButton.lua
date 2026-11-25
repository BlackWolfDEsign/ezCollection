local _, ns = ...
local L = ns.L
local Core = ezCore

-- Sichtbarer Knopf für alles, was ezMap auf der Karte kann: rund wie Blizzards Pin-Knopf und direkt daneben
-- (Weltkarte oben links). Linksklick öffnet ein Menü: Koordinaten eingeben, eigene Position, Markierung entfernen
-- oder teilen, „Zuletzt“, Flugpunkte, die dir oder deinen Twinks fehlen, besuchte Lehrer, Dungeoneingänge,
-- Zonenstufen, Bibliotheksbücher, Sammel-Fundorte, der Baum „Was ezMap auf der Karte zeigt“ (steht er im
-- Kartenfilter: Schalter für Eingangssymbole, Koordinaten und Bücher), Einstellungen; Rechtsklick öffnet die Einstellungen (Entscheidung 5 vom
-- 18.11.2026). Seit dem Spielbefund vom 18.11.2026 („zur map, das muss ein button sein, sinnvoll aufgeteilt“) ist
-- dieser Knopf der EINE Ort von ezMap an der Weltkarte: ezMaps Abschnitt in Blizzards Kartenfilter (▼ oben rechts)
-- erscheint nur noch mit dem Schalter mapFilterSection (ab Werk aus) oder bei abgeschaltetem Knopf
-- (Gather.FilterWanted, Gather.InFilter). Nichts wird in Blizzards Kartentabellen eingetragen.
local MapButton = {}
ns.MapButton = MapButton

local button

local function Anchor()
    if not (button and WorldMapFrame) then return end
    local pin = WorldMapFrame.WorldMapTrackingPinButton
    local container = WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer() or WorldMapFrame
    button:ClearAllPoints()
    if pin then
        -- Forever: Pin-Knopf oben links → rechts daneben; Retail: oben rechts → links daneben.
        local pinX = pin.GetCenter and pin:GetCenter()
        local midX = container.GetCenter and container:GetCenter()
        if pinX and midX and pinX > midX then
            button:SetPoint("TOPRIGHT", pin, "TOPLEFT", 0, 0)
        else
            button:SetPoint("TOPLEFT", pin, "TOPRIGHT", 0, 0)
        end
    else
        button:SetPoint("TOPLEFT", container, "TOPLEFT", 3, 0)
    end
end

local function ShownMapID()
    return WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() or nil
end

---------------------------------------------------------------------------
-- Menü
---------------------------------------------------------------------------

local Menu = Core.Menu

-- Erklärzeile an einem Menüeintrag (MAP-19): Titel ist der Text des Eintrags, darunter, was der Klick tut und woher
-- die Angabe stammt (Leitlinie 11); seit Welle 27 optional eine graue Zeile „Quelle“ (Design-System 2.7). Läuft über
-- ezCores Menu.Tip (Blizzards SetTooltip des Eintrags); kennt der Eintrag das nicht, bleibt er ohne Tooltip.
-- → der Eintrag.
local function Tip(entry, title, text, source)
    return Menu.Tip(entry, title, text, source)
end
MapButton.Tip = Tip

-- Symbol an den Einträgen eines Bausteins: seit dem Fund des code-reviewers vom 17.11.2026 über ezCores
-- Core.Menu.IconRoot (ns.Icons.Root; vorher MapButton.IconRoot, neu in diesem Paket und ohne weiteren Aufrufer): jeder
-- Eintrag, den ein Baustein direkt anlegt, bekommt das Symbol aus der Tabelle der Einträge als Vorgabe, Hilfszeilen das
-- Hinweis-Symbol; ein eigenes Symbol des Bausteins (Route, „Wo am dichtesten?“) gilt vor der Vorgabe.

-- Schalter im Menü: dieselbe Erklärung wie auf der Einstellungsseite (OPT_<key>_TIP, eine Quelle). get: eigener Stand
-- statt ns.Enabled(key) – für einen Haken über einem Schieber mit „0 = aus“ (Herauszoomen, MinimapZoom.On)
function MapButton.Toggle(root, text, key, set, get)
    local entry = Menu.Toggle(root, text, get or function() return ns.Enabled(key) end,
        set or function(on) ns.SetSetting(key, on) end)
    return Tip(entry, text, L["OPT_" .. key .. "_TIP"])
end

-- Hinweis „übernimmt <Addon>“ samt Erklärzeile.
function MapButton.OtherTitle(root, text, tip)
    return Tip(Menu.Title(root, text), text, tip or L.MENU_OTHER_TIP)
end

-- Zeigt der Baum (Tree.lua) diesen Lehrer? Klassenlehrer, Tierausbilder, weitere Lehrer je Blatt; Berufslehrer je
-- Titel (dynamisches Blatt „prof:<Titel>“)
function MapButton.TrainerWanted(t)
    local Tree = ns.Tree
    if t.kind == "class" then return Tree.Leaf("trainerClass") end
    if t.kind == "pet" then return Tree.Leaf("trainerPet") end
    if t.kind == "profession" then
        local title = type(t.title) == "string" and t.title ~= "" and t.title or L.TREE_PROF_UNTITLED
        return Tree.Leaf("prof:" .. title)
    end
    return Tree.Leaf("trainerOther")
end

-- Bausteine für das Kartenmenü und für Blizzards Menü „Aufspüren“ (Tracking.lua).
-- Lehrer als Liste in ein Menü füllen (eigener Knopf „Lehrer“ oder – im Menü „Aufspüren“ – Blizzards Haken der
-- passenden Art, Tracking.lua). opts: kinds = { class = true, … } (nil: alle Arten), nearest = „Nächster
-- Klassenlehrer/Tierausbilder“ zeigen (nur, wenn die Arten dabei sind), other = Hinweis auf ein Addon, das alle Lehrer
-- zeigt, head = Kopfzeile mit Erklärung (Leitlinie 11: an Blizzards Haken sagt sie, woher die Liste stammt),
-- skipEmpty = ohne passende Lehrer nichts anlegen. → menu, oder nil, wenn nichts angelegt wurde (skipEmpty)
-- Ab so vielen Lehrern stehen sie je Zone in einem Untermenü (deine Zone zuerst), sonst als Liste mit Zonentiteln
-- (mit Questie kommen alle Lehrer des Kontinents dazu – als flache Liste zu lang)
MapButton.TRAINERS_FLAT = 15

-- Ein Lehrer als Knopf: Klick setzt die Markierung, Tooltip mit Quelle („laut Questie“ bzw. „von dir besucht“)
local function TrainerButton(menu, t)
    local label = ns.Trainers.Label(t)
    return Tip(Menu.Button(menu, label, function() ns.Trainers.Go(t) end), label, L.MENU_TRAINER_ENTRY_TIP,
        ns.Trainers.Source(t))
end

-- „Nächster …“ mit Quelle
local function NearestButton(menu, t, format, tip)
    local text = format:format(t.name)
    return Tip(Menu.Button(menu, text, function() ns.Trainers.Go(t) end), text, tip, ns.Trainers.Source(t))
end

-- Einträge (Kopien aus Core.Npcs.List, nach Zone sortiert) ins Menü: unter TRAINERS_FLAT flach mit der Zone als
-- Zwischenzeile, sonst je Zone ein Untermenü – die Zone von map bzw. deine zuerst (MapButton.ByZone). Ein Baustein für
-- die Lehrer und Gastwirt & Co. (Entscheidung des Nutzers vom 22.11.2026: „Ja, wie Lehrer“). Button(menu, eintrag)
function MapButton.ZoneList(menu, list, Button, map)
    if #list < MapButton.TRAINERS_FLAT then
        local zone
        for _, t in ipairs(list) do
            local name = ns.MapName(t.map)
            if name ~= zone then
                zone = name
                Menu.Title(menu, name)
            end
            Button(menu, t)
        end
        return
    end
    for _, group in ipairs(MapButton.ByZone(list, map)) do
        local sub = Menu.Button(menu, group.name)
        for _, t in ipairs(group.list) do Button(sub, t) end
    end
end

function MapButton.FillTrainers(menu, opts)
    opts = opts or {}
    local kinds = opts.kinds
    -- ohne bekannte Art zählt ein Lehrer als „weitere Lehrer“ (wie TrainerWanted)
    local function Want(kind) return kinds == nil or kinds[kind or "other"] == true end
    local list = {}
    local all, pending = ns.Trainers.List(nil, { map = opts.map })
    for _, t in ipairs(all) do
        if Want(t.kind) and MapButton.TrainerWanted(t) then list[#list + 1] = t end
    end
    if #list == 0 and opts.skipEmpty and not pending then return nil end
    if opts.head then Tip(Menu.Title(menu, opts.head), opts.head, L.MENU_TRAINERS_TIP) end
    -- Questie liest noch (erstes Öffnen nach dem Anmelden) bzw. antwortet falsch: sagen, was los ist
    MapButton.ListNotes(menu, #list == 0, pending, L.MENU_TRAINERS_NONE)
    if #list > 0 then
        local near = opts.nearest ~= false
        -- „Nächster …“ misst ab deinem Standort (Trainers.Nearest, nur dein Kontinent): zeigt die Weltkarte einen
        -- anderen Kontinent, aus der Liste deines Standorts rechnen, nicht aus der gezeigten (Fund des code-reviewers
        -- vom 22.11.2026)
        if opts.map then
            local here = ns.PlayerPosition()
            local mine = here and Core.Map.Parent(here, "Continent")
            if mine ~= Core.Map.Parent(opts.map, "Continent") then all = ns.Trainers.List() end
        end
        local nearest = near and Want("class") and ns.Tree.Leaf("trainerClass") and ns.Trainers.Nearest("class", all) or nil
        if nearest then NearestButton(menu, nearest, L.MENU_TRAINER_NEAREST, L.MENU_TRAINER_NEAREST_TIP) end
        -- Tierausbilder braucht nur der Jäger; in der Liste darunter stehen sie für alle
        local pet = near and Want("pet") and ns.playerClass == "HUNTER" and ns.Tree.Leaf("trainerPet")
            and ns.Trainers.Nearest("pet", all) or nil
        if pet then NearestButton(menu, pet, L.MENU_TRAINER_NEAREST_PET, L.MENU_TRAINER_NEAREST_PET_TIP) end
        -- Waffenmeister (Nutzer am 22.11.2026: „und noch waffenmeister“) – Art „other“, Blatt „weitere Lehrer“
        local weapon = near and Want("other") and ns.Tree.Leaf("trainerOther")
            and ns.Trainers.Nearest("weapon", all) or nil
        if weapon then NearestButton(menu, weapon, L.MENU_TRAINER_NEAREST_WEAPON, L.MENU_TRAINER_NEAREST_WEAPON_TIP) end
        if nearest or pet or weapon then Menu.Divider(menu) end
        MapButton.ZoneList(menu, list, TrainerButton, opts.map)
    end
    local other = opts.other ~= false and ns.TrainersElsewhere() or nil
    if other then
        Menu.Divider(menu)
        MapButton.OtherTitle(menu, L.MENU_TRAINERS_OTHER:format(other), L.MENU_TRAINERS_OTHER_TIP)
    end
    return menu
end

-- Einträge je Zone: { { name, map, list }, … } – deine Zone (bzw. die der Karte map) zuerst, dann nach Namen; die
-- Reihenfolge in einer Zone bleibt (Lehrer, Händler)
function MapButton.ByZone(list, map)
    local here = ns.Num(map) or ns.PlayerPosition()       -- map: die gezeigte Karte (ezMap-Knopf) zuerst
    here = here and Core.Map.Parent(here, "Zone") or nil
    local groups, byName = {}, {}
    for _, e in ipairs(list) do
        local name = ns.MapName(e.map) or "?"
        local g = byName[name]
        if not g then
            g = { name = name, map = e.map, list = {} }
            byName[name] = g
            groups[#groups + 1] = g
        end
        g.here = g.here or (here ~= nil and Core.Map.Parent(e.map, "Zone") == here)
        g.list[#g.list + 1] = e
    end
    table.sort(groups, function(a, b)
        if (a.here == true) ~= (b.here == true) then return a.here == true end
        return a.name < b.name
    end)
    return groups
end

-- Eigener Knopf „Lehrer“ mit Untermenü (Kartenmenü; im Menü „Aufspüren“ nur für Arten, deren Haken Blizzard dort
-- nicht zeigt). opts wie FillTrainers. → der Knopf oder nil (Gruppe „Lehrer“ im Baum aus)
function MapButton.AddTrainers(root, opts)
    if not ns.Tree.Any("trainers") then return nil end
    local menu = Tip(Menu.Button(root, L.MENU_TRAINERS), L.MENU_TRAINERS, L.MENU_TRAINERS_TIP)
    return MapButton.FillTrainers(menu, opts)
end

-- Dungeoneingänge der gezeigten Karte (auf einer Kontinentkarte die ihrer Zonen): zuerst aus ezCore.Dungeons, das sie
-- zur Laufzeit aus Blizzards Daten liest, dann die selbst betretenen, zuletzt die der Client-Tabellen (Entrances.lua nennt
-- je Eintrag die Quelle). Nach Stufe
-- gefärbt wie in Blizzards Gruppensuche; Klick setzt die Markierung.
function MapButton.Entrances(mapID)
    return ns.Entrances.For(mapID)
end

local function EntranceLabel(e)
    local entry = e.entry
    local label = e.name
    if entry and entry.minLevel and entry.maxLevel then
        local r, g, b = Core.Dungeons.Color(Core.Dungeons.DifficultyOf(entry))
        label = ("%s%s (%d–%d)|r"):format(Core.ColorCode(r, g, b), e.name, entry.minLevel, entry.maxLevel)
    end
    -- Quelle nennen, wenn der Eingang nicht vom Client kommt
    if e.source == "self" then label = label .. " " .. L.ENTRANCE_SELF_MARK end
    if e.source == "tables" then label = label .. " " .. L.ENTRANCE_TABLES_MARK end
    return label
end

function MapButton.AddEntrances(root, mapID)
    if not ns.Enabled("entranceList") then return end
    local list = MapButton.Entrances(mapID)
    if #list == 0 then return end
    local menu = Tip(Menu.Button(root, L.MENU_DUNGEONS), L.MENU_DUNGEONS, L.MENU_DUNGEONS_TIP)
    for _, e in ipairs(list) do
        Tip(Menu.Button(menu, EntranceLabel(e), function() ns.Way.Set(e.map, e.x, e.y, e.name, true) end),
            e.name, L.MENU_ENTRANCE_ENTRY_TIP:format(ns.Entrances.SourceText(e)))
    end
    local other = ns.EntrancesElsewhere()
    if other then
        Menu.Divider(menu)
        MapButton.OtherTitle(menu, L.MENU_DUNGEONS_OTHER:format(other), L.MENU_DUNGEONS_OTHER_TIP)
    end
end

function MapButton.AddRecent(root)
    if not ns.Enabled("wayRecent") then return end
    local history = ns.db.way.history
    if #history == 0 then return end
    local recent = Tip(Menu.Button(root, L.MENU_RECENT), L.MENU_RECENT, L.MENU_RECENT_TIP)
    for _, entry in ipairs(history) do
        local text = ns.Way.Describe(entry)
        Tip(Menu.Button(recent, text, function() ns.Way.SetEntry(entry) end), text, L.MENU_RECENT_ENTRY_TIP)
    end
end

-- Mit gesetzter Markierung: der Flugmeister, der dem Ziel am nächsten liegt (Klick setzt die Markierung auf ihn),
-- und darunter die Flugzeit von deinem nächsten Flugmeister dorthin – mit Quelle („bei dir gemessen“, „geschätzt“) oder
-- „noch unbekannt“. Kein Routenplaner (Flights.lua). Für das Kartenmenü und das Menü „Aufspüren“.
function MapButton.AddDestinationFlight(root)
    if not ns.Enabled("flightDest") then return false end
    local dest, own, seconds, estimated, flights = ns.Flights.AtWaypoint()
    if not dest then return false end
    local label = ns.Flights.DestinationLabel(dest)
    Tip(Menu.Button(root, label, function() ns.Flights.GoMaster(dest) end), label, L.MENU_FLIGHT_DEST_TIP)
    local line = ns.Flights.DestinationTimeLabel(dest, own, seconds, estimated)
    if line then
        local title = Menu.Title(root, line)
        if seconds then Tip(title, line, ns.Flights.DestinationTimeTip(estimated, flights)) end
    end
    return true
end

-- Was die Flugmeister-Liste zeigt: { nearest, zones, dest } oder nil (nichts zu zeigen; Schalter aus, keine Daten)
function MapButton.FlightData()
    local wanted = ns.Enabled("flightNearest")
    local nearest = wanted and ns.Flights.NearestMaster() or nil
    local zones = wanted and ns.Flights.MastersByZone() or {}
    local dest = ns.Enabled("flightDest") and ns.Flights.AtWaypoint() or nil
    if not (nearest or dest or #zones > 0) then return nil end
    return { nearest = nearest, zones = zones, dest = dest }
end

-- Flugmeister als Liste in ein Menü füllen (Menü „Aufspüren“: Blizzards Haken „Flugmeister“, Tracking.lua; ohne ihn
-- ein eigener Knopf, MapButton.AddFlights): Kopfzeile mit Erklärung (Leitlinie 11), „Nächster Flugmeister“,
-- „Flugmeister am Ziel“ (mit gesetzter Markierung), dann alle Flugmeister deines Kontinents je Zone als Untermenü
-- (Flights.MastersByZone); ein Klick setzt Blizzards Markierung. Spielbefund vom 21.11.2026: „man sollte alle einzeln
-- aus dem menü markieren können“. opts.head = Text der Kopfzeile, data = MapButton.FlightData()
-- (sonst hier gelesen). → menu, oder nil, wenn nichts darin stünde
function MapButton.FillFlights(menu, opts, data)
    opts = opts or {}
    data = data or MapButton.FlightData()
    if not data then return nil end
    local nearest, zones, dest = data.nearest, data.zones, data.dest
    if opts.head then Tip(Menu.Title(menu, opts.head), opts.head, L.TRACK_FLIGHTS_TIP) end
    if nearest then
        local text = ns.Flights.MasterLabel(nearest)
        Tip(Menu.Button(menu, text, function() ns.Flights.GoMaster(nearest) end), text, L.TRACK_FLIGHT_TIP)
    end
    if dest then MapButton.AddDestinationFlight(menu) end
    if #zones > 0 then
        if nearest or dest or opts.head then Menu.Divider(menu) end
        for _, zone in ipairs(zones) do
            local sub = Menu.Button(menu, zone.name)
            for _, master in ipairs(zone.masters) do
                local m = master
                local text = m.undiscovered and L.TRACK_FLIGHT_ENTRY_NEW:format(m.name) or m.name
                Tip(Menu.Button(sub, text, function() ns.Flights.GoMaster(m) end), text, L.TRACK_FLIGHT_ENTRY_TIP)
            end
        end
    end
    return menu
end

-- „Flugmeister hier (n)“ im ezMap-Knopf der Weltkarte (Entscheidung des Nutzers vom 22.11.2026, „ok mach das so“):
-- die Flugmeister der gezeigten Zone, auf einer Kontinentkarte je Zone ein Untermenü; Klick setzt die Markierung.
-- Quelle wie im Menü „Aufspüren“ (Flights.MastersByZone, Blizzards Flugkarte). → der Knopf oder nil
function MapButton.AddFlightsHere(root, mapID)
    if not ns.Enabled("flightNearest") then return nil end
    mapID = ns.Num(mapID)
    if not mapID then return nil end
    local zones = ns.Flights.MastersByZone(mapID)
    local info = Core.Map.Info(mapID)
    local isContinent = type(info) == "table" and ns.Num(info.mapType) == 2
    local shown = not isContinent and (Core.Map.Parent(mapID, "Zone") or mapID) or nil
    local function Entry(menu, m)
        local text = m.undiscovered and L.TRACK_FLIGHT_ENTRY_NEW:format(m.name) or m.name
        Tip(Menu.Button(menu, text, function() ns.Flights.GoMaster(m) end), text, L.TRACK_FLIGHT_ENTRY_TIP)
    end
    if shown then
        local masters
        for _, z in ipairs(zones) do if z.map == shown then masters = z.masters end end
        if not masters or #masters == 0 then return nil end
        local label = L.MENU_FLIGHTS_HERE:format(#masters)
        local menu = Tip(Menu.Button(root, label), label, L.MENU_FLIGHTS_HERE_TIP)
        for _, m in ipairs(masters) do Entry(menu, m) end
        return menu
    end
    if not isContinent or #zones == 0 then return nil end
    local n = 0
    for _, z in ipairs(zones) do n = n + #z.masters end
    local label = L.MENU_FLIGHTS_HERE:format(n)
    local menu = Tip(Menu.Button(root, label), label, L.MENU_FLIGHTS_HERE_TIP)
    for _, z in ipairs(zones) do
        local sub = Menu.Button(menu, z.name)
        for _, m in ipairs(z.masters) do Entry(sub, m) end
    end
    return menu
end

-- Eigener Knopf „Flugmeister“ mit derselben Liste (Menü „Aufspüren“, wenn Blizzard seinen Haken nicht zeigt).
-- → der Knopf oder nil
function MapButton.AddFlights(root)
    local data = MapButton.FlightData()
    if not data then return nil end
    local menu = Tip(Menu.Button(root, L.MENU_FLIGHTS), L.MENU_FLIGHTS, L.TRACK_FLIGHTS_TIP)
    return MapButton.FillFlights(menu, nil, data)
end

-- Zone oder kleiner (keine Welt- oder Kontinentkarte)? Händler gibt es nur dort.
function MapButton.IsZoneMap(mapID)
    mapID = ns.Num(mapID)
    local info = mapID and Core.Map.Info(mapID)
    local mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    return mapType ~= nil and mapType >= 3
end

-- Händler der gezeigten Zone, besucht (ezCore merkt sie beim Ansprechen, Core.Npcs) und laut Questie; eine Kleinkarte
-- zählt zu ihrer Zone. Händler mit Reparatur über das Blatt „repairTargets“, die übrigen über „vendorTargets“
-- (Tree.lua). → Liste (leer: nichts bekannt, Blätter aus, Welt- oder Kontinentkarte), wartet (Questie liest noch)
function MapButton.Vendors(mapID)
    mapID = ns.Num(mapID)
    if not MapButton.IsZoneMap(mapID) then return {}, false end
    local zone = Core.Map.Parent(mapID, "Zone") or mapID
    local wantAll, wantRepair = ns.Enabled("vendorTargets"), ns.Enabled("repairTargets")
    local out = {}
    -- dazu die Händler dieser Zone laut Questie (Entscheidung des Nutzers vom 22.11.2026; besuchte gehen vor)
    local all, pending = Core.Npcs.List({ kind = "vendor", located = true, fits = true, questie = { zone, mapID } })
    for _, e in ipairs(all) do
        local m = ns.Num(e.map)
        local here = m and (m == zone or m == mapID or Core.Map.Parent(m, "Zone") == zone)
        if here and ((e.repair and wantRepair) or (not e.repair and wantAll)) then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out, pending == true
end

-- Ab so vielen Händlern stehen sie nach Titel („Gemischtwaren“, „Waffenschmied“ …) in Untermenüs
MapButton.VENDORS_FLAT = 20

local function VendorButton(menu, e)
    local text = Core.Npcs.Label(e) or e.name or "?"
    if e.repair then text = text .. " " .. L.VENDOR_REPAIR_MARK end
    return Tip(Menu.Button(menu, text, function() ns.Way.Set(e.map, e.x, e.y, e.name, true) end), text,
        L.MENU_VENDOR_ENTRY_TIP, Core.Npcs.SourceLabel(e))
end

-- Antwortet Questie nicht wie erwartet (QuestieDB läuft, aber falsche Form oder Fehler)? → Hinweiszeile oder nil.
-- Ohne Questie (missing) kein Hinweis: dann gilt wie bisher nur das Besuchte.
function MapButton.QuestieTrouble()
    local Q = Core.Sources and Core.Sources.Questie
    if type(Q) ~= "table" or type(Q.TownsfolkReady) ~= "function" then return nil end
    local ok, ready, why = pcall(Q.TownsfolkReady)
    if ok and ready then return nil end
    if not ok or why == "shape" or why == "error" then return L.MENU_NPCS_QUESTIE_BROKEN end
    return nil
end

-- Zeilen über einer Lehrer- bzw. Händlerliste: „wird gelesen …“, Questie antwortet falsch, „Noch keine …“
function MapButton.ListNotes(menu, empty, pending, none)
    if pending then Tip(Menu.Title(menu, L.MENU_NPCS_LOADING), L.MENU_NPCS_LOADING, L.MENU_NPCS_LOADING_TIP) end
    local trouble = MapButton.QuestieTrouble()
    if trouble then Tip(Menu.Title(menu, trouble), trouble, L.MENU_NPCS_QUESTIE_BROKEN_TIP) end
    if empty and not pending and none then Menu.Title(menu, none) end
end

-- Händler einer Karte (Zone) in ein Menü füllen – Kartenmenü („Händler hier (n)“) und im Menü „Aufspüren“ an
-- Blizzards Haken „Reparieren“ (Tracking.AttachVendors; Spielbefund des Nutzers vom 22.11.2026: „händler hier finde
-- ich im menü nicht“). opts.head = Kopfzeile mit Erklärung, opts.list/opts.pending = schon gelesen (Vendors).
-- → menu, Anzahl
function MapButton.FillVendors(menu, mapID, opts)
    opts = opts or {}
    local list, pending = opts.list, opts.pending
    if not list then list, pending = MapButton.Vendors(mapID) end
    if opts.head then Tip(Menu.Title(menu, opts.head), opts.head, L.MENU_VENDORS_TIP) end
    MapButton.ListNotes(menu, #list == 0, pending, L.MENU_VENDORS_NONE)
    if #list < MapButton.VENDORS_FLAT then
        for _, e in ipairs(list) do VendorButton(menu, e) end
        return menu, #list
    end
    local groups, byTitle = {}, {}
    for _, e in ipairs(list) do
        local title = e.title or L.MENU_VENDORS_UNTITLED
        local g = byTitle[title]
        if not g then
            g = { title = title, list = {} }
            byTitle[title] = g
            groups[#groups + 1] = g
        end
        g.list[#g.list + 1] = e
    end
    table.sort(groups, function(a, b) return a.title < b.title end)
    for _, g in ipairs(groups) do
        local sub = Menu.Button(menu, ("%s (%d)"):format(g.title, #g.list))
        for _, e in ipairs(g.list) do VendorButton(sub, e) end
    end
    return menu, #list
end

-- Weitere Stadtbewohner laut Questie (Core.Npcs.ROLES: Gastwirt, Bankier, Auktionator, Stallmeister, Kampfmeister) für
-- die Pfeile an Blizzards Haken im Menü „Aufspüren“ (Entscheidung des Nutzers vom 22.11.2026: „ok“ auf „Pfeil an jedem
-- Haken, hinter dem eine suchbare NPC-Art mit Daten steckt“). Einmal je Öffnen gelesen: die Stadtbewohner deines
-- Kontinents, je Rolle. Besuchte kennen diese Rollen nicht – ohne Questie bleiben die Listen leer.
-- Je Rolle mit filter.kind gelesen (Fund des code-reviewers vom 22.11.2026): so verdrängt ein besuchter NPC ohne die
-- Rolle (ein Gastwirt, bei dem du eingekauft hast, ist als Händler gemerkt) den Eintrag laut Questie nicht, und ezCore
-- wandelt nur NPCs mit dieser Rolle um (Questie liest je Karte einmal, Core.Sources.Questie.Townsfolk).
-- zone = deine Zone ohne Koordinaten (Tracking.PlayerZone, z. B. in Instanzen): dann nur ihre, wie bei den Händlern.
-- → { [Rolle] = Liste }, wartet (true, solange Questie noch liest)
function MapButton.RoleLists(zone)
    local out, waiting = {}, false
    zone = ns.Num(zone)
    local maps = ns.Trainers.QuestieMaps() or (zone and { zone }) or nil
    for _, role in ipairs(Core.Npcs.ROLES or {}) do
        out[role] = {}
        if maps then
            local list, pending = Core.Npcs.List({ kind = role, located = true, fits = true, questie = maps })
            out[role] = list
            waiting = waiting or pending == true
        end
    end
    return out, waiting
end

local function RoleButton(menu, e)
    local text = Core.Npcs.Label(e) or e.name or "?"
    return Tip(Menu.Button(menu, text, function() ns.Way.Set(e.map, e.x, e.y, e.name, true) end), text,
        L.TRACK_ROLE_ENTRY_TIP, Core.Npcs.SourceLabel(e))
end

-- Eine Rolle in Blizzards Haken füllen: Kopfzeile, „wird gelesen …“ bzw. der Questie-Hinweis, „Nächster …“ (auf deinem
-- Kontinent), darunter alle des Kontinents je Zone wie bei den Lehrern (MapButton.ZoneList; Spielbefund des Nutzers vom
-- 22.11.2026 „wieso der unterschied?“, Antwort „Ja, wie Lehrer“ – vorher nur die deiner Zone).
-- opts.list/opts.pending = schon gelesen (RoleLists), opts.zone = deine Zone (Tracking.PlayerZone; mit Position dieselbe
-- wie die aus ns.PlayerPosition, ohne Position liest RoleLists ohnehin nur sie).
-- → menu oder nil (nichts zu zeigen: Blizzards Haken bleibt ohne Pfeil, keine leere Liste an Blizzards Eintrag)
function MapButton.FillRole(menu, role, opts)
    opts = opts or {}
    local list, pending = opts.list, opts.pending
    if not list then
        local lists
        lists, pending = MapButton.RoleLists(opts.zone)
        list = lists[role] or {}
    end
    if #list == 0 and not pending and not MapButton.QuestieTrouble() then return nil end
    local head = L.TRACK_ROLE_HEAD:format(L["TRACK_ROLE_" .. role] or role)
    Tip(Menu.Title(menu, head), head, L.TRACK_ROLE_TIP)
    MapButton.ListNotes(menu, false, pending)
    local nearest = ns.Trainers.NearestOf(list)
    local format = L["TRACK_ROLE_NEAREST_" .. role]
    if nearest and format then
        NearestButton(menu, nearest, format, L.TRACK_ROLE_NEAREST_TIP)
        Menu.Divider(menu)                                     -- nearest stammt aus list: darunter steht die Liste
    end
    MapButton.ZoneList(menu, list, RoleButton, opts.zone)      -- ab TRAINERS_FLAT: deine Zone zuerst
    return menu
end

-- Knopf „Händler hier (n)“ mit Untermenü: auf jeder Zone (auch ohne Händler – sonst fehlt der Eintrag ohne Grund,
-- Leitlinie 3), nicht auf Welt- und Kontinentkarten. → der Knopf oder nil
function MapButton.AddVendors(root, mapID)
    if not ns.Tree.Any("vendors") or not MapButton.IsZoneMap(mapID) then return nil end
    local list, pending = MapButton.Vendors(mapID)
    local label = L.MENU_VENDORS:format(#list)
    local menu = Tip(Menu.Button(root, label), label, L.MENU_VENDORS_TIP)
    MapButton.FillVendors(menu, mapID, { list = list, pending = pending })
    return menu
end

-- Einträge, die Kartenmenü und Menü „Aufspüren“ teilen: Markierung entfernen und Einstellungen.
function MapButton.AddClear(root)
    return ns.Icons.Apply(Tip(Menu.Button(root, L.MENU_CLEAR, function() ns.Way.Clear(true) end), L.MENU_CLEAR,
        L.MENU_CLEAR_TIP), "menuClear")
end

-- ezCores Eintrag „Einstellungen …“ mit Zahnrad (Core.Menu.Settings, T18-8, T9-9)
function MapButton.AddSettings(root)
    return Menu.Settings(root, ns)
end

--[[
    Das Menü des ezMap-Knopfs als Tabelle (Welle 27, Zweig modul/ezmap-menue; Wunsch des Nutzers vom 16.11.2026
    „menüaufteilung und ggf. eine refactorierung sinnvoll, ein stil siehe designsystem“): Abschnitte mit Überschrift in
    der Reihenfolge der Themen des Baums (Tree.lua) – „Wegpunkte“, „Dienste in der Stadt“, „Reise“, „Sammeln“,
    „Entdecken“, „Was ezMap auf der Karte zeigt“ –, am Ende „Einstellungen“. Ein Abschnitt erscheint nur, wenn er
    etwas enthält (Core.Menu.Section). Je Eintrag: Schlüssel, Symbol (Icons.DEF; Vorgabe über ns.Icons.Root, ein
    eigenes Symbol des Bausteins gilt davor) und der Baustein, der ihn baut
    (build(root, mapID); ob er etwas zeigt, entscheidet der Baustein selbst – Schalter des Baums, Daten, Rücksicht).
    Jeder Baustein läuft für sich (ns.Try): ein Fehler kostet nur seinen Eintrag. Alle Funktionen von vorher bleiben
    erreichbar (Leitlinie 3); „Wo am dichtesten?“ wird je Menü nur einmal gerechnet (Gather.WithDenseMemo).
]]
MapButton.SECTIONS = {
    { id = "way", title = "MSEC_WAY", icon = "own", entries = { "enter", "here", "clear", "link", "destFlight", "recent" } },
    { id = "town", title = "OPT_tree_town", icon = "town", entries = { "trainers", "vendors" } },
    { id = "journey", title = "OPT_tree_journey", icon = "journey", entries = { "flightsHere", "flightNodes", "entrances", "zones", "levelRoute" } },
    { id = "gather", title = "OPT_tree_gather", icon = "gather", entries = { "gather" } },
    { id = "discover", title = "OPT_tree_discover", icon = "discover", entries = { "books", "rares" } },
    { id = "show", title = "MSEC_SHOW", icon = "menuTree", entries = { "tree", "entrancePins", "coords", "bookToggle" } },
}

MapButton.ENTRIES = {
    enter = { icon = "menuEnter", build = function(root)
        Tip(Menu.Button(root, L.MENU_ENTER, function() ns.Way.Ask(ShownMapID()) end), L.MENU_ENTER, L.MENU_ENTER_TIP)
    end },
    here = { icon = "menuHere", build = function(root)
        Tip(Menu.Button(root, L.MENU_HERE, function() ns.Way.SetHere(nil, true) end), L.MENU_HERE, L.MENU_HERE_TIP)
    end },
    clear = { icon = "menuClear", build = function(root) if ns.Way.Get() then MapButton.AddClear(root) end end },
    link = { icon = "menuLink", build = function(root)
        if ns.Way.Get() then Tip(Menu.Button(root, L.MENU_LINK, ns.Way.ShareLink), L.MENU_LINK, L.MENU_LINK_TIP) end
    end },
    -- „Flugmeister am Ziel: …“ und die gelernte Flugzeit dorthin
    destFlight = { icon = "travel", build = function(root) if ns.Way.Get() then MapButton.AddDestinationFlight(root) end end },
    recent = { icon = "wayRecent", build = function(root) MapButton.AddRecent(root) end },
    trainers = { icon = "trainers", build = function(root, mapID) MapButton.AddTrainers(root, { map = mapID }) end },
    -- besuchte Händler der Zone (Gruppe „Händler“ im Baum)
    vendors = { icon = "vendors", build = function(root, mapID) MapButton.AddVendors(root, mapID) end },
    -- „Flugpunkte, die dir fehlen“ samt Twinks (Welle 26, F5)
    flightsHere = { icon = "travel", build = function(root, mapID) MapButton.AddFlightsHere(root, mapID) end },
    flightNodes = { icon = "flightMissing", build = function(root, mapID) ns.FlightNodes.AddMenu(root, mapID) end },
    entrances = { icon = "dungeons", build = function(root, mapID) MapButton.AddEntrances(root, mapID) end },
    -- „Zonenstufen: 5–12 (bei dir gesehen)“ mit Quelle (MAP-06)
    zones = { icon = "menuZones", build = function(root, mapID) ns.Zones.AddMenu(root, mapID) end },
    -- „Leveling-Route“ von ezQuest (Welle 27, zweiter Weg neben Blizzards Zahnrad-Menü am Questlog): ezQuest baut den
    -- Eintrag selbst (ezCore.API("ezQuest").AddLevelRouteMenu); ohne ezQuest oder mit abgeschalteter Route kein Eintrag
    levelRoute = { icon = "route", build = function(root)
        local api = Core.API("ezQuest")
        if type(api) == "table" and type(api.AddLevelRouteMenu) == "function" then api.AddLevelRouteMenu(root) end
    end },
    -- „Sammel-Fundorte“ bzw. (nur mit mapFilterSection) der Verweis auf Blizzards Kartenfilter (SAM-12). Als Untermenü
    -- bringt der Abschnitt „Route durch diese Zone“ (SAM-21) und „Wo am dichtesten?“ (SAM-23) selbst mit; sonst stehen
    -- beide hier – je mit eigenem Symbol (Route.AddMenu, Gather.AddDenseMenu; Fund des code-reviewers vom 17.11.2026)
    gather = { icon = "gather", build = function(root, mapID)
        if ns.Gather.AddMapMenu(root, mapID) == "filter" then
            ns.Route.AddMenu(root, mapID)
            ns.Gather.AddDenseMenu(root, mapID)
        end
    end },
    -- „Bibliotheksbücher“: fehlende Bücher der Zone mit Fundort (MAP-07)
    books = { icon = "bookTargets", build = function(root, mapID) ns.Books.AddMenu(root, mapID) end },
    -- „Letzter seltener Gegner – Wegpunkt“, sobald einer gemeldet wurde
    rares = { icon = "rarePins", build = function(root) ns.Rares.AddMenu(root) end },
    -- „Was ezMap auf der Karte zeigt“: der Baum (ohne „Sammeln“), außer er steht auf Wunsch in Blizzards Kartenfilter
    tree = { icon = "menuTree", build = function(root, mapID) MapButton.AddTree(root, mapID) end },
    -- Schalter „Dungeoneingänge auf der Karte“, „Koordinaten auf der Karte“ (oder wer sie schon zeigt),
    -- „Bibliotheksbücher im Kartenmenü“ (Entdecker-Wissen, ab Werk aus) – nur, wenn der Baum nicht im Knopf steht
    -- (MapButton.TreeInMenu): dort sind es Blätter unter „Reise“, „Eigene Wegpunkte“ und „Entdecken“, sonst stünden
    -- sie zweimal im Menü (Gegenprüfung vom 18.11.2026). Wer die Koordinaten schon zeigt, steht immer da.
    entrancePins = { icon = "dungeons", build = function(root)
        if not MapButton.TreeInMenu() then ns.Entrances.AddMenuToggle(root) end
    end },
    coords = { icon = "mapCoords", build = function(root) ns.MapCoords.AddMenuToggle(root, MapButton.TreeInMenu()) end },
    bookToggle = { icon = "bookPins", build = function(root)
        if not MapButton.TreeInMenu() then ns.Books.AddMenuToggle(root) end
    end },
}

-- Abschnitte bauen (auch für Prüfungen): → Liste der Abschnitte, die etwas enthalten
function MapButton.BuildSections(root, mapID, sections, entries)
    local used = {}
    local chain = {}    -- der erste Abschnitt, der etwas enthält, steht ohne Trenner direkt unter dem Titel
    for _, section in ipairs(sections or MapButton.SECTIONS) do
        local sec = Menu.Section(root, L[section.title] or section.title,
            { icon = ns.Icons.For(section.icon), first = section.first, chain = chain })
        for _, key in ipairs(section.entries) do
            local e = (entries or MapButton.ENTRIES)[key]
            if e and type(e.build) == "function" then
                ns.Try("MapMenu:" .. key, e.build, ns.Icons.Root(sec, e.icon), mapID)
            end
        end
        if sec.Used() then used[#used + 1] = section.id end
    end
    return used
end

local function BuildMenuNow(root)
    Tip(Menu.Title(root, L.MENU_TITLE), L.MENU_TITLE, L.MENU_TITLE_TIP)
    MapButton.BuildSections(root, ShownMapID())
    Menu.Divider(root)
    MapButton.AddSettings(root)
end

function MapButton.BuildMenu(root) return ns.Gather.WithDenseMemo(BuildMenuNow, root) end

-- Der Baum (Tree.lua) im ezMap-Knopf als Untermenü – seit dem 18.11.2026 immer, außer ezMaps Abschnitt steht auf
-- Wunsch (Schalter mapFilterSection) in Blizzards Kartenfilter und wurde dort schon gebaut (Gather.InFilter). Die
-- Gruppe „Sammeln“ fehlt hier: sie hat im Knopf ihren eigenen Abschnitt („Sammel-Fundorte“, Gather.BuildSection mit
-- denselben Einträgen, aber ohne Kisten – die stehen im Baum unter „Entdecken“). Die Schalter für Eingänge,
-- Koordinaten und Bücher im Abschnitt „Anzeige auf der Karte“ entfallen dann (MapButton.TreeInMenu): jede Funktion
-- steht so genau einmal im Menü (Gegenprüfung vom 18.11.2026). → "menu" | "filter"
function MapButton.AddTree(root, mapID)
    if ns.Gather.InFilter() then return "filter" end
    local sub = Tip(Menu.Button(root, L.TREE_MENU), L.TREE_MENU, L.TREE_MENU_TIP)
    -- „Einstellungen“ steht am Ende des Knopf-Menüs
    ns.Tree.AddAll(sub, mapID, { noSettings = true, skip = MapButton.TREE_SKIP })
    return "menu"
end

-- Gruppen des Baums, die im Untermenü des Knopfs fehlen, weil sie einen eigenen Abschnitt haben
MapButton.TREE_SKIP = { gather = true }

-- Steht der Baum gerade im Knopf (MapButton.AddTree)? Nein nur, wenn ezMaps Abschnitt in Blizzards Kartenfilter steht.
function MapButton.TreeInMenu() return not ns.Gather.InFilter() end

-- Menü über ezCore (Blizzards MenuUtil); ohne MenuUtil bleibt die Koordinaten-Eingabe.
function MapButton.OpenMenu()
    local opened = Menu.Open(button, function(root) ns.Try("MapMenu", MapButton.BuildMenu, root) end)
    if not opened then return ns.Way.Ask(ShownMapID()) end
end

---------------------------------------------------------------------------
-- Knopf (Aufbau wie Blizzards WorldMapTrackingPinButtonTemplate)
---------------------------------------------------------------------------

-- Tooltip nach Entscheidung 5 vom 18.11.2026: Titel, Stand, Linksklick (Menü), Rechtsklick (Einstellungen), Befehlszeile
local function OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    Core.TipTitle(GameTooltip, L.MENU_TITLE)
    local mapID, x, y, title = ns.Way.Get()
    if mapID then
        GameTooltip:AddLine(L.WAY_CURRENT:format(ns.Way.Describe({ map = mapID, x = x, y = y, title = title })), nil, nil, nil, true)
    else
        Core.TipLine(GameTooltip, L.WAY_NONE, "hint", true)
    end
    GameTooltip:AddLine(L.MAP_BUTTON_HINT, nil, nil, nil, true)
    GameTooltip:AddLine(L.MAP_BUTTON_RIGHT, nil, nil, nil, true)
    Core.TipClick(GameTooltip, L.MAP_BUTTON_SLASH:format(ns.Way.slash))
    GameTooltip:Show()
end

-- Klick: links (und ohne Angabe) das Menü, rechts die Einstellungen (Entscheidung 5 vom 18.11.2026)
function MapButton.Click(mouse)
    GameTooltip:Hide()
    if mouse == "RightButton" then return ns.OpenSettings() end
    return MapButton.OpenMenu()
end

function MapButton.Create()
    if button or not WorldMapFrame then return button end
    button = CreateFrame("Button", "ezMapWorldMapButton", WorldMapFrame)
    -- Maße wie Blizzards runder Knopf an der Minikarte bzw. der Kartenknopf daneben (Knopf 32, Hintergrund
    -- UI-Minimap-Background 25, Symbol 20, Rand MiniMap-TrackingBorder 54) – folgen einem Blizzard-Teil und bleiben
    -- bewusst außerhalb Core.Style.ICON/BUTTON (Design-System 2.3)
    button:SetSize(32, 32)
    button:SetFrameStrata("HIGH")
    local pin = WorldMapFrame.WorldMapTrackingPinButton
    if pin and pin.GetFrameLevel then button:SetFrameLevel(pin:GetFrameLevel()) end

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(25, 25)
    background:SetPoint("TOPLEFT", 3, -4)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -6)
    Core.SetIcon(icon, "Waypoint-MapPin-Tracked", "Interface\\Icons\\INV_Misc_Map_01")
    button.Icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 8, -8) end)
    button:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 7, -6) end)
    button:SetScript("OnClick", function(_, mouse) MapButton.Click(mouse) end)
    button:SetScript("OnEnter", OnEnter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    WorldMapFrame:HookScript("OnShow", function()
        ns.Try("MapButton", MapButton.Refresh)
        ns.Try("Guide", ns.Guide.Start)     -- Erklärblasen beim ersten Öffnen der Karte
    end)
    MapButton.Refresh()
    return button
end

function MapButton.Refresh()
    if not button then return end
    Anchor()
    button:SetShown(ns.Enabled("mapButton"))
end

function MapButton.Get() return button end

-- Wo ezMap an der Weltkarte steht – EINE Auswahl auf der Einstellungsseite statt der Haken „Knopf auf der Weltkarte“
-- und „ezMap auch in Blizzards Kartenfilter“ (Einstellungs-Prüfung vom 19.11.2026, Nr. 80, 81: der zweite wirkte ohne
-- den ersten nicht, Gather.FilterWanted). Gespeichert bleiben mapButton und mapFilterSection.
--   "button"  nur der ezMap-Knopf (ab Werk)      "filter"  nur Blizzards Kartenfilter      "both"  beides
MapButton.PLACES = { "button", "filter", "both" }
function MapButton.Place()
    if not ns.Enabled("mapButton") then return "filter" end
    return ns.Enabled("mapFilterSection") and "both" or "button"
end

function MapButton.SetPlace(place)
    if place == "button" then
        ns.SetSetting("mapFilterSection", false)
        ns.SetSetting("mapButton", true)
    elseif place == "filter" then
        ns.SetSetting("mapFilterSection", true)
        ns.SetSetting("mapButton", false)
    elseif place == "both" then
        ns.SetSetting("mapFilterSection", true)
        ns.SetSetting("mapButton", true)
    else
        return false
    end
    return true
end

function MapButton.PlaceValues()
    local values = {}
    for i, place in ipairs(MapButton.PLACES) do values[i] = { place, L["MAP_PLACE_" .. place] } end
    return values
end

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_WorldMap", function() ns.Try("MapButton", MapButton.Create) end)
end)

ns.OnSettingChanged(function(key)
    if key == "mapButton" then MapButton.Refresh() end
end)

-- Was andere Addons auf der Karte zeichnen (Flugpunkte, Dungeoneingänge): ezMap setzt dafür keine eigenen Symbole.
-- Koordinaten haben ihre eigene Statuszeile (MapCoords.lua).
ns.AddStatusLine(function()
    local parts = {}
    for _, item in ipairs(ns.MapFeaturesElsewhere()) do
        parts[#parts + 1] = ("%s (%s)"):format(L["FEATURE_" .. item.feature], item.who)
    end
    if #parts == 0 then return nil end
    return L.STATUS_MAP_OTHER:format(table.concat(parts, ", "))
end)
