local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    ezGear – bessere Ausrüstung erkennen, Itemlevel an den Plätzen, Sets und automatisches Umziehen.

      Stats.lua      Werte eines Gegenstands (C_Item.GetItemStats, ergänzt um das Item-Wissen von ezCore)
      Level.lua      Gewichte für die Stufe, Rüstung aus der Formel des Clients, eigene Rüstungsart, Wirkung auf den Spieler
      Weights.lua    Gewichtung: Standard je Klasse und Rolle (Talentbaum), eingefügte Pawn-Skalen
      Score.lua      die EINE Bewertung „besser“ (auch für ezQuest und ezLoot, siehe ns.API)
      Marks.lua      grüner Pfeil und Gold-Symbol auf beliebigen Knöpfen (Blizzards Atlanten)
      Bags.lua       Pfeil an den Taschenplätzen (über ezCores Platzmarken, mit ezBag dort)
      Quest.lua      Pfeil und Gold-Symbol in der Questbelohnung
      Trade.lua      Pfeil im Handelsfenster zwischen zwei Spielern
      Alts.lua       bringt ein Gegenstand einem Twink etwas? (Zeile im Tooltip)
      Tooltip.lua    Zeile „+12 % für Verstärkung“, Vergleich am Rezept-Ergebnis
      Character.lua  Itemlevel je Platz am Charakterfenster und beim Betrachten
      GroupCheck.lua Ausrüstungs-Check der Gruppe: Bewertung je Mitglied (über ezCores Betrachten-Dienst)
      GroupPanel.lua Seitenteil „Ausrüstungs-Check“ am Reiter „Schlachtzug“
      Sets.lua       Knopf „Sets“ am Charakterfenster (Blizzards Ausrüstungsmanager)
      Swap.lua       automatisch umziehen beim Reiten und Angeln
      Profiles.lua   Profile je Charakter, Klasse oder Spezialisierung (ezCore.NewProfiles)
      Tour.lua       Erklärblasen beim ersten Öffnen des Charakterfensters (ezCore.NewTour)
      Options.lua    Einstellungsseite

    Von ezCore (Welle 2): Gerüst (Datenbank, Login, /ezgear und /ezg, Status, ns.AfterCombat), Core.OpenPanel für
    Blizzards Charakterfenster, Core.EquipSlots für die Ausrüstungsplätze.

    Grenze: Ausrüsten ist im Kampf gesperrt – ezGear schlägt vor und legt nur außerhalb des Kampfes an.
    Taint-sicher: nur hooksecurefunc/HookScript, eigene Texturen und Schriften, nie Werte in Blizzards Tabellen.
]]

ns.DEFAULTS = {
    -- Pfeil „besser“
    bagArrows = true,       -- Taschenplätze und Handelsfenster (Trade.lua)
    questArrows = true,     -- Questbelohnung
    questCoin = true,       -- Gold-Symbol auf der Belohnung mit dem höchsten Verkaufswert
    minPercent = 1,         -- ab so viel Prozent besser gilt ein Gegenstand als „besser“
    downArrows = true,      -- roter Pfeil nach unten auf tragbaren Teilen, die schlechter sind (Tasche, Quest, Handel, Beute)
    -- „besseres Teil in der Tasche“ bei ezPanels Meldungen: kein eigener Schalter mehr, ezPanels Auswahl der
    -- Meldungsquellen ist die eine Stelle (Einstellungs-Prüfung 19.11.2026, Nr. 77)

    -- Tooltip: die Vergleichszeile „+12 % für Verstärkung“, auch „−8 %“ in Rot, ist fest (Nr. 41, 42; Rücksicht auf
    -- Pawn bleibt über ns.FOREIGN)
    tooltipEffect = true,   -- Zeile „Für dich“: was der Tausch an Gesundheit und Nahkampfschaden ausmacht (Score.EffectText, 25.11.2026)
    tooltipAlts = true,     -- Zeile „Für Twinks“: wem ein weiterzugebender Gegenstand etwas bringt (Alts.lua, 24.11.2026)
    recipeCompare = true,   -- Rezept-Ergebnis mit der angelegten Ausrüstung vergleichen

    -- Charakterfenster (Haltbarkeit je Platz, sobald beschädigt: fest, Nr. 43)
    charLevels = true,      -- Itemlevel je Platz
    charEnchant = true,     -- Zeichen „Verzauberung fehlt“ an verzauberbaren Plätzen (W-38, Frage 24)
    inspectLevels = true,   -- beim Betrachten, dazu der Durchschnitt
    setsButton = true,      -- Knopf „Sets“ am Charakterfenster
    chatButton = true,      -- Knopf „Chat“ am Charakterfenster: angelegte Ausrüstung als Links in den eigenen Chat

    -- Ausrüstungs-Check der Gruppe (Seitenteil am Reiter „Schlachtzug“; liest nur nach Klick, Gesamtreview I3)
    groupCheck = true,

    -- Automatisch umziehen (die Sets wählt jeder Charakter selbst)
    swapMount = true,
    swapFishing = true,
    fishIdle = 120,         -- Sekunden ohne Angeln, dann zurück
}

