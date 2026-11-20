local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    „Was kommt wann“ im Zauberbuch. Ein Seitenreiter rechts an
    Blizzards Zauberbuch (Blizzard_PlayerSpells, Forever-Fassung „Camelot“) schlägt im Buch selbst eine eigene
    Ansicht auf – an Stelle der Zauberliste, solange der Reiter aktiv ist (Entscheidung des Nutzers 13.11.2026:
    „das kann doch direkt ins Zauberbuch“). Inhalt: was jetzt beim Lehrer wartet, danach je Stufe die neuen Zauber
    und Ränge mit Kosten und der Summe bis zu dieser Stufe (zum Gold sparen). Daten: Core.Spells (lernt bei jedem
    Lehrerbesuch); ohne Lehrerbesuch die „kommt später“-Zauber des Zauberbuchs, noch ohne Kosten, ergänzt um die
    Stufen laut Client (Core.Spells.Coming, C_SpellBook.GetCurrentLevelSpells), soweit ezCore sie liefert.
    Lernstufen und Ränge laut Client-Tabellen (Welle 26, wago F3: Core.Spells.ClientComing, Quelle
    Core.ClientData.SourceText): die Liste ist damit für die eigene Klasse bis zur Höchststufe vollständig, auch ohne
    Lehrerbesuch. Die Stufe nimmt jeder Eintrag zuerst laut Client, dann laut Tabellen, dann laut Lehrer (Leitlinie 11);
    Kosten kennt nur der Lehrer (fehlen sie: „Kosten: noch nicht gesehen“). „Jetzt beim Lehrer“ und die Zahl am Reiter
    bleiben bei Core.Spells.Waiting (dieselbe Zahl wie ezPanel und der Hinweis beim Stufenaufstieg); was nur die
    Tabellen nennen, steht unter seiner Stufe bzw., schon erreicht, in der Gruppe „Erreicht laut Client-Tabellen“.
    Begleiter (MER-08): bei Klassen mit Begleiter (Core.Spells.PetKind) am Ende eine eigene Kopfzeile „Begleiter“ mit
    dem, was sein Ausbilder lehrt (Core.Spells.Available/Upcoming mit der Begleiter-Art); die Zahl am Reiter zählt
    diese Fähigkeiten mit. „Alles lernen“ bleibt beim Tierausbilder aus (Trainer.lua). Die Fußzeile der Ansicht
    (opts.footer) nennt die Quelle: „beim Lehrer gesehen am …“ bzw. „aus deinem Zauberbuch, noch ohne Kosten“.

    Die Ansicht selbst (Buchseiten, Kopfzeilen, Einträge wie SpellBookItemTemplate, Seiten-Layout, Blättern,
    verkleinertes Buch, Seitenreiter, zurück über Kategorie-Reiter und Suche, taint-sicher) baut ezCore:
    Core.NewSpellbookView (seit ezCore 1.7.0, vorher hier). ezMerchant liefert nur die Zeilen und Texte.
    Reiter bei y −70; darunter ezMacros Reiter „Ränge aktualisieren“ (y −114), dann ezCombat „Rotation“ (y −158).
]]

local U = {}
ns.Upcoming = U

local TAB_ICON = "Interface\\Icons\\INV_Misc_Book_11"
local TAB_Y = -70

local view          -- Core.NewSpellbookView, angelegt beim Einloggen

-- Bisherige Felder (Tests, Rundgang): U.view/U.frame = Rahmen der Ansicht, U.tab, U.pools, U.page, U.lines,
-- U.pages, U.spreads – gelesen aus der Ansicht in ezCore.
local FORWARD = { tab = true, pools = true, page = true, lines = true, pages = true, spreads = true }
setmetatable(U, { __index = function(_, key)
    if not view then return nil end
    if key == "view" or key == "frame" then return view.frame end
    if FORWARD[key] then return view[key] end
    return nil
end })

local function Spells() return Core.Spells end

-- Eigene Stufe aus ezCore (Core.PlayerLevel, V-179); 1, solange der Client sie nicht kennt.
local function PlayerLevel()
    return Core.PlayerLevel() or 1
end

local function SpellText(entry)
    if (entry.rank or 0) > 0 then return L.SPELL_RANK:format(entry.name, entry.rank) end
    return entry.name
end

local function Trainable() return _G.SPELLBOOK_TRAINABLE or L.UPCOMING_TRAINABLE end

---------------------------------------------------------------------------
-- Inhalt
---------------------------------------------------------------------------

-- Stufe eines späteren Eintrags in der dritten Zeile (Spieltest 15.11.2026: „bei jedem zauber [steht] das level“): wie
-- beim Begleiter „Stufe n · Kosten“, mit und ohne Lehrerdaten gleich und immer die kurze Form – Blizzards „Verfügbar
-- ab Stufe n“ passte nur bei einstelligen Stufen in die Zeile, also wieder „bei manchen so, bei anderen so“. Kürzte die
-- Ansicht dabei Stufe oder Kosten mit „…“, gilt die erste Form, in der beide ganz bleiben: „Stufe n · Kosten“ unter dem
-- Rang; die Kosten allein und die Stufe in der zweiten Zeile (hinter dem Rang, „Rang 4 · Stufe 58“, ohne Rang allein);
-- mit Rang auch die Stufe allein und die Kosten hinter dem Rang („Stufe unbekannt“ ist lang). Passt keine, bleiben die
-- Kosten ganz und die Stufe steht ganz im Tooltip. Ob der Platz reicht, rechnet ezCores Ansicht (SV.EntryText: Zeilen
-- je Teil samt Name, ein Münzbild wie zwei Zeichen) – keine eigene Zählung; der Name bekommt dann wie bei jedem Eintrag
-- mit Rang eine Zeile. Fehlt sie (älteres ezCore), bleibt es bei „Stufe n · Kosten“. name: Name des Eintrags.
-- → dritte Zeile, zweite Zeile
local function Whole(part)
    return type(part) == "table" and (tonumber(part.lines) or 0) > 0 and part.text == part.full
end

local function LevelDetail(levelText, cost, sub, name)
    if not cost then return levelText, sub end
    local tries = { { levelText .. " · " .. cost, sub } }
    if sub then
        tries[2] = { cost, sub .. " · " .. levelText }
        tries[3] = { levelText, sub .. " · " .. cost }
    else
        tries[2] = { cost, levelText }
    end
    local SV = Core.SpellbookView
    if not (type(SV) == "table" and type(SV.EntryText) == "function") then return tries[1][1], tries[1][2] end
    for _, try in ipairs(tries) do
        local fit = SV.EntryText({ name = name, sub = try[2], detail = try[1] })
        if Whole(fit.detail) and (not try[2] or Whole(fit.sub)) then return try[1], try[2] end
    end
    return tries[2][1], tries[2][2]
