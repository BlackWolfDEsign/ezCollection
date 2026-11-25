local _, ns = ...
local L = ns.L

--[[
    Reparatur (Titan Repair): Haltbarkeit, Reparaturkosten, beschädigte
    Gegenstände, Wert der grauen Gegenstände, automatisches Reparieren.
    Haltbarkeit und Kosten liest ezCore (ezCore.Durability, eine Quelle für alle Module):
    Summen aus Durability.Summary(), die beschädigten Plätze aus Equipped(), die Twinks aus Of(key).
    Plunder: Läuft ezBag, entscheidet ezBag (Schlösser, eigene Markierungen) – Wert über
    ezCore.API("ezBag").IsJunk(bag, slot), Verkaufen über SellJunk(). Ohne ezBag zählt ezPanel die grauen
    Gegenstände selbst und verkauft sie über ezCores Dienst (Core.Junk.Sell, nie im Kampf; Welle 28).
    Verbesserungen:
      - Ereignisse werden gesammelt und nachgeholt statt verworfen (Werte
        veralten nicht), noch nicht geladene Gegenstände werden nachgeladen.
      - Keine erfundenen Ruf-Rabatte: beim Händler zeigt ezPanel die echten
        Kosten (GetRepairAllCost), die der Server bereits rabattiert.
      - Gildenreparatur fällt auf eigenes Gold zurück, wenn Gildenlimit oder
        Guthaben der Gildenbank nicht reichen (ausgeführt von ezCore,
        Core.Durability.RepairAll, PANEL-04). Läuft schon die Auto-Reparatur
        von Leatrix Plus, hält sich ezPanel heraus.
    Automatisch reparieren zieht nach ezMerchant (Händler und Lehrer, abgestimmt am 13.11.2026):
    Ist ezMerchant geladen, repariert ezPanel nicht mehr selbst und zeigt nur an –
    ezCore.API("ezMerchant"): AutoRepair() → aktiv, Gildenbank, repariert ein anderes Addon?, dessen Name (vier Werte,
    der Vertrag seit ezMerchant 1.x); RepairNow(useGuild) für den Klick beim Händler; OpenSettings(). Ältere Formen
    (Tabelle { enabled, guild, leatrix }, zwei Werte plus Leatrix()) versteht ezPanel weiter. Ohne ezMerchant
    bleibt alles wie bisher. Die bisherigen Einstellungen bietet ezPanel ezMerchant zur
    einmaligen Übernahme an (ns.RepairSettings hier, als ezCore.API("ezPanel").RepairSettings in API.lua).
    Seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 62; Entscheidung des Nutzers „Ja, alle umsetzen“) gibt es EINEN
    Schaltersatz „Automatisch reparieren“ (an, Gildengeld zuerst, Kosten melden) in ezCore (Gruppe vendor, ab Werk aus)
    für ezMerchant und ezPanel: das Menü des Bausteins, ezMerchants Seite und Häkchen und die Seite „ezCollection“
    zeigen und schalten denselben Wert. Die alten Werte aus ezPanels Profilen gehen einmal dorthin (ohne ezMerchant hier
    über Core.Junk.AdoptPanelRepair, mit ezMerchant über dessen Übernahme); sie selbst bleiben unverändert liegen.
]]

local block = ns.RegisterBlock({
    id = "repair",
    command = "reparatur",
    name = L.REPAIR_NAME,
    label = L.REPAIR_LABEL,
    icon = "Interface\\Icons\\Trade_BlackSmithing",
    events = {},
    colorable = true,
    defaults = {
        enabled = true, zone = "left", order = 50,
        mode = "total",        -- total | lowest
        cost = true,
        inventory = false,
        -- autoRepair, guild, report: seit der Einstellungs-Prüfung vom 19.11.2026 ezCores gemeinsamer Schaltersatz
        -- (RepairOn/RepairGuild/RepairReport unten); alte Werte in den Profilen liest nur noch ns.RepairSettings
    },
    hints = function() return { L.REPAIR_HINT_LEFT, ezCore.ClickText("left", "SHIFT", L.REPAIR_HINT_SHIFT) } end,   -- T18-9
})

