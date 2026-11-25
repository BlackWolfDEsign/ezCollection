local _, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Lage „Auslieferung“ der Entdecker-Datenbank: Beiträge anderer Spieler aus dem Daten-Addon ezData (Entscheidung des
    Nutzers vom 22.11.2026: „enterprise“ – Daten getrennt vom Code, nachladbar, abschaltbar; Wortlaut und Auslegung im
    ROADMAP-Index, Eintrag „Beiträge anderer Spieler: eigenes Daten-Addon ezData“; Entwurf
    docs/archiv/entwurf-entdecker-datenbank.md, Abschnitte 8 und 9.2). ezData hat weder SavedVariables noch eigene
    Funktionen: tools/merge.lua schreibt je Tabelle eine Datei, die beim Laden DB.Ship(name, kopf, daten) ruft. Fehlt
    ezData oder ist es abgeschaltet, läuft alles weiter – die Lage bleibt leer.

    Laden: einmal nach PLAYER_LOGIN, nie im Kampf (sonst nach PLAYER_REGEN_ENABLED über Core.AfterCombat; Entwurf 9.2,
    „Wann lädt ezData?“). LoadOnDemand erspart das Laden nicht – es legt den Zeitpunkt fest und erlaubt das Abschalten.
    Die Dateien werden nicht umgebaut: eine Zeile wird erst beim Lesen kopiert.

      DB.Ship(name, kopf, daten)    meldet eine ausgelieferte Datei an (nur aus ezData). Gelesen wird sie nur, wenn
                                    kopf.fmt = DB.SHIP_FMT, die Tabelle angemeldet und kein Entdecker-Wissen ist und
                                    kopf.life und kopf.v ihrer Schicht und Version entsprechen – sonst nennt /ez status
                                    den Grund (DB.ShipStats).
                                    Kopf: fmt, life, v, builds = { lo, hi }, checked (Build der Client-Tabellen),
                                    contributors, day, license, minOrigins, rows (tools/merge.lua, M.ShipHead)
      DB.Shipped(name, k1 …)        → Kopie, info = { src = "ship", label = „aus Beiträgen (n Spieler), Stand Build x“,
                                      b, t, cnt, contributors, stale } oder nil, { reason }. Build und Zahl der
                                      Spieler sind die des Satzes (b, orig; bei Listen der neueste Eintrag bzw. der
                                      mit den meisten Herkünften), sonst die der ganzen Datei.
      DB.ShippedKeys(name, k1 …)    → sortierte Schlüssel einer Ebene der Auslieferung
      DB.ShipEach(fn, name, k1 …)   ruft fn(schlüssel, satz) je Eintrag einer Ebene, ohne Kopie (nur lesen, Reihenfolge
                                    beliebig) – für Umkehr-Indizes (ShipView.lua)
      DB.ShipInfoOf(name, satz)     → info zu einem so gelesenen Satz (wie bei DB.Shipped) oder nil
      DB.Best(name, k1 …)           → eine Antwort nach der Rangfolge (Entwurf, Abschnitt 8): frische Client-Antwort
                                      (Gegenstände über DB.Client), lokaler Satz (DB.Get; in den Schichten cache und
                                      held nur, wenn sein Build nicht älter ist als der ausgelieferte), Auslieferung.
                                      info.src nennt die Lage ("client", "own", "ship"). Kopiert wird nur der Satz,
                                      der gewinnt.
      DB.ShipStats()                → { state, reason, loadMs, rows, bytes (geschätzt wie DB.Stats), contributors,
                                      builds = { lo, hi }, checked, tables = { { name, rows, bytes, builds,
                                      contributors, day } }, skipped = { { name, why } } }
      DB.ShipLoad()                 lädt ezData jetzt (außerhalb des Kampfes, sonst danach) → true, wenn geladen
      DB.ShipVersion()              → Zahl, die bei jeder Änderung der Auslieferung steigt (für Arbeitsspeicher wie die
                                      Fundorte in Gathering.lua)
    state: "wait" (vor dem Einloggen), "combat" (wartet aufs Kampfende), "loaded", "missing" (nicht installiert),
    "disabled" (in der Addon-Liste aus), "failed" (reason nennt Blizzards Grund).

    DB.Get bleibt die eigene Lage („bei dir“): „bei dir“ und „aus Beiträgen“ bleiben getrennt (Leitlinie 11), und kein
    bestehender Leser mischt ausgelieferte Sätze unbemerkt unter die eigenen. Wer beide zeigt, fragt DB.Get und
    DB.Shipped und nennt je Zeile die Quelle; wer eine Antwort braucht, fragt DB.Best.
    Nachrichten: DB_SHIP_LOADED (name, build) je gelesener Datei, DB_SHIP_READY (Zahl der Tabellen) nach dem Laden.
]]

