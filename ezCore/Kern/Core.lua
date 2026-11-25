local ADDON, ns = ...

--[[
    ezCore – gemeinsame Basis der ezCollection (im Spiel heißt sie „ezCollection“).

    Ordner (seit Welle 11, RM-19; die TOC nennt jede Datei mit ihrem Ordner, die Ladereihenfolge blieb gleich):
      Kern         Gerüst, Texte, Helfer, Einstellungen, Befehle: Core, Locale, Util, EquipSlots, Bags, Channels,
                   Framework, Panels, Serialize, Format, Names, Settings, Slash
      Bausteine    Oberfläche an Blizzards Fenstern: Widgets, Highlight, Layout, Graph, TextDialog, SpellbookView,
                   SlotText, EditMode, Mover, Tooltip, UnitTooltip, ItemTooltip, ActionSlots, Glow, SecureButton,
                   GroupFrames, ClickBindings, AuraRow, ChatBar, SlotMarks, MoveFrames, Keys, Comfort
      Charakter    Daten je Charakter und Twink: Characters, Contacts, Inventory, Mail, MailQueue, Profiles,
                   Professions, Talents, Lockouts, CharData, Durability, Junk, History
      Wissen       Wissen über Gegenstände, Zauber, Orte und Quellen: Gathering, KnowledgeData, Knowledge, Collections,
                   Recipes, SpellData, MacroLogic, Spells, Auras, Npcs, DungeonData, Dungeons, Prices, SalvageData,
                   Salvage, Sources, SourcesQuestie, OtherAddOns, RotationBuilds
      Datenbank    Entdecker-Datenbank und Preis-Schicht: DBKeys, DB, DBMarket, Discovery, DiscoveryView,
                   DiscoveryLegacy (nur hier stehen die Träger, Lint-Regel 10)
      Werkzeuge    Fehlerliste, Diagnose, Daten-Probe, Sichern, Erster Start, Beitragen, Übersicht: ErrorList,
                   Diagnose, Probe, ProbeStations, Backup, FirstStart, Contribute, Collection
    Bindings.xml und Media bleiben im Ordner ezCore.

    Alles, was mehrere Module brauchen, gibt es genau einmal (SSOT/DRY):
      Core.lua        Modul-Gerüst: Print, Fehler-Log, Ereignisse (an- und abmelden, Einheiten-Filter), Nachrichten,
                      nach dem Kampf nachholen (AfterCombat), Einstellungs-Meldungen
      Framework.lua   Gerüst-Dienste: Verzeichnis der Nachrichten, Mindestversion (Require/Has), Schema-Version und
                      Migrationskette (Migrate), Datenbank/Login/Befehle/Status eines Moduls über NewModule(opts),
                      abgelöste Funktionen (Deprecated; Stabilitätsregel in docs/ezcore.md)
      Panels.lua      Blizzard-Fenster öffnen und schließen an einer Stelle (OpenPanel, OpenChatWith)
      Locale.lua      Texte (deDE/enUS) und NewLocale für die Module
      Util.lua        Secret Values, Addons, CVars, Zahlen, Text, Atlanten, Gegenstände, Karte, Blenden (FadeTo);
                      Zustand von Spieler und Einheiten (InInstance, UnitIs, Sperren; bis Welle 11 UnitState.lua)
      EquipSlots.lua  Ausrüstungsplätze (Core.EquipSlots) und Gegenstandsart (bis Welle 11 in Util.lua)
      Bags.lua        Taschen: Zahl, freie Plätze, Taschenlisten, jeder belegte Platz (bis Welle 11 in Util.lua)
      Channels.lua    Chat-Sperre, Chatfilter, Gruppenkanal, senden, Emotes, Kanäle (bis Welle 11 in Util.lua)
      Serialize.lua   Export/Import als Text (Serialize/Deserialize), sicher ohne loadstring
      Format.lua      Geld, Zeit, Klassenfarben und -namen
      Names.lua       Spielername und Realm (WoW Forever: Vor- und Nachname), Freunde, Battle.net
      Settings.lua    eine Kategorie „ezCollection“, jedes Modul eine Unterseite; ezCores eigene Schalter
                      (ParentPage, OwnDefaults, OwnCheckbox, ResetOwnSettings)
      Slash.lua       freie Befehle finden, Schalter, Hilfe, Charaktere auflisten und vergessen
      Widgets.lua     Dialoge, Tooltips, Häkchen, Seitenreiter (mit Stapel), Andocken, Fensterposition,
                      Erklärblasen und Rundgang
      Highlight.lua   Leuchtfarben (GLOW_KINDS), ActionHighlight (alte Schnittstelle; bis Welle 11 in Widgets.lua)
      Layout.lua      ein Muster für eigene Fenster, Werkzeugleisten und Menüs (LAYOUT, NewWindow, Toolbar, Menu)
      Graph.lua       Linien-Baustein Core.NewGraph (Preisverläufe; Geometrie als reine Funktion, Ausweichweg ohne CreateLine)
      TextDialog.lua  mehrzeiliger Text-Dialog mit Übernehmen/Abbrechen (vorher ezMacro)
      SpellbookView.lua  eigene Ansicht in Blizzards Zauberbuch (Reiter, Zeilen wie im Original)

      EditMode.lua    Bearbeitungsmodus: offen?, Ein- und Austritt (nur zuhören)
      Mover.lua       Teile verschieben: eine Anbindung an den Bearbeitungsmodus für alle Module
      Characters.lua  Charakterdaten aller Twinks (ezCoreDB.chars)
      Contacts.lua    ein Kontakt-Index (Freunde, Battle.net, Gilde) und Twinks der Battle.net-Freunde (ezChat, ezSocial)
      Inventory.lua   Taschen, Bank, Post, angelegt, Gildenbank (vorher ezBag)
      Mail.lua        Briefkasten: Kopfdaten, Forever-/Retail-Weiche, Posteingang erfassen
      MailQueue.lua   eine Versand-Warteschlange für Textbriefe (ezChat) und Anhänge (ezMail)
      Tooltip.lua     Tooltip-Pipeline für Gegenstände
      KnowledgeData.lua, Knowledge.lua   Item-Wissen (vorher ezBag)
      SlotText.lua    Itemlevel und „BoE“ auf Platzknöpfen (ezBag, ezLoot)
      ErrorList.lua   Fehlerliste zum Kopieren (Unterseite in Blizzards Einstellungen, sonst Fenster)
      Diagnose.lua    /ez debug (Mitschnitt: Ereignisse, Nachrichten, Laufzeit je Zuhörer) und /ez test
                      (Selbsttest: Vorlagen, Atlanten, APIs, Anmeldungen der Module über Core.AddSelfTest und
                      Daten-Zeilen; bis Welle 11 SelfTests.lua)
      Probe.lua, ProbeStations.lua   /ez probe (Daten-Probe: was antwortet der Client wirklich? Stationen, Mitschnitt
                      der Ereignisse, Tempo-Messung, Dokumentation des Clients; Ablage ezCoreDB.probe)
      Backup.lua      alle Einstellungen der Module als ein Text sichern und übernehmen
      FirstStart.lua  Erster Start: Übersicht (Module, fremde Addons, Vortritt), Rundgang, alle Erklärblasen neu
      ConsentNews.lua Nachfrage nach einem Update: nur die Zeilen der Einführung, die neu dazukamen (Core.Intro)
      Comfort.lua     Abschnitt „Komfort“: Beta-Hinweise ausblenden, Kamera weiter herauszoomen, CVar-Schalter
      MoveFrames.lua  Blizzard-Fenster an der Titelleiste verschieben (Mover, Teil 2) und skalieren
      Keys.lua        Tasten-Dienst: Einträge in Blizzards Tastaturbelegung (mit Bindings.xml)
      UnitTooltip.lua Tooltip-Pipeline für Einheiten und eingebaute Zeilen (Leben, Ziel, Gildenrang, Beziehung,
                      Ø-Itemlevel und Spezialisierung über „Betrachten“, Klassenfarbe, NPC-ID)
      Gathering.lua   Eigene Sammel-Fundorte und Bezugsquellen im Tooltip: Fundorte aus eigenen Ernten,
                      „Beute von“, „Händler“
      Collections.lua Item-Wissen für Sammlungen (Reittier, Haustier, Spielzeug, Aussehen) und Bibliotheksbücher
      Recipes.lua     Rezept-Wissen über alle Twinks: wer kann es, Skill-Stufen, Quelle
      Prices.lua      Preis-Wissen aus Blizzards Auktionshaus (Komplett-Scan, Suchen, Übersicht)
      History.lua     Verlauf: Beute, Gold, Post, Auktionen (ezCore erfasst, Module zeigen an)
      DungeonData.lua, Dungeons.lua   Dungeon- und Zonen-Tabelle: Gruppensuche, Kürzel, Stufen, Eingänge
      SpellData.lua, Spells.lua   Zauber-Wissen: Namen (Core.SpellName, bis Welle 11 in Util.lua), Ränge, Zauberbuch,
                      Lehrer (vorher ezMacro/ezCombat)
      ActionSlots.lua Aktionsplätze: nutzbare Plätze, Seiten, Blizzards Leisten, Inhalt lesen (ezMacro, ezBars, ezCombat)
      Glow.lua        Leucht-Dienst: ein Leuchtrahmen und eine Tooltip-Zeile je Aktionsknopf (Core.Glow)
      Auras.lua       Auren lesen, geheime gezählt statt verglichen (ezCombat, ezBuff)
      Profiles.lua    Profile je Charakter, Klasse, Spezialisierung, Export/Import (ezBag, ezPanel)
      BarProfiles.lua Leisten-Profile: Aktionsleisten samt Makros und Tasten speichern und laden (ezMacro, ezBars)
      Professions.lua Berufe und Berufs-Abklingzeiten aller Twinks
      Talents.lua     Talentbäume des gespielten Charakters: Punkte je Baum, Hauptbaum (ezCombat, ezTalent)
      Lockouts.lua    Instanz-Sperren aller Twinks, Instanzen der letzten Stunde
      CharData.lua    Gegenstandsstufe je Platz, Währungen, zuletzt geänderte Fraktion je Twink
      Npcs.lua        NPC-Ortswissen: Lehrer und Händler mit Gebiet und Koordinaten
      SalvageData.lua, Salvage.lua   Tabelle „Zerlegen“ (Entzaubern) als Daten
      Durability.lua  Haltbarkeit je Platz, Summe, Reparaturkosten, je Twink gemerkt
      OtherAddOns.lua fremde Addons an einer Stelle erkennen (Rücksicht, Leitlinie 9)
      RotationBuilds.lua  welche Rotation (ezCombat) zu welcher Talentvorlage (ezTalent) gehört, n:m
      ChatBar.lua     gemeinsame Knopfleiste am Chat (ezChat, ezMacro)
      Collection.lua  Übersicht in den Einstellungen (Seite „ezCollection“ samt Unterseite „Charaktere“), /ezcollection

    Die Module erhalten ihre bisherigen ns-Funktionen über ezCore.NewModule; so bleibt ihr Code
    gleich, und die Umsetzung steckt nur noch hier. Taint-sicher: nur hooksecurefunc/HookScript,
    nie Werte in Blizzards Tabellen.
]]

