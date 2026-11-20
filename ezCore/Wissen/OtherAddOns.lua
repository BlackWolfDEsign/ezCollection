local _, ns = ...
local Core = ezCore

--[[
    Fremde Addons an einer Stelle erkennen (Leitlinie 9: läuft ein Addon, das dieselbe Funktion schon
    erledigt, hält sich das Modul zurück oder zeigt einen Hinweis). Vorher prüfte jedes Modul selbst mit
    IsLoaded und den gespeicherten Einstellungen des fremden Addons. Liste und Begründungen:
    docs/fremd-addons.md.

      Core.WhoHandles(funktion)          → Name des Addons, das die Funktion gerade übernimmt, sonst nil
      Core.OtherAddOn(name, funktion)    → true/false, Anzeigename   (funktion nil = nur „läuft es?“)
      Core.OtherAddOns()                 → { { key, label, features = { funktion … } } … } laufende, für /ez status
      Core.OTHER_ADDONS[name]            → Eintrag: label, folders, features = { funktion = Prüfung }
                                           Prüfung: true (immer, solange es läuft) oder function(addon) → bool

    Funktionen (Name → wer sie nutzt):
      sellJunk (ezBag, ohne ezBag ezMerchant; ausgeführt von Core.Junk)  easyDestroy (ezBag)
      repair (ezPanel, ezMerchant)  fastLoot (ezLoot)
      questAccept questTurnIn questTracker questSort questItemTooltip questTint questSparkle questShare (ezQuest;
      questShare: angenommene Quests automatisch teilen – Stand 18.11.2026 ohne bekanntes Addon, docs/fremd-addons.md)
      minimapBag infoBar (ezPanel)  mapCoords (ezMap, ohne ezMap ezPanel)  flightTimes flightPoints dungeonEntrances way minimapAutoZoom (ezMap)
      readyTimer acceptSummon acceptResurrect blockDuels blockInvites (ezSocial)
      chatFade chatHistory chatStyle chatArrows (ezChat)  spellRanks (ezMacro)
      rebuffThanks (ezBuff)  auctionTooltip (ezAuction)  mailTooltip (ezMail)  craftCost (ezCraft)
      bagArrows questArrows upgradeTooltip gearSwap (ezGear)  actionBars (ezBars)  mapTrainers (ezMap)
      lootAtlas dungeonAtlas (ezLoot)
      bags (ezBag)  skillStages (ezCraft)  chatLinks chatChannelNames chatCopy chatHighlight whisperWindows (ezChat)
      chatLinkTooltip (ezChat; nur Hinweis: fremde Link-Tooltips gelten in Blizzards Chatfenstern, ezChats im eigenen)
      lfgBoard (ezSocial)  betaHints unitTooltip unitItemLevel moveFrames cameraZoom (ezCore)
      trainAll (ezMerchant)  zoneLevels rareAlerts battlegroundTimers (ezMap)  clickCast healFrames (ezHeal)
      rarePins (ezMap; Kartenpunkte seltener Gegner und Schätze – getrennt von rareAlerts, der Chat-Meldung; T5-1)
      groupBuffs (ezBuff)  damageMeter (ezCombat)  unitLoot (ezLoot)  petTrainerHint (ezMerchant)
      salvageValue (ezCraft)  pullTimer (ezMacro)  minimapShape (ezMap)
      fishing barProfiles (ezMacro)  talentTemplates (ezTalent)  slotLevels (ezGear)  itemSource (ezCore)
      clickLegend (ezHeal)  bookPins (ezMap)  questItemSource (ezCore)  auctionScan (ezCore, Prices.ScanYields)
      unitQuestLines (ezCore; ein Addon hängt eigene Quest-Blöcke an NPC-Tooltips – ezCores Einheiten-Pipeline setzt
        die Abschnitte der Module dann dahinter, S-1811-Tooltipabstand)
      gatherPins (ezMap; Sammel-Fundorte auf Karte und Minikarte – ezCore zählt still weiter)

      Core.OtherAddOnKeyHeld(funktion)   → true/false, Anzeigename: hält der Spieler gerade die Taste, mit der das
                                           übernehmende Addon seine Anzeige zeigt? nil, wenn niemand die Funktion
                                           übernimmt oder das Addon dafür keine Taste braucht (Feld keys am Eintrag)
      Nachricht OTHER_ADDONS_CHANGED (addon, ereignis): ein fremdes Addon sagt erst später, was es übernimmt (heute
                                           Forever++ nach READY und bei Änderungen). Wer bei PLAYER_LOGIN nach
                                           WhoHandles entschieden hat, wendet dann neu an.
    Nur gelesen wird: ob das Addon geladen ist, seine gespeicherten Einstellungen oder seine öffentliche Schnittstelle.
    Nichts wird geändert, nichts an seine Tasten gebunden.
    Jede Prüfung liest bei jedem Aufruf frisch – nichts wird zwischengespeichert, ein umgelegter Schalter des
    fremden Addons gilt sofort.
]]

local function DB(name)
    local db = rawget(_G, name)
    return type(db) == "table" and db or nil
end

-- Pawn: Schalter in PawnCommon, Standard an.
local function PawnOption(key)
    return function()
        local common = DB("PawnCommon")
        return common == nil or common[key] ~= false
    end
end

-- Leatrix Plus speichert jeden Schalter als "On"/"Off" in LeaPlusDB.
local function Lea(key)
    return function()
        local db = DB("LeaPlusDB")
        return db ~= nil and db[key] == "On"
    end
end

-- SexyMap: Einstellungen je Charakter in SexyMap2DB["Vorname Nachname"] (Forever) bzw. ["Name-Realm"], oder dort
-- "global" (dann SexyMap2DB.global); darin .core.autoZoom = Sekunden bis zum Herauszoomen, Standard 5, 0 = aus
-- (Quelltext funkydude/SexyMap, SexyMap.lua; Anfrage von ezMap 13.11.2026).
local function SexyMapProfile()
    local db = DB("SexyMap2DB")
    if not db then return nil end
    local ok, key = pcall(function()
        if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
            local name, surname = UnitNameUnmodified("player")
            return name .. " " .. surname
        end
        return UnitNameUnmodified("player") .. "-" .. GetRealmName()
    end)
    if not ok or type(key) ~= "string" or Core.IsSecret(key) then return nil end
    local profile = db[key]
    if profile == "global" then profile = db.global end
    return type(profile) == "table" and profile or nil
end

local function SexyMapAutoZoom()
    local profile = SexyMapProfile()
    local core = profile and profile.core
    local seconds = type(core) == "table" and tonumber(core.autoZoom) or nil
    return seconds == nil or seconds > 0
end

-- Tweaks Forever (cjber; ein anderes Addon als Forever Tweaks): je Schalter ein Schlüssel in TweaksForeverDB.
-- Fehlt der Schlüssel oder die ganze Tabelle, gilt der Standard des Addons – hier stehen nur die Schalter, die
-- ab Werk an sind (alle anderen: aus). Quelle: sein Quelltext, gelesen am 13.11.2026 (petTrainerHint: seine Datei
-- UI/PetTrainer.lua, Schlüssel und Standard an).
local TWEAKS_ON_BY_DEFAULT = {
    repair = true, sellJunk = true, mapCoords = true, zoneLevels = true, moveWindows = true, retailTooltips = true,
    fastLoot = true, questDistance = true, foreverQuests = true, dungeonEntrances = true, petTrainerHint = true,
}

local function TweaksOn(key)
    local db = DB("TweaksForeverDB")
    local value = db and rawget(db, key)
    if value == nil then return TWEAKS_ON_BY_DEFAULT[key] == true end
    return value ~= false
