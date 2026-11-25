local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Makros aus deinen Fähigkeiten – SpellMacros.lua (Welle 27, Paket modul/ezmacro-faehigkeiten). Frage des Nutzers vom
    16.11.2026: „kann es sein dass die makros unvollständig sind? auch in bezug auf die eigenen fähigkeiten?“ – auf
    „Makros aus deinen Fähigkeiten erzeugen und die Lücken der Liste füllen?“: „Ja, beides“ (ROADMAP-Index).

    Zu jedem gelernten Zauber deiner Klasse ohne eigene Vorlage bietet ezMacro ein passendes Makro nach der Art des
    Zaubers an (ezCore.SpellKinds: zuerst der Client – C_Spell.IsSpellHarmful/IsSpellHelpful –, sonst ezCores
    Client-Tabellen laut wago.tools):
      Schaden über Zeit, Schaden, Schwächung   „[@mouseover,harm,nodead][]“ – Gegner unter der Maus, sonst das Ziel
      Heilung, Stärkung                        Mitglied unter der Maus, sonst Mitspieler unter der Maus, sonst das Ziel,
                                               sonst du („[@mouseover,party][@mouseover,raid][@mouseover,help,nodead]
                                               [help,nodead][@player]“ – dieselbe Kette wie ezMacros Heil-Vorlagen,
                                               Spells.MacroGroupFirst: kein Durchrutschen auf das Ziel); geht der Zauber
                                               nicht auf dich (ns.NOT_SELF, laut Client-Tabelle SpellMisc – Göttliches
                                               Eingreifen, Segen der Opferung …), endet die Kette auf dem Ziel
                                               („…[@mouseover,help,nodead][]“, SM.FRIEND_OTHERS) statt auf dir
      Ziel beliebig (Gegner oder Mitspieler)   Mitglied unter der Maus, sonst wer unter der Maus ist, sonst das Ziel
                                               („[@mouseover,party][@mouseover,raid][@mouseover,exists,nodead][]“ –
                                               Heiliger Schock, Sühne, Magiebannung; Gegenprüfung zu Welle 27)
      Kontrolle                                „[@focus,harm,nodead][]“ – Fokus, sonst das Ziel
      Unterbrechen                             „/stopcasting“ vorweg, dann wie Kontrolle
    Reine Selbst-Zauber, Haltungen, passive, nur ausgelöste Zauber, Wiederbeleben (dafür gibt es Vorlagen),
    Lernzauber für den Begleiter und die Zauber in ns.NO_GENERATE (Data\Classes.lua: Finishing-Moves, Nahkampf aufs Ziel
    – laut Grund in ns.NO_TEMPLATE wirkt eine Maus- oder Fokus-Fassung dort nicht oder bringt nichts) bekommen keins.
    Ebenso keins (Fund des code-reviewers vor dem Merge, 16.11.2026): Schaden, Schaden über Zeit und Kontrolle mit
    Nahkampf-Reichweite (laut Client höchstens SM.MELEE_RANGE Meter – Combo-Aufbauer, Finishing-Moves, Nahkampfschläge:
    eine Maus-Fassung bringt dort nichts, die Combo-Punkte liegen auf dem Ziel) und alles aus ezCores Spells.CLASS der
    Klasse unter reactive, finisher und nextSwing (nur nach Parieren/Ausweichen, mit Combo-Punkten, mit dem nächsten
    Schlag – SSOT, dieselben Listen wie ezCombat).
    Den Zauber-Teil der /cast-Zeile baut ezCore (Spells.MacroCast) aus derselben Form wie die Makro-Logik der Vorlagen.
    Das Makro nennt den Zauber ohne Rang ({s:Grund-ID}): im Spiel wirkt so immer der höchste gelernte Rang, wie bei den
    Vorlagen (ns.Resolve, Ränge über ezCore).
    Nur Zauber, die ezCores Client-Tabelle kennt (Klassen- und Talentzauber); Volks-, Berufs- und allgemeine Zauber
    stehen in den Vorlagen (Data\Races.lua, Data\General.lua).

    Sichtbar im ezMacro-Fenster (Entwurf A), Reiter „Makros“, Auswahl „Für mich“: eine eigene Gruppe „Aus deinen
    Fähigkeiten“ mit Kopfzeile hinter den handgeschriebenen Vorlagen und vor den eigenen; je Eintrag Tooltip mit Art,
    erzeugtem Makrotext und Quelle; Übernehmen, Anpassen, Ziehen, Teilen wie bei jeder Vorlage (gemerkte Anpassungen in
    ezMacroDB.edits unter „spell:<Grund-ID>“). Der Filter „Empfohlen“ versteckt die Gruppe nie. Schalter
    „Makros aus deinen Fähigkeiten“ (macroFromSpells, ab Werk an) blendet sie aus (Leitlinie 3).

      SM.Enabled()               Schalter an?
      SM.Entries()               → Einträge (zwischengespeichert bis SPELLS_CHANGED, LEARNED_SPELL_IN_SKILL_LINE oder Schalter)
      SM.Entry(info)             → Eintrag aus ezCore.SpellKinds.Of(…)
      SM.Body(zauber, art)       → Makrotext mit {s:ID} oder nil (Art ohne Makro)
      SM.Logic(zauber, art)      → Zielkette (SM.LOGIC, bei Heilung/Stärkung nicht auf dich SM.FRIEND_OTHERS)
      SM.NotSelf(zauber)         → geht nicht auf dich selbst? (ns.NOT_SELF, auch über die Grund-ID)
      SM.NotSelfText()           → Zeile „Geht nicht auf dich selbst – laut Client-Tabellen …“
      SM.Name(zauber, art, belegt) → Name höchstens 16 Zeichen mit Kürzel (MO) bzw. (F); belegt(name) → true: Zahl davor
      SM.UniqueNames(liste)      → gleiche Kurznamen (untereinander, mit sichtbaren Vorlagen) bekommen eine Zahl
      SM.Covered()               → { [Zauber-ID und Grund-ID] = true } aller Zauber der Vorlagen
      SM.KnownSpells()           → IDs der gelernten Zauber (ezCore Spells.ForEachKnown, höchster Rang)
      SM.TipLines(eintrag)       → Zeilen für den Tooltip: Art, erzeugtes Makro, Quelle
      SM.HEADER                  Kopfzeile der Gruppe in der Liste (Feld header = true)
      SM.Page()                  Seite der Kopfzeile (Spieltest 20.11.2026, Entscheidung „Erklärseite + Knöpfe“):
                                 was die Gruppe ist, wie viele Makros, Knöpfe „Ersten zeigen“, „Einklappen“,
                                 „Ausblenden“ – ein Werkzeug (ns.Tools) ohne eigenen Reiter, angelegt beim ersten Aufruf
      SM.Collapsed() / SM.SetCollapsed(an)   Gruppe in der Liste eingeklappt (nur die Kopfzeile, ns.db.window)
]]

