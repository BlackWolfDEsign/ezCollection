local ADDON, ns = ...
local Core = ezCore
local L = ns.L
local Spells = Core.Spells

--[[
    Zauberwerte für die Rotations-Simulation (Welle 21, docs/talent-simulation.md, Abschnitt 6; Wunsch des Nutzers vom
    15.11.2026 abends: „die welle mit der talentbaum simulation trifft auch für die rotationen zu“).

    Das Rechnen läuft offline (tools/rotation_sim.lua, LuaJIT) – im Spiel liest ezCombat nur aus, was der Client zu den
    gelernten Zaubern weiß (Leitlinie 11: der Client zuerst), und gibt es als EINEN Text zum Kopieren aus:
      - je gelerntem, nicht passivem Zauber des Zauberbuchs (höchster Rang, Core.Spells): Grund-ID (kleinster gelernter
        Rang – die Form der Rotationsdaten), ID des höchsten Rangs, Rang, Name, Kosten und Ressource
        (C_Spell.GetSpellPowerCost), Zauberzeit (C_Spell.GetSpellInfo), Abklingzeit und globale Abklingzeit
        (GetSpellBaseCooldown) und der Tooltip-Text (C_Spell.GetSpellDescription) – Blizzards Funktionen, jede
        geschützt; geheime Werte werden übersprungen und gezählt (Leitlinie 6).
    Die Zahlen im Text zerlegt erst das Werkzeug (mit ezTalents Hilfen aus ezTalent/Measure.lua – eine Quelle).
    Gemessen wird nur außerhalb des Kampfes. Nichts wird gespeichert. Feldhelfer und Textausgabe (Kampfsperre,
    Hinweise, Link zum Mithelfen, Core.TextDialog) teilen sich ezTalent und ezCombat seit Welle 23 (A4) über ezCore
    (Core.MeasureField, Core.Measure.Show).

    Jede Stufe hilft (Frage des Nutzers vom 16.11.2026, wörtlich: „reichen auch die nackten character-stats von lvl 1?
    und ggf. lvl20? oder ist lvl 60 unabdingbar?“ – Antwort: Stufe 60 ist nicht unabdingbar): Stufe, Klasse und Volk
    stehen im Titel des Fensters und in der Kopfzeile des Textes; unter Stufe 60 kommt ein Hinweis statt einer Warnung,
    eine fehlende Spezialisierung (unter Stufe 10 gibt es keine Talente) bleibt ein leeres Feld. Unter dem Hinweis
    steht in einer Zeile, wohin der Text geht (Wunsch des Nutzers vom 16.11.2026: Helfer sollen ohne Anleitung
    wissen, was zu tun ist).

    Form des Textes (Fassung 1, gelesen von tools/rotation_sim.lua):
      ezCombat-Zauber;1;<Klasse>;<Volk>;<Stufe>;<Sprache>;<Build>;<Datum>;<Talentbaum>
      zauber;<Grund-ID>;<ID>;<Rang>;<Name>;<Kosten>;<Ressource>;<Zauberzeit ms>;<Abklingzeit ms>;<GCD ms>;<Text>
    Ressource: mana, rage, energy, focus … (Blizzards Enum.PowerType als Wort), leer ohne Kosten. Talentbaum: die
    Spezialisierung, die der Client meldet (leer, wenn er keine kennt).
]]

local Measure = {}
ns.RotationMeasure = Measure

Measure.HEAD, Measure.VERSION = "ezCombat-Zauber", 1
-- Höchststufe vom Client (Core.MaxLevel; Gesamtreview 18.11.2026, T16-14 – vorher fest 60, ein Forever-Patch mit höherer
-- Stufe hätte die Warnung „unter Höchststufe“ zwischen 60 und der neuen Grenze verschluckt)
function Measure.MaxLevel() return Core.MaxLevel() end
-- Enum.PowerType als Wort (Blizzards Werte: 0 Mana, 1 Wut, 2 Fokus, 3 Energie)
Measure.POWER = { [0] = "mana", [1] = "rage", [2] = "focus", [3] = "energy" }

local Field = Core.MeasureField      -- Wert ohne „;“ und Zeilenumbruch (ezCore, Welle 23)

