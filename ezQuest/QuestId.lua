local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Quest-ID am Questlog (aus dem ezMacro-Abgleich „Informationen“, MACRO-31):
      Tooltip   Fährt die Maus über eine Quest im Questlog, steht unten grau „Quest-ID: 1234“ (Schalter
                „Quest-ID im Tooltip des Questlogs“). Die Zeile hängt an Blizzards Tooltip der Zeile
                (DungeonQuests.lua hakt die Zeilen ein und ruft QuestId.AddToTooltip).
      Abfrage   „Quest mit ID erledigt?“: ein Eintrag in Blizzards Zahnrad-Menü oben rechts am Questlog öffnet
                Blizzards Eingabedialog (Core.AskText); die Antwort steht im eigenen Chat. Dazu der Knopf auf der
                Einstellungsseite und /ezq id 1234.
    Warum das Zahnrad-Menü und kein eigenes Eingabefeld in der Kopfzeile: In Forever füllen Blizzards Suchfeld (200)
    und der Zähler „Quests: 14/40“ (100) die Kopfzeile des Questlogs ganz aus (QuestMapFrameUtils.lua,
    QuestLogQuests_ShowQuestCount). Blizzards Menü hat das Tag MENU_QUEST_MAP_FRAME_SETTINGS
    (QuestMapFrame_SetupSettingsDropdown) – der offizielle, taint-sichere Weg ist Menu.ModifyMenu; Blizzards
    Einträge bleiben unberührt.
    Quelle der Auskunft ist der Client: C_QuestLog.IsQuestFlaggedCompleted (dieser Charakter), IsOnQuest und
    GetTitleForQuestID. Kennt der Client den Titel noch nicht, fordert ezQuest die Quest an
    (RequestLoadQuestByID, Antwort QUEST_DATA_LOAD_RESULT) und antwortet spätestens nach QuestId.WAIT Sekunden –
    dann ohne Titel und mit dem Hinweis, dass es die ID vielleicht nicht gibt (der Client meldet „nicht erledigt“
    auch für IDs ohne Quest). Gespeichert wird nichts.
]]

local QuestId = {}
ns.QuestId = QuestId

QuestId.TAG = "MENU_QUEST_MAP_FRAME_SETTINGS"   -- Blizzards Zahnrad-Menü am Questlog
QuestId.WAIT = 2                                -- Sekunden, die ezQuest höchstens auf den Titel wartet

local Call = Core.Call   -- geschützt, verträgt fehlende Funktionen
local Menu = Core.Menu

local MAX_DIGITS = 9
-- Farben der Antwort (Design-System 2.5, Welle 22; bis dahin eigene Farbcodes 40ff40, ffd100, ff8040, 999999):
-- erledigt in Blizzards Grün (Rolle „good“), im Questlog in Gold (Rolle „normal“, NORMAL_FONT_COLOR = ffd100),
-- offen in Blizzards ORANGE_FONT_COLOR (ff8040; ohne das Objekt Rolle „warn“), sonst ezCores Grau wie Hinweise.
local ROLES = { done = "good", active = "normal" }
function QuestId.Paint(state, text)
    if ROLES[state] then return Core.Style.ColorText(ROLES[state], text) end
    if state == "open" then
        local orange = rawget(_G, "ORANGE_FONT_COLOR")
        if type(orange) == "table" and type(orange.WrapTextInColorCode) == "function" then
            local ok, wrapped = pcall(orange.WrapTextInColorCode, orange, text)
            if ok and type(wrapped) == "string" then return wrapped end
        end
        return Core.Style.ColorText("warn", text)
    end
    return Core.Grey(text)
end

---------------------------------------------------------------------------
-- Eingabe lesen und den Client fragen
---------------------------------------------------------------------------

-- Quest-ID aus einer Eingabe: „1234“, „#1234“ oder ein Quest-Link (…|Hquest:1234:…). Sonst nil.
function QuestId.Parse(text)
    if type(text) == "number" and not Core.IsSecret(text) then text = tostring(text) end
    text = Core.Plain(text)
    if type(text) ~= "string" then return nil end
    text = Core.Trim(text)
    local digits = text:match("quest:(%d+)") or text:match("^#?(%d+)$")
    if not digits or #digits > MAX_DIGITS then return nil end
    local questID = tonumber(digits)
    return questID and questID > 0 and questID or nil
