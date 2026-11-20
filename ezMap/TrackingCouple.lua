local _, ns = ...
local Core = ezCore

--[[
    Blizzards Menü „Aufspüren“ und ezMaps Kartenfilter gemeinsam schalten (Kopplung C; Antwort des Nutzers vom
    17.11.2026 auf die Frage A/B/C, wörtlich „alles davon“, Wortlaut im ROADMAP-Index; Frage in docs/roadmap/ezMap.md).

    Schalter trackingCouple (OPT_trackingCouple, ab Werk aus, wie in der Frage): Hakst du in Blizzards Menü eine Art an
    oder ab, schaltet ezMap die passende Gruppe bzw. das Blatt seines Baums mit (Tree.Set) – und schaltest du in ezMap
    (Kartenfilter, ezMap-Knopf, Einstellungsseite) diese Gruppe, schaltet ezMap Blizzards Art über C_Minimap.SetTracking
    (über TrackingMemory.Set, nur Blizzards C-Schnittstelle, nichts in Blizzards Tabellen; Leitlinie 5).

      Couple.PAIRS = { { track = Name aus Icons.FILTER, tree = id im Baum } … }
      Couple.Active() → true, wenn der Schalter an ist und der Client C_Minimap hat
      Couple.FromBlizzard() → Zahl der in ezMap geschalteten Gruppen (nach MINIMAP_UPDATE_TRACKING)
      Couple.ToBlizzard(id) → Zahl der geschalteten bzw. vorgemerkten Blizzard-Arten (nach einer Änderung im Baum)
      Couple.Snapshot() → merkt Blizzards Stand als Ausgang, ohne zu schalten

    Paare: nur Stadtbewohner mit klarer Entsprechung – „Lehrer für eine Klasse“ zu Klassenlehrern, „Berufsausbilder“ zu
    den Berufslehrern, „Reparieren“ zu den Händlern mit Reparatur, „Flugmeister“ zu „Nächster Flugmeister“. Nicht
    gekoppelt: die Such-Zauber (Kräuter-, Mineraliensuche) – der Client lässt oft nur einen gleichzeitig zu, das
    Einschalten der Erze schaltete die Kräuter ab und damit ezMaps Kräuter mit; Händler für Essen und Trinken (ezMaps
    „Händler“ sind alle besuchten, nicht nur Essen).

    Regeln:
      - Ab dem nächsten Klick: Einschalten des Schalters gleicht nichts an (Couple.Snapshot), vorher Abweichendes bleibt.
      - Keine Schleife: jede Richtung schaltet nur, was wirklich abweicht (Tree.Any gegen Blizzards active bzw. die noch
        nicht gemeldete Anfrage), während ezMap selbst den Baum schaltet, hört die Gegenrichtung nicht zu, und eine Art,
        die ezMap gerade bei Blizzard angefragt hat, gilt als angefragt, bis der Client genau diesen Stand meldet –
        höchstens Couple.ASK_WAIT Sekunden lang (kein zweiter Aufruf, kein Zurückschalten, falls der Client seinen
        Stand erst später meldet; eine Meldung zu einer anderen Art dazwischen löscht die Anfrage nicht – Fund 2 des
        zweiten Reviews vom 17.11.2026; antwortet der Client nie, gilt nach der Frist wieder sein gemeldeter Stand).
      - Kampf: C_Minimap.SetTracking nur außerhalb des Kampfes; im Kampf merkt ezMap die Art vor und schaltet nach
        PLAYER_REGEN_ENABLED nach dem dann gültigen Stand des Baums (ns.AfterCombat).
      - TrackingMemory („Auswahl oben merken“): solange es nach dem Einloggen bzw. Wiederbeleben Blizzards Auswahl
        wiederherstellt (Memory.ready falsch oder Ruhezeit Memory.quietUntil), ist das kein Klick des Spielers – ezMap
        merkt den Stand nur als Ausgang und schaltet seinen Baum nicht. Schaltest du in dieser Zeit in ezMap, merkt ezMap
        die Art vor wie im Kampf und schaltet sie, sobald das Wiederherstellen fertig ist, nach dem dann gültigen Stand
        des Baums (sonst machte das Wiederherstellen den Klick rückgängig; Fund der Nachprüfung vom 17.11.2026). Was ezMap
        bei Blizzard schaltet, merkt TrackingMemory wie jeden Klick.
      - Tod: TrackingMemory wartet vom Tod bis zum Wiederbeleben (PLAYER_DEAD bis PLAYER_ALIVE bzw. PLAYER_UNGHOST, dann
        Memory.DELAY und Ruhezeit) mit Memory.ready falsch. ezMap prüft in dieser Zeit nicht im Sekundentakt, sondern
        wartet auf den Rückruf Memory.OnReady und holt Vorgemerktes danach nach (Fund 3 des zweiten Reviews vom
        17.11.2026). Ein Klick in Blizzards Menü „Aufspüren“ im Tod wird nicht gekoppelt: TrackingMemory merkt ihn
        nicht (Memory.Save gilt nicht im Tod) und stellt nach dem Wiederbeleben seine gemerkte Auswahl her; ezMap nimmt
        den Stand danach als Ausgang. Ist „Auswahl oben merken“ aus, bleibt ein solcher Klick bei Blizzard, ezMaps
        Gruppe schaltet nicht mit (bewusst: im Tod und beim Laden kann der Client selbst melden, ohne dass der Spieler
        klickt).
]]
local Couple = {}
ns.TrackingCouple = Couple

