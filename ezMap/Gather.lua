local _, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Sammel-Fundorte auf Blizzards Weltkarte (SAM-10 bis SAM-16, Welle 14; Ablösung von GatherMate nach der
    Entscheidung des Nutzers vom 14.11.2026).

    Daten: nur ezCores Dienst der eigenen Fundorte (Core.Gathering.Nodes, Near, Visible, Visibility, OwnRank, Required,
    SkillText, JustGathered, Forget) und die Fach-Fassade Core.Drops (Ertrag; Wert je Ernte über Drops.Worth). ezMap liest nie
    die Tabellen selbst und speichert keine Fundorte – nur seine Schalter und die Liste ausgeblendeter Vorkommen
    (ezMapDB.gatherHidden). Gezeichnet wird über ezCores Punkteschicht (Core.MapPins, Anbieter „ezMap.gather“): ein
    Rahmen als Kind von Blizzards Kartenfläche, Punkte als Texturen, ein Griff-Knopf für Tooltip, Klick und Menü. Kein
    eigenes Fenster, kein Eintrag in FENSTER (tools/lint.lua), nichts in Blizzards Kartentabellen (Leitlinien 1 und 5).

      SAM-10  Punkte der gezeigten Karte (Zone und darunter; Welt- und Kontinentkarten zeigen keine), Symbol = Bild des
              Hauptertrags aus dem Client (Core.ItemIcon), sonst das Bild der Suche bzw. des Berufs (Core.Spells.Icon)
      SAM-12  Abschnitt „ezMap – Sammeln“ in Blizzards Kartenfilter (Menu.ModifyMenu an MENU_WORLD_MAP_TRACKING, einmal
              angemeldet): Schalter je Art (eigene Werte in ezMapDB.settings, Blizzards Filtertabelle bleibt unberührt),
              darunter je Art „Wann zeigen“ (Modus aus ezCore: immer, mit Beruf, bei aktiver Suche; „nie“ seit dem
              19.11.2026 nur über den Haken der Art) und die einzelnen Vorkommen der Karte. Derselbe Abschnitt im ezMap-Kartenknopf
              und auf der Einstellungsseite (Abschnitt „Sammeln“, mit Größe, Deckkraft und Abdunkeln). Ausgeblendetes
              erfasst ezCore weiter (ezMap filtert nur die Anzeige). Seit dem Spielbefund vom 18.11.2026 („zur map,
              das muss ein button sein, sinnvoll aufgeteilt“) steht ezMap in Blizzards Kartenfilter nur noch mit dem
              Schalter mapFilterSection (ab Werk aus) oder bei abgeschaltetem ezMap-Knopf (Gather.FilterWanted);
              sonst ist der ezMap-Knopf der eine Ort.
      SAM-13  Tooltip am Punkt: Name (je Sprache gemerkt, sonst Name des Hauptertrags), Art, „n× geerntet, zuletzt
              vor …“, üblicher Ertrag, Rang (G.SkillText; seit Welle 27, F4 b, auch an Kisten – Schlossknacken, nur
              wenn bekannt – und an Schwärmen, Wortlaut samt Quelle aus ezCore), Wert je Ernte (seit Welle 24 aus ezCores
              Core.Drops.Worth/WorthLines, V2: erst ab Drops.WORTH_MIN Ernten, mit Grundlage und Preisquelle;
              seit dem 19.11.2026 immer, Nr. 44), Quelle („bei dir“ bzw. „aus deiner Sicherung“ für src = "backup", SAM-19;
              „aus Beiträgen (n Spieler), Stand Build x“ für src = "ship")
      ezData  Fundorte aus Beiträgen anderer Spieler (22.11.2026): Haken gatherShip unter „Sammeln“ (ab Werk an,
              Nachschlage-Wissen; im Baum nur, solange ezData geladen ist). Gather.WithShip ergänzt je Art die Punkte
              aus Core.Gathering.ShipNodes, ohne Doppelpunkte neben eigenen Stellen (SHIP_TWIN_YARDS); ihr Menü hat
              kein „Vergessen“ (es sind keine eigenen Stellen).
      SAM-14  Klick auf den Griff setzt Blizzards Markierung (ns.Way.Set); Rechtsklick: „Nächster Fundort von …“,
              ausblenden, vergessen (Rückfrage, Core.Gathering.Forget); Schnittstelle ezCore.API("ezMap").ShowGather
      SAM-15  eben geerntete Stellen (Sitzungsliste aus ezCore, Core.Gathering.JustGathered) für gatherDim Minuten
              abgedunkelt
      SAM-16  Rücksicht (Leitlinie 9): läuft GatherMate2 oder Gatherer Reforged (Core.WhoHandles("gatherPins")),
              zeichnet ezMap nicht, nennt das Addon im Menü und in /ezmap status und bietet den Haken „Fundorte trotz GatherMate2/Gatherer zeigen“ (gatherOverride); ezCore
              zählt still weiter. Leere Karte: ein ehrlicher Satz im Menü. Kisten ab Werk aus (Entdecker-Wissen).

    Kisten sind Entdecker-Wissen (Leitlinie 11): ezCore zeigt sie nur mit „Entdecker-Wissen“; ezMaps eigener Schalter
    „Kisten“ (ab Werk aus) ist derselbe ausdrückliche Wunsch wie bei den Bibliotheksbüchern (bookTargets) – ist er an,
    fragt ezMap ezCore mit filter.explorer = true (Kisten haben seit dem 19.11.2026 nur noch den Modus „immer“).
    Seit Welle 15 (SAM-11): dieselben Punkte auf der Minikarte über das Feld minikarte des Anbieters – ezCore setzt sie
    in Reichweite (Core.MapPins, Sichtradius aus C_Minimap.GetViewRadius), ezMap liefert sie nach eigenen Haken je
    Art (gatherMini*, Gruppe „Auf der Minikarte“ im Baum) und ezCores Modus der Fläche „minimap“
    (Core.Gathering.Visible(art, "minimap")); Größe und Deckkraft eigens (gatherMiniSize, gatherMiniAlpha), eben
    Geerntetes auch dort abgedunkelt. Einträge im Abschnitt „ezMap“ des Menüs „Aufspüren“ (Gather.AddMiniMenu); kennt
    der Client den Sichtradius nicht, stehen sie ausgegraut mit Erklärung.
    Seit Teilwelle 15b (Wunsch des Nutzers vom 15.11.2026 abends, Wortlaut im ROADMAP-Index): Farbe je Fundort für den
    eigenen Charakter aus ezCore (Core.Gathering.SkillUp – nötiger Wert des Vorkommens und eigene Fertigkeit,
    berechnet). Filtergruppe „Nach Farbe“ im Baum unter „Sammeln“ (gatherColor*: orange, gelb, grün, grau, rot,
    unbekannt; Tree-Feld filter) – sie siebt Weltkarte, Minikarte und Routen (Gather.ColorPass), nicht den Filter aus
    ShowGather und nicht „Wo am dichtesten?“. Rote Vorkommen (noch nicht sammelbar) stehen rötlich und blasser da; sie
    blendet „Rot – noch nicht abbaubar“ aus (seit dem 19.11.2026, vorher der Haken „Nur, was ich abbauen kann“).
    Kisten und Angelplätze haben keine Farbe für den Filter und gehen immer durch. Der Tooltip nennt
    „Fertigkeitspunkt: sicher / etwa n % / nie (grau ab Fertigkeit x)“ in der Farbe samt Quelle (ezCore).
    Seit dem 18.11.2026 (Wunsch des Nutzers, wörtlich: „ezgather: wenn ich mich den ressourcen näher muss unsere
    markierung verschwinden um zu wissen ob die ressource wirklich da ist (markierung verdeckt originale
    ressourcenmarkierung)“): Auf der Minikarte fehlt der Punkt eines Fundorts (und der nächste Punkt der Sammel-Route,
    seit dem Spieltest vom 19.11.2026 ihr einziger Punkt dort), solange der Spieler
    näher als gatherHideNearYards (10 bis 100, ab Werk 40; 0 = aus, seit dem 19.11.2026 ohne eigenen Haken) daran
    steht. Gerechnet
    wird in ezCores Punkteschicht (Feld hideNear des Anbieters, Gather.HideNear), die die Minikarte ohnehin nach jeder
    Bewegung neu setzt: kein eigener Ticker, keine Arbeit im Stand. Ohne eigene Position (Instanz, gesperrter Wert)
    zeichnet ezCore auf der Minikarte gar nichts. Die Weltkarte bleibt: Blizzard zeigt dort keine Vorkommen, die ein
    Punkt verdecken könnte.
    Routen (Route.lua) und die übrigen Fundorte (Eingänge, seltene Gegner, Bücher) stehen in eigenen Dateien.
]]
local Gather = {}
ns.Gather = Gather

Gather.PROVIDER = "ezMap.gather"
Gather.TAG = "MENU_WORLD_MAP_TRACKING"
Gather.KINDS = { "herb", "ore", "fish", "chest" }
Gather.KEY = { herb = "gatherHerb", ore = "gatherOre", fish = "gatherFish", chest = "gatherChest" }
-- Haken je Art für die Minikarte (SAM-11)
Gather.MINI_KEY = { herb = "gatherMiniHerb", ore = "gatherMiniOre", fish = "gatherMiniFish", chest = "gatherMiniChest" }
-- Modi je Art (ezCore G.VISIBILITY_MODES): Angeln hat keine Suche, Kisten keinen Beruf. Ohne „Nie“ seit der
-- Einstellungs-Prüfung vom 19.11.2026 (Nr. 86, 87; Zustimmung des Nutzers „Ja, alle umsetzen“): „Nie“ tat dasselbe wie
-- der abgewählte Haken der Art – ausblenden geht nur noch über den Haken. Kisten haben damit nur noch „Immer“, ihr
-- Auswahlfeld entfällt (Nr. 2 und 87). Ein gespeichertes „Nie“ stellt Gather.NormalizeModes um.
Gather.MODES = {
    herb = { "always", "profession", "tracking" },
    ore = { "always", "profession", "tracking" },
    fish = { "always", "profession" },
    chest = { "always" },
}
-- Ersatz für ein gespeichertes „Nie“ je Fläche und Art: ezCores zweiter Standard (Weltkarte „Mit Beruf“, Minikarte
-- „Bei aktiver Suche“), Angeln auf der Minikarte „Mit Beruf“ (Nr. 99: ezCores Standard dort war „Nie“, der Haken aber
-- an – alles sah nach an aus, und nichts erschien), Kisten „Immer“
Gather.NEVER_FALLBACK = {
    map = { herb = "profession", ore = "profession", fish = "profession", chest = "always" },
    minimap = { herb = "tracking", ore = "tracking", fish = "profession", chest = "always" },
}
-- Hat eine Art mehr als einen Modus? Sonst kein „Wann zeigen“ (Kisten: nur „Immer“)
function Gather.HasModes(kind)
    return #(Gather.MODES[kind] or {}) > 1
end
Gather.MIN_MAP_TYPE = 3     -- Zone (3), Dungeon (4), Kleinkarte (5), Waise (6); Welt und Kontinent nicht
Gather.DIM = 0.45           -- Helligkeit eines eben geernteten Punkts (Farbe und Faktor auf die Deckkraft)
Gather.NEAR_YARDS = 5       -- so nah am Spieler gilt ein Fundort als „dieser“ (für „Nächster Fundort“)
-- Minikarte: Punkte in der Nähe ausblenden (Schieber gatherHideNearYards, 0 = aus; Wunsch des Nutzers vom 18.11.2026),
-- Bereich des Schiebers
Gather.HIDE_NEAR_MIN, Gather.HIDE_NEAR_MAX, Gather.HIDE_NEAR_DEFAULT = 10, 100, 40
Gather.YIELD_LINES = 3      -- so viele Gegenstände nennt die Zeile „Üblicher Ertrag“
-- Rückfall-Bilder je Art, wenn weder Ertrag noch Zauberbild bekannt sind: Dateien des Clients (kein fremdes Symbolpaket)
Gather.KIND_ICON = { herb = "Interface\\Icons\\INV_Misc_Herb_07", ore = "Interface\\Icons\\INV_Ore_Copper_01",
    fish = "Interface\\Icons\\Trade_Fishing", chest = "Interface\\Icons\\INV_Box_02" }

local function GatherAPI()
    local G = Core.Gathering
    if type(G) == "table" and type(G.Nodes) == "function" then return G end
    return nil
end

local function Pins()
    local P = Core.MapPins
    if type(P) == "table" and type(P.AddProvider) == "function" then return P end
    return nil
end

local function KindLabel(kind)
    return Core.L["GATHER_KIND_" .. tostring(kind)] or tostring(kind)
end
Gather.KindLabel = KindLabel

-- Wünscht der Spieler Kisten (Entdecker-Wissen, Leitlinie 11)? ezMaps Haken „Kisten“ oder ezCores Schalter
-- „Entdecker-Wissen“ (DB.Explorer). Gilt für ShowGather; die Karte selbst zeigt Kisten nur mit ezMaps Haken.
local function ChestsWanted()
    if ns.Enabled("gatherChest") then return true end
    local DB = Core.DB
    return DB and type(DB.Explorer) == "function" and DB.Explorer() == true or false
end
Gather.ChestsWanted = ChestsWanted

local function Hidden()
    local db = ns.db
    if type(db) ~= "table" then return {} end
    if type(db.gatherHidden) ~= "table" then db.gatherHidden = {} end
    return db.gatherHidden
end

-- Schlüssel eines Vorkommens in der Ausblend-Liste: Art und ID (Angeln: Gebiet; Kräuter, Erze, Kisten: Objekt)
function Gather.HiddenKey(node)
    return tostring(node.kind) .. ":" .. tostring(node.id)
end

function Gather.IsHidden(node)
    return Hidden()[Gather.HiddenKey(node)] == true
end