end

-- Titel und „erledigt“ fragt ezCore an einer Stelle, geschützt vor gesperrten Werten (Core.QuestTitle,
-- Core.QuestDone; Welle 23c, A31 – vorher eigene Fassungen hier und in ezCore/Wissen/Collections.lua).
local function Title(questID)
    return Core.QuestTitle(questID)
end

-- true/false laut Client, nil ohne Auskunft (Funktion fehlt, Fehler oder geheimer Wert).
local function Flagged(questID)
    return Core.QuestDone(questID)
end

-- Steht die Quest im Questlog? true/false laut Client, nil ohne Auskunft (Funktion fehlt, gesperrter Wert). Auch für
-- die Leveling-Route (nach einer Rechnung in Scheiben keine Quest einfügen, die schon wieder weg ist; Fund der
-- Gegenprüfung vom 17.11.2026). QuestId.State liest nil wie bisher als „nicht im Log“.
function QuestId.InLog(questID)
    local log = C_QuestLog
    if type(log) ~= "table" then return nil end
    if type(log.IsOnQuest) == "function" then return Core.Bool(Call(log.IsOnQuest, questID), nil) end
    if type(log.GetLogIndexForQuestID) ~= "function" then return nil end
    local index = Call(log.GetLogIndexForQuestID, questID)
    if Core.IsSecret(index) then return nil end
    return Core.Num(index) ~= nil
end
local InLog = QuestId.InLog

-- Stand einer Quest für diesen Charakter: "done" (erledigt), "active" (steht im Questlog), "open" (nicht
-- erledigt) – nil, wenn der Client keine Auskunft gibt.
function QuestId.State(questID)
    questID = Core.Num(questID)
    if not questID then return nil end
    local done = Flagged(questID)
    if done == nil then return nil end
    if done then return "done" end
    return InLog(questID) and "active" or "open"
end

-- Antwort als Chatzeile und der Stand: „Quest 1234 („Wölfe“): erledigt – …“. Ohne Titel sagt die Zeile bei
-- „nicht erledigt“ dazu, dass der Client zu dieser ID keine Quest findet.
function QuestId.Answer(questID)
    questID = Core.Num(questID)
    if not questID then return L.ID_INVALID, nil end
    local title = Title(questID)
    local head = title and L.ID_HEAD_TITLE:format(questID, title) or L.ID_HEAD:format(questID)
    local state = QuestId.State(questID)
    local body, tone = L.ID_UNKNOWN, "unknown"
    if state == "done" then
        body, tone = L.ID_DONE, "done"
    elseif state == "active" then
        body, tone = L.ID_ACTIVE, "active"
    elseif state == "open" and title then
        body, tone = L.ID_OPEN, "open"
    elseif state == "open" then
        body = L.ID_OPEN_NOTITLE   -- grau: ob es die Quest gibt, weiß ezQuest hier nicht
    end
    return head .. ": " .. QuestId.Paint(tone, body), state
end

---------------------------------------------------------------------------
-- Abfrage: Eingabe prüfen, Antwort in den eigenen Chat
---------------------------------------------------------------------------

local waiting = {}   -- [questID] = Nummer der Abfrage, solange der Titel noch lädt
local asked = 0

local function Report(questID)
    waiting[questID] = nil
    ns.Print((QuestId.Answer(questID)))
end

-- Eingabe prüfen und antworten. Rückgabe: die Quest-ID, nil bei ungültiger Eingabe (dann steht ein Hinweis im Chat).
function QuestId.Check(text)
    local questID = QuestId.Parse(text)
    if not questID then
        ns.Print(L.ID_INVALID)
        return nil
    end
    QuestId.last = questID
    if waiting[questID] then return questID end   -- dieselbe ID lädt schon, die Antwort kommt gleich
    local log = C_QuestLog
    if Title(questID) or type(log) ~= "table" or type(log.RequestLoadQuestByID) ~= "function" then
        Report(questID)
        return questID
    end
    asked = asked + 1
    local token = asked
    waiting[questID] = token
    Core.QuestTitle(questID, true)   -- fordert die Quest beim Client an (RequestLoadQuestByID)
    C_Timer.After(QuestId.WAIT, function()
        if waiting[questID] == token then ns.Try("QuestId", Report, questID) end
    end)
    return questID
