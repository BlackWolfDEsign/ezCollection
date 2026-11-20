local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezBuff (Seite von ezCore):
-- Allgemein (Knopf zeigen, Knopf an/aus, Taste) → Essen und Fläschchen (mit Waffenverzauberung) → Klassen-Buffs (mit
-- der eigenen Wahl je Wahlgruppe) → Gruppe (Symbol, Zeichen, Gruppenfassung, Durchbuffen, Segen je Klasse für
-- Paladine) → Zurückgeben →
-- Melden (Chat, ezPanels Leiste) → Profile →
-- Erweitert (Status, Segen je Spieler, Einzelwahlen löschen, Einstellungen zurücksetzen, Erklärung erneut zeigen,
-- ergänzende Addons).
local page

local function Minutes(value)
    if value == 0 then return L.OFF end
    return ezCore.Minutes(value)
end

-- „Segen für <Klasse>“ (Paladin): Auswahlfeld auf die Wahl je Klasse (Group.BlessingValue/SetBlessingValue,
-- gespeichert je Charakter – deshalb eine Proxy-Einstellung statt ns.S; „Einstellungen zurücksetzen“ lässt sie
-- stehen). Die Einträge liest Blizzard bei jedem Öffnen neu (gelernte Segen). Nur für Paladine sichtbar.
-- Über ezCores page:ProxyDropdown (EC-114, BF-06); vorher baute ezBuff das Feld mit Blizzards API selbst.
-- Name der Einstellung wie bisher: <prefix>blessingClass_<Klasse>.
local function BlessingDropdown(class)
    local name = ezCore.ClassName(class) or class
    return page:ProxyDropdown("blessingClass", ns.Group.BlessingChoices,
        function() return ns.Group.BlessingValue(class) end,
        function(value) ns.Group.SetBlessingValue(class, value) end,
        { id = class, format = name, default = ns.Group.AUTO, shown = ns.Group.BlessingSettingsShown })
end