-- noRefresh: die Karte nicht neu zeichnen (viele Vorkommen auf einmal; der Aufrufer zeichnet danach einmal)
function Gather.SetHidden(node, hide, noRefresh)
    Hidden()[Gather.HiddenKey(node)] = hide and true or nil
    if not noRefresh then Gather.Refresh() end
end

---------------------------------------------------------------------------
-- Rücksicht und Sichtbarkeit
---------------------------------------------------------------------------

-- Wer Sammel-Fundorte schon zeichnet (reine Auskunft, zählt nicht als „gewichen“) → Name oder nil
function Gather.Other()
    local ask = Core.WhoHandlesInfo or Core.WhoHandles
    if type(ask) ~= "function" then return nil end
    return (ask("gatherPins"))
end

-- Weicht ezMap gerade? (zählt bei ezCore als „gewichen“) → Name oder nil; der Haken „Fundorte trotz GatherMate2/Gatherer zeigen“ (gatherOverride) hebt es auf
function Gather.Yields()
    if ns.Enabled("gatherOverride") then return nil end
    if type(Core.WhoHandles) ~= "function" then return nil end
    return (Core.WhoHandles("gatherPins", "ezMap"))
end

-- Nur, was du abbauen kannst? Seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 88) ist das der Eintrag „Rot – noch
-- nicht abbaubar“ im Filter „Nach Farbe“ (gatherColorRed, ab Werk an): abgewählt blendet er Kräuter und Erze über deinem
-- Rang aus – vorher der eigene Haken „Nur, was ich abbauen kann“ (gatherSkillOnly, Übernahme in ns.MigrateSettings1911)
function Gather.SkillOnly()
    return not ns.Enabled("gatherColorRed")
end

-- „Rot“ abgewählt und ohne den Beruf: dann kann der Charakter keines dieser Vorkommen abbauen
-- (G.OwnRank → nil heißt „kein Beruf“, 0 heißt „Rang unbekannt“ und blendet nichts aus)
local function SkillBlocked(G, kind)
    if not (Gather.SkillOnly() and (kind == "herb" or kind == "ore")) then return false end
    return type(G.OwnRank) == "function" and G.OwnRank(kind) == nil
end

-- Dasselbe für die Sammel-Route (Route.Collect): ganze Art gesperrt? (Spielbefund vom 19.11.2026, Bild 37: „Nur, was
-- ich abbauen kann“ wirkte nur auf die Punkte, nicht auf die Route)
function Gather.SkillBlockedKind(kind)
    local G = GatherAPI()
    if not G then return false end
    return SkillBlocked(G, kind) == true
end

-- Sichtbarkeit nach dem Ersatzmodus für ein noch nicht umgestelltes „Nie“ (wie ezCores G.Visible mit dem Modus aus
-- Gather.NEVER_FALLBACK) → true oder false, Grund
local function FallbackVisible(G, kind, surface)
    local mode = Gather.NEVER_FALLBACK[surface][kind]
    if mode == "tracking" and type(G.TRACKING_SPELLS) == "table" and G.TRACKING_SPELLS[kind]
        and type(G.Tracking) == "function" then
        return G.Tracking(kind) and true or false, "tracking"
    end
    if mode ~= "always" and type(G.HasProfession) == "function" then
        return G.HasProfession(kind) and true or false, "profession"
    end
    return true
end

-- Darf die Art auf der Weltkarte (surface "map", Standard) bzw. der Minikarte ("minimap") erscheinen? → true oder
-- false, Grund ("off" | "profession" | "tracking" | "explorer" | "noskill" | "nocore" | "kind"; ein noch nicht
-- umgestelltes „Nie“ in ezCore zählt wie sein Ersatzmodus, FallbackVisible)
function Gather.KindState(kind, surface)
    local G = GatherAPI()
    if not G then return false, "nocore" end
    surface = surface == "minimap" and "minimap" or "map"
    local key = (surface == "minimap" and Gather.MINI_KEY or Gather.KEY)[kind]
    if not key then return false, "kind" end
    if not ns.Enabled(key) then return false, "off" end
    if type(G.Visible) ~= "function" then
        if SkillBlocked(G, kind) then return false, "noskill" end
        return true
    end
    local ok, why = G.Visible(kind, surface)
    if not ok and why == "never" then ok, why = FallbackVisible(G, kind, surface) end
    if not ok and why == "explorer" then
        -- Kisten: der eigene Schalter ist der ausdrückliche Wunsch (wie bookTargets)
        return true
    end
    if ok and SkillBlocked(G, kind) then return false, "noskill" end
    return ok and true or false, why
end

-- Modus je Art und Fläche aus ezCore (surface "map", Standard, oder "minimap"). Ein „Nie“, das ezMap noch nicht
-- umgestellt hat (etwa nach dem Zurücksetzen von ezCores Schaltern, das nichts meldet), gilt als sein Ersatz aus
-- Gather.NEVER_FALLBACK – „Nie“ steht in keiner Auswahl mehr (Gegenprüfung des Pakets, Nr. 99)
function Gather.Mode(kind, surface)
    local G = GatherAPI()
    surface = surface == "minimap" and "minimap" or "map"
    local mode = G and type(G.Visibility) == "function" and G.Visibility(kind, surface) or nil
    if mode == "never" then return Gather.NEVER_FALLBACK[surface][kind] or mode end
    return mode
end

function Gather.SetMode(kind, mode, surface)
    local G = GatherAPI()
    if not (G and type(G.SetVisibility) == "function") then return false end
    local ok = G.SetVisibility(kind, surface or "map", mode)
    Gather.Refresh()
    return ok
end

-- Gespeichertes „Nie“ in ezCores Modus umstellen (Einstellungs-Prüfung vom 19.11.2026, Nr. 86, 87, 99; ezCore kennt
-- „Nie“ weiter, ezMap bietet es nicht mehr an). Ein „Nie“ war eine Wahl des Spielers – gespeichert, später eingespielt
-- (Sicherung, „Alles übernehmen“) oder in ezCore gewählt: der Haken der Art geht aus, der Modus auf den Ersatz aus
-- Gather.NEVER_FALLBACK – so bleibt unsichtbar, was unsichtbar sein sollte, und Haken und Regel passen zusammen
-- (Gegenprüfung des Pakets: vorher nur beim ersten Mal, ein später eingespieltes „Nie“ wurde stillschweigend sichtbar).
-- Ausnahme Angeln auf der Minikarte: dort ist „Nie“ ezCores Standard (Nr. 99; auch nach einem Zurücksetzen dort), der
-- Haken bleibt, wie er ist, und die Regel wird „Mit Beruf“. → Zahl der Umstellungen
local function KindOff(key)
    if type(ns.S) ~= "table" or ns.S[key] == false then return end
    local setting = type(ns.settingObjects) == "table" and ns.settingObjects[key] or nil
    if not (setting and pcall(setting.SetValue, setting, false) and ns.S[key] == false) then ns.SetSetting(key, false) end
end

