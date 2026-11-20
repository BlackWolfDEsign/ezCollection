local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Ein-Klick-Makros (Welle 2b, Thema 2; Entscheidung des Nutzers vom 13.11.2026: „Ja, in ezMacro“ – Reiter
    „Ein-Klick“ mit echten Blizzard-Makros, außerhalb des Kampfes mit dem besten Gegenstand aktuell gehalten).

    Die Einträge stehen in Data\OneClick.lua (Essen, Trinken, Verband, Heiltrank, Reittier, Ruhestein). Ihr Text ist
    ein Platzhalter {i:<art>}, den diese Datei bei Dynamic.lua anmeldet; übernommen wird wie jedes andere Makro über
    den Browser (Import.lua: CreateMacro/EditMacro, nur außerhalb des Kampfes).

    Bester Gegenstand je Art – klein und ohne eigene Daten, alles aus ezCore:
      Bestand        Core.ForEachBagItem (normale Taschen), Vorauswahl über Core.ItemClass (Verbrauchsgüter, ohne Server)
      Art            ezCore.Knowledge.Get(link).consumable – ezCores Item-Wissen liest den Tooltip und unterscheidet
                     Essen, Getränk, Essen & Trinken, Trank, Verband, dazu „stellt Gesundheit/Mana her“ und „Buff“
      benutzbar      facts.usableNow ~= false (Klasse, Berufsrang z. B. Erste Hilfe) und facts.minLevel <= Stufe
      Rangfolge      1. ohne Buff (Essen/Trinken: Buff-Essen verbraucht man nicht zum Auffüllen), 2. höchste
                     Mindeststufe, 3. höchste Gegenstandsstufe, 4. kleinste ID (feste Wahl bei Gleichstand)
    Reittier: aus Blizzards Reittiersammlung (C_MountJournal) – gesammelt, hier benutzbar, die mit Stern (Favoriten)
    zuerst, sonst nach Namen. Die Geschwindigkeit nennt der Client nicht; den Stern setzt der Spieler selbst in
    Blizzards Reittierführer (Leitlinie 1: das Original bestimmt).

    Aktuell halten (Einstellung „Ein-Klick-Makros aktuell halten“, OPT_oneClickUpdate): nach Taschen-, Stufen-,
    Gebiets- und Reittier-Änderungen schreibt ezMacro den Text eines übernommenen Ein-Klick-Makros neu, wenn ein
    besserer Gegenstand da ist – nur außerhalb des Kampfes (EditMacro ist geschützt), sonst nach dem Kampf
    (ns.AfterCombat). Geändert wird nur ein Makro, das ezMacro selbst angelegt hat: Nach jedem Übernehmen auf Klick
    (Import.OnApplied) merkt es sich Name, Index und den geschriebenen Text (ezMacroDB.oneClick) – Charakter-Makros
    je Charakter, allgemeine (Konto-)Makros kontoweit im Bereich „account“, damit ein Twink das Makro nicht für fremd
    hält. Gefunden wird das Makro über den Namen, nach Umbenennen über den gemerkten Text: Der Client sortiert Makros
    nach Namen, ein gemerkter Index zeigt nach dem Umbenennen auf ein anderes Makro – darum sucht ezMacro im Bereich
    das eine Makro, in dem noch genau der zuletzt geschriebene Text steht (und der die Form von ezMacro hat, SHAPES).
    Über den Text sucht es nur, wenn unter dem gemerkten Namen kein Makro mehr liegt (umbenannt oder gelöscht): Liegt
    dort eines mit anderem Text, hat der Spieler es geändert – dann gilt auch kein anderes Makro mit gleichem Text.
    Ein fremdes Makro gleichen Namens bleibt unberührt, der Reiter nennt es („Name belegt“); ein Makro, dessen Text
    der Spieler geändert oder das er gelöscht hat, ebenso – ezMacro legt nie ohne Klick neu an. Im Browser angepasste
    Einträge bleiben, wie sie sind.
]]
local OneClick = {}
ns.OneClick = OneClick

