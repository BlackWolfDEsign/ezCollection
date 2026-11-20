local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    Blizzards Menü „Aufspüren“ an der Minikarte: Auswahl je Charakter merken und wiederherstellen, dazu „Alle
    auswählen“ und „Alle abwählen“ (Wunsch des Nutzers vom 15.11.2026 abends, wörtlich: „"aufspüren" in wow bei der
    minimap muss auch die auswahl speichern und auch alle an/aus bieten, vllt beim design system mit“).

    Geprüft in Blizzards Forever-Quelle (Gethe/wow-ui-source, Zweig forever):
      - Blizzard_Minimap.toc lädt für Forever (Spielart camelot) die Mainline-Fassung Mainline/Minimap.lua mit den
        Konstanten aus Camelot/MinimapConstants.lua. MiniMapTrackingButtonMixin:OnLoad baut das Menü mit dem Tag
        MENU_MINIMAP_TRACKING. Ist die Client-Einstellung minimapTrackingShowAll aus, steht OBEN Blizzards Eintrag
        UNCHECK_ALL: er ruft C_Minimap.ClearAllTracking und schaltet danach jede Art aus ALWAYS_ON_FILTERS und
        CONDITIONAL_FILTERS wieder ein (Forever: Quest-Punkte, Abgeschlossene Quests des Kontos, Ziel), egal wie sie
        vorher stand. Alle anderen Haken nimmt er heraus – auch die der Such-Zauber (Mineraliensuche). ezMaps
        „Alle abwählen“ lässt diese Arten aus (Memory.SkipOff). Ein Gegenstück zum Anhaken hat Blizzard nicht; ezMap ergänzt es direkt
        darunter. Mit minimapTrackingShowAll fehlt Blizzards Eintrag, dann ergänzt ezMap beide.
      - Gezeigt werden Arten mit Zauber (filter.spellID) oder aus MinimapConstants.OPTIONAL_FILTERS (Forever:
        Reparieren, Gastwirt, Flugmeister, Stallmeister, Kampfmeister, Klassen- und Berufslehrer, Auktionator,
        Bankier, niedrigstufige Quests, Briefkasten) – dieselbe Regel hier (Tracking.Displayed).
      - Die Häkchen lesen Blizzards eigenen, vorhergesagten Stand (lokale Tabelle trackingState); Blizzard gleicht ihn
        bei MINIMAP_UPDATE_TRACKING mit C_Minimap.GetTrackingInfo ab – auch bei offenem Menü (OverrideSelectedState,
        ReinitializeAll). ezMap schaltet deshalb nur über C_Minimap.SetTracking und schreibt nichts in Blizzards
        Tabellen (Leitlinie 5).
      - „Niedrigstufige Quests“ und „Abgeschlossene Quests des Kontos“ hängen an Blizzards Einstellungen
        (MinimapUtil, PROXY_TRIVIAL_QUEST_FILTERING bzw. PROXY_ACCOUNT_COMPLETED_QUEST_FILTERING): der Client merkt
        sie selbst, ezMap merkt sie nicht noch einmal.
    Client (docs/datengrundlage.md, Probe 10 – Dokumentation der Signaturen): C_Minimap.GetNumTrackingTypes,
    GetTrackingInfo(i) → { name, texture, active, type, subType, spellID nilbar }, GetTrackingFilter(i) → { spellID?,
    filterID? }, SetTracking(i, an) mit SecretArguments=AllowedWhenUntainted und ohne HasRestrictions, Ereignis
    MINIMAP_UPDATE_TRACKING. Unbelegt (Probe 10 sagt dazu nichts; im Spiel prüfen, Spielprüfpunkt 60 c und d): ob
    das Schalten eines Such-Zaubers (intern ein Zauber) aus Addon-Code oder im Kampf gesperrt ist. ezMap schaltet
    Such-Zauber deshalb nur mit dem Schalter trackingSpellAuto (ab Werk aus, unten), nur außerhalb des Kampfes und hört
    auf ADDON_ACTION_BLOCKED und ADDON_ACTION_FORBIDDEN. Was der Client selbst
    merkt (CVar minimapTrackedInfov4), reicht laut Nutzer nicht – ezMap stellt nur her, was abweicht.

    Schlüssel je Art (keine Namen, die sind je Sprache): "s<spellID>", sonst "f<filterID>", sonst
    "t<type>:<subType>:<Textur>". Gespeichert in ezMapDB.tracking[charKey] = { on = { [Schlüssel] = true|false },
    order = { [Schlüssel] = n }, n, last = Schlüssel des zuletzt eingeschalteten Such-Zaubers, at }.

    Sperre (Prüfung auf Blizzards Regeln vom 17.11.2026, Risiko 19; Auftrag des Nutzers vom 17.11.2026, wörtlich „am
    ende muss sichergestellt werden dass das addon nicht gegen blizzard verstößt“): Als Sperre zählt jede Meldung
    ADDON_ACTION_BLOCKED bzw. ADDON_ACTION_FORBIDDEN an ezMap, die während des Wiederherstellens fällt (Zeitfenster
    Memory.watchUntil, so lang wie die Ruhezeit nach dem eigenen Schalten) oder deren Funktionsname „SetTracking“
    enthält – nicht nur die mit „SetTracking“, denn welchen Namen der Client bei einem Such-Zauber meldet, ist unbelegt.
    Nach der ersten Sperre schaltet ezMap Such-Zauber nicht mehr selbst ein, auch nicht nach dem nächsten Einloggen
    (gespeichert, für alle Charaktere: ezMapDB.trackingBlock = { at, func }; der Schalter trackingSpellAuto geht aus),
    und sagt das einmal im Chat. Den gemerkten Such-Zauber bietet es zum Anklicken an: Eintrag „Gemerkten Such-Zauber
    einschalten: <Name>“ im Abschnitt „Minikarte“ von ezMaps Teil in Blizzards Menü „Aufspüren“
    (Tracking.ENTRIES.spellClick, gleich unter „Auswahl oben merken“), dazu der Haken „Such-Zauber selbst einschalten“ –
    derselbe Schalter wie auf der Einstellungsseite (trackingSpellAuto); an hebt eine Sperre wieder auf (Leitlinie 3;
    aufgehoben bleibt der Vermerk als { at, func, lifted = true }). Sperrt Blizzard auch den Klick über ezMap, nennt
    ezMap Blizzards eigenen Eintrag darüber. Ist ezMaps Teil des Menüs aus (Schalter trackingMenu), nennen Hinweis und
    Status diesen Schalter und Blizzards eigenen Eintrag. Solange Such-Zauber nur per Klick gehen (Schalter aus oder
    gesperrt, Memory.Manual), gilt ein gemerkter Such-Zauber, der nicht an war, nicht als abgewählt (Memory.Save,
    Memory.spellSeen) – außer der Spieler schaltet
    gerade selbst einen anderen, nicht gemerkten Such-Zauber ein („gerade“: seit dem letzten Merken bzw. Wiederherstellen
    neu an; was schon beim Einloggen oder in der Ruhezeit an war, zählt nicht). Bekannte Grenze: Schaltet der Client
    selbst nach der Ruhezeit einen Such-Zauber ein, kann ezMap das nicht von einer Wahl des Spielers unterscheiden – der
    gemerkte gilt dann als abgewählt (Spielprüfpunkt 69 b).
    Bekannte Grenze (Fund 4 des code-reviewers vom 17.11.2026, nur sichere Richtung): Im Zeitfenster zählt jede Meldung
    an ezMap, auch eine Sperre aus einem anderen Teil von ezMap; außerhalb des Fensters zählt „SetTracking“ auch, wenn
    TrackingCouple.lua eine Art ohne Zauber schaltet. Beides ist jetzt gespeichert. Welche Funktion Blizzard nannte,
    steht in ezMapDB.trackingBlock.func (Spielprüfpunkt 69 b in docs/roadmap/ezMap.md).
    Ab Werk aus (Welle 29, NACH-27): Der Nutzer hat am 17.11.2026 entschieden, dass das automatische Einschalten von
    Such-Zaubern beim Aufspüren ab Werk aus ist, mit Hinweis und Knopf „Einschalten“ (Grundsatz wörtlich „user muss auf
    sowas hingewiesen werden, er kann es nutzen muss es aber einschalten“). Schalter trackingSpellAuto (OPT_ mit _TIP,
    Einstellungsseite Abschnitt „Minikarte“ und Haken im Menü „Aufspüren“), einmal umgestellt in ns.MigrateOptIn29
    (Core.lua), Hinweis an der Weltkarte über ezCores Core.OptInHint (Memory.RegisterOptInHint). Die übrigen Arten
    (Briefkasten, Gastwirt …) stellt ezMap mit trackingRemember weiter selbst her – sie sind Anzeigen der Minikarte.
    Wechselwirkung (vermerkt in docs/roadmap/ezMap.md): Im Zeitfenster des Wiederherstellens zählt jede Sperr-Meldung an
    ezMap – auch eine der Zielverfolgung (C_SuperTrack in Way.lua), etwa wenn eine Sammel- oder ezQuests Leveling-Route
    mit ezMaps wayTrack gerade dann weiterrückt; sie schaltet trackingSpellAuto aus (nur die sichere Richtung).
]]
local Memory = {}
ns.TrackingMemory = Memory

