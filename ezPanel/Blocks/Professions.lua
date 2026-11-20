local _, ns = ...
local L = ns.L

--[[
    Berufe (Titan ProfessionsMulti): Fertigkeit aller Berufe in einem Baustein,
    Fortschritt dieser Sitzung, Hinweis bei erreichter Stufen-Obergrenze und
    die Berufe der anderen Charaktere.
    Verbesserungen: ereignisgesteuert statt jede Sekunde abzufragen, kein
    ungeschütztes Zaubern beim Klick (öffnet nur das Berufebuch/Fertigkeiten).
    WoW Forever: GetProfessions liefert Erste Hilfe an dritter Stelle (statt
    Archäologie); die Obergrenze ist 300.
    Daten: ezCore.Professions (Read für den gespielten Charakter, Of(key) für die Twinks,
    c.profs schreibt ezCore). Der Baustein zeigt nur an und merkt sich die Startwerte der Sitzung.
]]

local block = ns.RegisterBlock({
    id = "professions",
    command = "berufe",
    name = L.PROF_NAME,
    label = L.PROF_LABEL,
    icon = "Interface\\Icons\\INV_Misc_Note_01",
    events = { "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "TRADE_SKILL_LIST_UPDATE" },
    colorable = true,
    defaults = {
        enabled = false, zone = "left", order = 80, icon = false, label = false,
        onBar = "primary",    -- primary | all
        names = false,
        alts = true,
    },
    hints = { L.PROF_HINT_LEFT },
})

local CAP = 300

---------------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------------

-- Berufe des gespielten Charakters: { slot, name, icon, rank, max, line, mod, primary } (ezCore).
local function Read()
    return ezCore.Professions.Read()
end

-- Startwerte der Sitzung (für „+n in dieser Sitzung“); die Berufe selbst erfasst ezCore.
local function NoteSessionStart()
    local s = ns.session
    if not s then return end
    s.prof = s.prof or {}
    for _, p in ipairs(Read()) do
        local key = p.line or p.name
        if s.prof[key] == nil then s.prof[key] = p.rank end
    end
end

ns.OnReady(function() C_Timer.After(2, NoteSessionStart) end)
ezCore.Listen("PROFESSIONS_CHANGED", function()
    NoteSessionStart()
    ns.QueueUpdate(block)
end, "ezPanel")

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local function RankColor(p)
    if p.rank >= CAP then return ns.GOLD end                          -- fertig
    if p.max > 0 and p.rank >= p.max then return ns.OrangeCode() end  -- zum Lehrer!
    return ns.WHITE
end

local function Gain(p)
    local start = ns.session.prof and ns.session.prof[p.line or p.name]
    if start and p.rank > start then return p.rank - start end
    return nil
end

function block:GetText()
    local cfg = self.cfg
    local parts = {}
    for _, p in ipairs(Read()) do
        if cfg.onBar == "all" or p.primary then
            local text = RankColor(p) .. p.rank .. "|r"
            if cfg.names then
                text = p.name .. " " .. text
            elseif p.icon then
                text = "|T" .. p.icon .. ":0|t " .. text
            end
            parts[#parts + 1] = text
        end
    end
    if #parts == 0 then return ns.Grey(L.PROF_NONE) end
    return table.concat(parts, "  ")
end

function block:OnTooltip(tooltip)
    local list = Read()
    if #list == 0 then
        ns.TipLine(tooltip, L.PROF_NONE_TIP, "highlight", true)   -- Leertext mit Erklärung (PANEL-17)
    end
    local trainer = false
    for _, p in ipairs(list) do
        local left = (p.icon and "|T" .. p.icon .. ":14:14|t " or "") .. p.name
        local right = RankColor(p) .. p.rank .. "|r / " .. p.max
        if p.mod > 0 then right = right .. " " .. ns.GREEN .. "(+" .. p.mod .. ")|r" end
        local gain = Gain(p)
        if gain then right = right .. " " .. ns.GREEN .. "[+" .. gain .. "]|r" end
        ns.TipDoubleLine(tooltip, left, right, "normal", "highlight")
        if p.rank < CAP and p.max > 0 and p.rank >= p.max then trainer = true end
    end
    if trainer then
        tooltip:AddLine(" ")
        ns.TipLine(tooltip, L.PROF_TRAINER, "orange", true)
    end

    if self.cfg.alts then
        local first = true
        for _, entry in ipairs(ns.Characters()) do
            local c = entry.c
            local profs = ezCore.Professions.Of(entry.key)
            if not entry.isMe and type(profs) == "table" and #profs > 0 then
                if first then
                    tooltip:AddLine(" ")
                    ns.TipLine(tooltip, L.OTHER_CHARS, "normal")
                    first = false
                end
                local parts = {}
                for _, p in ipairs(profs) do
                    parts[#parts + 1] = (p.icon and "|T" .. p.icon .. ":0|t " or "") .. p.rank
                end
                ns.TipDoubleLine(tooltip, ns.CharName(c, entry.key), table.concat(parts, "  ") .. ns.AltStand(c), "highlight", "highlight")
            end
        end
    end
end

function block:OnClick(button)
    if button ~= "LeftButton" then return end
    -- Nur Fenster öffnen, nie zaubern (das wäre eine geschützte Aktion). ezCore kennt die Wege der Clients
    -- (Berufebuch, Fertigkeiten im Charakterfenster, altes Zauberbuch).
    ezCore.TogglePanel("professions")
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(bar, L.PROF_SHOW_PRIMARY, cfg, "onBar", "primary", self)
    ns.MenuRadio(bar, L.PROF_SHOW_ALL, cfg, "onBar", "all", self)
    bar:CreateDivider()
    ns.MenuCheck(bar, L.PROF_SHOW_NAMES, cfg, "names", self)
    ns.MenuCheck(root, L.TIP_SHOW_ALTS, cfg, "alts", self)
end