local AFTER_KEY = "oneclick.refresh"
local DELAY = 0.5                              -- Sekunden: Taschen-Ereignisse kommen oft in Schüben

local Plain = Core.Plain   -- Wert nur, wenn er nicht geheim ist (ezCore, Leitlinie 2)

local function Num(value) return tonumber(Plain(value)) end

---------------------------------------------------------------------------
-- Gegenstände
---------------------------------------------------------------------------

-- Regeln je Art: test(c) → passt die Art? prefer(c) → bevorzugt (ohne Buff, reine Art)?
local RULES = {
    food = {
        test = function(c) return (c.kind == "food" or c.kind == "foodDrink") and c.restoresHealth == true end,
        prefer = function(c) return c.kind == "food" and not c.buff end,
    },
    drink = {
        test = function(c) return (c.kind == "drink" or c.kind == "foodDrink") and c.restoresMana == true end,
        prefer = function(c) return c.kind == "drink" and not c.buff end,
    },
    bandage = {
        test = function(c) return c.kind == "bandage" end,
    },
    potion = {
        test = function(c) return c.kind == "potion" and c.restoresHealth == true and not c.restoresMana end,
    },
}
OneClick.ITEM_KINDS = { "food", "drink", "bandage", "potion" }

-- a besser als b? Schlüssel { bevorzugt, Mindeststufe, Gegenstandsstufe, -ID }
local function Better(a, b)
    if not b then return true end
    for i = 1, #a do
        if a[i] ~= b[i] then return a[i] > b[i] end
    end
    return false
end

-- Bester Gegenstand einer Art in den Taschen → itemID, facts | nil, Grund ("noItem" | "noKnowledge").
function OneClick.Best(kind)
    local rule = RULES[kind]
    if not rule then return nil, "unknown" end
    local K = Core.Knowledge
    if type(K) ~= "table" or type(K.Get) ~= "function" then return nil, "noKnowledge" end
    local level = Core.PlayerLevel() or 1          -- ezCore: gesperrt oder unbekannt → nil (V-179)
    local consumable = Core.ITEM_CLASS and Core.ITEM_CLASS.Consumable or 0
    local seen, bestID, bestFacts, bestKey = {}, nil, nil, nil
    Core.ForEachBagItem(function(_, _, info)
        local id = type(info) == "table" and Num(info.itemID) or nil
        if not id or seen[id] then return end
        seen[id] = true
        if Core.ItemClass(id) ~= consumable then return end
        local link = Plain(info.hyperlink)
        local facts = K.Get(type(link) == "string" and link or id)
        local c = type(facts) == "table" and facts.consumable or nil
        if type(c) ~= "table" or not rule.test(c) then return end
        if facts.usableNow == false or (Num(facts.minLevel) or 0) > level then return end
        local key = { (rule.prefer and rule.prefer(c)) and 1 or 0, Num(facts.minLevel) or 0, Num(facts.itemLevel) or 0, -id }
        if Better(key, bestKey) then bestID, bestFacts, bestKey = id, facts, key end
    end)
    if not bestID then return nil, "noItem" end
    return bestID, bestFacts
end

local function ItemLines(kind)
    local id, why = OneClick.Best(kind)
    if not id then return nil, why == "noItem" and ("no_" .. kind) or why end
    return ("#showtooltip item:%d\n/use item:%d"):format(id, id)
end

---------------------------------------------------------------------------
-- Reittier
---------------------------------------------------------------------------

