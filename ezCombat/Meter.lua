local _, ns = ...
local L = ns.L
local Core = ezCore

-- Stufe 2: Blizzards eigene Schadensanzeige erweitern (Blizzard_DamageMeter, lädt auf Forever; Einschalten über
-- die CVar damageMeterEnabled, Lage und Aussehen im Bearbeitungsmodus). Kein zweites Details.
--
-- Was Blizzards Fenster schon kann (geprüft in der Forever-Quelle, Zweig „forever“): Balken in Klassenfarbe,
-- Sitzungen (gesamt, aktuell, frühere Kämpfe mit Dauer), Stile bis „dünn“, Balkenhöhe, Abstand, Textgröße,
-- Einklappen, bis zu drei Fenster, Aufschlüsselung je Zauber, Schaden/DPS/Heilung/HPS/Unterbrechungen/Bannungen/Tode.
-- Was fehlt und ezCombat ergänzt:
--   • Eigene Zeile hervorheben – Blizzard heftet sie nur an, wenn sie aus der Sicht gescrollt ist.
--   • Bericht in den Chat – als Eintrag in Blizzards Zahnrad-Menü des Fensters (Menu.ModifyMenu), dazu ein Knopf
--     in den Einstellungen und /ezk bericht.
--   • Sichtbarer Schalter für die Anzeige selbst (Blizzards Kästchen steckt unter Optionen → Erweitert).
--   • Häkchen „Schaden/Heilung an Gruppenrahmen“ im Zahnrad-Menü (Stufe 3, Anzeige in MeterFrames.lua), dazu die
--     Auswahl des Abschnitts für diese Balken (aktueller Kampf, gesamt, frühere Kämpfe).
--
-- Taint-sicher: hooksecurefunc an InitEntry der Fenster, eigene Texturen in eigenen Tabellen, Blizzards Methoden nur
-- lesend (Getter). Blizzards Daten sind im Kampf geheim (SecretWhenInCombat): Der Bericht geht nur außerhalb des
-- Kampfs; „isLocalPlayer“ ist nie geheim, die Hervorhebung funktioniert also auch im Kampf.
local Meter = {}
ns.Meter = Meter

local CVAR = "damageMeterEnabled"
Meter.CVAR = CVAR
local MAX_WINDOWS = 3
local MENU_TAG = "MENU_DAMAGE_METER_WINDOW_SETTINGS"
local HIGHLIGHT_TEXTURE = "Interface\\Buttons\\UI-Listbox-Highlight2"

local overlays = setmetatable({}, { __mode = "k" })       -- Eintrag → eigene Textur
local hookedWindows = setmetatable({}, { __mode = "k" })
local mixinHooked = false
local menuAdded = false

---------------------------------------------------------------------------
-- Schalter des Spiels
---------------------------------------------------------------------------

function Meter.GameMeterOn()
    return ns.CVarOn(CVAR)
end

function Meter.ToggleGameMeter()
    return ns.ToggleCVar(CVAR, L.METER_ON, L.METER_OFF)
end

---------------------------------------------------------------------------
-- Eigene Zeile hervorheben
---------------------------------------------------------------------------

local function IsMe(value)
    if ns.IsSecret(value) then return false end
    return value == true
end

local function Overlay(entry)
    local overlay = overlays[entry]
    if overlay then return overlay end
    local bar = type(entry.GetStatusBar) == "function" and entry:GetStatusBar() or nil
    local host = type(bar) == "table" and bar.CreateTexture and bar or entry
    overlay = host:CreateTexture(nil, "OVERLAY", nil, 7)
    overlay:SetAllPoints(host)
    overlay:SetTexture(HIGHLIGHT_TEXTURE)
    overlay:SetBlendMode("ADD")
    overlay:SetVertexColor(1, 0.82, 0, 0.45)      -- Blizzards Gold (NORMAL_FONT_COLOR)
    overlay:Hide()
    overlays[entry] = overlay
    return overlay
end

-- Markierung eines Eintrags setzen; me = Daten des Eintrags sagen „du“.
function Meter.Apply(entry, me)
    if type(entry) ~= "table" then return end
    local want = IsMe(me)   -- fest an (Einstellungs-Prüfung 19.11.2026, Abschnitt 4)
    if want then
        Overlay(entry):Show()
    elseif overlays[entry] then
        overlays[entry]:Hide()
    end
end