-- „Eigene Wahl: Segen | Rüstung | Schild“ (EC-39, ST-10; Leitlinie 3): je Wahlgruppe der eigenen Klasse ein
-- Auswahlfeld „Automatisch (Vorschlag: …)“ oder ein bestimmter Buff. Dieselbe gemerkte Wahl wie beim Wirken und im
-- Rechtsklick-Menü des Knopfs (Check.Prefer/SetPrefer, je Charakter); nur sichtbar, wenn deine Klasse die Gruppe hat.
-- Eine Gruppe mit eigenem Tooltip (OPT_prefer_<id>_TIP, etwa „imbue“: wirkt nur am Knopf) nimmt diesen statt OPT_prefer_TIP.
local function PreferDropdown(id)
    local tipKey = "OPT_prefer_" .. id .. "_TIP"
    local tip = L[tipKey] ~= tipKey and L[tipKey] or nil
    local function Values()
        local list = { { ns.Group.AUTO, ns.Check.AutoText(id) } }
        for _, choice in ipairs(ns.Check.Choices(id)) do list[#list + 1] = { choice.key, choice.name } end
        return list
    end
    return page:ProxyDropdown("prefer", Values,
        function() return ns.Check.Prefer(id) or ns.Group.AUTO end,
        function(value)
            if value == ns.Group.AUTO or value == "" then value = nil end
            ns.Check.SetPrefer(id, value)
        end,
        { id = id, format = ns.Check.KindName(id), default = ns.Group.AUTO, tooltip = tip,
          shown = function() return ns.Check.ChoiceGroup(id) ~= nil end })
end

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    page:Button(L.OPT_PREVIEW, L.OPT_PREVIEW_BUTTON, function() ns.Preview() end, L.OPT_PREVIEW_TIP)
    page:Checkbox("button")
    -- Taste für den Knopf (ezCores Tasten-Dienst, Eintrag „ezBuff: fehlenden Buff wirken“; Leitlinie 3)
    page:Button(L.OPT_BUTTON_KEY, L.OPT_BUTTON_KEY_BUTTON, function() ns.Button.OpenKeyBindings() end,
        function() return L.OPT_BUTTON_KEY_TIP .. "\n\n" .. ns.Button.KeyLine() end)

    page:Header(L.OPT_HEADER_CONSUMABLES)
    page:Checkbox("food")
    page:Checkbox("flask")
    page:Checkbox("weapon")
    local when = {}
    for _, value in ipairs(ns.CHOICES.when) do when[#when + 1] = { value, L["WHEN_" .. value] } end
    page:Dropdown("when", when)
    page:Checkbox("campfire")

    page:Header(L.OPT_HEADER_CLASS)
    page:Checkbox("selfBuffs")
    -- lange Selbst-Buffs (Buffs.LONG_SELF, T14-2): je Buff ein Schalter, nur für die Klasse, die ihn hat
    for _, info in ipairs(ns.Buffs.LONG_SELF) do
        local key = info.key
        -- eingerückt unter „selfBuffs“, aber nie grau: die eigene Rahmenzeile und „Durchbuffen“ (Check.MemberNeeds, own)
        -- nutzen sie auch mit groupFrames allein, und Blizzard wertet ein Prädikat nur bei Änderung der Oberzeile neu
        -- aus (code-reviewer 20.11.2026; Querschnitt „Unterschalter ausgrauen“)
        page:Checkbox(info.setting, nil, { parent = "selfBuffs", enabledWhen = function() return true end,
            shown = function() return ns.Buffs.LongSelfOf(key, ns.playerClass) end })
    end
    page:Checkbox("groupBuffs")
    page:Checkbox("otherBuffs")
    page:Checkbox("missingGlow")
    page:Slider("minLeft", ns.LIMITS.minLeft[1], ns.LIMITS.minLeft[2], 1, Minutes)
    for _, id in ipairs(ns.Check.CHOICE_KINDS) do PreferDropdown(id) end

    page:Header(L.OPT_HEADER_GROUP, L.OPT_HEADER_GROUP_TIP)
    page:Checkbox("groupFrames")
    page:Checkbox("groupSigns")
    -- Nur der Regler, ganz links „Aus“ (Einstellungs-Prüfung 19.11.2026, Nr. 75)
    page:Slider("groupMin", ns.LIMITS.groupMin[1], ns.LIMITS.groupMin[2], 1,
        function(value) return value <= ns.GROUP_MIN_OFF and L.GROUP_MIN_OFF or L.UNIT_MEMBERS:format(value) end)
    -- Vorlage „Durchbuffen“ je Klasse (Wunsch des Nutzers vom 15.11.2026, Macro.lua): Makro in Blizzards Verwaltung
    page:Button(L.OPT_MACRO, L.OPT_MACRO_BUTTON, function() ns.Macro.Create() end, function() return ns.Macro.Tip() end)
    page:Button(L.OPT_GROUP_KEY, L.OPT_GROUP_KEY_BUTTON, function() ns.Group.OpenKeyBindings() end, L.OPT_GROUP_KEY_TIP)
    for _, class in ipairs(ezCore.CLASSES) do BlessingDropdown(class) end

    page:Header(L.OPT_HEADER_REBUFF)
    page:Checkbox("rebuff")
    page:Checkbox("thank", nil, { parent = "rebuff" })   -- Dank nur nach eigenem Nachbuffen (Core.lua, Rebuff.lua) (Querschnitt „Unterschalter ausgrauen“, Einstellungs-Prüfung 19.11.2026)

    page:Header(L.OPT_HEADER_REPORT)
    page:Checkbox("report")
    page:Button(L.OPT_REPORT_NOW, L.OPT_REPORT_NOW_BUTTON, function() ns.PrintMissing(true) end, L.OPT_REPORT_NOW_TIP)
    -- Meldungen bei ezPanel: nur noch über ezPanels Menü „Quellen“ (Nr. 76)

    -- Profile je Klasse (Profiles.lua, Welle 23): Auswahl, „für die Klasse“, je Spezialisierung, Neu, Export,
    -- Import, Löschen – den Abschnitt baut ezCore (page:Profiles); eigenes Thema direkt vor „Erweitert“
    -- (design-system 2.10, Gesamtreview T9-5; vorher unter „Erweitert“)
    if ns.Profiles and ns.Profiles.P and page.Profiles then
        ns.Profiles.section = page:Profiles(ns.Profiles.P, { texts = L })
    end

    page:Advanced()
    page:StatusButton(L.OPT_STATUS_TIP)   -- Beschriftung von ezCore (Gesamtreview T9-2)
    -- Segen je Spieler (Einzelwahlen aus dem Rechtsklick-Menü): der Tooltip zeigt die Liste (Blizzards
    -- Settings.InitTooltip nimmt auch eine Funktion, Forever-Quelle Blizzard_Settings_Shared/Blizzard_Settings.lua),
    -- der Knopf schreibt sie in den Chat.
    page:Button(L.OPT_PLAYER_BLESSINGS, L.OPT_PLAYER_BLESSINGS_BUTTON, function() ns.Group.PrintPlayerBlessings() end,
        function() return ns.Group.PlayerBlessingsTip() end)
    -- Knopf mit Blizzards DELETE (Gesamtreview T18-22) über Core.Word – den Rückfall hält ezCore
    page:Button(L.OPT_CLEAR_PLAYERS, ezCore.Word("DELETE"), function() ns.Group.ClearPlayerBlessings() end,
        L.OPT_CLEAR_PLAYERS_TIP)
    page:ResetButton()   -- „Einstellungen zurücksetzen“ (ezCore); gemerkte Tränke und Segen bleiben
    page:TourButton(ns.Button.Tour())   -- Erklärblasen am Knopf erneut zeigen
    page:Companions()    -- ergänzende Addons mit CurseForge-Link

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
