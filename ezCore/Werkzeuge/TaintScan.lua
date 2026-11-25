local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Taint-Suche – Knopf „Taint-Suche“ auf der Seite „ezCollection“ → „Erweitert“ (Leitlinie 3) und /ez debug taint
    (Core.TaintScan). Anlass: Spielbefund vom 22.11.2026 – Blizzards Gruppenrahmen (CompactUnitFrame.lua, Vergleich
    mit einem gesperrten Wert) und Blizzards Einstellungen (C_Discord.IsUserOAuthed auf der Seite „Soziales“) liefen
    „tainted by ezCore“, ohne dass im Code eine Stelle zu sehen war, die in Blizzards Tabellen schreibt
    (docs/blizzard-regeln.md, Abschnitt 8).

    Blizzards issecurevariable([tabelle,] schlüssel) nennt für jeden Wert, ob er sicher ist und welches Addon ihn
    verunreinigt hat; Lesen damit verunreinigt nichts. Geprüft wird:
      - jeder globale Name, außer den eigenen (TaintScan.OwnName: Präfix „ez“, Slash-Befehle und Tastenbelegungen),
      - jedes Feld jeder globalen Tabelle und jedes globalen Rahmens von Blizzard, eine Ebene tief (ist der globale
        Name selbst verunreinigt, gehört die Tabelle einem Addon – ihre Felder werden nicht einzeln geprüft),
      - dazu Teile ohne globalen Namen (TaintScan.EXTRA): Klassenfarben, Kontoeinstellungen des Bearbeitungsmodus,
        Kategorienliste und Zeilen von Blizzards Einstellungen, Knöpfe des Spielmenüs, Lebensbalken der Gruppenrahmen,
        Lage-Daten der Aktionsleisten (TaintScan.BARS: systemInfo, anchorInfo, snappedFrames, settingMap), aktives
        Layout des Bearbeitungsmodus samt Systemen, Wartelisten von SpellEventListener, ItemEventListener und
        QuestEventListener (Spielbefund vom 23.11.2026: MainActionBar:SetPointBase im Kampf blockiert).
        Dafür ruft die Suche Blizzards Getter GetCategoryList, GetSettingsList, GetFrames/ForEachFrame und
        EnumerateActive auf (sie lesen nur Felder bzw. gehen über eine Liste; geschützt mit pcall).
    Die Suche läuft in Häppchen (TaintScan.BUDGET_MS je Frame) und ändert nichts; am Ende zeigt ein Fenster den Bericht
    zum Kopieren (deutsch, wie alle Diagnose-Berichte, Leitlinie 7). Einzeln stehen nur Funde der ezCollection;
    Einträge in Blizzards Sammellisten für Addons (TaintScan.ALLOWED, Leitlinie 5) und Funde anderer Addons zählt der
    Bericht nur. Eine einzelne Tabelle wird in einem Stück geprüft (next über mehrere Frames ist bei sich ändernden
    Tabellen unzulässig); das Zeitbudget gilt zwischen zwei Tabellen.
      TaintScan.Run()        Knopf und Befehl: starten, melden, danach den Bericht zeigen → true | false
      TaintScan.Start(done)  → true | false, "running" | "api"; done(ergebnis) nach dem letzten Häppchen,
                             done(nil, fehler), wenn ein Häppchen fehlschlägt (Fehler auch in der Fehlerliste)
      TaintScan.Running()    → läuft?
      TaintScan.Result()     → letztes Ergebnis { t, ms, checked, tables, own = { { path, by } … }, ownCount,
                               allowed, others = { [addon] = anzahl } } oder nil
      TaintScan.Lines([ergebnis]), TaintScan.Text(), TaintScan.Show()
      TaintScan.Step(zustand, ms) – ein Häppchen (intern, für Tests) → true, wenn fertig
    Vorher/Nachher (Paket „Taint 3“, 23.11.2026): Jeder Lauf vergleicht seine Funde mit dem vorigen derselben Sitzung
    (Ergebnis: newFinds, goneFinds, prevT) – Suche, dann einen Weg im Spiel gehen, wieder suchen: „neu“ zeigt, was der Weg
    verunreinigt hat. Funde, die bei jedem Addon gleich entstehen (TaintScan.EXPECTED: Zeilen des Spiel-Tooltips, die
    Blizzard für AddLine eines Addons anlegt; Blizzards Merkliste der Chat-Befehle), zählt der Bericht nur (expected).
]]