Memory.DELAY = 3        -- Sekunden nach Einloggen, /reload, Zonenwechsel oder Wiederbeleben bis zum Wiederherstellen
Memory.SETTLE = 2       -- so lange nach dem eigenen Wiederherstellen nichts merken (Antworten des Clients abwarten)
Memory.SPELL_GAP = 1.6  -- Abstand zwischen zwei Such-Zaubern (globale Abklingzeit)
Memory.FEATURE = "trackingRemember"     -- Rücksicht (Leitlinie 9): ns.OtherFor, Liste in docs/fremd-addons.md
Memory.SPELL_KEY = "trackingSpellAuto"  -- Schalter „Such-Zauber selbst einschalten“ (ab Werk aus, Welle 29)

-- Arten, die Blizzard in seinen Einstellungen merkt (MinimapUtil.MINIMAP_FILTER_SETTINGS_ENTRY); Zahlen aus
-- Enum.MinimapTrackingFilter laut Probe 10, falls der Client die Aufzählung nicht nennt.
local function FilterValue(name, fallback)
    local enum = rawget(_G, "Enum")
    local filters = type(enum) == "table" and Core.Peek(enum, "MinimapTrackingFilter") or nil
    return Core.Num(Core.Peek(filters, name)) or fallback
end
local SETTINGS_FILTERS = {
    [FilterValue("TrivialQuests", 1024)] = true,
    [FilterValue("AccountCompletedQuests", 2097152)] = true,
}

