local _, ns = ...
local Core = ezCore

--[[
    Art eines Zaubers (Welle 27, Paket modul/ezmacro-faehigkeiten; Wunsch des Nutzers vom 16.11.2026 auf die Frage
    „Makros aus deinen Fähigkeiten erzeugen und die Lücken der Liste füllen?“: „Ja, beides“). Abnehmer: ezMacro
    (Gruppe „Aus deinen Fähigkeiten“, SpellMacros.lua) – ein Makro je gelerntem Zauber nach seiner Art.

    Reihenfolge der Quellen (Leitlinie 11):
      1. der Client im Spiel: C_Spell.IsSpellHarmful / IsSpellHelpful (ältere Clients IsHarmfulSpell / IsHelpfulSpell)
         sagen, ob ein Zauber auf Gegner oder auf Mitspieler zielt; C_Spell.GetSpellInfo nennt Zauberzeit und Reichweite.
         Jede Antwort geht zuerst über Core.IsSecret (Leitlinie 6); eine gesperrte Antwort zählt als „weiß nicht“.
      2. die ausgelieferte Client-Tabelle Wissen/Client/SpellKinds.lua (laut wago.tools, erzeugt von
         tools/wago_ausliefern.lua, A.SpellKinds): was der Client nicht sagt – Unterbrechen, Kontrolle, Schaden über Zeit,
         Heilung, Selbst-Zauber, Lernzauber für den Begleiter.
    Widersprechen sich beide (Client „Gegner“, Tabelle „Heilung“), gilt der Client mit der allgemeinen Art seiner Seite
    („harm“ bzw. „help“). Sagt der Client nichts (keine Schnittstelle, gesperrt, weder noch), gilt die Tabelle. Weiß die
    Tabelle, dass ein Zauber nur dich selbst trifft, nur ausgelöst wird, wiederbelebt oder dem Begleiter etwas beibringt,
    gilt sie – das kann der Client nicht unterscheiden. Ebenso bei „any“ (Ziel beliebig, Gegner oder Mitspieler: Heiliger
    Schock, Sühne, Magiebannung, Gedankensicht, Wildtierkunde; Gegenprüfung zu Welle 27): eine Antwort „hilft“ allein
    machte daraus ein Makro, das bei einem Gegner als Ziel auf dich durchfällt.

      SpellKinds.KINDS                    Arten in Anzeigereihenfolge (die mit Makro zuerst)
      SpellKinds.FAMILY[art]              "harm" | "help" | nil (Arten ohne Ziel: self, proc, res, pet; any: beides)
      SpellKinds.Base(zauber)             → Grund-ID (Rang 1) laut Client-Tabellen, sonst die ID selbst
      SpellKinds.FromTable(zauber)        → art, grundID, klasse oder nil (Tabelle fehlt, Zauber unbekannt, gesperrt)
      SpellKinds.FromClient(zauber)       → "harm" | "help" | nil, { castTime (ms), minRange, maxRange } oder nil
      SpellKinds.Of(zauber)               → { id, base, kind, family, class, source = "client" | "tables" | "both",
                                             castTime } oder nil (weder Client noch Tabelle wissen etwas)
                                          maxRange: Reichweite laut Client (Meter; ezMacro erkennt daran Nahkampf)
      SpellKinds.ForClass(klasse)         → { [art] = { Grund-ID … } } (Kopie, für Abgleiche)
      SpellKinds.SourceText(quelle)       → „laut Client“ | „laut Client-Tabellen (wago.tools, Build …)“ | „Ziel laut Client,
                                          Art laut Client-Tabellen (…)“
]]

local SpellKinds = {}
Core.SpellKinds = SpellKinds

SpellKinds.KINDS = { "interrupt", "cc", "dot", "harm", "heal", "help", "any", "res", "self", "proc", "pet" }
SpellKinds.FAMILY = { interrupt = "harm", cc = "harm", dot = "harm", harm = "harm", heal = "help", help = "help" }
-- Arten, bei denen die Tabelle vor dem Client gilt (der Client kann sie nicht unterscheiden; „any“: er sagt nur eine Seite)
SpellKinds.TABLE_FIRST = { self = true, proc = true, res = true, pet = true, any = true }
SpellKinds.KEY = "spellKinds"

local L = Core.NewLocale({
    SPELLKINDS_SOURCE_CLIENT = Core.L.SOURCE_CLIENT,   -- ein Wortlaut für „laut Client“ (Kern/Locale.lua, T10-6)
    SPELLKINDS_SOURCE_BOTH = "Ziel laut Client, Art %s",
}, {
    SPELLKINDS_SOURCE_CLIENT = Core.L.SOURCE_CLIENT,
    SPELLKINDS_SOURCE_BOTH = "target according to the client, kind %s",
})
SpellKinds.L = L

