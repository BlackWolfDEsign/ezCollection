local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Kleine Helfer, je ein sichtbarer Schalter auf der Einstellungsseite (der Bereitschafts-Timer ist eine reine Anzeige
    und immer an; Prüfung der Einstellungen vom 19.11.2026, Nr. 28). Eigener Code auf Blizzards Aufrufen und ezCores
    Diensten:
      - Bereitschafts-Timer: Restzeit unter Blizzards Bereitschaftscheck und unter dem PvP-Beitrittsfenster
      - Beschwörung annehmen: nach 10 Sekunden, außer du lehnst vorher ab; nie im Kampf (dann danach)
      - Wiederbelebung annehmen: außer der Helfer steckt selbst im Kampf
      - Duelle und Gruppeneinladungen von Fremden ablehnen (Freunde, Battle.net-Freunde und Gilde dürfen)
    Ist derselbe Schalter in Leatrix Plus an, hält sich ezSocial zurück (ns.Active, Erkennung über Core.WhoHandles).
    Blizzards Dialoge schließt ezSocial danach mit Blizzards eigenem StaticPopup_Hide (ns.HidePopup).
]]

local Auto = {}
ns.Auto = Auto

Auto.SUMMON_DELAY = 10

---------------------------------------------------------------------------
-- Bereitschafts-Timer
---------------------------------------------------------------------------

-- Leiste mit Restzeit unter einem Blizzard-Fenster: ezCores Zeitbalken (Core.NewTimerBar – dieselbe Optik wie die
-- Flugleiste und die Schlachtfeld-Timer, Gesamtreview T9-8), an das Fenster gehängt; Restzeit als Text im Balken.
function Auto.NewTimerBar(owner)
    local bar = Core.NewTimerBar(owner, { role = "normal" })
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 6, -4)
    bar:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", -6, -4)
    -- Tooltip: was die Leiste zeigt und wer sie zeigt (Entscheidung „Tooltips an jedem Teil“; ohne eigenen Schalter
    -- seit der Prüfung der Einstellungen vom 19.11.2026)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self) Core.ShowTip(self, L.READY_TIMER, L.TIMER_TIP) end)
    bar:SetScript("OnLeave", GameTooltip_Hide)
    bar:Hide()
    bar:SetScript("OnUpdate", function(self)
        local left = (self.endsAt or 0) - Core.Uptime()
        if left <= 0 then
            self:Hide()
            return
        end
        self:SetTime(left, self.total)
    end)
    function bar:Start(seconds)
        seconds = Core.Num(seconds)
        if not seconds or seconds <= 0 then self:Hide() return false end
        self.endsAt = Core.Uptime() + seconds
        self.total = seconds
        self:SetTime(seconds, seconds)
        self:Show()
        return true
    end
    return bar
end

local pvpBar, readyBar

local function PvPShown(_, index)
    if not ns.Active("readyTimer") or not _G.PVPReadyDialog then return end
    pvpBar = pvpBar or Auto.NewTimerBar(_G.PVPReadyDialog)
    local left = type(GetBattlefieldPortExpiration) == "function" and Core.Num(GetBattlefieldPortExpiration(index))
    pvpBar:Start(left)
end

local function ReadyCheckOwner()
    local listener = _G.ReadyCheckListenerFrame
    if listener and listener:IsShown() then return listener end
    return _G.ReadyCheckFrame
end

function Auto.ReadyCheck(timeLeft)
    if not ns.Active("readyTimer") then return false end
    local owner = ReadyCheckOwner()
    if not (owner and owner:IsShown()) then return false end
    readyBar = readyBar or Auto.NewTimerBar(owner)
    if readyBar:GetParent() ~= owner then
        readyBar:SetParent(owner)
        readyBar:ClearAllPoints()
        readyBar:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 6, -4)
        readyBar:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", -6, -4)
    end
    return readyBar:Start(timeLeft)
end

ns.On("READY_CHECK", function(_, _, timeLeft)
    -- Blizzard zeigt sein Fenster im selben Ereignis; danach anhängen.
    C_Timer.After(0, function() ns.Try("ReadyTimer", Auto.ReadyCheck, timeLeft) end)
end)
ns.On("READY_CHECK_FINISHED", function() if readyBar then readyBar:Hide() end end)

