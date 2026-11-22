local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Blizzards Menü „Aufspüren“ an der Minikarte um sinnvolle Punkte erweitern (Wunsch des Nutzers 13.11.2026).

    Geprüft in Blizzards Forever-Quelle (Blizzard_Minimap, Mainline Minimap.lua): MiniMapTrackingButtonMixin:OnLoad
    baut das Menü mit SetupMenu und gibt ihm das Tag MENU_MINIMAP_TRACKING. ezMap hängt sich über Blizzards
    Menu.ModifyMenu an und fügt unten einen Abschnitt „ezMap“ an; Blizzards Einträge bleiben unberührt.

    Aufgenommen – Ziele für Blizzards Markierung; Blizzards Pfeil dazu nur, wenn sie verfolgt wird
    (Schalter wayTrack oder Klick auf die Markierung; seit Welle 29, Entscheidung des Nutzers vom 17.11.2026
    „Nur mit Schalter (Empfohlen)“):
      - Nächster Flugmeister (C_TaxiMap.GetTaxiNodesForMap wie Blizzards Weltkarte; auch noch nicht entdeckte der
        eigenen Fraktion, gerade die sucht man); mit gesetzter Markierung dazu der Flugmeister am Ziel und die
        gelernte Flugzeit dorthin (kein Routenplaner)
      - Lehrer wie im Kartenmenü (nächster Klassenlehrer und alle besuchten)
      - Dungeoneingänge deiner Zone (nur, wenn der Client sie liefert)
      - Zuletzt gesetzte Markierungen, Markierung entfernen
      - Schalter „Von selbst herauszoomen“ (MinimapZoom.lua), „Eckige Minikarte“ (MinimapShape.lua), Einstellungen
      - seit Welle 15 (SAM-11): „Sammel-Fundorte auf der Minikarte“ je Art und „Nur bei aktiver Suche“
        (Gather.AddMiniMenu); fehlt ezCores Sichtradius, ausgegraut mit Erklärung
    Nicht aufgenommen (Begründung in der ROADMAP, Abschnitt ezMap): Quest-Ziele, Briefkasten, Gasthaus und Bank der
    Zone.

    Seit Welle 16 (Wunsch des Nutzers vom 15.11.2026 abends, TrackingMemory.lua): oben „Alle auswählen“ über ezCores
    Baustein Menu.AllToggle. Seit dem 21.11.2026 (Nutzer: „alle abwählen alle anwählen kann auch einfach ein haken oder
    eben kein haken sein“) EIN Haken „Alle“ an der Stelle von Blizzards Eintrag UNCHECK_ALL, den ezMap dafür nur in der
    Darstellung ausblendet (Tracking.HideBlizzardEntry; Ausnahme von Leitlinie 5 nur für dieses Menü, Entscheidung des
    Nutzers vom selben Tag); fehlt Blizzards Eintrag (Client-Einstellung minimapTrackingShowAll), steht der Haken oben. Unabhängig vom Schalter
    trackingMenu (es ist kein Ziel, sondern Blizzards eigene Liste). Im Abschnitt „ezMap“ der Schalter „Auswahl oben
    merken“ (trackingRemember).

    Seit Welle 27 (Zweig modul/ezmap-menue; Wunsch des Nutzers vom 16.11.2026 mit Bildschirmfoto dieses Menüs,
    wörtlich „sollte sicherlich mit ezmap gekoppelt oder so sein... enterprise“): der Abschnitt „ezMap“ ist nach
    denselben Themen geordnet wie ezMaps Kartenfilter (Tree.lua) und trägt dieselben Symbole wie Blizzards Liste
    darüber – Lehrer mit Blizzards Bild „Lehrer für eine Klasse“, Flugmeister mit dem Bild „Flugmeister“, die
    Sammel-Arten mit Blizzards Such-Atlanten (Icons.lua liest sie zur Laufzeit aus C_Minimap.GetTrackingInfo).
    Abschnitte: „Dienste in der Stadt“, „Reise“, „Sammeln“, „Wegpunkte“, „Minikarte“, dann „Einstellungen“
    (Tracking.SECTIONS).

    Kopplung (Antwort des Nutzers vom 17.11.2026 auf die Frage A/B/C, wörtlich „alles davon“; Wortlaut im ROADMAP-Index):
      A) Optik und Ordnung wie oben.
      B) gleicher Platz: Einträge, die eine Blizzard-Art ergänzen, gehören zu Blizzards Eintrag dieser Art. Gefunden
         wird er über den Namen der Art aus dem Client (C_Minimap.GetTrackingInfo(i).name der Art mit passender
         filterID, MenuUtil.GetElementText). Bis zum 21.11.2026 standen „Nächster Flugmeister“ und „Flugmeister am
         Ziel“ als eigene Zeilen direkt unter Blizzards „Flugmeister“ (Tracking.BESIDE, eingefügt über
         Core.Menu.InsertRoot). Seit dem Spielbefund vom 21.11.2026 (Nutzer: „sehr gut, aber zum bild die funktion ist gut die anzeige schlecht. man sollte alle einzeln aus dem menü markieren können“) hängen sie
         wie die Lehrer als Untermenü an Blizzards Haken, zusammen mit allen Flugmeistern deines Kontinents je Zone
         (Tracking.AttachFlights, MapButton.FillFlights); fehlt Blizzards Haken, steht ein eigener Knopf
         „Flugmeister“ im Abschnitt „Reise“.
      Lehrer seit dem Spielbefund vom 21.11.2026 (Nutzer: „entweder muss beides sauber aufgelöst werden oder eben direkt
      anhakbar sein wie Lehrer für eine klasse, wie es jetzt ist, ist es doppelt gemoppelt“): kein eigener Eintrag
      „Lehrer“ mehr neben Blizzards Haken. ezMaps Liste hängt als Untermenü an Blizzards Haken selbst
      (Tracking.TRAINER_GROUPS): Klassenlehrer, Tierausbilder und weitere Lehrer samt „Nächster Klassenlehrer/
      Tierausbilder“ an „Lehrer für eine Klasse“, besuchte Berufslehrer an „Berufsausbilder“. Der Haken bleibt Blizzards
      (Text, Zustand, Blizzards eigene Schaltfunktion; ein Klick schaltet weiter das Aufspüren), ezMap legt nur
      Kind-Einträge an – Blizzards Menüsystem kennt „Haken, der zugleich Untermenü ist“ (Blizzard_Menu/Menu.lua,
      MenuManagerMixin:AttributeRespond: „a radio or checkbox is also a submenu“; Pick ruft den Responder auch mit
      Untermenü). Damit Blizzards Pfeil (MenuVariants.CreateSubmenuArrow, rechts) nicht auf Blizzards Symbol (ebenfalls
      rechts, Mainline Minimap.lua CreateCheckboxWithIcon) liegt, rückt ein Initializer das Symbol links neben den Pfeil.
      Fehlt Blizzards Haken einer Gruppe, stehen deren Lehrer wie bisher unter „Lehrer“ im Abschnitt. Ohne besuchte
      Lehrer einer Gruppe bleibt deren Haken ohne Untermenü (keine leere Liste an Blizzards Eintrag); nur „Lehrer für eine
      Klasse“ zeigt dann „Noch keine – öffne das Fenster eines Lehrers …“, damit die Funktion sichtbar bleibt
      (Leitlinie 3; Fund des code-reviewers vom 21.11.2026).
      Gastwirt, Stallmeister, Auktionator, Bankier, Kampfmeister seit dem 22.11.2026 (Frage des Nutzers „ob das
      ausklappmenü im menüpunkt nicht bei jedem menüpunkt vorhanden sein sollte“, Antwort „ok“ auf die feste Regel):
      Untermenü an Blizzards Haken mit „Nächster …“ und – seit dem Spielbefund vom selben Tag („wieso der
      unterschied?“, Antwort „Ja, wie Lehrer“) – allen des Kontinents je Zone wie bei den Lehrern, laut Questie
      (Tracking.ROLE_GROUPS, Tracking.AttachRoles, MapButton.FillRole, MapButton.ZoneList). Briefkasten und Niedrigstufige
      Quests bleiben ohne Pfeil.
      C) gemeinsames Schalten: Schalter „Mit Blizzards Aufspüren gemeinsam schalten“ (trackingCouple, ab Werk aus) im
         Abschnitt „Minikarte“ und auf der Einstellungsseite; die Kopplung selbst in TrackingCouple.lua.
]]
local Tracking = {}
ns.Tracking = Tracking
Tracking.TAG = "MENU_MINIMAP_TRACKING"

