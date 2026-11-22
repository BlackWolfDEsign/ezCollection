local ADDON, ns = ...
local L = ns.L

--[[
    ezLoot – Plündern wie im Original, nur schneller.
      FastLoot.lua  schneller plündern (Rücksicht auf Leatrix Plus)
      History.lua   Beute-Verlauf: zeigt an, was ezCore erfasst (ezCore.History „loot“)
      Frames.lua    Blizzards Plündern- und Würfelfenster: Itemlevel, „BoE“, Pfeil „besser“ (zeichnet ezGear),
                    Knopf am Plündernfenster, Blizzards Würfelergebnisse
      Drops.lua     Beute im Tooltip von Gegnern und NPCs: mögliche Beute aus ezCores Quellen (Core.Sources.LootOf)
                    über dem selbst Gezählten (ezCores Entdecker-Datenbank bzw. Verlauf, je NPC zusammengefasst)
      ItemLoot.lua  Beute bei dir im Tooltip von Gegenständen: von welchen Gegnern du ihn geplündert hast
      Tour.lua      Rundgang mit Erklärblasen (ezCore.NewTour) beim ersten Plündernfenster und Beute-Verlauf
      Options.lua   Einstellungsseite unter ezCollection → ezLoot
    Kein eigenes Fenster: Blizzards Fenster bekommen nur eigene Teile, die an ihnen hängen. Das Plündernfenster
    gehört zum Bearbeitungsmodus – ezLoot verschiebt, skaliert und meldet es nirgends an.
    Den Beute-Verlauf erfasst ezCore (ezCore.History); ezLoot zeigt ihn nur an.
]]

ns.DEFAULTS = {
    fastLoot = true,    -- schneller plündern, wenn das Spiel automatisch plündert
    -- itemLevel und bind (Itemlevel und „BoE“ im Plündern- und Würfelfenster) sind seit der Einstellungs-Prüfung vom
    -- 19.11.2026 gemeinsame Schalter mit ezBag in ezCore (ns.SHARED unten)
    upgrade = true,     -- Blizzards grüner Pfeil, wenn ezGear den Gegenstand besser findet
    npcLoot = true,     -- Beute im Tooltip von Gegnern und NPCs (aus dem Beute-Verlauf)
    -- (Beute-Verlauf an die Würfelergebnisse andocken, dockHistory: seit der Einstellungs-Prüfung vom 19.11.2026 immer –
    -- Wegziehen löst ihn schon, History.lua)
    npcLootHint = true, -- „noch nicht geplündert“ im Tooltip angreifbarer Gegner statt gar keiner Zeile
    itemLoot = true,    -- „Beute bei dir: n× von <Gegner>“ im Tooltip von Gegenständen (LOOT-13, Entscheidungsfrage 7)
    itemOrigin = true,  -- „Herkunft laut Questie: fällt von …“ an Nicht-Rohstoffen ohne eigene Beute (Welle 23, Nr. 24)
    itemContents = true, -- „Inhalt bei dir: n× geöffnet“ im Tooltip geöffneter Behälter (Contents.lua, 22.11.2026)
    npcWorth = true,    -- „Wert je Tötung: … (aus deiner Beute, n Tötungen)“ im Gegner-Tooltip (V2, Welle 24)
    npcSkin = true,     -- „Kürschnern: ab …“ im Gegner-Tooltip, Wert und Quelle aus ezCore (Welle 27, F4 b)
}

-- Slash-Schalter: /ezloot schnell, /ezloot itemlevel … – das englische Wort steht im Feld en (T10-1: „/ezl fast“
-- auch im englischen Client, wie es die englische Hilfe nennt)
ns.TOGGLES = {
    { "fastLoot", "schnell", en = "fast" },
    { "itemLevel", "itemlevel" },
    { "bind", "boe", en = "bind" },
    { "upgrade", "besser", en = "upgrade" },
    { "npcLoot", "tooltip" },
    { "itemLoot", "gegenstand", en = "item" },
    { "itemOrigin", "herkunft", en = "origin" },
    { "itemContents", "inhalt", en = "contents" },
    { "npcWorth", "wert", en = "worth" },
    { "npcSkin", "kuerschnern", en = "skin" },
    { "npcLootHint", "hinweis", en = "hint" },
}

local Core = ezCore