---------------------------------------------------------------------------
-- Erfassen
---------------------------------------------------------------------------

local state = { items = {}, equipCost = 0, bagCost = 0, pct = nil, lowest = nil, grey = 0 }
local merchantOpen = false
local missingInfo = false

local Durability = ezCore.Durability   -- Slot, SlotCost, BagItem, BagItemCost, Of

-- Der gemeinsame Schaltersatz „Automatisch reparieren“ in ezCore (Core.Junk.RepairSettings, Gruppe vendor).
local function RepairOn() return (ezCore.Junk.RepairSettings()) == true end
local function RepairGuild() return select(2, ezCore.Junk.RepairSettings()) == true end
local function RepairReport() return select(3, ezCore.Junk.RepairSettings()) == true end
local function SetRepair(key, on)
    ezCore.SetShared("vendor", key, on == true)
    ns.QueueUpdate(block)
    return true
end

local function ItemName(link, id)
    local name = link and link:match("%[(.-)%]")
    if not name and id then
        name = ezCore.ItemNameByID(id)   -- fordert fehlende Daten an
        if not name then missingInfo = true end
    end
    return name or "?"
end

local function SellPrice(id)
    if not id then return 0 end
    local price = ezCore.VendorPrice(id)
    if price == nil then
        missingInfo = true
        return 0
    end
    return price
end

-- Funktion aus ezBags Schnittstelle, solange ezBag läuft (nil, wenn es sie nicht anbietet).
local function BagFn(name)
    if not ns.IsLoaded("ezBag") then return nil end
    local api = ezCore.API("ezBag")
    local fn = api and api[name]
    return type(fn) == "function" and fn or nil
end

-- Plunder auf dem Platz? Mit ezBags IsJunk dessen Urteil (Schlösser, Markierungen), sonst grau mit denselben Grenzen wie
-- beim Verkauf (Core.Junk.Limits: nichts von der Einkaufsliste, nichts, was laut ezGear besser ist).
local function IsJunk(bag, slot, info)
    local isJunk = BagFn("IsJunk")
    if isJunk then
        local ok, junk = pcall(isJunk, bag, slot)
        return ok and junk and true or false
    end
    if info.quality ~= 0 then return false end
    SellPrice(info.itemID)      -- noch unbekannt: merkt sich, dass nach dem Laden neu zu zählen ist
    return (ezCore.Junk.Limits(info, false))
end

local ScheduleScan

local function Scan()
    if not block.cfg then return end        -- frühe Events vor dem Login
    if ns.InCombat() then
        state.pending = true
        ns.AfterCombat(function() ScheduleScan() end, "repairScan")
        return
    end
    state.pending = false
    missingInfo = false
    wipe(state.items)
    local bagCost, grey = 0, 0

    -- angelegte Ausrüstung: Summen aus ezCore, die beschädigten Plätze für den Tooltip
    local equipped = Durability.Equipped()
    local summary = Durability.Summary()
    for _, e in ipairs(equipped) do
        if e.cur < e.max then
            local link = GetInventoryItemLink("player", e.slot)
            table.insert(state.items, { name = ItemName(link, GetInventoryItemID("player", e.slot)), link = link,
                cur = e.cur, max = e.max, cost = Durability.SlotCost(e.slot) })
        end
    end

    -- alles, was der Charakter bei sich trägt (eine Taschenliste für alle Module: Core.BagList("carried"))
    ezCore.ForEachBagItem(function(bag, slot, info)
        if not info.hasNoValue and IsJunk(bag, slot, info) then
            grey = grey + SellPrice(info.itemID) * (info.stackCount or 1)
        end
        if block.cfg.inventory then
            local c, m = Durability.BagItem(bag, slot)
            if c and c < m then
                local cost = Durability.BagItemCost(bag, slot)
                bagCost = bagCost + cost
                table.insert(state.items, { name = ItemName(info.hyperlink, info.itemID), link = info.hyperlink,
                    cur = c, max = m, cost = cost, bag = true })
            end
        end
    end, "carried")
    table.sort(state.items, function(a, b) return a.cur / a.max < b.cur / b.max end)
    local any = #equipped > 0
    state.pct, state.lowest = any and summary.pct or nil, any and summary.low or nil
    state.equipCost, state.bagCost, state.grey = summary.cost, bagCost, grey
    ns.QueueUpdate(block)
