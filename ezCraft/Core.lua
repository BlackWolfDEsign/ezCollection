local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    ezCraft erweitert Blizzards Berufefenster (Blizzard_Professions, Forever-Fassung mit Camelot-Anpassungen).
    Daten kommen aus ezCore: Bestände aller Twinks (ezCore.Inventory), Rezepte (Item-Wissen),
    Preise (ezCore.Prices), Berufs-Abklingzeiten (ezCore.Professions), Fundorte (ezCore.Gathering),
    Versand (ezCore.MailQueue). ezCraft speichert nur, was dem Spieler gehört: Einkaufsliste,
    angeforderte Sendungen und die offene Ansicht im Berufefenster.

    Dateien:
      Data.lua       Rezept lesen, Bestände zählen, Skill-Farben, fehlende Rezepte (ohne Oberfläche)
      Shopping.lua   Einkaufsliste, Brücke zu ezAuction, Tooltip-Zeile, ns.API
      Tooltip.lua    Rezept und Zutaten im Item-Tooltip (Rezept-Wissen von ezCore, sonst „laut AtlasLoot“)
      Salvage.lua    Entzaubern: Wert im Tooltip, Kandidaten in der Tasche (Daten aus ezCore.Salvage)
      Shipments.lua  Material bei Twinks anfordern und am Briefkasten verschicken
      Panel.lua      Seitenteil mit Pfeil am Berufefenster: Reiter, Ansichten, Knopfleiste
      Book.lua       Knopf „Fundorte“ an den Sammelberufen in Blizzards Berufsbuch (Menü je Rohstoff, Kürschner-Liste)
      Where.lua      Rezepte und ihre Fundorte: „Woher“, „Noch zu lernen“, „Erhältlich bei“ im Tooltip (Welle 15b)
      Filter.lua     Schwierigkeitsfarben, Chance auf einen Fertigkeitspunkt, Farbfilter in Blizzards Filtermenü
      MailTab.lua    Seitenreiter „Sendungen“ am Postfenster
      Alerts.lua     Quellen „Abklingzeit fertig“ und „Material fehlt“ für ezPanels Baustein „Meldungen“
]]

ns.DEFAULTS = {
    panel = true,            -- ezCraft im Berufefenster (Seitenteil mit Pfeil; auf/zu merkt ezCraftDB.window.open)
    bookPanel = true,        -- dasselbe Seitenteil auch auf der Seite „Berufe“ (ohne Rezept und Fehlend; Nr. 22, Welle 23)
    tooltipRecipe = true,    -- Item-Tooltip: Rezept mit Zutaten und Bestand, wofür etwas Zutat ist
    countBank = true,        -- was als „vorhanden“ zählt (Herstellbar, fehlt, Einkaufsliste)
    countMail = true,
    countGuild = false,      -- Gildenbank gehört nicht dir allein: nur anzeigen
    countAlts = true,        -- Twinks, an die Post gehen kann
    costs = true,            -- Materialkosten aus dem Preis-Wissen von ezCore (Auktionspreise)
    costsBeside = false,     -- Kosten, Ergebnis und Gewinn am Rezept auch neben Auctionator zeigen (CRAFT-02)
    tooltipCost = true,      -- Item-Tooltip eines hergestellten Gegenstands: „Material ≈ …, n von m mit Preis“ (AH-32)
    skillStages = true,      -- Stufen der Skill-Farben im Berufefenster (zurückhaltend bei SkillUp Forever, ForeverArtisan)
    missingTab = true,       -- Reiter „Fehlend“: nicht erlernte Rezepte und ihre Quelle
    recipeWhere = true,      -- Fundorte der Rezepte: „Woher“ im Reiter „Rezept“, „Erhältlich bei“ im Tooltip (Welle 15b)
    recipeWaypoint = true,   -- „Auf der Karte zeigen“ setzt auch Blizzards Wegpunkt
    chanceNumber = false,    -- dieselbe Chance als kleine Zahl neben dem Namen
    cooldownTab = true,      -- Reiter „Abklingzeiten“: Berufs-Abklingzeiten aller Twinks (ezCore.Professions)
    -- Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 19 bis 22), ohne Schalter: Material bei ezCore zum
    -- Auffrischen anmelden (AH-39), Abschnitt „Farbe (ezCraft)“ im Filtermenü des Berufefensters, Chance auf einen
    -- Fertigkeitspunkt, Zeile „Einkaufsliste“ im Tooltip von Material. Gespeicherte Werte watchPrices, chanceTip,
    -- tooltipShopping bleiben unbeachtet liegen; colorFilter = false stellt ns.MigrateSettings1911 einmal um.
    gatherHint = true,       -- „hier sammelbar“ und Kartenknopf „Nächste Fundorte“ an fehlendem Material (ezCore.Gathering,
                             -- eigene Ernten zuerst; zur Karte führt ezMap, SAM-24)
    bookButton = true,       -- Knopf „Fundorte“ an den Sammelberufen in Blizzards Berufsbuch (Book.lua, SAM-25)
    tooltipSkin = true,      -- Item-Tooltip: „Leder von: Gegner (Zone) n×“ aus der eigenen Kürschner-Beute (SAM-25)
    mailTab = true,          -- Seitenreiter „Sendungen“ am Postfenster
    tooltipSalvage = true,   -- Item-Tooltip: was Ausrüstung beim Entzaubern ergibt und wert ist (ezCore.Salvage)
    salvageTab = true,       -- Reiter „Entzaubern“: Ausrüstung in der Tasche, die sich entzaubern lässt
    salvageMark = true,      -- Marke „lohnt sich zu entzaubern“ am Taschenplatz (ezCores Platzmarken, CRAFT-10)
}

