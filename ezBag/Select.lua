local ADDON, ns = ...
local L = ns.L

--[[
    Mehrfachauswahl und Massenaktionen:
    - Knopf „Auswählen“ in der Werkzeugleiste von Tasche, Bank und ezBag-Fenster schaltet die
      Auswahl ein: Ein Klick auf einen Platz markiert ihn (Häkchen), statt ihn zu benutzen.
    - Klick auf den Knopf, solange die Auswahl läuft (oder Rechtsklick): Menü mit „Alles markieren“, „Auswahl
      beenden“ und den Aktionen für alle markierten Gegenstände – einer Gruppe zuweisen, beim Händler verkaufen,
      an den offenen Brief anhängen (ezCores Versand-Warteschlange), an der Bank einlagern bzw. herausnehmen.
    - Gildenbank: „In die Tasche legen (n)“ entnimmt die markierten Plätze (Transfer.WithdrawSlots, Entnahme-Limit).
    - Die Markierung liegt in eigenen Knöpfen über den Plätzen (eigene Rahmen, darum taint-sicher:
      Blizzards Platz-Knöpfe bekommen keinen Klick und keine Werte).
    Zusammengefasste Stapel (Render.Compact) zählen mit allen ihren Stapeln.
]]

local Select = {}
ns.Select = Select

local SELL_INTERVAL = 0.2
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"

local active = setmetatable({}, { __mode = "k" })     -- [view] = { picked = { [key] = true } }
local pools = setmetatable({}, { __mode = "k" })      -- [view] = { Knopf, … }

-- Schlüssel eines Eintrags: echter Platz (Tasche/Bank, Fach und Platz der Gildenbank) oder Anzeige (Fenster offline).
function Select.KeyOf(entry)
    if type(entry.bag) == "number" and entry.slot then return entry.bag .. ":" .. entry.slot end
    if type(entry.guildTab) == "number" and entry.slot then return "g:" .. entry.guildTab .. ":" .. entry.slot end
    if entry.itemID then return "i:" .. tostring(entry.link or entry.itemID) end
    return nil
end

function Select.IsActive(view)
    return active[view] ~= nil
end

local function State(view)
    return active[view]
end

function Select.IsPicked(view, entry)
    local s = State(view)
    local key = s and Select.KeyOf(entry)
    return key ~= nil and s.picked[key] == true
end

