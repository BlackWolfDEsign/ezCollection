local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Blizzards Händlerfenster, erweitert:
      - breiter und auf Wunsch höher: mehr Waren auf einmal (Spalten 2–5, Reihen 5–7)
      - Suche über das Item-Wissen von ezCore (dieselbe Suche wie in ezBag) und Filter
      - Knopf „Mehrere kaufen“ an stapelbaren Waren, Alt+Klick kauft einen ganzen Stapel
      - bekannte Rezepte, Reittiere, Haustiere und Spielzeuge bekommen ein Häkchen und werden grau statt rot
      - was der Sammlung noch fehlt (Aussehen, Reittier, Haustier, Spielzeug), trägt einen Stern wie in ezBag;
        Filter „Nur Fehlendes für die Sammlung“ (ezCore: Collections.Missing, Stern über Collections.ApplyMark)
      - Ausrüstung, die besser ist als die angelegte, trägt ezGears Pfeil; Filter „Nur Verbesserungen“ (nur mit ezGear)
      - „Plunder verkaufen“ im Menü am Knopf „Filter“ (nur mit ezBag: dessen Regeln, dessen Verkauf)
    Wie: Auf dem Reiter „Händler“ zeigt ezMerchant die Waren in eigenen Plätzen aus Blizzards Vorlage
    MerchantItemTemplate (gleiche Optik, gleiche Klicks, Tooltips und Bestätigungen von Blizzard).
    Blizzards zehn Plätze und Blätter-Knöpfe werden dort nur ausgeblendet; auf dem Reiter „Rückkauf“
    und bei Gamepad-Steuerung bleibt alles Blizzards Original. Taint-sicher: nur hooksecurefunc und
    HookScript, ezMerchant schreibt keinen Wert in Blizzards Tabellen (Seite, Plätze, Konstanten).
]]

local M = {}
ns.Merchant = M

local ITEM_W, ITEM_H, GAP_X, GAP_Y = 153, 44, 12, 8      -- wie MerchantItem1–10 in Blizzards XML
local COL_W, ROW_H = ITEM_W + GAP_X, ITEM_H + GAP_Y
local LEFT, TOP = 11, -69
local BLIZZ_COLS, BLIZZ_ROWS, BLIZZ_ITEMS = 2, 5, 10
local MAX_COST = 3                                        -- MAX_ITEM_COST
local MONEY_WIDTH = 120                                   -- Blizzards MAX_MONEY_DISPLAY_WIDTH
local SEARCH_LEFT, SEARCH_MIN = 72, 110                   -- Suchfeld rechts vom Porträt
local FILTER_W = 96
local SEARCH_ROW = 28                                     -- eigene Zeile, wenn oben kein Platz ist

local frames = {}           -- eigene Warenplätze ezMerchantItem1 …
local ui = {}               -- Suchfeld, Filter, Blättern, Hinweis „nichts gefunden“
local state = { page = 1, query = "", list = {}, taken = false, total = 0 }
local original              -- Blizzards Maße und Anker, bevor ezMerchant das Fenster ändert
M.state, M.frames, M.ui = state, frames, ui

---------------------------------------------------------------------------
-- Wann übernimmt ezMerchant die Warenliste?
---------------------------------------------------------------------------

local function GamepadUI()
    return InputUtil ~= nil and InputUtil.IsGamepadUIEnabled ~= nil and InputUtil.IsGamepadUIEnabled() == true
end

-- Die beiden Funktionen von Blizzard, an die sich M.Setup hängt (hooksecurefunc mit Namen): fehlt eine, bleibt
-- das Original – ein Hook auf einen Namen, den es nicht gibt, wäre ein Lua-Fehler beim Einloggen (V-127).
M.HOOKS = { "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_UpdateBuybackInfo" }

-- Alles da, was die Plätze brauchen (sonst bleibt das Original).
function M.Supported()
    if M.broken or MerchantFrame == nil or _G.MerchantItem1 == nil or C_MerchantFrame == nil
        or C_MerchantFrame.GetItemInfo == nil or GetMerchantNumItems == nil or GetMerchantItemLink == nil then
        return false
    end
    for _, name in ipairs(M.HOOKS) do
        if type(_G[name]) ~= "function" then return false end
    end
    return true
end

function M.Active()
    return ns.Enabled("merchant") and M.Supported() and not GamepadUI() and MerchantFrame.selectedTab == 1
end

local function Columns() return ns.Setting("columns") end
local function Rows() return ns.Setting("rows") end
function M.PerPage() return Columns() * Rows() end

---------------------------------------------------------------------------
-- Item-Wissen: bekannt? passt zur Suche?
---------------------------------------------------------------------------

local function Knowledge() return Core.Knowledge end

local function Facts(link)
    local K = Knowledge()
    if not (K and link) then return nil end
    return K.Get(link)
end

-- Sammlung laut Item-Wissen (Collections.lua in ezCore): { kind, known, otherClass } oder nil.
function M.Collect(link)
    local facts = Facts(link)
    return facts and type(facts.collect) == "table" and facts.collect or nil
end

-- Schon bekannt: Rezept gelernt (Tooltip „Bereits bekannt“) oder Reittier, Haustier, Spielzeug gesammelt.
-- Ein gesammeltes Aussehen zählt nicht: die Rüstung selbst kann man trotzdem brauchen.
function M.IsKnown(link)
    local facts = Facts(link)
    if not facts then return false end
    if facts.recipe ~= nil and facts.recipe.known == true then return true end
    local c = M.Collect(link)
    return c and c.kind ~= "appearance" and c.known == true or false
end

-- Fehlt der Sammlung noch? fehlt, nurAndereKlasse – die Antwort von ezCore (Collections.Missing), dieselbe wie in ezBag.
-- nurAndereKlasse: dann zählt der Filter es nicht (dieser Charakter kann es nicht sammeln).
function M.Missing(link)
    local C = Core.Collections
    if not (link and C and C.Missing) then return false, false end
    return C.Missing(link)
