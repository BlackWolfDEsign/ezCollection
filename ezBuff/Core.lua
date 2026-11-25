local ADDON, ns = ...
local L = ns.L

--[[
    ezBuff – fehlende Buffs außerhalb des Kampfes melden und mit einem Klick nachholen.

      Buffs.lua    Auren über ezCore.Auras (nur außerhalb des Kampfes, gesperrte nie verglichen), Buff-Gruppen aus ezCore.Spells
      Weapon.lua   Waffenverzauberung auf Zeit (Gift, Wetzstein, Öl) je Hand lesen → Aufgabe mit Gegenstand
      Checks.lua   Was fehlt? Buff-Essen, Fläschchen/Elixier, Waffe, Klassen-Buffs, Lagerfeuer → Aufgabenliste;
                   Gruppenfassungen ab mehreren fehlenden Mitgliedern
      Rebuff.lua   Ein anderer Spieler bufft dich → Buff zurückgeben und mit Emote danken
      ActionGlow.lua  Aktionsknöpfe fehlender eigener Klassen-Buffs leuchten, in jedem Rang (Leucht-Dienst ezCore.Glow)
      Button.lua   Sicherer Knopf neben Blizzards Buff-Leiste (Core.SecureButton, wandert mit ihr), Tooltip mit allem,
                   was fehlt; Rechtsklick: eigene Wahl je Wahlgruppe und Einstellungen
      Group.lua    Abschnitt „Gruppe“: Symbol je Mitglied an Blizzards Gruppen- und Raidrahmen, Durchbuffen auf einer
                   Taste (ezCores Tasten-Dienst), Segen-Wahl im Rechtsklick-Menü, Zeichen für Essen und Fläschchen
      Macro.lua    Vorlage „Durchbuffen“ je Klasse: Makro in Blizzards Makroverwaltung, das den Knopf „Durchbuffen“ drückt
      Panel.lua    Meldungen auf ezPanels Leiste: „Buff fehlt“ und „Buff fehlt bei n Gruppenmitgliedern“
      Options.lua  Einstellungsseite (ezCollection → ezBuff)

    Im Kampf sind Auren geheim und der sichere Knopf darf sich nicht ändern: ezBuff prüft nur außerhalb,
    der Knopf verschwindet im Kampf über Blizzards Zustandstreiber und kommt danach wieder.
]]

ns.DEFAULTS = {
    button = true,          -- Knopf an Blizzards Buff-Leiste
    food = true,            -- Buff-Essen („Satt“)
    flask = true,           -- Fläschchen oder Elixier
    -- Buff-Essen und Fläschchen prüfen: "always" | "group" | "instance". Ab Werk "always" seit der Entscheidung des
    -- Nutzers vom 23.11.2026 („Auch allein prüfen“; vorher "group" – allein unterwegs fehlte das Buff-Essen)
    when = "always",
    selfBuffs = true,       -- eigene Klassen-Buffs auf dir
    -- lange Selbst-Buffs aus Talenten bzw. für eine Rolle, je Buff abwählbar (Buffs.LONG_SELF, T14-2; Entscheidung
    -- des Nutzers vom 19.11.2026). Zorn der Gerechtigkeit ab Werk aus: er nützt nur dem tankenden Paladin
    longTrueshotAura = true,   -- Aura des Volltreffers (Jäger, Talent)
    longRighteousFury = false, -- Zorn der Gerechtigkeit (Paladin, erhöht die Bedrohung)
    longSoulLink = true,       -- Seelenverbindung (Hexenmeister, Talent, nur mit Begleiter)
    groupBuffs = true,      -- eigene Klassen-Buffs auf Gruppenmitgliedern
    otherBuffs = true,      -- Buffs anderer Klassen in der Gruppe (nur Meldung)
    missingGlow = true,     -- Aktionsknöpfe fehlender eigener Buffs leuchten (jeder Rang)
    groupFrames = true,     -- Abschnitt „Gruppe“: Symbol „dein Buff fehlt“ an Blizzards Gruppen- und Raidrahmen
    groupSigns = true,      -- dort auch Zeichen für fehlendes Buff-Essen und Fläschchen
    -- Symbol und Durchbuffen wirken die Gruppenfassung, wenn sie mehreren fehlt (BF-09): ab so vielen Mitgliedern ohne
    -- den Buff (in Reichweite); 1 = aus (Einstellungs-Prüfung 19.11.2026, Nr. 75: nur noch der Regler, bis dahin dazu
    -- das Kästchen groupSpells)
    groupMin = 3,
    -- Waffenverzauberung (Gift, Wetzstein, Öl) als Aufgabe am Knopf (BF-17). Ab Werk an seit der Einstellungs-Prüfung
    -- vom 19.11.2026 (Abschnitt 4): handelt nur auf Klick; ezCombat warnt vor dem Ablauf, ezBuff bietet den Klick an.
    weapon = true,
    campfire = false,       -- Lagerfeuer-Buff (braucht Kochen und Holz)
    minLeft = 2,            -- Minuten: kürzere Restzeit zählt als fehlend
    rebuff = true,          -- Buff zurückgeben, wenn dich jemand bufft
    thank = true,           -- dabei mit Emote danken (ezCore.PerformEmote)
    report = true,          -- im Chat melden: Bereitschaftscheck, Instanz betreten
    -- Meldungen bei ezPanels Baustein „Meldungen“: kein eigener Schalter mehr, ezPanels Auswahl der Meldungsquellen ist
    -- die eine Stelle (Einstellungs-Prüfung 19.11.2026, Nr. 76)
}

