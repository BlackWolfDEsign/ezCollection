local _, ns = ...
local L = ns.L

--[[
    Kleine Werkzeugleiste neben dem Suchfeld – gleich in Tasche, Bank, Gildenbank und ezBag-Fenster:
      Suchen (gespeicherte Suchen, bei allen Charakteren suchen), Tasche/Gruppe wählen (alles
      andere ausgrauen), Sortierung, alle Gruppen auf/zu, Umlagern (passende Stapel in die
      andere Seite legen, nur wenn die Gegenseite offen ist).
    Die Knöpfe sehen aus wie Blizzards Platz-Knöpfe (Ring, gedrückt, Leuchten). Leiste, Knöpfe, Tooltip,
    Anordnung und Breiten-Meldung kommen aus ezCore.Toolbar (ezCore/Bausteine/Layout.lua); „alle auf/zu“ ist
    Blizzards Plus/Minus als eigener Knopf in derselben Leiste. Hier stehen Inhalt, Menüs und Sichtbarkeit.
]]

local Toolbar = {}
ns.Toolbar = Toolbar

local SIZE, GAP = ezCore.LAYOUT.TOOL_SIZE, ezCore.LAYOUT.TOOL_GAP
Toolbar.SIZE, Toolbar.GAP = SIZE, GAP

local ICON_FOCUS = "Interface\\Icons\\INV_Misc_Bag_08"
local ICON_SORT = "Interface\\Icons\\INV_Misc_Note_01"
local ICON_TRANSFER = "Interface\\Icons\\INV_Crate_04"
local ICON_SEARCH = "Interface\\Icons\\INV_Misc_Spyglass_03"
local ICON_SPACE = "Interface\\Icons\\INV_Misc_Bag_07"
local ICON_SELECT = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ARROW = { left = "Interface\\MoneyFrame\\Arrow-Left-Up", right = "Interface\\MoneyFrame\\Arrow-Right-Up" }
Toolbar.ARROW = ARROW
-- Reihenfolge von links nach rechts (unsichtbare Knöpfe rücken zusammen).
local ORDER = { space = 1, transfer = 2, search = 3, focus = 4, sort = 5, select = 6, collapse = 7 }

local function Tip(owner, title, lines)
    ezCore.Toolbar.Tip(owner, title, lines)
end

local function InlineIcon(icon)
    if not icon then return "" end
    return "|T" .. icon .. ":14:14:0:0|t "
end

---------------------------------------------------------------------------
-- Leiste
---------------------------------------------------------------------------

local Bar = {}
Bar.__index = Bar

