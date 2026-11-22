local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Eine Einkaufsliste suchen: jeder Eintrag nacheinander als Blizzard-Suche (C_AuctionHouse.SendBrowseQuery,
    im Takt des Servers), die Treffer jedes Eintrags werden gesammelt. Am Ende zeigt eine Suche nach allen
    gefundenen Gegenständen (C_AuctionHouse.SearchForItemKeys) die Treffer zusammen in Blizzards Ergebnisliste.
    Sucht der Spieler selbst (Suchfeld, Favoriten), bricht die Listensuche ab.
    In der Ansicht eines fremden Addons (Core.lua, ns.ForeignView) sucht ezAuction nicht: eine laufende Listensuche
    bricht ab, eine neue beginnt dort nicht, und was noch auf den Takt des Servers wartet (die Sammelsuche am Ende,
    eine Suche über Search.Item), verfällt – sonst holte ezAuction den Spieler aus dem fremden Reiter zurück.
    Ein freier Begriff kann mehr Treffer haben, als der Server im ersten Paket schickt: dann holt die Listensuche
    die weiteren Pakete nach (C_AuctionHouse.RequestMoreBrowseResults, Ereignis AUCTION_HOUSE_BROWSE_RESULTS_ADDED),
    höchstens Search.MAX_PAGES je Eintrag (Vollprüfung V-156).

    Fertigstellungsplan Welle 12:
      - Filter je Eintrag (AH-09): Stufe von–bis, Qualität, Kategorie, „genau“ gehen als EIGENE Abfrage-Tabelle an
        C_AuctionHouse.SendBrowseQuery (Search.QueryFor) – nie in Blizzards Filterstand, nie SetSelectedCategory.
      - Eine einzelne Zeile einer Liste suchen (AH-10): Search.Start(liste, index).
      - Suchverlauf (AH-08): Pfeil-Knopf rechts neben dem Suchfeld mit den letzten Search.RECENT_MAX Suchen;
        mitgeschrieben über den Hook auf AuctionHouseFrame:SendBrowseQuery (Text, Stufen und Filter aus dessen
        Argumenten, die Kategorie nur über Blizzards Lesefunktion CategoriesList:GetCategoryFilterData). Wiederholt wird mit eigener Abfrage;
        gesetzt wird nur der Text von Blizzards Suchfeld.
      - Filterzeile über der Ergebnisliste (Search.shown): Blizzards Filterknopf zeigt die eigenen Filter nicht, darum
        nennt eine Zeile, was gerade gilt („Verlauf: Erz, Stufe 20–30, selten“), mit „×“ zum Zurücksetzen.
      - Sortieren per Spaltenkopf (Search.Resort): Blizzard wiederholt dabei seine eigene letzte Suche
        (AuctionHouseFrameMixin:SetSortOrder, activeSearches) und nicht ezAuctions Abfrage. Ein Hook auf
        SetBrowseSortOrder schickt danach ezAuctions Abfrage noch einmal, mit Blizzards neuer Sortierung (Search.Sorts,
        nur gelesen) – sonst zeigte die Liste die alte Suche des Spielers, Suchfeld und Filterzeile aber die eigene.

    Fertigstellungsplan Welle 13 (AH-37):
      - Jeder Eintrag einer Listensuche und ihre Sammelsuche sind Aufträge in ezCores Prices.Queue (Rang „modul“,
        Schlüssel „ezAuction.list“ bzw. „ezAuction.listshow“; ns.Enqueue in Core.lua): nie zwei Abfragen zugleich, der
        nächste Eintrag kommt vor wartenden Erfassungen. Ohne Warteschlange der eigene Takt wie bisher.
      - Eine neue Suche des Spielers bricht die Listensuche ab (Hook auf AuctionHouseFrame:SendBrowseQuery – nur er
        unterscheidet sie vom Sortieren: Blizzards SendBrowseQuery kommt bei ezCore als SendBrowseQueryInternal an, wie
        ein Klick auf einen Spaltenkopf). Bricht ezCore einen Eintrag wegen Sortieren oder eines Klicks auf eine Zeile
        ab, kommt er nach der Wartezeit noch einmal (Search.UserCut).
      - Klicks in ezAuctions Oberfläche (Suchverlauf, „ד, Search.Item) melden ezCore eine Suche des Spielers
        (ns.UserQuery) und senden gleich.
      - Hinweiszeile während einer Erfassung, danach die vorige Ansicht (Abschnitt „Erfassung in Blizzards
        Ergebnisliste“ unten, Search.Capture).
]]

local Search = {}
ns.Search = Search

Search.results = setmetatable({}, { __mode = "k" })   -- [Liste] = { found = n, total = n, missing = { Text … } }
local TIMEOUT = 15
Search.MAX_PAGES = 10          -- weitere Pakete je Eintrag (ein Paket sind bis zu 50 Treffer)

local function Changed() ns.Fire("SEARCH_CHANGED") end
local function Lists() return ns.Lists end

-- Zeigt das Auktionsfenster gerade die Ansicht eines fremden Addons? Dann sendet ezAuction keine Suche und
-- schaltet Blizzards Ansicht nicht um.
local function Foreign() return ns.ModeName() == "other" end

-- Die Filter der Einträge gelten immer (Einstellungs-Prüfung vom 19.11.2026, Nr. 11: der frühere Schalter listFilters
-- setzte selbst gesetzte Filter still außer Kraft; wer keinen Filter will, setzt keinen).

