local _, ns = ...
local L = ns.L
local Menu = ezCore.Menu     -- Menüs an einer Stelle (Blizzards MenuUtil)

--[[
    Posteingang sortieren und durchsuchen: Seitenreiter (Lupe) rechts am Posteingang. Er öffnet ein
    Menü mit allen Briefen – nicht nur den sieben dieser Seite –, sortiert nach Eingang, Absender,
    Gegenstand, Restzeit oder Wert der Anhänge (ezCore-Preis-Wissen) und gefiltert nach einem
    Suchbegriff (Absender, Betreff, Anhänge; mehrere Wörter müssen alle passen). Ein Häkchen wählt
    den Brief für „Öffnen“ und „Zurück“ in der Leiste aus, „Treffer auswählen“ alle gefundenen auf einmal.
    Blizzards Liste selbst bleibt unverändert (ihre Reihenfolge kommt vom Server).
]]

local Overview = {}
ns.Overview = Overview

Overview.SORTS = { "inbox", "sender", "item", "time", "value" }

local query = ""                  -- Suchbegriff dieses Besuchs
local tab

local function SortKey()
    local key = ns.db and ns.db.overviewSort
    for _, k in ipairs(Overview.SORTS) do if k == key then return key end end
    return "inbox"
end

function Overview.SetSort(key) ns.db.overviewSort = key end
function Overview.SetQuery(text) query = ezCore.Trim(text or "") end
-- Suchbegriff dieses Besuchs ("" = keiner): für die Statuszeile unten und die Prüfungen (MAIL-04)
function Overview.Query() return query end