local TS = {}
Core.TaintScan = TS

TS.BUDGET_MS = 6        -- Millisekunden je Frame; danach geht die Suche im nächsten Frame weiter
TS.MAX_LIST = 200       -- so viele Funde der ezCollection stehen höchstens einzeln im Bericht
-- Blizzards Sammellisten, in die Addons eintragen dürfen (Leitlinie 5): Einträge dort zählen nur
-- (hash_SlashCmdList füllt Blizzards Chat aus den SLASH_…-Namen der Addons)
TS.ALLOWED = { UISpecialFrames = true, StaticPopupDialogs = true, SlashCmdList = true, hash_SlashCmdList = true }
-- Muster für Pfade, die nur gezählt werden: der globale Name einer Tooltip-Zeile selbst (nicht ihre Felder), Einträge
-- in Blizzards Merkliste der Chat-Befehle (nicht die Liste selbst)
TS.EXPECTED = { "^GameTooltipTextLeft%d+$", "^GameTooltipTextRight%d+$", "^hash_ChatTypeInfoList[%.%[]" }

local running, last

-- Millisekunden für die Häppchen: debugprofilestop läuft innerhalb eines Frames weiter, GetTime (Core.Uptime) nicht
local function ClockMs()
    local profile = rawget(_G, "debugprofilestop")
    if type(profile) == "function" then return profile() end
    return Core.Uptime() * 1000
end

-- Stammt die Verunreinigung von einem Modul der ezCollection? (issecurevariable nennt den Namen des Addons.) Name „ez“
-- + Großbuchstabe; nennt die TOC eine Kategorie (## Category), muss sie „ezCollection“ sein (Addons anderer Autoren mit
-- ähnlichem Namen zählen dann nicht mit). Gemerkt je Name.
local ownCache = {}
function TS.IsOwn(by)
    if type(by) ~= "string" or not by:find("^ez%u") then return false end
    if ownCache[by] == nil then
        local meta = rawget(_G, "C_AddOns") and C_AddOns.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
        local ok, category = false, nil
        if type(meta) == "function" then ok, category = pcall(meta, by, "Category") end
        ownCache[by] = not (ok and type(category) == "string" and category ~= "" and category ~= "ezCollection")
    end
    return ownCache[by]
end

-- Eigener globaler Name: dort ist „verunreinigt“ der Normalfall, die Suche überspringt ihn samt seinen Feldern.
function TS.OwnName(name)
    if type(name) ~= "string" then return false end
    local low = name:lower()
    if low:sub(1, 2) == "ez" then return true end
    if (name:find("^SLASH_") or name:find("^BINDING_")) and low:find("ez", 1, true) then return true end
    return false
end

-- → sicher?, Addon. Was sich nicht prüfen lässt (verbotener Rahmen, Fehler), gilt als sicher und wird nicht gemeldet.
local function Secure(tbl, key)
    local check = rawget(_G, "issecurevariable")
    local ok, secure, by
    if tbl == nil then ok, secure, by = pcall(check, key) else ok, secure, by = pcall(check, tbl, key) end
    if not ok then return true end
    return secure ~= false, by
end

local function KeyText(key)
    if type(key) == "number" then return "[" .. key .. "]" end
    if key:find("^[%a_][%w_]*$") then return "." .. key end
    return ("[%q]"):format(key)
end

local function Expected(path)
    for _, pattern in ipairs(TS.EXPECTED) do if path:find(pattern) then return true end end
    return false
