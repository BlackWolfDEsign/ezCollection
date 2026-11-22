local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Inhalt geöffneter Behälter im Tooltip (Frage des Nutzers vom 22.11.2026 an einer Schließkassette, wörtlich „sollte
    ezloot bei solchen gegenständen nicht die möglichen loot anzeigen?“, nachgereicht „ebenso muscheln und co“ und
    „das gilt auch für kisten, truhen und co“; Plan in docs/roadmap/ezLoot.md, „Erledigt: Inhalt von Behältern“).
      Gegenstände   alles, was sich in der Tasche öffnen lässt und dabei Blizzards Plündernfenster zeigt:
                    Schließkassetten, Muscheln, Säcke und Kisten aus Quests, Beutel … (Abschnitt im Gegenstands-Tooltip)
      Spielobjekte  Kisten und Truhen in der Welt (ezCores Art chest bzw. container; nicht Kräuter, Erz, Schwärme und
                    Quest-Objekte – deren Ertrag nennen ezMap und ezCore) im Tooltip beim Draufzeigen
      „Inhalt bei dir: 5× geöffnet“                 Ø Gold rechts, wenn Gold darin lag
        [Symbol] Gegenstand          3× bei 5 geöffneten
        … und 4 weitere (Umschalt)
    Ohne Shift drei Gegenstände, mit Shift acht (wie „Mögliche Beute“ am Gegner, Entscheidung zu Welle 2b), mit Shift
    dazu die Menge („zusammen m“), das Gold und „Gezählt bei dir und deinen Charakteren – eine Zählung, keine Dropchance“.
    Die Zeilen baut Drops.Lines (eine Stelle für Gegner und Behälter, what = "opens").

    Datenquellen (Leitlinie 11), in dieser Reihenfolge geprüft am 22.11.2026:
      1. Client: Forever liefert keine Beutetabellen, auch nicht für Behälter und Kisten (wie am Gegner, Drops.lua).
      2. Datenbank eines installierten Addons: AtlasLoot Classic Forever (GPL-2, Lesen erlaubt) führt keine Inhalte von
         Behältern oder Kisten – nur Bossbeute, Rezepte und eine Zuordnung Gegenstand » Quelle; QuestieDB kennt nur
         Quest-Gegenstände und nur die Richtung Gegenstand » Behälter bzw. Objekt (Item.itemDrops, Item.objectDrops;
         ezCores „Herkunft laut Questie“). Eine Umkehr bräuchte eine Suche über alle Gegenstände wie die vorbereitete,
         ab Werk ausgeschaltete Beute laut Questie am Gegner (DG-16, wartet auf die Messung DG-13) – Entscheidungsfrage 9.
      3. Selbst Gesammeltes: ezCores Entdecker-Datenbank zählt jedes Plündernfenster je Quelle (GetLootSourceInfo »
         Keys.Source): Gegenstands-GUID » Art „container“ (Raum item), Spielobjekt » Art „object“ (Raum obj, Art des
         Objekts in obj[id].kind); kontoweit, mit Mengen und Gold; Zerlegen ausgenommen (eigene Tabelle salvage).
         ezLoot liest nur über Core.Drops.Of – keine eigene Liste, keine eigene Rechnung. Ist „Datenbank: Erlebtes
         sammeln“ aus, bleibt das schon Gezählte sichtbar.
    Zusätzlich laut Questie (Entscheidung des Nutzers vom 22.11.2026, wörtlich: „zusätzlich „laut Questie““): unter
    dem selbst Gezählten „Kann enthalten (laut Questie, ohne Chance)“ mit den Gegenständen, die QuestieDB in diesem
    Behälter bzw. dieser Kiste kennt und die bei dir dort noch nicht lagen – drei, mit Shift acht. Gefragt über ezCores
    Core.Sources.ContentsOf (Umkehr-Index über QuestieDB zur Laufzeit, SourcesQuestie.lua); ezLoot liest QuestieDB
    nie selbst (Leitlinie 10). Ohne eigene Öffnung steht nur diese Liste da.
    Entdecker-Wissen (Leitlinie 11): Wo Kisten stehen, zeigt ezMap nur auf Wunsch. Der Inhalt der Kiste, auf die du
    gerade zeigst, ist Nachschlage-Wissen (Vorgabe des Auftrags vom 22.11.2026) – er steht ohne den Schalter
    „Entdecker-Wissen“ da.
    Nie oder nur leer geöffnet, unstimmige Zählung, gesperrte ID, ein Objekt-Name, den mehrere bekannte Objekte tragen,
    Ausrüstung, Erz und Kräuter (Ziele von Entzaubern, Sondieren, Mahlen – verpasst ezCore den Zauber, landete ihr
    Ergebnis sonst als „Inhalt“ beim Ausgangsgegenstand; Review vom 22.11.2026): keine Zeile, auch keine Leerzeile.
    Schalter „itemContents“ (ab Werk an) für beide, /ezl inhalt bzw. /ezl contents, Zeile in /ezl status. Plätze
    „contents“ in Core.Tooltip.ORDER (hinter „loot“) und Core.Tooltip.OBJECT_ORDER (hinter „quest“), mit Abstand davor.

      Contents.Available()             → hat dieses ezCore die Zählung? (sonst keine Zeile)
      Contents.Get(itemID)             → Zusammenfassung { loots, items = { { id, n, times, q } … }, money, moneyLoots,
                                         moneyAvg, what = "opens" } oder nil, dazu als zweiter Wert die Liste laut einer
                                         Addon-Datenbank { label, items = { { id } … } } oder nil; Contents.GetObject
                                         (objectID) ebenso. Zwischengespeichert wie ItemLoot.Get (Frist CACHE_TIME, Stand
                                         der Datenbank Drops.DbVersion), nicht solange die Datenbank noch lädt oder
                                         Questies Index noch läuft; QUESTIE_CONTENTS leert ihn und zeichnet neu
      Contents.Lines(itemID, long), Contents.ObjectLines(objectID, long) → Zeilen { left, right, r, g, b }
      Contents.ObjectFor(name)         → objectID des gezeigten Objekts (softinteract, sonst eindeutig über den Namen)
      Contents.AddSection(tooltip, itemID), Contents.AddObjectSection(tooltip, name) → Zahl der Zeilen
]]

