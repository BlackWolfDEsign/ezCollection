local ADDON, ns = ...
local L = ns.L

ns.DEFAULTS = {
    grouping = true,
    bankGrouping = true,
    guildGrouping = true,
    dockBank = true,
    newItems = true,
    compressEmpty = true,
    -- Reagenzientasche als Abschnitt unten in der Tasche (Entscheidung des Nutzers vom 23.11.2026: „Abschnitt unten
    -- (Empfohlen)“, Schalter ab Werk an; Reagent.lua)
    reagentSection = true,
    reagentAutoFill = true,   -- Entscheidung des Nutzers vom 23.11.2026: „ja zu automatisches Nachrücken“
    highlight = true,
    -- itemLevel, boe, autoSell und auctionWorth sind seit der Einstellungs-Prüfung vom 19.11.2026 gemeinsame Schalter
    -- in ezCore (ns.SHARED unten) – ihre Standardwerte stehen dort
    -- Wunsch des Nutzers vom 16.11.2026: Tasche geht mit dem Handelsfenster auf und danach wieder zu (Trade.lua)
    openOnTrade = true,
    dockWindow = true,
    -- Freie Plätze an Rucksack und Bank (bis 23.11.2026 „belegt/gesamt (frei)“) – ein Schalter seit der Einstellungs-Prüfung (Nr. 56/57, Entscheidung des
    -- Nutzers vom 19.11.2026); der frühere Bank-Schalter bankCount wurde einmal übernommen (ns.MigrateSettings1911)
    bagCount = true,
    transferArrows = true,
    transferStacksOnly = false,
    questMark = true,
    collectMark = true,
    craftMark = true,
    makeSpace = true,
    lootSpace = true,   -- Vorschlag am Plündernfenster bei voller Tasche (Nutzer am 24.11.2026; LootSpace.lua)
    -- ab Werk aus seit der Einstellungs-Prüfung (Nr. 97): „LÖSCHEN“ vorausfüllen hebelt Blizzards Schutz gegen
    -- versehentliches Zerstören aus – eine bewusste Wahl; gespeichertes „an“ einmal umgestellt (ns.MigrateSettings1911)
    easyDelete = false,
    compactStacks = false,
    -- Wunsch des Nutzers vom 18.11.2026 (W-1811-ezBag): je Ort ein eigener Platz unter „Alle Charaktere“. Seit der
    -- Einstellungs-Prüfung (19.11.2026) schaltet er nur diese Aufteilung; Fundort im Tooltip und am Suchknopf
    -- stehen immer da.
    showPlace = true,
    -- Sortierung aller Gruppen (Menü des Sortierknopfs, kein Schalter): "type", "name", "quality" … (Render.SortModes)
    sortMode = "type",
}

-- „Allem zustimmen“ (ezCore, Werkzeuge/FirstStart.lua: Intro.Registered; Spieltest 20.11.2026): jeder Schalter oben,
-- der ab Werk aus ist und kein Ablauf ohne Klick (die stehen in Intro.CONSENT). "on": mit der Zustimmung gesetzt;
-- "risk": bleibt aus, riskiert Blizzards Regeln oder Schutz; "choice": Geschmack, Filter, Leitlinie 9 oder 11.
-- tools/Tests/agree_test.lua prüft, dass jeder neue Schalter mit false hier oder in Intro.CONSENT steht.
-- risk hier: „Leichter zerstören“ hebt Blizzards Schutz gegen versehentliches Zerstören auf
-- on (Entscheidung des Nutzers vom 25.11.2026, Spieltest mit Foto, wörtlich „Wieso sind die nicht automatisch zusammen gefasst?“,
-- gewählt „Mit „Alle annehmen“ an (Empfohlen)“): „Gleiche Gegenstände zusammenfassen“ – bis dahin choice (nur Darstellung)
ns.AGREE = {
    compactStacks = "on", easyDelete = "risk", transferStacksOnly = "choice",
}

-- Neu seit v1.0.0-beta3 und ab Werk an; Einträge bleiben stehen (ezCore, Werkzeuge/ConsentNews.lua: Intro.NewsOnRows;
-- Nutzer am 24.11.2026): Die Blase „Neu seit dem Update“ nennt sie einmal mit gesetztem Häkchen. tools/Tests/agree_test.lua
-- ist rot, wenn ein neuer Schalter mit true hier fehlt.
-- accept (Nutzer am 25.11.2026, wörtlich „Reagenzien Tasche automatisch mit in großer ist nicht standardmäßig an? Muss aber
-- nach alle annehmen.“, gewählt „Immer einschalten (Empfohlen)“): „Allem zustimmen“ und „Alle annehmen“ schalten es ein,
-- auch wenn der Spieler es vorher ausgeschaltet hatte
ns.NEWS = { { "reagentSection", needs = "grouping", accept = true }, "reagentAutoFill", "lootSpace" }

