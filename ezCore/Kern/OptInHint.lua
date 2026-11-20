local _, ns = ...
local Core = ezCore

--[[
    Hinweis auf Abläufe ohne Klick (Welle 28, Paket kern/blizzard-handel; Antwort des Nutzers vom 17.11.2026, wörtlich
    „user muss auf sowas hingewiesen werden, er kann es nutzen muss es aber einschalten“). Was ohne Klick Gold kostet,
    verkauft, sendet oder Blizzards Zustände umstellt (Zielverfolgung, Questverfolgung, Markierung, Aufspüren), ist ab
    Werk aus. Damit der Spieler davon erfährt, zeigt ezCore EINMAL je Account und Funktion, wenn er das passende
    Blizzard-Fenster öffnet und die Funktion aus ist, eine Erklärblase am Fenster: was die Funktion tut, dass sie aus
    ist und warum, je Funktion ein Knopf „Einschalten“ (Leitlinie 3) und der Weg zur Einstellung. Höchstens EINE Blase
    je Fensteröffnung – mehrere Funktionen am selben Fenster (Händler: Plunder, Reparatur, Vorrat) stehen zusammen
    darin. Eine Stelle für alle Module (Leitlinie 2); die Module melden nur an.

      Core.OptInHint.Register(id, def) → true    id: eindeutig, z. B. "ezBag.autoSell"; ein zweiter Aufruf ersetzt
          def = {
            owner = "ezBag",                 Modul (Name in der Blase und vor den Meldungen)
            window = "merchant" | "mail" | "map" | "tracker" | "spellbook" | "chat" | "friends" | "macro" | "quest",
                                             an welchem Blizzard-Fenster (Core.OptInHint.WINDOWS)
            label = Text | fn → Text,        Name der Funktion (meist L.OPT_<schalter> des Moduls)
            what = Text | fn → Text,         was sie ohne Klick tut, ein Satz (Text des Moduls, deutsch und englisch)
            isOn = fn → bool,                ist sie an?
            enable = fn → bool,              einschalten (über die Einstellung des Moduls, ns.SetSetting) → jetzt an?
            disable = fn → bool,             frei (Einführung, Werkzeuge/FirstStart.lua): ausschalten; ohne nennt das
                                             Häkchen der Einführung beim Ausschalten den Weg (where)
            applies = fn → bool,             frei: gilt sie gerade? (z. B. nur ohne ezBag, nur am Reparatur-Händler)
            switchedOff = fn → bool,         frei: hat ezCollection sie beim Update ausgeschaltet? (Merker …Was des
                                             Moduls) – dann sagt die Blase das dazu (OPTIN_SWITCHED_OFF)
            where = Text | fn → Text,        frei: Weg zur Einstellung; Standard OPTIN_WHERE mit dem Modulnamen
            target = Rahmen | fn → Rahmen,   frei (Welle 29): worauf der Pfeil der Blase zeigt – ein Knopf des Moduls
                                             im Blizzard-Fenster (Kartenknopf, Reiter „Rotation“, Pfeil am Kopf der
                                             Questverfolgung); nur, wenn er zu sehen ist, sonst das Fenster selbst
            side = "left" | "right" | …,     frei: Lage der Blase zu target (Core.NewHints: above, below, right, left)
          }
      Core.OptInHint.RegisterSetting(owner, mns, key, def) → true    Kurzform für einen Schalter eines Moduls aus dem
          Gerüst (Core.NewModule; Gesamtreview 18.11.2026, T1-3): id "<owner>.<key>", label mns.L.OPT_<key>, what
          mns.L.OPTIN_<key>, isOn mns.S[key] == true, enable über mns.SetSetting(key, true); def wie oben (window Pflicht,
          die übrigen Felder ersetzen die Kurzform)
      Core.OptInHint.Unregister(id)    → true, wenn sie angemeldet war; Core.OptInHint.Entry(id) → def oder nil
      Core.OptInHint.Pending(window)   → Liste der Einträge, die beim Öffnen jetzt in der Blase stünden (aus, gilt,
                                         nicht gesehen, Gesamtschalter an)
      Core.OptInHint.Show(window)      → Blase oder nil. ezCore ruft es selbst kurz nach dem Öffnen des Fensters
                                         (OptInHint.DELAY, damit die Module das Fenster erst einrichten); nichts,
                                         solange eine Seite der Einführung an diesem Fenster steht (sie fragt dort
                                         selbst; Core.Intro.HoldsWindow, Werkzeuge/FirstStart.lua)
      Core.OptInHint.ShowSoon(window)  → true, wenn vorgemerkt: Show(window) nach OptInHint.DELAY – für einen Anlass,
                                         den nur das Modul erkennt (Gegenprüfung P17: ezChat beim „Spieler nicht
                                         gefunden“ nach einem Flüstern, das nur wegen des ausgeschalteten
                                         Nachsendens nicht wartet; dazu kommt kein CHAT_MSG_WHISPER_INFORM)
      Core.OptInHint.Seen(id)          → true, wenn der Hinweis schon kam
      Core.OptInHint.MarkIds(liste)    → Anzahl; nur die Hinweise mit diesen Kennungen gelten als gesehen (die Einführung
                                         merkt so nur, was auf ihrer Seite bzw. in der Liste von „Allem zustimmen“ stand)
      Core.OptInHint.Reset()           → Anzahl gesehener vorher; alle kommen wieder (Knopf „Hinweise erneut zeigen“,
                                         auch Core.ResetAllTours – „Alle Erklärungen erneut zeigen“)
      Core.OptInHint.Enabled()         Gesamtschalter OPT_optInHints (ezCoreDB.optIn.optInHints, ab Werk an)
      Core.OptInHint.AddSettings(page) Kästchen und Knopf unter „Erweitert“ der Seite „ezCollection“ (Page:Advanced
                                         der Elternseite ruft es einmal, Kern/Settings.lua)
    Fenster (OptInHint.WINDOWS): Händler und Briefkasten über ihre Ereignisse (MERCHANT_SHOW/CLOSED, MAIL_SHOW/CLOSED);
    seit Welle 29 (NACH-27) Weltkarte und Zauberbuch über HookScript an OnShow/OnHide von Blizzards Rahmen (hook = true;
    angehängt, sobald es den Rahmen gibt – Blizzard_WorldMap bzw. Blizzard_PlayerSpells laden erst später), die
    Questverfolgung beim Annehmen einer Quest (QUEST_ACCEPTED; sie ist immer offen, ein Öffnen gibt es nicht). Seit dem
    Gesamtreview vom 18.11.2026 (T1-3; Entscheidung 2 des Nutzers: Hinweis auch für Abläufe, die nie ab Werk an waren,
    sofern sie senden oder Blizzards Zustände umstellen) dazu das Chatfenster (Reiterleiste GeneralDockManager) beim
    Flüstern an andere (CHAT_MSG_WHISPER_INFORM; auch das Chatfenster ist immer offen – nur das Ereignis wird gehört,
    sein Inhalt nie gelesen), Blizzards Freundesliste und Makroverwaltung über OnShow/OnHide (hook = true;
    Blizzard_MacroUI lädt erst beim Öffnen); nach der Gegenprüfung des Pakets P17 auch Blizzards Questfenster
    (QuestFrame über OnShow/OnHide; ezQuest: automatisch annehmen und abgeben). Die Blase
    hängt am Blizzard-Fenster (Elternrahmen) und zeigt auf target des ersten Eintrags, dessen Knopf zu sehen ist.
    Gemerkt in ezCoreDB.optInSeen[id] = true (je Account), sobald die Blase OptInHint.MIN_SEEN Sekunden zu sehen war
    oder der Spieler „Verstanden“, das X oder ein „Einschalten“ darin klickt (dann jede Funktion der Blase; Fund des
    code-reviewers zu Welle 28: vorher schon beim Erscheinen). Schließt das Fenster vorher oder beginnt ein Kampf, kommt der Hinweis beim nächsten Öffnen wieder –
    der Spieler muss ihn gesehen haben (Grundsatz „user muss auf sowas hingewiesen werden“).

    Optik und Taint (Leitlinien 1 und 5): Blizzards HelpTip (Blizzard_SharedXML/HelpTip.lua, Zweig forever von
    Gethe/wow-ui-source) holt seine Rahmen aus EINEM gemeinsamen Pool (HelpTip.framePool, CreateFramePool mit
    Blizzards Vorlage der Hinweise) und schreibt Felder hinein (frame.info …). Ruft ein Addon HelpTip:Show, entstehen
    Rahmen dieses Pools aus Addon-Code, die Blizzard später für eigene Hinweise wiederverwendet – nicht taint-sicher.
    Darum die
    Erklärblase von ezCore (Core.NewHints, Bausteine/Widgets.lua): Blizzards Vorlagen GlowBoxTemplate und
    GlowBoxArrowTemplate in den Maßen von HelpTip.xml, eigene Rahmen, nur an Blizzards Fenster gehängt. Nie im Kampf:
    im Kampf erscheint keine Blase (sie kommt beim nächsten Öffnen, nichts wird gemerkt), beim Kampfbeginn verschwindet
    eine offene. Ein Klick auf „Einschalten“ im Kampf schaltet nichts (Meldung über Core.CombatNotice mit OPTIN_WHAT).
]]

