local _, ns = ...
local Core = ezCore

--[[
    Was ezCore je Charakter selbst erfasst, damit es ohne ezPanel nicht fehlt (Vollprüfung V-079, V-174; vorher
    ezPanel/Blocks/Alts.lua, Currencies.lua, Reputation.lua). Dieselben Felder im Charakter-Datensatz wie bisher;
    ezPanel ist umgestellt und liest nur noch (Core.ItemLevelOf, Core.Currencies, Core.LastFaction). Einzige Ausnahme:
    ezPanels Import eines alten Profils trägt bei Twinks ohne Wert die Gegenstandsstufe einmal nach (Import.lua).

    Gegenstandsstufe (me.ilvl = angelegt, me.ilvlAll = mit Taschen, me.gear = je Platz):
      Core.ItemLevel()               → angelegt (sonst gesamt), gesamt – jetzt, vom Client; nil, wenn unbekannt
      Core.ItemLevelOf(charKey)      → gemerkte Gegenstandsstufe eines Twinks, gesamt, Zeitpunkt
      Core.GearOf(charKey)           → { [platz] = { l = Itemlevel, q = Qualität, i = itemID, s = Kennung } } (nur lesen) oder
                                       nil; s (Core.ItemString) nur, wenn sie mehr sagt als die itemID (Verzauberung, Zusatz)
      Core.SaveGear()                → liest neu; Nachricht GEAR_CHANGED (charKey), wenn sich etwas geändert hat
    Währungen (me.currencies = { [currencyID] = Anzahl }):
      Core.Currencies.Info(id)       → Blizzards CurrencyInfo oder nil (gesperrte Menge gilt als unbekannt)
      Core.Currencies.Known()        → Liste der IDs: Währungsfenster, Currencies.EXTRA, angemeldete, schon gemerkte
      Core.Currencies.Track(id)      → eine ID zusätzlich prüfen (z. B. von einem Modul angeheftet)
      Core.Currencies.Of(charKey)    → { [id] = Anzahl } eines Twinks (nur lesen) oder nil
      Core.Currencies.Total(id, filter) → Summe über alle Twinks, Liste { { key, c, n, isMe } } (meiste zuerst)
      Core.Currencies.Save()         → liest neu; Nachricht CURRENCIES_CHANGED, wenn sich etwas geändert hat
    Zuletzt geänderte Fraktion (me.lastFaction = factionID):
      Core.LastFaction(charKey)      → factionID oder nil
      Core.Factions.Scan()           → vergleicht den Ruf mit dem letzten Stand; Nachricht FACTION_CHANGED (id, differenz)
    Ruf als ein Datensatz (W-12, vorher ezPanel/Blocks/Reputation.lua: ByIndex, ByID, NumFactions, Watched):
      Core.Factions.Info(id)         → { id, name, reaction, min, max, value, isHeader, hasRep, watched, collapsed,
                                         friendText, maxed, secret } oder nil (Name fehlt/gesperrt). Gesperrte Zahlen
                                         sind nil und secret = true – unbekannt, nie gerechnet (Leitlinie 6).
      Core.Factions.List()           → Liste in der Reihenfolge des Ruf-Fensters, Kopfzeilen eingeschlossen; jede
                                         Fraktion trägt header = Name der Kopfzeile darüber und index = ihre Zeile im
                                         Ruf-Fenster (Welle 23c, A47 – stimmt auch, wenn eine Zeile ohne lesbaren
                                         Namen in der Liste fehlt; für SetWatchedFactionIndex)
      Core.Factions.Watched()        → beobachtete Fraktion (Datensatz wie Info) oder nil
      Core.Factions.Count()          → Zahl der Zeilen im Ruf-Fenster
    Bekannte Fraktionen je Charakter (me.knownFactions = { [factionID] = { name, header } }; Frage 12, 14.11.2026:
    „Je Charakter in ezCore“; die Auswahl „welche zeige ich“ bleibt im Profil von ezPanel):
      Core.Factions.Known(charKey)   → die Tabelle (nur lesen) oder nil; ohne charKey dieser Charakter (legt sie an)
      Core.Factions.Remember()       → liest das Ruf-Fenster und merkt jede gesehene Fraktion; → Zahl der neuen
      Core.Factions.MigrateKnown()   → einmal je Charakter: ezPanels Liste (block.cfg.known aus Arbeitsdaten und allen
                                         Profilen) übernehmen; ezPanelDB bleibt unverändert
    Nur Daten – Anzeige, Leiste und Menüs bleiben Sache der Module.
]]

