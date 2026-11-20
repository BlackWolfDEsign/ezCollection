local _, ns = ...
local Core = ezCore

--[[
    Haltbarkeit als eine Quelle (vorher in ezPanel, gewünscht von ezGear, ezMerchant, ezPanel-Meldungen).

      Durability.Slot(slot)          → cur, max, pct      (nil, wenn der Platz keine Haltbarkeit hat)
      Durability.SlotCost(slot)      → Reparaturkosten des Platzes in Kupfer (0, wenn unbekannt)
      Durability.BagItem(bag, slot)  → cur, max, pct      Durability.BagItemCost(bag, slot) → Kupfer
      Durability.Equipped()          → { { slot, cur, max, pct } … } nur beschädigbare Plätze
      Durability.Summary()           → { pct, low, lowSlot, broken, damaged, cost }   angelegte Ausrüstung
                                       pct = Summe cur / Summe max, low = schlechtester Platz (0–1)
      Durability.Of(charKey)         → { pct, low, broken, t } gemerkt für jeden Twink (ezCoreDB.chars[key].durability)
      Nachricht: DURABILITY_CHANGED (summary)

    Beim Betrachten anderer Spieler gibt es keine Haltbarkeit (kein API). Werte werden nur gelesen.

    Reparieren als ein Dienst (W-11, VP-16; vorher zweimal: ezMerchant/Repair.lua und der Rückfall in
    ezPanel/Blocks/Repair.lua, dort ohne Guthaben und ohne Nachprüfung). Einstellungen und Meldungen bleiben in den
    Modulen.
      Durability.MerchantOpen()      → true, solange ein Händler offen ist (MERCHANT_SHOW bis MERCHANT_CLOSED)
      Durability.RepairCost()        → Kosten beim offenen Händler oder nil (nichts zu tun, Händler repariert nicht)
      Durability.GuildFunds()        → was die Gildenbank hergibt: das kleinere aus Tageslimit (-1 = unbegrenzt) und
                                       Guthaben; ist das Guthaben nicht lesbar, zählt nur das Limit
      Durability.RepairAll(useGuild, onDone) → ok, zahler, kosten, grund
          zahler = "guild" | "self" | nil, grund = nil | "merchant" (kein Händler, der repariert) | "nothing" |
          "money" (zu wenig Gold) | "pending" (Gilde zahlt, Nachprüfung läuft). Mit der Gilde ist das Ergebnis erst
          nach Durability.GUILD_CHECK_DELAY sicher: Ist dann noch etwas zu reparieren (Bank leer, Limit verbraucht),
          zahlt der Spieler den Rest selbst. onDone(ok, zahler, kosten, grund) kommt genau einmal mit dem
          endgültigen Ergebnis – sofort oder nach der Nachprüfung (nur, solange derselbe Händler offen ist).
      Durability.ReportText(ok, zahler, kosten, grund, melden, geld) → Text für den Chat oder nil (Gesamtreview
          18.11.2026, T16-12; vorher je eine Kopie in ezMerchant und ezPanel samt Texten): Erfolg und „nichts zu
          reparieren“ nur mit melden, „zu wenig Gold“ immer, „pending“ nie (das Ergebnis kommt erst mit onDone). Texte in
          Core.L. geld (frei): Funktion Kupfer → Text, etwa ezPanels ns.Money mit dessen Einstellung „Geldformat“
          (Gegenprüfung P19c); ohne geld Core.Money.
]]

Core.Durability = Core.Durability or {}
local Durability = Core.Durability

local FIRST, LAST = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19

local function Pair(ok, c, m)
    c, m = ok and Core.Num(c), ok and Core.Num(m)
    if not (c and m and m > 0) then return nil end
    return c, m, c / m
end

local function Cost(getter, a, b)
    local api = C_TooltipInfo
    if not (api and api[getter]) then return 0 end
    local ok, data = pcall(api[getter], a, b)
    return ok and type(data) == "table" and Core.Num(data.repairCost) or 0
end

function Durability.Slot(slot)
    if not GetInventoryItemDurability then return nil end
    return Pair(pcall(GetInventoryItemDurability, slot))
end

function Durability.SlotCost(slot) return Cost("GetInventoryItem", "player", slot) end

function Durability.BagItem(bag, slot)
    if not (C_Container and C_Container.GetContainerItemDurability) then return nil end
    return Pair(pcall(C_Container.GetContainerItemDurability, bag, slot))
end

function Durability.BagItemCost(bag, slot) return Cost("GetBagItem", bag, slot) end

