local _, ns = ...
local Core = ezCore

--[[
    Fähigkeiten, die nicht vom Lehrer kommen (24.11.2026; ezMerchants „Wo kommt was“, Schritt (d): „Klassenquests, die eine
    Fähigkeit bringen, und Fähigkeiten aus Gegenständen“, Auftrag des Nutzers, Wortlaut im ROADMAP-Index).

    Quellen (Leitlinien 11 und 12), jede Angabe trägt ihre:
      * Bücher: welcher Gegenstand welche Fähigkeit (mit Rang) welcher Klasse ab welcher Stufe lehrt, sagen die
        Client-Tabellen dieses Builds (Wissen/Client/SpellBooks.lua, Schlüssel spellBooks); ob du sie schon kannst, der
        Client; wo es das Buch gibt, Core.Knowledge.RecipeWhere (besuchte Händler, eigene Beute, Questie …). Kennt der
        Client den Gegenstand noch nicht, fordert ezCore ihn einmal an; erst danach nennen Questie und der Client Namen
        und Fundort (loading = true bis dahin). Verschleierte Gegenstände nur mit Entdecker-Wissen, das regelt Core.Sources.
      * Klassenquests: welche Quests nur deine Klasse annehmen darf, sagt QuestieDB zur Laufzeit
        (Core.Sources.Questie.ClassQuests, nichts kopiert); erledigt oder nicht, der Client; welche Fähigkeit die Quest
        bringt, nur der Client (C_QuestInfoSystem.GetQuestRewardSpells, GetQuestRewardSpellInfo » isSpellLearned; belegt in
        Blizzards Forever-Quelle, QuestInfoSystemDocumentation.lua) nach RequestLoadQuestByID. Sagt er nichts oder nicht zu
        jedem Zauber, hilft seit dem 24.11.2026 die Faktenliste Core.QuestSpells (Leitfäden zu Forever; nur Zauber, die der
        Client deiner Klasse und deinem Volk zuschreibt), auch für die Schritte einer Reihe, die dorthin führt.
        Sonst steht die Quest unter „Belohnung noch unbekannt“ – nie geraten, nie vorläufig gemerkt. Ob der Client
        die Belohnung fremder Quests ohne Questfenster nennt, ist im Spiel zu bestätigen (Probe K1: am Questfenster ja).

      SpellSources.Learned(zauber, rang) → true, wenn du genau diesen Zauber (bei Rängen: diesen oder einen höheren) kannst;
                                      rang nil = laut Client-Tabelle der Klassenzauber, sonst laut Zusatztext des Clients
      SpellSources.BookOf(zauber)   → Gegenstand, Stufe des Buchs, das ihn laut Client-Tabellen lehrt (bei mehreren das mit
                                      der kleinsten Stufe, dann ID), sonst nil – der Rang kommt dann nicht vom Lehrer
      SpellSources.Books()          → { { item, spell, name (Fähigkeit), rank (0 ohne), itemName, level, where = { fundort
                                      … }, loading } … } – nicht gelernte deiner Klasse, mit Fundort zuerst, dann nach Stufe
                                      und Name; {} ohne Daten
      SpellSources.Quests()         → { taught = { quest … }, open = { quest … }, source, sourceKey } | nil, grund – nicht
                                      erledigte Klassenquests; quest = { id, name, level, spells = { zauber … }, active
                                      (im Questlog), failed (der Client kennt die Quest nicht), from ("client" | "guide" |
                                      "wiki"), lead (Schritt einer Reihe, die dorthin führt), either (nur eine davon),
                                      steps (so viele offene Quests dieses Namens führen dorthin; eine Zeile) };
                                      taught: bringt eine Fähigkeit, die du noch nicht kannst, nach Stufe, Schritte vor dem
                                      Ziel; open: Belohnung noch unbekannt; grund wie Q.ClassQuests („building“: Questie liest noch)
                                      Fragt beim Client je Aufruf höchstens SpellSources.ASK Belohnungen an.
      SpellSources.QuestPlace(questID) → Ort, an dem die Quest beginnt ({ name, map, x, y, area }; ist keine Karte bekannt,
                                      nur der Name) oder nil
      Nachricht SPELLSOURCES_CHANGED: etwas davon kann sich geändert haben (Belohnung, Gegenstand oder Index da, Zauber
      gelernt, Quest abgegeben); gedrosselt.
]]

local SpellSources = {}
Core.SpellSources = SpellSources

local Num, Plain = Core.Num, Core.Plain