-- Arten, die Blizzards UNCHECK_ALL gleich wieder einschaltet: MinimapConstants.ALWAYS_ON_FILTERS und
-- CONDITIONAL_FILTERS (nur lesend). Fehlen Blizzards Konstanten, gelten die Forever-Werte aus
-- Camelot/MinimapConstants.lua (Zahlen laut Blizzard_APIDocumentationGenerated/MinimapConstantsDocumentation.lua).
local KEEP_FALLBACK = {
    [FilterValue("QuestPOIs", 65536)] = true,
    [FilterValue("AccountCompletedQuests", 2097152)] = true,
    [FilterValue("Target", 16384)] = true,
}
function Memory.KeepOn(filterID)
    if not filterID then return false end
    local consts = rawget(_G, "MinimapConstants")
    local always = type(consts) == "table" and Core.Peek(consts, "ALWAYS_ON_FILTERS") or nil
    local conditional = type(consts) == "table" and Core.Peek(consts, "CONDITIONAL_FILTERS") or nil
    if type(always) ~= "table" and type(conditional) ~= "table" then return KEEP_FALLBACK[filterID] == true end
    return (type(always) == "table" and Core.Peek(always, filterID) == true)
        or (type(conditional) == "table" and Core.Peek(conditional, filterID) == true)
end

local function Api()
    local api = rawget(_G, "C_Minimap")
    if type(api) ~= "table" or type(api.GetNumTrackingTypes) ~= "function" or type(api.GetTrackingInfo) ~= "function"
        or type(api.SetTracking) ~= "function" then
        return nil
    end
    return api
end
function Memory.Available() return Api() ~= nil end

-- Zeigt Blizzard alle Arten (Client-Einstellung minimapTrackingShowAll)? Dann fehlt sein Eintrag UNCHECK_ALL.
function Memory.ShowAll()
    local value = Core.Call(Core.CVar, "minimapTrackingShowAll")
    return not Core.IsSecret(value) and (value == "1" or value == 1 or value == true)
end

-- Gleiche Regel wie Blizzards CanDisplayTrackingInfo; ohne Blizzards Konstanten oder ohne GetTrackingFilter: alle.
function Memory.Displayed(filterID, spellID, showAll, hasFilter)
    if showAll or spellID or not hasFilter then return true end
    local consts = rawget(_G, "MinimapConstants")
    local optional = type(consts) == "table" and Core.Peek(consts, "OPTIONAL_FILTERS") or nil
    if type(optional) ~= "table" then return filterID ~= nil end
    return filterID ~= nil and Core.Peek(optional, filterID) == true
end

function Memory.Key(spellID, filterID, kind, subType, texture)
    if spellID then return "s" .. spellID end
    if filterID then return "f" .. filterID end
    texture = Core.Plain(texture)
    if type(texture) ~= "number" and type(texture) ~= "string" then texture = nil end
    if type(kind) == "string" and kind ~= "" and texture then
        return "t" .. kind .. ":" .. tostring(subType or 0) .. ":" .. tostring(texture)
    end
    return nil
end

-- Such-Zauber, die seit dem letzten Wiederherstellen an waren (Schlüssel → true). Nach einer Sperre gilt nur deren
-- Ausschalten als Wunsch des Spielers (Memory.Save); einer, der nie an war, bleibt gemerkt und per Klick angeboten.
Memory.spellSeen = {}

