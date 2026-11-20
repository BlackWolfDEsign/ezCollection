local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    „In Gilde einladen“ im Rechtsklick-Menü der Spieler (Welle 16, Wunsch des Nutzers vom 15.11.2026: „rechtsklick
    auf charakter(rahmen) muss in gilde einladen ermöglichen“). Blizzards Menüs bleiben Blizzards (Leitlinie 1):
    ezSocial hängt über Menu.ModifyMenu einen Eintrag an, liest nur aus contextData und schreibt nichts in Blizzards
    Tabellen (Leitlinie 5).

    Wo: die Spieler-Menüs aus ezCore (Core.Menu.PLAYER_MENUS) ohne eigenen Charakter, Gegenfraktion, Offline,
    Gildenliste und Battle.net-Gemeinschaften – also Gruppen- und Raidrahmen, Raid-Liste, Zielfenster und Fokus mit
    einem Spieler, Chat-Namen, Wer-Liste und Freunde online (MENU_UNIT_FRIEND), Kanal-Liste, Gemeinschaften,
    „Kürzlich gespielt“ – dazu Battle.net-Freunde, die gerade WoW Forever spielen (ihr Charakter).
    Wann: nur, wenn du in einer Gilde bist und einladen darfst (IsInGuild, CanGuildInvite – dieselbe Abfrage nutzt
    Blizzard für den Eintrag „Einladen“ der Gildenliste), der Spieler ein Spieler ist, nicht du selbst, kein Mitglied
    deiner Gilde (UnitIsInMyGuild, C_GuildInfo.MemberExistsByName, sonst ezCores Kontakte), online (mit Einheit
    UnitIsConnected wie Blizzards eigene Menüs; Gemeinschaften: clubMemberInfo.presence) und – wo der Client es
    sagt – deiner Fraktion (UnitFactionGroup; Battle.net: factionName; Gemeinschaften: clubMemberInfo.faction). Ein gesperrter Wert (Leitlinie 6) heißt:
    kein Eintrag. Sonst steht nichts da – kein ausgegrauter Eintrag ohne Erklärung. Ohne Einheit (Chat, Freunde,
    Wer-Liste) kennt der Client die Fraktion nicht; dann antwortet Blizzard selbst, falls sie nicht passt.
    Klick: C_GuildInfo.Invite(name) (Rückfall GuildInvite), nur auf den Klick des Spielers. Der Name ist der volle
    Name wie in Blizzards eigenem Einladen (Forever: „Vorname Nachname“, sonst „Name-Realm“, Core.FullName).
    Rücksicht (Leitlinie 9): Steht im Menü schon ein Eintrag mit demselben Text (Blizzard oder ein anderes Addon),
    legt ezSocial keinen zweiten an. Schalter menuGuildInvite (ab Werk an).

    GuildInvite.Tags() → Tags der Menüs     GuildInvite.CanInvite() → true, Gilde | false, Grund
    GuildInvite.Target(contextData) → voller Name | nil, Grund ("secret", "noplayer", "self", "faction", "member",
        "offline", "nocharacter", "none")
    GuildInvite.Listed(root) → steht der Eintrag schon im Menü?
    GuildInvite.AddEntry(root, contextData) → true | false, Grund     GuildInvite.Invite(name) → true | false
    GuildInvite.Hook() → true, sobald die Menüs ergänzt sind
]]
local GI = {}
ns.GuildInvite = GI

local hooked = false

-- Text, wenn er frei und nicht leer ist.
local function Text(value)
    if Core.IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
    return value
end

-- Battle.net-Freunde zeigen ein Konto; eingeladen wird ihr Charakter in diesem Spiel.
GI.EXTRA_TAGS = { "MENU_UNIT_BN_FRIEND" }

