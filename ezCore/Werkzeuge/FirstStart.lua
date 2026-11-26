local ADDON, ns = ...
local Core = ezCore
local L = Core.L

--[[
    Erster Start (Idee aus der Vollprüfung 13.11.2026): Wer die ezCollection neu installiert, sieht einmal, was
    läuft – welche Module aktiv sind, welche fremden Addons erkannt wurden und wer wem den Vortritt lässt
    (Leitlinie 9).

      * Beim ersten Anmelden EINE Chatzeile mit dem Weg zur Übersicht (/ez).
      * Beim ersten Öffnen der Seite „ezCollection“ über ezCore (Befehl /ez, Addon-Fach, Knopf „Zurück“ einer
        Modulseite) ein kurzer Rundgang aus drei Erklärblasen an Blizzards Einstellungsfenster (Core.NewTour).
      * Jederzeit: Knopf „Erster Start – Zeigen“ unter „Allgemein“ (die ganze Übersicht als Text zum Lesen und
        Kopieren, Core.TextDialog) und Knopf „Erklärblasen aller Module – Erneut zeigen“ unter „Erweitert“.

      Core.FirstStart.Lines()       → Zeilen der Übersicht       Core.FirstStart.Text()
      Core.FirstStart.Recommended() → { { key, label, url, why } … } empfohlene Addons (Questie, solange weder Questie
                                      noch QuestieDB läuft) – Zeile in der Übersicht und im letzten Schritt des Rundgangs
      Core.FirstStart.Yields()      → { { addon = Anzeigename, modules = { { module, features = { … } } … } } … }
                                      je laufendem fremdem Addon: welches Modul ihm bei welcher Funktion weicht;
                                      reine Hinweis-Funktionen (FS.HintOnly) fehlen, dort weicht kein Modul
      Core.FirstStart.HintOnly(f)   → true, wenn das Modul die Funktion nur in ns.HINT_BY führt (Hinweis am Schalter,
                                      das Modul bleibt an) und nicht in ns.HANDLED_BY (I2, Gesamtreview 18.11.2026)
      Core.FirstStart.Show()        zeigt die Übersicht (Knopf, /ez start)
      Core.FirstStart.StartTour()   → true, wenn der Rundgang vorgemerkt ist (nichts, wenn schon gesehen)
      Core.FirstStart.tour          der Rundgang (tour:Reset() zeigt ihn erneut)
      Core.FirstStart.Hint()        → true, wenn die Chatzeile jetzt gezeigt wurde (einmal je Account)
      Core.ResetAllTours()          → Anzahl der Erklärblasen-Sätze, die wieder von vorn beginnen (alle Module)
      Core.FEATURE_OWNER[funktion]  → Modul, das die Funktion sonst selbst erledigt (eine Stelle; ein Test
                                      vergleicht sie mit Core.OTHER_ADDONS)
      Core.FEATURE_OWNERS[funktion] → Liste, wenn der Eigentümer davon abhängt, welches Modul geladen ist
      Core.FeatureOwner(funktion)   → das erste geladene Modul aus FEATURE_OWNERS, sonst FEATURE_OWNER (oder nil)
      Core.FEATURE_SWITCH[funktion] → { module, key }: das Modul weicht nur, solange sein Schalter key an ist
                                      (Welle 23a, A80: mailTooltip – ezMail weicht Auctionator nur mit
                                      „attachYield“, ab Werk aus); FS.Yields führt solche Funktionen sonst unter
                                      „optional“, die Übersicht sagt „nur mit eigenem Schalter“
    Gemerkt in ezCoreDB.firstStart = { hint = Zeitpunkt } und ezCoreDB.tour (gesehene Blasen).
]]

local FS = {}
Core.FirstStart = FS

-- Funktion (Schlüssel aus Core.OTHER_ADDONS[…].features) → Modul, das zurücktritt, wenn ein fremdes Addon sie
-- übernimmt.
Core.FEATURE_OWNER = {
    sellJunk = "ezBag", easyDestroy = "ezBag", bags = "ezBag", bagStyle = "ezBag", bankStyle = "ezBag",
    repair = "ezMerchant", fastLoot = "ezLoot", lootAtlas = "ezLoot", dungeonAtlas = "ezLoot",
    questAccept = "ezQuest", questTurnIn = "ezQuest", questTracker = "ezQuest", questSort = "ezQuest",
    questItemTooltip = "ezQuest", questTint = "ezQuest", questSparkle = "ezQuest", questShare = "ezQuest",
    minimapBag = "ezPanel", mapCoords = "ezMap", infoBar = "ezPanel",
    flightTimes = "ezMap", flightPoints = "ezMap", dungeonEntrances = "ezMap", way = "ezMap", minimapAutoZoom = "ezMap",
    mapTrainers = "ezMap",
    readyTimer = "ezSocial", acceptSummon = "ezSocial", acceptResurrect = "ezSocial", blockDuels = "ezSocial",
    blockInvites = "ezSocial", lfgBoard = "ezSocial",
    chatFade = "ezChat", chatHistory = "ezChat", chatStyle = "ezChat", chatArrows = "ezChat", chatLinks = "ezChat",
    chatChannelNames = "ezChat", chatCopy = "ezChat", chatHighlight = "ezChat", whisperWindows = "ezChat",
    chatLinkTooltip = "ezChat",
    spellRanks = "ezMacro", comboPoints = "ezCombat", rebuffThanks = "ezBuff",
    auctionTooltip = "ezAuction", mailTooltip = "ezMail", craftCost = "ezCraft",
    bagArrows = "ezGear", questArrows = "ezGear", upgradeTooltip = "ezGear", gearSwap = "ezGear",
    actionBars = "ezBars", skillStages = "ezCraft",   -- seit dem 21.11.2026 nur Erkennung (ezCraft zeigt keine Skill-Stufen mehr)
    betaHints = "ezCore", unitTooltip = "ezCore", unitItemLevel = "ezCore", moveFrames = "ezCore", cameraZoom = "ezCore",
    trainAll = "ezMerchant", zoneLevels = "ezMap", rareAlerts = "ezMap", battlegroundTimers = "ezMap",
    groupBuffs = "ezBuff", damageMeter = "ezCombat", unitLoot = "ezLoot", petTrainerHint = "ezMerchant",
    salvageValue = "ezCraft", pullTimer = "ezMacro", minimapShape = "ezMap",
    -- Runde 3 (15.11.2026)
    fishing = "ezMacro", barProfiles = "ezMacro", talentTemplates = "ezTalent", slotLevels = "ezGear",
    itemSource = "ezCore", bookPins = "ezMap",
    -- Welle 10 (DG-17): Herkunft laut Questie an Quest-Gegenständen weicht Questies eigenem Tooltip
    questItemSource = "ezCore",
    -- Welle 12 (AH-03): Komplett-Scan mit kontoweiter Sperrzeit – ezCore startet keinen Scan von selbst
    auctionScan = "ezCore",
    -- Welle 13 (SAM-09): Sammel-Addons zeichnen Fundorte selbst – ezMap zeichnet dann nicht, ezCore zählt weiter
    gatherPins = "ezMap",
    -- Klick-Zaubern und Heilrahmen: ezHeal (Vorlagen auf Blizzards Klick-Zaubern, Hinweise bei Clique und HealBot)
    clickCast = "ezHeal", healFrames = "ezHeal", clickLegend = "ezHeal",
    -- S-1811-Tooltipabstand (Gesamtreview 18.11.2026): fremde Quest-Blöcke im NPC-Tooltip – ezCore setzt die Abschnitte
    -- der Module dahinter (UnitTooltip.lua, UT.SectionsLater)
    unitQuestLines = "ezCore",
    -- Gesamtreview 18.11.2026 (T5-1, Paket D3): Kartenpunkte seltener Gegner und Schätze, getrennt von rareAlerts
    rarePins = "ezMap",
}

-- Eigentümer je geladenem Modul (VP-30): Plunder verkauft ezCore (Core.Junk); zurück tritt das Modul, das ihn
-- auslöst – ezBag (liefert die Regel), ohne ezBag ezMerchant (dann nur Graues). Koordinaten zeigt ezMap, ezPanel
-- nur als Rückfall (PANEL-16). Der erste Eintrag steht zusätzlich in FEATURE_OWNER (eine Stelle für Tests).
Core.FEATURE_OWNERS = {
    sellJunk = { "ezBag", "ezMerchant" },
    mapCoords = { "ezMap", "ezPanel" },
}

function Core.FeatureOwner(feature)
    local list = Core.FEATURE_OWNERS[feature]
    if type(list) == "table" then
        for _, name in ipairs(list) do
            if Core.ModuleState and Core.ModuleState(name) == "loaded" then return name end
        end
    end
    return Core.FEATURE_OWNER[feature]
end

Core.FEATURE_SWITCH = {
    mailTooltip = { module = "ezMail", key = "attachYield" },
}

-- Weicht das Modul bei dieser Funktion gerade? false nur, wenn FEATURE_SWITCH einen Schalter nennt, das Modul
-- geladen ist und der Schalter nicht an ist (gelesen aus den Einstellungen des Moduls, nichts wird geschrieben).
function FS.Yielding(feature)
    local switch = Core.FEATURE_SWITCH[feature]
    if type(switch) ~= "table" then return true end
    local mod = Core.Module and Core.Module(switch.module)
    local S = mod and mod.ns and mod.ns.S
    if type(S) ~= "table" then return true end
    return S[switch.key] == true
end

-- Nur ein Hinweis (Gegenprüfung zu I2, Gesamtreview 18.11.2026): Führt das Modul, dem die Funktion gehört, sie nur
-- in ns.HINT_BY (Schalter → Funktion; Hinweis am Schalter, das Modul bleibt an) und nicht in ns.HANDLED_BY, weicht
-- es nicht – die Übersicht darf dann kein „hat Vortritt vor“ nennen (heute ezChat: chatStyle, chatLinkTooltip).
-- Gelesen aus dem geladenen Modul (eine Stelle), nichts wird geschrieben; ohne geladenes Modul false.
local function Lists(map, feature)
    if type(map) ~= "table" then return false end
    for _, f in pairs(map) do
        if f == feature then return true end
    end
    return false
end

function FS.HintOnly(feature)
    local owner = Core.FeatureOwner(feature)
    local mod = owner and Core.Module and Core.Module(owner)
    local mns = type(mod) == "table" and mod.ns
    if type(mns) ~= "table" then return false end
    return Lists(mns.HINT_BY, feature) and not Lists(mns.HANDLED_BY, feature)
end

