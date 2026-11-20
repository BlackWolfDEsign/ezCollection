local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Flugpunkte, die ein Charakter noch nicht kennt (Welle 26, Folge-Paket F5 aus docs/wago-tools.md, Abschnitt 4; Wunsch
    des Nutzers vom 16.11.2026: „grundsätzlich allen nützlichen infos von wago direkt nutzen z.b. in db oder
    validierung“, Wortlaut im ROADMAP-Index).

    Quellen (Leitlinie 11):
      welche Flugpunkte es gibt   ezCores Client-Wissen (Core.ClientData.TaxiNodes über Core.Route.FlightNodes und
                                  Route.MissingFlightNodes; laut Client-Tabellen, wago.tools) – nur Punkte mit Fraktion
                                  und Strecke, getrennt nach Kontinent und Fraktion
      welche ein Charakter kennt  Blizzards Flugkarte am Flugmeister (C_TaxiMap.GetAllTaxiNodes: bekannt sind nur die
                                  Zustände „hier“ und „erreichbar“ (Enum.FlightPathState Current, Reachable); ohne
                                  Zustand die Classic-Flugkarte: TaxiNodeGetType "CURRENT", "REACHABLE" bekannt, "NONE"
                                  unbekannt; „nicht erreichbar“ bzw. "DISTANT" bleibt offen) und Blizzards Weltkarte
                                  (C_TaxiMap.GetTaxiNodesForMap mit isUndiscovered; sie entscheidet die offenen) – gelesen beim Einloggen, am Flugmeister und beim Öffnen des
                                  Kartenmenüs. Ein Punkt gilt erst als unbekannt, wenn die Tabelle ihn führt und der
                                  Charakter ihn nicht kennt; ohne jede Angabe des Clients sagt ezMap „noch nicht erfasst“.
                                  Das gilt je Kontinent: erst wenn die Flugkarte oder die Weltkarte des ganzen Kontinents
                                  etwas über seine Punkte gesagt hat, heißt ein dort unbekannter Punkt „fehlt“.
      Twinks                      ezCores Charakterdaten (Core.CharacterList, Core.Char: Name, Klasse, Fraktion); das
                                  Bekannte je Charakter merkt ezMap in ezMapDB.taxiKnown[charKey] = { nodes = { [ID] =
                                  true }, seen = { [Kontinent] = Zeit }, at, src, faction } – accountweit, damit jeder Twink die Liste der anderen sieht.
                                  Vergisst ezCore einen Charakter (CHAR_FORGOTTEN), fällt sein Eintrag.
      Namen                       Blizzards Weltkarte bzw. Flugkarte (nur im Speicher der Sitzung), sonst ezCores Texte
                                  (beim Fliegen gemerkt, Flights.NodeLabel), sonst „#ID“

    Sichtbar (Leitlinie 3): Untermenü „Flugpunkte, die dir fehlen“ im ezMap-Knopf der Weltkarte (für den Kontinent der
    gezeigten Karte, darunter je Twink), Schalter flightMissing im Baum (Gruppe „Reisen und Flugmeister“, Einstellungen
    und Kartenfilter) und eine Zeile im Tooltip von Blizzards Flugpunkten auf der Weltkarte („Noch nicht entdeckt von:
    …“ – nur Twinks; ob du selbst ihn kennst, sagt Blizzards Tooltip schon). Kein eigenes Fenster, keine eigenen
    Kartensymbole, nichts in Blizzards Tabellen (Leitlinien 1 und 5).

      FlightNodes.Learn(charKey?, liste, quelle) → Zahl der neu bekannten; liste = { { id, known = true | false, name } }
      FlightNodes.LearnFromTaxiMap()          am Flugmeister (TAXIMAP_OPENED)
      FlightNodes.LearnFromMap(uiMapID)       Blizzards Flugpunkte einer Karte
      FlightNodes.Scan()                      beim Einloggen: die Kontinente der Tabelle und der eigene
      FlightNodes.ContinentOf(uiMapID)        → Kontinent (Map-ID der Client-Tabellen) oder nil
      FlightNodes.Missing(charKey, kontinent) → { ID … } oder nil, Grund ("unseen" | "nodata" | "nocontinent")
      FlightNodes.Known(charKey, ID)          → true | false | nil (Kontinent des Punkts nicht erfasst)
      FlightNodes.Twinks(kontinent)           → erfasste, nicht erfasste Twinks (je Kontinent)
      FlightNodes.Name(ID), FlightNodes.Place(ID) → Name; uiMapID, x, y oder nil
      FlightNodes.AddMenu(root, uiMapID)      Untermenü im Kartenmenü → Eintrag oder nil
      FlightNodes.TwinksMissing(ID)           → { { key, c } … } Twinks (nicht du), die den Punkt nicht kennen
      FlightNodes.TwinkTip(rec, alle)         → Tooltip eines Twinks im Untermenü („Stand: zuletzt erfasst vor …“)
]]
local FlightNodes = {}
ns.FlightNodes = FlightNodes

