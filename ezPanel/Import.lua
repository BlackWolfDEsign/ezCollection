local _, ns = ...
local L = ns.L

--[[
    Einmalige Übernahme aus Titan Panel.

    Titans gespeicherte Einstellungen sind nur da, solange Titan geladen ist.
    Deshalb übernimmt ezPanel beim ersten Start mit beiden Addons automatisch:
      - welche Plugins auf welcher Leiste und Seite stehen (in Titans Reihenfolge)
      - Deckkraft, Schriftgröße, Abstand, Skalierung, automatisches Ausblenden
      - die wichtigsten Plugin-Optionen (Uhr, Gold, XP, Taschen, Reparatur, Ort, Leistung)
      - die Charakterdaten aller Charaktere (Stufe, Gold, Ort, Spielzeit, Logout)
      - eigene Befehle aus Titan UI
    /ep titan wiederholt das jederzeit. Danach kann Titan deaktiviert werden.

    HERKUNFT der Zuordnungen unten (Leitlinien 10 und 11; Gesamtreview 18.11.2026, T5-5): Fakten über ein fremdes
    Addon, kein übernommener Code. Die Schlüssel sind die Namen, unter denen Titan Panel (HonorGoG) seine Plugins und
    Einstellungen in seinen gespeicherten Tabellen führt (TitanSettings, TitanAll, TitanUI_User_Slash – gelesen nur
    beim Übernehmen, solange Titan läuft, nichts hineingeschrieben); die Ziele sind ezPanels eigene Bausteine. Angelegt
    mit ezPanel 1.0.0 (git log -S: 402420e1, 12.11.2026); wie die Namen damals ermittelt wurden, belegt das Repo nicht.
    Titans Lizenz ist nicht geprüft (Titan ist hier nicht installiert); docs/fremd-addons.md, Abschnitt 9, führt das.
    Die Währungsnummern in CURRENCY sind dieselben wie ezCores Currencies.EXTRA (Name und Quelle je Nummer in
    Currencies.EXTRA_INFO, vom Forever-Client bestätigt) – Titans Plugin-Name ist nur der Schlüssel, die Nummer kommt
    aus dem Client; eine Prüfung in Tests/run_tests.lua hält beide gleich.
]]

-- Titan-ID → ezPanel-Baustein
local DIRECT = {
    Location = "location", XP = "xp", Gold = "gold", Clock = "clock", Volume = "volume",
    Bag = "bags", Repair = "repair", Performance = "performance", LootType = "loot",
    Ammo = "ammo", Regen = "regen", Post = "mail", Alts = "alts",
    TITAN_REPUTATION_XP = "reputation", TITAN_OUROM = "gold",
}

local CURRENCY = {
    TITAN_FOREVER_MERCHANTSFAVOR = 3402, TITAN_FOREVER_UNDERMINEREAL = 3469,
    TITAN_DRKTKM = 515, TITAN_PVHNRM = 1792, TITAN_FOREVER_RANKPOINTS = 3468,
}

local PROFESSION = {
    ALC = true, ARC = true, BLA = true, COO = true, ENC = true, ENG = true, FIR = true, FIS = true,
    HER = true, INS = true, JEW = true, LEA = true, MIN = true, SKI = true, TAI = true, MST = true,
}

local STATS = {
    TITAN_STGTHM = "str", TITAN_AGLTYM = "agi", TITAN_STMNM = "sta", TITAN_INLLM = "int", TITAN_SPRTM = "spi",
    TITAN_ARMRM = "armor", TITAN_BLKM = "block", TITAN_DDGM = "dodge", TITAN_PRRM = "parry", TITAN_HSTM = "haste",
    TITAN_MLAM = "ap", TITAN_RAPM = "rap", TITAN_SLLM = "sp",
}

local function Target(titanId)
    if DIRECT[titanId] then return DIRECT[titanId] end
    if CURRENCY[titanId] then return "currencies" end
    if STATS[titanId] then return "stats" end
    -- TitanProfessionsMulti: „ALCM“, „FIRM“ … ohne Präfix, dazu „TITAN_MSTRM“.
    local code = titanId:match("^(%u%u%u)M$") or titanId:match("^TITAN_(%u%u%u)R?M$")
    if code and PROFESSION[code] then return "professions" end
    if titanId:match("^TITAN_") or titanId:match("^AutoHide_") then return nil end
    return "ldb:" .. titanId    -- LDB-Plugins anderer Addons