-- „Allem zustimmen“ (ezCore, Werkzeuge/FirstStart.lua: Intro.Registered; Spieltest 20.11.2026): jeder Schalter oben,
-- der ab Werk aus ist und kein Ablauf ohne Klick (die stehen in Intro.CONSENT). "on": mit der Zustimmung gesetzt;
-- "risk": bleibt aus, riskiert Blizzards Regeln oder Schutz; "choice": Geschmack, Filter, Leitlinie 9 oder 11.
-- tools/Tests/agree_test.lua prüft, dass jeder neue Schalter mit false hier oder in Intro.CONSENT steht.
ns.AGREE = {
    campfire = "on", longRighteousFury = "choice",
}

-- Grenzen der Regler und Werte der Auswahlfelder – eine Stelle für die Einstellungsseite (Options.lua) und die
-- Prüfung der Profile (Profiles.lua, Welle 23).
ns.LIMITS = { minLeft = { 0, 10 }, groupMin = { 1, 10 } }   -- groupMin 1 = Gruppenfassung aus
ns.GROUP_MIN_OFF = 1
ns.CHOICES = { when = { "always", "group", "instance" } }

local Core = ezCore
-- Gerüst von ezCore (EC-66): Datenbank ezBuffDB samt Einstellungen und Tabellen, Anmelden (RunReady), /ezbuff mit
-- „optionen“, „status“, „hilfe“, „zuruecksetzen“ (ns.HandleSlash, ns.PrintHelp aus Core.HelpLines und L.CMD_HELP_OWN). Dazu die Abkürzungen ns.IsSecret,
-- ns.Plain, ns.Num, ns.InCombat, ns.OtherFor sowie ns.NoteSecret/ns.secretSeen (gesperrte Daten für /ezbuff status),
-- ns.Enabled und ns.Throttle. ezCore 1.11.0 bringt Core.InInstance und ns.OtherFor; 1.12.0 Core.UnitKey (BF-11) und
-- page:ProxyDropdown (BF-06, EC-39).
Core.NewModule(ADDON, ns, {
    title = "ezBuff",
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.CombatNotice, Core.HelpLines, Core.SettingsPathText, Core.Ticker
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",
    -- Welle 22 (ezCore 1.12.0 auf main): Symbolgröße aus dem Design-System, Dienst „Makro anlegen“, Kennzeichen am Knopf
    needs = { "NewSettingsProfiles", "Style.ICON", "Macro.Find", "Macro.Write", "Macro.Limits", "MacroBadge.Register",
        -- Einstellungs-Prüfung 19.11.2026: gespeicherte Werte einmal umstellen (Core.MigrateOnce)
        "MigrateOnce",
        -- Gesamtreview 18.11.2026, P19c (ohne neue Versionsnummer): Takt mit Griff (T7-3)
        "Ticker",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "More",
        -- Welle 23 (ezCore 1.13.0 ohne neue Versionsnummer, Paket kern/reste-23a):
        -- A1 Spieler-Menüs mit der Art „frame“ (die Art kam im selben Paket wie Debug.AddLine, docs/ezcore.md)
        "Menu.PlayerMenus", "Debug.AddLine",
        -- A3 gemeinsamer Leser der Waffenverzauberung, A4 Waffenzauber des Schamanen
        "WeaponEnchantInfo", "Spells.WeaponImbues", "Spells.BestImbueRank",
        -- heutige Zauber-Abfrage statt IsPlayerSpell (Paket kern/abgeloeste-namen, 24.11.2026, ohne neue Nummer)
        "KnowsSpell",
        -- Paket ezmacro/gifte-waffenzauber (ohne neue Nummer): Regel „bester Gegenstand“, Makro „Gegenstand auf die
        -- Waffe“ und Reihenfolge der Waffenzauber aus ezCore (eine Quelle mit ezMacro)
        "BestItems.Score", "BestItems.Usable", "Macro.WeaponItem", "Spells.IMBUE_ORDER", "Spells.OrderedImbues", "Spells.ChooseImbue", "WeaponEnchantable",
        -- Paket ezcore/klinge-wucht (ohne neue Nummer): je Hand nur, was die Waffe annimmt (Client-Tabelle SpellEquippedItems)
        "BestItems.PickWeaponEnchant",
        -- Fehler vom Nutzer vom 23.11.2026 (ohne neue Nummer): Buff-Essen bei jeder Klasse, „passt zur Klasse?“ aus ezCore
        "BestItems.Fit",
        -- A2 Profil-Gerüst (vergisst Charaktere selbst) und Übernehmen eines Werts
        "NewProfiles", "ApplySetting",
        -- Welle 26 (ezCore-Paket kern/ezcore-reste-24, ohne neue Nummer): „Was fehlt für diesen Zauber?“ aus ezCore
        "Spells.MissingReagents", "Spells.ReagentNeeds", "Spells.ReagentText", "Spells.ReagentSource",
        -- Welle 27 (kern/buff-schnittstelle, ohne neue Nummer): Buff-Wissen nur über ezCores Leseschnittstelle (F7)
        "Spells.IsBuff", "Spells.BuffField", "Spells.BuffKeys",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2): Addon-Fach und Befehl ohne Wort nach Entscheidung 5,
        -- Hilfe aus ezCore, Kampfsperre, Wege zu Einstellungen und Menüeintrag aus ezCore
        "compartmentMain", "slashMain", "CombatNotice", "SettingsPathText", "Menu.Settings",
        -- lange Selbst-Buffs (T14-2): Begleiter da?
        "UnitPresent",
        -- Tooltip-Zeilen mit Rollen statt Farbzahlen (T9-6)
        "TipLine",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "Word",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "ICON_FALLBACK" },
    db = "ezBuffDB",
    -- elixirs: [Zauber-ID der Aura] = "flask" | "elixir"; chars: [charKey] = { prefer = { [Buff] = Zauber-ID } };
    -- hints: gesehene Erklärblasen des Rundgangs
    tables = { "elixirs", "chars", "hints" },
    onLoad = function(db)
        for _, c in pairs(db.chars) do ns.MigratePrefer(c) end
        ns.MigrateSettings1911(db)
        ns.MigrateWhen2311(db)
    end,
    login = true,
    -- „test“ und „makro“ versteht ezBuff selbst; „optionen“, „status“, „hilfe“ und „zuruecksetzen“ (Rückfrage wie der
    -- Knopf) das Gerüst. main: „/ezbuff“ ohne Wort meldet wie der Linksklick im Addon-Fach, was fehlt (Entscheidung 5)
    slash = { extra = function(cmd) return ns.SlashExtra(cmd) end, main = function() ns.PrintMissing(true) end,
        mainText = L.MAIN_TEXT, reset = true },
})