-- Seit der letzten Veröffentlichung neu und ab Werk an: die Blase „Neu seit dem Update“ nennt sie (ezCore, ConsentNews.lua)
ns.NEWS = { "tooltipAlts", "tooltipEffect" }

-- Einstellungs-Prüfung vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“): fest statt Schalter. Ihr alter
-- Wert gilt nicht mehr; die Schlüssel fliegen einmal aus Einstellungen und Profilen (ns.MigrateSettings1911).
ns.ALWAYS = { tooltip = true, tooltipWorse = true, charDurability = true, panelUpgrade = true }
ns.REMOVED_SETTINGS = { "tooltip", "tooltipWorse", "charDurability", "panelUpgrade" }

function ns.MigrateSettings1911(db)
    return Core.MigrateOnce(db, "settings1911", function()
        local function Strip(settings)
            if type(settings) ~= "table" then return end
            for _, key in ipairs(ns.REMOVED_SETTINGS) do settings[key] = nil end
        end
        Strip(db.settings)
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            Strip(type(profile) == "table" and profile.settings or nil)
        end
        return true
    end)
end

-- Eigene Befehle; „optionen“, „status“, „hilfe“ und die Schalter aus ns.TOGGLES versteht ezCores Gerüst.
local function SlashExtra(cmd, rest)
    rest = rest or ""
    if cmd == "gewichtung" or cmd == "skala" or cmd == "scale" or cmd == "weights" then
        ns.OpenWeightMenu(UIParent)
    elseif cmd == "pawn" then
        if rest ~= "" then ns.ImportPawnScale(rest) else ns.AskPawnScale() end
    elseif cmd == "set" then
        if rest ~= "" then ns.EquipSetByName(rest) else ns.OpenSetsMenu(UIParent) end
    elseif cmd == "angeln" or cmd == "fish" or cmd == "fishing" then
        ns.ToggleFishing()
    elseif cmd == "test" or cmd == "vergleich" or cmd == "compare" then
        ns.PrintCompare(rest)
    elseif cmd == "ausrüstung" or cmd == "ausruestung" or cmd == "gear" or cmd == "equipped" then
        ns.PrintEquipped()
    elseif cmd == "profil" or cmd == "profile" or cmd == "profiles" then
        ns.SwitchProfileByName(rest)
    else
        return false
    end
    return true
end

