local _, ns = ...
local L = ns.L

--[[
    Charaktere (Titan Alts): Übersicht aller Charaktere mit Stufe, Ruhe-XP,
    Gold, Ort, Gegenstandsstufe, gespielter Zeit und letztem Login.
    Ruhe-XP wird für ausgeloggte Charaktere hochgerechnet (ezCore.EstimateRested).
    Stufe, Ruhe-XP, Gebiet, Ruhestein, Spielzeit und (seit Welle 2) die Gegenstandsstufe schreibt ezCore
    selbst; ezPanel fragt nur die Spielzeit auf Knopfdruck ab (RequestTimePlayed).
    Darunter die Instanz- und Raidsperren aller Charaktere nach Instanz gebündelt und
    die Instanzen der letzten Stunde (Daten: ezCore.Lockouts über Lockouts.lua). Linksklick öffnet Blizzards
    Schlachtzugsinformationen.
]]

local block = ns.RegisterBlock({
    id = "alts",
    command = "charaktere",     -- „/ep chars“ listet die gespeicherten Charaktere
    name = L.ALTS_NAME,
    label = L.ALTS_LABEL,
    icon = "Interface\\Icons\\Achievement_Character_Human_Male",
    fallbackIcon = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    events = { "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP" },
    interval = 60,             -- Restzeiten der Sperren und der Instanzgrenze laufen weiter
    defaults = {
        enabled = false, zone = "left", order = 60,
        barShows = "count",    -- count | ilvl | rested | lockouts
        scope = "all",         -- realm | all
        sort = "name",         -- name | level | money | seen
        cols = { level = true, rested = true, money = true, zone = false, seen = true, played = false, ilvl = false },
        hidden = {},
        lockouts = true,       -- Abschnitt „Sperren“ im Tooltip
        lockBosses = false,    -- besiegte Bosse je Charakter aufzählen
        -- Grenze pro Stunde (0 = keine Angabe). Ab Werk ns.INSTANCE_LIMIT (Entscheidung des Nutzers vom 22.11.2026:
        -- „Ab Werk 5, 10 streichen (Empfohlen)“)
        instanceLimit = ns.INSTANCE_LIMIT,
        cooldowns = true,      -- Berufs-Abklingzeiten aller Charaktere im Tooltip (Daten: ezCore.Professions)
    },
    hints = function() return { L.ALTS_HINT_LEFT } end,
})

---------------------------------------------------------------------------
-- Daten: die Gegenstandsstufe erfasst ezCore (Core.SaveGear, auch wenn der Baustein aus ist)
---------------------------------------------------------------------------

local function ItemLevel()
    return (ns.ItemLevel())
end

-- Gemerkte Stufe eines Charakters (angelegt), nil wenn noch nie erfasst.
local function ItemLevelOf(key)
    return (ezCore.ItemLevelOf(key))
end

ezCore.Listen("GEAR_CHANGED", function() ns.QueueUpdate("alts") end, "ezPanel")

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------

local function Visible(c, key)
    local cfg = block.cfg
    if cfg.hidden[key] then return false end
    if cfg.scope == "realm" and c.realm ~= ns.realm then return false end
    return true
end

function block:GetText()
    local cfg = self.cfg
    if cfg.barShows == "ilvl" then
        local ilvl = ItemLevel()
        return ilvl and ezCore.Decimal(ilvl, 1) or "?"   -- Dezimalzeichen der Spielsprache (T16-2)
    elseif cfg.barShows == "rested" then
        local full = 0
        for key, c in pairs(ezCore.Chars()) do
            local rested = Visible(c, key) and ns.EstimateRested(c)
            if rested and c.xpMax and rested >= c.xpMax * 1.5 - 1 then full = full + 1 end
        end
        return L.ALTS_RESTED_FULL:format(full)
    elseif cfg.barShows == "lockouts" then
        return L.LOCK_COUNT:format(ns.Lockouts.Total(Visible))
    end
    local count = 0
    for key, c in pairs(ezCore.Chars()) do
        if Visible(c, key) then count = count + 1 end
    end
    return tostring(count)
