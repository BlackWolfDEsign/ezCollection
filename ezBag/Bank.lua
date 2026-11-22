local _, ns = ...
local L = ns.L

--[[
    Gruppiert die originale Bank (BankFrame.BankPanel von WoW Forever) direkt im
    Blizzard-Fenster, genau wie die Tasche: gleiche Plätze, gleicher Hintergrund,
    nur im Fließ-Layout mit Gruppenrahmen (Render.lua).

    Die Spaltenzahl, Platzgröße und Abstände lesen wir aus der fertigen Anordnung
    von Blizzard (oder von ClassicUI, wenn dessen Bank-Stil an ist). Braucht unser
    Layout mehr oder weniger Höhe, passen wir die Fensterhöhe an – auch mit ClassicUIs
    Bank-Stil (wir setzen sie nach ClassicUI jedes Mal absolut aus dem Layout).
    Taint-sicher: nur hooksecurefunc/HookScript, keine Werte in Blizzards Tabellen.

    TOC „## OptionalDeps: ClassicUIForever, Leatrix_Plus, BetterBags“ – Gründe nach der Regel für OptionalDeps
    (docs/ezcore.md, „Gerüst-Dienste“; Gesamtreview 18.11.2026, T4-8; Prüfung Welle 4, docs/roadmap/uebergreifend.md):
      ClassicUIForever  Grund (b): ClassicUI baut Taschen- und Bankrahmen beim Laden um; ezBags Haken und die
                        Fensterhöhe oben setzen danach auf (ezBag lädt nach ClassicUI).
      Leatrix_Plus,     Kandidaten „nur Erkennung“: ezBag fragt beide zur Laufzeit über ezCore (Core.OtherAddOn,
      BetterBags        ns.OtherFor) und greift beim Laden auf nichts von ihnen zu. Die Einträge entfallen erst nach
                        der Spielprüfung, weil sich die Ladereihenfolge ändert (docs/roadmap/ezBag.md, „Im Spiel prüfen“).
]]

local Bank = {}
ns.Bank = Bank

local CHECK_INTERVAL = 0.2
local SPACING = 5        -- wie in der Tasche
local INSET = 10         -- Innenrand der Bank links und rechts
local SEARCH_X, SEARCH_Y = 60, 33   -- Suchzeile: vom Porträt bis zur Werkzeugleiste (Blizzards Höhe)
local FOOT_X, FOOT_GAP = 12, 4      -- Fußzeile: Taschenplätze, Kosten, Kaufen

local panel, bankFrame, holder, view, toolbar, countText
local installed, dirty, applying = false, false, false
local lastSignature
local blizz                    -- zuletzt gelesene Anordnung von Blizzard/ClassicUI
local sized                    -- { panelBase, frameBase, panelSet, frameSet }
local clickHooked = setmetatable({}, { __mode = "k" })
local concealed = setmetatable({}, { __mode = "k" })

-- Ursprüngliche Ankerpunkte, Größen und Sichtbarkeit von allem, was wir umstellen.
-- Eine Fassung für Bank und Gildenbank: Render.NewRegionStore.
local store = ns.Render.NewRegionStore()
local saved = store.saved
local function Save(region) store.Save(region) end
local function RestoreSaved() store.Restore() end
local function Fade(region)
    if not region then return end
    Save(region)
    region:SetAlpha(0)
end

-- Behälter der Bank (Grundfach und Taschenfächer) mit Namen und Symbol.
local function BankTabs()
    local list = {}
    for i, data in ipairs(panel and panel.purchasedBankTabData or {}) do
        local id = data.ID
        if type(id) == "number" then
            local name = data.name
            if not name or name == "" then name = C_Container.GetBagName(id) or (L.PLACE_bank .. " " .. i) end
            list[#list + 1] = { id = id, name = name, icon = data.icon,
                free = C_Container.GetContainerNumFreeSlots(id) or 0, total = C_Container.GetContainerNumSlots(id) or 0 }
        end
    end
    return list