-- Gerüst von ezCore (Core.ModuleScaffold): Datenbank mit Standardwerten, Login (ns.charKey, ns.RunReady),
-- Befehl /ezgear mit Kurzbefehl /ezg (nur, wenn er frei ist), Status (ns.AddStatusLine, ns.PrintStatus) und
-- „nach dem Kampf“ (ns.AfterCombat). Speicher: Einstellungen und Pawn-Skalen für alle, Gewichtung und Sets je Charakter.
--   scales  [Name] = { class = "ROGUE", weights = { … } }
--   chars   [charKey] = { scale, mountSet, fishSet, swap, last = { key, weights, auto } (zuletzt geltende Gewichtung; Alts.lua) }
--   hints   gesehene Erklärblasen (Tour.lua)
--   ui      Zustand der Oberfläche (groupOpen: Seitenteil „Ausrüstungs-Check“ offen; GroupPanel.lua)
Core.NewModule(ADDON, ns, {
    title = "ezGear",
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.Inspect, Core.PlainCall, Core.CleanImportName, Core.CombatNotice
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0", needs = { "AfterCombat", "OpenPanel", "EquipSlots", "scaffoldHelpers", "Uptime", "Spells.FISHING",
        "EquipSlots.ButtonName", "SlotText.AverageLevel", "Menu.Tip", "SlotMarks.Add", "Style.IconSize",
        -- Einstellungs-Prüfung 19.11.2026: gespeicherte Werte einmal umstellen (Core.MigrateOnce)
        "MigrateOnce",
        -- Profile vergessen den Charakter selbst (P.Forget bei CHAR_FORGOTTEN): ezCore Welle 23a, ohne neue Nummer
        -- nach 1.13.0 – laut docs/ezcore.md gehört es zur Fähigkeit ApplySetting
        "ApplySetting",
        -- Ausrüstungs-Check der Gruppe (Gesamtreview 18.11.2026, I3): ezCores Betrachten-Dienst und Seitenteil, ohne neue
        -- Nummer
        "Inspect.NewQueue", "Inspect.GroupUnits", "NewSidePanel", "Style.SetTextColor", "UnitIs",
        "ClassOfGUID", "PlainCall", "EquipSlots.IsTwoHand",
        -- Paket ezgear/talent-empfehlung (ohne neue Nummer): Waffenart eines Gegenstands
        "ItemWeaponKind",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2): Addon-Fach und Befehl ohne Wort nach Entscheidung 5,
        -- Hilfe aus ezCore, Kampfsperre, Wege zu Einstellungen und Menüeintrag aus ezCore
        "compartmentMain", "slashMain", "CombatNotice", "SettingsPathText", "Menu.Settings",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CombatText", "Word",
        -- „Für Twinks“ (Alts.lua, 24.11.2026; ohne neue Nummer)
        "More", "CharacterList", "GearOf", "AltRecipient", "CharName", "ItemID", "Prices.TooltipBound", "Knowledge.VariantKey",
        -- Rolle aus dem Talentbaum (24.11.2026; ohne neue Nummer)
        "Talents.MainTree", "Talents.TreeName", "Talents.Role",
        -- Bewertung für die Stufe und Rüstungsart (Level.lua, 25.11.2026; ohne neue Nummer)
        "ClientData.Expected", "Spells.FormActive", "ItemClassName", "Decimal", "Round" },
    db = "ezGearDB", tables = { "scales", "chars", "hints", "ui" },
    onLoad = function(db) ns.MigrateSettings1911(db) end,
    login = true,
    -- Kurzbefehl /ezg aus Core.SLASH_ALIASES (eine Liste, T18-14); main: „/ezgear“ ohne Wort wählt wie der Linksklick im
    -- Addon-Fach die Gewichtung (Entscheidung 5); reset: „zuruecksetzen“ fragt wie der Knopf (T18-20)
    slash = { extra = SlashExtra, main = function() ns.OpenWeightMenu(UIParent) end, mainText = L.MAIN_TEXT, reset = true },
})

-- ns.IsSecret, ns.Plain, ns.Num, ns.InCombat, ns.OtherFor, ns.Enabled, ns.Throttle und ns.WhenAddOnLoaded gibt
-- Core.NewModule (Abkürzungen des Gerüsts, W-14). Aufruf nur, wenn die Funktion existiert; Fehler fallen still auf
-- nil (ezCore.Call, eine Stelle für alle Module).
ns.Call = Core.Call

-- Tooltip an einem Menüeintrag (Gewichtung, Sets, Umziehen; GEAR-15) über ezCores Core.Menu.Tip (in needs geprüft;
-- fehlt es dennoch, bleibt der Eintrag ohne Tooltip). → der Eintrag
function ns.MenuTip(entry, title, text)
    local menu = Core.Menu
    if not (entry and menu and type(menu.Tip) == "function") then return entry end
    return menu.Tip(entry, title, text)
end

---------------------------------------------------------------------------
-- Rücksicht auf fremde Addons (Liste: docs/fremd-addons.md). Läuft Pawn mit seinen Pfeilen bzw. Tooltip-Werten,
-- hält sich ezGear dort zurück; läuft Outfitter, zieht ezGear nicht selbst um. Erkannt nur über ezCore
-- (ns.OtherFor aus dem Gerüst, also Core.WhoHandles; Pawns Schalter einzeln), damit /ez status und ezGear dasselbe sagen.
---------------------------------------------------------------------------