local Core = _G.ezCore or {}
_G.ezCore = Core
Core.ns = ns
Core.name = ADDON
Core.TITLE = "ezCollection"
Core.PREFIX_COLOR = "|cff33ff99"

local modules, moduleOrder = {}, {}
Core.modules, Core.moduleOrder = modules, moduleOrder

---------------------------------------------------------------------------
-- Texte: Deutsch ist die Grundsprache, Englisch für alle anderen Clients
---------------------------------------------------------------------------

-- Liefert eine Text-Tabelle: erst die Sprache des Clients, dann Deutsch, dann fallback (z. B. ezCore.L),
-- zuletzt der Schlüssel selbst.
function Core.NewLocale(de, en, fallback)
    local source = (GetLocale and GetLocale() == "deDE") and de or (en or de)
    return setmetatable({}, {
        __index = function(t, key)
            local value = source[key] or de[key]
            if value == nil and fallback then value = fallback[key] end
            if value == nil then value = key end
            rawset(t, key, value)
            return value
        end,
    })
end

function Core.IsGerman()
    return GetLocale and GetLocale() == "deDE"
end

---------------------------------------------------------------------------
-- Ausgabe
---------------------------------------------------------------------------

-- Ein Absender für die Basis (Gesamtreview 18.11.2026, T18-5): Meldungen von ezCore erscheinen als „ezCollection:“,
-- wie /ez, die Einstellungsseite und ns.Print von ezCore – auch die rund 35 Aufrufe Core.Print(Core.name, …).
-- Core.name („ezCore“) bleibt der Schlüssel für Fehlerliste, Ereignisse und Rundgänge.
function Core.Print(name, msg)
    if name == Core.name then name = Core.TITLE end
    DEFAULT_CHAT_FRAME:AddMessage(Core.PREFIX_COLOR .. tostring(name) .. "|r: " .. tostring(msg))
end

---------------------------------------------------------------------------
-- Fehler-Log: Beim Einloggen zeigt WoW Fehler oft nicht an. ezCore merkt sie sich
-- (ezCoreDB.errors, die letzten 50, über /reload hinweg) und je Modul für diese Sitzung.
---------------------------------------------------------------------------

