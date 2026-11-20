--[[
    Träger der Entdecker-Datenbank (Entwurf docs/archiv/entwurf-entdecker-datenbank.md, Abschnitt 9.1; Frage F3 „Zwei Ordner“).
    Dieses Addon hat keine eigene Funktion: Es trägt nur die SavedVariable ezWorldDB in einer eigenen Datei, damit ein
    Schaden am Weltwissen nie Einstellungen, Charaktere und Tagebücher in ezCoreDB trifft. Es lädt vor ezCore
    (ezCore.toc: OptionalDeps) und hat selbst keine Abhängigkeit. Lesen und Schreiben: ezCore, DB.lua.

    Einzige Aufgabe hier: die Tabelle beim ersten Laden anlegen (ezCore legt einen Träger nie selbst an – sonst
    überschriebe ein späteres Laden frühe Schreibvorgänge). Meldet der Client SAVED_VARIABLES_TOO_LARGE für dieses
    Addon, wird nichts angelegt: eine leere Tabelle überschriebe beim Abmelden die Datei (ezCore meldet es,
    DB_CARRIER_LOST).
    Der Träger lädt vor ezCore, ezCore hört das Ereignis also nicht selbst: der Merker <Addon>TooLarge (eine globale
    Variable, nicht gespeichert) sagt es ihm (DB.lua).
]]

local ADDON = ...
local frame = CreateFrame("Frame")
local tooLarge = false
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("SAVED_VARIABLES_TOO_LARGE")
frame:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON then return end
    if event == "SAVED_VARIABLES_TOO_LARGE" then
        tooLarge = true
        rawset(_G, ADDON .. "TooLarge", true)
        return
    end
    if not tooLarge and type(ezWorldDB) ~= "table" then ezWorldDB = {} end
    self:UnregisterEvent("ADDON_LOADED")
end)
