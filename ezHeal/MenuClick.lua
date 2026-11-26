local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Blizzards „Menü“ (Rechtsklick) und „Ziel“ (Linksklick) auf den Einheiten-, Gruppen- und Raidrahmen (Spieltest des
    Nutzers vom 24.11.2026, wörtlich „ich kann nicht das menü beim gruppenmitglied oder mir aufrufen“). Beides gibt es nur,
    solange Blizzards Klick-Zauber-Profil es nennt (Grund und Quelle: Core.ClickBindings.Interactions). ezHeals Vorlagen
    lassen blanken Links- und Rechtsklick frei (T.RESERVED); Blizzards Fenster, ein geladenes Profil oder ein anderes Addon
    können sie trotzdem belegen – ezHeal sagt es dann einmal je Charakter und Lage im Chat, nennt es im Status und bietet
    „Menü und Ziel zurückholen“ an: Menü des Knopfs „Vorlagen“ an Blizzards Fenster „Klick-Zauber“ und Einstellungsseite,
    Abschnitt „Klick-Belegung“. Geschrieben wird nach einer Rückfrage, die nennt, was weicht, nur außerhalb des Kampfes;
    ezCore sichert vorher, „Zurück“ holt die alte Belegung.

    Rechtsklick bleibt „Menü“ (Schalter keepMenu, ab Werk an; Nutzer am 25.11.2026, wörtlich: „Einfaches Rechtsklick muss im
    ezheal verboten sein, dann entsteht das Problem nicht“): Liegt auf dem Rechtsklick ohne Umschalttaste etwas anderes als
    „Menü“, legt ezHeal „Menü“ von selbst zurück (M.Keep) und sagt im Chat, was gewichen ist – beim Anmelden, nach dem
    Schließen von Blizzards Fenster, nach jedem Schreiben über ezCore und nach einem Wechsel der Talentgruppe, nur außerhalb
    des Kampfes (sonst danach). In Blizzards Fenster sagt der Chat es schon beim Belegen (M.OnUnbound). „Zurück“ und geladene
    Profile kommen gleich mit „Menü“ (M.Fix). Zauber und Makros auf anderen Tasten, auch Umschalt/Strg/Alt + Rechtsklick,
    bleiben, wie sie sind; ein verlegtes „Menü“ kommt von seiner Taste zurück. „Ziel“ rührt ezHeal nur an, wenn es selbst auf
    dem Rechtsklick liegt (dann kommt es auf den Linksklick, wenn der frei ist; sonst schreibt ezHeal nichts und sagt es
    einmal). Läuft ein anderes Addon für Klick-Zauber, hält ezHeal sich zurück (Leitlinie 9). Bis zum 25.11.2026 galt: nie von selbst (so mit
    ausgeschaltetem Schalter weiter).
    Ob das Spiel das Schreiben ohne Klick des Spielers annimmt, ist offen (Blizzards Beschreibung: HasRestrictions, ohne
    Angabe welche; docs/api-pruefung.md 5.3). Nimmt es sie nicht an, sagt ezHeal es samt dem Weg per Klick und versucht es
    nur noch einmal, wenn der Spieler in Blizzards Fenster speichert (ein Klick); lehnt das Spiel auch das ab, bis /reload
    nicht wieder.
]]
local M = {}
ns.MenuClick = M

M.DELAY = 8     -- Sekunden nach dem Anmelden bis zum Blick auf die Belegung (der Client lädt sein Profil nach)
M.SETTLE, M.TRIES = 3, 4     -- danach so lange (höchstens so oft) warten, bis zwei Blicke dieselbe Belegung zeigen
M.AFTER_SPEC = 2             -- Sekunden nach einem Wechsel der Talentgruppe bis zum ersten Blick
M.VERIFY = 0.5               -- Sekunden zwischen Schreiben und dem Blick, ob das Spiel es angenommen hat
M.WINDOW_DELAY = 1.5         -- Sekunden nach dem Schließen von Blizzards Fenster bis zum zweiten Blick
M.RETRIES = 2                -- so oft neu ansetzen, wenn sich die Belegung bis zu diesem Blick anders änderte
M.KEEP_KEY = "ezHeal:keepMenu"