-- Reihenfolge für Einstellungen und Slash-Befehle (Schlüssel, deutscher Befehl, Abschnitt der Einstellungsseite,
-- optional der Funktionsschlüssel aus ezCores Liste fremder Addons für den Hinweis „Übernimmt schon: …“ im Tooltip;
-- en: das englische Wort für den englischen Client – T10-1).
ns.TOGGLES = {
    { "grouping", "gruppen", "groups", en = "groups" },
    { "bankGrouping", "bankgruppen", "groups", en = "bankgroups" },
    { "guildGrouping", "gildengruppen", "groups", en = "guildgroups" },
    { "dockBank", "andocken", "bank", en = "dock" },
    { "newItems", "neu", "groups", en = "new" },
    { "compressEmpty", "frei", "groups", en = "free" },
    { "reagentSection", "reagenz", "groups", en = "reagent" },
    { "reagentAutoFill", "nachruecken", "groups", en = "refill" },
    { "highlight", "hervorheben", "display", en = "highlight" },
    { "itemLevel", "itemlevel", "display", en = "itemlevel" },
    { "boe", "boe", "display", en = "boe" },
    { "autoSell", "verkaufen", "vendor", en = "sell" },
    { "openOnTrade", "handel", "vendor", "bags", en = "trade" },
    { "dockWindow", "fensterandocken", "bank", en = "dockwindow" },
    { "bagCount", "platz", "display", en = "slots" },
    { "transferArrows", "pfeile", "bank", en = "arrows" },
    { "transferStacksOnly", "nurstapel", "bank", en = "stacksonly" },
    { "questMark", "questsymbol", "display", en = "questicon" },
    { "collectMark", "sammlung", "display", en = "collection" },
    { "craftMark", "einkauf", "display", en = "shopping" },
    { "auctionWorth", "auktionswert", "display", en = "auctionworth" },
    { "makeSpace", "platzschaffen", "space", en = "makespace" },
    { "lootSpace", "beuteplatz", "space", en = "lootspace" },
    { "easyDelete", "zerstoeren", "space", en = "destroy" },
    { "compactStacks", "zusammenfassen", "groups", en = "compact" },
    { "showPlace", "fundort", "display", en = "location" },
}

---------------------------------------------------------------------------
-- Helfer: die allgemeinen kommen aus ezCore (eine Umsetzung für alle Module)
---------------------------------------------------------------------------

