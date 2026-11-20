local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Automatisch reparieren (vorher ezPanel, Baustein „Reparatur“): beim Händler alles reparieren,
    auf Wunsch zuerst mit Gildengeld; reicht das Gildenlimit nicht, zahlt der Spieler selbst.
    Repariert schon ein anderes Addon automatisch (Erkennung in ezCore: Core.WhoHandles("repair"), etwa
    Leatrix Plus mit „AutoRepairGear“), hält sich ezMerchant heraus und nennt es.
    ezPanel zeigt Haltbarkeit und Kosten weiter an und repariert nur noch, wenn ezMerchant fehlt
    (ezCore.API("ezMerchant")). Die Schalter gelten seit der Einstellungs-Prüfung vom 19.11.2026 für beide Module
    (ezCores gemeinsamer Schaltersatz „vendor“, ns.SHARED in Core.lua); ezPanels frühere Werte kommen einmal dorthin.
    Sichtbar: zwei Häkchen unten im (breiten) Händlerfenster und im Menü am Knopf „Filter“; in Blizzards Breite
    (zwei Spalten) und ohne erweitertes Händlerfenster ein kleines Häkchen ohne Text neben Blizzards
    Reparaturknöpfen (V-124), damit die Funktion immer einen sichtbaren Knopf im Händlerfenster hat.
]]

local R = {}
ns.Repair = R

-- Ausgeführt wird die Reparatur in ezCore (Core.Durability.RepairAll, W-11, V-119, MER-01: eine Fassung für
-- ezMerchant und ezPanels Rückfall – Guthaben der Gildenbank, Nachprüfung, Rest mit eigenem Gold). ezMerchant behält
-- Einstellungen (Auto-Reparatur, Gildengeld, Kosten melden) und Meldungen; RepairAllItems ruft es nicht selbst.
local D = Core.Durability

-- Repariert schon ein anderes Addon automatisch? Dann dessen Name, sonst nil (Liste in ezCore, OtherAddOns.lua).
function R.Other()
    return (ns.OtherFor("repair"))
end

-- Früherer Name (Schnittstelle Leatrix()): true, wenn ein anderes Addon repariert – nicht nur Leatrix Plus.
function R.Leatrix()
    return R.Other() ~= nil
end

-- Kosten beim offenen Händler, nil wenn nichts zu reparieren ist oder er nicht repariert (aus ezCore).
function R.Cost()
    return D.RepairCost()
end

-- Was die Gildenbank für eine Reparatur hergibt – wie Blizzards Händlerfenster: das kleinere aus Tageslimit
-- (-1 = unbegrenzt) und Guthaben der Bank (aus ezCore, Core.Durability.GuildFunds).
function R.GuildFunds()
    return D.GuildFunds()
end

-- Meldung zum endgültigen Ergebnis von Core.Durability.RepairAll (onDone kommt genau einmal: sofort oder nach der
-- Nachprüfung der Gildenreparatur). Erfolg nur mit report, zu wenig Gold immer. Text und Regel aus ezCore
-- (Core.Durability.ReportText, Gesamtreview 18.11.2026, T16-12 – dieselbe Meldung wie ezPanels Rückfall).
local function Report(report, ok, payer, cost, reason)
    local text = D.ReportText(ok, payer, cost, reason, report)
    if text then ns.Print(text) end
end

