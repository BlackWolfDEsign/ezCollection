local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Emote-Leisten über ezBars (Entscheidungen des Nutzers vom 14.11.2026: „ezMacro sollte die ezBar als leiste für
    emotes benutzen (+größeneinstellbar)“; Frage 16: ohne ezBars „Hinweis mit Knopf (Empfohlen)“).

    ezMacro liefert nur, was auf den Knöpfen liegt: je Leiste die gewählten Emotes (Data\Emotes.lua, reine Emotes wie
    {e:THANK}) mit Symbol, Tooltip und Klick über ns.Emote.Perform (Emote.lua – sonst spuckte die Leiste wieder auf
    den Boden), dazu als ersten Knopf ein Zahnrad für das Menü der Leiste (Rechtsklick auf ein Emote zusätzlich). Zeichnen,
    Raster (Spalten, Reihen, Knopfgröße, Abstand), Sichtbarkeit, Verschieben und die Plätze am Chat übernimmt ezBars
    (ezCore.API("ezBars").RegisterBar, ezBars/Core.lua; Anker in ezBars/Anchors.lua):
      Leiste 1  "chatSide": senkrecht neben dem Chat, gegenüber von Blizzards Chat-Knöpfen (rechts, solange die
                Knöpfe links stehen)
      Leiste 2  "chatTop": waagerecht direkt auf den Chat-Reitern, ohne Abstand, rechtsbündig (Spieltest 14.11.2026:
                „dort wo der rahmen ist will ich keinen abstand haben sondern direkt die bar“)
      weitere   "free" (ezBars stellt sie untereinander in die Bildschirmmitte), solange kein Platz am Chat frei ist
    Was ezBars nicht abdeckt, meldet seine Abfrage BarAnchors(): Fehlt ein Platz am Chat, steht die Leiste frei, und
    Status sowie Bars.Uncovered() nennen es (Abbruchkriterium aus Welle 3 des Fertigstellungsplans).

    Läuft ezBars nicht, baut ezMacro keine eigene Leiste (Frage 16): Einstellungsseite, Reiter „Chat“ (Emotes) und Status
    zeigen „Emote-Leisten brauchen ezBars“ mit einem Knopf (Bars.ShowNeed: Übersicht der ezCollection, dazu im Chat,
    ob ezBars fehlt oder nur ausgeschaltet ist).

    Gespeichert (ezMacroDB.bars, Fassung 5): je Leiste { id, emotes = { [Makro-ID] = true }, anchor = "chatSide" |
    "chatTop" | "free", cols, rows } – cols und rows sind nur die Standardwerte, die ezBars beim ersten Anmelden
    übernimmt; danach gelten die Werte in den ezBars-Einstellungen der Leiste; dazu nach der Übernahme old (Sperre und
    Anhängen der alten Fassung, aufgehoben bis zur Antwort auf die Frage Welle 5). Die Leisten der Fassungen 1 bis 4
    (eigene Rahmen, Umbruch, Einrasten) übernimmt Bars.Upgrade einmal: Auswahl, Platz und Ausrichtung.
]]
local Bars = {}
ns.EmoteBar = Bars

local OWNER = "ezMacro"
local KEY_PREFIX = "ezMacro.bar"            -- Lage der Fassungen 1–4 in ezCoreDB.positions (frei stehende Leisten)
local ID_PREFIX = "ezMacroEmote"            -- Kennung bei ezBars: ezMacroEmote<ID>
-- Speicherplatz der Lage einer angemeldeten Leiste in ezCoreDB.positions: ezBars' Mover-Schlüssel
-- „ezBars.extra.<Kennung>“ (Bars.MoverKey in ezBars/Bars.lua, genannt in docs/roadmap/ezBars.md). Nur für die einmalige
-- Übernahme einer alten Lage und für „Zurücksetzen“; die Prüfung „Lage übernommen“ hält den Namen genau.
local EZBARS_KEY = "ezBars.extra."
-- Knopfgröße in ezBars (% von 45 ≈ 22 px wie bisher) und Abstand in px bei 100 %: ezBars skaliert Knopf, Symbol und
-- Abstand gemeinsam (wie Blizzards Bearbeitungsmodus; Spieltest 15.11.2026), 6 ergibt bei 50 % die bisherigen 3 px.
local SIZE, PADDING = 50, 6
local GRID_MAX = 12                         -- Spalten und Reihen in ezBars höchstens
-- Zahnrad als erster Knopf der Leiste: das eine Zahnrad von ezCore (Core.Menu.ICON_SETTINGS, aufgelöst über
-- Core.Menu.ResolveIcon – Atlas, sonst Blizzards Datei; Gesamtreview T9-9, design-system 2.2).
local function GearIcon()
    local kind, value = Core.Menu.ResolveIcon(Core.Menu.ICON_SETTINGS)
    if kind == "atlas" then return value, nil end
    return nil, value