end

local function Tweaks(key)
    return function() return TweaksOn(key) end
end

-- Seine Dungeon-Eingänge hängen zusätzlich an Blizzards CVar „showDungeonEntrancesOnMap“ ("0" = aus).
local function TweaksDungeonEntrances()
    if not TweaksOn("dungeonEntrances") then return false end
    local ok, value = pcall(Core.CVar, "showDungeonEntrancesOnMap")
    if not ok or Core.IsSecret(value) then return true end
    return not (value == "0" or value == 0 or value == false)
end

-- Forever++ (xIGBClutchIx, MIT): öffentliche Schnittstelle ForeverPlusPlusAPI.v1 laut seinem docs/api.md –
-- IsModuleEnabled(name) erst, wenn IsReady() wahr ist (nach PLAYER_LOGIN), folgt seinem Profil; nil heißt „Modul
-- gibt es nicht“. GetModuleOption(name, schlüssel) → nil für unbekannte Schlüssel. Die Modulnamen sind am Quelltext
-- belegt (15.11.2026, je Datei ns.NewModule("<Name>") unter ForeverPlusPlus/Modules). Vor IsReady gilt: übernimmt nichts.
local function FPPApi()
    local api = rawget(_G, "ForeverPlusPlusAPI")
    if type(api) ~= "table" then return nil end
    local ok, v1 = pcall(function() return api.v1 end)   -- laut seiner Doku nur lesbar; Fehler abfangen
    return ok and type(v1) == "table" and v1 or nil
end

local function FPP(module, option)
    return function()
        local v1 = FPPApi()
        if not v1 then return false end
        local okReady, ready = pcall(v1.IsReady)
        if not (okReady and ready == true) then return false end
        local okOn, on = pcall(v1.IsModuleEnabled, module)
        if not (okOn and on == true) then return false end
        if option then
            local okOpt, value = pcall(v1.GetModuleOption, module, option)
            if okOpt and value == false then return false end
        end
        return true
    end
end

-- Forever++ QuestTracker gestaltet Blizzards Verfolgung um, ersetzt sie aber nicht (darum questSort, nicht
-- questTracker); nach Stufe sortiert es nur mit seiner Option sort = "low" oder "high" (Standard "off"). Belegt an
-- seinem Quelltext (Modules/Quests/QuestTracker.lua, 15.11.2026).
local function FPPSortsTracker()
    if not FPP("QuestTracker")() then return false end
    local v1 = FPPApi()
    local ok, value = pcall(v1.GetModuleOption, "QuestTracker", "sort")
    return ok and (value == "low" or value == "high")
end

-- Forever++ antwortet erst nach seinem Rückruf READY (nach PLAYER_LOGIN); wer bei PLAYER_LOGIN entscheidet (etwa
-- ezMap bei der Form der Minikarte, ezCore bei „Blizzard-Fenster verschieben“), hört OTHER_ADDONS_CHANGED und wendet
-- neu an. Ebenso nach MODULE_TOGGLED, OPTION_CHANGED und PROFILE_CHANGED. Nur seine öffentlichen Rückrufe
-- (RegisterCallback(event, fn, owner) laut seinem docs/api.md), in pcall; nichts wird geschrieben.
local FPP_EVENTS = { "READY", "MODULE_TOGGLED", "OPTION_CHANGED", "PROFILE_CHANGED" }
local fppOwner, fppWatching = {}, false

local function FPPChanged(event) Core.Fire("OTHER_ADDONS_CHANGED", "ForeverPlusPlus", event) end

local function WatchFPP()
    if fppWatching then return end
    local v1 = FPPApi()
    if not (v1 and type(v1.RegisterCallback) == "function") then return end
    fppWatching = true
    for _, event in ipairs(FPP_EVENTS) do pcall(v1.RegisterCallback, event, FPPChanged, fppOwner) end
    -- READY schon vorbei (seine Doku verspricht keine Wiederholung): gleich einmal melden
    local ok, ready = pcall(v1.IsReady)
    if ok and ready == true then FPPChanged("READY") end
end

ns.On("ADDON_LOADED", function(_, name) if name == "ForeverPlusPlus" then WatchFPP() end end)
ns.On("PLAYER_LOGIN", WatchFPP)

-- Tnny's Mob Loot (GPL-3.0): TnnysMobLootDB.settings.key = "ALT", "CTRL" oder "SHIFT" (Standard "ALT"); seine
-- Hover-Liste erscheint, solange diese Taste über einem Gegner gehalten wird, „Drops from“ im Gegenstands-Tooltip
-- steht in settings.dropsFrom ("ALWAYS" Standard, "KEY", "OFF"). Belegt an seinem Quelltext (TnnysMobLoot.lua,
-- DEFAULTS und KeyDown), 15.11.2026.
local function TnnySettings()
    local db = DB("TnnysMobLootDB")
    local settings = db and rawget(db, "settings")
    return type(settings) == "table" and settings or nil
end

local TNNY_KEYS = { ALT = "IsAltKeyDown", CTRL = "IsControlKeyDown", SHIFT = "IsShiftKeyDown" }

local function TnnyKeyHeld()
    local settings = TnnySettings()
    local key = settings and settings.key
    if key == nil then key = "ALT" end
    local down = TNNY_KEYS[key] and rawget(_G, TNNY_KEYS[key])
    if type(down) ~= "function" then return false end
    return down() and true or false
end

-- Questie: gelesen werden nur vier Schalter aus Questie.db.profile (AceDB), je mit Herkunft (Gesamtreview 18.11.2026,
-- T5-6 d; nachgesehen am 19.11.2026 in Questie 12.9.0, TOC Questie_Forever.toc, Interface 16001). Lizenz zuerst
-- gelesen: LICENSE.md erlaubt laut Questie-Team Forks und Kopien unter GPLv3, im Zweifel gilt „alle Rechte
-- vorbehalten“ – hier steht kein Code von Questie, nur die Namen der Schalter als Fakten. Jeder Schalter ist im Spiel
-- in Questies eigenem Optionsfenster sichtbar (/questie):
--   autoAccept.enabled  Reiter „Auto“, „Auto Accept Quests“   (Modules/Options/AutoTab/QuestieOptionsAuto.lua)
--   autocomplete        Reiter „Auto“, „Auto Complete Quests“ (ebenda)
--   trackerEnabled      Reiter „Tracker“, „Enable Tracker“    (Modules/Options/TrackerTab/QuestieOptionsTracker.lua)
--   enableTooltips      Reiter „General“, „Enable World Tooltips“ (Modules/Options/GeneralTab/QuestieOptionsGeneral.lua)
-- Vorgaben ab Werk in Modules/Options/QuestieOptionsDefaults.lua (enableTooltips an, autocomplete aus, trackerEnabled
-- an). Fehlt ein Schalter (Questie benennt ihn um), gelten die drei ersten als aus und enableTooltips wie Questies
-- Vorgabe als an – kein Fehler.
local function QuestieProfile()
    local questie = rawget(_G, "Questie")
    local db = type(questie) == "table" and rawget(questie, "db")
    local ok, profile = pcall(function() return db and db.profile end)
    return ok and type(profile) == "table" and profile or nil
end