-- Nachricht an andere Module ins Verzeichnis von ezCore (Core.MESSAGES; UE-15): Der Name trägt das Modul.
Core.RegisterMessage("EZBUFF_TASKS", "ezBuff",
    "Nach jeder Prüfung von ezBuff: die Liste fehlender Buffs ist neu (lesen über ezCore.API(\"ezBuff\").Missing). Zuhörer: ezCombat, ezBuff/Panel.lua.")
Core.RegisterMessage("EZBUFF_PREFER_CHANGED", "ezBuff",
    "Die gemerkte Wahl einer Wahlgruppe hat sich geändert (Auswahl, Rechtsklick-Menü oder selbst gewirkt; lesen über ezCore.API(\"ezBuff\").Preferred). Zuhörer: ezMacro (Vorlage „Waffenzauber“).",
    "gruppe")

-- Klasse vor allen übrigen OnReady-Aufgaben (vorher im eigenen PLAYER_LOGIN); ns.charKey setzt das Gerüst.
ns.OnReady(function() ns.playerClass = Core.PlayerClass() end)

-- Voller Name einer Einheit (Forever: „Vorname Nachname“, sonst „Name-Realm“) – ezCore rechnet ihn.
ns.UnitFullName = Core.UnitFullName

-- Erster Rückgabewert eines Client-Aufrufs, nil bei Fehler oder geheimem Wert.
function ns.Value(fn, ...)
    return Core.Plain((Core.Call(fn, ...)))
