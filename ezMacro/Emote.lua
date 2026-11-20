local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Emotes mit Ziel. Blizzards Emotes nennen das Ziel von selbst („… dankt <Ziel>“) – außer dort, wo der Client dem
    Emote kein Ziel (mehr) gibt. WoW Forever nimmt bei SPIT kein Ziel mehr an (Spieltest 14.11.2026:
    PerformEmote("SPIT", "target") und mit dem Namen spucken beide auf den Boden). Für solche Emotes sendet ezMacro
    mit Ziel ein Text-Emote, das den Namen nennt („spuckt <Ziel> an.“, über ezCores Core.SendChat); ohne Ziel bleibt
    es bei Blizzards Emote. Auf Wunsch spielt ezMacro davor Blizzards Emote ohne Ziel (Einstellung „Spucken mit Ziel:
    Animation + Text“, OPT_spitAnimation, ab Werk aus – zwei Chatzeilen je Klick).

    „Angriff!“ (CHARGE) nennt das Ziel nie. Blizzard hat dafür ein eigenes Emote, ATTACKMYTARGET („fordert alle auf,
    <Ziel> anzugreifen“, mit Stimme): Mit einem angreifbaren Ziel führt ezMacro dieses aus, sonst CHARGE wie bisher
    (Emote.TARGET_EMOTE).

    Alle Wege laufen hier durch: Klick auf die Emote-Leiste, das Makro aus dem Reiter „Chat“ (Emotes) (im Makro steht
    „/ezmacro emote SPIT“ bzw. „/ezmacro emote CHARGE“ – ein Emote-Befehl kennt keine Bedingungen, die Wahl fällt
    beim Klick) und das automatische Hinterherspucken (AutoEmote.lua).

    ns.Emote.Perform(token[, name]) → true gesendet | false gesperrt oder fehlgeschlagen | nil ohne Blizzards Funktion
    ns.Emote.Preview(token[, name]) → der Satz, der jetzt hinausginge („spuckt Bob an.“), sonst nil
    ns.Emote.Resolve(token[, name]) → das Emote, das jetzt ausgeführt würde (CHARGE oder ATTACKMYTARGET)
    ns.Emote.Reason(token)          → warum dieses Emote anders hinausgeht (für Tooltips), sonst nil
    ns.Emote.Command(token)         → Makrozeile für {e:TOKEN}
    ns.Emote.Outdated(entry)        → Index, Token, alter Befehl: das Makro des Eintrags hat noch Blizzards Befehl
]]
local Emote = {}
ns.Emote = Emote

-- Emotes, denen der Client kein Ziel gibt: text = Satz mit Ziel (%s = Name), why = Grund für den Tooltip (Locale),
-- whyBoth = derselbe Grund im Modus „Animation + Text“.
Emote.TARGET_TEXT = {
    SPIT = { text = "EMOTE_SPIT_TARGET", why = "EMOTE_SPIT_WHY", whyBoth = "EMOTE_SPIT_WHY_BOTH" },
}

-- Emotes, für die Blizzard mit Ziel ein eigenes Emote hat, das das Ziel nennt: emote = dessen Token, why = Grund für
-- den Tooltip, attackable = nur mit angreifbarem Ziel (alle zum Angriff auf einen Freund zu rufen wäre falsch).
-- Empfehlung zu Frage 13 der Moduldatei umgesetzt, Antwort offen (docs/roadmap/ezMacro.md): kein allgemeiner
-- Schalter „Ziel im Emote nennen“. Weitere Emotes, die auf Forever das Ziel nicht nennen, kommen nach dem Spieltest
-- (Prüfpunkt 9) wie Spucken in TARGET_TEXT.
Emote.TARGET_EMOTE = {
    CHARGE = { emote = "ATTACKMYTARGET", why = "EMOTE_CHARGE_WHY", attackable = true },
}

-- Wie ein Emote aus TARGET_TEXT mit Ziel hinausgeht:
--   "text"  nur der Satz – eine Chatzeile, keine Animation (Vorgabe)
--   "both"  erst Blizzards Emote ohne Ziel (Animation und seine eigene Chatzeile), dann der Satz – zwei Chatzeilen
-- Vorgabe "text"; die Einstellung „Spucken mit Ziel: Animation + Text“ (spitAnimation) schaltet auf "both".
-- Empfehlung zu Frage 12 der Moduldatei umgesetzt, Antwort offen (docs/roadmap/ezMacro.md).
Emote.MODE = "text"