Core.OTHER_ADDONS = {
    LeatrixPlus = { label = "Leatrix Plus", folders = { "Leatrix_Plus" }, features = {
        sellJunk = Lea("AutoSellJunk"), repair = Lea("AutoRepairGear"), easyDestroy = Lea("EasyItemDestroy"),
        fastLoot = Lea("FasterLooting"), questAccept = Lea("AutomateQuests"),
        questTurnIn = function()
            local db = DB("LeaPlusDB")
            return db ~= nil and db.AutomateQuests == "On" and db.AutoQuestCompleted ~= "Off"
        end,
        minimapBag = function()
            local db = DB("LeaPlusDB")
            return db ~= nil and db.MinimapModder == "On" and db.MinimapButtonBag == "On"
        end,
        flightTimes = Lea("ShowFlightTimes"), readyTimer = Lea("ShowReadyTimer"),
        acceptSummon = Lea("AutoAcceptSummon"), acceptResurrect = Lea("AutoAcceptRes"),
        blockDuels = Lea("NoDuelRequests"), blockInvites = Lea("NoPartyInvites"),
        unitTooltip = Lea("TipModEnable"),
        chatFade = Lea("NoChatFade"), chatArrows = Lea("UseArrowKeysInChat"),
        cameraZoom = Lea("MaxCameraZoom"),   -- „Max camera zoom“: cameraDistanceMaxZoomFactor 2,6 (aus: 1,9)
    } },
    LeatrixMaps = { label = "Leatrix Maps", folders = { "Leatrix_Maps" }, features = {
        mapCoords = function()
            local db = DB("LeaMapsDB")
            return db ~= nil and db.ShowCoords == "On"
        end,
        -- „Show dungeons and raids“ und „Show zone levels“ (Schlüsselnamen im Spiel bestätigen)
        dungeonEntrances = function()
            local db = DB("LeaMapsDB")
            return db ~= nil and db.ShowDungeonIcons == "On"
        end,
        zoneLevels = function()
            local db = DB("LeaMapsDB")
            return db ~= nil and db.ShowZoneLevels == "On"
        end,
    } },
    TweaksForever = { label = "Tweaks Forever", folders = { "TweaksForever" },
        url = "https://www.curseforge.com/wow/addons/tweaks-forever", features = {
        questAccept = Tweaks("quests"), questTurnIn = Tweaks("quests"),
        repair = Tweaks("repair"), sellJunk = Tweaks("sellJunk"), trainAll = Tweaks("trainAll"),
        mapCoords = Tweaks("mapCoords"), zoneLevels = Tweaks("zoneLevels"), cameraZoom = Tweaks("cameraZoom"),
        moveFrames = Tweaks("moveWindows"), unitTooltip = Tweaks("retailTooltips"), fastLoot = Tweaks("fastLoot"),
        acceptSummon = Tweaks("summons"), acceptResurrect = Tweaks("resurrections"),
        blockDuels = Tweaks("declineDuels"), blockInvites = Tweaks("partyStrangers"),
        questSort = Tweaks("questDistance"), questTint = Tweaks("foreverQuests"),
        dungeonEntrances = TweaksDungeonEntrances, rareAlerts = Tweaks("rareAlerts"),
        chatHistory = Tweaks("chatHistory"), chatChannelNames = Tweaks("chatShortNames"),
        chatLinks = Tweaks("chatWebLinks"), whisperWindows = Tweaks("chatWhisperTabs"),
        -- Hinweis beim Tierausbilder des Jägers (sein „Pet trainer hint“); sein Abdunkeln in der Wildtierausbildung
        -- („beastTrainingKnown“) wirkt in einem anderen Fenster als ezMerchant und wird nicht abgefragt
        petTrainerHint = Tweaks("petTrainerHint"),
    } },
    -- Forever Tweaks hat keine Schalter: was es kann, ist an, solange es läuft. Verkaufen, Reparieren und
    -- Lebenspunkte im Tooltip hat es im September 2026 entfernt (Quelltext ivribalko/wow-forever-tweaks).
    ForeverTweaks = { label = "Forever Tweaks", folders = { "ForeverTweaks" }, features = {
        questSort = true, chatFade = true, chatHistory = true, chatStyle = true, spellRanks = true,
        betaHints = true,
        flightPoints = function() return rawget(_G, "ForeverTweaksFlightPointsEnabled") ~= false end,
        dungeonEntrances = function() return rawget(_G, "ForeverTweaksDungeonEntrancesEnabled") ~= false end,
    } },
    Questie = { label = "Questie", folders = { "Questie" }, url = "https://www.curseforge.com/wow/addons/questie", features = {
        questAccept = function()
            local p = QuestieProfile()
            return p ~= nil and type(p.autoAccept) == "table" and p.autoAccept.enabled == true
        end,
        questTurnIn = function() local p = QuestieProfile() return p ~= nil and p.autocomplete == true end,
        questTracker = function() local p = QuestieProfile() return p ~= nil and p.trackerEnabled == true end,
        questItemTooltip = function() local p = QuestieProfile() return p ~= nil and p.enableTooltips ~= false end,
        mapTrainers = true,   -- Lehrer und Stadtbewohner auf der Karte (ezMap verweist darauf)
        -- DG-17: Questies Tooltip nennt bei Quest-Gegenständen schon die Quest und ihr Ziel – dort hält sich ezCores
        -- Zeile „Herkunft laut Questie“ zurück (Gathering.lua); an allen anderen Gegenständen nicht
        questItemSource = function() local p = QuestieProfile() return p ~= nil and p.enableTooltips ~= false end,
        -- S-1811-Tooltipabstand (Gesamtreview 18.11.2026): Questie hängt Quest-Blöcke an NPC-Tooltips, im selben Bild
        -- hinter ezCores Abschnitte – die Abschnitte der Module schreiben dann einen Augenblick später ans Ende
        unitQuestLines = function() local p = QuestieProfile() return p ~= nil and p.enableTooltips ~= false end,
    } },
    -- QuestieDB (Questie-Team): die Datenbank, die Questie seit 12.0.0 mitinstalliert; läuft auch allein. Nur erkannt –
    -- abgefragt wird sie über LibQuestieDB in SourcesQuestie.lua (DG-14). Keine eigene Funktion, die ein Modul abgibt.
    QuestieDB = { label = "QuestieDB", folders = { "QuestieDB" }, features = {} },
    -- Forever Quest Tint: Ordner ForeverQuestTint laut Installationshinweis seiner Projektseite
    -- (curseforge.com/wow/addons/forever-quest-tint, 16.11.2026; Paket „Ordnernamen“, Welle 27)
    ForeverQuestTint = { label = "Forever Quest Tint", folders = { "ForeverQuestTint", "Forever_Quest_Tint" }, features = { questTint = true } },
    ForeverQuests = { label = "Forever Quests", folders = { "ForeverQuests" }, features = { questTint = true } },
    -- Attune (CixiDelmont, „All Rights Reserved“, Forever-Datei): Zugangs- und Dungeon-Questketten. Ordner Attune laut
    -- BeautifulAttune.toc (Forever, „## Interface: 16001“, „## OptionalDeps: … Attune …“; github.com/HeartOfD2/
    -- BeautifulAttune) und laut Installationshinweis der Classic-Fassung („Copy the Attune folder“, legacy-wow.com/
    -- ?p=18808), beides abgerufen am 16.11.2026 (Welle 27). Keine dokumentierte Schnittstelle: nur „läuft es?“ und
    -- „Ergänzende Addons“ in ezQuest (Entscheidung Nr. 33 vom 16.11.2026); keine Funktion, die ein Modul abgibt.
    Attune = { label = "Attune", folders = { "Attune" }, url = "https://www.curseforge.com/wow/addons/attune", features = {} },
    -- Forever Loot Sparkles (conoar, GPL-3.0): stellt das Funkeln an plünderbaren Quest-Objekten wieder her (Umriss-Modus
    -- und outlineModeShowLootEffectWhenDisabled). Ordner belegt an der Dateiliste seines Quelltexts
    -- (github.com/svengabr/ForeverLootSparkles: ForeverLootSparkles.toc im Wurzelordner, 15.11.2026); Funktion laut
    -- seiner Beschreibung auf CurseForge. Sein Code ist nicht geöffnet. ezQuest setzt dann nichts (Sparkle.lua).
    ForeverLootSparkles = { label = "Forever Loot Sparkles", folders = { "ForeverLootSparkles" },
        url = "https://www.curseforge.com/wow/addons/forever-loot-sparkles", features = { questSparkle = true } },
    -- Forever++ (Ordner ForeverPlusPlus laut seiner TOC im öffentlichen Quelltext): je Funktion sein Modul über die
    -- öffentliche Schnittstelle (FPP oben). Der Ordner „ForeverPlus“ gehört zu einem anderen Addon (ForeverPlus von
    -- Epicstrike) und steht hier nicht mehr (EC-15); dessen Ordnername ist nicht belegt, ein eigener Eintrag fehlt.
    ForeverPlusPlus = { label = "Forever++", folders = { "ForeverPlusPlus" }, url = "https://www.curseforge.com/wow/addons/foreverplusplus",
        features = {
        questTint = FPP("ForeverQuestIcons"), questAccept = FPP("AutoQuest", "accept"), questTurnIn = FPP("AutoQuest", "turnIn"),
        repair = FPP("AutoRepair"), sellJunk = FPP("AutoSellJunk"), easyDestroy = FPP("EasyDelete"), fastLoot = FPP("FastLoot"),
        spellRanks = FPP("SpellRanks"), talentTemplates = FPP("TalentPlanner"), fishing = FPP("FishingCast"),
        chatFade = FPP("PersistentChat"), chatHistory = FPP("ChatHistory"), chatCopy = FPP("ChatCopy"),
        chatArrows = FPP("ChatArrowKeys"), chatChannelNames = FPP("ShortChannelNames"), whisperWindows = FPP("WhisperWindow"),
        moveFrames = FPP("MovableWindows"), bagArrows = FPP("UpgradeArrows"), questArrows = FPP("UpgradeArrows"),
        flightTimes = FPP("FlightTimer"), way = FPP("Waypoints"), minimapShape = FPP("SquareMinimap"),
        betaHints = FPP("HideBetaFeedback"), questSort = FPPSortsTracker,
    } },
    Titan = { label = "Titan Panel", folders = { "Titan" }, features = { infoBar = true } },
    BetterBags = { label = "BetterBags", folders = { "BetterBags" }, features = { bags = true } },
    -- ClassicUI Forever: Teile einzeln abschaltbar (ForeverClassicUIDB); Standard jeweils an.
    ClassicUIForever = { label = "ClassicUI Forever", folders = { "ClassicUIForever" }, features = {
        bagStyle = function() local db = DB("ForeverClassicUIDB") return not (db and db.bags == false) end,
        bankStyle = function() local db = DB("ForeverClassicUIDB") return not (db and (db.panels == false or db.panelBank == false)) end,
        comboPoints = function() local db = DB("ForeverClassicUIDB") return not (db and db.comboPoints == false) end,
    } },
    MinimapButtonButton = { label = "MinimapButtonButton", folders = { "MinimapButtonButton" }, features = { minimapBag = true } },
    HidingBar = { label = "HidingBar", folders = { "HidingBar" }, features = { minimapBag = true } },
    InFlight = { label = "InFlight", folders = { "InFlight", "InFlight_Load" }, features = { flightTimes = true } },
    TomTom = { label = "TomTom", folders = { "TomTom" }, features = { way = true } },
    -- Auctionator: Preise im Tooltip, Anhang-Liste im Post-Tooltip, Herstellkosten im Berufefenster. Nur „läuft es?“ –
    -- seine Einstellungen werden nicht gelesen (Entscheidung des Nutzers vom 14.11.2026: „Nur öffentliche API“; die
    -- Zugriffe auf Auctionators interne Einstellungen vom 13.11.2026 sind entfernt). Ob ein Modul deshalb
    -- weicht, entscheidet es mit eigenem Schalter: ezAuction „Auch neben anderen Auktions-Addons zeigen“ (gilt auch für TradeSkillMaster), ezMail „attachYield“.
    -- auctionScan (AH-03, Welle 12): Auctionator nutzt den Komplett-Scan und damit dieselbe kontoweite Sperrzeit –
    -- ezCore startet dann keinen Scan von selbst (Prices.ScanYields). TradeSkillMaster steht darunter.
    Auctionator = { label = "Auctionator", folders = { "Auctionator" }, features = {
        auctionTooltip = true, mailTooltip = true, craftCost = true, auctionScan = true,
    } },
    -- TradeSkillMaster (Sapu94 u. a., „All Rights Reserved“; Forever-Datei auf seiner Projektseite curseforge.com/wow/
    -- addons/tradeskill-master, 16.11.2026): Preise und Entzauber-Wert im Gegenstands-Tooltip. Ordner TradeSkillMaster
    -- laut seiner Hilfe (support.tradeskillmaster.com/addon/how-do-i-fix-an-error-about-appdatalua-being-empty:
    -- „delete TradeSkillMaster and TradeSkillMaster_AppHelper“, abgerufen am 16.11.2026; Welle 27). Nur „läuft es?“ –
    -- seine Einstellungen werden nicht gelesen; ezAuction weicht nur nach eigenem Schalter (wie bei Auctionator).
    TradeSkillMaster = { label = "TradeSkillMaster", folders = { "TradeSkillMaster" },
        url = "https://www.curseforge.com/wow/addons/tradeskill-master",
        features = { auctionTooltip = true, salvageValue = true } },
    -- Pawn: Schalter in PawnCommon (Standard an; ohne gespeicherte Einstellungen gilt „an“)
    Pawn = { label = "Pawn", folders = { "Pawn" }, features = {
        bagArrows = PawnOption("ShowBagUpgradeAdvisor"), questArrows = PawnOption("ShowQuestUpgradeAdvisor"),
        upgradeTooltip = PawnOption("ShowUpgradesOnTooltips"),
    } },
    Outfitter = { label = "Outfitter", folders = { "Outfitter" }, features = { gearSwap = true } },
    -- ItemRack Universal (Bl4ut0, Public Domain, Forever-Fassung): Ordner ItemRack laut seiner Projektseite
    -- (dazu ItemRackOptions, nachladbar)
    ItemRack = { label = "ItemRack", folders = { "ItemRack" }, features = { gearSwap = true } },
    -- Winter Essentials (MIT): Itemlevel, Verzauberung und Sockel an den Plätzen des Charakterfensters; Ordner
    -- WinterEssentials laut seiner Projektseite („AddOns\WinterEssentials\WinterEssentials.toc“). Schlüssel slotLevels
    -- für ezGear (W-38, Frage 24 – Empfehlung umgesetzt, Antwort offen)
    WinterEssentials = { label = "Winter Essentials", folders = { "WinterEssentials" }, features = { slotLevels = true } },
    Manners = { label = "Manners", folders = { "Manners" }, features = { rebuffThanks = true } },
    Bartender4 = { label = "Bartender4", folders = { "Bartender4" }, features = { actionBars = true } },
    Dominos = { label = "Dominos", folders = { "Dominos" }, features = { actionBars = true } },
    -- AtlasLoot Classic Forever (Sliccer) liegt im Ordner „AtlasLootClassic“; „AtlasLoot“ ist der Ordner der Retail-Fassung.
    -- itemSource: schreibt ab Werk Herkunft, Drop-Chance und Beruf in Gegenstands-Tooltips (seine Schalter werden
    -- nicht gelesen: läuft es, gilt die Zeile als vergeben)
    AtlasLoot = { label = "AtlasLoot", folders = { "AtlasLootClassic", "AtlasLoot" }, features = { lootAtlas = true, itemSource = true } },
    -- BiS-Zeile im Gegenstands-Tooltip (Teil von AtlasLoot Classic Forever; Ordner beim Nutzer installiert, TOC
    -- „AtlasLoot Forever [BiS ToolTip]“, Dependencies: AtlasLootClassic; keine Lizenzangabe – nur „läuft es?“)
    AtlasBIStooltips = { label = "AtlasLoot BiS-Tooltip", folders = { "AtlasBIStooltips" }, features = { itemSource = true } },
    -- OneForAll – Forever (smoergi, GPLv3): Talentrechner mit Vorlagen je Klasse, Dungeons mit Bossen, Beute und
    -- Questketten in seinem Fenster. Ordner OneForAll laut TOC im öffentlichen Quelltext (OneForAll/OneForAll.toc).
    OneForAll = { label = "OneForAll – Forever", folders = { "OneForAll" }, url = "https://www.curseforge.com/wow/addons/oneforall-forever",
        features = { talentTemplates = true, dungeonAtlas = true } },
    -- Talented Forever (Slackbringer, zlib): Talentvorlagen; Ordner „Talented“ laut seiner Projektseite
    TalentedForever = { label = "Talented Forever", folders = { "Talented" }, url = "https://www.curseforge.com/wow/addons/talented-forever",
        features = { talentTemplates = true } },
    -- Myslot (Apache 2.0): Aktionsleisten, Makros und Tastenbelegung als Profil sichern und laden; Ordner Myslot
    -- laut TOC im öffentlichen Quelltext (Myslot.toc). Lädt nur auf Knopfdruck – stört ezMacro nicht, wird nur genannt.
    Myslot = { label = "Myslot", folders = { "Myslot" }, features = { barProfiles = true } },
    Atlas = { label = "Atlas", folders = { "Atlas" }, url = "https://www.curseforge.com/wow/addons/atlas",
        features = { dungeonAtlas = true } },
    -- MaxRank: Ordner MaxRank laut TOC im öffentlichen Quelltext (github.com/jBeyondstars/MaxRank: MaxRank.toc, 16.11.2026)
    MaxRank = { label = "MaxRank", folders = { "MaxRank" }, features = { spellRanks = true } },
    RankWatch = { label = "Rank Watch", folders = { "RankWatch" }, features = { spellRanks = true } },
    NovaSpellRankChecker = { label = "Nova Spell Rank Checker", folders = { "NovaSpellRankChecker" }, features = { spellRanks = true } },
    BlizzMove = { label = "BlizzMove", folders = { "BlizzMove" }, features = { moveFrames = true } },
    -- MoveAny (d4kir92): verschiebt und skaliert Blizzards Fenster; Ordner MoveAny laut TOC im öffentlichen Quelltext
    -- (MoveAny.toc, für Forever MoveAny_Camelot.toc). Lizenz „All Rights Reserved“ – nur „läuft es?“.
    MoveAny = { label = "MoveAny", folders = { "MoveAny" }, features = { moveFrames = true } },
    -- Taschen: zwei Taschen-Addons greifen in dieselben Fenster
    ArkInventory = { label = "ArkInventory", folders = { "ArkInventory" }, features = { bags = true } },
    Bagnon = { label = "Bagnon", folders = { "Bagnon" }, features = { bags = true } },
    Baganator = { label = "Baganator", folders = { "Baganator" }, features = { bags = true } },
    -- Berufe: Skill-Farben je Rezept. SkillUp Forever: Ordner SkillUpForever laut TOC im öffentlichen Quelltext
    -- (github.com/cjber/skillup-forever: SkillUpForever.toc im Wurzelordner, 16.11.2026); die beiden anderen Namen
    -- bleiben als Rückfall. ForeverArtisan im Spiel bestätigen.
    SkillUpForever = { label = "SkillUp Forever", folders = { "SkillUpForever", "SkillUp_Forever", "SkillUp" }, features = { skillStages = true } },
    ForeverArtisan = { label = "ForeverArtisan", folders = { "ForeverArtisan" }, features = { skillStages = true } },
    -- Chat (Ordnernamen von Better Forever Chat im Spiel bestätigen)
    -- chatLinkTooltip: Prats Modul HoverTips (ab Werk an) zeigt Link-Tooltips in ChatFrame1 bis NUM_CHAT_WINDOWS
    -- (github.com/Sylvanaar/prat-3-0, GPL-3.0, modules/HoverTips.lua, gelesen 18.11.2026); ob es abgeschaltet ist,
    -- wird nicht gelesen – ezChat zeigt dazu nur einen Hinweis.
    Prat = { label = "Prat", folders = { "Prat-3.0" }, features = {
        chatLinks = true, chatChannelNames = true, chatCopy = true, chatHighlight = true, chatLinkTooltip = true } },
    Chatter = { label = "Chatter", folders = { "Chatter" }, features = { chatLinks = true, chatChannelNames = true, chatCopy = true } },
    BetterForeverChat = { label = "Better Forever Chat", folders = { "BetterForeverChat", "Better_Forever_Chat" }, features = {
        chatLinks = true, chatCopy = true } },
    WIM = { label = "WIM", folders = { "WIM" }, features = { whisperWindows = true } },
    -- Minikarte: SexyMap zoomt von selbst heraus („Auto Zoom-Out Delay“) und gestaltet Form und Rahmen der Minikarte
    -- immer selbst (minimapShape; ezMaps „Eckige Minikarte“ ruht dann)
    SexyMap = { label = "SexyMap", folders = { "SexyMap" }, features = {
        minimapAutoZoom = SexyMapAutoZoom, minimapShape = true } },
    -- ElvUI (Ordner ElvUI laut öffentlichem Quelltext tukui-org/ElvUI): eckige Minikarte. Ob sein Minikarten-Teil
    -- abgeschaltet ist, wird nicht gelesen – läuft es, gilt die Form als vergeben.
    ElvUI = { label = "ElvUI", folders = { "ElvUI" }, features = { minimapShape = true } },
    -- Bücher-Punkte auf der Karte (NEU-03, für ezMap): HandyNotes-Plugin „Forever Books“ (Ordner beim Nutzer
    -- installiert, TOC RequiredDeps: HandyNotes; „All Rights Reserved“ – nur „läuft es?“, nichts ausgelesen)
    ForeverBooks = { label = "HandyNotes – Forever Books", folders = { "HandyNotes_ForeverBooks" }, features = { bookPins = true } },
    -- Sammel-Addons (SAM-09, Welle 13): zeichnen eigene Fundorte auf Karte und Minikarte – ezMap zeichnet dann nicht
    -- und nennt das Addon, ezCore erfasst still weiter. Nur „läuft es?“ (Leitlinie 10). Ordnernamen belegt an den
    -- früheren Lese-Brücken in Gathering.lua (bis Welle 16, RB-02 und RB-03 entfernt) und an den TOC-Dateien.
    GatherMate2 = { label = "GatherMate2", folders = { "GatherMate2" }, url = "https://www.curseforge.com/wow/addons/gathermate2",
        features = { gatherPins = true } },
    GathererReforged = { label = "Gatherer Reforged", folders = { "GathererReforged" },
        url = "https://www.curseforge.com/wow/addons/gatherer-reforged", features = { gatherPins = true } },
    -- Gruppensuche aus dem Chat (vorher ezSocial/Core.lua). Ordner laut TOC im öffentlichen Quelltext (16.11.2026):
    -- github.com/Vysci/LFG-Group-Bulletin-Board (Ordner LFGBulletinBoard mit LFGBulletinBoard.toc) und
    -- github.com/Pinta365/LFGForever (LFGForever.toc im Wurzelordner).
    LFGBulletinBoard = { label = "LFG Bulletin Board", folders = { "LFGBulletinBoard" }, features = { lfgBoard = true } },
    LFGForever = { label = "LFGForever", folders = { "LFGForever" }, features = { lfgBoard = true } },
    -- Tooltips für Einheiten
    TipTac = { label = "TipTac", folders = { "TipTac" }, features = { unitTooltip = true } },
    TinyTooltip = { label = "TinyTooltip", folders = { "TinyTooltip" }, features = { unitTooltip = true } },
    -- Itemlevel bzw. Ausrüstungswert im Spieler-Tooltip (Ordnernamen im Spiel bestätigen)
    TacoTip = { label = "TacoTip", folders = { "TacoTip" }, features = { unitItemLevel = true } },
    GearScore = { label = "GearScore", folders = { "GearScore", "GearScoreLite" }, features = { unitItemLevel = true } },
    -- Seltene Gegner melden (rareAlerts, Chatzeile) und auf der Karte zeigen (rarePins; Gesamtreview 18.11.2026, T5-1:
    -- vorher hing ezMaps Kartenpunkt am Schlüssel der Meldung). NovaRares: Ordnername im Spiel bestätigen; ob es Punkte
    -- auf die Karte setzt, ist nicht belegt – nur rareAlerts.
    -- RareScanner („All Rights Reserved“): nur „läuft es?“, keine seiner Einstellungen lesen – Entscheidung des Nutzers
    -- vom 19.11.2026 („Nur „läuft“ (Empfohlen)“; Gesamtreview 18.11.2026, T5-6); läuft es, gelten Meldung und
    -- Kartenpunkte als vergeben. Wer trotzdem beides von ezMap will, setzt dort „Trotzdem melden“ (rareOverride).
    RareScanner = { label = "RareScanner", folders = { "RareScanner" }, url = "https://www.curseforge.com/wow/addons/rarescanner",
        features = { rareAlerts = true, rarePins = true } },
    SilverDragon = { label = "SilverDragon", folders = { "SilverDragon" }, features = { rareAlerts = true, rarePins = true } },
    NovaRares = { label = "NovaRares", folders = { "NovaRares" }, features = { rareAlerts = true } },
    -- HandyNotes: WoW Forever (Kemayo), Plugin für HandyNotes: seltene Gegner und Schätze auf der Karte. Ordner
    -- HandyNotes_WoWForever am Client belegt (TOC: Interface 16001, RequiredDeps: HandyNotes, X-Curse-Project-ID
    -- 1697216; keine Lizenzdatei – nur „läuft es?“, nichts ausgelesen). Es meldet nichts im Chat – nur rarePins.
    HandyNotesWoWForever = { label = "HandyNotes: WoW Forever", folders = { "HandyNotes_WoWForever" },
        url = "https://www.curseforge.com/wow/addons/handynotes-wow-forever", features = { rarePins = true } },
    -- Dungeon- und Raideingänge auf der Karte (Plugin für HandyNotes; seine Auswahl Dungeon/Raid liegt im
    -- AceDB-Profil und wird nicht gelesen: läuft es, zeigt es Eingänge)
    ForeverInstances = { label = "Forever Instances", folders = { "Forever_Instances" }, features = { dungeonEntrances = true } },
    -- Klick-Zaubern auf Blizzards Rahmen und eigene Heilrahmen
    Clique = { label = "Clique", folders = { "Clique" }, features = { clickCast = true } },
    -- HealBot: HealBot_Config.DisabledNow == 1 heißt „gerade abgeschaltet“ (je Charakter gespeichert)
    HealBot = { label = "HealBot", folders = { "HealBot" }, features = {
        healFrames = function()
            local config = DB("HealBot_Config")
            return not (config and config.DisabledNow == 1)
        end,
    } },
    VuhDo = { label = "VuhDo", folders = { "VuhDo" }, features = { healFrames = true } },
    Grid2 = { label = "Grid2", folders = { "Grid2" }, features = { healFrames = true } },
    Cell = { label = "Cell", folders = { "Cell" }, features = { healFrames = true } },
    -- Click Casting Tooltip (GPLv3, Forever-Datei): zeigt die Klick-Belegung im Tooltip der Einheitenrahmen; Ordner
    -- ClickCastingTooltip laut TOC im öffentlichen Quelltext. Schlüssel clickLegend für ezHeals Klick-Legende (HL-01).
    ClickCastingTooltip = { label = "Click Casting Tooltip", folders = { "ClickCastingTooltip" }, features = { clickLegend = true } },
    -- Party Buff Tracker Forever: Übersicht der Gruppe, solange sein Hauptfenster nicht ausgeblendet ist
    -- (shown, Standard an); sein „Auto Repair“ ist ab Werk aus.
    PartyBuffTrackerForever = { label = "Party Buff Tracker Forever", folders = { "PartyBuffTrackerForever" },
        url = "https://www.curseforge.com/wow/addons/party-buff-tracker-forever", features = {
        groupBuffs = function()
            local db = DB("PartyBuffTrackerForeverDB")
            return not (db and db.shown == false)
        end,
        repair = function()
            local db = DB("PartyBuffTrackerForeverDB")
            return db ~= nil and db.autoRepair == true
        end,
    } },
    Details = { label = "Details! Damage Meter", folders = { "Details" }, features = { damageMeter = true } },
    -- ForeverMeter (GPL-3.0-or-later): Ordner ForeverMeter laut TOC im öffentlichen Quelltext (ForeverMeter.toc)
    ForeverMeter = { label = "ForeverMeter", folders = { "ForeverMeter" }, features = { damageMeter = true } },
    Capping = { label = "Capping", folders = { "Capping" }, features = { battlegroundTimers = true } },
    -- Beute im Gegner-Tooltip: Tnny's Mob Loot zeigt seine Liste neben dem Tooltip nur mit dem Schalter „hover“
    -- (TnnysMobLootDB.settings.hover, Standard aus) und nur, solange seine Taste gehalten wird (keys.unitLoot,
    -- Core.OtherAddOnKeyHeld; EC-96). „Drops from“ im Gegenstands-Tooltip (itemSource) ab Werk an, aus mit
    -- dropsFrom = "OFF". Forever Drops und WhatItDrops stehen darunter; Drop Atlas fehlt, bis sein Ordnername belegt
    -- ist (Welle 27: weder Projektseite noch ein Quelltext nennen ihn).
    TnnysMobLoot = { label = "Tnny's Mob Loot", folders = { "TnnysMobLoot" }, features = {
        unitLoot = function()
            local settings = TnnySettings()
            return settings ~= nil and settings.hover == true
        end,
        itemSource = function()
            local settings = TnnySettings()
            return not (settings and settings.dropsFrom == "OFF")
        end,
    }, keys = { unitLoot = TnnyKeyHeld } },
    -- Forever Drops (Bergtrollz, „All Rights Reserved“): Beute samt Chance im Gegner-Tooltip und Chancen im
    -- Gegenstands-Tooltip (laut Projektseite curseforge.com/wow/addons/forever-drops). Ordner ForeverDrops: Die
    -- Projektseite nennt seine Speicherdatei „SavedVariables\ForeverDrops.lua“ (abgerufen am 16.11.2026, Welle 27) –
    -- WoW benennt sie nach dem Addon. Nur „läuft es?“; keine Taste bekannt, es gilt also immer als zeigend.
    ForeverDrops = { label = "Forever Drops", folders = { "ForeverDrops" }, url = "https://www.curseforge.com/wow/addons/forever-drops",
        features = { unitLoot = true, itemSource = true } },
    -- WhatItDrops (Garufo, GPL-3.0): Beute-Fenster zum Ziel, nicht im Tooltip – darum keine Funktion, die ein Modul
    -- abgibt. Ordner WhatItDrops laut TOC im öffentlichen Quelltext (github.com/SokratisV/WhatItDrops: Ordner
    -- WhatItDrops mit WhatItDrops_Forever.toc, dazu nachladbare Daten-Ordner WhatItDrops_*; 16.11.2026, Welle 27).
    -- Als Datenquelle (Frage 12) nicht angebunden – erst nach Prüfung einer dokumentierten Schnittstelle.
    WhatItDrops = { label = "WhatItDrops", folders = { "WhatItDrops" }, url = "https://www.curseforge.com/wow/addons/whatitdrops",
        features = {} },
    -- Entzauber-Wert im Tooltip: Enchantrix (eigenständig und als Teil der Auctioneer-Suite; Ordner Enchantrix laut
    -- seiner TOC-Datei). Für Forever gibt es keine Fassung; läuft es trotzdem, zeigt es den Wert – seine eigenen
    -- Schalter werden nicht gelesen.
    Enchantrix = { label = "Enchantrix", folders = { "Enchantrix" }, features = { salvageValue = true } },
    -- Pull-Timer: Deadly Boss Mods legt „/pull <Sekunden>“ an, solange BigWigs nicht läuft (DBM-Core,
    -- modules/Commands.lua). Ordner DBM-Core laut seiner TOC-Datei; ezMacro macht aus der Pull-Ansage dann
    -- „/pull“.
    DeadlyBossMods = { label = "Deadly Boss Mods", folders = { "DBM-Core" }, url = "https://www.curseforge.com/wow/addons/deadly-boss-mods",
        features = { pullTimer = true } },
    -- BigWigs legt ebenfalls „/pull“ an; Ordner BigWigs laut TOC im öffentlichen Quelltext (BigWigs.toc, mit
    -- Init_Camelot.lua für Forever)
    BigWigs = { label = "BigWigs", folders = { "BigWigs" }, features = { pullTimer = true } },
    -- Angeln mit einer Taste (ezMacro „Angeln“): Ordnernamen laut TOC im öffentlichen Quelltext – Fishing-OneKey
    -- (MIT, Fishing-Onekey.toc) und Angleur (Angleur.toc). Forever Angler und Better Fishing fehlen, bis ihre
    -- Ordnernamen belegt sind; Forever++ über sein Modul FishingCast (oben).
    FishingOneKey = { label = "Fishing-OneKey", folders = { "Fishing-Onekey" }, features = { fishing = true } },
    Angleur = { label = "Angleur", folders = { "Angleur" }, features = { fishing = true } },
}

