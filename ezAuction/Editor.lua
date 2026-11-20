local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Editor einer Einkaufsliste: liegt über Blizzards Ergebnisfläche im Reiter „Kaufen“ (kein eigenes Fenster,
    kein Reiter) und schließt sich, sobald gesucht wird oder der Reiter wechselt.
    Einträge: Suchbegriff tippen (in Anführungszeichen genau dieser Name), Gegenstand hineinziehen oder mit
    Shift-Klick einfügen, die aktuelle Suche übernehmen; bei Rezepten die Zutaten aus dem Item-Wissen.
    Listen mit Quelle (Bibliotheksbücher, ezCraft) zeigt der Editor nur: ihr Inhalt kommt aus der Quelle.
]]

local Editor = {}
ns.Editor = Editor

local frame, input, list, emptyText, title, hint
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
        if input then input:SetText("") end
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

-- Shift-Klick auf einen Gegenstand, solange das Eingabefeld den Fokus hat.
local function OnInsertLink(link)
    if not (input and Editor.IsShown() and input:HasFocus()) or type(link) ~= "string" then return end
    local now = GetTime()
    if link == lastLink and lastLinkTime and now - lastLinkTime < 0.2 then return end
    lastLink, lastLinkTime = link, now
    if Lists().ParseLink(link) then Editor.Add(link) end
end

local function HookLinks()
    if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
    if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink) end
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
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    row.label:SetJustifyH("LEFT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(16, 16)
    row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
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
    row.filter:SetPoint("RIGHT", row.remove, "LEFT", -6, 0)
    -- Nur diese Zeile suchen (AH-10)
    row.search = SmallButton(row, "Interface\\Common\\UI-Searchbox-Icon", function(self)
        if list and self.entry then ns.Buy.StartEntry(list, self.entry) end
    end, L.EDITOR_ROW_SEARCH, L.EDITOR_ROW_SEARCH_TIP)
    row.search:SetPoint("RIGHT", row.filter, "LEFT", -6, 0)

    row.reagents = CreateFrame("Button", nil, row)
    row.reagents:SetSize(16, 16)
    row.reagents:SetPoint("RIGHT", row.search, "LEFT", -6, 0)
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
    local icon = Core.ItemIcon(entry.itemID)
    row.icon:SetTexture(icon or Core.ICON_FALLBACK)
    row.label:SetText(Editor.RowText(entry))
    local editable = Editor.IsEditable(list)
    row.remove:SetShown(editable)
    -- Filter nur an Listen ohne Quelle: deren Einträge baut die Quelle bei jeder Suche neu
    row.filter:SetShown(editable)
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

local function Button(parent, text, width, onClick, tipTitle, tipBody)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
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
    local results = AuctionHouseFrame.BrowseResultsFrame
    local ok, f = pcall(CreateFrame, "Frame", "ezAuctionListEditor", AuctionHouseFrame, "InsetFrameTemplate")
    if not ok or not f then f = CreateFrame("Frame", "ezAuctionListEditor", AuctionHouseFrame) end
    frame = f
    f:SetPoint("TOPLEFT", results, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", results, "BOTTOMRIGHT", 0, 0)
    f:SetFrameLevel((results:GetFrameLevel() or 1) + 30)
    f:EnableMouse(true)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetPoint("TOPLEFT", 3, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetTexture("Interface\\QuestFrame\\UI-TextBackground-BackdropBackground")

    title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12)
    title:SetPoint("RIGHT", f, "RIGHT", -330, 0)
    title:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() Editor.Close() end)
    close:SetScript("OnEnter", function(self) Core.ShowTip(self, Core.Word("CLOSE"), L.EDITOR_CLOSE_TIP) end)
    close:SetScript("OnLeave", GameTooltip_Hide)
    Editor.closeButton = close

    local search = Button(f, L.EDITOR_SEARCH, 90, function() if list then ns.Buy.StartList(list) end end,
        L.EDITOR_SEARCH, L.LIST_SEARCH_TIP)
    search:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local delete = Button(f, Core.Word("DELETE"), 90, function()
        local current = list
        if not current then return end
        Core.Confirm(L.EDITOR_DELETE_CONFIRM:format(current.name), function()
            Lists().Delete(current)
            Editor.Close()
        end)
    end, Core.Word("DELETE"), L.EDITOR_DELETE_TIP)
    delete:SetPoint("RIGHT", search, "LEFT", -4, 0)
    local rename = Button(f, L.EDITOR_RENAME, 100, function()
        local current = list
        if not current then return end
        Core.AskText(L.EDITOR_RENAME_PROMPT, current.name, function(text)
            if not Lists().Rename(current, text) then ns.Print(L.EDITOR_NAME_TAKEN:format(text or "")) end
            Editor.Refresh()
        end)
    end, L.EDITOR_RENAME, L.EDITOR_RENAME_TIP)
    rename:SetPoint("RIGHT", delete, "LEFT", -4, 0)

    input = CreateFrame("EditBox", "ezAuctionListEditorInput", f, "InputBoxTemplate")
    input:SetSize(240, 20)
    input:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -44)
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

    local add = Button(f, L.EDITOR_ADD, 100, function()
        if not Editor.AddCursorItem() then Editor.Add(input:GetText()) end
    end, L.EDITOR_ADD, L.EDITOR_ADD_TIP)
    add:SetPoint("LEFT", input, "RIGHT", 8, 0)
    local fromSearch = Button(f, L.EDITOR_FROM_SEARCH, 130, Editor.AddCurrentSearch,
        L.EDITOR_FROM_SEARCH, L.EDITOR_FROM_SEARCH_TIP)
    fromSearch:SetPoint("LEFT", add, "RIGHT", 4, 0)
    editControls = { input, add, fromSearch }
    Editor.editControls = editControls   -- für Prüfungen

    hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", input, "BOTTOMLEFT", -6, -6)
    hint:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.EDITOR_HINT)

    -- Weitergeben als Text (AUC-20): unten rechts, unter der Liste der Einträge
    local import = Button(f, L.EDITOR_IMPORT, 100, function() Editor.Import() end, L.EDITOR_IMPORT, L.EDITOR_IMPORT_TIP)
    import:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
    local export = Button(f, L.EDITOR_EXPORT, 100, function() Editor.Export() end, L.EDITOR_EXPORT, L.EDITOR_EXPORT_TIP)
    export:SetPoint("RIGHT", import, "LEFT", -4, 0)
    Editor.importButton, Editor.exportButton = import, export

    -- Kostenvoranschlag der Liste (AH-10): unten links, neben den Knöpfen zum Weitergeben
    local cost = CreateFrame("Frame", nil, f)
    cost:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 10)
    cost:SetPoint("RIGHT", export, "LEFT", -8, 0)
    cost:SetHeight(18)
    cost:EnableMouse(true)
    cost.text = cost:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cost.text:SetAllPoints(cost)
    cost.text:SetJustifyH("LEFT")
    cost:SetScript("OnEnter", function(self) Core.ShowTip(self, L.LIST_COST_TITLE, L.LIST_COST_TIP) end)
    cost:SetScript("OnLeave", GameTooltip_Hide)
    Editor.cost = cost

    list = nil
    Editor.rows = ns.NewScrollList(f, 24, InitRow)
    Editor.rows:SetPoints(10, -92, -10, 34)
    emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -110)
    emptyText:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    emptyText:SetText(L.EDITOR_EMPTY)

    f:SetScript("OnReceiveDrag", Editor.AddCursorItem)
    f:SetScript("OnMouseUp", function() Editor.AddCursorItem() end)
    HookLinks()
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
    Editor.Open(lists[1])
    return true
