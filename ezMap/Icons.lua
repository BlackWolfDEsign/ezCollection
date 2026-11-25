local _, ns = ...
local Core = ezCore

--[[
    Symbole der ezMap-Menüs an EINER Stelle (Welle 27, Zweig modul/ezmap-menue; Wunsch des Nutzers vom 16.11.2026,
    wörtlich: „das filter menü von ezmap ist schon geil, aber die passenden icons wären der hit, also passend für
    lehrer, händler, briefkasten, schmied und co“; Nachtrag mit Bildschirmfoto von Blizzards Menü „Aufspüren“: „sollte
    sicherlich mit ezmap gekoppelt oder so sein... enterprise“).

    Quellen in dieser Reihenfolge (Leitlinien 1 und 11), keine eigenen Bilddateien:
      1. Blizzards Menü „Aufspüren“ zur Laufzeit: C_Minimap.GetTrackingInfo(i).texture der Art, deren
         GetTrackingFilter(i).filterID passt – dieselben Bilder, die Blizzard dort rechts neben den Einträgen zeigt
         (Blizzard_Minimap/Mainline/Minimap.lua, CreateCheckboxWithIcon; Zweig forever). Zauber-Arten mit
         abgeschnittenem Rand wie dort.
      2. Blizzards Atlas aus derselben Quelle: TRACKING_SPELL_OVERRIDE_ATLAS in Minimap.lua („professions_tracking_herb“,
         „…_ore“, „…_fish“ für Kräuter-, Mineralien- und Fischsuche), sonst Atlanten der Weltkarte.
      3. Blizzards Dateien: die Minikarten-Symbole Interface\Minimap\Tracking\… und Zauber-/Gegenstandssymbole
         Interface\Icons\… – nur, wenn der Client die Datei kennt (Core.KnownFile).
      4. Berufe: das Symbol des Berufszaubers über die API – ezCores Core.Menu.ProfessionIcon bzw.
         Core.Menu.ProfessionIconOfTitle (seit dem Fund des code-reviewers vom 17.11.2026 in ezCore, damit ezCraft- und
         ezTalent-Menü dasselbe nutzen; Leitlinie 2).
      Fehlt alles, nimmt ezCore Blizzards Fragezeichen (Core.Menu.ICON_FALLBACK) – nie ein leeres Feld.

    Zahlen der Aufspür-Arten: Enum.MinimapTrackingFilter laut Blizzard_APIDocumentationGenerated/
    MinimapConstantsDocumentation.lua (Zweig forever); der Client nennt sie selbst, die Zahlen sind nur der Rückfall.

      Icons.DEF[schlüssel] = { track = Art, atlas = Name | { … }, file = Pfad | { … }, crop, spell = Zauber-ID }
      Icons.Spec(def) → Angabe für Core.Menu.IconMarkup (Funktion, rechnet beim Bau des Menüs)
      Icons.For(schlüssel) → Angabe oder nil; Icons.Tracking(art) → { file, crop } | nil (Blizzards Bild)
      Icons.Apply(eintrag, schlüssel) → eintrag; Icons.Root(root, schlüssel) → Hülle (Core.Menu.IconRoot): Symbol als
      Vorgabe für jeden Eintrag eines Bausteins, Hilfszeilen (Titelzeilen) mit dem Hinweis-Symbol „info“
]]
local Icons = {}
ns.Icons = Icons

Icons.FILTER = {
    Auctioneer = 1, Banker = 2, Battlemaster = 4, TaxiNode = 8, VenderFood = 16, Innkeeper = 32, Mailbox = 64,
    TrainerProfession = 128, VendorReagent = 256, Repair = 512, Stablemaster = 2048, TrainerClass = 8388608,
}

