local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Freundes- und Gildenliste in Blizzards eigenen Fenstern:
      - Freunde (FriendsFrame): Name in Klassenfarbe, Stufe nach deiner Stufe gefärbt, Notiz in der Infozeile
      - Battle.net-Freunde in WoW Forever: Charakter in Klassenfarbe mit Stufe; die Twinks (jeder Charakter, mit
        dem ein Freund online war – ezCore merkt sie sich, Core.BNAlts) unter Blizzards Freundes-Tooltip
      - Gilde (Gemeinschaften-Fenster, lädt bei Bedarf): Stufe nach deiner Stufe gefärbt (Namen färbt Blizzard)
      - je Freund ein Knopf „Gespräch“ mit Ungelesen- und Warteschlangen-Zahl aus ezChat (Talk.lua)
    Bekannte Spieler und Twinks kommen aus ezCore (Contact, BNAlts, FullName). Nur hooksecurefunc/HookScript.
]]

local Friends = {}
ns.Friends = Friends

local BUTTON_BNET = _G.FRIENDS_BUTTON_TYPE_BNET or 2
local BUTTON_WOW = _G.FRIENDS_BUTTON_TYPE_WOW or 3

local Call = Core.Call

-- „Stufe 60 Krieger“ in der Farbe der Stufe (Blizzards Vorlage FRIENDS_LEVEL_TEMPLATE).
local function LevelClassText(level, className)
    local template = _G.FRIENDS_LEVEL_TEMPLATE or L.FRIENDS_LEVEL_TEMPLATE
    local ok, text = pcall(string.format, template, level, className or "")
    if not ok then text = ns.LevelText(level) end
    return ns.Colored(text, ns.LevelRGB(level))
end

---------------------------------------------------------------------------
-- Twinks der Battle.net-Freunde
---------------------------------------------------------------------------

-- Charakter eines Battle.net-Freundes, der gerade WoW Forever spielt: name, class, level, area – sonst nil.
-- Ob er in diesem Spiel online ist, entscheidet ezCore (Core.BNCharacter); der Name ist der, den Blizzards
-- Freundesliste zeigt (zum Einfärben dort).
function Friends.GameCharacter(accountInfo)
    if not Core.BNCharacter(accountInfo) then return nil end
    local game = accountInfo.gameAccountInfo
    local name = Core.Plain(game.characterName)
    if type(name) ~= "string" or name == "" then return nil end
    return name, Core.ClassOfGUID(game.playerGuid), Core.Num(game.characterLevel), Core.Plain(game.areaName)
end

-- BattleTag des Freundes (ezCore), sonst nil.
local function TagOf(accountInfo)
    return type(accountInfo) == "table" and Core.BNTagOf(accountInfo.bnetAccountID) or nil
end

-- Merken übernimmt ezCore selbst (beim Anmelden und bei Battle.net-Änderungen, immer); ezSocial zeigt sie immer an,
-- einen Schalter „friendAlts“ gibt es seit der Prüfung der Einstellungen vom 19.11.2026 nicht mehr. Beide Funktionen bleiben als Weiterleitung; ezSocial ruft sie
-- nicht mehr auf.
--   RememberAll() → Anzahl der gerade erfassten Charaktere (ezCores eigene Erfassung)
--   Remember(info) → true, wenn der Freund gerade in diesem Spiel online ist und ezCore ihn damit kennt
function Friends.RememberAll()
    local contacts = Core.Contacts
    return contacts and type(contacts.RememberAlts) == "function" and contacts.RememberAlts() or 0
end

-- Twinks eines Freundes (BattleTag) ohne den gerade gespielten (voller Name), zuletzt gesehene zuerst:
-- { { name, class, level, seen } … } aus ezCore (Core.BNAlts).
function Friends.Alts(battleTag, except)
    return Core.BNAlts(battleTag, except)
end

---------------------------------------------------------------------------
-- Freundesliste
---------------------------------------------------------------------------

-- Knopf „Gespräch“ (Talk.lua) einer Zeile: auf dem Platz von Blizzards Spielsymbol (bei WoW-Freunden frei),
-- sonst links davon; senkrecht mittig wie das Symbol. Bei Battle.net-Freunden setzt Blizzard den Knopf
-- „Beschwören“ (Freund werben) auf denselben Platz – dann links davon. Angelegt erst, wenn ezChat da ist.
local talkButtons = setmetatable({}, { __mode = "k" })

local function Shown(region) return region ~= nil and region:IsShown() and region or nil end

local function SetTalk(button, name, bn, label)
    local talk = talkButtons[button]
    if not talk then
        if not (name and ns.Talk.Enabled()) then return end
        talk = ns.Talk.Button(button, 20)
        talkButtons[button] = talk
    end
    talk:ClearAllPoints()
    local taken = Shown(ns.Region(button.gameIcon)) or (bn and Shown(ns.Region(button.summonButton)))
    if taken then
        talk:SetPoint("RIGHT", taken, "LEFT", -1, 0)
    else
        talk:SetPoint("RIGHT", button, "RIGHT", -26, 0)
    end
    ns.Talk.Set(talk, name, bn, label)
end
Friends.TalkButton = function(button) return talkButtons[button] end

