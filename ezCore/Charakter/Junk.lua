local _, ns = ...
local Core = ezCore

--[[
    Plunder verkaufen als ein Dienst (W-23, VP-30, Frage 14 – Empfehlung umgesetzt, Antwort offen). Vorher lief die
    Ausführung nur in ezBag (ezBag/Junk.lua); ezMerchant zeigte am Händlerfenster nur mit ezBag „Plunder verkaufen
    (ezBag)“. Jetzt: EINE Ausführung hier – nur bei offenem Händler, in gedrosselten Runden, Abbruch beim Schließen,
    eine Meldung mit der Summe. Ein Modul liefert nur die Regel, was als Plunder gilt (ezBag: Gruppen, Schlösser,
    Markierungen); ohne Regel gilt Graues mit Händlerwert. ezMerchant zeigt Knopf und Schalter – auch ohne ezBag.
    Umkehrbar: ezBags SellJunk bleibt, wie es ist, bis ezBag in seinem Paket hierher weiterleitet.

      Junk.SetRule(owner, fn)        → meldet die Regel eines Moduls an (eine je Modul; die zuletzt angemeldete gilt)
                                       fn(info, bag, slot) → verkaufen, markiert, geschützt  (info = ContainerItemInfo)
                                       fn = nil meldet ab
      Junk.Rule()                    → owner, fn der geltenden Regel (nil, nil = Graues); ohne angemeldete Regel nimmt
                                       ezCore ezBags Schnittstelle IsJunk(bag, slot), wenn ezBag läuft
      Junk.Check(bag, slot, info)    → verkaufen, markiert, geschützt – Seltenes und Besseres wird nie verkauft
      Junk.Collect(opts)             → Liste { { bag, slot, itemID, price, count } }, Zahl geschützter, behaltene
                                       (nur mit opts.skipAuctionWorth: { { bag, slot, itemID, count } } – Gegenstände,
                                       die im Auktionshaus mehr bringen, Core.Prices.WorthMark)
      Junk.Value(opts)               → Summe in Kupfer, Anzahl Plätze (was Sell jetzt verkaufen würde)
      Junk.Sell(opts)                → true, behaltene (Liste wie bei Collect), wenn der Verkauf beginnt (Händler
                                       offen, nicht schon dabei)
          opts = { onlyMarked = bool, quiet = bool, owner = "ezMerchant", onDone = fn(verkauft, kupfer, geschützt,
                   behaltene, abbruch), skipAuctionWorth = bool, byHand = bool }   (abbruch: nil oder "combat")
          skipAuctionWorth (AH-13, Welle 13; ab Werk AUS): nur wenn der Aufrufer es setzt, lässt der Dienst
          Gegenstände mit der Marke „im Auktionshaus mehr wert“ aus und nennt sie als Liste. In Welle 13 setzt es
          niemand – bestehende Aufrufer verkaufen unverändert; eingeschaltet wird es von ezMerchant in Welle 14 (AH-27).
          Weitere Felder werden an Collect und die Regel durchgereicht; unbekannte Felder stören nicht.
      Junk.Selling(), Junk.Stop()
      Junk.MerchantKeeps(), Junk.ShowKept(liste, owner)   ezMerchants „Im Auktionshaus Wertvolles behalten“ für alle Verkäufer
      Grenzen (Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 11): nie im Kampf – eine Runde im Kampf beendet den
      Verkauf sofort, Junk.Sell beginnt im Kampf gar nicht erst –, höchstens Junk.MAX_PER_ROUND Plätze je Runde und
      jeder Platz einmal je Verkauf (was nach dem Versuch noch liegt, bleibt liegen). Seltenes und Besseres nie.
      Rückmeldung im Kampf (Fund des code-reviewers, Welle 28): Hört ein Verkauf wegen des Kampfes auf, sagt der Dienst
      es nach der Summe (JUNK_STOPPED_COMBAT) – auch mit quiet, denn das Modul meldet nur Summe und Geschütztes; onDone
      bekommt als fünften Wert "combat". Junk.Sell im Kampf → false, "combat"; mit opts.byHand = true (Klick des
      Spielers: ezBags Menü und ezPanels Knopf) steht dazu ezCores Kampfsatz im Chat (Core.CombatNotice mit
      JUNK_WHAT, T18-1); ezMerchants Knopf fragt den Kampf vorher selbst und sagt denselben Satz.
      Nachricht: JUNK_SOLD (verkauft, kupfer, geschützt, owner)

    Einkaufsliste (A43, Welle 23b; vorher nur in ezBag als ns.CraftNeed): Material, das ezCrafts Einkaufsliste braucht,
    verkauft der Dienst nie – auch ohne ezBag (ezMerchant verkauft dann ohne Regel). Check meldet es als „nicht verkaufen“
    (nicht als geschützt, wie ezBags Regel).
      Junk.CraftNeed(gegenstand)     → Bedarf (Zahl > 0) oder nil: Gesamtbedarf aus ezCore.API("ezCraft").Needs(),
                                       gemerkt bis EZCRAFT_SHOPPING_CHANGED, RECIPES_CHANGED oder einem Ereignis des
                                       Berufefensters; Junk.Sell liest vor jedem Verkauf frisch. Läuft ezCraft nicht: nil
      Junk.ClearCraftNeeds()         Zwischenspeicher verwerfen

    Rücksicht (Leitlinie 9): Wer sellJunk übernimmt (Leatrix Plus, Tweaks, Forever++), steht in Core.WhoHandles;
    Eigentümer des Schlüssels ist das erste geladene Modul aus Core.FEATURE_OWNERS.sellJunk (ezBag, sonst
    ezMerchant). Sell verkauft dann nur von Hand Ausgelöstes – automatische Aufrufe setzen onlyMarked selbst.
]]

