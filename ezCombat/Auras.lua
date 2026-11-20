local _, ns = ...
local L = ns.L
local Glow = ns.Glow

-- Eigene DoTs und HoTs auf dem Ziel:
--   1. Blizzards Zielfenster zeigt eigene Auren ohnehin größer (21 statt 17). ezCombat stellt diese Größe
--      über Blizzards eigene Schnittstelle des Auren-Containers höher (SetLargeAuraSize) – das Original, nur größer.
--   2. Eine Reihe großer Symbole in Aktionsknopf-Optik über dem Zielfenster, mit Restzeit in Zahlen: Blizzards
--      Auren-Reihe über ezCore.AuraRow (CB-06; leuchtet im Pandemie-Fenster des Spiels), ohne Blizzards Vorlage
--      ezCombats eigene Reihe als Rückfall (CB-07 entfernt sie nach dem Spieltest).
--      Kurz vor Ablauf leuchtet der passende Aktionsknopf mit Blizzards Proc-Leuchten: „neu setzen“.
-- Blizzards Auren-Knöpfe sind für Addons gesperrt, sobald Auren geheim sind (DenyTaintedAccessWhenAurasAreSecret);
-- an ihnen leuchtet nur, was Blizzard selbst zeigt – die eigene Reihe des Rückfalls leuchtet über ezCombat.
-- Im Kampf sind die Auren des Ziels meist gesperrt: Dann regeln Blizzards Dauer-Objekt und eine Stufenkurve die
-- Deckkraft des Leuchtens (siehe „Gesperrte Restzeiten“ unten).
-- Spieltest 13.11.2026 („eigene DoTs/HoTs … kommt nie zum Einsatz“), Befund aus der Forever-Quelle:
-- GetAuraDataByIndex ist „SecretWhenUnitAuraRestricted“ – gesperrt ist die ganze Aura ein gesperrter Wert, nicht nur
-- ihre Felder. ezCore.Auras.Scan hörte dann bei der ersten Aura auf (eine gesperrte Tabelle lässt sich nicht lesen),
-- die Liste blieb leer und die Reihe verborgen – und gesperrt sind die Auren, sobald man im Kampf ist, also immer,
-- wenn ein eigener DoT auf dem Ziel liegt. Nie gesperrt ist C_UnitAuras.GetUnitAuraInstanceIDs (nur Zahlen, auf
-- Wunsch nach Ablauf sortiert) und GetAuraDuration (Dauer-Objekt je Instanz). Darüber liest seit ezCore 1.8.0
-- ezCore.Auras.Scan selbst (vorher baute ezCombat das hier nach); Namen und Symbole gesperrter Auren kennt ezCombat
-- aus den eigenen Zaubern (Auras.Learn, Auras.Remember).
-- Auslaufende DoTs stehen außerdem am gemeinsamen Symbolplatz in der Bildschirmmitte (Symbol.lua, Rang 1).
local Auras = {}
ns.Auras = Auras

local MAX_DURATION = 60     -- längere Auren (Seelenstärke, Mal der Wildnis …) sind keine DoTs/HoTs
local PANDEMIC = 0.3        -- Anteil der Dauer, ab dem ein neues Setzen nichts verschenkt (Blizzards Pandemie)
local MAX_ICONS = 6
local ICON_SIZE = 30
local SPACING = 5
local TICK = 0.1
local BLIZZARD_LARGE_SIZE = 21
local FALLBACK_ICON = ezCore.ICON_FALLBACK_ID   -- ezCores Ersatzsymbol, Fragezeichen (Gesamtreview 18.11.2026, T16-NM6)

local current = {}          -- gesammelte Auren des Ziels (Felder wie ezCore.Auras.Scan, expires = Ablaufzeit)
local CAST_WINDOW = 1.5     -- Sekunden: so lange nach einem eigenen Zauber gehört eine neue Aura zu ihm
local USE_WINDOW = 6        -- Sekunden: Aktionsknopf gedrückt, Zauber bis dahin gewirkt (Zauberzeit)
local AURA_LANDS = 0.5      -- Sekunden: so lange nach dem eigenen Zauber liegt seine Aura sicher auf dem Ziel
local icons = {}
local row
local demoUntil = 0

---------------------------------------------------------------------------
-- Auren lesen: ezCore.Auras.Scan (eine Stelle für ezCombat und ezBuff)
---------------------------------------------------------------------------

-- Diagnose für den Spieltest (/ezk status, Zeile „DoTs, letztes Lesen im Kampf“): was das letzte Lesen im Kampf
-- ergab – Zahl der Instanz-IDs, gelesene, gesperrte und nicht herausgegebene Auren, Einträge in der Liste, gesperrte
-- mit Dauer-Objekt und mit Namen, dazu (aus Auras.UpdateSymbol) ob Blizzards Dauer-Objekt die Restzeit auswerten
-- ließ. Jede dieser Stellen kann im Spiel stumm leer bleiben; die Zeile zeigt, welche.
local diag

local function NoteRead(info)
    if not ns.InCombat() then return end
    info.when = GetTime()
    diag = info
end

function Auras.Diag() return diag end