Couple.PAIRS = {
    { track = "TrainerClass", tree = "trainerClass" },
    { track = "TrainerProfession", tree = "trainerProf" },
    { track = "Repair", tree = "repairTargets" },
    { track = "TaxiNode", tree = "flightNearest" },
}

Couple.seen = {}        -- tree-id » zuletzt gesehener Stand der Blizzard-Art
Couple.asked = {}       -- tree-id » bei Blizzard angefragter Stand (bis der Client ihn meldet, höchstens ASK_WAIT)
Couple.askedAt = {}     -- tree-id » Laufzeit (Core.Uptime) der Anfrage
Couple.ASK_WAIT = 5     -- Sekunden, die eine Anfrage ohne passende Meldung des Clients gilt
Couple.pending = {}     -- tree-id » true: nach dem Kampf bzw. nach dem Wiederherstellen schalten
local applying = false  -- ezMap schaltet gerade selbst den Baum (Gegenrichtung hört nicht zu)
local waitingRestore = false

local Memory = function() return ns.TrackingMemory end

function Couple.Active()
    return ns.Enabled("trackingCouple") and Memory().Available() == true
end

-- Blizzards Art eines Paars in der gezeigten Liste (gesperrte Antworten fehlen dort) → Eintrag oder nil
local function EntryOf(pair, list)
    local want = ns.Icons.FilterID(pair.track)
    if not want then return nil end
    for _, entry in ipairs(list) do
        if entry.filterID == want then return entry end
    end
    return nil
end

-- Wiederherstellen von TrackingMemory läuft (kein Klick des Spielers)?
local function Restoring()
    local M = Memory()
    if not M.ready then return true end
    return Core.Uptime() < (M.quietUntil or 0)
end

function Couple.Snapshot()
    local list = Memory().List()
    for _, pair in ipairs(Couple.PAIRS) do
        local entry = EntryOf(pair, list)
        Couple.seen[pair.tree] = entry and entry.active or nil
    end
    Couple.asked, Couple.askedAt = {}, {}
end

