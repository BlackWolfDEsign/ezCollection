local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Pfeil „besser“ an Blizzards Ergebniszeilen und Filter „Nur Verbesserungen“ (AUC-09, VP-35, GEAR-06 – W-27, Rest
    von V-125; ezMerchant als Vorbild). Bewertung und Pfeil kommen aus ezGear (ezCore.API("ezGear"): SetUpgradeIcon,
    IsUpgrade), hier wird nichts nachgebaut. Ohne ezGear gibt es weder Pfeil noch Filter.
    Nur Anzeige: der Pfeil sitzt auf ezAuctions eigener Auflage der Zeile (ns.RowOverlay), der Filter blendet
    Zeilen ohne Verbesserung mit einem eigenen Schleier ab – Blizzards Zeilen und Datenlisten bleiben unverändert.
    Gebaut vor dem Spieltest des Pfeils in ezMerchant (Grundsatz 5): Fehlt eine Auskunft, bleibt die Zeile wie bisher.
]]

local Upgrade = {}
ns.Upgrade = Upgrade

local check

-- ezGears Schnittstelle, wenn ezGear läuft und den Pfeil anbietet; sonst nil.
function Upgrade.Gear()
    local gear = Core.API("ezGear")
    if type(gear) == "table" and type(gear.SetUpgradeIcon) == "function" then return gear end
    return nil
end

-- Pfeil an (Schalter upgradeArrow) und ezGear da?
function Upgrade.Active()
    return ns.Enabled("upgradeArrow") and Upgrade.Gear() ~= nil
end

-- Filter „Nur Verbesserungen“ wirksam? Nur zusammen mit dem Pfeil.
function Upgrade.FilterOn()
    return ns.Enabled("upgradeOnly") and Upgrade.Active()
end

-- Link zu einer Ergebniszeile, nur für Ausrüstung (aus Blizzards Gegenstandsdaten der itemID); sonst nil.
function Upgrade.LinkOf(itemKey)
    local itemID = type(itemKey) == "table" and Core.Num(itemKey.itemID)
    if not itemID or not Core.IsEquipment(itemID) then return nil end
    local fn = (C_Item and C_Item.GetItemInfo) or rawget(_G, "GetItemInfo")
    local link = select(2, Core.Call(fn, itemID))
    if Core.IsSecret(link) or type(link) ~= "string" or link == "" then return nil end
    return link
end

-- Laut ezGear besser als das Angelegte? true/false; nil = ezGear fehlt oder die Daten laden noch.
function Upgrade.IsUpgrade(link)
    local gear = Upgrade.Gear()
    if not (gear and link and type(gear.IsUpgrade) == "function") then return nil end
    local ok, up = pcall(gear.IsUpgrade, link)
    if not ok then
        ns.Error(up, "IsUpgrade (ezGear)")
        return nil
    end
    return up
end

-- Eine Ergebniszeile: Pfeil setzen oder leeren, unter dem Filter abblenden. Rückgabe: Erklärzeile für den Tooltip
-- der Zeile (nil, wenn nichts zu sagen ist).
function Upgrade.Mark(overlay, data)
    local gear = Upgrade.Gear()
    local dim = type(overlay) == "table" and overlay.SetDim
    if not gear then
        if dim then overlay:SetDim(false) end
        return nil
    end
    local active = Upgrade.Active()
    local link = active and type(data) == "table" and Upgrade.LinkOf(data.itemKey) or nil
    -- Der Pfeil liegt auf dem Halter der Auflage (links in der Zeile, ns.RowOverlay); eine Marke wie „−5 %“ steht
    -- rechts neben dem gemessenen Pfeil statt darunter (Spielbefund 16.11.2026). Freigehalten wird sein Platz nur,
    -- solange ezGear noch lädt (SetUpgradeIcon gibt dann nil zurück, der Pfeil kommt später) – ohne Pfeil bleibt die
    -- Marke am Rand und rückt nicht in Blizzards Preisanzeige (Gegenprüfung vom 17.11.2026)
    local holder = type(overlay) == "table" and overlay.marks or overlay
    local ok, result = pcall(gear.SetUpgradeIcon, holder, link)
    if not ok then ns.Error(result, "SetUpgradeIcon (ezGear)") end
    if type(overlay) == "table" then
        overlay.markSlot = (ok and link ~= nil and result == nil) or nil
        if overlay.PlaceLabel then overlay:PlaceLabel() end
    end
    local up = link and Upgrade.IsUpgrade(link)
    if dim then overlay:SetDim(Upgrade.FilterOn() and up ~= true) end
    if up == true then return L.UPGRADE_ROW_TIP end
    return nil
end

---------------------------------------------------------------------------
-- Sichtbarer Schalter „Nur Verbesserungen“ unten neben Blizzards Goldanzeige (nur in der Ergebnisliste)
---------------------------------------------------------------------------

function Upgrade.Update()
    if not check then return end
    local mode, browsing = ns.ModeName()
    local show = ns.AuctionHouseShown() and mode == "buy" and browsing == true and Upgrade.Active()
    check:SetShown(show == true)
    if check.SetChecked then check:SetChecked(ns.Enabled("upgradeOnly")) end
end

-- Knopf, solange zu sehen (für Prüfungen).
function Upgrade.Button()
    return check ~= nil and check:IsVisible() and check or nil
end

local function Build()
    local ok, box = pcall(CreateFrame, "CheckButton", "ezAuctionUpgradeOnly", AuctionHouseFrame, "UICheckButtonTemplate")
    if not ok or not box then box = CreateFrame("CheckButton", "ezAuctionUpgradeOnly", AuctionHouseFrame) end
    check = box
    box:SetSize(Core.Style.BUTTON.check, Core.Style.BUTTON.check)   -- Haken (Design-System 2.3; bis Welle 22 22)
    local money = AuctionHouseFrame.MoneyFrameBorder
    if money then
        box:SetPoint("LEFT", money, "RIGHT", 12, 0)
    else
        box:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT", 200, 4)
    end
    local label = Core.Peek(box, "Text")
    if type(label) ~= "table" or not label.SetText then
        label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", box, "RIGHT", 2, 0)
    end
    label:SetText(L.OPT_upgradeOnly)
    box.label = label
    box:SetScript("OnClick", function() ns.SetSetting("upgradeOnly", not ns.Enabled("upgradeOnly")) end)
    box:SetScript("OnEnter", function(self) Core.ShowTip(self, L.OPT_upgradeOnly, L.OPT_upgradeOnly_TIP) end)
    box:SetScript("OnLeave", GameTooltip_Hide)
    box:Hide()
end

local function Redecorate()
    if ns.Buy and ns.Buy.redecorate then ns.Buy.redecorate() end
end

ns.OnAuctionHouse(function()
    Build()
    Upgrade.Update()
end)
ns.Listen("AH_MODE", Upgrade.Update)
ns.Listen("AH_SHOW", Upgrade.Update)
-- Nachgeladene Gegenstandsdaten: Pfeile und Schleier der sichtbaren Zeilen neu (gesammelt)
ns.On("GET_ITEM_INFO_RECEIVED", ns.Throttle(function() if Upgrade.Active() then Redecorate() end end, 0.3))
ns.OnSettingChanged(function(key)
    if key == "upgradeArrow" or key == "upgradeOnly" then
        Upgrade.Update()
        Redecorate()
    end
end)
