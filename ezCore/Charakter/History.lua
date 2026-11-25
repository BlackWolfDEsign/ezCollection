local _, ns = ...
local Core = ezCore

--[[
    Verlauf als eine Quelle (Punkt 5): Beute (ezLoot), Gold (ezPanel), Post (ezMail) und Auktionen (ezAuction,
    ezMail, ezPanel). ezCore erfasst, die Module zeigen nur an. Gespeichert in ezCoreDB.history[art], je Art
    die neuesten Einträge (älteste fallen heraus), jeder Eintrag mit Zeit `t` und Charakter `c` (charKey).

      History.Add(art, eintrag)        → eintrag (für eigene Arten eines Moduls; t und c setzt ezCore)
      History.List(art, filter)        → { eintrag … } neueste zuerst
                                         filter = { char = key, since = time(), limit = n, match = fn(e) → bool }
      History.Sum(art, feld, filter)   → Summe eines Zahlenfelds
      History.Clear(art)
      History.Since(zeitraum) → time() des Beginns: "today", "day", "week", "month" oder Tage; nil = gesamt
      History.AuctionTotals(filter) → { sale, buy, back, outbid, income, fees, spent, balance, ahIn }
                                         (eine Rechnung für ezAuction, ezMail und ezPanel)
      Nachricht: HISTORY_ADDED (art, eintrag) bei jedem neuen Eintrag

    Arten und Felder:
      loot     link, id, n (Anzahl), q (Qualität), money (Kupfer bei Münzen), cur (Währungs-ID),
               src = { type = "Creature"|"GameObject"|"Item"|"fishing"|"roll"|…, name, npc }, roll (gewonnener Wurf),
               zone (Text), map (uiMapID), inst (Instanz-ID aus GetInstanceInfo),
               w (Nummer des Plündern-Fensters, gleich für alle Einträge und das Gold eines Fensters; Vorschlag von ezLoot)
      gold     d (Änderung in Kupfer, + oder −), m (Gold danach), src = "loot"|"mail"|"auction"|"merchant"|
               "trainer"|"taxi"|"trade"|"guildbank"|"quest"|"barber"|"other"
      mail     dir = "in"|"out", who (Absender bzw. Empfänger), subj, money, cod, items = { { i, l, c } … }
      auction  type = "sale"|"buy"|"expired"|"cancelled"|"outbid", item (Name), link, n, gross (Brutto),
               fee (Gebühr), deposit (Anzahlung), net (Netto), who (Käufer bzw. Verkäufer); bei "sale" zusätzlich
               sold (geschätzter Verkaufszeitpunkt, nur tagesgenau zu zeigen) und soldEst = true (W-56, SoldAt);
               t ist die Abholzeit
      posting  eigene Einstellung im Auktionshaus mit Ergebnis (AH-21, Welle 14) – Felder im Abschnitt „Einstell-Verlauf“
      combat   ein Kampf, geschrieben von ezCombat (Zusammenfassung nach dem Kampf, MeterSummary.lua; EC-113):
               dur (Dauer in Sekunden), dmg (eigener Schaden), dps, dmgRank (Platz in der Gruppe), heal (eigene
               Heilung), hps, healRank, size (Gruppengröße), zone (Text). Nur offene Werte aus Blizzards
               C_DamageMeter – was das Spiel sperrt, fehlt im Eintrag. ezCore erfasst diese Art nicht selbst.

    History.KINDS nennt die Arten in fester Reihenfolge (für Auswahlen), History.KindLabel(art) ihren Namen
    („Beute“, „Gold“, „Post“, „Auktionen“, „Kämpfe“, „Einstellungen“), History.MAX[art] die Grenze je Art (sonst 1000).

    Erfasst wird nur, was der Client ohnehin zeigt: Plündern-Fenster (LOOT_*), „Ihr habt gewonnen“ im
    Chat, PLAYER_MONEY mit dem offenen Fenster als Quelle, gesendete Post (MAIL_SENT aus Inventory.lua) und
    Entnahmen aus dem Posteingang (hooksecurefunc auf TakeInboxMoney, TakeInboxItem, AutoLootMailItem).
    Geheime Werte werden ausgelassen.
]]

Core.History = Core.History or {}
local History = Core.History

History.MAX = { loot = 2000, gold = 2000, mail = 1000, auction = 2000, combat = 500, posting = 1000 }
local DEFAULT_MAX = 1000
-- Die Arten des Verlaufs in fester Reihenfolge (Auswahlen, Übersichten). Nicht zu verwechseln mit der Reihenfolge
-- der Gold-Quellen weiter unten (offenes Fenster): ein Kampf ist keine Gold-Quelle.
History.KINDS = { "loot", "gold", "mail", "auction", "combat", "posting" }

local Plain, Num = Core.Plain, Core.Num

local Now, Clock = Core.Now, Core.Uptime

local function Store(kind, create)
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if not db.history then
        if not create then return nil end
        db.history = {}
    end
    local list = db.history[kind]
    if not list and create then
        list = {}
        db.history[kind] = list
    end
    return list
end

-- Volle Verläufe mit Spielraum kürzen (Gesamtreview 18.11.2026, T8-7): vorher schob jeder neue Eintrag eines vollen
-- Verlaufs mit table.remove(list, 1) bis zu 2000 Einträge um eine Stelle. Jetzt darf die Liste um History.SLACK (Anteil,
-- mindestens 1 Eintrag) über max wachsen und wird dann in EINEM Durchlauf auf max gekürzt (die ältesten fallen weg).
-- Alle Leser sehen nur die neuesten max Einträge (History.Window: History.List, LootOfNpc, LootSources, Count), für sie
-- bleibt die Grenze also genau (Gegenprüfung P19a – vorher lasen LootOfNpc, LootSources und Count die ganze Liste
-- samt Spielraum). → Anzahl entfernter
History.SLACK = 0.1
function History.Trim(list, max)
    if type(list) ~= "table" then return 0 end
    max = math.max(0, math.floor(tonumber(max) or DEFAULT_MAX))
    local n = #list
    local slack = math.max(1, math.floor(max * History.SLACK))
    if n < max + slack then return 0 end
    local extra = n - max
    for i = 1, max do list[i] = list[i + extra] end
    for i = n, max + 1, -1 do list[i] = nil end
    return extra
end