function Emote.Mode()
    if ns.S and ns.S.spitAnimation then return "both" end
    return Emote.MODE
end

local function Entry(token)
    return type(token) == "string" and Emote.TARGET_TEXT[token] or nil
end

-- Blizzards Befehle eines Emotes, klein geschrieben: { ["/spucken"] = true, … }, und ob der Client das Emote führt.
-- Die Schreibweisen liefert ezCore (Core.EmoteCommands, Welle 23 – vorher las ezMacro EMOTE<n>_TOKEN und
-- EMOTE<n>_CMD<m> hier selbst); leer heißt: der Client führt das Emote nicht.
local function ClientCommands(token)
    local commands = {}
    local list = type(Core.EmoteCommands) == "function" and Core.EmoteCommands(token) or {}
    for _, command in ipairs(list) do commands[command:lower()] = true end
    return commands, #list > 0
end

-- Eintrag aus TARGET_EMOTE – nur, wenn der Client das andere Emote führt (sonst bleibt alles wie bisher).
local function Swap(token)
    local swap = type(token) == "string" and Emote.TARGET_EMOTE[token] or nil
    if swap and select(2, ClientCommands(swap.emote)) then return swap end
    return nil
end

function Emote.Reason(token)
    local entry = Entry(token)
    if entry then return L[(Emote.Mode() == "both" and entry.whyBoth) or entry.why] end
    local swap = Swap(token)
    return swap and L[swap.why] or nil
end

-- Name des Ziels, wie er im Chat steht: Spieler wie beim Flüstern (ezCore: auf Forever Vor- und Nachname), sonst
-- der Name der Einheit. nil ohne Ziel oder bei geheimem Namen (dann bleibt es bei Blizzards Emote).
function Emote.TargetName()
    -- ezCore prüft Einheit und Antworten (Core.UnitPresent, Core.UnitIs: gesperrt → nil; V-184)
    if Core.UnitPresent("target") ~= true then return nil end
    local isPlayer = Core.UnitIs("target")
    if isPlayer == nil then return nil end
    if isPlayer then
        local full = Core.UnitFullName("target")
        return full and Core.ShortName(full) or nil
    end
    local ok, name = pcall(UnitName, "target")
    if not ok or Core.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Der Satz, der jetzt hinausginge: nur für Emotes aus TARGET_TEXT und nur mit Ziel (name bzw. das aktuelle Ziel).
-- Leitlinie 6: zuerst IsSecret – ein geheimer Name wird weder mit nil verglichen noch durch das Ziel ersetzt.
function Emote.Preview(token, name)
    local entry = Entry(token)
    if not entry then return nil end
    if Core.IsSecret(name) then return nil end
    if name == nil then name = Emote.TargetName() end
    if type(name) ~= "string" or name == "" then return nil end
    return L[entry.text]:format(name)
end

-- Das Emote, das jetzt ausgeführt würde: für Emotes aus TARGET_EMOTE mit (angreifbarem) Ziel das andere Emote,
-- sonst token selbst. Ein ausdrücklicher Name (automatische Emotes), ein geheimer Zielname oder eine gesperrte
-- Antwort des Clients lassen es bei Blizzards Emote, wie es ist (Leitlinie 6).
function Emote.Resolve(token, name)
    local swap = Swap(token)
    if not swap then return token end
    if Core.IsSecret(name) then return token end
    if name ~= nil or not Emote.TargetName() then return token end
    if swap.attackable and not (UnitCanAttack and Core.Bool(UnitCanAttack("player", "target"), false)) then return token end
    return swap.emote
end

-- Emote ausführen. name: ausdrückliches Ziel (automatische Emotes), sonst gilt das aktuelle Ziel.
function Emote.Perform(token, name)
    local line = Emote.Preview(token, name)
    if not line then return Core.PerformEmote(Emote.Resolve(token, name), name) end
    if Core.ChatLocked() then return false end
    if Emote.Mode() == "both" then Core.PerformEmote(token) end
    return Core.SendChat(line, "EMOTE")
end