local Menu = Core.Menu

-- Zone, in der du stehst (über Kleinkarten wie Stadtvierteln hinweg), für die Dungeoneingänge: Elternkarte bis zur
-- Art „Zone“ aus ezCore (Core.Map.Parent, W-14); kennt der Client die Kette nicht, bleibt es deine Karte.
local function PlayerZone()
    local mapID = ns.PlayerPosition()
    if not mapID then return nil end
    return (Core.Map.Parent(mapID, "Zone")) or mapID
end

-- Stelle von Blizzards Eintrag UNCHECK_ALL in der Liste (Blizzard setzt ihn als ersten). → Stelle | nil, gefunden?,
-- Blizzards Beschreibung (nur, wenn gefunden). Lässt sich die Liste nicht durchsehen, gilt Blizzards Quelle: ohne
-- minimapTrackingShowAll steht er oben.
function Tracking.BlizzardUncheckIndex(root)
    local util = rawget(_G, "MenuUtil")
    local blizzardText = rawget(_G, "UNCHECK_ALL")
    if type(root.EnumerateElementDescriptions) == "function" and type(util) == "table"
        and type(util.GetElementText) == "function" and type(blizzardText) == "string" and not Core.IsSecret(blizzardText) then
        local ok, found, desc = pcall(function()
            for index, d in root:EnumerateElementDescriptions() do
                local text = util.GetElementText(d)
                if not Core.IsSecret(text) and text == blizzardText then return index, d end
            end
        end)
        if ok then return found, true, found and desc or nil end
    end
    if ns.TrackingMemory.ShowAll() then return nil, true end
    return 1, false