function Gather.NormalizeModes()
    local G = GatherAPI()
    if Gather.normalizing or not (G and type(G.Visibility) == "function" and type(G.SetVisibility) == "function") then
        return 0
    end
    local todo = {}
    for _, surface in ipairs({ "map", "minimap" }) do
        for _, kind in ipairs(Gather.KINDS) do
            if G.Visibility(kind, surface) == "never" then todo[#todo + 1] = { kind, surface } end
        end
    end
    Gather.normalizing = true     -- SetVisibility meldet GATHERING_VISIBILITY; der Zuhörer ruft hierher zurück
    for _, entry in ipairs(todo) do
        local kind, surface = entry[1], entry[2]
        Core.Try("ezMap", "Gather.NormalizeModes", G.SetVisibility, kind, surface, Gather.NEVER_FALLBACK[surface][kind])
        if not (surface == "minimap" and kind == "fish") then
            Core.Try("ezMap", "Gather.NormalizeModes", KindOff, (surface == "minimap" and Gather.MINI_KEY or Gather.KEY)[kind])
        end
    end
    Gather.normalizing = false
    return #todo
end

local function FilterFor(kind)
    local G = GatherAPI()
    local filter = { kind = kind }
    if kind == "chest" then filter.explorer = true end
    if Gather.SkillOnly() and (kind == "herb" or kind == "ore") and G and type(G.OwnRank) == "function" then
        -- Rang samt Bonus: dagegen prüft der Client (ezCore, Rest f aus dem Review zu kern/sammel-fertigkeit)
        local rank = ns.Num(G.OwnRank(kind, true))
        if rank and rank > 0 then filter.skill = rank end
    end
    return filter
end

Gather.FilterFor = FilterFor

---------------------------------------------------------------------------
-- Nach Farbe (Teilwelle 15b): Chance auf einen Fertigkeitspunkt je Fundort, Regel und Text aus ezCore
---------------------------------------------------------------------------

Gather.COLORS = { "orange", "yellow", "green", "gray", "unknown" }
Gather.COLOR_KEY = { orange = "gatherColorOrange", yellow = "gatherColorYellow", green = "gatherColorGreen",
    gray = "gatherColorGray", unknown = "gatherColorUnknown" }
Gather.RED_TINT = { 1, 0.35, 0.35 }   -- Punkte, die du noch nicht sammeln kannst: rötlich …
Gather.RED_ALPHA = 0.6                -- … und blasser (Faktor auf die Deckkraft)

-- Eigene Fertigkeit je Sammelart, einmal je Aufbau gelesen (G.OwnRank fragt den Client) → { art = Rang | false,
-- effective = { art = Rang samt Bonus } } (der Bonus entscheidet in ezCore „kannst du es?“, G.SkillUp)
function Gather.Ranks()
    local G = GatherAPI()
    local out = { effective = {} }
    for _, kind in ipairs({ "herb", "ore", "fish" }) do
        local rank = G and type(G.OwnRank) == "function" and G.OwnRank(kind) or nil
        out[kind] = rank == nil and false or rank
        out.effective[kind] = rank ~= nil and G.OwnRank(kind, true) or nil
    end
    return out
end

-- Farbe eines Fundorts für den eigenen Charakter → "orange" | "yellow" | "green" | "gray" | "red" | "unknown" oder nil
-- (Kisten; ezCore ohne Farbdienst). ranks aus Gather.Ranks (sonst fragt ezCore selbst).
function Gather.ColorOf(node, ranks)
    local G = GatherAPI()
    if not (G and type(G.SkillUp) == "function" and type(node) == "table") then return nil end
    local rank = nil
    if type(ranks) == "table" and ranks[node.kind] ~= nil then
        rank = ranks[node.kind]
        if rank == false then
            -- Beruf fehlt: Kräuter und Erze kannst du nicht sammeln (wie ezCores Grund „noprof“)
            if node.kind == "herb" or node.kind == "ore" then return "red" end
            rank = nil
        end
    end
    local eff = rank ~= nil and type(ranks.effective) == "table" and ranks.effective[node.kind] or nil
    local info = G.SkillUp(node.id, node.kind, rank, eff)
    return type(info) == "table" and info.color or nil
end

-- Sind alle Farben an? Dann siebt der Filter nichts (und ezMap rechnet keine Farbe dafür)
function Gather.AllColors()
    for _, color in ipairs(Gather.COLORS) do
        if not ns.Enabled(Gather.COLOR_KEY[color]) then return false end
    end
    return true
end

-- Lässt der Filter „Nach Farbe“ den Fundort durch? Kisten (keine Farbe) und rote Vorkommen immer – rot regelt der
-- Eintrag „Rot – noch nicht abbaubar“ über den Rang (Gather.SkillOnly, FilterFor). Angelplätze ebenfalls immer: sie
-- verlangen keinen Wert, ihre Farbe wäre stets „unbekannt“ – wer „Unbekannt“ abwählte, verlor sonst ohne Ankündigung
-- alle Angelplätze (Einstellungs-Prüfung vom 19.11.2026, Abschnitt 4; ausblenden über den Haken „Angelplätze“).
-- color: schon bekannte Farbe (sonst rechnet ColorOf)
function Gather.ColorPass(node, ranks, color)
    if Gather.AllColors() then return true end
    if type(node) == "table" and node.kind == "fish" then return true end
    color = color or Gather.ColorOf(node, ranks)
    if color == nil or color == "red" then return true end
    local key = Gather.COLOR_KEY[color]
    return key == nil or ns.Enabled(key)
end

-- Karten mit eigenem Gebiet (Zone und darunter)
function Gather.MapAllowed(mapID)
    local info = Core.Map.Info(mapID)
    local mapType = type(info) == "table" and ns.Num(info.mapType) or nil
    return mapType ~= nil and mapType >= Gather.MIN_MAP_TYPE
end

-- Gesetzter Filter aus ShowGather: { item, kind, map } bis die Karte schließt
Gather.focus = nil

function Gather.ClearFocus()
    if Gather.focus then
        Gather.focus = nil
        Gather.Refresh()
    end
end

-- Alle eigenen Fundorte der Karte ohne ezMaps Filter (für den Satz bei leerer Karte) → Anzahl
function Gather.Total(mapID)
    local G = GatherAPI()
    mapID = ns.Num(mapID)
    if not (G and mapID) then return 0 end
    local n = 0
    for _, kind in ipairs(Gather.KINDS) do
        -- Kisten nur mit ezMaps Haken: ohne ihn zählen auch Altbestand-Objekte (ohne obj-Satz, bei ezCore Art
        -- „chest“ ohne Entdecker-Merkmal) nicht mit
        if kind ~= "chest" or ns.Enabled("gatherChest") then
            n = n + #G.Nodes(mapID, { kind = kind, explorer = kind == "chest" or nil })
        end
    end
    return n
end

-- Fundorte, die ezMap auf der Karte mapID zeigt (nach Schaltern, Modus, Rang und Ausblend-Liste) → Liste der Knoten.
-- surface "minimap": nach den Haken und Modi der Minikarte (ohne den Filter aus ShowGather – der gilt der Weltkarte)
function Gather.Shown(mapID, surface)
    local G = GatherAPI()
    mapID = ns.Num(mapID)
    if not (G and mapID) then return {} end
    local out = {}
    local focus = Gather.focus
    if focus and surface ~= "minimap" then return Gather.Find(mapID, focus) end
    local hidden = Hidden()
    local ranks = Gather.Ranks()
    local colors = {}     -- Farbe je Vorkommen (Art und ID), einmal je Aufbau gerechnet
    for _, kind in ipairs(Gather.KINDS) do
        if Gather.KindState(kind, surface) then
            local nodes = G.Nodes(mapID, FilterFor(kind))
            if Gather.ShipWanted() then nodes = Gather.WithShip(nodes, mapID, kind) end
            for _, node in ipairs(nodes) do
                local key = Gather.HiddenKey(node)
                if not hidden[key] then
                    -- Farbe je Fundort (Teilwelle 15b): für den Filter „Nach Farbe“ und die Tönung roter Punkte
                    local color = colors[key]
                    if color == nil then
                        color = Gather.ColorOf(node, ranks) or false
                        colors[key] = color
                    end
                    node.color = color or nil
                    if Gather.ColorPass(node, ranks, node.color) then out[#out + 1] = node end
                end
            end
        end
    end
    return out
end

-- Ist mindestens eine Art auf der Weltkarte eingeschaltet? (Seit dem Baum, Tree.lua, gibt es keinen eigenen
-- Gruppen-Schalter gatherPins mehr: die Gruppe „Sammeln“ ergibt sich aus den Arten; Kisten stehen unter
-- „Entdecker-Wissen“.)
function Gather.AnyKind()
    for _, kind in ipairs(Gather.KINDS) do
        if ns.Enabled(Gather.KEY[kind]) then return true end
    end
    return false
end

-- Zeichnet ezMap auf der Karte? → true oder false, Grund ("off" | "other" | "map" | "nocore")
function Gather.Active(mapID)
    if not (GatherAPI() and Pins()) then return false, "nocore" end
    if not (Gather.AnyKind() or Gather.focus) then return false, "off" end
    if Gather.Yields() then return false, "other" end
    if mapID and not Gather.MapAllowed(mapID) then return false, "map" end
    return true
end

---------------------------------------------------------------------------
-- Ertrag, Name und Symbol je Vorkommen (zwischengespeichert bis GATHERING_CHANGED)
---------------------------------------------------------------------------

local facts = {}

function Gather.ForgetFacts() facts = {} end

local function YieldOf(node)
    local D = Core.Drops
    if not (type(D) == "table" and type(D.Of) == "function") then return nil end
    local ok, total
    if node.stored == "fishing" then
        ok, total = pcall(D.Of, "fishing", node.map, node.id)
    else
        ok, total = pcall(D.Of, "object", node.id)
    end
    return ok and type(total) == "table" and total or nil
end

-- Hauptertrag: der am häufigsten gefundene Gegenstand (bei Gleichstand die kleinere Nummer)
local function MainItem(total)
    local best, bestF
    for itemID, it in pairs(type(total) == "table" and type(total.items) == "table" and total.items or {}) do
        local f = ns.Num(it.f) or 0
        if ns.Num(itemID) and (not bestF or f > bestF or (f == bestF and itemID < best)) then best, bestF = itemID, f end
    end
    return best
end

local function KindIcon(kind)
    local S = Core.Spells
    local G = GatherAPI()
    local spell
    if kind == "fish" then
        spell = S and S.FISHING
    else
        spell = G and type(G.TRACKING_SPELLS) == "table" and G.TRACKING_SPELLS[kind]
    end
    local icon = spell and S and type(S.Icon) == "function" and S.Icon(spell) or nil
    return icon or Gather.KIND_ICON[kind] or Gather.KIND_ICON.chest
end

local function FishAreaName(area)
    local api = rawget(_G, "C_Map")
    local name = api and Core.Plain(Core.Call(api.GetAreaInfo, area))
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- Name eines Objekts: der in ezCores Datenbank für die Sprache des Clients gemerkte, sonst der Name des Hauptertrags,
-- sonst ein in einer anderen Sprache gemerkter (DB.Text fällt auf eine beliebige Sprache zurück). → Name oder nil,
-- endgültig (false: später noch einmal versuchen – der Gegenstand kann noch nicht im Cache des Clients sein)
local function ObjectName(id, main)
    local DB = Core.DB
    local text, loc
    if DB and type(DB.Text) == "function" then text, loc = DB.Text("obj", id) end
    local Keys = DB and DB.Keys
    local own = Keys and type(Keys.Locale) == "function" and Keys.Locale() or nil
    if text and (loc == nil or loc == own) then return text, true end
    local itemName = main and Core.ItemNameByID(main) or nil
    if itemName then return itemName, true end
    return text, main == nil
end

function Gather.Facts(node)
    -- Angeln: Gebiet je Speicherkarte; Objekte gelten überall gleich
    local key = node.stored == "fishing" and ("f|" .. tostring(node.map) .. "|" .. tostring(node.id))
        or ("o|" .. tostring(node.id))
    local hit = facts[key]
    if hit and hit.retry then
        local name, final = ObjectName(node.id, hit.main)
        if name then hit.name = name end
        if final then hit.retry = nil end
    end
    if hit then return hit end
    local total = YieldOf(node)
    local main = MainItem(total)
    local Keys = Core.DB and Core.DB.Keys
    local fallbackItem
    if Keys and type(Keys.GatherOf) == "function" then
        local _, itemID = Keys.GatherOf(node.id)
        fallbackItem = ns.Num(itemID)
    end
    main = main or fallbackItem
    local name, final = nil, true
    if node.stored == "fishing" then
        local area = FishAreaName(node.id)
        name = area and L.GMAP_FISH_NAME:format(area) or L.GMAP_FISH
    else
        name, final = ObjectName(node.id, main)
    end
    hit = { total = total, main = main, name = name or L.GMAP_UNNAMED, retry = not final or nil,
        icon = (main and Core.ItemIcon(main)) or KindIcon(node.kind) }
    facts[key] = hit
    return hit
end

---------------------------------------------------------------------------
-- Eben geerntet (SAM-15)
---------------------------------------------------------------------------

-- Sitzungsliste aus ezCore, nur Einträge jünger als gatherDim Minuten, umgerechnet auf die Karte mapID
local function Recent(mapID)
    local G = GatherAPI()
    local minutes = ns.Num(ns.S and ns.S.gatherDim) or 0
    if not (G and type(G.JustGathered) == "function") or minutes <= 0 then return {} end
    local now, out = Core.Uptime(), {}
    for _, e in ipairs(G.JustGathered()) do
        local age = now - (ns.Num(e.t) or 0)
        if age >= 0 and age <= minutes * 60 then
            local x, y = e.x, e.y
            if x and y and e.map ~= mapID then x, y = Core.Map.PosOn(mapID, e.map, x, y) end
            -- sx, sy: Lage auf der Speicherkarte (Abgleich mit der Stelle wie bei ezCores WasJustGathered)
            out[#out + 1] = { id = e.id, kind = e.kind, map = e.map, x = x, y = y, sx = e.x, sy = e.y, age = age }
        end
    end
    return out
end
Gather.Recent = Recent

local function Yards(mapID)
    local D = Core.Discovery
    if D and type(D.MapYards) == "function" then return D.MapYards(mapID) end
    return nil
end

-- Liegen zwei Stellen auf der Karte mapID im Umkreis yards? Ohne Kartengröße: 1 % der Karte (wie ezCore).
local function Close(mapID, ax, ay, bx, by, yards)
    if not (ax and ay and bx and by) then return false end
    local w, h = Yards(mapID)
    if w and h then return math.sqrt(((ax - bx) * w) ^ 2 + ((ay - by) * h) ^ 2) <= yards end
    return math.abs(ax - bx) < 0.01 and math.abs(ay - by) < 0.01
end
Gather.Close = Close        -- auch für QuestieSpawns.lua (Punkte laut Questie neben eigenen Funden, Paket „Fundorte“)

-- Fundorte aus Beiträgen anderer Spieler (ezData, 22.11.2026): Haken gatherShip, nur solange ezData geladen ist
Gather.SHIP_TWIN_YARDS = 15   -- so nah an einer eigenen Stelle desselben Vorkommens gilt ein Punkt als dieselbe (wie
                              -- QS.TWIN_YARDS: dein Punkt bleibt, der Tooltip nennt deine Quelle)

function Gather.ShipReady()
    local DB = Core.DB
    if not (DB and type(DB.ShipStats) == "function") then return false end
    return DB.ShipStats().state == "loaded"
end

function Gather.ShipWanted() return ns.Enabled("gatherShip") and Gather.ShipReady() end

-- eigene Knoten einer Art und dazu die aus Beiträgen (Core.Gathering.ShipNodes, gleicher Filter), ohne Doppelpunkte:
-- ein Punkt aus Beiträgen im Umkreis SHIP_TWIN_YARDS einer eigenen Stelle desselben Vorkommens fällt weg → Liste
function Gather.WithShip(own, mapID, kind)
    local G = GatherAPI()
    if not (G and type(G.ShipNodes) == "function") then return own end
    -- eigene Stellen je Vorkommen in Zellen von SHIP_TWIN_YARDS (ohne Kartengröße 1 % der Karte, wie Close); x, y
    -- liegen bei beiden schon auf mapID – geprüft werden nur die 3×3 Nachbarzellen
    local w, h = Yards(mapID)
    local cx, cy = 0.01, 0.01
    if w and h and w > 0 and h > 0 then cx, cy = Gather.SHIP_TWIN_YARDS / w, Gather.SHIP_TWIN_YARDS / h end
    local out, cells = {}, {}
    local function Key(id, i, j) return tostring(id) .. "|" .. i .. "|" .. j end
    for n, node in ipairs(own) do
        out[n] = node
        local x, y = ns.Num(node.x), ns.Num(node.y)
        if x and y then
            local key = Key(node.id, math.floor(x / cx), math.floor(y / cy))
            cells[key] = cells[key] or {}
            table.insert(cells[key], node)
        end
    end
    local function Twin(node)
        local x, y = ns.Num(node.x), ns.Num(node.y)
        if not (x and y) then return false end
        local i, j = math.floor(x / cx), math.floor(y / cy)
        for di = -1, 1 do
            for dj = -1, 1 do
                for _, mine in ipairs(cells[Key(node.id, i + di, j + dj)] or {}) do
                    local near
                    if w and h and w > 0 and h > 0 then
                        near = math.sqrt(((x - mine.x) * w) ^ 2 + ((y - mine.y) * h) ^ 2) <= Gather.SHIP_TWIN_YARDS
                    else
                        near = math.abs(x - mine.x) < 0.01 and math.abs(y - mine.y) < 0.01
                    end
                    if near then return true end
                end
            end
        end
        return false
    end
    for _, node in ipairs(G.ShipNodes(mapID, FilterFor(kind))) do
        if not Twin(node) then out[#out + 1] = node end
    end
    return out
end

-- Lage eines Knotens auf seiner Speicherkarte: Core.Gathering.Nodes liefert sx, sy (Welle 23c); liegt der Knoten
-- auf der gezeigten Karte, sind x, y dieselben. → x, y oder nil
local function StoredXY(node, mapID)
    if type(node) ~= "table" then return nil end
    local sx, sy = ns.Num(node.sx), ns.Num(node.sy)
    if sx and sy then return sx, sy end
    if node.map == mapID then return ns.Num(node.x), ns.Num(node.y) end
    return nil
end
Gather.StoredXY = StoredXY

-- Eben geerntet? → Alter in Sekunden oder nil (recent aus Recent(mapID)). Ob die Stelle gemeint ist (Umkreis
-- JUST_YARDS auf der Speicherkarte, nicht älter als gatherDim Minuten), entscheidet seit Welle 23 (A8) ezCore
-- (Core.Gathering.WasJustGathered mit maxAge); die Sitzungsliste liefert nur noch das Alter für den Tooltip, und
-- zwar das der Ernte an DIESER Stelle (Umkreis JUST_YARDS auf der Speicherkarte), nicht das jüngste desselben
-- Vorkommens anderswo auf der Karte (Gegenprüfung Welle 23).
function Gather.DimAge(node, recent, mapID)
    local G = GatherAPI()
    local minutes = ns.Num(ns.S and ns.S.gatherDim) or 0
    if not (G and type(G.WasJustGathered) == "function") or minutes <= 0 or #recent == 0 then return nil end
    local sx, sy = StoredXY(node, mapID)
    if not G.WasJustGathered(node.id, node.map, sx, sy, minutes * 60) then return nil end
    local radius = ns.Num(G.JUST_YARDS) or 15
    local age
    for _, e in ipairs(recent) do
        if e.id == node.id and e.kind == node.kind and e.map == node.map and (not age or e.age < age) then
            local here
            if not (e.sx and e.sy) then
                here = true
            elseif sx and sy then
                here = Close(node.map, e.sx, e.sy, sx, sy, radius)
            else
                here = Close(mapID, e.x, e.y, node.x, node.y, radius)
            end
            if here then age = e.age end
        end
    end
    return age
end

---------------------------------------------------------------------------
-- Anbieter für Core.MapPins
---------------------------------------------------------------------------

function Gather.Points(mapID, surface)
    mapID = ns.Num(mapID)
    if not mapID then return {} end
    local mini = surface == "minimap"
    local size = ns.Num(mini and ns.S.gatherMiniSize or ns.S.gatherSize) or (mini and 12 or 14)
    local alpha = math.max(0.1, math.min(1, (ns.Num(mini and ns.S.gatherMiniAlpha or ns.S.gatherAlpha) or 100) / 100))
    local recent = Recent(mapID)
    local out = {}
    local shown = Gather.Shown(mapID, surface)
    -- Weltkarte: die gezeigten Knoten merken – QuestieSpawns.lua gleicht im selben Neuaufbau damit ab, statt sie noch
    -- einmal zu rechnen (Paket „Fundorte“, Fund des code-reviewers vom 22.11.2026)
    if not mini then Gather.lastShown = { map = mapID, nodes = shown } end
    for _, node in ipairs(shown) do
        local f = Gather.Facts(node)
        local point = { x = node.x, y = node.y, texture = f.icon, size = size, a = alpha, node = node }
        if node.color == "red" then
            -- noch nicht sammelbar (Teilwelle 15b): deutlich anders – rötlich und blasser
            point.r, point.g, point.b = Gather.RED_TINT[1], Gather.RED_TINT[2], Gather.RED_TINT[3]
            point.a = alpha * Gather.RED_ALPHA
            point.red = true
        end
        local age = #recent > 0 and Gather.DimAge(node, recent, mapID) or nil
        if age then
            point.r, point.g, point.b, point.a = Gather.DIM, Gather.DIM, Gather.DIM, alpha * Gather.DIM
            point.dim = age
        end
        out[#out + 1] = point
    end
    return out
end

-- Punkte für die Minikarte (SAM-11): mapID ist die Speicherkarte, auf der der Spieler steht (ezCore rechnet die Lage)
function Gather.MiniPoints(mapID) return Gather.Points(mapID, "minimap") end

-- Ist mindestens eine Art auf der Minikarte eingeschaltet?
function Gather.AnyMiniKind()
    for _, kind in ipairs(Gather.KINDS) do
        if ns.Enabled(Gather.MINI_KEY[kind]) then return true end
    end
    return false
end

-- Lässt ezCore die Minikarten-Punkte mangels Sichtradius aus? → Grund ("api" | "nocore") oder nil. Dieselbe Regel wie
-- ezCores Grund „api“ (MapPins.MinimapState): C_Minimap.GetViewRadius fehlt oder nennt keinen Radius. Bewusst nicht aus
-- dem gemerkten Zustand gelesen – den setzt ezCore erst nach dem Sammeln der Punkte zurück, die Sichtbarkeit wird
-- aber mitten darin gefragt.
function Gather.MiniUnavailable()
    local P = Pins()
    if not (P and type(P.MinimapState) == "function") then return "nocore" end
    local api = rawget(_G, "C_Minimap")
    if type(api) ~= "table" or type(api.GetViewRadius) ~= "function" then return "api" end
    local ok, yards = pcall(api.GetViewRadius)
    yards = ok and not Core.IsSecret(yards) and ns.Num(yards) or nil
    if not (yards and yards > 0) then return "api" end
    return nil
end

-- Zeichnet ezMap auf der Minikarte? → true oder false, Grund ("nocore" | "off" | "other" | "api")
function Gather.MiniActive()
    if not (GatherAPI() and Pins()) then return false, "nocore" end
    if not Gather.AnyMiniKind() then return false, "off" end
    if Gather.Yields() then return false, "other" end
    if Gather.MiniUnavailable() then return false, "api" end
    return true
end

-- Umkreis in Yards, in dem die Minikarte ezMaps Punkte auslässt (Feld hideNear der Anbieter „ezMap.gather“ und
-- „ezMap.route“; ezCore fragt bei jeder Neuberechnung) → Yards oder nil (Schieber auf 0 = aus). Seit der
-- Einstellungs-Prüfung vom 19.11.2026 (Nr. 89, 90) ein Schieber statt Haken und Schieber: 0 heißt aus, sonst wird der
-- Wert auf HIDE_NEAR_MIN bis HIDE_NEAR_MAX begrenzt; Unlesbares gilt als HIDE_NEAR_DEFAULT. Ein gespeichertes „aus“
-- des alten Hakens gatherHideNear übernimmt ns.MigrateSettings1911 als 0.
function Gather.HideNear()
    if not ns.db then return nil end
    local yards = ns.Num(ns.S and ns.S.gatherHideNearYards) or Gather.HIDE_NEAR_DEFAULT
    if yards <= 0 then return nil end
    return math.max(Gather.HIDE_NEAR_MIN, math.min(Gather.HIDE_NEAR_MAX, yards))
end

-- Beschriftung des Schiebers: 0 = „aus“, sonst die geltende Entfernung (1 bis 9 gelten als HIDE_NEAR_MIN)
function Gather.HideNearLabel(value)
    value = ns.Num(value) or 0
    if value <= 0 then return L.GMAP_DIM_OFF end
    return Core.L.GATHER_YARDS:format(math.max(Gather.HIDE_NEAR_MIN, math.min(Gather.HIDE_NEAR_MAX, value)))
end

-- Neu zeichnen, wenn die Karte offen ist (Core.MapPins baut nur die gezeigte Karte, in Scheiben)
function Gather.Refresh()
    local P = Pins()
    if P and type(P.Refresh) == "function" then return P.Refresh() end
    return 0
end

local function ShownMapID()
    local map = rawget(_G, "WorldMapFrame")
    if type(map) ~= "table" or type(map.GetMapID) ~= "function" then return nil end
    local ok, id = pcall(map.GetMapID, map)
    return ok and ns.Num(id) or nil
end
Gather.ShownMapID = ShownMapID

---------------------------------------------------------------------------
-- Tooltip am Punkt (SAM-13)
---------------------------------------------------------------------------

local function QtyText(it, harvests)
    local lo, hi = ns.Num(it.lo), ns.Num(it.hi)
    if lo and hi and lo ~= hi then return ("%d–%d"):format(lo, hi) end
    if lo or hi then return tostring(lo or hi) end
    local f, s = ns.Num(it.f) or 0, ns.Num(it.s) or 0
    if f > 0 then return Core.Decimal(s / f, 1) end   -- Dezimalzeichen der Spielsprache (T16-2)
    return "?"
end

-- „Silberblatt ×1–3, Wilddornrose ×1 (12 %)“ → Text oder nil
function Gather.YieldText(total)
    if type(total) ~= "table" or type(total.items) ~= "table" then return nil end
    local harvests = ns.Num(total.cnt) or 0
    local list = {}
    for itemID, it in pairs(total.items) do
        if ns.Num(itemID) and type(it) == "table" and (ns.Num(it.f) or 0) > 0 then list[#list + 1] = { id = itemID, it = it } end
    end
    if #list == 0 then return nil end
    table.sort(list, function(a, b)
        if a.it.f ~= b.it.f then return a.it.f > b.it.f end
        return a.id < b.id
    end)
    local parts = {}
    for i = 1, math.min(#list, Gather.YIELD_LINES) do
        local e = list[i]
        local name = Core.ItemNameByID(e.id) or ("#" .. e.id)
        local qty = QtyText(e.it, harvests)
        local share = harvests > 0 and e.it.f / harvests or 1
        if share < 0.9 then
            parts[#parts + 1] = L.GMAP_YIELD_SHARE:format(name, qty, Core.Percent(share * 100))
        else
            parts[#parts + 1] = L.GMAP_YIELD_ITEM:format(name, qty)
        end
    end
    return table.concat(parts, ", ")
end

-- Wert je Ernte (V2, Welle 24): Rechnung, Mindestzahl und Wortlaut aus ezCore (Core.Drops.Worth und WorthLines,
-- Welle 23d) – dieselbe Zeile wie am Gegner in ezLoot. Grundlage sind die eigenen Ernten des Vorkommens (Objekte:
-- überall, wo du es geerntet hast; Angeln: das Gebiet auf dieser Speicherkarte), Preise aus den eigenen
-- Auktionshaus-Erfassungen bzw. der Händlerpreis laut Client. Angelplätze und Fischschwärme nennt ezCore „je Fang“
-- mit „bei dir gefangen: n“ (Drops.WORTH_PER, Welle 26). → Zeilen { Wert, Grundlage } oder {} und Grund:
-- "nocore" (ezCore ohne den Dienst: nichts zeigen), "error", sonst ezCores Grund ("few" unter der Mindestzahl, "none",
-- "secret", "noprice"). Immer an seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 44, Zustimmung des Nutzers „Ja,
-- alle umsetzen“): die Zeile erscheint nur beim Draufzeigen; der Schalter gatherWorth entfällt, ein gespeichertes „aus“
-- gilt nicht mehr.
local function WorthArgs(node)
    if node.stored == "fishing" then return "fishing", node.map, node.id end
    return "object", node.id
end

function Gather.WorthLines(node)
    local D = Core.Drops
    if not (type(D) == "table" and type(D.Worth) == "function" and type(D.WorthLines) == "function") then
        return {}, "nocore"
    end
    if type(node) ~= "table" or node.id == nil then return {}, "none" end
    local ok, worth, why = pcall(D.Worth, WorthArgs(node))
    if not ok then return {}, "error" end
    if type(worth) ~= "table" then return {}, why or "none" end
    local lines
    ok, lines = pcall(D.WorthLines, WorthArgs(node))
    if not (ok and type(lines) == "table") then return {}, "error" end
    return lines
end

-- Zeilen „Fertigkeitspunkt: …“ (Core.Gathering.SkillUp und SkillUpLines; Kisten: keine) → Zahl der Zeilen
function Gather.AddSkillUp(tip, node)
    local G = GatherAPI()
    if not (G and type(G.SkillUp) == "function" and type(G.SkillUpLines) == "function") then return 0 end
    local lines = G.SkillUpLines(G.SkillUp(node.id, node.kind))
    for _, line in ipairs(lines) do tip:AddLine(line.text, line.r, line.g, line.b, true) end
    return #lines
end

function Gather.Tooltip(tip, point, mapID)
    local node = type(point) == "table" and point.node
    if type(node) ~= "table" then return end
    local f = Gather.Facts(node)
    Core.TipTitle(tip, f.name)
    Core.TipLine(tip, KindLabel(node.kind), "hint")
    local cnt = ns.Num(node.cnt) or 0
    if node.src == "ship" then
        -- aus Beiträgen anderer Spieler (ezData): ihre Ernten an dieser Stelle, ohne „zuletzt“ (Tage der Beiträge)
        Core.TipLine(tip, L.GMAP_HARVESTS_SHIP:format(cnt), "highlight")
    elseif ns.Num(node.t) then
        -- node.t ist ein Stempel der Datenbank (Serveruhr, Core.DB.Stamp): gegen die Serveruhr rechnen (T16-NZ1)
        Core.TipLine(tip, L.GMAP_HARVESTS:format(cnt, Core.Ago(node.t, "server")), "highlight")
    else
        Core.TipLine(tip, L.GMAP_HARVESTS_NOTIME:format(cnt), "highlight")
    end
    local yield = Gather.YieldText(f.total)
    if node.src == "ship" then
        -- Punkt aus Beiträgen: der Ertrag kommt aus deiner Beute – nur, wenn es ihn gibt, und mit „bei dir“
        if yield then Core.TipLine(tip, L.GMAP_YIELD_OWN:format(yield), "highlight", true) end
    else
        Core.TipLine(tip, yield and L.GMAP_YIELD:format(yield) or L.GMAP_YIELD_NONE, "highlight", true)
    end
    if node.stored ~= "fishing" then
        local G = GatherAPI()
        local skill = G and type(G.SkillText) == "function" and G.SkillText(node.id) or nil
        -- Welle 27 (F4 b): Kisten nennen den nötigen Wert (Schlossknacken) nur, wenn ezCore ihn kennt – die meisten
        -- Kisten verlangen keinen, „noch unbekannt“ wäre dort irreführend
        if skill then
            Core.TipLine(tip, L.GMAP_SKILL:format(skill), "highlight", true)
        elseif node.kind ~= "chest" then
            Core.TipLine(tip, L.GMAP_SKILL_NONE, "highlight", true)
        end
    end
    -- Chance auf einen Fertigkeitspunkt (Teilwelle 15b): Zeile in der Farbe und Quelle, beides aus ezCore
    Gather.AddSkillUp(tip, node)
    -- Wert je Ernte (V2): erst ab ezCores Mindestzahl, sonst keine Zeile; genug gezählt, aber kein Preis: ein
    -- ehrlicher Satz (das Auktionshaus besuchen)
    local worth, why = Gather.WorthLines(node)
    if worth[1] then
        Core.TipLine(tip, worth[1], "highlight")
        if worth[2] then Core.TipLine(tip, worth[2], "hint", true) end
    elseif why == "noprice" then
        Core.TipLine(tip, L.GMAP_VALUE_NONE, "hint", true)
    end
    if point.dim then Core.TipLine(tip, L.GMAP_DIMMED:format(Core.Duration(point.dim, true)), "blue") end
    -- Herkunft der Stelle: „bei dir“ aus ezCore, „aus deiner Sicherung“ für Stellen, die ezCore aus einem Text von
    -- „Als Text sichern“ eingelesen hat (Core.Gathering.Nodes reicht src = "backup" weiter, ezCore 23d, SAM-19; eine
    -- eigene Ernte dort macht wieder src = "own"). Filter und Haken behandeln solche Stellen wie eigene.
    -- Punkte aus Beiträgen anderer Spieler (ezData, Gather.WithShip) nennen „aus Beiträgen (n Spieler), Stand Build x“
    local label = (node.src == "ship" and node.label) or (node.src == "backup" and L.GMAP_SOURCE_BACKUP)
        or Core.L["DB_OWN"]
    Core.TipLine(tip, L.GMAP_SOURCE:format(label), "hint")
    -- Paket „Fundorte“ (22.11.2026): Questie kennt hier ein Vorkommen derselben Art – dessen Punkt zeichnet ezMap nicht
    -- doppelt (QuestieSpawns.lua, QS.TwinOf); die Quelle steht dann hier
    local QS = ns.QuestieSpawns
    if QS and type(QS.TwinOf) == "function" and QS.TwinOf(node, mapID) then
        local S = Core.Sources
        local questie = S and S.Label and S.Label({ source = "Questie", sourceKey = "QuestieDB" })
            or Core.L.SOURCES_ACCORDING:format("Questie")
        Core.TipLine(tip, L.GMAP_ALSO_QUESTIE:format(questie), "hint", true)
    end
    if node.fallback then Core.TipLine(tip, L.GMAP_FALLBACK, "hint", true) end
    if Gather.focus then Core.TipLine(tip, L.GMAP_FOCUS_TIP_LINE, "blue", true) end
    Core.TipClick(tip, L.GMAP_HINT)
end

---------------------------------------------------------------------------
-- Klick und Menü am Punkt (SAM-14)
---------------------------------------------------------------------------

function Gather.Click(point, button, mapID)
    local node = type(point) == "table" and point.node
    if type(node) ~= "table" or button == "RightButton" then return false end
    return ns.Way.Set(mapID, point.x, point.y, Gather.Facts(node).name, true)
end

-- Nächster weiterer Fundort desselben Vorkommens auf der Karte mapID: vom Spieler aus, wenn er auf der Karte steht,
-- sonst vom Punkt; ohne den Punkt selbst, eben geerntete nur, wenn sonst keiner bleibt → Knoten oder nil
function Gather.NextOf(node, mapID)
    local G = GatherAPI()
    mapID = ns.Num(mapID)
    if not (G and mapID and type(node) == "table") then return nil end
    local px, py
    local where, x, y = Core.PlayerPosition(mapID)
    if where == mapID then px, py = x, y end
    local fromX, fromY = px or node.x, py or node.y
    local w, h = Yards(mapID)
    local recent = Recent(mapID)
    local best, bestD, spare, spareD
    for _, other in ipairs(G.Nodes(mapID, { kind = node.kind, explorer = true })) do
        if other.id == node.id and not (other.x == node.x and other.y == node.y) then
            local d
            if w and h then
                d = math.sqrt(((other.x - fromX) * w) ^ 2 + ((other.y - fromY) * h) ^ 2)
            else
                d = math.sqrt((other.x - fromX) ^ 2 + (other.y - fromY) ^ 2) * 1000
            end
            local here = px and w and d <= Gather.NEAR_YARDS
            if not here then
                if Gather.DimAge(other, recent, mapID) then
                    if not spareD or d < spareD then spare, spareD = other, d end
                elseif not bestD or d < bestD then
                    best, bestD = other, d
                end
            end
        end
    end
    return best or spare
end

local function Tip(entry, title, text, source) return ns.MapButton.Tip(entry, title, text, source) end

-- Zahl der eigenen Stellen, die Vergessen löscht: ein Objekt auf allen Speicherkarten (Core.Places.Of), Angeln alle
-- Stellen der Speicherkarte (Core.Places.OnMap). Core.Gathering.Forget zählt dagegen Datensätze (eine Liste je Karte
-- und Gebiet, dazu obj- und drops-Satz), nicht Stellen. → Anzahl
function Gather.ForgetCount(node)
    local P = Core.Places
    if type(P) ~= "table" or type(node) ~= "table" then return 0 end
    local n = 0
    if node.stored == "fishing" then
        local byKind = type(P.OnMap) == "function" and P.OnMap(node.map, { kind = "fishing", explorer = true }) or nil
        local areas = type(byKind) == "table" and type(byKind.fishing) == "table" and byKind.fishing or {}
        for _, list in pairs(areas) do n = n + #list end
    elseif type(P.Of) == "function" then
        n = #(P.Of("object", node.id, { explorer = true }) or {})
    end
    return n
end

function Gather.ForgetNode(node)
    local G = GatherAPI()
    if not (G and type(G.Forget) == "function") then return 0 end
    local spots = Gather.ForgetCount(node)
    local n
    if node.stored == "fishing" then
        n = G.Forget({ map = node.map, kind = "fish" })
    else
        n = G.Forget({ id = node.id })
    end
    if (ns.Num(n) or 0) <= 0 then spots = 0 end
    Gather.ForgetFacts()
    ns.Print(L.GMAP_FORGET_DONE:format(spots))
    Gather.Refresh()
    return spots
end

-- Nur diese eine Stelle vergessen (Welle 23, A8; SAM-14 „Diesen Punkt löschen“): Core.Gathering.Forget({ map, id,
-- x, y, kind }) entfernt die Stelle auf der Speicherkarte im Umkreis von JUST_YARDS. → 1 oder 0
function Gather.ForgetSpot(node, mapID)
    local G = GatherAPI()
    local x, y = StoredXY(node, mapID)
    if not (G and type(G.Forget) == "function" and type(node) == "table" and x and y) then return 0 end
    local n = ns.Num(G.Forget({ map = node.map, id = node.id, x = x, y = y,
        kind = node.stored == "fishing" and "fish" or nil })) or 0
    Gather.ForgetFacts()
    ns.Print(n > 0 and L.GMAP_FORGET_SPOT_DONE or L.GMAP_FORGET_SPOT_NONE)
    Gather.Refresh()
    return n > 0 and 1 or 0
end

-- Zahl der Fundorte dieses Vorkommens auf der Karte (für den Text der Rückfrage)
local function CountOf(node, mapID)
    local G = GatherAPI()
    local n = 0
    for _, other in ipairs(G and G.Nodes(mapID, { kind = node.kind, explorer = true }) or {}) do
        if other.id == node.id then n = n + 1 end
    end
    return n
end

function Gather.Menu(point, root, mapID)
    local node = type(point) == "table" and point.node
    if type(node) ~= "table" then return end
    local Menu = Core.Menu
    local name = Gather.Facts(node).name
    Menu.Title(root, name)
    Tip(Menu.Button(root, L.GMAP_PT_WAY, function() ns.Way.Set(mapID, point.x, point.y, name, true) end),
        L.GMAP_PT_WAY, L.GMAP_PT_WAY_TIP)
    local nextNode = Gather.NextOf(node, mapID)
    if nextNode then
        local text = L.GMAP_PT_NEXT:format(name)
        Tip(Menu.Button(root, text, function() ns.Way.Set(mapID, nextNode.x, nextNode.y, name, true) end),
            text, L.GMAP_PT_NEXT_TIP)
    else
        local text = L.GMAP_PT_NEXT_NONE:format(name)
        Tip(Menu.Title(root, text), text, L.GMAP_PT_NEXT_NONE_TIP)
    end
    local hide = L.GMAP_PT_HIDE:format(name)
    Tip(Menu.Button(root, hide, function() Gather.SetHidden(node, true) end), hide, L.GMAP_PT_HIDE_TIP)
    -- Vergessen löscht eigene Stellen – ein Punkt aus Beiträgen (ezData) ist keine; ausblenden geht wie oben
    if node.src == "ship" then return end
    Menu.Divider(root)
    if StoredXY(node, mapID) then
        local spot = L.GMAP_PT_FORGET_SPOT
        Tip(Menu.Button(root, spot, function()
            Core.Confirm(L.GMAP_FORGET_SPOT_CONFIRM:format(name), function() Gather.ForgetSpot(node, mapID) end,
                { alert = true })
        end), spot, L.GMAP_PT_FORGET_SPOT_TIP)
    end
    local fishing = node.stored == "fishing"
    local forget = fishing and L.GMAP_PT_FORGET_FISH or L.GMAP_PT_FORGET:format(name)
    Tip(Menu.Button(root, forget, function()
        -- Zahlen erst beim Klick: über alle Karten (Gather.ForgetCount), dazu die dieser Karte
        local total, ask = Gather.ForgetCount(node), nil
        if fishing then
            ask = L.GMAP_FORGET_FISH_CONFIRM:format(ns.MapName(node.map), total)
        else
            local here = CountOf(node, mapID)
            ask = L.GMAP_FORGET_CONFIRM:format(name, math.max(total, here), here)
        end
        Core.Confirm(ask, function() Gather.ForgetNode(node) end, { alert = true })
    end), forget, fishing and L.GMAP_PT_FORGET_FISH_TIP or L.GMAP_PT_FORGET_TIP)
end

---------------------------------------------------------------------------
-- Abschnitt „ezMap – Sammeln“: Blizzards Kartenfilter, ezMap-Kartenknopf (SAM-12, SAM-16)
---------------------------------------------------------------------------

local STATE_TEXT = { off = "GMAP_STATE_OFF", profession = "GMAP_STATE_PROFESSION",
    tracking = "GMAP_STATE_TRACKING", explorer = "GMAP_STATE_EXPLORER", noskill = "GMAP_STATE_NOSKILL",
    nocore = "GMAP_STATE_NOCORE" }

-- Erklärung je Art: Schalter-Tooltip plus, warum die Art gerade unsichtbar ist
function Gather.KindTip(kind)
    local tip = L["OPT_" .. Gather.KEY[kind] .. "_TIP"]
    local ok, why = Gather.KindState(kind)
    if not ok and STATE_TEXT[why] then tip = tip .. "\n\n" .. L[STATE_TEXT[why]]:format(KindLabel(kind)) end
    return tip
end

-- Vorkommen dieser Art auf der Karte (ohne Ausblend-Liste) → { { node, name, count } … } nach Name; für Kisten ohne
-- ezMaps Haken nil (Entdecker-Wissen: keine Namen, auch nicht von Altbestand-Objekten ohne obj-Satz)
local function ObjectsOn(kind, mapID)
    if kind == "chest" and not ns.Enabled("gatherChest") then return nil end
    local G = GatherAPI()
    local seen, out = {}, {}
    for _, node in ipairs(G and mapID and G.Nodes(mapID, { kind = kind, explorer = kind == "chest" or nil }) or {}) do
        local key = Gather.HiddenKey(node)
        local e = seen[key]
        if not e then
            e = { node = node, name = Gather.Facts(node).name, count = 0 }
            seen[key] = e
            out[#out + 1] = e
        end
        e.count = e.count + 1
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function AddKind(root, kind, mapID)
    local Menu = Core.Menu
    local key = Gather.KEY[kind]
    local label = KindLabel(kind)
    local entry = Menu.Toggle(root, label, function() return ns.Enabled(key) end,
        function(on) ns.Tree.SetLeaf(key, on) end)
    Tip(entry, label, Gather.KindTip(kind), ns.Tree.Source(key))   -- graue Quelle wie jedes Blatt des Baums
    -- Untermenü: wann zeigen (nicht bei Kisten: nur „Immer“, Nr. 2 der Einstellungs-Prüfung), einzelne Vorkommen
    if Gather.HasModes(kind) then
        Tip(Menu.Title(entry, L.GMAP_WHEN), L.GMAP_WHEN, L.GMAP_WHEN_TIP)
        for _, mode in ipairs(Gather.MODES[kind]) do
            local text = L["GMAP_MODE_" .. mode]
            Tip(Menu.Radio(entry, text, function() return Gather.Mode(kind) end, function(m) Gather.SetMode(kind, m) end,
                mode), text, L["GMAP_MODE_" .. mode .. "_TIP"])
        end
        Menu.Divider(entry)
    end
    Tip(Menu.Title(entry, L.GMAP_OBJECTS), L.GMAP_OBJECTS, L.GMAP_OBJECTS_TIP)
    local objects = ObjectsOn(kind, mapID)
    if not objects then
        ns.Icons.Apply(Tip(Menu.Title(entry, L.GMAP_OBJECTS_CHEST_OFF), L.GMAP_OBJECTS_CHEST_OFF, L.GMAP_OBJECTS_CHEST_OFF_TIP), "info")
    elseif #objects == 0 then
        ns.Icons.Apply(Tip(Menu.Title(entry, L.GMAP_OBJECTS_NONE), L.GMAP_OBJECTS_NONE, L.GMAP_OBJECTS_NONE_TIP), "info")
    end
    -- Design-System 2.11: ein Haken „Alle“ über den Vorkommen (ab drei); gemerkt in gatherHidden wie
    -- jeder Haken, die Karte zeichnet einmal neu statt je Vorkommen
    if objects and #objects >= 3 then
        Menu.AllToggle(entry, objects, function(o) return not Gather.IsHidden(o.node) end,
            function(o, on) Gather.SetHidden(o.node, not on, true) end,
            { after = function(changed) if changed > 0 then Gather.Refresh() end end })
    end
    for _, o in ipairs(objects or {}) do
        local text = L.GMAP_OBJECT:format(o.name, o.count)
        Tip(Menu.Toggle(entry, text, function() return not Gather.IsHidden(o.node) end,
            function(on) Gather.SetHidden(o.node, not on) end), text, L.GMAP_OBJECT_TIP)
    end
    return entry       -- Welle 27: der Baum (Tree.AddMenu) setzt das Symbol der Art daran
end

-- Ein Satz über den Stand der Karte: leer, alles ausgeblendet, Welt- oder Kontinentkarte → Text, Tooltip oder nil
function Gather.EmptyText(mapID)
    if not mapID then return nil end
    if not Gather.MapAllowed(mapID) then return L.GMAP_NOZONE, L.GMAP_NOZONE_TIP end
    -- Punkte aus Beiträgen (ezData) zählen getrennt: „deine Fundorte“ sind nur die eigenen (Leitlinie 11)
    local shown, ship = 0, 0
    for _, node in ipairs(Gather.Shown(mapID)) do
        if node.src == "ship" then ship = ship + 1 else shown = shown + 1 end
    end
    if ship > 0 then return L.GMAP_SHOWN_SHIP:format(shown + ship, shown, ship), L.GMAP_SHOWN_SHIP_TIP end
    if shown > 0 then return L.GMAP_SHOWN:format(shown), L.GMAP_SHOWN_TIP end
    local total = Gather.Total(mapID)
    if total == 0 then return L.GMAP_EMPTY, L.GMAP_EMPTY_TIP end
    return L.GMAP_HIDDEN:format(total), L.GMAP_HIDDEN_TIP
end

Gather.AddKind = AddKind

-- Kopf des Abschnitts: fehlt ezCores Dienst, zeichnet ein Sammel-Addon, gilt ein Filter aus ShowGather → false,
-- wenn ezCores Dienst fehlt (dann nichts weiter)
function Gather.SectionHead(root)
    local Menu, Box = Core.Menu, ns.MapButton
    if not GatherAPI() then
        Tip(Menu.Title(root, L.GMAP_NOCORE), L.GMAP_NOCORE, L.GMAP_NOCORE_TIP)
        return false
    end
    local other = Gather.Other()
    if other then
        local text = L.GMAP_OTHER:format(other)
        Box.OtherTitle(root, text, L.GMAP_OTHER_TIP)
        Box.Toggle(root, L.OPT_gatherOverride, "gatherOverride")
    end
    if Gather.focus then
        local text = L.GMAP_FOCUS:format(Gather.FocusLabel())
        Tip(Menu.Button(root, text, Gather.ClearFocus), text, L.GMAP_FOCUS_TIP)
    end
    return true
end

---------------------------------------------------------------------------
-- „Wo am dichtesten?“ und Fortschritt je Zone (SAM-23)
---------------------------------------------------------------------------

Gather.DENSE_ITEMS = 12     -- so viele Rohstoffe je Art
Gather.DENSE_ZONES = 8      -- so viele Zonen je Rohstoff

-- Rohstoffe je Art, die du schon geerntet hast, und je Rohstoff die Zonen mit den meisten eigenen Fundorten
-- (Core.Finds.Of: Punkte je Karte, über alle Kontinente). Seit Welle 23 (A8) kommt die Liste der Rohstoffe aus
-- ezCore (Core.Gathering.Items: alle eigenen Ernten mit Art) – vorher nur der Hauptertrag der Vorkommen auf dem
-- Kontinent der gezeigten Karte. mapID bleibt für die Aufrufer (Menü je Karte). Ausgeblendete Vorkommen („Auf der
-- Karte ausblenden“) gelten weiter: ein Rohstoff, dessen Objekte (Core.Gathering.ObjectsFor) alle ausgeblendet sind,
-- fehlt in der Liste (Gegenprüfung Welle 23). Angeln kennt ObjectsFor nicht; dort bleibt der Rohstoff.
-- → { { kind, items = { { item, name, total, zones = { { map, name, points } … } } … } } … } (Arten ohne Rohstoff fehlen)
function Gather.Dense(mapID)
    local G = GatherAPI()
    local F = Core.Finds
    if not (G and type(G.Items) == "function" and type(F) == "table" and type(F.Of) == "function") then return {} end
    local hidden = Hidden()
    local anyHidden = next(hidden) ~= nil
    -- Alle Objekte, die den Rohstoff liefern, unter dieser Art ausgeblendet? Ohne bekannte Objekte: nein.
    local function AllHidden(kind, item)
        if not (anyHidden and type(G.ObjectsFor) == "function") then return false end
        local any = false
        for id in pairs(G.ObjectsFor(item) or {}) do
            if not hidden[Gather.HiddenKey({ kind = kind, id = id })] then return false end
            any = true
        end
        return any
    end
    local out = {}
    for _, kind in ipairs(Gather.KINDS) do
        if kind ~= "chest" or ChestsWanted() then
            local seen, items = {}, {}
            for _, e in ipairs(G.Items(kind) or {}) do
                local main = ns.Num(type(e) == "table" and e.item or nil)
                if main and not seen[main] and not AllHidden(kind, main) then
                    seen[main] = true
                    local zones, total = {}, 0
                    for _, find in ipairs(F.Of(main) or {}) do
                        local m, points = ns.Num(find.mapID), ns.Num(find.points) or 0
                        if m and points > 0 and Gather.MapAllowed(m) then
                            zones[#zones + 1] = { map = m, name = ns.MapName(m), points = points }
                            total = total + points
                        end
                    end
                    table.sort(zones, function(a, b)
                        if a.points ~= b.points then return a.points > b.points end
                        return a.map < b.map
                    end)
                    while #zones > Gather.DENSE_ZONES do table.remove(zones) end
                    if #zones > 0 then
                        items[#items + 1] = { item = main, name = Core.ItemNameByID(main) or ("#" .. main), total = total,
                            zones = zones }
                    end
                end
            end
            table.sort(items, function(a, b)
                if a.total ~= b.total then return a.total > b.total end
                return a.name < b.name
            end)
            while #items > Gather.DENSE_ITEMS do table.remove(items) end
            if #items > 0 then out[#out + 1] = { kind = kind, items = items } end
        end
    end
    return out
end

-- Kartenmenü „Wo am dichtesten?“: je Art die Rohstoffe, je Rohstoff die Zonen nach eigener Punktzahl; ein Klick ruft
-- ShowGather (Karte der Zone mit nur diesem Rohstoff, Markierung auf den nächsten Fundort) → der Eintrag
-- Solange fn läuft, rechnet „Wo am dichtesten?“ je Karte nur einmal (ein Menü kann den Eintrag mehrfach enthalten;
-- Gather.Dense fragt je Rohstoff alle eigenen Fundorte ab). Danach wird in jedem Fall wieder frisch gerechnet.
function Gather.WithDenseMemo(fn, ...)
    if Gather.denseMemo then return fn(...) end
    Gather.denseMemo = {}
    local ok, result = pcall(fn, ...)
    Gather.denseMemo = nil
    if not ok then error(result, 0) end
    return result
end

function Gather.AddDenseMenu(root, mapID)
    local Menu = Core.Menu
    if not GatherAPI() then return nil end
    local sub = ns.Icons.Apply(Tip(Menu.Button(root, L.GMAP_DENSE), L.GMAP_DENSE, L.GMAP_DENSE_TIP), "gatherDense")
    local memo, key = Gather.denseMemo, mapID or 0
    local list = memo and memo[key]
    if not list then
        list = Gather.Dense(mapID)
        if memo then memo[key] = list end
    end
    if #list == 0 then
        -- Hilfszeile mit dem „i“, Überschriften mit dem Symbol der Art (Fund der Nachprüfung vom 17.11.2026)
        ns.Icons.Apply(Tip(Menu.Title(sub, L.GMAP_DENSE_NONE), L.GMAP_DENSE_NONE, L.GMAP_DENSE_NONE_TIP), "info")
        return sub
    end
    for _, group in ipairs(list) do
        ns.Icons.Apply(Menu.Title(sub, KindLabel(group.kind)), ns.Tree.Icon(Gather.KEY[group.kind]))
        for _, it in ipairs(group.items) do
            local label = L.GMAP_DENSE_ITEM:format(it.name, it.total)
            local itemMenu = Tip(Menu.Button(sub, label), label, L.GMAP_DENSE_ITEM_TIP)
            for _, z in ipairs(it.zones) do
                local text = L.GMAP_DENSE_ZONE:format(z.name, Core.Plural(z.points, Core.L["GATHER_SPOTS_ONE"], Core.L["GATHER_SPOTS_MANY"]))
                local item, map = it.item, z.map
                Tip(Menu.Button(itemMenu, text, function() Gather.Show({ item = item, map = map }) end), text,
                    L.GMAP_DENSE_ZONE_TIP)
            end
        end
    end
    return sub
end

-- Zeilen „Fortschritt: Kräuter: 37 Fundorte, zuletzt neu vor 3 Tagen“ der gezeigten Zone (Auskunft aus ezCore,
-- Core.Gathering.ProgressLines je Speicherkarte) → { Text … }; auf Welt- und Kontinentkarten keine
function Gather.ProgressLines(mapID)
    local G = GatherAPI()
    mapID = ns.Num(mapID)
    if not (G and mapID and type(G.ProgressLines) == "function" and Gather.MapAllowed(mapID)) then return {} end
    local Keys = Core.DB and Core.DB.Keys
    local store = Keys and Keys.MapOf and Keys.MapOf(mapID) or mapID
    local out = {}
    for _, line in ipairs(G.ProgressLines(store) or {}) do
        if type(line) == "string" then out[#out + 1] = L.GMAP_PROGRESS:format((line:gsub("^%s+", ""))) end
    end
    return out
end

-- Fuß des Abschnitts: der Satz zum Stand der Karte, Fortschritt der Zone und „Wo am dichtesten?“ (SAM-23). „Nur, was
-- ich abbauen kann“ stand bis zum 19.11.2026 hier; seitdem ist es „Rot – noch nicht abbaubar“ im Filter „Nach Farbe“
-- (Nr. 88 der Einstellungs-Prüfung)
function Gather.SectionFoot(root, mapID)
    local Menu = Core.Menu
    if not GatherAPI() then return end
    local other = Gather.Other()
    if not (other and not ns.Enabled("gatherOverride")) then
        local text, tip = Gather.EmptyText(mapID)
        if text then Tip(Menu.Title(root, text), text, tip) end
    end
    for _, line in ipairs(Gather.ProgressLines(mapID)) do Tip(Menu.Title(root, line), line, L.GMAP_PROGRESS_TIP) end
    Gather.AddDenseMenu(root, mapID)
end

-- Arten, die der Abschnitt im ezMap-Knopf auslässt: Kisten stehen im Baum unter „Entdecken“ » „Entdecker-Wissen“
-- (Tree.ROOT, Entdecker-Wissen nur auf Wunsch) und der Baum steht neben dem Abschnitt im Knopf – sonst zweimal
-- (Gegenprüfung vom 18.11.2026)
Gather.SECTION_SKIP = { chest = true }

-- Der ganze Abschnitt in einem Untermenü (ezMap-Knopf): Kopf, Gruppe „Sammeln“ wie im Baum (Schalter mit Erklärung,
-- „teilweise x von y“ und Quelle, „Teilweise wiederherstellen“, „Alle auswählen / Alle abwählen“), die Arten ohne
-- Kisten (Gather.SECTION_SKIP), die Untergruppen von „Sammeln“ (seit dem 18.11.2026 alle: der Baum im Knopf lässt die
-- Gruppe „Sammeln“ weg, MapButton.TREE_SKIP), Fuß
function Gather.BuildSection(root, mapID)
    if not Gather.SectionHead(root) then return end
    local Menu, Tree = Core.Menu, ns.Tree
    local label = Tree.LabelWithState("gather")
    ns.Icons.Apply(Tip(Menu.Toggle(root, label, function() return Tree.Checked("gather") end,
        function() Tree.Click("gather") end), label, Tree.GroupTip("gather"), Tree.Source("gather")), Tree.Icon("gather"))
    Tree.AddRestore(root, "gather")
    Tree.AddAllToggle(root, "gather")
    for _, kind in ipairs(Gather.KINDS) do
        if not Gather.SECTION_SKIP[kind] then
            ns.Icons.Apply(AddKind(root, kind, mapID), Tree.Icon(Gather.KEY[kind]))
        end
    end
    -- die Untergruppen der Gruppe „Sammeln“ wie im Baum: „Auf der Minikarte“ (SAM-11), „Nach Farbe“ (Teilwelle 15b),
    -- „Route“ (Route.lua) – vor dem 18.11.2026 stand hier nur „Nach Farbe“, die übrigen kamen über den Baum
    for _, child in ipairs(ns.Tree.Children("gather")) do
        if child.id then Tree.AddMenu(root, child.id, mapID) end
    end
    Gather.SectionFoot(root, mapID)
    if ns.Route then ns.Route.AddMenu(root, mapID) end     -- „Route durch diese Zone“ (SAM-21)
end

-- Blizzards Filterknopf der Weltkarte (Camelot: rechts an der Navigationsleiste; fehlt, wenn die Spielregel
-- WorldMapTrackingOptionsDisabled gilt) → der Knopf, wenn er sichtbar ist, sonst nil. Nur das benannte Feld: Blizzard
-- legt den Knopf dort an (Blizzard_WorldMap.lua, AddOverlayFrames); eine Suche über map.overlayFrames träfe ohne ihn
-- das Stockwerk-Auswahlfeld (ebenfalls ein Knopf mit SetupMenu).
function Gather.FilterButton()
    local map = rawget(_G, "WorldMapFrame")
    if type(map) ~= "table" then return nil end
    local button = map.WorldMapTrackingOptionsButton
    if type(button) == "table" and type(button.IsShown) == "function" and button:IsShown() then return button end
    return nil
end

-- Soll ezMaps Abschnitt in Blizzards Kartenfilter stehen? Mit dem Schalter mapFilterSection (ab Werk aus, Spielbefund
-- vom 18.11.2026: ein Knopf) – und immer, wenn der ezMap-Knopf abgeschaltet ist (mapButton aus): sonst gäbe es an der
-- Weltkarte keinen Weg mehr zu Baum, Sammel-Fundorten und ausgeblendeten Vorkommen (Leitlinie 3; Gegenprüfung vom
-- 18.11.2026)
function Gather.FilterWanted()
    return ns.Enabled("mapFilterSection") or not ns.Enabled("mapButton")
end

-- Steht ezMaps Abschnitt in Blizzards Kartenfilter? Nur, wenn gewünscht (Gather.FilterWanted), der Filterknopf da ist
-- und Blizzard den Abschnitt schon einmal gebaut hat. Dann verweist der ezMap-Knopf auf den Filter, statt die Schalter
-- doppelt zu zeigen. → der Filterknopf oder nil
function Gather.InFilter()
    if not Gather.FilterWanted() then return nil end
    local button = Gather.FilterButton()
    if button and Gather.blizzardMenuSeen then return button end
    return nil
end

-- Im ezMap-Kartenknopf: der ganze Abschnitt als Untermenü; nur wenn er auf Wunsch in Blizzards Kartenfilter steht
-- (Gather.InFilter), ein Verweis darauf
function Gather.AddMapMenu(root, mapID)
    local Menu = Core.Menu
    if Gather.InFilter() then
        Tip(Menu.Title(root, L.GMAP_IN_FILTER), L.GMAP_IN_FILTER, L.GMAP_IN_FILTER_TIP)
        return "filter"
    end
    local sub = Tip(Menu.Button(root, L.GMAP_MENU), L.GMAP_MENU, L.GMAP_MENU_TIP)
    -- Einträge ohne eigenes Symbol (Hinweise, „übernimmt …“, Fokus) bekommen das von „Sammeln“, Hilfszeilen das
    -- Hinweis-Symbol (Fund des code-reviewers vom 17.11.2026: jeder Eintrag mit Symbol)
    Gather.BuildSection(ns.Icons.Root(sub, "gather"), mapID)
    return "menu"
end

---------------------------------------------------------------------------
-- Minikarte: Einträge im Abschnitt „ezMap“ des Menüs „Aufspüren“ (SAM-11)
---------------------------------------------------------------------------

-- Arten mit einer Suche im Menü „Aufspüren“ (ezCore Core.Gathering.TRACKING_SPELLS: Kräuter- und Mineraliensuche)
Gather.SEARCH_KINDS = { "herb", "ore" }

-- „Nur bei aktiver Suche“: gilt für Kräuter und Erze auf der Minikarte der Modus „Bei aktiver Suche“?
function Gather.MiniSearchOnly()
    for _, kind in ipairs(Gather.SEARCH_KINDS) do
        if Gather.Mode(kind, "minimap") ~= "tracking" then return false end
    end
    return true
end

-- an: Kräuter und Erze nur bei aktiver Suche; die Modi davor merkt ezMap (ezMapDB.gatherMiniPrev[art]). aus: die
-- gemerkten Modi zurück, ohne gemerkten Modus „Mit Beruf“ (ezCores zweiter Standard je Art)
function Gather.SetMiniSearchOnly(on)
    local db = type(ns.db) == "table" and ns.db or {}
    if type(db.gatherMiniPrev) ~= "table" then db.gatherMiniPrev = {} end
    local prev = db.gatherMiniPrev
    for _, kind in ipairs(Gather.SEARCH_KINDS) do
        if on then
            local mode = Gather.Mode(kind, "minimap")
            if mode ~= "tracking" then prev[kind] = mode end
            Gather.SetMode(kind, "tracking", "minimap")
        else
            local mode = prev[kind]
            if type(mode) ~= "string" or mode == "tracking" then mode = "profession" end
            Gather.SetMode(kind, mode, "minimap")
            prev[kind] = nil
        end
    end
    return Gather.MiniSearchOnly()
end

-- Erklärung je Art für die Minikarte: Schalter-Tooltip plus, warum die Art dort gerade unsichtbar ist
function Gather.MiniKindTip(kind)
    local tip = L["OPT_" .. Gather.MINI_KEY[kind] .. "_TIP"]
    local ok, why = Gather.KindState(kind, "minimap")
    if not ok and STATE_TEXT[why] then tip = tip .. "\n\n" .. L[STATE_TEXT[why]]:format(KindLabel(kind)) end
    return tip
end

-- Eintrag ausgrauen (Blizzards SetEnabled am Menüeintrag; kennt er es nicht, bleibt er klickbar, die Erklärung steht)
local function Disable(entry)
    if type(entry) ~= "table" then return entry end
    if type(entry.SetEnabled) == "function" then pcall(entry.SetEnabled, entry, false) end
    entry.ezDisabled = true
    return entry
end

-- Zeile zum Stand der Minikarte (aus ezCore: gesetzte Punkte und Punkte der Karte) → Text, Erklärung
function Gather.MiniStateText()
    local P = Pins()
    local state = P and type(P.MinimapState) == "function" and P.MinimapState() or nil
    if type(state) ~= "table" then return nil end
    if state.on then return L.GMAP_MINI_STATE:format(ns.Num(state.shown) or 0, ns.Num(state.total) or 0), L.GMAP_MINI_STATE_TIP end
    local reason = state.reason and Core.L["MINIPINS_REASON_" .. tostring(state.reason)] or tostring(state.reason)
    return L.GMAP_MINI_OFF:format(reason), L.GMAP_MINI_STATE_TIP
end

-- Gruppe „Sammel-Fundorte auf der Minikarte“ (Gruppe gatherMini des Baums; Kisten als eigener Eintrag daneben, sie sind
-- Entdecker-Wissen) samt Untermenü je Art („Wann zeigen“ für die
-- Fläche „minimap“), dazu „Nur bei aktiver Suche“. Fehlt der Sichtradius, beide ausgegraut mit Erklärung.
-- → Gruppen-Eintrag, Grund des Ausgrauens oder nil
function Gather.AddMiniMenu(root)
    local Menu = Core.Menu
    if not GatherAPI() then return nil end
    local why = Gather.MiniUnavailable()
    local Tree = ns.Tree
    local state, onCount, total = Tree.State("gatherMini")
    local label = L.GMAP_MINI_GROUP
    if state == "mixed" then label = L.TREE_MIXED_LABEL:format(label, onCount, total) end
    local group = Menu.Toggle(root, label, function() return Tree.Checked("gatherMini") end,
        function() Tree.Click("gatherMini") end)
    ns.Icons.Apply(group, Tree.Icon("gatherMini"))          -- Symbole wie im Baum (Welle 27)
    local groupTip = Tree.Tip("gatherMini")
    if why then groupTip = groupTip .. "\n\n" .. L["GMAP_MINI_UNAVAILABLE_" .. why] end
    Tip(group, label, groupTip)
    -- Kisten: Entdecker-Wissen, eigener Eintrag neben der Gruppe (deren Haken schaltet sie nicht mit)
    local chestKey = Gather.MINI_KEY.chest
    local chest = Menu.Toggle(root, L.GMAP_MINI_CHEST, function() return ns.Enabled(chestKey) end,
        function(on) Tree.SetLeaf(chestKey, on) end)
    ns.Icons.Apply(chest, Tree.Icon(chestKey))
    local chestTip = Gather.MiniKindTip("chest") .. "\n\n" .. L.GMAP_MINI_CHEST_NOTE
    if why then chestTip = chestTip .. "\n\n" .. L["GMAP_MINI_UNAVAILABLE_" .. why] end
    Tip(chest, L.GMAP_MINI_CHEST, chestTip)
    local search = ns.Icons.Apply(Menu.Toggle(root, L.GMAP_MINI_SEARCH, Gather.MiniSearchOnly,
        function(on) Gather.SetMiniSearchOnly(on) end), "gatherMiniSearch")     -- eigenes Symbol (17.11.2026)
    local searchTip = L.GMAP_MINI_SEARCH_TIP
    if why then searchTip = searchTip .. "\n\n" .. L["GMAP_MINI_UNAVAILABLE_" .. why] end
    Tip(search, L.GMAP_MINI_SEARCH, searchTip)
    if why then
        Disable(group)
        Disable(chest)
        Disable(search)
        return group, why
    end
    local other = Gather.Other()
    local inGroup = ns.Icons.Root(group, "gatherMini")      -- Hinweise in der Gruppe mit Symbol (17.11.2026)
    if other then
        local text = L.GMAP_OTHER:format(other)
        ns.MapButton.OtherTitle(inGroup, text, L.GMAP_OTHER_TIP)
        ns.MapButton.Toggle(inGroup, L.OPT_gatherOverride, "gatherOverride")
    end
    -- je Art „Wann zeigen“ für die Minikarte: in der Gruppe nur deren Arten (Baum-Gruppe gatherMini), Kisten am
    -- eigenen Eintrag – so passt der Zähler „(teilweise: n von m)“ zu den Einträgen darunter
    -- (Kisten haben nur „Immer“ und damit kein „Wann zeigen“: Nr. 87 der Einstellungs-Prüfung vom 19.11.2026)
    local function WhenMenu(entry, k)
        if not Gather.HasModes(k) then return end
        Tip(Menu.Title(entry, L.GMAP_WHEN), L.GMAP_WHEN, L.GMAP_MINI_WHEN_TIP)
        for _, mode in ipairs(Gather.MODES[k]) do
            local mtext = L["GMAP_MODE_" .. mode]
            Tip(Menu.Radio(entry, mtext, function() return Gather.Mode(k, "minimap") end,
                function(m) Gather.SetMode(k, m, "minimap") end, mode), mtext, L["GMAP_MODE_" .. mode .. "_TIP"])
        end
    end
    local kindOf = {}
    for kind, key in pairs(Gather.MINI_KEY) do kindOf[key] = kind end
    for _, child in ipairs(Tree.Children("gatherMini")) do
        local key = child.key
        local kind = key and kindOf[key]
        if kind then
            local text = KindLabel(kind)
            local entry = Menu.Toggle(group, text, function() return ns.Enabled(key) end, function(on) Tree.SetLeaf(key, on) end)
            Tip(entry, text, Gather.MiniKindTip(kind))
            ns.Icons.Apply(entry, Tree.Icon(key))
            WhenMenu(entry, kind)
        end
    end
    WhenMenu(chest, "chest")
    local text, tip = Gather.MiniStateText()
    if text then Tip(Menu.Title(inGroup, text), text, tip) end
    return group
end

-- In Blizzards Kartenfilter (einmal angemeldet; Blizzard ruft die Ergänzung bei jedem Öffnen): seit dem Baum
-- (Tree.lua) der ganze Baum von ezMap – „Alles“, darunter die Gruppen als Untermenüs; die Sammel-Arten stehen mit
-- „Wann zeigen“ und den einzelnen Vorkommen in der Gruppe „Sammeln“, Kisten unter „Entdecker-Wissen“. Seit dem
-- 18.11.2026 nur mit dem Schalter mapFilterSection (ab Werk aus) oder ohne ezMap-Knopf (Gather.FilterWanted): Blizzard
-- kennt kein Abmelden einer Ergänzung, also prüft sie bei jedem Öffnen und lässt Blizzards Menü sonst unverändert.
function Gather.BuildFilter(root)
    if not Gather.FilterWanted() then return false end
    Gather.blizzardMenuSeen = true
    local Menu = Core.Menu
    Menu.Divider(root)
    Tip(Menu.Title(root, L.TREE_SECTION), L.TREE_SECTION, L.TREE_SECTION_TIP)
    ns.Tree.AddAll(root, ShownMapID())
    return true
end

-- Die Arten im Baum: jedes Blatt baut seinen Eintrag samt Untermenü („Wann zeigen“, einzelne Vorkommen) selbst;
-- Kopf und Fuß des Abschnitts hängen an der Gruppe „Sammeln“
for _, kind in ipairs(Gather.KINDS) do
    local k = kind
    ns.Tree.LEAF_MENU[Gather.KEY[k]] = function(root, mapID) return AddKind(root, k, mapID) end
end
ns.Tree.GROUP_BEFORE.gather = function(entry) Gather.SectionHead(entry) end
-- Minikarte (SAM-11): eigene Gruppe unter „Sammeln“, Kisten unter „Entdecker-Wissen“
ns.Tree.Add("gather", { id = "gatherMini", children = { { key = "gatherMiniHerb" }, { key = "gatherMiniOre" },
    { key = "gatherMiniFish" } } })
ns.Tree.Add("explorer", { key = "gatherMiniChest" }, "bookTargets")
-- Nach Farbe (Teilwelle 15b): Filtergruppe unter „Sammeln“ – zählt nicht zum Zustand von „Sammeln“ und „Alles“.
-- „Rot – noch nicht abbaubar“ seit der Einstellungs-Prüfung vom 19.11.2026 (Nr. 88; vorher „Nur, was ich abbauen kann“)
ns.Tree.Add("gather", { id = "gatherColor", filter = true, children = { { key = "gatherColorOrange" },
    { key = "gatherColorYellow" }, { key = "gatherColorGreen" }, { key = "gatherColorGray" },
    { key = "gatherColorRed" }, { key = "gatherColorUnknown" } } })
ns.Tree.GROUP_MENU.gather = function(entry, mapID)
    Gather.SectionFoot(entry, mapID)
    if ns.Route then ns.Route.AddMenu(entry, mapID) end    -- „Route durch diese Zone“ (SAM-21)
end

Gather.registered = false
function Gather.Register()
    local blizzardMenu = rawget(_G, "Menu")
    if Gather.registered or not (type(blizzardMenu) == "table" and type(blizzardMenu.ModifyMenu) == "function") then
        return Gather.registered
    end
    Gather.registered = pcall(blizzardMenu.ModifyMenu, Gather.TAG, function(_, root)
        ns.Try("GatherFilter", Gather.BuildFilter, root)
    end)
    return Gather.registered
end

---------------------------------------------------------------------------
-- Schnittstelle ShowGather (SAM-14): ezCore.API("ezMap").ShowGather({ gegenstand | art, karte })
---------------------------------------------------------------------------

local function PlayerZone()
    local mapID = Core.PlayerPosition()
    if not mapID then return nil end
    return (Core.Map.Parent(mapID, "Zone")) or mapID
end

-- Schlüssel eines Angel-Gebiets (Zahl, wo es geht – Drops und Orte führen dieselbe Nummer)
local function AreaKey(area) return ns.Num(area) or area end

-- Angel-Gebiete, in denen der Gegenstand gefangen wurde → { [Speicherkarte] = { [Gebiet] = true } } oder nil.
-- Seit Welle 23 (A8) eine Weiterleitung auf ezCore (Core.Gathering.FishAreasFor); Gather.Find braucht sie nicht mehr,
-- weil der Filter item von Core.Gathering.Nodes die Angelplätze selbst einbezieht.
local function FishAreasOf(item)
    local G = GatherAPI()
    if not (item and G and type(G.FishAreasFor) == "function") then return nil end
    local out
    for store, areas in pairs(G.FishAreasFor(item) or {}) do
        for area in pairs(type(areas) == "table" and areas or {}) do
            out = out or {}
            out[store] = out[store] or {}
            out[store][AreaKey(area)] = true
        end
    end
    return out
end
Gather.FishAreasOf = FishAreasOf

-- Fundorte zum Filter aus ShowGather ({ item, kind }) auf der Karte mapID über ezCore: Spielobjekte und – seit
-- Welle 23 (A8) im selben Aufruf – Angelplätze eines Gegenstands (Fang im Gebiet; vorher glich ezMap die Fang-Gebiete
-- selbst ab). Kisten (Entdecker-Wissen) nur auf Wunsch (ChestsWanted) – auch Altbestand-Objekte ohne obj-Satz, die
-- ezCore als Kiste ohne Entdecker-Merkmal führt. → Liste der Knoten
function Gather.Find(mapID, filter)
    local G = GatherAPI()
    mapID = ns.Num(mapID)
    if not (G and mapID and type(filter) == "table") then return {} end
    local chests = ChestsWanted()
    local out = {}
    for _, node in ipairs(G.Nodes(mapID, { item = filter.item, kind = filter.kind, explorer = chests or nil })) do
        if node.kind ~= "chest" or chests then out[#out + 1] = node end
    end
    return out
end

-- Erlaubte Karte (Zone und darunter) mit den meisten Fundorten unter der Karte parent (nach Speicherkarte) → uiMapID
local function BestUnder(parent, filter)
    local count, allowed, best, bestN = {}, {}, nil, 0
    for _, node in ipairs(Gather.Find(parent, filter)) do
        local m = ns.Num(node.map)
        if m and allowed[m] == nil then allowed[m] = Gather.MapAllowed(m) end
        if m and allowed[m] then
            count[m] = (count[m] or 0) + 1
            if count[m] > bestN or (count[m] == bestN and m < best) then best, bestN = m, count[m] end
        end
    end
    return best
end

-- Beste Karte für den Filter: die genannte (eine Welt- oder Kontinentkarte: die Zone darunter mit den meisten Punkten),
-- sonst deine Zone (wenn sie Fundorte hat), sonst für einen Gegenstand die Zone mit den meisten eigenen Ernten
-- (Core.Finds.Of), für eine Art die Zone deines Kontinents mit den meisten Punkten
function Gather.BestMap(filter, mapID)
    if not GatherAPI() then return nil end
    mapID = ns.Num(mapID)
    if mapID then
        local zone = Core.Map.Parent(mapID, "Zone") or mapID
        if Gather.MapAllowed(zone) then return #Gather.Find(zone, filter) > 0 and zone or nil end
        return BestUnder(mapID, filter)
    end
    local zone = PlayerZone()
    if zone and Gather.MapAllowed(zone) and #Gather.Find(zone, filter) > 0 then return zone end
    if filter.item then
        local F = Core.Finds
        for _, e in ipairs(F and type(F.Of) == "function" and F.Of(filter.item) or {}) do
            local m = ns.Num(e.mapID)
            if m and (ns.Num(e.points) or 0) > 0 and Gather.MapAllowed(m) and #Gather.Find(m, filter) > 0 then return m end
        end
        return nil
    end
    local continent = zone and Core.Map.Parent(zone, "Continent")
    if not continent then return nil end
    return BestUnder(continent, filter)
end

-- Nächster Punkt auf der Karte mapID: vom Spieler aus, sonst der am häufigsten geerntete → Knoten, Zahl der Fundorte
local function Nearest(filter, mapID)
    local list = Gather.Find(mapID, filter)
    local where, x, y = Core.PlayerPosition(mapID)
    local w, h = Yards(mapID)
    local best, bestD
    if where == mapID and x and y and w and h then
        for _, node in ipairs(list) do
            local d = ((node.x - x) * w) ^ 2 + ((node.y - y) * h) ^ 2
            if not bestD or d < bestD then best, bestD = node, d end
        end
        if best then return best, #list end
    end
    for _, node in ipairs(list) do
        if not best or (ns.Num(node.cnt) or 0) > (ns.Num(best.cnt) or 0) then best = node end
    end
    return best, #list
end

local function MapShown(map)
    return type(map) == "table" and type(map.IsShown) == "function" and map:IsShown() and true or false
end

-- Öffnet die Weltkarte auf mapID → true nur, wenn sie danach offen ist. Über ezCores zentralen Helfer
-- Core.OpenPanel("map", …) (V-169, wie ezCraft/Where.lua): der ruft Blizzards OpenWorldMap(mapID) und fällt ohne sie
-- auf Blizzards ToggleWorldMap zurück – nie ShowUIPanel oder WorldMapFrame:SetMapID aus ezMap (Prüfung auf Blizzards
-- Regeln vom 17.11.2026, Risiko 21: beides gilt als Taint-Weg). OpenWorldMap kehrt bei Blizzards Spielregel
-- WorldMapDisabled ohne Öffnen zurück, und ezMap umgeht das nicht. Im Kampf öffnet der Helfer nichts (still, Gather.Show
-- holt es nach dem Kampf nach). Fehlt OpenWorldMap, ruft der Helfer ToggleWorldMap ohne mapID
-- (ezCore/Kern/Panels.lua, Eintrag „map“): die Karte öffnet dann auf der Zone, die Blizzard wählt, nicht auf mapID,
-- und Gather.OpenMap meldet trotzdem true – ezMap stellt die Zone mit Absicht nicht nach (Fund 6 des
-- code-reviewers vom 17.11.2026; kein SetMapID, Risiko 21).
function Gather.OpenMap(mapID)
    if not Core.OpenPanel("map", mapID, true) then return false end
    return MapShown(rawget(_G, "WorldMapFrame"))
end
local OpenMap = Gather.OpenMap

function Gather.FocusLabel()
    local f = Gather.focus
    if not f then return "" end
    if f.item then return Core.ItemNameByID(f.item) or ("#" .. f.item) end
    return KindLabel(f.kind)
end

-- opts = { gegenstand | item = itemID oder Link, art | kind = "herb" | "ore" | "fish" | "chest", karte | map = uiMapID }
-- → true, { map, x, y, name, count, other, later, marked, markError } oder false, Grund ("args" | "kind" | "explorer" |
-- "nocore" | "none" | "nomap")
function Gather.Show(opts)
    opts = type(opts) == "table" and opts or {}
    if not GatherAPI() then return false, "nocore" end
    local item = Core.ItemID(opts.gegenstand or opts.item)
    local kind = opts.art or opts.kind
    if kind ~= nil and not Gather.KEY[kind] then return false, "kind" end
    if not (item or kind) then return false, "args" end
    -- Kisten sind Entdecker-Wissen (Leitlinie 11): nur mit ezMaps Haken „Kisten“ oder ezCores „Entdecker-Wissen“
    if kind == "chest" and not ChestsWanted() then return false, "explorer" end
    local filter = { item = item, kind = kind }
    local map = Gather.BestMap(filter, opts.karte or opts.map)
    if not map then return false, "none" end
    local node, count = Nearest(filter, map)
    if not node then return false, "none" end
    Gather.focus = { item = item, kind = kind, map = map }
    local name = Gather.Facts(node).name
    local info = { map = map, x = node.x, y = node.y, name = name, count = count, other = Gather.Yields() }
    -- Blizzard erlaubt die Markierung nicht auf jeder Karte (C_Map.CanSetUserWaypointOnMap): dann marked = false
    local marked, markError = ns.Way.Set(map, node.x, node.y, name)
    info.marked = marked and true or false
    if not marked then info.markError = markError end
    if ns.InCombat() then
        info.later = true
        ns.AfterCombat(function()
            if OpenMap(map) then Gather.Refresh() else Gather.ClearFocus() end
        end, "ShowGather")
        return true, info
    end
    if not OpenMap(map) then
        Gather.focus = nil
        return false, "nomap"
    end
    Gather.Refresh()
    return true, info
end

---------------------------------------------------------------------------
-- Status, Anmeldung, Neuaufbau
---------------------------------------------------------------------------

function Gather.StatusLine()
    if not (GatherAPI() and Pins()) then return L.STATUS_GATHER_NOCORE end
    local other = Gather.Other()
    if not Gather.AnyKind() then
        return L.STATUS_GATHER_OFF .. (other and (" " .. L.STATUS_GATHER_OTHER_TOO:format(other)) or "")
    end
    if other and not ns.Enabled("gatherOverride") then return L.STATUS_GATHER_OTHER:format(other) end
    local kinds = {}
    for _, kind in ipairs(Gather.KINDS) do
        if Gather.KindState(kind) then kinds[#kinds + 1] = KindLabel(kind) end
    end
    local line = L.STATUS_GATHER_ON:format(#kinds > 0 and table.concat(kinds, ", ") or L.STATUS_GATHER_NONE)
    -- Minikarte (SAM-11): Arten, sonst der Grund
    local mini = {}
    for _, kind in ipairs(Gather.KINDS) do
        if Gather.KindState(kind, "minimap") then mini[#mini + 1] = KindLabel(kind) end
    end
    local on, why = Gather.MiniActive()
    if on then
        line = line .. " " .. L.STATUS_GATHER_MINI:format(#mini > 0 and table.concat(mini, ", ") or L.STATUS_GATHER_NONE)
        -- nur, wenn ezCore das Feld hideNear kennt (Fähigkeitsmarke; ein älterer ezCore übergeht es still, Gegenprüfung
        -- vom 18.11.2026) – sonst meldete die Zeile ein Ausblenden, das nicht stattfindet
        local P = Pins()
        local near = P and P.HIDE_NEAR == true and Gather.HideNear()
        if near then line = line .. " " .. L.STATUS_GATHER_NEAR:format(Core.L.GATHER_YARDS:format(near)) end
    else
        line = line .. " " .. L.STATUS_GATHER_MINI_OFF:format(L["GMAP_MINI_WHY_" .. tostring(why)] or tostring(why))
    end
    -- Nach Farbe (Teilwelle 15b): welche Farben ausgeblendet sind
    local off = {}
    for _, color in ipairs(Gather.COLORS) do
        if not ns.Enabled(Gather.COLOR_KEY[color]) then off[#off + 1] = Core.L["GATHER_COLOR_" .. color] or color end
    end
    if Gather.SkillOnly() then off[#off + 1] = Core.L.GATHER_COLOR_red end     -- „Rot – noch nicht abbaubar“ (Nr. 88)
    if #off > 0 then line = line .. " " .. L.STATUS_GATHER_COLORS:format(table.concat(off, ", ")) end
    local zone = PlayerZone()
    if zone then line = line .. " " .. L.STATUS_GATHER_ZONE:format(Gather.Total(zone), ns.MapName(zone)) end
    if other then line = line .. " " .. L.STATUS_GATHER_OVERRIDE:format(other) end
    return line
end

ns.AddStatusLine(function() return Gather.StatusLine() end)

local function Hook()
    local map = rawget(_G, "WorldMapFrame")
    if Gather.hooked or type(map) ~= "table" or type(map.HookScript) ~= "function" then return end
    Gather.hooked = true
    map:HookScript("OnHide", function() ns.Try("GatherFocus", Gather.ClearFocus) end)
end

-- Nach dem Abdunkeln wieder hell zeichnen (ein Neuaufbau je Ernte, gatherDim Minuten später)
local function AfterDim()
    local minutes = ns.Num(ns.S.gatherDim) or 0
    if minutes > 0 and C_Timer and C_Timer.After then
        C_Timer.After(minutes * 60 + 1, function() ns.Try("GatherDim", Gather.Refresh) end)
    end
end

function Gather.Init()
    local P = Pins()
    if not (P and GatherAPI()) then return false end
    P.AddProvider(Gather.PROVIDER, {
        owner = "ezMap",
        punkte = function(mapID) return Gather.Points(mapID) end,
        minikarte = Gather.MiniPoints,
        hideNear = Gather.HideNear,     -- in der Nähe auf der Minikarte auslassen (Wunsch vom 18.11.2026)
        sichtbar = function(mapID, surface)
            if surface == "minimap" then return (Gather.MiniActive()) end
            return (Gather.Active(mapID))
        end,
        tooltip = Gather.Tooltip,
        klick = Gather.Click,
        menu = Gather.Menu,
    })
    Gather.Register()
    ns.WhenAddOnLoaded("Blizzard_WorldMap", function() ns.Try("GatherHook", Hook) end)
    Core.Listen("GATHERING_CHANGED", function() Gather.ForgetFacts() Gather.Refresh() end, "ezMap.Gather")
    -- ein „Nie“ in ezCores Modus (gespeichert oder später eingespielt) gleich umstellen (Nr. 86, 87, 99)
    Gather.NormalizeModes()
    Core.Listen("GATHERING_VISIBILITY", function()
        Gather.NormalizeModes()
        Gather.Refresh()
    end, "ezMap.Gather")
    Core.Listen("GATHERING_HARVEST", function() Gather.Refresh() AfterDim() end, "ezMap.Gather")
    Core.Listen("OTHER_ADDONS_CHANGED", function() Gather.Refresh() end, "ezMap.Gather")
    -- Farbe je Fundort hängt an der eigenen Fertigkeit (Teilwelle 15b): neu zeichnen, wenn sie steigt
    Core.Listen("PROFESSIONS_CHANGED", function() Gather.Refresh() end, "ezMap.Gather")
    return true
end

ns.OnReady(function() ns.Try("Gather", Gather.Init) end)

local SETTINGS = { gatherMiniHerb = true, gatherMiniOre = true, gatherMiniFish = true, gatherMiniChest = true,
    gatherMiniSize = true, gatherMiniAlpha = true, gatherHerb = true, gatherOre = true, gatherFish = true, gatherChest = true,
    gatherShip = true,
    gatherColorRed = true, gatherSize = true, gatherAlpha = true, gatherDim = true, gatherOverride = true,
    gatherColorOrange = true, gatherColorYellow = true, gatherColorGreen = true, gatherColorGray = true,
    gatherColorUnknown = true }
ns.OnSettingChanged(function(key)
    if SETTINGS[key] then Gather.Refresh() end
    -- Ausblenden in der Nähe: nur die Lage auf der Minikarte neu setzen (ezCore fragt Gather.HideNear dabei)
    if key == "gatherHideNearYards" then
        local P = Pins()
        if P and type(P.MinimapUpdate) == "function" then P.MinimapUpdate() else Gather.Refresh() end
    end
end)