end

---------------------------------------------------------------------------
-- Datenbank (ezBuffDB legt das Gerüst an: Core.NewModule oben)
---------------------------------------------------------------------------

-- Einstellungs-Prüfung vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“): gespeicherte Werte einmal
-- übernehmen – in den Einstellungen und in jedem gesicherten Profil (ezCores Core.MigrateOnce, Merker settings1911):
--   groupSpells false → groupMin 1 (= aus; Nr. 75), danach fliegt groupSpells
--   panelWarning      → entfernt (Nr. 76; ezPanels Quellen-Auswahl gilt, ihr alter Wert nicht mehr)
--   weapon false      → true (neuer Standard; ezCore schreibt alle Standardwerte in den Speicher, ein gespeichertes
--                       „aus“ ist vom alten Standard nicht zu unterscheiden – wie prepRestDefault in ezCombat;
--                       umkehrbar über das Kästchen)
ns.REMOVED_SETTINGS = { "groupSpells", "panelWarning" }

function ns.AdoptSettings1911(settings)
    if type(settings) ~= "table" then return end
    if settings.groupSpells == false then settings.groupMin = ns.GROUP_MIN_OFF end
    if settings.weapon == false then settings.weapon = true end
    for _, key in ipairs(ns.REMOVED_SETTINGS) do settings[key] = nil end
end

function ns.MigrateSettings1911(db)
    return Core.MigrateOnce(db, "settings1911", function()
        ns.AdoptSettings1911(db.settings)
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            ns.AdoptSettings1911(type(profile) == "table" and profile.settings or nil)
        end
        return true
    end)
end

-- Entscheidung des Nutzers vom 23.11.2026 („Auch allein prüfen“, auf die Frage „Soll ezBuff Buff-Essen und
-- Fläschchen auch prüfen, wenn du allein unterwegs bist?“; Anlass: „fehlendes bufffood (in tasche vorhanden) beim
-- hexer wird nicht angezeigt“): „Wann prüfen“ ab Werk "always" statt "group". Einmal umgestellt wird der alte
-- Werkswert "group" – in den Einstellungen und in jedem gesicherten Profil (Merker when2311). ezCore schreibt alle
-- Standardwerte in den Speicher; ein gespeichertes "group" ist vom alten Standard nicht zu unterscheiden (wie bei
-- weapon in settings1911) und wird mit umgestellt, umkehrbar über das Auswahlfeld. "instance" war nie Standard, also
-- selbst gewählt, und bleibt.
function ns.AdoptWhen2311(settings)
    if type(settings) == "table" and settings.when == "group" then settings.when = "always" end
end

