local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Einkaufsliste links (seit dem zweiten Spieltest vom 21.11.2026, Entscheidung des Nutzers „Ja, Seitenteil links
    (Empfohlen)“ auf „liste sollte links bei kaufen wie bei verkaufen aus der tasche eingezeigt werden“): die in der
    Kategorienliste gewählte Liste (ns.Buy.Select) steht im Reiter „Kaufen“ als Seitenteil links, im selben Rahmen
    wie „Aus der Tasche“ (ns.PanelLook, ns.PlaceLeftPanel). Vorher lag der Editor über Blizzards Ergebnisfläche und
    öffnete sich über ein Blatt-Symbol an der Liste – Blizzards Spaltenköpfe lagen darüber. Gesucht wird mit
    Blizzards „Suchen“ und Blizzards Filter (BuyTab.lua, Search.lua).
    Einträge: Suchbegriff tippen (in Anführungszeichen genau dieser Name), Gegenstand hineinziehen oder mit
    Shift-Klick einfügen, die aktuelle Suche übernehmen; bei Rezepten die Zutaten aus dem Item-Wissen.
    Listen mit Quelle (Bibliotheksbücher) zeigt der Editor nur: ihr Inhalt kommt aus der Quelle. Die Listen sind seit dem
    21.11.2026 ezCores gemeinsame Listen (Core.Lists) – dieselben wie in ezCraft, auch mit hergestellten Gegenständen.
]]

local Editor = {}
ns.Editor = Editor

local frame, input, list, emptyText, hint
local WIDTH = ns.LEFT_PANEL_WIDTH   -- Wunschbreite wie alle Seitenteile (Core.lua; schmaler bei wenig Platz)
local LOOK = ns.LOOK               -- Maße und Schriften der Listen wie ezTalent (ezCores Core.PANEL_LIST)
local ADD_W = 96                   -- „Hinzufügen“ rechts neben der Eingabe
local editControls = {}
local lastLink, lastLinkTime

local function Lists() return ns.Lists end

function Editor.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Editor.Current()
    return Editor.IsShown() and list or nil
end

---------------------------------------------------------------------------
-- Einträge hinzufügen
---------------------------------------------------------------------------

-- Darf die Liste von Hand geändert werden? (Nicht bei Listen mit Quelle.)
function Editor.IsEditable(target)
    return target ~= nil and Lists().SourceOf(target) == nil
end

function Editor.Add(value)
    if not Editor.IsEditable(list) then return nil end
    local entry = Lists().AddEntry(list, value)
    if entry then
        -- nur leeren, was aus dem Feld kam: ein Shift-Klick oder Hineinziehen lässt getippten Text stehen (Review)
        if input and value == input:GetText() then input:SetText("") end
        Editor.Refresh()
    end
    return entry
end

function Editor.AddCursorItem()
    if not (Editor.IsEditable(list) and GetCursorInfo) then return false end
    local kind, itemID, link = GetCursorInfo()
    if kind ~= "item" then return false end
    Editor.Add(link or itemID)
    if ClearCursor then ClearCursor() end
    return true
end

function Editor.AddCurrentSearch()
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    local box = bar and bar.SearchBox
    local text = box and box:GetText()
    if type(text) == "string" and Core.Trim(text) ~= "" then
        Editor.Add(text)
    else
        ns.Print(L.EDITOR_NO_SEARCH)
    end
end

-- Geht ein Shift-Klick gerade woandershin? Ein offenes Chat-Eingabefeld oder ein anderes Eingabefeld mit Fokus
-- (Makros …) bekommt den Gegenstand wie bei Blizzard; die Liste nur, wenn sonst niemand ihn nimmt. Blizzards Suchfeld
-- im Auktionshaus zählt nicht: Blizzard setzt den Namen dort bei jedem Shift-Klick ein, ob es den Fokus hat oder nicht.
-- Ein Link ohne gedrückte Umschalttaste (Addons fügen Links über ChatEdit_InsertLink ein, z. B. ezCores
-- Core.OpenChatWith) geht nie in die Liste (Befund des Reviews).
local function LinkGoesElsewhere()
    if input and input:HasFocus() then return false end
    local modified = rawget(_G, "IsModifiedClick")
    if type(modified) == "function" and not Core.Call(modified, "CHATLINK") then return true end
    local target = Core.LinkInput()
    local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
    return target ~= nil and target ~= input and target ~= (bar and bar.SearchBox)