end
-- Standard: freundliche Emotes senkrecht am Chat, die für Heilung und Kampf waagerecht auf den Chat-Reitern
-- (Entscheidung des Nutzers, 13.11.2026). Raster mit Platz für das Zahnrad.
local DEFAULT_BARS = {
    { emotes = { "emote_thank", "emote_hello", "emote_cheer", "emote_bow", "emote_laugh", "emote_applaud" },
      anchor = "chatSide", cols = 1, rows = 7 },
    { emotes = { "emote_healme", "emote_helpme", "emote_oom", "emote_charge", "emote_wait", "emote_follow" },
      anchor = "chatTop", cols = 7, rows = 1 },
}
-- 2: neue Leiste 2 (Heilung und Kampf) · 3: Leiste 2 oben über dem Chat · 4: senkrecht 7 je Spalte (13.11.2026)
-- 5: Leisten über ezBars (14.11.2026)
local BARS_VERSION = 5
-- Leiste 2 der Version 1 (freche Emotes); wer sie nie geändert hat, bekommt die neue Leiste 2.
local OLD_SECOND = { emote_spit = true, emote_mock = true, emote_chicken = true, emote_rude = true }
local ANCHORS = { chatSide = true, chatTop = true, free = true }
local CHAT_SLOTS = { "chatSide", "chatTop" }  -- Plätze am Chat, die je nur eine Leiste belegt

local options
local registered = {}                       -- [Leisten-ID] = true: bei ezBars angemeldet
local clicks = {}                           -- [Leisten-ID] = { [Token] = Klick-Funktion } (Bars.FindButton)

---------------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------------

