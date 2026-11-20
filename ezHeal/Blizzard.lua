local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Knopf „Vorlagen“ an Blizzards Fenster „Klick-Zauber“ (Blizzard_ClickBindingUI, ClickBindingFrame; Aufbau nach
    Blizzards Forever-Quelle, Blizzard_ClickBindingUI.xml/.lua: PortraitFrameTemplate, 440 × 620; oben links das
    Kästchen „Mouseover-Zauber“ bei 60/−30 (26 × 26, klickbar 100 Punkte weiter nach rechts, Beschriftung rechts
    daneben), darunter das Auswahlfeld „Mouseover-Taste“ (130 breit, ab 71 unter der Oberkante, nur bei
    eingeschaltetem Mouseover-Zauber; dann wird das Fenster 25 höher); oben rechts zwei Portrait-Knöpfe 31 × 31 –
    PlayerSpellsPortrait bei TOPRIGHT −40/−40 und links daneben MacrosPortrait (5 Abstand), also von rechts
    x −107…−40, y −40…−71; die Liste beginnt 85 unter der Oberkante).
    Der Knopf sitzt links neben MacrosPortrait, unten bündig mit den Portraits (2 tiefer): rechts von Kästchen und
    Auswahlfeld, über der Liste, ohne die Portrait-Knöpfe zu überdecken. Er ist ein Kind von Blizzards Fenster (kein
    eigenes Fenster, Leitlinie 1) und wandert mit ihm; von Blizzards Fenster wird nur gelesen. Ein Klick öffnet ein
    Menü: „Vorschau und Tasten wählen“ (Preview.lua), jede Vorlage der Klasse (mit Rückfrage und Vorschau), „Zurück“,
    „Belegung vor dem ersten Übernehmen“ (beide mit Rückfrage), „Profile der Klick-Belegung“ (Profiles.lua) und die
    Einstellungsseite.
]]

local B = {}
ns.BlizzardButton = B

B.ADDON = "Blizzard_ClickBindingUI"

local function Tooltip(self)
    Core.ShowTip(self, L.TITLE, L.BLIZZ_BUTTON_TIP)
end

-- Menü des Knopfs: Vorlagen der Klasse, Zurück, Einstellungen
function B.FillMenu(_, root)
    root:CreateTitle(L.TITLE)
    root:CreateButton(L.MENU_KEYS, function() ns.Preview.Open() end)
    for _, info in ipairs(ns.API.Templates()) do
        local kind = info.kind
        root:CreateButton(L.MENU_APPLY:format(info.label), function() ns.AskApply(kind) end)
    end
    root:CreateDivider()
    root:CreateButton(L.MENU_RESTORE, function() ns.AskRestore() end)
    root:CreateButton(L.MENU_RESTORE_FIRST, function() ns.AskRestore("first") end)
    -- benannte Profile der Klick-Belegung (HL-08, Profiles.lua): Untermenü
    ns.Profiles.FillMenu(root:CreateButton(L.MENU_PROFILES))
    -- Heil-Makros je Klasse in Blizzards Makrofenster (Macros.lua): anlegen und wieder entfernen, je mit Rückfrage
    root:CreateDivider()
    root:CreateButton(L.MENU_MACROS, function() ns.AskMacros() end)
    root:CreateButton(L.MENU_MACROS_REMOVE, function() ns.AskRemoveMacros() end)
    ezCore.Menu.Settings(root, ns)   -- „Einstellungen …“ von ezCore (Gesamtreview T18-8)
end

-- Über ezCores Menü (Fehlerfang, T18-12); ohne Blizzards MenuUtil öffnen die Einstellungen
local function OnClick(self)
    if not ezCore.Menu.Open(self, function(root) B.FillMenu(self, root) end) then ns.OpenSettings() end
end

B.WIDTH, B.HEIGHT, B.GAP = 90, 22, 8
-- Ersatzlage ohne MacrosPortrait: dieselbe Stelle nach Blizzards Maßen (linke Kante des Portraits 76 vom rechten Rand,
-- Unterkante 71 unter der Oberkante)
B.FALLBACK_X, B.FALLBACK_Y = -76 - B.GAP, -73

-- Lage des Knopfs: links neben Blizzards Portrait-Knopf „Makros“ (nur gelesen), sonst die Ersatzlage
function B.Anchor(button, parent)
    local macros = parent.MacrosPortrait
    button:ClearAllPoints()
    if type(macros) == "table" then
        button:SetPoint("BOTTOMRIGHT", macros, "BOTTOMLEFT", -B.GAP, -2)
    else
        button:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", B.FALLBACK_X, B.FALLBACK_Y)
    end
end

function B.Create()
    local parent = rawget(_G, "ClickBindingFrame")
    if B.button or type(parent) ~= "table" then return B.button end
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(B.WIDTH, B.HEIGHT)
    B.Anchor(button, parent)
    button:SetText(L.BLIZZ_BUTTON)
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    B.button = button
    -- Rundgang beim ersten Öffnen von Blizzards Fenster (Tour.lua, UE-28; nur zuhören)
    parent:HookScript("OnShow", function() ns.Tour.Start() end)
    if parent:IsShown() then ns.Tour.Start() end
    return button
end

ns.OnReady(function()
    ns.WhenAddOnLoaded(B.ADDON, function() ns.Try("Klick-Zauber-Knopf", B.Create) end)
end)