end

local function Note(state, path, by, allowed)
    if TS.IsOwn(by) then
        if allowed then state.allowed = state.allowed + 1 return end
        if Expected(path) then state.expected = state.expected + 1 return end
        state.ownSet[path .. "\0" .. by] = { path = path, by = by }   -- ungekappt, für Vorher/Nachher
        state.ownCount = state.ownCount + 1
        if #state.own < TS.MAX_LIST then state.own[#state.own + 1] = { path = path, by = by } end
    else
        local who = type(by) == "string" and by ~= "" and by or "?"
        state.others[who] = (state.others[who] or 0) + 1
    end
end

-- Felder einer Tabelle (eine Ebene); label ist der Pfad im Bericht.
local function ScanFields(state, tbl, label)
    if type(tbl) ~= "table" or Core.IsSecret(tbl) then return end
    state.tables = state.tables + 1
    local allowed = TS.ALLOWED[label] == true
    pcall(function()
        for key in pairs(tbl) do
            local kind = type(key)
            if (kind == "string" or kind == "number") and not Core.IsSecret(key) then
                state.checked = state.checked + 1
                local secure, by = Secure(tbl, key)
                if not secure then Note(state, label .. KeyText(key), by, allowed) end
            end
        end
    end)
end

local function Get(tbl, key)
    if type(tbl) ~= "table" then return nil end
    local ok, value = pcall(function() return tbl[key] end)
    return ok and value or nil
end

local function Call(tbl, method, ...)
    local fn = Get(tbl, method)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, tbl, ...)
    return ok and value or nil
end

-- Leisten, die Blizzards Leistenaufbau ordnet (EditModeUtil.GetBottomActionBars im Zweig forever, Camelot) und die
-- rechten Leisten; fehlende Namen überspringt die Suche.
TS.BARS = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "MultiBar5",
    "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar", "MainStatusTrackingBarContainer",
    "SecondaryStatusTrackingBarContainer", "MicroMenuContainer", "MicroMenu", "BagsBar", "MultiCastActionBarFrame",
    "MainMenuBarVehicleLeaveButton" }

