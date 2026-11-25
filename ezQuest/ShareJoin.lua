local ADDON, ns = ...
local L = ns.L
local Core = ezCore
local Share = ns.Share

--[[
    Fehlende Quests teilen, wenn ein Mitspieler dazukommt (Wunsch des Nutzers vom 24.11.2026, wörtlich „werden bei
    gruppeneinladung die fehlenden quests autom. geteilt? das wäre geil“). Trittst du einer Gruppe bei oder jemand
    deiner, bietet ezQuest die teilbaren Quests deines Logs an, die dem Neuen fehlen – über die gedrosselte Reihe von
    Share.lua (Share.Add, Share.Pump: eine Quest je Share.GAP Sekunden, nie im Kampf).

    Blizzards Schnittstellen (Gethe/wow-ui-source, Zweig forever, Commit c01a87b549bb, gelesen am 24.11.2026):
      Wer hat die Quest?  C_QuestLog.IsUnitOnQuest(unit, questID) → bool, keine gesperrte Antwort (QuestLogDocumentation);
          Blizzard zählt damit selbst die Mitspieler je Quest (QuestUtils.lua, QuestUtils_GetNumPartyMembersOnQuest). Ob
          der Client das Questlog eines weit entfernten Mitspielers kennt, ist nicht belegt – darum fragt ezQuest erst,
          wenn er in der Nähe ist, und teilt beim Beitritt nur auf ein lesbares „nein“.
      Wie weit?  Eine Reichweite des Teilens nennt Blizzards Quelle nicht; die Meldung ERR_QUEST_PUSH_TOO_FAR_S („%s ist
          zu weit entfernt, um diese Quest anzunehmen.“) steht in den Texten des Builds 1.60.1.71037 (wago.tools,
          GlobalStrings 41051). Laut warcraft.wiki.gg (Quest, „Sharing quests“) fiel die Grenze 2008 mit Fassung 3.0.3;
          ob sie auf Forever gilt, zeigt erst der Spieltest. ezQuest wartet darum, bis der Neue in der Nähe ist:
          verbunden, am Leben, für den Client zu sehen (UnitIsVisible: gleiche Karte und Phase) und höchstens Join.RANGE
          Yards weg (UnitDistanceSquared, laut Doku nicht gesperrt, in der Daten-Probe des Nutzers für party1 gelesen:
          37 und 10860; in Instanzen ohne Antwort, dann genügt UnitIsVisible). UnitInRange scheidet aus (SecretReturns).
          Meldet Blizzard trotzdem „zu weit“, halbiert ezQuest die Entfernung dieses Versuchs als neue Grenze der Sitzung
          und versucht es näher dran noch einmal (Join.TRIES).
      Einer nach dem anderen:  Solange der Mitspieler das Fenster einer geteilten Quest offen hat, meldet Blizzard für die
          nächste „… ist beschäftigt“ (ERR_QUEST_PUSH_BUSY_S). Nach „Ihr teilt die Quest mit …“ (…_SUCCESS_S) wartet die
          Reihe darum auf die Antwort, höchstens Join.ANSWER Sekunden. Die Antworten kommen als Systemzeile
          (warcraft.wiki.gg: „a yellow system message“); gelesen wird nur der Text (CHAT_MSG_SYSTEM, UI_INFO_MESSAGE,
          UI_ERROR_MESSAGE), kurz nach einem Teilen und nie ein gesperrter. Bleibt er gesperrt oder anders, gilt nur der
          Abstand der Reihe und Blizzards IsUnitOnQuest: Hat er sie, geht es gleich weiter, sonst nach Join.BLIND Sekunden
          (Fehler des Nutzers vom 24.11.2026: von mehreren Quests kam nur die erste an). Wer eine Quest so lange nicht beantwortet, hält die Reihe nicht noch einmal auf
          (Join.silent), und die Automatik lässt ihm Join.PAUSE Sekunden Ruhe. Über Join.GROUP_MAX Spielern wartet sie nie.
      An wen?  QuestLogPushQuest kennt kein Ziel: Blizzards Teilen geht immer an die ganze Gruppe. Damit niemand zweimal
          gefragt wird, entfällt eine Quest automatisch, sobald ein anderer Mitspieler ohne sie in dieser Sitzung schon
          gefragt wurde (Join.offered „asked“); wer sie laut Blizzards Antwort nicht nehmen kann (Stufe, Voraussetzung,
          schon erledigt …), zählt nicht („unfit“), er bekäme kein Fenster.

    Regeln:
      - Sendet ohne Klick an andere Spieler: ab Werk AUS (joinShare), einmal je Account ein Hinweis an Blizzards
        Questverfolgung (Core.OptInHint), sobald einem Neuen Quests fehlen. Ohne Automatik erscheint derselbe Anlass als
        Knopf am Kopf „Quests“ der Verfolgung (joinButton, ab Werk an, sendet nur auf Klick; Leitlinie 3).
      - Neu ist nur, wer dazukommt: gemerkt wird die GUID, darum nicht bei /reload oder Einloggen (Join.SETTLE Sekunden
        Bestandsaufnahme, im Schlachtfeld nachgeholt, sobald die eigene Gruppe wieder da ist), Zonenwechsel, Umwandlung in einen Schlachtzug oder Wiederverbinden; wer verschwindet und binnen
        Join.RETURN Sekunden zurückkommt, ist nicht neu.
      - Nur Quests, die beim Beitritt schon im Log standen (neu angenommene gehören zu „Angenommene Quests teilen“).
      - Nicht in Schlachtfeld und Arena, nicht in Instanzgruppen der Dungeonsuche, nicht über Join.GROUP_MAX Spielern.
      - Auswahl (joinShareWhich): „near“ = verfolgt oder im jetzigen Gebiet (ab Werk), „all“ = alle teilbaren; zuerst
        verfolgte im Gebiet, fertige zuletzt.
      - Höchstens Join.PER_PLAYER Quests je Neuem automatisch: Jede öffnet bei ihm ein Fenster, das er beantworten muss;
        fünf sind in gut einer halben Minute durch und decken die üblichen Quests eines Gebiets. Der Rest steht am Knopf.
      - Höchstens Join.WAIT Sekunden nach dem Beitritt (bis dahin ist man meist zusammen), danach ist der Neue nicht mehr neu.
      - Rücksicht (Leitlinie 9): teilt ein anderes Addon Quests (Funktion questShare), hält sich ezQuest zurück.
      - Chat: keine eigene Zeile (Blizzard meldet jede Antwort); /ezq status nennt, wer neu ist und worauf ezQuest wartet.
]]

