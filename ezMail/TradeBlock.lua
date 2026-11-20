local _, ns = ...
local L = ns.L

--[[
    Handel am Briefkasten blockieren: Solange der Briefkasten offen ist, lehnt WoW Handelsanfragen ab
    (Blizzards Einstellung „Handel blockieren“, CVar blockTrades). Beim Schließen gilt wieder die eigene
    Einstellung. Der alte Wert liegt in ezMailDB.tradeRestore, damit auch ein /reload am Briefkasten
    oder ein Absturz nichts dauerhaft verstellt.
]]

local GetValue, SetValue = ezCore.CVar, ezCore.SetCVar

-- Den alten Wert erst vergessen, wenn er wirklich wieder gilt (V-065): ezCore.SetCVar meldet false, wenn der Client
-- das Setzen ablehnt (geschützt, etwa im Kampf). Dann bleibt er gemerkt, und ezMail versucht es nach dem Kampf, beim
-- nächsten Schließen des Briefkastens und beim nächsten Einloggen noch einmal – „Handel blockieren“ bleibt so nie
-- dauerhaft an. → true, wenn nichts mehr offen ist.
local Restore
function Restore()
    local old = ns.db and ns.db.tradeRestore
    if old == nil then return true end
    if SetValue("blockTrades", old) == false then
        if ns.InCombat() then ns.AfterCombat(Restore, "tradeRestore") end
        return false
    end
    ns.db.tradeRestore = nil
    return true
end
ns.TradeBlock = { Restore = Restore }

local mailOpen = false      -- zwischen MAIL_SHOW und MAIL_CLOSED

-- Handel blockieren, solange der Briefkasten offen ist (beim Öffnen und beim Einschalten am offenen Briefkasten –
-- Gegenprüfung P17: „Einschalten“ in ezCores Hinweisblase am Briefkasten wirkt sofort, nicht erst beim nächsten Öffnen).
-- → true, wenn umgestellt wurde.
local function Block()
    if not (mailOpen and ns.S.blockTrades) or ns.db.tradeRestore ~= nil then return false end
    local current = GetValue("blockTrades")
    if current == nil or current == "1" then return false end      -- unbekannt oder schon blockiert
    -- Nur merken, was auch umgestellt wurde: lehnt der Client ab, gibt es nichts zurückzustellen.
    if SetValue("blockTrades", "1") == false then return false end
    ns.db.tradeRestore = current
    return true
end

ns.On("MAIL_SHOW", function()
    mailOpen = true
    Block()
end)
ns.On("MAIL_CLOSED", function()
    mailOpen = false
    Restore()
end)
ns.OnReady(Restore)

ns.OnSettingChanged(function(key)
    if key ~= "blockTrades" then return end
    if ns.S.blockTrades then Block() else Restore() end
end)

-- Hinweis am Briefkasten (ezCores Hinweis-Helfer, einmal je Account; Gesamtreview 18.11.2026, T1-3; Entscheidung 2 des Nutzers vom 18.11.2026: Hinweis auch für Abläufe ohne Klick, die nie
-- ab Werk an waren, sofern sie senden oder Blizzards Zustände umstellen; reine Anzeigen ohne Hinweis):
-- „Handel am Briefkasten blockieren“ stellt Blizzards Einstellung „Handel blockieren“ ohne Klick um.
function ns.RegisterTradeBlockHint()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.RegisterSetting) then return false end
    return Hint.RegisterSetting("ezMail", ns, "blockTrades", { window = "mail" })
end
ns.RegisterTradeBlockHint()

ns.OnStatus(function()
    local line = L.STATUS_TRADE:format(ns.S.blockTrades and L.YES or L.NO, tostring(GetValue("blockTrades")))
    if ns.db and ns.db.tradeRestore ~= nil then line = line .. " · " .. L.STATUS_TRADE_PENDING:format(tostring(ns.db.tradeRestore)) end
    return line
end)
