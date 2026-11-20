local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Quest-Fortschritt im Tooltip (Befund des Nutzers vom 15.11.2026: „im tootltip bzw das tooltip von questobjekten wird
    mir nicht angezeigt 5 von 7 oder sowas“). Eine Zeile „<Quest>: <Ziel> 5/7 (laut Quest-Log)“ in Blizzards Tooltip:
      Spielobjekte  ezCores Abschnitt für Spielobjekte (Core.Tooltip.AddObjectSection, Platz „quest“; Welle 23,
                    A5 – vorher ein eigener Eintrag bei TooltipDataProcessor). Forevers Tooltip eines Objekts trägt nur
                    den Namen (Daten-Probe F8: { dataInstanceID, type = 4 }, eine Zeile) – Name und Objekt-ID liefert
                    ezCore (Core.Tooltip.ObjectName; Core.Tooltip.ObjectID: GUID von „softinteract“ bei gleichem
                    Namen, sonst ezCores Namensliste der gesehenen Objekte).
      Gegner/NPCs   ezCores Abschnitt für Einheiten (Core.Tooltip.AddUnitSection), nie bei Spielern
      Gegenstände   Items.lua (Zeile „Quest: … (3/10)“), über Progress.Add
    Zuordnung Objekt bzw. Gegner » Quest-Ziel, der Reihe nach:
      1. Name im Ziel: „Dämmerkrautblüte: 5/7“ enthält das Objekt „Dämmerkrautblüte“ (bei Gegnern nur Ziele, die keine
         Gegenstände sind – „Wolf“ ist nicht „Wolfsfleisch“)
      2. Entdecker-Datenbank: obj.quest (Quest-Objekt, questID vom Client beim Plündern) und die Beute des Objekts bzw.
         Gegners (Core.Drops.Of) » Quest-Ziel mit diesem Gegenstand
    Fortschritt und Titel liest Items.lua aus dem Quest-Log (C_QuestLog, nur lesen). Rücksicht (Leitlinie 9): Steht
    dieselbe Angabe schon im Tooltip (Blizzard oder ein anderes Addon wie Questie), schweigt ezQuest – verglichen wird
    der Text; die bloße Anwesenheit von Questie reicht nicht. Weil Questie seine Zeilen auch nach ezQuest schreiben kann,
    prüft ezQuest bei eingeschalteten Questie-Tooltips einen Augenblick später (nächstes Bild) und schreibt dann
    (ezCores Tooltip.Later; im Einheiten-Tooltip setzt ezCore die Abschnitte dann ohnehin ans Ende).
    Abstand und Doppeltes (S-1811-Tooltipabstand, Gesamtreview 18.11.2026; Spielbefund „hier fehlt abstand zwischen den
    quests sowie zum loot reiter“): vor der ersten Zeile und zwischen Zeilen verschiedener Quests ezCores Trenner
    (Core.Tooltip.Gap, Gruppe je Quest); Zeilen derselben Quest stehen zusammen. Questie zeigt den Fortschritt in
    Blöcken – Kopfzeile „[15] <Quest>“, darunter Ziel und Gruppenmitglieder in eigenen Zeilen („Name: 3/20“). Steht
    unter einer Zeile mit dem Quest-Titel (bis zur nächsten Zeile mit einem anderen Titel aus dem Log) dieselbe Zahl
    bzw. dasselbe Ziel, gilt die Angabe als gezeigt und ezQuest schweigt (Progress.ShownInBlock).
]]

local Progress = {}
ns.Progress = Progress

local Plain, Num = Core.Plain, Core.Num

---------------------------------------------------------------------------
-- Was schon im Tooltip steht
---------------------------------------------------------------------------

-- Text ohne Farbcodes, klein geschrieben; nil für gesperrte oder leere Texte.
function Progress.Clean(text)
    text = Plain(text)
    if type(text) ~= "string" or text == "" then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return text:lower()
end

