local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Seitenreiter „Sendungen“ am Senden-Fenster des Briefkastens (SendMailFrame).
    Erscheint nur, wenn der aktuelle Charakter angeforderte Sendungen an Twinks hat (Shipments.lua).
    Klick: Rückfrage mit der Liste, dann verschickt ezCore.MailQueue alles nacheinander.
    Lage: unten rechts im Seitenreiter-Stapel des Senden-Fensters (ezCore, Core.SideTabs, von unten): ezMails
    Nachsenden-Reiter hat die Zahl 10, ezCraft 20 – ezCraft sitzt also darüber, ohne ezMail ganz unten. Kein Modul
    kennt mehr die Zahlen des anderen (V-143). ezMails Schnell-Anhängen-Reiter laufen von oben nach unten.
]]

local tab
local announced

local function Outgoing() return ns.Shipments.Outgoing() end

local function Refresh()
    if not tab then return end
    local out = Outgoing()
    local show = ns.Enabled("mailTab") and #out > 0 and SendMailFrame ~= nil and SendMailFrame:IsVisible()
    tab:SetShown(show)
    tab.Count:SetText(#out > 0 and #out or "")
    tab:SetEnabled(not ns.Shipments.IsSending())
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.MAILTAB_TITLE)
    for _, s in ipairs(Outgoing()) do
        ns.TipLine(GameTooltip, ns.Shipments.Describe(s), "highlight", true)
    end
    ns.TipLine(GameTooltip, L.MAILTAB_TIP, "hint", true)
    -- gesperrt, solange verschickt wird: der Tooltip sagt warum (T9-7)
    if ns.Shipments.IsSending() then ns.TipLine(GameTooltip, L.MAILTAB_BUSY, "bad", true) end
    GameTooltip:Show()
end

local function SendAll()
    local out = Outgoing()
    if #out == 0 then return end
    local lines = {}
    for _, s in ipairs(out) do lines[#lines + 1] = ns.Shipments.Describe(s) end
    Core.Confirm(L.MAILTAB_CONFIRM:format(table.concat(lines, "\n")), function()
        ns.Shipments.SendNext(true)
    end)
end
ns.SendShipments = SendAll

local function Create()
    if tab or not SendMailFrame then return end
    tab = Core.CreateSideTab(SendMailFrame, { key = "ezCraft.mail", order = 20, from = "bottom", start = 40, owner = ADDON })
    Core.SetIcon(tab.Icon, nil, "Interface\\Icons\\INV_Letter_15")
    tab:SetScript("OnClick", Core.SideTabClick(SendAll))
    tab:SetScript("OnEnter", Tooltip)
    Core.Toolbar.ShowTipWhileDisabled(tab)   -- Tooltip auch gesperrt (T9-7)
    SendMailFrame:HookScript("OnShow", Refresh)
    SendMailFrame:HookScript("OnHide", Refresh)
    Refresh()
end

function ns.MailTab() return tab end

ns.On("MAIL_SHOW", function()
    Create()
    Refresh()
    local out = Outgoing()
    if ns.Enabled("mailTab") and #out > 0 and not announced then
        announced = true
        ns.Print(L.MAILTAB_ANNOUNCE:format(#out))
    end
end)
ns.On("MAIL_CLOSED", function()
    announced = false
    Refresh()
end)
ns.Listen("SHIPMENTS_CHANGED", Refresh)
Core.Listen("MAIL_QUEUE_CHANGED", Refresh, ADDON)
ns.OnSettingChanged(function(key) if key == "mailTab" then Refresh() end end)