local Core = ezCore
-- Print, Error, On, OnReady, OnSettingChanged, SettingChanged, SetSetting … und das Gerüst aus ezCore
-- (Kern/Framework.lua): Datenbank ezBagDB mit Standardwerten, Anmelden (ns.charKey, ns.me, ns.RunReady), Befehl /ezbag
-- mit Kurzbefehl /eb (nur, wenn er frei ist), „status“, „hilfe“ und den Schaltern aus ns.TOGGLES. Was ezBag
-- darüber hinaus tut, steht in ns.OnLoad (Übernahmen) und ns.SlashExtra (eigene Befehle) weiter unten.
Core.NewModule(ADDON, ns, {
    -- Mindestversion von ezCore (V-006): 1.12.0 für den Plunder-Dienst (Core.Junk), die Tooltip-Abschnitte in ezCore
    -- (Core.ItemTooltip), Core.BagSpaceOf, Core.Menu.Tip und Core.OpenedOrDeferred (Einstellungen im Kampf)
    -- 1.15.0: Bausteine aus dem Gesamtreview vom 18.11.2026, u. a. Core.CancelConfirm, Core.CombatNotice, Core.OptInOnce, Core.Ticker
    -- (Liste je Modul in docs/roadmap/uebergreifend.md, P7)
    core = "1.15.0",
    needs = { "scaffold", "OpenPanel", "BagList", "ItemClassName", "tourOwner", "CompartmentHandlers", "Plural", "ClickText", "EmptyBagSlot", "BagKind", "IsSpecialBag", "GearProtects", "Junk.Limits",
        -- Marken zeichnen (eine Fassung mit ezCore)
        "SlotMarks.NewDrawer", "AskNumber",
        -- 24.11.2026 (ohne neue Versionsnummer): Erlös im Auktionshaus, ohne gemessene Gebühr brutto mit Hinweis
        "Prices.Proceeds", "Prices.FeeNote",
        "Junk.Sell", "Junk.SetRule", "ItemTooltip.AddCounts", "BagSpaceOf", "Menu.Tip", "OpenedOrDeferred",
        "Style.ColorText", "Style.Color", "Style.AllText", "Style.BUTTON", "Style.ICON", "Menu.AllToggle",
        -- Welle 17: Helfer und Texte, die ezCore ohne neue Versionsnummer bekam (tools/texte.lua, Regel 4)
        "L.ALL_CHARS",
        -- 23.11.2026: nur freier Platz (Auftrag des Nutzers), eine Fassung mit ezPanel
        "FreeSpaceText", "L.SPACE_FREE",
        -- 23.11.2026: Reagenzientasche als Abschnitt in der Tasche öffnet und schließt über Core.OpenPanel("reagentBag")
        "panelReagentBag", "SettingsPathText",
        -- Welle 23: ezCores eine Fassung für Stapelgröße, „Auktionshaus offen?“ und ezCrafts Einkaufsliste
        "MaxStack", "AuctionHouseOpen", "Junk.CraftNeed", "Junk.ClearCraftNeeds",
        -- Oberflächen-Einheit (Gesamtreview 18.11.2026, P13 D2; ezCore ohne neue Versionsnummer)
        "compartmentMain", "slashMain", "SlashCmd", "CombatNotice", "CancelConfirm", "confirmCancel",
        -- Gesamtreview 18.11.2026 (D3, kern/einheit-rest; ohne neue Nummer): Texthelfer statt Kopien im Modul
        "CmdText", "CombatText",
    -- Gesamtreview 18.11.2026 (P19a, kern/ssot-helfer; ohne neue Nummer): gemeinsame Helfer statt Kopien
    "OptInOnce", "RoleRGB", "QualityText", "PlaySound",
    -- Einstellungs-Prüfung vom 19.11.2026: Einmal-Umstellung der zusammengelegten Schalter; gemeinsame Schalter
    -- mehrerer Module (ezCore ohne neue Versionsnummer)
    "MigrateOnce", "ShareSettings", "AdoptModuleShared", "SharedOn",
    -- 20.11.2026 (ohne neue Versionsnummer): „Im Auktionshaus Wertvolles behalten“ als eine Stelle in ezCore
    "Junk.MerchantKeeps", "Junk.ShowKept" },
    db = "ezBagDB",
    onLoad = function(db) return ns.OnLoad(db) end,
    login = true,
    -- Kurzbefehl /eb aus Core.SLASH_ALIASES (nur, wenn frei); ohne Wort das ezBag-Fenster wie der Linksklick im
    -- Addon-Fach (Entscheidung 5 vom 18.11.2026)
    slash = {
        commands = { "/ezbag" },
        extra = function(cmd, rest) return ns.SlashExtra(cmd, rest) end,
        main = function() ns.Window.Toggle() end,
        mainText = L.COMPARTMENT_MAIN,
    },
})

-- ns.CmdText(text) (%s durch den geltenden Befehl: „/eb“, solange kein anderes Addon ihn belegt, sonst „/ezbag“; T18-2)
-- legt Core.NewModule an (Core.CmdText). Den Satz zur Kampfsperre für Stellen, die ihn selbst zeigen (ein laufender
-- Verkauf bricht ab, ein Umlagern endet mit Grund), liefert Core.CombatText(was); sonst Core.CombatNotice(ns, was).

-- Gegenstands-ID gefahrlos lesen (Leitlinie 6, V-054): zuerst ezCore.IsSecret, erst danach der Test auf nil.
-- So wird ein gesperrter Wert nie als Wahrheitswert geprüft. → ID oder nil (leer oder gesperrt).
-- Genau das tut ezCore.Plain – der Name bleibt als Verweis darauf (eine Umsetzung, Leitlinie 2).
ns.PlainID = Core.Plain

-- Dasselbe für Blizzards ContainerItemInfo: info.itemID oder nil (leerer Platz oder gesperrt).
function ns.ItemIDOf(info)
    if type(info) ~= "table" then return nil end
    return ns.PlainID(info.itemID)
end
ns.ItemName = Core.ItemName
ns.CoinText = Core.CoinText

-- Einzahl/Mehrzahl bildet ezCores Core.Plural (eine Umsetzung für alle Module); hier stehen nur die Texte.
-- Ohne Rückfall: "Plural" steht darum in needs (oben) – ein ezCore ohne Core.Plural meldet „ezCore zu alt“.
-- Ganzer Satz in zwei Fassungen: bei genau 1 der Text L[key .. "_ONE"], sonst L[key]; weitere Werte hängen an.
-- Dafür, wenn sich mehr als das Zählwort ändert („1 markierter Gegenstand … wurde“).
function ns.CountText(key, n, ...)
    local many, oneKey = L[key], key .. "_ONE"
    local one = L[oneKey]
    -- Ein fehlender Text kommt als sein eigener Schlüssel zurück: dann bleibt es bei der Mehrzahl.
    if one == oneKey then one = many end
    return Core.Plural(n, one, many, ...)
end

