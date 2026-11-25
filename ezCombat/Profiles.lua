local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Profile (CB-44, Vollprüfung V-110; Entscheidung des Nutzers 13.11.2026: „Profile, wo es klassenabhängig ist“ –
    ezCombat, ezBuff, ezGear, ezBars über ezCores Profil-Gerüst). Bis hierher galten ezCombats Schalter für alle
    Charaktere gemeinsam, obwohl vieles an der Klasse hängt (Combo-Punkte, Totems, Gifte, Energie-Tick, Rotation).
    ezCombat liefert nur, was ein Profil ist; Liste, Wechsel, Zuordnung (Charakter, Klasse, Spezialisierung),
    Export/Import, Sichern beim Ausloggen und die allgemeinen Texte kommen von Core.NewProfiles (über
    Core.NewSettingsProfiles, gemeinsam mit ezBuff), der Abschnitt der
    Einstellungsseite von page:Profiles (Options.lua, unter „Erweitert“).

    Ein Profil hält
      settings   alle Schalter, Regler und Auswahlfelder der Einstellungsseite (ns.DEFAULTS) außer rotationChoice
    NICHT im Profil:
      - rotationChoice: Spiegel der Rotation DIESES Charakters (gemerkt in ezCombatDB.rotations[charKey]); ein
        Profil für mehrere Klassen darf einem Krieger keine Magier-Rotation geben,
      - Anpassungen der Rotationen, Erklärblasen, Lagen der Teile (ezCore.Mover), Blizzards CVars.

    Welches Profil gilt (Gerüst): Spezialisierung (wenn an) → Charakter → Klasse → „Standard“. „Standard“ ist das
    gemeinsame Profil aller Charaktere ohne eigene Zuordnung; die Auswahl auf der Seite gilt für diesen Charakter
    (perChar), das Kästchen „für die Klasse“ für alle Charaktere der Klasse ohne eigene Wahl.
    Ausgangsprofil: Beim ersten Einloggen mit Profilen werden die bisherigen Einstellungen als „Standard“ gesichert
    (Profiles.Login) – wer nichts zuordnet, merkt keinen Unterschied.

    Die Arbeitsdaten bleiben ezCombatDB.settings (ns.S, alle Dateien lesen dort). Beim Wechsel sichert das Gerüst sie
    unter dem alten Namen und übernimmt die Werte des neuen Profils in dieselbe Tabelle – jeder geänderte Wert meldet
    sich wie von Hand umgestellt. „Alles sichern“ (ezCore, Core.ExportAll) nimmt ns.S mit, also die Werte des
    gerade aktiven Profils; die Profile selbst haben ihren eigenen Export (wie bei ezBag, ezPanel, ezBars, ezGear).
    Gespeichert (Felder des Gerüsts): ezCombatDB.profiles[name], activeProfile (nil = „Standard“),
    profileFor[charKey | "class:MAGE" | "charKey#Gruppe"], specMode[charKey].
]]

-- Werte eines Profils von vor der Einstellungs-Prüfung vom 19.11.2026 (alter Export, alte Sicherung) wie beim Laden
-- umstellen – auf einer Kopie, das übergebene Profil bleibt, wie es ist (Gegenprüfung 19.11.2026). Danach die
-- Combo-Punkte (Entscheidung 23.11.2026): ein Text ohne comboTarget stammt von vorher, sein comboScale meint nur das Ziel
-- (ns.AdoptCombo2311). Beide Schritte ändern einen neuen Text nicht.
local function Adopt(settings)
    if type(settings) ~= "table" then return {} end
    local copy = {}
    for key, value in pairs(settings) do copy[key] = value end
    if ns.AdoptSettings1911 then ns.AdoptSettings1911(copy) end
    if ns.AdoptCombo2311 then ns.AdoptCombo2311(copy) end
    return copy
end

local Profiles = Core.NewSettingsProfiles(ns, { owner = ADDON, kind = "ezCombat.profile", version = 1, adopt = Adopt,
    skip = { rotationChoice = true },           -- je Charakter, nicht im Profil (siehe oben)
    texts = L, print = ns.Print })
ns.Profiles = Profiles
-- dieselbe Umstellung für ezCores „Alles übernehmen“ (Core.ImportAll übergibt die Werte des Moduls als Kopie; wie ezBuff)
ns.ImportLegacy = Profiles.Adopted

-- Vor den übrigen Aufgaben beim Einloggen (TOC: gleich nach Core.lua), damit die Teile mit den Werten des richtigen
-- Profils starten.
ns.OnReady(function()
    ns.Try("Profiles", Profiles.Login)
end)

-- Vergessene Twinks (CHAR_FORGOTTEN): ihre Zuordnungen streicht seit Welle 23 (A14) ezCores Profil-Gerüst selbst
-- (P.Forget, Felder specMode und profileFor); das Profil selbst bleibt.

-- /ezk status: welches Profil gilt.
ns.AddStatusLine(function() return Profiles.StatusText(L.STATUS_PROFILE) end)
