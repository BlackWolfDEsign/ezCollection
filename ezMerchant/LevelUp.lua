local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Meldung beim Stufenaufstieg als Chat-Block (W-41, MER-06, VP-50; Frage 27 – Empfehlung umgesetzt, Antwort offen:
    „Ja, kein Fenster“). Kurz nach PLAYER_LEVEL_UP (Zauberbuch und Item-Wissen ziehen nach) stehen im Chat:
      1. neue Ränge beim Lehrer mit Kosten – gezählt in ezCore (Core.Spells.Waiting über T.Waiting), dieselbe Zahl
         wie in ezPanel; Quelle: dein letzter Lehrerbesuch, ohne ihn das Zauberbuch (Einstellung levelHint); dazu die
         Zauber beim Namen mit Rang und Einzelpreis, als Link, wo der Client einen liefert, höchstens fünf, danach
         „und n weitere“ (Wunsch des Nutzers vom 15.11.2026; Einstellung spellNames, Trainer.lua: T.Names);
         darunter, was laut Client-Tabellen genau ab dieser Stufe dazukommt, aber weder Lehrerbesuch noch Zauberbuch
         nennen (Welle 26, wago F3; LU.TableLine, Quelle samt Build, „Kosten: noch nicht gesehen“)
      2. Dungeons, die mit dieser Stufe in den empfohlenen Bereich kommen, dazu die übrigen passenden – aus ezCores
         Dungeon-Tabelle (Core.Dungeons.ForLevel; Quelle: Blizzards Gruppensuche, sonst ezCores Ersatzwerte)
         (Einstellung levelDungeons)
      3. Ausrüstung aus Taschen und Bank, die genau ab dieser Stufe tragbar ist – Item-Wissen von ezCore
         (Core.Knowledge: usableFrom = Mindeststufe und Rüstungs-/Waffenart deiner Klasse), Inhalt aus ezCores
         Inventar (die Bank mit dem Stand des letzten Besuchs); mit ezGear zusätzlich „besser“ (Einstellung levelGear)
      4. der nächste Talentpunkt laut der Vorlage, der ezTalent folgt – über ezCore.API("ezTalent").NextPoint() →
         Talent, Vorlage, Quelle (Welle 8, NEU-02; Einstellung levelTalent). Nur, wenn ezTalent läuft, eine
         Reihenfolge kennt und zusagt, dass NextPoint() ohne freien Talentpunkt nil liefert (API.NextPointChecksFree
         == true – die Prüfung der freien Punkte bleibt an einer Stelle in ezTalent); vergeben wird nichts. Dann und
         mit levelTalent an meldet API.ShowsNextPoint() == true – ezTalents eigene Chatzeile schweigt, die Zeile steht
         nicht zweimal im Chat. Ohne die Zusage meldet ezTalent wie bisher selbst, ezMerchants Block schweigt dazu
    Jede Zeile nennt ihre Quelle (Leitlinie 11).
]]

local LU = {}
ns.LevelUp = LU

LU.DELAY = 2            -- Sekunden nach PLAYER_LEVEL_UP
LU.MAX_DUNGEONS = 4     -- so viele „außerdem passend“
LU.MAX_GEAR = 6         -- so viele Gegenstände je Zeile