local DB = Core.DB
local Keys = DB.Keys
local Num, IsSecret = Core.Num, Core.IsSecret

DB.SHIP_ADDON = "ezData"
DB.SHIP_FMT = 1

local shipped = {}   -- [Tabelle] = { head = Kopf, rows = Daten } (die Tabellen der Datei selbst, nie verändert)
local skipped = {}   -- [Tabelle] = Grund ("unknown", "explorer", "fmt", "life", "version")
local state, reason, loadMs = "wait", nil, nil
local version = 0

function DB.ShipVersion() return version end

function DB.Ship(name, head, rows)
    if type(name) ~= "string" or type(head) ~= "table" or type(rows) ~= "table" then return false end
    version = version + 1
    local spec = DB.Spec(name)
    local why
    if not spec then why = "unknown"
    elseif spec.explorer then why = "explorer"
    elseif Num(head.fmt) ~= DB.SHIP_FMT then why = "fmt"
    elseif head.life ~= spec.life then why = "life"
    elseif Num(head.v) ~= spec.v then why = "version" end
    if why then
        skipped[name], shipped[name] = why, nil
        return false
    end
    skipped[name] = nil
    shipped[name] = { head = head, rows = rows }
    Core.Fire("DB_SHIP_LOADED", name, Num(type(head.builds) == "table" and head.builds.hi) or 0)
    return true
end

-- Ebene für Ebene absteigen; gesperrte Schlüssel nie als Index (Leitlinie 6)
local function Walk(t, ...)
    for i = 1, select("#", ...) do
        local k = select(i, ...)
        if type(t) ~= "table" or k == nil or IsSecret(k) then return nil end
        t = t[k]
    end
    return t
end

-- Build und Zahl der Spieler des Satzes selbst (orig, tools/merge.lua); bei einer Liste der neueste Eintrag bzw. der
-- Eintrag mit den meisten Herkünften – erst wenn der Satz nichts davon trägt, die Angaben der ganzen Datei
local function ShipInfo(head, row)
    local b, n = Num(row.b), Num(row.orig)
    for _, e in ipairs(row) do
        if type(e) == "table" then
            local eb, en = Num(e.b), Num(e.orig)
            if eb and not Num(row.b) then b = math.max(b or 0, eb) end
            if en and not Num(row.orig) then n = math.max(n or 0, en) end
        end
    end
    b = b or Num(type(head.builds) == "table" and head.builds.hi)
    n = n or Num(head.contributors) or 0
    return { src = "ship", label = L.DB_SHIP:format(n, tostring(b or "?")), b = b, t = Num(row.t), cnt = Num(row.cnt),
        contributors = n, stale = b ~= Keys.Build() or nil }
end

function DB.Shipped(name, ...)
    local s = shipped[name]
    if not s then return nil, { reason = skipped[name] or (state == "loaded" and "none" or "notloaded") } end
    if select("#", ...) == 0 then return nil, { reason = "nokey" } end
    local row = Walk(s.rows, ...)
    if type(row) ~= "table" then return nil, { reason = "none" } end
    return DB.Copy(row), ShipInfo(s.head, row)
end

function DB.ShippedKeys(name, ...)
    local s = shipped[name]
    local t = s and Walk(s.rows, ...)
    return type(t) == "table" and Core.SortedKeys(t) or {}
end

function DB.ShipEach(fn, name, ...)
    local s = shipped[name]
    local t = s and Walk(s.rows, ...)
    for k, row in pairs(type(t) == "table" and t or {}) do fn(k, row) end
