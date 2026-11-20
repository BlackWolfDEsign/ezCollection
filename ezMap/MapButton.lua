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
function MapButton.AddTrainers(root)
    if not ns.Tree.Any("trainers") then return end
    local menu = Tip(Menu.Button(root, L.MENU_TRAINERS), L.MENU_TRAINERS, L.MENU_TRAINERS_TIP)
    local list = {}
    for _, t in ipairs(ns.Trainers.List()) do
        if MapButton.TrainerWanted(t) then list[#list + 1] = t end
    end
    if #list == 0 then
        Menu.Title(menu, L.MENU_TRAINERS_NONE)
    else
        local nearest = ns.Tree.Leaf("trainerClass") and ns.Trainers.Nearest("class") or nil
        if nearest then
            local text = L.MENU_TRAINER_NEAREST:format(nearest.name)
            Tip(Menu.Button(menu, text, function() ns.Trainers.Go(nearest) end), text, L.MENU_TRAINER_NEAREST_TIP)
        end
        -- Tierausbilder braucht nur der Jäger; in der Liste darunter stehen sie für alle
        local pet = ns.playerClass == "HUNTER" and ns.Tree.Leaf("trainerPet") and ns.Trainers.Nearest("pet") or nil
        if pet then
            local text = L.MENU_TRAINER_NEAREST_PET:format(pet.name)
            Tip(Menu.Button(menu, text, function() ns.Trainers.Go(pet) end), text, L.MENU_TRAINER_NEAREST_PET_TIP)
        end
        if nearest or pet then Menu.Divider(menu) end
        local zone
        for _, t in ipairs(list) do
            local name = ns.MapName(t.map)
            if name ~= zone then
                zone = name
                Menu.Title(menu, name)
            end
            local label = ns.Trainers.Label(t)
            Tip(Menu.Button(menu, label, function() ns.Trainers.Go(t) end), label, L.MENU_TRAINER_ENTRY_TIP)
        end
    end
    local other = ns.TrainersElsewhere()
    if other then
        Menu.Divider(menu)
        MapButton.OtherTitle(menu, L.MENU_TRAINERS_OTHER:format(other), L.MENU_TRAINERS_OTHER_TIP)
    end
end

-- Dungeoneingänge der gezeigten Karte (auf einer Kontinentkarte die ihrer Zonen): zuerst aus ezCore.Dungeons, das
-- sie aus Blizzards Daten liest, dann die selbst betretenen (Entrances.lua nennt je Eintrag die Quelle). Nach Stufe
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
-- und darunter die Flugzeit von deinem nächsten Flugmeister dorthin – mit Quelle („bei dir gemessen“) oder „noch
-- unbekannt“. Kein Routenplaner (Flights.lua). Für das Kartenmenü und das Menü „Aufspüren“.
function MapButton.AddDestinationFlight(root)
    if not ns.Enabled("flightDest") then return false end
    local dest, own, seconds = ns.Flights.AtWaypoint()
    if not dest then return false end
    local label = ns.Flights.DestinationLabel(dest)
    Tip(Menu.Button(root, label, function() ns.Flights.GoMaster(dest) end), label, L.MENU_FLIGHT_DEST_TIP)
    local line = ns.Flights.DestinationTimeLabel(dest, own, seconds)
    if line then
        local title = Menu.Title(root, line)
        if seconds then Tip(title, line, L.MENU_FLIGHT_DEST_TIME_TIP) end
    end
    return true
end

-- Besuchte Händler der gezeigten Zone (ezCore merkt sie beim Ansprechen, Core.Npcs; eine Kleinkarte zählt zu ihrer
-- Zone): Klick setzt die Markierung. Händler mit Reparatur über das Blatt „repairTargets“, die übrigen über
-- „vendorTargets“ (Tree.lua). → der Eintrag oder nil (nichts bekannt, Blätter aus, Welt- oder Kontinentkarte)
function MapButton.Vendors(mapID)
    mapID = ns.Num(mapID)
    local info = mapID and Core.Map.Info(mapID)
    local mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    if not (mapType and mapType >= 3) then return {} end
    local zone = Core.Map.Parent(mapID, "Zone") or mapID
    local wantAll, wantRepair = ns.Enabled("vendorTargets"), ns.Enabled("repairTargets")
    local out = {}
    for _, e in ipairs(Core.Npcs.List({ kind = "vendor", located = true, fits = true })) do
        local m = ns.Num(e.map)
        local here = m and (m == zone or m == mapID or Core.Map.Parent(m, "Zone") == zone)
        if here and ((e.repair and wantRepair) or (not e.repair and wantAll)) then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

function MapButton.AddVendors(root, mapID)
    if not ns.Tree.Any("vendors") then return nil end
    local list = MapButton.Vendors(mapID)
    if #list == 0 then return nil end
    local label = L.MENU_VENDORS:format(#list)
    local menu = Tip(Menu.Button(root, label), label, L.MENU_VENDORS_TIP)
    for _, e in ipairs(list) do
        local text = Core.Npcs.Label(e) or e.name or "?"
        if e.repair then text = text .. " " .. L.VENDOR_REPAIR_MARK end
        Tip(Menu.Button(menu, text, function() ns.Way.Set(e.map, e.x, e.y, e.name, true) end), text,
            L.MENU_VENDOR_ENTRY_TIP)
    end
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
    { id = "journey", title = "OPT_tree_journey", icon = "journey", entries = { "flightNodes", "entrances", "zones", "levelRoute" } },
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
    trainers = { icon = "trainers", build = function(root) MapButton.AddTrainers(root) end },
    -- besuchte Händler der Zone (Gruppe „Händler“ im Baum)
    vendors = { icon = "vendors", build = function(root, mapID) MapButton.AddVendors(root, mapID) end },
    -- „Flugpunkte, die dir fehlen“ samt Twinks (Welle 26, F5)
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
    Menu.Title(root, L.MENU_TITLE)
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
