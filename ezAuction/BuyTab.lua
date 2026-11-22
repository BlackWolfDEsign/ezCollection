local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Reiter „Kaufen“ (ersetzt Auctionators „Einkaufen“, ohne eigenen Reiter):
      - Einkaufslisten als eigene Einträge oben in Blizzards Kategorienliste, mit Blizzards Knopfvorlage
        (AuctionCategoryButtonTemplate) und Blizzards Aussehen (AuctionHouseFilterButton_SetUp). Blizzards
        Kategorien rücken darunter; ihre Liste bleibt unangetastet.
      - Klick auf eine Liste wählt sie wie eine Kategorie (Buy.Select; seit dem zweiten Spieltest vom 21.11.2026):
        Blizzards Kategorie wird abgewählt und umgekehrt, die Liste steht links (Editor.lua), und Blizzards „Suchen“
        sucht mit Blizzards Filter nur ihre Einträge (Search.lua). Vorher suchte schon der Klick, und ein Blatt-Symbol
        öffnete den Editor über Blizzards Ergebnisliste.
      - „< Händler“ in Blizzards Ergebnisliste, wenn der Tiefstpreis unter dem Händlerpreis liegt.
      - „−23 %“/„+10 %“ gegen den Marktwert, ab fünf erfassten Tagen gegen den Median (Market.Judge), mit
        Begründung, Quelle und Verfügbarkeit im Tooltip der Zeile; Pfeil „besser“ aus ezGear (Upgrade.lua).
    Fertigstellungsplan Welle 14 (AH-22 bis AH-24):
      - „Schnäppchen (n)“ und „Beobachtet (n)“ als eigene Einträge unter den Einkaufslisten (Abschnitte Bargain und
        Watch unten); seit dem vierten Spieltest vom 21.11.2026 wählt ein Klick sie wie eine Kategorie (Buy.Pick, noch
        ein Klick wählt ab), „Suchen“ bzw. Enter zeigt die Treffer in Blizzards Ergebnisliste (Auftrag in ezCores
        Warteschlange, Rang „modul“). Nichts davon steht in Blizzards Tabelle AuctionCategories.
      - Kauf-Komfort am Warenkauf und an der Einzelstück-Liste (Abschnitt „Kaufbereich“ unten): „Bedarf: n“, Zeile im
        Kaufdialog, günstigste Zeile je Stück. Kaufen und Bieten bleiben Blizzards Knöpfe – ezAuction ruft nie
        StartCommoditiesPurchase, ConfirmCommoditiesPurchase oder PlaceBid.
]]

local Buy = {}
ns.Buy = Buy
Buy.LEFT_PAD = 3     -- wie Blizzards Kategorien (view:SetPadding, leftPad = 3)
Buy.SEPARATOR = 8    -- Abstand mit Trennlinie zwischen den eigenen Einträgen und Blizzards Kategorien

local holder, scrollPoints
local allLists = { items = {} }   -- Sammel-Liste „alle Einkaufslisten“ (Buy.AllLists)
local buttons = {}
local ROW_HEIGHT = 20
local GREEN = Core.GREEN

local function Categories()
    return AuctionHouseFrame and AuctionHouseFrame.CategoriesList
end

---------------------------------------------------------------------------
-- Knöpfe im Blizzard-Stil
---------------------------------------------------------------------------

