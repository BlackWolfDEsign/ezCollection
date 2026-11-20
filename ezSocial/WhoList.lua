local _, ns = ...
local Core = ezCore

--[[
    Wer-Liste in Blizzards Fenster „Gruppe suchen“ (dritter Reiter): Blizzard färbt nur die Spalte Klasse.
    ezSocial färbt den Namen in der Klassenfarbe, die Stufe nach deiner Stufe (rot zu hoch … grau zu niedrig)
    und den Gildennamen grün, wenn es deine Gilde ist; ganz rechts ein Knopf „Gespräch“ (ezChat, Talk.lua).
    Die Wer-Abfrage startet nur der Spieler selbst.
    Blizzard setzt Name und Stufe nicht zurück; deshalb merkt sich ezSocial die Grundfarbe je Zeile
    (eigene schwache Tabelle) und stellt sie wieder her, wenn der Schalter „Namen und Stufen farbig“ aus ist.
]]

local Who = {}
ns.Who = Who

local saved = setmetatable({}, { __mode = "k" })    -- [FontString] = { r, g, b } (Blizzards Grundfarbe)

local function Remember(fontString)
    if ns.Region(fontString) and not saved[fontString] and fontString.GetTextColor then
        local r, g, b = fontString:GetTextColor()
        if type(r) == "number" then saved[fontString] = { r, g, b } end
    end
end

local function Restore(fontString)
    local c = ns.Region(fontString) and saved[fontString]
    if c then fontString:SetTextColor(c[1], c[2], c[3]) end
end

-- Name der eigenen Gilde aus ezCores Gildenschlüssel („Gilde-Realm“; Gildennamen haben keinen Bindestrich).
local function MyGuild()
    local key = Core.Inventory.MyGuildKey()
    return type(key) == "string" and key:match("^([^%-]+)%-") or nil
end

-- Knopf „Gespräch“ (Talk.lua) ganz rechts in der Zeile: Blizzard lässt rechts neben dem Einladen-Knopf
-- 20 Pixel frei. Angelegt erst, wenn ezChat da ist.
local talkButtons = setmetatable({}, { __mode = "k" })

local function SetTalk(button, name)
    local talk = talkButtons[button]
    if not talk then
        if not (name and ns.Talk.Enabled()) then return end
        talk = ns.Talk.Button(button, 18)
        talk:SetPoint("RIGHT", button, "RIGHT", -1, 0)
        talkButtons[button] = talk
    end
    ns.Talk.Set(talk, name, false)
end
Who.TalkButton = function(button) return talkButtons[button] end

-- Nach Blizzards LFGWhoListButtonMixin:InitButton(elementData, selected).
function Who.Decorate(button, elementData)
    if not button then return end
    for _, key in ipairs({ "Name", "Level", "GuildName", "Variable" }) do Remember(button[key]) end
    local info = type(elementData) == "table" and elementData.info or nil
    local fullName = type(info) == "table" and Core.Plain(info.fullName) or nil
    SetTalk(button, type(fullName) == "string" and fullName or nil)
    if not ns.Enabled("colors") or type(info) ~= "table" then
        for _, key in ipairs({ "Name", "Level", "GuildName", "Variable" }) do Restore(button[key]) end
        return
    end
    local class = Core.Plain(info.filename)
    local color = type(class) == "string" and Core.ClassColor(class) or nil
    if button.Name then
        if color and color.r then button.Name:SetTextColor(color.r, color.g, color.b) else Restore(button.Name) end
    end
    local level = Core.Num(info.level)
    if button.Level then
        if level then button.Level:SetTextColor(ns.LevelRGB(level)) else Restore(button.Level) end
    end
    local guild, mine = Core.Plain(info.fullGuildName), MyGuild()
    local same = type(guild) == "string" and mine ~= nil and (guild == mine or guild:find("^" .. Core.EscapePattern(mine) .. "%-") ~= nil)
    for _, key in ipairs({ "GuildName", "Variable" }) do
        local fs = ns.Region(button[key])
        if fs then
            -- eigene Gilde in Blizzards Grün (Rolle „good“, Design-System 2.5; bis Welle 22 der eigene Ton 0.25, 1, 0.25)
            if same and fs:GetText() == info.fullGuildName then
                local r, g, b = Core.Style.Color("good")
                fs:SetTextColor(r, g, b)
            else
                Restore(fs)
            end
        end
    end
end

local hooked = false
function Who.Hook()
    if hooked or type(LFGWhoListButtonMixin) ~= "table" or type(LFGWhoListButtonMixin.InitButton) ~= "function" then
        return hooked
    end
    hooked = true
    -- Zeilen entstehen erst beim ersten Ergebnis; sie übernehmen die Methode der Vorlage beim Anlegen.
    hooksecurefunc(LFGWhoListButtonMixin, "InitButton", function(button, elementData)
        ns.Try("Who", Who.Decorate, button, elementData)
    end)
    return true
end

ns.OnReady(function()
    ns.WhenAddOnLoaded(ns.FINDER_ADDON, Who.Hook)
end)
