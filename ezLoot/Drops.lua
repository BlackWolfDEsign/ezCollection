local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Beute im Tooltip von Gegnern und NPCs (Wunsch des Nutzers 13.11.2026: „nsc/mobs … ihren loot im tooltip“).
    Forever hat keine Beutetabellen. Regel „Datenquellen“ (Nutzer, 13.11.2026): zuerst der Client, dann die Datenbank
    eines installierten Addons, dann selbst Gesammeltes; jede Zeile nennt ihre Quelle; kein leerer Tooltip ohne
    Erklärung. Daraus der Aufbau des Abschnitts (Entscheidung des Nutzers 14.11.2026, LOOT-01: zuerst das selbst
    Gezählte, dann QuestieDB ohne Chance – die Reihenfolge der Quellen legt ezCore fest, Core.Sources.ORDER; die
    Anbindung von Tnny's Mob Loot ist seit Welle 16 entfernt, RB-01):
      „Mögliche Beute laut <Quelle>“  aus ezCores Quellen (Core.Sources.LootOf; ezLoot fragt nur, per pcall, und
                                kopiert nichts) – höchstens 3 Gegenstände, mit Shift 8; rechts die Chance, wenn die
                                Quelle eine nennt – über der eigenen Zeile. Kennt die Quelle keine Chance (QuestieDB),
                                heißt der Kopf „Kann fallen lassen (laut Questie, ohne Chance)“, Quest-Gegenstände zuerst
      „Beute bei dir: n× geplündert“  was du und deine Twinks bei diesem NPC geplündert haben, je Gegenstand
                                „k× bei n geplünderten“ (DG-04): eine Zählung, keine Dropchance. Gezählt von ezCores
                                Entdecker-Datenbank (Core.Drops.Of über History.LootOfNpc().drops, Nenner
                                Core.Drops.Denominator – ohne V-008), ältere ezCore-Fassungen: der Beute-Verlauf
      „noch nichts – wächst …“  Hinweis statt nichts, nur bei angreifbaren Gegnern (Schalter „npcLootHint“); mit Shift
                                dazu, warum keine Quelle etwas nennt (Core.Sources.Hint)
    Zeigt ein anderes Addon selbst Beute im Gegner-Tooltip (ezCore.WhoHandles("unitLoot"), etwa Tnny's Mob Loot mit
    eingeschalteter Liste beim Überfahren – nur Rücksicht, nichts daraus gelesen), bleibt von ezLoot nur die eigene
    Zeile „bei dir n×“ – braucht das Addon
    dafür eine Taste (Core.OtherAddOnKeyHeld, LOOT-08), nur solange sie gehalten wird. Die volle Liste steht als
    Ansicht „Mögliche Beute“ im Beute-Verlauf (History.lua).
    Die Rechnung liegt in ezCore (Core.History.LootOfNpc und Core.Drops; dieselbe Rechnung nutzt ezCore umgekehrt
    für „Bezugsquellen“). ezLoot sortiert und zeigt nur.

      Drops.Summarize(npc) → { name, loots, items = { { id, link, q, n, times } … }, money, moneyLoots, npc,
                             moneyAvg, counted, what } – aus der Zählung (counted = true, what = "loots" | "deaths"
                             je Nenner) oder, ohne sie, aus dem Beute-Verlauf (ezCores LootOfNpc)
      Drops.Get(npc)       → dieselbe Zusammenfassung, zwischengespeichert (neu bei HISTORY_ADDED/REMOVED dieses NPC,
                             nach „Verlauf leeren“: HISTORY_CLEARED, und bei neuem Stand der Datenbank: DbVersion;
                             höchstens CACHE_MAX Gegner)
      Drops.Sorted(s, rareFirst) → Gegenstände: Quest zuerst, dann häufigste (bei Elite und Bossen: seltenste Qualität)
      Drops.Lines(s, long, rareFirst) → eigene Zeilen { left, right, r, g, b } (ohne Oberfläche, gut prüfbar)
      Drops.SourceLoot(npc, level) / GetSources(npc, level) → geprüfte Kopie der Antwort von Core.Sources.LootOf
                                              { npc, source, sourceKey, label, own, items = { { id, chance,
                                                quest } … } } | nil
      Drops.SortedSource(items, rareFirst)    → Quest zuerst, dann Chance
      Drops.PossibleLines(b, long, rareFirst) → Zeilen „Mögliche Beute laut <Quelle>“ (früherer Name SourceLines)
      Drops.SourceHint() / ActiveSources()    → Satz ohne Quelle / Namen der laufenden Quellen
      Drops.Listed(b)                         → true: die Quelle nennt Gegenstände ohne Chance (QuestieDB)
      Drops.AtlasLabel() / OpenAtlas(npc)     → AtlasLoot läuft: Name / nur sein Fenster öffnen (DG-49; AtlasLoot
                                                kennt keinen Befehl für einen bestimmten Boss)
      Drops.OtherShowing()                    → Name des Addons, das gerade selbst Beute im Gegner-Tooltip zeigt
      Drops.TooltipLines(s, opts)             → alle Zeilen des Abschnitts (opts: long, rareFirst, other, possible,
                                                hint, sourceHint, worth)
      Drops.Worth(npc) / WorthLines(npc, long) → Wert je Tötung aus ezCores Rechnung (V2, Welle 24; Schalter
                                                „npcWorth“), unter der eigenen Beute
      Drops.SkinLines(unit) / AddSkinSection   → „Kürschnern: ab …“ aus ezCore (Core.Gathering.SkinLines; Welle 27,
                                                F4 b; Schalter „npcSkin“), eigener Abschnitt „ezLoot.skin“

    Einheiten-Tooltip über ezCore.Tooltip.AddUnitSection („ezLoot.drops“); IsSecret vor jedem Vergleich.
    Mit Shift mehr Zeilen; wechselt Shift, zeichnet ezLoot den Tooltip neu (RefreshData).
]]

local D = {}
ns.Drops = D

