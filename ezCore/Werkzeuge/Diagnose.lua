local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Diagnose (Ideen aus der Vollprüfung 13.11.2026): zwei Werkzeuge für Fehlermeldungen, beide mit Knopf auf der
    Seite „ezCollection“ → „Erweitert“ (Leitlinie 3) und als Befehl.

    Mitschnitt – /ez debug (Core.Debug)
      Schneidet mit, welche Ereignisse und Nachrichten durch ezCore laufen und wie lange jeder Zuhörer braucht
      (debugprofilestop, Millisekunden). Gemessen wird im Verteiler von Core.lua (Core.SetProbe); ohne laufenden
      Mitschnitt kostet das nichts. Werte der Ereignisse werden nie gemerkt (sie können gesperrt sein) – nur Name,
      Besitzer, Anzahl und Zeit.
        Debug.Start(sekunden) → true | false (läuft schon)     endet von selbst nach Debug.MAX_SECONDS (300)
        Debug.Stop()          → true | false (lief nicht)
        Debug.Toggle()        → "started" | "stopped" (Knopf und Befehl: stoppt und zeigt den Bericht; Knopf
                                „Bericht zeigen“ ruft Debug.Show, ohne neu zu starten)
        Debug.Running()       → läuft?, Sekunden seit dem Start
        Debug.Stats()         → { { kind = "event" | "message" | "fire", name, owner, n, ms, max } … } teuerste zuerst
        Debug.Log()           → die letzten Debug.MAX_LOG Aufrufe { t, kind, name, owner, ms }, älteste zuerst
        Debug.Lines(), Debug.Text()   Bericht zum Kopieren      Debug.Show() → zeigt ihn (Core.TextDialog)
        Debug.AddLine(key, fn, owner) Erweiterungspunkt (Welle 23a, A65): fn() → Text oder Liste von Texten, steht
                                im Bericht gleich nach dem Kopf (und der Zeile „läuft noch“), in der Reihenfolge der
                                Anmeldung; derselbe key ersetzt, fn = nil streicht. Fehler in fn brechen den Bericht
                                nicht ab (Zeile „key: Fehler“). Statt einer Hülle um Debug.Lines.
        Debug.Developer(), Debug.SetDeveloper(an)   Entwicklerschalter (comfort.developer, ab Werk aus; Schalter
                                „Entwicklerwerkzeuge“ unter „Erweitert“, /ez debug entwickler): nur mit ihm laufen die
                                Sonderproben der Daten-Probe und wirkt der Testschalter comfort.editModeOpen.

    Selbsttest – /ez test (Core.SelfTest)
      Prüft, ob die Blizzard-Vorlagen, Atlanten und APIs, die ezCore nutzt, in diesem Client da sind
      (Core.SELFTEST). Was einen Rückfall hat, zählt als „fehlt (Rückfall vorhanden)“. Das Ergebnis steht danach
      in der Fehlerliste zum Kopieren (Core.ErrorListText).
        Core.SelfTest()       → { t, checked, ok, missing = { { kind, name, optional } … }, required }
        Core.SelfTestLines()  → Zeilen des letzten Ergebnisses (nil, solange keiner lief)
        Core.RunSelfTest()    → Ergebnis; prüft (im Kampf erst danach), meldet im Chat und zeigt die Fehlerliste
      Nichts wird verändert: Vorlagen über C_XMLUtil.GetTemplateInfo, sonst ein unsichtbarer Probe-Rahmen unter
      einem versteckten Elternrahmen.
]]

---------------------------------------------------------------------------
-- Mitschnitt
---------------------------------------------------------------------------

local Debug = {}
Core.Debug = Debug
Debug.MAX_LOG = 400
Debug.MAX_SECONDS = 300

local running, token, recorded = false, 0, false
local startedAt, stoppedAt = 0, 0
local stats, log, logCount, calls = {}, {}, 0, 0

local Clock = Core.Uptime

local function Probe(kind, name, owner, ms)
    if not running then return end
    name, owner = tostring(name), owner ~= nil and tostring(owner) or ""
    calls = calls + 1
    local key = kind .. "\031" .. name .. "\031" .. owner
    local s = stats[key]
    if not s then
        s = { kind = kind, name = name, owner = owner, n = 0, ms = 0, max = 0 }
        stats[key] = s
    end
    s.n = s.n + 1
    if type(ms) == "number" then
        s.ms = s.ms + ms
        if ms > s.max then s.max = ms end
    end
    logCount = logCount + 1
    log[(logCount - 1) % Debug.MAX_LOG + 1] = { t = Clock() - startedAt, kind = kind, name = name, owner = owner, ms = ms }
end

function Debug.Running()
    return running, running and (Clock() - startedAt) or (stoppedAt - startedAt)
end

function Debug.Start(seconds)
    if running then return false end
    running, token, recorded = true, token + 1, true
    startedAt, stoppedAt = Clock(), 0
    stats, log, logCount, calls = {}, {}, 0, 0
    Core.SetProbe(Probe)
    local mine = token
    local limit = math.min(Core.Num(seconds) or Debug.MAX_SECONDS, Debug.MAX_SECONDS)
    if limit <= 0 then limit = Debug.MAX_SECONDS end
    C_Timer.After(limit, function()
        if running and token == mine then
            Debug.Stop()
            ns.Print(L.DEBUG_AUTOSTOP:format(math.floor(limit + 0.5)))
        end
    end)
    return true
end

function Debug.Stop()
    if not running then return false end
    running = false
    stoppedAt = Clock()
    Core.SetProbe(nil)
    return true
end