-- Ein- und Ausschalten per /ezcraft <wort> (Core.HandleToggle); en: das englische Wort (T10-1, englischer Client).
ns.TOGGLES = {
    { "panel", "berufefenster", en = "professions" },   -- „/ezcraft fenster“ klappt das Seitenteil auf und zu
    { "tooltipRecipe", "rezept", en = "recipe" },
    { "mailTab", "post", en = "mail" },
    { "tooltipSalvage", "entzaubern", en = "disenchant" },
}

-- Seitenteil am Berufefenster auf- und zuklappen – ezCrafts Fenster: Linksklick im Addon-Fach, „/ezcraft“ ohne Wort und
-- „/ezcraft fenster“ (Entscheidung 5 vom 18.11.2026). Hauptschalter aus: erst einschalten, dann ist es zu sehen.
-- Ohne offenes Berufefenster gibt es kein Seitenteil zu sehen: dann nur ein Hinweis, ohne den gemerkten Zustand oder
-- den Hauptschalter zu ändern (Gegenprüfung 18.11.2026 – vorher kippte der Klick unsichtbar die gemerkte Wahl).
local function ProfessionsShown()
    local pf = rawget(_G, "ProfessionsFrame")
    return type(pf) == "table" and type(pf.IsShown) == "function" and pf:IsShown() and true or false
end

function ns.TogglePanel()
    if not ProfessionsShown() then
        ns.Print(L.SIDE_NEED_WINDOW)
        return nil
    end
    if not ns.Enabled("panel") then
        ns.SetSetting("panel", true)
        if ns.Panel then ns.Panel.SetOpen(true) end
        ns.Print(L.CMD_ON:format(L.OPT_panel))
        return true
    end
    local open = ns.Panel and ns.Panel.Toggle()
    ns.Print(open and L.SIDE_NOW_OPEN or L.SIDE_NOW_CLOSED)
    return open
end