local function CB()
    local cb = Core.ClickBindings
    if type(cb) ~= "table" or type(cb.Interactions) ~= "function" or not cb.Available() then return nil end
    return cb
end

-- Lage von „Ziel“ und „Menü“ → Liste (Core.ClickBindings.Interactions) | nil (nicht oder nicht ganz lesbar), dazu die Belegung
function M.State()
    local cb = CB()
    if not cb then return nil end
    local list, complete = cb.List()
    if type(list) ~= "table" or not complete then return nil end
    return cb.Interactions(list), list
end

-- Was liegt auf der Taste? → „Blitzheilung“ | „frei“
local function OnText(entry)
    if not entry then return L.MENUCLICK_FREE end
    return ns.Templates.Describe(entry)
end

-- Eine Zeile je Interaktion. all: auch, was am Platz liegt. → Liste
function M.Lines(states, all)
    local T, lines = ns.Templates, {}
    for _, info in ipairs(states or {}) do
        local name, key = T.ActionText(info.action), T.KeyText(info.button, "")
        if info.state == "missing" then
            lines[#lines + 1] = L.MENUCLICK_MISSING:format(name, key, OnText(info.on))
        elseif info.state == "moved" then
            local at = T.KeyText(info.entry.button, info.entry.modifiers)
            lines[#lines + 1] = L.MENUCLICK_MOVED:format(name, at, key, OnText(info.on))
        elseif all then
            lines[#lines + 1] = L.MENUCLICK_OK:format(name, key)
        end
    end
    return lines
end

-- Fehlt „Ziel“ oder „Menü“ ganz? (Verlegt ist eine Wahl des Spielers; „Menü“ nur ohne den Schalter keepMenu.)
-- → Kennung der Lage | nil. Ohne Zauber-ID: „Ränge aktualisieren“ tauscht nur sie, der Name bleibt (sonst dieselbe Meldung
-- je Rang; Review 24.11.2026).
local function Signature(states)
    local parts = {}
    for _, info in ipairs(states or {}) do
        if info.state == "missing" then
            parts[#parts + 1] = info.action .. "=" .. (info.on and (tostring(info.on.kind) .. ":" .. tostring(OnText(info.on))) or "-")
        end
    end
    return #parts > 0 and table.concat(parts, " ") or nil
end

-- Schon gesagte Lagen dieses Charakters { [Kennung] = true } – sie bleiben gemerkt, auch wenn zwischendurch alles am Platz
-- war (Wechsel der Talentgruppe, „Zurückholen“ und „Zurück“)
local function Told()
    local db, key = ns.db, ns.charKey or Core.charKey
    if type(db) ~= "table" or type(key) ~= "string" then return nil end
    if type(db.menuClick) ~= "table" then db.menuClick = {} end
    if type(db.menuClick[key]) ~= "table" then db.menuClick[key] = {} end
    return db.menuClick[key]
end

-- Vergisst ezCore einen Charakter, vergisst ezHeal seine Meldung mit (Core.lua, CHAR_FORGOTTEN)
function M.Forget(key)
    local db = ns.db
    if type(db) == "table" and type(db.menuClick) == "table" and key then db.menuClick[key] = nil end
end

-- Diese Lage einmal je Charakter: → true, wenn sie noch nicht gesagt war (und jetzt gemerkt ist)
local function FirstTime(signature)
    local told = signature and Told() or nil
    if not told or told[signature] then return false end
    told[signature] = true
    return true
end

-- Einmal je Charakter und Lage sagen. Leere Belegung (Client hat sein Profil noch nicht geladen) und ein fremdes Addon fürs
-- Klick-Zaubern (Leitlinie 9): kein Wort. → true, wenn eine Zeile kam
function M.Say()
    if ns.ClickCaster() then return false end
    local states, list = M.State()
    if not states or #list == 0 then return false end
    if not FirstTime(Signature(states)) then return false end
    ns.Print(L.MENUCLICK_SAY:format(table.concat(M.Lines(states), " "), L.MENU_MENUCLICK, ns.MenuClickSettingPath()))
    return true
end

function ns.MenuClickSettingPath()
    return Core.SettingsPathText(ADDON, "OPT_HEADER_BINDINGS", "OPT_MENUCLICK", L)
end

---------------------------------------------------------------------------
-- Rechtsklick bleibt „Menü“ (keepMenu)
---------------------------------------------------------------------------

local writing = false     -- schreibt M.Keep gerade? (dann nicht auf das eigene Schreiben reagieren)
local verifying = false   -- wartet M.Keep auf den Blick danach?
local failed = false      -- das Schreiben brachte nichts: bis zum nächsten Einschalten bzw. /reload nicht wieder versuchen
local failedInClick = false   -- … auch nicht aus einem Klick des Spielers heraus (M.WindowClosed)
local inClick = false     -- läuft der Blick gerade im Klick auf „Speichern“?
local retries = 0         -- neu angesetzt seit dem letzten Erfolg (M.RETRIES)
local settleRun = 0       -- laufende Kette von M.Settled (eine neue ersetzt sie)
local atShow              -- Belegung, als Blizzards Fenster aufging

function M.KeepOn()
    return ns.Enabled("keepMenu") and not ns.ClickCaster()
end

-- Verspricht ezHeal gerade, „Menü“ zurückzulegen? (Schalter an, und das Spiel hat es nicht abgelehnt)
function M.Active()
    return M.KeepOn() and not failed
end

function ns.KeepMenuSettingPath()
    return Core.SettingsPathText(ADDON, "OPT_HEADER_BINDINGS", "OPT_keepMenu", L)
end

-- Liste mit „Menü“ auf dem einfachen Rechtsklick → neue Liste, Lage davor (wie Core.ClickBindings.Interactions) |
-- dieselbe Liste, nil, Grund ("off", "same", "target", dazu der Eintrag auf dem Linksklick). Geschrieben wird hier nichts. Liegt „Ziel“ auf dem Rechtsklick,
-- verlöre es dabei seine Taste: dann kommen beide zurück (info.target = true), aber nur, wenn der Linksklick frei ist oder
-- nur „Menü“ trägt – sonst bleibt alles, wie es ist ("target"), und ezHeal sagt es nur.
function M.Fix(list)
    local cb = CB()
    if not cb or type(list) ~= "table" or not M.KeepOn() then return list, nil, "off" end
    local menu
    for _, info in ipairs(cb.Interactions(list) or {}) do
        if info.action == "menu" and info.state ~= "ok" then menu = info end
    end
    if not menu then return list, nil, "same" end
    local only = { menu = true }
    if menu.on and menu.on.kind == "interaction" and menu.on.action == "target" then
        local left = cb.Find(list, "LeftButton", 0)
        if left and left.kind ~= "interaction" then return list, nil, "target", left end
        only, menu.target = nil, true
    end
    local new, count = cb.RestoreInteractions(list, only)
    if count == 0 then return list, nil, "same" end
    return new, menu
end

local function Failed(why, click)
    failed, failedInClick = true, click == true
    ns.Print(L.KEEPMENU_FAILED:format(why, L.MENU_MENUCLICK))
end

-- Belegung als Text, um zwei Blicke zu vergleichen | nil (leer oder nicht ganz lesbar)
local function Fingerprint()
    local _, list = M.State()
    if type(list) ~= "table" or #list == 0 then return nil end
    local parts = {}
    for i, entry in ipairs(list) do
        parts[i] = table.concat({ tostring(entry.kind), tostring(entry.id), tostring(entry.button), tostring(entry.modifiers) }, ":")
    end
    return table.concat(parts, "|")
end

-- Nach dem Schreiben nachsehen: liegt „Menü“ wirklich dort? Dann sagen, was wich (und was sonst noch fehlt). Abgelehnt hat
-- das Spiel nur, wenn noch die Belegung von davor liegt; ist sie nicht lesbar oder eine andere (Talentgruppe gewechselt,
-- etwas anderes hat geschrieben), setzt ezHeal neu an – höchstens M.RETRIES mal.
local function Verify(info, before, click)
    verifying = false
    if not M.KeepOn() then return end
    local now = Fingerprint()
    local _, still = M.Fix(now and select(2, M.State()) or nil)
    if not now or still then
        if now ~= before and retries < M.RETRIES then
            retries = retries + 1
            M.Settled()
        else
            Failed(L.KEEPMENU_REFUSED, click)
        end
        return
    end
    failed, failedInClick, retries = false, false, 0
    local path = ns.KeepMenuSettingPath()
    if info.target then
        ns.Print(L.KEEPMENU_DONE_TARGET:format(path))
    elseif info.on then
        ns.Print(L.KEEPMENU_DONE:format(OnText(info.on), path))
    else
        ns.Print(L.KEEPMENU_DONE_EMPTY:format(path))
    end
    M.Say()
end

-- Nach dem Kampf nachsehen – einen Wimpernschlag später, nach einem in ezCore wartenden Wunsch
local function AfterCombat()
    Core.AfterCombat(function() C_Timer.After(0, function() ns.Try("Rechtsklick bleibt Menü", M.Check) end) end, M.KEEP_KEY, ADDON)
end

-- „Menü“ zurücklegen, wenn der einfache Rechtsklick etwas anderes trägt → true (geschrieben, M.VERIFY Sekunden später folgt
-- der Blick danach) | false, Grund ("off", "same", "target", "missing", "unreadable", "combat": nach dem Kampf, "pending":
-- ein Wunsch wartet in ezCore, danach sieht ezHeal nach, "failed"). Eine leere Belegung bleibt unberührt (der Client hat
-- sein Profil noch nicht geladen). Ohne Sicherung: „Zurück“ holt weiter den Stand von vor dem letzten Übernehmen – die
-- Sicherung dieses Schreibens trüge nur den Eintrag auf dem Rechtsklick, den „Zurück“ nicht wiederbringen darf; der Chat
-- nennt ihn.
function M.Keep()
    if not M.KeepOn() then return false, "off" end
    if failed and (failedInClick or not inClick) then return false, "failed" end
    local cb = CB()
    if not (cb and cb.Writable()) then return false, "missing" end
    local list, complete = cb.List()
    if type(list) ~= "table" or not complete or #list == 0 then return false, "unreadable" end
    local new, info, why, left = M.Fix(list)
    if not info then return false, why, left end
    local waits = cb.Pending()
    if Core.InCombat() then AfterCombat() end
    if waits then return false, "pending" end
    if Core.InCombat() then return false, "combat" end
    local before, click = Fingerprint(), inClick
    writing = true
    local called, ok, reason = pcall(cb.Set, new, { owner = ADDON, keepDefaults = false, backup = false, quiet = true })
    writing = false
    if not called or not ok then
        if not called then Core.Error(ADDON, ok, "Rechtsklick bleibt Menü") end
        Failed(called and ns.Explain(reason) or L.KEEPMENU_REFUSED, click)
        return false, "failed"
    end
    verifying = true
    C_Timer.After(M.VERIFY, function() ns.Try("Rechtsklick bleibt Menü", Verify, info, before, click) end)
    return true
end

-- Zeile zu „Zurück“ und geladenen Profilen: was auf dem Rechtsklick läge → Text | nil (dort läge nichts)
function M.KeptText(info)
    if type(info) ~= "table" or not info.on then return nil end
    return L.KEEPMENU_KEPT:format(OnText(info.on), ns.KeepMenuSettingPath())
end

-- „Ziel“ liegt auf dem Rechtsklick und der Linksklick ist belegt: ezHeal schreibt nichts und sagt es einmal je Lage
function M.SayBlocked(left)
    local text = OnText(left)
    if not FirstTime("blocked=" .. text) then return false end
    ns.Print(L.KEEPMENU_BLOCKED:format(text, L.MENU_MENUCLICK, ns.MenuClickSettingPath()))
    return true
end

-- Nachsehen: zuerst zurücklegen, was der Schalter verlangt, dann sagen, was sonst fehlt („Ziel“; ohne Schalter „Menü“).
-- Solange das Zurücklegen wartet (Kampf, Wunsch in ezCore, Blick danach), kein Wort.
function M.Check()
    if writing or verifying then return false end
    local kept, reason, left = M.Keep()
    if kept then return true end
    if reason == "combat" or reason == "pending" then return false end
    if reason == "target" then return M.SayBlocked(left) end
    return M.Say()
end

-- Erst nachsehen, wenn zwei Blicke im Abstand M.SETTLE dieselbe Belegung zeigen: Geschrieben würde die gelesene Liste, eine
-- halb geladene wäre danach die ganze. Ein neuer Anlass ersetzt eine wartende Kette.
-- → wie M.Check | false (blieb leer oder unruhig, oder ersetzt) | nil (wartet)
function M.Settled(last, tries, run)
    if run == nil then
        settleRun = settleRun + 1
        run = settleRun
    elseif run ~= settleRun then
        return false
    end
    local now = Fingerprint()
    if now and now == last then return M.Check() end
    tries = tries or 0
    if tries >= M.TRIES then return false end
    C_Timer.After(M.SETTLE, function() ns.Try("Menü per Klick", M.Settled, now, tries + 1, run) end)
    return nil
end

-- Blizzards Fenster „Klick-Zauber“ geht auf: Belegung merken
function M.WindowShown()
    atShow = Fingerprint()
end

-- Blizzards Fenster „Klick-Zauber“ geht zu. „Speichern“ schließt es im selben Klick; falls das Spiel das Schreiben nur aus
-- einem Klick heraus nimmt, ist es hier noch einer – darum sofort nachsehen, aber nur, wenn das Gespeicherte schon zu lesen
-- ist (die Belegung ist eine andere als beim Öffnen): sonst schriebe ezHeal den alten Stand darüber. Kurz danach in jedem
-- Fall. Nicht, während ezCore das Fenster neu lädt (es schreibt dann gerade).
function M.WindowClosed()
    local cb, before, now = CB(), atShow, Fingerprint()
    atShow = nil
    if cb and not cb.Reloading() and before and now and now ~= before then
        inClick = true
        ns.Try("Menü per Klick", M.Check)
        inClick = false
    end
    C_Timer.After(M.WINDOW_DELAY, function() ns.Try("Menü per Klick", M.Check) end)
end

-- Blizzards Fenster „Klick-Zauber“ hat einer Zeile die Taste genommen (SetUnboundText; nur zugehört): war es „Menü“, gleich
-- sagen, dass ezHeal es nach dem Speichern zurücklegt. → true, wenn eine Zeile kam
function M.OnUnbound(element)
    local info = Core.Peek(element, "bindingInfo")
    local enum = rawget(_G, "Enum")
    local menuType = Core.Peek(Core.Peek(enum, "ClickBindingType"), "Interaction")
    local menuID = Core.Peek(Core.Peek(enum, "ClickBindingInteraction"), "OpenContextMenu")
    if type(info) ~= "table" or menuType == nil or menuID == nil or not M.Active() then return false end
    if Core.Plain(Core.Peek(info, "type")) ~= menuType or Core.Plain(Core.Peek(info, "actionID")) ~= menuID then return false end
    ns.Print(L.KEEPMENU_WINDOW)
    return true
end

-- Zeile für den Status | nil (nicht lesbar)
function M.StatusLine()
    local states, list = M.State()
    if not states or #states == 0 then return nil end
    local state = M.Active() and L.ON or (M.KeepOn() and L.KEEPMENU_STOPPED or L.OFF)
    if M.Active() and select(3, M.Fix(list)) == "target" then state = L.KEEPMENU_BLOCKED_STATE end
    return table.concat(M.Lines(states, true), " ") .. " " .. L.STATUS_KEEPMENU:format(state)
end

-- Zurückholen ohne Rückfrage → true, Anzahl | true, "same" | false, Grund ("missing", "combat", "unreadable", …)
function M.Apply()
    local cb = CB()
    if not (cb and cb.Writable()) then return false, "missing" end
    if Core.InCombat() then return false, "combat" end
    local states, list = M.State()
    if not states then return false, "unreadable" end
    local new, count = cb.RestoreInteractions(list)
    if count == 0 then return true, "same" end
    local ok, reason = cb.Set(new, { owner = ADDON, keepDefaults = false })
    if not ok then return false, reason end
    if reason ~= "same" then ns.Templates.DefaultsRestored() end
    failed, failedInClick, retries = false, false, 0
    -- die behobene Lage kennt der Spieler jetzt: „Zurück“ meldet sie nicht noch einmal
    local signature = Signature(states)
    local told = signature and Told() or nil
    if told then told[signature] = true end
    return true, reason == "same" and "same" or count
end

-- Knopf und Menüeintrag: was fehlt, mit Rückfrage zurückholen; fehlt nichts, sagt es der Chat. → true, wenn gefragt wurde
function M.Ask()
    if Core.InCombat() then
        ns.CombatNotice(L.APPLY_COMBAT_WHAT)
        return false
    end
    local cb = CB()
    if not (cb and cb.Writable()) then
        ns.Print(L.ERR_missing)
        return false
    end
    local states, list = M.State()
    if not states then
        ns.Print(L.ERR_unreadable)
        return false
    end
    local _, count = cb.RestoreInteractions(list)
    if count == 0 then
        ns.Print(L.MENUCLICK_FINE:format(table.concat(M.Lines(states, true), " ")))
        return false
    end
    Core.Confirm(L.ASK_MENUCLICK:format(table.concat(M.Lines(states), "\n")), function()
        local ok, reason = M.Apply()
        ns.Print(not ok and ns.Explain(reason) or (M.KeepOn() and L.MENUCLICK_DONE_KEEP or L.MENUCLICK_DONE))
    end)
    return true
end

ns.OnReady(function()
    C_Timer.After(M.DELAY, function() ns.Try("Menü per Klick", M.Settled) end)
    local cb = CB()
    -- nach jedem Schreiben über ezCore (Profil geladen, „Zurück“, Ränge): nachsehen – erst, wenn der Schreiber fertig ist
    -- (er führt danach noch seine Merkliste nach)
    if cb and type(cb.OnChange) == "function" then
        cb.OnChange(function(ok)
            if ok and not writing then C_Timer.After(0, function() ns.Try("Menü per Klick", M.Check) end) end
        end)
    end
    -- je Talentgruppe eine eigene Belegung (Blizzards Fenster hört auf das erste Ereignis)
    local function Later() C_Timer.After(M.AFTER_SPEC, function() ns.Try("Menü per Klick", M.Settled) end) end
    ns.OnUnit("PLAYER_SPECIALIZATION_CHANGED", "player", Later)
    ns.On("ACTIVE_TALENT_GROUP_CHANGED", Later)
end)

ns.OnSettingChanged(function(key)
    if key ~= "keepMenu" then return end
    failed, failedInClick, retries = false, false, 0
    ns.Try("Menü per Klick", M.Check)
end)
