local _, ns = ...
local Core = ezCore

-- Slash-Befehle: was alle Module gleich machen, steht nur hier.

-- "Befehl Rest" → befehl (klein), rest
function Core.ParseSlash(input)
    input = Core.Trim(input or "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    return (cmd or ""):lower(), rest or ""
end

-- Befehlswort zum Vergleichen (Gesamtreview 18.11.2026, T18-16): klein, Umlaute als ae/oe/ue/ss – „vermächtnis“ und
-- „vermaechtnis“ sind dasselbe Wort, auch „Übersicht“ mit großem Umlaut. Core.ParseSlash bleibt unverändert (Module
-- vergleichen dort teils noch mit dem Umlaut); Core.HandleToggle und die Standardbefehle des Gerüsts vergleichen über
-- diesen Helfer, Module nehmen ihn für eigene Wörter. → Wort (Text, nie nil)
local FOLD = { { "ä", "ae" }, { "ö", "oe" }, { "ü", "ue" }, { "ß", "ss" }, { "Ä", "ae" }, { "Ö", "oe" }, { "Ü", "ue" } }
function Core.SlashWord(word)
    if Core.IsSecret(word) or type(word) ~= "string" then return "" end
    word = word:lower()
    for _, pair in ipairs(FOLD) do word = word:gsub(pair[1], pair[2]) end
    return word
end

function Core.PrintHelp(mns, lines)
    for _, line in ipairs(lines or mns.L.CMD_HELP) do mns.Print(line) end
end

-- Wörter eines Eintrags aus mns.TOGGLES: { Schlüssel, deutsches Wort, …, en = "englisches Wort" | { … } }. Der dritte
-- und vierte Listenplatz gehören den Modulen (ezBag, ezChat: Abschnitt der Einstellungsseite) – das englische Wort
-- steht deshalb im Feld en (T10-1: „/ezg durability“ im englischen Client).
local function ToggleMatches(entry, want)
    if type(entry) ~= "table" or type(entry[1]) ~= "string" then return false end
    if Core.SlashWord(entry[1]) == want or Core.SlashWord(entry[2]) == want then return true end
    local en = entry.en
    if type(en) == "string" then return Core.SlashWord(en) == want end
    for _, word in ipairs(type(en) == "table" and en or {}) do
        if Core.SlashWord(word) == want then return true end
    end
    return false
end

-- Schalter aus mns.TOGGLES umschalten. true, wenn cmd einer war. Verglichen wird über Core.SlashWord (Umlaute, groß
-- und klein); dazu der Schlüssel selbst und das englische Wort aus entry.en.
function Core.HandleToggle(mns, cmd)
    local want = Core.SlashWord(cmd)
    if want == "" then return false end
    for _, entry in ipairs(mns.TOGGLES or {}) do
        if ToggleMatches(entry, want) then
            local key = entry[1]
            -- gemeinsamer Schalter von ezCore (entry.shared = { gruppe, key }; Einstellungs-Prüfung 19.11.2026): der
            -- Befehl des Moduls schaltet denselben Wert wie das Kästchen auf beiden Seiten
            local shared = type(entry.shared) == "table" and entry.shared
                or (type(mns.SHARED) == "table" and mns.SHARED[key]) or nil
            if shared then
                local on = Core.SetShared(shared[1], shared[2], not Core.SharedOn(shared[1], shared[2]))
                mns.Print((on and mns.L.CMD_ON or mns.L.CMD_OFF):format(mns.L["OPT_" .. key]))
                return true
            end
            mns.SetSetting(key, not mns.S[key])
            mns.Print((mns.S[key] and mns.L.CMD_ON or mns.L.CMD_OFF):format(mns.L["OPT_" .. key]))
            return true
        end
    end
    return false
end

-- Bekannte Charaktere auflisten (aktueller zuerst). Überschrift aus ezCore (T16-3: eine Handlung, ein Wortlaut – die
-- Daten liegen nur einmal in ezCore, gleich über welches Modul der Befehl kam).
function Core.PrintChars(mns)
    mns.Print(Core.L.CMD_CHARS)
    for _, entry in ipairs(Core.CharacterList()) do mns.Print("  " .. entry.key) end
end

-- Charakter vergessen: gilt für alle Module, denn die Daten liegen nur einmal in ezCore. Nur „nicht gefunden“ kommt aus
-- dem Modul (sein Text nennt den Befehl des Moduls, z. B. „/eb chars zeigt alle“).
function Core.ForgetCommand(mns, rest)
    local L = mns.L
    local key, candidates = Core.FindCharKey(rest)
    if not key then
        if candidates then return mns.Print(Core.L.CMD_AMBIGUOUS:format(rest or "", table.concat(candidates, ", "))) end
        return mns.Print(L.CMD_NOT_FOUND:format(rest or ""))
    end
    return Core.AskForgetChar(key, mns)
end

-- Rückfrage und Vergessen für einen Schlüssel – EIN Weg für den Befehl und für den Knopf „Vergessen“ auf der Seite
-- „ezCollection → Charaktere“ (V-004). → true, wenn die Rückfrage gezeigt wurde; false und Grund ("self", "unknown").
-- „vergessen“ und „nicht den gespielten Charakter“ sagt immer ezCore (T16-3: vorher „gelöscht“ in ezBag und ezPanel).
function Core.AskForgetChar(key, mns)
    mns = type(mns) == "table" and mns or ns
    local L = mns.L or Core.L
    if key == Core.charKey then
        mns.Print(Core.L.CMD_SELF)
        return false, "self"
    end
    if type(key) ~= "string" or Core.Chars()[key] == nil then
        mns.Print(L.CMD_NOT_FOUND:format(tostring(key or "")))
        return false, "unknown"
    end
    -- Endgültig (Taschen, Bank, Post, Berufe, Rezepte): erst nach „Ja“, die Frage nennt den vollen Schlüssel.
    Core.Confirm(Core.L.CMD_FORGET_ASK:format(key), function()
        if Core.ForgetChar(key) then mns.Print(Core.L.CMD_FORGOT:format(key)) end
    end, { alert = true })
    return true
end

-- Ist ein Befehl schon belegt? Chat-Typen wie /e gehen vor Slash-Befehlen, Emotes auch.
-- ownKey: eigener SlashCmdList-Schlüssel (wird übersprungen). Vorher ezMacro.
function Core.SlashTaken(command, ownKey)
    local wanted = command:upper()
    local function Scan(prefix)
        for i = 1, 20 do
            local value = _G["SLASH_" .. prefix .. i]
            if value == nil then return false end
            if type(value) == "string" and value:upper() == wanted then return true end
        end
        return false
    end
    -- Blizzard verschiebt bereits eingelesene Einträge in eine Proxy-Tabelle (Metatable-__index),
    -- deshalb beide Ebenen durchsuchen.
    local function ScanList(list)
        if type(list) ~= "table" then return false end
        for key in pairs(list) do
            if key ~= ownKey and type(key) == "string" and Scan(key) then return true end
        end
        local meta = getmetatable(list)
        local proxy = type(meta) == "table" and meta.__index
        if type(proxy) == "table" then
            for key in pairs(proxy) do
                if key ~= ownKey and type(key) == "string" and Scan(key) then return true end
            end
        end
        return false
    end
    if ScanList(ChatTypeInfo) or ScanList(SlashCmdList) then return true end
    for _, list in ipairs({ _G.hash_ChatTypeInfoList, _G.hash_SlashCmdList, _G.hash_EmoteTokenList }) do
        if type(list) == "table" and list[wanted] ~= nil then return true end
    end
    for i = 1, (MAXEMOTEINDEX or 1000) do
        if _G["EMOTE" .. i .. "_TOKEN"] then
            for j = 1, 10 do
                local cmd = _G["EMOTE" .. i .. "_CMD" .. j]
                if not cmd then break end
                if cmd:upper() == wanted then return true end
            end
        end
    end
    -- Auch eingetragene, aber noch nicht eingelesene SLASH_-Werte anderer Addons.
    for key, value in pairs(_G) do
        if type(key) == "string" and type(value) == "string" and value:upper() == wanted and key:match("^SLASH_")
            and not (ownKey and key:match("^SLASH_" .. ownKey .. "%d+$")) then
            return true
        end
    end
    return false
end

-- Kurzbefehl nachträglich setzen (erst beim Einloggen, wenn alle Addons geladen sind).
-- candidates: Liste von Befehlen, der erste freie gewinnt. Rückgabe: der gesetzte Befehl oder nil.
function Core.AddSlashAlias(key, index, candidates, handler)
    for _, command in ipairs(candidates) do
        if not Core.SlashTaken(command, key) then
            _G["SLASH_" .. key .. index] = command
            -- Neu eintragen, damit Blizzard die Befehlsliste beim nächsten Chat-Befehl neu einliest.
            SlashCmdList[key] = handler
            return command
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Ein Kurzbefehl-Schema für alle Module (Gesamtreview 18.11.2026, P13: T18-2, T18-14, T18-15, T18-20; Entscheidung 5
-- vom 18.11.2026: feste Kurzbefehle nur, wenn frei – Muster ezQuest ns.SlashCmd)
---------------------------------------------------------------------------

--[[
    Core.SLASH_ALIASES   EINE Liste der Kurzbefehle: Modul → Kandidaten (der erste freie gilt, Core.AddSlashAlias).
                         Das Gerüst nimmt sie, wenn ein Modul in opts.slash kein alias nennt; ein Test prüft, dass sich
                         keine zwei Module einen Kurzbefehl teilen und keiner ein Befehl des Clients ist (/em ist
                         Blizzards Emote – darum /ezmc für ezMacro, T18-14). /ezm gehört ezMail (Frage vom 13.11.2026,
                         nach Empfehlung beantwortet im Gesamtreview, T18-15), als Kurzbefehl mit Belegt-Prüfung.
    Core.SlashCmd(mns, rest) → der geltende Befehl des Moduls („/eb“, wenn der Kurzbefehl gesetzt ist, sonst „/ezbag“),
                         mit rest dahinter („/eb fenster“). Texte nennen so nie einen Befehl, der beim Spieler einem
                         anderen Addon gehört (T18-2). Das Gerüst setzt mns.SlashCmd(rest) als Abkürzung.
                         mns darf auch der Name eines Moduls sein („ezTalent“): Dann fragt ezCore das geladene Modul,
                         sonst gilt dessen fester Befehl („/eztalent“) – so nennt ein Modul den Befehl eines anderen,
                         ohne dessen ns zu kennen (Gegenprüfung D3; vorher las ezCombat Core.Module("ezTalent").ns).
    Core.HelpLines(mns, own) → Hilfe in einer Form für alle Module (T18-20): Kopfzeile und Standardbefehle aus ezCore
                         (L.MODULE_HELP, dazu „zuruecksetzen“, wenn das Modul es anbietet), danach die eigenen Zeilen
                         own (Standard: mns.L.CMD_HELP_OWN). In jeder Zeile steht %s für den geltenden Befehl.
    Core.RESET_COMMANDS  Wörter für „Einstellungen zurücksetzen“ mit Rückfrage – nur für Module mit opts.slash.reset
                         (ezPanel nutzt „reset“ heute für die Lage der Leiste).
    Core.SlashReset(mns, fn) → fragt nach (Core.Confirm wie der Knopf page:ResetButton) und setzt danach zurück: fn()
                         oder die Einstellungsseite des Moduls (page:ResetToDefaults), sonst ns.DEFAULTS.
]]
Core.SLASH_ALIASES = {
    ezAuction = { "/eza" },
    ezBag = { "/eb" },
    ezChat = { "/ezc" },
    ezCombat = { "/ezk" },
    ezGear = { "/ezg" },
    ezLoot = { "/ezl" },
    ezMacro = { "/ezmc" },
    ezMail = { "/ezm" },
    ezMerchant = { "/ezh", "/ezvendor" },
    ezPanel = { "/ep" },
    ezQuest = { "/ezq" },
    ezSocial = { "/ezs" },
    ezTalent = { "/ezt" },
}

Core.RESET_COMMANDS = { "zuruecksetzen", "reset" }
local resetWord = {}
for _, word in ipairs(Core.RESET_COMMANDS) do resetWord[word] = true end

-- true, wenn word „Einstellungen zurücksetzen“ heißt (über Core.SlashWord: auch „zurücksetzen“).
function Core.IsResetCommand(word)
    return resetWord[Core.SlashWord(word)] == true
end

function Core.SlashCmd(mns, rest)
    local cmd
    if type(mns) == "string" and not Core.IsSecret(mns) and mns ~= "" then
        local mod = Core.Module(mns)
        mns = (mod and type(mod.ns) == "table") and mod.ns or { moduleName = mns }
    end
    if type(mns) == "table" then
        cmd = mns.slashAlias or mns.slashCommand
        if type(cmd) ~= "string" or cmd == "" then
            local name = mns.moduleName
            cmd = type(name) == "string" and ("/" .. name:lower()) or nil
        end
    end
    if not cmd and mns ~= ns then return Core.SlashCmd(ns, rest) end   -- ohne Modul: ezCores eigener Befehl
    cmd = cmd or "/ezcollection"
    if type(rest) == "string" and not Core.IsSecret(rest) and rest ~= "" then return cmd .. " " .. rest end
    return cmd
end

-- Zeile mit %s für den geltenden Befehl; „%%“ wird ein Prozentzeichen, andere Platzhalter (%d …) bleiben stehen. Fehlt
-- %s, bleibt die Zeile, wie sie ist. Eine Regel für die Hilfe und Core.CmdText (vorher scheiterte eine Zeile mit %s und
-- %d still an string.format und behielt ihr „%s“).
local function FormatLine(line, cmd)
    if type(line) ~= "string" or Core.IsSecret(line) or not line:find("%", 1, true) then return line end
    return (line:gsub("%%(.?)", function(c)
        if c == "s" then return cmd end
        if c == "%" then return "%" end
    end))
end

--[[
    Core.CmdText(mns, text) → text mit dem geltenden Befehl des Moduls an jeder Stelle von „%s“ (T18-2; vorher je eine
      Kopie ns.CmdText in ezBag, ezMail und ezAuction). Erst beim Zeigen aufrufen – der Kurzbefehl steht erst nach dem
      Einloggen fest (Core.SlashCmd). Kein Text oder gesperrt: unverändert zurück. Core.NewModule legt mns.CmdText(text)
      als Abkürzung an. mns darf wie bei Core.SlashCmd der Name eines Moduls sein (Core.CmdText("ezTalent", text)).
]]
function Core.CmdText(mns, text)
    if type(text) ~= "string" or Core.IsSecret(text) then return text end
    return FormatLine(text, Core.SlashCmd(mns))
end

function Core.HelpLines(mns, own)
    local L = Core.L
    local cmd = Core.SlashCmd(mns)
    local lines = {}
    -- Mit opts.slash.main führt der Befehl ohne Wort die Hauptfunktion aus (Entscheidung 5): dann sagt die zweite Zeile
    -- das, und die Einstellungen stehen mit ihrem Wort darunter (Gegenprüfung D1)
    local main = type(mns) == "table" and mns.slashMain or nil
    for i, text in ipairs(L.MODULE_HELP) do
        if i == 2 and main then
            local what = type(main) == "string" and not Core.IsSecret(main) and main ~= "" and main or L.MODULE_HELP_MAIN_DEFAULT
            lines[#lines + 1] = L.MODULE_HELP_MAIN:format(cmd, what)
            lines[#lines + 1] = FormatLine(L.MODULE_HELP_SETTINGS, cmd)
        else
            lines[#lines + 1] = FormatLine(text, cmd)
        end
    end
    if type(mns) == "table" and mns.slashReset then lines[#lines + 1] = FormatLine(L.MODULE_HELP_RESET, cmd) end
    if own == nil and type(mns) == "table" and type(mns.L) == "table" then own = mns.L.CMD_HELP_OWN end
    if type(own) == "table" then
        for _, text in ipairs(own) do lines[#lines + 1] = FormatLine(text, cmd) end
    end
    return lines
end

function Core.SlashReset(mns, fn)
    mns = type(mns) == "table" and mns or ns
    local owner = mns.moduleName or Core.name
    local page = mns.settingsPage
    if type(fn) ~= "function" and type(page) == "table" and type(page.AskReset) == "function" then
        -- dieselbe Rückfrage und derselbe Nachlauf wie der Knopf (opts.ask, opts.onReset von page:ResetButton)
        return page:AskReset()
    end
    return Core.Confirm(Core.L.RESET_SETTINGS_ASK:format(owner), function()
        if type(fn) == "function" then
            fn()
        elseif type(mns.settingsPage) == "table" and type(mns.settingsPage.ResetToDefaults) == "function" then
            mns.settingsPage:ResetToDefaults()
        elseif type(mns.DEFAULTS) == "table" and type(mns.SetSetting) == "function" then
            for key, value in pairs(mns.DEFAULTS) do mns.SetSetting(key, value) end
            Core.ResetModuleShared(mns)   -- gemeinsame Schalter auf ezCores Standard (wie Page:ResetToDefaults)
        end
        if type(mns.Print) == "function" then mns.Print(Core.L.RESET_SETTINGS_DONE) end
    end)
end