end

-- Shift-Klick auf einen Gegenstand (Tasche, Blizzards Ergebnisliste, Rezept, Link im Chat), solange eine änderbare
-- Liste links steht: der Gegenstand kommt in die Liste – wie Blizzard ihn ins Suchfeld setzt (vierter Spieltest vom
-- 21.11.2026: „am besten wie original blizz mit shift linke maustaste auf icon in suche einfügen --> das mit der suche
-- einfügen fehlt der einkaufsliste-anzeige im ah“). Vorher nur, solange das Eingabefeld der Liste den Fokus hatte.
local function OnInsertLink(link)
    if not (input and Editor.IsShown() and Editor.IsEditable(list)) or type(link) ~= "string" then return end
    if LinkGoesElsewhere() then return end
    local now = GetTime()
    if link == lastLink and lastLinkTime and now - lastLinkTime < 0.2 then return end   -- mehrere Haken, ein Klick
    lastLink, lastLinkTime = link, now
    if Lists().ParseLink(link) then Editor.Add(link) end
end
Editor.OnInsertLink = OnInsertLink   -- für Prüfungen

local function HookLinks()
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink) end
    -- Blizzards Weg für Shift-Klicks auf Gegenstände; greift auch, wo Blizzards Auktionshaus den Link selbst nimmt
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if IsModifiedClick and IsModifiedClick("CHATLINK") then OnInsertLink(link) end
        end)
    end
end

---------------------------------------------------------------------------
-- Filter und Höchstpreis einer Zeile (AH-09): Menü am Filter-Knopf der Zeile. Gesetzt wird nur der Eintrag der
-- eigenen Liste (Lists.SetFilters); Blizzards Kategorienliste und Filterknopf bleiben unberührt.
---------------------------------------------------------------------------

-- Stufe von–bis abfragen („20-30“, leer = ohne).
function Editor.AskLevels(entry)
    local target = list
    local current = ""
    if entry.minLevel or entry.maxLevel then current = ("%s-%s"):format(entry.minLevel or "", entry.maxLevel or "") end
    Core.AskText(L.FILTER_LEVELS_PROMPT, current, function(text)
        local low, high = Lists().ParseLevels(text)
        if low == false then return ns.Print(L.FILTER_LEVELS_BAD:format(text or "")) end
        Lists().SetFilters(target, entry, { minLevel = low or false, maxLevel = high or false })
    end, 12)
end

-- Höchstpreis je Stück abfragen („5“ = 5 Gold, „5g 20s“, leer = ohne).
function Editor.AskMaxPrice(entry)
    local target = list
    local current = entry.maxPrice and Core.PlainMoney(entry.maxPrice) or ""
    Core.AskText(L.FILTER_PRICE_PROMPT, current, function(text)
        local copper = Lists().ParseMoney(text)
        if copper == false then return ns.Print(L.FILTER_PRICE_BAD:format(text or "")) end
        Lists().SetFilters(target, entry, { maxPrice = copper or false })
    end, 20)
end

-- Kategorien aus Blizzards Tabelle als Untermenüs (höchstens drei Ebenen); jede Ebene wählbar.
local function AddCategories(parent, nodes, path, entry, target)
    for _, node in ipairs(nodes or {}) do
        local name = path and (path .. " " .. Core.ARROW .. " " .. node.name) or node.name
        local choice = { name = name, filters = node.filters, implicit = node.implicit }
        local function Pick() Lists().SetFilters(target, entry, { category = Lists().CleanCategory(choice) or false }) end
        if node.children and #node.children > 0 then
            local sub = Core.Menu.Button(parent, node.name)
            Core.Menu.Button(sub, L.FILTER_CATEGORY_ALL:format(node.name), Pick)
            AddCategories(sub, node.children, name, entry, target)
        else
            Core.Menu.Button(parent, node.name, Pick)
        end
    end
end