-- Zählwort mit Zahl: „1 Platz“ / „3 Plätze“ aus L.COUNT_<WORT>_ONE und L.COUNT_<WORT>_MANY. Eigene Wörter (SLOT,
-- STEP, CHAR, GUILDBANK, HIT, STACK) stehen in Locale.lua, ITEM kommt aus ezCore.L. Ein Satz mit zwei Zahlen setzt
-- je Zahl ein Zählwort ein („Passt: 1 Platz (2 Schritte)“).
function ns.CountWord(word, n)
    return Core.Plural(n, L["COUNT_" .. word .. "_ONE"], L["COUNT_" .. word .. "_MANY"])
end

-- Farben für Tooltip-Zeilen und Hinweise über ezCores Rollen (Design-System 2.5; Welle 23, A3 – vorher Zahlen wie
-- 1, 0.82, 0 an rund 40 Stellen): ns.TipRGB(rolle) → r, g, b. Rollen aus Core.Style.COLOR ("normal" Gold,
-- "highlight" Weiß, "good", "bad" …) – nur drei Werte: der vierte von Core.Style.Color ist Blizzards Farbobjekt und
-- stünde in AddLine an der Stelle des Umbruchs, in SetText an der des Alphas. "hint": Hinweise und Quellen in
-- ezCores Grau (Core.GREY, dasselbe Grau wie Core.Grey im Text – Design-System 2.5).
-- Seit dem Gesamtreview vom 18.11.2026 (T16-5) nur noch die Namen in ezBag: ns.TipRGB ist ezCores Core.RoleRGB,
-- ns.AddTipLine färbt die ganze Zeile in dieser Farbe (Hinweis: Core.GREY als r, g, b, ohne Farbcode im Text).
function ns.TipRGB(role) return Core.RoleRGB(role) end

-- Eine Tooltip-Zeile in der Farbe einer Rolle (siehe ns.TipRGB); wrap = umbrechen.
function ns.AddTipLine(text, role, wrap)
    local r, g, b = ns.TipRGB(role or "highlight")
    GameTooltip:AddLine(text, r, g, b, wrap)
end

-- Fremde Addons erkennt ezCore an einer Stelle (Core.OtherAddOn / Core.WhoHandles, Liste in
-- ezCore/Wissen/OtherAddOns.lua und docs/fremd-addons.md); ezBag fragt nur nach.

-- ClassicUI Forever zeichnet die Taschen selbst neu, wenn sein Modul "bags" an ist (Standard: an).
function ns.ClassicUIBagsActive()
    return (Core.OtherAddOn("ClassicUIForever", "bagStyle")) == true
end

-- ClassicUI Forever kleidet die Bank im klassischen Stil ein (Module "panels" und "panelBank").
function ns.ClassicUIBankActive()
    return (Core.OtherAddOn("ClassicUIForever", "bankStyle")) == true
end

-- Name des Addons, das graue Gegenstände schon verkauft (Leatrix Plus „Plunder verkaufen“ …), sonst nil.
function ns.OtherSellsJunk()
    return (ns.OtherFor("sellJunk"))
end

-- Name des Addons, das Blizzards Tasche ersetzt (BetterBags, ArkInventory, Bagnon, Baganator), sonst nil.
function ns.OtherBags()
    return (ns.OtherFor("bags"))
end

-- Getragene Taschen ohne Schlüsselbund: hier wird verkauft (Plunder), Platz geschafft und umgelagert.
-- Die Regel steht einmal in ezCore (Core.BagList, V-053); ns.SellBags bleibt als Weiterleitung.
function ns.SellBags()
    return Core.BagList("sell")
end

-- Steht der Charakter beim Händler? (eine Fassung für Plunder, Auswahl, „Platz schaffen“ und das Gruppen-Menü)
function ns.AtMerchant()
    local frame = _G.MerchantFrame
    return frame ~= nil and frame:IsShown() == true
end

function ns.UsingCombinedBags()
    local manager = _G.ContainerFrameSettingsManager
    if manager and manager.IsUsingCombinedBags then
        local ok, result = pcall(manager.IsUsingCombinedBags, manager)
        if ok then return result == true end
    end
    return Core.CVar("combinedBags") == "1"
end

---------------------------------------------------------------------------
-- Lagen in ezCoreDB.positions (seit 1.8; vorher ezBagDB.bagPos, framePos, bagFramePos, window)
---------------------------------------------------------------------------

ns.BAG_KEY = "ezBag.bag"            -- kombinierte Tasche (abgedockt)
ns.WINDOW_KEY = "ezBag.window"      -- ezBag-Fenster
local BAGFRAME_PREFIX = "ezBag.bagFrame:"
ns.BAGFRAME_PREFIX = BAGFRAME_PREFIX

-- Einzelnes Taschenfenster (ohne kombinierte Tasche) je Taschen-ID.
function ns.BagFrameKey(id) return BAGFRAME_PREFIX .. tostring(id) end

