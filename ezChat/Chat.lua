local _, ns = ...
local L = ns.L
local Conv = ns.Conv

-- Gespräche vorrangig im Blizzard-Chatfenster:
-- * Rechtsklick auf einen Chat-Reiter → ezChat → Neues Gespräch (Freunde, Battle.net,
--   Gilde, letzte Gespräche, Name). Öffnet Blizzards Flüster-Eingabe und zeigt den
--   bisherigen Verlauf mit der Person grau darüber.
-- * Öffnet Blizzard einen Flüster-Reiter („Flüstern in neuem Reiter“), steht dort
--   sofort der gespeicherte Verlauf.
-- * Herauslösen: „Im Gesprächsfenster öffnen“ – das ezChat-Fenster ist der Rahmen.
-- Nur offizielle Wege: Menu.ModifyMenu, hooksecurefunc, AddMessage. Fenster und Reiter
-- öffnet Blizzard selbst, ezChat schreibt nichts in Blizzards Chat-Tabellen.

local Chat = {}
ns.Chat = Chat

local MENU_HEIGHT = 400   -- lange Listen scrollen

---------------------------------------------------------------------------
-- Gesprächspartner auswählen (Chat-Reiter-Menü und Gesprächsfenster)
---------------------------------------------------------------------------

local function BySort(a, b) return a.sort < b.sort end

local function NewGroup() return { online = {}, offline = {} } end

local function AddEntry(group, entry, online)
    entry.sort = entry.sort or entry.label:lower()
    table.insert(online and group.online or group.offline, entry)
end

local function SortGroup(group)
    table.sort(group.online, BySort)
    table.sort(group.offline, BySort)
    return group
end

-- Charaktere: WoW-Freunde (auch Battle.net-Freunde, die gerade dieses Spiel spielen,
-- als ihr Charakter) und Gilde.
local function Characters()
    local friends, guild, seen = NewGroup(), NewGroup(), {}
    ns.ForEachCharacter(function(full, online, source, bnLabel)
        if ns.IsSelf(full) then return end
        local name = ns.Short(full)
        if source == "guild" then
            AddEntry(guild, { target = full, label = name }, online)
            return
        end
        if seen[full:lower()] then return end   -- WoW- und Battle.net-Freund zugleich
        seen[full:lower()] = true
        local label = name
        if bnLabel then label = name .. " " .. ns.ColorText("bnet", "(" .. bnLabel .. ")") end
        AddEntry(friends, { target = full, label = label, sort = name:lower() }, online)
    end)
    return SortGroup(friends), SortGroup(guild)
end

-- Battle.net-Freunde fürs Battle.net-Flüstern; wer gerade spielt, mit Charakter in Grau.
-- Liste aller Battle.net-Konten aus ezCore (auch offline oder in anderen Spielen).
local function BNFriends()
    local group = NewGroup()
    for _, friend in ipairs(ezCore.BNFriends()) do
        local label = friend.character and (friend.name .. " " .. ezCore.Grey("(" .. ns.Short(friend.character) .. ")")) or friend.name
        AddEntry(group, { target = friend.tag, label = label, sort = friend.name:lower() }, friend.online)
    end
    return SortGroup(group)
end

local function Scrolling(description)
    if description.SetScrollMode then description:SetScrollMode(MENU_HEIGHT) end
end

local function AddNote(menu, text)
    if menu.CreateTitle then
        menu:CreateTitle(text)
    else
        local entry = menu:CreateButton(text, function() end)
        if entry.SetEnabled then entry:SetEnabled(false) end
    end
end