-- Reittier aus Blizzards Sammlung → { id, name, icon, favorite } | nil, Grund ("noJournal" | "noMount").
function OneClick.BestMount()
    local journal = rawget(_G, "C_MountJournal")
    if type(journal) ~= "table" or type(journal.GetMountIDs) ~= "function" or type(journal.GetMountInfoByID) ~= "function" then
        return nil, "noJournal"
    end
    local ok, ids = pcall(journal.GetMountIDs)
    if not ok or type(ids) ~= "table" then return nil, "noJournal" end
    local best
    for _, mountID in ipairs(ids) do
        local okInfo, name, _, icon, _, isUsable, _, isFavorite, _, _, hidden, isCollected = pcall(journal.GetMountInfoByID, mountID)
        name, isUsable, isFavorite, hidden, isCollected = Plain(name), Plain(isUsable), Plain(isFavorite), Plain(hidden), Plain(isCollected)
        if okInfo and type(name) == "string" and name ~= "" and isCollected == true and isUsable == true and hidden ~= true then
            local candidate = { id = mountID, name = name, icon = Plain(icon), favorite = isFavorite == true }
            if not best or (candidate.favorite and not best.favorite)
                or (candidate.favorite == best.favorite and candidate.name < best.name) then
                best = candidate
            end
        end
    end
    if not best then return nil, "no_mount" end
    return best
end

local function MountLines()
    local mount, why = OneClick.BestMount()
    if not mount then return nil, why end
    return ("#showtooltip\n/cast [nomounted] %s\n/dismount [mounted]"):format(mount.name)
end

-- Symbol für die Liste, solange der fertige Text keinen Gegenstand nennt (Reittier; die Helfer „Eine Taste“ melden
-- ihr Symbol über OneClick.ICONS an, OneKey.lua) → Symbol | nil.
OneClick.ICONS = {}
function OneClick.Icon(kind)
    local icon = OneClick.ICONS[kind]
    if type(icon) == "function" then return icon() end
    if kind ~= "mount" then return nil end
    local mount = OneClick.BestMount()
    return mount and mount.icon or nil
end

---------------------------------------------------------------------------
-- Platzhalter anmelden
---------------------------------------------------------------------------

for _, kind in ipairs(OneClick.ITEM_KINDS) do
    ns.Dynamic.Register(kind, function() return ItemLines(kind) end)
end
ns.Dynamic.Register("mount", MountLines)

-- Form eines Textes, den ezMacro geschrieben hat; nur so ein Makro wird beim Aktualisieren neu geschrieben. Ein
-- Eintrag ist ein Muster oder eine Liste von Mustern (ein Helfer „Eine Taste“ schreibt je nach Lage verschiedene
-- Formen; OneKey.lua meldet seine hier an).
local ITEM_SHAPE = "^#showtooltip item:%d+\n/use item:%d+$"
OneClick.ITEM_SHAPE = ITEM_SHAPE
OneClick.SHAPES = {
    food = ITEM_SHAPE, drink = ITEM_SHAPE, bandage = ITEM_SHAPE, potion = ITEM_SHAPE,
    mount = "^#showtooltip\n/cast %[nomounted%] [^\n]+\n/dismount %[mounted%]$",
}

---------------------------------------------------------------------------
-- Aktuell halten
---------------------------------------------------------------------------

