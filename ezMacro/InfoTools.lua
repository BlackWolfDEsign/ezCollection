local _, ns = ...
local L = ns.L
local Core = ezCore
local UI = ns.UI

--[[
    Werkzeug „Kleine Helfer“ (MACRO-29; eigene Texte):
    Knöpfe für Dinge, für die Spieler sonst einen Makro-Platz opfern. Ausgaben stehen nur im eigenen Chat.

      Bildschirmfoto ohne Benutzeroberfläche   nur außerhalb des Kampfes: Oberfläche aus über Blizzards
          SetUIVisibility – denselben Weg wie die Taste „Benutzeroberfläche ein/aus“ (Alt+Z, Blizzard_FrameXML/
          Bindings_Camelot.xml, Zweig forever); nur wenn es SetUIVisibility nicht gibt, UIParent:Hide/Show als
          Rückfall (Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 5: UIParent:Show aus Addon-Code lässt die
          Einblend-Skripte aller Blizzard-Fenster im Addon-Ablauf laufen – direkt vor dem Kampf ein Taint-Weg). Kurz
          warten, Screenshot(), danach sofort wieder an – bei SCREENSHOT_SUCCEEDED, SCREENSHOT_FAILED, einem Fehler
          beim Aufruf, nach Shot.TIMEOUT Sekunden ohne Antwort und beim Kampfbeginn (PLAYER_REGEN_DISABLED kommt vor
          der Kampfsperre). Ist der Kampf doch schon gesperrt, kommt die Oberfläche erst nach dem Kampf zurück
          (Hinweis auf Alt+Z) – auf beiden Wegen, nie unter der Kampfsperre. War die Oberfläche schon aus (Alt+Z),
          bleibt sie aus. Auch /ezmacro foto.
      NPC-ID des Ziels   Die Zeile „NPC-ID“ im Tooltip jeder Einheit gibt es schon in ezCore (Einstellung „NPC-ID“,
          Abschnitt Tooltip, ab Werk aus) – hier nur ihr Stand, ein Knopf zur Seite und „Im Chat zeigen“ (Name und ID
          des Ziels aus der GUID, Core.NpcID). Auch /ezmacro npc.
      Plündermethode wechseln   gibt es schon in ezPanel (Baustein „Beute“, Rechtsklick » „Plündermethode“, nur als
          Gruppenleiter) – hier nur der Verweis mit dem Stand des Bausteins (ezCore.API("ezPanel").BlockEnabled).
]]
local Info = {}
ns.InfoTools = Info

---------------------------------------------------------------------------
-- Bildschirmfoto ohne Benutzeroberfläche
---------------------------------------------------------------------------

local Shot = { DELAY = 0.1, TIMEOUT = 3 }
Info.Shot = Shot
local running        -- laufendes Foto: { hidden, method } oder nil

-- Oberfläche ein- bzw. ausblenden → Weg ("visibility" | "parent") oder nil (nichts ging). Zuerst Blizzards
-- SetUIVisibility (der Weg von Alt+Z); UIParent:Hide/Show nur, wenn es SetUIVisibility nicht gibt (Risiko 5).
-- method: denselben Weg wie beim Ausblenden nehmen.
local function SetVisible(visible, method)
    local set = rawget(_G, "SetUIVisibility")
    if type(set) == "function" then
        if method == "parent" then return nil end
        if pcall(set, visible) then return "visibility" end
        return nil
    end
    local parent = rawget(_G, "UIParent")
    if method ~= "visibility" and type(parent) == "table" then
        local fn = visible and parent.Show or parent.Hide
        if type(fn) == "function" and pcall(fn, parent) then return "parent" end
    end
    return nil
end

local function UIShown()
    local parent = rawget(_G, "UIParent")
    if type(parent) ~= "table" or type(parent.IsShown) ~= "function" then return true end
    return Core.Bool(parent:IsShown(), true)
end

function Shot.Busy() return running ~= nil end

-- Oberfläche zurück. Unter der Kampfsperre nie (Leitlinie 5 – ob Blizzard SetUIVisibility aus Addon-Code im Kampf
-- zulässt, ist nicht belegt; UIParent:Show wäre gesperrt): dann nach dem Kampf (Hinweis mit Blizzards Taste).
-- beforeLockdown: aus PLAYER_REGEN_DISABLED – die Sperre greift erst danach.
function Shot.Restore(run, beforeLockdown)
    if not (run and run.hidden) then return true end
    if not beforeLockdown and ns.InCombat() then
        run.later = true
        ns.Print(L.SHOT_LATER)
        ns.AfterCombat(function() SetVisible(true, run.method) end, "shot.restore")
        return false
    end
    run.hidden = SetVisible(true, run.method) == nil
    return not run.hidden