-- Feste Reihenfolge, damit WhoHandles immer denselben Namen nennt.
Core.OTHER_ORDER = { "LeatrixPlus", "ForeverTweaks", "TweaksForever", "Questie", "LeatrixMaps", "ClassicUIForever", "BetterBags", "Titan",
    "MinimapButtonButton", "HidingBar", "InFlight", "TomTom", "Auctionator", "Pawn", "Outfitter", "Manners",
    "ForeverQuestTint", "ForeverQuests", "ForeverPlusPlus", "MaxRank", "RankWatch", "NovaSpellRankChecker", "BlizzMove",
    "ArkInventory", "Bagnon", "Baganator", "SkillUpForever", "ForeverArtisan", "Prat", "Chatter", "BetterForeverChat", "WIM",
    "LFGBulletinBoard", "LFGForever", "TipTac", "TinyTooltip", "TacoTip", "GearScore", "Bartender4", "Dominos", "AtlasLoot", "Atlas",
    "RareScanner", "SilverDragon", "NovaRares", "HandyNotesWoWForever", "ForeverInstances", "Clique", "HealBot", "VuhDo", "Grid2", "Cell",
    "PartyBuffTrackerForever", "Details", "Capping", "TnnysMobLoot", "Enchantrix", "DeadlyBossMods",
    -- Runde 3 (15.11.2026)
    "MoveAny", "ItemRack", "WinterEssentials", "AtlasBIStooltips", "OneForAll", "TalentedForever", "Myslot", "ElvUI",
    "ForeverBooks", "ClickCastingTooltip", "ForeverMeter", "BigWigs", "FishingOneKey", "Angleur",
    -- Welle 13 (SAM-09)
    "GatherMate2", "GathererReforged" }

