local _, ns = ...
local Core = ezCore

--[[
    Datenquellen: Brücke zu den Datenbanken installierter Addons (Regel „Datenquellen“ des Nutzers, 13.11.2026:
    zuerst der Client, dann die Datenbank eines installierten Addons, dann selbst Gesammeltes; jede Angabe nennt
    ihre Quelle; kein leerer Tooltip ohne Erklärung). Dieser Dienst ist nur die mittlere Stufe: Client und selbst
    Gesammeltes fragt das Modul selbst (Core.Knowledge, Core.History), die Datenbanken fremder Addons hier.

    Leitlinie 10: Nichts wird kopiert oder gespeichert. Jede Abfrage liest zur Laufzeit nur das eine Feld, nach dem
    gefragt wird, per pcall, prüft seine Form und baut daraus eine neue, eigene Antwort; in die Tabellen der Addons
    wird nie geschrieben, nachladbare Teile werden nie von hier aus geladen.

    Reihenfolge (EC-03, DG-27, RM-08; Entscheidung des Nutzers 14.11.2026 „Ja, und Questie empfehlen“): zuerst der
    Client (fragt das Modul selbst bzw. die eigene Quelle unten), dann die eigene Entdecker-Datenbank (Quelle „own“,
    „bei dir“), dann QuestieDB zur Laufzeit (SourcesQuestie.lua), dann weitere (AtlasLoot). Die Anbindung von Tnny's
    Mob Loot ist seit Welle 16 entfernt (RB-01, Nachtrag des Nutzers vom 14.11.2026); läuft es, nimmt ezCore nur
    Rücksicht (Erkennung unitLoot in OtherAddOns.lua).

      Core.Sources.Register(schlüssel, quelle) → true | false, "invalid"
          quelle = { label = Anzeigename, ready = fn() → true | false, grund ("missing" | "shape"),
                     recipeFor = fn(itemID), lootOf = fn(npcID, info), openFor = fn(npcID),
                     whereFrom = fn(itemID, opts), recipesUsing = fn(itemID), contentsOf = fn(id, art),
                     own = true (eigene Daten: keine Marke „fremd“, Zeile „bei dir“, nicht in /ez status),
                     silent = true (stiller Rückfall: fehlt er, nennt ihn kein Hinweis),
                     generic = true (openFor öffnet nur das Fenster, nicht den Gegner: nur mit ausdrücklichem
                     Schlüssel in OpenFor) }
          Erneutes Anmelden ersetzt. Ein Schlüssel, der in Core.Sources.ORDER fehlt, kommt hinten dazu.
      Core.Sources.Unregister(schlüssel) → true | false
      Core.Sources.ORDER                     feste Reihenfolge der bekannten Quellen
      Core.Sources.Order() → { schlüssel … } angemeldete Quellen in dieser Reihenfolge (Kopie)
      Eine Auskunft darf nil, "skip" liefern, wenn sie gar nicht nachgesehen hat – der Stand bleibt dann, wie er war.
      Core.Sources.Status(schlüssel) → "ok" | "missing" (Addon läuft nicht) | "shape" (läuft, antwortet aber in
                                       unerwarteter Form) | "error" (warf einen Fehler) | "unknown" (nicht angemeldet)
      Core.Sources.Skipped(schlüssel) → Zahl verworfener Einträge (je Auskunft und ID einmal gezählt): Eine
                                       Auskunft darf nil, "entry" liefern, wenn nur dieser eine Eintrag nicht passt
                                       (die Quelle bleibt "ok"); unbrauchbare Gegenstände einer Beuteliste entfernt
                                       der Dienst selbst. "shape" heißt: die Form der Quelle stimmt grundsätzlich nicht.
      Core.Sources.List(auskunft) → { { key, label, status, asks = { recipeFor = true … }, skipped } … }   ohne auskunft alle
      Core.Sources.Ask(auskunft, …) → antwort | nil      erste Quelle in der Reihenfolge, die antwortet
      Core.Sources.AskAll(auskunft, …) → { antwort … }    alle, die antworten, in der Reihenfolge
          Jede Antwort trägt source (Anzeigename) und sourceKey.

      Auskünfte:
      Core.Sources.RecipeFor(itemID) → { item, spell, name, profession, professionKey, skill = { a, b, c } | nil,
                                         skillUnknown, reagents = { { id, count } … }, count, recipeItem, source,
                                         sourceKey } | nil
          skill nur mit echten Schwellen; eine 0 heißt „unbekannt“ (bei Forever-Rezepten der Regelfall, DG-50) – dann
          skill = nil und skillUnknown = true
          spell = Zauber-ID des Herstellens; profession = Name des Berufs, wie die Quelle ihn nennt (kann fehlen);
          count = Anzahl hergestellter Stücke; recipeItem = Gegenstand, der das Rezept lehrt (kann fehlen)
      Core.Sources.LootOf(npcID, info) → { npc, items = { { id, chance, quest, listed } … }, listed, source,
                                           sourceKey } | nil
          info = { level } wird an die Quelle durchgereicht. chance 0–1 oder nil (ohne Chance; QuestieDB nennt nur
          „kann fallen lassen“). Die Felder measured, estimated, few, hidden, skin, worldDrops, levelMismatch, asOf
          und credit gab es nur für Tnny's Mob Loot; seit Welle 16 (RB-01) liefert sie keine Quelle mehr – ältere
          Antworten mit ihnen bleiben gültig, ausgewertet werden sie nicht.
      Core.Sources.OpenFor(npcID[, schlüssel]) → true, Anzeigename | false, grund ("missing", "invalid", "closed",
                                                 "error") – öffnet das Fenster der Quelle für diesen Gegner; eine Quelle
                                                 mit generic (AtlasLoot) nur, wenn ihr Schlüssel genannt ist
      Core.Sources.WhereFrom(itemID, opts) → { item, drops = { eintrag … }, objects, containers, vendors, quests,
                                               n = { drops = Gesamtzahl … }, source, sourceKey } | nil   (DG-15)
          „Woher?“: fällt von (Gegner), liegt in (Objekt), steckt in (Behälter), verkauft von (Händler),
          Questbelohnung; eintrag = { kind ("npc" | "object" | "item" | "quest"), id, name, lo, hi (Stufe), rank,
          area (Gebiets-ID der Quelle), zone (Name laut Client), map (uiMapID, wenn der Client sie zuordnet), x, y
          (0–1), cnt (nur „bei dir“: so oft gesehen), price (nur „bei dir“) }. Je Liste höchstens WHERE_MAX
          Einträge; n nennt die ganze Zahl. Erst die eigene Datenbank, dann QuestieDB. Verschleiert der Client den
          Gegenstand noch (keine Antwort, nicht enthüllt), antwortet QuestieDB nur mit dem Schalter „Entdecker-Wissen“
          (OPT_explorer, ab Werk aus; DG-18). opts.all = true: alle Quellen (AskAll) statt der ersten.
      Core.Sources.RecipesUsing(itemID) → { { recipeID, spell, name, count, product, source, sourceKey } … } nach
          Name (EC-97, ST-17): wofür der Gegenstand Zutat ist – zuerst selbst Gesehenes (Knowledge.RecipesUsing),
          sonst AtlasLoot zur Laufzeit (AtlasLoot hat keinen Rückweg Zutat » Rezepte: begrenzte Suche über die
          Produkte, die der Client dir schon gezeigt hat; nichts wird gespeichert)
      Core.Sources.ContentsOf(art, id) → { kind, id, items = { { id, listed = true } … }, n, listed, source,
          sourceKey } | nil – was ein Behälter (art "item") bzw. eine Kiste (art "object") enthalten kann, ohne Chance;
          heute nur QuestieDB (Umkehr-Index, SourcesQuestie.lua); läuft der Index noch: nil (Grund "skip")
      Core.Sources.ClientKnowsItem(itemID) → true, wenn der Client den Gegenstand liefert oder er enthüllt ist
      Core.Sources.Label(antwort) → „laut AtlasLoot“, „laut Questie“, „bei dir“ …
      Core.Sources.Hint(auskunft) → Satz, warum keine Quelle antwortet („Questie nicht installiert“) | nil; stille
                                    Rückfälle (silent) und die eigene Datenbank nennt er nicht
      Core.Sources.Reason(auskunft) → Grund, Anzeigename, Schlüssel, ID der letzten Frage (A60, Welle 23b): "ok",
                                    "entry" (Eintrag verworfen), "shape", "error", "none" (saubere Antwort „nichts“),
                                    "skip", "missing"; ohne Antwort zählt der aussagekräftigste Grund aller Quellen
                                    (Rangfolge Sources.REASON_RANK). Der Anzeigename fehlt bei der eigenen Datenbank
      Core.Sources.ReasonText(auskunft) → Satz zum Grund („AtlasLoot kennt den Eintrag, seine Angaben passen aber
                                    nicht“ bzw. „… antwortet nicht wie erwartet“) | nil
      Core.Sources.StatusLine() → Zeile für /ez status oder nil (die angebundenen Addons, die gerade antworten)

    Angemeldete Quellen:
      own            die eigene Entdecker-Datenbank (DiscoveryView.lua): whereFrom über Core.Drops.SourcesOf,
                     Core.Vendors.Selling, Core.Places.Of und DB.Text; recipesUsing über Knowledge.RecipesUsing
      QuestieDB      LibQuestieDB zur Laufzeit (SourcesQuestie.lua): whereFrom, contentsOf; lootOf nur vorbereitet, ab Werk aus
      AtlasLoot      AtlasLoot Classic Forever (global AtlasLoot): recipeFor über
                     AtlasLoot.Data.Profession.GetCraftSpellForCreatedItem und GetProfessionData,
                     dazu AtlasLoot.Data.Recipe.GetRecipeForSpell (im Spiel bestätigt: 118 → 2330); recipesUsing über
                     dieselben Abfragen als Umkehr-Index im Arbeitsspeicher (Sources.ForgetRecipesUsing);
                     openFor über SlashCmdList.ATLASLOOT("") – öffnet nur das Fenster (generic)
]]