end

function DB.ShipInfoOf(name, row)
    local s = shipped[name]
    if not s or type(row) ~= "table" then return nil end
    return ShipInfo(s.head, row)
end

-- ausgelieferter Satz ohne Kopie (nur zum Vergleichen) » Satz, info | nil
local function ShipRow(name, ...)
    local s = shipped[name]
    local row = s and select("#", ...) > 0 and Walk(s.rows, ...)
    if type(row) ~= "table" then return nil end
    return row, ShipInfo(s.head, row)
end

-- kopiert wird nur der Satz, der gewinnt
function DB.Best(name, ...)
    if name == "item" then return DB.Client("item", ...) end
    local own, info = DB.Get(name, ...)
    local ship, shipInfo = ShipRow(name, ...)
    if own and ship then
        local spec = DB.Spec(name)
        if spec and spec.life ~= "seen" and (Num(info.b) or 0) < (Num(shipInfo.b) or 0) then
            return DB.Copy(ship), shipInfo
        end
        return own, info
    end
    if own then return own, info end
    if ship then return DB.Copy(ship), shipInfo end
    return nil, info
end

function DB.ShipStats()
    local out = { state = state, reason = reason, loadMs = loadMs, tables = {}, rows = 0, bytes = 0, contributors = 0,
        builds = {}, skipped = {} }
    for _, name in ipairs(DB.Tables()) do
        local s = shipped[name]
        if s then
            local head, spec = s.head, DB.Spec(name)
            local rows = Num(head.rows) or 0
            local bytes = rows * (Num(spec and spec.bytes) or 80)
            local b = type(head.builds) == "table" and head.builds or {}
            local lo, hi, n = Num(b.lo), Num(b.hi), Num(head.contributors) or 0
            out.tables[#out.tables + 1] = { name = name, rows = rows, bytes = bytes, builds = { lo = lo, hi = hi },
                contributors = n, day = type(head.day) == "string" and head.day or nil }
            out.rows, out.bytes, out.contributors = out.rows + rows, out.bytes + bytes, math.max(out.contributors, n)
            if lo then out.builds.lo = math.min(out.builds.lo or lo, lo) end
            if hi then out.builds.hi = math.max(out.builds.hi or hi, hi) end
            out.checked = math.max(out.checked or 0, Num(head.checked) or 0)
        end
    end
    for _, name in ipairs(Core.SortedKeys(skipped)) do out.skipped[#out.skipped + 1] = { name = name, why = skipped[name] } end
    return out
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function DB.ShipLoad()
    if state == "loaded" then return true end
    if Core.InCombat() then
        state = "combat"
        Core.AfterCombat(DB.ShipLoad, "ezCore.DB.ShipLoad")
        return false
    end
    -- Ladezeit in Millisekunden (debugprofilestop, wie die Scheiben in DB.lua) für /ez status – Leistung beim Laden
    local profile = rawget(_G, "debugprofilestop")
    local t0 = type(profile) == "function" and profile() or nil
    local ok, why = Core.LoadAddOn(DB.SHIP_ADDON)
    loadMs = t0 and (profile() - t0) or nil
    if ok then
        state, reason = "loaded", nil
        Core.Fire("DB_SHIP_READY", Count(shipped))
    else
        reason = why
        state = why == "DISABLED" and "disabled" or ((why == nil or why == "MISSING") and "missing" or "failed")
    end
    return ok
end

-- nur für die Prüfungen: zurück in den Zustand vor dem Einloggen
function DB.ShipReset()
    shipped, skipped, state, reason, loadMs = {}, {}, "wait", nil, nil
    version = version + 1
end

ns.On("PLAYER_LOGIN", function() DB.ShipLoad() end)

Core.RegisterMessage("DB_SHIP_LOADED", "DBShip.lua", "Eine Datei der Auslieferung (ezData, Beiträge anderer Spieler) ist gelesen.", "name, build")
Core.RegisterMessage("DB_SHIP_READY", "DBShip.lua", "ezData ist geladen (einmal nach dem Einloggen, nie im Kampf).", "tabellen")