local OptIn = {}
Core.OptInHint = OptIn

-- open/close: Ereignisse; hook = true: HookScript an OnShow/OnHide des Rahmens frame; side: Lage der Blase zum Fenster
-- bzw. zum Knopf des Moduls (target), wenn der Eintrag keine eigene nennt.
OptIn.WINDOWS = {
    merchant = { open = "MERCHANT_SHOW", close = "MERCHANT_CLOSED", frame = "MerchantFrame" },
    mail = { open = "MAIL_SHOW", close = "MAIL_CLOSED", frame = "MailFrame" },
    -- Welle 29 (NACH-27): Weltkarte (ezMap: Zielverfolgung, Such-Zauber; Pfeil auf ezMaps Kartenknopf oben rechts,
    -- darum links davon über der Kartenfläche), Questverfolgung (ezQuest; rechts am Bildschirm, darum links davon),
    -- Zauberbuch (ezCombat: Reiter „Rotation“ an der rechten Kante)
    map = { frame = "WorldMapFrame", hook = true, side = "left" },
    tracker = { open = "QUEST_ACCEPTED", frame = "ObjectiveTrackerFrame", side = "left" },
    spellbook = { frame = "PlayerSpellsFrame", hook = true, side = "right" },
    -- Gesamtreview 18.11.2026 (T1-3): Chatfenster (ezChat: Nachsenden, automatische Antwort – beim Flüstern an andere),
    -- Freundesliste (ezChat: „tippt …“ und Ort im angedockten Gesprächsfenster; ezSocial: Beschwörung, Wiederbelebung,
    -- Duelle und Einladungen), Makroverwaltung (ezMacro: Danken und Spucken)
    -- Chat: Blizzards Reiterleiste der angedockten Chatfenster (GeneralDockManager) – sie ist zu sehen, auch wenn ein
    -- anderer Reiter als das Hauptfenster gewählt ist (dann ist ChatFrame1 verborgen)
    chat = { open = "CHAT_MSG_WHISPER_INFORM", frame = "GeneralDockManager", side = "right" },
    friends = { frame = "FriendsFrame", hook = true, side = "right" },
    macro = { frame = "MacroFrame", hook = true, side = "right" },
    -- Gegenprüfung P17 (zu T1-3): Questfenster (ezQuest: annehmen und abgeben ohne Klick; Pfeil auf ezQuests Häkchen
    -- „Automatisch“ oben rechts im Fenster)
    quest = { frame = "QuestFrame", hook = true, side = "right" },
}
OptIn.DELAY = 0.3          -- Sekunden nach dem Öffnen des Fensters
OptIn.MIN_SEEN = 3         -- so lange muss die Blase zu sehen sein, bis der Hinweis als gesehen gilt (ohne Klick)
OptIn.SIDE = "right"       -- Lage der Blase zum Fenster (Core.NewHints: above, below, right, left)
OptIn.WIDTH = 300          -- breiter als Blizzards 226: je Funktion eine Zeile mit Knopf
OptIn.TEXT_WIDTH = 270
OptIn.BUTTON_WIDTH, OptIn.BUTTON_HEIGHT = 120, 22

