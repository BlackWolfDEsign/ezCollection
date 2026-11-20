local _, ns = ...
local L = ns.L
local Core = ezCore

-- Übernimmt Makros in Blizzards Makroverwaltung (CreateMacro/EditMacro).
-- Nur außerhalb des Kampfes, mit Prüfung der Plätze für allgemeine und Charakter-Makros.
-- Plätze, Suche nach Namen und Schreiben über ezCores gemeinsamen Dienst „Makro anlegen“ (Core.Macro, Welle 15;
-- Übergabe aus den Zusatzpaketen 14b – vorher eine eigene Fassung hier, dieselbe in ezHeal und ezBuff).
local Import = {}
ns.Import = Import

local Macro = Core.Macro
local function Limits() return Macro.Limits() end

-- Höchstlänge: 255 wie bei Blizzard, mit langen Makros (Long.lua) bis 1023.
function Import.MaxChars()
    if ns.Long and ns.Long.Available() then return ns.LONG_MAX_CHARS end
    return ns.MACRO_MAX_CHARS
end

function Import.Available()
    return Macro.Available()
end

-- Belegte und freie Plätze: allgemein, max allgemein, Charakter, max Charakter.
function Import.Counts()
    local numAccount, numChar = Macro.Counts()
    local maxAccount, maxChar = Limits()
    return numAccount, maxAccount, numChar, maxChar
end

function Import.DefaultPerChar(entry)
    local mode = ns.S.scopeMode
    if mode == "char" then return true end
    if mode == "account" then return false end
    -- Ein-Klick: der beste Gegenstand hängt an den Taschen des Charakters; „Aus deinen Fähigkeiten“: an seinem Zauberbuch
    return entry.category == "class" or entry.category == "race" or entry.category == "oneclick"
        or entry.category == "spells"
end

function Import.ScopeLabel(perChar)
    return perChar and L.SCOPE_char or L.SCOPE_account
end

-- Vorhandenes Makro gleichen Namens: Index und ob es ein Charakter-Makro ist.
function Import.Find(name)
    local index = Macro.Find(name)
    if not index then return nil end
    local maxAccount = Limits()
    return index, index > maxAccount
end

function Import.CleanName(name)
    name = Core.Trim((tostring(name or ""):gsub("[\r\n\"]", "")))   -- Core.Trim (T16-15)
    return ns.Truncate(name, ns.MACRO_NAME_MAX)
end

function Import.CleanBody(body)
    body = tostring(body or ""):gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("%s+$", "")
    return body
end

