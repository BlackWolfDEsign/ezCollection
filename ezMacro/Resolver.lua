local _, ns = ...
local L = ns.L
local Core = ezCore

-- Übersetzt Makro-Vorlagen in die Client-Sprache:
--   {s:2061}  -> Zaubername aus ezCores Zauber-Wissen (Client-Sprache, Ersatznamen in ezCore/SpellData.lua)
--   {s:9634|5487} -> der erste gelernte der Zauber (der beste zuerst), sonst der letzte (z. B. Terrorbären- bzw.
--                Bärengestalt; Wiederbeleben, sonst Wiedergeburt)
--   {e:THANK} -> Emote-Befehl des Clients, z. B. /danke oder /thank
--   {t:OOM}   -> Textbaustein aus Locale.lua (MT_OOM)
--   {r:opener}, {g:shield} -> Text, der erst beim Übernehmen entsteht (Dynamic.lua: Eröffnung aus ezCombat, Waffe
--                und Schild aus Tasche und Ausrüstung). Fehlt die Grundlage, entfällt die ganze Zeile.
--   {i:food}  -> bester Gegenstand bzw. Reittier einer Art (OneClick.lua, Reiter „Ein-Klick“), ebenso ganze Zeilen

ns.MACRO_MAX_CHARS = ezCore.Macro.MAX_CHARS   -- aus ezCore (Gesamtreview 18.11.2026, T16-8; vorher eigener Wert)
ns.MACRO_NAME_MAX = 16
ns.DEFAULT_ICON = ezCore.Macro.DEFAULT_ICON -- Fragezeichen (134400): mit #showtooltip zeigt das Makro den Zauber selbst

---------------------------------------------------------------------------
-- Zauber: Namen, Symbole und „bekannt“ kommen aus ezCores Zauber-Wissen (ezCore.Spells, vorher hier).
-- Die Ersatznamen für IDs, die der Client nicht kennt, stehen in ezCore/SpellData.lua (SSOT).
---------------------------------------------------------------------------

local Spells = ezCore.Spells
ns.SPELLS = Spells.FALLBACK   -- { [id] = { "Deutsch", "English" } }, nur lesen

-- Liefert Name und ob er vom Client stammt (false = Ersatzname aus den Daten).
function ns.SpellName(id)
    return Spells.Name(id)
end

function ns.SpellIcon(id)
    return Spells.Icon(id)
end

-- Kennt der Spieler (oder sein Begleiter) den Zauber? Bei Rängen genügt irgendein Rang. Ohne ID: ja.
function ns.IsSpellKnown(id)
    id = tonumber(id)
    if not id then return true end
    return Spells.IsKnown(id)
end

-- Zauber-ID, die auf einen Aktionsplatz kommt (Leisten-Profile, Ränge): der höchste gelernte Rang aus dem
-- Zauberbuch, sonst die ID selbst, falls bekannt. nil = nicht gelernt. Eine Fassung in ezCore (Core.BarProfiles,
-- Architektur-Review 22.11.2026), hier die Weiterleitung unter dem bisherigen Namen.
function ns.BestKnownSpell(id)
    return ezCore.BarProfiles.BestKnownSpell(id)
end

---------------------------------------------------------------------------
-- Emotes
---------------------------------------------------------------------------

-- Befehl des Clients zu einem Emote-Token („THANK“ → „/danke“ bzw. „/thank“) aus Blizzards Tabellen,
-- eine Umsetzung in ezCore (auch für ezBuff).
ns.EmoteCommand = ezCore.EmoteCommand

---------------------------------------------------------------------------
-- Vorlagen
---------------------------------------------------------------------------