-- Einstellungs-Prüfung vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“, Abschnitt 4 nach Empfehlung):
-- „Beute-Verlauf an die Würfelergebnisse andocken“ ist immer an (Wegziehen löst ihn schon) – der Schlüssel dockHistory
-- verschwindet einmal aus ezLootDB.settings (Merker db.settings1911, Core.MigrateOnce); ein gespeichertes „aus“ gilt
-- nicht mehr. → true beim ersten Mal, sonst nil
ns.RETIRED_1911 = { "dockHistory" }
function ns.MigrateSettings1911(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    return Core.MigrateOnce(db, "settings1911", function()
        for _, key in ipairs(ns.RETIRED_1911) do db.settings[key] = nil end
        return true
    end)
end

-- Eigene Befehle vor den gemeinsamen (Gerüst: optionen, status, hilfe, Schalter aus ns.TOGGLES). true = erledigt.
-- Die englischen Schalterwörter (fast, hint, item, origin, worth, skin) und „kürschnern“ mit Umlaut versteht
-- seit dem Gesamtreview (T10-1, T18-16) ezCores Core.HandleToggle über ns.TOGGLES (Feld en, Core.SlashWord).
function ns.SlashExtra(cmd)
    if cmd == "mögliche" or cmd == "moegliche" or cmd == "possible" then
        ns.LootHistory.TogglePossible()
    elseif cmd == "auto" or cmd == "autoloot" or cmd == "automatisch" then
        ns.ToggleAutoLoot()
    elseif cmd == "würfel" or cmd == "wuerfel" or cmd == "rolls" then
        ns.OpenRollHistory()
    elseif cmd == "verlauf" or cmd == "history" or cmd == "beute" or cmd == "loot" then
        ns.LootHistory.Toggle()
    else
        return false
    end
    return true
end

-- Gerüst aus ezCore (Core.ModuleScaffold): Datenbank ezLootDB mit Einstellungen und „tour“, Anmelden (ns.RunReady),
-- Befehl /ezloot mit Kurzbefehl /ezl (ns.HandleSlash), Status (ns.AddStatusLine, ns.StatusLines, ns.PrintStatus).
-- core/needs: Ist ezCore zu alt, meldet ezCore das einmal im Chat und das Modul bleibt still – statt nil-Fehlern.
Core.NewModule(ADDON, ns, {
    -- scaffoldHelpers (ns.IsSecret/Num/OtherFor des Gerüsts), Now, Uptime und Core.Style (Welle 22) kamen nach 1.11.0
    -- ohne neue Nummer dazu
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.ItemIconText, Core.SwitchCVar, Core.TipClick, Core.Tooltip.Gap
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    title = "ezLoot", core = "1.15.0", needs = { "ItemInstant", "Sources.ContentsOf", "Finds.ObjectKind", "Discovery.TargetObject", "Tooltip.ORDER.contents",
        "Tooltip.OBJECT_ORDER.contents", "WhoHandles", "AddCompanion", "NewTour", "TogglePanel",
        "scaffoldHelpers", "Now", "Uptime", "Style.Color", "Style.IconSize",
        -- Welle 23: Teile aus den ezCore-Paketen 23a und 23c (ohne neue Versionsnummer)
        "Style.SetTextColor", "Tooltip.ORDER.loot",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More", "L.ALL_CHARS",
        -- Welle 26 (ezCore-Paket kern/ezcore-reste-24, ohne neue Nummer): Geld-Spalte „money“ (Core.GoldDecimal)
        "GoldDecimal",
        -- Gesamtreview 18.11.2026 (P14): „Automatisch plündern“ schaltet im Kampf nicht um (ohne neue Nummer)
        "SwitchCVar",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2; ezCore ohne neue Versionsnummer): Addon-Fach und Befehl
        -- nach Entscheidung 5, Tooltip-Rollen, Klick-Hinweis, Weg zur Einstellung
        "compartmentMain", "slashMain", "SlashCmd", "TipLine", "TipTitle", "TipText", "TipClick", "ClickText",
        "SettingsPathText", "ShowTip",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CombatNotice",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "ICON_FALLBACK", "QualityName", "QualityText", "MigrateOnce",
    -- Einstellungs-Prüfung 19.11.2026 (ezCore ohne neue Versionsnummer): gemeinsame Schalter mehrerer Module
    "ShareSettings", "AdoptModuleShared", "SharedOn" },
    db = "ezLootDB", tables = { "tour" }, login = true,
    -- Einstellungs-Prüfung vom 19.11.2026: eigene Umzüge, danach die alten Werte der gemeinsamen Schalter einmal an
    -- ezCore (ns.SHARED unten; ein „an“ bleibt an)
    onLoad = function(db)
        ns.MigrateSettings1911(db)
        Core.AdoptModuleShared(ns, db)
    end,
    -- Kurzbefehl /ezl (nur, wenn frei) aus Core.SLASH_ALIASES; ohne Wort öffnet der Befehl den Beute-Verlauf wie der
    -- Linksklick im Addon-Fach (Entscheidung 5 vom 18.11.2026)
    slash = { extra = function(cmd) return ns.SlashExtra(cmd) end, main = function() ns.LootHistory.Toggle() end,
        mainText = L.COMPARTMENT_MAIN },
})