-- Eigene kurze Auren auf dem Ziel, die am schnellsten auslaufende zuerst, gesperrte am Ende.
-- Gesperrte stehen als { secret = true, icon, instance, durationObject } in der Liste (keepSecret, durations):
-- Symbol und Dauer-Objekt gehen unverändert an Blizzards Rahmen (SetTexture, SetCooldownFromDurationObject),
-- gerechnet wird damit nie. Zweiter Rückgabewert: true, wenn das Spiel Daten gerade geheim hält; dritter: true,
-- wenn es Auren gar nicht herausgab (Aufruf schlug fehl oder lieferte nichts – die Liste ist dann unvollständig).
function Auras.Collect()
    local list = {}
    local present = ns.UnitPresent("target")     -- gesperrt: das Spiel hält Daten geheim, keine Liste geraten
    if present == nil then
        NoteRead({ noTarget = true })
        return list, true, false
    end
    if not present then return list, false, false end
    local friendly = ns.Bool(UnitIsFriend("player", "target"), false)
    local filter = friendly and "HELPFUL|PLAYER" or "HARMFUL|PLAYER"
    -- ezCore liest über die nie gesperrten Instanz-IDs (ganz gesperrte Auren als Platzhalter mit Instanz und
    -- Blizzards Dauer-Objekt); ezCombat ergänzt Namen und Symbole aus den eigenen Zaubern.
    local auras, secret, ids, unread = ezCore.Auras.Scan("target", filter,
        { keepSecret = true, durations = true, max = MAX_ICONS * 2 })
    if ids then Auras.Learn(ids) end
    Auras.Remember(auras)
    -- Platz in ezCores Liste: Blizzards Reihenfolge der Instanz-IDs (Sortierung „Expiration“ des Clients, die zuerst
    -- auslaufende zuerst) – auch für gesperrte Auren, deren Restzeit ezCombat nicht lesen darf.
    local place = {}
    for index, aura in ipairs(auras) do
        if aura.secret then
            list[#list + 1] = aura
        elseif aura.name and aura.expires and aura.duration and aura.duration > 0 and aura.duration <= MAX_DURATION then
            list[#list + 1] = aura
        end
        place[aura] = index
    end
    -- Offene nach Ablauf, gesperrte dahinter nach ihrem Platz (CB-05, V-106): Vorher galten zwei gesperrte als gleich,
    -- table.sort ist nicht stabil und verwürfelte sie – CheckExpiring nimmt aber die erste gesperrte als die zuerst
    -- auslaufende (Symbolplatz „läuft aus“).
    table.sort(list, function(a, b)
        local secretA, secretB = a.secret and true or false, b.secret and true or false
        if secretA ~= secretB then return secretB end
        if not secretA and a.expires ~= b.expires then return a.expires < b.expires end
        return place[a] < place[b]
    end)
    local withDuration, named = 0, 0
    for _, aura in ipairs(list) do
        if aura.secret then
            if aura.durationObject then withDuration = withDuration + 1 end
            if aura.name then named = named + 1 end
        end
    end
    NoteRead({ list = list, ids = ids and #ids or nil, read = #auras, secret = secret, unread = ns.Num(unread) or 0,
        listed = #list, withDuration = withDuration, named = named })
    return list, secret > 0, (ns.Num(unread) or 0) > 0
end

---------------------------------------------------------------------------
-- Gesperrte Auren: Instanz-IDs (nie gesperrt) und was ezCombat aus den eigenen Zaubern über sie weiß.
-- Lesen gehört seit ezCore 1.8.0 nach ezCore.Auras (InstanceIDs, FromInstances, Duration); hier bleiben die
-- Weiterleitungen und das Wissen aus den eigenen Zaubern.
---------------------------------------------------------------------------

-- Instanz-IDs der Auren, die zum Filter passen, die zuerst auslaufende zuerst; nil ohne Schnittstelle.
-- Weiterleitung an ezCore.Auras.InstanceIDs (höchstens doppelt so viele wie Symbole in der Reihe).
function Auras.InstanceIDs(unit, filter)
    return ezCore.Auras.InstanceIDs(unit, filter, MAX_ICONS * 2)
end

-- Bekannte Auren je Ziel: [Instanz-ID] = { name, spellId, icon } – aus offenen Werten oder dem eigenen Zauber,
-- der sie gerade gesetzt hat. Mit lesbarer GUID des Ziels hält ezCore das Wissen je Gegner
-- (ezCore.AuraRows.Remember/Recall, begrenzt auf AR.MEMORY_GUIDS Gegner; CB-05, VP-10): Wer zwischen zwei Gegnern
-- wechselt, behält die Namen seiner DoTs auf beiden. Ohne lesbare GUID (gesperrt) gilt die eigene Tabelle known nur
-- für dieses Ziel und wird beim Zielwechsel geleert (wie bisher).
local known, knownGUID = {}, nil

local function Memory()
    local AR = ezCore.AuraRows
    if knownGUID and AR and type(AR.Remember) == "function" and type(AR.Recall) == "function" then return AR end
    return nil
end

local function KnownGet(id)
    local AR = Memory()
    if AR then return AR.Recall(knownGUID, id) end
    return known[id]
end

local function KnownSet(id, info)
    local AR = Memory()
    if AR and AR.Remember(knownGUID, id, info) then return end
    known[id] = info
end
local seenIDs               -- Instanz-IDs beim letzten Lesen (nil = neues Ziel, erst merken)
local lastCast, lastUsed
-- Dasselbe für die eigenen Buffs auf dem Spieler (Rotation: „liegt der selbst gewirkte Buff?“, wenn das Spiel die
-- Auren im Kampf sperrt) – eine eigene Merkliste, die mit dem Ziel nichts zu tun hat.
local playerKnown, playerSeenIDs = {}, nil

-- unit: "target" (Standard) oder "player".
function Auras.Known(id, unit)
    if unit == "player" then return playerKnown[id] end
    return KnownGet(id)
end

-- Zuletzt gedrückter Aktionsknopf: { name, icon, when } oder nil (die Rotation erkennt damit eigene Zauber).
function Auras.LastUsed() return lastUsed end

-- Legt dieser eigene Zauber ({ name, spellId }) eine eigene Aura auf das Ziel? Nur dann bekommt eine gesperrte, neu
-- erschienene Aura des Ziels seinen Namen. Sonst hieße der Debuff aus einem Proc oder Talent (Verwundbarkeit nach
-- Schattenblitz, Entzünden, Tiefe Wunden) wie der Zauber davor: „Schattenblitz läuft aus“, und dessen Aktionsknopf
-- leuchtete „erneuern“. Quellen: die Rotationen der eigenen Klasse und die Volksfähigkeiten (Schritte der Art
-- „dot“ – DoT, HoT, Debuff zum Aufrechterhalten) und die Dauer, die der Client für eine eigene Aura dieses Zaubers
-- schon offen gezeigt hat (ezCore.Spells.AuraSeconds).
function Auras.SetsTargetAura(cast)
    if type(cast) ~= "table" then return false end
    local seconds = ezCore.Spells.AuraSeconds
    if cast.spellId and type(seconds) == "function" and seconds(cast.spellId) then return true end
    if not cast.name then return false end
    local data = type(ns.ROTATIONS) == "table" and ns.ROTATIONS or {}
    local function InSteps(steps)
        for _, step in ipairs(type(steps) == "table" and steps or {}) do
            if step.when == "dot" and ns.SpellName(step.id) == cast.name then return true end
        end
        return false
    end
    for _, rotation in ipairs(data[ns.playerClass or ""] or {}) do
        if InSteps(rotation.steps) then return true end
    end
    return InSteps(data.RACIAL)
end

-- Neue Instanz kurz nach einem eigenen Zauber: Sie gehört zu ihm (nur wenn genau eine neu ist).
-- unit = "player": die Buffs des Spielers; allowed(name) entscheidet dann, ob dieser Zauber überhaupt einen Buff
-- auf den Spieler legt (sonst bekäme ein Proc, der direkt nach einem DoT erscheint, dessen Namen). Für das Ziel
-- entscheidet Auras.SetsTargetAura.
function Auras.Learn(ids, unit, allowed)
    local forPlayer = unit == "player"
    local seen = seenIDs
    local get, set = KnownGet, KnownSet
    if forPlayer then
        seen = playerSeenIDs
        get = function(id) return playerKnown[id] end
        set = function(id, info) playerKnown[id] = info end
    end
    local fresh = {}
    if seen then
        for _, id in ipairs(ids) do
            if not seen[id] then fresh[#fresh + 1] = id end
        end
    end
    seen = {}
    for _, id in ipairs(ids) do seen[id] = true end
    if forPlayer then
        playerSeenIDs = seen
        -- was nicht mehr auf dem Spieler liegt, braucht keinen Namen mehr (Instanz-IDs kommen nicht wieder)
        for id in pairs(playerKnown) do
            if not seen[id] then playerKnown[id] = nil end
        end
    else
        seenIDs = seen
    end
    if #fresh == 1 and lastCast and GetTime() - lastCast.when <= CAST_WINDOW and not get(fresh[1]) then
        local fits
        if forPlayer then
            fits = type(allowed) ~= "function" or allowed(lastCast.name)
        else
            fits = Auras.SetsTargetAura(lastCast)
        end
        if fits then
            set(fresh[1], { name = lastCast.name, spellId = lastCast.spellId, icon = lastCast.icon,
                guessed = lastCast.guessed })
            lastCast = nil
        end
    end
end

-- Liste aus ezCore.Auras ergänzen: offene Auren merken ([Instanz-ID] = Name, Zauber, Symbol), gesperrten Namen,
-- Zauber und – fehlt es – das Symbol des eigenen Zaubers geben, der sie gesetzt hat. Rückgabe: dieselbe Liste.
-- aura.guessed = true: Der Name ist nur aus dem zuletzt gedrückten Knopf erschlossen (die Zauber-ID war gesperrt).
-- DoT-Reihe und Buff-Warnung zeigen ihn (nur Anzeige); die Rotation nimmt ihn nur mit „Mitzählen“
-- (Rotation.UnitAuras; Fund 1 des code-reviewers vor dem Merge, 17.11.2026).
-- unit: "target" (Standard) oder "player" (eigene Merkliste).
function Auras.Remember(list, unit)
    local get, set = KnownGet, KnownSet
    if unit == "player" then
        get = function(id) return playerKnown[id] end
        set = function(id, info) playerKnown[id] = info end
    end
    for _, aura in ipairs(list or {}) do
        local id = aura.instance
        local info = id and aura.secret and get(id)
        if id and not aura.secret then
            if aura.name then set(id, { name = aura.name, spellId = aura.spellId, icon = aura.icon }) end
        elseif info then
            aura.name, aura.spellId, aura.guessed = info.name, info.spellId, info.guessed or nil
            -- Symbol: aus der (feldweise gesperrten) Aura – darf an SetTexture –, sonst vom eigenen Zauber.
            if not ns.IsSecret(aura.icon) and aura.icon == nil then aura.icon = info.icon end
        end
    end
    return list
end

-- Auren zu Instanz-IDs: Weiterleitung an ezCore.Auras.FromInstances (gesperrte als Platzhalter), dazu das Wissen
-- aus den eigenen Zaubern (Auras.Remember).
function Auras.FromInstances(unit, ids)
    local list, secret = ezCore.Auras.FromInstances(unit, ids, { keepSecret = true })
    return Auras.Remember(list), secret
end

-- Name, Symbol und Zauber-ID eines eigenen Zaubers: aus der Zauber-ID, wenn sie nicht gesperrt ist; sonst vom
-- zuletzt gedrückten Aktionsknopf (ohne ID; vierter Wert true = erschlossen, nicht vom Spiel genannt). nil, wenn
-- beides fehlt. Für die Anzeige (DoT-Reihe, Buff-Warnung) gilt der Knopf-Name immer; die Rotation nimmt ihn nur mit
-- „Mitzählen“ (aura.guessed, siehe Auras.Remember; den Zauber selbst ordnet State.OnSpellcast nach eigener Regel zu).
function Auras.CastInfo(spellID)
    local id = ns.Num(spellID)
    if id then return ns.SpellName(id), ezCore.Spells.Icon(id), id end
    if lastUsed and GetTime() - lastUsed.when <= USE_WINDOW then return lastUsed.name, lastUsed.icon, nil, true end
    return nil
end

-- Eigene Zauber: der zuletzt gewirkte (Auras.CastInfo).
local function OnOwnCast(unit, spellID)
    if not ns.IsSecret(unit) and unit ~= "player" then return end
    local name, icon, id, guessed = Auras.CastInfo(spellID)
    if name then lastCast = { name = name, spellId = id, icon = icon, when = GetTime(), guessed = guessed } end
    -- Rotation: once-Schritte abhaken, Zähler fortschreiben, Ersatzuhr stellen (RotationState.lua bestimmt den
    -- Namen nach seiner eigenen, engeren Regel – auch wenn die Zauber-ID gesperrt ist).
    local State = ns.RotationState
    if State and State.OnSpellcast then State.OnSpellcast(spellID, lastUsed) end
end
Auras.OnOwnCast = OnOwnCast

local castFrame = CreateFrame("Frame")
if castFrame.RegisterUnitEvent then
    castFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
else
    castFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
castFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
    ns.Try("Auras", OnOwnCast, unit, spellID)
    if Auras.UpdateSoon then
        Auras.UpdateSoon()
        -- Die Aura landet erst nach dem Zauber auf dem Ziel: kurz danach noch einmal lesen (Netz für den Fall, dass
        -- UNIT_AURA ausbleibt), solange der Zauber noch als „gerade gewirkt“ gilt (CAST_WINDOW).
        C_Timer.After(AURA_LANDS, Auras.UpdateSoon)
    end
end)
if type(UseAction) == "function" then
    hooksecurefunc("UseAction", function(slot)
        slot = ns.Num(slot)
        local name = slot and ezCore.Call(Glow.SlotSpellName, slot)
        if name then lastUsed = { name = name, icon = ezCore.ActionSlots.Texture(slot), when = GetTime() } end
    end)
end

-- Neues Ziel: Instanzen neu merken. Mit lesbarer GUID bleibt das Wissen über jeden Gegner in ezCore (KnownGet); die
-- eigene Tabelle (ohne lesbare GUID) gilt nur für das Ziel, bei dem sie entstand.
function Auras.NewTarget()
    seenIDs = nil
    local guid = ns.Plain(UnitGUID and UnitGUID("target"))
    if guid ~= knownGUID or guid == nil then
        known, knownGUID = {}, guid
    end
end

-- Pandemie-Wert des Spiels: wie viel ein neues Setzen jetzt mitnähme (C_UnitAuras.GetRefreshCarryOverDuration,
-- im Kampf meist gesperrt); nil, wenn es ihn nicht gibt, er 0 ist oder gesperrt.
function Auras.CarryOver(aura)
    local api = C_UnitAuras and C_UnitAuras.GetRefreshCarryOverDuration
    if not (aura and aura.instance and api) then return nil end
    local value = ns.Num(ezCore.Call(api, "target", aura.instance))
    if value and value > 0 then return value end
    return nil
end

-- Ab wann „neu setzen“: die Warnzeit aus den Einstellungen plus Zauberzeit (Feuerbrand braucht 2 s), bei langen
-- DoTs schon ab 30 % Restdauer (Blizzards Pandemie-Fenster: so viel nimmt ein neues Setzen mit). Liefert das Spiel
-- den Pandemie-Wert selbst, gilt er statt der 30 %. Nur mit offenen Werten; gesperrt regelt die Stufenkurve unten.
function Auras.WarnAt(aura)
    local warn = ns.S.dotWarn + ns.CastTime(aura.spellId or aura.name)
    local window = Auras.CarryOver(aura)
    if window then
        window = window + 0.05
    elseif aura.duration then
        window = aura.duration * PANDEMIC
    end
    if window and window > warn then return window end
    return warn
end

function Auras.IsExpiring(aura, now)
    if not aura or aura.secret then return false end
    local left = aura.expires - (now or GetTime())
    return left > 0 and left <= Auras.WarnAt(aura)
end

---------------------------------------------------------------------------
-- Reihe über dem Zielfenster (Blizzards Reihe über ezCore.AuraRow, sonst die eigene als Rückfall)
---------------------------------------------------------------------------

-- Kind von Blizzards Zielfenster: nur außerhalb des Kampfs anlegen (beim Login bzw. kurz vor Kampfbeginn).
local ROW_ANCHOR = { "BOTTOMLEFT", "TargetFrame", "TOPLEFT", 26, 0 }

---------------------------------------------------------------------------
-- Blizzards Auren-Reihe über ezCore.AuraRow (CB-06, Entscheidung des Nutzers vom 13.11.2026 „Ja, ganz umstellen“):
-- Blizzard sammelt, sortiert und zeigt die eigenen Auren selbst – auch gesperrt, mit Symbol, Spirale, Stapelzahl und
-- Leuchten im Pandemie-Fenster des Spiels (Knopf-Vorlage aus ezCore). Zwei Gruppen zugleich, weil sich der Filter
-- im Kampf nicht umschalten lässt: dots (HARMFUL|PLAYER) und hots (HELPFUL|PLAYER), je höchstens sechs Symbole bis
-- 60 s Gesamtdauer, die zuerst auslaufende zuerst. Lage über ezCore.Mover mit dem alten Schlüssel ezCombat.dots
-- (gemerkte Lagen gelten weiter), ohne eigene Lage wie bisher über dem Zielfenster.
-- Kennt der Client Blizzards Vorlage nicht (ezCore.AuraRows.Available() falsch), bleibt ezCombats eigene Reihe
-- (Row, Icon, ShowAura unten) als Rückfall – entfernt wird sie erst nach dem Spieltest (CB-07).
-- Was nicht an der Reihe hängt, bleibt in ezCombat: Auras.Collect (Symbolplatz, Leuchten am Aktionsknopf),
-- CheckExpiring mit eigenem Takt (unten), WarnAt, Learn/Remember.
---------------------------------------------------------------------------

local SORT_METHODS = rawget(_G, "AuraContainerSortMethod")
local SORT_EXPIRATION = type(SORT_METHODS) == "table" and SORT_METHODS.Expiration or 4   -- Forever-Quelle
local rowMode               -- "blizzard" | "own" | nil (noch nicht entschieden: im Kampf ist die Vorlage unbekannt)
local blizzRow              -- die Reihe aus ezCore.AuraRow
local blizzShown            -- zuletzt gewünschte Sichtbarkeit (Schalter dots)
local previewCount = 0      -- Beispiel-Symbole der Reihe (reihe:Preview)

local function GroupOptions()
    return {
        maxFrameCount = MAX_ICONS,
        candidateFilters = { maxDuration = MAX_DURATION },
        sortMethod = SORT_EXPIRATION,
        layout = { elementWidth = ICON_SIZE, elementHeight = ICON_SIZE, elementSpacing = SPACING },
        button = { size = ICON_SIZE, pandemic = true, tooltip = false },
    }
end

-- Welche Reihe? Einmal entschieden, gilt es bis zum Neuladen. → "blizzard" | "own" | nil
local function Mode()
    if rowMode then return rowMode end
    if not TargetFrame then return nil end
    local AR = ezCore.AuraRows
    local available = AR and type(AR.Available) == "function" and AR.Available()
    if available == nil then return nil end
    if available ~= true or type(ezCore.AuraRow) ~= "function" then
        rowMode = "own"
        return rowMode
    end
    local want = ns.Enabled("dots") and true or false
    local reihe, why = ezCore.AuraRow("ezCombat", "dots", {
        parent = TargetFrame, unit = "target", shown = want,
        mover = { key = "ezCombat.dots", label = L.MOVER_DOTS, owner = "ezCombat",
            width = MAX_ICONS * (ICON_SIZE + SPACING), height = ICON_SIZE, anchor = ROW_ANCHOR },
        groups = { { "dots", "HARMFUL|PLAYER", GroupOptions() }, { "hots", "HELPFUL|PLAYER", GroupOptions() } },
    })
    if reihe then
        blizzRow, blizzShown, rowMode = reihe, want, "blizzard"
        if why and why ~= "combat" then ns.Error("AuraRow: " .. tostring(why), "Auras") end
    else
        rowMode = "own"
        ns.Error("AuraRow: " .. tostring(why), "Auras")
    end
    return rowMode
end

function Auras.Mode() return Mode() end
function Auras.BlizzardRow() return blizzRow end

-- Schalter dots und Beispiel-Symbole an Blizzards Reihe (nur, was sich geändert hat).
local function ApplyBlizzardRow(demo, list)
    local count = demo and math.min(#list, MAX_ICONS) or 0
    if count ~= previewCount then
        local icons, pandemic = {}, nil
        for index = 1, count do
            icons[index] = list[index].icon
            if not pandemic and Auras.IsExpiring(list[index]) then pandemic = index end
        end
        if blizzRow:Preview(count, { icons = icons, size = ICON_SIZE, spacing = SPACING, pandemic = pandemic }) then
            previewCount = count
        end
    end
    -- Solange Beispiel-Symbole stehen, weicht Blizzards Reihe: Beide hängen am Halter, sonst lägen zwei Sätze Symbole
    -- übereinander (die eigene Reihe ersetzte die echten Auren durch die Beispiele). Danach gilt wieder der Schalter.
    local want = (ns.Enabled("dots") and previewCount == 0) and true or false
    if want ~= blizzShown then
        local ok, why = blizzRow:SetShown(want)
        if ok or why == "combat" then blizzShown = want end
    end
end

local function Row()
    if row or not TargetFrame or ns.InCombat() then return row end
    if Mode() ~= "own" then return nil end
    row = CreateFrame("Frame", "ezCombatAuraRow", TargetFrame)
    row:SetSize(MAX_ICONS * (ICON_SIZE + SPACING), ICON_SIZE)
    row:SetPoint(ROW_ANCHOR[1], TargetFrame, ROW_ANCHOR[3], ROW_ANCHOR[4], ROW_ANCHOR[5])
    -- Verschiebbar (ezCore.Mover); Standard: über dem Zielfenster, wandert mit ihm.
    ns.Movable(row, "dots", L.MOVER_DOTS, ROW_ANCHOR, true)
    row:EnableMouse(false)
    row:Hide()
    local elapsedSince = 0
    row:SetScript("OnUpdate", function(_, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince < TICK then return end
        elapsedSince = 0
        ns.Try("Auras", Auras.CheckExpiring)
    end)
    return row
end

-- „Teile verschieben“ ohne Ziel: Die Reihe ist ein Kind des Zielfensters (erscheint mit ihm, übernimmt seine Größe)
-- und wäre mit ihm verborgen. Solange die Auswahl außerhalb des Bearbeitungsmodus offen ist, hängt sie deshalb an
-- UIParent – in der Größe des Zielfensters, der Anker bleibt –, danach wieder am Zielfenster. Nur der eigene
-- Rahmen, nur außerhalb des Kampfs (sonst nach PLAYER_REGEN_ENABLED).
local detached = false

function Auras.UpdateParent()
    if not (row and TargetFrame) then return end
    local want = ns.PartsShowing() and not ezCore.EditMode.IsActive() and (detached or not TargetFrame:IsVisible())
    if want == detached or ns.InCombat() then return end
    if want then
        row:SetParent(UIParent)
        row:SetScale(TargetFrame:GetScale() or 1)
    else
        row:SetParent(TargetFrame)
        row:SetScale(1)
    end
    detached = want
end

function Auras.Detached() return detached end

-- Rahmen der DoT-Reihe (Erklärblase, Prüfungen) statt des globalen Namens: Blizzards Reihe (reihe:Frame()) bzw. die
-- eigene; nil, solange es keine gibt.
function Auras.Frame()
    if blizzRow then return blizzRow:Frame() end
    return row
end

-- Ziel der Erklärblase „DoTs“: Blizzards Container verbietet nach dem ersten AddAuraGroup das Andocken fremder Rahmen
-- ohne AR.ANCHOR_TEMPLATE (Blizzard_CustomAuraContainer), die Blase (GlowBoxTemplate) hat sie nicht. Sie dockt
-- deshalb am Halter der Reihe an (unter UIParent, an derselben Stelle, Größe von sechs Symbolen) – nur solange das
-- Zielfenster zu sehen ist, sonst wird der Schritt wie bisher übersprungen. Beim Rückfall die eigene Reihe.
function Auras.TourTarget()
    if blizzRow then
        local holder = blizzRow:Holder()
        if holder and TargetFrame and TargetFrame:IsVisible() then return holder end
        return nil
    end
    return row
end

local function Icon(index)
    if icons[index] then return icons[index] end
    local frame = CreateFrame("Frame", nil, Row())
    frame:SetSize(ICON_SIZE, ICON_SIZE)
    frame:SetPoint("LEFT", row, "LEFT", (index - 1) * (ICON_SIZE + SPACING), 0)
    frame:EnableMouse(false)
    Glow.StyleIcon(frame)
    local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cooldown:SetAllPoints(frame.icon)
    if cooldown.SetReverse then cooldown:SetReverse(true) end
    if cooldown.SetDrawEdge then cooldown:SetDrawEdge(true) end
    if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(false) end
    frame.cooldown = cooldown
    local count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
    frame.count = count
    frame:Hide()
    icons[index] = frame
    return frame
end

---------------------------------------------------------------------------
-- Gesperrte Restzeiten (im Kampf auf WoW Forever üblich): Blizzards Dauer-Objekt wertet die Restzeit über
-- eine Stufenkurve selbst aus, und SetAlpha nimmt das gesperrte Ergebnis an. So leuchtet das Symbol
-- genau dann, wenn es auslaufen will – ohne dass ezCombat die Restzeit je liest.
---------------------------------------------------------------------------

local curves = {}

local function StepCurve(key, points)
    if curves[key] then return curves[key] end
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    local ok, curve = pcall(C_CurveUtil.CreateCurve)
    if not ok or type(curve) ~= "table" then return nil end
    local stepType = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step
    if stepType and curve.SetType then curve:SetType(stepType) end
    for _, point in ipairs(points) do curve:AddPoint(point[1], point[2]) end
    curves[key] = curve
    return curve
end

-- Restzeit ≤ Schwelle → 1 (leuchten), sonst 0.
local function WarnCurve()
    return StepCurve("warn" .. ns.S.dotWarn, { { 0, 1 }, { ns.S.dotWarn, 0 } })
end
-- Gegenkurve für den Symbolplatz: Restzeit ≤ Schwelle → 0 (die übrigen Einträge verschwinden), sonst 1.
local function GateCurve()
    return StepCurve("gate" .. ns.S.dotWarn, { { 0, 0 }, { ns.S.dotWarn, 1 } })
end
-- Gesamtdauer über 60 s (Seelenstärke, Mal der Wildnis …) → Symbol unsichtbar, wie im offenen Fall gefiltert.
local function ShortCurve()
    return StepCurve("short", { { 0, 1 }, { MAX_DURATION + 0.01, 0 } })
end

-- Rückgabe: true und das (womöglich gesperrte) Ergebnis, sonst false. Das Ergebnis wird nie geprüft oder
-- verglichen, nur an SetAlpha weitergereicht – mit gesperrten Werten darf ein Addon nichts anderes tun.
local function Evaluate(durationObject, method, curve)
    if not (durationObject and curve and type(durationObject[method]) == "function") then return false end
    local ok, result = pcall(durationObject[method], durationObject, curve)
    if not ok then return false end
    return true, result
end

local function ShowAura(frame, aura)
    -- Ein gesperrtes Symbol darf direkt an SetTexture gehen, aber nicht geprüft werden. Fehlt es ganz (ezCore liefert
    -- bei ganz gesperrter Aura ohne Wissen aus dem eigenen Zauber kein Symbol), steht das Fragezeichen da statt
    -- eines leeren Symbols (CB-05, VP-10; IsSecret vor dem Vergleich mit nil).
    if aura.secret then
        if not ns.IsSecret(aura.icon) and aura.icon == nil then
            frame.icon:SetTexture(FALLBACK_ICON)
        elseif not pcall(frame.icon.SetTexture, frame.icon, aura.icon) then
            frame.icon:SetTexture(FALLBACK_ICON)
        end
    else
        frame.icon:SetTexture(aura.icon or FALLBACK_ICON)
    end
    frame.durationObject = nil
    if aura.secret then
        -- Restzeit geheim: Blizzards Dauer-Objekt zeigt die Spirale trotzdem.
        local shown = false
        local duration = aura.durationObject
        if duration then
            frame.durationObject = duration
            if frame.cooldown.SetCooldownFromDurationObject then
                shown = pcall(frame.cooldown.SetCooldownFromDurationObject, frame.cooldown, duration)
            end
        end
        if not shown then frame.cooldown:Clear() end
        frame.count:SetText("")
        local ok, alpha = Evaluate(frame.durationObject, "EvaluateTotalDuration", ShortCurve())
        if ok then frame:SetAlpha(alpha) else frame:SetAlpha(1) end
    else
        frame.cooldown:SetCooldown(aura.expires - aura.duration, aura.duration)
        frame.count:SetText(aura.count > 1 and aura.count or "")
        frame:SetAlpha(1)
    end
    frame.aura = aura
    frame:Show()
end

local warned = {}            -- [Name] = Ablaufzeit, für die zuletzt gewarnt wurde (/ezk status)

-- Text am Symbolplatz: „Verderbnis läuft aus“, ohne bekannten Namen „DoT läuft aus“.
function Auras.SymbolText(aura)
    if aura.name and not aura.demo then return L.SYMBOL_DOT:format(aura.name) end
    return L.SYMBOL_DOT_PLAIN
end

-- Text bei „Text unter dem Symbol: nur Name“ (Symbol.lua, S-1811-Symboltext): der Name des DoTs, ohne bekannten
-- Namen keiner.
function Auras.SymbolTexts(aura)
    return { name = (aura.name and not aura.demo) and aura.name or nil }
end

function Auras.CheckExpiring()
    local now = GetTime()
    local names = {}
    local firstOpen, firstSecret
    local alphas = {}           -- gesperrte DoTs mit bekanntem Namen: Deckkraft des Knopf-Leuchtens (gesperrt)
    for _, aura in ipairs(current) do
        if Auras.IsExpiring(aura, now) then
            names[aura.name] = true
            firstOpen = firstOpen or aura           -- current ist nach Ablauf sortiert
            if not aura.demo and warned[aura.name] ~= aura.expires then
                warned[aura.name] = aura.expires
                Auras.last = { when = now, name = aura.name }
            end
        elseif aura.secret and aura.durationObject then
            firstSecret = firstSecret or aura       -- Blizzards Reihenfolge: die zuerst auslaufende zuerst
            -- Name aus dem eigenen Zauber bekannt: Der Knopf leuchtet mit, Deckkraft aus der Warnkurve.
            if aura.name then
                local ok, alpha = Evaluate(aura.durationObject, "EvaluateRemainingDuration", WarnCurve())
                if ok then
                    names[aura.name] = true
                    alphas[aura.name] = alpha
                end
            end
        end
    end
    Auras.UpdateSymbol(firstOpen, firstSecret)
    for _, frame in ipairs(icons) do
        local aura = frame:IsShown() and frame.aura or nil
        local secretOk, secretAlpha = false, nil
        if aura and aura.secret then
            secretOk, secretAlpha = Evaluate(frame.durationObject, "EvaluateRemainingDuration", WarnCurve())
        end
        if secretOk then
            Glow.Show(frame, false, "dot")
            Glow.SetAlpha(frame, secretAlpha)
        elseif aura and Auras.IsExpiring(aura, now) then
            Glow.Show(frame, false, "dot")
            Glow.SetAlpha(frame, 1)
        else
            Glow.Hide(frame)
        end
    end
    Glow.SetSpellAlphas(alphas)
    Glow.SetSpells("dot", ns.ShowAt("expiring", "glow") and names or nil)
end

-- Anzeige über dem Charakter, linker Platz (Rang 1): der zuerst auslaufende DoT/HoT, offen mit Restzeit als
-- Spirale. Offen entscheidet ezCombat selbst; gesperrt regelt Blizzards Dauer-Objekt die eigene Ebene (Warnkurve),
-- blendet die übrigen Einträge des Platzes aus (Gegenkurve) und zeigt die Spirale (durchgereicht, nie gelesen).
function Auras.UpdateSymbol(firstOpen, firstSecret)
    local Symbol = ns.Symbol
    if not ns.ShowAt("expiring", "center") then
        Symbol.Clear("dot")
        Symbol.ClearSecret()
        return
    end
    if firstOpen then
        local timer = (ns.Num(firstOpen.expires) and ns.Num(firstOpen.duration))
            and { start = firstOpen.expires - firstOpen.duration, duration = firstOpen.duration } or nil
        -- Zauber für „noch nicht bereit“ (außer Reichweite, Kraft fehlt); ns.Plain, nie ein gesperrter Wert mit „or“
        local spell = ns.Plain(firstOpen.spellId) or ns.Plain(firstOpen.name)
        Symbol.Set("dot", firstOpen.icon, Auras.SymbolText(firstOpen), "dot", timer, spell, Auras.SymbolTexts(firstOpen))
    else
        Symbol.Clear("dot")
    end
    local okWarn, alpha, okGate, gateAlpha = false, nil, false, nil
    if firstSecret then
        okWarn, alpha = Evaluate(firstSecret.durationObject, "EvaluateRemainingDuration", WarnCurve())
        okGate, gateAlpha = Evaluate(firstSecret.durationObject, "EvaluateRemainingDuration", GateCurve())
    end
    -- Diagnose: Gelang die Auswertung der Restzeit für die Liste des letzten Lesens im Kampf?
    if firstSecret and diag and diag.list == current then diag.evaluated = okWarn and okGate end
    if okWarn and okGate then
        Symbol.SetSecret(firstSecret.instance, firstSecret.icon, Auras.SymbolText(firstSecret), alpha, gateAlpha,
            firstSecret.durationObject, Auras.SymbolTexts(firstSecret))
    else
        Symbol.ClearSecret()
    end
end

local function DemoList()
    local now = GetTime()
    local first = ezCore.ActionSlots.Texture(1)     -- Symbol des ersten Aktionsplatzes, sonst ein festes
    return {
        { name = "ezCombat-Demo-1", icon = 136207, duration = 12, expires = now + 2.5, count = 0, demo = true },
        { name = "ezCombat-Demo-2", icon = first or 136118, duration = 15, expires = now + 11, count = 0, demo = true },
    }
end

function Auras.Update()
    local list, secret = {}, false
    local demo = ns.Previewing(demoUntil)
    if demo then
        if GetTime() >= demoUntil then current = DemoList() end   -- Bearbeitungsmodus: Beispiel ohne Ende
        list = current
    elseif ns.Enabled("dots") or ns.ShowAny("expiring") then
        local unread
        list, secret, unread = Auras.Collect()
        if secret then ns.NoteSecret("auras") end
        if unread then ns.NoteSecret("aurasUnread") end
    end
    current = list
    if Auras.UpdateTicker then Auras.UpdateTicker() end   -- T7-3: Profilwechsel ohne Einstellungs-Meldung

    if Mode() == "blizzard" then
        -- Blizzards Reihe zeigt die Auren selbst; ezCombat schaltet sie nur und zeigt Beispiel-Symbole.
        ApplyBlizzardRow(demo, list)
    elseif (demo or ns.Enabled("dots")) and Row() then
        for index = 1, MAX_ICONS do
            local aura = list[index]
            if aura then
                ShowAura(Icon(index), aura)
            elseif icons[index] then
                icons[index].aura = nil
                icons[index]:Hide()
                Glow.Hide(icons[index])
            end
        end
        row:SetShown(#list > 0)
    elseif row then
        row:Hide()
        for _, frame in ipairs(icons) do Glow.Hide(frame) end
    end
    Auras.CheckExpiring()
end

local updateSoon = ns.Throttle(Auras.Update, 0.05)
Auras.UpdateSoon = updateSoon

-- Spieltest 14.11.2026 („es zeigt immer diese fähigkeit an und nicht auslaufender dot“): Im Kampf kommt UNIT_AURA
-- mit gesperrten Werten (Forever-Quelle, UnitAuraDocumentation: SecretWhenAurasRestricted – auch die Einheit). Der
-- Vergleich unit == "target" traf dann nie; im Kampf las ezCombat nur beim Zielwechsel und nach jedem eigenen Zauber
-- neu. Deshalb hört der Zuhörer nur auf das Ziel (ns.OnUnit: Blizzard weckt ihn nur dafür) und nimmt eine gesperrte
-- Einheit als das Ziel – ein zusätzlicher Auslöser. Als Ursache des Fundes ist das nicht belegt: Im Spieltest lagen
-- drei eigene DoTs auf dem Ziel (also drei Lesevorgänge nach eigenen Zaubern), und es kam weder Warnung noch Reihe.
-- Offen ist, ob das Spiel die Instanz-IDs nennt, das Dauer-Objekt herausgibt und die Kurve auswerten lässt – das
-- zeigt die Diagnosezeile in /ezk status (Auras.DiagText) beim nächsten Spieltest.
ns.OnUnit("UNIT_AURA", "target", function(_, unit)
    if ns.IsSecret(unit) or unit == "target" then updateSoon() end
end)
ns.On("PLAYER_TARGET_CHANGED", function()
    Auras.NewTarget()
    updateSoon()
end)
-- Kampfbeginn und -ende, Addon-Sperre des Spiels geändert: Die Sperre der Auren kippt, ohne dass sich eine Aura
-- ändert – neu lesen. Die Addon-Sperre meldet ezCore (Core.OnRestrictionChanged, CB-22; kennt ein Client das
-- Ereignis nicht, kommt keine Meldung – dann tragen Kampfbeginn und -ende allein).
for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
    ns.On(event, function() updateSoon() end)
end
ns.OnRestrictionChanged(updateSoon)

-- Eigener Takt für CheckExpiring (Symbolplatz „läuft aus“ und Leuchten am Aktionsknopf), alle 0,25 s: Er hängt an
-- keinem Rahmen – Blizzards Reihe (ezCore.AuraRow) führt keine fremden Skripte, und ohne sichtbare Reihe muss die
-- Warnung trotzdem kommen. Nur die eigene Reihe des Rückfalls prüft, solange sie sichtbar ist, in ihrem OnUpdate
-- (0,1 s, wegen des Leuchtens an ihren Symbolen); dann ruht dieser Takt.
-- Gesamtreview 18.11.2026 (T7-3): Der ganze Takt liegt in ns.Try (auch row:IsShown und ns.ShowAny), der Griff ist
-- gemerkt (Auras.ticker), und der Takt läuft nur, solange „läuft aus“ irgendwo erscheint (Einstellung showExpiring) –
-- vorher weckte er auch abgeschaltet viermal je Sekunde.
function Auras.Tick()
    if (not row or not row:IsShown()) and ns.ShowAny("expiring") and #current > 0 then
        Auras.CheckExpiring()
    end
end

function Auras.UpdateTicker()
    local want = ns.ShowAny("expiring")
    if want and not Auras.ticker and C_Timer.NewTicker then
        Auras.ticker = C_Timer.NewTicker(0.25, function() ns.Try("Auras", Auras.Tick) end)
    elseif not want and Auras.ticker then
        Auras.ticker:Cancel()
        Auras.ticker = nil
    end
    return Auras.ticker ~= nil
end
Auras.UpdateTicker()
ns.OnReady(Auras.UpdateTicker)
ns.OnSettingChanged(function(key)
    if key == ns.SHOW_KEYS.expiring then Auras.UpdateTicker() end
end)

---------------------------------------------------------------------------
-- Blizzards Zielfenster: eigene Auren größer
---------------------------------------------------------------------------

local bigApplied = false

local function Containers()
    local list = {}
    for _, unitFrame in ipairs({ TargetFrame, FocusFrame }) do
        if type(unitFrame) == "table" and type(unitFrame.GetAuraContainer) == "function" then
            local ok, container = pcall(unitFrame.GetAuraContainer, unitFrame)
            if ok and type(container) == "table" and type(container.SetLargeAuraSize) == "function" then
                list[#list + 1] = container
            end
        end
    end
    return list
end

-- Nur außerhalb des Kampfs; ausgeschaltet stellt ezCombat Blizzards Größe nur wieder her, wenn es sie geändert hat.
-- Aus heißt: Regler auf Blizzards Größe (Einstellungs-Prüfung 19.11.2026, Nr. 72; bis dahin Kästchen bigAuras).
function Auras.BigAurasOn()
    local size = ns.S and tonumber(ns.S.bigAuraSize)
    return size ~= nil and size > BLIZZARD_LARGE_SIZE
end

function Auras.ApplyBigAuras()
    if ns.InCombat() then return false end
    local enabled = Auras.BigAurasOn()
    if not enabled and not bigApplied then return false end
    local defaults = rawget(_G, "TargetFrameAuraContainerDefaults")
    local size = enabled and ns.S.bigAuraSize
        or (type(defaults) == "table" and defaults.LargeAuraSize) or BLIZZARD_LARGE_SIZE
    local done = false
    for _, container in ipairs(Containers()) do
        if pcall(container.SetLargeAuraSize, container, size) then done = true end
    end
    bigApplied = enabled and done
    return done
end

ns.On("PLAYER_REGEN_ENABLED", Auras.ApplyBigAuras)
ns.On("PLAYER_REGEN_ENABLED", Auras.UpdateParent)
ns.On("PLAYER_REGEN_DISABLED", function() Row() end)

-- Was die DoT-Reihe bei gesperrten Auren noch kann (/ezk status).
ns.AddStatusLine(function()
    if ns.secretSeen.auras then return L.STATUS_DOTS_SECRET end
end)
-- … und wenn das Spiel die Auren gar nicht herausgab: Dann fehlt die Warnung, und der Status sagt es (nie stumm).
ns.AddStatusLine(function()
    if ns.secretSeen.aurasUnread then return L.STATUS_DOTS_UNREAD end
end)
-- Welche Reihe über dem Zielfenster steht (für den Spieltest, CB-06/CB-07). Nur ezCombats eigene Reihe: Die Zahl
-- aller Auren-Reihen (Core.AuraRows.StatusLine, auch die anderer Module) nennt ezCore schon unter /ez status.
-- Wartet die Reihe auf das Kampfende (auch nach „Aus“ im Kampf), sagt es die Zeile.
ns.AddStatusLine(function()
    if blizzRow then
        if blizzRow:Pending() > 0 then return L.STATUS_DOTS_ROW_WAITING end
        if ns.Enabled("dots") then return L.STATUS_DOTS_BLIZZ_ROW end
        return nil
    end
    if rowMode == "own" and ns.Enabled("dots") then return L.STATUS_DOTS_OWN_ROW end
end)

-- Diagnose des letzten Lesens im Kampf (erscheint, sobald im Kampf einmal mit Ziel gelesen wurde): zeigt, an
-- welcher Stelle die Warnung hängen bleibt, wenn im Spiel nichts kommt.
function Auras.DiagText()
    if not diag then return nil end
    local ago = L.STATUS_AGO:format(ezCore.Duration(GetTime() - diag.when, true))
    if diag.noTarget then return L.STATUS_DOTS_DIAG_TARGET:format(ago) end
    local evaluated
    if not ns.ShowAt("expiring", "center") then
        evaluated = L.STATUS_DIAG_SYMBOL_OFF
    elseif diag.evaluated == nil then
        evaluated = L.STATUS_DIAG_NOT_TRIED
    else
        evaluated = diag.evaluated and L.STATUS_DIAG_OK or L.STATUS_DIAG_FAILED
    end
    return L.STATUS_DOTS_DIAG:format(ago, diag.ids and tostring(diag.ids) or L.STATUS_DIAG_NO_IDS,
        diag.read, diag.read - diag.secret, diag.secret, diag.unread, diag.listed, diag.withDuration, diag.named,
        (WarnCurve() and GateCurve()) and L.STATUS_DIAG_CURVES or L.STATUS_DIAG_NO_CURVES, evaluated)
end
ns.AddStatusLine(Auras.DiagText)

-- Wann zuletzt gewarnt wurde – oder dass bisher keiner deiner DoTs auslief (für den Spieltest).
ns.AddStatusLine(function()
    if not (ns.Enabled("dots") or ns.ShowAny("expiring")) then
        return L.STATUS_DOTS_OFF:format(ns.PathText("OPT_HEADER_DOTS", "OPT_dots"))
    end
    if Auras.last then
        return L.STATUS_DOTS_LAST:format(Auras.last.name,
            L.STATUS_AGO:format(ezCore.Duration(GetTime() - Auras.last.when, true)))
    end
    return L.STATUS_DOTS_NONE:format(ezCore.Duration(ns.S.dotWarn))
end)

ns.OnSettingChanged(function(key)
    if key == "bigAuraSize" then
        Auras.ApplyBigAuras()
    elseif key == "dots" or key == "dotWarn" or key == "showExpiring" then
        updateSoon()
    end
end)

ns.OnReady(function()
    Row()                   -- entscheidet zuerst, welche Reihe es gibt (Mode)
    Auras.ApplyBigAuras()
    updateSoon()
end)

-- Auswahl zum Verschieben (Bearbeitungsmodus, „Teile verschieben“): Beispiel-Symbole, solange sie offen ist.
ns.Listen("PARTS_SHOWING", function()
    Auras.Update()
    Auras.UpdateParent()
end)

-- Nach dem Bearbeitungsmodus die eigene Aurengröße erneut setzen (Blizzard baut die Einheitenfenster neu auf).
ns.Listen("EDIT_MODE", function(active)
    if not active then Auras.ApplyBigAuras() end
end)

-- Vorschau: zwei Beispiel-Symbole über dem Zielfenster, eines kurz vor Ablauf (leuchtet).
ns.AddPreview("dots", 30, function()
    if not (TargetFrame and TargetFrame:IsVisible()) then
        ns.Print(L.PREVIEW_NEED_TARGET)
        return false
    end
    current = DemoList()
    demoUntil = GetTime() + 4
    Auras.Update()
    C_Timer.After(4.1, updateSoon)
    return true
end)