local MAX_LOG, MAX_SESSION = 50, 20
local pendingLog = {}   -- Fehler vor dem Laden von ezCoreDB
local sessionStart = time and time() or 0   -- ab hier „neu in dieser Sitzung“ (auch nach /reload)
local notifying = false
local seenErrors = {}        -- Modul + Text → true: in dieser Sitzung schon gemeldet (Blizzards Anzeige nur einmal)
local REPEAT_NOTICE = 1      -- Sekunden: Wiederholungen melden ERRORS_CHANGED höchstens so oft
local lastRepeatNotice

-- Nachricht ERRORS_CHANGED; ein Fehler in einem Zuhörer löst sie nicht erneut aus.
local function ErrorsChanged()
    if notifying or not Core.Fire then return end
    notifying = true
    pcall(Core.Fire, "ERRORS_CHANGED")
    notifying = false
end

-- Gleiche Meldung (Modul + Text) am vorhandenen Eintrag zählen statt neu eintragen: n = wie oft, t = zuletzt.
-- Ein Dauerfehler (jeder Frame) verdrängt so nicht die anderen Einträge. toFront: Eintrag nach vorn (neueste zuerst).
local function CountRepeat(list, entry, toFront)
    for i = 1, #list do
        local old = list[i]
        if type(old) == "table" and old.m == entry.m and old.e == entry.e then
            old.n = (tonumber(old.n) or 1) + (tonumber(entry.n) or 1)
            old.t = math.max(tonumber(old.t) or 0, tonumber(entry.t) or 0)
            if toFront and i > 1 then
                table.remove(list, i)
                table.insert(list, 1, old)
            end
            return true
        end
    end
    return false
end