-- ns.IsSecret, ns.Num, ns.Plain, ns.OtherFor, ns.Enabled, ns.Throttle und ns.WhenAddOnLoaded kommen aus
-- Core.NewModule (Abkürzungen des Gerüsts, eine Fassung für alle Module; W-14).

-- Gemeinsame Schalter mit ezBag (Einstellungs-Prüfung 19.11.2026, Nr. 95/96; Entscheidung des Nutzers „Ja, alle
-- umsetzen“): Itemlevel und „BoE“ gelten an ezBags Taschenplätzen und hier im Plündern- und Würfelfenster – ein Wert in
-- ezCore (Gruppe itemMarks). ns.Enabled("itemLevel" | "bind"), die Kästchen der Seite (Spiegel) und /ezloot itemlevel
-- bzw. boe führen dorthin; die erste Quelle mit gespeichertem Wert setzt ihn, jede weitere kann nur einschalten.
-- old = ezLoots früherer Standard (an): ein gespeichertes „an“ ist keine Wahl und überstimmt kein „aus“ aus ezBag.
ns.SHARED = Core.ShareSettings(ns, {
    itemLevel = { "itemMarks", "itemLevel", mode = "first", old = true },
    bind = { "itemMarks", "boe", mode = "first", old = true },
})

---------------------------------------------------------------------------
-- Rücksicht auf andere Addons: erkannt an einer Stelle in ezCore (WhoHandles, Liste in docs/fremd-addons.md).
-- ns.OtherFor(funktion) aus dem Gerüst → Name des Addons, das sie schon übernimmt, sonst nil:
-- "fastLoot" (Leatrix Plus „Faster auto loot“), "lootAtlas" (AtlasLoot), "dungeonAtlas" (Atlas), "unitLoot".
---------------------------------------------------------------------------

-- Name des Addons, das schneller plündern schon übernimmt, sonst nil.
function ns.FastLootOther()
    return (ns.OtherFor("fastLoot"))
end

-- Schnell plündern ist gewollt und kein anderes Addon erledigt es schon.
function ns.FastLootActive()
    return ns.Enabled("fastLoot") and ns.FastLootOther() == nil
end

-- Ergänzende Addons (Abschlussrunde): unter „Erweitert“ mit Link zum Kopieren (ezCore.AddCompanion, page:Companions).
-- Nicht Leatrix Plus: dafür hält sich ezLoot nur zurück. Link geprüft am 13.11.2026 (AtlasLoot Classic Forever, Sliccer).
-- Questie (LOOT-11; Entscheidung des Nutzers 14.11.2026 „Ja, und Questie empfehlen“): Name, Ordner und Link stehen
-- einmal in ezCore (Core.OTHER_ADDONS.Questie, V-138), hier nur Schlüssel und Begründung. Tnny's Mob Loot ist keine
-- Ergänzung und seit Welle 16 auch keine angebundene Quelle mehr (RB-01); läuft es, nimmt ezLoot nur Rücksicht.
ns.COMPANIONS = {
    { key = "AtlasLoot", label = "AtlasLoot Classic Forever", url = "https://www.curseforge.com/wow/addons/atlasloot-forever",
      role = "optional", why = L.COMPANION_WHY_ATLASLOOT },
    { key = "Questie", role = "optional", why = L.COMPANION_WHY_QUESTIE },
}
for _, entry in ipairs(ns.COMPANIONS) do Core.AddCompanion(ADDON, entry) end

---------------------------------------------------------------------------
-- Automatisch plündern ist eine Einstellung des Spiels (Optionen → Steuerung)
---------------------------------------------------------------------------

-- Blizzards Standard der CVar autoLootDefault ist „0“ (aus) – Standard des Kästchens auf ezLoots Seite
ns.AUTOLOOT_DEFAULT = false

function ns.AutoLootOn()
    return Core.CVar("autoLootDefault") == "1"
end