end

local function SortedList()
    local cfg = block.cfg
    local list = ns.Characters(function(c, key) return Visible(c, key) end)
    if cfg.sort ~= "name" then
        table.sort(list, function(a, b)
            local x, y
            if cfg.sort == "level" then
                x, y = a.c.level or 0, b.c.level or 0
            elseif cfg.sort == "money" then
                x, y = a.c.money or 0, b.c.money or 0
            else
                x, y = a.c.lastSeen or 0, b.c.lastSeen or 0
                if a.isMe then x = math.huge end
                if b.isMe then y = math.huge end
            end
            if x ~= y then return x > y end
            return a.key < b.key
        end)
    end
    return list
end

function block:OnTooltip(tooltip)
    local cfg = self.cfg
    local cols = cfg.cols
    local maxLevel = ns.MaxLevel()
    local totalMoney, totalPlayed, count = 0, 0, 0
    for _, entry in ipairs(SortedList()) do
        local c = entry.c
        count = count + 1
        local left = ns.CharName(c, entry.key)
        if cols.level and c.level then
            local lvl = c.level >= maxLevel and ns.Gold(c.level) or ns.White(c.level)
            left = lvl .. "  " .. left
        end
        local parts = {}
        if cols.rested and c.level and c.level < maxLevel then
            local rested = ns.EstimateRested(c)
            if rested and c.xpMax and c.xpMax > 0 then
                local pct = rested / c.xpMax * 100
                local text = ns.BlueCode() .. L.ALTS_RESTED_SHORT:format(ns.Round(pct)) .. "|r"
                if c.xp then text = ns.Grey(ezCore.Percent(math.floor(c.xp / c.xpMax * 100))) .. " " .. text end
                parts[#parts + 1] = text
            end
        end
        local ilvl = cols.ilvl and ItemLevelOf(entry.key)
        if ilvl then parts[#parts + 1] = ns.Grey(L.ILVL_SHORT .. " " .. ("%.0f"):format(ilvl)) end
        if cols.zone and c.zone then parts[#parts + 1] = ns.Grey(c.zone) end
        if cols.played then
            local played = ns.PlayedNow(c)
            if played then
                parts[#parts + 1] = ns.Grey(ns.Duration(played, true))
                totalPlayed = totalPlayed + played
            end
        end
        if cols.seen then
            parts[#parts + 1] = entry.isMe and ns.GREEN .. L.ONLINE .. "|r" or ns.Grey(ns.Ago(c.lastSeen))
        end
        if cols.money then
            parts[#parts + 1] = ns.Money(c.money or 0)
            totalMoney = totalMoney + (c.money or 0)
        end
        ns.TipDoubleLine(tooltip, left, table.concat(parts, "  "), "highlight", "highlight")
    end
    tooltip:AddLine(" ")
    ns.TipDoubleLine(tooltip, L.ALTS_COUNT, count, "normal", "highlight")
    if cols.money then ns.TipDoubleLine(tooltip, L.TOTAL, ns.Money(totalMoney), "normal", "highlight") end
    if cols.played and totalPlayed > 0 then
        ns.TipDoubleLine(tooltip, L.PLAYED_TOTAL, ns.Duration(totalPlayed, true), "normal", "highlight")
    end
    local me = ns.me
    if me.hearth then ns.TipDoubleLine(tooltip, L.HEARTH, me.hearth, "normal", "highlight") end
    if cfg.lockouts then self:AddLockouts(tooltip) end
    if cfg.cooldowns then self:AddCooldowns(tooltip) end
end

-- Laufende Berufs-Abklingzeiten aller Charaktere (z. B. Transmutation), früheste zuerst.
function block:AddCooldowns(tooltip)
    local prof = ezCore.Professions
    if not (prof and type(prof.AllCooldowns) == "function") then return end
    local rows = {}
    for _, e in ipairs(prof.AllCooldowns()) do
        local c = ezCore.Char(e.char)
        if c and Visible(c, e.char) then rows[#rows + 1] = { e = e, c = c } end
    end
    if #rows == 0 then return end
    tooltip:AddLine(" ")
    ns.TipLine(tooltip, L.CD_TITLE, "normal")
    for _, r in ipairs(rows) do
        local left = ns.CharName(r.c, r.e.char) .. "  " .. ns.Grey(r.e.name or "?")
        ns.TipDoubleLine(tooltip, left, L.CD_READY_IN:format(ns.Duration(r.e.left, true)), "highlight", "highlight")
    end
end

ezCore.Listen("PROF_COOLDOWNS_CHANGED", function() ns.QueueUpdate(block) end, "ezPanel")

---------------------------------------------------------------------------
-- Sperren
---------------------------------------------------------------------------

local function Progress(l)
    local total = l.total
    if not total or total <= 0 then return "" end
    local done = l.done or 0
    local text = ("%d/%d"):format(done, total)
    if done >= total then return ns.RED .. text .. "|r" end
    return ns.WHITE .. text .. "|r"
end

local function GroupTitle(g)
    local extra = g.worldBoss and L.LOCK_WORLD_BOSS or g.diff
    if not extra and g.size then extra = L.LOCK_SIZE:format(g.size) end
    return extra and (g.name .. " " .. ns.Grey("(" .. extra .. ")")) or g.name
end

function block:AddLockouts(tooltip)
    local cfg = self.cfg
    local now = time()
    local groups = ns.Lockouts.ByInstance(Visible)
    local recent, nextFree = ns.Lockouts.RecentInstances()
    tooltip:AddLine(" ")
    ns.TipLine(tooltip, L.LOCK_TITLE, "normal")
    if #groups == 0 then ns.TipLine(tooltip, L.LOCK_NONE, "hint") end
    for _, g in ipairs(groups) do
        ns.TipDoubleLine(tooltip, GroupTitle(g), L.LOCK_RESET:format(ns.Duration(g.resetAt - now, true)), "highlight", "hint")
        for _, e in ipairs(g.chars) do
            local l = e.lock
            local right = Progress(l)
            if l.ext then right = right .. " " .. ns.Grey(L.LOCK_EXTENDED) end
            ns.TipDoubleLine(tooltip, "   " .. ns.CharName(e.c, e.key), right, "highlight", "highlight")
            if cfg.lockBosses and type(l.bosses) == "table" then
                local killed = {}
                for _, boss in ipairs(l.bosses) do
                    if boss.k then killed[#killed + 1] = boss.n end
                end
                if #killed > 0 then ns.TipLine(tooltip, "      " .. table.concat(killed, ", "), "hint", true) end
            end
        end
    end
    local limit = cfg.instanceLimit or 0
    local text = limit > 0 and ("%d/%d"):format(recent, limit) or tostring(recent)
    if limit > 0 and recent >= limit then text = ns.RED .. text .. "|r" end
    if nextFree and recent > 0 then text = text .. " " .. ns.Grey(L.LOCK_NEXT_FREE:format(ns.Duration(nextFree, true))) end
    ns.TipDoubleLine(tooltip, L.LOCK_RECENT, text, "normal", "highlight")
end

-- Für den Baustein „Meldungen“: Instanzgrenze fast oder ganz erreicht (nur mit eingestellter Grenze).
function block:Warnings()
    local limit = self.cfg.instanceLimit or 0
    if limit <= 0 then return nil end
    local recent, nextFree = ns.Lockouts.RecentInstances()
    if recent < limit - 1 then return nil end
    return { L.ALERT_INSTANCES:format(recent, limit, ns.Duration(nextFree or 0, true)) }
end

-- Blizzards Schlachtzugsinformationen (Freunde → Schlachtzug → Schlachtzugsinformationen).
local function OpenRaidInfo()
    return ezCore.TogglePanel("raidinfo")   -- im Kampf: Hinweis von ezCore
end

function block:OnClick(button)
    if button == "LeftButton" then OpenRaidInfo() end
end

function block:OnMenu(root)
    local cfg = self.cfg
    local bar = root:CreateButton(L.MENU_BAR_SHOWS)
    ns.MenuRadio(bar, L.ALTS_SHOW_COUNT, cfg, "barShows", "count", self)
    ns.MenuRadio(bar, L.ALTS_SHOW_ILVL, cfg, "barShows", "ilvl", self)
    ns.MenuRadio(bar, L.ALTS_SHOW_RESTED, cfg, "barShows", "rested", self)
    ns.MenuRadio(bar, L.ALTS_SHOW_LOCKOUTS, cfg, "barShows", "lockouts", self)

    local cols = root:CreateButton(L.MENU_COLUMNS)
    for _, key in ipairs({ "level", "rested", "money", "zone", "seen", "played", "ilvl" }) do
        ns.MenuCheck(cols, L["ALTS_COL_" .. key], cfg.cols, key, self)
    end

    local tip = root:CreateButton(L.MENU_TOOLTIP)
    ns.MenuCheck(tip, L.CD_SHOW, cfg, "cooldowns", self)
    tip:CreateDivider()
    ns.MenuRadio(tip, L.SCOPE_REALM, cfg, "scope", "realm", self)
    ns.MenuRadio(tip, L.SCOPE_ALL, cfg, "scope", "all", self)
    tip:CreateDivider()
    ns.MenuRadio(tip, L.SORT_NAME, cfg, "sort", "name", self)
    ns.MenuRadio(tip, L.SORT_LEVEL, cfg, "sort", "level", self)
    ns.MenuRadio(tip, L.SORT_MONEY, cfg, "sort", "money", self)
    ns.MenuRadio(tip, L.SORT_SEEN, cfg, "sort", "seen", self)

    local chars = root:CreateButton(L.MENU_CHARACTERS)
    -- „Alle auswählen / Alle abwählen“ über den Charakteren (Design-System 2.11; gemerkt in cfg.hidden)
    ns.MenuAllToggle(chars, ns.Characters(), function(entry) return not cfg.hidden[entry.key] end,
        function(entry, on) cfg.hidden[entry.key] = (not on) or nil end, function() ns.QueueUpdate(self) end)
    for _, entry in ipairs(ns.Characters()) do
        local key = entry.key
        chars:CreateCheckbox(ns.CharName(entry.c, key), function() return not cfg.hidden[key] end, function()
            cfg.hidden[key] = not cfg.hidden[key] or nil
            ns.QueueUpdate(self)
            return MenuResponse and MenuResponse.Refresh
        end)
    end

    local locks = root:CreateButton(L.LOCK_MENU)
    ns.MenuCheck(locks, L.LOCK_SHOW, cfg, "lockouts", self)
    ns.MenuCheck(locks, L.LOCK_SHOW_BOSSES, cfg, "lockBosses", self)
    local limit = locks:CreateButton(L.LOCK_LIMIT)
    ns.MenuRadio(limit, L.LOCK_LIMIT_NONE, cfg, "instanceLimit", 0, self)
    -- die Grenze von WoW Forever mit Quelle; die frühere Auswahl 10 entfällt (ns.MigrateInstanceLimit)
    ns.MenuRadio(limit, L.LOCK_LIMIT_FOREVER:format(ns.INSTANCE_LIMIT), cfg, "instanceLimit", ns.INSTANCE_LIMIT, self)
    -- ein anderer gespeicherter Wert (z. B. aus einem Profil-Import) bleibt sichtbar und gewählt, bis du umschaltest
    local own = tonumber(cfg.instanceLimit)
    if own and own > 0 and own ~= ns.INSTANCE_LIMIT then
        ns.MenuRadio(limit, L.LOCK_LIMIT_OWN:format(own), cfg, "instanceLimit", cfg.instanceLimit, self)
    end
    locks:CreateDivider()
    locks:CreateButton(L.LOCK_OPEN_RAIDINFO, OpenRaidInfo)
    locks:CreateButton(L.LOCK_REFRESH, function() ns.Lockouts.Request() end)

    if RequestTimePlayed then
        root:CreateButton(L.MENU_REQUEST_PLAYED, function() RequestTimePlayed() end)
    end
end