end

--[[
    Blizzards „Alle abwählen“ ausblenden (Entscheidung des Nutzers vom 21.11.2026 auf die Frage „Wie soll der eine Haken
    im Menü „Aufspüren“ entstehen?“: „Hide Blizzard's (Recommended)“ – Ausnahme von Leitlinie 5 nur für dieses Menü).
    Nur Darstellung: ein Initializer an Blizzards Beschreibung macht den Knopf dieses Öffnens 1 Bildpunkt hoch,
    durchsichtig und ohne Maus (Blizzards CallInitializers nimmt die Größe des letzten Initializers und rundet sie,
    Blizzard_Menu/Menu.lua). Nicht 0 hoch: Spielbefund vom 21.11.2026 – das Menü schrumpfte auf ein winziges Kästchen
    (ein 0 hoher Rahmen hat kein gültiges Rechteck, die Einträge darunter hängen an ihm, und Blizzards MeasureExtents
    überspringt ungültige Rechtecke). Ein Fehler im Initializer darf Blizzards Menü nie abbrechen (pcall). Ein
    Resetter gibt den Knopf vor der Wiederverwendung im Pool zurück (Menu.lua, SecureCallResetters). Text, Klick und
    Reihenfolge von Blizzards Eintrag bleiben; kein Wert in Blizzards Tabellen. → true, wenn angemeldet.
]]
function Tracking.HideBlizzardEntry(desc)
    if type(desc) ~= "table" or Core.IsSecret(desc) or type(desc.AddInitializer) ~= "function"
        or type(desc.AddResetter) ~= "function" then
        return false
    end
    local ok = pcall(desc.AddInitializer, desc, Tracking.HideButton)
    if ok then ok = pcall(desc.AddResetter, desc, Tracking.ShowButton) end
    return ok
end

Tracking.HIDDEN_HEIGHT = 1     -- Bildpunkte; nie 0 (siehe oben)
function Tracking.HideButton(button)
    if type(button) ~= "table" then return nil end
    local ok = pcall(function()
        if type(button.SetAlpha) == "function" then button:SetAlpha(0) end
        if type(button.EnableMouse) == "function" then button:EnableMouse(false) end
    end)
    if not ok then return nil end      -- dann bleibt Blizzards Eintrag sichtbar statt eines kaputten Menüs
    return 1, Tracking.HIDDEN_HEIGHT
end

function Tracking.ShowButton(button)
    if type(button) ~= "table" then return end
    pcall(function()
        if type(button.SetAlpha) == "function" then button:SetAlpha(1) end
        if type(button.EnableMouse) == "function" then button:EnableMouse(true) end
    end)
end

-- Ein Haken „Alle“ an der Stelle von Blizzards „Alle abwählen“ (ezCores Baustein; seit 21.11.2026 statt „Alle
-- auswählen“ darunter). Angehakt, wenn alle Arten an sind, die beim Einschalten zählen (ohne Such-Zauber,
-- Memory.SkipOn); Ausschalten wie Blizzards Eintrag ohne Blizzards Pflicht-Arten (Memory.SkipOff). Fehlt Blizzards
-- Eintrag (Client-Einstellung minimapTrackingShowAll), steht der Haken oben. → der Haken
function Tracking.AddAllToggle(root)
    local Memory = ns.TrackingMemory
    if not (Memory.Available() and type(Menu.AllToggle) == "function") then return nil end
    local index, _, blizzard = Tracking.BlizzardUncheckIndex(root)
    local at = index and index + 1 or 1
    local entry = Menu.AllToggle(root, Memory.List, Memory.IsActive, Memory.Set,
        { tip = L.TRACK_ALL_TIP, onSkip = Memory.SkipOn, offSkip = Memory.SkipOff, at = at,
          onAfter = Memory.AfterOnSay,      -- ausgelassene Such-Zauber im Chat nennen (Spielbefund 18.11.2026)
          offAfter = Memory.AfterOffSay })  -- Such-Zauber im Kampf erst danach
    -- nur ausblenden, wenn der Haken wirklich dort steht (sonst hängt AllToggle ihn ans Ende und oben fehlte jede
    -- Sammel-Auswahl; Fund des code-reviewers vom 21.11.2026)
    if entry and blizzard and Tracking.EntryAt(root, at) == entry then Tracking.HideBlizzardEntry(blizzard) end
    return entry
end

-- Eintrag an Stelle at der Liste (Blizzards EnumerateElementDescriptions) → Beschreibung oder nil
function Tracking.EntryAt(root, at)
    if type(root) ~= "table" or type(root.EnumerateElementDescriptions) ~= "function" then return nil end
    local ok, found = pcall(function()
        for index, desc in root:EnumerateElementDescriptions() do
            if index == at then return desc end
        end
    end)
    return ok and found or nil
end

-- Abschnitt „ezMap“ als Tabelle (Welle 27): Abschnitte wie im Kartenfilter, je Eintrag Symbol und Baustein (siehe
-- MapButton.SECTIONS). Jeder Eintrag hat eine Erklärzeile mit Quelle (MAP-19, MapButton.Tip über ezCores Menu.Tip).
-- Reihenfolge wie im ezMap-Knopf der Weltkarte (MapButton.SECTIONS): Wegpunkte, Dienste in der Stadt, Reise,
-- Sammeln, dann das Eigene dieses Menüs („Minikarte“). Entscheidung des Nutzers vom 22.11.2026 („ok mach das so“ auf
-- den Vorschlag „gleiche Reihenfolge, gleiche Bausteine – Weltkarte: gezeigte Karte, Minikarte: dein Standort“).
-- Was eine Karte braucht (Koordinaten eingeben, Leveling-Route, Bücher, seltene Gegner), bleibt im ezMap-Knopf.
Tracking.SECTIONS = {
    { id = "way", title = "MSEC_WAY", icon = "own", entries = { "here", "clear", "recent" } },
    { id = "town", title = "OPT_tree_town", icon = "town", tip = "TRACK_SEC_TOWN_TIP",
      entries = { "trainers", "vendors" } },
    { id = "journey", title = "OPT_tree_journey", icon = "journey", entries = { "flights", "entrances" } },
    { id = "gather", title = "OPT_tree_gather", icon = "gather", entries = { "gatherMini" } },
    { id = "minimap", title = "TRACK_SEC_MINIMAP", icon = "menuMinimap",
      entries = { "remember", "couple", "autoZoom", "square" } },
}

-- Lehrer an Blizzards Haken (Spielbefund 21.11.2026): je Gruppe die Blizzard-Art, deren Haken die Liste als Untermenü
-- trägt, die Arten der Lehrer (Trainers.KindOf) und die Blätter des Baums (Tree.lua), von denen eines an sein muss
Tracking.TRAINER_GROUPS = {
    { track = "TrainerClass", kinds = { class = true, pet = true, other = true }, head = "TRACK_TRAINERS_HEAD",
      leaves = { "trainerClass", "trainerPet", "trainerOther" } },
    { track = "TrainerProfession", kinds = { profession = true }, head = "TRACK_TRAINERS_HEAD_PROF",
      leaves = { "trainerProf" }, skipEmpty = true },     -- ohne besuchte Berufslehrer kein Untermenü
}

-- Weitere Stadtbewohner an Blizzards Haken (Entscheidung des Nutzers vom 22.11.2026: „ok“ auf „feste Regel: Pfeil an
-- jedem Haken, hinter dem eine suchbare NPC-Art mit Daten steckt – Gastwirt, Stallmeister, Auktionator, Bankier,
-- Kampfmeister mit „Nächster …“ und den NPCs deiner Zone; Briefkasten und Niedrigstufige Quests ohne Pfeil“). Je Gruppe
-- die Rolle in ezCore (Core.Npcs.ROLES, laut Questie) und die Blizzard-Art (Icons.FILTER), deren Haken sie trägt.
-- Briefkasten (keine NPCs) und Niedrigstufige Quests (keine Daten) stehen bewusst nicht hier.
Tracking.ROLE_GROUPS = {
    { role = "innkeeper", track = "Innkeeper" },
    { role = "stablemaster", track = "Stablemaster" },
    { role = "auctioneer", track = "Auctioneer" },
    { role = "banker", track = "Banker" },
    { role = "battlemaster", track = "Battlemaster" },
}

Tracking.ENTRIES = {
    -- eigene Position markieren: derselbe Baustein wie im ezMap-Knopf (MapButton.ENTRIES.here)
    here = { icon = "menuHere", build = function(root) ns.MapButton.ENTRIES.here.build(root) end },
    -- nur die Lehrer, deren Gruppe keinen Haken von Blizzard fand (Tracking.AttachTrainers); ohne Blizzards Haken alle
    trainers = { icon = "trainers", build = function(root, rest)
        if rest == nil then ns.MapButton.AddTrainers(root)
        elseif next(rest.kinds) then ns.MapButton.AddTrainers(root, { kinds = rest.kinds, other = rest.other }) end
    end },
    -- Händler deiner Zone: nur, wenn Blizzards Haken „Reparieren“ fehlt (sonst hängt die Liste dort,
    -- Tracking.AttachVendors)
    vendors = { icon = "vendors", build = function(root, attached)
        if not attached then ns.MapButton.AddVendors(root, Tracking.PlayerZone()) end
    end },
    -- Flugmeister: nur, wenn Blizzards Haken „Flugmeister“ fehlt (sonst hängt die Liste dort, Tracking.AttachFlights)
    flights = { icon = "travel", build = function(root, attached)
        if not attached then ns.MapButton.AddFlights(root) end
    end },
    entrances = { icon = "dungeons", build = function(root) ns.MapButton.AddEntrances(root, PlayerZone()) end },
    -- Sammel-Fundorte auf der Minikarte (SAM-11); die Symbole je Art setzt Gather.AddMiniMenu selbst, die Vorgabe hier
    -- gilt für die übrigen Einträge (Fund des code-reviewers vom 17.11.2026: „Nur bei aktiver Suche“ ohne Symbol)
    gatherMini = { icon = "gatherMini", build = function(root) ns.Gather.AddMiniMenu(root) end },
    recent = { icon = "wayRecent", build = function(root) ns.MapButton.AddRecent(root) end },
    clear = { icon = "menuClear", build = function(root) if ns.Way.Get() then ns.MapButton.AddClear(root) end end },
    remember = { icon = "menuMinimap", build = function(root)
        local _, why, who = ns.TrackingMemory.Active()
        if why == "other" then
            ns.MapButton.OtherTitle(root, L.TRACK_REMEMBER_OTHER:format(who))
        elseif why ~= "api" then
            ns.MapButton.Toggle(root, L.TRACK_REMEMBER, "trackingRemember")   -- Auswahl oben merken (Welle 16)
        end
    end },
    -- Kopplung C (Antwort des Nutzers vom 17.11.2026): Blizzards Haken und ezMaps passende Gruppe gemeinsam schalten
    couple = { icon = "couple", build = function(root)
        if ns.TrackingMemory.Available() then ns.MapButton.Toggle(root, L.OPT_trackingCouple, "trackingCouple") end
    end },
    autoZoom = { icon = "menuMinimap", build = function(root)
        local other = ns.MinimapZoom.AutoElsewhere()
        if other then
            ns.MapButton.OtherTitle(root, L.TRACK_AUTOZOOM_OTHER:format(other))
        else
            -- Haken über dem Schieber minimapAutoZoomDelay (0 = aus; Nr. 91 der Einstellungs-Prüfung vom 19.11.2026)
            local Z = ns.MinimapZoom
            ns.MapButton.Toggle(root, L.TRACK_AUTOZOOM, "minimapAutoZoomDelay", Z.SetOn, Z.On)
        end
    end },
    square = { icon = "menuMinimap", build = function(root)
        local shaper = ns.MinimapShape.Elsewhere()
        if shaper then
            ns.MapButton.OtherTitle(root, L.TRACK_SQUARE_OTHER:format(shaper))
        else
            ns.MapButton.Toggle(root, L.TRACK_SQUARE, "minimapSquare")
        end
    end },
}

-- Name einer Blizzard-Art im Client (Kopplung B): GetTrackingInfo(i).name der gezeigten Art mit passender filterID
-- (TrackingMemory.List lässt gesperrte Antworten aus) → Text oder nil
function Tracking.TrackName(filterName)
    local want = ns.Icons.FilterID(filterName)
    if not want then return nil end
    for _, entry in ipairs(ns.TrackingMemory.List()) do
        if entry.filterID == want and entry.name ~= entry.key then return entry.name end
    end
    return nil
end

-- Blizzards Eintrag dieser Art im Menü (oben oder eine Ebene tiefer) → Beschreibung, die ihn enthält, seine Stelle und
-- er selbst; nil, wenn er fehlt
local function Locate(root, filterName)
    local util = rawget(_G, "MenuUtil")
    local name = Tracking.TrackName(filterName)
    if not name or type(util) ~= "table" or type(util.GetElementText) ~= "function" then return nil end
    local function Search(parent, deeper)
        if type(parent) ~= "table" or type(parent.EnumerateElementDescriptions) ~= "function" then return nil end
        local subs = {}
        local ok, found, entry = pcall(function()
            for index, desc in parent:EnumerateElementDescriptions() do
                local text = util.GetElementText(desc)
                if not Core.IsSecret(text) and text == name then return index, desc end
                subs[#subs + 1] = desc
            end
        end)
        if ok and found then return parent, found, entry end
        if not (ok and deeper) then return nil end
        for _, desc in ipairs(subs) do
            local p, at, e = Search(desc, false)
            if p then return p, at, e end
        end
        return nil
    end
    return Search(root, true)
end

-- Blizzards Haken dieser Art, wenn er Kind-Einträge annimmt (CreateButton der Beschreibung) → Beschreibung oder nil
function Tracking.BlizzardEntry(root, filterName)
    local _, _, entry = Locate(root, filterName)
    if type(entry) == "table" and not Core.IsSecret(entry) and type(entry.CreateButton) == "function" then return entry end
    return nil
end

-- Blizzards Pfeil des Untermenüs und Blizzards Symbol der Art sitzen beide rechts im Haken: das Symbol links neben den
-- Pfeil rücken, die Breite um den Pfeil erweitern (Blizzards Formel aus CreateCheckboxWithIcon: Textbreite + 60, Höhe
-- 20). Gefunden wird das Symbol über den rechten Anker von Blizzards Text; ohne Pfeil oder Symbol bleibt alles, wie es
-- ist. Nur Darstellung am Menüknopf dieses Öffnens, kein Wert in Blizzards Tabellen.
Tracking.ARROW_ROOM = 18
function Tracking.ArrowRoom(button)
    if type(button) ~= "table" then return nil end
    local arrow, fs = button.arrow, button.fontString
    if type(arrow) ~= "table" or type(fs) ~= "table" or type(fs.GetNumPoints) ~= "function"
        or type(fs.GetPoint) ~= "function" then
        return nil
    end
    local icon
    for i = 1, fs:GetNumPoints() do
        local point, rel = fs:GetPoint(i)
        if point == "RIGHT" and type(rel) == "table" and rel ~= arrow and rel ~= button then icon = rel end
    end
    if not (icon and type(icon.ClearAllPoints) == "function" and type(icon.SetPoint) == "function") then return nil end
    icon:ClearAllPoints()
    icon:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
    if type(fs.GetUnboundedStringWidth) ~= "function" then return nil end
    local width = fs:GetUnboundedStringWidth()
    if Core.IsSecret(width) or type(width) ~= "number" then return nil end
    return width + 60 + Tracking.ARROW_ROOM, 20
end

-- Gruppe gewollt? Mindestens ein Blatt im Baum an (Tree.Any: auch die dynamische Gruppe der Berufslehrer)
local function GroupWanted(group)
    for _, leaf in ipairs(group.leaves) do
        if ns.Tree.Any(leaf) then return true end
    end
    return false
end

-- Lehrer als Untermenü an Blizzards Haken hängen (Spielbefund 21.11.2026). → nil, wenn keiner der Haken da ist (dann
-- steht „Lehrer“ wie bisher im Abschnitt); sonst { kinds = Arten ohne Haken, other = Hinweis auf ein Addon noch offen }
function Tracking.AttachTrainers(root)
    if not ns.Tree.Any("trainers") then return { kinds = {}, other = false } end
    local rest, other, attached = {}, true, false
    for _, group in ipairs(Tracking.TRAINER_GROUPS) do
        if GroupWanted(group) then
            local entry = Tracking.BlizzardEntry(root, group.track)
            if entry then
                attached = true     -- auch ohne Untermenü versorgt: kein eigener „Lehrer“ mit leerer Liste
                if ns.MapButton.FillTrainers(entry, { kinds = group.kinds, head = L[group.head], other = other,
                    skipEmpty = group.skipEmpty }) then
                    other = false
                    ns.Try("TrackingArrowRoom", entry.AddInitializer, entry, Tracking.ArrowRoom)
                end
            else
                for kind in pairs(group.kinds) do rest[kind] = true end
            end
        end
    end
    if not attached then return nil end
    return { kinds = rest, other = other }
end

-- Flugmeister als Untermenü an Blizzards Haken „Flugmeister“ (Spielbefund 21.11.2026, wie die Lehrer). → true, wenn
-- Blizzards Haken da ist (dann steht kein eigener Knopf im Abschnitt; ohne Flugmeister bleibt der Haken ohne Pfeil)
function Tracking.AttachFlights(root)
    local entry = Tracking.BlizzardEntry(root, "TaxiNode")
    if not entry then return false end
    if ns.MapButton.FillFlights(entry, { head = L.TRACK_FLIGHTS_HEAD }) then
        ns.Try("TrackingArrowRoom", entry.AddInitializer, entry, Tracking.ArrowRoom)
    end
    return true
end

-- Deine Zone (die Händlerliste im Menü „Aufspüren“ gilt für den Ort, an dem du stehst) oder nil. Die Karte kommt von
-- Blizzards GetBestMapForUnit – ohne Koordinaten (in Instanzen ist die Position gesperrt, die Karte nicht).
function Tracking.PlayerZone()
    local api = rawget(_G, "C_Map")
    local map = type(api) == "table" and ns.Num(Core.Call(api.GetBestMapForUnit, "player")) or nil
    map = map or ns.PlayerPosition()
    return map and (Core.Map.Parent(map, "Zone") or map) or nil
end

-- Händler deiner Zone als Untermenü an Blizzards Haken „Reparieren“ (Spielbefund des Nutzers vom 22.11.2026: „händler
-- hier finde ich im menü nicht“ – die Liste stand nur im ezMap-Knopf der Weltkarte). Wie Lehrer und Flugmeister: der
-- Haken schaltet weiter Blizzards Aufspüren. → true, wenn Blizzards Haken da ist (dann kein eigener Knopf)
function Tracking.AttachVendors(root)
    local entry = Tracking.BlizzardEntry(root, "Repair")
    if not entry then return false end
    local zone = Tracking.PlayerZone()
    if zone and ns.Tree.Any("vendors") and ns.MapButton.FillVendors(entry, zone, { head = L.TRACK_VENDORS_HEAD }) then
        ns.Try("TrackingArrowRoom", entry.AddInitializer, entry, Tracking.ArrowRoom)
    end
    return true
end

-- Gastwirte, Stallmeister, Auktionatoren, Bankiers und Kampfmeister laut Questie als Untermenü an Blizzards Haken
-- (wie Lehrer, Flugmeister und Händler; der Haken schaltet weiter Blizzards Aufspüren). Fehlt Blizzards Haken, kommt
-- kein eigener Knopf dazu; ohne Daten bleibt der Haken ohne Pfeil. Gelesen wird einmal je Öffnen und nur, wenn einer
-- der Haken da ist. → Anzahl der Haken mit Untermenü
function Tracking.AttachRoles(root)
    if not ns.Tree.Any("town") then return 0 end
    local lists, pending, zone
    local n = 0
    for _, group in ipairs(Tracking.ROLE_GROUPS) do
        local entry = Tracking.BlizzardEntry(root, group.track)
        if entry then
            if not lists then
                zone = Tracking.PlayerZone()
                lists, pending = ns.MapButton.RoleLists(zone)
            end
            if ns.MapButton.FillRole(entry, group.role, { list = lists[group.role] or {}, pending = pending, zone = zone }) then
                n = n + 1
                ns.Try("TrackingArrowRoom", entry.AddInitializer, entry, Tracking.ArrowRoom)
            end
        end
    end
    return n
end

function Tracking.Build(root)
    ns.Try("TrackingAllToggle", Tracking.AddAllToggle, root)   -- ein Fehler dort kostet nicht den Abschnitt darunter
    if not ns.Enabled("trackingMenu") then return end
    local Box = ns.MapButton
    -- Lehrer und Flugmeister an Blizzards Haken zuerst (kein Eintrag doppelt). Ein Fehler dort wird gemeldet (Core.Try,
    -- reicht anders als ns.Try das Ergebnis durch) und kostet nur diese Einträge: lieber ein unvollständiges Untermenü
    -- als dieselben Einträge noch einmal im Abschnitt (Fund des code-reviewers vom 21.11.2026)
    local okTrainers, trainersRest = Core.Try("ezMap", "TrackingTrainers", Tracking.AttachTrainers, root)
    if not okTrainers then trainersRest = { kinds = {}, other = false } end
    local okFlights, flightsAttached = Core.Try("ezMap", "TrackingFlights", Tracking.AttachFlights, root)
    if not okFlights then flightsAttached = true end
    local okVendors, vendorsAttached = Core.Try("ezMap", "TrackingVendors", Tracking.AttachVendors, root)
    if not okVendors then vendorsAttached = true end
    Core.Try("ezMap", "TrackingRoles", Tracking.AttachRoles, root)     -- nur an Blizzards Haken, kein eigener Knopf
    local given = { trainers = trainersRest, flights = flightsAttached, vendors = vendorsAttached }
    Menu.Divider(root)
    ns.MapButton.Tip(Menu.Title(root, L.TRACK_TITLE), L.TRACK_TITLE, L.TRACK_TITLE_TIP)
    -- der erste Abschnitt, der etwas enthält, steht ohne Trenner direkt unter dem Titel – auch wenn „Dienste in der
    -- Stadt“ leer bleibt (alle Lehrer aus; Fund der Gegenprüfung 17.11.2026)
    local chain = {}
    for _, section in ipairs(Tracking.SECTIONS) do
        local sec = Menu.Section(root, L[section.title] or section.title, { icon = ns.Icons.For(section.icon),
            tip = section.tip and L[section.tip] or nil, chain = chain })
        for _, key in ipairs(section.entries) do
            local e = Tracking.ENTRIES[key]
            if e then ns.Try("TrackingMenu:" .. key, e.build, ns.Icons.Root(sec, e.icon), given[key]) end
        end
    end
    Menu.Divider(root)
    Box.AddSettings(root)
end

-- Einmal anmelden; Blizzard ruft die Ergänzung bei jedem Öffnen des Menüs auf. Der Schalter wirkt sofort.
local registered = false
function Tracking.Register()
    local blizzardMenu = rawget(_G, "Menu")
    if registered or not (type(blizzardMenu) == "table" and type(blizzardMenu.ModifyMenu) == "function") then
        return registered
    end
    registered = pcall(blizzardMenu.ModifyMenu, Tracking.TAG, function(_, root)
        ns.Try("TrackingMenu", Tracking.Build, root)
    end)
    return registered
end

ns.OnReady(function() Tracking.Register() end)
