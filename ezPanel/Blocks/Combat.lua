local _, ns = ...
local L = ns.L

--[[
    Kampf (CB-17): der letzte Kampf dieses Charakters aus ezCores Verlauf (Art „combat“). Den Eintrag schreibt
    ezCombat nach jedem Kampf (Zusammenfassung aus Blizzards C_DamageMeter, MeterSummary.lua): dur (Dauer in
    Sekunden), dmg, dps, dmgRank (Platz in der Gruppe), heal, hps, healRank, size (Gruppengröße), zone. Was das Spiel
    sperrt, fehlt im Eintrag – der Baustein zeigt nur, was da ist, und rechnet nichts nach.
    Leiste: Schaden oder Heilung pro Sekunde (auf Wunsch die Dauer), dazu der eigene Platz in der Gruppe.
    Tooltip: Dauer, Schaden, Heilung, Platz, Ort und Zeitpunkt, darunter die früheren Kämpfe.
    Linksklick (und Eintrag im Menü): Blizzards eigene Schadensanzeige ein- und ausschalten – über dieselbe Einstellung
    des Spiels wie ezCombats Schalter (CVar damageMeterEnabled; ezCore.SetCVar fängt gesperrte Fälle ab).
    Den Verlauf schreibt ezCombat nur mit seiner Einstellung „Zusammenfassung nach dem Kampf“ (ab Werk aus). Ohne Kampf
    im Verlauf nennt der Tooltip diesen Schalter, und das Menü hat „Einstellungen von ezCombat“ (Leitlinie 3) – aber
    nur, wenn der Schalter nicht sicher an ist: ezCombats Schnittstelle sagt es (SummaryEnabled, CB-17; Welle 23). Ist
    er an, sagt der Leertext, dass der nächste Kampf hier erscheint; kennt ezCombat die Abfrage nicht (ältere
    Fassung), nennt er den Schalter wie bisher.
    Rücksicht (Leitlinie 9): Zeigt ein anderes Addon Schaden und Heilung (Details – ezCore.WhoHandles("damageMeter")),
    schaltet der Baustein Blizzards Anzeige nicht und nennt das Addon im Tooltip; die Werte aus dem Verlauf bleiben.
    Verlauf über Wochen (V4, Bericht Welle 20, docs/archiv/eroerterung-datenbank.md; freigegeben „zuerst V1–V5“): Unter den
    früheren Kämpfen steht je Woche (ab Montag) das Mittel von Schaden und Heilung pro Sekunde aus gleichartigen
    Kämpfen – allein oder in der Gruppe wie der letzte Kampf (oder fest gewählt), ab einer Mindestdauer, damit kurze
    Scharmützel die Werte nicht verzerren –, dazu der Trend der neuesten gegen die vorige Woche (Pfeil, Prozent) und
    die Quelle („aus deinen Kämpfen: n“). Eine Woche zählt erst ab TREND_PER_WEEK Kämpfen. Die Rechnung ist
    block.Trend (nur ezPanel nutzt sie; braucht sie ein zweites Modul, gehört sie nach ezCore). Gesperrte Werte
    (Leitlinie 6) fallen über ns.Num heraus, bevor verglichen oder gerechnet wird.
    „Als Text kopieren“ (V5): Menüeintrag „Kämpfe als Text kopieren …“ – alle Kämpfe dieses Charakters, älteste zuerst,
    als Tabelle über ezCores Kopierfeld (ns.CopyAsText » Core.CopyAsText, Welle 23d). Fehlt der Dienst, fehlt der
    Eintrag. Namen anderer Spieler stehen nicht im Eintrag, also gibt es kein Häkchen „Namen mitnehmen“ (Frage E6).
]]

local Core = ezCore

local KIND = "combat"
local CVAR = "damageMeterEnabled"
local EARLIER = 4        -- frühere Kämpfe im Tooltip
local TREND_WEEKS = 4    -- Wochen im Tooltip (neueste zuerst)
local TREND_PER_WEEK = 3 -- Mindestzahl gleichartiger Kämpfe, damit eine Woche zählt
local TREND_MINS = { 10, 20, 30, 60 }   -- Auswahl der Mindestdauer in Sekunden
local ALL_FIGHTS = 500   -- so viele Kämpfe hält ezCore höchstens (History.MAX.combat)
local ARROW_UP = "|TInterface\\Buttons\\Arrow-Up-Up:0|t"
local ARROW_DOWN = "|TInterface\\Buttons\\Arrow-Down-Up:0|t"

