local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Ansagen für Anführer, Stufe 1 (Wunsch des Nutzers, 13.11.2026): fertige Sätze für Dungeon, Raid und PvP als
    gewöhnliche Makros im Reiter „Chat“ (Ansagen) (Data\Announce.lua). Nichts wird automatisch ausgelöst – der Spieler
    schickt jede Ansage selbst per Klick oder Taste ab.

    Der Kanal wählt sich selbst (Einstellung „Kanal der Ansagen“, announceMode):
      "auto"   Im Makro steht „/ezmacro ansage warn Text“. Beim Klick sucht ezMacro den Kanal aus: Raidwarnung als
               Leiter oder Assistent im Raid, sonst Raid, Schlachtfeld/Instanzgruppe bzw. Gruppe (Core.GroupChannel)
               und sendet über Core.SendChat. Ein Makro passt so für jede Gruppe.
      "fixed"  Im Makro steht Blizzards eigener Befehl (/rw, /raid, /i, /p) für die Gruppe, in der man beim
               Übernehmen ist. Das läuft ohne Addon-Senden – für den Fall, dass der Client Addons das Senden im
               Kampf oder in Instanzen verwehrt (im Spiel zu prüfen).
    Platzhalter: %t = Name des Ziels (wie in Blizzards Chat), %z = das Gebiet, in dem man steht (nur „auto“; bei
    festen Kanälen steht dort „meine Position“), %r = Zielsymbol des Ziels als „{rt1}“ … „{rt8}“ (nur „auto“, sonst
    fällt es weg), %n = Name aus dem Rechtsklick-Menü (Stufe 2, AnnounceMenu.lua).
    Pull-Timer: Läuft ein Addon mit Pull-Timer (ezCore: Core.WhoHandles("pullTimer")), wird aus der Pull-Ansage
    dessen Befehl „/pull n“ statt eines eigenen Texts (Leitlinie 9) – nichts wird nachgebaut.

    ns.Announce.Send(kind, text) → true, chatType | false, "empty" | "alone" | "locked" | "failed"
    ns.Announce.Channel(kind)    → "RAID_WARNING" | "RAID" | "INSTANCE_CHAT" | "PARTY" | nil (allein)
    ns.Announce.Command(kind)    → Anfang der Makrozeile je nach Einstellung
    ns.Announce.SendEntry(entry) → wie Send, für einen Eintrag des Reiters (Knopf „Jetzt ansagen“): die angepasste
                                   Fassung, sonst der mitgelieferte Satz; false, "none" ohne Ansage-Zeile
]]
local Announce = {}
ns.Announce = Announce

-- Arten: "warn" (wichtig: Raidwarnung, wenn man darf) und "group" (gewöhnlicher Gruppenkanal)
local KIND_WORDS = {
    warn = "warn", warnung = "warn", warning = "warn", rw = "warn",
    group = "group", gruppe = "group", g = "group",
}

-- Blizzards Befehle je Kanal (englische Formen gelten in jeder Sprache)
local COMMANDS = { RAID_WARNING = "/rw", RAID = "/raid", INSTANCE_CHAT = "/i", PARTY = "/p" }

-- Blizzards Befehl für einen Kanal („/rw“, „/raid“, „/i“, „/p“) oder nil – für die Zeile in der Chat-Eingabe
-- (AnnounceMenu.lua): Blizzards Eingabe wechselt damit selbst in den Kanal.
function Announce.CommandFor(channel)
    return COMMANDS[channel]
end

function Announce.Kind(word)
    if type(word) ~= "string" then return nil end
    return KIND_WORDS[word:lower()]
end

-- „auto“: Kanal beim Klick wählen (Standard); sonst feste Blizzard-Befehle im Makro.
function Announce.Auto()
    return not (ns.S and ns.S.announceMode == "fixed")
end

-- Darf der Spieler eine Raidwarnung senden? Im Raid nur Leiter und Assistenten.
function Announce.CanWarn()
    if not (IsInRaid and IsInRaid()) then return false end
    local leader = UnitIsGroupLeader and UnitIsGroupLeader("player")
    local assist = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
    if Core.IsSecret(leader) or Core.IsSecret(assist) then return false end
    return (leader or assist) and true or false
end

-- Kanal für eine Ansage dieser Art; nil, wenn man in keiner Gruppe ist.
function Announce.Channel(kind)
    local base = Core.GroupChannel()
    if not base then return nil end
    if kind == "warn" and Announce.CanWarn() then return "RAID_WARNING" end
    return base
end

-- Name des Kanals für Anzeige und Status („Raidwarnung“, „Gruppe“ …).
function Announce.ChannelLabel(channel)
    return L["ANN_CH_" .. tostring(channel or "NONE")]
end

