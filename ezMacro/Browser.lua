local _, ns = ...
local L = ns.L

-- Makro-Browser im Originalstil von WoW Forever (Mainline-Oberfläche, kein ClassicUI):
--   Platz        rechts angedockt an Blizzards Makroverwaltung (MacroFrame), sonst eigenständig
--   Rahmen       ButtonFrameTemplate mit Reitern unten (PanelTabButtonTemplate), ohne Porträt; Fenster, Maße,
--                Fußzeile, Knopf „Einstellungen“ und Menüs aus ezCores Layout-Grundlage (NewWindow, LAYOUT, Menu)
--   Liste        Zeilen wie Blizzards Klassenlehrer (ClassTrainerSkillButtonTemplate, TrainerTextures)
--   Makrotext    wie Blizzards Makroverwaltung (TooltipBackdropTemplate, ScrollFrameTemplate)
--   Symbol       im UI-EmptySlot-Rahmen wie das gewählte Makro in der Makroverwaltung
--   Reiter       vier nach Zweck (Entwurf A, Frage 14, entschieden 16.11.2026; ns.TABS in Core.lua): Makros, Ein-Klick,
--                Chat, Werkzeuge. Oben die Auswahl des Reiters (ns.TAB_VIEWS: „Für mich“, Klasse, Volk … bzw. Emotes,
--                Dungeon, Raid, PvP), bei Klasse und Volk daneben die Gruppe, im Reiter „Makros“ die Auswahl „Art“
--                (Makro-Arten aus Welle 15, Kinds.lua). Die Knöpfe der Erklär-Seite stehen in einer Zeile unten.
--   Gemerkt      ezMacroDB.window.tab, .views (Auswahl je Reiter), .selected (gewählter Eintrag je Auswahl, Schlüssel
--                wie bisher die Kategorie, dazu „mine“ und „heal“); .category schreibt der Browser weiter mit (die
--                Kategorie der Auswahl), damit eine ältere Fassung den Stand lesen kann. Die alte Reiter-Wahl übernimmt
--                MigrateWindow einmal (Klasse wird „Für mich“, Emotes und Ansagen „Chat“ …).
local Browser = {}
ns.Browser = Browser

-- Angedockt übernimmt der Browser die Höhe der Makroverwaltung; FRAME_H gilt nur als eigenständiges Fenster.
local FRAME_W, FRAME_H = 780, 540
local LIST_W, ROW_H = 298, 47              -- Maße der Klassenlehrer-Zeilen
local NOTES_H, BUTTON_ROW_H = 46, 26       -- Hinweise und je Knopfzeile unter dem Makrotext (zwei Zeilen)
local VIEW_W, GROUP_W, KIND_W, ALL_W = 170, 150, 110, 126  -- obere Leiste: Auswahl, Gruppe, Art, „Alle zeigen“
local SEARCH_W = 160   -- links davon höchstens 12 + 170 + 6 + 298 (Knöpfe der eigenen Vorlagen) + 6 + 110 = 602
local INSET_W = LIST_W + 34                -- Liste plus Scrollleiste
local DETAIL_LEFT = 4 + INSET_W + 16
local INFO_TOP = -60        -- Beginn der Erklär-Seite unter Symbol und Titel
local DETAIL_W = FRAME_W - DETAIL_LEFT - 14
ns.DETAIL_W = DETAIL_W   -- Breite der Werkzeug-Seiten (Tools.lua)
local TRAINER_TEXTURES = "Interface\\ClassTrainerFrame\\TrainerTextures"
local LAYOUT, Menu = ezCore.LAYOUT, ezCore.Menu
local POSITION_KEY = "ezMacro.window"   -- ezCoreDB.positions; die alte Lage aus ezMacroDB.window.pos wird einmal übernommen

local frame
local ui = {}

-- Rundgang beim ersten Öffnen (ezCore.NewTour, Abschlussrunde): die wichtigsten Handgriffe nacheinander, „Verstanden“
-- führt zur nächsten Blase; Schritte, deren Knopf gerade nicht zu sehen ist, kommen später. Gesehene Schritte stehen
-- in ezMacroDB.hints. Die erste Blase („browser“) ist die bisherige Anleitung – wer sie kennt, sieht nur das Neue.
ns.Tour = ezCore.NewTour({
    owner = ns, field = "hints", okay = L.HINT_OK,
    steps = {
        { key = "browser", target = function() return ui.importButton end, text = L.HINT_BROWSER, side = "above" },
        { key = "tourEdit", target = function() return ui.editButton end, text = L.TOUR_EDIT, side = "above" },
        -- Entwurf A (Welle 24): die Auswahl oben („Für mich“ …) – wer den Rundgang kennt, sieht nur diese Blase neu
        { key = "tourView", target = function() return ui.view end, text = L.TOUR_VIEW, side = "below" },
        { key = "tourTabs", target = function() return frame.Tabs[1] end, text = L.TOUR_TABS, side = "below" },
        { key = "tourTools", target = function() return frame.Tabs[ns.TAB_INDEX.tools] end, text = L.TOUR_TOOLS,
          side = "below" },
        { key = "tourSettings", target = function() return frame.ezSettings end, text = L.TOUR_SETTINGS, side = "above" },
    },
})
local rows = {}
local list = {}
local current -- ausgewählter Eintrag
-- tab: Reiter (ns.TABS); view: Auswahl je Reiter; category/group: was die Auswahl zeigt (Kategorie der Einträge bzw.
-- „mine“ für „Für mich“, Gruppe je Kategorie); kind: Auswahl „Art“ im Reiter „Makros“ (nicht gemerkt, wie Blizzards
-- Filter in der Makroverwaltung beim Öffnen wieder „Alle“)
local state = { tab = "macros", view = {}, category = "mine", group = {}, kind = "all", search = "", showAll = false }

-- Farben, Klänge und Scrollbereich aus UI.lua (gemeinsam mit den Werkzeugen).
local UI = ns.UI
local PlaySoundKit, Colored, SetFontColor = UI.PlaySound, UI.Colored, UI.SetFontColor
local AtlasExists, ShowTip, TipScript = ezCore.AtlasExists, ezCore.ShowTip, ezCore.TipScript
local CreateScrollFrame = UI.ScrollFrame

---------------------------------------------------------------------------
-- Daten für die Liste
---------------------------------------------------------------------------

local function GroupsFor(category)
    if category == "class" then return ns.CLASSES end
    if category == "race" then return ns.RACES end
    if category == "announce" then return ns.ANNOUNCE_GROUPS end
    if category == "general" then return ns.GENERAL_GROUPS end
    return nil
end

-- Gehört ein Eintrag zur gewählten Gruppe? In „Allgemein“ tragen die Einträge aus Data\General.lua kein Feld group –
-- sie bilden die Gruppe „general“; „Heilen und Buffen per Klick“ (ClickCast.lua) trägt group = "clickheal".
local function InGroup(entry, category, group)
    if group == nil then return true end
    if category == "general" then return (entry.group or "general") == group end
    return entry.group == group
end

local function DefaultGroup(category)
    local groups = GroupsFor(category)
    if not groups then return nil end
    -- Ansagen: die Gruppe, in der man gerade ist (Schlachtfeld, Raid, sonst Dungeon)
    if category == "announce" then return ns.Announce.DefaultGroup() end
    if category == "general" then return groups[1] end
    local mine = category == "class" and ns.playerClass or ns.playerRace
    for _, token in ipairs(groups) do
        if token == mine then return token end
    end
    return groups[1]
end

local function GroupText(category, token)
    if category == "class" then
        local r, g, b = ns.ClassColor(token)
        local name = ns.ClassName(token)
        if token == ns.playerClass then name = L.GROUP_MINE:format(name) end
        return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
    end
    if category == "announce" then return L["ANN_GROUP_" .. token] end
    if category == "general" then return L["GROUP_" .. token] end
    local name = ns.RaceName(token)
    if token == ns.playerRace then name = L.GROUP_MINE:format(name) end
    return name
end

local function Matches(entry, query)
    if query == "" then return true end
    local haystack = (ns.EntryName(entry) .. "\n" .. ns.EntryWhy(entry) .. "\n" .. ns.Text(entry.desc) .. "\n"
        .. (ns.EntryBody(entry))):lower()
    return haystack:find(query, 1, true) ~= nil
end

-- Werkzeuge im Reiter „Ein-Klick“ findet die Suche über Name und Unterzeile.
local function ToolMatches(entry, query)
    if query == "" then return true end
    return ((entry.name or "") .. "\n" .. (entry.why or "")):lower():find(query, 1, true) ~= nil
end

-- „Für mich“ (Entwurf A): Makros der eigenen Klasse, des eigenen Volkes (ohne die für eine andere Klasse) und die
-- allgemeinen (ohne „Heilen und Buffen per Klick“, das hat eine eigene Auswahl); die eigenen Vorlagen hängt BuildList an.
local function Mine(entry)
    if entry.category == "class" then return entry.group == ns.playerClass end
    if entry.category == "race" then
        return entry.group == ns.playerRace and (entry.class == nil or entry.class == ns.playerClass)
    end
    return entry.category == "general" and (entry.group or "general") == "general"
end

local function InSelection(entry, category, group)
    if category == "mine" then return Mine(entry) end
    return entry.category == category and InGroup(entry, category, group)
end

-- Empfohlen sind Makros mit echtem Vorteil im Kampf (Feld rec). Standardmäßig zeigt die Liste nur sie;
-- „Alle zeigen“ blendet die übrigen dazu, die meist nur einen Platz auf der Leiste sparen. Emotes sind
-- nie gefiltert, die Suche durchsucht immer alles.
local function HasRecommended(category, group)
    for _, entry in ipairs(ns.MACROS) do
        if InSelection(entry, category, group) and entry.rec then return true end
    end
    return false
end

local function Filtered()
    local category = state.category
    if category == "emote" or state.showAll or strtrim(state.search or "") ~= "" then return false end
    return HasRecommended(category, state.group[category])
end

-- Einträge einer Auswahl: mitgelieferte Makros, eigene Vorlagen (Custom.lua), Werkzeuge (Tools.lua), ezHeals
-- Heil-Makros (HealMacros.lua, frisch gelesen) oder die Gruppe „Heilen und Buffen per Klick“ (ClickCast.lua: aus
-- ezHeals Vorlagen bzw. den Maus-über-Makros deiner Klasse).
local function Source(category, group)
    if category == "custom" then return ns.Custom.Entries() end
    if category == "tools" then return ns.Tools.Entries("tools") end
    if category == "heal" then return ns.HealMacros.Entries() end
    if category == "general" and group == "clickheal" then return (ns.ClickCast.Entries()) end
    return ns.MACROS
end

-- Auswahl „Art“ im Reiter „Makros“ (Makro-Arten aus Welle 15): dieselbe Erkennung wie in Blizzards Makroverwaltung
-- (Kinds.Detect am fertigen Text); ezHeals Heil-Makros sind immer „Heilen“.
local function EntryKind(entry)
    if entry.heal then return "heal" end
    local detect = ns.Kinds and ns.Kinds.Detect
    if type(detect) ~= "function" then return nil end
    local ok, kind = pcall(detect, ns.EntryName(entry), (ns.EntryBody(entry)))
    return ok and kind or nil
end

local function KindMatches(entry)
    if state.tab ~= "macros" or state.kind == "all" then return true end
    return EntryKind(entry) == state.kind
end

-- Filter „Nur Makros mit gelernten Zaubern“: wirkt nur im Reiter „Makros“, wo sein Knopf „Art“ steht (Leitlinie 3;
-- Gegenprüfung der Einstellungen vom 19.11.2026 – in „Ein-Klick“ verschwanden sonst Einträge ohne sichtbaren Schalter).
local function UnknownHidden(entry)
    return state.tab == "macros" and ns.S.hideUnknown and not ns.IsEntryKnown(entry)
end