end

-- Blizzards Eingabedialog (Core.AskText) mit der zuletzt gefragten ID; die Antwort steht danach im Chat.
function QuestId.Ask()
    local current = QuestId.last and tostring(QuestId.last) or ""
    return Core.AskText(L.ID_PROMPT, current, function(text) ns.Try("QuestId", QuestId.Check, text) end)
end

---------------------------------------------------------------------------
-- Tooltip der Zeilen im Questlog
---------------------------------------------------------------------------

-- „Quest-ID: 1234“ anhängen. true, wenn die Zeile dazukam.
function QuestId.AddToTooltip(tooltip, questID)
    questID = Core.Num(questID)
    if not questID or questID <= 0 or not ns.Enabled("questIdTip") then return false end
    Core.TipLine(tooltip, L.ID_LINE:format(questID), "hint")   -- ezCores Grau (T9-6, Gegenprüfung D2)
    tooltip:Show()
    return true
end

---------------------------------------------------------------------------
-- Blizzards Zahnrad-Menü am Questlog: Abschnitt „ezQuest“ unter Blizzards Einträgen
---------------------------------------------------------------------------

-- Tooltip an einem Menü-Eintrag über ezCores Menu.Tip (Blizzards SetTooltip des Eintrags; Welle 23, A1 – vorher eine
-- eigene Fassung MenuTip hier und in ezCombat/Meter.lua).
function QuestId.BuildMenu(root)
    Menu.Divider(root)
    Menu.Title(root, L.TITLE)
    Menu.Tip(Menu.Button(root, L.ID_MENU, function() ns.Try("QuestId", QuestId.Ask) end), L.ID_MENU, L.ID_MENU_TIP)
    Menu.Tip(Menu.Toggle(root, L.OPT_questIdTip, function() return ns.Enabled("questIdTip") end,
        function(on) ns.SetSetting("questIdTip", on) end), L.OPT_questIdTip, L.OPT_questIdTip_TIP)
    -- Quests teilen (Share.lua; Wunsch des Nutzers vom 18.11.2026): Haken „automatisch teilen“ und „Jetzt teilen“.
    -- Wie bei der Leveling-Route unten bleibt ein Fehler abgefangen, zählt aber im Ergebnis (Gegenprüfung W-1811)
    local shareOk = not ns.Share or ns.Try("ShareMenu", ns.Share.AddMenu, root)
    -- Leveling-Route (LevelRoute.lua): Eintrag mit Untermenü im selben Abschnitt „ezQuest“. Ihr Fehler bleibt hier
    -- abgefangen (Quest-ID und Haken stehen trotzdem), wird aber zurückgegeben – sonst meldete /ezq status „aufgebaut“,
    -- obwohl genau der Eintrag „Leveling-Route“ fehlt (Fund der Gegenprüfung vom 18.11.2026)
    local routeOk = not ns.LevelRoute or ns.Try("LevelRouteMenu", ns.LevelRoute.AddMenu, root)
    return shareOk == true and routeOk == true
end