end

function Bank.ContainerIDs()
    local ids, seen = {}, {}
    for _, tab in ipairs(BankTabs()) do
        ids[#ids + 1] = tab.id
        seen[tab.id] = true
    end
    if #ids == 0 and panel and panel.itemButtonPool then
        for button in panel.itemButtonPool:EnumerateActive() do
            local ok, id = pcall(button.GetBankTabID, button)
            if ok and type(id) == "number" and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

-- Bankplätze wie am Rucksack: frei und gesamt über alle gekauften Fächer.
function Bank.SlotSpace()
    local free, total = 0, 0
    for _, id in ipairs(Bank.ContainerIDs()) do
        total = total + (C_Container.GetContainerNumSlots(id) or 0)
        free = free + (C_Container.GetContainerNumFreeSlots(id) or 0)
    end
    return free, total
end

local function ActiveButtons()
    local list = {}
    if not (panel and panel.itemButtonPool and panel.itemButtonPool.EnumerateActive) then return list end
    for button in panel.itemButtonPool:EnumerateActive() do
        if button.GetBankTabID and button.GetContainerSlotID then list[#list + 1] = button end
    end
    return list
end

local function SlotOf(button)
    local okTab, tab = pcall(button.GetBankTabID, button)
    local okSlot, slot = pcall(button.GetContainerSlotID, button)
    if okTab and okSlot and type(tab) == "number" and type(slot) == "number" then return tab, slot end
end

---------------------------------------------------------------------------
-- Klicks und Zeigen
---------------------------------------------------------------------------

local function OnItemClick(button, mouse)
    -- Rechtsklick auf zusammengefasste Stapel: die übrigen Stapel folgen Blizzards einem in die Tasche (Stacks.lua)
    if ns.Stacks.OnItemClick(view, button, mouse) then return end
    if mouse ~= "RightButton" or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
    local bag, slot = SlotOf(button)
    if not bag then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local itemID = ns.ItemIDOf(info)
    if itemID then ns.Groups.OpenItemMenuFor(button, itemID, info.hyperlink, info.quality) end
end

local function HookButton(button)
    if clickHooked[button] then return end
    clickHooked[button] = true
    button:HookScript("OnClick", OnItemClick)
    ns.Render.HookHover(button, view)
end

---------------------------------------------------------------------------
-- Geometrie lesen
---------------------------------------------------------------------------

local function Distinct(values)
    table.sort(values)
    local out = {}
    for _, v in ipairs(values) do
        if #out == 0 or v - out[#out] > 1.5 then out[#out + 1] = v end
    end
    return out
end

-- Blizzards (bzw. ClassicUIs) Raster auslesen, bevor wir etwas verschieben.
local function Capture(buttons)
    local pLeft, pTop = panel:GetLeft(), panel:GetTop()
    if not pLeft or not pTop or #buttons == 0 then return nil end
    local w, h = buttons[1]:GetSize()
    if not w or w <= 0 then w, h = 37, 37 end
    local xs, ys = {}, {}
    for _, b in ipairs(buttons) do
        if not concealed[b] then
            local l, t = b:GetLeft(), b:GetTop()
            if l and t then
                xs[#xs + 1] = l - pLeft
                ys[#ys + 1] = pTop - t
            end
        end
    end
    if #xs == 0 then return nil end
    local cx, cy = Distinct(xs), Distinct(ys)
    local spX = (#cx > 1) and math.max(0, (cx[2] - cx[1]) - w) or 5
    local spY = (#cy > 1) and math.max(0, (cy[2] - cy[1]) - h) or 5
    -- Spalten: so viele wie in Blizzards Breite passen (Blizzard hat teils breitere Lücken).
    local gridW = cx[#cx] + w - cx[1]
    local cols = math.max(1, math.floor((gridW + spX) / (w + spX) + 0.01))
    return {
        left = cx[1], top = cy[1], w = w, h = h, spX = spX, spY = spY, cols = cols,
        gridW = gridW, gridH = cy[#cy] + h - cy[1],
    }
end

-- Unterkante des Bank-Suchfelds, gemessen von der Oberkante des Bank-Inhalts.
local function SearchBottom()
    local box = _G.BankItemSearchBox
    if not (box and box:IsVisible()) then return nil end
    local bottom, top = box:GetBottom(), panel:GetTop()
    if not bottom or not top then return nil end
    return (top - bottom) * (box:GetEffectiveScale() / panel:GetEffectiveScale())
end

--[[
    Höhe um delta ändern, ausgehend von der jetzigen Höhe. delta wird jedes Mal aus dem
    fertigen Layout gemessen (Unterkante der Gruppen bis zur Fußzeile), das Ergebnis ist
    also absolut: Setzt Blizzard oder ClassicUI die Höhe zwischendurch neu, landen wir
    beim nächsten Durchgang trotzdem genau wieder auf der passenden Höhe.
]]
local function SetHeights(delta)
    if math.abs(delta) < 0.5 then return end
    local ph, fh = panel:GetHeight(), bankFrame:GetHeight()
    if not sized then sized = { panelBase = ph, frameBase = fh } end
    local newP, newF = math.max(ph + delta, 120), math.max(fh + delta, 160)
    panel:SetHeight(newP)
    bankFrame:SetHeight(newF)
    sized.panelSet, sized.frameSet = newP, newF
end

local function RestoreHeights()
    if not sized then return end
    if sized.panelSet and math.abs(panel:GetHeight() - sized.panelSet) < 0.5 then panel:SetHeight(sized.panelBase) end
    if sized.frameSet and math.abs(bankFrame:GetHeight() - sized.frameSet) < 0.5 then bankFrame:SetHeight(sized.frameBase) end
    sized = nil
end

---------------------------------------------------------------------------
-- Suchzeile und Fußzeile
---------------------------------------------------------------------------

-- Abstand einer Region zur Unterkante der Bank (in Bank-Koordinaten).
local function FromBottom(region, edge)
    local v = edge == "top" and region:GetTop() or region:GetBottom()
    local fb = bankFrame:GetBottom()
    if not v or not fb then return nil end
    return (v * region:GetEffectiveScale() - fb * bankFrame:GetEffectiveScale()) / bankFrame:GetEffectiveScale()
end

local function Shown(region)
    return region and region:IsShown() and region:GetAlpha() > 0.05
end

--[[
    Suchzeile wie in der Tasche: Name des Bankfachs links, dann das Suchfeld über
    die ganze Breite, Blizzards Sortierknopf und unsere Werkzeugleiste rechts.
]]
local function FitTopRow()
    local box = _G.BankItemSearchBox
    if not box then return end
    local fw = bankFrame:GetWidth() or 0
    local x = SEARCH_X
    local header = panel.Header
    if header and header:IsShown() and header.Text then
        local tw = math.ceil(header.Text:GetStringWidth() or 0)
        if tw > 0 then
            Save(header)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", bankFrame, "TOPLEFT", x, -SEARCH_Y)
            header:SetSize(tw + 4, 20)
            x = x + tw + 12
        end
    end
    -- „belegt/gesamt (frei)“ gleich hinter dem Fachnamen, gefärbt wie am Rucksack; ein Schalter für Rucksack und Bank
    -- (bagCount, Einstellungs-Prüfung vom 19.11.2026, Nr. 56/57).
    if ns.S.bagCount then
        local free, total = Bank.SlotSpace()
        if total > 0 then
            if not countText then
                countText = bankFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
            end
            countText:ClearAllPoints()
            countText:SetPoint("LEFT", bankFrame, "TOPLEFT", x, -(SEARCH_Y + 10))
            countText:SetText(("%d/%d (%d)"):format(total - free, total, free))
            countText:SetTextColor(ns.SpaceColor(free, total))
            countText:Show()
            x = x + math.ceil(countText:GetStringWidth() or 0) + 10
        elseif countText then
            countText:Hide()
        end
    elseif countText then
        countText:Hide()
    end
    -- ClassicUIs Überschrift "Gegenstandsplätze" läge mitten in der Suchzeile.
    local fcui = bankFrame.fcui
    if fcui and fcui.itemSlotsTitle then Fade(fcui.itemSlotsTitle) end

    local barW = toolbar and toolbar:Update() or 0
    local sort = panel.AutoSortButton
    local sortW = (sort and sort:IsShown()) and (sort:GetWidth() + 8) or 0
    Save(box)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", bankFrame, "TOPLEFT", x + 4, -SEARCH_Y)
    box:SetWidth(math.max(60, fw - x - 4 - (INSET + barW + 2 + sortW)))
    if toolbar then
        toolbar.frame:ClearAllPoints()
        if sort and sort:IsShown() then
            toolbar.frame:SetPoint("LEFT", sort, "RIGHT", 2, 0)
        else
            toolbar.frame:SetPoint("LEFT", box, "RIGHT", 8, 0)
        end
        toolbar.frame:Show()
    end
end

--[[
    Forevers Bank hat eine Trennlinie (mit Raute am Ende) zwischen Plätzen und
    Taschenfächern, fest in der alten Höhe. Nach dem Zusammenrücken der Fußzeile läge
    sie quer durch die Plätze. ClassicUI blendet sie in seinem Bank-Stil ebenfalls aus;
    die Gruppenrahmen trennen Plätze und Fußzeile schon.
]]
local function HideDividers(top)
    local function Scan(frame, depth)
        for _, r in ipairs({ frame:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" and r.GetAtlas then
                local atlas = r:GetAtlas()
                if type(atlas) == "string" and not ns.IsSecret(atlas) and atlas:lower():find("divider", 1, true) then
                    Fade(r)
                end
            end
        end
        if depth > 0 then
            for _, child in ipairs({ frame:GetChildren() }) do Scan(child, depth - 1) end
        end
    end
    Scan(bankFrame, 2)
    return top
end

local function BagSlotButtons()
    local list = {}
    if not bankFrame.itemButtonBagPool then return list end
    for button in bankFrame.itemButtonBagPool:EnumerateActive() do list[#list + 1] = button end
    table.sort(list, function(a, b) return (tonumber(a.bagSlotID) or 0) < (tonumber(b.bagSlotID) or 0) end)
    return list
end

--[[
    Fußzeile zusammenrücken: "Taschenplätze" und die Taschenfächer in einer Reihe
    gleich über dem Geld, Kosten und Kaufen-Knopf daneben – passt das nicht in die
    Breite, links neben das Geld, sonst in eine zweite Reihe dicht darüber.
    Gibt die Höhe der Fußzeile (von der Unterkante der Bank) zurück.
]]
local function CompactFoot()
    local bags = BagSlotButtons()
    local money = panel.MoneyFrame
    local moneyTop = (money and money:IsShown() and FromBottom(money, "top")) or 26
    local moneyBottom = (money and money:IsShown() and FromBottom(money, "bottom")) or 4
    local moneyMid = (moneyTop + moneyBottom) / 2
    local moneyLeft = money and money:IsShown() and money:GetLeft() and bankFrame:GetLeft()
        and (money:GetLeft() - bankFrame:GetLeft()) or nil
    local fw = bankFrame:GetWidth() or 0
    if #bags == 0 then return moneyTop + FOOT_GAP end

    local bw, bh = bags[1]:GetSize()
    bw, bh = bw or 37, bh or 37
    local rowY = moneyTop + FOOT_GAP
    local mid = rowY + bh / 2
    local x = FOOT_X

    -- Beschriftung: ClassicUIs eigene oder Blizzards.
    local fcui = bankFrame.fcui
    local label = (fcui and Shown(fcui.bagSlotsTitle) and fcui.bagSlotsTitle) or (Shown(bankFrame.BagText) and bankFrame.BagText)
    if label then
        Save(label)
        label:SetWidth(0)   -- so breit wie der Text (Blizzards Feld ist teils schmaler als die große Schrift)
        label:ClearAllPoints()
        label:SetPoint("LEFT", bankFrame, "BOTTOMLEFT", x, mid)
        local lw = math.max(label:GetStringWidth() or 0,
            label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or 0)
        x = x + math.ceil(lw) + 8
    end
    -- Die Fächer hängen direkt am Text: stimmt die gemessene Breite nicht, rutschen sie trotzdem nicht darüber.
    for i, b in ipairs(bags) do
        Save(b)
        b:ClearAllPoints()
        if i == 1 and label then
            b:SetPoint("LEFT", label, "RIGHT", 8, 0)
        elseif i == 1 then
            b:SetPoint("BOTTOMLEFT", bankFrame, "BOTTOMLEFT", x, rowY)
        else
            b:SetPoint("LEFT", bags[i - 1], "RIGHT", SPACING, 0)
        end
    end
    local rowEnd = x + #bags * (bw + SPACING) - SPACING
    local top = rowY + bh + FOOT_GAP

    -- Kosten und Kaufen.
    local buy = panel.PurchaseButton
    if not (buy and buy:IsShown()) then return HideDividers(top) end
    local cost = Shown(bankFrame.BagCost) and bankFrame.BagCost or nil
    local price = panel.MoneyDisplay and panel.MoneyDisplay:IsShown() and panel.MoneyDisplay or nil
    -- ClassicUIs Hinweistext am Kaufen-Knopf braucht eine eigene Reihe – weg damit.
    local own = buy.GetFontString and buy:GetFontString()
    for _, region in ipairs({ buy:GetRegions() }) do
        if region ~= own and region.GetObjectType and region:GetObjectType() == "FontString" then Fade(region) end
    end
    -- Sichtbare Breite eines Geldfelds (das Feld selbst ist oft breiter als „1 Gold“).
    local function MoneyWidth(mf)
        local w, name = 0, mf:GetName()
        for _, key in ipairs({ "GoldButton", "SilverButton", "CopperButton" }) do
            local b = rawget(mf, key) or (name and _G[name .. key])
            if type(b) == "table" and b.IsShown and b:IsShown() then w = w + (b:GetWidth() or 0) + 2 end
        end
        return w > 0 and w or (mf:GetWidth() or 0)
    end
    local costW = cost and (math.ceil(cost:GetStringWidth() or 0) + 6) or 0
    local priceW = price and (math.ceil(MoneyWidth(price)) + 8) or 0
    -- Kaufen-Knopf so schmal wie sein Text (Blizzards Breite ist für längere Sprachen gedacht),
    -- damit alles in die Zeile der Taschenfächer passt.
    Save(buy)
    local fullW = saved[buy].w or buy:GetWidth() or 100
    local tightW = own and math.max(64, math.ceil((own:GetStringWidth() or 0) + 28)) or fullW
    tightW = math.min(fullW, tightW)
    local ROW_GAP = 14

    -- Eine Zeile: Kosten und Kaufen direkt hinter dem letzten Fach (hängt daran, rutscht also nie darüber).
    local function ChainAfter(anchor)
        local prev, gap = anchor, ROW_GAP
        for _, region in ipairs({ cost or false, price or false, buy }) do
            if region then
                Save(region)
                region:ClearAllPoints()
                region:SetPoint("LEFT", prev, "RIGHT", gap, 0)
                prev = region
                gap = (region == cost) and 6 or 8
            end
        end
    end

    -- Auch in der zweiten Zeile schmal: Kosten, Preis und Kaufen eng beieinander.
    buy:SetWidth(tightW)
    if fw - INSET - rowEnd - ROW_GAP >= costW + priceW + tightW then
        ChainAfter(bags[#bags])                             -- eine Zeile
        return HideDividers(top)
    end
    local groupW = costW + priceW + tightW

    local function PlaceGroup(left, y)
        local cx = left
        if cost then
            Save(cost)
            cost:ClearAllPoints()
            cost:SetPoint("LEFT", bankFrame, "BOTTOMLEFT", cx, y)
            cx = cx + costW
        end
        if price then
            Save(price)
            price:ClearAllPoints()
            price:SetPoint("LEFT", bankFrame, "BOTTOMLEFT", cx, y)
            cx = cx + priceW
        end
        Save(buy)
        buy:ClearAllPoints()
        buy:SetPoint("LEFT", bankFrame, "BOTTOMLEFT", cx, y)
    end

    if moneyLeft and FOOT_X + groupW + 8 <= moneyLeft then
        PlaceGroup(FOOT_X, moneyMid)                        -- neben dem Geld
    else
        local bh2 = math.max(buy:GetHeight() or 22, 22)
        PlaceGroup(FOOT_X, top + bh2 / 2)                   -- zweite Reihe, dicht darüber
        top = top + bh2 + FOOT_GAP
    end
    return HideDividers(top)
end

---------------------------------------------------------------------------
-- Anordnen
---------------------------------------------------------------------------

local function Searching()
    local box = _G.BankItemSearchBox
    return box and box:IsVisible() and (box:GetText() or "") ~= "" or false
end

-- Itemlevel, BoE und Marken (Marks.lua) auf den sichtbaren Plätzen.
local function UpdateMarks()
    for _, entry in ipairs(view.entries) do
        local b = entry.button
        local info = entry.bag and C_Container.GetContainerItemInfo(entry.bag, entry.slot)
        ns.SetItemMarks(b, info and info.itemID, info and info.hyperlink, info and info.quality,
            info and info.isBound == true, entry.bag, entry.slot)
    end
end

function Bank.RefreshMarks()
    if view and bankFrame and bankFrame:IsShown() and not Bank.Blocked() then UpdateMarks() end
end

local function DoLayout(fromBlizzard)
    dirty = false
    local buttons = ActiveButtons()
    if #buttons == 0 then return end
    if fromBlizzard or not blizz then
        local captured = Capture(buttons)
        if captured then blizz = captured end
    end
    if not blizz then return end

    local slots = {}
    for _, button in ipairs(buttons) do
        HookButton(button)
        local bag, slot = SlotOf(button)
        if bag then slots[#slots + 1] = { button = button, bag = bag, slot = slot } end
    end
    local groups = ns.GroupsFromSlots(slots, false)

    --[[
        Einheitlich mit der Tasche: gleiche Platzgröße und 5er-Abstände. Breite: der
        ganze Innenraum der Bank (mindestens Blizzards Raster), zentriert. Oben: gleich
        unter dem Suchfeld der Bank. Unten: bis wo Blizzards Raster endete.
    ]]
    local w, h = blizz.w, blizz.h
    local panelW = panel:GetWidth() or 0
    local innerL = math.min(blizz.left, INSET)
    local innerR = math.max(blizz.left + blizz.gridW, panelW - INSET)
    local cols = math.max(1, math.floor((innerR - innerL + SPACING) / (w + SPACING)))
    local out = ns.Render.Flow(groups, { cols = cols, w = w, h = h, spX = SPACING, spY = SPACING },
        { viewKey = "bank", searching = Searching() })

    FitTopRow()
    local top = blizz.top - math.floor(SPACING / 2)
    local below = SearchBottom()
    if below and below + 2 < top then top = below + 2 end
    -- Unten: bis zur zusammengerückten Fußzeile (sonst bis Blizzards Rasterende).
    local bottomLimit = blizz.top + blizz.gridH + math.ceil(SPACING / 2)
    local footTop = CompactFoot()
    local pTop, fBottom = panel:GetTop(), bankFrame:GetBottom()
    if footTop and pTop and fBottom then
        bottomLimit = (pTop * panel:GetEffectiveScale() - fBottom * bankFrame:GetEffectiveScale())
            / panel:GetEffectiveScale() - footTop - 2
    end

    local signature = ns.Render.Signature(out, cols .. ":" .. math.floor(top) .. ":" .. math.floor(bottomLimit))
    if not fromBlizzard and signature == lastSignature then return end
    lastSignature = signature

    -- Höhe anpassen: genau bis zur Fußzeile, ohne freie Fläche – auch mit ClassicUIs Bank-Stil
    -- (dessen Höhe setzen wir nach ihm jedes Mal neu, siehe SetHeights).
    SetHeights(math.ceil((top + out.totalH) - bottomLimit))

    local originX = innerL + math.floor(((innerR - innerL) - out.width) / 2)
    local originY = top
    local function Place(region, left, top)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", panel, "TOPLEFT", originX + left, -(originY + top))
    end

    local level = buttons[1]:GetFrameLevel()
    holder:SetFrameLevel(math.max(1, level - 2))
    view:Draw(out, Place, function(entry, shown, left, top)
        local button = entry.button
        ns.SetFreeCount(button, nil)
        if shown then
            Place(button, left, top)
            concealed[button] = nil
            ns.RevealButton(button)
            ns.SetStackTotal(button, entry.stackTotal)
        else
            concealed[button] = true
            ns.ConcealButton(button, holder)
            ns.SetStackTotal(button, nil)
        end
    end)
    for _, g in ipairs(out.groups) do
        if g.compressed and g.entries[1] then ns.SetFreeCount(g.entries[1].button, g.count) end
    end
    view:SetLevel(math.max(1, level - 1))
    view:ApplyDim()
    if Searching() then
        C_Timer.After(0, function() view:ExtendSearch(_G.BankItemSearchBox:GetText()) end)
    end
    if toolbar then toolbar:Update() end
    if ns.Transfer then ns.Transfer.Refresh() end

    UpdateMarks()
end

local function Restore()
    for button in pairs(concealed) do ns.RevealButton(button) end
    wipe(concealed)
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
    if panel then RestoreHeights() end
    RestoreSaved()
    if toolbar then toolbar.frame:Hide() end
    if countText then countText:Hide() end
    lastSignature = nil
end

-- Werkzeugleiste und Ansicht der Bank (nil, solange es Blizzards Bank nicht gibt).
function Bank.Toolbar() return toolbar end
function Bank.View() return view end

function Bank.Blocked()
    return not ns.S or not ns.S.bankGrouping or not panel
end

function Bank.Apply(fromBlizzard)
    if applying or not panel then return end
    if Bank.Blocked() then
        if lastSignature or next(concealed) then Restore() end
        return
    end
    if not bankFrame:IsShown() then return end
    if ns.InCombat() and panel:IsProtected() then
        dirty = true
        return
    end
    applying = true
    local ok, err = pcall(DoLayout, fromBlizzard)
    applying = false
    if not ok then geterrorhandler()(err) end
end

function Bank.Refresh(force)
    if not bankFrame or not bankFrame:IsShown() then
        lastSignature = nil
        return
    end
    if force then
        lastSignature = nil
        Bank.Apply(false)
    else
        dirty = true
    end
end

local function CanRelayoutNow()
    return ns.Render.CanRelayout(bankFrame, nil, view)
end

-- Nach Blizzards (und ClassicUIs) eigener Anordnung, im nächsten Frame.
local function AfterBlizzard()
    C_Timer.After(0, function()
        if bankFrame and bankFrame:IsShown() then
            lastSignature = nil
            Bank.Apply(true)
        end
    end)
end

local function Install()
    if installed then return end
    bankFrame = _G.BankFrame
    panel = (bankFrame and bankFrame.BankPanel) or _G.BankPanel
    if not bankFrame or not panel or not panel.itemButtonPool then
        panel = nil
        return
    end
    installed = true

    holder = CreateFrame("Frame", nil, panel)
    holder:SetAllPoints()
    holder:SetScript("OnUpdate", ns.Render.DeferredUpdate(function() return dirty end, function()
        if CanRelayoutNow() then Bank.Apply(false) end
    end, CHECK_INTERVAL))
    view = ns.Render.NewView(holder, "bank")
    toolbar = ns.Toolbar.New(bankFrame, {
        viewKey = "bank",
        view = function() return view end,
        bags = BankTabs,
        views = function() return ns.Window and ns.Window.ViewEntries("bank") or {} end,
        transfer = "bank",
        select = true,
        search = function() return _G.BankItemSearchBox end,
        allChars = true,
        onResize = function()
            if not Bank.Blocked() and bankFrame:IsShown() then FitTopRow() end
        end,
    })
    toolbar.frame:SetFrameLevel(bankFrame:GetFrameLevel() + 20)
    toolbar.frame:Hide()
    ns.Transfer.Register("bank", view, bankFrame, toolbar)

    -- Fußzeile: Blizzard (und ClassicUI) stellen Taschenfächer neu – danach wieder zusammenrücken.
    if bankFrame.RefreshBagButtons then
        hooksecurefunc(bankFrame, "RefreshBagButtons", function()
            if not Bank.Blocked() then dirty = true; lastSignature = nil end
        end)
    end
    if panel.RefreshHeaderText then
        hooksecurefunc(panel, "RefreshHeaderText", function()
            if not Bank.Blocked() and bankFrame:IsShown() then FitTopRow() end
        end)
    end

    if panel.GenerateItemSlotsForSelectedTab then
        hooksecurefunc(panel, "GenerateItemSlotsForSelectedTab", AfterBlizzard)
    end
    if panel.RefreshBankPanel then
        hooksecurefunc(panel, "RefreshBankPanel", function() dirty = true end)
    end
    -- Reiter rechts an der Bank: die angedockte Tasche hält Abstand dazu.
    if panel.RefreshBankTabs then
        hooksecurefunc(panel, "RefreshBankTabs", function()
            C_Timer.After(0, function() ns.Layout.Reposition() end)
        end)
    end
    bankFrame:HookScript("OnShow", AfterBlizzard)
    bankFrame:HookScript("OnHide", function()
        dirty = false
        lastSignature = nil
        ns.Render.CancelDrag()
        if toolbar then toolbar:ClearFocus() end
    end)
end

ns.OnReady(Install)

ns.On("BANKFRAME_OPENED", function()
    Install()
    AfterBlizzard()
    -- Für ein ganz einheitliches Bild (Bank im Forever-Original wie die Tasche): einmal erklären,
    -- wie man ClassicUIs Bank-Stil ausschaltet. Die Gruppierung läuft auch mit ihm.
    if ns.S.bankGrouping and ns.ClassicUIBankActive() and not ns.db.hintClassicBank then
        ns.db.hintClassicBank = true
        ns.Print(L.HINT_CLASSIC_BANK)
    end
end)
ns.On("BAG_UPDATE_DELAYED", function() if bankFrame and bankFrame:IsShown() then dirty = true end end)
ns.On("PLAYERBANKSLOTS_CHANGED", function() if bankFrame and bankFrame:IsShown() then dirty = true end end)
ns.On("INVENTORY_SEARCH_UPDATE", function() if bankFrame and bankFrame:IsShown() then Bank.Refresh(true) end end)

ns.OnSettingChanged(function(key)
    if key == "bagCount" then
        Bank.Refresh(true)
    elseif key == "bankGrouping" or key == "compressEmpty" then
        if key == "bankGrouping" and not ns.S.bankGrouping then
            Restore()
            -- Blizzard die Plätze beim nächsten Öffnen selbst wieder anordnen lassen.
            ns.Print(L.BANK_REOPEN)
        else
            Bank.Refresh(true)
        end
    end
end)
