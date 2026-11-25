local ADDON, ns = ...
local Core = ezCore

--[[ Blizzard-Fenster aus Addon-Code öffnen, umschalten, schließen – EIN Ort für alle Module
     (Entscheidung des Nutzers 13.11.2026, Fund V-169 der Vollprüfung).

     Core.OpenPanel(name, arg, opts)    → true | false, Grund
     Core.TogglePanel(name, arg, quiet) → true | false, Grund
     Core.ClosePanel(name, arg, quiet)  → true | false, Grund
     Core.PanelShown(name, arg)         → true | false | nil (unbekannt)
     Core.Panels.Frames(name)           → oberste Rahmen des Fensters (panel, sonst frames), neue Liste
     Core.Panels.SettingsPending()      → true, wenn Blizzards Einstellungsfenster offen ist und beim Schließen etwas
                                          übernähme (geänderte Einstellungen, Tastenbelegung, „Übernehmen“) – dann
                                          schließt ClosePanel("settings") nicht: false, "pending"
     Core.OpenChatWith(text, asLink)    → true | false, Weg/Grund

     Regeln:
     - Nur außerhalb des Kampfes. Im Kampf: kurzer Hinweis (UIErrorsFrame) und false, "combat".
     - Jede Blizzard-Funktion wird erst gesucht (fehlt sie: die nächste aus der Liste) und über pcall gerufen.
     - Unbekannter Name oder unbekannte Variante → false, "unknown"; kein Weg im Client → false, "missing".
     - Nur Aufrufe von Blizzards eigenen Funktionen; nichts wird in Blizzards Tabellen geschrieben.
     - Fenster mit selfOnly (Zauberbuch, Talente, Klick-Zauber) schließt der Spieler selbst: Schließen und Umschalten geben
       false, "self" und einen Hinweis mit dem Weg (Panels.SelfHint). Öffnen ist seit dem Versuch vom 23.11.2026 wieder
       frei (Panels.OPEN_SELF_ONLY = false); mit true ist auch das Öffnen gesperrt (Stand von PR 732). Das Neu-Öffnen
       nach dem Speichern sperren die Aufrufer über Panels.SelfOnly (Core.ClickBindings.Reload, ezHeal Dock.lua).
       Talente (seit 24.11.2026): Zauberbuch und Talente sind Unterrahmen von PlayerSpellsFrame, und das Raster hängt am
       ganzen Fenster (PlayerSpellsFrameMixin:OnShow/OnHide → MultiActionBar_ShowAllGrids/HideAllGrids), nicht am Reiter.
       Ist es schon offen, schaltet „open“ auch nicht auf die Talente um (def.busy, Panels.SelfOpen): SetTab schriebe den
       gemerkten Reiter aus Addon-Code, und OnShow → UpdateTabs liest ihn beim nächsten Öffnen vor dem Raster
       (Blizzard_PlayerSpells/Blizzard_PlayerSpellsFrame.lua, Build 1.60.1.71091).
       Beleg (Blizzards Forever-Quelle, Blizzard_ActionBar/Shared/ActionBar.lua):
       Auf- und Zugehen des Zauberbuchs ruft SetShowGrid(…, ACTION_BUTTON_SHOW_GRID_REASON_SPELLCOLLECTION) auf allen
       Aktionsleisten und schreibt dabei showAllButtons, shownButtonContainers und oldGridSettings. Aus Addon-Code
       geöffnet, sind diese Felder verunreinigt; im Kampf liest StanceBar:UpdateGridLayout → ShouldUpdateGrid sie, und
       MainActionBar:SetPointBase wird blockiert (Spielbefunde vom 23.11.2026: „leiste weg“, Leitlinie 5). Laut Nutzer
       blieb die Leiste, solange nach dem Speichern nichts das Zauberbuch wieder öffnete („das problem war nicht
       zauberbuch klickzauber öffnen und speichern. sondern dass danach wieder zauberbuch geöffnet wurde“) – der
       Spieltest entscheidet, ob das Öffnen frei bleibt.
     Neue Fenster nur hier ergänzen (Panels.LIST), nicht im Modul. ]]

local Panels = {}
Core.Panels = Panels

---------------------------------------------------------------------------
-- Helfer
---------------------------------------------------------------------------

-- Globale Funktion oder Tabelle über ihren Namen, auch „PlayerSpellsUtil.ToggleSpellBookFrame“.
local function Global(path)
    if type(path) ~= "string" then return nil end
    local value
    for part in path:gmatch("[^.]+") do
        if value == nil then
            value = rawget(_G, part)
        elseif type(value) == "table" then
            value = value[part]
        else
            return nil
        end
        if value == nil then return nil end
    end
    return value
end
Panels.Global = Global

-- Ist das Fenster zu sehen? true/false, nil wenn es das Fenster (noch) nicht gibt.
local function FrameVisible(name)
    local frame = Global(name)
    if type(frame) ~= "table" then return nil end
    local probe = frame.IsVisible or frame.IsShown
    if type(probe) ~= "function" then return nil end
    local ok, visible = pcall(probe, frame)
    if not ok or Core.IsSecret(visible) then return nil end
    return visible and true or false
