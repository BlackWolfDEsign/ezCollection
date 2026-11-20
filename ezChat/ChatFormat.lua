local _, ns = ...
local L = ns.L

-- Blizzards Chatfenster verfeinern – nur über offizielle Wege:
-- * Nachrichtenfilter (ChatFrameUtil.AddMessageEventFilter): Internetadressen werden zu Links, der
--   eigene Name und Stichwörter farbig, Kanalnamen ohne Gebiet. Geheime Nachrichten (Kampf in Instanzen)
--   reicht Blizzard gar nicht erst an Filter weiter; ezChat prüft trotzdem selbst.
-- * Links vom Typ „addon“ leitet Forevers SetItemRef an EventRegistry „SetItemRef“ weiter
--   (Blizzard_UIPanels_Game/Shared/ItemRefHandlersShared.lua); ein Klick zeigt die Adresse zum Kopieren.
-- * Kopieren und Ausblenden: Blizzards ScrollingMessageFrameSecureMixin (SetTextCopyable, SetFading) ist
--   laut Blizzard für Addons gedacht und läuft wie ungetaintet. Pfeiltasten: SetAltArrowKeyMode am
--   Eingabefeld (Blizzards Vorlage hat ignoreArrows="true").
-- Was ezChat nicht eingeschaltet hat, fasst es nicht an (z. B. wenn Leatrix Plus dasselbe erledigt).

local Format = {}
ns.Format = Format

-- Farben aus Blizzards Farbobjekten (ns.ColorCode, Core.lua; Design-System 2.5): Web-Adressen in Blizzards Blau,
-- Stichwörter in Blizzards Orange (vorher eigene Töne 4fc3f7 und ff9933)
local LINK_COLOR = ns.ColorCode("link")
local MARK_COLOR = ns.ColorCode("orange")
local MAX_URLS = 300

---------------------------------------------------------------------------
-- Text zerlegen: Links, Farben und Symbole bleiben unangetastet
---------------------------------------------------------------------------

-- Teile, die nie verändert werden: Hyperlinks, Texturen, Atlas-Symbole, Battle.net-Namen, Farbcodes.
local KEEP = { "|H.-|h.-|h", "|T.-|t", "|A.-|a", "|K.-|k", "|c%x%x%x%x%x%x%x%x", "|r" }