-- Bank und Gildenbank unter dem Schlüssel von ezCores „Blizzard-Fenster verschieben“ („blizz:<Fenster>“):
-- eine Lage je Fenster, wer es auch verschiebt (ezBag meldet beide dort an, Layout.ClaimPanels).
function ns.PanelKey(name) return "blizz:" .. tostring(name) end

-- Alte Lagen aus ezBagDB einmal übernehmen. Bank und Gildenbank: ezBags Lage war die sichtbare (ezBag setzt
-- sie nach Blizzard und ezCore), darum gilt sie auch vor einer älteren aus ezCores Fenster-Verschieben.
function ns.MigratePositions()
    local db = ns.db
    if not (db and Core.Positions(true)) then return false end
    for name, pos in pairs(type(db.framePos) == "table" and db.framePos or {}) do
        if type(pos) == "table" and type(pos.point) == "string" then
            Core.StorePosition(ns.PanelKey(name), { point = pos.point, relPoint = pos.relPoint or pos.point,
                x = tonumber(pos.x) or 0, y = tonumber(pos.y) or 0 })
        end
    end
    Core.ImportPosition(ns.BAG_KEY, db.bagPos)
    for id, pos in pairs(type(db.bagFramePos) == "table" and db.bagFramePos or {}) do
        Core.ImportPosition(ns.BagFrameKey(id), pos)
    end
    Core.ImportPosition(ns.WINDOW_KEY, db.window)
    db.framePos, db.bagPos, db.bagFramePos, db.window = nil, nil, nil, nil
    return true
end

---------------------------------------------------------------------------
-- Datenbank
---------------------------------------------------------------------------

local migrated = false

-- Hinweise beim Einloggen nur einmal je Zustand (V-057): gemerkt wird, welcher zuletzt gezeigt wurde. Ändert sich
-- der Zustand (anderes Taschen-Addon, kombinierte Tasche wieder aus), kommt der passende Hinweis einmal neu.
-- → Zustand ("classicui", "bags:<Addon>", "combinedOff") oder nil, Text
function ns.LoginNotice()
    if not (ns.S and ns.S.grouping) then return nil end
    local otherBags = ns.OtherBags()
    if ns.ClassicUIBagsActive() then return "classicui", L.CONFLICT_CLASSICUI end
    if otherBags then return "bags:" .. tostring(otherBags), L.CONFLICT_BAGS:format(otherBags, otherBags) end
    if not ns.UsingCombinedBags() then return "combinedOff", L.COMBINED_OFF end
    return nil
end

-- Gemerkte Hinweise (ezBagDB.notices): login = zuletzt gezeigter Zustand, bankHint = „Bank einmal öffnen“ gesagt.
function ns.Notices()
    local db = ns.db
    if type(db) ~= "table" then return nil end
    if type(db.notices) ~= "table" then db.notices = {} end
    return db.notices
end

-- → true, wenn der Hinweis gezeigt wurde (neuer Zustand); false: nichts zu sagen oder schon gesagt.
function ns.ShowLoginNotice()
    local notices = ns.Notices()
    if not notices then return false end
    local state, text = ns.LoginNotice()
    if state == notices.login then return false end
    notices.login = state
    if not state then return false end
    ns.Print(text)
    return true
end

-- „Plunder beim Händler verkaufen“ ab Werk aus (Antwort des Nutzers vom 17.11.2026, wörtlich „user muss auf sowas
-- hingewiesen werden, er kann es nutzen muss es aber einschalten“; Fund des code-reviewers, Welle 28): Wer den alten
-- Standard (an) gespeichert hat, bekommt einmal den neuen – FillDefaults füllt nur Fehlendes, sonst bliebe es an.
-- Gemerkt wird der alte Wert (db.autoSellOff28Was = true), damit der Hinweis am Händler sagt, dass ezCollection
-- umgestellt hat; der Merker db.autoSellOff28 verhindert ein zweites Umstellen – wer es danach selbst einschaltet,
-- behält es. Rückgabe: true, wenn umgestellt wurde.
-- Seit dem Gesamtreview vom 18.11.2026 (T4-7) über ezCores Core.OptInOnce – Merker und Verhalten wie vorher.
function ns.MigrateAutoSellOptIn(db)
    return Core.OptInOnce(db, "autoSellOff28", { autoSell = "autoSellOff28Was" }) ~= nil
end