end

local scanTimer
function ScheduleScan(delay)
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(delay or 0.5, function()
        scanTimer = nil
        Scan()
    end)
end

ns.OnReady(function() ScheduleScan(3) end)
ns.On("UPDATE_INVENTORY_DURABILITY", function() ScheduleScan() end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ScheduleScan() end)
ns.On("BAG_UPDATE_DELAYED", function() ScheduleScan(1) end)
-- Im Kampf verschobene Prüfung: ns.AfterCombat in Scan() statt eines eigenen Zuhörers.
ns.On("GET_ITEM_INFO_RECEIVED", function() if missingInfo then ScheduleScan(1) end end)
-- ezGear hat fertig geladen oder rechnet anders (Stufe, Gewichtung): was verschont wird, kann sich ändern
ezCore.Listen("GEAR_SCORES_CHANGED", function() ScheduleScan(1) end, "ezPanel.repair")

---------------------------------------------------------------------------
-- Händler: automatisch reparieren
---------------------------------------------------------------------------

-- Repariert schon ein anderes Addon automatisch (Leatrix Plus)? Dann dessen Name; Erkennung in ezCore.
local function LeatrixRepairs()
    return (ns.OtherFor("repair"))
end

-- ezMerchant übernimmt das automatische Reparieren, sobald es geladen ist.
local function MerchantRepairs()
    return ns.IsLoaded("ezMerchant")
end

-- Funktion aus ezMerchants Schnittstelle (nil, wenn ezMerchant sie nicht anbietet).
local function MerchantFn(name)
    local api = MerchantRepairs() and ezCore.API("ezMerchant")
    local fn = api and api[name]
    return type(fn) == "function" and fn or nil
end

-- Stand der Auto-Reparatur in ezMerchant: { enabled, guild, leatrix, other }, falls ezMerchant ihn anbietet.
-- Der Vertrag: AutoRepair() → aktiv, Gildenbank, repariert ein anderes Addon?, Name dieses Addons (vier Werte).
-- Ältere Formen bleiben verstanden: eine Tabelle { enabled, guild, leatrix }; fehlt der dritte Wert, fragt
-- ezPanel Leatrix().
local function MerchantRepairInfo()
    local autoRepair = MerchantFn("AutoRepair")
    if not autoRepair then return nil end
    local ok, enabled, useGuild, viaLeatrix, other = pcall(autoRepair)
    if not ok then return nil end
    if type(enabled) == "table" then
        local t = enabled
        return { enabled = t.enabled == true, guild = t.guild == true, leatrix = t.leatrix == true }
    end
    local info = { enabled = enabled == true, guild = useGuild == true }
    if type(viaLeatrix) == "boolean" then
        info.leatrix = viaLeatrix
        other = ezCore.Plain(other)
        if viaLeatrix and type(other) == "string" and other ~= "" then info.other = other end
        return info
    end
    local leatrix = MerchantFn("Leatrix")
    if leatrix then
        local okL, on = pcall(leatrix)
        info.leatrix = okL and on == true
    end
    return info
end

local function OpenMerchantSettings()
    local open = MerchantFn("OpenSettings")
    if open and pcall(open) then return end
    if not ezCore.OpenModuleSettings("ezMerchant") then ns.Print(L.REPAIR_MERCHANT_NO_SETTINGS) end
end

local function MerchantCost()
    if not (merchantOpen and CanMerchantRepair and CanMerchantRepair()) then return nil end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not ns.Num(cost) or cost <= 0 then return nil end
    return cost
