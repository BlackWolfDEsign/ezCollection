local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Sammel-Fundorte: Wo lassen sich Kräuter, Erze und Fische sammeln? Seit der Entscheidung vom 14.11.2026
    („Auctionator und GatherMate ablösen“) hat ezCollection eigene Fundorte: ezCore merkt jede eigene Ernte in der
    Entdecker-Datenbank (Discovery.lua, Tabellen obj und spot) und liefert sie über den Dienst unten; die Anzeige auf
    Karte und Minikarte baut ezMap (Wellen 13 bis 15). Die Lese-Brücken zu Gatherer Reforged und GatherMate2 sind
    seit Welle 16 entfernt (RB-02, RB-03); auf beide nimmt ezCollection nur noch Rücksicht (gatherPins).

      ezCore.Gathering.Sources(itemID)       → { { zone = Name, mapID, count, source = Addon } … }, meiste zuerst
      ezCore.Gathering.Text(itemID, max)     → „Westfall, Wald von Elwynn (+2)“ oder nil
      ezCore.Gathering.InZone(itemID, mapID) → Anzahl im Gebiet (ohne mapID: wo du gerade bist) – „hier sammelbar“
      ezCore.Gathering.Active()              → Namen der Addons, die gerade Fundorte liefern
      ezCore.Gathering.AddProvider(key, label, fn, opts)   fn(itemID) → { { mapID oder zone, count } … };
                                             opts.first (vorn einreihen), opts.active (fn → liefert gerade etwas)
    Seit Welle 9 steht vorn die eigene Entdecker-Datenbank als Quelle „bei dir“ (Core.Finds.Of, DiscoveryView.lua):
    eigene Ernten an Spielobjekten und beim Angeln je Karte, gezählt auch, wenn ein Sammel-Addon läuft (DG-12).
    Die Zeile „Beute von“ weicht einem Abschnitt, der Core.Tooltip.ClaimLine("lootFrom", …) anmeldet (ezLoot).
    Tooltip „Bezugsquellen“ (Nutzer 13.11.2026: „betrifft nicht nur kräuter und erze sondern alle rohstoffe und
    ressourcen, gerne auch händler/NSC“), Schalter unter „ezCollection“ → „Tooltip“ (ezCoreDB.tooltip.gathering):
      „Fundorte: …“      gesammelt (eigene Ernten „bei dir“: Kräuter, Erze, Fische)
      „Beute bei dir von: …“  Gegner, die den Rohstoff fallen ließen (eigene Beute aller Charaktere, History.LootSources)
      „Händler: …“       Händler, die ihn verkaufen (beim Ansprechen gemerkt, Knowledge.VendorSources), günstigste zuerst
      „Herkunft laut Questie: fällt von …; verkauft von …“  nur ohne eigene Beute- und Händlerzeile, aus der ersten
                         angebundenen Datenbank (Core.Sources.WhereFrom, DG-15); an Quest-Gegenständen nicht, solange
                         Questies Tooltip sie zeigt (questItemSource, DG-17)
    Beute und Händler gelten für Rohstoffe und Ressourcen (Knowledge.IsResource: Handwerkswaren und Reagenzien).
      ezCore.Gathering.Lines(itemID) → { Text … } (für den Tooltip und für Tests); ohne Fundort an Kräutern und Erzen
                                       ein erklärender Satz (Leitlinie 11)

    Dienst der eigenen Fundorte (SAM-03, Welle 12; Module lesen nur hierüber, nie die Tabellen):
      G.Nodes(mapID, filter)       → { { id, kind, stored, map, x, y, cnt, t, fallback, explorer } … } Punkte auf
                                     der Karte mapID: aus ihrer Speicherkarte und, über Weltkoordinaten umgerechnet,
                                     aus Eltern- und Nachbarkarten (Karten ohne Weltposition: nur die Speicherkarte);
                                     nichts wird doppelt gespeichert. filter = { kind = "herb"|"ore"|"chest"|"fish",
                                     item = itemID, skill = Rang (nur, was dieser Rang abbauen kann;
                                     ein nur „höchstens“ bekannter Wert – "upto" – blendet seit Welle 23d nicht aus),
                                     explorer = true }
                                     – Kisten nur mit OPT_explorer bzw. filter.explorer; filter.item gilt seit Welle 23c
                                     auch für Angelplätze (Fang im Gebiet); sx, sy = Lage auf der Speicherkarte;
                                     src = "backup" für Stellen aus einer eingelesenen Sicherung (Welle 23d), sonst nil
      G.Near(mapID, x, y, radius)  → dieselben Punkte im Umkreis (Yards, über C_Map.GetMapWorldSize), nächster zuerst,
                                     je mit yards; ohne Kartengröße {} und "nosize"
      G.Kinds()                    → { { kind, label, count } … } eigene Arten (herb, ore, chest, fish)
      G.Forget({ id | map, kind }) → Zahl entfernter Stellen (ein Objekt überall, eine Karte ganz oder je Art)
      G.Forget({ map, id, x, y, kind, yards }) → 1 oder 0: nur die eine Stelle des Objekts (bzw. des Angel-Gebiets
                                     mit kind = "fish") auf der Speicherkarte map, die (x, y) am nächsten liegt, im
                                     Umkreis yards (Standard G.JUST_YARDS; ohne Kartengröße 1 % der Karte); x, y auf
                                     der Speicherkarte – die Felder sx, sy der Punkte aus G.Nodes (Welle 23c, A34)
      G.Items()                    → { { item, kind, harvests, sources, need, needHow } … } alle Gegenstände deiner
                                     Ernten mit Art (herb, ore, fish, skin; chest nur mit Entdecker-Wissen), meiste
                                     Ernten zuerst; need/needHow: kleinster nötiger Rang der Objekte (G.Required)
                                     – für „Wo am dichtesten?“ (Welle 23c, A36)
      G.ItemsOf(art)               → dieselben Einträge nur einer Art („Rohstoffe je Art“ für ezCraft; Welle 23c, A38)
      G.FishAreasFor(itemID)       → { [Speicherkarte] = { [Gebiet] = Fänge } } Angel-Gebiete mit diesem Fang
                                     (Filter item von G.Nodes bezieht sie ein; Welle 23c, A37)
      G.Required(objectID)         → Rang, Herkunft ("client" laut Client-Meldung | "seen" bei dir beobachtet |
                                     "upto" höchstens, aus einer Ernte) oder nil (SAM-04); G.SkillText(objectID)
      G.RequiredByLock(schloss)    → Rang, Art, "tables" laut Client-Tabellen (Welle 26, F4; Objekt » Schloss fehlt)
      Welle 27 (F4 b, Abschnitt „Nötige Fertigkeit aller Sammel-Ressourcen“ unten): G.Required gibt als dritten Wert
                                     { cnt, kind, lock, locks, stage } und kennt die Herkunft "tables" (Schloss-Stufe
                                     laut Client-Tabellen, eingegrenzt durch die eigene Beobachtung); Kisten (Schloss-
                                     knacken) und Schwärme (Angeln) zählen mit. G.NeedText, G.SkinRequired(npcID, stufe),
                                     G.SkinLines, G.SkinEstimate, G.RequiredItem(itemID), G.KindOfSkillName(name),
                                     G.SkillName(art); G.OwnRank("chest") liest Schlossknacken (633)
      G.ObjectsFor(itemID)        → { [objectID] = Ernten } – Umkehr-Index Gegenstand » Objekte (nur im Arbeitsspeicher)
      G.SkillUp(objectID, art, F?, Fb?) → Farbe (orange, gelb, grün, grau, rot, unbekannt) und Chance auf einen
                                     Fertigkeitspunkt für den eigenen Charakter, berechnet (Abschnitt „Farbe und Chance“;
                                     rot nach dem Rang samt Bonus Fb, Ergebnis mit effective)
      Nachricht GATHERING_CHANGED: eigene Fundorte oder Objekte haben sich geändert (aus DB_CHANGED, je Bild einmal)

    Fremde Sammel-Addons (Welle 16, SAM-30): Die Lese-Brücken zu Gatherer Reforged (RB-02) und GatherMate2 samt der
    Kennungs-Tabelle NODES, ihrer Herleitung zur Laufzeit (NodeIDs, DG-54) und dem Zweig für Zusatzspeicher (RB-03)
    sind entfernt – Entscheidung des Nutzers vom 15.11.2026 zu DG-54. ezCore liest ihre Daten nicht mehr; läuft
    eines, hält sich ezMap über gatherPins zurück (Erkennung in OtherAddOns.lua). AddProvider bleibt als
    Schnittstelle; ein Lieferant ohne opts.first heißt im Tooltip „laut <Name>“, nie „bei dir“ (DG-56).
]]

local G = {}
Core.Gathering = G

-- Erweiterungen bestehender Aufrufe (Welle 23c), prüfbar über needs bzw. Core.Has: Forget mit einer Stelle (A34),
-- WasJustGathered mit maxAge (A35), Filter item von Nodes mit Angelplätzen (A37). Neue Funktionen (Items, ItemsOf,
-- FishAreasFor) findet Core.Has über den Namen.
Core.FEATURES.gatherForgetSpot = true
Core.FEATURES.gatherJustMaxAge = true
Core.FEATURES.gatherNodesFish = true

local providers = {}

