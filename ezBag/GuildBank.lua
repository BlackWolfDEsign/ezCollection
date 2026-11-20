local _, ns = ...
local L = ns.L

--[[
    Gruppiert die originale Gildenbank (GuildBankFrame) direkt im Blizzard-Fenster,
    genau wie Tasche und Bank: gleiche Plätze, gleicher Rahmen, gleiche Reiter,
    gleiches Geld- und Protokollfeld – nur die 98 Plätze des aktuellen Reiters stehen
    im Fließ-Layout mit Gruppenrahmen (Render.lua).

    Blizzards Platz-Raster ist auf den Spalten-Hintergrund gemalt. Den blenden wir
    aus und geben jedem Platz dasselbe Original-Feld aus dieser Grafik mit.
    Passt der Inhalt nicht in die Fläche, werden die Plätze etwas kleiner (bis 70 %),
    das Fenster selbst bleibt unverändert.
    Taint-sicher: nur hooksecurefunc/HookScript, keine Werte in Blizzards Tabellen.
]]

local GuildBank = {}
ns.GuildBank = GuildBank

local CHECK_INTERVAL = 0.2
local SPACING = 5
local SEARCH_Y = 27          -- Suchzeile gleich unter der Titelleiste (wie in der Bank)
local MIN_HEIGHT = 200
local NUM_COLUMNS, PER_COLUMN = 7, 14
local MIN_SCALE, SCALE_STEP = 0.7, 0.05
local SLOT_SHEET = "Interface\\GuildBankFrame\\UI-GuildBankFrame-Slots"
local SLOT_COORDS = { 3 / 128, 48 / 128, 0, 44 / 512 }   -- ein Feld aus dem Spalten-Hintergrund

local frame, holder, view, toolbar
local installed, dirty, applying = false, false, false
local lastSignature, lastTab, lastMode   -- lastMode: eigener Merker statt eines Felds in GuildBankFrame
local concealed = setmetatable({}, { __mode = "k" })
local slotArt = setmetatable({}, { __mode = "k" })
local clickHooked = setmetatable({}, { __mode = "k" })
-- Eine Fassung für Bank und Gildenbank: Render.NewRegionStore (hier mit Skalierung; Breite nur beim Suchfeld).
local store = ns.Render.NewRegionStore({ scale = true, widthOf = "EditBox" })
local saved = store.saved

local function Save(region) store.Save(region) end
local function RestoreSaved() store.Restore() end

---------------------------------------------------------------------------
-- Höhe (wie die Bank: genau so hoch wie der Inhalt)
---------------------------------------------------------------------------

local based   -- { h = Blizzards Höhe, set = unsere }

-- Blizzard setzt das Feld "Verbleibende Entnahmen" fest 378 unter die Oberkante.
-- Bei geänderter Höhe zählt derselbe Abstand vom Boden aus.
local function FixLimitAnchor()
    local lim = frame and frame.TabLimitBG
    if not (based and lim) then return end
    local p, rel, rp, x, y = lim:GetPoint(1)
    if p and rp == "TOP" and rel == frame then
        Save(lim)
        lim:ClearAllPoints()
        lim:SetPoint(p, frame, "BOTTOM", x or 0, based.h + (y or 0))
    end
end

local function SetFrameHeight(h)
    local cur = frame:GetHeight()
    if not based then based = { h = cur } end
    if math.abs(cur - h) > 0.5 then frame:SetHeight(h) end
    based.set = h
    FixLimitAnchor()
end

local function RestoreHeight()
    if not based then return end
    if based.set and math.abs(frame:GetHeight() - based.set) < 0.5 then frame:SetHeight(based.h) end
    based = nil
end

---------------------------------------------------------------------------
-- Suchzeile (wie die Bank: Fachname links, Suchfeld über die ganze Breite, Leiste rechts)
---------------------------------------------------------------------------