function Editor.FilterMenu(owner, entry)
    local target = list
    if not (target and entry and Editor.IsEditable(target)) then return false end
    local opened = Core.Menu.Open(owner, function(root)
        Core.Menu.Title(root, L.FILTER_TITLE:format(Lists().EntryLabel(entry)))
        local categories = Core.Menu.Button(root, L.FILTER_MENU_CATEGORY:format(entry.category and entry.category.name or L.FILTER_NONE))
        Core.Menu.Button(categories, L.FILTER_NONE, function() Lists().SetFilters(target, entry, { category = false }) end)
        local tree = Lists().CategoryTree()
        if tree then AddCategories(categories, tree, nil, entry, target) end
        Core.Menu.Button(root, L.FILTER_MENU_LEVELS:format(Lists().LevelText(entry.minLevel, entry.maxLevel) or L.FILTER_NONE),
            function() Editor.AskLevels(entry) end)
        local qualities = Core.Menu.Button(root, L.FILTER_MENU_QUALITY:format(entry.quality
            and L.FILTER_QUALITY:format(Lists().QualityName(entry.quality)) or L.FILTER_NONE))
        Core.Menu.Radio(qualities, L.FILTER_NONE, function() return entry.quality or 0 end,
            function() Lists().SetFilters(target, entry, { quality = false }) end, 0)
        for quality = 1, Lists().QUALITY_MAX do
            Core.Menu.Radio(qualities, L.FILTER_QUALITY:format(Lists().QualityName(quality)), function() return entry.quality or 0 end,
                function(value) Lists().SetFilters(target, entry, { quality = value }) end, quality)
        end
        if not entry.itemID then
            Core.Menu.Toggle(root, L.FILTER_MENU_EXACT, function() return entry.exact == true end,
                function(value) Lists().SetFilters(target, entry, { exact = value and true or false }) end)
        end
        Core.Menu.Button(root, L.FILTER_MENU_PRICE:format(entry.maxPrice and ns.Money(entry.maxPrice) or L.FILTER_NONE),
            function() Editor.AskMaxPrice(entry) end)
        Core.Menu.Divider(root)
        Core.Menu.Button(root, L.FILTER_MENU_CLEAR, function()
            Lists().SetFilters(target, entry, { minLevel = false, maxLevel = false, quality = false, category = false, maxPrice = false })
        end)
    end)
    -- Ohne Blizzards Menü: wenigstens der Höchstpreis über den Eingabedialog
    if not opened then Editor.AskMaxPrice(entry) end
    return true
end

-- Text der Zeile: Eintrag, dahinter grau die Filter samt Höchstpreis (AH-09; seit der Einstellungs-Prüfung vom
-- 19.11.2026 immer).
function Editor.RowText(entry)
    local label = Lists().EntryLabel(entry)
    local filters = Lists().FilterText(entry, true)
    if filters then label = label .. "  " .. Core.Grey(filters) end   -- Hinweis in ezCores Grau (Design-System 2.5)
    return label
end

-- Kostenvoranschlag unter der Liste (AH-10; Schalter listCost).
function Editor.CostText()
    if not (list and ns.Enabled("listCost")) then return nil end
    return Lists().CostText(list)
end

---------------------------------------------------------------------------
-- Zeilen
---------------------------------------------------------------------------

local function SmallButton(row, texture, onClick, title, body)
    local button = CreateFrame("Button", nil, row)
    button:SetSize(16, 16)
    button:SetNormalTexture(texture)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self) Core.ShowTip(self, title, body) end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    return button
end