-- Linke Zeilen des Tooltips (bereinigt), so wie sie gerade stehen – auch die, die andere Addons angehängt haben.
function Progress.Lines(tooltip)
    local list = {}
    if type(tooltip) ~= "table" then return list end
    local name = tooltip.GetName and Plain(tooltip:GetName())
    local n = tooltip.NumLines and Num(tooltip:NumLines()) or 0
    for i = 1, n do
        local fs = type(name) == "string" and rawget(_G, name .. "TextLeft" .. i) or nil
        local text = type(fs) == "table" and fs.GetText and Progress.Clean(fs:GetText()) or nil
        if text then list[#list + 1] = text end
    end
    return list
end

-- Steht piece in line? Beginnt oder endet piece mit einer Ziffer, zählt es nur als ganze Zahl: „3/20“ steht nicht in
-- „13/20“ oder „3/200“ (S-1811-Tooltipabstand: Zeilen von Gruppenmitgliedern tragen andere Zahlen).
function Progress.Has(line, piece)
    if type(line) ~= "string" or type(piece) ~= "string" or piece == "" then return false end
    local digitStart, digitEnd = piece:find("^%d") ~= nil, piece:find("%d$") ~= nil
    local start = 1
    while true do
        local s, e = line:find(piece, start, true)
        if not s then return false end
        local before, after = line:sub(s - 1, s - 1), line:sub(e + 1, e + 1)
        if not (digitStart and before:find("^%d")) and not (digitEnd and after:find("^%d")) then return true end
        start = s + 1
    end
end
local Has = Progress.Has

-- Steht a (und b, wenn angegeben) in einer Zeile? Groß und klein gelten gleich.
function Progress.Shown(lines, a, b)
    a = type(a) == "string" and a ~= "" and a:lower() or nil
    b = type(b) == "string" and b ~= "" and b:lower() or nil
    if not a then return false end
    for _, line in ipairs(lines) do
        if Has(line, a) and (not b or Has(line, b)) then return true end
    end
    return false
end

-- Kopfzeile eines Quest-Blocks, den ein anderes Addon in den Tooltip schreibt (Zeilen aus Progress.Lines, zur Laufzeit
-- gelesen): „[15] <Quest>“ (Stufe in eckigen Klammern, auch „[15+]“ o. Ä.). Gegenprüfung: Blöcke für Quests, die nur ein Mitspieler hat, stehen nicht im eigenen Log – die
-- Kopfzeile beendet den Block trotzdem (beobachtet im Spielbefund vom 18.11.2026).
function Progress.BlockHead(line)
    return type(line) == "string" and line:find("^%s*%[%d+[^%]]*%]") ~= nil
end

-- Steht im Block einer Quest (Zeile mit dem Titel, dann die Zeilen bis zur nächsten mit einem anderen Titel aus
-- others oder bis zur nächsten Kopfzeile, Progress.BlockHead) eine Zeile mit piece? piece nil: der Titel allein reicht
-- (ganze Quest). Groß und klein gelten gleich.
function Progress.ShownInBlock(lines, title, piece, others)
    title = type(title) == "string" and title ~= "" and title:lower() or nil
    if not title then return false end
    piece = type(piece) == "string" and piece ~= "" and piece:lower() or nil
    others = type(others) == "table" and others or {}
    for i, line in ipairs(lines) do
        if Has(line, title) then
            if not piece then return true end
            for j = i + 1, #lines do
                local below, other = lines[j], Progress.BlockHead(lines[j])
                for _, t in ipairs(others) do
                    if t ~= title and not title:find(t, 1, true) and Has(below, t) then
                        other = true
                        break
                    end
                end
                if other then break end
                if Has(below, piece) then return true end
            end
        end
    end
    return false
end

local function AlreadyThere(lines, entry, titles)
    if Progress.Shown(lines, entry.a, entry.b) then return true end
    local alt = entry.alt
    if type(alt) == "table" and alt[1] ~= nil and Progress.Shown(lines, alt[1], alt[2]) then return true end
    -- Block eines anderen Addons (Questie): Titel, darunter dieselbe Zahl, bei Zielen ohne Zahl dasselbe Ziel
    if not entry.quest then return false end
    -- ganze Quest: offen reicht der Titel; abgeschlossen nur mit dem Fertig-Wort im Block (Gegenprüfung)
    if entry.wholeQuest then return Progress.ShownInBlock(lines, entry.quest, entry.done and entry.b or nil, titles) end
    if Progress.ShownInBlock(lines, entry.quest, entry.count or entry.a, titles) then return true end
    return type(alt) == "table" and alt[2] ~= nil and Progress.ShownInBlock(lines, entry.quest, alt[2], titles)
end

-- Titel aller Quests im Log, klein geschrieben (Grenzen der Blöcke für ShownInBlock).
local function LogTitles()
    local list = {}
    for _, q in ipairs(ns.Items and ns.Items.Quests() or {}) do
        if type(q.title) == "string" and q.title ~= "" then list[#list + 1] = q.title:lower() end
    end
    return list
end

-- ezCores Trenner (Core.Tooltip.Gap); Gruppe je Quest: Zeilen derselben Quest ohne Leerzeile dazwischen.
local function Gap(tooltip, entry)
    local T = Core.Tooltip
    if type(T) ~= "table" or type(T.Gap) ~= "function" then return end
    T.Gap(tooltip, "ezQuest.quest:" .. tostring(entry.questID or entry.quest or ""))
end

local function FirstLine(tooltip)
    local name = tooltip.GetName and Plain(tooltip:GetName())
    local fs = type(name) == "string" and rawget(_G, name .. "TextLeft1") or nil
    return type(fs) == "table" and fs.GetText and Plain(fs:GetText()) or nil
end

local function Write(tooltip, entries)
    local lines, added = Progress.Lines(tooltip), 0
    local titles = LogTitles()
    for _, entry in ipairs(entries) do
        if not AlreadyThere(lines, entry, titles) then
            Gap(tooltip, entry)
            if entry.done then Core.TipLine(tooltip, entry.text, "gray") else Core.TipLine(tooltip, entry.text, "normal") end
            added = added + 1
        end
    end
    return added
end

--[[
    entries = { { text, done, a, b, alt = { a, b }, quest, questID, count, wholeQuest } … }: text ist die Zeile, a/b
    (und alt) die Stücke, an denen eine schon vorhandene Zeile mit derselben Angabe zu erkennen ist; quest (Titel),
    count („3/20“) bzw. wholeQuest die Stücke für den Block eines anderen Addons. → Zahl der sofort geschriebenen
    Zeilen. Mit Questies Tooltips (ezCore.WhoHandles „questItemTooltip“) wird erst im nächsten Bild geprüft und
    geschrieben, solange noch derselbe Tooltip steht (ezCores Tooltip.Later; schon in ezCores spätem Durchlauf: sofort).
]]
function Progress.Add(tooltip, entries)
    if type(tooltip) ~= "table" or type(entries) ~= "table" or #entries == 0 then return 0 end
    local defer = ns.OtherHandles("questItemTooltip") ~= nil
    local T = Core.Tooltip
    if type(T) == "table" and type(T.Later) == "function" then
        local n, now = T.Later(tooltip, function(tip) return Write(tip, entries) end, defer)
        return now and (n or 0) or 0
    end
    if not defer then return Write(tooltip, entries) end
    local first = FirstLine(tooltip)
    C_Timer.After(0, function()
        if not (tooltip.IsShown and tooltip:IsShown()) or FirstLine(tooltip) ~= first then return end
        if Write(tooltip, entries) > 0 and tooltip.Show then tooltip:Show() end
    end)
    return 0
end

---------------------------------------------------------------------------
-- Ziele finden
---------------------------------------------------------------------------

Progress.MIN_NAME = 3   -- kürzere Namen passen in zu viele Zieltexte

--[[
    Ziele zu einem Namen: name (Objekt oder Gegner), items = { [Name klein] = true } (Beute), quests = { [questID] =
    true } (Quest-Objekt laut Datenbank), opts.noItemByName = true (bei Gegnern: Name nicht in Gegenstands-Zielen
    suchen). → { { quest, objective (nil = die ganze Quest), via = "name" | "loot" } … } in der Reihenfolge des Logs
]]
function Progress.Find(name, items, quests, opts)
    local found = {}
    local key = type(name) == "string" and #name >= Progress.MIN_NAME and name:lower() or nil
    items = type(items) == "table" and items or {}
    quests = type(quests) == "table" and quests or {}
    opts = type(opts) == "table" and opts or {}
    for _, q in ipairs(ns.Items and ns.Items.Quests() or {}) do
        local any = false
        for _, o in ipairs(q.objectives or {}) do
            local lower = o.name:lower()
            local byName = key ~= nil and lower:find(key, 1, true) ~= nil
                and not (opts.noItemByName and o.kind == "item")
            local byLoot = o.kind == "item" and items[lower] == true
            if byName or byLoot then
                found[#found + 1] = { quest = q, objective = o, via = byName and "name" or "loot" }
                any = true
            end
        end
        if not any and quests[q.questID] then
            found[#found + 1] = { quest = q, via = "loot" }
        end
    end
    return found
end

-- Zeile zu einem Fund. → Eintrag für Progress.Add oder nil (die Quest hat schon eine Zeile „fertig“, seen merkt sie)
function Progress.Entry(hit, seen)
    local q, o = hit.quest, hit.objective
    local source = hit.via == "loot" and L.PROGRESS_SOURCE_LOOT or L.PROGRESS_SOURCE
    if q.complete or not o then
        if seen then
            if seen[q.questID] then return nil end
            seen[q.questID] = true
        end
        if q.complete then
            return { text = L.PROGRESS_QUEST_DONE:format(q.title) .. " " .. source, done = true, a = q.title,
                b = L.PROGRESS_DONE_WORD, quest = q.title, questID = q.questID, wholeQuest = true }
        end
        return { text = L.PROGRESS_QUEST:format(q.title) .. " " .. source, done = false, a = q.title,
            quest = q.title, questID = q.questID, wholeQuest = true }
    end
    if o.done then
        return { text = L.PROGRESS_DONE:format(q.title, o.name) .. " " .. source, done = true, a = o.name,
            b = L.PROGRESS_DONE_WORD, alt = o.need and o.need > 0 and { o.name, o.need .. "/" .. o.need } or nil,
            quest = q.title, questID = q.questID }
    end
    if o.have and o.need and o.need > 0 then
        local count = o.have .. "/" .. o.need
        return { text = L.PROGRESS_LINE:format(q.title, o.name, count) .. " " .. source, done = false,
            a = o.name, b = count, quest = q.title, questID = q.questID, count = count }
    end
    return { text = L.PROGRESS_PLAIN:format(q.title, o.name) .. " " .. source, done = false, a = o.name, b = q.title,
        quest = q.title, questID = q.questID }
end

function Progress.Entries(found)
    local list, seen = {}, {}
    for _, hit in ipairs(found) do
        local entry = Progress.Entry(hit, seen)
        if entry then list[#list + 1] = entry end
    end
    return list
end

---------------------------------------------------------------------------
-- Entdecker-Datenbank (nur lesen, alles geschützt)
---------------------------------------------------------------------------

-- Weiterleitungen auf ezCore (Welle 23, A5; die Fassungen standen bis dahin hier): Beute als Namen
-- (Core.Discovery.LootNames), Objekt-ID aus der GUID (Core.ObjectID) und zum Namen im Tooltip (Core.Tooltip.ObjectID).

-- Namen der Gegenstände, die bei dir aus dieser Quelle kamen (Core.Drops.Of(art, id)) → { [Name klein] = true }
function Progress.LootNames(kind, id)
    local discovery = Core.Discovery
    if not (id and type(discovery) == "table" and type(discovery.LootNames) == "function") then return {} end
    local names = Core.Call(discovery.LootNames, kind, id)
    return type(names) == "table" and names or {}
end

-- Objekt-ID aus einer GUID („GameObject-0-…-<id>-…“) oder nil.
function Progress.ObjectIDFromGUID(guid)
    return Core.ObjectID(guid)
end

-- Objekt-ID zum Namen im Tooltip: das Objekt, auf das die Interaktion zielt (gleicher Name), sonst ezCores Namensliste.
function Progress.ObjectID(name)
    return Core.Tooltip.ObjectID(name)
end

-- Quests, die das Objekt laut Datenbank braucht (obj.quest) → { [questID] = true }
function Progress.ObjectQuests(id)
    local set = {}
    local db = Core.DB
    if not (id and type(db) == "table" and type(db.Get) == "function") then return set end
    local row = Core.Call(db.Get, "obj", id)
    local questID = type(row) == "table" and Num(row.quest) or nil
    if questID then set[questID] = true end
    return set
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

local function Usable(tooltip)
    if tooltip ~= GameTooltip then return false end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
    return ns.Enabled("progressTip")
end

-- Spielobjekt (Kraut, Erzader, Quest-Objekt) mit Name und Objekt-ID – so ruft ezCores Abschnitt für Spielobjekte.
-- → Zahl der Zeilen (sofort geschrieben)
function Progress.ForObject(tooltip, name, id)
    if not Usable(tooltip) or Core.IsSecret(name) or type(name) ~= "string" or name == "" then return 0 end
    id = Num(id)
    local found = Progress.Find(name, Progress.LootNames("object", id), Progress.ObjectQuests(id))
    return Progress.Add(tooltip, Progress.Entries(found))
end

-- Dasselbe aus den Tooltip-Daten (Name und Objekt-ID wie in ezCores Abschnitt). → Zahl der Zeilen
function Progress.OnObject(tooltip, data)
    if not Usable(tooltip) then return 0 end
    local name = Core.Tooltip.ObjectName(tooltip, data)
    if not name then return 0 end
    return Progress.ForObject(tooltip, name, Progress.ObjectID(name))
end

-- Gegner oder NPC (Abschnitt in ezCores Tooltip für Einheiten). Spieler bekommen keine Zeile.
function Progress.OnUnit(tooltip, unit, data)
    if not Usable(tooltip) then return 0 end
    if Plain(Core.Call(rawget(_G, "UnitIsPlayer"), unit)) == true then return 0 end
    local name = Plain(Core.Call(rawget(_G, "UnitName"), unit))
    if type(name) ~= "string" or name == "" then return 0 end
    local guid = type(data) == "table" and Plain(data.guid) or nil
    if type(guid) ~= "string" then guid = Plain(Core.Call(rawget(_G, "UnitGUID"), unit)) end
    local npcID = Core.NpcID(guid)
    local found = Progress.Find(name, Progress.LootNames("loot", npcID), nil, { noItemByName = true })
    return Progress.Add(tooltip, Progress.Entries(found))
end

ns.OnReady(function()
    -- Spielobjekte: ezCore ruft fn(tooltip, name, data, objectID) nur für GameTooltip, Fehler ins Fehler-Log
    Core.Tooltip.AddObjectSection("ezQuest.progress", "quest", function(tooltip, name, _, id)
        return Progress.ForObject(tooltip, name, id)
    end, ADDON)
    if Core.Tooltip and Core.Tooltip.AddUnitSection then
        Core.Tooltip.AddUnitSection("ezQuest.progress", 55, Progress.OnUnit, ADDON)
    end
end)