-- Einstellungs-Prüfung vom 19.11.2026 (Entscheidung des Nutzers „Ja, alle umsetzen“), einmal je Speicher:
--   - Nr. 56/57: „Belegt/frei“ an Rucksack und Bank ist ein Schalter (bagCount). An bleibt er, wenn einer der beiden
--     an war; der alte Bank-Schlüssel bankCount fällt weg.
--   - Nr. 97: „Leichter zerstören“ ab Werk aus; ein gespeichertes „an“ war der alte Standard, keine Wahl – einmal aus
--     (Merker easyDeleteOff1911Was für die Prüfung; wer es danach einschaltet, behält es).
--   - Immer an (Nr. 5, 6; Schloss „nie verkaufen“ aus Abschnitt 4): goldTooltip, bagValue, lockIcon haben keinen
--     Schalter mehr – ein gespeichertes „aus“ wird gelöscht, nicht mehr beachtet.
function ns.MigrateSettings1911(db)
    if type(db) ~= "table" or type(db.settings) ~= "table" then return nil end
    local S = db.settings
    local merged = Core.MigrateOnce(db, "settings1911", function()
        if S.bankCount ~= nil then
            S.bagCount = not (S.bagCount == false and S.bankCount == false)
            S.bankCount = nil
        end
        S.goldTooltip, S.bagValue, S.lockIcon = nil, nil, nil
        return true
    end)
    Core.OptInOnce(db, "easyDeleteOff1911", { easyDelete = "easyDeleteOff1911Was" })
    return merged
end

-- Gemeinsame Schalter (Einstellungs-Prüfung 19.11.2026; Entscheidung des Nutzers „Ja, alle umsetzen“): Diese Werte
-- liegen in ezCore und gelten für mehrere Module – Itemlevel und „BoE“ auch in ezLoots Beutefenster (Nr. 95/96),
-- „Plunder beim Händler verkaufen“ auch für ezMerchant (Nr. 59/60, ab Werk aus), die Münze „im Auktionshaus mehr
-- wert“ in der Tasche ist ezCores Schalter „in der Tasche“ (Nr. 50/58). ns.Enabled/ns.SetSetting, die Kästchen der
-- Seite (Spiegel) und die Slash-Schalter führen auf ezCores Wert; ns.OnLoad übernimmt die alten Werte einmal
-- (Core.AdoptModuleShared: ein „an“ bleibt an). old = ezBags früherer Standard: ein gespeicherter Wert gleich old ist
-- keine Wahl des Spielers (Core.FillDefaults hatte ihn gespeichert) und wird nicht übernommen.
ns.SHARED = Core.ShareSettings(ns, {
    itemLevel = { "itemMarks", "itemLevel", mode = "first", old = true },
    boe = { "itemMarks", "boe", mode = "first", old = true },
    autoSell = { "vendor", "autoSell", old = false },
    auctionWorth = { "priceOpts", "worthBag", old = false },
})

-- Nach dem Gerüst (ezBagDB angelegt, db.settings mit Standardwerten, ns.db und ns.S gesetzt): ezBags Übernahmen.
function ns.OnLoad(db)
    -- Einmalige Übernahme aus dem Vorgänger "TaschenGruppen": nur in einen frischen Speicher (das Gerüst hat ihn
    -- eben angelegt – ezBag selbst hat noch nichts hineingeschrieben).
    local old = rawget(_G, "TaschenGruppenDB")
    local fresh = db.version == nil and db.assign == nil and db.groups == nil and db.collapsedBy == nil
    if fresh and type(old) == "table" then
        for key, value in pairs(old) do
            if key == "settings" then
                for k, v in pairs(type(value) == "table" and value or {}) do db.settings[k] = v end
            else
                db[key] = value
            end
        end
        Core.FillDefaults(db.settings, ns.DEFAULTS, true)
        migrated = true
    end
    TaschenGruppenDB = nil
    -- nach der Übernahme: auch ein „an“ aus dem Vorgänger wird einmal umgestellt
    ns.MigrateAutoSellOptIn(db)
    ns.MigrateSettings1911(db)
    -- danach gehen die alten Werte der gemeinsamen Schalter einmal an ezCore (ns.SHARED)
    Core.AdoptModuleShared(ns, db)

    -- Zugeklappt je Ansicht; der alte gemeinsame Stand gilt für die Tasche.
    if not db.collapsedBy then
        db.collapsedBy = { bag = db.collapsed or {}, bank = {}, guild = {}, window = {} }
    end
    db.collapsed = nil
    -- 1.3: Fließ-Layout. Die Bank wird im Original gruppiert, das Fenster öffnet nicht mehr von selbst. (Hier stand
    -- bis Welle 23 auch „bankWindow = false“; der Schalter ist gestrichen, ein gespeicherter Wert bleibt unbeachtet
    -- liegen – Entscheidung des Nutzers vom 16.11.2026, Nr. 15, vorläufig nach Empfehlung.)
    if (db.version or 0) < 13 then
        db.settings.compact, db.settings.rectShapes = nil, nil
        for _, c in pairs(db.groups or {}) do c.width, c.shape = nil, nil end
        db.version = 13
    end
    db.assign = db.assign or {}
    db.groups = db.groups or {}     -- Anpassungen je Gruppe: label, sort, newRow
    db.custom = db.custom or {}     -- eigene Gruppen: [id] = { label = "...", rules = {...} }
    -- Charakterdaten, Gildenbanken und Item-Wissen liegen seit 1.4 in ezCore (ezCoreDB.chars/.guilds/
    -- .knowledge). db.chars, db.guilds und db.knowledge bleiben als Sicherung unverändert liegen.
    -- Lagen (Tasche, Bank, Gildenbank, einzelne Taschen, Fenster) liegen seit 1.8 in ezCoreDB.positions.