local SM = {}
ns.SpellMacros = SM

SM.CATEGORY = "spells"
SM.HEADER = { header = true, id = "spells:header", category = "spells" }
SM.ORDER = { interrupt = 1, cc = 2, dot = 3, harm = 4, heal = 5, help = 6, any = 7 }

-- Art » Zielkette wie in ezCores Makro-Logik (kind, unit, chain), Zeile davor, Kürzel im Namen
local FOCUS = { kind = "focus", unit = "harm", chain = { "focus", "target" }, suffix = "(F)" }
local ENEMY = { kind = "mouseover", unit = "harm", chain = { "mouseover", "target" }, suffix = "(MO)" }
local FRIEND = { kind = "mouseover", unit = "help", chain = { "mouseover", "target", "player" }, suffix = "(MO)" }
local ANY = { kind = "mouseover", unit = "exists", chain = { "mouseover", "target" }, suffix = "(MO)" }
SM.LOGIC = {
    interrupt = { kind = FOCUS.kind, unit = FOCUS.unit, chain = FOCUS.chain, suffix = FOCUS.suffix, pre = "/stopcasting" },
    cc = FOCUS, dot = ENEMY, harm = ENEMY, heal = FRIEND, help = FRIEND, any = ANY,
}
-- Heilung und Stärkung, die nicht auf dich gehen (ns.NOT_SELF, Data\Classes.lua – laut Client-Tabelle SpellMisc;
-- Fund c des Reviews vor dem Merge von Welle 27): dieselbe Kette ohne „sonst du“ – das letzte Glied ist das Ziel
-- („[@mouseover,party][@mouseover,raid][@mouseover,help,nodead][]“; passt es nicht, meldet Blizzard es selbst)
-- Ohne Spells.MacroCast: dieselben Bedingungen über ezCores Spells.MacroCondition (Paket ezmacro/ssot-doppelungen –
-- vorher fester Text hier; ns.GroupFirst hebt sie danach wie zuvor auf die Gruppen-Glieder). Ehrlich: Den Rückfall
-- erreicht nur noch ein ezCore, das MacroCondition, aber nicht MacroCast kennt; beide verlangt ns.CORE_NEEDS.
local Cond = Core.Spells.MacroCondition
SM.FRIEND_OTHERS = { kind = "mouseover", unit = "help", chain = { "mouseover", "target" }, suffix = "(MO)",
    fallback = Cond(nil, "help", { "mouseover", "target" }) }