-- Blizzards Minikarten-Symbole als Rückfall, wenn der Client die Art im Menü „Aufspüren“ nicht führt
local TRACK = "Interface\\Minimap\\Tracking\\"
Icons.TRACK_FILE = {
    Auctioneer = TRACK .. "Auctioneer", Banker = TRACK .. "Banker", Battlemaster = TRACK .. "BattleMaster",
    TaxiNode = TRACK .. "FlightMaster", VenderFood = TRACK .. "Food", Innkeeper = TRACK .. "Innkeeper",
    Mailbox = TRACK .. "Mailbox", TrainerProfession = TRACK .. "Profession", VendorReagent = TRACK .. "Reagents",
    Repair = TRACK .. "Repair", Stablemaster = TRACK .. "StableMaster", TrainerClass = TRACK .. "Class",
}

local I = "Interface\\Icons\\"

-- Ein Eintrag je Knoten des Baums (Tree.lua: Gruppen-id bzw. Schalter) und je Eintrag der Menüs (MapButton.lua,
-- Tracking.lua). Fehlt ein Blatt, nimmt Tree.Icon das Symbol seiner Gruppe.
Icons.DEF = {
    -- Baum: oberste Ebene
    all = { atlas = "Waypoint-MapPin-Tracked", file = I .. "INV_Misc_Map_01" },
    town = { track = "Innkeeper" },
    gather = { file = I .. "INV_Pick_02" },
    discover = { atlas = "VignetteKill", file = I .. "INV_Misc_Spyglass_03" },
    journey = { track = "TaxiNode" },
    own = { atlas = "Waypoint-MapPin-Tracked", file = I .. "INV_Misc_Map_01" },
    -- Dienste in der Stadt
    trainers = { track = "TrainerClass" },
    trainerClass = { track = "TrainerClass" },
    trainerPet = { track = "Stablemaster" },
    trainerProf = { track = "TrainerProfession" },
    trainerOther = { track = "TrainerClass" },
    vendors = { track = "VenderFood" },
    vendorTargets = { track = "VenderFood" },
    repairTargets = { track = "Repair" },
    recipes = { file = { I .. "INV_Scroll_03", I .. "INV_Misc_Note_01" } },
    recipeVendorPins = { track = "VenderFood" },
    recipeTrainerPins = { track = "TrainerProfession" },
    -- Sammeln
    gatherHerb = { atlas = "professions_tracking_herb", file = I .. "Trade_Herbalism" },
    gatherOre = { atlas = "professions_tracking_ore", file = I .. "Trade_Mining" },
    gatherFish = { atlas = "professions_tracking_fish", file = I .. "Trade_Fishing" },
    gatherMini = { file = { I .. "INV_Misc_Map_01" } },
    gatherMiniHerb = { atlas = "professions_tracking_herb", file = I .. "Trade_Herbalism" },
    gatherMiniOre = { atlas = "professions_tracking_ore", file = I .. "Trade_Mining" },
    gatherMiniFish = { atlas = "professions_tracking_fish", file = I .. "Trade_Fishing" },
    gatherColor = { file = I .. "INV_Misc_Gem_Variety_01" },
    route = { file = I .. "Ability_Tracking" },
    -- seit den Funden des code-reviewers vom 17.11.2026 je ein eigenes Symbol: „Wo am dichtesten?“, „Nur bei aktiver
    -- Suche“ (Blizzards Lupe der Suchfelder), „Nur, was ich abbauen kann“ (Spitzhacke wie „Sammeln“) – seit dem
    -- 19.11.2026 der Eintrag „Rot – noch nicht abbaubar“ im Filter „Nach Farbe“ (Nr. 88 der Einstellungs-Prüfung)
    gatherDense = { file = I .. "Ability_Hunter_Pathfinding" },
    gatherMiniSearch = { atlas = "common-search-magnifyingglass", file = "Interface\\Common\\UI-Searchbox-Icon" },
    gatherColorRed = { file = I .. "INV_Pick_02" },
    -- Entdecken
    explorer = { file = I .. "INV_Misc_Spyglass_03" },
    gatherChest = { atlas = "VignetteLoot", file = I .. "INV_Box_02" },
    gatherMiniChest = { atlas = "VignetteLoot", file = I .. "INV_Box_02" },
    rarePins = { atlas = "VignetteKill", file = I .. "Ability_Hunter_MarkedForDeath" },
    bookTargets = { file = I .. "INV_Misc_Book_09" },
    bookPins = { file = I .. "INV_Misc_Book_09" },
    questie = { file = { "Interface\\GossipFrame\\AvailableQuestIcon", I .. "INV_Misc_Book_08" } },
    questieRares = { atlas = "VignetteKill", file = I .. "Ability_Hunter_MarkedForDeath" },
    questieHerbs = { atlas = "professions_tracking_herb", file = I .. "Trade_Herbalism" },     -- wie gatherHerb
    questieOre = { atlas = "professions_tracking_ore", file = I .. "Trade_Mining" },          -- wie gatherOre
    -- Reise
    travel = { track = "TaxiNode" },
    flightMissing = { track = "TaxiNode" },
    dungeons = { atlas = "Dungeon", file = I .. "INV_Misc_Key_03" },
    -- Eigene Wegpunkte und Kartenhilfen
    wayRecent = { atlas = "Waypoint-MapPin-Tracked", file = I .. "INV_Misc_Map_01" },
    mapCoords = { file = I .. "INV_Misc_Spyglass_02" },
    -- Einträge der Menüs (MapButton.lua, Tracking.lua), die keine Baum-Knoten sind
    menuEnter = { atlas = "Waypoint-MapPin-Untracked", file = I .. "INV_Misc_Map_01" },
    menuHere = { file = I .. "Ability_Tracking" },
    menuClear = { file = { "Interface\\Buttons\\UI-GroupLoot-Pass-Up", I .. "INV_Misc_QuestionMark" } },
    menuLink = { file = I .. "INV_Letter_15" },
    menuZones = { file = I .. "INV_Misc_Map02" },
    menuTree = { file = I .. "INV_Misc_Map_01" },
    menuMinimap = { file = I .. "INV_Misc_Map02" },
    -- „Teilweise wiederherstellen“ (Blizzards Pfeil zum Neuladen), Hilfszeilen (Blizzards „i“ der Hilfe-Knöpfe) und der
    -- Schalter „Mit Blizzards Aufspüren koppeln“ (Blizzards Bild des Knopfs „Aufspüren“) – Funde des code-reviewers und
    -- Antwort des Nutzers vom 17.11.2026
    menuRestore = { file = "Interface\\Buttons\\UI-RefreshButton" },
    info = { file = "Interface\\Common\\help-i" },
    couple = { atlas = "ui-hud-minimap-tracking-up", file = "Interface\\Minimap\\Tracking\\None" },
}

