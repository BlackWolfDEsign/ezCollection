local ADDON, ns = ...

--[[
    Instanz- und Raidsperren aller Charaktere.

    Seit Welle 2 erfasst ezCore die Sperren (ezCore.Lockouts, ezCore/Lockouts.lua): Abfrage, Einlesen
    (GetSavedInstanceInfo, GetSavedWorldBossInfo → ezCoreDB.chars[key].lockouts) und die „Instanzen in der
    letzten Stunde“ für den ganzen Account (ezCoreDB.instances; ezPanelDB.instances hat ezCore einmal
    übernommen und es bleibt liegen). ezPanel schreibt nichts mehr selbst und hört auf kein eigenes Ereignis –
    sonst blieben LOCKOUTS_CHANGED und INSTANCES_CHANGED aus, weil ezCore Änderungen an denselben Feldern
    erkennt.

    Diese Datei ist nur noch die Weiterleitung: Alle bisherigen ns.Lockouts-Funktionen bleiben erhalten
    (Leitlinie 8). Die Schnittstelle für andere Module – ezCore.API("ezPanel").Lockouts und .RecentInstances –
    setzt API.lua zusammen (eine Stelle, W-30); sie verweist auf Lockouts.List und Lockouts.RecentInstances hier.
    Neu gezeichnet wird auf ezCores Nachrichten.

    Anzeige: Charaktere-Block (Blocks/Alts.lua). Ob WoW Forever eine Grenze pro Stunde hat, ist offen – sie
    lässt sich im Menü einstellen.
]]

local Core = ezCore
local CL = Core.Lockouts
local Lockouts = {}
ns.Lockouts = Lockouts

---------------------------------------------------------------------------
-- Erfassen (ezCore; nur der gespielte Charakter, die Twinks beim nächsten Einloggen)
---------------------------------------------------------------------------

-- Sperren neu einlesen (ezCore tut das selbst bei UPDATE_INSTANCE_INFO). → true, wenn gelesen wurde
function Lockouts.Scan()
    return CL.Scan()
end

-- Blizzards Abfrage; die Antwort kommt als UPDATE_INSTANCE_INFO. Ohne Angabe wie bisher: sofort fragen
-- (der Aufrufer ist ein Klick im Menü). force = false überlässt ezCore, ob gerade schon jemand gefragt hat.
function Lockouts.Request(force)
    return CL.Request(force ~= false)
end

---------------------------------------------------------------------------
-- Lesen
---------------------------------------------------------------------------

-- Aktive Sperren eines Charakter-Datensatzes (abgelaufene fallen heraus).
function Lockouts.Active(c)
    return CL.Active(c)
end

-- Zahl aller aktiven Sperren der Charaktere, die filter(c, key) auswählt.
function Lockouts.Total(filter)
    return CL.Total(filter)
end

--[[
    Alle aktiven Sperren nach Instanz gebündelt:
      { { name, diff, size, raid, worldBoss, resetAt, chars = { { key, c, lock, isMe } } } }
    Schlachtzüge zuerst, dann Dungeons, dann Weltbosse; Charaktere wie ezCore.CharacterList.
]]
function Lockouts.ByInstance(filter)
    return CL.ByInstance(filter)
end

---------------------------------------------------------------------------
-- Instanzen in der letzten Stunde (Account)
---------------------------------------------------------------------------

-- Anzahl der in der letzten Stunde betretenen Instanzen und Sekunden, bis die älteste herausfällt.
function Lockouts.RecentInstances()
    return CL.Recent()
end

-- Betretene Instanz (Dungeon oder Schlachtzug) merken; dieselbe Instanz desselben Charakters nur einmal.
-- ezCore ruft das selbst beim Betreten der Welt.
function Lockouts.NoteInstance()
    return CL.NoteInstance()
end

-- „<Instanz> wurde zurückgesetzt.“ (INSTANCE_RESET_SUCCESS): der nächste Besuch zählt neu.
function Lockouts.OnSystemMessage(msg)
    return CL.OnSystemMessage(msg)
end

---------------------------------------------------------------------------
-- Neu zeichnen: ezCores Nachrichten statt eigener Ereignisse
---------------------------------------------------------------------------

local function Redraw()
    if ns.ready and ns.QueueUpdate then ns.QueueUpdate("alts") end
end
Core.Listen("LOCKOUTS_CHANGED", Redraw, ADDON)
Core.Listen("INSTANCES_CHANGED", Redraw, ADDON)

---------------------------------------------------------------------------
-- Für andere Module (ezCore.API("ezPanel").Lockouts, angeboten in API.lua) – Weiterleitung auf ezCore.Lockouts
---------------------------------------------------------------------------

-- Aktive Sperren eines Charakters (Schlüssel wie ezCore.charKey; ohne Schlüssel: der gespielte).
-- Liste von { name, diff, raid, size, done, total, resetAt, ext, worldBoss, bosses = { { n, k } } } – nur lesen.
-- Neue Abnehmer nehmen gleich ezCore.Lockouts.List bzw. IsLocked.
function Lockouts.List(charKey)
    return CL.List(charKey)
end
