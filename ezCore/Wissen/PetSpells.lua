local _, ns = ...
local Core = ezCore

--[[
    Was der Begleiter noch lernen kann, ohne Besuch beim Ausbilder: Core.PetSpells (24.11.2026; Nutzer zum leeren Abschnitt
    „Begleiter“ in „Was kommt wann“, wörtlich: „"was kommt wann" - keine daten, wenn nicht anders möglich ok --> alle
    möglichkeiten von offiziellen daten abgefragt?“).

    Quellen (Leitlinien 11 und 12), alle aus dem Client:
      * Hexenmeister: Grimoires – Gegenstände, die dem Dämon eine Fähigkeit beibringen, mit nötiger Stufe und Händlerpreis
        (Client-Tabellen dieses Builds, Wissen/Client/PetBooks.lua, Schlüssel petBooks). Der Dämonenausbilder verkauft sie
        (kein Lehrerfenster; Core.Npcs, demonVendor), ein Besuch „beim Lehrer“ brächte also nie Daten.
      * Jäger: Lernzauber des Begleiters mit Lernstufe und dem, was sie lehren (Client-Tabelle classSpells, Art 1; id =
        der gelehrte Zauber). Kosten führt der Client nicht;
        ob der Tierausbilder sie lehrt oder das Zähmen, sagt er auch nicht – das sagt erst das Lehrerfenster (dann gelten
        dessen Daten, Core.Spells.Trainer).
      * Was er schon kann: Begleiter-Zauberbuch (Core.Spells.PetBook). Es nennt nur den gerufenen Begleiter; je Dämon merkt
        ezCore im Datensatz des Charakters, was er je konnte (petSpells = { [Linie] = { [Zauber] = Rang } }; vereint, nicht
        ersetzt: ein Dämon verlernt nichts, aber ein halb geladenes Zauberbuch nennt zu wenig). Nie gerufen (seit ezCore
        läuft): unbekannt, dann zählt nichts als „jetzt“. Ein versklavter Dämon (UnitIsCharmed) gilt nicht als eigener.

      PetSpells.List(stufe) → { kind = "book" | "trainer", now = { eintrag … }, open = { eintrag … }, later = { eintrag … },
                  unknown = { { line, owner, count } … }, source } | nil (Klasse ohne Begleiter, ohne Daten). eintrag =
                  { id, item, name, rank, level, cost, icon, line, owner, book | tables }: now = Stufe erreicht, der Dämon
                  kann es nicht; open = Stufe erreicht, aber ob er es kann oder lernen kann, weiß ezCore nicht (dieser Dämon
                  war noch nie gerufen, je Dämon gezählt in unknown; beim Jäger alles Erreichte, je Fähigkeit nur der höchste
                  Rang: der Client sagt nicht, welches Tier was lernen kann); later = ab einer höheren Stufe. Nach Stufe,
                  Name, Rang.
      PetSpells.Waiting(stufe) → Anzahl, Kosten, Liste (now), Art ("book" | "trainer" | nil ohne Daten)
      PetSpells.Owner(linie)   → Name des Dämons (Wichtel …) | nil
      PetSpells.Remember()     → das Zauberbuch des gerufenen Dämons merken; → Linie | nil
]]

local PetSpells = {}
Core.PetSpells = PetSpells

local Num = Core.Num

local L = Core.NewLocale({
    PET_OWNER_188 = "Wichtel", PET_OWNER_189 = "Teufelsjäger", PET_OWNER_204 = "Leerwandler", PET_OWNER_205 = "Sukkubus",
}, {
    PET_OWNER_188 = "Imp", PET_OWNER_189 = "Felhunter", PET_OWNER_204 = "Voidwalker", PET_OWNER_205 = "Succubus",
})

PetSpells.LINES = { 188, 204, 205, 189 }      -- Reihenfolge, in der die Dämonen kommen

function PetSpells.Owner(line)
    line = Num(line)
    local key = line and ("PET_OWNER_" .. line)
    local text = key and L[key]
    return text ~= key and text or nil
end

-- Alle Einträge der Klasse (Namen fragt der Client): Liste, Art | nil
local function Entries()
    local CD, S = Core.ClientData, Core.Spells
    local class = Core.PlayerClass()
    if not (CD and class and S and S.PetKind and S.PetKind(class)) then return nil end
    local out = {}
    local books = CD.Table("petBooks")
    local P = Core.Proficiency
    local classID = P and P.ClassID(class)
    for item, e in pairs(classID and type(books) == "table" and books or {}) do
        local spell = Num(e[1])
        if spell and P.HasBit(Num(e[2]) or 0, classID - 1) then
            out[#out + 1] = { id = spell, item = item, name = Core.SpellName(spell) or Core.ItemNameByID(item) or ("#" .. spell),
                rank = Num(e[4]) or 0, level = Num(e[3]) or 0, line = Num(e[5]), cost = Num(e[6]), book = true,
                owner = PetSpells.Owner(e[5]), icon = S.Icon(spell) }
        end
    end
    if #out > 0 then return out, "book" end
    for _, e in ipairs(CD.ClassSpells(class) or {}) do
        local id = e.teaches or e.id
        local name = e.pet and Core.SpellName(id)
        if name then
            out[#out + 1] = { id = id, name = name, rank = e.rank, level = e.level, icon = S.Icon(id), tables = true }
        end
    end
    if #out > 0 then return out, "trainer" end
    return nil
end

local function Sort(list)
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        if a.name ~= b.name then return a.name < b.name end
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.id < b.id
    end)
    return list