-- Prüfung „Leisten und Bearbeitungsmodus verunreinigt?“ (Bericht, eigene Zeile): ein Fund der ezCollection an einem
-- dieser Teile kann Blizzards Neuaufbau der unteren Leisten im Kampf blockieren (Spielbefund vom 23.11.2026).
function TS.IsBarPath(path)
    if type(path) ~= "string" then return false end
    for _, prefix in ipairs({ "EditModeManagerFrame", "aktives Layout", "SpellEventListener", "OverrideActionBar" }) do
        if path:sub(1, #prefix) == prefix then return true end
    end
    for _, name in ipairs(TS.BARS) do
        local rest = path:sub(#name + 1, #name + 1)
        if path:sub(1, #name) == name and (rest == "" or rest == "." or rest == "[") then return true end
    end
    return (path:find("^ActionButton%d") or path:find("^PetActionButton%d") or path:find("^StanceButton%d")
        or path:find("^PossessButton%d") or path:find("^MultiBar%w+Button%d")
        or path:find("^Gamepad%w*ActionBar")) ~= nil   -- Gamepad-Leisten (Spielbefund vom 23.11.2026)
end

-- Teile ohne globalen Namen, an denen die Funde vom 22.11.2026 hingen. list() → { { pfad, tabelle } … }
TS.EXTRA = {
    { key = "classColors", list = function()
        local out, colors = {}, rawget(_G, "RAID_CLASS_COLORS")
        if type(colors) == "table" then
            for class, color in pairs(colors) do
                if type(class) == "string" and type(color) == "table" then out[#out + 1] = { "RAID_CLASS_COLORS." .. class, color } end
            end
        end
        return out
    end },
    { key = "editMode", list = function()
        return { { "EditModeManagerFrame.AccountSettings", Get(rawget(_G, "EditModeManagerFrame"), "AccountSettings") } }
    end },
    -- Spielbefund vom 23.11.2026 (Begleiterleiste verschwand im Kampf, Blizzard baute die unteren Leisten neu auf,
    -- MainActionBar:SetPointBase blockiert): was dieser Weg zwei Ebenen tief liest. GetActiveLayoutInfo liest nur Felder
    -- (overrideLayoutInfo bzw. layoutInfo.layouts[activeLayout]; Blizzard_EditMode/Shared/EditModeManager.lua, forever).
    { key = "actionBars", list = function()
        local manager = rawget(_G, "EditModeManagerFrame")
        local active = Call(manager, "GetActiveLayoutInfo")
        local out = { { "EditModeManagerFrame.layoutInfo", Get(manager, "layoutInfo") },
            { "EditModeManagerFrame.overrideLayoutInfo", Get(manager, "overrideLayoutInfo") },
            { "EditModeManagerFrame:GetActiveLayoutInfo()", active } }
        local systems = Get(active, "systems")
        if type(systems) == "table" then
            for i, info in ipairs(systems) do
                out[#out + 1] = { "aktives Layout, System " .. i, info }
                out[#out + 1] = { "aktives Layout, System " .. i .. ".anchorInfo", Get(info, "anchorInfo") }
            end
        end
        for _, name in ipairs(TS.BARS) do
            local bar = rawget(_G, name)
            local info = Get(bar, "systemInfo")
            out[#out + 1] = { name .. ".systemInfo", info }
            out[#out + 1] = { name .. ".systemInfo.anchorInfo", Get(info, "anchorInfo") }
            out[#out + 1] = { name .. ".snappedFrames", Get(bar, "snappedFrames") }
            out[#out + 1] = { name .. ".settingMap", Get(bar, "settingMap") }
        end
        for _, name in ipairs({ "SpellEventListener", "ItemEventListener", "QuestEventListener" }) do
            out[#out + 1] = { name .. ".callbacks", Get(rawget(_G, name), "callbacks") }
        end
        return out
    end },
    { key = "settings", list = function()
        local panel = rawget(_G, "SettingsPanel")
        local out = { { "SettingsPanel:GetCategoryList()", Call(panel, "GetCategoryList") } }
        local box = Get(Call(panel, "GetSettingsList"), "ScrollBox")
        local frames = Call(box, "GetFrames")
        if type(frames) ~= "table" then
            frames = {}
            Call(box, "ForEachFrame", function(frame) frames[#frames + 1] = frame end)
        end
        for i, frame in ipairs(frames) do out[#out + 1] = { "SettingsPanel-Zeile " .. i, frame } end
        return out
    end },
    { key = "gameMenu", list = function()
        local out, pool = {}, Get(rawget(_G, "GameMenuFrame"), "buttonPool")
        local enumerate = Get(pool, "EnumerateActive")
        if type(enumerate) == "function" then
            local ok, iter, state, start = pcall(enumerate, pool)
            if ok and type(iter) == "function" then
                for button in iter, state, start do out[#out + 1] = { "GameMenuFrame-Knopf " .. (#out + 1), button } end
            end
        end
        return out
    end },
    { key = "groupFrames", list = function()
        local out = {}
        local function Bar(name)
            local bar = Get(rawget(_G, name), "healthBar")
            if bar then out[#out + 1] = { name .. ".healthBar", bar } end
        end
        for i = 1, 5 do Bar("CompactPartyFrameMember" .. i) end
        for i = 1, 40 do Bar("CompactRaidFrame" .. i) end
        for group = 1, 8 do
            for member = 1, 5 do Bar("CompactRaidGroup" .. group .. "Member" .. member) end
        end
        return out
    end },
}

local function GlobalNames()
    local names = {}
    for name in pairs(_G) do
        if type(name) == "string" then names[#names + 1] = name end
    end
    return names
end

function TS.Step(state, budget)
    local stop = ClockMs() + (budget or TS.BUDGET_MS)
    while state.i <= #state.names do
        local name = state.names[state.i]
        state.i = state.i + 1
        if name ~= "_G" and not TS.OwnName(name) then
            state.checked = state.checked + 1
            local secure, by = Secure(nil, name)
            if not secure then
                Note(state, name, by, false)
            else
                local value = rawget(_G, name)
                if type(value) == "table" then ScanFields(state, value, name) end
            end
        end
        if ClockMs() >= stop then return false end
    end
    while state.x <= #TS.EXTRA do
        local extra = TS.EXTRA[state.x]
        state.x = state.x + 1
        local ok, list = pcall(extra.list)
        if ok and type(list) == "table" then
            for _, entry in ipairs(list) do ScanFields(state, entry[2], entry[1]) end
        end
        if ClockMs() >= stop then return false end
    end
    return true
end

function TS.Running() return running ~= nil end
function TS.Result() return last end

function TS.Start(done)
    if running then return false, "running" end
    if type(rawget(_G, "issecurevariable")) ~= "function" then return false, "api" end
    local state = { names = GlobalNames(), i = 1, x = 1, checked = 0, tables = 0, own = {}, ownCount = 0, allowed = 0,
        expected = 0, ownSet = {}, others = {}, t = Core.Now(), began = ClockMs() }
    running = state
    local function Tick()
        if running ~= state then return end
        local ok, finished = pcall(TS.Step, state)
        if not ok then
            running = nil
            Core.Error(ADDON, finished, "TaintScan")
            if type(done) == "function" then Core.Try(ADDON, "TaintScan done", done, nil, finished) end
            return
        end
        if not finished then C_Timer.After(0, Tick) return end
        running = nil
        state.ms = ClockMs() - state.began
        state.names = nil
        table.sort(state.own, function(a, b) return a.path < b.path end)
        state.barFinds = {}
        for _, f in pairs(state.ownSet) do if TS.IsBarPath(f.path) then state.barFinds[#state.barFinds + 1] = f end end
        table.sort(state.barFinds, function(a, b) return a.path < b.path end)
        if last and last.ownSet then   -- Vorher/Nachher: alle Funde (Pfad und Modul) gegenüber dem vorigen Lauf
            state.newFinds, state.goneFinds, state.prevT = {}, {}, last.t
            for key, f in pairs(state.ownSet) do if not last.ownSet[key] then state.newFinds[#state.newFinds + 1] = f end end
            for key, f in pairs(last.ownSet) do if not state.ownSet[key] then state.goneFinds[#state.goneFinds + 1] = f end end
            local function ByPath(a, b) if a.path ~= b.path then return a.path < b.path end return a.by < b.by end
            table.sort(state.newFinds, ByPath)
            table.sort(state.goneFinds, ByPath)
        end
        last = state
        if type(done) == "function" then Core.Try(ADDON, "TaintScan done", done, state) end
    end
    C_Timer.After(0, Tick)
    return true
end

function TS.Run()
    local ok, why = TS.Start(function(result)
        if not result then ns.Print(L.TAINT_FAILED) return end
        ns.Print(L.TAINT_DONE:format(result.ownCount))
        TS.Show()
    end)
    if ok then ns.Print(L.TAINT_STARTED)
    elseif why == "running" then ns.Print(L.TAINT_RUNNING)
    else ns.Print(L.TAINT_NO_API) end
    return ok
end

function TS.Lines(result)
    result = result or last
    if not result then return { "Taint-Suche: noch kein Lauf (/ez debug taint oder Knopf „Taint-Suche“)." } end
    local lines = {
        ("ezCollection – Taint-Suche vom %s"):format(date("%d.%m.%Y %H:%M", result.t)),
        ("Geprüft: %d Werte in %d Tabellen, Dauer %s."):format(result.checked, result.tables, Core.Seconds((result.ms or 0) / 1000, 1)),
    }
    -- Prüfung „Leisten und Bearbeitungsmodus“ zuerst: vor dem nächsten Kampf sichtbar, ob es wieder droht
    local bars = result.barFinds or {}
    if #bars == 0 then
        lines[#lines + 1] = "Aktionsleisten und Bearbeitungsmodus: sauber."
    else
        lines[#lines + 1] = ("Aktionsleisten und Bearbeitungsmodus: %d Funde – Blizzards Neuaufbau der Leisten kann im Kampf"
            .. " blockiert werden; vor dem nächsten Kampf /reload und diesen Bericht schicken."):format(#bars)
        for i, f in ipairs(bars) do
            if i > 10 then lines[#lines + 1] = ("  … und %d weitere"):format(#bars - 10) break end
            lines[#lines + 1] = ("  %s: %s"):format(f.by, f.path)
        end
    end
    lines[#lines + 1] = ("Von ezCollection verunreinigt: %d"):format(result.ownCount)
    for _, found in ipairs(result.own) do lines[#lines + 1] = ("  %s: %s"):format(found.by, found.path) end
    if result.ownCount > #result.own then lines[#lines + 1] = ("  … und %d weitere"):format(result.ownCount - #result.own) end
    if result.prevT then
        lines[#lines + 1] = ("Seit dem Lauf von %s: %d neu, %d weg"):format(date("%H:%M:%S", result.prevT), #result.newFinds, #result.goneFinds)
        for _, part in ipairs({ { "neu", result.newFinds }, { "weg", result.goneFinds } }) do
            local kind, list = part[1], part[2]
            for i, f in ipairs(list) do
                if i > TS.MAX_LIST then lines[#lines + 1] = ("  … und %d weitere (%s)"):format(#list - TS.MAX_LIST, kind) break end
                lines[#lines + 1] = ("  %s %s: %s"):format(kind, f.by, f.path)
            end
        end
    end
    lines[#lines + 1] = ("Bei jedem Addon gleich (Zeilen des Spiel-Tooltips, Merkliste der Chat-Befehle): %d"):format(result.expected or 0)
    lines[#lines + 1] = ("Einträge der ezCollection in Blizzards Sammellisten für Addons (UISpecialFrames, StaticPopupDialogs, SlashCmdList, hash_SlashCmdList; erlaubt): %d")
        :format(result.allowed)
    local others = {}
    for who, n in pairs(result.others) do others[#others + 1] = { who = who, n = n } end
    table.sort(others, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.who < b.who end)
    local parts = {}
    for _, o in ipairs(others) do parts[#parts + 1] = o.who .. " " .. o.n end
    lines[#lines + 1] = "Von anderen Addons verunreinigt: " .. (#parts > 0 and table.concat(parts, ", ") or "keine")
    lines[#lines + 1] = "Lesart: Ein Fund ist ein Wert in Blizzards Tabellen, den ein Modul geschrieben hat – oder Blizzards eigener Code,"
        .. " während er nach einem Aufruf aus einem Modul verunreinigt lief. „SettingsPanel-Zeile“: Blizzards Liste liest Factory"
        .. " und InitFrame aus den Zeilen-Objekten, die ein Addon für seine Seite anlegt – so bei jedem Addon mit Seiten in Blizzards"
        .. " Einstellungen; Blizzard überschreibt die Felder, sobald es die Zeile für eine eigene Seite neu aufbaut."
        .. " Liest Blizzards Code den Wert, läuft er ab dort „tainted by“ dieses Modul. Am aussagekräftigsten direkt nach dem Fehler im Spiel (etwa nach Esc »"
        .. " Bearbeitungsmodus oder nach dem Öffnen der Einstellungen)."
    return lines
end

function TS.Text() return table.concat(TS.Lines(), "\n") end

function TS.Show()
    return Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.TAINT_TITLE, hint = L.TAINT_HINT, text = TS.Text(),
        readOnly = true, select = true, maxLetters = 0, owner = ADDON })
end