-- ezGear-Schalter → Funktion in ezCores Liste fremder Addons (Core.OTHER_ADDONS)
ns.FOREIGN = {
    bagArrows = "bagArrows",
    questArrows = "questArrows",
    questCoin = "questArrows",      -- Pawns Quest-Pfeile zeigen auch die wertvollste Belohnung
    panelUpgrade = "bagArrows",     -- zeigt Pawn die Taschen-Pfeile, meldet ezGear auch der Leiste kein „besser“
    tooltip = "upgradeTooltip",
    swapMount = "gearSwap",
    swapFishing = "gearSwap",
    charLevels = "slotLevels",      -- Itemlevel an den Plätzen des Charakterfensters (Winter Essentials; W-38, VP-47)
    charEnchant = "slotLevels",     -- dasselbe Addon zeigt dort auch die Verzauberung
}

-- Erklärung eines Schalters für die Einstellungsseite: hält sich ezGear gerade zurück, nennt sie das Addon, das
-- übernimmt (Leitlinie 9 – sonst wüsste niemand, warum der Schalter nichts tut).
function ns.OptionTip(key)
    local tip = L["OPT_" .. key .. "_TIP"]
    local other = ns.HeldBackBy(key)
    if other then tip = tip .. "\n\n" .. L.OPT_HELD_BY:format(other) end
    return tip
end

-- Name des fremden Addons, das diese Funktion gerade übernimmt (oder nil), dazu sein Schlüssel in ezCores Liste
function ns.HeldBackBy(key)
    local feature = ns.FOREIGN[key]
    if not feature then return nil end
    local label, other = ns.OtherFor(feature)
    if not label then return nil end
    return label, other
end

-- Schalter an (oder fest, ns.ALWAYS) und kein fremdes Addon übernimmt die Funktion
function ns.Active(key)
    return (ns.ALWAYS[key] or ns.Enabled(key)) and ns.HeldBackBy(key) == nil
end

---------------------------------------------------------------------------
-- Datenbank (angelegt vom Gerüst, siehe Core.NewModule oben)
---------------------------------------------------------------------------

-- Eintrag des aktuellen Charakters (erst nach PLAYER_LOGIN sinnvoll).
function ns.Char()
    local db = ns.db
    if not db then return {} end
    local key = ns.charKey or "?"
    local c = db.chars[key]
    if type(c) ~= "table" then
        c = {}
        db.chars[key] = c
    end
    return c
end

-- Erster Schritt beim Einloggen (das Gerüst hat ns.charKey gesetzt und ruft ns.RunReady): die Klasse, danach
-- einmal je Sitzung sagen, wo sich ezGear zurückhält. Steht vor allen anderen ns.OnReady der Dateien dahinter.
ns.OnReady(function()
    ns.playerClass = Core.PlayerClass()
    local seen = {}
    for key in pairs(ns.FOREIGN) do
        local label, other = ns.HeldBackBy(key)
        if label and ns.Enabled(key) and not seen[label] then
            seen[label] = true
            local hint = "HINT_" .. tostring(other or label):upper()
            ns.Print(L[hint] ~= hint and L[hint] or L.HINT_OTHER:format(label))
        end
    end
end)

-- Vergessene Twinks auch hier entfernen.
Core.Listen("CHAR_FORGOTTEN", function(key)
    if ns.db and key then ns.db.chars[key] = nil end
    if ns.Alts then ns.Alts.Reset() end
end, ADDON)

---------------------------------------------------------------------------
-- Alles neu bewerten: Gewichtung, Ausrüstung oder Stufe haben sich geändert.
-- Gesammelt (viele Ereignisse in einem Bild → eine Neuberechnung); andere Module hören auf
-- ezCore.Listen("GEAR_SCORES_CHANGED", fn) und fragen danach ezCore.API("ezGear") neu.
---------------------------------------------------------------------------

local function Broadcast()
    ns.Fire("SCORES_CHANGED")
    Core.Fire("GEAR_SCORES_CHANGED")
end
local throttledBroadcast

function ns.Changed()
    if ns.ClearScoreCache then ns.ClearScoreCache() end
    throttledBroadcast = throttledBroadcast or ns.Throttle(Broadcast, 0.2)
    throttledBroadcast()
