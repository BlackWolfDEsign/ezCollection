local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Makros nach Art – Kinds.lua (Welle 15, Paket „Makros nach Art gruppieren und filtern“). Wunsch des Nutzers vom
    15.11.2026 abends, wörtlich: „und das makros kategorisiert sind, gruppiert sind im ezmacro? sinnvoll?“ (ROADMAP.md,
    „Entscheidungen des Nutzers“; docs/roadmap/ezMacro.md). Gebaut nach Empfehlung, Antwort offen.

    Jedes Makro in Blizzards Makroverwaltung bekommt eine Art: Heilen, Buffs, Kampf, Emotes, Berufe oder Sonstiges.
    Reihenfolge der Quellen (Leitlinie 11, jede Angabe nennt ihre Quelle):
      1. eigene Zuordnung des Spielers (gemerkt je Makroname: allgemeine Makros kontoweit, Charakter-Makros je
         Charakter – ezMacroDB.macroKind[„account“ | charKey][Name])
      2. Kennzeichen der Module (ezCores Core.MacroBadge: ezHeal „Maus-Überfahren“ » Heilen, ezBuff „Durchbuffen“ »
         Buffs; ein ezHeal-Makro mit einem Buff-Zauber, etwa Wasseratmung, zählt zu Buffs)
      3. Inhalt: Zauber hinter /cast, /use, /castsequence, #showtooltip – Heilen, Bannen und Wiederbeleben laut
         ezCores Zauber-Wissen (Spells.HEALS, DISPELS, RESURRECTS) » Heilen; Buffs laut Spells.BuffKey und
         Spells.HELPERS » Buffs; Berufe (Angeln, Berufe des Charakters laut Core.Professions, Entzaubern) » Berufe;
         /startattack, /petattack, [harm] oder ein anderer Zauber » Kampf; nur Emotes und Chat-Zeilen » Emotes
      4. sonst Sonstiges
    Die Erkennung bleibt in ezMacro (Auftrag: keine neue ezCore-Datei); sie nutzt nur vorhandene ezCore-Dienste.

    Sichtbar in Blizzards Makroverwaltung (Leitlinie 1, das Original; Blizzard_MacroUI, Zweig forever):
      - Knopf „Art: Alle“ an der Trennleiste unter dem Symbolraster, links neben „Speichern“ (über dem Raster liegen
        Blizzards Reiter bis 6 px an die erste Reihe – kein Platz). Linksklick: Menü „Zeigen“ (Alle, je Art mit Zahl)
        und „Gewähltes Makro einordnen“. Leitlinie 3: jede Funktion hat diesen Knopf.
      - Das Raster blendet Makros anderer Art ab (blass und grau), statt sie auszublenden: ausblenden hieße Blizzards
        Datenquelle des Rasters ersetzen (Leitlinie 5). Beim Öffnen der Makroverwaltung steht der Filter auf „Alle“.
      - Tooltip am Symbol: Name, Art und woher sie kommt; Rechtsklick aufs Symbol: Art ändern (zusätzlich zum Knopf).
    Taint-sicher (Leitlinie 5): nur hooksecurefunc an MacroFrame.Update und MacroFrame.MacroSelector.RunSetup und
    HookScript an den Symbolen; nichts wird in Blizzards Tabellen geschrieben, Makros werden weder verschoben noch
    umbenannt. Abblenden (SetAlpha, SetDesaturated) und Tooltips sind keine geschützten Aktionen.
    Abschaltbar: Schalter „Makros nach Art“ (macroKinds, ab Werk an).

      Kinds.LIST                         Arten in Anzeigereihenfolge
      Kinds.Detect(name, body)           » art, quelle, detail (ohne eigene Zuordnung)
      Kinds.Of(index)                    » art, quelle, detail, eigen (true: vom Spieler zugeordnet) | nil (kein Makro)
      Kinds.Set(index, art | nil)        eigene Zuordnung merken bzw. löschen (nil: zurück zur Erkennung) » true
      Kinds.Filter(), Kinds.SetFilter(art | "all")
      Kinds.Shows(index)                 » passt das Makro zum Filter?
      Kinds.Counts(scope)                » { [art] = Zahl, all = Zahl } für „account“ oder „char“
      Kinds.SourceText(quelle, detail)   » Text der Quelle für Tooltip und Menü
]]