local ADDON = "ezCore"
local Sources = {}
Core.Sources = Sources

Sources.ORDER = { "own", "QuestieDB", "AtlasLoot" }
Sources.ASKS = { "recipeFor", "lootOf", "openFor", "whereFrom", "recipesUsing", "contentsOf" }
Sources.WHERE_MAX = 8            -- Einträge je Liste in WhereFrom (n nennt die ganze Zahl)
Sources.SCAN_MAX = 4000          -- RecipesUsing über AtlasLoot: höchstens so viele neue Produkte je Frage in den Index

local registry, extra = {}, {}
local problems = {}              -- [schlüssel] = "shape" | "error" (letzte Abfrage; für Status und Hinweis)
local reported = {}              -- [schlüssel .. auskunft] = true – jeden Fehler nur einmal in die Fehlerliste
local skipped = {}               -- [schlüssel] = { n, ids } – verworfene Einträge (Auskunft und ID je einmal gezählt)

-- Positive ganze Zahl (IDs), nie geheim.
local function ID(value)
    if Core.IsSecret(value) then return nil end
    if type(value) == "string" then value = tonumber(value) end
    if type(value) ~= "number" or value <= 0 or value ~= math.floor(value) then return nil end
    return value
end

-- Zahl, nie geheim – gemeinsamer Helfer in Util.lua (Leitlinie 2)
local Number = Core.Num