-- Jetzt reparieren. useGuild nil: Einstellung; quiet: automatisch (meldet nur mit „Kosten im Chat melden“).
-- Automatisch nie im Kampf (Gesamtreview 18.11.2026, T1-6): dann nach dem Kampf, wenn der Händler noch offen ist und
-- die Bedingungen von MERCHANT_SHOW noch gelten (Schalter an, kein anderes Addon repariert; Gegenprüfung P17 – der
-- Schalter unten im Händlerfenster lässt sich auch im Kampf ausschalten). Die Gildenbank folgt dann der Einstellung.
-- → true, wenn repariert wird (mit der Gilde: die Nachprüfung in ezCore läuft noch). Schließt der Händler vor der
-- Nachprüfung, kommt keine Meldung – ob die Gilde gezahlt hat, ist dann nicht mehr sicher.
function R.Now(useGuild, quiet)
    if quiet and ns.InCombat() then
        local asked = useGuild
        ns.AfterCombat(function()
            if D.MerchantOpen() and ns.Enabled("repairAuto") and not R.Other() then
                ns.Try("Repair", R.Now, asked, true)
            end
        end, "repairAuto")
        return false
    end
    if useGuild == nil then useGuild = ns.Enabled("repairGuild") end
    if not D.MerchantOpen() then
        if not quiet then ns.Print(L.REPAIR_NEED_MERCHANT) end
        return false
    end
    local report = not quiet or ns.Enabled("repairReport")
    local ok = D.RepairAll(useGuild == true, function(...)
        -- „nichts zu reparieren“ nur von Hand melden, Erfolg nach repairReport
        local done, _, _, reason = ...
        if not done and reason ~= "money" and quiet then return end
        Report(report, ...)
    end)
    return ok == true
end

ns.On("MERCHANT_SHOW", function()
    if ns.Enabled("repairAuto") and not R.Other() then
        C_Timer.After(0.2, function() ns.Try("Repair", R.Now, nil, true) end)
    end
end)

-- Hinweis am Händler (ezCores Hinweis-Helfer, einmal je Account; Antwort des Nutzers vom 17.11.2026: was ohne Klick
-- Gold kostet, ist ab Werk aus und bekommt einen Hinweis mit Knopf „Einschalten“). repairAuto war schon aus. Nur bei
-- einem Händler, der repariert, und solange kein anderes Addon automatisch repariert.
function R.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezMerchant.repairAuto", {
        owner = ADDON,
        window = "merchant",
        label = function() return L.OPT_repairAuto end,
        what = function() return L.OPTIN_repairAuto end,
        isOn = function() return ns.Enabled("repairAuto") == true end,
        enable = function()
            ns.SetSetting("repairAuto", true)
            return ns.Enabled("repairAuto") == true
        end,
        applies = function()
            return CanMerchantRepair ~= nil and CanMerchantRepair() == true and R.Other() == nil
        end,
        -- Die Übernahme aus ezPanel hat sie ausgeschaltet, weil die Profile dort abwichen (Gegenprüfung P19b)
        switchedOff = function()
            if ns.db ~= nil and type(ns.db.migrated) == "table" and ns.db.migrated.panelRepairMixed == true then
                return true
            end
            local J = Core.Junk
            return J ~= nil and type(J.RepairMixedOff) == "function" and J.RepairMixedOff() == true
        end,
    })
end
R.RegisterOptInHint()

---------------------------------------------------------------------------
-- Häkchen unten im Händlerfenster (nur breit: zwischen Reparatur-Knöpfen und Goldanzeige ist dann Platz)
---------------------------------------------------------------------------

local checks = {}
R.checks = checks