Core.OwnDefaults("optIn", { optInHints = true })

local entries, order = {}, {}

local function L() return Core.L end

-- Wert oder Ergebnis einer Funktion des Moduls (Fehler landen in der Fehlerliste des Moduls). → Wert oder default
local function Ask(def, field, default)
    local value = def[field]
    if type(value) ~= "function" then
        if value == nil then return default end
        return value
    end
    local ok, result = Core.Try(def.owner, "OptInHint." .. field, value)
    if not ok then return default end
    return result
end

local function Text(def, field)
    local value = Ask(def, field, nil)
    return type(value) == "string" and value or nil
end

function OptIn.Register(id, def)
    if type(id) ~= "string" or id == "" or type(def) ~= "table" then return false end
    if not OptIn.WINDOWS[def.window] or type(def.isOn) ~= "function" or type(def.enable) ~= "function" then return false end
    if not entries[id] then order[#order + 1] = id end
    def.id = id
    def.owner = def.owner or Core.name
    entries[id] = def
    return true
end

-- Kurzform für einen Schalter eines Moduls aus dem Gerüst (Core.NewModule setzt mns.L, mns.S und mns.SetSetting):
-- Name, Satz, „an?“ und „Einschalten“ folgen dem Schlüssel; def ergänzt bzw. ersetzt (window Pflicht). → true/false
function OptIn.RegisterSetting(owner, mns, key, def)
    if type(owner) ~= "string" or type(mns) ~= "table" or type(key) ~= "string" or type(def) ~= "table" then return false end
    local entry = { owner = owner }
    entry.label = function() return mns.L and mns.L["OPT_" .. key] end
    entry.what = function() return mns.L and mns.L["OPTIN_" .. key] end
    entry.isOn = function() return type(mns.S) == "table" and mns.S[key] == true end
    entry.enable = function()
        if type(mns.SetSetting) ~= "function" or type(mns.S) ~= "table" then return false end
        mns.SetSetting(key, true)
        return mns.S[key] == true
    end
    for field, value in pairs(def) do entry[field] = value end
    return OptIn.Register(owner .. "." .. key, entry)
end

-- Eingetragene Funktion (für Prüfungen und Diagnose). → def oder nil
function OptIn.Entry(id) return entries[id] end

-- Funktion abmelden (ein Modul zieht den Hinweis zurück; Prüfungen räumen auf). → true, wenn sie angemeldet war
function OptIn.Unregister(id)
    if not entries[id] then return false end
    entries[id] = nil
    for i = #order, 1, -1 do
        if order[i] == id then table.remove(order, i) end
    end
    return true
end

local function SeenStore()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.optInSeen) ~= "table" then db.optInSeen = {} end
    return db.optInSeen