--[[
    opts = {
        viewKey = "bag" | "bank" | "guild",
        view    = function() return view end,
        bags    = function() return { { id, name, icon, free, total }, ... } end   (optional)
        transfer = "bag" | "bank" | "guild"   (Quelle beim Umlagern, optional)
        search  = function() return EditBox end   (Suchfeld des Fensters, optional: Knopf „Suchen“)
        allChars = true                           (Treffer bei anderen Charakteren am Suchknopf zählen)
        space   = true                            (Knopf „Platz schaffen“, wenn die Tasche fast voll ist)
        select  = true                            (Knopf „Auswählen“: Mehrfachauswahl, Select.lua)
    }
]]
function Toolbar.New(parent, opts)
    local self = setmetatable({ opts = opts }, Bar)
    -- Leiste aus ezCore: ordnet die sichtbaren Knöpfe an und meldet eine neue Breite (dann passt das
    -- Fenster sein Suchfeld an, einen Frame später, wie bisher).
    local bar = ezCore.Toolbar.New(parent, { size = SIZE, gap = GAP, onResize = function()
        if opts.onResize then C_Timer.After(0, opts.onResize) end
    end })
    self.bar = bar
    local frame = bar.frame
    self.frame = frame
    self.buttons = {}

    if opts.search then
        -- Zahl am Knopf: Treffer bei anderen Charakteren (Bank, Post, Twinks, Gildenbank) für die aktuelle Suche.
        self.search = bar:Add("search", { icon = ICON_SEARCH, order = ORDER.search, badge = true,
            onClick = function(b, mouse)
                if mouse == "RightButton" then return self:SetSearch("") end
                self:OpenSearchMenu(b)
            end,
            tooltip = function()
                local lines = { L.TB_SEARCH_TIP }
                local text = self:SearchText()
                if text ~= "" and opts.allChars then
                    local n = ns.Search.OtherCount(text)
                    lines[#lines + 1] = { n > 0 and L.TB_SEARCH_OTHERS:format(ns.CountWord("HIT", n)) or L.TB_SEARCH_OTHERS_NONE, ns.TipRGB("hint") }
                    -- Fundort (W-1811-ezBag): wo die Treffer liegen – Taschen der Twinks, Bank, Post, angelegt, Gildenbank;
                    -- immer, ohne Schalter (Einstellungs-Prüfung vom 19.11.2026: die Suchhilfe nie abschalten)
                    local where = n > 0 and ns.Search.OtherPlacesText(text)
                    if where then lines[#lines + 1] = { L.TB_SEARCH_PLACES:format(where), ns.TipRGB("hint") } end
                end
                lines[#lines + 1] = { L.TB_SEARCH_CLEAR, ns.TipRGB("hint") }
                return L.TB_SEARCH, lines
            end })
    end

    if opts.space then
        -- Platz schaffen (Space.lua): nur sichtbar, wenn die Tasche fast voll ist; rote Zahl = freie Plätze.
        local space = bar:Add("space", { icon = ICON_SPACE, order = ORDER.space,
            onClick = function(b, mouse)
                if mouse == "RightButton" then return ns.Space.OpenMenu(b) end
                ns.Space.SuggestCheapest()
            end,
            tooltip = function()
                local lines = { L.SPACE_TIP:format(ns.CountWord("SLOT", ns.Space.Free())) }
                local c = ns.Space.Candidates()[1]
                if c then lines[#lines + 1] = L.SPACE_NEXT:format(c.link or tostring(c.itemID)) end
                lines[#lines + 1] = { L.SPACE_RIGHT, ns.TipRGB("hint") }
                return L.SPACE_TITLE, lines
            end })
        space.free = space:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        space.free:SetDrawLayer("OVERLAY", 7)
        space.free:SetPoint("BOTTOMRIGHT", -1, 1)
        local r, g, b = ezCore.Style.Color("bad")   -- Blizzards RED_FONT_COLOR (Design-System 2.5)
        space.free:SetTextColor(r, g, b)   -- nur drei Werte: der vierte von Style.Color ist das Farbobjekt, nicht Alpha
        space:Hide()
        self.space = space
    end

    if opts.select then
        self.select = bar:Add("select", { icon = ICON_SELECT, order = ORDER.select, badge = true,
            onClick = function(b, mouse) ns.Select.OnToolbarClick(b, self:View(), mouse) end,
            tooltip = function() return L.SELECT_BUTTON, ns.Select.TooltipLines(self:View()) end })
    end

    self.focus = bar:Add("focus", { icon = ICON_FOCUS, order = ORDER.focus,
        onClick = function(b, mouse)
            if mouse == "RightButton" then return self:SetFocus(nil) end
            self:OpenFocusMenu(b)
        end,
        tooltip = function()
            local lines = { L.TB_FOCUS_TIP, L.TB_GROUP_EDIT_TIP }
            if self:CanRedock() then lines[#lines + 1] = L.TB_REDOCK_TIP end
            if self.opts.views then lines[#lines + 1] = L.TB_VIEW_TIP end
            lines[#lines + 1] = { L.TB_FOCUS_CLEAR, ns.TipRGB("hint") }
            if self.opts.views then lines[#lines + 1] = { ns.CmdText(L.TB_VIEW_CMD), ns.TipRGB("hint") } end
            return L.TB_FOCUS, lines
        end })

    self.sort = bar:Add("sort", { icon = ICON_SORT, order = ORDER.sort,
        onClick = function(b) self:OpenSortMenu(b) end,
        tooltip = function()
            local current = ns.S.sortMode or "type"
            local label = current
            for _, m in ipairs(ns.Render.SortModes()) do if m.key == current then label = m.label end end
            return L.TB_SORT, { L.TB_SORT_TIP:format(label), { L.TB_SORT_MENU, ns.TipRGB("hint") } }
        end })

    -- Alle Gruppen auf/zu: Blizzards Plus/Minus wie in Quest- und Berufslisten (eigener Knopf, die Leiste
    -- ordnet ihn nur an).
    local collapse = CreateFrame("Button", nil, frame)
    collapse:SetSize(SIZE, SIZE)
    collapse.tex = collapse:CreateTexture(nil, "ARTWORK")
    -- Plus/Minus in Blizzards Größe für kleine Knöpfe (16, Core.Style.BUTTON.small)
    collapse.tex:SetSize(ezCore.Style.BUTTON.small, ezCore.Style.BUTTON.small)
    collapse.tex:SetPoint("CENTER")
    local hl = collapse:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
    hl:SetBlendMode("ADD")
    hl:SetSize(ezCore.Style.BUTTON.small, ezCore.Style.BUTTON.small)
    hl:SetPoint("CENTER")
    collapse:SetScript("OnClick", function() self:ToggleAll() end)
    collapse:SetScript("OnEnter", function(b)
        Tip(b, self:AnyCollapsed() and L.MENU_EXPAND_ALL or L.MENU_COLLAPSE_ALL,
            { L.TB_COLLAPSE_TIP, { ns.CmdText(L.TB_COLLAPSE_CMD), ns.TipRGB("hint") } })
    end)
    collapse:SetScript("OnLeave", GameTooltip_Hide)
    self.collapse = bar:Add("collapse", { button = collapse, order = ORDER.collapse })

    if opts.transfer then
        local t = bar:Add("transfer", { icon = ICON_TRANSFER, order = ORDER.transfer,
            onClick = function(b, mouse)
                if mouse == "RightButton" then return self:OpenTransferMenu(b) end
                ns.Transfer.Run(opts.transfer)
            end,
            tooltip = function()
                local target = ns.Transfer.Target(opts.transfer)
                local moves, items = ns.Transfer.Count(opts.transfer)
                local lines = {}
                if target then
                    lines[1] = L.TB_TRANSFER_TIP:format(L["PLACE_" .. target])
                    lines[2] = { items > 0 and L.TB_TRANSFER_COUNT:format(ns.CountWord("SLOT", items), ns.CountWord("STEP", moves))
                        or L.TB_TRANSFER_NONE, ns.TipRGB("hint") }
                end
                lines[#lines + 1] = { L.TB_TRANSFER_MENU, ns.TipRGB("hint") }
                lines[#lines + 1] = { ns.CmdText(L.TB_TRANSFER_CMD), ns.TipRGB("hint") }
                return L.TB_TRANSFER, lines
            end })
        t.arrow = t:CreateTexture(nil, "OVERLAY", nil, 3)
        t.arrow:SetSize(ezCore.Style.ICON.line, ezCore.Style.ICON.line)   -- Symbol in Zeilengröße (16, Core.Style)
        t.arrow:SetPoint("CENTER", 0, 0)
        self.transfer = t
    end

    frame:SetScript("OnShow", function() self:Update() end)
    local view = self:View()
    if view then view.toolbar = self end
    self:Update()
    return self
end

function Bar:View()
    return self.opts.view and self.opts.view() or nil
end

-- Sichtbare Knöpfe von links nach rechts anordnen; gibt die Breite zurück.
-- Sichtbarkeit der Knöpfe festlegen (Umlagern nur mit offener Gegenseite, Platz schaffen nur bei voller
-- Tasche); anordnen und die Breite melden macht ezCores Leiste. Gibt die Breite zurück.
function Bar:Layout()
    if self.transfer then
        self.transfer:SetShown(ns.Transfer.Target(self.opts.transfer) ~= nil)
    end
    if self.space then
        local show = ns.Space.ShouldShow()
        self.space:SetShown(show)
        if show then self.space.free:SetText(ns.Space.Free()) end
    end
    local width = self.bar:Layout()
    self.width = width
    return width
end

function Bar:Width()
    return self.frame:GetWidth() or SIZE
end

function Bar:AnyCollapsed()
    local view = self:View()
    if not view then return false end
    for _, key in ipairs(view:AllKeys()) do
        if ns.Groups.IsCollapsed(self.opts.viewKey, key) then return true end
    end
    return false
end

function Bar:ToggleAll()
    local view = self:View()
    if not view then return end
    ns.Groups.SetAllCollapsed(self.opts.viewKey, view:AllKeys(), not self:AnyCollapsed())
    self:Update()
end

function Bar:Update()
    local any = self:AnyCollapsed()
    local base = any and "Interface\\Buttons\\UI-PlusButton-" or "Interface\\Buttons\\UI-MinusButton-"
    self.collapse.tex:SetTexture(base .. "Up")
    local view = self:View()
    local focus = view and view.focus
    self.focus.active:SetShown(focus ~= nil)
    self.focus.icon:SetTexture(focus and focus.icon or ICON_FOCUS)
    if self.transfer then
        local side = ns.Transfer.ArrowSide(self.opts.transfer)
        self.transfer.arrow:SetTexture(side and ARROW[side] or nil)
    end
    self:UpdateSearchBadge()
    self:UpdateSelect()
    return self:Layout()
end

-- Suchfeld des Fensters (Blizzards bzw. das eigene im ezBag-Fenster).
function Bar:SearchBox()
    return self.opts.search and self.opts.search() or nil
end

function Bar:SearchText()
    local box = self:SearchBox()
    return box and strtrim(box:GetText() or "") or ""
end

function Bar:SetSearch(text)
    local box = self:SearchBox()
    if not box then return end
    box:SetText(text or "")
    if box.ClearFocus then box:ClearFocus() end
    self:UpdateSearchBadge()
end

-- Zahl am Suchknopf: Treffer bei anderen Charakteren (nur, wenn gesucht wird).
function Bar:UpdateSearchBadge()
    local s = self.search
    if not s then return end
    local text = self:SearchText()
    local n = (text ~= "" and self.opts.allChars) and ns.Search.OtherCount(text) or 0
    s.badge:SetText(n > 0 and (n > 99 and "99+" or tostring(n)) or "")
    s.active:SetShown(text ~= "")
end

function Bar:SetFocus(focus)
    local view = self:View()
    if not view then return end
    view:SetFocus(focus)
    self:Update()
end

-- Eintrag „Tasche wieder andocken“ anbieten? In Tasche, Bank und Gildenbank, solange die Tasche abgedockt ist und
-- Bank oder Gildenbank offen stehen (Layout.CanRedockBag); nicht im ezBag-Fenster.
function Bar:CanRedock()
    return self.opts.viewKey ~= "window" and ns.Layout ~= nil and ns.Layout.CanRedockBag ~= nil and ns.Layout.CanRedockBag() == true
end

-- Fokus und Auswahl aufheben, z. B. wenn das Fenster schließt.
function Bar:ClearFocus()
    local view = self:View()
    if view and ns.Select and ns.Select.IsActive(view) then ns.Select.SetActive(view, false) end
    if view and view.focus then
        view.focus = nil
        self:Update()
    end
end

-- Knopf „Auswählen“: leuchtet, solange die Auswahl an ist; Zahl = markierte Plätze.
function Bar:UpdateSelect()
    local b = self.select
    if not b then return end
    local view = self:View()
    local on = view ~= nil and ns.Select.IsActive(view)
    b.active:SetShown(on)
    local n = on and ns.Select.Count(view) or 0
    b.badge:SetText(n > 0 and tostring(n) or "")
end

---------------------------------------------------------------------------
-- Menüs
---------------------------------------------------------------------------

--[[
    „Tasche, Gruppe oder Bank“:
      Alles zeigen
      Tasche hervorheben ▸ (Gildenbank: Fach wechseln ▸)   – aktuelle Wahl steht im Namen
      Gruppe hervorheben ▸
      Tasche wieder andocken (nur, solange sie abgedockt ist und Bank oder Gildenbank offen stehen)
      Unterwegs ansehen: Bank, Gildenbank, alles auch Twinks (Stand vom letzten Besuch)
]]
function Bar:OpenFocusMenu(owner)
    local view = self:View()
    if not view then return end
    local focus = view.focus
    local function Is(value)
        local f = view.focus
        if value == "" then return f == nil end
        return f ~= nil and (f.kind .. ":" .. tostring(f.kind == "bag" and f.bag or f.key)) == value
    end
    local function Current(label, name)
        return name and (label .. ": " .. ezCore.White(name)) or label
    end

    ezCore.Menu.Open(owner, function(root)
        root:CreateTitle(L.TB_FOCUS)
        root:CreateRadio(L.TB_FOCUS_ALL, Is, function() self:SetFocus(nil) end, "")

        -- Taschen bzw. Fächer
        local bags = self.opts.bags and self.opts.bags() or {}
        if #bags > 0 then
            local chosen
            for _, bag in ipairs(bags) do
                if (self.opts.pickBag and bag.checked) or (focus and focus.kind == "bag" and focus.bag == bag.id) then
                    chosen = bag.name
                end
            end
            local sub = root:CreateButton(Current(self.opts.bagsTitle or L.TB_FOCUS_BAGS, chosen))
            for _, bag in ipairs(bags) do
                local text = InlineIcon(bag.icon) .. bag.name
                if bag.total and bag.total > 0 then
                    text = text .. " " .. ezCore.Grey(L.TB_FREE:format(bag.free or 0, bag.total))
                end
                if self.opts.pickBag then
                    -- Gildenbank: ein Fach wählen heißt dorthin wechseln (wie Blizzards Reiter).
                    sub:CreateRadio(text, function() return bag.checked == true end,
                        function() self.opts.pickBag(bag) end, "bag:" .. tostring(bag.id))
                else
                    sub:CreateRadio(text, Is, function()
                        self:SetFocus({ kind = "bag", bag = bag.id, icon = bag.icon })
                    end, "bag:" .. tostring(bag.id))
                end
            end
        end

        -- Gruppen
        local out = view.out
        if out then
            local list, seen, chosen = {}, {}, nil
            local function Add(g)
                if seen[g.groupKey] or #g.entries == 0 then return end
                seen[g.groupKey] = true
                list[#list + 1] = g
                if focus and focus.kind == "group" and focus.key == g.groupKey then chosen = g.label end
            end
            for _, g in ipairs(out.groups) do Add(g) end
            for _, g in ipairs(out.chips) do Add(g) end
            if #list > 0 then
                local sub = root:CreateButton(Current(L.TB_FOCUS_GROUPS, chosen))
                for _, g in ipairs(list) do
                    sub:CreateRadio(g.label .. " " .. ezCore.Grey("(" .. #g.entries .. ")"), Is, function()
                        if ns.Groups.IsCollapsed(self.opts.viewKey, g.groupKey) then
                            ns.Groups.ToggleCollapsed(self.opts.viewKey, g.groupKey)
                        end
                        self:SetFocus({ kind = "group", key = g.groupKey })
                    end, "group:" .. g.groupKey)
                end
                -- Gruppe „Neu“ leeren, ohne die Tasche zu schließen (auch per Rechtsklick auf ihren Titel)
                if seen.new then root:CreateButton(L.MENU_CLEAR_NEW, function() ns.Groups.ClearNew() end) end
            end
            -- Gruppe anpassen (umbenennen, Sortierung, unterteilen, Regeln, neue Gruppe …): dasselbe Menü wie
            -- per Rechtsklick auf den Gruppentitel, hier über einen sichtbaren Knopf (V-044). Auch leere Gruppen.
            local all = {}
            for _, g in ipairs(out.groups) do all[#all + 1] = g end
            for _, g in ipairs(out.chips) do all[#all + 1] = g end
            ns.Groups.AddEditMenu(root, self.opts.viewKey, all, view:AllKeys())
        end

        -- Abgedockte Tasche wieder neben Bank bzw. Gildenbank stellen – sonst nur per Rechtsklick auf die Titelleiste
        -- der Tasche (BAG-11, Leitlinie 3).
        if self:CanRedock() then
            root:CreateDivider()
            root:CreateButton(L.TB_REDOCK, function() ns.Layout.RedockBag() end)
        end

        -- Bank und Gildenbank unterwegs ansehen (ezBag-Fenster, Stand vom letzten Besuch).
        local views = self.opts.views and self.opts.views() or {}
        if #views > 0 then
            root:CreateDivider()
            root:CreateTitle(L.TB_VIEW)
            for _, v in ipairs(views) do root:CreateButton(InlineIcon(v.icon) .. v.text, v.func) end
        end
    end)
end

--[[
    „Suchen“:
      Schnellsuche: Nutzbar, BoE, Rezept, Neu (Neu = Gruppe „Neu“ hervorheben)
      Gespeicherte Suchen (eigene), aktuelle Suche speichern, gespeicherte löschen ▸
      Bei allen Charakteren suchen (ezBag-Fenster: alle Twinks, Bank, Post, Gildenbank)
]]
function Bar:OpenSearchMenu(owner)
    local current = self:SearchText()
    local view = self:View()
    ezCore.Menu.Open(owner, function(root)
        root:CreateTitle(L.TB_SEARCH_QUICK)
        for _, preset in ipairs(ns.Search.Presets()) do
            root:CreateButton(preset.label, function() self:SetSearch(preset.text) end)
        end
        local hasNew = false
        if view and view.out then
            for _, g in ipairs(view.out.groups) do if g.groupKey == "new" then hasNew = true end end
        end
        if hasNew then
            root:CreateButton(L.CAT_new, function()
                self:SetSearch("")
                self:SetFocus({ kind = "group", key = "new" })
            end)
        end

        local saved = ns.Search.Saved()
        if #saved > 0 then
            root:CreateDivider()
            root:CreateTitle(L.TB_SEARCH_SAVED)
            for _, text in ipairs(saved) do
                root:CreateButton(text, function() self:SetSearch(text) end)
            end
        end
        root:CreateDivider()
        if current ~= "" and not ns.Search.IsSaved(current) then
            root:CreateButton(L.TB_SEARCH_SAVE:format(current), function() ns.Search.Save(current) end)
        end
        if #saved > 0 then
            local del = root:CreateButton(L.TB_SEARCH_DELETE)
            for _, text in ipairs(saved) do
                del:CreateButton(text, function() ns.Search.Remove(text) end)
            end
        end
        if self.opts.allChars then
            local n = current ~= "" and ns.Search.OtherCount(current) or 0
            local label = current ~= "" and L.TB_SEARCH_ALL_N:format(n) or L.TB_SEARCH_ALL
            root:CreateButton(label, function() ns.Window.OpenSearch(current) end)
        end
        if current ~= "" then
            root:CreateButton(L.TB_SEARCH_CLEAR_MENU, function() self:SetSearch("") end)
        end
    end)
end

function Bar:OpenSortMenu(owner)
    local function Is(mode) return (ns.S.sortMode or "type") == mode end
    -- Über ns.SetSetting wie jede Einstellung (V-058); neu geordnet wird beim Zuhörer in Layout.lua.
    local function Set(mode) ns.SetSetting("sortMode", mode) end
    ezCore.Menu.Open(owner, function(root)
        root:CreateTitle(L.TB_SORT_ALL)
        for _, mode in ipairs(ns.Render.SortModes()) do
            root:CreateRadio(mode.label, Is, Set, mode.key)
        end
        if ns.Groups.AnyOwnSort() then
            root:CreateDivider()
            root:CreateButton(L.TB_SORT_RESET, function() ns.Groups.ClearOwnSort() end)
        end
        -- Layout-Profile je Charakter oder Klasse (Profiles.lua)
        if ns.Profiles then
            root:CreateDivider()
            ns.Profiles.AddMenu(root)
        end
        root:CreateDivider()
        root:CreateCheckbox(L.OPT_compactStacks, function() return ns.S.compactStacks end,
            function() ns.SetSetting("compactStacks", not ns.S.compactStacks) end)
        root:CreateTitle(L.TB_SORT_HINT)
    end)
end

function Bar:OpenTransferMenu(owner)
    local source = self.opts.transfer
    ezCore.Menu.Open(owner, function(root)
        root:CreateTitle(L.TB_TRANSFER)
        local target = ns.Transfer.Target(source)
        if target then
            root:CreateButton(L.TB_TRANSFER_DO:format(L["PLACE_" .. source], L["PLACE_" .. target]),
                function() ns.Transfer.Run(source) end)
            root:CreateButton(L.TB_TRANSFER_DO:format(L["PLACE_" .. target], L["PLACE_" .. source]),
                function() ns.Transfer.Run(target) end)
            root:CreateDivider()
        end
        root:CreateCheckbox(L.OPT_transferArrows, function() return ns.S.transferArrows end,
            function() ns.SetSetting("transferArrows", not ns.S.transferArrows) end)
        root:CreateCheckbox(L.OPT_transferStacksOnly, function() return ns.S.transferStacksOnly end,
            function() ns.SetSetting("transferStacksOnly", not ns.S.transferStacksOnly) end)
    end)
end
