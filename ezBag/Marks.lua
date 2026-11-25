local ADDON, ns = ...
local L = ns.L

--[[
    Marken oben links auf den Plätzen – eine Stelle für alle Module, damit sich nichts überlagert
    und niemand dieselben Knöpfe doppelt hookt. Gezeichnet in Tasche, Bank, Gildenbank und im
    ezBag-Fenster (über ns.SetItemMarks, Layout.lua).
    - eigene: Quest (Erkennung von ezQuest, falls geladen), Schloss „nie verkaufen“
      (grauer Gegenstand, den du einer anderen Gruppe zugewiesen hast), Zettel „für ezCrafts Einkaufsliste“
    - fremde: ezCore.API("ezBag").AddSlotMark(key, { order, owner, fn }) – z. B. ezGear „besser“; ezCores Münze
      „im Auktionshaus mehr wert“ (ezCore.auctionWorth) nur mit Schalter bzw. beim Händler mit ezMerchant (AH-26)
    - Auskunft für andere Module: ezCore.API("ezBag").IsLocked(bag, slot) – trägt der Platz das Schloss?
    Die übrigen Ecken sind belegt: Itemlevel oben rechts, BoE unten links, Anzahl unten rechts.
    Im ezBag-Fenster sitzt das Ortssymbol (Fundort) rechts in der Ecke, die Itemlevel und Anzahl frei lassen
    (Window.PlaceIconCorner) – der linke Rand bleibt den Marken und „BoE“.
]]

local Marks = {}
ns.Marks = Marks

local MAX_SHOWN = 2          -- untereinander am linken Rand, darunter steht „BoE“

local providers = {}         -- { key, order, owner, fn }
local drawer = ezCore.SlotMarks.NewDrawer()            -- gezeichnet wird mit ezCores Fassung (eine Optik für beide)

-- Farbenblind-Hilfe (EC-47): Ist ezCores Schalter „Zeichen am Leuchten“ an, steht rechts neben einer Marke mit sign
-- ein Zeichen (ezCore.MarkSign: „+“ grün, „!“ rot …, „-“ für grau = erledigt oder nicht für dich). Eine eigene
-- graue Marke (desaturate ohne Färbung) bekommt von sich aus „muted“ (ezCore.SlotMarks.SignOf).
Marks.SignOf = ezCore.SlotMarks.SignOf