-- Zauber eines Platzhalters {s:…}: bei „a|b|c“ der erste gelernte, sonst der letzte (die Grundform). Rückgabe: ID.
function ns.PickSpell(arg)
    local ids = {}
    for id in tostring(arg or ""):gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
    if #ids <= 1 then return ids[1] end
    for _, id in ipairs(ids) do
        if ns.IsSpellKnown(id) then return id end
    end
    return ids[#ids]
end

-- Markiert eine Zeile, die wegfällt, weil ein Platzhalter von Dynamic.lua nichts liefert.
local DROP = "\1"

-- Gibt den fertigen Text und eine Liste der IDs zurück, für die nur ein Ersatzname da war.
function ns.Resolve(template)
    local missing = {}
    local text = (template or ""):gsub("{(%a):([^}]+)}", function(kind, arg)
        if kind == "s" then
            local id = ns.PickSpell(arg)
            local name, fromClient = ns.SpellName(id)
            if not fromClient then missing[#missing + 1] = tostring(id or arg) end
            return name or ("?" .. tostring(id or arg))
        elseif kind == "r" or kind == "g" or kind == "i" then
            -- Eröffnung (ezCombat), Waffe und Schild bzw. bester Gegenstand (Ein-Klick): ganze Zeilen, sonst entfällt
            -- die Zeile
            local line = ns.Dynamic and ns.Dynamic.Line(kind, arg)
            return line or DROP
        elseif kind == "e" then
            -- Blizzards Emote-Befehl; Spucken über „/ezmacro emote SPIT“ (mit Ziel ein Text-Emote, Emote.lua)
            return ns.Emote.Command(arg)
        elseif kind == "t" then
            return L["MT_" .. arg]
        elseif kind == "c" then
            -- Ansagen: Anfang der Zeile je nach Einstellung („/ezmacro ansage warn“ bzw. /rw, /raid, /i, /p)
            return ns.Announce.Command(arg)
        elseif kind == "p" then
            -- Pull-Ansage „Sekunden|Text“: Pull-Timer eines laufenden Addons oder die eigene Ansage
            local seconds, say = arg:match("^(%d+)|(.*)$")
            if seconds then return ns.Announce.PullLine(seconds, say) end
        end
        return nil -- unbekannt: unverändert lassen
    end)
    if text:find(DROP, 1, true) then
        local kept = {}
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            if not line:find(DROP, 1, true) then kept[#kept + 1] = line end
        end
        text = table.concat(kept, "\n")
    end
    -- Feste Kanäle: %z (Gebiet) kann Blizzards Chat nicht einsetzen – dort steht „meine Position“; das Zielsymbol %r
    -- (MACRO-26) setzt nur ezMacro beim Klick ein, im festen Makro fällt es weg.
    if (text:find("%z", 1, true) or text:find("%r", 1, true)) and ns.Announce and not ns.Announce.Auto() then
        text = ns.Announce.FixedText(text)
    end
    return text, missing
end

-- Alle Spell-IDs einer Vorlage in Reihenfolge; bei „{s:a|b}“ der gewählte (ns.PickSpell), mit all = true alle.
function ns.TemplateSpells(template, all)
    local list = {}
    for arg in (template or ""):gmatch("{s:([%d|]+)}") do
        if all then
            for id in arg:gmatch("%d+") do list[#list + 1] = tonumber(id) end
        else
            list[#list + 1] = ns.PickSpell(arg)
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Einträge
---------------------------------------------------------------------------

function ns.MainSpell(entry)
    if entry.need == false then return nil end
    if entry.need then return entry.need end
    return ns.TemplateSpells(entry.body)[1]
end

-- entry.needs = "opener": nur nutzbar, wenn Dynamic.lua den Text bauen kann (Eröffnung aus ezCombat).
function ns.IsEntryKnown(entry)
    if entry.needs and not (ns.Dynamic and ns.Dynamic.Ready(entry.needs)) then return false end
    local spell = ns.MainSpell(entry)
    if not spell then return true end
    return ns.IsSpellKnown(spell)
end

-- Feste Symbole: entry.icon ist ein Name oder eine Liste { Wunsch, Ersatz, … }. Genommen wird das erste
-- Symbol, das der Client kennt (neuere Symbole fehlen womöglich im Forever-Client).
-- Rückgabe: Pfad und Datei-ID (nil, wenn der Client keine Datei-IDs nennt).
local function FixedIcon(icon)
    local names = type(icon) == "table" and icon or { icon }
    for _, name in ipairs(names) do
        local path = "Interface\\Icons\\" .. name
        if not GetFileIDFromPath then return path, nil end
        local fileID = GetFileIDFromPath(path)
        if fileID and fileID > 0 then return path, fileID end
    end
    return "Interface\\Icons\\" .. names[#names], nil
end

-- Pfad eines festen Symbols (Name oder Liste von Namen, das erste vorhandene zählt).
function ns.IconPath(icon)
    return (FixedIcon(icon))
end

function ns.EntryIcon(entry)
    if entry.custom then return entry.icon or ns.DEFAULT_ICON end
    if entry.icon then return (FixedIcon(entry.icon)) end
    -- ezHeals Heil-Makros (HealMacros.lua): fertiger Text ohne {s:…}, der Zauber kommt aus ezHeals Schritten
    if entry.iconSpell then return ns.SpellIcon(entry.iconSpell) or ns.DEFAULT_ICON end
    local spell = ns.TemplateSpells(entry.body)[1]
    -- Ein-Klick: der Gegenstand steht erst im fertigen Text (entry.needs); entry.glyph, solange keiner da ist
    local body = entry.needs and (ns.EntryBody(entry)) or entry.body
    local itemID = body:match("^#showtooltip item:(%d+)")
    if itemID then
        return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(tonumber(itemID))) or ns.DEFAULT_ICON
    end
    local kindIcon = entry.needs and ns.OneClick and ns.OneClick.Icon(entry.needs)
    if kindIcon then return kindIcon end
    if entry.glyph then return (FixedIcon(entry.glyph)) end
    local slot = entry.body:match("^#showtooltip (%d+)\n")
    if slot then
        return GetInventoryItemTexture("player", tonumber(slot)) or "Interface\\Icons\\INV_Jewelry_Talisman_01"
    end
    if spell then return ns.SpellIcon(spell) or ns.DEFAULT_ICON end
    return ns.DEFAULT_ICON
end

-- Symbol für CreateMacro: feste Symbole als Datei-ID, sonst das dynamische Fragezeichen.
function ns.MacroIcon(entry)
    if entry.custom then return entry.icon end
    if entry.icon then
        local _, fileID = FixedIcon(entry.icon)
        return fileID or ns.DEFAULT_ICON
    end
    return ns.DEFAULT_ICON
end

-- Fähigkeiten, die das Makro auf der Aktionsleiste ersetzt: alle Zauber der Vorlage außer Haltungen,
-- in die es nur als Rückfall wechselt (z. B. „…; Kampfhaltung“; Knurren wechselt erst in die Bärengestalt).
-- Die Haltungen und Gestalten führt ezCore (Spells.MacroFallbackForms aus FAMILIES.stance und den Bärengestalten;
-- Paket ezmacro/ssot-doppelungen) – vorher stand hier eine eigene Liste derselben fünf Zauber.
local STANCE_FALLBACKS = Spells.MacroFallbackForms()
function ns.ReplacedSpells(entry)
    local spells, seen = {}, {}
    for _, id in ipairs(ns.TemplateSpells(entry.body)) do
        if not STANCE_FALLBACKS[id] and not seen[id] then
            seen[id] = true
            spells[#spells + 1] = id
        end
    end
    return spells
end

---------------------------------------------------------------------------
-- Maus über wahlweise (Entscheidungen des Nutzers vom 23.11.2026: „Einer für alle, abweichbar (Empfohlen)“ und „Ja,
-- eigener Schalter (Empfohlen)“; docs/roadmap/ezMacro.md, „Neue Recherche: alle sinnvollen Klassenmakros, Maus-über
-- wahlweise“, Schritt 1 und 2). Blizzards „Mouseover-Zauber“ wirkt nur auf Zauber auf Leisten, nicht auf Makros
-- (docs/klassenmakros-recherche.md, Erkenntnis 1). Die Einstellungen „Maus über Mitspieler“ (mouseoverFriend) und „Maus
-- über Gegner“ (mouseoverHostile) gelten für alle Vorlagen mit Gliedern „Einheit unter der Maus“; das Kästchen „Maus
-- über“ im ezMacro-Fenster weicht je Makro ab (ezMacroDB.mouseover[id] = { friend = …, hostile = … }, nur Abweichungen).
-- Gestrichen wird an einer Stelle in ezCore (Spells.MacroMouseover); ohne Maus heißt die Vorlage ohne „(MO)“.
-- Nie betroffen: eigene Vorlagen, Werkzeuge, ezHeals Heil-Makros, die Klick-Zauber (Gruppe „Heilen und Buffen per
-- Klick“ behält die Kette immer) und schon übernommene WoW-Makros (die schreibt erst „Aktualisieren“ neu).
---------------------------------------------------------------------------

local MO_SETTING = { friend = "mouseoverFriend", hostile = "mouseoverHostile" }
local moKinds = setmetatable({}, { __mode = "k" })   -- [Eintrag] = { body = Vorlage, kinds = … } (Zwischenspeicher)

-- Welche Maus-Glieder hat die Vorlage? → { friend = true, hostile = true } (nur vorhandene) oder nil
function ns.MouseoverKinds(entry)
    if type(entry) ~= "table" or entry.custom or entry.tool or entry.heal or type(entry.body) ~= "string" then return nil end
    if entry.category == "general" and entry.group == "clickheal" then return nil end
    local fn = Core.Spells and Core.Spells.MacroMouseoverKinds
    if type(fn) ~= "function" then return nil end
    local cached = moKinds[entry]
    if not (cached and cached.body == entry.body) then
        cached = { body = entry.body, kinds = fn(entry.body) }
        moKinds[entry] = cached
    end
    return cached.kinds
end

-- Standard aus den Einstellungen (ab Werk an)
function ns.MouseoverDefault(kind)
    local key = MO_SETTING[kind]
    return not (key and ns.S and ns.S[key] == false)
end

-- Abweichung dieses Makros (Tabelle) oder nil. Nur für Vorlagen mit Maus-Gliedern: Die Hülle in der Gruppe „Heilen und
-- Buffen per Klick“ trägt die Kennung ihres Klassenmakros, hat aber selbst keine Abweichung (Durchsicht 24.11.2026 –
-- „Zurücksetzen“ dort löschte die des Klassenmakros).
function ns.MouseoverOverride(entry)
    if not ns.MouseoverKinds(entry) then return nil end
    local all = ns.db and ns.db.mouseover
    local own = type(all) == "table" and type(entry) == "table" and entry.id ~= nil and all[entry.id] or nil
    return type(own) == "table" and own or nil
end

function ns.MouseoverOn(entry, kind)
    local own = ns.MouseoverOverride(entry)
    if own and type(own[kind]) == "boolean" then return own[kind] end
    return ns.MouseoverDefault(kind)
end

-- Wirkt die Vorlage mit den Schaltern noch auf die Einheit unter der Maus? nil = Vorlage ohne Maus-Glieder
function ns.MouseoverActive(entry)
    local kinds = ns.MouseoverKinds(entry)
    if not kinds then return nil end
    for kind in pairs(kinds) do
        if ns.MouseoverOn(entry, kind) then return true end
    end
    return false
end

-- Kästchen „Maus über“: setzt die Abweichung für alle Maus-Glieder der Vorlage; was dem Standard gleicht, fällt weg
-- (so führt derselbe Klick zurück auf die Einstellung, Leitlinie 3). Ändert sich der Name, baut ns.NamesChanged neu.
function ns.SetMouseover(entry, on)
    local kinds = ns.MouseoverKinds(entry)
    if not (kinds and ns.db and type(ns.db.mouseover) == "table") then return end
    local before = ns.EntryName(entry)
    local own = {}
    on = on and true or false
    for kind in pairs(kinds) do
        if on ~= ns.MouseoverDefault(kind) then own[kind] = on end
    end
    ns.db.mouseover[entry.id] = next(own) and own or nil
    if ns.EntryName(entry) ~= before then ns.NamesChanged() end
end

-- Vorlage mit den Schaltern (Platzhalter {s:…} bleiben)
function ns.TemplateBody(entry)
    local body = entry.body
    if not ns.MouseoverKinds(entry) then return body end
    return Core.Spells.MacroMouseover(body, {
        friend = ns.MouseoverOn(entry, "friend"), hostile = ns.MouseoverOn(entry, "hostile") })
end

-- „Lichtblitz (MO)“ → „Lichtblitz“ (auch die Kurzform „Furchtschutz MO“)
local function WithoutMouseSuffix(name)
    name = name:gsub("%s*%(MO%)$", "")
    name = name:gsub("%s+MO$", "")
    return name
end

-- Makros aus deinen Fähigkeiten (SM.UniqueNames): name gilt für die Fassung namePlain, otherName für die andere.
-- Steht der Schalter inzwischen anders (Kästchen geklickt, noch nicht neu gebaut), gelten sie vertauscht.
-- → Name jetzt, Name der anderen Fassung
local function GeneratedNames(entry)
    if (ns.MouseoverActive(entry) == false) == entry.namePlain then return entry.name, entry.otherName end
    return entry.otherName or entry.name, entry.name
end

-- Name ohne Maus: plainName der Vorlage, wenn das gestrichene Kürzel einen anderen Namen träfe (englisch „Wave“ ist
-- das Emote-Makro „Winken“), sonst ohne „(MO)“
local function PlainName(entry, full)
    if entry.plainName then return ns.Text(entry.plainName) or full end
    return WithoutMouseSuffix(full)
end

-- Name der Vorlage mit den Schaltern: ohne Maus fällt das Kürzel „(MO)“ weg
function ns.TemplateName(entry)
    if entry.generated and entry.namePlain ~= nil then
        return ns.Truncate(ns.Text((GeneratedNames(entry))) or "", ns.MACRO_NAME_MAX)
    end
    local name = ns.Text(entry.name) or ""
    if ns.MouseoverActive(entry) == false then name = PlainName(entry, name) end
    return ns.Truncate(name, ns.MACRO_NAME_MAX)
end

-- Name der anderen Fassung (Schalter umgestellt: „Lichtblitz (MO)“ ↔ „Lichtblitz“), um ein schon übernommenes Makro
-- wiederzufinden (Import.FindEntry). nil ohne Maus-Glieder, bei angepasstem Namen oder ohne Kürzel.
function ns.MouseoverOtherName(entry)
    local active = ns.MouseoverActive(entry)
    if active == nil then return nil end
    local edit = ns.db and ns.db.edits and ns.db.edits[entry.id]
    if edit and type(edit.name) == "string" then return nil end
    if entry.generated then   -- Makros aus deinen Fähigkeiten (SM.UniqueNames)
        if entry.namePlain == nil then return nil end
        return select(2, GeneratedNames(entry))
    end
    local full = ns.Text(entry.name) or ""
    local plain = PlainName(entry, full)
    if plain == full then return nil end
    return ns.Truncate(active and plain or full, ns.MACRO_NAME_MAX)
end

-- Beschreibung für die Erklär-Seite: die Vorlagen sagen „unter der Maus, sonst Ziel“; ist die Maus für dieses Makro aus,
-- sagt ein Satz dahinter, was jetzt gilt (statt jede Beschreibung doppelt zu führen)
function ns.EntryDesc(entry)
    local desc = ns.Text(entry.desc)
    if ns.MouseoverActive(entry) ~= false then return desc end
    if type(desc) ~= "string" or desc == "" then return L.DETAIL_MOUSEOVER_OFF end
    return desc .. "\n" .. L.DETAIL_MOUSEOVER_OFF
end

-- Einstellung umgestellt: Namen und Texte der Liste ändern sich
ns.OnSettingChanged(function(key)
    if key == "mouseoverFriend" or key == "mouseoverHostile" then ns.NamesChanged() end
end)

function ns.EntryName(entry)
    if entry.custom or entry.tool then return ns.Truncate(entry.name or "", ns.MACRO_NAME_MAX) end
    local edit = ns.db.edits[entry.id]
    if edit and type(edit.name) == "string" then return edit.name end
    return ns.TemplateName(entry)
end

-- Fertiger Makrotext (angepasst oder aus der Vorlage, mit den Schaltern „Maus über“) und fehlende IDs.
function ns.EntryBody(entry)
    if entry.custom then return entry.body or "", {} end
    if entry.tool then return "", {} end
    local edit = ns.db.edits[entry.id]
    if edit and type(edit.body) == "string" then return edit.body, {} end
    return ns.Resolve(ns.TemplateBody(entry))
end

function ns.IsEdited(entry)
    if entry.custom or entry.tool then return false end
    return ns.db.edits[entry.id] ~= nil
end

-- Ein Makroname der Liste hat sich geändert (Anpassung, Zurücksetzen, eigene Vorlage angelegt oder entfernt): Die
-- erzeugten Einträge aus deinen Fähigkeiten weichen belegten Namen aus (SpellMacros.UniqueNames) und werden neu gebaut;
-- das Fenster baut seine Liste neu (Nachricht NAMES_CHANGED, Browser.lua).
function ns.NamesChanged()
    local SM = ns.SpellMacros
    if SM and type(SM.Invalidate) == "function" then SM.Invalidate() end
    if ns.Fire then ns.Fire("NAMES_CHANGED") end
end

-- Eigene Vorlagen speichern direkt in ihren Eintrag, mitgelieferte als Anpassung (ezMacroDB.edits).
function ns.SaveEdit(entry, name, body)
    local before = ns.EntryName(entry)
    if entry.custom then
        ns.Custom.Save(entry, name, body)
    else
        local defaultName = ns.TemplateName(entry)
        local defaultBody = ns.Resolve(ns.TemplateBody(entry))
        if name == defaultName and body == defaultBody then
            ns.db.edits[entry.id] = nil
        else
            ns.db.edits[entry.id] = { name = name, body = body }
        end
    end
    if ns.EntryName(entry) ~= before then ns.NamesChanged() end
end

function ns.ResetEdit(entry)
    if entry.custom or entry.tool then return end
    local before = ns.EntryName(entry)
    ns.db.edits[entry.id] = nil
    -- „Zurücksetzen“ nimmt auch die Abweichung „Maus über“ zurück (Entscheidung des Nutzers vom 23.11.2026)
    if type(ns.db.mouseover) == "table" and ns.MouseoverKinds(entry) then ns.db.mouseover[entry.id] = nil end
    if ns.EntryName(entry) ~= before then ns.NamesChanged() end
end

-- Nutzen in Alltagssprache („Das bringt dir“), ersatzweise die Beschreibung.
function ns.EntryWhy(entry)
    if entry.custom then return entry.why or L.CUSTOM_WHY end
    return ns.Text(entry.why) or ns.Text(entry.desc)
end

-- Worauf das Makro wirkt, wenn nicht aufs Ziel: "mouse" (Maus, Kürzel MO) oder "focus" (Fokus, Kürzel F).
function ns.EntryTarget(entry)
    -- mit den Schaltern „Maus über“: ohne Maus kein Schlagwort „Maus“
    local name, body = ns.TemplateName(entry), ns.TemplateBody(entry) or ""
    if name:find("%(F%)%s*$") then return "focus" end
    if name:find("%(MO%)%s*$") then return "mouse" end
    if body:find("@focus", 1, true) then return "focus" end
    if body:find("@mouseover", 1, true) then return "mouse" end
    return nil
end

-- Name für die Liste: ohne die Kürzel (MO)/(F), die dort als Schlagwort „Maus“/„Fokus“ erscheinen.
function ns.ShortName(entry)
    local name = ns.EntryName(entry):gsub("%s*%(MO%)$", ""):gsub("%s*%(F%)$", "")
    return name
end

function ns.GroupLabel(entry)
    if entry.category == "class" then return ns.ClassName(entry.group) end
    if entry.category == "race" then return ns.RaceName(entry.group) end
    if entry.category == "announce" then return L.TAB_announce .. " – " .. L["ANN_GROUP_" .. tostring(entry.group)] end
    if entry.category == "general" and entry.group == "clickheal" then return L.TAB_general .. " – " .. L.GROUP_clickheal end
    if entry.category == "heal" then return L.VIEW_heal end
    if entry.category == "spells" then return L.SPELLMACRO_GROUP end
    return L["TAB_" .. entry.category]
end

-- Alle Zauber-IDs, die ezMacros Vorlagen benutzen (Platzhalter {s:…} und Feld need).
function ns.UsedSpellIDs()
    local ids = {}
    for _, entry in ipairs(ns.MACROS) do
        for _, id in ipairs(ns.TemplateSpells(entry.body, true)) do ids[id] = true end
        if type(entry.need) == "number" then ids[entry.need] = true end
    end
    return ids
end

-- Anmeldung bei ezCores Zauber-Prüfung („/ez zauber“, Knopf „Zauber prüfen“; Welle 23, A2 – Vorbild ezCombat): Die
-- Menge entsteht erst beim Prüfen, dann sind alle Vorlagen geladen, auch die aus ezCores Makro-Logik.
if ezCore.Has("AddSpellSource") then ezCore.AddSpellSource("ezMacro", function() return ns.UsedSpellIDs() end) end

-- Prüft alle Zauber-IDs der Vorlagen gegen den Client (Befehl /ezmacro pruefen).
function ns.CheckSpells()
    local missing, total = {}, 0
    for id in pairs(ns.UsedSpellIDs()) do
        total = total + 1
        if not ezCore.SpellName(id) then missing[#missing + 1] = id end
    end
    table.sort(missing)
    if #missing == 0 then
        ns.Print(L.CMD_CHECK_OK:format(total))
        return
    end
    ns.Print(L.CMD_CHECK_MISSING:format(#missing, total))
    local line = {}
    for _, id in ipairs(missing) do
        line[#line + 1] = ("%d (%s)"):format(id, ns.Text(ns.SPELLS[id]) or "?")
        if #line == 4 then
            ns.Print("  " .. table.concat(line, ", "))
            wipe(line)
        end
    end
    if #line > 0 then ns.Print("  " .. table.concat(line, ", ")) end
end

---------------------------------------------------------------------------
-- Syntaxhinweise für angepasste Makros (wie Macro Toolkit): offene Klammern und unbekannte Befehle,
-- bevor das Makro übernommen wird – Blizzard zeigt solche Fehler erst beim Drücken.
---------------------------------------------------------------------------

local knownCommands = {}
local commandCheck   -- nil = noch nicht geprüft, true/false = Befehlsliste brauchbar

-- Ist der Befehl bekannt (Slash-Befehl, Chat-Typ, Emote)? Prüfung in ezCore, Ergebnis gemerkt.
local function CommandKnown(command)
    command = command:lower()
    local known = knownCommands[command]
    if known == nil then
        known = ezCore.SlashTaken(command) == true
        knownCommands[command] = known
    end
    return known
end

-- Liefert eine Liste { { line = n, kind = "bracket" | "command", text = "/befehl" }, … }.
function ns.LintMacro(body)
    local problems = {}
    if type(body) ~= "string" or body == "" then return problems end
    if commandCheck == nil then commandCheck = CommandKnown("/cast") end   -- ohne /cast keine Befehlsprüfung
    local index = 0
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        index = index + 1
        local _, opened = line:gsub("%[", "")
        local _, closed = line:gsub("%]", "")
        if opened ~= closed then problems[#problems + 1] = { line = index, kind = "bracket" } end
        local command = line:match("^%s*(/[^%s%[]+)")
        if command and commandCheck and not CommandKnown(command) then
            problems[#problems + 1] = { line = index, kind = "command", text = command }
        end
        -- Blizzard führt jede Zeile einzeln aus: auch in langen Makros höchstens 255 Zeichen je Zeile.
        if #line > ns.MACRO_MAX_CHARS then problems[#problems + 1] = { line = index, kind = "line" } end
    end
    return problems
end
