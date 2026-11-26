local _, ns = ...
local Core = ezCore

-- Kleine Helfer, die mehrere Module brauchen. Alles ohne Fehler bei fehlender API.

---------------------------------------------------------------------------
-- Secret Values (Kampf/Instanz): prüfen und auslassen, nie damit rechnen
---------------------------------------------------------------------------

local isSecret = type(issecretvalue) == "function" and issecretvalue or nil
local canAccess = type(canaccessvalue) == "function" and canaccessvalue or nil

-- Zuerst issecretvalue: Gesperrte Werte dürfen nicht einmal mit nil verglichen werden.
function Core.IsSecret(value)
    if isSecret and isSecret(value) then return true end
    if value == nil then return false end
    if canAccess and not canAccess(value) then return true end
    return false
end

-- Alle Werte normal (nicht geheim)?
function Core.Usable(...)
    for i = 1, select("#", ...) do
        if Core.IsSecret((select(i, ...))) then return false end
    end
    return true
end

-- value nur, wenn er nicht geheim ist.
function Core.Plain(value)
    if Core.IsSecret(value) then return nil end
    return value
end

-- Geschützter Aufruf, dessen erste zwei Rückgaben nur kommen, wenn keine geheim ist (sonst nil); eine fehlende Funktion
-- und Fehler geben still nil (Gegenprüfung I3, Gesamtreview 18.11.2026: vorher je eine Kopie in Inspect.lua,
-- UnitTooltip.lua und ezGear/GroupCheck.lua).
function Core.PlainCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok or Core.IsSecret(a) or Core.IsSecret(b) then return nil end
    return a, b
end

-- Zahl, mit der sicher gerechnet werden darf (keine Secret Values, kein nil).
function Core.Num(value)
    if Core.IsSecret(value) or type(value) ~= "number" then return nil end
    return value
end

-- Feld einer Tabelle lesen, die gesperrt sein oder einem fremden Addon gehören kann: geheime Tabelle, keine
-- Tabelle oder ein Fehler beim Lesen (Metatabelle, gesperrte Aura) → nil. Vorher je eine Kopie in Auras.lua (Peek)
-- und Sources.lua (Field).
local function RawField(t, key) return t[key] end

function Core.Peek(t, key)
    if Core.IsSecret(t) or type(t) ~= "table" then return nil end
    local ok, value = pcall(RawField, t, key)
    if ok then return value end
    return nil
end

-- Wahrheitswert, der geheim sein kann: dann (oder bei nil) gilt fallback (vorher ezCombat).
function Core.Bool(value, fallback)
    if Core.IsSecret(value) or value == nil then return fallback end
    return value and true or false
end

-- Wie Core.Bool, aber nil heißt „nein“ (Welle 23a, A56; vorher ezMacro AutoEmote Answer): Viele Abfragen des Clients
-- liefern nil für „nicht“ (UnitInRaid, IsInGuild …). Nur ein gesperrter Wert wird durch whenSecret ersetzt.
function Core.Flag(value, whenSecret)
    if Core.IsSecret(value) then return whenSecret end
    return value and true or false
end

---------------------------------------------------------------------------
-- Addons, CVars, Kampf
---------------------------------------------------------------------------

function Core.IsLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name) == true
    end
    local isLoaded = rawget(_G, "IsAddOnLoaded")
    return type(isLoaded) == "function" and isLoaded(name) == true
end

-- → true | false, Grund (Blizzards zweite Rückgabe von LoadAddOn, etwa "MISSING" oder "DISABLED"; ezData, DBShip.lua).
-- Die alte globale Funktion nur über rawget: ezCore ruft das seit ezData bei jedem Einloggen, auch dort, wo es sie
-- nicht gibt.
function Core.LoadAddOn(name)
    if Core.IsLoaded(name) then return true end
    local load = (C_AddOns and C_AddOns.LoadAddOn) or rawget(_G, "LoadAddOn")
    if not load then return false end
    local ok, loaded, why = pcall(load, name)
    if (ok and loaded == true) or Core.IsLoaded(name) then return true end
    return false, ok and type(why) == "string" and why or nil
end

-- fn sofort, wenn das Addon schon geladen ist, sonst sobald es lädt. Ein Fehler in fn landet im
-- Fehlerprotokoll von owner (Standard: ezCore), statt den Aufrufer abzubrechen (vorher ezCombat).
function Core.WhenAddOnLoaded(name, fn, owner)
    local function Run()
        local ok, err = pcall(fn)
        if not ok then Core.Error(owner or Core.name, err, name) end
    end
    if Core.IsLoaded(name) then
        Run()
    elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded(name, Run)
    else
        -- Nach dem Lauf abmelden (V-016): sonst bliebe für jedes Addon ein toter Zuhörer auf ADDON_LOADED stehen.
        local done = false
        local function OnLoaded(_, loaded)
            if loaded == name and not done then
                done = true
                Core.UnregisterEvent(Core.name, "ADDON_LOADED", OnLoaded)
                Run()
            end
        end
        ns.On("ADDON_LOADED", OnLoaded)
    end
end

function Core.CVar(name)
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(name) end
    return GetCVar and GetCVar(name)
end

-- Geschützte CVars (z. B. im Kampf) werfen keinen Fehler (vorher ezCombat). Rückgabe: true bei Erfolg.
function Core.SetCVar(name, value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not set then return false end
    local ok, result = pcall(set, name, value)
    return ok and result ~= false
end

function Core.InCombat()
    return InCombatLockdown and InCombatLockdown() == true
end

-- Spieleinstellung auf Klick umstellen (Schalter in Menüs, Bausteinen, Knöpfen): nie im Kampf (T1-9/T2-5,
-- Gesamtreview 18.11.2026; auch ezCombats Schlagtimer prüft hier). Der Aufrufer sagt dem Spieler, was los ist –
-- Core.CombatNotice(ns, Core.L.CVAR_WHAT) oder ein eigener Gegenstand (ezCombat SWING_WHAT). Abläufe ohne Klick
-- nehmen Core.SetCVar und
-- warten selbst (Core.AfterCombat).
-- → true | false, "combat" | "failed" (das Spiel hat den Wert nicht angenommen)
function Core.SwitchCVar(name, value)
    if Core.InCombat() then return false, "combat" end
    if Core.SetCVar(name, value) then return true end
    return false, "failed"
end

---------------------------------------------------------------------------
-- Zeit und Tabellen (W-14: vorher 16 lokale „Now()“ mit zwei Bedeutungen, viermal „Clock()“, dreimal „SortedKeys“)
---------------------------------------------------------------------------

-- Uhrzeit in Sekunden seit 1970 (time()) – für alles, was gespeichert wird und einen /reload überlebt.
function Core.Now()
    return Core.Num(time and time()) or 0
end

-- Laufzeit der Sitzung in Sekunden mit Bruchteilen (GetTime()) – für Abstände, Takte und Fristen; nie speichern.
function Core.Uptime()
    return Core.Num(GetTime and GetTime()) or 0
end

---------------------------------------------------------------------------
-- Zeitbasis (Gesamtreview 18.11.2026, T16-NZ1 bis NZ4; Entscheidung 6 des Nutzers): Anzeigen („heute“, Uhrzeiten,
-- Datumsangaben) in der Ortszeit des PCs, Auswertungen (Preis-Tage, Stunde, Wochentag) in Serverzeit. Zwei Uhren
-- liefern gespeicherte Stempel: die PC-Uhr (Core.Now, time()) und die Serveruhr (GetServerTime, Core.DB.Stamp). Beide
-- zählen Sekunden seit 1970 (UTC); sie weichen nur voneinander ab, wenn die PC-Uhr falsch geht. Core.Time rechnet
-- zwischen beiden um, statt gespeicherte Stempel umzuschreiben. Basis: "local" (PC, Standard) oder "server".
-- Texte dazu (Time.Label, Time.Tagged) stehen in Format.lua.
---------------------------------------------------------------------------

Core.Time = Core.Time or {}
local Time = Core.Time
local DAY = 86400
Time.DAY = DAY
Time.SKEW_TOLERANCE = 2   -- Abweichung unter 2 Sekunden ist Messrauschen (beide Uhren zählen ganze Sekunden)
Time.ZONE_MAX = 14 * 3600 -- größter plausibler Abstand der Server-Zeitzone zu UTC

local function ServerClock()
    local fn = rawget(_G, "GetServerTime")
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn)
    v = ok and Core.Num(v)
    return v or nil
end

-- Uhrzeit jetzt: "local" (Standard) = PC-Uhr wie Core.Now, "server" = GetServerTime (ohne sie die PC-Uhr).
function Time.Now(base)
    if base == "server" then return ServerClock() or Core.Now() end
    return Core.Now()
end

local skewAt, skew = nil, 0
-- Abstand Serveruhr − PC-Uhr in Sekunden (0 ohne GetServerTime oder unter Time.SKEW_TOLERANCE). Höchstens einmal je
-- Minute neu gemessen; fresh = true misst sofort.
function Time.Skew(fresh)
    local up = Core.Uptime()
    if not fresh and skewAt and up >= skewAt and up - skewAt < 60 then return skew end
    skewAt, skew = up, 0
    local server = ServerClock()
    if server then
        local diff = server - Core.Now()
        if math.abs(diff) >= Time.SKEW_TOLERANCE then skew = diff end
    end
    return skew
end

-- Stempel der Serveruhr (DB.Stamp, Community-Nachrichten) auf die PC-Uhr umrechnen bzw. umgekehrt; nil ohne Zahl.
function Time.FromServer(t)
    t = Core.Num(t)
    return t and (t - Time.Skew()) or nil
end
function Time.ToServer(t)
    t = Core.Num(t)
    return t and (t + Time.Skew()) or nil
end
-- Stempel in der Basis from ("local" Standard, "server") als Stempel der PC-Uhr.
function Time.AsLocal(t, from)
    if from == "server" then return Time.FromServer(t) end
    return Core.Num(t)
end

local zoneAt, zone = nil, 0
-- Abstand der Server-Zeitzone zu UTC in Sekunden (auf Viertelstunden gerundet, höchstens Time.ZONE_MAX), aus
-- C_DateAndTime.GetServerTimeLocal; ohne sie 0 (UTC). Höchstens einmal je Minute neu gefragt; fresh = true sofort.
-- Vorher in Prices.DayOffset (Frage 37), das jetzt hierher weiterleitet.
function Time.Zone(fresh)
    local up = Core.Uptime()
    if not fresh and zoneAt and up >= zoneAt and up - zoneAt < 60 then return zone end
    zoneAt, zone = up, 0
    local api = rawget(_G, "C_DateAndTime")
    local getLocal = type(api) == "table" and api.GetServerTimeLocal
    if type(getLocal) == "function" then
        local ok, server = pcall(getLocal)
        server = ok and Core.Num(server)
        local utc = ServerClock() or Core.Now()
        if server and utc then
            local diff = math.floor((server - utc) / 900 + 0.5) * 900
            if math.abs(diff) <= Time.ZONE_MAX then zone = diff end
        end
    end
    return zone
end