-- Einstellungs-Prüfung vom 19.11.2026, Nr. 20 (Gegenprüfung): der Schalter „Farbfilter im Filtermenü“ entfiel, der
-- Abschnitt „Farbe (ezCraft)“ wirkt seitdem immer. Wer den Schalter aus hatte, bekäme sonst eine alte Farbwahl samt
-- Blizzards Filter „Fertigkeitsanstieg“ ungefragt zurück. Darum einmal je Speicher (Core.MigrateOnce, Merker
-- settings1911): stand colorFilter auf aus, die gemerkte Farbwahl aller Charaktere vergessen – dann sind alle Farben
-- gewählt (Grundstellung, der Filter tut nichts). → true, wenn umgestellt wurde.
function ns.MigrateSettings1911(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    return Core.MigrateOnce(db, "settings1911", function()
        if db.settings.colorFilter ~= false then return false end
        db.colorFilter, db.settings.colorFilter = nil, nil
        return true
    end)
end

-- Eigene Wörter von /ezcraft; „optionen“, „status“, „hilfe“ und die Schalter aus ns.TOGGLES versteht ezCores Gerüst.
local function SlashExtra(cmd)
    if cmd == "fenster" or cmd == "window" then
        ns.TogglePanel()
        return true
    elseif cmd == "liste" or cmd == "list" then
        if ns.Shopping then ns.Shopping.Print() end
        return true
    elseif cmd == "leeren" or cmd == "clear" then
        -- wie die Knöpfe erst nach Rückfrage (T9-10; vorher sofort – ein Tippfehler leerte die ganze Liste)
        if ns.Shopping then ns.Shopping.AskClear(true) end
        return true
    end
    return false
end

-- Das Gerüst von ezCore (Core.NewModule, Framework.lua) übernimmt Datenbank, Einloggen, /ezcraft und den Status:
--   db/tables   ezCraftDB mit settings (Standardwerte aus ns.DEFAULTS) und den Tabellen
--               hints     gesehene Erklärblasen (Rundgang)
--               shopping  { { id = recipeID, count } }
--               shipments { { from, to, items = { [itemID] = n }, note, created } }
--               window    { tab, open } (offene Ansicht, Seitenteil auf oder zu)
--               salvageIgnore { [itemID] = true } (nie zum Entzaubern vorschlagen)
--               watch     { recent = { recipeID … }, favorites = { [recipeID] = true } } (Material zum Beobachten, AH-39)
--   needs       was ezCraft von ezCore braucht; fehlt etwas, meldet ezCore es einmal statt eines Fehlers im Modul
Core.NewModule(ADDON, ns, {
    title = "ezCraft",
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.ItemIconText, Core.CombatNotice, Core.TipDoubleLine, Core.Tooltip.Gap
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",
    -- scaffoldHelpers: ns.Plain/Num/OtherFor des Gerüsts; Now/Uptime: Zeit über ezCore (Kleinhelfer nach 1.11.0);
    -- NewSidePanel: Seitenteil mit Pfeil (FP-09), Rücksicht-Schlüssel craftCost (W-58) kam mit 1.12.0
    needs = { "AltRecipient", "WhoHandles", "Prices.Get", "SideTabs.Layout", "scaffoldHelpers", "Now", "Uptime",
        "NewSidePanel", "Style.Color", "Style.AllText", "Menu.AllToggle",   -- Style/AllToggle: Design-System (Welle 22)
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More",
        -- Welle 23: Stufenfarben aus ezCore (A1), Abklingzeiten je Gruppe (A6)
        "Gathering.SkillRGB", "Professions.CooldownGroup", "Professions.FEATURES.merged",
        "Gathering.ItemsOf",     -- Rohstoffe je Art samt Kürschnerei 393 in PROFESSION_LINES (A5)
        -- Welle 27 (Zweig modul/ezcraft-menue): Symbole und Abschnitte in den Menüs, ohne neue Versionsnummer in ezCore
        "Menu.Icon", "Menu.IconMarkup", "Menu.IconRoot", "Menu.Section", "Menu.ProfessionIcon",
        -- Gesamtreview 18.11.2026 (T4-NR5): erreichbarer Bestand als eine Regel in ezCore
        "Inventory.Reachable",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2; ezCore ohne neue Versionsnummer)
        "compartmentMain", "slashMain", "CombatNotice", "Toolbar.ShowTipWhileDisabled", "TipLine", "TipDoubleLine",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CombatText",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "PlaySound",
    -- Einstellungs-Prüfung vom 19.11.2026: Einmal-Umstellung des entfallenen Farbfilter-Schalters
    "MigrateOnce" },
    db = "ezCraftDB",
    tables = { "hints", "shopping", "shipments", "window", "salvageIgnore", "watch" },
    onLoad = function(db)
        ns.Shopping.Migrate(db.shopping)   -- vor 1.2 mit Name, Symbol und Zutaten
        ns.MigrateSettings1911(db)
    end,
    login = true,
    -- ohne Wort: Seitenteil auf- und zuklappen wie der Linksklick im Addon-Fach (Entscheidung 5); Hilfe aus ezCore mit
    -- L.CMD_HELP_OWN
    slash = { extra = SlashExtra, main = function() ns.TogglePanel() end, mainText = L.COMPARTMENT_MAIN },
})

-- ns.Plain, ns.Num, ns.OtherFor, ns.Enabled(key), ns.Throttle(fn, delay), ns.WhenAddOnLoaded(addon, fn),
-- ns.AfterCombat(fn, key), ns.AddStatusLine, ns.PrintStatus, ns.HandleSlash und ns.PrintHelp kommen aus
-- Core.NewModule (Abkürzungen des Gerüsts, W-14).

-- Tooltip-Zeilen in den Farbrollen von ezCore (Welle 23, A2; Design-System 2.5 – keine Farbzahlen in AddLine):
-- rolle aus Core.Style.COLOR ("normal" Gold, "highlight" Weiß, "good", "bad" …), dazu "hint" für Quellen und Hinweise
-- in ezCores Grau Core.GREY. D1 hat die Helfer wortgleich nach ezCore gehoben (Core.TipLine, Core.TipDoubleLine);
-- seit der Gegenprüfung zu P13 D2 (18.11.2026, Leitlinie 2) sind ns.TipLine und ns.TipDoubleLine nur noch ihre Namen
-- in ezCraft – die eigene Kopie (RoleRGB, RoleText) ist entfallen.
ns.TipLine = Core.TipLine
ns.TipDoubleLine = Core.TipDoubleLine

