local _, ns = ...
local L = ns.L

-- ezMacro-Knopf in Blizzards Knopfleiste am Chat, direkt unter dem Sprachchat-Knopf bzw. den sichtbaren
-- Sprachknöpfen, mit deren Abstand (−2) – so wie Blizzard ChatFrameToggleVoiceDeafenButton anheftet
-- (FloatingChatFrameVoiceChat.xml). Symbol: das Porträt der Makroverwaltung
-- (Blizzard_MacroUI.xml: Interface\MacroFrame\MacroFrame-Icon).
-- Aussehen (VoiceToggleButtonTemplate), Platz und Mitwandern beim Reiterwechsel kommen aus ezCores
-- gemeinsamer Chat-Knopfleiste (ezCore/ChatBar.lua). Andere Knöpfe der Leiste (z. B. von ezChat, das von
-- unten nach oben stapelt) haben Vorrang: Reicht der Platz nicht, blendet sich der Knopf aus.
local ChatButton = {}
ns.ChatButton = ChatButton
local CoreBar = ezCore.ChatBar

-- Tooltip im Format des Addon-Fachs: Titel weiß, Klick-Zeilen grün aus ezCores Texten (Gesamtreview T16-10, T9-6)
local function Tooltip()
    ezCore.TipTitle(GameTooltip, L.TITLE)
    ezCore.TipClick(GameTooltip, ezCore.L.COMPARTMENT_LEFT_MAIN:format(L.MAIN_TEXT))
    ezCore.TipClick(GameTooltip, ezCore.L.COMPARTMENT_RIGHT_SETTINGS)
end

-- Kein eigener Klang: Makroverwaltung und Einstellungen spielen beim Öffnen ihren eigenen.
local function Click(_, mouseButton)
    if mouseButton == "RightButton" then
        ns.OpenSettings()
    else
        ns.Browser.Toggle()
    end
end

function ChatButton.Layout() CoreBar.Layout() end
function ChatButton.LayoutSoon() CoreBar.LayoutSoon() end

ns.OnReady(function()
    CoreBar.Add({
        key = "ezMacro.browser", owner = "ezMacro", side = "top", order = 10, name = "ezMacroChatButton",
        icon = "Interface\\MacroFrame\\MacroFrame-Icon", file = "Interface\\Icons\\INV_Misc_Note_02",
        shown = function() return ns.S and ns.S.chatButton end,
        tooltip = Tooltip, onClick = Click,
    })
end)

ns.OnSettingChanged(function(key)
    if key == "chatButton" then CoreBar.Layout() end
end)
