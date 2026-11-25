local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Quests teilen (Wunsch des Nutzers vom 18.11.2026, wörtlich „feature: quest automatisch teilen“; Paket W-1811 des
    Gesamtreviews vom 18.11.2026). Nimmst du in einer Gruppe oder einem Schlachtzug eine Quest an, die sich teilen
    lässt, bietet ezQuest sie deinen Mitspielern über Blizzards eigenes Teilen an – dasselbe wie der Knopf „Teilen“ in
    den Questlog-Details und der Eintrag „Quest teilen“ in Blizzards Rechtsklick-Menü einer Quest.

    Blizzards Weg (Gethe/wow-ui-source, Zweig forever, gelesen am 18.11.2026):
      Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua, QuestMapQuestOptions_ShareQuest(questID):
          questLogIndex = C_QuestLog.GetLogIndexForQuestID(questID); QuestLogPushQuest(questLogIndex)
      Knopf frei nur, wenn C_QuestLog.IsPushableQuest(questID) und IsInGroup() (und die Quest nicht gesperrt ist,
      C_QuestLog.IsQuestDisabledForSession). QuestLogPushQuest steht in keiner Dokumentation des Zweigs (eine alte
      globale Funktion) und ist weder als geschützt noch als „braucht einen Klick“ (hardware event) gekennzeichnet;
      warcraft.wiki.gg (API_QuestLogPushQuest) nennt ebenfalls keine Sperre. Ältere Clients lesen die gewählte Quest
      statt des Arguments – darum setzt ezQuest vorher C_QuestLog.SetSelectedQuest und stellt die vorher gewählte
      Quest danach wieder ein (nichts in Blizzards Tabellen, Leitlinie 5).

    Regeln (Grundsatz des Nutzers vom 17.11.2026 und Entscheidung 2 vom 18.11.2026):
      - Das sendet ohne Klick an andere Spieler: ab Werk AUS (autoShare), einmal je Account ein Hinweis über ezCores
        Core.OptInHint an Blizzards Questverfolgung, wenn du in einer Gruppe eine Quest annimmst (Fenster „tracker“,
        Ereignis QUEST_ACCEPTED), mit Knopf „Einschalten“.
      - Gedrosselt und gebündelt: Angenommene Quests kommen in eine Reihe; die erste geht nach Share.DELAY Sekunden
        hinaus (mehrere auf einmal angenommene sammeln sich so), danach höchstens eine alle Share.GAP Sekunden.
      - Jede Quest automatisch nur einmal je Sitzung (Share.shared); eine Quest, die dir ein Spieler geteilt hat
        (QUEST_DETAIL mit einem Spieler als Gegenüber, danach angenommen), teilt ezQuest nicht zurück.
      - Nie im Kampf: die Reihe wartet bis PLAYER_REGEN_ENABLED (ns.AfterCombat).
      - Haben alle Mitspieler die Quest schon (C_QuestLog.IsUnitOnQuest für jeden), entfällt sie. Ist das für einen
        Mitspieler nicht lesbar (Funktion fehlt, gesperrter Wert, zu weit weg), teilt ezQuest einfach – Blizzard meldet
        dann selbst, wer sie schon hat.
      - Nicht allein, nicht für Quests, die sich nicht teilen lassen.
      - Rücksicht (Leitlinie 9): übernimmt ein anderes Addon das automatische Teilen (ezCores Erkennung, Funktion
        questShare), hält sich ezQuest zurück. Stand 18.11.2026 kennt ezCore keines (docs/fremd-addons.md).
      - Einer nach dem anderen (24.11.2026): meldet Blizzard, dass die Quest einem Mitspieler gerade angeboten wird, wartet
        die Reihe auf seine Antwort (ShareJoin.lua, Join.Hold) – solange sein Fenster offen ist, ginge die nächste als
        „beschäftigt“ verloren.
      - Nichts geht verloren (Fehler des Nutzers vom 24.11.2026, wörtlich „quest teilen funktioniert aber bei mehreren quest
        eines npcsw wird nur die erste geteitl“): Meldet Blizzard für einen Mitspieler „beschäftigt“, „tot“ oder „zu weit
        entfernt“, kommt die Quest nach Share.RETRY Sekunden noch einmal, höchstens Share.TRIES mal (Share.Later) – nur,
        solange sie jemandem fehlt, der beim ersten Mal dabei war und noch nicht gefragt wurde, nie, wenn ein anderer sie
        abgelehnt hat, und nicht in großen Gruppen (Join.GROUP_MAX: jeder Versuch geht an alle).
      - Chat: keine Zeile je Quest (Blizzard meldet im Chat, wer sie angenommen hat oder schon hat); die zuletzt geteilte
        Quest und die Zahl dieser Sitzung stehen in /ezq status. Nur „Jetzt teilen“ (ein Klick) sagt eine Zeile.
    Sichtbar (Leitlinie 3): Haken „Angenommene Quests automatisch teilen“ und „Teilbare Quests jetzt teilen“ im
    Zahnrad-Menü am Questlog (Abschnitt „ezQuest“, QuestId.BuildMenu) und auf ezQuests Einstellungsseite.

    Kommt ein Mitspieler dazu, bietet ShareJoin.lua die Quests an, die ihm fehlen (Wunsch vom 24.11.2026; eigener Schalter
    joinShare) – über dieselbe Reihe (Share.Add mit join = true).
]]