FlightNodes.TWINKS_IN_TIP = 5     -- so viele Twinks nennt der Tooltip am Flugpunkt, dann „und n weitere“

-- Blizzards Zustände der Flugkarte (Enum.FlightPathState; Werte wie in Blizzards Quelle, falls das Enum fehlt)
FlightNodes.STATE = {
    Current = Enum and Enum.FlightPathState and Enum.FlightPathState.Current or 0,
    Reachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Reachable or 1,
}

local names = {}        -- [ID] = Name aus Blizzards Karten (Sitzung)
local places = {}       -- [ID] = { map, x, y } aus Blizzards Weltkarte (Sitzung)

local function ClientData()
    local CD = Core.ClientData
    return type(CD) == "table" and type(CD.TaxiNode) == "function" and CD or nil
end

local function RouteAPI()
    local R = Core.Route
    return type(R) == "table" and type(R.MissingFlightNodes) == "function" and R or nil
end

local function Store()
    local db = ns.db
    if type(db) ~= "table" then return {} end
    if type(db.taxiKnown) ~= "table" then db.taxiKnown = {} end
    return db.taxiKnown
end

local function Record(key, create)
    local store = Store()
    local rec = store[key]
    if type(rec) ~= "table" then
        if not create then return nil end
        rec = {}
        store[key] = rec
    end
    if type(rec.nodes) ~= "table" then rec.nodes = {} end
    if type(rec.seen) ~= "table" then rec.seen = {} end
    return rec
end
FlightNodes.Record = Record

-- Ist das Bekannte des Charakters auf diesem Kontinent erfasst? (nil-Kontinent: irgendwo erfasst)
local function SeenOn(rec, continent)
    if not (rec and rec.at) then return false end
    if continent == nil then return true end
    return rec.seen[continent] ~= nil
end
FlightNodes.SeenOn = SeenOn

local function MyKey() return Core.charKey end

local function PlainName(name)
    if ns.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name:match("^[^,]+") or name
end

---------------------------------------------------------------------------
-- Lernen
---------------------------------------------------------------------------

-- Ein Punkt, den Blizzard als unbekannt meldet, fällt aus der Liste; ein bekannter kommt dazu. Punkte ohne Angabe
-- bleiben, wie sie waren (Flugpunkte vergisst man nicht). Erfasst ist ein Kontinent erst, wenn eine Angabe zu einem
-- seiner Punkte kam (rec.seen[Kontinent] = Zeit; Kontinent laut Client-Tabelle) – nur dann zählt ein fehlender Punkt
-- dort als „fehlt“. partial = true: die Liste nennt nur einen Ausschnitt des Kontinents (Zonenkarte), Bekanntes wird
-- gelernt, der Kontinent gilt aber nicht als erfasst. → Zahl der neu bekannten
function FlightNodes.Learn(key, list, source, partial)
    key = key or MyKey()
    if type(key) ~= "string" or type(list) ~= "table" then return 0 end
    local CD = ClientData()
    local any, continents = false, {}
    for _, e in ipairs(list) do
        local id = ns.Num(e.id)
        if id and e.name then names[id] = e.name end
        if id and (e.known == true or e.known == false) then
            any = true
            local node = CD and CD.TaxiNode(id)
            if node and node.continent then continents[node.continent] = true end
        end
    end
    if not any then return 0 end
    local rec, added = Record(key, true), 0
    if not partial then
        for continent in pairs(continents) do rec.seen[continent] = time() end
    end
    for _, e in ipairs(list) do
        local id = ns.Num(e.id)
        if id and e.known == true and not rec.nodes[id] then
            rec.nodes[id] = true
            added = added + 1
        elseif id and e.known == false then
            rec.nodes[id] = nil
        end
    end
    rec.at = time()
    rec.src = source or rec.src
    if key == MyKey() then rec.faction = ns.faction or (Core.me and Core.me.faction) or rec.faction end
    return added