local cache = {}

local function FilterID(name)
    local enum = rawget(_G, "Enum")
    local filters = type(enum) == "table" and Core.Peek(enum, "MinimapTrackingFilter") or nil
    return Core.Num(Core.Peek(filters, name)) or Icons.FILTER[name]
end
Icons.FilterID = FilterID

-- Blizzards Bild der Aufspür-Art aus dem Client → { file, crop } | nil. Gesperrte Antworten zählen als „keine“.
function Icons.Tracking(name)
    if cache[name] ~= nil then return cache[name] or nil end
    local api = rawget(_G, "C_Minimap")
    local want = FilterID(name)
    local found = false
    if want and type(api) == "table" and type(api.GetNumTrackingTypes) == "function"
        and type(api.GetTrackingInfo) == "function" and type(api.GetTrackingFilter) == "function" then
        local count = Core.Num(Core.Call(api.GetNumTrackingTypes)) or 0
        for index = 1, count do
            local filter = Core.Call(api.GetTrackingFilter, index)
            if not Core.IsSecret(filter) and type(filter) == "table" and Core.Num(Core.Peek(filter, "filterID")) == want then
                local info = Core.Call(api.GetTrackingInfo, index)
                local texture = not Core.IsSecret(info) and type(info) == "table" and Core.Plain(Core.Peek(info, "texture")) or nil
                if (type(texture) == "number" and texture > 0) or (type(texture) == "string" and texture ~= "") then
                    found = { file = texture, crop = Core.Plain(Core.Peek(info, "type")) == "spell" }
                end
                break
            end
        end
    end
    cache[name] = found
    return found or nil
