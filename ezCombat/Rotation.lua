local _, ns = ...
local L = ns.L
local Core = ezCore
local Spells = Core.Spells
local State = ns.RotationState

-- Rotationen (Wunsch des Nutzers, 13.11.2026: „verschiedene rotations je klasse und rasse, einmal um es sich
-- anzuschauen und als zweites … das man sich rotations auswählen kann und immer die nächste aktion direkt
-- vorausgesagt/angezeigt wird“; dazu „die funktion muss schon unterscheiden zwischen fest rotattion, einmaligen
-- buffs aller x min etc.“). Daten: ns.ROTATIONS (RotationData/<KLASSE>.lua, je Rotation mit Quelle).
--
-- Die Regel:
--   1. Die Liste steps einer Rotation ist flach, ihre Reihenfolge ist die Rangfolge.
--   2. Die Art eines Schritts (kind) steuert nur das Tor (wird er jetzt überhaupt bewertet?) und den Abschnitt im
--      Zauberbuch – nie den Rang.
--   3. Zwei getrennte Auswertungen:
--        Vor dem Kampf (Rotation.EvaluatePrep)  nur Dauer-Buffs (longbuff) und Vorbereitung (prepare), nur
--            außerhalb des Kampfes, auch ohne Ziel. Ergebnis: alle fälligen Schritte.
--        Als Nächstes (Rotation.Evaluate)       alle übrigen Arten außer „situativ“, ein Durchgang in
--            Listenreihenfolge, nur mit angreifbarem Ziel. Ergebnis: der erste fällige Schritt.
--   4. Ein Dauer-Buff oder eine Vorbereitung kommt nie aus Evaluate – weder im Kampf noch davor.
--   5. Schritte ohne kind (Altdaten) laufen wie bisher; die eine Ausnahme: when = "buff" auf einem Klassen-Buff,
--      der mindestens ezCore.Spells.LONG_BUFF_MINUTES hält, gilt als Dauer-Buff (Dämonenhaut, Rüstungen, Inneres
--      Feuer, Dornen …) und geht damit nur noch in „Vor dem Kampf“.
-- Jede Prüfung liefert wahr / falsch / unbekannt (gesperrte oder unlesbare Werte): Unbekanntes wird übersprungen
-- und genannt (Tooltip, /ezk status) – ezCombat rät nie. Der Client ist die Quelle: Name, Symbol, Ränge, gelernt,
-- nutzbar, Abklingzeit, Zauberzeit, Auren und ihre Dauer kommen zur Laufzeit aus ezCore.Spells und ezCore.Auras.
--
-- Nächste Aktion: Liefert Blizzards Rotations-Assistent eine Empfehlung (C_AssistedCombat, auf Forever laut Quelle
-- nur im Spieltyp „mainline“ geladen), zeigt ezCombat sie; sonst die eigene Auswertung.
-- Anzeige: am Symbolplatz (ns.Symbol: „Vor dem Kampf: …“, „Als Nächstes: …“) und leuchtend am Aktionsknopf über
-- ezCores Leucht-Dienst (Core.Glow: „next“, „side“, „prep“ – jeder Rang des Zaubers zählt).
local Rotation = {}
ns.Rotation = Rotation

local CHECK_EVERY = 0.25
local IDLE_EVERY = 5            -- Sekunden: ohne Ziel außerhalb des Kampfes (sonst auf Ereignisse)
local PREVIEW_SECONDS = 4
-- Vorwarnung vor Ablauf (Welle 27, Paket modul/ezcombat-abklingzeit; Wunsch des Nutzers vom 16.11.2026 zu „solange die
-- Abklingzeit läuft“: „ja oder halt 3sek vorher“): Ein höher eingestufter Schritt, dessen Abklingzeit in höchstens so
-- vielen Sekunden endet (Einstellung rotationWarn, 0–5, ab Werk 3), erscheint schon vorher als „gleich bereit“ mit
-- Restzeit; vorn steht er, wenn er innerhalb von Rotation.SOON_LEAD bereit wird (oder kein anderer Schritt bereit ist).
-- SOON_LEAD 0,5 s: Wer jetzt den niedrigeren Schritt drückt, löst die globale Abklingzeit (bis 1,5 s) aus und verzögert
-- den höheren um bis zu 1,5 s minus Rest; Blizzards Zauberschlange (CVar SpellQueueWindow, ab Werk 400 ms) nimmt einen
-- Druck so kurz vor dem Ende schon an. Läuft die globale Abklingzeit offen lesbar länger, gilt ihr Rest.
Rotation.SOON_LEAD = 0.5
local OWNER = "ezCombat"
local RACE_ALIAS = { Scourge = "Undead" }     -- UnitRace liefert für Untote „Scourge“
local POWER_ID = { Mana = 0, Rage = 1, Energy = 3, ComboPoints = 4 }

-- Art (Farbe) für „nächste Aktion“: ezCores Art „next“ (Gold, „jetzt nutzen“, ezCore 1.6.2).
function Rotation.Kind() return "next" end

-- Art eines Schritts → Abschnitt (Auswertung und Platz im Zauberbuch).
Rotation.KINDS = { longbuff = "prep", prepare = "prep", opener = "opener", maintain = "combat", priority = "combat",
    resource = "combat", phase = "combat", filler = "combat", cooldown = "cooldown", aoe = "aoe",
    situational = "situational" }
Rotation.SECTIONS = { "prep", "opener", "combat", "cooldown", "aoe", "situational" }
-- Arten, bei denen „nur die Kraft fehlt“ nicht genügt (kein Vorschlag ohne Mana, Wut, Energie).
local NEEDS_POWER = { longbuff = true, prepare = true, resource = true, cooldown = true }
local BOSS_RANKS = { elite = true, rareelite = true, worldboss = true }

---------------------------------------------------------------------------
-- Daten und Auswahl (gemerkt je Charakter)
---------------------------------------------------------------------------

-- Berechnete Rotationen zeigen (Welle 21)? Immer – der Schalter rotationComputed blendete nur Listeneinträge aus und ist
-- gestrichen (Einstellungs-Prüfung 19.11.2026, Nr. 34: wer eine bestimmte Rotation will, wählt sie aus).
function Rotation.ComputedShown() return true end

-- Berechnet (Welle 21, RotationComputed.lua): trägt die Herkunft computed = { date, build, model, distribution, … }.
function Rotation.IsComputed(rotation) return type(rotation) == "table" and type(rotation.computed) == "table" end

-- Nimmt „Nach Talentbaum“ diese Rotation? Vorlagen immer; berechnete nur mit Erkennung (pick, eigene Talente der
-- Verteilung), nicht vorläufig (ohne Talentwirkungen gerechnet) und nicht für Heiler (Heilzauber nur von Hand: der
-- Motor schlägt nur gegen ein angreifbares Ziel vor) – die bleiben wählbar.
function Rotation.AutoEligible(rotation)
    if Rotation.IsOwn(rotation) then return false end      -- eigene Rotation (RotationOwn.lua): nur von Hand
    if not Rotation.IsComputed(rotation) then return true end
    local c = rotation.computed
    return c.provisional ~= true and c.healer ~= true and type(rotation.pick) == "table"
end

-- Eigene Rotation dieses Charakters (RotationOwn.lua, Kopie einer Vorlage)?
function Rotation.IsOwn(rotation) return type(rotation) == "table" and type(rotation.own) == "table" end