local function Report(key, ask, err)
    problems[key] = "error"
    if reported[key .. ask] then return end
    reported[key .. ask] = true
    if Core.Error then Core.Error(ADDON, err, "Sources " .. key .. "." .. ask) end
end

-- Feld einer fremden Tabelle lesen, ohne dass ein Metatabellen-Fehler durchschlägt – gemeinsamer Helfer in Util.lua.
local Field = Core.Peek

---------------------------------------------------------------------------
-- Anmeldung und Reihenfolge
---------------------------------------------------------------------------

function Sources.Register(key, source)
    if type(key) ~= "string" or key == "" or type(source) ~= "table" or type(source.label) ~= "string" then
        return false, "invalid"
    end
    if source.ready ~= nil and type(source.ready) ~= "function" then return false, "invalid" end
    for _, ask in ipairs(Sources.ASKS) do
        if source[ask] ~= nil and type(source[ask]) ~= "function" then return false, "invalid" end
    end
    local listed = false
    for _, k in ipairs(Sources.ORDER) do if k == key then listed = true end end
    if not listed and not registry[key] then extra[#extra + 1] = key end
    registry[key] = source
    problems[key], skipped[key] = nil, nil
    return true
end

function Sources.Unregister(key)
    if not registry[key] then return false end
    registry[key], problems[key], skipped[key] = nil, nil, nil
    for i = #extra, 1, -1 do if extra[i] == key then table.remove(extra, i) end end
    return true
end

function Sources.Order()
    local out = {}
    for _, key in ipairs(Sources.ORDER) do if registry[key] then out[#out + 1] = key end end
    for _, key in ipairs(extra) do if registry[key] then out[#out + 1] = key end end
    return out
end

function Sources.Status(key)
    local source = registry[key]
    if not source then return "unknown" end
    if source.ready then
        local ok, ready, why = pcall(source.ready)
        if not ok then
            Report(key, "ready", ready)
            return "error"
        end
        if ready ~= true then return why == "shape" and "shape" or "missing" end
    end
    return problems[key] or "ok"
end

function Sources.List(ask)
    local out = {}
    for _, key in ipairs(Sources.Order()) do
        local source = registry[key]
        if ask == nil or source[ask] then
            local asks = {}
            for _, a in ipairs(Sources.ASKS) do if source[a] then asks[a] = true end end
            out[#out + 1] = { key = key, label = source.label, status = Sources.Status(key), asks = asks,
                skipped = Sources.Skipped(key) }
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Form der Antworten prüfen (eine Stelle für alle Quellen)
---------------------------------------------------------------------------

-- Jede Prüfung → "ok" | "shape" (grundsätzlich falsche Form: die Quelle antwortet nicht wie erwartet) | "entry"
-- (nur dieser Eintrag ist unbrauchbar: verworfen, die Quelle bleibt "ok"). Einzelne unbrauchbare Gegenstände einer
-- Beuteliste entfernt die Prüfung selbst; zweiter Wert = wie viele.
local CHECK = {}

function CHECK.recipeFor(r)
    if type(r) ~= "table" or not ID(r.spell) or type(r.reagents) ~= "table" then return "shape" end
    if Core.IsSecret(r.profession) or (r.profession ~= nil and type(r.profession) ~= "string") then return "shape" end
    for _, reagent in ipairs(r.reagents) do
        -- Ein Rezept mit einer unbrauchbaren Zutat wäre falsch: das ganze Rezept verwerfen, nicht die Quelle
        if type(reagent) ~= "table" or not ID(reagent.id) or not Number(reagent.count) or reagent.count <= 0 then return "entry" end
    end
    return "ok"
end

local function GoodItem(item)
    if type(item) ~= "table" or not ID(item.id) then return false end
    local chance = item.chance
    if Core.IsSecret(chance) then return false end              -- zuerst prüfen: einen geheimen Wert nie mit nil vergleichen
    return chance == nil or (type(chance) == "number" and chance >= 0 and chance <= 1)
end

function CHECK.lootOf(r)
    if type(r) ~= "table" or type(r.items) ~= "table" then return "shape" end
    local kept, dropped = {}, 0
    for _, item in ipairs(r.items) do
        if GoodItem(item) then kept[#kept + 1] = item else dropped = dropped + 1 end
    end
    if dropped == 0 then return "ok", 0 end
    r.items = kept
    if #kept == 0 then return "entry", dropped end
    return "ok", dropped
end

-- Inhalt eines Behälters bzw. einer Kiste: dieselbe Form wie die Beute eines Gegners (items mit id, chance nil)
CHECK.contentsOf = CHECK.lootOf

-- „Woher?“: Listen von Einträgen; ein unbrauchbarer Eintrag fällt einzeln weg, eine Liste in falscher Form heißt
-- „shape“. Ohne einen einzigen Eintrag: "entry" (nur diese Antwort ist leer).
Sources.WHERE_LISTS = { "drops", "objects", "containers", "vendors", "quests" }
local WHERE_KIND = { drops = "npc", objects = "object", containers = "item", vendors = "npc", quests = "quest" }

local function GoodWhere(e, kind)
    if type(e) ~= "table" or e.kind ~= kind or not ID(e.id) then return false end
    if Core.IsSecret(e.name) or (e.name ~= nil and type(e.name) ~= "string") then return false end
    for _, f in ipairs({ "lo", "hi", "x", "y", "cnt", "price", "area", "map", "rank" }) do
        if Core.IsSecret(e[f]) or (e[f] ~= nil and type(e[f]) ~= "number") then return false end
    end
    if e.x ~= nil and (e.x < 0 or e.x > 1) then return false end
    if e.y ~= nil and (e.y < 0 or e.y > 1) then return false end
    return true
end

function CHECK.whereFrom(r)
    if type(r) ~= "table" or not ID(r.item) then return "shape" end
    local total, dropped = 0, 0
    for _, list in ipairs(Sources.WHERE_LISTS) do
        local entries = r[list]
        if entries ~= nil then
            if type(entries) ~= "table" then return "shape" end
            local kept = {}
            for _, e in ipairs(entries) do
                if GoodWhere(e, WHERE_KIND[list]) then kept[#kept + 1] = e else dropped = dropped + 1 end
            end
            r[list] = #kept > 0 and kept or nil
            total = total + #kept
        end
    end
    if total == 0 then return "entry", dropped end
    return "ok", dropped
end

function CHECK.recipesUsing(r)
    if type(r) ~= "table" then return "shape" end
    local kept, dropped = {}, 0
    for _, e in ipairs(r) do
        local key = false
        if type(e) == "table" then
            local r = e.recipeID
            key = ID(r) ~= nil or ID(e.spell) ~= nil
                or (not Core.IsSecret(r) and type(r) == "string" and r ~= "")
        end
        if key and Number(e.count) and e.count > 0
            and not Core.IsSecret(e.name) and type(e.name) == "string" and e.name ~= "" then
            kept[#kept + 1] = e
        else
            dropped = dropped + 1
        end
    end
    for i = #r, 1, -1 do r[i] = nil end
    for i, e in ipairs(kept) do r[i] = e end
    if #kept == 0 then return "entry", dropped end
    return "ok", dropped
end

-- Verworfene Einträge je Quelle zählen (jede Auskunft und ID nur einmal – derselbe Tooltip zählt nicht hoch).
local function Skip(key, ask, arg)
    local seen = skipped[key]
    if not seen then
        seen = { n = 0, ids = {} }
        skipped[key] = seen
    end
    local id = ask .. ":" .. tostring(arg)
    if not seen.ids[id] then
        seen.ids[id] = true
        seen.n = seen.n + 1
    end
end

function Sources.Skipped(key)
    return skipped[key] and skipped[key].n or 0
end

-- Läuft das Addon in der erwarteten Form? (nur ready, ohne den Stand der letzten Antwort)
local function Ready(key, source)
    if not source.ready then return true end
    local ok, ready = pcall(source.ready)
    if not ok then
        Report(key, "ready", ready)
        return false
    end
    return ready == true
end

-- Antwort einer Quelle → Ergebnis, Grund: "ok" (Antwort), "none" (saubere Antwort „nichts“), "entry" (Eintrag
-- verworfen), "shape" (falsche Form), "error" (Fehler), "skip" (nicht nachgesehen), "missing" (Addon läuft nicht).
-- Ohne diese Auskunft: nil, nil.
local function Query(key, ask, ...)
    local source = registry[key]
    local fn = source and source[ask]
    if not fn then return nil, nil end
    if not Ready(key, source) then return nil, "missing" end
    local ok, result, why = pcall(fn, ...)
    if not ok then
        Report(key, ask, result)
        return nil, "error"
    end
    if result == nil then
        if why == "shape" then
            problems[key] = "shape"
            return nil, "shape"
        elseif why == "skip" then
            -- die Quelle hat gar nicht nachgesehen (etwa keine Kandidaten): der Stand der letzten Abfrage bleibt
            return nil, "skip"
        elseif why == "entry" then                   -- nur dieser Eintrag passt nicht: die Form der Quelle stimmt
            problems[key] = nil
            Skip(key, ask, (...))
            return nil, "entry"
        end
        -- saubere Antwort „nichts“ (kein Eintrag für diesen Gegenstand): die Quelle antwortet wie erwartet, ein
        -- früherer Stand „shape“ oder „error“ gilt nicht mehr (Hinweis aus Welle 3; A60 geprüft in Welle 23b)
        problems[key] = nil
        return nil, "none"
    end
    local verdict, dropped = "ok", 0
    if CHECK[ask] then verdict, dropped = CHECK[ask](result) end
    if verdict == "shape" then
        problems[key] = "shape"
        return nil, "shape"
    end
    problems[key] = nil
    if verdict == "entry" or (dropped or 0) > 0 then Skip(key, ask, (...)) end
    if verdict == "entry" then return nil, "entry" end
    if type(result) == "table" then
        result.source, result.sourceKey = source.own and Core.L.DB_OWN or source.label, key
        -- Antwort eines fremden Addons: die Entdecker-Datenbank nimmt sie nie an (Leitlinie 10, DB.MarkForeign)
        if not source.own and Core.DB and Core.DB.MarkForeign then Core.DB.MarkForeign(result, key) end
    end
    return result, "ok"
end

-- A60 (Welle 23b): Grund der letzten Frage je Auskunft. Antwortet keine Quelle, zählt der aussagekräftigste Grund:
-- verworfener Eintrag vor falscher Form vor Fehler vor „nichts“ vor „nicht nachgesehen“ vor „läuft nicht“.
local reasons = {}   -- [auskunft] = { why, key, arg }
Sources.REASON_RANK = { ok = 7, entry = 6, shape = 5, error = 4, none = 3, skip = 2, missing = 1 }

local function Weigh(best, why, key)
    if why and (not best or Sources.REASON_RANK[why] > Sources.REASON_RANK[best.why]) then return { why = why, key = key } end
    return best
end

local function NoteReason(ask, best, arg)
    reasons[ask] = { why = best and best.why or "missing", key = best and best.key or nil, arg = arg }
end

function Sources.Ask(ask, ...)
    local best
    for _, key in ipairs(Sources.Order()) do
        local result, why = Query(key, ask, ...)
        if result ~= nil then
            NoteReason(ask, { why = "ok", key = key }, (...))
            return result
        end
        best = Weigh(best, why, key)
    end
    NoteReason(ask, best, (...))
    return nil
end

function Sources.AskAll(ask, ...)
    local out, best = {}, nil
    for _, key in ipairs(Sources.Order()) do
        local result, why = Query(key, ask, ...)
        if result ~= nil then out[#out + 1] = result end
        best = Weigh(best, why, key)
    end
    NoteReason(ask, best, (...))
    return out
end

-- → Grund ("ok" | "entry" | "shape" | "error" | "none" | "skip" | "missing"), Anzeigename der Quelle (nil bei der
-- eigenen Datenbank, Leitlinie 7), Schlüssel der Quelle, gefragte ID – der letzten Frage nach dieser Auskunft; nil,
-- solange nicht gefragt wurde
function Sources.Reason(ask)
    local r = reasons[ask]
    if not r then return nil end
    local source = r.key and registry[r.key]
    return r.why, source and not source.own and source.label or nil, r.key, r.arg
end

-- Satz zum Grund der letzten Frage für Tooltips („AtlasLoot kennt den Eintrag, seine Angaben passen aber nicht“) oder
-- nil, wenn es nichts zu erklären gibt (Antwort, „nichts“, eigene Datenbank). Fehlt ein Addon, sagt es Sources.Hint.
function Sources.ReasonText(ask)
    local why, label = Sources.Reason(ask)
    if not label then return nil end
    local L = Core.L
    if why == "entry" then return L.SOURCES_ENTRY:format(label) end
    if why == "shape" or why == "error" then return L.SOURCES_BROKEN:format(label) end
    return nil
end

function Sources.RecipeFor(itemID)
    itemID = ID(itemID)
    if not itemID then return nil end
    return Sources.Ask("recipeFor", itemID)
end

function Sources.LootOf(npcID, info)
    npcID = ID(npcID)
    if not npcID then return nil end
    if info ~= nil and type(info) ~= "table" then info = nil end
    return Sources.Ask("lootOf", npcID, info)
end

-- Inhalt eines Behälters (art "item", itemID) bzw. einer Kiste (art "object", objectID) laut einer angebundenen
-- Datenbank (22.11.2026, ezLoot Contents.lua). Die Quelle bekommt (id, art) – die ID zuerst, damit verworfene Einträge
-- je ID gezählt werden (Skip).
Sources.CONTENT_KINDS = { item = true, object = true }
function Sources.ContentsOf(kind, id)
    id = ID(id)
    if not (id and Sources.CONTENT_KINDS[kind]) then return nil end
    return Sources.Ask("contentsOf", id, kind)
end

-- Liefert der Client den Gegenstand selbst (volles GetItemInfo mit Namen) oder ist er auf diesem Realm enthüllt?
-- Sonst gilt er als verschleiert: Herkunft und Name aus fremden Datenbanken sind dann Entdecker-Wissen
-- (Leitlinie 11, DG-18). Dieselbe Regel wie DB.Client: GetItemInfoInstant zählt nicht, es antwortet auf Forever auch
-- für nie gesehene Nummern (docs/archiv/probe-ergebnis-2026-11-14.md).
function Sources.ClientKnowsItem(itemID)
    itemID = ID(itemID)
    if not itemID then return false end
    local fn = rawget(_G, "GetItemInfo") or Field(rawget(_G, "C_Item"), "GetItemInfo")
    if type(fn) == "function" then
        local ok, name = pcall(fn, itemID)
        if ok and not Core.IsSecret(name) and type(name) == "string" and name ~= "" then return true end
    end
    local DB = Core.DB
    return DB and DB.Revealed and DB.Revealed(itemID) == true or false
end

function Sources.WhereFrom(itemID, opts)
    itemID = ID(itemID)
    if not itemID then return nil end
    if opts ~= nil and type(opts) ~= "table" then opts = nil end
    if opts and opts.all then return Sources.AskAll("whereFrom", itemID, opts) end
    return Sources.Ask("whereFrom", itemID, opts)
end

-- Zuerst selbst Gesehenes, sonst AtlasLoot – jeder Eintrag nennt seine Quelle (für „Zutat für: … (laut AtlasLoot)“).
function Sources.RecipesUsing(itemID)
    itemID = ID(itemID)
    if not itemID then return {} end
    local list = Sources.Ask("recipesUsing", itemID)
    if type(list) ~= "table" then return {} end
    local out = {}
    for i, e in ipairs(list) do
        local copy = {}
        for k, v in pairs(e) do copy[k] = v end
        copy.source, copy.sourceKey = list.source, list.sourceKey
        out[i] = copy
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.recipeID or a.spell or "") < tostring(b.recipeID or b.spell or "")
    end)
    return out
end

function Sources.OpenFor(npcID, key)
    npcID = ID(npcID)
    if not npcID then return false, "invalid" end
    local keys = key and { key } or Sources.Order()
    local lastWhy = "missing"
    for _, k in ipairs(keys) do
        local source = registry[k]
        -- Ein Fenster ohne den Gegner (AtlasLoot) nur, wenn genau diese Quelle gemeint ist
        if source and source.openFor and (key or not source.generic) and Sources.Status(k) ~= "missing" then
            local ok, opened, why = pcall(source.openFor, npcID)
            if not ok then
                Report(k, "openFor", opened)
                lastWhy = "error"
            elseif opened == true then
                return true, source.label
            else
                lastWhy = type(why) == "string" and why or "closed"
            end
        end
    end
    return false, lastWhy
end

---------------------------------------------------------------------------
-- Texte
---------------------------------------------------------------------------

function Sources.Label(result)
    if type(result) ~= "table" or type(result.source) ~= "string" then return nil end
    local L = Core.L
    local from = registry[result.sourceKey]
    if from and from.own then return L.DB_OWN end           -- eigene Datenbank: „bei dir“, nicht „laut bei dir“
    return L.SOURCES_ACCORDING:format(result.source)
end

function Sources.Hint(ask)
    local L = Core.L
    local missing, broken = {}, {}
    for _, entry in ipairs(Sources.List(ask)) do
        local source = registry[entry.key]
        if entry.status == "ok" and not source.own then return nil end
        -- Stille Rückfälle (silent) und die eigene Datenbank werden nie als „fehlt“ beworben (EC-03, DG-27);
        -- Fehler der eigenen Datenbank stehen in der Fehlerliste, ihr interner Schlüssel nie im Hinweis (Leitlinie 7)
        if entry.status == "missing" then
            if not (source.silent or source.own) then missing[#missing + 1] = entry.label end
        elseif entry.status ~= "ok" and not source.own then
            broken[#broken + 1] = entry.label
        end
    end
    if #broken > 0 then return L.SOURCES_BROKEN:format(table.concat(broken, ", ")) end
    if #missing > 0 then return L.SOURCES_MISSING:format(table.concat(missing, ", ")) end
    return nil
end

-- Übersetzter Text je Zustand für /ez status (Leitlinie 7: nie den internen Schlüssel zeigen)
local STATUS_TEXT = { shape = "SOURCES_STATUS_SHAPE", error = "SOURCES_STATUS_ERROR" }

function Sources.StatusLine()
    local L = Core.L
    local running = {}
    for _, entry in ipairs(Sources.List()) do
        if registry[entry.key].own then
            -- die eigene Datenbank hat ihre eigene Zeile in /ez status (DiscoveryView.lua)
        elseif entry.status == "ok" then
            if entry.skipped > 0 then
                running[#running + 1] = entry.label .. " (" .. L.SOURCES_SKIPPED:format(entry.skipped) .. ")"
            else
                running[#running + 1] = entry.label
            end
        elseif entry.status ~= "missing" then
            running[#running + 1] = entry.label .. " (" .. L[STATUS_TEXT[entry.status] or "SOURCES_STATUS_SHAPE"] .. ")"
        end
    end
    if #running == 0 then return nil end
    return L.STATUS_SOURCES:format(table.concat(running, ", "))
end

---------------------------------------------------------------------------
-- Quelle 0: die eigene Entdecker-Datenbank („bei dir“)
---------------------------------------------------------------------------

local OWN_KIND = { loot = "drops", skin = "drops", pick = "drops", herbCorpse = "drops", mineCorpse = "drops",
    object = "objects", container = "containers" }

local function ItemName(itemID)
    local fn = rawget(_G, "GetItemInfo") or Field(rawget(_G, "C_Item"), "GetItemInfo")
    if type(fn) ~= "function" then return nil end
    local ok, name = pcall(fn, itemID)
    if ok and type(name) == "string" and not Core.IsSecret(name) and name ~= "" then return name end
    return nil
end

local function ZoneName(mapID)
    local fn = Field(rawget(_G, "C_Map"), "GetMapInfo")
    if not ID(mapID) or type(fn) ~= "function" then return nil end
    local ok, info = pcall(fn, mapID)
    local name = ok and Field(info, "name")
    if type(name) == "string" and not Core.IsSecret(name) and name ~= "" then return name end
    return nil
end
Sources.ZoneName = ZoneName

-- Ort und Stufe eines selbst gesehenen NPC bzw. Objekts in den Eintrag (der häufigste Ort zuerst)
local function OwnPlace(e, kind)
    local places = Core.Places and Core.Places.Of(kind, e.id) or {}
    local p = places[1]
    if p and Number(p.map) and p.map > 0 then
        e.map, e.zone = p.map, ZoneName(p.map)
        if Number(p.x) and Number(p.y) and p.x >= 0 and p.x <= 1 and p.y >= 0 and p.y <= 1 then e.x, e.y = p.x, p.y end
    end
end

local function OwnNpc(e)
    local DB = Core.DB
    e.name = DB.Text("npc", e.id)
    local row = DB.Get("npc", e.id)
    local lv = row and row.lvls
    if type(lv) == "table" then e.lo, e.hi = Number(lv.lo), Number(lv.hi) end
    OwnPlace(e, "npc")
end

local function Capped(out, list, e)
    out.n[list] = (out.n[list] or 0) + 1
    if out.n[list] > Sources.WHERE_MAX then return false end
    out[list] = out[list] or {}
    table.insert(out[list], e)
    return true
end

Sources.Register("own", {
    label = "own",
    own = true,
    silent = true,
    ready = function()
        local DB = Core.DB
        if DB and DB.Ready and DB.Ready() then return true end
        return false, "missing"
    end,
    whereFrom = function(itemID)
        local out = { item = itemID, n = {} }
        for _, src in ipairs(Core.Drops and Core.Drops.SourcesOf(itemID) or {}) do
            local list = OWN_KIND[src.kind]
            local id = ID(src.id)
            if list and id then
                local e = { kind = WHERE_KIND[list], id = id, cnt = Number(src.f) }
                if Capped(out, list, e) then
                    if list == "drops" then OwnNpc(e)
                    elseif list == "objects" then e.name = Core.DB.Text("obj", id); OwnPlace(e, "object")
                    else e.name = ItemName(id) end
                end
            end
        end
        for _, v in ipairs(Core.Vendors and Core.Vendors.Selling(itemID) or {}) do
            local id = ID(v.npc)
            if id and not v.gone then
                local e = { kind = "npc", id = id, price = Number(v.pr) }
                if Capped(out, "vendors", e) then OwnNpc(e) end
            end
        end
        for _, list in ipairs(Sources.WHERE_LISTS) do
            if out[list] then return out end
        end
        return nil
    end,
    recipesUsing = function(itemID)
        local K = Core.Knowledge
        local list = K and K.RecipesUsing and K.RecipesUsing(itemID) or {}
        local out = {}
        for _, e in ipairs(list) do
            local rec = type(e.recipe) == "table" and e.recipe or {}
            local name = type(rec.n) == "string" and rec.n or (Number(rec.o) and ItemName(rec.o)) or nil
            local key = ID(e.recipeID) or (type(e.recipeID) == "string" and e.recipeID) or nil
            if name and (key or ID(rec.s)) then
                out[#out + 1] = { recipeID = key, spell = ID(rec.s), name = name, count = Number(e.count) or 1,
                    product = ID(rec.o) }
            end
        end
        if #out == 0 then return nil end
        return out
    end,
})

---------------------------------------------------------------------------
-- Quelle 1: AtlasLoot Classic Forever (Herstellung)
---------------------------------------------------------------------------

local function AtlasProfession()
    local atlas = rawget(_G, "AtlasLoot")
    local data = Field(atlas, "Data")
    return Field(data, "Profession"), Field(data, "Recipe")
end

-- Name des Berufs aus AtlasLoots eigener, schon übersetzter Beschreibung („|cff00ff00Linksklick:|r Alchemie“);
-- AtlasLoot führt den Namen nur in einer lokalen Tabelle. Unbekannter Beruf (0): kein Name.
local function AtlasProfessionName(P, spell, profKey)
    if not profKey or profKey <= 0 then return nil end
    local describe = Field(P, "GetSpellDescription")
    if type(describe) ~= "function" then return nil end
    local ok, text = pcall(describe, spell)
    if not ok or type(text) ~= "string" or Core.IsSecret(text) then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local name = text:match("([^:]+)$")
    name = name and name:match("^%s*(.-)%s*$")
    if not name or name == "" then return nil end
    return name
end

local function SpellName(spell)
    local api = rawget(_G, "C_Spell")
    local fn = Field(api, "GetSpellName")
    if type(fn) ~= "function" then return nil end
    local ok, name = pcall(fn, spell)
    if ok and type(name) == "string" and not Core.IsSecret(name) and name ~= "" then return name end
    return nil
end

-- Fertigkeit laut AtlasLoot: für Forever-Rezepte fehlen die Schwellen durchgehend (0 = unbekannt, der Regelfall;
-- DG-50). Nur echte Schwellen werden geliefert, sonst skill = nil und skillUnknown = true.
local function Skill(a, b, c)
    if a and b and c and a > 0 and b > 0 and c > 0 then return { a, b, c } end
    return nil
end

-- Ein Rezept aus AtlasLoots Daten zu einem Zauber, in eigener, neuer Form. → rezept | nil, "shape" | "entry"
local function AtlasRecipe(P, R, spell, itemID)
    local okData, data = pcall(Field(P, "GetProfessionData"), spell)
    if not okData then error(data, 0) end
    if type(data) ~= "table" then return nil, "shape" end
    -- Ein einzelner unpassender Eintrag verwirft nur diese Antwort ("entry"), nicht die ganze Quelle
    local created = ID(Field(data, 1))
    if created and created ~= itemID then return nil, "entry" end
    local ids, counts = Field(data, 6), Field(data, 7)
    if type(ids) ~= "table" or (counts ~= nil and type(counts) ~= "table") then return nil, "shape" end
    local reagents = {}
    for i = 1, #ids do
        local id = ID(Field(ids, i))
        -- Ohne Mengen-Tabelle je 1; steht eine da, muss jede Menge stimmen (nie still zu 1 machen)
        local count = 1
        if counts then count = Number(Field(counts, i)) end
        if not id or not count or count <= 0 then return nil, "entry" end
        reagents[#reagents + 1] = { id = id, count = count }
    end
    local profKey = Number(Field(data, 2))
    local a, b, c = Number(Field(data, 3)), Number(Field(data, 4)), Number(Field(data, 5))
    local recipeItem
    local forSpell = Field(R, "GetRecipeForSpell")
    if type(forSpell) == "function" then
        local okRecipe, id = pcall(forSpell, spell)
        recipeItem = okRecipe and ID(id) or nil
    end
    local skill = Skill(a, b, c)
    return {
        item = itemID, spell = spell, name = SpellName(spell),
        profession = AtlasProfessionName(P, spell, profKey), professionKey = profKey,
        skill = skill, skillUnknown = skill == nil or nil,
        reagents = reagents, count = Number(Field(data, 8)) or 1, recipeItem = recipeItem,
    }
end

-- Kandidaten für RecipesUsing über AtlasLoot: Produkte, die der Client dir schon gezeigt hat (Zwischenspeicher der
-- Datenbank, cache.item) – AtlasLoot führt keinen Rückweg Zutat » Rezepte, und sein Rezept-Verzeichnis ist von
-- außen nicht aufzählbar. Daraus entsteht ein Umkehr-Index Zutat » Rezepte, nur im Arbeitsspeicher (nichts wird
-- gespeichert), in Scheiben: je Frage höchstens SCAN_MAX noch nicht geprüfte Produkte, die höchsten IDs zuerst.
-- Die Kandidatenliste (sortierte Schlüssel) wird nur neu gelesen, wenn sich DB.Version("item") geändert hat und
-- USING_REFRESH Sekunden vergangen sind – so kostet ein Tooltip (ezCraft fragt bei jedem) nur das Nachschlagen.
Sources.USING_REFRESH = 60
local using = {}

local function UsingIndex(P)
    if using.P ~= P then
        using = { P = P, scanned = {}, spells = {}, by = {}, pending = {}, pos = 1, total = 0, version = nil,
            t = nil, results = {} }
    end
    return using
end

-- Index und Antworten verwerfen (etwa nachdem AtlasLoot neu geladen hat); der nächste Aufruf baut neu.
function Sources.ForgetRecipesUsing()
    using = {}
end

local function UsingRefresh(idx)
    local DB = Core.DB
    local version = DB and DB.Version and DB.Version("item") or 0
    local now = Core.Num(rawget(_G, "GetTime") and GetTime()) or 0
    if idx.version ~= nil and (version == idx.version or now - idx.t < Sources.USING_REFRESH) then return end
    idx.version, idx.t = version, now
    local list = DB and DB.KeysOf and DB.KeysOf("item") or {}
    local pending = {}
    for i = #list, 1, -1 do                                   -- die höchsten IDs (neuere Gegenstände) zuerst
        local product = list[i]
        if not idx.scanned[product] then pending[#pending + 1] = product end
    end
    idx.pending, idx.pos, idx.total = pending, 1, #list
end

-- Höchstens SCAN_MAX Produkte aus idx.pending in den Index aufnehmen. → true | nil, "shape" (Fehler werfen weiter)
local function UsingScan(idx, craft, data)
    local stop = math.min(#idx.pending, idx.pos + Sources.SCAN_MAX - 1)
    local grew = false
    while idx.pos <= stop do
        local product = idx.pending[idx.pos]
        local ok, spell = pcall(craft, product)
        if not ok then error(spell, 0) end
        if Core.IsSecret(spell) then return nil, "shape" end
        if spell ~= nil and not ID(spell) then return nil, "shape" end
        if spell and not idx.spells[spell] then
            local okData, raw = pcall(data, spell)
            if not okData then error(raw, 0) end
            idx.spells[spell] = true
            local ids, counts = Field(raw, 6), Field(raw, 7)
            if type(ids) == "table" then
                for i = 1, #ids do
                    local reagent = ID(Field(ids, i))
                    if reagent then
                        local list = idx.by[reagent]
                        if not list then list = {} idx.by[reagent] = list end
                        -- dieselbe Zutat zweimal im Rezept: ein Eintrag je Rezept (die erste Menge zählt)
                        if not (list[#list] and list[#list].spell == spell) then
                            list[#list + 1] = { spell = spell, product = product, count = counts and Number(Field(counts, i)) or 1 }
                            grew = true
                        end
                    end
                end
            end
        end
        idx.scanned[product] = true
        idx.pos = idx.pos + 1
    end
    if grew then idx.results = {} end
    return true
end

Sources.Register("AtlasLoot", {
    label = "AtlasLoot",
    ready = function()
        local P = AtlasProfession()
        if type(Field(P, "GetCraftSpellForCreatedItem")) == "function" and type(Field(P, "GetProfessionData")) == "function" then
            return true
        end
        if rawget(_G, "AtlasLoot") ~= nil or (Core.OtherAddOn and Core.OtherAddOn("AtlasLoot")) then return false, "shape" end
        return false, "missing"
    end,
    recipeFor = function(itemID)
        local P, R = AtlasProfession()
        local ok, spell = pcall(Field(P, "GetCraftSpellForCreatedItem"), itemID)
        if not ok then error(spell, 0) end
        if Core.IsSecret(spell) then return nil, "shape" end     -- zuerst prüfen: einen geheimen Wert nie mit nil vergleichen
        if spell == nil then return nil end
        spell = ID(spell)
        if not spell then return nil, "shape" end
        return AtlasRecipe(P, R, spell, itemID)
    end,
    recipesUsing = function(itemID)
        local P, R = AtlasProfession()
        local craft, data = Field(P, "GetCraftSpellForCreatedItem"), Field(P, "GetProfessionData")
        local idx = UsingIndex(P)
        UsingRefresh(idx)
        if idx.total == 0 and next(idx.by) == nil then return nil, "skip" end
        local okScan, why = UsingScan(idx, craft, data)
        if not okScan then return nil, why end
        local cached = idx.results[itemID]
        if cached ~= nil then
            if cached == false then return nil end
            return cached
        end
        local out = {}
        for _, e in ipairs(idx.by[itemID] or {}) do
            local rec = AtlasRecipe(P, R, e.spell, e.product)
            if type(rec) == "table" then
                out[#out + 1] = { spell = e.spell, recipeID = e.spell, name = rec.name or rec.profession or ("#" .. e.spell),
                    count = e.count, product = e.product, profession = rec.profession }
            end
        end
        if #out == 0 then
            idx.results[itemID] = false
            return nil
        end
        idx.results[itemID] = out
        return out
    end,
    -- AtlasLoot hat keinen Befehl, der einen bestimmten Boss öffnet (docs/datengrundlage.md 10.1): „/al“ öffnet nur
    -- sein Fenster. Deshalb generic – Core.Sources.OpenFor fragt es nur mit ausdrücklichem Schlüssel.
    generic = true,
    openFor = function()
        local frame = rawget(_G, "AtlasLoot_GUI-Frame")
        local isShown = Field(frame, "IsShown")
        if type(isShown) == "function" then
            local okShown, shown = pcall(isShown, frame)
            if okShown and shown == true then return true end     -- schon offen: nicht wieder zuklappen
        end
        local fn = Field(rawget(_G, "SlashCmdList"), "ATLASLOOT")
        if type(fn) ~= "function" then return false, "missing" end
        local ok, err = pcall(fn, "")
        if not ok then error(err, 0) end
        frame = rawget(_G, "AtlasLoot_GUI-Frame")
        isShown = Field(frame, "IsShown")
        if type(isShown) ~= "function" then return false, "closed" end
        local okShown, shown = pcall(isShown, frame)
        if okShown and shown == true then return true end
        return false, "closed"
    end,
})