function GI.Tags()
    local menu = Core.Menu
    if type(menu) ~= "table" or type(menu.PlayerMenus) ~= "function" then return {} end
    local tags = menu.PlayerMenus({ self = false, enemy = false, offline = false, guild = false, bnet = false })
    for _, tag in ipairs(GI.EXTRA_TAGS) do tags[#tags + 1] = tag end
    return tags
end

function GI.CanInvite()
    if Core.Bool(Core.Call(rawget(_G, "IsInGuild")), false) ~= true then return false, "noguild" end
    local can = rawget(_G, "CanGuildInvite")
    if type(can) ~= "function" then return false, "unknown" end
    if Core.Bool(Core.Call(can), false) ~= true then return false, "rights" end
    return true, Text((Core.Call(rawget(_G, "GetGuildInfo"), "player")))
end

local function MyFaction()
    return Text((Core.Call(rawget(_G, "UnitFactionGroup"), "player")))
end

-- Mitglied deiner Gilde? true, false oder nil (gesperrt). Zuerst Blizzards Antwort, dann ezCores Kontakte.
local function IsMember(full, unit)
    if unit then
        local answer = Core.Call(rawget(_G, "UnitIsInMyGuild"), unit)
        if Core.IsSecret(answer) then return nil end
        if answer == true then return true end
    end
    local info = rawget(_G, "C_GuildInfo")
    if type(info) == "table" then
        local answer = Core.Call(info.MemberExistsByName, full)
        if Core.IsSecret(answer) then return nil end
        if answer == true then return true end
    end
    local contact = Core.Contact(full)
    if type(contact) == "table" and type(contact.sources) == "table" and contact.sources.guild then return true end
    return false
end

local function UnitTarget(unit)
    local is = Core.UnitIs(unit)                     -- vorhanden und Spieler; nil = gesperrt oder unbekannt
    if is == false then return nil, "noplayer" end
    if is ~= true then return nil, "secret" end
    local isSelf = Core.UnitIs(unit, "player")
    if isSelf == true then return nil, "self" end
    if isSelf == nil then return nil, "secret" end
    -- Wie Blizzards eigene Menüs (UnitPopupSharedButtonMixins: UnitIsConnected): ein Gruppen- oder Raidmitglied, das
    -- offline ist, behält seinen Rahmen und sein Menü, eine Einladung fände es aber nicht.
    local connected = Core.Call(rawget(_G, "UnitIsConnected"), unit)
    if Core.IsSecret(connected) then return nil, "secret" end
    if connected == false then return nil, "offline" end
    local mine = MyFaction()
    if mine then
        local theirs = Core.Call(rawget(_G, "UnitFactionGroup"), unit)
        if Core.IsSecret(theirs) then return nil, "secret" end
        if theirs ~= mine then return nil, "faction" end
    end
    local full = Core.UnitFullName(unit)
    if not full then return nil, "secret" end
    if Core.IsSelf(full) then return nil, "self" end
    return full, nil, unit
end

local function BNTarget(id)
    local info = Core.BNInfoByID(id)
    local full = Core.BNCharacter(info)
    if not full then return nil, "nocharacter" end
    local mine = MyFaction()
    local faction = mine and Core.Peek(info.gameAccountInfo, "factionName")
    if Core.IsSecret(faction) then return nil, "secret" end
    if mine and type(faction) == "string" and faction ~= "" and faction ~= mine then return nil, "faction" end
    return full
end

-- Mitglied einer Gemeinschaft (Menü COMMUNITIES_WOW_MEMBER): Blizzards Mitgliederliste zeigt auch Offline-Mitglieder
-- und legt dann kein eigenes Menü an; ob jemand online ist, steht nur in contextData.clubMemberInfo.presence, die
-- Fraktion in clubMemberInfo.faction (Enum.PvPFaction). Gibt den Grund zurück, aus dem kein Eintrag kommt, sonst nil.
local function ClubMemberBlock(contextData)
    local info = Core.Peek(contextData, "clubMemberInfo")
    if Core.IsSecret(info) then return "secret" end
    if type(info) ~= "table" then return nil end
    local presence = Core.Peek(info, "presence")
    if Core.IsSecret(presence) then return "secret" end
    local enum = rawget(_G, "Enum")
    local presences = type(enum) == "table" and enum.ClubMemberPresence
    if type(presences) == "table" and presence ~= nil and presence == presences.Offline then return "offline" end
    local faction = Core.Peek(info, "faction")
    if Core.IsSecret(faction) then return "secret" end
    local factions = type(enum) == "table" and enum.PvPFaction
    local mine = MyFaction()
    if mine and faction ~= nil and type(factions) == "table" then
        local theirs = (faction == factions.Horde and "Horde") or (faction == factions.Alliance and "Alliance") or nil
        if theirs and theirs ~= mine then return "faction" end
    end
    return nil
end

local function NameTarget(contextData)
    local block = ClubMemberBlock(contextData)
    if block then return nil, block end
    local name = Core.Peek(contextData, "name")
    if Core.IsSecret(name) then return nil, "secret" end
    if type(name) ~= "string" or name == "" then return nil, "none" end
    -- server ist der Realm, auf Forever der Nachname (Blizzard: surname); Core.FullName unterscheidet beides.
    local second = Core.Peek(contextData, "server") or Core.Peek(contextData, "surname")
    if Core.IsSecret(second) then return nil, "secret" end
    if type(second) == "string" and second ~= "" and not name:find("-", 1, true) then name = name .. "-" .. second end
    return Core.FullName(name)
end

function GI.Target(contextData)
    if Core.IsSecret(contextData) or type(contextData) ~= "table" then return nil, "none" end
    local unit = Core.Peek(contextData, "unit")
    if Core.IsSecret(unit) then return nil, "secret" end
    local full, why
    if type(unit) == "string" and unit ~= "" then
        full, why = UnitTarget(unit)
    else
        unit = nil
        local id = Core.Peek(contextData, "bnetIDAccount")
        if Core.IsSecret(id) then return nil, "secret" end
        if id ~= nil then
            full, why = BNTarget(id)
        else
            full, why = NameTarget(contextData)
        end
    end
    if not full then return nil, why or "none" end
    if Core.IsSelf(full) then return nil, "self" end
    local member = IsMember(full, unit)
    if member == nil then return nil, "secret" end
    if member then return nil, "member" end
    return full
end

local function ElementText(desc)
    local util = rawget(_G, "MenuUtil")
    if type(util) == "table" and type(util.GetElementText) == "function" then
        local text = Text((Core.Call(util.GetElementText, desc)))
        if text then return text end
    end
    return Text(Core.Peek(desc, "text"))
end

-- Sucht in root und eine Ebene darunter einen Eintrag mit dem Text von „In Gilde einladen“ (Groß/Klein egal).
local function Scan(desc, want, depth)
    if type(desc) ~= "table" or type(desc.EnumerateElementDescriptions) ~= "function" then return false end
    for _, child in desc:EnumerateElementDescriptions() do
        local text = ElementText(child)
        if text and text:lower() == want then return true end
        if depth < 2 and Scan(child, want, depth + 1) then return true end
    end
    return false
end

function GI.Listed(root)
    local ok, found = pcall(Scan, root, L.MENU_GUILD_INVITE:lower(), 1)
    return ok and found == true
end

-- Tooltip: „Lädt <Name> in deine Gilde <Gilde> ein – Blizzard schickt die Einladung, <Name> muss annehmen.“
function GI.TipText(name, guild)
    local who = Core.ShortName(name)
    local text = guild and L.MENU_GUILD_INVITE_TIP or L.MENU_GUILD_INVITE_TIP_NO_NAME
    text = text:gsub("{name}", function() return who end)
    return (text:gsub("{guild}", function() return guild or "" end))
end

function GI.Invite(name)
    if Core.IsSecret(name) or type(name) ~= "string" or name == "" then return false end
    local info = rawget(_G, "C_GuildInfo")
    local fn = type(info) == "table" and info.Invite or nil
    if type(fn) ~= "function" then fn = rawget(_G, "GuildInvite") end
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, name)
    if not ok then
        ns.Error(err, "GuildInvite")
        return false
    end
    return true