--[[
    Anmelden (Wunsch des Nutzers vom 18.11.2026, „zeigt es mir nicht an“ – Untersuchung in docs/roadmap/ezQuest.md):
    Laut Blizzards Forever-Quelle (Blizzard_Menu/Menu.lua) merkt Menu.ModifyMenu die Ergänzung je Tag und ruft sie bei
    jedem Aufbau eines Menüs mit diesem Tag auf (Menu.PopulateDescription); wurde das Menü schon einmal aufgebaut, auch
    sofort. Der Zeitpunkt der Anmeldung ist also gleich. Fehlt Menu.ModifyMenu zur Zeit von ns.OnReady (anderer Client,
    ein Addon lädt Blizzards Menü später) oder wirft die Anmeldung, versucht ezQuest es erneut: beim Laden von
    Blizzard_UIPanels_Game bzw. Blizzard_WorldMap und bei jedem Öffnen des Questlogs (HookScript, Leitlinie 5).
    Damit ein Eintrag nach einem zweiten Versuch nicht doppelt steht, baut ezQuest je Menü nur einmal an (schwache
    Tabelle, nichts in Blizzards Tabellen). Für /ezq status zählt QuestId.menu, ob angemeldet, wie oft aufgebaut, wie
    oft dabei ein Fehler kam (auch in den Einträgen „Quests teilen“ und „Leveling-Route“) und ob der letzte Aufbau
    gelang (lastOk;
    QuestId.StatusLine meldet „Fehler“ nur, solange der letzte Aufbau fehlschlug – Fund der Gegenprüfung vom 18.11.2026).
    false, wenn der Client Menu.ModifyMenu nicht hat – dann bleiben der Knopf auf der Einstellungsseite und /ezq id.
]]
QuestId.menu = { registered = false, built = 0, failed = 0, tries = 0, lastOk = nil }
local builtFor = setmetatable({}, { __mode = "k" })    -- [root] = true: dieses Menü hat den Abschnitt schon
function QuestId.Build(root)
    if type(root) ~= "table" or builtFor[root] then return false end
    builtFor[root] = true
    local result
    local ok = ns.Try("QuestIdMenu", function() result = QuestId.BuildMenu(root) end)
    ok = ok and result ~= false     -- false: „Quests teilen“ oder „Leveling-Route“ warf (BuildMenu fängt es selbst ab)
    QuestId.menu.built = QuestId.menu.built + 1
    if not ok then QuestId.menu.failed = QuestId.menu.failed + 1 end
    QuestId.menu.lastOk = ok
    return ok
end

function QuestId.Register()
    local state = QuestId.menu
    local blizzardMenu = rawget(_G, "Menu")
    if state.registered or not (type(blizzardMenu) == "table" and type(blizzardMenu.ModifyMenu) == "function") then
        return state.registered
    end
    state.tries = state.tries + 1
    state.registered = pcall(blizzardMenu.ModifyMenu, QuestId.TAG, function(_, root) QuestId.Build(root) end)
    return state.registered
end

-- Erneut versuchen, wenn das Questlog aufgeht (einmal eingehakt; ohne QuestMapFrame später beim Laden der Karte)
local hookedLog = false
function QuestId.HookQuestLog()
    local frame = rawget(_G, "QuestMapFrame")
    if hookedLog or type(frame) ~= "table" or type(frame.HookScript) ~= "function" then return hookedLog end
    hookedLog = true
    frame:HookScript("OnShow", function() ns.Try("QuestId", QuestId.Register) end)
    return true
end

-- Zeile für /ezq status: Steht der Abschnitt „ezQuest“ (Quest-ID, Leveling-Route) im Zahnrad-Menü am Questlog?
function QuestId.StatusLine()
    local m = QuestId.menu
    if not m.registered then return L.MENU_STATUS_MISSING:format(ns.SlashCmd("route")) end
    if m.lastOk == false then return L.MENU_STATUS_FAILED:format(m.failed) end
    if m.built > 0 then return L.MENU_STATUS_SEEN end
    return L.MENU_STATUS_READY
end

-- Schnittstelle für andere Module (ezCore.API("ezQuest")): Stand einer Quest und der Eingabedialog – gedacht für
-- den Info-Knopf „Quest mit ID erledigt?“ in ezMacros Reiter „Werkzeuge“ (docs/roadmap/ezMacro.md).
ns.API.QuestState = QuestId.State
ns.API.AskQuestId = QuestId.Ask

ns.OnReady(function()
    ns.Try("QuestId", QuestId.Register)
    ns.Try("QuestId", QuestId.HookQuestLog)
    for _, addon in ipairs({ "Blizzard_UIPanels_Game", "Blizzard_WorldMap" }) do
        ns.WhenAddOnLoaded(addon, function()
            QuestId.Register()
            QuestId.HookQuestLog()
        end)
    end
    -- Titel nachgeladen (oder die ID gibt es nicht): jetzt antworten statt auf den Zeitablauf zu warten
    ns.On("QUEST_DATA_LOAD_RESULT", function(_, questID)
        questID = Core.Num(questID)
        if questID and waiting[questID] then Report(questID) end
    end)
end)