local block = ns.RegisterBlock({
    id = "combat",
    command = "kampfwerte",
    name = L.COMBAT_NAME,
    label = L.COMBAT_LABEL,
    icon = "Interface\\Icons\\Ability_DualWield",
    fallbackIcon = "Interface\\Icons\\INV_Sword_04",
    events = { "PLAYER_ENTERING_WORLD" },
    colorable = true,
    defaults = {
        enabled = false, zone = "right", order = 45,
        show = "auto",          -- auto | dps | hps | duration
        rank = true,            -- Platz in der Gruppe auf der Leiste
        trend = true,           -- Verlauf über Wochen im Tooltip (V4)
        trendKind = "auto",     -- auto (wie der letzte Kampf) | solo | group
        trendMin = 20,          -- Mindestdauer eines Kampfs für den Verlauf (Sekunden)
    },
})

---------------------------------------------------------------------------
-- Daten (ezCore.History, Art „combat“)
---------------------------------------------------------------------------

-- Die letzten n Kämpfe dieses Charakters, neueste zuerst (Kopien liefert ezCore nicht – nur lesen).
local function Fights(n)
    local history = Core.History
    if type(history) ~= "table" or type(history.List) ~= "function" then return {} end
    local ok, list = pcall(history.List, KIND, { char = ns.charKey, limit = n })
    return ok and type(list) == "table" and list or {}
end
block.Fights = Fights

-- Schreibt ezCombat Kämpfe? (Ohne ezCombat bleibt der Verlauf leer – der Tooltip sagt das.)
local function Recorder()
    return ns.IsLoaded("ezCombat")
end

-- Schreibt ezCombat nach dem Kampf einen Eintrag („Zusammenfassung nach dem Kampf“ an)? true/false laut ezCombats
-- Schnittstelle (ezCore.API("ezCombat").SummaryEnabled); nil, wenn ezCombat nicht läuft oder die Abfrage nicht kennt.
local function SummaryOn()
    local api = Core.API("ezCombat")
    if type(api) ~= "table" or type(api.SummaryEnabled) ~= "function" then return nil end
    local ok, on = pcall(api.SummaryEnabled)
    if not ok or ns.IsSecret(on) then return nil end
    return on == true
end
block.SummaryOn = SummaryOn

-- Leertext ohne Kampf im Verlauf: ohne ezCombat dessen Erklärung; Schalter an: „der nächste Kampf erscheint hier“;
-- sonst (aus oder unbekannt) der Weg zum Schalter.
local function EmptyText()
    if not Recorder() then return L.COMBAT_NO_EZCOMBAT end
    if SummaryOn() == true then return L.COMBAT_NONE_READY end
    return L.COMBAT_NONE
end
block.EmptyText = EmptyText

-- Zeigt ein anderes Addon Schaden und Heilung (Details)? Name oder nil (Erkennung in ezCore).
local function OtherMeter()
    return ns.OtherFor("damageMeter")
end

---------------------------------------------------------------------------
-- Blizzards Schadensanzeige
---------------------------------------------------------------------------

-- true/false: an oder aus; nil: der Client kennt die Einstellung nicht (keine Schadensanzeige von Blizzard).
local function MeterOn()
    local value = Core.CVar(CVAR)
    if ns.IsSecret(value) or value == nil then return nil end
    return value == "1" or value == 1 or value == true
end
block.MeterOn = MeterOn

local function ToggleMeter()
    local other = OtherMeter()
    if other then return ns.Print(L.COMBAT_OTHER:format(other)) end
    local on = MeterOn()
    if on == nil then return ns.Print(L.COMBAT_METER_MISSING) end
    -- Im Kampf nicht (Core.SwitchCVar, T1-9 Gesamtreview 18.11.2026): Hinweis statt Umschalten.
    local ok, why = Core.SwitchCVar(CVAR, on and "0" or "1")
    -- Im Kampf ezCores gemeinsamer Satz über Core.CombatNotice (Gesamtreview 18.11.2026, Nachlauf P19a – vorher der
    -- fertige Satz L.CVAR_COMBAT, der nur noch für diesen Baustein in ezCore stand)
    if not ok and why == "combat" then return Core.CombatNotice(ns, Core.L.CVAR_WHAT) end
    if not ok then return ns.Print(L.COMBAT_METER_FAILED) end
    ns.Print(on and L.COMBAT_METER_OFF or L.COMBAT_METER_ON)