local function Join(list, max)
    local shown = {}
    for i = 1, math.min(#list, max) do shown[i] = list[i] end
    local text = table.concat(shown, ", ")
    if #list > max then text = text .. " " .. ezCore.More(#list - max, true) end
    return text
end

-- Die wartenden Zauber beim Namen, neueste zuerst, mit Einzelpreis nach einem Lehrerbesuch (Trainer.lua: T.Names,
-- Einstellung spellNames). → Text oder nil (aus, nichts benannt)
function LU.RankNames(level)
    local T = ns.Trainer
    if not (T and T.WaitingList and T.Names) then return nil end
    local list, withCost = T.WaitingList(level)
    return T.Names(list, { cost = withCost })
end

-- 1. Neue Ränge beim Lehrer, mit den Zaubern beim Namen (Wunsch des Nutzers vom 15.11.2026). → Text oder nil
function LU.RanksLine(level)
    local T = ns.Trainer
    if not T then return nil end
    local count, total = T.Waiting(level)
    count = ns.Num(count)
    if not count or count == 0 then return nil end
    local what = Core.Plural(count, L.RANKS_ONE, L.RANKS_MANY)
    local names = LU.RankNames(level)
    if total then
        if names then return L.NEW_RANKS_NAMED:format(what, ns.Money(total), names) end
        return L.NEW_RANKS:format(what, ns.Money(total))
    end
    if names then return L.NEW_RANKS_NOCOST_NAMED:format(what, names) end
    return L.NEW_RANKS_NOCOST:format(what)
end

-- 1b. Was laut Client-Tabellen genau ab dieser Stufe dazukommt, aber weder dein letzter Lehrerbesuch noch dein
-- Zauberbuch nennt (Welle 26, wago F3; Spellbook.lua: U.TableExtra – dieselben Einträge wie in der Gruppe „Erreicht
-- laut Client-Tabellen“). Die Zahl in Zeile 1 bleibt die von Core.Spells.Waiting (wie ezPanel); diese Zeile ergänzt
-- sie, ohne sie zu ändern. Seit Welle 26 (Paket kern/ezcore-reste-24) zählt Core.Spells.Waiting die Tabellen ohne
-- Lehrerbesuch selbst mit (Core.Spells.BookEntries) – diese Zeile kommt dann nur noch nach einem Lehrerbesuch. Beim Namen mit der Einstellung spellNames, sonst als Anzahl; Quelle samt Build, Kosten
-- „noch nicht gesehen“ (der Client führt keine). Die Stufe ist die, die „Was kommt wann“ zeigt (U.EntryLevel: zuerst
-- laut Client, dann laut Tabellen). → Text oder nil
function LU.TableLine(level)
    local U = ns.Upcoming
    level = ns.Num(level)
    if not (level and U and type(U.TableExtra) == "function") then return nil end
    local reached = U.TableExtra(level)
    local list = {}
    local known = #reached > 0 and type(U.ClientLevels) == "function" and U.ClientLevels() or nil
    for _, entry in ipairs(reached) do
        local shown = type(U.EntryLevel) == "function" and U.EntryLevel(entry, nil, known) or ns.Num(entry.level)
        -- Ränge aus Büchern lehrt kein Lehrer: sie stehen in „Was kommt wann“ und „Wo kommt was“
        if shown == level and not entry.bookItem then list[#list + 1] = entry end
    end
    if #list == 0 then return nil end
    local T = ns.Trainer
    local names = T and T.Names and T.Names(list, {})
    local what = names or Core.Plural(#list, L.RANKS_ONE, L.RANKS_MANY)
    return L.LEVEL_TABLES:format(U.TableSource() or "?", what)
end

-- 2. Dungeons im neuen Stufenbereich. → Text oder nil (nichts Neues mit dieser Stufe)
function LU.DungeonLine(level)
    local D = Core.Dungeons
    if not (D and type(D.ForLevel) == "function") then return nil end
    local ok, list = pcall(D.ForLevel, level, "dungeon")
    if not ok or type(list) ~= "table" then return nil end
    local new, others, client = {}, {}, true
    for _, entry in ipairs(list) do
        local label = type(D.Label) == "function" and D.Label(entry, level) or entry.name
        if type(label) == "string" then
            if ns.Num(entry.minLevel) == level then new[#new + 1] = label else others[#others + 1] = label end
            if entry.fromClient ~= true then client = false end
        end
    end
    if #new == 0 then return nil end
    local text = L.LEVEL_DUNGEONS:format(table.concat(new, ", "))
    if #others > 0 then text = text .. " " .. L.LEVEL_DUNGEONS_ALSO:format(Join(others, LU.MAX_DUNGEONS)) end
    return text .. " " .. (client and L.LEVEL_SOURCE_LFG or L.LEVEL_SOURCE_TABLE)
end

-- Ausrüstung aus einer Liste von ezCores Inventar ({ { i, l, c, … } … }), die genau ab level tragbar ist.
local function Wearable(list, level, seen, gear)
    local out = {}
    local K = Core.Knowledge
    if type(list) ~= "table" or not (K and K.Get) then return out end
    for _, e in ipairs(list) do
        local link = type(e) == "table" and e.l
        if type(link) == "string" and not ns.IsSecret(link) and not seen[link] then
            seen[link] = true
            local f = K.Get(link)
            if type(f) == "table" and f.isEquipment and ns.Num(f.usableFrom) == level then
                local text = link
                if gear then
                    local okUp, better = pcall(gear.IsUpgrade, link)
                    if okUp and better == true then text = text .. " " .. L.LEVEL_GEAR_BETTER end
                end
                out[#out + 1] = text
            end
        end
    end
    return out
end

-- 3. Jetzt tragbare Teile. → Liste von Texten (Taschen, Bank)
function LU.GearLines(level)
    local me = Core.me
    local items = type(me) == "table" and me.items
    if type(items) ~= "table" then return {} end
    local api = Core.API("ezGear")
    local gear = type(api) == "table" and type(api.IsUpgrade) == "function" and api or nil
    local seen, lines = {}, {}
    local bags = Wearable(items.bags, level, seen, gear)
    if #bags > 0 then lines[#lines + 1] = L.LEVEL_GEAR:format(Join(bags, LU.MAX_GEAR), L.LEVEL_GEAR_BAGS) end
    local bank = Wearable(items.bank, level, seen, gear)
    if #bank > 0 then
        local seenAt = ns.Num(me.bankSeen)
        local where = seenAt and L.LEVEL_GEAR_BANK:format(Core.Ago(seenAt)) or L.LEVEL_GEAR_BANK_OLD
        lines[#lines + 1] = L.LEVEL_GEAR:format(Join(bank, LU.MAX_GEAR), where)
    end
    return lines
end

-- ezTalents Schnittstelle, wenn NextPoint() ohne freien Talentpunkt nil liefert (NextPointChecksFree == true);
-- sonst nil. Ohne diese Zusage übernimmt ezMerchant die Zeile nicht: ezTalents eigene Zeile prüft die freien Punkte
-- (Plan.ReportNext über Traits.Currency), ezMerchants Zeile stünde sonst auch auf Stufen ohne neuen Klassenpunkt.
function LU.TalentAPI()
    local api = Core.API("ezTalent")
    if type(api) == "table" and type(api.NextPoint) == "function" and api.NextPointChecksFree == true then return api end
    return nil
end

-- 4. Nächster Talentpunkt laut ezTalent. → Text oder nil (ezTalent fehlt, prüft keine freien Punkte, kennt keine
-- Reihenfolge, kein Punkt frei, Schalter aus)
function LU.TalentLine()
    local api = LU.TalentAPI()
    local fn = api and api.NextPoint
    if type(fn) ~= "function" then return nil end
    local ok, name, template, source = pcall(fn)
    if not ok then
        ns.Error(name, "NextPoint (ezTalent)")
        return nil
    end
    if ns.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    if ns.IsSecret(template) or type(template) ~= "string" or template == "" then template = "?" end
    if ns.IsSecret(source) or type(source) ~= "string" or source == "" then source = L.LEVEL_TALENT_SOURCE end
    return L.LEVEL_TALENT:format(name, template, source)
end

-- Zeigt ezMerchants Block den nächsten Talentpunkt? (ezCore.API("ezMerchant").ShowsNextPoint, für ezTalent)
-- Nur mit levelTalent und einem ezTalent, das die freien Punkte selbst prüft – sonst meldet ezTalent wie bisher.
function LU.ShowsTalent()
    return ns.Enabled("levelTalent") == true and LU.TalentAPI() ~= nil
end

-- Alle Zeilen des Blocks für diese Stufe (je Teil eine Einstellung).
function LU.Lines(level)
    local lines = {}
    local function Add(text) if type(text) == "string" and text ~= "" then lines[#lines + 1] = text end end
    if ns.Enabled("levelHint") then
        ns.Try("LevelRanks", function() Add(LU.RanksLine(level)) end)
        ns.Try("LevelTables", function() Add(LU.TableLine(level)) end)
    end
    if ns.Enabled("levelDungeons") then ns.Try("LevelDungeons", function() Add(LU.DungeonLine(level)) end) end
    if ns.Enabled("levelGear") then
        ns.Try("LevelGear", function() for _, text in ipairs(LU.GearLines(level)) do Add(text) end end)
    end
    if LU.ShowsTalent() then ns.Try("LevelTalent", function() Add(LU.TalentLine()) end) end
    return lines
end

-- Block in den Chat: eine Zeile allein, mehrere unter einer Kopfzeile. → Zahl der Zeilen
function LU.Report(level)
    level = ns.Num(level) or Core.PlayerLevel()
    if not level then return 0 end
    local lines = LU.Lines(level)
    if #lines > 1 then ns.Print(L.LEVEL_HEAD:format(level)) end
    for _, text in ipairs(lines) do
        ns.Print(#lines > 1 and ("  " .. (Core.ARROW or "-") .. " " .. text) or text)
    end
    return #lines
end

ns.On("PLAYER_LEVEL_UP", function(_, level)
    if not (ns.Enabled("levelHint") or ns.Enabled("levelDungeons") or ns.Enabled("levelGear") or LU.ShowsTalent()) then
        return
    end
    level = ns.Num(level)
    -- Zauberbuch, Lehrerdaten und Item-Wissen kurz nachziehen lassen
    C_Timer.After(LU.DELAY, function() ns.Try("LevelUp", LU.Report, level) end)
end)

-- Schnittstelle für ezTalent (NEU-02): true, solange ezMerchants Block die Zeile „Nächster Punkt“ übernimmt.
ns.API.ShowsNextPoint = function() return LU.ShowsTalent() end