local Share = {}
ns.Share = Share

Share.DELAY = 0.5   -- Sekunden nach dem Annehmen, bis die erste Quest hinausgeht (bündelt mehrere)
Share.GAP = 2       -- höchstens eine Quest je so viele Sekunden
Share.RETRY = 10    -- Sekunden bis zum nächsten Versuch, wenn sie bei einem Mitspieler nicht ankam
Share.TRIES = 6     -- so oft versucht es ezQuest noch einmal

Share.queue = {}        -- { { id = questID, manual = bool, join = bool } … } in der Reihenfolge des Annehmens
Share.queued = {}       -- [questID] = true, solange sie in der Reihe steht
Share.shared = {}       -- [questID] = true: in dieser Sitzung schon geteilt (automatisch keine Wiederholung)
Share.fromPlayer = {}   -- [questID] = true: ein Spieler hat sie dir geteilt (nicht zurückteilen)
Share.count = 0         -- in dieser Sitzung geteilt
Share.lastID = nil      -- zuletzt geteilte Quest
Share.lastEntry = nil   -- ihr Eintrag der Reihe (für Share.Later)
Share.last = nil        -- Laufzeit (Core.Uptime) des letzten Teilens

-- Beitritt (ShareJoin.lua füllt dieselbe Tabelle). Leer, falls die neue Datei nach einem Update ohne Neustart des Spiels
-- noch nicht geladen ist: Teilen und Status gehen dann wie vorher.
Share.Join = {
    Hold = function() return nil end,
    Ready = function() return false end,
    Pushed = function() end,
    AskAgain = function() return false end,
    Guids = function() return nil end,
    Big = function() return false end,
    StatusLines = function() return {} end,
}

local Call, Num, Flag = Core.Call, Core.Num, Core.Flag

local function Locked()
    return Flag(Call(rawget(_G, "InCombatLockdown")), true) == true
end

---------------------------------------------------------------------------
-- Gruppe und Quest lesen
---------------------------------------------------------------------------

-- In einer Gruppe oder einem Schlachtzug (auch einer Instanzgruppe)? Gesperrt oder unbekannt heißt nein.
function Share.InGroup()
    return Flag(Call(rawget(_G, "IsInGroup")), false) == true or Flag(Call(rawget(_G, "IsInRaid")), false) == true
end

-- Wer das automatische Teilen schon übernimmt (ezCores Erkennung, Leitlinie 9): Name des Addons oder nil.
function Share.Other()
    return ns.OtherHandles("questShare")
end

function Share.Active()
    return ns.Enabled("autoShare") and not Share.Other()
end

-- Lässt sich die Quest jetzt teilen? Wie Blizzards Knopf: teilbar laut Client, nicht gesperrt, steht im Log.
function Share.Pushable(questID)
    questID = Num(questID)
    local log = C_QuestLog
    if not questID or questID <= 0 or type(log) ~= "table" then return false end
    if Flag(Call(log.IsPushableQuest, questID), false) ~= true then return false end
    if Flag(Call(log.IsQuestDisabledForSession, questID), false) == true then return false end
    return Num(Call(log.GetLogIndexForQuestID, questID)) ~= nil
end