-- Tagesnummer (Tage seit dem 1.1.1970) eines Kalenderdatums – dieselbe Zählung wie die Server-Tage.
local function DaysFromCivil(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end
Time.DaysFromCivil = DaysFromCivil

-- Tag, Stunde und Wochentag (0 = Sonntag; der 1.1.1970, Tag 0, war ein Donnerstag) eines Stempels t (Standard: jetzt)
-- im Kalender der Basis base ("local" Standard: Ortszeit des PCs; "server": Serverzeit). from nennt die Basis des
-- Stempels ("local" Standard = PC-Uhr wie Core.Now; "server" = Serveruhr wie DB.Stamp).
function Time.Day(t, base, from)
    t = Core.Num(t)
    if base == "server" then
        local s
        if from == "server" then s = t or Time.Now("server") else s = Time.ToServer(t or Core.Now()) end
        s = s + Time.Zone()
        local day = math.floor(s / DAY)
        return day, math.floor((s - day * DAY) / 3600), (day + 4) % 7
    end
    local lt = (t and Time.AsLocal(t, from)) or Core.Now()
    local d = date and date("*t", lt)
    if type(d) ~= "table" then
        local day = math.floor(lt / DAY)
        return day, math.floor((lt - day * DAY) / 3600), (day + 4) % 7
    end
    local day = DaysFromCivil(d.year, d.month, d.day)
    return day, d.hour, (day + 4) % 7
end

-- Heutiger Tag in der Basis (Tagesnummer wie Time.Day).
function Time.Today(base)
    return (Time.Day(nil, base))
end

-- Liegt der Stempel t (Basis from) am heutigen Tag der Basis base?
function Time.IsToday(t, base, from)
    if not Core.Num(t) then return false end
    return (Time.Day(t, base, from)) == Time.Today(base)
end

-- Beginn eines Tages (Tagesnummer) in der Basis base, als Stempel der PC-Uhr (vergleichbar mit Core.Now-Stempeln).
function Time.DayStart(day, base)
    day = Core.Num(day)
    if not day then return nil end
    day = math.floor(day)
    if base == "server" then return day * DAY - Time.Zone() - Time.Skew() end
    -- Kalenderdatum des Tages (Mittag UTC liegt am selben Datum wie die Tagesnummer)
    local d = date and date("!*t", day * DAY + DAY / 2)
    if type(d) ~= "table" or not time then return day * DAY end
    return time({ year = d.year, month = d.month, day = d.day, hour = 0, min = 0, sec = 0 })
end

-- Beginn des heutigen Tags in der Basis base als Stempel der PC-Uhr.
function Time.TodayStart(base)
    return Time.DayStart(Time.Today(base), base)
end

local function KeyOrder(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "boolean" then return (a and 1 or 0) < (b and 1 or 0) end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
end
local function TextOrder(a, b) return tostring(a) < tostring(b) end

-- Bit-Masken ohne Bibliothek (Lua 5.1, Zahl als Summe von Zweierpotenzen); eine Fassung statt fünf (Durchsicht
-- 24.11.2026; ezTalent/Optimize.lua behält seine, sie lädt auch ohne ezCore).
-- HasBit: Ist das Bit mit diesem Wert (1, 2, 4 …) gesetzt? Ohne Prüfung der Werte – auch für heiße Schleifen.
function Core.HasBit(mask, value) return math.floor(mask / value) % 2 == 1 end

-- Bit n (0 = niedrigstes) einer Maske aus Client-Tabellen: geprüft; negative Werte als 32 Bit, -1 = alle.
function Core.HasBitAt(mask, n)
    mask, n = Core.Num(mask), Core.Num(n)
    if not mask or not n or n < 0 or n > (mask < 0 and 31 or 52) then return false end
    if mask == -1 then return true end
    if mask < 0 then mask = mask + 4294967296 end
    return Core.HasBit(mask, 2 ^ n)
end

-- Schlüssel einer Tabelle in fester Reihenfolge: Zahlen nach Wert, Texte nach Alphabet, gemischte nach Art
-- (boolean, number, string). byText = true vergleicht alle als Text („10“ vor „9“; so sortierte Glow.lua bisher).
-- Keine Tabelle: leere Liste.
function Core.SortedKeys(map, byText)
    local keys = {}
    if Core.IsSecret(map) or type(map) ~= "table" then return keys end
    for key in pairs(map) do keys[#keys + 1] = key end
    table.sort(keys, byText and TextOrder or KeyOrder)
    return keys
end

-- Kurz gesammelt ausführen: viele Ereignisse in einem Bild lösen fn nur einmal aus (vorher ezCombat).
function Core.Throttle(fn, delay, owner)
    local pending = false
    return function()
        if pending then return end
        pending = true
        C_Timer.After(delay or 0.05, function()
            pending = false
            local ok, err = Core.PCallStack(fn)
            if not ok then Core.Error(owner or Core.name, err, "Throttle", nil, Core.TakeErrorStack()) end
        end)
    end
end

-- Dauer-Takt mit Griff (Gesamtreview 18.11.2026, T7-3; vorher je Modul ein C_Timer.NewTicker, dessen Rückgabe niemand
-- behielt – nie anzuhalten –, teils mit eigenem pcall ohne Stapel). fn läuft je Takt über Core.Try: ein Fehler steht in
-- der Fehlerliste von owner (Standard ezCore), mit Stapel. active (frei): fn → true, solange der Takt laufen soll; ohne
-- active läuft er immer. where: Name in der Fehlerliste (Standard „Ticker“). → Griff:
--   griff:Update()   startet bzw. hält an nach active() – etwa aus OnSettingChanged. → läuft?
--   griff:Start(), griff:Stop(), griff:Running(), griff:Fire() (ein Takt sofort; → ok wie Core.Try)
-- Ohne C_Timer.NewTicker (Prüf-Stub ohne Takte) bleibt der Griff angehalten; Fire geht trotzdem.
local TickerMethods = {}
TickerMethods.__index = TickerMethods

function TickerMethods:Fire()
    return Core.Try(self.owner, self.where, self.fn)
end

function TickerMethods:Running()
    return self.handle ~= nil
end

function TickerMethods:Start()
    if self.handle then return true end
    if not (C_Timer and C_Timer.NewTicker) or type(self.fn) ~= "function" then return false end
    local griff = self
    self.handle = C_Timer.NewTicker(self.seconds, function() griff:Fire() end)
    return self.handle ~= nil
end

function TickerMethods:Stop()
    local handle = self.handle
    self.handle = nil
    if handle and type(handle.Cancel) == "function" then handle:Cancel() end
end

function TickerMethods:Update()
    local want = true
    if type(self.active) == "function" then
        local ok, on = Core.Try(self.owner, self.where, self.active)
        want = ok and on and true or false
    end
    if want then self:Start() else self:Stop() end
    return self:Running()
end

function Core.Ticker(owner, seconds, fn, active, where)
    local griff = setmetatable({ owner = owner or Core.name, seconds = tonumber(seconds) or 1, fn = fn,
        active = active, where = where or "Ticker" }, TickerMethods)
    griff:Update()
    return griff
end

---------------------------------------------------------------------------
-- Eigenes Überblenden für alle Module (die Kopien in ezMacro und ezBars sind abgelöst). Nicht UIFrameFadeIn/Out: die tragen den Rahmen
-- in Blizzards Fade-Liste (FADEFRAMES) ein und lassen ihn von Blizzards Verwalter abarbeiten (Leitlinie 5).
---------------------------------------------------------------------------

local fades = {}    -- [Region] = { from, to, duration, elapsed, onDone }
local fader         -- eigener Taktgeber, läuft nur, solange etwas blendet

local function FadeDone(region, fade)
    fades[region] = nil
    region:SetAlpha(fade.to)
    if fade.onDone then
        local ok, err = pcall(fade.onDone, region, fade.to)
        if not ok then Core.Error(fade.owner or Core.name, err, "FadeTo") end
    end
end

-- Einen Schritt weiterblenden (intern, OnUpdate des Taktgebers). → true, solange noch etwas läuft.
function Core.FadeStep(elapsed)
    elapsed = tonumber(elapsed) or 0
    local running = false
    local done
    for region, fade in pairs(fades) do
        fade.elapsed = fade.elapsed + elapsed
        if fade.elapsed >= fade.duration then
            done = done or {}
            done[#done + 1] = region
        else
            region:SetAlpha(fade.from + (fade.to - fade.from) * fade.elapsed / fade.duration)
            running = true
        end
    end
    -- erst nach der Schleife abschließen: onDone darf ein neues Blenden starten
    for i = 1, done and #done or 0 do
        local region = done[i]
        local fade = fades[region]
        if fade then FadeDone(region, fade) end
    end
    if next(fades) then running = true end
    if not running and fader then fader:SetScript("OnUpdate", nil) end
    return running
end

local function FaderUpdate(_, elapsed) Core.FadeStep(elapsed) end

--[[
    Core.FadeTo(region, alpha, dauer, onDone, owner) → true: blendet | false: sofort gesetzt
      Blendet die Deckkraft einer EIGENEN Region (Rahmen, Textur, Text) in dauer Sekunden auf alpha. Ohne Dauer
      (nil, 0) oder ohne Region mit GetAlpha wird sofort gesetzt. Ein neues FadeTo ersetzt ein laufendes und
      startet beim aktuellen Wert. onDone(region, alpha) läuft am Ende (auch beim sofortigen Setzen).
      Ist die aktuelle Deckkraft ein gesperrter Wert, wird ohne Blenden gesetzt.
]]
function Core.FadeTo(region, alpha, duration, onDone, owner)
    if type(region) ~= "table" or type(region.SetAlpha) ~= "function" then return false end
    alpha = tonumber(alpha) or 1
    duration = tonumber(duration) or 0
    local from = region.GetAlpha and Core.Num(region:GetAlpha()) or nil
    local fade = { from = from or alpha, to = alpha, duration = duration, elapsed = 0, onDone = onDone, owner = owner }
    if duration <= 0 or from == nil or from == alpha or not CreateFrame then
        FadeDone(region, fade)
        return false
    end
    fades[region] = fade
    fader = fader or CreateFrame("Frame")
    fader:SetScript("OnUpdate", FaderUpdate)
    return true
end

-- Laufendes Blenden beenden. finish = true: sofort auf den Zielwert (mit onDone), sonst bleibt der aktuelle Wert.
-- → true, wenn eines lief.
function Core.StopFade(region, finish)
    local fade = fades[region]
    if not fade then return false end
    if finish then FadeDone(region, fade) else fades[region] = nil end
    return true
end

-- Blendet die Region gerade? → Zielwert oder nil.
function Core.Fading(region)
    local fade = fades[region]
    return fade and fade.to or nil
end

---------------------------------------------------------------------------
-- Aufrufe (vorher in elf Modulen je ein eigenes „Call“)
---------------------------------------------------------------------------

-- Läuft der Mitschnitt (/ez debug, Core.Debug.Running), steht der Fehler in der Fehlerliste (W-08, Entscheidung
-- des Nutzers 14.11.2026: „Ja, im Diagnosemodus“): je Meldungstext ein Eintrag, Wiederholungen zählen dort nur
-- hoch. Still – Blizzards Fehleranzeige bleibt zu, denn Core.Call sichert auch Aufrufe, deren Scheitern erwartet
-- ist. Ohne Mitschnitt ändert sich nichts.
local function DropOk(ok, ...)
    if ok then return ... end
    local debug = Core.Debug
    if debug and debug.Running and debug.Running() then Core.Error(Core.name, (...), "Core.Call", true) end
    return nil
end

-- Geschützter Aufruf, der auch eine fehlende Funktion verträgt: die Ergebnisse oder nil.
function Core.Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return DropOk(pcall(fn, ...))
end

-- Wie pcall, aber eine fehlende Funktion gibt false: ok, Ergebnisse.
function Core.PCall(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

-- Meldung oben in der Bildschirmmitte (Blizzards UIErrorsFrame); Standard rot wie Blizzards Fehler.
-- Ohne Farbe geht sie über Blizzards eigenen Weg für Addons (AddExternalErrorMessage: Blizzards Farbe), sonst –
-- oder wenn der Client ihn nicht kennt – über AddMessage. → true, wenn gezeigt.
-- Seit dem Gesamtreview vom 18.11.2026 (T18-23) statt der Zahlen auch eine Rolle aus Core.Style.COLOR:
-- Core.ErrorMessage(text, "warn") für Hinweise (gelb), ohne Farbe bleibt es Blizzards Fehlerweg.
function Core.ErrorMessage(text, r, g, b)
    if Core.IsSecret(text) or type(text) ~= "string" or text == "" then return false end
    if type(r) == "string" then
        local Style = Core.Style
        local rr, gg, bb
        if type(Style) == "table" and type(Style.Color) == "function" then rr, gg, bb = Style.Color(r) end
        r, g, b = rr, gg, bb
        if type(r) ~= "number" then r, g, b = 1, 1, 0 end
    end
    local frame = rawget(_G, "UIErrorsFrame")
    if type(frame) ~= "table" then return false end
    if r == nil and g == nil and b == nil and type(frame.AddExternalErrorMessage) == "function" then
        if pcall(frame.AddExternalErrorMessage, frame, text) then return true end
    end
    if type(frame.AddMessage) ~= "function" then return false end
    return (pcall(frame.AddMessage, frame, text, r or 1, g or 0.1, b or 0.1))
end

---------------------------------------------------------------------------
-- Gegenstände (vorher je mehrfach in ezCore und den Modulen)
---------------------------------------------------------------------------

-- Name aus einem Gegenstandslink.
function Core.ItemName(link)
    if type(link) ~= "string" or Core.IsSecret(link) then return nil end
    return link:match("%[(.-)%]")
end

-- itemID aus Zahl, Link, „item:123“, Zahlentext oder Tabelle mit itemID; sonst nil.
-- Anzahl eines Gegenstands beim gespielten Charakter (V-037): C_Item.GetItemCount, sonst das alte Global – vorher
-- je selbst in ezBuff, ezPanel, ezMerchant und (nur das entfernte Global) in Professions.lua.
--   bank = true      Bank mitzählen
--   charges = true   Aufladungen statt Stapel zählen (z. B. Zauberstäbe, Angelköder)
-- item: itemID, Link oder Name. Immer eine Zahl – 0, wenn die Schnittstelle fehlt oder der Wert gesperrt ist.
function Core.ItemCount(item, bank, charges)
    if Core.IsSecret(item) or item == nil then return 0 end
    local fn = (C_Item and C_Item.GetItemCount) or rawget(_G, "GetItemCount")
    if not fn then return 0 end
    local ok, count = pcall(fn, item, bank and true or false, charges and true or false)
    return ok and Core.Num(count) or 0
end

-- Gegenstands-Kennung eines Links ohne Namen und ohne das, was nur dieses Exemplar betrifft (Verzauberung, Sockel, uniqueID,
-- Stufe und Spezialisierung des Trägers, Herkunft): „item:12345:…“ mit Zusatz und Bonus, also dem, wonach auch das
-- Item-Wissen unterscheidet (Knowledge.VariantKey) – zum Merken (Core.GearOf); nil ohne Link.
function Core.ItemString(link)
    if Core.IsSecret(link) or type(link) ~= "string" then return nil end
    local body = link:match("item:([%-%d:]+)")
    if not body then return nil end
    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = field end
    for _, i in ipairs({ 2, 3, 4, 5, 6, 8, 9, 10, 12 }) do
        if fields[i] then fields[i] = "" end
    end
    return (("item:" .. table.concat(fields, ":")):gsub(":+$", ""))
end

function Core.ItemID(item)

    if Core.IsSecret(item) then return nil end
    local id
    if type(item) == "number" then
        id = item
    elseif type(item) == "table" then
        id = Core.Num(item.itemID)
    elseif type(item) == "string" and item ~= "" then
        id = tonumber(item:match("item:(%d+)") or item:match("^%s*(%d+)%s*$") or "")
    end
    return id and id > 0 and id or nil
end

-- Name zu einer itemID in der Spielsprache. Fehlen die Daten, fordert ezCore sie beim Client an
-- (Ereignis ITEM_DATA_LOAD_RESULT) und gibt nil.
function Core.ItemNameByID(item, noRequest)
    local id = Core.ItemID(item)
    if not id then return nil end
    local name = Core.Plain(Core.Call(C_Item and C_Item.GetItemNameByID, id))
    if type(name) ~= "string" or name == "" then
        name = Core.Plain(Core.Call(C_Item and C_Item.GetItemInfo or rawget(_G, "GetItemInfo"), id))
    end
    if type(name) == "string" and name ~= "" then return name end
    if not noRequest then Core.Call(C_Item and C_Item.RequestLoadItemDataByID, id) end
    return nil
end

-- Symbol (Datei-ID oder Pfad) eines Gegenstands (ID oder Link); nil, wenn unbekannt.
function Core.ItemIcon(item)
    local id = Core.ItemID(item)
    if not id then return nil end
    local icon = Core.Plain(Core.Call(C_Item and C_Item.GetItemIconByID, id))
    if icon == nil then
        local _, _, _, _, texture = Core.ItemInstant(id)
        icon = Core.Plain(texture)
    end
    return icon
end

-- Symbol eines Gegenstands als Bild im Text vor einer Zeile (Wunsch des Nutzers vom 18.11.2026 zum Beute-Tooltip:
-- „tooltip des drops vllt mit den item icons?“) – EIN Helfer für alle Zeilen, die Gegenstände nennen (ezLoot,
-- ezPanel, ezMerchant). Größe 0 = Höhe der Schrift der Zeile, Beschnitt wie Blizzards Symbole im Text und ezCores
-- Menüs (Core.Menu.ICON_CROP, 5:59 von 64). Das Symbol kommt über Core.ItemIcon (C_Item.GetItemIconByID, auch ohne
-- geladene Gegenstandsdaten); fehlt es, bleibt der Text ohne Bild.
--   Core.ItemIconMarkup(item) → "|T<symbol>:0:0…|t" oder nil
--   Core.ItemIconText(item, text, quality) → Bild, Leerzeichen, Text; text nil → Name in der Farbe der Qualität
--     (quality, sonst C_Item.GetItemQualityByID; Name über Core.ItemNameByID, fehlt er: nil). Gesperrt bleibt
--     gesperrt: ein gesperrter Text kommt unverändert zurück, ein gesperrter Gegenstand ohne Bild (Leitlinie 6).
function Core.ItemIconMarkup(item)
    if Core.IsSecret(item) then return nil end
    local icon = Core.ItemIcon(item)
    if Core.IsSecret(icon) then return nil end
    if type(icon) == "number" then
        if icon <= 0 then return nil end
    elseif type(icon) ~= "string" or icon == "" or icon:find("|", 1, true) or icon:find(":", 1, true) then
        return nil
    end
    local menu = Core.Menu
    local crop = type(menu) == "table" and type(menu.ICON_CROP) == "string" and menu.ICON_CROP or ""
    return ("|T%s:0:0%s|t"):format(tostring(icon), crop)
end

function Core.ItemIconText(item, text, quality)
    if Core.IsSecret(text) then return text end
    if text == nil then
        local name = Core.ItemNameByID(item)
        if not name then return nil end
        if quality == nil and not Core.IsSecret(item) then
            local id = Core.ItemID(item)
            quality = id and Core.PlainCall(C_Item and C_Item.GetItemQualityByID, id) or nil
        end
        quality = not Core.IsSecret(quality) and Core.Num(quality) or nil
        text = quality and (Core.QualityHex(quality) .. name .. "|r") or name
    end
    if type(text) ~= "string" then return text end
    local markup = Core.ItemIconMarkup(item)
    if not markup then return text end
    return markup .. " " .. text
end

-- Händlerpreis je Stück in Kupfer: aus dem Item-Wissen, sonst vom Client. 0 = unverkäuflich, nil = unbekannt.
function Core.VendorPrice(item)
    if Core.IsSecret(item) or item == nil then return nil end
    local K = Core.Knowledge
    local facts = K and Core.Call(K.Get, item)
    local price = type(facts) == "table" and Core.Num(facts.vendorPrice)
    if price then return price end
    local info = { Core.Call(C_Item and C_Item.GetItemInfo or rawget(_G, "GetItemInfo"), item) }
    return Core.Num(info[11])
end

-- Größter Stapel eines Gegenstands (Welle 23a, A11; vorher ezAuction Scan.MaxStack und ezBag Transfer MaxStack):
-- C_Item.GetItemMaxStackSizeByID, sonst der achte Wert von GetItemInfo; sonst fallback (Standard 1). Zweiter Wert:
-- true, wenn der Client die Zahl genannt hat (ezAuction will „unbekannt“ von 1 unterscheiden). item: ID, Link, Text.
function Core.MaxStack(item, fallback)
    if fallback == nil then fallback = 1 end
    local id = Core.ItemID(item)
    if not id then return fallback, false end
    local size = Core.Num(Core.Call(C_Item and C_Item.GetItemMaxStackSizeByID, id))
    if not (size and size > 0) then
        size = Core.Num((select(8, Core.Call(C_Item and C_Item.GetItemInfo or rawget(_G, "GetItemInfo"), id))))
    end
    if size and size > 0 then return size, true end
    return fallback, false
end

---------------------------------------------------------------------------
-- Namen und Muster
---------------------------------------------------------------------------

-- Text für string.find/match/gsub als Muster unschädlich machen.
function Core.EscapePattern(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("%p", "%%%0"))
end

-- Freier Name: base, sonst „base (2)“, „base (3)“ … taken(name) → true, wenn belegt.
-- opts.format (Standard „%s (%d)“), opts.maxChars kürzt base, damit der Zusatz passt, opts.default bei leerem base.
-- opts.suffix: fester Zusatz am Ende jedes Namens (ezMacros Kürzel „ (MO)“), zählt zu maxChars; die Zahl steht davor
-- („Sengender 2 (MO)“). Ein gekürzter base verliert Leerzeichen am Ende (nicht „Ein sehr  2“).
function Core.UniqueName(base, taken, opts)
    opts = opts or {}
    base = Core.Trim(type(base) == "string" and not Core.IsSecret(base) and base or "")
    if base == "" then base = opts.default or "?" end
    local fmt = opts.format or "%s (%d)"
    local suffix = type(opts.suffix) == "string" and opts.suffix or ""
    local function Len(text) return strlenutf8 and strlenutf8(text) or #text end
    local function Fit(text, extra)
        extra = extra + Len(suffix)
        if opts.maxChars and Len(text) + extra > opts.maxChars then
            return (Core.TruncateChars(text, opts.maxChars - extra):gsub("%s+$", ""))
        end
        return text
    end
    local first = Fit(base, 0) .. suffix
    if type(taken) ~= "function" or not taken(first) then return first end
    for n = 2, 999 do
        local name = fmt:format(Fit(base, Len(fmt:format("", n))), n) .. suffix
        if not taken(name) then return name end
    end
    return first
end

---------------------------------------------------------------------------
-- Zahlen
---------------------------------------------------------------------------

function Core.Round(value, digits)
    value = Core.Num(value)                          -- V-022: gesperrter oder fehlender Wert → nil statt Rechenfehler
    if not value then return nil end
    local mult = 10 ^ (Core.Num(digits) or 0)
    return math.floor(value * mult + 0.5) / mult
end

-- Median einer Zahlenliste (Welle 15; vorher je eine lokale Fassung in Prices.lua und History.PostStats). Sortiert die
-- Liste an Ort und Stelle; gesperrte oder fehlende Werte gehören nicht hinein. Gerade Anzahl: Mittel der beiden
-- mittleren Werte, kaufmännisch auf eine ganze Zahl gerundet (Kupfer). nil ohne Werte.
function Core.Median(list)
    if type(list) ~= "table" then return nil end
    local n = #list
    if n == 0 then return nil end
    table.sort(list)
    if n % 2 == 1 then return list[(n + 1) / 2] end
    return math.floor((list[n / 2] + list[n / 2 + 1]) / 2 + 0.5)
end

-- 12345 → „12.345“ (Trennzeichen je nach Spielsprache).
function Core.FormatNumber(value)
    value = Core.Num(value)
    if not value then return "?" end
    value = math.floor(value + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
    return tostring(value)
end

-- Große Zahlen kurz: 1,2k / 3,4 Mio. (deutsch mit Komma, englisch mit Punkt – Core.Decimal; Gesamtreview 18.11.2026,
-- T16-2: vorher stand trotz dieses Kommentars „1.2k“ im deutschen Client). Ab threshold (Standard 10 000) kurz, darunter
-- Core.FormatNumber; ezBag kürzt Stapelzahlen schon ab 1000 (kleine Knöpfe).
function Core.ShortNumber(value, threshold)
    value = Core.Num(value)
    if not value then return "?" end
    local abs = math.abs(value)
    if abs >= 1e6 then return (Core.L.FMT_MILLION):format(Core.Decimal(value / 1e6, 1)) end
    if abs >= (Core.Num(threshold) or 1e4) then return (Core.L.FMT_THOUSAND):format(Core.Decimal(value / 1e3, 1)) end
    return Core.FormatNumber(value)
end

-- Zahl mit Nachkommastellen im Zahlformat der Spielsprache (Entscheidung des Nutzers vom 16.11.2026, Nr. 41 „den
-- Empfehlungen folgen“): deutsch mit Komma („1,5“), englisch mit Punkt („1.5“); das Zeichen steht in Core.L.DECIMAL_SEP.
-- digits = Nachkommastellen (Standard 0: ganze Zahl ohne Zeichen). Gesperrter oder fehlender Wert: „?“. Grundlage von
-- Core.Percent, Core.Seconds, Core.Minutes und Core.Hours; Module, die Zahlen selbst formatieren, stellen später um.
function Core.Decimal(value, digits)
    value = Core.Num(value)
    if not value then return "?" end
    local text = ("%." .. math.max(0, math.floor(Core.Num(digits) or 0)) .. "f"):format(value)
    local sep = Core.L and Core.L.DECIMAL_SEP
    if type(sep) == "string" and sep ~= "" and sep ~= "." then text = text:gsub("%.", sep, 1) end
    return text
end

-- Kupfer als Gold-Zahl für Tabellenkalkulationen (Welle 26, Paket kern/ezcore-reste-24; vorher je eine Kopie in ezLoot
-- H.CopyGold, ezPanel ns.CopyGold und ezAuction ns.GoldNumber – Leitlinie 2): 1 g 23 s 45 k → „1,2345“, immer vier
-- Nachkommastellen (genau bis zum Kupfer), Dezimalzeichen der Spielsprache über Core.Decimal; Kupfer wird auf ganze
-- Zahlen gerundet, Ausgaben mit Minus („-1,5000“). Gesperrter oder fehlender Betrag: nil (Leitlinie 6). Die Spalte
-- format = "money" von Core.TableText schreibt ihre Zellen damit (gesperrt dort „?“).
function Core.GoldDecimal(copper)
    copper = Core.Num(copper)
    if not copper or copper ~= copper or copper == math.huge or copper == -math.huge then return nil end
    local negative = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local text = Core.Decimal(copper / 10000, 4)
    if negative and copper > 0 then text = "-" .. text end
    return text
end

-- Prozent aus EINER Stelle (Frage 9, Entscheidung des Nutzers 14.11.2026): deutsch „50 %“ mit Leerzeichen,
-- englisch „50%“ (Core.L.FMT_PERCENT). value ist schon in Prozent (50, nicht 0,5); digits = Nachkommastellen, im
-- deutschen Client mit Komma („12,5 %“, Core.Decimal; Welle 23d).
function Core.Percent(value, digits)
    value = Core.Num(value)
    if not value then return "?" end
    return Core.L.FMT_PERCENT:format(Core.Decimal(value, digits))
end

-- Einzahl oder Mehrzahl nach der Anzahl (Spieltest 14.11.2026: „Plunder verkauft: 1 Gegenstände“):
--   Core.Plural(1, "%d Gegenstand", "%d Gegenstände") → „1 Gegenstand“, (3, …) → „3 Gegenstände“, (0, …) → „0 Gegenstände“
-- Die Einzahl gilt nur bei genau 1 – im Deutschen und im Englischen gleich. Beide Formen stehen in der
-- Locale-Datei (L.X_ONE, L.X_MANY, deutsch und englisch); für Gegenstände gibt es sie fertig:
--   Core.Plural(n, Core.L.COUNT_ITEM_ONE, Core.L.COUNT_ITEM_MANY)
-- Weitere Werte nach den Formen gehen an string.format: Core.Plural(n, "%d Brief von %s", "%d Briefe von %s", name).
-- Formen ohne „%d“ kommen unverändert zurück; fehlt die Mehrzahl, gilt die Einzahl. Gesperrte oder fehlende
-- Anzahl: Mehrzahl (gesperrt: unbesehen eingesetzt, sonst „?“).
function Core.Plural(count, one, many, ...)
    if type(many) ~= "string" then many = one end
    if type(one) ~= "string" then one = many end
    if type(many) ~= "string" then return "" end
    local secret = Core.IsSecret(count)
    local form = many
    if not secret and count == 1 then form = one end
    if secret or type(count) == "number" then
        local ok, text = pcall(string.format, form, count, ...)
        if ok then return text end
    end
    local ok, text = pcall(string.format, (form:gsub("%%d", "%%s")), "?", ...)
    if ok then return text end
    return form
end

-- Blizzards Grammatik-Kode „|4Einzahl:Mehrzahl;“ auflösen (Welle 17; Fehlerliste des Nutzers vom 15.11.2026: im
-- Kopierfeld stand roh „in 2 |4Bereich:Bereichen;“). Schriftfelder und der Chat lösen den Kode selbst auf, ein
-- Eingabefeld (EditBox: Kopierfelder, Textfenster) und gespeicherte Texte nicht – was dorthin geht, läuft hier durch.
-- Wie bei Blizzard zählt die Zahl unmittelbar davor: genau 1 → Einzahl, sonst Mehrzahl („6.722“ ist eine Zahl;
-- Farbcodes |cAARRGGBB zählen nicht). Ohne Zahl davor: Mehrzahl. Kein Text: unverändert zurück.
function Core.ResolveGrammar(text)
    if type(text) ~= "string" or Core.IsSecret(text) or not text:find("|4", 1, true) then return text end
    local out, pos = {}, 1
    while true do
        local s, e, one, many = text:find("|4([^:;]*):([^;]*);", pos)
        if not s then break end
        local before = text:sub(1, s - 1):gsub("|c%x%x%x%x%x%x%x%x", "")
        local number = before:match("(%d[%d%.,]*)%D*$")
        local value = number and tonumber((number:gsub("[%.,]", ""))) or nil
        out[#out + 1] = text:sub(pos, s - 1)
        out[#out + 1] = value == 1 and one or many
        pos = e + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

-- Rest einer gekürzten Liste aus EINER Stelle (Welle 17, UE-08; vorher acht gleiche Texte in den Modulen):
--   Core.More(3) → „… und 3 weitere“, Core.More(1) → „… und noch 1“ (ohne Geschlecht, passt zu jedem Wort;
--   englisch „… and 3 more“);
--   inline = true ohne „… “ für den Satz: „A, B und 3 weitere“.
function Core.More(count, inline)
    local L = Core.L
    if inline then return Core.Plural(count, L.MORE_INLINE_ONE, L.MORE_INLINE_MANY) end
    return Core.Plural(count, L.MORE_ONE, L.MORE_MANY)
end

-- Pfeil einer Aufklappzeile (Nutzer am 24.11.2026, wörtlich: „"und x weitere" brauch noch einen aufklapppfeil“):
-- Blizzards Pfeil nach unten = zugeklappt, nach oben = offen. FoldTexture(open) → Datei; FoldText(open, text) → Text mit
-- dem Pfeil davor (für Textfelder; die Zauberbuch-Ansicht zeichnet ihn selbst, line.fold).
function Core.FoldTexture(open)
    return open and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up"
end

function Core.FoldText(open, text)
    return "|T" .. Core.FoldTexture(open) .. ":14:14|t " .. tostring(text or "")
end

---------------------------------------------------------------------------
-- Gesperrte Werte ANZEIGEN (Forever: UnitHealth ist immer gesperrt – auch die eigene Einheit, auch ohne Kampf)
---------------------------------------------------------------------------
-- Ein gesperrter Wert darf nicht geprüft, verglichen oder verrechnet werden. string.format nimmt ihn aber an und
-- liefert einen (wieder gesperrten) Text, den FontString:SetText, GameTooltip:AddLine und AddDoubleLine zeigen
-- (im Spiel bestätigt am 14.11.2026). Wo nur ANGEZEIGT wird, also nie Core.Num/Core.Plain (die machen aus dem
-- Wert nil, die Zeile fehlt dann still), sondern diese Helfer. Alle geben wie Core.PCall zuerst „ok“ zurück –
-- ein gewöhnlicher Wahrheitswert. Der Text dahinter kann gesperrt sein: nur weiterreichen, nie prüfen
-- (auch kein „if text then“), nie vergleichen.

-- string.format mit Werten, die gesperrt sein dürfen: nichts wird angesehen. → ok, text
function Core.FormatSecret(fmt, ...)
    if Core.IsSecret(fmt) or type(fmt) ~= "string" then return false, nil end
    local ok, text = pcall(string.format, fmt, ...)
    if ok then return true, text end
    return false, nil
end

-- Lässt sich der Wert in „%s“ einsetzen? Gesperrt: ja, unbesehen. Frei: nur eine Zahl. → vorhanden, gesperrt
local function Shown(value)
    if Core.IsSecret(value) then return true, true end
    return type(value) == "number", false
end

-- „aktuell / maximal (Prozent)“. Sind beide Zahlen frei, mit Tausenderpunkten und selbst gerechnetem Anteil.
-- Ist eine gesperrt, gehen beide roh durch string.format – gerechnet wird dann nichts; der Anteil erscheint nur,
-- wenn der Aufrufer einen fertigen Wert mitgibt (percent, 0–100, darf gesperrt sein: UnitHealthPercent mit
-- CurveConstants.ScaleTo100). → ok, text (ok = false: nichts zu zeigen)
function Core.RatioText(cur, max, percent)
    local L = Core.L
    local hasCur, curLocked = Shown(cur)
    local hasMax, maxLocked = Shown(max)
    if not (hasCur and hasMax) then return false, nil end
    if not curLocked and not maxLocked then
        if max <= 0 then return false, nil end
        return true, L.FMT_RATIO_PERCENT:format(Core.FormatNumber(cur), Core.FormatNumber(max),
            ("%d"):format(math.floor(cur / max * 100 + 0.5)))
    end
    if Shown(percent) then
        local okPercent, percentText = Core.FormatSecret("%.0f", percent)
        if okPercent then
            local ok, text = Core.FormatSecret(L.FMT_RATIO_PERCENT, cur, max, percentText)
            if ok then return true, text end
        end
    end
    return Core.FormatSecret(L.FMT_RATIO, cur, max)
end

-- Blizzards Kurve 0–1 → 0–100 (CurveConstants.ScaleTo100). Ohne Kurve liefern UnitHealthPercent und
-- UnitPowerPercent 0–1 – gesperrt, also nicht umrechenbar; dann bleibt der Anteil weg.
local function PercentCurve()
    local curves = rawget(_G, "CurveConstants")
    return type(curves) == "table" and curves.ScaleTo100 or nil
end

-- Leben einer Einheit als Text „aktuell / maximal (Prozent)“ – auch, wenn das Spiel die Werte sperrt. → ok, text
-- Den Anteil gesperrter Werte liefert der Client fertig: UnitHealthPercent(unit, usePredicted, curve).
function Core.UnitHealthText(unit)
    if Core.IsSecret(unit) or type(unit) ~= "string" then return false, nil end
    local curFn, maxFn = rawget(_G, "UnitHealth"), rawget(_G, "UnitHealthMax")
    if type(curFn) ~= "function" or type(maxFn) ~= "function" then return false, nil end
    local okCur, cur = pcall(curFn, unit)
    local okMax, max = pcall(maxFn, unit)
    if not (okCur and okMax) then return false, nil end
    local percent
    if Core.IsSecret(cur) or Core.IsSecret(max) then
        local fn, curve = rawget(_G, "UnitHealthPercent"), PercentCurve()
        if type(fn) == "function" and curve then
            local ok, value = pcall(fn, unit, true, curve)
            if ok then percent = value end
        end
    end
    return Core.RatioText(cur, max, percent)
end

-- Kraft einer Einheit (powerType: Enum.PowerType, nil = die aktuelle) als Text, wie Core.UnitHealthText. → ok, text
-- Anteil gesperrter Werte: UnitPowerPercent(unit, powerType, unmodified, curve).
function Core.UnitPowerText(unit, powerType)
    if Core.IsSecret(unit) or type(unit) ~= "string" then return false, nil end
    if Core.IsSecret(powerType) then powerType = nil end
    local curFn, maxFn = rawget(_G, "UnitPower"), rawget(_G, "UnitPowerMax")
    if type(curFn) ~= "function" or type(maxFn) ~= "function" then return false, nil end
    local okCur, cur = pcall(curFn, unit, powerType)
    local okMax, max = pcall(maxFn, unit, powerType)
    if not (okCur and okMax) then return false, nil end
    local percent
    if Core.IsSecret(cur) or Core.IsSecret(max) then
        local fn, curve = rawget(_G, "UnitPowerPercent"), PercentCurve()
        if type(fn) == "function" and curve then
            local ok, value = pcall(fn, unit, powerType, false, curve)
            if ok then percent = value end
        end
    end
    return Core.RatioText(cur, max, percent)
end

-- Pixel-Angabe für Schieberegler: „12 px“ (gerundet; vorher ezBars und ezCombat).
function Core.Pixels(value)
    value = Core.Num(value)
    if not value then return "?" end
    return ("%d px"):format(math.floor(value + 0.5))
end

-- Farbcode von Rot (0) über Gelb nach Grün (1).
function Core.Gradient(fraction)
    fraction = math.max(0, math.min(1, Core.Num(fraction) or 0))   -- V-022: gesperrter Wert zählt als 0
    local r, g
    if fraction < 0.5 then
        r, g = 1, fraction * 2
    else
        r, g = (1 - fraction) * 2, 1
    end
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), 0)
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

function Core.Trim(text)
    if type(text) ~= "string" then return "" end
    return (text:match("^%s*(.-)%s*$"))
end

-- Auf höchstens maxBytes kürzen, ohne ein UTF-8-Zeichen zu zerschneiden; „…“ markiert die Kürzung.
function Core.TruncateBytes(text, maxBytes)
    if type(text) ~= "string" or Core.IsSecret(text) then return text end
    maxBytes = tonumber(maxBytes) or 0
    if #text <= maxBytes then return text end
    -- V-020: das Auslassungszeichen (3 Bytes) zählt mit; nur eine UNVOLLSTÄNDIGE letzte Folge fällt weg.
    local mark = "…"
    local room = maxBytes - #mark
    if room <= 0 then return maxBytes >= #mark and mark or "" end
    local cut = text:sub(1, room)
    local start = #cut
    while start > 0 do
        local b = cut:byte(start)
        if b < 128 or b >= 192 then break end      -- kein Folgebyte: hier beginnt das letzte Zeichen
        start = start - 1
    end
    if start > 0 then
        local b = cut:byte(start)
        local need = (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1
        if #cut - start + 1 < need then cut = cut:sub(1, start - 1) end
    else
        cut = ""                                     -- nur Folgebytes: nichts Ganzes übrig
    end
    return cut .. mark
end

-- Auf höchstens maxChars Zeichen kürzen (UTF-8-sicher, ohne Markierung), z. B. für Makronamen.
function Core.TruncateChars(text, maxChars)
    if type(text) ~= "string" then return "" end
    if strlenutf8 and strlenutf8(text) <= maxChars then return text end
    local count, cut = 0, #text
    for pos in text:gmatch("()[^\128-\191]") do
        count = count + 1
        if count > maxChars then
            cut = pos - 1
            break
        end
    end
    return text:sub(1, cut)
end

-- Blizzards Formatstring (z. B. ERR_CHAT_PLAYER_NOT_FOUND_S, AUCTION_SOLD_MAIL_SUBJECT) als Suchmuster:
-- %s und %1$s werden zu (.-), %d zu (%d+); der Rest passt wörtlich, von Anfang bis Ende.
-- Die EINE Fassung (V-029, vorher eine zweite in Knowledge.lua): versteht %s, %d, Platznummern („%1$s“), „%%“,
-- %c (Vorzeichen), %f/%g (Zahl mit Komma oder Punkt) und Grammatik-Codes („|4Tag:Tage;“ → beliebig).
-- tooltip = true: wie eine Tooltip-Zeile behandeln („|n“ → Leerzeichen, Rand abschneiden).
function Core.FormatToPattern(fmt, tooltip)
    fmt = Core.Plain(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local s = fmt
    if tooltip then
        s = Core.Trim((s:gsub("|n", " ")))
        if s == "" then return nil end
    end
    s = s:gsub("|4[^;]*;", "\1")
    s = s:gsub("%%%d+%$", "%%")
    s = s:gsub("%%%%", "\2")
    s = s:gsub("%%[%-%d%.]*s", "\3"):gsub("%%[%-%d%.]*d", "\4"):gsub("%%c", "\5"):gsub("%%[%-%d%.]*[fg]", "\6")
    s = Core.EscapePattern(s)
    s = s:gsub("\1", ".-"):gsub("\2", "%%%%"):gsub("\3", "(.-)"):gsub("\4", "(%%d+)")
    s = s:gsub("\5", "([%%+%%-])"):gsub("\6", "([%%d%%.,]+)")
    return "^" .. s .. "$"
end

-- Tooltip-Zeile säubern: Farb-, Link-, Textur- und Umbruch-Codes weg, Rand ab; nil bei leerem oder gesperrtem Text.
function Core.CleanText(text)
    text = Core.Plain(text)
    if type(text) ~= "string" or text == "" then return nil end
    text = Core.Trim((Core.PlainText(text):gsub("|n", " ")))
    if text == "" then return nil end
    return text
end

-- Farbcodes, Links und Symbole in reinen Text umwandeln (für Briefe und Vorschauen).
function Core.PlainText(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|cn[^:]*:", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("|K.-|k", "?")
    return text
end

-- Nur Farbcodes entfernen.
function Core.StripColors(text)
    if type(text) ~= "string" then return text end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

---------------------------------------------------------------------------
-- Texturen: immer die des Clients (Forever-Originalstil), mit schlichtem Ersatz
---------------------------------------------------------------------------

function Core.AtlasExists(name)
    if not (name and C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- Ausschnitt eines Atlas für SetTexCoord: left..right und top..bottom als Anteile (0 bis 1) des Atlas-Bereichs →
-- l, r, t, b in Koordinaten seiner Datei, oder nil ohne Angaben des Clients. SetTexCoord nach SetAtlas rechnet gegen die
-- ganze Datei, ein Atlas ist oft nur ein Teil davon (C_Texture.GetAtlasInfo: left/right/top/bottomTexCoord; so rechnet
-- auch Blizzards TotemFrame.lua der Forever-Quelle). Gegenprüfung I1 vom 18.11.2026 (ezQuest, Erfahrungsleiste).
-- Fünfter Wert: die Datei des Atlas (info.file) für SetTexture mit dem Ausschnitt (ezMerchants Bodenleiste; Nachlauf
-- P19a des Gesamtreviews, vorher eine eigene Abfrage in ezMerchant).
function Core.AtlasTexCoord(name, left, right, top, bottom)
    if not (name and C_Texture and C_Texture.GetAtlasInfo) then return nil end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    if not ok or type(info) ~= "table" or Core.IsSecret(info) then return nil end
    local l, r = Core.Num(info.leftTexCoord), Core.Num(info.rightTexCoord)
    local t, b = Core.Num(info.topTexCoord), Core.Num(info.bottomTexCoord)
    if not (l and r and t and b) then return nil end
    left, right, top, bottom = left or 0, right or 1, top or 0, bottom or 1
    local file = Core.Plain(info.file)
    return l + (r - l) * left, l + (r - l) * right, t + (b - t) * top, t + (b - t) * bottom, file
end

-- Erster vorhandener Atlas aus einer Liste (Namen können je Client abweichen).
function Core.FirstAtlas(list)
    for _, name in ipairs(list) do
        if Core.AtlasExists(name) then return name end
    end
    return nil
end

-- Eigene Position: uiMapID, x, y (0 bis 1) oder nil (Instanz, Ladebildschirm, gesperrter Wert).
-- Vorher je eine Fassung in ezMap/Core.lua und ezPanel/Blocks/Location.lua.
-- Klassen-Kürzel ("MAGE") und Stufe des eigenen Charakters; nil, solange der Client sie nicht kennt.
function Core.PlayerClass()
    local _, token = Core.Call(rawget(_G, "UnitClass"), "player")
    token = Core.Plain(token)
    return type(token) == "string" and token ~= "" and token or nil
end

function Core.PlayerLevel()
    return Core.Num((Core.Call(rawget(_G, "UnitLevel"), "player")))
end

function Core.PlayerPosition(mapID)
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    if mapID == nil then
        local ok, best = pcall(C_Map.GetBestMapForUnit, "player")
        mapID = ok and Core.Num(best) or nil
    end
    if not mapID then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok then return nil end
    local x, y = Core.Map.XY(pos)
    if not (x and y) or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end

--[[
    Kartenhelfer (W-14; vorher fünfmal in ezMap und zweimal in ezCore):
      Core.Map.XY(vektor)                → x, y            Blizzards Vector2D (GetXY) oder { x, y }; gesperrt/leer: nil
      Core.Map.Info(mapID)               → Blizzards UiMapDetails oder nil
      Core.Map.Parent(mapID, zielTyp)    → mapID, info     die Karte selbst oder die nächste Elternkarte, deren Art
                                           höchstens zielTyp ist (Enum.UIMapType: Cosmic 0, World 1, Continent 2,
                                           Zone 3, Dungeon 4, Micro 5, Orphan 6; der Name "Zone" geht auch).
                                           Ohne Treffer nach Core.Map.MAX_DEPTH Schritten: nil
      Core.Map.WorldPos(mapID, x, y)     → Kontinent, wx, wy (Meter) – für Entfernungen über Zonengrenzen
      Core.Map.PosOn(ziel, mapID, x, y)  → x, y auf der Karte ziel (0–1) oder nil, wenn der Punkt dort nicht liegt
      Core.Map.FromWorld(kontinent, wx, wy) → mapID, x, y der Zone dort (Kleinkarten auf ihre Zone umgerechnet) oder nil
      Core.Map.PosOn(ziel, mapID, x, y, true) → x, y auch außerhalb von 0–1 (Richtung und Linie zu einem Punkt neben
                                           der Karte, etwa für Routen über den Kartenrand); nil ohne Weltlage oder
                                           auf einem anderen Kontinent als die Karte ziel
      Core.Map.Zones(kontinent)          → { { map, name } … } die Zonen direkt unter dem Kontinent laut Client
                                           (C_Map.GetMapChildrenInfo mit Kartentyp Zone), nach Namen; leer ohne
                                           Antwort. Zonen unter einer anderen Zone fehlen (bei Forevers Karten keine;
                                           Städte hängen direkt am Kontinent). Seit 22.11.2026 (ezMap Flugmeister,
                                           Lehrer und Händler laut Questie)
    Alles nil, wenn der Client die Funktion nicht hat oder gesperrt antwortet.
]]
local Map = {}
Core.Map = Map
Map.MAX_DEPTH = 8
Map.TYPES = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 }

function Map.XY(pos)
    if Core.IsSecret(pos) or type(pos) ~= "table" then return nil end
    local x, y
    if type(pos.GetXY) == "function" then
        local ok, px, py = pcall(pos.GetXY, pos)
        if ok then x, y = px, py end
    else
        x, y = pos.x, pos.y
    end
    x, y = Core.Num(x), Core.Num(y)
    if not (x and y) then return nil end
    return x, y
end

function Map.Info(mapID)
    mapID = Core.Num(mapID)
    local api = rawget(_G, "C_Map")
    if not mapID or type(api) ~= "table" then return nil end
    local info = Core.Call(api.GetMapInfo, mapID)
    if Core.IsSecret(info) or type(info) ~= "table" then return nil end
    return info
end

local function MapType(kind)
    if type(kind) == "string" then
        local enum = Enum and Enum.UIMapType
        return Core.Num(enum and enum[kind]) or Map.TYPES[kind]
    end
    return Core.Num(kind)
end

function Map.Parent(mapID, kind)
    local target = MapType(kind)
    mapID = Core.Num(mapID)
    if not target then return nil end
    for _ = 1, Map.MAX_DEPTH do
        local info = mapID and Map.Info(mapID)
        if not info then return nil end
        local mapType = Core.Num(info.mapType)
        if not mapType or mapType <= target then return mapID, info end
        mapID = Core.Num(info.parentMapID)
    end
    return nil
end

function Map.Zones(continent)
    continent = Core.Num(continent)
    local api = rawget(_G, "C_Map")
    if not continent or type(api) ~= "table" then return {} end
    local children = Core.Call(api.GetMapChildrenInfo, continent, MapType("Zone"))
    if Core.IsSecret(children) or type(children) ~= "table" then return {} end
    local out, seen = {}, {}
    for _, child in ipairs(children) do
        local map = type(child) == "table" and Core.Num(child.mapID) or nil
        local name = map and child.name
        if map and not seen[map] and not Core.IsSecret(name) and type(name) == "string" and name ~= "" then
            seen[map] = true
            out[#out + 1] = { map = map, name = name }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Map.WorldPos(mapID, x, y)
    mapID, x, y = Core.Num(mapID), Core.Num(x), Core.Num(y)
    local api, vector = rawget(_G, "C_Map"), rawget(_G, "CreateVector2D")
    if not (mapID and x and y) or type(api) ~= "table" or type(vector) ~= "function" then return nil end
    if type(api.GetWorldPosFromMapPos) ~= "function" then return nil end
    local ok, continent, pos = pcall(api.GetWorldPosFromMapPos, mapID, vector(x, y))
    if not ok then return nil end
    continent = Core.Num(continent)
    local wx, wy = Map.XY(pos)
    if not (continent and wx and wy) then return nil end
    return continent, wx, wy
end

-- Weltlage → Lage auf der Karte target über drei Ecken der Karte (affin; Weltachsen dürfen zur Karte gedreht bzw.
-- vertauscht sein) → x, y (auch außerhalb von 0–1) oder nil (Ecke unbekannt, anderer Kontinent, entartete Karte)
function Map.PosFromCorners(target, continent, wx, wy)
    local c0, x0, y0 = Map.WorldPos(target, 0, 0)
    local c1, x1, y1 = Map.WorldPos(target, 1, 0)
    local c2, x2, y2 = Map.WorldPos(target, 0, 1)
    if not (c0 and c1 and c2) or c0 ~= continent or c1 ~= continent or c2 ~= continent then return nil end
    local ax, ay, bx, by, dx, dy = x1 - x0, y1 - y0, x2 - x0, y2 - y0, wx - x0, wy - y0
    local det = ax * by - bx * ay
    if math.abs(det) < 1e-9 then return nil end
    return (dx * by - bx * dy) / det, (ax * dy - dx * ay) / det
end

-- Weltlage → Zone dort samt Lage (die Client-Tabellen führen Weltkoordinaten: Flugpunkte, Dungeoneingänge). Nennt der
-- Client eine Kleinkarte, wird auf die Zone darüber umgerechnet. → mapID, x, y (0–1) oder nil
function Map.FromWorld(continent, wx, wy)
    continent, wx, wy = Core.Num(continent), Core.Num(wx), Core.Num(wy)
    local api, vector = rawget(_G, "C_Map"), rawget(_G, "CreateVector2D")
    if not (continent and wx and wy) or type(api) ~= "table" or type(api.GetMapPosFromWorldPos) ~= "function"
        or type(vector) ~= "function" then return nil end
    local ok, mapID, pos = pcall(api.GetMapPosFromWorldPos, continent, vector(wx, wy))
    local x, y = Map.XY(ok and pos or nil)
    mapID = ok and Core.Num(mapID) or nil
    if not (mapID and x and y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    local zone = Map.Parent(mapID, "Zone")
    if zone and zone ~= mapID then
        local zx, zy = Map.PosOn(zone, mapID, x, y)
        if zx then return zone, zx, zy end
    end
    return mapID, x, y
end

function Map.PosOn(target, mapID, x, y, outside)
    target, mapID, x, y = Core.Num(target), Core.Num(mapID), Core.Num(x), Core.Num(y)
    if not (target and mapID and x and y) then return nil end
    if target == mapID then return x, y end
    local api, vector = rawget(_G, "C_Map"), rawget(_G, "CreateVector2D")
    if type(api) ~= "table" or type(api.GetMapPosFromWorldPos) ~= "function" or type(vector) ~= "function" then return nil end
    local continent, wx, wy = Map.WorldPos(mapID, x, y)
    if not continent then return nil end
    local ok, _, pos = pcall(api.GetMapPosFromWorldPos, continent, vector(wx, wy), target)
    local tx, ty
    if ok then tx, ty = Map.XY(pos) end
    -- neben der Karte: liefert der Client dort keine Lage, rechnet ezCore sie über die Ecken der Zielkarte um
    -- (dieselbe Kontinent-Prüfung steckt darin)
    if not (tx and ty) and outside == true then return Map.PosFromCorners(target, continent, wx, wy) end
    if not (tx and ty) then return nil end
    if tx < 0 or tx > 1 or ty < 0 or ty > 1 then
        if outside ~= true then return nil end
        -- neben der Karte nur auf demselben Kontinent (sonst wäre die Lage eine sinnlose Umrechnung)
        local own = Map.WorldPos(target, 0.5, 0.5)
        if own ~= continent then return nil end
    end
    return tx, ty
end

--[[
    Karte nach ihrem Namen (Welle 23c, A30; vorher je eine eigene Suche in ezQuest Entrance.ZoneMap und ezMap
    Way.FindMap – ezMaps Präfix- und Teilwortsuche bleibt dort):
      Core.Map.NameKey(name)          → Vergleichsschlüssel: klein, ohne Rand und ohne führenden Artikel (ezCore führt
                                        „Schwarzfels“, der deutsche Client nennt die Karte „Der Schwarzfels“); nil bei
                                        gesperrtem oder leerem Namen
      Core.Map.Top(mapID)             → oberste Karte über mapID (Kette der Elternkarten), sonst nil
      Core.Map.ByName(name, zielTyp)  → uiMapID, info – gesucht unter der obersten Karte über der Karte des Spielers und
                                        über Blizzards Weltkarte (GetFallbackWorldMapID; in Instanzen endet die eigene
                                        Kette oft ohne Eltern); eine Karte der Art zielTyp (Name oder Zahl wie bei
                                        Map.Parent, Standard "Zone") hat Vorrang vor gleichnamigen anderer Art. Je Name
                                        und Art einmal gesucht; „nicht gefunden“ nur gemerkt, wenn der ganze Baum (oben
                                        Kosmos oder Welt) gefragt war. Core.Map.ForgetNames() leert den Zwischenspeicher.
]]
Map.ARTICLES = { "der ", "die ", "das ", "the " }

function Map.NameKey(name)
    name = Core.Plain(name)
    if type(name) ~= "string" then return nil end
    local key = Core.Trim(name:lower())   -- Core.Trim (T16-15)
    for _, article in ipairs(Map.ARTICLES) do
        if key:sub(1, #article) == article then key = key:sub(#article + 1) break end
    end
    return key ~= "" and key or nil
end

function Map.Top(mapID)
    mapID = Core.Num(mapID)
    for _ = 1, Map.MAX_DEPTH do
        local info = mapID and Map.Info(mapID)
        if not info then return nil end
        local parent = Core.Num(info.parentMapID)
        if not parent or parent == 0 or not Map.Info(parent) then return mapID end
        mapID = parent
    end
    return mapID
end

local byName = {}   -- „Schlüssel|Art“ » uiMapID (false: im ganzen Kartenbaum nicht gefunden)

function Map.ForgetNames() byName = {} end

function Map.ByName(name, kind)
    local key = Map.NameKey(name)
    local want = MapType(kind or "Zone")
    if not (key and want) then return nil end
    local cacheKey = key .. "|" .. want
    local hit = byName[cacheKey]
    if hit == false then return nil end
    if hit then return hit, Map.Info(hit) end
    local api = rawget(_G, "C_Map")
    if type(api) ~= "table" then return nil end   -- später erneut versuchen, nichts merken
    local roots, seen = {}, {}
    for _, start in ipairs({ Core.Call(api.GetBestMapForUnit, "player") or false, Core.Call(api.GetFallbackWorldMapID) or false }) do
        local top = start and Map.Top(start)
        if top and not seen[top] then seen[top] = true roots[#roots + 1] = top end
    end
    local found, foundInfo, exact, whole = nil, nil, false, false
    local worldType = Map.TYPES.World
    for _, top in ipairs(roots) do
        local topInfo = Map.Info(top)
        if topInfo and (Core.Num(topInfo.mapType) or 9) <= worldType then whole = true end
        local list = Core.Call(api.GetMapChildrenInfo, top, nil, true)
        if Core.IsSecret(list) then list = nil end
        for _, info in ipairs(type(list) == "table" and list or {}) do
            if type(info) == "table" and Map.NameKey(info.name) == key then
                local id, isWanted = Core.Num(info.mapID), Core.Num(info.mapType) == want
                if id and (not found or (isWanted and not exact)) then found, foundInfo, exact = id, info, isWanted end
                if id and isWanted then break end
            end
        end
        if exact then break end
    end
    if found or whole then byName[cacheKey] = found or false end
    return found, foundInfo
end

-- Name einer Karte (uiMapID), sonst „#id“.
function Core.MapName(mapID)
    local ok, info = pcall(function() return mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID) end)
    return ok and type(info) == "table" and info.name or ("#" .. tostring(mapID))
end

-- Kennt der Client die Datei? (GetFileIDFromPath liefert nil oder 0 für Unbekanntes.)
function Core.KnownFile(path)
    if not GetFileIDFromPath then return true end
    local fileID = GetFileIDFromPath(path)
    return fileID ~= nil and fileID > 0
end

-- Symbol setzen: Atlas, wenn vorhanden, sonst Datei mit abgeschnittenem Rand.
function Core.SetIcon(texture, atlas, file)
    if atlas and Core.AtlasExists(atlas) then
        texture:SetAtlas(atlas)
    else
        texture:SetTexture(file)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

---------------------------------------------------------------------------
-- Zustand von Spieler und Einheiten (bis Welle 11 eigene Datei UnitState.lua; EC-36)
---------------------------------------------------------------------------

--[[
    Zustand von Spieler und Einheiten für das Klassen-Wissen (ezCombat-Rotation, ezBuff, ezMacro, ezHeal):
    kleine Abfragen, die sonst jedes Modul selbst nachbaute. Jede Antwort ist wahr, falsch oder unbekannt (nil);
    gesperrte Werte werden nie verglichen (zuerst Core.IsSecret), unbekannt heißt für den Aufrufer: nichts verlangen.

      Core.AurasLocked()              → true/false/nil   sperrt das Spiel gerade Auren? (C_Secrets.ShouldAurasBeSecret)
      Core.SpellAuraLocked(id)        → true/false/nil   kann die Aura dieses Zaubers gesperrt sein? (GetSpellAuraSecrecy)
      Core.SpellCastLocked(unit, id)  → true/false/nil   ist dieser Zauber der Einheit gesperrt? (ShouldUnitSpellCastBeSecret)
          Nur zusätzliche Zeichen für „unbekannt“: „nicht gesperrt“ ersetzt nie das Lesen (Core.Auras.Scan zählt
          gesperrte und unlesbare Auren selbst). Ohne C_Secrets: nil.
      Core.InGroup()                  → bool             in einer Gruppe oder einem Schlachtzug
      Core.InInstance()               → drin, art        drin: true/false/nil (unbekannt); art: "party" | "raid" | "pvp" |
                                        "arena" | "scenario" | "none" oder nil (IsInInstance; W-14, vorher acht
                                        Fassungen in den Modulen)
      Core.UnitPresent(unit)          → true/false/nil   gibt es die Einheit? (UnitExists; nil = gesperrt oder unbekannt)
      Core.UnitIs(unit, andere)       → true/false/nil   ohne andere: gibt es die Einheit und ist sie ein Spieler?
                                        mit andere ("player", "target" …): sind beide dieselbe Einheit? (UnitIsUnit)
      Core.RestrictionActive(art)     → true/false/nil   gilt die Addon-Sperre des Spiels? art: "combat" | "encounter" |
                                        "challenge" | "pvp" | "map" | "chat" oder Blizzards Nummer; ohne art: irgendeine
      Core.RestrictionState(art)      → "inactive" | "activating" | "active" | nil
      Core.PvPPossible()              → true, grund | false   ist Kampf mit der anderen Fraktion möglich? grund:
                                        "instance" (Schlachtfeld, Arena), "match" (Sperre „PvP-Match“), "flag" (für
                                        PvP markiert, auch Kriegsmodus), "ffa" (jeder gegen jeden), "unknown" (Antwort
                                        gesperrt oder Fehler – im Zweifel möglich); Restschaden: im PvP ganz aus
      Core.OnRestrictionChanged(fn, owner)   fn(art, aktiv, zustand), sobald eine Sperre beginnt oder endet
                                        (Nachricht RESTRICTION_CHANGED) – „lesbar ab wann“ hängt an der Sperre, nicht
                                        an PLAYER_REGEN_ENABLED
      Core.PlayerMoving()             → bool             über PLAYER_STARTED_MOVING/PLAYER_STOPPED_MOVING (GetUnitSpeed ist sperrbar)
      Core.UnitRank(unit)             → "normal" | "elite" | "rare" | "rareelite" | "worldboss" | "trivial" | "minus", nil
      Core.UnitCreatureKey(unit)      → sprachfester Schlüssel ("beast", "demon", "undead" …), nil = unbekannt
      Core.WeaponKind(hand)           → Art, istWaffe    hand: "main" (Standard), "off", "ranged" oder Platznummer;
                                        Art: "dagger", "sword", "mace", "axe", "fist", "staff", "polearm", "bow", "gun",
                                        "crossbow", "wand", "thrown", "fishing", "shield", "held" (in der Nebenhand
                                        gehalten), "other"; nil bei leerem Platz
      Core.ItemWeaponKind(item)       → Art, istWaffe, zweihändig   dieselbe Art für einen Gegenstand (Link oder ID),
                                        nicht für eine Hand – etwa für den Vergleich im Tooltip (ezGear,
                                        Paket ezgear/talent-empfehlung); nil, wenn der Client ihn (noch) nicht kennt
                                        oder er kein Gegenstand der Hände ist (Brustteil, Ring …)
]]

---------------------------------------------------------------------------
-- Sperren (C_Secrets, falls vorhanden)
---------------------------------------------------------------------------

-- Geschützter Aufruf einer C_Secrets-Funktion: ok, Wert (gesperrte Antwort oder Fehler → false).
local function Secrets(name, ...)
    local api = rawget(_G, "C_Secrets")
    local fn = type(api) == "table" and api[name] or nil
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    if not ok or Core.IsSecret(value) then return false end
    return true, value
end

local function AsBool(ok, value)
    if ok and type(value) == "boolean" then return value end
    return nil
end

function Core.AurasLocked()
    return AsBool(Secrets("ShouldAurasBeSecret"))
end

-- Die Rückgabe von GetSpellAuraSecrecy ist nicht belegt [V]: Wahrheitswert wie er ist; Zahl 0 = nie gesperrt,
-- jede andere Zahl = kann gesperrt sein; alles andere unbekannt.
function Core.SpellAuraLocked(id)
    id = Core.Num(id)
    if not id then return nil end
    local ok, value = Secrets("GetSpellAuraSecrecy", id)
    if not ok then return nil end
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    return nil
end

function Core.SpellCastLocked(unit, id)
    id = Core.Num(id)
    if not id or Core.IsSecret(unit) or type(unit) ~= "string" then return nil end
    return AsBool(Secrets("ShouldUnitSpellCastBeSecret", unit, id))
end

---------------------------------------------------------------------------
-- Gruppe und Bewegung
---------------------------------------------------------------------------

function Core.InGroup()
    local inGroup, inRaid = rawget(_G, "IsInGroup"), rawget(_G, "IsInRaid")
    return Core.Plain(Core.Call(inGroup)) == true or Core.Plain(Core.Call(inRaid)) == true
end

-- In einer Instanz? Beide Antworten zuerst über Core.IsSecret; ein gesperrter oder fehlender Wert heißt unbekannt.
function Core.InInstance()
    local fn = rawget(_G, "IsInInstance")
    if type(fn) ~= "function" then return nil, nil end
    local ok, inside, kind = pcall(fn)
    if not ok then return nil, nil end
    kind = Core.Plain(kind)
    if type(kind) ~= "string" or kind == "" then kind = nil end
    return Core.Bool(inside, nil), kind
end

local moving = false
ns.On("PLAYER_STARTED_MOVING", function() moving = true end)
ns.On("PLAYER_STOPPED_MOVING", function() moving = false end)

function Core.PlayerMoving() return moving end

---------------------------------------------------------------------------
-- Einheit: vorhanden, Spieler, dieselbe Einheit (V-184, CB-39: vorher je Modul ein eigener Weg um UnitExists)
---------------------------------------------------------------------------

-- Wahrheitswert einer Einheiten-Abfrage: true/false, nil bei gesperrter Einheit, gesperrter Antwort oder Fehler.
local function UnitFlag(name, unit, other)
    if Core.IsSecret(unit) or type(unit) ~= "string" or unit == "" then return nil end
    local fn = rawget(_G, name)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, unit, other)
    if not ok then return nil end
    return Core.Bool(value, nil)
end

function Core.UnitPresent(unit)
    return UnitFlag("UnitExists", unit)
end

function Core.UnitIs(unit, other)
    if Core.IsSecret(other) then return nil end      -- zuerst prüfen: einen gesperrten Wert nie mit nil vergleichen
    if other ~= nil then
        if type(other) ~= "string" or other == "" then return nil end
        return UnitFlag("UnitIsUnit", unit, other)
    end
    local present = UnitFlag("UnitExists", unit)
    if present ~= true then return present end
    return UnitFlag("UnitIsPlayer", unit)
end

---------------------------------------------------------------------------
-- Addon-Sperre des Spiels (ADDON_RESTRICTION_STATE_CHANGED, C_RestrictedActions) – EINE Stelle (EC-99; vorher hörte
-- ezCombat selbst zu). Blizzards Abfrage antwortet während des Ereignisses immer „nein“ und liefert keinen
-- Anfangszustand: ezCore merkt sich deshalb den Zustand aus dem Ereignis und fragt nur, solange es keinen kennt.
---------------------------------------------------------------------------

-- Enum.AddOnRestrictionType (Combat 0, Encounter 1, ChallengeMode 2, PvPMatch 3, Map 4, Chat 5)
Core.RESTRICTIONS = { "combat", "encounter", "challenge", "pvp", "map", "chat" }
local RESTRICTION_STATES = { [0] = "inactive", [1] = "activating", [2] = "active" }
local restrictionID, restrictionSeen = {}, {}
for index, key in ipairs(Core.RESTRICTIONS) do restrictionID[key] = index - 1 end

local function RestrictionID(kind)
    if Core.IsSecret(kind) then return nil end
    if type(kind) == "string" then return restrictionID[kind] end
    kind = Core.Num(kind)
    if kind and Core.RESTRICTIONS[kind + 1] then return kind end
    return nil
end

function Core.RestrictionState(kind)
    local id = RestrictionID(kind)
    if not id then return nil end
    if restrictionSeen[id] then return restrictionSeen[id] end
    local api = rawget(_G, "C_RestrictedActions")
    if type(api) ~= "table" then return nil end
    local state = Core.Num(Core.Call(api.GetAddOnRestrictionState, id))
    if state and RESTRICTION_STATES[state] then return RESTRICTION_STATES[state] end
    local active = Core.Bool(Core.Call(api.IsAddOnRestrictionActive, id), nil)
    if active == nil then return nil end
    return active and "active" or "inactive"
end

function Core.RestrictionActive(kind)
    if Core.IsSecret(kind) then return nil end       -- zuerst prüfen: einen gesperrten Wert nie mit nil vergleichen
    if kind ~= nil then
        local state = Core.RestrictionState(kind)
        if state == nil then return nil end
        return state == "active"
    end
    local known = false
    for _, key in ipairs(Core.RESTRICTIONS) do
        local state = Core.RestrictionState(key)
        if state == "active" then return true end
        if state ~= nil then known = true end
    end
    if known then return false end
    return nil
end

function Core.OnRestrictionChanged(fn, owner)
    return Core.Listen("RESTRICTION_CHANGED", fn, owner)
end

-- PvP möglich? Entscheidung des Nutzers vom 22.11.2026 zu Restschaden und Weg A („Ganz aus (Empfohlen)“): alles, was
-- nachrechnet oder Daten austauscht, ist aus, sobald Kampf mit der anderen Fraktion möglich ist. Eine gesperrte
-- Antwort oder ein Fehler heißt „möglich“; fehlt eine Abfrage im Client ganz, zählt sie nicht.
local PVP_FLAGS = { { "UnitIsPVP", "flag" }, { "UnitIsPVPFreeForAll", "ffa" } }

function Core.PvPPossible()
    local _, kind = Core.InInstance()
    if kind == "pvp" or kind == "arena" then return true, "instance" end
    local match = Core.RestrictionState("pvp")
    if match == "active" or match == "activating" then return true, "match" end
    for _, flag in ipairs(PVP_FLAGS) do
        local fn = rawget(_G, flag[1])
        if type(fn) == "function" then
            local ok, value = pcall(fn, "player")
            if not ok or Core.IsSecret(value) then return true, "unknown" end
            if value == true or value == 1 then return true, flag[2] end
        end
    end
    return false
end

-- Das Ereignis kennt nicht jeder Client; ezCore meldet es dann nicht an (Core.RegisterEvent).
ns.On("ADDON_RESTRICTION_STATE_CHANGED", function(_, kind, state)
    local id = RestrictionID(kind)
    state = Core.Num(state)
    local text = state and RESTRICTION_STATES[state] or nil
    if not id or not text then return end
    restrictionSeen[id] = text
    Core.Fire("RESTRICTION_CHANGED", Core.RESTRICTIONS[id + 1], text == "active", text)
end)

---------------------------------------------------------------------------
-- Einheit: Einstufung und Kreaturentyp
---------------------------------------------------------------------------

local RANKS = { normal = true, elite = true, rare = true, rareelite = true, worldboss = true, trivial = true, minus = true }

-- UnitClassification ist laut Forever-Quelle nie gesperrt; geprüft wird trotzdem.
function Core.UnitRank(unit)
    if Core.IsSecret(unit) or type(unit) ~= "string" then return nil end
    local rank = Core.Plain(Core.Call(rawget(_G, "UnitClassification"), unit))
    if type(rank) == "string" and RANKS[rank] then return rank end
    return nil
end

-- Typ-Nummern (Blizzards CreatureType, seit Classic unverändert) → Schlüssel.
Core.CREATURE_KEYS = { "beast", "dragonkin", "demon", "elemental", "giant", "undead", "humanoid", "critter", "mechanical",
    "none", "totem", "pet", "gas" }
-- Rückfall über den Namen, wenn der Client keine Nummer liefert (deutsch und englisch).
local CREATURE_NAMES = {
    ["wildtier"] = "beast", ["beast"] = "beast", ["drachkin"] = "dragonkin", ["dragonkin"] = "dragonkin",
    ["dämon"] = "demon", ["demon"] = "demon", ["elementar"] = "elemental", ["elemental"] = "elemental",
    ["riese"] = "giant", ["giant"] = "giant", ["untoter"] = "undead", ["undead"] = "undead",
    ["humanoid"] = "humanoid", ["kleintier"] = "critter", ["tier"] = "critter", ["critter"] = "critter",
    ["mechanisch"] = "mechanical", ["mechanical"] = "mechanical", ["totem"] = "totem",
    ["nicht spezifiziert"] = "none", ["not specified"] = "none", ["haustier"] = "pet", ["non-combat pet"] = "pet",
    ["gaswolke"] = "gas", ["gas cloud"] = "gas",
}

-- UnitCreatureType ist sperrbar: gesperrt oder unbekannt → nil.
function Core.UnitCreatureKey(unit)
    if Core.IsSecret(unit) or type(unit) ~= "string" then return nil end
    local api = rawget(_G, "UnitCreatureType")
    if type(api) ~= "function" then return nil end
    local ok, name, id = pcall(api, unit)
    if not ok then return nil end
    id = Core.Num(id)
    if id and Core.CREATURE_KEYS[id] then return Core.CREATURE_KEYS[id] end
    name = Core.Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    return CREATURE_NAMES[name:lower()]
end

---------------------------------------------------------------------------
-- Waffe in der Hand
---------------------------------------------------------------------------

local HAND_SLOTS = { main = 16, off = 17, ranged = 18 }
-- Plätze der Hände für Module (Paket ezmacro/gifte-waffenzauber: ezMacros Gift- und Waffenzauber-Vorlagen) – eine
-- eigene Tabelle, damit ein Modul, das hineinschreibt, Core.WeaponKind nicht verändert.
Core.HAND_SLOTS = { main = HAND_SLOTS.main, off = HAND_SLOTS.off, ranged = HAND_SLOTS.ranged }
-- Unterarten der Waffen (Blizzards Enum.ItemWeaponSubclass, seit Classic unverändert).
local WEAPON_KINDS = { [0] = "axe", [1] = "axe", [2] = "bow", [3] = "gun", [4] = "mace", [5] = "mace", [6] = "polearm",
    [7] = "sword", [8] = "sword", [10] = "staff", [13] = "fist", [15] = "dagger", [16] = "thrown", [18] = "crossbow",
    [19] = "wand", [20] = "fishing" }
local ARMOR_SHIELD = 6

-- Gegenstand in dieser Hand ("main" | "off" | "ranged" | Platznummer) → itemID | nil, Grund: "empty" (leerer Platz),
-- "unknown" (Hand oder Wert gesperrt, Abfrage fehlt oder wirft). Eine Stelle für Core.WeaponKind und
-- Core.BestItems.FitsHand (Paket ezcore/klinge-wucht); liest die eigene Platztabelle, nicht Core.HAND_SLOTS.
function Core.HandItem(hand)
    if Core.IsSecret(hand) then return nil, "unknown" end
    local slot = HAND_SLOTS[hand or "main"] or Core.Num(hand)
    local api = rawget(_G, "GetInventoryItemID")
    if not slot or type(api) ~= "function" then return nil, "unknown" end
    local ok, raw = pcall(api, "player", slot)
    if not ok or Core.IsSecret(raw) then return nil, "unknown" end
    local item = Core.Num(raw)
    if not item then return nil, "empty" end
    return item
end

-- Gegenstände der Hände, die keine Waffe und kein Schild sind (in der Nebenhand gehalten, Relikt)
local HELD_LOCS = { INVTYPE_HOLDABLE = true, INVTYPE_RELIC = true }

function Core.ItemWeaponKind(item)
    if Core.IsSecret(item) or item == nil then return nil end
    local classID, subClassID, equipLoc = Core.ItemClass(item)
    if not classID then return nil end
    if classID == Core.ITEM_CLASS.Weapon then
        -- die eine Zweihänder-Regel (Core.EquipSlots.IsTwoHand)
        return WEAPON_KINDS[subClassID or -1] or "other", true, Core.EquipSlots.IsTwoHand(equipLoc or item) == true
    end
    if classID == Core.ITEM_CLASS.Armor and subClassID == ARMOR_SHIELD then return "shield", false, false end
    if HELD_LOCS[equipLoc or ""] then return "held", false, false end
    return nil       -- kein Gegenstand der Hände (Brustteil, Ring …)
end

function Core.WeaponKind(hand)
    local item = Core.HandItem(hand)
    if not item then return nil end
    local classID = Core.ItemClass(item)
    if not classID then return nil end
    local kind, isWeapon = Core.ItemWeaponKind(item)
    if not kind then return "held", false end     -- was sonst in einer Hand liegt, gilt wie bisher als gehalten
    return kind, isWeapon
end

-- Nimmt die Waffe dieser Hand eine Verzauberung auf Zeit an (Gift, Wetzstein, Öl, Waffenzauber)? Eine Waffe, keine
-- Angelrute; Schild, Nebenhand-Gegenstand und leerer Platz nicht. Eine Regel für ezBuff (Weapon.HasWeapon) und ezMacro
-- (Gift- und Waffenzauber-Vorlagen; Paket ezmacro/gifte-waffenzauber). → true | false
function Core.WeaponEnchantable(hand)
    local kind, isWeapon = Core.WeaponKind(hand)
    if Core.IsSecret(kind) or Core.IsSecret(isWeapon) then return false end
    return isWeapon == true and kind ~= "fishing"
end

---------------------------------------------------------------------------
-- Gemeinsame Helfer statt Kopien in den Modulen (Gesamtreview 18.11.2026, Paket P19a, Zweig kern/ssot-helfer)
---------------------------------------------------------------------------

--[[
    Core.CopyTable(wert, maxTiefe) → tiefe Kopie (T16-7; vorher fünf Fassungen mit verschiedenem Verhalten: ohne Grenze
      mit Stapelüberlauf bei einem Zyklus, nil ab Tiefe 12, die ORIGINAL-Tabelle ab Tiefe 8 …). Ein festes Verhalten:
      Zyklen und mehrfach genutzte Teiltabellen bleiben erhalten (dieselbe Teiltabelle wird einmal kopiert und mehrfach
      eingehängt, kein Überlauf); was tiefer als maxTiefe liegt (Standard Core.COPY_DEPTH = 32), fällt weg (nil) – nie
      eine geteilte Referenz zum Original. Kein Tabellenwert: unverändert zurück. Schlüssel werden nicht kopiert.
    Core.CopyList(liste) → flache Kopie des Listenteils (1..n); keine Tabelle: leere Liste.
    DB.Copy, Prices.Rules (CopyDeep), ezCombat Own.Copy, ezPanel Profile und die CopyList-Kopien in ezCore leiten
    hierher weiter (Namen bleiben, Leitlinie 8).
]]
Core.COPY_DEPTH = 32
local function CopyInto(value, depth, maxDepth, seen)
    if type(value) ~= "table" then return value end
    if seen[value] then return seen[value] end
    if depth > maxDepth then return nil end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[k] = CopyInto(v, depth + 1, maxDepth, seen) end
    return out
end
function Core.CopyTable(value, maxDepth)
    if type(value) ~= "table" then return value end
    return CopyInto(value, 0, math.floor(Core.Num(maxDepth) or Core.COPY_DEPTH), {})
end

function Core.CopyList(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for i, v in ipairs(list) do out[i] = v end
    return out
end

-- Sofort-Auskunft über einen Gegenstand (T16-16; vorher acht eigene Umhüllungen in ezCore mit je eigenem Rückfall und
-- pcall): C_Item.GetItemInfoInstant, sonst die alte Globale, geschützt. Gesperrter oder fehlender Wert und Fehler: nil.
-- → itemID, itemType, itemSubType, equipLoc, icon, classID, subClassID (wie Blizzard; fragt den Server nicht).
-- api (freiwillig): eine Tabelle mit GetItemInfoInstant statt C_Item (für Prüfungen und die Datenprobe).
function Core.ItemInstant(item, api)
    if Core.IsSecret(item) or item == nil then return nil end
    local fn = type(api) == "table" and api.GetItemInfoInstant or nil
    if type(fn) ~= "function" then
        fn = (C_Item and C_Item.GetItemInfoInstant) or rawget(_G, "GetItemInfoInstant")
    end
    if type(fn) ~= "function" then return nil end
    local ok, id, itemType, subType, equipLoc, icon, classID, subClassID = pcall(fn, item)
    if not ok or Core.IsSecret(id) then return nil end
    return id, itemType, subType, equipLoc, icon, classID, subClassID
end

-- Blizzard-Ton (T16-NM4; vorher sechs verschiedene Absicherungen, mehrere Aufrufe ganz ohne): key = Name in SOUNDKIT
-- („IG_MAINMENU_OPTION_CHECKBOX_ON“) oder eine Ton-ID, channel freiwillig („Master“, „SFX“ …). Kennt der Client den
-- Namen nicht oder wirft PlaySound, bleibt es still. → true, wenn gespielt.
function Core.PlaySound(key, channel)
    local play = rawget(_G, "PlaySound")
    if type(play) ~= "function" or Core.IsSecret(key) then return false end
    local id = key
    if type(key) == "string" then
        local kit = rawget(_G, "SOUNDKIT")
        id = type(kit) == "table" and kit[key] or nil
    end
    if type(id) ~= "number" then return false end
    if channel ~= nil then return (pcall(play, id, channel)) end
    return (pcall(play, id))
end

-- Ersatzsymbol bei fehlendem Bild (T16-NM6, T16-8; vorher rund 20 Kopien als Pfad, Datei-ID 134400 oder lokale
-- Konstante): Blizzards Fragezeichen. Core.Menu.ICON_FALLBACK ist ein Verweis darauf; Makros nehmen die Datei-ID
-- Core.Macro.DEFAULT_ICON (dasselbe Bild).
Core.ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"
Core.ICON_FALLBACK_ID = 134400

-- Ist icon dieses Ersatzsymbol – als Datei-ID, als Pfad (Groß-/Kleinschreibung und Schrägstrich egal) oder als bloßer
-- Name, wie ältere Fassungen von ezHeal es schickten? Für Listen, die statt des Fragezeichens ein eigenes Bild zeigen
-- (ezMacro HealMacros; Gegenprüfung P19a zu T16-8 – vorher eine eigene Kopie des Namens dort).
function Core.IsFallbackIcon(icon)
    if Core.IsSecret(icon) then return false end
    if type(icon) == "number" then return icon == Core.ICON_FALLBACK_ID end
    if type(icon) ~= "string" then return false end
    local name = icon:lower():gsub("/", "\\")
    return name == Core.ICON_FALLBACK:lower() or name == "inv_misc_questionmark"
        or name == tostring(Core.ICON_FALLBACK_ID)
end

--[[
    Einmal-Umstellungen (T4-7, T4-5; vorher fünf fast gleiche Opt-in-Umstellungen von Hand in ezBag, ezChat, ezMap und
    ezQuest, und ezMail las ezCoreDB.migrated selbst):
      Core.MigrateOnce(store, flag, fn) → nil, wenn store[flag] schon gesetzt ist; sonst store[flag] = true und das
        Ergebnis von fn() (geschützt; ein Fehler landet in der Fehlerliste und zählt als erledigt). store: die Tabelle,
        in der der Merker liegt (oben in der DB des Moduls oder dessen db.migrated – die Lage bleibt je Modul, wie sie
        war, damit kein Merker verloren geht).
      Core.OptInOnce(db, flag, keys, store) → Liste der umgestellten Schlüssel oder nil. Ein Ablauf, der früher ab Werk
        an war und jetzt aus ist: wer den alten Standard (true) gespeichert hat, bekommt EINMAL false (FillDefaults füllt
        nur Fehlendes). keys = { einstellung = "MerkerWas" } oder in fester Reihenfolge { { einstellung, "MerkerWas" } … }:
        der alte Wert wird als store[MerkerWas] = true gemerkt (für den Hinweis „beim Update ausgeschaltet“). store
        Standard db; „migrated“ = db.migrated (wird angelegt).
        Wer danach selbst einschaltet, behält es (der Merker flag verhindert ein zweites Umstellen).
      Core.Migrated(key) → true, wenn ezCore die einmalige Übernahme key (ezCoreDB.migrated[key]) erledigt hat – die
        Auskunft für Module statt eines Blicks in ezCores Speicher (Form von ezCoreDB.migrated darf sich ändern).
]]
function Core.MigrateOnce(store, flag, fn)
    if type(store) ~= "table" or flag == nil or store[flag] then return nil end
    store[flag] = true
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn)
    if not ok then
        if Core.Error then Core.Error(Core.name or "ezCore", result, "MigrateOnce " .. tostring(flag)) end
        return nil
    end
    return result
end

function Core.OptInOnce(db, flag, keys, store)
    if type(db) ~= "table" or type(db.settings) ~= "table" or type(keys) ~= "table" then return nil end
    if store == "migrated" then
        if type(db.migrated) ~= "table" then db.migrated = {} end
        store = db.migrated
    elseif type(store) ~= "table" then
        store = db
    end
    -- keys als Liste { { einstellung, "MerkerWas" } … } behält die Reihenfolge, als Tabelle { einstellung = "MerkerWas" }
    -- gilt die Namensfolge
    local pairsList = {}
    if type(keys[1]) == "table" then
        for _, pair in ipairs(keys) do pairsList[#pairsList + 1] = { pair[1], pair[2] } end
    else
        for key, was in pairs(keys) do pairsList[#pairsList + 1] = { key, was } end
        table.sort(pairsList, function(a, b) return tostring(a[1]) < tostring(b[1]) end)
    end
    return Core.MigrateOnce(store, flag, function()
        local switched
        for _, pair in ipairs(pairsList) do
            local key, was = pair[1], pair[2]
            if db.settings[key] == true then
                db.settings[key] = false
                if type(was) == "string" then store[was] = true end
                switched = switched or {}
                switched[#switched + 1] = key
            end
        end
        return switched
    end)
end

function Core.Migrated(key)
    local db = Core.db
    local done = type(db) == "table" and db.migrated or nil
    return type(done) == "table" and key ~= nil and done[key] ~= nil and done[key] ~= false or false
end

-- Rolle des Spielers: "TANK" | "HEALER" | "DAMAGER" | nil (unbekannt), dazu die Quelle ("group" | "talents" | "leveling").
-- Spieltest 20.11.2026 (ezCombat, Kampfanzeige am Rahmen): „angezeigt wird am rahmen nur, was den spieler betrifft“.
-- Reihenfolge:
--   1. Rolle in der Gruppe (UnitGroupRolesAssigned("player"), „NONE“ zählt nicht). Laut Datenkatalog kann das Spiel
--      sie sperren (docs/datenkatalog-client.md, Gruppe) – dann gilt die zuletzt offen gelesene Gruppenrolle, solange
--      der Spieler in einer Gruppe ist (Review 20.11.2026: sonst spränge ein Heiler bei Kampfbeginn auf Schaden).
--   2. Rolle des Talentbaums mit den meisten bestätigten Punkten (Core.Talents.MainTree, Talents.Role; Auftrag des Nutzers
--      vom 24.11.2026: „Ja, umstellen“). Bis dahin die der Spezialisierung: Forever führt je Klasse nur eine, Rolle Schaden
--      (Client-Tabelle ChrSpecialization) – ein Heiler ohne Gruppenrolle hieß Schaden.
--   3. Noch keine Talentpunkte: Schaden (wie ezGears Leveling-Rolle). Talente (noch) nicht lesbar: unbekannt.
-- Blizzards Abfragen werden nur gelesen, per pcall, jeder Wert zuerst auf geheim geprüft (Leitlinie 6).
Core.ROLES = { TANK = true, HEALER = true, DAMAGER = true }
-- Klassen, die heilen können (Blizzards Klassen-Kennungen) – für „Rolle unbekannt“: wer nicht heilen kann, heilt nicht.
Core.HEAL_CLASSES = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true, MONK = true, EVOKER = true }
local lastGroupRole = nil
local function KnownRole(role)
    if Core.IsSecret(role) or type(role) ~= "string" then return nil end
    return Core.ROLES[role] and role or nil
end
local function Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end
local function InGroup()
    local ok, grouped = Call(rawget(_G, "IsInGroup"))
    return ok and not Core.IsSecret(grouped) and grouped == true
end
function Core.PlayerRole()
    local ok, role = Call(rawget(_G, "UnitGroupRolesAssigned"), "player")
    if ok and Core.IsSecret(role) then
        if lastGroupRole and InGroup() then return lastGroupRole, "group" end
    else
        role = ok and KnownRole(role) or nil
        if ok then lastGroupRole = role end
        if role then return role, "group" end
    end
    local tree, known = Core.Talents.MainTree()
    if not known then return nil end
    if not tree then return "DAMAGER", "leveling" end
    role = KnownRole((Core.Talents.Role(Core.PlayerClass(), tree)))
    if role then return role, "talents" end
    return nil
end

-- Rolle eines Gruppenmitglieds (26.11.2026, für ezBuffs Segen nach Rolle): für den Spieler wie Core.PlayerRole, sonst
-- die Rolle in der Gruppe (UnitGroupRolesAssigned; „NONE“, gesperrt oder unbekannt → nil). Talente anderer Spieler liest
-- ezCore nicht (Betrachten kostet je Spieler eine Anfrage). → "TANK" | "HEALER" | "DAMAGER" | nil, Quelle
function Core.UnitRole(unit)
    if Core.IsSecret(unit) or type(unit) ~= "string" then return nil end
    local okSelf, isSelf = Call(rawget(_G, "UnitIsUnit"), unit, "player")
    if unit == "player" or (okSelf and not Core.IsSecret(isSelf) and isSelf == true) then return Core.PlayerRole() end
    local ok, role = Call(rawget(_G, "UnitGroupRolesAssigned"), unit)
    role = ok and KnownRole(role) or nil
    if role then return role, "group" end
    return nil
end

-- Kann der Spieler heilen (Klasse)? → true | false | nil (Klasse unbekannt)
function Core.PlayerCanHeal()
    local ok, _, class = Call(rawget(_G, "UnitClass"), "player")
    if not ok or Core.IsSecret(class) or type(class) ~= "string" then return nil end
    return Core.HEAL_CLASSES[class] == true
end

--[[
    Lange Arbeit in Scheiben (24.11.2026, „Beitrag vorbereiten“):
      Core.Sliced(fn, opts) → Auftrag mit Cancel(), Done()
        fn(tick) läuft als Koroutine; tick() gibt nach opts.ms Millisekunden je Bild ab (Standard 5; ohne Uhr nach 2000
        Aufrufen), tick(true) sofort. fn gibt das Ergebnis zurück, opts.onDone(ergebnis) bekommt es.
        Im Kampf pausiert der Auftrag und läuft danach weiter. Fehler: Fehlerliste (opts.owner, opts.where), kein onDone,
        dafür opts.onError().
]]
function Core.Sliced(fn, opts)
    opts = type(opts) == "table" and opts or {}
    local clock = rawget(_G, "debugprofilestop")
    if type(clock) ~= "function" then clock = nil end
    local budget, count, start = Core.Num(opts.ms) or 5, 0, 0
    local job, done, cancelled = {}, false, false
    local function tick(now)
        count = count + 1
        if not now then
            if clock then
                if count % 16 ~= 0 or clock() - start < budget then return end
            elseif count < 2000 then
                return
            end
        end
        count = 0
        coroutine.yield()
    end
    local co = coroutine.create(function() return fn(tick) end)
    local function Step()
        if done or cancelled then return end
        if Core.InCombat() then
            Core.AfterCombat(Step, job, opts.owner)
            return
        end
        start = clock and clock() or 0
        local ok, result = coroutine.resume(co)
        if not ok then
            done = true
            Core.Error(opts.owner or Core.name, result, opts.where or "Sliced")
            if type(opts.onError) == "function" then Core.Try(opts.owner, opts.where or "Sliced", opts.onError) end
        elseif coroutine.status(co) == "dead" then
            done = true
            if type(opts.onDone) == "function" then Core.Try(opts.owner, opts.where or "Sliced", opts.onDone, result) end
        else
            C_Timer.After(0, Step)
        end
    end
    function job.Cancel() cancelled = true end
    function job.Done() return done or cancelled end
    Step()
    return job
end