-- Wendet fn auf alle reinen Textteile an und setzt den Text wieder zusammen.
local function EachPlain(text, fn)
    local out, pos = {}, 1
    while true do
        local s, e
        for _, pattern in ipairs(KEEP) do
            local ps, pe = text:find(pattern, pos)
            if ps and (not s or ps < s) then s, e = ps, pe end
        end
        if not s then break end
        out[#out + 1] = fn(text:sub(pos, s - 1))
        out[#out + 1] = text:sub(s, e)
        pos = e + 1
    end
    out[#out + 1] = fn(text:sub(pos))
    return table.concat(out)
end

-- Suchmuster ohne Rücksicht auf Groß- und Kleinschreibung (für lateinische Buchstaben).
local function LoosePattern(word)
    return (word:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%a", function(c)
        return "[" .. c:lower() .. c:upper() .. "]"
    end))
end

-- Gehört das Byte zu einem Wort? Buchstaben, Ziffern und alle Bytes von UTF-8-Zeichen (Umlaute).
local function WordByte(byte)
    return byte ~= nil and ((byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122) or byte >= 128)
end

-- Alle Vorkommen von pattern in einem reinen Textteil einfärben. whole: nur ganze Wörter.
local function MarkPart(part, pattern, color, whole)
    local out, pos, found = {}, 1, false
    while pos <= #part do
        local s, e = part:find(pattern, pos)
        if not s then break end
        if not whole or (not WordByte(part:byte(s - 1)) and not WordByte(part:byte(e + 1))) then
            out[#out + 1] = part:sub(pos, s - 1) .. color .. part:sub(s, e) .. "|r"
            found = true
        else
            out[#out + 1] = part:sub(pos, e)
        end
        pos = e + 1
    end
    out[#out + 1] = part:sub(pos)
    return table.concat(out), found
end

-- Suchbegriff im Text markieren (Suche im Gesprächsfenster); query klein geschrieben.
function Format.MarkQuery(text, query)
    if type(text) ~= "string" or type(query) ~= "string" or query == "" then return text end
    local pattern = LoosePattern(query)
    return EachPlain(text, function(part) return (MarkPart(part, pattern, MARK_COLOR, false)) end)
end

---------------------------------------------------------------------------
-- Internetadressen
---------------------------------------------------------------------------

local urls, nextUrl = {}, 0
local URL_PATTERNS = { "https?://[^%s|]+", "www%.[%w%-]+%.%a[^%s|]*" }
local TRAILING = "[%.,;:!%?%)%]\"']+$"

local function LinkFor(url)
    nextUrl = nextUrl % MAX_URLS + 1
    urls[nextUrl] = url
    return ("%s|Haddon:ezChat:url:%d|h[%s]|h|r"):format(LINK_COLOR, nextUrl, url)
end

local function LinkifyPart(part)
    if not part:find("http", 1, true) and not part:find("www.", 1, true) then return part end
    local out, pos = {}, 1
    while true do
        local s, e
        for _, pattern in ipairs(URL_PATTERNS) do
            local ps, pe = part:find(pattern, pos)
            if ps and (not s or ps < s) then s, e = ps, pe end
        end
        if not s then break end
        local url = part:sub(s, e)
        local tail = url:match(TRAILING) or ""
        url = url:sub(1, #url - #tail)
        out[#out + 1] = part:sub(pos, s - 1) .. LinkFor(url) .. tail
        pos = e + 1
    end
    out[#out + 1] = part:sub(pos)
    return table.concat(out)
end

-- Internetadressen im Text als anklickbare ezChat-Links.
function Format.Linkify(text)
    if type(text) ~= "string" or not ns.Usable(text) then return text end
    if not text:find("http", 1, true) and not text:find("www.", 1, true) then return text end
    return EachPlain(text, LinkifyPart)
end

-- Enthält der Text eine Internetadresse (dieselben Muster wie die Links)? Für den Spam-Filter (Spam.lua).
function Format.HasUrl(text)
    if type(text) ~= "string" or not ns.Usable(text) then return false end
    for _, pattern in ipairs(URL_PATTERNS) do
        if text:find(pattern) then return true end
    end
    return false
end

-- Adresse eines ezChat-Links (link = "addon:ezChat:url:12", text = der ganze Link). Der angezeigte Text
-- geht vor: Die Nummern wiederholen sich nach MAX_URLS Adressen, alte Chatzeilen zeigen dann sonst falsch.
function Format.UrlOf(link, text)
    if type(link) ~= "string" or not ns.Usable(link, text) then return nil end
    local index = tonumber(link:match("^addon:ezChat:url:(%d+)"))
    if not index then return nil end
    local shown = type(text) == "string" and text:match("|h%[(.-)%]|h")
    if shown and shown ~= "" then return shown end
    return urls[index]
end

-- Klick auf einen ezChat-Link: Adresse markiert zum Kopieren zeigen (Strg+C).
-- Rückgabe true, wenn es ein ezChat-Link war.
function Format.HandleLink(link, text)
    local url = Format.UrlOf(link, text)
    if not url then return false end
    ezCore.AskText(L.URL_COPY, url, function() end, 1000)
    return true
end

---------------------------------------------------------------------------
-- Eigenen Namen und Stichwörter hervorheben
---------------------------------------------------------------------------

local patterns   -- Liste der Suchmuster (nil = neu aufbauen)

local function Words()
    local list, seen = {}, {}
    local function Add(word)
        word = ns.Trim(word or "")
        if word ~= "" and not seen[word:lower()] then
            seen[word:lower()] = true
            list[#list + 1] = word
        end
    end
    -- Eigener Name: auf Forever der Vorname aus „Vorname Nachname“, sonst der Name ohne Realm.
    local self = ns.selfName
    if type(self) == "string" then
        local sep = ns.surnameSep or " "
        local cut = self:find(sep, 1, true) or self:find("-", 1, true)
        Add(cut and self:sub(1, cut - 1) or self)
    end
    for word in tostring(ns.S.keywords or ""):gmatch("[^,;]+") do Add(word) end
    return list
end

local function Patterns()
    if patterns then return patterns end
    patterns = {}
    for _, word in ipairs(Words()) do patterns[#patterns + 1] = LoosePattern(word) end
    return patterns
end

function Format.ResetWords() patterns = nil end

-- Kommt der eigene Name oder ein Stichwort im Text vor?
function Format.Matches(text)
    if type(text) ~= "string" or not ns.Usable(text) then return false end
    local found = false
    EachPlain(text, function(part)
        for _, pattern in ipairs(Patterns()) do
            if not found then
                local _, hit = MarkPart(part, pattern, "", true)
                found = found or hit
            end
        end
        return part
    end)
    return found
end

-- Eigenen Namen und Stichwörter farbig hervorheben.
function Format.Highlight(text)
    if type(text) ~= "string" or not ns.Usable(text) or #Patterns() == 0 then return text end
    return EachPlain(text, function(part)
        for _, pattern in ipairs(Patterns()) do part = (MarkPart(part, pattern, MARK_COLOR, true)) end
        return part
    end)
end

-- Stichwörter bearbeiten (Knopf auf der Einstellungsseite, /ezchat stichwoerter).
function Format.EditKeywords()
    ns.AskText(L.KEYWORDS_PROMPT, ns.S.keywords or "", function(text)
        ns.SetSetting("keywords", text or "")
        ns.Print(text ~= "" and L.KEYWORDS_SET:format(text) or L.KEYWORDS_NONE)
    end)
end

---------------------------------------------------------------------------
-- Kanalnamen kürzen
---------------------------------------------------------------------------

-- "2. Handel - Stadt" → "2. Handel". Die Nummer davor bleibt (Blizzard braucht sie), Community-Kanäle
-- bleiben unverändert. Der Name selbst bleibt ganz, damit Blizzard die Zeile weiter dem Kanal zuordnet.
function Format.ShortChannel(channel)
    if type(channel) ~= "string" or not ns.Usable(channel) or channel:find("Community:", 1, true) then return channel end
    local prefix, name = channel:match("^(%d+%. )(.-) %- .+$")
    if prefix and name and name ~= "" then return prefix .. name end
    return channel
end

-- Schlüssel für Kanal-Alarme: seit 1.6.0 ezCore.ChannelKey (klein, ohne Nummer, Gebiet und Leerzeichen,
-- „2. Suche nach Gruppe“ → „suchenachgruppe“), derselbe wie in ezSocial. Bleibt als Weiterleitung erhalten.
function Format.ChannelKey(name)
    return ezCore.ChannelKey(name)
end

---------------------------------------------------------------------------
-- Nachrichtenfilter
---------------------------------------------------------------------------

local TEXT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
}

-- Flüstern ist ohnehin an dich gerichtet (und hat Blizzards Ton): dort nichts hervorheben.
local NO_HIGHLIGHT = {
    CHAT_MSG_WHISPER = true, CHAT_MSG_WHISPER_INFORM = true,
    CHAT_MSG_BN_WHISPER = true, CHAT_MSG_BN_WHISPER_INFORM = true,
}

local function FromSelf(sender)
    if type(sender) ~= "string" or sender == "" then return false end
    local full = ns.FullName(sender)
    return full ~= nil and ns.IsSelf(full)
end
Format.FromSelf = FromSelf

function Format.Filter(_, event, msg, sender, language, channel, ...)
    if not ns.S or type(msg) ~= "string" or not ns.Usable(msg, sender, channel) then return false end
    local newMsg, newChannel = msg, channel
    if ns.Active("links") then newMsg = Format.Linkify(newMsg) end
    if ns.Active("highlight") and not NO_HIGHLIGHT[event] and not FromSelf(sender) then newMsg = Format.Highlight(newMsg) end
    if ns.Active("shortChannels") and event == "CHAT_MSG_CHANNEL" then newChannel = Format.ShortChannel(channel) end
    if newMsg == msg and newChannel == channel then return false end
    return false, newMsg, sender, language, newChannel, ...
end

---------------------------------------------------------------------------
-- Chatfenster: kopieren, nicht ausblenden, Pfeiltasten
---------------------------------------------------------------------------

local touched = { copy = false, fade = false, arrows = false }   -- hat ezChat das schon einmal eingeschaltet?

local function EachChatFrame(fn)
    local seen, names = {}, {}
    for i, name in ipairs(CHAT_FRAMES or {}) do names[i] = name end   -- Blizzards Liste nur lesen
    if #names == 0 then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do names[i] = "ChatFrame" .. i end
    end
    for _, name in ipairs(names) do
        local frame = _G[name]
        -- ChatFrame2 ist das Kampflog: bleibt, wie Blizzard es eingerichtet hat.
        if frame and name ~= "ChatFrame2" and not seen[frame] then
            seen[frame] = true
            fn(frame, name)
        end
    end
end

local function OnCopied(_, _, count)
    if type(count) == "number" and count > 0 then ns.Print(L.COPIED:format(count)) end
end

-- Schalter auf alle Chatfenster anwenden. Was ezChat nie eingeschaltet hat, bleibt unberührt.
function Format.ApplyFrames()
    if not ns.S then return end
    -- Übernimmt ein fremdes Addon Kopieren, Verblassen oder Pfeiltasten (ns.HANDLED_BY), fasst ezChat das
    -- gar nicht an, auch nicht zum Zurückstellen.
    local copyFree, fadeFree, arrowsFree = not ns.Other("copyChat"), not ns.Other("noFade"), not ns.Other("arrowKeys")
    local copy, fade, arrows = ns.Active("copyChat"), ns.Active("noFade"), ns.Active("arrowKeys")
    touched.copy = touched.copy or copy
    touched.fade = touched.fade or fade
    touched.arrows = touched.arrows or arrows
    EachChatFrame(function(frame, name)
        if touched.copy and copyFree and frame.SetTextCopyable then
            pcall(frame.SetTextCopyable, frame, copy and true or false)
            if copy and frame.SetOnTextCopiedCallback and frame.GetOnTextCopiedCallback
                and frame:GetOnTextCopiedCallback() == nil then
                pcall(frame.SetOnTextCopiedCallback, frame, OnCopied)
            end
        end
        if touched.fade and fadeFree and frame.SetFading then pcall(frame.SetFading, frame, not fade) end
        local edit = frame.editBox or _G[name .. "EditBox"]
        if touched.arrows and arrowsFree and edit and edit.SetAltArrowKeyMode then
            pcall(edit.SetAltArrowKeyMode, edit, not arrows)
        end
    end)
end

local function SafeApply()
    local ok, err = pcall(Format.ApplyFrames)
    if not ok then ns.Error(err) end
end

ns.OnReady(function()
    for _, event in ipairs(TEXT_EVENTS) do ns.AddMessageEventFilter(event, Format.Filter) end
    -- Blizzards Links vom Typ „addon“ (nur lokal erzeugte) kommen hier an.
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("SetItemRef", function(_, link, text)
            local ok, err = pcall(Format.HandleLink, link, text)
            if not ok then ns.Error(err) end
        end, Format)
    end
    -- Neue Chatfenster (Flüster-Reiter, „Neues Fenster“) bekommen dieselben Schalter.
    for _, fn in ipairs({ "FCF_OpenTemporaryWindow", "FCF_OpenNewWindow" }) do
        if type(_G[fn]) == "function" then hooksecurefunc(fn, SafeApply) end
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(1, SafeApply) end)
ns.On("UPDATE_CHAT_WINDOWS", SafeApply)

ns.OnSettingChanged(function(key)
    if key == "copyChat" or key == "noFade" or key == "arrowKeys" then SafeApply() end
    if key == "keywords" then Format.ResetWords() end
end)
