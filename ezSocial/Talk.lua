local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Knopf „Gespräch“ (Befund ezChat und ezSocial, 13.11.2026: ezSocial ist für Menschen und Gruppen in Blizzards
    Fenstern zuständig, ezChat für Nachrichten). In der Freundesliste, der Wer-Liste und bei „Durchsuchen“ öffnet
    ein kleiner Knopf das Gespräch mit dem Spieler in ezChat; dazu die Zahl ungelesener Nachrichten (gold, unten
    rechts) und wartender (grau, oben rechts – ezChat schickt sie, sobald der Empfänger online ist).
    Alles über ezCore.API("ezChat"): OpenConversation(name, { bn }) und – falls ezChat sie anbietet –
    ConversationCounts(name, { bn }) → ungelesen, wartend; bei Änderungen schickt ezChat die Nachricht
    EZCHAT_CONVERSATIONS_CHANGED (ezCore.Fire). Ohne ezChat oder mit Schalter aus bleiben die Knöpfe verborgen.
    Eigene Knöpfe in Blizzards Zeilen (Vorlage UIMenuButtonStretchTemplate wie Blizzards Abmelde-Knopf in
    „Durchsuchen“); Blizzards Zeilen und Texte bleiben unberührt.
]]

local Talk = {}
ns.Talk = Talk

-- Name der Nachricht, mit der ezChat Änderungen meldet: ezChats API.CHANGED, sobald ezChat geladen ist
-- (Talk.Listen); der feste Name hier ist nur der Ersatz bis dahin.
Talk.CHANGED = "EZCHAT_CONVERSATIONS_CHANGED"
local ICON = "Interface\\Icons\\UI_Chat"     -- dasselbe Symbol wie ezChats Knopf „Gespräche“ an der Chat-Leiste

local buttons = setmetatable({}, { __mode = "k" })

-- ezChats Schnittstelle, solange sie Gespräche öffnen kann; sonst nil.
function Talk.API()
    local api = Core.API("ezChat")
    if type(api) == "table" and type(api.OpenConversation) == "function" then return api end
    return nil
end

function Talk.Enabled()
    return ns.Enabled("talkButtons") and Talk.API() ~= nil
end

-- opts für ezChats OpenConversation/ConversationCounts: { bn, text } oder nil.
local function Opts(bn, text)
    if type(text) ~= "string" or Core.IsSecret(text) or text == "" then text = nil end
    if not bn and not text then return nil end
    return { bn = bn and true or nil, text = text }
end

-- Ungelesen, wartend – oder nil, wenn ezChat die Zahlen nicht anbietet.
function Talk.Counts(name, bn)
    local api = Talk.API()
    if not (api and type(api.ConversationCounts) == "function") or type(name) ~= "string" then return nil end
    local ok, unread, queued = pcall(api.ConversationCounts, name, Opts(bn))
    if not ok or unread == nil then return nil end
    return Core.Num(unread) or 0, Core.Num(queued) or 0
end

-- Gibt es in ezChat schon ein Gespräch mit dem Spieler? true/false, nil wenn ezChat es nicht sagt.
function Talk.Known(name, bn)
    local api = Talk.API()
    if not (api and type(api.Conversation) == "function") or type(name) ~= "string" then return nil end
    local ok, state = pcall(api.Conversation, name, bn and true or false)
    if not ok then return nil end
    return state ~= nil
end

-- Gespräch in ezChat öffnen (voller Name oder BattleTag mit bn); true, wenn ezChat es geöffnet hat.
-- text: vorbereitete Antwort für das Eingabefeld (ezChat: opts.text) – gesendet wird nichts. Sie geht nur mit,
-- solange es noch kein Gespräch mit dem Spieler gibt: ein angefangener Text dort bleibt, wie er ist.
function Talk.Open(name, bn, text)
    local api = Talk.API()
    if not api or type(name) ~= "string" or name == "" then return false end
    if text ~= nil and Talk.Known(name, bn) ~= false then text = nil end
    local ok, key = pcall(api.OpenConversation, name, Opts(bn, text))
    return ok and key ~= nil
end

-- Der eine Weg zum Gespräch für alle Stellen im Modul (Vollprüfung V-130): ezChat, sonst Blizzards Flüstern.
-- → true und der Weg ("ezChat" | "tell"), sonst false.
function Talk.Whisper(name, text)
    if type(name) ~= "string" or Core.IsSecret(name) or name == "" then return false end
    if Talk.Open(name, false, text) then return true, "ezChat" end
    local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if type(tell) ~= "function" then return false end
    tell(Core.ShortName(name))
    return true, "tell"
end

---------------------------------------------------------------------------
-- Knopf
---------------------------------------------------------------------------