-- true bei Erfolg; false, "combat" im Kampf (Schalter auf Klick: Core.SwitchCVar, T1-9 Gesamtreview 18.11.2026).
function ns.SetAutoLoot(on)
    return Core.SwitchCVar("autoLootDefault", on and "1" or "0")
end

function ns.ToggleAutoLoot()
    local want = not ns.AutoLootOn()
    local ok, why = ns.SetAutoLoot(want)
    if ok and ns.AutoLootOn() == want then
        ns.Print(want and L.AUTOLOOT_ON or L.AUTOLOOT_OFF)
    elseif why == "combat" then
        Core.CombatNotice(ns, Core.L.CVAR_WHAT)   -- ezCores Satz zur Kampfsperre (T18-1)
    else
        ns.Print(L.AUTOLOOT_FAILED)
    end
end

---------------------------------------------------------------------------
-- „besser“ kommt aus ezGear: Bewertung und Pfeil (SetUpgradeIcon) für alle Module, nicht nachgebaut
---------------------------------------------------------------------------

function ns.GearAvailable()
    local gear = Core.API("ezGear")
    return gear ~= nil and type(gear.SetUpgradeIcon) == "function"
end

---------------------------------------------------------------------------
-- Anmelden (Datenbank, ns.RunReady und der Kurzbefehl /ezl kommen aus dem Gerüst)
---------------------------------------------------------------------------

ns.On("PLAYER_LOGIN", function()
    if not ns.db then return end
    -- Einmal erklären, warum ezLoot nicht selbst schneller plündert.
    local other = ns.Enabled("fastLoot") and ns.FastLootOther()
    if other and not ns.db.fastLootHintShown then
        ns.db.fastLootHintShown = true
        ns.Print(L.HINT_OTHER:format(other))
    end
end)

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