local Now = Core.Now

---------------------------------------------------------------------------
-- Gegenstandsstufe
---------------------------------------------------------------------------

function Core.ItemLevel()
    local fn = rawget(_G, "GetAverageItemLevel")
    if type(fn) ~= "function" then return nil end
    local ok, overall, equipped = pcall(fn)
    if not ok then return nil end
    overall, equipped = Core.Num(overall), Core.Num(equipped)
    return equipped or overall, overall
end

function Core.ItemLevelOf(charKey)
    local c = Core.Char(charKey or Core.charKey)
    if not c then return nil end
    return Core.Num(c.ilvl), Core.Num(c.ilvlAll), Core.Num(c.gearAt)
end

function Core.GearOf(charKey)
    local c = Core.Char(charKey or Core.charKey)
    return c and type(c.gear) == "table" and c.gear or nil
end

local function ReadGear(before)
    local gear = {}
    local ST, ES = Core.SlotText, Core.EquipSlots
    if not (ST and ST.EquippedLevel and ES) then return gear end
    for _, e in ipairs(ES.LIST) do
        if not e.cosmetic then
            local level, quality, link = ST.EquippedLevel("player", e.slot)
            if not level then link = Core.Plain(Core.Call(rawget(_G, "GetInventoryItemLink"), "player", e.slot)) end
            local id, text = Core.ItemID(link), Core.ItemString(link)
            local entry = (level or id) and { l = level, q = quality, i = id, s = id and text ~= "item:" .. id and text or nil }
            -- angelegt, aber die Stufe lädt noch: der gemerkte Eintrag bleibt, sonst wenigstens die Kennung (kein leerer Platz)
            local old = not level and entry and type(before) == "table" and before[e.slot]
            gear[e.slot] = type(old) == "table" and old.i == id and old or entry or nil
        end
    end
    return gear
end