D.SHORT_ITEMS = 2           -- Gegenstände ohne Shift
D.LONG_ITEMS = 5            -- mit Shift (höchstens fünf)
D.CACHE_TIME = 60           -- Sekunden; danach neu rechnen (Sicherheitsnetz; Änderungen meldet ezCore, siehe unten)
D.QUEST_CLASS = 12          -- Enum.ItemClass.Questitem
D.QUEST_BIND = 4            -- bindType: Questgegenstand
D.RARE_FIRST = { worldboss = true, elite = true, rareelite = true }   -- Schlüssel von Core.UnitRank

local Num, Plain = Core.Num, Core.Plain

local function NpcOf(e)
    local src = type(e) == "table" and e.src
    return type(src) == "table" and Num(src.npc) or nil
end
D.NpcOf = NpcOf

---------------------------------------------------------------------------
-- Rechnung (ohne Oberfläche)
---------------------------------------------------------------------------

-- Zählung der Entdecker-Datenbank (History.LootOfNpc().drops = Core.Drops.Of("loot", npc): jede Leiche einmal,
-- Gruppenbeute seit ezCore Welle 23c im Nenner, ohne V-008) in die Form der Zusammenfassung übernehmen. Nenner und seine Art kommen
-- von ezCore (Core.Drops.Denominator: „geplünderte“ bzw. „getötete“). Fehlt die Zählung, ist sie leer oder
-- unstimmig, oder sammelt die Datenbank gerade nicht (D.DbState): false, dann bleibt der Beute-Verlauf. Die Zahlen
-- des Verlaufs bleiben unter s.log erhalten.
-- Zählt ezCores Entdecker-Datenbank gerade? → "on" | "old" (diese ezCore-Fassung hat Core.Drops nicht) | "off"
-- (Schalter „Datenbank: Erlebtes sammeln“ aus oder Träger verloren: DB.Collecting) | "wait" (noch nicht geladen:
-- DB.Ready). Sammelt sie nicht, wüchse nur der Beute-Verlauf weiter – die alte Zählung bliebe stehen. Fehlt eine
-- Abfrage (ältere Fassung), gilt sie als erfüllt; ein Fehler darin als „nicht“.
function D.DbState()
    local DR, DB = Core.Drops, Core.DB
    if type(DR) ~= "table" or type(DR.Of) ~= "function" or type(DR.Denominator) ~= "function" then return "old" end
    if type(DB) == "table" and type(DB.Ready) == "function" then
        local ok, ready = pcall(DB.Ready)
        if not ok or ready ~= true then return "wait" end
    end
    if type(DB) == "table" and type(DB.Collecting) == "function" then
        local ok, on = pcall(DB.Collecting)
        if not ok or on ~= true then return "off" end
    end
    return "on"
end

function D.FromCounts(s)
    local d, DR = s.drops, Core.Drops
    if ns.IsSecret(d) or type(d) ~= "table" or ns.IsSecret(d.items) or type(d.items) ~= "table"
        or D.DbState() ~= "on" then
        return false
    end
    local ok, n, what = pcall(DR.Denominator, d)
    n = ok and Num(n) or nil
    if not n or n < 1 then return false end
    what = (not ns.IsSecret(what) and what == "deaths") and "deaths" or "loots"
    -- Gruppenfenster: Seit ezCore Welle 23c (A64, Core.FEATURES.dropsPartyCounted) zählt ein Fenster in der Gruppe auch
    -- im Nenner (cnt); „k× bei n“ stimmt dann ohne Tode, der Rückfall entfällt. Altbestand trägt party ohne cnt: mehr
    -- Gruppenfenster als gezählte Fenster heißt unstimmig, ebenso Gruppenbeute ohne Tode bei einer älteren
    -- ezCore-Fassung (dort stand das Fenster nur in party). Unstimmig – dazu ein Zähler über dem Nenner (unten) –
    -- heißt: Beute-Verlauf.
    local party = Num(d.party) or 0
    local partyCounted = type(Core.Has) == "function" and Core.Has("dropsPartyCounted") == true
    if what ~= "deaths" and party > 0 and (not partyCounted or party > n) then return false end
    local money = type(d.money) == "table" and d.money or nil
    if money and (Num(money.cnt) or 0) > n then return false end
    local fromLog, items = {}, {}
    for _, item in ipairs(s.items) do if item.id then fromLog[item.id] = item end end
    for id, entry in pairs(d.items) do
        id = Num(id)
        local found = type(entry) == "table" and Num(entry.f) or nil
        if found and found > n then return false end
        if id and id > 0 and found and found > 0 then
            local log = fromLog[id]
            items[#items + 1] = { id = id, n = Num(entry.s) or found, times = found,
                q = log and log.q or D.ItemQuality(id), link = log and log.link }
        end
    end
    table.sort(items, function(a, b)
        if a.times ~= b.times then return a.times > b.times end
        if (a.q or 0) ~= (b.q or 0) then return (a.q or 0) > (b.q or 0) end
        return a.id < b.id
    end)
    s.log = { loots = s.loots, items = s.items, money = s.money, moneyLoots = s.moneyLoots }
    s.loots, s.items, s.counted, s.what = n, items, true, what
    s.money, s.moneyLoots = money and Num(money.sum) or 0, money and Num(money.cnt) or 0
    return true
end

-- Beute dieses NPC aus ezCore (eine Rechnung für ezLoot und ezCores „Bezugsquellen“). Ohne ezCore-Fassung: leer.
function D.Summarize(npc)
    npc = Num(npc)
    local history, s = Core.History, nil
    if npc and type(history) == "table" and type(history.LootOfNpc) == "function" then
        local ok, result = pcall(history.LootOfNpc, npc)
        if ok and type(result) == "table" then s = result end
    end
    s = s or {}
    s.npc = npc
    s.loots, s.money, s.moneyLoots = Num(s.loots) or 0, Num(s.money) or 0, Num(s.moneyLoots) or 0
    s.items = type(s.items) == "table" and s.items or {}
    for _, item in ipairs(s.items) do
        item.link, item.q = Plain(item.link), Num(item.q)
        item.n, item.times = Num(item.n) or 0, Num(item.times) or 0
    end
    s.counted, s.what = false, "loots"
    D.FromCounts(s)
    s.moneyAvg = s.loots > 0 and math.floor(s.money / s.loots + 0.5) or 0
    return s