end

-- Stern „fehlt der Sammlung“ oben links am Warenplatz: Zeichen von ezCore (Collections.ApplyMark, legt die Textur
-- selbst an). Hier nur ein Verweis je eigenem Platz, damit Tests und andere Teile den Stern finden.
local marks = setmetatable({}, { __mode = "k" })
function M.SetMark(f, missing, otherClass)
    local C = Core.Collections
    if not (C and C.ApplyMark) then return nil end
    marks[f] = C.ApplyMark(f.ItemButton, missing == true, otherClass == true)
    return marks[f]
end
function M.Mark(f) return marks[f] end

---------------------------------------------------------------------------
-- „Besser als angelegt“: Bewertung und Pfeil kommen aus ezGear (ezCore.API("ezGear")), nicht nachgebaut (V-120, V-125)
---------------------------------------------------------------------------

-- ezGears Schnittstelle, wenn ezGear läuft und den Pfeil anbietet; sonst nil.
function M.Gear()
    local gear = Core.API("ezGear")
    if type(gear) == "table" and type(gear.SetUpgradeIcon) == "function" then return gear end
    return nil
end

-- Ist die Ware laut ezGear besser als das Angelegte? true/false, nil = ezGear fehlt oder die Daten laden noch.
function M.IsUpgrade(link)
    local gear = M.Gear()
    if not (gear and link and type(gear.IsUpgrade) == "function") then return nil end
    local ok, up = pcall(gear.IsUpgrade, link)
    if not ok then
        ns.Error(up, "IsUpgrade (ezGear)")
        return nil
    end
    return up
end

-- Pfeil am Warenplatz setzen oder leeren (link = nil). → true, wenn ezGear gefragt wurde.
function M.SetUpgrade(f, link)
    local gear = M.Gear()
    if not gear then return false end
    local ok, err = pcall(gear.SetUpgradeIcon, f.ItemButton, link)
    if not ok then ns.Error(err, "SetUpgradeIcon (ezGear)") end
    return ok
end

M.FILTERS = { "filterUsable", "filterKnown", "filterAffordable", "filterMissing", "filterUpgrade" }

-- Wird der Filter gerade angeboten? „Nur Verbesserungen“ nur, solange ezGear läuft.
function M.FilterOffered(key)
    if key == "filterUpgrade" then return M.Gear() ~= nil end
    return true
end

local function AnyFilter()
    for _, key in ipairs(M.FILTERS) do
        if ns.Enabled(key) and M.FilterOffered(key) then return true end
    end
    return false
end
M.AnyFilter = AnyFilter

-- Passt die Ware an index zu Suche und Filtern?
function M.Passes(index, query)
    local info = C_MerchantFrame.GetItemInfo(index)
    if not info then return false end
    if ns.Enabled("filterUsable") and (info.isUsable == false or info.isPurchasable == false) then return false end
    if ns.Enabled("filterAffordable") and CanAffordMerchantItem and CanAffordMerchantItem(index) == false then return false end
    local link
    local upgrades = ns.Enabled("filterUpgrade") and M.Gear() ~= nil
    if ns.Enabled("filterKnown") or ns.Enabled("filterMissing") or upgrades or query ~= "" then
        link = GetMerchantItemLink(index)
    end
    if upgrades and M.IsUpgrade(link) ~= true then return false end
    if ns.Enabled("filterKnown") and M.IsKnown(link) then return false end
    if ns.Enabled("filterMissing") then
        local missing, otherClass = M.Missing(link)
        if not missing or otherClass then return false end
    end
    if query ~= "" then
        local f = Facts(link)
        if f then return Knowledge().Match(f, query) == true end
        -- Item-Wissen noch nicht geladen: nach dem Namen
        return type(info.name) == "string" and info.name:lower():find(query:lower(), 1, true) ~= nil
    end
    return true
end

