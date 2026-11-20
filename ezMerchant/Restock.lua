local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Vorrat auffüllen (W-39, MER-05, VP-48; Frage 25 – Empfehlung umgesetzt, Antwort offen):
      - Sollmengen je Charakter (ezMerchantDB.restock[Charakter][itemID] = { amount, name }): Rechtsklick auf das
        Plus an einer Ware oder Menü „Filter“ » „Sollmenge festlegen“ fragt nach der Menge (Core.AskText); 0 streicht.
        Gedacht für Reagenzien, Giftzutaten und Munition – die Liste pflegst du selbst, ezMerchant bringt keine
        fremde Tabelle mit (Leitlinie 10).
      - Knopf „Vorrat auffüllen (Kosten)“ unten im breiten Händlerfenster (neben den Häkchen der Reparatur, wenn Platz
        ist) und immer im Menü „Filter“. Ein Klick kauft nur, was dieser Händler führt, bis zur Sollmenge (Bestand in
        den Taschen über Core.ItemCount), in Teilen wie „Mehrere kaufen“ (Merchant.lua, M.StartBuying), auf
        Bezahlbares begrenzt; schließt der Händler, bricht der Kauf ab. Während des Kaufs heißt der Knopf „Anhalten“.
        Waren mit Sonderwährung kauft ezMerchant hier nicht (Blizzard fragt dort nach).
      - Automatik „beim Öffnen des Händlers auffüllen“ (restockAuto) ab Werk aus. Übernimmt schon ein anderes Addon
        das Auffüllen (ns.OtherFor("restock"), Liste in ezCore), füllt ezMerchant nicht von selbst auf und nennt es.
]]

local Rs = {}
ns.Restock = Rs

Rs.MAX_TARGET = 99999         -- mehr fragt der Dialog nicht ab (6 Zeichen)
Rs.MENU_LIMIT = 40            -- so viele Waren im Untermenü „Sollmenge festlegen“
Rs.AUTO_DELAY = 0.5           -- nach dem Öffnen (die Reparatur läuft nach 0,2 s)
Rs.STOP_GUARD = 0.4           -- der zweite Klick eines Doppelklicks hält nicht an (wie „Alles lernen“)
-- Knopf unten rechts in der Verbreiterung; links davon die Häkchen der Reparatur (etwa 120 breit, Repair.lua)
Rs.BUTTON_W, Rs.CHECKS_W, Rs.MARGIN = 160, 120, 12

-- Letzte Zeile von „Meine Sollmengen ändern“, wenn die Liste länger ist als Rs.MENU_LIMIT: „und 3 weitere (alle:
-- /ezh vorrat)“ – der Rest aus ezCore (Core.More, mit Einzahl „und noch 1“; Welle 23), dahinter der Verweis mit dem
-- geltenden Befehl (ns.SlashCmd: /ezh nur, wenn frei – T18-2).
function Rs.MoreText(rest)
    return Core.More(rest, true) .. " " .. L.MENU_RESTOCK_ALL:format(ns.SlashCmd())
end

-- Weg zur Einstellung „Knopf „Vorrat auffüllen““ in der einen Form (Core.SettingsPathText, T18-18)
function Rs.DisabledText()
    return L.RESTOCK_DISABLED:format(Core.SettingsPathText("ezMerchant", "OPT_HEADER_RESTOCK", "OPT_restock", L))
end

---------------------------------------------------------------------------
-- Sollmengen (je Charakter)
---------------------------------------------------------------------------

local function Store()
    local all = ns.db and ns.db.restock
    local key = ns.charKey or Core.charKey
    if type(all) ~= "table" or key == nil then return nil end
    if type(all[key]) ~= "table" then all[key] = {} end
    return all[key]
end

local function Amount(value)
    if type(value) == "table" then value = value.amount end
    value = ns.Num(value)
    return value and value > 0 and math.floor(value) or nil
end

-- Sollmenge eines Gegenstands (itemID) für diesen Charakter oder nil.
function Rs.Target(itemID)
    local store = Store()
    itemID = Core.ItemID(itemID)
    return store and itemID and Amount(store[itemID]) or nil