local Join = Share.Join     -- in Share.lua angelegt (mit leeren Fassungen)

Join.PER_PLAYER = 5     -- Quests je Neuem, die ohne Klick hinausgehen
Join.GROUP_MAX = 10     -- Spieler samt dir; größere Schlachtzüge nicht
Join.WAIT = 600         -- Sekunden: so lange wartet ezQuest auf einen Neuen, der noch zu weit weg ist
Join.POLL = 5           -- Sekunden zwischen zwei Blicken, solange jemand neu ist
Join.SETTLE = 10        -- Sekunden nach Einloggen oder /reload: wer dann da ist, ist nicht neu
Join.RETURN = 120       -- Sekunden: wer so schnell zurück ist, ist nicht neu
Join.READS = 5          -- so oft liest ezQuest die Gruppe noch einmal, solange eine GUID fehlt
Join.RANGE = 100        -- Yards: „in der Nähe“ (Grundwert, siehe Join.range)
Join.RANGE_MIN = 10     -- Yards: enger wird die Grenze nach „zu weit“ nie
Join.ANSWER = 30        -- Sekunden, die eine geteilte Quest höchstens auf ihre Antwort warten lässt
Join.BLIND = 30         -- Sekunden bis zur nächsten Quest, wenn keine Antwort zu lesen war und er sie noch nicht hat
Join.TRIES = 2          -- neue Versuche nach „beschäftigt“, „tot“ oder „zu weit“, je Neuem und Quest
Join.PAUSE = 60         -- Sekunden Ruhe für einen Neuen, der eine Quest nicht beantwortet hat
Join.RETRY = 15         -- Sekunden bis zum nächsten Versuch bei diesem Neuen
Join.TIP_QUESTS = 8     -- Titel im Tooltip des Knopfs

Join.present = {}       -- [GUID] = true: steht in der Gruppe
Join.gone = {}          -- [GUID] = Laufzeit, seit der sie fehlt
Join.new = {}           -- [GUID] = { since, left, log = { [questID] = true }, tries = {}, retryAt, full }
Join.offered = {}       -- [GUID][questID] = "asked" (gefragt) | "unfit" (kann sie nicht nehmen)
Join.open = {}          -- [GUID] = Laufzeit, bis zu der ezQuest auf die Antwort wartet
Join.openID = {}        -- [GUID] = die Quest dazu
Join.heard = nil        -- Blizzards letzte Zeile zur zuletzt geteilten Quest (Text), nil: noch keine gelesen
Join.silent = {}        -- [GUID] = true: hat eine Quest nicht beantwortet – auf ihn wartet die Reihe nicht mehr
Join.fresh = {}         -- [GUID] = true: beim letzten Teilen zum ersten Mal nach dieser Quest gefragt
Join.lastID = nil       -- zuletzt geteilte Quest (ezQuest oder Blizzards Knopf)
Join.lastAt = nil       -- Laufzeit dazu
Join.broken = nil       -- Blizzards Teilen schlug fehl: in dieser Sitzung nichts mehr ohne Klick, kein Knopf
Join.range = Join.RANGE -- gelernte Grenze dieser Sitzung (nach „zu weit“)
Join.baseline = false   -- läuft die Bestandsaufnahme? (endet, wenn die Gruppe nach baseUntil einmal ganz lesbar war)
Join.baseUntil = 0      -- frühestes Ende der Bestandsaufnahme (Laufzeit)
Join.reads = 0          -- so oft schon noch einmal gelesen, weil eine GUID fehlte
Join.dismissed = false  -- Knopf für die jetzigen Neuen ausgeblendet (Rechtsklick)