local Kinds = {}
ns.Kinds = Kinds

Kinds.LIST = { "heal", "buff", "combat", "emote", "profession", "other" }
Kinds.ACCOUNT = "account"
Kinds.DIM_ALPHA = 0.3

local KNOWN = {}
for _, kind in ipairs(Kinds.LIST) do KNOWN[kind] = true end
Kinds.KNOWN = KNOWN

function Kinds.Enabled()
    return ns.S == nil or ns.S.macroKinds ~= false
end

---------------------------------------------------------------------------
-- Namenslisten aus ezCores Zauber-Wissen (einmal gebaut, klein geschrieben)
---------------------------------------------------------------------------

local Spells = Core.Spells
local lower = string.lower

local function AddName(set, name)
    if type(name) == "string" and name ~= "" then set[lower(name)] = true end
end

-- Name aus dem Client (Spells.Name) und beide Ersatznamen (Spells.FALLBACK), damit die Erkennung auch Makros
-- aus der anderen Sprache kennt.
local function AddSpell(set, id)
    if not Spells then return end
    if type(Spells.Name) == "function" then AddName(set, (Spells.Name(id))) end
    local pair = type(Spells.FALLBACK) == "table" and Spells.FALLBACK[id]
    if type(pair) == "table" then
        AddName(set, pair[1])
        AddName(set, pair[2])
    end
end

local function AddEach(set, data)
    if type(data) ~= "table" then return end
    for _, value in pairs(data) do
        if type(value) == "number" then
            AddSpell(set, value)
        elseif type(value) == "table" then
            AddEach(set, value)
        end
    end
end

local healNames, helperNames
local function HealNames()
    if not healNames then
        healNames = {}
        if Spells then
            AddEach(healNames, Spells.HEALS)
            AddEach(healNames, Spells.DISPELS)
            AddEach(healNames, Spells.RESURRECTS)
        end
    end
    return healNames
end
local function HelperNames()
    if not helperNames then
        helperNames = {}
        if Spells then AddEach(helperNames, Spells.HELPERS) end
    end
    return helperNames
end

-- Berufe: Angeln, die Berufe dieses Charakters (Core.Professions, Namen vom Client) und Entzaubern (13262, Ersatzname
-- in ezCores Zauber-Wissen). Neu gebaut, sobald sich die Berufe ändern.
local DISENCHANT = 13262
local professionNames
local function ProfessionNames()
    if professionNames then return professionNames end
    professionNames = {}
    if Spells and Spells.FISHING then AddSpell(professionNames, Spells.FISHING) end
    AddSpell(professionNames, DISENCHANT)
    local P = Core.Professions
    local ok, read = false, nil
    if P and type(P.Read) == "function" then ok, read = pcall(P.Read) end
    if ok and type(read) == "table" then
        for _, prof in ipairs(read) do
            if type(prof) == "table" then AddName(professionNames, Core.Plain(prof.name)) end
        end
    end
    -- dazu die gemerkte Liste dieses Charakters (Core.Professions.Of): auf Forever liefert GetProfessions teils nichts,
    -- ezCore hebt die Berufe dann aus der Fertigkeitenliste auf (src = "skill")
    local mine = false
    if P and type(P.Of) == "function" and ns.charKey then ok, mine = pcall(P.Of, ns.charKey) end
    if ok and type(mine) == "table" then
        for _, prof in ipairs(mine) do
            if type(prof) == "table" then AddName(professionNames, Core.Plain(prof.name)) end
        end
    end
    return professionNames
end

local clientChat   -- Chat-Befehle aus dem Client (IsChatCommand)

-- Für Prüfungen und nach PROFESSIONS_CHANGED / SPELLS_CHANGED: Listen neu bauen.
function Kinds.ResetNames()
    healNames, helperNames, professionNames, clientChat = nil, nil, nil, nil
end
if Core.Listen then Core.Listen("PROFESSIONS_CHANGED", function() professionNames = nil end, "ezMacro") end

---------------------------------------------------------------------------
-- Emotes und Chat-Zeilen
---------------------------------------------------------------------------