end

-- Questgegenstand? Aus dem Item-Wissen (Klasse „Quest“ oder „Questgegenstand“-Bindung); unbekannt: nein.
function D.IsQuest(item)
    local knowledge = Core.Knowledge
    if not (item and item.id and type(knowledge) == "table" and type(knowledge.Get) == "function") then return false end
    local ok, facts = pcall(knowledge.Get, item.id)
    if not ok or type(facts) ~= "table" then return false end
    return Num(facts.classID) == D.QUEST_CLASS or Num(facts.bindType) == D.QUEST_BIND or facts.questbind == true
end

function D.Sorted(s, rareFirst)
    local items = {}
    for i, item in ipairs(s.items) do
        items[i] = item
        item.quest = D.IsQuest(item)
    end
    table.sort(items, function(a, b)
        if a.quest ~= b.quest then return a.quest end
        local qa, qb = a.q or 0, b.q or 0
        if rareFirst and qa ~= qb then return qa > qb end
        if a.times ~= b.times then return a.times > b.times end
        if qa ~= qb then return qa > qb end
        if a.n ~= b.n then return a.n > b.n end
        return (a.id or 0) < (b.id or 0)
    end)
    return items
end

-- Name in der Farbe der Qualität (Name zur itemID, sonst der Text des Links).
function D.ItemText(item)
    local name = item.id and Core.ItemNameByID(item.id)
    if not name and type(item.link) == "string" then
        name = item.link:match("%[(.-)%]") or Core.StripColors(item.link)
    end
    local text = Core.QualityHex(item.q) .. (name or "?") .. "|r"
    if item.quest then text = text .. " (" .. L.DROPS_QUEST .. ")" end
    return text
end

-- Zeile eines Gegenstands im Tooltip: sein Symbol im Text davor (Wunsch des Nutzers vom 18.11.2026, „tooltip des
-- drops vllt mit den item icons?“), über ezCores einen Helfer Core.ItemIconText; ohne Symbol nur der Name. Die
-- Zeilen der Beute-Ansicht (History.lua) zeigen ihr Symbol selbst und nehmen weiter D.ItemText.
function D.TipItemText(item)
    local text = D.ItemText(item)
    if type(Core.ItemIconText) ~= "function" then return text end
    return Core.ItemIconText(item.id or item.link, text)
end

-- Farben aus ezCores Rollen statt eigener Zahlen (T9-6, Gegenprüfung D2): Kopf gold („normal“), Angaben weiß
-- („highlight“), Quellen, Hinweise und Chancen grau („gray“, dasselbe Grau wie Core.Grey)
local function RoleColor(role)
    local Style = Core.Style
    local r, g, b
    if type(Style) == "table" and type(Style.Color) == "function" then r, g, b = Style.Color(role) end
    if type(r) ~= "number" then return { 1, 1, 1 } end
    return { r, g, b }
end
local GOLD, GREY, WHITE = RoleColor("normal"), RoleColor("gray"), RoleColor("highlight")
D.GREY = GREY

local function Line(left, right, color)
    color = color or WHITE
    return { left = left, right = right, r = color[1], g = color[2], b = color[3] }
end

-- Kopfzeile der eigenen Beute: „Beute bei dir: n× geplündert“ (Nenner geplünderte Leichen) bzw. „n× getötet“, wenn
-- ezCores Nenner die Tode sind (Core.Drops.Denominator).
function D.HeadText(s)
    return (s.what == "deaths" and L.DROPS_HEAD_DEATHS or L.DROPS_HEAD):format(s.loots)
end

-- „k× bei n geplünderten“ (DG-04): in wie vielen der gezählten Leichen der Gegenstand lag – eine Zählung, keine
-- Dropchance; mit Shift dazu die Menge („zusammen m“).
function D.CountText(item, s, long)
    local times = math.min(item.times or 0, s.loots)
    local text = (s.what == "deaths" and L.DROPS_COUNT_DEATHS or L.DROPS_COUNT):format(times, s.loots)
    if long and (item.n or 0) > times then text = L.DROPS_AMOUNT:format(text, item.n) end
    return text
end