end

local function Profile()
    local settings = _G.TitanSettings
    if type(settings) ~= "table" or type(settings.Players) ~= "table" then return nil end
    local all = _G.TitanAll
    if type(all) == "table" and all.GlobalProfileUse and settings.Players[all.GlobalProfileName] then
        return settings.Players[all.GlobalProfileName]
    end
    local me = ns.me
    -- Titan schlüsselt nach „Name@Realm“ mit dem lesbaren Realmnamen (ezCore: realmName).
    local key = (me.name or "?") .. "@" .. (me.realmName or me.realm or "?")
    return settings.Players[key]
end

local function Truthy(v) return v == true or v == 1 end

-- Plugin-Optionen, soweit sie eine Entsprechung haben.
local function ImportOptions(id, titanId, p)
    local cfg = ns.db.blocks[id]
    if not cfg or type(p) ~= "table" then return end
    if p.ShowIcon ~= nil then cfg.icon = Truthy(p.ShowIcon) end
    if p.ShowLabelText ~= nil and id ~= "gold" then cfg.label = Truthy(p.ShowLabelText) end
    if p.ShowColoredText ~= nil then cfg.colored = Truthy(p.ShowColoredText) end

    if id == "clock" then
        cfg.h24 = p.Format ~= "12H"
        local mode = p.TimeMode or "Server"
        cfg.mode = (mode:find("%+") and "both") or (mode == "Local" and "local") or "server"
        cfg.offset = mode:find("Adjusted") and tonumber(p.OffsetHour) or 0
        cfg.hideMinimapClock = Truthy(p.HideMapTime)
        cfg.hideCalendarButton = Truthy(p.HideGameTimeMinimap)
    elseif id == "gold" and titanId == "Gold" then
        if Truthy(p.ViewAll) then cfg.show = Truthy(p.AllServers) and "all" or "realm" else cfg.show = "char" end
        cfg.scope = (Truthy(p.AllServers) or Truthy(p.MergeServers)) and "all" or "realm"
    elseif id == "xp" then
        local t = p.DisplayType or ""
        cfg.show = t:find("PerHour") and "rate" or "percent"
    elseif id == "bags" then
        cfg.mode = Truthy(p.ShowUsedSlots) and "used" or "free"
    elseif id == "repair" then
        cfg.cost = Truthy(p.ShowRepairCost)
        -- automatisch reparieren und Gildengeld: seit der Einstellungs-Prüfung vom 19.11.2026 ezCores gemeinsamer
        -- Schaltersatz für ezPanel und ezMerchant (Gruppe vendor). Die Übernahme läuft auch ohne Klick (erster Start
        -- mit Titan), und der Schalter gilt fürs ganze Konto: nur ein „an“ aus Titan schaltet ein, ein „aus“ oder ein
        -- fehlender Titan-Wert schaltet nichts ab – sonst ginge ezMerchants Reparatur unbemerkt aus (Gegenprüfung
        -- 19.11.2026; dieselbe Regel wie Core.AdoptShared: ein „an“ gewinnt)
        if Truthy(p.AutoRepair) then ezCore.SetShared("vendor", "repairAuto", true) end
        if Truthy(p.UseGuildBank) then ezCore.SetShared("vendor", "repairGuild", true) end
        cfg.inventory = Truthy(p.ShowInventory)
        cfg.mode = Truthy(p.ShowMostDamaged) and "lowest" or "total"
    elseif id == "location" then
        if p.ShowZoneText ~= nil then cfg.showZone = Truthy(p.ShowZoneText) end
        if p.ShowSubZoneText ~= nil then cfg.showSubzone = Truthy(p.ShowSubZoneText) end
        if p.ShowCoordsText ~= nil then cfg.coords = Truthy(p.ShowCoordsText) end
        if p.ShowCoordsOnMap ~= nil then cfg.mapCoords = Truthy(p.ShowCoordsOnMap) end
        local fmt = type(p.CoordsFormat) == "string" and p.CoordsFormat or ""
        cfg.precision = fmt:find("%.2f", 1, true) and 2 or fmt:find("%.1f", 1, true) and 1 or (fmt ~= "" and 0) or cfg.precision
    elseif id == "performance" then
        if p.ShowFPS ~= nil then cfg.fps = Truthy(p.ShowFPS) end
        if p.ShowLatency ~= nil then cfg.home = Truthy(p.ShowLatency) end
        if p.ShowWorldLatency ~= nil then cfg.world = Truthy(p.ShowWorldLatency) end
        if p.ShowMemory ~= nil then cfg.memory = Truthy(p.ShowMemory) end
        if tonumber(p.NumOfAddons) then cfg.addons = math.min(40, tonumber(p.NumOfAddons)) end
    elseif id == "currencies" and CURRENCY[titanId] then
        cfg.pinned = cfg.pinned or {}
        cfg.pinned[CURRENCY[titanId]] = true
    elseif id == "stats" and STATS[titanId] then
        cfg.stat = STATS[titanId]
    end