end

-- Ende eines Fotos: success true (gespeichert), false (misslungen), nil (keine Antwort, Kampf).
function Shot.Finish(success, beforeLockdown)
    local run = running
    if not run then return false end
    running = nil
    -- „… die Oberfläche ist wieder da“ nur, wenn sie es ist: unter der Kampfsperre sagt SHOT_LATER schon alles,
    -- ließ sie sich nicht einblenden, kommt der Hinweis auf Blizzards Taste.
    local back = Shot.Restore(run, beforeLockdown)
    if not back then
        if not run.later then ns.Print(L.SHOT_STUCK) end
    elseif success == true then
        ns.Print(L.SHOT_DONE)
    elseif success == false then
        ns.Print(L.SHOT_FAILED)
    else
        ns.Print(L.SHOT_TIMEOUT)
    end
    ns.Tools.RefreshKey("info")
    return true
end

-- Foto machen → true | false, "busy" | "combat" | "missing"
function Shot.Take()
    if running then
        ns.Print(L.SHOT_BUSY)
        return false, "busy"
    end
    if ns.InCombat() then
        ns.Print(L.SHOT_COMBAT)
        return false, "combat"
    end
    local shoot = rawget(_G, "Screenshot")
    if type(shoot) ~= "function" then
        ns.Print(L.SHOT_MISSING)
        return false, "missing"
    end
    local run = {}
    running = run
    if UIShown() then
        run.method = SetVisible(false)
        run.hidden = run.method ~= nil
    end
    C_Timer.After(Shot.DELAY, function()
        if running ~= run then return end
        if not pcall(shoot) then Shot.Finish(false) end
        -- sonst meldet der Client SCREENSHOT_SUCCEEDED bzw. SCREENSHOT_FAILED
    end)
    C_Timer.After(Shot.TIMEOUT, function()
        if running == run then Shot.Finish(nil) end
    end)
    return true
end

ns.On("SCREENSHOT_SUCCEEDED", function() if running then Shot.Finish(true) end end)
ns.On("SCREENSHOT_FAILED", function() if running then Shot.Finish(false) end end)
-- Kampfbeginn während des Fotos: sofort zurück – PLAYER_REGEN_DISABLED kommt vor der Kampfsperre
ns.On("PLAYER_REGEN_DISABLED", function() if running then Shot.Finish(nil, true) end end)

---------------------------------------------------------------------------
-- NPC-ID des Ziels (Verweis auf ezCores Tooltip-Zeile)
---------------------------------------------------------------------------

-- NPC-ID und Name des Ziels → id, name | nil, "none" | "secret"
function Info.TargetNpc()
    if Core.UnitPresent("target") ~= true then return nil, "none" end
    local guid = UnitGUID and UnitGUID("target")
    if Core.IsSecret(guid) then return nil, "secret" end
    local id = type(Core.NpcID) == "function" and Core.NpcID(guid) or nil
    if not id then return nil, "none" end
    local name, why = ns.Announce.UnitName("target")
    if why == "secret" then return nil, "secret" end
    return id, name or "?"
end

-- „Im Chat zeigen“: nur im eigenen Chat (ns.Print), niemand sonst sieht es.
function Info.PrintNpc()
    local id, name = Info.TargetNpc()
    if id then
        ns.Print(L.NPC_LINE:format(name, id))
    else
        ns.Print(name == "secret" and L.NPC_SECRET or L.NPC_NONE)
    end
    return id
end

-- Übernimmt ein fremdes Addon den Tooltip (Leatrix Plus, Forever Tweaks, TipTac …)? → dessen Name oder nil.
-- Dann ruht ezCores Zeile „NPC-ID“, und Einschalten in ezCore bewirkt nichts (Leitlinie 9).
function Info.TooltipOther()
    return (ns.OtherFor("unitTooltip"))
end

-- Steht ezCores Zeile „NPC-ID“ im Tooltip? true/false; nil, wenn ezCore sie nicht kennt.
function Info.TooltipIDs()
    local UT = Core.UnitTooltip
    if type(UT) ~= "table" or type(UT.Enabled) ~= "function" then return nil end
    local ok, on = pcall(UT.Enabled, "ids")
    return ok and on == true
end

