local _, ns = ...
local L = ns.L

--[[
    Beim Öffnen des Briefkastens (einsammeln, dazu die Absender-Regeln):
      1. Briefe von Absendern mit der Regel „zurückschicken“ gehen zurück (Rules.lua).
      2. Auto-Express (Einstellung, aus): Gold, AH-Verkäufe, AH-Käufe und Briefe vertrauter Absender
         einsammeln – über denselben Runner wie „Alle öffnen“, also nie Nachnahme oder GM-Post und nie
         die frei gehaltenen Taschenplätze.
    Beides erst, wenn der Posteingang geladen ist, und nur einmal je Besuch. Shift beim Öffnen des
    Briefkastens überspringt beides. Ein Klick auf „Stopp“ in der Leiste hält an.
]]

local Express = {}
ns.Express = Express

local START_DELAY = 0.6        -- nach dem ersten MAIL_INBOX_UPDATE: Blizzard füllt die Liste noch

local steps                    -- noch ausstehende Schritte dieses Besuchs
local scheduled = false

local function NextStep()
    if not steps or ns.Runner.IsBusy() then return end
    if not (MailFrame and MailFrame:IsShown()) then
        steps = nil
        return
    end
    while #steps > 0 do
        local step = table.remove(steps, 1)
        if step == "return" then
            local targets = ns.Rules.ReturnTargets()
            if #targets > 0 and ns.Runner.Start("return", targets, { auto = true }) then return end
        elseif step == "collect" and ns.S.autoExpress then
            if ns.Runner.Start("auto", nil, { auto = true }) then return end
        end
    end
    steps = nil
end

-- Läuft beim Öffnen des Briefkastens, sobald der Posteingang da ist (auch zum Testen aufrufbar).
function Express.Run()
    steps = { "return", "collect" }
    NextStep()
end

function Express.Pending() return steps ~= nil end

ns.On("MAIL_SHOW", function()
    steps, scheduled = nil, false
    -- Shift beim Öffnen: diesmal nichts automatisch (wie Blizzards Shift für „ohne Express“).
    Express.skipVisit = IsShiftKeyDown() and true or false
    Express.visitStarted = false
end)

ns.On("MAIL_INBOX_UPDATE", function()
    if Express.visitStarted or Express.skipVisit or scheduled then return end
    if not (MailFrame and MailFrame:IsShown()) then return end
    scheduled = true
    C_Timer.After(START_DELAY, function()
        scheduled = false
        if Express.visitStarted or not (MailFrame and MailFrame:IsShown()) then return end
        -- Noch leer? Dann kommt der Posteingang mit dem nächsten Update.
        if ns.NumMails() == 0 then return end
        Express.visitStarted = true
        ns.Try("Express", Express.Run)
    end)
end)

ns.On("MAIL_CLOSED", function() steps = nil end)

-- Nach jedem Durchlauf den nächsten Schritt; nach einem Stopp des Spielers nichts mehr.
ns.Listen("RUN_CHANGED", function()
    if not steps or ns.Runner.IsBusy() then return end
    if ns.Runner.lastStopped then
        steps = nil
        return
    end
    C_Timer.After(0.3, NextStep)
end)

-- Hinweis am Briefkasten (ezCores Hinweis-Helfer, einmal je Account; Gesamtreview 18.11.2026, T1-3; Entscheidung 2 des Nutzers vom 18.11.2026: Hinweis auch für Abläufe ohne Klick, die nie
-- ab Werk an waren, sofern sie senden oder Blizzards Zustände umstellen; reine Anzeigen ohne Hinweis):
-- „Beim Öffnen einsammeln“ nimmt ohne Klick Gold und Gegenstände aus dem Posteingang.
function Express.RegisterOptInHint()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.RegisterSetting) then return false end
    return Hint.RegisterSetting("ezMail", ns, "autoExpress", { window = "mail" })
end
Express.RegisterOptInHint()

ns.OnStatus(function()
    return L.STATUS_EXPRESS:format(ns.S.autoExpress and L.YES or L.NO, ns.Rules.Count())
end)