end

function Icons.ForgetTracking() cache = {} end

-- Zauber- und Gegenstandssymbole (Interface\Icons\…, Datei-IDs von Zaubern) bekommen den abgeschnittenen Rand wie
-- Blizzards Zauber-Arten im Menü „Aufspüren“; Blizzards Minikarten-Symbole nicht.
local function Crops(file)
    return type(file) == "string" and file:lower():find("^interface\\icons\\") ~= nil
end

-- Angabe für Core.Menu.IconMarkup: Blizzards Bild der Aufspür-Art zuerst, dann Atlas, dann die erste Datei, die der
-- Client kennt, dann der Berufszauber; ohne alles bleibt ezCores Rückfall.
function Icons.Spec(def)
    if type(def) ~= "table" then return nil end
    return function()
        local tracked = def.track and Icons.Tracking(def.track) or nil
        if tracked then return { atlas = def.atlas, file = tracked.file, crop = tracked.crop } end
        local files = {}
        if def.track and Icons.TRACK_FILE[def.track] then files[#files + 1] = Icons.TRACK_FILE[def.track] end
        for _, f in ipairs(type(def.file) == "table" and def.file or { def.file }) do files[#files + 1] = f end
        for _, f in ipairs(files) do
            if type(f) == "string" and Core.KnownFile(f) then
                return { atlas = def.atlas, file = f, crop = def.crop or Crops(f) }
            end
        end
        if def.spell and Core.Spells and Core.Spells.Icon then
            local ok, icon = pcall(Core.Spells.Icon, def.spell)
            if ok and not Core.IsSecret(icon) and icon then return { atlas = def.atlas, file = icon, crop = true } end
        end
        return { atlas = def.atlas }
    end
end

function Icons.For(key)
    return Icons.Spec(Icons.DEF[key])
end

-- Symbol eines Berufs über seinen Zauber (Kennung wie in ezCores Berufsliste, z. B. „herbalism“) → Angabe oder nil.
-- Seit dem Fund des code-reviewers vom 17.11.2026 aus ezCore (Core.Menu.ProfessionIcon), hier nur weitergereicht.
function Icons.Profession(key)
    local fn = Core.Menu.ProfessionIcon
    return type(fn) == "function" and fn(key) or nil
end

-- Berufslehrer je Titel („Schneiderlehrer“, „Herbalism Trainer“): Symbol des Berufs, den der Titel nennt – auch über
-- den Wortstamm und für alle Berufe, nicht nur eigene (ezCores Core.Menu.ProfessionIconOfTitle; Fund des
-- code-reviewers vom 17.11.2026). → Angabe oder nil (dann das Symbol der Gruppe)
function Icons.ProfessionOfTitle(title)
    local fn = Core.Menu.ProfessionIconOfTitle
    if type(fn) ~= "function" then return nil end
    return (fn(title))
end

function Icons.Apply(entry, key)
    local spec = type(key) == "function" and key or Icons.For(key)
    if not spec or type(Core.Menu.Icon) ~= "function" then return entry end
    return Core.Menu.Icon(entry, spec)
end

-- Hülle um root: Symbol als Vorgabe für jeden Eintrag, den ein Baustein direkt anlegt; Hilfszeilen mit „info“
-- (ezCores Core.Menu.IconRoot). Ohne Symbol → root unverändert.
function Icons.Root(root, key)
    local spec = type(key) == "function" and key or (key and Icons.For(key))
    if not spec or type(Core.Menu.IconRoot) ~= "function" then return root end
    return Core.Menu.IconRoot(root, spec, { titleIcon = Icons.For("info") })
end

-- Blizzards Arten können sich mit gelernten Such-Zaubern ändern
ns.On("SPELLS_CHANGED", function() Icons.ForgetTracking() end)