end

-- Reparieren ohne ezMerchant: die eine Ausführung in ezCore (Core.Durability.RepairAll, W-11, PANEL-04) – mit der
-- Gilde nur, wenn Tageslimit UND Guthaben der Gildenbank reichen; nach einer Nachprüfung zahlt der Spieler den Rest
-- selbst. ezPanel behält Einstellung und Meldung: die Meldung kommt erst mit dem endgültigen Ergebnis (onDone).
-- → true, wenn repariert wird (bei der Gilde: die Nachprüfung läuft noch).
-- Geht der Händler vor der Nachprüfung zu, ruft ezCore onDone nicht mehr; die Gilde hat dann aber schon repariert.
-- Diese Meldung merkt sich pendingGuild und gibt sie bei MERCHANT_CLOSED aus.
local pendingGuild   -- { cost, quiet } einer Gildenreparatur, deren Nachprüfung noch läuft

local function ReportPendingGuild()
    local p = pendingGuild
    pendingGuild = nil
    local text = p and ezCore.Durability.ReportText(true, "guild", p.cost, nil, not p.quiet or RepairReport(),
        ns.Money)
    if text then ns.Print(text) end
end

local function RepairNow(useGuild, quiet)
    if not MerchantCost() then return false end
    -- Text und Regel der Meldung aus ezCore (Core.Durability.ReportText, Gesamtreview 18.11.2026, T16-12 – dieselbe
    -- Meldung wie ezMerchant): Erfolg nach „Kosten im Chat melden“ (von Hand immer), zu wenig Gold immer. Den
    -- Betrag formatiert ns.Money nach ezPanels Einstellung „Geldformat“ (Gegenprüfung P19c).
    local function Report(ok, payer, cost, reason)
        pendingGuild = nil
        local text = ezCore.Durability.ReportText(ok, payer, cost, reason, not quiet or RepairReport(), ns.Money)
        if text then ns.Print(text) end
        if ok then ScheduleScan(1) end
    end
    local ok, payer, cost, state = ezCore.Durability.RepairAll(useGuild == true, Report)
    if ok == true and payer == "guild" and state == "pending" then pendingGuild = { cost = cost, quiet = quiet } end
    return ok == true
end

-- Klick „Jetzt reparieren“ beim Händler: mit ezMerchant über dessen RepairNow (seine Einstellung
-- zur Gildenbank), sonst wie bisher selbst.
local function RepairByHand()
    local merchantRepair = MerchantFn("RepairNow")
    if merchantRepair then
        local ok, done = pcall(merchantRepair)
        if not ok then geterrorhandler()(done) end
        ScheduleScan(1)
        return ok and done == true
    end
    return RepairNow(RepairGuild(), false)
end

-- Automatisch reparieren (ohne ezMerchant, ohne Leatrix Plus): nie im Kampf (Gegenprüfung P17 zu T1-6, wie ezMerchant
-- R.Now; docs/blizzard-regeln.md Tabellen 5 und 7) – im Kampf wartet es bis danach (ns.AfterCombat) und läuft nur, wenn
-- der Händler dann noch offen ist und die Bedingungen noch gelten (Schalter an, kein anderes Addon repariert).
-- → true, wenn repariert wird.
local function AutoRepair()
    if not (merchantOpen and RepairOn()) or LeatrixRepairs() or MerchantRepairs() then
        return false
    end
    if ns.InCombat() then
        ns.AfterCombat(AutoRepair, "autoRepair")
        return false
    end
    return RepairNow(RepairGuild(), true)
end

ns.On("MERCHANT_SHOW", function()
    merchantOpen = true
    ns.QueueUpdate(block)
    if RepairOn() and not LeatrixRepairs() and not MerchantRepairs() then
        C_Timer.After(0.2, AutoRepair)
    end
end)
ns.On("MERCHANT_CLOSED", function()
    merchantOpen = false
    ReportPendingGuild()
    ScheduleScan(0.5)
end)