local function NewCheck(key, label, y)
    local check = Core.CreateCheck(MerchantFrame, 22)
    check:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", 0, y)
    check.label = check:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    check.label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    check.label:SetText(label)
    check:SetScript("OnClick", function(self) ns.SetSetting(key, self:GetChecked() and true or false) end)
    check:SetScript("OnEnter", function(self)
        local body = L["OPT_" .. key .. "_TIP"]
        local other = key == "repairAuto" and R.Other()
        if other then body = body .. "\n\n" .. L.REPAIR_OTHER:format(other) end
        Core.ShowTip(self, L["OPT_" .. key], body)
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- gesperrt (ein anderes Addon repariert): der Tooltip nennt den Grund auch dann (T9-7)
    Core.Toolbar.ShowTipWhileDisabled(check)
    check:Hide()
    check.key = key
    checks[key] = check
    return check
end

-- Blizzards Reparaturknopf, neben dem das kleine Häkchen sitzt: der rechteste sichtbare.
local REPAIR_BUTTONS = { "MerchantGuildBankRepairButton", "MerchantRepairAllButton", "MerchantRepairItemButton" }
function R.RepairAnchor()
    for _, name in ipairs(REPAIR_BUTTONS) do
        local b = _G[name]
        if b and b.IsShown and b:IsShown() then return b end
    end
    return nil
end

-- Stehen die beiden Häkchen mit Text unten im breiten Fenster? (Auch für den Knopf „Vorrat auffüllen“ daneben.)
function R.ChecksShown()
    local merchant = ns.Merchant
    local repairs = CanMerchantRepair ~= nil and CanMerchantRepair() == true
    return (merchant and merchant.state.taken and ns.Setting("columns") > 2 and repairs) and true or false, repairs
end

function R.UpdateChecks()
    local auto, guild, small = checks.repairAuto, checks.repairGuild, checks.small
    if not auto then return end
    local merchant = ns.Merchant
    local shown, repairs = R.ChecksShown()
    if small then
        -- Kein Platz für die beiden Häkchen mit Text: ein kleines neben Blizzards Reparaturknöpfen (nur auf dem
        -- Reiter „Händler“, dort stehen die Knöpfe).
        local anchor = not shown and repairs and MerchantFrame:IsShown() and (MerchantFrame.selectedTab or 1) == 1
            and R.RepairAnchor() or nil
        if anchor then
            small:ClearAllPoints()
            small:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
        end
        small:SetShown(anchor ~= nil)
        small:SetChecked(ns.Enabled("repairAuto"))
        small:SetEnabled(R.Other() == nil)
    end
    local x = (merchant and merchant.BaseWidth and merchant.BaseWidth() or 336) + 6
    auto:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", x, 56)
    guild:SetPoint("BOTTOMLEFT", MerchantFrame, "BOTTOMLEFT", x, 32)
    auto:SetShown(shown)
    guild:SetShown(shown and IsInGuild() == true)
    auto:SetChecked(ns.Enabled("repairAuto"))
    guild:SetChecked(ns.Enabled("repairGuild"))
    local other = R.Other() ~= nil
    auto:SetEnabled(not other)
    auto.label:SetFontObject(other and "GameFontDisableSmall" or "GameFontNormalSmall")
end

local UpdateChecksSoon = ns.Throttle(function() R.UpdateChecks() end, 0.1)

ns.OnReady(function()
    if not MerchantFrame then return end
    local auto = NewCheck("repairAuto", L.REPAIR_AUTO_SHORT, 56)
    NewCheck("repairGuild", L.REPAIR_GUILD_SHORT, 32)
    -- das kleine Häkchen: dieselbe Einstellung, ohne Text, eigener Platz in R.checks
    local small = NewCheck("repairAuto", "", 0)
    small:SetSize(20, 20)
    checks.repairAuto, checks.small = auto, small
    ns.Listen("MERCHANT_LAYOUT", R.UpdateChecks)
    -- Ohne erweitertes Händlerfenster meldet Merchant.lua kein Layout: dann über Blizzards Fenster selbst.
    ns.On("MERCHANT_SHOW", function() UpdateChecksSoon() end)
    ns.On("MERCHANT_UPDATE", function() UpdateChecksSoon() end)
    if type(_G.MerchantFrame_Update) == "function" then
        hooksecurefunc("MerchantFrame_Update", function() UpdateChecksSoon() end)
    end
end)

---------------------------------------------------------------------------
-- Einmalige Übernahme der Einstellungen aus ezPanel (ezCore.API("ezPanel").RepairSettings). Seit der
-- Einstellungs-Prüfung vom 19.11.2026 gehen sie in ezCores gemeinsamen Schaltersatz (Core.Junk.AdoptPanelRepair: ein
-- „an“ schaltet ein, ein „aus“ nichts aus); hatte ezMerchant sie schon früher übernommen, sind ezPanels Werte veraltet.
---------------------------------------------------------------------------

local REPAIR_KEYS = { repairAuto = true, repairGuild = true, repairReport = true }

-- Chatzeile nach einer Übernahme mit abweichenden Profilen: Stand, „ezCollection hat es ausgeschaltet“, der Grund (in
-- ezPanel je Charakter verschieden eingestellt, ezMerchant gilt fürs Konto; Gesamtreview 18.11.2026, T4-6) und der Weg
-- zur Einstellung.
-- Die Chatzeile (Text in ezCore, Core.Junk.ReportRepairMixed – eine Fassung für ezMerchant und ezPanel).
function R.ReportMixed()
    local J = Core.Junk
    if J and type(J.ReportRepairMixed) == "function" then J.ReportRepairMixed() end
end

function R.MigrateFromPanel()
    local done = ns.db and ns.db.migrated
    local J = Core.Junk
    if not done or not (J and type(J.AdoptPanelRepair) == "function") then return false end
    if done.panelRepair then
        -- schon früher übernommen (in ezMerchants Werte, die Core.AdoptModuleShared weitergab): ezPanels Werte sind alt
        if type(J.SkipPanelRepair) == "function" then J.SkipPanelRepair() end
        return false
    end
    local panel = Core.API("ezPanel")
    local get = panel and panel.RepairSettings
    if type(get) ~= "function" then return false end   -- ältere ezPanel-Fassung: beim nächsten Login wieder
    local ok, old = pcall(get)
    if not ok or type(old) ~= "table" then return false end
    done.panelRepair = true
    -- ezPanel liefert { autoRepair, guild, report, mixed, autoAnywhere } (Absprache vom 13.11.2026); „auto“ wird
    -- ebenso verstanden. Standen ezPanels Profile verschieden, bleibt es aus: ezCore sagt es einmal im Chat, die Blase
    -- am Händler nennt es ebenfalls (switchedOff); die Häkchen unten im Händlerfenster schalten es sofort ein.
    local auto = old.autoRepair
    if auto == nil then auto = old.auto end
    if J.AdoptPanelRepair(old) and auto == true and ns.Enabled("repairAuto") then ns.Print(L.REPAIR_MIGRATED) end
    R.UpdateChecks()
    return true
end

-- Wer die Reparatur selbst einstellt, bekommt die alten ezPanel-Werte nicht mehr übergestülpt (gemeinsamer Schalter:
-- auch eine Änderung auf ezCores Seite oder in ezPanel kommt hier an, ns.SHARED).
ns.OnSettingChanged(function(key)
    if not REPAIR_KEYS[key] then return end
    if ns.db and ns.db.migrated then ns.db.migrated.panelRepair = true end
    -- Wer die Reparatur selbst umschaltet, hat sie nicht mehr „von ezCollection ausgeschaltet“ (Blase am Händler)
    if key == "repairAuto" and ns.db and ns.db.migrated then ns.db.migrated.panelRepairMixed = nil end
    R.UpdateChecks()
end)

-- ezPanel lädt nach ezMerchant (Alphabet): erst kurz nach dem Login fragen.
ns.OnReady(function() C_Timer.After(1, function() ns.Try("Migrate", R.MigrateFromPanel) end) end)

---------------------------------------------------------------------------
-- Schnittstelle und Status
---------------------------------------------------------------------------

-- an, mitGildengeld, anderes (drei Booleans) und dessen Name: Einstellung von ezMerchant; anderes = true, wenn
-- ein anderes Addon repariert (dann nicht ezMerchant). So liest es ezPanel (local on, guild = AutoRepair()).
ns.API.AutoRepair = function()
    local other = R.Other()
    return ns.Enabled("repairAuto"), ns.Enabled("repairGuild"), other ~= nil, other
end
ns.API.RepairNow = function(useGuild) return R.Now(useGuild, false) end
ns.API.Leatrix = R.Leatrix
ns.API.RepairBy = R.Other

ns.AddStatusLine(function()
    local other = R.Other()
    if other then return L.REPAIR_OTHER:format(other) end
    if not ns.Enabled("repairAuto") then return L.STATUS_REPAIR_OFF end
    return L.STATUS_REPAIR_ON:format(ns.Enabled("repairGuild") and L.STATUS_REPAIR_GUILD or "")
end)
