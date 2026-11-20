local _, ns = ...
local Core = ezCore

--[[
    Anschluss an ezCores Entdecker-Datenbank (Core.DB; Welle 10, MAP-17, DG-06). Eine Quelle für alle Module: Die
    selbst betretenen Eingänge (Entrances.lua) und die gelernten Flugzeiten (Flights.lua) liegen dort, ezMap liest
    und schreibt sie über ezCores Dienst und Fassaden (Core.Entrances, Core.Flights).

    Übergabe der alten Speicher (ezMapDB.entrances, ezMapDB.flights/flightNames): einmal je Ablage der Datenbank.
    Der Merker ezMapDB.migrated[Gebiet] trägt die Kennung der Ablage (meta.id), in die übergeben wurde – wird die
    Ablage ersetzt, übergibt ezMap noch einmal. Die alten Speicher bleiben liegen. Schreibt ezMap einen alten
    Speicher, ohne dass er übergeben ist (Discovery.Dirty), fällt der Merker weg – so kommt auch das in die Datenbank,
    was in einer Sitzung ohne gespeicherte Ablage gelernt wurde.
      - Ablage gespeichert (Träger da): einmal übergeben, Merker setzen; danach schreibt ezMap die alten Speicher
        nicht mehr (Moved).
      - Ablage nur im Arbeitsspeicher (Verknüpfung fehlt): in jeder Sitzung neu übergeben, kein Merker; ezMap
        schreibt die alten Speicher weiter mit, damit beim Ausloggen nichts verloren geht.
      - Ablage nicht nutzbar (nicht bereit, eingefroren, Träger verloren): ezMap arbeitet wie früher allein mit den
        alten Speichern (Usable() falsch).
    Geschrieben wird über DB.AsOwn: Eingänge und Flugzeiten sind eigene Funktionen von ezMap, die es vor der
    Datenbank gab – sie dürfen auch bei ausgeschaltetem Schalter „Datenbank: Erlebtes sammeln“ schreiben.
]]
local Discovery = {}
ns.Discovery = Discovery

local imports = {}      -- { { what, fn } } in der Reihenfolge der Anmeldung
local session = {}      -- [Gebiet] = Kennung der Ablage, in die in dieser Sitzung schon übergeben wurde

-- Dienst der Datenbank, wenn ezMap ihn nutzen kann; sonst nil.
function Discovery.DB()
    local DB = Core.DB
    if type(DB) ~= "table" or type(DB.Ready) ~= "function" or not DB.Ready() then return nil end
    if DB.Frozen and DB.Frozen() then return nil end
    if DB.CarrierLost and DB.CarrierLost("world") then return nil end
    return DB
end

function Discovery.Usable() return Discovery.DB() ~= nil end

-- Kennung der laufenden Ablage (meta.id) oder nil.
function Discovery.Id()
    local DB = Discovery.DB()
    local meta = DB and DB.Meta and DB.Meta()
    return meta and ns.Num(meta.id) or nil
end

local function Marks()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return db.migrated
end

-- Ist der alte Speicher dieses Gebiets in die gespeicherte Ablage übergeben? Dann schreibt ezMap ihn nicht mehr.
function Discovery.Moved(what)
    local DB = Discovery.DB()
    if not (DB and DB.Persistent and DB.Persistent()) then return false end
    local marks, id = Marks(), Discovery.Id()
    return marks ~= nil and id ~= nil and marks[what] == id
end

-- ezMap hat den alten Speicher dieses Gebiets beschrieben, ohne dass er übergeben war (Ablage nur im
-- Arbeitsspeicher oder Datenbank nicht nutzbar): Merker löschen, damit die nächste gespeicherte Ablage das Neue
-- noch einmal übernimmt. Was die Datenbank schon kennt, überspringen die Übergaben (kein doppeltes Zählen).
function Discovery.Dirty(what)
    local marks = Marks()
    if marks then marks[what] = nil end
end

-- Schreiben als eigene Funktion von ezMap (DB.AsOwn). → Rückgaben des Dienstes oder nil, "off"
function Discovery.Own(fn, ...)
    local DB = Discovery.DB()
    if not DB or type(fn) ~= "function" then return nil, "off" end
    if type(DB.AsOwn) ~= "function" then return fn(...) end
    return DB.AsOwn(fn, ...)
end

-- Übergabe eines alten Speichers anmelden: fn() schreibt ihn in die Datenbank.
function Discovery.AddImport(what, fn)
    imports[#imports + 1] = { what = what, fn = fn }
end

-- Alle fälligen Übergaben ausführen (nach dem Anmelden und wenn ezCore eine neue Ablage meldet). Im Kampf staut der
-- Dienst die Schreibzugriffe; deshalb wartet ezMap auf das Kampfende. → Anzahl der gelaufenen Übergaben
function Discovery.Import()
    local DB = Discovery.DB()
    local id = Discovery.Id()
    if not (DB and id) or type(ns.db) ~= "table" then return 0 end
    if ns.InCombat and ns.InCombat() then
        if ns.AfterCombat then ns.AfterCombat(Discovery.Import, "discoveryImport") end
        return 0
    end
    local persistent = DB.Persistent and DB.Persistent()
    local marks, ran = Marks(), 0
    for _, step in ipairs(imports) do
        if session[step.what] ~= id and marks[step.what] ~= id then
            local ok, err = pcall(step.fn)
            if ok then
                session[step.what] = id
                if persistent then marks[step.what] = id end
                ran = ran + 1
            else
                Core.Error("ezMap", err, "Discovery.Import " .. tostring(step.what))
                session[step.what] = id     -- in dieser Sitzung nicht noch einmal (der Fehler steht in der Liste)
            end
        end
    end
    if ns.Entrances and ns.Entrances.Known then ns.Entrances.Known(true) end
    return ran
end

-- Wie ein neues Anmelden: vergisst, in welche Ablagen in dieser Sitzung schon übergeben wurde (danach zählt allein
-- der Merker ezMapDB.migrated). Für die Prüfungen; im Spiel beginnt jede Sitzung ohnehin leer.
function Discovery.NewSession()
    wipe(session)
    if ns.Entrances and ns.Entrances.NewSession then ns.Entrances.NewSession() end
end

-- Kontext der übergebenen Altdaten: Bit 8 in pt („aus dem Altbestand übernommen“), Build unbekannt (Entwurf 11).
function Discovery.OldContext(seen)
    return { pt = 8, b = 0, t = ns.Num(seen) }
end

-- Nachrichten von ezCore: neue Ablage (Übergabe), geänderte Tabelle „entrance“ (Symbole, Chatzeile,
-- Rückfall-Speicher). Nur „entrance“: Jeder Schreiber eines Eingangs (ezCores Discovery.OnWorld, Entrances.Note, die
-- Übergabe, „Eingänge vergessen“) ändert auch diese Tabelle, und DB_CHANGED kommt höchstens einmal je Bild. Die
-- Tabelle „spot“ schreibt ezCore bei fast jedem Plündern und Ansprechen – das liefe sonst jedes Mal alle Eingänge
-- dreimal durch.
if type(Core.Listen) == "function" then
    Core.Listen("DB_READY", function() ns.Try("Discovery", Discovery.Import) end, "ezMap")
    Core.Listen("DB_CHANGED", function(name)
        if ns.Entrances and name == "entrance" then ns.Try("Entrances", ns.Entrances.OnChanged) end
    end, "ezMap")
end

ns.OnReady(function() ns.Try("Discovery", Discovery.Import) end)
