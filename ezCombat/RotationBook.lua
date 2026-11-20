local _, ns = ...
local L = ns.L
local Core = ezCore
local Spells = Core.Spells
local Rotation = ns.Rotation
local State = ns.RotationState

-- Seitenreiter „Rotation“ am Zauberbuch (Wunsch des Nutzers, 13.11.2026: „die vorlagen der rotationen nach auswah
-- müssen auch angezeigt werden, als grundlage dienen und ggf anpassbar --> was hinter den rotationen steckt, weiß
-- keiner, welche ausgewählt sind, weiß keiner, wie welche rotation fogt, weiß niemand“). Die Seite im Buch baut
-- ezCore (Core.NewSpellbookView, in Blizzards Optik); ezCombat liefert die Zeilen und Texte. Platz: im Seitenreiter-
-- Stapel des Zauberbuchs mit der Zahl 30, unter ezMerchant „Was kommt wann“ (10) und ezMacro „Ränge aktualisieren“ (20)
-- (Gesamtreview 18.11.2026, T16-4; vorher fest y −158 – TAB_Y bleibt als alter Wunschplatz).
--
-- Zwei Ansichten (Book.Lines; Entscheidung des Nutzers vom 16.11.2026, „Frage 2: Entwurf A“): ab Werk der Spickzettel
-- (Book.EasyLines, Beschreibung bei der Funktion), unten unter „Rotation ändern“ die Liste aller Schritte
-- (Book.EditLines, mit Ein/Aus und Pfeilen für jede Variante) – gemerkt je Charakter (Book.Editing,
-- ezCombatDB.rotationBookEdit). Seit dem Spielbefund vom 19.11.2026 (Bild 39, „anpassen bei rotationen ist unnötig“)
-- und der Entscheidung des Nutzers vom 20.11.2026 („Klick tauscht, Ziehen schiebt (Empfohlen)“) wird direkt auf beiden
-- Ansichten bearbeitet: Klick auf einen Schritt tauscht die Fähigkeit (Book.StepMenu), Ziehen ändert die Reihenfolge
-- (Book.Drop), Rechtsklick schaltet aus – nur außerhalb des Kampfes (Book.Locked). Der Knopf „Anpassen“ oben entfiel;
-- „Erstellen“ neben „Andere wählen“ legt eine eigene Rotation an. Eigene Rotationen (Kopie einer Vorlage) baut
-- RotationOwn.lua.
--
-- Aufbau der Seite zum Anpassen von oben nach unten (Book.EditLines):
--   0. „Fertig“ – zurück zum Spickzettel.
--   1. „Rotation wählen“ – oben auf Seite 1: „Nach Talentbaum“ und jede Rotation der Klasse (berechnete zuerst,
--      mit „berechnet“; gibt es keine, eine Zeile, was fehlt und wie sie entstehen). Genau ein Eintrag
--      ist aktiv (Feld active, volle Farbe, „Aktiv“); alle anderen sind grau und sagen „Klicken: wählen“. Ist „Nach
--      Talentbaum“ gewählt, ist dieser Eintrag aktiv und nennt, welche Rotation er gerade nimmt.
--   2. Kopf mit dem Namen der gezeigten Rotation, rechts „angepasst“, wenn sie von der Vorlage abweicht.
--   3. Erklärung in Sätzen (how) und Hinweis (note); bei einer berechneten Rotation (Welle 21) dazu die Herkunft:
--      berechnet am, für welche Talentverteilung, Annahmen, Quelle der Werte.
--   4. „Eigene Anpassungen: n“ mit dem Knopf „Zurück zur Vorlage“.
--   5. Die Abschnitte in fester Folge, nur die mit Schritten: Vor dem Kampf · Eröffnung · Im Kampf · Abklingzeiten ·
--      Mehrere Gegner (mit Knopf für den Flächenmodus) · Situativ.
--   6. Je Schritt ein Eintrag: Nummer (Rangfolge), Symbol und Name vom Client, Bedingung in Worten, Zustand
--      (Jetzt dran / Fehlt / Liegt / Noch nicht gelernt / Aus / gezählt …); rechts die Knöpfe Ein/Aus, Hoch, Runter.
--      Varianten desselben Zaubers, deren feste Bedingung für diesen Charakter nicht gilt, stehen nicht als eigener
--      Eintrag (Book.Folded; Spieltest 15.11.2026, „2x hintereinander der selbe segen“).
--      Eigene Rotation: alle sechs Abschnitte, je mit „Schritt hinzufügen“; ein Klick auf einen Schritt wählt seine
--      Bedingung (Menü), selbst hinzugefügte tragen ein Kreuz zum Entfernen statt des Kästchens.
--   6b. „Eigene Rotation“: Als eigene Rotation speichern; bei einer eigenen Umbenennen, Als Text teilen, Löschen; Aus
--      Text übernehmen.
--   7. Quelle(n): Klick zeigt den Link zum Kopieren.
-- Ein Klick auf eine andere Rotation wählt sie (gemerkt je Charakter) und zeigt sofort ihren Inhalt.
--
-- Knöpfe: Die Zeilen tragen sie als Daten (buttons = { … } am Eintrag, kind = "action" für eine Zeile mit Knopf);
-- ezCores Zauberbuch-Ansicht zeichnet sie selbst (opts.buttons = true, Core.SpellbookView.NATIVE_BUTTONS; CB-36) –
-- nur eigene Rahmen, nichts Geschütztes; ein Knopf ruft nur Book.Button und wirkt nie einen Zauber. Zeilengrenzen
-- der Einträge, Abstand zur nächsten Spalte bzw. zur Knopfspalte, Höhe der Absätze und die Seite des Tooltips kommen
-- ebenfalls aus ezCores Ansicht (CB-12).
local Book = {}
ns.RotationBook = Book

local KEY = "ezCombat.rotation"
local TAB_Y = -158
local TAB_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local SOURCE_ICON = "Interface\\Icons\\INV_Misc_Note_01"
local AUTO_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local REMOVE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"   -- Kreuz: selbst hinzugefügten Schritt entfernen
local SEP = " · "
local MENU_CHUNK = 20   -- Zauber je Untermenü in „Schritt hinzufügen“

local view          -- Core.NewSpellbookView, angelegt beim Einloggen
local chooserOpen = false       -- Spickzettel: Liste „Andere wählen“ aufgeklappt (bis zur Wahl bzw. zum Schließen)
local unlearnedOpen = false     -- Spickzettel: „Noch nicht gelernt“ aufgeklappt
local offOpen = false           -- Spickzettel: „Ausgeschaltet“ aufgeklappt

local function CharKey() return Core.charKey or "?" end

-- Spickzettel oder Seite zum Anpassen? Gemerkt je Charakter (ezCombatDB.rotationBookEdit[Charakter] = true).
function Book.Editing()
    local saved = ns.db and type(ns.db.rotationBookEdit) == "table" and ns.db.rotationBookEdit[CharKey()]
    return saved == true
end

-- Umschalter „Anpassen“ / „Fertig“. → true, wenn sich etwas geändert hat
function Book.SetEditing(on)
    on = on and true or false
    if not ns.db or Book.Editing() == on then return false end
    ns.db.rotationBookEdit = type(ns.db.rotationBookEdit) == "table" and ns.db.rotationBookEdit or {}
    ns.db.rotationBookEdit[CharKey()] = on or nil
    if next(ns.db.rotationBookEdit) == nil then ns.db.rotationBookEdit = nil end
    chooserOpen = false
    return true
end

---------------------------------------------------------------------------
-- Texte: Bedingung in Worten
---------------------------------------------------------------------------

-- Text mit Werten füllen, ohne je zu werfen (ein falscher Wert in den Daten darf die Seite nicht leeren).
local function Fmt(text, ...)
    local ok, result = pcall(string.format, text, ...)
    return ok and result or text
end

-- Name zu einer Zauber-ID, einem Buff-Schlüssel, einer Wahlgruppe oder einer Familie aus ezCore.Spells – immer der
-- Name, den der Client für den Zauber kennt.
local function SpellLabel(value)
    if type(value) == "number" then return ns.SpellName(value) or ("#" .. value) end
    if type(value) ~= "string" then return "?" end
    local key = Spells.IsBuff(value) and value or nil
    if not key then
        local group = Spells.BuffGroup(value, ns.playerClass)
        key = group and (Spells.ChooseBuff(value, { class = ns.playerClass }) or group.keys[1])
    end
    local spells = key and Spells.BuffField(key, "spells")
    if type(spells) == "table" and spells[1] then
        return ns.SpellName(spells[1]) or value
    end
    local ids = Spells.Family(value)
    if ids and ids[1] then
        local first = ns.SpellName(ids[1]) or value
        return #ids > 1 and (first .. " …") or first
    end
    return value
end