function Debug.Stats()
    local list = {}
    for _, s in pairs(stats) do
        list[#list + 1] = { kind = s.kind, name = s.name, owner = s.owner, n = s.n, ms = s.ms, max = s.max }
    end
    table.sort(list, function(a, b)
        if a.ms ~= b.ms then return a.ms > b.ms end
        if a.n ~= b.n then return a.n > b.n end
        if a.name ~= b.name then return a.name < b.name end
        return a.owner < b.owner
    end)
    return list
end

function Debug.Log()
    local list = {}
    local first = math.max(1, logCount - Debug.MAX_LOG + 1)
    for i = first, logCount do
        local entry = log[(i - 1) % Debug.MAX_LOG + 1]
        if entry then list[#list + 1] = entry end
    end
    return list
end

function Debug.Calls() return calls end

-- Gab es in dieser Sitzung schon einen Mitschnitt (laufend oder beendet)? Spieltest 19.11.2026 (Wortlaut des Nutzers:
-- „ezCollection 1.15.0 – Mitschnitt über 0.0 Sekunden, 0 Aufrufe / Nichts mitgeschnitten.“): Der Knopf „Bericht
-- zeigen“ bzw. „/ez debug zeigen“ zeigte vor jedem Start einen leeren Bericht über 0,0 Sekunden – als sei ein
-- Mitschnitt gelaufen und habe nichts gefunden. Ohne Mitschnitt sagen Bericht und Chat jetzt, wie man startet
-- (L.DEBUG_NONE_HEAD, L.DEBUG_NONE_HOW).
function Debug.Recorded() return recorded end

local KIND_TEXT = { event = "DEBUG_KIND_event", message = "DEBUG_KIND_message", fire = "DEBUG_KIND_fire" }

-- Zusatzzeilen der Module (Debug.AddLine): Liste { key, fn, owner } in der Reihenfolge der Anmeldung.
local extraLines = {}

function Debug.AddLine(key, fn, owner)
    if type(key) ~= "string" or key == "" then return false end
    for i, entry in ipairs(extraLines) do
        if entry.key == key then
            if type(fn) == "function" then
                entry.fn, entry.owner = fn, owner
            else
                table.remove(extraLines, i)
            end
            return true
        end
    end
    if type(fn) ~= "function" then return false end
    extraLines[#extraLines + 1] = { key = key, fn = fn, owner = owner }
    return true
end

local function AppendExtra(lines)
    for _, entry in ipairs(extraLines) do
        local ok, out = pcall(entry.fn)
        if not ok then
            lines[#lines + 1] = entry.key .. ": " .. (L.DEBUG_LINE_FAILED or "error")
        elseif type(out) == "string" then
            lines[#lines + 1] = out
        elseif type(out) == "table" then
            for _, text in ipairs(out) do
                if type(text) == "string" then lines[#lines + 1] = text end
            end
        end
    end
end

function Debug.Lines(maxStats, maxLog)
    maxStats, maxLog = maxStats or 40, maxLog or 60
    if not recorded then
        return { L.DEBUG_NONE_HEAD:format(Core.Version and Core.Version(ADDON) or "?"), L.DEBUG_NONE_HOW }
    end
    local _, seconds = Debug.Running()
    local lines = { L.DEBUG_HEAD:format(Core.Version and Core.Version(ADDON) or "?", seconds or 0, calls) }
    if running then lines[#lines + 1] = L.DEBUG_RUNNING end
    AppendExtra(lines)
    local list = Debug.Stats()
    if #list == 0 then
        lines[#lines + 1] = L.DEBUG_EMPTY
        return lines
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L.DEBUG_STATS_HEAD
    local shown = 0
    for _, s in ipairs(list) do
        if s.kind ~= "fire" then
            shown = shown + 1
            if shown > maxStats then break end
            lines[#lines + 1] = ("%9.2f  %6d  %8.2f  %s  %s  %s"):format(s.ms, s.n, s.max, L[KIND_TEXT[s.kind]] or s.kind, s.name, s.owner)
        end
    end
    local fired = {}
    for _, s in ipairs(list) do
        if s.kind == "fire" then fired[#fired + 1] = s end
    end
    if #fired > 0 then
        table.sort(fired, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.name < b.name
        end)
        local parts = {}
        for _, s in ipairs(fired) do parts[#parts + 1] = s.name .. " ×" .. s.n end
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.DEBUG_FIRED:format(table.concat(parts, ", "))
    end
    local entries = Debug.Log()
    if #entries > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.DEBUG_LOG_HEAD:format(math.min(#entries, maxLog))
        for i = math.max(1, #entries - maxLog + 1), #entries do
            local e = entries[i]
            lines[#lines + 1] = ("%11s  %s  %s  %s%s"):format(Core.Seconds(e.t, 2), L[KIND_TEXT[e.kind]] or e.kind, e.name, e.owner,
                type(e.ms) == "number" and ("  %.2f ms"):format(e.ms) or "")
        end
    end
    return lines
end

function Debug.Text()
    return table.concat(Debug.Lines(), "\n")
end

function Debug.Show()
    if not recorded then ns.Print(L.DEBUG_NONE_HOW) end
    return Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.DEBUG_TITLE, hint = L.DEBUG_HINT, text = Debug.Text(), readOnly = true, select = true,
        maxLetters = 0, owner = ADDON })
end

-- Knopf und „/ez debug“: starten bzw. stoppen und den Bericht zeigen.
function Debug.Toggle()
    if running then
        Debug.Stop()
        ns.Print(L.DEBUG_STOPPED:format(calls))
        Debug.Show()
        return "stopped"
    end
    Debug.Start()
    ns.Print(L.DEBUG_STARTED:format(Debug.MAX_SECONDS))
    return "started"
end

---------------------------------------------------------------------------
-- Entwicklerschalter (Gesamtreview 18.11.2026, Entscheidung 1, Funde T1-5/T11-4/T2-7): Werkzeuge mit Nebenwirkung,
-- die nur Entwickler und Helfer brauchen – die Sonderproben der Daten-Probe (X2 bis X8, F7: Komplett-Scan, Wegpunkt,
-- Rezept-Filter, Betrachten, Sammelabfrage, Menge im Warenkauf, Minikarten-Zoom) und der Testschalter
-- comfort.editModeOpen – wirken nur, solange er an ist. Ab Werk aus; an über den Schalter „Entwicklerwerkzeuge“
-- unter „Erweitert“ (Leitlinie 3) oder „/ez debug entwickler“. Die Automatik der Daten-Probe hängt nicht daran.
--   Debug.Developer()        → true | false
--   Debug.SetDeveloper(an)   → neuer Zustand (false, solange ezCoreDB noch nicht geladen ist); setzt über das
--                              Kästchen (Core.ApplyOwnSetting), damit offene Einstellungen und die Zeilen, die an ihm
--                              hängen, sofort nachziehen
-- „Alles sichern/übernehmen“ nimmt den Schalter nicht mit (Core.OwnExportSkip; Gegenprüfung zum Gesamtreview, P6).
---------------------------------------------------------------------------

Core.OwnDefaults("comfort", { developer = false })
Core.OwnExportSkip("comfort", { developer = true })

function Debug.Developer()
    return Core.OwnSetting("comfort", "developer") == true
end

function Debug.SetDeveloper(on)
    local tbl = Core.OwnSettings("comfort")
    if type(tbl) ~= "table" then return false end
    Core.ApplyOwnSetting("comfort", "developer", on == true)
    return tbl.developer == true
end

-- Zeilen unter „Erweitert“ (Collection.lua): der Entwicklerschalter, darunter der Testschalter comfort.editModeOpen
-- (Mover.lua) – der nur zu sehen ist, solange der Entwicklerschalter an ist (opts.shown von page:OwnCheckbox; Blizzards
-- Liste wertet die Bedingung nach jedem Umschalten neu aus). → Zeile des Entwicklerschalters, Zeile des Testschalters
-- (je nil ohne Client-Unterstützung)
function Debug.AddDeveloperRows(page)
    if type(page) ~= "table" or type(page.OwnCheckbox) ~= "function" then return nil end
    local _, devRow = page:OwnCheckbox("comfort", "developer")
    local testRow
    if Core.Mover and Core.Mover.Open then
        _, testRow = page:OwnCheckbox("comfort", "editModeOpen", { shown = Debug.Developer })
    end
    return devRow, testRow
end

-- „/ez debug entwickler [an|aus]“: ohne Zusatz umschalten; meldet den neuen Zustand
local function DeveloperCommand(more)
    local word = Core.Trim(more or ""):lower()
    local on
    if word == "an" or word == "on" then on = true
    elseif word == "aus" or word == "off" then on = false
    else on = not Debug.Developer() end
    if Core.OwnSettings("comfort") == nil then return false end
    on = Debug.SetDeveloper(on)
    ns.Print(on and L.DEBUG_DEV_ON or L.DEBUG_DEV_OFF)
    return on
end

-- „/ez debug [an|aus|zeigen|entwickler [an|aus]]“
function Debug.Command(rest)
    local word, more = Core.Trim(rest or ""):lower():match("^(%S*)%s*(.-)$")
    if word == "entwickler" or word == "developer" or word == "dev" then
        DeveloperCommand(more)
    elseif word == "an" or word == "on" or word == "start" then
        if Debug.Start() then ns.Print(L.DEBUG_STARTED:format(Debug.MAX_SECONDS)) else ns.Print(L.DEBUG_RUNNING) end
    elseif word == "aus" or word == "off" or word == "stop" then
        if Debug.Stop() then ns.Print(L.DEBUG_STOPPED:format(calls)) else ns.Print(L.DEBUG_NOT_RUNNING) end
    elseif word == "zeigen" or word == "show" then
        Debug.Show()
    else
        Debug.Toggle()
    end
end

---------------------------------------------------------------------------
-- Selbsttest
---------------------------------------------------------------------------

-- Was ezCore vom Client braucht. optional = true: ezCore hat einen Rückfall (meist pcall und eine zweite Vorlage).
-- Beim Einbau einer neuen Vorlage, eines Atlas oder einer API hier eintragen.
Core.SELFTEST = {
    templates = {
        { "Button", "UIPanelButtonTemplate" },
        { "Button", "UIPanelCloseButton" },
        { "ScrollFrame", "UIPanelScrollFrameTemplate" },
        { "Frame", "TooltipBackdropTemplate" },
        { "EditBox", "SearchBoxTemplate" },
        { "Frame", "PortraitFrameFlatTemplate", optional = true },
        { "Frame", "ButtonFrameTemplate", optional = true },
        { "ScrollFrame", "ScrollFrameTemplate", optional = true },
        { "CheckButton", "UICheckButtonTemplate", optional = true },
        { "CheckButton", "RightSideTabTemplate", optional = true },
        { "Frame", "GlowBoxTemplate", optional = true },
        { "Frame", "GlowBoxArrowTemplate", optional = true },
        { "Frame", "InsetFrameTemplate", optional = true },     -- Seitenteil mit Pfeil (Core.NewSidePanel); sonst ein leerer Rahmen
        { "Frame", "ActionButtonSpellAlertTemplate", optional = true },
        { "Frame", "BackdropTemplate", optional = true },
        { "Button", "SecureActionButtonTemplate" },
        { "Frame", "NineSliceCodeTemplate", optional = true },
        { "Frame", "PagingControlsHorizontalTemplate", optional = true },
        { "Frame", "SpellBookHeaderTemplate", optional = true },
        { "AuraContainer", "CustomAuraContainerTemplate", optional = true },
        { "Frame", "DisableUntrustedLayoutScriptsTemplate", optional = true },
        { "Cooldown", "CooldownFrameTemplate", optional = true },   -- Spirale der AuraRow-Vorlage (sonst ohne)
        { "DropdownButton", "WowStyle1DropdownTemplate", optional = true },   -- Core.Menu.Dropdown (sonst Knopf mit Menü)
    },
    atlases = {
        { "common-icon-yellowx", optional = true }, { "common-icon-yellowx-down", optional = true },
        { "chatframe-button-up", optional = true }, { "communities-icon-notification", optional = true },
        { "UI-HUD-ActionBar-IconFrame-Mouseover", optional = true }, { "UI-HUD-ActionBar-IconFrame-Flash", optional = true },
        { "spellbook-divider", optional = true }, { "spellbook-item-backplate", optional = true },
        { "spellbook-item-iconframe", optional = true }, { "spellbook-item-iconframe-inactive", optional = true },
        { "spellbook-item-iconframe-shadow", optional = true }, { "spellbook-item-spellicon-mask", optional = true },
        { "spellbook-item-needtrainer-iconframe-backplate", optional = true }, { "spellbook-item-needtrainer-shadow", optional = true },
        { "UI-HUD-ActionBar-IconFrame-Mask", optional = true }, { "UI-HUD-ActionBar-IconFrame", optional = true },   -- Core.StyleIcon
        { "questlog-icon-setting", optional = true },   -- Zahnrad Core.Menu.ICON_SETTINGS (sonst UI-OptionsButton)
        -- Buchseiten der Zauberbuch-Ansicht (SpellbookView PAGE_ART; Gesamtreview 18.11.2026, T16-NM1)
        { "spellbook-Page-Left-C60", optional = true }, { "spellbook-Page-Right-C60", optional = true },
    },
    -- Dateien (Gesamtreview 18.11.2026, T16-NM1; vorher prüfte /ez test keine): Pfade, die ezCore selbst setzt, geprüft
    -- über Core.KnownFile (GetFileIDFromPath). optional = true: ezCore hat einen Rückfall (andere Datei oder Vorlage).
    -- Die Dateien und Atlanten der Module melden die Module über Core.AddSelfTest an (kind = "file" bzw. "atlas").
    files = {
        { "Interface\\Buttons\\WHITE8X8" },
        { "Interface\\Buttons\\ButtonHilight-Square" },
        { "Interface\\Buttons\\UI-Common-MouseHilight" },
        { "Interface\\Buttons\\Arrow-Down-Up" }, { "Interface\\Buttons\\Arrow-Up-Up" },
        { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" }, { "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down" },
        { "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" }, { "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down" },
        { "Interface\\Buttons\\UI-Quickslot2" }, { "Interface\\Buttons\\UI-Quickslot-Depress" },
        { "Interface\\Buttons\\UI-ActionButton-Border" }, { "Interface\\Buttons\\CheckButtonHilight" },
        { "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
        { "Interface\\Minimap\\Tracking\\Mailbox" },
        { "Interface\\TargetingFrame\\UI-StatusBar" },
        { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" }, { "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
        { "Interface\\MoneyFrame\\UI-GoldIcon" },
        { "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up" }, { "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down" },
        { "Interface\\CharacterFrame\\TempPortraitAlphaMask" },
        { "Interface\\CastingBar\\UI-CastingBar-Border" },
        { "Interface\\Common\\Indicator-Red" }, { "Interface\\Common\\Indicator-Green" },
        { "Interface\\Icons\\INV_Misc_QuestionMark" },                                    -- Core.ICON_FALLBACK
        { "Interface\\Common\\Indicator-Yellow", optional = true },                      -- MapPins (sonst Fragezeichen)
        { "Interface\\Buttons\\UI-OptionsButton", optional = true },                     -- Zahnrad-Rückfall
        { "Interface\\SpellBook\\SpellBook-SkillLineTab", optional = true },             -- Seitenreiter ohne Vorlage
        { "Interface\\Buttons\\UI-CheckBox-Up", optional = true },                       -- Häkchen ohne Vorlage
        { "Interface\\Buttons\\UI-CheckBox-Down", optional = true },
        { "Interface\\Buttons\\UI-CheckBox-Highlight", optional = true },
        { "Interface\\Buttons\\UI-CheckBox-Check", optional = true },
        { "Interface\\Buttons\\UI-CheckBox-Check-Disabled", optional = true },
    },
    apis = {
        -- Grundlage
        { "CreateFrame" }, { "hooksecurefunc" }, { "C_Timer.After" }, { "GetTime" }, { "InCombatLockdown" },
        { "StaticPopup_Show" }, { "GameTooltip" }, { "UIParent" }, { "SlashCmdList" },
        { "issecretvalue", optional = true }, { "canaccessvalue", optional = true }, { "debugprofilestop", optional = true },
        { "C_XMLUtil.GetTemplateInfo", optional = true }, { "C_Texture.GetAtlasInfo", optional = true },
        -- Einstellungen
        { "Settings.RegisterVerticalLayoutCategory" }, { "Settings.RegisterAddOnSetting" }, { "Settings.RegisterAddOnCategory" },
        { "Settings.CreateCheckbox" }, { "Settings.OpenToCategory" },
        { "Settings.RegisterVerticalLayoutSubcategory", optional = true }, { "Settings.RegisterCanvasLayoutSubcategory", optional = true },
        { "Settings.RegisterProxySetting", optional = true }, { "Settings.CreateSlider", optional = true },
        { "Settings.CreateSliderOptions", optional = true }, { "Settings.CreateControlTextContainer", optional = true },
        { "CreateSettingsButtonInitializer" }, { "CreateSettingsListSectionHeaderInitializer" },
        { "SettingsPanel", optional = true },
        -- Addons, CVars
        { "C_AddOns.IsAddOnLoaded" }, { "C_AddOns.GetAddOnMetadata" }, { "C_AddOns.DoesAddOnExist", optional = true },
        { "C_CVar.GetCVar", optional = true }, { "C_CVar.GetCVarDefault", optional = true },
        -- Tooltip
        { "TooltipDataProcessor.AddTooltipPostCall" }, { "Enum.TooltipDataType" }, { "C_TooltipInfo.GetUnit", optional = true },
        -- Gegenstände, Taschen
        { "C_Item.GetItemInfo" }, { "C_Item.GetItemInfoInstant" }, { "C_Item.GetItemCount", optional = true },
        { "C_Item.RequestLoadItemDataByID", optional = true }, { "C_Item.GetDetailedItemLevelInfo", optional = true },
        { "C_Container.GetContainerNumSlots" }, { "C_Container.GetContainerItemInfo" },
        { "C_Container.GetContainerNumFreeSlots", optional = true }, { "C_Bank.FetchPurchasedBankTabIDs", optional = true },
        -- Zauber, Aktionsplätze, Auren
        { "C_Spell.GetSpellName", optional = true }, { "C_Spell.GetSpellInfo", optional = true },
        { "C_Spell.GetSpellCooldown", optional = true }, { "C_SpellBook.IsSpellKnown", optional = true },
        { "C_ActionBar.GetActionCooldown", optional = true }, { "GetActionInfo" },
        { "C_UnitAuras.GetAuraDataByIndex", optional = true },
        -- Karte, Kontakte, Namen
        { "C_Map.GetBestMapForUnit" }, { "C_Map.GetMapInfo" }, { "C_Map.GetPlayerMapPosition", optional = true },
        { "C_FriendList.GetNumFriends", optional = true }, { "C_BattleNet.GetFriendAccountInfo", optional = true },
        { "RegionalUniqueNamesEnabled", optional = true }, { "UnitNameUnmodified", optional = true },
        { "C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator", optional = true },
        -- Post, Auktionshaus, Berufe, Sperren, Betrachten
        { "SendMail" }, { "GetInboxHeaderInfo" }, { "SetSendMailMoney" }, { "C_Mail.IsCommandPending", optional = true },
        { "C_AuctionHouse.GetBrowseResults", optional = true }, { "C_AuctionHouse.ReplicateItems", optional = true },
        { "GetProfessions", optional = true }, { "C_TradeSkillUI.GetRecipeSchematic", optional = true },
        { "RequestRaidInfo", optional = true }, { "GetSavedInstanceInfo", optional = true },
        { "NotifyInspect", optional = true }, { "C_PaperDollInfo.GetInspectItemLevel", optional = true },
        { "C_CurrencyInfo.GetCurrencyInfo", optional = true },
        -- Bearbeitungsmodus (nur zuhören)
        { "EventRegistry.RegisterCallback", optional = true }, { "EditModeManagerFrame", optional = true },
        -- Gruppen- und Raidrahmen (GroupFrames.lua: nur zuhören und lesen)
        { "CompactUnitFrame_SetUnit", optional = true }, { "PartyFrame.PartyMemberFramePool", optional = true },
        { "PartyFrame.UpdatePartyFrames", optional = true }, { "EditModeManagerFrame.UseRaidStylePartyFrames", optional = true },
        -- Klick-Zauber (ClickBindings.lua: lesen, schreiben nur außerhalb des Kampfes, Fenster öffnen)
        { "C_ClickBindings.GetProfileInfo", optional = true }, { "C_ClickBindings.SetProfileByInfo", optional = true },
        { "C_ClickBindings.GetStringFromModifiers", optional = true }, { "C_ClickBindings.CanSpellBeClickBound", optional = true },
        { "ToggleClickBindingFrame", optional = true },
    },
}

local holder   -- versteckter Elternrahmen für Probe-Rahmen (nur ohne C_XMLUtil.GetTemplateInfo)

-- Gibt es die Vorlage? Zuerst Blizzards Auskunft, sonst ein Probe-Rahmen (unsichtbar, bleibt versteckt liegen).
function Core.TemplateExists(frameType, name)
    if type(name) ~= "string" or name == "" then return false end
    local xml = rawget(_G, "C_XMLUtil")
    if type(xml) == "table" and type(xml.GetTemplateInfo) == "function" then
        local ok, info = pcall(xml.GetTemplateInfo, name)
        if ok then return info ~= nil end
    end
    if type(CreateFrame) ~= "function" then return false end
    if not holder then
        holder = CreateFrame("Frame")
        holder:Hide()
    end
    local ok, frame = pcall(CreateFrame, frameType or "Frame", nil, holder, name)
    if ok and type(frame) == "table" then
        if frame.Hide then pcall(frame.Hide, frame) end
        return true
    end
    return false
end

-- „C_Item.GetItemInfo“ → gibt es den Namen (Funktion oder Tabelle)?
function Core.GlobalExists(path)
    if type(path) ~= "string" or path == "" then return false end
    local value = _G
    for part in path:gmatch("[^%.]+") do
        if type(value) ~= "table" then return false end
        local ok, nextValue = pcall(function() return value == _G and rawget(_G, part) or value[part] end)
        if not ok or nextValue == nil then return false end
        value = nextValue
    end
    return true
end

---------------------------------------------------------------------------
-- Selbsttest der Module: Anmeldung und Daten-Zeilen (bis Welle 11 SelfTests.lua; EC-36)
---------------------------------------------------------------------------

local Spells = Core.Spells
--[[
    Selbsttest der Module (/ez test): Core.AddSelfTest(owner, fn, key)
      key (freiwillig) unterscheidet mehrere Anmeldungen desselben Besitzers; ohne key ersetzt eine neue die alte.

      fn() → { { kind = "spell" | "item" | …, name = Text, there = bool, optional = bool } … }
      Core.SelfTest() ruft nach den eigenen Prüfungen (Vorlagen, Atlanten, APIs) jede angemeldete Funktion geschützt
      und zählt ihre Einträge genauso: checked, ok, missing { kind, name, optional, owner }, required; extra nennt,
      wie viele der geprüften Einträge von Modulen stammen. Ein Fehler in einer Funktion bricht den Selbsttest
      nicht ab (er landet im Fehler-Log des Moduls).
      Core.SelfTestOwners() → { owner … } in der Reihenfolge der Anmeldung.

    ezCore meldet selbst an: jede Zauber-ID aus Spells.BUFFS und Spells.FAMILIES (optional – eine ID, die dieser
    Client nicht kennt, steht dann in der Fehlerliste). ezCombat meldet die Zauber-IDs seiner Rotationen an.

    Bis Welle 11 eigene Datei SelfTests.lua, die Core.SelfTest umhüllte; seit EC-36 steht alles hier und
    Core.SelfTest ruft die Anmeldungen direkt (Core.SELFTEST, SelfTestLines, RunSelfTest unverändert).

    Daten-Zeilen (DG-45, docs/datengrundlage.md 3.4): „ist die Funktion da?“ beantwortet nicht „liefert sie Daten?“.
    Ein Eintrag mit kind = "data" ist eine Beobachtung, kein Mangel – er zählt nicht zu checked/missing, sondern steht
    in result.data und erscheint als Zeile „Daten: <Name> – n Einträge / leer / fehlt / hier nicht prüfbar (Grund)“:
      { kind = "data", name = Text, state = "count" | "empty" | "missing" | "na" | "text", count = Zahl, note = Text }
        "na" = hier nicht prüfbar: die Probe hängt am Ort oder an einem offenen Fenster (Eingänge der aktuellen Karte,
        Wachen-Punkt, Händler) oder die Antwort ist gesperrt – sonst wiederholt sich der Fehlschluss „leer“.
        "text" = eine Auskunft, die keine Liste ist (ja/nein, Form einer GUID, Zustand einer Quelle).
      Core.SelfTestData(name, wert, note)   → Eintrag aus einem Wert: Tabelle und Zahl werden gezählt, nil und 0 sind
                                              „leer“, ein gesperrter Wert ist „hier nicht prüfbar (gesperrt)“ – er wird
                                              nur erkannt, nie verglichen
      Core.SelfTestCall(name, "Pfad", …)    → ruft die Client-Funktion geschützt: fehlt sie, „fehlt“; wirft sie, „hier
                                              nicht prüfbar (Fehler)“; sonst Core.SelfTestData mit der ersten Rückgabe
      Core.SelfTestNA(name, grund)          → Eintrag „hier nicht prüfbar (grund)“
      Core.SelfTestDataLine(eintrag)        → die Zeile
    ezCore meldet die Client-Quellen aus der Datengrundlage und je angebundener Quelle (Core.Sources.List) den Zustand an.
]]

local tests, owners, order = {}, {}, {}   -- tests[id] = { owner, fn }; order = ids in der Reihenfolge der Anmeldung

function Core.AddSelfTest(owner, fn, key)
    if type(fn) ~= "function" then return false end
    owner = type(owner) == "string" and owner ~= "" and owner or "?"
    local id = owner
    if type(key) == "string" and key ~= "" then id = owner .. "\031" .. key end
    if not tests[id] then
        order[#order + 1] = id
        local known = false
        for _, name in ipairs(owners) do if name == owner then known = true end end
        if not known then owners[#owners + 1] = owner end
    end
    tests[id] = { owner = owner, fn = fn }
    return true
end

function Core.SelfTestOwners()
    local list = {}
    for i, owner in ipairs(owners) do list[i] = owner end
    return list
end

---------------------------------------------------------------------------
-- Daten-Zeilen
---------------------------------------------------------------------------

local DATA_STATES = { count = true, empty = true, missing = true, na = true, text = true }

function Core.SelfTestNA(name, reason)
    return { kind = "data", name = name, state = "na", note = reason }
end

-- Zahl der Einträge einer Tabelle: Listenlänge, sonst die Zahl der Schlüssel (geschützt – fremde Tabellen können werfen).
local function CountEntries(value)
    local ok, n = pcall(function()
        local size = #value
        if size > 0 then return size end
        local keys = 0
        for _ in pairs(value) do keys = keys + 1 end
        return keys
    end)
    return ok and n or nil
end

function Core.SelfTestData(name, value, note)
    local entry = { kind = "data", name = name, note = note }
    if Core.IsSecret(value) then
        entry.state, entry.note = "na", L.SELFTEST_DATA_LOCKED
    elseif value == nil then
        entry.state = "empty"
    elseif type(value) == "number" then
        entry.state, entry.count = value > 0 and "count" or "empty", value
    elseif type(value) == "table" then
        local n = CountEntries(value)
        if n == nil then
            entry.state, entry.note = "na", L.SELFTEST_DATA_ERROR
        else
            entry.state, entry.count = n > 0 and "count" or "empty", n
        end
    elseif type(value) == "boolean" then
        entry.state, entry.note = "text", value and L.YES or L.NO
    else
        entry.state, entry.note = "text", tostring(value)
    end
    return entry
end

-- "C_Item.GetItemInfo" → Funktion oder nil
local function ResolveFunction(path)
    local value = _G
    for part in tostring(path):gmatch("[^%.]+") do
        if type(value) ~= "table" then return nil end
        value = value == _G and rawget(_G, part) or Core.Peek(value, part)
        if value == nil then return nil end
    end
    return type(value) == "function" and value or nil
end

-- → Eintrag, alle Rückgaben (für Proben, die mehr als den ersten Wert brauchen; nil bei „fehlt“ oder Fehler)
function Core.SelfTestCall(name, path, ...)
    local fn = ResolveFunction(path)
    if not fn then return { kind = "data", name = name, state = "missing" } end
    local results = { pcall(fn, ...) }
    if not results[1] then return Core.SelfTestNA(name, L.SELFTEST_DATA_ERROR) end
    return Core.SelfTestData(name, results[2]), results
end

function Core.SelfTestDataLine(entry)
    if type(entry) ~= "table" then return nil end
    local text
    if entry.state == "count" then
        text = Core.Plural(entry.count, L.SELFTEST_DATA_ONE, L.SELFTEST_DATA_MANY)
    elseif entry.state == "text" then
        text = tostring(entry.note or "?")
    else
        text = L["SELFTEST_DATA_" .. tostring(entry.state)]
    end
    if entry.state ~= "text" and type(entry.note) == "string" and entry.note ~= "" then
        text = text .. " (" .. entry.note .. ")"
    end
    return L.SELFTEST_DATA:format(tostring(entry.name), text)
end

-- Einträge der angemeldeten Funktionen in ein Ergebnis von Core.SelfTest zählen. Melden zwei Anmeldungen denselben
-- Eintrag (gleiche Art, gleicher Name – etwa ezCore und ezHeal dieselbe Zauber-ID „Segen der Rettung (1038)“), zählt
-- er nur einmal (Fehlerliste des Nutzers vom 15.11.2026: 1038, 19977 und 20911 standen doppelt). Verlangt ihn eine
-- der Anmeldungen ausdrücklich (nicht optional), gilt er als verlangt.
local function Extend(result)
    result.extra = 0
    result.data = {}
    local seen = {}   -- ["Art\031Name"] = true (vorhanden) bzw. der Eintrag in result.missing
    for _, id in ipairs(order) do
        local owner = tests[id].owner
        local ok, list = pcall(tests[id].fn)
        if not ok then
            Core.Error(owner, list, "selfTest")
        elseif type(list) == "table" then
            for _, entry in ipairs(list) do
                if type(entry) == "table" and entry.kind == "data" then
                    -- Beobachtung, kein Mangel: eigene Liste, zählt nicht mit
                    if not Core.IsSecret(entry.name) and entry.name ~= nil and DATA_STATES[entry.state] then
                        result.data[#result.data + 1] = { name = tostring(entry.name), state = entry.state,
                            count = Core.Num(entry.count), note = Core.Plain(entry.note), owner = owner }
                    end
                elseif type(entry) == "table" and not Core.IsSecret(entry.name) and entry.name ~= nil then
                    local kind, name = tostring(entry.kind or "api"), tostring(entry.name)
                    local key = kind .. "\031" .. name
                    local before = seen[key]
                    if before == nil then
                        result.checked = result.checked + 1
                        result.extra = result.extra + 1
                        if entry.there then
                            result.ok = result.ok + 1
                            seen[key] = true
                        else
                            local optional = entry.optional == true
                            local missing = { kind = kind, name = name, optional = optional, owner = owner }
                            result.missing[#result.missing + 1] = missing
                            seen[key] = missing
                            if not optional then result.required = result.required + 1 end
                        end
                    elseif type(before) == "table" and before.optional and not entry.there and entry.optional ~= true then
                        before.optional = false
                        result.required = result.required + 1
                    end
                end
            end
        end
    end
    return result
end


local lastResult

function Core.SelfTest()
    local result = { t = time and time() or 0, checked = 0, ok = 0, missing = {}, required = 0 }
    local function Note(kind, name, there, optional)
        result.checked = result.checked + 1
        if there then
            result.ok = result.ok + 1
        else
            result.missing[#result.missing + 1] = { kind = kind, name = name, optional = optional == true }
            if not optional then result.required = result.required + 1 end
        end
    end
    for _, entry in ipairs(Core.SELFTEST.templates) do
        Note("template", entry[2], Core.TemplateExists(entry[1], entry[2]), entry.optional)
    end
    for _, entry in ipairs(Core.SELFTEST.atlases) do
        Note("atlas", entry[1], Core.AtlasExists(entry[1]), entry.optional)
    end
    for _, entry in ipairs(Core.SELFTEST.files or {}) do
        Note("file", entry[1], Core.KnownFile(entry[1]), entry.optional)
    end
    for _, entry in ipairs(Core.SELFTEST.apis) do
        Note("api", entry[1], Core.GlobalExists(entry[1]), entry.optional)
    end
    Extend(result)          -- Einträge der angemeldeten Module (Core.AddSelfTest)
    lastResult = result
    return result
end

function Core.SelfTestResult() return lastResult end

function Core.SelfTestLines()
    local r = lastResult
    if not r then return nil end
    local lines = { L.SELFTEST_HEAD:format(Core.DateText(r.t, "long"), r.checked, #r.missing, r.required) }
    for _, m in ipairs(r.missing) do
        lines[#lines + 1] = (m.optional and L.SELFTEST_MISSING_OPTIONAL or L.SELFTEST_MISSING):format(L["SELFTEST_KIND_" .. m.kind] or m.kind, m.name)
    end
    if #r.missing == 0 then lines[#lines + 1] = L.SELFTEST_ALL_OK end
    -- Daten-Zeilen (DG-45, oben): Beobachtungen „liefert die Funktion Daten?“, kein Mangel
    if type(r.data) == "table" and #r.data > 0 and Core.SelfTestDataLine then
        lines[#lines + 1] = L.SELFTEST_DATA_HEAD
        for _, entry in ipairs(r.data) do lines[#lines + 1] = Core.SelfTestDataLine(entry) end
    end
    return lines
end

-- Knopf und „/ez test“: prüfen (im Kampf erst danach), im Chat melden, Fehlerliste zum Kopieren zeigen.
function Core.RunSelfTest(quiet)
    local result
    local ran = Core.AfterCombat(function()
        result = Core.SelfTest()
        if quiet then return end
        if #result.missing == 0 then
            ns.Print(L.SELFTEST_DONE_OK:format(result.checked))
        else
            ns.Print(L.SELFTEST_DONE:format(result.checked, #result.missing, result.required))
        end
        if type(result.data) == "table" and #result.data > 0 then ns.Print(L.SELFTEST_DATA_DONE:format(#result.data)) end
        if Core.ShowErrorList then Core.ShowErrorList() end
    end, "ezCore.selfTest", ADDON)
    if not ran and not quiet then ns.Print(L.SELFTEST_COMBAT) end
    return result
end

---------------------------------------------------------------------------
-- Anmeldungen von ezCore selbst
---------------------------------------------------------------------------

-- ezCore: Kennt dieser Client die Zauber-IDs des Klassen-Wissens?
Core.AddSelfTest("ezCore", function()
    local list, seen = {}, {}
    local function Add(id)
        if seen[id] then return end
        seen[id] = true
        list[#list + 1] = { kind = "spell", name = ("%s (%d)"):format(Spells.Name(id) or "?", id), there = Spells.Exists(id),
            optional = true }
    end
    for _, key in ipairs(Spells.BUFF_ORDER) do
        local d = Spells.BUFFS[key]
        for _, id in ipairs(d and d.spells or {}) do Add(id) end
        for _, id in ipairs(d and d.group or {}) do Add(id) end
    end
    local names = {}
    for name in pairs(Spells.FAMILIES) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        for _, id in ipairs(Spells.FAMILIES[name].spells) do Add(id) end
    end
    -- Welle 8: Heilen, Bannen, Wiederbeleben, Helfer, Gestalten und die Makro-Logik je Klasse
    local ids = {}
    local function Collect(t)
        for k, v in pairs(t or {}) do
            if type(v) == "table" then Collect(v) elseif type(v) == "number" and type(k) == "number" then ids[v] = true end
        end
    end
    Collect(Spells.HEALS)
    Collect(Spells.DISPELS)
    Collect(Spells.RESURRECTS)
    Collect(Spells.HELPERS)
    for id in pairs(Spells.FORM_IDS or {}) do ids[id] = true end
    for id in pairs(Spells.MacroSpells and Spells.MacroSpells() or {}) do ids[id] = true end
    local sorted = {}
    for id in pairs(ids) do sorted[#sorted + 1] = id end
    table.sort(sorted)
    for _, id in ipairs(sorted) do Add(id) end
    return list
end)

---------------------------------------------------------------------------
-- ezCore: Daten-Zeilen der Client-Quellen (DG-45; Liste aus docs/datengrundlage.md 3.3 und 3.4). Jede Probe liest
-- nur, ruft geschützt und zeigt Zahlen – nie Namen, nie eine ganze GUID. Ortsgebundenes sagt „hier nicht prüfbar“.
---------------------------------------------------------------------------

local RECIPE = 2330          -- ein Rezept der Alchemie – dieselbe Nummer wie in docs/datengrundlage.md 3.3

local function Shown(name)
    local frame = rawget(_G, name)
    local isShown = Core.Peek(frame, "IsShown")
    if type(isShown) ~= "function" then return false end
    local ok, shown = pcall(isShown, frame)
    return ok and Core.Bool(shown, false)
end

local function CurrentMap()
    local api = rawget(_G, "C_Map")
    return Core.Num(Core.Call(Core.Peek(api, "GetBestMapForUnit"), "player"))
end

Core.AddSelfTest("ezCore", function()
    local list = {}
    local function Add(entry) list[#list + 1] = entry end
    local function Label(key, ...) return L["SELFTEST_D_" .. key]:format(...) end

    -- Buff-Gruppen und Zauber je Stufe
    Add(Core.SelfTestCall(Label("groupBuffs"), "C_CooldownViewer.GetGroupBuffItems"))
    local level = Core.PlayerLevel() or 1
    Add(Core.SelfTestCall(Label("levelSpells", level + 2), "C_SpellBook.GetCurrentLevelSpells", level + 2))
    -- Begleiter-Fähigkeiten (DG-46): Zahl der Zauber im Begleiter-Zauberbuch (ohne Begleiter: leer)
    Add(Core.SelfTestCall(Label("petSpells"), "C_SpellBook.HasPetSpells"))

    -- Rezepte ohne offenes Berufefenster
    local window = Shown("ProfessionsFrame") or Shown("TradeSkillFrame")
    local output, results = Core.SelfTestCall(Label("recipeOutput"), "C_TradeSkillUI.GetRecipeOutputItemData", RECIPE)
    if results then
        local data = results[2]
        local hasItem = not Core.IsSecret(data) and (Core.Num(Core.Peek(data, "itemID")) or Core.Plain(Core.Peek(data, "hyperlink"))) ~= nil
        if not Core.IsSecret(data) then output = Core.SelfTestData(Label("recipeOutput"), hasItem and 1 or nil) end
    end
    if window then output.note = L.SELFTEST_NOTE_PROFESSION_OPEN end
    Add(output)
    local schematic, schematicResults = Core.SelfTestCall(Label("recipeSchematic"), "C_TradeSkillUI.GetRecipeSchematic", RECIPE, false)
    if schematicResults and not Core.IsSecret(schematicResults[2]) then
        schematic = Core.SelfTestData(Label("recipeSchematic"), Core.Peek(schematicResults[2], "reagentSlotSchematics"))
    end
    if window then schematic.note = L.SELFTEST_NOTE_PROFESSION_OPEN end
    Add(schematic)

    -- Dungeonführer
    Add(Core.SelfTestCall(Label("journalTiers"), "EJ_GetNumTiers"))

    -- Plunder verkaufen: nur am offenen Händler
    if Shown("MerchantFrame") then
        Add(Core.SelfTestCall(Label("junkItems"), "C_MerchantFrame.GetNumJunkItems"))
        Add(Core.SelfTestCall(Label("junkEnabled"), "C_MerchantFrame.IsSellAllJunkEnabled"))
    else
        Add(Core.SelfTestNA(Label("junkItems"), L.SELFTEST_NA_MERCHANT))
    end

    -- Karte: Wachen-Punkt, Dungeon-Eingänge, Zonenstufen – alles am Ort
    local map = CurrentMap()
    if not map then
        Add(Core.SelfTestNA(Label("guardPoi"), L.SELFTEST_NA_NOMAP))
        Add(Core.SelfTestNA(Label("entrances"), L.SELFTEST_NA_NOMAP))
        Add(Core.SelfTestNA(Label("mapLevels"), L.SELFTEST_NA_NOMAP))
    else
        local poi = Core.SelfTestCall(Label("guardPoi"), "C_GossipInfo.GetPoiForUiMapID", map)
        if poi.state == "empty" then poi = Core.SelfTestNA(Label("guardPoi"), L.SELFTEST_NA_GUARD) end
        if poi.state == "count" then poi.count = 1 end      -- die Rückgabe ist die Nummer des Punkts, keine Anzahl
        Add(poi)
        local entrances = Core.SelfTestCall(Label("entrances"), "C_EncounterJournal.GetDungeonEntrancesForMap", map)
        if entrances.state == "empty" then entrances = Core.SelfTestNA(Label("entrances"), L.SELFTEST_NA_MAP:format(map)) end
        Add(entrances)
        local levels, levelResults = Core.SelfTestCall(Label("mapLevels"), "C_Map.GetMapLevels", map)
        if levelResults then
            local low = Core.Num(levelResults[2])
            if Core.IsSecret(levelResults[2]) then
                levels = Core.SelfTestData(Label("mapLevels"), levelResults[2])
            elseif low and low > 0 then
                levels = { kind = "data", name = Label("mapLevels"), state = "text",
                    note = L.SELFTEST_LEVELS:format(low, Core.Num(levelResults[3]) or low) }
            else
                levels = Core.SelfTestNA(Label("mapLevels"), L.SELFTEST_NA_MAP:format(map))
            end
        end
        Add(levels)
    end

    -- Sammlungen: Haustiere (Spieltest: 0 Einträge), Herkunft eines Aussehens
    Add(Core.SelfTestCall(Label("pets"), "C_PetJournal.GetNumPets"))
    local sourceID
    local getLink, itemInfo = rawget(_G, "GetInventoryItemLink"), Core.Peek(rawget(_G, "C_TransmogCollection"), "GetItemInfo")
    for slot = 1, 19 do
        local link = Core.Plain(Core.Call(getLink, "player", slot))
        if type(link) == "string" and type(itemInfo) == "function" then
            local _, id = Core.Call(itemInfo, link)
            sourceID = Core.Num(id)
            if sourceID then break end
        end
    end
    if type(itemInfo) ~= "function" then
        Add({ kind = "data", name = Label("appearanceSource"), state = "missing" })
    elseif not sourceID then
        Add(Core.SelfTestNA(Label("appearanceSource"), L.SELFTEST_NA_NOITEM))
    else
        local source, sourceResults = Core.SelfTestCall(Label("appearanceSource"), "C_TransmogCollection.GetSourceInfo", sourceID)
        if sourceResults and not Core.IsSecret(sourceResults[2]) and type(sourceResults[2]) == "table" then
            local kind = Core.Num(Core.Peek(sourceResults[2], "sourceType"))
            source = { kind = "data", name = Label("appearanceSource"), state = kind and "text" or "empty",
                note = kind and L.SELFTEST_SOURCE_TYPE:format(kind) or nil }
        end
        Add(source)
        Add(Core.SelfTestCall(Label("appearanceDrops"), "C_TransmogCollection.GetAppearanceSourceDrops", sourceID))
    end

    -- Kampflog und Form der GUID (nur Art und Zahl der Teile – nie die GUID selbst)
    Add(Core.SelfTestCall(Label("combatLog"), "C_CombatLog.IsCombatLogRestricted"))
    local guid = Core.Call(rawget(_G, "UnitGUID"), "player")
    if Core.IsSecret(guid) then
        Add(Core.SelfTestData(Label("guid"), guid))
    elseif type(guid) == "string" and guid ~= "" then
        local parts = select(2, guid:gsub("%-", "")) + 1
        Add({ kind = "data", name = Label("guid"), state = "text", note = L.SELFTEST_GUID:format(guid:match("^([^%-]+)") or "?", parts) })
    else
        Add({ kind = "data", name = Label("guid"), state = "empty" })
    end
    -- Die offene Frage aus der Datengrundlage (3.3) betrifft die GUID eines Gegners: Blizzard verschleiert Teile –
    -- ist die NPC-Nummer (Feld 6) noch lesbar? Nur mit einem Ziel, das kein Spieler ist.
    if Core.UnitPresent("target") == true and Core.UnitIs("target") == false then
        local targetGuid = Core.Call(rawget(_G, "UnitGUID"), "target")
        if Core.IsSecret(targetGuid) then
            Add(Core.SelfTestData(Label("targetGuid"), targetGuid))
        elseif type(targetGuid) == "string" and targetGuid ~= "" then
            local parts = select(2, targetGuid:gsub("%-", "")) + 1
            Add({ kind = "data", name = Label("targetGuid"), state = "text", note = L.SELFTEST_GUID_NPC:format(
                targetGuid:match("^([^%-]+)") or "?", parts, Core.NpcID(targetGuid) and L.YES or L.NO) })
        else
            Add({ kind = "data", name = Label("targetGuid"), state = "empty" })
        end
    else
        Add(Core.SelfTestNA(Label("targetGuid"), L.SELFTEST_NA_TARGET))
    end

    -- Forever-Währungen ohne Beleg (PANEL-11, CharData.lua): kennt der Client die Nummer? Name aus dem Client.
    local currencies = Core.Currencies
    for _, id in ipairs(currencies and currencies.EXTRA or {}) do
        local info = currencies.Info and currencies.Info(id)
        local name = info and Core.Plain(info.name)
        if type(name) == "string" and name ~= "" then
            Add({ kind = "data", name = Label("currency", id), state = "text", note = name })
        else
            Add({ kind = "data", name = Label("currency", id), state = "missing" })
        end
    end

    -- angebundene Quellen (fremde Datenbanken, nur zur Laufzeit gefragt)
    local sources = Core.Sources
    if type(sources) == "table" and type(sources.List) == "function" then
        local ok, entries = pcall(sources.List)
        for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
            local name = Label("source", tostring(entry.label or entry.key))
            if entry.status == "missing" then
                Add({ kind = "data", name = name, state = "missing" })
            elseif entry.status == "ok" then
                local note = L.SELFTEST_SOURCE_OK
                if (Core.Num(entry.skipped) or 0) > 0 then note = note .. ", " .. L.SOURCES_SKIPPED:format(entry.skipped) end
                Add({ kind = "data", name = name, state = "text", note = note })
            else
                Add({ kind = "data", name = name, state = "text",
                    note = entry.status == "error" and L.SOURCES_STATUS_ERROR or L.SOURCES_STATUS_SHAPE })
            end
        end
    end
    return list
end, "data")

-- DG-20: die Bücher-IDs (Collections.lua) gegen QuestieDB bzw. den Client bestätigen
if Core.Collections and Core.Collections.BookSelfTest then
    Core.AddSelfTest("ezCore", Core.Collections.BookSelfTest, "books")
end