end

-- ezTalent hat eine andere Verteilung für dich (Talente, Fragebogen; ezTalent/Gear.lua): Gewichtung neu
Core.Listen("EZTALENT_GEAR_CHANGED", function()
    if ns.Weights then ns.Weights.ForgetTalent() end
    ns.Changed()
end, "ezGear")

-- Talentbaum gelesen oder geändert (ezCore.Talents, nur bestätigte Punkte): „Automatisch“ folgt ihm
Core.Listen("TALENTS_CHANGED", function() ns.Changed() end, "ezGear")

-- Neue Waffen- bzw. Rüstungsfertigkeit gelernt (ezCore.Proficiency): gelbe Pfeile werden grün
Core.Listen("PROFICIENCY_CHANGED", function() ns.Changed() end, "ezGear")

ns.OnReady(function()
    -- PLAYER_LEVEL_CHANGED: dann liefert UnitLevel schon die neue Stufe (die Gewichte hängen seit dem 25.11.2026 an ihr)
    for _, event in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
        "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED" }) do
        ns.On(event, function() ns.Changed() end)
    end
end)

-- Nach dem Kampf: Ausrüsten ist im Kampf gesperrt. ns.AfterCombat(fn, key) kommt von ezCore (Core.AfterCombat,
-- eine Reihe für alle Module; derselbe Schlüssel ersetzt den wartenden Auftrag). Ob ein Auftrag wartet, sagt
-- Core.AfterCombatWaiting("ezGear:<key>") – die eigene Hülle ns.PendingAfterCombat ist entfallen (Entscheidung C).

---------------------------------------------------------------------------
-- Status (/ezgear status und Knopf unter „Erweitert“): ns.AddStatusLine, ns.StatusLines und ns.PrintStatus
-- kommen vom Gerüst; die Kopfzeile ist ns.StatusHeader().
---------------------------------------------------------------------------

ns.AddStatusLine(function()
    local held = {}
    for key in pairs(ns.FOREIGN) do
        local other = ns.Enabled(key) and ns.HeldBackBy(key)
        if other then held[#held + 1] = ("%s (%s)"):format(L["OPT_" .. key], other) end
    end
    if #held == 0 then return nil end
    table.sort(held)
    return L.STATUS_HELD_BACK:format(table.concat(held, ", "))
end)

---------------------------------------------------------------------------
-- Slash-Befehle (zusätzlich zu den Knöpfen): /ezgear und /ezg meldet das Gerüst an (ns.HandleSlash, ns.PrintHelp
-- aus Core.HelpLines mit L.CMD_HELP_OWN); die eigenen Wörter stehen oben in SlashExtra.
---------------------------------------------------------------------------

-- Schalter für /ezgear <Wort> (Core.HandleToggle); en: das englische Wort für den englischen Client (T10-1)
ns.TOGGLES = {
    { "bagArrows", "taschen", en = "bags" }, { "downArrows", "rot", en = "red" }, { "questArrows", "quest", en = "quest" },
    { "questCoin", "gold", en = "gold" },
    { "charLevels", "itemlevel", en = "itemlevel" },
    { "charEnchant", "verzauberung", en = "enchant" },
    { "setsButton", "sets", en = "sets" },
    { "swapMount", "reiten", en = "riding" },
}

-- Weg zu einer Einstellung auf ezGears Seite (Core.SettingsPathText, T18-18): Abschnitt und Option als Schlüssel
function ns.PathText(section, option)
    return Core.SettingsPathText(ADDON, section, option, L)
end

---------------------------------------------------------------------------
-- Addon-Knopf an der Minikarte nach Entscheidung 5 vom 18.11.2026 (Gesamtreview T18-3, T16-10): Linksklick wählt die
-- Gewichtung (vorher Rechtsklick), Rechtsklick öffnet die Einstellungen; Tooltip und Befehlszeile von ezCore
---------------------------------------------------------------------------

ezGear_OnAddonCompartmentClick, ezGear_OnAddonCompartmentEnter, ezGear_OnAddonCompartmentLeave = Core.CompartmentHandlers({
    ns = ns, title = L.TITLE, main = function() ns.OpenWeightMenu(UIParent) end, mainText = L.MAIN_TEXT,
})