end

function Editor.Refresh()
    if not frame or not list then return end
    title:SetText(L.EDITOR_TITLE:format(list.name))
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

function Editor.Open(target)
    if not (target and ns.ahReady and ns.AuctionHouseShown()) then return false end
    ns.ShowBrowseResults()
    if not frame then Build() end
    list = target
    ns.Buy.active = target
    Editor.Refresh()
    frame:Show()
    ns.Buy.Refresh()
    return true
end

function Editor.Close()
    if frame then frame:Hide() end
end

ns.Listen("LISTS_CHANGED", function()
    if not Editor.IsShown() then return end
    if not Lists().IndexOf(list) then return Editor.Close() end
    Editor.Refresh()
end)
ns.Listen("AH_MODE", function(mode)
    local _, browsing = ns.ModeName()
    if mode ~= "buy" or not browsing then Editor.Close() end
end)
ns.Listen("AH_HIDE", Editor.Close)
-- Neue Preise ändern den Kostenvoranschlag; Schalter blenden Knöpfe und Filter ein und aus
ns.Listen("PRICES_UPDATED", function() if Editor.IsShown() then Editor.Refresh() end end)
ns.OnSettingChanged(function(key)
    if (key == "rowSearch" or key == "listCost") and Editor.IsShown() then Editor.Refresh() end
end)
ns.OnAuctionHouse(function()
    if AuctionHouseFrame.SendBrowseQuery then
        hooksecurefunc(AuctionHouseFrame, "SendBrowseQuery", function() Editor.Close() end)
    end
end)