-- Zeilen { left, right, color, rightColor } (Tooltip.Lines, Where.TooltipLines, Salvage.Lines) zeichnen; color und
-- rightColor sind Rollen wie oben. Einzelne Zeilen brechen um, Doppelzeilen nicht (wie Blizzards AddDoubleLine).
function ns.TipLines(tooltip, lines)
    if type(tooltip) ~= "table" or type(lines) ~= "table" then return end
    for _, l in ipairs(lines) do
        if l.right ~= nil then
            ns.TipDoubleLine(tooltip, l.left, l.right, l.color, l.rightColor)
        else
            ns.TipLine(tooltip, l.left, l.color, true)
        end
    end
end

-- Was ezCraft anderen Modulen anbietet (ezCore.API("ezCraft")); gefüllt in Shopping.lua.
ns.API = {}

-- Ergänzende Addons (Einstellungen → „Erweitert“, README): keine. Pflicht ist nur ezCore (TOC). Fundorte kommen aus
-- den eigenen Ernten („bei dir“); Gatherer Reforged und GatherMate2 stehen seit Welle 16 (SAM-27) nicht mehr als
-- Ergänzung hier. SkillUp Forever und ForeverArtisan fehlen bewusst: dort hält ezCraft sich nur zurück.

-- Ein Twink wird vergessen (/ez vergessen): seine Sendungen sind dann gegenstandslos.
Core.Listen("CHAR_FORGOTTEN", function(key)
    if not (ns.db and key) then return end
    for i = #ns.db.shipments, 1, -1 do
        local s = ns.db.shipments[i]
        if s.from == key or s.to == key then table.remove(ns.db.shipments, i) end
    end
    ns.Fire("SHIPMENTS_CHANGED")
end, ADDON)

---------------------------------------------------------------------------
-- Status (/ezcraft status, Einstellungen → „Erweitert“ → „Status“): Kopfzeile und Ausgabe macht ezCores Gerüst
---------------------------------------------------------------------------

ns.AddStatusLine(function()
    return L.STATUS_SHOPPING:format(#(ns.db and ns.db.shopping or {}))
end)
ns.AddStatusLine(function()
    local mine, incoming = 0, 0
    if ns.Shipments then mine, incoming = ns.Shipments.Counts() end
    return L.STATUS_SHIPMENTS:format(mine, incoming)
end)
ns.AddStatusLine(function()
    local Data, lines = ns.Data, {}
    if not Data then return nil end
    if Data.HasCooldowns() then
        -- geteilte Abklingzeiten zählen einmal (ezCores Gruppe, Welle 23 A6)
        local running, ready = #Data.Cooldowns(false, true), #Data.ReadyCooldownsMerged()
        lines[#lines + 1] = ready > 0 and L.STATUS_COOLDOWNS_READY:format(running, ready) or L.STATUS_COOLDOWNS:format(running)
    end
    if Data.HasGathering() then
        -- woher die Fundorte kommen („bei dir“ zuerst) bzw. dass es noch keine eigenen Ernten gibt (SAM-24)
        lines[#lines + 1] = Data.GatherSourcesText()
    end
    local other = Data.SkillStagesOther()
    if other then lines[#lines + 1] = L.STATUS_STAGES_OTHER:format(other) end
    -- Nur bei eingeschalteten „Materialkosten“: sonst zeigt der Reiter „Rezept“ ohnehin keine Kosten (CostRows).
    local costOther = ns.Enabled("costs") and Data.CraftCostOther(true)
    if costOther then
        lines[#lines + 1] = (ns.Enabled("costsBeside") and L.STATUS_COSTS_BESIDE or L.STATUS_COSTS_OTHER):format(costOther)
    end
    -- AH-39: wie viel Material ezCraft bei ezCore zum Auffrischen angemeldet hat
    if Core.Prices and type(Core.Prices.AddWatchProvider) == "function" then
        lines[#lines + 1] = L.STATUS_WATCH:format(#Data.WatchItems())
    end
    local waiting = Data.WaitingLines()
    for _, line in ipairs(waiting) do lines[#lines + 1] = line end
    if #waiting == 0 then lines[#lines + 1] = L.STATUS_ALL_THERE end
    return lines
end)

---------------------------------------------------------------------------
-- Addon-Knopf
---------------------------------------------------------------------------

-- Blizzards Addon-Fach an der Minikarte (TOC: AddonCompartmentFunc …), gebaut von ezCore. Entscheidung 5 vom 18.11.2026
-- (T18-3, T16-10): Linksklick klappt das Seitenteil auf und zu, Rechtsklick öffnet die Einstellungen; Tooltip und
-- Befehlszeile baut ezCore.
ezCraft_OnAddonCompartmentClick, ezCraft_OnAddonCompartmentEnter, ezCraft_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({
        ns = ns,
        owner = ADDON,
        title = L.TITLE,
        main = function() ns.TogglePanel() end,
        mainText = L.COMPARTMENT_MAIN,
    })
