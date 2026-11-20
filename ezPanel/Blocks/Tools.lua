local _, ns = ...
local L = ns.L

--[[
    Werkzeuge (Titan UI): UI neu laden, Frame-Stack, Ereignis-Protokoll und
    eigene Slash-Befehle im Menü; Tagesreset im Tooltip.
    Fehlerzähler: die Fehler aller ez-Module, die ezCore sich merkt (auch über /reload hinweg);
    Zahlen aus ezCore.ErrorCount() (gesamt, davon in dieser Sitzung), neu gezeichnet bei der
    ezCore-Nachricht ERRORS_CHANGED. Rot, wenn in dieser Sitzung neue dazukamen, sonst grau.
    „Fehlerliste“ im Menü (und Strg+Linksklick) öffnet ezCores Fenster zum Kopieren
    (ezCore.ShowErrorList); ausgeben im Chat und leeren gehen ebenfalls über das Menü.
    Verbesserung: Eigene Befehle laufen direkt über die Funktion, die das Addon
    für den Befehl registriert hat – nicht über die Chatzeile. Das verhindert
    Taint der Chat-Eingabe. Geschützte Befehle (/cast, /use …) lassen sich so
    bewusst nicht ausführen; ezPanel sagt dann Bescheid.
]]

local block = ns.RegisterBlock({
    id = "tools",
    command = "werkzeuge",
    name = L.TOOLS_NAME,
    icon = "Interface\\Icons\\INV_Misc_Gear_01",
    colorable = true,
    defaults = {
        enabled = false, zone = "right", order = 50, label = false,
        commands = {},        -- eigene Befehle; Neu laden, Frame-Stack, Ereignisse sind fest eingebaut
        errors = true,        -- Fehlerzähler auf der Leiste
    },
    hints = function(self)
        -- Klick-Hinweise mit Zusatztaste über ezCore (Core.ClickText, T18-9)
        local list = { L.TOOLS_HINT_LEFT, ezCore.ClickText("left", "SHIFT", L.TOOLS_HINT_SHIFT) }
        if ezCore.ErrorCount() > 0 then list[#list + 1] = ezCore.ClickText("left", "CTRL", L.TOOLS_HINT_ERRORS) end
        return list
    end,
})

---------------------------------------------------------------------------
-- Befehle ausführen
---------------------------------------------------------------------------

local function Reload()
    if C_UI and C_UI.Reload then C_UI.Reload() else ReloadUI() end
end

local function FrameStack()
    ns.LoadAddOn("Blizzard_DebugTools")
    if FrameStackTooltip_Toggle then FrameStackTooltip_Toggle() end
end

local function EventTraceToggle()
    ns.LoadAddOn("Blizzard_EventTrace")
    local frame = _G.EventTrace
    if frame and frame.SetShown then frame:SetShown(not frame:IsShown()) end
end

-- Eingebaute Befehle, die ezPanel selbst sauber aufruft.
local BUILTIN = {
    ["/reload"] = Reload, ["/rl"] = Reload,
    ["/fstack"] = FrameStack, ["/framestack"] = FrameStack,
    ["/eventtrace"] = EventTraceToggle, ["/etrace"] = EventTraceToggle,
}

-- Findet die Funktion, die ein Addon für den Befehl angemeldet hat.
local function FindHandler(cmd)
    cmd = cmd:lower()
    for name, fn in pairs(SlashCmdList) do
        for i = 1, 10 do
            local slash = _G["SLASH_" .. name .. i]
            if not slash then break end
            if type(slash) == "string" and slash:lower() == cmd then return fn end
        end
    end
    return nil
end
ns.SlashHandler = FindHandler

local function Run(line)
    line = strtrim(line or "")
    local cmd, rest = line:match("^(/%S+)%s*(.-)$")
    if not cmd then return ns.Print(L.TOOLS_BAD:format(line)) end
    local builtin = BUILTIN[cmd:lower()]
    if builtin and rest == "" then return builtin() end
    local fn = FindHandler(cmd)
    if fn then
        local ok, err = pcall(fn, rest, DEFAULT_CHAT_FRAME.editBox)
        if not ok then geterrorhandler()(err) end
    else
        ns.Print(L.TOOLS_UNKNOWN:format(cmd))
    end
end

---------------------------------------------------------------------------
-- Befehl hinzufügen (Eingabedialog von ezCore)
---------------------------------------------------------------------------

local function AskCommand()
    ezCore.AskText(L.TOOLS_ADD_PROMPT, "/", function(text)
        if type(text) == "string" and text:match("^/%S") then table.insert(block.cfg.commands, text) end
    end, 120)
end

---------------------------------------------------------------------------
-- Fehlerzähler (Daten: ezCore)
---------------------------------------------------------------------------

-- gesamt, davon in dieser Sitzung (ezCore zählt; „Sitzung“ beginnt auch nach /reload neu)
local function ErrorCounts()
    return ezCore.ErrorCount()
end

-- Fenster mit allen Fehlern zum Kopieren (ezCore).
local function ShowErrors()
    ezCore.ShowErrorList()
end

local function PrintErrors()
    ezCore.PrintErrors()
end

local function ClearErrors()
    ezCore.ClearErrors()   -- meldet ERRORS_CHANGED, der Zähler zeichnet sich darüber neu
    ns.Print(L.TOOLS_ERRORS_CLEARED)
end

-- Neue oder geleerte Fehler sofort zeigen – hier und im Baustein „Meldungen“.
ezCore.Listen("ERRORS_CHANGED", function()
    ns.QueueUpdate(block)
    ns.QueueUpdate("alerts")
end, "ezPanel")

-- Für den Baustein „Meldungen“: neue Fehler in dieser Sitzung.
function block:Warnings()
    local _, new = ErrorCounts()
    if new > 0 then return { L.ALERT_ERRORS:format(new) } end
    return nil
end

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

function block:GetText()
    if not self.cfg.errors then return "" end
    local total, new = ErrorCounts()
    if total == 0 then return "" end
    return (new > 0 and ns.RED or ns.GREY) .. total .. "|r"
end

local Reset = ns.ResetIn   -- Sekunden bis zum Tages- oder Wochenreset (Core.lua, eine Fassung mit „Uhr“)

function block:OnTooltip(tooltip)
    local _, build, _, interface = GetBuildInfo()
    ns.TipDoubleLine(tooltip, L.TOOLS_CLIENT, ("%s (%s)"):format(build or "?", interface or "?"), "normal", "highlight")
    ns.TipDoubleLine(tooltip, L.LOC_REALM, GetRealmName(), "normal", "highlight")
    local daily, weekly = Reset("GetSecondsUntilDailyReset"), Reset("GetSecondsUntilWeeklyReset")
    if daily then ns.TipDoubleLine(tooltip, L.CLOCK_DAILY, ns.Duration(daily, true), "normal", "highlight") end
    if weekly then ns.TipDoubleLine(tooltip, L.CLOCK_WEEKLY, ns.Duration(weekly, true), "normal", "highlight") end
    if #self.cfg.commands > 0 then
        tooltip:AddLine(" ")
        ns.TipLine(tooltip, L.TOOLS_COMMANDS, "normal")
        -- wörtlich, nicht als Farb- oder Link-Code gedeutet (Gesamtreview 18.11.2026, T6-6)
        for _, cmd in ipairs(self.cfg.commands) do ns.TipLine(tooltip, "  " .. ezCore.Literal(tostring(cmd)), "highlight") end
    end
    local total, new = ErrorCounts()
    tooltip:AddLine(" ")
    if total == 0 then
        ns.TipLine(tooltip, L.TOOLS_ERRORS_NONE, "hint")
        return
    end
    ns.TipDoubleLine(tooltip, L.TOOLS_ERRORS, L.TOOLS_ERRORS_COUNT:format(total, new), "normal", "highlight")
    local list = ezCore.Errors()
    for i = 1, math.min(3, #list) do
        local e = list[i]
        local text = ezCore.TruncateChars(ezCore.StripColors(tostring(e.e or "?")), 90)
        ns.TipLine(tooltip, ("%s: %s"):format(e.m or "?", text), "bad", true)
    end
end

local function AddCommands(root)
    root:CreateButton(L.TOOLS_RELOAD, Reload)
    root:CreateButton(L.TOOLS_FSTACK, FrameStack)
    root:CreateButton(L.TOOLS_EVENTTRACE, EventTraceToggle)
    local total = ErrorCounts()
    root:CreateButton(L.TOOLS_ERROR_LIST:format(total), ShowErrors)
    if total > 0 then
        root:CreateButton(L.TOOLS_ERRORS_PRINT, PrintErrors)
        root:CreateButton(L.TOOLS_ERRORS_CLEAR, ClearErrors)
    end
    local cmds = block.cfg.commands
    if #cmds > 0 then
        root:CreateDivider()
        root:CreateTitle(L.TOOLS_COMMANDS)
        for _, cmd in ipairs(cmds) do
            root:CreateButton(ezCore.Literal(tostring(cmd)), function() Run(cmd) end)
        end
    end
end

function block:OnClick(button, frame)
    if button ~= "LeftButton" then return end
    if IsShiftKeyDown() then return Reload() end
    if IsControlKeyDown and IsControlKeyDown() then return ShowErrors() end
    GameTooltip:Hide()
    ezCore.Menu.Open(frame, function(root)
        root:CreateTitle(L.TOOLS_NAME)
        AddCommands(root)
    end)
end

function block:OnMenu(root)
    local cmds = self.cfg.commands
    AddCommands(root)
    ns.MenuCheck(root, L.TOOLS_SHOW_ERRORS, self.cfg, "errors", self)
    root:CreateDivider()
    root:CreateButton(L.TOOLS_ADD, AskCommand)
    if #cmds > 0 then
        local remove = root:CreateButton(L.TOOLS_REMOVE)
        for i, cmd in ipairs(cmds) do
            remove:CreateButton(cmd, function() table.remove(cmds, i) end)
        end
    end
end