function Meter.IsHighlighted(entry)
    local overlay = overlays[entry]
    return overlay ~= nil and overlay:IsShown()
end

local function OnInitEntry(_, entry, elementData)
    Meter.Apply(entry, type(elementData) == "table" and elementData.isLocalPlayer or nil)
end

local function Windows()
    local list = {}
    for index = 1, MAX_WINDOWS do
        local window = rawget(_G, "DamageMeterSessionWindow" .. index)
        if type(window) == "table" then list[#list + 1] = window end
    end
    return list
end

-- Alle sichtbaren Einträge neu markieren (nach einer Änderung in den Einstellungen).
function Meter.RefreshAll()
    for _, window in ipairs(Windows()) do
        pcall(function()
            for _, entry in window:EnumerateEntryFrames() do Meter.Apply(entry, entry.isLocalPlayer) end
        end)
        local pinned = type(window.GetLocalPlayerEntry) == "function" and window:GetLocalPlayerEntry() or nil
        if type(pinned) == "table" then Meter.Apply(pinned, pinned.isLocalPlayer) end
    end
end

-- Die vorhandenen Fenster einzeln, später erzeugte über Blizzards Vorlage (sie kopiert die Methoden beim Anlegen).
function Meter.Attach()
    if not mixinHooked then
        for _, window in ipairs(Windows()) do
            if not hookedWindows[window] and type(window.InitEntry) == "function" then
                hooksecurefunc(window, "InitEntry", OnInitEntry)
                hookedWindows[window] = true
            end
        end
        local mixin = rawget(_G, "DamageMeterSessionWindowMixin")
        if type(mixin) == "table" and type(mixin.InitEntry) == "function" then
            hooksecurefunc(mixin, "InitEntry", OnInitEntry)
            mixinHooked = true
        end
    end
    Meter.AddMenu()
    Meter.RefreshAll()
end

---------------------------------------------------------------------------
-- Bericht in den Chat
---------------------------------------------------------------------------

-- Arten ohne „pro Sekunde“ (Zähler): Unterbrechungen, Bannungen, Tode.
local function CountsOnly(damageMeterType)
    local enum = Enum and Enum.DamageMeterType
    if not enum then return false end
    return damageMeterType == enum.Interrupts or damageMeterType == enum.Dispels or damageMeterType == enum.Deaths
end

-- Methode eines Blizzard-Objekts geschützt aufrufen (ezCore.Call): erstes Ergebnis oder nil.
local function Call(object, method, ...)
    if type(object) ~= "table" then return nil end
    return (Core.Call(object[method], object, ...))
end

local function Text(value)
    value = ns.Plain(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

-- Name der Art, wie Blizzards Fenster ihn in der Kopfzeile zeigt („Schaden“, „DPS“ …).
local function TypeName(window)
    local fontString = Call(window, "GetDamageMeterTypeName")
    return fontString and Text(Call(fontString, "GetText")) or L.METER_TITLE
end

-- Frühere Kämpfe, die der Client gerade führt (C_DamageMeter.GetAvailableCombatSessions, Forever-Quelle
-- DamageMeterDocumentation: { sessionID, name, durationSeconds }) → { { id, name, duration } … }, neueste zuerst
-- (höchste ID; Blizzards Fenster zählt die Kämpfe ebenso hoch). Jeder Wert über IsSecret; leer, wenn nichts lesbar ist.
function Meter.CombatSessions()
    local api = rawget(_G, "C_DamageMeter")
    if type(api) ~= "table" or type(api.GetAvailableCombatSessions) ~= "function" then return {} end
    local ok, list = pcall(api.GetAvailableCombatSessions)
    if not ok or ns.IsSecret(list) or type(list) ~= "table" then return {} end
    local out = {}
    for _, info in ipairs(list) do
        if type(info) == "table" and not ns.IsSecret(info) then
            local id = ns.Num(info.sessionID)
            if id then out[#out + 1] = { id = id, name = Text(info.name), duration = ns.Num(info.durationSeconds) } end
        end
    end
    table.sort(out, function(a, b) return a.id > b.id end)
    return out
end

-- Name eines früheren Kampfs wie in Blizzards Auswahl: sein Name, sonst „Kampf n“ (Blizzards Text), mit Dauer.
function Meter.CombatName(combat)
    if type(combat) ~= "table" then return L.METER_SESSION end
    local name = combat.name
    if not name then
        local pattern = Text(rawget(_G, "DAMAGE_METER_COMBAT_NUMBER"))
        name = pattern and pattern:format(combat.id) or L.METER_SESSION_COMBAT:format(combat.id)
    end
    if combat.duration and combat.duration > 0 then
        return L.METER_SESSION_WITH_TIME:format(name, Core.Duration(combat.duration, true))
    end
    return name
end

-- Name der Sitzung mit Blizzards Texten: „Aktueller Kampf“, „Gesamt“ oder der Name eines früheren Kampfs.
function Meter.SessionName(sessionType, sessionID)
    local enum = Enum and Enum.DamageMeterSessionType
    if enum and sessionType == enum.Current then
        return Text(rawget(_G, "DAMAGE_METER_CURRENT_SESSION")) or L.METER_SESSION_CURRENT
    end
    if enum and sessionType == enum.Overall then
        return Text(rawget(_G, "DAMAGE_METER_OVERALL_SESSION")) or L.METER_SESSION_OVERALL
    end
    if sessionID ~= nil then
        for _, combat in ipairs(Meter.CombatSessions()) do
            if combat.id == sessionID and combat.name then return combat.name end
        end
        local pattern = Text(rawget(_G, "DAMAGE_METER_COMBAT_NUMBER"))
        if pattern then return pattern:format(sessionID) end
    end
    return L.METER_SESSION
end
local SessionName = Meter.SessionName

-- Sitzung, die das Fenster gerade zeigt: Daten, Art, Name der Sitzung – oder nil, "secret", wenn das Spiel die
-- Sitzung sperrt (T3-5, Gesamtreview 18.11.2026: zuerst IsSecret, dann erst indexieren; wie MF.Session).
-- Ist einer der Werte des Fensters gesperrt, ebenso nil, "secret": ein Standardwert (Schaden, aktueller Kampf)
-- passte nicht zum Titel, den das Fenster zeigt (Gegenprüfung P14).
local function SessionOf(window)
    local api = C_DamageMeter
    if type(api) ~= "table" then return nil end
    local damageMeterType = Call(window, "GetDamageMeterType")
    local sessionType, sessionID = Call(window, "GetSessionType"), Call(window, "GetSessionID")
    if ns.IsSecret(damageMeterType) or ns.IsSecret(sessionType) or ns.IsSecret(sessionID) then return nil, "secret" end
    if damageMeterType == nil then
        damageMeterType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
    end
    if sessionType == nil and sessionID == nil then
        sessionType = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    end
    local ok, session
    if sessionType ~= nil and api.GetCombatSessionFromType then
        ok, session = pcall(api.GetCombatSessionFromType, sessionType, damageMeterType)
    elseif api.GetCombatSessionFromID then
        ok, session = pcall(api.GetCombatSessionFromID, sessionID, damageMeterType)
    end
    if not ok then return nil end
    if ns.IsSecret(session) then return nil, "secret" end
    if type(session) ~= "table" then return nil end
    local title = ("%s – %s"):format(TypeName(window), SessionName(sessionType, sessionID))
    return session, damageMeterType, title
end

-- Zeilen des Berichts. Rückgabe: Liste oder nil und der Grund (Text).
function Meter.ReportLines(window, count)
    if ns.InCombat() then return nil, Core.CombatText(L.METER_REPORT_WHAT) end   -- ezCores Satz (T18-1)
    local session, damageMeterType, title = SessionOf(window)
    if not session then return nil, damageMeterType == "secret" and L.METER_REPORT_SECRET or L.METER_REPORT_NONE end
    local sources = session.combatSources
    if ns.IsSecret(sources) then return nil, L.METER_REPORT_SECRET end
    if type(sources) ~= "table" or #sources == 0 then return nil, L.METER_REPORT_EMPTY end
    local duration = ns.Num(session.durationSeconds)
    local lines = { duration and duration > 0 and L.METER_REPORT_HEAD_TIME:format(title, Core.Duration(duration, true))
        or L.METER_REPORT_HEAD:format(title) }
    local countsOnly = CountsOnly(damageMeterType)
    for index, source in ipairs(sources) do
        if index > count then break end
        -- Ein gesperrter Eintrag wird nicht indexiert (T3-5; wie MF.Ranking)
        if ns.IsSecret(source) or type(source) ~= "table" then return nil, L.METER_REPORT_SECRET end
        local name = ns.Plain(source.name)
        local value = ns.Num(source.totalAmount)
        if type(name) ~= "string" or not value then return nil, L.METER_REPORT_SECRET end
        local perSecond = not countsOnly and ns.Num(source.amountPerSecond) or nil
        local amount = countsOnly and Core.FormatNumber(value) or Core.ShortNumber(value)
        if perSecond and perSecond > 0 then
            lines[#lines + 1] = L.METER_REPORT_LINE_RATE:format(index, Core.ShortName(name), amount,
                Core.ShortNumber(perSecond))
        else
            lines[#lines + 1] = L.METER_REPORT_LINE:format(index, Core.ShortName(name), amount)
        end
    end
    return lines
end

-- Wohin: „GROUP“ wählt Schlachtzug, Instanz- oder Gruppenchat (ezCore.GroupChannel); „SELF“ zeigt nur dir den
-- Bericht. Rückgabe: Chat-Art oder nil (kein Kanal).
function Meter.ChatType(target)
    if target == "GROUP" then
        return Core.GroupChannel()
    elseif target == "GUILD" then
        return IsInGuild and IsInGuild() and "GUILD" or nil
    end
    return nil
end

function Meter.Targets()
    local list = {}
    if Meter.ChatType("GROUP") then
        list[#list + 1] = { key = "GROUP", text = L.METER_TO_GROUP, tip = L.METER_TO_GROUP_TIP }
    end
    if Meter.ChatType("GUILD") then
        list[#list + 1] = { key = "GUILD", text = L.METER_TO_GUILD, tip = L.METER_TO_GUILD_TIP }
    end
    list[#list + 1] = { key = "SELF", text = L.METER_TO_SELF, tip = L.METER_TO_SELF_TIP }
    return list
end

-- Bericht eines Fensters (Standard: das Hauptfenster) senden. Rückgabe: true, wenn etwas ging.
function Meter.Report(window, target)
    target = target or "SELF"
    window = window or Windows()[1]
    if not window then
        ns.Print(L.METER_REPORT_NONE)
        return false
    end
    local lines, reason = Meter.ReportLines(window, ns.S.meterReportLines)
    if not lines then
        ns.Print(reason)
        return false
    end
    local chatType = target ~= "SELF" and Meter.ChatType(target) or nil
    if target ~= "SELF" and not chatType then
        ns.Print(L.METER_REPORT_NO_CHANNEL)
        return false
    end
    if chatType and Core.ChatLocked() then
        ns.Print(L.METER_REPORT_LOCKED)
        return false
    end
    -- Senden über ezCore (Gruppenkanal bei „GROUP“, nie während der Chat-Sperre).
    for _, line in ipairs(lines) do
        if chatType then Core.SendChat(line, target) else ns.Print(line) end
    end
    return true
end

-- Das Fenster, zu dem ein Knopf im Menü gehört (Zahnrad sitzt in der Kopfzeile des Fensters).
local function WindowOf(owner)
    local windows = {}
    for _, window in ipairs(Windows()) do windows[window] = true end
    local frame = owner
    for _ = 1, 6 do
        if type(frame) ~= "table" then return nil end
        if windows[frame] then return frame end
        frame = type(frame.GetParent) == "function" and frame:GetParent() or nil
    end
    return nil
end

-- Häkchen „Schaden/Heilung an Gruppenrahmen“ (Stufe 3, MeterFrames.lua) – dieselben Schalter wie in den
-- Einstellungen, gleich dort, wo man den Schadensmesser bedient (Leitlinie 3).
function Meter.AddFrameToggles(rootDescription)
    local MF = ns.MeterFrames
    local chosen = MF and MF.SessionLine() or nil
    for _, key in ipairs({ "meterFramesDamage", "meterFramesHealing" }) do
        local item = Core.Menu.Toggle(rootDescription, L["OPT_" .. key],
            function() return ns.Enabled(key) end,
            function(value) ns.SetSetting(key, value == true) end)
        local tip = L["OPT_" .. key .. "_TIP"]
        Core.Menu.Tip(item, L["OPT_" .. key], chosen and (tip .. "\n\n" .. chosen) or tip)
    end
    if MF then Meter.AddMoreChoices(rootDescription) end
end

-- Top-3-Ansicht und weitere Arten (MeterTop.lua; Antwort des Nutzers vom 16.11.2026: „Ja, beides“): Untermenü
-- „Darstellung an den Gruppenrahmen: …“ (Zeilen, nur die ersten 3, beides) und Untermenü „Weitere Arten an den
-- Gruppenrahmen“ mit je einem Häkchen – dieselben Schalter wie in den Einstellungen (Leitlinie 3).
function Meter.AddMoreChoices(rootDescription)
    local MF = ns.MeterFrames
    local view = Core.Menu.Button(rootDescription, L.METER_FRAMES_VIEW_MENU:format(MF.ViewLabel(MF.View())))
    Core.Menu.Tip(view, L.OPT_meterFramesView, L.OPT_meterFramesView_TIP)
    local function Set(value) ns.SetSetting(MF.VIEW_KEY, value) end
    for _, value in ipairs(ns.CHOICES[MF.VIEW_KEY]) do
        local item = Core.Menu.Radio(view, MF.ViewLabel(value), MF.View, Set, value)
        Core.Menu.Tip(item, MF.ViewLabel(value), L["OPT_meterFramesView_" .. value .. "_TIP"])
    end
    local more = Core.Menu.Button(rootDescription, L.METER_FRAMES_MORE_MENU)
    Core.Menu.Tip(more, L.METER_FRAMES_MORE_MENU, L.METER_FRAMES_MORE_MENU_TIP)
    for _, key in ipairs(MF.MORE_KEYS) do
        local item = Core.Menu.Toggle(more, L["OPT_" .. key],
            function() return ns.Enabled(key) end,
            function(value) ns.SetSetting(key, value == true) end)
        Core.Menu.Tip(item, L["OPT_" .. key], MF.Tooltip(key))
    end
    return view, more
end

-- Auswahl des Abschnitts für die Rahmen-Balken (Entscheidung des Nutzers 13.11.2026: „wählbar machen, gerne wie
-- bei details wenn möglich“): Untermenü „Abschnitt: …“ mit aktuellem Kampf, gesamt und den früheren Kämpfen, die
-- Blizzards Schadensmesser gerade führt. Umsetzung über C_DamageMeter (MeterFrames.lua).
function Meter.AddSessionChoice(rootDescription)
    local MF = ns.MeterFrames
    if not MF then return nil end
    local _, _, name = MF.Selector()
    local sub = Core.Menu.Button(rootDescription, L.METER_FRAMES_SESSION_MENU:format(name))
    Core.Menu.Tip(sub, L.OPT_meterFramesSession, MF.SessionTip())
    local function Get() return MF.ChoiceValue() end
    local function Set(value) MF.SelectValue(value) end
    for _, entry in ipairs(MF.ChoiceList()) do
        if entry.title then
            Core.Menu.Title(sub, entry.text)
        else
            local item = Core.Menu.Radio(sub, entry.text, Get, Set, entry.value)
            Core.Menu.Tip(item, entry.text, entry.tip)
        end
    end
    return sub
end

-- Eintrag in Blizzards Zahnrad-Menü jedes Fensters: „Bericht in den Chat“ ›  Gruppe / Gilde / nur für mich.
function Meter.AddMenu()
    if menuAdded or not (Menu and type(Menu.ModifyMenu) == "function") then return end
    menuAdded = true
    Menu.ModifyMenu(MENU_TAG, function(owner, rootDescription)
        Core.Menu.Divider(rootDescription)
        do   -- immer da (Einstellungs-Prüfung 19.11.2026, Nr. 35): handelt nur auf Klick
            local window = WindowOf(owner)
            local sub = Core.Menu.Button(rootDescription, L.METER_REPORT)
            Core.Menu.Tip(sub, L.METER_REPORT, L.METER_REPORT_TIP:format(ns.PathText("OPT_HEADER_METER", "OPT_meterReportLines")))
            for _, entry in ipairs(Meter.Targets()) do
                local key = entry.key
                local item = Core.Menu.Button(sub, entry.text, function() ns.Try("Meter", Meter.Report, window, key) end)
                Core.Menu.Tip(item, entry.text, entry.tip)
            end
        end
        Meter.AddFrameToggles(rootDescription)
        ns.Try("Meter", Meter.AddSessionChoice, rootDescription)
    end)
end

---------------------------------------------------------------------------

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_DamageMeter", Meter.Attach)
end)

ns.AddStatusLine(function()
    if rawget(_G, "DamageMeter") and not Meter.GameMeterOn() then
        return L.STATUS_METER_OFF:format(ns.PathText("OPT_HEADER_METER", "OPT_METER_GAME"))
    end
end)