local function BuildRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(Core.Style.ICON.line, Core.Style.ICON.line)   -- Symbol in einer Zeile (Design-System 2.3; bis Welle 22 18)
    row.icon:SetPoint("LEFT", row, "LEFT", LOOK.entryIndent, 0)   -- eingerückt wie ezTalents Einträge
    row.label = row:CreateFontString(nil, "OVERLAY", LOOK.fonts.entry)
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -84, 0)   -- vier Knöpfe zu 16 mit 4 Abstand (schmales Seitenteil)
    row.label:SetJustifyH("LEFT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(16, 16)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.remove:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    row.remove:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight", "ADD")
    row.remove:SetScript("OnClick", function(self)
        if list and self.index then
            Lists().RemoveEntry(list, self.index)
            Editor.Refresh()
        end
    end)
    row.remove:SetScript("OnEnter", function(self) Core.ShowTip(self, L.EDITOR_REMOVE, L.EDITOR_REMOVE_TIP) end)
    row.remove:SetScript("OnLeave", GameTooltip_Hide)

    -- Filter und Höchstpreis der Zeile (AH-09)
    row.filter = SmallButton(row, "Interface\\Buttons\\UI-GuildButton-OfficerNote-Up", function(self)
        if self.entry then Editor.FilterMenu(self, self.entry) end
    end, L.EDITOR_FILTER, L.EDITOR_FILTER_TIP)
    row.filter:SetPoint("RIGHT", row.remove, "LEFT", -4, 0)
    -- Nur diese Zeile suchen (AH-10)
    row.search = SmallButton(row, "Interface\\Common\\UI-Searchbox-Icon", function(self)
        if list and self.entry then ns.Buy.StartEntry(list, self.entry) end
    end, L.EDITOR_ROW_SEARCH, L.EDITOR_ROW_SEARCH_TIP)
    row.search:SetPoint("RIGHT", row.filter, "LEFT", -4, 0)

    row.reagents = CreateFrame("Button", nil, row)
    row.reagents:SetSize(16, 16)
    row.reagents:SetPoint("RIGHT", row.search, "LEFT", -4, 0)
    row.reagents:SetNormalTexture("Interface\\Icons\\Trade_BlackSmithing")
    row.reagents:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    row.reagents:SetScript("OnClick", function(self)
        local entry = self.entry
        if not (list and entry and entry.itemID) then return end
        local added = Lists().AddReagents(list, entry.itemID, entry.count)
        ns.Print(L.EDITOR_REAGENTS_DONE:format(added))
        Editor.Refresh()
    end)
    row.reagents:SetScript("OnEnter", function(self) Core.ShowTip(self, L.EDITOR_REAGENTS, L.EDITOR_REAGENTS_TIP) end)
    row.reagents:SetScript("OnLeave", GameTooltip_Hide)

    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if entry.itemID and GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(entry.itemID)
        else
            Core.TipTitle(GameTooltip, Lists().EntryLabel(entry))
            GameTooltip:AddLine(entry.exact and L.EDITOR_EXACT_TIP or L.EDITOR_TERM_TIP, nil, nil, nil, true)
        end
        -- Bestand aller Charaktere (Lists.StockText; nicht bei Listen mit Quelle)
        local stock = Lists().StockText(entry, list)
        if stock then Core.TipLine(GameTooltip, L.LIST_STOCK_LABEL:format(stock), "highlight", true) end
        -- Filter und Höchstpreis (AH-09)
        local filters = Lists().FilterText(entry)
        if filters then Core.TipLine(GameTooltip, L.FILTER_ROW_TIP:format(filters), "blue", true) end
        if entry.maxPrice then
            Core.TipLine(GameTooltip, L.FILTER_PRICE_ROW_TIP:format(ns.Money(entry.maxPrice)), "blue", true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnReceiveDrag", Editor.AddCursorItem)
    row.built = true
end

local function InitRow(row, data)
    if not row.built then BuildRow(row) end
    local entry = data.entry
    row.entry = entry
    row.remove.index = data.index
    row.reagents.entry = entry
    row.filter.entry, row.search.entry = entry, entry
    local icon = entry.recipe and Core.Lists.Icon(entry) or Core.ItemIcon(entry.itemID)
    row.icon:SetTexture(icon or Core.ICON_FALLBACK)
    row.label:SetText(Editor.RowText(entry))
    local editable = Editor.IsEditable(list)
    row.remove:SetShown(editable)
    -- Filter nur an Listen ohne Quelle: deren Einträge baut die Quelle bei jeder Suche neu
    -- hergestellte Gegenstände: gesucht wird ihr Material bzw. Produkt (Core.Lists) – Filter gälten dort nicht
    row.filter:SetShown(editable and not entry.recipe)
    row.search:SetShown(ns.Enabled("rowSearch"))
    row.reagents:SetShown(editable and entry.itemID ~= nil and Lists().ReagentsOf(entry.itemID) ~= nil)
end

---------------------------------------------------------------------------
-- Rahmen
---------------------------------------------------------------------------

-- Tooltip eines Eingabe-Teils: gesperrt (Liste mit Quelle) steht der Grund darunter (Gesamtreview 18.11.2026, T9-7;
-- design-system 2.7 – derselbe Satz wie im Hinweis über der Liste).
function Editor.TipBody(control, body)
    local enabled = not (control and control.IsEnabled) or control:IsEnabled()
    local source = list and Lists().SourceOf(list)
    if enabled or not source then return body end
    local reason = L["EDITOR_SOURCE_" .. source]
    if type(reason) ~= "string" then return body end
    return (body and body .. "\n\n" or "") .. Core.Style.ColorText("bad", reason)
end

-- Schrift der Knöpfe nach der Breite setzt Editor.OnWidth (schmal: Blizzards kleine Schrift)
local function Button(parent, text, width, onClick, tipTitle, tipBody)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, ns.BUTTON_H)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    if tipTitle then
        button:SetScript("OnEnter", function(self) Core.ShowTip(self, tipTitle, Editor.TipBody(self, tipBody)) end)
        button:SetScript("OnLeave", GameTooltip_Hide)
    end
    -- auch ausgeschaltet mit Tooltip (Blizzard meldet OnEnter sonst nicht)
    return Core.Toolbar.ShowTipWhileDisabled(button)