-- Die Liste einer Art und der erste Index, ab dem Leser sie sehen (die neuesten History.MAX[kind] Einträge; der
-- Spielraum von History.Trim bleibt unsichtbar) → liste, erster Index; ohne Liste eine leere Tabelle und 1.
local NO_ENTRY = {}   -- Platzhalter für Fremdes in der Liste (Leser über History.Window)
function History.Window(kind)
    local list = Store(kind, false)
    if type(list) ~= "table" then return {}, 1 end
    local max = History.MAX[kind] or DEFAULT_MAX
    return list, math.max(1, #list - max + 1)
end

function History.Add(kind, entry)
    local list = type(kind) == "string" and type(entry) == "table" and Store(kind, true)
    if not list then return nil end
    entry.t = entry.t or Now()
    entry.c = entry.c or Core.charKey
    list[#list + 1] = entry
    History.Trim(list, History.MAX[kind] or DEFAULT_MAX)
    Core.Fire("HISTORY_ADDED", kind, entry)
    return entry
end

local function Matches(e, filter)
    if not filter then return true end
    if filter.char and e.c ~= filter.char then return false end
    if filter.since and (e.t or 0) < filter.since then return false end
    if filter.match and not filter.match(e) then return false end
    return true
end

---------------------------------------------------------------------------
-- Beute nach Gegner (Nutzer 13.11.2026: Beute im Tooltip von Gegnern, Bezugsquellen von Rohstoffen)
--   History.LootOfNpc(npcID)  → { name, loots (Plündern-Fenster), items = { { id, link, q, n, times } … },
--                                 money (Kupfer gesamt), moneyLoots, drops, dropsInfo }; Gegenstände häufigste zuerst.
--                                 drops: die Zählung der Entdecker-Datenbank (Core.Drops.Of, Welle 9) – ohne V-008
--   History.LootSources(itemID) → { { npc, name, zone, times, n } … } Gegner, die ihn fallen ließen, häufigste zuerst
-- Eigene Beute aller Charaktere; Forever liefert keine Beutetabellen.
---------------------------------------------------------------------------

-- Fenster eines Eintrags: mit Fensternummer genau (c#w). Ältere Einträge ohne w (vor ezCore 1.5) gehören zum selben
-- Fenster, wenn sie vom selben Charakter und Gegner höchstens NO_W_GAP Sekunden nach dem vorigen kamen – das Gold
-- kommt bis zu 2 s nach dem Schließen (Hinweis von ezLoot). state merkt sich je Charakter und Gegner das letzte.
local NO_W_GAP = 3
local function LootWindow(e, state)
    if Num(e.w) then return tostring(e.c) .. "#" .. e.w end
    local src = e.src
    local who = tostring(e.c) .. ":" .. tostring(type(src) == "table" and (src.npc or src.name) or "")
    local t = Num(e.t) or 0
    local last = state and state[who]
    if last and math.abs(t - last.t) <= NO_W_GAP then
        last.t = t
        return last.key
    end
    local key = who .. "@" .. t
    if state then state[who] = { t = t, key = key } end
    return key
end
-- Dieselbe Regel für die einmalige Übernahme in die Beute-Zählung der Entdecker-Datenbank (Discovery.lua)
History.LootWindowOf = LootWindow

function History.LootOfNpc(npcID)
    npcID = Num(npcID)
    local out = { loots = 0, items = {}, money = 0, moneyLoots = 0 }
    if not npcID then return out end
    local windows, moneyWindows, byItem, itemWindows, state = {}, {}, {}, {}, {}
    local loot, first = History.Window("loot")
    for i = first, #loot do
        local e = type(loot[i]) == "table" and loot[i] or NO_ENTRY
        local src = e.src
        if type(src) == "table" and src.npc == npcID then
            out.name = src.name or out.name
            local key = LootWindow(e, state)
            if not windows[key] then windows[key], out.loots = true, out.loots + 1 end
            if Num(e.money) then
                out.money = out.money + e.money
                if not moneyWindows[key] then moneyWindows[key], out.moneyLoots = true, out.moneyLoots + 1 end
            elseif Num(e.id) then
                local item = byItem[e.id]
                if not item then
                    item = { id = e.id, link = e.link, q = e.q, n = 0, times = 0 }
                    byItem[e.id] = item
                    out.items[#out.items + 1] = item
                end
                item.n = item.n + (Num(e.n) or 1)
                -- times zählt Fenster, nicht Einträge (zwei Stapel im selben Fenster zählen einmal)
                local seen = itemWindows[e.id] or {}
                itemWindows[e.id] = seen
                if not seen[key] then seen[key], item.times = true, item.times + 1 end
                item.link = item.link or e.link
            end
        end
    end
    table.sort(out.items, function(a, b)
        if a.times ~= b.times then return a.times > b.times end
        return (a.q or 0) > (b.q or 0)
    end)
    -- Zusätzlich die Zählung der Entdecker-Datenbank (Inhalt des Fensters beim Öffnen, jede Leiche einmal, Gruppe nicht
    -- im Nenner – ohne den Fehler V-008): out.drops = { cnt, party, deaths, empty, money, items = { [itemID] = { f, s,
    -- lo, hi } }, old … }, out.dropsInfo = Auskunft (Quelle „bei dir“). Die Felder oben bleiben die des Tagebuchs.
    local D = Core.Drops
    if D and D.Of then out.drops, out.dropsInfo = D.Of("loot", npcID) end
    return out
end

function History.LootSources(itemID)
    itemID = Num(itemID)
    local list, by, seen, state = {}, {}, {}, {}
    if not itemID then return list end
    local loot, first = History.Window("loot")
    for i = first, #loot do
        local e = type(loot[i]) == "table" and loot[i] or NO_ENTRY
        local src = e.src
        if e.id == itemID and type(src) == "table" and (src.type == "Creature" or src.type == "Vehicle") then
            local key = src.npc or src.name
            if key then
                local s = by[key]
                if not s then
                    s = { npc = src.npc, times = 0, n = 0 }
                    by[key], seen[key] = s, {}
                    list[#list + 1] = s
                end
                s.name, s.zone = s.name or src.name, s.zone or e.zone
                s.n = s.n + (Num(e.n) or 1)
                local window = LootWindow(e, state)
                if not seen[key][window] then seen[key][window], s.times = true, s.times + 1 end
            end
        end
    end
    table.sort(list, function(a, b) return a.times > b.times end)
    return list
end

-- Einen Eintrag wieder entfernen (z. B. ein Anhang, den der Server abgelehnt hat). Nachricht HISTORY_REMOVED.
function History.Remove(kind, entry)
    local list = type(entry) == "table" and Store(kind, false)
    if not list then return false end
    for i = #list, 1, -1 do
        if list[i] == entry then
            table.remove(list, i)
            Core.Fire("HISTORY_REMOVED", kind, entry)
            return true
        end
    end
    return false
end

function History.List(kind, filter)
    local out = {}
    if not Store(kind, false) then return out end
    local limit = filter and filter.limit
    -- höchstens die neuesten max Einträge (History.Trim lässt bis zu History.SLACK mehr stehen, T8-7)
    local list, first = History.Window(kind)
    for i = #list, first, -1 do
        local e = list[i]
        if Matches(e, filter) then
            out[#out + 1] = e
            if limit and #out >= limit then break end
        end
    end
    return out
end

function History.Sum(kind, field, filter)
    local sum = 0
    for _, e in ipairs(History.List(kind, filter)) do sum = sum + (Num(e[field]) or 0) end
    return sum
end

local DAY = 86400

-- Zeiträume und Arten des Auktionsverlaufs – EINE Liste samt Texten (V-061; vorher je eine in ezMail und ezAuction,
-- mit „Heute“ gegen „24 Stunden“). History.Since versteht jeden Schlüssel aus PERIOD_KEYS.
History.PERIODS = { "today", "week", "month", "all" }                 -- die Auswahl, die Fenster anbieten
History.PERIOD_KEYS = { "today", "day", "week", "month", "all" }      -- alles, was History.Since kennt
History.AUCTION_TYPES = { "sale", "buy", "expired", "cancelled", "outbid" }

-- Anzeigename eines Zeitraums („Letzte 7 Tage“); short = true die Kurzform („7 Tage“). Unbekannt → nil.
function History.PeriodLabel(period, short)
    if type(period) ~= "string" then return nil end
    local key = (short and "HIST_PERIOD_SHORT_" or "HIST_PERIOD_") .. period
    local text = Core.L[key]          -- Core.L liefert für Unbekanntes den Schlüssel selbst
    if text == key then return nil end
    -- „Heute“ ist der Tag in der Ortszeit des PCs (Entscheidung 6 vom 18.11.2026, T16-NZ3); Lang- und Kurzform nennen
    -- die Basis, weil daneben (Seitenteil „Markt“ von ezAuction) Preis-Tage in Serverzeit stehen – auch die Auswahl
    -- des Auktionsverlaufs, die die Kurzform zeigt
    if period == "today" then text = Core.Time.Tagged(text, "local") end
    return text
end

-- Anzeigename einer Verlaufsart („Beute“, „Kämpfe“). Unbekannt → nil.
function History.KindLabel(kind)
    if Core.IsSecret(kind) or type(kind) ~= "string" then return nil end
    local key = "HIST_KIND_" .. kind
    local text = Core.L[key]
    if text == key then return nil end
    return text
end

-- Anzeigename einer Auktionsart („Verkauft“) oder – wenn es keine Auktionsart ist – einer Verlaufsart
-- (History.TypeLabel("combat") → „Kämpfe“). Unbekannt → nil.
function History.TypeLabel(kind)
    if Core.IsSecret(kind) or type(kind) ~= "string" then return nil end
    local key = "HIST_AUCTION_" .. kind
    local text = Core.L[key]
    if text == key then return History.KindLabel(kind) end
    return text
end

-- Liste für Auswahlmenüs: { { key, text } … } in der Reihenfolge von History.PERIODS (bzw. der übergebenen Liste).
function History.PeriodChoices(list, short)
    local out = {}
    for _, key in ipairs(type(list) == "table" and list or History.PERIODS) do
        local text = History.PeriodLabel(key, short)
        if text then out[#out + 1] = { key, text } end
    end
    return out
end

-- Beginn eines Zeitraums als Stempel der PC-Uhr; "today" = Mitternacht in der Ortszeit des PCs (Core.Time, eine Regel
-- für „heute“ in allen Anzeigen; T16-NZ3).
function History.Since(period, now)
    now = Num(now) or Now()
    if period == "today" then
        return Core.Time.DayStart((Core.Time.Day(now, "local")), "local")
    end
    local days = (period == "day" and 1) or (period == "week" and 7) or (period == "month" and 30) or Num(period)
    return days and (now - days * DAY) or nil
end

-- Anzahl je Art; income = Netto der Verkäufe, fees = Gebühren, spent = Kaufpreis, balance = income − spent,
-- ahIn = Gold, das per Post aus dem Auktionshaus kommt (Verkäufe netto und zurückgegebene Gebote).
function History.AuctionTotals(filter)
    local t = { sale = 0, buy = 0, back = 0, outbid = 0, income = 0, fees = 0, spent = 0, balance = 0, ahIn = 0 }
    for _, e in ipairs(History.List("auction", filter)) do
        local kind = e.type
        if kind == "sale" then
            t.sale = t.sale + 1
            t.income = t.income + (Num(e.net) or 0)
            t.fees = t.fees + (Num(e.fee) or 0)
            t.ahIn = t.ahIn + (Num(e.net) or 0)
        elseif kind == "buy" then
            t.buy = t.buy + 1
            t.spent = t.spent + (Num(e.gross) or 0)
        elseif kind == "expired" or kind == "cancelled" then
            t.back = t.back + 1
        elseif kind == "outbid" then
            t.outbid = t.outbid + 1
            t.ahIn = t.ahIn + (Num(e.net) or 0)
        end
    end
    t.balance = t.income - t.spent
    return t
end

function History.Clear(kind)
    local db = Core.db
    if kind == nil or type(db) ~= "table" or not db.history then return end
    local had = db.history[kind] ~= nil
    db.history[kind] = nil
    if had then Core.Fire("HISTORY_CLEARED", kind) end
end

-- Anzahl der Einträge, die Leser sehen (History.Window; der Spielraum von History.Trim zählt nicht): einer Art oder
-- (ohne Angabe) aller Arten.
function History.Count(kind)
    local db = Core.db
    local all = type(db) == "table" and type(db.history) == "table" and db.history or {}
    local function Of(k, list)
        if type(list) ~= "table" then return 0 end
        return math.min(#list, History.MAX[k] or DEFAULT_MAX)
    end
    if kind ~= nil then return Of(kind, all[kind]) end
    local n = 0
    for k, list in pairs(all) do n = n + Of(k, list) end
    return n
end

-- Den ganzen Verlauf leeren (Beute, Gold, Post, Auktionen; Knopf „Verlauf leeren“ auf der Seite „ezCollection“).
-- → Anzahl entfernter Einträge (wie History.Count, dieselbe Zahl wie in der Rückfrage). Nachricht HISTORY_CLEARED (nil).
function History.ClearAll()
    local db = Core.db
    local n = History.Count()
    if type(db) == "table" and type(db.history) == "table" then
        for kind in pairs(db.history) do db.history[kind] = nil end
    end
    Core.Fire("HISTORY_CLEARED", nil)
    return n
end

---------------------------------------------------------------------------
-- Ort und Quelle
---------------------------------------------------------------------------

local ItemID = Core.ItemID
History.ItemID = ItemID

local function Where()
    local zone = GetRealZoneText and Plain(GetRealZoneText()) or nil
    local map = C_Map and C_Map.GetBestMapForUnit and Num(C_Map.GetBestMapForUnit("player")) or nil
    local inst
    -- Nur in einer Instanz (Core.InInstance prüft gesperrte Antworten; unbekannt zählt als „vielleicht“)
    if GetInstanceInfo and Core.InInstance() ~= false then
        local ok, _, instanceType, _, _, _, _, _, instanceID = pcall(GetInstanceInfo)
        instanceType = ok and Plain(instanceType) or nil
        if instanceType and instanceType ~= "none" then inst = Num(instanceID) end
    end
    return zone, map, inst
end

-- Quelle aus einer GUID: Art (erstes Feld), NPC-ID (Feld 6 bei Kreaturen) und, wenn bekannt, der Name.
function History.Source(guid)
    guid = Plain(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local kind = strsplit("-", guid)
    local src = { type = kind }
    if kind == "Creature" or kind == "Vehicle" then src.npc = Core.NpcID(guid) end
    for _, unit in ipairs({ "target", "mouseover", "focus" }) do
        if UnitGUID and Plain(UnitGUID(unit)) == guid then
            src.name = Plain(UnitName(unit))
            break
        end
    end
    return src
end

---------------------------------------------------------------------------
-- Beute: Plündern-Fenster und gewonnene Würfe
---------------------------------------------------------------------------

local loot, lootSource, lootWindow
local LOOT_MONEY = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2
local LOOT_CURRENCY = Enum and Enum.LootSlotType and Enum.LootSlotType.Currency or 3

-- Fortlaufende Nummer je Plündern-Fenster (über Sitzungen hinweg, ezCoreDB.historyWindow).
local function NextLootWindow()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    db.historyWindow = (Num(db.historyWindow) or 0) + 1
    return db.historyWindow
end
History.NextLootWindow = NextLootWindow

-- Welle 23c (A69): Der Sammler liest das Fenster schon bei LOOT_READY (mit schnellem Plündern sind die Plätze bei
-- LOOT_OPENED oft schon geleert – dann fehlte die Beute im Verlauf) und nur einmal je Öffnen (LOOT_READY kommt bis zu
-- dreimal, LOOT_OPENED danach; LOOT_CLOSED gibt frei). Entdoppeln je Quell-GUID: öffnest du dieselbe Leiche bzw.
-- dasselbe Objekt in dieser Sitzung erneut, bekommt das Fenster dieselbe Nummer (w) – History.LootOfNpc zählt es
-- einmal. Angeln hat keine Quell-GUID: jedes Fenster ist ein eigener Fang. Höchstens History.LOOT_SOURCE_MAX GUIDs.
History.LOOT_SOURCE_MAX = 200
local lootOpen = false
local windowBySource, windowBySourceN = {}, 0

local function SnapshotLoot()
    if lootOpen then return end
    lootOpen = true
    loot = {}
    lootSource = nil
    lootWindow = nil
    if not GetNumLootItems then
        lootWindow = NextLootWindow()
        return
    end
    -- Abfragen geschützt (Core.Call): seit LOOT_READY liest der Sammler früher, ein Fehler hier darf die übrigen
    -- Zuhörer des Ereignisses nicht treffen
    local fishing = Core.Bool(Core.Call(rawget(_G, "IsFishingLoot")), false) == true
    local firstGuid
    for slot = 1, Num(Core.Call(GetNumLootItems)) or 0 do
        local slotType = Num(Core.Call(rawget(_G, "GetLootSlotType"), slot))
        local _, name, quantity, currencyID, quality = Core.Call(rawget(_G, "GetLootSlotInfo"), slot)
        local guid = Plain((Core.Call(rawget(_G, "GetLootSourceInfo"), slot)))
        if type(guid) ~= "string" or guid == "" then guid = nil end
        firstGuid = firstGuid or guid
        local src = fishing and { type = "fishing" } or History.Source(guid)
        lootSource = lootSource or src
        if slotType ~= LOOT_MONEY then
            local link = Plain(Core.Call(rawget(_G, "GetLootSlotLink"), slot))
            loot[slot] = { link = link or Plain(name), id = ItemID(link), n = Num(quantity) or 1, q = Num(quality),
                cur = slotType == LOOT_CURRENCY and Num(currencyID) or nil, src = src }
        end
    end
    local key = not fishing and firstGuid or nil
    lootWindow = key and windowBySource[key] or nil
    if not lootWindow then
        lootWindow = NextLootWindow()
        if key and lootWindow then
            if windowBySourceN >= History.LOOT_SOURCE_MAX then windowBySource, windowBySourceN = {}, 0 end
            windowBySource[key] = lootWindow
            windowBySourceN = windowBySourceN + 1
        end
    end
    for _, e in pairs(loot) do e.w = lootWindow end
end
History.SnapshotLoot = SnapshotLoot

local function LootSlotCleared(_, slot)
    local e = loot and loot[slot]
    if not e then return end
    loot[slot] = nil
    e.zone, e.map, e.inst = Where()
    History.Add("loot", e)
end

local wonPattern
local function OnLootMessage(_, msg)
    if Core.IsSecret(msg) or type(msg) ~= "string" then return end
    if wonPattern == nil then wonPattern = LOOT_ROLL_YOU_WON and Core.FormatToPattern(LOOT_ROLL_YOU_WON) or false end
    local link = wonPattern and msg:match(wonPattern)
    if not link then return end
    local id = ItemID(link)
    local quality = id and C_Item and C_Item.GetItemQualityByID and Num(C_Item.GetItemQualityByID(id)) or nil
    local zone, map, inst = Where()
    History.Add("loot", { link = link, id = id, n = 1, q = quality, src = { type = "roll" }, roll = true,
        zone = zone, map = map, inst = inst })
end

---------------------------------------------------------------------------
-- Gold: Änderung mit dem offenen Fenster als Quelle
---------------------------------------------------------------------------

local ctx = {}         -- Fenster → true (offen) oder GetTime(), bis zu dem es nach dem Schließen noch zählt
local AFTER = 2        -- Gold kommt oft kurz nach dem Schließen (Handel, Quest, Plündern)
local ORDER = { "loot", "mail", "auction", "merchant", "trainer", "taxi", "trade", "guildbank", "quest", "barber" }
local lastMoney

local function Open(name) ctx[name] = true end
local function Close(name) ctx[name] = Clock() + AFTER end

function History.Context()
    local now = Clock()
    for _, name in ipairs(ORDER) do
        local v = ctx[name]
        if v == true or (type(v) == "number" and v > now) then return name end
    end
    return "other"
end

local function OnMoney()
    local money = Core.Characters.EventMoney()
    if not money then return end
    local before = lastMoney
    lastMoney = money
    if not before or money == before then return end
    local d = money - before
    local src = History.Context()
    History.Add("gold", { d = d, m = money, src = src })
    if src == "loot" and d > 0 then
        local zone, map, inst = Where()
        History.Add("loot", { money = d, src = lootSource, zone = zone, map = map, inst = inst, w = lootWindow })
    end
end

---------------------------------------------------------------------------
-- Post und Auktionen
---------------------------------------------------------------------------

local taken = {}   -- je Brief: Gold bzw. Anhänge schon erfasst (doppelte Hooks bei „Alle öffnen“)
local lastTake     -- letzte Entnahme mit Anhängen (für MAIL_FAILED)

local function MailKey(index, h)
    return Core.Mail.Signature(h) .. "\031" .. tostring(h.daysLeft or index)
end

-- Wie viele Briefe im Posteingang haben diesen Schlüssel? (Zwei gleiche AH-Verkäufe derselben Sekunde)
local function KeyCounts()
    local counts = {}
    local okN, n = pcall(GetInboxNumItems)
    for index = 1, (okN and Num(n)) or 0 do
        local h = Core.Mail and Core.Mail.Header(index)
        if h then
            local key = MailKey(index, h)
            counts[key] = (counts[key] or 0) + 1
        end
    end
    return counts
end

-- Ist ein Brief verschwunden, gilt sein Merker nicht mehr – ein gleicher Brief danach wird wieder erfasst.
local function ForgetGoneMail()
    if next(taken) == nil then return end
    local counts = KeyCounts()
    for key, seen in pairs(taken) do
        local now = counts[key] or 0
        if now < (seen.count or 1) then taken[key] = nil else seen.count = now end
    end
end

-- Auktionshaus-Betreff: eine Erkennung für Post und Verlauf (Mail.AuctionKind, V-028).
local function AuctionType(subject)
    return Core.Mail.AuctionKind(subject)
end
History.AuctionType = AuctionType

local function Invoice(index)
    if not GetInboxInvoiceInfo then return nil end
    local ok, invoiceType, itemName, playerName, bid, buyout, deposit, consignment, _, _, count = pcall(GetInboxInvoiceInfo, index)
    if not ok or not invoiceType then return nil end
    return { type = invoiceType, item = Plain(itemName), who = Plain(playerName), bid = Num(bid), buyout = Num(buyout),
        deposit = Num(deposit), fee = Num(consignment), n = Num(count) }
end

local function ItemsOf(index, only)
    local items = {}
    local first, last = only or 1, only or (ATTACHMENTS_MAX_RECEIVE or 16)
    for att = first, last do
        local _, itemID, _, count = GetInboxItem(index, att)
        itemID = Num(itemID)
        if itemID then
            items[#items + 1] = { i = itemID, l = GetInboxItemLink and Plain(GetInboxItemLink(index, att)), c = Num(count) or 1 }
        end
    end
    return items
end

-- W-56: geschätzter Verkaufszeitpunkt einer Auktion. Der Eintrag „auction“ entsteht beim Entnehmen der Post und trägt
-- deren Zeit (t); der Verkauf lag früher: Eingang des Briefs = jetzt − (Laufzeit − Restlaufzeit), davor die
-- Verzögerung der Auktionshaus-Post. Beides ist auf Forever noch nicht gemessen (VP-73, im Spiel prüfen) – darum nur
-- tagesgenau zu zeigen und als Schätzung gekennzeichnet (soldEst = true). → Sekunden, true oder nil
History.AH_MAIL_DAYS = 30        -- Laufzeit der Auktionshaus-Post
History.AH_MAIL_DELAY = 3600     -- Verzögerung zwischen Verkauf und Eingang des Briefs
function History.SoldAt(daysLeft, now)
    local left, at = Num(daysLeft), Num(now)
    if not (left and at) or left <= 0 or left > History.AH_MAIL_DAYS then return nil end
    local sold = at - (History.AH_MAIL_DAYS - left) * 86400 - History.AH_MAIL_DELAY
    return math.floor(math.min(sold, at)), true
end

-- Eine Entnahme: money = true (Gold genommen), att = Platz oder "all" (alle Anhänge).
local function Took(index, money, att)
    local h = Core.Mail and Core.Mail.Header(index)
    if not h then return end
    local key = MailKey(index, h)
    local seen = taken[key]
    if not seen then
        seen = { att = {}, count = KeyCounts()[key] or 1 }
        taken[key] = seen
    end
    local slots = {}
    local entry = { dir = "in", who = Plain(h.sender), subj = Plain(h.subject), items = {} }
    if money and not seen.money and h.money > 0 then
        seen.money = true
        entry.money = h.money
    end
    if att then
        local items = ItemsOf(index, att ~= "all" and att or nil)
        for n, item in ipairs(items) do
            local slot = att ~= "all" and att or n
            if not seen.att[slot] then
                seen.att[slot] = true
                slots[#slots + 1] = slot
                entry.items[#entry.items + 1] = item
            end
        end
    end
    if not entry.money and #entry.items == 0 then return end
    if #entry.items == 0 then entry.items = nil end
    History.Add("mail", entry)
    lastTake = entry.items and { at = Now(), mail = entry, key = key, slots = slots } or nil

    -- Auktionshaus-Post: Verkauf (Gold), Kauf und Rückläufer (Gegenstand), überboten (Gold zurück)
    local kind, item = AuctionType(h.subject)
    if not kind then return end
    local inv = Invoice(index)
    local first = entry.items and entry.items[1]
    local a = { type = kind, item = inv and inv.item or item, link = first and first.l, n = (inv and inv.n) or (first and first.c) }
    if kind == "sale" and entry.money then
        a.gross, a.fee, a.deposit, a.net, a.who = inv and inv.bid, inv and inv.fee, inv and inv.deposit, entry.money, inv and inv.who
        a.sold, a.soldEst = History.SoldAt(h.daysLeft, Now())
    elseif kind == "buy" and first then
        a.gross, a.who = inv and inv.bid, inv and inv.who
    elseif (kind == "expired" or kind == "cancelled") and first then
        -- Gegenstand kommt zurück, kein Gold
    elseif kind == "outbid" and entry.money then
        a.net = entry.money
    else
        return
    end
    History.Add("auction", a)
    if lastTake and lastTake.mail == entry then lastTake.auction = a end
end

-- Der Server hat einen Anhang abgelehnt (z. B. Taschen voll): die eben erfasste Entnahme zurücknehmen.
local function TakeFailed()
    local last = lastTake
    lastTake = nil
    if not last or Now() - last.at > 3 then return end
    local seen = taken[last.key]
    if seen then
        for _, slot in ipairs(last.slots) do seen.att[slot] = nil end
    end
    if last.mail.money then
        last.mail.items = nil
    else
        History.Remove("mail", last.mail)
    end
    if last.auction and last.auction.type ~= "sale" and last.auction.type ~= "outbid" then
        History.Remove("auction", last.auction)
    end
end

local function HookMail()
    if type(TakeInboxMoney) == "function" then
        hooksecurefunc("TakeInboxMoney", function(index) ns.Try("History mail", Took, index, true, nil) end)
    end
    if type(TakeInboxItem) == "function" then
        hooksecurefunc("TakeInboxItem", function(index, att) ns.Try("History mail", Took, index, false, att) end)
    end
    if type(AutoLootMailItem) == "function" then
        hooksecurefunc("AutoLootMailItem", function(index) ns.Try("History mail", Took, index, true, "all") end)
    end
end

---------------------------------------------------------------------------
-- Einstell-Verlauf mit Ergebnis (AH-21, Welle 14; Teil A der Ablöse-Analyse, Datenmodell 7)
---------------------------------------------------------------------------
--[[
    Art "posting": jede eigene Einstellung im Auktionshaus, verknüpft mit ihrem Ergebnis.
      Felder: item (itemID), link, n (Menge), unit (Stückpreis: Sofortkauf, ohne Sofortkauf das Gebot), buyout
              (Sofortkauf gesamt = unit × n; fehlt ohne Sofortkauf), bid (Gebot je Stück, nur Einzelstücke), dur (Dauer
              1 = 12 h, 2 = 24 h, 3 = 48 h), comm = true (Ware), ids = { auctionID … } (aus
              AUCTION_HOUSE_AUCTION_CREATED; fehlt das Ereignis, bleibt die Liste leer), res = "sold" | "expired" |
              "cancelled" (nil = offen), rt (Zeit des Ergebnisses), how = "event" (Benachrichtigung bzw.
              AUCTION_CANCELED mit auctionID) | "mail" (Briefe des Auktionshauses, über Gegenstand und Menge),
              soldN (verkaufte Menge laut Briefen), got (Erlös brutto laut Briefen, Summe), net (netto, Summe),
              backN (zurückgekommene Menge laut Briefen), mail = true (mindestens ein Brief zugeordnet),
              h (Auktionshaus „Realm-Fraktion“ beim Einstellen, Core.HouseKey; seit dem Gesamtreview vom 18.11.2026,
              T4-NR6 – ältere Einträge ohne h gehören zum Haus ihres Charakters, Core.CharHouseKey)
    Preise wie in Blizzards Forever-Quelle (Blizzard_AuctionHouseItemSellFrame.lua, GetTotalPrice = Menge × Sofortkauf
    bzw. Gebot): PostItem bekommt Gebot und Sofortkauf je Stück, PostCommodity den Stückpreis.
    Erfasst wird nur zuhörend (hooksecurefunc auf C_AuctionHouse.PostItem/PostCommodity – ezCore ruft nie selbst ein);
    die Vormerkung gilt mit AUCTION_HOUSE_AUCTION_CREATED oder spätestens nach History.POST_CONFIRM Sekunden (wie in
    ezAuction, V-159). AUCTION_HOUSE_SHOW_ERROR (außer Fehlern beim Bieten, History.IsBidError) verwirft die älteste
    Vormerkung. Fragt Blizzard nach (AUCTION_HOUSE_POST_WARNING bzw. _POST_ERROR: der Aufruf hat noch nichts
    eingestellt), fällt die eben gemachte Vormerkung weg; erst „Annehmen“ (ConfirmPostItem/ConfirmPostCommodity, ebenfalls
    nur gehört) merkt neu vor – „Abbrechen“ hinterlässt nichts. Ein Mehrfachverkauf (AUCTION_MULTISELL_START, mehrere
    Einzelstücke auf einmal) bekommt alle folgenden CREATED-Ereignisse, bis seine Menge erreicht ist; bricht er ab
    (AUCTION_MULTISELL_FAILURE), gilt die bis dahin eingestellte Menge.
    Ergebnis: AUCTION_CANCELED(auctionID) » abgebrochen; Benachrichtigung (AUCTION_HOUSE_SHOW_NOTIFICATION bzw.
    _FORMATTED_, Enum.AuctionHouseNotification 4 AuctionSold, 5 AuctionExpired, 1 AuctionRemoved) mit auctionID; sonst
    die Briefe (Art "auction" sale/expired/cancelled). Ein Brief geht an die älteste Einstellung desselben Gegenstands,
    die noch Menge offen hat: zuerst eine, deren Ergebnis schon über das Ereignis kam (gleiches Ergebnis), dann eine
    offene; je gleiche Restmenge vor einer, in die der Brief passt. Teilverkäufe (Waren werden in Teilen verkauft, jeder
    Teil ein Brief) zählen soldN und got hoch; das Ergebnis steht fest, wenn die ganze Menge abgerechnet ist – „verkauft“,
    wenn nichts zurückkam, sonst das Ergebnis des Rückläufers. Das geschätzte Feld „verkauft“ (EC-24) steht weiter am
    Eintrag "auction".

      History.PostStats(gegenstand, opts) → opts.house = „Realm-Fraktion“: nur Einstellungen an diesem Haus (T4-NR6;
                                     ezAuction fragt so für das Haus, an dem es steht), opts.char = nur dieser Charakter;
                                     ohne opts alle Einstellungen aller Charaktere. Rückgabe:
                                     { posted, sold, expired, cancelled, open, rate (verkauft je Ergebnis, 0–1 oder
                                     nil), usual (üblicher Verkaufspreis je Stück: Median aus Erlös je verkauftem Stück,
                                     auch Teilverkäufe; ohne Brief der Stückpreis der verkauften Einstellung), last =
                                     { { res, unit, n, t, rt } … } (neueste zuerst, höchstens History.POST_LAST) }
      History.AuctionMail(charKey) → { seen, list = { { kind = "sale" | "expired" | "cancelled", item, n, price, taken,
                                     t } … } } Auskunft „Auktionspost“: Verkäufe und Rückläufer, die im Briefkasten liegen
                                     (beim letzten Besuch gesehen) oder in dieser Sitzung abgeholt wurden; price = letzter
                                     Preis (Erlös bzw. Stückpreis der Einstellung). A26 (Welle 23b): abgeholte Rückläufer
                                     früherer Sitzungen stehen mit earlier = true dabei, bis der Gegenstand neu eingestellt
                                     ist (höchstens History.TAKEN_DAYS Tage, je Gegenstand der jüngste) – so bleibt die
                                     Marke „zurück“ über das Sitzungsende; Verkäufe nur aus dieser Sitzung
      History.RepostedSince(gegenstand, t, charKey) → seit t neu eingestellt? (Einstell-Verlauf)
      History.FEATURES             Merkmale für Core.Has, z. B. "History.FEATURES.takenUntilPosted"
      History.IsBidError(code)     → true, wenn ein Fehlercode aus AUCTION_HOUSE_SHOW_ERROR nur beim Bieten vorkommt
      History.LinkPosting(eintrag)  intern: einen Auktionshaus-Brief der passenden Einstellung zuordnen (für Prüfungen)
]]
History.POST_CONFIRM = 10      -- Sekunden: so lange wartet eine Einstellung auf AUCTION_HOUSE_AUCTION_CREATED
History.POST_LAST = 5
History.TAKEN_DAYS = 14        -- A26: so lange bleibt ein abgeholter Rückläufer „zurück“, solange er nicht neu eingestellt ist
History.FEATURES = { takenUntilPosted = true, postStatsHouse = true }
History.NOTIFY = { [4] = "sold", [5] = "expired", [1] = "cancelled" }
-- Namen in Blizzards Enum.AuctionHouseError, die nur beim Bieten vorkommen; fehlt ein Name auf dem Client, zählt er nicht
History.BID_ERRORS = { "HigherBid", "BidIncrement", "BidOwn", "MinBid" }
local RESULT_OF = { sale = "sold", expired = "expired", cancelled = "cancelled" }
local SAME_CALL = 1            -- Sekunden: so nah gehören Aufruf und Nachfrage (POST_WARNING) zusammen

local pendingPosts = {}        -- { entry, at } in der Reihenfolge der Aufrufe
local lastPosting              -- für weitere CREATED-Ereignisse derselben Einstellung (mehrere Einzelstücke)
local multiPosting, multiDone  -- laufender Mehrfachverkauf und seine bisher eingestellte Menge (AUCTION_MULTISELL_*)
local multiEnd                 -- Zeit, zu der der Mehrfachverkauf fertig gemeldet wurde (danach noch SAME_CALL Sekunden)
local warnedAt                 -- Nachfrage kam vor dem Hook an: der nächste Aufruf stellt noch nichts ein

local function LocationItem(location)
    local api = rawget(_G, "C_Item")
    if type(api) ~= "table" or location == nil then return nil end
    local id, link
    if type(api.GetItemID) == "function" then
        local ok, value = pcall(api.GetItemID, location)
        id = ok and Num(value) or nil
    end
    if type(api.GetItemLink) == "function" then
        local ok, value = pcall(api.GetItemLink, location)
        link = ok and Plain(value) or nil
        if type(link) ~= "string" or link == "" then link = nil end
    end
    return id or ItemID(link), link
end

local function Confirm(entry, auctionID)
    if auctionID then entry.ids[#entry.ids + 1] = auctionID end
    History.Add("posting", entry)
end

local function Unpend(entry)
    for i, p in ipairs(pendingPosts) do
        if p.entry == entry then
            table.remove(pendingPosts, i)
            return true
        end
    end
    return false
end

function History.IsBidError(code)
    local codes = rawget(_G, "Enum") and Enum.AuctionHouseError
    if Core.IsSecret(code) then return false end
    if code == nil or type(codes) ~= "table" then return false end
    for _, name in ipairs(History.BID_ERRORS) do
        if codes[name] ~= nil and codes[name] == code then return true end
    end
    return false
end

-- Vormerkung aus einem Aufruf von PostItem bzw. PostCommodity (bzw. ConfirmPostItem/ConfirmPostCommodity)
function History.NotePost(location, duration, quantity, bid, buyout, unitPrice)
    local id, link = LocationItem(location)
    quantity = Num(quantity) or 1
    if not id then return nil end
    local entry = { item = id, link = link, n = quantity, dur = Num(duration), ids = {}, h = Core.HouseKey() }
    if unitPrice ~= nil then
        entry.comm, entry.unit = true, Num(unitPrice)
        entry.buyout = entry.unit and entry.unit * quantity or nil
    else
        -- PostItem: Gebot und Sofortkauf je Stück (Blizzards GetTotalPrice = Menge × Sofortkauf bzw. Gebot)
        local each = Num(buyout)
        entry.bid = Num(bid)
        entry.unit = each or entry.bid
        entry.buyout = each and each * quantity or nil
    end
    if warnedAt and Clock() - warnedAt <= SAME_CALL then
        -- Blizzard hat schon nachgefragt: dieser Aufruf stellt nichts ein (erst „Annehmen“)
        warnedAt = nil
        return entry, "confirm"
    end
    local pending = { entry = entry, at = Clock() }
    pendingPosts[#pendingPosts + 1] = pending
    C_Timer.After(History.POST_CONFIRM, function()
        if Unpend(entry) then
            Confirm(entry, nil)
            lastPosting = entry
        end
    end)
    return entry
end

-- Blizzard fragt nach (AUCTION_HOUSE_POST_WARNING) oder meldet einen Einstellfehler mit Fenster
-- (AUCTION_HOUSE_POST_ERROR): der eben gemachte Aufruf hat nichts eingestellt
function History.PostWarning()
    local p = pendingPosts[#pendingPosts]
    if p and Clock() - (p.at or 0) <= SAME_CALL then
        table.remove(pendingPosts)
        if multiPosting == p.entry then multiPosting = nil end
        return p.entry
    end
    warnedAt = Clock()
    return nil
end

-- AUCTION_HOUSE_SHOW_ERROR: die älteste Vormerkung hat der Server abgelehnt (Fehler beim Bieten zählen nicht)
function History.PostFailed(code)
    if History.IsBidError(code) then return nil end
    local p = table.remove(pendingPosts, 1)
    if not p then return nil end
    if multiPosting == p.entry then multiPosting = nil end
    return p.entry
end

-- Mehrfachverkauf: die jüngste Vormerkung eines Einzelstücks (PostItem) bekommt die folgenden CREATED-Ereignisse
function History.MultisellStart()
    multiPosting, multiDone, multiEnd = nil, 0, nil
    for i = #pendingPosts, 1, -1 do
        local e = pendingPosts[i].entry
        if not e.comm then
            multiPosting = e
            return e
        end
    end
    return nil
end

function History.MultisellUpdate(posted, total)
    if not (multiPosting and Num(posted)) then return end
    multiDone = Num(posted)
    if Num(total) and multiDone >= Num(total) then multiEnd = Clock() end
end

-- Abgebrochen: es gilt die bis dahin eingestellte Menge; ohne eine eingestellte Auktion fällt die Vormerkung weg
function History.MultisellFailed()
    local e = multiPosting
    multiPosting = nil
    if not e then return nil end
    local done = math.max(Num(multiDone) or 0, #e.ids)
    if done <= 0 then
        Unpend(e)
        return nil
    end
    e.n = done
    if e.unit and e.buyout then e.buyout = e.unit * done end
    return e
end

function History.PostCreated(auctionID)
    auctionID = Num(auctionID)
    local m = multiPosting
    if m and multiEnd and Clock() - multiEnd > SAME_CALL then
        multiPosting, m = nil, nil   -- fertig gemeldet, aber nicht jede Auktion kam als CREATED
    end
    if m and #m.ids < (Num(m.n) or 1) then
        -- laufender Mehrfachverkauf: je Auktion ein CREATED, alle gehören zu dieser Einstellung
        if Unpend(m) then
            Confirm(m, auctionID)
            lastPosting = m
        elseif auctionID then
            m.ids[#m.ids + 1] = auctionID
        end
        if #m.ids >= (Num(m.n) or 1) then multiPosting = nil end
        return m
    end
    local p = table.remove(pendingPosts, 1)
    if p then
        Confirm(p.entry, auctionID)
        lastPosting = p.entry
        return p.entry
    end
    -- weitere Auktion derselben Einstellung (mehrere Einzelstücke auf einmal)
    local e = lastPosting
    if e and auctionID and not e.comm and #(e.ids or {}) < (Num(e.n) or 1) then
        e.ids[#e.ids + 1] = auctionID
        return e
    end
    return nil
end

local function ByAuction(auctionID)
    auctionID = Num(auctionID)
    if not auctionID then return nil end
    for _, e in ipairs(History.List("posting", { char = Core.charKey, limit = 300 })) do
        for _, id in ipairs(type(e.ids) == "table" and e.ids or {}) do
            if id == auctionID then return e end
        end
    end
    return nil
end

local function Resolve(e, res, how)
    if not e or e.res then return false end
    e.res, e.rt, e.how = res, Now(), how
    Core.Fire("HISTORY_POSTING", e)
    return true
end

function History.PostResult(auctionID, res)
    local e = ByAuction(auctionID)
    if not e then return nil end
    Resolve(e, res, "event")
    return e
end

function History.OnNotification(kind, auctionID)
    local res = History.NOTIFY[Num(kind)]
    if not res then return nil end
    return History.PostResult(auctionID, res)
end

-- Gegenstand eines Auktions-Eintrags: aus dem Link, sonst über den Namen (Rechnung nennt nur ihn)
local function AuctionItem(a)
    local id = ItemID(a.link)
    if not id and type(a.item) == "string" then
        local K = Core.Knowledge
        id = K and K.ItemIDByName and Num(K.ItemIDByName(a.item)) or nil
    end
    return id
end

-- Menge einer Einstellung, für die noch kein Brief kam
local function Rest(e)
    return (Num(e.n) or 1) - (Num(e.soldN) or 0) - (Num(e.backN) or 0)
end

-- Passt der Brief (Ergebnis res, Menge n) im Schritt step zur Einstellung e? Schritte 1–2: Ergebnis schon über das
-- Ereignis gekommen (gleiches Ergebnis), 3–4: offen; ungerade: gleiche Restmenge, gerade: der Brief passt hinein
local function Fits(e, item, res, n, t, step)
    if e.item ~= item or (e.t or 0) > t then return false end
    local rest = Rest(e)
    if rest <= 0 then return false end
    if step <= 2 then
        if not (e.res == res and e.how == "event") then return false end
    elseif e.res ~= nil then
        return false
    end
    if n == nil then return true end
    if step % 2 == 1 then return rest == n end
    return n <= rest
end

function History.LinkPosting(a)
    if type(a) ~= "table" then return nil end
    local res = RESULT_OF[a.type]
    if not res then return nil end
    local item = AuctionItem(a)
    local n = Num(a.n)
    local t = a.t or Now()
    local best
    local list = History.List("posting", { char = a.c or Core.charKey, limit = 500 })
    for step = 1, 4 do
        for i = #list, 1, -1 do   -- älteste zuerst
            if Fits(list[i], item, res, n, t, step) then
                best = list[i]
                break
            end
        end
        if best then break end
    end
    if not best then return nil end
    local count = n or Rest(best)
    if res == "sold" then
        best.soldN = (Num(best.soldN) or 0) + count
        if Num(a.gross) then best.got = (Num(best.got) or 0) + Num(a.gross) end
        if Num(a.net) then best.net = (Num(best.net) or 0) + Num(a.net) end
    else
        best.backN = (Num(best.backN) or 0) + count
        best.back = res
    end
    best.mail = true
    if best.res == nil and Rest(best) <= 0 then
        Resolve(best, (Num(best.backN) or 0) > 0 and (best.back or res) or "sold", "mail")
    end
    return best
end

-- Median: eine Fassung für alle (Core.Median, Util.lua, Welle 15); gerade Anzahl jetzt kaufmännisch gerundet wie in
-- Prices.lua statt abgerundet
local Median = Core.Median

-- Erlös je verkauftem Stück: aus den Briefen (auch Teilverkäufe), sonst der Stückpreis einer verkauften Einstellung
local function SoldUnit(e)
    local got, soldN = Num(e.got), Num(e.soldN)
    if got and soldN and soldN > 0 then return math.floor(got / soldN) end
    if e.res ~= "sold" then return nil end
    local n = Num(e.n) or 1
    if got and n > 0 then return math.floor(got / n) end
    return Num(e.unit)
end

-- Haus einer Einstellung: gemerkt (h) oder, bei Einträgen vor T4-NR6, das Haus ihres Charakters (nil, wenn unbekannt).
local function PostHouse(e)
    local h = type(e.h) == "string" and e.h or Core.CharHouseKey(e.c)
    return h and h:lower() or nil
end
History.PostHouse = PostHouse

function History.PostStats(item, opts)
    item = Num(item) or ItemID(item)
    local out = { posted = 0, sold = 0, expired = 0, cancelled = 0, open = 0, last = {} }
    if not item then return out end
    opts = type(opts) == "table" and opts or {}
    local house = type(opts.house) == "string" and opts.house:lower() or nil
    local prices = {}
    local filter = { char = opts.char, match = function(e) return e.item == item and (house == nil or PostHouse(e) == house) end }
    for _, e in ipairs(History.List("posting", filter)) do
        out.posted = out.posted + 1
        if e.res then out[e.res] = (out[e.res] or 0) + 1 else out.open = out.open + 1 end
        local unit = SoldUnit(e)
        if unit then prices[#prices + 1] = unit end
        if e.res and #out.last < History.POST_LAST then
            out.last[#out.last + 1] = { res = e.res, unit = Num(e.unit), n = Num(e.n), t = e.t, rt = e.rt }
        end
    end
    local done = out.sold + out.expired + out.cancelled
    out.rate = done > 0 and out.sold / done or nil
    out.usual = Median(prices)
    return out
end

-- Auskunft „Auktionspost“: beim Besuch des Briefkastens die Auktionshaus-Briefe merken (je Charakter), dazu das in
-- dieser Sitzung Abgeholte (aus dem Verlauf „auction“)
-- Letzter Stückpreis einer Einstellung DIESES Charakters (charKey bzw. der gespielte; T4-NR6 – vorher irgendeines
-- Charakters auf irgendeinem Haus)
local function LastUnit(item, charKey)
    for _, e in ipairs(History.List("posting", { char = charKey or Core.charKey, match = function(e) return e.item == item end, limit = 1 })) do
        return Num(e.unit)
    end
    return nil
end

function History.ScanAuctionMail()
    local me = Core.me
    if not (me and GetInboxNumItems) then return nil end
    local list = {}
    local okN, count = pcall(GetInboxNumItems)
    for index = 1, (okN and Num(count)) or 0 do
        local h = Core.Mail and Core.Mail.Header(index)
        local kind, name
        if h then kind, name = AuctionType(h.subject) end
        if kind == "sale" or kind == "expired" or kind == "cancelled" then
            local inv = Invoice(index)
            local first = (kind ~= "sale") and ItemsOf(index, 1)[1] or nil
            local item = first and first.i or AuctionItem({ item = inv and inv.item or name })
            local n = (inv and inv.n) or (first and first.c) or nil
            local price = kind == "sale" and (inv and inv.bid or (h.money > 0 and h.money or nil)) or (item and LastUnit(item))
            list[#list + 1] = { kind = kind, item = item, n = n, price = price }
        end
    end
    me.ahMail = { seen = Now(), list = list }
    return me.ahMail
end

function History.AuctionMail(charKey)
    local key = charKey or Core.charKey
    local char = Core.Char and Core.Char(key) or (key == Core.charKey and Core.me) or nil
    local stored = type(char) == "table" and type(char.ahMail) == "table" and char.ahMail or nil
    local out = { seen = stored and stored.seen or nil, list = {} }
    for _, e in ipairs(stored and stored.list or {}) do
        out.list[#out.list + 1] = { kind = e.kind, item = e.item, n = e.n, price = e.price }
    end
    local start = Core.Session and Core.Session.Start and Core.Session.Start() or nil
    if not (start and key == Core.charKey) then start = nil end
    -- A26 (Welle 23b): Abgeholte Rückläufer aus früheren Sitzungen bleiben „zurück“, bis der Gegenstand neu eingestellt
    -- wird (Einstell-Verlauf „posting“ desselben Charakters), höchstens History.TAKEN_DAYS Tage; je Gegenstand der
    -- jüngste. Verkäufe zählen wie bisher nur aus dieser Sitzung. Kennzeichen earlier = true.
    local earlierSeen = {}
    for _, a in ipairs(History.List("auction", { char = key, since = History.Since(History.TAKEN_DAYS) })) do
        if RESULT_OF[a.type] then
            local item = AuctionItem(a)
            local inSession = start ~= nil and (Num(a.t) or 0) >= start
            local earlier = not inSession and a.type ~= "sale" and item ~= nil and not earlierSeen[item]
            if earlier then
                earlierSeen[item] = true
                earlier = not History.RepostedSince(item, a.t, key)
            end
            if inSession or earlier then
                out.list[#out.list + 1] = { kind = a.type, item = item, n = Num(a.n), taken = true, t = a.t,
                    price = a.type == "sale" and Num(a.gross or a.net) or (item and LastUnit(item, key)),
                    earlier = earlier or nil }
            end
        end
    end
    return out
end

-- Wurde der Gegenstand seit dem Zeitpunkt t (wieder) eingestellt? (Einstell-Verlauf, Charakter charKey bzw. dieser)
function History.RepostedSince(item, t, charKey)
    item = Num(item) or ItemID(item)
    if not item then return false end
    return #History.List("posting", { char = charKey or Core.charKey, since = Num(t) or 0, limit = 1,
        match = function(e) return e.item == item end }) > 0
end

local function HookPosting()
    local api = rawget(_G, "C_AuctionHouse")
    if type(api) ~= "table" then return end
    -- ConfirmPost*: „Annehmen“ nach Blizzards Nachfrage (AUCTION_HOUSE_POST_WARNING) – erst das stellt ein
    for _, name in ipairs({ "PostItem", "ConfirmPostItem" }) do
        if type(api[name]) == "function" then
            hooksecurefunc(api, name, function(location, duration, quantity, bid, buyout)
                ns.Try("History posting", History.NotePost, location, duration, quantity, bid, buyout, nil)
            end)
        end
    end
    for _, name in ipairs({ "PostCommodity", "ConfirmPostCommodity" }) do
        if type(api[name]) == "function" then
            hooksecurefunc(api, name, function(location, duration, quantity, unitPrice)
                ns.Try("History posting", History.NotePost, location, duration, quantity, nil, nil, unitPrice)
            end)
        end
    end
end

local function OnMailSent(mail)
    if type(mail) ~= "table" then return end
    local items = {}
    for _, e in ipairs(mail.items or {}) do items[#items + 1] = { i = e.i, l = e.l, c = e.c } end
    History.Add("mail", { dir = "out", who = mail.to, subj = mail.subject, money = Num(mail.money) or 0,
        cod = Num(mail.cod) or 0, items = #items > 0 and items or nil })
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

for _, pair in ipairs({
    { "loot", "LOOT_OPENED", "LOOT_CLOSED" }, { "mail", "MAIL_SHOW", "MAIL_CLOSED" },
    { "auction", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }, { "merchant", "MERCHANT_SHOW", "MERCHANT_CLOSED" },
    { "trainer", "TRAINER_SHOW", "TRAINER_CLOSED" }, { "taxi", "TAXIMAP_OPENED", "TAXIMAP_CLOSED" },
    { "trade", "TRADE_SHOW", "TRADE_CLOSED" }, { "guildbank", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED" },
    { "quest", "QUEST_COMPLETE", "QUEST_FINISHED" }, { "barber", "BARBER_SHOP_OPEN", "BARBER_SHOP_CLOSE" },
}) do
    local name = pair[1]
    ns.On(pair[2], function() Open(name) end)
    ns.On(pair[3], function() Close(name) end)
end

-- Welle 23c (A69): zuerst LOOT_READY (Fenster samt Gold-Zusammenhang), LOOT_OPENED als Rückfall
ns.On("LOOT_READY", function()
    Open("loot")
    SnapshotLoot()
end)
ns.On("LOOT_OPENED", SnapshotLoot)
ns.On("LOOT_SLOT_CLEARED", LootSlotCleared)
ns.On("LOOT_CLOSED", function()
    loot = nil
    lootOpen = false
end)
ns.On("CHAT_MSG_LOOT", OnLootMessage)
ns.On("PLAYER_MONEY", OnMoney)
ns.On("MAIL_CLOSED", function() taken, lastTake = {}, nil end)
ns.On("MAIL_INBOX_UPDATE", function() ForgetGoneMail() end)
ns.On("MAIL_FAILED", function() TakeFailed() end)
Core.Listen("MAIL_SENT", OnMailSent)
-- Einstell-Verlauf (AH-21)
ns.On("AUCTION_HOUSE_AUCTION_CREATED", function(_, auctionID) ns.Try("History posting", History.PostCreated, auctionID) end)
ns.On("AUCTION_CANCELED", function(_, auctionID) ns.Try("History posting", History.PostResult, auctionID, "cancelled") end)
ns.On("AUCTION_HOUSE_SHOW_ERROR", function(_, code) ns.Try("History posting", History.PostFailed, code) end)
ns.On("AUCTION_HOUSE_POST_WARNING", function() ns.Try("History posting", History.PostWarning) end)
ns.On("AUCTION_HOUSE_POST_ERROR", function() ns.Try("History posting", History.PostWarning) end)
ns.On("AUCTION_MULTISELL_START", function() ns.Try("History posting", History.MultisellStart) end)
ns.On("AUCTION_MULTISELL_UPDATE", function(_, posted, total) ns.Try("History posting", History.MultisellUpdate, posted, total) end)
ns.On("AUCTION_MULTISELL_FAILURE", function() ns.Try("History posting", History.MultisellFailed) end)
ns.On("AUCTION_HOUSE_CLOSED", function() multiPosting, warnedAt = nil, nil end)
local function OnNotification(_, kind, ...)
    -- auctionID ist die letzte Zahl nach der Art (FORMATTED: Art, Text, auctionID)
    local id
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if not Core.IsSecret(v) and Num(v) then id = Num(v) end
    end
    if id then ns.Try("History posting", History.OnNotification, kind, id) end
end
ns.On("AUCTION_HOUSE_SHOW_NOTIFICATION", OnNotification)
ns.On("AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION", OnNotification)
Core.Listen("HISTORY_ADDED", function(kind, entry)
    if kind == "auction" then ns.Try("History posting", History.LinkPosting, entry) end
end, "ezCore.History")
Core.Listen("MAILBOX_SCANNED", function() ns.Try("History posting", History.ScanAuctionMail) end, "ezCore.History")
Core.RegisterMessage("HISTORY_POSTING", "History.lua", "Eine eigene Einstellung im Auktionshaus hat ihr Ergebnis (verkauft, abgelaufen, abgebrochen).", "eintrag")
---------------------------------------------------------------------------
-- Sitzung (W-13, VP-18): die EINE Sitzung der ezCollection
---------------------------------------------------------------------------
--[[
    Core.Session – Beginn, Startgold, Einnahmen und Ausgaben seit dem Einloggen; übersteht ein /reload: Liegt das
    letzte Ausloggen (PLAYER_LOGOUT kommt auch beim Neuladen) höchstens Session.GAP (60) Sekunden zurück, läuft sie
    weiter. Die Summe aus dem Verlauf taugt dafür nicht (höchstens 2.000 Einträge). Gespeichert im Charakter-Datensatz
    (me.coreSession); ezPanels eigene Sitzung (me.session) bleibt, bis ezPanel umstellt und nur noch hier liest.

      Session.Get()          → { start, money, earned, spent, data } (nur lesen) oder nil vor dem Anmelden
      Session.Start()        → time() des Beginns;  Session.StartMoney() → Gold beim Beginn
      Session.Earned(), Session.Spent() → Kupfer;  Session.Net() → Einnahmen minus Ausgaben
      Session.Duration()     → Sekunden seit Beginn
      Session.Data(owner)    → Tabelle eines Moduls für eigene Zähler dieser Sitzung (Ruf, XP, Sammeln – SAM-09);
                               leert sich mit der Sitzung. Kein zweiter Sitzungsbegriff in den Modulen.
      Session.Reset()        → neue Sitzung („Sitzung zurücksetzen“); Nachricht SESSION_RESET (sitzung)
      Session.IsContinued()  → true, wenn diese Sitzung ein /reload überstanden hat
]]

local Session = {}
Core.Session = Session
Session.GAP = 60
local session, continued, sessionMoney

-- Ausgangsstand für Gold-Differenzen: nie eine 0, die der Client früh beim Laden liefert (Characters.lua,
-- Chars.MoneyBaseline; Gegenprüfung des Pakets „Taint, Realm und Gold“ vom 22.11.2026 – sonst zählte die erste
-- Gold-Änderung das ganze Gold als Einnahme)
local function Baseline()
    local chars = Core.Characters
    if chars and chars.MoneyBaseline then return chars.MoneyBaseline() end
    return GetMoney and Num(GetMoney()) or nil
end

local function NewSession(me)
    session = { start = Now(), money = Baseline() or 0, earned = 0, spent = 0, data = {} }
    me.coreSession = session
    continued = false
    return session
end

function Session.Get() return session end
function Session.Start() return session and session.start or nil end
function Session.StartMoney() return session and session.money or nil end
function Session.Earned() return session and Num(session.earned) or 0 end
function Session.Spent() return session and Num(session.spent) or 0 end
function Session.Net() return Session.Earned() - Session.Spent() end
function Session.IsContinued() return continued == true end

function Session.Duration()
    local start = Session.Start()
    return start and math.max(0, Now() - start) or 0
end

function Session.Data(owner)
    if not session or type(owner) ~= "string" or owner == "" then return nil end
    if type(session.data) ~= "table" then session.data = {} end
    local t = session.data[owner]
    if type(t) ~= "table" then
        t = {}
        session.data[owner] = t
    end
    return t
end

function Session.Reset()
    local me = Core.me
    if not me then return nil end
    NewSession(me)
    sessionMoney = Num(session.money)
    Core.Fire("SESSION_RESET", session)
    return session
end

-- Beim Anmelden: weiterlaufen oder neu (dieselbe Regel wie bisher in ezPanel)
function Session.Begin()
    local me = Core.me
    if not me then return nil end
    local last = Num(Core.previousLastSeen)
    local s = me.coreSession
    if type(s) == "table" and Num(s.start) and last and Now() - last <= Session.GAP then
        session, continued = s, true
        s.earned, s.spent = Num(s.earned) or 0, Num(s.spent) or 0
        if type(s.data) ~= "table" then s.data = {} end
    else
        NewSession(me)
    end
    sessionMoney = Baseline()
    return session
end

local function SessionMoney()
    if not session then return end
    local money = Core.Characters.EventMoney()
    if not money then return end
    local before = sessionMoney
    sessionMoney = money
    if not before or money == before then return end
    if money > before then
        session.earned = (Num(session.earned) or 0) + (money - before)
    else
        session.spent = (Num(session.spent) or 0) + (before - money)
    end
end

ns.On("PLAYER_MONEY", SessionMoney)

Core.Listen("CHARS_READY", function()
    lastMoney = Baseline()
    HookMail()
    HookPosting()
    Session.Begin()
end)