end

-- Item-Wissen (ezCore) anbinden: bei nachgeladenen Gegenständen sanft neu ordnen.
ns.Knowledge = Core.Knowledge

local function SetupKnowledge()
    local K = ns.Knowledge
    if not K then return end
    if K.OnReady then
        K.OnReady(ns.Throttle(function()
            ns.Groups.ClearRuleCache()
            if ns.Search then ns.Search.ClearCache() end
            if ns.Layout then ns.Layout.Request() end
            if ns.Bank then ns.Bank.Refresh(false) end
            if ns.GuildBank then ns.GuildBank.Refresh(false) end
            if ns.Window then ns.Window.Refresh(false) end
            -- Sammlungen und Bücher ändern sich (gelernt, abgegeben): Marken neu zeichnen.
            if ns.Marks then ns.Marks.Refresh() end
        end, 0.5))
    end
end

-- Beim Anmelden setzt das Gerüst ns.charKey, ns.realm, ns.me und ruft ns.RunReady. Diese Datei lädt als erste
-- nach den Texten: Ihr OnReady läuft darum vor allen anderen – Lagen übernehmen und Item-Wissen anbinden, bevor
-- Tasche, Bank und Fenster sich einrichten.
ns.OnReady(function()
    ns.MigratePositions()
    SetupKnowledge()
end)

-- Hinweise erst, wenn alle Dateien eingerichtet sind (dieser Zuhörer läuft nach dem des Gerüsts).
ns.On("PLAYER_LOGIN", function()
    if migrated then ns.Print(L.MIGRATED) end
    ns.ShowLoginNotice()
end)

---------------------------------------------------------------------------
-- Status (/eb status und Knopf „Status“ unter „Erweitert“)
---------------------------------------------------------------------------

local function OnOff(value) return value and L.ON or L.OFF end

---------------------------------------------------------------------------
-- Tooltip-Zeilen „Anzahl bei Twinks“ und „Item-Wissen“: zeigt seit BAG-05 ezCore (Seite „ezCollection“, Abschnitt
-- „Tooltip“). ezBag verweist nur dorthin – Knopf auf der eigenen Seite, Zeile im Status, die alten Befehle.
---------------------------------------------------------------------------

local TOOLTIP_COMMANDS = { tooltip = "counts", tooltipcounts = "counts", wissen = "knowledge", iteminfo = "knowledge",
    knowledge = "knowledge" }   -- englisch wie die Hilfe (T10-1)
local TOOLTIP_TEXT = { counts = "OPT_ttCounts", knowledge = "OPT_ttKnowledge" }

-- Steht der Abschnitt in ezCore an? (key = "counts" oder "knowledge")
function ns.CoreTooltipOn(key)
    return Core.OwnSetting and Core.OwnSetting("tooltip", key) ~= false
end

-- /eb tooltip und /eb wissen (vorher ezBags eigene Schalter): schalten ezCores Schalter um und sagen es im Chat.
-- → true, wenn cmd einer dieser Befehle war
function ns.ToggleCoreTooltip(cmd)
    local key = TOOLTIP_COMMANDS[cmd]
    local own = key and Core.OwnSettings and Core.OwnSettings("tooltip")
    if not own then return false end
    own[key] = own[key] == false
    ns.Print((own[key] and L.CMD_ON or L.CMD_OFF):format(Core.L[TOOLTIP_TEXT[key]]))
    return true
end

-- Seite „ezCollection“ öffnen (dort stehen die Schalter unter „Tooltip“); ohne Einstellungs-Fenster nennt der Chat
-- den Stand. Im Kampf merkt ezCore das Öffnen vor und sagt es selbst – dann keine zweite Meldung.
-- → true, wenn die Seite aufging oder nach dem Kampf aufgeht
function ns.OpenTooltipSettings()
    if Core.OpenSettings and Core.OpenedOrDeferred(Core.OpenSettings) then return true end
    ns.Print(ns.TooltipStatus())
    return false
end

function ns.TooltipStatus()
    return L.STATUS_TOOLTIP:format(OnOff(ns.CoreTooltipOn("counts")), OnOff(ns.CoreTooltipOn("knowledge")))
end