-- Alle Briefe mit Anhangnamen: { index, h, items = { { name, count } }, value = Wert oder nil, source = Quelle und
-- Alter der Preise (MAIL-08, Inbox.MergeSource) oder nil, text = Suchtext klein }
function Overview.Letters()
    local list = {}
    for index = 1, (ns.NumMails()) do
        local h = ns.Header(index)
        if h then
            local entry = { index = index, h = h, items = {} }
            local words = { h.sender, h.subject }
            if h.items > 0 then
                for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
                    local name, _, _, count = GetInboxItem(index, attachment)
                    if name then
                        entry.items[#entry.items + 1] = { name = name, count = count or 1 }
                        words[#words + 1] = name
                    end
                end
            end
            local _
            entry.value, _, entry.source = ns.Inbox.Value(index)
            entry.text = table.concat(words, "\031"):lower()
            list[#list + 1] = entry
        end
    end
    return list
end

local function Matches(entry, words)
    for _, word in ipairs(words) do
        if not entry.text:find(word, 1, true) then return false end
    end
    return true
end

local SORTERS = {
    sender = function(a, b)
        local x, y = a.h.sender:lower(), b.h.sender:lower()
        if x ~= y then return x < y end
        return a.index < b.index
    end,
    item = function(a, b)
        local x, y = a.items[1], b.items[1]
        if (x ~= nil) ~= (y ~= nil) then return x ~= nil end          -- Briefe ohne Anhang ans Ende
        if x and y and x.name:lower() ~= y.name:lower() then return x.name:lower() < y.name:lower() end
        return a.index < b.index
    end,
    time = function(a, b)
        if a.h.daysLeft ~= b.h.daysLeft then return a.h.daysLeft < b.h.daysLeft end
        return a.index < b.index
    end,
    value = function(a, b)                                            -- wertvollste zuerst, ohne Preis ans Ende
        if (a.value ~= nil) ~= (b.value ~= nil) then return a.value ~= nil end
        if a.value and b.value and a.value ~= b.value then return a.value > b.value end
        return a.index < b.index
    end,
}

-- Quelle und ältestes Alter der Preise einer Liste von Briefen (MAIL-08), nil ohne Preis.
function Overview.SourceOf(entries)
    local source
    for _, entry in ipairs(entries or {}) do
        if entry.value then source = ns.Inbox.MergeSource(source, entry.source) end
    end
    return source
end

-- Gefilterte und sortierte Briefe. Rückgabe: Treffer, Anzahl aller Briefe.
function Overview.List(text, sort)
    local all = Overview.Letters()
    local words = {}
    for word in (text or ""):lower():gmatch("%S+") do words[#words + 1] = word end
    local shown = {}
    for _, entry in ipairs(all) do
        if #words == 0 or Matches(entry, words) then shown[#shown + 1] = entry end
    end
    local sorter = SORTERS[sort or "inbox"]
    if sorter then table.sort(shown, sorter) end
    return shown, #all
end

-- Eine Menüzeile: Absender (Farbe nach Regel) – Betreff [Anhang] · Gold · Restzeit
function Overview.EntryText(entry)
    local h = entry.h
    local sender = h.sender
    local rule = ns.Rules.Get(sender)
    if rule == "trust" or (not rule and ns.Rules.IsOwn(sender)) then
        sender = ezCore.Style.ColorText("good", sender)   -- vertraut: Blizzards Grün (Design-System 2.5)
    elseif rule then
        sender = ezCore.Style.ColorText("bad", sender)    -- andere Regel: Blizzards Rot
    end
    local parts = { sender .. " – " .. h.subject }
    local first = entry.items[1]
    if first then
        local item = first.name .. (first.count > 1 and (" x" .. first.count) or "")
        if #entry.items > 1 then item = item .. " +" .. (#entry.items - 1) end
        parts[#parts + 1] = ezCore.Style.ColorText("highlight", "[" .. item .. "]")
    end
    local text = table.concat(parts, " ")
    if entry.value then text = text .. " · " .. L.OV_VALUE:format(ns.CoinText(entry.value)) end
    if h.money > 0 then text = text .. " · " .. ns.CoinText(h.money) end
    if h.cod > 0 then text = text .. " · " .. L.OV_COD:format(ns.CoinText(h.cod)) end
    return text .. " · " .. ezCore.Duration(h.daysLeft * 86400, true)
end

---------------------------------------------------------------------------
-- Menü
---------------------------------------------------------------------------

local function Reopen(owner)
    C_Timer.After(0, function()
        if InboxFrame and InboxFrame:IsVisible() then Overview.ShowMenu(owner) end
    end)
end

local function AskSearch(owner)
    ezCore.AskText(L.OV_SEARCH_PROMPT, query, function(text)
        Overview.SetQuery(text)
        Reopen(owner)
    end)
end

-- AH-33: Zeile „Auktionspost: …“ mit der Liste je Gegenstand im Tooltip (abgeschalteter Knopf, denn Blizzards
-- Titelzeilen nehmen keine Maus an) und darunter „Auktionspost abholen“ – derselbe Lauf wie an der Zeile über der
-- Briefliste (Inbox.TakeAuctionMail). Nichts, wenn der Schalter aus ist oder keine Auktionspost im Briefkasten liegt.
-- Rückgabe: die Zeile oder nil (für die Prüfungen).
function Overview.AddAuctionMail(root, busy)
    if not ns.S.auctionMail then return nil end
    local info = ns.Inbox.AuctionMail()
    local text = ns.Inbox.AuctionLineText(info)
    if not text then return nil end
    Menu.Divider(root)
    local line = Menu.Button(root, text)
    if type(line) == "table" and line.SetEnabled then line:SetEnabled(false) end
    if Menu.Tip then Menu.Tip(line, L.AHMAIL_TITLE, ns.Inbox.AuctionTipText(info)) end
    local take = Menu.Button(root, L.AHMAIL_TAKE, function() ns.Inbox.TakeAuctionMail() end)
    if busy and type(take) == "table" and take.SetEnabled then
        take:SetEnabled(false)
        if Menu.Tip then Menu.Tip(take, L.AHMAIL_TAKE, L.RUN_BUSY_TIP) end   -- Grund am gesperrten Eintrag (T9-7)
    end
    return line
end

function Overview.ShowMenu(owner)
    local sort = SortKey()
    local shown, total = Overview.List(query, sort)
    local busy = ns.Runner.IsBusy()
    local selectable = ns.S.selectBoxes and not busy
    local opened = Menu.Open(owner, function(root)
        if root.SetScrollMode and #shown > 20 then root:SetScrollMode(26 * 20) end
        Menu.Title(root, query ~= "" and L.OV_TITLE_FOUND:format(#shown, total) or L.OV_TITLE:format(total))
        Menu.Button(root, query ~= "" and L.OV_SEARCH_ACTIVE:format(query) or L.OV_SEARCH, function() AskSearch(owner) end)
        if query ~= "" then
            Menu.Button(root, L.OV_SEARCH_CLEAR, function()
                Overview.SetQuery("")
                Reopen(owner)
            end)
        end
        -- Die Sortierung ordnet die Liste darunter neu: Menü schließen (Menu.Close) und neu öffnen.
        local sortMenu = Menu.Button(root, L.OV_SORT:format(L["OV_SORT_" .. sort]))
        local function SetSort(key)
            Overview.SetSort(key)
            Reopen(owner)
            return Menu.Close()
        end
        for _, key in ipairs(Overview.SORTS) do Menu.Radio(sortMenu, L["OV_SORT_" .. key], SortKey, SetSort, key) end
        Overview.AddAuctionMail(root, busy)

        Menu.Divider(root)
        if #shown == 0 then Menu.Title(root, query ~= "" and L.OV_NONE_FOUND or L.OV_EMPTY) end
        -- MAIL-08: eine Zeile mit Quelle und ältestem Alter aller gezeigten Preise; je Brief steht sie im Tooltip
        local sourceLine = ns.Inbox.SourceText(Overview.SourceOf(shown))
        if sourceLine then Menu.Title(root, L.OV_VALUE_SOURCE:format(sourceLine)) end
        -- Design-System 2.11: ein Haken „Alle“ über den Briefen (ab drei); eine Auswahl für eine
        -- Handlung (Öffnen), sie wird nicht gemerkt (2.12, Ausnahme)
        if selectable and #shown >= 3 then
            Menu.AllToggle(root, shown, function(entry) return ns.Inbox.IsSelected(entry.index) end,
                function(entry, on) ns.Inbox.SetSelected(entry.index, on) end,
                { onTip = L.OV_ALL_CHECK_TIP, offTip = L.OV_ALL_UNCHECK_TIP,
                  after = function() ns.Inbox.Refresh() end })
        end
        for _, entry in ipairs(shown) do
            local index = entry.index
            local row
            if selectable then
                row = Menu.Toggle(root, Overview.EntryText(entry), function() return ns.Inbox.IsSelected(index) end,
                    function(on)
                        ns.Inbox.SetSelected(index, on)
                        ns.Inbox.Refresh()
                    end)
            end
            local rowSource = entry.value and ns.Inbox.SourceText(entry.source)
            if not row and rowSource and Menu.Tip then
                -- Blizzards Titelzeilen nehmen keine Maus an; ein abgeschalteter Knopf zeigt den Tooltip trotzdem
                -- (SetMotionScriptsWhileDisabled im ButtonInitializer der Forever-Quelle)
                row = Menu.Button(root, Overview.EntryText(entry))
                if type(row) == "table" and row.SetEnabled then row:SetEnabled(false) end
            elseif not row then
                row = Menu.Title(root, Overview.EntryText(entry))
            end
            if rowSource and Menu.Tip then
                Menu.Tip(row, L.VALUE_TOOLTIP:format(ns.CoinText(entry.value)), L.VALUE_SOURCE:format(rowSource))
            end
        end

        Menu.Divider(root)
        if not ns.S.selectBoxes then
            Menu.Title(root, L.OV_NEED_SELECT)
            return
        end
        local wanted = {}
        for _, entry in ipairs(shown) do wanted[entry.index] = true end
        local pick = Menu.Button(root, L.OV_SELECT:format(#shown), function() ns.Inbox.SelectIndexes(wanted) end)
        if #shown == 0 or busy then
            pick:SetEnabled(false)
            -- Grund am gesperrten Eintrag (T9-7); ohne Briefe sagt es die Zeile darüber
            if busy and Menu.Tip then Menu.Tip(pick, L.OV_SELECT:format(#shown), L.RUN_BUSY_TIP) end
        end
        if ns.Inbox.Count() > 0 then
            local clear = Menu.Button(root, L.OV_UNSELECT, ns.Inbox.ClearSelection)
            if busy then
                clear:SetEnabled(false)
                if Menu.Tip then Menu.Tip(clear, L.OV_UNSELECT, L.RUN_BUSY_TIP) end
            end
        end
    end)
    if not opened then ns.Print(L.NO_MENU) end
end

---------------------------------------------------------------------------
-- Seitenreiter rechts am Posteingang
---------------------------------------------------------------------------

local function UpdateTab()
    if not tab then return end
    local on = ns.S.overview and true or false
    tab:SetShown(on)
    if on then
        local n = ns.NumMails()
        tab.Count:SetText(n > 0 and n or "")
    end
end
Overview.UpdateTab = UpdateTab

local function CreateTab()
    if tab or not InboxFrame then return end
    -- Lage über ezCores Seitenreiter-Stapel am Postfenster (vereinbart: Übersicht 10, Verlauf 20, erster bei -48):
    -- sichtbare Reiter stehen lückenlos, auch die anderer Module.
    tab = ns.CreateSideTab(InboxFrame, { key = "ezMail.overview", order = 10, anchor = MailFrame or InboxFrame,
        start = -48, owner = "ezMail" })
    tab.Icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    tab:SetScript("OnClick", ns.SideTabClick(function(self) Overview.ShowMenu(self) end))
    tab:SetScript("OnEnter", function(self)
        local text = L.OV_TAB_TIP
        if query ~= "" then text = text .. "\n" .. L.OV_TAB_QUERY:format(query) end
        ns.ShowTip(self, L.OV_TAB_TITLE, text)
    end)
    UpdateTab()
end

function Overview.Tab() return tab end

ns.WhenMailUI("Übersicht", CreateTab)
ns.On("MAIL_INBOX_UPDATE", UpdateTab)
ns.On("MAIL_SHOW", function() query = "" end)
ns.OnSettingChanged(function(key)
    if key == "overview" then UpdateTab() end
end)
ns.OnStatus(function()
    local search = Overview.Query()
    return L.STATUS_OVERVIEW:format(tab and (tab:IsShown() and L.YES or L.STATUS_HIDDEN) or L.STATUS_MISSING_PART, SortKey(),
        search ~= "" and search or L.STATUS_OVERVIEW_NO_SEARCH)
end)