-- Einheiten der Mitspieler (ohne dich): im Schlachtzug raid1…, sonst party1….
function Share.Members()
    local units = {}
    if Flag(Call(rawget(_G, "IsInRaid")), false) == true then
        local count = Num(Call(rawget(_G, "GetNumGroupMembers"))) or 0
        for i = 1, count do
            local unit = "raid" .. i
            if Core.UnitIs(unit, "player") ~= true then units[#units + 1] = unit end
        end
    else
        local count = Num(Call(rawget(_G, "GetNumSubgroupMembers"))) or 0
        for i = 1, count do units[#units + 1] = "party" .. i end
    end
    return units
end

-- Hat dieser Mitspieler die Quest? true | false | nil (Funktion fehlt, gesperrt, unbekannt)
function Share.OnQuest(unit, questID)
    local log = C_QuestLog
    if type(log) ~= "table" then return nil end
    return Core.Bool(Call(log.IsUnitOnQuest, unit, questID), nil)
end

-- Haben alle Mitspieler die Quest schon? Nur true, wenn es für JEDEN lesbar „ja“ ist; sonst (unbekannt, gesperrt,
-- jemand ohne) false – dann teilt ezQuest einfach, Blizzard meldet den Rest.
function Share.AllHave(questID)
    local units = Share.Members()
    if #units == 0 then return false end
    for _, unit in ipairs(units) do
        if Share.OnQuest(unit, questID) ~= true then return false end
    end
    return true
end

-- Teilbare Quests im Questlog (für „Jetzt teilen“ und die Zahl im Menü): Liste der Quest-IDs in der Reihenfolge des
-- Logs. Das Log liest ezCores Core.QuestLogEntries (ohne Kopfzeilen und versteckte Einträge, gesperrte Werte über
-- Core.Peek – derselbe Filter wie Vorschau und Route; Gegenprüfung W-1811 vom 18.11.2026, vorher eine eigene Schleife).
-- withoutAllHave: Quests, die laut Share.AllHave schon alle Mitspieler haben, fallen weg (wie beim Abarbeiten der
-- Reihe) – sonst zählte das Menü sie mit und „Jetzt teilen“ meldete „Teile n Quests“, obwohl keine hinausgeht.
function Share.PushableInLog(withoutAllHave)
    local list = {}
    for _, entry in ipairs(Core.QuestLogEntries() or {}) do
        if Share.Pushable(entry.id) and not (withoutAllHave and Share.AllHave(entry.id)) then
            list[#list + 1] = entry.id
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Teilen über Blizzards Weg
---------------------------------------------------------------------------

-- Eine Quest teilen wie Blizzards Knopf „Teilen“. → true, wenn sie hinausging.
function Share.Push(questID)
    local log = C_QuestLog
    local push = rawget(_G, "QuestLogPushQuest")
    if type(log) ~= "table" or type(push) ~= "function" then return false end
    local index = Num(Call(log.GetLogIndexForQuestID, questID))
    if not index then return false end
    local before = Num(Call(log.GetSelectedQuest))
    Call(log.SetSelectedQuest, questID)
    Share.pushing = true        -- ShareJoin.lua beobachtet QuestLogPushQuest: das hier meldet Next selbst
    local ok = pcall(push, index)
    Share.pushing = nil
    -- Zurück wie Blizzards QuestMapQuestOptions_AbandonQuest (setzt die vorher gewählte Quest ohne Bedingung zurück):
    -- auch 0 („keine gewählt“), sonst bliebe die geteilte Quest ohne Klick in Blizzards Questlog gewählt
    -- (Gegenprüfung W-1811 vom 18.11.2026)
    if before and before ~= questID then Call(log.SetSelectedQuest, before) end
    return ok
end

-- Den nächsten Eintrag der Reihe prüfen und teilen. → true, wenn geteilt wurde.
local function Next(entry)
    local questID = entry.id
    if not Share.InGroup() then return false end
    if entry.join then
        if not Share.Join.Ready(questID) then return false end            -- inzwischen aus, zu weit weg oder schon da
    elseif not entry.manual and not Share.Active() then
        return false                                                      -- inzwischen ausgeschaltet
    end
    if not Share.Pushable(questID) or Share.AllHave(questID) then return false end
    if entry.again then
        local again = Share.Join.AskAgain(questID, entry.guids)
        if again == nil then Share.Later(entry) end     -- wem sie fehlt, ist gerade nicht in der Nähe
        if not again then return false end
    end
    if not Share.Push(questID) then
        if entry.join then Share.Join.broken = true end     -- Blizzards Teilen scheitert: nicht alle paar Sekunden wieder
        return false
    end
    Share.shared[questID] = true
    Share.count = Share.count + 1
    Share.lastID, Share.lastEntry = questID, entry
    entry.guids = entry.guids or Share.Join.Guids()
    Share.Join.Pushed(questID)
    return true
end

local scheduled = false
local function Schedule(delay)
    if scheduled then return end
    scheduled = true
    C_Timer.After(delay, function()
        scheduled = false
        ns.Try("Share", Share.Pump)
    end)
end

-- Die Reihe abarbeiten: höchstens eine Quest je Share.GAP Sekunden, nie im Kampf. → Anzahl geteilter (0 oder 1).
function Share.Pump()
    if #Share.queue == 0 then return 0 end
    if Locked() then
        Share.waitingCombat = true
        ns.AfterCombat(function()
            Share.waitingCombat = nil
            Schedule(Share.DELAY)
        end, "share")
        return 0
    end
    local now = Core.Uptime()
    if Share.last and now < Share.last + Share.GAP then
        Schedule(Share.last + Share.GAP - now)
        return 0
    end
    if Share.Join.Hold(now) then        -- ein Mitspieler hat die vorige noch nicht beantwortet
        Schedule(Share.GAP)
        return 0
    end
    local done = 0
    while #Share.queue > 0 and done == 0 do
        local entry = table.remove(Share.queue, 1)
        Share.queued[entry.id] = nil
        if Next(entry) then
            Share.last = now
            done = 1
        end
    end
    if #Share.queue > 0 then Schedule(Share.GAP) end
    return done
end

-- Quest in die Reihe stellen. manual: ein Klick („Jetzt teilen“) – dann auch, wenn sie schon geteilt wurde; join: sie
-- fehlt jemandem, der gerade dazukam (ShareJoin.lua merkt selbst, wer schon gefragt wurde).
-- → true, wenn sie neu in der Reihe steht.
function Share.Add(questID, manual, join)
    questID = Num(questID)
    if not questID or questID <= 0 then return false end
    if Share.queued[questID] then
        -- ein Klick geht vor: aus dem wartenden Eintrag ohne Klick wird einer mit Klick (sonst ginge der Klick verloren,
        -- sobald der Eintrag wegen seiner eigenen Regeln entfällt)
        for _, entry in ipairs(Share.queue) do
            if entry.id == questID and manual and (entry.again or not entry.manual) then
                entry.manual, entry.join, entry.again, entry.guids = true, false, nil, nil
                return true
            end
        end
        return false
    end
    if not manual and not join and (Share.shared[questID] or Share.fromPlayer[questID]) then return false end
    Share.queue[#Share.queue + 1] = { id = questID, manual = manual == true, join = join == true }
    Share.queued[questID] = true
    Schedule(Share.DELAY)
    return true
end

-- Die Quest kam bei einem Mitspieler nicht an: später noch einmal (Beitritt, entry.join: das übernimmt ShareJoin.lua
-- selbst). → true, wenn vorgemerkt
function Share.Later(entry)
    if type(entry) ~= "table" or entry.join or entry.later or (entry.tries or 0) >= Share.TRIES or Share.Join.Big() then
        return false
    end
    entry.tries, entry.later = (entry.tries or 0) + 1, true
    C_Timer.After(Share.RETRY, function()
        entry.later = nil
        ns.Try("Share", function()
            if not Share.InGroup() then return end
            entry.again = true
            if Share.queued[entry.id] then
                -- steht sie inzwischen nur wegen eines Beitritts in der Reihe, gelten die Regeln dieses Eintrags
                for i, waiting in ipairs(Share.queue) do
                    if waiting.id == entry.id and waiting.join then Share.queue[i] = entry end
                end
                return
            end
            Share.queue[#Share.queue + 1] = entry
            Share.queued[entry.id] = true
            Schedule(0)
        end)
    end)
    return true
end

-- QUEST_ACCEPTED: Forever liefert die Quest-ID (QuestLogDocumentation: Payload questId); ältere Clients
-- (questLogIndex, questID) – dann gilt das zweite Argument. Die Markierung „von einem Spieler geteilt“ gilt nur für
-- diese eine Annahme und wird dabei verbraucht.
function Share.OnAccepted(_, first, second)
    local questID = Num(second) or Num(first)
    if not questID then return false end
    local fromPlayer = Share.fromPlayer[questID]
    Share.fromPlayer[questID] = nil
    if fromPlayer or not Share.Active() or not Share.InGroup() then return false end
    return Share.Add(questID, false)
end

-- QUEST_DETAIL: Ist das Gegenüber ein Spieler, hat er dir die Quest geteilt – nicht zurückteilen. Zeigt dir danach
-- ein NPC dieselbe Quest, gilt das Angebot des Spielers nicht mehr (abgelehnt; Gegenprüfung W-1811 vom 18.11.2026 –
-- vorher sperrte ein abgelehntes Angebot die Quest für die ganze Sitzung). Unbekannt (gesperrt): nichts ändern.
function Share.OnDetail()
    local isPlayer = Core.UnitIs("questnpc")
    if isPlayer == nil then return false end
    local questID = Num(Call(rawget(_G, "GetQuestID")))
    if not questID or questID <= 0 then return false end
    Share.fromPlayer[questID] = (isPlayer == true) or nil
    return isPlayer == true
end

-- Ein Klick: alle teilbaren Quests des Logs in die Reihe (Zahnrad-Menü, Einstellungsseite). → Anzahl in der Reihe.
function Share.Now()
    if not Share.InGroup() then
        ns.Print(L.SHARE_SOLO)
        return 0
    end
    local added = 0
    for _, questID in ipairs(Share.PushableInLog(true)) do
        if Share.Add(questID, true) then added = added + 1 end
    end
    if added == 0 then
        ns.Print(L.SHARE_NONE)
    else
        ns.Print(L.SHARE_QUEUED:format(added, Share.GAP))
    end
    return added
end

---------------------------------------------------------------------------
-- Zahnrad-Menü am Questlog (Abschnitt „ezQuest“, QuestId.BuildMenu) und Status
---------------------------------------------------------------------------

function Share.AddMenu(root)
    local Menu = Core.Menu
    Menu.Tip(Menu.Toggle(root, L.OPT_autoShare, function() return ns.Enabled("autoShare") end,
        function(on) ns.SetSetting("autoShare", on) end), L.OPT_autoShare, L.OPT_autoShare_TIP)
    Menu.Tip(Menu.Toggle(root, L.OPT_joinShare, function() return ns.Enabled("joinShare") end,
        function(on) ns.SetSetting("joinShare", on) end), L.OPT_joinShare, L.OPT_joinShare_TIP)
    local count = Share.InGroup() and #Share.PushableInLog(true) or 0
    local entry = Menu.Button(root, L.SHARE_MENU_NOW:format(count), function() ns.Try("Share", Share.Now) end)
    local tip = L.SHARE_MENU_NOW_TIP
    if not Share.InGroup() then tip = tip .. "\n\n" .. L.SHARE_SOLO end
    Menu.Tip(entry, L.OPT_SHARE_NOW, tip)
    if count == 0 and type(entry) == "table" and type(entry.SetEnabled) == "function" then
        pcall(entry.SetEnabled, entry, false)
    end
    return true
end

-- Zeilen für /ezq status: zuletzt geteilt und was in der Reihe wartet. nil, wenn es nichts zu sagen gibt.
function Share.StatusLines()
    local lines = {}
    if Share.lastID then
        local title = Core.QuestTitle(Share.lastID) or tostring(Share.lastID)
        lines[#lines + 1] = L.STATUS_SHARE_LAST:format(title, Share.count)
    end
    if #Share.queue > 0 then
        lines[#lines + 1] = L.STATUS_SHARE_QUEUED:format(#Share.queue)
            .. (Share.waitingCombat and (" – " .. L.STATUS_SHARE_COMBAT)
                or Share.Join.Hold(Core.Uptime()) and (" – " .. L.STATUS_SHARE_ANSWER) or "")
    end
    if Share.lastID and Share.Join.AnswerLine then lines[#lines + 1] = Share.Join.AnswerLine() end
    for _, line in ipairs(Share.Join.StatusLines()) do lines[#lines + 1] = line end
    return lines
end

---------------------------------------------------------------------------
-- Hinweis an der Questverfolgung (ezCores Core.OptInHint; Entscheidung 2 des Nutzers vom 18.11.2026)
---------------------------------------------------------------------------

-- Einmal je Account, wenn du in einer Gruppe eine Quest annimmst und das Teilen aus ist. Nicht allein, nicht, wenn
-- ein anderes Addon das Teilen übernimmt, und nicht, solange dort die Erklärblase von ezQuests Rundgang steht.
function Share.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezQuest.autoShare", {
        owner = ADDON,
        window = "tracker",
        label = function() return L.OPT_autoShare end,
        what = function() return L.OPTIN_autoShare end,
        where = function()
            return Core.SettingsPathText("ezQuest", "OPT_HEADER_SHARE", "OPT_autoShare", L) .. " " .. L.OPTIN_WHERE_autoShare
        end,
        isOn = function() return ns.Enabled("autoShare") end,
        enable = function()
            ns.SetSetting("autoShare", true)
            return ns.Enabled("autoShare")
        end,
        applies = function()
            local tour = ns.Tracker and ns.Tracker.TourShowing
            return Share.InGroup() and not Share.Other() and not (tour and tour())
        end,
        side = "left",
    })
end
Share.RegisterOptInHint()

ns.OnReady(function()
    ns.On("QUEST_ACCEPTED", Share.OnAccepted)
    ns.On("QUEST_DETAIL", Share.OnDetail)
end)