end

function GI.AddEntry(root, contextData)
    if not ns.Enabled("menuGuildInvite") then return false, "off" end
    if type(root) ~= "table" or type(root.CreateButton) ~= "function" then return false, "none" end
    local can, guild = GI.CanInvite()
    if not can then return false, guild end
    local name, why = GI.Target(contextData)
    if not name then return false, why end
    if GI.Listed(root) then return false, "listed" end
    if type(root.CreateDivider) == "function" then root:CreateDivider() end
    local entry = root:CreateButton(L.MENU_GUILD_INVITE, function() GI.Invite(name) end)
    Core.Menu.Tip(entry, L.MENU_GUILD_INVITE, GI.TipText(name, guild))
    return true
end

function GI.Hook()
    if hooked then return true end
    if not (Menu and type(Menu.ModifyMenu) == "function") then return false end
    local tags = GI.Tags()
    if #tags == 0 then return false end
    for _, tag in ipairs(tags) do
        pcall(Menu.ModifyMenu, tag, function(_, root, contextData) ns.Try("GuildInvite", GI.AddEntry, root, contextData) end)
    end
    hooked = true
    return true
end

ns.OnReady(function() GI.Hook() end)

-- /ezs status: an, aus oder an, aber ohne Gilde bzw. Recht unsichtbar
ns.AddStatusLine(function()
    if not ns.Enabled("menuGuildInvite") then return L.STATUS_GUILD_INVITE_OFF end
    return GI.CanInvite() and L.STATUS_GUILD_INVITE_ON or L.STATUS_GUILD_INVITE_HIDDEN
end)