-- Hinweis am Händler (ezCores Hinweis-Helfer, einmal je Account; Antwort des Nutzers vom 17.11.2026: was ohne Klick
-- Gold kostet, ist ab Werk aus und bekommt einen Hinweis mit Knopf „Einschalten“). autoRepair war schon aus. Nur wenn
-- ezPanel selbst repariert: ohne ezMerchant (sonst gilt dessen Hinweis), ohne anderes Addon, das repariert, mit
-- sichtbarem Baustein und bei einem Händler, der repariert. Der Schalter steht im Menü des Bausteins und seit der
-- Einstellungs-Prüfung vom 19.11.2026 als gemeinsamer Schalter auf der Seite „ezCollection“ (OPTIN_WHERE_autoRepair).
function ns.RegisterRepairOptInHint()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezPanel.autoRepair", {
        owner = "ezPanel",
        window = "merchant",
        label = function() return L.REPAIR_AUTO_ENABLE end,
        what = function() return L.OPTIN_autoRepair end,
        -- dazu der Weg zum gemeinsamen Schalter auf der Seite „ezCollection“ (Core.SettingsPathText)
        where = function() return L.OPTIN_WHERE_autoRepair .. " " .. ezCore.Junk.RepairPathText() end,
        isOn = function() return RepairOn() end,
        enable = function() return SetRepair("repairAuto", true) end,
        -- Ausschalten (Einführung, Einverständnis-Liste; Gesamtreview 18.11.2026, Rest aus dem Paket Einführung)
        disable = function() return SetRepair("repairAuto", false) end,
        applies = function()
            return block.cfg ~= nil and block.cfg.enabled ~= false and not MerchantRepairs() and not LeatrixRepairs()
                and CanMerchantRepair ~= nil and CanMerchantRepair() == true
        end,
        -- Die Übernahme aus den Profilen hat sie ausgeschaltet, weil diese abwichen (Core.Junk.AdoptPanelRepair)
        switchedOff = function() return ezCore.Junk.RepairMixedOff() == true end,
    })
end
ns.RegisterRepairOptInHint()

-- Graue Gegenstände verkaufen (nur auf Knopfdruck, nur beim Händler). Läuft ezBag, verkauft ezBag
-- (SellJunk achtet auf Schlösser und Markierungen); ohne dessen Schnittstelle verkauft ezPanel dann nichts.
local function SellGrey()
    if not merchantOpen then return ns.Print(L.REPAIR_NEED_MERCHANT) end
    if ns.IsLoaded("ezBag") then
        local sell = BagFn("SellJunk")
        if not sell then return ns.Print(L.REPAIR_JUNK_EZBAG) end
        local ok, err = pcall(sell)
        if not ok then geterrorhandler()(err) end
        ScheduleScan(1)
        return
    end
    -- Ohne ezBag verkauft ezCores Dienst (Core.Junk.Sell, seit ezCore 1.12; ezPanel verlangt 1.13): Graues mit
    -- Händlerwert aus den Taschen von Core.BagList("sell"), in gedrosselten Runden, nie im Kampf – im Kampf sagt ezCore
    -- das im Chat (byHand), hört ein Verkauf wegen des Kampfes auf, ebenso. Vorher stand hier eine eigene Schleife mit
    -- UseContainerItem ohne Kampfprüfung und ohne Drosselung (Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 11;
    -- Fund des code-reviewers, Welle 28). ezPanels Meldung bleibt: Anzahl und Erlös (REPAIR_SOLD_ONE/_MANY). ezCore zählt
    -- verkaufte Plätze (ein Stapel aus drei Pelzen ist einer), darum nennt der Satz Taschenplätze, nicht Gegenstände.
    -- „Im Auktionshaus Wertvolles behalten“ (ezMerchants Schalter): fragt ezCore (Core.Junk.MerchantKeeps) wie ezBag;
    -- was liegen bleibt, nennt ezMerchant (Core.Junk.ShowKept) – nie still weniger verkaufen.
    local J = ezCore.Junk
    if not (J and J.Sell) then return end
    local opts = { owner = "ezPanel", quiet = true, byHand = true, onDone = function(sold, gained, _, kept)
        sold, gained = tonumber(sold) or 0, tonumber(gained) or 0
        if sold > 0 then ns.Print(ezCore.Plural(sold, L.REPAIR_SOLD_ONE, L.REPAIR_SOLD_MANY, ns.Money(gained))) end
        if J.ShowKept then J.ShowKept(kept, "ezPanel") end
        ScheduleScan(1)
    end }
    if J.MerchantKeeps and J.MerchantKeeps() then opts.skipAuctionWorth = true end
    J.Sell(opts)
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    local cfg = self.cfg
    local pct = cfg.mode == "lowest" and state.lowest or state.pct
    if not pct then return ns.Grey("–") end
    local text = ns.Gradient(pct) .. ezCore.Percent(math.floor(pct * 100 + 0.5)) .. "|r"
    local cost = MerchantCost() or (state.equipCost + (cfg.inventory and state.bagCost or 0))
    if cfg.cost and cost > 0 then text = text .. " (" .. ns.Money(cost) .. ")" end
    return text