local function SpellList(value)
    if type(value) ~= "table" then return SpellLabel(value) end
    local names = {}
    for index, one in ipairs(value) do
        if index > 3 then
            names[#names + 1] = "…"
            break
        end
        names[#names + 1] = SpellLabel(one)
    end
    return table.concat(names, ", ")
end

local function Flag(key)
    return function(value) return L["ROTATION_NEED_" .. key .. (value and "_true" or "_false")] end
end

local function Named(key)
    return function(value) return Fmt(L["ROTATION_NEED_" .. key], SpellList(value)) end
end

local function Range(minKey, maxKey)
    return function(value)
        if type(value) ~= "table" then return nil end
        local parts = {}
        if value.min then parts[#parts + 1] = Fmt(L[minKey], value.min) end
        if value.max then parts[#parts + 1] = Fmt(L[maxKey], value.max) end
        return table.concat(parts, ", ")
    end
end

local function AuraNeed(key)
    return function(value)
        local id = value
        if type(value) == "table" and value.id ~= nil then id = value.id end
        local text = Fmt(L["ROTATION_NEED_" .. key], SpellList(id))
        if type(value) == "table" and value.min then text = text .. " (" .. Fmt(L.ROTATION_STACKS, value.min) .. ")" end
        return text
    end
end

-- Kurzform je weiterer Bedingung (need = { … }); Reihenfolge wie Rotation.NEED_ORDER.
local NEED_TEXT = {
    combat = Flag("combat"),
    target = function() return L.ROTATION_NEED_target end,
    solo = function(value) return value and L.ROTATION_NEED_solo or L.ROTATION_NEED_grouped end,
    grouped = function(value) return value and L.ROTATION_NEED_grouped or L.ROTATION_NEED_solo end,
    leveling = Flag("leveling"),
    level = function(value)
        if type(value) ~= "table" then return nil end
        if value.min and value.max then return Fmt(L.ROTATION_NEED_level, value.min, value.max) end
        if value.min then return Fmt(L.ROTATION_NEED_level_min, value.min) end
        if value.max then return Fmt(L.ROTATION_NEED_level_max, value.max) end
        return nil
    end,
    known = Named("known"),
    unknown = Named("unknown"),
    seen = Named("seen"),
    aoe = Flag("aoe"),
    stealth = Flag("stealth"),
    pet = Flag("pet"),
    form = Named("form"),
    weapon = function() return L.ROTATION_NEED_weapon end,
    item = function(value) return Fmt(L.ROTATION_NEED_item, type(value) == "table" and value.min or 1) end,
    queued = function() return L.ROTATION_NEED_queued end,
    usable = Named("usable"),
    unusable = Named("unusable"),
    moving = Flag("moving"),
    inrange = Named("inrange"),
    outrange = Named("outrange"),
    enemy = function(value)
        if type(value) ~= "table" then return nil end
        local parts = {}
        if value.rank then parts[#parts + 1] = L.ROTATION_NEED_enemy_rank end
        if value.norank then parts[#parts + 1] = L.ROTATION_NEED_enemy_norank end
        if value.type then parts[#parts + 1] = L.ROTATION_NEED_enemy_type end
        return table.concat(parts, ", ")
    end,
    totem = function(value)
        local up = not (type(value) == "table" and value.up == false)
        return up and L.ROTATION_NEED_totem_up or L.ROTATION_NEED_totem_down
    end,
    counter = function() return L.ROTATION_NEED_counter end,
    cp = Range("ROTATION_CP", "ROTATION_NEED_cp_max"),
    rage = Range("ROTATION_NEED_rage_min", "ROTATION_NEED_rage_max"),
    energy = Range("ROTATION_NEED_energy_min", "ROTATION_NEED_energy_max"),
    mana = Range("ROTATION_NEED_mana_min", "ROTATION_NEED_mana_max"),
    aura = AuraNeed("aura"),
    noaura = AuraNeed("noaura"),
}

-- Kurztext einer einzelnen weiteren Bedingung („nur im Kampf“, „ab 30 Wut“, „wenn Schattentrance liegt“).
function Book.NeedText(key, value)
    local fn = NEED_TEXT[key]
    local text = fn and fn(value)
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

-- Dauer eines Dauer-Buffs in Worten: „hält 30 min“ (vom Client gelernt) bzw. „hält etwa 30 min“ (Rückfall aus
-- ezCores Buff-Wissen, solange der Client die Dauer noch nicht gezeigt hat). nil, wenn beides fehlt.
-- Maßgeblich ist der Zauber, den die Zeile zeigt (bei einer Wahlgruppe der gewählte Buff der eigenen Klasse, z. B.
-- auf Stufe 10 Dämonenhaut statt Dämonenrüstung); jeder Rang zählt.
local function DurationText(step)
    local shownID = Rotation.StepSpell(step)
    local minutes, source
    local seconds = Spells.AuraSeconds(shownID)
    if seconds then minutes, source = seconds / 60, "aura" end
    if not minutes then
        local group, own = Rotation.BuffOf(step)
        local key = (type(shownID) == "number" and Spells.BuffKey(shownID)) or own or group
        if key then minutes, source = Spells.BuffMinutes(key) end
    end
    if not minutes then
        seconds = Spells.AuraSeconds(step.aura or step.id)
        if seconds then minutes, source = seconds / 60, "aura" end
    end
    if not minutes then return nil end
    minutes = math.floor(minutes + 0.5)
    if minutes < 1 then return nil end
    return Fmt(source == "fallback" and L.ROTATION_MINUTES_FALLBACK or L.ROTATION_MINUTES, minutes)
end

-- Bedingung eines Schritts in Worten („Fehlt oder läuft aus (Ziel) · erst nach Ablauf“, „Ab 40 Wut“, „Bei Aufwärmen
-- · 3 Stapel“, „Dauer-Buff fehlt oder läuft bald aus · hält 30 min“): when, Dauer, refresh, once, Stapel,
-- Combo-Punkte und jede weitere Bedingung (need).
function Book.ConditionText(step)
    local when = step.when or "ready"
    local parts = {}
    local text
    if when == "proc" then
        local key = step.unit == "target" and "ROTATION_WHEN_proc_TARGET" or "ROTATION_WHEN_proc"
        text = Fmt(L[key], step.aura and ns.SpellName(step.aura) or "?")
    elseif when == "buff" and Rotation.KindOf(step) == "longbuff" then
        text = L.ROTATION_WHEN_longbuff
    elseif (when == "dot" or when == "buff") and step.aura and ns.SpellName(step.aura) then
        text = Fmt(L["ROTATION_WHEN_" .. when .. "_AURA"], ns.SpellName(step.aura))
    elseif when == "finisher" then
        text = Fmt(L.ROTATION_WHEN_finisher, step.cp or 5)
    elseif when == "rage" or when == "energy" or when == "mana" then
        text = Fmt(L["ROTATION_WHEN_" .. when], step.min or 0)
    elseif when == "lowmana" then
        text = Fmt(L.ROTATION_WHEN_lowmana, step.max or 100)
    elseif when == "enchant" then
        text = step.hand == "off" and L.ROTATION_WHEN_enchant_off or L.ROTATION_WHEN_enchant_main
    elseif when == "item" then
        text = Fmt(L.ROTATION_WHEN_item, step.min or 1)
    elseif when == "totemslot" then
        local slot = tonumber(step.slot)
        text = Fmt(L.ROTATION_WHEN_totemslot, slot and slot >= 1 and slot <= 4 and L["ROTATION_TOTEM_" .. slot] or "?")
    else
        local key = "ROTATION_WHEN_" .. tostring(when)
        text = L[key]
        if text == key then text = "" end       -- unbekannte Bedingung: kein Schlüssel als Text
    end
    if text ~= "" then parts[#parts + 1] = text end
    if Rotation.KindOf(step) == "longbuff" then
        local duration = DurationText(step)
        if duration then parts[#parts + 1] = duration end
    end
    if step.refresh == "missing" then
        parts[#parts + 1] = L.ROTATION_REFRESH_missing
    elseif step.refresh == "cast" then
        parts[#parts + 1] = L.ROTATION_REFRESH_cast
    elseif type(step.refresh) == "number" then
        parts[#parts + 1] = Fmt(L.ROTATION_REFRESH_seconds, step.refresh)
    end
    if step.once == "target" then
        parts[#parts + 1] = L.ROTATION_ONCE_target
    elseif step.once == "combat" then
        parts[#parts + 1] = L.ROTATION_ONCE_combat
    end
    if step.mine == false then parts[#parts + 1] = L.ROTATION_ANYSOURCE end
    if step.stacks then parts[#parts + 1] = Fmt(L.ROTATION_STACKS, step.stacks) end
    if step.cp and when ~= "finisher" then parts[#parts + 1] = Fmt(L.ROTATION_CP, step.cp) end
    if type(step.need) == "table" then
        for _, key in ipairs(Rotation.NEED_ORDER) do
            if step.need[key] ~= nil then
                local needText = Book.NeedText(key, step.need[key])
                if needText then parts[#parts + 1] = needText end
            end
        end
    end
    if Rotation.IsBurst(step) then
        parts[#parts + 1] = L["ROTATION_CD_" .. (ns.S and ns.S.rotationCooldowns or "always")]
    end
    if step.race then table.insert(parts, 1, L.ROTATION_RACIAL) end
    return table.concat(parts, SEP)
end

---------------------------------------------------------------------------
-- Zustand eines Schritts
---------------------------------------------------------------------------

-- „Noch nicht gelernt“, mit der Lernstufe, wenn der Client sie kennt und sie noch vor dem Spieler liegt.
local function UnlearnedText(id)
    local level = Spells.LevelLearned(id)
    local mine = Core.PlayerLevel and Core.PlayerLevel() or nil
    if level and (not mine or level > mine) then return Fmt(L.ROTATION_STATE_LEARN_AT, level) end
    return L.ROTATION_BOOK_UNKNOWN
end

-- Was der Eintrag eines Schritts zeigt: Zauber-ID, Name, gelernt. Steht der Schritt für eine Wahlgruppe (buff =
-- "armor"), ist es der gewählte Buff; nennt er einen bestimmten Buff, bleibt es dieser – wird er von einem anderen
-- der Gruppe abgelöst, steht das als Zustand (replacedBy = Name des gewählten).
local function Shown(entry)
    local step = entry.step
    local _, own = Rotation.BuffOf(step)
    if own then
        local chosen, chosenSpell = Spells.ChooseBuff(own, { prefer = own, class = ns.playerClass })
        if chosen ~= own then
            local spells = Spells.BuffField(own, "spells")
            local ownID = type(spells) == "table" and spells[1] or step.id
            local name = ns.SpellName(ownID)
            local known = name ~= nil and ((Spells.Known(name) and true) or Spells.IsKnown(ownID) == true)
            return { id = known and Spells.Highest(ownID) or ownID, name = name, known = known,
                replacedBy = known and chosenSpell and ns.SpellName(chosenSpell) or nil }
        end
    end
    return { id = entry.id, name = entry.name, known = entry.known }
end

-- Die nächste Aktion aus Rotation.state: Schritt (eigene Rotation) bzw. Name (Blizzards Assistent), dazu die
-- Schritte, die gerade nebenher laufen.
local function NextInfo()
    local state = Rotation.state or {}
    local info = { side = {} }
    if state.source == "rotation" then
        info.step, info.id, info.counted = state.step, state.id, state.counted == true
    elseif state.source == "blizzard" then
        info.name = state.name
    end
    for _, step in ipairs(state.side or {}) do info.side[step] = true end
    return info
end

local function IsNext(info, entry, shown)
    if info.found then return false end
    local step = entry.step
    local hit
    if info.step then
        hit = info.step == step
    elseif info.id then
        hit = info.id == step.id
    elseif info.name then
        hit = shown.name ~= nil and info.name == shown.name
    end
    if hit then info.found = true end
    return hit == true
end

-- Zustand eines Schritts, erste zutreffende Regel: Aus · Ersetzt/Noch nicht gelernt · Jetzt dran (nebenher – jetzt)
-- · Vor dem Kampf: Fehlt / Läuft aus / Nicht lesbar / Liegt / Vorhanden · Erledigt · Flächenmodus aus / Nur Liste.
-- Rückgabe: Text (leer = nichts zu sagen), Kennung für Tests und andere Module.
function Book.StepState(entry, section, shown, ctx, info)
    local step = entry.step
    if not entry.enabled then
        return entry.optional and L.ROTATION_STATE_OPTIONAL_OFF or L.ROTATION_STATE_OFF, "off"
    end
    if shown.replacedBy then return Fmt(L.ROTATION_STATE_REPLACED, shown.replacedBy), "replaced" end
    if not shown.known then return UnlearnedText(shown.id), "unlearned" end
    local suggestible = Rotation.Suggestible(step)
    if section ~= "prep" and suggestible then
        if step.side and info.side[step] then return L.ROTATION_STATE_SIDE_NOW, "side" end
        if IsNext(info, entry, shown) then
            local text = L.ROTATION_BOOK_NOW
            if info.counted then text = text .. SEP .. L.ROTATION_STATE_COUNTED end
            return text, "now"
        end
    end
    if not suggestible then return L.ROTATION_STATE_LISTONLY, "listonly" end
    if section == "prep" then
        if entry.kind == "longbuff" then
            local state, _, _, needFalse = Rotation.PrepState(step, ctx)
            if state == "missing" or state == "nopower" then return L.ROTATION_STATE_MISSING, "missing" end
            if state == "expiring" then return L.ROTATION_STATE_EXPIRING, "expiring" end
            if state == "unknown" then return L.ROTATION_STATE_UNREAD, "unread" end
            if state == "ok" and not needFalse then return L.ROTATION_STATE_UP, "up" end
            return "", ""
        end
        local due, why = Rotation.StepDue(step, ctx)
        if due == true then return L.ROTATION_STATE_MISSING, "missing" end
        if due == nil then return L.ROTATION_STATE_UNREAD, "unread" end
        if why == "done" then return L.ROTATION_STATE_DONE, "done" end
        if why == nil then return L.ROTATION_STATE_READY, "ready" end
        return "", ""
    end
    if step.once and State.Done(entry.key) then
        return step.once == "combat" and L.ROTATION_STATE_DONE_COMBAT or L.ROTATION_STATE_DONE, "done"
    end
    if step.kind ~= nil then        -- Altschritte laufen ohne diese Tore
        if section == "aoe" and not Rotation.Aoe() then return L.ROTATION_STATE_AOE_OFF, "aoeoff" end
        if section == "cooldown" and Rotation.IsBurst(step) and ns.S and ns.S.rotationCooldowns == "never" then
            return L.ROTATION_STATE_LISTONLY, "listonly"
        end
    end
    return "", ""
end

---------------------------------------------------------------------------
-- Zeilen (Felder von Core.NewSpellbookView, siehe docs/ezcore.md)
---------------------------------------------------------------------------

-- Seite einer Quelle für die Liste („www.wowhead.com“).
local function Host(url)
    return type(url) == "string" and url:match("^https?://([^/]+)") or ""
end

-- Symbol einer Rotation in der Auswahl: der erste Kampfschritt (sonst stünde überall derselbe Dauer-Buff).
local function RotationIcon(rotation)
    local first
    for _, step in ipairs(rotation.steps or {}) do
        local id = Rotation.StepSpell(step)
        first = first or id
        if Rotation.SectionOf(step) ~= "prep" and Rotation.Suggestible(step) and step.when ~= "buff" then
            return Spells.Icon(id)
        end
    end
    return first and Spells.Icon(first) or nil
end

-- Absatz: Seine Höhe schätzt ezCores Ansicht aus dem Text (SV.TextHeight, mit der wahren Seitenbreite).
local function TextLine(text, field)
    local line = { kind = "text", left = text }
    line[field] = true
    return line
end

-- Zeile mit einem Knopf (key für Book.Button): Text darüber, Beschriftung, Tooltip; Höhe aus ezCores Ansicht.
local function ActionLine(key, text, button, tip, disabled)
    return { kind = "action", left = text, button = button, key = key, tip = tip, disabled = disabled and true or false }
end

-- Alle Quellen einer Rotation: die Hauptquelle, dann die weiteren Seiten (ohne Doppelte).
local function Sources(rotation)
    local list, seen = {}, {}
    local function Add(url)
        if type(url) == "string" and url ~= "" and not seen[url] then
            seen[url] = true
            list[#list + 1] = url
        end
    end
    Add(rotation.source)
    for _, url in ipairs(type(rotation.sources) == "table" and rotation.sources or {}) do Add(url) end
    return list
end

-- Tooltip-Zeile in einer Farb-Rolle des Design-Systems (Core.Style).
local function Tip(text, role)
    local r, g, b = Core.Style.Color(role)
    return { text, r, g, b, true }
end

-- Wortlaut, mit dem tools/rotation_sim.lua den Satz eines berechneten Schritts ergänzt („Teilt die Abklingzeit mit {ID}.“,
-- verlangt vom Daten-Lint, Punkt 14). Nennt der Satz eines Schritts damit einen Zauber derselben Kategorie, steht die
-- geteilte Abklingzeit schon im Tooltip (Gegenprüfung Welle 26: sonst doppelt); die Quelle nennt dann die Annahme der
-- Rotation („geteilte Abklingzeiten laut Client-Tabellen …“). Gilt auch für eigene Kopien berechneter Rotationen.
Book.SHARED_SENTENCE = { "Teilt die Abklingzeit mit {%d}", "Shares its cooldown with {%d}" }

function Book.SentenceNamesShared(step, spellID)
    local text = type(step) == "table" and step.text
    if type(text) == "string" then text = { text } end
    if type(text) ~= "table" or not spellID or not ns.SharedCooldownSpells then return false end
    for _, other in ipairs(ns.SharedCooldownSpells(spellID, true)) do
        for _, pattern in ipairs(Book.SHARED_SENTENCE) do
            local needle = pattern:format(other.id)
            for _, one in pairs(text) do
                if type(one) == "string" and one:find(needle, 1, true) then return true end
            end
        end
    end
    return false
end

-- Geteilte Abklingzeit eines Schritts (Welle 26, F10): „Teilt die Abklingzeit mit … – laut Client-Tabellen (…).“ an
-- den Tooltip hängen (Spickzettel und Seite zum Anpassen; nur gelernte Zauber derselben Kategorie, ns.SharedCooldownText).
-- Nicht, wenn der Satz des Schritts sie schon nennt (Book.SentenceNamesShared).
local function AddSharedTip(tooltip, spellID, step)
    if step and Book.SentenceNamesShared(step, spellID) then return end
    local text = spellID and ns.SharedCooldownText and ns.SharedCooldownText(spellID)
    if text then tooltip[#tooltip + 1] = Tip(text, "highlight") end
end
Book.AddSharedTip = AddSharedTip

-- Bearbeiten direkt auf der Seite (Entscheidung des Nutzers vom 20.11.2026, „Klick tauscht, Ziehen schiebt“): der
-- Tooltip eines Schritts nennt Klick (Fähigkeit tauschen; eigene Rotation: auch die Bedingung), Ziehen (Reihenfolge im
-- selben Abschnitt, mit dessen Namen – auf dem Spickzettel sind die Abschnitte sonst nicht zu sehen) und – im Kampf –
-- die Sperre. Die Hinweise stehen im breiten Tooltip als ein Block ohne Leerzeilen (join, ezCores AddTipLines);
-- Rechtsklick bzw. Entfernen hängt der Aufrufer mit Book.JoinTip an.
function Book.JoinTip(tip)
    tip.join = true
    return tip
end

function Book.AddEditTips(tooltip, own, sectionKey)
    tooltip[#tooltip + 1] = Tip(ns.ClickText(own and L.ROTATION_STEP_CLICK_OWN_TIP or L.ROTATION_STEP_CLICK_TIP, "left"),
        "good")
    local section = sectionKey and L["ROTATION_SECTION_" .. sectionKey] or "?"
    tooltip[#tooltip + 1] = Book.JoinTip(Tip(Fmt(L.ROTATION_STEP_DRAG_TIP, section), "good"))
    if ns.InCombat() then
        tooltip[#tooltip + 1] = Book.JoinTip(Tip(Core.CombatText(L.ROTATION_STEP_EDIT_WHAT), "bad"))
    end
    return tooltip
end

-- Einträge der Auswahl: „Nach Talentbaum“ und jede Rotation der Klasse. Genau einer ist aktiv. Berechnete Rotationen
-- (Welle 21) tragen „berechnet“ und im Tooltip ihre Herkunft; gibt es für die Klasse keine, sagt eine Zeile, was fehlt
-- und wie sie entstehen (Leitlinie 11) – solange der Schalter „Berechnete Rotationen zeigen“ an ist.
local function ChoiceLines(lines, list, rotation, choice)
    local auto = choice == "auto"
    local default = Rotation.Default()
    local defaultName = Rotation.Name(default)
    -- Der Tooltip nennt zuerst, was „Nach Talentbaum“ nimmt – auf der Seite kann der Text gekürzt sein.
    local autoTakes = Fmt(auto and L.ROTATION_BOOK_AUTO_ACTIVE or L.ROTATION_BOOK_AUTO_WOULD, defaultName)
    lines[#lines + 1] = { kind = "spell", name = L.ROTATION_AUTO,
        sub = (not auto) and autoTakes or nil,
        detail = auto and autoTakes or ns.ClickText(L.ROTATION_BOOK_PICK),
        icon = AUTO_ICON, title = L.ROTATION_AUTO, style = auto and "known" or "future",
        tooltip = { Tip(autoTakes, "normal"), Tip(L.OPT_rotationChoice_TIP, "highlight"),
            (not auto) and Tip(ns.ClickText(L.ROTATION_BOOK_PICK_TIP), "good") or nil },
        choose = "auto", active = auto, tipWide = true }
    for _, other in ipairs(list) do
        local active = choice == other.key
        local detail = ns.ClickText(L.ROTATION_BOOK_PICK)
        if active then
            detail = L.ROTATION_BOOK_ACTIVE
        elseif auto and other == rotation then
            detail = ns.ClickText(L.ROTATION_BOOK_PICK_FIXED)         -- die nimmt „Nach Talentbaum“ gerade: fest wählen
        end
        local sub = Fmt(L.ROTATION_BOOK_TREE, other.tree or 0)
        local computed = Rotation.IsComputed(other)
        if computed then
            sub = sub .. SEP .. (other.computed.provisional and L.ROTATION_BOOK_PROVISIONAL or L.ROTATION_BOOK_COMPUTED)
        end
        if Rotation.IsEdited(other) then sub = sub .. SEP .. L.ROTATION_BOOK_EDITED end
        local tooltip = {}
        local how = Rotation.How(other)
        if how then tooltip[#tooltip + 1] = Tip(how, "normal") end
        for _, text in ipairs(Rotation.ComputedLines(other)) do tooltip[#tooltip + 1] = Tip(text, "highlight") end
        if not active then tooltip[#tooltip + 1] = Tip(ns.ClickText(L.ROTATION_BOOK_PICK_TIP), "good") end
        lines[#lines + 1] = { kind = "spell", name = Rotation.Name(other), sub = sub, detail = detail,
            icon = RotationIcon(other), title = Rotation.Name(other), style = active and "known" or "future",
            tooltip = tooltip, choose = other.key, active = active, tipWide = true }
    end
    if Rotation.ComputedShown() then
        local any = false
        for _, other in ipairs(list) do any = any or Rotation.IsComputed(other) end
        if not any then lines[#lines + 1] = TextLine(L.ROTATION_BOOK_COMPUTED_NONE, "computedNone") end
    end
end

-- Eintrag eines Schritts mit seinen Knöpfen (Ein/Aus, Hoch, Runter – am Rand des Abschnitts grau). Untereinander am
-- rechten Rand: Pfeil hoch oben, Kästchen in der Mitte, Pfeil runter unten (place). rank: Nummer auf der Seite
-- (Book.VisibleSteps), index und count: Platz unter den gezeigten Einträgen des Abschnitts.
local function StepLine(rotation, section, entry, index, count, ctx, info, rank)
    local step = entry.step
    local shown = Shown(entry)
    local label = shown.name or ("#" .. tostring(shown.id))
    -- Erst der Zustand (liest die Auren; dabei merkt ezCore die Dauer vom Client), dann die Bedingung mit dieser Dauer
    local state, stateKey = Book.StepState(entry, section.key, shown, ctx, info)
    local condition = Book.ConditionText(step)
    local lit = entry.enabled and shown.known and not shown.replacedBy
    -- Tooltip: Erklärung, die ganze Bedingung und der Zustand – auf der Seite sind sie auf wenige Zeilen gekürzt.
    local own = Rotation.IsOwn(rotation)
    local added = own and step.added == true
    local tooltip = { Tip(Rotation.StepText(step), "normal"), Tip(condition, "highlight") }
    if Rotation.StepText(step) == "" then tooltip[1] = Tip(Book.EasyText(step), "normal") end
    if shown.known then AddSharedTip(tooltip, shown.id, step) end
    if state ~= "" then tooltip[#tooltip + 1] = Tip(state, "blue") end   -- Zustand (vorher STATE_COLOR, T9-6)
    -- Klick: Menü zum Tauschen (eigene Rotation: dazu die Bedingung), Ziehen: Reihenfolge; selbst hinzugefügte
    -- Schritte entfernt das Kreuz
    Book.AddEditTips(tooltip, own, section.key)
    -- selbst hinzugefügt bzw. getauscht: Kreuz statt Kästchen, Rechtsklick schaltet trotzdem aus und ein
    if added then
        tooltip[#tooltip + 1] = Book.JoinTip(Tip(L.ROTATION_OWN_REMOVE_TIP, "good"))
        tooltip[#tooltip + 1] = Book.JoinTip(Tip(ns.ClickText(L.ROTATION_STEP_TOGGLE_TIP, "right"), "good"))
    else
        tooltip[#tooltip + 1] = Book.JoinTip(Tip(L.ROTATION_BOOK_TOGGLE_TIP, "good"))
    end
    local first = { key = "toggle", check = entry.enabled and true or false, title = label, place = "CENTER",
        tip = ns.ClickText(entry.enabled and L.ROTATION_BTN_TOGGLE_ON_TIP or L.ROTATION_BTN_TOGGLE_OFF_TIP) }
    if added then
        first = { key = "remove", texture = REMOVE_ICON, disabledTexture = REMOVE_ICON, title = label, place = "CENTER",
            tip = L.ROTATION_OWN_REMOVE_TIP }
    end
    return { kind = "spell", name = (rank and (rank .. ". ") or "– ") .. label, sub = condition,
        detail = state, icon = Spells.Icon(shown.id), spellID = shown.id, title = label,
        style = lit and "known" or "future",
        tooltip = tooltip, tipWide = true, drag = true,
        buttons = {
            first,
            { key = "up", arrow = "Up", place = "TOP", title = label, tip = ns.ClickText(L.ROTATION_BTN_UP_TIP),
                disabled = index == 1 },
            { key = "down", arrow = "Down", place = "BOTTOM", title = label, tip = ns.ClickText(L.ROTATION_BTN_DOWN_TIP),
                disabled = index == count },
        },
        step = step, stepKey = entry.key, rotation = rotation.key, section = section.key, rank = rank,
        state = stateKey, enabled = entry.enabled, own = own, added = added }
end

---------------------------------------------------------------------------
-- Varianten eines Schritts zusammenfassen (Spieltest des Nutzers vom 15.11.2026: „beim paladin 2x hintereinander der
-- selbe segen“). Manche Vorlagen führen denselben Zauber zweimal, je mit einer festen Bedingung, die sich ausschließt
-- (Aura der Hingabe „auf Höchststufe“ und „beim Leveln, solange Aura der Vergeltung fehlt“; Arkaner Schuss mit und
-- ohne „beim Leveln“). Für einen Charakter gilt davon höchstens eine; die Seite zeigte trotzdem beide untereinander.
-- Jetzt steht ein Schritt, dessen feste Bedingung für diesen Charakter sicher nicht gilt, nicht als eigener Eintrag,
-- wenn im selben Abschnitt ein geltender Schritt denselben Zauber zeigt. Die Vorlage, Anpassungen (aus, Reihenfolge)
-- und die Auswertung bleiben unverändert; die Nummern auf der Seite zählen nur die gezeigten Einträge.
-- Gelten zwei Varianten zugleich (ein ODER über zwei Schritte: Klaue „solange Wilder Biss fehlt“ und „beim Leveln“ auf
-- Stufe 30) und gleicht sich ihre Kampfbedingung, steht der Zauber ebenfalls einmal (Gegenprüfung vom 15.11.2026).
---------------------------------------------------------------------------

-- Feste Bedingungen: hängen nur an Stufe und Gelerntem, nicht an Kampf, Ziel oder Auren.
Book.STATIC_NEED = { "leveling", "level", "known", "unknown" }

-- Gilt die feste Bedingung eines Schritts für diesen Charakter? false nur, wenn eine davon sicher nicht gilt
-- (unbekannt zählt als „gilt“ – dann bleibt der Eintrag sichtbar).
function Book.StaticApplies(step)
    local need = type(step) == "table" and step.need
    if type(need) ~= "table" then return true end
    for _, key in ipairs(Book.STATIC_NEED) do
        local fn = need[key] ~= nil and Rotation.CHECKS[key]
        if fn then
            local ok, result = pcall(fn, need[key], step, {})
            if ok and result == false then return false end
        end
    end
    return true
end

-- Hat der Schritt eine feste Bedingung (Book.STATIC_NEED)?
local function HasStaticNeed(step)
    local need = type(step) == "table" and step.need
    if type(need) ~= "table" then return false end
    for _, key in ipairs(Book.STATIC_NEED) do
        if need[key] ~= nil then return true end
    end
    return false
end

-- Bedingung eines Schritts ohne die festen Teile (Book.STATIC_NEED), in Worten wie Book.ConditionText: Zwei Schritte
-- mit demselben Zauber und derselben Kampfbedingung unterscheiden sich für den Spieler nur in Stufe bzw. Gelerntem.
function Book.CombatCondition(step)
    if not HasStaticNeed(step) then return Book.ConditionText(step) end
    local static = {}
    for _, key in ipairs(Book.STATIC_NEED) do static[key] = true end
    local copy, need, any = {}, {}, false
    for key, value in pairs(step) do copy[key] = value end
    for key, value in pairs(step.need) do
        if not static[key] then need[key], any = value, true end
    end
    copy.need = any and need or nil
    return Book.ConditionText(copy)
end

-- Zusammengefasste Schritte eines Abschnitts (aus Rotation.Sections): { [Schritt-Schlüssel] = true }. Gilt keine
-- Variante eines Zaubers (etwa Aura der Hingabe auf Stufe 30 mit gelernter Aura der Vergeltung), bleibt die erste
-- stehen – sonst stünde er zweimal da bzw. gar nicht. Gelten zwei Varianten mit fester Bedingung und gleicher
-- Kampfbedingung zugleich, bleibt die erste.
function Book.Folded(section)
    local folded, applies, shownBy, variants = {}, {}, {}, {}
    for index, entry in ipairs(section.steps or {}) do
        applies[index] = Book.StaticApplies(entry.step)
        if applies[index] and entry.name then
            shownBy[entry.name] = true
            if HasStaticNeed(entry.step) then
                local okText, text = pcall(Book.CombatCondition, entry.step)
                local same = okText and tostring(entry.name) .. "\0" .. tostring(text)
                if same and variants[same] then folded[entry.key] = true elseif same then variants[same] = true end
            end
        end
    end
    for index, entry in ipairs(section.steps or {}) do
        if not applies[index] and entry.name then
            if shownBy[entry.name] then folded[entry.key] = true end
            shownBy[entry.name] = true
        end
    end
    return folded
end

-- Die gezeigten Einträge eines Abschnitts mit ihrer Nummer auf der Seite. counters: { prep = n, next = n } –
-- übersprungene Nummern bisher (Vor dem Kampf zählt für sich, die übrigen Abschnitte durchgehend, wie
-- Rotation.Sections). → { { entry, rank } … }
function Book.VisibleSteps(section, counters)
    counters = counters or { prep = 0, next = 0 }
    local folded, list = Book.Folded(section), {}
    local counter = section.key == "prep" and "prep" or "next"
    for _, entry in ipairs(section.steps or {}) do
        if folded[entry.key] then
            if entry.rank then counters[counter] = counters[counter] + 1 end
        else
            list[#list + 1] = { entry = entry, rank = entry.rank and (entry.rank - counters[counter]) or nil }
        end
    end
    return list
end

-- Eine Stelle hoch bzw. runter unter den gezeigten Einträgen: Rotation.MoveStep tauscht mit dem nächsten Schritt des
-- Abschnitts; war der zusammengefasst (unsichtbar), geht es weiter, bis ein gezeigter überholt ist. → geändert?
function Book.MoveVisible(rotation, step, direction)
    local moved = false
    for _ = 1, 64 do
        local neighbor, folded
        for _, section in ipairs(Rotation.Sections(rotation)) do
            for index, entry in ipairs(section.steps) do
                if entry.step == step then
                    neighbor = section.steps[index + direction]
                    folded = Book.Folded(section)
                end
            end
        end
        if not Rotation.MoveStep(rotation, step, direction) then break end
        moved = true
        if not (neighbor and folded and folded[neighbor.key]) then break end
    end
    return moved
end

-- Herkunft einer eigenen Rotation in einem Satz („Eigene Rotation, nach Gebrechen (Leveln)“).
local function OwnOrigin(rotation)
    local own = rotation and rotation.own
    if type(own) ~= "table" then return nil end
    return Fmt(L.ROTATION_OWN_ORIGIN, own.fromName or own.from or "?")
end

-- Abschnitte zum Zeichnen: die Vorlage nur mit Schritten (Rotation.Sections); eine eigene Rotation zeigt alle
-- Abschnitte, auch leere – dort kommt der erste Schritt über „Schritt hinzufügen“ hinein.
local function PageSections(rotation)
    local sections = Rotation.Sections(rotation)
    if not Rotation.IsOwn(rotation) then return sections end
    local byKey, all = {}, {}
    for _, section in ipairs(sections) do byKey[section.key] = section end
    for _, key in ipairs(Rotation.SECTIONS) do
        all[#all + 1] = byKey[key] or { key = key, title = L["ROTATION_SECTION_" .. key], right = nil, steps = {} }
    end
    return all
end

-- Eigene Felder der Zeilen: chooser (Kopf der Auswahl); choose (Schlüssel einer Rotation oder "auto") und active
-- (genau eine Auswahlzeile); computedNone (noch keine berechnete Rotation, Welle 21);
-- rotation und edited (Kopf der Rotation); how, note, computed, origin (Absätze; computed: Herkunft einer berechneten,
-- origin: einer eigenen); key (Zeile mit Knopf: "done", "reset", "saveown", "rename", "export", "delete", "import",
-- "aoe", "add"); section (Kopf und Schritte eines Abschnitts); step, stepKey, rank, state, enabled, buttons, own, added
-- (Schritt); source (Link).
-- Die Seite zum Anpassen (bis Welle 23 die einzige Seite; seit dem Paket „Spickzettel“ hinter dem Knopf „Anpassen“,
-- Entscheidung des Nutzers vom 16.11.2026, Entwurf A): ganz oben „Fertig“ zurück zum Spickzettel.
function Book.EditLines()
    local lines = {}
    local list = Rotation.ForClass()
    if #list == 0 then
        lines[1] = { kind = "text", left = L.ROTATION_BOOK_NONE }
        return lines
    end
    local rotation = Rotation.Selected()
    local choice = Rotation.Choice()
    local own = Rotation.IsOwn(rotation)
    -- 0. Fertig: zurück zum Spickzettel
    lines[#lines + 1] = ActionLine("done", L.ROTATION_EDIT_DONE_LABEL, L.ROTATION_EDIT_DONE, L.ROTATION_EDIT_DONE_TIP)
    -- 1. Auswahl
    lines[#lines + 1] = { kind = "header", left = L.ROTATION_BOOK_CHOOSE, chooser = true }
    ChoiceLines(lines, list, rotation, choice)
    -- 2. Kopf der gezeigten Rotation
    local edits = Rotation.EditCount(rotation)
    local right = choice == "auto" and L.ROTATION_AUTO_SHORT or L.ROTATION_CHOSEN
    if own then right = L.ROTATION_OWN_SHORT end
    if edits > 0 then right = L.ROTATION_BOOK_EDITED end
    lines[#lines + 1] = { kind = "header", left = Rotation.Name(rotation), right = right, rotation = rotation.key,
        edited = edits > 0, own = own }
    -- 3. Erklärung und Hinweis
    local how = Rotation.How(rotation)
    if how then lines[#lines + 1] = TextLine(Fmt(L.ROTATION_BOOK_HOW, how), "how") end
    local note = Rotation.Note(rotation)
    if note then lines[#lines + 1] = TextLine(note, "note") end
    -- Herkunft einer berechneten Rotation (Welle 21): berechnet am, Talentverteilung, Annahmen, Quelle der Werte
    for _, text in ipairs(Rotation.ComputedLines(rotation)) do lines[#lines + 1] = TextLine(text, "computed") end
    if own then lines[#lines + 1] = TextLine(OwnOrigin(rotation), "origin") end
    -- 4. Zurück zur Vorlage (eigene Rotation: zum gespeicherten Stand)
    if own then
        lines[#lines + 1] = ActionLine("reset", edits > 0 and Fmt(L.ROTATION_OWN_RESET_LABEL, edits) or L.ROTATION_OWN_RESET_NONE,
            L.ROTATION_OWN_RESET, L.ROTATION_OWN_RESET_TIP, edits == 0)
    else
        lines[#lines + 1] = ActionLine("reset", edits > 0 and Fmt(L.ROTATION_BOOK_RESET_LABEL, edits) or L.ROTATION_BOOK_RESET_NONE,
            L.ROTATION_BOOK_RESET, L.ROTATION_BOOK_RESET_TIP, edits == 0)
    end
    local Own = ns.RotationOwn
    local full = Own ~= nil and Own.Count() >= Own.MAX
    -- 5. und 6. Abschnitte mit ihren Schritten
    local ctx = { now = GetTime(), combat = ns.InCombat(), rotation = rotation, steps = Rotation.Steps(rotation),
        aoe = Rotation.Aoe() }
    local info = NextInfo()
    local counters = { prep = 0, next = 0 }
    for _, section in ipairs(PageSections(rotation)) do
        lines[#lines + 1] = { kind = "header", left = section.title, right = section.right, section = section.key }
        if section.key == "aoe" then
            lines[#lines + 1] = ActionLine("aoe", L.ROTATION_BOOK_AOE_LABEL,
                Rotation.Aoe() and L.ROTATION_BOOK_AOE_OFF or L.ROTATION_BOOK_AOE_ON, L.ROTATION_BOOK_AOE_TIP)
            lines[#lines].section = section.key
        end
        local visible = Book.VisibleSteps(section, counters)
        for index, row in ipairs(visible) do
            lines[#lines + 1] = StepLine(rotation, section, row.entry, index, #visible, ctx, info, row.rank)
        end
        if own then
            lines[#lines + 1] = ActionLine("add", Fmt(L.ROTATION_OWN_ADD_LABEL, section.title), L.ROTATION_OWN_ADD,
                L.ROTATION_OWN_ADD_TIP, #rotation.own.steps >= ns.RotationOwn.MAX_STEPS)
            lines[#lines].section = section.key
        end
    end
    -- 6b. Als eigene Rotation speichern (Kopie mit den Anpassungen); eine eigene umbenennen, teilen, löschen; eine
    -- geteilte aus Text übernehmen. Unter den Abschnitten, damit die Schritte oben auf der ersten Doppelseite bleiben.
    if Own then
        lines[#lines + 1] = { kind = "header", left = L.ROTATION_OWN_HEADER, ownTools = true }
        lines[#lines + 1] = ActionLine("saveown", full and Fmt(L.ROTATION_OWN_SAVE_FULL, Own.MAX) or L.ROTATION_OWN_SAVE_LABEL,
            L.ROTATION_OWN_SAVE, L.ROTATION_OWN_SAVE_TIP, full)
        if own then
            lines[#lines + 1] = ActionLine("rename", L.ROTATION_OWN_RENAME_LABEL, L.ROTATION_OWN_RENAME, L.ROTATION_OWN_RENAME_TIP)
            lines[#lines + 1] = ActionLine("export", L.ROTATION_OWN_EXPORT_LABEL, L.ROTATION_OWN_EXPORT, L.ROTATION_OWN_EXPORT_TIP)
            lines[#lines + 1] = ActionLine("delete", L.ROTATION_OWN_DELETE_LABEL, Core.Word("DELETE"),
                L.ROTATION_OWN_DELETE_TIP)   -- „Löschen“: Blizzards DELETE (T18-22)
        end
        lines[#lines + 1] = ActionLine("import", L.ROTATION_OWN_IMPORT_LABEL, L.ROTATION_OWN_IMPORT, L.ROTATION_OWN_IMPORT_TIP,
            full)
    end
    -- 7. Quelle(n)
    local sources = Sources(rotation)
    if #sources > 0 then
        lines[#lines + 1] = { kind = "header", left = L.ROTATION_BOOK_SOURCE, sources = true }
        for _, url in ipairs(sources) do
            lines[#lines + 1] = { kind = "spell", name = Host(url), detail = ns.ClickText(L.ROTATION_BOOK_COPY), icon = SOURCE_ICON,
                title = L.ROTATION_BOOK_SOURCE,
                tooltip = { Tip(url, "highlight"), Tip(ns.ClickText(L.ROTATION_BOOK_COPY_TIP), "good") },
                source = url, rotation = rotation.key }
        end
    end
    return lines
end

---------------------------------------------------------------------------
-- Spickzettel (Entscheidung des Nutzers vom 16.11.2026, „Frage 2: Entwurf A“; Entwurf in docs/roadmap/ezCombat.md,
-- „Entscheidungsfrage: Rotation für Einsteiger verständlich“). Die Standardansicht der Seite: oben „Deine Rotation:
-- <Name>“ mit den Knöpfen „Andere wählen“ und „Anpassen“, der Absatz „So funktioniert sie“, dann drei Blöcke mit
-- Alltags-Überschriften – „Bevor es losgeht“, „Im Kampf“ (von oben nach unten: das Erste, das geht, drückst du),
-- „Wenn es eng wird“ –, je Zeile Nummer, Symbol, Name und EIN Satz (Feld text des Schritts), keine Pfeile, keine
-- Kästchen; der Schritt, der gerade dran ist, steht hervorgehoben („Jetzt dran“). Ungelerntes steht eingeklappt
-- unter „Noch nicht gelernt (n)“. Die Seite zum Anpassen (Book.EditLines) liegt unverändert hinter „Anpassen“.
-- Gezeigt wird nur, was für diesen Charakter gilt: ausgeschaltete Schritte, abgelöste Buffs und Varianten, deren feste
-- Bedingung (Stufe, Leveln, gelernt) nicht zutrifft, entfallen hier.
---------------------------------------------------------------------------

-- Der eine Satz eines Schritts: sein Text aus den Daten; ohne Text (selbst hinzugefügt, Bedingung neu gewählt) der
-- Satz der gewählten Bedingung (RotationOwn.CONDITIONS), sonst die Bedingung in Worten.
function Book.EasyText(step)
    local text = Rotation.StepText(step)
    if text ~= "" then return text end
    local Own = ns.RotationOwn
    local condition = Own and Own.ConditionOf(step)
    local tip = condition and Own.ConditionTip(condition)
    if tip then return tip end
    return Book.ConditionText(step)
end

-- Block eines Schritts: „prep“ (Bevor es losgeht), „fight“ (Im Kampf, nummeriert in der Rangfolge) oder „tight“
-- (Wenn es eng wird: Situatives, Mana zurückholen, was nur in der Liste steht, mehrere Gegner bei ausgeschaltetem
-- Flächenmodus).
function Book.EasyBlock(sectionKey, entry)
    if sectionKey == "prep" then return "prep" end
    if sectionKey == "situational" or entry.kind == "resource" or not Rotation.Suggestible(entry.step) then return "tight" end
    if sectionKey == "aoe" and not Rotation.Aoe() then return "tight" end
    return "fight"
end
Book.EASY_BLOCKS = { "prep", "fight", "tight" }

local function EasyLine(rotation, item, number, ctx, info)
    local entry, shown, section = item.entry, item.shown, item.section
    local step = entry.step
    local label = shown.name or ("#" .. tostring(shown.id))
    local _, stateKey = Book.StepState(entry, section.key, shown, ctx, info)
    local nowText
    if stateKey == "now" then
        nowText = L.ROTATION_BOOK_NOW
    elseif stateKey == "side" then
        nowText = L.ROTATION_STATE_SIDE_NOW
    elseif section.key == "prep" and entry.kind == "longbuff" and not ctx.combat and not ctx.prepNow
        and (stateKey == "missing" or stateKey == "expiring") then
        -- vor dem Kampf: der erste fehlende bzw. auslaufende Dauer-Buff ist dran (eine Zeile, nie im Kampf)
        nowText = stateKey == "expiring" and L.ROTATION_EASY_PREP_EXPIRING or L.ROTATION_EASY_PREP_NOW
        ctx.prepNow = true
    end
    local sentence = Book.EasyText(step)
    local tooltip = { Tip(sentence, "normal"), Tip(Book.ConditionText(step), "highlight") }
    AddSharedTip(tooltip, shown.id, step)
    if nowText then tooltip[#tooltip + 1] = Tip(nowText, "good") end
    local own = Rotation.IsOwn(rotation)
    Book.AddEditTips(tooltip, own, section.key)
    tooltip[#tooltip + 1] = Book.JoinTip(Tip(ns.ClickText(L.ROTATION_EASY_OFF_TIP, "right"), "good"))
    return { kind = "spell", name = (number and (number .. ". ") or "– ") .. label, sub = sentence,
        detail = nowText and Core.Style.ColorText("good", nowText) or nil, icon = Spells.Icon(shown.id),
        spellID = shown.id, title = label, style = "known", tooltip = tooltip, tipWide = true, drag = true,
        easy = true, block = item.block, step = step, stepKey = entry.key, rotation = rotation.key, section = section.key,
        rank = number, state = stateKey, now = nowText ~= nil, enabled = entry.enabled, own = own,
        added = own and step.added == true }
end

-- Zeilen des Spickzettels. Eigene Felder: easy (alle Zeilen), block (Kopf und Schritte eines Blocks), now (Schritt ist
-- dran), unlearned (Schritt, der noch nicht gelernt ist), key "choose" / "edit" / "unlearned" (Zeilen mit Knopf).
function Book.EasyLines()
    local lines = {}
    local list = Rotation.ForClass()
    if #list == 0 then
        lines[1] = { kind = "text", left = L.ROTATION_BOOK_NONE }
        return lines
    end
    local rotation = Rotation.Selected()
    local choice = Rotation.Choice()
    local edits = Rotation.EditCount(rotation)
    local right = choice == "auto" and L.ROTATION_AUTO_SHORT or L.ROTATION_CHOSEN
    if Rotation.IsOwn(rotation) then right = L.ROTATION_OWN_SHORT end
    if edits > 0 then right = L.ROTATION_BOOK_EDITED end
    -- 1. Deine Rotation, mit „Andere wählen“ und daneben „Erstellen“ (eigene Rotation; Spielbefund des Nutzers vom
    -- 19.11.2026, Bild 40). Der Knopf „Anpassen“ entfiel am 20.11.2026: Bearbeitet wird direkt auf der Seite (Klick
    -- tauscht, Ziehen schiebt); was nur die Liste aller Schritte kann, steht unten unter „Rotation ändern“.
    local Own = ns.RotationOwn
    local full = Own ~= nil and Own.Count() >= Own.MAX
    lines[#lines + 1] = { kind = "header", left = Fmt(L.ROTATION_EASY_HEAD, Rotation.Name(rotation)), right = right,
        rotation = rotation.key, easy = true }
    lines[#lines + 1] = ActionLine("choose", L.ROTATION_EASY_CHOOSE_LABEL,
        chooserOpen and L.ROTATION_EASY_CHOOSE_CLOSE or L.ROTATION_EASY_CHOOSE, L.ROTATION_EASY_CHOOSE_TIP)
    lines[#lines].easy = true
    if Own then
        lines[#lines].second = { key = "create", button = L.ROTATION_EASY_CREATE, disabled = full,
            tip = full and Fmt(L.ROTATION_OWN_SAVE_FULL, Own.MAX) or L.ROTATION_EASY_CREATE_TIP }
    end
    if chooserOpen then
        local first = #lines + 1
        ChoiceLines(lines, list, rotation, choice)
        for index = first, #lines do lines[index].easy = true end
    end
    -- 2. So funktioniert sie (bleibt oben), Herkunft einer berechneten bzw. eigenen Rotation
    local how = Rotation.How(rotation)
    if how then lines[#lines + 1] = TextLine(Fmt(L.ROTATION_BOOK_HOW, how), "how") end
    for _, text in ipairs(Rotation.ComputedLines(rotation)) do lines[#lines + 1] = TextLine(text, "computed") end
    local origin = OwnOrigin(rotation)
    if origin then lines[#lines + 1] = TextLine(origin, "origin") end
    -- 3. Die drei Blöcke
    local ctx = { now = GetTime(), combat = ns.InCombat(), rotation = rotation, steps = Rotation.Steps(rotation),
        aoe = Rotation.Aoe() }
    local info = NextInfo()
    local blocks, unlearned, off = { prep = {}, fight = {}, tight = {} }, {}, {}
    local hasAoe = false
    for _, section in ipairs(Rotation.Sections(rotation)) do
        hasAoe = hasAoe or section.key == "aoe"
        for _, row in ipairs(Book.VisibleSteps(section)) do
            local entry = row.entry
            local shown = Shown(entry)
            if not entry.enabled and Book.StaticApplies(entry.step) then
                off[#off + 1] = { entry = entry, shown = shown, section = section }
            elseif entry.enabled and not shown.replacedBy and Book.StaticApplies(entry.step) then
                local item = { entry = entry, shown = shown, section = section,
                    block = Book.EasyBlock(section.key, entry) }
                if shown.known then
                    table.insert(blocks[item.block], item)
                else
                    unlearned[#unlearned + 1] = item
                end
            end
        end
    end
    for _, key in ipairs(Book.EASY_BLOCKS) do
        local items = blocks[key]
        if #items > 0 then
            lines[#lines + 1] = { kind = "header", left = L["ROTATION_EASY_BLOCK_" .. key], block = key, easy = true }
            local lead = key == "fight" and L.ROTATION_EASY_BLOCK_fight_LEAD or nil
            if lead then
                local line = TextLine(lead, "lead")
                line.block, line.easy = key, true
                lines[#lines + 1] = line
            end
            for index, item in ipairs(items) do
                lines[#lines + 1] = EasyLine(rotation, item, key ~= "tight" and index or nil, ctx, info)
            end
        end
    end
    -- 4. Noch nicht gelernt (n) – zeigen (eingeklappt)
    if #unlearned > 0 then
        lines[#lines + 1] = ActionLine("unlearned", Fmt(L.ROTATION_EASY_UNLEARNED, #unlearned),
            unlearnedOpen and L.ROTATION_EASY_HIDE or L.ROTATION_EASY_SHOW, L.ROTATION_EASY_UNLEARNED_TIP)
        lines[#lines].easy = true
        if unlearnedOpen then
            for _, item in ipairs(unlearned) do
                local label = item.shown.name or ("#" .. tostring(item.shown.id))
                lines[#lines + 1] = { kind = "spell", name = "– " .. label, sub = UnlearnedText(item.shown.id),
                    detail = Book.EasyText(item.entry.step), icon = Spells.Icon(item.shown.id), spellID = item.shown.id,
                    title = label, style = "future", easy = true, unlearned = true, step = item.entry.step,
                    stepKey = item.entry.key, rotation = rotation.key, section = item.section.key }
            end
        end
    end
    -- 4b. Ausgeschaltet (n) – zeigen (eingeklappt); ein Klick schaltet den Schritt wieder ein
    if #off > 0 then
        lines[#lines + 1] = ActionLine("offlist", Fmt(L.ROTATION_EASY_OFF, #off),
            offOpen and L.ROTATION_EASY_HIDE or L.ROTATION_EASY_SHOW, L.ROTATION_EASY_OFF_LIST_TIP)
        lines[#lines].easy = true
        if offOpen then
            for _, item in ipairs(off) do
                local label = item.shown.name or ("#" .. tostring(item.shown.id))
                lines[#lines + 1] = { kind = "spell", name = "– " .. label, sub = Book.EasyText(item.entry.step),
                    detail = ns.ClickText(L.ROTATION_EASY_ON), icon = Spells.Icon(item.shown.id),
                    spellID = item.shown.id, title = label, style = "future", easy = true, offStep = true,
                    tooltip = { Tip(ns.ClickText(L.ROTATION_EASY_ON_TIP), "good") },
                    step = item.entry.step, stepKey = item.entry.key, rotation = rotation.key, section = item.section.key,
                    enabled = false }
            end
        end
    end
    -- 5. Rotation ändern: was bis zum 20.11.2026 nur hinter „Anpassen“ stand (Leitlinie 8 – keine Funktion geht
    -- verloren): zurück zur Vorlage, Flächenmodus, eigene Rotation (Schritt hinzufügen, umbenennen, teilen, löschen),
    -- aus Text übernehmen, die Liste aller Schritte mit Ein/Aus und Pfeilen (Book.EditLines).
    Book.ToolLines(lines, rotation, hasAoe, full)
    -- 6. Quelle(n) (Leitlinie 11): Klick zeigt den Link zum Kopieren
    local sources = Sources(rotation)
    if #sources > 0 then
        lines[#lines + 1] = { kind = "header", left = L.ROTATION_BOOK_SOURCE, sources = true, easy = true }
        for _, url in ipairs(sources) do
            lines[#lines + 1] = { kind = "spell", name = Host(url), detail = ns.ClickText(L.ROTATION_BOOK_COPY),
                icon = SOURCE_ICON, title = L.ROTATION_BOOK_SOURCE, easy = true,
                tooltip = { Tip(url, "highlight"), Tip(ns.ClickText(L.ROTATION_BOOK_COPY_TIP), "good") },
                source = url, rotation = rotation.key }
        end
    end
    return lines
end

-- Zeilen „Rotation ändern“ unter dem Spickzettel (5.). full: so viele eigene Rotationen, wie gehen (Own.MAX).
function Book.ToolLines(lines, rotation, hasAoe, full)
    local Own = ns.RotationOwn
    local own = Rotation.IsOwn(rotation)
    local edits = Rotation.EditCount(rotation)
    local function Add(line)
        line.easy, line.tools = true, true
        lines[#lines + 1] = line
        return line
    end
    Add({ kind = "header", left = L.ROTATION_EASY_TOOLS })
    if own then
        Add(ActionLine("reset", edits > 0 and Fmt(L.ROTATION_OWN_RESET_LABEL, edits) or L.ROTATION_OWN_RESET_NONE,
            L.ROTATION_OWN_RESET, L.ROTATION_OWN_RESET_TIP, edits == 0))
    else
        Add(ActionLine("reset", edits > 0 and Fmt(L.ROTATION_BOOK_RESET_LABEL, edits) or L.ROTATION_BOOK_RESET_NONE,
            L.ROTATION_BOOK_RESET, L.ROTATION_BOOK_RESET_TIP, edits == 0))
    end
    if hasAoe then
        Add(ActionLine("aoe", L.ROTATION_BOOK_AOE_LABEL, Rotation.Aoe() and L.ROTATION_BOOK_AOE_OFF or L.ROTATION_BOOK_AOE_ON,
            L.ROTATION_BOOK_AOE_TIP))
    end
    if own and Own then
        Add(ActionLine("add", L.ROTATION_EASY_ADD_LABEL, L.ROTATION_OWN_ADD, L.ROTATION_OWN_ADD_TIP,
            #rotation.own.steps >= Own.MAX_STEPS))
        Add(ActionLine("rename", L.ROTATION_OWN_RENAME_LABEL, L.ROTATION_OWN_RENAME, L.ROTATION_OWN_RENAME_TIP))
        Add(ActionLine("export", L.ROTATION_OWN_EXPORT_LABEL, L.ROTATION_OWN_EXPORT, L.ROTATION_OWN_EXPORT_TIP))
        Add(ActionLine("delete", L.ROTATION_OWN_DELETE_LABEL, Core.Word("DELETE"), L.ROTATION_OWN_DELETE_TIP))
    end
    if Own then
        Add(ActionLine("import", L.ROTATION_OWN_IMPORT_LABEL, L.ROTATION_OWN_IMPORT, L.ROTATION_OWN_IMPORT_TIP, full))
    end
    Add(ActionLine("edit", L.ROTATION_EASY_EDIT_LABEL, L.ROTATION_EASY_EDIT, L.ROTATION_EASY_EDIT_TIP))
    return lines
end

-- Die Zeilen der Seite: Spickzettel oder – nach „Anpassen“ – die Seite zum Anpassen (gemerkt je Charakter).
function Book.Lines()
    if Book.Editing() then return Book.EditLines() end
    return Book.EasyLines()
end

---------------------------------------------------------------------------
-- Klicks und Knöpfe
---------------------------------------------------------------------------

local function RotationOf(line)
    return (line and line.rotation and Rotation.Find(line.rotation)) or Rotation.Selected()
end

---------------------------------------------------------------------------
-- Eigene Rotation (RotationOwn.lua): Namen abfragen, teilen, übernehmen, Menüs für Zauber und Bedingung
---------------------------------------------------------------------------

-- „Als eigene Rotation speichern“: Name abfragen (Vorschlag „<Vorlage> (eigene)“), dann Kopie anlegen und wählen.
function Book.AskSave(rotation)
    local Own = ns.RotationOwn
    if not (Own and rotation) then return false end
    Core.AskText(L.ROTATION_OWN_SAVE_PROMPT, Own.DefaultName(rotation), function(name)
        local key, reason, detail = Own.Create(rotation, name, true)
        if key then
            ns.Print(Fmt(L.ROTATION_OWN_SAVED, Rotation.Name(Rotation.Find(key))))
        else
            ns.Print(Own.SaveReasonText(reason, detail))
        end
    end, Own.NAME_MAX)
    return false
end

function Book.AskRename(rotation)
    local Own = ns.RotationOwn
    if not (Own and Rotation.IsOwn(rotation)) then return false end
    local key = rotation.key
    Core.AskText(L.ROTATION_OWN_RENAME_PROMPT, rotation.own.name, function(name) Own.Rename(key, name) end, Own.NAME_MAX)
    return false
end

-- Teilen: der Text im Textdialog von ezCore, markiert zum Kopieren.
function Book.ShowExport(rotation)
    local Own = ns.RotationOwn
    local text = Own and Own.Export(rotation)
    if not text then return false end
    Core.TextDialog({ owner = "ezCombat", title = Fmt(L.ROTATION_OWN_EXPORT_TITLE, Rotation.Name(rotation)),
        hint = L.ROTATION_OWN_EXPORT_HINT, text = text, select = true })
    return false
end

-- Übernehmen: Text einfügen, „Übernehmen“ prüft (Own.Import); ein Fehler hält den Dialog offen und steht im Chat.
function Book.ShowImport()
    local Own = ns.RotationOwn
    if not Own then return false end
    Core.TextDialog({ owner = "ezCombat", title = L.ROTATION_OWN_IMPORT_TITLE, hint = L.ROTATION_OWN_IMPORT_HINT,
        text = "", accept = true, maxLetters = 0,   -- „Übernehmen“: ezCores Standardtext (T18-22)
        onAccept = function(text)
            local key, reason, detail = Own.Import(text)
            if not key then
                ns.Print(Own.ReasonText(reason, detail))
                return false
            end
            Rotation.Select(key)
            ns.Print(Fmt(L.ROTATION_OWN_IMPORTED_DONE, Rotation.Name(Rotation.Find(key))))
            return true
        end })
    return false
end

function Book.AskDelete(rotation)
    local Own = ns.RotationOwn
    if not (Own and Rotation.IsOwn(rotation)) then return false end
    local key, name = rotation.key, Rotation.Name(rotation)
    Core.Confirm(Fmt(L.ROTATION_OWN_DELETE_ASK, name), function()
        if Own.Delete(key) then ns.Print(Fmt(L.ROTATION_OWN_DELETED, name)) end
    end, { alert = true })
    return false
end

-- Einträge des Menüs „Schritt hinzufügen“: gelernte Zauber nach Namen, ab MENU_CHUNK in Untermenüs („A … F“).
-- → { { label, spells = { { id, name } … } } } (eine Gruppe ohne label: flach)
function Book.AddMenuGroups()
    local spells = ns.RotationOwn and ns.RotationOwn.KnownSpells() or {}
    if #spells <= MENU_CHUNK + 5 then return { { spells = spells } } end
    local groups = {}
    for first = 1, #spells, MENU_CHUNK do
        local chunk = {}
        for index = first, math.min(first + MENU_CHUNK - 1, #spells) do chunk[#chunk + 1] = spells[index] end
        groups[#groups + 1] = { label = chunk[1].name .. " … " .. chunk[#chunk].name, spells = chunk }
    end
    return groups
end

function Book.AddMenu(line, owner)
    local Own, Menu = ns.RotationOwn, Core.Menu
    local rotation = RotationOf(line)
    if not (Own and Menu and Rotation.IsOwn(rotation)) then return false end
    local key, section = rotation.key, line.section
    local groups = Book.AddMenuGroups()
    -- Zauber eines Abschnitts unter parent (in Untermenüs ab MENU_CHUNK)
    local function AddSpells(parent, into)
        for _, group in ipairs(groups) do
            local sub = group.label and Menu.Button(parent, group.label) or parent
            for _, spell in ipairs(group.spells) do
                Menu.Button(sub, spell.name, function()
                    if Own.AddStep(key, into, spell.id) then
                        ns.Print(Fmt(L.ROTATION_OWN_ADDED, spell.name, L["ROTATION_SECTION_" .. into]))
                    end
                end)
            end
        end
    end
    Menu.Open(owner, function(root)
        if section then
            Menu.Title(root, Fmt(L.ROTATION_OWN_ADD_TITLE, L["ROTATION_SECTION_" .. section]))
        else
            Menu.Title(root, L.ROTATION_EASY_ADD_TITLE)
        end
        if #groups[1].spells == 0 then
            Menu.Title(root, L.ROTATION_OWN_ADD_NONE)
            return
        end
        if section then return AddSpells(root, section) end
        -- ohne Abschnitt (Knopf unter „Rotation ändern“): erst der Abschnitt, dann der Zauber
        for _, into in ipairs(Rotation.SECTIONS) do
            if Own.SECTION_DEFAULT[into] then AddSpells(Menu.Button(root, L["ROTATION_SECTION_" .. into]), into) end
        end
    end)
    return false
end

---------------------------------------------------------------------------
-- Direkt auf der Seite bearbeiten (Entscheidung des Nutzers vom 20.11.2026, „Klick tauscht, Ziehen schiebt
-- (Empfohlen)“): Klick auf einen Schritt öffnet das Menü zum Tauschen der Fähigkeit, Ziehen mit der Maus ändert die
-- Reihenfolge im Abschnitt – beides nur außerhalb des Kampfes (im Kampf gesperrt mit Hinweis, Book.Locked).
-- Getauscht wird nur in einer eigenen Rotation; ist die gezeigte eine Vorlage, entsteht erst eine eigene Kopie
-- (Own.Create, Name „<Vorlage> (eigene)“) und wird gewählt. Verschieben einer Vorlage ist eine Anpassung wie die Pfeile.
---------------------------------------------------------------------------

-- Im Kampf gesperrt? notify = true sagt es im Chat (Core.CombatNotice).
function Book.Locked(notify)
    if not ns.InCombat() then return false end
    if notify then Core.CombatNotice(ns, L.ROTATION_STEP_EDIT_WHAT) end
    return true
end

-- Fähigkeit des Schritts einer Zeile gegen spellID tauschen. → true, wenn getauscht
function Book.Swap(line, spellID)
    if Book.Locked(true) then return false end
    local Own = ns.RotationOwn
    local rotation = RotationOf(line)
    if not (Own and rotation and type(line) == "table" and line.stepKey and type(spellID) == "number") then return false end
    local key = rotation.key
    if not Rotation.IsOwn(rotation) then
        local created, reason, detail = Own.Create(rotation, nil, true)
        if not created then
            ns.Print(Own.SaveReasonText(reason, detail))
            return false
        end
        key = created
        ns.Print(Fmt(L.ROTATION_STEP_SWAP_OWN, Rotation.Name(Rotation.Find(key))))
    end
    return Own.SwapSpell(key, line.stepKey, spellID)
end

-- Ziehen beginnen? Nur Schritte, nie im Kampf (opts.canDrag der Zauberbuch-Ansicht).
function Book.CanDrag(line)
    if type(line) ~= "table" or not line.step or line.offStep or line.unlearned then return false end
    return not Book.Locked(true)
end

-- Losgelassen: from auf to (Zeilen der Seite). Nur im selben Abschnitt derselben Rotation; der Schritt rückt an den
-- Platz des Ziels (unter den gezeigten Einträgen, Book.MoveVisible). Auf dem Spickzettel zusätzlich im selben Block
-- (Book.EasyBlock): Ein Schritt aus „Wenn es eng wird“ kann zum selben Abschnitt gehören wie einer aus „Im Kampf“,
-- verschoben stünde er aber weiter in seinem Block – es änderte sich etwas, ohne dass man es sieht. Die Absage nennt
-- die Abschnitte bzw. den Block, weil der Spickzettel sie nicht zeigt. → true, wenn verschoben
function Book.Drop(from, to)
    if type(from) ~= "table" or not from.step or type(to) ~= "table" or not to.step or from.step == to.step then
        return false
    end
    if Book.Locked(true) then return false end
    if from.rotation ~= to.rotation then return false end
    if from.easy and to.easy and from.block ~= to.block then
        ns.Print(Fmt(L.ROTATION_STEP_DROP_BLOCK, from.title or "?", L["ROTATION_EASY_BLOCK_" .. tostring(from.block)] or "?"))
        return false
    end
    if from.section ~= to.section then
        ns.Print(Fmt(L.ROTATION_STEP_DROP_SECTION, from.title or "?", L["ROTATION_SECTION_" .. tostring(from.section)] or "?",
            L["ROTATION_SECTION_" .. tostring(to.section)] or "?"))
        return false
    end
    local rotation = RotationOf(from)
    if not rotation then return false end
    local fromIndex, toIndex
    for _, section in ipairs(Rotation.Sections(rotation)) do
        if section.key == from.section then
            for index, row in ipairs(Book.VisibleSteps(section)) do
                if row.entry.step == from.step then fromIndex = index end
                if row.entry.step == to.step then toIndex = index end
            end
        end
    end
    if not (fromIndex and toIndex) then return false end
    local direction = toIndex > fromIndex and 1 or -1
    local moved = false
    for _ = 1, math.abs(toIndex - fromIndex) do
        if not Book.MoveVisible(rotation, from.step, direction) then break end
        moved = true
    end
    return moved
end

-- Menü eines Schritts (Klick): Fähigkeit tauschen (gelernte Zauber, ab MENU_CHUNK in Untermenüs), bei einer eigenen
-- Rotation die Bedingung, dann Aus/Ein und – selbst hinzugefügt – Entfernen.
function Book.StepMenu(line, owner)
    local Menu = Core.Menu
    local rotation = RotationOf(line)
    if not (Menu and rotation and type(line) == "table" and line.step) then return false end
    if Book.Locked(true) then return false end
    local Own = ns.RotationOwn
    local own = Rotation.IsOwn(rotation)
    local groups = Book.AddMenuGroups()
    Menu.Open(owner, function(root)
        Menu.Title(root, Fmt(L.ROTATION_STEP_SWAP_TITLE, line.title or "?"))
        if not own then Menu.Title(root, L.ROTATION_STEP_SWAP_COPY) end
        if #groups[1].spells == 0 then Menu.Title(root, L.ROTATION_OWN_ADD_NONE) end
        for _, group in ipairs(groups) do
            local sub = group.label and Menu.Button(root, group.label) or root
            for _, spell in ipairs(group.spells) do
                if spell.name ~= line.title then
                    Menu.Button(sub, spell.name, function() Book.Swap(line, spell.id) end)
                end
            end
        end
        if own and Own then
            local entries, custom = Book.ConditionEntries(line)
            local key, stepKey = rotation.key, line.stepKey
            Menu.Divider(root)
            local cond = Menu.Button(root, L.ROTATION_STEP_CONDITION)
            if custom then Menu.Title(cond, L.ROTATION_OWN_COND_TEMPLATE) end
            for _, entry in ipairs(entries) do
                local item = Menu.Radio(cond, entry.label, function() return Own.ConditionOf(line.step) end, function(value)
                    if not Book.Locked(true) then Own.SetCondition(key, stepKey, value) end
                    return Menu.Close()
                end, entry.key)
                Menu.Tip(item, entry.label, entry.tip)
            end
        end
        Menu.Divider(root)
        -- Aus/Ein für jeden Schritt, auch selbst hinzugefügte und getauschte (Own.SwapSpell setzt added); die
        -- dazu noch Entfernen
        local on = Rotation.StepEnabled(rotation, line.step)
        Menu.Button(root, on and L.ROTATION_STEP_OFF or L.ROTATION_STEP_ON, function()
            if not Book.Locked(true) then Book.Button(line, "toggle") end
        end)
        if line.added and Own then
            Menu.Tip(Menu.Button(root, L.ROTATION_OWN_REMOVE, function()
                if not Book.Locked(true) then Own.RemoveStep(rotation.key, line.stepKey) end
            end), L.ROTATION_OWN_REMOVE, L.ROTATION_OWN_REMOVE_TIP)
        end
    end)
    return false
end

-- Einträge des Menüs „Bedingung“ eines Schritts einer eigenen Rotation: { { key, label, tip, checked } … }; dazu,
-- ob der Schritt eine Bedingung der Vorlage trägt, die keiner Auswahl entspricht.
function Book.ConditionEntries(line)
    local Own = ns.RotationOwn
    local entries = {}
    if not (Own and type(line) == "table" and line.step) then return entries, false end
    local current = Own.ConditionOf(line.step)
    for _, choice in ipairs(Own.CONDITIONS) do
        entries[#entries + 1] = { key = choice.key, label = Own.ConditionLabel(choice.key), tip = Own.ConditionTip(choice.key),
            checked = current == choice.key }
    end
    return entries, current == nil
end

function Book.ConditionMenu(line, owner)
    local Own, Menu = ns.RotationOwn, Core.Menu
    local rotation = RotationOf(line)
    if not (Own and Menu and Rotation.IsOwn(rotation) and line.step) then return false end
    local key, stepKey = rotation.key, line.stepKey
    local entries, custom = Book.ConditionEntries(line)
    Menu.Open(owner, function(root)
        Menu.Title(root, Fmt(L.ROTATION_OWN_COND_TITLE, line.title or "?"))
        if custom then Menu.Title(root, L.ROTATION_OWN_COND_TEMPLATE) end
        for _, entry in ipairs(entries) do
            local item = Menu.Radio(root, entry.label, function() return Own.ConditionOf(line.step) end, function(value)
                if not Book.Locked(true) then Own.SetCondition(key, stepKey, value) end
                return Menu.Close()
            end, entry.key)
            Menu.Tip(item, entry.label, entry.tip)
        end
        if line.added then
            Menu.Divider(root)
            Menu.Tip(Menu.Button(root, L.ROTATION_OWN_REMOVE, function()
                if not Book.Locked(true) then Own.RemoveStep(key, stepKey) end
            end), L.ROTATION_OWN_REMOVE, L.ROTATION_OWN_REMOVE_TIP)
        end
    end)
    return false
end

-- Knopf einer Zeile: "toggle" (Schritt aus/an), "up"/"down" (eine Stelle im Abschnitt), "reset" (zurück zur
-- Vorlage), "aoe" (Flächenmodus umschalten); Spickzettel: "edit" (Liste aller Schritte), "choose" (Liste „Andere
-- wählen“ auf/zu), "create" („Erstellen“: eigene Rotation, wie "saveown"), "unlearned" (Noch nicht gelernt auf/zu),
-- "offlist" (Ausgeschaltet auf/zu); Liste aller Schritte: "done" (Fertig), "saveown", "import"; eigene
-- Rotation: "rename", "export", "delete", "add" (Menü der Zauber), "remove" (selbst hinzugefügten Schritt entfernen).
-- owner: der Knopf (für Menüs). → true, wenn sich etwas geändert hat. Wirkt nie einen Zauber.
function Book.Button(line, key, owner)
    if type(line) ~= "table" then return false end
    key = key or line.key
    if key == "edit" or key == "done" then return Book.SetEditing(key == "edit") end
    if key == "choose" then
        chooserOpen = not chooserOpen
        return true
    end
    if key == "unlearned" then
        unlearnedOpen = not unlearnedOpen
        return true
    end
    if key == "offlist" then
        offOpen = not offOpen
        return true
    end
    if key == "import" then return Book.ShowImport() end
    local rotation = RotationOf(line)
    if key == "aoe" then
        Rotation.SetAoe(not Rotation.Aoe())
        return true
    end
    if not rotation then return false end
    if key == "reset" then
        local name = Rotation.Name(rotation)
        local changed = Rotation.ResetEdits(rotation)
        ns.Print(Fmt(changed and L.ROTATION_RESET_DONE or L.ROTATION_RESET_NOTHING, name))
        return changed
    end
    if key == "saveown" or key == "create" then return Book.AskSave(rotation) end
    if key == "rename" then return Book.AskRename(rotation) end
    if key == "export" then return Book.ShowExport(rotation) end
    if key == "delete" then return Book.AskDelete(rotation) end
    if key == "add" then return Book.AddMenu(line, owner) end
    if not line.step then return false end
    if key == "toggle" then
        return Rotation.SetStepEnabled(rotation, line.step, not Rotation.StepEnabled(rotation, line.step))
    elseif key == "remove" then
        return Rotation.IsOwn(rotation) and ns.RotationOwn.RemoveStep(rotation.key, line.stepKey) or false
    elseif key == "up" then
        return Book.MoveVisible(rotation, line.step, -1)
    elseif key == "down" then
        return Book.MoveVisible(rotation, line.step, 1)
    end
    return false
end

-- Klick auf einen Eintrag: Rotation wählen bzw. Link der Quelle zum Kopieren anbieten. Schritte (Spickzettel und Liste
-- aller Schritte, seit 20.11.2026): Linksklick öffnet das Menü zum Tauschen (Book.StepMenu; Umschalt-Linksklick bei
-- einer eigenen Rotation gleich das Menü „Bedingung“), Rechtsklick schaltet aus bzw. ein – auch selbst hinzugefügte
-- und getauschte Schritte (die entfernt zusätzlich das Kreuz bzw. das Menü). Ein Schritt unter „Ausgeschaltet“ geht
-- per Klick wieder an.
-- Noch nicht gelernte Schritte tun nichts.
function Book.Click(line, button, owner)
    if type(line) ~= "table" then return end
    if line.choose then
        chooserOpen = false
        Rotation.Select(line.choose)
    elseif line.source then
        Core.AskText(Fmt(L.ROTATION_BOOK_COPY_PROMPT, Rotation.Name(RotationOf(line))), line.source,
            function() end, 0)
    elseif line.offStep then
        Book.Button(line, "toggle")
    elseif line.step and not line.unlearned and button == "RightButton" then
        Book.Button(line, "toggle")
    elseif line.step and not line.unlearned then
        if line.own and IsShiftKeyDown and IsShiftKeyDown() then
            if not Book.Locked(true) then Book.ConditionMenu(line, owner) end
        else
            Book.StepMenu(line, owner)
        end
    end
end

---------------------------------------------------------------------------
-- Knöpfe auf der Seite: zeichnet ezCores Zauberbuch-Ansicht (opts.buttons = true, CB-36)
---------------------------------------------------------------------------

-- Aufgeschlagen und zu sehen (Zauberbuch offen, Reiter aktiv)?
local function Visible()
    return view ~= nil and view.frame ~= nil and view.frame:IsVisible()
end

-- Die sichtbaren Knöpfe der aufgeschlagenen (Doppel-)Seite: { steps = { Knopfspalte … }, actions = { Knopf … } }
-- (Tests, Rundgang) – aus ezCores Ansicht; zugeschlagen keine.
function Book.Widgets()
    if not (Visible() and view.Widgets) then return { steps = {}, actions = {} } end
    return view:Widgets()
end

-- Sichtbarer Knopf einer Zeile mit Knopf ("reset", "aoe") – Ziel der Erklärblase „Vorlage anpassen“.
function Book.ActionButton(key)
    if not (Visible() and view.ActionButton) then return nil end
    local button = view:ActionButton(key)
    if button and button:IsVisible() then return button end
    return nil
end

---------------------------------------------------------------------------
-- Ansicht
---------------------------------------------------------------------------

function Book.View() return view end
function Book.Tab() return view and view.tab end
function Book.IsOpen() return view ~= nil and view:IsShown() end
function Book.Refresh() if view then view:Refresh() end end

-- Der Reiter folgt dem Hauptschalter „Nächste Aktion vorschlagen“ (Einstellungs-Prüfung 19.11.2026, Nr. 33; bis dahin
-- eigener Schalter rotationBook – ohne den Reiter fehlte der einzige Ort zum Anpassen, Leitlinie 3).
function Book.Enabled() return ns.Enabled("rotation") and #Rotation.ForClass() > 0 end

-- Erklärblasen: am Reiter, sobald das Zauberbuch aufgeht; ist die gesehen, an „Zurück zur Vorlage“, sobald die
-- Seite aufgeschlagen ist (jeweils nur diese eine Blase des Rundgangs, nie zwei zugleich). Steht gerade ezCores Hinweis
-- am Zauberbuch (unten, Book.RegisterOptInHint), wartet die Blase an „Zurück zur Vorlage“ bis zum nächsten Zeichnen.
local tourPending = false
local function OptInShowing()
    local Hint = Core.OptInHint
    return Hint ~= nil and Hint.Box ~= nil and Hint.Box("spellbook") ~= nil
end
local function TourSoon()
    local tour = ns.Tour and ns.Tour()
    if tourPending or not tour or (tour.hints.Seen("rotationTab") and tour.hints.Seen("rotationEdit")) then return end
    tourPending = true
    C_Timer.After(0.3, function()
        tourPending = false
        if ns.ShowTourStep("rotationTab") then return end
        if tour.hints.Seen("rotationTab") and Book.IsOpen() and not OptInShowing() then
            ns.ShowTourStep("rotationEdit")
        end
    end)
end

local function Setup()
    if view or not Core.NewSpellbookView then return end
    view = Core.NewSpellbookView({
        key = KEY,
        owner = "ezCombat",
        frameName = "ezCombatRotationView",
        icon = TAB_ICON,
        tabY = TAB_Y, order = 30,   -- Seitenreiter-Stapel des Zauberbuchs: nach ezMerchant 10 und ezMacro 20 (T16-4)
        title = L.ROTATION_BOOK_TITLE,
        tip = L.ROTATION_BOOK_TAB_TIP,
        lines = function() return Book.Lines() end,
        onClick = function(line, button, entry) Book.Click(line, button, entry) end,
        buttons = true,         -- ezCore zeichnet Knopfspalte und Zeile mit Knopf (Core.SpellbookView.NATIVE_BUTTONS)
        onButton = function(line, key, button) return Book.Button(line, key, button) end,
        -- Ziehen schiebt einen Schritt im Abschnitt (Entscheidung des Nutzers vom 20.11.2026); nie im Kampf
        canDrag = function(line) return Book.CanDrag(line) end,
        onDrop = function(from, to) return Book.Drop(from, to) end,
        enabled = Book.Enabled,
        -- Kein „remember“: Das Zauberbuch öffnet immer auf Blizzards eigenem Reiter, die Seite „Rotation“ nur auf Klick
        -- (Spielbefund des Nutzers vom 19.11.2026: „Zauberbuch öffnen landet direkt bei ‚Deine Rotation‘ anstatt auf dem
        -- original“). Bis dahin merkte ezCombatDB.rotationBookOpen die zuletzt aufgeschlagene Seite.
    })
    -- Nach jedem Zeichnen der aufgeschlagenen Seite die Erklärblasen des Rundgangs. Die Ansicht ist eine Tabelle von
    -- ezCore (kein Rahmen von Blizzard): Ihre Methode Render wird für diese eine Ansicht ergänzt, nicht ersetzt.
    local render = view.Render
    view.Render = function(self, ...)
        render(self, ...)
        if self:IsShown() then TourSoon() end
    end
    ns.WhenAddOnLoaded("Blizzard_PlayerSpells", function()
        local frame = rawget(_G, "PlayerSpellsFrame")
        if not frame then return end
        frame:HookScript("OnShow", TourSoon)
        -- Zuschlagen beim Schließen macht ezCore für alle Ansichten (SpellbookView, CloseOnHide; seit 20.11.2026)
        if frame.SpellBookFrame then frame.SpellBookFrame:HookScript("OnShow", TourSoon) end
    end)
end

local RefreshSoon = ns.Throttle(function() Book.Refresh() end, 0.2)
Rotation.OnChange(function() Book.Refresh() end)
-- Nächste Aktion gewechselt: nur neu zeichnen, wenn die Seite gerade offen ist („Jetzt dran“ wandert mit)
Rotation.OnNext(function() if Book.IsOpen() then view:Render() end end)
ns.On("SPELLS_CHANGED", function() RefreshSoon() end)
-- Zustände der Seite, die ohne Wechsel der nächsten Aktion kippen: Buff liegt/fehlt, Kampf, Ziel, Begleiter, Gepäck
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_TARGET_CHANGED", "BAG_UPDATE_DELAYED",
    "UPDATE_SHAPESHIFT_FORM", "PLAYER_LEVEL_UP" }) do
    ns.On(event, function() if Book.IsOpen() then RefreshSoon() end end)
end
-- UNIT_AURA kommt im Kampf mit gesperrter Einheit; geweckt wird der Zuhörer nur für den Spieler (ns.OnUnit).
ns.OnUnit("UNIT_AURA", "player", function(_, unit)
    if Book.IsOpen() and (ns.IsSecret(unit) or unit == "player") then RefreshSoon() end
end)
ns.OnUnit("UNIT_PET", "player", function(_, unit)
    if Book.IsOpen() and not ns.IsSecret(unit) and unit == "player" then RefreshSoon() end
end)
ns.OnSettingChanged(function(key)
    if key == "rotation" and view then view:UpdateTab() end
end)
ns.OnReady(Setup)

---------------------------------------------------------------------------
-- Hinweis „Mitzählen“ am Zauberbuch (ezCores Hinweis-Helfer, Welle 29, NACH-27)
---------------------------------------------------------------------------

-- „Mitzählen, wenn das Spiel Werte sperrt“ (rotationEstimate) ist seit der Prüfung auf Blizzards Regeln vom 17.11.2026 ab
-- Werk aus; die Umstellung in Core.lua (estimateOff17) schaltete ein gespeichertes „an“ aus. Grundsatz des Nutzers vom
-- 17.11.2026, wörtlich „user muss auf sowas hingewiesen werden, er kann es nutzen muss es aber einschalten“: einmal je
-- Account, wenn das Zauberbuch aufgeht und es Rotationen für die Klasse gibt; Pfeil auf den Reiter „Rotation“. Erst nach
-- der Erklärblase des Rundgangs am Reiter und nie neben einer offenen Blase des Rundgangs (nie zwei Blasen am Reiter).
-- Ist die Seite schon aufgeschlagen (per Klick; gemerkt wird sie seit 20.11.2026 nicht mehr), ihr Knopf „Zurück zur Vorlage“ zu sehen und dessen Blase noch nicht
-- gesehen, kommt diese zuerst – beide liefen sonst 0,3 s nach dem Öffnen gleichzeitig an (TourSoon und
-- OptInHint.DELAY). Ohne den Knopf (keine gelernte Rotation) kann die Blase nicht kommen, dann wartet der Hinweis nicht.
-- Umgekehrt wartet die Blase, solange der Hinweis steht (TourSoon, OptInShowing).
-- Für die beim Update Umgestellten (db.estimateOff17Was: Einstellungen oder ein gesichertes Profil) sagt die Zeile
-- „beim Update ausgeschaltet“ – für sie änderte sich das Verhalten im Kampf ohne eigenes Zutun.
local function TourBusy()
    local tour = ns.Tour and ns.Tour()
    if not (tour and tour.hints) then return false end
    if not tour.hints.Seen("rotationTab") then return true end
    if not tour.hints.Seen("rotationEdit") and Book.ActionButton("reset") ~= nil then return true end
    for _, key in ipairs({ "rotationTab", "rotationEdit" }) do
        local box = tour.hints.Box and tour.hints.Box(key)
        if box and box.IsShown and box:IsShown() then return true end
    end
    return false
end

function Book.EstimateSwitchedOff()
    local was = type(ns.db) == "table" and ns.db.estimateOff17Was or nil
    if type(was) ~= "table" then return false end
    return was.settings == true or (type(was.profiles) == "table" and next(was.profiles) ~= nil)
end

function Book.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezCombat.rotationEstimate", {
        owner = "ezCombat",
        window = "spellbook",
        label = function() return L.OPT_rotationEstimate end,
        what = function() return L.OPTIN_rotationEstimate end,
        where = function() return ns.PathText("SETTINGS_ADVANCED", "OPT_rotationEstimate") end,   -- T18-18
        isOn = function() return ns.Enabled("rotationEstimate") end,
        enable = function()
            ns.SetSetting("rotationEstimate", true)
            return ns.Enabled("rotationEstimate")
        end,
        applies = function() return Book.Enabled() and not TourBusy() end,
        switchedOff = Book.EstimateSwitchedOff,
        target = function() return Book.Tab() end,
        side = "right",
    })
end
Book.RegisterOptInHint()