-- Noch offene Anfrage dieser Art → angefragter Stand oder nil (nach Couple.ASK_WAIT Sekunden verfällt sie)
local function Asked(tree)
    local asked = Couple.asked[tree]
    if asked == nil then return nil end
    if Core.Uptime() - (Couple.askedAt[tree] or 0) > Couple.ASK_WAIT then
        Couple.asked[tree], Couple.askedAt[tree] = nil, nil
        return nil
    end
    return asked
end

-- Blizzard » ezMap: geänderte Arten schalten die passende Gruppe (nur, was abweicht)
function Couple.FromBlizzard()
    if not Couple.Active() or Restoring() then
        Couple.Snapshot()
        return 0
    end
    local list = Memory().List()
    local Tree = ns.Tree
    local count = 0
    for _, pair in ipairs(Couple.PAIRS) do
        local entry = EntryOf(pair, list)
        if entry then
            local was = Couple.seen[pair.tree]
            local asked = Asked(pair.tree)
            Couple.seen[pair.tree] = entry.active
            -- angefragt und noch nicht so gemeldet: der Client ist noch nicht so weit – nicht zurückschalten, die
            -- Anfrage bleibt offen; so gemeldet: erledigt
            local waiting = asked ~= nil and asked ~= entry.active
            if asked ~= nil and not waiting then Couple.asked[pair.tree], Couple.askedAt[pair.tree] = nil, nil end
            if was ~= nil and was ~= entry.active and not waiting and Tree.Any(pair.tree) ~= entry.active then
                applying = true
                local ok, err = pcall(Tree.Set, pair.tree, entry.active)
                applying = false
                if ok then count = count + 1 else ns.Error(err, "TrackingCouple") end
            end
        else
            Couple.asked[pair.tree], Couple.askedAt[pair.tree] = nil, nil     -- Art nicht mehr gezeigt
        end
    end
    return count
end

-- Betrifft eine Änderung im Baum (Gruppe, Blatt, dynamisches Blatt) dieses Paar? Gruppe darüber, das Blatt selbst
-- oder etwas darunter.
local function Affects(pairTree, id)
    local Tree = ns.Tree
    if id == nil then return false end
    if Tree.DynGroupOf(id) == pairTree then return true end
    local cur = pairTree
    while cur do
        if cur == id then return true end
        cur = Tree.Parent(cur)
    end
    cur = Tree.Parent(id)
    while cur do
        if cur == pairTree then return true end
        cur = Tree.Parent(cur)
    end
    return false
end
Couple.Affects = Affects

-- Stand der Blizzard-Art, von dem ezMap ausgeht: eine noch nicht gemeldete Anfrage gilt schon (sonst hielte ezMap
-- „aus und gleich wieder an“ für erledigt, und die verspätete Meldung „aus“ schaltete ezMap zurück)
local function Current(pair, entry)
    local asked = Asked(pair.tree)
    if asked ~= nil then return asked end
    return entry.active
end

local function SetNow(pair, entry, want)
    if Asked(pair.tree) == want then return false end
    if Memory().Set(entry, want) then
        Couple.asked[pair.tree], Couple.askedAt[pair.tree] = want, Core.Uptime()
        return true
    end
    return false
end

-- Vorgemerkte Arten später schalten: im Kampf nach PLAYER_REGEN_ENABLED (ns.AfterCombat), während TrackingMemory
-- wiederherstellt nach dessen Ruhezeit (ein Zeitgeber genügt). Solange TrackingMemory noch gar nicht bereit ist
-- (Einloggen, Tod bis zum Wiederbeleben), wartet ezMap auf den Rückruf Memory.OnReady, statt zu prüfen.
local function FlushLater()
    if ns.InCombat() then
        ns.AfterCombat(function() ns.Try("TrackingCouple", Couple.Flush) end, "trackingCouple")
        return
    end
    local M = Memory()
    if waitingRestore or not M.ready then return end
    waitingRestore = true
    local wait = math.max((M.quietUntil or 0) - Core.Uptime(), 0) + 0.1
    C_Timer.After(wait, function()
        waitingRestore = false
        ns.Try("TrackingCouple", Couple.Flush)
    end)