--[[
    fn(itemID, link, bag, slot, quality) → nil oder eine Marke:
      { atlas = "…", useAtlasSize = bool }  oder  { texture = "…" }
      dazu optional r, g, b (Färbung), desaturate (grau), x, y (Versatz der ersten Marke), sign (Farbenblind-Hilfe,
      EC-47: Schlüssel für ezCore.MarkSign – eine Farbe wie "green"/"red" oder "muted" für den grauen Zustand)
    bag/slot sind nil, wenn der Platz nur eine Anzeige ist (ezBag-Fenster offline, Gildenbank).
    Mit useAtlasSize sitzt die Marke wie Blizzards eigener Pfeil am Platz (Ecke 0,0, Atlas-Größe).
    Die Marken stehen untereinander am linken Rand, höchstens zwei.
]]
function Marks.Add(key, opts)
    if type(key) ~= "string" or type(opts) ~= "table" or type(opts.fn) ~= "function" then return false end
    Marks.Remove(key)
    providers[#providers + 1] = { key = key, order = tonumber(opts.order) or 50, owner = opts.owner or key, fn = opts.fn }
    Marks.Refresh()
    ezCore.SlotMarks.Sort(providers)
    return true
end

function Marks.Remove(key)
    for i = #providers, 1, -1 do
        if providers[i].key == key then table.remove(providers, i) end
    end
end

function Marks.Keys()
    local list = {}
    for _, p in ipairs(providers) do list[#list + 1] = p.key end
    return list
end

-- Alle Marken neu zeichnen (z. B. nachdem ezGear neu bewertet hat), gedrosselt über ns.Throttle (ezCore).
Marks.Refresh = ns.Throttle(function()
    if ns.Layout and ns.Layout.RefreshOverlays then ns.Layout.RefreshOverlays() end
    if ns.Bank and ns.Bank.RefreshMarks then ns.Bank.RefreshMarks() end
    if ns.GuildBank and ns.GuildBank.RefreshMarks then ns.GuildBank.RefreshMarks() end
    if ns.Window and ns.Window.Refresh then ns.Window.Refresh(false) end
end, 0.1)

-- Marken, die für diesen Platz gelten, in Reihenfolge (höchstens MAX_SHOWN).
function Marks.For(itemID, link, bag, slot, quality)
    local list = {}
    itemID = ns.PlainID(itemID)
    if not itemID then return list end
    local worth   -- nil = noch nicht gefragt (nur, wenn ezCores Münze angemeldet ist)
    for _, p in ipairs(providers) do
        local ok, mark = true, nil
        local skip = false
        if p.key == Marks.AUCTION_WORTH then
            if worth == nil then worth = Marks.AuctionWorthShown() end
            skip = not worth
        end
        if not p.failed and not skip then ok, mark = pcall(p.fn, itemID, link, bag, slot, quality) end
        if not ok then
            -- Einmal melden und abschalten, sonst käme der Fehler für jeden Platz bei jedem Neuaufbau.
            p.failed = true
            ezCore.Error(p.owner, mark, "ezBag.SlotMark " .. p.key)
        elseif type(mark) == "table" and (mark.atlas or mark.texture) then
            mark.key = p.key
            list[#list + 1] = mark
            if #list >= MAX_SHOWN then break end
        end
    end
    return list
end

function Marks.Apply(button, itemID, link, quality, bag, slot)
    if not button then return end
    drawer.Draw(button, Marks.For(itemID, link, bag, slot, quality))
end

-- Zeichen i am Knopf (nil, wenn keines steht) – für Tests und /dump
Marks.SignShown = drawer.SignShown

-- Schaltet der Spieler „Zeichen am Leuchten“ um, sofort neu zeichnen (Nachricht von ezCore 1.12.0)
ezCore.Listen("GLOW_MARKS_CHANGED", function() Marks.Refresh() end, ADDON)

---------------------------------------------------------------------------
-- Eigene Marken
---------------------------------------------------------------------------

-- Quest: Erkennung liefert ezQuest (ns.API.ItemQuest), ezBag zeigt nur an.
function ns.QuestItem(itemID, link)
    local api = ezCore.API("ezQuest")
    if not (api and type(api.ItemQuest) == "function") then return nil end
    local ok, info = pcall(api.ItemQuest, itemID, link)
    if ok and type(info) == "table" then return info end
    return nil
end

-- Eine Regel für „Quest-Gegenstand an diesem Platz“ (Gruppe „Quest“ und „Platz schaffen“): Blizzards
-- Angabe zum Platz, dazu was ezQuest erkennt (z. B. Leinenstoff für ein aktives Questziel), falls geladen.
function ns.IsQuestSlot(bag, slot, itemID, link)
    local quest = C_Container.GetContainerItemQuestInfo(bag, slot)
    if quest and (quest.isQuestItem or quest.questID) then return true end
    if not ns.PlainID(itemID) then return false end
    return ns.QuestItem(itemID, link) ~= nil
end

local QUEST_STARTS = "Interface\\GossipFrame\\AvailableQuestIcon"
local QUEST_NEEDED = "Interface\\GossipFrame\\ActiveQuestIcon"

Marks.Add("ezBag.quest", { order = 20, owner = ADDON, fn = function(itemID, link)
    if not (ns.S and ns.S.questMark) then return nil end
    local info = ns.QuestItem(itemID, link)
    if not info then return nil end
    return { texture = info.starts and QUEST_STARTS or QUEST_NEEDED, desaturate = info.done == true }
end })

-- Sammlungen und Bibliotheksbücher (Item-Wissen aus ezCore): Stern = Aussehen, Reittier, Haustier oder
-- Spielzeug fehlt noch (grau: nur für eine andere Klasse; Erkennung und Stern aus ezCore.Collections, wie
-- an Händler und Beute); Buch = noch abzugeben (grau: schon abgegeben).
local BOOK = "Interface\\Icons\\INV_Misc_Book_09"

Marks.Add("ezBag.collect", { order = 30, owner = ADDON, fn = function(itemID, link)
    if not (ns.S and ns.S.collectMark) then return nil end
    local _, book = ns.CollectInfo(itemID, link)
    if book then return { texture = BOOK, desaturate = book.done == true } end
    local C = ezCore.Collections
    if not (C and C.Missing) then return nil end
    local missing, otherClass = C.Missing(link or itemID)
    if missing then return { texture = C.MARK_TEXTURE, desaturate = otherClass == true } end
end })

-- Material für die gemeinsamen Einkaufslisten (CRAFT-14, V-144): Gesamtbedarf aus Core.Lists (ezCraft und ezAuction),
-- gemerkt bis zur Nachricht LISTS_CHANGED oder einer Änderung der Rezepte bzw. des Berufefensters (und vor jedem
-- Plunder-Verkauf und jedem „Platz schaffen“ neu gelesen). Der Plunder-Verkauf und
-- „Platz schaffen“ lassen diese Gegenstände liegen; die Menge nennt ezCrafts eigene Tooltip-Zeile („Einkaufsliste“).
-- Gelesen und gemerkt wird in ezCore (Core.Junk.CraftNeed/ClearCraftNeeds, A43 – eine Fassung für ezBag und ezMerchant
-- ohne ezBag); ns.CraftNeed und ns.ClearCraftNeeds bleiben als Weiterleitung.
-- → Bedarf (Zahl > 0) oder nil (auf keiner Liste, gesperrte ID)
function ns.CraftNeed(itemID)
    itemID = ns.PlainID(itemID)
    if not itemID then return nil end
    return ezCore.Junk.CraftNeed(itemID)
end

function ns.ClearCraftNeeds() ezCore.Junk.ClearCraftNeeds() end

local SHOPPING = "Interface\\Icons\\INV_Misc_Note_01"

Marks.Add("ezBag.craft", { order = 40, owner = ADDON, fn = function(itemID)
    if not (ns.S and ns.S.craftMark) then return nil end
    if ns.CraftNeed(itemID) then return { texture = SHOPPING } end
end })

local function CraftNeedsChanged() Marks.Refresh() end      -- den Bedarf verwirft ezCore selbst (Lists, Junk)
ezCore.Listen("LISTS_CHANGED", CraftNeedsChanged, ADDON)
-- Auch hier ändert sich der Bedarf, ohne Nachricht: Das Berufefenster liefert andere Zutaten als das Rezept-Wissen,
-- solange es offen ist (ezCore.Junk verwirft ihn bei denselben Ereignissen).
ezCore.Listen("RECIPES_CHANGED", CraftNeedsChanged, ADDON)
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_CLOSE" }) do
    ns.On(event, CraftNeedsChanged)
end

-- Von dir (Alt+Rechtsklick, Ziehen, Auswahl) einer Gruppe außer „Plunder“ zugewiesen? Gilt für jede Qualität.
function ns.HandAssigned(itemID)
    if not itemID or not ns.db then return false end
    local assigned = ns.db.assign[itemID]
    return assigned ~= nil and assigned ~= "junk"
end

-- „Nie verkaufen“ mit Symbol und Wirkung auf den Plunder-Verkauf: grau, aber von dir einer anderen Gruppe zugewiesen.
function ns.NeverSell(itemID, quality)
    if quality ~= 0 then return false end
    return ns.HandAssigned(itemID)
end

local LOCK = "Interface\\PetBattles\\PetBattle-LockIcon"

-- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Abschnitt 4): ohne das Symbol sähe man den selbst gesetzten
-- Schutz nicht. Die Erklärung steht im Tooltip der Überschrift „Händler und Handel“ (OPT_SECTION_vendor_TIP).
Marks.Add("ezBag.lock", { order = 60, owner = ADDON, fn = function(itemID, _, _, _, quality)
    if ns.NeverSell(itemID, quality) then return { texture = LOCK } end
end })

-- „Im Auktionshaus mehr wert“ (AH-26): ezCores Münze (Schlüssel ezCore.auctionWorth). Rechnung, Schwelle, Rangfolge
-- (order 70, bei offenem Händlerfenster 25) und die Tooltip-Zeile mit Auktionswert, Händlerpreis, Quelle und Alter
-- stehen in ezCore (Wissen/Prices.lua: AuctionWorth, WorthMark, Tooltip-Abschnitt ezCore.auctionWorth) – ezBag rechnet
-- nichts und schreibt keine eigene Zeile, es zeichnet die Münze nur oder lässt sie weg. Weggelassen rückt die nächste
-- Marke nach (höchstens zwei, Reihenfolge wie von ezCore gemeldet).
-- In der Tasche ab Werk aus (Schalter auctionWorth). Beim Händler schaltet ezMerchant sie ein (AH-27): solange ein
-- Händlerfenster offen ist und ezMerchant läuft. Ob sie dort erscheint, entscheidet allein ezCores Schalter der Münze
-- (ezCore meldet sie sonst gar nicht an); ezMerchants Schalter auctionWorth gilt nur für die Zeile unter dessen
-- Händlerfenster. Bis Welle 23 fragte ezBag dafür ezCore.API("ezMerchant").AuctionWorth() – ezMerchant bot das nie an
-- (es bietet KeepAuctionWorth/ShowKept, siehe Junk.lua). → true, wenn die Münze an ezBags Plätzen erscheinen darf
Marks.AUCTION_WORTH = "ezCore.auctionWorth"

function Marks.AuctionWorthShown()
    -- ezCores Schalter „in der Tasche“ (ns.SHARED: auctionWorth = priceOpts.worthBag; Einstellungs-Prüfung 19.11.2026)
    if ns.Enabled("auctionWorth") then return true end
    if not ns.AtMerchant() then return false end
    return type(ezCore.API("ezMerchant")) == "table"
end

-- Händlerfenster auf oder zu: ezCore meldet seine Münze mit neuer Rangfolge neu an (das zeichnet ohnehin neu); hier
-- zusätzlich, damit die Münze ohne Schalter mit dem Fenster kommt und geht.
ns.On("MERCHANT_SHOW", function() Marks.Refresh() end)
ns.On("MERCHANT_CLOSED", function() Marks.Refresh() end)

---------------------------------------------------------------------------
-- Schnittstelle für andere Module (ezCore.API("ezBag"), siehe README)
---------------------------------------------------------------------------

ns.API = ns.API or {}
ns.API.AddSlotMark = Marks.Add
-- Zeichnet ezBag die Marken in Blizzards Taschen? Nur in der zusammengefassten; einzelne Taschen übernimmt ezCore.
ns.API.MarksBags = function() return ns.UsingCombinedBags() end
ns.API.RemoveSlotMark = Marks.Remove
ns.API.RefreshMarks = Marks.Refresh
ns.API.SLOT_MARK_ROTATION = true   -- Platzmarken dürfen rotation (Bogenmaß) mitgeben

-- IsLocked(bag, slot) → true, wenn der Gegenstand auf diesem Taschenplatz als „nie verkaufen“ gilt: vom Nutzer
-- einer anderen Gruppe als „Plunder“ zugewiesen – jede Qualität (ns.HandAssigned). Bis Welle 23 nur graue
-- Gegenstände (ns.NeverSell); seit der Entscheidung des Nutzers vom 16.11.2026 (Nr. 18, ezBag.md Frage 8,
-- vorläufig nach Empfehlung) meldet die Auskunft jeden von Hand zugewiesenen Gegenstand – so wirkt sie auch für
-- ezCrafts Liste „Entzaubern“, ezMacros Ein-Klick, ezAuctions Taschenliste und ezCores Münze „im Auktionshaus mehr
-- wert“. Das Symbol am Platz und der Plunder-Verkauf bleiben bei grauen (ns.NeverSell). Die eine Auskunft „nie
-- verkaufen“ für andere Module: nur lesen. Leerer Platz, gesperrte Werte, falsche Angaben → false.
function ns.API.IsLocked(bag, slot)
    if type(bag) ~= "number" or type(slot) ~= "number" then return false end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local itemID = ns.ItemIDOf(info)
    if not itemID then return false end
    return ns.HandAssigned(itemID) == true
end

-- ezQuest meldet geänderte Quest-Gegenstände: neu einsortieren und Marken zeichnen.
ezCore.Listen("EZQUEST_ITEMS_CHANGED", function()
    if ns.Groups then ns.Groups.ClearRuleCache() end
    if ns.Layout then ns.Layout.Request() end
    if ns.Bank then ns.Bank.Refresh(false) end
    Marks.Refresh()
end, ADDON)

ns.OnSettingChanged(function(key)
    if key == "questMark" or key == "collectMark" or key == "craftMark" or key == "auctionWorth" then
        Marks.Refresh()
    end
end)