end

-- Classic-Flugkarte: Art je Platz. CURRENT und REACHABLE sind sicher bekannt, NONE unbekannt. DISTANT („von hier
-- nicht erreichbar“) zählt nicht: ob der Punkt dann bekannt ist, sagt Blizzards Weltkarte (isUndiscovered).
local KNOWN_TYPE = { CURRENT = true, REACHABLE = true }

-- Am Flugmeister: „hier“ und „erreichbar“ (Enum.FlightPathState Current, Reachable) sind bekannt; „nicht erreichbar“
-- lässt ezMap offen (die Weltkarte entscheidet). Fehlt der Zustand (ältere Flugkarte), entscheidet die Art des Platzes.
function FlightNodes.LearnFromTaxiMap()
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetTaxiMapID) then return 0 end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, GetTaxiMapID())
    if not ok or ns.IsSecret(nodes) or type(nodes) ~= "table" then return 0 end
    local list = {}
    for _, node in ipairs(nodes) do
        if type(node) == "table" and not ns.IsSecret(node.nodeID) then
            local id, known = ns.Num(node.nodeID), nil
            local state = ns.Num(ns.Plain(node.state))
            if state then
                if state == FlightNodes.STATE.Current or state == FlightNodes.STATE.Reachable then known = true end
            elseif type(TaxiNodeGetType) == "function" and ns.Num(node.slotIndex) then
                local kind = ns.Plain(TaxiNodeGetType(node.slotIndex))
                if KNOWN_TYPE[kind] then known = true elseif kind == "NONE" then known = false end
            end
            if id then list[#list + 1] = { id = id, known = known, name = PlainName(node.name) } end
        end
    end
    return FlightNodes.Learn(MyKey(), list, "taxi")
end

-- Blizzards Flugpunkte einer Karte (so zeigt sie die Weltkarte): isUndiscovered = true heißt unbekannt, false bekannt;
-- ohne das Feld nur Name und Lage.
function FlightNodes.LearnFromMap(mapID)
    mapID = ns.Num(mapID)
    if not (mapID and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return 0 end
    local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, mapID)
    if not ok or ns.IsSecret(nodes) or type(nodes) ~= "table" then return 0 end
    -- Lage nur von Zonen und Kleinkarten merken (auf einer Kontinentkarte lässt Blizzard keine Markierung zu)
    local info = Core.Map.Info(mapID)
    local zoneLevel = info and (ns.Num(info.mapType) or 0) >= Core.Map.TYPES.Zone
    -- erfasst ist der Kontinent nur über eine Karte, die ihn ganz zeigt (Kontinent oder darüber)
    local whole = info and (ns.Num(info.mapType) or 99) <= Core.Map.TYPES.Continent
    local list = {}
    for _, node in ipairs(nodes) do
        local id = type(node) == "table" and not ns.IsSecret(node.nodeID) and ns.Num(node.nodeID) or nil
        if id then
            local flag, known = node.isUndiscovered, nil
            if not ns.IsSecret(flag) then
                if flag == true then known = false elseif flag == false then known = true end
            end
            local x, y = Core.Map.XY(node.position)
            if x and y and zoneLevel and not places[id] then places[id] = { map = mapID, x = x, y = y } end
            list[#list + 1] = { id = id, known = known, name = PlainName(node.name) }
        end
    end
    return FlightNodes.Learn(MyKey(), list, "map", not whole)
end

-- Kontinent (Map-ID wie in den Client-Tabellen) einer Karte: über die Weltlage ihrer Mitte.
function FlightNodes.ContinentOf(mapID)
    local continent = Core.Map.WorldPos(mapID, 0.5, 0.5)
    return continent
end

-- Karte und Lage eines Flugpunkts: zuerst Blizzards eigene Lage (Weltkarte), sonst die Weltkoordinaten der
-- Client-Tabellen auf die passende Karte umgerechnet. → uiMapID, x, y oder nil
function FlightNodes.Place(id)
    id = ns.Num(id)
    local p = id and places[id]
    if p then return p.map, p.x, p.y end
    local CD = ClientData()
    local node = id and CD and CD.TaxiNode(id)
    local api, vector = rawget(_G, "C_Map"), rawget(_G, "CreateVector2D")
    if node and node.x and node.y and type(api) == "table" and type(api.GetMapPosFromWorldPos) == "function"
        and type(vector) == "function" then
        local ok, mapID, pos = pcall(api.GetMapPosFromWorldPos, node.continent, vector(node.x, node.y))
        local x, y = Core.Map.XY(ok and pos or nil)
        mapID = ok and ns.Num(mapID) or nil
        if mapID and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            -- auf die Zone darüber, wenn es eine Kleinkarte ist (die Markierung gehört in die Zone)
            local zone = Core.Map.Parent(mapID, "Zone")
            if zone and zone ~= mapID then
                local zx, zy = Core.Map.PosOn(zone, mapID, x, y)
                if zx then return zone, zx, zy end
            end
            return mapID, x, y
        end
    end
    return nil
end

-- Beim Einloggen: die Kontinente, auf denen die Tabelle Flugpunkte führt, und der Kontinent, auf dem du stehst.
function FlightNodes.Scan()
    local CD = ClientData()
    local seen, maps = {}, {}
    local function Add(mapID)
        local continent = mapID and Core.Map.Parent(mapID, "Continent")
        if continent and not seen[continent] then
            seen[continent] = true
            maps[#maps + 1] = continent
        end
    end
    -- je Kontinent der erste Flugpunkt, dessen Lage der Client umrechnen kann
    local done = {}
    for _, node in ipairs(CD and CD.TaxiNodes() or {}) do
        if node.continent and not done[node.continent] then
            local mapID = FlightNodes.Place(node.id)
            if mapID then
                done[node.continent] = true
                Add(mapID)
            end
        end
    end
    local api = rawget(_G, "C_Map")
    if type(api) == "table" then Add(Core.Call(api.GetBestMapForUnit, "player")) end
    local added = 0
    for _, mapID in ipairs(maps) do added = added + FlightNodes.LearnFromMap(mapID) end
    return added, maps
end

---------------------------------------------------------------------------
-- Abfragen
---------------------------------------------------------------------------

local function FactionOf(key, rec)
    if rec and rec.faction then return rec.faction end
    local c = Core.Char(key)
    return c and c.faction or nil
end

function FlightNodes.Known(key, id)
    local rec = Record(key or MyKey())
    id = ns.Num(id)
    if not (rec and rec.at and id) then return nil end
    local CD = ClientData()
    local node = CD and CD.TaxiNode(id)
    if node and node.continent and not SeenOn(rec, node.continent) then return nil end
    return rec.nodes[id] == true
end

-- Flugpunkte des Kontinents (Fraktion des Charakters), die er nicht kennt. → { ID … } oder nil, Grund
function FlightNodes.Missing(key, continent)
    key = key or MyKey()
    local R = RouteAPI()
    if not (R and ClientData()) then return nil, "nodata" end
    continent = ns.Num(continent)
    if not continent then return nil, "nocontinent" end
    local rec = Record(key)
    if not SeenOn(rec, continent) then return nil, "unseen" end
    return R.MissingFlightNodes(rec.nodes, continent, FactionOf(key, rec))
end

-- Alle Flugpunkte des Kontinents für die Fraktion des Charakters (für „du kennst alle n“)
function FlightNodes.Total(key, continent)
    local R = Core.Route
    if not (type(R) == "table" and type(R.FlightNodes) == "function") then return 0 end
    return #R.FlightNodes(ns.Num(continent), FactionOf(key or MyKey(), Record(key or MyKey())))
end

function FlightNodes.Name(id)
    id = ns.Num(id)
    if not id then return "?" end
    if names[id] then return names[id] end
    if ns.Flights and ns.Flights.NodeLabel and ns.Discovery.DB() then
        local label = ns.Flights.NodeLabel(id)
        if type(label) == "string" and label ~= "" then return label end
    end
    return "#" .. tostring(id)
end

-- „Goldhain (Wald von Elwynn)“; ohne Karte nur der Name
function FlightNodes.Label(id)
    local mapID = FlightNodes.Place(id)
    if mapID then return L.TAXI_ENTRY:format(FlightNodes.Name(id), ns.MapName(mapID)) end
    return FlightNodes.Name(id)
end

function FlightNodes.Go(id)
    local mapID, x, y = FlightNodes.Place(id)
    if not mapID then return false end
    return ns.Way.Set(mapID, x, y, FlightNodes.Name(id), true)
end

-- Twinks (alle eigenen Charaktere außer dir), deren Bekanntes erfasst ist, deren Fraktion dort fliegt und die den
-- Punkt nicht kennen. → { { key, c } … } in ezCores Reihenfolge
function FlightNodes.TwinksMissing(id)
    id = ns.Num(id)
    local CD = ClientData()
    local node = id and CD and CD.TaxiNode(id)
    if not node then return {} end
    local out = {}
    for _, e in ipairs(Core.CharacterList()) do
        local rec = not e.isMe and Record(e.key)
        if SeenOn(rec, node.continent) and not rec.nodes[id] then
            local faction = FactionOf(e.key, rec)
            local fits = (faction == "Alliance" and node.alliance) or (faction == "Horde" and node.horde)
            if fits then out[#out + 1] = { key = e.key, c = e.c } end
        end
    end
    return out
end

-- Twinks mit erfasstem Bekannten auf dem Kontinent bzw. ohne → zwei Listen { { key, c, rec } … }
local function Twinks(continent)
    local seen, unseen = {}, {}
    for _, e in ipairs(Core.CharacterList()) do
        if not e.isMe then
            local rec = Record(e.key)
            if SeenOn(rec, continent) then
                seen[#seen + 1] = { key = e.key, c = e.c, rec = rec }
            else
                unseen[#unseen + 1] = { key = e.key, c = e.c }
            end
        end
    end
    return seen, unseen
end
FlightNodes.Twinks = Twinks

---------------------------------------------------------------------------
-- Kartenmenü
---------------------------------------------------------------------------

local function SourceTip()
    local CD = ClientData()
    return L.TAXI_SOURCE:format(CD and CD.SourceText and CD.SourceText("taxi") or "?")
end

local function AddEntries(menu, list)
    local MB, Menu = ns.MapButton, Core.Menu
    local entries = {}
    for _, id in ipairs(list) do entries[#entries + 1] = { id = id, label = FlightNodes.Label(id) } end
    table.sort(entries, function(a, b) return a.label < b.label end)
    for _, e in ipairs(entries) do
        local id = e.id
        if FlightNodes.Place(id) then
            MB.Tip(Menu.Button(menu, e.label, function() FlightNodes.Go(id) end), e.label,
                L.TAXI_ENTRY_TIP:format(SourceTip()))
        else
            MB.Tip(Menu.Title(menu, e.label), e.label, L.TAXI_ENTRY_NOPLACE_TIP:format(SourceTip()))
        end
    end
end

-- Tooltip eines Twinks im Untermenü: „Stand: zuletzt erfasst vor 3 Tagen …“ (Core.Ago liefert „vor …“ bzw. „… ago“
-- selbst); „kennt alle“ (all) ohne den Satz zum Klick – die Zeile hat keine Punkte zum Anklicken.
function FlightNodes.TwinkTip(rec, all)
    local when = type(rec) == "table" and rec.at and Core.Ago(rec.at) or "?"
    return (all and L.MENU_TAXI_TWINK_ALL_TIP or L.MENU_TAXI_TWINK_TIP):format(when)
end

-- Untermenü „Flugpunkte, die dir fehlen“ für den Kontinent der gezeigten Karte. → der Eintrag oder nil (Schalter aus,
-- keine Client-Tabelle, Karte ohne Kontinent oder ohne Flugpunkte in der Tabelle)
function FlightNodes.AddMenu(root, mapID)
    if not ns.Enabled("flightMissing") then return nil end
    if not (ClientData() and RouteAPI()) then return nil end
    -- Was die Weltkarte gerade zeigt, frisch lesen (der Kontinent darüber nennt alle Punkte des Kontinents)
    FlightNodes.LearnFromMap(mapID)
    local continentMap = Core.Map.Parent(mapID, "Continent")
    if continentMap and continentMap ~= ns.Num(mapID) then FlightNodes.LearnFromMap(continentMap) end
    local continent = FlightNodes.ContinentOf(mapID)
    if not continent or #Core.Route.FlightNodes(continent) == 0 then return nil end
    local MB, Menu = ns.MapButton, Core.Menu
    local mine, why = FlightNodes.Missing(MyKey(), continent)
    local label = mine and #mine > 0 and L.MENU_TAXI_COUNT:format(#mine) or L.MENU_TAXI
    local menu = MB.Tip(Menu.Button(root, label), label, L.MENU_TAXI_TIP:format(SourceTip()))
    if why == "unseen" then
        MB.Tip(Menu.Title(menu, L.MENU_TAXI_UNSEEN), L.MENU_TAXI_UNSEEN, L.MENU_TAXI_UNSEEN_TIP)
    elseif mine and #mine == 0 then
        local line = L.MENU_TAXI_ALL:format(FlightNodes.Total(MyKey(), continent))
        MB.Tip(Menu.Title(menu, line), line, L.MENU_TAXI_ALL_TIP)
    elseif mine then
        AddEntries(menu, mine)
    end
    -- Twinks: je erfasstem Twink ein Untermenü mit seinen fehlenden Punkten, darunter, wer noch nicht erfasst ist
    local seen, unseen = Twinks(continent)
    if #seen > 0 or #unseen > 0 then
        Menu.Divider(menu)
        MB.Tip(Menu.Title(menu, L.MENU_TAXI_TWINKS), L.MENU_TAXI_TWINKS, L.MENU_TAXI_TWINKS_TIP)
    end
    for _, t in ipairs(seen) do
        local name = Core.CharName(t.c, t.key, nil, true)
        local list = FlightNodes.Missing(t.key, continent) or {}
        if #list == 0 then
            local line = L.MENU_TAXI_TWINK_ALL:format(name)
            MB.Tip(Menu.Title(menu, line), line, FlightNodes.TwinkTip(t.rec, true))
        else
            local line = L.MENU_TAXI_TWINK:format(name, #list)
            local sub = MB.Tip(Menu.Button(menu, line), line, FlightNodes.TwinkTip(t.rec))
            AddEntries(sub, list)
        end
    end
    if #unseen > 0 then
        local parts = {}
        for _, t in ipairs(unseen) do parts[#parts + 1] = Core.CharName(t.c, t.key, nil, true) end
        local line = L.MENU_TAXI_TWINKS_UNSEEN:format(#unseen)
        MB.Tip(Menu.Title(menu, line), line, L.MENU_TAXI_TWINKS_UNSEEN_TIP:format(table.concat(parts, ", ")))
    end
    return menu
end

---------------------------------------------------------------------------
-- Tooltip von Blizzards Flugpunkten auf der Weltkarte (FlightPointPinMixin, Blizzard_SharedMapDataProviders)
---------------------------------------------------------------------------

-- Zeilen für den Flugpunkt id: „Noch nicht entdeckt von: A, B“ und grau die Quelle. → { { text, grau } … }
function FlightNodes.PinLines(id)
    if not ns.Enabled("flightMissing") then return {} end
    local twinks = FlightNodes.TwinksMissing(id)
    if #twinks == 0 then return {} end
    local parts = {}
    for i, t in ipairs(twinks) do
        if i > FlightNodes.TWINKS_IN_TIP then break end
        parts[#parts + 1] = Core.CharName(t.c, t.key, nil, true)
    end
    local who = table.concat(parts, ", ")
    -- „A, B und 3 weitere“ (gemeinsamer Wortlaut aus ezCore)
    local rest = #twinks - FlightNodes.TWINKS_IN_TIP
    if rest > 0 then who = (who ~= "" and (who .. " ") or "") .. Core.More(rest, true) end
    return { { text = L.TAXI_PIN_TWINKS:format(who) },
        { text = L.TAXI_PIN_SOURCE, grey = true } }
end

local function PinNodeID(pin)
    if type(pin) ~= "table" then return nil end
    for _, field in ipairs({ "poiInfo", "taxiNodeData" }) do
        local info = pin[field]
        if not ns.IsSecret(info) and type(info) == "table" and not ns.IsSecret(info.nodeID) then
            local id = ns.Num(info.nodeID)
            if id then return id end
        end
    end
    return nil
end

function FlightNodes.OnPinEnter(pin)
    local id = PinNodeID(pin)
    if not id or not GameTooltip then return false end
    if GameTooltip.GetOwner and GameTooltip:GetOwner() ~= pin then return false end
    local lines = FlightNodes.PinLines(id)
    if #lines == 0 then return false end
    for _, line in ipairs(lines) do
        if line.grey then
            Core.TipLine(GameTooltip, line.text, "hint", true)
        else
            Core.TipLine(GameTooltip, line.text, "normal", true)
        end
    end
    GameTooltip:Show()
    return true
end

local hooked = false
function FlightNodes.HookPins()
    if hooked then return true end
    local mixin = rawget(_G, "FlightPointPinMixin")
    if type(mixin) ~= "table" or type(mixin.OnMouseEnter) ~= "function" then return false end
    hooksecurefunc(mixin, "OnMouseEnter", function(pin) ns.Try("FlightPinTooltip", FlightNodes.OnPinEnter, pin) end)
    hooked = true
    return true
end

---------------------------------------------------------------------------
-- Anmelden
---------------------------------------------------------------------------

ns.Tree.Add("travel", { key = "flightMissing" }, "flightTimes")

ns.On("TAXIMAP_OPENED", function() ns.Try("FlightNodes", FlightNodes.LearnFromTaxiMap) end)
-- Blizzards Weltkarte zeichnet ihre Flugpunkte bei diesem Ereignis neu (neuer Flugpunkt entdeckt)
ns.On("TAXI_NODE_STATUS_CHANGED", function() ns.Try("FlightNodes", FlightNodes.Scan) end)

ns.OnReady(function()
    ns.Try("FlightNodes", FlightNodes.Scan)
    if not FlightNodes.HookPins() then
        for _, addon in ipairs({ "Blizzard_SharedMapDataProviders", "Blizzard_WorldMap" }) do
            ns.WhenAddOnLoaded(addon, function() ns.Try("FlightNodes", FlightNodes.HookPins) end)
        end
    end
end)

Core.Listen("CHAR_FORGOTTEN", function(key)
    if type(key) == "string" then Store()[key] = nil end
end, "ezMap")

-- /ezmap status: wie viele Flugpunkte du auf deinem Kontinent kennst und für wie viele Charaktere es erfasst ist
ns.AddStatusLine(function()
    if not (ClientData() and RouteAPI()) then return nil end
    if not ns.Enabled("flightMissing") then return L.STATUS_TAXI_OFF end
    local count = 0
    for key in pairs(Store()) do
        local rec = Record(key)
        if rec and rec.at then count = count + 1 end
    end
    local api = rawget(_G, "C_Map")
    local here = type(api) == "table" and Core.Call(api.GetBestMapForUnit, "player") or nil
    local continent = here and FlightNodes.ContinentOf(here)
    local mine = continent and FlightNodes.Missing(MyKey(), continent)
    if mine then
        local total = FlightNodes.Total(MyKey(), continent)
        return L.STATUS_TAXI:format(total - #mine, total, count)
    end
    return L.STATUS_TAXI_UNSEEN:format(count)
end)