local FALLBACK = { focus = Cond(nil, FOCUS.unit, FOCUS.chain), harm = Cond(nil, ENEMY.unit, ENEMY.chain),
    help = Cond(nil, FRIEND.unit, FRIEND.chain), exists = Cond(nil, ANY.unit, ANY.chain) }

function SM.Enabled()
    return ns.S == nil or ns.S.macroFromSpells ~= false
end

SM.ICON = { "INV_Misc_Book_09", "INV_Misc_Book_11" }   -- Buch wie Blizzards Zauberbuch (das erste, das der Client kennt)

function SM.Collapsed()
    return ns.db ~= nil and type(ns.db.window) == "table" and ns.db.window.spellsCollapsed == true
end

function SM.SetCollapsed(collapsed)
    if not (ns.db and type(ns.db.window) == "table") then return end
    ns.db.window.spellsCollapsed = collapsed and true or nil
    if ns.Browser and ns.Browser.Refresh then ns.Browser.Refresh() end
end

-- Wie viele Makros stehen in der Gruppe, wie viele davon gibt es schon in Blizzards Makroverwaltung?
function SM.Counts()
    local total, existing = 0, 0
    -- auch unter dem Namen der anderen Fassung (Schalter „Maus über“ umgestellt, Import.FindEntry)
    local find = ns.Import and ns.Import.FindEntry
    for _, entry in ipairs(SM.Entries()) do
        total = total + 1
        if type(find) == "function" and find(entry, ns.EntryName(entry)) then existing = existing + 1 end
    end
    return total, existing
end