end

function OptIn.Seen(id)
    local seen = SeenStore()
    return seen ~= nil and seen[id] == true
end

function OptIn.Enabled()
    return Core.OwnSetting("optIn", "optInHints") ~= false
end

function OptIn.Reset()
    local seen = SeenStore()
    if not seen then return 0 end
    local n = 0
    for _, value in pairs(seen) do if value == true then n = n + 1 end end
    wipe(seen)
    return n
end

-- Nur diese Hinweise als gesehen merken (Einführung, Nachlauf zum Review von PR 536: nur die Hinweise, deren Schalter
-- auf der Seite bzw. in der Liste von „Allem zustimmen“ wirklich stand – vorher alle des Moduls, auch z. B. ezBags
-- „Plunder verkaufen“, dessen Zeile auf ezCores Startseite steht). ids = Liste von Kennungen; unbekannte zählen nicht.
-- → Anzahl neu als gesehen gemerkter Hinweise
function OptIn.MarkIds(ids)
    local seen = SeenStore()
    if not seen or type(ids) ~= "table" then return 0 end
    local n = 0
    for _, id in ipairs(ids) do
        if entries[id] and seen[id] ~= true then
            seen[id] = true
            n = n + 1
        end
    end
    return n
end

function OptIn.Pending(window)
    local list = {}
    local seen = SeenStore()
    if not seen or not OptIn.Enabled() then return list end
    for _, id in ipairs(order) do
        local def = entries[id]
        if def.window == window and seen[id] ~= true and Ask(def, "isOn", true) ~= true
            and Ask(def, "applies", true) ~= false then
            list[#list + 1] = def
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Blase
---------------------------------------------------------------------------

local hints                  -- Core.NewHints, beim ersten Zeigen angelegt (Bausteine/Widgets.lua lädt nach Kern/)
local boxSeen = {}           -- Merker der Blase selbst: gemerkt wird je Funktion (optInSeen), nicht je Fenster

-- Der Satz Erklärblasen des Helfers steht nicht in Core.hintSets: „Alle Erklärungen erneut zeigen“
-- (Core.ResetAllTours, Werkzeuge/FirstStart.lua) setzt die Hinweise über OptIn.Reset zurück – boxSeen ist nur der
-- Merker der Blase selbst und wird bei jedem Zeigen geleert (Fund des code-reviewers zu Welle 28).
local function Hints()
    if not hints and type(Core.NewHints) == "function" then
        hints = Core.NewHints(function() return boxSeen end, L().OPTIN_OK)
        local sets = Core.hintSets
        for i = #(sets or {}), 1, -1 do
            if sets[i] == hints then table.remove(sets, i) end
        end
    end
    return hints
end

local function BoxKey(window) return "optin:" .. tostring(window) end

-- Hinweise als gesehen merken (je Funktion, je Account).
local function Mark(list)
    local seen = SeenStore()
    if not seen then return end
    for _, def in ipairs(list or {}) do
        if def.id then seen[def.id] = true end
    end
end

-- Zeilentext einer Funktion: Name (Gold, mit Modul), was sie tut, ob ezCollection sie umgestellt hat, Weg (grau).
function OptIn.RowText(def)
    local label = Text(def, "label") or def.id
    local parts = { Core.Gold(label) .. " (" .. tostring(def.owner) .. ")" }
    local what = Text(def, "what")
    if what then parts[#parts + 1] = what end
    if Ask(def, "switchedOff", false) == true then parts[#parts + 1] = L().OPTIN_SWITCHED_OFF end
    parts[#parts + 1] = Core.Grey(Text(def, "where") or L().OPTIN_WHERE:format(tostring(def.owner)))
    return table.concat(parts, " ")
end

local function Switch(row)
    local def = row.def
    if not def then return false end
    if Core.InCombat() then
        Core.CombatNotice(def.owner, L().OPTIN_WHAT)
        return false
    end
    -- ein Klick in der Blase: der Hinweis hat den Spieler erreicht – alle Funktionen darin gelten als gesehen
    local box = row.GetParent and row:GetParent()
    Mark(type(box) == "table" and box.optInList or { def })
    local ok, on = Core.Try(def.owner, "OptInHint.enable", def.enable)
    if not (ok and on == true) then return false end
    row.Button:SetText(L().OPTIN_ENABLED)
    row.Button:Disable()
    Core.Print(def.owner, L().OPTIN_DONE:format(Text(def, "label") or def.id,
        Text(def, "where") or L().OPTIN_WHERE:format(tostring(def.owner))))
    return true
end
OptIn.Switch = Switch

local function NewRow(box)
    local row = CreateFrame("Frame", nil, box)
    row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallLeft")
    row.Text:SetWidth(OptIn.TEXT_WIDTH)
    row.Text:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.Text:SetJustifyH("LEFT")
    row.Button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Button:SetSize(OptIn.BUTTON_WIDTH, OptIn.BUTTON_HEIGHT)
    row.Button:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    row.Button:SetScript("OnClick", function() Switch(row) end)
    return row
end

local function Height(fontString, fallback)
    local h = fontString and fontString.GetStringHeight and fontString:GetStringHeight()
    return (type(h) == "number" and h > 0) and h or fallback
end

-- Worauf der Pfeil zeigt: target des ersten Eintrags, dessen Knopf zu sehen ist, sonst das Fenster.
-- → Rahmen, Lage der Blase
function OptIn.Anchor(window, frame, list)
    local w = OptIn.WINDOWS[window] or {}
    for _, def in ipairs(list or {}) do
        local target = Ask(def, "target", nil)
        if type(target) == "table" and type(target.IsVisible) == "function" and target:IsVisible() then
            return target, def.side or w.side or OptIn.SIDE
        end
    end
    return frame, w.side or OptIn.SIDE
end

-- „Verstanden“ und das X (Core.NewHints) merken die Blase nur für sich; hier zusätzlich jede Funktion darin.
local function HookAcknowledge(box)
    if box.optInHooked then return end
    box.optInHooked = true
    local function Done()
        box.optInToken = (box.optInToken or 0) + 1
        Mark(box.optInList)
    end
    for _, button in ipairs({ box.OkayButton, box.CloseButton }) do
        if type(button) == "table" and button.HookScript then button:HookScript("OnClick", Done) end
    end
end

local function Build(window, frame, list)
    local H = Hints()
    if not H then return nil end
    local key = BoxKey(window)
    boxSeen[key] = nil
    local target, side = OptIn.Anchor(window, frame, list)
    local box = H.Show(key, frame, target, L().OPTIN_HEAD, side)
    if not box then return nil end
    if box.SetClampedToScreen then box:SetClampedToScreen(true) end     -- Vollbild-Karte: nichts ragt hinaus
    HookAcknowledge(box)
    box:SetWidth(OptIn.WIDTH)
    box.Text:SetWidth(OptIn.TEXT_WIDTH)
    box.optInRows = box.optInRows or {}
    for _, row in ipairs(box.optInRows) do
        row:Hide()
        row.def = nil
    end
    local anchor, height = box.Text, 15 + Height(box.Text, 28)
    for i, def in ipairs(list) do
        local row = box.optInRows[i]
        if not row then
            row = NewRow(box)
            box.optInRows[i] = row
        end
        row.def = def
        row.Text:SetText(OptIn.RowText(def))
        row.Button:SetText(L().OPTIN_ENABLE)
        row.Button:Enable()
        local h = Height(row.Text, 28) + 4 + OptIn.BUTTON_HEIGHT
        row:SetSize(OptIn.TEXT_WIDTH, h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        row:Show()
        anchor, height = row, height + 8 + h
    end
    if not box.optInFoot then
        box.optInFoot = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmallLeft")
        box.optInFoot:SetWidth(OptIn.TEXT_WIDTH)
        box.optInFoot:SetJustifyH("LEFT")
    end
    box.optInFoot:SetText(L().OPTIN_FOOT)
    box.optInFoot:ClearAllPoints()
    box.optInFoot:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    box.optInFoot:Show()
    height = height + 8 + Height(box.optInFoot, 24) + 10 + 22 + 12
    box:SetHeight(height)
    box.optInWindow = window
    box.optInTarget = target
    return box
end

-- Offene Blase eines Fensters (für Prüfungen). → Blase oder nil
function OptIn.Box(window)
    local box = hints and hints.Box(BoxKey(window))
    if box and box.IsShown and box:IsShown() then return box end
    return nil
end

-- Blase weg (Fenster zu, Kampfbeginn): war sie noch keine OptInHint.MIN_SEEN Sekunden zu sehen, gilt nichts als
-- gesehen – der Hinweis kommt beim nächsten Öffnen wieder.
function OptIn.Hide(window)
    local box = hints and hints.Box(BoxKey(window))
    if box then box.optInToken = (box.optInToken or 0) + 1 end
    if hints then hints.Hide(BoxKey(window)) end
end

function OptIn.Show(window)
    local w = OptIn.WINDOWS[window]
    if not w or Core.InCombat() then return nil end
    local frame = rawget(_G, w.frame)
    if type(frame) ~= "table" or not (frame.IsShown and frame:IsShown()) then return nil end
    -- Steht dort gerade eine Seite der Einführung, fragt sie das Einverständnis selbst ab: keine zweite Blase mit
    -- derselben Frage darüber (Gegenprüfung zum Spieltest 19.11.2026); nichts gilt dadurch als gesehen
    local intro = Core.Intro
    if type(intro) == "table" and type(intro.HoldsWindow) == "function" and intro.HoldsWindow(frame) then return nil end
    local list = OptIn.Pending(window)
    if #list == 0 then return nil end
    local box = Build(window, frame, list)
    if not box then return nil end
    box.optInList = list
    box.optInToken = (box.optInToken or 0) + 1
    local token = box.optInToken
    if C_Timer and C_Timer.After then
        C_Timer.After(OptIn.MIN_SEEN, function()
            if box.optInToken == token and box:IsVisible() then Mark(box.optInList) end
        end)
    end
    return box
end

local function ShowSoon(window)
    if not OptIn.WINDOWS[window] or not (C_Timer and C_Timer.After) then return false end
    C_Timer.After(OptIn.DELAY, function() Core.Try(Core.name, "OptInHint.Show", OptIn.Show, window) end)
    return true
end
OptIn.ShowSoon = ShowSoon

-- Fenster ohne Ereignis (hook = true): an OnShow/OnHide von Blizzards Rahmen hängen, sobald es ihn gibt – nur
-- HookScript (Leitlinie 5), je Rahmen einmal. Weltkarte und Zauberbuch entstehen erst mit ihren Blizzard-Addons, darum
-- auch bei jedem ADDON_LOADED nachsehen. → Anzahl neu angehängter Fenster
local hooked = {}           -- [Fenster] = Rahmen, an dem ezCore hängt
function OptIn.HookWindows()
    local n = 0
    for window, w in pairs(OptIn.WINDOWS) do
        local frame = w.hook and rawget(_G, w.frame) or nil
        if type(frame) == "table" and hooked[window] ~= frame and type(frame.HookScript) == "function" then
            hooked[window] = frame
            frame:HookScript("OnShow", function() ShowSoon(window) end)
            frame:HookScript("OnHide", function() OptIn.Hide(window) end)
            n = n + 1
        end
    end
    return n
end
function OptIn.Hooked(window) return hooked[window] end

for window, w in pairs(OptIn.WINDOWS) do
    if w.open then ns.On(w.open, function() ShowSoon(window) end) end
    -- Die Blase hängt am Fenster und bliebe sonst beim nächsten Öffnen mit sichtbar.
    if w.close then ns.On(w.close, function() OptIn.Hide(window) end) end
end
OptIn.HookWindows()
ns.On("ADDON_LOADED", function() OptIn.HookWindows() end)
ns.On("PLAYER_LOGIN", function() OptIn.HookWindows() end)

ns.On("PLAYER_REGEN_DISABLED", function()
    for window in pairs(OptIn.WINDOWS) do OptIn.Hide(window) end
end)

---------------------------------------------------------------------------
-- Einstellungen (Seite „ezCollection“ » „Erweitert“)
---------------------------------------------------------------------------

-- Einstellungs-Prüfung 19.11.2026 (Nr. 53–55): Der Schalter heißt „Hinweise und Angebote zeigen“ und gilt für alle
-- einmaligen Hinweise von ezCore – diese Hinweise auf Abläufe ohne Klick, den Hinweis „Mithelfen“ (Contribute.lua) und
-- das Angebot der Einführung (FirstStart.lua); deren eigene Kästchen sind weg, beide Blasen haben einen Knopf „Nicht
-- mehr zeigen“ bzw. „Nicht mehr anbieten“. Der frühere Knopf „Hinweise erneut zeigen“ ging im Knopf „Alle Hinweise und
-- Erklärblasen erneut zeigen“ auf (Core.ResetAllTours setzt auch diese Hinweise zurück; Collection.lua).
function OptIn.AddSettings(page)
    if type(page) ~= "table" or type(page.OwnCheckbox) ~= "function" then return false end
    page:OwnCheckbox("optIn", "optInHints")
    return true
end