ns.AddStatusLine(function()
    if not ns.S then return nil end
    local lines = {}
    local state, text = ns.LoginNotice()
    lines[#lines + 1] = L.STATUS_GROUPING:format(OnOff(ns.S.grouping), OnOff(ns.S.bankGrouping), OnOff(ns.S.guildGrouping))
    -- Was die Gruppierung der Tasche gerade aufhält (ClassicUI, anderes Taschen-Addon, kombinierte Tasche aus)
    if state then lines[#lines + 1] = text end
    local sells = ns.OtherSellsJunk()
    lines[#lines + 1] = L.STATUS_SELL:format(OnOff(ns.Enabled("autoSell"))) .. (sells and (" " .. L.STATUS_OTHER:format(sells)) or "")
    local profile = ns.Profiles and ns.Profiles.Active and ns.Profiles.Active()
    lines[#lines + 1] = ns.TooltipStatus()
    if profile then lines[#lines + 1] = L.STATUS_PROFILE:format(ns.Profiles.Label and ns.Profiles.Label(profile) or profile) end
    local chars, guilds = 0, 0
    for _ in pairs(Core.CharacterList and Core.CharacterList() or {}) do chars = chars + 1 end
    for _ in pairs(Core.Guilds and Core.Guilds() or {}) do guilds = guilds + 1 end
    lines[#lines + 1] = L.STATUS_KNOWN:format(ns.CountWord("CHAR", chars), ns.CountWord("GUILDBANK", guilds))
    -- Wo die Liste mit „Vergessen“ steht (ezCores Seite; ezBag hat dafür den Knopf unter „Erweitert“)
    lines[#lines + 1] = L.STATUS_CHARS_WHERE:format(L.CHARS_HEADER, L.OPT_CHARS)
    if ns.slashAlias then lines[#lines + 1] = L.STATUS_ALIAS:format(ns.slashAlias) end
    return lines
end)

---------------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------------

-- ezBags eigene Befehle. Das Gerüst (/ezbag, Kurzbefehl /eb, wenn frei) ruft das zuerst; false = nicht meiner, dann
-- gelten dort die Hauptfunktion ohne Wort wie der Linksklick im Addon-Fach (slash.main: das ezBag-Fenster,
-- Entscheidung 5 vom 18.11.2026), „optionen“ die Einstellungen, „status“, „hilfe“, die Schalter aus ns.TOGGLES und
-- sonst die Hilfe.
function ns.SlashExtra(cmd, rest)
    if cmd == "fenster" or cmd == "window" then
        ns.Window.Toggle()
    elseif cmd == "bank" then
        ns.Window.Open(ns.charKey, "bank")
    elseif cmd == "gilde" or cmd == "guild" then
        ns.Window.OpenGuild()
    elseif cmd == "aufklappen" or cmd == "expand" then
        ns.Groups.ExpandEverything()
        ns.Print(L.CMD_EXPANDED)
    elseif cmd == "zuklappen" or cmd == "collapse" then
        -- Alle Gruppen aller Ansichten – auch Untergruppen („Unterteilen nach“) und ohne gespeicherte Reihenfolge (V-050).
        ns.Groups.CollapseEverything()
        ns.Print(L.CMD_COLLAPSED)
    elseif cmd == "umlagern" or cmd == "transfer" then
        ns.Transfer.Run("bag")
    elseif cmd == "position" then
        ns.Layout.ResetPosition()
        ns.Print(L.CMD_POSITION_RESET)
    elseif cmd == "reihenfolge" or cmd == "order" then
        ns.Groups.ResetOrder()
        ns.Print(L.CMD_ORDER_RESET)
    elseif ns.ToggleCoreTooltip(cmd) then
        -- /eb tooltip, /eb wissen: ezCores Schalter (BAG-05)
    elseif cmd == "chars" then
        Core.PrintChars(ns)
    elseif cmd == "vergessen" or cmd == "forget" then
        -- Die Charakterdaten liegen einmal in ezCore: vergessen gilt für alle Module.
        Core.ForgetCommand(ns, rest)
    else
        return false
    end
    return true
end

-- Addon-Fach an der Minikarte (TOC: AddonCompartmentFunc, …OnEnter, …OnLeave): Klick, Tooltip und Fehler in
-- ezCores Fehlerliste über ezCore.CompartmentHandlers. Entscheidung 5 vom 18.11.2026 (T18-3, T16-10): Linksklick das
-- ezBag-Fenster – dasselbe wie der Knopf oben rechts an der Tasche (vorher Rechtsklick) –, Rechtsklick die
-- Einstellungen (sonst Hilfe).
ezBag_OnAddonCompartmentClick, ezBag_OnAddonCompartmentEnter, ezBag_OnAddonCompartmentLeave = Core.CompartmentHandlers({
    ns = ns,
    title = ADDON,
    main = function() ns.Window.Toggle() end,
    mainText = L.COMPARTMENT_MAIN,
    owner = ADDON,
})