end
block.ToggleMeter = ToggleMeter

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local function Value(e, field) return ns.Num(e and e[field]) end

-- „2.“ bzw. nil – Platz nur in einer Gruppe (size > 1).
local function RankShort(rank, size)
    if not rank or not size or size < 2 then return nil end
    return L.COMBAT_RANK_SHORT:format(rank)
end

-- Was auf der Leiste steht: „dps“ oder „hps“ (auto: was du mehr gemacht hast), sonst die Dauer.
local function Pick(e, show)
    local dps, hps = Value(e, "dps"), Value(e, "hps")
    if show == "dps" and dps then return "dps" end
    if show == "hps" and hps then return "hps" end
    if show == "duration" then return "duration" end
    if dps and hps then return hps > dps and "hps" or "dps" end
    if dps then return "dps" end
    if hps then return "hps" end
    return "duration"
end

function block:GetText()
    local e = Fights(1)[1]
    if not e then return ns.Grey(L.COMBAT_NONE_SHORT) end
    local cfg = self.cfg
    local pick = Pick(e, cfg.show)
    local text, rank
    if pick == "dps" then
        text = L.COMBAT_DPS_SHORT:format(ns.Short(Value(e, "dps")))
        rank = RankShort(Value(e, "dmgRank"), Value(e, "size"))
    elseif pick == "hps" then
        text = L.COMBAT_HPS_SHORT:format(ns.Short(Value(e, "hps")))
        rank = RankShort(Value(e, "healRank"), Value(e, "size"))
    else
        local dur = Value(e, "dur")
        text = dur and ns.Duration(dur, true) or "?"
    end
    if cfg.rank and rank then text = text .. " " .. ns.Grey(rank) end
    return text
end

-- „1.234 (56 pro Sekunde)“ und Platz in einer Zeile.
local function AddPart(tooltip, title, total, rate, rank, size)
    if not total and not rate then return end
    local text = total and ns.Number(total) or "?"
    if rate then text = L.COMBAT_PER_SECOND:format(text, ns.Number(math.floor(rate + 0.5))) end
    if rank and size and size > 1 then text = text .. "  " .. ns.Grey(L.COMBAT_RANK:format(rank, size)) end
    ns.TipDoubleLine(tooltip, title, text, "normal", "highlight")
end

---------------------------------------------------------------------------
-- Verlauf über Wochen (V4)
---------------------------------------------------------------------------

-- Alle Kämpfe dieses Charakters, die ezCore hält (neueste zuerst).
local function AllFights()
    local history = Core.History
    local max = type(history) == "table" and type(history.MAX) == "table" and ns.Num(history.MAX[KIND])
    return Fights(max or ALL_FIGHTS)
end

-- "group" ab zwei Mitspielern (size > 1), sonst "solo" – auch ohne Angabe.
local function FightKind(e)
    local size = Value(e, "size")
    return size and size > 1 and "group" or "solo"
end
block.FightKind = FightKind

-- Montag 0:00 Uhr (Ortszeit) der Woche, in der t liegt.
local function WeekStart(t)
    local d = date("*t", t)
    local back = (d.wday + 5) % 7          -- Tage seit Montag (wday: 1 = Sonntag)
    return time({ year = d.year, month = d.month, day = d.day - back, hour = 0, min = 0, sec = 0 })
end
block.WeekStart = WeekStart

