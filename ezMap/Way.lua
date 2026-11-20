local ADDON, ns = ...
local L = ns.L
local Core = ezCore

-- /way mit Blizzards eigener Kartenmarkierung (C_Map.SetUserWaypoint) und – nur mit dem Schalter wayTrack, ab Werk aus
-- seit Welle 29 (NACH-27) – Zielverfolgung (C_SuperTrack):
-- kein eigener Pfeil, keine eigenen Kartensymbole. Blizzard kennt nur eine Markierung; ezMap merkt sich
-- die letzten als „Zuletzt“ (Kartenmenü) und den Titel, den Blizzards Markierung nicht hat.
local Way = {}
ns.Way = Way

local HISTORY_MAX = 15
local SAME = 0.0005     -- gleiche Stelle (Bruchteil der Kartenbreite)

---------------------------------------------------------------------------
-- Zonennamen finden
---------------------------------------------------------------------------

-- Vergleichsform: klein, ohne Leer- und Satzzeichen („Un'Goro-Krater“ = „ungoro krater“).
-- string.lower kennt nur ASCII, deshalb die Umlaute von Hand.
local FOLD = { ["Ä"] = "ä", ["Ö"] = "ö", ["Ü"] = "ü", ["É"] = "é", ["È"] = "è", ["À"] = "à" }
local function Fold(text)
    text = tostring(text or ""):lower()
    for upper, lower in pairs(FOLD) do text = text:gsub(upper, lower) end
    return (text:gsub("[%s%p]", ""))
end
Way.Fold = Fold

-- Rangfolge der Kartentypen: Zone vor Kontinent vor allem anderen (Enum.UIMapType)
local TYPE_RANK = { [3] = 1, [2] = 2, [6] = 3, [5] = 4, [4] = 5, [1] = 6, [0] = 7 }

local zoneIndex

-- Oberste Karte über mapID (Elternkarte 0). Kartenangaben über Core.Map.Info: gesperrte oder fehlerhafte Antworten
-- gelten als „keine Karte“ (MAP-02); Core.Map.Parent passt nicht, es sucht eine Elternkarte mit Zieltyp.
local function TopMap(mapID)
    local info = Core.Map.Info(mapID)
    for _ = 1, 10 do
        if not info then break end
        local parent = info.parentMapID
        if not parent or parent == 0 then return info.mapID end
        local parentInfo = Core.Map.Info(parent)
        if not parentInfo then return info.mapID end
        info = parentInfo
    end
    return info and info.mapID
end

-- Alle Karten unter der obersten Karte der eigenen Zone und unter Blizzards Weltkarte (in Instanzen
-- endet die Kette der eigenen Karte manchmal früh).
local function BuildIndex()
    if not (C_Map and C_Map.GetMapChildrenInfo and C_Map.GetMapInfo) then return {} end
    local roots = {}
    local start = ns.Num(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if start then roots[#roots + 1] = TopMap(start) end
    if C_Map.GetFallbackWorldMapID then roots[#roots + 1] = TopMap(C_Map.GetFallbackWorldMapID()) end
    local index, seen = {}, {}
    local function Add(info)
        if info and info.mapID and info.name and not seen[info.mapID] then
            seen[info.mapID] = true
            index[#index + 1] = { id = info.mapID, name = info.name, key = Fold(info.name),
                rank = TYPE_RANK[info.mapType] or 8 }
        end
    end
    for _, top in ipairs(roots) do
        Add(C_Map.GetMapInfo(top))
        for _, info in ipairs(C_Map.GetMapChildrenInfo(top, nil, true) or {}) do Add(info) end
    end
    table.sort(index, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.id < b.id
    end)
    return index
end

-- Karte zu einem Namen: uiMapID oder nil, Fehlertext (bei mehreren Treffern mit Vorschlägen).
function Way.FindMap(name)
    if not zoneIndex or #zoneIndex == 0 then zoneIndex = BuildIndex() end
    local wanted = Fold(name)
    if wanted == "" then return nil, L.WAY_NO_ZONE end
    local exact, prefix, inside = {}, {}, {}
    for _, entry in ipairs(zoneIndex) do
        if entry.key == wanted then
            exact[#exact + 1] = entry
        elseif entry.key:sub(1, #wanted) == wanted then
            prefix[#prefix + 1] = entry
        elseif entry.key:find(wanted, 1, true) then
            inside[#inside + 1] = entry
        end
    end
    for _, list in ipairs({ exact, prefix, inside }) do
        if #list > 0 then
            -- Liste ist nach Kartentyp sortiert: Gleichnamige (z. B. Phasen derselben Zone) nimmt die erste.
            local names, distinct = {}, {}
            for _, entry in ipairs(list) do
                if not distinct[entry.name] then
                    distinct[entry.name] = true
                    names[#names + 1] = entry.name
                end
            end
            if #names == 1 or list == exact then return list[1].id end
            table.sort(names)
            local shown = {}
            for i = 1, math.min(5, #names) do shown[i] = names[i] end
            return nil, L.WAY_AMBIGUOUS:format(name, table.concat(shown, ", "))
        end
    end
    return nil, L.WAY_UNKNOWN_ZONE:format(name)
end

---------------------------------------------------------------------------
-- Eingabe lesen: „[Zone|#uiMapID] x y [Titel]“
---------------------------------------------------------------------------

local function Number(token)
    if not token then return nil end
    local text = token:gsub(",$", ""):gsub(",", ".")
    if text:match("^%d+%.?%d*$") or text:match("^%.%d+$") then return tonumber(text) end
    return nil
end

local function Tokens(input)
    local raw = {}
    for token in tostring(input or ""):gmatch("%S+") do raw[#raw + 1] = token end
    -- „45,32“ ohne Zahl daneben ist ein Koordinatenpaar, „45,3 32,1“ sind zwei Zahlen mit Dezimalkomma.
    local tokens = {}
    for i, token in ipairs(raw) do
        local a, b = token:match("^(%d+%.?%d*),(%d+%.?%d*)$")
        if a and not Number(raw[i - 1]) and not Number(raw[i + 1]) then
            tokens[#tokens + 1] = a
            tokens[#tokens + 1] = b
        else
            tokens[#tokens + 1] = token
        end
    end
    return tokens
end

-- Liefert { zone = Text|nil, mapID = Zahl|nil, x, y (0 bis 1), title = Text|nil } oder nil, Fehlertext.
function Way.Parse(input)
    local tokens = Tokens(input)
    local at
    for i = 1, #tokens - 1 do
        if Number(tokens[i]) and Number(tokens[i + 1]) then
            at = i
            break
        end
    end
    if not at then return nil, L.WAY_BAD end
    local x, y = Number(tokens[at]), Number(tokens[at + 1])
    if x > 100 or y > 100 then return nil, L.WAY_RANGE end
    local zone = Core.Trim(table.concat(tokens, " ", 1, at - 1))
    local title = Core.Trim(table.concat(tokens, " ", at + 2))
    local spec = { x = x / 100, y = y / 100, title = title ~= "" and title or nil }
    local id = zone:match("^#(%d+)$")
    if id then
        spec.mapID = tonumber(id)
    elseif zone ~= "" then
        spec.zone = zone
    end
    return spec
end

---------------------------------------------------------------------------
-- Blizzards Markierung setzen und lesen
---------------------------------------------------------------------------

local function Describe(entry)
    local text = ns.MapName(entry.map) .. " " .. ns.CoordText(entry.x, entry.y)
    if entry.title then text = text .. " – " .. entry.title end
    return text
end
Way.Describe = Describe

local function Remember(entry)
    local history = ns.db.way.history
    for i = #history, 1, -1 do
        local old = history[i]
        if old.map == entry.map and math.abs(old.x - entry.x) < SAME and math.abs(old.y - entry.y) < SAME then
            table.remove(history, i)
        end
    end
    table.insert(history, 1, entry)
    for i = #history, HISTORY_MAX + 1, -1 do history[i] = nil end
end

local function Link()
    if not (C_Map.GetUserWaypointHyperlink and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return nil end
    local ok, link = pcall(C_Map.GetUserWaypointHyperlink)
    if ok and type(link) == "string" and link ~= "" then return link end
    return nil
end
Way.Link = Link

-- Läuft Blizzards Zielverfolgung zur Markierung? true | false, sonst nil (Abfrage fehlt, wirft oder der Wert ist
-- gesperrt) – nil heißt „nicht zu sagen“ und wird nie als Ablehnung gewertet.
function Way.Tracking()
    local query = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint
    if type(query) ~= "function" then return nil end
    local ok, on = pcall(query)
    if not ok or ns.IsSecret(on) or type(on) ~= "boolean" then return nil end
    return on
end

-- Blizzards Zielverfolgung (Pfeil und Entfernung zur Markierung) einschalten – nur mit dem Schalter wayTrack (ab Werk
-- aus seit Welle 29, NACH-27: Grundsatz des Nutzers vom 17.11.2026, wörtlich „user muss auf sowas hingewiesen werden, er
-- kann es nutzen muss es aber einschalten“; ohne ihn bleibt der Klick auf Blizzards Markierung) – taint-sicher gefasst (V-183: Forevers
-- Entwickler-Hinweise führen C_SuperTrack.SetSuperTrackedUserWaypoint unter „nicht aus Addon-Code rufen“): nur
-- außerhalb des Kampfes und per pcall. Im Kampf sagt ezMap es im Chat und holt es danach nach, wenn die Markierung
-- dann noch steht (ezCores Reihe „nach dem Kampf“, nur der letzte Wunsch zählt); läuft die Zielverfolgung im Kampf
-- schon, entfällt der Hinweis. Lehnt Blizzard ab, nennt die Meldung den Weg von Hand – auch bei einer stillen
-- Ablehnung: ein blockierter Aufruf wirft keinen Fehler, deshalb sieht ezMap danach nach (Way.Tracking).
-- quiet = true (Welle 23, A2): im Kampf ohne die Chatzeile „nach dem Kampf“ – die Route setzt es beim Weiterrücken
-- nach einer Ernte; nachgeholt wird trotzdem.
-- auto = true (Welle 27, Fund des code-reviewers vor dem Merge, 17.11.2026): ein Aufruf ohne Klick (ezQuests
-- Leveling-Route rückt weiter; den Pfeil gibt es dabei nur mit wayTrack) – im Kampf still wie quiet, und eine
-- Ablehnung meldet ezMap höchstens einmal je Sitzung, sonst stünde sie nach jedem Teilziel im Chat.
-- Rückgabe: true | false, "off" | "noapi" | "combat" | "failed".
function Way.Track(quiet, auto)
    if not ns.Enabled("wayTrack") then return false, "off" end
    if not (C_SuperTrack and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function") then return false, "noapi" end
    if Core.InCombat() then
        -- nach dem Kampf in jedem Fall nachsehen: Blizzard kann die Zielverfolgung beim Ersetzen der Markierung beenden
        ns.AfterCombat(function()
            if C_Map and C_Map.HasUserWaypoint and Core.Bool(C_Map.HasUserWaypoint(), false) then Way.Track(nil, auto) end
        end, "wayTrack")
        if Way.Tracking() == true then return true end      -- der Pfeil steht schon: kein Hinweis nötig
        if not (quiet or auto) then Core.CombatNotice(ns, L.WAY_TRACK_WHAT, "later") end
        return false, "combat"
    end
    local ok = pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    if not ok or Way.Tracking() == false then
        if not (auto and Way.autoTrackFailed) then ns.Print(L.WAY_TRACK_FAILED) end
        if auto then Way.autoTrackFailed = true end
        return false, "failed"
    end
    return true
end

-- Erlaubt das Spiel auf dieser Karte eine eigene Markierung? (Instanzkarten oft nicht.) Ohne Abfrage: ja.
function Way.CanSet(mapID)
    mapID = ns.Num(mapID)
    if not mapID then return false end
    if C_Map and C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then return false end
    return true
end

-- Setzt Blizzards Markierung. x, y von 0 bis 1. quiet = true: im Kampf keine Chatzeile der Zielverfolgung (Way.Track).
-- opts (Welle 27, Leveling-Route in ezQuest; freiwillig): { owner = Kennung (die Markierung gehört diesem Besitzer, bis
-- eine andere sie ersetzt – Way.Owner; Arrive.lua lässt sie bei Ankunft stehen), label = Name des Besitzers für Texte
-- („Leveling-Route“), noHistory = true (kein Eintrag in „Zuletzt“), track = false (nur die Markierung, Blizzards
-- Zielverfolgung bleibt, wie sie ist – Weiterrücken ohne Klick; ein im Kampf wartender Pfeil-Wunsch einer früheren
-- Markierung verfällt, sonst schaltete ezMap nach dem Kampf den Pfeil für diese ein) bzw. "auto" (Zielverfolgung wie
-- Way.Track mit auto, nur mit dem Schalter wayTrack) }. Ohne opts bzw. ohne track: Zielverfolgung, wenn wayTrack an ist.
-- Rückgabe: true oder false, Fehlertext.
function Way.Set(mapID, x, y, title, verbose, quiet, opts)
    opts = type(opts) == "table" and opts or nil
    local function Fail(message)
        if verbose then ns.Print(message) end
        return false, message
    end
    mapID, x, y = ns.Num(mapID), ns.Num(x), ns.Num(y)
    if not (mapID and x and y) then return Fail(L.WAY_BAD) end
    if x < 0 or x > 1 or y < 0 or y > 1 then return Fail(L.WAY_RANGE) end
    if not (C_Map and C_Map.SetUserWaypoint) then return Fail(L.WAY_NO_API) end
    if not Way.CanSet(mapID) then
        return Fail(L.WAY_NOT_HERE:format(ns.MapName(mapID)))
    end
    local point
    if UiMapPoint and UiMapPoint.CreateFromCoordinates then
        point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
    else
        point = { uiMapID = mapID, position = CreateVector2D and CreateVector2D(x, y) or { x = x, y = y } }
    end
    local entry = { map = mapID, x = x, y = y, title = title, t = time() }
    -- vor dem Setzen merken: USER_WAYPOINT_UPDATED kommt sofort und soll den Titel behalten
    local previous = ns.db.way.current
    ns.db.way.current = entry
    local ok, wasSet = pcall(C_Map.SetUserWaypoint, point)
    if not ok or wasSet == false then
        ns.db.way.current = previous
        return Fail(L.WAY_FAILED)
    end
    -- Besitzer nur im Arbeitsspeicher: nach /reload gehört die Markierung niemandem mehr (die Leveling-Route ist dann weg)
    Way.owned = opts and opts.owner ~= nil and { owner = opts.owner, label = opts.label, map = mapID, x = x, y = y } or nil
    -- Zielverfolgung: nur außerhalb des Kampfes, sonst Hinweis (außer quiet) und danach; ohne Klick (opts.track) gar
    -- nicht bzw. ohne wiederholte Meldung (Fund des code-reviewers vor dem Merge, 17.11.2026). track == false verwirft
    -- auch einen wartenden Wunsch aus dem Kampf (Fund des 2. Reviews der Leveling-Route vom 17.11.2026)
    local track = opts and opts.track
    if track == false then
        Core.CancelAfterCombat(ADDON .. ":wayTrack")
    else
        Way.Track(quiet, track == "auto")
    end
    if not (opts and opts.noHistory) then Remember(entry) end
    if verbose then
        local link = Link()
        ns.Print(L.WAY_SET:format(Describe(entry)) .. (link and (" " .. link) or ""))
    end
    return true
end

function Way.Clear(verbose)
    local had = C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
    if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    ns.db.way.current = nil
    Way.owned = nil
    if verbose then ns.Print(had and L.WAY_CLEARED or L.WAY_NONE) end
    return true
end

-- Blizzards Markierung lesen: uiMapID, x, y oder nil
-- Gesperrt oder fehlerhaft: nil statt Fehler – seit der Kartenmarkierung bei Ankunft (Arrive.lua) fragt ein Ticker alle
-- 0,5 s hier nach (Fund des code-reviewers vor dem Merge, 16.11.2026; Leitlinie 6).
local function BlizzardWaypoint()
    if not (C_Map and C_Map.HasUserWaypoint and C_Map.GetUserWaypoint) then return nil end
    if not Core.Bool(Core.Call(C_Map.HasUserWaypoint), false) then return nil end
    local ok, point = pcall(C_Map.GetUserWaypoint)
    if not ok or ns.IsSecret(point) or type(point) ~= "table" then return nil end
    local x, y = Core.Map.XY(point.position)
    local mapID = ns.Num(point.uiMapID)
    if not (mapID and x and y) then return nil end
    return mapID, x, y
end

local function Matches(entry, mapID, x, y)
    return entry ~= nil and entry.map == mapID and math.abs(entry.x - x) < SAME and math.abs(entry.y - y) < SAME
end

-- Wem gehört die gesetzte Markierung? → Besitzer, Name für Texte – oder nil (keine, eine eigene des Spielers oder eine
-- ohne Besitzer). Ersetzt jemand die Markierung (Strg+Klick, /way, ein anderes Addon), gehört sie niemandem mehr.
function Way.Owner()
    local o = Way.owned
    if not o then return nil end
    local mapID, x, y = BlizzardWaypoint()
    if not (mapID and Matches({ map = o.map, x = o.x, y = o.y }, mapID, x, y)) then
        Way.owned = nil
        return nil
    end
    return o.owner, o.label
end

function Way.OwnedBy(owner)
    return owner ~= nil and Way.Owner() == owner
end

-- Aktuelle Markierung (auch eine, die der Spieler per Strg+Klick auf der Karte gesetzt hat).
function Way.Get()
    local mapID, x, y = BlizzardWaypoint()
    if not mapID then return nil end
    local current = ns.db.way.current
    return mapID, x, y, Matches(current, mapID, x, y) and current.title or nil
end

-- Blizzard meldet jede Änderung, auch Strg+Klick auf die Karte und das Entfernen dort.
ns.On("USER_WAYPOINT_UPDATED", function()
    if not ns.db then return end
    local mapID, x, y = BlizzardWaypoint()
    if not mapID then
        ns.db.way.current = nil
        return
    end
    if Matches(ns.db.way.current, mapID, x, y) then return end
    ns.db.way.current = { map = mapID, x = x, y = y, t = time() }
    Remember(ns.db.way.current)
end)

function Way.SetHere(title, verbose)
    local mapID, x, y = ns.PlayerPosition()
    if not mapID then
        if verbose then ns.Print(L.WAY_NO_POSITION) end
        return false, L.WAY_NO_POSITION
    end
    return Way.Set(mapID, x, y, title, verbose)
end

function Way.SetEntry(entry)
    return Way.Set(entry.map, entry.x, entry.y, entry.title, true)
end

-- Markierung als Kartenlink in die Chatzeile (wie Blizzards Rechtsklick auf die Markierung → Link teilen).
function Way.ShareLink()
    local link = Link()
    if not link then return ns.Print(L.WAY_NONE) end
    -- ezCore legt den Link in die Chatzeile (Blizzards Link-Einfügen, sonst Chat öffnen); gesendet wird nie.
    local ok, why = Core.OpenChatWith(link, true)
    if not ok then ns.Print(L.WAY_LINK_FAILED) end
    return ok, why
end

function Way.PrintCurrent()
    local mapID, x, y, title = Way.Get()
    if not mapID then return ns.Print(L.WAY_NONE) end
    local link = Link()
    ns.Print(L.WAY_CURRENT:format(Describe({ map = mapID, x = x, y = y, title = title })) .. (link and (" " .. link) or ""))
end

function Way.PrintHistory()
    local history = ns.db.way.history
    if #history == 0 then return ns.Print(L.WAY_HISTORY_EMPTY) end
    ns.Print(L.WAY_HISTORY)
    for i, entry in ipairs(history) do ns.Print(("  %d. %s"):format(i, Describe(entry))) end
end

---------------------------------------------------------------------------
-- Hinweis an der Weltkarte (ezCores Hinweis-Helfer, Welle 29, NACH-27)
---------------------------------------------------------------------------

-- „Zielverfolgung einschalten“ ist ab Werk aus (Grundsatz des Nutzers vom 17.11.2026). Einmal je Account, an der
-- Weltkarte mit dem Pfeil auf ezMaps Kartenknopf; nicht, solange dort gerade eine Erklärblase von ezMaps Rundgang steht
-- (dann beim nächsten Öffnen). Für die beim Update umgestellten (ns.MigrateOptIn29) sagt der Hinweis das dazu.
function Way.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezMap.wayTrack", {
        owner = ADDON,
        window = "map",
        label = function() return L.OPT_wayTrack end,
        what = function() return L.OPTIN_wayTrack end,
        isOn = function() return ns.Enabled("wayTrack") end,
        enable = function()
            ns.SetSetting("wayTrack", true)
            return ns.Enabled("wayTrack")
        end,
        applies = function() return not (ns.Guide and ns.Guide.Showing and ns.Guide.Showing()) end,
        switchedOff = function() return type(ns.db) == "table" and ns.db.wayTrackOff29Was == true end,
        target = function() return ns.MapButton and ns.MapButton.Get and ns.MapButton.Get() end,
        side = "below",
    })
end
Way.RegisterOptInHint()

---------------------------------------------------------------------------
-- Befehl: /way, /ezway, /ezmap way
---------------------------------------------------------------------------

local WORDS_CLEAR = { reset = true, clear = true, aus = true, off = true, ["löschen"] = true, entfernen = true, weg = true }
local WORDS_HERE = { hier = true, here = true }
local WORDS_LIST = { liste = true, list = true, verlauf = true, history = true, zuletzt = true }

function Way.Help()
    local command = Way.slash or "/ezway"
    for _, line in ipairs(L.WAY_HELP) do ns.Print((line:gsub("%%CMD%%", command))) end
end

-- defaultMap: Karte ohne Zonennamen (Standard: die eigene Zone; im Kartenmenü die gezeigte Karte).
function Way.Command(input, defaultMap)
    input = Core.Trim(input or "")
    local first, rest = input:match("^(%S+)%s*(.-)$")
    local word = (first or ""):lower()
    if input == "" then
        Way.PrintCurrent()
        return Way.Help()
    elseif WORDS_CLEAR[word] and rest == "" then
        return Way.Clear(true)
    elseif WORDS_LIST[word] and rest == "" then
        return Way.PrintHistory()
    elseif WORDS_HERE[word] then
        return Way.SetHere(rest ~= "" and rest or nil, true)
    elseif word == "hilfe" or word == "help" then
        return Way.Help()
    end
    local spec, err = Way.Parse(input)
    if not spec then
        ns.Print(err)
        return Way.Help()
    end
    local mapID = spec.mapID
    if not mapID and spec.zone then
        mapID, err = Way.FindMap(spec.zone)
        if not mapID then return ns.Print(err) end
    end
    mapID = mapID or defaultMap or ns.Num(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    if not mapID then return ns.Print(L.WAY_NO_ZONE) end
    return Way.Set(mapID, spec.x, spec.y, spec.title, true)
end

-- Eingabefenster (Kartenmenü, Einstellungen): Koordinaten auf der gezeigten Karte bzw. in der eigenen Zone.
function Way.Ask(mapID)
    mapID = mapID or ns.Num(C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player"))
    local prompt = mapID and L.WAY_ASK:format(ns.MapName(mapID)) or L.WAY_ASK_NOZONE
    Core.AskText(prompt, "", function(text)
        if text and text ~= "" then Way.Command(text, mapID) end
    end, 80)
end

SLASH_EZMAPWAY1 = "/ezway"
SlashCmdList.EZMAPWAY = function(input) Way.Command(input) end
Way.slash = "/ezway"

-- /way erst beim Einloggen, wenn alle Addons geladen sind: Hat TomTom (oder ein anderes Addon) ihn, bleibt /ezway.
ns.OnReady(function()
    if not ns.Enabled("waySlash") then return end
    local command = Core.AddSlashAlias("EZMAPWAY", 2, { "/way" }, SlashCmdList.EZMAPWAY)
    if command then Way.slash = command end
end)

ns.OnSettingChanged(function(key)
    if key == "waySlash" then ns.Print(L.RELOAD_NEEDED) end
end)

ns.AddStatusLine(function()
    if Way.slash == "/way" then return L.STATUS_WAY_OWN end
    if not ns.Enabled("waySlash") then return L.STATUS_WAY_OFF end
    return L.STATUS_WAY_TAKEN:format(ns.WayElsewhere() or L.ANOTHER_ADDON)
end)