local function BuildList()
    local list = state.list
    wipe(list)
    local total = GetMerchantNumItems() or 0
    local query = state.query
    local filtering = query ~= "" or AnyFilter()
    for index = 1, total do
        if not filtering or M.Passes(index, query) then list[#list + 1] = index end
    end
    state.total, state.filtering = total, filtering
    return list
end

---------------------------------------------------------------------------
-- Ein Warenplatz: Blizzards Vorlage, gefüllt wie in MerchantFrame_UpdateMerchantInfo
---------------------------------------------------------------------------

local function UpdateAltCurrency(f, index, canAfford)
    local frameName = f.alt:GetName()
    local used, width = 0, 0
    if (GetMerchantItemCostInfo(index) or 0) > 0 then
        for i = 1, MAX_COST do
            local texture, value, link = GetMerchantItemCostItem(index, i)
            if texture then
                used = used + 1
                local button = _G[frameName .. "Item" .. used]
                button.index, button.item, button.itemLink = index, i, link
                AltCurrencyFrame_Update(frameName .. "Item" .. used, texture, value, canAfford)
                width = width + button:GetWidth() + (used > 1 and 4 or 0)
                button:Show()
            end
        end
    end
    for i = used + 1, MAX_COST do
        local button = _G[frameName .. "Item" .. i]
        if button then button:Hide() end
    end
    return width
end

-- Färbung wie in MerchantFrame_UpdateMerchantInfo: Namensrahmen, Platz, Symbol (und dessen Rand).
local TINTS = {
    normal  = { name = { 0.5, 0.5, 0.5 }, slot = { 1, 1, 1 },       icon = { 1, 1, 1 } },
    red     = { name = { 1, 0, 0 },       slot = { 1, 0, 0 },       icon = { 0.9, 0, 0 } },
    redDim  = { name = { 0.5, 0, 0 },     slot = { 0.5, 0, 0 },     icon = { 0.5, 0, 0 } },     -- ausverkauft, nicht nutzbar
    greyDim = { name = { 0.5, 0.5, 0.5 }, slot = { 0.5, 0.5, 0.5 }, icon = { 0.5, 0.5, 0.5 } }, -- ausverkauft oder bekannt
}

local function Tint(f, button, kind)
    local t = TINTS[kind] or TINTS.normal
    SetItemButtonNameFrameVertexColor(f, t.name[1], t.name[2], t.name[3])
    SetItemButtonSlotVertexColor(f, t.slot[1], t.slot[2], t.slot[3])
    SetItemButtonTextureVertexColor(button, t.icon[1], t.icon[2], t.icon[3])
    SetItemButtonNormalTextureVertexColor(button, t.icon[1], t.icon[2], t.icon[3])
end

local function ClearFrame(f)
    local button = f.ItemButton
    button.price, button.hasItem, button.name, button.link, button.extendedCost = nil, nil, nil, nil, nil
    button:Hide()
    SetItemButtonNameFrameVertexColor(f, 0.5, 0.5, 0.5)
    SetItemButtonSlotVertexColor(f, 0.4, 0.4, 0.4)
    f.Name:SetText("")
    f.money:Hide()
    f.alt:Hide()
    f.known:Hide()
    M.SetMark(f, false)
    M.SetUpgrade(f, nil)
    f.plus:Hide()
    f.merchantIndex = nil
end

local function MaxStack(index)
    local ok, value = pcall(GetMerchantItemMaxStack, index)
    return ok and tonumber(value) or 1
end

local function FillFrame(f, index)
    local info = index and C_MerchantFrame.GetItemInfo(index)
    if not info then return ClearFrame(f) end
    local button = f.ItemButton
    if info.currencyID and CurrencyContainerUtil and CurrencyContainerUtil.GetCurrencyContainerInfo then
        info.name, info.texture, info.numAvailable = CurrencyContainerUtil.GetCurrencyContainerInfo(info.currencyID,
            info.numAvailable, info.name, info.texture, nil)
    end
    local canAfford = CanAffordMerchantItem(index)
    local link = GetMerchantItemLink(index)
    f.merchantIndex = index
    f.Name:SetText(info.name)
    SetItemButtonCount(button, info.stackCount)
    SetItemButtonStock(button, info.numAvailable)
    SetItemButtonTexture(button, info.texture)
    button.name, button.link, button.texture = info.name, link, info.texture

    local moneyName = f.money:GetName()
    if info.hasExtendedCost and (info.price or 0) <= 0 then
        button.price, button.extendedCost = nil, true
        UpdateAltCurrency(f, index, canAfford)
        f.alt:ClearAllPoints()
        f.alt:SetPoint("BOTTOMLEFT", f.nameFrame, "BOTTOMLEFT", 0, 31)
        f.money:Hide()
        f.alt:Show()
    elseif info.hasExtendedCost then
        button.price, button.extendedCost = info.price, true
        local altWidth = UpdateAltCurrency(f, index, canAfford)
        MoneyFrame_SetMaxDisplayWidth(f.money, MONEY_WIDTH - altWidth)
        MoneyFrame_Update(moneyName, info.price)
        SetMoneyFrameColor(moneyName, canAfford == false and "gray" or nil)
        f.alt:ClearAllPoints()
        f.alt:SetPoint("LEFT", moneyName, "RIGHT", -14, 0)
        f.alt:Show()
        f.money:Show()
    else
        button.price, button.extendedCost = info.price, nil
        MoneyFrame_SetMaxDisplayWidth(f.money, MONEY_WIDTH)
        MoneyFrame_Update(moneyName, info.price)
        SetMoneyFrameColor(moneyName, canAfford == false and "gray" or nil)
        f.alt:Hide()
        f.money:Show()
    end

    if button.IconQuestTexture then
        if info.isQuestStartItem then
            button.IconQuestTexture:SetTexture(TEXTURE_ITEM_QUEST_BANG)
            button.IconQuestTexture:Show()
        else
            button.IconQuestTexture:Hide()
        end
    end
    MerchantFrameItem_UpdateQuality(f, link)

    local itemID = GetMerchantItemID and GetMerchantItemID(index)
    local isHeirloom = itemID and C_Heirloom and C_Heirloom.IsItemHeirloom(itemID)
    local knownHeirloom = isHeirloom and C_Heirloom.PlayerHasHeirloom(itemID)
    button.showNonrefundablePrompt = not C_MerchantFrame.IsMerchantItemRefundable(index)
    button.hasItem = true
    button:SetID(index)
    button:Show()

    -- Bekanntes immer markieren (Einstellungs-Prüfung vom 19.11.2026, Nr. 7: schützt vor Doppelkauf)
    local known = M.IsKnown(link)
    local tintRed = not known and (not info.isPurchasable or (not info.isUsable and not isHeirloom))
    SetItemButtonDesaturated(button, knownHeirloom or known)
    if info.numAvailable == 0 or knownHeirloom or known then
        Tint(f, button, tintRed and "redDim" or "greyDim")
    elseif tintRed then
        Tint(f, button, "red")
    else
        Tint(f, button, "normal")
    end
    f.known:SetShown(known == true)
    local missing, otherClass = false, false
    if ns.Enabled("markMissing") then missing, otherClass = M.Missing(link) end
    M.SetMark(f, missing, otherClass)
    M.SetUpgrade(f, ns.Enabled("markUpgrade") and link or nil)
    f.plus:SetShown(ns.Enabled("stackButton") and MaxStack(index) > 1)
end

---------------------------------------------------------------------------
-- Mehrere kaufen
---------------------------------------------------------------------------

local buying

-- Wie viele Stück sind bezahlbar? nil = unbekannt (dann entscheidet der Server).
function M.Affordable(index, info)
    info = info or C_MerchantFrame.GetItemInfo(index)
    if not info then return 0 end
    local unit = math.max(1, info.stackCount or 1)
    local can
    if (info.price or 0) > 0 then can = math.floor(GetMoney() / (info.price / unit)) end
    if info.hasExtendedCost then
        for i = 1, MAX_COST do
            local _, value, link, currencyName = GetMerchantItemCostItem(index, i)
            if link and not currencyName and (value or 0) > 0 then
                local mine = Core.ItemCount(link)
                local n = math.floor(mine / (value / unit))
                can = can and math.min(can, n) or n
            end
        end
    end
    if info.numAvailable and info.numAvailable >= 0 then
        local stock = info.numAvailable * unit
        can = can and math.min(can, stock) or stock
    end
    return can
end

-- Ganzer Stapel: so viele, wie in einen Taschenplatz passen.
function M.StackSize(index)
    local link = GetMerchantItemLink(index)
    local size
    if link and C_Item and C_Item.GetItemMaxStackSize then
        local ok, value = pcall(C_Item.GetItemMaxStackSize, link)
        size = ok and tonumber(value) or nil
    end
    return math.max(size or 1, MaxStack(index))
end

-- Ein Kauf in Teilen (auch für „Vorrat auffüllen“, Restock.lua): job = { index, link, name, left, total, bought = 0,
-- chunk, onDone(job), onStop(job, gekauft) }. Ohne onDone/onStop meldet der Kauf selbst im Chat.
local function Step()
    local job = buying
    if not job then return end
    if job.failed or not MerchantFrame:IsShown() or GetMerchantItemLink(job.index) ~= job.link then
        buying = nil
        local got = job.failed and job.bought - (job.lastChunk or 0) or job.bought
        if job.onStop then return job.onStop(job, got) end
        return ns.Print(L.STACK_STOPPED:format(got, job.total))
    end
    local n = math.min(job.left, job.chunk)
    BuyMerchantItem(job.index, n)
    job.left, job.bought, job.lastChunk = job.left - n, job.bought + n, n
    if job.left > 0 then
        C_Timer.After(M.STEP_DELAY, Step)
    else
        buying = nil
        if job.onDone then return job.onDone(job) end
        ns.Print(L.STACK_BOUGHT:format(job.total, job.link or job.name))
    end
end
M.STEP_DELAY = 0.3

-- Kauf in Teilen beginnen (job wie bei Step). → false, wenn schon ein Kauf läuft.
function M.StartBuying(job)
    if buying or type(job) ~= "table" then return false end
    job.bought = job.bought or 0
    buying = job
    Step()
    return true
end

-- Läuft gerade ein Kauf in Teilen?
function M.Buying() return buying ~= nil end

-- Laufenden Kauf anhalten (Knopf „Anhalten“ von „Vorrat auffüllen“). → true, wenn einer lief.
function M.StopBuying()
    local job = buying
    if not job then return false end
    buying = nil
    if job.onStop then job.onStop(job, job.bought) else ns.Print(L.STACK_STOPPED:format(job.bought, job.total)) end
    return true
end

-- So viele Stück gibt der Händler auf einmal ab (mindestens ein Bündel).
function M.Chunk(index, unit) return math.max(unit or 1, MaxStack(index)) end

-- Meldet das Spiel „Inventar voll“ oder „nicht genug Geld“, hört der Kauf nach diesem Teil auf
-- (sonst käme bei jedem weiteren Teil dieselbe Fehlermeldung).
local STOP_ERRORS = { "ERR_INV_FULL", "ERR_NOT_ENOUGH_MONEY", "ERR_ITEM_MAX_COUNT", "ERR_BAG_FULL" }
ns.On("UI_ERROR_MESSAGE", function(_, _, message)
    if not buying or type(message) ~= "string" or ns.IsSecret(message) then return end
    for _, key in ipairs(STOP_ERRORS) do
        if _G[key] and message == _G[key] then buying.failed = true return end
    end
end)

-- Höchste Kaufmenge auf einmal (Gesamtreview 18.11.2026, T6-8): so viel, wie das Mengenfeld mit 6 Zeichen fasst –
-- „1e999“ passt auch hinein und wurde sonst zu unendlich (bei kostenloser Ware mit unbegrenztem Vorrat begrenzte
-- nichts den Kauf, die Meldungen zeigten eine Müllzahl).
M.MAX_AMOUNT = 99999

-- amount Stück der Ware hinter button kaufen, in Teilen so groß, wie der Händler auf einmal verkauft.
-- amount muss eine endliche Zahl von 1 bis M.MAX_AMOUNT sein (sonst Meldung STACK_INVALID, kein Kauf).
function M.Buy(button, amount)
    local index = button:GetID()
    local info = C_MerchantFrame.GetItemInfo(index)
    if not info or buying then return false end
    amount = Core.FiniteNumber(amount, 1, M.MAX_AMOUNT)
    if not amount then
        ns.Print(L.STACK_INVALID:format(M.MAX_AMOUNT))
        return false
    end
    amount = math.floor(amount)
    local unit = math.max(1, info.stackCount or 1)
    amount = math.ceil(amount / unit) * unit
    local can = M.Affordable(index, info)
    if can then amount = math.min(amount, math.floor(can / unit) * unit) end
    if amount <= 0 then
        ns.Print(L.STACK_NONE)
        return false
    end
    local chunk = M.Chunk(index, unit)
    if button.extendedCost or button.showNonrefundablePrompt then
        -- Sonderwährung oder nicht erstattbar: Blizzards eigene Bestätigung, ein Teil auf einmal
        if amount > chunk then ns.Print(L.STACK_EXTENDED) end
        MerchantFrame_ConfirmExtendedItemCost(button, math.min(amount, chunk))
        return true
    end
    local link = GetMerchantItemLink(index)
    local function Start()
        M.StartBuying({ index = index, link = link, name = info.name, left = amount, total = amount, bought = 0, chunk = chunk })
    end
    local cost = (info.price or 0) / unit * amount
    if cost >= (MERCHANT_HIGH_PRICE_COST or 1500000) then
        Core.Confirm(L.STACK_CONFIRM:format(amount, link or info.name, ns.Money(cost)), Start)
    else
        Start()
    end
    return true
end

function M.BuyStack(button)
    return M.Buy(button, M.StackSize(button:GetID()))
end

function M.AskAmount(button)
    local index = button:GetID()
    local info = C_MerchantFrame.GetItemInfo(index)
    if not info then return end
    local stack = M.StackSize(index)
    local can = M.Affordable(index, info)
    Core.AskText(L.STACK_ASK:format(info.name or "?", stack, can or stack), tostring(stack), function(text)
        local n = Core.FiniteNumber(text, 1, M.MAX_AMOUNT)
        if not n then return ns.Print(L.STACK_INVALID:format(M.MAX_AMOUNT)) end
        M.Buy(button, math.floor(n))
    end, 6)
end

---------------------------------------------------------------------------
-- Plätze anlegen
---------------------------------------------------------------------------

local KNOWN_ATLAS = { "common-icon-checkmark", "Tracker-Check" }

local function EnsureFrame(i)
    local f = frames[i]
    if f then return f end
    local name = "ezMerchantItem" .. i
    f = CreateFrame("Frame", name, MerchantFrame, "MerchantItemTemplate")
    f.ItemButton = f.ItemButton or _G[name .. "ItemButton"]
    f.Name = f.Name or _G[name .. "Name"]
    f.money = _G[name .. "MoneyFrame"]
    f.alt = _G[name .. "AltCurrencyFrame"]
    f.nameFrame = _G[name .. "NameFrame"]
    f.Name:SetWidth(88)     -- Platz für das Plus oben rechts

    local known = f.ItemButton:CreateTexture(nil, "OVERLAY", nil, 2)
    known:SetSize(16, 16)
    known:SetPoint("TOPRIGHT", f.ItemButton, "TOPRIGHT", 4, 4)
    Core.SetIcon(known, Core.FirstAtlas(KNOWN_ATLAS), "Interface\\RaidFrame\\ReadyCheck-Ready")
    known:Hide()
    f.known = known
    -- Der Stern „fehlt der Sammlung“ oben links kommt aus ezCore (M.SetMark), erst wenn er gebraucht wird.

    local plus = CreateFrame("Button", nil, f)
    plus:SetSize(16, 16)
    plus:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -1)
    plus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    plus:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    plus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    -- Rechtsklick: Sollmenge für „Vorrat auffüllen“ (Restock.lua); sichtbar auch im Menü „Filter“ » „Sollmenge festlegen“
    if plus.RegisterForClicks then plus:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    plus:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" and ns.Restock then
            return ns.Try("RestockAsk", ns.Restock.AskTarget, f.ItemButton:GetID())
        end
        ns.Try("AskAmount", M.AskAmount, f.ItemButton)
    end)
    plus:SetScript("OnEnter", function(self) Core.ShowTip(self, L.STACK_TIP_TITLE, L.STACK_TIP .. "\n" .. L.RESTOCK_PLUS_TIP) end)
    plus:SetScript("OnLeave", function() GameTooltip:Hide() end)
    plus:Hide()
    f.plus = plus

    -- Alt+Klick: ganzer Stapel (Blizzards Klick tut bei Alt nichts)
    f.ItemButton:HookScript("OnClick", function(self)
        if IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() and MerchantFrame.selectedTab == 1 then
            ns.Try("BuyStack", M.BuyStack, self)
        end
    end)
    frames[i] = f
    return f