end

local function ImportLayout(profile)
    local panel = profile.Panel
    if type(panel) ~= "table" or type(panel.Buttons) ~= "table" then return 0 end
    local plugins = type(profile.Plugins) == "table" and profile.Plugins or {}

    -- Alles aus, dann Titans Auswahl in Titans Reihenfolge einschalten.
    -- Titan setzt das erste Plugin der rechten Seite an den rechten Rand und die
    -- folgenden links davon; ezPanel ordnet von links nach rechts – rechts also absteigend.
    for _, def in ipairs(ns.blockList) do def.cfg.enabled = false end
    local count, seen = 0, {}
    for i = 1, table.maxn(panel.Buttons) do     -- maxn wie Titan: Lücken in der Liste überspringen
        local titanId = panel.Buttons[i]
        local id = type(titanId) == "string" and Target(titanId)
        if id then
            ns.db.blocks[id] = ns.db.blocks[id] or {}
            local cfg = ns.db.blocks[id]
            local p = plugins[titanId] or {}
            -- Plugins von Titans unteren Leisten landen mit auf der einen Leiste oben.
            local zone = Truthy(p.DisplayOnRightSide) and "right" or "left"
            if not cfg.enabled then
                cfg.enabled = true
                cfg.zone = zone
                seen[zone] = (seen[zone] or 0) + 1
                cfg.order = zone == "right" and (1000 - seen[zone] * 10) or seen[zone] * 10
                count = count + 1
            end
            ImportOptions(id, titanId, p)
        end
    end

    -- Leisten (Titan speichert sie unter BarVars, ältere Versionen direkt im Profil)
    local bars = type(profile.BarVars) == "table" and profile.BarVars or profile
    local main = bars.Titan_Bar__Display_Bar
    -- Über ns.SetSetting (V-086): Leiste, „Platz oben“, Spielwelt und die Einstellungsseite ziehen sofort nach.
    local function Set(key, value)
        if ns.S[key] ~= value then ns.SetSetting(key, value) end
    end
    Set("topBar", true)   -- ezPanel hat nur die obere Leiste; sie zeigt alles, was Titan oben und unten hatte
    if type(main) == "table" then
        Set("autoHideTop", main.auto_hide == true)
        Set("hideInCombat", main.hide_in_combat == true)
    end
    if tonumber(panel.FontSize) then Set("fontSize", math.max(8, math.min(18, tonumber(panel.FontSize)))) end
    if tonumber(panel.ButtonSpacing) then Set("spacing", math.max(4, math.min(40, tonumber(panel.ButtonSpacing)))) end
    if tonumber(panel.Scale) then Set("scale", math.max(0.5, math.min(2, tonumber(panel.Scale)))) end
    if Truthy(panel.LockButtons) then Set("locked", true) end
    if panel.HideTipsInCombat ~= nil then Set("tooltipsInCombat", not Truthy(panel.HideTipsInCombat)) end
    return count
end