-- opts.first = true: vor allen anderen (die eigene Datenbank „bei dir“, DG-12); opts.active = fn() → true, wenn der
-- Anbieter gerade etwas liefert (sonst gilt „Addon key läuft“).
function G.AddProvider(key, label, fn, opts)
    for i = #providers, 1, -1 do
        if providers[i].key == key then table.remove(providers, i) end
    end
    local entry = { key = key, label = label, fn = fn, active = type(opts) == "table" and opts.active or nil }
    if type(opts) == "table" and opts.first then table.insert(providers, 1, entry) else providers[#providers + 1] = entry end
end

---------------------------------------------------------------------------
-- Abfragen
---------------------------------------------------------------------------

local function ZoneName(mapID, fallback)
    if mapID and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
    end
    return fallback or (mapID and ("#" .. mapID)) or "?"
end

local cache, CACHE_SECONDS = {}, 30

function G.Sources(itemID)
    itemID = Core.Num(itemID)
    if not itemID then return {} end
    local now = GetTime and GetTime() or 0
    local hit = cache[itemID]
    if hit and now - hit.t < CACHE_SECONDS then return hit.list end
    local byZone, list = {}, {}
    for _, provider in ipairs(providers) do
        local ok, found = pcall(provider.fn, itemID)
        if ok and type(found) == "table" then
            for _, e in ipairs(found) do
                local name = ZoneName(e.mapID, e.zone)
                local entry = byZone[name]
                if not entry then
                    entry = { zone = name, mapID = e.mapID, count = 0, source = provider.label, sourceKey = provider.key }
                    byZone[name] = entry
                    list[#list + 1] = entry
                end
                if (e.count or 0) > entry.count then
                    entry.count, entry.source, entry.sourceKey = e.count or 0, provider.label, provider.key
                end
                if provider.key == "ezCore" then entry.points = Core.Num(e.points) end
            end
        elseif not ok then
            Core.Error(Core.name, found, "Gathering " .. provider.key)
        end
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.zone < b.zone
    end)
    cache[itemID] = { t = now, list = list }
    return list
end

function G.Text(itemID, max)
    local list = G.Sources(itemID)
    if #list == 0 then return nil end
    max = max or 3
    local names = {}
    for i = 1, math.min(max, #list) do names[i] = list[i].zone end
    local text = table.concat(names, ", ")
    if #list > max then text = text .. " " .. L.GATHER_MORE:format(#list - max) end
    return text
end

-- Ganze Tooltip-Zeile mit neutraler Quelle (DG-56, SAM-03): „Fundorte: Westfall, … (bei dir, 12 Punkte; laut
-- <Lieferant>)“. Die eigene Datenbank heißt „bei dir“ mit der Zahl ihrer Punkte und steht immer zuerst, sobald sie
-- irgendwo Punkte hat (auch in einem Gebiet, in dem ein Addon mehr zählt, oder hinter den ersten max Gebieten); jede
-- andere Quelle „laut <Addon>“ – nie „selbst gesammelt“ für fremde Punkte.
function G.Line(itemID, max)
    local text = G.Text(itemID, max)
    if not text then return nil end
    local list, phrases, seen, own, hasOwn = G.Sources(itemID), {}, {}, 0, false
    for _, e in ipairs(list) do
        if e.sourceKey == "ezCore" or e.points ~= nil then
            hasOwn = true
            own = own + (Core.Num(e.points) or 0)
        end
    end
    if hasOwn then
        phrases[1] = own > 0 and L.GATHER_SOURCE_OWN_POINTS:format(L.GATHER_SOURCE_OWN,
            Core.Plural(own, L.GATHER_POINTS_ONE, L.GATHER_POINTS_MANY)) or L.GATHER_SOURCE_OWN
    end
    for i = 1, math.min(max or 3, #list) do
        local e = list[i]
        if e.sourceKey ~= "ezCore" then
            local phrase = L.GATHER_SOURCE_ADDON:format(e.source or "?")
            if not seen[phrase] then seen[phrase] = true phrases[#phrases + 1] = phrase end
        end
    end
    return L.GATHER_LINE_SOURCES:format(text, table.concat(phrases, "; "))
end

local function PlayerMapID()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    return ok and Core.Num(mapID) or nil
end

function G.InZone(itemID, mapID)
    mapID = mapID or PlayerMapID()
    if not mapID then return 0 end
    for _, e in ipairs(G.Sources(itemID)) do
        if e.mapID == mapID then return e.count end
    end
    return 0
end

function G.Active()
    local labels = {}
    for _, provider in ipairs(providers) do
        local on
        if provider.active then
            local ok, yes = pcall(provider.active)
            on = ok and yes == true
        else
            on = Core.IsLoaded(provider.key)
        end
        if on then labels[#labels + 1] = provider.label end
    end
    return labels
end

function G.ClearCache() cache = {} end

---------------------------------------------------------------------------
-- Dienst der eigenen Fundorte (SAM-03): Nodes, Near, Kinds, Forget, Required
---------------------------------------------------------------------------

-- gespeicherte Art (obj.kind, Discovery.lua) » öffentliche Art; Angel-Stellen (spot fishing) heißen fish
G.KIND_PUBLIC = { herb = "herb", mine = "ore", chest = "chest", pool = "fish" }
G.KIND_ORDER = { "herb", "ore", "fish", "chest" }
local PUBLIC_ALIAS = { mine = "ore", pool = "fish", fishing = "fish" }

local function DBReady()
    local DB = Core.DB
    return DB and DB.Ready and DB.Ready() and DB or nil
end

local function Version(DB)
    return DB.Version("spot") .. ":" .. DB.Version("obj") .. ":" .. DB.Version("drops") .. ":" .. (DB.Explorer() and 1 or 0)
end

-- Arbeitsspeicher: Objekt-Arten, Umkehr-Index Gegenstand » Objekte, Punkte je gezeigter Karte – je Version neu
local mem = { ver = nil, kinds = {}, items = nil, maps = {} }
local function Mem(DB)
    local ver = Version(DB)
    if mem.ver ~= ver then mem = { ver = ver, kinds = {}, items = nil, maps = {} } end
    return mem
end

local function StoredKind(DB, m, id)
    local k = m.kinds[id]
    if k == nil then
        local row = DB.Get("obj", id)
        k = type(row) == "table" and row.kind or false
        m.kinds[id] = k
    end
    return k or nil
end

function G.ObjectsFor(itemID)
    local DB = DBReady()
    itemID = Core.Num(itemID)
    if not (DB and itemID) then return {} end
    local m = Mem(DB)
    if not m.items then
        m.items = {}
        for _, id in ipairs(DB.KeysOf("drops", "object")) do
            local row = DB.Get("drops", "object", id)
            for _, b in pairs(type(row) == "table" and type(row.diff) == "table" and row.diff or {}) do
                for item, it in pairs(type(b) == "table" and type(b.items) == "table" and b.items or {}) do
                    local byItem = m.items[item] or {}
                    m.items[item] = byItem
                    byItem[id] = (byItem[id] or 0) + (Core.Num(it.f) or 0)
                end
            end
        end
    end
    local out = {}
    for id, n in pairs(m.items[itemID] or {}) do out[id] = n end
    return out
end

-- Welle 23c (A37): Angel-Gebiete je Gegenstand – Umkehr-Index aus drops fishing (Speicherkarte » Gebiet), nur im
-- Arbeitsspeicher wie G.ObjectsFor (neu je Version der Tabellen). → { [Speicherkarte] = { [Gebiet] = Fänge } }
function G.FishAreasFor(itemID)
    local DB = DBReady()
    itemID = Core.Num(itemID)
    if not (DB and itemID) then return {} end
    local m = Mem(DB)
    if not m.fish then
        m.fish = {}
        for _, map in ipairs(DB.KeysOf("drops", "fishing")) do
            for _, area in ipairs(DB.KeysOf("drops", "fishing", map)) do
                local row = DB.Get("drops", "fishing", map, area)
                for _, b in pairs(type(row) == "table" and type(row.diff) == "table" and row.diff or {}) do
                    for item, it in pairs(type(b) == "table" and type(b.items) == "table" and b.items or {}) do
                        local byItem = m.fish[item] or {}
                        m.fish[item] = byItem
                        byItem[map] = byItem[map] or {}
                        byItem[map][area] = (byItem[map][area] or 0) + (Core.Num(it.f) or 0)
                    end
                end
            end
        end
    end
    local out = {}
    for map, areas in pairs(m.fish[itemID] or {}) do
        out[map] = {}
        for area, n in pairs(areas) do out[map][area] = n end
    end
    return out
end

---------------------------------------------------------------------------
-- Nötige Fertigkeit aller Sammel-Ressourcen (SAM-04; Welle 27, Paket kern/sammel-fertigkeit, F4 b)
---------------------------------------------------------------------------
--[[
    Entscheidung des Nutzers vom 16.11.2026 (F4 b, wörtlich „wird auch leder beachtet? "alle" ressourcen?“): ezCore
    erhebt die nötige Fertigkeit im Spiel für Kräuter (Kräuterkunde), Erz und Gestein (Bergbau), Kisten (Schlossknacken),
    Schwärme (Angeln, soweit der Client etwas meldet) und Leder (Kürschnerei). Erhoben wird in Discovery.lua:
      Meldung des Clients   „Benötigt <Beruf> (<Rang>)“ (Muster aus den GlobalStrings, Discovery.SKILL_ERRORS) – der Name
                            des Berufs in der Meldung legt die Art fest (G.KindOfSkillName), sonst der eigene Zauber
      Tooltip               dieselbe Zeile im Tooltip eines Spielobjekts bzw. eines Gegners (nur gelesen, nie verändert)
      Ergebnis              Erfolg mit dem eigenen Rang (Ernte, Fang am Schwarm, Kürschnern, „Schloss knacken“)
    Gespeichert in der Entdecker-Datenbank in der Form, die schon SAM-04 nutzt (keine neue Tabelle, keine neuen Felder,
    docs/datengrundlage.md, Abschnitt 17): obj[objectID].skill bzw. npc[npcID].skill = { req (laut Client), lo
    (kleinster Rang bei Erfolg), hi (größter Rang bei Fehlschlag), cnt (Zahl der Beobachtungen, Welle 27) }.
    Abgleich mit den Schloss-Stufen der Client-Tabelle (Wissen/Client/Locks.lua, laut wago.tools): Jedes Kraut, Erz
    und jede verschlossene Kiste trägt ein Schloss mit einer Stufe aus ClientData.LockStages. Liegt zwischen dem größten
    Fehlschlag und der kleinsten Ernte genau eine Stufe der Tabelle (bzw. unter der kleinsten Ernte nur eine), ist der
    Rang genau bekannt: Herkunft "tables". Welches Schloss es ist, bleibt offen (mehrere Schlösser teilen eine Stufe) –
    info.locks nennt die Kandidaten. Schwärme werden nicht eingegrenzt: ob ein Schwarm auf Forever ein Schloss mit
    Angel-Stufe trägt, ist nicht belegt. Leder hat kein Schloss: der Wert hängt am Gegner (G.SkinRequired); ohne
    Beobachtung nur bei einem als kürschnerbar bekannten Gegner eine Schätzung aus seiner Stufe, gekennzeichnet als
    "estimated" (Leitlinie 11).
    Herkunft (how): "client" laut Client-Meldung | "tables" Schloss-Stufe laut Client-Tabellen, eingegrenzt durch deine
    Beobachtung | "seen" ab etwa, bei dir beobachtet | "upto" höchstens, bei dir beobachtet | "estimated" geschätzt
    „Laut Beiträgen“ gibt es noch nicht (Gesamtreview 18.11.2026, T14-7): Die Herkunft kommt erst mit der vorgefüllten
    Auslieferung der Entdecker-Datenbank (Stufe 2, Lage „Auslieferung“ DB.Ship) – nicht gebaut, über die Variante wird am
    Entwurf entschieden (docs/roadmap/ezCore.md, „Datenbank“). tools/merge.lua trägt die Felder schon zusammen; bis zur
    Auslieferung liest sie im Spiel nichts, und Bounds nennt nie „laut Beiträgen“.
]]

-- gespeicherte Objekt-Art » Schloss-Art der Client-Tabelle (ClientData.LOCK_KIND); Schwärme (pool) bewusst nicht
G.LOCK_KIND_OF = { herb = "herb", mine = "mining", chest = "lockpicking" }
-- Sammelberufe je Art (skillLine aus GetProfessionInfo; Nummern des Clients, sprachfrei – Kräuterkunde 182, Bergbau
-- 186, Angeln 356, Kürschnerei 393; Datenkatalog 7.3, wago.tools wowf SkillLine). Die eine Liste der Berufe;
-- G.SKILL_LINE_OF leitet sich daraus ab (Welle 27, SSOT). tools/gegenpruefung.lua liest sie aus dieser Datei.
G.PROFESSION_LINES = { herb = 182, ore = 186, fish = 356, skin = 393 }
-- Schlossknacken ist kein Beruf (fehlt in KnowledgeData.PROFESSIONS): Linie und Name als Rückfall, wenn der Client
-- ihn nicht nennt (Linie 633 laut wago.tools wowf SkillLine; englisch laut SkillLine, deutsch Name im deutschen Client)
G.LOCKPICKING = { line = 633, de = "Schlossknacken", en = "Lockpicking" }
-- Fertigkeitslinie je öffentlicher Art: die Berufe aus G.PROFESSION_LINES, dazu chest = Schlossknacken
G.SKILL_LINE_OF = { chest = G.LOCKPICKING.line }
for kind, line in pairs(G.PROFESSION_LINES) do G.SKILL_LINE_OF[kind] = line end
local LINE_KIND = {}
for kind, line in pairs(G.SKILL_LINE_OF) do LINE_KIND[line] = kind end

local function Bounds(skill)
    local req, lo, hi = Core.Num(skill.req), Core.Num(skill.lo), Core.Num(skill.hi)
    if req then return req, "client" end
    if hi then
        local need = hi + 1
        if lo and lo < need then need = lo end
        return need, "seen"
    end
    if lo then return lo, "upto" end
    return nil
end

-- Genau eine Schloss-Stufe zwischen größtem Fehlschlag (ausgeschlossen) und kleinster Ernte (eingeschlossen)? → Stufe
local function Narrow(lockKind, lo, hi)
    local CD = Core.ClientData
    if not (lockKind and lo and CD and CD.LockStages) then return nil end
    local hit
    for _, stage in ipairs(CD.LockStages(lockKind)) do
        if stage <= lo and (not hi or stage > hi) then
            if hit then return nil end
            hit = stage
        end
    end
    return hit
end
G.NarrowByLocks = Narrow

-- SAM-04: benötigte Fertigkeit eines Objekts. → Rang, Herkunft, { cnt, kind, lock, locks, stage } oder nil
function G.Required(objectID)
    local DB = DBReady()
    local row = DB and DB.Get("obj", objectID)
    local skill = type(row) == "table" and type(row.skill) == "table" and row.skill or nil
    if not skill then return nil end
    local need, how = Bounds(skill)
    if not need then return nil end
    local lockKind = G.LOCK_KIND_OF[row.kind]
    local info = { cnt = Core.Num(skill.cnt), kind = G.KIND_PUBLIC[row.kind] or row.kind, lock = lockKind }
    if how ~= "client" then
        local stage = Narrow(lockKind, Core.Num(skill.lo), Core.Num(skill.hi))
        if stage then need, how = stage, "tables" end
    end
    if lockKind and (how == "client" or how == "tables") then
        local CD = Core.ClientData
        info.locks = CD and CD.LocksAt and CD.LocksAt(lockKind, need) or nil
        info.stage = info.locks ~= nil   -- die Zahl ist eine Stufe der Client-Tabelle (sonst: Forever weicht ab)
    end
    return need, how, info
end

-- Welle 26 (F4, Paket kern/wago-wissen): nötige Fertigkeit eines Schlosses laut Client-Tabellen (Lock/LockType,
-- ezCore.ClientData.LockSkill). Welches Spielobjekt welches Schloss hat, weiß nur der Server – nutzbar erst mit einer
-- selbst erhobenen Schloss-Kennung je Objekt (offen, docs/roadmap/ezCore.md). → Rang, Art ("herb" | "mining" |
-- "fishing" | "lockpicking"), Quelle ("tables") oder nil
function G.RequiredByLock(lockID)
    local CD = Core.ClientData
    local list = CD and CD.LockSkill and CD.LockSkill(lockID)
    local e = list and list[1]
    if not e then return nil end
    return e.skill, e.kind, "tables"
end

-- Welle 27: Name einer Fertigkeit in der Sprache des Clients (art: herb, ore, fish, skin, chest) – zuerst der Client
-- (Berufe, Fertigkeitenliste), sonst der Name aus KnowledgeData.PROFESSIONS bzw. G.LOCKPICKING
local function ClientSkillName(line)
    local P = Core.Professions
    if P and P.Read then
        local ok, list = pcall(P.Read)
        for _, prof in ipairs(ok and type(list) == "table" and list or {}) do
            if prof.line == line and type(prof.name) == "string" and prof.name ~= "" then return prof.name end
        end
    end
    local lines = Core.SkillLines and Core.SkillLines(200)
    for _, l in ipairs(type(lines) == "table" and lines or {}) do
        if l.id == line and type(l.name) == "string" and l.name ~= "" then return l.name end
    end
    return nil
end

local function FixedSkillNames(line)
    if line == G.LOCKPICKING.line then return G.LOCKPICKING.de, G.LOCKPICKING.en end
    local KD = ns.KnowledgeData
    for _, p in ipairs(KD and type(KD.PROFESSIONS) == "table" and KD.PROFESSIONS or {}) do
        if p.skillLine == line then return p.de, p.en end
    end
    return nil
end

-- Rest b aus dem Review zu kern/sammel-fertigkeit: der Name je Linie wird gemerkt (G.SkillName läuft je Tooltip einer
-- Kiste oder eines Schwarms; vorher las jeder Aufruf Berufe und Fertigkeitenliste). false: kein Name bekannt.
local nameOfLine = {}
function G.SkillName(kind)
    kind = PUBLIC_ALIAS[kind] or kind
    local line = G.SKILL_LINE_OF[kind]
    if not line then return nil end
    local name = nameOfLine[line]
    if name == nil then
        name = ClientSkillName(line)
        if not name then
            local de, en = FixedSkillNames(line)
            name = Core.IsGerman and Core.IsGerman() and de or en or de
        end
        nameOfLine[line] = name or false
    end
    return name or nil
end

-- Name eines Berufs aus einer Client-Meldung oder Tooltip-Zeile » öffentliche Art (herb, ore, fish, skin, chest) oder
-- nil. Index einmal gebaut (Namen des Clients und beide Sprachen der festen Namen); G.ForgetSkillNames baut neu – auch
-- die gemerkten Namen von G.SkillName.
local skillNames
function G.ForgetSkillNames()
    skillNames = nil
    nameOfLine = {}
end
-- neue Berufe bringen neue Namen des Clients (andere Sprachen als deutsch und englisch kennt nur der Client); die
-- Fertigkeitenliste (Schlossknacken) meldet sich mit SKILL_LINES_CHANGED
Core.Listen("PROFESSIONS_CHANGED", function() G.ForgetSkillNames() end, "ezCore.Gathering.skillNames")
ns.On("SKILL_LINES_CHANGED", function() G.ForgetSkillNames() end)
function G.KindOfSkillName(name)
    if Core.IsSecret(name) or type(name) ~= "string" then return nil end
    name = Core.Trim(name)   -- Core.Trim (Gesamtreview 18.11.2026, T16-15)
    if name == "" then return nil end
    if not skillNames then
        skillNames = {}
        local function Add(text, line)
            if type(text) == "string" and not Core.IsSecret(text) and text ~= "" and LINE_KIND[line] then
                skillNames[text:lower()] = LINE_KIND[line]
            end
        end
        for _, line in pairs(G.SKILL_LINE_OF) do
            local de, en = FixedSkillNames(line)
            Add(de, line)
            Add(en, line)
            Add(ClientSkillName(line), line)
        end
    end
    return skillNames[name:lower()]
end

-- Wortlaut einer nötigen Fertigkeit samt Quelle (Leitlinie 11): „ab 125, laut Client-Meldung“, mit Zahl der eigenen
-- Beobachtungen „… (bei dir 3×)“; Kisten und Schwärme nennen den Beruf davor („Schlossknacken ab 75 …“).
-- named = false: ohne Beruf (Kürschnern hat seine eigene Zeile)
function G.NeedText(rank, how, cnt, kind, named)
    rank, cnt = Core.Num(rank), Core.Num(cnt)
    if not (rank and G.SKILL_HOWS[how]) then return nil end
    local text
    if cnt and cnt > 0 and how ~= "estimated" then
        text = L["GATHER_SKILL_" .. how .. "_n"]:format(rank, cnt)
    else
        text = L["GATHER_SKILL_" .. how]:format(rank)
    end
    kind = PUBLIC_ALIAS[kind] or kind
    if named ~= false and (kind == "chest" or kind == "fish") then
        local name = G.SkillName(kind)
        if name then text = L.GATHER_SKILL_NAMED:format(name, text) end
    end
    return text
end
G.SKILL_HOWS = { client = true, tables = true, seen = true, upto = true, estimated = true }

function G.SkillText(objectID)
    local rank, how, info = G.Required(objectID)
    if not rank then return nil end
    return G.NeedText(rank, how, info and info.cnt, info and info.kind)
end

-- Schließkassetten (Gegenstände mit Schloss): nötige Fertigkeit laut Client-Tabellen (ClientData.ItemLockSkill)
-- → Rang, "lockpicking", "tables" oder nil
function G.RequiredItem(itemID)
    local CD = Core.ClientData
    local list = CD and CD.ItemLockSkill and CD.ItemLockSkill(itemID)
    for _, e in ipairs(list or {}) do
        if e.kind == "lockpicking" then return e.skill, e.kind, "tables" end
    end
    return nil
end

-- Kürschnern hängt nicht an einem Schloss, sondern am Gegner: npc[npcID].skill (Form wie obj.skill).
-- Schätzung aus der Stufe des Gegners (REGEL, berechnet, nicht vom Client gemeldet): Faustregel der klassischen
-- Fassung (Wowpedia, „Skinning“) – bis Stufe 10 Fertigkeit 1, bis Stufe 20 (Stufe − 10) × 10, darüber Stufe × 5.
-- Gilt nur als „geschätzt“; jede Beobachtung geht vor. Im Forever-Client gegenprüfen (Spieltest ezCore).
G.SKIN_RULE = { flat = 10, mid = 20, midStep = 10, high = 5 }
function G.SkinEstimate(level)
    level = Core.Num(level)
    if not level or level < 1 then return nil end
    local r = G.SKIN_RULE
    if level <= r.flat then return 1 end
    if level <= r.mid then return (level - r.flat) * r.midStep end
    return level * r.high
end

-- Gegner, deren Tooltip in dieser Sitzung „kürschnerbar“ zeigte (Blizzards UNIT_SKINNABLE_LEATHER; Discovery.lua)
local skinnable, skinnableN = {}, 0
function G.NoteSkinnable(npcID)
    npcID = Core.Num(npcID)
    if not npcID or skinnable[npcID] then return end
    if skinnableN >= 500 then skinnable, skinnableN = {}, 0 end
    skinnable[npcID], skinnableN = true, skinnableN + 1
end

-- → Rang, Herkunft ("client" | "seen" | "upto" | "estimated"), { cnt, kind = "skin", level } oder nil.
-- level: Stufe des Gegners (sonst die gesehene Stufe aus npc.lvls); geschätzt wird nur bei einem Gegner, der schon
-- bei dir gekürschnert wurde (drops skin) oder dessen Tooltip „kürschnerbar“ zeigte.
function G.SkinRequired(npcID, level)
    local DB = DBReady()
    npcID = Core.Num(npcID)
    if not (DB and npcID) then return nil end
    local row = DB.Get("npc", npcID)
    local skill = type(row) == "table" and type(row.skill) == "table" and row.skill or nil
    if skill then
        local need, how = Bounds(skill)
        if need then return need, how, { cnt = Core.Num(skill.cnt), kind = "skin" } end
    end
    -- Rest b: „schon gekürschnert?“ ohne Kopie des Beute-Satzes (DB.Get kopiert tief) – DB.KeysOf nennt nur die
    -- Felder des Satzes, leer heißt: kein Satz
    if not (skinnable[npcID] or #DB.KeysOf("drops", "skin", npcID) > 0) then return nil end
    level = Core.Num(level)
    if not level then
        local lvls = type(row) == "table" and type(row.lvls) == "table" and row.lvls or nil
        level = lvls and (Core.Num(lvls.hi) or Core.Num(lvls.lo)) or nil
    end
    local est = G.SkinEstimate(level)
    if not est then return nil end
    return est, "estimated", { kind = "skin", level = level }
end

-- Zeile „Kürschnern: ab 125, laut Client-Meldung“ für den Gegner-Tooltip (ezLoot) in der Farbe für die eigene
-- Kürschnerei (G.SkillColor; ohne Beruf grau „unbekannt“). → { { text, r, g, b } } oder {}
function G.SkinLines(npcID, level)
    local need, how, info = G.SkinRequired(npcID, level)
    if not need then return {} end
    local text = G.NeedText(need, how, info and info.cnt, "skin", false)
    local rank = Core.Num(G.OwnRank("skin"))
    -- Rest f: „kannst du es?“ (rot, „(du: …)“) mit dem Rang samt Bonus, gegen den der Client prüft; die Farbe der Chance
    -- auf einen Punkt bleibt beim Rang ohne Bonus (wie G.SkillUp)
    local eff = Core.Num(G.OwnRank("skin", true))
    if not (eff and rank and eff >= rank) then eff = rank end
    local color = rank and rank > 0 and G.SkillColor(need, rank) or "unknown"
    if color == "red" and eff >= need then color = "orange" end
    -- nur eine obere Schranke: „noch nicht“ geben die Daten nicht her (wie G.SkillUp)
    if color == "red" and how == "upto" then color = "unknown" end
    if color == "red" then text = L.GATHER_SKIN_YOU:format(text, eff) end
    local r, g, b = G.SkillRGB(color)
    return { { text = L.GATHER_SKIN_LINE:format(text), r = r, g = g, b = b, color = color } }
end

-- Alle eigenen Punkte, die auf der Karte mapID liegen (Speicherkarte direkt, andere über Weltkoordinaten)
local function Collect(DB, m, mapID)
    local hit = m.maps[mapID]
    if hit then return hit end
    local out = {}
    local Map = Core.Map
    local convertible = Map and Map.WorldPos and Map.WorldPos(mapID, 0.5, 0.5) ~= nil
    for _, store in ipairs(DB.KeysOf("spot")) do
        local direct = store == mapID
        if direct or (convertible and Core.Num(store) and store > 0) then
            for _, sk in ipairs({ "object", "fishing" }) do
                for _, id in ipairs(DB.KeysOf("spot", store, sk)) do
                    local stored = sk == "fishing" and "fishing" or StoredKind(DB, m, id)
                    -- Quest-Objekte und neutrale Behälter (Welle 13) sind keine Sammelknoten: nicht in Nodes. Ein
                    -- Fundort ohne obj-Satz bleibt wie bisher eine Kiste (Altbestand, wie Core.Finds.IsGatherObject).
                    local keep = sk == "fishing" or stored == nil or G.KIND_PUBLIC[stored]
                    local list = keep and DB.Get("spot", store, sk, id) or nil
                    for _, el in ipairs(list or {}) do
                        local x, y = DB.Keys.Unpack(el.xy)
                        local sx, sy = x, y
                        if x and not direct then x, y = Map.PosOn(mapID, store, x, y) end
                        if x then
                            out[#out + 1] = { id = id, sx = sx, sy = sy,
                                kind = G.KIND_PUBLIC[stored] or (sk == "fishing" and "fish") or "chest",
                                stored = stored, map = store, x = x, y = y, cnt = el.cnt, t = el.t,
                                fallback = DB.Keys.IsFallback(id) and sk == "object" or nil,
                                explorer = stored == "chest" or nil,
                                src = el.src == "backup" and "backup" or nil }
                        end
                    end
                end
            end
        end
    end
    m.maps[mapID] = out
    return out
end

local function Pass(node, filter, explorer, wantItem, wantFish)
    if node.explorer and not explorer then return false end
    if filter.kind and node.kind ~= (PUBLIC_ALIAS[filter.kind] or filter.kind) then return false end
    if node.stored == "fishing" then
        -- Welle 23c (A37): Angelplätze, deren Gebiet den Gegenstand schon gegeben hat
        if wantFish and not (wantFish[node.map] and wantFish[node.map][node.id]) then return false end
    elseif wantItem and not wantItem[node.id] then
        return false
    end
    local rank = Core.Num(filter.skill)
    if rank and node.stored ~= "fishing" then
        -- Entscheidung des Nutzers vom 16.11.2026 (Nr. 36): nur ein sicher bekannter Wert („client“ laut Client, „seen“
        -- bei dir beobachtet) blendet aus. „upto“ ist nur eine obere Schranke aus der Ernte eines Charakters mit
        -- höherem Rang – das Vorkommen kann sammelbar sein und bleibt sichtbar (wie G.SkillUp: „unbekannt“)
        local need, how = G.Required(node.id)
        if need and how ~= "upto" and need > rank then return false end
    end
    return true
end

function G.Nodes(mapID, filter)
    local DB = DBReady()
    mapID = Core.Num(mapID)
    if not (DB and mapID) then return {} end
    filter = type(filter) == "table" and filter or {}
    local m = Mem(DB)
    local explorer = filter.explorer == true or DB.Explorer()
    local wantItem = filter.item and G.ObjectsFor(filter.item) or nil
    local wantFish = filter.item and G.FishAreasFor(filter.item) or nil
    local out = {}
    for _, node in ipairs(Collect(DB, m, mapID)) do
        if Pass(node, filter, explorer, wantItem, wantFish) then
            local copy = {}
            for k, v in pairs(node) do copy[k] = v end
            out[#out + 1] = copy
        end
    end
    return out
end

function G.Near(mapID, x, y, radius, filter)
    x, y, radius = Core.Num(x), Core.Num(y), Core.Num(radius)
    local D = Core.Discovery
    local w, h
    if D and D.MapYards then w, h = D.MapYards(mapID) end
    if not (w and x and y and radius) then return {}, "nosize" end
    local out = {}
    for _, node in ipairs(G.Nodes(mapID, filter)) do
        local d = math.sqrt(((node.x - x) * w) ^ 2 + ((node.y - y) * h) ^ 2)
        if d <= radius then
            node.yards = d
            out[#out + 1] = node
        end
    end
    table.sort(out, function(a, b) return a.yards < b.yards end)
    return out
end

function G.Kinds()
    local DB = DBReady()
    local counts = {}
    if DB then
        for _, id in ipairs(DB.KeysOf("obj")) do
            local row = DB.Get("obj", id)
            local k = type(row) == "table" and G.KIND_PUBLIC[row.kind]
            if k and (k ~= "chest" or DB.Explorer()) then counts[k] = (counts[k] or 0) + 1 end
        end
        for _, store in ipairs(DB.KeysOf("spot")) do
            for _, area in ipairs(DB.KeysOf("spot", store, "fishing")) do
                counts.fish = (counts.fish or 0) + #(DB.Get("spot", store, "fishing", area) or {})
            end
        end
    end
    local out = {}
    for _, k in ipairs(G.KIND_ORDER) do
        if counts[k] then out[#out + 1] = { kind = k, label = L["GATHER_KIND_" .. k], count = counts[k] } end
    end
    return out
end

-- Welle 23c (A36, A38): Gegenstände der eigenen Ernten mit Art. Objekte (drops object; Art aus obj, ein Objekt ohne
-- obj-Satz gilt wie in Collect als Kiste, Quest-Objekte und Behälter zählen nicht), Angeln (drops fishing) und
-- Kürschnern (drops skin). Kisten nur mit Entdecker-Wissen.
local function ItemList(DB, m)
    if m.list then return m.list end
    local byKey, list = {}, {}
    local function Add(kind, item, n, objectID)
        item = Core.Num(item)
        if not item then return end
        local key = kind .. ":" .. item
        local e = byKey[key]
        if not e then
            e = { item = item, kind = kind, harvests = 0, sources = 0, seen = {} }
            byKey[key] = e
            list[#list + 1] = e
        end
        e.harvests = e.harvests + (Core.Num(n) or 0)
        local src = objectID or "-"
        if not e.seen[src] then
            e.seen[src] = true
            e.sources = e.sources + 1
        end
        if objectID then
            local need, how = G.Required(objectID)
            if need and (not e.need or need < e.need) then e.need, e.needHow = need, how end
        end
    end
    local function Blocks(row, fn)
        for _, b in pairs(type(row) == "table" and type(row.diff) == "table" and row.diff or {}) do
            for item, it in pairs(type(b) == "table" and type(b.items) == "table" and b.items or {}) do
                fn(item, type(it) == "table" and it.f or 0)
            end
        end
    end
    for _, id in ipairs(DB.KeysOf("drops", "object")) do
        local stored = StoredKind(DB, m, id)
        local kind = stored == nil and "chest" or G.KIND_PUBLIC[stored]
        if kind then Blocks(DB.Get("drops", "object", id), function(item, f) Add(kind, item, f, id) end) end
    end
    for _, map in ipairs(DB.KeysOf("drops", "fishing")) do
        for _, area in ipairs(DB.KeysOf("drops", "fishing", map)) do
            Blocks(DB.Get("drops", "fishing", map, area), function(item, f) Add("fish", item, f, nil) end)
        end
    end
    for _, npc in ipairs(DB.KeysOf("drops", "skin")) do
        Blocks(DB.Get("drops", "skin", npc), function(item, f) Add("skin", item, f, nil) end)
    end
    for _, e in ipairs(list) do e.seen = nil end
    table.sort(list, function(a, b)
        if a.harvests ~= b.harvests then return a.harvests > b.harvests end
        if a.kind ~= b.kind then return a.kind < b.kind end
        return a.item < b.item
    end)
    m.list = list
    return list
end

function G.Items(kind)
    local DB = DBReady()
    if not DB then return {} end
    kind = kind and (PUBLIC_ALIAS[kind] or kind)
    local explorer = DB.Explorer()
    local out = {}
    for _, e in ipairs(ItemList(DB, Mem(DB))) do
        if (kind == nil or e.kind == kind) and (e.kind ~= "chest" or explorer) then
            out[#out + 1] = { item = e.item, kind = e.kind, harvests = e.harvests, sources = e.sources, need = e.need,
                needHow = e.needHow }
        end
    end
    return out
end

function G.ItemsOf(kind)
    if type(kind) ~= "string" then return {} end
    return G.Items(kind)
end

-- Vergessen (nur über sichtbare Knöpfe mit Rückfrage – die baut ezMap): opts.id = ein Objekt überall (obj, drops,
-- Orte), opts.map = alle eigenen Fundorte einer Speicherkarte, mit opts.kind nur eine Art. → Zahl entfernter Datensätze
-- (obj, drops, je Karte die Liste der Fundorte eines Objekts – nicht einzelne Punkte; die zählen ForgetKind/ForgetZone)
-- Welle 23c (A34): die eine Stelle eines Objekts (bzw. Angel-Gebiets) im Umkreis von (x, y) auf der Speicherkarte
local function ForgetOne(DB, opts)
    local map, x, y = Core.Num(opts.map), Core.Num(opts.x), Core.Num(opts.y)
    local kind = opts.kind and (PUBLIC_ALIAS[opts.kind] or opts.kind)
    local sk = kind == "fish" and "fishing" or "object"
    local yards = Core.Num(opts.yards) or G.JUST_YARDS
    local D = Core.Discovery
    local w, h
    if D and D.MapYards then w, h = D.MapYards(map) end
    local best, bestD
    for i, el in ipairs(DB.Get("spot", map, sk, opts.id) or {}) do
        local ex, ey = DB.Keys.Unpack(type(el) == "table" and el.xy or nil)
        if ex then
            local d, near
            if w then
                d = math.sqrt(((ex - x) * w) ^ 2 + ((ey - y) * h) ^ 2)
                near = d <= yards
            else
                d = math.max(math.abs(ex - x), math.abs(ey - y))
                near = d < 0.01
            end
            if near and (not bestD or d < bestD) then best, bestD = i, d end
        end
    end
    if not best then return 0 end
    local changed = DB.Change("spot", { map, sk, opts.id }, function(row)
        table.remove(row, best)
        if #row == 0 then return "delete" end
    end)
    return changed and 1 or 0
end

function G.Forget(opts)
    local DB = DBReady()
    if not (DB and type(opts) == "table") then return 0 end
    local n = 0
    if opts.id ~= nil and Core.Num(opts.map) and Core.Num(opts.x) and Core.Num(opts.y) then
        n = ForgetOne(DB, opts)
    elseif opts.id ~= nil then
        n = n + DB.Forget("obj", opts.id) + DB.Forget("drops", "object", opts.id)
        for _, store in ipairs(DB.KeysOf("spot")) do n = n + DB.Forget("spot", store, "object", opts.id) end
    elseif Core.Num(opts.map) then
        local want = opts.kind and (PUBLIC_ALIAS[opts.kind] or opts.kind)
        if want == nil or want == "fish" then n = n + DB.Forget("spot", opts.map, "fishing") end
        if want == nil then
            n = n + DB.Forget("spot", opts.map, "object")
        else
            for _, id in ipairs(DB.KeysOf("spot", opts.map, "object")) do
                local row = DB.Get("obj", id)
                local k = type(row) == "table" and G.KIND_PUBLIC[row.kind]
                if k == want then n = n + DB.Forget("spot", opts.map, "object", id) end
            end
        end
    end
    if n > 0 then
        mem = { ver = nil, kinds = {}, items = nil, maps = {} }
        G.ClearCache()
        Core.Fire("GATHERING_CHANGED", opts.map)
    end
    return n
end

Core.Listen("DB_CHANGED", function(name)
    if name == "spot" or name == "obj" then
        cache = {}
        Core.Fire("GATHERING_CHANGED")
    end
end, "ezCore.Gathering")
Core.RegisterMessage("GATHERING_CHANGED", "Gathering.lua", "Eigene Sammel-Fundorte oder Objekte haben sich geändert (neue Ernte, Vergessen); höchstens einmal je Bild.", "mapID | nil")

---------------------------------------------------------------------------
-- Sichtbarkeit je Art und Fläche (SAM-08, Welle 13)
---------------------------------------------------------------------------
--[[
    G.Visible(art, fläche)       → true/false, Grund ("explorer" | "never" | "profession" | "tracking" | "kind")
        art: herb, ore, fish, chest, treasure, rare, book; fläche: "map" (Weltkarte) oder "minimap"
    G.Visibility(art, fläche)    → Modus: "always" (immer), "profession" (mit Beruf), "tracking" (bei aktiver Suche aus
                                   dem Menü „Aufspüren“), "never" (nie)
    G.SetVisibility(art, fläche, modus) → true; Nachricht GATHERING_VISIBILITY (art, fläche, modus)
    G.HasProfession(art), G.Tracking(art) → bool
    Wissen an EINER Stelle (Leitlinie 11): Kräuter, Erze und Angeln sind Nachschlage-Wissen (G.KNOWLEDGE "lookup"),
    Kisten, Schätze, seltene Gegner und Bücher Entdecker-Wissen ("explorer") – sie zeigt nur der Schalter
    „Entdecker-Wissen“ (OPT_explorer, DB.Explorer(), ab Werk aus), gleich welcher Modus gilt. Quest-Objekte und neutrale
    Behälter (quest, container) sind keine Sammelknoten und nie sichtbar.
    Die Schalter je Art zeigt ezMap im Filtermenü der Karte und im Menü „Aufspüren“ (SAM-10, Welle 14); ezCore hält
    nur Modus und Regel.
]]
G.KNOWLEDGE = { herb = "lookup", ore = "lookup", fish = "lookup", chest = "explorer", treasure = "explorer",
    rare = "explorer", book = "explorer" }
G.VISIBILITY_MODES = { "always", "profession", "tracking", "never" }
G.SURFACES = { map = true, minimap = true }
-- Sammelberufe je Art: G.PROFESSION_LINES steht seit Welle 27 weiter oben (vor G.SKILL_LINE_OF). Dazu der Schlüssel
-- des Berufs in Core.Knowledge (KnowledgeData.PROFESSIONS) für den Rückfall aus der Fertigkeitenliste.
G.PROFESSION_KEYS = { herb = "herbalism", ore = "mining", fish = "fishing", skin = "skinning" }
-- skin (Kürschnerei 393, Welle 23c, A38): nur Beruf und Rang (G.OwnRank) und Rohstoffe je Art (G.ItemsOf("skin"));
-- Kürschnern hat keine Fundorte, darum keine Sichtbarkeit und keine Art in G.KNOWLEDGE.
-- Suche im Menü „Aufspüren“ (C_Minimap.GetTrackingInfo(i).spellID, laut Blizzards MinimapDocumentation nilbar):
-- klassische Zauber-Nummern Kräutersuche 2383 und Mineraliensuche 2580 – im Spiel NICHT gelesen (Probe A17 zeigte nur
-- Dienstleister); ohne spellID gilt der Name des Zaubers (Core.SpellName). Für Angeln gibt es keine Suche: „tracking“
-- verhält sich dort wie „profession“.
G.TRACKING_SPELLS = { herb = 2383, ore = 2580 }

local VIS_DEFAULTS = {}
for kind, knowledge in pairs(G.KNOWLEDGE) do
    VIS_DEFAULTS["map_" .. kind] = knowledge == "lookup" and "profession" or "always"
    VIS_DEFAULTS["minimap_" .. kind] = knowledge == "lookup" and (kind == "fish" and "never" or "tracking") or "always"
end
Core.OwnDefaults("gatherVis", VIS_DEFAULTS)

local VALID_MODE = { always = true, profession = true, tracking = true, never = true }
do -- erlaubte Modi für eingefügte Texte (Core.ImportAll, Gegenprüfung zu T6-2)
    local modes, choices = { "always", "profession", "tracking", "never" }, {}
    for key in pairs(VIS_DEFAULTS) do choices[key] = modes end
    Core.OwnRules("gatherVis", { choices = choices })
end

function G.Visibility(kind, surface)
    kind = PUBLIC_ALIAS[kind] or kind
    if not (G.KNOWLEDGE[kind] and G.SURFACES[surface]) then return nil end
    local mode = Core.OwnSetting("gatherVis", surface .. "_" .. kind)
    return VALID_MODE[mode] and mode or VIS_DEFAULTS[surface .. "_" .. kind]
end

function G.SetVisibility(kind, surface, mode)
    kind = PUBLIC_ALIAS[kind] or kind
    if not (G.KNOWLEDGE[kind] and G.SURFACES[surface] and VALID_MODE[mode]) then return false end
    local tbl = Core.OwnSettings("gatherVis")
    if not tbl then return false end
    tbl[surface .. "_" .. kind] = mode
    Core.Fire("GATHERING_VISIBILITY", kind, surface, mode)
    return true
end

-- Rang des eigenen Sammelberufs (eine Abfrage für Core.Gathering und Core.Discovery): zuerst live GetProfessions
-- (Core.Professions.Read), sonst die gespeicherten Berufe des Charakters samt Rückfall aus der Fertigkeitenliste
-- (Core.Knowledge.CharProfs, src = "skill") – auf Forever liefert GetProfessions teils nichts (Professions.lua).
-- → Rang (Zahl, 0 wenn unbekannt) oder nil ohne Beruf. effective: Rang samt Bonus (Handschuhe, Volk – mod laut
-- Client), gegen den der Client das Schloss prüft; die gespeicherten Berufe kennen keinen Bonus (dann ohne). Discovery
-- schreibt Schranken nur mit effective (Fund des code-reviewers vor dem Merge, 16.11.2026: sonst lagen „ab“ und
-- „höchstens“ um den Bonus zu niedrig und die Eingrenzung über die Schloss-Stufen traf eine Stufe zu tief).
function G.OwnRank(kind, effective)
    kind = PUBLIC_ALIAS[kind] or kind
    if kind == "chest" then
        -- Welle 27 (F4 b): Schlossknacken ist kein Beruf – nur die Fertigkeitenliste nennt den Rang (Linie 633, sonst
        -- über den Namen); nil, wenn der Charakter es nicht kann
        local lines = Core.SkillLines and Core.SkillLines(200)
        for _, l in ipairs(type(lines) == "table" and lines or {}) do
            if l.id == G.LOCKPICKING.line or (l.id == nil and G.KindOfSkillName(l.name) == "chest") then
                return (Core.Num(l.rank) or 0) + (effective and Core.Num(l.mod) or 0)
            end
        end
        return nil
    end
    local line, key = G.PROFESSION_LINES[kind], G.PROFESSION_KEYS[kind]
    if not line then return nil end
    local P = Core.Professions
    if P and P.Read then
        local ok, list = pcall(P.Read)
        for _, prof in ipairs(ok and type(list) == "table" and list or {}) do
            if prof.line == line then return (Core.Num(prof.rank) or 0) + (effective and Core.Num(prof.mod) or 0) end
        end
    end
    local K = Core.Knowledge
    local map = K and K.CharProfs and Core.charKey and K.CharProfs(Core.charKey)
    local rank = type(map) == "table" and map[key]
    if rank ~= nil and rank ~= false then return Core.Num(rank) or 0 end
    return nil
end

function G.HasProfession(kind)
    return G.OwnRank(kind) ~= nil
end

---------------------------------------------------------------------------
-- Farbe und Chance auf einen Fertigkeitspunkt beim Sammeln (Wunsch des Nutzers vom 15.11.2026 abends: „nach grau,
-- weiß grün, gelb, orange filtern können --> also was gibt mir mit wieviel wahrscheinlichkeit einen skillpunkt“)
---------------------------------------------------------------------------
--[[
    REGEL (berechnet, nicht vom Client gemeldet): allgemeine Spielmechanik der klassischen Sammelberufe Kräuterkunde
    und Bergbau. Ein Vorkommen, das die Fertigkeit R verlangt, ist für einen Charakter mit Fertigkeit F
        rot      F < R              noch nicht sammelbar
        orange   R ≤ F < R + 25     Punkt sicher
        gelb     R + 25 ≤ F < R + 50
        grün     R + 50 ≤ F < R + 100
        grau     F ≥ R + 100        nie ein Punkt
    Zwischen gelb und grau fällt die Chance gleichmäßig: (grau − F) / (grau − gelb) – dieselbe Faustformel, die für
    Rezepte gilt (Wowpedia, „Profession“ und „Skill“; Abstände 25/50/100 bei Kräuterkunde und Bergbau, Spielerwissen
    der klassischen Fassung). ezCore liest weder Abstände noch Chance aus dem Client: im Forever-Client gegenprüfen
    (Spieltest – zeigt Blizzards Tooltip am Vorkommen den Wert in Farbe, muss sie zu dieser passen; Punkte je Ernte
    zählen). Weicht Forever ab, ändern sich nur G.SKILL_STEPS bzw. G.SkillUpChance – die Texte (GATHER_SKILLUP_HOW
    hier, die Tooltips der Farb-Filter in ezMap/Locale.lua über ns.FillSkillSteps) setzen die Grenzen daraus ein.
    Rezepte (ezCraft) haben eigene Grenzen je Rezept aus dem Client (Knowledge.SkillStages, recipeObs.stages) – dort
    gilt NICHT diese Regel, wohl aber dieselbe Formel der Chance: G.SkillUpChance(F, gelb, grau) nimmt beliebige
    Grenzen.
    Nötiger Wert R aus G.Required (SAM-04): „client“ genau (laut Client-Meldung), „seen“ untere Schranke aus einem
    Fehlschlag (bei dir beobachtet), „upto“ obere Schranke aus einer Ernte (der Wert ist höchstens so groß – die
    Farbe kann grauer sein). Eigene Fertigkeit aus G.OwnRank (live GetProfessions, sonst die gespeicherten Berufe).

      G.SkillColor(R, F)           → Farbe ("red" | "orange" | "yellow" | "green" | "gray" | "unknown"), Grenzen
                                     { need, yellow, green, gray } (ohne R oder F: "unknown", nil)
      G.SkillUpChance(F, gelb, grau) → 0 bis 1 (unter gelb 1, ab grau 0) oder nil
      G.SkillUp(objectID, art, F?, Fb?) → { color, chance, need, how, rank, effective, yellow, green, gray, bound,
                                     reason }; art: herb, ore, fish (Kisten: nil); F nimmt G.OwnRank(art), Fb (Rang
                                     samt Bonus, entscheidet rot) G.OwnRank(art, true), wenn F nicht gegeben ist.
                                     bound: "exact" (client) | "about" (seen) | "most" (upto); reason bei "unknown"
                                     bzw. "red": "noneed" (R unbekannt) | "norank" (F unbekannt) | "fish" (Angelplätze
                                     verlangen keinen Wert) | "noprof" (Beruf fehlt) | "low" (F < R) | "upto"
                                     (nur obere Schranke und F < R: der wahre Wert kann tiefer liegen, darum
                                     „unbekannt“ statt rot)
      G.SkillUpLines(info)         → { { text, r, g, b } … } – Zeile „Fertigkeitspunkt: …“ in der Farbe und die Quelle
      G.SkillRGB(farbe)            → r, g, b (Blizzards TradeSkillTypeColor, sonst dieselben Werte hier)
]]
G.SKILL_STEPS = { yellow = 25, green = 50, gray = 100 }
G.SKILL_COLORS = { "orange", "yellow", "green", "gray", "unknown" }    -- Reihenfolge der Filter; rot steht für sich
-- Farben wie Blizzards TradeSkillTypeColor (optimal, medium, easy, trivial, difficult); Rückfall, falls der Client die
-- Tabelle nicht kennt
local SKILL_RGB = { orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 }, green = { 0.25, 0.75, 0.25 },
    gray = { 0.5, 0.5, 0.5 }, red = { 1, 0.1, 0.1 }, unknown = { 0.6, 0.6, 0.6 } }
local BLIZZARD_SKILL = { orange = "optimal", yellow = "medium", green = "easy", gray = "trivial", red = "difficult" }

function G.SkillRGB(color)
    local blizz = rawget(_G, "TradeSkillTypeColor")
    local c = type(blizz) == "table" and BLIZZARD_SKILL[color] and blizz[BLIZZARD_SKILL[color]]
    if type(c) == "table" and Core.Num(c.r) and Core.Num(c.g) and Core.Num(c.b) then return c.r, c.g, c.b end
    c = SKILL_RGB[color] or SKILL_RGB.unknown
    return c[1], c[2], c[3]
end

function G.SkillColor(need, rank)
    need, rank = Core.Num(need), Core.Num(rank)
    if not (need and rank and rank > 0) then return "unknown", nil end
    local s = G.SKILL_STEPS
    local stages = { need = need, yellow = need + s.yellow, green = need + s.green, gray = need + s.gray }
    if rank < need then return "red", stages end
    if rank < stages.yellow then return "orange", stages end
    if rank < stages.green then return "yellow", stages end
    if rank < stages.gray then return "green", stages end
    return "gray", stages
end

function G.SkillUpChance(rank, yellow, gray)
    rank, yellow, gray = Core.Num(rank), Core.Num(yellow), Core.Num(gray)
    if not (rank and yellow and gray) then return nil end
    if rank >= gray then return 0 end
    if rank < yellow or gray <= yellow then return 1 end
    return (gray - rank) / (gray - yellow)
end

-- Welle 27: "tables" (Schloss-Stufe laut Client-Tabellen) ist genau wie die Client-Meldung
local BOUND = { client = "exact", tables = "exact", seen = "about", upto = "most", estimated = "about" }

-- Rest f aus dem Review zu kern/sammel-fertigkeit: effective = Rang samt Bonus (G.OwnRank(art, true)); er entscheidet
-- „kannst du es?“ (rot, „Noch nicht sammelbar … (du: …)“, „unbekannt“ bei einer oberen Schranke), denn dagegen prüft
-- der Client das Schloss. Farbe und Chance auf einen Fertigkeitspunkt rechnen mit dem Rang ohne Bonus (rank). Ohne
-- rank fragt G.SkillUp beide selbst; mit rank ohne effective gilt rank für beides (wie bisher).
function G.SkillUp(objectID, kind, rank, effective)
    kind = PUBLIC_ALIAS[kind] or kind
    if not G.PROFESSION_LINES[kind] then return nil end
    if kind == "fish" then return { color = "unknown", reason = "fish" } end
    if rank == nil then
        rank = G.OwnRank(kind)
        if effective == nil then effective = G.OwnRank(kind, true) end
    end
    if rank == nil or rank == false then return { color = "red", reason = "noprof" } end
    rank, effective = Core.Num(rank), Core.Num(effective)
    if not (effective and rank and effective >= rank) then effective = rank end
    local need, how = G.Required(objectID)
    local info = { need = need, how = how, rank = rank, effective = effective, bound = how and BOUND[how] or nil }
    if not need then
        info.color, info.reason = "unknown", "noneed"
        return info
    end
    if not (rank and rank > 0) then
        info.color, info.reason = "unknown", "norank"
        return info
    end
    local color, stages = G.SkillColor(need, rank)
    -- der Bonus reicht: sammelbar, und unter dem nötigen Wert ist ein Punkt sicher (orange)
    if color == "red" and effective >= need then color = "orange" end
    if color == "red" and info.bound == "most" then
        -- nur obere Schranke (jemand hat mit diesem Rang geerntet): der wahre Wert kann tiefer liegen – „noch nicht
        -- sammelbar“ geben die Daten nicht her
        info.color, info.reason = "unknown", "upto"
        return info
    end
    info.color = color
    info.yellow, info.green, info.gray = stages.yellow, stages.green, stages.gray
    if color == "red" then
        info.reason, info.chance = "low", 0
    else
        info.chance = G.SkillUpChance(rank, stages.yellow, stages.gray)
    end
    return info
end

function G.SkillUpLines(info)
    if type(info) ~= "table" or not info.color then return {} end
    local r, g, b = G.SkillRGB(info.color)
    local lines = {}
    local function add(text, lr, lg, lb) lines[#lines + 1] = { text = text, r = lr, g = lg, b = lb } end
    local color = info.color
    if color == "unknown" then
        if info.reason == "upto" and info.need and info.rank then
            add(L.GATHER_SKILLUP_UNKNOWN_upto:format(info.need, info.effective or info.rank), r, g, b)
        else
            add(L["GATHER_SKILLUP_UNKNOWN_" .. tostring(info.reason)] or L.GATHER_SKILLUP_UNKNOWN_noneed, r, g, b)
        end
        return lines
    end
    if color == "red" then
        if info.reason == "noprof" then
            add(L.GATHER_SKILLUP_NOPROF, r, g, b)
        else
            add(L.GATHER_SKILLUP_RED:format(info.need, info.effective or info.rank), r, g, b)
        end
    elseif color == "orange" then
        add(L.GATHER_SKILLUP_SURE:format(info.yellow - 1), r, g, b)
    elseif color == "gray" then
        add(L.GATHER_SKILLUP_NEVER:format(info.gray), r, g, b)
    else
        add(L.GATHER_SKILLUP_CHANCE:format(Core.Percent(math.floor((info.chance or 0) * 100 + 0.5)),
            L["GATHER_COLOR_" .. color], info.gray), r, g, b)
    end
    if info.rank and info.need then
        local s = G.SKILL_STEPS
        local how = L.GATHER_SKILLUP_HOW:format(info.rank, s.yellow - 1, s.green - 1, s.gray - 1)
        if info.bound == "most" then how = how .. " " .. L.GATHER_SKILLUP_BOUND_most:format(info.need)
        elseif info.bound == "about" then how = how .. " " .. L.GATHER_SKILLUP_BOUND_about:format(info.need) end
        add(how, 0.6, 0.6, 0.6)
    end
    return lines
end

local tracking   -- Art » true, solange die Suche läuft (nil = neu lesen)
local function ReadTracking()
    local state = {}
    local api = rawget(_G, "C_Minimap")
    if type(api) ~= "table" or type(api.GetNumTrackingTypes) ~= "function" or type(api.GetTrackingInfo) ~= "function" then
        return state
    end
    local names = {}
    for kind, spell in pairs(G.TRACKING_SPELLS) do
        local name = Core.SpellName and Core.SpellName(spell)
        if type(name) == "string" and name ~= "" then names[name] = kind end
    end
    local ok, n = pcall(api.GetNumTrackingTypes)
    for i = 1, ok and Core.Num(n) or 0 do
        local okI, info = pcall(api.GetTrackingInfo, i)
        if okI and type(info) == "table" and not Core.IsSecret(info) and info.active == true then
            local spell = Core.Num(info.spellID)
            for kind, id in pairs(G.TRACKING_SPELLS) do
                if spell == id then state[kind] = true end
            end
            local byName = type(info.name) == "string" and names[info.name]
            if byName then state[byName] = true end
        end
    end
    return state
end

function G.Tracking(kind)
    if not tracking then tracking = ReadTracking() end
    return tracking[PUBLIC_ALIAS[kind] or kind] == true
end

ns.On("MINIMAP_UPDATE_TRACKING", function()
    tracking = nil
    Core.Fire("GATHERING_VISIBILITY")
end)

function G.Visible(kind, surface)
    kind = PUBLIC_ALIAS[kind] or kind
    local knowledge = G.KNOWLEDGE[kind]
    if not knowledge then return false, "kind" end
    local mode = G.Visibility(kind, surface or "map")
    if not mode then return false, "kind" end
    if knowledge == "explorer" then
        local DB = Core.DB
        if not (DB and DB.Explorer and DB.Explorer()) then return false, "explorer" end
    end
    if mode == "never" then return false, "never" end
    if mode == "always" then return true end
    if mode == "tracking" and G.TRACKING_SPELLS[kind] then
        return G.Tracking(kind), "tracking"
    end
    if G.PROFESSION_LINES[kind] then return G.HasProfession(kind), "profession" end
    return true
end

Core.RegisterMessage("GATHERING_VISIBILITY", "Gathering.lua", "Sichtbarkeit der Sammel-Arten geändert (Modus je Art und Fläche oder die Suche im Menü „Aufspüren“).", "kind, surface, mode | nil")

---------------------------------------------------------------------------
-- Sitzung: eben geerntet und Sammel-Zähler (SAM-09, Welle 13)
---------------------------------------------------------------------------
--[[
    Discovery meldet jede eigene Ernte mit GATHERING_HARVEST ({ id, kind, map, items, harvest }).
    G.JustGathered(mapID)  → { { id, kind, map, x, y, t } … } eben geerntete Stellen dieser Sitzung (nur im
                             Arbeitsspeicher, höchstens G.JUST_MAX; fürs Abdunkeln auf Karte und Minikarte)
    G.WasJustGathered(id, mapID, x, y, maxAge) → true, wenn dieselbe Stelle in dieser Sitzung geerntet wurde; mit
                             maxAge (Sekunden, Welle 23c, A35) nur, wenn die Ernte höchstens so alt ist
    G.SessionStats()       → { harvests, kinds = { art = n }, items = { [itemID] = menge }, value, priced, start }
                             – Ernten, Ertrag und Wert (Marktwert aus Core.Prices) der Sitzung. Beginn und Reset kommen
                             von Core.Session (Session.Data("ezCore.gathering")), der Zähler übersteht /reload wie sie.
]]
G.JUST_MAX = 200
G.JUST_YARDS = 15
local just = {}

local function PlayerXY(map)
    if not (map and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not ok then return nil end
    return Core.Map.XY(pos)
end

local function Counter()
    local S = Core.Session
    return S and S.Data and S.Data("ezCore.gathering") or nil
end

function G.OnHarvest(info)
    if type(info) ~= "table" then return end
    local kind = PUBLIC_ALIAS[info.kind] or info.kind
    if not G.KNOWLEDGE[kind] then return end
    local map = Core.Num(info.map)
    if info.harvest ~= false then
        local x, y = PlayerXY(map)
        if #just >= G.JUST_MAX then table.remove(just, 1) end
        just[#just + 1] = { id = info.id, kind = kind, map = map, x = x, y = y, t = Core.Uptime() }
    end
    local c = Counter()
    if not c then return end
    if info.harvest ~= false then
        c.harvests = (Core.Num(c.harvests) or 0) + 1
        c.kinds = type(c.kinds) == "table" and c.kinds or {}
        c.kinds[kind] = (Core.Num(c.kinds[kind]) or 0) + 1
    end
    c.items = type(c.items) == "table" and c.items or {}
    for itemID, qty in pairs(type(info.items) == "table" and info.items or {}) do
        itemID = Core.Num(itemID)
        if itemID then c.items[itemID] = (Core.Num(c.items[itemID]) or 0) + (Core.Num(qty) or 1) end
    end
end
Core.Listen("GATHERING_HARVEST", G.OnHarvest, "ezCore.Gathering")
Core.RegisterMessage("GATHERING_HARVEST", "Discovery.lua", "Eine eigene Ernte (Kraut, Erz, Angeln) wurde erfasst; harvest = false: nur weiterer Ertrag aus demselben Besuch.", "{ id, kind, map, items, harvest }")

function G.JustGathered(mapID)
    mapID = Core.Num(mapID)
    local out = {}
    for _, e in ipairs(just) do
        if not mapID or e.map == mapID then
            local copy = {}
            for k, v in pairs(e) do copy[k] = v end
            out[#out + 1] = copy
        end
    end
    return out
end

function G.WasJustGathered(id, mapID, x, y, maxAge)
    mapID, x, y, maxAge = Core.Num(mapID), Core.Num(x), Core.Num(y), Core.Num(maxAge)
    local D = Core.Discovery
    local w, h
    if D and D.MapYards and mapID then w, h = D.MapYards(mapID) end
    local now = maxAge and Core.Uptime() or nil
    for _, e in ipairs(just) do
        if e.id == id and (not mapID or e.map == mapID) and (not now or now - (e.t or 0) <= maxAge) then
            if not (x and y and e.x and e.y) then return true end
            if w and math.sqrt(((e.x - x) * w) ^ 2 + ((e.y - y) * h) ^ 2) <= G.JUST_YARDS then return true end
            if not w and math.abs(e.x - x) < 0.01 and math.abs(e.y - y) < 0.01 then return true end
        end
    end
    return false
end

function G.ForgetJustGathered() just = {} end

function G.SessionStats()
    local c = Counter() or {}
    local out = { harvests = Core.Num(c.harvests) or 0, kinds = {}, items = {}, value = 0, priced = 0,
        start = Core.Session and Core.Session.Start and Core.Session.Start() or nil }
    for k, n in pairs(type(c.kinds) == "table" and c.kinds or {}) do out.kinds[k] = n end
    local P = Core.Prices
    for itemID, qty in pairs(type(c.items) == "table" and c.items or {}) do
        out.items[itemID] = qty
        local v = P and P.Value and P.Value(itemID, qty)
        if Core.Num(v) then
            out.value = out.value + v
            out.priced = out.priced + 1
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Pflege der Fundorte (SAM-18, Welle 14)
---------------------------------------------------------------------------
--[[
    Sichtbar auf ezCores Einstellungsseite, Abschnitt „Sammeln“ (G.AddCare); jede Aktion mit Core.Confirm.
      G.Locked() / G.SetLocked(an)   Schalter „Fundorte nicht mehr ändern“ (OPT_gatherLocked, ezCoreDB.gatherCare.locked,
                                     ab Werk aus): neue Ernten zählen weiter (Beute, Arten), aber keine Stelle kommt
                                     dazu oder ändert sich (Discovery.Place lässt Angeln und Objekte der Arten in
                                     G.KIND_PUBLIC aus; Quest-Objekte und Behälter werden weiter erfasst). Die Knöpfe
                                     unten bleiben bedienbar – sie sind ausdrückliche Aufträge mit Rückfrage; bei
                                     eingefrorener Datenbank (DB.Frozen) kommt statt der Rückfrage ein Hinweis.
      G.Points(filter)               → Zahl eigener Fundorte (filter = { kind, map }), Speicherkarten über alle
      G.ForgetKind(art)              → Zahl entfernter Stellen: alle Fundorte einer Art auf allen Karten
      G.ForgetZone(map)              → Zahl entfernter Stellen: alle Fundorte einer Speicherkarte
      G.MergeNear(yards, opts)       → Zahl zusammengelegter Stellen: Punkte desselben Objekts (bzw. Angel-Gebiets) im
                                     Umkreis yards werden einer (der häufigste bleibt, Zählungen addieren sich, t das
                                     neueste, t0 das älteste); opts.dry = true nur zählen, opts.map nur diese Karte;
                                     gezählt wird nur, was DB.Change wirklich geändert hat
      G.Stats()                      → { points, kinds = { art = n }, maps = n, bytes } (geschätzt: G.POINT_BYTES je Punkt)
      G.Progress(map)                → { { kind, label, count, lastNew, lastSeen } … } je Art: Fundorte auf der
                                     Speicherkarte, jüngster neuer Punkt (t0, seit Welle 14 je neuem Punkt gesetzt) und
                                     zuletzt gesehen (t); G.ProgressLines(map) → Texte („Erze: 37 Fundorte, zuletzt neu
                                     vor 3 Tagen“) – Knopf „Fortschritt hier“
      G.StatusLine()                 → Zeile für /ez status („Sammel-Fundorte: …“) oder nil ohne Datenbank
]]
G.POINT_BYTES = 60          -- geschätzte Größe eines Fundorts in der Datei (xy, cnt, t, b, t0)
G.MERGE_STEPS = { 5, 10, 15, 20, 30 }
G.MERGE_DEFAULT = 15
Core.OwnDefaults("gatherCare", { locked = false, mergeYards = G.MERGE_DEFAULT })
-- eingefügte Texte (Core.ImportAll): Umkreis nur im Bereich der Stufen (Gegenprüfung zu T6-2; vorher kam z. B.
-- 1000000 durch und „Zusammenlegen“ fasste danach alle Stellen einer Karte zusammen)
Core.OwnRules("gatherCare", { limits = { mergeYards = { G.MERGE_STEPS[1], G.MERGE_STEPS[#G.MERGE_STEPS] } } })

function G.Locked() return Core.OwnSetting("gatherCare", "locked") == true end

function G.SetLocked(on)
    local t = Core.OwnSettings("gatherCare")
    if not t then return false end
    t.locked = on == true
    return true
end

-- Jede eigene Stelle: fn(store, sk, id, list, kind) – sk "object" oder "fishing"; Art öffentlich (herb, ore, fish …)
local function EachSpot(DB, fn, onlyMap)
    for _, store in ipairs(DB.KeysOf("spot")) do
        if onlyMap == nil or store == onlyMap then
            for _, sk in ipairs({ "object", "fishing" }) do
                for _, id in ipairs(DB.KeysOf("spot", store, sk)) do
                    local kind
                    if sk == "fishing" then
                        kind = "fish"
                    else
                        local row = DB.Get("obj", id)
                        local stored = type(row) == "table" and row.kind or nil
                        kind = stored == nil and "chest" or G.KIND_PUBLIC[stored]
                    end
                    if kind then fn(store, sk, id, DB.Get("spot", store, sk, id) or {}, kind) end
                end
            end
        end
    end
end

local function Changed(map)
    mem = { ver = nil, kinds = {}, items = nil, maps = {} }
    G.ClearCache()
    Core.Fire("GATHERING_CHANGED", map)
end

function G.Points(filter)
    local DB = DBReady()
    if not DB then return 0 end
    filter = type(filter) == "table" and filter or {}
    local want = filter.kind and (PUBLIC_ALIAS[filter.kind] or filter.kind)
    local n = 0
    EachSpot(DB, function(_, _, _, list, kind)
        if want == nil or kind == want then n = n + #list end
    end, Core.Num(filter.map))
    return n
end

-- Fundorte einer Art bzw. einer Karte entfernen – dieselbe Zuordnung wie G.Points (ein Fundort ohne obj-Satz gilt
-- als Kiste), damit die Zahl der Rückfrage stimmt. → Zahl entfernter Fundorte
local function ForgetSpots(DB, want, onlyMap)
    local doomed = {}
    EachSpot(DB, function(store, sk, id, list, k)
        if (want == nil or k == want) and #list > 0 then doomed[#doomed + 1] = { store, sk, id, #list } end
    end, onlyMap)
    -- eine Massenlöschung mit einer Zählung am Ende (DB.ForgetMany, Welle 15) statt DB.Forget je Stelle
    local paths = {}
    for i, d in ipairs(doomed) do paths[i] = { d[1], d[2], d[3] } end
    local n = 0
    if #paths > 0 then
        local _, hit = DB.ForgetMany("spot", paths)
        for i, d in ipairs(doomed) do
            if hit[i] then n = n + d[4] end
        end
    end
    if n > 0 then Changed(onlyMap) end
    return n
end

function G.ForgetKind(kind)
    local DB = DBReady()
    kind = PUBLIC_ALIAS[kind] or kind
    if not (DB and G.KNOWLEDGE[kind]) then return 0 end
    return ForgetSpots(DB, kind, nil)
end

function G.ForgetZone(map)
    local DB = DBReady()
    map = Core.Num(map)
    if not (DB and map) then return 0 end
    return ForgetSpots(DB, nil, map)
end

function G.MergeNear(yards, opts)
    local DB = DBReady()
    yards = Core.Num(yards)
    opts = type(opts) == "table" and opts or {}
    if not (DB and yards and yards > 0) then return 0 end
    local D = Core.Discovery
    local total, touched = 0, {}
    EachSpot(DB, function(store, sk, id, list)
        if #list < 2 then return end
        local w, h
        if D and D.MapYards then w, h = D.MapYards(store) end
        if not w then return end
        -- häufigster zuerst, dann in der gespeicherten Reihenfolge
        local sorted = {}
        for i, el in ipairs(list) do sorted[#sorted + 1] = { el = el, i = i } end
        table.sort(sorted, function(a, b)
            local ca, cb = Core.Num(a.el.cnt) or 0, Core.Num(b.el.cnt) or 0
            if ca ~= cb then return ca > cb end
            return a.i < b.i
        end)
        local kept, removed = {}, 0
        for _, o in ipairs(sorted) do
            local x, y = DB.Keys.Unpack(o.el.xy)
            local into
            if x then
                for _, k in ipairs(kept) do
                    if k.x and math.sqrt(((k.x - x) * w) ^ 2 + ((k.y - y) * h) ^ 2) <= yards then into = k break end
                end
            end
            if into then
                removed = removed + 1
                into.cnt = into.cnt + (Core.Num(o.el.cnt) or 0)
                into.t = math.max(into.t or 0, Core.Num(o.el.t) or 0)
                if Core.Num(o.el.t0) then into.t0 = math.min(into.t0 or o.el.t0, o.el.t0) end
            else
                kept[#kept + 1] = { el = o.el, x = x, y = y, cnt = Core.Num(o.el.cnt) or 0, t = Core.Num(o.el.t),
                    t0 = Core.Num(o.el.t0) }
            end
        end
        if removed == 0 then return end
        if opts.dry then
            total = total + removed
            return
        end
        -- gezählt wird nur, was die Datenbank wirklich ändert (eingefroren bzw. nur lesbar: DB.Change → false)
        local changed = DB.Change("spot", { store, sk, id }, function(row)
            for i = #row, 1, -1 do row[i] = nil end
            for i, k in ipairs(kept) do
                k.el.cnt, k.el.t, k.el.t0 = k.cnt, k.t, k.t0
                row[i] = k.el
            end
        end)
        if changed then
            total = total + removed
            touched[store] = true
        end
    end, Core.Num(opts.map))
    if not opts.dry and total > 0 then Changed(next(touched)) end
    return total
end

function G.Stats()
    local DB = DBReady()
    local out = { points = 0, kinds = {}, maps = 0, bytes = 0 }
    if not DB then return out end
    local maps = {}
    EachSpot(DB, function(store, _, _, list, kind)
        if #list > 0 then
            out.points = out.points + #list
            out.kinds[kind] = (out.kinds[kind] or 0) + #list
            maps[store] = true
        end
    end)
    for _ in pairs(maps) do out.maps = out.maps + 1 end
    out.bytes = out.points * G.POINT_BYTES
    return out
end

function G.Progress(map)
    local DB = DBReady()
    map = Core.Num(map)
    if not (DB and map) then return {} end
    local by = {}
    EachSpot(DB, function(_, _, _, list, kind)
        local e = by[kind]
        if not e then e = { kind = kind, label = L["GATHER_KIND_" .. kind], count = 0 } by[kind] = e end
        for _, el in ipairs(list) do
            e.count = e.count + 1
            local t0, t = Core.Num(el.t0), Core.Num(el.t)
            if t0 and (not e.lastNew or t0 > e.lastNew) then e.lastNew = t0 end
            if t and (not e.lastSeen or t > e.lastSeen) then e.lastSeen = t end
        end
    end, map)
    local out = {}
    for _, k in ipairs(G.KIND_ORDER) do
        if by[k] and by[k].count > 0 then out[#out + 1] = by[k] end
    end
    return out
end

function G.ProgressLines(map)
    local lines = {}
    for _, e in ipairs(G.Progress(map)) do
        local count = Core.Plural(e.count, L.GATHER_SPOTS_ONE, L.GATHER_SPOTS_MANY)
        local when = e.lastNew and L.GATHER_PROGRESS_NEW:format(Core.Ago(e.lastNew, "server"))
            or (e.lastSeen and L.GATHER_PROGRESS_SEEN:format(Core.Ago(e.lastSeen, "server"))) or nil
        lines[#lines + 1] = when and L.GATHER_PROGRESS_LINE:format(e.label or e.kind, count, when)
            or L.GATHER_PROGRESS_LINE_SHORT:format(e.label or e.kind, count)
    end
    return lines
end

function G.StatusLine()
    local DB = DBReady()
    if not DB then return nil end
    local st = G.Stats()
    local parts = {}
    for _, k in ipairs(G.KIND_ORDER) do
        if st.kinds[k] then parts[#parts + 1] = (L["GATHER_KIND_" .. k] or k) .. " " .. st.kinds[k] end
    end
    local line = L.GATHER_STATUS:format(Core.Plural(st.points, L.GATHER_SPOTS_ONE, L.GATHER_SPOTS_MANY),
        #parts > 0 and table.concat(parts, ", ") or L.NONE, st.maps, math.ceil(st.bytes / 1024))
    if G.Locked() then line = line .. " " .. L.GATHER_STATUS_LOCKED end
    return line
end

-- Auswahl für die Knöpfe (nur im Arbeitsspeicher; die Seite merkt sich nichts davon)
local function PlayerStore()
    local DB = Core.DB
    local map = DB and DB.Keys and DB.Keys.PlayerSpot and DB.Keys.PlayerSpot()
    return Core.Num(map) and map > 0 and map or nil
end

local function ZoneChoices()
    local DB = DBReady()
    local list = { { 0, L.GATHER_ZONE_HERE } }   -- 0: die Zone, in der du gerade bist
    if not DB then return list end
    local counts = {}
    EachSpot(DB, function(store, _, _, l) counts[store] = (counts[store] or 0) + #l end)
    for store, n in pairs(counts) do
        if n > 0 then list[#list + 1] = { store, L.GATHER_ZONE_CHOICE:format(Core.MapName(store), n) } end
    end
    table.sort(list, function(a, b)
        if (a[1] == 0) ~= (b[1] == 0) then return a[1] == 0 end
        return a[2] < b[2]
    end)
    return list
end

local function KindChoices()
    local list = {}
    local st = G.Stats()
    for _, k in ipairs(G.KIND_ORDER) do
        list[#list + 1] = { k, L.GATHER_ZONE_CHOICE:format(L["GATHER_KIND_" .. k], st.kinds[k] or 0) }
    end
    return list
end

-- Eingefrorene Datenbank (neuerer Speicher, Projekt-Datei): die Pflege kann nichts ändern – Hinweis statt Rückfrage
local function CareBlocked()
    local DB = Core.DB
    if DB and DB.Frozen and DB.Frozen() then
        Core.Print(Core.name, L.GATHER_CARE_FROZEN)
        return true
    end
    return false
end

function G.AskForgetKind(kind)
    if CareBlocked() then return end
    kind = kind or "herb"
    local n = G.Points({ kind = kind })
    if n == 0 then return Core.Print(Core.name, L.GATHER_CARE_NOTHING) end
    Core.Confirm(L.GATHER_FORGET_KIND_ASK:format(n, L["GATHER_KIND_" .. kind] or kind), function()
        Core.Print(Core.name, L.GATHER_CARE_DONE:format(G.ForgetKind(kind)))
    end, { alert = true })
end

function G.AskForgetZone(map)
    if CareBlocked() then return end
    map = Core.Num(map)
    if not map or map <= 0 then map = PlayerStore() end
    local n = map and G.Points({ map = map }) or 0
    if n == 0 then return Core.Print(Core.name, L.GATHER_CARE_NOTHING) end
    Core.Confirm(L.GATHER_FORGET_ZONE_ASK:format(n, Core.MapName(map)), function()
        Core.Print(Core.name, L.GATHER_CARE_DONE:format(G.ForgetZone(map)))
    end, { alert = true })
end

-- Art bzw. Zone wählen, dann die Rückfrage (Einstellungs-Prüfung 19.11.2026, Abschnitt 4: vorher zwei Auswahlfelder
-- „Art“ und „Zone“ vor den Knöpfen, die wie Einstellungen aussahen, aber nur die Wahl für eine Aktion waren und nicht
-- gespeichert wurden). Der Knopf öffnet Blizzards Menü mit den Arten bzw. Zonen samt Zahl der Fundorte; ein Eintrag führt
-- zur bekannten Rückfrage. Ohne Menü (Client ohne MenuUtil) gilt wie bisher Kräuter bzw. die Zone, in der du bist.
-- → true, wenn das Menü aufging
local function ChooseThen(button, title, choices, ask)
    if CareBlocked() then return false end
    local owner = type(button) == "table" and type(button.GetObjectType) == "function" and button or rawget(_G, "UIParent")
    local list = choices()
    local opened = Core.Menu and Core.Menu.Open and Core.Menu.Open(owner, function(root)
        Core.Menu.Title(root, title)
        for _, choice in ipairs(list) do
            local value = choice[1]
            Core.Menu.Button(root, choice[2], function() ask(value) end)
        end
    end)
    if not opened then ask(nil) end
    return opened == true
end

function G.ChooseForgetKind(button)
    return ChooseThen(button, L.GATHER_FORGET_KIND_LABEL, KindChoices, G.AskForgetKind)
end

function G.ChooseForgetZone(button)
    return ChooseThen(button, L.GATHER_FORGET_ZONE_LABEL, ZoneChoices, G.AskForgetZone)
end

function G.AskMerge(yards)
    if CareBlocked() then return end
    yards = Core.Num(yards) or Core.Num(Core.OwnSetting("gatherCare", "mergeYards")) or G.MERGE_DEFAULT
    local n = G.MergeNear(yards, { dry = true })
    if n == 0 then return Core.Print(Core.name, L.GATHER_MERGE_NOTHING:format(yards)) end
    Core.Confirm(L.GATHER_MERGE_ASK:format(n, yards), function()
        Core.Print(Core.name, L.GATHER_MERGE_DONE:format(G.MergeNear(yards)))
    end)
end

function G.PrintProgress(map)
    map = Core.Num(map) or PlayerStore()
    local lines = map and G.ProgressLines(map) or {}
    if #lines == 0 then return Core.Print(Core.name, L.GATHER_PROGRESS_NONE) end
    Core.Print(Core.name, L.GATHER_PROGRESS_HEAD:format(Core.MapName(map)))
    for _, line in ipairs(lines) do Core.Print(Core.name, line) end
end

---------------------------------------------------------------------------
-- Eigene Fundorte als Text sichern und einlesen (SAM-19; Entscheidung des Nutzers vom 16.11.2026, Nr. 34 „den
-- Empfehlungen folgen“: „Ja, klein, nur als eigene Sicherung“). Zusätzlich zu SavedVariables – kein Austausch
-- zwischen Spielern (Entscheidung vom 13.11.2026), der Text ist nur für die eigene Sicherung gedacht.
---------------------------------------------------------------------------
--[[
    G.ExportText()           → Text, Zahl der Stellen – oder nil und Grund ("nodb", "empty" oder ein Grund von Core.Pack)
    G.ImportText(text, opts) → Ergebnis { ok, reason, added, known, skipped, objects }; opts.dryRun = true: nur
                               prüfen und zählen. reason: "nodb" | "combat" | "locked" | "off" | "empty" | "format" |
                               "kind" | "newer" | "version"
    G.ShowBackupExport(), G.ShowBackupImport()   die zwei Dialoge (Core.TextDialog, angedockt an Blizzards
                               Einstellungsfenster); Knöpfe auf der Seite „Sammeln“, Abschnitt „Pflege“ (Leitlinie 3)
    Form: Core.Pack(G.BACKUP_KIND, G.BACKUP_VERSION, { b = Build, spots = { { m = Speicherkarte, k = "o" (Objekt) |
          "f" (Angeln), id = objectID bzw. Gebiet, xy = Lage (DB.Keys.Pack), c = Ernten, t, t0, o = Art des Objekts
          (herb, mine, pool, chest) } … } }) – Art und Version stehen im Umschlag; eine neuere Version lehnt Unpack ab.
    Einlesen: Eine Stelle, die schon bekannt ist (dieselbe Stelle laut Discovery.SamePlace), bleibt, wie sie ist – die
    eigenen Daten gewinnen. Neue Stellen tragen die Herkunft src = "backup" (G.Nodes reicht sie als node.src weiter;
    ezMap zeigt „Sicherung“ statt „bei dir“); erntest du dort selbst, wird daraus src = "own" (Discovery.Place). Die
    Art eines Objekts kommt nur dazu, wo die Datenbank sie noch nicht kennt (DB.Adopt). Der Schalter „Fundorte nicht
    mehr ändern“ (G.Locked) sperrt auch das Einlesen; im Kampf und bei ausgeschalteter Datensammlung geht es nicht.
]]
G.BACKUP_KIND = "ezCollection.gatherSpots"
G.BACKUP_VERSION = 1
local BACKUP_SK = { o = "object", f = "fishing" }
local BACKUP_CODE = { object = "o", fishing = "f" }

function G.ExportText()
    local DB = DBReady()
    if not DB then return nil, "nodb" end
    local m = Mem(DB)
    local spots, items = {}, 4   -- Einträge wie Core.Deserialize sie zählt: kind, v, b, spots
    for _, map in ipairs(DB.KeysOf("spot")) do
        if Core.Num(map) and map > 0 then
            for _, sk in ipairs({ "object", "fishing" }) do
                for _, id in ipairs(DB.KeysOf("spot", map, sk)) do
                    local stored = sk == "object" and StoredKind(DB, m, id) or nil
                    -- nur Sammel-Fundorte: Kräuter, Erze, Angelplätze, Kisten (ohne obj-Satz gilt eine Stelle als Kiste)
                    if sk == "fishing" or stored == nil or G.KIND_PUBLIC[stored] then
                        for _, el in ipairs(DB.Get("spot", map, sk, id) or {}) do
                            if type(el) == "table" and Core.Num(el.xy) then
                                local row = { m = map, k = BACKUP_CODE[sk], id = id, xy = el.xy,
                                    c = Core.Num(el.cnt), t = Core.Num(el.t), t0 = Core.Num(el.t0), o = stored }
                                spots[#spots + 1] = row
                                items = items + 1
                                for _ in pairs(row) do items = items + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    if #spots == 0 then return nil, "empty" end
    if items > G.BACKUP_MAX_ITEMS then return nil, "toolarge" end
    local text, why = Core.Pack(G.BACKUP_KIND, G.BACKUP_VERSION, { b = DB.Keys.Build(), spots = spots })
    if not text then return nil, why end
    if #text > G.BACKUP_MAX_LENGTH then return nil, "toolarge" end
    return text, #spots
end

local UNPACK_REASON = { empty = "empty", kind = "kind", newer = "newer", version = "version", size = "size" }

-- Grenzen einer Zeile (Gesamtreview 18.11.2026, T6-9): Kartennummer, Lage (DB.Keys.Pack: x und y je 0 … 9999),
-- Ernten je Stelle, Länge eines Notschlüssels, Spielraum für die Uhr (Sicherung von einem anderen Rechner).
G.BACKUP_MAX_MAP = 10000000
G.BACKUP_MAX_XY = 99999999
G.BACKUP_MAX_COUNT = 10000
G.BACKUP_MAX_KEY = 200
G.BACKUP_CLOCK_SLACK = 86400
-- Größe des Sicherungstexts (Gegenprüfung zu T6-7): eine Zeile sind etwa 100 Zeichen und 9 Einträge; die allgemeinen
-- Grenzen von Core.Deserialize (4 MiB, 400000) reichten nur für rund 44000 Stellen. Das Einlesen gibt diese größeren
-- Grenzen mit, das Sichern prüft dieselben und sagt es vor dem Kopieren (Grund "toolarge"), statt einen Text zu
-- zeigen, der sich nicht wieder einlesen lässt.
G.BACKUP_MAX_LENGTH = 32 * 1024 * 1024
G.BACKUP_MAX_ITEMS = 3000000

local function WholeNumber(value, minValue, maxValue)
    value = Core.FiniteNumber(value, minValue, maxValue)
    return value and value == math.floor(value) and value or nil
end

-- Objekt bzw. Gebiet einer Zeile: eine ganze Zahl (Objekt ab 1, Angelgebiet ab 0) oder ein Notschlüssel von
-- DB.Keys („~…“, Objekt ohne lesbare GUID) ohne Steuerzeichen und „|“, höchstens BACKUP_MAX_KEY Bytes.
local function BackupId(id, sk)
    if type(id) == "number" then return WholeNumber(id, sk == "object" and 1 or 0, G.BACKUP_MAX_MAP) end
    if type(id) == "string" and not Core.IsSecret(id) and #id <= G.BACKUP_MAX_KEY and id:sub(1, 1) == "~"
        and not id:find("[%c|]") then
        return id
    end
    return nil
end

-- Eine Zeile der Sicherung prüfen. → map, Speicherart, id, Felder, Objektart – oder nil (Zeile zählt als
-- übersprungen). T6-9: Kartennummer ganz und > 0, Lage ganz in 0 … BACKUP_MAX_XY, Ernten endlich und nicht negativ,
-- geklemmt auf 1 … BACKUP_MAX_COUNT (fehlt die Zahl: 1), Zeiten ganz, > 0 und nicht in der Zukunft (Spielraum BACKUP_CLOCK_SLACK), id siehe BackupId.
local function BackupRow(r)
    if type(r) ~= "table" or Core.IsSecret(r) then return nil end
    local sk = BACKUP_SK[r.k]
    local map, xy = WholeNumber(r.m, 1, G.BACKUP_MAX_MAP), WholeNumber(r.xy, 0, G.BACKUP_MAX_XY)
    if not (map and sk and xy) then return nil end
    local id = BackupId(r.id, sk)
    if id == nil then return nil end
    local cnt = 1
    if r.c ~= nil then
        -- nicht endlich oder negativ: Zeile ungültig; mehr als BACKUP_MAX_COUNT wird geklemmt (Gegenprüfung: der
        -- Zähler einer Stelle wächst ohne Deckel, die eigene Sicherung verlor sonst genau diese Stelle)
        cnt = Core.FiniteNumber(r.c, 0)
        if not cnt then return nil end
        cnt = math.max(1, math.min(G.BACKUP_MAX_COUNT, math.floor(cnt)))
    end
    local kind = type(r.o) == "string" and G.KIND_PUBLIC[r.o] and r.o or nil
    local fields = { xy = xy, cnt = cnt, src = "backup" }
    local latest = Core.Now() + G.BACKUP_CLOCK_SLACK
    for _, field in ipairs({ "t", "t0" }) do
        if r[field] ~= nil then
            local t = WholeNumber(r[field], 1, latest)
            if not t then return nil end
            fields[field] = t
        end
    end
    return map, sk, id, fields, kind
end
G.BackupRow = BackupRow

function G.ImportText(text, opts)
    opts = type(opts) == "table" and opts or {}
    local result = { ok = false, added = 0, known = 0, skipped = 0, objects = 0 }
    local DB = DBReady()
    if not DB then result.reason = "nodb" return result end
    if Core.InCombat() then result.reason = "combat" return result end
    if G.Locked() then result.reason = "locked" return result end
    if not DB.Collecting() then result.reason = "off" return result end
    local data, why = Core.Unpack(text, G.BACKUP_KIND, G.BACKUP_VERSION,
        { maxLength = G.BACKUP_MAX_LENGTH, maxItems = G.BACKUP_MAX_ITEMS })
    if not data then result.reason = UNPACK_REASON[why] or "format" return result end
    if type(data.spots) ~= "table" then result.reason = "format" return result end
    local D = Core.Discovery
    for _, r in ipairs(data.spots) do
        local map, sk, id, fields, kind = BackupRow(r)
        if not map then
            result.skipped = result.skipped + 1
        else
            local known = false
            for _, el in ipairs(DB.Get("spot", map, sk, id) or {}) do
                if type(el) == "table" and D.SamePlace(el, fields, { map, sk }) then known = true break end
            end
            if known then
                result.known = result.known + 1
            else
                if not opts.dryRun then
                    if kind and sk == "object" and DB.Get("obj", id) == nil then
                        if DB.Adopt("obj", id, { kind = kind }) then result.objects = result.objects + 1 end
                    end
                    if DB.Observe("spot", { map, sk, id }, fields) then
                        result.added = result.added + 1
                    else
                        result.skipped = result.skipped + 1
                    end
                else
                    result.added = result.added + 1
                end
            end
        end
    end
    result.ok = true
    return result
end

function G.BackupResultText(result)
    if type(result) ~= "table" then return L.GATHER_BACKUP_NO_format end
    if not result.ok then return L["GATHER_BACKUP_NO_" .. tostring(result.reason)] or L.GATHER_BACKUP_NO_format end
    return L.GATHER_BACKUP_DONE:format(result.added, result.known, result.skipped)
end

local function SettingsAnchor() return rawget(_G, "SettingsPanel") end

function G.ShowBackupExport()
    local text, n = G.ExportText()
    if not text then
        Core.Print(Core.name, L["GATHER_BACKUP_NO_" .. tostring(n)] or L.GATHER_BACKUP_NO_empty)
        return nil
    end
    return Core.TextDialog({ anchor = SettingsAnchor(), title = L.GATHER_BACKUP_EXPORT_TITLE,
        hint = L.GATHER_BACKUP_EXPORT_HINT:format(n), text = text, readOnly = true, select = true, owner = "ezCore" })
end

function G.ShowBackupImport()
    return Core.TextDialog({ anchor = SettingsAnchor(), title = L.GATHER_BACKUP_IMPORT_TITLE,
        hint = L.GATHER_BACKUP_IMPORT_HINT, text = "", accept = L.GATHER_BACKUP_IMPORT_ACCEPT, owner = "ezCore",
        onAccept = function(text)
            local result = G.ImportText(text)
            Core.Print(Core.name, G.BackupResultText(result))
            if not result.ok then return false end
        end })
end

-- Abschnitt „Sammeln“ auf der Seite „ezCollection“ (Collection.lua)
function G.AddCare(page)
    if type(page) ~= "table" or type(page.Button) ~= "function" then return false end
    page:Header(L.GATHER_CARE_HEADER, L.GATHER_CARE_HEADER_TIP)
    -- „Entdecker-Wissen zeigen (Spoiler)“ sichtbar bei den Fundorten statt unter „Erweitert“ (Einstellungs-Prüfung 19.11.2026)
    local discovery = Core.Discovery
    if discovery and discovery.AddExplorerSetting then discovery.AddExplorerSetting(page) end
    page:OwnCheckbox("gatherCare", "locked", { text = "gatherLocked" })
    page:Button(L.GATHER_PROGRESS_LABEL, L.GATHER_PROGRESS_BUTTON, function() G.PrintProgress() end, L.GATHER_PROGRESS_TIP)
    -- Art bzw. Zone im Menü des Knopfs, dann die Rückfrage (G.ChooseForgetKind / G.ChooseForgetZone)
    page:Button(L.GATHER_FORGET_KIND_LABEL, L.GATHER_FORGET_BUTTON, function(button) G.ChooseForgetKind(button) end,
        L.GATHER_FORGET_KIND_TIP)
    page:Button(L.GATHER_FORGET_ZONE_LABEL, L.GATHER_FORGET_BUTTON, function(button) G.ChooseForgetZone(button) end,
        L.GATHER_FORGET_ZONE_TIP)
    if type(page.ProxyDropdown) == "function" then
        page:ProxyDropdown("gatherMergeYards", function()
            local list = {}
            for _, v in ipairs(G.MERGE_STEPS) do list[#list + 1] = { v, L.GATHER_YARDS:format(v) } end
            return list
        end, function() return Core.Num(Core.OwnSetting("gatherCare", "mergeYards")) or G.MERGE_DEFAULT end, function(v)
            local t, n = Core.OwnSettings("gatherCare"), Core.Num(v)
            if t and n then t.mergeYards = n end
        end, { default = G.MERGE_DEFAULT, varType = Settings and Settings.VarType and Settings.VarType.Number })
    end
    page:Button(L.GATHER_MERGE_LABEL, L.GATHER_MERGE_BUTTON, function() G.AskMerge() end, L.GATHER_MERGE_TIP)
    -- Sicherung als Text (SAM-19, Welle 23d)
    page:Button(L.GATHER_BACKUP_EXPORT_LABEL, L.GATHER_BACKUP_EXPORT_BUTTON, function() G.ShowBackupExport() end,
        L.GATHER_BACKUP_EXPORT_TIP)
    page:Button(L.GATHER_BACKUP_IMPORT_LABEL, L.GATHER_BACKUP_IMPORT_BUTTON, function() G.ShowBackupImport() end,
        L.GATHER_BACKUP_IMPORT_TIP)
    return true
end

---------------------------------------------------------------------------
-- Tooltip-Zeile und Schalter
---------------------------------------------------------------------------

local function Enabled()
    local db = Core.db
    local t = type(db) == "table" and db.tooltip
    if type(t) ~= "table" then return true end
    return t.gathering ~= false
end

local LOOT_MAX, VENDOR_MAX = 3, 2

-- V-031: „Beute von“ läuft bei jedem Neuaufbau des Tooltips – das Ergebnis je Gegenstand merken, statt jedes Mal
-- den ganzen Beute-Verlauf (bis 2000 Einträge) zu durchsuchen. Verworfen wird der Eintrag, sobald für diesen
-- Gegenstand Beute dazukommt oder wegfällt (HISTORY_ADDED/HISTORY_REMOVED), sonst nach LOOT_CACHE_SECONDS.
local lootCache, LOOT_CACHE_SECONDS, LOOT_CACHE_MAX = {}, 300, 200
local lootCached = 0
G.lootCacheStats = { hit = 0, miss = 0 }

local function LootSources(itemID)
    local H = Core.History
    if not (H and H.LootSources) then return {} end
    local now = Core.Num(GetTime and GetTime()) or 0
    local hit = lootCache[itemID]
    if hit and now - hit.t < LOOT_CACHE_SECONDS then
        G.lootCacheStats.hit = G.lootCacheStats.hit + 1
        return hit.list
    end
    G.lootCacheStats.miss = G.lootCacheStats.miss + 1
    local list = H.LootSources(itemID) or {}
    if not hit then
        if lootCached >= LOOT_CACHE_MAX then lootCache, lootCached = {}, 0 end
        lootCached = lootCached + 1
    end
    lootCache[itemID] = { t = now, list = list }
    return list
end

-- Zwischenspeicher verwerfen: für einen Gegenstand oder (ohne Angabe) ganz. Rückgabe: true, wenn etwas wegfiel.
function G.ForgetLoot(itemID)
    if itemID == nil then
        local had = lootCached > 0
        lootCache, lootCached = {}, 0
        return had
    end
    itemID = Core.Num(itemID)
    if not (itemID and lootCache[itemID]) then return false end
    lootCache[itemID] = nil
    lootCached = math.max(0, lootCached - 1)
    return true
end

local function OnHistory(kind, entry)
    if kind ~= "loot" then return end
    local id = type(entry) == "table" and Core.Num(entry.id)
    if id then G.ForgetLoot(id) else G.ForgetLoot() end
end
Core.Listen("HISTORY_ADDED", OnHistory, "ezCore.Gathering")
Core.Listen("HISTORY_REMOVED", OnHistory, "ezCore.Gathering")
Core.Listen("HISTORY_CLEARED", function(kind) if kind == nil or kind == "loot" then G.ForgetLoot() end end, "ezCore.Gathering")

local function LootText(itemID)
    local list = LootSources(itemID)
    if #list == 0 then return nil end
    local parts = {}
    for i = 1, math.min(#list, LOOT_MAX) do
        local s = list[i]
        local name = s.name or (s.npc and L.GATHER_NPC:format(s.npc)) or "?"
        parts[#parts + 1] = (s.zone and L.GATHER_LOOT_ZONE:format(name, s.zone) or name) .. " " .. L.GATHER_TIMES:format(s.times)
    end
    local text = table.concat(parts, ", ")
    if #list > LOOT_MAX then text = text .. " " .. L.GATHER_MORE:format(#list - LOOT_MAX) end
    return text
end

local function VendorText(itemID)
    local K = Core.Knowledge
    local list = K and K.VendorSources and K.VendorSources(itemID) or {}
    if #list == 0 then return nil end
    local parts = {}
    for i = 1, math.min(#list, VENDOR_MAX) do
        local v = list[i]
        local price = Core.Money(v.price, "coins")
        if (v.stack or 1) > 1 then price = L.GATHER_STACK:format(v.stack, price) end
        parts[#parts + 1] = L.GATHER_VENDOR_ENTRY:format(v.name or "?", v.zone or "?", price) .. (v.limited and (" " .. L.GATHER_LIMITED) or "")
    end
    local text = table.concat(parts, ", ")
    if #list > VENDOR_MAX then text = text .. " " .. L.GATHER_MORE:format(#list - VENDOR_MAX) end
    return text
end

-- „Herkunft laut Questie“ (DG-15): nur, wenn ezCore selbst keine Beute- oder Händlerzeile hat, aus der ersten
-- angebundenen Datenbank (nicht der eigenen – die steht schon in „Beute von“ und „Händler“). An Quest-Gegenständen
-- hält sie sich zurück, solange Questies eigener Tooltip die Quest nennt (DG-17, Funktion questItemSource).
local ORIGIN_MAX = 3

local function OriginText(itemID)
    local S = Core.Sources
    if not (S and S.WhereFrom) then return nil end
    local K = Core.Knowledge
    if K and K.IsQuestItem and K.IsQuestItem(itemID) and Core.WhoHandles("questItemSource") then return nil end
    local answer
    for _, a in ipairs(S.WhereFrom(itemID, { all = true }) or {}) do
        if a.sourceKey ~= "own" then answer = a break end
    end
    if not answer then return nil end
    local parts = {}
    for _, list in ipairs(S.WHERE_LISTS) do
        local entries = answer[list]
        if type(entries) == "table" and #entries > 0 then
            local names = {}
            for i = 1, math.min(#entries, ORIGIN_MAX) do
                local e = entries[i]
                local name
                -- „steckt in <Behälter>“ nennt einen Gegenstand (kind "item"): sein Symbol davor, über ezCores einen
                -- Helfer (Wunsch vom 18.11.2026 „mit den item icons“); ohne Namen der Name aus dem Client, dann „#ID“
                if list == "containers" and type(Core.ItemIconText) == "function" then
                    name = Core.ItemIconText(e.id, e.name) or Core.ItemIconText(e.id, "#" .. tostring(e.id))
                end
                name = name or e.name or "#" .. tostring(e.id)
                if list ~= "quests" and e.zone then name = L.GATHER_LOOT_ZONE:format(name, e.zone) end
                names[#names + 1] = name
            end
            local total = type(answer.n) == "table" and Core.Num(answer.n[list]) or #entries
            local text = table.concat(names, ", ")
            if total > #names then text = text .. " " .. L.GATHER_MORE:format(total - #names) end
            parts[#parts + 1] = L["GATHER_ORIGIN_" .. list]:format(text)
        end
    end
    if #parts == 0 then return nil end
    return L.GATHER_ORIGIN_LINE:format(S.Label(answer) or answer.source, table.concat(parts, "; "))
end
G.OriginText = OriginText

-- Kraut oder Erz (Handwerkswaren, Unterklasse 9 bzw. 7) – nur dort sagt die Zeile ohne Fundort, warum (Leitlinie 11)
local function Gatherable(itemID)
    local classID, subclassID = Core.ItemClass(itemID)   -- Core.ItemInstant (Gesamtreview 18.11.2026, T16-16)
    return classID == 7 and (subclassID == 9 or subclassID == 7)
end
G.Gatherable = Gatherable

function G.Lines(itemID)
    local lines = {}
    if not Enabled() then return lines end
    local line = #G.Active() > 0 and G.Line(itemID) or nil
    if line then
        lines[#lines + 1] = line
    elseif Gatherable(itemID) then
        lines[#lines + 1] = L.GATHER_LINE_NONE
    end
    -- Welle 27 (F4 b): Schließkassetten nennen die nötige Fertigkeit laut Client-Tabellen (Nachschlage-Wissen)
    local lockRank = G.RequiredItem(itemID)
    if lockRank then lines[#lines + 1] = L.GATHER_ITEM_LOCK:format(G.SkillName("chest") or G.LOCKPICKING.en, lockRank) end
    local K = Core.Knowledge
    if K and K.IsResource and K.IsResource(itemID) then
        -- „Beute von“ weicht, sobald ein Abschnitt (ezLoot) dieselbe Aussage anmeldet: Core.Tooltip.ClaimLine("lootFrom", …)
        local claimed = Core.Tooltip.Shows(itemID, "lootFrom")
        local loot = not claimed and LootText(itemID) or nil
        -- Welle 23c (A28): die Zeile nennt ihre Quelle („Beute bei dir von: …“, Leitlinie 11)
        if loot then lines[#lines + 1] = L.GATHER_LOOT_OWN:format(loot) end
        local vendor = VendorText(itemID)
        if vendor then lines[#lines + 1] = L.GATHER_VENDOR_LINE:format(vendor) end
        -- Welle 13 (Übergabe aus Welle 11, ezLoot): zeigt ein Abschnitt die eigene Beute (lootFrom), gibt es eigene
        -- Beute – dann keine „Herkunft laut Questie“, so wie ohne den Abschnitt
        if not loot and not claimed and not vendor then
            local origin = OriginText(itemID)
            if origin then lines[#lines + 1] = origin end
        end
    end
    return lines
end

-- Welle 26 (Nachtrag aus Welle 23, ezCraft-Paket): die eigene Fundort-Zeile in der Farbrolle „good“ des Design-Systems
-- (Blizzards Grün, ezCore.Style) statt fester Zahlen (vorher 0.6, 0.9, 0.6)
G.LINE_ROLE = "good"
-- Abstand (S-1811-Tooltipabstand): eine Leerzeile davor (Core.Tooltip.Gap), Gruppe „origin“ – ezLoots „Beute bei dir“
-- (Platz loot, gleich danach) schließt ohne Leerzeile an.
G.TOOLTIP_GROUP = "origin"
Core.Tooltip.AddItemSection("ezCore.gathering", "gathering", function(tooltip, itemID)
    local lines = G.Lines(itemID)
    if #lines == 0 then return end
    local r, g, b = Core.Style.Color(G.LINE_ROLE)
    Core.Tooltip.Gap(tooltip, G.TOOLTIP_GROUP)
    for _, line in ipairs(lines) do tooltip:AddLine(line, r, g, b, true) end
end, "ezCore")

-- Schalter unter der Überschrift „Tooltip“ (Collection.lua ruft es nach UnitTooltip.AddSection auf).
function G.AddSettings(cat)
    local db = Core.db
    if not (cat and type(db) == "table" and Settings and Settings.RegisterAddOnSetting and Settings.CreateCheckbox) then return end
    local page = Core.ParentPage()
    if not page then return end
    local active = G.Active()
    page:OwnCheckbox("tooltip", "gathering", { text = "ttGathering", variable = "ezCore_tt_gathering",
        onChange = function() G.ClearCache() end,
        note = #active > 0 and L.GATHER_ACTIVE:format(table.concat(active, ", ")) or L.GATHER_NONE_SOURCES })
end
Core.OwnDefaults("tooltip", { gathering = true })   -- Standardwert bei den übrigen Tooltip-Schaltern (V-018)
