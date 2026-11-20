local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezChat (Seite von ezCore).
-- Aufbau wie jede Seite: „Allgemein“ → Themen → „Erweitert“.
local page

local function OpenBlizzardSocial()
    -- Zeitstempel und Chat-Stil gehören zu Blizzards eigenen Optionen (Soziales). Geöffnet wird über ezCore
    -- (Core.OpenPanel): im Kampf nicht, dann kommt ezCores Hinweis; kennt der Client den Weg nicht, der Text.
    local ok, why = ezCore.OpenPanel("settings", "social")
    if not ok and why ~= "combat" then ns.Print(L.TIMESTAMPS_WHERE) end
    return ok, why
end

ns.OpenBlizzardSocial = OpenBlizzardSocial

-- Blizzards eigene Einstellung „Neue Flüsternachrichten“ (CVar whisperMode, Optionen → Soziales; in Blizzards
-- Forever-Quelle: Blizzard_SettingsDefinitions_Frame/Social.lua): "inline" im Chatfenster, "popout" eigener Reiter,
-- "popout_and_inline" beides. Der Knopf nennt den Stand im Chat, erklärt das Zusammenspiel mit ezChat und öffnet
-- Blizzards Seite. → der gelesene Wert (oder nil)
local WHISPER_MODES = { inline = "CONVERSATION_MODE_INLINE", popout = "CONVERSATION_MODE_POPOUT",
    popout_and_inline = "CONVERSATION_MODE_POPOUT_AND_INLINE" }
function ns.WhisperModeText(mode)
    local global = mode and WHISPER_MODES[mode]
    if not global then return tostring(mode or "?") end
    local text = rawget(_G, global)
    if type(text) == "string" and text ~= "" then return text end
    return L["WHISPER_MODE_" .. mode]
end

function ns.ShowWhisperMode()
    local ok, mode = pcall(ezCore.CVar, "whisperMode")
    if not ok or ns.IsSecret(mode) or type(mode) ~= "string" then mode = nil end
    ns.Print(L.WHISPER_MODE_NOW:format(ns.WhisperModeText(mode)))
    ns.Print(L["WHISPER_MODE_HINT_" .. (mode and WHISPER_MODES[mode] and mode or "unknown")])
    OpenBlizzardSocial()
    return mode
end