local function ShowTooltip(self)
    if not self.talkName then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- Zeilen in den Rollen von ezCore (Gesamtreview T9-6), Weg zum Schalter über Core.SettingsPathText (T18-18)
    Core.TipTitle(GameTooltip, L.TALK_BUTTON)
    local where = Core.SettingsPathText(ns.moduleName or "ezSocial", "OPT_HEADER_TALK", "OPT_talkButtons", L)
    Core.TipText(GameTooltip, L.TALK_TIP:format(self.talkLabel or Core.ShortName(self.talkName) or self.talkName, where))
    local unread, queued = Talk.Counts(self.talkName, self.talkBn)
    if unread and unread > 0 then Core.TipLine(GameTooltip, L.TALK_UNREAD:format(unread), "normal") end
    if queued and queued > 0 then Core.TipLine(GameTooltip, L.TALK_QUEUED:format(queued), "hint", true) end
    GameTooltip:Show()
end

-- Neuer Knopf (verborgen) in einer Zeile von Blizzard; Lage setzt der Aufrufer.
function Talk.Button(parent, width, height)
    local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIMenuButtonStretchTemplate")
    if not (ok and b) then b = CreateFrame("Button", nil, parent) end
    height = height or width
    b:SetSize(width, height)
    b.Icon = b:CreateTexture(nil, "ARTWORK")
    b.Icon:SetSize(height - 6, height - 6)
    b.Icon:SetPoint("CENTER")
    b.Icon:SetTexture(ICON)
    b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if not (b.GetHighlightTexture and b:GetHighlightTexture()) then
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    end
    b.Unread = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.Unread:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -2)
    -- Farben über ezCores Rollen (Design-System 2.5, Welle 22; vorher Zahlen): ungelesen in Gold, wartend grau
    -- (an SetTextColor nur r, g, b – der vierte Wert von Core.Style.Color ist Blizzards Farbobjekt).
    local cr, cg, cb = Core.Style.Color("normal")
    b.Unread:SetTextColor(cr, cg, cb)
    b.Queued = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.Queued:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3, 2)
    cr, cg, cb = Core.Style.Color("gray")
    b.Queued:SetTextColor(cr, cg, cb)
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", function(self)
        if self.talkName then Talk.Open(self.talkName, self.talkBn) end
    end)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:Hide()
    buttons[b] = true
    return b
end

function Talk.UpdateCounts(button)
    local unread, queued = Talk.Counts(button.talkName, button.talkBn)
    button.Unread:SetText((unread and unread > 0) and tostring(unread) or "")
    button.Queued:SetText((queued and queued > 0) and tostring(queued) or "")
end

-- Zeigt den Knopf, solange ezChat da und der Schalter an ist; sonst verborgen.
local function Apply(button)
    if button.wantName and Talk.Enabled() then
        button.talkName, button.talkBn, button.talkLabel = button.wantName, button.wantBn, button.wantLabel
        Talk.UpdateCounts(button)
        button:Show()
    else
        button.talkName = nil
        button:Hide()
    end
end

-- Für wen der Knopf gilt (voller Name oder BattleTag mit bn, label: Name im Tooltip); name nil blendet ihn aus.
function Talk.Set(button, name, bn, label)
    if not button then return end
    if type(name) ~= "string" or Core.IsSecret(name) or name == "" then name = nil end
    -- Forever: Blizzards Listen nennen mitunter nur den Vornamen – über ezCores Kontakte ergänzen
    -- (Core.CompleteName: nur bei genau einem Kontakt mit diesem Vornamen, sonst bleibt der Name)
    if name and not bn then name = Core.CompleteName(name) end
    button.wantName, button.wantBn, button.wantLabel = name, (name and bn) and true or nil, label
    Apply(button)
end

-- Zahlen und Sichtbarkeit aller Knöpfe neu (ezChat meldet eine Änderung, Schalter umgelegt).
function Talk.Refresh()
    for button in pairs(buttons) do Apply(button) end
end

-- Auf ezChats Änderungs-Nachricht hören. Der Name kommt aus ezChats Schnittstelle (API.CHANGED); beim Laden
-- der Datei ist ezChat vielleicht noch nicht da, deshalb zuerst der Ersatzname und nach dem Anmelden noch einmal.
local listening = {}
local function OnChanged() ns.Try("Talk", Talk.Refresh) end

function Talk.Listen()
    local api = Talk.API()
    local message = api and api.CHANGED
    if type(message) ~= "string" or message == "" then message = Talk.CHANGED end
    Talk.CHANGED = message
    if not listening[message] then
        listening[message] = true
        Core.Listen(message, OnChanged, "ezSocial")
    end
    return message
end

Talk.Listen()
ns.OnReady(Talk.Listen)

ns.OnSettingChanged(function(key)
    if key == "talkButtons" then Talk.Refresh() end
end)