end

---------------------------------------------------------------------------
-- Suchfeld, Filter, Blättern
---------------------------------------------------------------------------

local Render   -- unten

local function SetPage(page)
    local pages = math.max(1, math.ceil(#state.list / M.PerPage()))
    page = math.max(1, math.min(pages, page))
    if page == state.page then return end
    state.page = page
    if StackSplitFrame and StackSplitFrame:IsShown() then
        for _, f in ipairs(frames) do
            if StackSplitFrame.owner == f.ItemButton then StackSplitFrame:Hide() break end
        end
    end
    Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    Render()
end
M.SetPage = SetPage

-- Blätterknöpfe nach Blizzards Vorbild: MerchantPrevPageButton/MerchantNextPageButton (Blizzard_UIPanels_Game/
-- Mainline/MerchantFrame.xml, Zweig forever: 32 × 32, Hintergrund UI-PageButton-Background, Mitte 96 über der
-- Unterkante) – die Größe 32 folgt diesem Blizzard-Teil (Design-System 2.3), keine eigene Zahl.
local function PageButton(direction)
    local button = CreateFrame("Button", nil, MerchantFrame)
    button:SetSize(32, 32)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\UI-PageButton-Background")
    bg:SetSize(32, 32)
    bg:SetPoint("CENTER", 0, 1)
    local label = button:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
    local file = direction < 0 and "Prev" or "Next"
    button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. file .. "Page-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. file .. "Page-Down")
    button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. file .. "Page-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    if direction < 0 then
        button:SetPoint("CENTER", MerchantFrame, "BOTTOMLEFT", 25, 96)
        label:SetPoint("LEFT", button, "RIGHT")
        label:SetText(_G.PREV or L.PAGE_PREV)
    else
        button:SetPoint("CENTER", MerchantFrame, "BOTTOMRIGHT", -26, 96)
        label:SetPoint("RIGHT", button, "LEFT", -3, 0)
        label:SetText(_G.NEXT or L.PAGE_NEXT)
    end
    button:SetScript("OnClick", function() SetPage(state.page + direction) end)
    -- Tooltip auch auf der ersten bzw. letzten Seite (Knopf dann gesperrt): nennt das Mausrad
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:SetScript("OnEnter", function(self)
        if direction < 0 then
            Core.ShowTip(self, _G.PREV or L.PAGE_PREV, L.PAGE_PREV_TIP)
        else
            Core.ShowTip(self, _G.NEXT or L.PAGE_NEXT, L.PAGE_NEXT_TIP)
        end
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    return button
end

local function CreateFilter()
    local ok, dropdown = pcall(CreateFrame, "DropdownButton", "ezMerchantFilter", MerchantFrame, "WowStyle1FilterDropdownTemplate")
    if not ok or not dropdown or not dropdown.SetupMenu then
        ok, dropdown = pcall(CreateFrame, "Button", "ezMerchantFilter", MerchantFrame, "UIPanelButtonTemplate")
        if not ok or not dropdown then return nil end
        dropdown:SetText(L.FILTER)
        dropdown:SetScript("OnClick", function(self)
            Core.Menu.Open(self, function(root) M.BuildMenu(nil, root) end)
        end)
    else
        if dropdown.SetText then dropdown:SetText(L.FILTER) end
        dropdown:SetupMenu(function(_, root) M.BuildMenu(nil, root) end)
        if dropdown.SetIsDefaultCallback then dropdown:SetIsDefaultCallback(function() return not AnyFilter() end) end
        if dropdown.SetDefaultCallback then dropdown:SetDefaultCallback(function() M.ResetFilters() end) end
    end
    dropdown:SetSize(FILTER_W, 22)
    dropdown:HookScript("OnEnter", function(self) Core.ShowTip(self, L.FILTER, L.FILTER_TIP) end)
    dropdown:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return dropdown
end

local function CreateSearch()
    local ok, box = pcall(CreateFrame, "EditBox", "ezMerchantSearchBox", MerchantFrame, "SearchBoxTemplate")
    if not ok or not box then
        ok, box = pcall(CreateFrame, "EditBox", "ezMerchantSearchBox", MerchantFrame, "InputBoxTemplate")
        if not ok or not box then return nil end
    end
    box:SetSize(140, 20)
    box:SetAutoFocus(false)
    if box.Instructions then box.Instructions:SetText(L.SEARCH_HINT) end
    box:HookScript("OnTextChanged", function(self)
        local text = Core.Trim(self:GetText() or "")
        if text == state.query then return end
        state.query, state.page = text, 1
        Render()
    end)
    box:HookScript("OnEnter", function(self) Core.ShowTip(self, L.SEARCH_HINT, L.SEARCH_TIP) end)
    box:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return box
end

local function CreateUI()
    ui.search = CreateSearch()
    ui.filter = CreateFilter()
    ui.prev, ui.next = PageButton(-1), PageButton(1)
    ui.pageText = MerchantFrame:CreateFontString(nil, "BORDER", "GameFontNormal")
    ui.pageText:SetSize(160, 0)
    ui.pageText:SetPoint("BOTTOM", MerchantFrame, "BOTTOM", 0, 86)
    ui.pageText:Hide()
    ui.empty = MerchantFrame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.empty:SetText(L.NO_MATCH)
    ui.empty:Hide()
    -- Bodenleiste bis zum rechten Rand (Blizzards Atlas reicht nur für zwei Spalten)
    ui.border = MerchantFrame:CreateTexture(nil, "OVERLAY")
    ui.border:Hide()
end

local function ShowUI(shown)
    for _, key in ipairs({ "search", "filter" }) do
        if ui[key] then ui[key]:SetShown(shown) end
    end
    if not shown then
        ui.prev:Hide()
        ui.next:Hide()
        ui.pageText:Hide()
        ui.empty:Hide()
        ui.border:Hide()
    end
end

---------------------------------------------------------------------------
-- Fenster übernehmen und zurückgeben
---------------------------------------------------------------------------

local function BlizzardItems(shown)
    for i = 1, BLIZZ_ITEMS do
        local item = _G["MerchantItem" .. i]
        if item then item:SetShown(shown) end
    end
end

-- Streifen aus der Mitte des Atlas (zwischen Reparatur-Knöpfen und Rückkauf-Platz): Datei und Koordinaten.
local SLICE_FROM, SLICE_TO = 0.45, 0.50
-- Ausschnitt über ezCores Core.AtlasTexCoord (Gesamtreview 18.11.2026, Nachlauf P19a – vorher las ezMerchant
-- C_Texture.GetAtlasInfo selbst); Datei als fünfter Wert. Form der Rückgabe wie bisher.
function M.BorderSlice(atlas)
    local left, right, top, bottom, file = Core.AtlasTexCoord(atlas, SLICE_FROM, SLICE_TO, 0, 1)
    if not (left and file) then return nil end
    return { file = file, left = left, right = right, top = top, bottom = bottom }
end

local function SearchOnOwnRow(width)
    local blizzDropdown = MerchantFrame.FilterDropdown
    local right = 11 + FILTER_W + 6
    if blizzDropdown and blizzDropdown:IsShown() then right = right + (blizzDropdown:GetWidth() or 152) + 6 end
    return width - SEARCH_LEFT - right < SEARCH_MIN
end

local function Layout()
    if not original then
        local border = _G.MerchantFrameBottomLeftBorder
        original = {
            width = MerchantFrame:GetWidth(), height = MerchantFrame:GetHeight(),
            buyback = _G.MerchantBuyBackItem and { _G.MerchantBuyBackItem:GetPoint(1) } or nil,
            borderAtlas = border and border.GetAtlas and border:GetAtlas() or "UI-Merchant-BotFrame",
        }
    end
    local cols, rows = Columns(), Rows()
    local width = original.width + (cols - BLIZZ_COLS) * COL_W
    local ownRow = SearchOnOwnRow(width)
    local extraTop = ownRow and SEARCH_ROW or 0
    MerchantFrame:SetSize(width, original.height + (rows - BLIZZ_ROWS) * ROW_H + extraTop)

    for i = 1, cols * rows do
        local f = EnsureFrame(i)
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", LEFT + col * COL_W, TOP - extraTop - row * ROW_H)
        f:Show()
    end
    for i = cols * rows + 1, #frames do frames[i]:Hide() end

    -- Rückkauf-Platz bleibt unter den Waren, wenn das Fenster höher wird
    local buyback = _G.MerchantBuyBackItem
    if buyback and original.buyback and original.buyback[1] then
        local p = original.buyback
        buyback:ClearAllPoints()
        buyback:SetPoint(p[1], p[2], p[3], p[4] or 0, (p[5] or 0) - (rows - BLIZZ_ROWS) * ROW_H - extraTop)
    end

    -- Bodenleiste rechts weiterführen: ein schmaler Streifen aus Blizzards Atlas, in die Breite gezogen
    -- (der ganze Atlas würde Rückkauf-Rahmen und Trenner doppelt zeigen)
    local slice = cols > BLIZZ_COLS and _G.MerchantFrameBottomLeftBorder and M.BorderSlice(original.borderAtlas)
    if slice then
        ui.border:ClearAllPoints()
        ui.border:SetTexture(slice.file)
        ui.border:SetTexCoord(slice.left, slice.right, slice.top, slice.bottom)
        ui.border:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", original.width - 3, 26)
        ui.border:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -1, 26)
        ui.border:SetHeight(61)
        ui.border:Show()
    else
        ui.border:Hide()
    end

    -- Suchfeld und Filter: rechts vom Porträt, sonst in einer eigenen Zeile über den Waren
    local blizzDropdown = MerchantFrame.FilterDropdown
    if ui.filter then
        ui.filter:ClearAllPoints()
        if ownRow then
            ui.filter:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -11, TOP + 6)
        elseif blizzDropdown and blizzDropdown:IsShown() then
            ui.filter:SetPoint("RIGHT", blizzDropdown, "LEFT", -6, 0)
        else
            ui.filter:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -11, -32)
        end
    end
    if ui.search then
        ui.search:ClearAllPoints()
        if ownRow then
            ui.search:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", LEFT + 6, TOP + 5)
        else
            ui.search:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", SEARCH_LEFT, -33)
        end
        if ui.filter then
            ui.search:SetPoint("RIGHT", ui.filter, "LEFT", -10, 0)
        else
            ui.search:SetPoint("RIGHT", MerchantFrame, "TOPRIGHT", -11, 0)
        end
    end
    ui.empty:ClearAllPoints()
    ui.empty:SetPoint("TOP", MerchantFrame, "TOP", 0, TOP - extraTop - 2 * ROW_H)
    state.ownRow = ownRow