-- Alle reinen Emotes aus den Emote-Makros, in deren Reihenfolge (eine Quelle für Browser und Leisten).
function Bars.Options()
    if options then return options end
    options = {}
    for _, entry in ipairs(ns.MACROS) do
        local token = entry.category == "emote" and entry.body:match("^{e:([%u_]+)}$")
        if token then options[#options + 1] = { entry = entry, token = token } end
    end
    return options
end

function Bars.List()
    return ns.db.bars
end

function Bars.Get(id)
    for index, data in ipairs(ns.db.bars) do
        if data.id == id then return data, index end
    end
end

-- Speicherplatz der alten Lage (Fassungen 1–4) in ezCoreDB.positions.
function Bars.Key(id)
    return KEY_PREFIX .. tostring(id)
end

-- Kennung der Leiste bei ezBars und der Speicherplatz ihrer Lage dort.
function Bars.BarId(id)
    return ID_PREFIX .. tostring(id)
end

function Bars.PositionKey(id)
    return EZBARS_KEY .. Bars.BarId(id)
end

-- Wie viele Emotes die Leiste zeigt (nur bekannte, in der Reihenfolge von Bars.Options).
local function EmoteCount(data)
    local count = 0
    if type(data.emotes) ~= "table" then return count end
    for _, option in ipairs(Bars.Options()) do
        if data.emotes[option.entry.id] then count = count + 1 end
    end
    return count
end

local function Label(option)
    return ns.Text(option.entry.name)
end

local function Clamp(value, default)
    value = math.floor(tonumber(value) or default)
    return math.max(1, math.min(GRID_MAX, value))
end

-- Platz am Chat ("chatSide", "chatTop") frei (außer für exceptId)?
local function SlotFree(slot, exceptId)
    for _, data in ipairs(ns.db.bars) do
        if data.anchor == slot and data.id ~= exceptId then return false end
    end
    return true
end

-- Standardraster je Platz: am Chat seitlich eine Spalte, sonst eine Reihe (mit Platz für das Zahnrad).
local function DefaultGrid(anchor)
    if anchor == "chatSide" then return 1, 7 end
    return 7, 1
end

local function NewBar(emotes, anchor, cols, rows)
    local id = ns.db.nextBarId or 1
    ns.db.nextBarId = id + 1
    local set = {}
    for _, emote in ipairs(emotes or {}) do set[emote] = true end
    local defaultCols, defaultRows = DefaultGrid(anchor)
    local data = { id = id, emotes = set, anchor = ANCHORS[anchor] and anchor or "free",
        cols = Clamp(cols, defaultCols), rows = Clamp(rows, defaultRows) }
    table.insert(ns.db.bars, data)
    return data
end

local function CreateDefaults()
    ns.db.bars, ns.db.nextBarId, ns.db.barsVersion = {}, 1, BARS_VERSION
    for _, def in ipairs(DEFAULT_BARS) do NewBar(def.emotes, def.anchor, def.cols, def.rows) end
end

-- Raster einer Leiste der Fassungen 1–4 für ezBars: so viele Spalten und Reihen, wie sie zeigte. Das Zahnrad stand dort
-- hinter dem letzten Platz der ersten Spalte (Reihe); bei ezBars ist es ein Knopf im Raster, darum ein Platz mehr.
--   senkrecht   „Emotes pro Spalte“ (perLine) je Spalte, weitere Spalten daneben
--   waagerecht  Fassung 4: eine Reihe, mit „Zweite Reihe“ (twoRows) zwei; bis Fassung 3: Reihen zu je perLine
-- Ohne gespeicherten Wert gilt der Standard der Fassung (bis 3: 6 je Spalte, ab 4: 7).
local function OldGrid(data, version)
    local emotes = EmoteCount(data)
    local count = emotes + 1
    local per = math.max(1, math.floor(tonumber(data.perLine) or (version < 4 and 6 or 7)))
    local cols, rows
    if data.horizontal then
        if version >= 4 then
            rows = data.twoRows and 2 or 1
            cols = math.ceil(count / rows)
        else
            cols = math.min(emotes, per) + 1
            rows = math.ceil(count / cols)
        end
    else
        rows = math.min(emotes, per) + 1
        cols = math.ceil(count / rows)
    end
    if cols > GRID_MAX then cols, rows = GRID_MAX, math.ceil(count / GRID_MAX) end
    if rows > GRID_MAX then rows, cols = GRID_MAX, math.ceil(count / GRID_MAX) end
    return Clamp(cols, 1), Clamp(rows, 1)
end

-- Alte Lage (Fassungen 1–4) einmal an den Platz von ezBars geben; ezCore.Mover setzt sie beim Anmelden.
local function MovePosition(data)
    local old = Core.StoredPosition(Bars.Key(data.id))
    if old then Core.ImportPosition(Bars.PositionKey(data.id), old) end
    Core.StorePosition(Bars.Key(data.id), nil)
end

-- Sperre und Anhängen kennt ezBars nicht (Frage Welle 5 in docs/roadmap/ezMacro.md, Empfehlung umgesetzt, Antwort
-- offen). Bis zur Antwort hebt die Übernahme die alten Werte in data.old auf ({ locked = true, to = <Leisten-ID>,
-- side = … }), damit ein späterer Nachbau sie wieder herstellen kann; gelesen wird data.old von nichts.
local function KeepOld(data, locked, anchor)
    local old = {}
    if locked then old.locked = true end
    if type(anchor) == "table" and type(anchor.to) == "number" then old.to, old.side = anchor.to, anchor.side end
    if next(old) then data.old = old end
end

-- Eine Leiste der Fassungen 1–4 in Fassung 5 umschreiben: Platz am Chat bleibt („chat“ » chatSide, „chatTop“ bleibt),
-- eine frei stehende Leiste behält ihre Lage, eine an eine andere Leiste gesteckte steht frei (ezBars steckt keine
-- Leisten zusammen). Ausrichtung und Umbruch werden Spalten und Reihen.
local function ConvertBar(data, version)
    local anchor = type(data.anchor) == "table" and data.anchor or {}
    KeepOld(data, data.locked, anchor)
    data.cols, data.rows = OldGrid(data, version)
    if anchor.to == "chat" or anchor.to == "chatTop" then
        -- am Chat gilt der Anker, eine übrig gebliebene Lage nicht (wie bisher in Bars.Validate)
        data.anchor = anchor.to == "chat" and "chatSide" or "chatTop"
        Core.StorePosition(Bars.Key(data.id), nil)
    else
        if type(anchor.free) == "table" then Core.ImportPosition(Bars.Key(data.id), anchor.free) end
        data.anchor = "free"
        MovePosition(data)
    end
    data.horizontal, data.perLine, data.twoRows, data.locked = nil, nil, nil, nil
end

-- Übernimmt die einzelne Leiste der ersten Version (ezMacroDB.bar und die alten Einstellungen) in Leiste 1;
-- die frechen Emotes wandern dabei auf Leiste 2. Eine alte freie Lage geht einmal an ezCore (Platz von ezBars).
function Bars.Migrate()
    if type(ns.db.bars) == "table" and #ns.db.bars > 0 then return false end
    CreateDefaults()
    local old, first, second = ns.db.bar, ns.db.bars[1], ns.db.bars[2]
    if type(old) == "table" then
        if type(old.emotes) == "table" then
            first.emotes = {}
            for id, on in pairs(old.emotes) do
                if on and not second.emotes[id] then first.emotes[id] = true end
            end
        end
        KeepOld(first, ns.S.barLocked == true)
        local layout = { emotes = first.emotes, horizontal = ns.S.barHorizontal == true, perLine = ns.S.barPerLine }
        first.cols, first.rows = OldGrid(layout, 1)
        if type(old.pos) == "table" and old.pos[1] and Core.ImportPosition(Bars.PositionKey(first.id), old.pos) then
            first.anchor = "free"
        end
    end
    ns.db.bar = nil
    ns.S.barHorizontal, ns.S.barPerLine, ns.S.barLocked = nil, nil, nil
    return true
end

local function SameSet(a, b)
    for key in pairs(a) do if not b[key] then return false end end
    for key in pairs(b) do if not a[key] then return false end end
    return true
end

-- Einmalig je Fassung der Leisten. Rückgabe: true, wenn sich etwas geändert hat.
--   2: Hat Leiste 2 noch die frechen Emotes der ersten Fassung, bekommt sie die Emotes für Heilung und Kampf
--      (die von Leiste 1 dorthin umziehen) und hängt wieder außen an Leiste 1, falls sie frei stand.
--   3: Liegt Leiste 2 noch am alten Standardplatz (außen an Leiste 1, die am Chat hängt), kommt sie waagerecht
--      oben über den Chat (neuer Standard, 13.11.2026). Selbst verschobene Leisten bleiben, wo sie sind.
--   4: (senkrecht höchstens 7 je Spalte, waagerecht „Zweite Reihe“) geht in Schritt 5 auf: OldGrid liest jede alte
--      Fassung so, wie sie die Leiste zeigte.
--   5: Leisten über ezBars (ConvertBar): Platz, Lage, Spalten und Reihen.
function Bars.Upgrade()
    local version = tonumber(ns.db.barsVersion) or 1
    if version >= BARS_VERSION then return false end
    ns.db.barsVersion = BARS_VERSION
    local first, second = ns.db.bars[1], ns.db.bars[2]
    if type(first) == "table" and type(second) == "table" then
        if version < 2 and type(second.emotes) == "table" and SameSet(second.emotes, OLD_SECOND) then
            second.emotes = {}
            for _, emote in ipairs(DEFAULT_BARS[2].emotes) do
                second.emotes[emote] = true
                if type(first.emotes) == "table" then first.emotes[emote] = nil end
            end
            if type(second.anchor) ~= "table" or second.anchor.free then
                Core.StorePosition(Bars.Key(second.id), nil)
                second.anchor = { to = first.id, side = "outward" }
            end
        end
        -- Nur beim Schritt auf Fassung 3 (V-094): Wer Leiste 2 danach bewusst wieder außen an Leiste 1 steckt, behält das.
        local anchor = type(second.anchor) == "table" and second.anchor or {}
        if version < 3 and anchor.to == first.id and anchor.side == "outward" and type(first.anchor) == "table"
            and first.anchor.to == "chat" then
            second.anchor = { to = "chatTop" }
            second.horizontal = true
        end
    end
    for _, data in ipairs(ns.db.bars) do
        if type(data) == "table" and type(data.id) == "number" then ConvertBar(data, version) end
    end
    return true
end

-- Gespeicherte Leisten prüfen: kaputte Einträge reparieren, doppelte Plätze am Chat lösen.
function Bars.Validate()
    local valid = {}
    for _, data in ipairs(ns.db.bars) do
        if type(data) == "table" and type(data.id) == "number" then
            data.emotes = type(data.emotes) == "table" and data.emotes or {}
            if not ANCHORS[data.anchor] then data.anchor = "free" end
            local cols, rows = DefaultGrid(data.anchor)
            data.cols, data.rows = Clamp(data.cols, cols), Clamp(data.rows, rows)
            valid[#valid + 1] = data
            if data.id >= (ns.db.nextBarId or 1) then ns.db.nextBarId = data.id + 1 end
        end
    end
    ns.db.bars = valid
    local taken = {}
    for _, data in ipairs(valid) do
        if data.anchor ~= "free" then
            if taken[data.anchor] then data.anchor = "free" end
            taken[data.anchor] = true
        end
    end
end

---------------------------------------------------------------------------
-- ezBars
---------------------------------------------------------------------------

local function API()
    local api = Core.API("ezBars")
    if type(api) == "table" and type(api.RegisterBar) == "function" then return api end
    return nil
end

-- Läuft ezBars mit Leisten für andere Module?
function Bars.Available()
    return API() ~= nil
end

-- Zustand von ezBars: "loaded" | "outdated" (läuft, kennt aber keine Leisten anderer Module: eine Fassung vor
-- RegisterBar) | "disabled" (installiert, aus) | "absent" (nicht installiert) – ezCore.ModuleState.
function Bars.State()
    if Bars.Available() then return "loaded" end
    local state = Core.ModuleState and Core.ModuleState("ezBars") or "disabled"
    if state == "loaded" then return "outdated" end
    return state == "absent" and "absent" or "disabled"
end

-- Text je Zustand ohne ezBars-Leisten: für den Chat (BAR_NEED_*) und den Status (BAR_STATE_*).
local NEED_TEXT = { absent = "BAR_NEED_ABSENT", disabled = "BAR_NEED_DISABLED", outdated = "BAR_NEED_OUTDATED" }
local STATE_TEXT = { absent = "BAR_STATE_ABSENT", disabled = "BAR_STATE_DISABLED", outdated = "BAR_STATE_OUTDATED" }

-- Plätze am Chat, die ezBars nicht abdeckt (BarAnchors), als Liste der Kennungen ("chatSide", "chatTop"); leer, wenn
-- alles abgedeckt ist. Für Spieler heißen sie L.BAR_SLOT_<Kennung>.
function Bars.Uncovered()
    local api, out = API(), {}
    if not api then return out end
    local covered = type(api.BarAnchors) == "function" and api.BarAnchors() or {}
    for _, slot in ipairs(CHAT_SLOTS) do
        if type(covered) ~= "table" or covered[slot] ~= true then out[#out + 1] = slot end
    end
    return out
end

-- Knopf „Emote-Leisten brauchen ezBars“ (Einstellungen, Reiter „Chat“ (Emotes)): sagt im Chat, ob ezBars fehlt oder nur
-- ausgeschaltet ist, und öffnet die Übersicht der ezCollection (alle Module mit ihrem Stand).
function Bars.ShowNeed()
    local state = Bars.State()
    if state == "loaded" then return Bars.OpenSettings() end
    ns.Print(L[NEED_TEXT[state] or NEED_TEXT.disabled])
    if Core.OpenSettings then Core.OpenSettings() end
    return false
end

local function Blocked()
    Core.ErrorMessage(L.BAR_BLOCKED)
end

-- Tooltip eines Emote-Knopfs: füllt GameTooltip selbst (ezBars hat SetOwner schon gesetzt und ruft Show).
local function EmoteTooltip(option)
    return function()
        GameTooltip:SetText(Label(option))
        -- Emote ohne Ziel im Client (Spucken): mit Ziel der Satz, der hinausgeht – im Modus „Animation + Text“ mit
        -- dem Hinweis auf die Animation davor; dazu immer der Grund (auch für „Angriff!“ mit Ziel)
        local line = ns.Emote.Preview(option.token)
        if line then
            -- Rollen statt Farbzahlen (Gesamtreview 18.11.2026, T9-6)
            Core.TipLine(GameTooltip, L[ns.Emote.Mode() == "both" and "BAR_TIP_BOTH" or "BAR_TIP_TEXT"]:format(line), "highlight", true)
        else
            local target = ns.Emote.TargetName()
            Core.TipLine(GameTooltip, target and L.BAR_TIP_TARGET:format(target) or L.BAR_TIP_NOTARGET, "highlight")
        end
        local why = ns.Emote.Reason(option.token)
        if why then Core.TipText(GameTooltip, why) end
        Core.TipLine(GameTooltip, L.BAR_TIP_MENU, "hint")
        Core.TipLine(GameTooltip, L.BAR_TIP_MOVE, "hint", true)
    end
end

-- Knöpfe einer Leiste für ezBars: zuerst das Zahnrad, dann die gewählten Emotes in der Reihenfolge von Bars.Options.
-- Das Zahnrad steht vorn, weil ezBars bei mehr Knöpfen als Plätzen im Raster die letzten abschneidet – so bleibt der
-- sichtbare Weg zum Menü (Leitlinie 3) immer da, auch mit einem Emote mehr oder einem kleineren Raster.
function Bars.Buttons(data)
    -- Sichtbarer Weg zum Menü der Leiste (Leitlinie 3): Zahnrad wie Blizzards UIPanelIconDropdownButtonTemplate.
    local function gear(button) Bars.OpenMenu(data.id, button) end
    local gearAtlas, gearFile = GearIcon()
    local list = { {
        atlas = gearAtlas, icon = gearFile,
        tooltip = function()
            local _, index = Bars.Get(data.id)
            return L.BAR_MENU_BUTTON:format(index or 1), L.BAR_MENU_BUTTON_TIP
        end,
        onClick = gear,
    } }
    local byToken = { menu = gear }
    for _, option in ipairs(Bars.Options()) do
        if data.emotes[option.entry.id] then
            local function click(button, mouseButton)
                if mouseButton == "RightButton" then
                    Bars.OpenMenu(data.id, button)
                elseif ns.Emote.Perform(option.token) == false then
                    Blocked()
                end
            end
            byToken[option.token] = click
            list[#list + 1] = { icon = ns.EntryIcon(option.entry), tooltip = EmoteTooltip(option), onClick = click }
        end
    end
    clicks[data.id] = byToken
    return list
end

-- Knopf einer angemeldeten Leiste, der das Emote token zeigt ("menu": das Zahnrad) – für Erklärungen und Prüfungen.
function Bars.FindButton(id, token)
    local api, wanted = API(), clicks[id] and clicks[id][token]
    local frame = api and wanted and api.BarFrame(Bars.BarId(id))
    if type(frame) ~= "table" or type(frame.buttons) ~= "table" then return nil end
    for _, button in ipairs(frame.buttons) do
        if button:IsShown() and type(button.ezButton) == "table" and button.ezButton.onClick == wanted then return button end
    end
    return nil
end

-- Rahmen einer angemeldeten Leiste (von ezBars) oder nil.
function Bars.Frame(id)
    local api = API()
    return api and registered[id] and api.BarFrame(Bars.BarId(id)) or nil
end

local function Register(data, index)
    local api = API()
    local ok, why = api.RegisterBar({
        id = Bars.BarId(data.id), name = L.BAR_TITLE_N:format(index), owner = OWNER,
        buttons = Bars.Buttons(data), anchor = data.anchor,
        defaults = { cols = data.cols, rows = data.rows, size = SIZE, padding = PADDING, show = "always" },
    })
    if ok then
        registered[data.id] = true
    else
        ns.Error(tostring(why), "EmoteBar RegisterBar " .. Bars.BarId(data.id))
    end
end

local function Unregister(id)
    local api = API()
    if api and registered[id] then api.UnregisterBar(Bars.BarId(id)) end
    registered[id] = nil
    clicks[id] = nil
end

-- Meldet die Leisten bei ezBars an (wiederholbar: neue Emotes, Namen, Platz) bzw. ab (ausgeblendet, entfernt). Ohne
-- ezBars nichts – kein eigener Leistenbau (Frage 16).
function Bars.PlaceAll()
    if not ns.db or type(ns.db.bars) ~= "table" then return end
    local wanted = {}
    if API() and ns.S.barShown then
        for index, data in ipairs(ns.db.bars) do
            wanted[data.id] = true
            Register(data, index)
        end
    end
    for id in pairs(registered) do
        if not wanted[id] then Unregister(id) end
    end
    -- Einmal erklären, was die Leiste kann; die Blase steht zur Bildschirmmitte hin.
    local first = ns.db.bars[1] and Bars.Frame(ns.db.bars[1].id)
    if first and ns.Hint then
        local x, width = first:GetCenter(), GetScreenWidth and GetScreenWidth()
        ns.Hint.Show("bars", first, first, L.HINT_BARS, (x and width and x > width / 2) and "left" or "right")
    end
end

function Bars.Update()
    Bars.PlaceAll()
end

-- Bei ezBars angemeldete Leisten (Anzahl).
function Bars.Registered()
    local n = 0
    for _ in pairs(registered) do n = n + 1 end
    return n
end

-- Einstellungen der Leiste bei ezBars öffnen (Spalten, Reihen, Knopfgröße, Abstand, Sichtbarkeit, Lage); ohne id die
-- erste Leiste. Ohne ezBars der Hinweis.
function Bars.OpenSettings(id)
    local api = API()
    if not api then return Bars.ShowNeed() end
    id = id or (ns.db.bars[1] and ns.db.bars[1].id)
    if id and registered[id] and api.OpenBarSettings(Bars.BarId(id)) then return true end
    ns.Print(ns.S.barShown and L.BAR_NONE or L.BAR_HIDDEN)
    return false
end

---------------------------------------------------------------------------
-- Leisten anlegen, entfernen, zurücksetzen, verschieben
---------------------------------------------------------------------------

-- Standardplatz einer Leiste: Leiste 1 seitlich am Chat, Leiste 2 auf den Reitern, weitere auf dem ersten freien
-- Platz am Chat, sonst frei.
function Bars.DefaultAnchor(data)
    local _, index = Bars.Get(data.id)
    local def = index and DEFAULT_BARS[index]
    if def and SlotFree(def.anchor, data.id) then return def.anchor end
    for _, slot in ipairs(CHAT_SLOTS) do
        if SlotFree(slot, data.id) then return slot end
    end
    return "free"
end

-- Neue, leere Leiste auf ihrem Standardplatz (Bars.DefaultAnchor: als Leiste 2 auf den Reitern, sonst der erste freie
-- Platz am Chat, sonst frei), mit dem Standardraster dieses Platzes.
function Bars.Add()
    local data = NewBar({}, "free")
    data.anchor = Bars.DefaultAnchor(data)
    data.cols, data.rows = DefaultGrid(data.anchor)
    if not ns.S.barShown then ns.SetSetting("barShown", true) end
    Bars.PlaceAll()
    return data
end

-- Verschobene Lage einer Leiste vergessen: bei ezBars (ezCore.Mover) und die alte von ezMacro (Fassungen 1–4).
local function ForgetPosition(id)
    local Mover, key = Core.Mover, Bars.PositionKey(id)
    if Mover and Mover.Get and Mover.Get(key) then Mover.Reset(key) else Core.StorePosition(key, nil) end
    Core.StorePosition(Bars.Key(id), nil)
end

-- Entfernt eine Leiste (ezBars meldet sie ab; ihre Einstellungen dort bleiben). Die letzte bleibt. Ihre verschobene
-- Lage vergisst ezCore – sonst erbte eine spätere Leiste mit derselben Nummer (nach „Zurücksetzen“) die alte Stelle.
function Bars.Remove(id)
    local data, index = Bars.Get(id)
    if not data or #ns.db.bars <= 1 then return false end
    ForgetPosition(id)
    table.remove(ns.db.bars, index)
    Bars.PlaceAll()
    return true
end

-- Die zwei Standard-Leisten wieder herstellen: Emotes und Platz am Chat; eine verschobene Lage vergisst ezCore.
-- Spalten, Reihen und Größe bleiben in den ezBars-Einstellungen der Leiste. Nur außerhalb des Kampfes.
function Bars.Reset()
    if ns.InCombat() then
        ns.CombatNotice()
        return false
    end
    for _, data in ipairs(type(ns.db.bars) == "table" and ns.db.bars or {}) do
        if type(data) == "table" and data.id then ForgetPosition(data.id) end
    end
    ns.db.bars, ns.db.bar = nil, nil
    Bars.Migrate()
    Bars.PlaceAll()
    return true
end

-- Leisten verschieben: ezCores Auswahl der ezBars-Leisten ohne Bearbeitungsmodus (die Emote-Leisten gehören dort
-- zu ezBars).
function Bars.Unlock()
    if not ns.S.barShown then ns.SetSetting("barShown", true) end
    if Core.Mover then Core.Mover.Unlock("ezBars") end
end

-- Legt ein Emote auf eine Leiste oder nimmt es herunter – die eine Stelle, die die Belegung schreibt (Menü der
-- Leiste, „Alle auswählen“ und „Auf die Leiste“ im Reiter „Chat“). bar: Leistendaten oder Kennung; beim Auflegen wird
-- die Leiste eingeschaltet; noPlace: nicht gleich neu setzen (wer viele ändert, ruft danach einmal Bars.PlaceAll).
-- » true | false (keine solche Leiste)
function Bars.SetEmote(bar, emote, on, noPlace)
    local data = type(bar) == "table" and bar or Bars.Get(bar)
    if type(data) ~= "table" or emote == nil then return false end
    data.emotes = type(data.emotes) == "table" and data.emotes or {}
    data.emotes[emote] = on and true or nil
    if on and not ns.S.barShown then ns.SetSetting("barShown", true) end
    if not noPlace then Bars.PlaceAll() end
    return true
end

---------------------------------------------------------------------------
-- Menü je Leiste (Zahnrad als erster Knopf, Rechtsklick auf ein Emote zusätzlich)
---------------------------------------------------------------------------

function Bars.OpenMenu(id, owner)
    local data, index = Bars.Get(id)
    if not data then return end
    local Menu = Core.Menu
    Menu.Open(owner or Bars.Frame(id), function(root)
        Menu.Title(root, L.BAR_TITLE_N:format(index))
        local options = Bars.Options()
        -- Haken „Alle“ über den Emotes (Design-System 2.11, ezCores Baustein; gemerkt in
        -- data.emotes wie jeder einzelne Haken). Die Leiste wird nur einmal neu gesetzt, nicht je Emote.
        Menu.AllToggle(root, options, function(option) return data.emotes[option.entry.id] == true end,
            function(option, on) Bars.SetEmote(data, option.entry.id, on, true) end,
            { after = function(changed) if changed > 0 then Bars.PlaceAll() end end })
        for _, option in ipairs(options) do
            local emote = option.entry.id
            Menu.Toggle(root, ("|T%s:16:16|t %s"):format(tostring(ns.EntryIcon(option.entry)), Label(option)),
                function() return data.emotes[emote] == true end,
                function(on) Bars.SetEmote(data, emote, on) end)
        end
        Menu.Divider(root)
        -- Spalten, Reihen, Knopfgröße, Abstand, Sichtbarkeit und Standardplatz: Seite der Leiste bei ezBars
        Menu.Button(root, L.BAR_SETTINGS, function() Bars.OpenSettings(id) end)
        Menu.Button(root, L.BAR_MOVE, function() Bars.Unlock() end)
        Menu.Divider(root)
        Menu.Button(root, L.BAR_NEW, function() Bars.Add() end)
        local remove = Menu.Button(root, L.BAR_REMOVE, function() Bars.Remove(id) end)
        if remove and remove.SetEnabled then remove:SetEnabled(#ns.db.bars > 1) end
        Menu.Button(root, L.BAR_HIDE, function()
            ns.SetSetting("barShown", false)
            ns.Print(L.BAR_HIDDEN)
        end)
    end)
end

---------------------------------------------------------------------------
-- Status und Start
---------------------------------------------------------------------------

function Bars.StatusLine()
    local state = Bars.State()
    if state ~= "loaded" then
        return L.BAR_STATUS_NEED:format(L[STATE_TEXT[state] or STATE_TEXT.disabled])
    end
    if not ns.S.barShown then return L.BAR_STATUS_OFF end
    local line = L.BAR_STATUS:format(Bars.Registered())
    local missing = {}
    for _, slot in ipairs(Bars.Uncovered()) do missing[#missing + 1] = L["BAR_SLOT_" .. slot] end
    if #missing > 0 then line = line .. " " .. L.BAR_STATUS_UNCOVERED:format(table.concat(missing, ", ")) end
    return line
end

ns.AddStatusLine(function() return Bars.StatusLine() end)

ns.OnSettingChanged(function(key)
    if key == "barShown" then Bars.PlaceAll() end
end)

ns.OnReady(function()
    Bars.Migrate()
    Bars.Upgrade()
    Bars.Validate()
    Bars.PlaceAll()
end)