-- Wort des Befehls in der Sprache des Clients („/ezmacro ansage …“ bzw. „/ezmacro announce …“).
local function CommandWord() return ns.isGerman and "ansage" or "announce" end
local function KindWord(kind)
    if kind == "warn" then return "warn" end
    return ns.isGerman and "gruppe" or "group"
end

-- Anfang der Makrozeile: „/ezmacro ansage warn“ (auto) bzw. Blizzards Befehl für die jetzige Gruppe (fest).
function Announce.Command(kind)
    kind = Announce.Kind(kind) or "group"
    if Announce.Auto() then
        return "/ezmacro " .. CommandWord() .. " " .. KindWord(kind)
    end
    return COMMANDS[Announce.Channel(kind) or "PARTY"]
end

-- Zeile für eine Pull-Ansage: der Pull-Timer eines laufenden Addons („/pull 5“), sonst die eigene Ansage.
function Announce.PullLine(seconds, text)
    seconds = tonumber(seconds) or 5
    if ns.OtherFor("pullTimer") then return "/pull " .. seconds end     -- Gerüst: Core.WhoHandles
    return Announce.Command("warn") .. " " .. tostring(text or "")
end

-- Gebiet, in dem der Spieler steht (Untergebiet vor Gebiet); nil, wenn der Client nichts Lesbares nennt.
function Announce.Place()
    for _, name in ipairs({ "GetSubZoneText", "GetMinimapZoneText", "GetZoneText" }) do
        local fn = rawget(_G, name)
        if type(fn) == "function" then
            local ok, text = pcall(fn)
            if ok and not Core.IsSecret(text) and type(text) == "string" and text ~= "" then return text end
        end
    end
    return nil
end

-- Name einer Einheit, wenn sie da ist und der Client ihn frei nennt; sonst nil (gesperrt: nil, "secret").
function Announce.UnitName(unit)
    if type(unit) ~= "string" or Core.UnitPresent(unit) ~= true then return nil end   -- ezCore prüft die Antwort (V-184)
    local name = UnitName and UnitName(unit)
    if Core.IsSecret(name) then return nil, "secret" end
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Zielsymbol einer Einheit als Blizzards Chat-Zeichen „{rt1}“ … „{rt8}“ (Stern … Totenschädel; der Chat zeigt es
-- in jeder Sprache als Symbol). nil ohne Symbol, ohne Einheit oder bei gesperrter Antwort.
function Announce.Mark(unit)
    if type(unit) ~= "string" or Core.UnitPresent(unit) ~= true then return nil end
    local index = Core.Plain(Core.Call(rawget(_G, "GetRaidTargetIndex"), unit))
    index = tonumber(index)
    if index and index >= 1 and index <= 8 and index == math.floor(index) then return "{rt" .. index .. "}" end
    return nil
end

-- Platzhalter einsetzen: %z = Gebiet, %t = Name des Ziels, %r = Zielsymbol des Ziels (MACRO-26; ohne Symbol
-- nichts), %n = Name der Einheit aus dem Rechtsklick-Menü. ctx (optional, AnnounceMenu.lua): ctx.target = Einheit
-- für %t und %r (Standard "target"), ctx.name = Name für %n. Ein geheimer Zielname bleibt als %t stehen (den setzt
-- dann Blizzards Chat selbst ein). Doppelte Leerzeichen eines leeren Platzhalters fallen weg.
function Announce.Expand(text, ctx)
    text = tostring(text or "")
    local unit = type(ctx) == "table" and ctx.target or "target"
    if text:find("%z", 1, true) then
        local place = Announce.Place() or L.ANN_HERE
        text = text:gsub("%%z", function() return place end)
    end
    if type(ctx) == "table" and text:find("%n", 1, true) then   -- nur aus dem Menü; ein eigener Text behält %n
        local who = ctx.name
        if Core.IsSecret(who) or type(who) ~= "string" or who == "" then who = L.ANN_NO_TARGET end
        text = text:gsub("%%n", function() return who end)
    end
    if text:find("%r", 1, true) then
        local mark = Announce.Mark(unit) or ""
        text = text:gsub("%%r", function() return mark end)
    end
    if text:find("%t", 1, true) then
        local name, why = Announce.UnitName(unit)
        if why ~= "secret" then text = text:gsub("%%t", function() return name or L.ANN_NO_TARGET end) end
    end
    return Core.Trim((text:gsub("  +", " ")))
end

-- Text für ein Makro mit festem Kanal: %z kann Blizzards Chat nicht einsetzen, dort steht „meine Position“; das
-- Zielsymbol %r kennt nur ezMacro beim Klick – im festen Makro fällt es weg.
function Announce.FixedText(text)
    text = tostring(text or ""):gsub("%%z", function() return L.ANN_HERE end)
    return (text:gsub("%%r ?", ""))
end

local lastSent

