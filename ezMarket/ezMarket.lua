--[[
    Träger der Preis-Schicht (Entwurf docs/archiv/entwurf-entdecker-datenbank.md, Abschnitte 1.5 und 9.1; Frage F3 „Zwei
    Ordner“). Dieses Addon hat keine eigene Funktion: Es trägt nur die SavedVariable ezMarketDB in einer eigenen Datei –
    die Preise sind der größte und kurzlebigste Posten; so lassen sie sich getrennt löschen, und ihr Wachstum trifft
    weder das Weltwissen (ezWorld) noch Einstellungen und Charaktere (ezCoreDB). Es lädt vor ezCore (ezCore.toc:
    OptionalDeps) und hat selbst keine Abhängigkeit. Lesen und Schreiben: ezCore, DBMarket.lua und Prices.lua.

    Einzige Aufgabe hier: die Tabelle beim ersten Laden anlegen (ezCore legt einen Träger nie selbst an – sonst
    überschriebe ein späteres Laden frühe Schreibvorgänge). Meldet der Client SAVED_VARIABLES_TOO_LARGE für dieses
    Addon, wird nichts angelegt: eine leere Tabelle überschriebe beim Abmelden die Datei (ezCore meldet es).
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
    if not tooLarge and type(ezMarketDB) ~= "table" then ezMarketDB = {} end
    self:UnregisterEvent("ADDON_LOADED")
end)