local Call, Num, Flag = Core.Call, Core.Num, Core.Flag

---------------------------------------------------------------------------
-- Gruppe: wer ist da, wer ist neu?
---------------------------------------------------------------------------

-- GUID eines Spielers; false: lesbar, aber kein Spieler (Begleiter); nil: gesperrt oder noch unbekannt.
function Join.Guid(unit)
    local guid = Core.Plain(Call(rawget(_G, "UnitGUID"), unit))
    if type(guid) ~= "string" or guid == "" then return nil end
    return guid:find("^Player%-") ~= nil and guid
end

-- Schlachtfeld, Arena oder Gruppe der Dungeonsuche (Instanzgruppe): hier weder teilen noch die Gruppe neu zählen.
function Join.Excluded()
    local _, kind = Core.InInstance()
    if kind == "pvp" or kind == "arena" then return true end
    if Core.GroupChannel() == "INSTANCE_CHAT" then return true end
    return Flag(Call(rawget(_G, "HasLFGRestrictions")), false) == true
end

-- Darf ezQuest hier anbieten? Gruppe bis Join.GROUP_MAX, nicht ausgenommen, kein anderes Addon zuständig, Blizzards
-- Teilen geht.
function Join.Allowed()
    return not Join.broken and type(rawget(_G, "QuestLogPushQuest")) == "function" and Share.InGroup()
        and not Join.Excluded() and #Share.Members() + 1 <= Join.GROUP_MAX and not Share.Other()
end

-- Bestandsaufnahme: Wer ab jetzt in der Gruppe steht, ist nicht neu, bis sie nach Join.SETTLE Sekunden ganz gelesen ist.
function Join.Base()
    Join.baseline, Join.baseUntil = true, Core.Uptime() + Join.SETTLE
    C_Timer.After(Join.SETTLE, function() ns.Try("ShareJoin", Join.Roster) end)
end

-- Gruppe neu lesen. → Anzahl neu Hinzugekommener
function Join.Roster()
    if Join.Excluded() then
        Join.frozen = true
        return 0
    end
    local now = Core.Uptime()
    -- im Schlachtfeld eingeloggt: die eigene Gruppe erscheint erst kurz nach dem Verlassen
    if Join.frozen then
        Join.frozen = nil
        if Join.baseline then Join.Base() end
    end
    local units = Share.InGroup() and Share.Members() or {}
    local seen, unreadable, added = {}, false, 0
    for _, unit in ipairs(units) do
        local guid = Join.Guid(unit)
        if guid then seen[guid] = true elseif guid == nil then unreadable = true end
    end
    -- nicht lesbar heißt nicht gegangen: erst streichen, wenn alle lesbar sind
    if not unreadable then
        for guid in pairs(Join.present) do
            if not seen[guid] then
                Join.present[guid], Join.gone[guid] = nil, now
                Join.new[guid], Join.open[guid] = nil, nil
            end
        end
    end
    -- gerade beigetreten und noch ohne GUID: kurz darauf noch einmal lesen (nicht endlos: gesperrt bleibt gesperrt)
    if not unreadable then
        Join.reads = 0
    elseif Join.reads < Join.READS and not Join.rereading then
        Join.reads, Join.rereading = Join.reads + 1, true
        C_Timer.After(Join.POLL, function()
            Join.rereading = nil
            ns.Try("ShareJoin", Join.Roster)
        end)
    end
    local settling, log = Join.baseline, nil
    for guid in pairs(seen) do
        if not Join.present[guid] then
            local back = Join.gone[guid] and now - Join.gone[guid] < Join.RETURN
            Join.present[guid], Join.gone[guid] = true, nil
            if not settling and not back then
                if not log then     -- das Log einmal je Durchlauf (Beitritt zu einer großen Gruppe); nur gelesen
                    log = {}
                    for _, entry in ipairs(Core.QuestLogEntries() or {}) do log[entry.id] = true end
                end
                Join.new[guid] = { since = now, left = Join.PER_PLAYER, log = log, tries = {}, retryAt = 0 }
                added = added + 1
            end
        end
    end
    if Join.baseline and now >= Join.baseUntil and (not unreadable or Join.reads >= Join.READS) then Join.baseline = false end
    if added > 0 then
        Join.dismissed = false
        Join.Poll()
    end
    return added
end