end

-- Für den Baustein „Meldungen“: ein Gegenstand unter 20 % Haltbarkeit.
local LOW_DURABILITY = 0.2
function block:Warnings()
    if state.lowest and state.lowest < LOW_DURABILITY then
        return { L.ALERT_DURABILITY:format(math.floor(state.lowest * 100 + 0.5)) }
    end
    return nil
end

function block:OnTooltip(tooltip)
    local cfg = self.cfg
    if state.pct then
        tooltip:AddDoubleLine(L.REPAIR_DURABILITY, ns.Gradient(state.pct) ..
            ezCore.Percent(math.floor(state.pct * 100 + 0.5)) .. "|r")
    end
    if state.lowest then
        tooltip:AddDoubleLine(L.REPAIR_LOWEST, ns.Gradient(state.lowest) .. ezCore.Percent(math.floor(state.lowest * 100 + 0.5)) .. "|r")
    end
    if #state.items > 0 then
        tooltip:AddLine(" ")
        for _, item in ipairs(state.items) do
            local pct = item.cur / item.max
            local left = ns.Gradient(pct) .. ezCore.Percent(math.floor(pct * 100 + 0.5)) .. "|r  " .. (item.link or item.name)
            if item.bag then left = left .. " " .. ns.Grey(L.REPAIR_IN_BAG) end
            ns.TipDoubleLine(tooltip, left, item.cost > 0 and ns.Money(item.cost) or "", "highlight", "highlight")
        end
    else
        ns.TipLine(tooltip, L.REPAIR_ALL_FINE, "good")
    end

    tooltip:AddLine(" ")
    ns.TipDoubleLine(tooltip, L.REPAIR_COST_EQUIP, ns.Money(state.equipCost), "normal", "highlight")
    if cfg.inventory then
        ns.TipDoubleLine(tooltip, L.REPAIR_COST_BAGS, ns.Money(state.bagCost), "normal", "highlight")
    end
    local merchant = MerchantCost()
    if merchant then
        ns.TipDoubleLine(tooltip, L.REPAIR_COST_MERCHANT, ns.Money(merchant), "normal", "highlight")
    else
        ns.TipLine(tooltip, L.REPAIR_DISCOUNT_NOTE, "hint", true)
    end
    if state.grey > 0 then
        ns.TipDoubleLine(tooltip, BagFn("IsJunk") and L.REPAIR_JUNK or L.REPAIR_GREY, ns.Money(state.grey), "normal", "highlight")
    end
    if IsInGuild() and RepairGuild() and CanGuildBankRepair and CanGuildBankRepair() then
        local limit = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
        if limit then
            ns.TipDoubleLine(tooltip, L.REPAIR_GUILD_LIMIT, limit == -1 and L.UNLIMITED or ns.Money(limit), "normal", "highlight")
        end
    end
    if ns.TipAlts() then
        local first = true
        for _, entry in ipairs(ns.Characters(function(_, key) return key ~= ns.charKey end)) do
            local d = Durability.Of(entry.key)
            local pct = type(d) == "table" and ns.Num(d.pct)
            if pct then
                if first then
                    tooltip:AddLine(" ")
                    ns.TipLine(tooltip, L.OTHER_CHARS, "normal")
                    first = false
                end
                local text = ns.Gradient(pct) .. ezCore.Percent(math.floor(pct * 100 + 0.5)) .. "|r"
                if (ns.Num(d.broken) or 0) > 0 then text = text .. " " .. ns.RED .. L.REPAIR_BROKEN:format(d.broken) .. "|r" end
                ns.TipDoubleLine(tooltip, ns.CharName(entry.c, entry.key), text .. ns.AltStand(entry.c, d.t), "highlight", "highlight")
            end
        end
    end
    if MerchantRepairs() then
        local info = MerchantRepairInfo()
        local text = L.REPAIR_AUTO_MERCHANT
        if info and info.leatrix then
            -- Der Name kommt aus ezMerchants viertem Wert; ohne ihn (ältere Form) der bisherige Text.
            text = info.other and L.REPAIR_AUTO_OTHER:format(info.other) or L.REPAIR_AUTO_LEATRIX
        elseif info then
            text = (info.enabled and L.REPAIR_AUTO_MERCHANT_ON or L.REPAIR_AUTO_MERCHANT_OFF)
            if info.enabled and info.guild then text = text .. " " .. L.REPAIR_AUTO_MERCHANT_GUILD end
        end
        ns.TipLine(tooltip, text, "hint", true)
    elseif RepairOn() then
        local other = LeatrixRepairs()
        ns.TipLine(tooltip, other and L.REPAIR_AUTO_OTHER:format(other) or L.REPAIR_AUTO_ON, "hint", true)
    end