function ns.MigrateWhen2311(db)
    return Core.MigrateOnce(db, "when2311", function()
        ns.AdoptWhen2311(db.settings)
        for _, profile in pairs(type(db.profiles) == "table" and db.profiles or {}) do
            ns.AdoptWhen2311(type(profile) == "table" and profile.settings or nil)
        end
        return true
    end)
end

-- Gemerkte Wahl (prefer) einmalig bereinigen: Bis zur Nachbesserung H7 merkte sich ezBuff jeden selbst gewirkten
-- Buff einer Wahlgruppe – auch den, den die Automatik vorgeschlagen hatte, und jeden Segen auf einem anderen
-- Spieler. Seither gilt eine gemerkte Wahl als bewusst (Check.Remember merkt nur noch eine Abweichung vom Vorschlag)
-- und gewinnt; ein alter Eintrag hielte den Spieler sonst für immer fest (Paladin bei Macht statt Könige,
-- Schamane über keepChoice beim Blitzschlagschild statt Wasserschild). Gelöscht wird, was von der alten Automatik
-- stammen kann (true = jeder Eintrag der Gruppe):
--   blessing  jeder: Macht war der Vorschlag, und Segen auf Gruppenmitgliedern wurden ebenso gemerkt
--   shield    Blitzschlagschild (alter Vorschlag; mit keepChoice schlüge er das Wasserschild für immer)
--   armor     Frostrüstung, Dämonenhaut (alter Vorschlag; ezCore löst sie ohnehin ab, zählt nur im Rückfall)
-- Eis-, Magische und Dämonenrüstung sowie das Wasserschild schlug die alte Automatik nie vor – sie bleiben.
ns.PREFER_SCHEMA = 2
ns.PREFER_LEGACY = {
    blessing = true,
    shield = { lightningShield = true },
    armor = { frostArmor = true, demonSkin = true },
}

-- Daten eines Charakters auf den aktuellen Stand der gemerkten Wahl bringen (einmal; Marke c.preferSchema).
function ns.MigratePrefer(c)
    if type(c) ~= "table" or c.preferSchema == ns.PREFER_SCHEMA then return false end
    if type(c.prefer) == "table" then
        for id, rule in pairs(ns.PREFER_LEGACY) do
            local key = c.prefer[id]
            if key ~= nil and (rule == true or rule[key]) then c.prefer[id] = nil end
        end
    end
    c.preferSchema = ns.PREFER_SCHEMA
    return true
end

-- Ein Twink wird vergessen (/ez vergessen): seine Wahl der Segen und Rüstungen auch.
Core.Listen("CHAR_FORGOTTEN", function(key)
    if ns.db and key then ns.db.chars[key] = nil end
end, ADDON)

-- Daten des aktuellen Charakters (gewählte Segen und Rüstungen).
function ns.CharDB()
    if not ns.db then return {} end
    local key = ns.charKey or Core.charKey or "?"
    local c = ns.db.chars[key]
    if type(c) ~= "table" then
        c = { preferSchema = ns.PREFER_SCHEMA }   -- neu: nichts Altes zu bereinigen
        ns.db.chars[key] = c
    end
    c.prefer = type(c.prefer) == "table" and c.prefer or {}
    c.blessings = type(c.blessings) == "table" and c.blessings or {}   -- [Klasse] = Segen (Rechtsklick-Menü)
    -- ["Name-Realm"] = { blessing = Segen, class = Klasse, name = Anzeigename }: Einzelwahl je Spieler, überstimmt
    -- die Klasse; bleibt, wenn der Spieler die Gruppe verlässt (löschen unter Einstellungen → Erweitert)
    c.players = type(c.players) == "table" and c.players or {}
    return c
end

---------------------------------------------------------------------------
-- Wo bin ich? Buff-Essen und Fläschchen lohnen sich je nach Einstellung nur in Gruppe oder Instanz.
---------------------------------------------------------------------------

-- ns.InInstance behält seine Bedeutung (nur Dungeon und Schlachtzug zählen) und leitet an Core.InInstance weiter
-- (W-14, BF-03): gesperrt oder unbekannt zählt wie bisher als „nicht drin“.
function ns.InInstance()
    local inside, kind = Core.InInstance()
    if inside == true and (kind == "party" or kind == "raid") then return true, kind end
    return false, kind