-- Ist der Mitspieler nah genug? → true | false, Grund ("offline" | "dead" | "far"), Entfernung in Yards (wenn lesbar)
function Join.Near(unit)
    if Flag(Call(rawget(_G, "UnitIsConnected"), unit), true) == false then return false, "offline" end
    if Flag(Call(rawget(_G, "UnitIsDeadOrGhost"), unit), false) == true then return false, "dead" end
    if Core.Bool(Call(rawget(_G, "UnitIsVisible"), unit), nil) ~= true then return false, "far" end
    local squared, checked = Call(rawget(_G, "UnitDistanceSquared"), unit)
    squared = Num(squared)
    if Core.Bool(checked, nil) == true and squared and squared >= 0 then
        local yards = math.sqrt(squared)
        return yards <= Join.range, yards > Join.range and "far" or nil, yards
    end
    return true
end

-- Mitspieler mit allem, was die Auswahl braucht (je Durchlauf einmal gelesen).
local function Snapshot()
    local now, out = Core.Uptime(), {}
    for _, unit in ipairs(Share.Members()) do
        local guid = Join.Guid(unit)
        local new = guid and Join.new[guid] or nil
        local near, why, yards = Join.Near(unit)
        out[#out + 1] = { unit = unit, guid = guid, new = new, near = near, why = why, yards = yards,
            ready = new ~= nil and near and not new.full and now >= new.retryAt }
    end
    return out
end

---------------------------------------------------------------------------
-- Auswahl
---------------------------------------------------------------------------