-- Sortierung, die Blizzards Spaltenköpfe gerade zeigen (AuctionHouseFrame:GetSortsForContext, nur gelesen, als
-- Kopie); ohne sie ezAuctions feste Sortierung ns.Sorts().
function Search.Sorts()
    local frame = AuctionHouseFrame
    if frame and type(frame.GetSortsForContext) == "function" and type(frame.GetBrowseSearchContext) == "function" then
        local ok, sorts = pcall(function() return frame:GetSortsForContext(frame:GetBrowseSearchContext()) end)
        local out = {}
        for _, sort in ipairs(ok and type(sorts) == "table" and sorts or {}) do
            if type(sort) == "table" and sort.sortOrder ~= nil then
                out[#out + 1] = { sortOrder = sort.sortOrder, reverseSort = sort.reverseSort == true }
            end
        end
        if #out > 0 then return out end
    end
    return ns.Sorts()
end

-- Prüft ezAuction bei diesem Eintrag selbst etwas, das der Server vielleicht nicht anwendet (die Mindest-Qualität
-- eines freien Begriffs)? Dann zeigt Blizzards Liste nur die geprüften Treffer (Search.Finish), auch bei einer Zeile.
function Search.OwnFilter(entry)
    return type(entry) == "table" and entry.quality ~= nil and entry.itemID == nil
end

-- Passt ein Treffer zum Eintrag? itemID genau; „genau“ nach Name; sonst alles, was Blizzards Suche liefert. Eine
-- Mindest-Qualität prüft ezAuction zusätzlich selbst (falls der Server die Qualitäts-Filter nicht anwendet).
function Search.Matches(entry, itemKey)
    if type(itemKey) ~= "table" then return false end
    if entry.itemID then return itemKey.itemID == entry.itemID end
    local info
    local function Info()
        if info == nil then
            info = C_AuctionHouse.GetItemKeyInfo and Core.Call(C_AuctionHouse.GetItemKeyInfo, itemKey) or false
        end
        return type(info) == "table" and info or nil
    end
    if entry.quality then
        local quality = Info() and Core.Num(Info().quality)
        if quality and quality < entry.quality then return false end
    end
    if entry.exact and entry.text then
        local name = Info() and Info().itemName
        if type(name) == "string" then return name:lower() == entry.text:lower() end
    end
    return true
end

function Search.IsRunning(list)
    local run = Search.running
    return run ~= nil and (list == nil or run.list == list)
end

-- Fortschritt für die Anzeige: index, total (nil, wenn diese Liste nicht läuft).
function Search.Progress(list)
    local run = Search.running
    if not run or (list and run.list ~= list) then return nil end
    return math.max(1, run.index), run.total
end

-- Blizzards Filter-Kennungen (Enum.AuctionHouseFilter) je Qualität, von „schlecht“ bis „Artefakt“.
Search.QUALITY_FLAGS = { [0] = "PoorQuality", "CommonQuality", "UncommonQuality", "RareQuality", "EpicQuality",
    "LegendaryQuality", "ArtifactQuality" }

-- Filter-Kennungen für einen Eintrag: „genau“ (Begriff in Anführungszeichen oder Gegenstand), ab der Qualität alle
-- höheren, dazu der feste Filter der Kategorie. Kennungen, die der Client nicht kennt, fallen weg.
function Search.FilterFlags(entry)
    local filters = {}
    local enum = Enum and Enum.AuctionHouseFilter
    if type(enum) ~= "table" then return filters end
    if enum.ExactMatch and (entry.exact or entry.itemID) then filters[#filters + 1] = enum.ExactMatch end
    if entry.quality then
        for quality = entry.quality, #Search.QUALITY_FLAGS do
            local flag = enum[Search.QUALITY_FLAGS[quality]]
            if flag then filters[#filters + 1] = flag end
        end
    end
    local implicit = entry.category and entry.category.implicit
    if implicit then
        local known = false
        for _, flag in ipairs(filters) do if flag == implicit then known = true end end
        if not known then filters[#filters + 1] = implicit end
    end
    return filters
end

-- Blizzards Filterknopf, nur gelesen (Shared/Blizzard_AuctionHouseSearchBar.lua, Zweig forever: CalculateFiltersArray,
-- GetLevelRange): die Filter-Kennungen und Stufen, die der Spieler dort gewählt hat. Seit dem zweiten Spieltest vom
-- 21.11.2026 sucht eine Einkaufsliste mit Blizzards Filter (Entscheidung „Wie eine Kategorie (Empfohlen)“ auf „unsere
-- einkaufliste sollte genauso wie die anderen menüpunkte über suche und filter funktionieren“). → flags, min, max
function Search.BlizzardFilters()
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    local button = bar and bar.FilterButton
    if type(button) ~= "table" then return {}, nil, nil end
    local flags = button.CalculateFiltersArray and Core.Call(button.CalculateFiltersArray, button)
    local low, high
    if button.GetLevelRange then low, high = Core.Call(button.GetLevelRange, button) end
    low, high = Core.Num(low), Core.Num(high)
    return type(flags) == "table" and flags or {}, (low and low > 0) and low or nil, (high and high > 0) and high or nil
end

-- Filter des Eintrags und Blizzards Filter zusammen: Qualitäten als Schnittmenge, wenn beide welche nennen (sonst die
-- vorhandenen), alle übrigen Kennungen zusammen. → neue Liste
function Search.MergeFilters(own, blizzard)
    local enum = Enum and Enum.AuctionHouseFilter
    local quality = {}
    if type(enum) == "table" then
        for _, name in pairs(Search.QUALITY_FLAGS) do if enum[name] then quality[enum[name]] = true end end
    end
    local function Split(list)
        local q, other, any = {}, {}, false
        for _, flag in ipairs(list or {}) do
            if quality[flag] then q[flag], any = true, true else other[#other + 1] = flag end
        end
        return q, other, any
    end
    local ownQ, ownOther, ownAny = Split(own)
    local bQ, bOther, bAny = Split(blizzard)
    local out, seen = {}, {}
    local function Add(flag) if not seen[flag] then seen[flag] = true out[#out + 1] = flag end end
    for _, flag in ipairs(ownOther) do Add(flag) end
    for _, flag in ipairs(bOther) do Add(flag) end
    for _, flag in ipairs(own or {}) do
        if ownQ[flag] and (not bAny or bQ[flag]) then Add(flag) end
    end
    if not ownAny then
        for _, flag in ipairs(blizzard or {}) do if bQ[flag] then Add(flag) end end
    end
    return out
end

-- Eigene Abfrage-Tabelle für C_AuctionHouse.SendBrowseQuery (nie Blizzards Filtertabelle): Text, Stufen, Filter,
-- Kategorie (als Kopie) und Blizzards Sortierung; dazu Blizzards Filterknopf (Search.BlizzardFilters): Stufen als
-- engster Bereich beider.
function Search.QueryFor(entry, term)
    local flags, low, high = Search.BlizzardFilters()
    local query = { searchString = term, sorts = Search.Sorts(), filters = Search.MergeFilters(Search.FilterFlags(entry), flags) }
    query.minLevel, query.maxLevel = entry.minLevel, entry.maxLevel
    if low and (not query.minLevel or low > query.minLevel) then query.minLevel = low end
    if high and (not query.maxLevel or high < query.maxLevel) then query.maxLevel = high end
    local filters = entry.category and entry.category.filters
    if filters then
        query.itemClassFilters = {}
        for index, f in ipairs(filters) do
            query.itemClassFilters[index] = { classID = f.classID, subClassID = f.subClassID, inventoryType = f.inventoryType }
        end
    end
    return query
end

-- Was die Ergebnisliste gerade aus ezAuction zeigt: { kind = "list" | "recent" | "item", list, entryOf = { [Schlüssel]
-- = Eintrag }, text = Zeile über der Ergebnisliste oder nil, term = Suchtext, query = die gesendete eigene Abfrage
-- bzw. keys = die Gegenstände der Sammelsuche (für Search.Resort) }. nil, sobald der Spieler selbst sucht.
Search.shown = nil

local function Show(shown)
    Search.shown = shown
    -- eine neue Ansicht ersetzt eine noch wartende Sammelsuche bzw. Wiederholung (deren Antwort zeigte das Alte)
    local job = Search.showJob
    if job then
        Search.showJob = nil
        ns.DropJob(job)
    end
    if Search.UpdateBar then Search.UpdateBar() end
end

-- Keine eigene Ansicht mehr (Knopf „Zurücksetzen“, BuyTab.lua): Filterzeile weg, wartende Sammelsuche fallen gelassen.
function Search.ClearShown() Show(nil) end

-- Eintrag der gezeigten Liste, der diesen Treffer gefunden hat (für „über Höchstpreis“, Bestand); sonst nil.
function Search.EntryFor(itemKey)
    local shown = Search.shown
    if not (shown and shown.entryOf and type(itemKey) == "table") then return nil end
    local entry = shown.entryOf[ns.KeyString(itemKey)]
    if entry then return entry, shown.list end
    return nil
end

-- Zeile über der Ergebnisliste für eine Liste: ein Eintrag mit Filtern nennt sie, mehrere nur ihre Zahl.
local function ListBarText(list, entries)
    local filtered, first = 0, nil
    for _, entry in ipairs(entries) do
        if Lists().HasFilters(entry) then
            filtered = filtered + 1
            first = first or entry
        end
    end
    if filtered == 0 then return nil end
    if #entries == 1 then return L.FILTERBAR_LIST:format(list.name, Lists().FilterText(first)) end
    return L.FILTERBAR_LIST_MANY:format(list.name, filtered)
end

-- Eine Liste suchen – alle Einträge, oder mit only (Index) nur diese eine Zeile (AH-10; das Ergebnis „gefunden/
-- gesamt“ an der Liste bleibt dann, wie es war).
function Search.Start(list, only)
    if not (list and C_AuctionHouse and C_AuctionHouse.SendBrowseQuery) then return false end
    if not ns.AuctionHouseShown() or Foreign() then return false end
    if Search.running then Search.Cancel(true) end
    -- hergestellte Gegenstände als ihr fehlendes Material bzw. der Gegenstand selbst (ezCores Core.Lists)
    local entries = Lists().SearchEntries(list, only)
    if #entries == 0 then
        if only == nil then ns.Print(L.LIST_EMPTY:format(list.name)) end
        return false
    end
    ns.ShowBrowseResults()
    Search.running = { list = list, entries = entries, index = 0, total = #entries, keys = {}, seen = {}, found = {},
        single = only ~= nil, entryOf = {}, click = true }
    if only == nil then Search.results[list] = nil end
    Show({ kind = "list", list = list, entryOf = Search.running.entryOf, text = ListBarText(list, entries) })
    Changed()
    Search.Next()
    return true
end

function Search.Next()
    local run = Search.running
    if not run then return end
    run.index = run.index + 1
    local entry = run.entries[run.index]
    if not entry then return Search.Finish() end
    local term = ns.Lists.SearchText(entry)
    if not term then
        run.found[run.index] = 0
        return Search.Next()
    end
    Changed()
    Search.Send(run, run.index, entry, term)
end

-- Einen Eintrag senden – als Auftrag in ezCores Warteschlange (AH-37, Rang „modul“, Schlüssel „ezAuction.list“),
-- ohne sie im eigenen Takt. Die Frist je Paket hält Search.Await; der Auftrag selbst darf alle Pakete abwarten.
function Search.Send(run, index, entry, term)
    -- click: eine Liste sucht nur ein Klick des Spielers („Suchen“, Eingabetaste, Zeile im Editor) – sie wartet die
    -- Haltezeit nach Blizzards eigener Suche nicht ab (ezCore A23; sonst 10 s Pause nach der Eingabetaste). Nach einem
    -- Eingriff des Spielers mitten in der Liste (Sortieren: Search.Resort, Search.UserCut) wartet sie wieder.
    local job = { name = "list", text = L.QUEUE_LIST:format(run.list.name or "?"),
        timeout = TIMEOUT * (Search.MAX_PAGES + 2), click = run.click == true }
    job.start = function()
        if Search.running ~= run or run.index ~= index then
            ns.JobDone(job)
            return
        end
        local query = Search.QueryFor(entry, term)
        run.pages = 0
        run.lastQuery = query
        run.ownQuery = true
        local ok = pcall(C_AuctionHouse.SendBrowseQuery, query)
        run.ownQuery = false
        if not ok then
            run.waiting = false
            run.found[index] = 0
            Search.Next()
            ns.JobDone(job)
            return
        end
        Search.Await(run)
    end
    -- ezCore bricht ab: keine Antwort oder Fehler beim Senden zählt als gescheitert; eine Suche des Spielers prüft
    -- Search.UserCut im nächsten Bild (eine neue Suche hat die Liste dann schon beendet, ein Klick auf einen Spaltenkopf
    -- oder eine Ergebniszeile nicht – dann kommt der Eintrag nach der Wartezeit noch einmal).
    job.cancel = function(_, why)
        if run.job ~= job or Search.running ~= run then return end
        if why == "timeout" or why == "error" then
            if run.waiting then Search.OnResults(true) else Search.Next() end
        elseif why == "user" then
            C_Timer.After(0, function() Search.UserCut(run, job) end)
        elseif why == "closed" then
            Search.Cancel(true)
        end
    end
    run.job = job
    ns.Enqueue(job)
end

-- Die Warteschlange hat den Eintrag wegen einer Suche des Spielers abgebrochen. Läuft die Liste danach noch (es war
-- keine neue Suche, sondern Sortieren oder ein Klick auf eine Zeile), wird der Eintrag neu eingereiht.
function Search.UserCut(run, job)
    if Search.running ~= run or run.job ~= job then return false end
    run.waiting = false
    run.click = false   -- der Spieler hat eingegriffen: ab jetzt mit Haltezeit
    run.index = run.index - 1
    Search.Next()
    return true
end

-- Auf die Antwort des Servers warten; bleibt sie aus, zählt die Anfrage nach TIMEOUT als gescheitert.
-- Jede Anfrage (auch jedes weitere Paket) bekommt ihre eigene Frist.
function Search.Await(run)
    run.waiting = true
    run.token = (run.token or 0) + 1
    local token = run.token
    C_Timer.After(TIMEOUT, function()
        if Search.running == run and run.waiting and run.token == token then Search.OnResults(true) end
    end)
end

-- Hat der Server zu einem freien Begriff noch weitere Treffer? Einträge mit itemID oder genauem Namen brauchen
-- das nicht (ihr Treffer steht im ersten Paket).
function Search.WantsMore(entry, run)
    local api = C_AuctionHouse
    if entry.itemID or entry.exact then return false end
    if not (api.HasFullBrowseResults and api.RequestMoreBrowseResults) then return false end
    if (run.pages or 0) >= Search.MAX_PAGES then return false end
    return Core.Call(api.HasFullBrowseResults) == false
end

-- Ergebnis der laufenden Anfrage (failed: Fehler oder keine Antwort).
function Search.OnResults(failed)
    local run = Search.running
    if not (run and run.waiting) then return end
    run.waiting = false
    local entry = run.entries[run.index]
    -- Scheitert ein weiteres Paket, bleiben die Treffer der bisherigen Pakete.
    local count = run.found[run.index] or 0
    if not failed and entry then
        -- GetBrowseResults liefert alle bisher geladenen Pakete: neu zählen, Schlüssel nur einmal merken.
        count = 0
        local results = Core.Call(C_AuctionHouse.GetBrowseResults) or {}
        for _, result in ipairs(results) do
            if Search.Matches(entry, result.itemKey) then
                count = count + 1
                local key = ns.KeyString(result.itemKey)
                if not run.seen[key] then
                    run.seen[key] = true
                    run.keys[#run.keys + 1] = result.itemKey
                    run.entryOf[key] = entry
                end
            end
        end
    end
    run.found[run.index] = count
    if not failed and entry and Search.WantsMore(entry, run) then
        local index = run.index
        run.pages = (run.pages or 0) + 1
        Search.Await(run)
        ns.WhenThrottleReady(function()
            if Search.running ~= run or run.index ~= index or not run.waiting then return end
            if not pcall(C_AuctionHouse.RequestMoreBrowseResults) then Search.OnResults(true) end
        end)
        return
    end
    -- Erst den nächsten Auftrag einreihen, dann diesen beenden: so folgt der nächste Eintrag gleich, vor wartenden
    -- Erfassungen (Rang „modul“ vor „erfassung“).
    local done = run.job
    Search.Next()
    ns.JobDone(done)
end

function Search.Finish()
    local run = Search.running
    if not run then return end
    Search.running = nil
    local found, missing = 0, {}
    for index, entry in ipairs(run.entries) do
        if (run.found[index] or 0) > 0 then
            found = found + 1
        else
            missing[#missing + 1] = ns.Lists.EntryLabel(entry)
        end
    end
    if not run.single then Search.results[run.list] = { found = found, total = run.total, missing = missing } end
    -- Mehrere Begriffe – oder ein Begriff, dessen Treffer ezAuction selbst prüft (Search.OwnFilter, auch die Lupe
    -- einer Zeile): alle geprüften Treffer zusammen in Blizzards Ergebnisliste.
    local collect = #run.keys > 0 and (run.total > 1 or Search.OwnFilter(run.entries[1]))
        and C_AuctionHouse.SearchForItemKeys ~= nil
    local shown = Search.shown
    if shown and shown.entryOf == run.entryOf then
        if collect then shown.keys = run.keys else shown.query = run.lastQuery end
    end
    if collect then
        Search.SendShown("listshow", L.QUEUE_LIST:format(run.list.name or "?"), function()
            -- Inzwischen im Reiter eines fremden Addons: die Sammelsuche verfällt (die Treffer je Eintrag bleiben).
            if Search.running or not ns.AuctionHouseShown() or Foreign() then return false end
            -- Zur Ergebnisliste nur, wenn der Spieler noch im Reiter „Kaufen“ steht (etwa in der Ansicht eines
            -- Gegenstands); ist er inzwischen in „Verkaufen“ oder „Auktionen“, bleibt er dort – die Antwort füllt
            -- Blizzards Ergebnisliste trotzdem und steht beim Zurückwechseln da (Welle 23, Hinweis aus Welle 3).
            if ns.ModeName() == "buy" then ns.ShowBrowseResults() end
            Core.Call(C_AuctionHouse.SearchForItemKeys, run.keys, Search.Sorts())
            return true
        end)
    end
    Changed()
end

-- Eine Abfrage, deren Antwort Blizzards Ergebnisliste zeigen soll (Sammelsuche am Ende einer Liste, Wiederholung der
-- vorigen Ansicht nach einer Erfassung): als Auftrag der Warteschlange, fertig mit der nächsten Antwort der Übersicht
-- (Search.OnShownAnswer). send() → true, wenn gesendet. Rückgabe: der Auftrag.
Search.showJob = nil
function Search.SendShown(name, text, send)
    local job = { name = name, text = text }
    job.start = function()
        local ok, sent = pcall(send)
        if ok and sent then
            job.sent = true
        else
            if Search.showJob == job then Search.showJob = nil end
            ns.JobDone(job)
        end
    end
    job.cancel = function() if Search.showJob == job then Search.showJob = nil end end
    if Search.showJob and Search.showJob ~= job then ns.DropJob(Search.showJob) end
    Search.showJob = job
    ns.Enqueue(job)
    return job
end

-- Die Antwort auf den gesendeten Auftrag ist da: die Liste gehört wieder dem Nächsten.
function Search.OnShownAnswer(job)
    if not (job and job.sent and Search.showJob == job) then return false end
    Search.showJob = nil
    ns.JobDone(job)
    return true
end

-- silent: kein Hinweis im Chat (z. B. wenn gleich die nächste Liste startet).
function Search.Cancel(silent)
    local run = Search.running
    if not run then return end
    Search.running = nil
    ns.DropJob(run.job)
    if not silent then ns.Print(L.LIST_CANCELLED:format(run.list.name)) end
    Changed()
end

-- Einen einzelnen Gegenstand oder Begriff in Blizzards Ergebnisliste suchen (itemID, Link, Text oder Eintrag wie
-- bei Lists.NormalizeEntry) – für andere Module, z. B. ein Eintrag am Gegenstand in ezBag (Vollprüfung V-163).
-- Rückgabe: true und der Suchbegriff, oder false und der Grund: "closed" (Auktionshaus zu), "item" (nichts
-- Brauchbares bzw. Name noch nicht geladen), "missing" (Client ohne Suche), "other" (das Fenster zeigt die Ansicht
-- eines fremden Addons – dort schaltet ezAuction nichts um; wechselt der Spieler dorthin, während die Suche noch
-- auf den Takt des Servers wartet, verfällt sie).
function Search.Item(value)
    if not (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery) then return false, "missing" end
    if not ns.AuctionHouseShown() then return false, "closed" end
    if Foreign() then return false, "other" end
    local entry = ns.Lists.NormalizeEntry(value)
    local term = entry and ns.Lists.SearchText(entry)
    if not term then return false, "item" end
    if Search.running then Search.Cancel(true) end
    ns.UserQuery()
    ns.ShowBrowseResults()
    local query = Search.QueryFor(entry, term)
    local shown = { kind = "item", term = term, query = query }   -- ohne Filterzeile; gemerkt für Search.Resort
    Show(shown)
    -- noch eingereiht, aber die Ansicht ist schon eine andere (z. B. „Zurücksetzen“, BuyTab.lua): nicht mehr senden
    ns.WhenThrottleReady(function()
        if Search.shown ~= shown then return end
        if ns.AuctionHouseShown() and not Foreign() then pcall(C_AuctionHouse.SendBrowseQuery, query) end
    end)
    return true, term
end

-- ezCore.API("ezAuction").Search(item) → true, Suchbegriff | false, Grund (siehe Search.Item)
ns.API.Search = Search.Item

-- Nach Blizzards eigener Abfrage etwas starten (Eingabetaste mit gewählter Einkaufsliste, BuyTab.lua): erst, wenn ihre
-- Antwort da ist – sonst zählte sie als Antwort auf den ersten Listeneintrag (Befund des Reviews vom 21.11.2026);
-- bleibt sie aus, nach ANSWER_WAIT Sekunden. Ein neuer Aufruf ersetzt den alten.
Search.ANSWER_WAIT = 3
local afterAnswer
local function RunAfterAnswer()
    local pending = afterAnswer
    afterAnswer = nil
    if pending then ns.Try("AfterAnswer", pending.fn) end
end
function Search.AfterBlizzardAnswer(fn)
    local pending = { fn = fn }
    afterAnswer = pending
    C_Timer.After(Search.ANSWER_WAIT, function()
        if afterAnswer == pending then RunAfterAnswer() end
    end)
end
function Search.CancelAfterAnswer() afterAnswer = nil end

-- Antwort der Übersicht: zuerst merken, ob ein gezeigter Auftrag (Search.SendShown) schon gesendet war – beendet die
-- Listensuche hier ihren letzten Eintrag, startet ihre Sammelsuche, und deren Antwort kommt erst später.
local function OnBrowseAnswer(failed)
    -- Blizzards Antwort ist da: Wartendes im nächsten Bild starten (nach ezCores eigener Auswertung der Antwort)
    if afterAnswer and not (Search.running and Search.running.waiting) then
        local pending = afterAnswer
        C_Timer.After(0, function()
            if afterAnswer == pending then RunAfterAnswer() end
        end)
    end
    local shown = Search.showJob
    local wasSent = shown ~= nil and shown.sent
    if Search.running and Search.running.waiting then Search.OnResults(failed) end
    if wasSent then Search.OnShownAnswer(shown) end
end
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() OnBrowseAnswer(false) end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function() OnBrowseAnswer(false) end)
ns.On("AUCTION_HOUSE_BROWSE_FAILURE", function() OnBrowseAnswer(true) end)
ns.Listen("AH_CLOSED", function() Search.Cancel(true) Search.CancelAfterAnswer() end)
ns.Listen("AH_HIDE", function() Search.Cancel(true) Search.CancelAfterAnswer() end)
-- Ansicht eines fremden Addons (Core.lua, ns.ForeignView): dessen Suchen liefen sonst in die Listensuche hinein.
ns.Listen("AH_MODE", function(mode)
    if mode == "other" then
        Search.Cancel()
        -- eine wartende Sammelsuche bzw. Wiederholung verfällt dort (sonst holte sie den Spieler später zurück)
        if Search.showJob then
            ns.DropJob(Search.showJob)
            Search.showJob = nil
        end
    end
end)

---------------------------------------------------------------------------
-- Suchverlauf (AH-08): die letzten Search.RECENT_MAX Suchen in ezAuctionDB.ui.recent, jüngste zuerst:
--   { text, minLevel, maxLevel, flags = { Blizzards Filter-Kennungen … }, category = wie bei Lists.CleanCategory,
--     noCategory = true (Blizzards Lesefunktion fehlte – Kategorie unbekannt), time }
---------------------------------------------------------------------------

Search.RECENT_MAX = 20
Search.RECENT_FLAGS = 32      -- so viele Filter-Kennungen merkt ein Eintrag höchstens

local function Store()
    local ui = ns.db and ns.db.ui
    if not ui then return {} end
    if type(ui.recent) ~= "table" then ui.recent = {} end
    return ui.recent
end

local function Int(value, low, high) return Lists().Int(value, low, high) end

-- Ein Eintrag geprüft (aus dem Hook oder aus dem Speicher); nil, wenn nichts zu wiederholen wäre.
function Search.CleanRecent(value)
    if type(value) ~= "table" then return nil end
    local text = type(value.text) == "string" and not Core.IsSecret(value.text) and Core.Trim(value.text) or ""
    if #text > Lists().TEXT_LETTERS then text = Core.Trim(Core.TruncateChars(text, Lists().TEXT_LETTERS)) end
    local flags, seen = {}, {}
    for _, flag in ipairs(type(value.flags) == "table" and value.flags or {}) do
        flag = Int(flag, 0, 1e4)
        if flag and not seen[flag] and #flags < Search.RECENT_FLAGS then
            seen[flag] = true
            flags[#flags + 1] = flag
        end
    end
    table.sort(flags)
    local low, high = Int(value.minLevel, 1, Lists().MAX_LEVEL), Int(value.maxLevel, 1, Lists().MAX_LEVEL)
    if low and high and low > high then low, high = high, low end
    local category = Lists().CleanCategory(value.category)
    if text == "" and not category then return nil end
    return { text = text, minLevel = low, maxLevel = high, flags = flags, category = category,
        noCategory = (not category and value.noCategory == true) or nil, time = Core.Num(value.time) }
end

-- Kennung zum Zusammenlegen: dieselbe Suche steht nur einmal da (die jüngste oben).
function Search.RecentKey(item)
    local category = item.category
    local parts = { item.text:lower(), item.minLevel or "", item.maxLevel or "", table.concat(item.flags or {}, ","),
        category and (category.name or "?") or "" }
    for _, f in ipairs(category and category.filters or {}) do
        parts[#parts + 1] = ("%s.%s.%s"):format(f.classID, f.subClassID or "", f.inventoryType or "")
    end
    return table.concat(parts, "|")
end

-- Die gemerkten Suchen, geprüft (Kaputtes fällt aus dem Speicher). Jüngste zuerst.
function Search.Recent()
    local store, out = Store(), {}
    for _, value in ipairs(store) do
        local item = Search.CleanRecent(value)
        if item and #out < Search.RECENT_MAX then out[#out + 1] = item end
    end
    for index = #store, 1, -1 do store[index] = nil end
    for index, item in ipairs(out) do store[index] = item end
    return store
end

-- Eine Suche vorn einreihen (eine gleiche wandert nach vorn). Rückgabe: der Eintrag oder nil.
function Search.Remember(value)
    if not ns.Enabled("recentSearches") then return nil end
    local item = Search.CleanRecent(value)
    if not item then return nil end
    item.time = time()
    local list, key = Search.Recent(), Search.RecentKey(item)
    for index = #list, 1, -1 do
        if Search.RecentKey(list[index]) == key then table.remove(list, index) end
    end
    table.insert(list, 1, item)
    while #list > Search.RECENT_MAX do table.remove(list) end
    return item
end

function Search.ClearRecent()
    local store = Store()
    for index = #store, 1, -1 do store[index] = nil end
    ns.Print(L.RECENT_CLEARED)
end

-- Name der gewählten Kategorie aus Blizzards Lesefunktion GetSelectedCategory und der Tabelle AuctionCategories
-- (nur gelesen): „Rüstung » Stoff“; nil, wenn sich nichts lesen lässt.
function Search.CategoryName(categories)
    local root = rawget(_G, "AuctionCategories")
    if not (categories and type(categories.GetSelectedCategory) == "function" and type(root) == "table") then return nil end
    local ok, a, b, c = pcall(categories.GetSelectedCategory, categories)
    if not ok then return nil end
    local names, nodes = {}, root
    for _, index in ipairs({ a or false, b or false, c or false }) do
        local node = index and type(nodes) == "table" and nodes[index]
        if type(node) ~= "table" then break end
        if type(node.name) == "string" then names[#names + 1] = node.name end
        nodes = node.subCategories
    end
    if #names == 0 then return nil end
    return table.concat(names, " " .. Core.ARROW .. " ")
end

-- Kategorie der gerade gesendeten Suche: Kategorie (wie Lists.CleanCategory) bzw. nil; zweite Rückgabe true, wenn
-- Blizzards Lesefunktion fehlt (dann bleibt die Kategorie unbekannt, und der Eintrag sagt das).
function Search.CurrentCategory()
    local categories = AuctionHouseFrame and AuctionHouseFrame.CategoriesList
    if not (categories and type(categories.GetCategoryFilterData) == "function") then return nil, true end
    local ok, filters, implicit = pcall(categories.GetCategoryFilterData, categories)
    if not ok then return nil, true end
    if filters == nil and implicit == nil then return nil end
    return Lists().CleanCategory({ name = Search.CategoryName(categories), filters = filters, implicit = implicit })
end

-- Aus dem Hook auf Blizzards AuctionHouseFrame:SendBrowseQuery(Text, Stufe von, Stufe bis, Filter): mitschreiben.
-- Die letzte Suche des Spielers bleibt auch ohne Suchverlauf in Search.lastPlayer: nach einer Erfassung wiederholt
-- ezAuction sie als eigene Abfrage (AH-37, Capture.Restore).
function Search.RecordPlayerSearch(searchString, minLevel, maxLevel, filters)
    local category, unknown = Search.CurrentCategory()
    local value = { text = searchString, minLevel = minLevel, maxLevel = maxLevel, flags = filters,
        category = category, noCategory = unknown }
    Search.lastPlayer = Search.CleanRecent(value)
    return Search.Remember(value)
end

-- Namen der Filter-Kennungen, die eine Zeile nennt (die übrigen sind Blizzards Grundstand und bleiben ungenannt).
Search.FLAG_TEXTS = { "ExactMatch", "UsableOnly", "UncollectedOnly", "UpgradesOnly", "CurrentExpansionOnly",
    "LegendaryCraftedItemOnly" }

local function FlagNames(flags)
    local enum = Enum and Enum.AuctionHouseFilter
    if type(enum) ~= "table" then return {} end
    local set = {}
    for _, flag in ipairs(flags or {}) do set[flag] = true end
    local out = {}
    for _, name in ipairs(Search.FLAG_TEXTS) do
        if enum[name] and set[enum[name]] then out[#out + 1] = L["FLAG_" .. name] end
    end
    -- Qualitäten: nur nennen, wenn nicht alle gewählt sind (Blizzards Grundstand: alle)
    local chosen, known = {}, 0
    for quality = 0, #Search.QUALITY_FLAGS do
        local flag = enum[Search.QUALITY_FLAGS[quality]]
        if flag then
            known = known + 1
            if set[flag] then chosen[#chosen + 1] = Lists().QualityName(quality) end
        end
    end
    if #chosen > 0 and #chosen < known then out[#out + 1] = table.concat(chosen, "/") end
    return out
end

-- Filter einer gemerkten Suche als Text („Rüstung » Stoff, Stufe 20–30, selten“); nil ohne Filter.
function Search.RecentFilterText(item)
    local parts = {}
    if item.category then
        parts[#parts + 1] = item.category.name or L.FILTER_CATEGORY
    elseif item.noCategory then
        parts[#parts + 1] = L.RECENT_NO_CATEGORY
    end
    parts[#parts + 1] = Lists().LevelText(item.minLevel, item.maxLevel)
    for _, name in ipairs(FlagNames(item.flags)) do parts[#parts + 1] = name end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Beschriftung im Menü: „Erz (Rüstung » Stoff, Stufe 20–30)“.
function Search.RecentLabel(item)
    local text = item.text ~= "" and item.text or L.RECENT_NO_TEXT
    local filters = Search.RecentFilterText(item)
    return filters and (text .. " (" .. filters .. ")") or text
end

-- Eigene Abfrage für eine gemerkte Suche (Kopien, nie Blizzards Tabellen).
function Search.RecentQuery(item)
    local query = { searchString = item.text, sorts = Search.Sorts(), minLevel = item.minLevel, maxLevel = item.maxLevel,
        filters = {} }
    for index, flag in ipairs(item.flags or {}) do query.filters[index] = flag end
    local category = item.category
    if category then
        if category.filters then
            query.itemClassFilters = {}
            for index, f in ipairs(category.filters) do
                query.itemClassFilters[index] = { classID = f.classID, subClassID = f.subClassID, inventoryType = f.inventoryType }
            end
        end
        local implicit, known = category.implicit, false
        for _, flag in ipairs(query.filters) do if flag == implicit then known = true end end
        if implicit and not known then query.filters[#query.filters + 1] = implicit end
    end
    return query
end

-- Text in Blizzards Suchfeld setzen – das Einzige, was ezAuction dort setzt (Blizzards Filterknopf bleibt, wie er ist).
local function SetBoxText(text)
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    local box = bar and bar.SearchBox
    if box and box.SetText then pcall(box.SetText, box, text or "") end
end

-- Eine gemerkte Suche wiederholen. Rückgabe: true, oder false und Grund ("closed", "other", "missing", "item").
function Search.Replay(item)
    if not (C_AuctionHouse and C_AuctionHouse.SendBrowseQuery) then return false, "missing" end
    if not ns.AuctionHouseShown() then return false, "closed" end
    if Foreign() then return false, "other" end
    item = Search.CleanRecent(item)
    if not item then return false, "item" end
    if Search.running then Search.Cancel(true) end
    ns.UserQuery()
    if ns.Buy and ns.Buy.Select then ns.Buy.Select(nil) end
    ns.ShowBrowseResults()
    SetBoxText(item.text)
    local filters = Search.RecentFilterText(item)
    local query = Search.RecentQuery(item)
    local shown = { kind = "recent", term = item.text, query = query,
        text = filters and L.FILTERBAR_RECENT:format(Search.RecentLabel(item)) or nil }
    Show(shown)
    Search.Remember(item)
    ns.WhenThrottleReady(function()
        if Search.shown ~= shown then return end   -- inzwischen zurückgesetzt oder ersetzt
        if ns.AuctionHouseShown() and not Foreign() then pcall(C_AuctionHouse.SendBrowseQuery, query) end
    end)
    Changed()
    return true
end

-- Menü am Pfeil-Knopf: die gemerkten Suchen, darunter „Verlauf leeren“. Ohne Blizzards Menü: die jüngste wiederholen.
function Search.RecentMenu(owner)
    local recent = Search.Recent()
    local opened = Core.Menu.Open(owner, function(root)
        Core.Menu.Title(root, L.RECENT_TITLE)
        if #recent == 0 then
            Core.Menu.Title(root, L.RECENT_EMPTY)
            return
        end
        for _, item in ipairs(recent) do
            local copy = item
            Core.Menu.Button(root, Search.RecentLabel(item), function() Search.Replay(copy) end)
        end
        Core.Menu.Divider(root)
        Core.Menu.Button(root, L.RECENT_CLEAR, function() Search.ClearRecent() end)
    end)
    if not opened then
        if recent[1] then Search.Replay(recent[1]) else ns.Print(L.RECENT_EMPTY) end
    end
    return opened
end

---------------------------------------------------------------------------
-- Pfeil-Knopf neben dem Suchfeld und Filterzeile über der Ergebnisliste
---------------------------------------------------------------------------

local arrow, bar

function Search.RecentButton()
    return arrow ~= nil and arrow:IsVisible() and arrow or nil
end

function Search.FilterBar()
    return bar
end

function Search.UpdateArrow()
    if not arrow then return end
    local mode = ns.ModeName()
    arrow:SetShown(ns.Enabled("recentSearches") and ns.AuctionHouseShown() and mode == "buy")
end

-- Die Zeile steht nur, solange eigene Filter gelten, die Blizzards Filterknopf nicht zeigt – und nie in der Ansicht
-- eines fremden Addons.
function Search.UpdateBar()
    if not bar then return end
    local shown = Search.shown
    local text = shown and shown.text
    local _, browsing = ns.ModeName()
    -- Gehört die Liste gerade einer Erfassung, steht dort deren Hinweiszeile (AH-37) – die Filter gelten dann nicht.
    if not (text and browsing and ns.AuctionHouseShown()) or Search.Capture.BarShown() then
        bar:Hide()
        return
    end
    bar.text:SetText(text)
    bar:Show()
end

-- „×“: die eigenen Filter vergessen und den Text des Suchfelds ohne sie suchen (eigene Abfrage, nur Text und
-- Sortierung). Blizzards Filterknopf gilt wieder bei der nächsten eigenen Suche des Spielers.
function Search.ResetFilters()
    local shown = Search.shown
    if Search.running then Search.Cancel(true) end
    Show(nil)
    local box = AuctionHouseFrame and AuctionHouseFrame.SearchBar and AuctionHouseFrame.SearchBar.SearchBox
    local text = box and box.GetText and box:GetText()
    if type(text) ~= "string" or Core.IsSecret(text) or Core.Trim(text) == "" then
        text = shown and shown.term
    end
    if type(text) == "string" and Core.Trim(text) ~= "" and ns.AuctionHouseShown() and not Foreign() then
        local query = { searchString = Core.Trim(text), sorts = Search.Sorts(), filters = {} }
        ns.UserQuery()
        Show({ kind = "item", term = query.searchString, query = query })   -- ohne Filterzeile; für Search.Resort
        ns.WhenThrottleReady(function()
            if ns.AuctionHouseShown() and not Foreign() then pcall(C_AuctionHouse.SendBrowseQuery, query) end
        end)
    end
    Changed()
    return true
end

-- Ansicht „Beobachtet“ (Buy.ShowWatched): Blizzards Favoritensuche (C_AuctionHouse.SearchForFavorites, nur gelesen –
-- StartFavoritesSearch ruft ezAuction nicht, Welle 13) mit der gewünschten Sortierung senden; der Spiegel lernt die
-- Antwort mit (Watch.pending). Eine Stelle für den Klick, das Sortieren und die Wiederholung nach einer Erfassung.
-- → true, wenn gesendet.
function Search.SendWatched(sorts)
    local api = C_AuctionHouse
    if not (api and type(api.SearchForFavorites) == "function") then return false end
    if ns.Watch then ns.Watch.pending = true end
    local ok = pcall(api.SearchForFavorites, sorts or Search.Sorts())
    if not ok and ns.Watch then ns.Watch.pending = nil end
    return ok
end

-- Nach einem Klick auf einen Spaltenkopf (Hook auf AuctionHouseFrame:SetBrowseSortOrder): Blizzard hat seine eigene
-- letzte Suche neu geschickt. Zeigt die Liste gerade ezAuctions Abfrage, geht sie mit Blizzards neuer Sortierung
-- noch einmal hinaus (die Sammelsuche einer Liste ebenso); läuft eine Listensuche und wartet sie gerade auf den
-- Server, wird ihr Eintrag neu gesendet, damit Blizzards Antwort nicht als dessen Treffer zählt.
-- Rückgabe: true, wenn etwas neu gesendet wird.
function Search.Resort()
    if not ns.AuctionHouseShown() or Foreign() then return false end
    local run = Search.running
    if run then
        if not run.waiting then return false end
        local done = run.job
        run.waiting = false
        run.click = false   -- der Spieler hat sortiert: ab jetzt mit Haltezeit (Search.Send)
        run.index = run.index - 1
        Search.Next()
        ns.JobDone(done)
        return true
    end
    local shown = Search.shown
    if not shown then return false end
    local sorts = Search.Sorts()
    local function Still() return Search.shown == shown and not Search.running and ns.AuctionHouseShown() and not Foreign() end
    if shown.keys and C_AuctionHouse.SearchForItemKeys then
        ns.WhenThrottleReady(function()
            if Still() then Core.Call(C_AuctionHouse.SearchForItemKeys, shown.keys, sorts) end
        end)
        return true
    end
    if type(shown.query) == "table" and C_AuctionHouse.SendBrowseQuery then
        local query = {}
        for key, value in pairs(shown.query) do query[key] = value end
        query.sorts = sorts
        ns.WhenThrottleReady(function()
            if Still() then pcall(C_AuctionHouse.SendBrowseQuery, query) end
        end)
        return true
    end
    -- „Beobachtet“: Blizzards Favoritensuche mit der neuen Sortierung (sonst sortierte Blizzard seine letzte eigene
    -- Suche und die Ansicht ginge verloren; Welle 23, Übergabe aus Welle 14)
    if shown.kind == "watch" then
        ns.WhenThrottleReady(function()
            if Still() then Search.SendWatched(sorts) end
        end)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Erfassung in Blizzards Ergebnisliste (AH-37): Hinweiszeile mit „Abbrechen“, danach die vorige Ansicht
---------------------------------------------------------------------------
--[[
    Eine Erfassung (ezCores Auffrischung „Meine Preise“, „Fehlende“, ein Durchlauf je Kategorie) schickt ihre Abfragen
    über die Übersicht – Blizzards Ergebnisliste zeigt dann deren Antworten. Solange ein solcher Auftrag die
    Warteschlange hält (Queue.Owner), steht über der Liste „ezAuction erfasst gerade Preise (…) – diese Liste gehört der
    Erfassung“ mit dem Knopf „Abbrechen“. Beim ersten Auftrag merkt sich ezAuction die Ansicht des Spielers (eine Liste
    oder Suche von ezAuction, Blizzards Favoriten – Blizzards Feld isDisplayingFavorites, nur gelesen – oder seine
    letzte eigene Suche); nach dem letzten Auftrag geht sie als eigene Abfrage noch einmal hinaus (Rang „modul“, also
    keine Suche des Spielers): die Suche mit einer eigenen Abfrage-Tabelle (wie der Suchverlauf), die Favoriten über
    C_AuctionHouse.SearchForFavorites. Blizzards StartSearch bzw. StartFavoritesSearch ruft ezAuction dafür nicht:
    laut Blizzards Quelle (Zweig forever, Blizzard_AuctionHouseSearchBar.lua) schreibt StartSearch die Stufen in
    g_auctionHouseFilters und StartFavoritesSearch ruft SetSelectedCategory – beides schließen Leitlinie 5 und die
    Festlegung aus Welle 12 aus. Sucht der Spieler selbst, gilt seine neue Ansicht: nichts wird wiederholt.
]]
local Capture = {}
Search.Capture = Capture
Capture.RESTORE_DELAY = 0.5   -- so lange nach dem letzten Auftrag warten, ob ein weiterer folgt
Capture.RESTORE_TRIES = 20    -- … höchstens so oft, solange noch Aufträge warten
Capture.STOP_SECONDS = 30     -- nach „Abbrechen“: so lange wird jeder weitere Schritt derselben Erfassung abgebrochen

local captureBar

-- Gehört dieser Auftrag einer Erfassung? Rang „erfassung“ oder ezCores Auffrischung (Schlüssel „refresh:…“, Herkunft
-- Sammelabfrage bzw. Kategorie). ezAuctions eigene Aufträge (Listensuche, Unterboten-Prüfung) und die Suche des
-- Spielers zählen nicht.
function Capture.Is(owner)
    if type(owner) ~= "table" or owner.rank == "user" then return false end
    local key = type(owner.key) == "string" and owner.key or ""
    if key:sub(1, #ns.QUEUE_PREFIX) == ns.QUEUE_PREFIX then return false end
    return owner.rank == "capture" or owner.origin == "bulk" or owner.origin == "category" or key:find("^refresh:") ~= nil
end

-- Der Auftrag einer Erfassung, der gerade die Liste hält; sonst nil.
function Capture.Owner()
    local queue = ns.Queue()
    local owner = queue and type(queue.Owner) == "function" and Core.Call(queue.Owner)
    if Capture.Is(owner) then return owner end
    return nil
end

function Capture.Text(owner)
    local what = type(owner) == "table" and type(owner.text) == "string" and owner.text ~= "" and owner.text
    return what and L.CAPTURE_BAR_WHAT:format(what) or L.CAPTURE_BAR
end

-- Die Ansicht des Spielers jetzt: { kind = "shown", shown } | { kind = "favorites" } | { kind = "search", item } | nil
function Capture.ViewNow()
    if Search.shown then return { kind = "shown", shown = Search.shown } end
    if Core.Peek(AuctionHouseFrame, "isDisplayingFavorites") == true then return { kind = "favorites" } end
    if Search.lastPlayer then return { kind = "search", item = Search.lastPlayer } end
    return nil
end

-- Die gemerkte Ansicht als eigene Abfrage wiederholen. Rückgabe: true, wenn ein Auftrag eingereiht wurde.
function Capture.Restore(view)
    if type(view) ~= "table" or not ns.Enabled("restoreView") or not ns.AuctionHouseShown() or Foreign() then return false end
    local api = C_AuctionHouse
    local send
    if view.kind == "shown" then
        local shown = view.shown
        if Search.shown ~= shown then return false end
        if shown.keys and api.SearchForItemKeys then
            send = function() return Search.shown == shown and Core.Call(api.SearchForItemKeys, shown.keys, Search.Sorts()) ~= false end
        elseif type(shown.query) == "table" and api.SendBrowseQuery then
            send = function()
                if Search.shown ~= shown then return false end
                local query = {}
                for key, value in pairs(shown.query) do query[key] = value end
                query.sorts = Search.Sorts()
                return (pcall(api.SendBrowseQuery, query))
            end
        elseif shown.kind == "watch" then
            -- „Beobachtet“ kommt nach einer Erfassung wieder (Welle 23)
            send = function() return Search.shown == shown and Search.SendWatched(Search.Sorts()) end
        end
    elseif view.kind == "favorites" and type(api.SearchForFavorites) == "function" then
        send = function() return (pcall(api.SearchForFavorites, Search.Sorts())) end
    elseif view.kind == "search" and view.item and api.SendBrowseQuery then
        local query = Search.RecentQuery(view.item)
        send = function() return (pcall(api.SendBrowseQuery, query)) end
    end
    if not send then return false end
    Search.SendShown("restore", L.QUEUE_RESTORE, function()
        if not ns.AuctionHouseShown() or Foreign() or Search.running then return false end
        return send()
    end)
    return true
end

-- Ende der Erfassung: nach kurzer Frist nachsehen, ob noch ein Auftrag einer Erfassung folgt.
function Capture.PlanEnd(tries)
    tries = tries or 0
    C_Timer.After(Capture.RESTORE_DELAY, function()
        if not Capture.active or Capture.Owner() then return end
        local queue = ns.Queue()
        local pending = queue and type(queue.Pending) == "function" and Core.Num(Core.Call(queue.Pending)) or 0
        if pending > 0 and tries < Capture.RESTORE_TRIES then return Capture.PlanEnd(tries + 1) end
        Capture.End()
    end)
end

function Capture.End()
    local view = Capture.before
    Capture.active, Capture.before, Capture.stopUntil = false, nil, nil
    Capture.UpdateBar()
    return Capture.Restore(view)
end

-- Neuer Besitzer der Warteschlange (Nachricht PRICES_QUEUE_CHANGED).
function Capture.OnChanged()
    local owner = Capture.Owner()
    if owner then
        if not Capture.active then
            Capture.active = true
            local mode = ns.ModeName()
            Capture.before = mode == "buy" and Capture.ViewNow() or nil
        end
        -- nach „Abbrechen“: der nächste Schritt hat seine Abfrage schon gesendet – gleich danach abbrechen
        if Capture.stopUntil and GetTime() < Capture.stopUntil then
            local key = owner.key
            C_Timer.After(0, function() Capture.CancelKey(key) end)
        end
    elseif Capture.active then
        Capture.PlanEnd()
    end
    Capture.UpdateBar()
end

function Capture.CancelKey(key)
    local queue = ns.Queue()
    local owner = Capture.Owner()
    if queue and owner and owner.key == key then queue.Cancel(key) return true end
    return false
end

-- Knopf „Abbrechen“: den laufenden Schritt abbrechen und jeden weiteren derselben Erfassung, der in den nächsten
-- Capture.STOP_SECONDS startet. Rückgabe: true, wenn etwas abgebrochen wurde.
function Capture.Cancel()
    local owner = Capture.Owner()
    if not owner then return false end
    Capture.stopUntil = GetTime() + Capture.STOP_SECONDS
    Capture.CancelKey(owner.key)
    ns.Print(L.CAPTURE_CANCELLED)
    Capture.UpdateBar()
    return true
end

-- Der Spieler sucht selbst (Queue.OnUserSearch): seine neue Ansicht gilt, nichts wird wiederholt.
function Capture.OnUserSearch()
    Capture.active, Capture.before = false, nil
    Capture.UpdateBar()
end

function Capture.Reset()
    Capture.active, Capture.before, Capture.stopUntil = false, nil, nil
    Capture.UpdateBar()
end

function Capture.BarShown()
    return captureBar ~= nil and captureBar:IsShown()
end

function Capture.Bar() return captureBar end

-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Abschnitt 4): ohne die Zeile änderte sich die Ergebnisliste
-- scheinbar grundlos, und „Abbrechen“ fehlte.
function Capture.UpdateBar()
    if captureBar then
        local owner = ns.AuctionHouseShown() and Capture.Owner()
        local _, browsing = ns.ModeName()
        if owner and browsing then
            captureBar.text:SetText(Capture.Text(owner))
            captureBar:Show()
        else
            captureBar:Hide()
        end
    end
    Search.UpdateBar()
end

function Capture.Build()
    local results = AuctionHouseFrame.BrowseResultsFrame
    if not results or captureBar then return end
    captureBar = CreateFrame("Frame", "ezAuctionCaptureBar", results)
    captureBar:SetHeight(16)
    captureBar:SetPoint("BOTTOMLEFT", results, "TOPLEFT", 4, 1)
    captureBar:SetPoint("BOTTOMRIGHT", results, "TOPRIGHT", -24, 1)
    captureBar:SetFrameLevel((results:GetFrameLevel() or 1) + 11)
    captureBar.text = captureBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    captureBar.text:SetPoint("LEFT", captureBar, "LEFT", 0, 0)
    captureBar.text:SetPoint("RIGHT", captureBar, "RIGHT", -80, 0)
    captureBar.text:SetJustifyH("LEFT")
    captureBar.cancel = ns.TextButton(captureBar)
    captureBar.cancel:SetLabel(Core.Word("CANCEL"))
    captureBar.cancel:SetPoint("RIGHT", captureBar, "RIGHT", 0, 0)
    captureBar.cancel:SetScript("OnClick", function() Capture.Cancel() end)
    captureBar.cancel:SetScript("OnEnter", function(self) Core.ShowTip(self, Core.Word("CANCEL"), L.CAPTURE_CANCEL_TIP) end)
    captureBar:Hide()
    Capture.UpdateBar()
end

Core.Listen("PRICES_QUEUE_CHANGED", function() ns.Try("Capture", Capture.OnChanged) end, "ezAuction")
do
    local queue = Core.Prices and Core.Prices.Queue
    if type(queue) == "table" and type(queue.OnUserSearch) == "function" then
        -- auch ein Klick in ezAuctions Suchverlauf oder „ד ist eine eigene Suche des Spielers (ns.UserQuery)
        queue.OnUserSearch("ezAuction", function() Capture.OnUserSearch() end)
    end
end
local function BuildArrow()
    local searchBar = AuctionHouseFrame.SearchBar
    local box = searchBar and searchBar.SearchBox
    if not box then return end
    -- Rechts neben dem Suchfeld wie der Knopf an Blizzards Auswahlfeld (24 × 24, gleiches Bild): das Feld klappt seine
    -- letzten Suchen auf. Bis Welle 27 lag ein 16er-Knopf im Feld vor Blizzards Löschen-Knopf und war als Knopf
    -- kaum zu erkennen (Spielbefund 16.11.2026); Maße in ns.Layout.RECENT, geprüft in Tests/lage.lua. Pfeil aus ezCore
    -- (Core.Toolbar.ArrowButton, T18-13); der Name bleibt als globaler Verweis für die Lage-Prüfungen.
    local R = ns.Layout.RECENT
    arrow = Core.Toolbar.ArrowButton(searchBar, function(self) Search.RecentMenu(self) end, L.RECENT_TITLE,
        L.RECENT_TIP:format(Search.RECENT_MAX), { size = R.size })
    _G.ezAuctionRecentButton = arrow
    arrow:SetPoint("LEFT", box, "RIGHT", R.gap, 0)
    Search.UpdateArrow()
end

local function BuildBar()
    local results = AuctionHouseFrame.BrowseResultsFrame
    if not results then return end
    bar = CreateFrame("Frame", "ezAuctionFilterBar", results)
    bar:SetHeight(16)
    bar:SetPoint("BOTTOMLEFT", results, "TOPLEFT", 4, 1)
    bar:SetPoint("BOTTOMRIGHT", results, "TOPRIGHT", -24, 1)
    bar:SetFrameLevel((results:GetFrameLevel() or 1) + 10)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.text:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.text:SetPoint("RIGHT", bar, "RIGHT", -20, 0)
    bar.text:SetJustifyH("LEFT")
    bar.reset = ns.TextButton(bar)
    bar.reset:SetLabel("×")
    bar.reset:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    bar.reset:SetScript("OnClick", function() Search.ResetFilters() end)
    bar.reset:SetScript("OnEnter", function(self) Core.ShowTip(self, L.FILTERBAR_RESET, L.FILTERBAR_RESET_TIP) end)
    bar:Hide()
    Search.UpdateBar()
end

ns.OnAuctionHouse(function()
    BuildArrow()
    BuildBar()
    Search.Capture.Build()
end)
ns.Listen("AH_MODE", function()
    Search.UpdateArrow()
    Search.Capture.UpdateBar()
end)
ns.Listen("AH_SHOW", function()
    Search.UpdateArrow()
    Search.Capture.UpdateBar()
end)
ns.Listen("AH_HIDE", function()
    Show(nil)
    -- Die gemerkte Suche gehört zu diesem Besuch: beim nächsten Öffnen wiederholt eine Erfassung sie nicht.
    Search.lastPlayer = nil
    Search.Capture.Reset()
end)
ns.OnSettingChanged(function(key)
    if key == "recentSearches" then Search.UpdateArrow() end
end)

-- Eigene Suche des Spielers (Suchfeld, Kategorien, Favoriten) geht vor; sie kommt in den Suchverlauf, und die
-- Filterzeile verschwindet (jetzt gilt wieder Blizzards Filterknopf).
ns.OnAuctionHouse(function()
    -- kind: nil (Suchfeld, Kategorie) oder "favorites" – nie aus Blizzards Argumenten (SendBrowseQuery übergibt nach
    -- dem Suchtext die Stufen, Befund des Reviews vom 21.11.2026)
    local function PlayerSearch(searchString, kind)
        local run = Search.running
        if run and run.ownQuery then return end
        if run then Search.Cancel() end
        Show(nil)
        -- gewählte Einkaufsliste: Eingabetaste im leeren Suchfeld sucht sie, sonst ist sie abgewählt (BuyTab.lua)
        if ns.Buy and ns.Buy.OnBlizzardSearch then ns.Try("ListSearch", ns.Buy.OnBlizzardSearch, searchString, kind) end
    end
    if AuctionHouseFrame.SendBrowseQuery then
        hooksecurefunc(AuctionHouseFrame, "SendBrowseQuery", function(_, searchString) PlayerSearch(searchString, nil) end)
        hooksecurefunc(AuctionHouseFrame, "SendBrowseQuery", function(_, searchString, minLevel, maxLevel, filters)
            ns.Try("RecentSearch", Search.RecordPlayerSearch, searchString, minLevel, maxLevel, filters)
        end)
    end
    if AuctionHouseFrame.QueryAll then hooksecurefunc(AuctionHouseFrame, "QueryAll", function(_, context)
        if AuctionHouseSearchContext and context == AuctionHouseSearchContext.AllFavorites then PlayerSearch(nil, "favorites") end
    end) end
    -- Spaltenkopf der Ergebnisliste: Blizzard wiederholt seine eigene Suche, ezAuction danach die gezeigte
    if AuctionHouseFrame.SetBrowseSortOrder then
        hooksecurefunc(AuctionHouseFrame, "SetBrowseSortOrder", function() ns.Try("Resort", Search.Resort) end)
    end
end)