function FS.Yields()
    local out = {}
    for _, entry in ipairs(Core.OtherAddOns and Core.OtherAddOns() or {}) do
        local byModule, order = {}, {}
        for _, feature in ipairs(entry.features or {}) do
            if not FS.HintOnly(feature) then
                local module = Core.FeatureOwner(feature) or "?"
                if not byModule[module] then
                    byModule[module] = { module = module, features = {}, optional = {} }
                    order[#order + 1] = module
                end
                if FS.Yielding(feature) then
                    table.insert(byModule[module].features, feature)
                else
                    table.insert(byModule[module].optional, feature)
                end
            end
        end
        table.sort(order)
        local modules = {}
        for _, module in ipairs(order) do modules[#modules + 1] = byModule[module] end
        out[#out + 1] = { addon = entry.label, key = entry.key, modules = modules }
    end
    return out
end

-- Was ezCollection selbst lernt (Welle 16; Gegenprüfung: nur, was auch läuft): die Preise, solange ezAuction
-- geladen ist (der Knopf „Preise erfassen“ ist dort); die Fundorte, solange ezMap geladen ist und kein Sammel-Addon
-- die Anzeige übernimmt (gatherPins – dann nennt der Abschnitt „Vortritt“ das Addon).  → { Text … }
function FS.OwnLines()
    local out = {}
    local function Running(name) return Core.ModuleState and Core.ModuleState(name) == "loaded" end
    if Running("ezAuction") then out[#out + 1] = L.FIRST_OWN_PRICES end
    if Running("ezMap") and not (Core.WhoHandlesInfo and Core.WhoHandlesInfo("gatherPins")) then
        out[#out + 1] = L.FIRST_OWN_SPOTS
    end
    return out
end

local function ModuleLists()
    local loaded, off = {}, {}
    for _, name in ipairs(Core.ModuleNames and Core.ModuleNames() or {}) do
        local state = Core.ModuleState(name)
        if state == "loaded" then
            loaded[#loaded + 1] = name
        elseif state == "disabled" then
            off[#off + 1] = name
        end
    end
    return loaded, off
end

-- Empfohlene Addons anderer Autoren (EC-04, DG-19; Entscheidung des Nutzers 14.11.2026 „Ja, und Questie empfehlen“):
-- Questie, solange weder Questie noch QuestieDB läuft. Tnny's Mob Loot wird hier nicht empfohlen (stiller Rückfall).
-- Die Adresse steht einmal am Eintrag in Core.OTHER_ADDONS.  → { { key, label, url, why } … }
function FS.Recommended()
    local out = {}
    local running = Core.OtherAddOn and (Core.OtherAddOn("Questie") or Core.OtherAddOn("QuestieDB"))
    local entry = Core.OTHER_ADDONS and Core.OTHER_ADDONS.Questie
    if not running and entry and type(entry.url) == "string" then
        out[#out + 1] = { key = "Questie", label = entry.label, url = entry.url, why = L.COMPANION_WHY_QUESTIE_SOURCE }
    end
    return out
end

function FS.Lines()
    local lines = { L.FIRST_HEAD:format(Core.Version(ADDON)) }
    local loaded, off = ModuleLists()
    lines[#lines + 1] = ""
    if #loaded > 0 then
        lines[#lines + 1] = L.FIRST_MODULES:format(#loaded)
        for _, name in ipairs(loaded) do
            local tip = Core.ModuleTip and Core.ModuleTip(name)
            lines[#lines + 1] = "  " .. name .. " " .. Core.Version(name) .. (type(tip) == "string" and tip ~= "" and (" – " .. tip) or "")
        end
    else
        lines[#lines + 1] = L.FIRST_NO_MODULES
    end
    if #off > 0 then lines[#lines + 1] = L.FIRST_OFF:format(table.concat(off, ", ")) end
    lines[#lines + 1] = ""
    local yields = FS.Yields()
    if #yields == 0 then
        lines[#lines + 1] = L.FIRST_NO_OTHERS
    else
        lines[#lines + 1] = L.FIRST_OTHERS:format(#yields)
        for _, y in ipairs(yields) do
            if #y.modules == 0 then
                lines[#lines + 1] = "  " .. L.FIRST_OTHER_NONE:format(y.addon)
            else
                local parts = {}
                for _, m in ipairs(y.modules) do
                    if #m.features > 0 then
                        parts[#parts + 1] = L.FIRST_YIELD_PART:format(m.module, table.concat(m.features, ", "))
                    end
                    if m.optional and #m.optional > 0 then
                        parts[#parts + 1] = L.FIRST_YIELD_SWITCH:format(m.module, table.concat(m.optional, ", "))
                    end
                end
                lines[#lines + 1] = "  " .. L.FIRST_YIELD:format(y.addon, table.concat(parts, "; "))
            end
        end
        lines[#lines + 1] = L.FIRST_YIELD_NOTE
    end
    -- Welle 16 (Ablösung): was ezCollection selbst lernt, statt es aus Auctionator oder einem Sammel-Addon zu lesen
    local own = FS.OwnLines()
    if #own > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.FIRST_OWN
        for _, line in ipairs(own) do lines[#lines + 1] = "  " .. line end
    end
    for _, r in ipairs(FS.Recommended()) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.FIRST_RECOMMEND:format(r.label, r.why)
        lines[#lines + 1] = "  " .. r.url
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L.FIRST_WHERE
    return lines
end

function FS.Text()
    return table.concat(FS.Lines(), "\n")
end

function FS.Show()
    return Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.FIRST_TITLE, text = Core.StripColors(FS.Text()), readOnly = true, maxLetters = 0, owner = ADDON })
end

---------------------------------------------------------------------------
-- Rundgang an Blizzards Einstellungsfenster
---------------------------------------------------------------------------

local function Store()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.tour) ~= "table" then db.tour = {} end
    return db.tour
end

local function Panel()
    local panel = rawget(_G, "SettingsPanel")
    return type(panel) == "table" and panel or nil
end

FS.tour = Core.NewTour({ store = Store, module = ADDON, steps = {
    { key = "first.modules", target = Panel, side = "right", text = function()
        local loaded = ModuleLists()
        return L.FIRST_TOUR_MODULES:format(#loaded)
    end },
    { key = "first.others", target = Panel, side = "right", text = function()
        local names = {}
        for _, y in ipairs(FS.Yields()) do names[#names + 1] = y.addon end
        if #names == 0 then return L.FIRST_TOUR_NO_OTHERS end
        return L.FIRST_TOUR_OTHERS:format(table.concat(names, ", "))
    end },
    { key = "first.more", target = Panel, side = "right", text = function()
        local r = FS.Recommended()[1]
        if r then return L.FIRST_TOUR_MORE .. "\n\n" .. L.FIRST_TOUR_RECOMMEND:format(r.label, r.why) end
        return L.FIRST_TOUR_MORE
    end },
} })

function FS.StartTour()
    local panel = Panel()
    if not panel then return false end
    return FS.tour:StartSoon(panel, 0.8)
end

-- Einmal je Account: eine Chatzeile mit dem Weg zur Übersicht.
function FS.Hint()
    local db = Core.db
    if type(db) ~= "table" then return false end
    if type(db.firstStart) ~= "table" then db.firstStart = {} end
    if db.firstStart.hint then return false end
    db.firstStart.hint = time and time() or 0
    local loaded = ModuleLists()
    ns.Print(L.FIRST_HINT:format(#loaded))
    return true
end

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(8, function()
        local ok, err = pcall(FS.Hint)
        if not ok then Core.Error(ADDON, err, "FirstStart") end
    end)
end)

---------------------------------------------------------------------------
-- Erklärblasen aller Module erneut zeigen
---------------------------------------------------------------------------

function Core.ResetAllTours()
    local n = 0
    for _, hints in ipairs(Core.hintSets or {}) do
        local ok, seen = pcall(hints.SeenCount)
        if ok and (seen or 0) > 0 then n = n + 1 end
        Core.Try(nil, "ResetAllTours", hints.Reset)
    end
    -- Hinweise auf Abläufe ohne Klick (Kern/OptInHint.lua): eigener Speicher je Funktion (ezCoreDB.optInSeen), nicht in
    -- Core.hintSets – sonst kämen sie hier nicht wieder (Fund des code-reviewers zu Welle 28)
    local optIn = Core.OptInHint
    if optIn and type(optIn.Reset) == "function" then
        local ok, seen = pcall(optIn.Reset)
        if ok and (seen or 0) > 0 then n = n + 1 end
    end
    -- Angebot der Einführung (unten): kommt beim nächsten Einloggen wieder, wenn es schon kam
    local intro = Core.Intro
    if intro and type(intro.ResetOffer) == "function" then
        local ok, was = pcall(intro.ResetOffer)
        if ok and was then n = n + 1 end
    end
    -- Hinweis „Mithelfen“ (Contribute.lua): ein Knopf für alle Hinweise (Einstellungs-Prüfung 19.11.2026, Nr. 53)
    local contribute = Core.Contribute
    if contribute and type(contribute.ResetHint) == "function" then
        local ok, was = pcall(contribute.ResetHint)
        if ok and was then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Einführung: Addon und jedes Modul – kurz, einzeln, mit Einverständnis
---------------------------------------------------------------------------

--[[
    Wunsch des Nutzers vom 18.11.2026 (W-1811-Einfuehrung), wörtlich: „am ende aller enden sollten wir ein
    vollständiges kurzes tutorial zum addon und jeden modul geben, kurze erklärung, einverständnis - alles (alles
    alles), abgespeckt oder seperat einzeln“. Erweitert den ersten Start (oben) statt eines eigenen Fensters
    (Leitlinie 1): alles steht in Blizzards Einstellungsfenster.

      * Kurz (abgespeckt): die Seite „Einführung“ unter „ezCollection“ (Allgemein » Module » Einverständnis »
        Mithelfen » Erweitert) mit einem Knopf je Modul und je Ablauf ohne Klick einem Häkchen; dazu „Kurz: alles auf
        einer Seite“ – der ganze Text zum Lesen und Kopieren (Core.TextDialog an Blizzards Einstellungsfenster).
      * Einzeln (Spieltest 19.11.2026, S-1911-Einfuehrung: „einführung == passende einleitung und öffnung der
        entsprechenden module nacheinander und abfrage der zustimmung“): je Seite EINE Erklärblase mit „Zurück“ und
        „Weiter“. Für ein Modul öffnet sich das Blizzard-Fenster, an dem es andockt (Intro.WINDOWS: Talente, Zauberbuch,
        Questlog, Weltkarte, Taschen …; über Core.OpenPanel, nur außerhalb des Kampfes), sonst seine Einstellungsseite;
        in derselben Blase je Ablauf ohne Klick dieses Moduls ein Häkchen – das Einverständnis. Die Erklärblasen des
        Moduls (Core.NewTour) laufen dabei an ihrer Stelle im Fenster; wer die Seite verlassen hat („Weiter“,
        „Zurück“, „Fertig“, X, Esc am Fenster), bekommt die Blasen, die dort wirklich standen (tour:ShownSteps,
        Intro.Note), beim Öffnen des Fensters nicht mehr – Blasen an anderen Fenstern (Händler, Lehrer) bleiben –,
        ebenso wenig die Blase „Einschalten“ von Core.OptInHint für die Schalter der Seite (Intro.Settle); solange die Seite an
        einem Fenster steht, zeigt Core.OptInHint dort keine eigene Blase (Intro.HoldsWindow). Ein Kampfbeginn
        unterbricht nur: nichts gilt als gesehen. Ein Fenster, das die Einführung geöffnet hat, schließt sie beim
        Weiterblättern wieder; eins, das der Spieler offen hatte (auch auf einem anderen Reiter), bleibt offen. Blizzards
        Einstellungsfenster geht über Core.ClosePanel "settings" zu – mit nicht übernommenen Änderungen bleibt es offen,
        und die Seite steht dort (Core.Panels.SettingsPending). Jede Seite ist einzeln
        aufrufbar: Knopf „Einführung“ unter „Allgemein“ jeder Modulseite (Core.NewSettingsPage, Kern/Settings.lua),
        Knöpfe der Seite „Einführung“, Befehl „einführung <Modul>“ von ezCore.
      * Allem zustimmen: alle Abläufe ohne Klick der laufenden Module auf einmal an – Knopf im Angebot, in der
        Kurzfassung und auf der Seite „Einführung“, Befehl „einführung alles“; vorher eine Rückfrage mit der Liste aller
        Schalter je Modul (Intro.AgreeList; bis Intro.AGREE_LINES Module über Core.Confirm, mehr als Textfenster mit
        „Allem zustimmen“ – nichts bleibt ungenannt). Danach gelten die Hinweise „Einschalten“ der Schalter als
        erledigt, die sich einschalten ließen (Intro.SettleAll); was nicht ging, nennt eine Chatzeile. Die Erklärblasen
        der Fenster kommen beim ersten Öffnen wie bisher. Ein „Ja“ im Kampf wird nach dem Kampf ausgeführt. Mit
        gesetzt werden die Schalter aus Intro.ALSO und jeder Schalter, den ein Modul in ns.AGREE mit „on“ anmeldet
        (ezCore: Intro.OWN_AGREE) – alles, was ab Werk aus ist und Blizzards Regeln erlauben (Spieltest 20.11.2026).
        Was sie riskiert („risk“), bleibt aus und steht im Tooltip des Knopfs; Geschmack, Filter, Rücksicht auf fremde
        Addons, Entdecker-Wissen und Entwicklerwerkzeuge („choice“) bleiben, wie sie sind, und stehen in der
        Kurzfassung. Die Kurzfassung ist nur zum Lesen und erledigt nichts.
      * Einverständnis: Intro.CONSENT nennt die Schalter aller Abläufe ohne Klick (Liste in docs/blizzard-regeln.md,
        Abschnitt 5; eine Prüfung vergleicht sie mit ZEILEN und EINZELN aus tools/Tests/optin_test.lua). Quelle der
        Wahrheit bleibt die Einstellung des Moduls: Die Häkchen lesen sie bei jedem Zeichnen, ein Klick setzt sie über
        denselben Weg wie das Kästchen des Moduls (Setting-Objekt, sonst mns.SetSetting; ezCores eigene Schalter über
        Core.ApplyOwnSetting; ezPanels Reparatur über den Eintrag in Core.OptInHint). Im Kampf ändert die Einführung
        nichts und zeigt nichts (danach über Core.AfterCombat).
      * Angebot: EINE Erklärblase nach dem Einloggen (Intro.OFFER_DELAY) mit „Allem zustimmen“, „Einzeln
        entscheiden“, „Kurz“ und „Später“ – links am Addon-Fach der Minikarte mit bündiger Oberkante (Lage „leftTop“),
        sonst über der Reiterleiste des Chats (ohne beides keins). Höchstens
        Intro.MAX_OFFERS-mal je Account („Später“ und das X zählen), nie im Kampf, nie in einer Instanz. Abschaltbar
        über den gemeinsamen Schalter „Hinweise und Angebote zeigen“ (OPT_optInHints) und den Knopf „Nicht mehr
        anbieten“ der Blase (ezCoreDB.intro.never) – das eigene Kästchen OPT_introOffer entfiel mit der
        Einstellungs-Prüfung vom 19.11.2026 (Nr. 55); ein gespeichertes „aus“ wird einmal zu „nicht mehr anbieten“.

      Core.Intro.CONSENT              { { Modul, Schlüssel [, group = Gruppe in ezCoreDB] [, hint = id] } … }
      Core.Intro.ModuleText(name)     → Einführungstext des Moduls (L.INTRO_MOD_<Modul>) oder nil
      Core.Intro.Features(name)       → Kurzüberblick des Moduls: Zeilen aus L.INTRO_FEATURES im Locale des Moduls
                                      (eine Stelle je Modul) oder {}; Core.Intro.FeatureText(name, einrückung) → „• …“ oder nil
      Core.Intro.HasPage(name)        → true, wenn es einen gibt (dann hat die Modulseite den Knopf „Einführung“)
      Core.Intro.PageTip(name)        → Tooltip des Knopfs „Einführung“
      Core.Intro.CommandLine(name)    → „Befehl: … – alle Befehle: …“ (Core.SlashCmd)
      Core.Intro.Get(eintrag)         → true/false; nil, wenn das Modul nicht läuft oder eintrag.available() nicht gilt
      Core.Intro.Default(eintrag)     → Standard ab Werk (ein Eintrag aus Core.OptInHint gilt als ab Werk aus)
      Core.Intro.Set(eintrag, an)     → ok, Grund ("combat" | "absent" | "same" | "blocked" | "own" | "hint" | "module" | "where")
      Core.Intro.CanSwitchOn(eintrag) → false, wenn das Modul den Schalter in ns.SWITCHABLE[Schlüssel] als hier wirkungslos
                                      meldet („Allem zustimmen“ lässt ihn aus, die Kästchen sind grau, Set → "blocked")
      Core.Intro.Label(eintrag), Core.Intro.What(eintrag)   Name des Schalters, was passiert, wenn an
      Core.Intro.Rows(nurLaufende)    → { { entry, module, key, label, what, value, default } … }
      Core.Intro.Lines() / Text()     → Kurzfassung (alle Module, Einverständnis, Mithelfen)
      Core.Intro.ShowShort()          Kurzfassung als Text an Blizzards Einstellungsfenster
      Core.Intro.Pages()              → { { key = "start" }, { key = Modul, module = Modul } …, { key = "consent" },
                                         { key = "help" } } (nur laufende Module)
      Core.Intro.Show(nr | key)       → true, wenn die Blase dieser Seite jetzt steht; Core.Intro.ShowModule(name)
      Core.Intro.HidePager(), Core.Intro.current (Nummer der offenen Seite), Core.Intro.nav (Fenster, Modul der Seite)
      Core.Intro.ALSO                 wie CONSENT, mit dem Einverständnis gesetzt, kein Ablauf ohne Klick
                                      [, on = Wert für „zugestimmt“] [, label = , what = Text von ezCore] – nur für
                                      Einträge ohne eigenes Modul; Module melden ihre über ns.AGREE an (unten)
      ns.AGREE (je Modul)             { [Schlüssel] = "on" | "risk" | "choice" | { "on", on = , label = , what = } }:
                                      jeder Schalter des Moduls, der ab Werk aus ist und kein Ablauf ohne Klick
                                      (Intro.CONSENT); tools/Tests/agree_test.lua prüft die Vollständigkeit
      ns.AGREE_NOTE (je Modul)        fn → Text | nil: Hinweis zu einer Blizzard-Einstellung (ezHeal stellt
                                      „Selbstwirken“ ab Werk um, 23.11.2026) – steht in der Rückfrage von
                                      „Allem zustimmen“, im Chat danach und auf der Seite des Moduls; kein Häkchen
      Core.Intro.Notes(modul)         → { { module, text } … } der laufenden Module (mit modul: nur dieses)
      Core.Intro.NoteText(modul)      → „Modul: Text“ je Zeile | nil
      Core.Intro.OWN_AGREE            dasselbe für ezCores eigene Schalter: { { Schlüssel, Art, group = , text = } … }
      Core.Intro.Registered()         → { { module, key, kind, entry } … } aller laufenden Module und ezCore
      Core.Intro.AlsoEntries()        → Intro.ALSO und die Anmeldungen mit „on“ (wie Intro.CONSENT)
      Core.Intro.Excluded(art, auchAn) → Text „ezBag: Leichter zerstören, …“ der Anmeldungen dieser Art oder nil
      Core.Intro.ConsentRisk(eintrag) → true bei agree = "risk" in Intro.CONSENT: „Allem zustimmen“ lässt ihn aus
      Core.Intro.StaysOff()           → Chatzeile nach „Allem zustimmen“: was weiter aus ist (nur von Hand) oder nil
      Core.Intro.AgreeTip()           → Tooltip des Knopfs „Allem zustimmen“ (mit den Ausnahmen „risk“)
      Core.Intro.SplitAlso(zeilen)    → Zeilen aus CONSENT, Zeilen aus ALSO (row.also) – Anzahlen zählen nur die ersten
      Core.Intro.HintIds(zeilen)      → Kennungen der Hinweise „Einschalten“ dieser Zeilen (Modul.Schlüssel, hint, hints)
      Core.Intro.WINDOWS[modul]       { panel = Name in Core.Panels.LIST, side [, frames + why nur abweichend] } (Spieltest 19.11.)
      Core.Intro.WindowFrames(eintrag) → Rahmen für die Blase (frames, sonst Core.Panels.Frames(panel))
      Core.Intro.PageRows(seite)      → Einverständnis-Zeilen der Seite (Modul; Startseite: ezCore)
      Core.Intro.ToggleRow(zeile)     Häkchen der Blase umlegen (über Intro.Set) → ok
      Core.Intro.Note(modul)          → Anzahl: Schritte seiner Rundgänge, deren Blase jetzt steht, vormerken
      Core.Intro.Settle(modul, zeilen) → Schritte, Hinweise: vorgemerkte Schritte und die Hinweise „Einschalten“ dieser
                                      Zeilen erledigt (ohne zeilen: die der Seite des Moduls)
      Core.Intro.Forget(modul)        vorgemerkte Schritte verwerfen (Kampfbeginn: nichts gilt als gesehen)
      Core.Intro.SettleAll(zeilen)    → Hinweise: die Hinweise „Einschalten“ dieser Zeilen erledigt („Allem zustimmen“:
                                      die eingeschalteten; ohne zeilen: alle laufender Module)
      Core.Intro.HoldsWindow(rahmen)  → true, solange eine Seite der Einführung an diesem Rahmen steht
      Core.Intro.AgreeRows(), AgreeList(zeilen)   was „Allem zustimmen“ einschaltet: Text je Modul, Anzahl Module
      Core.Intro.AgreeAll(beiNein)    Rückfrage, dann Core.Intro.ApplyAll() → eingeschaltet, nicht gegangen (die nicht
                                      gegangenen nennt eine Chatzeile; im Kampf nach dem Kampf, Intro.AGREE_KEY)
      Core.Intro.AddPage(elternseite) baut die Seite „Einführung“ (Collection.lua beim Aufbau der Übersicht)
      Core.Intro.Open()               öffnet sie; Core.Intro.Command(rest) – Befehl „einführung“ von ezCore
      Core.Intro.TryOffer()           → true, wenn das Angebot jetzt kam (Blase); false, Grund
      Core.Intro.ResetOffer()         → true, wenn es schon kam (kommt beim nächsten Einloggen wieder)
      Core.Intro.Existing(speicher)   → true, wenn der Spieler die Einführung schon hatte (angeboten, zugestimmt, „Nicht
                                      mehr anbieten“); Core.Intro.OfferPending(speicher) → true, solange das Angebot noch kommt
      * Nachfrage nach einem Update (Werkzeuge/ConsentNews.lua): Kommen Zeilen dazu, die der Spieler noch nicht
        angeboten bekam, fragt EINE Blase nach genau diesen – mit Häkchen je Zeile, „Alle annehmen“ und „Fertig“.
        Angeboten heißt: Die Zeile stand im Angebot der Einführung, in „Allem zustimmen“, auf einer Seite, die der
        Spieler verlassen hat, oder in der Nachfrage (Intro.MarkKnown). Knopf „Neu seit dem Update“ auf dieser Seite.
    Gemerkt in ezCoreDB.intro = { offered = Anzahl, done = Zeitpunkt, never = true nach „Nicht mehr anbieten“,
    known = { [Intro.EntryId] = true } angebotene Zeilen, news = { Kennung … } die Zeilen der letzten Nachfrage }.
]]

local Intro = {}
Core.Intro = Intro

-- Einmalige Übernahme des früheren Kästchens „Einführung beim ersten Start anbieten“ (Nr. 55): ein „aus“ wird zu
-- „nicht mehr anbieten“. Merker ezCoreDB.migrated.introOffer19. → true, wenn übernommen
function Intro.MigrateOfferSwitch(db)
    if type(db) ~= "table" then return false end
    if type(db.migrated) ~= "table" then db.migrated = {} end
    return Core.MigrateOnce(db.migrated, "introOffer19", function()
        local store = db.intro
        if type(store) ~= "table" or store.introOffer == nil then return false end
        local off = store.introOffer == false
        store.introOffer = nil
        if off then store.never = true end
        return off
    end) == true
end
Core.Listen("CORE_LOADED", function() Intro.MigrateOfferSwitch(Core.db) end, "ezCore.Intro")

-- Abläufe ohne Klick (docs/blizzard-regeln.md, Abschnitt 5): je Schalter eine Zeile. Gruppiert nach „ab Werk aus“ und
-- „ab Werk an“ wird zur Laufzeit über die Standards der Module (Intro.Default), nicht hier.
-- Freies Feld available = fn → bool: die Zeile gilt nur, solange fn wahr ist (sonst liefert Intro.Get nil wie bei
-- einem Modul, das nicht läuft) – für Schalter, die das Modul selbst nur unter einer Bedingung zeigt oder ausführt.
local function CameraKnown()
    local comfort = Core.Comfort
    return type(comfort) == "table" and type(comfort.CameraZoom) == "function" and comfort.CameraZoom() ~= nil
end
-- Gemeinsame Schalter am Händler (Charakter/Junk.lua; Einstellungs-Prüfung 19.11.2026, Nr. 59/60 und 62): eine Zeile
-- für „Plunder verkaufen“ (liest ezBag, sonst ezMerchant) und eine für „Automatisch reparieren“ (liest ezMerchant, sonst
-- ezPanel) – nur, solange eines dieser Module läuft und kein fremdes Addon dasselbe tut (Leitlinie 9). Vorher je Modul
-- eine Zeile (ezBag autoSell, ezMerchant autoSellJunk und repairAuto, ezPanel autoRepair über dessen Hinweis).
local function NoOther(feature)
    return not (type(Core.WhoHandlesInfo) == "function" and Core.WhoHandlesInfo(feature))
end
local function SellRuns()
    return (Core.IsLoaded("ezBag") or Core.IsLoaded("ezMerchant")) and NoOther("sellJunk")
end
local function RepairRuns()
    return (Core.IsLoaded("ezMerchant") or Core.IsLoaded("ezPanel")) and NoOther("repair")
end
Intro.CONSENT = {
    { "ezCore", "autoSell", group = "vendor", text = "vendorAutoSell", available = SellRuns,
        hints = { "ezBag.autoSell", "ezMerchant.autoSellJunk" } },
    { "ezCore", "repairAuto", group = "vendor", text = "vendorRepairAuto", available = RepairRuns,
        hints = { "ezMerchant.repairAuto", "ezPanel.autoRepair" } },
    { "ezMerchant", "restockAuto" },
    -- agree = "risk": „Allem zustimmen“ lässt ihn aus (kostet Porto ohne Klick; Entscheidung des Nutzers vom
    -- 21.11.2026, Intro.ConsentRisk) – einschalten nur von Hand (Häkchen, Seite von ezChat, Hinweis am Briefkasten)
    { "ezChat", "mailDelivery", agree = "risk" }, { "ezChat", "offlineQueue" }, { "ezChat", "catchChatWhispers" },
    -- der Hinweis ezChat.reply schaltet replyCombat und replyInstance ein (ezChat/Situation.lua, REPLY_ON), nicht
    -- replyAway – nur die Zeile seines Schalters erledigt ihn
    { "ezChat", "replyAway" }, { "ezChat", "replyCombat", hints = { "ezChat.reply" } },
    { "ezChat", "shareTyping" }, { "ezChat", "shareZone" },
    { "ezMail", "blockTrades" }, { "ezMail", "autoExpress" },
    -- ezCores Kästchen steht nur, wenn die Kamera-CVar lesbar ist (Bausteine/Comfort.lua)
    { "ezCore", "cameraZoom", group = "comfort", available = CameraKnown },
    { "ezAuction", "buyNextSelect" }, { "ezAuction", "scanOnOpen" },
    { "ezMap", "trackingRemember" }, { "ezMap", "trackingSpellAuto" }, { "ezMap", "wayTrack" },
    { "ezMap", "wayAutoClear" }, { "ezMap", "trackingCouple" },
    { "ezQuest", "sortTracker" }, { "ezQuest", "sortSuperTrack" }, { "ezQuest", "worldSparkle" },
    { "ezQuest", "worldIcons" }, { "ezQuest", "autoQuest" }, { "ezQuest", "autoShare" }, { "ezQuest", "joinShare" },
    { "ezQuest", "routeWatch" },
    { "ezCombat", "rotationEstimate" }, { "ezCombat", "rotation" },
    { "ezMacro", "autoThank" }, { "ezMacro", "autoSpit" }, { "ezMacro", "oneClickUpdate" }, { "ezMacro", "rankAuto" },
    { "ezMacro", "backupOnLogout" },
    { "ezGear", "swapMount" }, { "ezGear", "swapFishing" },
    { "ezLoot", "fastLoot" },
    { "ezSocial", "acceptSummon" }, { "ezSocial", "acceptResurrect" }, { "ezSocial", "blockDuels" },
    { "ezSocial", "blockInvites" },
    { "ezTalent", "makeRoom" },
    { "ezPanel", "reserveTop" },
}
-- Hinweise „Einschalten“ (Core.OptInHint) einer Zeile: "<Modul>.<Schlüssel>", dazu entry.hint und entry.hints – die
-- Kennungen, deren Schalter diese Zeile ist (gemeinsame Schalter am Händler, eine Blase für zwei Antworten). Nur diese
-- gelten als gesehen, wenn die Zeile auf der Seite bzw. in der Liste von „Allem zustimmen“ stand (Nachlauf zum Review
-- von PR 536; vorher alle Hinweise des Moduls, auch nie gezeigte). → Liste
function Intro.HintIds(rows)
    local out, have = {}, {}
    local function Add(id)
        if type(id) == "string" and not have[id] then
            have[id] = true
            out[#out + 1] = id
        end
    end
    for _, row in ipairs(rows or {}) do
        local entry = row.entry or row
        if type(entry) == "table" and entry[1] and entry[2] then
            Add(entry[1] .. "." .. entry[2])
            Add(entry.hint)
            for _, id in ipairs(entry.hints or {}) do Add(id) end
        end
    end
    return out
end
-- Mit dem Einverständnis gesetzt, ohne ein Ablauf ohne Klick zu sein (darum nicht in Intro.CONSENT und nicht in
-- docs/blizzard-regeln.md, Abschnitt 5): Schalter, die der Spieler ausdrücklich mit der Zustimmung gesetzt haben will.
-- Felder wie in Intro.CONSENT; on = der Wert, der „zugestimmt“ heißt (ohne: true); label/what = Text von ezCore.
-- Spielbefund des Nutzers vom 20.11.2026 (Bild 37, wörtlich: „zu dem sollte dieser haken bei dem einverständnis auch
-- gesetzt werden“): „Nur, was ich abbauen kann“ – in ezMap seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 88) der
-- abgewählte Eintrag „Rot – noch nicht abbaubar“ (gatherColorRed) im Kartenfilter „Sammeln“ » „Nach Farbe“. Seit dem
-- Spieltest vom 20.11.2026 meldet ezMap ihn selbst an (ns.AGREE in ezMap/Core.lua); hier stehen nur noch Einträge, die
-- keinem Modul gehören (heute keiner).
Intro.ALSO = {}

-- „Allem zustimmen“ setzt auch die übrigen Schalter, die ab Werk aus sind – soweit Blizzards Regeln es erlauben
-- (Spieltest 20.11.2026, wörtlich: „"allem zustimmen" muss auch die kompakte minikarte aktivieren sowie folgende
-- fuunktionen wenn blizz es erlaubt“). Keine feste Liste hier (Leitlinie 2): Jedes Modul meldet seine Schalter in
-- ns.AGREE neben seinen Standards an (<Modul>/Core.lua), ezCore die eigenen in Intro.OWN_AGREE. Art je Schlüssel:
--   "on"      mit dem Einverständnis gesetzt (ergänzt eine Funktion oder Auskunft, keine reine Optik; nichts davon
--             handelt ohne Klick an Spielern, Gold oder Blizzards geschützten Abläufen)
--   "risk"    bleibt aus: riskiert Blizzards Regeln oder einen Schutz von Blizzard (sendet, wählt, verbraucht oder
--             gibt Gold aus ohne Klick, schreibt in Blizzards Felder, hebt eine Sicherung auf; docs/blizzard-regeln.md)
--             – der Tooltip von „Allem zustimmen“ und die Rückfrage nennen ihn
--   "choice"  bleibt, wie es ist: keine Funktion, sondern Geschmack oder Filter, Hilfe, die nur manche brauchen
--             (Farbenblind-Hilfe, Entscheidung vom 21.11.2026), Rücksicht auf ein fremdes Addon
--             (Leitlinie 9), Entdecker-Wissen (Leitlinie 11, nur auf ausdrücklichen Wunsch) oder Entwicklerwerkzeug –
--             die Kurzfassung nennt ihn
--   { "on", on = false, label = , what = }   wie ein Eintrag in Intro.CONSENT (on = Wert, der „zugestimmt“ heißt)
-- Abläufe ohne Klick (Intro.CONSENT) stehen nicht in ns.AGREE. tools/Tests/agree_test.lua liest die Standards jedes
-- Moduls und meldet jeden Schalter, der ab Werk aus ist und weder in Intro.CONSENT noch angemeldet ist.
Intro.AGREE_KINDS = { on = true, risk = true, choice = true }
-- available wie in Intro.CONSENT: Übernimmt ein fremdes Addon die Funktion (Leitlinie 9), steht die Zeile nicht da und
-- „Allem zustimmen“ schaltet nichts ein, was ezCore dann ohnehin ruhen lässt
-- Was nur die Optik nach Geschmack ändert (Zeichen, Farben, zusätzliche Texte oder Knöpfe, Skalierung, Ausblenden),
-- ergänzt keine Funktion und ist "choice" (Spieltest 20.11.2026, Knopf mit „o fehlt“, wörtlich „mh was soll das sein“; Folgeauftrag der Hauptsession)
Intro.OWN_AGREE = {
    -- Blizzards Fehlerbericht-Knopf und Umfragen ausblenden: nur weniger auf dem Bildschirm, Geschmack
    { "betaHints", "choice", group = "comfort", available = function() return NoOther("betaHints") end },
    -- Farbenblind-Zeichen (? > + !) am Leuchten: Barrierefreiheit nach Bedarf, nur wer sie braucht (Entscheidung vom
    -- 21.11.2026: „nur optional anschaltbar, standardmäßig aus“)
    { "glowMarks", "choice", group = "comfort" },
    { "moveFrames", "on", group = "comfort", available = function() return NoOther("moveFrames") end },
    -- Skalieren: zusätzliche Knöpfe „-“ und „+“ an jeder Titelleiste, Größe nach Geschmack
    { "frameScale", "choice", group = "comfort", available = function() return NoOther("moveFrames") end },
    -- Kennungen im Tooltip sind ein Werkzeug zum Nachschlagen, kein Gewinn für jeden (Entscheidung vom 19.11.2026)
    { "ids", "choice", group = "tooltip", text = "ttIDs" },
    -- zusätzliche Münze an Taschenplätzen (dieselbe Auskunft steht am Händler und im Tooltip): Zeichen nach Geschmack
    { "worthBag", "choice", group = "priceOpts", text = "auctionWorthBag" },
    -- Gildengold geht ohne Klick aus (Reparatur am Händler)
    { "repairGuild", "risk", group = "vendor", text = "vendorRepairGuild" },
    -- Entdecker-Wissen nur auf ausdrücklichen Wunsch (Leitlinie 11)
    { "explorer", "choice", group = "discovery" },
    { "locked", "choice", group = "gatherCare", text = "gatherLocked" },
    { "developer", "choice", group = "comfort" },
}

Intro.OFFER_DELAY = 12          -- Sekunden nach dem Einloggen (die Chatzeile des ersten Starts kommt nach 8)
Intro.MAX_OFFERS = 2             -- so oft je Account höchstens
Intro.AFTER_COMBAT_DELAY = 5     -- Sekunden nach dem Kampf, bevor ein im Kampf fälliges Angebot kommt
Intro.SIDE = "right"             -- Lage der Blase zu Blizzards Einstellungsfenster
Intro.BUTTON_WIDTH = 100         -- „Zurück“ und „Weiter“ nebeneinander in der Blase
Intro.BOX_WIDTH = 300            -- Blase der Seiten: breiter als Blizzards 226, je Ablauf ohne Klick ein Häkchen
Intro.TEXT_WIDTH = 270
Intro.CHECK_SIZE = 24
Intro.ALSO_NAMES = 6             -- „Allem zustimmen“: bis zu so vielen Mit-Schaltern die Namen im Chat, darüber die Anzahl
Intro.AGREE_LINES = 10           -- „Allem zustimmen“: bis zu so vielen Modulen Core.Confirm, darüber ein Textfenster
Intro.COMBAT_KEY = "ezCore.intro"
Intro.OFFER_KEY = "ezCore.introOffer"
-- Eigener Schlüssel für ein „Ja“ zu „Allem zustimmen“ im Kampf (Nachlauf zum Review von PR 536): unter COMBAT_KEY
-- ersetzte jeder spätere Aufruf der Einführung im Kampf (Seite zeigen, Kurzfassung) das vorgemerkte „Ja“
Intro.AGREE_KEY = "ezCore.introAgree"

-- Text oder nil (Core.NewLocale liefert für einen fehlenden Schlüssel den Schlüssel selbst)
local function Lookup(tbl, key)
    if type(tbl) ~= "table" then return nil end
    local value = tbl[key]
    if type(value) ~= "string" or Core.IsSecret(value) or value == "" or value == key then return nil end
    return value
end

local function ModuleNs(name)
    local mod = Core.Module and Core.Module(name)
    local mns = type(mod) == "table" and mod.ns or nil
    if type(mns) ~= "table" or type(mns.S) ~= "table" then return nil end
    return mns
end
Intro.ModuleNs = ModuleNs      -- auch für die Nachfrage nach einem Update (Werkzeuge/ConsentNews.lua)

local function ModuleL(name)
    if name == ADDON then return L end
    local mod = Core.Module and Core.Module(name)
    local mns = type(mod) == "table" and mod.ns or nil
    return type(mns) == "table" and type(mns.L) == "table" and mns.L or nil
end

local function HintEntry(entry)
    local hints = Core.OptInHint
    if type(entry) ~= "table" or not entry.hint or not (hints and hints.Entry) then return nil end
    return hints.Entry(entry.hint)
end

function Intro.ModuleText(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return nil end
    return Lookup(L, "INTRO_MOD_" .. name)
end

-- Kurzüberblick je Modul (Wunsch des Nutzers vom 21.11.2026: „bei der einführung neben dem einverständnis einholen auch
-- die funktionen des jeweiligen moduls kurz und kackig erzählen“): L.INTRO_FEATURES im Locale des Moduls – eine Stelle je
-- Modul (SSOT), deutsch und englisch, 3 bis 6 Zeilen durch einen Zeilenumbruch getrennt. Seite, Tooltip des Knopfs
-- „Einführung“ und Kurzfassung zeigen sie als Punkte vor dem Einführungstext (INTRO_MOD_<Modul>: nur noch, wo das Modul
-- sitzt) und vor den Häkchen. → Liste der Zeilen (leer ohne)
Intro.FEATURES_KEY = "INTRO_FEATURES"
function Intro.Features(name)
    local out = {}
    if type(name) ~= "string" or Core.IsSecret(name) or name == ADDON then return out end
    local mL = ModuleL(name)
    if mL == L then return out end
    local text = Lookup(mL, Intro.FEATURES_KEY)
    if not text then return out end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then out[#out + 1] = line end
    end
    return out
end

-- Die Zeilen als Punkte („• …“, eine je Zeile, mit Einrückung davor). → Text oder nil
function Intro.FeatureText(name, indent)
    local lines = {}
    for _, line in ipairs(Intro.Features(name)) do lines[#lines + 1] = (indent or "") .. L.INTRO_FEATURE_LINE:format(line) end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n")
end

function Intro.HasPage(name)
    return Intro.ModuleText(name) ~= nil
end

function Intro.PageTip(name)
    local text = Intro.ModuleText(name)
    local tip = L.INTRO_PAGE_TIP:format(tostring(name))
    if text then tip = text .. "\n\n" .. tip end
    -- was das Modul kann zuerst, wie auf seiner Seite (Kurzüberblick); INTRO_MOD sagt nur noch, wo es sitzt
    local features = Intro.FeatureText(name)
    if features then tip = features .. "\n\n" .. tip end
    return tip
end

function Intro.CommandLine(name)
    return L.INTRO_CMD:format(Core.SlashCmd(name), Core.SlashCmd(name, L.INTRO_HELP_WORD))
end

---------------------------------------------------------------------------
-- Einverständnis: lesen und setzen über die Einstellung des Moduls
---------------------------------------------------------------------------

-- Wert der Einstellung, der „zugestimmt“ heißt (Intro.ALSO: on = false für einen Schalter, der zum Zustimmen aus muss)
local function Wanted(entry)
    if entry.on == nil then return true end
    return entry.on == true
end

function Intro.Get(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.available) == "function" then
        local ok, yes = Core.Try(nil, "Intro.available", entry.available)
        if not ok or Core.IsSecret(yes) or not yes then return nil end
    end
    local key = entry[2]
    -- entry.get/entry.set: ein Zustand statt eines Schalters (ezMap „Alles aufspüren“: Blizzards Haken, kein Schlüssel in
    -- ns.S; Spieltest 24.11.2026). get = fn() → true | false | nil (gilt hier nicht), set = fn(an) → false, wenn es nicht ging
    if type(entry.get) == "function" then
        local ok, value = Core.Try(entry[1], "Intro.Get", entry.get)
        if not ok or Core.IsSecret(value) or value == nil then return nil end
        return value == true
    end
    if entry.group then return Core.OwnSetting(entry.group, key) == Wanted(entry) end
    if entry.hint then
        local def = HintEntry(entry)
        if not def then return nil end
        local ok, on = Core.Try(def.owner, "Intro.Get", def.isOn)
        return ok and not Core.IsSecret(on) and on == true
    end
    local mns = ModuleNs(entry[1])
    if not mns then return nil end
    local value = mns.S[key]
    if Core.IsSecret(value) then return nil end
    if value == nil and entry.on ~= nil then return nil end   -- Schalter, den das Modul nicht (mehr) kennt
    return value == Wanted(entry)
end

-- Standard ab Werk im Sinn von „zugestimmt“ (mit entry.on umgerechnet)
local function AsConsent(entry, raw)
    if raw == nil or entry.on == nil then return raw end
    return raw == Wanted(entry)
end

function Intro.Default(entry)
    if type(entry) ~= "table" then return nil end
    if entry.group then
        local defaults = Core.DEFAULTS[entry.group]
        return AsConsent(entry, defaults and defaults[entry[2]])
    end
    -- Einträge in ezCores Hinweis-Helfer sind Abläufe, die ab Werk aus sind (Kern/OptInHint.lua); ein Zustand
    -- (entry.get) hat keinen Standard von ezCollection
    if entry.hint or type(entry.get) == "function" then return false end
    local mns = ModuleNs(entry[1])
    local defaults = mns and mns.DEFAULTS
    if type(defaults) ~= "table" then return nil end
    return AsConsent(entry, defaults[entry[2]])
end

function Intro.Label(entry)
    local def = HintEntry(entry)
    if def then
        local label = def.label
        if type(label) == "function" then
            local ok, text = Core.Try(def.owner, "Intro.Label", label)
            label = ok and text or nil
        end
        if type(label) == "string" and label ~= "" then return label end
    end
    -- entry.label: eigener Text von ezCore (Intro.ALSO – der Name des Moduls passt zum umgekehrten Schalter nicht)
    local own = type(entry.label) == "string" and Lookup(L, entry.label) or nil
    if own then return own end
    -- entry.text: Schlüssel des Textes, wenn er vom Schlüssel der Einstellung abweicht (gemeinsame Schalter von ezCore)
    return Lookup(ModuleL(entry[1]), "OPT_" .. (entry.text or entry[2])) or tostring(entry[2])
end

function Intro.What(entry)
    local key = entry[2]
    local def = HintEntry(entry)
    if def then
        local what = def.what
        if type(what) == "function" then
            local ok, text = Core.Try(def.owner, "Intro.What", what)
            what = ok and text or nil
        end
        if type(what) == "string" and what ~= "" then return what end
    end
    local own = type(entry.what) == "string" and Lookup(L, entry.what) or nil
    if own then return own end
    local mL = ModuleL(entry[1])
    return Lookup(mL, "OPTIN_" .. key) or Lookup(L, "INTRO_ON_" .. key) or Lookup(mL, "OPT_" .. key .. "_TIP") or ""
end

-- Lässt sich die Zeile hier sinnvoll einschalten? Ein Modul meldet Schalter, die auf diesem Client nie wirken können, in
-- ns.SWITCHABLE[Schlüssel] = fn() → bool – dieselbe Funktion graut das Kästchen auf der Seite des Moduls (ezMacro
-- „Fremden Heilern danken“: WoW Forever sperrt die Heilvorhersage). Spieltest 20.11.2026: „Allem zustimmen“ schaltete
-- ihn trotzdem ein, ezMacro meldete gleich danach „ohne Wirkung“. Ohne Eintrag, bei einem Fehler im Prädikat (steht in
-- der Fehlerliste) oder einem geheimen Wert: ja. Nur für Einstellungen eines Moduls, nicht für group/hint, und nur, wo
-- „zustimmen“ die Einstellung einschaltet (ein umgekehrter Eintrag mit on = false schaltet sie aus – das geht immer). → bool
function Intro.CanSwitchOn(entry)
    if type(entry) ~= "table" or entry.group or entry.hint or type(entry.get) == "function" or not Wanted(entry) then
        return true
    end
    local mns = ModuleNs(entry[1])
    local list = mns and mns.SWITCHABLE
    local fn = type(list) == "table" and list[entry[2]] or nil
    if type(fn) ~= "function" then return true end
    local ok, yes = Core.Try(entry[1], "Intro.CanSwitchOn", fn)
    if not ok or Core.IsSecret(yes) then return true end
    return yes ~= false
end

function Intro.Set(entry, value)
    value = value == true
    if type(entry) ~= "table" then return false, "absent" end
    if Core.InCombat() then
        Core.CombatNotice(ns, L.INTRO_SET_WHAT)
        return false, "combat"
    end
    local current = Intro.Get(entry)
    if current == nil then return false, "absent" end
    if current == value then return true, "same" end
    -- zustimmen zu einem Schalter, der hier nie wirkt: nicht einschalten (Ausschalten geht immer)
    if value and not Intro.CanSwitchOn(entry) then
        ns.Print(L.INTRO_SET_BLOCKED:format(Intro.Label(entry), tostring(entry[1])))
        return false, "blocked"
    end
    local key = entry[2]
    if type(entry.get) == "function" then
        local ok, done = Core.Try(entry[1], "Intro.Set", entry.set, value)
        return ok and not Core.IsSecret(done) and done ~= false, "state"
    end
    -- der Wert der Einstellung: „zugestimmt“ ist Wanted(entry), sonst das Gegenteil
    local target = Wanted(entry)
    if not value then target = not target end
    if entry.group then
        Core.ApplyOwnSetting(entry.group, key, target)
        return Core.OwnSetting(entry.group, key) == target, "own"
    end
    if entry.hint then
        local def = HintEntry(entry)
        local fn
        if def then
            if value then fn = def.enable else fn = def.disable end
        end
        if type(fn) ~= "function" then
            -- Der Hinweis kann nur einschalten (ezPanels Reparatur: Schalter im Menü des Bausteins): den Weg nennen
            local where = def and def.where
            if type(where) == "function" then
                local ok, text = Core.Try(def.owner, "Intro.where", where)
                where = ok and text or nil
            end
            ns.Print(L.INTRO_OFF_WHERE:format(Intro.Label(entry), type(where) == "string" and where or entry[1]))
            return false, "where"
        end
        Core.Try(def.owner, "Intro.Set", fn)
        return Intro.Get(entry) == value, "hint"
    end
    local mns = ModuleNs(entry[1])
    -- derselbe Weg wie das Kästchen des Moduls: Blizzards Setting-Objekt (das Kästchen zieht nach, ns.SettingChanged
    -- läuft), sonst die Einstellung des Moduls direkt
    local setting = type(mns.settingObjects) == "table" and mns.settingObjects[key] or nil
    if type(setting) == "table" and type(setting.SetValue) == "function" then pcall(setting.SetValue, setting, target) end
    if mns.S[key] ~= target and type(mns.SetSetting) == "function" then mns.SetSetting(key, target) end
    return mns.S[key] == target, "module"
end

-- Knopf der Seite „Einführung“ zu einem Zustand: umschalten und sagen, was jetzt gilt (der Knopf zeigt den Stand nicht).
-- → ok, Grund
function Intro.ToggleState(entry)
    local want = Intro.Get(entry) ~= true
    local ok, why = Intro.Set(entry, want)
    if ok then
        ns.Print((want and L.INTRO_STATE_ON or L.INTRO_STATE_OFF):format(Intro.Label(entry)))
    elseif why ~= "combat" then     -- Kampf sagt Intro.Set selbst
        ns.Print(L.INTRO_STATE_FAILED:format(Intro.Label(entry)))
    end
    return ok, why
end

-- Art und Felder einer Anmeldung: "on" | "risk" | "choice" oder { Art, on = …, label = …, what = … }. → Art, Felder
local function AgreeKind(value)
    if type(value) == "string" then return value, nil end
    if type(value) == "table" then return value[1], value end
    return nil, nil
end

local function AgreeEntry(module, key, fields)
    local entry = { module, key }
    for field, value in pairs(fields or {}) do
        if type(field) == "string" then entry[field] = value end
    end
    return entry
end

-- Alle Anmeldungen laufender Module (Reihenfolge der Module, je Modul nach Schlüssel), danach ezCores eigene.
-- → { { module, key, kind, entry } … }; entry wie in Intro.CONSENT
function Intro.Registered()
    local out = {}
    for _, name in ipairs(Core.ModuleNames and Core.ModuleNames() or {}) do
        local mns = name ~= ADDON and ModuleNs(name) or nil
        local list = mns and mns.AGREE
        if type(list) == "table" then
            local keys = {}
            for key in pairs(list) do
                if type(key) == "string" then keys[#keys + 1] = key end
            end
            table.sort(keys)
            for _, key in ipairs(keys) do
                local kind, fields = AgreeKind(list[key])
                if Intro.AGREE_KINDS[kind] then
                    out[#out + 1] = { module = name, key = key, kind = kind, entry = AgreeEntry(name, key, fields) }
                end
            end
        end
    end
    for _, own in ipairs(Intro.OWN_AGREE or {}) do
        if type(own) == "table" and Intro.AGREE_KINDS[own[2]] then
            out[#out + 1] = { module = ADDON, key = own[1], kind = own[2], entry = AgreeEntry(ADDON, own[1], own) }
        end
    end
    return out
end

-- Intro.ALSO und alle Anmeldungen mit „on“ (wie Einträge in Intro.CONSENT). → Liste
-- Kennung einer Zeile: Modul[.Gruppe].Schlüssel (ezCores Schlüssel gibt es in mehreren Gruppen)
local function EntryId(entry)
    return tostring(entry[1]) .. "." .. (entry.group and (entry.group .. ".") or "") .. tostring(entry[2])
end
Intro.EntryId = EntryId

-- Intro.ALSO und alle Anmeldungen mit „on“ (wie Einträge in Intro.CONSENT), ohne Doppel: was schon in Intro.CONSENT
-- oder davor in der Liste steht, kommt nicht noch einmal (sonst zwei Zeilen und zwei gleichnamige Häkchen). → Liste
function Intro.AlsoEntries()
    local list, seen = {}, {}
    for _, entry in ipairs(Intro.CONSENT or {}) do seen[EntryId(entry)] = true end
    local function Add(entry)
        local id = EntryId(entry)
        if not seen[id] then
            seen[id] = true
            list[#list + 1] = entry
        end
    end
    for _, entry in ipairs(Intro.ALSO or {}) do Add(entry) end
    for _, reg in ipairs(Intro.Registered()) do
        if reg.kind == "on" then Add(reg.entry) end
    end
    return list
end

-- Hinweise beim Zustimmen (Entscheidung des Nutzers vom 23.11.2026 zu ezHeal, wörtlich „kein umbau, beim zustimmen
-- hinweis geben dass standardmäßig aus“, bestätigt mit „Ja, genau so“): Ein Modul meldet mit
-- ns.AGREE_NOTE = fn → Text | nil einen Hinweis zu einer Blizzard-Einstellung an (ezHeal: stellt sie ab Werk um). Er
-- steht in der Rückfrage von „Allem zustimmen“, im Chat danach und auf der Seite des Moduls – nur, solange fn einen
-- Text liefert. Kein Häkchen; die Einführung setzt dabei nichts.
-- → { { module, text } … } der laufenden Module (Reihenfolge der Module)
function Intro.Notes(only)
    local out = {}
    for _, name in ipairs(Core.ModuleNames and Core.ModuleNames() or {}) do
        local mns = name ~= ADDON and (only == nil or only == name) and ModuleNs(name) or nil
        local fn = mns and mns.AGREE_NOTE
        if type(fn) == "function" then
            local ok, text = pcall(fn)
            -- ein Fehler im Modul landet in dessen Fehlerliste (wie mns.Try), der Hinweis fehlt dann nur (Review 23.11.2026)
            if not ok then Core.Error(name, text, "AGREE_NOTE") end
            if ok and type(text) == "string" and not Core.IsSecret(text) and text ~= "" then
                out[#out + 1] = { module = name, text = text }
            end
        end
    end
    return out
end

-- Hinweise als ein Text („ezHeal: …“, je Modul eine Zeile) | nil
function Intro.NoteText(only)
    local lines = {}
    for _, note in ipairs(Intro.Notes(only)) do lines[#lines + 1] = L.INTRO_AGREE_LINE:format(note.module, note.text) end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

-- Zeilen aus Intro.CONSENT, danach Intro.ALSO und die Anmeldungen mit „on“ (Intro.AlsoEntries); row.also: kein
-- Ablauf ohne Klick, darum in keiner Anzahl „Abläufe ohne Klick“ und unter eigenem Kopf (Intro.SplitAlso)
function Intro.Rows(runningOnly)
    local rows = {}
    for index, list in ipairs({ Intro.CONSENT, Intro.AlsoEntries() }) do
        for _, entry in ipairs(list) do
            local value = Intro.Get(entry)
            if value ~= nil or not runningOnly then
                rows[#rows + 1] = { entry = entry, module = entry[1], key = entry[2], value = value, also = index == 2,
                    default = Intro.Default(entry), label = Intro.Label(entry), what = Intro.What(entry) }
            end
        end
    end
    return rows
end

-- Zeilen trennen: Abläufe ohne Klick (Intro.CONSENT) und Mit-Schalter (Intro.ALSO, row.also). → zwei Listen
function Intro.SplitAlso(rows)
    local consent, also = {}, {}
    for _, row in ipairs(rows or {}) do
        if row.also then also[#also + 1] = row else consent[#consent + 1] = row end
    end
    return consent, also
end

-- Mit-Schalter trennen: ab Werk aus (Intro.ALSO, Anmeldungen) und ab Werk an, vom Spieler ausgeschaltet (row.accept,
-- Intro.AcceptRows). → zwei Listen
local function SplitAccept(also)
    local plain, again = {}, {}
    for _, row in ipairs(also) do
        if row.accept then again[#again + 1] = row else plain[#plain + 1] = row end
    end
    return plain, again
end

-- Namen der Zeilen („ezMap: Sammel-Fundorte …“), mit Komma. → Text
local function RowNames(rows)
    local names = {}
    for _, row in ipairs(rows) do names[#names + 1] = L.INTRO_AGREE_LINE:format(row.module, row.label) end
    return table.concat(names, ", ")
end

-- Ablauf ohne Klick, den „Allem zustimmen“ auslässt: agree = "risk" an seinem Eintrag in Intro.CONSENT – er kostet oder
-- riskiert etwas ohne Klick (ezChats Briefversand kostet Porto; Entscheidung des Nutzers vom 21.11.2026: „das darf in
-- dem fall nicht passieren“). Er bleibt ein Häkchen der Einführung und wird wie die Anmeldungen „risk“ genannt.
-- → true oder false
local function ConsentRisk(entry)
    return type(entry) == "table" and entry.agree == "risk"
end
Intro.ConsentRisk = ConsentRisk

-- Anmeldungen dieser Art („risk“ oder „choice“) laufender Module, die jetzt aus sind („ezBag: Leichter zerstören,
-- …“; mit Komma). Was der Spieler selbst schon eingeschaltet hat, nennt die Liste nicht – außer mit evenIfOn (Tooltip
-- des Knopfs: er steht ab dem Bau der Seite fest und sagt nur, was „Allem zustimmen“ nicht einschaltet). → Text oder nil
function Intro.Excluded(kind, evenIfOn)
    local names = {}
    if kind == "risk" then   -- zuerst die Abläufe ohne Klick mit agree = "risk" (Intro.ConsentRisk)
        for _, entry in ipairs(Intro.CONSENT or {}) do
            if ConsentRisk(entry) then
                local value = Intro.Get(entry)   -- nil: Modul läuft nicht
                if value == false or (evenIfOn and value == true) then
                    names[#names + 1] = L.INTRO_AGREE_LINE:format(entry[1], Intro.Label(entry))
                end
            end
        end
    end
    for _, reg in ipairs(Intro.Registered()) do
        local value = Intro.Get(reg.entry)
        if reg.kind == kind and (value == false or (evenIfOn and value ~= nil)) then
            names[#names + 1] = L.INTRO_AGREE_LINE:format(reg.module, Intro.Label(reg.entry))
        end
    end
    if #names == 0 then return nil end
    return table.concat(names, ", ")
end

-- Was nach „Allem zustimmen“ weiter aus ist und nur von Hand an geht (Wunsch des Nutzers vom 21.11.2026: „allg. sollte
-- kurz gesagt werden was nach alle annehmen weiterhin aus ist, manuell eingestellt werden musss“). Kurz (Review): mit
-- Namen nur die ausgelassenen Abläufe ohne Klick (Intro.ConsentRisk, je Modul gruppiert – die hätte man von „Allem
-- zustimmen“ erwartet), die übrigen riskanten und die Geschmacks-Anmeldungen als Anzahl je Modul; alle Namen stehen
-- in der Rückfrage davor und in der Kurzfassung. → Text oder nil (nichts mehr aus)
local function ModuleCounts(kind)
    local counts, order = {}, {}
    for _, reg in ipairs(Intro.Registered()) do
        if reg.kind == kind and Intro.Get(reg.entry) == false then
            if not counts[reg.module] then order[#order + 1] = reg.module end
            counts[reg.module] = (counts[reg.module] or 0) + 1
        end
    end
    local list = {}
    for _, module in ipairs(order) do list[#list + 1] = L.INTRO_OFF_COUNT:format(module, counts[module]) end
    return #list > 0 and table.concat(list, ", ") or nil
end

function Intro.StaysOff()
    local parts = {}
    local byModule, order = {}, {}
    for _, entry in ipairs(Intro.CONSENT or {}) do
        if ConsentRisk(entry) and Intro.Get(entry) == false then
            local module = entry[1]
            if not byModule[module] then
                byModule[module] = {}
                order[#order + 1] = module
            end
            table.insert(byModule[module], Intro.Label(entry))
        end
    end
    for _, module in ipairs(order) do
        parts[#parts + 1] = L.INTRO_AGREE_LINE:format(module, table.concat(byModule[module], ", "))
    end
    local risk = ModuleCounts("risk")
    if risk then parts[#parts + 1] = L.INTRO_OFF_RISK:format(risk) end
    local choice = ModuleCounts("choice")
    if choice then parts[#parts + 1] = L.INTRO_OFF_CHOICE:format(choice) end
    if #parts == 0 then return nil end
    return L.INTRO_AGREE_STAYS_OFF:format(table.concat(parts, "; "), Core.SlashCmd(ns, L.INTRO_CMD_WORD))
end

-- Tooltip des Knopfs „Allem zustimmen“: was er tut und was er auslässt, weil es Blizzards Regeln riskiert. → Text
function Intro.AgreeTip()
    local risk = Intro.Excluded("risk", true)
    if not risk then return L.INTRO_AGREE_TIP end
    return L.INTRO_AGREE_TIP .. "\n\n" .. L.INTRO_AGREE_RISK:format(risk)
end

---------------------------------------------------------------------------
-- Kurzfassung (alles auf einer Seite)
---------------------------------------------------------------------------

local function ConsentLines(lines, rows)
    local consent, also = Intro.SplitAlso(rows)
    for pass = 1, 2 do
        local wantOn = pass == 2
        local head = false
        for _, row in ipairs(consent) do
            if (row.default == true) == wantOn then
                if not head then
                    lines[#lines + 1] = wantOn and L.INTRO_CONSENT_ON_HEAD or L.INTRO_CONSENT_OFF_HEAD
                    head = true
                end
                lines[#lines + 1] = "  " .. L.INTRO_CONSENT_LINE:format(row.value and L.INTRO_STATE_ON or L.INTRO_STATE_OFF,
                    row.module, row.label, row.what)
            end
        end
    end
    if #also > 0 then lines[#lines + 1] = L.INTRO_ALSO_HEAD end
    for _, row in ipairs(also) do
        lines[#lines + 1] = "  " .. L.INTRO_CONSENT_LINE:format(row.value and L.INTRO_STATE_ON or L.INTRO_STATE_OFF,
            row.module, row.label, row.what)
    end
end

function Intro.Lines()
    local lines = { L.INTRO_DIALOG_TITLE, "", L.INTRO_ABOUT, "" }
    local loaded = ModuleLists()
    lines[#lines + 1] = L.INTRO_MODULES_HEAD:format(#loaded)
    for _, name in ipairs(Core.ModuleNames and Core.ModuleNames() or {}) do
        local state = Core.ModuleState(name)
        local text = Intro.ModuleText(name) or Core.ModuleTip(name) or ""
        if state == "loaded" then
            lines[#lines + 1] = "  " .. name
            -- wie auf der Seite des Moduls: zuerst, was es kann, dann wo es sitzt
            local features = Intro.FeatureText(name, "    ")
            if features then lines[#lines + 1] = features end
            if text ~= "" then lines[#lines + 1] = "    " .. text end
            lines[#lines + 1] = "    " .. Intro.CommandLine(name)
        else
            lines[#lines + 1] = "  " .. name .. " (" .. (state == "absent" and L.INTRO_MODULE_ABSENT or L.INTRO_MODULE_OFF) .. ")"
            if text ~= "" then lines[#lines + 1] = "    " .. text end
        end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L.INTRO_CONSENT_HEAD
    ConsentLines(lines, Intro.Rows(true))
    -- was „Allem zustimmen“ auslässt (Anmeldungen „risk“ und „choice“, Spieltest 20.11.2026)
    local risk, choice = Intro.Excluded("risk"), Intro.Excluded("choice")
    if risk then lines[#lines + 1] = L.INTRO_AGREE_RISK:format(risk) end
    if choice then lines[#lines + 1] = L.INTRO_AGREE_CHOICE:format(choice) end
    lines[#lines + 1] = L.INTRO_CONSENT_WHERE
    if Core.Contribute then
        lines[#lines + 1] = ""
        lines[#lines + 1] = L.INTRO_HELP_HEAD
        lines[#lines + 1] = "  " .. L.INTRO_HELP:format(Core.SlashCmd(ns, L.INTRO_HELP_CMD))
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = L.INTRO_WHERE
    return lines
end

function Intro.Text()
    return table.concat(Intro.Lines(), "\n")
end

-- Seite „Einführung“ öffnen (im Kampf vorgemerkt über Core.OpenSettingsCategory); ohne Seite die Übersicht
function Intro.Open()
    local page = Intro.page
    if type(page) == "table" and type(page.Open) == "function" then return page:Open() end
    return Core.OpenSettings and Core.OpenSettings() or false
end

-- key: eigener Schlüssel für Core.AfterCombat (ohne: Intro.COMBAT_KEY – der letzte Aufruf im Kampf gilt)
local function Later(fn, key)
    Core.CombatNotice(ns, L.INTRO_WHAT, "later")
    Core.AfterCombat(fn, key or Intro.COMBAT_KEY, ADDON)
    return false
end

local function OfferStore()
    local db = Core.db
    if type(db) ~= "table" then return nil end
    if type(db.intro) ~= "table" then db.intro = {} end
    return db.intro
end
Intro.OfferStore = OfferStore

-- Hatte der Spieler die Einführung schon? Angeboten (auch „Später“), zugestimmt oder „Nicht mehr anbieten“. → bool
function Intro.Existing(store)
    store = store or OfferStore()
    if type(store) ~= "table" then return false end
    return store.done ~= nil or (tonumber(store.offered) or 0) > 0 or store.never == true
end

-- Kommt das Angebot der Einführung noch (nicht abgelehnt, nicht erledigt, noch nicht MAX_OFFERS-mal)? → bool
function Intro.OfferPending(store)
    store = store or OfferStore()
    if type(store) ~= "table" then return false end
    return store.never ~= true and store.done == nil and (tonumber(store.offered) or 0) < Intro.MAX_OFFERS
end

-- Diese Zeilen hat der Spieler angeboten bekommen (Nachfrage nach einem Update, Werkzeuge/ConsentNews.lua: dort
-- Intro.MarkKnown; die Datei lädt nach dieser). → Anzahl neu gemerkter
local function MarkKnown(rows)
    if type(Intro.MarkKnown) ~= "function" then return 0 end
    return Intro.MarkKnown(rows)
end

-- Merker anlegen, ehe das Angebot oder die Zustimmung zählt: bei einer Neuinstallation gilt dabei alles, was ab Werk an
-- ist, als bekannt (Intro.Known in ConsentNews.lua unterscheidet das an Intro.Existing)
local function PrepareKnown()
    if type(Intro.Known) == "function" then Intro.Known() end
end

-- Laufende Module mit Seite in der Einführung (dieselbe Reihenfolge wie die Seiten)
local function RunningPageModules()
    local out = {}
    for _, name in ipairs(Core.ModuleNames and Core.ModuleNames() or {}) do
        if Core.ModuleState(name) == "loaded" and Intro.HasPage(name) then out[#out + 1] = name end
    end
    return out
end

---------------------------------------------------------------------------
-- Erledigt: Blasen und Hinweise eines Moduls (Spieltest 19.11.2026, S-1911-Einfuehrung)
---------------------------------------------------------------------------

-- Wer die Seite eines Moduls in der Einführung gesehen hat, bekommt dessen Erklärblasen beim Öffnen des Fensters nicht
-- mehr (Rundgänge über Core.ModuleTours, Bausteine/Widgets.lua) und auch nicht die Blase „Einschalten“ von
-- Core.OptInHint – über seine Abläufe ohne Klick hat er auf der Seite schon entschieden.
-- Gegenprüfung: nur die Schritte, deren Ziel während der Seite zu sehen war – die Seite von ezMerchant steht am
-- Zauberbuch, seine Blasen am Händler und am Lehrer bleiben; an einer Einstellungsseite (ezMail, ezAuction …) bleibt
-- der ganze Rundgang. Nachlauf zum Review von PR 536: auch am Fenster nur die Blasen, die wirklich standen
-- (tour:ShownSteps beim Zeigen, kurz danach und beim Verlassen) – ein sichtbares Ziel allein reichte vorher, auch für
-- Schritte, deren Blase noch gar nicht an der Reihe war. Bestätigte Blasen („OK“, X) merkt der Rundgang selbst.
local noted = setmetatable({}, { __mode = "k" })    -- Rundgang → { [Schlüssel] = true }

function Intro.Note(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return 0 end
    local n = 0
    for _, tour in ipairs(Core.ModuleTours and Core.ModuleTours(name) or {}) do
        if type(tour.ShownSteps) == "function" then
            local ok, set = Core.Try(nil, "Intro.Note", tour.ShownSteps, tour)
            if ok and type(set) == "table" then
                local mine = noted[tour] or {}
                noted[tour] = mine
                for key in pairs(set) do
                    if not mine[key] then
                        mine[key] = true
                        n = n + 1
                    end
                end
            end
        end
    end
    return n
end

function Intro.Forget(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return end
    for _, tour in ipairs(Core.ModuleTours and Core.ModuleTours(name) or {}) do noted[tour] = nil end
end

-- rows: die Einverständnis-Zeilen, die auf der Seite standen (ohne: die der Seite des Moduls, Intro.PageRows) – nur
-- deren Hinweise „Einschalten“ gelten als erledigt (Intro.HintIds). → Schritte, Hinweise
function Intro.Settle(name, rows)
    if type(name) ~= "string" or Core.IsSecret(name) then return 0, 0 end
    local steps = 0
    for _, tour in ipairs(Core.ModuleTours and Core.ModuleTours(name) or {}) do
        local only = noted[tour]
        noted[tour] = nil
        if only and next(only) then
            local ok, count = Core.Try(nil, "Intro.Settle", tour.MarkSeen, tour, only)
            if ok then steps = steps + (tonumber(count) or 0) end
        end
    end
    local hints = 0
    local optIn = Core.OptInHint
    if type(rows) ~= "table" then rows = Intro.PageRows({ module = name }) end
    if optIn and type(optIn.MarkIds) == "function" then hints = optIn.MarkIds(Intro.HintIds(rows)) or 0 end
    -- die Zeilen der Seite gelten als angeboten: eine Nachfrage nach einem Update fragt nicht noch einmal danach
    MarkKnown(rows)
    return steps, hints
end

-- „Allem zustimmen“: die Hinweise „Einschalten“ der Zeilen, die in der Liste standen und sich einschalten ließen,
-- sind erledigt (der Spieler hat entschieden; ohne rows: alle Zeilen laufender Module). Die Erklärblasen der Fenster
-- bleiben – sie erklären das Fenster beim ersten Öffnen und waren nirgends zu sehen (Gegenprüfung). → Hinweise
function Intro.SettleAll(rows)
    local optIn = Core.OptInHint
    if type(rows) ~= "table" then rows = Intro.Rows(true) end
    if optIn and type(optIn.MarkIds) == "function" then return optIn.MarkIds(Intro.HintIds(rows)) or 0 end
    return 0
end

---------------------------------------------------------------------------
-- Allem zustimmen: alle Abläufe ohne Klick der laufenden Module auf einmal an
---------------------------------------------------------------------------

-- Was „Allem zustimmen“ einschalten würde: die Zeilen laufender Module, die jetzt aus sind – ohne Schalter, die auf
-- diesem Client nie wirken (Intro.CanSwitchOn; nicht in Rückfrage, Anzahl und Chatzeile) –, dazu die Zeilen aus
-- Intro.AcceptRows (row.accept: ab Werk an, vom Spieler ausgeschaltet). → Liste wie Intro.Rows
function Intro.AgreeRows()
    local out = {}
    for _, row in ipairs(Intro.Rows(true)) do
        if row.value == false and Intro.CanSwitchOn(row.entry) and not ConsentRisk(row.entry) then
            out[#out + 1] = row
        end
    end
    -- ab Werk an, ausgeschaltet, und ausdrücklich mit einzuschalten (accept = true in ns.NEWS; ConsentNews.lua)
    for _, row in ipairs(Intro.AcceptRows()) do out[#out + 1] = row end
    return out
end

-- Was „Allem zustimmen“ auslässt: aus, aber hier wirkungslos (Intro.CanSwitchOn) – Rückfrage und Chat nennen sie.
-- → Text „ezMacro: Fremden Heilern danken“ (mehrere mit Komma) oder nil
function Intro.SkippedNames()
    local names = {}
    for _, row in ipairs(Intro.Rows(true)) do
        if row.value == false and not Intro.CanSwitchOn(row.entry) and not ConsentRisk(row.entry) then
            names[#names + 1] = L.INTRO_AGREE_LINE:format(row.module, row.label)
        end
    end
    if #names == 0 then return nil end
    return table.concat(names, ", ")
end

-- Liste je Modul („ezMerchant: Plunder verkaufen, Reparieren“) – vollständig (Gegenprüfung: vorher verschwanden ab dem
-- 11. Modul die Schalter hinter einer Anzahl, zugestimmt wurde trotzdem zu allen). → Text, Anzahl Module
function Intro.AgreeList(rows)
    local byModule, order = {}, {}
    for _, row in ipairs(rows or Intro.AgreeRows()) do
        if not byModule[row.module] then
            byModule[row.module] = {}
            order[#order + 1] = row.module
        end
        table.insert(byModule[row.module], row.label)
    end
    local lines = {}
    for _, module in ipairs(order) do
        lines[#lines + 1] = L.INTRO_AGREE_LINE:format(module, table.concat(byModule[module], ", "))
    end
    return table.concat(lines, "\n"), #order
end

local function Finish(store, choice)
    store.done = time and time() or 0
    if choice == "short" then Intro.ShowShort() elseif choice == "pages" then Intro.Show(1) end
end

-- Einschalten ohne Rückfrage (nach dem „Ja“). → Anzahl eingeschalteter Abläufe, Anzahl, die nicht gingen
function Intro.ApplyAll()
    -- Gegenprüfung: Die Rückfrage bleibt beim Kampfbeginn offen – ein „Ja“ im Kampf wird nach dem Kampf ausgeführt
    -- (eigener Schlüssel Intro.AGREE_KEY: ein späterer Aufruf der Einführung im Kampf ersetzt das „Ja“ nicht mehr)
    if Core.InCombat() then
        Later(Intro.ApplyAll, Intro.AGREE_KEY)
        return 0, 0
    end
    -- Nachlauf zum Review von PR 536: nur, was sich einschalten ließ, gilt als erledigt; ein Fehlschlag steht im Chat,
    -- sein Hinweis „Einschalten“ bleibt, und das Angebot gilt erst als erledigt, wenn nichts fehlschlug
    local done, failed, agreed, names, also, failedIds = 0, 0, {}, {}, {}, {}
    for _, row in ipairs(Intro.AgreeRows()) do
        local ok = Intro.Set(row.entry, true)
        if ok then
            done = done + 1
            agreed[#agreed + 1] = row
            if row.also then also[#also + 1] = row end
        else
            failed = failed + 1
            names[#names + 1] = L.INTRO_AGREE_LINE:format(row.module, row.label)
            failedIds[EntryId(row.entry)] = true
        end
    end
    local store = OfferStore()
    PrepareKnown()
    if store and failed == 0 then store.done = store.done or (time and time() or 0) end
    Intro.SettleAll(agreed)
    -- in der Rückfrage stand alles: was eingeschaltet wurde, was riskant ausblieb, was schon an war – nur was nicht
    -- ging, bleibt offen (die Nachfrage nach einem Update fragt es wieder, wie ihr „Alle annehmen“)
    local offered = {}
    for _, row in ipairs(Intro.Rows(true)) do
        if not failedIds[EntryId(row.entry)] then offered[#offered + 1] = row end
    end
    for _, row in ipairs(agreed) do if row.accept then offered[#offered + 1] = row end end
    MarkKnown(offered)
    -- die Anzahl nennt nur Abläufe ohne Klick, die Mit-Schalter (Intro.ALSO) stehen in einer eigenen Zeile, ebenso, was
    -- wieder angeht (row.accept)
    local count = done - #also
    local again
    also, again = SplitAccept(also)
    if count > 0 or (#also == 0 and #again == 0) then
        ns.Print(L.INTRO_AGREE_DONE:format(count, Core.SlashCmd(ns, L.INTRO_CMD_WORD)))
    end
    -- viele Mit-Schalter (Anmeldungen der Module): die Anzahl statt einer überlangen Chatzeile; die Namen standen in
    -- der Rückfrage und stehen in der Kurzfassung
    if #also > Intro.ALSO_NAMES then
        ns.Print(L.INTRO_AGREE_ALSO_DONE_N:format(#also, Core.SlashCmd(ns, L.INTRO_CMD_WORD)))
    elseif #also > 0 then
        ns.Print(L.INTRO_AGREE_ALSO_DONE:format(RowNames(also)))
    end
    if #again > 0 then ns.Print(L.INTRO_AGREE_AGAIN_DONE:format(RowNames(again))) end
    if failed > 0 then ns.Print(L.INTRO_AGREE_FAILED:format(failed, table.concat(names, ", "))) end
    local off = Intro.StaysOff()
    if off then ns.Print(off) end
    -- Hinweise der Module (Intro.Notes; Entscheidung vom 23.11.2026), je eine Chatzeile
    for _, note in ipairs(Intro.Notes()) do ns.Print(L.INTRO_AGREE_NOTE:format(note.module, note.text)) end
    return done, failed
end

-- Knopf „Allem zustimmen“ (Angebot, Kurzfassung, Seite „Einführung“): Liste, was dann passiert, Rückfrage über
-- Core.Confirm – bei mehr als Intro.AGREE_LINES Modulen über ein Textfenster (Core.TextDialog, rollbar) mit „Allem
-- zustimmen“, damit die ganze Liste Platz hat. onCancel: was bei „Nein“ bzw. „Abbrechen“ geschieht (Angebot: der Weg
-- zur Einführung im Chat). → true, wenn gefragt
function Intro.AgreeAll(onCancel)
    if Core.InCombat() then return Later(function() Intro.AgreeAll(onCancel) end) end
    local rows = Intro.AgreeRows()
    local skipped = Intro.SkippedNames()
    if #rows == 0 then
        -- alles schon an: entschieden ist nichts Neues, kein Hinweis gilt dadurch als gesehen (Nachlauf PR 536)
        local store = OfferStore()
        PrepareKnown()
        if store then store.done = store.done or (time and time() or 0) end
        MarkKnown(Intro.Rows(true))
        ns.Print(skipped and L.INTRO_AGREE_NONE_SKIPPED:format(skipped) or L.INTRO_AGREE_NONE)
        local off = Intro.StaysOff()
        if off then ns.Print(off) end
        for _, note in ipairs(Intro.Notes()) do ns.Print(L.INTRO_AGREE_NOTE:format(note.module, note.text)) end
        return false
    end
    local _, modules = Intro.AgreeList(rows)
    -- die Anzahl nennt nur Abläufe ohne Klick; Mit-Schalter (Intro.ALSO) unter eigenem Satz
    local consent, also = Intro.SplitAlso(rows)
    local again
    also, again = SplitAccept(also)
    local prompt
    if #consent == 0 and #also == 0 then
        prompt = L.INTRO_AGREE_CONFIRM_AGAIN
    elseif #consent == 0 then
        prompt = L.INTRO_AGREE_CONFIRM_ALSO:format((Intro.AgreeList(also)))
    else
        local list = Intro.AgreeList(consent)
        if #also > 0 then list = list .. "\n\n" .. L.INTRO_AGREE_ALSO:format((Intro.AgreeList(also))) end
        prompt = L.INTRO_AGREE_CONFIRM:format(#consent, list)
    end
    if #again > 0 then prompt = prompt .. "\n\n" .. L.INTRO_AGREE_AGAIN:format((Intro.AgreeList(again))) end
    if skipped then prompt = prompt .. "\n\n" .. L.INTRO_AGREE_SKIPPED:format(skipped) end
    local risk = Intro.Excluded("risk")
    if risk then prompt = prompt .. "\n\n" .. L.INTRO_AGREE_RISK:format(risk) end
    -- Hinweise der Module (Intro.Notes): „Allem zustimmen“ stellt dabei nichts um, sie stehen nur zum Lesen da
    local notes = Intro.NoteText()
    if notes then prompt = prompt .. "\n\n" .. L.INTRO_AGREE_NOTES:format(notes) end
    local function Cancel() if type(onCancel) == "function" then onCancel() end end
    if modules > Intro.AGREE_LINES then
        Core.TextDialog({ title = L.INTRO_AGREE_LABEL, text = prompt, readOnly = true, maxLetters = 0, owner = ADDON,
            accept = L.INTRO_AGREE_BUTTON, onAccept = function() Intro.ApplyAll() end, onCancel = Cancel })
        return true
    end
    Core.Confirm(prompt, function() Intro.ApplyAll() end, { owner = ADDON, accept = L.INTRO_AGREE_BUTTON,
        onCancel = function(reason) if reason == "no" then Cancel() end end })
    return true
end

function Intro.ShowShort()
    if Core.InCombat() then return Later(Intro.ShowShort) end
    Intro.HidePager()
    Intro.Open()
    -- Nur zum Lesen (Gegenprüfung): erledigt nichts – vorher galten schon beim Öffnen alle Erklärblasen aller Module als
    -- gesehen, auch wenn das Fenster gleich wieder zuging. Entscheiden: „Allem zustimmen“ unten, sonst „Schließen“.
    return Core.TextDialog({ anchor = rawget(_G, "SettingsPanel"), title = L.INTRO_DIALOG_TITLE,
        text = Core.StripColors(Intro.Text()), readOnly = true, maxLetters = 0, owner = ADDON,
        accept = L.INTRO_AGREE_BUTTON, onAccept = function() Intro.AgreeAll() end, cancel = L.TEXTDIALOG_CLOSE })
end

---------------------------------------------------------------------------
-- Einzeln: Modul für Modul an seinem Blizzard-Fenster, mit Einverständnis in der Blase
---------------------------------------------------------------------------

-- Nichts wird gemerkt: jede Seite lässt sich immer wieder zeigen (frischer Speicher je Abfrage).
local pager
local function Pager()
    if not pager then pager = Core.NewHints(function() return {} end, L.INTRO_NEXT) end
    return pager
end
Intro.PAGER_KEY = "intro.page"

function Intro.Pages()
    local pages = { { key = "start" } }
    for _, name in ipairs(RunningPageModules()) do pages[#pages + 1] = { key = name, module = name } end
    pages[#pages + 1] = { key = "consent" }
    if Core.Contribute then pages[#pages + 1] = { key = "help" } end
    return pages
end

-- Wessen Abläufe auf der Seite stehen: das Modul, auf der Startseite ezCore selbst. → Modulname oder nil
local function PageOwner(page)
    if page.module then return page.module end
    if page.key == "start" then return ADDON end
    return nil
end

-- Einverständnis-Zeilen der Seite (laufende Abläufe dieses Moduls). → Liste wie Intro.Rows
function Intro.PageRows(page)
    local owner = type(page) == "table" and PageOwner(page) or nil
    local out = {}
    if not owner then return out end
    for _, row in ipairs(Intro.Rows(true)) do
        if row.module == owner then out[#out + 1] = row end
    end
    return out
end

function Intro.PageText(page, index, count)
    local head, body
    if page.module then
        head = page.module
        body = (Intro.ModuleText(page.module) or "") .. "\n\n" .. Intro.CommandLine(page.module)
        -- zuerst, was das Modul kann (Kurzüberblick), dann wo es sitzt, der Befehl und die Häkchen
        local features = Intro.FeatureText(page.module)
        if features then body = features .. "\n\n" .. body end
        -- Hinweis des Moduls (Intro.Notes, Entscheidung vom 23.11.2026), gelb hinter dem Befehl
        local note = Intro.Notes(page.module)[1]
        if note then body = body .. "\n\n" .. Core.Gold(L.INTRO_NOTE_HEAD) .. " " .. note.text end
    elseif page.key == "consent" then
        local on, all = 0, 0
        for _, row in ipairs((Intro.SplitAlso(Intro.Rows(true)))) do
            all = all + 1
            if row.value then on = on + 1 end
        end
        head, body = L.INTRO_CONSENT_HEAD, L.INTRO_CONSENT_PAGE:format(on, all)
    elseif page.key == "help" then
        head, body = L.INTRO_HELP_HEAD, L.INTRO_HELP:format(Core.SlashCmd(ns, L.INTRO_HELP_CMD))
    else
        head, body = Core.TITLE or "ezCollection", L.INTRO_ABOUT .. "\n\n" .. L.INTRO_WHERE
    end
    local consent, also = Intro.SplitAlso(Intro.PageRows(page))
    if #consent > 0 then body = body .. "\n\n" .. Core.Gold(L.INTRO_PAGE_CONSENT) end
    if #also > 0 then body = body .. "\n\n" .. L.INTRO_PAGE_ALSO:format(RowNames(also)) end
    return Core.Gold(head) .. " " .. L.INTRO_PAGE_COUNT:format(index, count) .. "\n\n" .. body
end

-- Blizzard-Fenster je Modul (Spieltest 19.11.2026, S-1911-Einfuehrung, wörtlich: „einführung == passende einleitung
-- und öffnung der entsprechenden module nacheinander und abfrage der zustimmung“): Die Seite eines Moduls öffnet das
-- Fenster, an dem es andockt – über Blizzards eigene Funktionen (Core.OpenPanel, Kern/Panels.lua: nur außerhalb des
-- Kampfes, nichts in Blizzards Tabellen) –, und die Blase steht daneben. panel: Name in Core.Panels.LIST; side: Lage
-- der Blase. Woran die Blase hängt (der erste sichtbare Rahmen), kommt aus derselben Liste – die obersten Rahmen des
-- Fensters, Core.Panels.Frames (Nachlauf zum Review von PR 536: vorher eine zweite Liste hier, SSOT); frames nur, wo es
-- davon abweichen muss. Ohne Eintrag – Händler, Briefkasten und Auktionshaus öffnen sich nur am NPC, Leisten und
-- Tooltips haben kein Fenster – oder wenn es der Spieler selbst öffnet (Zauberbuch, Talente, Klick-Zauber:
-- Core.Panels.SelfOnly) und nicht schon offen hat, steht die Seite an der Einstellungsseite des Moduls.
Intro.WINDOWS = {
    ezBag = { panel = "bags", side = "left" },
    ezCombat = { panel = "spellbook", side = "right" },
    -- abweichend (why): professions.panel nennt auch CharacterFrame (alter Fertigkeiten-Reiter) – ein offenes
    -- Charakterfenster hieße sonst „Berufebuch schon offen“, und die Einführung schlösse es beim Weiterblättern nicht
    ezCraft = { panel = "professions", side = "right", frames = { "ProfessionsBookFrame" },
        why = "CharacterFrame gehört nicht zum Berufebuch" },
    ezGear = { panel = "character", side = "right" },
    ezHeal = { panel = "clickbindings", side = "right" },
    ezMacro = { panel = "macro", side = "right" },
    ezMap = { panel = "map", side = "right" },
    -- „Was kommt wann“ ist ein Reiter am Zauberbuch (ezMerchant/Upcoming.lua)
    ezMerchant = { panel = "spellbook", side = "right" },
    ezQuest = { panel = "questlog", side = "right" },
    ezSocial = { panel = "friends", side = "right" },
    ezTalent = { panel = "talents", side = "right" },
}
-- Rahmen, an denen die Blase eines Eintrags hängen kann. → Liste
function Intro.WindowFrames(win)
    if type(win) ~= "table" then return {} end
    if type(win.frames) == "table" then return win.frames end
    return Core.Panels and Core.Panels.Frames and Core.Panels.Frames(win.panel) or {}
end
Intro.TOUR_DELAY = 0.5       -- Sekunden nach dem Öffnen des Fensters, bis die Blasen des Moduls kommen

-- Stand der Führung: welches Fenster die Einführung geöffnet hat (nur das schließt sie wieder), woran die Blase hängt,
-- welches Modul die offene Seite hat; switching: die Einführung schließt bzw. öffnet gerade selbst ein Fenster (dessen
-- OnHide beendet die Führung dann nicht)
local nav = { panel = nil, opened = false, frame = nil, module = nil, rows = nil, switching = false }
Intro.nav = nav

local function Visible(name)
    local frame = Core.Panels and Core.Panels.Global and Core.Panels.Global(name) or rawget(_G, name)
    if type(frame) ~= "table" or type(frame.IsVisible) ~= "function" then return nil end
    local ok, shown = pcall(frame.IsVisible, frame)
    return ok and shown == true and frame or nil
end

local function FirstVisible(names)
    for _, name in ipairs(names or {}) do
        local frame = Visible(name)
        if frame then return frame end
    end
    return nil
end

-- Steht eine Seite an diesem Rahmen? Core.OptInHint zeigt dort dann keine eigene Blase „Einschalten“ (Gegenprüfung:
-- sonst lagen zwei Blasen mit derselben Frage übereinander – die Seite fragt das Einverständnis selbst ab).
function Intro.HoldsWindow(frame)
    return Intro.current ~= nil and frame ~= nil and nav.frame == frame
end

-- Die offene Seite verlassen: Blasen, die dort zu sehen waren, und Hinweise ihres Moduls sind erledigt (Intro.Note vor
-- dem Schließen, dann Intro.Settle) – nicht mit interrupted (Kampfbeginn: keine Entscheidung, Gegenprüfung). Ein
-- Fenster, das die Einführung selbst geöffnet hat, geht zu – nicht, wenn die nächste Seite dasselbe braucht
-- (nextPanel), nicht mit keepWindow (X, Esc, Kampfbeginn: der Spieler schaut weiter hin) und nie im Kampf.
local function Leave(nextPanel, keepWindow, interrupted)
    local module, rows = nav.module, nav.rows
    nav.module, nav.rows = nil, nil
    if module then
        if interrupted then
            Intro.Forget(module)
        else
            Intro.Note(module)
            Intro.Settle(module, rows or {})
        end
    end
    if nav.panel and nav.panel ~= nextPanel then
        if nav.opened and not keepWindow and not Core.InCombat() then
            nav.switching = true
            Core.Try(nil, "Intro.ClosePanel", Core.ClosePanel, nav.panel, nil, true)
            nav.switching = false
        end
        nav.panel, nav.opened = nil, false
    end
    nav.frame = nil
end

-- Schließt der Spieler das Fenster, an dem die Blase hängt (Esc, X – auch Blizzards Einstellungsfenster), endet die
-- Führung: sonst bliebe die Blase nur mittelbar verborgen und erschiene beim nächsten Öffnen mit altem Stand
-- (Gegenprüfung W-1811-Einfuehrung). Einmal je Rahmen eingehängt, nur HookScript (Leitlinie 5).
local hookedFrames = setmetatable({}, { __mode = "k" })
local function HookFrameHide(frame)
    if hookedFrames[frame] or type(frame.HookScript) ~= "function" then return end
    hookedFrames[frame] = true
    frame:HookScript("OnHide", function(self)
        if Intro.current and nav.frame == self and not nav.switching then Intro.HidePager() end
    end)
end

-- Öffnet, wo die Seite steht: das Blizzard-Fenster des Moduls (Intro.WINDOWS), sonst seine Einstellungsseite bzw. die
-- Seite „Einführung“. → Rahmen für die Blase, Lage; nil, wenn nichts zu sehen ist
local function OpenFor(page)
    local win = page.module and Intro.WINDOWS[page.module]
    local frames = Intro.WindowFrames(win)
    -- Nachlauf zum Review von PR 536: Hat Blizzards Einstellungsfenster nicht übernommene Änderungen, bleibt es offen
    -- (schließen ginge nur über Blizzards Übernehmen bzw. Rückfrage aus Addon-Code, nicht taint-sicher) – dann steht
    -- die Seite dort wie bei einem Modul ohne Fenster
    local pending = Core.Panels and Core.Panels.SettingsPending and Core.Panels.SettingsPending()
    if win and win.panel and not pending then
        if nav.panel ~= win.panel then
            if Core.PanelShown(win.panel) == true then
                nav.panel, nav.opened = win.panel, false        -- schon offen: bleibt beim Verlassen offen
            elseif Core.Panels and Core.Panels.SelfOnly and Core.Panels.SelfOnly(win.panel) then
                -- Zauberbuch, Talente und Klick-Zauber öffnet die Einführung nie (Kern/Panels.lua, selfOnly; Review vom
                -- 23.11.2026): schließen dürfte sie sie beim Weiterblättern nicht, und nach dem Kampf liefe es ohne
                -- Klick. Die Seite steht dann in Blizzards Einstellungsfenster wie bei einem Modul ohne Fenster.
                nav.opened = false
            else
                -- Gegenprüfung: Hatte der Spieler das Fenster auf einem anderen Reiter offen
                -- (Karte ohne Questlog), wechselt die Einführung nur den Reiter und schließt es beim Verlassen nicht
                local wasOpen = FirstVisible(frames) ~= nil
                nav.switching = true
                local ok, opened = Core.Try(nil, "Intro.OpenPanel", Core.OpenPanel, win.panel, nil, true)
                -- „Steht“ heißt: das Fenster des Moduls selbst (Core.PanelShown), nicht nur sein Oberrahmen
                -- (öffnet sich der Reiter nicht, zählt ein anderer nicht). Blizzards Einstellungsfenster erst zu, wenn es steht – sonst bleibt es für die Einstellungsseite offen.
                local stands = Core.PanelShown(win.panel) == true
                local settings = Panel()
                if stands and settings and settings.IsShown and settings:IsShown() then
                    Core.Try(nil, "Intro.CloseSettings", Core.ClosePanel, "settings", nil, true)
                end
                nav.switching = false
                nav.panel, nav.opened = win.panel, ok and opened == true and stands and not wasOpen
            end
        end
        local frame = Core.PanelShown(win.panel) == true and FirstVisible(frames) or nil
        if frame then return frame, win.side or Intro.SIDE end
    end
    nav.switching = true
    if page.module then
        local mns = ModuleNs(page.module) or (Core.Module(page.module) or {}).ns
        local own = type(mns) == "table" and mns.settingsPage or nil
        if type(own) == "table" and type(own.Open) == "function" then own:Open() else Core.OpenModuleSettings(page.module) end
    else
        Intro.Open()
    end
    nav.switching = false
    local panel = Panel()
    if panel and panel.IsShown and panel:IsShown() then return panel, Intro.SIDE end
    return nil
end

local function StartTours(name)
    if type(name) ~= "string" or name == ADDON then return 0 end
    local n = 0
    for _, tour in ipairs(Core.ModuleTours and Core.ModuleTours(name) or {}) do
        local ok, started = Core.Try(nil, "Intro.StartTours", tour.StartSoon, tour, nil, Intro.TOUR_DELAY)
        if ok and started then n = n + 1 end
    end
    return n
end

-- Ein Häkchen der Blase umlegen: setzt den Schalter über denselben Weg wie die Seite „Einführung“ (Intro.Set) und
-- zeigt danach den echten Stand (im Kampf oder bei einem nur einschaltbaren Schalter bleibt er). → ok
-- Tooltip einer Einverständnis-Zeile; ist der Schalter aus und hier wirkungslos, mit dem Grund fürs Grau (Leitlinie 11)
local function RowTip(entry, what, module)
    local text = L.INTRO_ROW_TIP:format(what, module)
    if Intro.Get(entry) ~= true and not Intro.CanSwitchOn(entry) then
        text = text .. "\n\n" .. L.INTRO_ROW_BLOCKED:format(tostring(module))
    end
    return text
end
Intro.RowTip = RowTip

-- Häkchen der Blase nach dem echten Stand: Haken, und grau samt Beschriftung, solange aus und hier wirkungslos
-- (Blizzards UICheckButtonTemplate hat für ein gesperrtes leeres Kästchen keine eigene Textur)
local function RowState(row)
    local entry = row and row.entry
    if not (entry and row.Check) then return end
    local on = Intro.Get(entry) == true
    if row.Check.SetChecked then row.Check:SetChecked(on) end
    local usable = on or Intro.CanSwitchOn(entry)
    if row.Check.SetEnabled then row.Check:SetEnabled(usable) end
    if row.Label and row.Label.SetFontObject then
        row.Label:SetFontObject(usable and "GameFontHighlightSmallLeft" or "GameFontDisableSmallLeft")
    end
end

function Intro.ToggleRow(row)
    local entry = type(row) == "table" and row.entry or nil
    if not entry then return false end
    local ok = Intro.Set(entry, Intro.Get(entry) ~= true)
    Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
    RowState(row)
    return ok
end

local function NewRow(box)
    local row = CreateFrame("Frame", nil, box)
    row.Check = Core.CreateCheck(row, Intro.CHECK_SIZE)
    row.Check:SetPoint("TOPLEFT", row, "TOPLEFT", -4, 2)
    row.Label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallLeft")
    row.Label:SetPoint("TOPLEFT", row, "TOPLEFT", Intro.CHECK_SIZE, -4)
    row.Label:SetWidth(Intro.TEXT_WIDTH - Intro.CHECK_SIZE)
    row.Label:SetJustifyH("LEFT")
    row.Check:SetScript("OnClick", function() Intro.ToggleRow(row) end)
    row.Check:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

local function Height(fontString, fallback)
    local ok, h = pcall(function() return fontString and fontString:GetStringHeight() end)
    return (ok and type(h) == "number" and not Core.IsSecret(h) and h > 0) and h or fallback
end

-- Häkchen der Seite in die Blase (je Ablauf ohne Klick eines; Name, Tooltip „Wenn an: …“) und Höhe der Blase
local function FillRows(box, page, rows)
    box:SetWidth(Intro.BOX_WIDTH)
    box.Text:SetWidth(Intro.TEXT_WIDTH)
    box.ezIntroRows = box.ezIntroRows or {}
    for _, row in ipairs(box.ezIntroRows) do
        row:Hide()
        row.entry = nil
    end
    local anchor, height = box.Text, 15 + Height(box.Text, 40)
    for i, data in ipairs(rows or Intro.PageRows(page)) do
        local row = box.ezIntroRows[i]
        if not row then
            row = NewRow(box)
            box.ezIntroRows[i] = row
        end
        row.entry = data.entry
        row.Label:SetText(data.label)
        -- grau wie auf der Seite des Moduls, solange der Schalter aus ist und hier nie wirkt (Intro.CanSwitchOn)
        RowState(row)
        local label, entry, what, module = data.label, data.entry, data.what, data.module
        row.Check:SetScript("OnEnter", function(self)
            Core.ShowTip(self, label, RowTip(entry, what, module), "ANCHOR_RIGHT")
        end)
        local h = math.max(Intro.CHECK_SIZE, Height(row.Label, 12) + 6)
        row:SetSize(Intro.TEXT_WIDTH, h)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -8 or -2)
        row:Show()
        anchor, height = row, height + (i == 1 and 8 or 2) + h
    end
    box:SetHeight(height + 10 + 22 + 12)
    return box.ezIntroRows
end
-- auch für die Nachfrage nach einem Update (Werkzeuge/ConsentNews.lua): dieselben Häkchen wie die Seiten
Intro.FillRows = FillRows

-- „Zurück“ dazu und „Weiter“ nach rechts (einmal je Blase)
local function Decorate(box)
    if box.ezIntroBack then return end
    if type(box.SetClampedToScreen) == "function" then box:SetClampedToScreen(true) end   -- große Weltkarte: nichts ragt hinaus
    local back = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    back:SetSize(Intro.BUTTON_WIDTH, 22)
    back:SetPoint("BOTTOMLEFT", 12, 12)
    back:SetText(L.INTRO_BACK)
    back:SetScript("OnClick", function()
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Intro.Show(math.max(1, (Intro.current or 2) - 1))
    end)
    box.ezIntroBack = back
    local okay = box.OkayButton
    if okay then
        okay:SetSize(Intro.BUTTON_WIDTH, 22)
        okay:ClearAllPoints()
        okay:SetPoint("BOTTOMRIGHT", -12, 12)
        -- Blizzards Teil (NewHints) blendet die Blase aus; danach die nächste Seite
        okay:HookScript("OnClick", function()
            local i = Intro.current
            if i and i < #Intro.Pages() then Intro.Show(i + 1) else Intro.HidePager() end
        end)
    end
    if box.CloseButton then box.CloseButton:HookScript("OnClick", function() Intro.HidePager() end) end
end

-- Führung beenden (X, Esc am Fenster, „Fertig“): die offene Seite gilt als gesehen, ihr Fenster bleibt offen.
-- interrupted (Kampfbeginn): nichts gilt als gesehen – der Spieler hat nicht entschieden (Gegenprüfung).
function Intro.HidePager(interrupted)
    if pager then pager.Hide(Intro.PAGER_KEY) end
    if Intro.current or nav.module or nav.panel then Leave(nil, true, interrupted) end
    Intro.current = nil
end

function Intro.Show(index)
    local pages = Intro.Pages()
    if type(index) == "string" then
        local found
        for i, page in ipairs(pages) do
            if page.key == index then found = i end
        end
        index = found
    end
    index = tonumber(index)
    if not index or index < 1 or index > #pages then index = 1 end
    if Core.InCombat() then
        Intro.HidePager(true)
        local want = index
        return Later(function() Intro.Show(want) end)
    end
    local page = pages[index]
    local win = page.module and Intro.WINDOWS[page.module]
    Leave(win and win.panel or nil)
    local frame, side = OpenFor(page)
    if not frame then
        Intro.current = nil
        return false
    end
    nav.frame = frame
    HookFrameHide(frame)
    local box = Pager().Show(Intro.PAGER_KEY, frame, frame, Intro.PageText(page, index, #pages), side)
    if not box then return false end
    Decorate(box)
    local rows = Intro.PageRows(page)
    FillRows(box, page, rows)
    if box.OkayButton then box.OkayButton:SetText(index < #pages and L.INTRO_NEXT or L.INTRO_DONE) end
    box.ezIntroBack:SetShown(index > 1)
    local owner = PageOwner(page)
    nav.module = owner
    nav.rows = rows          -- nur deren Hinweise „Einschalten“ gelten beim Verlassen als erledigt (Intro.Settle)
    Intro.current = index
    -- Die Erklärblasen des Moduls laufen hier, an ihrer Stelle im Fenster; was dort zu sehen ist, gilt beim Verlassen
    -- als gesehen (vorgemerkt jetzt, kurz nach dem Start der Blasen – manche Ziele entstehen erst beim Einrichten des
    -- Fensters – und noch einmal beim Verlassen)
    StartTours(page.module)
    if owner then
        Intro.Note(owner)
        if C_Timer and C_Timer.After then
            C_Timer.After(Intro.TOUR_DELAY + 0.1, function()
                if Intro.current == index and nav.module == owner then Intro.Note(owner) end
            end)
        end
    end
    return true
end

function Intro.ShowModule(name)
    if not Intro.HasPage(name) or Core.ModuleState(name) ~= "loaded" then return Intro.Show(1) end
    return Intro.Show(name)
end

---------------------------------------------------------------------------
-- Seite „Einführung“ unter „ezCollection“ (Leitlinie 7: Allgemein » Themen » Erweitert)
---------------------------------------------------------------------------

function Intro.AddPage(parent)
    if Intro.page then return Intro.page end
    parent = parent or (Core.ParentPage and Core.ParentPage())
    if not (type(parent) == "table" and type(parent.Sub) == "function") then return nil end
    local page = parent:Sub(L.INTRO_TITLE)
    if not page then return nil end
    Intro.page = page
    page:Button(L.INTRO_SHORT_LABEL, L.INTRO_SHORT_BUTTON, function() Intro.ShowShort() end, L.INTRO_SHORT_TIP)
    page:Button(L.INTRO_PAGES_LABEL, L.INTRO_PAGES_BUTTON, function() Intro.Show(1) end, L.INTRO_PAGES_TIP)
    page:Button(L.INTRO_AGREE_LABEL, L.INTRO_AGREE_BUTTON, function() Intro.AgreeAll() end, Intro.AgreeTip())
    -- Nachfrage nach einem Update wieder zeigen (Leitlinie 3; Werkzeuge/ConsentNews.lua)
    page:Button(L.INTRO_NEWS_LABEL, L.INTRO_NEWS_BUTTON, function() Intro.ShowNews(true) end, L.INTRO_NEWS_TIP)
    page:Header(L.INTRO_MODULES_HEADER, L.INTRO_MODULES_HEADER_TIP)
    for _, name in ipairs(RunningPageModules()) do
        page:Button(name, L.INTRO_MODULE_BUTTON, function() Intro.ShowModule(name) end, Intro.PageTip(name))
    end
    local consent, also = Intro.SplitAlso(Intro.Rows(true))
    -- Durchgang 1: ab Werk aus, 2: ab Werk an, 3: Mit-Schalter (Intro.ALSO) unter eigenem Kopf
    for pass = 1, 3 do
        local wantOn = pass == 2
        local head = false
        for _, row in ipairs(pass == 3 and also or consent) do
            if pass == 3 or (row.default == true) == wantOn then
                if not head then
                    if pass == 3 then
                        page:Header(L.INTRO_ALSO_HEADER, L.INTRO_ALSO_HEADER_TIP)
                    else
                        page:Header(wantOn and L.INTRO_CONSENT_ON_HEADER or L.INTRO_CONSENT_HEADER,
                            wantOn and L.INTRO_CONSENT_ON_HEADER_TIP or L.INTRO_CONSENT_HEADER_TIP)
                    end
                    head = true
                end
                local entry = row.entry
                -- Mit-Schalter von ezCore tragen ihre Gruppe im Namen (gleiche Schlüssel in zwei Gruppen); die Namen der
                -- Abläufe ohne Klick bleiben, wie sie waren
                local name = row.module .. "_" .. ((row.also and entry.group) and (entry.group .. "_") or "") .. row.key
                if type(entry.get) == "function" then
                    -- ein Zustand (Blizzards Haken) ist kein Wert von ezCollection: Knopf statt Kästchen – Blizzards
                    -- „Standard“ setzte ein Kästchen zurück und nähme dem Spieler seine Auswahl (Review 24.11.2026)
                    page:Button(L.INTRO_ROW_LABEL:format(row.module, row.label), L.INTRO_STATE_BUTTON,
                        function() Intro.ToggleState(entry) end, RowTip(entry, row.what, row.module))
                else
                    local _, checkRow = page:ProxyCheckbox("intro_" .. name,
                        function() return Intro.Get(entry) == true end,
                        function(value) Intro.Set(entry, value) end,
                        { label = L.INTRO_ROW_LABEL:format(row.module, row.label), -- Tooltip als Funktion: der Grund fürs Grau steht nur da, solange er gilt
                          tooltip = function() return RowTip(entry, row.what, row.module) end,
                          default = row.default == true })
                    -- grau wie auf der Seite des Moduls, solange aus und hier wirkungslos (Intro.CanSwitchOn; an bleibt
                    -- es bedienbar, damit man es ausschalten kann)
                    if type(checkRow) == "table" and type(checkRow.AddModifyPredicate) == "function" then
                        pcall(checkRow.AddModifyPredicate, checkRow,
                            function() return Intro.Get(entry) == true or Intro.CanSwitchOn(entry) end)
                    end
                end
            end
        end
    end
    if Core.Contribute then
        page:Header(L.INTRO_HELP_HEAD, L.INTRO_HELP_HEADER_TIP)
        page:Button(L.CONTRIB_HELP_LABEL, L.CONTRIB_HELP_BUTTON, function() Core.Contribute.ShowHelp() end, L.CONTRIB_HELP_TIP)
    end
    page:Advanced()
    page:Button(L.INTRO_OFFER_RESET_LABEL, L.INTRO_OFFER_RESET_BUTTON, function()
        Intro.ResetOffer()
        ns.Print(L.INTRO_OFFER_RESET_DONE)
    end, L.INTRO_OFFER_RESET_TIP)
    return page
end

-- Befehl „einführung“ von ezCore: ohne Wort die Seite, „kurz“, „einzeln“, „alles“ oder ein Modul
function Intro.Command(rest)
    local word = Core.SlashWord(Core.Trim(rest or ""))
    if word == "" then
        if not Core.OpenedOrDeferred(Intro.Open) then ns.Print(Intro.Usage()) end
        return "page"
    elseif word == "kurz" or word == "short" then
        Intro.ShowShort()
        return "short"
    elseif word == "einzeln" or word == "pages" or word == "single" then
        Intro.Show(1)
        return "pages"
    elseif word == "alles" or word == "all" then
        Intro.AgreeAll()
        return "all"
    end
    local name = Core.FindModuleName(word)
    if name then
        Intro.ShowModule(name)
        return "module"
    end
    ns.Print(Intro.Usage())
    return "usage"
end

function Intro.Usage()
    return L.INTRO_CMD_USAGE:format(Core.SlashCmd(ns, L.INTRO_CMD_WORD), Core.SlashCmd(ns, L.INTRO_CMD_WORD .. " bag"))
end

---------------------------------------------------------------------------
-- Angebot nach dem Einloggen: „Allem zustimmen“, „Einzeln entscheiden“, „Kurz“, „Später“
---------------------------------------------------------------------------

local offerHints
local function OfferHints()
    if not offerHints then offerHints = Core.NewHints(function() return {} end, L.INTRO_AGREE_BUTTON) end
    return offerHints
end
Intro.OFFER_HINT = "intro.offer"

-- Woran die Blase hängt: Blizzards Addon-Fach an der Minikarte, sonst die Reiterleiste des Chats. → Rahmen, Lage
-- Spieltest 19.11.2026 (Bild: erste Zeile „Neu bei ezCollection?“ oben abgeschnitten): Das Fach sitzt dicht unter der
-- Oberkante; mittig links daneben („left“) ragte die obere Hälfte der Blase hinaus, SetClampedToScreen half nicht.
-- Jetzt links daneben mit der Oberkante bündig („leftTop“, Bausteine/Widgets.lua) – die Blase wächst nach unten.
function Intro.OfferTarget()
    local frame = Visible("AddonCompartmentFrame")
    if frame then return frame, "leftTop" end
    frame = Visible("GeneralDockManager")
    if frame then return frame, "above" end
    return nil
end

local function InInstance()
    local fn = rawget(_G, "IsInInstance")
    if type(fn) ~= "function" then return false end
    local ok, inside = pcall(fn)
    return ok and not Core.IsSecret(inside) and inside == true
end

Intro.InInstance = InInstance

local function LaterText()
    ns.Print(L.INTRO_OFFER_LATER_DONE:format(Core.SlashCmd(ns, L.INTRO_CMD_WORD)))
end

-- Fünf Knöpfe in drei Reihen: oben „Allem zustimmen“ (Blizzards Knopf der Blase) und „Einzeln entscheiden“, darunter
-- „Kurz“ und „Später“, unten über die ganze Breite „Nicht mehr anbieten“ (Einstellungs-Prüfung 19.11.2026, Nr. 55).
-- Die Breite folgt dem längsten Text der oberen vier, die Blase wird breiter, wenn nötig.
local function DecorateOffer(box)
    if box.ezIntroPages then return end
    if type(box.SetClampedToScreen) == "function" then box:SetClampedToScreen(true) end
    local okay = box.OkayButton
    local pages = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    local short = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    local later = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    local never = CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    pages:SetText(L.INTRO_OFFER_PAGES)
    short:SetText(L.INTRO_OFFER_SHORT)
    later:SetText(L.INTRO_OFFER_LATER)
    never:SetText(L.INTRO_OFFER_NEVER)
    local width = 90
    for _, button in ipairs({ okay, pages, short, later }) do
        local fs = button and Core.Peek(button, "GetFontString") and button:GetFontString()
        local ok, w = pcall(function() return fs and fs:GetStringWidth() end)
        if ok and type(w) == "number" and not Core.IsSecret(w) and w + 20 > width then width = w + 20 end
    end
    local gap = 4
    local total = width * 2 + gap + 24
    local okWidth, boxWidth = pcall(box.GetWidth, box)
    if okWidth and type(boxWidth) == "number" and total > boxWidth then box:SetWidth(total) end
    -- drei Reihen: „Nicht mehr anbieten“ unten über die ganze Breite (Einstellungs-Prüfung 19.11.2026, Nr. 55)
    local top = 12 + 22 + gap + 22 + gap
    if okay then
        okay:SetSize(width, 22)
        okay:ClearAllPoints()
        okay:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -gap / 2, top)
    end
    pages:SetSize(width, 22)
    pages:SetPoint("BOTTOMLEFT", box, "BOTTOM", gap / 2, top)
    short:SetSize(width, 22)
    short:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -gap / 2, 12 + 22 + gap)
    later:SetSize(width, 22)
    later:SetPoint("BOTTOMLEFT", box, "BOTTOM", gap / 2, 12 + 22 + gap)
    never:SetSize(width * 2 + gap, 22)
    never:SetPoint("BOTTOM", box, "BOTTOM", 0, 12)
    -- „Allem zustimmen“ ist Blizzards Knopf der Blase (blendet sie aus); danach die Rückfrage mit der Liste
    if okay then
        okay:HookScript("OnClick", function() Intro.AgreeAll(LaterText) end)
        okay:SetScript("OnEnter", Core.TipScript(L.INTRO_AGREE_BUTTON, L.INTRO_AGREE_TIP, "ANCHOR_BOTTOM"))
        okay:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end
    local function Choose(choice)
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        box:Hide()
        local store = OfferStore()
        if store then Finish(store, choice) end
    end
    pages:SetScript("OnClick", function() Choose("pages") end)
    short:SetScript("OnClick", function() Choose("short") end)
    later:SetScript("OnClick", function()
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        box:Hide()
        LaterText()
    end)
    never:SetScript("OnClick", function()
        Core.PlaySound("IG_MAINMENU_OPTION_CHECKBOX_OFF")
        box:Hide()
        Intro.NeverOffer()
    end)
    if box.CloseButton then box.CloseButton:HookScript("OnClick", function() LaterText() end) end
    box.ezIntroPages, box.ezIntroShort, box.ezIntroLater, box.ezIntroNever = pages, short, later, never
end

-- „Nicht mehr anbieten“ (Knopf der Blase): kommt nicht wieder, bis „Angebot der Einführung – Erneut zeigen“ bzw. „Alle
-- Hinweise und Erklärblasen erneut zeigen“ es zurücksetzt. → true
function Intro.NeverOffer()
    local store = OfferStore()
    if not store then return false end
    store.never = true
    ns.Print(L.INTRO_OFFER_NEVER_DONE:format(Core.SlashCmd(ns, L.INTRO_CMD_WORD)))
    return true
end

function Intro.TryOffer()
    local hint = Core.OptInHint
    if hint and hint.Enabled and not hint.Enabled() then return false, "off" end
    local store = OfferStore()
    if not store then return false, "db" end
    if store.never then return false, "off" end
    -- dieselbe Bedingung wie die Nachfrage nach einem Update (Werkzeuge/ConsentNews.lua: wartet, solange es noch kommt)
    if not Intro.OfferPending(store) then return false, "done" end
    if Intro.offeredNow then return false, "session" end
    if Core.InCombat() then
        Core.AfterCombat(function()
            C_Timer.After(Intro.AFTER_COMBAT_DELAY, function() Core.Try(nil, "Intro.TryOffer", Intro.TryOffer) end)
        end, Intro.OFFER_KEY, ADDON)
        return false, "combat"
    end
    if InInstance() then return false, "instance" end
    -- Ohne sichtbares Ziel kein Angebot und nichts gezählt (nächstes Einloggen); den Weg nennt schon die Chatzeile
    -- des ersten Starts (/ez), und eine zweite Zeile wäre aufdringlich
    local target, side = Intro.OfferTarget()
    local box = target and OfferHints().Show(Intro.OFFER_HINT, target, target, L.INTRO_OFFER, side)
    if not box then return false, "target" end
    Intro.offeredNow = true
    PrepareKnown()
    store.offered = (tonumber(store.offered) or 0) + 1
    -- das Angebot steht für alle Zeilen von heute: nach einem Update fragt ezCore nur nach den dann neuen
    MarkKnown(Intro.Rows(true))
    DecorateOffer(box)
    -- Der Text nutzt die Breite der (für die Knöpfe verbreiterten) Blase, die Höhe kommt für drei Knopfreihen neu
    -- (Blizzards Maße der Blase rechnen mit einer Reihe; 15 oben, 10 Abstand, 22 + 4 + 22 + 4 + 22 Knöpfe, 12 unten)
    local okWidth, width = pcall(box.GetWidth, box)
    if okWidth and type(width) == "number" and not Core.IsSecret(width) then box.Text:SetWidth(width - 30) end
    local okText, textHeight = pcall(box.Text.GetStringHeight, box.Text)
    if not (okText and type(textHeight) == "number" and not Core.IsSecret(textHeight)) then textHeight = 40 end
    box:SetHeight(15 + textHeight + 10 + 22 + 4 + 22 + 4 + 22 + 12)
    return true, "bubble"
end

function Intro.ResetOffer()
    local store = OfferStore()
    if not store then return false end
    local was = Intro.Existing(store)
    -- Bestand bleibt Bestand: der Merker entsteht vor dem Zurücksetzen (sonst gälte er danach als Neuinstallation)
    if was then PrepareKnown() end
    store.done, store.offered, store.never = nil, nil, nil
    Intro.offeredNow = nil
    if offerHints then offerHints.Hide(Intro.OFFER_HINT) end
    return was
end

-- Ein Kampfbeginn nimmt die Blasen weg (das Angebot kommt beim nächsten Einloggen wieder, wenn es noch darf)
ns.On("PLAYER_REGEN_DISABLED", function()
    Intro.HidePager(true)
    if offerHints then offerHints.Hide(Intro.OFFER_HINT) end
end)

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(Intro.OFFER_DELAY, function() Core.Try(nil, "Intro.TryOffer", Intro.TryOffer) end)
end)