local Num, Plain = Core.Num, Core.Plain

local function Id(v)
    if Core.IsSecret(v) then return nil end
    return Num(Plain(v))
end

-- [Zauber-ID] = { art, klasse } aus der ausgelieferten Tabelle, einmal gebaut (die Tabelle ändert sich im Spiel nicht)
local index
local function Index()
    if index then return index end
    local CD = Core.ClientData
    local data = CD and CD.Table and CD.Table(SpellKinds.KEY)
    if type(data) ~= "table" then return nil end
    index = {}
    for _, class in ipairs(Core.SortedKeys(data)) do
        for kind, list in pairs(type(data[class]) == "table" and data[class] or {}) do
            for _, id in ipairs(type(list) == "table" and list or {}) do
                if not index[id] then index[id] = { kind, class } end
            end
        end
    end
    return index
end

function SpellKinds.Base(spellID)
    spellID = Id(spellID)
    if not spellID then return nil end
    local CD = Core.ClientData
    local e = CD and CD.ClassSpell and CD.ClassSpell(spellID)
    return e and e.base or spellID
end

function SpellKinds.FromTable(spellID)
    spellID = Id(spellID)
    local idx = spellID and Index()
    if not idx then return nil end
    local row = idx[spellID]
    local base = spellID
    if not row then
        base = SpellKinds.Base(spellID)
        row = base and idx[base]
    end
    if not row then return nil end
    return row[1], base, row[2]
end

-- Antwort des Clients auf „schadet / hilft dieser Zauber?“: true, false oder nil (keine Schnittstelle, Fehler, gesperrt)
local function Ask(fn, spellID)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, spellID)
    if not ok or Core.IsSecret(value) or value == nil then return nil end
    return value and true or false
end

function SpellKinds.FromClient(spellID)
    spellID = Id(spellID)
    if not spellID then return nil end
    local S = C_Spell
    local harmful = Ask(S and S.IsSpellHarmful or IsHarmfulSpell, spellID)
    local helpful = Ask(S and S.IsSpellHelpful or IsHelpfulSpell, spellID)
    local info
    if S and type(S.GetSpellInfo) == "function" then
        local ok, t = pcall(S.GetSpellInfo, spellID)
        if ok and type(t) == "table" and not Core.IsSecret(t) then
            info = { castTime = Num(Plain(Core.Peek(t, "castTime"))), minRange = Num(Plain(Core.Peek(t, "minRange"))),
                maxRange = Num(Plain(Core.Peek(t, "maxRange"))) }
        end
    end
    local family
    if harmful and not helpful then family = "harm" elseif helpful and not harmful then family = "help" end
    return family, info
end

function SpellKinds.Of(spellID)
    spellID = Id(spellID)
    if not spellID then return nil end
    local tableKind, base, class = SpellKinds.FromTable(spellID)
    local family, info = SpellKinds.FromClient(spellID)
    local out = { id = spellID, base = base or SpellKinds.Base(spellID) or spellID, class = class,
        castTime = info and info.castTime or nil, maxRange = info and info.maxRange or nil }
    if tableKind and SpellKinds.TABLE_FIRST[tableKind] then
        out.kind, out.source = tableKind, "tables"
    elseif family and tableKind and SpellKinds.FAMILY[tableKind] == family then
        out.kind, out.source = tableKind, "both"
    elseif family then
        out.kind, out.source = family, "client"
    elseif tableKind then
        out.kind, out.source = tableKind, "tables"
    else
        return nil
    end
    out.family = SpellKinds.FAMILY[out.kind]
    return out
end

function SpellKinds.ForClass(class)
    local CD = Core.ClientData
    local data = CD and CD.Table and CD.Table(SpellKinds.KEY)
    local out = {}
    local t = type(data) == "table" and type(class) == "string" and data[class]
    for kind, list in pairs(type(t) == "table" and t or {}) do
        out[kind] = {}
        for i, id in ipairs(list) do out[kind][i] = id end
    end
    return out
end

function SpellKinds.SourceText(source)
    local CD = Core.ClientData
    local tables = CD and CD.SourceText and CD.SourceText(SpellKinds.KEY) or ""
    if source == "client" then return L.SPELLKINDS_SOURCE_CLIENT end
    if source == "both" then return L.SPELLKINDS_SOURCE_BOTH:format(tables) end
    return tables
end