---------------------------------------------------------------------------
-- Plündermethode (Verweis auf ezPanel, Baustein „Beute“)
---------------------------------------------------------------------------

-- "noPanel" (ezPanel nicht geladen) | "on" (Baustein auf der Leiste) | "off"
function Info.LootState()
    local api = Core.API and Core.API("ezPanel")
    if type(api) ~= "table" then return "noPanel" end
    if type(api.BlockEnabled) == "function" then
        local ok, on = pcall(api.BlockEnabled, "loot")
        if ok and on == true then return "on" end
    end
    return "off"
end

function Info.OpenPanelSettings()
    return Core.OpenModuleSettings and Core.OpenModuleSettings("ezPanel") or false
end

---------------------------------------------------------------------------
-- Seite im Reiter „Werkzeuge“
---------------------------------------------------------------------------

local function Block(panel, anchor, title, gap)
    local head = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    head:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, gap or -14)
    head:SetJustifyH("LEFT")
    head:SetText(title)
    local text = UI.Text(panel, "GameFontHighlightSmall", panel.width)
    text:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
    return head, text
end

local function OnOff(on)
    return on and UI.Colored("GREEN_FONT_COLOR", L.ON) or UI.Colored("GRAY_FONT_COLOR", L.OFF)
end

ns.Tools.Register({
    key = "info", order = 50, icon = { "INV_Misc_Spyglass_02", "INV_Misc_Note_01" },
    name = L.TOOL_INFO, why = L.TOOL_INFO_WHY, desc = L.TOOL_INFO_DESC,
    status = function()
        return L.INFO_STATUS:format(OnOff(Info.TooltipIDs()), OnOff(Info.LootState() == "on"))
    end,
    build = function(panel)
        panel.shotHead, panel.shotText = Block(panel, panel.top, L.SHOT_TITLE, -10)
        panel.shotText:SetText(L.SHOT_TEXT)
        panel.shot = UI.Button(panel, L.SHOT_BUTTON, 150, function() Shot.Take() end, L.SHOT_TITLE, L.SHOT_TIP)
        panel.shot:SetPoint("TOPLEFT", panel.shotText, "BOTTOMLEFT", 0, -6)

        panel.npcHead, panel.npcText = Block(panel, panel.shot, L.NPC_TITLE)
        panel.npc = UI.Button(panel, L.NPC_BUTTON, 150, function() Info.PrintNpc() end, L.NPC_BUTTON, L.NPC_BUTTON_TIP)
        panel.npc:SetPoint("TOPLEFT", panel.npcText, "BOTTOMLEFT", 0, -6)
        -- Weg über ezCore (Core.SettingsPathText; Abschnitt und Name aus ezCores Texten, T18-18)
        panel.npcSettings = UI.Button(panel, L.NPC_SETTING, 150, function() Core.OpenSettings() end, L.NPC_SETTING,
            L.NPC_SETTING_TIP:format(Core.SettingsPathText("ezCollection", "UT_HEADER", "OPT_ttIDs")))
        panel.npcSettings:SetPoint("LEFT", panel.npc, "RIGHT", 4, 0)

        panel.lootHead, panel.lootText = Block(panel, panel.npc, L.LOOT_TITLE)
        panel.loot = UI.Button(panel, L.LOOT_BUTTON, 150, function() Info.OpenPanelSettings() end, L.LOOT_BUTTON,
            L.LOOT_BUTTON_TIP)
        panel.loot:SetPoint("TOPLEFT", panel.lootText, "BOTTOMLEFT", 0, -6)
    end,
    refresh = function(panel)
        panel.shot:SetEnabled(not ns.InCombat() and not Shot.Busy())
        local other = Info.TooltipOther()
        if other then
            panel.npcText:SetText(L.NPC_TOOLTIP_OTHER:format(other))
        else
            panel.npcText:SetText(Info.TooltipIDs() and L.NPC_TOOLTIP_ON or L.NPC_TOOLTIP_OFF)
        end
        panel.npcSettings:SetEnabled(not other)
        local loot = Info.LootState()
        panel.lootText:SetText(L["LOOT_STATE_" .. loot])
        panel.loot:SetEnabled(loot ~= "noPanel")
    end,
})

-- Im Kampf ist der Knopf „Foto machen“ grau.
ns.On("PLAYER_REGEN_DISABLED", function() ns.Tools.RefreshKey("info") end)
ns.On("PLAYER_REGEN_ENABLED", function() ns.Tools.RefreshKey("info") end)