local page
function SM.Page()
    if page or not ns.Tools then return page end
    local UI = ns.UI
    page = ns.Tools.Register({
        key = "spellGroup", order = 99, place = "spellgroup", icon = SM.ICON,
        shown = function() return false end,   -- kein Werkzeug der Listen und Statuszeilen, nur die Seite der Kopfzeile
        name = L.SPELLMACRO_GROUP, why = L.SPELLMACRO_GROUP_DESC, desc = L.SPELLMACRO_PAGE_DESC,
        status = function()
            local total, existing = SM.Counts()
            return L.SPELLMACRO_PAGE_COUNT:format(total, existing)
        end,
        build = function(panel)
            panel.first = UI.Button(panel, L.SPELLMACRO_PAGE_FIRST, 150, function()
                local first = SM.Entries()[1]
                if not first then return end
                if SM.Collapsed() then SM.SetCollapsed(false) end
                ns.Browser.ShowEntry(first)
            end, L.SPELLMACRO_PAGE_FIRST, L.SPELLMACRO_PAGE_FIRST_TIP)
            panel.first:SetPoint("TOPLEFT", panel.top, "BOTTOMLEFT", 0, -10)
            panel.fold = UI.Button(panel, L.SPELLMACRO_PAGE_COLLAPSE, 130, function()
                SM.SetCollapsed(not SM.Collapsed())
                ns.Tools.RefreshKey("spellGroup")
            end, L.SPELLMACRO_PAGE_COLLAPSE, L.SPELLMACRO_PAGE_COLLAPSE_TIP)
            panel.fold:SetPoint("LEFT", panel.first, "RIGHT", 6, 0)
            panel.hide = UI.Button(panel, L.SPELLMACRO_PAGE_HIDE, 130, function()
                ns.SetSetting("macroFromSpells", false)
                if ns.Browser and ns.Browser.Refresh then ns.Browser.Refresh() end
            end, L.SPELLMACRO_PAGE_HIDE, L.SPELLMACRO_PAGE_HIDE_TIP)
            panel.hide:SetPoint("LEFT", panel.fold, "RIGHT", 6, 0)
            panel.info = UI.Text(panel, "GameFontHighlightSmall", panel.width)
            panel.info:SetPoint("TOPLEFT", panel.first, "BOTTOMLEFT", 0, -10)
        end,
        refresh = function(panel)
            panel.fold:SetText(SM.Collapsed() and L.SPELLMACRO_PAGE_EXPAND or L.SPELLMACRO_PAGE_COLLAPSE)
            panel.first:SetEnabled(#SM.Entries() > 0)
            panel.info:SetText(L.SPELLMACRO_PAGE_HOW)
        end,
    })
    page.id = SM.HEADER.id      -- die Kopfzeile in der Liste ist der Platz dieser Seite (Auswahl, Hervorhebung)
    return page
end

-- Geht der Zauber nicht auf dich selbst? (ns.NOT_SELF; Rang über die Grund-ID aus ezCore)
function SM.NotSelf(spell)
    spell = tonumber(spell)
    local list = ns.NOT_SELF
    if not (spell and type(list) == "table") then return false end
    if list[spell] then return true end
    local Base = Core.SpellKinds and Core.SpellKinds.Base
    local base = type(Base) == "function" and Base(spell) or nil
    return base ~= nil and list[base] == true
end

-- Zielkette eines Zaubers dieser Art: wie SM.LOGIC, für Heilung und Stärkung, die nicht auf dich gehen, ohne „sonst du“
function SM.Logic(spell, kind)
    local logic = SM.LOGIC[kind]
    if logic == FRIEND and SM.NotSelf(spell) then return SM.FRIEND_OTHERS end
    return logic
end

function SM.Body(spell, kind)
    local logic = SM.Logic(spell, kind)
    spell = tonumber(spell)
    if not (logic and spell) then return nil end
    local cast
    local MacroCast = Core.Spells and Core.Spells.MacroCast
    if type(MacroCast) == "function" then
        cast = MacroCast({ steps = { { spell = spell } }, kind = logic.kind, unit = logic.unit, chain = logic.chain })
    end
    if type(cast) ~= "string" then
        cast = (logic.fallback or FALLBACK[logic.kind == "focus" and "focus" or logic.unit]) .. (" {s:%d}"):format(spell)
    end
    local lines = { "#showtooltip" }
    if logic.pre then lines[#lines + 1] = logic.pre end
    lines[#lines + 1] = "/cast " .. cast
    return ns.GroupFirst(table.concat(lines, "\n"))
end

-- Gekürzt wird nach Zeichen (Core.UniqueName über Core.TruncateChars), wie ezCore die Grenze misst
-- (Core.Macro.NameLength); ob Forever bei Umlauten Bytes zählt, zeigt erst der Spieltest (docs/roadmap/ezMacro.md,
-- „Im Spiel prüfen (Welle 27)“). taken(name) → true, wenn belegt: dann eine Zahl vor dem Kürzel, damit zwei Einträge
-- nicht gleich heißen („Sengender 2 (MO)“, SM.UniqueNames). Die Zählung macht ezCore (Core.UniqueName mit Kürzel).
-- plain == true: ohne Kürzel (Schalter „Maus über“ für dieses Makro aus, Resolver.lua – ohne Maus kein „(MO)“).
function SM.Name(spell, kind, taken, plain)
    local logic = SM.LOGIC[kind]
    local name = ns.SpellName(spell)
    if type(name) ~= "string" or name == "" then name = "#" .. tostring(spell) end
    local suffix = not plain and logic and logic.suffix or nil
    return Core.UniqueName(name, taken, { format = "%s %d", maxChars = ns.MACRO_NAME_MAX,
        suffix = suffix and (" " .. suffix) or nil, default = "#" .. tostring(spell) })
end

-- Name in Stamm und Kürzel der Makros aus deinen Fähigkeiten zerlegen („Sengender S (MO)“ → „Sengender S“, „ (MO)“;
-- Kürzel aus SM.LOGIC). Ohne Kürzel: name, "". Damit setzt Custom.FreeName die Zahl vor das Kürzel wie SM.Name, und ein
-- langer Name verliert beim Kürzen nicht das Kürzel (Gegenprüfung des Pakets modul/ezmacro-reste: sonst „Sengender S (M 2“).
function SM.SplitSuffix(name)
    if type(name) ~= "string" then return name, "" end
    local seen = {}
    for _, logic in pairs(SM.LOGIC) do
        local suffix = logic.suffix and " " .. logic.suffix
        if suffix and not seen[suffix] then
            seen[suffix] = true
            local stem = name:sub(1, #name - #suffix)
            if #name > #suffix and name:sub(-#suffix) == suffix and Core.Trim(stem) ~= "" then return stem, suffix end
        end
    end
    return name, ""
end

-- Gleiche Kurznamen abfangen (Fund b des Reviews vor dem Merge von Welle 27): Zwei lange Zaubernamen können gekürzt
-- gleich lauten, oder ein erzeugter Name gleicht dem einer Vorlage (alle außer denen fremder Klassen), einer eigenen
-- Vorlage (ns.Custom, steht in „Für mich“ daneben) oder dem angepassten Namen eines erzeugten Eintrags. Angepasste
-- Namen zählen überall; einen angepassten Namen hat der Nutzer gewählt, er bekommt keine Zahl. Der Zauber mit der
-- kleineren Grund-ID behält den Namen, die übrigen bekommen eine Zahl vor dem Kürzel – unabhängig von der Reihenfolge
-- im Zauberbuch. Ändert die Einträge der Liste, gibt sie zurück. Ändert sich ein Name, baut ns.NamesChanged neu.
function SM.UniqueNames(list)
    local taken = {}
    local function Take(name)
        if type(name) == "string" then taken[name] = true end
    end
    if ns.db then
        for _, e in ipairs(ns.MACROS) do
            if e.category ~= "class" or e.group == ns.playerClass then Take(ns.EntryName(e)) end
        end
        for _, e in ipairs(ns.Custom and ns.Custom.Entries() or {}) do Take(ns.EntryName(e)) end
    end
    local order = {}
    for _, e in ipairs(list) do
        local edit = ns.db and ns.db.edits and ns.db.edits[e.id]
        if edit and type(edit.name) == "string" then Take(edit.name) else order[#order + 1] = e end
    end
    table.sort(order, function(a, b) return (tonumber(a.spell) or 0) < (tonumber(b.spell) or 0) end)
    -- Schalter „Maus über“ (Resolver.lua): ohne Maus ohne Kürzel (namePlain merkt, für welche Fassung name gilt).
    -- otherName = Name der anderen Fassung mit eigener Zählung (zweiter Durchlauf über dieselbe Grundmenge), damit ein
    -- schon übernommenes Makro wiedergefunden wird (Import.FindEntry) und nie das eines anderen Eintrags
    local base = {}
    for name in pairs(taken) do base[name] = true end
    local function Taken(name) return taken[name] end
    for _, e in ipairs(order) do
        e.namePlain = ns.MouseoverActive(e) == false
        e.name = SM.Name(e.spell, e.kind, Taken, e.namePlain)
        taken[e.name] = true
    end
    local other = {}
    local function OtherTaken(name) return base[name] or other[name] end
    for _, e in ipairs(order) do
        e.otherName = nil
        if ns.MouseoverActive(e) ~= nil then
            e.otherName = SM.Name(e.spell, e.kind, OtherTaken, not e.namePlain)
            other[e.otherName] = true
        end
    end
    return list
end

-- Zauber der Vorlagen (Klasse, Volk, Allgemein) samt Grund-ID: diese bekommen kein erzeugtes Makro. Einmal gebaut –
-- die Vorlagen stehen nach dem Laden fest.
local covered
function SM.Covered()
    if covered then return covered end
    covered = {}
    local Base = Core.SpellKinds and Core.SpellKinds.Base
    for _, entry in ipairs(ns.MACROS) do
        for _, id in ipairs(ns.TemplateSpells(entry.body, true)) do
            covered[id] = true
            local base = Base and Base(id)
            if base then covered[base] = true end
        end
    end
    return covered
end

function SM.KnownSpells()
    local list = {}
    local Spells = Core.Spells
    if not (Spells and type(Spells.ForEachKnown) == "function") then return list end
    Spells.ForEachKnown(function(e)
        local id = type(e) == "table" and Core.Num(Core.Plain(e.maxID)) or nil
        if id then list[#list + 1] = id end
    end)
    return list
end

-- Passiv laut Client (Leitlinie 6: gesperrt zählt als „weiß nicht“, dann entscheidet die Tabelle)
local function Passive(id)
    local fn = (C_Spell and C_Spell.IsSpellPassive) or IsPassiveSpell
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, id)
    return ok and Core.Bool(value, false) == true
end

local function Format(key, name)
    local pair = ns.TextPair(key)
    return { (pair[1] or ""):format(name), (pair[2] or pair[1] or ""):format(name) }
end

function SM.Entry(info)
    if type(info) ~= "table" or not SM.LOGIC[info.kind] then return nil end
    local base, kind = info.base, info.kind
    local spellName = ns.SpellName(base) or ("#" .. tostring(base))
    -- Heilung oder Stärkung, die nicht auf dich geht: eigene Beschreibung ohne „oder dich“ (Kette SM.FRIEND_OTHERS)
    local notSelf = SM.Logic(base, kind) == SM.FRIEND_OTHERS
    local textKind = notSelf and "others" or kind
    -- Erklär-Seite: Beschreibung, darunter Art und Quelle (Leitlinie 11; Art und Quelle in der Sprache des Clients)
    local desc = Format("SPELLMACRO_DESC_" .. textKind, spellName)
    local SK = Core.SpellKinds
    local note = L.SPELLMACRO_TIP_KIND:format(SM.KindLabel(kind)) .. " · "
        .. L.SPELLMACRO_TIP_SOURCE:format(SK and SK.SourceText and SK.SourceText(info.source) or "")
    if notSelf then note = note .. "\n" .. SM.NotSelfText() end
    desc[1], desc[2] = desc[1] .. "\n" .. note, desc[2] .. "\n" .. note
    return {
        id = "spell:" .. tostring(base),
        category = SM.CATEGORY,
        group = ns.playerClass,
        generated = true,
        spell = base,
        kind = kind,
        notSelf = notSelf or nil,
        source = info.source,
        name = SM.Name(base, kind),
        desc = desc,
        why = ns.TextPair("SPELLMACRO_WHY_" .. textKind),
        body = SM.Body(base, kind),
        need = base,
    }
end

local cache
function SM.Invalidate() cache = nil end

-- Nahkampf (Kopf): Reichweite laut Client höchstens so viele Meter (Blizzards Nahkampf meldet 0 bzw. 5)
SM.MELEE_RANGE = 5
SM.MELEE_KINDS = { harm = true, dot = true, cc = true }
SM.CLASS_SKIP = { "reactive", "finisher", "nextSwing" }

-- Zauber aus ezCores Spells.CLASS[klasse] unter SM.CLASS_SKIP → { [id] = true }
function SM.ClassSkip(class)
    local S = Core.Spells
    local list = S and type(S.CLASS) == "table" and type(class) == "string" and S.CLASS[class] or nil
    local out = {}
    for _, key in ipairs(SM.CLASS_SKIP) do
        for _, id in ipairs(type(list) == "table" and list[key] or {}) do out[id] = true end
    end
    return out
end

-- Nahkampf-Zauber einer Art mit Ziel? (ohne Reichweite laut Client: nein)
function SM.Melee(info)
    if type(info) ~= "table" or not SM.MELEE_KINDS[info.kind] then return false end
    local range = Core.Num(info.maxRange)
    return range ~= nil and range <= SM.MELEE_RANGE
end

function SM.Entries()
    if not SM.Enabled() then return {} end
    if cache then return cache end
    local out = {}
    local SK = Core.SpellKinds
    if not (SK and type(SK.Of) == "function") then
        cache = out
        return out
    end
    local skip = SM.Covered()
    local noGenerate = ns.NO_GENERATE or {}
    local classSkip = SM.ClassSkip(ns.playerClass)
    local seen = {}
    for _, id in ipairs(SM.KnownSpells()) do
        local info = SK.Of(id)
        -- info.class: nur Zauber, die ezCores Client-Tabelle kennt (Klassen- und Talentzauber)
        if info and info.class and SM.LOGIC[info.kind] and not skip[info.base] and not skip[id]
            and not noGenerate[info.base] and not noGenerate[id] and not classSkip[info.base] and not classSkip[id]
            and not SM.Melee(info) and not seen[info.base] and not Passive(id) then
            seen[info.base] = true
            local entry = SM.Entry(info)
            if entry and entry.body then out[#out + 1] = entry end
        end
    end
    SM.UniqueNames(out)
    table.sort(out, function(a, b)
        local oa, ob = SM.ORDER[a.kind] or 99, SM.ORDER[b.kind] or 99
        if oa ~= ob then return oa < ob end
        return a.name < b.name
    end)
    cache = out
    return out
end

function SM.KindLabel(kind)
    return L["SPELLMACRO_KIND_" .. tostring(kind)]
end

-- „Geht nicht auf dich selbst – laut Client-Tabellen (SpellMisc, Build …)“ (Leitlinie 11: die Angabe nennt ihre Quelle)
function SM.NotSelfText()
    return L.SPELLMACRO_TIP_NOTSELF:format(tostring(ns.NOT_SELF_BUILD or "?"))
end

function SM.TipLines(entry)
    if type(entry) ~= "table" or not entry.generated then return {} end
    local SK = Core.SpellKinds
    local lines = { L.SPELLMACRO_TIP_KIND:format(SM.KindLabel(entry.kind)) }
    if entry.notSelf then lines[#lines + 1] = SM.NotSelfText() end
    lines[#lines + 1] = L.SPELLMACRO_TIP_BODY
    for line in ((ns.EntryBody(entry)) .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    local source = SK and SK.SourceText and SK.SourceText(entry.source) or ""
    lines[#lines + 1] = L.SPELLMACRO_TIP_SOURCE:format(source)
    return lines
end

ns.On("SPELLS_CHANGED", SM.Invalidate)
ns.On("LEARNED_SPELL_IN_SKILL_LINE", SM.Invalidate)
ns.OnSettingChanged(function(key)
    if key == "macroFromSpells" then SM.Invalidate() end
end)