---------------------------------------------------------------------------
-- Beschwörung annehmen
---------------------------------------------------------------------------

local function SummonPending()
    local api = C_SummonInfo
    local left = api and api.GetSummonConfirmTimeLeft and Core.Num(api.GetSummonConfirmTimeLeft())
    return left ~= nil and left > 0
end

local function Summoner()
    local api = C_SummonInfo
    local name = api and api.GetSummonConfirmSummoner and Core.Plain(api.GetSummonConfirmSummoner())
    local area = api and api.GetSummonConfirmAreaName and Core.Plain(api.GetSummonConfirmAreaName())
    return name, area
end

local summonWaiting = nil     -- Beschwörer, auf dessen Annahme gewartet wird (Kampf)

function Auto.ConfirmSummon(expected)
    if not ns.Active("acceptSummon") or not SummonPending() then return false end
    local name = Summoner()
    if expected and name ~= expected then return false end
    if Core.InCombat() then
        summonWaiting = name or true
        ns.AfterCombat(Auto.SummonAfterCombat, "summon")   -- ezCores Reihe statt eines eigenen Zuhörers
        return false
    end
    summonWaiting = nil
    C_SummonInfo.ConfirmSummon()
    for _, which in ipairs({ "CONFIRM_SUMMON", "CONFIRM_SUMMON_SCENARIO", "CONFIRM_SUMMON_STARTING_AREA" }) do
        ns.HidePopup(which)
    end
    return true
end

ns.On("CONFIRM_SUMMON", function()
    if not ns.Active("acceptSummon") or not (C_SummonInfo and C_SummonInfo.ConfirmSummon) then return end
    local name, area = Summoner()
    ns.Print(L.SUMMON_SOON:format(name or "?", area or "?", Auto.SUMMON_DELAY))
    C_Timer.After(Auto.SUMMON_DELAY, function() ns.Try("Summon", Auto.ConfirmSummon, name) end)
end)

-- Nach dem Kampf (Core.AfterCombat): die im Kampf gemerkte Beschwörung annehmen, wenn sie noch ansteht.
function Auto.SummonAfterCombat()
    if not summonWaiting then return false end
    local expected = summonWaiting ~= true and summonWaiting or nil
    return Auto.ConfirmSummon(expected)
end

---------------------------------------------------------------------------
-- Wiederbelebung annehmen
---------------------------------------------------------------------------

-- Steckt der Helfer selbst im Kampf? Unbekannt oder geheim gilt als ja (dann lieber selbst klicken).
local function HelperInCombat(name)
    if type(UnitAffectingCombat) ~= "function" or type(name) ~= "string" then return false end
    local ok, value = pcall(UnitAffectingCombat, name)
    if not ok then return false end
    return Core.Bool(value, true)
end