end

local function Take()
    BlizzardItems(false)
    if _G.MerchantPrevPageButton then MerchantPrevPageButton:Hide() end
    if _G.MerchantNextPageButton then MerchantNextPageButton:Hide() end
    if _G.MerchantPageText then MerchantPageText:Hide() end
    if not state.taken then
        state.taken = true
        ShowUI(true)
    end
    Layout()
end

-- Blizzards Original zurück (Rückkauf-Reiter, Einstellung aus, Gamepad).
function M.Release()
    if not state.taken then return end
    state.taken = false
    ShowUI(false)
    for _, f in ipairs(frames) do f:Hide() end
    if original then
        MerchantFrame:SetSize(original.width, original.height)
        local buyback = _G.MerchantBuyBackItem
        if buyback and original.buyback and original.buyback[1] then
            -- einzeln statt unpack: relativeTo kann nil sein, unpack dürfte dann hinter dem Punktnamen abschneiden (V-127)
            local p = original.buyback
            buyback:ClearAllPoints()
            buyback:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0)
        end
    end
    BlizzardItems(true)
    -- Blätter-Knöpfe hatte Blizzard schon richtig gesetzt; ezMerchant hatte sie nur versteckt.
    if MerchantFrame.selectedTab == 1 and (GetMerchantNumItems() or 0) > BLIZZ_ITEMS then
        if _G.MerchantPrevPageButton then MerchantPrevPageButton:Show() end
        if _G.MerchantNextPageButton then MerchantNextPageButton:Show() end
        if _G.MerchantPageText then MerchantPageText:Show() end
    end
    ns.Fire("MERCHANT_LAYOUT")