-- Einträge, die in der Reihenfolge fehlen, kommen hinten dazu – eine neue Erkennung geht so nie verloren.
do
    local listed, extra = {}, {}
    for _, key in ipairs(Core.OTHER_ORDER) do listed[key] = true end
    for key in pairs(Core.OTHER_ADDONS) do
        if not listed[key] then extra[#extra + 1] = key end
    end
    table.sort(extra)
    for _, key in ipairs(extra) do Core.OTHER_ORDER[#Core.OTHER_ORDER + 1] = key end
end

local function Loaded(entry)
    for _, folder in ipairs(entry.folders or {}) do
        if Core.IsLoaded(folder) then return true end
    end
    return false
end

local function Check(entry, feature)
    local test = entry.features and entry.features[feature]
    if test == nil then return false end
    if test == true then return true end
    local ok, result = pcall(test, entry)
    return ok and result == true
end

function Core.OtherAddOn(name, feature)
    local entry = Core.OTHER_ADDONS[name]
    if not entry or not Loaded(entry) then return false, entry and entry.label end
    if feature == nil then return true, entry.label end
    return Check(entry, feature), entry.label
end

---------------------------------------------------------------------------
-- Rücksicht-Zähler (AH-14, Welle 13): wie oft ist ein Modul je Funktion und Addon gewichen?
--   Core.WhoHandles(funktion, modul)  zählt, wenn es ein übernehmendes Addon nennt: je Funktion, Addon und (falls
--                                     angegeben) fragendem Modul; ohne modul zählt es unter Core.FeatureOwner(funktion),
--                                     sofern dieses Modul läuft (bzw. ezCore ist).
--                                     Gezählt wird je Sitzung (nicht gespeichert) und höchstens einmal je
--                                     Core.YIELD_SECONDS je Funktion, Addon und Modul – ein Tooltip fragt bei jedem
--                                     Neuaufbau, das wäre sonst kein „gewichen“, sondern ein Bildzähler.
--   Core.WhoHandlesInfo(funktion)     → wie Core.WhoHandles, zählt aber nicht (reine Auskunft: Einstellungsseiten)
--   Core.YieldCounts(funktion)        → { { feature, key, label, module, n, last } … }, meiste zuerst (ohne funktion: alle)
--   Core.YieldText(funktion)          → „wich 3× Auctionator (ezAuction)“ oder nil – Auskunft für Einstellungsseiten
--   Core.YieldStatusLine()            → Zeile für /ez status oder nil
---------------------------------------------------------------------------
Core.YIELD_SECONDS = 30
local yields = {}   -- "funktion|addon|modul" » { feature, key, label, module, n, last }

local function CountYield(feature, key, label, module)
    if not module then
        -- ohne Angabe: das Modul, dem die Funktion gehört – nur, wenn es läuft (sonst ist niemand gewichen)
        module = Core.FeatureOwner and Core.FeatureOwner(feature)
        if not module or (module ~= Core.name and Core.ModuleState and Core.ModuleState(module) ~= "loaded") then return end
    end
    local id = feature .. "|" .. key .. "|" .. module
    local e = yields[id]
    local now = Core.Uptime and Core.Uptime() or 0
    if not e then
        e = { feature = feature, key = key, label = label, module = module, n = 0 }
        yields[id] = e
    elseif e.last and now - e.last < Core.YIELD_SECONDS then
        return
    end
    e.n, e.last = e.n + 1, now
end

local function Handler(feature)
    for _, key in ipairs(Core.OTHER_ORDER) do
        local entry = Core.OTHER_ADDONS[key]
        if entry and entry.features and entry.features[feature] ~= nil and Loaded(entry) and Check(entry, feature) then
            return entry, key
        end
    end
    return nil
end

function Core.WhoHandles(feature, module)
    local entry, key = Handler(feature)
    if not entry then return nil end
    if type(feature) == "string" then CountYield(feature, key, entry.label, type(module) == "string" and module or nil) end
    return entry.label, key
end

-- Reine Auskunft ohne Zählen (Gegenprüfung Welle 13): Einstellungsseiten und Tooltips, die nur sagen, wer die
-- Funktion übernimmt, sind kein „gewichen“. → Name, Schlüssel wie Core.WhoHandles
function Core.WhoHandlesInfo(feature)
    local entry, key = Handler(feature)
    if not entry then return nil end
    return entry.label, key
end

function Core.YieldCounts(feature)
    local out = {}
    for _, e in pairs(yields) do
        if feature == nil or e.feature == feature then
            out[#out + 1] = { feature = e.feature, key = e.key, label = e.label, module = e.module, n = e.n, last = e.last }
        end
    end
    table.sort(out, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.feature .. a.key .. a.module < b.feature .. b.key .. b.module
    end)
    return out
end

function Core.YieldText(feature)
    local list = Core.YieldCounts(feature)
    if #list == 0 then return nil end
    local L, parts = Core.L, {}
    for _, e in ipairs(list) do parts[#parts + 1] = L.YIELD_ENTRY:format(e.n, e.label, e.module) end
    return L.YIELD_TEXT:format(table.concat(parts, ", "))
end

function Core.YieldStatusLine()
    local list = Core.YieldCounts()
    if #list == 0 then return nil end
    local L, parts = Core.L, {}
    for _, e in ipairs(list) do parts[#parts + 1] = L.YIELD_STATUS_ENTRY:format(e.feature, e.n, e.label, e.module) end
    return L.STATUS_YIELDS:format(table.concat(parts, "; "))
end

function Core.ResetYields() yields = {} end

-- EC-96: Zeigt das übernehmende Addon seine Anzeige nur bei gehaltener Taste (Tnny's Mob Loot), sagt dies, ob sie
-- gerade gehalten wird – so blendet ein Modul seine eigene Anzeige nur dann aus. Nur gelesen, nichts gebunden.
function Core.OtherAddOnKeyHeld(feature)
    local label, key = Core.WhoHandles(feature)
    local entry = key and Core.OTHER_ADDONS[key]
    local test = entry and type(entry.keys) == "table" and entry.keys[feature]
    if type(test) ~= "function" then return nil, label end
    local ok, held = pcall(test, entry)
    return ok and held == true, label
end

function Core.OtherAddOns()
    local list = {}
    for _, key in ipairs(Core.OTHER_ORDER) do
        local entry = Core.OTHER_ADDONS[key]
        if entry and Loaded(entry) then
            local features = {}
            for feature in pairs(entry.features or {}) do
                if Check(entry, feature) then features[#features + 1] = feature end
            end
            table.sort(features)
            list[#list + 1] = { key = key, label = entry.label, features = features }
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Benötigte und ergänzende Addons je Modul (Entscheidung des Nutzers 13.11.2026: in README und im Spiel, mit
-- CurseForge-Link; im Spiel lässt sich der Link nur kopieren). Pflicht ist für jedes Modul nur ezCore.
--   Core.AddCompanion(modul, { key, label, url, role = "required" | "optional", why = Text, folders = { … } })
--       key: Eintrag in Core.OTHER_ADDONS (dann kommen Name, Ordner und – wenn dort eine url steht – die Adresse
--            von dort: das Modul nennt nur key und why) oder ein eigener Name (dann ist url Pflicht)
--   Core.Companions(modul) → { { key, label, url, role, why, installed } … }, Pflicht zuerst
--   Core.AddCompanionButtons(layout, modul) / page:Companions() → Abschnitt „Ergänzende Addons“ unter „Erweitert“
---------------------------------------------------------------------------

Core.COMPANIONS = {}

function Core.AddCompanion(module, entry)
    if type(module) ~= "string" or type(entry) ~= "table" then return false end
    local known = entry.key and Core.OTHER_ADDONS[entry.key]
    -- Die Adresse steht EINMAL am Eintrag in Core.OTHER_ADDONS (V-138: der Questie-Link stand in drei Modulen);
    -- ein Modul nennt dann nur key und why. Eine eigene url geht vor.
    local url = entry.url or (known and known.url)
    if type(url) ~= "string" or url == "" then return false end
    local item = {
        key = entry.key or entry.label, label = entry.label or (known and known.label) or entry.key, url = url,
        role = entry.role == "required" and "required" or "optional", why = entry.why,
        folders = entry.folders or (known and known.folders) or { entry.key },
    }
    if type(item.label) ~= "string" then return false end
    local list = Core.COMPANIONS[module] or {}
    Core.COMPANIONS[module] = list
    for i = #list, 1, -1 do
        if list[i].key == item.key then table.remove(list, i) end
    end
    list[#list + 1] = item
    return true
end

function Core.Companions(module)
    local out = {}
    for _, item in ipairs(Core.COMPANIONS[module] or {}) do
        out[#out + 1] = { key = item.key, label = item.label, url = item.url, role = item.role, why = item.why,
            installed = Loaded(item) }
    end
    table.sort(out, function(a, b)
        if (a.role == "required") ~= (b.role == "required") then return a.role == "required" end
        return a.label:lower() < b.label:lower()
    end)
    return out
end

-- Knöpfe für eine Einstellungsseite: Name (Pflicht/ergänzend, installiert?), Klick zeigt den Link zum Kopieren.
function Core.AddCompanionButtons(layout, module)
    local list = Core.Companions(module)
    if #list == 0 or not (layout and layout.AddInitializer and CreateSettingsButtonInitializer) then return 0 end
    local L = Core.L
    if CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.COMPANIONS_HEADER, L.COMPANIONS_HEADER_TIP))
    end
    for _, c in ipairs(list) do
        local label = L.COMPANION_LABEL:format(c.label, c.role == "required" and L.COMPANION_REQUIRED or L.COMPANION_OPTIONAL,
            c.installed and L.COMPANION_INSTALLED or L.COMPANION_MISSING)
        local tip = (type(c.why) == "string" and (c.why .. "\n\n") or "") .. c.url
        layout:AddInitializer(CreateSettingsButtonInitializer(label, L.COMPANION_COPY, function()
            Core.AskText(L.COMPANION_COPY_PROMPT:format(c.label), c.url, function() end, 0)
        end, tip, true))
    end
    return #list
end

-- ezCore selbst: Herkunft, Händler, Lehrer und Standorte zur Laufzeit aus QuestieDB (Core.Sources, EC-04, DG-19).
-- Gatherer Reforged und GatherMate2 stehen hier nicht mehr (SAM-27, Welle 16): Fundorte kommen aus den eigenen Ernten,
-- die beiden bekommen nur noch Rücksicht (Einträge oben, Funktion gatherPins).
Core.AddCompanion("ezCore", { key = "Questie", why = Core.L.COMPANION_WHY_QUESTIE_SOURCE })