-- Zeilen für „/ezl status“ und den Knopf „Status“ (page:StatusButton); gesammelt über ns.AddStatusLine.
function ns.OwnStatusLines()
    local lines = {}
    if not ns.Enabled("fastLoot") then
        lines[#lines + 1] = L.STATUS_FAST_OFF
    elseif ns.FastLootOther() then
        lines[#lines + 1] = L.STATUS_FAST_OTHER:format(ns.FastLootOther())
    else
        lines[#lines + 1] = L.STATUS_FAST_ON
    end
    lines[#lines + 1] = ns.AutoLootOn() and L.STATUS_AUTOLOOT_ON or L.STATUS_AUTOLOOT_OFF
    lines[#lines + 1] = ns.GearAvailable() and L.STATUS_GEAR_ON or L.STATUS_GEAR_OFF
    if not ns.Enabled("npcLoot") then
        lines[#lines + 1] = L.STATUS_DROPS_OFF:format(ns.SlashCmd())
    elseif ns.OtherFor("unitLoot") then
        local keyed, other = ns.Drops.OtherKeyed()
        lines[#lines + 1] = (keyed and L.STATUS_DROPS_OTHER_KEY or L.STATUS_DROPS_OTHER):format(other)
    else
        lines[#lines + 1] = L.STATUS_DROPS_ON
    end
    if ns.Enabled("npcLoot") then lines[#lines + 1] = ns.SourcesStatusLine() end
    lines[#lines + 1] = ns.WorthStatusLine()
    lines[#lines + 1] = ns.CountStatusLine()
    lines[#lines + 1] = ns.Enabled("itemLoot") and L.STATUS_ITEMLOOT_ON or L.STATUS_ITEMLOOT_OFF:format(ns.SlashCmd())
    -- Leitlinie 9: zeigt ein anderes Addon selbst, von wem ein Gegenstand fiel (Tnny's Mob Loot „Drops from“), sagt
    -- der Status das; ezLoots Zeile nennt dagegen nur selbst Gezähltes („bei dir“) und bleibt. Gilt auch für die
    -- Herkunft „laut …“ (itemOrigin): Sie steht dann neben der des anderen Addons (Gegenprüfung Welle 23)
    if (ns.Enabled("itemLoot") or ns.Enabled("itemOrigin")) and ns.OtherFor("itemSource") then
        lines[#lines + 1] = L.STATUS_ITEMLOOT_OTHER:format(ns.OtherFor("itemSource"))
    end
    -- Herkunft laut einer angebundenen Datenbank an Nicht-Rohstoffen (Welle 23, Entscheidung Nr. 24)
    lines[#lines + 1] = ns.Enabled("itemOrigin") and L.STATUS_ITEMORIGIN_ON or L.STATUS_ITEMORIGIN_OFF:format(ns.SlashCmd())
    -- Inhalt geöffneter Behälter (Contents.lua): aus der Zählung von ezCores Datenbank
    lines[#lines + 1] = ns.Enabled("itemContents") and L.STATUS_ITEMCONTENTS_ON
        or L.STATUS_ITEMCONTENTS_OFF:format(ns.SlashCmd())
    local history = ns.LootHistory
    if history and history.Available() then
        lines[#lines + 1] = L.STATUS_HISTORY:format(#history.Entries({ all = false, zone = false, quality = -1 }),
            ns.SlashCmd())
    else
        lines[#lines + 1] = L.HISTORY_NO_CORE
    end
    if ns.OtherFor("lootAtlas") then
        lines[#lines + 1] = L.STATUS_ATLASLOOT
    elseif ns.OtherFor("dungeonAtlas") then
        lines[#lines + 1] = L.STATUS_ATLAS
    end
    return lines
end
ns.AddStatusLine(function() return ns.OwnStatusLines() end)

-- Wert je Tötung (V2, Welle 24): Schalter, Beute im Gegner-Tooltip (die Zeile steht in diesem Abschnitt) und ob dieses
-- ezCore die Rechnung hat (Core.Drops.Worth, Welle 23d) – ohne sie bleibt die Zeile still weg.
function ns.WorthStatusLine()
    if not (ns.Enabled("npcWorth") and ns.Enabled("npcLoot")) then return L.STATUS_WORTH_OFF:format(ns.SlashCmd(), ns.SlashCmd()) end
    if not ns.Drops.WorthAvailable() then return L.STATUS_WORTH_OLD end
    local min = ezCore.Drops and ezCore.Num(ezCore.Drops.WORTH_MIN) or 5
    return L.STATUS_WORTH_ON:format(min)
end

-- Woher „Beute bei dir“ zählt: ezCores Entdecker-Datenbank (Core.Drops, ohne V-008), solange sie sammelt und den
-- Gegner stimmig kennt, sonst der Beute-Verlauf (dieselbe Abfrage wie im Tooltip: Drops.DbState).
function ns.CountStatusLine()
    local state = ns.Drops.DbState()
    if state == "on" then return L.STATUS_COUNT_DB end
    if state == "off" then
        -- Name des Schalters aus ezCores Texten (eine Quelle für den Wortlaut)
        local CL, key = Core.L, "OPT_dataCollect"
        local name = type(CL) == "table" and type(CL[key]) == "string" and CL[key] or "?"
        return L.STATUS_COUNT_OFF:format(name)
    end
    if state == "wait" then return L.STATUS_COUNT_WAIT end
    return L.STATUS_COUNT_LOG
end

-- Statuszeile „Mögliche Beute“: nennt die Quellen, die gerade antworten, beim Namen; sonst warum keine
-- (Core.Sources.Hint; stille Rückfälle nennt ezCore dort nicht); ältere ezCore-Fassung ohne
-- Core.Sources.LootOf.
function ns.SourcesStatusLine()
    local D = ns.Drops
    if not (D and D.SourcesAvailable()) then return L.STATUS_SOURCES_OFF end
    local names = D.ActiveSources()
    if #names > 0 then return L.STATUS_SOURCES_ON:format(table.concat(names, ", ")) end
    return L.STATUS_SOURCES_NONE:format(D.SourceHint())
end
-- ns.StatusLines, ns.PrintStatus (Kopf ns.StatusHeader()) und ns.HandleSlash (/ezloot, /ezl) stellt das Gerüst;
-- die eigenen Befehle stehen oben in ns.SlashExtra.

---------------------------------------------------------------------------
-- Addon-Knopf an der Minikarte
---------------------------------------------------------------------------

-- Entscheidung 5 vom 18.11.2026 (T18-3, T16-10): Linksklick = Hauptfunktion – der Beute-Verlauf –, Rechtsklick =
-- Einstellungen (vorher schaltete er schneller plündern; das tun der Knopf am Plündernfenster, die Einstellung und
-- „/ezl schnell“). Klick, Tooltip und Befehlszeile baut ezCore.
ezLoot_OnAddonCompartmentClick, ezLoot_OnAddonCompartmentEnter, ezLoot_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({
        ns = ns, title = L.TITLE, main = function() ns.LootHistory.Toggle() end, mainText = L.COMPARTMENT_MAIN,
        owner = ADDON,
    })
-- früherer Name des Klicks (Prüfungen, andere Aufrufer): dieselbe Belegung wie das Addon-Fach
function ns.CompartmentClick(button) return ezLoot_OnAddonCompartmentClick(nil, button) end
