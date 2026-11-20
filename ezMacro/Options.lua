local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezMacro (Seite von ezCore).
local page

-- Beschriftung rechts am Schieberegler, z. B. „10 Min.“ – Einheit aus ezCore (Frage 9: Core.Minutes, Core.Seconds)
local function Unit(helper)
    return function(value) return ezCore[helper](value) end
end

local function Choices(values, labelPrefix)
    local list = {}
    for _, value in ipairs(values) do list[#list + 1] = { value, L[labelPrefix .. value] } end
    return list
end

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    -- Allgemein: Knopf zum Fenster. Verschieben und Lagen zurücksetzen gehören zu ezBars, seit die Emote-Leisten
    -- dort angemeldet sind (ezMacro hat keinen eigenen Teil bei ezCore.Mover mehr): Zahnrad » „Leisten verschieben“.
    page:Button(L.OPT_OPEN, L.OPT_OPEN_BUTTON, function() ns.Browser.Show() end, L.OPT_OPEN_TIP)

    -- Prüfung der Einstellungen vom 19.11.2026: „Nur Makros mit gelernten Zaubern zeigen“ (hideUnknown) und „Makros aus
    -- deinen Fähigkeiten“ (macroFromSpells) sind Filter der Liste und stehen im Menü „Art“ des ezMacro-Fensters, nicht
    -- mehr hier; „Veraltete Ränge leuchten lassen“ steht bei „Ränge aktualisieren“, „Spucken mit Ziel“ bei „Emotes“
    page:Header(L.OPT_HEADER_MACROS)
    page:Checkbox("pickupAfterImport")
    page:Checkbox("chatButton")
    page:Dropdown("scopeMode", Choices({ "auto", "char", "account" }, "OPT_SCOPE_"))
    -- Makros nach Art in Blizzards Makroverwaltung (Kinds.lua): Knopf „Art“, Abblenden, Tooltip, Rechtsklick
    page:Checkbox("macroKinds")

    page:Header(L.OPT_HEADER_AUTO)
    -- Grau, solange der Client die Heilvorhersage sperrt und der Schalter aus ist (T14-6, AutoEmote.lua)
    local _, thankRow = page:Checkbox("autoThank")
    if type(thankRow) == "table" and thankRow.AddModifyPredicate and ns.Auto and ns.Auto.ThankSwitchable then
        thankRow:AddModifyPredicate(function() return ns.Auto.ThankSwitchable() end)
    end
    page:Checkbox("autoSpit")
    page:Dropdown("autoStyle", Choices({ "emote", "text" }, "OPT_STYLE_"))
    -- Abstände je Art nur für die Automatik (AutoEmote.lua: ohne autoThank/autoSpit kein Lauf ohne Klick) – grau,
    -- solange sie aus ist (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)
    page:Slider("thankCooldown", 1, 60, 1, Unit("Minutes"), nil, { parent = "autoThank" })
    page:Slider("spitCooldown", 1, 60, 1, Unit("Minutes"), nil, { parent = "autoSpit" })
    page:Slider("globalCooldown", 10, 600, 10, Unit("Seconds"))
    page:Checkbox("openWorldOnly")
    page:Checkbox("thankAfterCombat", nil, { parent = "autoThank" })
    page:Checkbox("announce")

    -- Ansagen für Anführer (Reiter „Chat“ (Ansagen)): wie der Kanal gewählt wird
    page:Header(L.OPT_HEADER_ANNOUNCE)
    page:Button(L.OPT_ANNOUNCE_OPEN, L.OPT_ANNOUNCE_OPEN_BUTTON, function() ns.Browser.ShowCategory("announce") end,
        L.OPT_ANNOUNCE_OPEN_TIP)
    page:Dropdown("announceMode", Choices({ "auto", "fixed" }, "OPT_ANNOUNCE_"))
    page:Checkbox("announceBar")
    page:Checkbox("announceMenu")

    -- Ein-Klick-Makros (Reiter „Ein-Klick“): mit dem besten Gegenstand aktuell halten
    page:Header(L.OPT_HEADER_ONECLICK)
    page:Button(L.OPT_ONECLICK_OPEN, L.OPT_ONECLICK_OPEN_BUTTON, function() ns.Browser.ShowCategory("oneclick") end,
        L.OPT_ONECLICK_OPEN_TIP)
    page:Checkbox("oneClickUpdate")
    -- Helfer „Eine Taste“ (OneKey.lua): je Helfer ein Schalter, dazu die beiden Werkzeuge
    -- grau ohne „Ein-Klick-Makros aktuell halten“: OneKey.Active verlangt ihn (sonst zeigte das Makro A, der Knopf wirkte B)
    page:Checkbox("oneKeyConjure", nil, { parent = "oneClickUpdate" })
    page:Checkbox("oneKeyQuest", nil, { parent = "oneClickUpdate" })
    page:Checkbox("oneKeyOpen", nil, { parent = "oneClickUpdate" })
    page:Button(L.OPT_ONEKEY_OPEN, L.OPT_ONEKEY_OPEN_BUTTON, function() ns.Browser.ShowEntry(ns.Tools.Get("onekeyOpen")) end,
        L.OPT_ONEKEY_OPEN_TIP)
    page:Checkbox("oneKeyPet", nil, { parent = "oneClickUpdate" })
    -- Dämon der Begleiter-Taste nur für Hexenmeister (Prüfung der Einstellungen vom 19.11.2026); die Wahl steht für alle
    -- auch im Werkzeug „Begleiter“ selbst (OneKey.lua)
    if ns.ShowsPetDemon() then
        page:Dropdown("petDemon", Choices({ "imp", "voidwalker", "succubus", "felhunter" }, "OPT_DEMON_"))
    end
    page:Button(L.OPT_ONEKEY_PET, L.OPT_ONEKEY_PET_BUTTON, function() ns.Browser.ShowEntry(ns.Tools.Get("onekeyPet")) end,
        L.OPT_ONEKEY_PET_TIP)

    -- Angeln mit einer Taste (Werkzeug „Angeln mit einer Taste“)
    page:Header(L.OPT_HEADER_FISH)
    page:Button(L.OPT_FISH_OPEN, L.OPT_FISH_OPEN_BUTTON, function() ns.Browser.ShowEntry(ns.Tools.Get("fishing")) end,
        L.OPT_FISH_OPEN_TIP)
    page:Checkbox("fishingKey")

    -- Emote-Leisten über ezBars: Emotes je Leiste über ihr Zahnrad (oder Rechtsklick), Raster und Lage auf der Seite
    -- der Leiste bei ezBars. Läuft ezBars nicht, steht hier nur der Hinweis mit Knopf (Frage 16).
    -- Emotes (Emote.lua): Spucken mit Ziel gilt für Leiste, Makro und Hinterherspucken
    page:Header(L.OPT_HEADER_EMOTES)
    page:Checkbox("spitAnimation")

    page:Header(L.OPT_HEADER_BAR)
    page:Checkbox("barShown")
    local function WithBars() return ns.EmoteBar.Available() end
    local function WithoutBars() return not ns.EmoteBar.Available() end
    -- Sichtbar je nach ezBars über ezCores opts.shown (vorher eine eigene Hilfe über Blizzards Zeile, Fund 12 der
    -- Gegenprüfung Welle 5; page:Button kennt opts.shown seit Welle 6)
    page:Button(L.OPT_BAR_NEED, L.OPT_BAR_NEED_BUTTON, function() ns.EmoteBar.ShowNeed() end, L.OPT_BAR_NEED_TIP,
        { shown = WithoutBars })
    page:Button(L.OPT_BAR_SETTINGS, L.OPT_BAR_SETTINGS_BUTTON, function() ns.EmoteBar.OpenSettings() end,
        L.OPT_BAR_SETTINGS_TIP, { shown = WithBars })
    page:Button(L.OPT_BAR_NEW, L.OPT_BAR_NEW_BUTTON, function() ns.EmoteBar.Add() end, L.OPT_BAR_NEW_TIP,
        { shown = WithBars })
    page:Button(L.OPT_BAR_RESET, L.OPT_BAR_RESET_BUTTON, function() ns.EmoteBar.Reset() end, L.OPT_BAR_RESET_TIP,
        { shown = WithBars })

    -- Ränge aktualisieren (Knopf im Zauberbuch und im Reiter „Werkzeuge“)
    page:Header(L.OPT_HEADER_RANKS)
    page:Checkbox("rankGlow")
    page:Checkbox("rankAuto")

    -- Werkzeuge im Makro-Browser: Makros sichern, Leisten-Profile (die Knöpfe dazu sitzen im Reiter selbst)
    page:Header(L.OPT_HEADER_TOOLS)
    page:Button(L.OPT_TOOLS, L.OPT_TOOLS_BUTTON, function() ns.Browser.ShowCategory("tools") end, L.OPT_TOOLS_TIP)
    page:Checkbox("backupOnLogout")
    page:Checkbox("profileMacros")
    page:Checkbox("profileBindings")
    page:Checkbox("profileClearEmpty")

    -- Erweitert: Rundgang und Erklärungen wieder zeigen, die Prüfungen der Befehle status, pruefen und test als Knöpfe
    -- (Leitlinie 3), ergänzende Addons
    page:Advanced()
    page:TourButton({ Reset = function() ns.ResetHints() end }, L.OPT_HINTS_TIP)
    page:StatusButton(L.OPT_STATUS_TIP)   -- Beschriftung von ezCore (Gesamtreview T9-2)
    page:Button(L.OPT_CHECK, L.OPT_CHECK_BUTTON, function() ns.CheckSpells() end, L.OPT_CHECK_TIP)
    page:Button(L.OPT_TEST_THANK, L.OPT_TEST_THANK_BUTTON, function() ns.TestEmote("thank") end, L.OPT_TEST_THANK_TIP)
    page:Button(L.OPT_TEST_SPIT, L.OPT_TEST_SPIT_BUTTON, function() ns.TestEmote("spit") end, L.OPT_TEST_SPIT_TIP)
    -- „Einstellungen zurücksetzen“ von ezCore mit Rückfrage (Gesamtreview T9-4); Makros, Vorlagen, Sicherungen und
    -- Leisten-Profile bleiben. Dieselbe Rückfrage nimmt „/ezmacro zuruecksetzen“ (slash.reset).
    page:ResetButton({ tip = L.OPT_RESET_TIP })
    -- Ergänzende Addons (ezCore.AddCompanion): ezMacro braucht nur ezCollection (Basis); der Abschnitt erscheint,
    -- sobald ein Eintrag mit geprüftem CurseForge-Link dazukommt.
    page:Companions()

    page:Register()
end

-- Steht „Dämon der Begleiter-Taste“ auf der Seite? Nur für Hexenmeister (ohne bekannte Klasse wie bisher für alle).
function ns.ShowsPetDemon()
    local class = ezCore.PlayerClass and ezCore.PlayerClass()
    return class == nil or class == "WARLOCK"
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