SpellSources.ASK = 8                 -- Belohnungen je Aufruf beim Client anfordern
SpellSources.ASK_PAUSE = 2           -- Sekunden bis zur nächsten Runde, falls der Client schweigt
local asked = {}                     -- [Quest] = true: beim Client angefordert
local failed = {}                    -- [Quest] = true: der Client kennt sie nicht (QUEST_DATA_LOAD_RESULT ohne Erfolg)
local answers = {}                   -- [Quest] = { zauber … } laut Client ({}: nur Wirkungen, keine Fähigkeit)
local items = {}                     -- [Gegenstand] = "asked" (angefordert) | "done" (Antwort da)
local again = false

if Core.RegisterMessage then
    Core.RegisterMessage("SPELLSOURCES_CHANGED", "SpellSources.lua", "Fähigkeiten aus Quests und Büchern können sich geändert "
        .. "haben: Belohnung, Gegenstand oder Index der Klassenquests ist da, Zauber gelernt, Quest abgegeben.", "")
end

local function Fn(space, name)
    local t = rawget(_G, space)
    local fn = type(t) == "table" and Core.Peek(t, name) or nil
    return type(fn) == "function" and fn or nil
end

local Changed = Core.Throttle(function() Core.Fire("SPELLSOURCES_CHANGED") end, 0.2)

-- Rang eines Klassenzaubers laut Client-Tabellen (sofort da), sonst laut Zusatztext des Clients
local function RankOf(spell)
    local CD, S = Core.ClientData, Core.Spells
    local e = CD and type(CD.ClassSpell) == "function" and CD.ClassSpell(spell) or nil
    if e then return Num(e.rank) or 0 end
    return S and type(S.Rank) == "function" and Num(S.Rank(spell)) or 0
end

-- Reittier des Zaubers gesammelt? (die Reittiere der Hexenmeister und Paladine stehen in der Sammlung, nicht im Zauberbuch)
local function MountCollected(spell)
    local id = Num((Core.Call(Fn("C_MountJournal", "GetMountFromSpell"), spell)))
    if not id then return false end
    return Core.Bool((select(11, Core.Call(Fn("C_MountJournal", "GetMountInfoByID"), id))), false) == true
end

function SpellSources.Learned(spell, rank)
    spell = Num(spell)
    if not spell then return false end
    if Core.KnowsSpell(spell) then return true end
    if MountCollected(spell) then return true end
    -- ein höherer Rang zählt auch; ohne Rang gilt nur genau dieser Zauber (der Name allein reicht nicht: wer Frostblitz
    -- Rang 1 kann, kann Rang 11 nicht)
    rank = Num(rank) or RankOf(spell)
    if rank > 0 then
        local S = Core.Spells
        local name = Core.SpellName(spell)
        return name ~= nil and S ~= nil and S.KnowsRank(name, rank) == true
    end
    return false
end

---------------------------------------------------------------------------
-- Bücher
---------------------------------------------------------------------------

-- Name des Buchs; kennt ihn der Client noch nicht, einmal anfordern (ITEM_DATA_LOAD_RESULT unten). → Name | nil, wartet
local function BookName(item)
    local name = Core.ItemNameByID and Core.ItemNameByID(item, true) or nil
    if name or items[item] == "done" then return name, false end
    if not items[item] then
        local load = Fn("C_Item", "RequestLoadItemDataByID")
        if not load then return nil, false end
        items[item] = "asked"
        Core.Call(load, item)
    end
    return nil, items[item] == "asked"
end

local bookOf, bookData      -- [Zauber] = { Gegenstand, Stufe }, gebaut aus der Tabelle bookData
function SpellSources.BookOf(spell)
    spell = Num(spell)
    local data = Core.ClientData and Core.ClientData.Table and Core.ClientData.Table("spellBooks")
    if not (spell and type(data) == "table") then return nil end
    if bookData ~= data then
        bookOf, bookData = {}, data
        for _, item in ipairs(Core.SortedKeys(data)) do
            local e = data[item]
            local id, level = Num(Core.Peek(e, 1)), Num(Core.Peek(e, 3)) or 0
            if id and not (bookOf[id] and bookOf[id][2] <= level) then bookOf[id] = { item, level } end
        end
    end
    local hit = bookOf[spell]
    if hit then return hit[1], hit[2] end
    return nil
end

