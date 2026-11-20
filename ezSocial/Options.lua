local _, ns = ...
local L = ns.L

-- Einstellungen unter Esc → Optionen → AddOns → ezCollection → ezSocial (Seite von ezCore).
-- Aufbau wie jede Seite: „Allgemein“ (Fenster öffnen) → Themen → „Erweitert“.
local page

-- Unterschalter von „Reiter ‚Aus dem Chat‘“ (chatTab), die ohne ihn nichts tun: grau, solange er aus ist (Querschnitt
-- „Unterschalter ausgrauen“; entschieden am 20.11.2026). Belege: ChatLFG.lua – das Mitlesen (CHAT_MSG_CHANNEL) und
-- Chat.Add brechen ohne chatTab ab, die Kanäle werden nur dort gefragt; ChatTab.lua – der Reiter samt Gruppieren
-- (chatGroup), Antwortvorschlag (chatReply) und Alter (chatMaxAge) ist ohne chatTab aus; Panel.lua – ezPanels
-- Meldung liefert ohne chatTab nichts.
ns.OPTION_PARENT = {
    chatTrade = "chatTab", chatLFG = "chatTab", chatWorld = "chatTab", chatGeneral = "chatTab",
    chatMaxAge = "chatTab", chatGroup = "chatTab", chatReply = "chatTab",
}
local function Under(key) local p = ns.OPTION_PARENT[key] return p and { parent = p } or nil end

local function Register()
    if page then return end
    page = ezCore.NewSettingsPage(ns)
    if not page then return end

    -- Allgemein: die beiden Fenster, die ezSocial erweitert
    -- Befehle in den Tooltips über ns.SlashCmd (nie ein Kurzbefehl, der einem anderen Addon gehört; Gesamtreview T18-2)
    page:Button(L.OPT_OPEN_FINDER, L.OPT_OPEN_BUTTON, function() ns.OpenGroupFinder() end, L.OPT_OPEN_FINDER_TIP:format(ns.SlashCmd()))
    page:Button(L.OPT_OPEN_CHAT, L.OPT_OPEN_BUTTON, function() ns.OpenChatTab() end, L.OPT_OPEN_CHAT_TIP:format(ns.SlashCmd("chat")))

    -- Ein Farb-Schalter für Gruppensuche, Wer-Liste, Freunde und Gilde (Prüfung der Einstellungen vom 19.11.2026,
    -- Nr. 65–68); Stufe der Gruppe, gesperrte Instanzen, Twinks der Freunde und der Bereitschafts-Timer sind immer an
    -- (Nr. 25–28)
    page:Checkbox("colors")

    page:Header(L.OPT_HEADER_FINDER)
    page:Checkbox("finderMembers")
    page:Checkbox("finderRoleBorder")

    page:Header(L.OPT_HEADER_CHAT)
    page:Checkbox("chatTab")
    page:Checkbox("chatTrade", nil, Under("chatTrade"))
    page:Checkbox("chatLFG", nil, Under("chatLFG"))
    page:Checkbox("chatWorld", nil, Under("chatWorld"))
    page:Checkbox("chatGeneral", nil, Under("chatGeneral"))
    page:Slider("chatMaxAge", 5, 60, 5, function(value) return ezCore.Minutes(value) end, nil, Under("chatMaxAge"))
    page:Checkbox("chatGroup", nil, Under("chatGroup"))
    page:Checkbox("chatReply", nil, Under("chatReply"))

    page:Header(L.OPT_HEADER_LISTS)
    page:Checkbox("friendNotes")

    page:Header(L.OPT_HEADER_TALK)
    page:Checkbox("talkButtons")

    page:Header(L.OPT_HEADER_MENU)
    page:Checkbox("menuGuildInvite")

    page:Header(L.OPT_HEADER_AUTO)
    page:Checkbox("acceptSummon")
    page:Checkbox("acceptResurrect")
    page:Checkbox("blockDuels")
    page:Checkbox("blockInvites")

    page:Advanced()
    page:StatusButton(L.OPT_STATUS_TIP:format(ns.SlashCmd("status")))   -- Beschriftung von ezCore (Gesamtreview T9-2)
    page:Button(L.OPT_CLEAR_CHAT, L.OPT_CLEAR_BUTTON, function() ns.Chat.Clear() end, L.OPT_CLEAR_CHAT_TIP)
    page:Button(L.OPT_FORGET_ALTS, L.OPT_CLEAR_BUTTON, function()
        ezCore.ForgetBNAlts()   -- die Twinks merkt sich ezCore für die ganze Sammlung
        ns.Print(L.ALTS_FORGOTTEN)
    end, L.OPT_FORGET_ALTS_TIP)
    page:ResetButton()   -- „Einstellungen zurücksetzen“ (ezCore); gesammelte Nachrichten und Twinks bleiben
    page:TourButton(ns.Tour.tour, L.OPT_TOUR_TIP)   -- „Erklärung erneut zeigen“ (Tour.lua)
    page:Companions()    -- „Ergänzende Addons“ (ezCore); ezSocial meldet keine an, dann bleibt der Abschnitt weg

    page:Register()
end

ns.OnReady(function() ns.Try("Settings", Register) end)

function ns.OpenSettings()
    return page ~= nil and page:Open()
end