-- true, wenn ein neuer Eintrag entstand (false: nur gezählt oder kein Platz mehr).
local function LogEntry(entry)
    local db = _G.ezCoreDB
    if type(db) ~= "table" then
        if CountRepeat(pendingLog, entry) or #pendingLog >= MAX_LOG then return false end
        pendingLog[#pendingLog + 1] = entry
        return true
    end
    db.errors = db.errors or {}
    if CountRepeat(db.errors, entry, true) then return false end
    table.insert(db.errors, 1, entry)
    for i = #db.errors, MAX_LOG + 1, -1 do db.errors[i] = nil end
    return true
end

-- Text eines Eintrags für Listen: ab dem zweiten Auftreten mit Zähler („… (×3)“).
function Core.ErrorLabel(entry)
    local text = tostring(type(entry) == "table" and entry.e or "?")
    local n = type(entry) == "table" and tonumber(entry.n) or 1
    if n > 1 then text = text .. " (×" .. n .. ")" end
    return text
end

function Core.FlushErrorLog()
    if type(_G.ezCoreDB) ~= "table" then return end
    for i = #pendingLog, 1, -1 do LogEntry(pendingLog[i]) end
    wipe(pendingLog)
end

-- Fehler eines Moduls melden: Log, Sitzungsliste, optional eigener Speicher, dann Blizzards Fehleranzeige.
-- Entprellt: dieselbe Meldung (Modul + Text) wird nur beim ersten Auftreten der Sitzung in die Sitzungsliste, den
-- eigenen Speicher und Blizzards Anzeige gegeben; danach zählt nur noch der Eintrag im Log (n), und ERRORS_CHANGED
-- kommt für Wiederholungen höchstens einmal je Sekunde (Aufrufer sitzen in OnUpdate und im Ereignisverteiler).
-- quiet = true: nur Log und Sitzungsliste, Blizzards Fehleranzeige bleibt zu (Core.Call im Diagnosemodus, W-08).
-- stack (freiwillig): der Aufrufstapel an der Fehlerstelle (Core.PCallStack); er steht beim ersten Eintrag im Feld s
-- (gekürzt auf Core.ERROR_STACK_MAX Zeichen) und kommt mit in die Fehlerliste zum Kopieren (Gesamtreview 18.11.2026,
-- T7-2 – vorher sah BugSack nur den Stapel von Core.Error).
Core.ERROR_STACK_MAX = 800
function Core.Error(name, err, where, quiet, stack)
    local text = where and (tostring(where) .. ": " .. tostring(err)) or tostring(err)
    local id = tostring(name) .. "\031" .. text
    local first = not seenErrors[id]
    seenErrors[id] = true
    local mod = modules[name]
    if mod and first then
        if #mod.problems < MAX_SESSION then mod.problems[#mod.problems + 1] = text end
        if mod.onError then pcall(mod.onError, text) end
    end
    local entry = { t = time and time() or 0, m = tostring(name), e = text }
    if type(stack) == "string" and stack ~= "" then entry.s = stack:sub(1, Core.ERROR_STACK_MAX) end
    local added = LogEntry(entry)
    if added or first then
        ErrorsChanged()
    else
        local now = GetTime and GetTime() or 0
        if not lastRepeatNotice or now - lastRepeatNotice >= REPEAT_NOTICE or now < lastRepeatNotice then
            lastRepeatNotice = now
            ErrorsChanged()
        end
    end
    -- Blizzards Fehleranzeige bzw. BugSack/BugGrabber bekommen den Stapel der Fehlerstelle mit (ihr eigener Stapel zeigt
    -- nur Core.Error und den Verteiler; Gegenprüfung P19a zu T7-2).
    if first and not quiet then geterrorhandler()(Core.ErrorWithStack(text, entry.s)) end
end

-- Text für die Fehleranzeige: Meldung, darunter der Stapel der Fehlerstelle (falls bekannt).
function Core.ErrorWithStack(text, stack)
    text = tostring(text)
    if type(stack) ~= "string" or stack == "" then return text end
    return text .. "\n" .. stack
end

--[[
    Core.PCallStack(fn, …) → wie pcall, merkt sich bei einem Fehler aber den Aufrufstapel an der Fehlerstelle
      (xpcall mit debugstack; Gesamtreview 18.11.2026, T7-2). Core.TakeErrorStack() → dieser Stapel (einmal, danach
      nil). Kennt der Client kein xpcall mit Argumenten oder kein debugstack, ist es pcall ohne Stapel.
    Genutzt vom Ereignisverteiler, Core.Try, ns.Try, Core.Throttle und Core.AfterCombat.
]]
local lastStack
local function StackHandler(err)
    local stack = rawget(_G, "debugstack")
    lastStack = nil
    if type(stack) == "function" then
        local ok, text = pcall(stack, 2, 12, 0)
        if ok and type(text) == "string" then lastStack = text end
    end
    return err
end
-- Reicht xpcall(f, handler, a) a an f weiter (LuaJIT, WoW)? Lua 5.1 ohne Erweiterung ruft f ohne Argumente.
local xpcallArgs
do
    local ok, okInner, value = pcall(xpcall, function(a) return a end, StackHandler, 1)
    xpcallArgs = ok and okInner == true and value == 1
end
function Core.PCallStack(fn, ...)
    if xpcallArgs then return xpcall(fn, StackHandler, ...) end
    return pcall(fn, ...)
end
function Core.TakeErrorStack()
    local s = lastStack
    lastStack = nil
    return s
end

-- Rückruf geschützt ausführen (W-08): Ein Fehler steht immer in der Fehlerliste von owner (Standard ezCore), nicht
-- nur im Diagnosemodus – für Rückrufe der Module, Timer und Hooks, die ezCore für andere ruft (vorher blanke
-- pcall, deren Fehler niemand sah). → ok, Ergebnisse. Keine Funktion: false. Seit T7-2 mit Aufrufstapel.
local function TryResult(owner, where, ok, ...)
    if ok then return true, ... end
    Core.Error(owner or ADDON, (...), where, nil, Core.TakeErrorStack())
    return false
end

function Core.Try(owner, where, fn, ...)
    if type(fn) ~= "function" then return false end
    return TryResult(owner, where, Core.PCallStack(fn, ...))
end

-- Alle gemerkten Fehler (neueste zuerst), optional nur eines Moduls.
function Core.Errors(name)
    local list = {}
    local db = _G.ezCoreDB
    for _, entry in ipairs(type(db) == "table" and db.errors or pendingLog) do
        if not name or entry.m == name then list[#list + 1] = entry end
    end
    return list
end

function Core.ClearErrors()
    if type(_G.ezCoreDB) == "table" then _G.ezCoreDB.errors = {} end
    wipe(pendingLog)
    wipe(seenErrors)   -- nach dem Leeren zählt jede Meldung wieder als neu
    lastRepeatNotice = nil
    ErrorsChanged()
end

-- Zähler (z. B. für ezPanel): alle gemerkten Fehler und davon die aus dieser Sitzung, optional nur eines Moduls.
function Core.ErrorCount(name)
    local list = Core.Errors(name)
    local new = 0
    for _, e in ipairs(list) do
        if (tonumber(e.t) or 0) >= sessionStart then new = new + 1 end
    end
    return #list, new
end

---------------------------------------------------------------------------
-- Ereignisse: ein Frame für alle Module. Die Reihenfolge der Anmeldung bleibt erhalten,
-- ezCore selbst ist immer zuerst dran (es lädt vor den Modulen).
-- Mit Einheiten-Filter (UNIT_AURA nur für „player“ …) hängt der Zuhörer an eigenen Rahmen (je zwei Einheiten
-- einer), die Blizzard über RegisterUnitEvent nur für diese Einheiten weckt; der Verteiler prüft die Einheit
-- zusätzlich. Eine gesperrte Einheit zählt dabei als Treffer – der Zuhörer braucht keinen eigenen Vergleich, und
-- wenn er doch vergleicht (zwei Einheiten), dann erst nach ns.IsSecret (Leitlinie 6).
---------------------------------------------------------------------------

local buses = {}        -- [1] = Hauptrahmen (ohne Filter), danach je Einheitenpaar einer
local unitBuses = {}    -- "player,target" → Bus

-- Geheime Einheit: nicht vergleichen, zustellen (der Zuhörer bekam sie bisher auch).
local function UnitMatches(units, unit)
    if issecretvalue and issecretvalue(unit) then return true end
    return type(unit) == "string" and units[unit] == true
end

-- Messfühler für den Mitschnitt (/ez debug, Diagnose.lua): solange einer gesetzt ist, meldet der Verteiler je
-- Zuhörer Art ("event" | "message"), Name, Besitzer und Laufzeit in Millisekunden (debugprofilestop) und je
-- gesendeter Nachricht ("fire", Name). Ohne Fühler kostet das einen Vergleich je Aufruf. Werte des Ereignisses
-- werden nie weitergereicht (sie können gesperrt sein).
local probe, probeClock
function Core.SetProbe(fn)
    probe = type(fn) == "function" and fn or nil
    probeClock = rawget(_G, "debugprofilestop")
    if type(probeClock) ~= "function" then
        probeClock = function() return (GetTime and GetTime() or 0) * 1000 end
    end
    return probe ~= nil
end
function Core.Probing() return probe ~= nil end

local function Dispatch(bus, event, ...)
    local list = bus.handlers[event]
    if not list then return end
    for i = 1, #list do
        local entry = list[i]
        if entry and not entry.dead and (not entry.units or UnitMatches(entry.units, ...)) then
            local ok, err
            -- mit Aufrufstapel an der Fehlerstelle (Core.PCallStack, T7-2)
            if probe then
                local t0 = probeClock()
                ok, err = Core.PCallStack(entry.fn, event, ...)
                pcall(probe, "event", event, entry.owner, probeClock() - t0)
            else
                ok, err = Core.PCallStack(entry.fn, event, ...)
            end
            if not ok then Core.Error(entry.owner, err, event, nil, Core.TakeErrorStack()) end
        end
    end
end

local function NewBus(units)
    local bus = { frame = CreateFrame("Frame"), handlers = {}, units = units }
    bus.frame:SetScript("OnEvent", function(_, event, ...) Dispatch(bus, event, ...) end)
    buses[#buses + 1] = bus
    return bus
end

local mainBus = NewBus()

-- "player" | { "player", "target" } | { player = true } → Menge, sortierte Liste (nil ohne Einheiten)
local function UnitSet(units)
    if units == nil then return nil end
    local set, list = {}, {}
    if type(units) == "string" then
        set[units] = true
    elseif type(units) == "table" then
        for key, value in pairs(units) do
            if type(key) == "number" and type(value) == "string" then
                set[value] = true
            elseif type(key) == "string" and value then
                set[key] = true
            end
        end
    end
    for unit in pairs(set) do list[#list + 1] = unit end
    if #list == 0 then return nil end
    table.sort(list)
    return set, list
end

-- Rahmen mit Blizzards RegisterUnitEvent für einen Einheitensatz: eine oder zwei Einheiten je Rahmen (mehr nimmt
-- RegisterUnitEvent nicht). Größere Sätze werden in Paare geteilt (T8-3, Gesamtreview 18.11.2026; so macht es
-- Blizzard je Einheitenrahmen): Dann filtert der Client auch 45 Einheiten (ezBuff: player, party1-4, raid1-40),
-- und eine Namensplakette weckt den Verteiler nicht – auch nicht im Kampf, wenn die Einheit gesperrt ankommt.
-- → Liste der Busse, die jetzt auf das Ereignis hören | nil, wenn ein Rahmen das Ereignis nicht annimmt (dann ist
-- in diesem Aufruf nichts angemeldet geblieben, der Hauptrahmen mit Filter übernimmt).
local function UnitBusesFor(event, list)
    local result, fresh = {}, {}
    for i = 1, #list, 2 do
        local pair = { list[i], list[i + 1] }
        local key = table.concat(pair, ",")
        local unitBus = unitBuses[key]
        if not unitBus then
            unitBus = NewBus(pair)
            unitBuses[key] = unitBus
        end
        if not unitBus.handlers[event] then
            if type(unitBus.frame.RegisterUnitEvent) ~= "function"
                or not pcall(unitBus.frame.RegisterUnitEvent, unitBus.frame, event, pair[1], pair[2]) then
                for _, bus in ipairs(fresh) do
                    bus.handlers[event] = nil
                    pcall(bus.frame.UnregisterEvent, bus.frame, event)
                end
                return nil
            end
            unitBus.handlers[event] = {}
            fresh[#fresh + 1] = unitBus
        end
        result[#result + 1] = unitBus
    end
    return result
end

-- Unbekannte Events (z. B. auf einem anderen Client) dürfen das Addon nicht stoppen: dann false.
-- units (optional): Einheit, Liste oder Menge – fn läuft nur, wenn der erste Wert des Ereignisses eine davon ist.
-- Ein Zuhörer mit mehr als zwei Einheiten steht als derselbe Eintrag in mehreren Bussen (je Paar einer); der Client
-- stellt ein Ereignis nur dem Rahmen zu, dessen Einheit es nennt – der Zuhörer läuft also einmal je Ereignis.
function Core.RegisterEvent(owner, event, fn, units)
    if type(fn) ~= "function" or type(event) ~= "string" then return false end
    local set, list = UnitSet(units)
    local entry = { fn = fn, owner = owner, units = set }
    local targets = set and UnitBusesFor(event, list)
    if targets then
        for _, bus in ipairs(targets) do table.insert(bus.handlers[event], entry) end
        return true
    end
    if not mainBus.handlers[event] then
        if not pcall(mainBus.frame.RegisterEvent, mainBus.frame, event) then return false end
        mainBus.handlers[event] = {}
    end
    table.insert(mainBus.handlers[event], entry)
    return true
end

-- Wie RegisterEvent, die Einheiten vorn (V-042): Core.RegisterUnitEvent("ezCombat", "UNIT_AURA", "player", fn).
function Core.RegisterUnitEvent(owner, event, units, fn)
    return Core.RegisterEvent(owner, event, fn, units)
end

-- Abmelden: alle Zuhörer von owner für das Ereignis, mit fn nur dieser. → Anzahl abgemeldeter Zuhörer.
-- Darf aus einem Zuhörer heraus gerufen werden: die laufende Runde überspringt abgemeldete, die Liste wird ersetzt
-- statt verändert. Hört niemand mehr zu, meldet ezCore das Ereignis auch bei Blizzard ab.
function Core.UnregisterEvent(owner, event, fn)
    local removed, counted = 0, {}
    for b = 1, #buses do
        local bus = buses[b]
        local list = bus.handlers[event]
        if list then
            local keep, gone = {}, 0
            for i = 1, #list do
                local entry = list[i]
                if entry.owner == owner and (fn == nil or entry.fn == fn) then
                    entry.dead = true
                    gone = gone + 1
                    -- derselbe Eintrag in mehreren Bussen (Paare, siehe RegisterEvent) zählt einmal
                    if not counted[entry] then
                        counted[entry] = true
                        removed = removed + 1
                    end
                else
                    keep[#keep + 1] = entry
                end
            end
            if gone > 0 then
                if #keep > 0 then
                    bus.handlers[event] = keep
                else
                    bus.handlers[event] = nil
                    pcall(bus.frame.UnregisterEvent, bus.frame, event)
                end
            end
        end
    end
    return removed
end

-- Hört owner (oder irgendwer) auf das Ereignis? Für Tests und /dump.
function Core.EventRegistered(event, owner)
    for b = 1, #buses do
        local list = buses[b].handlers[event]
        for i = 1, list and #list or 0 do
            if owner == nil or list[i].owner == owner then return true end
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Nachrichten zwischen den Modulen (z. B. INVENTORY_CHANGED, MAIL_QUEUE_CHANGED, CHAR_FORGOTTEN).
-- Verzeichnis aller Namen: Core.MESSAGES (Framework.lua).
---------------------------------------------------------------------------

local listeners = {}

function Core.Listen(message, fn, owner)
    if type(fn) ~= "function" then return false end
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], { fn = fn, owner = owner or ADDON })
    return true
end

-- Abmelden: Core.Unlisten(nachricht, fn) – genau dieser Zuhörer; Core.Unlisten(nachricht, nil, owner) – alle des
-- Besitzers. → Anzahl. Darf aus einem Zuhörer heraus gerufen werden (wie UnregisterEvent).
function Core.Unlisten(message, fn, owner)
    local list = listeners[message]
    if not list or (fn == nil and owner == nil) then return 0 end
    local keep, gone = {}, 0
    for i = 1, #list do
        local entry = list[i]
        if (fn == nil or entry.fn == fn) and (owner == nil or entry.owner == owner) then
            entry.dead = true
            gone = gone + 1
        else
            keep[#keep + 1] = entry
        end
    end
    if gone > 0 then listeners[message] = #keep > 0 and keep or nil end
    return gone
end

-- Hört jemand auf die Nachricht? (Dann lohnt es, Daten dafür sofort aufzubereiten, z. B. CONTACTS_CHANGED.)
function Core.Listening(message)
    local list = listeners[message]
    return list ~= nil and #list > 0
end

function Core.Fire(message, ...)
    if probe then pcall(probe, "fire", message) end
    local list = listeners[message]
    if not list then return end
    for i = 1, #list do
        local entry = list[i]
        if entry and not entry.dead then
            local ok, err
            if probe then
                local t0 = probeClock()
                ok, err = pcall(entry.fn, ...)
                pcall(probe, "message", message, entry.owner, probeClock() - t0)
            else
                ok, err = pcall(entry.fn, ...)
            end
            if not ok then Core.Error(entry.owner, err, message) end
        end
    end
end

---------------------------------------------------------------------------
-- Nach dem Kampf nachholen (V-010): EINE Warteschlange statt eines eigenen Merkers je Datei.
---------------------------------------------------------------------------

local afterQueue, afterByKey = {}, {}

local function Locked()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
end

--[[
    Core.AfterCombat(fn, key, owner) → true: sofort gelaufen (kein Kampf) | false: wartet bis PLAYER_REGEN_ENABLED.
      key (optional)  derselbe Schlüssel ersetzt den wartenden Aufruf (nur der letzte läuft, an der alten Stelle der
                      Reihe); ohne Schlüssel wartet jeder Aufruf für sich
      owner           Modul für die Fehlerliste (Standard ezCore); Fehler in fn brechen die Reihe nicht ab
    Die Reihenfolge der Anmeldung bleibt erhalten. ezGears alte Form (key, fn) wird auch verstanden.
    Module nutzen ns.AfterCombat(fn, key) – der Schlüssel gilt dann nur im Modul.
]]
function Core.AfterCombat(fn, key, owner)
    if type(fn) ~= "function" and type(key) == "function" then fn, key = key, fn end
    if type(fn) ~= "function" then return false end
    local waiting = key ~= nil and afterByKey[key] or nil
    if not Locked() then
        if waiting then
            waiting.cancelled = true
            afterByKey[key] = nil
        end
        local ok, err = Core.PCallStack(fn)
        if not ok then Core.Error(owner or ADDON, err, "AfterCombat", nil, Core.TakeErrorStack()) end
        return true
    end
    if waiting then
        waiting.fn, waiting.owner = fn, owner or waiting.owner
        return false
    end
    local entry = { fn = fn, key = key, owner = owner }
    afterQueue[#afterQueue + 1] = entry
    if key ~= nil then afterByKey[key] = entry end
    return false
end

-- Wartenden Aufruf streichen. → true, wenn einer wartete.
function Core.CancelAfterCombat(key)
    local entry = key ~= nil and afterByKey[key] or nil
    if not entry then return false end
    entry.cancelled = true
    afterByKey[key] = nil
    return true
end

-- Wartet ein Aufruf mit diesem Schlüssel? Ohne Schlüssel: Anzahl aller wartenden.
function Core.AfterCombatWaiting(key)
    if key ~= nil then return afterByKey[key] ~= nil end
    local count = 0
    for i = 1, #afterQueue do
        if not afterQueue[i].cancelled then count = count + 1 end
    end
    return count
end

-- Die Reihe abarbeiten (intern, bei PLAYER_REGEN_ENABLED). → Anzahl gelaufener Aufrufe.
function Core.RunAfterCombat()
    if Locked() or #afterQueue == 0 then return 0 end
    local list = afterQueue
    afterQueue = {}
    -- afterByKey bleibt bis zum Lauf des jeweiligen Eintrags gültig: Ruft ein früherer Eintrag AfterCombat oder
    -- CancelAfterCombat mit dem Schlüssel eines späteren, ersetzt bzw. streicht das den späteren (Fund der Prüfung)
    local ran = 0
    for i = 1, #list do
        local entry = list[i]
        if entry.key ~= nil and afterByKey[entry.key] == entry then afterByKey[entry.key] = nil end
        if not entry.cancelled then
            ran = ran + 1
            local ok, err = Core.PCallStack(entry.fn)
            if not ok then Core.Error(entry.owner or ADDON, err, "AfterCombat", nil, Core.TakeErrorStack()) end
        end
    end
    return ran
end

-- Zuerst angemeldet: läuft vor allen anderen Zuhörern auf das Kampfende (ezCore und Module).
Core.RegisterEvent(ADDON, "PLAYER_REGEN_ENABLED", function() Core.RunAfterCombat() end)

---------------------------------------------------------------------------
-- Gespeicherte Werte
---------------------------------------------------------------------------

-- Fehlende Werte aus defaults ergänzen (Tabellen rekursiv). strictType: Werte falschen Typs ersetzen.
function Core.FillDefaults(target, defaults, strictType)
    for key, value in pairs(defaults) do
        local current = target[key]
        if current == nil or (strictType and type(current) ~= type(value)) then
            if type(value) == "table" then
                target[key] = {}
                Core.FillDefaults(target[key], value, strictType)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(current) == "table" then
            Core.FillDefaults(current, value, strictType)
        end
    end
    return target
end

---------------------------------------------------------------------------
-- Modul-Gerüst: gibt jedem Modul seine gewohnten ns-Funktionen
---------------------------------------------------------------------------

--[[
    ezCore.NewModule(name, ns, opts) setzt in ns:
      Print(msg), Error(err, where), Try(where, fn, ...), problems
      On(event, fn), Listen(msg, fn), Fire(msg, ...)            (Listen/Fire nur innerhalb des Moduls)
      Off(event, fn) → Anzahl abgemeldeter Zuhörer (ohne fn alle des Moduls), Unlisten(msg, fn),
      OnUnit(event, einheiten, fn) (nur für diese Einheiten, z. B. "player" oder { "player", "target" })
      AfterCombat(fn, key) → true sofort gelaufen | false wartet bis zum Kampfende (Core.AfterCombat)
      AddStatusLine(text | fn), StatusLines(), PrintStatus(), TourStore(feld)   (nur, wenn das Modul sie nicht selbst hat)
      OnReady(fn), RunReady(), OnLogout(fn), RunLogout()
      OnSettingChanged(fn), SettingChanged(key), SetSetting(key, value)
      IsSecret(wert), Num(wert), Plain(wert), InCombat(), IsLoaded(addon)   Abkürzungen auf Core.* (W-14)
      OtherFor(funktion) → Name, Schlüssel des fremden Addons, das sie übernimmt (Core.WhoHandles), sonst nil
      OtherInfo(funktion) → wie OtherFor, zählt aber kein „gewichen“ (Core.WhoHandlesInfo; reine Hinweise, I2)
      NoteSecret(art), secretSeen, SecretLine() → „Zuletzt gesperrte Daten: …“ oder nil; StatusHeader() → Kopfzeile
      Enabled(key) → ns.S[key] == true, Throttle(fn, delay), WhenAddOnLoaded(addon, fn)   (vorher in bis zu zehn
                 Modulen kopiert; ein Modul darf sie weiter selbst setzen)
      Core (= ezCore)
    opts.onError(text): zusätzlich eigener Fehlerspeicher (ezChat: ezChatDB.errors)
    opts.title: Anzeigename (Standard: name)
    opts.core = "1.9.0", opts.needs = { "AfterCombat", "Glow.Set" }: Mindestversion bzw. Fähigkeiten von ezCore
        (Core.Require); fehlt etwas, meldet ezCore es einmal im Chat und in /ez status, und das Modul bleibt still:
        RunReady und onLoad laufen nicht, ns.On/OnUnit/Listen melden nichts an, seine Befehle nennen nur den Grund
        (Gesamtreview 18.11.2026, T4-3).
    opts.db, defaults, tables, schema, migrations, onLoad, login, slash, statusHead: das Gerüst, das sonst jedes
        Modul selbst schreibt (Framework.lua, Core.ModuleScaffold) – alles freiwillig, ohne Angabe ändert sich nichts.
]]
function Core.NewModule(name, mns, opts)
    opts = opts or {}
    local mod = modules[name]
    if not mod then
        mod = { name = name }
        modules[name] = mod
        moduleOrder[#moduleOrder + 1] = name
    end
    mod.ns, mod.title, mod.onError = mns, opts.title or name, opts.onError
    mod.problems = {}
    local readyList, logoutList, settingList, localListeners = {}, {}, {}, {}
    mod.ready = false

    mns.Core = Core
    mns.moduleName = name
    mns.problems = mod.problems

    function mns.Print(msg) Core.Print(mod.title, msg) end
    function mns.Error(err, where) Core.Error(name, err, where) end

    function mns.Try(where, fn, ...)
        local ok, err = Core.PCallStack(fn, ...)
        if not ok then Core.Error(name, err, where, nil, Core.TakeErrorStack()) end
        return ok
    end

    -- Ein gesperrtes Modul (ezCore zu alt, mod.blocked) ist still (Gesamtreview 18.11.2026, T4-3): seine Ereignis- und
    -- Nachrichten-Zuhörer werden nicht angemeldet, das Gerüst lässt onLoad aus, und seine Befehle nennen nur den Grund.
    -- Vorher lief alles außer RunReady weiter. Das Gerüst selbst meldet seine Zuhörer über Core.RegisterEvent an
    -- (Datenbank laden), die bleiben.
    function mns.On(event, fn)
        if mod.blocked then return false end
        return Core.RegisterEvent(name, event, fn)
    end
    function mns.OnUnit(event, units, fn)
        if mod.blocked then return false end
        return Core.RegisterEvent(name, event, fn, units)
    end
    function mns.Off(event, fn) return Core.UnregisterEvent(name, event, fn) end

    function mns.Listen(message, fn)
        if mod.blocked then return end
        localListeners[message] = localListeners[message] or {}
        table.insert(localListeners[message], fn)
    end

    -- Liste ersetzen statt verändern: eine laufende Fire-Runde bleibt heil.
    function mns.Unlisten(message, fn)
        local list = localListeners[message]
        if not list then return 0 end
        local keep, gone = {}, 0
        for i = 1, #list do
            if fn == nil or list[i] == fn then gone = gone + 1 else keep[#keep + 1] = list[i] end
        end
        localListeners[message] = #keep > 0 and keep or nil
        return gone
    end

    -- In der laufenden Runde abgemeldete Zuhörer laufen nicht mehr (wie bei Core.Unlisten): Unlisten ersetzt die Liste,
    -- also läuft nur, was in der aktuellen Liste noch steht.
    local function StillListening(message, list, fn)
        local now = localListeners[message]
        if now == list then return true end
        for i = 1, #(now or {}) do
            if now[i] == fn then return true end
        end
        return false
    end

    function mns.Fire(message, ...)
        local list = localListeners[message]
        if not list then return end
        for i = 1, #list do
            if StillListening(message, list, list[i]) then mns.Try(message, list[i], ...) end
        end
    end

    function mns.OnReady(fn)
        if mod.ready then
            mns.Try("OnReady", fn)
        else
            table.insert(readyList, fn)
        end
    end

    function mns.RunReady()
        if mod.blocked then return false end   -- ezCore ist zu alt für das Modul (opts.core/opts.needs): gemeldet
        mod.ready = true
        for _, fn in ipairs(readyList) do mns.Try("OnReady", fn) end
    end

    function mns.OnLogout(fn) table.insert(logoutList, fn) end
    function mns.RunLogout()
        for _, fn in ipairs(logoutList) do mns.Try("OnLogout", fn) end
    end

    -- Ein Schlüssel aus mns.SHARED (Core.ShareSettings, Settings.lua) liest bzw. setzt den gemeinsamen Schalter von ezCore
    -- (Einstellungs-Prüfung 19.11.2026) – der Code des Moduls bleibt bei ns.Enabled(key) und ns.SetSetting(key, wert).
    if mns.Enabled == nil then
        mns.Enabled = function(key)
            local shared = type(mns.SHARED) == "table" and mns.SHARED[key]
            if shared then return Core.SharedOn(shared[1], shared[2]) end
            return mns.S ~= nil and mns.S[key] == true
        end
    end
    if mns.Throttle == nil then mns.Throttle = function(fn, delay) return Core.Throttle(fn, delay, name) end end
    -- Dauer-Takt mit Griff, Fehler in der Fehlerliste des Moduls (Core.Ticker, Gesamtreview 18.11.2026, T7-3)
    if mns.Ticker == nil then
        mns.Ticker = function(seconds, fn, active, where) return Core.Ticker(name, seconds, fn, active, where) end
    end
    if mns.WhenAddOnLoaded == nil then mns.WhenAddOnLoaded = function(addon, fn) Core.WhenAddOnLoaded(addon, fn, name) end end
    -- Der Schlüssel gilt nur im Modul ("ezGear:swap"); ezGears alte Form (key, fn) wird auch verstanden.
    if mns.AfterCombat == nil then
        mns.AfterCombat = function(fn, key)
            if type(fn) ~= "function" and type(key) == "function" then fn, key = key, fn end
            return Core.AfterCombat(fn, key ~= nil and (name .. ":" .. tostring(key)) or nil, name)
        end
    end

    function mns.OnSettingChanged(fn) table.insert(settingList, fn) end
    function mns.SettingChanged(key)
        for _, fn in ipairs(settingList) do mns.Try(key, fn, key) end
    end

    -- Wert passend zum Standard: Zahl bleibt Zahl, Schalter bleibt true/false, sonst unverändert.
    function mns.SetSetting(key, value)
        local shared = type(mns.SHARED) == "table" and mns.SHARED[key]
        if shared then
            -- gemeinsamer Schalter: ezCore führt den Wert; die Nachricht OWN_SETTING_CHANGED ruft mns.SettingChanged(key)
            Core.SetShared(shared[1], shared[2], value and true or false)
            return
        end
        local default = mns.DEFAULTS and mns.DEFAULTS[key]
        if type(default) == "number" then
            value = tonumber(value) or default
        elseif type(default) == "boolean" then
            value = value and true or false
        end
        mns.S[key] = value
        mns.SettingChanged(key)
    end

    -- Abkürzungen (W-14), nur soweit das Modul sie nicht selbst setzt. Bei jedem Aufruf über Core nachgeschlagen:
    -- ezCore meldet sich an, bevor Util.lua geladen ist, und Tests tauschen Core.IsSecret aus.
    if mns.IsSecret == nil then mns.IsSecret = function(value) return Core.IsSecret(value) end end
    if mns.Num == nil then mns.Num = function(value) return Core.Num(value) end end
    if mns.Plain == nil then mns.Plain = function(value) return Core.Plain(value) end end
    if mns.InCombat == nil then mns.InCombat = function() return Core.InCombat() end end
    if mns.IsLoaded == nil then mns.IsLoaded = function(addon) return Core.IsLoaded(addon) end end
    -- Welches fremde Addon übernimmt die Funktion? → Name, Schlüssel; nil: keines (Core.WhoHandles ist innen gesichert).
    if mns.OtherFor == nil then
        mns.OtherFor = function(feature)
            if type(Core.WhoHandles) ~= "function" then return nil end
            return Core.WhoHandles(feature)
        end
    end
    -- Nur Auskunft (Hinweis am Schalter, das Modul bleibt an): zählt nicht als „gewichen“ (Gegenprüfung zu I2,
    -- Gesamtreview 18.11.2026).
    if mns.OtherInfo == nil then
        mns.OtherInfo = function(feature)
            if type(Core.WhoHandlesInfo) ~= "function" then return nil end
            return Core.WhoHandlesInfo(feature)
        end
    end
    -- Gesperrte Daten merken (vorher je in ezBuff und ezCombat): ns.NoteSecret("auras") hält fest, wann das Spiel
    -- zuletzt einen Wert dieser Art sperrte; ns.SecretLine() macht daraus die Statuszeile (Framework.lua).
    if mns.secretSeen == nil then mns.secretSeen = {} end
    if mns.NoteSecret == nil then
        mns.NoteSecret = function(what)
            if Core.IsSecret(what) or what == nil then what = "data" end
            mns.secretSeen[tostring(what)] = Core.Uptime()
        end
    end

    -- Mindestversion und Gerüst (Framework.lua; ezCore selbst meldet sich an, bevor die Datei geladen ist)
    if (opts.core or opts.needs) and Core.Require then
        mod.blocked = not Core.Require(name, opts.core, opts.needs)
    end
    if Core.ModuleScaffold then Core.ModuleScaffold(mod, mns, opts) end

    return mod
end

function Core.Module(name) return modules[name] end

-- Schnittstelle eines Moduls für die anderen: Das Modul legt sie als Tabelle in ns.API ab
-- (z. B. ezGear: ns.API = { IsUpgrade = …, Score = … }). Andere fragen ezCore.API("ezGear") –
-- nil, solange das Modul nicht geladen ist oder nichts anbietet. So kennt kein Modul die Interna eines anderen.
function Core.API(name)
    local mod = modules[name]
    local api = mod and mod.ns and mod.ns.API
    return type(api) == "table" and api or nil
end

-- Auskunft eines anderen Moduls, sicher: Core.AskModule(ns, "ezGear", "Status", link) → Antworten der Funktion aus dessen
-- ns.API, nil ohne Modul oder Funktion. Wirft sie, landet der Fehler im Log des fragenden Moduls (ns.Error), Antwort nil.
-- (Durchsicht 24.11.2026: vorher je eine gleiche Hülle in ezAuction, ezMerchant und ezCraft.)
local function Answer(mns, name, fn, ok, ...)
    if ok then return ... end
    if type(mns) == "table" and type(mns.Error) == "function" then
        mns.Error((...), fn .. " (" .. name .. ")")
    end
    return nil
end
function Core.AskModule(mns, name, fn, ...)
    local api = Core.API(name)
    local ask = api and api[fn]
    if type(ask) ~= "function" then return nil end
    return Answer(mns, name, fn, pcall(ask, ...))
end

-- Stand eines Gegenstands laut ezGear (Schnittstelle Status) und Text dazu; „noslot“, wenn ezGear diesen Platz nicht
-- bewertet (Hemd, Wappenrock); nil ohne ezGear, ohne Link oder bei einem Fehler (dann im Log von ns).
function Core.GearStatus(mns, link)
    local api = Core.API("ezGear")
    if not (api and link and type(api.Status) == "function") then return nil end
    local ok, kind, text = pcall(api.Status, link)
    if not ok then
        Answer(mns, "ezGear", "Status", false, kind)
        return nil
    end
    return kind or "noslot", text
end

-- Schützt ezGear diesen Gegenstand vor Verkaufen, Wegwerfen und Zerlegen? true für Ausrüstung mit grünem oder gelbem
-- Pfeil (besser – jetzt oder sobald gelernt bzw. die Stufe reicht) und vorsichtshalber, solange ezGear lädt, der Link
-- fehlt oder die Frage scheitert; false ohne ezGear. Eine Regel für „Platz schaffen“ (ezBag), Plunder (Core.Junk) und
-- Zerlegen (ezCraft). Ein älteres ezGear ohne WorthKeeping kennt nur den grünen Pfeil.
function Core.GearProtects(mns, item, link)
    local api = Core.API("ezGear")
    if not api or not Core.IsEquipment(item) then return false end
    local fn, old = api.WorthKeeping, false
    if type(fn) ~= "function" then fn, old = api.IsUpgrade, true end
    if type(fn) ~= "function" then return false end
    if type(link) ~= "string" or Core.IsSecret(link) then return not old end
    local ok, keep = pcall(fn, link)
    if not ok then
        Answer(mns, "ezGear", old and "IsUpgrade" or "WorthKeeping", false, keep)
        return not old
    end
    if old then return keep == true end
    return keep ~= false
end

-- Version eines Addons aus der TOC.
function Core.Version(addon)
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not meta then return "?" end
    local ok, version = pcall(meta, addon or ADDON, "Version")
    return ok and version or "?"
end

-- ezCore ist selbst ein Modul (Knowledge.lua und die Charakterdaten nutzen ns.On, ns.db, ns.charKey).
Core.NewModule(ADDON, ns, { title = Core.TITLE })

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    if type(ezCoreDB) ~= "table" then ezCoreDB = {} end
    local db = ezCoreDB
    -- Schema-Version (db.schema) und Migrationskette: Core.SCHEMA, Core.MIGRATIONS in Framework.lua
    if Core.Migrate then Core.Migrate(db, Core.SCHEMA, Core.MIGRATIONS, { owner = ADDON }) end

    db.settings = db.settings or {}
    db.chars = db.chars or {}       -- Charakterdaten aller Twinks (Characters.lua)
    db.guilds = db.guilds or {}     -- Gildenbanken: ["Name-Realm"] = { name, realm, faction, tabs, counts, seen }
    db.knowledge = db.knowledge or {}   -- Item-Wissen über alle Twinks (Knowledge.lua)
    db.migrated = db.migrated or {}     -- einmalige Übernahmen aus den Modulen
    db.bnAlts = type(db.bnAlts) == "table" and db.bnAlts or {}   -- Twinks der Battle.net-Freunde (Contacts.lua)
    db.errors = db.errors or {}
    ns.db, ns.S = db, db.settings
    Core.db = db
    Core.FlushErrorLog()
    Core.Fire("CORE_LOADED")
end)