end

local function Build()
    local ok, f = pcall(CreateFrame, "Frame", "ezAuctionListEditor", AuctionHouseFrame, "ButtonFrameTemplate")
    if not ok or not f then f = CreateFrame("Frame", "ezAuctionListEditor", AuctionHouseFrame) end
    frame = f
    f:SetWidth(WIDTH)
    f:EnableMouse(true)
    f:Hide()
    -- Rahmen wie „Aus der Tasche“ und der Markt: Titel in Blizzards Titelleiste, ohne X (abwählen über die Liste)
    ns.PanelLook(f, L.LISTS)

    -- Kopf wie ezTalent ab ns.PANEL_TOP, LOOK.headLeft vom Rand (Blizzards Eingabefeld zeichnet 4 links vor seinem
    -- Feld): Eingabe und „Hinzufügen“; die Eingabe wächst mit der Breite des Seitenteils
    input = CreateFrame("EditBox", "ezAuctionListEditorInput", f, "InputBoxTemplate")
    input:SetHeight(20)
    input:SetPoint("TOPLEFT", f, "TOPLEFT", LOOK.headLeft + 4, -ns.PANEL_TOP)
    input:SetAutoFocus(false)
    input:SetMaxLetters(80)
    input:SetScript("OnEnterPressed", function(self)
        Editor.Add(self:GetText())
        self:ClearFocus()
    end)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnReceiveDrag", Editor.AddCursorItem)
    input:SetScript("OnEnter", function(self) Core.ShowTip(self, L.EDITOR_ADD, Editor.TipBody(self, L.EDITOR_ADD_TIP)) end)
    Core.Toolbar.ShowTipWhileDisabled(input)
    input:SetScript("OnLeave", GameTooltip_Hide)
    local add = Button(f, L.EDITOR_ADD, ADD_W, function()
        if not Editor.AddCursorItem() then Editor.Add(input:GetText()) end
    end, L.EDITOR_ADD, L.EDITOR_ADD_TIP)
    add:SetPoint("TOPRIGHT", f, "TOPRIGHT", -ns.BUTTON_X, -ns.PANEL_TOP)
    input:SetPoint("TOPRIGHT", add, "TOPLEFT", -ns.BUTTON_GAP, -1)   -- oben angehängt (Höhe bleibt 20)
    -- zweite Zeile: aktuelle Suche übernehmen, umbenennen (je halbe Breite, Editor.OnWidth)
    local fromSearch = Button(f, L.EDITOR_FROM_SEARCH, 106, Editor.AddCurrentSearch,
        L.EDITOR_FROM_SEARCH, L.EDITOR_FROM_SEARCH_TIP)
    fromSearch:SetPoint("TOPLEFT", f, "TOPLEFT", ns.BUTTON_X, -ns.PANEL_TOP - 26)
    local rename = Button(f, L.EDITOR_RENAME, 106, function()
        local current = list
        if not current then return end
        Core.AskText(L.EDITOR_RENAME_PROMPT, current.name, function(text)
            if not Lists().Rename(current, text) then ns.Print(L.EDITOR_NAME_TAKEN:format(text or "")) end
            Editor.Refresh()
        end)
    end, L.EDITOR_RENAME, L.EDITOR_RENAME_TIP)
    rename:SetPoint("LEFT", fromSearch, "RIGHT", ns.BUTTON_GAP, 0)
    editControls = { input, add, fromSearch }
    Editor.editControls = editControls   -- für Prüfungen
    Editor.renameButton = rename

    hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    -- beide Anker oben (der Kasten hängt an der Unterkante des Hinweises; „RIGHT“ am Seitenteil legte seine Mitte fest)
    hint:SetPoint("TOPLEFT", fromSearch, "BOTTOMLEFT", 0, -6)
    hint:SetPoint("TOPRIGHT", rename, "BOTTOMRIGHT", 0, -6)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.EDITOR_HINT)

    -- unten: Weitergeben als Text (AUC-20) und Löschen, darüber der Kostenvoranschlag (AH-10)
    -- drei gleich breite Knöpfe über die ganze Breite (wie ezTalents Knopfreihe; Editor.OnWidth)
    local export = Button(f, L.EDITOR_EXPORT, 70, function() Editor.Export() end, L.EDITOR_EXPORT, L.EDITOR_EXPORT_TIP)
    export:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ns.BUTTON_X, ns.BUTTON_Y)
    local import = Button(f, L.EDITOR_IMPORT, 70, function() Editor.Import() end, L.EDITOR_IMPORT, L.EDITOR_IMPORT_TIP)
    import:SetPoint("LEFT", export, "RIGHT", ns.BUTTON_GAP, 0)
    local delete = Button(f, Core.Word("DELETE"), 70, function()
        local current = list
        if not current then return end
        Core.Confirm(L.EDITOR_DELETE_CONFIRM:format(current.name), function()
            Lists().Delete(current)
            ns.Buy.Select(nil)
        end)
    end, Core.Word("DELETE"), L.EDITOR_DELETE_TIP)
    delete:SetPoint("LEFT", import, "RIGHT", ns.BUTTON_GAP, 0)
    Editor.importButton, Editor.exportButton, Editor.deleteButton = import, export, delete

    local cost = CreateFrame("Frame", nil, f)
    cost:SetPoint("BOTTOMLEFT", export, "TOPLEFT", 0, 6)
    cost:SetPoint("BOTTOMRIGHT", delete, "TOPRIGHT", 0, 6)   -- unten angehängt, 18 hoch (darüber beginnt der Kasten)
    cost:SetHeight(18)
    cost:EnableMouse(true)
    cost.text = cost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cost.text:SetAllPoints(cost)
    cost.text:SetJustifyH("LEFT")
    cost:SetScript("OnEnter", function(self) Core.ShowTip(self, L.LIST_COST_TITLE, L.LIST_COST_TIP) end)
    cost:SetScript("OnLeave", GameTooltip_Hide)
    Editor.cost = cost

    list = nil
    -- die Liste in Blizzards innerem Kasten zwischen Kopf (bis zum Hinweis) und Kostenzeile (wie ezTalent; ohne Kasten
    -- im Client wie vorher)
    Editor.rows = ns.NewScrollList(f, 24, InitRow, LOOK.entryGap)
    local bottom = ns.BUTTON_Y + ns.BUTTON_H + 6 + 18 + LOOK.buttonGap   -- über Knopfreihe und Kostenzeile
    f.inset = ns.PanelInset(f, hint, ns.BUTTON_X, bottom)
    Editor.inset = f.inset
    if f.inset then Editor.rows:SetInside(f.inset) else Editor.rows:SetPoints(8, -ns.PANEL_TOP - 92, -8, 62) end
    emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    if f.inset then
        emptyText:SetPoint("TOPLEFT", f.inset, "TOPLEFT", LOOK.insetLeft + LOOK.entryIndent, -(LOOK.insetTop + 6))
        emptyText:SetPoint("TOPRIGHT", f.inset, "TOPRIGHT", -LOOK.insetLeft, -(LOOK.insetTop + 6))
    else
        emptyText:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -ns.PANEL_TOP - 100)
        emptyText:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    end
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText(L.EDITOR_EMPTY)

    f:SetScript("OnReceiveDrag", Editor.AddCursorItem)
    f:SetScript("OnMouseUp", function() Editor.AddCursorItem() end)
    f.OnWidth = function(_, width) Editor.OnWidth(width) end
    Editor.OnWidth(WIDTH)
    HookLinks()