-- Blizzards Emote-Befehle aus dem Client (ezCores Emote-Index: Core.EmoteToken, Welle 23 – vorher eine eigene
-- Schleife über EMOTE<n>_CMD<m>), dazu die Befehle, die selbst ein Emote schreiben. Chat-Zeilen (Sagen, Gruppe,
-- Raid …) zählen mit zu „Emotes“.
local CHAT = {}
for _, cmd in ipairs({ "/e", "/em", "/emote", "/me", "/s", "/say", "/y", "/yell", "/sh", "/shout", "/p", "/party",
    "/ra", "/raid", "/rw", "/i", "/instance", "/bg", "/g", "/guild", "/o", "/officer", "/w", "/whisper", "/t",
    "/tell" }) do
    CHAT[cmd] = true
end
-- Chat-Befehle aus dem Client (Leitlinie 11): Blizzard baut sie aus SLASH_<Art><n> (ChatFrameUtil, ImportListToHash
-- in hash_ChatTypeInfoList) – so kommen übersetzte Befehle des deutschen Clients mit; die Liste oben ist der Rückfall.
local CHAT_TYPES = { "SAY", "YELL", "PARTY", "RAID", "RAID_WARNING", "INSTANCE_CHAT", "GUILD", "OFFICER", "WHISPER",
    "EMOTE", "BATTLEGROUND", "REPLY" }
local function IsChatCommand(cmd)
    if CHAT[cmd] then return true end
    if not clientChat then
        clientChat = {}
        for _, chatType in ipairs(CHAT_TYPES) do
            for i = 1, 20 do
                local text = rawget(_G, "SLASH_" .. chatType .. i)
                if type(text) ~= "string" then break end
                clientChat[lower(text)] = true
            end
        end
        local hash = rawget(_G, "hash_ChatTypeInfoList")
        if type(hash) == "table" then
            for key in pairs(hash) do
                if type(key) == "string" then clientChat[lower(key)] = true end
            end
        end
    end
    return clientChat[cmd] == true
end
-- eigene Befehle: ezMacros Emote- und Ansage-Makros (Emote.lua, Announce.lua)
local OWN_CHAT = { emote = true, ansage = true, ansagen = true, announce = true }

-- Führt der Client diesen Befehl als Emote? (ezCore liest EMOTE<n>_CMD<m> und hash_EmoteTokenList an einer Stelle.)
local function IsEmoteCommand(cmd)
    return type(Core.EmoteToken) == "function" and Core.EmoteToken(cmd) ~= nil
end

---------------------------------------------------------------------------
-- Erkennung aus dem Text
---------------------------------------------------------------------------

local CAST = { ["/cast"] = true, ["/spell"] = true, ["/castsequence"] = true, ["/castrandom"] = true,
    ["/use"] = true, ["/userandom"] = true }
local ATTACK = { ["/startattack"] = true, ["/stopattack"] = true, ["/petattack"] = true }
local PROFESSION_CLICK = { ezmacrofishing = true }

local Trim = Core.Trim   -- ezCore (Gesamtreview 18.11.2026, T16-15; vorher eine eigene Kopie)