-- always: Gruppe auch ohne Einträge zeigen (mit Hinweis), damit man sie findet.
local function AddGroup(root, title, group, bn, onPick, always)
    local online, offline = group.online, group.offline
    if #online + #offline == 0 and not always then return end
    local sub = root:CreateButton(("%s (%d/%d)"):format(title, #online, #online + #offline))
    Scrolling(sub)
    if #online + #offline == 0 then AddNote(sub, L.PICK_NONE) end
    for _, entry in ipairs(online) do
        sub:CreateButton(entry.label, function() onPick(entry.target, bn) end)
    end
    if #online > 0 and #offline > 0 then sub:CreateDivider() end
    for _, entry in ipairs(offline) do
        sub:CreateButton(ezCore.Grey(entry.label .. " – " .. L.OFFLINE), function() onPick(entry.target, bn) end)
    end
end

-- Füllt ein Menü mit allen möglichen Gesprächspartnern. onPick(target, bn).
function ns.PartnerMenu(root, onPick)
    local recent = Conv.Sorted()
    if #recent > 0 then
        local sub = root:CreateButton(L.PICK_RECENT)
        Scrolling(sub)
        for i = 1, math.min(20, #recent) do
            local convo = recent[i].convo
            sub:CreateButton(Conv.MenuLabel(convo), function() onPick(convo.name, convo.bn) end)
        end
    end
    local friends, guild = Characters()
    AddGroup(root, L.PICK_FRIENDS, friends, false, onPick, true)
    AddGroup(root, L.PICK_BNET, BNFriends(), true, onPick)
    AddGroup(root, L.PICK_GUILD, guild, false, onPick)
    root:CreateDivider()
    root:CreateButton(L.PICK_NAME, function()
        ns.AskText(L.POPUP_NEW, "", function(text)
            local full = ns.TypedName(text)
            if full then onPick(full, false) end
        end)
    end)
end

---------------------------------------------------------------------------
-- Chatfenster finden
---------------------------------------------------------------------------

-- BattleTag zu Blizzards Kontoname (|K…|k) eines Flüster-Reiters (ezCore).
local TagOfAccountName = ezCore.BNTagOfAccountName

-- Gesprächsschlüssel eines Blizzard-Flüster-Reiters (nur lesen).
local function KeyOfFrame(frame)
    if type(frame) ~= "table" or not frame.isTemporary then return nil end
    local chatType, target = frame.chatType, frame.chatTarget
    if type(target) ~= "string" or not ns.Usable(chatType, target) then return nil end
    if chatType == "WHISPER" then
        local full = ns.FullName(target)
        return full and Conv.KeyOf(ns.CompleteName(full))
    elseif chatType == "BN_WHISPER" then
        local tag = TagOfAccountName(target)
        return tag and Conv.KeyOf(tag, true)
    end
    return nil
end
Chat.KeyOfFrame = KeyOfFrame

local function DedicatedFrame(key)
    for _, name in ipairs(CHAT_FRAMES or {}) do
        local frame = _G[name]
        if frame and frame.inUse and KeyOfFrame(frame) == key then return frame end
    end
    return nil
end

-- Wo ein Gespräch im Chat erscheint: eigener Flüster-Reiter, sonst das gewählte
-- Chatfenster (wenn es Flüstern zeigt), sonst das Hauptfenster.
function Chat.FrameFor(key)
    local frame = key and DedicatedFrame(key)
    if frame then return frame end
    local current = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame()
    if current and ns.History.FrameShows(current, "WHISPER") then return current end
    return DEFAULT_CHAT_FRAME
end

-- ezChat-Hinweis beim Gespräch zeigen (Reiter des Partners oder Hauptfenster).
function Chat.Note(key, text)
    local frame = Chat.FrameFor(key)
    ns.NoteTo(frame, text)
    if frame ~= DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME then ns.NoteTo(DEFAULT_CHAT_FRAME, text) end
end

-- Eingehender Brief: wie ein Flüstern im Chat zeigen.
function Chat.ShowIncoming(key, convo, msg)
    local frame = Chat.FrameFor(key)
    local line, chatType = ns.History.ConvoLine(convo, msg)
    local r, g, b = ns.WhisperColor(chatType)
    frame:AddMessage(("[%s] %s"):format(ns.TimeText(msg.t), line), r, g, b)
end

---------------------------------------------------------------------------
-- Gespräch im Chat beginnen
---------------------------------------------------------------------------

-- Blizzards Eingabezeile auf Flüstern an den Partner stellen. Flüstern „klebt“ danach
-- (ChatTypeInfo.WHISPER.sticky), bis man den Kanal wechselt.
-- noteFrame: Chatfenster für Hinweise (nil = keine Hinweise ausgeben).
function Chat.Tell(convo, noteFrame)
    if convo.bn then
        local _, _, accountName = ns.BNFind(convo.name)
        local fn = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
        if accountName and fn then
            pcall(fn, accountName)
        else
            ns.Print(L.BN_NOT_FRIEND)
        end
        return
    end
    -- WoW Forever braucht „Vorname Nachname“, sonst bleibt die Eingabezeile bei „/w Vorname“.
    if noteFrame and ns.MissingSurname(convo.name) then
        ns.NoteTo(noteFrame, L.NEED_SURNAME:format(convo.name))
    end
    local fn = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    local chatFrame = noteFrame ~= DEFAULT_CHAT_FRAME and noteFrame or nil
    if fn then pcall(fn, ns.TellName(convo.name), chatFrame) end
end

---------------------------------------------------------------------------
-- Flüsterziel der Gesprächsansicht (Spieltest 21.11.2026: „ich muss diese person seperat anflüstern“)
---------------------------------------------------------------------------
-- Blizzards Flüster-Eingabe (SendTell) stellt nur den Chattyp, nicht den „klebenden“ Typ: Esc, ein Klick daneben
-- oder das Schließen der Zeile (Deactivate → ResetChatTypeToSticky) setzt sie zurück auf Sagen. Die Ansicht stellt
-- darum mit Blizzards eigenen Methoden der Eingabezeile (ChatFrameEditBoxBaseMixin, Forever-Quelle
-- Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua; so auch ChatFrameUtil.SendBNetTell und ReplyTell) Chattyp,
-- klebenden Typ und Ziel auf den Partner – wie Blizzards Flüster-Reiter im Stil „IM“ (FCF_OpenTemporaryWindow).
-- Der Stand davor wird gemerkt und beim Zurück zum Chat wiederhergestellt, solange die Zeile noch auf das
-- Gespräch zeigt; hat der Spieler im Gespräch selbst gewechselt (/g, /2 …), bleibt seine Wahl.
-- Die Zeile wird nur gestellt, nie aus Addon-Code geöffnet: Blizzards OpenChat/ActivateChat schreibt dabei die
-- globalen Merker ACTIVE_CHAT_EDIT_BOX und LAST_ACTIVE_CHAT_EDIT_BOX, und aus Addon-Code geschrieben bleiben sie
-- befleckt bis /reload – jedes spätere Enter des Spielers liest sie (taint.log des Nutzers vom 21.11.2026). Enter
-- öffnet die Zeile dann wie gewohnt, schon mit „Flüstert an …“ (der Kopf der Ansicht sagt es: L.VIEW_ENTER). Ob
-- die aus Addon-Code gestellten Attribute Blizzards Senden beflecken, kann das Log nicht zeigen – offen in der
-- Roadmap (docs/roadmap/ezChat.md, „Taint des Flüsterziels“).
local tellSaved   -- { box, chatType, stickyType, tellTarget, set = { chatType, target } } oder nil

-- Die Eingabezeile, die Blizzard zum Schreiben nimmt (Stil „klassisch“: die des Hauptfensters, „IM“: die des
-- gezeigten Fensters); nil, wenn sie die Methoden nicht hat.
local TELL_METHODS = { "GetChatType", "SetChatType", "GetStickyType", "SetStickyType", "GetTellTarget",
    "SetTellTarget", "UpdateHeader" }
local function SendBox(chatFrame)
    local choose = ChatFrameUtil and ChatFrameUtil.ChooseBoxForSend
    if not choose then return nil end
    local ok, box = pcall(choose, chatFrame)
    if not ok or type(box) ~= "table" then return nil end
    for _, method in ipairs(TELL_METHODS) do
        if type(box[method]) ~= "function" then return nil end
    end
    return box
end

-- Chattyp und Ziel für das Gespräch: Spieler „WHISPER“ an den Namen, den der Client braucht (ns.TellName);
-- Battle.net-Freunde „BN_WHISPER“ an den Kontonamen, Titel-Freunde wie bei Blizzard an ihre Figur
-- (ChatFrameUtil.SendBNetTell). nil, wenn der Battle.net-Partner kein Freund (mehr) ist.
local function TellOf(convo)
    if not convo.bn then return "WHISPER", ns.TellName(convo.name) end
    local _, _, accountName = ns.BNFind(convo.name)
    if not accountName then return nil end
    local title = ChatFrameUtil and ChatFrameUtil.GetCharacterWhisperTargetIfTitleFriend
    if title then
        local ok, character = pcall(title, accountName)
        if ok and type(character) == "string" and character ~= "" then return "WHISPER", character end
    end
    return "BN_WHISPER", accountName
end

-- Blizzards Eingabezeile zurück auf den gemerkten Stand (Ansicht geschlossen, anderes Fenster, Partner ohne Ziel).
-- Rückgabe: true, wenn zurückgestellt wurde.
function Chat.RestoreTell()
    local saved = tellSaved
    tellSaved = nil
    if not saved or not saved.set then return false end
    local box, set = saved.box, saved.set
    local ok, sticky, target = pcall(function() return box:GetStickyType(), box:GetTellTarget() end)
    if not ok then return false end
    if ezCore.IsSecret(sticky) or ezCore.IsSecret(target) then   -- gesperrt: nichts vergleichen (Leitlinie 6), beim nächsten Mal
        tellSaved = saved
        return false
    end
    if sticky ~= set.chatType or target ~= set.target then return false end   -- der Spieler hat gewechselt
    -- Geschlossene Zeile: Chattyp = klebender Typ wie bei Blizzard (ClearChat); ein flüchtiger Typ von damals
    -- (Schreien, Antwort an einen Dritten) gilt nur in einer gerade offenen Zeile weiter.
    local util = ChatFrameUtil
    local chatType = saved.chatType
    if not (util and util.GetActiveWindow and util.GetActiveWindow() == box) then chatType = saved.stickyType end
    ok = pcall(function()
        box:SetTellTarget(saved.tellTarget)
        box:SetStickyType(saved.stickyType)
        box:SetChatType(chatType)
        box:UpdateHeader()
    end)
    return ok
end

-- Blizzards Eingabezeile auf das Gespräch stellen (Chattyp, klebender Typ, Ziel). chatFrame: das gezeigte
-- Chatfenster. Beim Wechsel zwischen Gesprächen bleibt der Stand vor dem ersten gemerkt.
-- Rückgabe: true, wenn gestellt; false (Zeile unverändert bzw. auf den alten Stand zurück) sonst.
function Chat.SetTellTarget(convo, chatFrame)
    local box = SendBox(chatFrame)
    local chatType, target = TellOf(convo)
    if tellSaved and (not box or not chatType or tellSaved.box ~= box) then Chat.RestoreTell() end
    if not box or not chatType then return false end
    if not tellSaved then
        local ok, before = pcall(function()
            return { box = box, chatType = box:GetChatType(), stickyType = box:GetStickyType(),
                tellTarget = box:GetTellTarget() }
        end)
        if not ok then return false end
        tellSaved = before
    end
    local ok, err = pcall(function()
        box:SetTellTarget(target)
        box:SetChatType(chatType)
        box:SetStickyType(chatType)
        box:UpdateHeader()
    end)
    if not ok then   -- halb gestellt: zurück auf den gemerkten Stand (gilt als „noch auf das Gespräch“)
        ns.Error(err)   -- nicht stumm: ohne Ziel müsste der Spieler wieder selbst anflüstern
        local saved = tellSaved
        pcall(function()
            saved.set = { chatType = box:GetStickyType(), target = box:GetTellTarget() }
        end)
        Chat.RestoreTell()
        return false
    end
    tellSaved.set = { chatType = chatType, target = target }
    return true
end

-- Das gestellte Flüsterziel, solange die Zeile noch darauf zeigt (für den Hinweis „Enter: … anflüstern“), sonst nil.
function Chat.TellTarget()
    local saved = tellSaved
    if not saved or not saved.set then return nil end
    local ok, sticky, target = pcall(function() return saved.box:GetStickyType(), saved.box:GetTellTarget() end)
    if not ok or sticky ~= saved.set.chatType or target ~= saved.set.target then return nil end
    return target
end

-- Gezeigtes Gespräch nachführen (Chat-Ansicht bei jeder Änderung und beim Wechsel des gezeigten Fensters):
-- hat das Gespräch einen neuen Namen (Conv.Fix ergänzt den Nachnamen, Conv.Rename legt zusammen) oder nimmt
-- Blizzard eine andere Eingabezeile (Stil „IM“), wird die Zeile neu gestellt – nur, solange sie noch auf das
-- Gespräch zeigt; die eigene Wahl des Spielers bleibt. Rückgabe: true, wenn neu gestellt.
function Chat.KeepTell(convo, chatFrame)
    local saved = tellSaved
    if not saved or not saved.set then return false end
    local box = SendBox(chatFrame)
    if box and box ~= saved.box then return Chat.SetTellTarget(convo, chatFrame) end
    local chatType, target = TellOf(convo)
    if chatType == saved.set.chatType and target == saved.set.target then return false end
    local ok, sticky, current = pcall(function() return saved.box:GetStickyType(), saved.box:GetTellTarget() end)
    if not ok or sticky ~= saved.set.chatType or current ~= saved.set.target then return false end
    return Chat.SetTellTarget(convo, chatFrame)
end

-- Gespräch beginnen: in der Gesprächsansicht des Chatfensters (Auswahl in der
-- Reiterleiste), sonst direkt im Chat mit dem älteren Verlauf grau darüber.
function Chat.Start(target, bn)
    local convo, key = Conv.Get(target, bn, true)
    if not convo then return end
    key = Conv.Fix(key)
    convo = ns.C.convos[key]
    convo.closed = nil
    if ns.ChatView and ns.ChatView.Enabled() then
        ns.ChatView.Select(key, true)
        return
    end
    if (convo.unread or 0) > 0 then   -- der Verlauf steht gleich im Chat
        convo.unread = 0
        Conv.Changed(key)
    end
    local frame = Chat.FrameFor(key)
    ns.History.PrintConvo(frame, convo, ns.Number("restoreCount"))
    local online = ns.Delivery.IsOnline(convo)
    if online == false and ns.S.offlineQueue then
        ns.NoteTo(frame, L.HINT_OFFLINE:format(ns.Delivery.WaysText(convo)))
    end
    ns.Delivery.Expect(key)
    Chat.Tell(convo, frame)
end

---------------------------------------------------------------------------
-- Blizzards Flüster-Reiter: Verlauf beim Öffnen einblenden
---------------------------------------------------------------------------

local function OnTemporaryWindow(chatType, chatTarget)
    if not ns.C or (chatType ~= "WHISPER" and chatType ~= "BN_WHISPER") then return end
    if type(chatTarget) ~= "string" or not ns.Usable(chatTarget) then return end
    local key
    if chatType == "WHISPER" then
        local full = ns.FullName(chatTarget)
        key = full and Conv.KeyOf(ns.CompleteName(full))
    else
        local tag = TagOfAccountName(chatTarget)
        key = tag and Conv.KeyOf(tag, true)
    end
    local convo = key and ns.C.convos[key]
    local frame = key and DedicatedFrame(key)
    if convo and frame then ns.History.PrintConvo(frame, convo, ns.Number("restoreCount")) end
end

if type(FCF_OpenTemporaryWindow) == "function" then
    hooksecurefunc("FCF_OpenTemporaryWindow", function(chatType, chatTarget)
        ns.Seen("FCF_OpenTemporaryWindow")
        local ok, err = pcall(OnTemporaryWindow, chatType, chatTarget)
        if not ok then ns.Error(err) end
    end)
end

---------------------------------------------------------------------------
-- Rechtsklick auf einen Chat-Reiter: ezChat
---------------------------------------------------------------------------

-- Alle ezChat-Funktionen als Menü (Chat-Reiter und Rechtsklick auf die ezChat-Symbole).
-- key: Gespräch des angeklickten Flüster-Reiters (zum Herauslösen) oder nil.
function Chat.FillMenu(menu, key)
    local new = menu:CreateButton(L.NEW_CONVERSATION)
    ns.PartnerMenu(new, Chat.Start)
    if key and ns.C.convos[key] then
        menu:CreateButton(L.CHAT_DETACH, function() ns.Window.Open(key) end)
        ns.FlagEntries(menu, key)
    end
    menu:CreateButton(L.CHAT_OPEN_WINDOW, function() ns.Window.Open() end)
    ns.Alarms.FillMenu(menu:CreateButton(L.ALARM_BUTTON))
    local queued = #Conv.QueuedKeys()
    if queued > 0 then
        menu:CreateButton(L.CHAT_QUEUE:format(queued), function() ns.ListQueue() end)
    end
    -- „Einstellungen …“ von ezCore (Text, Zahnrad, Tooltip, im Kampf vorgemerkt; Gesamtreview T18-8)
    ezCore.Menu.Settings(menu, ns)
end

local function ChatTabMenu(owner, root)
    if not ns.C then return end
    local chatFrame = owner and owner.GetID and FCF_GetChatFrameByID and FCF_GetChatFrameByID(owner:GetID())
    root:CreateDivider()
    Chat.FillMenu(root:CreateButton(L.CHAT_MENU), KeyOfFrame(chatFrame))
end

---------------------------------------------------------------------------
-- Rechtsklick auf Spieler (Chat, Freunde auch offline, Gilde): ezChat-Gespräch
---------------------------------------------------------------------------

-- Welche Menüs: ezCores eine Liste der Spieler-Menüs (Core.Menu.PlayerMenus, Welle 16; vorher eine eigene Liste hier)
-- ohne den eigenen Charakter und die Gegenfraktion. Ausgelassen bleiben wie bisher die Raid-Liste, der Fokus,
-- Battle.net-Freunde offline (das Gesprächsfenster öffnet Blizzards Menü dafür selbst) und „Kürzlich zusammen
-- gespielt“ – der Umfang bleibt, die Tags kommen aus ezCore (Welle 23, A1).
Chat.UNIT_MENUS_LEFT_OUT = {
    MENU_UNIT_RAID = true, MENU_UNIT_FOCUS = true, MENU_UNIT_BN_FRIEND_OFFLINE = true,
    MENU_UNIT_RECENT_ALLY = true, MENU_UNIT_RECENT_ALLY_OFFLINE = true,
}
function Chat.UnitMenus()
    local list = {}
    for _, tag in ipairs(ezCore.Menu.PlayerMenus({ self = false, enemy = false })) do
        if not Chat.UNIT_MENUS_LEFT_OUT[tag] then list[#list + 1] = tag end
    end
    return list
end

-- Ziel eines Spieler-Menüs: voller Name (oder BattleTag) und, bei Battle.net-Freunden,
-- die gerade dieses Spiel spielen, zusätzlich ihr Charakter.
local function MenuTarget(contextData)
    if type(contextData) ~= "table" then return nil end
    if contextData.bnetIDAccount then
        local tag = ns.BNTagOf(contextData.bnetIDAccount)
        if not tag then return nil end
        return tag, true, ns.BNCharacter(ns.BNInfoByID(contextData.bnetIDAccount))
    end
    local name, server = contextData.name, contextData.server
    if type(name) ~= "string" or not ns.Usable(name, server) then return nil end
    local unit = contextData.unit
    -- ezCore.UnitIs (V-184): existiert und ist Spieler; false = kein Spieler, nil = gesperrt oder unbekannt
    if unit and ns.Usable(unit) and ezCore.UnitPresent(unit) == true then
        if ezCore.UnitIs(unit) ~= true then return nil end
    end
    -- server ist der Realm, auf WoW Forever der Nachname: FullName unterscheidet beides.
    if type(server) == "string" and server ~= "" and not name:find("-", 1, true) then
        name = name .. "-" .. server
    end
    local full = ns.FullName(name)
    if not full or ns.IsSelf(full) then return nil end
    return ns.CompleteName(full), false
end

local function AddPartnerEntries(menu, target, bn)
    menu:CreateButton(L.MENU_CHAT_WRITE, function() Chat.Start(target, bn) end)
    menu:CreateButton(L.CHAT_DETACH, function() ns.Window.OpenFor(target, bn) end)
end

local function UnitMenu(root, contextData)
    local target, bn, character = MenuTarget(contextData)
    if not target then return end
    root:CreateDivider()
    local entry = root:CreateButton(L.MENU_CONVERSATION)
    if character then
        -- Battle.net-Freund im Spiel: Charakter direkt oder über Battle.net anschreiben
        local char = entry:CreateButton(L.MENU_AS_CHARACTER:format(ns.Short(character)))
        AddPartnerEntries(char, character, false)
        local account = entry:CreateButton(L.MENU_AS_BNET)
        AddPartnerEntries(account, target, true)
    else
        AddPartnerEntries(entry, target, bn)
    end
end

ns.OnReady(function()
    if not (Menu and Menu.ModifyMenu) then return end
    pcall(Menu.ModifyMenu, "MENU_FCF_TAB", function(owner, root)
        ns.Seen("MENU_FCF_TAB")
        local ok, err = pcall(ChatTabMenu, owner, root)
        if not ok then ns.Error(err) end
    end)
    for _, tag in ipairs(Chat.UnitMenus()) do
        pcall(Menu.ModifyMenu, tag, function(_, root, contextData)
            ns.Seen(tag)
            local ok, err = pcall(UnitMenu, root, contextData)
            if not ok then ns.Error(err) end
        end)
    end
end)