-- Geschützter Aufruf; ein gesperrter Wert zählt als fehlend (secret wird gezählt).
local function Read(counter, fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    if Core.IsSecret(a) or Core.IsSecret(b) then
        counter.secret = counter.secret + 1
        return nil
    end
    return a, b
end

-- Kosten und Ressource: erster Eintrag von C_Spell.GetSpellPowerCost (Kosten 0 und keine Ressource ohne Eintrag).
function Measure.Cost(id, counter)
    local list = Read(counter, C_Spell and C_Spell.GetSpellPowerCost, id)
    local first = type(list) == "table" and list[1] or nil
    if type(first) ~= "table" or Core.IsSecret(first) then return 0, "" end
    local rawCost, rawType = Core.Peek(first, "cost"), Core.Peek(first, "type")
    if Core.IsSecret(rawCost) or Core.IsSecret(rawType) then
        counter.secret = counter.secret + 1
        return 0, ""
    end
    local cost = Core.Num(rawCost) or 0
    local power = Core.Num(rawType)
    return cost, power and Measure.POWER[power] or (power and tostring(power) or "")
end

-- Eine Zeile je Zauber. entry: { name, ranks = { [Rang] = id }, maxRank, maxID } aus Core.Spells.
function Measure.Row(entry, counter)
    local id = entry.maxID
    if type(id) ~= "number" then return nil end
    if Read(counter, C_Spell and C_Spell.IsSpellPassive, id) == true then return nil end
    local base, low
    for rank, rid in pairs(entry.ranks or {}) do
        if type(rank) == "number" and (not low or rank < low) then base, low = rid, rank end
    end
    base = base or id
    local cost, power = Measure.Cost(id, counter)
    local info = Read(counter, C_Spell and C_Spell.GetSpellInfo, id)
    local cast = type(info) == "table" and Core.Num(Core.Peek(info, "castTime")) or 0
    local cooldown, gcd = Read(counter, rawget(_G, "GetSpellBaseCooldown"), id)
    -- ohne Farb-, Link-, Textur- und Umbruch-Codes (Core.CleanText) – sonst läse das Werkzeug „|cFF00FF00100|r“ als
    -- vier Zahlen; wie ezTalent/Measure.lua (RankText)
    local text = Core.CleanText(Read(counter, C_Spell and C_Spell.GetSpellDescription, id))
    if type(text) ~= "string" or text == "" then
        counter.empty = counter.empty + 1
        if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, id) end
        text = ""
    end
    return table.concat({ "zauber", base, id, entry.maxRank or 0, Field(entry.name), cost, power, Core.Num(cast) or 0,
        Core.Num(cooldown) or 0, Core.Num(gcd) or 0, Field(text) }, ";")
end

-- Wer misst: Stufe, Klasse und Volk in Blizzards Wortlaut (UnitClass, UnitRace; Token als Rückfall). → Text
function Measure.Who(level)
    local className, classToken = Core.Call(rawget(_G, "UnitClass"), "player")
    local raceName, raceToken = Core.Call(rawget(_G, "UnitRace"), "player")
    className = Core.Plain(className) or Core.Plain(classToken) or Core.PlayerClass() or "?"
    raceName = Core.Plain(raceName) or Core.Plain(raceToken) or "?"
    return L.SIM_MEASURE_WHO:format(tostring(level or "?"), tostring(className), tostring(raceName))
end

-- Der ganze Text zum Kopieren. → Text, Zahl der Zauber, { secret, empty }, Stufe; nil, wenn kein Zauber gelernt ist
function Measure.Text()
    local counter = { secret = 0, empty = 0 }
    local rows = {}
    if Spells and Spells.ForEachKnown then
        Spells.ForEachKnown(function(entry)
            local row = Measure.Row(entry, counter)
            if row then rows[#rows + 1] = row end
        end)
    end
    if #rows == 0 then return nil, 0, counter end
    local class = Core.PlayerClass() or "?"
    local _, race = Core.Call(rawget(_G, "UnitRace"), "player")
    local locale = Core.Call(rawget(_G, "GetLocale")) or "?"
    local level = Core.PlayerLevel()
    local version, build = Core.Call(rawget(_G, "GetBuildInfo"))
    local stamp = tostring(Core.Plain(version) or "?") .. "." .. tostring(Core.Plain(build) or "?")
    local spec = ns.Num(Core.Call(rawget(_G, "GetSpecialization")))
    local head = table.concat({ Measure.HEAD, Measure.VERSION, class, Field(Core.Plain(race) or "?"), level or "?",
        Field(locale), Field(stamp), date and date("%Y-%m-%d") or "?", spec or "" }, ";")
    table.insert(rows, 1, head)
    return table.concat(rows, "\n"), #rows - 1, counter, level
end

-- Hinweise zur Messung: unter Stufe 60 (hilft trotzdem), Zauber ohne Text, gesperrte Werte. → { Text … }
function Measure.Warnings(counter, level)
    local out = {}
    level = Core.Num(level)
    if level and level < Measure.MaxLevel() then out[#out + 1] = L.SIM_MEASURE_LEVEL:format(level) end
    if (counter.empty or 0) > 0 then out[#out + 1] = L.SIM_MEASURE_EMPTY_TEXT:format(counter.empty) end
    if (counter.secret or 0) > 0 then out[#out + 1] = L.SIM_MEASURE_SECRET:format(counter.secret) end
    return out
end

-- Sichtbarer Weg: Knopf „Zauberwerte für die Simulation messen“ auf der Einstellungsseite (Erweitert); /ezk werte
-- zusätzlich. Ablauf über ezCore (Core.Measure.Show): Kampfsperre, leer?, Hinweise samt Zeile „Als GitHub-Issue mit der
-- Vorlage „Werte messen“ schicken“ mit dem Link, Fenster zum Kopieren. Im Kampf liest ezCombat gar nicht erst. → true, wenn
-- der Text gezeigt wurde
function Measure.Show()
    if ns.InCombat() then
        Core.CombatNotice(ns, L.SIM_MEASURE_WHAT)   -- ezCores Satz (T18-1)
        return false
    end
    local text, count, counter, level = Measure.Text()
    return Core.Measure.Show({
        text = text, print = ns.Print, combatText = Core.CombatText(L.SIM_MEASURE_WHAT), emptyText = L.SIM_MEASURE_NONE,
        title = text and L.SIM_MEASURE_TITLE:format(count, Measure.Who(level)) or nil,
        hint = L.SIM_MEASURE_HINT, warnings = text and Measure.Warnings(counter, level) or nil,
        sendText = L.SIM_MEASURE_SEND, owner = ADDON,
    })
end