function D.Lines(s, long, rareFirst)
    local lines = {}
    if type(s) ~= "table" or (s.loots or 0) < 1 then return lines end
    local head = D.HeadText(s)
    local avg = s.money > 0 and L.DROPS_GOLD_AVG:format(Core.CoinText(s.moneyAvg)) or nil
    lines[#lines + 1] = Line(head, not long and avg or nil, GOLD)
    local items = D.Sorted(s, rareFirst)
    local limit = long and D.LONG_ITEMS or D.SHORT_ITEMS
    for i = 1, math.min(limit, #items) do
        local item = items[i]
        lines[#lines + 1] = Line("  " .. D.TipItemText(item), D.CountText(item, s, long))
    end
    if long then
        if #items > limit then lines[#lines + 1] = Line("  " .. ezCore.More(#items - limit), nil, GREY) end
        if s.money > 0 then
            lines[#lines + 1] = Line(L.DROPS_GOLD_LONG:format(Core.CoinText(s.moneyAvg), s.moneyLoots, s.loots), nil, WHITE)
        end
        lines[#lines + 1] = Line(s.counted and L.DROPS_COUNTED or L.DROPS_SOURCE, nil, GREY)
    elseif #items > limit or s.money > 0 then
        lines[#lines + 1] = Line(L.DROPS_SHIFT:format(Core.L.CLICK_MOD_SHIFT), nil, GREY)
    end
    return lines
end

---------------------------------------------------------------------------
-- Zwischenspeicher
---------------------------------------------------------------------------

local cache, cached = {}, 0
D.CACHE_MAX = 200           -- Einträge je Zwischenspeicher; darüber wird er geleert (wie ezCores Gathering.lua)

-- Laufzeit der Sitzung (Frist des Zwischenspeichers, nie gespeichert): Core.Uptime (W-14)
local Clock = Core.Uptime

-- Stand der Zählung in ezCores Datenbank (Core.DB.Version("drops"), wie ezCores DiscoveryView). Sie ändert sich
-- auch ohne Eintrag im Beute-Verlauf (Tode, leere Fenster) – ein anderer Stand macht jeden Zwischenspeicher alt.
-- Fehlt die Abfrage oder liefert sie Unbrauchbares: 0.
function D.DbVersion()
    local DB = Core.DB
    if type(DB) ~= "table" or type(DB.Version) ~= "function" then return 0 end
    local ok, v = pcall(DB.Version, "drops")
    return ok and not ns.IsSecret(v) and Num(v) or 0
end

-- Gilt ein Eintrag noch? (jünger als CACHE_TIME und derselbe Stand der Datenbank)
function D.Fresh(c)
    return c ~= nil and Clock() - c.at < D.CACHE_TIME and c.ver == D.DbVersion()
end

function D.Get(npc)
    npc = Num(npc)
    if not npc then return nil end
    local c = cache[npc]
    if D.Fresh(c) then return c.s end
    local s = D.Summarize(npc)
    if not c then
        if cached >= D.CACHE_MAX then wipe(cache); cached = 0 end
        cached = cached + 1
    end
    cache[npc] = { s = s, at = Clock(), ver = D.DbVersion() }
    return s
end

---------------------------------------------------------------------------
-- Wert je Tötung (V2, Welle 24; Bericht Welle 20, docs/archiv/eroerterung-datenbank.md, vom Nutzer freigegeben „zuerst
-- V1–V5“). Die Rechnung liegt in ezCore (Core.Drops.Worth, Welle 23d: eigene Beute dieses Gegners × eigene
-- Auktionspreise, sonst Händlerpreis laut Client, dazu das Geld; unter Core.Drops.WORTH_MIN Vorgängen nichts).
-- ezLoot zeigt nur die Zeile und nennt die Quelle (Leitlinie 11): „Wert je Tötung: 1 g 20 s (aus deiner Beute,
-- 40 Tötungen)“, mit Shift darunter der Preis-Teil („Preise aus …“). Wortlaut und Preis-Teil kommen seit Welle 26
-- aus ezCore (Core.Drops.WorthLinesOf: Felder value und price) – eine Stelle für ezLoot und ezMap.
--   Drops.WorthAvailable()   → hat dieses ezCore die Rechnung und die Zeilen? (sonst bleibt die Zeile still weg)
--   Drops.Worth(npc)         → Ergebnis von Core.Drops.Worth("loot", npc) oder nil, Grund – zwischengespeichert am
--                              Eintrag von Drops.Get (gleiche Frist, gleicher Stand der Datenbank)
--   Drops.WorthLines(npc, long) → Zeilen für den Gegner-Tooltip ({} ohne Schalter, Rechnung oder genug Tötungen)
---------------------------------------------------------------------------

function D.WorthAvailable()
    local DR = Core.Drops
    return type(DR) == "table" and type(DR.Worth) == "function" and type(DR.WorthLinesOf) == "function"
end

function D.Worth(npc)
    npc = Num(npc)
    if not npc then return nil, "none" end
    if not D.WorthAvailable() then return nil, "old" end
    D.Get(npc)                          -- frischer Eintrag im Zwischenspeicher, an ihm hängt der Wert
    local c = cache[npc]
    if c and c.worth ~= nil then return c.worth or nil, c.why end
    local ok, w, why = pcall(Core.Drops.Worth, "loot", npc)
    if not ok then w, why = nil, "error" end
    -- Form prüfen (Leitlinie 6: gesperrt zuerst, nie mit nil vergleichen)
    if ns.IsSecret(w) or type(w) ~= "table" or ns.IsSecret(w.value) or ns.IsSecret(w.n)
        or not Num(w.value) or not Num(w.n) or Num(w.value) <= 0 then
        w = nil
        why = why or "none"
    end
    if c then c.worth, c.why = w or false, why end
    return w, why
end

-- Zeilen aus ezCores Wortlaut für das zwischengespeicherte Ergebnis (kein zweites Rechnen): Wert-Zeile mit dem Nenner
-- („aus deiner Beute, 40 Tötungen“), mit Shift nur der Preis-Teil (der Nenner stünde sonst zweimal untereinander,
-- Gegenprüfung Welle 24).
local function UsableText(text)
    return type(text) == "string" and not ns.IsSecret(text) and text ~= ""
end

function D.WorthLines(npc, long)
    local lines = {}
    if not ns.Enabled("npcWorth") then return lines end
    local w = D.Worth(npc)
    if not w or not D.WorthAvailable() then return lines end
    local ok, t = pcall(Core.Drops.WorthLinesOf, w)
    if not ok or type(t) ~= "table" or ns.IsSecret(t) or not UsableText(t.value) then return lines end
    lines[1] = Line(t.value, nil, WHITE)
    if long and UsableText(t.price) then
        -- Preisquelle aus ezCore (eine Stelle für ezLoot und ezMap): Auktionshaus-Erfassungen mit Alter, Händlerpreis
        local line = Line(t.price, nil, GREY)
        line.wrap = true
        lines[2] = line
    end
    return lines
end

---------------------------------------------------------------------------
-- Mögliche Beute aus ezCores Quellen (Datenbanken installierter Addons; ezLoot fragt nur)
---------------------------------------------------------------------------

D.SOURCE_SHORT = 3          -- Zeilen „laut <Quelle>“ ohne Shift (Entscheidung des Nutzers 13.11.2026: 3, mit Shift 8)
D.SOURCE_LONG = 8

-- Reicht dieses ezCore Beute aus fremden Datenbanken durch? (Core.Sources.LootOf, seit Welle 2b)
function D.SourcesAvailable()
    local sources = Core.Sources
    return type(sources) == "table" and type(sources.LootOf) == "function"
end

local function Chance(value)
    value = Num(value)
    if not value or value < 0 or value > 1 then return nil end
    return value
end

local function CopyItem(entry)
    if type(entry) ~= "table" or ns.IsSecret(entry) then return nil end
    local id = Num(entry.id)
    if not id or id <= 0 then return nil end
    -- Quest-Gegenstand: wie die Quelle sagt, sonst laut ezCores Item-Wissen (QuestieDB nennt es nicht mit)
    local quest = entry.quest == true or D.IsQuest({ id = id })
    return { id = id, chance = Chance(entry.chance), quest = quest or nil }
end

-- Antwort von ezCore: Core.Sources.LootOf(npcID, { level }) (Form in docs/ezcore.md). Alles wird geprüft und in
-- eigene Tabellen übernommen – nichts bleibt mit der Antwort verbunden, nichts wird hineingeschrieben. Fehlt der
-- Dienst, weiß keine Quelle etwas oder kommt eine falsche Form zurück: nil.
--   → { npc, source, sourceKey, label, own, items = { { id, chance (0–1), quest } … } }
function D.SourceLoot(npc, level)
    npc = Num(npc)
    if not (npc and D.SourcesAvailable()) then return nil end
    local info = Num(level) and level > 0 and { level = level } or nil
    local ok, b = pcall(Core.Sources.LootOf, npc, info)
    if not ok or ns.IsSecret(b) or type(b) ~= "table" or type(b.items) ~= "table" then return nil end
    local source = Plain(b.source)
    if type(source) ~= "string" or source == "" then return nil end
    local out = { npc = npc, source = source, sourceKey = Plain(b.sourceKey), items = {} }
    for _, entry in ipairs(b.items) do
        local item = CopyItem(entry)
        if item then out.items[#out.items + 1] = item end
    end
    if #out.items == 0 then return nil end
    out.own = out.sourceKey == "own"        -- ezCores eigene Entdecker-Datenbank („bei dir“), keine fremde Quelle
    -- Kopfzeile von ezCore („laut Questie“, „laut AtlasLoot“), sonst in eigenen Worten
    local labelOk, label = false, nil
    if type(Core.Sources.Label) == "function" then labelOk, label = pcall(Core.Sources.Label, b) end
    label = labelOk and Plain(label) or nil
    out.label = type(label) == "string" and label ~= "" and label or L.SOURCES_ACCORDING:format(source)
    return out
end

local sourceCache, sourceCached = {}, 0

-- Zwischengespeichert je Gegner und Stufe (CACHE_TIME, höchstens CACHE_MAX Einträge); false = keine Quelle weiß etwas.
function D.GetSources(npc, level)
    npc = Num(npc)
    if not npc then return nil end
    local key = npc .. ":" .. (Num(level) or 0)
    local c = sourceCache[key]
    if c and Clock() - c.at < D.CACHE_TIME then return c.b or nil end
    local b = D.SourceLoot(npc, level)
    if not c then
        if sourceCached >= D.CACHE_MAX then wipe(sourceCache); sourceCached = 0 end
        sourceCached = sourceCached + 1
    end
    sourceCache[key] = { b = b or false, at = Clock() }
    return b
end

-- Qualität zur itemID aus ezCores Item-Wissen (unbekannt: nil, Farbe dann weiß).
function D.ItemQuality(id)
    local knowledge = Core.Knowledge
    if not (id and type(knowledge) == "table" and type(knowledge.Get) == "function") then return nil end
    local ok, facts = pcall(knowledge.Get, id)
    return ok and type(facts) == "table" and Num(facts.quality) or nil
end

-- Reihenfolge: Quest-Gegenstände zuerst, bei Elite und Bossen die seltenste Qualität, sonst die höchste Chance.
function D.SortedSource(items, rareFirst)
    local list = {}
    for i, item in ipairs(type(items) == "table" and items or {}) do
        list[i] = item
        if item.q == nil then item.q = D.ItemQuality(item.id) end
        item.order = i
    end
    table.sort(list, function(a, b)
        if (a.quest == true) ~= (b.quest == true) then return a.quest == true end
        local qa, qb = a.q or 0, b.q or 0
        if rareFirst and qa ~= qb then return qa > qb end
        local ca, cb = a.chance or -1, b.chance or -1
        if ca ~= cb then return ca > cb end
        return a.order < b.order
    end)
    return list
end

-- Chance als Text: ab 10 % ganze Zahl, ab 1 % eine Nachkommastelle, ab 0,1 % zwei, darunter „<0,1 %“.
function D.ChanceText(chance)
    chance = Chance(chance)
    if not chance then return nil end
    local pct = chance * 100
    local text
    if pct >= 10 then
        text = ("%d"):format(math.floor(pct + 0.5))
    elseif pct >= 1 then
        text = Core.Decimal(pct, 1)   -- Dezimalzeichen der Spielsprache (T16-2)
    elseif pct >= 0.1 then
        text = Core.Decimal(pct, 2)
    else
        return L.DROPS_PCT_LOW
    end
    return L.DROPS_PCT:format((text:gsub("%.", L.DECIMAL)))
end

-- Rechte Spalte eines Gegenstands: die Chance der Quelle („33 %“, grau), ohne Chance nichts. → Text, Farbe
function D.ChanceRight(item)
    local text = D.ChanceText(item.chance)
    return text, text and GREY or nil
end

-- Zeilen „Mögliche Beute laut <Quelle>“ (b aus GetSources): höchstens SOURCE_SHORT Gegenstände, mit Shift
-- SOURCE_LONG und der Weg zur vollen Liste.
-- Nennt die Quelle Gegenstände ohne jede Chance (QuestieDB: „kann fallen lassen“)? Dann heißt der Kopf so.
function D.Listed(b)
    if type(b) ~= "table" or type(b.items) ~= "table" or #b.items == 0 then return false end
    for _, item in ipairs(b.items) do
        if type(item) ~= "table" or item.chance ~= nil then return false end
    end
    return true
end

-- Kopfzeile: „Mögliche Beute laut <Quelle>“, ohne Chance „Kann fallen lassen (laut Questie, ohne Chance)“, aus der
-- eigenen Entdecker-Datenbank „Beute bei dir (gezählt)“.
function D.PossibleHead(b)
    local label = b.label or L.SOURCES_ACCORDING:format(b.source or "?")
    if b.own then return L.DROPS_POSSIBLE_OWN:format(label) end
    if D.Listed(b) then return L.DROPS_LISTED:format(label) end
    return L.DROPS_POSSIBLE:format(label)
end

-- Rest einer gekürzten Liste (Welle 23, A1): „… und 3 weitere“ aus ezCore (Core.More, eine Stelle für alle Module),
-- ohne Shift mit dem Zusatz „(Shift)“ – mit Shift steht mehr da. Auch für den Gegenstands-Tooltip (ItemLoot.lua).
function D.MoreText(count, long)
    if long then return ezCore.More(count) end
    return ezCore.More(count) .. " " .. L.DROPS_SHIFT_TAG:format(Core.L.CLICK_MOD_SHIFT)
end

function D.PossibleLines(b, long, rareFirst)
    local lines = {}
    if type(b) ~= "table" then return lines end
    lines[1] = Line(D.PossibleHead(b), nil, GOLD)
    local items = D.SortedSource(b.items, rareFirst)
    local limit = long and D.SOURCE_LONG or D.SOURCE_SHORT
    for i = 1, math.min(limit, #items) do
        local item = items[i]
        local right, rgb = D.ChanceRight(item)
        local line = Line("  " .. D.TipItemText(item), right)
        if right and rgb then line.rr, line.rg, line.rb = rgb[1], rgb[2], rgb[3] end
        lines[#lines + 1] = line
    end
    if #items > limit then
        lines[#lines + 1] = Line("  " .. D.MoreText(#items - limit, long), nil, GREY)
    end
    if long then lines[#lines + 1] = Line(L.DROPS_VIEW:format(ns.SlashCmd()), nil, GREY) end
    return lines
end

-- Früherer Name (Welle 2, damals für Core.Sources.NpcLoot); bleibt als Weg zu PossibleLines.
function D.SourceLines(b, long, rareFirst) return D.PossibleLines(b, long, rareFirst) end

-- Kurzer Satz, warum keine Quelle mögliche Beute nennt (Leitlinie 11: kein leerer Tooltip ohne Erklärung).
function D.SourceHint()
    if not D.SourcesAvailable() then return L.DROPS_HINT_NO_CORE end
    local hint
    if type(Core.Sources.Hint) == "function" then
        local ok, text = pcall(Core.Sources.Hint, "lootOf")
        hint = ok and Plain(text) or nil
    end
    if type(hint) == "string" and hint ~= "" then return L.DROPS_HINT:format(hint) end
    return L.DROPS_HINT_UNKNOWN
end

-- Namen der Quellen, die gerade mögliche Beute liefern (für /ezl status und Tooltips); leer, wenn keine läuft.
function D.ActiveSources()
    local names = {}
    if not (D.SourcesAvailable() and type(Core.Sources.List) == "function") then return names end
    local ok, list = pcall(Core.Sources.List, "lootOf")
    if not ok or type(list) ~= "table" then return names end
    for _, entry in ipairs(list) do
        -- die eigene Entdecker-Datenbank ist keine angebundene Quelle (eigene Statuszeile „Beute bei dir“)
        if type(entry) == "table" and entry.status == "ok" and type(entry.label) == "string" and entry.key ~= "own" then
            names[#names + 1] = entry.label
        end
    end
    return names
end

-- AtlasLoot (DG-49): Bossbeute neuer Forever-Instanzen reicht keine Quelle durch – solange AtlasLoot läuft, öffnet
-- ein Knopf wenigstens sein Fenster. AtlasLoot kennt keinen Befehl für einen bestimmten Boss: ezCore öffnet es nur
-- mit ausdrücklichem Schlüssel (generic), und der Tooltip des Knopfs sagt das. → Anzeigename | nil
D.ATLAS_KEY = "AtlasLoot"
function D.AtlasLabel()
    if not (D.SourcesAvailable() and type(Core.Sources.List) == "function" and type(Core.Sources.OpenFor) == "function") then
        return nil
    end
    local ok, list = pcall(Core.Sources.List, "openFor")
    if not ok or type(list) ~= "table" then return nil end
    for _, entry in ipairs(list) do
        if type(entry) == "table" and entry.key == D.ATLAS_KEY and entry.status == "ok" then
            return type(entry.label) == "string" and entry.label or D.ATLAS_KEY
        end
    end
    return nil
end

-- Fenster von AtlasLoot öffnen (Core.Sources.OpenFor mit Schlüssel). → true | false, Meldung für den Chat
function D.OpenAtlas(npc)
    local label = D.AtlasLabel()
    if not label then return false, L.POSSIBLE_OPEN_MISSING end
    local ok, opened = pcall(Core.Sources.OpenFor, Num(npc) or 1, D.ATLAS_KEY)
    if ok and opened == true then return true end
    return false, L.POSSIBLE_OPEN_FAILED:format(label)
end

-- Alle Zeilen des Abschnitts. opts: long (Shift), rareFirst, other (true: ein anderes Addon zeigt selbst Beute im
-- Gegner-Tooltip), possible (Antwort aus GetSources), hint (Hinweis bei nie geplünderten Gegnern erlaubt),
-- sourceHint (Satz, warum keine Quelle etwas nennt; nur mit Shift), worth (Zeilen aus WorthLines, V2).
function D.TooltipLines(s, opts)
    opts = opts or {}
    local lines = {}
    local looted = type(s) == "table" and (s.loots or 0) > 0
    if opts.other then
        -- Das andere Addon zeigt die mögliche Beute; von ezLoot nur die eigene Zeile „bei dir n×“.
        if looted then
            local avg = s.money > 0 and L.DROPS_GOLD_AVG:format(Core.CoinText(s.moneyAvg)) or nil
            lines[1] = Line(D.HeadText(s), avg, GOLD)
        end
        return lines
    end
    local known = D.PossibleLines(opts.possible, opts.long, opts.rareFirst)
    for _, line in ipairs(known) do lines[#lines + 1] = line end
    if looted then
        for _, line in ipairs(D.Lines(s, opts.long, opts.rareFirst)) do lines[#lines + 1] = line end
        -- Wert je Tötung (V2) direkt unter der eigenen Beute; leer unter ezCores Mindestzahl oder mit Schalter aus
        for _, line in ipairs(type(opts.worth) == "table" and opts.worth or {}) do lines[#lines + 1] = line end
        if #known == 0 and opts.long and opts.sourceHint then lines[#lines + 1] = Line(opts.sourceHint, nil, GREY) end
    elseif #known > 0 then
        lines[#lines + 1] = Line(L.DROPS_NONE, nil, GREY)
    elseif opts.hint then
        -- keine Quelle und nichts Eigenes: kurz sagen, warum hier nichts steht (kein leerer Tooltip ohne Erklärung)
        lines[#lines + 1] = Line(L.DROPS_NONE, nil, GREY)
        if opts.long then
            if opts.sourceHint then lines[#lines + 1] = Line(opts.sourceHint, nil, GREY) end
            lines[#lines + 1] = Line(L.DROPS_NONE_WHY, nil, GREY)
        end
    end
    return lines
end

function D.ClearCache()
    wipe(cache)
    wipe(sourceCache)
    cached, sourceCached = 0, 0
end

local function Forget(kind, e)
    if kind ~= "loot" then return end
    local npc = NpcOf(e)
    if npc and cache[npc] then cache[npc], cached = nil, cached - 1 end
end
Core.Listen("HISTORY_ADDED", Forget, ADDON)
Core.Listen("HISTORY_REMOVED", Forget, ADDON)
-- „Verlauf leeren“ (ezCore.History.Clear/ClearAll): art = nil heißt alles. Ohne das zeigte der Tooltip bis zu
-- CACHE_TIME Sekunden lang Beute, die es nicht mehr gibt.
Core.Listen("HISTORY_CLEARED", function(kind)
    if kind == nil or kind == "loot" then D.ClearCache() end
end, ADDON)

---------------------------------------------------------------------------
-- Einheiten-Tooltip
---------------------------------------------------------------------------

-- Zeigt gerade ein anderes Addon selbst Beute im Gegner-Tooltip? → sein Name | nil. Braucht es dafür eine Taste
-- (Tnny's Mob Loot, Entscheidungsfrage 5: „Nur bei gehaltener Taste“, LOOT-08), zählt es nur, solange sie gehalten
-- wird (Core.OtherAddOnKeyHeld, EC-96); kennt ezCore keine Taste (nil) oder ist es eine ältere Fassung ohne diese
-- Auskunft, gilt es wie bisher als zeigend.
function D.OtherShowing()
    local other = ns.OtherFor("unitLoot")
    if other == nil then return nil end
    if type(Core.OtherAddOnKeyHeld) ~= "function" then return other end
    local ok, held = pcall(Core.OtherAddOnKeyHeld, "unitLoot")
    if ok and held == false then return nil end
    return other
end

-- Braucht das andere Addon eine Taste für seine Liste? → true, Name (für /ezl status)
function D.OtherKeyed()
    local other = ns.OtherFor("unitLoot")
    if other == nil or type(Core.OtherAddOnKeyHeld) ~= "function" then return false, other end
    local ok, held = pcall(Core.OtherAddOnKeyHeld, "unitLoot")
    return ok and type(held) == "boolean", other
end

-- Voller Abschnitt? Schalter an und kein anderes Addon zeigt gerade Beute im Einheiten-Tooltip (dann bleibt von
-- ezLoot nur die eigene Zeile „bei dir n×“, siehe TooltipLines).
function D.Allowed()
    return ns.Enabled("npcLoot") and D.OtherShowing() == nil
end

-- Abfragen des Clients über ezCore (Core.Call, Core.Bool, Core.Plain, Core.UnitRank; V-179, V-184): nie ein
-- Fehler, ein gesperrter Wert zählt wie „unbekannt“ – die eigene Hülle Call ist entfallen.

-- NPC-ID einer Einheit (nil bei Spielern, geheimen Werten und allem ohne Kreatur-GUID).
function D.UnitNpc(unit)
    if ns.IsSecret(unit) or type(unit) ~= "string" then return nil end
    if Core.Bool(Core.Call(UnitIsPlayer, unit), false) then return nil end
    return Core.NpcID(Core.Plain((Core.Call(UnitGUID, unit))))
end

-- Einstufung über ezCore (Core.UnitRank: „normal“, „elite“, „rareelite“, „worldboss“ …; gesperrt → nil, LOOT-02)
function D.RareFirst(unit)
    local rank = Core.UnitRank(unit)
    return rank ~= nil and D.RARE_FIRST[rank] == true
end

-- Stufe einer Einheit (reicht ezLoot an Core.Sources.LootOf durch; die Stufenprüfung der Schätzungen von Tnny's Mob
-- Loot ist seit Welle 16 entfernt); geheim, unbekannt oder ≤ 0: nil.
function D.UnitLevel(unit)
    if ns.IsSecret(unit) or type(unit) ~= "string" then return nil end
    local level = Num((Core.Call(UnitLevel, unit)))
    return level and level > 0 and level or nil
end

local function ShiftDown() return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true end

-- Hinweis „noch nicht geplündert“ nur bei Gegnern, die sich angreifen lassen (nicht bei Händlern, Wachen der
-- eigenen Seite, Begleitern) und nur mit dem Schalter dafür.
function D.HintWanted(unit)
    if not ns.Enabled("npcLootHint") then return false end
    return Core.Bool(Core.Call(UnitCanAttack, "player", unit), false)
end

-- Abstand vor dem Abschnitt (S-1811-Tooltipabstand, Gesamtreview 18.11.2026; Spielbefund „hier fehlt abstand …
-- zum loot reiter“): ezCores einer Trenner (Core.Tooltip.Gap). Beute und Kürschnern bilden eine Gruppe – „Kürschnern:
-- ab 125“ schließt ohne Leerzeile an die Beute an. Läuft Questie, setzt ezCore beide Abschnitte hinter dessen Blöcke.
D.TOOLTIP_GROUP = "ezLoot.npc"
function D.Gap(tooltip)
    local T = Core.Tooltip
    if type(T) == "table" and type(T.Gap) == "function" then return T.Gap(tooltip, D.TOOLTIP_GROUP) end
    return false
end

function D.AddSection(tooltip, unit)
    if not ns.Enabled("npcLoot") then return 0 end
    local npc = D.UnitNpc(unit)
    if not npc then return 0 end
    -- zuletzt geprüfter Gegner, auch ohne Zeilen: hält man die Taste des anderen Addons über einem nie geplünderten
    -- Gegner, entsteht keine Zeile – beim Loslassen muss ezLoot trotzdem neu zeichnen (OnModifier, LOOT-08)
    D.checkedNpc = npc
    local full = D.Allowed()    -- false: ein anderes Addon zeigt die mögliche Beute schon, von ezLoot nur „bei dir n×“
    local long = ShiftDown()
    local possible = full and D.GetSources(npc, D.UnitLevel(unit)) or nil
    local lines = D.TooltipLines(D.Get(npc), {
        long = long, rareFirst = D.RareFirst(unit), other = not full, possible = possible,
        hint = full and D.HintWanted(unit), sourceHint = full and long and not possible and D.SourceHint() or nil,
        -- Wert je Tötung (V2): dieselbe Rücksicht wie der Beute-Block (Leitlinie 9) – zeigt ein anderes Addon seine
        -- Liste am Gegner, bleibt nur „bei dir n×“
        worth = full and D.WorthLines(npc, long) or nil,
    })
    if #lines == 0 then return 0 end
    D.Gap(tooltip)
    for _, line in ipairs(lines) do
        if line.right then
            tooltip:AddDoubleLine(line.left, line.right, line.r, line.g, line.b, line.rr or 1, line.rg or 1, line.rb or 1)
        else
            tooltip:AddLine(line.left, line.r, line.g, line.b, line.wrap == true)
        end
    end
    D.shownNpc = npc
    return #lines
end

-- Welle 27 (F4 b, Entscheidung des Nutzers vom 16.11.2026): „Kürschnern: ab 125, laut Client-Meldung“ am Gegner.
-- Wert, Quelle und Farbe kommen aus ezCore (Core.Gathering.SkinLines – beobachtet, laut Client oder als „geschätzt“
-- gekennzeichnet), ezLoot rechnet nichts. Keine Zeile, solange ezCore nichts weiß. Schalter npcSkin; gesperrte
-- Einheiten prüft D.UnitNpc zuerst (Leitlinie 6).
function D.SkinLines(unit)
    if not ns.Enabled("npcSkin") then return {} end
    local npc = D.UnitNpc(unit)
    local G = Core.Gathering
    if not (npc and type(G) == "table" and type(G.SkinLines) == "function") then return {} end
    local ok, lines = pcall(G.SkinLines, npc, D.UnitLevel(unit))
    return ok and type(lines) == "table" and lines or {}
end

function D.AddSkinSection(tooltip, unit)
    local lines = D.SkinLines(unit)
    if #lines > 0 then D.Gap(tooltip) end
    for _, line in ipairs(lines) do tooltip:AddLine(line.text, line.r, line.g, line.b, true) end
    return #lines
end

if type(Core.Tooltip) == "table" and type(Core.Tooltip.AddUnitSection) == "function" then
    Core.Tooltip.AddUnitSection("ezLoot.drops", 60, function(tooltip, unit) D.AddSection(tooltip, unit) end, ADDON)
    Core.Tooltip.AddUnitSection("ezLoot.skin", 61, function(tooltip, unit) D.AddSkinSection(tooltip, unit) end, ADDON)
end

-- Shift gedrückt oder losgelassen: Tooltip neu zeichnen, wenn er gerade Beute dieses Moduls zeigt. Alt und Strg nur,
-- solange ein anderes Addon seine Beute-Liste mit einer Taste zeigt (LOOT-08: ezLoot blendet seine Liste nur aus,
-- während dessen Taste gehalten wird).
D.SHIFT_KEYS = { LSHIFT = true, RSHIFT = true }
D.OTHER_KEYS = { LALT = true, RALT = true, LCTRL = true, RCTRL = true }
-- Ohne anderes Addon ändert Shift nur Zeilen, die schon dastehen (shownNpc). Läuft eines, kann jede seiner Tasten
-- (auch Shift) ezLoots Liste erst hervorholen – dann zählt der zuletzt geprüfte Gegner (checkedNpc), auch wenn er
-- gerade keine Zeile hatte.
function D.OnModifier(key)
    local other = ns.OtherFor("unitLoot") ~= nil
    if not D.SHIFT_KEYS[key] and not (D.OTHER_KEYS[key] and other) then return false end
    local npc = other and D.checkedNpc or D.shownNpc
    if not (npc and GameTooltip and GameTooltip:IsShown() and GameTooltip.GetUnit and GameTooltip.RefreshData) then
        return false
    end
    local ok, _, unit = pcall(GameTooltip.GetUnit, GameTooltip)
    if not ok or D.UnitNpc(unit) ~= npc then return false end
    return pcall(GameTooltip.RefreshData, GameTooltip) == true
end
ns.On("MODIFIER_STATE_CHANGED", function(_, key) D.OnModifier(key) end)