end

local function OpenCharacter()
    return ezCore.TogglePanel("character", "PaperDollFrame")   -- im Kampf: Hinweis von ezCore
end

-- „Jetzt reparieren“ und „Plunder verkaufen“ stehen beim Händler weiter unten im Menü (OnMenu).
block.actions = {
    { text = L.REPAIR_RESCAN, fn = function() Scan() end },
    { text = L.REPAIR_OPEN_CHARACTER, fn = OpenCharacter },
}

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    if IsShiftKeyDown() then
        Scan()
        return
    end
    if MerchantCost() then
        RepairByHand()
    else
        OpenCharacter()
    end
end

-- Für ezMerchant: die bisherigen Einstellungen zur einmaligen Übernahme (nur lesen). Angeboten als
-- ezCore.API("ezPanel").RepairSettings – die Schnittstelle setzt API.lua zusammen (eine Stelle, W-30).
-- ezPanels Profile gelten je Charakter, ezMerchants Einstellungen für das ganze Konto (Gesamtreview 18.11.2026, T4-6):
-- „automatisch reparieren“ und „Gildenbank“ kommen je Schalter nur mit, wenn alle gespeicherten Profile dasselbe sagen.
-- Weicht ein Schalter ab, liefert die Abfrage ihn aus (mixed = true) – einschalten muss man selbst (Grundsatz des
-- Nutzers vom 17.11.2026). autoAnywhere sagt, ob irgendein Profil automatisch repariert hat: dann meldet ezMerchant
-- bei der Übernahme, dass es aus ist, und sein Hinweis am Händler nennt den Grund (Gegenprüfung P19b).
local MIGRATE_KEYS = { "autoRepair", "guild" }

local function ProfileRepair(profile)
    local blocks = type(profile) == "table" and profile.blocks
    local cfg = type(blocks) == "table" and blocks.repair
    return type(cfg) == "table" and cfg or {}
end