end
Panels.FrameVisible = FrameVisible

-- Ist das Fenster offen, auch wenn es bei ausgeblendeter Oberfläche (Alt+Z) nicht zu sehen ist? true/false, nil = unbekannt.
local function FrameOpen(name)
    local frame = Global(name)
    if type(frame) ~= "table" or type(frame.IsShown) ~= "function" then return nil end
    local ok, isShown = pcall(frame.IsShown, frame)
    if not ok or Core.IsSecret(isShown) then return nil end
    return isShown and true or false
end

-- Geschützter Aufruf: true bei Erfolg, false bei einem Fehler (landet in der Fehlerliste).
local function Run(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return true end
    Core.Error(ADDON, err, "OpenPanel")
    return false
end

-- Schritt: Blizzards Funktion „path“ rufen. args(arg) liefert die Werte dafür (false = Schritt passt nicht),
-- ohne args geht arg unverändert durch. Rückgabe des Schritts: true erledigt, false Fehler, nil gibt es nicht.
local function Fn(path, args)
    return function(arg)
        local fn = Global(path)
        if type(fn) ~= "function" then return nil end
        if not args then return Run(fn, arg) end
        local a, b = args(arg)
        if a == false then return nil end
        return Run(fn, a, b)
    end
end

local function NoArgs() return nil end

-- Blizzards Taschen-ID der Reagenzientasche (Enum.BagIndex.ReagentBag) oder nil.
local function ReagentBagID()
    local enum = rawget(_G, "Enum")
    local index = type(enum) == "table" and enum.BagIndex or nil
    local id = type(index) == "table" and index.ReagentBag or nil
    if type(id) ~= "number" then return nil end
    local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(id)
    if Core.IsSecret(slots) or type(slots) ~= "number" or slots <= 0 then return nil end
    return id
end
local function ReagentBagArg()
    local id = ReagentBagID()
    if not id then return false end
    return id
end

-- Schritt: Fenster über Blizzards Panel-Verwaltung zeigen (für Fenster ohne eigene Öffnen-Funktion).
local function ShowFrame(name)
    return function()
        local frame = Global(name)
        if type(frame) ~= "table" then return nil end
        local show = rawget(_G, "ShowUIPanel")
        if type(show) == "function" then return Run(show, frame) end
        if type(frame.Show) == "function" then return Run(frame.Show, frame) end
        return nil
    end
end

local function HideFrame(frame)
    local hide = rawget(_G, "HideUIPanel")
    if type(hide) == "function" then return Run(hide, frame) end
    if type(frame.Hide) == "function" then return Run(frame.Hide, frame) end
    return nil
end

-- Würde Blizzards Einstellungsfenster beim Schließen etwas übernehmen? Nur gelesen. Zwei Quellen: die Tabelle der
-- geänderten Einstellungen des Rahmens (self.modified – Blizzards Close/ExitWithCommit übernimmt sie samt
-- Tastenbelegung, auch ohne „Übernehmen“) und SettingsPanelMixin:HasUnappliedSettings (Änderungen, die erst
-- „Übernehmen“ wirksam macht, Grafik u. a.). → true, wenn es offen ist und eines davon zutrifft; im Zweifel (Fehler,
-- gesperrter Wert) ebenfalls true – dann bleibt es lieber offen.
function Panels.SettingsPending()
    if not FrameVisible("SettingsPanel") then return false end
    local panel = Global("SettingsPanel")
    if type(panel) ~= "table" then return false end
    -- rawget: Blizzards Mixin legt Tabelle und Methode als eigene Felder des Rahmens an (nichts davon vom Client)
    local modified = rawget(panel, "modified")
    if Core.IsSecret(modified) then return true end
    if type(modified) == "table" then
        local ok, key = pcall(next, modified)
        if not ok or key ~= nil then return true end
    end
    local pending = rawget(panel, "HasUnappliedSettings")
    if type(pending) ~= "function" then return false end
    local ok, yes = pcall(pending, panel)
    if not ok or Core.IsSecret(yes) then return true end
    return yes == true
end

local function Steps(steps, arg)
    for _, step in ipairs(steps or {}) do
        local result = step(arg)
        if result ~= nil then return result end
    end
    return nil
end

---------------------------------------------------------------------------
-- Reiter (optionales Argument)
---------------------------------------------------------------------------

-- Charakterfenster: Kurzname oder Blizzards Rahmenname; ohne Angabe die Ausrüstung.
Panels.CHARACTER_TABS = {
    paperdoll = "PaperDollFrame", equipment = "PaperDollFrame", stats = "PaperDollFrame",
    currency = "TokenFrame", currencies = "TokenFrame", token = "TokenFrame",
    reputation = "ReputationFrame",
    skills = "SkillFrame", skill = "SkillFrame",
}

local function CharacterTab(arg)
    if type(arg) ~= "string" or arg == "" then return "PaperDollFrame" end
    return Panels.CHARACTER_TABS[arg:lower()] or arg
end

-- Einstellungen: Kurzname → Blizzards Konstante in „Settings“.
Panels.SETTINGS_IDS = {
    social = "SOCIAL_CATEGORY_ID",
    keybindings = "KEYBINDINGS_CATEGORY_ID", keys = "KEYBINDINGS_CATEGORY_ID",
}

-- Kategorie-ID aus Zahl, Kurzname ("social", "keybindings"), Konstantenname oder Kategorie-Tabelle.
-- false: ein Kurzname, dessen Konstante der Client nicht kennt.
local function SettingsID(arg)
    local settings = rawget(_G, "Settings")
    if type(arg) == "table" and type(arg.GetID) == "function" then
        local ok, id = pcall(arg.GetID, arg)
        return ok and id or nil
    end
    if type(arg) ~= "string" then return arg end
    local constant = Panels.SETTINGS_IDS[arg:lower()]
    if constant then
        local id = type(settings) == "table" and settings[constant]
        if id == nil or id == false then return false end
        return id
    end
    if type(settings) == "table" and arg:match("^[%u_]+$") and settings[arg] ~= nil then return settings[arg] end
    return arg
end

-- Kategorie-ID einer Kategorie in Blizzards Einstellungsfenster über ihren Namen (für Kategorien ohne ID-Konstante,
-- etwa „Kampf“). Nur gelesen: SettingsPanel:GetAllCategories() und category:GetName()/:GetID() (Forever-Quelle
-- Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua, Blizzard_Category.lua). → id | nil
local function SettingsIDByName(name)
    name = Core.Plain(name)
    if type(name) ~= "string" or name == "" then return nil end
    local panel = Global("SettingsPanel")
    local all = type(panel) == "table" and panel.GetAllCategories
    if type(all) ~= "function" then return nil end
    local ok, list = pcall(all, panel)
    if not ok or type(list) ~= "table" or Core.IsSecret(list) then return nil end
    for _, category in ipairs(list) do
        if type(category) == "table" and type(category.GetName) == "function" and type(category.GetID) == "function" then
            local okName, label = pcall(category.GetName, category)
            if okName and not Core.IsSecret(label) and label == name then
                local okID, id = pcall(category.GetID, category)
                if okID and not Core.IsSecret(id) and id ~= nil then return id end
            end
        end
    end
    return nil
end
Panels.SettingsIDByName = SettingsIDByName

local function SelectedTab(frameName)
    local frame, get = Global(frameName), rawget(_G, "PanelTemplates_GetSelectedTab")
    if type(frame) ~= "table" or type(get) ~= "function" then return nil end
    local ok, tab = pcall(get, frame)
    if not ok or Core.IsSecret(tab) then return nil end
    return tab
end

---------------------------------------------------------------------------
-- Die Fenster
--   frames  Rahmen, an denen „offen?“ abgelesen wird (der erste sichtbare zählt)
--   panel   oberste Rahmen, die beim Schließen versteckt werden – nur nötig, wo „frames“ einen Unterrahmen
--           nennt (Reiter in Blizzards Fenster); ohne „panel“ gelten die Rahmen aus „frames“
--   shown   eigene Prüfung fn(arg) → true/false/nil (für Reiter)
--   load    Blizzards Addon, das das Fenster erst lädt (bei Bedarf)
--   toggle/open/close  Schritte in Reihenfolge; der erste, den der Client kennt, gilt.
--   Fehlt „open“: offen → nichts, sonst toggle. Fehlt „close“: HideUIPanel auf das
--   sichtbare oberste Fenster (panel, sonst frames) – nie auf einen Unterrahmen.
--   Fehlt „toggle“: offen → close, sonst open.
---------------------------------------------------------------------------

Panels.LIST = {
    -- arg: Reiter (Kurzname aus CHARACTER_TABS oder Rahmenname, z. B. "TokenFrame")
    character = {
        frames = { "CharacterFrame" },
        shown = function(arg)
            local open = FrameVisible("CharacterFrame")
            if not open or arg == nil then return open end
            return FrameVisible(CharacterTab(arg)) == true
        end,
        toggle = { Fn("ToggleCharacter", CharacterTab) },
    },
    -- arg: das Fenster, das die Taschen braucht (wie Blizzards OpenAllBags(frame)); bei toggle ohne Bedeutung
    bags = {
        frames = { "ContainerFrameCombinedBags", "ContainerFrame1" },
        toggle = { Fn("ToggleAllBags", NoArgs) },
        open = { Fn("OpenAllBags") },
        close = { Fn("CloseAllBags") },
    },
    -- Blizzards Reagenzientasche: im kombinierten Modus ein eigenes Fenster neben der Tasche, ohne festen Rahmennamen
    -- (Blizzard nimmt das nächste freie ContainerFrameN) – darum „offen?“ über IsBagOpen. ezBag zeigt sie als Abschnitt
    -- in der Tasche und öffnet bzw. schließt sie mit (23.11.2026). Ohne angelegte Reagenzientasche: "missing".
    -- Schlüssel klein geschrieben wie alle (Core.OpenPanel sucht name:lower()); Aufruf als "reagentBag" geht.
    reagentbag = {
        shown = function()
            local id = ReagentBagID()
            local isOpen = rawget(_G, "IsBagOpen")
            if not id or type(isOpen) ~= "function" then return nil end
            local ok, open = pcall(isOpen, id)
            if not ok or Core.IsSecret(open) then return nil end
            return open ~= nil and open ~= false
        end,
        open = { Fn("OpenBag", ReagentBagArg) },
        close = { Fn("CloseBag", ReagentBagArg) },
    },
    -- arg: uiMapID (nur beim Öffnen)
    map = {
        frames = { "WorldMapFrame" },
        toggle = { Fn("ToggleWorldMap", NoArgs), Fn("ToggleFrame", function()
            local frame = rawget(_G, "WorldMapFrame")
            if type(frame) ~= "table" then return false end
            return frame
        end) },
        open = { Fn("OpenWorldMap", function(arg)
            if FrameVisible("WorldMapFrame") and arg == nil then return false end
            return arg
        end) },
    },
    -- arg: Nummer des Reiters (Blizzards FRIEND_TAB_…)
    friends = {
        frames = { "FriendsFrame" },
        shown = function(arg)
            local open = FrameVisible("FriendsFrame")
            if not open or arg == nil then return open end
            local tab = SelectedTab("FriendsFrame")
            return tab == nil or tab == arg
        end,
        toggle = { Fn("ToggleFriendsFrame") },
    },
    guild = {
        frames = { "CommunitiesFrame", "GuildFrame" },
        toggle = { Fn("ToggleGuildFrame", NoArgs) },
    },
    raid = {
        frames = { "RaidFrame" },
        toggle = { Fn("ToggleRaidFrame", NoArgs) },
    },
    -- Schlachtzugsinformationen (Freunde → Schlachtzug → Schlachtzugsinformationen), vorher ezPanel
    raidinfo = {
        frames = { "RaidInfoFrame" },
        toggle = { function()
            local toggle = rawget(_G, "ToggleRaidFrame")
            if type(toggle) ~= "function" then return nil end
            if not Run(toggle) then return false end
            local info = rawget(_G, "RaidInfoFrame")
            if FrameVisible("RaidFrame") and FrameVisible("RaidInfoFrame") == false and type(info.Show) == "function" then
                return Run(info.Show, info)
            end
            return true
        end },
        open = { function()
            local toggle = rawget(_G, "ToggleRaidFrame")
            if type(toggle) ~= "function" then return nil end
            if not FrameVisible("RaidFrame") and not Run(toggle) then return false end
            local info = rawget(_G, "RaidInfoFrame")
            if FrameVisible("RaidFrame") and FrameVisible("RaidInfoFrame") == false and type(info.Show) == "function" then
                return Run(info.Show, info)
            end
            return true
        end },
    },
    -- arg: nur für das alte Zauberbuch (BOOKTYPE_…). selfOnly: s. Kopf (Taint der Aktionsleisten; Öffnen: OPEN_SELF_ONLY)
    spellbook = {
        selfOnly = "TOGGLESPELLBOOK",
        frames = { "PlayerSpellsFrame.SpellBookFrame", "SpellBookFrame" },
        panel = { "PlayerSpellsFrame", "SpellBookFrame" },
        toggle = { Fn("PlayerSpellsUtil.ToggleSpellBookFrame", NoArgs), Fn("ToggleSpellBook", function(arg)
            local book = arg or rawget(_G, "BOOKTYPE_SPELL")
            if book == nil then return false end
            return book
        end) },
        open = { Fn("PlayerSpellsUtil.OpenToSpellBookTab", NoArgs) },
    },
    -- selfOnly: s. Kopf. busy: ist eines davon offen, schaltet „open“ nicht auf die Talente um (Panels.SelfOpen)
    talents = {
        selfOnly = "TOGGLETALENTS",
        busy = { "PlayerSpellsFrame", "ClickBindingFrame" },
        frames = { "PlayerSpellsFrame.TalentsFrame", "PlayerTalentFrame", "ClassTalentFrame" },
        panel = { "PlayerSpellsFrame", "PlayerTalentFrame", "ClassTalentFrame" },
        toggle = { Fn("PlayerSpellsUtil.ToggleClassTalentFrame", NoArgs), Fn("ToggleTalentFrame", NoArgs) },
    },
    -- Berufe: Blizzards Berufebuch, sonst der Fertigkeiten-Reiter, sonst das alte Zauberbuch (vorher ezPanel)
    professions = {
        frames = { "ProfessionsBookFrame", "SkillFrame" },
        panel = { "ProfessionsBookFrame", "CharacterFrame" },
        toggle = {
            Fn("ToggleProfessionsBook", NoArgs),
            Fn("ToggleCharacter", function()
                if rawget(_G, "SkillFrame") == nil then return false end
                return "SkillFrame"
            end),
            Fn("ToggleSpellBook", function()
                local book = rawget(_G, "BOOKTYPE_PROFESSION")
                if book == nil then return false end
                return book
            end),
        },
    },
    macro = {
        frames = { "MacroFrame" },
        load = function()
            local loadUI = rawget(_G, "MacroFrame_LoadUI")
            if type(loadUI) == "function" then pcall(loadUI) else Core.LoadAddOn("Blizzard_MacroUI") end
        end,
        open = { Fn("ShowMacroFrame", NoArgs), ShowFrame("MacroFrame") },
    },
    -- Blizzards Klick-Zauber (Optionen → Tastaturbelegung → Klick-Zauber); Daten dazu: Core.ClickBindings
    clickbindings = {
        selfOnly = "TOGGLESPELLBOOK",   -- öffnet das Zauberbuch mit (Spielbefund vom 23.11.2026)
        frames = { "ClickBindingFrame" },
        load = function()
            local loadUI = rawget(_G, "ClickBindingFrame_LoadUI")
            if type(loadUI) == "function" then pcall(loadUI) else Core.LoadAddOn("Blizzard_ClickBindingUI") end
        end,
        toggle = {
            Fn("ToggleClickBindingFrame", NoArgs), Fn("ClickBindingFrame_Toggle", NoArgs),
            function()
                local frame = Global("ClickBindingFrame")
                if type(frame) ~= "table" then return nil end
                if FrameVisible("ClickBindingFrame") then return HideFrame(frame) end
                return ShowFrame("ClickBindingFrame")()
            end,
        },
    },
    calendar = {
        frames = { "CalendarFrame" },
        load = function() Core.LoadAddOn("Blizzard_Calendar") end,
        toggle = { Fn("ToggleCalendar", NoArgs), Fn("Calendar_Toggle", NoArgs) },
    },
    -- Blizzards Uhr mit Wecker und Stoppuhr
    clock = {
        frames = { "TimeManagerFrame" },
        load = function() Core.LoadAddOn("Blizzard_TimeManager") end,
        toggle = { Fn("TimeManager_Toggle", NoArgs) },
    },
    questlog = {
        frames = { "QuestLogFrame", "QuestMapFrame" },
        panel = { "QuestLogFrame", "WorldMapFrame" },
        toggle = { Fn("ToggleQuestLog", NoArgs) },
    },
    groupfinder = {
        frames = { "LFGParentFrame", "PVEFrame" },
        toggle = { Fn("ToggleGroupFinderFrame", NoArgs), Fn("ToggleLFGParentFrame", NoArgs), Fn("PVEFrame_ToggleFrame", NoArgs) },
    },
    achievements = {
        frames = { "AchievementFrame" },
        toggle = { Fn("ToggleAchievementFrame", NoArgs) },
    },
    -- Würfel-Verlauf
    loothistory = {
        frames = { "GroupLootHistoryFrame", "LootHistoryFrame" },
        toggle = { Fn("ToggleLootHistoryFrame", NoArgs) },
    },
    -- arg: Nummer des Reiters
    collections = {
        frames = { "CollectionsJournal" },
        toggle = { Fn("ToggleCollectionsJournal") },
        open = { Fn("SetCollectionsJournalShown", function(arg) return true, arg end) },
        -- eigener Schritt: Fn() kann false nicht als Wert weiterreichen (false heißt dort „Schritt passt nicht“)
        close = { function()
            local fn = Global("SetCollectionsJournalShown")
            if type(fn) ~= "function" then return nil end
            return Run(fn, false)
        end },
    },
    -- arg: Kategorie – ID, Kurzname ("social", "keybindings") oder Kategorie-Tabelle; ohne arg nur das Fenster
    settings = {
        frames = { "SettingsPanel" },
        open = {
            function(arg)
                if arg == nil then return nil end
                local settings = rawget(_G, "Settings")
                local open = type(settings) == "table" and settings.OpenToCategory
                if type(open) ~= "function" then return nil end
                local id = SettingsID(arg)
                if id == nil or id == false then return nil end
                return Run(open, id)
            end,
            function(arg)
                if arg ~= nil then return nil end
                if FrameVisible("SettingsPanel") then return true end
                return ShowFrame("SettingsPanel")()
            end,
        },
        -- Schließen (Nachlauf zum Review von PR 536): SettingsPanelMixin:Close übernimmt alle Änderungen
        -- (ExitWithCommit → Commit: CommitSettings, CommitBindings) bzw. zeigt Blizzards StaticPopup
        -- GAME_SETTINGS_CONFIRM_DISCARD (Gethe/wow-ui-source, Zweig forever,
        -- Blizzard_Settings_Shared/Blizzard_SettingsPanel.lua) – aus Addon-Code liefe beides im Addon-Pfad, das ist nicht
        -- taint-sicher (Leitlinie 5). Darum: Stehen Änderungen an (self.modified oder HasUnappliedSettings, nur gelesen),
        -- bleibt das Fenster offen ("pending") – entscheiden muss der Spieler mit Blizzards eigenen Knöpfen. Sonst gibt
        -- es nichts zu übernehmen, und das Fenster geht wie jedes andere über HideUIPanel zu (Schritt nil).
        close = { function()
            if not FrameVisible("SettingsPanel") then return true end
            if Panels.SettingsPending() then return "pending" end
            return nil
        end },
    },
    -- Blizzards Optionen der Raidrahmen (Einstellungen » Interface » Schlachtzugsrahmen; HL-09): eingehende Heilung,
    -- Absorption, Aggro, bannbare Debuffs – was Blizzards Rahmen selbst zeigen. Der Weg ist der des Zahnrads an
    -- Blizzards Raidleiste (Settings.OpenToCategory mit der Kategorie „Interface“ und dem Abschnitt
    -- RAID_FRAMES_LABEL; am Forever-Client zu bestätigen). Kennt der Client den Abschnitt nicht, öffnet die Kategorie,
    -- sonst das Einstellungsfenster.
    raidframes = {
        frames = { "SettingsPanel" },
        open = {
            function()
                local settings = rawget(_G, "Settings")
                local open = type(settings) == "table" and settings.OpenToCategory
                local id = type(settings) == "table" and settings.INTERFACE_CATEGORY_ID
                if type(open) ~= "function" or Core.IsSecret(id) or id == nil then return nil end
                local label = Core.Plain(rawget(_G, "RAID_FRAMES_LABEL"))
                if type(label) == "string" and label ~= "" then return Run(open, id, label) end
                return Run(open, id)
            end,
            function()
                if FrameVisible("SettingsPanel") then return true end
                return ShowFrame("SettingsPanel")()
            end,
        },
    },
    -- Blizzards Kampf-Optionen (Einstellungen » Gameplay » Kampf; Forever-Quelle Blizzard_SettingsDefinitions_Frame/
    -- Combat.lua: Settings.RegisterVerticalLayoutCategory(COMBAT_LABEL)) – dort stellt der Spieler „Selbstwirken“ um
    -- (ezHeal, Fehler vom 23.11.2026). arg: Name einer globalen Textkonstante für die Zeile, bis zu der Blizzards Liste
    -- rollt (z. B. "SELF_CAST"; Settings.OpenToCategory mit scrollToElementName). Die Kategorie hat keine ID-Konstante:
    -- Sie wird über ihren Namen gesucht (SettingsIDByName). Kennt der Client sie nicht, öffnet das Einstellungsfenster.
    combat = {
        frames = { "SettingsPanel" },
        open = {
            function(arg)
                local settings = rawget(_G, "Settings")
                local open = type(settings) == "table" and settings.OpenToCategory
                local id = SettingsIDByName(rawget(_G, "COMBAT_LABEL"))
                if type(open) ~= "function" or id == nil then return nil end
                local row = type(arg) == "string" and Core.Plain(rawget(_G, arg)) or nil
                if type(row) == "string" and row ~= "" then return Run(open, id, row) end
                return Run(open, id)
            end,
            function()
                if FrameVisible("SettingsPanel") then return true end
                return ShowFrame("SettingsPanel")()
            end,
        },
    },
    -- Der offene Brief im Postfenster: nur schließen (öffnen kann ihn nur ein Klick im Posteingang)
    openmail = {
        frames = { "OpenMailFrame" },
        closeOnly = true,
    },
}

---------------------------------------------------------------------------
-- Offen? Öffnen, schließen, umschalten
---------------------------------------------------------------------------

local function Shown(def, arg)
    if def.shown then return def.shown(arg) end
    local known
    for _, name in ipairs(def.frames or {}) do
        local visible = FrameVisible(name)
        if visible then return true end
        if visible == false then known = false end
    end
    return known
end

local function Load(def)
    if not def.load then return end
    for _, name in ipairs(def.frames or {}) do
        if Global(name) ~= nil then return end
    end
    pcall(def.load)
end

local Open, Close

function Open(def, arg, noToggle)
    if def.closeOnly then return nil end
    Load(def)
    local result = Steps(def.open, arg)
    if result ~= nil then return result end
    if def.open and not def.toggle then return nil end
    if Shown(def, arg) then return true end
    if noToggle then return nil end
    return Steps(def.toggle, arg)
end

function Close(def, arg, noToggle)
    local result = Steps(def.close, arg)
    if result ~= nil then return result end
    local shown = Shown(def)
    if not shown then return true end   -- zu, oder das Fenster gibt es (noch) nicht
    -- Nur das oberste Fenster verstecken: HideUIPanel auf einen Unterrahmen (Reiter) ließe das Fenster leer offen.
    for _, name in ipairs(def.panel or def.frames or {}) do
        if FrameVisible(name) then
            local hidden = HideFrame(Global(name))
            if hidden ~= nil then return hidden end
        end
    end
    if shown and not noToggle then return Steps(def.toggle, arg) end
    return nil
end

local function Toggle(def, arg)
    if def.closeOnly then return Close(def, arg, true) end
    Load(def)
    local result = Steps(def.toggle, arg)
    if result ~= nil then return result end
    if Shown(def, arg) then return Close(def, arg, true) end
    return Open(def, arg, true)
end

local MODES = { open = Open, close = Close, toggle = Toggle }

local function Definition(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return nil end
    return Panels.LIST[name:lower()]
end

-- Die bekannten Namen, sortiert (für Status und Doku).
function Panels.Names()
    local names = {}
    for name in pairs(Panels.LIST) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function Panels.Known(name)
    return Definition(name) ~= nil
end

-- Oberste Rahmen eines Fensters (panel, sonst frames) – woran ein Teil hängt, das am ganzen Fenster steht (Einführung,
-- Intro.WINDOWS: eine Quelle statt einer zweiten Liste). → neue Liste (leer, wenn der Name unbekannt ist)
function Panels.Frames(name)
    local def = Definition(name)
    local out = {}
    for _, frame in ipairs(def and (def.panel or def.frames) or {}) do out[#out + 1] = frame end
    return out
end

-- Ist das Fenster offen (mit arg: auf diesem Reiter)? true/false, nil = unbekannt (Name oder Rahmen fehlt).
function Core.PanelShown(name, arg)
    local def = Definition(name)
    if not def then return nil end
    if Core.IsSecret(arg) then arg = nil end
    local ok, shown = pcall(Shown, def, arg)
    if not ok then return nil end
    return shown
end

-- Versuch vom 23.11.2026 (Entscheidung des Nutzers: „stop. können wir nicht kurz probieren, zauber-buch klickbelegung
-- speichern und schluss. ohne erneut öffnen? beim ezmacro genausao?“): Zauberbuch und Klick-Zauber dürfen aus
-- Addon-Code wieder öffnen (Knöpfe von ezMacro und ezHeal). true sperrt auch das Öffnen wieder (Stand von PR 732), falls
-- die Aktionsleisten im Spieltest doch verschwinden.
Panels.OPEN_SELF_ONLY = false

-- Schließt der Spieler dieses Fenster selbst (selfOnly, s. Kopf)? → true/false. Aufrufer, die Zauberbuch, Talente oder
-- Klick-Zauber von sich aus schließen oder neu öffnen (nach dem Speichern), lassen es dann – das Öffnen auf einen
-- Knopf hin regelt Panels.OPEN_SELF_ONLY.
function Panels.SelfOnly(name)
    local def = Definition(name)
    return def ~= nil and def.selfOnly ~= nil
end

-- Steht ein Fenster offen, in dem dieses nur ein Reiter ist (def.busy)? Gefragt ist IsShown, also auch bei ausgeblendeter
-- Oberfläche. → "own" (auf diesem Reiter), "other" (auf einem anderen: öffnen hieße umschalten), nil (zu oder ohne busy).
-- Nennt ein vorhandener Rahmen seinen Stand nicht (gesperrter Wert, Fehler), gilt er als offen: lieber nicht umschalten.
function Panels.SelfOpen(name)
    local def = Definition(name)
    local open = false
    for _, frame in ipairs(def and def.busy or {}) do
        open = open or FrameOpen(frame) == true or (FrameOpen(frame) == nil and type(Global(frame)) == "table")
    end
    if not open then return nil end
    -- Der Reiter zählt nur mit seinem obersten Rahmen: IsShown bleibt am Reiter wahr, wenn das Fenster zu ist
    local top, own = false, false
    for _, frame in ipairs(def.panel or {}) do top = top or FrameOpen(frame) == true end
    for _, frame in ipairs(def.frames or {}) do own = own or FrameOpen(frame) == true end
    return top and own and "own" or "other"
end

-- Wie der Spieler das Fenster selbst öffnet: „Taste N“ aus Blizzards Tastenbelegung, ohne Taste „über das Mikromenü“.
-- → Text | nil (kein Fenster mit selfOnly)
function Panels.SelfWay(name)
    local def = Definition(name)
    if not (def and def.selfOnly) then return nil end
    local key
    local getKey = rawget(_G, "GetBindingKey")
    if type(getKey) == "function" then
        local ok, value = pcall(getKey, def.selfOnly)
        if ok and type(value) == "string" and not Core.IsSecret(value) and value ~= "" then
            local text = rawget(_G, "GetBindingText")
            local okText, shown = false, nil
            if type(text) == "function" then okText, shown = pcall(text, value) end
            key = okText and shown or value
            if type(key) ~= "string" or Core.IsSecret(key) then key = value end
        end
    end
    local L = Core.L
    return key and L.PANEL_SELF_KEY:format(key) or L.PANEL_SELF_NOKEY
end

-- Hinweis für Fenster, die der Spieler selbst öffnet, mit dem Weg (Panels.SelfWay). → Text | nil
function Panels.SelfHint(name)
    local def, way = Definition(name), Panels.SelfWay(name)
    if not way then return nil end
    local L = Core.L
    local what = L.PANEL_SELF_BOOK
    if def == Panels.LIST.clickbindings then what = L.PANEL_SELF_CLICK end
    if def == Panels.LIST.talents then what = L.PANEL_SELF_TALENTS end
    return what:format(way)
end

-- Blizzard-Fenster öffnen. opts: nil | "open" | "toggle" | "close" | true (ohne Hinweis) | { mode, quiet }.
-- Rückgabe: true, oder false und der Grund: "unknown" (Name/Variante), "combat", "missing" (der Client
-- hat keinen Weg dafür), "error" (Blizzards Funktion meldete einen Fehler; steht in der Fehlerliste).
function Core.OpenPanel(name, arg, opts)
    local mode, quiet = "open", false
    if type(opts) == "string" then
        mode = opts
    elseif type(opts) == "table" then
        mode, quiet = opts.mode or "open", opts.quiet and true or false
    elseif opts == true then
        quiet = true
    end
    local def, action = Definition(name), MODES[mode]
    if not def or not action then return false, "unknown" end
    if Core.IsSecret(arg) then arg = nil end
    if Core.InCombat() then
        -- Eine Einstellungsseite (Kategorie-Tabelle) öffnen wollen: wie jeder andere Weg Hinweis im Chat und nach dem
        -- Kampf nachholen (ST-04, Core.OpenSettingsCategory) – so auch ezAuctions ns.OpenSettings.
        if name == "settings" and mode == "open" and type(arg) == "table" and type(arg.GetID) == "function"
            and Core.OpenSettingsCategory then
            Core.OpenSettingsCategory(arg)
            return false, "combat"
        end
        if not quiet then Core.CombatNotice(nil, Core.L.PANEL_WHAT, nil, { center = true, chat = false }) end
        return false, "combat"
    end
    -- Zauberbuch, Talente und Klick-Zauber: nie aus Addon-Code schließen oder umschalten (Kopf, „selfOnly“); öffnen nur,
    -- solange Panels.OPEN_SELF_ONLY aus ist (Versuch vom 23.11.2026) und das Fenster nicht schon auf einem anderen Reiter
    -- steht
    if def.selfOnly and (mode ~= "open" or Panels.OPEN_SELF_ONLY or Panels.SelfOpen(name) == "other") then
        if not quiet then Core.Print(Core.TITLE, Panels.SelfHint(name)) end
        return false, "self"
    end
    -- Offen, aber bei ausgeblendeter Oberfläche (Alt+Z) nicht sichtbar: „open“ fiele sonst auf die Liste toggle zurück
    -- und schlösse das Fenster (Klick-Zauber samt Zauberbuch) aus Addon-Code (Review vom 23.11.2026)
    if def.selfOnly then
        for _, frameName in ipairs(def.panel or def.frames or {}) do
            if FrameOpen(frameName) == true and FrameVisible(frameName) ~= true then return true end
        end
    end
    local ok, result = pcall(action, def, arg)
    if not ok then
        Core.Error(ADDON, result, "OpenPanel")
        return false, "error"
    end
    if result == true then return true end
    if type(result) == "string" then return false, result end   -- eigener Grund eines Schritts ("pending")
    return false, result == nil and "missing" or "error"
end

function Core.TogglePanel(name, arg, quiet)
    return Core.OpenPanel(name, arg, { mode = "toggle", quiet = quiet })
end

function Core.ClosePanel(name, arg, quiet)
    return Core.OpenPanel(name, arg, { mode = "close", quiet = quiet })
end

---------------------------------------------------------------------------
-- Chat-Eingabe mit Text öffnen (vorher je selbst in ezMap/Way.lua und ezPanel/Blocks/Location.lua)
---------------------------------------------------------------------------

local function ChatFn(utilName, globalName)
    local util = rawget(_G, "ChatFrameUtil")
    local fn = type(util) == "table" and util[utilName] or nil
    if type(fn) ~= "function" then fn = rawget(_G, globalName) end
    return type(fn) == "function" and fn or nil
end

-- Wohin ginge ein Link aus Blizzards Umschalt+Klick (HandleModifiedItemClick → InsertLink)? Das offene
-- Chat-Eingabefeld oder ein anderes Eingabefeld mit Fokus (Makrotext, Suchfelder …). → Eingabefeld oder nil
function Core.LinkInput()
    local active = Core.Call(ChatFn("GetActiveWindow", "ChatEdit_GetActiveWindow"))
    if active ~= nil then return active end
    return Core.Call(rawget(_G, "GetCurrentKeyBoardFocus"))
end

-- Text in die Chatzeile: in ein offenes Eingabefeld einfügen, sonst die Eingabe mit dem Text öffnen.
-- asLink (oder ein Text mit „|H“): zuerst Blizzards Link-Einfügen (wie Umschalt-Klick, auch ins Makrofeld).
-- Gesendet wird nie. Rückgabe: true, "link" | "insert" | "open" – oder false, "empty" | "locked" | "missing".
function Core.OpenChatWith(text, asLink)
    if type(text) ~= "string" or Core.IsSecret(text) or text == "" then return false, "empty" end
    if Core.ChatLocked() then return false, "locked" end
    if asLink or text:find("|H", 1, true) then
        local insertLink = ChatFn("InsertLink", "ChatEdit_InsertLink")
        if insertLink then
            local ok, done = pcall(insertLink, text)
            if ok and not Core.IsSecret(done) and done then return true, "link" end
        end
    end
    local active = ChatFn("GetActiveWindow", "ChatEdit_GetActiveWindow")
    if active then
        local ok, edit = pcall(active)
        if ok and type(edit) == "table" and type(edit.Insert) == "function" and pcall(edit.Insert, edit, text) then
            return true, "insert"
        end
    end
    local open = ChatFn("OpenChat", "ChatFrame_OpenChat")
    if open and pcall(open, text) then return true, "open" end
    return false, "missing"
end