local function FitTopRow()
    local x = 14
    local bg, bgL, bgR = frame.TabTitleBG, frame.TabTitleBGLeft, frame.TabTitleBGRight
    if bg and bg:IsShown() and frame.TabTitle and frame.TabTitle:IsShown() then
        local capL = bgL and bgL:GetWidth() or 8
        Save(bg)
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", x + capL, -(SEARCH_Y + 1))
        x = x + capL + (bg:GetWidth() or 0) + (bgR and bgR:GetWidth() or 8) + 8
    end
    local barW = toolbar and toolbar:Update() or 0
    if toolbar then
        toolbar.frame:ClearAllPoints()
        toolbar.frame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -(SEARCH_Y - 1))
        toolbar.frame:Show()
    end
    local box = _G.GuildItemSearchBox
    if box then
        Save(box)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", frame, "TOPLEFT", x + 4, -SEARCH_Y)
        box:SetWidth(math.max(60, (frame:GetWidth() or 0) - x - 4 - (12 + barW + 8)))
    end
end

-- Fächer der Gildenbank für "Tasche wählen" – ein Klick wechselt das Fach wie Blizzards Reiter.
local function GuildTabs()
    local list = {}
    local n = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    local current = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
    for i = 1, n do
        local name, icon, viewable = GetGuildBankTabInfo(i)
        if viewable then
            list[#list + 1] = { id = i, name = name or (L.PLACE_guild .. " " .. i), icon = icon, checked = (i == current) }
        end
    end
    return list
end

local function PickTab(bag)
    local tab = (frame.BankTabs and frame.BankTabs[bag.id]) or _G["GuildBankTab" .. bag.id]
    if tab and tab.OnClick then tab:OnClick("LeftButton", false) end
end

local function Buttons()
    local list = {}
    for c = 1, NUM_COLUMNS do
        local col = frame.Columns and frame.Columns[c]
        for i = 1, PER_COLUMN do
            local b = col and col.Buttons and col.Buttons[i]
            if b then list[#list + 1] = b end
        end
    end
    return list
end

local function Visible()
    return frame and frame:IsShown() and frame.Columns and frame.Columns[1] and frame.Columns[1]:IsShown()
        and (frame.mode == nil or frame.mode == "bank")
end

---------------------------------------------------------------------------
-- Klicks und Zeigen
---------------------------------------------------------------------------

local function ItemAt(slot)
    local tab = GetCurrentGuildBankTab()
    local texture, count, locked, _, quality = GetGuildBankItemInfo(tab, slot)
    if not texture then return nil end
    local link = GetGuildBankItemLink(tab, slot)
    local itemID = ezCore.ItemID(link)   -- V-176: gesperrt oder leer → nil
    if not itemID then return nil end
    return itemID, link, quality, count or 1, locked
end

local function OnItemClick(button, mouse)
    if mouse ~= "RightButton" or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    local itemID, link, quality = ItemAt(button:GetID())
    if itemID then ns.Groups.OpenItemMenuFor(button, itemID, link, quality) end
end

local function HookButton(button)
    if clickHooked[button] then return end
    clickHooked[button] = true
    button:HookScript("OnClick", OnItemClick)
    ns.Render.HookHover(button, view)
end

-- Das Original-Feld aus dem Spalten-Hintergrund für einen einzelnen Platz.
local function SlotArt(button)
    local tex = slotArt[button]
    if not tex then
        tex = button:CreateTexture(nil, "BACKGROUND", nil, -7)
        tex:SetTexture(SLOT_SHEET)
        tex:SetTexCoord(unpack(SLOT_COORDS))
        tex:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 3)
        tex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
        slotArt[button] = tex
    end
    local bg = frame.Columns[1].Background
    if tex.SetDesaturated and bg and bg.IsDesaturated then tex:SetDesaturated(bg:IsDesaturated()) end
    tex:Show()
    return tex
end

---------------------------------------------------------------------------
-- Anordnen
---------------------------------------------------------------------------

-- Fläche der Original-Spalten (in Fensterkoordinaten von oben links).
local function Area()
    local c1, c7 = frame.Columns[1], frame.Columns[NUM_COLUMNS]
    local fl, ft = frame:GetLeft(), frame:GetTop()
    local l, t, r, b = c1:GetLeft(), c1:GetTop(), c7:GetRight(), c7:GetBottom()
    if not (fl and ft and l and t and r and b) then return nil end
    return { left = l - fl, top = ft - t - 2, right = r - fl, bottom = ft - b + 2 }
end

-- Suchtext: Blizzards Gildenbank-Suche, sonst die der Tasche (beide filtern dieselbe Suche).
local function SearchText()
    local box = _G.GuildItemSearchBox
    local text = box and box:GetText() or ""
    if text == "" and _G.BagItemSearchBox then text = _G.BagItemSearchBox:GetText() or "" end
    return text
end

local function Searching()
    return SearchText() ~= ""
end

local function BuildGroups(buttons)
    local groups, byKey = {}, {}
    local tab = GetCurrentGuildBankTab()
    for _, button in ipairs(buttons) do
        HookButton(button)
        local slot = button:GetID()
        local itemID, link, quality, count = ItemAt(slot)
        local key = "empty"
        -- guildTab: Fach des Platzes – die Auswahl markiert damit je Platz und entnimmt genau diesen (Select.lua).
        local entry = { button = button, slot = slot, order = slot, sig = slot, guildTab = tab }
        if itemID then
            key = ns.ClassifyItem({ itemID = itemID, link = link, quality = quality, name = ns.ItemName(link) })
            entry.itemID, entry.link, entry.quality = itemID, link, quality or 1
            entry.name, entry.count = ns.ItemName(link) or "", count
        end
        local group = byKey[key] or ns.Render.NewGroup(groups, byKey, key, key)
        group.entries[#group.entries + 1] = entry
    end
    ns.Render.AddEmptyCustomGroups(groups, byKey)
    ns.Render.SortGroups(groups)
    return groups
end

-- Itemlevel und Marken (Marks.lua) auf den sichtbaren Plätzen.
local function UpdateMarks()
    for _, entry in ipairs(view.entries) do
        ns.SetItemMarks(entry.button, entry.itemID, entry.link, entry.quality, nil)
    end
end

local function DoLayout(fromBlizzard)
    dirty = false
    if not Visible() then return end
    local buttons = Buttons()
    if #buttons == 0 then return end
    FitTopRow()
    local area = Area()
    if not area then return end

    local groups = BuildGroups(buttons)
    local w, h = buttons[1]:GetSize()
    w, h = (w and w > 0) and w or 37, (h and h > 0) and h or 37
    local width = area.right - area.left
    local searching = Searching()

    -- Oben: gleich unter der Suchzeile. Unten: Blizzards Fuß (Geld, Knöpfe, Entnahmen) bleibt,
    -- das Fenster wird so hoch wie der Inhalt – wie die Bank.
    local top = math.min(area.top, SEARCH_Y + 20 + 2)
    local baseH = based and based.h or frame:GetHeight()
    local footH = baseH - area.bottom
    local screenH = UIParent:GetHeight() * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    local maxArea = math.max(area.bottom - area.top, screenH - 80 - top - footH)

    -- Nur wenn selbst das größte Fenster nicht reicht, werden die Plätze kleiner.
    local out, scale, sp
    local s = 1
    while true do
        sp = math.max(3, math.floor(SPACING * s + 0.5))
        local cw, ch = w * s, h * s
        local cols = math.max(1, math.floor((width + sp) / (cw + sp)))
        out = ns.Render.Flow(groups, { cols = cols, w = cw, h = ch, spX = sp, spY = sp },
            { viewKey = "guild", searching = searching })
        scale = s
        if out.totalH <= maxArea or s - SCALE_STEP < MIN_SCALE - 0.001 then break end
        s = s - SCALE_STEP
    end

    local tab = GetCurrentGuildBankTab()
    local signature = ns.Render.Signature(out, tab .. ":" .. scale .. ":" .. math.floor(width) .. ":" .. top)
    if not fromBlizzard and signature == lastSignature then return end
    lastSignature = signature
    SetFrameHeight(math.max(MIN_HEIGHT, math.ceil(top + out.totalH + footH + 2)))
    area.top = top

    for c = 1, NUM_COLUMNS do
        local bg = frame.Columns[c].Background
        if bg then
            Save(bg)
            bg:SetAlpha(0)
        end
    end

    local originX = area.left + math.floor((width - out.width) / 2)
    local originY = area.top
    local function Place(region, left, top)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", frame, "TOPLEFT", originX + left, -(originY + top))
    end

    local level = buttons[1]:GetFrameLevel()
    holder:SetFrameLevel(math.max(1, level - 2))
    view:Draw(out, Place, function(entry, shown, left, top, g)
        local button = entry.button
        Save(button)
        ns.SetFreeCount(button, nil)
        if shown then
            button:SetScale(scale)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", frame, "TOPLEFT", (originX + left) / scale, -(originY + top) / scale)
            concealed[button] = nil
            ns.RevealButton(button)
            SlotArt(button)
            if g.compressed then ns.SetFreeCount(button, g.count) end
            ns.SetStackTotal(button, entry.stackTotal)
        else
            concealed[button] = true
            ns.ConcealButton(button, holder)
            ns.SetStackTotal(button, nil)
        end
    end)
    view:SetLevel(math.max(1, level - 1))
    view:ApplyDim()
    if searching then
        C_Timer.After(0, function() view:ExtendSearch(SearchText()) end)
    end
    UpdateMarks()
    ns.Transfer.Refresh()
end

function GuildBank.RefreshMarks()
    if view and frame and not GuildBank.Blocked() and Visible() then UpdateMarks() end
end

local function Restore()
    for button in pairs(concealed) do ns.RevealButton(button) end
    wipe(concealed)
    for _, tex in pairs(slotArt) do tex:Hide() end
    if view then
        for _, entry in ipairs(view.entries) do
            if entry.button then
                ns.Render.SetDimmed(entry.button, false)
                ns.SetFreeCount(entry.button, nil)
                ns.SetStackTotal(entry.button, nil)
            end
        end
        view:HideAll()
        view.focus = nil
    end
    RestoreHeight()
    RestoreSaved()
    if toolbar then toolbar.frame:Hide() end
    lastSignature = nil
end

-- Werkzeugleiste und Ansicht der Gildenbank (nil, solange Blizzards Gildenbank nicht geladen ist).
function GuildBank.Toolbar() return toolbar end
function GuildBank.View() return view end

function GuildBank.Blocked()
    return not ns.S or not ns.S.guildGrouping or not frame
end

function GuildBank.Apply(fromBlizzard)
    if applying or not frame then return end
    if GuildBank.Blocked() then
        if lastSignature or next(concealed) then Restore() end
        return
    end
    if not Visible() then
        -- Protokoll, Geldprotokoll, Fachinfo: Blizzards Original (Höhe, Titel, Suche).
        if lastSignature or next(saved) then Restore() end
        return
    end
    applying = true
    local ok, err = pcall(DoLayout, fromBlizzard)
    applying = false
    if not ok then geterrorhandler()(err) end
end

function GuildBank.Refresh(force)
    if not frame or not frame:IsShown() then
        lastSignature = nil
        return
    end
    if force then
        lastSignature = nil
        GuildBank.Apply(false)
    else
        dirty = true
    end
end

local function CanRelayoutNow()
    return ns.Render.CanRelayout(frame, ns.Transfer.Running())
end

-- Nach Blizzards Update: neuer Reiter oder anderer Modus sofort, sonst sanft verzögert.
local function AfterUpdate()
    local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
    local mode = frame.mode
    if tab ~= lastTab or mode ~= lastMode then
        lastTab, lastMode = tab, mode
        lastSignature = nil
        GuildBank.Apply(true)
    else
        dirty = true
    end
end

local function Install()
    if installed then return end
    frame = _G.GuildBankFrame
    if not frame or not frame.Columns or not frame.Update then
        frame = nil
        return
    end
    installed = true

    holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints()
    holder:SetScript("OnUpdate", ns.Render.DeferredUpdate(function() return dirty end, function()
        if CanRelayoutNow() then GuildBank.Apply(false) end
    end, CHECK_INTERVAL))
    view = ns.Render.NewView(holder, "guild")
    toolbar = ns.Toolbar.New(frame, {
        viewKey = "guild",
        view = function() return view end,
        bags = GuildTabs,
        bagsTitle = L.TB_FOCUS_TABS,
        pickBag = PickTab,
        views = function() return ns.Window and ns.Window.ViewEntries("guild") or {} end,
        transfer = "guild",
        -- Auswählen wie in der Bank (V-051): markieren, einer Gruppe zuweisen und „In die Tasche legen (n)“ – das
        -- entnimmt die markierten Plätze über Transfer.WithdrawSlots (Entnahme-Limit des Rangs). Verkaufen und
        -- Umlegen per „Benutzen“ gibt es hier nicht (Select.LiveSlots).
        select = true,
        search = function() return _G.GuildItemSearchBox end,
        allChars = true,
        onResize = function() if not GuildBank.Blocked() and Visible() then FitTopRow() end end,
    })
    toolbar.frame:SetFrameLevel(frame:GetFrameLevel() + 20)
    toolbar.frame:Hide()
    ns.Transfer.Register("guild", view, frame, toolbar)
    -- Verschieben wie die Bank (Titelleiste ziehen, Position merken, Rechtsklick: zurücksetzen).
    ns.Layout.InstallPanelMover(frame)

    hooksecurefunc(frame, "Update", AfterUpdate)
    -- Fachname und Entnahme-Feld setzt Blizzard hier neu (Breite/Anker): wieder einpassen.
    if frame.UpdateTabs then
        hooksecurefunc(frame, "UpdateTabs", function()
            if GuildBank.Blocked() or not Visible() then return end
            FitTopRow()
            FixLimitAnchor()
        end)
    end
    if frame.UpdateFiltered then
        hooksecurefunc(frame, "UpdateFiltered", function()
            if GuildBank.Blocked() or not Visible() then return end
            view:ApplyDim()
            if toolbar then toolbar:UpdateSearchBadge() end
            if Searching() then
                C_Timer.After(0, function() view:ExtendSearch(SearchText()) end)
            end
        end)
    end
    -- Wie die Bank: Blizzards Bank öffnet beim Öffnen alle Taschen (und schließt sie wieder),
    -- die Gildenbank nicht. Damit die Tasche auch hier gleich daneben andockt, holen wir das nach.
    frame:HookScript("OnShow", function(self)
        lastTab, lastSignature = nil, nil
        -- Über ezCore (ein Ort für Blizzards Fenster-Funktionen, V-047): nur außerhalb des Kampfes, ohne Hinweis
        -- (kein Klick des Nutzers).
        if ns.S.dockBank then ezCore.OpenPanel("bags", self, true) end
        C_Timer.After(0, function()
            GuildBank.Apply(true)
            ns.Layout.Reposition()
        end)
    end)
    frame:HookScript("OnHide", function(self)
        dirty = false
        lastSignature, lastTab = nil, nil
        ns.Render.CancelDrag()
        if toolbar then toolbar:ClearFocus() end
        if ns.S.dockBank then ezCore.ClosePanel("bags", self, true) end
    end)
end

ns.OnReady(function()
    if _G.GuildBankFrame then Install() end
end)
ns.On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_GuildBankUI" and ns.S then Install() end
end)
ns.On("GUILDBANKFRAME_OPENED", function()
    Install()
    C_Timer.After(0, function() GuildBank.Apply(true) end)
end)
ns.On("INVENTORY_SEARCH_UPDATE", function()
    if frame and frame:IsShown() and not GuildBank.Blocked() then GuildBank.Refresh(true) end
end)

ns.OnSettingChanged(function(key)
    if key == "guildGrouping" or key == "compressEmpty" then
        if key == "guildGrouping" and not ns.S.guildGrouping then
            Restore()
        else
            GuildBank.Refresh(true)
        end
    end
end)