end

-- Blizzards Breite des Händlerfensters (für Teile, die rechts davon in die Verbreiterung gehören).
function M.BaseWidth()
    return original and original.width or (MerchantFrame and MerchantFrame:GetWidth()) or 336
end

function Render()
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    if not M.Active() then return M.Release() end
    local ok, err = pcall(function()
        Take()
        local list = BuildList()
        local perPage = M.PerPage()
        local pages = math.max(1, math.ceil(#list / perPage))
        if state.page > pages then state.page = pages end
        local first = (state.page - 1) * perPage
        for i = 1, perPage do FillFrame(frames[i], list[first + i]) end
        local paging = #list > perPage
        ui.prev:SetShown(paging)
        ui.next:SetShown(paging)
        ui.pageText:SetShown(paging)
        if paging then
            ui.prev:SetEnabled(state.page > 1)
            ui.next:SetEnabled(state.page < pages)
            ui.pageText:SetText((_G.MERCHANT_PAGE_NUMBER or L.PAGE_TEXT):format(state.page, pages))
        end
        ui.empty:SetShown(state.filtering and #list == 0)
        state.pages = pages
    end)
    if not ok then
        -- Lieber Blizzards Original als ein halbes Fenster: für diese Sitzung zurück zum Original.
        M.broken = true
        ns.Error(err, "Merchant")
        M.Release()
    end
    ns.Fire("MERCHANT_LAYOUT")
end
M.Render = Render

local RenderSoon = ns.Throttle(function() Render() end, 0.2)

---------------------------------------------------------------------------
-- Menü am Knopf „Filter“ (auch Spalten und Reparatur: so ist alles mit einem sichtbaren Knopf erreichbar)
---------------------------------------------------------------------------

function M.ResetFilters()
    for _, key in ipairs(M.FILTERS) do
        if ns.S[key] then ns.SetSetting(key, false) end
    end
    if ui.search then ui.search:SetText("") end
end

-- ezBags Schnittstelle, wenn ezBag läuft und „Plunder verkaufen“ anbietet; sonst nil (Junk.lua).
function M.JunkAPI()
    return ns.Junk.BagAPI()
end

-- Plunder jetzt verkaufen: mit ezBag nach dessen Regeln, ohne ezBag nur Graues über ezCore (Junk.lua, MER-02).
-- → true, wenn der Verkauf beginnt
function M.SellJunk()
    return ns.Junk.SellNow()
end

-- Aufgebaut mit ezCore.Menu (eine Stelle für alle Menüs); der Knopf „Filter“ ist Blizzards Filter-Vorlage.
function M.BuildMenu(_, root)
    local Menu = Core.Menu
    local function Flag(key)
        return Menu.Toggle(root, L["OPT_" .. key], function() return ns.Enabled(key) end,
            function(value) ns.SetSetting(key, value and true or false) end)
    end
    Menu.Title(root, L.FILTER)
    -- Die Filter stehen seit der Einstellungs-Prüfung vom 19.11.2026 nur hier (nicht mehr auf der Einstellungsseite);
    -- ihre Erklärung kommt darum als Tooltip an den Eintrag.
    for _, key in ipairs(M.FILTERS) do
        if M.FilterOffered(key) then Menu.Tip(Flag(key), L["OPT_" .. key], L["OPT_" .. key .. "_TIP"]) end
    end
    Menu.Button(root, L.FILTER_RESET, M.ResetFilters)
    Menu.Divider(root)
    local options = {}
    for n = ns.LIMITS.columns[1], ns.LIMITS.columns[2] do options[#options + 1] = { n, L.MENU_COLUMNS_N:format(n) } end
    Menu.Choice(root, L.MENU_COLUMNS, options, Columns, function(n) ns.SetSetting("columns", n) end)
    Menu.Divider(root)
    Menu.Title(root, L.MENU_REPAIR)
    Flag("repairAuto")
    Flag("repairGuild")
    -- Vorrat auffüllen (Restock.lua): Knopf mit Kosten, Sollmengen der Waren dieses Händlers, Automatik
    if ns.Restock then
        Menu.Divider(root)
        ns.Restock.BuildMenu(root)
    end
    -- Plunder: Knopf und Schalter, mit ezBag nach dessen Regeln, sonst nur Graues über ezCore (Junk.lua, MER-02)
    if ns.Junk then
        Menu.Divider(root)
        ns.Junk.BuildMenu(root)
    end
    Menu.Divider(root)
    Menu.Settings(root, ns)        -- „Einstellungen …“ mit Zahnrad aus ezCore (T18-8)
end

---------------------------------------------------------------------------
-- Anbindung an Blizzards Händlerfenster
---------------------------------------------------------------------------

local MERCHANT_KEYS = { merchant = true, columns = true, rows = true, markMissing = true,
    markUpgrade = true, stackButton = true }
for _, key in ipairs(M.FILTERS) do MERCHANT_KEYS[key] = true end

function M.Setup()
    if M.ready or not M.Supported() then return end
    M.ready = true
    CreateUI()
    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function() Render() end)
    hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function() M.Release() end)
    MerchantFrame:HookScript("OnShow", function()
        state.page = 1
        if ui.search and ui.search:GetText() ~= "" then ui.search:SetText("") end
        state.query = ""
        Render()
    end)
    MerchantFrame:HookScript("OnHide", function()
        buying = nil
        if ui.search then ui.search:SetText("") end
        state.query = ""
    end)
    -- Mausrad blättert in den eigenen Seiten (Blizzards Blättern tut nichts, solange seine Knöpfe versteckt sind)
    MerchantFrame:HookScript("OnMouseWheel", function(_, delta)
        if state.taken then SetPage(state.page + (delta > 0 and -1 or 1)) end
    end)
    ns.On("GET_ITEM_INFO_RECEIVED", function() if state.taken then RenderSoon() end end)
    local K = Knowledge()
    if K and K.OnReady then K.OnReady(function() if state.taken then RenderSoon() end end) end
    -- ezGear hat neu bewertet (Gewichte, Profil): Pfeile und Filter „Nur Verbesserungen“ neu
    Core.Listen("GEAR_SCORES_CHANGED", function() if state.taken then RenderSoon() end end, ADDON)
end

ns.OnSettingChanged(function(key)
    if not MERCHANT_KEYS[key] then return end
    if key == "columns" or key == "rows" then state.page = 1 end
    if MerchantFrame and MerchantFrame:IsShown() then Render() end
end)

ns.OnReady(function() ns.Try("Merchant", M.Setup) end)

ns.AddStatusLine(function()
    if GamepadUI() then return L.STATUS_GAMEPAD end
    if not (ns.Enabled("merchant") and M.Supported()) then return L.STATUS_MERCHANT_OFF end
    return L.STATUS_MERCHANT_ON:format(Columns(), Rows())
end)