end

-- Nach dem Kampf bzw. dem Wiederherstellen: die vorgemerkten Arten nach dem jetzt gültigen Stand des Baums
function Couple.Flush()
    if not Couple.Active() then
        Couple.pending = {}
        return 0
    end
    if ns.InCombat() or Restoring() then
        if next(Couple.pending) then FlushLater() end
        return 0
    end
    local todo = Couple.pending
    Couple.pending = {}
    local list = Memory().List()
    local count = 0
    for _, pair in ipairs(Couple.PAIRS) do
        if todo[pair.tree] then
            local entry = EntryOf(pair, list)
            local want = ns.Tree.Any(pair.tree)
            if entry and Current(pair, entry) ~= want and SetNow(pair, entry, want) then count = count + 1 end
        end
    end
    return count
end

-- ezMap » Blizzard: nach einer Änderung im Baum die betroffenen Arten (nur, was abweicht; im Kampf vormerken)
function Couple.ToBlizzard(id)
    if applying or not Couple.Active() then return 0 end
    local list
    local count = 0
    for _, pair in ipairs(Couple.PAIRS) do
        if Affects(pair.tree, id) then
            list = list or Memory().List()
            local entry = EntryOf(pair, list)
            local want = ns.Tree.Any(pair.tree)
            if entry and Current(pair, entry) ~= want then
                if ns.InCombat() or Restoring() then
                    Couple.pending[pair.tree] = true
                    FlushLater()
                    count = count + 1
                elseif SetNow(pair, entry, want) then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local fromSoon = ns.Throttle(function() ns.Try("TrackingCouple", Couple.FromBlizzard) end, 0.2)
ns.On("MINIMAP_UPDATE_TRACKING", function() fromSoon() end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.Try("TrackingCouple", Couple.Snapshot) end)
ns.Tree.OnChanged(function(id) Couple.ToBlizzard(id) end)
-- TrackingMemory ist bereit (nach dem Wiederherstellen bzw. dem Wiederbeleben): Vorgemerktes nachholen
Memory().OnReady(function()
    if next(Couple.pending) then ns.Try("TrackingCouple", Couple.Flush) end
end)
-- Hinweis an der Weltkarte (ezCores Hinweis-Helfer, einmal je Account; Gesamtreview 18.11.2026, T1-3; Entscheidung 2 des Nutzers vom 18.11.2026: Hinweis auch für Abläufe ohne Klick, die nie
-- ab Werk an waren, sofern sie senden oder Blizzards Zustände umstellen; reine Anzeigen ohne Hinweis):
-- Die Kopplung schaltet Blizzards Aufspür-Haken mit, wenn du ezMaps Gruppe schaltest (und umgekehrt) – den anderen
-- Haken ohne eigenen Klick.
function Couple.RegisterOptInHint()
    local Hint = ezCore.OptInHint
    if not (Hint and Hint.RegisterSetting) then return false end
    return Hint.RegisterSetting("ezMap", ns, "trackingCouple", {
        window = "map",
        -- wie die übrigen Hinweise an der Karte: warten, solange ezMaps Rundgang eine Blase zeigt; Pfeil auf den Kartenknopf
        applies = function() return not (ns.Guide and ns.Guide.Showing and ns.Guide.Showing()) end,
        target = function() return ns.MapButton and ns.MapButton.Get and ns.MapButton.Get() end,
        side = "below",
    })
end
Couple.RegisterOptInHint()

ns.OnSettingChanged(function(key)
    if key == "trackingCouple" then
        Couple.pending = {}
        Couple.Snapshot()       -- ab dem nächsten Klick (siehe Kopf)
    elseif ns.Tree.Node(key) then
        Couple.ToBlizzard(key)  -- ein Schalter des Baums, auf der Einstellungsseite gesetzt
    end
end)