-- Die Arten, die Blizzards Menü gerade zeigt: { { index, key, name, active, spell, filterID, settings } … }.
-- Gesperrte Antworten (Leitlinie 6) lassen die Art aus – sie wird weder gemerkt noch geschaltet.
function Memory.List()
    local api = Api()
    if not api then return {} end
    local count = Core.Num(Core.Call(api.GetNumTrackingTypes)) or 0
    local hasFilter = type(api.GetTrackingFilter) == "function"
    local showAll = Memory.ShowAll()
    local list = {}
    for index = 1, count do
        local info = Core.Call(api.GetTrackingInfo, index)
        if not Core.IsSecret(info) and type(info) == "table" then
            local filter = hasFilter and Core.Call(api.GetTrackingFilter, index) or nil
            if Core.IsSecret(filter) or type(filter) ~= "table" then filter = nil end
            local spellID = Core.Num(Core.Peek(info, "spellID")) or Core.Num(Core.Peek(filter, "spellID"))
            local filterID = Core.Num(Core.Peek(filter, "filterID"))
            local kind = Core.Plain(Core.Peek(info, "type"))
            local active = Core.Peek(info, "active")
            local key = Memory.Key(spellID, filterID, kind, Core.Num(Core.Peek(info, "subType")), Core.Peek(info, "texture"))
            if key and not Core.IsSecret(active) and Memory.Displayed(filterID, spellID, showAll, hasFilter) then
                local name = Core.Plain(Core.Peek(info, "name"))
                local item = { index = index, key = key, name = type(name) == "string" and name or key,
                    active = active == true, spell = spellID ~= nil or kind == "spell", filterID = filterID,
                    settings = filterID ~= nil and SETTINGS_FILTERS[filterID] == true }
                if item.spell and item.active then Memory.spellSeen[key] = true end
                list[#list + 1] = item
            end
        end
    end
    return list
end

function Memory.Find(key)
    for _, entry in ipairs(Memory.List()) do
        if entry.key == key then return entry end
    end
    return nil
end

-- Eine Art schalten (nur Blizzards C-Schnittstelle, Leitlinie 5). → true bei Erfolg
function Memory.Set(entry, on)
    local api = Api()
    if not (api and type(entry) == "table" and entry.index) then return false end
    local ok, err = pcall(api.SetTracking, entry.index, on and true or false)
    if not ok then ns.Error(err, "TrackingSet") end
    return ok
end

local function Dead()
    local fn = rawget(_G, "UnitIsDeadOrGhost")
    return Core.Bool(Core.Call(fn, "player"), false)
end

---------------------------------------------------------------------------
-- Speicher je Charakter
---------------------------------------------------------------------------

function Memory.Store(create)
    local db, key = ns.db, ns.charKey or Core.charKey
    if not (db and key) then return nil end
    if type(db.tracking) ~= "table" then db.tracking = {} end
    local rec = db.tracking[key]
    if type(rec) ~= "table" then
        if not create then return nil end
        rec = {}
        db.tracking[key] = rec
    end
    if type(rec.on) ~= "table" then rec.on = {} end
    if type(rec.order) ~= "table" then rec.order = {} end
    rec.n = Core.Num(rec.n) or 0
    return rec
end

-- Laufen Merken und Wiederherstellen? → true | false, Grund ("off" | "other", Name | "api")
function Memory.Active()
    if not ns.Enabled("trackingRemember") then return false, "off" end
    local other = ns.OtherFor(Memory.FEATURE)
    if other then return false, "other", other end
    if not Api() then return false, "api" end
    return true
end

Memory.ready = false        -- erst nach dem Wiederherstellen merken (sonst merkt ezMap den Stand beim Einloggen)
Memory.quietUntil = 0

-- Rückruf fn(), sobald Memory.ready wieder gilt (nach dem Wiederherstellen bzw. Wiederbeleben) – für die Kopplung,
-- die bis dahin Vorgemerktes aufhebt, statt im Sekundentakt zu prüfen (Fund 3 des zweiten Reviews vom 17.11.2026)
local readyListeners = {}
function Memory.OnReady(fn)
    if type(fn) == "function" then readyListeners[#readyListeners + 1] = fn end
end
local function Ready()
    Memory.ready = true
    for _, fn in ipairs(readyListeners) do ns.Try("TrackingReady", fn) end
end

-- Such-Zauber, die beim letzten Merken bzw. Wiederherstellen an waren (Schlüssel → true): nur ein Such-Zauber, der
-- danach neu angeht, ist eine Wahl des Spielers (Memory.Save). Eigener Stand statt Memory.spellSeen, weil Memory.List
-- auch von der Kopplung und dem Menü aufgerufen wird und Memory.spellSeen dabei schon vor dem Merken füllt.
Memory.spellOn = {}
local function SpellsOn(list)
    local on = {}
    for _, entry in ipairs(list) do
        if entry.spell and entry.active then on[entry.key] = true end
    end
    return on
end

-- Stand merken, sobald der Spieler ihn ändert. force: auch während der Ruhezeit (erster Stand eines Charakters).
-- → true, wenn sich etwas geändert hat
function Memory.Save(force)
    if not (Memory.ready and Memory.Active()) or Dead() then return false end
    -- In der Ruhezeit nichts merken, aber festhalten, welche Such-Zauber an sind (Memory.spellOn): was der Client hier
    -- selbst einschaltet, gilt danach nicht als neue Wahl des Spielers (Gegenprüfung vom 17.11.2026)
    if not force and Core.Uptime() < (Memory.quietUntil or 0) then
        Memory.spellOn = SpellsOn(Memory.List())
        return false
    end
    local before = Memory.spellOn or {}
    local list = Memory.List()
    Memory.spellOn = SpellsOn(list)
    if #list == 0 then return false end
    local rec = Memory.Store(true)
    if not rec then return false end
    local changed = false
    -- Hat der Spieler gerade selbst einen Such-Zauber eingeschaltet, der nicht gemerkt war (über Blizzards Eintrag),
    -- gelten die übrigen gemerkten, die aus sind, als abgewählt (Fund 5 des code-reviewers vom 17.11.2026: sonst blieb
    -- der Knopf „Gemerkten Such-Zauber einschalten“ für den alten stehen). „Gerade“ heißt: seit dem letzten Merken bzw.
    -- Wiederherstellen neu an (nicht in Memory.spellOn) – ein Such-Zauber, der schon beim Einloggen an war und den
    -- ezMap nicht ausschalten durfte, ist keine neue Wahl (Gegenprüfung vom 17.11.2026).
    local chosen = false
    local manual = Memory.Manual()
    if manual then
        for _, entry in ipairs(list) do
            if entry.spell and entry.active and not entry.settings and rec.on[entry.key] ~= true
                and not before[entry.key] then
                chosen = true
            end
        end
    end
    for _, entry in ipairs(list) do
        -- Nach einer Sperre ist ein gemerkter Such-Zauber aus, weil ezMap ihn nicht schalten durfte – das ist kein
        -- Wunsch des Spielers. Erst wenn er in dieser Sitzung an war, zählt sein Ausschalten (Fund 1 der
        -- Gegenprüfung vom 17.11.2026: sonst verschwand der Knopf „Gemerkten Such-Zauber einschalten“).
        local keep = manual and not chosen and entry.spell and not entry.active and rec.on[entry.key] == true
            and not Memory.spellSeen[entry.key]
        if not entry.settings and not keep and rec.on[entry.key] ~= entry.active then
            rec.on[entry.key] = entry.active
            changed = true
            if entry.spell and entry.active then
                rec.n = rec.n + 1
                rec.order[entry.key] = rec.n
                rec.last = entry.key
            end
        end
    end
    if changed then rec.at = time() end
    return changed
end

-- Was weicht vom Gemerkten ab? → Schritte { { entry, on } … } (erst Ausschalten, dann Einschalten ohne Zauber),
-- Such-Zauber zum Einschalten (der zuletzt gewählte zuletzt – lässt der Client nur einen zu, bleibt er an)
function Memory.Plan()
    local rec = Memory.Store(false)
    if not rec then return {}, {} end
    local off, on, spells = {}, {}, {}
    for _, entry in ipairs(Memory.List()) do
        local want = rec.on[entry.key]
        if not entry.settings and type(want) == "boolean" and want ~= entry.active then
            if not want then
                off[#off + 1] = { entry = entry, on = false }
            elseif entry.spell then
                spells[#spells + 1] = entry
            else
                on[#on + 1] = { entry = entry, on = true }
            end
        end
    end
    for _, step in ipairs(on) do off[#off + 1] = step end
    table.sort(spells, function(a, b)
        local oa, ob = Core.Num(rec.order[a.key]) or 0, Core.Num(rec.order[b.key]) or 0
        if oa ~= ob then return oa < ob end
        return a.index < b.index
    end)
    return off, spells
end

-- Einen Such-Zauber später einschalten – er wird beim Lauf neu gesucht (die Reihenfolge der Arten kann wechseln).
local function SpellLater(key, delay, token)
    C_Timer.After(delay, function()
        if Memory.token ~= token or Memory.Manual() or ns.InCombat() or Dead() or not Memory.Active() then return end
        local entry = Memory.Find(key)
        if entry and not entry.active then Memory.Set(entry, true) end
    end)
end

-- Wiederherstellen (nach Memory.DELAY): nur außerhalb des Kampfes (sonst nach PLAYER_REGEN_ENABLED), nur was
-- abweicht. → Anzahl der Schaltungen
function Memory.Restore()
    local active = Memory.Active()
    if not active then
        Ready()
        return 0
    end
    if Dead() then return 0 end             -- PLAYER_ALIVE bzw. PLAYER_UNGHOST holen es nach
    if ns.InCombat() then
        ns.AfterCombat(function() ns.Try("TrackingRestore", Memory.Restore) end, "trackingRestore")
        return 0
    end
    local hadRecord = Memory.Store(false) ~= nil
    Memory.spellSeen = {}                   -- ab hier neu zählen (Plan liest die Liste und merkt, was an ist)
    local steps, spells = Memory.Plan()
    Memory.spellOn = SpellsOn(Memory.List())
    if Memory.Manual() then spells = {} end -- Schalter aus oder blockiert: nur per Klick (Memory.BuildMenu)
    local count = 0
    Memory.quietUntil = Core.Uptime() + Memory.SETTLE + math.max(0, #spells - 1) * Memory.SPELL_GAP
    -- Zeitfenster der Sperr-Erkennung: jede Sperr-Meldung an ezMap bis zum Ende der Ruhezeit zählt (OnBlocked) – nur,
    -- wenn ein Such-Zauber versucht wird; Arten ohne Zauber meldet der Client unter „SetTracking“ (Fund 3 der
    -- Gegenprüfung vom 17.11.2026)
    if #spells > 0 then Memory.watchUntil = Memory.quietUntil end
    for _, step in ipairs(steps) do
        if Memory.Set(step.entry, step.on) then count = count + 1 end
    end
    for i, entry in ipairs(spells) do
        if i == 1 then
            if Memory.Set(entry, true) then count = count + 1 end
        else
            SpellLater(entry.key, (i - 1) * Memory.SPELL_GAP, Memory.token)
            count = count + 1
        end
    end
    Memory.ready = true
    Memory.restored = { count = count, at = time() }
    if not hadRecord then Memory.Save(true) end     -- erster Stand dieses Charakters: so, wie der Client ihn hat
    Ready()                                         -- erst jetzt die Zuhörer (Memory.OnReady)
    return count
end

-- Nach Memory.DELAY wiederherstellen; ein späterer Aufruf ersetzt einen wartenden.
function Memory.Schedule()
    Memory.ready = false
    Memory.token = (Memory.token or 0) + 1
    local token = Memory.token
    C_Timer.After(Memory.DELAY, function()
        if Memory.token == token then ns.Try("TrackingRestore", Memory.Restore) end
    end)
end

---------------------------------------------------------------------------
-- Alle auswählen / Alle abwählen (Menü „Aufspüren“ und Einstellungsseite)
---------------------------------------------------------------------------

-- Such-Zauber nimmt „Alle auswählen“ aus: der Client lässt oft nur einen gleichzeitig zu, und sie sind Zauber.
function Memory.SkipOn(entry) return entry.spell == true end
function Memory.IsActive(entry) return entry.active end

-- „Alle abwählen“ lässt aus, was Blizzards UNCHECK_ALL gleich wieder einschaltet (Quest-Punkte, Ziel …), und im
-- Kampf die Such-Zauber (die folgen nach dem Kampf, Memory.AfterOff).
function Memory.SkipOff(entry)
    if Memory.KeepOn(entry.filterID) then return true end
    return entry.spell == true and ns.InCombat()
end

-- Nach „Alle abwählen“ (Menü und Einstellungsseite): im Kampf noch aktive Such-Zauber nach dem Kampf ausschalten.
-- → true, wenn etwas wartet
function Memory.AfterOff()
    if not ns.InCombat() then return false end
    for _, entry in ipairs(Memory.List()) do
        if entry.spell and entry.active and not Memory.KeepOn(entry.filterID) then
            ns.AfterCombat(function() Memory.SetAll(false) end, "trackingAllOff")
            return true
        end
    end
    return false
end

-- Menüeintrag „Alle abwählen“ (opts.after von ezCores Baustein): wartet etwas, im Chat sagen.
function Memory.AfterOffSay(_, on)
    if not on and Memory.AfterOff() then Core.CombatNotice(ns, L.TRACKMEM_OFF_WHAT, "later") end
end

-- Such-Zauber, die „Alle auswählen“ ausgelassen hat (Memory.SkipOn) und die noch aus sind: ihre Namen (Liste).
function Memory.SkippedSpells()
    local names = {}
    for _, entry in ipairs(Memory.List()) do
        if Memory.SkipOn(entry) and not entry.active and type(entry.name) == "string" and not Core.IsSecret(entry.name) then
            names[#names + 1] = entry.name
        end
    end
    return names
end

-- Nach „Alle auswählen“ (Menü und Einstellungsseite): Such-Zauber, die bewusst ausgelassen wurden, im Chat nennen –
-- sonst sieht es aus, als hätte der Klick sie vergessen (Spielbefund des Nutzers vom 18.11.2026: „"allwe wählen"
-- gedrückt bei minimap aber mineraliensuche hat es nicht aktiviert“). → true, wenn eine Zeile kam
function Memory.SaySkipped()
    local names = Memory.SkippedSpells()
    if #names == 0 then return false end
    ns.Print(L.TRACKMEM_SPELLS_SKIPPED:format(table.concat(names, ", ")))
    return true
end

-- Menüeintrag „Alle auswählen“ (opts.after von ezCores Baustein)
function Memory.AfterOnSay(_, on)
    if on then Memory.SaySkipped() end
end

-- Alle Arten an (ohne Such-Zauber) bzw. alle aus (wie Blizzards UNCHECK_ALL, auch Such-Zauber, ohne die Arten, die
-- Blizzard dabei wieder einschaltet). → Anzahl | nil, "api" | Anzahl, "combat" (beim Ausschalten im Kampf: die
-- Such-Zauber warten auf das Ende des Kampfes, der Rest ist geschaltet)
function Memory.SetAll(on)
    if not Api() then return nil, "api" end
    local count = Core.Menu.SetAll(Memory.List, Memory.IsActive, Memory.Set, on, on and Memory.SkipOn or Memory.SkipOff)
    if not on and Memory.AfterOff() then return count, "combat" end
    return count
end

-- Knöpfe der Einstellungsseite: schalten und im Chat sagen, was geschah.
function Memory.SetAllAndSay(on)
    local count, why = Memory.SetAll(on)
    if why == "api" then
        ns.Print(L.TRACKMEM_NOAPI)
    elseif why == "combat" then
        if count > 0 then ns.Print(L.TRACKMEM_ALL_OFF:format(count)) end
        Core.CombatNotice(ns, L.TRACKMEM_OFF_WHAT, "later")
    elseif count == 0 then
        ns.Print(L.TRACKMEM_NOTHING)
    else
        ns.Print((on and L.TRACKMEM_ALL_ON or L.TRACKMEM_ALL_OFF):format(count))
    end
    if on and why == nil then Memory.SaySkipped() end
    return count, why
end

---------------------------------------------------------------------------
-- Status und Ereignisse
---------------------------------------------------------------------------

function Memory.StatusLine()
    local active, why, who = Memory.Active()
    if not active then
        if why == "other" then return L.STATUS_TRACKMEM_OTHER:format(who) end
        if why == "api" then return L.STATUS_TRACKMEM_NOAPI end
        return L.STATUS_TRACKMEM_OFF
    end
    local rec = Memory.Store(false)
    local count = 0
    for _ in pairs(rec and rec.on or {}) do count = count + 1 end
    local line = L.STATUS_TRACKMEM_ON:format(count)
    local last = rec and rec.last and Memory.Find(rec.last)
    if last then line = line .. " " .. L.STATUS_TRACKMEM_SPELL:format(last.name) end
    if Memory.blocked and Memory.blockedNow then line = line .. " " .. L.STATUS_TRACKMEM_BLOCKED end
    if Memory.blocked then
        line = line .. " " .. Memory.ClickText(L.STATUS_TRACKMEM_SPELLS_CLICK, L.STATUS_TRACKMEM_SPELLS_NOMENU)
    elseif Memory.Manual() and Memory.HasSpells() then
        line = line .. " " .. Memory.ClickText(L.STATUS_TRACKMEM_SPELLS_MANUAL, L.STATUS_TRACKMEM_SPELLS_MANUAL_NOMENU)
    end
    return line
end
ns.AddStatusLine(function() return Memory.StatusLine() end)

local saveSoon = ns.Throttle(function() ns.Try("TrackingSave", Memory.Save) end, 0.3)
ns.On("MINIMAP_UPDATE_TRACKING", function() saveSoon() end)
ns.On("PLAYER_ENTERING_WORLD", function() Memory.Schedule() end)
ns.On("PLAYER_LEAVING_WORLD", function() Memory.ready = false end)
ns.On("PLAYER_DEAD", function() Memory.ready = false end)
local function Revived()
    if not Dead() then Memory.Schedule() end
end
ns.On("PLAYER_ALIVE", Revived)
ns.On("PLAYER_UNGHOST", Revived)

---------------------------------------------------------------------------
-- Such-Zauber nur mit Schalter (Welle 29, NACH-27) und Sperre durch Blizzard (Risiko 19 der Prüfung vom 17.11.2026)
---------------------------------------------------------------------------

Memory.CLICK_WATCH = 1      -- so lange nach einem Klick auf „Gemerkten Such-Zauber einschalten“ zählt eine Sperr-Meldung

-- Schaltet ezMap gemerkte Such-Zauber selbst ein? Nur mit dem Schalter trackingSpellAuto (ab Werk aus) und ohne Sperre.
function Memory.SpellsAuto() return ns.Enabled(Memory.SPELL_KEY) and not Memory.blocked end

-- Such-Zauber nur per Klick (Schalter aus oder von Blizzard blockiert)? Dann stellt Memory.Restore sie nicht her, das
-- Menü bietet die gemerkten zum Anklicken an, und Memory.Save vergisst keinen, nur weil er aus ist.
function Memory.Manual() return not Memory.SpellsAuto() end

-- Kennt der Charakter Such-Zauber (Blizzards Menü „Aufspüren“ zeigt eine Art mit Zauber)?
function Memory.HasSpells()
    for _, entry in ipairs(Memory.List()) do
        if entry.spell then return true end
    end
    return false
end

-- Gespeicherte Sperre (für alle Charaktere – Blizzards Regel gilt für den Client) → { at, func } oder nil;
-- vom Spieler aufgehobene ({ …, lifted = true }, Haken „Such-Zauber selbst einschalten“) zählen nicht
function Memory.StoredBlock()
    local db = ns.db
    local rec = db and type(db.trackingBlock) == "table" and db.trackingBlock or nil
    if rec and rec.lifted then return nil end
    return rec
end

-- Sperre aufheben (der Spieler hat „Such-Zauber selbst einschalten“ angehakt): ab dem nächsten Einloggen, Zonenwechsel
-- oder Wiederbeleben schaltet ezMap sie wieder selbst ein. Der Vermerk bleibt als { at, func, lifted = true }.
function Memory.LiftBlock()
    Memory.blocked, Memory.blockedNow = nil, nil
    local db = ns.db
    local old = db and type(db.trackingBlock) == "table" and db.trackingBlock or nil
    if old and not old.lifted then db.trackingBlock = { at = old.at or time(), func = old.func, lifted = true } end
end

-- Gespeicherte Sperre in diese Sitzung übernehmen (beim Einloggen); der Schalter geht dann aus – die Sperre wiegt
-- schwerer (Blizzards Regeln). → true, wenn Such-Zauber gesperrt sind
function Memory.LoadBlock()
    if Memory.StoredBlock() then
        Memory.blocked = true
        if ns.Enabled(Memory.SPELL_KEY) then ns.SetSetting(Memory.SPELL_KEY, false) end
    end
    return Memory.blocked == true
end

-- Eine Sperre merken: ab jetzt Such-Zauber nur noch per Klick (Schalter aus), gespeichert; beim ersten Mal einmal im
-- Chat sagen (ein Text: blockiert, gilt auch nach dem Einloggen, Weg per Klick bzw. ohne ezMaps Menüteil).
-- → true, wenn die Sperre neu ist
function Memory.Block(func)
    local db = ns.db
    if db and not Memory.StoredBlock() then
        db.trackingBlock = { at = time(), func = type(func) == "string" and func or nil }
    end
    if Memory.blocked then return false end
    Memory.blocked, Memory.blockedNow = true, true
    if ns.Enabled(Memory.SPELL_KEY) then ns.SetSetting(Memory.SPELL_KEY, false) end
    ns.Print(Memory.ClickText(L.TRACKMEM_BLOCKED, L.TRACKMEM_BLOCKED_NOMENU))
    return true
end

-- Den Klick-Weg gibt es nur mit ezMaps Teil im Menü „Aufspüren“ (Schalter trackingMenu, Tracking.Build); ist er aus,
-- nennen Hinweis und Status den Schalter und Blizzards eigenen Eintrag (Fund 2 der Gegenprüfung vom 17.11.2026).
-- → withMenu oder noMenu:format(Name des Schalters)
function Memory.ClickText(withMenu, noMenu)
    if ns.Enabled("trackingMenu") then return withMenu end
    return noMenu:format(L.OPT_trackingMenu or "trackingMenu")
end

-- Haken „Such-Zauber selbst einschalten“ (Menü „Aufspüren“ und Einstellungsseite, ein Schalter): an hebt eine Sperre auf
-- (ns.OnSettingChanged unten), aus heißt nur noch per Klick.
function Memory.SetSpellsAuto(on)
    ns.SetSetting(Memory.SPELL_KEY, on and true or false)
end

-- Gemerkte Such-Zauber, die gerade aus sind → { entry … } (der zuletzt gewählte zuletzt)
function Memory.Pending()
    local _, spells = Memory.Plan()
    return spells
end

-- Klick auf „Gemerkten Such-Zauber einschalten“: nur außerhalb des Kampfes, über Blizzards C-Schnittstelle.
-- → true, wenn geschaltet
function Memory.SpellClick(key)
    if ns.InCombat() then
        Core.CombatNotice(ns, L.TRACKMEM_SPELL_WHAT, "blocked")
        return false
    end
    if Dead() then return false end
    local entry = Memory.Find(key)
    if not entry or entry.active then return false end
    Memory.clickUntil, Memory.clickName = Core.Uptime() + Memory.CLICK_WATCH, entry.name
    return Memory.Set(entry, true)
end

-- Einträge im Abschnitt „Minikarte“: der Haken „Such-Zauber selbst einschalten“ (immer, solange ezMap die Auswahl
-- merkt; Welle 29, NACH-27) und – solange Such-Zauber nur per Klick gehen – je gemerktem, gerade ausgeschaltetem
-- Such-Zauber ein Knopf.
function Memory.BuildMenu(root)
    if not Memory.Active() then return end
    local Menu = Core.Menu
    for _, entry in ipairs(Memory.Manual() and Memory.Pending() or {}) do
        local key, text = entry.key, L.TRACKMEM_SPELL_CLICK:format(entry.name)
        Menu.Tip(Menu.Button(root, text, function() Memory.SpellClick(key) end), text, L.TRACKMEM_SPELL_CLICK_TIP,
            L.TRACKMEM_SPELL_SOURCE)
    end
    local auto = Menu.Toggle(root, L.OPT_trackingSpellAuto, Memory.SpellsAuto, Memory.SetSpellsAuto)
    Menu.Tip(auto, L.OPT_trackingSpellAuto, L.OPT_trackingSpellAuto_TIP)
end

-- In ezMaps Teil von Blizzards Menü „Aufspüren“ (Tracking.lua lädt vorher): Abschnitt „Minikarte“, gleich unter
-- „Auswahl oben merken“. Nur eigene Tabellen – Blizzards Menü bleibt bei der einen Anmeldung von Tracking.Register.
local function AddToTrackingMenu()
    local Tracking = ns.Tracking
    if not (type(Tracking) == "table" and type(Tracking.ENTRIES) == "table" and type(Tracking.SECTIONS) == "table") then
        return false
    end
    Tracking.ENTRIES.spellClick = { icon = "menuMinimap", build = function(root) Memory.BuildMenu(root) end }
    for _, section in ipairs(Tracking.SECTIONS) do
        if section.id == "minimap" and type(section.entries) == "table" then
            local at = #section.entries + 1
            for i, key in ipairs(section.entries) do
                if key == "spellClick" then return true end
                if key == "remember" then at = i + 1 end
            end
            table.insert(section.entries, at, "spellClick")
            return true
        end
    end
    return false
end
AddToTrackingMenu()

-- ADDON_ACTION_BLOCKED meldet, was nur im Kampf gesperrt ist, ADDON_ACTION_FORBIDDEN, was Addons nie dürfen – beide
-- (wie ezCore/Charakter/MailQueue.lua). Als Sperre zählt jede Meldung an ezMap im Zeitfenster des Wiederherstellens
-- oder mit „SetTracking“ im Namen; nach einem Klick sagt ezMap, dass auch der Klick nicht ging.
local function OnBlocked(_, addon, func)
    if Core.IsSecret(addon) or addon ~= ADDON then return end
    if Core.IsSecret(func) or type(func) ~= "string" then func = nil end
    local now = Core.Uptime()
    if now < (Memory.clickUntil or 0) then
        Memory.clickUntil = 0
        ns.Print(L.TRACKMEM_CLICK_BLOCKED:format(Memory.clickName or "?"))
        Memory.Block(func)
        return
    end
    if (func and func:find("SetTracking", 1, true)) or now < (Memory.watchUntil or 0) then Memory.Block(func) end
end
ns.On("ADDON_ACTION_BLOCKED", OnBlocked)
ns.On("ADDON_ACTION_FORBIDDEN", OnBlocked)
ns.OnReady(function() Memory.LoadBlock() end)

-- Schalter eingeschaltet: der Stand von jetzt ist der Ausgang (sonst stellte das nächste Einloggen Altes her).
-- „Such-Zauber selbst einschalten“ an (Menü, Einstellungsseite oder Hinweis): hebt eine Sperre auf.
ns.OnSettingChanged(function(key)
    if key == "trackingRemember" and ns.Enabled("trackingRemember") then
        Ready()
        Memory.Save(true)
    elseif key == Memory.SPELL_KEY and ns.Enabled(Memory.SPELL_KEY) then
        Memory.LiftBlock()
    end
end)

-- Hinweis an der Weltkarte (ezCores Hinweis-Helfer, Welle 29, NACH-27): „Such-Zauber selbst einschalten“ ist ab Werk
-- aus. Einmal je Account, nur wenn ezMap die Auswahl merkt, der Charakter Such-Zauber kennt und Blizzard nicht
-- blockiert hat (dann kam schon die Chatzeile), nicht neben einer Blase von ezMaps Rundgang. Pfeil auf ezMaps
-- Kartenknopf, in derselben Blase wie „Zielverfolgung einschalten“ (Way.lua).
function Memory.RegisterOptInHint()
    local Hint = Core.OptInHint
    if not (Hint and Hint.Register) then return false end
    return Hint.Register("ezMap.trackingSpellAuto", {
        owner = ADDON,
        window = "map",
        label = function() return L.OPT_trackingSpellAuto end,
        what = function() return L.OPTIN_trackingSpellAuto end,
        where = function() return L.OPTIN_WHERE_trackingSpellAuto end,
        isOn = function() return ns.Enabled(Memory.SPELL_KEY) end,
        enable = function()
            Memory.SetSpellsAuto(true)
            return ns.Enabled(Memory.SPELL_KEY)
        end,
        applies = function()
            return Memory.Active() == true and not Memory.StoredBlock() and Memory.HasSpells()
                and not (ns.Guide and ns.Guide.Showing and ns.Guide.Showing())
        end,
        switchedOff = function() return type(ns.db) == "table" and ns.db.trackSpellOff29Was == true end,
        target = function() return ns.MapButton and ns.MapButton.Get and ns.MapButton.Get() end,
        side = "below",
    })
end
Memory.RegisterOptInHint()

-- Vergisst ezCore einen Charakter, vergisst ezMap seine Auswahl mit.
Core.Listen("CHAR_FORGOTTEN", function(key)
    if ns.db and type(ns.db.tracking) == "table" and key then ns.db.tracking[key] = nil end
end, ADDON)