-- Ersatz, falls Blizzards Vorlage fehlt: dieselben Teile, damit Style() überall gleich arbeitet.
local function PlainButton(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(132, ROW_HEIGHT)
    button.NormalTexture = button:CreateTexture(nil, "BACKGROUND")
    button.NormalTexture:SetAllPoints()
    button.NormalTexture:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-FilterBg")
    button.NormalTexture:SetTexCoord(0, 0.53125, 0, 0.625)
    button.Lines = button:CreateTexture(nil, "BACKGROUND")
    button.Lines:Hide()
    button.HighlightTexture = button:CreateTexture(nil, "BORDER")
    button.HighlightTexture:SetAllPoints()
    button.HighlightTexture:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
    button.HighlightTexture:SetBlendMode("ADD")
    button.HighlightTexture:Hide()
    button.SelectedTexture = button:CreateTexture(nil, "ARTWORK")
    button.SelectedTexture:SetAllPoints()
    button.SelectedTexture:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-Tab-Highlight")
    button.SelectedTexture:Hide()
    button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.Text:SetPoint("LEFT", 8, 0)
    button.Text:SetPoint("RIGHT", -4, 0)
    button.Text:SetJustifyH("LEFT")
    button:SetFontString(button.Text)
    button:SetScript("OnEnter", function(self) self.HighlightTexture:Show() end)
    button:SetScript("OnLeave", function(self) self.HighlightTexture:Hide() end)
    return button
end

local function Style(button, info)
    if AuctionHouseFilterButton_SetUp and button.Lines then
        local ok = pcall(AuctionHouseFilterButton_SetUp, button, info)
        if ok then return end
    end
    button:SetText(info.name)
    if button.Text then
        button.Text:ClearAllPoints()
        button.Text:SetPoint("LEFT", button, "LEFT", info.type == "category" and 8 or 18, 0)
        button.Text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    end
    if button.SelectedTexture then button.SelectedTexture:SetShown(info.selected == true) end
end

local function NewButton()
    local ok, button = pcall(CreateFrame, "Button", nil, holder, "AuctionCategoryButtonTemplate")
    if not ok or not button then button = PlainButton(holder) end
    button:SetHeight(ROW_HEIGHT)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Stand der Listensuche bzw. Treffer („1/3 …“, „2/3“) rechts in der Zeile, nie gekürzt (Buy.ListCount). Das
    -- Blatt-Symbol „Liste bearbeiten“ davor entfiel am 21.11.2026: die gewählte Liste steht links (Editor.lua)
    local count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    count:SetJustifyH("RIGHT")
    count:Hide()
    button.ezCount = count
    -- Pfeil-Kreis am Eintrag „Beobachtet“: Fehlende auffrischen (AH-23; nur zu sehen, wenn welche fehlen)
    local refresh = CreateFrame("Button", nil, button)
    refresh:SetSize(Core.Style.BUTTON.small, Core.Style.BUTTON.small)
    refresh:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    refresh:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    refresh:SetHighlightTexture("Interface\\Buttons\\UI-RefreshButton", "ADD")
    refresh:SetScript("OnClick", function() Buy.RefreshMissing() end)
    refresh:SetScript("OnEnter", function(self)
        Core.ShowTip(self, L.WATCH_REFRESH, L.WATCH_REFRESH_TIP:format(#ns.Watch.Missing()))
    end)
    refresh:SetScript("OnLeave", GameTooltip_Hide)
    button.ezRefresh = refresh
    button:SetScript("OnClick", function(self, mouse) Buy.OnClick(self, mouse) end)
    button:HookScript("OnEnter", function(self) Buy.ShowTooltip(self) end)
    button:HookScript("OnLeave", GameTooltip_Hide)
    return button
end

---------------------------------------------------------------------------
-- Einträge
---------------------------------------------------------------------------

local function ListLabel(list)
    local index, total = ns.Search.Progress(list)
    if index then return L.LIST_RUNNING:format(list.name, index, total) end
    local result = ns.Search.results[list]
    if result then return L.LIST_RESULT:format(list.name, result.found, result.total) end
    return list.name
end

-- Stand einer Liste als eigene Zahl rechts in der Zeile (Spieltest vom 21.11.2026: „klicke ich auf diese, und dann auf
-- suchen, wird mir alles gesucht“ – der Stand hing hinten am Namen und fiel bei langen Namen der Kürzung zum Opfer,
-- man sah nicht, dass der Klick schon sucht). → Text oder nil
function Buy.ListCount(list)
    local index, total = ns.Search.Progress(list)
    if index then return L.LIST_COUNT_RUNNING:format(index, total) end
    local result = ns.Search.results[list]
    if result then return L.LIST_COUNT_RESULT:format(result.found, result.total) end
    return nil
end

-- „+ Fehlende Bücher“ steht da, solange diesem Charakter Bücher fehlen und es die Liste „Bibliotheksbücher“ noch nicht gibt.
local function ShowBooksRow()
    if ns.Lists.OfSource("books") ~= nil then return false end
    local missing = ns.Lists.MissingBooks()
    return missing ~= nil and #missing > 0
end

-- Zeilen in Anzeigereihenfolge: Überschrift, Listen (aufgeklappt), ggf. „Weitere …“, „+ Neue Liste“,
-- ggf. „+ Fehlende Bücher“ (Schalter shoppingLists); darunter „Schnäppchen (n)“ und „Beobachtet (n)“ (Welle 14, je
-- mit eigenem Schalter – sie stehen auch, wenn die Einkaufslisten aus sind).
function Buy.Rows()
    local rows, tail = {}, {}
    if ns.Enabled("bargainList") then tail[#tail + 1] = { kind = "bargain" } end
    if ns.Enabled("watchList") then tail[#tail + 1] = { kind = "watch" } end
    local function Done()
        for _, row in ipairs(tail) do rows[#rows + 1] = row end
        return rows
    end
    if not ns.Enabled("shoppingLists") then return Done() end
    local lists = ns.Lists.All()
    rows[1] = { kind = "header" }
    if ns.db.ui.listsCollapsed then return Done() end
    local categories = Categories()
    local height = categories and categories:GetHeight() or 400
    local room = math.max(4, math.floor(height * 0.45 / ROW_HEIGHT))
    local books = ShowBooksRow()
    local extra = (books and 2 or 1) + #tail
    local shown = #lists
    if 1 + #lists + extra > room then shown = room - 2 - extra end
    for index = 1, math.max(0, shown) do rows[#rows + 1] = { kind = "list", list = lists[index] } end
    if shown < #lists then rows[#rows + 1] = { kind = "more", from = shown + 1 } end
    rows[#rows + 1] = { kind = "new" }
    if books then rows[#rows + 1] = { kind = "books" } end
    return Done()
end

-- Was die Ergebnisliste gerade aus ezAuction zeigt (Search.shown.kind: „list“, „bargain“, „watch“ …); sonst nil.
local function ShownKind()
    local shown = ns.Search and ns.Search.shown
    return shown and shown.kind or nil
end

function Buy.Refresh()
    if not holder then return end
    local rows = Buy.Rows()
    if #rows == 0 then
        holder:Hide()
        return
    end
    holder:Show()
    local lists = ns.Lists.All()
    for index, row in ipairs(rows) do
        local button = buttons[index] or NewButton()
        buttons[index] = button
        button.ezRow = row
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        button:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
        local info
        if row.kind == "header" then
            local name = #lists > 0 and L.LISTS_COUNT:format(L.LISTS, #lists) or L.LISTS
            -- hervorgehoben nur mit gewählter Liste, wie Blizzards Kategorie über der gewählten Unterkategorie
            -- (zweiter Spieltest vom 21.11.2026: „wieso kann ich beides selektieren?“)
            -- gewählt („alle Listen“, Buy.Pick("lists")) oder über der gewählten Liste – wie Blizzards Oberkategorie
            info = { type = "category", name = name, selected = Buy.pick == "lists" or Buy.active ~= nil }
        elseif row.kind == "list" then
            info = { type = "subCategory", name = row.list.name, selected = Buy.active == row.list }
        elseif row.kind == "more" then
            info = { type = "subCategory", name = L.LIST_MORE:format(#lists - row.from + 1), selected = false }
        elseif row.kind == "books" then
            info = { type = "subCategory", name = GREEN .. L.LIST_BOOKS_NEW .. "|r", selected = false }
        elseif row.kind == "bargain" or row.kind == "watch" then
            -- hervorgehoben, solange gewählt (Buy.Pick), wie eine Kategorie – nicht erst nach der Suche
            local count = row.kind == "bargain" and Buy.Bargain.Count() or ns.Watch.Count()
            local name = (row.kind == "bargain" and L.BARGAIN_ROW or L.WATCH_ROW):format(count)
            info = { type = "category", name = count > 0 and name or Core.Grey(name), selected = Buy.pick == row.kind }
        else
            info = { type = "subCategory", name = GREEN .. L.LIST_NEW .. "|r", selected = false }
        end
        Style(button, info)
        -- Platz für den Pfeil-Kreis an „Beobachtet“, damit lange Namen nicht darunter laufen
        local refresh = row.kind == "watch" and ns.AuctionHouseShown() and #ns.Watch.Missing() > 0
        local count = row.kind == "list" and Buy.ListCount(row.list)
            or (row.kind == "header" and Buy.pick == "lists" and Buy.ListCount(allLists)) or nil
        button.ezCount:SetText(count or "")
        button.ezCount:SetShown(count ~= nil)
        if button.Text then
            if count then
                button.Text:SetPoint("RIGHT", button.ezCount, "LEFT", -3, 0)
            else
                button.Text:SetPoint("RIGHT", button, "RIGHT", refresh and -22 or -4, 0)
            end
        end
        button.ezRefresh:SetShown(refresh == true)
        button:Show()
    end
    for index = #rows + 1, #buttons do buttons[index]:Hide() end
    holder:SetHeight(#rows * ROW_HEIGHT + 2)
end

local function NewList()
    Core.AskText(L.LIST_NEW_PROMPT, ns.Lists.UniqueName(L.LIST_DEFAULT_NAME), function(text)
        local list = ns.Lists.Create(text)
        Buy.Select(list)
        ns.Editor.Focus()
    end)
end

-- Fehlende Bücher als Liste „Bibliotheksbücher“ anlegen und gleich suchen.
function Buy.StartBooks()
    local list, count = ns.Lists.UpdateBooks(true)
    if not list or count == 0 then
        ns.Print(L.BOOKS_NONE)
        return false
    end
    -- gewählt wie jede Liste; Blizzards „Suchen“ sucht sie (zweiter Spieltest vom 21.11.2026)
    Buy.Select(list)
    return true
end

function Buy.StartList(list)
    -- Listen mit Quelle vor jeder Suche auffrischen (Buch abgegeben, Material inzwischen gekauft).
    local source = ns.Lists.SourceOf(list)
    if source then ns.Lists.UpdateSource(source, false) end
    if Buy.active ~= list then Buy.Select(list) end
    ns.Search.Start(list)
    Buy.Refresh()
end

-- Alle Einkaufslisten als eine Suche (Spieltest vom 21.11.2026: „klick einkaufslisten also ausgewählt dann suche alle
-- sachen aus den einkaufslisten, wenn spezifische liste ausgewählt dann suche nur nach items der liste... genauso wie es
-- blizz macht“): eine Sammel-Liste aus den Einträgen aller Listen; derselbe Gegenstand mit denselben Filtern (bzw.
-- dasselbe Rezept) nur einmal, Mengen zusammengezählt. Die Sammel-Liste ist keine gespeicherte Liste.
function Buy.AllLists()
    allLists.name = L.LISTS
    local items, seen = {}, {}
    for _, list in ipairs(ns.Lists.All()) do
        for _, entry in ipairs(type(list) == "table" and type(list.items) == "table" and list.items or {}) do
            if type(entry) == "table" then
                -- Begriffe ohne itemID unabhängig von Groß- und Kleinschreibung (Befund des Reviews)
                local key = entry.recipe and ("r" .. tostring(entry.recipe) .. (entry.buy and "b" or ""))
                    or (tostring(entry.itemID or string.lower(ns.Lists.SearchText(entry) or "")) .. "|"
                        .. tostring(entry.exact or "") .. "|" .. ns.Lists.FilterKey(entry))
                local have = seen[key]
                if have then
                    local a, b = Core.Num(have.count), Core.Num(entry.count)
                    if a or b then have.count = (a or 0) + (b or 0) end
                    -- Höchstpreis: der strengere gilt; hat eine Liste keinen, gilt keiner (unabhängig von der Reihenfolge)
                    local pa, pb = Core.Num(have.maxPrice), Core.Num(entry.maxPrice)
                    have.maxPrice = (pa and pb) and math.min(pa, pb) or nil
                else
                    local copy = {}
                    for k, v in pairs(entry) do copy[k] = v end
                    seen[key] = copy
                    items[#items + 1] = copy
                end
            end
        end
    end
    allLists.items = items
    return allLists
end

function Buy.StartAll()
    ns.Lists.UpdateSources()
    if Buy.pick ~= "lists" then Buy.Pick("lists") end
    local all = Buy.AllLists()
    if ns.Lists.ForgetSearch then ns.Lists.ForgetSearch() end   -- die Sammel-Liste ändert sich mit jeder Liste
    local started = ns.Search.Start(all)
    Buy.Refresh()
    return started
end

-- Nur eine Zeile einer Liste suchen (Knopf „Suchen“ an der Zeile im Editor, AH-10). Rückgabe: true, wenn gesucht wird.
function Buy.StartEntry(list, entry)
    local index
    for i, other in ipairs(type(list) == "table" and list.items or {}) do
        if other == entry then index = i end
    end
    if not index then return false end
    if Buy.active ~= list then Buy.Select(list) end
    local started = ns.Search.Start(list, index)
    Buy.Refresh()
    return started
end

local function MoreMenu(owner, from)
    local lists = ns.Lists.All()
    local opened = Core.Menu.Open(owner, function(root)
        for index = from, #lists do
            local list = lists[index]
            Core.Menu.Button(root, ListLabel(list), function() Buy.Select(list) end)
        end
    end)
    -- Ohne Menü: die nächste verborgene Liste wählen.
    if not opened and lists[from] then Buy.Select(lists[from]) end
end

function Buy.OnClick(button, mouse)
    local row = button.ezRow
    if not row then return end
    Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    if row.kind == "header" then
        -- wie Blizzards Oberkategorie: Klick wählt „alle Listen“ und klappt auf, noch ein Klick wählt ab und klappt zu;
        -- läuft die Suche aller Listen, bricht der Klick sie ab
        if ns.Search.IsRunning(allLists) then
            ns.Search.Cancel()
        elseif Buy.pick == "lists" and mouse ~= "RightButton" then
            ns.db.ui.listsCollapsed = true
            Buy.Select(nil)
        else
            ns.db.ui.listsCollapsed = false
            Buy.Pick("lists")
        end
    elseif row.kind == "list" then
        -- wie eine Kategorie: wählen (links erscheint die Liste); noch ein Klick wählt ab; läuft ihre Suche, bricht
        -- der Klick sie ab
        if ns.Search.IsRunning(row.list) then
            ns.Search.Cancel()
        elseif Buy.active == row.list and mouse ~= "RightButton" then
            Buy.Select(nil)
        else
            Buy.Select(row.list)
        end
    elseif row.kind == "more" then
        MoreMenu(button, row.from)
    elseif row.kind == "books" then
        Buy.StartBooks()
    elseif row.kind == "bargain" or row.kind == "watch" then
        -- wie eine Kategorie (vierter Spieltest vom 21.11.2026: „unsere listenpunkte muss man genauso abwählen können
        -- wie die blizzard kategorien“): Klick wählt, noch ein Klick wählt ab; gesucht wird mit „Suchen“ bzw. Enter
        if Buy.pick == row.kind and mouse ~= "RightButton" then Buy.Select(nil) else Buy.Pick(row.kind) end
    else
        NewList()
    end
end

function Buy.ShowTooltip(button)
    local row = button.ezRow
    if not row then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if row.kind == "header" then
        Core.TipTitle(GameTooltip, L.LISTS)
        GameTooltip:AddLine(ns.CmdText(L.LISTS_TIP), nil, nil, nil, true)
    elseif row.kind == "list" then
        local list = row.list
        Core.TipTitle(GameTooltip, list.name)
        local labels = {}
        for _, entry in ipairs(list.items or {}) do labels[#labels + 1] = ns.Lists.EntryLabel(entry) end
        Core.TipLine(GameTooltip, #labels > 0 and table.concat(labels, ", ") or L.EDITOR_EMPTY, "normal", true)
        -- Bestand aller Charaktere je Eintrag mit Gegenstand (Lists.StockText; nicht bei Listen mit Quelle)
        local stock, more = ns.Lists.StockLines(list)
        for _, line in ipairs(stock) do Core.TipLine(GameTooltip, line, "highlight", true) end
        if more > 0 then Core.TipLine(GameTooltip, L.LIST_STOCK_MORE:format(ezCore.More(more)), "hint", true) end
        local result = ns.Search.results[list]
        if result and #result.missing > 0 then
            Core.TipLine(GameTooltip, L.LIST_MISSING:format(table.concat(result.missing, ", ")), "bad", true)
        end
        -- Kostenvoranschlag (AH-10)
        local cost = ns.Enabled("listCost") and ns.Lists.CostText(list)
        if cost then Core.TipLine(GameTooltip, cost, "normal", true) end
        GameTooltip:AddLine(ns.Search.IsRunning(list) and L.LIST_CANCEL_TIP or L.LIST_SEARCH_TIP, nil, nil, nil, true)
    elseif row.kind == "more" then
        Core.TipTitle(GameTooltip, L.LIST_MORE:format(#ns.Lists.All() - row.from + 1))
        GameTooltip:AddLine(L.LIST_MORE_TIP, nil, nil, nil, true)
    elseif row.kind == "bargain" then
        Buy.BargainTooltip()
    elseif row.kind == "watch" then
        Buy.WatchTooltip()
    elseif row.kind == "books" then
        Core.TipTitle(GameTooltip, L.LIST_BOOKS_NEW)
        GameTooltip:AddLine(L.LIST_BOOKS_TIP, nil, nil, nil, true)
        local C = Core.Collections
        if C and C.BookProgress then
            local done, total = Core.Call(C.BookProgress)
            if done and total then Core.TipLine(GameTooltip, L.BOOKS_PROGRESS:format(done, total), "normal") end
        end
    else
        Core.TipTitle(GameTooltip, L.LIST_NEW)
        GameTooltip:AddLine(L.LIST_NEW_TIP, nil, nil, nil, true)
    end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Auswahl wie eine Kategorie (zweiter Spieltest vom 21.11.2026; Entscheidungen des Nutzers „Wie eine Kategorie
-- (Empfohlen)“ und – für das Abwählen von Blizzards Kategorie – „Ja, Ausnahme (Empfohlen)“ zu Leitlinie 5)
---------------------------------------------------------------------------

local resetting = false
Buy.noCategoryReset = false   -- nach einer Blockade durch Blizzard für die Sitzung aus (ns.T1Blocked)

-- Blizzards gewählte Kategorie zurücksetzen – derselbe Aufruf wie Blizzards eigener Favoriten-Knopf
-- (AuctionHouseSearchBarMixin:StartFavoritesSearch → SetSelectedCategory(nil), Shared/Blizzard_AuctionHouseSearchBar.lua,
-- Zweig forever). Die einzige Ausnahme von Leitlinie 5 in ezAuction: nur außerhalb des Kampfes, geschützt aufgerufen.
-- → true, wenn zurückgesetzt
function Buy.ResetBlizzardCategory()
    if Buy.noCategoryReset or (InCombatLockdown and InCombatLockdown()) then return false end
    local categories = Categories()
    if not (categories and categories.GetSelectedCategory and categories.SetSelectedCategory) then return false end
    local ok, index = pcall(categories.GetSelectedCategory, categories)
    if not ok or index == nil then return false end
    resetting = true
    local done = pcall(categories.SetSelectedCategory, categories, nil)
    resetting = false
    return done
end

-- Eine Liste wählen (nil: alles Eigene abwählen – Liste, Schnäppchen, Beobachtet). Gewählt: Blizzards Kategorie wird
-- abgewählt, die Liste steht links, Blizzards „Suchen“ sucht nur ihre Einträge (Buy.UpdateSearchButton). Eine Liste
-- mit Quelle wird vorher aufgefrischt.
function Buy.Select(list)
    if list ~= nil and not ns.Lists.IndexOf(list) then list = nil end
    Buy.active = list
    Buy.pick = nil
    if list then
        local source = ns.Lists.SourceOf(list)
        if source then ns.Lists.UpdateSource(source, false) end
        ns.ShowBrowseResults()
        Buy.ResetBlizzardCategory()
        -- Schnäppchen und Beobachtet sind nicht mehr gewählt
        local shown = ns.Search.shown
        if shown and (shown.kind == "bargain" or shown.kind == "watch") then ns.Search.shown = nil end
    end
    if ns.Editor then ns.Editor.Update() end
    Buy.UpdateSearchButton()
    Buy.Refresh()
    return list ~= nil
end

-- „Schnäppchen“ bzw. „Beobachtet“ wählen wie eine Kategorie (kind "bargain" | "watch"; vierter Spieltest vom
-- 21.11.2026): die Liste und Blizzards Kategorie sind abgewählt, der Eintrag ist hervorgehoben, gesucht wird erst mit
-- „Suchen“ bzw. Enter im leeren Suchfeld (Buy.SearchSelected). Vorher suchte schon der Klick und meldete im Chat.
function Buy.Pick(kind)
    if kind ~= "bargain" and kind ~= "watch" and kind ~= "lists" then return Buy.Select(nil) end
    Buy.active = nil
    Buy.pick = kind
    -- eine gezeigte Schnäppchen- bzw. Beobachtet-Ansicht gehört nicht mehr zur Auswahl (wie Buy.Select)
    local shown = ns.Search.shown
    if shown and (shown.kind == "bargain" or shown.kind == "watch") and shown.kind ~= kind then ns.Search.shown = nil end
    ns.ShowBrowseResults()
    Buy.ResetBlizzardCategory()
    if ns.Editor then ns.Editor.Update() end
    Buy.UpdateSearchButton()
    Buy.Refresh()
    return true
end

-- „Suchen“ bzw. Enter mit eigener Auswahl: die gewählte Liste, Schnäppchen oder Beobachtet. → wie die Suche selbst
function Buy.SearchSelected()
    if Buy.active then return Buy.StartList(Buy.active) end
    if Buy.pick == "lists" then return Buy.StartAll() end
    if Buy.pick == "bargain" then return Buy.ShowBargains() end
    if Buy.pick == "watch" then return Buy.ShowWatched() end
    return false
end

-- Blizzard hat eine Kategorie gewählt (Klick des Spielers): die Liste ist abgewählt, Schnäppchen und Beobachtet auch.
function Buy.OnCategorySelected(index)
    if resetting or index == nil then return end
    local shown = ns.Search.shown
    if shown and (shown.kind == "bargain" or shown.kind == "watch") then ns.Search.shown = nil end
    if Buy.active or Buy.pick then Buy.Select(nil) else Buy.Refresh() end
end

-- Blizzards Suche ging los (Suchfeld mit Eingabetaste, Favoriten): mit gewählter Liste und leerem Suchfeld sucht
-- ezAuction danach die Liste. Blizzards breite Abfrage ist dann schon unterwegs; die Listensuche startet nach ihrer
-- Antwort (Search.AfterBlizzardAnswer – sonst zählte sie für den ersten Eintrag) als Klick-Auftrag ohne Haltezeit
-- und ersetzt Blizzards Ergebnis. Mit Suchtext oder bei den Favoriten ist die Liste abgewählt. kind: nil oder "favorites".
function Buy.OnBlizzardSearch(searchString, kind)
    if not (Buy.active or Buy.pick) then return end
    if kind == nil and (searchString == nil or Core.Trim(tostring(searchString)) == "") then
        local list, pick = Buy.active, Buy.pick
        ns.Search.AfterBlizzardAnswer(function()
            if Buy.active == list and Buy.pick == pick and ns.AuctionHouseShown() then Buy.SearchSelected() end
        end)
    else
        Buy.Select(nil)
    end
end

-- Eigener Knopf „Suchen“ genau über Blizzards Knopf, solange eine Liste gewählt ist: Blizzards Knopf würde alles suchen
-- (seine Abfrage kennt keine Liste); ezAuction sucht die Einträge mit Blizzards Filter. Gleiches Aussehen.
local searchButton
local function BuildSearchButton()
    local bar = AuctionHouseFrame.SearchBar
    local blizzard = bar and bar.SearchButton
    if searchButton or type(blizzard) ~= "table" or type(blizzard.GetFrameLevel) ~= "function" then return end
    searchButton = CreateFrame("Button", "ezAuctionListSearchButton", bar, "UIPanelButtonTemplate")
    searchButton:SetAllPoints(blizzard)
    searchButton:SetFrameLevel((blizzard:GetFrameLevel() or 1) + 5)
    searchButton:SetText(blizzard.GetText and blizzard:GetText() or rawget(_G, "SEARCH") or L.EDITOR_SEARCH)
    searchButton:SetScript("OnClick", function()
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Buy.SearchSelected()
    end)
    searchButton:SetScript("OnEnter", function(self)
        local tip = Buy.active and L.LIST_SEARCH_BUTTON_TIP:format(Buy.active.name)
            or (Buy.pick == "lists" and L.LISTS_SEARCH_TIP)
            or (Buy.pick == "bargain" and L.BARGAIN_SEARCH_TIP) or (Buy.pick == "watch" and L.WATCH_SEARCH_TIP) or ""
        Core.ShowTip(self, self:GetText() or L.EDITOR_SEARCH, tip)
    end)
    searchButton:SetScript("OnLeave", GameTooltip_Hide)
    searchButton:Hide()
    -- Text ins Suchfeld getippt: die Liste ist abgewählt, Blizzards Knopf sucht wieder selbst
    local box = bar.SearchBox
    if box and box.HookScript then
        box:HookScript("OnTextChanged", function(self, user)
            if user and (Buy.active or Buy.pick) and Core.Trim(self:GetText() or "") ~= "" then Buy.Select(nil) end
        end)
    end
end

function Buy.UpdateSearchButton()
    if not searchButton then return end
    local own = ((Buy.active ~= nil or Buy.pick == "lists") and ns.Enabled("shoppingLists"))
        or (Buy.pick == "bargain" and ns.Enabled("bargainList"))
        or (Buy.pick == "watch" and ns.Enabled("watchList"))
    searchButton:SetShown((own and ns.AuctionHouseShown() and ns.ModeName() == "buy") == true)
end

-- Eigener Knopf „Suchen“, solange zu sehen (für Prüfungen und den Rundgang).
function Buy.SearchButton()
    return searchButton ~= nil and searchButton:IsVisible() and searchButton or nil
end

-- Knopf „Zurücksetzen“ (Wunsch des Nutzers vom 21.11.2026: „zurücksetzen button der aktuellen suche beim kaufen reiter“;
-- Entscheidung „Everything, like Blizzard (Recommended)“): zurück zum Zustand nach dem Öffnen – Suchtext, eigene Auswahl
-- (Einkaufsliste, Schnäppchen, Beobachtet) und eigene Suche; außerhalb des Kampfes auch Blizzards Kategorie und Filter
-- über Blizzards eigene Funktionen (CategoriesList:SetSelectedCategory(nil) wie der Favoriten-Knopf,
-- FilterButton:Reset() wie Blizzards X am Filterknopf; Shared/Blizzard_AuctionHouseSearchBar.lua, Zweig forever) –
-- die zweite Ausnahme von Leitlinie 5 in ezAuction. Blizzards zuletzt gezeigte Ergebnisse bleiben stehen (es gibt keine
-- Abfrage „nichts“). → true, wenn Blizzards Kategorie bzw. Filter dabei zurückgesetzt werden durften und es ging
function Buy.ResetSearch()
    local Search = ns.Search
    -- schon eingereihte eigene Sendungen (Search.Item, Search.Replay) prüfen Search.shown und entfallen mit ClearShown
    if Search.running then Search.Cancel(true) end
    if Search.CancelAfterAnswer then Search.CancelAfterAnswer() end
    Search.ClearShown()
    -- eigene Kategorien wie nach dem Öffnen: nichts gewählt, „Einkaufslisten“ zugeklappt (Spieltest vom 21.11.2026:
    -- „zürcksetzen muss auch unsere kaegorien schließen und abwählen“)
    ns.db.ui.listsCollapsed = true
    Buy.Select(nil)
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    local box = bar and bar.SearchBox
    if type(box) == "table" then
        if type(box.Reset) == "function" then pcall(box.Reset, box) elseif box.SetText then box:SetText("") end
        if box.ClearFocus then box:ClearFocus() end
    end
    local blizzard = not Buy.noCategoryReset and not (InCombatLockdown and InCombatLockdown())
    local done = false
    if blizzard then
        if Buy.ResetBlizzardCategory() then done = true end
        local filter = bar and bar.FilterButton
        if type(filter) == "table" and type(filter.Reset) == "function" and pcall(filter.Reset, filter) then done = true end
    end
    Buy.Refresh()
    return done
end

local resetButton
local function BuildResetButton()
    local bar = AuctionHouseFrame.SearchBar
    local after = _G.ezAuctionRecentButton or (bar and bar.SearchBox)
    if resetButton or type(bar) ~= "table" or type(after) ~= "table" then return end
    local R = ns.Layout.RESET
    resetButton = CreateFrame("Button", "ezAuctionResetSearch", bar)
    resetButton:SetSize(R.size, R.size)
    resetButton.icon = resetButton:CreateTexture(nil, "ARTWORK")
    resetButton.icon:SetAllPoints()
    Core.SetIcon(resetButton.icon, R.atlas, R.file)
    resetButton:SetHighlightTexture(R.file, "ADD")
    local highlight = resetButton:GetHighlightTexture()
    if highlight and highlight.SetAlpha then highlight:SetAlpha(0.4) end
    resetButton:SetPoint("LEFT", after, "RIGHT", R.gap, 0)
    resetButton:SetScript("OnClick", function()
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Buy.ResetSearch()
    end)
    resetButton:SetScript("OnEnter", function(self) Core.ShowTip(self, L.SEARCH_RESET, L.SEARCH_RESET_TIP) end)
    resetButton:SetScript("OnLeave", GameTooltip_Hide)
end
function Buy.ResetButton() return resetButton end

ns.OnAuctionHouse(function()
    BuildSearchButton()
    BuildResetButton()
    local categories = Categories()
    if categories and categories.SetSelectedCategory then
        hooksecurefunc(categories, "SetSelectedCategory", function(_, index) ns.Try("CategorySelected", Buy.OnCategorySelected, index) end)
    end
end)
ns.Listen("AH_MODE", function() Buy.UpdateSearchButton() end)
ns.Listen("AH_HIDE", function()
    Buy.active, Buy.pick = nil, nil
    Buy.UpdateSearchButton()
end)

-- Kopfzeile „Einkaufslisten“, solange sie zu sehen ist (Ziel des Rundgangs).
function Buy.HeaderButton()
    local button = buttons[1]
    if not (holder and holder:IsVisible() and button and button.ezRow and button.ezRow.kind == "header") then return nil end
    return button
end

-- Knopf der Zeile dieser Art („bargain“, „watch“ …), solange zu sehen; sonst nil (für Prüfungen).
function Buy.RowButton(kind)
    if not (holder and holder:IsVisible()) then return nil end
    for _, button in ipairs(buttons) do
        if button:IsShown() and button.ezRow and button.ezRow.kind == kind then return button end
    end
    return nil
end

---------------------------------------------------------------------------
-- Einbau in Blizzards Kategorienliste
---------------------------------------------------------------------------

-- Blizzards Liste rückt unter die Einkaufslisten (nur ihre Anker; gemerkt, damit „aus“ sie zurücksetzt).
function Buy.Attach()
    local categories = Categories()
    local box = categories and categories.ScrollBox
    if not (box and box.GetNumPoints) then return end
    if not scrollPoints then
        scrollPoints = {}
        for index = 1, box:GetNumPoints() do scrollPoints[index] = { box:GetPoint(index) } end
    end
    local x, y, right = 3, -6, -25
    for _, point in ipairs(scrollPoints) do
        if point[1] == "TOPLEFT" then x, y = point[4] or x, point[5] or y end
        if point[1] == "BOTTOMRIGHT" or point[1] == "TOPRIGHT" or point[1] == "RIGHT" then right = point[4] or right end
    end
    if not holder then
        holder = CreateFrame("Frame", nil, categories)
        Buy.holder = holder
    end
    holder:ClearAllPoints()
    -- Zeilen wie Blizzards Kategorien: deren Liste rückt die Knöpfe 3 nach rechts (Shared/
    -- Blizzard_AuctionHouseCategoriesList.lua: view:SetPadding(0, 0, leftPad = 3, 0, 0)) und reicht bis zur rechten Kante
    -- ihrer ScrollBox (Spielbefund vom 21.11.2026: „zentrieren wie die anderen“ – vorher 3 weiter links, rechts 25 frei)
    holder:SetPoint("TOPLEFT", categories, "TOPLEFT", x + Buy.LEFT_PAD, y)
    holder:SetPoint("RIGHT", categories, "RIGHT", right, 0)
    holder:SetHeight(ROW_HEIGHT)
    -- Abstand und Trennlinie zu Blizzards Kategorien („die eigenen etwas abgrenzen“, 21.11.2026)
    if not holder.rule then
        local rule = holder:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        local r, g, b = Core.Style.Color("normal")
        rule:SetColorTexture(r or 1, g or 0.82, b or 0, 0.4)   -- Blizzards Gold, halb durchsichtig
        holder.rule = rule
    end
    holder.rule:ClearAllPoints()
    holder.rule:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", 4, -(Buy.SEPARATOR / 2))
    holder.rule:SetPoint("TOPRIGHT", holder, "BOTTOMRIGHT", -4, -(Buy.SEPARATOR / 2))
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", holder, "BOTTOMLEFT", -Buy.LEFT_PAD, -Buy.SEPARATOR)
    for _, point in ipairs(scrollPoints) do
        if point[1] ~= "TOPLEFT" and point[1] ~= "TOP" and point[1] ~= "TOPRIGHT" then box:SetPoint(unpack(point)) end
    end
    Buy.attached = true
    Buy.Refresh()
end

function Buy.Detach()
    local categories = Categories()
    local box = categories and categories.ScrollBox
    if holder then holder:Hide() end
    if not (box and scrollPoints and Buy.attached) then return end
    box:ClearAllPoints()
    for _, point in ipairs(scrollPoints) do box:SetPoint(unpack(point)) end
    Buy.attached = false
end

-- Steht über der Kategorienliste überhaupt ein Eintrag (Einkaufslisten, Schnäppchen, Beobachtet)?
function Buy.WantsHolder()
    return ns.Enabled("shoppingLists") or ns.Enabled("bargainList") or ns.Enabled("watchList")
end

function Buy.Apply()
    if not ns.ahReady then return end
    if Buy.WantsHolder() then Buy.Attach() else Buy.Detach() end
end

---------------------------------------------------------------------------
-- Blizzards Ergebnisliste: „< Händler“, Abstand zum Marktwert, Schnäppchen
---------------------------------------------------------------------------

-- Beschriftung einer Ergebniszeile: text, r, g, b, hervorheben? (nil, wenn nichts zu sagen ist)
function Buy.BrowseLabel(data)
    if type(data) ~= "table" or type(data.itemKey) ~= "table" or type(data.minPrice) ~= "number" then return nil end
    local price, itemID = data.minPrice, data.itemKey.itemID
    local vendor = Core.VendorPrice(itemID)
    if ns.Enabled("vendorMark") and vendor and vendor > 0 and price < vendor then
        return L.BELOW_VENDOR, 0.1, 1, 0.1, true, L.BELOW_VENDOR_TIP:format(ns.Money(vendor))
    end
    if not ns.Enabled("marketCompare") then return nil end
    -- Ab fünf erfassten Tagen gilt der Median der Tages-Tiefstpreise als Bezug (AUC-04, VP-72, Folge von W-53):
    -- die eine Bewertung aus Market.lua, mit Begründung und Quelle samt Alter der letzten Erfassung; vorher (und bei
    -- Abwandlungen, deren Median verschiedene Preise mischt) wie bisher der Marktwert.
    local Market = ns.Market
    local judgement = Market and Market.Judge(itemID, price, Market.HasVariant(data.itemKey))
    if judgement then
        local percent = judgement.percent
        local tip = Market.JudgeText(judgement)
        local source = Market.SourceLine(judgement.stats, itemID)
        if source then tip = tip .. "\n" .. source end
        if judgement.verdict == "cheap" then return L.MARKET_BELOW:format(-percent), 1, 0.82, 0, true, tip end
        if percent < 0 then return L.MARKET_BELOW:format(-percent), 0.6, 1, 0.6, false, tip end
        if percent > 0 then return L.MARKET_ABOVE:format(percent), 0.6, 0.6, 0.6, false, tip end
        return nil
    end
    local info = ns.PriceInfo(itemID)
    local market = info and info.market
    if not market or market <= 0 then return nil end
    local percent = Core.Round((price - market) / market * 100)
    local money = ns.Money(market)
    -- Jede Angabe nennt ihre Quelle: der Marktwert stammt aus den selbst erfassten Preisen (mit Alter).
    local source = ns.Scan and ns.Scan.SourceText(info)
    local function Tip(text) return source and (text .. "\n" .. source) or text end
    if percent <= -(ns.S.bargainPercent or 20) then
        return L.MARKET_BELOW:format(-percent), 1, 0.82, 0, true, Tip(L.MARKET_BARGAIN_TIP:format(-percent, money))
    end
    if percent < 0 then return L.MARKET_BELOW:format(-percent), 0.6, 1, 0.6, false, Tip(L.MARKET_BELOW_TIP:format(-percent, money)) end
    if percent > 0 then return L.MARKET_ABOVE:format(percent), 0.6, 0.6, 0.6, false, Tip(L.MARKET_ABOVE_TIP:format(percent, money)) end
    return nil
end

-- Menge, die die gerade gesuchte Einkaufsliste von diesem Gegenstand braucht (Eintrag mit itemID und Menge,
-- z. B. aus ezCraft „fehlt noch n“); nil ohne Liste oder Menge (Vollprüfung V-161). Dritte Rückgabe: der Eintrag.
function Buy.Wanted(data)
    -- „alle Listen“: die Sammel-Liste frisch (eine Liste kann sich seit der Suche geändert haben; Befund des Reviews)
    local list = Buy.active or (Buy.pick == "lists" and Buy.AllLists()) or nil
    local itemID = type(data) == "table" and type(data.itemKey) == "table" and data.itemKey.itemID
    if not (list and itemID) then return nil end
    -- hergestellte Gegenstände zählen mit ihrem fehlenden Material (ns.Lists.SearchEntries)
    for _, entry in ipairs(ns.Lists.SearchEntries(list)) do
        if entry.itemID == itemID and entry.count then return entry.count, list, entry end
    end
    return nil
end

-- Eintrag einer Einkaufsliste zu einer Ergebniszeile: der Eintrag, der den Treffer in der gezeigten Liste gefunden
-- hat (Search.EntryFor), sonst ein Eintrag der gewählten Liste mit derselben itemID. Rückgabe: Eintrag, Liste.
function Buy.EntryFor(data)
    local key = type(data) == "table" and data.itemKey
    if type(key) ~= "table" then return nil end
    local entry, list = ns.Search.EntryFor(key)
    if entry then return entry, list end
    list = Buy.active
    for _, other in ipairs(list and list.items or {}) do
        if other.itemID and other.itemID == key.itemID then return other, list end
    end
    return nil
end

-- Höchstpreis eines Eintrags überschritten (AH-09)? Rückgabe: Zeile für den Tooltip (Grenze und Quelle) oder nil.
-- Filter und Höchstpreis wirken seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 11) immer – kein Schalter mehr.
function Buy.OverMaxPrice(data)
    if type(data) ~= "table" then return nil end
    local price = Core.Num(data.minPrice)
    local entry, list = Buy.EntryFor(data)
    local limit = entry and Core.Num(entry.maxPrice)
    if not (price and limit and list) or price <= limit then return nil end
    return L.MAX_PRICE_OVER_TIP:format(ns.Money(limit), list.name, ns.Lists.EntryLabel(entry))
end

-- Wo der größte Teil des Bestands liegt (Lists.StockOf: Taschen, Bank, Post, angelegt), mit dem Namen des
-- Charakters: „, davon 32 auf der Bank von …“; nil ohne Bestand bei Charakteren.
function Buy.PlaceText(info)
    local part = type(info) == "table" and info.part
    local place = part and info.place
    if not (part and place) then return nil end
    local where = part.isMe and L["STOCK_PLACE_" .. place .. "_ME"] or L["STOCK_PLACE_" .. place]:format(Core.CharName(part.c, part.key))
    return L.STOCK_MOST:format(info.most, where)
end

-- Bestand zum Gegenstand einer Ergebniszeile (Lists.StockOf); nil ohne Zählung. Immer an seit der
-- Einstellungs-Prüfung vom 19.11.2026 (Nr. 12).
local function StockInfo(data)
    local itemID = type(data) == "table" and type(data.itemKey) == "table" and Core.Num(data.itemKey.itemID)
    return itemID and ns.Lists.StockOf(itemID) or nil
end

-- Warnung vor Doppelkauf, wenn der Bestand die Menge des Eintrags einer eigenen Liste deckt (Lists.Covers); sonst nil.
-- Gerechnet wird mit dem erreichbaren Teil (Lists.Reach; Gesamtreview 18.11.2026, T4-NR5): Bestand eines Twinks der
-- anderen Fraktion, eines nicht erreichbaren Realms, Angelegtes und fremde Gildenbanken verhindern keinen Kauf.
local function DoubleWarn(info, entry, list)
    local have = math.min(info.chars + info.guilds, ns.Lists.Reach(info) or (info.chars + info.guilds))
    local covered, need = ns.Lists.Covers(entry, list, have)
    if not covered then return nil end
    return Buy.DoubleWarnText(list.name, have, need)
end

-- Wortlaut der Warnung: „Achtung:“ in Blizzards Orange (ns.Orange; Design-System 2.5 – die Farbe steht im Code, nicht
-- im Text der Übersetzung), dahinter der Satz.
function Buy.DoubleWarnText(name, have, need)
    return ns.Orange(L.STOCK_DOUBLE_HEAD) .. " " .. L.STOCK_DOUBLE_WARN:format(name, have, need)
end

-- Bestand aller Charaktere zu einer Ergebniszeile (AH-11): „Du hast 40 (alle Charaktere), davon 32 auf der Bank
-- von …“; dazu die Warnung vor Doppelkauf. Für Zeilen ohne Eintrag der aktiven Liste – die nennt den Bestand schon in
-- ihrer Zeile „Bestand: …“ (Buy.MarkBrowseRow). nil ohne Bestand oder ohne ezCores Zählung.
function Buy.StockLine(data, entry, list)
    local info = StockInfo(data)
    if not info or info.chars + info.guilds <= 0 then return nil end
    local line = L.STOCK_HAVE:format(info.chars) .. (Buy.PlaceText(info) or "")
    if info.guilds > 0 then line = line .. L.LIST_STOCK_GUILD:format(info.guilds) end
    local warn = DoubleWarn(info, entry, list)
    if warn then line = line .. "\n" .. warn end
    return line
end

function Buy.MarkBrowseRow(_, data, overlay)
    local text, r, g, b, highlight, tip = Buy.BrowseLabel(data)
    local wanted, list, entry = Buy.Wanted(data)
    local stockShown = false
    if wanted then
        local line = L.LIST_NEED_TIP:format(list.name, wanted)
        -- Eigene Listen: dazu der Bestand aller Charaktere („brauche 12, hast 4 …“) – nur hier im Tooltip. Mit
        -- dem Bestand (AH-11) steht der Ort in derselben Zeile, und statt „genug da“ folgt die Warnung vor
        -- Doppelkauf: Gesamtzahl und „genug“ also nur einmal.
        local info = StockInfo(data)
        local warn = info and DoubleWarn(info, entry, list)
        local stock = ns.Lists.StockText(entry, list, info and { info = info, place = Buy.PlaceText(info), warned = warn ~= nil })
        if stock then
            line = line .. "\n" .. L.LIST_STOCK_LABEL:format(stock)
            if warn then line = line .. "\n" .. warn end
            stockShown = info ~= nil
        end
        tip = tip and (tip .. "\n" .. line) or line
        -- Ohne andere Markierung steht die Menge selbst in der Zeile („12×“).
        if not text then text, r, g, b = L.EDITOR_COUNT:format(wanted), 1, 1, 1 end
    end
    -- Höchstpreis des Eintrags überschritten (AH-09): die Marke geht vor, die Erklärung steht oben im Tooltip
    local over = Buy.OverMaxPrice(data)
    if over then
        text, r, g, b, highlight = L.MAX_PRICE_OVER, 1, 0.35, 0.35, false
        tip = tip and (over .. "\n" .. tip) or over
    end
    -- Beobachtet (AH-23): Zielpreis im Tooltip; erreicht die Zeile ihn, steht „Ziel“ in der Zeile (Höchstpreis geht vor)
    local watched = ns.Enabled("watchList") and type(data) == "table" and ns.Watch.Of(data.itemKey)
    if watched then
        local price = Core.Num(data.minPrice)
        local line = L.WATCH_ROW_TIP:format(ns.Watch.TargetText(watched, price))
        tip = tip and (line .. "\n" .. tip) or line
        local target = Core.Num(watched.target)
        if target and price and price <= target and not over then
            text, r, g, b, highlight = L.WATCH_LABEL, 1, 0.82, 0, true
        end
    end
    -- Schnäppchen-Liste (AH-22): Begründung, Zahl der Tage und Quelle oben im Tooltip
    if ShownKind() == "bargain" then
        local hit = Buy.Bargain.HitFor(data)
        if hit then
            local line = Buy.Bargain.Text(hit)
            tip = tip and (line .. "\n" .. tip) or line
        end
    end
    -- Verfügbarkeit (AUC-03) nur im Tooltip der Zeile, nur wenn die Zeile ohnehin etwas erklärt und genug Tage da sind
    if tip and ns.Market then
        local itemID = type(data) == "table" and type(data.itemKey) == "table" and data.itemKey.itemID
        local lines = itemID and ns.Market.Availability(itemID, nil, data.totalQuantity, true) or {}
        if #lines > 0 then tip = tip .. "\n" .. table.concat(lines, "\n") end
    end
    -- Pfeil „besser“ aus ezGear und Filter „Nur Verbesserungen“ (Upgrade.lua)
    local upgrade = ns.Upgrade and ns.Upgrade.Mark(overlay, data)
    if upgrade then tip = tip and (tip .. "\n" .. upgrade) or upgrade end
    -- Bestand aller Charaktere und Warnung vor Doppelkauf (AH-11), wenn ihn nicht schon die Zeile „Bestand: …“ nennt
    if not stockShown then
        local stockEntry, stockList = entry, list
        if not stockEntry then stockEntry, stockList = Buy.EntryFor(data) end
        local stock = Buy.StockLine(data, stockEntry, stockList)
        if stock then tip = tip and (tip .. "\n" .. stock) or stock end
    end
    overlay:SetLabel(text, r, g, b)
    overlay:SetTip(tip, r, g, b)
    if highlight then overlay:SetTint(0.2, 1, 0.2) else overlay:SetTint(nil) end
end

---------------------------------------------------------------------------
-- Einzelstück-Liste (AuctionHouseFrame.ItemBuyFrame.ItemList, AH-12): Stückpreis in der Überlagerung der Zeile, wenn
-- eine Auktion mehrere Stück enthält; im Tooltip der Zeile der Verkäufer, soweit das Suchergebnis ihn nennt (aus dem
-- Komplett-Scan kommt er leer – dann keine Zeile). Blizzards Tabellenaufbau bleibt, wie er ist: keine eigene Spalte.
---------------------------------------------------------------------------

-- Verkäufer aus Blizzards Suchergebnis (owners, totalNumberOfOwners): Text oder nil.
function Buy.SellerText(data)
    local owners = type(data) == "table" and data.owners
    if type(owners) ~= "table" then return nil end
    local first = owners[1]
    if type(first) ~= "string" or Core.IsSecret(first) or Core.Trim(first) == "" then return nil end
    local others = (Core.Num(data.totalNumberOfOwners) or #owners) - 1
    -- „… und n weitere“ aus ezCore (Core.More mit Einzahl „und noch 1“; Welle 23), hier nur der Rahmen „Verkäufer:“
    if others > 0 then return L.SELLER_MANY:format(first, ezCore.More(others, true)) end
    return L.SELLER_ONE:format(first)
end

function Buy.MarkItemRow(_, data, overlay)
    local text, lines = nil, {}
    -- Stückpreis und Verkäufer immer (Einstellungs-Prüfung vom 19.11.2026, Nr. 13)
    if type(data) == "table" then
        local quantity, buyout = Core.Num(data.quantity), Core.Num(data.buyoutAmount)
        if quantity and quantity > 1 and buyout and buyout > 0 then
            local unit = math.floor(buyout / quantity)
            text = L.UNIT_PRICE_LABEL:format(ns.Money(unit))
            lines[#lines + 1] = L.UNIT_PRICE_TIP:format(ns.Money(unit), ns.Money(buyout), quantity)
        end
        local seller = Buy.SellerText(data)
        if seller then lines[#lines + 1] = seller end
    end
    -- AH-24: die günstigste fremde Auktion je Stück golden hinterlegt (nach einem Kauf also die nächstgünstige)
    local best = ns.Enabled("buyNextMark") and type(data) == "table" and data.auctionID ~= nil
        and Buy.CheapestAuction(data.itemKey) == data.auctionID
    if best then lines[#lines + 1] = L.NEXT_ROW_TIP end
    overlay:SetTint(best and 1 or nil, 0.82, 0)
    overlay:SetLabel(text, 1, 1, 1)
    overlay:SetTip(#lines > 0 and table.concat(lines, "\n") or nil, 1, 0.82, 0)
end

---------------------------------------------------------------------------
-- „Ergebnisse als Text“ im Zahnrad-Menü (AH-12): Name, Tiefstpreis und Menge der gezeigten Ergebnisse in ezCores
-- Text-Dialog, zum Kopieren (Addons können keine Dateien schreiben).
---------------------------------------------------------------------------

-- Zeilen „Name; Preis; Menge“ (erste Zeile: Überschrift); leer ohne Ergebnis.
function Buy.ResultLines()
    local api = C_AuctionHouse
    local results = api and api.GetBrowseResults and Core.Call(api.GetBrowseResults)
    local lines = {}
    for _, result in ipairs(type(results) == "table" and results or {}) do
        local key = type(result) == "table" and result.itemKey
        if type(key) == "table" then
            local info = api.GetItemKeyInfo and Core.Call(api.GetItemKeyInfo, key)
            local name = type(info) == "table" and type(info.itemName) == "string" and info.itemName
                or Core.ItemNameByID(key.itemID) or ("#" .. tostring(key.itemID))
            lines[#lines + 1] = L.RESULTS_LINE:format(name, Core.PlainMoney(Core.Num(result.minPrice) or 0),
                tostring(Core.Num(result.totalQuantity) or "?"))
        end
    end
    if #lines > 0 then table.insert(lines, 1, L.RESULTS_HEADER) end
    return lines
end

-- Rückgabe: der Text oder nil (dann steht der Grund im Chat).
function Buy.ShowResultsText()
    local lines = Buy.ResultLines()
    if #lines == 0 then
        ns.Print(L.RESULTS_NONE)
        return nil
    end
    local text = table.concat(lines, "\n")
    if type(Core.TextDialog) ~= "function" then
        ns.Print(L.LIST_EXPORT_FAIL)
        return nil
    end
    Core.TextDialog({ title = L.RESULTS_TITLE:format(#lines - 1), hint = L.RESULTS_HINT, text = text, select = true,
        anchor = AuctionHouseFrame, owner = "ezAuction" })
    return text
end

---------------------------------------------------------------------------
-- Schnäppchen (AH-22, Welle 14): nach einer Erfassung alles unter Händlerpreis und alles, was die eine Bewertung aus
-- AUC-04 (Market.Judge: Median der Tages-Tiefstpreise ab fünf erfassten Tagen, Schwellen-Schalter bargainPercent)
-- als günstig einstuft – dieselbe Funktion wie die Markierung „−23 %“ oben, keine eigene Schwelle.
-- Woher die Treffer kommen: aus jeder Antwort der Übersicht (Suchen, Kategorien, „Meine Preise“, Listen) und nach
-- jeder Erfassung aus den beobachteten Gegenständen (Prices.WatchList), danach aus allen übrigen Preisen von heute
-- (Prices.Today, seit Welle 23 – so zählt auch der ganze Komplett-Scan). Ein Treffer gilt für sein Auktionshaus und den
-- Tag seiner Erfassung.
---------------------------------------------------------------------------

local Bargain = { hits = {} }    -- [ns.KeyString(itemKey)] = { kind, itemKey, itemID, price, vendor | judgement, gain, seen, house }
Buy.Bargain = Bargain
Bargain.MAX = 40          -- so viele zeigt ein Klick (Blizzards Sammelsuche; laut Probe X6 mit 40 Schlüsseln belegt)
Bargain.ROWS = 100        -- so viele Zeilen prüft ein Takt höchstens, der Rest folgt in den nächsten Takten (je Zeile
                          -- rechnet ezCore Prices.Stats samt Protokoll – bei Kategorie-Durchläufen kommen viele Seiten)
Bargain.pos = { browse = 0, watched = 0, today = 0 }   -- so weit ist die Prüfung der Antwort, des Beobachteten
                                                       -- bzw. der übrigen Preise von heute gekommen
Bargain.later = {}        -- [Art] = nächster Takt (unten bei den Ereignissen gesetzt: browse alle 0,5 s, watched jede s)
-- Beobachtetes zuerst aus diesen Anbietern (vom Spieler gewählt), dann der Rest (Taschen, eigene Auktionen …)
Bargain.FIRST = { ["ezAuction.favorites"] = true, ["ezAuction.lists"] = true }
Bargain.LIST_TIP = 5      -- so viele Treffer nennt der Tooltip des Eintrags

local function House()
    local prices = ns.Prices()
    return prices and type(prices.Key) == "function" and Core.Call(prices.Key) or "?"
end

local function Today(seen)
    seen = Core.Num(seen)
    if not seen then return false end
    local prices = ns.Prices()
    if prices and type(prices.Day) == "function" then return Core.Call(prices.Day, seen) == Core.Call(prices.Day) end
    return time() - seen < 86400
end

-- Die Bewertung einer Zeile: { kind = "vendor", vendor, price, gain } | { kind = "cheap", judgement, price, gain } | nil.
-- Unter Händlerpreis geht vor (sicherer Gewinn); „günstig“ nur über Market.Judge (Schalter marketHint wie überall).
function Bargain.Assess(itemKey, price)
    local itemID = type(itemKey) == "table" and Core.Num(itemKey.itemID)
    price = Core.Num(price)
    if not (itemID and price and price > 0) then return nil end
    local vendor = Core.VendorPrice(itemID)
    if vendor and vendor > 0 and price < vendor then
        return { kind = "vendor", vendor = vendor, price = price, gain = vendor - price }
    end
    local Market = ns.Market
    local judgement = Market and Market.Judge(itemID, price, Market.HasVariant(itemKey))
    if judgement and judgement.verdict == "cheap" then
        return { kind = "cheap", judgement = judgement, price = price, gain = judgement.median - price }
    end
    return nil
end

-- Eine Zeile mit Tiefstpreis übernehmen: Treffer merken bzw. einen alten vergessen, der nicht mehr günstig ist.
function Bargain.Learn(itemKey, price, seen)
    if type(itemKey) ~= "table" or Core.IsSecret(itemKey) then return nil end
    local key = ns.KeyString(itemKey)
    local hit = Bargain.Assess(itemKey, price)
    if hit then
        hit.itemKey = { itemID = itemKey.itemID, itemLevel = itemKey.itemLevel or 0, itemSuffix = itemKey.itemSuffix or 0,
            battlePetSpeciesID = itemKey.battlePetSpeciesID or 0 }
        hit.itemID, hit.seen, hit.house = itemKey.itemID, Core.Num(seen) or time(), House()
    end
    Bargain.hits[key] = hit
    return hit
end

-- Treffer dieses Auktionshauses von heute, die besten zuerst: unter Händlerpreis nach Gewinn je Stück, dann günstig
-- nach dem Abstand zum Median. Veraltete fallen dabei weg.
function Bargain.List()
    local house, out = House(), {}
    for key, hit in pairs(Bargain.hits) do
        if hit.house == house and Today(hit.seen) then out[#out + 1] = hit else Bargain.hits[key] = nil end
    end
    table.sort(out, function(a, b)
        if a.kind ~= b.kind then return a.kind == "vendor" end
        if a.kind == "vendor" then
            if a.gain ~= b.gain then return a.gain > b.gain end
        elseif a.judgement.percent ~= b.judgement.percent then
            return a.judgement.percent < b.judgement.percent
        end
        return ns.KeyString(a.itemKey) < ns.KeyString(b.itemKey)
    end)
    return out
end

function Bargain.Count() return #Bargain.List() end

-- Treffer zu einer Ergebniszeile (genau ihr Schlüssel); nil sonst.
function Bargain.HitFor(data)
    local key = type(data) == "table" and type(data.itemKey) == "table" and ns.KeyString(data.itemKey)
    return key and Bargain.hits[key] or nil
end

local function ItemName(hit)
    return Core.ItemNameByID(hit.itemID) or ("#" .. tostring(hit.itemID))
end

-- Begründung mit Zahl der Tage und Quelle (Tooltip der Zeile in der Schnäppchen-Liste).
function Bargain.Text(hit)
    if type(hit) ~= "table" then return nil end
    local info = ns.PriceInfo(hit.itemKey)
    local source = ns.Scan and ns.Scan.SourceText(info) or nil
    if hit.kind == "vendor" then
        local line = L.BARGAIN_VENDOR_TIP:format(ns.Money(hit.price), ns.Money(hit.vendor), ns.Money(hit.gain))
        return line .. "\n" .. L.BARGAIN_VENDOR_SOURCE .. (source and ("\n" .. source) or "")
    end
    local j = hit.judgement
    local line = L.BARGAIN_CHEAP_TIP:format(Core.Percent(math.abs(j.percent)),
        Core.Plural(j.days, L.MARKET_DAYS_ONE, L.MARKET_DAYS_MANY), ns.Money(j.median))
    local market = ns.Market and ns.Market.SourceLine(j.stats, hit.itemID)
    return line .. (market and ("\n" .. market) or "")
end

-- Antwort der Übersicht: jede Zeile mit Tiefstpreis prüfen, je Takt höchstens Bargain.ROWS, dann ab der nächsten Zeile
-- weiter (Bargain.later.browse). fresh: eine neue Antwort, von vorn (AUCTION_HOUSE_BROWSE_RESULTS_UPDATED); sonst
-- weiter, wo der letzte Takt aufgehört hat (weitere Seiten über AUCTION_HOUSE_BROWSE_RESULTS_ADDED hängen hinten an).
function Bargain.FromBrowse(fresh)
    if not ns.Enabled("bargainList") then return 0 end
    local api = C_AuctionHouse
    local results = api and api.GetBrowseResults and Core.Call(api.GetBrowseResults)
    results = type(results) == "table" and results or {}
    local index = (not fresh and Bargain.pos.browse) or 0
    if index > #results then index = 0 end    -- kürzer als bisher geprüft: eine andere Antwort
    local count = 0
    while index < #results and count < Bargain.ROWS do
        index = index + 1
        local result = results[index]
        if type(result) == "table" and Core.Num(result.minPrice) then
            Bargain.Learn(result.itemKey, result.minPrice)
            count = count + 1
        end
    end
    Bargain.pos.browse = index
    Buy.Refresh()
    if index < #results and Bargain.later.browse then Bargain.later.browse() end
    return count
end

-- Reihenfolge des Beobachteten: Favoriten und Einkaufslisten zuerst, der Rest in ezCores Reihenfolge.
function Bargain.WatchedOrder(list)
    local first, rest = {}, {}
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if type(e) == "table" and Bargain.FIRST[e.from] then first[#first + 1] = e else rest[#rest + 1] = e end
    end
    for _, e in ipairs(rest) do first[#first + 1] = e end
    return first
end

-- Listen für Bargain.FromWatched: das Beobachtete (Favoriten und Listen zuerst, Bargain.WatchedOrder) und als zweite
-- Liste jeder übrige Gegenstand mit Preis von heute aus ezCores Aufzählung (Prices.Today, Welle 23b; Herkunft
-- „ezCore.today“) – je Gegenstand einmal. Ohne Prices.Today ist die zweite Liste leer. → watched, today
function Bargain.WatchedAndToday(prices)
    local list, today = Bargain.WatchedOrder(Core.Call(prices.WatchList)), {}
    if type(prices.Today) ~= "function" then return list, today end
    local seen = {}
    for _, e in ipairs(list) do
        local id = type(e) == "table" and (Core.Num(e.itemID) or Core.ItemID(e.item))
        if id then seen[id] = true end
    end
    Core.Call(prices.Today, function(itemID)
        itemID = Core.Num(itemID)
        if itemID and not seen[itemID] then
            seen[itemID] = true
            today[#today + 1] = { item = itemID, itemID = itemID, from = "ezCore.today" }
        end
    end)
    return list, today
end

-- einen Eintrag bewerten; true, wenn er einen Preis von heute hatte (zählt gegen Bargain.ROWS)
local function LearnWatched(prices, e)
    local info = type(e) == "table" and ns.PriceInfo(e.item)
    if not (info and Today(info.seen) and Core.Num(info.min)) then return false end
    local base, full
    if type(prices.ItemKey) == "function" then base, full = Core.Call(prices.ItemKey, e.item) end
    local itemKey = (info.variant and full) or base
    if type(itemKey) ~= "table" and Core.Num(e.itemID) then itemKey = { itemID = e.itemID, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 } end
    if type(itemKey) ~= "table" then return false end
    Bargain.Learn(itemKey, info.min, info.seen)
    return true
end

-- Nach einer Erfassung: das Beobachtete mit Preis von heute (Prices.WatchList – Einkaufslisten, Taschen, eigene
-- Auktionen, Favoriten …), danach die übrigen Preise von heute (Bargain.WatchedAndToday). Der Schlüssel kommt aus
-- ezCores Prices.ItemKey (mit Abwandlung der volle, sonst die Basis).
-- Je Takt höchstens Bargain.ROWS bewertete Einträge (ohne Preis von heute zählt keiner), dann weiter im nächsten
-- (Bargain.later.watched). fresh: die Listen neu holen und von vorn. keepToday (mit fresh): nur das Beobachtete neu,
-- die Liste „heute“ läuft an ihrer Stelle weiter – sonst erreichte nach einem Komplett-Scan mit vielen Tausend Preisen
-- kein Durchlauf ihr Ende, weil jede Suche die Warteschlange leert (PRICES_QUEUE_CHANGED, Gegenprüfung Welle 23).
-- Bargain.today: nil = nie geholt, false = durchlaufen (bis zur nächsten Erfassung bzw. zum nächsten Öffnen).
function Bargain.FromWatched(fresh, keepToday)
    local prices = ns.Prices()
    if not (ns.Enabled("bargainList") and prices and type(prices.WatchList) == "function") then return 0 end
    if (fresh and not keepToday) or Bargain.today == nil then
        Bargain.watched, Bargain.today = Bargain.WatchedAndToday(prices)
        Bargain.pos.watched, Bargain.pos.today = 0, 0
    elseif fresh or (Bargain.watched == nil and not Bargain.today) then   -- läuft „heute“ noch, bleibt das Beobachtete durch
        Bargain.watched, Bargain.pos.watched = Bargain.WatchedOrder(Core.Call(prices.WatchList)), 0
    end
    local count = 0
    local list, index = Bargain.watched or {}, Bargain.pos.watched or 0
    while index < #list and count < Bargain.ROWS do
        index = index + 1
        if LearnWatched(prices, list[index]) then count = count + 1 end
    end
    Bargain.pos.watched = index
    local watchedDone = index >= #list
    if watchedDone and Bargain.today then
        local today, at = Bargain.today, Bargain.pos.today or 0
        while at < #today and count < Bargain.ROWS do
            at = at + 1
            if LearnWatched(prices, today[at]) then count = count + 1 end
        end
        Bargain.pos.today = at
        if at >= #today then Bargain.today = false end
    end
    if watchedDone then Bargain.watched = nil end
    Buy.Refresh()
    if (Bargain.watched or Bargain.today) and Bargain.later.watched then Bargain.later.watched() end
    return count
end

-- Eigene Ansicht in Blizzards Ergebnisliste: die Gegenstände keys über Blizzards Sammelsuche (SearchForItemKeys), als
-- Auftrag der Warteschlange (Rang „modul“, Search.SendShown). Search.shown nennt die Ansicht – Sortieren per
-- Spaltenkopf und die Wiederholung nach einer Erfassung kennen sie so (Search.Resort, Capture.Restore).
local function ShowKeys(kind, keys, text)
    local api = C_AuctionHouse
    if not (api and api.SearchForItemKeys) then return false, "missing" end
    if ns.Search.running then ns.Search.Cancel(true) end
    if Buy.pick ~= kind then Buy.Pick(kind) end   -- gesucht wird nur, was gewählt ist (wie Buy.StartList)
    ns.ShowBrowseResults()
    local shown = { kind = kind, keys = keys }
    ns.Search.shown = shown
    ns.Search.SendShown(kind, text, function()
        if ns.Search.shown ~= shown or not ns.AuctionHouseShown() or ns.ModeName() == "other" then return false end
        ns.ShowBrowseResults()
        Core.Call(api.SearchForItemKeys, keys, ns.Search.Sorts())
        return true
    end)
    ns.Search.UpdateBar()
    Buy.Refresh()
    if Buy.redecorate then Buy.redecorate() end
    return true
end

-- „Suchen“ mit gewähltem „Schnäppchen (n)“ (Buy.SearchSelected). Rückgabe: true, oder false und Grund ("closed", "other", "empty", "missing").
function Buy.ShowBargains()
    if not ns.AuctionHouseShown() then return false, "closed" end
    if ns.ModeName() == "other" then return false, "other" end
    local list = Bargain.List()
    if #list == 0 then
        ns.Print(L.BARGAIN_NONE)
        return false, "empty"
    end
    local keys = {}
    for index, hit in ipairs(list) do
        if index > Bargain.MAX then break end
        keys[#keys + 1] = hit.itemKey
    end
    return ShowKeys("bargain", keys, L.QUEUE_BARGAIN)
end

function Buy.BargainTooltip()
    local list = Bargain.List()
    Core.TipTitle(GameTooltip, L.BARGAIN_TITLE)
    local rule = ns.Enabled("marketHint") and L.BARGAIN_RULE:format(ns.S.bargainPercent or 20, ns.Market and ns.Market.HINT_DAYS or 5)
        or L.BARGAIN_RULE_VENDOR
    GameTooltip:AddLine(rule, nil, nil, nil, true)
    for index, hit in ipairs(list) do
        if index > Bargain.LIST_TIP then
            Core.TipLine(GameTooltip, ezCore.More(#list - Bargain.LIST_TIP), "hint")
            break
        end
        local why = hit.kind == "vendor" and L.BARGAIN_WHY_VENDOR:format(ns.Money(hit.vendor))
            or L.BARGAIN_WHY_CHEAP:format(Core.Percent(math.abs(hit.judgement.percent)))
        Core.TipLine(GameTooltip, L.BARGAIN_LINE:format(ItemName(hit), ns.Money(hit.price), why), "normal", true)
    end
    GameTooltip:AddLine(#list > 0 and L.BARGAIN_CLICK:format(math.min(#list, Bargain.MAX)) or L.BARGAIN_EMPTY_TIP,
        nil, nil, nil, true)
    Core.TipLine(GameTooltip, L.BARGAIN_SOURCES, "hint", true)
end

---------------------------------------------------------------------------
-- Beobachtet (AH-23, Welle 14): Eintrag „Beobachtet (n)“ – der Spiegel steht in Lists.lua (ns.Watch)
---------------------------------------------------------------------------

-- „Suchen“ mit gewähltem „Beobachtet“: Blizzards eigene Favoritensuche (C_AuctionHouse.SearchForFavorites – dieselbe Abfrage wie Blizzards
-- Favoriten-Knopf; dessen StartFavoritesSearch ruft ezAuction nicht, weil es SetSelectedCategory aufruft – Welle 13).
-- Die Antwort lernt der Spiegel mit (Watch.pending), die Zeilen tragen Zielpreis und „Ziel“. Rückgabe wie oben.
function Buy.ShowWatched()
    local api = C_AuctionHouse
    if not ns.AuctionHouseShown() then return false, "closed" end
    if ns.ModeName() == "other" then return false, "other" end
    if not (api and type(api.SearchForFavorites) == "function") then return false, "missing" end
    if api.HasFavorites and Core.Call(api.HasFavorites) == false then
        ns.Print(L.WATCH_NONE)
        return false, "empty"
    end
    if ns.Search.running then ns.Search.Cancel(true) end
    if Buy.pick ~= "watch" then Buy.Pick("watch") end
    ns.ShowBrowseResults()
    local shown = { kind = "watch" }
    ns.Search.shown = shown
    ns.Search.SendShown("watch", L.QUEUE_WATCH, function()
        if ns.Search.shown ~= shown or not ns.AuctionHouseShown() or ns.ModeName() == "other" then return false end
        ns.ShowBrowseResults()
        return ns.Search.SendWatched(ns.Search.Sorts())
    end)
    ns.Search.UpdateBar()
    Buy.Refresh()
    return true
end

-- Pfeil-Kreis am Eintrag: Beobachtete ohne Preis von heute über ezCores Prices.Refresh auffrischen (Rang „modul“).
function Buy.RefreshMissing()
    local missing = ns.Watch.Missing()
    if #missing == 0 then
        ns.Print(L.WATCH_REFRESH_NONE)
        return false
    end
    local ok, count = ns.Scan.Refresh(missing, "click")
    if ok then ns.Print(L.SCAN_REFRESH_STARTED:format(Core.Num(count) or 0)) else ns.Print(L.SCAN_FAIL_unsupported) end
    return ok
end

function Buy.WatchTooltip()
    local entries = ns.Watch.Entries()
    Core.TipTitle(GameTooltip, L.WATCH_TITLE)
    GameTooltip:AddLine(L.WATCH_TIP, nil, nil, nil, true)
    for index, entry in ipairs(entries) do
        if index > Bargain.LIST_TIP then
            Core.TipLine(GameTooltip, ezCore.More(#entries - Bargain.LIST_TIP), "hint")
            break
        end
        Core.TipLine(GameTooltip, L.WATCH_LINE:format(ns.Watch.Name(entry), ns.Watch.TargetText(entry)), "normal", true)
    end
    local hits = #ns.Watch.Hits()
    if hits > 0 then Core.TipLine(GameTooltip, Core.Plural(hits, L.WATCH_HITS_ONE, L.WATCH_HITS_MANY), "good", true) end
    local missing = #ns.Watch.Missing()
    if missing > 0 then Core.TipLine(GameTooltip, L.WATCH_MISSING:format(missing), "highlight", true) end
    GameTooltip:AddLine(ns.AuctionHouseShown() and L.WATCH_CLICK or L.WATCH_CLOSED, nil, nil, nil, true)
end

---------------------------------------------------------------------------
-- Kaufbereich (AH-24, Welle 14): „Bedarf: n“ am Mengenfeld des Warenkaufs, Zeile im Kaufdialog, günstigste Zeile je
-- Stück in der Einzelstück-Liste. Tor T1 für den Kaufbereich: „kein Block, Fehler nicht wiederholbar“ (ns.T1.buy) –
-- gesetzt wird darum nur mit eigenem Schalter (buySetQuantity, buyNextSelect; ab Werk aus) und nur über Blizzards
-- eigene Wege (Mengenwahl über das Ereignis CommoditiesQuantitySelectionChanged, Auswahl über die Liste); sonst steht
-- „Bedarf: n“ nur als Text und die Zeile ist nur markiert. Kaufen und Bieten bleiben Blizzards Knöpfe.
---------------------------------------------------------------------------

local needButton, dialogLine

local function BuyDisplay()
    local frame = AuctionHouseFrame and Core.Peek(AuctionHouseFrame, "CommoditiesBuyFrame")
    local display = type(frame) == "table" and Core.Peek(frame, "BuyDisplay")
    return type(display) == "table" and display or nil
end

-- Darf der Klick auf „Bedarf: n“ die Menge eintragen? Schalter und Tor T1 (ns.BuyMaySet).
function Buy.CanSetNeed() return ns.Enabled("buySetQuantity") and ns.BuyMaySet() end

function Buy.NeedButton() return needButton ~= nil and needButton:IsShown() and needButton or nil end

-- Bedarf zur gerade geöffneten Ware (Lists.Need: Menge der Liste minus Bestand aller Charaktere); nil ohne.
function Buy.CurrentNeed()
    local display = BuyDisplay()
    local itemID = display and display.GetItemID and Core.Num(display:GetItemID())
    if not (itemID and ns.Enabled("buyNeed")) then return nil end
    return ns.Lists.Need(itemID, Buy.active)
end

function Buy.UpdateNeed()
    if not needButton then return end
    local info = Buy.CurrentNeed()
    Buy.needInfo = info
    if not info then
        needButton:Hide()
        return
    end
    needButton:SetLabel(L.NEED_LABEL:format(info.need))
    needButton:Show()
end

function Buy.NeedTip()
    local info = Buy.needInfo
    if not info then return L.NEED_TIP_NONE end
    local lines = {}
    if info.source then
        lines[1] = L.NEED_TIP_SOURCE:format(info.list.name, info.count)
    elseif info.have and (info.guilds or 0) > 0 then
        -- die Gildenbank eigens genannt wie in Lists.StockText (AUC-12), abgezogen wird sie dort wie hier
        lines[1] = L.NEED_TIP_STOCK_GUILD:format(info.list.name, info.count, info.chars or 0, info.guilds)
    elseif info.have then
        lines[1] = L.NEED_TIP_STOCK:format(info.list.name, info.count, info.have, info.need)
    else
        lines[1] = L.NEED_TIP_COUNT:format(info.list.name, info.count)
    end
    -- T4-NR5: abgezogen wird nur der erreichbare Teil (Lists.Need)
    if not info.source and info.reach and info.have and info.reach < info.have then
        lines[#lines + 1] = L.NEED_TIP_REACH:format(info.reach)
    end
    if Buy.CanSetNeed() then
        lines[#lines + 1] = L.NEED_TIP_SET
    else
        -- Weg zur Einstellung in der einen Form (Core.SettingsPathText, T18-18)
        lines[#lines + 1] = ns.BuyMaySet()
            and L.NEED_TIP_SHOW:format(Core.SettingsPathText("ezAuction", "OPT_HEADER_BUY", "OPT_buySetQuantity", L))
            or L.NEED_TIP_T1
    end
    lines[#lines + 1] = L.NEED_TIP_T1_STATE:format(ns.T1Text("buy"))
    return table.concat(lines, "\n")
end

-- Klick auf „Bedarf: n“: mit Schalter und Tor T1 die Menge über Blizzards eigene Mengenwahl (dasselbe Ereignis, das
-- Blizzards Klick auf eine Angebotszeile auslöst – es setzt Mengenfeld und Preise zusammen), sonst nur der Hinweis.
-- Nie Kaufen oder Bestätigen. Rückgabe: true, wenn die Menge gesetzt wurde.
function Buy.ApplyNeed()
    local info = Buy.needInfo
    if not (info and info.need > 0) then
        ns.Print(L.NEED_NONE)
        return false
    end
    if not Buy.CanSetNeed() then
        ns.Print(L.NEED_SHOW_ONLY:format(info.need))
        return false
    end
    local frame, display = AuctionHouseFrame, BuyDisplay()
    local events = type(AuctionHouseFrameMixin) == "table" and type(AuctionHouseFrameMixin.Event) == "table"
        and AuctionHouseFrameMixin.Event
    local event = events and events.CommoditiesQuantitySelectionChanged
    local ok = false
    if event and frame and type(frame.TriggerEvent) == "function" then
        ok = pcall(frame.TriggerEvent, frame, event, info.need)
    elseif display and type(display.SetQuantitySelected) == "function" then
        ok = pcall(display.SetQuantitySelected, display, info.need)
    elseif display and display.QuantityInput and type(display.QuantityInput.SetQuantity) == "function" then
        ok = pcall(display.QuantityInput.SetQuantity, display.QuantityInput, info.need)
    end
    if ok then ns.Print(L.NEED_SET:format(info.need)) end
    return ok
end

-- Zeile im Kaufdialog: „12 % unter deinem Mittel (12 Tage erfasst)“ aus Market.Judge; unter fünf Tagen der Satz, ab
-- wann es eine gibt. nil ohne Preis-Wissen, mit marketHint aus und bei Abwandlungen. Ohne eigenen Schalter seit der
-- Einstellungs-Prüfung vom 19.11.2026 (Nr. 14).
function Buy.DialogText(itemID, unitPrice)
    local Market = ns.Market
    if not Market then return nil end
    local judgement, why = Market.Judge(itemID, unitPrice)
    if judgement then
        local days = Core.Plural(judgement.days, L.MARKET_DAYS_ONE, L.MARKET_DAYS_MANY)
        local percent = judgement.percent
        if percent < 0 then return L.DIALOG_UNDER:format(Core.Percent(-percent), days) end
        if percent > 0 then return L.DIALOG_OVER:format(Core.Percent(percent), days) end
        return L.DIALOG_AT:format(days)
    end
    if why == "few" then
        local stats = Market.Stats(itemID)
        local points = stats and Core.Num(stats.points) or 0
        return L.DIALOG_FEW:format(Core.Plural(points, L.MARKET_DAYS_ONE, L.MARKET_DAYS_MANY), Market.HINT_DAYS)
    end
    return nil
end

function Buy.UpdateDialog(itemID, unitPrice)
    if not dialogLine then return end
    local text = Buy.DialogText(itemID, unitPrice)
    dialogLine.text:SetText(text or "")
    dialogLine:SetShown(text ~= nil)
end

function Buy.DialogLine() return dialogLine end

-- Günstigste fremde Auktion je Stück zu einem Gegenstand (Blizzards geladene Einzelstück-Angebote); nil ohne.
-- Gemerkt für einen Augenblick (die Liste fragt je Zeile).
local cheapest = {}
function Buy.CheapestAuction(itemKey)
    local api = C_AuctionHouse
    if type(itemKey) ~= "table" or not (api and api.GetNumItemSearchResults and api.GetItemSearchResultInfo) then return nil end
    local key, now = ns.KeyString(itemKey), GetTime()
    if cheapest.key == key and cheapest.at == now then return cheapest.id end
    local bestID, bestUnit
    for index = 1, Core.Num(Core.Call(api.GetNumItemSearchResults, itemKey)) or 0 do
        local r = Core.Call(api.GetItemSearchResultInfo, itemKey, index)
        local buyout = type(r) == "table" and Core.Num(r.buyoutAmount)
        if buyout and buyout > 0 and not r.containsOwnerItem and r.auctionID ~= nil then
            local unit = buyout / math.max(1, Core.Num(r.quantity) or 1)
            if not bestUnit or unit < bestUnit then bestID, bestUnit = r.auctionID, unit end
        end
    end
    cheapest.key, cheapest.at, cheapest.id = key, now, bestID
    return bestID
end

-- Neue Angebote (Kauf, neue Liste von Blizzard): die gemerkte günstigste Auktion gilt nicht mehr.
function Buy.ForgetCheapest() cheapest = {} end

-- Nach einem Kauf (ITEM_PURCHASED) die nächstgünstige Zeile vorwählen – nur mit Schalter buyNextSelect und Tor T1,
-- über Blizzards eigene Auswahl der Liste (SetSelectedEntryByCondition). Rückgabe: true, wenn gewählt.
function Buy.SelectNext()
    Buy.selectNext = nil
    if not (ns.Enabled("buyNextSelect") and ns.BuyMaySet()) then return false end
    local frame = AuctionHouseFrame and AuctionHouseFrame.ItemBuyFrame
    local list = frame and frame.ItemList
    if not (list and frame:IsShown() and type(list.SetSelectedEntryByCondition) == "function") then return false end
    local id = Buy.CheapestAuction(Core.Peek(frame, "itemKey"))
    if id == nil then return false end
    return (pcall(list.SetSelectedEntryByCondition, list, function(row) return type(row) == "table" and row.auctionID == id end, true))
end

Buy.SELECT_WAIT = 2       -- Sekunden: so lange wartet die Vorwahl nach einem Kauf höchstens auf Blizzards neue Liste

local function BuildBuyArea()
    local display = BuyDisplay()
    local input = display and Core.Peek(display, "QuantityInput")
    if type(input) == "table" and not needButton then
        needButton = ns.TextButton(display)
        -- unter Blizzards Mengenfeld, rechtsbündig (Lage geschätzt: Prüfpunkt im Spiel)
        needButton:SetPoint("TOPRIGHT", input, "BOTTOMRIGHT", 0, -1)
        needButton:SetScript("OnClick", function() Buy.ApplyNeed() end)
        needButton:SetScript("OnEnter", function(self) Core.ShowTip(self, L.NEED_TITLE, Buy.NeedTip()) end)
        needButton:Hide()
        local frame = AuctionHouseFrame.CommoditiesBuyFrame
        local later = ns.Throttle(function() Buy.UpdateNeed() end, 0)
        if type(frame.SetItemIDAndPrice) == "function" then hooksecurefunc(frame, "SetItemIDAndPrice", later) end
        display:HookScript("OnShow", later)
    end
    local dialog = Core.Peek(AuctionHouseFrame, "BuyDialog")
    if type(dialog) == "table" and not dialogLine then
        dialogLine = CreateFrame("Frame", "ezAuctionBuyDialogLine", dialog)
        dialogLine:SetSize(320, 22)
        -- unter Blizzards Kaufdialog, damit nichts über dessen Knöpfen liegt
        dialogLine:SetPoint("TOP", dialog, "BOTTOM", 0, -2)
        local back = dialogLine:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints(dialogLine)
        back:SetColorTexture(0, 0, 0, 0.7)
        dialogLine.text = dialogLine:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dialogLine.text:SetPoint("CENTER", dialogLine, "CENTER", 0, 0)
        dialogLine:Hide()
        if type(dialog.SetItemID) == "function" then
            hooksecurefunc(dialog, "SetItemID", function(_, itemID, _, unitPrice)
                ns.Try("BuyDialog", Buy.UpdateDialog, itemID, unitPrice)
            end)
        end
    end
end

ns.On("ITEM_PURCHASED", function()
    Buy.ForgetCheapest()
    if Buy.redecorateItems then Buy.redecorateItems() end
    if not (ns.Enabled("buyNextSelect") and ns.BuyMaySet()) then return end
    Buy.selectNext = true
    C_Timer.After(Buy.SELECT_WAIT, function() if Buy.selectNext then Buy.SelectNext() end end)
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function()
    Buy.ForgetCheapest()
    if Buy.selectNext then Buy.SelectNext() end
    if Buy.redecorateItems then Buy.redecorateItems() end
end)

---------------------------------------------------------------------------

ns.OnAuctionHouse(function()
    Buy.Apply()
    ns.Try("BuyArea", BuildBuyArea)
    local results = AuctionHouseFrame.BrowseResultsFrame
    Buy.redecorate = ns.DecorateList(results and results.ItemList, Buy.MarkBrowseRow)
    local items = AuctionHouseFrame.ItemBuyFrame
    Buy.redecorateItems = ns.DecorateList(items and items.ItemList, Buy.MarkItemRow)
end)

ns.Listen("LISTS_CHANGED", function()
    if Buy.active and not ns.Lists.IndexOf(Buy.active) then Buy.active = nil end
    Buy.Refresh()
    -- Mengen der gesuchten Liste stehen in Blizzards Ergebniszeilen (Buy.Wanted)
    if Buy.redecorate then Buy.redecorate() end
end)
ns.Listen("SEARCH_CHANGED", function()
    Buy.Refresh()
    if Buy.redecorate then Buy.redecorate() end
end)
ns.Listen("AH_SHOW", function()
    Buy.Refresh()
    Bargain.FromWatched(true)
end)
ns.Listen("PRICES_UPDATED", function() if Buy.redecorate then Buy.redecorate() end end)
-- Schnäppchen: jede Antwort der Übersicht (gesammelt im nächsten Augenblick; eine neue Antwort von vorn, weitere Seiten
-- und lange Antworten Takt um Takt), nach einer Erfassung das Beobachtete (neu geholt, dann Takt um Takt)
local browseFresh, watchedFresh = false, false
local browseLater = ns.Throttle(function()
    local fresh = browseFresh
    browseFresh = false
    Bargain.FromBrowse(fresh)
end, 0.5)
Bargain.later.browse = browseLater
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() browseFresh = true browseLater() end)
ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", browseLater)
-- watchedFresh: false, "watched" (Warteschlange leer: nur das Beobachtete neu) oder "all" (Erfassung fertig: auch die
-- übrigen Preise von heute neu); "all" geht vor
local watchedLater = ns.Throttle(function()
    local fresh = watchedFresh
    watchedFresh = false
    if ns.AuctionHouseShown() then Bargain.FromWatched(fresh and true, fresh == "watched") end
end, 1)
Bargain.later.watched = watchedLater
local function WatchedAnew(all)
    if all or watchedFresh ~= "all" then watchedFresh = all and "all" or "watched" end
    watchedLater()
end
Core.Listen("PRICES_SCAN_DONE", function() WatchedAnew(true) end, "ezAuction")
Core.Listen("PRICES_QUEUE_CHANGED", function(owner) if owner == nil then WatchedAnew(false) end end, "ezAuction")
ns.Listen("WATCH_CHANGED", function()
    Buy.Refresh()
    if Buy.redecorate then Buy.redecorate() end
end)
ns.Listen("AH_HIDE", function()
    Buy.selectNext = nil
    if ShownKind() == "bargain" or ShownKind() == "watch" then Buy.Refresh() end
end)
ns.OnSettingChanged(function(key)
    if key == "shoppingLists" or key == "bargainList" or key == "watchList" then
        -- abgeschaltet, während gewählt: abwählen (sonst suchte Enter die abgeschaltete Ansicht; Befund des Reviews)
        if (key == "bargainList" and Buy.pick == "bargain" or key == "watchList" and Buy.pick == "watch"
            or key == "shoppingLists" and (Buy.active or Buy.pick == "lists")) and not ns.Enabled(key) then
            Buy.Select(nil)
        end
        Buy.Apply()
        if key == "bargainList" and ns.Enabled("bargainList") then Bargain.FromBrowse(true) end
    end
    if (key == "vendorMark" or key == "marketCompare" or key == "bargainPercent" or key == "marketHint"
        or key == "watchList") and Buy.redecorate then
        Buy.redecorate()
    end
    if key == "buyNextMark" and Buy.redecorateItems then Buy.redecorateItems() end
    if key == "buyNeed" or key == "buySetQuantity" then Buy.UpdateNeed() end
end)