end

-- Tooltip-Zeilen zur Stufe eines späteren Eintrags: die Stufe und woher sie stammt (Leitlinie 11); weicht der Client
-- vom Lehrer ab (nur mit Lehrerdaten, trainerData), auch was der Lehrer nannte; ohne Stufe der Grund. pet: Fähigkeit
-- des Begleiters – deren Stufe stammt nur von seinem Ausbilder (U.EntryLevel fragt den Client nicht), das sagt
-- UPCOMING_PET_TIP unten; keine Zeile, die den Client als Grund nennt.
local function LevelTip(tip, entry, level, from, trainerData, pet)
    if not level then
        tip[#tip + 1] = L.UPCOMING_LEVEL_UNKNOWN
        tip[#tip + 1] = { pet and L.UPCOMING_LEVEL_UNKNOWN_PET_TIP or L.UPCOMING_LEVEL_UNKNOWN_TIP, "hint" }
        return
    end
    tip[#tip + 1] = L.UPCOMING_LEVEL:format(level)
    if entry.client or pet then return end                -- UPCOMING_FROM_CLIENT bzw. UPCOMING_PET_TIP nennt die Quelle
    if entry.tables then                                   -- nur laut Client-Tabellen: der Rang von dort
        if from == "client" then                           -- die Stufe nennt der Client selbst (Leitlinie 11)
            tip[#tip + 1] = { L.UPCOMING_LEVEL_SRC_CLIENT, "hint" }
            tip[#tip + 1] = { L.UPCOMING_RANK_FROM_TABLES:format(U.TableSource() or "?"), "hint" }
            local tables = ns.Num(entry.level)
            if tables and tables ~= level then
                tip[#tip + 1] = { L.UPCOMING_LEVEL_TABLES_DIFF:format(tables), "normal" }
            end
        else
            tip[#tip + 1] = { L.UPCOMING_FROM_TABLES:format(U.TableSource() or "?"), "hint" }
        end
        -- Volk und Fraktion filtert ezCore seit Welle 26 (Spells.ClientComing nach der Volksmaske) – kein Hinweis mehr
        return
    end
    if from == "tables" then
        tip[#tip + 1] = { L.UPCOMING_LEVEL_SRC_TABLES:format(U.TableSource() or "?"), "hint" }
        local trainer = ns.Num(entry.level)
        if trainerData and trainer and trainer ~= level then
            tip[#tip + 1] = { L.UPCOMING_LEVEL_TRAINER_DIFF:format(trainer), "normal" }
        end
    elseif from == "client" then
        tip[#tip + 1] = { L.UPCOMING_LEVEL_SRC_CLIENT, "hint" }
        local trainer = ns.Num(entry.level)
        if trainerData and trainer and trainer ~= level then
            tip[#tip + 1] = { L.UPCOMING_LEVEL_TRAINER_DIFF:format(trainer), "normal" }
        end
    else
        tip[#tip + 1] = { L.UPCOMING_LEVEL_SRC_TRAINER, "hint" }
    end
end

-- Eintrag für die Ansicht (Felder von Core.NewSpellbookView): Name, Rang, Kosten bzw. Stufe, Symbol, Tooltip;
-- jetzt beim Lehrer mit Blizzards Rahmen „beim Lehrer erlernbar“, später grau wie „kommt später“ und mit der Stufe
-- (U.EntryLevel: zuerst laut Client, dann laut Lehrer; fehlt sie, „Stufe unbekannt“ mit dem Grund im Tooltip).
-- pet: Fähigkeit des Begleiters (Abschnitt „Begleiter“ ohne Stufen-Kopfzeilen). known: Stufen laut Client
-- (U.ClientLevels), einmal je Liste gerechnet. shown: Stufe und Quelle, schon gerechnet (ByShownLevel), sonst nil.
-- state "reached": nur laut Client-Tabellen, Stufe schon erreicht (unter der Kopfzeile seiner Stufe, ReachedLines) –
-- grau wie „später“, mit Stufe und Kosten im Eintrag und dem Grund samt Quelle im Tooltip. Ohne Preis (nur Tabellen oder Zauberbuch) steht „Kosten: noch nicht gesehen“ im
-- Tooltip, mit Lehrerdaten (withCost) auch im Eintrag – die übrigen Einträge nennen dort ihre Kosten.
-- Jetzt dran, aber nur laut Client-Tabellen und ohne Lehrerbesuch (Core.Spells.BookEntries, tables = true; seit Welle
-- 26 in der Zahl am Reiter): statt „beim Lehrer erlernbar“ steht im Eintrag wie bei den anderen Einträgen die Stufe (und
-- Kosten, sobald bekannt; Spielbefund des Nutzers vom 19.11.2026: „Erreicht laut Client-Tabellen“ sei „unsinn“), der
-- Tooltip nennt die Tabellen samt Build und dass auch eine Quest den Rang lehren kann (Leitlinie 11).
local function SpellLine(entry, state, withCost, pet, known, shown)
    local now = state == "now"
    local tablesNow = now and entry.tables and not withCost and not pet
    local rank = tonumber(entry.rank) or 0
    local cost = withCost and entry.cost ~= nil and ns.Money(entry.cost) or nil
    local costText = entry.cost and ns.Money(entry.cost) or (withCost and not pet and L.UPCOMING_COST_UNSEEN) or nil
    local sub = rank > 0 and L.UPCOMING_RANK:format(rank) or nil
    local detail                      -- nie nil: sonst zeigte die Ansicht right (Kosten) als dritte Zeile
    local level, from
    local tip = {}
    if tablesNow then
        detail, sub = LevelDetail(entry.level and L.UPCOMING_LEVEL:format(entry.level) or L.UPCOMING_LEVEL_UNKNOWN,
            costText, sub, entry.name)
        if entry.level then tip[#tip + 1] = L.UPCOMING_LEVEL:format(entry.level) end
        tip[#tip + 1] = { L.UPCOMING_FROM_TABLES:format(U.TableSource() or "?"), "hint" }
    elseif now then
        local label = Trainable()
        detail = costText and (label .. " · " .. costText) or label
        if entry.level then tip[#tip + 1] = L.UPCOMING_LEVEL:format(entry.level) end
    else
        if shown then level, from = shown.level, shown.from else level, from = U.EntryLevel(entry, pet, known) end
        detail, sub = LevelDetail(level and L.UPCOMING_LEVEL:format(level) or L.UPCOMING_LEVEL_UNKNOWN, costText, sub,
            entry.name)
        LevelTip(tip, entry, level, from, withCost, pet)
    end
    if entry.cost then
        tip[#tip + 1] = L.UPCOMING_COST:format(ns.Money(entry.cost))
    elseif not pet then
        tip[#tip + 1] = L.UPCOMING_COST_UNSEEN
        tip[#tip + 1] = { L.UPCOMING_COST_UNSEEN_TIP, "hint" }
    end
    if state == "reached" then
        tip[#tip + 1] = { withCost and L.UPCOMING_REACHED_TIP or L.UPCOMING_REACHED_TIP_NODATA, "normal" }
    end
    if tablesNow then
        tip[#tip + 1] = { L.UPCOMING_NOW_TABLES_TIP, "normal" }
    elseif now then
        tip[#tip + 1] = { Trainable(), "good" }
    end
    if pet then tip[#tip + 1] = { L.UPCOMING_PET_TIP, "hint" } end
    if entry.client then tip[#tip + 1] = { L.UPCOMING_FROM_CLIENT, "hint" } end
    return { kind = "spell", left = SpellText(entry), right = cost, icon = entry.icon, entry = entry, state = state,
        name = entry.name, sub = sub, detail = detail, pet = pet or nil, level = level, levelFrom = from,
        spellID = tonumber(entry.id), style = now and "trainable" or "future", tooltip = tip }
end

-- Ohne Lehrerbesuch: die „kommt später“-Zauber des Zauberbuchs, ergänzt um die Zauber je Stufe laut Client – seit
-- Welle 23 (A44) aus EINER Stelle: Core.Spells.BookEntries (dieselbe Liste zählt Core.Spells.Waiting für ezPanel und
-- den Hinweis beim Stufenaufstieg). Fehlt im Zauberbuch die Stufe, gilt die des Clients; was nur der Client nennt,
-- trägt client = true; gelernte Ränge und unbenannte Zauber bleiben weg. → Liste, ob der Client etwas geliefert hat
-- Die Abfrage fragt je Zauber Name, Rang, Symbol und „bekannt“ beim Client nach; die Ansicht holt Zeilen, Fußzeile
-- und Zahl am Reiter im selben Bild – deshalb gilt das Ergebnis für dieses Bild (gleiches GetTime(), gleiche
-- Funktionen, gleiche Höchststufe) und wird verworfen, sobald sich das Zauberbuch oder die Stufe ändert (unten).
local bookCache = {}
local tableCache = {}       -- dasselbe für die Client-Tabellen (U.TableEntries)

function U.ForgetClient() bookCache, tableCache = {}, {} end

local function EntryKey(name, rank) return tostring(name) .. "#" .. (tonumber(rank) or 0) end

function U.BookEntries(S)
    S = S or Spells()
    if not (S and type(S.BookEntries) == "function") then return {}, false end
    local now = type(GetTime) == "function" and GetTime() or nil
    local maxLevel = Core.MaxLevel()
    local c = bookCache
    if now ~= nil and c.at == now and c.fn == S.BookEntries and c.coming == S.Coming and c.future == S.Future
        and c.max == maxLevel then
        return c.list, c.client
    end
    local ok, list, client = pcall(S.BookEntries)
    if not ok then
        ns.Error(list, "Spells.BookEntries")
        list, client = nil, false
    end
    list = type(list) == "table" and list or {}
    client = client == true
    bookCache = { at = now, fn = S.BookEntries, coming = S.Coming, future = S.Future, max = maxLevel, list = list,
        client = client }
    return list, client
end

---------------------------------------------------------------------------
-- Lernstufen und Ränge laut Client-Tabellen (Welle 26, wago F3; ezCore: Core.Spells.ClientComing aus
-- Core.ClientData, Tabelle „classSpells“). Leitlinie 11: die Tabellen gehen vor der Beobachtung beim Lehrer, die
-- Beobachtung bleibt Rückfall und Gegenprobe (weicht der Lehrer ab, sagt es der Tooltip). Kosten führt der Client
-- nicht – sie bleiben die Erhebung beim Lehrer.
---------------------------------------------------------------------------

-- Quelle der Tabellen als Text („laut Client-Tabellen (wago.tools, Build …)“) oder nil (ezCore ohne Tabellen).
function U.TableSource()
    local CD = Core.ClientData
    if not (type(CD) == "table" and type(CD.SourceText) == "function") then return nil end
    local ok, text = pcall(CD.SourceText, "classSpells")
    return ok and type(text) == "string" and text ~= "" and text or nil
end

-- Alle noch nicht gelernten Klassenzauber laut Client-Tabellen, von Stufe 1 bis zur Höchststufe:
-- { { id, name, rank, level, base, icon, tables = true } … } nach Stufe (Spells.ClientComing); ohne Unbenannte und
-- ohne höhere Ränge nicht gelernter Talente. Zweiter Wert: liefert ezCore die Tabelle? Gilt wie U.BookEntries für
-- dieses Bild (gleiches GetTime(), gleiche Funktion, gleiche Höchststufe) und fällt mit U.ForgetClient.
-- Welle 27 (Paket kern/review-454, Review zu PR 454): Was offen ist, entscheidet ezCore (Core.Spells.OpenTableEntries
-- über Spells.TableEntryOpen – eine Rechnung mit Core.Spells.BookEntries; vorher standen „gelernt?“ und „Talent
-- fehlt?“ hier ein zweites Mal). Damit fallen auch die Lernzauber des Begleiters (Jäger: Klaue, Ducken …; pet = true)
-- und ausgelöste Zauber (triggered) weg, dazu ein Eintrag mit Name, Stufe und Rang eines gelernten.
function U.TableEntries(S)
    S = S or Spells()
    if not (S and type(S.ClientComing) == "function") then return {}, false end
    local now = type(GetTime) == "function" and GetTime() or nil
    local maxLevel = Core.MaxLevel()
    local c = tableCache
    if now ~= nil and c.at == now and c.fn == S.ClientComing and c.max == maxLevel then return c.list, c.has end
    local ok, raw = pcall(S.ClientComing, 0, maxLevel)
    if not ok then
        ns.Error(raw, "Spells.ClientComing")
        raw = nil
    end
    local list = {}
    local okOpen, open = pcall(S.OpenTableEntries, type(raw) == "table" and raw or {})
    if not okOpen then
        ns.Error(open, "Spells.OpenTableEntries")
        open = nil
    end
    for _, e in ipairs(type(open) == "table" and open or {}) do
        list[#list + 1] = { id = ns.Num(e.id), name = e.name, rank = ns.Num(e.rank) or 0, level = ns.Num(e.level),
            base = ns.Num(e.base), icon = e.icon, tables = true }
    end
    local has = type(raw) == "table"
    tableCache = { at = now, fn = S.ClientComing, max = maxLevel, list = list, has = has }
    return list, has
end

-- Was die bisherige Quelle schon nennt: mit Lehrerbesuch alles, was der Lehrer je anbot (Core.Spells.Trainer, auch
-- Gelerntes), sonst U.BookEntries. → Menge der Schlüssel Name#Rang, Menge der Zauber-IDs, [Name@Stufe] = höchster Rang
-- dort (0 = ohne Rang). Name@Stufe fängt ab, dass die Tabellen Ränge über den englischen Namen zählen: weicht die
-- Zählung vom Lehrer ab, stünde derselbe Zauber sonst zweimal da. Ein höherer Rang derselben Stufe gilt nicht als
-- abgedeckt (Feuerball 25306, Rang 12, neben Rang 11 beim Lehrer; Gegenprüfung des Reviews zu PR 454).
local function Covered(S, trainerSeen)
    local keys, ids, levels = {}, {}, {}
    local list
    if trainerSeen and type(S.Trainer) == "function" then list = S.Trainer() else list = U.BookEntries(S) end
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if type(e) == "table" then
            keys[EntryKey(e.name, e.rank)] = true
            local level = ns.Num(e.level)
            if level then
                local key = tostring(e.name) .. "@" .. level
                levels[key] = math.max(levels[key] or 0, ns.Num(e.rank) or 0)
            end
            local id = ns.Num(e.id)
            if id then ids[id] = true end
        end
    end
    return keys, ids, levels
end

-- Deckt Name@Stufe einen Eintrag der Tabellen ab? (siehe Covered)
local function LevelCovers(levels, e)
    local top = levels[tostring(e.name) .. "@" .. tostring(e.level)]
    return top ~= nil and (top == 0 or (ns.Num(e.rank) or 0) <= top)
end

-- Was nur die Client-Tabellen nennen (weder der Lehrer bei deinem letzten Besuch noch dein Zauberbuch): schon
-- erreicht (Stufe bis level) und später, beide nach Stufe. Diese Einträge zählen nicht in der Zahl am Reiter
-- (Core.Spells.Waiting zählt sie nicht – dieselbe Zahl wie ezPanel). Seit Welle 26 (Paket kern/ezcore-reste-24) nimmt
-- Core.Spells.BookEntries die Tabellen selbst auf: ohne Lehrerbesuch deckt U.BookEntries alles ab, und hier bleibt
-- nur, was dein letzter Lehrerbesuch nicht nannte. → erreicht, später, Tabelle vorhanden?
function U.TableExtra(level, S)
    S = S or Spells()
    level = ns.Num(level) or PlayerLevel()
    local reached, later = {}, {}
    if not S then return reached, later, false end
    local entries, has = U.TableEntries(S)
    if #entries == 0 then return reached, later, has end
    local keys, ids, levels = Covered(S, type(S.TrainerSeen) == "function" and S.TrainerSeen())
    local known = U.ClientLevels(S)                        -- dieselben Listen dieses Bilds, keine zweite Abfrage
    for _, e in ipairs(entries) do
        if not ((e.id and ids[e.id]) or keys[EntryKey(e.name, e.rank)] or LevelCovers(levels, e)) then
            -- einsortiert nach der Stufe, die der Eintrag zeigt (U.EntryLevel: zuerst laut Client, dann Tabellen)
            local shown = U.EntryLevel(e, nil, known) or e.level
            if shown <= level then reached[#reached + 1] = e else later[#later + 1] = e end
        end
    end
    return reached, later, has
end

-- Stufen laut Client für spätere Einträge: Name#Rang → Eintrag aus U.BookEntries (Zauberbuch „kommt später“ und
-- Zauber je Stufe, mit ID und Stufe), ergänzt um die Client-Tabellen (U.TableEntries, Feld tables) – wo das Zauberbuch
-- den Eintrag nicht oder ohne Stufe kennt. Einmal je Liste; ohne Zauber-Wissen leer.
function U.ClientLevels(S)
    S = S or Spells()
    local byKey = {}
    if not S then return byKey end
    for _, entry in ipairs((U.BookEntries(S))) do byKey[EntryKey(entry.name, entry.rank)] = entry end
    for _, entry in ipairs((U.TableEntries(S))) do
        local key = EntryKey(entry.name, entry.rank)
        local hit = byKey[key]
        if not (hit and ns.Num(hit.level)) then byKey[key] = entry end
    end
    return byKey
end

-- Stufe, ab der ein späterer Eintrag lernbar ist, und woher sie stammt (Leitlinie 11, in dieser Reihenfolge):
--   "client": C_Spell.GetSpellLevelLearned über Core.Spells.LevelLearned (nur dessen Antwort laut Client oder
--             Zauberbuch – Lehrer und eigene Tabellen folgen erst danach), sonst das Zauberbuch bzw. die Zauber je
--             Stufe mit gleichem Namen und Rang (U.ClientLevels; Lehrerdaten tragen keine Zauber-ID);
--   "tables":  die Client-Tabellen (U.ClientLevels, Einträge mit tables = true; Welle 26, wago F3);
--   "trainer": die Lehrerdaten aus Core.Spells (entry.level).
-- Fähigkeiten des Begleiters (pet) nur laut seinem Ausbilder – das Zauberbuch des Spielers gilt für sie nicht.
-- → Stufe, Quelle; nil, wenn weder Client noch Tabellen noch Lehrer eine nennen
function U.EntryLevel(entry, pet, known)
    if type(entry) ~= "table" then return nil end
    if not pet then
        local S = Spells()
        known = known or U.ClientLevels(S)
        local hit = known[EntryKey(entry.name, entry.rank)]
        local id = tonumber(entry.id) or (hit and tonumber(hit.id))
        if id and S and type(S.LevelLearned) == "function" then
            local ok, level, from = pcall(S.LevelLearned, id)
            level = ok and ns.Num(level) or nil
            if level and level > 0 and (from == "client" or from == "book") then return level, "client" end
        end
        local level = hit and ns.Num(hit.level)
        if level and level > 0 then return level, hit.tables and "tables" or "client" end
        if entry.tables and ns.Num(entry.level) then return ns.Num(entry.level), "tables" end
    end
    local level = ns.Num(entry.level)
    if level and level > 0 then return level, "trainer" end
    return nil
end

-- Spätere Einträge mit der Stufe, die jeder von ihnen zeigt (U.EntryLevel), sortiert nach dieser Stufe (ohne Stufe
-- zuletzt, sonst in der bisherigen Reihenfolge). Kopfzeilen und Summen gruppieren nach derselben Stufe wie die
-- Einträge: nennt der Client eine andere Stufe als der Lehrer, stünde sonst unter „Stufe 20“ ein Eintrag „Stufe 22“ –
-- wieder „bei manchen so, bei anderen so“ (Spieltest 15.11.2026). Was der Lehrer nannte, sagt der Tooltip des
-- Eintrags (UPCOMING_LEVEL_TRAINER_DIFF). → { { entry, level, from, index } … }
local function ByShownLevel(list, known)
    local rows = {}
    for i, entry in ipairs(list) do
        local level, from = U.EntryLevel(entry, nil, known)
        rows[i] = { entry = entry, level = level, from = from, index = i }
    end
    table.sort(rows, function(a, b)
        if a.level ~= b.level then
            if a.level == nil or b.level == nil then return b.level == nil end
            return a.level < b.level
        end
        return a.index < b.index
    end)
    return rows
end

-- Kopfzeile einer Stufe (ohne Stufe: „Stufe unbekannt“).
local function LevelHeader(level)
    return level and L.UPCOMING_LEVEL:format(level) or L.UPCOMING_LEVEL_UNKNOWN
end

-- Ohne Lehrerbesuch „jetzt“: Stufe erreicht oder unbekannt (wie bisher Core.Spells.Waiting). Eine Regel für die
-- Gruppe „Jetzt beim Lehrer“ und die Zahl am Reiter.
local function BookNow(entry, level) return (tonumber(entry.level) or 0) <= level end

-- Ohne Lehrerbesuch: wie viele Einträge aus U.BookEntries jetzt dran sind (dieselben wie unter „Jetzt beim Lehrer“).
function U.BookWaiting(level, S)
    level = level or PlayerLevel()
    local count = 0
    for _, entry in ipairs((U.BookEntries(S))) do
        if BookNow(entry, level) then count = count + 1 end
    end
    return count
end

-- Laut Client-Tabellen schon erreicht, beim Lehrer nicht gesehen (U.TableExtra): gleich nach „Jetzt beim Lehrer“, grau
-- wie „später“, nicht in der Zahl am Reiter. Wie die anderen Einträge unter der Kopfzeile ihrer Stufe, mit Stufe und
-- Kosten im Eintrag; der Tooltip sagt, warum der Eintrag nicht unter „Jetzt beim Lehrer“ steht, die Quelle nennen
-- Tooltip und Fußzeile (Spielbefund des Nutzers vom 19.11.2026: die eigene Kopfzeile „Erreicht laut Client-Tabellen“
-- war „unsinn“).
local function ReachedLines(lines, reached, withCost, known)
    if #reached == 0 then return end
    local current = false
    for _, row in ipairs(ByShownLevel(reached, known)) do
        if row.level ~= current then
            current = row.level
            lines[#lines + 1] = { kind = "header", left = LevelHeader(current), level = current, reached = true }
        end
        lines[#lines + 1] = SpellLine(row.entry, "reached", withCost, nil, known, row)
    end
end

-- Ohne Lehrerbesuch: was das Zauberbuch schon als „kommt später“ zeigt, dazu die Stufen laut Client und die
-- Client-Tabellen (Welle 26), ohne Kosten.
local function FutureLines(S, level, lines)
    local future, client = U.BookEntries(S)
    local reached, extra, tables = U.TableExtra(level, S)
    local intro = (tables and L.UPCOMING_NO_DATA_TABLES) or (client and L.UPCOMING_NO_DATA_CLIENT) or L.UPCOMING_NO_DATA
    lines[#lines + 1] = { kind = "text", left = intro, noData = true }
    local now, current = {}, nil
    local known = U.ClientLevels(S)                      -- dieselben Listen dieses Bilds, keine zweite Abfrage
    for _, entry in ipairs(future) do
        if BookNow(entry, level) then now[#now + 1] = entry end
    end
    if #now > 0 then
        lines[#lines + 1] = { kind = "header", left = L.UPCOMING_NOW }
        for _, entry in ipairs(now) do lines[#lines + 1] = SpellLine(entry, "now", false) end
    end
    ReachedLines(lines, reached, false, known)
    local later = {}
    for _, entry in ipairs(future) do
        if not BookNow(entry, level) then later[#later + 1] = entry end
    end
    for _, entry in ipairs(extra) do later[#later + 1] = entry end
    current = false                    -- wie in U.SpellLines: auch ohne Stufe eine Kopfzeile („Stufe unbekannt“)
    for _, row in ipairs(ByShownLevel(later, known)) do
        if row.level ~= current then
            current = row.level
            lines[#lines + 1] = { kind = "header", left = LevelHeader(current), level = current }
        end
        lines[#lines + 1] = SpellLine(row.entry, "later", false, nil, known, row)
    end
    return lines
end

---------------------------------------------------------------------------
-- Lehrer auf der Karte zeigen (MAP-21, Teil ezMerchant): ezMaps Schnittstelle (ezCore.API("ezMap")) kennt die
-- gemerkten Lehrer und setzt Blizzards Kartenmarkierung; hier nur der Eintrag in „Was kommt wann“ und der Klick.
---------------------------------------------------------------------------

local WAY_ICON = "Interface\\Icons\\INV_Misc_Map_01"

-- ezMaps Schnittstelle, wenn ezMap läuft und Lehrer findet; sonst nil.
function U.MapAPI()
    local api = Core.API("ezMap")
    if type(api) == "table" and type(api.NearestTrainer) == "function" and type(api.SetWaypoint) == "function" then
        return api
    end
    return nil
end

-- Nächster gemerkter Lehrer deiner Klasse auf diesem Kontinent (laut ezMap) oder nil.
function U.NearestTrainer()
    local api = U.MapAPI()
    if not api then return nil end
    local ok, t = pcall(api.NearestTrainer, "class")
    if not ok or type(t) ~= "table" or not (ns.Num(t.map) and ns.Num(t.x) and ns.Num(t.y)) then return nil end
    return t
end

local function TrainerName(t)
    local label = Core.Npcs and Core.Npcs.Label and Core.Npcs.Label(t)
    return type(label) == "string" and label or (type(t.name) == "string" and t.name) or "?"
end

local function TrainerPlace(t)
    local name = Core.MapName and Core.MapName(t.map)
    return type(name) == "string" and name or ("#" .. tostring(t.map))
end

-- Kennt das Spiel die eigene Position? Ohne sie (Instanz, gesperrter Wert) findet ezMap keinen Lehrer – das heißt
-- dann nicht, dass keiner gemerkt ist.
local function PositionKnown()
    local mapID = Core.PlayerPosition and Core.PlayerPosition()
    return mapID ~= nil
end

-- Kartenmarkierung auf den nächsten Lehrer setzen und im Chat sagen, wohin (oder warum nicht). → true, wenn gesetzt
function U.GoToTrainer()
    local api = U.MapAPI()
    if not api then
        ns.Print(L.UPCOMING_WAY_NOMAP)
        return false
    end
    local t = U.NearestTrainer()
    if not t then
        ns.Print(PositionKnown() and L.UPCOMING_WAY_NONE or L.UPCOMING_WAY_NOPOS)
        return false
    end
    local name = TrainerName(t)
    local ok, done, err = pcall(api.SetWaypoint, t.map, t.x, t.y, name)
    if ok and done then
        ns.Print(L.UPCOMING_WAY_SET:format(name, TrainerPlace(t)))
        return true
    end
    ns.Print(L.UPCOMING_WAY_FAILED:format(tostring(ok and err or done or "?")))
    return false
end

-- Eintrag „Lehrer auf der Karte zeigen“ (nur mit ezMap); ein Klick darauf ruft U.GoToTrainer (onClick unten).
function U.WayLine()
    if not U.MapAPI() then return nil end
    local t = U.NearestTrainer()
    local sub
    if t then
        sub = L.UPCOMING_WAY_TO:format(TrainerName(t), TrainerPlace(t))
    else                                        -- wie U.GoToTrainer: ohne Position heißt nil nicht „keiner gemerkt“
        sub = PositionKnown() and L.UPCOMING_WAY_UNKNOWN or L.UPCOMING_WAY_NOPOS_SHORT
    end
    -- Kurzer Name im Eintrag (Spielbefund des Nutzers vom 19.11.2026: „Lehrer auf der...“ stand abgeschnitten), der
    -- volle Text ist der Titel des Tooltips.
    return { kind = "spell", action = "trainerWay", left = L.UPCOMING_WAY_SHORT, name = L.UPCOMING_WAY_SHORT,
        title = L.UPCOMING_WAY,
        sub = sub, detail = L.UPCOMING_WAY_SOURCE, icon = WAY_ICON, style = "trainable",
        tooltip = { { L.UPCOMING_WAY_TIP, "highlight" }, { L.UPCOMING_WAY_SOURCE_TIP, "hint" } } }
end

-- Den Eintrag einreihen: unter „Jetzt beim Lehrer“, sonst oben (nach dem Hinweis ohne Lehrerdaten).
local function AddWay(lines)
    local way = U.WayLine()
    if not way then return lines end
    local at = 1
    for i, line in ipairs(lines) do
        if line.kind == "header" and line.left == L.UPCOMING_NOW then at = i + 1 break end
    end
    if at == 1 and lines[1] and lines[1].kind == "text" and lines[1].noData then at = 2 end
    table.insert(lines, at, way)
    return lines
end

-- Klick auf einen Eintrag der Ansicht (Core.NewSpellbookView: onClick).
function U.Click(line)
    if type(line) == "table" and line.action == "trainerWay" then return U.GoToTrainer() end
    return false
end

-- Zeilen der Ansicht: { kind = "header" | "spell" | "text", left, right, icon, entry, state = "now" | "later", level }
-- und die Anzeige-Felder von Core.NewSpellbookView (name, sub, detail, spellID, style, tooltip). Mit ezMap steht
-- dazu der Eintrag „Lehrer auf der Karte zeigen“ (action = "trainerWay").
function U.Lines(level)
    return U.PetLines(level, AddWay(U.SpellLines(level)))
end

---------------------------------------------------------------------------
-- Begleiter (MER-08): eigene Kopfzeile am Ende, Daten aus ezCore (Lehrerfenster des Ausbilders, Begleiter-Zauberbuch)
---------------------------------------------------------------------------

-- Art der Begleiter-Fähigkeiten dieser Klasse ("HUNTER:PET" …) oder nil (Klasse ohne Begleiter, ezCore zu alt).
function U.PetKind()
    local S = Spells()
    if not (S and type(S.PetKind) == "function") then return nil end
    local ok, kind = pcall(S.PetKind)
    return ok and type(kind) == "string" and kind or nil
end

-- Ist ein Begleiter da? Was er schon kann, weiß ezCore nur aus seinem Zauberbuch (Core.Spells.PetBook, nil ohne
-- gerufenen Begleiter); ohne es gälte jede Fähigkeit seines Ausbilders als „jetzt“. Ohne Spells.PetBook (älteres
-- ezCore) oder bei einem Fehler darin: wie bisher (true).
function U.PetPresent()
    local S = Spells()
    if not (S and type(S.PetBook) == "function") then return true end
    local ok, book = pcall(S.PetBook)
    if not ok then return true end
    return type(book) == "table"
end

-- Wie viele Begleiter-Fähigkeiten jetzt beim Ausbilder warten (Core.Spells.Waiting mit der Begleiter-Art; ohne
-- Besuch und ohne gerufenen Begleiter 0).
function U.PetWaiting(level)
    local S, kind = Spells(), U.PetKind()
    if not (kind and S.Waiting) or not U.PetPresent() then return 0 end
    local ok, count = pcall(S.Waiting, level, kind)
    return ok and ns.Num(count) or 0
end

-- Eigener Teil der Zahl am Reiter. Mit Lehrerbesuch Core.Spells.Waiting (über Trainer.lua); ohne ihn zählt ezCore
-- seit Welle 23 (A44) dieselbe Liste wie die Ansicht (Core.Spells.BookEntries) – ezPanel, der Hinweis beim
-- Stufenaufstieg und die Zahl am Reiter liegen damit nicht mehr auseinander. Die Ansicht zählt dann über
-- U.BookWaiting, also über die Liste, die sie für dieses Bild schon geholt hat (eine Client-Abfrage je Bild statt
-- einer zweiten in Spells.Waiting); die Prüfung in Tests/reste23.lua sichert, dass beide Zahlen gleich sind.
function U.OwnWaiting(level)
    local S = Spells()
    if S and S.TrainerSeen and not S.TrainerSeen() then return U.BookWaiting(level, S) end
    local own = ns.Trainer and ns.Trainer.Waiting(level)
    return ns.Num(own) or 0
end

-- Zahl am Reiter: was jetzt beim Lehrer wartet, dazu die Fähigkeiten des Begleiters bei seinem Ausbilder.
function U.Count(level)
    return U.OwnWaiting(level) + U.PetWaiting(level)
end

-- Tooltip des Reiters; bei einer Klasse mit Begleiter mit dem Satz, dass er mitgezählt wird.
function U.TabTip()
    if U.PetKind() then return L.UPCOMING_TAB_TIP .. "\n" .. L.UPCOMING_TAB_TIP_PET end
    return L.UPCOMING_TAB_TIP
end

-- Eine Gruppe des Reiter-Tooltips: Kopfzeile, darunter je Zauber eine Zeile mit Rang (und Preis), höchstens fünf
-- (Trainer.lua: T.SpellList); nil ohne Einträge.
local function NowGroup(T, list, head, withCost)
    local text = T.SpellList(T.Newest(list), { cost = withCost, plain = true, sep = "\n", more = true })
    return text and (head .. "\n" .. text) or nil
end

-- Die jetzt lernbaren Zauber für den Tooltip des Reiters (Leitlinie 3; Wunsch des Nutzers vom 15.11.2026): dieselben
-- Einträge wie unter „Jetzt beim Lehrer“, unter der Quelle. Ohne Lehrerbesuch nennt die Kopfzeile wie die Ansicht
-- (FutureLines), ob die Stufen laut Client dabei sind. Bei einer Klasse mit Begleiter folgt als eigene Gruppe, was die
-- Zahl am Reiter mitzählt (U.PetWaiting): seine Fähigkeiten, die jetzt beim Ausbilder warten. nil, wenn nichts wartet.
function U.NowTip(level)
    local S, T = Spells(), ns.Trainer
    if not (S and S.TrainerSeen and S.Available and T and T.SpellList) then return nil end
    level = level or PlayerLevel()
    local own
    if S.TrainerSeen() then
        own = NowGroup(T, S.Available(level), L.UPCOMING_TAB_NOW, true)
    else
        local list, entries, client = {}, U.BookEntries(S)
        local tables = false          -- Ränge nur laut Client-Tabellen (seit Welle 26 in ezCores Liste): Kopfzeile nennt sie
        for _, entry in ipairs(entries) do
            if BookNow(entry, level) then
                list[#list + 1] = entry
                if entry.tables then tables = true end
            end
        end
        local head = (tables and client and L.UPCOMING_TAB_NOW_ALL) or (tables and L.UPCOMING_TAB_NOW_TABLES)
            or (client and L.UPCOMING_TAB_NOW_CLIENT) or L.UPCOMING_TAB_NOW_BOOK
        own = NowGroup(T, list, head)
    end
    -- was nur die Client-Tabellen als schon erreicht nennen (Gruppe „Erreicht laut Client-Tabellen“): eine Zeile, nicht
    -- mitgezählt
    local reached = U.TableExtra(level, S)
    if #reached > 0 then
        local line = L.UPCOMING_TAB_REACHED:format(Core.Plural(#reached, L.RANKS_ONE, L.RANKS_MANY))
        own = own and (own .. "\n" .. line) or line
    end
    local kind, pet = U.PetKind(), nil
    if kind and S.TrainerSeen(kind) and U.PetPresent() then
        pet = NowGroup(T, S.Available(level, kind) or {}, L.UPCOMING_TAB_NOW_PET, true)
    end
    if own and pet then return own .. "\n\n" .. pet end
    return own or pet
end

-- Ganzer Tooltip des Reiters: Erklärung, darunter die jetzt lernbaren Zauber.
function U.TabText()
    local tip = U.TabTip()
    local ok, now = pcall(U.NowTip)
    if not ok then ns.Error(now, "NowTip") end
    if ok and now then return tip .. "\n\n" .. now end
    return tip
end

-- Abschnitt „Begleiter“ an lines anhängen: jetzt beim Ausbilder (mit Kosten), danach was später kommt (Stufe und
-- Kosten im Eintrag). Ohne Besuch beim Ausbilder ein Hinweis, was fehlt (Leitlinie 11), und wie viel der Begleiter
-- laut seinem Zauberbuch schon kann. → lines
function U.PetLines(level, lines)
    lines = lines or {}
    local S, kind = Spells(), U.PetKind()
    if not (kind and S.TrainerSeen and S.Available and S.Upcoming) then return lines end
    level = level or PlayerLevel()
    local header = { kind = "header", left = L.UPCOMING_PET, pet = true }
    lines[#lines + 1] = header
    if not S.TrainerSeen(kind) then
        lines[#lines + 1] = { kind = "text", left = L.UPCOMING_PET_NO_DATA, pet = true }
        local book = S.PetBook and S.PetBook()
        if type(book) == "table" and #book > 0 then
            local text = #book == 1 and L.UPCOMING_PET_BOOK_ONE or L.UPCOMING_PET_BOOK:format(#book)
            lines[#lines + 1] = { kind = "text", left = text, pet = true }
        end
        return lines
    end
    local now, nowTotal = S.Available(level, kind)
    local later = S.Upcoming(level, Core.MaxLevel(), kind)
    if not U.PetPresent() and (#(now or {}) > 0 or #(later or {}) > 0) then
        -- ohne gerufenen Begleiter: was sein Ausbilder lehrt, grau und ohne „jetzt“ (er kann einiges davon schon)
        lines[#lines + 1] = { kind = "text", left = L.UPCOMING_PET_NOPET, pet = true }
        for _, entry in ipairs(now or {}) do lines[#lines + 1] = SpellLine(entry, "later", true, true) end
        for _, entry in ipairs(later or {}) do lines[#lines + 1] = SpellLine(entry, "later", true, true) end
        return lines
    end
    if (ns.Num(nowTotal) or 0) > 0 then header.right = L.UPCOMING_PET_NOW_SUM:format(ns.Money(nowTotal)) end
    for _, entry in ipairs(now or {}) do lines[#lines + 1] = SpellLine(entry, "now", true, true) end
    for _, entry in ipairs(later or {}) do lines[#lines + 1] = SpellLine(entry, "later", true, true) end
    if #(now or {}) == 0 and #(later or {}) == 0 then
        lines[#lines + 1] = { kind = "text", left = L.UPCOMING_PET_NONE, pet = true }
    end
    return lines
end

---------------------------------------------------------------------------
-- Quelle in der Fußzeile (MER-08, Regel „Datenquellen“)
---------------------------------------------------------------------------

-- Satzende: ein Punkt, außer der Text endet schon auf einen (das deutsche Datum „14.11.“).
local function Sentence(text)
    if text:sub(-1) == "." then return text end
    return text .. "."
end

-- „am 14.11.“ bzw. „heute um 14:05“
local function SeenText(stamp)
    stamp = ns.Num(stamp)
    if not stamp then return "?" end
    local today = date("%Y%m%d", stamp) == date("%Y%m%d", time())
    if today then return L.UPCOMING_SEEN_TODAY:format(date("%H:%M", stamp)) end
    return L.UPCOMING_SEEN_ON:format(Core.DateText(stamp, "day"))
end

-- Woher die Zeilen des Spielers stammen: "trainer" (Lehrerbesuch), "client" (Stufen laut Client und Zauberbuch),
-- "book" (nur Zauberbuch) oder nil (ezCore ohne Zauber-Wissen).
function U.Source()
    local S = Spells()
    if not (S and S.TrainerSeen) then return nil end
    if S.TrainerSeen() then return "trainer" end
    return select(2, U.BookEntries(S)) and "client" or "book"
end

-- Text der Fußzeile: Quelle der eigenen Zeilen, bei einer Klasse mit Begleiter auch die seiner Zeilen.
function U.Footer()
    local source = U.Source()
    if not source then return nil end
    local S = Spells()
    local text
    if source == "trainer" then
        text = Sentence(L.UPCOMING_SRC_TRAINER:format(SeenText(S.TrainerSeen())))
    else
        text = source == "client" and L.UPCOMING_SRC_CLIENT or L.UPCOMING_SRC_BOOK
    end
    -- Stufen und Ränge auch laut Client-Tabellen (Welle 26), sobald ezCore sie liefert
    local tableSource = select(2, U.TableEntries(S)) and U.TableSource()
    if tableSource then text = text .. " " .. L.UPCOMING_SRC_TABLES:format(tableSource) end
    local kind = U.PetKind()
    if kind then
        local seen = S.TrainerSeen(kind)
        text = text .. " " .. (seen and Sentence(L.UPCOMING_SRC_PET:format(SeenText(seen))) or L.UPCOMING_SRC_PET_NONE)
    end
    return text
end

function U.SpellLines(level)
    local S = Spells()
    local lines = {}
    if not (S and S.Available and S.Upcoming and S.TrainerSeen) then return lines end
    level = level or PlayerLevel()
    if not S.TrainerSeen() then return FutureLines(S, level, lines) end
    local now, nowTotal = S.Available(level)
    local running = nowTotal or 0
    if #now > 0 then
        lines[#lines + 1] = { kind = "header", left = L.UPCOMING_NOW, right = ns.Money(running) }
        for _, entry in ipairs(now) do lines[#lines + 1] = SpellLine(entry, "now", true) end
    end
    -- dazu, was nur die Client-Tabellen nennen (Welle 26): schon erreicht als eigene Gruppe, später unter seiner Stufe
    local reached, extra = U.TableExtra(level, S)
    local later = {}
    for _, entry in ipairs(S.Upcoming(level, Core.MaxLevel()) or {}) do later[#later + 1] = entry end
    for _, entry in ipairs(extra) do later[#later + 1] = entry end
    local known = (#later > 0 or #reached > 0) and U.ClientLevels(S) or nil
    ReachedLines(lines, reached, true, known)
    -- false statt nil: auch ein Eintrag ohne Stufe bekommt seine Kopfzeile („Stufe unbekannt“). Kopfzeilen und Summen
    -- nach der Stufe, die die Einträge zeigen (ByShownLevel)
    local current = false
    local rows = ByShownLevel(later, known)
    for _, row in ipairs(rows) do
        if row.level ~= current then
            current = row.level
            local levelCost = 0
            for _, other in ipairs(rows) do
                if other.level == current then levelCost = levelCost + (other.entry.cost or 0) end
            end
            running = running + levelCost
            -- rechts nur die Münzen der laufenden Summe (Spieltest 15.11.2026: „das "bis hier" [ist] unnötig“);
            -- was die Zahl bedeutet, sagt der Tooltip des Reiters (UPCOMING_TAB_TIP)
            lines[#lines + 1] = { kind = "header", left = LevelHeader(current),
                right = L.UPCOMING_SUM:format(ns.Money(running)), level = current }
        end
        lines[#lines + 1] = SpellLine(row.entry, "later", true, nil, known, row)
    end
    if #now == 0 and #later == 0 and #reached == 0 then lines[#lines + 1] = { kind = "text", left = L.UPCOMING_NONE } end
    return lines
end

---------------------------------------------------------------------------
-- Ansicht im Buch (ezCore) – bisherige Funktionen bleiben und reichen weiter
---------------------------------------------------------------------------

-- Verteilt die Zeilen auf Buchseiten (Core.SpellbookView.Layout). → { Seite = { { line, x, y, w, h } … } … }
function U.Layout(lines, pageW, pageH) return Core.SpellbookView.Layout(lines, pageW, pageH) end

function U.Render() if view then view:Render() end end

-- Bisheriger Name: fasst Inhalt, Seiten und Reiter neu.
function U.Refresh() if view then view:Refresh() end end

function U.IsOpen() return view ~= nil and view:IsShown() end

function U.UpdateTab() if view then view:UpdateTab() end end

-- Auf- und Zuschlagen. Gemerkt wird nichts mehr: Das Zauberbuch öffnet immer auf Blizzards Zauberliste, „Was kommt
-- wann“ nur auf Klick (ezCore schlägt jede eigene Ansicht beim Schließen zu; Antwort des Nutzers vom 20.11.2026 auf
-- „Soll ‚Zauberbuch öffnet auf Blizzards Reiter‘ auch für ezMerchants ‚Was kommt wann‘ gelten?“: „Ja, auch ezMerchant“).
function U.Toggle() if view then view:Toggle() end end

local function Setup()
    if view then return end
    view = Core.NewSpellbookView({
        key = "ezMerchant.upcoming",
        owner = ADDON,
        frameName = "ezMerchantUpcomingView",
        icon = TAB_ICON,
        tabY = TAB_Y, order = 10,   -- Seitenreiter-Stapel des Zauberbuchs: oben (T16-4)
        title = L.UPCOMING_TITLE,
        tip = function() return U.TabText() end,
        lines = function() return U.Lines() end,
        footer = function() return U.Footer() end,
        onClick = function(line) U.Click(line) end,
        count = function() return U.Count() end,
        enabled = function() return ns.Enabled("upcoming") end,
    })
    if type(ns.db) == "table" then ns.db.upcomingOpen = nil end   -- alter Merker von „remember“, wird nicht mehr gelesen
end

local RefreshSoon = ns.Throttle(function() U.Refresh() end, 0.2)
Core.Listen("SPELLS_TRAINER_CHANGED", function() RefreshSoon() end, ADDON)
Core.Listen("SPELLS_KNOWN_CHANGED", function() U.ForgetClient() RefreshSoon() end, ADDON)
ns.On("PLAYER_LEVEL_UP", function() U.ForgetClient() RefreshSoon() end)
ns.OnSettingChanged(function(key) if key == "upcoming" then U.UpdateTab() end end)

ns.OnReady(Setup)