end

-- Knöpfe nach der Breite des Seitenteils (ns.PlaceLeftPanel ruft das nach dem Andocken): zweite Kopfzeile je halbe
-- Breite, unten drei gleich breite Knöpfe; schmal (unter 300, wie ezTalents Knopfreihe) in Blizzards kleiner Schrift.
-- → Breite eines unteren Knopfs
function Editor.OnWidth(width)
    if not frame then return nil end
    width = Core.Num(width) or WIDTH
    local inner = width - 2 * ns.BUTTON_X
    local half = math.floor((inner - ns.BUTTON_GAP) / 2)
    local third = math.floor((inner - 2 * ns.BUTTON_GAP) / 3)
    local small = width < 300
    for _, b in ipairs({ editControls[3], Editor.renameButton }) do if b then b:SetWidth(half) end end
    for _, b in ipairs({ Editor.exportButton, Editor.importButton, Editor.deleteButton }) do if b then b:SetWidth(third) end end
    for _, b in ipairs({ editControls[2], editControls[3], Editor.renameButton, Editor.exportButton, Editor.importButton,
        Editor.deleteButton }) do
        if b and b.SetNormalFontObject then
            b:SetNormalFontObject(small and "GameFontNormalSmall" or "GameFontNormal")
            b:SetHighlightFontObject(small and "GameFontHighlightSmall" or "GameFontHighlight")
            b:SetDisabledFontObject(small and "GameFontDisableSmall" or "GameFontDisable")
        end
    end
    return third