function SpellSources.Books()
    local out = {}
    local data = Core.ClientData and Core.ClientData.Table and Core.ClientData.Table("spellBooks")
    local P = Core.Proficiency
    local class = Core.PlayerClass()
    local classID = class and P and P.ClassID(class) or nil
    if not (data and classID) then return out end
    local K = Core.Knowledge
    for item, e in pairs(data) do
        local spell, mask, rank = Num(e[1]), Num(e[2]), Num(e[4]) or 0
        if spell and mask and P.HasBit(mask, classID - 1) and not SpellSources.Learned(spell, rank) then
            local itemName, loading = BookName(item)
            local where = K and type(K.RecipeWhere) == "function" and Core.Call(K.RecipeWhere, nil, { item = item, noText = true })
            out[#out + 1] = { item = item, spell = spell, name = Core.SpellName(spell) or ("#" .. spell), rank = rank,
                itemName = itemName, level = Num(e[3]) or 0, loading = loading or nil,
                where = type(where) == "table" and where or {} }
        end
    end
    table.sort(out, function(a, b)
        local wa, wb = a.where[1] and 0 or 1, b.where[1] and 0 or 1
        if wa ~= wb then return wa < wb end
        if a.level ~= b.level then return a.level < b.level end
        if a.name ~= b.name then return a.name < b.name end
        return a.item < b.item
    end)
    return out
end

---------------------------------------------------------------------------
-- Klassenquests
---------------------------------------------------------------------------