-- Markierte Einträge der Ansicht (nur, was gerade sichtbar ist), samt zusammengefasster Stapel.
function Select.Picked(view)
    local s, list = State(view), {}
    if not s then return list end
    for _, entry in ipairs(view.entries or {}) do
        local key = Select.KeyOf(entry)
        if key and s.picked[key] then
            list[#list + 1] = entry
            for _, other in ipairs(entry.merged or {}) do list[#list + 1] = other end
        end
    end
    return list
end

function Select.Count(view)
    local n = 0
    local s = State(view)
    if not s then return 0 end
    for _, entry in ipairs(view.entries or {}) do
        local key = Select.KeyOf(entry)
        if key and s.picked[key] then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Markier-Knöpfe über den Plätzen
---------------------------------------------------------------------------

local function Picker(view, i)
    local pool = pools[view]
    if not pool then
        pool = {}
        pools[view] = pool
    end
    local p = pool[i]
    if not p then
        p = CreateFrame("Button", nil, view.parent)
        p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        p.fill = p:CreateTexture(nil, "OVERLAY")
        p.fill:SetAllPoints()
        p.fill:SetColorTexture(1, 0.82, 0, 0.18)
        p.check = p:CreateTexture(nil, "OVERLAY", nil, 2)
        p.check:SetTexture(CHECK)
        p.check:SetSize(ezCore.Style.BUTTON.check, ezCore.Style.BUTTON.check)   -- Haken wie Blizzards (20, Core.Style)
        p.check:SetPoint("CENTER")
        p:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        p:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then return Select.OpenMenu(self, self.view) end
            Select.Toggle(self.view, self.entry)
        end)
        p:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.entry and self.entry.link then
                GameTooltip:SetHyperlink(self.entry.link)
            elseif self.entry and self.entry.itemID then
                GameTooltip:SetItemByID(self.entry.itemID)
            end
            GameTooltip:AddLine(L.SELECT_CLICK, ns.TipRGB("hint"))
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", GameTooltip_Hide)
        pool[i] = p
    end
    return p
end

-- Nach jedem Zeichnen (View:Draw) und beim Umschalten.
function Select.Refresh(view)
    local pool = pools[view] or {}
    local n = 0
    if State(view) then
        for _, entry in ipairs(view.entries or {}) do
            local button = entry.button or entry.display
            if button and entry.itemID and Select.KeyOf(entry) then
                n = n + 1
                local p = Picker(view, n)
                p.view, p.entry = view, entry
                p:ClearAllPoints()
                p:SetAllPoints(button)
                p:SetFrameLevel((button:GetFrameLevel() or 1) + 6)
                local picked = Select.IsPicked(view, entry)
                p.check:SetShown(picked)
                p.fill:SetShown(picked)
                p:Show()
            end
        end
    end
    for i = n + 1, #pool do pool[i]:Hide() end
    if view.toolbar and view.toolbar.UpdateSelect then view.toolbar:UpdateSelect() end
end

function Select.SetActive(view, on)
    if not view then return end
    if on then
        active[view] = active[view] or { picked = {} }
    else
        active[view] = nil
    end
    Select.Refresh(view)
end

function Select.ToggleMode(view)
    Select.SetActive(view, not Select.IsActive(view))
end

function Select.Toggle(view, entry)
    local s = State(view)
    local key = s and Select.KeyOf(entry)
    if not key then return end
    s.picked[key] = not s.picked[key] or nil
    Select.Refresh(view)
end

function Select.Clear(view)
    local s = State(view)
    if s then wipe(s.picked) end
    Select.Refresh(view)
end

-- Alles in der Ansicht markieren (oder nur eine Gruppe).
function Select.PickAll(view, groupKey)
    local s = State(view)
    if not s then return end
    for _, entry in ipairs(view.entries or {}) do
        local key = Select.KeyOf(entry)
        if key and entry.itemID and (not groupKey or entry.groupKey == groupKey or entry.rootKey == groupKey) then
            s.picked[key] = true
        end
    end
    Select.Refresh(view)
end

---------------------------------------------------------------------------
-- Aktionen
---------------------------------------------------------------------------

-- Jeden Gegenstand einmal einer Gruppe zuweisen (wie Alt+Rechtsklick).
function Select.Assign(view, groupKey)
    local seen, n = {}, 0
    for _, entry in ipairs(Select.Picked(view)) do
        if entry.itemID and not seen[entry.itemID] then
            seen[entry.itemID] = true
            ns.db.assign[entry.itemID] = (groupKey ~= "auto") and groupKey or nil
            n = n + 1
        end
    end
    if n > 0 then
        local items = ns.CountWord("ITEM", n)
        ns.Print(groupKey == "auto" and L.SELECT_ASSIGNED_AUTO:format(items) or L.SELECT_ASSIGNED:format(items, ns.Groups.Label(groupKey)))
        Select.Clear(view)
        ns.Groups.RefreshAll()
    end
    return n
end

local function LiveSlots(view)
    local list = {}
    for _, entry in ipairs(Select.Picked(view)) do
        if type(entry.bag) == "number" and entry.slot and entry.itemID then
            local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
            if info and info.itemID == entry.itemID and not info.isLocked then
                list[#list + 1] = { bag = entry.bag, slot = entry.slot, itemID = entry.itemID, quality = info.quality,
                    noValue = info.hasNoValue }
            end
        end
    end
    return list
end

local function AtMerchant() return ns.AtMerchant() end
local function AtMail() return SendMailFrame ~= nil and SendMailFrame:IsVisible() end
local function AtBank() return ns.Inventory.IsBankOpen() end

-- Nacheinander benutzen (verkaufen bzw. umlagern), damit der Server mitkommt. Nie im Kampf (T1-2, Gesamtreview
-- 18.11.2026; Risiko 11 in docs/blizzard-regeln.md): beginnt er unterwegs, hört der Ticker auf und meldet combatText.
local useTicker
local function UseAll(slots, stillOk, combatText)
    if useTicker then useTicker:Cancel() end
    local i = 0
    useTicker = C_Timer.NewTicker(SELL_INTERVAL, function(t)
        i = i + 1
        local s = slots[i]
        local fight = s ~= nil and ns.InCombat()
        if not s or fight or not stillOk() then
            t:Cancel()
            useTicker = nil
            if fight then ns.Print(combatText) end
            return
        end
        local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
        if info and info.itemID == s.itemID then C_Container.UseContainerItem(s.bag, s.slot) end
    end, #slots + 1)
end

function Select.Sell(view)
    if not AtMerchant() then return 0 end
    if ns.InCombat() then
        ezCore.CombatNotice(ns, L.SELL_WHAT)   -- ein Satz zur Kampfsperre (T18-1)
        return 0
    end
    local list = {}
    for _, s in ipairs(LiveSlots(view)) do
        if not s.noValue then list[#list + 1] = s end
    end
    if #list == 0 then return 0 end
    ns.Print(L.SELECT_SELLING:format(ns.CountWord("STACK", #list)))
    UseAll(list, AtMerchant, ezCore.CombatText(L.SELL_WHAT))
    Select.Clear(view)
    return #list
end

-- An der Bank: Tasche ↔ Bank (Rechtsklick-Verhalten des Spiels). Wie das Umlagern mit den Pfeilen nie im Kampf.
function Select.Move(view)
    if not AtBank() then return 0 end
    if ns.InCombat() then
        ezCore.CombatNotice(ns, L.TRANSFER_WHAT)
        return 0
    end
    local list = LiveSlots(view)
    if #list == 0 then return 0 end
    UseAll(list, AtBank, ezCore.CombatText(L.TRANSFER_WHAT))
    Select.Clear(view)
    return #list
end

-- An den offenen Brief anhängen (ezCore.MailQueue.Attach, hört auf, wenn der Brief voll ist).
function Select.Attach(view)
    local queue = ezCore.MailQueue
    if not (AtMail() and queue and queue.Attach) then return 0 end
    local entries = {}
    for _, s in ipairs(LiveSlots(view)) do entries[#entries + 1] = { bag = s.bag, slot = s.slot, itemID = s.itemID } end
    if #entries == 0 then return 0 end
    queue.Attach(entries, function(left)
        if type(left) == "number" and left > 0 then ns.Print(ns.CountText("SELECT_MAIL_FULL", left)) end
    end)
    Select.Clear(view)
    return #entries
end

-- Markierte Plätze der offenen Gildenbank: { tab, slot, itemID } je Platz (für Transfer.WithdrawSlots).
local function GuildSlots(view)
    local list = {}
    for _, entry in ipairs(Select.Picked(view)) do
        if type(entry.guildTab) == "number" and entry.slot and entry.itemID then
            list[#list + 1] = { tab = entry.guildTab, slot = entry.slot, itemID = entry.itemID }
        end
    end
    return list
end

-- Gildenbank: markierte Plätze in die Tasche legen – ein Platz je Schritt über den Entnahme-Ablauf (Transfer.lua),
-- der das Entnahme-Limit des Rangs und die volle Tasche beachtet und am Ende meldet, was kam und was blieb.
-- → Zahl der Plätze, deren Entnahme begonnen hat (0 mit Meldung, wenn es nicht geht)
function Select.Withdraw(view)
    local slots = GuildSlots(view)
    if #slots == 0 then return 0 end
    local started, reason = ns.Transfer.WithdrawSlots(slots)
    if not started then
        local text = ns.Transfer.ReasonText(reason)
        if text then ns.Print(text) end
        return 0
    end
    Select.Clear(view)
    return #slots
end

-- → true, wenn das Menü aufging (false: Client ohne Menü-Baukasten)
function Select.OpenMenu(owner, view)
    if not view then return false end
    if not Select.IsActive(view) then Select.SetActive(view, true) end
    local n = Select.Count(view)
    return ezCore.Menu.Open(owner, function(root)
        root:CreateTitle(n > 0 and L.SELECT_TITLE_N:format(n) or L.SELECT_TITLE)
        if n > 0 then
            local assign = root:CreateButton(L.SELECT_ASSIGN)
            assign:CreateButton(L.MENU_AUTO, function() Select.Assign(view, "auto") end)
            assign:CreateDivider()
            for _, key in ipairs(ns.ASSIGNABLE) do
                assign:CreateButton(ns.Groups.Label(key), function() Select.Assign(view, key) end)
            end
            local customs = ns.Groups.CustomKeys()
            if #customs > 0 then
                assign:CreateDivider()
                for _, key in ipairs(customs) do
                    assign:CreateButton(ns.Groups.Label(key), function() Select.Assign(view, key) end)
                end
            end
            local live = #LiveSlots(view)
            if live > 0 and AtMerchant() then
                root:CreateButton(L.SELECT_SELL:format(live), function()
                    ezCore.Confirm(ns.CountText("SELECT_SELL_ASK", live), function() Select.Sell(view) end)
                end)
            end
            if live > 0 and AtMail() then
                root:CreateButton(L.SELECT_MAIL:format(live), function() Select.Attach(view) end)
            end
            if live > 0 and AtBank() then
                root:CreateButton(L.SELECT_MOVE:format(live), function() Select.Move(view) end)
            end
            -- Gildenbank: markierte Plätze entnehmen (dort gibt es kein „Benutzen“ wie an der Bank)
            local stored = #GuildSlots(view)
            if stored > 0 then
                root:CreateButton(L.SELECT_WITHDRAW:format(stored), function() Select.Withdraw(view) end)
            end
            root:CreateDivider()
            root:CreateButton(L.SELECT_CLEAR, function() Select.Clear(view) end)
        end
        root:CreateButton(L.SELECT_ALL, function() Select.PickAll(view) end)
        root:CreateButton(L.SELECT_END, function() Select.SetActive(view, false) end)
    end)
end

---------------------------------------------------------------------------
-- Knopf in der Werkzeugleiste (Toolbar.lua ruft das auf)
---------------------------------------------------------------------------

-- Linksklick: Auswahl einschalten. Läuft sie schon, öffnet auch der Linksklick das Menü – auch ohne markierten
-- Platz, damit „Alles markieren“ und „Auswahl beenden“ einen sichtbaren Weg haben (Leitlinie 3). Rechtsklick: Menü.
function Select.OnToolbarClick(button, view, mouse)
    if not view then return end
    if mouse == "RightButton" or Select.IsActive(view) then
        local wasActive = Select.IsActive(view)
        -- Ohne Menü-Baukasten bleibt der Linksklick der Schalter (sonst ließe sich die Auswahl nicht beenden).
        if Select.OpenMenu(button, view) == false and mouse ~= "RightButton" and wasActive then Select.ToggleMode(view) end
        return
    end
    Select.ToggleMode(view)
end

function Select.TooltipLines(view)
    local lines = { L.SELECT_TIP }
    if view and Select.IsActive(view) then
        local n = Select.Count(view)
        lines[#lines + 1] = { n > 0 and L.SELECT_ACTIVE_N:format(n) or L.SELECT_ACTIVE, ns.TipRGB("good") }
    end
    lines[#lines + 1] = { L.SELECT_RIGHT, ns.TipRGB("hint") }
    return lines
end
