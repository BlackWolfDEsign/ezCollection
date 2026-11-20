local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Bibliotheksbücher als Ziele im Kartenmenü (MAP-07; Welle 11).

    Untermenü „Bibliotheksbücher“ für die gezeigte Zone bzw. den Dungeon (nicht auf Welt- und Kontinentkarten): die
    Bücher, die dieser Charakter noch nicht abgegeben und nicht eingesammelt hat (Taschen, Bank, Post; Status aus
    ezCore.Collections.Books), mit ihrem Fundort in diesem Gebiet. Klick setzt Blizzards Markierung (ns.Way.Set);
    erlaubt das Spiel auf der Karte keine (Instanz, ns.Way.CanSet), steht das Buch als Zeile ohne Klick da.
    Reihenfolge der Quellen (Leitlinie 11; ezCore ordnet „bei dir“ vor „laut Questie“, Core.Sources.ORDER):
      1. selbst gesehen: wo du das Buch aufgehoben hast (Gebiet „Buch-Fundort“ der Entdecker-Datenbank,
         Core.Books.Where) – „bei dir“, mit der Zahl
      2. die Herkunft laut ezCore (Core.Books.From über Core.Sources.WhereFrom: eigene Quellen, sonst QuestieDB zur
         Laufzeit; kennt die erste Quelle hier keinen Ort, auch die übrigen) – „laut Questie“; ein Eintrag ohne Ort im
         Gebiet steht als Zeile ohne Klick da (selbst Gesehenes in einer Instanz ebenso)
      3. ohne Quelle eine erklärende Zeile (nie stumm)
    Fundorte sind Entdecker-Wissen: nur mit dem Schalter „Bibliotheksbücher im Kartenmenü“ (bookTargets, ab Werk aus);
    ist er an, fragt ezMap ezCore mit opts.explorer = true.
    Rücksicht (Leitlinie 9): zeichnet ein anderes Addon die Bücher als Punkte auf die Karte (Core.WhoHandles("bookPins"):
    HandyNotes – Forever Books), zeichnet ezMap ohnehin keine – die Liste bleibt als Ziel, darunter steht der Name des
    Addons (wie bei den Dungeoneingängen). Aus fremden Addons wird nichts kopiert; nichts wird gespeichert.
]]
local Books = {}
ns.Books = Books

-- Kartentypen mit eigenem Gebiet: Zone (3), Dungeon (4) und darunter; Welt und Kontinent haben keins.
Books.MIN_MAP_TYPE = 3
-- Listen der Herkunft (Core.Sources.WhereFrom) in dieser Reihenfolge; der Text nennt die Art.
Books.LISTS = { "objects", "containers", "drops", "vendors", "quests" }

local function Explorer() return { explorer = true } end

-- „bei dir“ – ezCores Wort für die eigene Datenbank (Core.Sources.Label, eine Quelle für alle Module).
function Books.OwnLabel()
    local S = Core.Sources
    local label = S and S.Label and S.Label({ source = "own", sourceKey = "own" })
    return label or L.BOOK_SOURCE_UNNAMED
end

-- Gebiet, unter dem ezCore Orte führt (Zone bzw. Dungeon; eine Kleinkarte zählt zu ihrer Zone) → uiMapID oder nil.
function Books.Zone(mapID)
    mapID = ns.Num(mapID)
    local info = mapID and Core.Map.Info(mapID)
    local mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    if not (mapType and mapType >= Books.MIN_MAP_TYPE) then return nil end
    local Keys = Core.DB and Core.DB.Keys
    local zone = Keys and Keys.MapOf and Keys.MapOf(mapID)
    return ns.Num(zone) or mapID
end

local function Collections()
    local C = Core.Collections
    if type(C) == "table" and type(C.Books) == "function" then return C end
    return nil
end