local hiddenUnknown, hiddenOptional, hiddenKind = 0, 0, 0
local function BuildList()
    wipe(list)
    hiddenUnknown, hiddenOptional, hiddenKind = 0, 0, 0
    local category = state.category
    local group = state.group[category]
    if category == "tools" then
        for _, entry in ipairs(Source(category, group)) do list[#list + 1] = entry end
        return
    end
    local query = strtrim(state.search or ""):lower()
    local filtered = Filtered()
    local others, extra, fromSpells = {}, {}, {}
    -- always: eigene Vorlagen in „Für mich“ – nie vom Filter „Empfohlen“ versteckt, sie stehen hinter den Vorlagen;
    -- into: Liste, in die ein solcher Eintrag kommt (sonst extra) – die Gruppe „Aus deinen Fähigkeiten“ (Welle 27)
    local function Take(entry, always, into)
        if entry.tool then
            if ToolMatches(entry, query) then extra[#extra + 1] = entry end
        elseif not Matches(entry, query) then
            return
        elseif UnknownHidden(entry) then
            hiddenUnknown = hiddenUnknown + 1
        elseif not KindMatches(entry) then
            hiddenKind = hiddenKind + 1
        elseif always then
            into = into or extra
            into[#into + 1] = entry
        elseif filtered and not entry.rec then
            hiddenOptional = hiddenOptional + 1
        elseif entry.rec then
            list[#list + 1] = entry
        else
            others[#others + 1] = entry
        end
    end
    for _, entry in ipairs(Source(category, group)) do
        if InSelection(entry, category, group) then Take(entry) end
    end
    if category == "mine" then
        -- Welle 27: Makros aus deinen Fähigkeiten (SpellMacros.lua) – eigene Gruppe hinter den Vorlagen, vor den eigenen
        if ns.SpellMacros.Enabled() then
            for _, entry in ipairs(ns.SpellMacros.Entries()) do Take(entry, true, fromSpells) end
        end
        for _, entry in ipairs(ns.Custom.Entries()) do Take(entry, true) end
    elseif category == "oneclick" then
        -- Entwurf A: Angeln mit einer Taste und die Werkzeuge der Helfer „Eine Taste“ stehen bei den Ein-Klick-Makros
        for _, entry in ipairs(ns.Tools.Entries("oneclick")) do Take(entry) end
    end
    -- Empfohlene zuerst, sonst in der Reihenfolge der Daten; dann die Gruppe „Aus deinen Fähigkeiten“ mit Kopfzeile,
    -- eigene Vorlagen und Werkzeuge am Ende.
    for _, entry in ipairs(others) do list[#list + 1] = entry end
    if #fromSpells > 0 then
        list[#list + 1] = ns.SpellMacros.HEADER
        -- eingeklappt (Seite der Kopfzeile, Spieltest 20.11.2026): nur die Kopfzeile; die Suche zeigt immer alles
        if not ns.SpellMacros.Collapsed() or query ~= "" then
            for _, entry in ipairs(fromSpells) do list[#list + 1] = entry end
        end
    end
    for _, entry in ipairs(extra) do list[#list + 1] = entry end
end

local function ExistingScope(entry)
    local index, perChar = ns.Import.Find(ns.EntryName(entry))
    return index, perChar
end

-- „Ersetzt: Sturmangriff, Abfangen“ – welche Fähigkeiten das Makro auf der Aktionsleiste ersetzt.
local function ReplacesText(entry)
    local names = {}
    for _, id in ipairs(ns.ReplacedSpells(entry)) do names[#names + 1] = ns.SpellName(id) or tostring(id) end
    if #names == 0 then return nil end
    return Colored("NORMAL_FONT_COLOR", L.DETAIL_REPLACES) .. " " .. table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- Detailbereich
---------------------------------------------------------------------------

local function CurrentPerChar()
    return ui.perChar:GetChecked() and true or false
end

-- Freie Plätze statt „belegt/maximal“: Das ist die Zahl, die beim Übernehmen zählt.
local function UpdateCounts()
    local numAccount, maxAccount, numChar, maxChar = ns.Import.Counts()
    ui.count:SetText(L.COUNT:format(math.max(0, maxAccount - numAccount), math.max(0, maxChar - numChar)))
end

-- Worauf das Makro wirkt: Schlagwort in der Liste und Tipp, wie man es benutzt.
local TARGET_TAG = { mouse = "TAG_MOUSE", focus = "TAG_FOCUS" }

local function TargetTip(entry)
    local target = ns.EntryTarget(entry)
    if target == "focus" then
        -- Menüeintrag genau wie im Spiel (Blizzards SET_FOCUS: „Fokus festlegen“ / „Set Focus“).
        return L.TIP_FOCUS:format(type(SET_FOCUS) == "string" and SET_FOCUS or L.TAG_FOCUS)
    elseif target == "mouse" then
        return L.TIP_MOUSE
    end
    return nil
end

-- ezHeals Heil-Makros (HealMacros.lua): Zustand aus ezHeal, „Übernehmen“ legt über ezHeal an; Charakter-Makro immer.
local function UpdateHealStatus()
    local existing = ns.Import.Find(ns.Import.CleanName(current.name))
    ui.perChar:SetChecked(true)
    ui.perChar:Disable()
    SetFontColor(ui.perCharLabel, "GRAY_FONT_COLOR")
    ui.importButton:SetText((existing or current.state ~= "new") and L.BTN_UPDATE or L.BTN_IMPORT)
    ui.importButton:SetEnabled(not ns.InCombat() and ns.HealMacros.Usable(current))
    local stateText = ns.HealMacros.StateText(current)
    if current.state == "same" then
        ui.subtitle:SetText(ns.GroupLabel(current) .. "  ·  "
            .. Colored("GREEN_FONT_COLOR", L.DETAIL_EXISTS:format(ns.Import.ScopeLabel(true))))
    elseif stateText then
        ui.subtitle:SetText(ns.GroupLabel(current) .. "  ·  " .. Colored("ORANGE_FONT_COLOR", stateText))
    else
        ui.subtitle:SetText(ns.GroupLabel(current))
    end
    local notes = {}
    if ns.InCombat() then notes[#notes + 1] = Colored("RED_FONT_COLOR", ns.CombatText()) end
    notes[#notes + 1] = Colored("LIGHTBLUE_FONT_COLOR", L.HEAL_NOTE)
    ui.notes:SetText(table.concat(notes, "\n"))
end

local function UpdateDetailStatus()
    if not current then return end
    if current.tool then return ns.Tools.Refresh(current) end
    if current.heal then return UpdateHealStatus() end
    local name = ui.nameBox:GetText()
    local body = ui.textEdit:GetText()
    local length = #body
    -- Über 255 Zeichen wird es ein langes Makro (Long.lua), bis zur Höchstlänge von ezMacro.
    local maxChars = ns.Import.MaxChars()

    if length > maxChars then
        ui.charCount:SetText(Colored("RED_FONT_COLOR", L.DETAIL_CHARS_OVER:format(length, maxChars)))
    elseif length > ns.MACRO_MAX_CHARS then
        ui.charCount:SetText(Colored("LIGHTBLUE_FONT_COLOR", L.DETAIL_CHARS_LONG:format(length)))
    else
        ui.charCount:SetText(L.DETAIL_CHARS:format(length))
    end

    local existing, existingPerChar = ns.Import.Find(ns.Import.CleanName(name))
    ui.importButton:SetText(existing and L.BTN_UPDATE or L.BTN_IMPORT)
    -- Emote-Makro mit altem Blizzard-Befehl (Emote.lua) – nur, wenn es das Makro ist, das der Knopf „Aktualisieren“
    -- ersetzt (Name im Feld): Unterzeile, Hinweis und Tooltip des Knopfs sagen dann dasselbe
    local outdatedIndex, _, oldCommand = ns.Emote.Outdated(current)
    if not existing or outdatedIndex ~= existing then oldCommand = nil end
    ui.outdated = oldCommand ~= nil
    if existing then
        ui.perChar:SetChecked(existingPerChar)
        ui.perChar:Disable()
        SetFontColor(ui.perCharLabel, "GRAY_FONT_COLOR")
        -- Emote-Makro aus der Zeit vor „/ezmacro emote …“ (altes „Spucken“ mit /spucken): „veraltet“ statt grün.
        -- Umgeschrieben wird nur auf Klick („Aktualisieren“, mit Rückfrage) – der Tooltip des Knopfs nennt den Grund.
        if oldCommand then
            ui.subtitle:SetText(ns.GroupLabel(current) .. "  ·  "
                .. Colored("ORANGE_FONT_COLOR", L.DETAIL_OUTDATED:format(ns.Import.ScopeLabel(existingPerChar))))
        else
            ui.subtitle:SetText(ns.GroupLabel(current) .. "  ·  "
                .. Colored("GREEN_FONT_COLOR", L.DETAIL_EXISTS:format(ns.Import.ScopeLabel(existingPerChar))))
        end
    else
        ui.perChar:Enable()
        SetFontColor(ui.perCharLabel, "HIGHLIGHT_FONT_COLOR")
        ui.subtitle:SetText(ns.GroupLabel(current))
    end

    local ok = not ns.InCombat() and ns.Import.Available() and length > 0 and length <= maxChars
        and strtrim(name) ~= ""
    ui.importButton:SetEnabled(ok)
    -- Klick-Zauber: nur außerhalb des Kampfes und wenn ezCore Blizzards Klick-Zaubern schreiben kann
    ui.clickButton:SetEnabled(ok and ns.ClickCast.Available())
    ui.resetButton:SetEnabled(ns.IsEdited(current))

    -- Hinweise unter dem Textfeld, wichtigste zuerst.
    local notes = {}
    if ns.InCombat() then notes[#notes + 1] = Colored("RED_FONT_COLOR", ns.CombatText()) end
    if current.class and current.class ~= ns.playerClass then
        notes[#notes + 1] = Colored("ORANGE_FONT_COLOR", L.DETAIL_REQUIRES:format(ns.ClassName(current.class)))
    end
    local spell = ns.MainSpell(current)
    if spell and not ns.IsSpellKnown(spell) then
        notes[#notes + 1] = Colored("GRAY_FONT_COLOR", L.DETAIL_UNKNOWN:format(ns.SpellName(spell) or spell))
    end
    local _, missing = ns.Resolve(current.body)
    if #missing > 0 then
        local names = {}
        for _, id in ipairs(missing) do names[#names + 1] = (ns.SpellName(id) or "?") .. " (" .. id .. ")" end
        notes[#notes + 1] = Colored("NORMAL_FONT_COLOR", L.DETAIL_MISSING:format(table.concat(names, ", ")))
    end
    -- Teile, die erst beim Übernehmen entstehen (Eröffnung aus ezCombat, Waffe und Schild): warum eine Zeile fehlt
    if not current.custom then
        for _, text in ipairs(ns.Dynamic.Notes(current.body)) do notes[#notes + 1] = Colored("ORANGE_FONT_COLOR", text) end
    end
    -- Ein-Klick-Helfer, dessen Zauber ein Reagenz oder Werkzeug fehlt: „Dir fehlt …“ samt Quelle (OneKey.ReagentLines,
    -- Bedarf aus ezCores Client-Tabellen; Paket modul/ezbuff-reagenzien)
    if type(current.needs) == "string" and ns.OneKey and ns.OneKey.ReagentLines then
        local lines = ns.OneKey.ReagentLines(current.needs)
        if lines[1] then notes[#notes + 1] = Colored("ORANGE_FONT_COLOR", lines[1]) end
        if lines[2] then notes[#notes + 1] = Colored("GRAY_FONT_COLOR", lines[2]) end
    end
    -- Emote-Makro mit altem Blizzard-Befehl (Emote.lua): Hinweis, kein stilles Umschreiben
    if oldCommand then notes[#notes + 1] = Colored("ORANGE_FONT_COLOR", L.EMOTE_OUTDATED_NOTE:format(oldCommand)) end
    -- Ein-Klick: ein fremdes Makro trägt schon den Namen – ezMacro hält es nicht aktuell (OneClick.lua)
    if ns.OneClick.NameTaken(current) then
        notes[#notes + 1] = Colored("ORANGE_FONT_COLOR", L.ONECLICK_NAME_TAKEN:format(ns.EntryName(current)))
    end
    -- Syntaxhinweise zum Text im Feld „Anpassen“ (Klammern, unbekannte Befehle)
    for _, problem in ipairs(ns.LintMacro(body)) do
        local text
        if problem.kind == "bracket" then
            text = L.DETAIL_LINT_BRACKET:format(problem.line)
        elseif problem.kind == "line" then
            text = L.DETAIL_LINT_LINE:format(problem.line)
        else
            text = L.DETAIL_LINT_COMMAND:format(problem.line, problem.text)
        end
        notes[#notes + 1] = Colored("ORANGE_FONT_COLOR", text)
    end
    if length > ns.MACRO_MAX_CHARS and length <= maxChars then
        notes[#notes + 1] = Colored("LIGHTBLUE_FONT_COLOR", L.DETAIL_LONG)
    end
    if ns.IsEdited(current) then notes[#notes + 1] = Colored("LIGHTBLUE_FONT_COLOR", L.DETAIL_EDITED) end
    ui.notes:SetText(table.concat(notes, "\n"))
end

-- Erklär-Seite: die Abschnitte „Das bringt dir“, „Ohne dieses Makro“, „So funktioniert's“ und der Tipp untereinander.
-- texts[i] ist der Inhalt von ui.sections[i]. Ein leerer Abschnitt wird samt Überschrift übersprungen; der nächste
-- hängt am letzten sichtbaren (Spieltest 14.11.2026: bei „Heiltrank“ und „Sammeln“ lagen „Ohne dieses Makro:“ und
-- „So funktioniert's“ übereinander). Ob ein Abschnitt leer ist, sagt der Text selbst – nicht FontString:GetText(),
-- das im Spiel für leeren Text nil liefert (daran scheiterte der alte Vergleich mit "").
local function LayoutInfo(texts)
    local last
    for index, section in ipairs(ui.sections) do
        local text = texts[index]
        if type(text) ~= "string" then text = "" end
        section.empty = strtrim(text) == ""
        section.text:SetText(section.empty and "" or text)
        if not section.empty then
            local head = section.label or section.text
            head:ClearAllPoints()
            if last then
                head:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, section.gap)
            else
                head:SetPoint("TOPLEFT", ui.detail, "TOPLEFT", 0, INFO_TOP)
            end
            last = section.text
        end
    end
end

-- Zwei Seiten im Detailbereich: „Das bringt dir“ (Standard) und „Anpassen“ (Name und Makrotext).
-- Wer nur übernehmen will, sieht keinen Makrotext.
local function UpdatePages()
    local hasEntry = current ~= nil and not current.tool
    for _, widget in ipairs(ui.infoWidgets) do widget:SetShown(hasEntry and not ui.editing) end
    for _, widget in ipairs(ui.editWidgets) do widget:SetShown(hasEntry and ui.editing) end
    -- Leere Abschnitte der Erklär-Seite bleiben aus (LayoutInfo hat sie übersprungen).
    for _, section in ipairs(ui.sections) do
        if section.empty then
            if section.label then section.label:Hide() end
            section.text:Hide()
        end
    end
    -- Ansagen: „Jetzt ansagen“ über „Übernehmen“ (nur auf der Erklär-Seite)
    ui.sayButton:SetShown(hasEntry and not ui.editing and current.say ~= nil or false)
    -- Reiter „Chat“: „Auf die Leiste“ (nur auf der Erklär-Seite)
    ui.toBarButton:SetShown(hasEntry and not ui.editing and state.tab == "chat" or false)
    -- Eigene Vorlagen: „Löschen“ statt „Zurücksetzen“, kein „Als Vorlage“ (sie sind ja schon eine).
    if hasEntry then
        local custom = current.custom == true
        ui.resetButton:SetShown(ui.editing and not custom)
        ui.templateButton:SetShown(ui.editing and not custom)
        ui.deleteButton:SetShown(custom)
        -- ezHeals Heil-Makros: den Text baut ezHeal – kein Anpassen, kein Klick-Zauber (HealMacros.lua)
        if current.heal then
            ui.editButton:Hide()
            ui.clickButton:Hide()
        end
        Browser.UpdateToBar()
    end
    ui.editButton:SetText(ui.editing and L.BTN_EDIT_DONE or L.BTN_EDIT)
    -- Knopfzeilen unten (Entwurf A): unten links Anpassen, Teilen, Klick-Zauber, rechts „Übernehmen“; darüber links der
    -- Haken „Charakter-Makro“, rechts Löschen, Zurücksetzen, Jetzt ansagen, Auf die Leiste – je nur die sichtbaren.
    local last
    for _, button in ipairs({ ui.editButton, ui.shareButton, ui.clickButton }) do
        if button:IsShown() then
            button:ClearAllPoints()
            if last then
                button:SetPoint("LEFT", last, "RIGHT", 4, 0)
            else
                button:SetPoint("BOTTOMLEFT", ui.detail, "BOTTOMLEFT", 0, -2)
            end
            last = button
        end
    end
    last = nil
    for _, button in ipairs({ ui.deleteButton, ui.resetButton, ui.sayButton, ui.toBarButton }) do
        if button:IsShown() then
            button:ClearAllPoints()
            if last then
                button:SetPoint("RIGHT", last, "LEFT", -4, 0)
            else
                button:SetPoint("BOTTOMRIGHT", ui.detail, "BOTTOMRIGHT", 0, BUTTON_ROW_H - 2)
            end
            last = button
        end
    end
end

local function SetEditing(editing)
    ui.editing = editing and true or false
    if not ui.editing then
        ui.nameBox:ClearFocus()
        ui.textEdit:ClearFocus()
    end
    UpdatePages()
end

local function ShowDetail(entry)
    current = entry
    -- Werkzeuge zeigen ihre eigene Seite anstelle der Makro-Erklärung.
    if entry and entry.tool then
        for _, widget in ipairs(ui.detailWidgets) do widget:Hide() end
        ui.placeholder:Hide()
        UpdatePages()
        ns.Tools.Show(entry, ui.detail)
        return
    end
    ns.Tools.HideAll()
    local hasEntry = entry ~= nil
    for _, widget in ipairs(ui.detailWidgets) do widget:SetShown(hasEntry) end
    ui.placeholder:SetShown(not hasEntry)
    if not entry then
        UpdatePages()
        return
    end
    if entry.heal then ui.editing = false end   -- ezHeals Heil-Makros haben keine Seite „Anpassen“

    ui.icon:SetTexture(ns.EntryIcon(entry))
    ui.icon:SetDesaturated(not ns.IsEntryKnown(entry))
    ui.title:SetText(ns.EntryName(entry))
    ui.replaces:SetText(ReplacesText(entry) or "")
    -- Nutzen, „Ohne dieses Makro“, „So funktioniert's“, Tipp: leere Abschnitte fallen weg, der Rest rückt auf.
    local tip = TargetTip(entry)
    LayoutInfo({
        ns.EntryWhy(entry),
        ns.Text(entry.without),
        ns.Text(entry.desc),
        tip and (Colored("GREEN_FONT_COLOR", L.DETAIL_TIP) .. " " .. tip) or nil,
    })
    ui.nameBox:SetText(ns.EntryName(entry))
    ui.nameBox:SetCursorPosition(0)
    ui.textEdit:SetText((ns.EntryBody(entry)))
    ui.textEdit:SetCursorPosition(0)
    ui.textScroll:SetVerticalScroll(0)

    local existing, existingPerChar = ExistingScope(entry)
    if existing then
        ui.perChar:SetChecked(existingPerChar)
    else
        ui.perChar:SetChecked(ns.Import.DefaultPerChar(entry))
    end
    UpdatePages()
    UpdateDetailStatus()
end

---------------------------------------------------------------------------
-- Liste
---------------------------------------------------------------------------

local function EntryImportArgs(entry)
    local name = ns.EntryName(entry)
    local body = ns.EntryBody(entry)
    local existing, existingPerChar = ExistingScope(entry)
    local perChar
    if existing then
        perChar = existingPerChar
    elseif entry == current then
        perChar = CurrentPerChar()
    else
        perChar = ns.Import.DefaultPerChar(entry)
    end
    return name, body, perChar
end


local function UpdateRows()
    local selectedId = current and current.id
    for index, row in ipairs(rows) do
        local entry = list[index]
        if entry and entry.header then
            -- Kopfzeile einer Gruppe (Welle 27: „Aus deinen Fähigkeiten“) – Klick zeigt ihre Seite (SM.Page)
            row.entry = entry
            row.icon:SetTexture(ns.IconPath(ns.SpellMacros.ICON))
            row.icon:SetDesaturated(false)
            row.disabledBG:Hide()
            row.name:SetText(L.SPELLMACRO_GROUP)
            SetFontColor(row.name, "NORMAL_FONT_COLOR")
            row.tag:SetText("")
            if row.star then row.star:Hide() end
            row.desc:SetText(ns.SpellMacros.Collapsed() and L.SPELLMACRO_GROUP_COLLAPSED:format(#ns.SpellMacros.Entries())
                or L.SPELLMACRO_GROUP_DESC)
            SetFontColor(row.desc, "GRAY_FONT_COLOR")
            row.check:Hide()
            row.selected:SetShown(selectedId == entry.id)
            row:Show()
        elseif entry and entry.tool then
            row.entry = entry
            row.icon:SetTexture(ns.IconPath(entry.icon))
            row.icon:SetDesaturated(false)
            row.disabledBG:Hide()
            row.name:SetText(entry.name)
            SetFontColor(row.name, "NORMAL_FONT_COLOR")
            row.tag:SetText("")
            if row.star then row.star:Hide() end
            row.desc:SetText(entry.why or "")
            SetFontColor(row.desc, "HIGHLIGHT_FONT_COLOR")
            row.check:Hide()
            row.selected:SetShown(entry.id == selectedId)
            row:Show()
        elseif entry then
            local known = ns.IsEntryKnown(entry)
            row.entry = entry
            row.icon:SetTexture(ns.EntryIcon(entry))
            row.icon:SetDesaturated(not known)
            row.disabledBG:SetShown(not known) -- wie beim Klassenlehrer: Nicht-Verfügbares abgedunkelt
            row.name:SetText(ns.ShortName(entry))
            SetFontColor(row.name, known and "NORMAL_FONT_COLOR" or "GRAY_FONT_COLOR")
            local target = ns.EntryTarget(entry)
            -- Schlagwort rechts: worauf das Makro wirkt – oder „veraltet“ für ein Emote-Makro mit altem Befehl
            if ns.Emote.Outdated(entry) then
                row.tag:SetText(Colored("ORANGE_FONT_COLOR", L.TAG_OUTDATED))
            else
                row.tag:SetText(target and L[TARGET_TAG[target]] or "")
            end
            if row.star then row.star:SetShown(entry.rec == true) end
            local desc = ns.EntryWhy(entry)
            if entry.class then desc = ns.ClassName(entry.class) .. ": " .. desc end
            row.desc:SetText(desc)
            SetFontColor(row.desc, known and "HIGHLIGHT_FONT_COLOR" or "GRAY_FONT_COLOR")
            row.check:SetShown(ExistingScope(entry) ~= nil)
            row.selected:SetShown(entry.id == selectedId)
            row:Show()
        else
            row.entry = nil
            row:Hide()
        end
    end
end

-- Beim Überfahren: ersetzte Fähigkeiten nennen und auf den Aktionsleisten hervorheben.
local function AddReplaces(entry)
    local text = ReplacesText(entry)
    if not text then return end
    ezCore.TipLine(GameTooltip, text, "highlight", true)      -- Rollen statt Farbzahlen (Gesamtreview 18.11.2026, T9-6)
    local count = ns.Highlight.Show(ns.ReplacedSpells(entry))
    if count > 0 then
        GameTooltip:AddLine(Colored("GREEN_FONT_COLOR", L.ROW_TIP_ONBARS:format(count)), nil, nil, nil, true)
    else
        GameTooltip:AddLine(Colored("GRAY_FONT_COLOR", L.ROW_TIP_NOTONBARS), nil, nil, nil, true)
    end
end

local function RowOnEnter(self)
    local entry = self.entry
    if not entry then return end
    if entry.header then
        UI.Tip(self, L.SPELLMACRO_GROUP, L.SPELLMACRO_GROUP_TIP)   -- Weg über den Knopf „Art“ (Prüfung vom 19.11.2026)
        return
    end
    if entry.tool then
        UI.Tip(self, entry.name, function()
            local status = ns.Tools.Status(entry)
            return (entry.why or "") .. (status and ("\n" .. status) or "")
        end)
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.EntryName(entry))
    if entry.rec then GameTooltip:AddLine(Colored("GREEN_FONT_COLOR", L.ROW_TIP_RECOMMENDED)) end
    ezCore.TipLine(GameTooltip, ns.EntryWhy(entry), "highlight", true)
    if entry.without then
        GameTooltip:AddLine(Colored("GRAY_FONT_COLOR", L.DETAIL_WITHOUT .. " " .. ns.Text(entry.without)), nil, nil, nil, true)
    end
    local tip = TargetTip(entry)
    if tip then ezCore.TipLine(GameTooltip, Colored("GREEN_FONT_COLOR", L.DETAIL_TIP) .. " " .. tip, "highlight", true) end
    AddReplaces(entry)
    -- Makros aus deinen Fähigkeiten (Welle 27): Art, erzeugter Makrotext und Quelle (Leitlinie 11)
    if entry.generated then
        local lines = ns.SpellMacros.TipLines(entry)
        for index, line in ipairs(lines) do
            local color = index == 1 and "NORMAL_FONT_COLOR" or ((index == 2 or index == #lines) and "GRAY_FONT_COLOR")
            ezCore.TipLine(GameTooltip, color and Colored(color, line) or line, "highlight", true)
        end
    end
    if entry.class then
        GameTooltip:AddLine(Colored("ORANGE_FONT_COLOR", L.DETAIL_REQUIRES:format(ns.ClassName(entry.class))), nil, nil, nil, true)
    end
    local spell = ns.MainSpell(entry)
    if spell and not ns.IsSpellKnown(spell) then
        GameTooltip:AddLine(Colored("GRAY_FONT_COLOR", L.DETAIL_UNKNOWN:format(ns.SpellName(spell) or spell)), nil, nil, nil, true)
    end
    local existing, perChar = ExistingScope(entry)
    if existing then
        local _, _, oldCommand = ns.Emote.Outdated(entry)
        if oldCommand then
            GameTooltip:AddLine(Colored("ORANGE_FONT_COLOR", L.EMOTE_OUTDATED_NOTE:format(oldCommand)), nil, nil, nil, true)
        else
            GameTooltip:AddLine(Colored("GREEN_FONT_COLOR", L.DETAIL_EXISTS:format(ns.Import.ScopeLabel(perChar))))
        end
    end
    -- ezHeals Heil-Makros: Zustand aus ezHeal; ziehen geht nicht (ezHeal legt das Makro an)
    local healState = entry.heal and ns.HealMacros.StateText(entry)
    if healState then GameTooltip:AddLine(Colored("ORANGE_FONT_COLOR", healState), nil, nil, nil, true) end
    GameTooltip:AddLine(" ")
    -- Klick-Hinweise grün wie Blizzards Hinweiszeilen (Core.TipClick), „Klick:“ über Core.ClickText (T18-9, T18-11)
    ezCore.TipClick(GameTooltip, ezCore.ClickText(nil, nil, L.ROW_TIP_CLICK))
    ezCore.TipClick(GameTooltip, L.ROW_TIP_DOUBLE)
    if not entry.heal then ezCore.TipClick(GameTooltip, L.ROW_TIP_DRAG) end
    GameTooltip:Show()
end

local function RowOnLeave()
    ns.Highlight.Clear()
    GameTooltip:Hide()
end

local function RowOnClick(self)
    if not self.entry then return end
    PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
    ns.db.window.selected[state.category] = self.entry.id
    -- Kopfzeile „Aus deinen Fähigkeiten“: ihre Seite rechts (Spieltest 20.11.2026, „Erklärseite + Knöpfe“)
    ShowDetail(self.entry.header and ns.SpellMacros.Page() or self.entry)
    UpdateRows()
end

local function RowOnDoubleClick(self)
    local entry = self.entry
    if not entry or entry.tool or entry.header then return end
    if current ~= entry then RowOnClick(self) end
    if entry.heal then return ns.HealMacros.Apply(entry) end
    local name, body, perChar = EntryImportArgs(entry)
    ns.Import.Apply(entry, name, body, perChar, ns.S.pickupAfterImport)
end

local function RowOnDragStart(self)
    local entry = self.entry
    if not entry or entry.tool or entry.heal or entry.header then return end
    local name, body, perChar = EntryImportArgs(entry)
    ns.Import.Drag(entry, name, body, perChar)
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, ui.content)
    row:SetSize(LIST_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    row:RegisterForDrag("LeftButton")

    -- Aufbau und Grafiken wie Blizzards ClassTrainerSkillButtonTemplate (Mainline).
    local normal = row:CreateTexture(nil, "BACKGROUND", nil, 0)
    normal:SetTexture(TRAINER_TEXTURES)
    normal:SetTexCoord(0.00195313, 0.57421875, 0.65820313, 0.75000000)
    normal:SetAllPoints()

    row.disabledBG = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.disabledBG:SetColorTexture(0.55, 0.55, 0.55, 1)
    row.disabledBG:SetBlendMode("MOD")
    row.disabledBG:SetPoint("TOPLEFT", 2, -2)
    row.disabledBG:SetPoint("BOTTOMRIGHT", -2, 2)
    row.disabledBG:Hide()

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(TRAINER_TEXTURES)
    highlight:SetTexCoord(0.00195313, 0.57421875, 0.75390625, 0.84570313)
    highlight:SetBlendMode("ADD")
    highlight:SetAllPoints()

    -- 36 wie die Makro-Knöpfe in Blizzards Makroverwaltung (Blizzard_MacroUI.xml, MacroButtonTemplate über
    -- SelectorButtonTemplate) – folgt einem Blizzard-Teil, bleibt bewusst außerhalb Core.Style.ICON (Design-System 2.3)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(36, 36)
    row.icon:SetPoint("LEFT", 6, 0)

    row.selected = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.selected:SetTexture(TRAINER_TEXTURES)
    row.selected:SetTexCoord(0.00195313, 0.57421875, 0.84960938, 0.94140625)
    row.selected:SetBlendMode("ADD")
    row.selected:SetAllPoints()
    row.selected:Hide()

    row.check = row:CreateTexture(nil, "OVERLAY", nil, 1)
    row.check:SetSize(16, 16)
    row.check:SetPoint("TOPRIGHT", -6, -6)
    row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    row.check:Hide()

    -- Stern für Empfohlene wie die Favoriten in Blizzards Sammlungen (Ecke des Symbols).
    if AtlasExists("PetJournal-FavoritesIcon") then
        row.star = row:CreateTexture(nil, "OVERLAY", nil, 2)
        row.star:SetAtlas("PetJournal-FavoritesIcon")
        local starSize = ezCore.Style.IconSize("line")   -- Symbol in der Zeile (Design-System 2.3; bisher 18)
        row.star:SetSize(starSize, starSize)
        row.star:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -6, 6)
        row.star:Hide()
    end

    -- Schlagwort statt Kürzel: „Maus“ für (MO), „Fokus“ für (F).
    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.tag:SetPoint("TOPRIGHT", row, "TOPRIGHT", -26, -8)
    row.tag:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetHeight(12)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.desc = row:CreateFontString(nil, "OVERLAY", SystemFont_Shadow_Small and "SystemFont_Shadow_Small" or "GameFontHighlightSmall")
    row.desc:SetSize(LIST_W - 58, 30)
    row.desc:SetPoint("LEFT", row.name, "LEFT", 0, -19)
    row.desc:SetJustifyH("LEFT")
    row.desc:SetJustifyV("MIDDLE")
    row.desc:SetMaxLines(2)

    row:SetScript("OnClick", RowOnClick)
    row:SetScript("OnDoubleClick", RowOnDoubleClick)
    row:SetScript("OnDragStart", RowOnDragStart)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    rows[index] = row
    return row
end

-- Sichtbarer Knopf „Alle zeigen (+n)“ / „Nur empfohlene“ neben der Klassen- bzw. Volksauswahl.
local function UpdateAllButton()
    local button = ui.allButton
    if not button then return end
    local category = state.category
    local relevant = category ~= "emote" and strtrim(state.search or "") == ""
        and HasRecommended(category, state.group[category])
    button:SetShown(relevant and (state.showAll or hiddenOptional > 0))
    button:SetText(state.showAll and L.BTN_SHOW_RECOMMENDED or L.BTN_SHOW_ALL:format(hiddenOptional))
end

local function UpdateList(keepScroll)
    BuildList()
    UpdateAllButton()
    for index = #rows + 1, #list do CreateRow(index) end
    ui.content:SetHeight(math.max(1, #list * ROW_H))
    if not keepScroll then ui.listScroll:SetVerticalScroll(0) end

    if #list == 0 then
        local query = strtrim(state.search or "")
        if state.category == "custom" and query == "" and hiddenKind == 0 then
            ui.empty:SetText(L.LIST_EMPTY_CUSTOM)
        elseif state.category == "heal" and query == "" then
            ui.empty:SetText(L.LIST_EMPTY_HEAL)
        elseif query ~= "" then
            ui.empty:SetText(L.LIST_EMPTY_SEARCH:format(query))
        elseif hiddenKind > 0 then
            ui.empty:SetText(L.LIST_EMPTY_KIND:format(ns.Kinds.Label(state.kind)))
        elseif hiddenUnknown > 0 then
            ui.empty:SetText(L.LIST_EMPTY_UNKNOWN)
        else
            ui.empty:SetText(L.LIST_EMPTY)
        end
        ui.empty:Show()
    else
        ui.empty:Hide()
    end

    -- Auswahl behalten, sonst die gespeicherte oder die erste nehmen.
    local wanted = ns.db.window.selected[state.category]
    local pick
    for _, entry in ipairs(list) do
        if current and entry == current then pick = entry break end
    end
    if not pick then
        for _, entry in ipairs(list) do
            if entry.id == wanted then
                -- die Kopfzeile steht für ihre Seite (SM.Page trägt dieselbe id wie SM.HEADER)
                pick = entry.header and ns.SpellMacros.Page() or entry
                break
            end
        end
    end
    if not pick then
        -- der erste wählbare Eintrag (eine Kopfzeile ist keiner)
        for _, entry in ipairs(list) do
            if not entry.header then pick = entry break end
        end
    end
    if pick ~= current or not keepScroll then ShowDetail(pick) else UpdateDetailStatus() end
    UpdateRows()
end

---------------------------------------------------------------------------
-- Gruppenauswahl (Klasse/Volk) und Reiter
---------------------------------------------------------------------------

-- Infozeile über der Liste (Klick öffnet die Einstellungen): bei den Emotes der Stand der automatischen Emotes,
-- bei den Ansagen der Kanal, der gerade gilt, bei Ein-Klick, ob ezMacro die Makros aktuell hält.
local INFO_TIPS = { announce = "ANN_INFO_TIP", oneclick = "ONECLICK_INFO_TIP", emote = "AUTO_INFO_TIP" }
local function UpdateAutoInfo()
    if not ui.autoInfo then return end
    if state.category == "announce" then
        ui.autoInfo.text:SetText(ns.Announce.InfoText())
    elseif state.category == "oneclick" then
        local on, off = Colored("GREEN_FONT_COLOR", L.ON), Colored("GRAY_FONT_COLOR", L.OFF)
        ui.autoInfo.text:SetText(L.ONECLICK_INFO:format(ns.S.oneClickUpdate and on or off))
    else
        local on, off = Colored("GREEN_FONT_COLOR", L.ON), Colored("GRAY_FONT_COLOR", L.OFF)
        -- Danken an, aber der Client sperrt die Erkennung (Heilvorhersage, AutoEmote.lua): ehrlich „gesperrt“ statt „an“
        local thank = ns.Auto.ThankBlocked() and Colored("ORANGE_FONT_COLOR", L.WORD_LOCKED) or (ns.S.autoThank and on or off)
        ui.autoInfo.text:SetText(L.AUTO_INFO:format(thank, ns.S.autoSpit and on or off))
    end
    ui.autoInfo:SetWidth(ui.autoInfo.text:GetStringWidth() + 4)
    -- Emotes ohne ezBars: „Emote-Leisten brauchen ezBars“ neben dem Stand der Automatik (Klick: ns.EmoteBar.ShowNeed)
    if ui.barsNeed then
        local need = state.category == "emote" and not ns.EmoteBar.Available()
        if need then
            ui.barsNeed.text:SetText(Colored("ORANGE_FONT_COLOR", L.OPT_BAR_NEED))
            ui.barsNeed:SetWidth(ui.barsNeed.text:GetStringWidth() + 4)
        end
        ui.barsNeed:SetShown(need)
    end
end

local function GroupMenu(_, root)
    local category = state.category
    for _, token in ipairs(GroupsFor(category) or {}) do
        Menu.Radio(root, GroupText(category, token),
            function() return state.group[category] end,
            function()
                state.group[category] = token
                current = nil
                UpdateList()
                if ui.groupModern then
                    -- Text erst nach dem Schließen des Menüs auffrischen.
                    C_Timer.After(0, function() ui.group:RefreshText() end)
                else
                    ui.group:SetText(GroupText(category, token))
                end
            end, token)
    end
end

-- Auswahlfeld über ezCore (Core.Menu.Dropdown: Blizzards WowStyle1DropdownTemplate, ohne die Vorlage ein Knopf mit
-- Kontextmenü; Gesamtreview T18-12 – vorher eine eigene Kopie hier). label() liefert den Text des Rückfall-Knopfs.
-- → Rahmen, modern (true: Blizzards Auswahlfeld)
local function CreateSelector(width, generator, label)
    local box = Menu.Dropdown(frame, width, function(root) generator(nil, root) end, label)
    return box, box.modern == true
end

-- Gruppe (Klasse bzw. Volk) neben der Auswahl.
local function CreateGroupSelector()
    local selector, modern = CreateSelector(GROUP_W, GroupMenu, function()
        local category = state.category
        return GroupText(category, state.group[category])
    end)
    ui.groupModern = modern
    return selector
end

-- Text eines Auswahlfelds auffrischen; im offenen Menü erst nach dem Schließen (later).
local function RefreshSelector(selector, modern, text, later)
    if not modern then
        selector:SetText(text)
    elseif later then
        C_Timer.After(0, function() selector:RefreshText() end)
    else
        selector:RefreshText()
    end
end

-- Auswahl eines Reiters » Kategorie und Gruppe der Einträge
local function ViewCategory(tab, view)
    if tab == "oneclick" or tab == "tools" then return tab, nil end
    if tab == "chat" then
        if view == "dungeon" or view == "raid" or view == "pvp" then return "announce", view end
        return "emote", nil
    end
    if view == "general" or view == "clickheal" then return "general", view end
    return view or "mine", nil   -- mine, class, race, custom, heal
end

local function ViewAvailable(view)
    if view == "heal" then return ns.HealMacros.Available() end
    return true
end

-- Gemerkte Auswahl des Reiters; unbekannt oder nicht verfügbar (ezHeal aus): die Vorauswahl.
local DEFAULT_VIEW = { macros = "mine", chat = "emote" }
local function CurrentView(tab)
    local views = ns.TAB_VIEWS[tab]
    if not views then return nil end
    local view, known = state.view[tab], false
    for _, candidate in ipairs(views) do
        if candidate == view then known = true end
    end
    if not known or not ViewAvailable(view) then view = DEFAULT_VIEW[tab] end
    state.view[tab] = view
    return view
end

local function ViewText(view)
    if view == "mine" then return L.VIEW_mine end
    if view == "custom" then return L.VIEW_custom end
    if view == "heal" then return L.VIEW_heal end
    if view == "clickheal" then return L.GROUP_clickheal end
    if view == "dungeon" or view == "raid" or view == "pvp" then return L["ANN_GROUP_" .. view] end
    return L["TAB_" .. view]
end

-- Tooltip je Eintrag der Auswahl: Titel, Text (die Texte der früheren Reiter, wo es sie gibt)
local function ViewTip(view)
    if view == "clickheal" then return L.GENERAL_GROUP_TIP_TITLE, L.GENERAL_GROUP_TIP end
    if view == "dungeon" or view == "raid" or view == "pvp" then
        return L.ANN_GROUP_TIP_TITLE, L.TAB_TIP_announce .. " " .. L.ANN_GROUP_TIP
    end
    if view == "mine" or view == "heal" then return ViewText(view), L["VIEW_TIP_" .. view] end
    return ViewText(view), L["TAB_TIP_" .. view]
end

local SelectTab   -- unten; die Auswahl ruft sie auf

local function ViewMenu(_, root)
    local tab = state.tab
    for _, view in ipairs(ns.TAB_VIEWS[tab] or {}) do
        if ViewAvailable(view) then
            local radio = Menu.Radio(root, ViewText(view), function() return state.view[tab] end, function()
                state.view[tab] = view
                SelectTab(tab, true)
            end, view)
            Menu.Tip(radio, ViewTip(view))
        end
    end
end

local function CreateViewSelector()
    local selector, modern = CreateSelector(VIEW_W, ViewMenu, function() return ViewText(state.view[state.tab]) end)
    ui.viewModern = modern
    return selector
end

-- Auswahl „Art“ (Reiter „Makros“): Menü wie Blizzards Knopf „Art“ in der Makroverwaltung (Kinds.lua)
local function UpdateKindButton()
    ui.kindButton:SetText(L.KIND_BUTTON:format(ns.Kinds.Label(state.kind)))
end

local function KindMenu(owner)
    Menu.Open(owner, function(root)
        Menu.Title(root, L.KIND_MENU_SHOW)
        local function Get() return state.kind end
        local function Set(value)
            state.kind = value
            UpdateKindButton()
            current = nil
            UpdateList()
            return Menu.Close()
        end
        Menu.Radio(root, ns.Kinds.Label("all"), Get, Set, "all")
        for _, kind in ipairs(ns.Kinds.LIST) do
            Menu.Tip(Menu.Radio(root, ns.Kinds.Label(kind), Get, Set, kind), ns.Kinds.Label(kind), L["KIND_TIP_" .. kind])
        end
        -- Filter der Liste (Prüfung der Einstellungen vom 19.11.2026: früher Dauerschalter auf der Einstellungsseite);
        -- gemerkt wie bisher in ezMacros Einstellungen, damit die Wahl das nächste Öffnen überdauert
        Browser.AddFilterEntries(root)
    end)
end

-- Schlüssel der Filter im Menü „Art“, in dieser Reihenfolge.
Browser.FILTERS = { "hideUnknown", "macroFromSpells" }
function Browser.AddFilterEntries(root)
    Menu.Divider(root)
    Menu.Title(root, L.KIND_MENU_FILTER)
    for _, key in ipairs(Browser.FILTERS) do
        local entry = Menu.Toggle(root, L["OPT_" .. key], function() return ns.S[key] and true or false end, function(value)
            ns.SetSetting(key, value and true or false)
            return Menu.Refresh()
        end)
        Menu.Tip(entry, L["OPT_" .. key], L["OPT_" .. key .. "_TIP"])
    end
end

-- Obere Leiste von links: Auswahl, Gruppe, Knöpfe der eigenen Vorlagen, Art, „Alle zeigen“; die Infozeile (Emotes,
-- Ansagen, Ein-Klick) neben der Auswahl bzw. oben links; rechts die Suche.
local function LayoutHeader()
    local last
    for _, widget in ipairs({ ui.view, ui.group, ui.customBar, ui.kindButton }) do
        if widget:IsShown() then
            widget:ClearAllPoints()
            if last then
                widget:SetPoint("LEFT", last, "RIGHT", 6, 0)
            else
                widget:SetPoint("TOPLEFT", frame, "TOPLEFT", ui.headerX, LAYOUT.HEADER_Y)
            end
            last = widget
        end
    end
    ui.allButton:ClearAllPoints()
    if last then
        ui.allButton:SetPoint("LEFT", last, "RIGHT", 6, 0)
    else
        ui.allButton:SetPoint("TOPLEFT", frame, "TOPLEFT", ui.headerX, LAYOUT.HEADER_Y)
    end
    ui.autoInfo:ClearAllPoints()
    if ui.view:IsShown() then
        ui.autoInfo:SetPoint("LEFT", ui.view, "RIGHT", 10, 0)
    else
        ui.autoInfo:SetPoint("TOPLEFT", frame, "TOPLEFT", ui.headerX + 4, LAYOUT.SEARCH_Y_PLAIN)
    end
end

-- Untere Leiste von rechts: Einstellungen, „Makros“ (nur eigenständig), „Zum Ziel …“ (Ansagen), „Leiste einstellen“
-- (Reiter „Chat“).
local function LayoutFooter()
    local anchor = ui.docked and ui.settingsButton or ui.macrosButton
    for _, button in ipairs({ ui.targetButton, ui.barButton }) do
        if button:IsShown() then
            button:ClearAllPoints()
            button:SetPoint("RIGHT", anchor, "LEFT", -LAYOUT.GAP, 0)
            anchor = button
        end
    end
end

-- Reiter wählen und seine Auswahl anwenden. fromMenu: aus dem offenen Menü der Auswahl (Text erst danach auffrischen).
SelectTab = function(tab, fromMenu)
    if not ns.TAB_INDEX[tab] then tab = "macros" end
    state.tab = tab
    ns.db.window.tab = tab
    ui.editing = false
    if PanelTemplates_SetTab then PanelTemplates_SetTab(frame, ns.TAB_INDEX[tab]) end

    local view = CurrentView(tab)
    local category, group = ViewCategory(tab, view)
    state.category = category
    if group then state.group[category] = group end
    -- Stand für ältere Fassungen (ein Reiter je Kategorie): die Kategorie der Auswahl
    if ns.CATEGORY_TAB[category] and category ~= "heal" then ns.db.window.category = category end
    local groups = (category == "class" or category == "race") and GroupsFor(category) or nil
    if groups then state.group[category] = state.group[category] or DefaultGroup(category) end

    ui.view:SetShown(view ~= nil)
    if view then RefreshSelector(ui.view, ui.viewModern, ViewText(view), fromMenu) end
    ui.group:SetShown(groups ~= nil)
    if groups then RefreshSelector(ui.group, ui.groupModern, GroupText(category, state.group[category]), fromMenu) end
    -- Eigene: Knöpfe „Neu“, „Aus Text“, „Aus Makro“; Art nur im Reiter „Makros“; Werkzeuge brauchen keine Suche.
    ui.customBar:SetShown(category == "custom")
    ui.kindButton:SetShown(tab == "macros")
    UpdateKindButton()
    ui.autoInfo:SetShown(category == "emote" or category == "announce" or category == "oneclick")
    LayoutHeader()
    ui.targetButton:SetShown(category == "announce")
    ui.barButton:SetShown(tab == "chat")
    LayoutFooter()
    UpdateAutoInfo()
    ui.search:SetShown(tab ~= "tools")
    ns.Highlight.Clear()

    current = nil
    UpdateList()
end

-- Kategorie (oder Reiter) » Reiter und Auswahl. Ansagen ohne Gruppe: die Lage, in der du gerade bist.
local function PlaceOfCategory(category)
    if ns.TAB_INDEX[category] then return category, nil end
    if category == "mine" or category == "clickheal" then return "macros", category end
    local tab = ns.CATEGORY_TAB[category]
    if not tab then return nil end
    if category == "announce" then return tab, ns.Announce.DefaultGroup() end
    if tab == "macros" or category == "emote" then return tab, category end
    return tab, nil
end

-- Bis Welle 23 ein Reiter je Kategorie; jetzt Reiter und Auswahl, die diese Kategorie zeigen.
local function SelectCategory(category)
    local tab, view = PlaceOfCategory(category)
    if not tab then return end
    if view then state.view[tab] = view end
    SelectTab(tab)
end

---------------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------------

-- Fensterposition über ezCore.NewWindow (ezCoreDB.positions[POSITION_KEY]).
local function SavePosition() frame:SavePosition() end

local function RestorePosition() frame:RestorePosition() end

-- Leichte Aktualisierung ohne Auswahl zu verlieren (Makros oder Zauberbuch geändert).
local function SoftRefresh()
    if not (frame and frame:IsShown()) then return end
    UpdateCounts()
    UpdateList(true)
end

-- Ein Makroname hat sich geändert (ns.NamesChanged, Nachricht NAMES_CHANGED): Die Einträge aus deinen Fähigkeiten heißen
-- dann womöglich anders („… 2 (MO)“), die Liste wird neu gebaut. Während du im Namensfeld tippst, erst wenn es den Fokus
-- verliert (Enter, Esc, Klick daneben) – nicht bei jedem Tastendruck, und die Schreibmarke bleibt, wo sie ist (Fund 5 des
-- Reviews vor dem Merge von modul/ezmacro-reste).
local namesPending = false

local function OnNamesChanged()
    if not (frame and frame:IsShown()) then return end
    if ui.nameBox and ui.nameBox:HasFocus() then
        namesPending = true
        return
    end
    namesPending = false
    SoftRefresh()
end

local function OnNameFocusLost()
    if not namesPending then return end
    namesPending = false
    SoftRefresh()
end

local function OnEdited(_, userInput)
    if not userInput or not current then return end
    ns.SaveEdit(current, ui.nameBox:GetText(), ui.textEdit:GetText())
    ui.title:SetText(ns.EntryName(current))
    UpdateDetailStatus()
    UpdateRows()
end

local function ImportCurrent()
    if not current then return end
    if current.heal then return ns.HealMacros.Apply(current) end   -- ezHeal legt an (nach Rückfrage)
    ns.Import.Apply(current, ui.nameBox:GetText(), ui.textEdit:GetText(), CurrentPerChar(), ns.S.pickupAfterImport)
end

local function DragCurrent()
    if not current or current.heal then return end
    local perChar = CurrentPerChar()
    ns.Import.Drag(current, ui.nameBox:GetText(), ui.textEdit:GetText(), perChar)
end

local function ShareCurrent()
    if not current or current.tool then return end
    ns.Share(ui.nameBox:GetText(), ui.textEdit:GetText())
end

-- Fügt Text an der Schreibmarke ein (Bedingungs-Baukasten) und speichert wie beim Tippen.
local function InsertText(text)
    ui.textEdit:Insert(text)
    OnEdited(nil, true)
end

-- Speichert den Text im Feld als eigene Vorlage (Reiter „Makros“, Auswahl „Nur Eigene“).
local function SaveAsTemplate()
    if not current or current.custom then return end
    local icon = current.icon and ns.MacroIcon(current) or nil
    local entry = ns.Custom.Add(ns.Custom.FreeName(ui.nameBox:GetText()), ui.textEdit:GetText(), icon)
    ns.Print(L.CUSTOM_SAVED:format(entry.name))
end

local function DeleteCurrent()
    local entry = current
    if not (entry and entry.custom) then return end
    ezCore.Confirm(L.CUSTOM_DELETE_CONFIRM:format(entry.name), function()
        ns.Custom.Remove(entry)
    end)
end

-- Menü „Aus Makro“: vorhandene Makros aus Blizzards Makroverwaltung als eigene Vorlage kopieren.
local function FromMacroMenu(_, root)
    if root.SetScrollMode then root:SetScrollMode(400) end   -- bis zu 138 Makros: Menü scrollt
    local any = false
    for _, perChar in ipairs({ false, true }) do
        local macros = ns.Macros.All(perChar and "char" or "account")
        if #macros > 0 then
            Menu.Title(root, ns.Import.ScopeLabel(perChar))
            for _, macro in ipairs(macros) do
                any = true
                Menu.Button(root, macro.name, function()
                    local entry = ns.Custom.FromMacro(macro.index)
                    if entry then Browser.ShowEntry(entry, true) end
                end)
            end
        end
    end
    if not any then Menu.Title(root, L.CUSTOM_NO_MACROS) end
end

-- Knopf „Makros“ im eigenständigen Fenster: Blizzards Makroverwaltung über ezCore (nur außerhalb des Kampfes,
-- im Kampf zeigt ezCore den Hinweis).
local function OpenMacroFrame()
    return ezCore.OpenPanel("macro")
end

local function CreateDetail()
    -- Rechts auf dem normalen Fensterhintergrund, wie der Bearbeitungsbereich der Makroverwaltung.
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPLEFT", frame, "TOPLEFT", DETAIL_LEFT, -64)
    pane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 32)
    ui.detail = pane
    ui.detailWidgets, ui.infoWidgets, ui.editWidgets = {}, {}, {}
    local function Track(widget) table.insert(ui.detailWidgets, widget) return widget end
    local function TrackInfo(widget) table.insert(ui.infoWidgets, widget) return widget end
    local function TrackEdit(widget) table.insert(ui.editWidgets, widget) return widget end

    ui.placeholder = pane:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.placeholder:SetPoint("CENTER")
    ui.placeholder:SetText(L.DETAIL_NONE)

    -- Symbol im UI-EmptySlot-Rahmen wie das gewählte Makro in Blizzards Makroverwaltung (ziehbar).
    -- Maße wie Blizzards gewähltes Makro (Blizzard_MacroUI.xml: MacroFrameSelectedMacroBackground UI-EmptySlot 64 × 64,
    -- darin MacroFrameSelectedMacroButton 36 × 36 bei 14/−14) – folgen einem Blizzard-Teil (Design-System 2.3)
    local iconButton = Track(CreateFrame("Button", nil, pane))
    iconButton:SetSize(36, 36)
    iconButton:SetPoint("TOPLEFT", 14, -10)
    iconButton:RegisterForDrag("LeftButton")
    local slot = iconButton:CreateTexture(nil, "BACKGROUND")
    slot:SetTexture("Interface\\Buttons\\UI-EmptySlot")
    slot:SetSize(64, 64)
    slot:SetPoint("TOPLEFT", -14, 14)
    ui.icon = iconButton:CreateTexture(nil, "ARTWORK")
    ui.icon:SetAllPoints()
    local iconHighlight = iconButton:CreateTexture(nil, "HIGHLIGHT")
    iconHighlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    iconHighlight:SetBlendMode("ADD")
    iconHighlight:SetAllPoints()
    iconButton:SetScript("OnDragStart", DragCurrent)
    iconButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        ezCore.TipTitle(GameTooltip, L.DETAIL_ICON_TIP)
        if current then AddReplaces(current) end
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", RowOnLeave)

    -- Sichtbarer Knopf zum Anpassen; ohne ihn bleibt der Makrotext verborgen. Entwurf A: Anpassen, Teilen und
    -- Klick-Zauber stehen unten links in einer Zeile mit „Übernehmen“ (UpdatePages ordnet die sichtbaren).
    ui.editButton = Track(CreateFrame("Button", nil, pane, "UIPanelButtonTemplate"))
    ui.editButton:SetSize(96, 22)
    ui.editButton:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 0, -2)
    ui.editButton:SetText(L.BTN_EDIT)
    ui.editButton:SetScript("OnClick", function()
        PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
        SetEditing(not ui.editing)
    end)
    ui.editButton:SetScript("OnEnter", function(self)
        ShowTip(self, ui.editing and L.BTN_EDIT_DONE or L.BTN_EDIT, ui.editing and L.BTN_EDIT_DONE_TIP or L.BTN_EDIT_TIP)
    end)
    ui.editButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- „Klick-Zauber“: Makro auf eine Maustaste in Blizzards Klick-Zaubern legen (ClickCast.lua, über ezCore,
    -- nur außerhalb des Kampfes, mit Rückfrage). Unten in der Knopfzeile hinter „Teilen“.
    ui.clickButton = Track(UI.Button(pane, L.BTN_CLICKBIND, 96, function(self)
        if not current or current.tool or current.heal then return end
        ns.ClickCast.Menu(self, current, ui.nameBox:GetText(), ui.textEdit:GetText(), CurrentPerChar())
    end))
    ui.clickButton:SetScript("OnEnter", function(self)
        local tip = L.BTN_CLICKBIND_TIP .. "\n\n" .. ns.ClickCast.Guide()
        if current and type(current.click) == "table" then
            tip = tip .. "\n" .. L.CLICK_TIP_SUGGESTED:format(ns.ClickCast.KeyText(current.click[1], current.click[2]))
        end
        if not ns.ClickCast.Available() then tip = tip .. "\n" .. Colored("RED_FONT_COLOR", L.CLICK_ERR_missing) end
        local other = ns.ClickCast.Other()
        if other then tip = tip .. "\n" .. Colored("ORANGE_FONT_COLOR", L.CLICK_OTHER_ADDON:format(other, other)) end
        ShowTip(self, L.BTN_CLICKBIND_TITLE, tip)
    end)
    ui.clickButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- „Teilen“: Makro als Text zum Kopieren (Gilde, Discord); einfügen über „Aus Text“ (Reiter „Makros“, „Nur Eigene“).
    ui.shareButton = Track(UI.Button(pane, L.BTN_SHARE, 80, ShareCurrent, L.BTN_SHARE, L.BTN_SHARE_TIP))
    ui.shareButton:SetPoint("LEFT", ui.editButton, "RIGHT", 4, 0)
    ui.clickButton:SetPoint("LEFT", ui.shareButton, "RIGHT", 4, 0)

    ui.title = Track(pane:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"))
    ui.title:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 18, -2)
    ui.title:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    ui.title:SetJustifyH("LEFT")
    ui.title:SetWordWrap(false)

    ui.subtitle = Track(pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    ui.subtitle:SetPoint("TOPLEFT", ui.title, "BOTTOMLEFT", 0, -4)
    ui.subtitle:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    ui.subtitle:SetJustifyH("LEFT")
    ui.subtitle:SetWordWrap(false)

    -- „Ersetzt: …“ unter der Unterzeile, noch neben dem Symbol.
    ui.replaces = Track(pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    ui.replaces:SetPoint("TOPLEFT", ui.subtitle, "BOTTOMLEFT", 0, -3)
    ui.replaces:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    ui.replaces:SetJustifyH("LEFT")
    ui.replaces:SetWordWrap(false)

    -- Seite „Das bringt dir“: Nutzen, was man ohne das Makro tun müsste, wie es funktioniert, Tipp.
    local function Text(font, anchor, y, lines)
        local text = TrackInfo(pane:CreateFontString(nil, "ARTWORK", font))
        text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y)
        text:SetWidth(DETAIL_W)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("TOP")
        text:SetSpacing(2)
        if lines then text:SetMaxLines(lines) end
        return text
    end
    ui.whyLabel = TrackInfo(pane:CreateFontString(nil, "ARTWORK", "GameFontNormal"))
    ui.whyLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, INFO_TOP)
    ui.whyLabel:SetText(L.DETAIL_WHY)
    ui.why = Text("GameFontHighlight", ui.whyLabel, -4, 3)
    ui.withoutLabel = TrackInfo(pane:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"))
    ui.withoutLabel:SetPoint("TOPLEFT", ui.why, "BOTTOMLEFT", 0, -8)
    ui.withoutLabel:SetText(L.DETAIL_WITHOUT)
    ui.without = Text("GameFontHighlightSmall", ui.withoutLabel, -3, 2)
    SetFontColor(ui.without, "GRAY_FONT_COLOR")
    ui.howLabel = TrackInfo(pane:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"))
    ui.howLabel:SetPoint("TOPLEFT", ui.without, "BOTTOMLEFT", 0, -8)
    ui.howLabel:SetText(L.DETAIL_HOW)
    ui.desc = Text("GameFontHighlightSmall", ui.howLabel, -3, 3)
    ui.tip = Text("GameFontHighlightSmall", ui.desc, -6, 2)
    -- Abschnitte in ihrer Reihenfolge: label = Überschrift (der Inhalt hängt fest darunter), gap = Abstand zum
    -- Abschnitt davor. LayoutInfo setzt die Texte und hängt jeden Abschnitt an den letzten sichtbaren.
    ui.sections = {
        { label = ui.whyLabel, text = ui.why },
        { label = ui.withoutLabel, text = ui.without, gap = -8 },
        { label = ui.howLabel, text = ui.desc, gap = -8 },
        { text = ui.tip, gap = -6 },
    }

    -- Seite „Anpassen“: Name und Makrotext
    local nameLabel = TrackEdit(pane:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"))
    nameLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -60)
    nameLabel:SetText(L.DETAIL_NAME)

    ui.nameBox = TrackEdit(CreateFrame("EditBox", nil, pane, "InputBoxTemplate"))
    ui.nameBox:SetSize(180, 20)
    ui.nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -4)
    ui.nameBox:SetAutoFocus(false)
    ui.nameBox:SetMaxLetters(ns.MACRO_NAME_MAX)
    ui.nameBox:SetScript("OnEnterPressed", EditBox_ClearFocus or function(self) self:ClearFocus() end)
    ui.nameBox:SetScript("OnEscapePressed", EditBox_ClearFocus or function(self) self:ClearFocus() end)
    ui.nameBox:HookScript("OnTextChanged", OnEdited)
    ui.nameBox:HookScript("OnEditFocusLost", OnNameFocusLost)

    -- Bedingungs-Baukasten und „Als Vorlage“ rechts neben dem Namen.
    ui.builderButton = TrackEdit(UI.Button(pane, L.BTN_BUILDER, 100, function(self)
        ns.Builder.Menu(self, InsertText)
    end, L.BTN_BUILDER, L.BTN_BUILDER_TIP))
    ui.builderButton:SetPoint("LEFT", ui.nameBox, "RIGHT", 12, 0)
    ui.templateButton = TrackEdit(UI.Button(pane, L.BTN_TEMPLATE, 100, SaveAsTemplate, L.BTN_TEMPLATE,
        L.BTN_TEMPLATE_TIP))
    ui.templateButton:SetPoint("LEFT", ui.builderButton, "RIGHT", 4, 0)

    -- Makrotext
    local textLabel = TrackEdit(pane:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall"))
    textLabel:SetPoint("TOPLEFT", ui.nameBox, "BOTTOMLEFT", -6, -10)
    textLabel:SetText(L.DETAIL_TEXT)

    ui.charCount = TrackEdit(pane:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall"))
    ui.charCount:SetPoint("RIGHT", pane, "RIGHT", -2, 0)
    ui.charCount:SetPoint("BOTTOM", textLabel, "BOTTOM", 0, 0)
    ui.charCount:SetJustifyH("RIGHT")

    -- Textfeld wie MacroFrameTextBackground / MacroFrameText (TooltipBackdropTemplate, GameFontHighlightSmall).
    local ok, textBg = pcall(CreateFrame, "Frame", nil, pane, "TooltipBackdropTemplate")
    if not (ok and textBg) then textBg = CreateFrame("Frame", nil, pane) end
    TrackEdit(textBg)
    -- Füllt den Platz bis über Hinweise und Knopfzeile: angedockt so hoch wie die Makroverwaltung,
    -- als eigenständiges Fenster entsprechend größer.
    textBg:SetPoint("TOPLEFT", textLabel, "BOTTOMLEFT", -6, -4)
    textBg:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 2 * BUTTON_ROW_H + NOTES_H + 6)

    ui.textScroll = CreateScrollFrame("ezMacroFrameTextScroll", textBg, false)
    ui.textScroll:SetPoint("TOPLEFT", 11, -8)
    ui.textScroll:SetPoint("BOTTOMRIGHT", -26, 8)

    ui.textEdit = CreateFrame("EditBox", nil, ui.textScroll)
    ui.textEdit:SetMultiLine(true)
    ui.textEdit:SetAutoFocus(false)
    ui.textEdit:SetFontObject(GameFontHighlightSmall)
    ui.textEdit:SetWidth(DETAIL_W - 40)
    ui.textEdit:SetHeight(130)
    ui.textEdit:SetMaxLetters(1023)
    ui.textScroll:SetScrollChild(ui.textEdit)
    ui.textEdit:SetScript("OnEscapePressed", EditBox_ClearFocus or function(self) self:ClearFocus() end)
    ui.textEdit:HookScript("OnTextChanged", OnEdited)
    -- Mitscrollen beim Tippen mit Blizzards eigenen Helfern, wie MacroFrameText.
    if ScrollingEdit_OnCursorChanged and ScrollingEdit_OnUpdate and ScrollingEdit_OnTextChanged then
        ui.textEdit:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        ui.textEdit:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, self:GetParent()) end)
        ui.textEdit:HookScript("OnTextChanged", function(self) ScrollingEdit_OnTextChanged(self, self:GetParent()) end)
    else
        ui.textEdit:SetScript("OnCursorChanged", function(_, _, y, _, height)
            local scroll = ui.textScroll
            local top = -y
            local offset = scroll:GetVerticalScroll()
            local visible = scroll:GetHeight()
            if top < offset then
                scroll:SetVerticalScroll(top)
            elseif top + height > offset + visible then
                scroll:SetVerticalScroll(math.min(top + height - visible, scroll:GetVerticalScrollRange()))
            end
        end)
    end
    textBg:EnableMouse(true)
    textBg:SetScript("OnMouseDown", function() ui.textEdit:SetFocus() end)

    ui.notes = Track(pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    ui.notes:SetPoint("TOPLEFT", textBg, "BOTTOMLEFT", 2, -6)
    ui.notes:SetPoint("RIGHT", pane, "RIGHT", 0, 0)
    ui.notes:SetHeight(NOTES_H) -- vier Zeilen, wichtigste Hinweise zuerst
    ui.notes:SetJustifyH("LEFT")
    ui.notes:SetJustifyV("TOP")
    ui.notes:SetSpacing(2)

    -- Speicherort und Knöpfe: der Haken in der Zeile über den Knöpfen (Entwurf A)
    -- Haken über ezCores Baustein (Blizzards UICheckButtonTemplate) in Core.Style.BUTTON.check (20; bisher 26)
    ui.perChar = Track(ezCore.CreateCheck(pane, ezCore.Style.IconSize("check")))
    ui.perChar:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", -4, BUTTON_ROW_H - 4)
    ui.perChar:SetScript("OnEnter", TipScript(L.CHK_PERCHAR, L.CHK_PERCHAR_TIP))
    ui.perChar:SetScript("OnLeave", RowOnLeave)
    ui.perCharLabel = Track(pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"))
    ui.perCharLabel:SetPoint("LEFT", ui.perChar, "RIGHT", 2, 1)
    ui.perCharLabel:SetText(L.CHK_PERCHAR)

    ui.importButton = Track(CreateFrame("Button", nil, pane, "UIPanelButtonTemplate"))
    ui.importButton:SetSize(120, 22)
    ui.importButton:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, -2)
    ui.importButton:SetText(L.BTN_IMPORT)
    ui.importButton:SetScript("OnClick", ImportCurrent)
    ui.importButton:SetScript("OnEnter", function(self)
        if current and current.heal then return ShowTip(self, self:GetText(), L.HEAL_IMPORT_TIP) end
        -- veraltetes Emote-Makro: zuerst, was veraltet ist und was „Aktualisieren“ tut (mit Grund)
        local outdated = current and not current.tool and ui.outdated and ns.Emote.OutdatedText(current)
        ShowTip(self, self:GetText(), outdated and (outdated .. "\n\n" .. L.BTN_IMPORT_TIP) or L.BTN_IMPORT_TIP)
    end)
    ui.importButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ui.resetButton = TrackEdit(CreateFrame("Button", nil, pane, "UIPanelButtonTemplate"))
    ui.resetButton:SetSize(110, 22)
    ui.resetButton:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, BUTTON_ROW_H - 2)
    ui.resetButton:SetText(L.BTN_RESET)
    ui.resetButton:SetScript("OnEnter", TipScript(L.BTN_RESET, L.BTN_RESET_TIP))
    ui.resetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.resetButton:SetScript("OnClick", function()
        if not current then return end
        ns.ResetEdit(current)
        ShowDetail(current)
        UpdateRows()
    end)

    -- Ansagen: „Jetzt ansagen“ schickt den Satz sofort in den Kanal, der gerade gilt (Leitlinie 3: der Befehl
    -- „/ezmacro ansage“ hat damit einen sichtbaren Knopf). In der Zeile über „Übernehmen“, rechts. Ist die Ansage
    -- angepasst, geht die angepasste Fassung hinaus (Announce.SendEntry).
    ui.sayButton = UI.Button(pane, L.ANN_SAY, 120, function()
        if current and current.say then ns.Announce.SendEntry(current) end
    end, L.ANN_SAY, L.ANN_SAY_TIP)
    ui.sayButton:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, BUTTON_ROW_H - 2)
    ui.sayButton:Hide()

    -- Reiter „Chat“ (Entwurf A): „Auf die Leiste“ legt ein Emote auf eine Emote-Leiste (ezBars) bzw. schaltet die
    -- Ansage-Leiste an der Raid-Verwaltung (sie zeigt immer alle Ansagen der Lage, in der du bist).
    ui.toBarButton = UI.Button(pane, L.BTN_TO_BAR, 120, function(self) Browser.ToBarMenu(self) end)
    ui.toBarButton:SetScript("OnEnter", function(self) ShowTip(self, L.BTN_TO_BAR, Browser.ToBarTip()) end)
    ui.toBarButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- auch grau zeigt der Knopf, warum (Chat-Zeilen passen nicht auf die Emote-Leiste)
    if ui.toBarButton.SetMotionScriptsWhileDisabled then ui.toBarButton:SetMotionScriptsWhileDisabled(true) end
    ui.toBarButton:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, BUTTON_ROW_H - 2)
    ui.toBarButton:Hide()

    -- Eigene Vorlagen: „Löschen“ an der Stelle von „Zurücksetzen“ (auf beiden Seiten sichtbar).
    ui.deleteButton = Track(UI.Button(pane, ezCore.Word("DELETE"), 110, DeleteCurrent, ezCore.Word("DELETE"),
        L.CUSTOM_DELETE_TIP))
    ui.deleteButton:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, BUTTON_ROW_H - 2)
end

---------------------------------------------------------------------------
-- „Auf die Leiste“ (Reiter „Chat“, Entwurf A)
---------------------------------------------------------------------------

-- Was „Auf die Leiste“ mit dem Eintrag tun kann: "emote" (reines Emote, passt auf eine Emote-Leiste), "announce"
-- (Ansage: die Ansage-Leiste zeigt sie mit ihrer Gruppe), "text" (Emote-Makro mit Chat-Zeile: passt nicht) oder nil.
local function ToBarKind(entry)
    if type(entry) ~= "table" then return nil end
    if entry.category == "announce" then return "announce" end
    if entry.category ~= "emote" then return nil end
    for _, option in ipairs(ns.EmoteBar.Options()) do
        if option.entry == entry then return "emote" end
    end
    return "text"
end
Browser.ToBarKind = ToBarKind

local function BarList()
    local bars = ns.EmoteBar.List()
    return type(bars) == "table" and bars or {}
end

-- Nummern der Emote-Leisten, auf denen das Emote liegt („1, 2“) oder nil.
local function BarsWith(entry)
    local found = {}
    for index, data in ipairs(BarList()) do
        if type(data.emotes) == "table" and data.emotes[entry.id] then found[#found + 1] = tostring(index) end
    end
    return #found > 0 and table.concat(found, ", ") or nil
end

function Browser.UpdateToBar()
    local kind = ToBarKind(current)
    ui.toBarButton:SetEnabled(kind == "emote" or kind == "announce")
end

function Browser.ToBarTip()
    local kind = ToBarKind(current)
    if kind == "emote" then
        local on = BarsWith(current)
        local tip = L.BTN_TO_BAR_TIP_emote
        if not ns.EmoteBar.Available() then tip = tip .. "\n" .. Colored("ORANGE_FONT_COLOR", L.OPT_BAR_NEED) end
        if on then tip = tip .. "\n" .. Colored("GREEN_FONT_COLOR", L.BTN_TO_BAR_ON:format(on)) end
        return tip
    elseif kind == "announce" then
        local on, off = Colored("GREEN_FONT_COLOR", L.ON), Colored("GRAY_FONT_COLOR", L.OFF)
        return L.BTN_TO_BAR_TIP_announce .. "\n" .. L.BTN_TO_BAR_STATE:format(ns.S.announceBar and on or off)
    end
    return L.BTN_TO_BAR_TIP_text
end

-- Emote: Menü mit einem Haken je Emote-Leiste und „Neue Leiste“ (ohne ezBars der Hinweis mit Knopf, Frage 16);
-- Ansage: Haken „Ansage-Leiste an der Raid-Verwaltung“ (dieselbe Einstellung wie auf der Einstellungsseite).
function Browser.ToBarMenu(owner)
    local entry = current
    local kind = ToBarKind(entry)
    if kind == "emote" then
        if not ns.EmoteBar.Available() then return ns.EmoteBar.ShowNeed() end
        Menu.Open(owner, function(root)
            Menu.Title(root, L.BTN_TO_BAR)
            for index, data in ipairs(BarList()) do
                Menu.Toggle(root, L.BAR_TITLE_N:format(index),
                    function() return type(data.emotes) == "table" and data.emotes[entry.id] == true end,
                    function(on) ns.EmoteBar.SetEmote(data, entry.id, on) end)
            end
            Menu.Divider(root)
            Menu.Button(root, L.BAR_NEW, function()
                local data = ns.EmoteBar.Add()
                if type(data) == "table" then ns.EmoteBar.SetEmote(data, entry.id, true) end
            end)
        end)
    elseif kind == "announce" then
        Menu.Open(owner, function(root)
            Menu.Title(root, L.BTN_TO_BAR)
            Menu.Tip(Menu.Toggle(root, L.OPT_announceBar, function() return ns.S.announceBar end,
                function(on) ns.SetSetting("announceBar", on and true or false) end),
                L.OPT_announceBar, L.OPT_announceBar_TIP)
        end)
    end
end

-- Einmalige Übernahme der alten Reiter-Wahl (acht Reiter bis Welle 23) in Reiter und Auswahl nach Entwurf A. Die
-- frühere Vorauswahl „Klasse“ (deine Klasse) wird „Für mich“ – sie zeigt deine Klasse zuerst –, der dort gemerkte
-- Eintrag gilt auch für „Für mich“. ezMacroDB.window.category bleibt stehen (ohne Verlust umkehrbar).
local OLD_TAB = { class = { "macros", "mine" }, race = { "macros", "race" }, general = { "macros", "general" },
    custom = { "macros", "custom" }, oneclick = { "oneclick" }, emote = { "chat", "emote" }, announce = { "chat" },
    tools = { "tools" } }
local function MigrateWindow()
    local window = ns.db.window
    window.views = type(window.views) == "table" and window.views or {}
    window.selected = type(window.selected) == "table" and window.selected or {}
    if ns.TAB_INDEX[window.tab] then return end
    local old = OLD_TAB[window.category] or OLD_TAB.class
    window.tab = old[1]
    if old[1] == "chat" and not old[2] then
        window.views.chat = ns.Announce.DefaultGroup()
    elseif old[2] then
        window.views[old[1]] = old[2]
    end
    if window.selected.mine == nil then window.selected.mine = window.selected.class end
end
Browser.MigrateWindow = MigrateWindow

local function Create()
    -- Der Browser ist ein Seitenfenster der Makroverwaltung: ohne eigenes Porträt wie Blizzards Seitenfenster
    -- (NewWindow ruft ButtonFrameTemplate_HidePortrait); nur ältere Clients ohne diese Funktion bekommen das
    -- Notiz-Symbol, damit die Ecke nicht leer bleibt. Esc schließt (UISpecialFrames).
    frame = ezCore.NewWindow("ezMacroFrame", {
        template = "ButtonFrameTemplate", title = L.TITLE, width = FRAME_W, height = FRAME_H,
        portrait = not ButtonFrameTemplate_HidePortrait and "Interface\\Icons\\INV_Misc_Note_02" or nil,
        positionKey = POSITION_KEY, import = ns.db.window.pos, default = { "CENTER", "CENTER", 0, 40 },
    })
    -- Verschieben nur als eigenständiges Fenster; angedockt wandert es mit der Makroverwaltung.
    frame:SetScript("OnDragStart", function(self)
        if not ui.docked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        if ui.docked then return end
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        SavePosition()
    end)
    -- Das X schließt den Browser bewusst: Zustand für das nächste Öffnen merken.
    if type(frame.CloseButton) == "table" then
        frame.CloseButton:HookScript("OnClick", function() ns.db.window.open = false end)
    end

    local inset = frame.Inset
    if not inset then
        inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
        frame.Inset = inset
    end
    -- Das Inset umfasst nur die Liste; Vorschau und Bearbeitung liegen rechts auf dem Fensterhintergrund.
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, LAYOUT.CONTENT_TOP)
    inset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 26)
    inset:SetWidth(INSET_W)

    -- Obere Leiste: Auswahl des Reiters, Gruppe (Klasse bzw. Volk), Art, „Alle zeigen“ links, Suche rechts
    -- (LayoutHeader). Die Gruppe entsteht zuerst – ihre Lage setzt LayoutHeader.
    ui.group = CreateGroupSelector()
    ui.group:HookScript("OnEnter", function(self) ShowTip(self, L.GROUP_TIP_TITLE, L.GROUP_TIP) end)
    ui.group:HookScript("OnLeave", function() GameTooltip:Hide() end)
    local headerX = frame.ezPortrait and LAYOUT.HEADER_X or LAYOUT.HEADER_X_PLAIN
    ui.headerX = headerX
    ui.group:SetPoint("TOPLEFT", frame, "TOPLEFT", headerX, LAYOUT.HEADER_Y)

    ui.view = CreateViewSelector()
    ui.view:HookScript("OnEnter", function(self)
        if state.tab == "chat" then
            ShowTip(self, L.VIEW_TIP_TITLE, L.VIEW_TIP_chat)
        else
            ShowTip(self, L.VIEW_TIP_TITLE, L.VIEW_TIP_macros)
        end
    end)
    ui.view:HookScript("OnLeave", function() GameTooltip:Hide() end)
    ui.view:SetPoint("TOPLEFT", frame, "TOPLEFT", headerX, LAYOUT.HEADER_Y)

    -- Auswahl „Art“ (Reiter „Makros“): Makro-Arten aus Welle 15 wie in Blizzards Makroverwaltung
    ui.kindButton = UI.Button(frame, L.KIND_BUTTON:format(L.MACRO_KIND_all), KIND_W, function(self) KindMenu(self) end)
    ui.kindButton:SetScript("OnEnter", function(self) ShowTip(self, L.KIND_BUTTON_TITLE, L.VIEW_KIND_TIP) end)
    ui.kindButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.kindButton:Hide()

    ui.autoInfo = CreateFrame("Button", nil, frame)
    ui.autoInfo:SetHeight(20)
    ui.autoInfo:SetPoint("TOPLEFT", frame, "TOPLEFT", headerX + 4, LAYOUT.SEARCH_Y_PLAIN)
    ui.autoInfo.text = ui.autoInfo:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ui.autoInfo.text:SetPoint("LEFT")
    ui.autoInfo:SetScript("OnClick", function() ns.OpenSettings() end)
    ui.autoInfo:SetScript("OnEnter", function(self)
        SetFontColor(self.text, "NORMAL_FONT_COLOR")
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        ezCore.TipTitle(GameTooltip, L[INFO_TIPS[state.category] or "AUTO_INFO_TIP"])
        GameTooltip:Show()
    end)
    ui.autoInfo:SetScript("OnLeave", function(self)
        SetFontColor(self.text, "HIGHLIGHT_FONT_COLOR")
        GameTooltip:Hide()
    end)
    ui.autoInfo:Hide()

    -- Reiter „Chat“ (Emotes) ohne ezBars: Hinweis mit Knopf statt einer Emote-Leiste (Frage 16, EmoteBar.lua)
    ui.barsNeed = CreateFrame("Button", nil, frame)
    ui.barsNeed:SetHeight(20)
    ui.barsNeed:SetPoint("LEFT", ui.autoInfo, "RIGHT", 12, 0)
    ui.barsNeed.text = ui.barsNeed:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ui.barsNeed.text:SetPoint("LEFT")
    ui.barsNeed:SetScript("OnClick", function() ns.EmoteBar.ShowNeed() end)
    ui.barsNeed:SetScript("OnEnter", function(self)
        ShowTip(self, L.OPT_BAR_NEED, L.OPT_BAR_NEED_TIP, "ANCHOR_BOTTOMRIGHT")
    end)
    ui.barsNeed:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.barsNeed:Hide()

    ui.allButton = CreateFrame("Button", "ezMacroFrameShowAll", frame, "UIPanelButtonTemplate")
    ui.allButton:SetSize(ALL_W, 22)
    ui.allButton:SetScript("OnClick", function()
        PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
        state.showAll = not state.showAll
        ns.db.window.showAll = state.showAll
        UpdateList(true)
    end)
    ui.allButton:SetScript("OnEnter", function(self)
        ShowTip(self, state.showAll and L.BTN_SHOW_RECOMMENDED or L.BTN_SHOW_ALL:format(hiddenOptional), L.SHOW_ALL_TIP,
            "ANCHOR_BOTTOMRIGHT")
    end)
    ui.allButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.allButton:Hide()

    -- Auswahl „Nur Eigene“ (Reiter „Makros“): neue Vorlage, aus geteiltem Text, aus einem vorhandenen Makro.
    ui.customBar = CreateFrame("Frame", nil, frame)
    ui.customBar:SetSize(298, LAYOUT.BUTTON_H)
    ui.customBar:SetPoint("TOPLEFT", frame, "TOPLEFT", frame.ezPortrait and LAYOUT.HEADER_X or LAYOUT.HEADER_X_PLAIN,
        LAYOUT.HEADER_Y - 1)
    local newButton = UI.Button(ui.customBar, L.BTN_NEW, 80, function()
        Browser.ShowEntry(ns.Custom.New(), true)
    end, L.BTN_NEW, L.BTN_NEW_TIP)
    newButton:SetPoint("LEFT")
    local textButton = UI.Button(ui.customBar, L.BTN_FROM_TEXT, 100, function() ns.ImportText() end,
        L.BTN_FROM_TEXT, L.BTN_FROM_TEXT_TIP)
    textButton:SetPoint("LEFT", newButton, "RIGHT", 4, 0)
    local macroButton = UI.Button(ui.customBar, L.BTN_FROM_MACRO, 110, function(self)
        Menu.Open(self, function(root) FromMacroMenu(self, root) end)
    end, L.BTN_FROM_MACRO, L.BTN_FROM_MACRO_TIP)
    macroButton:SetPoint("LEFT", textButton, "RIGHT", 4, 0)
    ui.customBar:Hide()

    ui.search = CreateFrame("EditBox", "ezMacroFrameSearch", frame, "SearchBoxTemplate")
    ui.search:SetSize(SEARCH_W, LAYOUT.SEARCH_H)
    ui.search:SetPoint("TOPRIGHT", frame, "TOPRIGHT", LAYOUT.SEARCH_X, LAYOUT.SEARCH_Y_PLAIN)
    ui.search:SetAutoFocus(false)
    ui.search:HookScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text == state.search then return end
        state.search = text
        UpdateList()
    end)

    -- Liste
    ui.listScroll = CreateScrollFrame("ezMacroFrameListScroll", inset, true)
    ui.listScroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -5)
    ui.listScroll:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 6, 5)
    ui.listScroll:SetWidth(LIST_W)
    ui.content = CreateFrame("Frame", nil, ui.listScroll)
    ui.content:SetSize(LIST_W, 1)
    ui.listScroll:SetScrollChild(ui.content)

    ui.empty = inset:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    ui.empty:SetPoint("TOPLEFT", ui.listScroll, "TOPLEFT", 12, -24)
    ui.empty:SetWidth(LIST_W - 24)
    ui.empty:SetJustifyH("CENTER")
    ui.empty:Hide()

    CreateDetail()

    -- Untere Leiste
    ui.count = frame:Footer("")
    local settingsButton = frame:SettingsButton(function() ns.OpenSettings() end)

    -- Nur als eigenständiges Fenster sichtbar (angedockt ist die Makroverwaltung ja schon offen).
    ui.macrosButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    ui.macrosButton:SetSize(120, LAYOUT.BUTTON_H)
    ui.macrosButton:SetPoint("RIGHT", settingsButton, "LEFT", -LAYOUT.GAP, 0)
    ui.macrosButton:SetText(L.BTN_MACROS)
    ui.macrosButton:SetScript("OnClick", OpenMacroFrame)
    ui.macrosButton:SetScript("OnEnter", TipScript(L.BTN_MACROS, L.BTN_MACROS_TIP))
    ui.macrosButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Ansagen: „Zum Ziel …“ öffnet die Ansagen des Rechtsklick-Menüs für das aktuelle Ziel (MACRO-26,
    -- Leitlinie 3: sichtbarer Zugang zum Menü-Eintrag). Links neben „Makros“ bzw. „Einstellungen“ (LayoutFooter).
    ui.settingsButton = settingsButton
    ui.targetButton = UI.Button(frame, L.ANN_TARGET_BUTTON, 120, function(self) ns.AnnounceMenu.OpenFor(self) end,
        L.ANN_TARGET_TITLE, L.ANN_TARGET_BUTTON_TIP)
    ui.targetButton:SetPoint("RIGHT", settingsButton, "LEFT", -LAYOUT.GAP, 0)
    ui.targetButton:Hide()

    -- Reiter „Chat“ (Entwurf A): „Leiste einstellen“ – bei den Emotes Größe, Spalten und Reihen der Emote-Leiste in
    -- ezBars (ohne ezBars der Hinweis mit Knopf, Frage 16), bei den Ansagen ezMacros Einstellungen (Ansage-Leiste an der
    -- Raid-Verwaltung; sie zeichnet ezMacro selbst, nicht ezBars).
    ui.barButton = UI.Button(frame, L.BTN_BAR_SETTINGS, 130, function()
        if state.category == "emote" then ns.EmoteBar.OpenSettings() else ns.OpenSettings() end
    end)
    ui.barButton:SetScript("OnEnter", function(self)
        ShowTip(self, L.BTN_BAR_SETTINGS, state.category == "emote" and L.BTN_BAR_SETTINGS_TIP_emote
            or L.BTN_BAR_SETTINGS_TIP_announce)
    end)
    ui.barButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.barButton:SetPoint("RIGHT", settingsButton, "LEFT", -LAYOUT.GAP, 0)
    ui.barButton:Hide()

    -- Reiter unten: vier nach Zweck (Entwurf A, ns.TABS)
    frame.Tabs = {}
    for index, tabKey in ipairs(ns.TABS) do
        local tab = CreateFrame("Button", "ezMacroFrameTab" .. index, frame, "PanelTabButtonTemplate")
        tab:SetID(index)
        tab:SetText(L["TAB_" .. tabKey])
        -- Abstände wie Blizzards eigene Reiter (z. B. InspectFrame).
        if index == 1 then
            tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        else
            tab:SetPoint("LEFT", frame.Tabs[index - 1], "RIGHT", -16, 0)
        end
        tab:SetScript("OnClick", function()
            PlaySoundKit("IG_CHARACTER_INFO_TAB")
            SelectTab(tabKey)
        end)
        tab:HookScript("OnEnter", function(self) ShowTip(self, L["TAB_" .. tabKey], L["TAB_TIP_" .. tabKey], "ANCHOR_BOTTOM") end)
        tab:HookScript("OnLeave", function() GameTooltip:Hide() end)
        if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
        frame.Tabs[index] = tab
    end
    if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(frame, #ns.TABS) end

    frame:SetScript("OnShow", function()
        PlaySoundKit("IG_CHARACTER_INFO_OPEN")
        -- „Art“ beim Öffnen wieder „Alle“, wie Blizzards Filter in der Makroverwaltung (Kinds.lua)
        state.kind = "all"
        Browser.Refresh()
        -- Beim ersten Öffnen: Rundgang, zuerst die kurze Anleitung mit Pfeil auf „Übernehmen“.
        ns.Tour:Start(frame)
    end)
    frame:SetScript("OnHide", function()
        PlaySoundKit("IG_CHARACTER_INFO_CLOSE")
        ns.Highlight.Clear()
        ui.nameBox:ClearFocus()
        ui.textEdit:ClearFocus()
        ui.search:ClearFocus()
    end)
    frame:Hide()

    MigrateWindow()
    state.tab = ns.TAB_INDEX[ns.db.window.tab] and ns.db.window.tab or "macros"
    state.view = ns.db.window.views          -- dieselbe Tabelle: die Auswahl je Reiter ist gleich gemerkt
    state.showAll = ns.db.window.showAll == true
end

---------------------------------------------------------------------------
-- Öffentliche Funktionen
---------------------------------------------------------------------------

function Browser.Refresh()
    if not frame then return end
    if ns.Long then ns.Long.Cleanup() end
    SelectTab(state.tab)
    UpdateCounts()
end

---------------------------------------------------------------------------
-- Andocken an Blizzards Makroverwaltung (taint-sicher: nur HookScript, nichts überschrieben,
-- nichts in MacroFrame-Tabellen geschrieben)
---------------------------------------------------------------------------

local hooked = false

local function MacroFrameAvailable()
    return type(MacroFrame) == "table" and type(MacroFrame.HookScript) == "function"
end

local function SetDocked(docked)
    ui.docked = docked
    if docked then
        ns.Dock(frame, MacroFrame)
    else
        frame:ClearAllPoints()
        frame:SetHeight(FRAME_H)
        frame:SetClampedToScreen(true)
        RestorePosition()
    end
    ui.macrosButton:SetShown(not docked)
    LayoutFooter()
end

local function CreateToggleButton()
    local button = CreateFrame("Button", "ezMacroMacroFrameButton", MacroFrame, "UIPanelButtonTemplate")
    button:SetSize(80, 22)
    -- Freie Lücke in Blizzards Knopfleiste: zwischen „Löschen“ (links) und „Neu“/„Beenden“ (rechts).
    button:SetPoint("BOTTOMLEFT", MacroFrame, "BOTTOMLEFT", 86, 4)
    button:SetText(L.TITLE)
    button:SetScript("OnClick", function()
        PlaySoundKit("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Browser.ToggleDocked()
    end)
    button:SetScript("OnEnter", TipScript(L.TITLE, L.TOGGLE_TIP))
    button:SetScript("OnLeave", RowOnLeave)
    ui.toggleButton = button
end

local function HookMacroFrame()
    if hooked or not MacroFrameAvailable() then return end
    hooked = true
    if not frame then Create() end
    SetDocked(true)
    CreateToggleButton()
    -- Mit der Makroverwaltung öffnen (wenn zuletzt offen) und immer mit ihr schließen.
    MacroFrame:HookScript("OnShow", function()
        if ns.db.window.open then frame:Show() end
    end)
    MacroFrame:HookScript("OnHide", function()
        frame:Hide()
    end)
    frame:SetShown(MacroFrame:IsShown() and ns.db.window.open and true or false)
end

-- Lädt und zeigt Blizzards Makroverwaltung über ezCore (Core.OpenPanel lädt selbst; ohne Hinweis, weil Browser.Open
-- den Kampf vorher abfängt) und hängt den Browser an. Rückgabe: true, wenn angedockt.
local function LoadMacroUI()
    ezCore.OpenPanel("macro", nil, true)
    HookMacroFrame()
    return hooked
end

local OPEN_KEY = "browser.open"                 -- Schlüssel in ns.AfterCombat
local OPEN_WAITING = "ezMacro:" .. OPEN_KEY     -- derselbe Schlüssel, wie ezCore ihn führt (Modul:Schlüssel)

-- Öffnet Makroverwaltung plus Browser. Im Kampf wird das Öffnen der Makroverwaltung (ein UIPanel)
-- auf das Kampfende verschoben (ns.AfterCombat); ist sie schon offen, erscheint der Browser sofort.
function Browser.Open()
    ns.db.window.open = true
    if not frame then Create() end
    if hooked and MacroFrame:IsShown() then
        frame:Show()
        return
    end
    if ns.InCombat() then
        if not ezCore.AfterCombatWaiting(OPEN_WAITING) then ezCore.CombatNotice(ns, L.OPEN_COMBAT_WHAT, "later") end
        ns.AfterCombat(function()
            if ns.db.window.open then Browser.Open() end
        end, OPEN_KEY)
        return
    end
    if LoadMacroUI() then
        if MacroFrame:IsShown() then frame:Show() end
    else
        -- Rückfall, falls die Makroverwaltung nicht lädt: eigenständiges Fenster.
        SetDocked(false)
        frame:Show()
    end
end

-- Schließt nur den Browser und merkt sich „zu“ (Knopf in der Makroverwaltung).
function Browser.Close()
    ns.db.window.open = false
    ezCore.CancelAfterCombat(OPEN_WAITING)
    if frame then frame:Hide() end
end

-- Knopf „ezMacro“ in der Makroverwaltung: Browser daneben ein-/ausblenden, Zustand merken.
function Browser.ToggleDocked()
    if frame and frame:IsShown() then Browser.Close() else Browser.Open() end
end

-- /ezmacro und Compartment: öffnen Makroverwaltung plus Browser und schließen beide wieder.
-- Der gemerkte Zustand bleibt dabei wie beim Schließen mit Esc erhalten.
function Browser.Toggle()
    if not (frame and frame:IsShown()) then
        Browser.Open()
    elseif ui.docked and MacroFrame:IsShown() then
        -- Blizzards Fenster schließt ezCore (nur außerhalb des Kampfes, im Kampf ein Hinweis); der Browser geht mit
        ezCore.ClosePanel("macro")
    else
        frame:Hide()
    end
end

Browser.Show = Browser.Open

-- Öffnet den Browser auf einem Reiter (z. B. „tools“ für /ezmacro werkzeuge).
-- Kategorie wie bisher („tools“, „announce“, „emote“, „custom“ …), dazu die Reiter („macros“, „chat“ …) und die
-- Auswahlen „mine“ und „clickheal“: öffnet den Reiter, der sie zeigt, auf dieser Auswahl.
function Browser.ShowCategory(category)
    local tab, view = PlaceOfCategory(category)
    if not tab then return end
    if not frame then Create() end
    if frame:IsShown() then return SelectCategory(category) end
    state.tab = tab
    ns.db.window.tab = tab
    if view then state.view[tab] = view end
    Browser.Open()
end

-- Reiter, Auswahl und Gruppe, die einen Eintrag zeigen. „Für mich“ bleibt, wenn der Eintrag dort steht (eigene Vorlage,
-- Makro deiner Klasse, deines Volkes, allgemeines).
local function PlaceOfEntry(entry)
    if entry.tool then return entry.place or "tools" end
    if entry.category == "oneclick" then return "oneclick" end
    if entry.category == "announce" then return "chat", entry.group end
    if entry.category == "emote" then return "chat", "emote" end
    if state.view.macros == "mine" and (entry.category == "custom" or Mine(entry)) then return "macros", "mine" end
    if entry.category == "spells" then return "macros", "mine" end   -- Aus deinen Fähigkeiten: nur in „Für mich“
    if entry.category == "general" then return "macros", entry.group == "clickheal" and "clickheal" or "general" end
    return "macros", entry.category, entry.group   -- class, race, custom, heal
end

-- Zeigt einen Eintrag (eigene Vorlage, Werkzeug …); editing: gleich die Seite „Anpassen“.
function Browser.ShowEntry(entry, editing)
    if not entry then return end
    if not frame then Create() end
    local tab, view, group = PlaceOfEntry(entry)
    -- Ein gezeigter Eintrag muss in der Liste stehen: „Art“ zurück auf „Alle“ (eine neue Vorlage ist sonst bei
    -- „Art: Heilen“ ausgefiltert, und „Neu“ wirkte, als täte es nichts). SelectTab schreibt den Knopf neu.
    state.kind = "all"
    state.tab = tab
    ns.db.window.tab = tab
    if view then state.view[tab] = view end
    local category = ViewCategory(tab, view)
    if group and (category == "class" or category == "race") then state.group[category] = group end
    ns.db.window.selected[category] = entry.id
    if not frame:IsShown() then Browser.Open() end
    if not frame:IsShown() then return end
    SelectTab(tab)
    if editing and current == entry then SetEditing(true) end
end

-- Reiter und Auswahl, die gerade gelten (für Prüfungen und andere Dateien): Reiter, Auswahl, Kategorie, Gruppe
function Browser.Selection()
    return state.tab, state.view[state.tab], state.category, state.group[state.category]
end

function Browser.Current() return current end
function Browser.Frame() return frame end
-- Knopf „Zum Ziel …“ im Reiter „Chat“ (Ansagen) (MACRO-26) oder nil, solange das Fenster nicht gebaut ist.
function Browser.TargetButton() return ui.targetButton end

ns.On("UPDATE_MACROS", SoftRefresh)
ns.Listen("CUSTOM_CHANGED", SoftRefresh)
ns.Listen("NAMES_CHANGED", OnNamesChanged)       -- Name angepasst oder zurückgesetzt (Resolver.lua, ns.NamesChanged)
ns.Listen("HEAL_MACROS_CHANGED", SoftRefresh)   -- ezHeal hat ein Heil-Makro angelegt (HealMacros.lua)
-- Aktionsplätze geändert: „Makros ohne Leiste“ und Leisten-Profile auffrischen (gebündelt).
local slotsPending = false
ns.On("ACTIONBAR_SLOT_CHANGED", function()
    if slotsPending or not (frame and frame:IsShown() and current and current.tool) then return end
    slotsPending = true
    C_Timer.After(0.3, function()
        slotsPending = false
        if frame:IsShown() and current and current.tool then ns.Tools.Refresh(current) end
    end)
end)
ns.On("SPELLS_CHANGED", SoftRefresh)
ns.On("PLAYER_REGEN_DISABLED", function() if frame and frame:IsShown() then UpdateDetailStatus() end end)
ns.On("PLAYER_REGEN_ENABLED", function() if frame and frame:IsShown() then UpdateDetailStatus() end end)

ns.OnSettingChanged(function(key)
    if not (frame and frame:IsShown()) then return end
    if key == "autoThank" or key == "autoSpit" or key == "autoState" then
        -- "autoState": AutoEmote.lua meldet den Stand der Erkennung, sobald er feststeht (Sperre der Heilvorhersage) –
        -- beim Wechsel von „autoThank“ läuft dieser Zuhörer noch vor dem von AutoEmote.lua
        UpdateAutoInfo()
    elseif key == "oneClickUpdate" then
        UpdateAutoInfo()
    elseif key == "hideUnknown" or key == "macros" or key == "macroFromSpells" then
        SoftRefresh()
    elseif (key == "scopeMode" or key == "announceMode") and current then
        -- Ansagen: der Makrotext hängt von der Einstellung ab („/ezmacro ansage …“ oder Blizzards Befehl)
        UpdateAutoInfo()
        ShowDetail(current)
    end
end)

-- Gruppe geändert (Raid gebildet, Leiter gewechselt): Kanal der Ansagen neu anzeigen; bei festen Kanälen ändert
-- sich auch der Makrotext.
local function OnGroupChanged()
    if not (frame and frame:IsShown() and state.category == "announce") then return end
    UpdateAutoInfo()
    if current and not ui.editing and not ns.Announce.Auto() then ShowDetail(current) end
end
ns.On("GROUP_ROSTER_UPDATE", OnGroupChanged)
ns.On("PARTY_LEADER_CHANGED", OnGroupChanged)

ns.OnReady(function()
    ns.db.window.selected = type(ns.db.window.selected) == "table" and ns.db.window.selected or {}
    -- Blizzard_MacroUI lädt erst bei Bedarf: dann andocken und den Knopf anlegen (ezCore fängt Fehler ab).
    ns.WhenAddOnLoaded("Blizzard_MacroUI", HookMacroFrame)
    HookMacroFrame()   -- Rückfall: Makroverwaltung schon da, ohne dass der Client sie als geladen meldet
end)