function Auto.AcceptResurrect(name)
    if not ns.Active("acceptResurrect") or type(AcceptResurrect) ~= "function" then return false end
    if not Core.Usable(name) or HelperInCombat(name) then return false end
    local delay = type(GetCorpseRecoveryDelay) == "function" and Core.Num(GetCorpseRecoveryDelay()) or 0
    if delay > 0 then
        C_Timer.After(delay + 0.2, function() ns.Try("Resurrect", Auto.AcceptResurrect, name) end)
        return false
    end
    AcceptResurrect()
    for _, which in ipairs({ "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }) do ns.HidePopup(which) end
    return true
end

ns.On("RESURRECT_REQUEST", function(_, name) Auto.AcceptResurrect(name) end)

---------------------------------------------------------------------------
-- Duelle und Einladungen von Fremden ablehnen
---------------------------------------------------------------------------

-- Trägt ein Kontakt (Freund, Battle.net-Freund, Gilde) diesen Vornamen? Nur für Namen ohne Nachnamen.
-- Weiterleitung auf ezCores Vornamen-Verzeichnis (SOCIAL-03): Core.Contacts.FirstNameCount zählt einmal je
-- Neubau des Kontakt-Index, statt bei jedem Duell oder jeder Einladung alle Listen neu abzufragen.
function Auto.SharesFirstName(first)
    if Core.IsSecret(first) or type(first) ~= "string" then return false end
    return (Core.Contacts.FirstNameCount(first) or 0) > 0
end

-- Fremd = in keiner Liste (Freunde, Battle.net, Gilde). Forever nennt in Ereignissen mitunter nur den
-- Vornamen; die Kontakte stehen mit vollem Namen im Index (Vollprüfung V-128). Deshalb zuerst ergänzen
-- (Core.CompleteName: genau ein Kontakt mit diesem Vornamen) – und im Zweifel, wenn mehrere Kontakte so
-- heißen, nicht ablehnen. Alle drei Abfragen lesen ezCores Kontakt-Index; der baut nach einer Kontaktänderung
-- frühestens Core.Contacts.INTERVAL nach dem letzten Neubau neu. Ist er nach den Abfragen noch veraltet (ein
-- eben hinzugekommener Freund oder ein neues Gildenmitglied fehlt womöglich), im Zweifel nicht ablehnen.
function Auto.IsStranger(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return false end
    local full = Core.CompleteName(Core.FullName(name) or name)
    if ns.ContactSource(full) ~= nil then return false end
    if Core.MissingSurname(full) and Auto.SharesFirstName(full) then return false end
    if Core.Contacts.State() == true then return false end
    return true
end

function Auto.Duel(name)
    if not ns.Active("blockDuels") or type(CancelDuel) ~= "function" or not Auto.IsStranger(name) then return false end
    CancelDuel()
    ns.HidePopup("DUEL_REQUESTED")
    ns.Print(L.DUEL_BLOCKED:format(name, Core.SettingsPathText(ns.moduleName or "ezSocial", "OPT_HEADER_AUTO", "OPT_blockDuels", L)))
    return true
end

function Auto.Invite(name)
    if not ns.Active("blockInvites") or type(DeclineGroup) ~= "function" or not Auto.IsStranger(name) then return false end
    DeclineGroup()
    ns.HidePopup("PARTY_INVITE")
    ns.HidePopup("PARTY_INVITE_XREALM")
    ns.Print(L.INVITE_BLOCKED:format(name, Core.SettingsPathText(ns.moduleName or "ezSocial", "OPT_HEADER_AUTO", "OPT_blockInvites", L)))
    return true
end

ns.On("DUEL_REQUESTED", function(_, name) Auto.Duel(name) end)
ns.On("PARTY_INVITE_REQUEST", function(_, name) Auto.Invite(name) end)

---------------------------------------------------------------------------
-- Anmelden
---------------------------------------------------------------------------

local pvpHooked = false
function Auto.HookPvP()
    if pvpHooked or type(PVPReadyDialog_Display) ~= "function" then return pvpHooked end
    pvpHooked = true
    hooksecurefunc("PVPReadyDialog_Display", function(...) ns.Try("PvPTimer", PvPShown, ...) end)
    if _G.PVPReadyDialog then
        _G.PVPReadyDialog:HookScript("OnHide", function() if pvpBar then pvpBar:Hide() end end)
    end
    return true
end

ns.OnReady(function()
    if not Auto.HookPvP() then ns.WhenAddOnLoaded("Blizzard_LFGUtil", Auto.HookPvP) end
end)

-- Hinweis an Blizzards Freundesliste (ezCores Hinweis-Helfer, einmal je Account; Gesamtreview 18.11.2026, T1-3; Entscheidung 2 des Nutzers vom 18.11.2026: Hinweis auch für Abläufe ohne Klick, die nie
-- ab Werk an waren, sofern sie senden oder Blizzards Zustände umstellen; reine Anzeigen ohne Hinweis):
-- Beschwörung und Wiederbelebung annehmen, Duelle und Einladungen von Fremden ablehnen antworten ohne Klick auf eine
-- Anfrage. Der Bereitschafts-Timer ist nur Anzeige und bekommt keinen. Nur, solange kein anderes Addon (heute Leatrix
-- Plus) dieselbe Funktion erledigt.
Auto.OPTIN = { "acceptSummon", "acceptResurrect", "blockDuels", "blockInvites" }
function Auto.RegisterOptInHints()
    local Hint = Core.OptInHint
    if not (Hint and Hint.RegisterSetting) then return false end
    local all = true
    for _, key in ipairs(Auto.OPTIN) do
        all = Hint.RegisterSetting("ezSocial", ns, key, {
            window = "friends",
            applies = function() return ns.HandledBy(key) == nil end,
        }) and all
    end
    return all
end
Auto.RegisterOptInHints()