local Junk = {}
Core.Junk = Junk

Junk.ROUND_INTERVAL = 0.25
-- Sicherung gegen endlose Runden. Jede gezählte Runde nimmt neue Plätze (jeder Platz einmal je Verkauf), eine Runde
-- ohne neue Plätze beendet den Verkauf ohnehin. Seit höchstens MAX_PER_ROUND Plätze je Runde gehen (Risiko 11) muss
-- die Sicherung alle Taschen abdecken: 40 × 10 = 400 Plätze, mehr als Rucksack, vier Taschen und Reagenzientasche
-- fassen (vorher 8 – damit endete ein Verkauf nach 80 Plätzen ohne Meldung; Fund der Gegenprüfung, Welle 28).
Junk.MAX_ROUNDS = 40
Junk.MAX_PER_ROUND = 10   -- Plätze je Runde (Risiko 11 der Prüfung vom 17.11.2026)
Junk.REPORT_DELAY = 0.8

local rules, order = {}, {}
local ticker, run

function Junk.SetRule(owner, fn)
    if type(owner) ~= "string" or owner == "" then return false end
    -- Immer erst austragen, dann (mit Regel) ans Ende: eine Neuanmeldung gilt als die zuletzt angemeldete.
    for i = #order, 1, -1 do
        if order[i] == owner then table.remove(order, i) end
    end
    rules[owner] = type(fn) == "function" and fn or nil
    if rules[owner] then order[#order + 1] = owner end
    return true
end

local function BagRule(info, bag, slot)
    local api = Core.API and Core.API("ezBag")
    local fn = type(api) == "table" and api.IsJunk
    if type(fn) ~= "function" then return nil end
    local ok, sell, marked = pcall(fn, bag, slot)
    if not ok then return nil end
    -- ezBags IsJunk nennt nur verkaufen und markiert; ein markierter seltener Gegenstand bleibt dort liegen, weil er
    -- geschützt ist – das hier nachbilden, damit der Hinweis JUNK_PROTECTED kommt (bis ezBag SetRule nutzt).
    local quality = type(info) == "table" and Core.Num(info.quality) or 0
    return sell and true or false, marked and true or false, (marked and not sell and quality >= 3) and true or false
end

function Junk.Rule()
    local owner = order[#order]
    if owner then return owner, rules[owner] end
    local api = Core.API and Core.API("ezBag")
    if type(api) == "table" and type(api.IsJunk) == "function" then return "ezBag", BagRule end
    return nil, nil
end

local function Grey(info)
    return Core.Num(info.quality) == 0
end

-- Einkaufsliste von ezCraft (A43): nil = noch nicht gelesen, false = ezCraft lieferte nichts Brauchbares
local craftNeeds

function Junk.CraftNeed(item)
    local itemID = Core.ItemID(item)
    if not itemID then return nil end
    if craftNeeds == nil then
        local api = Core.API and Core.API("ezCraft")
        -- ezCraft (noch) nicht da: nichts merken, beim nächsten Mal wieder fragen
        if not (type(api) == "table" and type(api.Needs) == "function") then return nil end
        local ok, map = pcall(api.Needs)
        craftNeeds = ok and type(map) == "table" and map or false
    end
    local n = craftNeeds and Core.Num(craftNeeds[itemID])
    if n and n > 0 then return n end
    return nil
end

function Junk.ClearCraftNeeds() craftNeeds = nil end

Core.Listen("EZCRAFT_SHOPPING_CHANGED", Junk.ClearCraftNeeds, Core.name)
Core.Listen("RECIPES_CHANGED", Junk.ClearCraftNeeds, Core.name)
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE" }) do
    ns.On(event, Junk.ClearCraftNeeds)
end

function Junk.Check(bag, slot, info, opts)
    if type(info) ~= "table" and C_Container and C_Container.GetContainerItemInfo then
        info = Core.Call(C_Container.GetContainerItemInfo, bag, slot)
    end
    if type(info) ~= "table" or Core.IsSecret(info.itemID) or info.itemID == nil or info.hasNoValue then
        return false, false, false
    end
    local sell, marked, protected
    local owner, rule = Junk.Rule()
    if rule then
        local ok, a, b, c = pcall(rule, info, bag, slot, opts)
        if ok then
            sell, marked, protected = a and true or false, b and true or false, c and true or false
        else
            Core.Error(owner or Core.name, a, "Junk rule")
            sell, marked, protected = Grey(info), false, false
        end
    else
        sell, marked, protected = Grey(info), false, false
    end
    local quality = Core.Num(info.quality) or 0
    if sell and quality >= 3 then return false, marked, true end   -- Seltenes und Besseres nie
    if not sell then return false, marked, protected end
    if Junk.CraftNeed(info.itemID) then return false, marked, false end   -- A43: Material der Einkaufsliste
    local price = Core.VendorPrice(info.hyperlink or info.itemID)
    return (price or 0) > 0, marked, false
end

-- AH-13: lohnt der Gegenstand im Auktionshaus mehr? (nur mit opts.skipAuctionWorth gefragt)
local function AuctionWorth(info, bag, slot)
    local P = Core.Prices
    if not (P and P.WorthMark) then return false end
    local ok, yes = pcall(P.WorthMark, info.itemID, info.hyperlink, bag, slot)
    return ok and yes == true
end

function Junk.Collect(opts)
    opts = type(opts) == "table" and opts or {}
    local list, protected, kept = {}, 0, opts.skipAuctionWorth == true and {} or nil
    Core.ForEachBagItem(function(bag, slot, info)
        if info.isLocked then return end
        local sell, marked, isProtected = Junk.Check(bag, slot, info, opts)
        if opts.onlyMarked and not marked then return end
        if isProtected then
            protected = protected + 1
        elseif sell then
            local count = Core.Num(info.stackCount) or 1
            if kept and AuctionWorth(info, bag, slot) then
                kept[#kept + 1] = { bag = bag, slot = slot, itemID = info.itemID, count = count }
            else
                list[#list + 1] = { bag = bag, slot = slot, itemID = info.itemID,
                    price = Core.VendorPrice(info.hyperlink or info.itemID) or 0, count = count }
            end
        end
    end, "sell")
    return list, protected, kept
end

function Junk.Value(opts)
    local list = Junk.Collect(opts)
    local sum = 0
    for _, e in ipairs(list) do sum = sum + e.price * e.count end
    return sum, #list
end

local function AtMerchant()
    local D = Core.Durability
    if D and D.MerchantOpen and D.MerchantOpen() then return true end
    local frame = rawget(_G, "MerchantFrame")
    return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() == true or false
end
Junk.AtMerchant = AtMerchant

-- „Im Auktionshaus Wertvolles behalten“ (ezMerchants Schalter keepAuctionWorth) gilt für jeden, der über diesen Dienst
-- verkauft (ezBags Automatik und SellJunk, ezPanels „Graue verkaufen“). Eine Stelle für die Frage und die Antwort:
--   Junk.MerchantKeeps()   → ezMerchants Schnittstelle, solange dort KeepAuctionWorth() true sagt; sonst nil (ohne
--                            ezMerchant, Schalter aus oder Fehler in der Auskunft – dann wird wie bisher verkauft)
--   Junk.ShowKept(liste, owner) → true, wenn ezMerchant die behaltenen Gegenstände nennt (Chatzeile, Zeile unter dem
--                            Händlerfenster mit „Trotzdem verkaufen“); nur bei offenem Händler. Nie still weniger verkaufen.
--                            owner: das Modul, unter dem ein Fehler in ezMerchants Auskunft protokolliert wird.
-- Der Aufrufer setzt dann opts.skipAuctionWorth und reicht die behaltenen aus Junk.Sell an Junk.ShowKept.
function Junk.MerchantKeeps()
    local api = Core.API("ezMerchant")
    if type(api) ~= "table" or type(api.KeepAuctionWorth) ~= "function" then return nil end
    local ok, keep = pcall(api.KeepAuctionWorth)
    if ok and keep == true then return api end
    return nil
end

function Junk.ShowKept(list, owner)
    if type(list) ~= "table" or #list == 0 or not AtMerchant() then return false end
    local api = Core.API("ezMerchant")
    if type(api) ~= "table" or type(api.ShowKept) ~= "function" then return false end
    local ok, err = pcall(api.ShowKept, list)
    if not ok then Core.Error(owner or Core.name or "ezCore", err, "ShowKept") end
    return ok
end

function Junk.Selling() return ticker ~= nil end

function Junk.Stop()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function Money() return Core.Num((Core.Call(rawget(_G, "GetMoney")))) or 0 end

local function Report(r)
    local sold = 0
    for _, e in pairs(r.attempted) do
        local info = C_Container and Core.Call(C_Container.GetContainerItemInfo, e.bag, e.slot)
        if type(info) ~= "table" or info.itemID ~= e.itemID then sold = sold + 1 end
    end
    local gained = math.max(0, Money() - r.startMoney)
    local L = Core.L
    if not r.opts.quiet then
        if sold > 0 and gained > 0 then
            Core.Print(r.opts.owner or Core.name, L.JUNK_SOLD:format(Core.Plural(sold, L.COUNT_ITEM_ONE, L.COUNT_ITEM_MANY),
                Core.CoinText(gained)))
        end
        if r.protected > 0 then
            Core.Print(r.opts.owner or Core.name, Core.Plural(r.protected, L.JUNK_PROTECTED_ONE, L.JUNK_PROTECTED_MANY))
        end
    end
    if type(r.opts.onDone) == "function" then
        local ok, err = pcall(r.opts.onDone, sold, gained, r.protected, r.kept, r.stopped)
        if not ok then Core.Error(r.opts.owner or Core.name, err, "Junk.Sell onDone") end
    end
    -- nach der Summe des Moduls (onDone): auch mit quiet, sonst bliebe der Abbruch stumm
    if r.stopped == "combat" then Core.Print(r.opts.owner or Core.name, L.JUNK_STOPPED_COMBAT) end
    Core.Fire("JUNK_SOLD", sold, gained, r.protected, r.opts.owner)
end

local function Finish(r)
    Junk.Stop()
    if r.finished then return end
    r.finished = true
    C_Timer.After(Junk.REPORT_DELAY, function() Report(r) end)
end

local function Round()
    local r = run
    if not r then return Junk.Stop() end
    if not AtMerchant() then return Finish(r) end
    if Core.InCombat() then                -- im Kampf sofort aufhören (Risiko 11) und es danach sagen
        r.stopped = "combat"
        return Finish(r)
    end
    if Core.Call(rawget(_G, "CursorHasItem")) or Core.Call(rawget(_G, "InRepairMode")) then return end
    local list, protected, kept = Junk.Collect(r.opts)
    r.protected = protected
    if kept and not r.kept then r.kept = kept end
    local used = 0
    for _, e in ipairs(list) do
        local key = e.bag .. ":" .. e.slot .. ":" .. e.itemID
        if not r.attempted[key] then
            if used >= Junk.MAX_PER_ROUND then break end
            used = used + 1
            r.attempted[key] = e
            C_Container.UseContainerItem(e.bag, e.slot)
        end
    end
    if used == 0 then return Finish(r) end
    r.rounds = r.rounds + 1
    if r.rounds >= Junk.MAX_ROUNDS then Finish(r) end
end

function Junk.Sell(opts)
    opts = type(opts) == "table" and opts or {}
    if ticker or not AtMerchant() or not (C_Container and C_Container.UseContainerItem) then return false end
    if Core.InCombat() then
        if opts.byHand then Core.CombatNotice(opts.owner or Core.name, Core.L.JUNK_WHAT) end
        return false, "combat"
    end
    Junk.ClearCraftNeeds()   -- die Einkaufsliste frisch lesen (A43)
    run = { opts = opts, rounds = 0, startMoney = Money(), attempted = {}, protected = 0 }
    local r = run
    ticker = C_Timer.NewTicker(Junk.ROUND_INTERVAL, Round)
    Round()
    return true, r.kept
end

-- Händler zu: Runden abbrechen, das Ergebnis des Verkauften trotzdem melden
ns.On("MERCHANT_CLOSED", function()
    if ticker and run then Finish(run) end
end)

---------------------------------------------------------------------------
-- Gemeinsame Schalter am Händler (Einstellungs-Prüfung 19.11.2026, Nr. 59/60 und 62; Entscheidung des Nutzers „Ja, alle
-- umsetzen“): EIN Schalter „Plunder beim Händler verkaufen“ für ezBag und ezMerchant und EIN Schaltersatz
-- „Automatisch reparieren“ für ezMerchant und ezPanel – vorher je Modul eigene Werte, von denen je nach geladenen Modulen
-- nur einer wirkte (Seite und Menü zeigten Verschiedenes). Ab Werk aus bleibt (docs/blizzard-regeln.md, Abschnitt 5).
-- Wer ausführt, bleibt wie bisher: Plunder verkauft ezBag, ohne ezBag ezMerchant; repariert wird von ezMerchant, ohne
-- ezMerchant von ezPanel. Die alten Werte übernehmen die Module einmal (Core.AdoptShared beim Laden).
--   ezCoreDB.vendor = { autoSell, repairAuto, repairGuild, repairReport }
--   Junk.AutoSell()                 → true, wenn „Plunder beim Händler verkaufen“ an ist
--   Junk.RepairSettings()           → automatisch?, Gildenbank zuerst?, Kosten im Chat melden?
--   Junk.AdoptPanelRepair(alt)      → true beim ersten Lauf: ezPanels frühere Reparatur-Schalter einmal übernehmen
--   Junk.SkipPanelRepair()          ezPanels Werte nicht mehr übernehmen (ezMerchant hatte sie schon)
--   Junk.RepairMixedOff()           → true, solange die Übernahme es wegen verschiedener Profile ausgeschaltet hat
--   Junk.ReportRepairMixed()        die Chatzeile dazu
--   Junk.RepairPathText()           → Weg zum Schalter „Automatisch reparieren“ (Seite „ezCollection“)
---------------------------------------------------------------------------
Core.OwnDefaults("vendor", { autoSell = false, repairAuto = false, repairGuild = false, repairReport = true })

function Junk.AutoSell()
    return Core.SharedOn("vendor", "autoSell")
end

function Junk.RepairSettings()
    return Core.SharedOn("vendor", "repairAuto"), Core.SharedOn("vendor", "repairGuild"),
        Core.OwnSetting("vendor", "repairReport") ~= false
end

-- Profile von ezPanel standen verschieden (je Charakter), der gemeinsame Schalter gilt fürs ganze Konto: aus und einmal
-- sagen, dass ezCollection es ausgeschaltet hat und wo man es einschaltet (vorher ezMerchants R.ReportMixed; der Weg
-- über Core.SettingsPathText: Seite „ezCollection“, Abschnitt „Gemeinsame Schalter“).
function Junk.RepairPathText()
    return Core.SettingsPathText(nil, "SHARED_HEADER", "OPT_vendorRepairAuto")
end

function Junk.ReportRepairMixed()
    local L = Core.L
    Core.Print(Core.name, L.OPTIN_SWITCHED_OFF .. " " .. L.VENDOR_REPAIR_MIXED .. " " .. Junk.RepairPathText())
end

-- Junk.AdoptPanelRepair(alt) → true beim ersten Lauf: übernimmt ezPanels frühere Reparatur-Schalter einmal in den
-- gemeinsamen Schaltersatz. alt ist ezCore.API("ezPanel").RepairSettings() = { autoRepair, guild, report, mixed,
-- autoAnywhere } (weichen ezPanels Profile ab, sind autoRepair und guild dort schon aus). Ein „an“ schaltet ein, ein
-- „aus“ schaltet nichts aus (Core.AdoptShared, Quelle „ezPanel“); „Kosten im Chat melden“ setzt die erste Quelle.
-- Stand automatisches Reparieren in einem Profil an, in einem anderen aus, bleibt es aus: dann einmal die Chatzeile
-- (Junk.ReportRepairMixed), und Junk.RepairMixedOff() sagt es der Blase am Händler, bis jemand den Schalter umlegt.
-- Junk.SkipPanelRepair(): ezMerchant hatte ezPanels Werte schon früher übernommen – sie sind veraltet und kommen nicht mehr.
local PANEL_FLAG, MIXED_FLAG = "vendor:panelRepair", "vendor:repairMixed"

local function Migrated()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return db.migrated
end

function Junk.AdoptPanelRepair(old)
    local migrated = Migrated()
    if not migrated or type(old) ~= "table" then return false end
    return Core.MigrateOnce(migrated, PANEL_FLAG, function()
        local auto = old.autoRepair
        if auto == nil then auto = old.auto end
        -- ezPanels frühere Standards (aus, aus, an) sind keine Wahl (Core.SharedChoice; Gegenprüfung 19.11.2026)
        local function Choice(value, default)
            if Core.SharedChoice({ old = default }, value) then return value end
            return nil
        end
        Core.AdoptShared("vendor", "repairAuto", "ezPanel", Choice(auto, false))
        Core.AdoptShared("vendor", "repairGuild", "ezPanel", Choice(old.guild, false))
        Core.AdoptShared("vendor", "repairReport", "ezPanel", Choice(old.report, true), "first")
        if old.mixed == true and old.autoAnywhere == true and not Core.SharedOn("vendor", "repairAuto") then
            migrated[MIXED_FLAG] = true
            Junk.ReportRepairMixed()
        end
        return true
    end) == true
end

function Junk.SkipPanelRepair()
    local migrated = Migrated()
    if migrated then migrated[PANEL_FLAG] = true end
end

function Junk.RepairMixedOff()
    local db = Core.db
    return type(db) == "table" and type(db.migrated) == "table" and db.migrated[MIXED_FLAG] == true
end

-- Wer „Automatisch reparieren“ selbst umlegt, hat es nicht mehr „von ezCollection ausgeschaltet“.
Core.Listen(Core.OWN_SETTING_CHANGED, function(group, key)
    if group ~= "vendor" or key ~= "repairAuto" then return end
    local db = Core.db
    if type(db) == "table" and type(db.migrated) == "table" then db.migrated[MIXED_FLAG] = nil end
end)