-- Noch fehlende Bücher dieses Charakters → Liste (nicht abgegeben, nicht eingesammelt), Zahl der eingesammelten
-- (Collections.Book zählt Taschen, Bank und Post).
function Books.Missing()
    local C = Collections()
    local list, inBag = {}, 0
    if not C then return list, inBag end
    for _, b in ipairs(C.Books()) do
        if not b.done then
            if (ns.Num(b.have) or 0) > 0 then inBag = inBag + 1 else list[#list + 1] = b end
        end
    end
    return list, inBag
end

local function Coord(v)
    v = ns.Num(v)
    if v and v >= 0 and v <= 1 then return v end
    return nil
end

-- Liegt die Karte in diesem Gebiet (selbst oder als Kleinkarte darin)?
local function InZone(map, zone)
    local Keys = Core.DB and Core.DB.Keys
    return map ~= nil and (map == zone or (Keys and Keys.MapOf and Keys.MapOf(map) == zone) or false)
end

-- 1. selbst aufgehoben (der häufigste Ort zuerst, Places.Of sortiert nach Zahl) → Ort mit x/y, sonst nil und ein
-- Eintrag nur mit dem Gebiet (in Instanzen speichert ezCore keine Lage, Discovery.Place).
local function OwnSpot(item, zone)
    local B = Core.Books
    if not (ns.Discovery.Usable() and type(B) == "table" and type(B.Where) == "function") then return nil end
    local area
    for _, p in ipairs(B.Where(item, Explorer()) or {}) do
        local map = ns.Num(p.map)
        if InZone(map, zone) then
            local x, y = Coord(p.x), Coord(p.y)
            local spot = { map = map, x = x, y = y, own = true, cnt = ns.Num(p.cnt) or 1, label = Books.OwnLabel() }
            if x and y then return spot end
            area = area or spot
        end
    end
    return nil, area
end

-- Fundort in einer Antwort der Herkunft (Core.Sources.WhereFrom) → Ort mit x/y, sonst nil und ein Eintrag nur mit
-- dem Gebiet.
local function AnswerSpot(answer, label, zone)
    local area
    for _, list in ipairs(Books.LISTS) do
        for _, e in ipairs(type(answer[list]) == "table" and answer[list] or {}) do
            local map = ns.Num(e.map)
            if InZone(map, zone) then
                local what = type(e.name) == "string" and e.name ~= "" and L["BOOK_FROM_" .. list]:format(e.name) or nil
                local x, y = Coord(e.x), Coord(e.y)
                local spot = { map = map, x = x, y = y, own = answer.sourceKey == "own", cnt = ns.Num(e.cnt),
                    label = label, what = what }
                if x and y then return spot end
                area = area or spot
            end
        end
    end
    return nil, area
end

-- 2. Herkunft laut ezCore (Core.Books.From prüft Buch und Entdecker-Wissen und gibt die erste Quelle). Kennt sie hier
-- keinen Ort, werden auch die übrigen Quellen gefragt (opts.all): sonst verdeckte ein eigener Eintrag aus einer
-- anderen Zone die Fundorte laut Questie (Gegenprüfung Welle 11).
local function FromSpot(item, zone)
    local B = Core.Books
    if type(B) ~= "table" or type(B.From) ~= "function" then return nil end
    local answer, info = B.From(item, Explorer())
    if type(answer) ~= "table" then return nil end
    local spot, area = AnswerSpot(answer, type(info) == "table" and info.label or nil, zone)
    if spot then return spot end
    local S = Core.Sources
    if not (S and S.WhereFrom) then return nil, area end
    for _, other in ipairs(S.WhereFrom(item, { explorer = true, all = true }) or {}) do
        if type(other) == "table" and other.sourceKey ~= answer.sourceKey then
            local label = S.Label and S.Label(other) or nil
            local s, a = AnswerSpot(other, label, zone)
            if s then return s end
            area = area or a
        end
    end
    return nil, area
end

-- Fundort eines Buchs in diesem Gebiet → { map, x, y, own, cnt, label, what } oder nil.
-- Ohne x und y: nur das Gebiet ist bekannt (keine Markierung möglich). Ein Ort mit x/y geht vor; unter den Einträgen
-- nur mit dem Gebiet geht „bei dir“ vor.
function Books.Spot(book, zone)
    local item = book and ns.Num(book.item)
    if not (item and zone) then return nil end
    local spot, ownArea = OwnSpot(item, zone)
    if spot then return spot end
    local area
    spot, area = FromSpot(item, zone)
    return spot or ownArea or area
end

-- Fehlende Bücher mit Fundort im Gebiet → Liste { book, spot } nach Name, Zahl der übrigen fehlenden, Zahl in der
-- Tasche, Zahl aller fehlenden.
function Books.InZone(mapID)
    local zone = Books.Zone(mapID)
    local missing, inBag = Books.Missing()
    local found, rest = {}, 0
    for _, b in ipairs(missing) do
        local spot = zone and Books.Spot(b, zone)
        if spot then found[#found + 1] = { book = b, spot = spot } else rest = rest + 1 end
    end
    table.sort(found, function(a, b) return (a.book.name or "") < (b.book.name or "") end)
    return found, rest, inBag, #missing
end

-- Erklärzeile zu einem Eintrag: woher der Fundort stammt.
function Books.SourceText(spot)
    if spot.own and spot.cnt and spot.what == nil then return L.BOOK_SOURCE_OWN:format(spot.cnt) end
    local label = spot.label or L.BOOK_SOURCE_UNNAMED
    if spot.what then return L.BOOK_SOURCE_WHAT:format(label, spot.what) end
    return L.BOOK_SOURCE:format(label)
end

local function Name(book) return book.name or ("#" .. tostring(book.item)) end

-- Untermenü im Kartenmenü. → der Eintrag oder nil (Schalter aus, Welt- oder Kontinentkarte, ezCore ohne Bücher)
function Books.AddMenu(root, mapID)
    if not ns.Enabled("bookTargets") then return nil end
    local C = Collections()
    if not (C and Books.Zone(mapID)) then return nil end
    local MB, Menu = ns.MapButton, Core.Menu
    local found, rest, inBag, missing = Books.InZone(mapID)
    local label = #found > 0 and L.MENU_BOOKS_COUNT:format(#found) or L.MENU_BOOKS
    local menu = MB.Tip(Menu.Button(root, label), label, L.MENU_BOOKS_TIP)
    if C.BookProgress then
        local done, total = C.BookProgress()
        local line = L.MENU_BOOKS_PROGRESS:format(ns.Num(done) or 0, ns.Num(total) or 0)
        MB.Tip(Menu.Title(menu, line), line, L.MENU_BOOKS_PROGRESS_TIP)
    end
    if missing == 0 and inBag == 0 then
        MB.Tip(Menu.Title(menu, L.MENU_BOOKS_ALLDONE), L.MENU_BOOKS_ALLDONE, L.MENU_BOOKS_ALLDONE_TIP)
    elseif missing == 0 then
        -- nichts mehr zu suchen: nur die Zeile der eingesammelten Bücher (unten), kein „kein Fundort bekannt“
    elseif #found == 0 then
        local S = Core.Sources
        local noQuestie = not (S and S.Status) or S.Status("QuestieDB") ~= "ok"
        MB.Tip(Menu.Title(menu, L.MENU_BOOKS_NONE), L.MENU_BOOKS_NONE,
            L.MENU_BOOKS_NONE_TIP .. (noQuestie and (" " .. L.MENU_BOOKS_NONE_NOQUESTIE) or ""))
    else
        for _, f in ipairs(found) do
            local b, spot = f.book, f.spot
            if spot.x and spot.y and ns.Way.CanSet(spot.map) then
                local text = L.MENU_BOOK_ENTRY:format(Name(b), spot.label or L.BOOK_SOURCE_UNNAMED)
                MB.Tip(Menu.Button(menu, text, function() Books.Go(b, spot) end), Name(b),
                    L.MENU_BOOK_ENTRY_TIP:format(Books.SourceText(spot)))
            elseif spot.x and spot.y then
                -- Ort bekannt, aber das Spiel erlaubt auf dieser Karte (Instanz) keine eigene Markierung
                local text = L.MENU_BOOK_NOPIN:format(Name(b), spot.label or L.BOOK_SOURCE_UNNAMED)
                MB.Tip(Menu.Title(menu, text), Name(b), L.MENU_BOOK_NOPIN_TIP:format(Books.SourceText(spot)))
            else
                local text = L.MENU_BOOK_AREA:format(Name(b))
                MB.Tip(Menu.Title(menu, text), Name(b), L.MENU_BOOK_AREA_TIP:format(Books.SourceText(spot)))
            end
        end
    end
    if rest > 0 and #found > 0 then
        local line = L.MENU_BOOKS_REST:format(rest)
        MB.Tip(Menu.Title(menu, line), line, L.MENU_BOOKS_REST_TIP)
    end
    if inBag > 0 then
        local line = L.MENU_BOOKS_BAG:format(inBag)
        MB.Tip(Menu.Title(menu, line), line, L.MENU_BOOKS_BAG_TIP)
    end
    local other = ns.OtherFor("bookPins")
    if other then
        Menu.Divider(menu)
        MB.OtherTitle(menu, L.MENU_BOOKS_OTHER:format(other), L.MENU_BOOKS_OTHER_TIP)
    end
    return menu
end

-- Blizzards Markierung auf den Fundort (Titel: der Name des Buchs).
function Books.Go(book, spot)
    return ns.Way.Set(spot.map, spot.x, spot.y, Name(book), true)
end

---------------------------------------------------------------------------
-- Fundorte fehlender Bücher als Punkte auf der Weltkarte (SAM-22; Entdecker-Wissen, ab Werk aus)
---------------------------------------------------------------------------
--[[
    Dieselben Fundorte wie im Untermenü (Books.InZone: zuerst selbst aufgehoben, sonst laut Questie), nur die mit Ort,
    als Punkte über ezCores Punkteschicht (Anbieter „ezMap.books“). Schalter bookPins (Gruppe „Schätze und
    Entdecker-Wissen“), ab Werk aus. Zeichnet ein anderes Addon die Bücher schon (Core.WhoHandles("bookPins"):
    HandyNotes – Forever Books), zeichnet ezMap nicht.
]]
Books.PROVIDER = "ezMap.books"
Books.PIN_SIZE = 16
Books.ICON = "Interface\\Icons\\INV_Misc_Book_09"

function Books.PinsWanted()
    return ns.Enabled("bookPins") and not ns.OtherFor("bookPins") and Collections() ~= nil
end

function Books.Points(mapID)
    if not Books.Zone(mapID) then return {} end
    local out = {}
    for _, f in ipairs((Books.InZone(mapID))) do
        local spot = f.spot
        if spot and spot.x and spot.y and spot.map then
            out[#out + 1] = { x = spot.x, y = spot.y, map = spot.map, size = Books.PIN_SIZE,
                texture = (f.book.item and Core.ItemIcon(f.book.item)) or Books.ICON, book = f.book, spot = spot }
        end
    end
    return out
end

function Books.PinTooltip(tip, point)
    if type(point) ~= "table" or not point.book then return end
    Core.TipTitle(tip, Name(point.book))
    Core.TipLine(tip, L.BOOKPIN_KIND, "hint")
    Core.TipLine(tip, Books.SourceText(point.spot), "hint", true)
    Core.TipClick(tip, L.BOOKPIN_HINT)
end

function Books.PinClick(point, button)
    if type(point) ~= "table" or not point.book or button == "RightButton" then return false end
    return Books.Go(point.book, point.spot)
end

function Books.InitPins()
    local P = Core.MapPins
    if not (type(P) == "table" and type(P.AddProvider) == "function") then return false end
    P.AddProvider(Books.PROVIDER, {
        owner = "ezMap",
        order = 45,
        punkte = Books.Points,
        sichtbar = function() return Books.PinsWanted() end,
        tooltip = Books.PinTooltip,
        klick = Books.PinClick,
    })
    return true
end

ns.Tree.Add("explorer", { key = "bookPins" }, "bookTargets")
ns.OnReady(function() ns.Try("BookPins", Books.InitPins) end)
ns.OnSettingChanged(function(key)
    local P = Core.MapPins
    if key == "bookPins" and type(P) == "table" and P.Refresh then P.Refresh() end
end)

-- Schalter im Kartenmenü (dieselbe Erklärung wie auf der Einstellungsseite).
function Books.AddMenuToggle(root)
    if not Collections() then return false end
    ns.MapButton.Toggle(root, L.MENU_BOOK_TARGETS, "bookTargets")
    return true
end

-- /ezmap status: Schalter, Fortschritt, wer Bücher-Punkte zeichnet
ns.AddStatusLine(function()
    local C = Collections()
    if not C then return nil end
    local other = ns.OtherFor("bookPins")
    local tail = other and (" " .. L.STATUS_BOOKS_OTHER:format(other)) or ""
    if not ns.Enabled("bookTargets") then return L.STATUS_BOOKS_OFF .. tail end
    local done, total = 0, 0
    if C.BookProgress then done, total = C.BookProgress() end
    local own = 0
    local B = Core.Books
    if ns.Discovery.Usable() and type(B) == "table" and type(B.Where) == "function" then
        for _, b in ipairs(C.Books()) do
            if #(B.Where(b.item, Explorer()) or {}) > 0 then own = own + 1 end
        end
    end
    return L.STATUS_BOOKS_ON:format(ns.Num(done) or 0, ns.Num(total) or 0, own) .. tail
end)