end

-- In Gruppe oder Schlachtzug? ezCore (Core.InGroup); ohne ezCore-Abfrage die alte Prüfung.
function ns.InGroup()
    if Core.InGroup then return Core.InGroup() == true end
    return IsInGroup ~= nil and IsInGroup() == true
end

-- when: "always" | "group" | "instance"
function ns.ContextAllows(when)
    if when == "always" then return true end
    if ns.InInstance() then return true end
    if when == "group" then return ns.InGroup() end
    return false
end

---------------------------------------------------------------------------
-- Melden im Chat
---------------------------------------------------------------------------

-- force: auch melden, wenn nichts fehlt (Slash-Befehl, Knopf „Jetzt melden“, Addon-Fach, Status).
-- Im Kampf steht noch die Liste der letzten Prüfung – sie wird nicht gemeldet (V-147), stattdessen ein Hinweis
-- (auch beim Bereitschaftscheck: Schweigen hieße dort „alles da“). Außerhalb des Kampfes nicht lesbar (tot, auf
-- dem Flug, Auren gesperrt): Die Liste ist dann leer und sagt nichts – Hinweis nur auf Wunsch (force).
function ns.PrintMissing(force)
    -- Auf Wunsch (force) außerhalb des Kampfes zuerst neu prüfen, wenn die letzte Prüfung nicht gilt – gleich nach
    -- dem Kampf steht die neue Prüfung noch aus (Check.Stale), der Hinweis „nicht lesbar“ wäre dann falsch.
    if force and ns.Check and not ns.InCombat() and not ns.Check.Readable() then ns.Check.Run() end
    if ns.Check and not ns.Check.Readable() then
        if ns.InCombat() then
            Core.CombatNotice(ns, L.REPORT_COMBAT_WHAT)   -- ezCores Satz zur Kampfsperre (T18-1)
        elseif force then
            ns.Print(L.REPORT_UNREADABLE)
        end
        return
    end
    local tasks = ns.Check and ns.Check.Tasks() or {}
    if #tasks == 0 then
        if force then ns.Print(L.REPORT_NONE) end
        return
    end
    -- Hinter „Es fehlt:“ steht nur, WAS fehlt (task.what) – der ganze Satz task.label endet selbst auf „fehlt“.
    -- Aufgaben ohne what fehlen nicht, sie sind zu tun (Buff zurückgeben, danken): eigene Zeile.
    local missing, todo = {}, {}
    for _, task in ipairs(tasks) do
        if task.what then missing[#missing + 1] = task.what else todo[#todo + 1] = task.label end
    end
    if #missing > 0 then ns.Print(L.REPORT_MISSING:format(table.concat(missing, ", "))) end
    if #todo > 0 then ns.Print(L.REPORT_TODO:format(table.concat(todo, ", "))) end
end

---------------------------------------------------------------------------
-- Status und Slash-Befehle
---------------------------------------------------------------------------

function ns.PrintStatus()
    ns.Print(ns.StatusHeader())
    if ns.Profiles then ns.Print(ns.Profiles.StatusLine()) end   -- welches Profil gilt (Welle 23, A2)
    local other = ns.Rebuff.OtherAddOn()
    if ns.S.rebuff and other then
        ns.Print(L.STATUS_MANNERS:format(other))
    elseif ns.S.rebuff and ns.S.thank then
        ns.Print(L.STATUS_EMOTE_OK)
    end
    -- „Zuletzt gesperrte Daten: Auren (vor 5 Sek.)“ aus dem Gerüst (ezCore, ns.SecretLine; Leitlinie 2)
    ns.Print(ns.SecretLine() or L.STATUS_NO_SECRET)
    -- Taste des Buff-Knopfs aus ezCores Tasten-Dienst (Eintrag „buff“) und bekannte Fläschchen (BF-10)
    local key = ns.Button and ns.Button.KeyText()
    ns.Print(key and L.STATUS_KEY:format(key) or L.STATUS_KEY_NONE:format(ns.PathText("SETTINGS_GENERAL", "OPT_BUTTON_KEY")))
    if ns.Check then ns.Print(L.STATUS_ELIXIRS:format(ns.Check.KnownElixirs())) end
    local Group = ns.Group
    if Group then
        local pbt = Group.OtherAddOn()
        if not ns.S.groupFrames then
            ns.Print(L.STATUS_GROUP_OFF)
        elseif pbt then
            ns.Print(L.STATUS_GROUP_PAUSED:format(pbt))
        else
            ns.Print(L.STATUS_GROUP:format(Group.Count(), Group.KeyLine()))
        end
        local singles = ns.Check and #ns.Check.PlayerBlessings() or 0
        if singles > 0 then
            ns.Print(L.STATUS_PLAYERS:format(singles, ns.PathText("SETTINGS_ADVANCED", "OPT_PLAYER_BLESSINGS")))
        end
    end
    -- Was der Client an Buffs kennt (Spieltest 15.11.2026): Buff-Gruppen des Clients und Buffs, die ihm fehlen
    local Buffs = ns.Buffs
    if Buffs then
        local keys, count = Buffs.ClientGroupBuffs()
        if count then
            local names = {}
            for _, key in ipairs(Core.Call(Core.Spells.BuffKeys) or {}) do
                local info = keys[key] and Buffs.Info(key)
                if info then names[#names + 1] = Buffs.Name(info, Buffs.SpellOf(info)) end
            end
            ns.Print(L.STATUS_CLIENT_GROUPS:format(count, #names > 0 and table.concat(names, ", ") or L.STATUS_NONE))
        end
        local absent = Buffs.Absent()
        if #absent > 0 then ns.Print(L.STATUS_ABSENT:format(table.concat(absent, ", "))) end
    end
    local panelLine = ns.Panel and ns.Panel.StatusLine()
    if panelLine then ns.Print(panelLine) end
    ns.PrintMissing(true)
end

-- Weg zu einer Einstellung auf ezBuffs Seite (Core.SettingsPathText, Gesamtreview T18-18): Abschnitt und Option als
-- Schlüssel (ezCores bzw. ezBuffs Texte), damit der Weg beim Umbenennen nicht veraltet.
function ns.PathText(section, option)
    return Core.SettingsPathText(ADDON, section, option, L)
end

-- Eigene Befehlswörter für das Gerüst (opts.slash.extra): true, wenn ezBuff den Befehl erledigt hat. Ohne Wort meldet
-- das Gerüst über slash.main (wie der Linksklick im Addon-Fach).
function ns.SlashExtra(cmd)
    if cmd == "test" or cmd == "vorschau" or cmd == "preview" then
        ns.Preview()
        return true
    elseif cmd == "makro" or cmd == "macro" then
        -- Vorlage „Durchbuffen“ (Macro.lua); sichtbar als Knopf unter Einstellungen » Gruppe und im Rechtsklick-Menü
        if ns.Macro then ns.Macro.Create() end
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Vorschau: der Knopf mit einem Beispiel (Einstellungen „Zeigen“, /ezbuff test, Bearbeitungsmodus)
---------------------------------------------------------------------------

function ns.Preview()
    if ns.InCombat() then
        Core.CombatNotice(ns, L.PREVIEW_COMBAT_WHAT)
        return false
    end
    return ns.Button ~= nil and ns.Button.Preview(10)
end

---------------------------------------------------------------------------
-- Schnittstelle für andere Module: ezCore.API("ezBuff")
---------------------------------------------------------------------------

ns.API = {
    -- Was fehlt gerade? Zwei Werte: Liste, lesbar.
    --   Liste   Kopie: { kind, key, label, spell = Zauber-ID oder nil, icon, keys = Buff-Schlüssel der Gruppe oder nil }
    --           label ist der ganze Satz („Rüstung (Dämonenhaut) fehlt“).
    --   lesbar  falsch im Kampf, tot, auf dem Flug oder wenn Auren gesperrt bzw. nicht lesbar sind – dann ist
    --           die Liste leer und sagt nichts (im Kampf nicht mehr die Liste der letzten Prüfung, V-147).
    --           Wer nur den ersten Wert liest, läuft unverändert.
    --           lesbar hängt nur an den Auren des Spielers: Ein Gruppenmitglied, dessen Auren nicht lesbar sind,
    --           wird still übersprungen (kein Eintrag, lesbar bleibt wahr).
    Missing = function()
        local out = {}
        if not (ns.Check ~= nil and ns.Check.Readable() == true) then return out, false end
        for _, task in ipairs(ns.Check.Tasks()) do
            local action = task.action
            local keys
            if type(task.buffKeys) == "table" then
                keys = {}
                for i, key in ipairs(task.buffKeys) do keys[i] = key end
            end
            out[#out + 1] = { kind = task.kind, key = task.key, label = task.label, icon = task.icon, keys = keys,
                spell = type(action) == "table" and action.type == "spell" and action.spell or nil }
        end
        return out, true
    end,
    -- Kümmert sich ezBuff um diesen Buff (Schlüssel oder Wahl)? „Eigene Klassen-Buffs“ an und Klasse passt.
    Watches = function(value) return ns.Check ~= nil and ns.Check.Watches(value) == true end,
    -- Neu prüfen (z. B. nach eigenem Bufffen); wirkt nur außerhalb des Kampfes.
    Refresh = function() if ns.Check then ns.Check.Request() end end,
    -- Makro „Durchbuffen“ (Macro.lua: „#showtooltip <Buff>“ und „/click ezBuffGroupNext“) für ezMacros Reiter „Ein-Klick“
    -- (Paket ezmacro/klickzauber-besitzer) → Text, Name | nil, "unsupported" (Klasse ohne Buff auf andere)
    GroupMacro = function()
        if not (ns.Macro and ns.Group) then return nil, "unsupported" end
        if not ns.Macro.Supported(ns.playerClass) then return nil, "unsupported" end
        return ns.Macro.Body(ns.playerClass), ns.Macro.Name()
    end,
    -- Gemerkte Wahl einer Wahlgruppe („blessing“, „armor“, „shield“, „imbue“) → Buff-Schlüssel oder nil (keine Wahl:
    -- dann gilt ezCore.Spells.ChooseBuff ohne prefer). Gilt auch, wenn ein Buff der Gruppe schon liegt oder
    -- „Eigene Klassen-Buffs“ aus ist – so zeigen ezBuff und ezCombat denselben Buff („Gemerkte Wahl gewinnt“).
    Preferred = function(group)
        if Core.IsSecret(group) or type(group) ~= "string" or not ns.db then return nil end
        local key = ns.CharDB().prefer[group]
        if Core.IsSecret(key) or type(key) ~= "string" then return nil end
        return key
    end,
}

---------------------------------------------------------------------------
-- Ergänzende Addons (Einstellungen → Erweitert, README). Pflicht ist nur ezCore.
---------------------------------------------------------------------------

-- Party Buff Tracker Forever (Darkspore): Übersicht der ganzen Gruppe. Name, Ordner und Adresse stehen EINMAL am
-- Eintrag in ezCore (Core.OTHER_ADDONS.PartyBuffTrackerForever, wie MAP-20 für Tweaks Forever); hier nur key und why.
Core.AddCompanion(ADDON, { key = "PartyBuffTrackerForever", role = "optional", why = L.COMPANION_WHY_PBT })

---------------------------------------------------------------------------
-- Addon-Knopf an der Minikarte nach Entscheidung 5 vom 18.11.2026 (Gesamtreview T18-3, T16-10): Linksklick meldet im
-- Chat, was fehlt (vorher Rechtsklick), Rechtsklick öffnet die Einstellungen; Tooltip und Befehlszeile von ezCore.
---------------------------------------------------------------------------

ezBuff_OnAddonCompartmentClick, ezBuff_OnAddonCompartmentEnter, ezBuff_OnAddonCompartmentLeave =
    Core.CompartmentHandlers({ ns = ns, title = L.TITLE, main = function() ns.PrintMissing(true) end, mainText = L.MAIN_TEXT })