-- Ansage jetzt senden (Befehl „/ezmacro ansage“, Knopf „Jetzt ansagen“, Schnittstelle für andere Module).
function Announce.Send(kind, text)
    kind = Announce.Kind(kind) or "group"
    text = Core.Trim(tostring(text or ""))
    if text == "" then
        ns.Print(L.ANN_USAGE)
        return false, "empty"
    end
    local message = Announce.Expand(text)
    local channel = Announce.Channel(kind)
    if not channel then
        ns.Print(L.ANN_ALONE:format(message))
        return false, "alone"
    end
    if Core.ChatLocked() then
        ns.Print(L.ANN_LOCKED)
        return false, "locked"
    end
    if not Core.SendChat(message, channel) then
        ns.Print(L.ANN_FAILED)
        return false, "failed"
    end
    lastSent = { text = message, channel = channel }
    return true, channel
end

function Announce.Last() return lastSent end

-- Rest hinter „/ezmacro ansage“: „[warn|gruppe] Text“ → Art, Text; ohne Art gilt der gewöhnliche Gruppenkanal.
local function SplitArgs(rest)
    rest = tostring(rest or "")
    local word, text = rest:match("^(%S+)%s*(.-)$")
    local kind = Announce.Kind(word)
    if not kind then kind, text = "group", rest end
    return kind, text
end

-- Befehl „/ezmacro ansage [warn|gruppe] Text“: ohne Art gilt der gewöhnliche Gruppenkanal.
function Announce.Slash(rest)
    return Announce.Send(SplitArgs(rest))
end

-- Blizzards Gruppenbefehle, die eine Ansage mit festem Kanal tragen (wie COMMANDS, dazu die langen Formen).
local FIXED_KINDS = {
    rw = "warn", raidwarning = "warn",
    raid = "group", ra = "group", i = "group", instance = "group", p = "group", party = "group",
}
local SLASH_WORDS = { ansage = true, announce = true }

-- Erste Ansage-Zeile eines Makrotexts → Art, Text: „/ezmacro ansage [warn|gruppe] Text“ (Kanal beim Klick) oder
-- ein fester Blizzard-Befehl („/rw Text“, „/p Text“). Andere Zeilen (#showtooltip, /cast, /pull …) zählen nicht.
function Announce.LineOf(body)
    for line in (tostring(body or "") .. "\n"):gmatch("([^\n]*)\n") do
        local command, rest = Core.Trim(line):match("^/(%S+)%s*(.-)$")
        command = command and command:lower()
        if command == "ezmacro" then
            local word, args = rest:match("^(%S+)%s*(.-)$")
            if word and SLASH_WORDS[word:lower()] then return SplitArgs(args) end
        elseif command and FIXED_KINDS[command] and rest ~= "" then
            return FIXED_KINDS[command], rest
        end
    end
    return nil
end

-- Was „Jetzt ansagen“ für einen Eintrag schickt: Art, Text. Hat der Spieler den Makrotext angepasst, gilt seine
-- Fassung (Fund der Prüfung: vorher ging immer der mitgelieferte Satz hinaus); ist der Text unverändert (nur der
-- Name angepasst), bleibt es beim mitgelieferten Satz samt %z. nil: Die Fassung enthält keine Ansage-Zeile.
function Announce.EntryLine(entry)
    if type(entry) ~= "table" or type(entry.say) ~= "table" then return nil end
    local edit = ns.db and ns.db.edits and ns.db.edits[entry.id]
    if type(edit) == "table" and type(edit.body) == "string" and edit.body ~= (ns.Resolve(entry.body)) then
        return Announce.LineOf(edit.body)
    end
    return Announce.Kind(entry.say.kind) or "group", ns.Text(entry.say.text)
end

-- Knopf „Jetzt ansagen“: die Fassung des Eintrags sofort senden.
function Announce.SendEntry(entry)
    local kind, text = Announce.EntryLine(entry)
    if not kind then
        ns.Print(L.ANN_SAY_NONE)
        return false, "none"
    end
    return Announce.Send(kind, text)
end

-- Vorgewählte Gruppe im Reiter „Chat“ (Ansagen): wo man gerade ist.
function Announce.DefaultGroup()
    local inInstance, kind = Core.InInstance()      -- ezCore: gesperrt oder unbekannt → nil (W-14)
    if inInstance == true and (kind == "pvp" or kind == "arena") then return "pvp" end
    if IsInRaid and IsInRaid() then return "raid" end
    return "dungeon"
end

-- Zeile über der Liste und im Status: welcher Kanal gerade gilt.
function Announce.InfoText()
    local channel = Announce.Channel("warn")
    local label = Announce.ChannelLabel(channel)
    return (Announce.Auto() and L.ANN_INFO or L.ANN_INFO_FIXED):format(label)
end

ns.AddStatusLine(function() return L.ANN_STATUS:format(Announce.InfoText()) end)
