local _, ns = ...
local Core = ezCore

--[[
    Item-Wissen für Sammlungen und Bücher (Punkt 8; gewünscht von ezBag: Aussehen gesammelt/fehlt/nur andere
    Klasse, Reittier/Haustier/Spielzeug schon bekannt, Bibliotheksbuch gefunden/abgegeben, Gruppe „Bücher“;
    ezAuction: Liste fehlender Bücher). Ergänzt die facts des Item-Wissens (Knowledge.lua) über K.AddDynamic:

      f.collect = { kind = "mount" | "pet" | "toy" | "appearance", known = true | false, otherClass = true | nil }
      f.book    = { quest = Quest-ID, done = true | false (dieser Charakter), doneBy = { charKey … } }
      Schlagwörter: collect, collect:<kind>, collected, uncollected, collect:otherClass, book, book:done, book:new

    Bibliotheksbücher (aus Season of Discovery, auf Forever für alle Klassen; Abgabe bei Garion Wendell in
    Sturmwind bzw. Owen Thadd in Unterstadt, je Buch eine Quest, die der Bibliothekar anbietet, solange das
    Buch in der Tasche ist):
      Collections.Books()            → { { item, quest, name, done, doneBy, have, haveAlts } … } alle bekannten
      Collections.Book(item)         → Eintrag oder nil
      Collections.BookProgress(key)  → abgegeben, gesamt (gesamt = 40)
      Nachricht: BOOKS_CHANGED
    Gegenstand und Quest gehören über den Namen zusammen (Buchname = Quest-Titel, in jeder Sprache); einmal
    erkannt, merkt ezCore das Paar in ezCoreDB.knowledge.bookMap. Abgegeben: C_QuestLog.IsQuestFlaggedCompleted,
    je Twink in ezCoreDB.chars[key].books gemerkt. Titel und „erledigt“ fragt die gemeinsame Quest-Abfrage
    (Core.QuestTitle, Core.QuestDone – Abschnitt unten, Welle 23c).
    IDs: QuestieDB Forever über den Polestar-Leitfaden „Library Books“ (fitzforge/polestar), Stand 13.11.2026.
    Zwei der 40 Bücher (A Ludite's Guide …, The Liminal and the Arcane) fehlen dort noch.
    Bestätigt werden die IDs im Selbsttest (/ez test, DG-20): läuft QuestieDB, fragt er zuerst dort (Exists), sonst den
    Client (Gegenstand bekannt bzw. Quest-Titel); eine Zeile je Art, unbekannte IDs nennt die Zeile.
      Core.Books.From(item, opts) → Herkunft eines Buchs (Core.Sources.WhereFrom: erst „bei dir“, dann „laut
                                     Questie“) – Entdecker-Wissen: nur mit OPT_explorer oder opts.explorer = true,
                                     sonst nil, { reason = "explorer" }; für das Bücher-Menü in ezMap

    Sammlungen (Retail-APIs, auf Forever je nach Client vorhanden – fehlt eine API, gibt es kein f.collect):
      Reittier C_MountJournal.GetMountFromItem, Haustier C_PetJournal.GetPetInfoByItemID, Spielzeug C_ToyBox,
      Aussehen C_TransmogCollection (bekannt auch über einen anderen Gegenstand mit demselben Aussehen)
      Spieltest 14.11.2026 (EC-14): Reittiere 136, Spielzeug 21, Transmog vorhanden, Haustiere 0. Haustiere zählen
      deshalb nur, wenn der Client welche führt (C_PetJournal.GetNumPets > 0) – sonst kein Schlagwort und keine Marke,
      statt bei jedem Haustier-Gegenstand „noch nicht gesammelt“. Collections.PetsAvailable() → true | false
]]

Core.Collections = Core.Collections or {}
local C = Core.Collections

local Num, Plain = Core.Num, Core.Plain

C.BOOK_TOTAL = 40

-- Buch-Gegenstände (Item-ID → englischer Name laut Client, ItemSparse über wago.tools; nur zur Orientierung, erkannt
-- wird über die ID – die wago-Prüfung vergleicht die Namen, Welle 26)
C.BOOK_ITEMS = {
    [203754] = "Archmage Antonidas: The Unabridged Autobiography", [203755] = "Archmage Theocritus' Research Journal",
    [207972] = "The Lessons of Ta'zo", [208185] = "The Apothecary's Metaphysical Primer",
    [208800] = "Baxtan: On Destructive Magics", [208860] = "Rumi of Gnomeregan: The Collected Works",
    [209843] = "Nar'thalas Almanac, Vol. 74", [209844] = "The Dalaran Digest, Vol. 23",
    [209845] = "Bewitchments and Glamours", [209846] = "Secrets of the Dreamers",
    [209847] = "Arcanic Systems Manual", [209848] = "Goaz Scrolls", [209849] = "Crimes Against Anatomy",
    [209850] = "Runes of the Sorcerer-Kings", [209851] = "Fury of the Land", [210177] = "Ataeric: On Arcane Curiosities",
    [213165] = "Basilisks: Should Petrification be Feared?", [215683] = "Geomancy: The Stone-Cold Truth",
    [215815] = "Defensive Magics 101", [215816] = "A Web of Lies: Debunking Myths and Legends",
    [215817] = "Demons and You", [215820] = "Mummies: A Guide to the Unsavory Undead", [215822] = "RwlRwlRwlRwl!",
    [220345] = "Sanguine Sorcery", [220346] = "Legends of the Tidesages", [220348] = "Everyday Etiquette",
    [220349] = "Stonewrought Design", [220350] = "Venomous Journeys", [220352] = "A Mind of Metal",
    [220353] = "Conjurer's Codex", [228132] = "Undead Potatoes", [228133] = "Magma or Lava?",
    [228134] = "Northern Kalimdor - A Comprehensive Guide", [228135] = "A Study of the Light", [228136] = "Ka-Boom!",
    [228138] = "The Knight and the Lady", [228140] = "Scourge: Undead Menace or Misunderstood?", [228141] = "Necromancy 101",
}
-- Abgabe-Quests der Bücher (ohne die Belohnungs-Quests „Friend of the Library“ 78150, 79536, 82208)
C.BOOK_QUESTS = { 78124, 78127, 78142, 78143, 78145, 78146, 78147, 78148, 78149, 79091, 79092, 79093, 79094, 79095,
    79096, 79097, 79535, 79947, 79948, 79949, 79950, 79951, 79952, 81947, 81949, 81952, 81953, 81954, 81955, 81956,
    84395, 84396, 84397, 84398, 84399, 84400, 84401, 84402 }

local LL = Core.NewLocale({
    TAG_collect = "Sammlung", TAG_collected = "schon gesammelt", TAG_uncollected = "noch nicht gesammelt",
    TAG_otherClass = "nur andere Klasse", TAG_mount = "Reittier", TAG_pet = "Haustier", TAG_toy = "Spielzeug",
    TAG_appearance = "Aussehen", TAG_book = "Bibliotheksbuch", TAG_bookDone = "Buch schon abgegeben",
    TAG_bookNew = "Buch noch nicht abgegeben",
    BOOK_TEST_ITEMS = "Bibliotheksbücher (Gegenstände)", BOOK_TEST_QUESTS = "Bibliotheksbücher (Abgabe-Quests)",
    BOOK_TEST_KNOWN = "%d von %d bekannt (%s)", BOOK_TEST_BY_QUESTIE = "laut Questie",
    BOOK_TEST_BY_CLIENT = Core.L.SOURCE_CLIENT,   -- ein Wortlaut für „laut Client“ (Kern/Locale.lua, T10-6)
    BOOK_TEST_MISSING = "unbekannt: %s",
}, {
    TAG_collect = "Collection", TAG_collected = "already collected", TAG_uncollected = "not collected yet",
    TAG_otherClass = "other class only", TAG_mount = "Mount", TAG_pet = "Pet", TAG_toy = "Toy",
    TAG_appearance = "Appearance", TAG_book = "Library book", TAG_bookDone = "Book already handed in",
    TAG_bookNew = "Book not handed in yet",
    BOOK_TEST_ITEMS = "Library books (items)", BOOK_TEST_QUESTS = "Library books (hand-in quests)",
    BOOK_TEST_KNOWN = "%d of %d known (%s)", BOOK_TEST_BY_QUESTIE = "according to Questie",
    BOOK_TEST_BY_CLIENT = Core.L.SOURCE_CLIENT,
    BOOK_TEST_MISSING = "unknown: %s",
})
C.L = LL

---------------------------------------------------------------------------
-- Sammlungen
---------------------------------------------------------------------------

local Call = Core.PCall

local function Mount(itemID)
    local api = C_MountJournal
    if not (api and api.GetMountFromItem and api.GetMountInfoByID) then return nil end
    local ok, mountID = Call(api.GetMountFromItem, itemID)
    mountID = ok and Num(mountID)
    if not mountID then return nil end
    local ok2, _, _, _, _, _, _, _, _, _, _, isCollected = Call(api.GetMountInfoByID, mountID)
    if not ok2 then return nil end
    return { kind = "mount", known = isCollected == true }
end

-- Führt der Client Haustiere? (Forever: Haustier-Fenster leer) Haustiere im Journal oder in der Sammlung > 0.
-- Die erste Zahl von GetNumPets folgt Such- und Filterstand des Journals; deshalb zählt auch die zweite (gesammelt).
function C.PetsAvailable()
    local api = C_PetJournal
    if not (api and api.GetPetInfoByItemID and api.GetNumPets) then return false end
    local ok, total, owned = Call(api.GetNumPets)
    if not ok then return false end
    total, owned = Num(total), Num(owned)
    return (total ~= nil and total > 0) or (owned ~= nil and owned > 0)
end

local function Pet(itemID)
    local api = C_PetJournal
    if not (api and api.GetPetInfoByItemID) or not C.PetsAvailable() then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, _, _, speciesID = Call(api.GetPetInfoByItemID, itemID)
    speciesID = ok and Num(speciesID)
    if not speciesID then return nil end
    local okN, owned = Call(api.GetNumCollectedInfo, speciesID)
    return { kind = "pet", known = okN and (Num(owned) or 0) > 0 or false }
end

local function Toy(itemID)
    local api = C_ToyBox
    if not (api and api.GetToyInfo) then return nil end
    local ok, toyID = Call(api.GetToyInfo, itemID)
    if not (ok and Num(toyID)) then return nil end
    local okHas, has = Call(PlayerHasToy, itemID)
    return { kind = "toy", known = okHas and has == true or false }
end

local function Appearance(f)
    local api = C_TransmogCollection
    if not (f.isEquipment and api and api.GetItemInfo and api.GetSourceInfo) then return nil end
    local ok, appearanceID, sourceID = Call(api.GetItemInfo, f.link or f.itemID)
    appearanceID, sourceID = ok and Num(appearanceID), ok and Num(sourceID)
    if not sourceID then return nil end
    local okS, info = Call(api.GetSourceInfo, sourceID)
    local known = okS and type(info) == "table" and info.isCollected == true
    if not known and appearanceID and api.GetAllAppearanceSources then
        local okA, sources = Call(api.GetAllAppearanceSources, appearanceID)
        for _, id in ipairs(okA and type(sources) == "table" and sources or {}) do
            local okI, other = Call(api.GetSourceInfo, id)
            if okI and type(other) == "table" and other.isCollected == true then known = true break end
        end
    end
    local otherClass
    if not known and api.PlayerCanCollectSource then
        local okC, hasData, canCollect = Call(api.PlayerCanCollectSource, sourceID)
        if okC and hasData and canCollect == false then otherClass = true end
    end
    return { kind = "appearance", known = known and true or false, otherClass = otherClass }
end

function C.Of(f)
    local itemID = type(f) == "table" and Num(f.itemID)
    if not itemID then return nil end
    return Mount(itemID) or Pet(itemID) or Toy(itemID) or Appearance(f)
end

---------------------------------------------------------------------------
-- Bücher
---------------------------------------------------------------------------

local function KDB(create)
    local db = Core.db
    local kdb = type(db) == "table" and db.knowledge
    if type(kdb) ~= "table" then return nil end
    if not kdb.bookMap and create then kdb.bookMap = {} end
    return kdb
end

local function Norm(text)
    text = Plain(text)
    if type(text) ~= "string" then return nil end
    text = text:lower():gsub("[%p%s]", "")
    return text ~= "" and text or nil
end

---------------------------------------------------------------------------
-- Gemeinsame Quest-Abfrage (Welle 23c, A31; vorher lokal hier zweimal und in ezQuest/QuestId.lua)
---------------------------------------------------------------------------
--[[
      Core.QuestTitle(questID, load) → Titel in der Spielsprache oder nil. load = true fordert eine noch unbekannte
                                       Quest beim Client an (C_QuestLog.RequestLoadQuestByID); der Titel kommt dann
                                       beim nächsten Fragen.
      Core.QuestDone(questID)        → true/false laut Client (C_QuestLog.IsQuestFlaggedCompleted, dieser Charakter),
                                       nil ohne Auskunft (Funktion fehlt, Fehler, gesperrter Wert)
    Beide fragen geschützt (Core.Peek, Core.Call) und vergleichen nie einen gesperrten Wert.
]]
local function QuestLogFn(name)
    local log = rawget(_G, "C_QuestLog")
    local fn = type(log) == "table" and Core.Peek(log, name) or nil
    return type(fn) == "function" and fn or nil
end

function Core.QuestTitle(questID, load)
    questID = Num(questID)
    if not questID then return nil end
    local title = Plain(Core.Call(QuestLogFn("GetTitleForQuestID"), questID))
    if type(title) == "string" and title ~= "" then return title end
    if load then Core.Call(QuestLogFn("RequestLoadQuestByID"), questID) end
    return nil
end

function Core.QuestDone(questID)
    questID = Num(questID)
    if not questID then return nil end
    return Core.Bool(Core.Call(QuestLogFn("IsQuestFlaggedCompleted"), questID), nil)
end

--[[
    Erfahrung aus Quests im Log (Feature I1 des Gesamtreviews vom 18.11.2026; vorher nur in ezQuest/LevelRoute.lua,
    LR.ReadQuest – Leitlinie 2: ein Helfer für die Leveling-Route und die Vorschau auf der Erfahrungsleiste, auch für
    andere Module ohne Abhängigkeit von ezQuest). Quelle: der Client (Leitlinie 11).
      Core.QuestXP(questID)    → EP, "client" oder nil: GetQuestLogRewardXP(questID) → totalXp, baseXp; genommen wird
                                 totalXp (was du jetzt bekämst), sonst baseXp. Belegt in Blizzards Forever-Quelle
                                 (Blizzard_FrameXMLUtil/Mainline/QuestUtils.lua, QuestUtils_AddQuestRewardsToTooltip).
      Core.QuestReady(questID) → true, wenn die Quest abgabebereit ist: C_QuestLog.IsComplete oder ReadyForTurnIn, sonst
                                 alle Teilziele erfüllt (GetQuestObjectives, finished); false sonst.
      Core.QuestLogEntries()   → { { id = questID, info = C_QuestLog.GetInfo(i) } … } aller Quests im Log ohne
                                 Überschriften und verborgene, oder nil ohne Questlog – der eine Filter für die Vorschau
                                 und die Leveling-Route (LR.ReadLog; Gegenprüfung I1).
      Core.QuestLogXP()        → { done, all, doneCount, allCount, unknown } über alle Quests im Log (ohne Überschriften
                                 und verborgene): Summe der EP der fertigen bzw. aller Quests, ihre Zahl und wie viele
                                 keine EP nennen (die zählen nicht mit) – oder nil ohne Questlog.
    Gesperrte Antworten (Leitlinie 6) zählen wie „keine Angabe“, nichts wirft.
]]
function Core.QuestXP(questID)
    questID = Num(questID)
    if not questID then return nil end
    local total, base = Core.Call(rawget(_G, "GetQuestLogRewardXP"), questID)
    total, base = Num(total), Num(base)
    local xp = (total and total > 0 and total) or (base and base > 0 and base) or nil
    if xp then return xp, "client" end
    return nil
end

function Core.QuestReady(questID)
    questID = Num(questID)
    if not questID then return false end
    if Core.Bool(Core.Call(QuestLogFn("IsComplete"), questID), false) == true
        or Core.Bool(Core.Call(QuestLogFn("ReadyForTurnIn"), questID), false) == true then
        return true
    end
    local list = Core.Call(QuestLogFn("GetQuestObjectives"), questID)
    if Core.IsSecret(list) or type(list) ~= "table" then return false end
    -- gesperrte Teilziele überspringen (wie die Leveling-Route seit Welle 27); fertig nur mit mindestens einem lesbaren
    local readable = 0
    for _, o in ipairs(list) do
        if type(o) == "table" and not Core.IsSecret(o) then
            if Core.Bool(Core.Peek(o, "finished"), false) ~= true then return false end
            readable = readable + 1
        end
    end
    return readable > 0
end

function Core.QuestLogEntries()
    local count, info = QuestLogFn("GetNumQuestLogEntries"), QuestLogFn("GetInfo")
    if not (count and info) then return nil end
    local out = {}
    for i = 1, Num(Core.Call(count)) or 0 do
        local e = Core.Call(info, i)
        if type(e) == "table" and not Core.IsSecret(e) and Core.Bool(Core.Peek(e, "isHeader"), false) ~= true
            and Core.Bool(Core.Peek(e, "isHidden"), false) ~= true then
            local id = Num(Core.Peek(e, "questID"))
            if id and id > 0 then out[#out + 1] = { id = id, info = e } end
        end
    end
    return out
end

function Core.QuestLogXP()
    local entries = Core.QuestLogEntries()
    if not entries then return nil end
    local out = { done = 0, all = 0, doneCount = 0, allCount = 0, unknown = 0 }
    for _, entry in ipairs(entries) do
        local xp = Core.QuestXP(entry.id)
        local ready = Core.QuestReady(entry.id)
        out.allCount = out.allCount + 1
        if ready then out.doneCount = out.doneCount + 1 end
        if xp then
            out.all = out.all + xp
            if ready then out.done = out.done + xp end
        else
            out.unknown = out.unknown + 1
        end
    end
    return out
end

--[[
    Farbe einer Queststufe aus Sicht einer Spielerstufe (Spieltest vom 20.11.2026: die Leveling-Route soll nach dem
    Stufenabstand ordnen; Leitlinie 2: ein Helfer für alle Module). Quelle: der Client (Leitlinie 11) – Blizzards
    Forever-Quelle, Blizzard_FrameXMLUtil/Mainline/DifficultyUtil.lua, DifficultyUtil.GetRelativeDifficultyColor(
    unitLevel, challengeLevel) gibt einen Eintrag aus QuestDifficultyColors zurück; dessen Schlüssel ist die Antwort.
      Core.QuestDifficulty(questLevel, playerLevel) → "impossible" (rot) | "verydifficult" (orange) | "difficult" (gelb)
          | "standard" (grün) | "trivial" (grau), Quelle "client" | "estimate" – oder nil ohne Stufen. playerLevel
          fehlt: Core.PlayerLevel(). Ohne Antwort des Clients dieselben Grenzen wie dort (≥ 5 Stufen über dir rot,
          ≥ 3 orange, ≥ −4 gelb, bis UnitQuestTrivialLevelRange unter dir grün, sonst grau; ohne diese Grenze 5
          Stufen – Vermutung), Quelle "estimate".
]]
Core.QUEST_DIFFICULTIES = { "impossible", "verydifficult", "difficult", "standard", "trivial" }
Core.QUEST_TRIVIAL_FALLBACK = 5     -- Stufen unter dir, ab denen grau gilt, wenn der Client es nicht sagt (Vermutung)

function Core.QuestDifficulty(questLevel, playerLevel)
    questLevel, playerLevel = Num(questLevel), Num(playerLevel) or Core.PlayerLevel()
    if not (questLevel and questLevel > 0 and playerLevel and playerLevel > 0) then return nil end
    local colors = rawget(_G, "QuestDifficultyColors")
    local util = rawget(_G, "DifficultyUtil")
    local fn = type(util) == "table" and not Core.IsSecret(util) and rawget(util, "GetRelativeDifficultyColor")
        or rawget(_G, "GetRelativeDifficultyColor")
    if type(colors) == "table" and not Core.IsSecret(colors) then
        local color = Core.Call(fn, playerLevel, questLevel)
        if type(color) == "table" and not Core.IsSecret(color) then
            for _, key in ipairs(Core.QUEST_DIFFICULTIES) do
                if rawequal(rawget(colors, key), color) then return key, "client" end
            end
        end
    end
    local diff = questLevel - playerLevel
    if diff >= 5 then return "impossible", "estimate" end
    if diff >= 3 then return "verydifficult", "estimate" end
    if diff >= -4 then return "difficult", "estimate" end
    local range = Num(Core.Call(rawget(_G, "UnitQuestTrivialLevelRange"), "player"))
    if not range or range < 0 then range = Core.QUEST_TRIVIAL_FALLBACK end
    if -diff <= range then return "standard", "estimate" end
    return "trivial", "estimate"
end

-- Farbe dazu (Paket ezsocial/levelfarbe; Leitlinie 2: eine Stelle für Stufenfarben – ezSocial rechnete eigene Grenzen):
--   Core.QuestDifficultyRGB(questLevel, playerLevel) → r, g, b, schlüssel, quelle – oder nil ohne Stufen.
-- Die Farbe kommt aus Blizzards QuestDifficultyColors[schlüssel]; fehlt die Tabelle, dieselben Werte von Hand
-- (Core.QUEST_DIFFICULTY_RGB, Quelle: Gethe/wow-ui-source, Zweig forever,
-- Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua, QuestDifficultyColors; nachgesehen am 20.11.2026).
Core.QUEST_DIFFICULTY_RGB = {
    impossible = { 1, 0.1, 0.1 }, verydifficult = { 1, 0.5, 0.25 }, difficult = { 1, 0.82, 0 },
    standard = { 0.25, 0.75, 0.25 }, trivial = { 0.5, 0.5, 0.5 },
}

function Core.QuestDifficultyRGB(questLevel, playerLevel)
    local key, source = Core.QuestDifficulty(questLevel, playerLevel)
    if not key then return nil end
    local colors = rawget(_G, "QuestDifficultyColors")
    local color = type(colors) == "table" and not Core.IsSecret(colors) and rawget(colors, key) or nil
    if type(color) == "table" and not Core.IsSecret(color) then
        local r, g, b = Num(rawget(color, "r")), Num(rawget(color, "g")), Num(rawget(color, "b"))
        if r and g and b then return r, g, b, key, source end
    end
    local rgb = Core.QUEST_DIFFICULTY_RGB[key]
    return rgb[1], rgb[2], rgb[3], key, source
end

-- Titel für die Zuordnung Buch » Quest: unbekannte Quests beim Client anfordern
local function QuestTitle(questID)
    return Core.QuestTitle(questID, true)
end

local ItemName = Core.ItemNameByID

-- Buch → Quest über den Namen (gleich oder einer beginnt mit dem anderen: „Nar'thalas Almanac“ / „…, Vol. 74“).
local function QuestFor(itemID)
    local kdb = KDB(true)
    local known = kdb and kdb.bookMap[itemID]
    if known then return known end
    local name = Norm(ItemName(itemID))
    if not name then return nil end
    local used = {}
    for _, q in pairs(kdb and kdb.bookMap or {}) do used[q] = true end
    for _, questID in ipairs(C.BOOK_QUESTS) do
        if not used[questID] then
            local title = Norm(QuestTitle(questID))
            if title and (title == name or title:sub(1, #name) == name or name:sub(1, #title) == title) then
                if kdb then kdb.bookMap[itemID] = questID end
                return questID
            end
        end
    end
    return nil
end
C.QuestFor = QuestFor

-- Abgegeben? true/false laut Client, nil ohne Auskunft (jetzt mit Schutz vor gesperrten Werten, Core.QuestDone)
local function Completed(questID)
    return Core.QuestDone(questID)
end

-- Abgegebene Bücher dieses Charakters merken (für die Twinks).
---------------------------------------------------------------------------
-- Zeichen „fehlt der Sammlung“ an Platzknöpfen (ezBag, ezMerchant): ein Stern oben links,
-- grau, wenn nur eine andere Klasse es sammeln kann.
---------------------------------------------------------------------------

C.MARK_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"
C.MARK_SIZE = 14

-- Fehlt der Gegenstand der Sammlung? → fehlt, nur für eine andere Klasse
function C.Missing(item)
    local K = Core.Knowledge
    if Core.IsSecret(item) or item == nil or not (K and K.Get) then return false, false end
    local ok, f = pcall(K.Get, item)
    local collect = ok and type(f) == "table" and f.collect or nil
    if type(collect) ~= "table" or collect.known ~= false then return false, false end
    return true, collect.otherClass == true
end

-- Stern an einem Knopf zeigen oder verbergen (eigene Textur, beim ersten Gebrauch angelegt; nichts wird in
-- Blizzards Knopf-Tabelle geschrieben). Rückgabe: die Textur oder nil.
local marks = setmetatable({}, { __mode = "k" })
function C.ApplyMark(button, missing, otherClass)
    if type(button) ~= "table" or type(button.CreateTexture) ~= "function" then return nil end
    local mark = marks[button]
    if not mark then
        if not missing then return nil end
        mark = button:CreateTexture(nil, "OVERLAY", nil, 2)
        mark:SetSize(C.MARK_SIZE, C.MARK_SIZE)
        mark:SetPoint("TOPLEFT", button, "TOPLEFT", -3, 3)
        mark:SetTexture(C.MARK_TEXTURE)
        marks[button] = mark
    end
    mark:SetDesaturated(otherClass == true)
    mark:SetShown(missing == true)
    return mark
end

function C.ScanBooks()
    local me = Core.me
    if not me then return false end
    local books, changed = me.books or {}, false
    for _, questID in ipairs(C.BOOK_QUESTS) do
        local done = Completed(questID)
        if done and not books[questID] then books[questID], changed = true, true end
    end
    me.books = books
    if changed then
        Core.Fire("BOOKS_CHANGED")
        if Core.Knowledge and Core.Knowledge.RefreshDynamic then Core.Knowledge.RefreshDynamic() end
    end
    return changed
end

local function DoneBy(questID)
    local list = {}
    for key, c in pairs(Core.Chars()) do
        if type(c.books) == "table" and c.books[questID] then list[#list + 1] = key end
    end
    table.sort(list)
    return list
end

local function Count(c, itemID)
    local n = 0
    for _, place in ipairs({ "bags", "bank", "mail" }) do
        local t = c and c[place]
        n = n + (type(t) == "table" and Num(t[itemID]) or 0)
    end
    return n
end

function C.Book(item)
    local itemID = Core.ItemID(item)
    if not (itemID and C.BOOK_ITEMS[itemID]) then return nil end
    local questID = QuestFor(itemID)
    local me = Core.me
    local done = questID and ((me and me.books and me.books[questID]) or Completed(questID)) and true or false
    local haveAlts = 0
    for key, c in pairs(Core.Chars()) do
        if key ~= Core.charKey then haveAlts = haveAlts + Count(c, itemID) end
    end
    return { item = itemID, quest = questID, name = ItemName(itemID) or C.BOOK_ITEMS[itemID], done = done,
        doneBy = questID and DoneBy(questID) or {}, have = Count(me, itemID), haveAlts = haveAlts }
end

function C.Books()
    local list = {}
    for itemID in pairs(C.BOOK_ITEMS) do list[#list + 1] = C.Book(itemID) end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

function C.BookProgress(charKey)
    local c = Core.Char(charKey or Core.charKey)
    local n = 0
    for _, questID in ipairs(C.BOOK_QUESTS) do
        if c and type(c.books) == "table" and c.books[questID] then n = n + 1 end
    end
    return n, C.BOOK_TOTAL
end

---------------------------------------------------------------------------
-- Anbindung an das Item-Wissen
---------------------------------------------------------------------------

local function Provide(f, add)
    f.collect, f.book = nil, nil
    local col = C.Of(f)
    if col then
        f.collect = col
        add("collect", LL.TAG_collect)
        add("collect:" .. col.kind, LL["TAG_" .. col.kind])
        if col.known then add("collected", LL.TAG_collected) else add("uncollected", LL.TAG_uncollected) end
        if col.otherClass then add("collect:otherClass", LL.TAG_otherClass) end
    end
    local book = C.BOOK_ITEMS[Num(f.itemID) or 0] and C.Book(f.itemID)
    if book then
        f.book = { quest = book.quest, done = book.done, doneBy = book.doneBy }
        add("book", LL.TAG_book)
        add(book.done and "book:done" or "book:new", book.done and LL.TAG_bookDone or LL.TAG_bookNew)
    end
end

if Core.Knowledge and Core.Knowledge.AddDynamic then Core.Knowledge.AddDynamic(Provide) end

local function Refresh()
    if Core.Knowledge and Core.Knowledge.RefreshDynamic then Core.Knowledge.RefreshDynamic() end
end
local RefreshLater = Core.Throttle(Refresh, 0.5, Core.name)
local ScanLater = Core.Throttle(function() C.ScanBooks() end, 2, Core.name)

for _, event in ipairs({ "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED", "TRANSMOG_COLLECTION_UPDATED",
    "COMPANION_LEARNED", "PET_JOURNAL_LIST_UPDATE" }) do
    ns.On(event, RefreshLater)
end
ns.On("QUEST_TURNED_IN", function(_, questID)
    questID = Num(questID)
    for _, q in ipairs(C.BOOK_QUESTS) do
        if q == questID then return ScanLater() end
    end
end)
Core.Listen("CHARS_READY", function() C_Timer.After(5, ScanLater) end)

---------------------------------------------------------------------------
-- DG-20: Bücher-IDs im Selbsttest bestätigen, Herkunft eines Buchs (Entdecker-Wissen)
---------------------------------------------------------------------------

Core.Books = Core.Books or {}

function Core.Books.From(item, opts)
    local itemID = Num(item)
    if not (itemID and C.BOOK_ITEMS[itemID]) then return nil, { reason = "nobook" } end
    local DB = Core.DB
    local explorer = (type(opts) == "table" and opts.explorer == true) or (DB and DB.Explorer and DB.Explorer())
    if not explorer then return nil, { reason = "explorer" } end
    local S = Core.Sources
    local answer = S and S.WhereFrom and S.WhereFrom(itemID, { explorer = true })
    if not answer then return nil, { reason = "none" } end
    return answer, { label = S.Label(answer), src = answer.sourceKey }
end

local function QuestieKnows(kind, id)
    local Q = Core.Sources and Core.Sources.Questie
    if not (Q and Q.Exists) then return nil end
    return Q.Exists(kind, id)
end

-- Selbsttest: nur fragen, nichts beim Client anfordern
local function QuestTitle(questID)
    return Core.QuestTitle(questID)
end

-- → zwei Daten-Zeilen „n von m bekannt (laut Questie | laut Client)“; unbekannte IDs stehen in der Zeile (höchstens
-- BOOK_TEST_SHOWN), nicht als Mangel – ein noch nicht geladener Gegenstand ist kein Fehler des Addons.
C.BOOK_TEST_SHOWN = 5

local function KnownLine(name, ids, ask, fallback)
    local known, via, missing = 0, false, {}
    for _, id in ipairs(ids) do
        local there = QuestieKnows(ask, id)
        if there ~= nil then via = true end
        if there == nil then there = fallback(id) and true or false end
        if there then known = known + 1 elseif #missing < C.BOOK_TEST_SHOWN then missing[#missing + 1] = tostring(id) end
    end
    local note = LL.BOOK_TEST_KNOWN:format(known, #ids, via and LL.BOOK_TEST_BY_QUESTIE or LL.BOOK_TEST_BY_CLIENT)
    if known < #ids then note = note .. " – " .. LL.BOOK_TEST_MISSING:format(table.concat(missing, ", ")) end
    return { kind = "data", name = name, state = "text", note = note, known = known, total = #ids, questie = via }
end

function C.BookSelfTest()
    local items = {}
    for itemID in pairs(C.BOOK_ITEMS) do items[#items + 1] = itemID end
    table.sort(items)
    return {
        KnownLine(LL.BOOK_TEST_ITEMS, items, "Item", function(id) return Core.Sources and Core.Sources.ClientKnowsItem(id) end),
        KnownLine(LL.BOOK_TEST_QUESTS, C.BOOK_QUESTS, "Quest", function(id) return QuestTitle(id) ~= nil end),
    }
end

-- angemeldet in Diagnose.lua (lädt nach dieser Datei)