function Friends.DecorateButton(button, elementData)
    if not button or not ns.Region(button.name) then return end
    local buttonType = type(elementData) == "table" and elementData.buttonType or button.buttonType
    local id = type(elementData) == "table" and elementData.id or button.id
    if buttonType ~= BUTTON_WOW and buttonType ~= BUTTON_BNET then SetTalk(button, nil) end
    if buttonType == BUTTON_WOW and C_FriendList and C_FriendList.GetFriendInfoByIndex then
        local info = Call(C_FriendList.GetFriendInfoByIndex, id)
        if type(info) ~= "table" then SetTalk(button, nil) return end
        local name = Core.Plain(info.name)
        -- Gespräch auch mit Freunden, die offline sind (ezChat hebt Nachrichten bis dahin auf)
        SetTalk(button, type(name) == "string" and name or nil, false, name)
        if ns.Enabled("colors") and info.connected and type(name) == "string" then
            local class = Core.ClassOfGUID(info.guid)
            local level = Core.Num(info.level)
            local shown = class and Core.ClassText(name, class) or name
            button.name:SetText(level and (shown .. ", " .. LevelClassText(level, Core.Plain(info.className))) or shown)
        end
        local note = Core.Plain(info.notes)
        if ns.Enabled("friendNotes") and type(note) == "string" and note ~= "" and ns.Region(button.info) then
            button.info:SetText((button.info:GetText() or "") .. "  " .. Core.Grey(note))
        end
    elseif buttonType == BUTTON_BNET and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        local info = Call(C_BattleNet.GetFriendAccountInfo, id)
        if type(info) ~= "table" then SetTalk(button, nil) return end
        local tag = TagOf(info)
        SetTalk(button, tag, true, Core.Plain(info.accountName) or (tag and tag:match("^(.-)#")))
        local charName, class, level = Friends.GameCharacter(info)
        if ns.Enabled("colors") and charName then
            local text = button.name:GetText()
            if type(text) == "string" and text:find(charName, 1, true) then
                local colored = class and Core.ClassText(charName, class) or charName
                if level then colored = colored .. " " .. ns.Colored(level, ns.LevelRGB(level)) end
                button.name:SetText((text:gsub(Core.EscapePattern(charName), (colored:gsub("%%", "%%%%")), 1)))
            end
        end
        local note = Core.Plain(info.note)
        if ns.Enabled("friendNotes") and type(note) == "string" and note ~= "" and ns.Region(button.info) then
            button.info:SetText((button.info:GetText() or "") .. "  " .. Core.Grey(note))
        end
    end
end

-- Kleiner Tooltip unter Blizzards Freundes-Tooltip: die übrigen Charaktere des Freundes.
local altTip
local function AltTooltip()
    if altTip then return altTip end
    altTip = CreateFrame("GameTooltip", "ezSocialAltTooltip", UIParent, "GameTooltipTemplate")
    return altTip
end

function Friends.ShowAlts(button)
    if not button or button.buttonType ~= BUTTON_BNET then return false end   -- immer (Prüfung vom 19.11.2026, Nr. 27)
    local info = C_BattleNet and Call(C_BattleNet.GetFriendAccountInfo, button.id)
    local tag = TagOf(info)
    if not tag then return false end
    local alts = Friends.Alts(tag, Core.BNCharacter(info))
    if #alts == 0 then return false end
    local tip = AltTooltip()
    local owner = (_G.FriendsTooltip and _G.FriendsTooltip:IsShown()) and _G.FriendsTooltip or button
    tip:SetOwner(owner, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    tip:AddLine(L.ALTS_TITLE)
    for _, alt in ipairs(alts) do
        local short = Core.ShortName(alt.name)
        local name = alt.class and Core.ClassText(short, alt.class) or short
        local right = alt.level and ns.Colored(ns.LevelText(alt.level), ns.LevelRGB(alt.level)) or ""
        tip:AddDoubleLine(name, right .. "  " .. Core.Grey(Core.Ago(alt.seen)))
    end
    tip:Show()
    return true
end

function Friends.HideAlts()
    if altTip then altTip:Hide() end
end

local hookedButtons = setmetatable({}, { __mode = "k" })

local function HookButton(button)
    if hookedButtons[button] or not button.HookScript then return end
    hookedButtons[button] = true
    button:HookScript("OnEnter", function(self) ns.Try("FriendAlts", Friends.ShowAlts, self) end)
    button:HookScript("OnLeave", Friends.HideAlts)
end

local friendsHooked = false
function Friends.HookFriends()
    if friendsHooked or type(FriendsFrame_UpdateFriendButton) ~= "function" then return friendsHooked end
    friendsHooked = true
    hooksecurefunc("FriendsFrame_UpdateFriendButton", function(button, elementData)
        if button then HookButton(button) end
        ns.Try("Friends", Friends.DecorateButton, button, elementData)
    end)
    return true
end

---------------------------------------------------------------------------
-- Gildenliste (Blizzard_Communities)
---------------------------------------------------------------------------

function Friends.DecorateGuildEntry(entry)
    if not ns.Enabled("colors") or not entry or not ns.Region(entry.Level) or type(entry.GetMemberInfo) ~= "function" then
        return
    end
    local info = entry:GetMemberInfo()
    if type(info) ~= "table" then return end
    local offline = Enum and Enum.ClubMemberPresence and Enum.ClubMemberPresence.Offline
    if info.presence == nil or (offline ~= nil and info.presence == offline) then return end
    local level = Core.Num(info.level)
    if level then entry.Level:SetTextColor(ns.LevelRGB(level)) end
end

local guildHooked = false
function Friends.HookGuild()
    local mixin = _G.CommunitiesMemberListEntryMixin
    if guildHooked or type(mixin) ~= "table" or type(mixin.UpdatePresence) ~= "function" then return guildHooked end
    guildHooked = true
    hooksecurefunc(mixin, "UpdatePresence", function(entry) ns.Try("Guild", Friends.DecorateGuildEntry, entry) end)
    return true
end

---------------------------------------------------------------------------
-- Anmelden
---------------------------------------------------------------------------

ns.OnReady(function()
    if not Friends.HookFriends() then ns.WhenAddOnLoaded("Blizzard_FriendsFrame", Friends.HookFriends) end
    ns.WhenAddOnLoaded("Blizzard_Communities", Friends.HookGuild)
end)