end

-- Sollmenge setzen; amount 0 oder nil streicht den Eintrag. → true, wenn gespeichert.
function Rs.SetTarget(itemID, amount, name)
    local store = Store()
    itemID = Core.ItemID(itemID)
    if not (store and itemID) then return false end
    amount = ns.Num(amount)
    if not amount or amount <= 0 then
        store[itemID] = nil
    else
        local old = type(store[itemID]) == "table" and store[itemID] or {}
        store[itemID] = { amount = math.min(Rs.MAX_TARGET, math.floor(amount)), name = name or old.name }
    end
    Rs.Update()
    return true
end

-- Alle Sollmengen: { { id, amount, name } … } nach Name.
function Rs.List()
    local list = {}
    for id, value in pairs(Store() or {}) do
        local amount = Amount(value)
        if amount then
            local name = Core.ItemNameByID(id, true) or (type(value) == "table" and value.name) or ("#" .. tostring(id))
            list[#list + 1] = { id = id, amount = amount, name = name }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function Rs.Clear()
    local all = ns.db and ns.db.restock
    local key = ns.charKey or Core.charKey
    if type(all) == "table" and key ~= nil then all[key] = {} end
    Rs.Update()
end

-- Vergisst ezCore einen Charakter, vergisst ezMerchant seine Sollmengen mit.
Core.Listen("CHAR_FORGOTTEN", function(key)
    if ns.db and type(ns.db.restock) == "table" and key ~= nil then ns.db.restock[key] = nil end
end, ADDON)

-- Übernimmt schon ein anderes Addon das Auffüllen? Name oder nil (ezCore, OtherAddOns.lua; jeder Aufruf frisch).
function Rs.Other()
    return (ns.OtherFor("restock"))
end

---------------------------------------------------------------------------
-- Was würde gekauft?
---------------------------------------------------------------------------

local function ItemAt(index)
    local id = GetMerchantItemID and ns.Num(GetMerchantItemID(index))
    if not id then
        local link = GetMerchantItemLink(index)
        id = link and Core.ItemID(link)
    end
    return id
end
Rs.ItemAt = ItemAt

local function MerchantOpen() return MerchantFrame ~= nil and MerchantFrame:IsShown() == true end

--[[
    Rs.Plan() → {
      entries = { { index, id, link, name, have, want, buy, cost, unit, chunk } … }   was gekauft wird, Reihenfolge der Waren
      total   = Kosten in Kupfer
      sold    = Zahl der Sollmengen, die dieser Händler führt
      full    = davon schon erreicht
      short   = { { name, want, can } … }   zu wenig Gold (gekauft wird so viel, wie reicht)
      special = { name … }                  Sonderwährung oder nicht kaufbar: nicht hier
      soldOut = { name … }                  begrenzter Vorrat des Händlers, gerade ausverkauft
    }
]]
function Rs.Plan()
    local plan = { entries = {}, total = 0, sold = 0, full = 0, short = {}, special = {}, soldOut = {} }
    local store = Store()
    if not (store and next(store) and MerchantOpen() and GetMerchantNumItems and C_MerchantFrame) then return plan end
    local money = ns.Num(GetMoney()) or 0
    local seen = {}
    for index = 1, ns.Num(GetMerchantNumItems()) or 0 do
        local id = ItemAt(index)
        local want = id and not seen[id] and Amount(store[id])
        if want then
            seen[id] = true
            plan.sold = plan.sold + 1
            local info = C_MerchantFrame.GetItemInfo(index)
            local have = Core.ItemCount(id)
            local need = want - have
            local name = info and Core.Plain(info.name) or Core.ItemNameByID(id, true) or ("#" .. id)
            if need <= 0 then
                plan.full = plan.full + 1
            elseif not info or info.hasExtendedCost or info.isPurchasable == false then
                plan.special[#plan.special + 1] = name
            elseif ns.Num(info.numAvailable) == 0 then          -- -1 heißt unbegrenzt, 0 ausverkauft
                plan.soldOut[#plan.soldOut + 1] = name
            else
                local unit = math.max(1, ns.Num(info.stackCount) or 1)
                local price = math.max(0, ns.Num(info.price) or 0)          -- Preis je Bündel (unit Stück)
                local bundles = math.ceil(need / unit)
                local stock = ns.Num(info.numAvailable)
                if stock and stock >= 0 then bundles = math.min(bundles, stock) end
                if price > 0 and bundles * price > money then
                    local can = math.floor(money / price)
                    plan.short[#plan.short + 1] = { name = name, want = bundles * unit, can = can * unit }
                    bundles = can
                end
                if bundles > 0 then
                    local cost = bundles * price
                    plan.entries[#plan.entries + 1] = { index = index, id = id, link = GetMerchantItemLink(index), name = name,
                        have = have, want = want, buy = bundles * unit, cost = cost, unit = unit,
                        chunk = ns.Merchant.Chunk(index, unit) }
                    plan.total = plan.total + cost
                    money = money - cost
                end
            end
        end
    end
    return plan
end

---------------------------------------------------------------------------
-- Kaufen: eine Ware nach der anderen, jede in Teilen (M.StartBuying)
---------------------------------------------------------------------------

-- Warum nichts zu kaufen ist (Plan ohne Einträge): Text für Chat und Tooltip.
function Rs.EmptyReason(plan)
    if plan.sold == 0 then return L.RESTOCK_NOT_SOLD end
    if #plan.short > 0 then return L.RESTOCK_NO_MONEY end
    if plan.full == plan.sold then return L.RESTOCK_FULL end
    local parts = Rs.Notes(plan)
    if #parts == 0 then return L.RESTOCK_FULL end
    return table.concat(parts, " ")
end

-- Hinweise zu Waren, die hier nicht gekauft werden (ausverkauft, Sonderwährung). → { Text … }
function Rs.Notes(plan)
    local parts = {}
    if #plan.soldOut > 0 then parts[#parts + 1] = L.RESTOCK_SOLD_OUT:format(table.concat(plan.soldOut, ", ")) end
    if #plan.special > 0 then parts[#parts + 1] = L.RESTOCK_SPECIAL:format(table.concat(plan.special, ", ")) end
    return parts
end

local run          -- { entries, pos, done = { { name, n } }, spent, short, notes, current, entry }

local function Summary(done)
    local parts = {}
    for _, d in ipairs(done) do
        if d.n > 0 then parts[#parts + 1] = L.RESTOCK_ITEM:format(d.n, d.name) end
    end
    return table.concat(parts, ", ")
end

local function Finish(stopped)
    local job = run
    run = nil
    if not job then return end
    local bought = Summary(job.done)
    if bought == "" then
        ns.Print(stopped and L.RESTOCK_STOPPED_NONE or L.RESTOCK_NOTHING_BOUGHT)
    elseif stopped then
        ns.Print(L.RESTOCK_STOPPED:format(bought, ns.Money(job.spent)))
    else
        ns.Print(L.RESTOCK_DONE:format(bought, ns.Money(job.spent)))
    end
    for _, s in ipairs(job.short or {}) do
        ns.Print(L.RESTOCK_SHORT:format(s.name, s.can, s.want))
    end
    for _, text in ipairs(job.notes or {}) do ns.Print(text) end
    Rs.Update()
end

local function Record(entry, n)
    n = math.max(0, ns.Num(n) or 0)
    run.done[#run.done + 1] = { name = entry.link or entry.name, n = n }
    if entry.buy > 0 then run.spent = run.spent + math.floor(entry.cost * n / entry.buy + 0.5) end
end

local Next
-- Nächste Ware nach dem Abstand zwischen zwei Käufen – nur, solange derselbe Lauf noch läuft (ein neuer Lauf nach
-- „Anhalten“ hat seine eigene Kette).
local function NextLater(job) C_Timer.After(ns.Merchant.STEP_DELAY, function() if run == job then Next() end end) end

Next = function()
    local job = run
    if not job then return end
    if not MerchantOpen() then return Finish(true) end
    job.pos = job.pos + 1
    local entry = job.entries[job.pos]
    if not entry then return Finish(false) end
    if GetMerchantItemLink(entry.index) ~= entry.link then return Next() end   -- Liste hat sich verschoben
    local current = { index = entry.index, link = entry.link, name = entry.name, left = entry.buy, total = entry.buy,
        bought = 0, chunk = entry.chunk }
    current.onDone = function(j)
        if run ~= job then return end
        Record(entry, j.bought)
        job.current = nil
        NextLater(job)
    end
    current.onStop = function(_, got)
        if run ~= job then return end
        Record(entry, got)
        job.current = nil
        Finish(true)
    end
    job.current, job.entry = current, entry
    if not ns.Merchant.StartBuying(current) then
        job.current = nil
        Finish(true)
    end
end

function Rs.Busy() return run ~= nil end

-- Auffüllen beginnen. auto = true: Automatik beim Öffnen (still, wenn nichts fehlt; fragt nie nach).
-- Die Automatik kauft nie im Kampf (Gesamtreview 18.11.2026, T1-6; docs/blizzard-regeln.md Tabelle 5): im Kampf
-- wartet sie bis danach (ns.AfterCombat) und läuft nur, wenn der Händler dann noch offen ist; beginnt ein Kampf
-- während des Auffüllens, hält sie an. Der Klick auf „Vorrat jetzt auffüllen“ bleibt auch im Kampf möglich
-- (BuyMerchantItem ist nicht geschützt; der Spieler hat geklickt).
-- → true, wenn ein Kauf beginnt (oder die Rückfrage bei hohen Kosten offen ist).
function Rs.Run(auto)
    if run then return false end
    if auto and ns.InCombat() then
        -- nach dem Kampf die Bedingungen von MERCHANT_SHOW erneut prüfen (Gegenprüfung P17: Schalter im Kampf
        -- ausgeschaltet oder ein anderes Addon füllt inzwischen auf – dann nichts kaufen)
        ns.AfterCombat(function()
            if MerchantOpen() and ns.Enabled("restockAuto") and not Rs.Other() then
                ns.Try("RestockAuto", Rs.Run, true)
            end
        end, "restockAuto")
        return false
    end
    if not ns.Enabled("restock") then          -- Einstellung aus: auch „Vorrat jetzt auffüllen“ ruht
        if not auto then ns.Print(Rs.DisabledText()) end
        return false
    end
    if not MerchantOpen() then
        if not auto then ns.Print(L.RESTOCK_NEED_MERCHANT) end
        return false
    end
    local M = ns.Merchant
    if not (M and M.StartBuying) or M.Buying() then return false end
    local plan = Rs.Plan()
    if #plan.entries == 0 then
        if not auto then ns.Print(Rs.EmptyReason(plan)) end
        return false
    end
    local function Go()
        if run or not MerchantOpen() or M.Buying() then return end
        run = { entries = plan.entries, pos = 0, done = {}, spent = 0, short = plan.short, notes = Rs.Notes(plan),
            started = GetTime(), auto = auto == true }
        Next()
        Rs.Update()
    end
    local high = _G.MERCHANT_HIGH_PRICE_COST or 1500000
    if plan.total >= high then
        if auto then
            ns.Print(L.RESTOCK_AUTO_HIGH:format(ns.Money(plan.total)))
            return false
        end
        Core.Confirm(L.RESTOCK_CONFIRM:format(ns.Money(plan.total)), Go)
        return true
    end
    Go()
    return true
end

-- Anhalten (der Knopf heißt während des Kaufs „Anhalten“). → true, wenn ein Lauf angehalten wurde.
function Rs.Stop()
    if not run then return false end
    if run.current and ns.Merchant.StopBuying() then return true end   -- onStop beendet den Lauf
    Finish(true)
    return true
end

function Rs.Click()
    if run then
        if GetTime() - (run.started or 0) < Rs.STOP_GUARD then return false end
        return Rs.Stop()
    end
    return Rs.Run(false)
end

-- Händler zu: Merchant.lua bricht den laufenden Teil ab (OnHide); hier zählt, was davon schon gekauft war.
ns.On("MERCHANT_CLOSED", function()
    if not run then return end
    if run.current and ns.Merchant.StopBuying() then return end   -- Teil lief noch: onStop zählt und beendet
    if run.current and run.entry then
        Record(run.entry, run.current.bought)
        run.current = nil
    end
    Finish(true)
end)

-- Kampfbeginn während der Automatik: anhalten (T1-6); von Hand Begonnenes läuft weiter.
ns.On("PLAYER_REGEN_DISABLED", function()
    if run and run.auto then Rs.Stop() end
end)

ns.On("MERCHANT_SHOW", function()
    if not (ns.Enabled("restock") and ns.Enabled("restockAuto")) or Rs.Other() then return end
    C_Timer.After(Rs.AUTO_DELAY, function() ns.Try("RestockAuto", Rs.Run, true) end)
end)

-- Hinweis am Händler (ezCores Hinweis-Helfer, einmal je Account; Antwort des Nutzers vom 17.11.2026: was ohne Klick
-- Gold kostet, ist ab Werk aus und bekommt einen Hinweis mit Knopf „Einschalten“). restockAuto war schon aus. Nur mit
-- eingeschaltetem „Vorrat auffüllen“ und mindestens einer Sollmenge, und solange kein anderes Addon auffüllt.
function Rs.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezMerchant.restockAuto", {
        owner = ADDON,
        window = "merchant",
        label = function() return L.OPT_restockAuto end,
        what = function() return L.OPTIN_restockAuto end,
        isOn = function() return ns.Enabled("restockAuto") == true end,
        enable = function()
            ns.SetSetting("restockAuto", true)
            return ns.Enabled("restockAuto") == true
        end,
        applies = function() return ns.Enabled("restock") == true and #Rs.List() > 0 and Rs.Other() == nil end,
    })
end
Rs.RegisterOptInHint()

---------------------------------------------------------------------------
-- Sollmenge festlegen (Plus an der Ware, Menü „Filter“)
---------------------------------------------------------------------------

function Rs.AskTarget(index)
    local id = index and ItemAt(index)
    local info = id and C_MerchantFrame.GetItemInfo(index)
    if not id then return false end
    local name = info and Core.Plain(info.name) or Core.ItemNameByID(id, true) or ("#" .. id)
    local suggest = Rs.Target(id) or (ns.Merchant.StackSize and ns.Merchant.StackSize(index)) or 1
    return Rs.AskTargetID(id, name, suggest)
end

-- Sollmenge eines Gegenstands abfragen – auch ohne Händler, der ihn führt (Untermenü „Meine Sollmengen“).
function Rs.AskTargetID(id, name, suggest)
    id = Core.ItemID(id)
    if not id then return false end
    name = name or Core.ItemNameByID(id, true) or ("#" .. id)
    local current = Rs.Target(id)
    suggest = suggest or current or 1
    Core.AskText(L.RESTOCK_ASK:format(name, Core.ItemCount(id), current or 0), tostring(suggest), function(text)
        local n = tonumber(text)
        if not n or n < 0 then return ns.Print(L.RESTOCK_INVALID) end
        n = math.min(Rs.MAX_TARGET, math.floor(n))
        Rs.SetTarget(id, n, name)
        if n == 0 then
            ns.Print(L.RESTOCK_REMOVED:format(name))
        else
            ns.Print(L.RESTOCK_SET:format(name, n))
        end
    end, 6)
    return true
end

function Rs.PrintList()
    local list = Rs.List()
    if #list == 0 then return ns.Print(L.RESTOCK_LIST_EMPTY) end
    ns.Print(L.RESTOCK_LIST_HEAD:format(#list))
    for _, e in ipairs(list) do
        ns.Print(L.RESTOCK_LIST_LINE:format(e.name, e.amount, Core.ItemCount(e.id)))
    end
end

-- Einträge im Menü am Knopf „Filter“ (Merchant.lua ruft das).
function Rs.BuildMenu(root)
    local Menu = Core.Menu
    Menu.Title(root, L.MENU_RESTOCK)
    if ns.Enabled("restock") and MerchantOpen() then
        if run then
            Menu.Button(root, L.RESTOCK_STOP, function() ns.Try("Restock", Rs.Stop) end)
        else
            local plan = Rs.Plan()
            if #plan.entries > 0 then
                Menu.Button(root, L.RESTOCK_COST:format(Core.PlainMoney(plan.total)), function() ns.Try("Restock", Rs.Click) end)
            end
        end
    end
    local sub = Menu.Button(root, L.MENU_RESTOCK_SET)
    local seen, count = {}, 0
    for index = 1, (MerchantOpen() and ns.Num(GetMerchantNumItems()) or 0) do
        local id = ItemAt(index)
        if id and not seen[id] and count < Rs.MENU_LIMIT and ns.Merchant.StackSize(index) > 1 then
            seen[id] = true
            count = count + 1
            local info = C_MerchantFrame.GetItemInfo(index)
            local name = info and Core.Plain(info.name) or ("#" .. id)
            local target = Rs.Target(id)
            local label = target and L.MENU_RESTOCK_ITEM:format(name, target) or name
            Menu.Button(sub, label, function() ns.Try("RestockAsk", Rs.AskTarget, index) end)
        end
    end
    if count == 0 then Menu.Button(sub, L.MENU_RESTOCK_NONE) end
    -- Alle Sollmengen dieses Charakters ändern oder streichen, auch wenn dieser Händler die Ware nicht führt
    local mine = Menu.Button(root, L.MENU_RESTOCK_MINE)
    local list = Rs.List()
    for i = 1, math.min(#list, Rs.MENU_LIMIT) do
        local e = list[i]
        Menu.Button(mine, L.MENU_RESTOCK_ITEM:format(e.name, e.amount), function()
            ns.Try("RestockAsk", Rs.AskTargetID, e.id, e.name)
        end)
    end
    -- Rest der Liste: „und 3 weitere“ aus ezCore (Core.More, mit Einzahl „und noch 1“), dahinter der Verweis
    if #list > Rs.MENU_LIMIT then Menu.Button(mine, Rs.MoreText(#list - Rs.MENU_LIMIT)) end
    if #list == 0 then Menu.Button(mine, L.MENU_RESTOCK_MINE_NONE) end
    if ns.Enabled("restock") then                   -- ohne den Knopf bewirkt die Automatik nichts (MERCHANT_SHOW)
        Menu.Toggle(root, L.OPT_restockAuto, function() return ns.Enabled("restockAuto") end,
            function(value) ns.SetSetting("restockAuto", value and true or false) end)
    end
    Menu.Button(root, L.MENU_RESTOCK_LIST, function() Rs.PrintList() end)
end

---------------------------------------------------------------------------
-- Knopf unten im breiten Händlerfenster
---------------------------------------------------------------------------

local button

-- Platz rechts neben den Häkchen der Reparatur in der Verbreiterung? → true
function Rs.Fits()
    local M = ns.Merchant
    if not (M and M.state and M.state.taken and MerchantFrame) then return false end
    local width = ns.Num(MerchantFrame:GetWidth()) or 0
    local room = width - M.BaseWidth() - Rs.MARGIN * 2
    if ns.Repair and ns.Repair.ChecksShown and ns.Repair.ChecksShown() then room = room - Rs.CHECKS_W end
    return room >= Rs.BUTTON_W
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    -- Rollen statt Farbzahlen (T9-6): Titel weiß, Text gold, Waren weiß, Fehlendes rot, Hinweise und Quelle grau
    Core.TipTitle(GameTooltip, run and L.RESTOCK_STOP or L.RESTOCK)
    if run then
        Core.TipText(GameTooltip, L.RESTOCK_STOP_TIP)
        GameTooltip:Show()
        return
    end
    local plan = Rs.Plan()
    if #plan.entries == 0 then
        Core.TipText(GameTooltip, Rs.EmptyReason(plan))
    else
        Core.TipText(GameTooltip, L.RESTOCK_TIP:format(ns.Money(plan.total)))
        for _, e in ipairs(plan.entries) do
            Core.TipDoubleLine(GameTooltip, L.RESTOCK_TIP_LINE:format(e.buy, e.name, e.have, e.want), ns.Money(e.cost),
                "highlight", "highlight")
        end
    end
    for _, s in ipairs(plan.short) do
        Core.TipLine(GameTooltip, L.RESTOCK_SHORT:format(s.name, s.can, s.want), "bad", true)
    end
    if #plan.entries > 0 or #plan.short > 0 then      -- sonst stehen die Hinweise schon oben (EmptyReason)
        for _, text in ipairs(Rs.Notes(plan)) do Core.TipLine(GameTooltip, text, "hint", true) end
    end
    local other = Rs.Other()
    if other then Core.TipText(GameTooltip, L.RESTOCK_OTHER:format(other)) end
    Core.TipLine(GameTooltip, L.RESTOCK_SOURCE, "hint", true)
    GameTooltip:Show()
end

function Rs.Update()
    if not button then return end
    local plan = ns.Enabled("restock") and Rs.Fits() and Rs.Plan()
    local shown = plan and (plan.sold > 0 or run ~= nil) or false
    button:SetShown(shown)
    if not shown then return end
    button:ClearAllPoints()
    button:SetPoint("BOTTOMRIGHT", MerchantFrame, "BOTTOMRIGHT", -Rs.MARGIN, 44)
    if run then
        button:SetText(L.RESTOCK_STOP)
        button:SetEnabled(true)
        return
    end
    local text = plan.total > 0 and L.RESTOCK_COST:format(Core.PlainMoney(plan.total)) or L.RESTOCK
    button:SetText(text)
    local label = button.GetFontString and button:GetFontString()
    if label and label.GetStringWidth and (ns.Num(label:GetStringWidth()) or 0) > Rs.BUTTON_W - 12 then
        button:SetText(L.RESTOCK)
    end
    button:SetEnabled(#plan.entries > 0)
end

local UpdateSoon = ns.Throttle(function() Rs.Update() end, 0.1)

local function CreateButton()
    if button or not MerchantFrame then return end
    local ok, b = pcall(CreateFrame, "Button", "ezMerchantRestockButton", MerchantFrame, "UIPanelButtonTemplate")
    if not ok or not b then return end
    button = b
    button:SetSize(Rs.BUTTON_W, 22)
    if button.SetMotionScriptsWhileDisabled then button:SetMotionScriptsWhileDisabled(true) end
    button:SetScript("OnClick", function() ns.Try("Restock", Rs.Click) end)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    Rs.button = button
end

ns.OnReady(function()
    ns.Try("Restock", CreateButton)
    ns.Listen("MERCHANT_LAYOUT", function() Rs.Update() end)
    ns.On("MERCHANT_UPDATE", function() UpdateSoon() end)
    ns.On("BAG_UPDATE_DELAYED", function() if button and button:IsShown() then UpdateSoon() end end)
    ns.On("PLAYER_MONEY", function() if button and button:IsShown() then UpdateSoon() end end)
end)

local RESTOCK_KEYS = { restock = true, restockAuto = true, columns = true }
ns.OnSettingChanged(function(key) if RESTOCK_KEYS[key] then UpdateSoon() end end)

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

ns.AddStatusLine(function()
    if not ns.Enabled("restock") then return L.STATUS_RESTOCK_OFF end
    local other = Rs.Other()
    if other then return L.RESTOCK_OTHER:format(other) end
    return L.STATUS_RESTOCK:format(#Rs.List(), ns.Enabled("restockAuto") and L.STATUS_RESTOCK_AUTO or "")
end)