-- Läuft dieses Emote im Makro über ezMacros Befehl? (Die Wahl „mit Ziel / ohne Ziel“ fällt beim Klick.)
local function Rerouted(token)
    return Entry(token) ~= nil or Swap(token) ~= nil
end

-- Makrozeile für {e:TOKEN}: Blizzards Emote-Befehl in der Sprache des Clients; für Emotes mit eigenem Satz oder
-- anderem Emote mit Ziel der Befehl von ezMacro, weil ein Emote-Befehl im Makro keine Bedingung „mit Ziel / ohne
-- Ziel“ kennt.
function Emote.Command(token)
    if Rerouted(token) then return "/ezmacro emote " .. token end
    return ns.EmoteCommand(token)
end

-- Hat der Spieler das Makro dieses Eintrags noch mit Blizzards Emote-Befehl – aus der Zeit, bevor der Eintrag über
-- „/ezmacro emote …“ lief (ein altes „Spucken“ mit /spucken geht auf WoW Forever auf den Boden)? → Index des Makros,
-- Token, alter Befehl | nil. ezMacro schreibt vorhandene Makros nie von selbst um: Der Reiter zeigt nur den Hinweis
-- „veraltet“, „Aktualisieren“ ersetzt das Makro nach der üblichen Rückfrage (Browser.lua, Import.lua).
-- Der Hinweis verspricht, dass „Aktualisieren“ den alten Befehl durch ezMacros Befehl ersetzt. Das stimmt nur, wenn
-- der Text, den der Knopf schriebe (ns.EntryBody – auch ein vom Spieler angepasster Eintrag), ezMacros Befehl
-- enthält und den alten nicht mehr. Hat der Spieler den Eintrag anders angepasst (alter Befehl behalten, Emote ganz
-- herausgenommen), gibt es nichts zu versprechen – dann kein Hinweis.
function Emote.Outdated(entry)
    if type(entry) ~= "table" or type(entry.body) ~= "string" or not entry.body:find("{e:", 1, true) then return nil end
    local index = ns.Import.Find(ns.EntryName(entry))
    if not index then return nil end
    local body = Core.Plain(ns.Import.RawBody(index))
    if type(body) ~= "string" then return nil end
    local written = ns.Import.CleanBody((ns.EntryBody(entry)))
    if ns.Import.CleanBody(body) == written then return nil end
    -- Zeilen des Textes, den „Aktualisieren“ schriebe: ganze Zeile und Befehl am Zeilenanfang, klein geschrieben
    local lines, commands = {}, {}
    for line in written:gmatch("[^\n]+") do
        lines[Core.Trim(line):lower()] = true
        local command = line:match("^%s*(/%S+)")
        if command then commands[command:lower()] = true end
    end
    for token in entry.body:gmatch("{e:([%u_]+)}") do
        if Rerouted(token) and lines[Emote.Command(token):lower()] then
            local old = ClientCommands(token)
            local fallback = ns.EmoteCommand(token)
            if type(fallback) == "string" then old[fallback:lower()] = true end
            local stays = false
            for command in pairs(old) do
                if commands[command] then stays = true break end
            end
            if not stays then
                for line in body:gmatch("[^\n]+") do
                    local command = line:match("^%s*(/%S+)")
                    if command and old[command:lower()] then return index, token, command end
                end
            end
        end
    end
    return nil
end

-- Hinweis für den Tooltip von „Aktualisieren“: was am Makro veraltet ist, was der Knopf tut und warum. → Text | nil
function Emote.OutdatedText(entry)
    local index, token, command = Emote.Outdated(entry)
    if not index then return nil end
    local why = Emote.Reason(token)
    return L.EMOTE_OUTDATED_TIP:format(command, Emote.Command(token)) .. (why and ("\n\n" .. why) or "")
end

-- Befehl „/ezmacro emote SPIT“ (so steht es im Makro). Rückgabe: true gesendet.
function Emote.Slash(rest)
    local token = Core.Trim(tostring(rest or "")):upper()
    if not token:find("^[%u_]+$") then
        ns.Print(L.EMOTE_USAGE)
        return false
    end
    local sent = Emote.Perform(token)
    if sent == false then Core.ErrorMessage(L.BAR_BLOCKED) end
    return sent == true
end
