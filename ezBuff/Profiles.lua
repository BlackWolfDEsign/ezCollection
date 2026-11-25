local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Profile je Klasse (Welle 23, A2; Entscheidung des Nutzers 13.11.2026 „Profile: Wo es klassenabhängig ist“ –
    ezCombat, ezBuff, ezGear und ezBars über ezCores Profil-Gerüst). Bis hierher galten ezBuffs Schalter für alle
    Charaktere gemeinsam, obwohl vieles an der Klasse hängt (eigene Klassen-Buffs, Gruppe und Durchbuffen,
    Waffenverzauberung, Zurückgeben). ezBuff liefert nur, was ein Profil ist; Liste, Wechsel, Zuordnung (Charakter,
    Klasse, Spezialisierung), Export/Import, Sichern beim Ausloggen, Vergessen eines Charakters (CHAR_FORGOTTEN) und
    die allgemeinen Texte kommen von Core.NewProfiles (über Core.NewSettingsProfiles, gemeinsam mit ezCombat), der Abschnitt der Einstellungsseite von page:Profiles
    (Options.lua, unter „Erweitert“).

    Ein Profil hält
      settings   alle Schalter, Regler und Auswahlfelder der Einstellungsseite (ns.DEFAULTS)
    NICHT im Profil (bleibt je Charakter bzw. accountweit wie bisher):
      - die eigene Wahl je Wahlgruppe und die Segen je Klasse und Spieler (ezBuffDB.chars[charKey]),
      - die gemerkten Tränke (ezBuffDB.elixirs) und die gesehenen Erklärblasen (ezBuffDB.hints).

    Welches Profil gilt (Gerüst): Spezialisierung (wenn an) → Charakter → Klasse → „Standard“. Ausgangsprofil: Beim
    ersten Einloggen mit Profilen werden die bisherigen Einstellungen als „Standard“ gesichert (Profiles.Login) – wer
    nichts zuordnet, merkt keinen Unterschied. Die Arbeitsdaten bleiben ezBuffDB.settings (ns.S); beim Wechsel sichert
    das Gerüst sie unter dem alten Namen und übernimmt die Werte des neuen Profils über Core.ApplySetting (jeder
    geänderte Wert meldet sich wie von Hand umgestellt). Gespeichert (Felder des Gerüsts): ezBuffDB.profiles[name],
    activeProfile (nil = „Standard“), profileFor[charKey | "class:MAGE" | "charKey#Gruppe"], specMode[charKey].
]]

-- Alte Exporte und Sicherungen (von vor der Einstellungs-Prüfung vom 19.11.2026) wie beim Laden umstellen – auf einer
-- Kopie, nur wenn ein entfernter Schlüssel drinsteht (code-reviewer 20.11.2026: sonst brachte ein alter Export mit
-- groupSpells = false und groupMin = 3 die Gruppenfassung zurück; ein neuer Export mit weapon = false bleibt aus).
local function Adopt(settings)
    if type(settings) ~= "table" then return settings end
    local old = false
    for _, key in ipairs(ns.REMOVED_SETTINGS or {}) do
        if settings[key] ~= nil then old = true end
    end
    if not (old and ns.AdoptSettings1911) then return settings end
    local copy = {}
    for key, value in pairs(settings) do copy[key] = value end
    ns.AdoptSettings1911(copy)
    -- Ein Export von vor dem 19.11.2026 stammt sicher aus der Zeit des alten Werkswerts „In Gruppe oder Instanz“:
    -- wie beim Laden auf „Immer“ (Entscheidung des Nutzers vom 23.11.2026, ns.AdoptWhen2311; Review). Neuere Exporte
    -- lassen sich vom selbst gewählten Wert nicht unterscheiden und bleiben.
    if ns.AdoptWhen2311 then ns.AdoptWhen2311(copy) end
    return copy
end

local Profiles = Core.NewSettingsProfiles(ns, { owner = ADDON, kind = "ezBuff.profile", version = 1, adopt = Adopt,
    texts = L, print = ns.Print })
ns.Profiles = Profiles
ns.ImportLegacy = Profiles.Adopted   -- dieselbe Umstellung für „Alles übernehmen“ (ezCores Core.ImportAll)

-- Zeile für /ezbuff status („Profil: Standard“, Text aus ezCore).
function Profiles.StatusLine() return Profiles.StatusText(L.PROFILE_MENU) end

-- Vor den übrigen Aufgaben beim Einloggen (TOC: gleich nach Core.lua), damit die Teile mit den Werten des richtigen
-- Profils starten.
ns.OnReady(function()
    ns.Try("Profiles", Profiles.Login)
end)