end

-- Zauberbuch des gerufenen Begleiters: { [Name] = höchster Rang } und, bei Grimoires, seine Linie. Der Rang kommt aus der
-- Tabelle (Zauber-Kennung), sonst aus dem Zusatztext des Clients, sonst 1: Rang 1 bringt der Dämon mit (kein Grimoire).
local function ReadBook(entries)
    if type(UnitIsCharmed) == "function" then
        local ok, charmed = pcall(UnitIsCharmed, "pet")
        if ok and not Core.IsSecret(charmed) and charmed == true then return nil end      -- versklavt, nicht der eigene
    end
    local book = Core.Spells.PetBook()
    if not book then return nil end
    local rankOf, lineOf = {}, {}
    for _, e in ipairs(entries) do
        rankOf[e.id] = e.rank
        if e.line then lineOf[e.name] = e.line end
    end
    local known, votes = {}, {}
    for _, b in ipairs(book) do
        local rank = math.max(rankOf[b.id] or b.rank or 0, 1)        -- ohne Rang (Phasenverschiebung): zählt wie 1
        if (known[b.name] or -1) < rank then known[b.name] = rank end
        local line = lineOf[b.name]
        if line then votes[line] = (votes[line] or 0) + 1 end
    end
    local line, best = nil, 0
    for _, id in ipairs(PetSpells.LINES) do
        if (votes[id] or 0) > best then line, best = id, votes[id] end
    end
    return known, line
end

function PetSpells.Remember()
    local entries, kind = Entries()
    if kind ~= "book" then return nil end
    local known, line = ReadBook(entries)
    local char = Core.Char()
    if not (known and line and char) then return nil end
    char.petSpells = type(char.petSpells) == "table" and char.petSpells or {}
    -- nur was es als Grimoire gibt, unter der Zauber-Kennung des Rangs (der Name hinge an der Sprache); zu dem, was schon
    -- gemerkt ist (ein halb geladenes Zauberbuch darf nichts vergessen lassen)
    local store = type(char.petSpells[line]) == "table" and char.petSpells[line] or {}
    for _, e in ipairs(entries) do
        if e.line == line and known[e.name] and known[e.name] >= math.max(e.rank, 1) then store[e.id] = e.rank end
    end
    char.petSpells[line] = store
    return line
end

function PetSpells.List(level)
    local entries, kind = Entries()
    if not entries then return nil end
    level = Num(level) or Core.PlayerLevel() or 1
    local known, line = ReadBook(entries)
    local char = Core.Char()
    local store = type(char) == "table" and type(char.petSpells) == "table" and char.petSpells or {}
    local out = { kind = kind, now = {}, open = {}, later = {}, unknown = {},
        source = Core.ClientData.SourceText(kind == "book" and "petBooks" or "classSpells") }
    local count, top = {}, {}              -- je Dämon die offenen; je Fähigkeit des Jägers der Platz in open
    for _, e in ipairs(Sort(entries)) do
        local knows
        if kind == "book" then
            local seen = type(store[e.line]) == "table" and store[e.line] or nil
            local live = known and line == e.line
            if live or seen then
                knows = (live and known[e.name] ~= nil and known[e.name] >= math.max(e.rank, 1))
                    or (seen ~= nil and seen[e.id] ~= nil)
            end
        elseif known and known[e.name] and known[e.name] >= math.max(e.rank, 1) then
            knows = true
        end
        if knows ~= true then
            if e.level > level then
                out.later[#out.later + 1] = e
            elseif knows == false then
                out.now[#out.now + 1] = e
            elseif e.line then
                out.open[#out.open + 1] = e
                count[e.line] = (count[e.line] or 0) + 1
            elseif not top[e.name] then
                out.open[#out.open + 1] = e
                top[e.name] = #out.open
            elseif out.open[top[e.name]].rank < e.rank then
                out.open[top[e.name]] = e
            end
        end
    end
    Sort(out.open)
    for _, id in ipairs(PetSpells.LINES) do
        if count[id] then out.unknown[#out.unknown + 1] = { line = id, owner = PetSpells.Owner(id), count = count[id] } end
    end
    return out
end

function PetSpells.Waiting(level)
    local res = PetSpells.List(level)
    local cost = 0
    for _, e in ipairs(res and res.now or {}) do cost = cost + (e.cost or 0) end
    return res and #res.now or 0, cost, res and res.now or {}, res and res.kind or nil
end

-- Begleiter gerufen, Fähigkeit gelernt: den Stand dieses Dämons merken
Core.Listen("SPELLS_KNOWN_CHANGED", function() Core.Try("ezCore", "PetSpells.Remember", PetSpells.Remember) end, "ezCore.PetSpells")