function Durability.Equipped()
    local list = {}
    for slot = FIRST, LAST do
        local c, m, pct = Durability.Slot(slot)
        if c then list[#list + 1] = { slot = slot, cur = c, max = m, pct = pct } end
    end
    return list
end

function Durability.Summary()
    local cur, max, low, lowSlot, broken, damaged, cost = 0, 0, nil, nil, 0, 0, 0
    for _, e in ipairs(Durability.Equipped()) do
        cur, max = cur + e.cur, max + e.max
        if not low or e.pct < low then low, lowSlot = e.pct, e.slot end
        if e.cur == 0 then broken = broken + 1 end
        if e.cur < e.max then
            damaged = damaged + 1
            cost = cost + Durability.SlotCost(e.slot)
        end
    end
    return { pct = max > 0 and cur / max or 1, low = low or 1, lowSlot = lowSlot, broken = broken,
        damaged = damaged, cost = cost }
end

function Durability.Of(charKey)
    local c = charKey and Core.Char(charKey)
    return c and c.durability or nil
end

local function Update()
    local me = Core.me
    if not me then return end
    local s = Durability.Summary()
    me.durability = { pct = s.pct, low = s.low, broken = s.broken, t = time and time() or 0 }
    Core.Fire("DURABILITY_CHANGED", s)
end
Durability.Update = Update

---------------------------------------------------------------------------
-- Reparieren (W-11)
---------------------------------------------------------------------------

Durability.GUILD_CHECK_DELAY = 0.5
local merchantOpen, visit = false, 0

function Durability.MerchantOpen()
    return merchantOpen
end

function Durability.RepairCost()
    if not merchantOpen then return nil end
    local can = rawget(_G, "CanMerchantRepair")
    if type(can) ~= "function" then return nil end
    local okCan, repairs = pcall(can)
    if not okCan or Core.IsSecret(repairs) or not repairs then return nil end
    local get = rawget(_G, "GetRepairAllCost")
    if type(get) ~= "function" then return nil end
    local ok, cost, canRepair = pcall(get)
    cost = ok and Core.Num(cost) or nil
    if not ok or Core.IsSecret(canRepair) or not canRepair or not cost or cost <= 0 then return nil end
    return cost
end

function Durability.GuildFunds()
    local limit = Core.Num((Core.Call(rawget(_G, "GetGuildBankWithdrawMoney")))) or 0
    local bank = Core.Num((Core.Call(rawget(_G, "GetGuildBankMoney"))))
    if limit == -1 then return bank or math.huge end
    if bank and bank < limit then return bank end
    return limit
end

local function CanGuild()
    local inGuild = Core.Call(rawget(_G, "IsInGuild"))
    local can = Core.Call(rawget(_G, "CanGuildBankRepair"))
    if Core.IsSecret(inGuild) or Core.IsSecret(can) then return false end
    return inGuild and can and true or false
end

local function Done(onDone, ok, payer, cost, reason)
    if type(onDone) == "function" then
        local okCall, err = pcall(onDone, ok, payer, cost, reason)
        if not okCall then Core.Error(Core.name, err, "Durability.RepairAll") end
    end
    return ok, payer, cost, reason
end

function Durability.ReportText(ok, payer, cost, reason, report, money)
    local L = Core.L
    local format = type(money) == "function" and money or Core.Money
    if ok then
        if not report or reason == "pending" then return nil end
        return (payer == "guild" and L.REPAIR_DONE_GUILD or L.REPAIR_DONE):format(format(Core.Num(cost) or 0))
    elseif reason == "money" then
        return L.REPAIR_NO_MONEY:format(format(Core.Num(cost) or 0))
    elseif (reason == "nothing" or reason == "merchant") and report then
        return L.REPAIR_NOTHING
    end
    return nil
end

local function PaySelf(cost, onDone)
    local money = Core.Num((Core.Call(rawget(_G, "GetMoney")))) or 0
    if money < cost then return Done(onDone, false, nil, cost, "money") end
    RepairAllItems()
    return Done(onDone, true, "self", cost, nil)
end

function Durability.RepairAll(useGuild, onDone)
    if not merchantOpen then return Done(onDone, false, nil, nil, "merchant") end
    local cost = Durability.RepairCost()
    if not cost then
        local can = Core.Call(rawget(_G, "CanMerchantRepair"))
        return Done(onDone, false, nil, nil, can and "nothing" or "merchant")
    end
    if useGuild and CanGuild() and Durability.GuildFunds() >= cost then
        RepairAllItems(true)
        local atVisit = visit
        C_Timer.After(Durability.GUILD_CHECK_DELAY, function()
            if not merchantOpen or atVisit ~= visit then return end   -- Händler zu: keine Aussage mehr
            local rest = Durability.RepairCost()
            if not rest then
                Done(onDone, true, "guild", cost, nil)
            else
                PaySelf(rest, onDone)
            end
        end)
        return true, "guild", cost, "pending"
    end
    return PaySelf(cost, onDone)
end

ns.On("MERCHANT_SHOW", function()
    merchantOpen = true
    visit = visit + 1
end)
ns.On("MERCHANT_CLOSED", function() merchantOpen = false end)

local Later = Core.Throttle(Update, 0.5, Core.name)
ns.On("UPDATE_INVENTORY_DURABILITY", Later)
ns.On("PLAYER_EQUIPMENT_CHANGED", Later)
Core.Listen("CHARS_READY", Later)
