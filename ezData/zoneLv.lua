-- ezData/zoneLv.lua – erzeugt von tools/merge.lua, nicht von Hand ändern (Ablauf: docs/beitragen.md).
-- Tabelle zoneLv (Schicht seen, Version 1) aus Beiträgen anderer Spieler (DB-N1); je Spieler der neueste Beitrag,
-- ein Satz erst ab 2 Herkünften. Beitragende: 0.
-- Build-Spanne: noch keine Beiträge; geprüft gegen die Client-Tabellen von Build 71037 (Leitlinie 12).
-- Lizenz der Beiträge: ezCollection License 1.0 (Einwilligung je Beitrag, Datei LICENSE); nichts aus fremden Addons.
-- Nur Nummern und Zahlen, Zeitstempel auf den Tag gerundet; keine Namen, GUIDs oder Realms. Leser: ezCore, DB.Ship.
local Core = ezCore
if not (Core and Core.DB and Core.DB.Ship) then return end
Core.DB.Ship("zoneLv", {
 builds = {},
 checked = 71037,
 contributors = 0,
 fmt = 1,
 license = "ezCollection License 1.0",
 life = "seen",
 minOrigins = 2,
 rows = 0,
 v = 1,
}, {})