local C = {}
ns.Contents = C

C.ITEM_KIND, C.OBJECT_KIND = "container", "object"   -- Arten in ezCores Entdecker-Datenbank (DBKeys.lua, Keys.KINDS)
C.OBJECT_KINDS = { chest = true, container = true }  -- Kisten und neutrale Behälter (Discovery.LootKind)
-- Gegenstandsklassen, die kein Behälter sind, aber Ziel eines Zerlege-Zaubers: Waffe 2, Rüstung 4, Handwerkswaren 7
C.NOT_CONTAINER = { [2] = true, [4] = true, [7] = true }
C.LIMITS = { short = 3, long = 8, rest = true }       -- Gegenstände ohne bzw. mit Shift; Rest-Zeile auch ohne Shift
C.CACHE_TIME = 60           -- Sekunden (Sicherheitsnetz; ein neuer Stand der Datenbank macht den Eintrag alt)
C.CACHE_MAX = 200           -- Einträge im Zwischenspeicher; darüber wird er geleert (wie ItemLoot.lua)

local Num = Core.Num
local Clock = Core.Uptime
local cache, cached = {}, 0 -- ["container:4632"] = { s = Zusammenfassung | false, at, ver }

function C.Available()
    local DR = Core.Drops
    return type(DR) == "table" and type(DR.Of) == "function" and type(DR.Denominator) == "function"
end

-- Zählung dieser Quelle in die Form der Zusammenfassung des Gegner-Tooltips (Drops.FromCounts prüft sie: Zähler
-- über dem Nenner, unstimmige Gruppenfenster, gesperrte Werte – dann nil).
function C.Summarize(kind, id)
    local ok, total = pcall(Core.Drops.Of, kind, id)
    if not ok or ns.IsSecret(total) or type(total) ~= "table" then return nil end
    local s = { drops = total, items = {}, loots = 0, money = 0, moneyLoots = 0 }
    if not ns.Drops.FromCounts(s, { stale = true }) then return nil end
    if #s.items == 0 and s.money <= 0 then return nil end   -- nur leer geöffnet: keine Zeile
    s.what = "opens"                                         -- Tode gibt es an Behältern nicht
    s.moneyAvg = s.loots > 0 and math.floor(s.money / s.loots + 0.5) or 0
    return s
end