-- Charakterdaten aus Titans „Info“-Tabellen (nur Lücken füllen, nichts überschreiben).
local function ImportCharacters()
    local players = _G.TitanSettings and _G.TitanSettings.Players
    if type(players) ~= "table" then return 0 end
    local count = 0
    for toon, data in pairs(players) do
        local info = type(data) == "table" and data.Info
        local name, realm
        if type(toon) == "string" then name, realm = toon:match("^(.-)@(.+)$") end
        if type(info) == "table" and name and realm and name ~= "" then
            local c, created = ezCore.CharRecord(name, realm, true)
            if created then count = count + 1 end
            c.name = c.name or name
            c.realm = c.realm or ezCore.NormalizeRealm(realm)
            c.realmName = c.realmName or realm
            c.class = c.class or info.className
            c.faction = c.faction or info.factionName
            c.level = c.level or tonumber(info.level)
            c.money = c.money or tonumber(info.gold_toon)
            c.lastSeen = c.lastSeen or tonumber(info.logout)
            c.played = c.played or tonumber(info.played_total)
            c.zone = c.zone or info.zoneText
            c.hearth = c.hearth or info.hearth_binding
            c.xp = c.xp or tonumber(info.unit_xp)
            c.xpMax = c.xpMax or tonumber(info.unit_xp_max)
            -- Die Stufe des gespielten Charakters schreibt nur ezCore (sonst bliebe GEAR_CHANGED aus).
            if c ~= ezCore.me then c.ilvl = c.ilvl or tonumber(info.itemLevelEquipped) end
        end
    end
    return count
end

local SKIP_COMMANDS = { reload = true, rl = true, fstack = true, framestack = true, eventtrace = true, etrace = true }

local function ImportCommands()
    local list = _G.TitanUI_User_Slash
    local tools = ns.db.blocks.tools
    if type(list) ~= "table" or not tools then return end
    tools.commands = tools.commands or {}
    local have = {}
    for _, cmd in ipairs(tools.commands) do have[cmd:lower()] = true end
    for _, entry in ipairs(list) do
        local cmd = type(entry) == "table" and entry.command
        if type(cmd) == "string" and cmd ~= "" then
            local word = cmd:match("^/?(%S+)")
            if word and not SKIP_COMMANDS[word:lower()] and not word:lower():match("^titan") then
                local full = "/" .. cmd:gsub("^/", "")
                local known = not ns.SlashHandler or ns.SlashHandler(full:match("^(/%S+)"))
                if known and not have[full:lower()] then
                    table.insert(tools.commands, full)
                    have[full:lower()] = true
                end
            end
        end
    end
end

-- force: von /ep titan (wiederholt die Übernahme und meldet das Ergebnis).
function ns.ImportTitan(force)
    local db = ns.db
    if db.titanImported and not force then return end
    if not ezCore.OtherAddOn("Titan") or type(_G.TitanSettings) ~= "table" then
        if force then ns.Print(L.IMPORT_NO_TITAN) end
        db.titanImported = true
        return
    end
    local profile = Profile()
    local blocks = 0
    if profile then blocks = ImportLayout(profile) end
    local chars = ImportCharacters()
    ImportCommands()
    db.titanImported = true
    ns.Print(L.IMPORT_DONE:format(blocks, chars))
    ns.Print(L.IMPORT_DISABLE_TITAN)

    if force and ns.ready then
        -- Laufende Bausteine an die neuen Einstellungen anpassen.
        for _, def in ipairs(ns.blockList) do
            ns.SetBlockEnabled(def.id, def.cfg.enabled)
        end
        ns.ApplyBarStyle()
        ns.UpdateBarVisibility()
        ns.ApplyViewport()
        if ns.ApplyTopSpace then ns.ApplyTopSpace() end
        ns.RequestLayout()
    end
end

-- Läuft noch eine andere Infoleiste (Titan Panel …), liegen zwei Leisten übereinander: einmal pro Login
-- darauf hinweisen. Erkennung in ezCore (ns.OtherFor("infoBar") aus dem Gerüst).
ns.OnReady(function()
    local other = ns.OtherFor("infoBar")
    if other then
        C_Timer.After(8, function() ns.Print(L.INFOBAR_STILL_ACTIVE:format(other, other)) end)
    end
end)