-- Unterschalter, die ohne ihren Oberschalter nichts tun: grau, solange er aus ist (Querschnitt „Unterschalter
-- ausgrauen“, Einstellungs-Prüfung 19.11.2026). Belege: Delivery.lua (Warteschlange nur mit offlineQueue; Fang aus dem
-- Chat, Nachhaken und Briefe arbeiten nur auf ihr), Spam.Check (bricht ohne spamFilter ab), Alarms.lua (Ton nur mit
-- highlight).
ns.OPTION_PARENT = {
    catchChatWhispers = "offlineQueue", retryWhisper = "offlineQueue", mailDelivery = "offlineQueue",
    spamBusy = "spamFilter", spamLevel = "spamFilter",
    highlightSound = "highlight",
}
local function Under(key) local p = ns.OPTION_PARENT[key] return p and { parent = p } or nil end

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    -- Übernimmt ein fremdes Addon die Funktion (ns.HANDLED_BY), steht das im Tooltip des Schalters.
    local function Section(name)
        for _, entry in ipairs(ns.TOGGLES) do
            local key = entry[1]
            if entry[3] == name and (key ~= "community" or ns.Community.Available()) then
                local note = ns.OtherNote(key)
                page:Checkbox(key, note and (L["OPT_" .. key .. "_TIP"] .. "\n\n" .. note) or nil, Under(key))
            end
        end
    end

    -- Allgemein: das Gesprächsfenster
    page:Button(L.OPT_OPEN_WINDOW, L.OPT_OPEN_WINDOW_BUTTON, function() ns.Window.Open() end, L.OPT_OPEN_WINDOW_TIP)

    page:Header(L.SECTION_HISTORY, L.PRIVACY_NOTE)
    Section("history")
    page:Slider("keepCount", 25, 500, 25)
    page:Slider("restoreCount", 5, 100, 5)
    page:Slider("keepDays", 0, 365, 5, function(value)
        value = math.floor(tonumber(value) or 0)
        return value == 0 and L.KEEP_FOREVER or L.KEEP_DAYS:format(value)
    end)
    page:Button(L.OPT_CLEAR, DELETE, function()   -- Blizzards Standardwort (Gesamtreview T18-22)
        ns.Confirm(L.CONFIRM_CLEAR, function() ns.History.ClearAll() end)
    end, L.OPT_CLEAR_TIP)

    page:Header(L.SECTION_OFFLINE, L.SECTION_OFFLINE_TIP)
    Section("offline")

    -- Läuft Prat, sagt der Tooltip der Überschrift, dass ezChats Link-Tooltip nur hier gilt (ns.HINT_BY.linkTooltip;
    -- seit der Prüfung der Einstellungen vom 19.11.2026 immer an, ohne eigenes Kästchen)
    page:Header(L.SECTION_WINDOW, ns.OtherNote("linkTooltip"))
    Section("window")
    page:Button(L.OPT_WHISPER_MODE, L.OPT_WHISPER_MODE_BUTTON, function() ns.ShowWhisperMode() end, L.OPT_WHISPER_MODE_TIP)

    page:Header(L.SECTION_CHAT, L.SECTION_CHAT_TIP)
    Section("chat")
    page:Button(L.OPT_TIMESTAMPS, L.OPT_TIMESTAMPS_BUTTON, OpenBlizzardSocial, L.OPT_TIMESTAMPS_TIP)

    page:Header(L.SECTION_HIGHLIGHT)
    Section("highlight")
    page:Button(L.OPT_KEYWORDS, L.OPT_KEYWORDS_BUTTON, function() ns.Format.EditKeywords() end, L.OPT_KEYWORDS_TIP)

    -- Spam-Filter (Spam.lua)
    page:Header(L.SECTION_SPAM, L.SECTION_SPAM_TIP)
    Section("spam")
    page:Slider("spamLevel", 0, 30, 1, function(value)
        value = math.floor(tonumber(value) or 0)
        return value == 0 and L.SPAM_LEVEL_OFF or tostring(value)
    end, nil, Under("spamLevel"))
    page:Button(L.OPT_SPAM_WORDS, L.OPT_SPAM_WORDS_BUTTON, function() ns.Spam.EditWords() end, L.OPT_SPAM_WORDS_TIP)
    page:Button(L.OPT_SPAM_SHOW, L.OPT_SPAM_SHOW_BUTTON, function() ns.Window.OpenFiltered() end, L.OPT_SPAM_SHOW_TIP)

    -- Verhalten je Lage (Situation.lua): Fenster, Ton, Alarme, dann die automatische Antwort
    page:Header(L.SECTION_SITUATION, L.SECTION_SITUATION_TIP)
    -- Fenster bei neuer Nachricht: je Lage und „Sonst“ (ohne Hauptschalter, Prüfung der Einstellungen vom 19.11.2026);
    -- übernimmt WIM die Flüsterfenster, sagt es der Tooltip
    local popupNote = ns.OtherNote("openOnWhisper")
    for _, sit in ipairs(ns.Situation.ORDER) do
        local key = "sitPopup" .. ns.Situation.SUFFIX[sit]
        -- „nach dem Kampf“ nur beim Kampf: die übrigen Lagen gelten nur außerhalb des Kampfes (Situation.Current prüft
        -- den Kampf zuerst), dort hieß es „sofort“ (code-reviewer 20.11.2026; gespeicherte Werte: ns.MigratePopupAfter)
        page:Dropdown(key, ns.Situation.PopupValues(sit ~= "combat"), popupNote and (L["OPT_" .. key .. "_TIP"] .. "\n\n" .. popupNote) or nil)
    end
    page:Dropdown("sitPopupOther", ns.Situation.PopupValues(true),
        popupNote and (L.OPT_sitPopupOther_TIP .. "\n\n" .. popupNote) or nil)
    Section("situation")
    page:Header(L.SECTION_REPLY, L.SECTION_REPLY_TIP)
    Section("reply")
    page:Slider("replyMinutes", 5, 240, 5)
    for _, sit in ipairs(ns.Situation.ORDER) do
        page:Button(L.OPT_REPLY_TEXT:format(L["SIT_" .. sit]), L.OPT_REPLY_TEXT_BUTTON, function() ns.Situation.EditReply(sit) end,
            L.OPT_REPLY_TEXT_TIP)
    end

    page:Header(L.SECTION_ALARM, L.SECTION_ALARM_TIP)
    Section("alarm")
    local tones = {}
    for _, name in ipairs(ns.TONES) do tones[#tones + 1] = { name, L["TONE_" .. name] } end
    page:Dropdown("alarmTone", tones)
    page:Button(L.OPT_ALARM_MORE, L.OPT_ALARM_MORE_BUTTON, function() ns.Window.OpenAlarms() end, L.OPT_ALARM_MORE_TIP)

    -- Mit anderen ezChat-Nutzern (Typing.lua): „tippt …“ und Ort, ab Werk aus
    page:Header(L.SECTION_PEERS, L.SECTION_PEERS_TIP)
    Section("peers")

    page:Advanced()
    page:StatusButton()        -- „Status – Im Chat zeigen“: der sichtbare Weg zu /ezchat status (Leitlinie 3)
    -- Diagnose: speichern, Namen unkenntlich (ab Werk) oder im Klartext, wieder löschen (Vollprüfung W-62)
    page:Button(L.OPT_DIAG, L.OPT_DIAG_BUTTON, function() ns.SaveDiag() end, L.OPT_DIAG_TIP)
    page:Checkbox("diagPlain")
    page:Button(L.OPT_DIAG_CLEAR, DELETE, function() ns.AskClearDiag() end, L.OPT_DIAG_CLEAR_TIP)
    -- „Einstellungen zurücksetzen“ aus ezCore, mit ezChats Hinweis, dass Verlauf und Gespräche bleiben
    page:ResetButton({ tip = L.OPT_RESET_TIP, ask = L.CONFIRM_RESET })
    page:TourButton(ns.Tour)   -- Erklärblasen erneut zeigen
    page:Companions()          -- ergänzende Addons (ezChat braucht nur ezCore; Liste heute leer)

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