-- Art der eigenen Zählung » Art in Core.Sources.ContentsOf
C.SOURCE_KIND = { container = "item", object = "object" }

-- Liste laut einer Addon-Datenbank (heute QuestieDB über ezCore), ohne die Gegenstände, die schon in der eigenen
-- Zählung s stehen. → Liste | nil, wartet (true: die Quelle hat noch nicht nachgesehen – Questies Index läuft)
function C.Listed(kind, id, s)
    local S = Core.Sources
    if not (type(S) == "table" and type(S.ContentsOf) == "function") then return nil end
    local ok, res = pcall(S.ContentsOf, C.SOURCE_KIND[kind], id)
    if not ok then return nil end            -- Fehler: der Grund stammte von einer früheren Frage
    if ns.IsSecret(res) or type(res) ~= "table" or type(res.items) ~= "table" then
        local okWhy, why = false, nil
        if res == nil and type(S.Reason) == "function" then okWhy, why = pcall(S.Reason, "contentsOf") end
        return nil, okWhy and why == "skip"
    end
    local own = {}
    for _, item in ipairs(type(s) == "table" and s.items or {}) do own[item.id] = true end
    local items = {}
    for _, it in ipairs(res.items) do
        local itemID = type(it) == "table" and not ns.IsSecret(it.id) and Num(it.id) or nil
        if itemID and itemID > 0 and not own[itemID] then items[#items + 1] = { id = itemID } end
    end
    if #items == 0 then return nil end
    local label
    if type(S.Label) == "function" then
        local okLabel, text = pcall(S.Label, res)
        label = okLabel and not ns.IsSecret(text) and type(text) == "string" and text or nil
    end
    return { label = label or L.CONTENTS_SOURCE_UNKNOWN, items = items }
end

local function Cached(kind, id)
    if ns.IsSecret(id) then return nil end
    id = Num(id)
    if not (id and id > 0 and C.Available()) then return nil end
    local key = kind .. ":" .. id
    local c = cache[key]
    if c and Clock() - c.at < C.CACHE_TIME and c.ver == ns.Drops.DbVersion() then return c.s or nil, c.q or nil end
    local s = C.Summarize(kind, id)
    local q, waiting = C.Listed(kind, id, s)
    -- Datenbank lädt noch (nach dem Einloggen) oder Questies Index läuft: nicht merken, sonst bliebe der Tooltip bis
    -- zur Frist leer
    if waiting or ns.Drops.DbState() == "wait" then return s, q end
    if not c then
        -- höchstens CACHE_MAX Einträge (Stöbern im Auktionshaus oder in der Bank)
        if cached >= C.CACHE_MAX then wipe(cache); cached = 0 end
        cached = cached + 1
    end
    cache[key] = { s = s or false, q = q or false, at = Clock(), ver = ns.Drops.DbVersion() }
    return s, q
end

-- Ausrüstung, Erz, Kräuter: nie ein Behälter (siehe Kopf). Unbekannte Klasse: kein Ausschluss.
function C.IsContainerItem(itemID)
    local _, _, _, _, _, classID = Core.ItemInstant(itemID, rawget(_G, "C_Item"))
    classID = not ns.IsSecret(classID) and Num(classID) or nil
    return not (classID and C.NOT_CONTAINER[classID])
end

function C.Get(itemID)
    if ns.IsSecret(itemID) or not C.IsContainerItem(itemID) then return nil end
    return Cached(C.ITEM_KIND, itemID)
end

function C.GetObject(objectID)
    if ns.IsSecret(objectID) then return nil end
    local F = Core.Finds
    if not (type(F) == "table" and type(F.ObjectKind) == "function") then return nil end
    local ok, kind = pcall(F.ObjectKind, objectID)
    if not ok or ns.IsSecret(kind) or not C.OBJECT_KINDS[kind] then return nil end
    return Cached(C.OBJECT_KIND, objectID)
end

function C.ClearCache() wipe(cache); cached = 0 end

local function LinesOf(s, q, long)
    local lines = {}
    if s then
        lines = ns.Drops.Lines(s, long, false, { short = C.LIMITS.short, long = C.LIMITS.long, rest = C.LIMITS.rest,
            shift = L.CONTENTS_SHIFT })
    end
    if q then
        for _, line in ipairs(ns.Drops.PossibleLines(q, long, false, { head = L.CONTENTS_LISTED:format(q.label),
            view = false })) do
            lines[#lines + 1] = line
        end
    end
    return lines
end

function C.Lines(itemID, long)
    local s, q = C.Get(itemID)
    return LinesOf(s, q, long)
end
function C.ObjectLines(objectID, long)
    local s, q = C.GetObject(objectID)
    return LinesOf(s, q, long)
end

-- Welches Objekt zeigt der Tooltip? ezCores Discovery.TargetObject (eine Stelle, Leitlinie 2): das in Reichweite
-- (softinteract) mit diesem Namen, sonst das eine bekannte Objekt dieses Namens. Tragen mehrere bekannte Objekte den
-- Namen (etwa „Ramponierte Truhe“ in vielen Stufen), nil – der Inhalt einer anderen Truhe wäre falsch. (Tooltip.ObjectID,
-- das die Pipeline als vierten Wert reicht, nimmt bei gleichem Namen das erste Objekt.)
function C.ObjectFor(name)
    if ns.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local D = Core.Discovery
    if not (type(D) == "table" and type(D.TargetObject) == "function") then return nil end
    local ok, id = pcall(D.TargetObject, name)
    return ok and not ns.IsSecret(id) and Num(id) or nil
end

local function ShiftDown() return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true end

local function Show(tooltip, lines)
    if #lines == 0 then return 0 end
    local T = Core.Tooltip
    if type(T) == "table" and type(T.Gap) == "function" then T.Gap(tooltip) end   -- eigene Gruppe: immer Abstand
    for _, line in ipairs(lines) do
        if line.right then
            tooltip:AddDoubleLine(line.left, line.right, line.r, line.g, line.b, line.rr or 1, line.rg or 1, line.rb or 1)
        else
            tooltip:AddLine(line.left, line.r, line.g, line.b, line.wrap == true)   -- wie der Gegner-Tooltip
        end
    end
    return #lines
end

function C.AddSection(tooltip, itemID)
    if not ns.Enabled("itemContents") then return 0 end
    local n = Show(tooltip, C.Lines(itemID, ShiftDown()))
    if n > 0 then C.shownItem = Num(itemID) end   -- Shift wechselt: ItemLoot.OnModifier zeichnet neu
    return n
end

-- Spielobjekte: Shift gilt beim Aufbau (Blizzards Objekt-Tooltip lässt sich nicht wie ein Gegenstand neu zeichnen)
function C.AddObjectSection(tooltip, name)
    if not ns.Enabled("itemContents") then return 0 end
    return Show(tooltip, C.ObjectLines(C.ObjectFor(name), ShiftDown()))
end

local tooltip = Core.Tooltip
if type(tooltip) == "table" and type(tooltip.AddItemSection) == "function" then
    tooltip.AddItemSection("ezLoot.contents", "contents", function(tip, itemID) C.AddSection(tip, itemID) end, ADDON)
end
if type(tooltip) == "table" and type(tooltip.AddObjectSection) == "function" then
    tooltip.AddObjectSection("ezLoot.contents", "contents", function(tip, name) C.AddObjectSection(tip, name) end, ADDON)
end

-- Questies Index ist fertig: Zwischenspeicher leeren und einen gerade gezeigten Gegenstands-Tooltip neu zeichnen –
-- sonst erschiene „laut Questie“ erst beim nächsten Draufzeigen. Nur bei „index“: Ein Fehlschlag kann synchron mitten
-- im Aufbau des Tooltips gemeldet werden (Start des Index); ein Neuzeichnen dort verdoppelte die Abschnitte
-- (Gegenprüfung 22.11.2026). Kisten in der Welt zeigen die Liste erst beim nächsten Draufzeigen (Objekt-Tooltips
-- lassen sich nicht neu zeichnen).
function C.OnQuestieContents(state)
    if state ~= "index" then return false end
    C.ClearCache()
    local tip = rawget(_G, "GameTooltip")
    if not (type(tip) == "table" and tip.IsShown and tip:IsShown() and tip.GetItem and tip.RefreshData) then return false end
    local ok, _, _, id = pcall(tip.GetItem, tip)
    if not ok or ns.IsSecret(id) or not Num(id) then return false end
    return pcall(tip.RefreshData, tip) == true
end
Core.Listen("QUESTIE_CONTENTS", function(_, state) C.OnQuestieContents(state) end, ADDON)