end

-- Die offene Liste als Text zeigen (ezCores Text-Dialog, zum Kopieren mit Strg+C). Rückgabe: der Text oder nil.
function Editor.Export()
    if not list then return nil end
    local text = Lists().Export(list)
    if type(text) ~= "string" or type(Core.TextDialog) ~= "function" then
        ns.Print(L.LIST_EXPORT_FAIL)
        return nil
    end
    Core.TextDialog({ title = L.LIST_EXPORT_TITLE:format(list.name), hint = L.LIST_EXPORT_HINT, text = text,
        select = true, anchor = AuctionHouseFrame, owner = "ezAuction" })
    return text
end

-- Text einfügen und übernehmen: legt die Listen neu an und öffnet die erste im Editor. Bei einem Fehler bleibt der
-- Dialog offen und der Grund steht im Chat.
function Editor.Import()
    if type(Core.TextDialog) ~= "function" then
        ns.Print(L.LIST_EXPORT_FAIL)
        return false
    end
    Core.TextDialog({ title = L.LIST_IMPORT_TITLE, hint = L.LIST_IMPORT_HINT, text = "", accept = true,
        anchor = AuctionHouseFrame, owner = "ezAuction", onAccept = function(text) return Editor.ImportText(text) end })
    return true
end

-- Übernahme eines Texts (auch für Prüfungen). → true oder false (Grund im Chat).
function Editor.ImportText(text)
    local lists, count = Lists().Import(text)
    if not lists then
        ns.Print(L.LIST_IMPORT_FAIL:format(L["LIST_IMPORT_WHY_" .. tostring(count)] or L.LIST_IMPORT_WHY_bad))
        return false
    end
    local names = {}
    for _, imported in ipairs(lists) do names[#names + 1] = imported.name end
    local entries = Core.Plural(Core.Num(count) or 0, L.LIST_IMPORT_ENTRIES_ONE, L.LIST_IMPORT_ENTRIES_MANY)
    ns.Print(Core.Plural(#lists, L.LIST_IMPORT_DONE_ONE, L.LIST_IMPORT_DONE_MANY, table.concat(names, ", "), entries))
    ns.Buy.Select(lists[1])
    return true
end

function Editor.Refresh()
    if not frame or not list then return end
    if frame.SetTitle then pcall(frame.SetTitle, frame, L.EDITOR_TITLE:format(list.name)) end
    Editor.title = L.EDITOR_TITLE:format(list.name)   -- für Prüfungen
    -- Liste mit Quelle: Eingabe gesperrt, Hinweis woher der Inhalt kommt.
    local source = Lists().SourceOf(list)
    for _, control in ipairs(editControls) do
        if control.SetEnabled then control:SetEnabled(source == nil) end
    end
    if source then input:ClearFocus() end
    hint:SetText(source and L["EDITOR_SOURCE_" .. source] or L.EDITOR_HINT)
    local data = {}
    for index, entry in ipairs(list.items or {}) do data[#data + 1] = { index = index, entry = entry } end
    Editor.rows:SetData(data)
    emptyText:SetShown(#data == 0)
    local cost = Editor.CostText()
    Editor.cost.text:SetText(cost or "")
    Editor.cost:SetShown(cost ~= nil)
end

-- Zeigen, solange eine Liste gewählt ist (ns.Buy.active), der Reiter „Kaufen“ offen und die Einkaufslisten an; sonst
-- verbergen. → true, wenn zu sehen
function Editor.Update()
    local target = ns.Buy and ns.Buy.active
    local want = target ~= nil and ns.ahReady and ns.AuctionHouseShown() and ns.ModeName() == "buy"
        and ns.Enabled("shoppingLists") and Lists().IndexOf(target) ~= nil
    if not want then
        if frame then frame:Hide() end
        list = nil
        if ns.MarketPanel then ns.MarketPanel.PlaceArrow() end
        return false
    end
    if not frame then Build() end
    list = target
    frame:Show()
    ns.PlaceLeftPanel(frame, WIDTH)
    Editor.Refresh()
    -- der Pfeil des zugeklappten Markts weicht dem Seitenteil aus, wenn es rechts steht
    if ns.MarketPanel then ns.MarketPanel.PlaceArrow() end
    return true
end

-- Eine Liste zeigen: sie wird gewählt wie eine Kategorie (ns.Buy.Select) und steht links. → true, wenn zu sehen
function Editor.Open(target)
    if not (target and ns.ahReady and ns.AuctionHouseShown()) then return false end
    if ns.Buy.active ~= target then ns.Buy.Select(target) else Editor.Update() end
    return Editor.IsShown()
end

-- Neu andocken, falls zu sehen (der Markt hat sich auf- oder zugeklappt oder die Seite gewechselt; MarketPanel.lua).
function Editor.Place()
    if not (frame and frame:IsShown()) then return false end
    ns.PlaceLeftPanel(frame, WIDTH)
    if ns.MarketPanel then ns.MarketPanel.PlaceArrow() end
    return true
end

-- Nur verbergen; die Wahl bleibt (ns.Buy.Select(nil) wählt ab).
function Editor.Close()
    if frame then frame:Hide() end
end

-- Seite, an der das Seitenteil angedockt hat (ns.PlaceLeftPanel), oder nil.
function Editor.DockedSide()
    return frame ~= nil and frame.dockSide or nil
end

-- Breite nach dem Platz (ns.PlaceLeftPanel), sonst die Wunschbreite
function Editor.Width()
    return frame ~= nil and frame.fitWidth or WIDTH
end

-- Eingabefeld fokussieren (neue Liste).
function Editor.Focus()
    if input and Editor.IsShown() and Editor.IsEditable(list) then input:SetFocus() end
end

ns.Listen("LISTS_CHANGED", function()
    if not Editor.IsShown() then return end
    if not Lists().IndexOf(list) then return ns.Buy.Select(nil) end
    Editor.Refresh()
end)
ns.Listen("AH_MODE", function() Editor.Update() end)
ns.Listen("AH_HIDE", Editor.Close)
-- Neue Preise ändern den Kostenvoranschlag; Schalter blenden Knöpfe und Filter ein und aus
ns.Listen("PRICES_UPDATED", function() if Editor.IsShown() then Editor.Refresh() end end)
ns.OnSettingChanged(function(key)
    if (key == "rowSearch" or key == "listCost") and Editor.IsShown() then Editor.Refresh() end
    if key == "shoppingLists" or key == "sellListSide" then Editor.Update() end
end)