-- Rotationen einer Klasse: zuerst die eigenen dieses Charakters (RotationOwn.lua), mit Schalter dann die berechneten
-- (passend zur erkannten Talentverteilung, Welle 21), dann die Vorlagen aus RotationData/<KLASSE>.lua. Die Liste wird
-- je Klasse gemerkt, bis sich eine der Quellen ändert.
local combined = {}
local NO_LIST = {}      -- gemeinsame leere Liste (nur lesen)
function Rotation.ForClass(class)
    class = class or ns.playerClass
    local list = (ns.ROTATIONS or {})[class]
    list = type(list) == "table" and list or {}
    local data = ns.RotationData
    local own = ns.RotationOwn and ns.RotationOwn.ForClass(class) or NO_LIST
    local computed = NO_LIST
    if Rotation.ComputedShown() and data and data.Computed then computed = data.Computed(class) end
    if #computed == 0 and #own == 0 then return list end
    local slot = combined[class or "?"]
    if slot and slot.list == list and slot.count == #list and slot.computed == computed and slot.own == own then
        return slot.out
    end
    local out = {}
    for _, rotation in ipairs(own) do out[#out + 1] = rotation end
    for _, rotation in ipairs(computed) do out[#out + 1] = rotation end
    for _, rotation in ipairs(list) do out[#out + 1] = rotation end
    combined[class or "?"] = { list = list, count = #list, computed = computed, own = own, out = out }
    return out
end

function Rotation.Find(key, class)
    for _, rotation in ipairs(Rotation.ForClass(class)) do
        if rotation.key == key then return rotation end
    end
    return nil
end

-- Passt eine Rotation zu „Nach Talentbaum“? pick = { leveling, level, known, unknown, form … } – Bedeutung wie
-- need; alle Angaben müssen gelten. true / false / nil (unbekannt: eine Angabe ist gesperrt, keine ist falsch –
-- für Aufrufer, die nur wahr/falsch kennen, heißt das „passt nicht“). Ohne pick passt sie immer.
function Rotation.PickMatches(rotation)
    local pick = rotation and rotation.pick
    if type(pick) ~= "table" then return true end
    local ctx = { now = GetTime(), combat = ns.InCombat(), rotation = rotation }
    local unknown = false
    for key, value in pairs(pick) do
        local fn = Rotation.CHECKS and Rotation.CHECKS[key]
        if not fn then return false end
        local result = fn(value, nil, ctx)
        if result == nil then
            unknown = true
        elseif result ~= true then
            return false
        end
    end
    if unknown then return nil end
    return true
end

-- Letzte Antwort von Rotation.Default je Klasse (Schlüssel): Bleibt ein pick unbekannt (Gestaltleiste im Kampf
-- gesperrt), gilt sie weiter – sonst spränge „Nach Talentbaum“ hin und her und setzte jedes Mal den Zustand zurück.
local lastDefault = {}

-- Talentbaum des Charakters (1–3, der mit den meisten bestätigten Punkten) → Nummer | nil, bekannt (nil und true: noch
-- keine Punkte). Bis zum 24.11.2026 fragte „Nach Talentbaum“ GetSpecialization: Die Globale gibt es auf Forever nicht, und
-- je Klasse gibt es nur eine Spezialisierung – es nahm immer die erste Rotation der Klasse (Paladin 0/7/0 » „Heilig“).
function Rotation.Tree() return Core.Talents.MainTree() end

-- Name des Talentbaums n der eigenen Klasse aus dem Client, sonst „Talentbaum n“; nil ohne Nummer.
function Rotation.TreeName(n)
    if type(n) ~= "number" then return nil end
    return Core.Talents.TreeName(n) or L.ROTATION_BOOK_TREE:format(n)
end

-- Woran „Nach Talentbaum“ sich hält: „Dein Talentbaum: Schutz (0 / 7 / 0)“ bzw. warum es die erste Rotation nimmt.
function Rotation.AutoWhy()
    local tree, known = Rotation.Tree()
    if not known then return L.ROTATION_AUTO_UNKNOWN end
    if not tree then return L.ROTATION_AUTO_NO_POINTS end
    local stand = Core.Talents.Current()
    return L.ROTATION_AUTO_TREE:format(Rotation.TreeName(tree), stand and table.concat(stand.spent, " / ") or "?")
end

-- Ohne eigene Wahl: die erste Rotation des Talentbaums (ohne Punkte oder unbekannt: der Klasse), deren pick passt;
-- ist ein pick davor unbekannt, die letzte Wahl (wenn sie noch zum Talentbaum gehört); passt keine, die erste.
-- Berechnete Rotationen stehen vorn und kommen nur mit Erkennung in Frage (Rotation.AutoEligible).
function Rotation.Default(class)
    class = class or ns.playerClass
    local list = Rotation.ForClass(class)
    local tree = class == ns.playerClass and Rotation.Tree() or nil      -- von einer anderen Klasse ist nichts bekannt
    local all = true
    for _, rotation in ipairs(list) do all = all and Rotation.AutoEligible(rotation) end
    if not all then
        local eligible = {}
        for _, rotation in ipairs(list) do
            if Rotation.AutoEligible(rotation) then eligible[#eligible + 1] = rotation end
        end
        if #eligible > 0 then list = eligible end
    end
    local candidates = list
    if tree then
        local ofTree = {}
        for _, rotation in ipairs(list) do
            if rotation.tree == tree then ofTree[#ofTree + 1] = rotation end
        end
        if #ofTree > 0 then candidates = ofTree end
    end
    local unknown = false
    for _, rotation in ipairs(candidates) do
        local match = Rotation.PickMatches(rotation)
        if match == true then
            if not unknown then
                lastDefault[class or "?"] = rotation.key
                return rotation
            end
            break
        elseif match == nil then
            unknown = true
        end
    end
    if unknown then
        local last = lastDefault[class or "?"]
        for _, rotation in ipairs(candidates) do
            if rotation.key == last then return rotation end
        end
    end
    for _, rotation in ipairs(candidates) do
        if Rotation.PickMatches(rotation) == true then return rotation end
    end
    return candidates[1]
end

local function CharKey() return Core.charKey or "?" end

-- Gewählter Schlüssel des Charakters („auto“ = nach Talentbaum).
function Rotation.Choice()
    local saved = ns.db and type(ns.db.rotations) == "table" and ns.db.rotations[CharKey()]
    if saved and (saved == "auto" or Rotation.Find(saved)) then return saved end
    return "auto"
end

function Rotation.Selected()
    local choice = Rotation.Choice()
    return (choice ~= "auto" and Rotation.Find(choice)) or Rotation.Default()
end

function Rotation.Select(key)
    if not ns.db then return end
    ns.db.rotations = type(ns.db.rotations) == "table" and ns.db.rotations or {}
    ns.db.rotations[CharKey()] = key or "auto"
    if ns.S and ns.S.rotationChoice ~= (key or "auto") then ns.SetSetting("rotationChoice", key or "auto") end
    State.Reset("all")
    -- unter ns.Try wie die Takte (T7-NE2): ein Fehler bricht den Wechsel nicht ab, die Zuhörer laufen trotzdem
    ns.Try("Rotation", Rotation.Update)
    for _, fn in ipairs(Rotation.listeners) do pcall(fn) end
end
Rotation.listeners = {}
function Rotation.OnChange(fn) table.insert(Rotation.listeners, fn) end
-- fn() nach jedem Wechsel der nächsten Aktion (Zauberbuch-Seite markiert sie)
Rotation.nextListeners = {}
function Rotation.OnNext(fn) table.insert(Rotation.nextListeners, fn) end

local function Localized(pair)
    if type(pair) ~= "table" then return nil end
    return (Core.IsGerman() and pair[1] or pair[2]) or pair[1]
end
Rotation.Localized = Localized

-- Herkunft einer berechneten Rotation in Sätzen (Seite „Rotation“ und Tooltip der Auswahl; Leitlinie 11: jede Angabe
-- nennt ihre Quelle): „Berechnet am … für die Talentverteilung …“, Annahmen, Quelle der Werte und – wenn „Nach
-- Talentbaum“ sie nicht nimmt – warum. → { Text … } (leer für Vorlagen)
function Rotation.ComputedLines(rotation)
    if not Rotation.IsComputed(rotation) then return {} end
    local c = rotation.computed
    local date, model, build = tostring(c.date or "?"), tostring(c.model or "?"), tostring(c.build or "?")
    local lines = {}
    local talentBuild = type(c.distribution) == "table" and Localized(c.distribution.name) or nil
    if talentBuild then
        lines[#lines + 1] = L.ROTATION_COMPUTED_AT:format(date, talentBuild, model, build)
    else
        lines[#lines + 1] = L.ROTATION_COMPUTED_AT_NONE:format(date, model, build)
    end
    -- „%s“ in den Annahmen ist ezTalents geltender Befehl (tools/rotation_sim.lua schreibt keinen festen Kurzbefehl;
    -- Gesamtreview T18-2, D3); ohne geladenes ezTalent dessen fester Befehl /eztalent. ezCore löst den Modulnamen
    -- auf, ezCombat kennt ezTalents ns nicht (Gegenprüfung D3)
    local assume = Core.CmdText("ezTalent", Localized(c.assumptions))
    if assume then lines[#lines + 1] = L.ROTATION_COMPUTED_ASSUME:format(assume) end
    local values = Localized(c.values)
    if values then lines[#lines + 1] = L.ROTATION_COMPUTED_VALUES:format(values) end
    if not Rotation.AutoEligible(rotation) then
        -- Heiler-Grund und „vorläufig“ schließen sich nicht aus: eine vorläufige Heiler-Rotation zeigt beide, „Vorläufig –
        -- Grundwerte geschätzt“ zuletzt (Tooltip, Seite und Spickzettel). Die drei Hinweise stehen unverändert als L-Text
        -- in der Liste: der Spickzettel (RotationBook, Book.EasyLines) erkennt sie daran und lässt sie sichtbar.
        if c.healer then lines[#lines + 1] = L.ROTATION_COMPUTED_HEALER end
        if c.provisional then
            lines[#lines + 1] = L.ROTATION_COMPUTED_PROVISIONAL
        elseif not c.healer then
            lines[#lines + 1] = L.ROTATION_COMPUTED_MANUAL
        end
    end
    return lines
end

-- Text mit Zaubernamen statt Platzhaltern: „{980}“ wird der Name, den der Client für die Zauber-ID 980 kennt.
function Rotation.Expand(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("{(%d+)}", function(id)
        return ns.SpellName(tonumber(id)) or ("#" .. id)
    end))
end

-- Name einer Rotation in der Sprache des Spiels.
function Rotation.Name(rotation)
    if not rotation then return "" end
    return Localized(rotation.name) or rotation.key
end

-- Name ohne den Zusatz „(vorläufig berechnet)“ bzw. „(berechnet)“ – für Stellen, die das daneben nennen (Rotationen und
-- Talentvorlagen im Zauberbuch: stand bis zum 24.11.2026 doppelt, Bild des Nutzers).
function Rotation.WithoutComputed(name)
    if type(name) ~= "string" then return name end
    for _, word in ipairs({ L.ROTATION_BOOK_PROVISIONAL, L.ROTATION_BOOK_COMPUTED }) do
        local tail = " (" .. word .. ")"
        if #name > #tail and name:sub(-#tail) == tail then return name:sub(1, -#tail - 1) end
    end
    return name
end

-- Kurzer Name einer Rotation (nur bei berechneten gekürzt).
function Rotation.ShortName(rotation)
    local name = Rotation.Name(rotation)
    return Rotation.IsComputed(rotation) and Rotation.WithoutComputed(name) or name
end

-- Talentvorlagen (ezTalent) zu einer Rotation, n:m: Die Schlüssel kommen aus ezCores Zuordnung (Core.RotationBuilds, die
-- eine Stelle), Namen und Aufteilung aus ezTalent. Eine eigene Rotation gehört zu den Vorlagen ihrer Vorlage.
-- → { { key, name, split, tree, computed, provisional, purpose } … } (erste = Vorgabe), Grund (Text, wenn die Liste leer ist)
function Rotation.Builds(rotation)
    local own = Rotation.IsOwn(rotation)
    local key
    if own then key = rotation.own.from elseif rotation then key = rotation.key end
    local class = Rotation.ClassOf(rotation) or ns.playerClass
    local keys = key and Core.RotationBuilds.Builds(class, key) or {}
    if #keys == 0 then
        return {}, key and Core.RotationBuilds.Why(class, key) or (own and L.ROTATION_BUILDS_OWN) or L.ROTATION_BUILDS_NONE
    end
    local talent = Core.API("ezTalent")
    if not (type(talent) == "table" and type(talent.Builds) == "function") then return {}, L.ROTATION_BUILDS_MODULE end
    local ok, list = pcall(talent.Builds, keys, class)
    if not ok then
        ns.Error(list, "ezTalent.Builds")
        list = nil
    end
    if type(list) ~= "table" or #list == 0 then return {}, L.ROTATION_BUILDS_UNREAD end
    return list
end

-- Eine Talentvorlage in ezTalent zeigen (Talentfenster, Vorschau – gesetzt wird nichts). → true, wenn sie zu sehen ist
function Rotation.ShowBuild(key)
    local talent = Core.API("ezTalent")
    if not (type(talent) == "table" and type(talent.ShowBuild) == "function") then
        ns.Print(L.ROTATION_BUILDS_MODULE)
        return false
    end
    local ok, shown = pcall(talent.ShowBuild, key)
    if not ok then
        ns.Error(shown, "ezTalent.ShowBuild")
        return false
    end
    return shown == true
end

-- Hinweis einer Rotation (Widersprüche der Quellen, Leveln) in der Sprache des Spiels, sonst nil.
function Rotation.Note(rotation)
    return Rotation.Expand(Localized(rotation and rotation.note))
end

-- Erklärung in Sätzen, wie die Rotation funktioniert, in der Sprache des Spiels; nil, wenn sie keine hat.
function Rotation.How(rotation)
    return Rotation.Expand(Localized(rotation and rotation.how))
end

-- Text eines Schritts („wann ist er dran“) in der Sprache des Spiels.
function Rotation.StepText(step)
    return Rotation.Expand(Localized(step and step.text)) or ""
end

-- Annahme eines Schritts (Feld guess, Leitlinie 11: jede Angabe nennt ihre Quelle – eine geschätzte Schwelle sagt, dass
-- sie geschätzt ist): der Satz in der Sprache des Clients oder nil.
function Rotation.StepGuess(step)
    local text = Rotation.Expand(Localized(step and step.guess))
    if type(text) ~= "string" or text == "" then return nil end
    return text
end

function Rotation.PlayerRace()
    local _, race = UnitRace("player")
    race = ns.Plain(race)
    return RACE_ALIAS[race] or race
end

-- Schritte einer Rotation in der Reihenfolge der Vorlage, die Volksfähigkeiten des Spielers oben eingereiht
-- (Kochendes Blut, Berserker …).
function Rotation.Template(rotation, race, class)
    local steps = {}
    race, class = race or Rotation.PlayerRace(), class or ns.playerClass
    for _, racial in ipairs((ns.ROTATIONS or {}).RACIAL or {}) do
        if racial.race == race and (not racial.class or racial.class == class) then
            steps[#steps + 1] = racial
        end
    end
    for _, step in ipairs(rotation and rotation.steps or {}) do steps[#steps + 1] = step end
    return steps
end

-- Dieselben Schritte in der wirksamen Reihenfolge (Anpassungen dieses Charakters, RotationEdit.lua);
-- ausgeschaltete Schritte bleiben in der Liste.
function Rotation.Steps(rotation, race, class)
    local template = Rotation.Template(rotation, race, class)
    if Rotation.ApplyOrder then return Rotation.ApplyOrder(rotation, template) end
    return template
end

---------------------------------------------------------------------------
-- Arten und Schlüssel
---------------------------------------------------------------------------

-- Altschritt (ohne kind) mit when = "buff" auf einem Klassen-Buff, der lange hält: der Buff-Schlüssel, sonst nil.
local function LegacyLongKey(step)
    if step.kind ~= nil or step.when ~= "buff" or step.aura or step.buff then return nil end
    local key = Spells.BuffKey(step.id)
    if key and Spells.BuffField(key, "class") and Spells.IsLongBuff(step.id) then return key end
    return nil
end

function Rotation.KindOf(step)
    if step.kind then return step.kind end
    if LegacyLongKey(step) then return "longbuff" end
    if step.when == "aoe" then return "aoe" end
    if step.when == "filler" then return "filler" end
    return "priority"
end

function Rotation.IsLegacy(step)
    return step.kind == nil and LegacyLongKey(step) == nil
end

function Rotation.SectionOf(step)
    return Rotation.KINDS[Rotation.KindOf(step)] or "combat"
end

-- Name eines Schritts für Anpassungen und Zustand: das Feld key, sonst Art und Zauber-ID.
function Rotation.StepKey(step)
    return step.key or ns.RotationData.DefaultKey(step)
end

-- Wahlgruppe und eigener Buff-Schlüssel eines Schritts, der für einen Buff aus ezCores Buff-Wissen steht:
-- Feld buff (Schlüssel oder Gruppe), bei Altschritten der abgeleitete Dauer-Buff. Sonst nil.
local function BuffOf(step)
    local value = step.buff
    if value == nil then value = LegacyLongKey(step) end
    if value == nil then return nil end
    if Spells.IsBuff(value) then return Spells.BuffField(value, "kind") or value, value end
    return value, nil
end
Rotation.BuffOf = BuffOf

-- Gemerkte Wahl einer Wahlgruppe (Segen, Rüstung): nennt der Schritt einen bestimmten Buff (own), dieser; sonst die
-- gemerkte Wahl aus ezBuff, damit beide Module dieselbe Wahl vorschlagen und das Wirken des Vorschlags dort nichts
-- löscht. ezBuff führt die Wahl (eine Stelle) und bietet sie seit Welle 2b über ezCore.API("ezBuff").Preferred(gruppe)
-- an → Buff-Schlüssel oder nil; gelesen wird defensiv (pcall, IsSecret, nur bekannte Schlüssel). Ohne ezBuff: nil.
-- ListPrefer ist nur noch der Rückfall für eine ältere ezBuff-Fassung ohne Preferred: Ist ezBuff dort für die Gruppe
-- zuständig (Watches), gilt der Zauber, den ezBuffs Liste (Missing) für diese Gruppe nennt – so zeigen Symbolplatz
-- und Reiter denselben Buff. Liegt schon ein Buff der Gruppe, nennt die Liste nichts; dann bleibt ChooseBuff ohne
-- Vorliebe. Der Rückfall bleibt bis zur ersten Veröffentlichung und entfällt danach mit Beleg (Vollprüfung
-- 14.11.2026, W-30 und Frage 20 – Empfehlung umgesetzt, Antwort offen).
local function ListPrefer(api, group)
    if type(api.Watches) ~= "function" or type(api.Missing) ~= "function" then return nil end
    local okWatch, watches = pcall(api.Watches, group)
    if not okWatch or Core.IsSecret(watches) or watches ~= true then return nil end
    local okList, list = pcall(api.Missing)
    if not okList or Core.IsSecret(list) or type(list) ~= "table" then return nil end
    for _, entry in ipairs(list) do
        if type(entry) == "table" and entry.kind == "self" and entry.key == group then
            local spell = entry.spell
            if Core.IsSecret(spell) or type(spell) ~= "number" then return nil end
            local key = Spells.BuffKey(spell)
            if key and Spells.IsBuff(key) and (Spells.BuffField(key, "kind") or key) == group then return key end
            return nil
        end
    end
    return nil
end

function Rotation.BuffPrefer(group, own)
    if own ~= nil then return own end
    if Core.IsSecret(group) or type(group) ~= "string" then return nil end
    local api = Core.API and Core.API("ezBuff")
    if type(api) ~= "table" then return nil end
    if type(api.Preferred) ~= "function" then return ListPrefer(api, group) end
    local ok, key = pcall(api.Preferred, group)
    if not ok or Core.IsSecret(key) or type(key) ~= "string" or not Spells.IsBuff(key) then return nil end
    return key
end

-- Ist der Zauber gelernt? (Zauber-Wissen von ezCore; Volksfähigkeiten notfalls über die ID)
local function Known(step, name)
    if Spells.Known and Spells.Known(name) then return true end
    return Spells.IsKnown and Spells.IsKnown(step.id) and true or false
end
Rotation.Known = Known

-- Zauber eines Schritts: Zauber-ID (höchster gelernter Rang), Name, gelernt. Steht der Schritt für einen Buff aus
-- ezCores Buff-Wissen, entscheidet ezCore.Spells.ChooseBuff (Dämonenrüstung löst Dämonenhaut ab); nennt der
-- Schritt einen bestimmten Buff und ist der wählbar, gewinnt er; nennt er nur die Gruppe (buff = "blessing"), gewinnt
-- die gemerkte Wahl aus ezBuff (Rotation.BuffPrefer).
-- Noch kein Buff der Gruppe gelernt (nur ohne bestimmten Buff im Schritt): der Buff, der zuerst lernbar ist (kleinste
-- Stufe, nicht nur als gemerkte Wahl) – beim Paladin unter Stufe 4 Segen der Macht (ab 4) statt Könige (ab 20).
-- Gegenprüfung vom 15.11.2026: seit es nur noch einen Segen-Schritt gibt (id 20217), stand dort sonst Könige.
-- Ohne Stufen in den Daten bleibt fallback (die ID des Schritts).
local function FirstLearnable(group, fallback)
    local data = Spells.BuffGroup and Spells.BuffGroup(group, ns.playerClass)
    local best, bestLevel
    for _, key in ipairs(data and data.keys or {}) do
        local levels, spells = Spells.BuffField(key, "levels"), Spells.BuffField(key, "spells")
        local level = not Spells.BuffField(key, "manual") and type(levels) == "table" and levels[1]
        local spell = type(spells) == "table" and spells[1]
        if type(level) == "number" and spell and (not bestLevel or level < bestLevel) then best, bestLevel = spell, level end
    end
    return best or fallback
end

function Rotation.StepSpell(step)
    local group, own = BuffOf(step)
    if group then
        local _, spell = Spells.ChooseBuff(own or group, { prefer = Rotation.BuffPrefer(group, own), class = ns.playerClass })
        if spell then return spell, ns.SpellName(spell), true end
        local shown = own and step.id or FirstLearnable(group, step.id)
        return shown, ns.SpellName(shown), false
    end
    local name = ns.SpellName(step.id)
    local known = name ~= nil and Known(step, name)
    local id = known and Spells.Highest(step.id) or nil
    return id or step.id, name, known
end

---------------------------------------------------------------------------
-- Lesen: Ziel, Kraft, Auren
---------------------------------------------------------------------------

-- Gibt es die Einheit gerade (etwa "pettarget": hat der Begleiter ein Ziel)? wahr / falsch / unbekannt (gesperrt).
-- Ohne Ziel des Begleiters liegt dort keine Aura – ein Schritt auf "pettarget" ist dann nicht fällig statt „fehlt“.
-- Leitet an ns.UnitPresent (Core.lua) weiter – die eine Stelle für UnitExists in ezCombat (Leitlinie 6).
function Rotation.UnitPresent(unit)
    return ns.UnitPresent(unit)
end

-- Angreifbares, lebendes Ziel? Gesperrt oder unbekannt zählt als „nein“ (kein Vorschlag auf Verdacht).
local function TargetAttackable()
    if Rotation.UnitPresent("target") ~= true then return false end
    return ns.Bool(UnitCanAttack("player", "target"), false) and not ns.Bool(UnitIsDead("target"), false)
end
Rotation.TargetAttackable = TargetAttackable

local function PowerID(name)
    local enum = Enum and Enum.PowerType
    return (enum and enum[name]) or POWER_ID[name]
end

-- Kraft als Zahl; gesperrt = unbekannt (nil), vermerkt für /ezk status (ns.NoteSecret("power"), Zeile in Ticks.lua).
-- Die Bedingung gilt dann als unbekannt, der Schritt wird übersprungen und genannt – nie geraten.
local function Power(name)
    local value = UnitPower("player", PowerID(name))
    if ns.IsSecret(value) then
        ns.NoteSecret("power")
        return nil
    end
    return ns.Num(value)
end
Rotation.Power = Power

local function ManaPercent()
    local id = PowerID("Mana")
    local value, maximum = UnitPower("player", id), UnitPowerMax("player", id)
    if ns.IsSecret(value) or ns.IsSecret(maximum) then
        ns.NoteSecret("power")
        return nil
    end
    value, maximum = ns.Num(value), ns.Num(maximum)
    if not (value and maximum) or maximum <= 0 then return nil end
    return value / maximum * 100
end
Rotation.ManaPercent = ManaPercent

-- Kraft ohne Zahl (Paket ezcombat/rotation-recherche, 20.11.2026; Auftrag des Nutzers, wörtlich: „der rotations-modul
-- berücksichtigt nicht logisch energie, combopunkte, mana, wut, bedrohung und co oder? da muss eine saubere und
-- vollständige logik her“). Ist die Zahl gesperrt (im Kampf auf Forever Mana, Wut und Energie), entscheidet die Spanne
-- aus Blizzards Nutzbarkeit der gelernten Zauber (ezCores Spells.PowerBounds: nutzbar mit k Kosten → mindestens k;
-- „zu wenig Kraft“ bei k → weniger als k). Was die Spanne nicht entscheidet, bleibt unbekannt (überspringen und
-- nennen, nie raten). Je Bewertung einmal je Kraftart gelesen (ctx.powerBounds). Zuletzt so entschieden:
-- Rotation.lastPowerProbe = { power, by, when } für /ezk status (Quelle nennen, Leitlinie 11).
local function Bounds(name, ctx)
    local id = PowerID(name)
    if id == nil then return nil end
    local memo = ctx and ctx.powerBounds
    if ctx and not memo then
        memo = {}
        ctx.powerBounds = memo
    end
    local read = memo and memo[id]
    if not read then
        local lo, hi, loBy, hiBy = Spells.PowerBounds(id)
        read = { lo = lo, hi = hi, loBy = loBy, hiBy = hiBy }
        if memo then memo[id] = read end
    end
    return read
end

-- Bereich { min, max } (absolut) für die Kraftart name über die Spanne; scale: Faktor für Prozent (Mana).
Rotation.Bounds = Bounds      -- auch für Werte abwägen (RotationValue.lua): eine Spanne je Bewertung

local function BoundsRange(name, range, ctx, scale)
    if type(range) ~= "table" or not (range.min or range.max) then return nil end
    local read = Bounds(name, ctx)
    if not read then return nil end
    scale = scale or 1
    local min = range.min and range.min * scale or nil
    local max = range.max and range.max * scale or nil
    if min and min <= 0 then min = nil end          -- „ab 0“ ist immer erfüllt, belegt nichts
    if not (min or max) then return true end
    local result = Spells.PowerInRange(read.lo, read.hi, min, max)
    if result ~= nil then
        -- Beleg: welcher Zauber die entscheidende Grenze lieferte (bei wahr mit beiden Grenzen beide)
        local by
        if result == false then
            if min and read.hi and read.hi <= min then by = read.hiBy else by = read.loBy end
        elseif min and max then
            by = read.loBy and read.hiBy and (read.loBy .. ", " .. read.hiBy) or read.loBy or read.hiBy
        elseif min then
            by = read.loBy
        else
            by = read.hiBy
        end
        if by then Rotation.lastPowerProbe = { power = name, by = by, when = GetTime() } end
    end
    return result
end

-- Kraft im Bereich { min, max }? Zuerst die Zahl (außerhalb des Kampfes offen), sonst die Spanne. true/false/nil.
function Rotation.PowerRange(name, range, ctx)
    local value = Power(name)
    if value ~= nil then
        if type(range) ~= "table" then return true end
        if range.min and value < range.min then return false end
        if range.max and value > range.max then return false end
        return true
    end
    return BoundsRange(name, range, ctx)
end

-- Mana in Prozent im Bereich { min, max }? Zuerst die Zahl, sonst die Spanne – das Maximum ist beim Spieler offen
-- (Forever-Quelle: UnitPowerMax gesperrt nur, wenn die Einheit nicht spielergesteuert ist); gesperrt: unbekannt.
function Rotation.ManaRange(range, ctx)
    local percent = ManaPercent()
    if percent ~= nil then
        if type(range) ~= "table" then return true end
        if range.min and percent < range.min then return false end
        if range.max and percent > range.max then return false end
        return true
    end
    local maximum = UnitPowerMax and UnitPowerMax("player", PowerID("Mana"))
    if ns.IsSecret(maximum) then return nil end
    maximum = ns.Num(maximum)
    if not maximum or maximum <= 0 then return nil end
    if type(range) == "table" and range.max and range.max >= 100 and not range.min then return true end  -- nie über 100 %
    if type(range) == "table" and range.max and range.max >= 100 then range = { min = range.min } end
    return BoundsRange("Mana", range, ctx, maximum / 100)
end

-- Ist das Mana gesperrt (im Kampf oft)? Nur dann gilt der Weg ohne Zahl (Rotation.OnlyManaMissing).
local function ManaLocked()
    local id = PowerID("Mana")
    return ns.IsSecret(UnitPower("player", id)) or ns.IsSecret(UnitPowerMax("player", id))
end
Rotation.ManaLocked = ManaLocked

-- Fehlt diesem Zauber allein das Mana? Der Weg ohne Zahl, wenn die Kraft gesperrt ist: wahr nur, wenn das Spiel es
-- offen sagt (C_Spell.IsSpellUsable: nicht nutzbar, nur die Kraft fehlt) und die Hauptkraft des Spielers Mana ist
-- (eine Katze ohne Energie zählt nicht). Gesperrt oder unklar: falsch – dann wird nichts daraus geschlossen.
function Rotation.OnlyManaMissing(name)
    if not name then return false end
    local powerType = UnitPowerType and UnitPowerType("player")
    if ns.IsSecret(powerType) or ns.Num(powerType) ~= PowerID("Mana") then return false end
    local usable, noPower = ns.SpellUsable(name)
    return usable == false and noPower == true
end

-- Hängt ein Schritt, der Mana zurückholt (when = "lowmana" oder need.mana nur mit max), allein am gesperrten Mana?
-- result: Ergebnis der Bedingung; needed, needKey, unknowns: aus Rotation.NeedDue; usable: der Zauber selbst ist
-- jetzt nutzbar (nie etwas Unwirkbares vorschlagen). Dann meldet StepDue "secret:mana", und Evaluate schlägt den
-- Schritt vor, wenn dem nächsten fälligen Schritt allein das Mana fehlt.
local function WaitsOnLockedMana(step, result, needed, needKey, unknowns, usable)
    if usable ~= true or not ManaLocked() then return false end
    if step.when == "lowmana" then return result == nil and needed == true end
    local mana = type(step.need) == "table" and step.need.mana
    return result == true and needed == nil and needKey == "mana" and unknowns == 1
        and type(mana) == "table" and mana.max ~= nil and mana.min == nil
end

-- Combo-Punkte; gesperrt = unbekannt (nil), vermerkt für /ezk status (ns.NoteSecret("combo"), Zeile in Hints.lua).
local function ComboPoints()
    local points = GetComboPoints and GetComboPoints("player", "target")
    if ns.IsSecret(points) then
        ns.NoteSecret("combo")
        return nil
    end
    return ns.Num(points) or 0
end
Rotation.ComboPoints = ComboPoints

-- Kann dieser eigene Zauber einen Buff auf den Spieler legen? (Nur dann bekommt eine gesperrte, neu erschienene
-- Aura des Spielers seinen Namen – ein Proc direkt nach einem DoT bliebe sonst nicht „unbekannt“.)
local function OwnBuffCheck(ctx)
    if ctx.ownBuff then return ctx.ownBuff end
    local names
    ctx.ownBuff = function(name)
        if Spells.BuffKey(name) then return true end
        if not ctx.steps then return true end
        if not names then
            names = {}
            for _, step in ipairs(ctx.steps) do
                if step.when == "buff" then
                    local _, stepName = Rotation.StepSpell(step)
                    if stepName then names[stepName] = true end
                end
            end
        end
        return names[name] == true
    end
    return ctx.ownBuff
end

-- Auren einer Einheit, je Bewertung einmal gelesen (ezCore.Auras.Scan mit Platzhaltern für gesperrte Auren; Namen
-- gesperrter kommen vom eigenen Zauber, ns.Auras.Remember). filter: "HELPFUL" | "HARMFUL"; mine: nur eigene.
-- Rückgabe: Liste, Zahl der Auren, über die nichts bekannt ist (gesperrt ohne Namen, unlesbar – dann heißt „nicht
-- in der Liste“ nicht „liegt nicht“), Eintrag { list, unknown, secret, unread, ids }.
-- Gesperrte Auren, deren Name nur aus dem zuletzt gedrückten Knopf erschlossen ist (aura.guessed, Auras.Remember),
-- gelten ohne „Mitzählen“ als unbekannt: Name und Zauber fallen in dieser (eigenen) Liste weg – sonst fände FindAura
-- den DoT über den erschlossenen Namen („nicht fällig“), und mit unknown == 0 hieße ein anderer DoT „fehlt“ (Fund 1
-- des code-reviewers vor dem Merge, 17.11.2026). DoT-Reihe und Buff-Warnung lesen eigene Listen und behalten ihn.
local function DropGuessed(list)
    if State.Estimating() then return end
    for _, aura in ipairs(list) do
        if aura.secret and aura.guessed then aura.name, aura.spellId, aura.guessed = nil, nil, nil end
    end
end

function Rotation.UnitAuras(ctx, unit, filter, mine)
    ctx.auras = ctx.auras or {}
    local full = mine and (filter .. "|PLAYER") or filter
    local key = unit .. "|" .. full
    local entry = ctx.auras[key]
    if entry then return entry.list, entry.unknown, entry end
    local list, secret, ids, unread = Core.Auras.Scan(unit, full, { keepSecret = true })
    secret, unread = ns.Num(secret) or 0, ns.Num(unread) or 0
    if unit == "player" then
        if ids and full == "HELPFUL" then ns.Auras.Learn(ids, "player", OwnBuffCheck(ctx)) end
        ns.Auras.Remember(list, "player")
        DropGuessed(list)
        if filter == "HELPFUL" then State.NoteAuras(list) end
    elseif unit == "target" then
        -- Neue Instanzen dem eigenen Zauber zuordnen: Das macht sonst die DoT-Reihe (Auras.Collect); ist sie ganz
        -- abgeschaltet, liest nur die Rotation die Auren des Ziels.
        if ids and full == "HARMFUL|PLAYER"
            and not (ns.Enabled("dots") or ns.ShowAny("expiring")) then
            ns.Auras.Learn(ids)
        end
        ns.Auras.Remember(list)
        DropGuessed(list)
    end
    local unknown = unread
    for _, aura in ipairs(list) do
        if aura.secret and not aura.name then unknown = unknown + 1 end
    end
    -- Ohne Instanz-IDs sagt die Liste nichts über gesperrte Auren: dann zählt die Auskunft des Spiels.
    if not ids and Core.AurasLocked and Core.AurasLocked() == true then unknown = unknown + 1 end
    entry = { list = list, unknown = unknown, secret = secret, unread = unread, ids = ids }
    ctx.auras[key] = entry
    -- Vollständig offen gelesen: Das ist der Stand, von dem die Nachführung im Kampf ausgeht (State.OwnAura).
    -- "target"|"HARMFUL" (Schritte mit mine = false): Debuffs gleich welcher Quelle, eigene Karte (State.NoteAnyRead).
    if unknown == 0 and secret == 0 and not (Core.AurasLocked and Core.AurasLocked() == true) then
        if (unit == "player" and full == "HELPFUL") or (unit == "target" and full == "HARMFUL|PLAYER") then
            State.NoteOwnRead(unit, list)
        elseif unit == "target" and full == "HARMFUL" then
            State.NoteAnyRead(list)
        end
    end
    return list, unknown, entry
end

-- Sind die Buffs des Spielers vollständig lesbar? Nur dann heißt „nicht gefunden“ auch „fehlt“.
local function PlayerReadable(ctx)
    local _, _, entry = Rotation.UnitAuras(ctx, "player", "HELPFUL", false)
    return entry.secret == 0 and entry.unread == 0 and not (Core.AurasLocked and Core.AurasLocked() == true)
end

-- Aura in einer Liste: what = Zauber-ID, Buff-Schlüssel, Gruppe, Familie oder eine Liste davon. Zuerst offen über
-- Zauber-ID und alle Ränge, sonst über den Namen (ezCore.Spells.FindAura); danach gesperrte Auren, deren Namen
-- ezCombat vom eigenen Zauber kennt.
local function FindAura(list, what)
    if what == nil or type(list) ~= "table" then return nil end
    if type(what) == "table" then
        for _, one in ipairs(what) do
            local aura = FindAura(list, one)
            if aura then return aura end
        end
        return nil
    end
    local aura = Spells.FindAura(list, what)
    if aura then return aura end
    local ids, names
    for _, entry in ipairs(list) do
        if entry.secret and entry.name then
            ids = ids or Spells.AuraIDs(what) or {}
            if entry.spellId and ids[entry.spellId] then return entry end
            if not names then
                names = {}
                for id in pairs(ids) do
                    local name = ns.SpellName(id)
                    if name then names[name] = true end
                end
            end
            if names[entry.name] then return entry end
        end
    end
    return nil
end
Rotation.FindAura = FindAura

local function Enabled(step, ctx)
    if not Rotation.StepEnabled then return step.optional ~= true end
    return Rotation.StepEnabled(ctx.rotation, step)
end

-- Was sich ausschließt, ohne dass der Schritt es sagt (24.11.2026; Nutzer, wörtlich: „ezrotation muss auch
-- beachten/berücksichtigen dass manche fäihgkeiten sich auschließena“) – aus ezCores Familien (Spells.FAMILIES, geprüft
-- gegen die Beschreibungen des Clients) bzw. Wahlgruppen:
--   dot   auf dem Ziel (Flüche, Omen, Stiche): immer. Liegt schon ein anderer eigener der Gruppe, ist der Schritt nicht dran –
--         vorher überschrieben sich Omen der Pein und Omen der Verdammnis in den berechneten Rotationen im Wechsel.
--   buff  auf dir (Siegel, Aspekte, Rüstungen …): nur zwischen selbst hinzugefügten Schritten (added) derselben Liste; die
--         Vorlagen lösen es mit group und need, und ein einzelner Schritt soll weiter an „fehlt“ erinnern.
-- Schritte mit eigener group gehen vor. → Gruppe | nil, true = nur die Schritte der Liste zählen
local autoGroups = setmetatable({}, { __mode = "k" })
local function AutoGroup(step)
    local id = type(step.aura) == "number" and step.aura or step.id
    if type(id) ~= "number" or step.race then return nil end
    local dot = step.when == "dot" and step.mine ~= false and step.unit == nil
    local buff = step.when == "buff" and step.added == true and step.buff == nil and step.unit == nil
    if not (dot or buff) then return nil end
    local memo = autoGroups[step]
    if memo and memo.id == id and memo.class == ns.playerClass and memo.dot == dot then return memo.group or nil, buff end
    local group
    local family = Spells.FamilyOf(id)
    local class, unit = Spells.FamilyInfo(family)
    if class and class == ns.playerClass and (dot and unit == "target" or buff and unit ~= "target") then
        group = family
    elseif buff and not family then
        local key = Spells.BuffKey(id)
        local choice = key and Spells.BuffGroup(key, ns.playerClass)
        group = choice and choice.kind and choice.id or nil
    end
    -- Nennt der Client den Namen noch nicht, zählt das Ergebnis nicht (ein höherer Rang steht nur über den Namen fest)
    if group or Spells.Name(id) then autoGroups[step] = { id = id, class = ns.playerClass, dot = dot, group = group or false } end
    return group, buff
end

-- → Gruppe | nil, nur die Schritte der Liste, aus dem Client-Wissen (nicht im Schritt genannt)
function Rotation.GroupOf(step)
    if step.group ~= nil then return step.group or nil, false, false end
    local group, listOnly = AutoGroup(step)
    return group, listOnly, group ~= nil
end
local GroupOf = Rotation.GroupOf

-- Namen dessen, was sich mit diesem Schritt ausschließt (gelernt, ohne ihn selbst): die Familie bzw. Wahlgruppe aus ezCore,
-- sonst die Schritte derselben Rotation mit derselben Gruppe. → Liste (leer: nichts)
function Rotation.GroupNames(step, rotation)
    local names, seen = {}, {}
    local group, listOnly = GroupOf(step)
    if not group then return names end
    local _, own = Rotation.StepSpell(step)
    if own then seen[own] = true end
    local function Add(id)
        local name = type(id) == "number" and ns.SpellName(id) or nil
        if name and not seen[name] and (Spells.Known(id) or Spells.IsKnown(id) == true) then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    if not listOnly then
        local ids, family = Spells.Family(group)
        local choice = Spells.BuffGroup(group, ns.playerClass)
        if choice then
            for _, key in ipairs(choice.keys) do Add((Spells.BuffField(key, "spells") or {})[1]) end
        elseif ids and family.class == ns.playerClass then
            for _, id in ipairs(ids) do Add(id) end
        end
    end
    for _, other in ipairs(type(rotation) == "table" and rotation.steps or {}) do
        if other ~= step and GroupOf(other) == group then Add(other.id) end
    end
    return names
end

-- Sich ausschließende Auren (group bzw. GroupOf): liegt eine andere der Gruppe? Zuerst die Wahlgruppe aus ezCores
-- Buff-Wissen (kind), dann die Familie (Spells.FAMILIES, nur die der eigenen Klasse), sonst wie bisher die Schritte derselben
-- Liste. Rückgabe: Aura oder nil; zweiter Wert true, wenn es unbekannt ist (Gestaltleiste gesperrt).
local function GroupAura(step, list, ctx)
    local group, listOnly = GroupOf(step)
    if not group then return nil end
    if not listOnly and Spells.BuffGroup(group, ns.playerClass) then return FindAura(list, group) end
    local class, _, form = Spells.FamilyInfo(group)
    if not listOnly and class and class == ns.playerClass then
        if not form then return FindAura(list, group) end
        local unknown = false
        for _, id in ipairs((Spells.Family(group))) do
            local active = Spells.FormActive(id)
            if active == true then return { form = true } end
            if active == nil then unknown = true end
        end
        return nil, unknown
    end
    for _, other in ipairs(ctx.steps or {}) do
        if other ~= step and GroupOf(other) == group then
            local aura = FindAura(list, other.aura or other.id)
            if aura then return aura end
            if listOnly and form and Spells.FormActive(other.id) == true then return { form = true } end
        end
    end
    return nil
end

-- Restzeit einer Aura in Sekunden: offen gelesen; dauerhaft = unendlich. Gesperrt: die Ersatzuhr (eigener Zauber
-- plus die vom Client gelernte Dauer, nur mit „Mitzählen“ – der Vorschlag trägt dann „gezählt“), sonst nil.
local function Remaining(aura, name, auraID, unit, ctx)
    if aura.form then return math.huge end
    if not aura.secret then
        if not aura.expires then return math.huge end
        return aura.expires - ctx.now
    end
    if not State.Estimating() then return nil end
    local at = State.CastAt(name, unit)
    -- Dauer vom Client gelernt, sonst aus der Zauberbeschreibung (wie Tracked; Spieltest 23.11.2026: ohne gelernte Dauer
    -- blieb die Restzeit unbekannt und der Vorlauf aus)
    local seconds = Spells.AuraSeconds(auraID) or (type(auraID) == "number" and State.DescriptionSeconds(auraID)) or nil
    if not (at and seconds) then return nil end
    ctx.counted = true
    return seconds - (ctx.now - at), seconds
end
Rotation.Remaining = Remaining

-- Vorlauf einer Erneuerung (Spieltest 23.11.2026, Wunsch des Nutzers, wörtlich: „ezcombat: sollte fähigkeiten wie dots
-- immer etwas eher ansagen --> also wirkungszeit und cool down berücksichtigen --> dot/hot läuft in 3s aus -->
-- fähigkeit cooldown in 0.5s vor, fähigkeit braucht 1,7s castzeit --> anhand dessen berechnen wann fähigkeit gezeigt
-- wird im mittigen symbol --> derzeit erst mit ablauf des hots/dots was theoretisch zu spät ist“): Sekunden vor dem
-- Ablauf, ab denen der Schritt dran ist, damit die neue Wirkung genau beim Ablauf liegt =
--   Zauberzeit (mit Tempo, Blizzards GetSpellInfo; gesperrt: die letzte offene Lesung), mindestens eine globale
--     Abklingzeit (Spells.GCD_MAX, Rotation.LeadCast – auch ein Sofortzauber kommt so sichtbar früher)
--   + was davor noch läuft, das Längste aus: der Abklingzeit des Zaubers (offen gelesen oder mitgezählt wie bei der
--     Vorwarnung), dem Rest der globalen Abklingzeit (offen gelesen; im Kampf gesperrt – mit „Mitzählen“ dann der
--     eigene letzte Zauber plus Spells.GCD_MAX, wie ns.SharedOnCooldown; der Vorschlag trägt „gezählt“) und dem Rest
--     des Zaubers, den du gerade wirkst (UnitCastingInfo bzw. UnitChannelInfo, offen gelesen)
--   + Reserve für die Verzögerung zum Server (Rotation.Reserve: Latenz aus GetNetStats, sonst REFRESH_RESERVE)
--   + ein Takt der Bewertung (CHECK_EVERY: ohne Ereignis wird nur so oft neu bewertet, sonst rutschte ein kurzes
--     Fenster durch).
-- Höchstens Blizzards Pandemie-Fenster (ezCores Core.AuraRows.PANDEMIC × Dauer, wenn die Dauer bekannt ist): so früh neu
-- gesetzt geht nichts verloren. Steht die Abklingzeit noch, ist der Schritt „bis auf die Abklingzeit dran“ – die
-- Vorwarnung zeigt ihn dann mit „bereit in …“ (wie bei jedem Schritt mit Abklingzeit). Reserve und Wartezeit liest
-- eine Bewertung nur einmal (ctx.leadBase).
Rotation.REFRESH_RESERVE = 0.2      -- Sekunden, wenn die Latenz nicht offen zu lesen ist
Rotation.RESERVE_LIMITS = { 0.05, 0.5 }
Rotation.CHECK_EVERY = CHECK_EVERY

-- Pandemie-Anteil: eine Quelle in ezCore (Core.AuraRows.PANDEMIC, wie ezCombats Auras.WarnAt)
function Rotation.Pandemic()
    return ns.Num(Core.AuraRows and Core.AuraRows.PANDEMIC) or 0.3
end

function Rotation.Reserve()
    local fn = rawget(_G, "GetNetStats")
    if type(fn) == "function" then
        local ok, _, _, home, world = pcall(fn)
        local ms = ok and (ns.Num(world) or ns.Num(home)) or nil
        if ms and ms > 0 then
            local limits = Rotation.RESERVE_LIMITS
            return math.max(limits[1], math.min(limits[2], ms / 1000))
        end
    end
    return Rotation.REFRESH_RESERVE
end

-- Rest des Zaubers, den du gerade wirkst oder kanalisierst (offen gelesen) → Sekunden oder 0
local function CastingLeft(now)
    for _, name in ipairs({ "UnitCastingInfo", "UnitChannelInfo" }) do
        local fn = rawget(_G, name)
        if type(fn) == "function" then
            local ok, _, _, _, _, endMs = pcall(fn, "player")
            endMs = ok and ns.Num(endMs) or nil
            if endMs and endMs / 1000 > now then return endMs / 1000 - now end
        end
    end
    return 0
end

-- Wartezeit ohne die Abklingzeit des Zaubers (globale Abklingzeit, laufender Zauber) und Reserve; einmal je Bewertung
local function LeadBase(now, ctx)
    if ctx and ctx.leadBase then return ctx.leadBase end
    local gcd, counted = Rotation.GcdLeft(now), nil
    if not gcd and ns.CooldownTimes(Spells.GCD_SPELL) == nil and State.Estimating() then
        -- globale Abklingzeit gesperrt: mit „Mitzählen“ aus dem eigenen letzten Zauber erschlossen
        local at = State.LastCastAt()
        if type(at) == "number" and now >= at and now - at < Spells.GCD_MAX then
            gcd, counted = Spells.GCD_MAX - (now - at), true
        end
    end
    local base = { wait = math.max(gcd or 0, CastingLeft(now)), counted = counted,
        reserve = Rotation.Reserve() + CHECK_EVERY }
    if ctx then ctx.leadBase = base end
    return base
end

-- Zauberzeit in Sekunden; gesperrt gilt die letzte offene Lesung (Core.Spells.CastTime; Spieltest 23.11.2026:
-- Feuerbrand kam mit „Mitzählen“ nicht sichtbar früher)
local primedAt = -math.huge     -- letztes Vorablesen ohne Ziel (Rotation.Evaluate)
function Rotation.CastSeconds(name) return (ns.CastTime(name)) end

-- Vor dem Kampf vorab lesen, was im Kampf gesperrt ist (Spieltest 23.11.2026, nach dem Neustart „12-14, nein“):
-- Zauberzeiten der Schritte mit Erneuern (Vorlauf) und die Werte der Füller und des Zauberstabs (Werte abwägen –
-- sonst rechnete ezCombat erst, wenn vor dem Kampf schon ein Füller vorn stand, und blieb im Kampf ohne Werte still).
Rotation.PRIME_EVERY = 2
function Rotation.Prime(steps)
    for _, step in ipairs(steps or {}) do
        if step.refresh ~= nil and (step.when == "dot" or step.when == "buff") then
            local _, name = Rotation.StepSpell(step)
            if name then Rotation.CastSeconds(name) end
        end
    end
    if ns.RotationValue and ns.RotationValue.Prime then ns.RotationValue.Prime(steps) end
end

-- Sofortzauber belegen mindestens eine globale Abklingzeit (Spieltest 23.11.2026, Nutzer zum Vorlauf: „ja aber nur bei
-- diesem (sichtbar)“ – nur Feuerbrand mit Zauberzeit kam sichtbar früher; Verderbnis und Omen der Pein, beide sofort,
-- erst 0,45 s vor dem Ablauf): Der Vorlauf rechnet mit der Zauberzeit, mindestens aber Spells.GCD_MAX. Sonst begänne
-- davor noch ein anderer Zauber, der den DoT um eine globale Abklingzeit hinter den Ablauf schiebt.
function Rotation.LeadCast(cast)
    return math.max(ns.Num(cast) or 0, ns.Num(Spells.GCD_MAX) or 1.5)
end

-- → Vorlauf in Sekunden, Zauberzeit (wie gelesen, ohne Untergrenze), Wartezeit (das Längste aus Abklingzeit, globaler
-- Abklingzeit und laufendem Zauber), Reserve (Latenz plus ein Takt), gezählt (true, wenn die globale Abklingzeit
-- mitgezählt ist)
function Rotation.RefreshLead(step, name, total, ctx)
    local cast = Rotation.CastSeconds(name)
    local now = ctx and ctx.now or GetTime()
    local base = LeadBase(now, ctx)
    local wait = base.wait
    local spell = Rotation.StepSpell(step)
    if spell then
        local reason, coolLeft = Rotation.CooldownReason(spell, name, ctx)
        if (reason == "cooldown" or reason == "cooldown:shared") and ns.Num(coolLeft) and coolLeft > wait then
            wait = coolLeft
        end
    end
    local lead = Rotation.LeadCast(cast) + wait + base.reserve
    total = ns.Num(total)
    if total and total > 0 and total ~= math.huge then lead = math.min(lead, total * Rotation.Pandemic()) end
    return lead, cast, wait, base.reserve, base.counted
end

-- Muss eine liegende Aura erneuert werden? refresh: "missing" (erst zum Ablauf: Rest höchstens der Vorlauf),
-- "cast" (Rest höchstens die Zauberzeit bzw. der Vorlauf), Zahl (Rest höchstens so viele Sekunden bzw. der
-- Vorlauf), sonst die bisherige Regel (warn: Warnzeit plus Zauberzeit, Pandemie). Ist der Rest unbekannt: mit refresh
-- nicht dran (wie bisher), ohne (Altschritt) unbekannt.
-- Dieselbe Regel mit einer schon bekannten Restzeit (left nil = unbekannt), auch für nachgeführte Auren.
local function DueAt(step, aura, name, left, seconds, warn, ctx)
    local refresh = step.refresh
    if left == nil then
        if refresh ~= nil then return false end
        return nil
    end
    if left == math.huge then return false end
    if refresh == nil then return warn(aura, left, seconds) end
    if left <= 0 then return true end
    local lead, cast, _, _, counted = Rotation.RefreshLead(step, name, seconds or (aura and aura.duration), ctx)
    local threshold = lead          -- "missing" (und Unbekanntes wie "missing")
    if refresh == "cast" then
        threshold = math.max(cast, lead)
    elseif type(refresh) == "number" then
        threshold = math.max(refresh, lead)
    end
    local due = left <= threshold
    if due and counted and ctx then ctx.counted = true end     -- dran dank der mitgezählten globalen Abklingzeit
    -- Liegt die Wirkung noch und ist schon dran: auslaufend (die Mitte zeigt es, Rotation.Evaluate → expiring)
    if due and ctx then ctx.refreshLeft, ctx.refreshTotal = left, ns.Num(seconds or (aura and aura.duration)) end
    return due
end

-- Zauber-ID für die Dauer einer eigenen Aura: step.aura, sonst der höchste gelernte Rang (Rotation.StepSpell). Rang 1
-- hat oft eine kürzere Dauer – sonst kam die gezählte Restzeit zu früh (Zweitmeinung zum Spieltest vom 23.11.2026).
local function DurationID(step)
    if step.aura then return step.aura end
    return (Rotation.StepSpell(step)) or step.id
end
Rotation.DurationID = DurationID

local function RefreshDue(step, aura, name, unit, ctx, warn)
    local left, seconds = Remaining(aura, name, DurationID(step), unit, ctx)
    return DueAt(step, aura, name, left, seconds, warn, ctx)
end

-- Nachführung, wenn das Spiel die Auren sperrt (Spieltest 15.11.2026, Befund 1; State.OwnAura): Namen, unter denen
-- eine eigene Aura liegt – der Zauber des Schritts und jede Aura von what (Zauber-ID, Buff-Schlüssel, Gruppe,
-- Familie oder Liste davon, alle Ränge über ezCore.Spells.AuraIDs).
local function TrackNames(what, name, names, seen)
    names, seen = names or {}, seen or {}
    local function Add(one)
        if type(one) == "string" and one ~= "" and not seen[one] then
            seen[one] = true
            names[#names + 1] = one
        end
    end
    Add(name)
    local function Each(value)
        if type(value) == "table" then
            for _, one in ipairs(value) do Each(one) end
            return
        end
        if value == nil then return end
        if type(value) == "number" then Add(ns.SpellName(value)) end
        for id in pairs(Spells.AuraIDs(value) or {}) do Add(ns.SpellName(id)) end
    end
    Each(what)
    return names, seen
end
Rotation.TrackNames = TrackNames

-- Zustand einer eigenen Aura aus der Nachführung: "missing" | "running" | nil (unbekannt: nie gewirkt oder gewirkt mit
-- unbekannter Restzeit – beides nur durch Mitzählen zu erfahren, und „Mitzählen“ ist aus; Blizzards Regeln, Prüfung
-- 17.11.2026 – der Schritt wird übersprungen und genannt), Restzeit,
-- Gesamtdauer. Beruht das auf den eigenen Zaubern (nie gewirkt bzw. Zauber plus Dauer), trägt der Vorschlag
-- „gezählt“ (ctx.counted); ein Ablauf aus der letzten offenen Lesung ist gelesen. unit: "player" oder "target";
-- any: auch Debuffs anderer Quellen (mine = false). Die Dauer: vom Client gelernt, sonst aus der Zauberbeschreibung.
local function Tracked(unit, what, name, auraID, ctx, any)
    local seconds = Spells.AuraSeconds(auraID) or (type(auraID) == "number" and State.DescriptionSeconds(auraID)) or nil
    local state, left, total, _, source = State.OwnAura(unit == "player" and "player" or "target",
        TrackNames(what, name), seconds, ctx.now, any)
    if source == "uncounted" then return nil end
    if source == "cast" or source == "never" then ctx.counted = true end
    return state, left, total
end
Rotation.Tracked = Tracked

-- Lässt sich diese Aura nachführen? Nur, wenn ein Schritt der Rotation sie selbst setzt (Bedingung dot oder buff) –
-- ein Proc oder ein fremder Buff kommt ohne eigenen Zauber, „nie gewirkt“ hieße dort nichts.
function Rotation.Trackable(what, ctx)
    local wanted = {}
    for _, one in ipairs((TrackNames(what))) do wanted[one] = true end
    for _, step in ipairs(ctx and ctx.steps or {}) do
        if step.when == "dot" or step.when == "buff" then
            for _, one in ipairs((TrackNames(BuffOf(step) or step.aura or step.id, (select(2, Rotation.StepSpell(step)))))) do
                if wanted[one] then return true end
            end
        end
    end
    return false
end

-- Läuft (nachgeführt) eine andere Aura derselben Gruppe? Wahlgruppe bzw. Familie über ihren Schlüssel, sonst die
-- Schritte derselben Liste mit derselben group. → läuft (nil: unbekannt); true, wenn der jüngste andere die eigene Wirkung
-- ersetzt hat (sie zählt dann nicht mehr); Zeitpunkt des jüngsten anderen
local function GroupTracked(step, unit, ctx)
    local group, listOnly, auto = GroupOf(step)
    if not group then return false end
    local names, seen = {}, {}
    if not listOnly then names, seen = TrackNames(group) end
    for _, other in ipairs(ctx.steps or {}) do
        if other ~= step and GroupOf(other) == group then
            TrackNames(other.aura or other.id, (select(2, Rotation.StepSpell(other))), names, seen)
        end
    end
    local own = {}
    TrackNames(step.aura or step.id, (select(2, Rotation.StepSpell(step))), own)
    local ownSet = {}
    for _, one in ipairs(own) do ownSet[one] = true end
    local others = {}
    for _, one in ipairs(names) do
        if not ownSet[one] then others[#others + 1] = one end
    end
    if not others[1] then return false end
    -- nil: ohne „Mitzählen“ ist unbekannt, ob ein anderer der Gruppe liegt (nie gewirkt bzw. Restzeit nur gezählt)
    local state, _, _, _, source, when = State.OwnAura(unit, others, nil, ctx.now)
    -- Wer zuletzt kam, hat den anderen ersetzt (Review 24.11.2026: Verdammnis, dann von Hand Pein – die gezählte Verdammnis
    -- sperrte Pein bis zu ihrem Ende)
    local _, _, _, _, _, ownWhen = State.OwnAura(unit, own, nil, ctx.now)
    if when and ownWhen and ownWhen > when then return false end
    -- (eine Gruppe nur aus dem Client-Wissen sperrt erst, wenn es feststeht)
    if source == "uncounted" then
        if auto then return false end
        return nil
    end
    if state == "running" then return true, false, when end
    if when and ownWhen and when > ownWhen then
        if source == "cast" then ctx.counted = true end
        return false, true
    end
    return false
end

---------------------------------------------------------------------------
-- Bedingungen (when): true = dran, false = nicht dran, nil = unbekannt (gesperrte Werte – übersprungen und genannt)
---------------------------------------------------------------------------

local CONDITIONS = {}

function CONDITIONS.ready() return true end
function CONDITIONS.filler() return true end
function CONDITIONS.reactive(_, _, _, usable) return usable end

-- Eigener DoT/Debuff auf dem Ziel (unit = "pettarget": auf dem Ziel des Begleiters – hat er keins, nicht fällig;
-- mine = false: von jedem): fehlt oder läuft aus. Ohne refresh die Warnzeit der DoT-Reihe (mit 30-%-Regel).
-- group: liegt ein anderer der Gruppe (ein Omen je Ziel), ist der Schritt nicht dran.
-- Wirkung eines dot-Schritts, die liegt (aura) bzw. nachgeführt wird (aura nil): ist sie zu erneuern? nil: unbekannt.
local function DotDue(step, aura, name, unit, ctx)
    if aura then
        return RefreshDue(step, aura, name, unit, ctx, function(found, left, seconds)
            if not found.secret then return ns.Auras.IsExpiring(found, ctx.now) end
            return left > 0 and left <= ns.Auras.WarnAt({ name = name, duration = seconds })
        end)
    end
    local state, left, seconds = Tracked("target", step.aura or step.id, name, DurationID(step), ctx, step.mine == false)
    if state == nil then return nil end
    if state == "missing" then return true end
    if step.stacks then return nil end      -- liegt, Stapel unbekannt
    return DueAt(step, nil, name, left, seconds, function(_, rest, total)
        return rest > 0 and rest <= ns.Auras.WarnAt({ name = name, duration = total })
    end, ctx)
end

-- Vortritt in einer Gruppe (Review 24.11.2026): Liegt ein anderes Mitglied und läuft gerade aus, das ein späterer Schritt der
-- Liste jetzt erneuern würde, ist dieser höhere Schritt dran. Ohne das kam Omen der Verdammnis gegen einen Boss nie mehr,
-- wenn Pein zuerst lag – Pein erneuert sich immer vor ihrem Ablauf. aura: die liegende Aura; nil: nachgeführt (when: ihr
-- Zeitpunkt, State.OwnAura).
local function GroupYields(step, aura, list, unit, ctx, when)
    local group, after = GroupOf(step), false
    for _, later in ipairs(ctx.steps or {}) do
        if later == step then
            after = true
        elseif after and later.when == "dot" and later.unit == step.unit and later.mine ~= false and not later.stacks
            and GroupOf(later) == group and Enabled(later, ctx) and Rotation.NeedDue(later.need, later, ctx) == true then
            local _, name, known = Rotation.StepSpell(later)
            if name and known then
                local mine
                if aura then
                    mine = FindAura(list, later.aura or later.id) == aura
                else
                    local _, _, _, _, _, own = State.OwnAura("target", (TrackNames(later.aura or later.id, name)), nil, ctx.now)
                    mine = when ~= nil and own == when
                end
                if mine then
                    -- „läuft aus“ gehört zur anderen Wirkung, nicht zu diesem Schritt
                    local refreshLeft, refreshTotal = ctx.refreshLeft, ctx.refreshTotal
                    local due = DotDue(later, aura, name, unit, ctx) == true
                    ctx.refreshLeft, ctx.refreshTotal = refreshLeft, refreshTotal
                    return due
                end
            end
        end
    end
    return false
end

function CONDITIONS.dot(step, name, ctx)
    local unit = step.unit == "pettarget" and "pettarget" or "target"
    if unit == "pettarget" then
        local present = Rotation.UnitPresent(unit)
        if present ~= true then return present end
    end
    local list, unknown = Rotation.UnitAuras(ctx, unit, "HARMFUL", step.mine ~= false)
    local aura = FindAura(list, step.aura or step.id)
    local group = GroupOf(step)
    if not aura and group then
        local other, groupUnknown = GroupAura(step, list, ctx)
        if other then return unit == "target" and GroupYields(step, other, list, unit, ctx) end
        if groupUnknown then return nil end
    end
    if not aura then
        if unknown == 0 then return true end
        -- Gesperrt (im Kampf auf Forever üblich): mit „Mitzählen“ nachführen – nie auf dieses Ziel gewirkt heißt
        -- „fehlt“, sonst zählt die Restzeit aus Zauber und Dauer (State.OwnAura); ohne bleibt es unbekannt (nil).
        -- Ziel des Begleiters: nur nachführen, wenn es das Ziel des Spielers ist (sonst unbekannt)
        if unit == "pettarget" and not State.PetOnTarget() then return nil end
        local groupRunning, replaced, when = false, false, nil
        if group then groupRunning, replaced, when = GroupTracked(step, "target", ctx) end
        if groupRunning == nil then return nil end
        if groupRunning then return unit == "target" and GroupYields(step, nil, list, unit, ctx, when) end
        if replaced then return true end
        return DotDue(step, nil, name, unit, ctx)
    end
    if step.stacks then
        if aura.secret then return nil end      -- da, Stapel gesperrt
        if (aura.count or 0) < step.stacks then return true end
    end
    return DotDue(step, aura, name, unit, ctx)
end

-- Eigener Buff: fehlt oder läuft aus (ohne refresh: Warnzeit wie „Eigene Buffs“). buff: der Schritt steht für
-- eine Gruppe aus ezCores Buff-Wissen – jeder Buff der Gruppe zählt. group: sich ausschließende Buffs (Siegel,
-- Aspekte) – liegt einer der Gruppe, ist der Schritt nicht dran, bis der ausläuft.
function CONDITIONS.buff(step, name, ctx)
    local list, unknown = Rotation.UnitAuras(ctx, "player", "HELPFUL", false)
    local aura = FindAura(list, BuffOf(step) or step.aura or step.id)
    local group = GroupOf(step)
    if not aura and group then
        local other, groupUnknown = GroupAura(step, list, ctx)
        if groupUnknown then return nil end
        aura = other
    end
    if not aura then
        if unknown == 0 then return true end
        -- Gesperrt: nachführen wie bei den DoTs (zuletzt offen gelesen; eigener Zauber mit Dauer und „nie gewirkt“
        -- nur mit „Mitzählen“, sonst unbekannt).
        local groupRunning = false
        if group then groupRunning = GroupTracked(step, "player", ctx) end
        if groupRunning == nil then return nil end
        if groupRunning then return false end
        local state, left, seconds = Tracked("player", BuffOf(step) or step.aura or step.id, name,
            DurationID(step), ctx)
        if state == nil then return nil end
        if state == "missing" then return true end
        return DueAt(step, nil, name, left, seconds, function(_, rest, total)
            return rest <= ns.Buffs.WarnAt({ name = name, duration = total })
        end, ctx)
    end
    if aura.form then return false end
    return RefreshDue(step, aura, name, "player", ctx, function(found, left, seconds)
        local data = found.secret and { name = name, duration = seconds } or found
        return left <= ns.Buffs.WarnAt(data)
    end)
end

-- Proc: eine Aura (step.aura) liegt auf dir – mit unit = "target" ein eigener Debuff auf dem Ziel –, bei stacks mit
-- mindestens so vielen Stapeln (Pyroschlag bei 3× Aufwärmen, Schattenblitz bei Schattentrance).
function CONDITIONS.proc(step, _, ctx)
    local list, unknown
    if step.unit == "target" then
        list, unknown = Rotation.UnitAuras(ctx, "target", "HARMFUL", step.mine ~= false)
    else
        list, unknown = Rotation.UnitAuras(ctx, "player", "HELPFUL", false)
    end
    local aura = FindAura(list, step.aura or step.id)
    if not aura then
        if unknown > 0 then return nil end
        return false
    end
    if not step.stacks then return true end
    if aura.secret then return nil end
    return (aura.count or 0) >= step.stacks
end

function CONDITIONS.finisher(step)
    local points = ComboPoints()
    if points == nil then return nil end
    return points >= (step.cp or 5)
end

-- Wut, Energie, Mana ab bzw. bis zu einer Schwelle: die Zahl, wenn offen, sonst die Spanne aus Blizzards Nutzbarkeit
-- (Rotation.PowerRange, Rotation.ManaRange – Paket ezcombat/rotation-recherche, 20.11.2026).
function CONDITIONS.rage(step, _, ctx)
    return Rotation.PowerRange("Rage", { min = step.min or 0 }, ctx)
end

function CONDITIONS.energy(step, _, ctx)
    return Rotation.PowerRange("Energy", { min = step.min or 0 }, ctx)
end

function CONDITIONS.mana(step, _, ctx)
    return Rotation.ManaRange({ min = step.min or 0 }, ctx)
end

function CONDITIONS.lowmana(step, _, ctx)
    return Rotation.ManaRange({ max = step.max or 100 }, ctx)
end

-- Totem dieses Namens steht nicht (Rang am Ende zählt nicht: „Totem der Verbrennung III“).
function CONDITIONS.totem(_, name)
    if not GetTotemInfo then return true end
    for slot = 1, 4 do
        local have, totemName = GetTotemInfo(slot)
        if ns.IsSecret(have) or ns.IsSecret(totemName) then return nil end
        if have and type(totemName) == "string" and ns.Totems.BaseName(totemName) == name then return false end
    end
    return true
end

function CONDITIONS.aoe() return false end     -- nur in der Liste, nie vorgeschlagen

-- Weitere Bedingungen (enchant, pet, form, item, totemslot, stealth, autorepeat, manual) trägt RotationChecks.lua ein.
Rotation.CONDITIONS = CONDITIONS

-- Weitere Bedingungen eines Schritts (need = { … }, nur UND): Rotation.CHECKS[schlüssel](wert, schritt, ctx) aus
-- RotationChecks.lua, in fester Reihenfolge (Rotation.NEED_ORDER). Ein „falsch“ schlägt jedes „unbekannt“.
-- Rückgabe: true / false / nil, Schlüssel der entscheidenden Prüfung, bei nil die Zahl der unbekannten Prüfungen.
Rotation.CHECKS = {}
Rotation.NEED_ORDER = {}

function Rotation.NeedDue(need, step, ctx)
    if type(need) ~= "table" then return true end
    local unknownKey, unknowns = nil, 0
    for _, key in ipairs(Rotation.NEED_ORDER) do
        local value = need[key]
        if value ~= nil then
            local fn = Rotation.CHECKS[key]
            local result = fn and fn(value, step, ctx)
            if result == false then return false, key end
            if result == nil then
                unknownKey = unknownKey or key
                unknowns = unknowns + 1
            end
        end
    end
    if unknownKey then return nil, unknownKey, unknowns end
    return true
end

---------------------------------------------------------------------------
-- Ist ein Schritt jetzt dran?
---------------------------------------------------------------------------

local function Context(ctx)
    ctx = ctx or {}
    ctx.now = ctx.now or GetTime()
    if ctx.combat == nil then ctx.combat = ns.InCombat() end
    return ctx
end

-- Abklingzeit eines Schritts: die eigene (ns.CooldownState – die Antwort des Spiels, und wo es schweigt, mitgezählt;
-- Welle 27, Paket modul/ezcombat-abklingzeit, Regeln bei State.Cooldown) und – nur wenn das Spiel die eigene gerade
-- nicht selbst nennt – die geteilte (ns.SharedOnCooldown: ein Zauber derselben Kategorie laut Client-Tabellen klingt
-- ab; Welle 26, Paket modul/ezcombat-kategorien). Offene Werte des Spiels enthalten die geteilte Abklingzeit schon.
-- → Grund ("cooldown", "cooldown:shared", "secret:cooldown" = unbekannt: gewirkt, aber nur mitzuzählen und
-- „Mitzählen“ ist aus bzw. die Dauer unbekannt – nie als bereit gewertet) oder nil (bereit); Restzeit (nil =
-- unbekannt); gezählt (die Antwort beruht auf den eigenen Zaubern)
local function CooldownReason(spell, name, ctx)
    local now = ctx and ctx.now or GetTime()
    -- T8-9: je Bewertung (ctx) liest das Spiel jede Abklingzeit nur einmal
    if ctx and not ctx.cooldownReads then ctx.cooldownReads = {} end
    local state, left, source, counted = ns.CooldownState(spell, name, now, ctx and ctx.cooldownReads)
    if state == "running" then return "cooldown", left, counted end
    if state == nil then return "secret:cooldown", nil, false end
    if source == "game" then return nil, 0, false end
    local shared, _, sharedCounted, sharedLeft = ns.SharedOnCooldown(spell, now, ctx and ctx.cooldownReads)
    if shared == true then return "cooldown:shared", sharedLeft, sharedCounted == true end
    if shared == nil then return "secret:cooldown", nil, false end
    return nil, 0, counted or sharedCounted == true
end
Rotation.CooldownReason = CooldownReason

-- Altschritt (ohne kind): bewertet wie bisher – gelernt, nutzbar oder nur die Kraft fehlt, keine Abklingzeit,
-- Bedingung. Neu nur, was nichts wegnimmt: Auren über Zauber-ID und Ränge, unlesbare Auren = unbekannt,
-- group kennt die ganze Gruppe; und der Nutzer kann den Schritt ausschalten.
-- Abklingzeit für StepDue und LegacyDue: läuft sie, Grund (Restzeit und „gezählt“ in ctx.coolLeft, ctx.coolCounted –
-- für die Vorwarnung); unbekannt: nil, true (der Schritt wird am Ende übersprungen und genannt, außer eine andere
-- Bedingung ist falsch – ein „falsch“ schlägt jedes „unbekannt“). ctx.skipCooldown: Abklingzeit nicht prüfen (Wäre der
-- Schritt sonst dran? – Vorwarnung). Ein gezählt „bereit“ kennzeichnet den Vorschlag (ctx.counted).
local function Cooling(spell, name, ctx)
    ctx.coolLeft, ctx.coolCounted = nil, nil
    if ctx.skipCooldown then return nil, false end
    local reason, left, counted = CooldownReason(spell, name, ctx)
    if reason == "secret:cooldown" then return nil, true end
    if reason then
        ctx.coolLeft, ctx.coolCounted = left, counted or nil
        return reason, false
    end
    if counted then ctx.counted = true end
    return nil, false
end

local function LegacyDue(step, ctx)
    local condition = CONDITIONS[step.when or "ready"]
    if not condition or step.when == "aoe" then return false, "gate" end
    if not Enabled(step, ctx) then return false, "off" end
    local name = ns.SpellName(step.id)
    if not name or not Known(step, name) then return false, "unknown-spell" end
    -- Nutzbarkeit gesperrt: unbekannt, nicht „nicht nutzbar“ – die übrigen Prüfungen laufen weiter, denn ein „falsch“
    -- schlägt jedes „unbekannt“ (Review vor dem Merge, 20.11.2026); die Tore der Nutzbarkeit entfallen dann.
    local usable, noPower, usableLocked = ns.SpellUsable(name)
    if usableLocked then
        -- weiter unten: unbekannt, wenn nichts falsch ist
    elseif step.when == "reactive" then
        if not usable then return false end
    elseif not (usable or noPower) then
        return false
    end
    local cooling, cdUnknown = Cooling(step.id, name, ctx)
    if cooling then return false, cooling end
    -- cp bei anderen Bedingungen: erst ab so vielen Combo-Punkten (Blutung bei 5)
    if step.cp and step.when ~= "finisher" then
        local points = ComboPoints()
        if points == nil then return nil, "secret" end
        if points < step.cp then return false end
    end
    local result = condition(step, name, ctx, usable)
    if result == false then return false end
    if cdUnknown then return nil, "secret:cooldown" end
    if usableLocked then return nil, "secret" end
    if result == nil then
        if WaitsOnLockedMana(step, result, true, nil, 0, usable) then return nil, "secret:mana" end
        return nil, "secret"
    end
    return result
end

-- Ist dieser Schritt jetzt dran? true / false / nil (unbekannt). Zweiter Wert: der Grund ("off", "unknown-spell",
-- "done", "nopower", "cooldown", "cooldown:shared" = ein Zauber derselben Kategorie klingt ab, "gate",
-- "secret:cooldown" = gewirkt, die gesperrte Abklingzeit ist ohne „Mitzählen“ bzw. ohne Dauer nicht zu erfahren,
-- "need:<Schlüssel>", "secret", "secret:mana" = ein Mana-Rückholer, der allein am gesperrten Mana hängt). Das Tor der Art (Kampf, Eröffnung, Flächenmodus …) prüfen Evaluate und
-- EvaluatePrep – hier nur: Wäre er fällig, wenn er bewertet wird?
function Rotation.StepDue(step, ctx)
    ctx = Context(ctx)
    if step.kind == nil then return LegacyDue(step, ctx) end
    local when = step.when or "ready"
    local condition = CONDITIONS[when]
    if not condition then return false, "gate" end
    if not Enabled(step, ctx) then return false, "off" end
    local spellID, name, known = Rotation.StepSpell(step)
    if not name or not known then return false, "unknown-spell" end
    if step.once and State.Done(Rotation.StepKey(step)) then return false, "done" end
    -- Nutzbarkeit gesperrt: unbekannt statt „nicht nutzbar“; die übrigen Prüfungen laufen weiter (ein „falsch“ schlägt
    -- jedes „unbekannt“), die Tore der Nutzbarkeit entfallen (Review vor dem Merge, 20.11.2026).
    local usable, noPower, usableLocked = ns.SpellUsable(name)
    if usableLocked then
        -- weiter unten: unbekannt, wenn nichts falsch ist
    elseif when == "reactive" then
        if not usable then return false end
    elseif NEEDS_POWER[step.kind] or when == "buff" then
        if not usable then return false, "nopower" end
    elseif not (usable or noPower) then
        return false
    end
    local cooling, cdUnknown = Cooling(spellID, name, ctx)
    if cooling then return false, cooling end
    if step.cp and when ~= "finisher" then
        local points = ComboPoints()
        if points == nil then return nil, "secret" end
        if points < step.cp then return false end
    end
    local result = condition(step, name, ctx, usable)
    local needed, needKey, unknowns = Rotation.NeedDue(step.need, step, ctx)
    if result == false then return false end
    if needed == false then return false, "need:" .. tostring(needKey) end
    if cdUnknown then return nil, "secret:cooldown" end
    if usableLocked then return nil, "secret" end
    if result == nil or needed == nil then
        if WaitsOnLockedMana(step, result, needed, needKey, unknowns, usable) then return nil, "secret:mana" end
        return nil, "secret"
    end
    return true
end

---------------------------------------------------------------------------
-- Auswertung „Als Nächstes“
---------------------------------------------------------------------------

function Rotation.Aoe() return ns.S ~= nil and ns.S.rotationAoe == true end
function Rotation.SetAoe(on)
    if ns.S and ns.S.rotationAoe ~= (on and true or false) then ns.SetSetting("rotationAoe", on and true or false) end
    return Rotation.Aoe()
end

-- Flächenmodus umschalten (Einstellungs-Prüfung 19.11.2026, Nr. 100: eigene Taste in Blizzards Tastaturbelegung über
-- ezCores Tasten-Dienst und Klick auf das Symbol in der Mitte; das Kästchen der Einstellungen bleibt als Spiegel). Nur
-- ein eigener gespeicherter Wert, nichts Geschütztes – geht auch im Kampf. Meldet den neuen Stand im Chat. → neuer Stand
function Rotation.ToggleAoe()
    local on = Rotation.SetAoe(not Rotation.Aoe())
    ns.Print(on and L.ROTATION_AOE_ON or L.ROTATION_AOE_OFF)
    return on
end

-- Belegte Taste des Flächenmodus als Text oder nil (Tooltips).
function Rotation.AoeKeyText()
    local Keys = Core.Keys
    return Keys and Keys.KeyText and Keys.KeyText("combatAoe") or nil
end

-- Große Burst-Abklingzeit (Kaltblütigkeit, Arkane Macht, Tollkühnheit …)? Nur sie folgen „Große Abklingzeiten
-- vorschlagen“ (OPT_rotationCooldowns); Feld burst = true an einem Schritt der Art cooldown.
function Rotation.IsBurst(step)
    return type(step) == "table" and step.burst == true and Rotation.KindOf(step) == "cooldown"
end

-- Tor der Art: Wird der Schritt in „Als Nächstes“ überhaupt bewertet?
local function Gate(step, kind)
    if kind == "longbuff" or kind == "prepare" or kind == "situational" then return false end
    if step.kind == nil then return true end        -- Altschritt: wie bisher (when = "aoe" lehnt StepDue ab)
    if kind == "opener" then return State.Opening() end
    if kind == "cooldown" then
        -- Die Auswahl „Große Abklingzeiten vorschlagen“ gilt nur für die großen Burst-Abklingzeiten (burst = true,
        -- Entscheidung A des Nutzers vom 13.11.2026); alle übrigen Abklingzeiten kommen, sobald sie bereit sind.
        if not Rotation.IsBurst(step) then return true end
        local mode = ns.S and ns.S.rotationCooldowns or "always"
        if mode == "never" then return false end
        if mode == "boss" then return BOSS_RANKS[Core.UnitRank("target") or ""] == true end
        return true
    end
    if kind == "aoe" then return Rotation.Aoe() and step.when ~= "aoe" end
    return true
end

-- Kann der Spieler gerade nicht selbst zaubern? Tot oder Geist, auf einem Flug, in einem Fahrzeug mit eigener Leiste
-- (UnitHasVehicleUI: dann gelten die Knöpfe des Fahrzeugs). UnitInVehicle allein zählt nicht – auf einem Sitz ohne
-- Fahrzeugleiste (Beifahrer eines Reittiers für zwei) behält der Spieler seine Leiste (Gegenprüfung vom 15.11.2026). Dann schlägt die Rotation nichts vor und „Vor dem Kampf“ bleibt leer (Prüfung der Anzeige
-- über dem Charakter vom 15.11.2026: tot mit einem Gegner im Ziel stand dort weiter „Als Nächstes: …“). Gesperrt
-- oder unbekannt heißt „kann“ (wie bisher, nie geraten).
local function PlayerUnable()
    for _, name in ipairs({ "UnitIsDeadOrGhost", "UnitOnTaxi", "UnitHasVehicleUI" }) do
        if ns.Bool(Core.Call(rawget(_G, name), "player"), false) then return true end
    end
    return false
end
Rotation.PlayerUnable = PlayerUnable

-- Vorwarnung: Sekunden aus der Einstellung (0 = aus).
function Rotation.WarnSeconds()
    local value = ns.Num(ns.S and ns.S.rotationWarn)
    if not value or value <= 0 then return 0 end
    return value
end

-- Rest der globalen Abklingzeit, wenn das Spiel ihn offen nennt (sonst nil).
local function GcdLeft(now)
    local start, duration = ns.CooldownTimes(Spells.GCD_SPELL)
    if not (start and duration) or start <= 0 or duration <= 0 then return nil end
    local left = start + duration - now
    if left <= 0 then return nil end
    return left
end
Rotation.GcdLeft = GcdLeft     -- auch für den Vorlauf einer Erneuerung (Rotation.RefreshLead, weiter oben)

-- Der erste Schritt, der jetzt dran ist: Schritt, Name, übersprungene Namen (gesperrte Werte), side (fällige
-- Schritte, die nebenher laufen), Grund ohne Schritt ("unable", "notarget", "precombat", "hold"), gezählt (der
-- Vorschlag beruht auf einem gezählten statt gelesenen Wert), soon (Vorwarnung, Welle 27): { step, name, left,
-- counted, lead, pos } – der höchste Schritt vor dem Vorschlag (pos: Platz in der Liste; auch vor einem Mana-Rückholer,
-- der den Vorschlag übernimmt), der nur noch auf seine Abklingzeit wartet und in höchstens
-- Rotation.WarnSeconds() bereit wird; lead = true: er ist selbst der Vorschlag (bereit in höchstens Rotation.SOON_LEAD
-- bzw. dem offenen Rest der globalen Abklingzeit, oder kein anderer Schritt ist bereit).
function Rotation.Evaluate(rotation)
    local skipped, side = {}, {}
    rotation = rotation or Rotation.Selected()
    if rotation and PlayerUnable() then return nil, nil, skipped, side, "unable" end
    local combat = ns.InCombat()
    local steps = rotation and Rotation.Steps(rotation)
    -- Vorab lesen auch ohne Ziel (Zweitmeinung zum Spieltest vom 23.11.2026: zog dich ein Gegner in den Kampf, bevor du
    -- etwas anvisiert hattest, lief es nie – im Kampf fehlten dann Zauberzeiten und Werte)
    -- Ohne Ziel höchstens alle Rotation.PRIME_EVERY Sekunden (Review 23.11.2026: sonst bei jeder Bewertung, mit
    -- Energie oder Wut bis zu zehnmal je Sekunde)
    local attackable = TargetAttackable()
    if steps and not combat then
        local now = GetTime()
        if attackable or now - primedAt >= Rotation.PRIME_EVERY then
            primedAt = now
            Rotation.Prime(steps)
        end
    end
    if not rotation or not attackable then return nil, nil, skipped, side, "notarget" end
    if not combat and ns.S and ns.S.rotationOpener == false then return nil, nil, skipped, side, "precombat" end
    State.Use(rotation, steps)
    local _, holding = State.Casting(steps)
    if holding and holding.hold then return nil, nil, skipped, side, "hold" end
    local ctx = { now = GetTime(), combat = combat, rotation = rotation, steps = steps, aoe = Rotation.Aoe() }
    State.WatchCooldowns(steps, combat)
    -- Hält die Rotation einen eigenen Buff, werden die Buffs des Spielers bei jeder Bewertung gelesen – auch wenn
    -- der Schritt gerade nicht bewertet wird (Abklingzeit, Kraft). Nur so fällt eine neue, gesperrte Aura direkt
    -- nach dem eigenen Zauber auf und bekommt dessen Namen.
    if combat then
        for _, step in ipairs(steps) do
            if step.when == "buff" then
                Rotation.UnitAuras(ctx, "player", "HELPFUL", false)
                break
            end
        end
    end
    local found, foundName, counted, soon
    local expiring      -- der Vorschlag erneuert eine noch liegende Wirkung: { step, left, total, at }
    local warn = Rotation.WarnSeconds()
    local refill        -- erster Mana-Rückholer, der allein am gesperrten Mana hängt: { step, name, counted, index, pos }
    local openerAlive = false
    local currentNames, repeating = {}, {}     -- repeating: Dauerfeuer (Stab, Automatischer Schuss) – fast immer „aktuell“
    for pos, step in ipairs(steps) do
        local kind = Rotation.KindOf(step)
        -- Nach dem Fund zählen nur noch Schritte nebenher (side) und Eröffnungsschritte (schließt die Eröffnung?);
        -- „zuletzt übersprungen“ sammelt ohnehin nur bis zum Fund. Die übrigen werden nicht mehr bewertet – nur
        -- „wird gerade gewirkt“ sieht jeder Schritt nach (benennt einen eigenen Zauber mit gesperrter ID).
        local gated = Gate(step, kind)
        local name
        if gated then
            name = select(2, Rotation.StepSpell(step))
            if name and Spells.IsCurrent(name) then
                currentNames[#currentNames + 1] = name
                if step.when == "autorepeat" then repeating[name] = true end
            end
        end
        if gated and (not found or step.side or (kind == "opener" and step.kind)) then
            ctx.counted, ctx.refreshLeft, ctx.refreshTotal = nil, nil, nil
            local due, why = Rotation.StepDue(step, ctx)
            if kind == "opener" and step.kind and due ~= false then openerAlive = true end
            if step.side then
                if due == true then side[#side + 1] = step end
            elseif not found then
                if due == true then
                    found, foundName, counted = step, name, ctx.counted == true
                    if ctx.refreshLeft then
                        expiring = { step = step, left = ctx.refreshLeft, total = ctx.refreshTotal, at = ctx.now }
                    end
                elseif due == false and not soon and warn > 0 and name
                    and (why == "cooldown" or why == "cooldown:shared") then
                    local left, coolCounted = ctx.coolLeft, ctx.coolCounted == true
                    if left and left > 0 and left <= warn then
                        ctx.skipCooldown = true
                        local again = Rotation.StepDue(step, ctx)
                        ctx.skipCooldown = nil
                        if again == true then
                            soon = { step = step, name = name, left = left, counted = coolCounted or ctx.counted == true,
                                pos = pos }
                            -- erneuert eine noch liegende Wirkung: auch über die Vorwarnung „läuft aus“ (Review 23.11.2026)
                            if ctx.refreshLeft then
                                soon.expiring = { step = step, left = ctx.refreshLeft, total = ctx.refreshTotal,
                                    at = ctx.now }
                            end
                        end
                    end
                elseif due == nil and name then
                    skipped[#skipped + 1] = name
                    if refill and not refill.probe then refill.probe = name end
                    if why == "secret:mana" and not refill then
                        refill = { step = step, name = name, counted = ctx.counted == true, index = #skipped, pos = pos }
                    end
                end
            end
        end
    end
    -- Mana gesperrt: Der Rückholer (Aderlass, Hervorrufung, Manaflut, Anregen …) ist dran, wenn das Spiel vom nächsten
    -- fälligen Schritt sagt, ihm fehle allein das Mana – ohne fälligen Schritt vom ersten danach übersprungenen
    -- (ein Füller, der selbst an einer Mana-Schwelle hängt). Sonst bleibt er übersprungen und genannt – nie geraten.
    if refill and Rotation.OnlyManaMissing(found and foundName or refill.probe) then
        table.remove(skipped, refill.index)
        found, foundName, counted = refill.step, refill.name, refill.counted
        -- Ein abklingender Schritt unter dem Rückholer ist nicht höher eingestuft als der Vorschlag: keine Vorwarnung.
        if soon and soon.pos > refill.pos then soon = nil end
    end
    -- Werte abwägen (RotationValue.lua, Auftrag vom 23.11.2026): ist der Vorschlag ein Füller (oder leer), entscheidet
    -- der Vergleich Zauber gegen Zauberstab; step = false heißt „der Stab schießt schon – nichts Neues“.
    local weighed = ns.RotationValue and ns.RotationValue.Weigh(found, ctx, steps)
    local value
    if weighed then
        value = weighed.note
        if weighed.step ~= found then
            found, foundName = weighed.step or nil, weighed.step and weighed.name or nil
            counted = weighed.counted == true
        elseif weighed.counted then
            counted = true
        end
    end
    -- Vorwarnung: vorn, wenn der höhere Schritt so bald bereit wird, dass der andere ihn nur verzögern würde.
    if soon then
        local lead = math.min(warn, math.max(Rotation.SOON_LEAD, GcdLeft(ctx.now) or 0))
        if not found or soon.left <= lead then
            soon.lead = true
            found, foundName, counted = soon.step, soon.name, soon.counted
            expiring = soon.expiring
            value = nil     -- die Abwägung galt dem Füller: keine Zeile und keine Marke „Stab reicht“ am anderen Zauber
        end
    end
    State.NoteCurrent(currentNames, repeating)
    -- Die Eröffnung schließt, sobald im Kampf kein Eröffnungsschritt mehr fällig oder unbekannt ist.
    if combat and State.Opening() and not openerAlive then State.CloseOpening() end
    if expiring and expiring.step ~= found then expiring = nil end   -- Rückholer, Abwägung oder Vorwarnung kamen vor
    return found, foundName, skipped, side, nil, counted, soon, value, expiring
end

---------------------------------------------------------------------------
-- Auswertung „Vor dem Kampf“
---------------------------------------------------------------------------

local function EzBuff()
    local api = Core.API and Core.API("ezBuff")
    if type(api) == "table" and type(api.Watches) == "function" and type(api.Missing) == "function" then return api end
    return nil
end

-- Zustand eines Dauer-Buffs: "ok" | "missing" | "expiring" | "unknown", Zauber-ID, wer ihn meldet.
--   mit Gruppe aus ezCores Buff-Wissen und ezBuff zuständig (Watches): aus ezBuffs Liste (eine Stelle rechnet)
--   sonst: selbst über ezCore.Spells.BuffState bzw. die Aura des Zaubers
local function BuffState(step, ctx)
    local group, own = BuffOf(step)
    local spellID = Rotation.StepSpell(step)
    if group then
        local api = EzBuff()
        local ok, watches = pcall(function() return api and api.Watches(group) end)
        if ok and watches == true then
            local okList, list, readable = pcall(api.Missing)
            if not okList or readable ~= true then return "unknown", spellID, "ezBuff" end
            for _, entry in ipairs(type(list) == "table" and list or {}) do
                if entry.kind == "self" and entry.key == group then
                    -- nennt der Schritt einen bestimmten Buff und ist der wählbar: der; sonst der von ezBuff
                    local key, chosen = Spells.ChooseBuff(own or group,
                        { prefer = Rotation.BuffPrefer(group, own), class = ns.playerClass })
                    if not (own and key == own) then chosen = ns.Num(entry.spell) or chosen end
                    return "missing", chosen or spellID, "ezBuff"
                end
            end
            return "ok", spellID, "ezBuff"
        end
        if not PlayerReadable(ctx) then return "unknown", spellID, OWNER end
        local list = Rotation.UnitAuras(ctx, "player", "HELPFUL", false)
        local state, _, _, chosen = Spells.BuffState(own or group, list,
            { minLeft = Spells.PREP_LEFT, prefer = Rotation.BuffPrefer(group, own), class = ns.playerClass })
        return state or "unknown", chosen or spellID, OWNER
    end
    if not PlayerReadable(ctx) then return "unknown", spellID, OWNER end
    local list = Rotation.UnitAuras(ctx, "player", "HELPFUL", false)
    local aura = FindAura(list, step.aura or step.id)
    if not aura then return "missing", spellID, OWNER end
    if aura.expires then
        local minLeft = Spells.PREP_LEFT
        if aura.duration and aura.duration > 0 and minLeft > aura.duration / 4 then minLeft = aura.duration / 4 end
        if aura.expires - ctx.now < minLeft then return "expiring", spellID, OWNER end
    end
    return "ok", spellID, OWNER
end

-- Zustand eines Schritts aus „Vor dem Kampf“ – auch im Kampf lesbar (für das Zauberbuch):
-- "ok" | "missing" | "expiring" | "unknown" | "nopower" | "unlearned" | "off"; dazu Zauber-ID, wer ihn meldet, und
-- true, wenn der Buff zwar fehlt, aber eine weitere Bedingung (need) des Schritts nicht gilt – dann ist er für
-- diesen Schritt kein Thema ("ok"), ein anderer Schritt derselben Gruppe darf ihn aber melden.
function Rotation.PrepState(step, ctx)
    ctx = Context(ctx)
    if not Enabled(step, ctx) then return "off" end
    local spellID, name, known = Rotation.StepSpell(step)
    if not name or not known then return "unlearned", spellID end
    if Rotation.KindOf(step) ~= "longbuff" then
        local due, why = Rotation.StepDue(step, ctx)
        if due == true then return "missing", spellID, OWNER end
        if due == nil then return "unknown", spellID, OWNER end
        if why == "nopower" then return "nopower", spellID, OWNER end
        return "ok", spellID, OWNER
    end
    local state, chosen, by = BuffState(step, ctx)
    spellID = chosen or spellID
    if state == "missing" or state == "expiring" then
        local needed = Rotation.NeedDue(step.need, step, ctx)
        if needed == false then return "ok", spellID, by, true end
        if needed == nil then return "unknown", spellID, by end
        local chosenName = ns.SpellName(spellID) or name
        local usable = ns.SpellUsable(chosenName)
        if not usable or ns.OnCooldown(chosenName) == true then return "nopower", spellID, by end
    end
    return state, spellID, by
end

-- Was vor dem Kampf fehlt: Liste { { step, id, name, state = "missing" | "expiring", by = "ezBuff" | "ezCombat" } }
-- in Listenreihenfolge, dazu die übersprungenen Namen (Auren nicht lesbar). Im Kampf, tot, auf dem Flug oder im
-- Fahrzeug leer (PlayerUnable).
function Rotation.EvaluatePrep(rotation)
    local list, skipped = {}, {}
    rotation = rotation or Rotation.Selected()
    if not rotation or ns.InCombat() then return list, skipped end
    if PlayerUnable() then return list, skipped end
    local steps = Rotation.Steps(rotation)
    State.Use(rotation, steps)
    local ctx = { now = GetTime(), combat = false, rotation = rotation, steps = steps, aoe = Rotation.Aoe() }
    local reported = {}
    local target
    for _, step in ipairs(steps) do
        local kind = Rotation.KindOf(step)
        if kind == "longbuff" or kind == "prepare" then
            local needsTarget = type(step.need) == "table" and step.need.target == true
            if needsTarget and target == nil then target = TargetAttackable() end
            if not needsTarget or target then
                local group = BuffOf(step)
                local groupKey = group or ("id:" .. tostring(step.aura or step.id))
                if kind ~= "longbuff" or not reported[groupKey] then
                    local state, spellID, by, needFalse = Rotation.PrepState(step, ctx)
                    local name = spellID and ns.SpellName(spellID)
                    if state == "missing" or state == "expiring" then
                        if kind == "longbuff" then reported[groupKey] = true end
                        list[#list + 1] = { step = step, id = spellID, name = name, state = state, by = by or OWNER }
                    elseif state == "unknown" and name then
                        if kind == "longbuff" then reported[groupKey] = true end
                        skipped[#skipped + 1] = name
                    elseif (state == "ok" and not needFalse) or state == "nopower" then
                        if kind == "longbuff" then reported[groupKey] = true end
                    end
                end
            end
        end
    end
    return list, skipped
end

---------------------------------------------------------------------------
-- Abschnitte (für das Zauberbuch und die Schnittstelle)
---------------------------------------------------------------------------

-- Wird der Schritt je bewertet? (situativ, „nur Liste“ und „nach Lage“ nie)
local function Suggestible(step, kind)
    if kind == "situational" or step.when == "aoe" or step.when == "manual" then return false end
    return true
end
Rotation.Suggestible = function(step) return Suggestible(step, Rotation.KindOf(step)) end

local function SectionRight(key)
    if key == "cooldown" then return L["ROTATION_CD_" .. (ns.S and ns.S.rotationCooldowns or "always")] end
    if key == "aoe" then return Rotation.Aoe() and L.ROTATION_AOE_ON or L.ROTATION_AOE_OFF end
    return L["ROTATION_SECTION_" .. key .. "_RIGHT"]
end

-- Abschnitte einer Rotation in fester Folge, nur die mit Schritten:
-- { { key, title, right, steps = { { step, key, id, name, icon, known, rank, enabled, optional, kind } } } }
-- rank: Nummer in der jeweiligen Auswertung – eigene Zählung für „Vor dem Kampf“, durchgehend über Eröffnung,
-- Im Kampf, Abklingzeiten und Mehrere Gegner (das ist die Rangfolge); nil für Schritte, die nie bewertet werden
-- oder ausgeschaltet sind.
function Rotation.Sections(rotation, race, class)
    rotation = rotation or Rotation.Selected()
    local bySection, prepRank, nextRank = {}, 0, 0
    local ctx = { rotation = rotation }
    for _, step in ipairs(Rotation.Steps(rotation, race, class)) do
        local kind = Rotation.KindOf(step)
        local section = Rotation.KINDS[kind] or "combat"
        local id, name, known = Rotation.StepSpell(step)
        local enabled = Enabled(step, ctx)
        local rank
        if enabled and Suggestible(step, kind) then
            if section == "prep" then
                prepRank = prepRank + 1
                rank = prepRank
            else
                nextRank = nextRank + 1
                rank = nextRank
            end
        end
        bySection[section] = bySection[section] or {}
        table.insert(bySection[section], { step = step, key = Rotation.StepKey(step), id = id, name = name,
            icon = Spells.Icon(id), known = known, rank = rank, enabled = enabled, optional = step.optional == true,
            kind = kind })
    end
    local sections = {}
    for _, key in ipairs(Rotation.SECTIONS) do
        if bySection[key] then
            sections[#sections + 1] = { key = key, title = L["ROTATION_SECTION_" .. key], right = SectionRight(key),
                steps = bySection[key] }
        end
    end
    return sections
end

---------------------------------------------------------------------------
-- Blizzards Rotations-Assistent (C_AssistedCombat)
---------------------------------------------------------------------------

-- Steht Blizzards Assistent zur Verfügung? → true/false, dazu der Grund, den das Spiel nennt (Text oder nil). Auf
-- Forever gemessen am 15.11.2026 (außerhalb des Kampfes): IsAvailable() → false, "WRONG_WORLD_STATE_EXPRESSION".
function Rotation.BlizzardState()
    local api = rawget(_G, "C_AssistedCombat")
    if type(api) ~= "table" or type(api.IsAvailable) ~= "function" or type(api.GetNextCastSpell) ~= "function" then
        return false, nil
    end
    local ok, available, reason = pcall(api.IsAvailable)
    if not ok then return false, nil end
    reason = ns.Plain(reason)
    if type(reason) == "number" then reason = tostring(reason) end
    if type(reason) ~= "string" or reason == "" then reason = nil end
    return ns.Plain(available) == true, reason
end

function Rotation.BlizzardAvailable()
    return (Rotation.BlizzardState())
end

-- Tooltip des Schalters rotationBlizzard (bei jedem Zeigen neu gefragt): der Text, dazu, ob der Assistent gerade fehlt
-- – dann ist der Schalter ausgegraut (Options.lua) und es gilt die eigene Rotation.
function Rotation.BlizzardTip()
    local tip = L.OPT_rotationBlizzard_TIP
    local available, reason = Rotation.BlizzardState()
    if available then return tip end
    return tip .. "\n\n" .. (reason and L.ROTATION_BLIZZARD_OFF_REASON:format(reason) or L.ROTATION_BLIZZARD_OFF)
end

function Rotation.BlizzardNext()
    if not Rotation.BlizzardAvailable() then return nil end
    local ok, id = pcall(C_AssistedCombat.GetNextCastSpell, false)
    if not ok then return nil end
    return ns.Num(id)
end

---------------------------------------------------------------------------
-- Anzeige: ein Symbolplatz (ns.Symbol) und der Leucht-Dienst (Core.Glow)
---------------------------------------------------------------------------

Rotation.state = {}
local previewUntil = 0
local lastSelected

local function NameSet(list)
    local names
    for _, entry in ipairs(list or {}) do
        local name = entry.name
        if name == nil and entry.id then
            local _, stepName = Rotation.StepSpell(entry)
            name = stepName
        end
        if name then
            names = names or {}
            names[name] = true
        end
    end
    return names
end

-- Liegt der Zauber auf einem sichtbaren Aktionsknopf (jeder Rang, auch Makros, die ihn zeigen)? Nur dort kann das
-- Leuchten der nächsten Aktion zu sehen sein. Die Leisten werden je Name höchstens einmal je BAR_TTL durchgesehen;
-- ein Leistenwechsel verwirft die Antwort sofort.
local BAR_TTL = 1
local barSeen = { at = -BAR_TTL }

function Rotation.OnBar(name)
    if type(name) ~= "string" or name == "" then return false end
    local now = GetTime()
    if barSeen.name ~= name or now - barSeen.at >= BAR_TTL then
        barSeen.name, barSeen.at = name, now
        barSeen.value = #ns.Glow.ButtonsFor({ [name] = true }) > 0
    end
    return barSeen.value
end

local function ForgetBars() barSeen.name = nil end

-- Nächste Aktion (CB-N1, Wunsch des Nutzers vom 14.11.2026 nach dem Probe-Lauf: „alle fähigkeiten, meldungen davon
-- zentral über den charakter, also auch die aktuelle fähigkeit der rotation“): Wo sie erscheint, sagt die Auswahl
-- showNext (ns.ShowAt "next") – groß in der Mitte der Anzeige über dem Charakter, als goldenes Leuchten am
-- Aktionsknopf (jeder Rang, auch Makros), beides (ab Werk) oder gar nicht. Liegt ihr Zauber auf keinem sichtbaren
-- Knopf, steht sie immer in der Mitte („… – nicht auf der Leiste“; fest seit der Einstellungs-Prüfung vom 19.11.2026, Nr. 29),
-- außer die Meldungsart ist ganz aus. always: Vorschau. spell: der Zauber – ist er noch nicht bereit (Abklingzeit,
-- Kraft, Reichweite), zeigt die Anzeige ihn trotzdem, aber erkennbar „wartet“ (Symbol.lua, Wunsch des Nutzers vom
-- 15.11.2026 abends).
local symbolShown = {}      -- [Eintrag] = true, solange die Rotation ihn an der Anzeige gesetzt hat

-- Vorwarnung als Text (Welle 27): „bereit in 0,4 Sek.“ bzw. „gleich bereit: Richturteil (2,3 Sek.)“, mit „gezählt“,
-- wenn die Restzeit mitgezählt ist. → Zusatz zur Zeile „Als Nächstes“ oder nil
function Rotation.SoonText(soon)
    if type(soon) ~= "table" or not soon.left then return nil end
    local seconds = Core.Seconds(math.max(0, soon.left), 1)
    if soon.counted then seconds = seconds .. ", " .. L.ROTATION_STATE_COUNTED end
    if soon.lead then return L.ROTATION_SOON_IN:format(seconds) end
    return L.ROTATION_SOON:format(soon.name or "?", seconds)
end

-- Auslaufende Wirkung in der Mitte (Antwort des Nutzers vom 23.11.2026: „es muss ersichtlich sein das etwas ausläuft
-- was erneuert werden muss“): Restzeit als Spirale wie links, Farbe der Art „läuft aus“ und die Zeile „läuft aus –
-- erneuern“ in jeder Auswahl von „Text unter dem Symbol“. → timer, Art, Zeile oder nil
function Rotation.ExpiringLook(expiring)
    if type(expiring) ~= "table" then return nil end
    local left, total, at = ns.Num(expiring.left), ns.Num(expiring.total), ns.Num(expiring.at)
    local timer
    if left and total and at and total > 0 and left > 0 and left <= total then
        local start = math.floor((at + left - total) * 100 + 0.5) / 100     -- gerundet: jede Bewertung gleich
        timer = { start = start, duration = total }
    end
    return timer, "dot", L.SYMBOL_EXPIRING_NOTE
end

local function ShowNext(name, icon, counted, always, spell, soon, value, expiring)
    local Symbol = ns.Symbol
    local offBar = name ~= nil and ns.ShowAny("next") and not Rotation.OnBar(name)
    if name and (always or offBar or ns.ShowAt("next", "center")) then
        local text = (offBar and L.SYMBOL_NEXT_OFFBAR or L.SYMBOL_NEXT):format(name)
        local extra = Rotation.SoonText(soon)
        if extra then text = text .. (soon.lead and " – " or "\n") .. extra end
        -- Werte abwägen: warum Zauber oder Stab (kurz; /ezk status nennt die Zahlen und die Quelle) – als eigene Zeile
        -- (texts.note), unabhängig von „Text unter dem Symbol“; Schalter „Schadensvergleich unter dem Symbol“ (rotationValuesText, ab Werk aus)
        local why = ns.RotationValue and ns.Enabled("rotationValuesText") and ns.RotationValue.Text(value) or nil
        local timer, kind, expiringNote = Rotation.ExpiringLook(expiring)
        -- Text unter dem Symbol (S-1811-Symboltext): ausführlich wie bisher, sonst nur der Name bzw. gar keiner. Nicht
        -- auf der Leiste steht in jeder Auswahl eine kurze Zeile – auf einem Knopf, den es nicht gibt, leuchtet
        -- nichts, und das zeigt kein Symbol.
        local texts = { name = name, always = offBar and L.SYMBOL_OFFBAR_SHORT:format(name) or nil,
            left = soon and soon.lead and soon.left or nil, glow = always or nil, note = why or expiringNote }
        Symbol.Set("next", icon, text, kind or Rotation.Kind(), timer, spell, texts)
        symbolShown.next = true
    elseif name == nil and type(value) == "table" and value.shooting and ns.ShowAt("next", "center") then
        -- Der Stab schießt schon (Werte abwägen): nichts Neues zu drücken – er bleibt mit der Zeile der Abwägung in der
        -- Mitte, ohne Leuchten am Knopf (Antwort des Nutzers vom 23.11.2026: „Stab in der Mitte (Empfohlen)“)
        local wand = value.shooting
        local why = ns.RotationValue and ns.Enabled("rotationValuesText") and ns.RotationValue.Text(value) or nil
        Symbol.Set("next", wand.spell and Spells.Icon(wand.spell), L.SYMBOL_WAND_SHOOTING:format(wand.name or "?"),
            Rotation.Kind(), nil, nil, { name = wand.name, note = why, glow = false })
        symbolShown.next = true
    elseif symbolShown.next then
        symbolShown.next = nil
        Symbol.Clear("next")
    end
    -- Werte abwägen, Ziel fast tot: Marke „Stab reicht“ unten rechts an der Mitte, nur solange der Füller dort steht
    if ns.RotationValue then ns.RotationValue.ShowFinish(symbolShown.next and value or nil) end
    Rotation.nextOffBar = offBar or nil
    -- Der Knopf leuchtet nur, wenn der Zauber bereit oder fast bereit ist (Spieltest 20.11.2026, Readiness.Ready – mit
    -- der gezählten Restzeit der Vorwarnung vorn, falls die Abklingzeit gesperrt ist); die Vorschau leuchtet immer. Das
    -- Symbol in der Mitte bekommt dieselbe Grundlage (texts.left, texts.glow), damit beide gleich antworten.
    local left = soon and soon.lead and soon.left or nil
    local ready = always or ns.Readiness.Ready(spell, nil, left) ~= false
    if name and ready and ns.ShowAt("next", "glow") then
        Core.Glow.Set(OWNER, "next", { kind = "next", names = { [name] = true }, nameOf = ns.SpellName,
            tip = counted and L.GLOW_TIP_next_counted or L.GLOW_TIP_next })
    else
        Core.Glow.Clear(OWNER, "next")
    end
end

-- Schritte, die nebenher laufen (kein globaler Cooldown): leuchten nur, belegen nie „Als Nächstes“ – also nur, wenn
-- die nächste Fähigkeit am Knopf leuchten soll.
local function ShowSide(side)
    local names = ns.ShowAt("next", "glow") and ns.Enabled("rotationSide") and NameSet(side) or nil
    if names then
        Core.Glow.Set(OWNER, "side", { kind = "next", names = names, nameOf = ns.SpellName, tip = L.GLOW_TIP_side })
    else
        Core.Glow.Clear(OWNER, "side")
    end
end

-- Vor dem Kampf: „Vor dem Kampf: …“ am linken Platz der Anzeige über dem Charakter (in Ruhezonen nur auf Wunsch;
-- nicht, solange „Eigene Buffs“ denselben Namen schon als auslaufend zeigt) und Leuchten in der Art „Buff fehlt“. Im
-- Kampf nie. Was fehlt, gehört zu „läuft aus“: Mitte und Leuchten folgen dessen Auswahl (showExpiring).
local function ShowPrep(prep)
    local Symbol = ns.Symbol
    local active = ns.Enabled("rotation") and ns.Enabled("rotationPrep") and not ns.InCombat() and prep and prep[1]
    local first, more
    if active and ns.ShowAt("expiring", "center") then
        local resting = ns.Bool(Core.Call(rawget(_G, "IsResting")), false)
        if not resting or ns.Enabled("rotationPrepRest") then
            local showing = ns.Buffs and ns.Buffs.Showing and ns.Buffs.Showing()
            more = -1
            for _, entry in ipairs(prep) do
                if entry.name and entry.name ~= showing then
                    first = first or entry
                    more = more + 1
                end
            end
        end
    end
    if first then
        local text = more > 0 and L.SYMBOL_PREP_MORE:format(first.name, more) or L.SYMBOL_PREP:format(first.name)
        Symbol.Set("prep", Spells.Icon(first.id), text, "missing", nil, first.id, { name = first.name })
        symbolShown.prep = true
    elseif symbolShown.prep then
        symbolShown.prep = nil
        Symbol.Clear("prep")
    end
    local names = active and ns.ShowAt("expiring", "glow") and NameSet(prep) or nil
    -- Was ezBuff gerade selbst als „fehlt“ meldet, nicht noch einmal (CB-40, „ezBuff ist die eine Stelle“; die
    -- Anzeige über dem Charakter und der Reiter spiegeln es weiter).
    if names and ns.Buffs and ns.Buffs.HandledByEzBuff then
        for name in pairs(ns.Buffs.HandledByEzBuff(names)) do names[name] = nil end
        if not next(names) then names = nil end
    end
    if names then
        Core.Glow.Set(OWNER, "prep", { kind = "missing", names = names, nameOf = ns.SpellName, tip = L.GLOW_TIP_prep })
    else
        Core.Glow.Clear(OWNER, "prep")
    end
end

-- Bewertet die gewählte Rotation in state (Rotation.Update).
local function Assess(state)
    if ns.Enabled("rotation") then
        local selected = Rotation.Selected()
        -- „Nach Talentbaum“ hat gewechselt (Stufe, Gestalt, Talent): Zustand der alten Rotation gilt nicht mehr.
        -- false = „keine Rotation“ (beides gleich normiert, sonst wäre nil ~= false bei jedem Durchgang ein Wechsel)
        local selectedKey = selected and selected.key or false
        if lastSelected ~= nil and selectedKey ~= lastSelected then
            State.Reset("all")
            for _, fn in ipairs(Rotation.listeners) do pcall(fn) end
        end
        lastSelected = selectedKey
        local id = ns.S.rotationBlizzard and not PlayerUnable() and TargetAttackable() and Rotation.BlizzardNext()
        if id then
            state.source, state.id, state.spell, state.name = "blizzard", id, id, ns.SpellName(id)
        elseif ns.S.rotationInCombat == false and ns.InCombat() then
            -- Schalter „Eigene Empfehlung auch im Kampf“ aus (Blizzards Regeln, Prüfung 17.11.2026, V1): im Kampf keine
            -- eigene Empfehlung, nur Blizzards Assistent (oben). Ab Werk an – die Vorhersage im Kampf bleibt
            -- (entschieden vom Nutzer am 17.11.2026)
            state.source, state.reason = "rotation", "blizzardonly"
        else
            local step, name, skipped, side, reason, counted, soon, value, expiring = Rotation.Evaluate(selected)
            state.source, state.step, state.name, state.skipped = "rotation", step, name, skipped
            state.side, state.reason, state.counted, state.soon = side, reason, counted or nil, soon
            state.value, state.expiring = value, expiring
            state.id = step and step.id
            if step then
                state.spell, state.key, state.kind = Rotation.StepSpell(step), Rotation.StepKey(step), Rotation.KindOf(step)
            end
        end
        state.prep, state.prepSkipped = Rotation.EvaluatePrep(selected)
        if #state.skipped > 0 then Rotation.lastSkipped = { when = state.when, names = state.skipped } end
        if #state.prepSkipped > 0 then Rotation.lastPrepSkipped = { when = state.when, names = state.prepSkipped } end
    end
end

function Rotation.Update()
    if GetTime() < previewUntil then return end
    local state = { when = GetTime(), skipped = {}, side = {}, prep = {}, prepSkipped = {} }
    -- Wirft die Bewertung (Datenfehler, Ausnahme einer Client-Abfrage), bleibt kein alter Vorschlag und kein altes
    -- Leuchten stehen: Anzeige leer, Grund „error“ in /ezk status, der Fehler in ezCores Fehlerliste (Gesamtreview
    -- 18.11.2026, T7-NE2). „Nie raten“ – ein veralteter Vorschlag wäre ein falscher.
    local ok, problem = pcall(Assess, state)
    if not ok then
        state = { when = state.when, source = "rotation", reason = "error", skipped = {}, side = {}, prep = {},
            prepSkipped = {} }
        ns.Error(problem, "Rotation.Update")
    end
    local before = Rotation.state and Rotation.state.id
    Rotation.state = state
    ShowNext(state.name, state.spell and Spells.Icon(state.spell), state.counted, nil, state.spell, state.soon, state.value,
        state.expiring)
    ShowSide(state.side)
    ShowPrep(state.prep)
    if before ~= state.id then
        for _, fn in ipairs(Rotation.nextListeners) do pcall(fn) end
    end
end

local updateSoon = ns.Throttle(function() ns.Try("Rotation", Rotation.Update) end, 0.1)
Rotation.UpdateSoon = updateSoon

local function IsPlayer(unit) return not ns.IsSecret(unit) and unit == "player" end

for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "ACTIONBAR_UPDATE_USABLE", "SPELLS_CHANGED",
    "BAG_UPDATE_DELAYED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_UPDATE_RESTING", "PLAYER_LEVEL_UP",
    -- tot, wiederbelebt, Flug, Fahrzeug (PlayerUnable): die Anzeige über dem Charakter räumt sofort bzw. kommt zurück
    "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
    ns.On(event, updateSoon)
end
-- Leisten geändert (Zauber gezogen, Seite gewechselt, Gestalt, Makro): „liegt auf einer Leiste“ neu ansehen.
for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD" }) do
    ns.On(event, function()
        ForgetBars()
        updateSoon()
    end)
end
-- UNIT_*-Ereignisse nur für die Einheiten, die zählen (ns.OnUnit: Blizzard weckt den Zuhörer nur für sie; eine
-- gesperrte Einheit stellt ezCore trotzdem zu – deshalb bleibt die Prüfung im Zuhörer).
-- UNIT_AURA kommt im Kampf mit gesperrter Einheit (Forever-Quelle: SecretWhenAurasRestricted): Geweckt wird der
-- Zuhörer nur für Spieler und Ziel, also zählt eine gesperrte Einheit als eine von beiden.
ns.OnUnit("UNIT_AURA", { "player", "target" }, function(_, unit)
    if ns.IsSecret(unit) or unit == "player" or unit == "target" then updateSoon() end
end)
for _, event in ipairs({ "UNIT_POWER_FREQUENT", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_PET", "UNIT_INVENTORY_CHANGED",
    "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }) do
    ns.OnUnit(event, "player", function(_, unit) if IsPlayer(unit) then updateSoon() end end)
end
-- Kampfbeginn: „Vor dem Kampf“ verschwindet sofort, nicht erst mit der nächsten Bewertung.
ns.On("PLAYER_REGEN_DISABLED", function()
    symbolShown.prep = nil
    ns.Symbol.Clear("prep")
    Core.Glow.Clear(OWNER, "prep")
end)
-- Talentpunkte umverteilt oder Spezialisierungsgruppe gewechselt: „Nach Talentbaum“ neu bestimmen (Assess setzt den
-- Zustand zurück, wenn dabei eine andere Rotation herauskommt), die Seite nennt den Baum neu.
Core.Listen("TALENTS_CHANGED", function()
    updateSoon()
    for _, fn in ipairs(Rotation.listeners) do pcall(fn) end
end, OWNER)
-- ezBuff hat neu geprüft (seine Liste ist die eine Stelle für „Dauer-Buff fehlt“, wenn es zuständig ist).
Core.Listen("EZBUFF_TASKS", function() updateSoon() end, OWNER)
ns.OnSettingChanged(function(key)
    -- Takte nur, solange die Rotation an ist (Gesamtreview 18.11.2026, T7-3; Gegenprüfung P19c)
    if Rotation.ticker then Rotation.ticker:Update() end
    if Rotation.idleTicker then Rotation.idleTicker:Update() end
    if key == "rotationChoice" then
        if ns.S.rotationChoice ~= Rotation.Choice() then Rotation.Select(ns.S.rotationChoice) end
    elseif type(key) == "string" and (key:find("^rotation") or key == "showNext" or key == "showExpiring") then
        updateSoon()
        if key == "rotationAoe" or key == "rotationCooldowns" then
            for _, fn in ipairs(Rotation.listeners) do pcall(fn) end
        end
    end
end)

-- Restzeiten laufen ohne Ereignis ab: ein leiser Takt mit angreifbarem Ziel; ohne Ziel außerhalb des Kampfes
-- reichen die Ereignisse und ein seltener Blick (Dauer-Buff läuft bald aus).
-- Beide Takte laufen ganz in der Fehlerliste (ezCores Ticker-Helfer mit Griff, Gesamtreview 18.11.2026, T7-3): auch ein
-- Fehler beim Prüfen des Ziels landet im Fehlerprotokoll. Sie entstehen erst in OnReady (ein älteres ezCore ohne
-- ns.Ticker meldet dann nur „zu alt“, Gegenprüfung P19c) und laufen nur, solange die Rotation an ist (RotationOn;
-- OnSettingChanged oben startet bzw. hält sie an).
local function RotationOn() return ns.S ~= nil and ns.Enabled("rotation") end

-- Beim Einloggen: die Wahl dieses Charakters in die Einstellung spiegeln (die Einstellungsseite zeigt sie).
ns.OnReady(function()
    Rotation.ticker = ns.Ticker(CHECK_EVERY, function()
        if RotationOn() and TargetAttackable() then Rotation.Update() end
    end, RotationOn, "Rotation")
    Rotation.idleTicker = ns.Ticker(IDLE_EVERY, function()
        if RotationOn() and not TargetAttackable() and not ns.InCombat() then
            Rotation.Update()
        end
    end, RotationOn, "Rotation")
    if ns.S and ns.S.rotationChoice ~= Rotation.Choice() then ns.SetSetting("rotationChoice", Rotation.Choice()) end
    updateSoon()
end)

-- Werte für die Auswahl auf der Einstellungsseite: { { Schlüssel, Text } }. Immer dieselbe Tabelle, bei jedem Aufruf
-- neu gefüllt: Die Einstellungsseite hält sie fest, und eine neue eigene Rotation (RotationOwn.lua ruft das nach jeder
-- Änderung) erscheint so ohne neue Seite in der Auswahl.
local choiceValues = {}
function Rotation.ChoiceValues()
    for index = #choiceValues, 1, -1 do choiceValues[index] = nil end
    choiceValues[1] = { "auto", L.ROTATION_AUTO }
    for _, rotation in ipairs(Rotation.ForClass()) do
        choiceValues[#choiceValues + 1] = { rotation.key, Rotation.Name(rotation) }
    end
    return choiceValues
end

---------------------------------------------------------------------------
-- Selbsttest: Kennt dieser Client die Zauber- und Gegenstands-IDs der Rotationen? (/ez test, /ezk status)
---------------------------------------------------------------------------

-- Die Kennungen sammelt ns.RotationData.StepIDs bzw. RotationIDs (eine Stelle für /ez zauber, diesen Selbsttest und
-- tools/zauber.lua; Gesamtreview 18.11.2026, T7-NE4).

local function ItemExists(id)
    local api = C_Item and C_Item.DoesItemExistByID
    if type(api) ~= "function" then return nil end
    local ok, there = pcall(api, id)
    there = ns.Plain(there)
    if ok and type(there) == "boolean" then return there end
    return nil
end

-- Alle Rotationen aller Klassen und die Volksfähigkeiten: { checked = Anzahl, missing = { { class, rotation, key,
-- id, what = "spell" | "aura" | "item" } } }. Nichts wird geraten oder ersetzt – ein Schritt mit unbekannter ID
-- fällt wie ein ungelernter aus.
function Rotation.CheckSpells()
    local result = { checked = 0, missing = {} }
    local function Check(class, rotationKey, stepKey, what, id)
        local there
        if what == "item" then there = ItemExists(id) else there = Spells.Exists(id) end
        if there == nil then return end         -- nicht prüfbar (Schnittstelle fehlt)
        result.checked = result.checked + 1
        if not there then
            result.missing[#result.missing + 1] = { class = class, rotation = rotationKey, key = stepKey, id = id,
                what = what }
        end
    end
    local classes = {}
    for class in pairs(ns.ROTATIONS or {}) do classes[#classes + 1] = class end
    table.sort(classes)
    for _, class in ipairs(classes) do
        if class == "RACIAL" then
            for _, step in ipairs(ns.ROTATIONS.RACIAL) do
                ns.RotationData.StepIDs(step, function(id, what)
                    Check(class, tostring(step.race), Rotation.StepKey(step), what, id)
                end)
            end
        else
            -- mit den berechneten Rotationen (Welle 21), solange sie gezeigt werden; Schritte, pick, Zähler und {ID}
            -- in den Texten (Fundstelle: Schritt-Schlüssel bzw. Feld der Rotation, etwa „pick.known“, „counter:x“)
            for _, rotation in ipairs(Rotation.ForClass(class)) do
                ns.RotationData.RotationIDs(rotation, function(id, what, field, step)
                    Check(class, rotation.key, step and Rotation.StepKey(step) or field, what, id)
                end)
            end
        end
    end
    return result
end

-- ezCores Selbsttest (/ez test): je unbekannter ID eine Zeile mit der ersten Fundstelle
-- („WARLOCK/affliction opener:348 → 348“), bekannte IDs zählen als geprüft.
if Core.AddSelfTest then
    Core.AddSelfTest(OWNER, function()
        local check = Rotation.CheckSpells()
        local list, seen = {}, {}
        for _, entry in ipairs(check.missing) do
            local id = entry.what .. ":" .. entry.id
            if seen[id] then
                seen[id].count = seen[id].count + 1
            else
                seen[id] = { count = 1, entry = entry }
                list[#list + 1] = seen[id]
            end
        end
        local result = {}
        for _, item in ipairs(list) do
            local entry = item.entry
            local name = ("%s/%s %s » %d"):format(entry.class, entry.rotation, entry.key, entry.id)
            if item.count > 1 then name = name .. " (+" .. (item.count - 1) .. ")" end
            result[#result + 1] = { kind = entry.what == "item" and "item" or "spell", name = name, there = false,
                optional = true }
        end
        local known = check.checked - #check.missing
        if known > 0 then
            result[#result + 1] = { kind = "spell", name = "ezCombat: " .. known, there = true, optional = true }
        end
        return result
    end)
end

---------------------------------------------------------------------------
-- /ezk status
---------------------------------------------------------------------------

local function Ago(when) return L.STATUS_AGO:format(Core.Duration(GetTime() - when, true)) end

-- Woher die nächste Aktion kommt.
ns.AddStatusLine(function()
    if not ns.Enabled("rotation") then return L.STATUS_ROTATION_OFF:format(ns.PathText("OPT_HEADER_ROTATION", "OPT_rotation")) end
    if #Rotation.ForClass() == 0 then return L.STATUS_ROTATION_NONE end
    if ns.S.rotationBlizzard and Rotation.BlizzardAvailable() then return L.STATUS_ROTATION_BLIZZARD end
    local rotation = Rotation.Selected()
    local auto = Rotation.Choice() == "auto"
    local line = L.STATUS_ROTATION_OWN:format(Rotation.Name(rotation), auto and L.ROTATION_AUTO_SHORT or L.ROTATION_CHOSEN)
    return auto and (line .. " · " .. Rotation.AutoWhy()) or line
end)
-- Welcher Schritt gerade gezeigt wird und von welcher Art er ist – oder warum keiner.
ns.AddStatusLine(function()
    if not ns.Enabled("rotation") or #Rotation.ForClass() == 0 then return nil end
    local state = Rotation.state or {}
    if state.source ~= "rotation" then return nil end
    if state.step and state.name then
        local kind = L["ROTATION_KIND_" .. tostring(state.kind)] or tostring(state.kind)
        if state.counted then kind = kind .. ", " .. L.ROTATION_STATE_COUNTED end
        local line = L.STATUS_ROTATION_STEP:format(state.name, kind)
        local soon = Rotation.SoonText(state.soon)
        if soon then line = line .. " · " .. soon end
        -- Liegt der Schritt auf keinem sichtbaren Knopf, kann nichts leuchten: Der Status sagt, wo er dann steht.
        if Rotation.nextOffBar then line = line .. " " .. L.STATUS_ROTATION_OFFBAR end
        return line
    end
    return L.STATUS_ROTATION_NOSTEP:format(L["ROTATION_REASON_" .. (state.reason or "none")])
end)
-- Werte abwägen: Zahlen, Mana und Quelle des letzten Vergleichs (Leitlinie 11).
ns.AddStatusLine(function()
    local state = Rotation.state
    if not (ns.Enabled("rotation") and state and state.source == "rotation" and ns.RotationValue) then return nil end
    local line = ns.RotationValue.StatusText(state.value)
    if line then return line end
    -- nicht abgewogen: sagen, warum (Spieltest 23.11.2026)
    local skip = ns.RotationValue.skip
    if skip and skip ~= "off" then return L.STATUS_VALUE_SKIP:format(L["STATUS_VALUE_SKIP_" .. skip] or skip) end
    return nil
end)
-- Vorlauf vor dem Ablauf (Spieltest 23.11.2026): im Kampf nur mit „Mitzählen“ – wer es aus hat, erfährt hier, warum
-- DoTs und HoTs dort erst nach dem Ablauf kommen (Wunsch des Nutzers über die Orchestrierung: „So lassen“, Mitzählen
-- bleibt ab Werk aus). Nur, wenn die gewählte Rotation einen Schritt mit Erneuern hat.
ns.AddStatusLine(function()
    if not ns.Enabled("rotation") or State.Estimating() then return nil end
    local rotation = Rotation.Selected()
    for _, step in ipairs(rotation and rotation.steps or {}) do
        if (step.when == "dot" or step.when == "buff") and step.refresh ~= nil then
            return L.STATUS_ROTATION_LEAD_OFF:format(ns.PathText("SETTINGS_ADVANCED", "OPT_rotationEstimate"))
        end
    end
    return nil
end)
-- Neue Dateien eines Pakets lädt WoW erst nach einem Neustart des Spiels – /reload liest die TOC nicht neu (Spieltest
-- 23.11.2026 nach PR 715: keine Zeile, keine Marke, kein Stab). Fehlen sie, sagt ezCombat das sichtbar, statt still
-- nichts zu tun: einmal im Chat beim Laden und in /ezk status.
Rotation.FILES = {
    { "ezCombat/RotationValue.lua", function() return ns.RotationValue ~= nil end },
    { "ezCore/Wissen/SpellValue.lua", function() return Core.SpellValue ~= nil end },
    { "ezCore/Wissen/Client/Direct.lua", function()
        local CD = Core.ClientData
        return CD ~= nil and type(CD.Table) == "function" and type(CD.Table("direct")) == "table"
    end },
}
function Rotation.MissingFiles()
    local missing = {}
    for _, file in ipairs(Rotation.FILES) do
        local ok, loaded = pcall(file[2])
        if not (ok and loaded) then missing[#missing + 1] = file[1] end
    end
    return missing
end
ns.AddStatusLine(function()
    local missing = Rotation.MissingFiles()
    if #missing == 0 then return nil end
    return L.STATUS_FILES_MISSING:format(table.concat(missing, ", "))
end)
ns.OnReady(function()
    local missing = Rotation.MissingFiles()
    if #missing > 0 then ns.Print(L.STATUS_FILES_MISSING:format(table.concat(missing, ", "))) end
end)
-- Was zuletzt übersprungen wurde (gesperrte Werte).
ns.AddStatusLine(function()
    local last = Rotation.lastSkipped
    if not (ns.Enabled("rotation") and last and #last.names > 0) then return nil end
    return L.STATUS_ROTATION_SKIPPED:format(table.concat(last.names, ", "), Ago(last.when))
end)
-- Woher die Rotation im Kampf ihre Kraft kannte (Leitlinie 11: Quelle nennen): Blizzards Nutzbarkeit eines Zaubers.
ns.AddStatusLine(function()
    local probe = Rotation.lastPowerProbe
    if not (ns.Enabled("rotation") and probe and probe.by) then return nil end
    local power = rawget(_G, probe.power:upper())      -- Blizzards Texte MANA, RAGE, ENERGY
    if type(power) ~= "string" or ns.IsSecret(power) then power = probe.power end
    return L.STATUS_ROTATION_POWER:format(power, probe.by, Ago(probe.when))
end)
-- Vor dem Kampf: was fehlt bzw. dass die Auren nicht lesbar waren.
ns.AddStatusLine(function()
    if not ns.Enabled("rotation") then return nil end
    local names = {}
    for _, entry in ipairs((Rotation.state or {}).prep or {}) do names[#names + 1] = entry.name end
    if #names > 0 then return L.STATUS_ROTATION_PREP:format(table.concat(names, ", ")) end
    return nil
end)
ns.AddStatusLine(function()
    local last = Rotation.lastPrepSkipped
    if not (ns.Enabled("rotation") and last and #last.names > 0) then return nil end
    return L.STATUS_ROTATION_PREP_UNREAD:format(table.concat(last.names, ", ") .. ", " .. Ago(last.when))
end)
ns.AddStatusLine(function()
    if not ns.Enabled("rotation") or not Rotation.EditCount then return nil end
    local count = Rotation.EditCount(Rotation.Selected())
    if count > 0 then return L.STATUS_ROTATION_EDITED:format(count) end
    return nil
end)
ns.AddStatusLine(function()
    if ns.Enabled("rotation") and Rotation.Aoe() then return L.STATUS_ROTATION_AOE end
    return nil
end)
ns.AddStatusLine(function()
    if not ns.Enabled("rotation") then return nil end
    local ids, seen = {}, {}
    for _, entry in ipairs(Rotation.CheckSpells().missing) do
        if not seen[entry.id] then
            seen[entry.id] = true
            ids[#ids + 1] = entry.id
        end
    end
    if #ids == 0 then return nil end
    table.sort(ids)
    local shown = {}
    for index = 1, math.min(#ids, 8) do shown[index] = tostring(ids[index]) end
    if #ids > 8 then shown[#shown + 1] = "…" end
    return L.STATUS_ROTATION_IDS:format(#ids, table.concat(shown, ", "))
end)
ns.AddStatusLine(function()
    if not ns.Enabled("rotation") or #Rotation.ForClass() == 0 then return nil end
    return L.STATUS_ROTATION_CAST:format(L["ROTATION_CAST_" .. State.CastSource()])
end)

-- Vorschau: der erste gelernte Schritt der Auswertung „Als Nächstes“ als nächste Aktion – nie ein Schritt aus
-- „Vor dem Kampf“.
ns.AddPreview("rotation", 45, function()
    if not ns.Enabled("rotation") then return false end
    local rotation = Rotation.Selected()
    local chosen, fallback
    for _, step in ipairs(Rotation.Steps(rotation)) do
        local kind = Rotation.KindOf(step)
        if kind ~= "longbuff" and kind ~= "prepare" and Suggestible(step, kind) then
            fallback = fallback or step
            local _, name, known = Rotation.StepSpell(step)
            if name and known then chosen = step break end
        end
    end
    chosen = chosen or fallback or (rotation and rotation.steps and rotation.steps[1])
    if not chosen then return false end
    previewUntil = GetTime() + PREVIEW_SECONDS
    local id, name = Rotation.StepSpell(chosen)
    ShowNext(name, Spells.Icon(id), nil, true, id)      -- Vorschau: Knopf und Symbolplatz, auch wenn dieser sonst frei bleibt
    C_Timer.After(PREVIEW_SECONDS + 0.1, function()
        previewUntil = 0
        updateSoon()
    end)
    return true
end)

---------------------------------------------------------------------------
-- Schnittstelle für andere Module (ezCore.API("ezCombat")), z. B. ezTalent: zu einer Talent-Vorlage die Rotation
-- desselben Talentbaums nennen. Gibt nur Kopien heraus, nie ezCombats eigene Tabellen.
---------------------------------------------------------------------------

-- Angabe aus pick als Liste (Kopie): known = 1 oder { 1, 2 } → { … } | nil
local function List(value)
    if value == nil then return nil end
    local out = {}
    for i, id in ipairs(type(value) == "table" and value or { value }) do out[i] = id end
    return out
end

local function Summary(rotation)
    if not rotation then return nil end
    local pick = type(rotation.pick) == "table" and rotation.pick or {}
    return { key = rotation.key, tree = rotation.tree, name = Rotation.Name(rotation), source = rotation.source,
        steps = #(rotation.steps or {}), how = Rotation.How(rotation),
        edited = Rotation.IsEdited ~= nil and Rotation.IsEdited(rotation) or false,
        computed = Rotation.IsComputed(rotation), own = Rotation.IsOwn(rotation),
        known = List(pick.known), unknown = List(pick.unknown), leveling = pick.leveling }
end

ns.API = ns.API or {}

-- Rotationen einer Klasse (ohne Angabe: die des Spielers): { { key, tree, name, source, steps = Anzahl, how, edited,
-- computed, own, known, unknown, leveling } } – computed: berechnet (Welle 21, RotationComputed.lua); own: eigene; known,
-- unknown (Zauber-IDs), leveling: woran „Nach Talentbaum“ sie erkennt
function ns.API.Rotations(class)
    local list = {}
    for _, rotation in ipairs(Rotation.ForClass(class)) do list[#list + 1] = Summary(rotation) end
    return list
end

-- Die (erste) Rotation für Talentbaum 1–3 einer Klasse, sonst nil – eine Vorlage aus den Quellen. Zu einer bestimmten
-- Talentvorlage: ns.API.RotationForBuild.
function ns.API.RotationFor(class, tree)
    for _, rotation in ipairs(Rotation.ForClass(class)) do
        if rotation.tree == tree and not Rotation.IsComputed(rotation) then return Summary(rotation) end
    end
    return nil
end

-- Die Vorgabe zu einer Talentvorlage (Schlüssel aus ezTalent, recherchiert oder berechnet), sonst nil – aus ezCores
-- Zuordnung (Core.RotationBuilds, die eine Stelle; bis zum 24.11.2026 nur berechnete über computed.distribution).
function ns.API.RotationForBuild(key, class)
    for _, rkey in ipairs(Core.RotationBuilds.Rotations(class or ns.playerClass, key)) do
        local rotation = Rotation.Find(rkey, class)
        if rotation then return Summary(rotation) end
    end
    return nil
end

-- Gewählte Rotation dieses Charakters: Zusammenfassung, Wahl („auto“ = nach Talentbaum).
function ns.API.SelectedRotation() return Summary(Rotation.Selected()), Rotation.Choice() end

-- Rotation wählen (Schlüssel einer Rotation der eigenen Klasse oder „auto“); true, wenn es sie gibt.
function ns.API.SelectRotation(key)
    if key ~= "auto" and not Rotation.Find(key) then return false end
    Rotation.Select(key)
    return true
end

-- Abschnitte einer Rotation (Schlüssel; ohne Angabe die gewählte; class: Klasse, Standard die eigene):
-- { { key, title, steps = { { key, id, name, kind, rank, enabled, optional, text, condition } } } }
function ns.API.Sections(key, class)
    local rotation = key and Rotation.Find(key, class) or (key == nil and Rotation.Selected()) or nil
    if not rotation then return {} end
    local Book = ns.RotationBook
    local sections = {}
    for _, section in ipairs(Rotation.Sections(rotation, nil, class)) do
        local steps = {}
        for _, entry in ipairs(section.steps) do
            steps[#steps + 1] = { key = entry.key, id = entry.id, name = entry.name, kind = entry.kind,
                rank = entry.rank, enabled = entry.enabled, optional = entry.optional,
                text = Rotation.StepText(entry.step),
                condition = Book and Book.ConditionText and Book.ConditionText(entry.step) or nil }
        end
        sections[#sections + 1] = { key = section.key, title = section.title, steps = steps }
    end
    return sections
end

-- Nächste Aktion: { id, name, key, kind, source = "rotation" | "blizzard", counted } oder nil.
function ns.API.NextAction()
    local state = Rotation.state or {}
    if not state.name then return nil end
    return { id = state.spell or state.id, name = state.name, key = state.key, kind = state.kind, source = state.source,
        counted = state.counted == true }
end

-- Was vor dem Kampf fehlt: { { id, name, key, state, by } }, lesbar (false: Auren waren nicht lesbar oder Kampf –
-- dann sagt die leere Liste nichts).
function ns.API.Prep()
    local state = Rotation.state or {}
    local list = {}
    for _, entry in ipairs(state.prep or {}) do
        list[#list + 1] = { id = entry.id, name = entry.name, key = Rotation.StepKey(entry.step), state = entry.state,
            by = entry.by }
    end
    return list, not ns.InCombat() and #(state.prepSkipped or {}) == 0
end

function ns.API.IsEdited(key)
    local rotation = key and Rotation.Find(key) or Rotation.Selected()
    return rotation ~= nil and Rotation.IsEdited ~= nil and Rotation.IsEdited(rotation)
end

function ns.API.ResetEdits(key)
    local rotation = key and Rotation.Find(key) or Rotation.Selected()
    if not (rotation and Rotation.ResetEdits) then return false end
    return Rotation.ResetEdits(rotation)
end

function ns.API.Aoe() return Rotation.Aoe() end
function ns.API.SetAoe(on) return Rotation.SetAoe(on) end
function ns.API.ToggleAoe() return Rotation.ToggleAoe() end   -- Taste „Flächenmodus“ (ezCore.Keys, combatAoe)
-- Die Taste liefert ezCombat selbst (Keys.Register): ezCores Eintrag fragt sonst nur die Schnittstelle oben.
if Core.Keys and Core.Keys.Register then
    Core.Keys.Register("combatAoe", function() Rotation.ToggleAoe() return true end, "ezCombat")
end

-- Unbekannte Zauber- und Gegenstands-IDs der Rotationen (Kopie): { checked, missing = { … } }
function ns.API.CheckSpells()
    local check = Rotation.CheckSpells()
    local copy = { checked = check.checked, missing = {} }
    for index, entry in ipairs(check.missing) do
        copy.missing[index] = { class = entry.class, rotation = entry.rotation, key = entry.key, id = entry.id,
            what = entry.what }
    end
    return copy
end