local function SameGear(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for slot, e in pairs(a) do
        local o = b[slot]
        if type(e) ~= "table" or type(o) ~= "table" or e.l ~= o.l or e.q ~= o.q or e.i ~= o.i or e.s ~= o.s then
            return false
        end
    end
    for slot in pairs(b) do
        if a[slot] == nil then return false end
    end
    return true
end

function Core.SaveGear()
    local me = Core.me
    if not me then return false end
    local equipped, overall = Core.ItemLevel()
    local gear = ReadGear(me.gear)
    local changed = false
    if equipped and me.ilvl ~= equipped then me.ilvl, changed = equipped, true end
    if overall and me.ilvlAll ~= overall then me.ilvlAll, changed = overall, true end
    -- Direkt nach dem Anmelden kennt der Client die Ausrüstung manchmal noch nicht: einen leeren Stand nicht über
    -- einen gemerkten schreiben, solange Blizzard zugleich eine Gegenstandsstufe meldet.
    local empty = next(gear) == nil
    if not (empty and equipped and equipped > 0 and type(me.gear) == "table" and next(me.gear) ~= nil) then
        if not SameGear(gear, me.gear) then me.gear, changed = gear, true end
    end
    me.gearAt = Now()
    if changed then Core.Fire("GEAR_CHANGED", Core.charKey) end
    return changed
end

local GearLater = Core.Throttle(function() Core.SaveGear() end, 0.5, Core.name)
ns.On("PLAYER_EQUIPMENT_CHANGED", GearLater)
ns.On("PLAYER_AVG_ITEM_LEVEL_UPDATE", GearLater)

---------------------------------------------------------------------------
-- Währungen
---------------------------------------------------------------------------

local Currencies = {}
Core.Currencies = Currencies

-- Forever-Währungen, die immer geprüft werden (auch wenn ihr Abschnitt im Währungsfenster eingeklappt ist).
-- HERKUNFT (PANEL-11, Leitlinie 10; nachgelesen mit git log -S, 15.11.2026): Die Liste kam mit ezPanel 1.0.0
-- (402420e, 12.11.2026, Kommentar „Forever-Währungen, die Titan kennt“) und zog am 13.11.2026 nach ezCore (cbe6623).
-- Eine Liste aus einem fremden Addon ist kein Beleg; die Nummern gelten nur, soweit der Client sie bestätigt – seit dem
-- 15.11.2026 bestätigt die Client-Tabelle CurrencyTypes des Forever-Clients alle fünf (Namen in EXTRA_INFO).
-- Je Nummer Name und Quelle in Currencies.EXTRA_INFO; /ez test zeigt je Nummer, ob der Client sie kennt (Daten-Zeile
-- „Forever-Währung <Nummer>“). Eine Nummer, die der Client nicht kennt, liefert Currencies.Info nicht (nil) und wird
-- nie gemerkt; nach dem Spieltest wird sie hier gestrichen (ROADMAP ezCore, „Im Spiel prüfen“).
Currencies.EXTRA = { 3402, 3469, 515, 1792, 3468 }
-- Name (deutsch, englisch) und Quelle je Nummer; name = nil heißt: erst der Client nennt ihn.
Currencies.EXTRA_INFO = {
    [1792] = { de = "Ehrenpunkte", en = "Honor Points", verified = true,
        source = "Blizzard: Constants.CurrencyConsts.HONOR_CURRENCY_ID des Forever-Clients (Daten-Probe, Dokumentation der Signaturen, 15.11.2026); Name laut Client-Tabelle CurrencyTypes des Forever-Clients (Produkt wowf, Build 1.60.1.70938, auf wago.tools nachgesehen am 15.11.2026, docs/datengrundlage.md 13.4)" },
    [515] = { de = "Dunkelmond-Gewinnlos", en = "Darkmoon Prize Ticket", verified = true, source = "Client-Tabelle CurrencyTypes des Forever-Clients (Produkt wowf, Build 1.60.1.70938, auf wago.tools nachgesehen am 15.11.2026, docs/datengrundlage.md 13.4)" },
    [3402] = { de = "Händlergunst", en = "Merchant's Favor", verified = true, source = "Client-Tabelle CurrencyTypes des Forever-Clients (Produkt wowf, Build 1.60.1.70938, auf wago.tools nachgesehen am 15.11.2026, docs/datengrundlage.md 13.4)" },
    [3468] = { de = "Rangpunkte", en = "Rank Points", verified = true, source = "Client-Tabelle CurrencyTypes des Forever-Clients (Produkt wowf, Build 1.60.1.70938, auf wago.tools nachgesehen am 15.11.2026, docs/datengrundlage.md 13.4)" },
    [3469] = { de = "Angelaufener Lorenhallreal", en = "Tarnished Undermine Real", verified = true, source = "Client-Tabelle CurrencyTypes des Forever-Clients (Produkt wowf, Build 1.60.1.70938, auf wago.tools nachgesehen am 15.11.2026, docs/datengrundlage.md 13.4)" },
}
local tracked = {}

function Currencies.Info(id)
    id = Core.Num(id)
    local C = C_CurrencyInfo
    if not (id and C and C.GetCurrencyInfo) then return nil end
    local ok, info = pcall(C.GetCurrencyInfo, id)
    if not ok or Core.IsSecret(info) or type(info) ~= "table" then return nil end
    local name = Core.Plain(info.name)
    if type(name) ~= "string" or name == "" then return nil end
    if Core.IsSecret(info.quantity) then return nil end
    return info
end

function Currencies.Track(id)
    id = Core.Num(id)
    if not id then return false end
    tracked[id] = true
    return true
end

local function IdFromLink(link)
    link = Core.Plain(link)
    return type(link) == "string" and tonumber(link:match("currency:(%d+)")) or nil
end

function Currencies.Known()
    local ids, seen = {}, {}
    local function add(id)
        id = Core.Num(id)
        if id and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    local C = C_CurrencyInfo
    if C and C.GetCurrencyListSize and C.GetCurrencyListInfo then
        local okN, size = pcall(C.GetCurrencyListSize)
        for i = 1, okN and Core.Num(size) or 0 do
            local ok, info = pcall(C.GetCurrencyListInfo, i)
            if ok and type(info) == "table" and not Core.IsSecret(info) and not Core.Bool(info.isHeader, false) then
                local id = Core.Num(info.currencyID)
                if not id and C.GetCurrencyListLink then
                    local okL, link = pcall(C.GetCurrencyListLink, i)
                    id = okL and IdFromLink(link) or nil
                end
                add(id)
            end
        end
    end
    for _, id in ipairs(Currencies.EXTRA) do add(id) end
    for id in pairs(tracked) do add(id) end
    local me = Core.me
    if me and type(me.currencies) == "table" then
        for id in pairs(me.currencies) do add(id) end
    end
    return ids
end

function Currencies.Of(charKey)
    local c = Core.Char(charKey or Core.charKey)
    return c and type(c.currencies) == "table" and c.currencies or nil
end

function Currencies.Total(id, filter)
    id = Core.Num(id)
    local list, sum = {}, 0
    if not id then return 0, list end
    for _, entry in ipairs(Core.CharacterList(filter)) do
        local n = type(entry.c.currencies) == "table" and Core.Num(entry.c.currencies[id]) or nil
        if n and n > 0 then
            sum = sum + n
            list[#list + 1] = { key = entry.key, c = entry.c, n = n, isMe = entry.isMe }
        end
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.key < b.key
    end)
    return sum, list
end

function Currencies.Save()
    local me = Core.me
    if not me then return false end
    if type(me.currencies) ~= "table" then me.currencies = {} end
    local changed = false
    for _, id in ipairs(Currencies.Known()) do
        local info = Currencies.Info(id)
        if info then
            local quantity = Core.Num(info.quantity) or 0
            if (Core.Bool(info.discovered, true) ~= false or quantity > 0) and me.currencies[id] ~= quantity then
                me.currencies[id] = quantity
                changed = true
            end
        end
    end
    if changed then Core.Fire("CURRENCIES_CHANGED", Core.charKey) end
    return changed
end

local CurrenciesLater = Core.Throttle(function() Currencies.Save() end, 0.1, Core.name)
ns.On("CURRENCY_DISPLAY_UPDATE", CurrenciesLater)

---------------------------------------------------------------------------
-- Zuletzt geänderte Fraktion
---------------------------------------------------------------------------

local Factions = {}
Core.Factions = Factions

local known = {}       -- factionID → true (auch aus eingeklappten Abschnitten, sobald einmal gesehen)
local snapshot = {}    -- factionID → Ruf beim letzten Vergleich

local function Standing(id)
    local R = C_Reputation
    if R and R.GetFactionDataByID then
        local ok, d = pcall(R.GetFactionDataByID, id)
        if ok and type(d) == "table" and not Core.IsSecret(d) then return Core.Num(d.currentStanding) end
        return nil
    end
    local old = rawget(_G, "GetFactionInfoByID")
    if type(old) == "function" then
        local ok, _, _, _, _, _, value = pcall(old, id)
        return ok and Core.Num(value) or nil
    end
    return nil
end

local function CollectKnown()
    local R = C_Reputation
    if R and R.GetNumFactions and R.GetFactionDataByIndex then
        local okN, n = pcall(R.GetNumFactions)
        for i = 1, okN and Core.Num(n) or 0 do
            local ok, d = pcall(R.GetFactionDataByIndex, i)
            local id = ok and type(d) == "table" and not Core.IsSecret(d) and Core.Num(d.factionID)
            if id and id ~= 0 then known[id] = true end
        end
        return
    end
    local count, info = rawget(_G, "GetNumFactions"), rawget(_G, "GetFactionInfo")
    if type(count) == "function" and type(info) == "function" then
        local okN, n = pcall(count)
        for i = 1, okN and Core.Num(n) or 0 do
            local id = Core.Num((select(15, pcall(info, i))))
            if id and id ~= 0 then known[id] = true end
        end
    end
end

-- Vergleicht den Ruf aller bekannten Fraktionen mit dem letzten Stand. → factionID der zuletzt geänderten oder nil.
-- Der erste Aufruf merkt nur den Stand (nichts gilt als geändert).
function Factions.Scan()
    local me = Core.me
    if not me then return nil end
    CollectKnown()
    if Core.Num(me.lastFaction) then known[me.lastFaction] = true end
    if type(me.knownFactions) == "table" then
        for id in pairs(me.knownFactions) do
            if Core.Num(id) then known[id] = true end
        end
    end
    local changed, delta
    for id in pairs(known) do
        local value = Standing(id)
        if value then
            local before = snapshot[id]
            if before ~= nil and before ~= value then
                -- mehrere zugleich (Rufbonus auf verwandte Fraktionen): die mit der größten Änderung zählt
                local d = value - before
                if not delta or math.abs(d) > math.abs(delta) then changed, delta = id, d end
            end
            snapshot[id] = value
        end
    end
    if changed then
        me.lastFaction = changed
        Core.Fire("FACTION_CHANGED", changed, delta)
    end
    return changed, delta
end

function Core.LastFaction(charKey)
    local c = Core.Char(charKey or Core.charKey)
    return c and Core.Num(c.lastFaction) or nil
end

---------------------------------------------------------------------------
-- Ruf als ein Datensatz (W-12): moderne API mit Rückfall auf die alte
---------------------------------------------------------------------------

local function Field(value)
    if Core.IsSecret(value) then return nil, true end
    return value, false
end

local function Normalize(d)
    if type(d) ~= "table" or Core.IsSecret(d) then return nil end
    local name = d.name
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local f = { name = name, isHeader = Core.Bool(d.isHeader, false) == true, hasRep = Core.Bool(d.isHeaderWithRep, false) == true,
        watched = Core.Bool(d.isWatched, false) == true, collapsed = Core.Bool(d.isCollapsed, false) == true }
    local id = Core.Num(d.factionID)
    f.id = id and id ~= 0 and id or nil
    local secret, s = false, false
    f.reaction, s = Field(d.reaction) secret = secret or s
    f.min, s = Field(d.currentReactionThreshold) secret = secret or s
    f.max, s = Field(d.nextReactionThreshold) secret = secret or s
    f.value, s = Field(d.currentStanding) secret = secret or s
    f.reaction, f.min, f.max, f.value = Core.Num(f.reaction), Core.Num(f.min), Core.Num(f.max), Core.Num(f.value)
    -- Freundschaften (falls der Client sie kennt)
    local G = rawget(_G, "C_GossipInfo")
    if f.id and type(G) == "table" and type(G.GetFriendshipReputation) == "function" then
        local ok, fr = pcall(G.GetFriendshipReputation, f.id)
        if ok and type(fr) == "table" and not Core.IsSecret(fr) and (Core.Num(fr.friendshipFactionID) or 0) ~= 0 then
            local text = fr.reaction
            f.friendText = type(text) == "string" and not Core.IsSecret(text) and text or nil
            local lo, hi, at = fr.reactionThreshold, fr.nextThreshold, fr.standing
            if Core.IsSecret(lo) or Core.IsSecret(hi) or Core.IsSecret(at) then
                secret = true
            else
                f.min = Core.Num(lo) or f.min
                f.max = Core.Num(hi) or f.max
                f.value = Core.Num(at) or f.value
                if hi == nil then f.maxed = true end
            end
        end
    end
    if secret then
        f.secret, f.min, f.max, f.value = true, nil, nil, nil
        return f
    end
    if f.min and f.max and f.max <= f.min then f.maxed = true end
    if f.reaction and f.reaction >= 8 and f.value and f.max and f.value >= f.max - 1 then f.maxed = true end
    return f
end
Factions.Normalize = Normalize

local function Pcall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j, k, l, m, n end
    return nil
end

function Factions.Count()
    local R = rawget(_G, "C_Reputation")
    if type(R) == "table" and R.GetNumFactions then return Core.Num((Pcall(R.GetNumFactions))) or 0 end
    return Core.Num((Pcall(rawget(_G, "GetNumFactions")))) or 0
end

local function ByIndex(i)
    local R = rawget(_G, "C_Reputation")
    if type(R) == "table" and R.GetFactionDataByIndex then return Normalize((Pcall(R.GetFactionDataByIndex, i))) end
    local info = rawget(_G, "GetFactionInfo")
    if type(info) ~= "function" then return nil end
    local name, _, reaction, lo, hi, value, _, _, isHeader, collapsed, hasRep, isWatched, _, id = Pcall(info, i)
    return Normalize({ name = name, reaction = reaction, currentReactionThreshold = lo, nextReactionThreshold = hi,
        currentStanding = value, isHeader = isHeader, isCollapsed = collapsed, isHeaderWithRep = hasRep,
        isWatched = isWatched, factionID = id })
end

function Factions.Info(id)
    id = Core.Num(id)
    if not id or id == 0 then return nil end
    local R = rawget(_G, "C_Reputation")
    if type(R) == "table" and R.GetFactionDataByID then return Normalize((Pcall(R.GetFactionDataByID, id))) end
    local name, _, reaction, lo, hi, value = Pcall(rawget(_G, "GetFactionInfoByID"), id)
    return Normalize({ name = name, reaction = reaction, currentReactionThreshold = lo, nextReactionThreshold = hi,
        currentStanding = value, factionID = id })
end

function Factions.List()
    local list, header = {}, nil
    for i = 1, Factions.Count() do
        local f = ByIndex(i)
        if f then
            f.header = header
            f.index = i
            list[#list + 1] = f
            -- jede Kopfzeile (auch eine mit eigenem Ruf) ist Überschrift der Zeilen darunter
            if f.isHeader then header = f.name end
        end
    end
    return list
end

function Factions.Watched()
    local R = rawget(_G, "C_Reputation")
    if type(R) == "table" and R.GetWatchedFactionData then
        local d = Pcall(R.GetWatchedFactionData)
        if type(d) ~= "table" or Core.IsSecret(d) then return nil end
        local id = Core.Num(d.factionID)
        if not id or id == 0 then return nil end
        return Factions.Info(id) or Normalize(d)
    end
    local name, reaction, lo, hi, value, id = Pcall(rawget(_G, "GetWatchedFactionInfo"))
    if name == nil then return nil end
    return Normalize({ name = name, reaction = reaction, currentReactionThreshold = lo, nextReactionThreshold = hi,
        currentStanding = value, factionID = id, isWatched = true })
end

---------------------------------------------------------------------------
-- Bekannte Fraktionen je Charakter (Frage 12)
---------------------------------------------------------------------------

function Factions.Known(charKey)
    if charKey == nil or charKey == Core.charKey then
        local me = Core.me
        if not me then return nil end
        if type(me.knownFactions) ~= "table" then me.knownFactions = {} end
        return me.knownFactions
    end
    local c = Core.Char(charKey)
    return c and type(c.knownFactions) == "table" and c.knownFactions or nil
end

local function Note(store, id, name, header)
    if not id or type(name) ~= "string" or name == "" then return false end
    local e = store[id]
    local new = type(e) ~= "table"
    if new then
        e = {}
        store[id] = e
    end
    e.name = name
    if type(header) == "string" and header ~= "" then e.header = header end
    return new
end

function Factions.Remember()
    local store = Factions.Known()
    if not store then return 0 end
    local n = 0
    for _, f in ipairs(Factions.List()) do
        if f.id and (not f.isHeader or f.hasRep) then
            known[f.id] = true
            if Note(store, f.id, f.name, f.header) then n = n + 1 end
        end
    end
    return n
end

-- Einmalige Übernahme aus ezPanel (Frage 12): bisher lag die Liste im Profil des Ruf-Bausteins (block.cfg.known,
-- für alle Charaktere gleich). Übernommen wird je Charakter beim ersten Anmelden; ezPanelDB bleibt unverändert.
-- Gesamtreview 18.11.2026, T4-1: nur für Charaktere, die es beim ersten Lauf dieser Regel schon gab – ein später
-- erstellter Twink erbt die eingefrorene Kontoliste nicht (Factions.Remember füllt seine Liste selbst). Der erste Lauf
-- merkt done._at (Zeit) und done.eligible (alle bekannten Charaktere; ein gerade erst angelegter Satz ohne früheres
-- Anmelden – Core.previousLastSeen leer – zählt nicht dazu). Charaktere, die die Übernahme schon hatten (done[key]),
-- bleiben unberührt.
function Factions.MigrateKnown()
    local db, key = Core.db, Core.charKey
    if type(db) ~= "table" or not key then return 0 end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    local done = db.migrated.ezPanelFactions
    if type(done) ~= "table" then
        done = {}
        db.migrated.ezPanelFactions = done
    end
    if done[key] then return 0 end
    if type(done.eligible) ~= "table" then
        done.eligible = {}
        for k, c in pairs(Core.Chars()) do
            if type(c) == "table" and (k ~= key or Core.previousLastSeen ~= nil) then done.eligible[k] = true end
        end
        done._at = time()
    end
    if not done.eligible[key] then
        done[key] = true   -- neuer Charakter: nichts zu übernehmen, auch später nicht
        return 0
    end
    local old = rawget(_G, "ezPanelDB")
    if type(old) ~= "table" then return 0 end   -- ezPanel (noch) nicht da: beim nächsten Anmelden wieder prüfen
    local store = Factions.Known()
    if not store then return 0 end
    done[key] = true
    local n = 0
    local function Take(blocks)
        local cfg = type(blocks) == "table" and blocks.reputation
        local list = type(cfg) == "table" and cfg.known
        if type(list) ~= "table" then return end
        for id, e in pairs(list) do
            id = Core.Num(id)
            if id and id ~= 0 and type(e) == "table" and store[id] == nil and Note(store, id, e.name, e.header) then
                n = n + 1
            end
        end
    end
    Take(old.blocks)
    if type(old.profiles) == "table" then
        for _, profile in pairs(old.profiles) do
            if type(profile) == "table" then Take(profile.blocks) end
        end
    end
    return n
end

local FactionsLater = Core.Throttle(function()
    Factions.Remember()
    Factions.Scan()
end, 1, Core.name)
ns.On("UPDATE_FACTION", FactionsLater)
ns.On("CHAT_MSG_COMBAT_FACTION_CHANGE", FactionsLater)

---------------------------------------------------------------------------
-- Beim Anmelden: erster Stand (Ausrüstung und Währungen kennt der Client erst kurz danach)
---------------------------------------------------------------------------

Core.Listen("CHARS_READY", function()
    C_Timer.After(2, function()
        Currencies.Save()
        local ok, err = pcall(Factions.MigrateKnown)
        if not ok then Core.Error(Core.name, err, "Factions.MigrateKnown") end
        Factions.Remember()
        Factions.Scan()
    end)
    C_Timer.After(3, function() Core.SaveGear() end)
end, "ezCore.CharData")