-- Zaubernamen einer /cast-Zeile: Bedingungen [..] und reset=… weg, je Glied „;“ bzw. Schritt „,“ ein Name,
-- ohne „!“ und ohne „(Rang n)“.
local function SpellNames(rest, out)
    rest = rest:gsub("%b[]", ""):gsub("reset=%S+", "")
    for part in (rest .. ";"):gmatch("([^;]*);") do
        for name in (part .. ","):gmatch("([^,]*),") do
            name = Trim(name):gsub("^!", ""):gsub("%s*%b()$", "")
            name = Trim(name)
            if name ~= "" and not name:match("^%d+$") then out[#out + 1] = name end
        end
    end
end

-- Art eines Zaubernamens laut ezCores Zauber-Wissen: "heal" | "buff" | "profession" | nil (unbekannt).
local function SpellKind(name)
    local key = lower(name)
    if HealNames()[key] then return "heal" end
    if HelperNames()[key] then return "buff" end
    if Spells and type(Spells.BuffKey) == "function" then
        local ok, buff = pcall(Spells.BuffKey, name)
        if ok and buff then return "buff" end
    end
    if ProfessionNames()[key] then return "profession" end
    return nil
end
Kinds.SpellKind = SpellKind

local function Badge(name, body)
    local MB = Core.MacroBadge
    if not (MB and type(MB.Match) == "function") then return nil end
    local ok, kind, owner = pcall(MB.Match, name, body)
    if ok and kind then return kind, owner end
    return nil
end

function Kinds.Detect(name, body)
    name = type(name) == "string" and name or ""
    body = type(body) == "string" and body or ""
    local spells, casts = {}, {}
    local attack, harm, chat, other = false, false, false, false
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        line = Trim(line)
        local tip = line:match("^#show%a*%s+(.+)$")
        if tip then
            SpellNames(tip, spells)
        elseif line ~= "" and line:sub(1, 1) ~= "#" then
            local cmd, rest = line:match("^(/%S+)%s*(.*)$")
            cmd = cmd and lower(cmd)
            if not cmd then
                other = true
            elseif CAST[cmd] then
                if rest:find("[%[,]%s*harm") then harm = true end   -- nicht „noharm“
                local names = {}
                SpellNames(rest, names)
                for _, n in ipairs(names) do
                    spells[#spells + 1] = n
                    if cmd ~= "/use" and cmd ~= "/userandom" then casts[#casts + 1] = n end
                end
            elseif ATTACK[cmd] then
                attack = true
            elseif cmd == "/click" then
                local button = lower(Trim(rest:gsub("%b[]", "")):match("^(%S*)") or "")
                if PROFESSION_CLICK[button] then spells[#spells + 1] = false end
            elseif cmd == "/ezmacro" then
                if OWN_CHAT[lower(rest:match("^(%S*)") or "")] then chat = true else other = true end
            elseif IsChatCommand(cmd) or IsEmoteCommand(cmd) then
                chat = true
            else
                other = true
            end
        end
    end

    local found = {}
    local firstOf = {}
    for _, n in ipairs(spells) do
        local kind = n == false and "profession" or SpellKind(n)
        if kind then
            found[kind] = true
            firstOf[kind] = firstOf[kind] or (n or nil)
        end
    end

    local badge, owner = Badge(name, body)
    if badge then
        if badge == "group" then return "buff", "badge", owner end
        -- Maus-Makros: ezHeal legt auch Buffs auf Mitspieler an (Vorlage „Buffs“, etwa Wasseratmung) – der Inhalt
        -- entscheidet zwischen Heilen und Buffs
        if found.buff and not found.heal then return "buff", "badge", owner end
        return "heal", "badge", owner
    end
    if found.heal then return "heal", "spell", firstOf.heal end
    if found.buff then return "buff", "spell", firstOf.buff end
    if found.profession then return "profession", "spell", firstOf.profession end
    if attack then return "combat", "attack" end
    if harm then return "combat", "harm" end
    if #casts > 0 then return "combat", "cast", casts[1] end
    if chat and not other then return "emote", "chat" end
    return "other", "none"
end

---------------------------------------------------------------------------
-- Makros, eigene Zuordnung
---------------------------------------------------------------------------

local function MaxAccount()
    if Core.Macro and type(Core.Macro.Limits) == "function" then return (Core.Macro.Limits()) end
    local _, maxAccount = ns.Import.Counts()
    return maxAccount
end

local function ScopeKey(index)
    if index > MaxAccount() then return ns.charKey or "?" end
    return Kinds.ACCOUNT
end

local function Info(index)
    index = tonumber(index)
    if not index or index <= 0 or type(GetMacroInfo) ~= "function" then return nil end
    local name, _, body = GetMacroInfo(index)
    name = Core.Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    local full = ns.Import and ns.Import.BodyOf and ns.Import.BodyOf(index)
    body = Core.Plain(full) or Core.Plain(body)
    return index, name, type(body) == "string" and body or ""
end

local function Store(index, create)
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.macroKind) ~= "table" then
        if not create then return nil end
        db.macroKind = {}
    end
    local key = ScopeKey(index)
    local store = db.macroKind[key]
    if type(store) ~= "table" then
        if not create then return nil end
        store = {}
        db.macroKind[key] = store
    end
    return store
end

function Kinds.Of(index)
    local i, name, body = Info(index)
    if not i then return nil end
    local store = Store(i, false)
    local own = store and store[name]
    if KNOWN[own] then return own, "own", nil, true end
    local kind, source, detail = Kinds.Detect(name, body)
    return kind, source, detail, false
end

function Kinds.Set(index, kind)
    local i, name = Info(index)
    if not i then return false end
    if kind ~= nil and not KNOWN[kind] then return false end
    local store = Store(i, kind ~= nil)
    if store then store[name] = kind end
    Kinds.Refresh()
    return true
end

-- Ein vergessener Twink (ezCore.ForgetChar, Nachricht CHAR_FORGOTTEN): seine eigene Zuordnung der Charakter-Makros
-- geht mit (macroKind[charKey]; Gesamtreview 18.11.2026, Nachsuche zu T4-2). Die allgemeinen Makros („account“)
-- gehören allen Charakteren und bleiben, ebenso Sicherungen und lange Makros (festgelegt 13.11.2026). → true, wenn
-- etwas gemerkt war.
function Kinds.ForgetChar(key)
    local db = ns.db
    if type(key) ~= "string" or key == Kinds.ACCOUNT or key == ns.charKey or type(db) ~= "table"
        or type(db.macroKind) ~= "table" or db.macroKind[key] == nil then
        return false
    end
    db.macroKind[key] = nil
    return true
end
Core.Listen("CHAR_FORGOTTEN", function(key) Kinds.ForgetChar(key) end, "ezMacro")

local filter = "all"
function Kinds.Filter() return filter end
function Kinds.SetFilter(kind)
    if kind ~= "all" and not KNOWN[kind] then kind = "all" end
    filter = kind
    Kinds.Refresh()
    return true
end

function Kinds.Shows(index)
    if filter == "all" or not Kinds.Enabled() then return true end
    local kind = Kinds.Of(index)
    return kind == nil or kind == filter
end

function Kinds.Counts(scope)
    local counts = { all = 0 }
    for _, kind in ipairs(Kinds.LIST) do counts[kind] = 0 end
    local numAccount, maxAccount, numChar = ns.Import.Counts()
    local first, last = 1, numAccount
    if scope == "char" then first, last = maxAccount + 1, maxAccount + numChar end
    for index = first, last do
        local kind = Kinds.Of(index)
        if kind then
            counts[kind] = counts[kind] + 1
            counts.all = counts.all + 1
        end
    end
    return counts
end

function Kinds.Label(kind)
    if kind == "all" then return L.MACRO_KIND_all end
    return L["MACRO_KIND_" .. tostring(kind)] or tostring(kind)
end

function Kinds.SourceText(source, detail)
    if source == "own" then return L.KIND_SRC_own end
    if source == "badge" then return L.KIND_SRC_badge:format(tostring(detail)) end
    if source == "spell" then
        if detail then return L.KIND_SRC_spell:format(detail) end
        return L.KIND_SRC_fishing
    end
    if source == "cast" then return L.KIND_SRC_cast:format(tostring(detail)) end
    if source == "attack" or source == "harm" or source == "chat" then return L["KIND_SRC_" .. source] end
    return L.KIND_SRC_none
end

---------------------------------------------------------------------------
-- Blizzards Makroverwaltung
---------------------------------------------------------------------------

local ui = { hooked = false, buttons = setmetatable({}, { __mode = "k" }), dimmed = setmetatable({}, { __mode = "k" }) }
Kinds.ui = ui

local function Frame() return rawget(_G, "MacroFrame") end

-- Tatsächlicher Index eines Rasterplatzes (Blizzards MacroFrame:GetMacroDataIndex, sonst macroBase + Platz).
local function ActualIndex(selectionIndex)
    local frame = Frame()
    selectionIndex = tonumber(selectionIndex)
    if not (frame and selectionIndex) then return nil end
    local get = Core.Peek(frame, "GetMacroDataIndex")
    if type(get) == "function" then
        local ok, index = pcall(get, frame, selectionIndex)
        if ok and tonumber(index) then return tonumber(index) end
    end
    return (tonumber(Core.Peek(frame, "macroBase")) or 0) + selectionIndex
end
Kinds.ActualIndex = ActualIndex

local function SelectionOf(button)
    local get = Core.Peek(button, "GetSelectionIndex")
    if type(get) == "function" then
        local ok, index = pcall(get, button)
        if ok then return tonumber(index) end
    end
    return tonumber(Core.Peek(button, "selectionIndex"))
end

local function SetDim(button, dim)
    if not dim and not ui.dimmed[button] then return end
    button:SetAlpha(dim and Kinds.DIM_ALPHA or 1)
    local icon = Core.Peek(button, "Icon")
    if icon and icon.SetDesaturated then icon:SetDesaturated(dim and true or false) end
    ui.dimmed[button] = dim or nil
end

local function Paint(button, selectionIndex)
    if type(button) ~= "table" then return end
    local index = ActualIndex(selectionIndex or SelectionOf(button))
    local exists = index and Info(index) ~= nil
    SetDim(button, exists and not Kinds.Shows(index))
end
Kinds.Paint = Paint

local function EachButton(fn)
    local frame = Frame()
    local selector = frame and Core.Peek(frame, "MacroSelector")
    local enum = selector and Core.Peek(selector, "EnumerateButtons")
    if type(enum) ~= "function" then
        for button in pairs(ui.buttons) do fn(button) end
        return
    end
    local ok, iter, state, first = pcall(enum, selector)
    if not ok or type(iter) ~= "function" then return end
    for button in iter, state, first do fn(button) end
end

local function UpdateKindButton()
    local button = ui.kindButton
    if not button then return end
    button:SetShown(Kinds.Enabled())
    button:SetText(L.KIND_BUTTON:format(Kinds.Label(filter)))
end

function Kinds.Refresh()
    if not ui.hooked then return end
    UpdateKindButton()
    EachButton(function(button) Paint(button) end)
end

-- Tatsächlicher Index des in Blizzards Fenster gewählten Makros oder nil.
local function SelectedIndex()
    local frame = Frame()
    local get = frame and Core.Peek(frame, "GetSelectedIndex")
    if type(get) ~= "function" then return nil end
    local ok, selection = pcall(get, frame)
    return ok and ActualIndex(selection) or nil
end
Kinds.SelectedIndex = SelectedIndex

-- Einträge „Art ändern“ für ein Makro (Rechtsklick aufs Symbol und Menü des Knopfs).
local function AddAssign(root, index)
    local i, name = Info(index)
    if not i then return end
    local Menu = Core.Menu
    local kind, source, _, own = Kinds.Of(i)
    Menu.Title(root, L.KIND_MENU_ASSIGN:format(name))
    local function Get() return kind end
    local function Set(value)
        Kinds.Set(i, value)
        return Menu.Close()
    end
    for _, k in ipairs(Kinds.LIST) do
        Menu.Tip(Menu.Radio(root, Kinds.Label(k), Get, Set, k), Kinds.Label(k), L["KIND_TIP_" .. k])
    end
    if own then
        local detected, dsource, ddetail = Kinds.Detect(name, select(3, Info(i)))
        Menu.Tip(Menu.Button(root, L.KIND_MENU_RESET:format(Kinds.Label(detected)), function()
            Kinds.Set(i, nil)
            return Menu.Close()
        end), L.KIND_MENU_RESET_TITLE, Kinds.SourceText(dsource, ddetail))
    end
    return source
end
Kinds.AddAssign = AddAssign

function Kinds.BuildMenu(root)
    local Menu = Core.Menu
    local frame = Frame()
    local tab = frame and Core.Peek(frame, "selectedTab")
    local counts = Kinds.Counts(tab == 2 and "char" or "account")
    Menu.Title(root, L.KIND_MENU_SHOW)
    local function Get() return filter end
    local function Set(value)
        Kinds.SetFilter(value)
        return Menu.Close()
    end
    Menu.Radio(root, L.KIND_COUNT:format(Kinds.Label("all"), counts.all), Get, Set, "all")
    for _, k in ipairs(Kinds.LIST) do
        Menu.Tip(Menu.Radio(root, L.KIND_COUNT:format(Kinds.Label(k), counts[k]), Get, Set, k), Kinds.Label(k),
            L["KIND_TIP_" .. k])
    end
    local selected = SelectedIndex()
    if selected and Info(selected) then
        Menu.Divider(root)
        AddAssign(root, selected)
    end
end

local function ShowTooltip(button)
    if not Kinds.Enabled() then return end
    local index = ActualIndex(SelectionOf(button))
    local i, name = Info(index)
    if not i then return end
    local kind, source, detail = Kinds.Of(i)
    local tip = GameTooltip
    tip:SetOwner(button, "ANCHOR_RIGHT")
    Core.TipTitle(tip, name)                    -- Rollen statt Farbzahlen (Gesamtreview 18.11.2026, T9-6)
    Core.TipLine(tip, L.KIND_LINE:format(Kinds.Label(kind), Kinds.SourceText(source, detail)), "blue", true)
    Core.TipLine(tip, L.KIND_RIGHTCLICK, "hint", true)
    tip:Show()
end

local function HookButton(button)
    if type(button) ~= "table" or ui.buttons[button] then return end
    ui.buttons[button] = true
    if type(button.HookScript) ~= "function" then return end
    button:HookScript("OnEnter", ShowTooltip)
    button:HookScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)
    button:HookScript("OnMouseUp", function(self, mouseButton)
        if mouseButton ~= "RightButton" or not Kinds.Enabled() then return end
        local index = ActualIndex(SelectionOf(self))
        if not (index and Info(index)) then return end
        Core.Menu.Open(self, function(root) AddAssign(root, index) end)
    end)
end
Kinds.HookButton = HookButton

local function CreateKindButton(frame)
    local button = CreateFrame("Button", "ezMacroKindButton", frame, "UIPanelButtonTemplate")
    button:SetSize(104, 18)
    -- Ebene: Kind des Makrofensters ohne eigene Ebene (Design-System 2.6, Rolle „parent“; bisher HIGH). Damit kein
    -- Teil von Blizzards Fenster den Knopf verdeckt, liegt er eine Rahmenstufe über „Speichern“, neben dem er sitzt.
    Core.Style.SetStrata(button, "parent")
    local save = rawget(_G, "MacroSaveButton")
    if type(save) == "table" then
        button:SetPoint("BOTTOMRIGHT", save, "TOPLEFT", -6, 1)
        local okLevel, level = pcall(save.GetFrameLevel, save)
        if okLevel and not ns.IsSecret(level) and type(level) == "number" then button:SetFrameLevel(level + 1) end
    else
        button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -96, -207)
    end
    button:SetScript("OnClick", function(self)
        if ns.UI then ns.UI.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON") end
        Core.Menu.Open(self, Kinds.BuildMenu)
    end)
    button:SetScript("OnEnter", function(self)
        Core.ShowTip(self, L.KIND_BUTTON_TITLE,
            L.KIND_BUTTON_TIP:format(Core.SettingsPathText(ns.moduleName or "ezMacro", "OPT_HEADER_MACROS", "OPT_macroKinds", L)))
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.kindButton = button
    return button
end

function Kinds.Hook()
    local frame = Frame()
    if ui.hooked or type(frame) ~= "table" or type(hooksecurefunc) ~= "function" then return ui.hooked end
    local selector = Core.Peek(frame, "MacroSelector")
    ui.hooked = true
    CreateKindButton(frame)
    if selector and type(Core.Peek(selector, "RunSetup")) == "function" then
        hooksecurefunc(selector, "RunSetup", function(_, button, selectionIndex)
            HookButton(button)
            Paint(button, selectionIndex)
        end)
    end
    if type(Core.Peek(frame, "Update")) == "function" then
        hooksecurefunc(frame, "Update", function() Kinds.Refresh() end)
    end
    if type(frame.HookScript) == "function" then
        -- Beim Öffnen wieder alle zeigen (Empfehlung, Antwort offen: kein gemerkter Filter)
        frame:HookScript("OnShow", function() Kinds.SetFilter("all") end)
    end
    EachButton(HookButton)
    Kinds.Refresh()
    return true
end

ns.OnSettingChanged(function(key)
    if key == "macroKinds" then Kinds.Refresh() end
end)
ns.On("UPDATE_MACROS", function() Kinds.Refresh() end)
ns.On("SPELLS_CHANGED", function() Kinds.ResetNames() end)

ns.OnReady(function()
    ns.WhenAddOnLoaded("Blizzard_MacroUI", Kinds.Hook)
    Kinds.Hook()   -- Rückfall: Makroverwaltung schon da, ohne dass der Client sie als geladen meldet
end)