-- Neue, denen die Quest lesbar fehlt und die jetzt gefragt werden können; nil, wenn es keinen gibt. Ohne Klick
-- (manual nicht true) auch nil, wenn ein anderer ohne die Quest schon gefragt wurde – er bekäme das Fenster noch einmal –
-- oder ein anderer Neuer seine Join.PER_PLAYER schon hatte (das Teilen geht auch an ihn).
function Join.Targets(questID, manual, members)
    local targets
    for _, m in ipairs(members or Snapshot()) do
        local has = Share.OnQuest(m.unit, questID)
        if has ~= true then
            local state = m.guid and Join.offered[m.guid] and Join.offered[m.guid][questID] or nil
            if not manual and (state == "asked" or (m.new and m.new.left <= 0 and state ~= "unfit")) then return nil end
            if m.ready and has == false and not state and m.new.log[questID] then
                targets = targets or {}
                targets[#targets + 1] = m
            end
        end
    end
    return targets
end

-- Rang einer Quest des Logs: verfolgt im Gebiet 3, im Gebiet 2, verfolgt 1, sonst 0 (Items.lua kennt beides).
function Join.Rank(entry)
    local zone = Core.Plain(Call(rawget(_G, "GetRealZoneText")))
    local inZone = ns.Items.InZone(entry.info, entry.header, zone)
    return (inZone and 2 or 0) + (ns.Items.Watched(C_QuestLog, entry.id) and 1 or 0)
end

-- Quests, die einem Neuen fehlen, beste zuerst. → Liste der Quest-IDs, Liste der Neuen { guid, unit }
function Join.List(manual)
    local list, rows, who, named = {}, {}, {}, {}
    if not Join.Allowed() then return list, who end
    local all = ns.S.joinShareWhich == "all"
    local members = Snapshot()
    for order, entry in ipairs(Core.QuestLogEntries() or {}) do
        local targets = not Share.queued[entry.id] and Share.Pushable(entry.id) and Join.Targets(entry.id, manual, members)
        if targets then
            local rank = Join.Rank(entry)
            if all or rank > 0 then
                rows[#rows + 1] = { id = entry.id, rank = rank, done = Core.QuestReady(entry.id) == true, order = order }
                for _, m in ipairs(targets) do
                    if not named[m.guid] then
                        named[m.guid] = true
                        who[#who + 1] = m
                    end
                end
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.done ~= b.done then return b.done end
        if a.rank ~= b.rank then return a.rank > b.rank end
        return a.order < b.order
    end)
    for i, row in ipairs(rows) do list[i] = row.id end
    return list, who
end

---------------------------------------------------------------------------
-- Anbieten (Reihe von Share.lua)
---------------------------------------------------------------------------

-- Darf eine Quest der Reihe, die beim Beitritt hineinkam, jetzt hinaus? (Share.lua, Next)
function Join.Ready(questID)
    return ns.Enabled("joinShare") and Join.Allowed() and Join.Targets(questID, false) ~= nil
end

-- Dieser Mitspieler wurde nach der Quest gefragt.
local function Ask(m, questID)
    local states = Join.offered[m.guid]
    if not states then
        states = {}
        Join.offered[m.guid] = states
    end
    if states[questID] == "asked" then return end       -- schon früher gefragt: „beschäftigt“ nimmt das nicht zurück
    states[questID] = "asked"
    Join.fresh[m.guid] = true
    if m.new then m.new.left = m.new.left - 1 end
end

-- Eine Quest ging hinaus (gleich auf welchem Weg): wen Blizzard damit gefragt hat, merken.
function Join.Pushed(questID)
    Join.lastID, Join.lastAt, Join.fresh, Join.heard = questID, Core.Uptime(), {}, nil
    for _, m in ipairs(Snapshot()) do
        if m.guid and m.near and Share.OnQuest(m.unit, questID) ~= true then Ask(m, questID) end
    end
end

-- GUIDs der jetzigen Mitspieler (für Share.Later: nachgereicht wird nur, wer beim ersten Mal dabei war).
function Join.Guids()
    local guids = {}
    for _, unit in ipairs(Share.Members()) do
        local guid = Join.Guid(unit)
        if guid then guids[guid] = true end
    end
    return guids
end

-- Zu groß zum Warten und Nachreichen?
function Join.Big() return #Share.Members() + 1 > Join.GROUP_MAX end

-- Noch einmal anbieten, was bei einem Mitspieler nicht ankam (guids: wer beim ersten Mal dabei war)? → true: in der Nähe hat
-- sie einer davon nicht, der noch nicht gefragt wurde; nil: noch nicht (er ist weiter weg, oder ein anderer hat sein
-- Fenster offen); false: nein – niemand mehr, oder einer ohne sie wurde schon gefragt und bekäme das Fenster noch einmal
function Join.AskAgain(questID, guids)
    local yes, wait, open = false, false, false
    for _, m in ipairs(Snapshot()) do
        if Share.OnQuest(m.unit, questID) ~= true then
            local state = m.guid and Join.offered[m.guid] and Join.offered[m.guid][questID] or nil
            if state == "asked" then
                if not Join.open[m.guid] then return false end
                open = true
            elseif not state and (not guids or m.guid and guids[m.guid]) then
                if m.near then yes = true else wait = true end
            end
        end
    end
    if open then return nil end
    if yes then return true end
    if wait then return nil end
    return false
end

-- Wer die angebotene Quest inzwischen laut Client hat, hat geantwortet – auch, wenn Blizzards Zeile fehlte.
local function Settle()
    if next(Join.open) == nil then return end
    for _, unit in ipairs(Share.Members()) do
        local guid = Join.Guid(unit)
        if guid and Join.open[guid] and Join.openID[guid] and Share.OnQuest(unit, Join.openID[guid]) == true then
            Join.open[guid], Join.silent[guid] = nil, nil
        end
    end
end

-- Sekunden, die die Reihe noch auf eine Antwort wartet, oder nil. Nicht in großen Gruppen: dort wartete man ewig.
function Join.Hold(now)
    local hold
    Settle()
    for guid, untilTime in pairs(Join.open) do
        if not Join.present[guid] then
            Join.open[guid] = nil
        elseif untilTime <= now then
            -- nicht beantwortet: die Reihe wartet nicht noch einmal auf ihn, die Automatik lässt ihn eine Weile in Ruhe
            Join.open[guid], Join.silent[guid] = nil, true
            if Join.new[guid] then Join.new[guid].retryAt = math.max(Join.new[guid].retryAt, now + Join.PAUSE) end
        else
            hold = math.max(hold or 0, untilTime - now)
        end
    end
    -- keine Zeile gelesen: warten, solange die Quest einem gerade Gefragten noch fehlt
    if not hold and not Join.heard and Join.lastAt and now < Join.lastAt + Join.BLIND then
        for _, unit in ipairs(Share.Members()) do
            local guid = Join.Guid(unit)
            if guid and Join.fresh[guid] and Share.OnQuest(unit, Join.lastID) ~= true then
                hold = Join.lastAt + Join.BLIND - now
                break
            end
        end
    end
    if hold and Join.Big() then return nil end
    return hold
end

-- Wer nicht mehr neu ist (Zeit um), fällt weg. → true, solange noch jemand neu ist
local function Expire()
    local now = Core.Uptime()
    for guid, new in pairs(Join.new) do
        if now >= new.since + Join.WAIT then Join.new[guid] = nil end
    end
    return next(Join.new) ~= nil
end

-- Ein Blick: anbieten (mit joinShare), Knopf nachziehen. → Anzahl neu in die Reihe gestellter Quests
function Join.Check()
    local waiting = Expire()
    local added = 0
    if waiting and not Core.InCombat() and ns.Enabled("joinShare") then
        for _, questID in ipairs(Join.List(false)) do
            if Share.Add(questID, false, true) then added = added + 1 end
        end
    end
    Join.UpdateButton()
    return added
end

local polling = false
function Join.Poll()
    if polling then return end
    polling = true
    C_Timer.After(Join.POLL, function()
        polling = false
        ns.Try("ShareJoin", Join.Check)
        if next(Join.new) then Join.Poll() end
    end)
end

-- Ein Klick am Knopf: alle fehlenden Quests der Auswahl in die Reihe, ohne Höchstzahl. → Anzahl
function Join.Click()
    local added = 0
    for _, questID in ipairs(Join.List(true)) do
        if Share.Add(questID, true) then added = added + 1 end
    end
    if added > 0 then ns.Print(L.SHARE_QUEUED:format(added, Share.GAP)) end
    Join.UpdateButton()
    return added
end

---------------------------------------------------------------------------
-- Blizzards Antworten (Systemzeilen der letzten geteilten Quest)
---------------------------------------------------------------------------

-- Teil des Textnamens ERR_QUEST_PUSH_<Teil>_S → Bedeutung
local ANSWERS = {
    SUCCESS = "open", ACCEPTED = "close", ONQUEST = "close", DECLINED = "close", LOG_FULL = "full",
    BUSY = "retry", DEAD = "retry", TOO_FAR = "far",
    INVALID = "unfit", ALREADY_DONE = "unfit", DIFFERENT_SERVER_DAILY = "unfit", PREREQUISITE = "unfit",
    LOW_LEVEL = "unfit", HIGH_LEVEL = "unfit", CLASS = "unfit", RACE = "unfit", LOW_FACTION = "unfit",
    HIGH_FACTION = "unfit", EXPANSION = "unfit", WRONG_FACTION = "unfit",
    -- ohne Namen: gilt für alle, auf die ezQuest gerade wartet
    TIMER_EXPIRED = "all", NOT_ALLOWED = "all", NOT_DAILY = "all", NOT_IN_PARTY = "all", CROSS_FACTION_RESTRICTED = "all",
}
local patterns
local function Patterns()
    if patterns then return patterns end
    patterns = {}
    for part, kind in pairs(ANSWERS) do
        local pattern = Core.FormatToPattern(rawget(_G, "ERR_QUEST_PUSH_" .. part .. "_S"))
        if pattern then patterns[#patterns + 1] = { pattern = pattern, kind = kind } end
    end
    return patterns
end

-- Mitspieler zu einem Namen aus Blizzards Zeile. → { unit, guid, yards … } oder nil
local function ByName(name)
    for _, m in ipairs(Snapshot()) do
        local full = Core.UnitFullName(m.unit)
        local short = Core.Plain(Call(rawget(_G, "UnitName"), m.unit))
        if m.guid and (name == full or name == short or (full and name == Core.ShortName(full))) then
            return m
        end
    end
    return nil
end

local lastKind, lastGuid, lastAt
-- Text einer Systemzeile auswerten. → Bedeutung (siehe ANSWERS) oder nil
function Join.OnText(text)
    local now = Core.Uptime()
    local questID = Join.lastID
    if not questID or not Join.lastAt or now - Join.lastAt > 2 * Join.ANSWER then return nil end
    text = Core.Plain(text)
    if type(text) ~= "string" or text == "" then return nil end
    text = Core.PlainText(text)
    for _, entry in ipairs(Patterns()) do
        local found, _, name = text:find(entry.pattern)
        if found then
            if entry.kind == "all" then
                Join.open = {}
                Join.heard = text
                return "all"
            end
            local m = type(name) == "string" and ByName((name:gsub("^%[(.-)%]$", "%1")))
            if m then
                local kind, guid = entry.kind, m.guid
                -- eine späte Antwort auf die vorige Quest: für diese wurde er noch nicht gefragt und hat sie nicht
                if kind == "close" and Join.openID[guid] ~= questID and Share.OnQuest(m.unit, questID) == false then
                    return nil
                end
                Join.heard = text
                -- dieselbe Antwort über zwei Ereignisse zählt einmal
                if kind == lastKind and guid == lastGuid and lastAt and now - lastAt < 1 then return kind end
                lastKind, lastGuid, lastAt = kind, guid, now
                Join.Answer(kind, m, questID, now)
                return kind
            end
        end
    end
    return nil
end

function Join.Answer(kind, m, questID, now)
    local guid, new = m.guid, m.new
    if kind == "open" then
        -- gefragt, auch wenn er für ezQuest zu weit weg schien (Join.Pushed merkt nur die in der Nähe)
        Ask(m, questID)
        Join.openID[guid] = questID
        if not Join.silent[guid] then Join.open[guid] = now + Join.ANSWER end
        return
    end
    Join.open[guid] = nil
    if kind ~= "retry" and kind ~= "far" then Join.silent[guid] = nil end
    local states = Join.offered[guid]
    if kind == "unfit" then
        if states then states[questID] = "unfit" end
    elseif kind == "full" then
        if states then states[questID] = "unfit" end
        if new then new.full = true end
    elseif kind == "retry" or kind == "far" then
        -- er wurde nicht gefragt: noch einmal versuchen, aber nicht endlos (wer schon früher gefragt wurde, bleibt es)
        if kind == "far" and m.yards then Join.range = math.max(Join.RANGE_MIN, math.min(Join.range, m.yards / 2)) end
        if Share.lastEntry and Share.lastEntry.id == questID then Share.Later(Share.lastEntry) end
        if not Join.fresh[guid] then return end
        Join.fresh[guid] = nil
        -- die Versuche eines Neuen zählen nur für seine fehlenden Quests; alles andere reicht Share.Later nach
        local last = Share.lastEntry
        if not new or not (last and last.id == questID and last.join) then
            if states then states[questID] = nil end
            if new then new.left, new.retryAt = math.min(Join.PER_PLAYER, new.left + 1), now + Join.RETRY end
            return
        end
        new.tries[questID] = (new.tries[questID] or 0) + 1
        new.retryAt = now + Join.RETRY
        if states and states[questID] == "asked" then
            states[questID] = new.tries[questID] > Join.TRIES and "unfit" or nil
            new.left = math.min(Join.PER_PLAYER, new.left + 1)
        end
    end
end

---------------------------------------------------------------------------
-- Knopf am Kopf „Quests“ von Blizzards Verfolgung (links vom Sortier-Pfeil)
---------------------------------------------------------------------------

local button

function Join.Button() return button end

-- Namen der Neuen, denen gerade etwas fehlt („Anna, Bert“).
local function Names(who)
    local names = {}
    for _, m in ipairs(who) do
        local full = Core.UnitFullName(m.unit)
        names[#names + 1] = full and Core.ShortName(full) or "?"
    end
    return table.concat(names, ", ")
end

local function ShowTip(self)
    local list, who = Join.List(true)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    Core.TipTitle(GameTooltip, L.JOIN_BUTTON:format(#list))
    if #who > 0 then GameTooltip:AddLine(L.JOIN_BUTTON_WHO:format(Names(who)), nil, nil, nil, true) end
    for i = 1, math.min(#list, Join.TIP_QUESTS) do
        Core.TipLine(GameTooltip, Core.QuestTitle(list[i]) or tostring(list[i]), "normal")
    end
    if #list > Join.TIP_QUESTS then Core.TipLine(GameTooltip, Core.More(#list - Join.TIP_QUESTS), "normal") end
    GameTooltip:AddLine(L.JOIN_BUTTON_NOTE, nil, nil, nil, true)
    Core.TipClick(GameTooltip, L.JOIN_BUTTON_CLICK:format(Share.GAP))
    Core.TipClick(GameTooltip, L.JOIN_BUTTON_HIDE)
    GameTooltip:Show()
end

-- Erst gebaut, wenn zum ersten Mal jemand neu ist, dem Quests fehlen. nil, solange Blizzards Verfolgung fehlt.
function Join.CreateButton()
    if button then return button end
    local module = rawget(_G, "QuestObjectiveTracker")
    local header = type(module) == "table" and module.Header
    if type(header) ~= "table" or not header.CreateTexture then return nil end
    button = CreateFrame("Button", nil, header)
    local size = Core.Style.BUTTON.small
    button:SetSize(size, size)
    local arrow = ns.Tracker and ns.Tracker.Button() or header.MinimizeButton
    if arrow then
        button:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
    else
        button:SetPoint("RIGHT", header, "RIGHT", -44, 0)
    end
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    -- Blizzards Symbol für gemeinsame Quests (Atlas im Build 1.60.1.71037)
    Core.SetIcon(button.icon, "QuestSharing-DialogIcon", "Interface\\GossipFrame\\AvailableQuestIcon")
    button.Count = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.Count:SetPoint("RIGHT", button, "LEFT", -2, 0)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, mouse)
        GameTooltip:Hide()
        if mouse == "RightButton" then
            Join.dismissed = true
            Join.UpdateButton()
        else
            ns.Try("ShareJoin", Join.Click)
        end
    end)
    button:SetScript("OnEnter", ShowTip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    return button
end

-- Wartet noch eine Quest der Automatik in der Reihe? Dann zeigt der Knopf erst, was danach übrig bleibt.
local function AutoQueued()
    for _, entry in ipairs(Share.queue) do if entry.join then return true end end
    return false
end

-- Knopf zeigen oder verbergen und die Zahl nachziehen. → Anzahl fehlender Quests (0: verborgen)
function Join.UpdateButton()
    local count = 0
    if ns.Enabled("joinButton") and next(Join.new) and not Join.dismissed and not AutoQueued() then
        count = #Join.List(true)
    end
    if count > 0 then Join.CreateButton() end
    if not button then return count end
    button.Count:SetText(tostring(count))
    local shown = button:IsShown()
    button:SetShown(count > 0)
    if count > 0 and not shown and not ns.Enabled("joinShare") and Core.OptInHint and Core.OptInHint.ShowSoon then
        ns.AfterCombat(function() Core.OptInHint.ShowSoon("tracker") end, "joinHint")
    end
    if count == 0 and shown and GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    return count
end

---------------------------------------------------------------------------
-- Status und Hinweis
---------------------------------------------------------------------------

-- Was Blizzard zuletzt auf ein Teilen geantwortet hat (für /ezq status).
function Join.AnswerLine()
    if Join.heard then return L.STATUS_SHARE_HEARD:format(Join.heard) end
    return L.STATUS_SHARE_DEAF
end

local WAIT_TEXT = { offline = "JOIN_WAIT_OFFLINE", dead = "JOIN_WAIT_DEAD", far = "JOIN_WAIT_FAR" }
-- Zeilen für /ezq status: wer neu ist und worauf ezQuest wartet; die gelernte Entfernung.
function Join.StatusLines()
    local lines = {}
    local members = (ns.Enabled("joinShare") or ns.Enabled("joinButton")) and Join.Allowed() and Snapshot() or {}
    for _, m in ipairs(members) do
        if m.new then
            local full = Core.UnitFullName(m.unit)
            local state
            if not m.near then
                state = L[WAIT_TEXT[m.why] or WAIT_TEXT.far]
            elseif m.new.full then
                state = L.JOIN_WAIT_FULL
            else
                local missing = 0
                m.ready = true      -- auch, wenn gerade die Pause nach „beschäftigt“ läuft
                for _, entry in ipairs(Core.QuestLogEntries() or {}) do
                    if Share.Pushable(entry.id) and Join.Targets(entry.id, true, { m }) then missing = missing + 1 end
                end
                state = L.JOIN_MISSING:format(missing)
            end
            lines[#lines + 1] = L.STATUS_JOIN:format(full and Core.ShortName(full) or "?", state)
        end
    end
    if Join.range < Join.RANGE then lines[#lines + 1] = L.STATUS_JOIN_RANGE:format(math.floor(Join.range + 0.5)) end
    return lines
end

-- Einmal je Account, sobald einem Neuen Quests fehlen und der Schalter aus ist; Pfeil auf den Knopf.
function Join.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezQuest.joinShare", {
        owner = ADDON,
        window = "tracker",
        label = function() return L.OPT_joinShare end,
        what = function() return L.OPTIN_joinShare end,
        where = function()
            return Core.SettingsPathText("ezQuest", "OPT_HEADER_SHARE", "OPT_joinShare", L) .. " " .. L.OPTIN_WHERE_autoShare
        end,
        isOn = function() return ns.Enabled("joinShare") end,
        enable = function()
            ns.SetSetting("joinShare", true)
            return ns.Enabled("joinShare")
        end,
        applies = function()
            local tour = ns.Tracker and ns.Tracker.TourShowing
            return next(Join.new) ~= nil and not (tour and tour()) and #Join.List(true) > 0
        end,
        target = Join.Button,
        side = "left",
    })
end
Join.RegisterOptInHint()

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------

-- Teilt der Spieler selbst über Blizzards Knopf, gilt die Quest für alle in der Nähe als angeboten (Beobachten über
-- hooksecurefunc; ezQuests eigenes Teilen meldet Share.lua).
function Join.OnBlizzardPush(index)
    if Share.pushing then return end
    local log = C_QuestLog
    local questID = Num(Call(log.GetQuestIDForLogIndex, index)) or Num(Call(log.GetSelectedQuest))
    if questID and questID > 0 then Join.Pushed(questID) end
end

ns.OnReady(function()
    Join.Base()
    Join.Roster()
    -- nur Einloggen und /reload sind eine Bestandsaufnahme; ein Zonenwechsel lässt die Gruppe, wie sie ist
    ns.On("PLAYER_ENTERING_WORLD", function(_, initial, reload)
        if Core.Bool(initial, false) == true or Core.Bool(reload, false) == true then Join.Base() end
        Join.Roster()
    end)
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "GROUP_JOINED", "GROUP_LEFT" }) do
        ns.On(event, function() Join.Roster() end)
    end
    ns.On("CHAT_MSG_SYSTEM", function(_, text) Join.OnText(text) end)
    ns.On("UI_INFO_MESSAGE", function(_, _, text) Join.OnText(text) end)
    ns.On("UI_ERROR_MESSAGE", function(_, _, text) Join.OnText(text) end)
    if type(rawget(_G, "QuestLogPushQuest")) == "function" and type(hooksecurefunc) == "function" then
        pcall(hooksecurefunc, "QuestLogPushQuest", function(index) ns.Try("ShareJoin", Join.OnBlizzardPush, index) end)
    end
end)

ns.OnSettingChanged(function(key)
    if key == "joinShare" or key == "joinButton" or key == "joinShareWhich" then ns.Try("ShareJoin", Join.Check) end
end)