function ns.RepairSettings()
    local cfg = block.cfg or (ns.db and ns.db.blocks and ns.db.blocks.repair) or block.defaults
    local result = { autoRepair = cfg.autoRepair == true, guild = cfg.guild == true, report = cfg.report ~= false }
    result.autoAnywhere = result.autoRepair
    local differs = {}
    local profiles = ns.db and ns.db.profiles
    local P = ns.Profiles and ns.Profiles.P
    local active = P and type(P.Active) == "function" and P.Active() or nil
    if type(profiles) == "table" then
        for name, profile in pairs(profiles) do
            if name ~= active then
                local other = ProfileRepair(profile)
                for _, key in ipairs(MIGRATE_KEYS) do
                    local value = other[key]
                    if value == nil then value = block.defaults[key] end
                    if (value == true) ~= result[key] then
                        result.mixed = true
                        differs[key] = true
                    end
                end
                if other.autoRepair == true then result.autoAnywhere = true end
            end
        end
    end
    for key in pairs(differs) do result[key] = false end
    return result
end

-- Einmalige Übernahme in ezCores gemeinsamen Schaltersatz, wenn ezPanel selbst repariert (ohne ezMerchant; mit
-- ezMerchant übernimmt dessen R.MigrateFromPanel dieselben Werte). Ein „an“ schaltet ein, ein „aus“ nichts aus;
-- abweichende Profile lassen es aus und ezCore sagt es einmal im Chat. → true beim ersten Lauf
function ns.AdoptRepairSettings()
    if MerchantRepairs() then return false end
    return ezCore.Junk.AdoptPanelRepair(ns.RepairSettings()) == true
end
ns.OnReady(function() C_Timer.After(1, function() ns.Try("AdoptRepairSettings", ns.AdoptRepairSettings) end) end)

-- Häkchen im Menü für einen Wert des gemeinsamen Schaltersatzes (statt ns.MenuCheck auf die Profiltabelle).
local function SharedCheck(root, text, key, get)
    return root:CreateCheckbox(text, get, function()
        SetRepair(key, not get())
        return MenuResponse and MenuResponse.Refresh
    end)
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(bar, L.REPAIR_MODE_TOTAL, cfg, "mode", "total", self)
    ns.MenuRadio(bar, L.REPAIR_MODE_LOWEST, cfg, "mode", "lowest", self)
    bar:CreateDivider()
    ns.MenuCheck(bar, L.REPAIR_SHOW_COST, cfg, "cost", self)
    ns.MenuCheck(root, L.REPAIR_INVENTORY, cfg, "inventory", self, function() ScheduleScan(0.1) end)
    ns.MenuTipAlts(root, self)

    local auto = root:CreateButton(L.REPAIR_AUTO)
    -- ein Schaltersatz für ezMerchant und ezPanel (ezCore, Gruppe vendor): mit ezMerchant repariert dieses, die Häkchen
    -- hier schalten trotzdem denselben Wert
    if MerchantRepairs() then
        auto:CreateTitle(L.REPAIR_AUTO_MERCHANT)
        auto:CreateButton(L.REPAIR_MERCHANT_SETTINGS, OpenMerchantSettings)
        auto:CreateDivider()
    end
    SharedCheck(auto, L.REPAIR_AUTO_ENABLE, "repairAuto", RepairOn)
    SharedCheck(auto, L.REPAIR_USE_GUILD, "repairGuild", RepairGuild)
    SharedCheck(auto, L.REPAIR_REPORT, "repairReport", RepairReport)

    if merchantOpen then
        root:CreateDivider()
        if MerchantCost() then
            root:CreateButton(L.REPAIR_NOW, RepairByHand)
        end
        if state.grey > 0 then
            if not ns.IsLoaded("ezBag") then
                root:CreateButton(L.REPAIR_SELL_GREY, SellGrey)
            elseif BagFn("SellJunk") then
                root:CreateButton(L.REPAIR_SELL_JUNK, SellGrey)
            else
                root:CreateTitle(L.REPAIR_JUNK_EZBAG)
            end
        end
    end
end