function OneClick.Entries()
    local list = {}
    for _, entry in ipairs(ns.MACROS) do
        if entry.category == "oneclick" then list[#list + 1] = entry end
    end
    return list
end

local function ShapeOf(entry)
    return type(entry) == "table" and entry.category == "oneclick" and entry.needs and OneClick.SHAPES[entry.needs] or nil
end

-- Hat ein Text die Form (ein Muster oder eines aus der Liste)?
local function FitsShape(body, shape)
    if type(body) ~= "string" then return false end
    if type(shape) == "string" then return body:match(shape) ~= nil end
    for _, pattern in ipairs(type(shape) == "table" and shape or {}) do
        if body:match(pattern) then return true end
    end
    return false
end
OneClick.FitsShape = FitsShape

-- Hält ezMacro diesen Eintrag gerade aktuell? Ein Helfer „Eine Taste“ hat dafür einen eigenen Schalter
-- (entry.setting, z. B. OPT_oneKeyQuest); ist er aus, bleibt sein Makro, wie es ist.
local function SettingOn(entry)
    return not (entry.setting and ns.S and ns.S[entry.setting] == false)
end
OneClick.SettingOn = SettingOn

-- Gedächtnis (ezMacroDB.oneClick), je Bereich eine Tabelle [macroId] = { name, index, body }:
--   [charKey]   Charakter-Makros – je Charakter
--   account     allgemeine (Konto-)Makros – kontoweit (MACRO-23: sonst hielte jeder Twink das Makro für fremd,
--               zeigte „Name belegt“ und hielte es nicht aktuell)
OneClick.ACCOUNT = "account"
local SCOPES = { "account", "char" }   -- Reihenfolge wie beim Client: allgemeine Makros zuerst

-- Gemerkte Ein-Klick-Makros eines Bereichs ("account" | "char") | nil (create: anlegen)
local function Store(scope, create)
    local all = ns.db and ns.db.oneClick
    local key = scope == "account" and OneClick.ACCOUNT or ns.charKey
    if type(all) ~= "table" or not key then return nil end
    local store = all[key]
    if type(store) ~= "table" then
        if not create then return nil end
        store = {}
        all[key] = store
    end
    return store
end

-- Bereich eines Makro-Index und die Indizes eines Bereichs (allgemeine Makros 1 … 120, Charakter-Makros dahinter).
local function ScopeOf(index)
    local _, maxAccount = ns.Import.Counts()
    return index > maxAccount and "char" or "account"
end

local function Range(scope)
    local numAccount, maxAccount, numChar = ns.Import.Counts()
    if scope == "account" then return 1, numAccount end
    return maxAccount + 1, maxAccount + numChar
end

local function MacroAt(index)
    if not index or type(GetMacroInfo) ~= "function" then return nil end
    local name, _, body = GetMacroInfo(index)
    return Plain(name), Plain(body)
end

-- Nach dem Übernehmen auf Klick (Import.OnApplied): dieses Makro hat ezMacro angelegt bzw. nach Rückfrage ersetzt.
-- Ein allgemeines Makro kommt in den Konto-Bereich, ein Charakter-Makro zum Charakter.
function OneClick.Remember(entry, index)
    if not ShapeOf(entry) or not tonumber(index) then return end
    local name, body = MacroAt(index)
    local store = type(name) == "string" and type(body) == "string" and Store(ScopeOf(index), true)
    if not store then return end
    store[entry.id] = { name = name, index = index, body = body }
end

-- Trägt ein anderer Eintrag desselben Bereichs genau dieses Makro (Name und Text)? Zwei Ein-Klick-Makros können
-- denselben Text haben (Essen und Trinken mit demselben „Essen & Trinken“) – das andere gehört dann nicht hierher.
local function ClaimedByOther(store, id, name, body)
    for otherId, other in pairs(store) do
        if otherId ~= id and type(other) == "table" and other.name == name and other.body == body then return true end
    end
    return false
end

-- Das von ezMacro angelegte Makro eines Eintrags in einem Bereich → Index, Eintrag im Gedächtnis | nil.
-- Erst über den Namen. Liegt unter dem Namen im Bereich kein Makro mehr (umbenannt), über den gemerkten Text: das
-- eine Makro des Bereichs, in dem noch genau der zuletzt geschriebene Text steht. Der gemerkte Index hilft nur noch
-- bei mehreren Treffern – der Client sortiert nach Namen, nach dem Umbenennen liegt dort meist ein anderes Makro
-- (MACRO-22). Liegt unter dem gemerkten Namen ein Makro mit anderem Text, hat der Spieler es geändert: Dann zählt
-- auch kein anderes Makro mit gleichem Text – sonst schriebe ezMacro ohne Klick ein fremdes Makro um.
local function LocateIn(entry, scope)
    local shape = ShapeOf(entry)
    local store = shape and Store(scope, false)
    local record = store and store[entry.id]
    if type(record) ~= "table" or type(record.body) ~= "string" then return nil end
    local function Ours(index)
        if not index or ScopeOf(index) ~= scope then return false end
        local _, body = MacroAt(index)
        return type(body) == "string" and body == record.body and FitsShape(body, shape)
    end
    local index = ns.Import.Find(record.name)
    if not Ours(index) then
        local found, count, remembered = nil, 0, tonumber(record.index)
        local byName, changed = nil, false
        local first, last = Range(scope)
        for candidate = first, last do
            local name = MacroAt(candidate)
            if Ours(candidate) then
                if name == record.name then
                    -- gleicher Name, aber nicht das Makro, das der Client zum Namen nennt (derselbe Name im anderen Bereich)
                    byName = byName or candidate
                elseif not ClaimedByOther(store, entry.id, name, record.body) then
                    count = count + 1
                    if not found or candidate == remembered then found = candidate end
                end
            elseif name == record.name then
                changed = true   -- unter dem gemerkten Namen liegt ein Makro mit anderem Text: vom Spieler geändert
            end
        end
        if byName then
            index = byName
        elseif changed or count == 0 or (count > 1 and found ~= remembered) then
            -- vom Spieler geändert, nichts gefunden oder mehrere gleiche Makros und keines am gemerkten Platz:
            -- nicht raten – ezMacro fasst dann keines an
            return nil
        else
            index = found
        end
    end
    record.index = index
    record.name = (MacroAt(index)) or record.name
    return index, record
end

-- Das von ezMacro angelegte Makro eines Eintrags → Index, Eintrag im Gedächtnis, Bereich | nil (allgemeine zuerst).
function OneClick.Locate(entry)
    for _, scope in ipairs(SCOPES) do
        local index, record = LocateIn(entry, scope)
        if index then return index, record, scope end
    end
    return nil
end

-- Gibt es ein Makro mit dem Namen des Eintrags, das ezMacro nicht angelegt hat? (Hinweis „Name belegt“ im Reiter)
function OneClick.NameTaken(entry)
    if not ShapeOf(entry) then return false end
    local index = ns.Import.Find(ns.EntryName(entry))
    if not index then return false end
    return LocateIn(entry, ScopeOf(index)) ~= index
end

-- Übernommene Ein-Klick-Makros, die sich aktualisieren lassen → { { entry, index, body, record } } – je Eintrag
-- das allgemeine und das Charakter-Makro, wenn es beide gibt.
local function Tracked()
    local list = {}
    for _, entry in ipairs(OneClick.Entries()) do
        if ShapeOf(entry) and not ns.IsEdited(entry) and SettingOn(entry) then
            for _, scope in ipairs(SCOPES) do
                local index, record = LocateIn(entry, scope)
                if index then list[#list + 1] = { entry = entry, index = index, body = record.body, record = record } end
            end
        end
    end
    return list
end

-- Einmalige Übernahme des alten Formats (bis Welle 2c lag alles je Charakter, MACRO-23): Ein Eintrag eines
-- allgemeinen Makros zieht in den Konto-Bereich um. Ob ein Eintrag ein allgemeines Makro meint, sagt sein gemerkter
-- Index (allgemeine Makros 1 … 120, Charakter-Makros dahinter) – das gilt für die Einträge aller Charaktere, ein
-- Twink muss nicht auf den Login des Charakters warten, der das Makro angelegt hat. Haben zwei Charaktere dasselbe
-- allgemeine Makro gemerkt (der zweite hat es nach Rückfrage übernommen), bleibt der Eintrag, dessen Text heute im
-- Makro steht. Charakter-Makros bleiben, wo sie sind. Läuft bei jedem Login; danach gibt es nichts mehr
-- umzuhängen. → Anzahl umgehängter Einträge
function OneClick.Migrate()
    local all = ns.db and ns.db.oneClick
    if type(all) ~= "table" or not ns.Import.Available() then return 0 end
    local _, maxAccount = ns.Import.Counts()
    -- Steht der gemerkte Text heute in einem allgemeinen Makro dieses Namens?
    local function Current(record)
        local first, last = Range("account")
        for index = first, last do
            local name, body = MacroAt(index)
            if name == record.name and body == record.body then return true end
        end
        return false
    end
    local moves = {}
    for key, store in pairs(all) do
        if key ~= OneClick.ACCOUNT and type(store) == "table" then
            for id, record in pairs(store) do
                local index = type(record) == "table" and tonumber(record.index)
                if index and index >= 1 and index <= maxAccount and type(record.body) == "string" then
                    moves[#moves + 1] = { store = store, id = id, record = record }
                end
            end
        end
    end
    if #moves == 0 then return 0 end
    local account = Store("account", true)
    if not account then return 0 end
    for _, move in ipairs(moves) do
        local kept = account[move.id]
        if type(kept) ~= "table" or (not Current(kept) and Current(move.record)) then account[move.id] = move.record end
        move.store[move.id] = nil
    end
    return #moves
end

-- Schreibt jedes übernommene Ein-Klick-Makro mit dem besten Gegenstand neu. → Anzahl geänderter Makros |
-- false, "combat" (läuft nach dem Kampf) | false, "off" | false, "missing".
function OneClick.Refresh()
    if not (ns.db and ns.S.oneClickUpdate) then return false, "off" end
    if not ns.Import.Available() then return false, "missing" end
    if ns.InCombat() then
        ns.AfterCombat(OneClick.Refresh, AFTER_KEY)
        return false, "combat"
    end
    local changed = 0
    for _, item in ipairs(Tracked()) do
        local body = (ns.EntryBody(item.entry))
        if body ~= "" and body ~= item.body then
            local index = ns.Import.Rewrite(item.index, body)
            if index then
                -- den neuen Text merken: nur er weist das Makro beim nächsten Mal als das von ezMacro aus
                local name, written = MacroAt(index)
                item.record.index, item.record.name = index, name or item.record.name
                item.record.body = written or body
                changed = changed + 1
            end
        end
    end
    if changed > 0 then ns.SettingChanged("macros") end
    return changed
end

-- Gebündelt nach Ereignissen (Taschen, Stufe, Gebiet, Reittiere, Item-Daten geladen).
local scheduled = false
function OneClick.Schedule()
    if scheduled or not ns.db then return end
    scheduled = true
    C_Timer.After(DELAY, function()
        scheduled = false
        ns.Try("OneClick", OneClick.Refresh)
    end)
end

for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "NEW_MOUNT_ADDED",
    "MOUNT_JOURNAL_USABILITY_CHANGED" }) do
    ns.On(event, OneClick.Schedule)
end

ns.OnReady(function()
    -- Übernehmen auf Klick (auch nach der Rückfrage „ersetzen?“ und beim Ziehen): ab jetzt gehört das Makro ezMacro.
    -- Hier statt beim Laden, weil Import.lua nach dieser Datei geladen wird.
    ns.Import.OnApplied(OneClick.Remember)
    -- altes Gedächtnis (alles je Charakter): Einträge allgemeiner Makros in den Konto-Bereich umhängen
    ns.Try("OneClick", OneClick.Migrate)
    -- ezCores Item-Wissen meldet, wenn Daten eines Gegenstands nachgeladen sind (dann kennt es die Art)
    if Core.Knowledge and type(Core.Knowledge.OnReady) == "function" then Core.Knowledge.OnReady(OneClick.Schedule) end
    OneClick.Schedule()
end)

ns.OnSettingChanged(function(key)
    if key == "oneClickUpdate" then OneClick.Schedule() end
end)

-- Ein vergessener Twink (ezCore.ForgetChar): sein Gedächtnis geht mit. Der Konto-Bereich bleibt – die allgemeinen
-- Makros gehören allen Charakteren.
Core.Listen("CHAR_FORGOTTEN", function(key)
    if key ~= nil and key ~= OneClick.ACCOUNT and ns.db and type(ns.db.oneClick) == "table" then ns.db.oneClick[key] = nil end
end, "ezMacro")

-- „Stand zeigen“: wie viele Ein-Klick-Makros ezMacro aktuell hält
ns.AddStatusLine(function()
    if not ns.db then return {} end
    if not ns.S.oneClickUpdate then return { L.ONECLICK_STATUS_OFF } end
    return { L.ONECLICK_STATUS:format(#Tracked()) }
end)