-- Belohnungszauber laut Client: Liste (nur solche, die du lernst; {} = keine Fähigkeit) oder nil (der Client sagt nichts
-- oder nicht zu jedem Zauber, ob du ihn lernst). Ohne Zauber ist „keine Belohnung“ von „noch nicht geladen“ nur zu
-- unterscheiden, wenn der Client HaveQuestRewardData führt (Retail; im Forever-Zweig nicht belegt) und „ja“ sagt.
local function RewardSpells(questID)
    local list = Core.Call(Fn("C_QuestInfoSystem", "GetQuestRewardSpells"), questID)
    if Core.IsSecret(list) then return nil end
    local info = Fn("C_QuestInfoSystem", "GetQuestRewardSpellInfo")
    local out, any = {}, false
    for i = 1, type(list) == "table" and #list or 0 do
        local spell = Num(Core.Peek(list, i))
        if not spell then return nil end
        any = true
        local learns = Plain(Core.Peek(Core.Call(info, questID, spell), "isSpellLearned"))
        if learns == nil then return nil end                  -- keine oder gesperrte Auskunft
        if learns then out[#out + 1] = spell end              -- „nein“: eine Wirkung (Aura), keine Fähigkeit
    end
    if not any and Core.Bool(Core.Call(rawget(_G, "HaveQuestRewardData"), questID), false) ~= true then return nil end
    return out
end

local function Answer(questID)
    local have = answers[questID]
    if have then return have end
    have = RewardSpells(questID)
    if have then answers[questID] = have end
    return have
end

local function Request(questID)
    asked[questID] = true
    Core.Call(Fn("C_QuestLog", "RequestLoadQuestByID"), questID)
    Core.Call(Fn("C_TaskQuest", "RequestPreloadRewardData"), questID)
end

-- Sind nach diesem Aufruf noch Quests ungefragt, in ASK_PAUSE Sekunden weiter (schweigt der Client, käme sonst kein Ereignis)
local function AskAgain()
    local T = rawget(_G, "C_Timer")
    if again or type(T) ~= "table" or type(T.After) ~= "function" then return end
    again = true
    T.After(SpellSources.ASK_PAUSE, function()
        again = false
        Changed()
    end)
end

-- Fähigkeiten laut Faktenliste (Core.QuestSpells), nur solche, die der Client deiner Klasse und deinem Volk zuschreibt;
-- für die gekennzeichneten Ausnahmen (extra: Reittiere, Gifte) genügt ein Zauber mit Namen. → { spells, … } | nil
local function Fact(class, q)
    local QS = Core.QuestSpells
    local hit = QS and type(QS.Find) == "function" and (QS.Find(class, q.base, q.level) or QS.Find(class, q.name, q.level)) or nil
    if not hit then return nil end
    local CD, out = Core.ClientData, {}
    for _, spell in ipairs(hit.spells) do
        local known = CD and type(CD.ClassSpell) == "function" and CD.ClassSpell(spell, class) or nil
        if known then
            if CD.RaceAllows(known, CD.PlayerRace()) then out[#out + 1] = spell end
        elseif hit.extra and Core.SpellName(spell) then
            out[#out + 1] = spell
        end
    end
    if #out == 0 then return nil end
    return { spells = out, lead = hit.lead, either = hit.either, wiki = hit.wiki }
end

-- Mehrere offene Quests gleichen Namens zur selben Fähigkeit (Schritte einer Reihe: „The Tome of Divinity“) werden eine
-- Zeile: die angenommene, sonst die erste; steps = wie viele es sind.
local function Merge(list)
    local out, by = {}, {}
    for _, e in ipairs(list) do
        local key = ("%s|%s|%s"):format(tostring(e.name), table.concat(e.spells, ","), tostring(e.lead))
        local at = e.name and by[key]
        if not at then
            out[#out + 1] = e
            by[key] = #out
        else
            local first = out[at]
            local steps = (first.steps or 1) + 1
            if e.active and not first.active then out[at] = e end
            out[at].steps = steps
        end
    end
    return out
end

function SpellSources.Quests()
    local Q = Core.Sources and Core.Sources.Questie
    local class = Core.PlayerClass()
    if not (class and Q and type(Q.ClassQuests) == "function") then return nil, "missing" end
    local res, why = Q.ClassQuests(class)
    if not res then return nil, why end
    local out = { taught = {}, open = {}, source = res.source, sourceKey = res.sourceKey }
    local budget, left = SpellSources.ASK, false
    for _, q in ipairs(res.list) do
        if Core.QuestDone(q.id) ~= true then
            local spells = Answer(q.id)
            if spells == nil and not asked[q.id] then
                if budget > 0 then
                    budget = budget - 1
                    Request(q.id)
                    spells = Answer(q.id)
                else
                    left = true
                end
            end
            local e = { id = q.id, name = Core.QuestTitle(q.id) or q.name, level = q.level, spells = {},
                active = Core.Bool(Core.Call(Fn("C_QuestLog", "IsOnQuest"), q.id), false) or nil }
            -- der Client geht vor; schweigt er (oder bringt die Quest selbst nichts, führt aber zu etwas): die Faktenliste
            local from = spells ~= nil and "client" or nil
            if spells == nil or #spells == 0 then
                local fact = Fact(class, q)
                if fact and (spells == nil or fact.lead) then
                    spells, from = fact.spells, fact.wiki and "wiki" or "guide"
                    e.lead, e.either = fact.lead, fact.either
                end
            end
            e.failed = failed[q.id]
            if spells == nil then
                out.open[#out.open + 1] = e
            else
                e.from = from
                for _, spell in ipairs(spells) do
                    if not SpellSources.Learned(spell) then e.spells[#e.spells + 1] = spell end
                end
                -- „nur eine davon“: ist eine gelernt, ist die Wahl getroffen (zur anderen führt ihre eigene Reihe)
                if e.spells[1] and not (e.either and #e.spells < #spells) then out.taught[#out.taught + 1] = e end
            end
        end
    end
    if left then AskAgain() end
    table.sort(out.taught, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        if (a.lead and 0 or 1) ~= (b.lead and 0 or 1) then return a.lead == true end
        if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
        return a.id < b.id
    end)
    out.taught = Merge(out.taught)
    return out
end

function SpellSources.QuestPlace(questID)
    local Q = Core.Sources and Core.Sources.Questie
    if not (Q and type(Q.QuestStart) == "function") then return nil end
    local map = Core.PlayerPosition and Core.PlayerPosition() or nil
    local places = Q.QuestStart(questID, { map = Num(map) })
    places = type(places) == "table" and places or {}
    for _, p in ipairs(places) do
        if Num(p.map) and Num(p.x) and Num(p.y) then return p end
    end
    return places[1]
end

-- Für die Prüfungen und einen neuen Charakter
function SpellSources.Forget() asked, failed, answers, items, again = {}, {}, {}, {}, false end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

ns.On("QUEST_DATA_LOAD_RESULT", function(_, questID, success)
    local id = Num(questID)
    if not (id and asked[id]) or answers[id] then return end
    failed[id] = Plain(success) == false or nil
    Answer(id)
    Changed()
end)
-- jede Antwort zählt, auch eine erfolglose: danach gilt das Buch als gefragt (sonst forderte jedes Zeichnen es neu an)
ns.On("ITEM_DATA_LOAD_RESULT", function(_, itemID)
    local id = Num(itemID)
    if not id or items[id] ~= "asked" then return end
    items[id] = "done"
    Changed()
end)
-- gelernt (Buch benutzt, beim Lehrer gewesen) bzw. Quest abgegeben
ns.On("SPELLS_CHANGED", Changed)
ns.On("QUEST_TURNED_IN", Changed)
Core.Listen("QUESTIE_CLASSQUESTS", Changed, "ezCore.SpellSources")