-- Befehle, die Lua-Code ausführen oder Client-Einstellungen ändern (Gesamtreview 18.11.2026, T6-1): welche das sind,
-- entscheidet ezCore (Core.RunsCode – /run, /script, /console, /dump, /tinspect und die Schreibweisen des Clients aus
-- SLASH_SCRIPT<n> usw.; P19: vorher eine eigene Liste ScriptCommandSet hier, dieselbe wie in ezCore).
-- Solche Befehle in einem Makrotext, in der Reihenfolge ihres ersten Auftretens, ohne Doppelte: { "/run", … }.
function Import.ScriptCommands(body)
    local found, seen = {}, {}
    if type(body) ~= "string" then return found end
    for line in body:gmatch("[^\r\n]+") do
        local cmd = line:match("^%s*(/[^%s%[]+)")
        cmd = cmd and cmd:lower()
        if cmd and not seen[cmd] and Core.RunsCode(cmd) then
            seen[cmd] = true
            found[#found + 1] = cmd
        end
    end
    return found
end

-- Meldung oben in der Bildschirmmitte über ezCore (Core.ErrorMessage: Blizzards AddExternalErrorMessage, sonst rot
-- über AddMessage; W-14) und im Chat.
local function Fail(message)
    Core.ErrorMessage(message)
    ns.Print(message)
    return false
end

-- pickup: true = nach dem Übernehmen (mit Hinweis), "drag" = der Spieler zieht gerade (ohne Hinweis).
local function PickUp(index, pickup)
    if not index or ns.InCombat() or type(PickupMacro) ~= "function" then return end
    ClearCursor()
    PickupMacro(index)
    if pickup ~= "drag" then ns.Print(L.MSG_PICKUP) end
end

local DONE_MESSAGES = { created = "MSG_CREATED", updated = "MSG_UPDATED", same = "MSG_UNCHANGED" }

-- Wer wissen muss, welches Makro ezMacro auf Klick des Spielers angelegt oder ersetzt hat (OneClick.lua: nur diese
-- hält es aktuell): fn(entry, index) nach jedem erfolgreichen Import.Apply, auch nach Rückfrage und beim Ziehen.
local appliedListeners = {}
function Import.OnApplied(fn)
    if type(fn) == "function" then appliedListeners[#appliedListeners + 1] = fn end
end

local function Done(index, perChar, name, state, pickup, onDone, entry)
    -- Ein schon aktuelles Makro einfach wegzuziehen braucht keine Meldung.
    if not (state == "same" and pickup == "drag") then
        ns.Print(L[DONE_MESSAGES[state]]:format(name, Import.ScopeLabel(perChar)))
    end
    if entry and index then
        for _, fn in ipairs(appliedListeners) do ns.Try("Import", fn, entry, index) end
    end
    if pickup then PickUp(index, pickup) end
    if onDone then onDone(index) end
    ns.SettingChanged("macros")
end

-- Text in Blizzards Makro, für lange Makros der ganze Text aus ezMacro (Long.lua).
function Import.RawBody(index)
    if not index or type(GetMacroInfo) ~= "function" then return nil end
    local _, _, body = GetMacroInfo(index)
    return body
end

function Import.BodyOf(index)
    local body = Import.RawBody(index)
    return (ns.Long and ns.Long.FullBody(body)) or body
end

-- Eine Stelle für CreateMacro/EditMacro (über Core.Macro.Write). Text über 255 Zeichen wird ein langes Makro: im
-- Platz steht nur „/click“, der Text liegt in ezMacro (Long.lua). Der Name wird wie im Client auf 16 Zeichen
-- gekürzt (Core.Macro.Write lehnt längere ab). Rückgabe: Index oder nil.
local function Write(index, name, icon, body, perChar)
    local current = index and Import.RawBody(index)
    if #body > ns.MACRO_MAX_CHARS then
        body = ns.Long and ns.Long.Store(name, body, perChar, current)
        if not body then return nil end
    elseif current and ns.Long then
        ns.Long.Release(current)   -- war lang, ist jetzt kurz
    end
    name = ns.Truncate(tostring(name or ""), ns.MACRO_NAME_MAX)
    return (Macro.Write(name, icon or (not index and ns.DEFAULT_ICON or nil), body, perChar and true or false, index))
end

-- Ersetzt nur den Text eines vorhandenen Makros (Name, Symbol und Bereich bleiben), z. B. neue Ränge.
function Import.Rewrite(index, body)
    if ns.InCombat() then return nil end
    local name = type(GetMacroInfo) == "function" and GetMacroInfo(index)
    if not name then return nil end
    local _, maxAccount = Import.Counts()
    return Write(index, name, nil, Import.CleanBody(body), index > maxAccount)
end

local function Overwrite(data)
    if ns.InCombat() then return Fail(ns.CombatText()) end
    -- Der Index kann sich verschoben haben, solange das Fenster offen war.
    local index, perChar = Import.Find(data.name)
    if not index then
        return Import.Apply(data.entry, data.name, data.body, data.perChar, data.pickup, data.onDone)
    end
    local newIndex = Write(index, data.name, data.icon, data.body, perChar)
    if not newIndex then return Fail(L.ERR_FAILED) end
    Done(newIndex, perChar, data.name, "updated", data.pickup, data.onDone, data.entry)
end

-- Rückfragen über ezCores Ja/Nein-Dialog (Core.Confirm, V-100) statt zweier eigener Dialog-Tabellen.

-- Legt das Makro an oder ersetzt (nach Rückfrage) ein gleichnamiges.
-- pickup: danach an den Mauszeiger hängen. onDone(index) nach Erfolg.
function Import.Apply(entry, name, body, perChar, pickup, onDone)
    if not Import.Available() then return Fail(L.ERR_NO_API) end
    if ns.InCombat() then return Fail(ns.CombatText()) end

    name = Import.CleanName(name)
    body = Import.CleanBody(body)
    if name == "" then return Fail(L.ERR_EMPTY_NAME) end
    if body == "" then return Fail(L.ERR_EMPTY_BODY) end
    if #body > Import.MaxChars() then return Fail(L.ERR_TOO_LONG:format(#body, Import.MaxChars())) end

    -- Eigene Symbole mitgeben; dynamische Makros behalten beim Ersetzen das vorhandene Symbol.
    local icon = entry and entry.icon and ns.MacroIcon(entry) or nil

    local existing, existingPerChar = Import.Find(name)
    if existing then
        if Import.CleanBody(Import.BodyOf(existing)) == body then
            Done(existing, existingPerChar, name, "same", pickup, onDone, entry)
            return true
        end
        local data = { entry = entry, name = name, body = body, icon = icon,
            perChar = perChar, pickup = pickup, onDone = onDone }
        Core.Confirm(L.POPUP_OVERWRITE:format(name, Import.ScopeLabel(existingPerChar)), function() Overwrite(data) end)
        return true
    end

    local numAccount, maxAccount, numChar, maxChar = Import.Counts()
    if perChar and numChar >= maxChar then
        return Fail(L.ERR_FULL:format(L.SCOPE_char, numChar, maxChar))
    elseif not perChar and numAccount >= maxAccount then
        return Fail(L.ERR_FULL:format(L.SCOPE_account, numAccount, maxAccount))
    end

    local index = Write(nil, name, icon, body, perChar)
    if not index then return Fail(L.ERR_FAILED) end
    Done(index, perChar, name, "created", pickup, onDone, entry)
    return true
end

-- Hängt ein vorhandenes Makro an den Mauszeiger oder legt es dafür zuerst an.
function Import.Drag(entry, name, body, perChar)
    if ns.InCombat() then return Fail(ns.CombatText()) end
    return Import.Apply(entry, name, body, perChar, "drag")
end

---------------------------------------------------------------------------
-- Viele Makros auf einmal (Sicherung zurückholen, Leisten-Profil laden): erst ein Plan, dann **eine**
-- gesammelte Rückfrage statt einer je Makro.
-- list = { { name, body, icon, perChar }, … }
---------------------------------------------------------------------------

function Import.Plan(list)
    local plan = { create = {}, replace = {}, same = {}, full = {}, invalid = {} }
    local numAccount, maxAccount, numChar, maxChar = Import.Counts()
    local free = { [true] = maxChar - numChar, [false] = maxAccount - numAccount }
    local seen = {}
    for _, macro in ipairs(list or {}) do
        local name, body = Import.CleanName(macro.name), Import.CleanBody(macro.body)
        local perChar = macro.perChar and true or false
        local item = { name = name, body = body, icon = macro.icon, perChar = perChar }
        local key = (perChar and "c:" or "a:") .. name
        if name == "" or body == "" or #body > Import.MaxChars() then
            table.insert(plan.invalid, item)
        elseif not seen[key] then
            seen[key] = true
            local index = ns.Macros.Find(name, perChar)
            if index then
                if Import.CleanBody(Import.BodyOf(index)) == body then
                    table.insert(plan.same, item)
                else
                    table.insert(plan.replace, item)
                end
            elseif free[perChar] > 0 then
                free[perChar] = free[perChar] - 1
                table.insert(plan.create, item)
            else
                table.insert(plan.full, item)
            end
        end
    end
    plan.changes = #plan.create + #plan.replace
    return plan
end

-- Zusammenfassung für Rückfrage und Chat: „9 neu, 2 ersetzen, 1 unverändert, 3 ohne Platz“.
function Import.PlanText(plan)
    local parts = {}
    if #plan.create > 0 then parts[#parts + 1] = L.PLAN_CREATE:format(#plan.create) end
    if #plan.replace > 0 then parts[#parts + 1] = L.PLAN_REPLACE:format(#plan.replace) end
    if #plan.same > 0 then parts[#parts + 1] = L.PLAN_SAME:format(#plan.same) end
    if #plan.full > 0 then parts[#parts + 1] = L.PLAN_FULL:format(#plan.full) end
    if #plan.invalid > 0 then parts[#parts + 1] = L.PLAN_INVALID:format(#plan.invalid) end
    if #parts == 0 then return L.PLAN_EMPTY end
    return table.concat(parts, ", ")
end

-- Führt den Plan aus (außerhalb des Kampfes): erst ersetzen, dann anlegen. Rückgabe: Anzahl der Änderungen.
function Import.RunPlan(plan)
    if ns.InCombat() then
        Fail(ns.CombatText())
        return 0
    end
    local done = 0
    for _, item in ipairs(plan.replace) do
        local index = ns.Macros.Find(item.name, item.perChar)
        if index and Write(index, item.name, item.icon, item.body, item.perChar) then done = done + 1 end
    end
    for _, item in ipairs(plan.create) do
        if Write(nil, item.name, item.icon, item.body, item.perChar) then done = done + 1 end
    end
    if done > 0 then ns.SettingChanged("macros") end
    return done
end

-- Fragt einmal nach („<title>: 9 neu, 2 ersetzen …?“) und führt dann alles aus.
-- onDone(done, plan) nach dem Ausführen; ohne Änderungen nur eine Meldung, keine Rückfrage.
-- extra: weitere Zeile für die Rückfrage (z. B. „42 Aktionsplätze belegen“), force: auch ohne Makro-Änderung fragen.
function Import.ConfirmPlan(plan, title, onDone, extra, force)
    if ns.InCombat() then return Fail(ns.CombatText()) end
    if plan.changes == 0 and not force then
        ns.Print(L.PLAN_NOTHING:format(title, Import.PlanText(plan)))
        if onDone then onDone(0, plan) end
        return true
    end
    local text = L.PLAN_CONFIRM:format(title, Import.PlanText(plan))
    if extra then text = text .. "\n" .. extra end
    Core.Confirm(text, function()
        if ns.InCombat() then return Fail(ns.CombatText()) end
        local done = Import.RunPlan(plan)
        ns.Print(L.PLAN_DONE:format(title, done, Import.PlanText(plan)))
        if onDone then onDone(done, plan) end
    end)
    return true
end