--[[
    block.Trend(kämpfe, opts) → ergebnis | nil, "few", ergebnis
        kämpfe: Einträge der Art „combat“ (Reihenfolge egal)
        opts = { kind = "solo" | "group" | nil (alle), minDur = Sekunden (20), perWeek = Mindestzahl je Woche (3) }
        ergebnis = { kind, minDur, perWeek, n = gleichartige Kämpfe,
                     weeks = { { start, n, dps, hps } … } neueste zuerst; dps/hps = Mittel der Woche oder nil (zu wenige),
                     dps = { to, from, change (Prozent), toWeek, fromWeek } | nil, hps = … }
        Trend: die neueste Woche mit Mittel gegen die nächstältere mit Mittel; ohne zwei solche Wochen „few“.
        Gesperrte Einträge und Werte (Leitlinie 6) zählen nicht – ns.Num prüft vor jedem Vergleich.
]]
local function Trend(list, opts)
    opts = type(opts) == "table" and opts or {}
    local minDur = ns.Num(opts.minDur) or 20
    local perWeek = ns.Num(opts.perWeek) or TREND_PER_WEEK
    local kind = opts.kind
    local buckets, weeks, n = {}, {}, 0
    for _, e in ipairs(type(list) == "table" and list or {}) do
        if type(e) == "table" and not ns.IsSecret(e) then
            local t, dur = Value(e, "t"), Value(e, "dur")
            local dps, hps = Value(e, "dps"), Value(e, "hps")
            if t and dur and dur >= minDur and (dps or hps) and (not kind or FightKind(e) == kind) then
                local start = WeekStart(t)
                local b = buckets[start]
                if not b then
                    b = { start = start, n = 0, dpsSum = 0, dpsN = 0, hpsSum = 0, hpsN = 0 }
                    buckets[start] = b
                    weeks[#weeks + 1] = b
                end
                b.n, n = b.n + 1, n + 1
                if dps then b.dpsSum, b.dpsN = b.dpsSum + dps, b.dpsN + 1 end
                if hps then b.hpsSum, b.hpsN = b.hpsSum + hps, b.hpsN + 1 end
            end
        end
    end
    table.sort(weeks, function(a, b) return a.start > b.start end)
    local out = { kind = kind, minDur = minDur, perWeek = perWeek, n = n, weeks = {} }
    for _, b in ipairs(weeks) do
        local dps = b.dpsN >= perWeek and b.dpsSum / b.dpsN or nil
        local hps = b.hpsN >= perWeek and b.hpsSum / b.hpsN or nil
        if dps or hps then out.weeks[#out.weeks + 1] = { start = b.start, n = b.n, dps = dps, hps = hps } end
    end
    for _, field in ipairs({ "dps", "hps" }) do
        local to, from
        for _, w in ipairs(out.weeks) do
            if w[field] then
                if not to then to = w else from = w break end
            end
        end
        if to and from and from[field] > 0 then
            out[field] = { to = to[field], from = from[field], change = (to[field] - from[field]) / from[field] * 100,
                toWeek = to.start, fromWeek = from.start }
        end
    end
    if not out.dps and not out.hps then return nil, "few", out end
    return out
end
block.Trend = Trend

-- Welche Kämpfe der Verlauf vergleicht: fest gewählt oder wie der letzte Kampf.
local function TrendKind(cfg, last)
    if cfg.trendKind == "solo" or cfg.trendKind == "group" then return cfg.trendKind end
    return FightKind(last)
end

-- „+12 %“ grün mit Pfeil nach oben, „-5 %“ rot mit Pfeil nach unten, unter einem halben Prozent „gleich“.
local function ChangeText(change)
    local r = change >= 0 and math.floor(change + 0.5) or -math.floor(-change + 0.5)
    if r == 0 then return ns.Grey(L.COMBAT_TREND_SAME) end
    if r > 0 then return ARROW_UP .. " " .. ns.GREEN .. "+" .. ns.Percent(r) .. "|r" end
    return ARROW_DOWN .. " " .. ns.RED .. "-" .. ns.Percent(-r) .. "|r"
end
block.ChangeText = ChangeText

local function AddTrend(tooltip, cfg, last)
    local kind = TrendKind(cfg, last)
    local minDur = ns.Num(cfg.trendMin) or 20
    local trend, _, few = Trend(AllFights(), { kind = kind, minDur = minDur })
    tooltip:AddLine(" ")
    ns.TipLine(tooltip, L.COMBAT_TREND:format(kind == "group" and L.COMBAT_TREND_GROUP or L.COMBAT_TREND_SOLO,
        Core.Seconds(minDur)), "normal")
    if not trend then
        ns.TipLine(tooltip, L.COMBAT_TREND_FEW:format(few and few.n or 0, TREND_PER_WEEK), "hint", true)
        return
    end
    for i = 1, math.min(TREND_WEEKS, #trend.weeks) do
        local w = trend.weeks[i]
        local parts = {}
        if w.dps then parts[#parts + 1] = L.COMBAT_DPS_SHORT:format(ns.Short(w.dps)) end
        if w.hps then parts[#parts + 1] = L.COMBAT_HPS_SHORT:format(ns.Short(w.hps)) end
        ns.TipDoubleLine(tooltip, "  " .. L.COMBAT_TREND_WEEK:format(date(Core.L.DATE_DAY, w.start)), table.concat(parts, ", ") .. " " .. ns.Grey(("(%d)"):format(w.n)), "highlight", "highlight")
    end
    if trend.dps then ns.TipDoubleLine(tooltip, L.COMBAT_TREND_DPS, ChangeText(trend.dps.change), "normal", "highlight") end
    if trend.hps then ns.TipDoubleLine(tooltip, L.COMBAT_TREND_HPS, ChangeText(trend.hps.change), "normal", "highlight") end
    -- Quelle (Leitlinie 11)
    ns.TipLine(tooltip, L.COMBAT_TREND_SOURCE:format(trend.n, TREND_PER_WEEK), "hint", true)
end

---------------------------------------------------------------------------
-- Als Text kopieren (V5)
---------------------------------------------------------------------------

-- Spalten der Tabelle; Namen anderer Spieler enthält ein Kampf nicht (keine Spalte mit personal).
local COPY_COLUMNS = {
    { key = "t", title = L.COPY_COL_TIME, format = function(t) return Core.DateText(t, "long") end },
    { key = "zone", title = L.COMBAT_ZONE },
    { key = "dur", title = L.COMBAT_COPY_DURATION },
    { key = "size", title = L.COMBAT_COPY_SIZE },
    { key = "dmg", title = L.COMBAT_DAMAGE },
    { key = "dps", title = L.COMBAT_COPY_DPS },
    { key = "dmgRank", title = L.COMBAT_COPY_DMG_RANK },
    { key = "heal", title = L.COMBAT_HEALING },
    { key = "hps", title = L.COMBAT_COPY_HPS },
    { key = "healRank", title = L.COMBAT_COPY_HEAL_RANK },
}
block.COPY_COLUMNS = COPY_COLUMNS

-- Alle Kämpfe dieses Charakters als Tabelle, älteste zuerst (für eine Tabellenkalkulation).
local function CopyFights()
    local list, rows = AllFights(), {}
    for i = #list, 1, -1 do rows[#rows + 1] = list[i] end
    return ns.CopyAsText({ title = L.COMBAT_COPY_TITLE, columns = COPY_COLUMNS, rows = rows })
end
block.CopyFights = CopyFights

-- Kurzfassung eines früheren Kampfs: „vor 5 Min. – 1,2k DPS, 0:42“.
local function Brief(e)
    local parts = {}
    local dps, hps, dur = Value(e, "dps"), Value(e, "hps"), Value(e, "dur")
    if dps then parts[#parts + 1] = L.COMBAT_DPS_SHORT:format(ns.Short(dps)) end
    if hps then parts[#parts + 1] = L.COMBAT_HPS_SHORT:format(ns.Short(hps)) end
    if dur then parts[#parts + 1] = ns.Duration(dur, true) end
    return #parts > 0 and table.concat(parts, ", ") or "?"
end

function block:OnTooltip(tooltip)
    local list = Fights(EARLIER + 1)
    local e = list[1]
    if not e then
        -- Leertext (PANEL-17): woher die Kämpfe kommen und warum hier noch keiner steht
        ns.TipLine(tooltip, EmptyText(), "highlight", true)
    else
        ns.TipDoubleLine(tooltip, L.COMBAT_LAST, ns.Grey(ns.Ago(e.t)), "normal", "highlight")
        local dur = Value(e, "dur")
        if dur then ns.TipDoubleLine(tooltip, L.COMBAT_DURATION, ns.Duration(dur, true), "normal", "highlight") end
        local size = Value(e, "size")
        AddPart(tooltip, L.COMBAT_DAMAGE, Value(e, "dmg"), Value(e, "dps"), Value(e, "dmgRank"), size)
        AddPart(tooltip, L.COMBAT_HEALING, Value(e, "heal"), Value(e, "hps"), Value(e, "healRank"), size)
        if type(e.zone) == "string" and e.zone ~= "" then
            ns.TipDoubleLine(tooltip, L.COMBAT_ZONE, e.zone, "normal", "highlight")
        end
        if #list > 1 then
            tooltip:AddLine(" ")
            ns.TipLine(tooltip, L.COMBAT_EARLIER, "normal")
            for i = 2, #list do
                ns.TipDoubleLine(tooltip, "  " .. ns.Ago(list[i].t), Brief(list[i]), "highlight", "highlight")
            end
        end
        if self.cfg.trend then AddTrend(tooltip, self.cfg, e) end
        -- Quelle der Werte (Leitlinie 11)
        tooltip:AddLine(" ")
        ns.TipLine(tooltip, L.COMBAT_SOURCE, "hint", true)
    end
    tooltip:AddLine(" ")
    local other = OtherMeter()
    if other then
        ns.TipLine(tooltip, L.COMBAT_OTHER:format(other), "hint", true)
    else
        local on = MeterOn()
        if on == nil then
            ns.TipLine(tooltip, L.COMBAT_METER_MISSING, "hint", true)
        else
            ns.TipDoubleLine(tooltip, L.COMBAT_METER, on and L.ON or L.OFF, "normal", "highlight")
        end
    end
end

-- Hinweise passend zum Klick: ohne eigenen Schalter (anderes Addon, keine Anzeige) keiner.
block.hints = function()
    if OtherMeter() or MeterOn() == nil then return {} end
    return { L.COMBAT_HINT_LEFT }
end

-- ezCombats Einstellungen öffnen (dort steht „Zusammenfassung nach dem Kampf“) – sonst die Erklärung im Chat.
local function OpenRecorderSettings()
    if Core.OpenModuleSettings and Core.OpenModuleSettings("ezCombat") then return true end
    ns.Print(L.COMBAT_NONE)
    return false
end
block.OpenRecorderSettings = OpenRecorderSettings

block.actions = function()
    local list = {}
    if not (OtherMeter() or MeterOn() == nil) then list[1] = { text = L.COMBAT_METER_TOGGLE, fn = ToggleMeter } end
    -- Noch kein Kampf, ezCombat läuft, sein Schalter ist nicht sicher an: der Weg dorthin (sichtbar statt nur im Tooltip)
    if Recorder() and SummaryOn() ~= true and not Fights(1)[1] then list[#list + 1] = { text = L.COMBAT_OPEN_EZCOMBAT:format(Core.L.MENU_OWN_SETTINGS), fn = OpenRecorderSettings } end
    -- V5: nur mit ezCores Kopierfeld (Welle 23d) und mindestens einem Kampf
    if ns.CanCopyText() and Fights(1)[1] then list[#list + 1] = { text = L.COMBAT_COPY, fn = CopyFights } end
    return list
end

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    if OtherMeter() or MeterOn() == nil then return end
    ToggleMeter()
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(bar, L.COMBAT_SHOW_AUTO, cfg, "show", "auto", self)
    ns.MenuRadio(bar, L.COMBAT_SHOW_DPS, cfg, "show", "dps", self)
    ns.MenuRadio(bar, L.COMBAT_SHOW_HPS, cfg, "show", "hps", self)
    ns.MenuRadio(bar, L.COMBAT_SHOW_DURATION, cfg, "show", "duration", self)
    bar:CreateDivider()
    ns.MenuCheck(bar, L.COMBAT_SHOW_RANK, cfg, "rank", self)

    -- Verlauf über Wochen (V4): an/aus, welche Kämpfe, Mindestdauer
    local trend = root:CreateButton(L.COMBAT_TREND_MENU)
    ns.MenuCheck(trend, L.COMBAT_TREND_SHOW, cfg, "trend", self)
    trend:CreateDivider()
    ns.MenuRadio(trend, L.COMBAT_TREND_KIND_AUTO, cfg, "trendKind", "auto", self)
    ns.MenuRadio(trend, L.COMBAT_TREND_KIND_SOLO, cfg, "trendKind", "solo", self)
    ns.MenuRadio(trend, L.COMBAT_TREND_KIND_GROUP, cfg, "trendKind", "group", self)
    trend:CreateDivider()
    for _, seconds in ipairs(TREND_MINS) do
        ns.MenuRadio(trend, L.COMBAT_TREND_MIN:format(Core.Seconds(seconds)), cfg, "trendMin", seconds, self)
    end
end

-- Neuer Kampf im Verlauf (ezCombat schreibt ihn nach dem Kampf) oder geleerter Verlauf: neu zeichnen.
local function OnHistory(kind)
    if kind == nil or kind == KIND then ns.QueueUpdate(block) end
end
Core.Listen("HISTORY_ADDED", OnHistory, "ezPanel")
Core.Listen("HISTORY_REMOVED", OnHistory, "ezPanel")
Core.Listen("HISTORY_CLEARED", OnHistory, "ezPanel")
-- Blizzards Schalter (auch aus ezCombat oder Blizzards Optionen): Tooltip und Hinweis folgen.
ns.On("CVAR_UPDATE", function(_, name)
    if name == CVAR then ns.QueueUpdate(block) end
end)
