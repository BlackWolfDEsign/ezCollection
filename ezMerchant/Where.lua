local ADDON, ns = ...
local L = ns.L
local Core = ezCore

--[[
    „Wo kommt was“ im Zauberbuch – der Reiter direkt unter „Was kommt wann“ (Spellbook.lua). Auftrag und Entscheidungen
    des Nutzers vom 23.11.2026 (Wortlaut im ROADMAP-Index): „bei klassen und beruflehrer nur die eigenen“, „"zum lehrer"
    aus "was kommt wann" raus und dafür für alle bei "wo kommt was" rein“, Inhalt „Waffenmeister, Klassen- und
    Berufslehrer, Reitlehrer, Begleiter-Fähigkeiten“ (Berufslehrer seit dem 24.11.2026 am Berufefenster, unten) – beide Reiter gleich formatiert (dieselbe Ansicht aus ezCore,
    Core.NewSpellbookView: Kopfzeile je Abschnitt, Einträge mit Symbol, Name, zwei kleinen Zeilen, Tooltip, Quelle in der
    Fußzeile).

    Schritt (a), 24.11.2026: je Art ein Abschnitt – Klassenlehrer (nur die eigene Klasse), Waffenmeister, Reitlehrer.
    Oben im Abschnitt „Zum …“ (der nächste auf deinem Kontinent, ein Klick setzt Blizzards Kartenmarkierung – der Eintrag,
    der bisher als „Zum Lehrer“ in „Was kommt wann“ stand), darunter die übrigen bekannten, der nächste zuerst (höchstens
    W.MAX je Art; ein Klick setzt die Markierung auf genau diesen).

    Schritt (b), 24.11.2026: Abschnitt „Begleiter“ (dasselbe Wort wie der Abschnitt in „Was kommt wann“, der seine
    Fähigkeiten zeigt; Entscheidung „begleiter-fähigkeiten zu "was kommt wann" und dessen lehrer zu "wo kommt was" -->
    beides konsistent formatiert“) direkt nach den Klassenlehrern, nur für Klassen mit Begleiter (Core.Spells.PetKind):
    Jäger mit den Tierausbildern (Art „pet“), Hexenmeister mit den Dämonenausbildern (Merkmal demon, ezCore am Titel).

    Berufe stehen nicht hier, sondern am Berufefenster (ezCraft, Reiter „Was kommt wann“ und „Wo kommt was“ für den
    gewählten Beruf; Nutzer am 24.11.2026, wörtlich: „wtf ich habe doch gesagt Berufelehrer gehören ins Berufefenster "wo
    kommt was" ebenso für "was kommt wann"“, „zauberbuch vs berufe grenzt das doch klar ab“). Vorher (Schritt c, 24.11.2026)
    stand hier je eigener Beruf ein Abschnitt am Ende.

    Welche Waffenfertigkeit wo, 24.11.2026 (Auftrag „Waffenmeister – welche Fertigkeit wo“, gebaut auf ezCore.Proficiency
    aus dem Paket ezgear/lernbar-tragbar, nicht doppelt – Leitlinie 2): im Abschnitt „Waffenmeister“ unter den Lehrern
    die Waffenfertigkeiten, die du noch lernen kannst (Proficiency.Learnable("weapon")), je „ab Stufe n“ (laut
    Client-Tabellen) und wo: der Lehrer, bei dem du sie im Lehrerfenster gesehen hast (Name und Gebiet), sonst „beim
    Waffenmeister“ (Classic-Regel, im Spiel zu bestätigen). Ein Klick setzt die Markierung auf diesen Lehrer bzw. den
    nächsten Waffenmeister.

    Rüstungsfertigkeiten, 24.11.2026 (Auftrag aus dem Spieltest; Entscheidung des Nutzers „Ja (Empfohlen)“, Wortlaut im
    ROADMAP-Index): dieselbe Liste im Abschnitt „Klassenlehrer“ (Proficiency.Learnable("armor"), etwa Platte und Kette ab
    40), Klick ohne gesehenen Lehrer: der nächste Klassenlehrer. Klassen, die keine Rüstung mehr lernen, sehen nichts davon.

    Schritt (d), 24.11.2026 (Entscheidung des Nutzers vom 23.11.2026, wörtlich: „Klassenquests,Fähigkeiten aus
    Gegenständen“): nach den Lehrern die Abschnitte „Klassenquests“ (nicht erledigte Quests nur deiner
    Klasse laut Questie, die laut Client eine Fähigkeit bringen; die übrigen aufklappbar „Belohnung noch unbekannt“) und
    „Bücher und Folianten“ (Gegenstände, die laut Client-Tabellen eine Fähigkeit deiner Klasse lehren, die du noch nicht
    kannst, mit Fundort laut ezCore). Daten: Core.SpellSources. Ein Klick setzt die Markierung auf den Geber bzw. Fundort.
    Ohne Inhalt fehlt der Abschnitt.

    Quellen (Leitlinie 11): die Lehrer, deren Fenster du geöffnet hast (ezCore, Core.Npcs) und – mit ezMap, solange
    Questie läuft – alle deines Kontinents laut Questie (ezCore.API("ezMap").TrainersNear, nur zur Laufzeit, nichts
    gespeichert). Ohne ezMap nur die besuchten, ohne Kartenmarkierung. Jeder Eintrag nennt seine Quelle („laut
    Questie“, „von dir besucht“), die Fußzeile sagt, woher die Liste stammt. Kein eigener Speicher, nichts Geschütztes:
    ein Klick ruft nur ezMaps Kartenmarkierung (SetWaypoint).
]]

local W = {}
ns.Where = W

local TAB_ICON = "Interface\\Icons\\INV_Misc_Map_01"
local WAY_ICON = "Interface\\Icons\\INV_Misc_Map_01"
W.ORDER = 15            -- Seitenreiter-Stapel: direkt unter „Was kommt wann“ (10), über ezMacro (20)
W.MAX = 5               -- bekannte Lehrer je Art unter „Zum …“ (der Rest als „… und n weitere“)

local view              -- Core.NewSpellbookView, angelegt beim Einloggen

-- Arten in der Reihenfolge der Abschnitte. Texte der Klassenlehrer sind die bisherigen von „Zum Lehrer“
-- (UPCOMING_WAY_*), die übrigen je Art eigene ganze Sätze (für die Übersetzung).
W.KINDS = { "class", "weapon", "riding" }
-- Abschnitt „Begleiter“ je Klasse (Schritt b): Art des Ausbilders; steht nach den Klassenlehrern (W.Kinds)
W.PET_SECTION = { HUNTER = "pet", WARLOCK = "demon" }
local KIND = {
    class = { head = L.WHERE_HEAD_class, short = L.UPCOMING_WAY_SHORT, title = L.UPCOMING_WAY,
        tip = L.UPCOMING_WAY_TIP, unknown = L.UPCOMING_WAY_UNKNOWN, none = L.UPCOMING_WAY_NONE,
        icon = "Interface\\Icons\\INV_Misc_Book_09" },
    weapon = { head = L.WHERE_HEAD_weapon, short = L.WHERE_WAY_weapon, title = L.WHERE_WAY_TITLE_weapon,
        tip = L.WHERE_WAY_TIP_weapon, unknown = L.WHERE_WAY_UNKNOWN_weapon, none = L.WHERE_WAY_NONE_weapon,
        icon = "Interface\\Icons\\INV_Sword_04" },
    riding = { head = L.WHERE_HEAD_riding, short = L.WHERE_WAY_riding, title = L.WHERE_WAY_TITLE_riding,
        tip = L.WHERE_WAY_TIP_riding, unknown = L.WHERE_WAY_UNKNOWN_riding, none = L.WHERE_WAY_NONE_riding,
        icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    pet = { head = L.UPCOMING_PET, short = L.WHERE_WAY_pet, title = L.WHERE_WAY_TITLE_pet,
        tip = L.WHERE_WAY_TIP_pet, unknown = L.WHERE_WAY_UNKNOWN_pet, none = L.WHERE_WAY_NONE_pet,
        icon = "Interface\\Icons\\Ability_Hunter_BeastTaming" },
    demon = { head = L.UPCOMING_PET, short = L.WHERE_WAY_demon, title = L.WHERE_WAY_TITLE_demon,
        tip = L.WHERE_WAY_TIP_demon, unknown = L.WHERE_WAY_UNKNOWN_demon, none = L.WHERE_WAY_NONE_demon,
        icon = "Interface\\Icons\\Spell_Shadow_SummonImp" },
}
W.KIND = KIND

-- Texte und Symbol einer Art
function W.Spec(kind) return KIND[kind] end

local function Text(kind, field)
    local spec = W.Spec(kind)
    return spec and spec[field] or nil
end

-- Abschnitt „Begleiter“ dieser Klasse ("pet" | "demon") oder nil: nur, wenn ezCore der Klasse Begleiter-Fähigkeiten
-- zuordnet – dieselbe Frage wie „Was kommt wann“ (U.PetKind → "HUNTER:PET" …; die Klasse steht in der Antwort)
function W.PetSection()
    local U = ns.Upcoming
    local kind = U and type(U.PetKind) == "function" and U.PetKind() or nil
    local class = type(kind) == "string" and kind:match("^(%u+):PET$") or nil
    return class and W.PET_SECTION[class] or nil
end

-- Abschnitte in ihrer Reihenfolge: Klassenlehrer, (Begleiter), Waffenmeister, Reitlehrer
function W.Kinds()
    local kinds = { W.KINDS[1] }
    local pet = W.PetSection()
    if pet then kinds[#kinds + 1] = pet end
    for i = 2, #W.KINDS do kinds[#kinds + 1] = W.KINDS[i] end
    return kinds
end

-- Bisherige Felder für Tests und Rundgang: W.view/W.frame = Rahmen der Ansicht, W.tab
setmetatable(W, { __index = function(_, key)
    if not view then return nil end
    if key == "view" or key == "frame" then return view.frame end
    if key == "tab" then return view.tab end
    return nil
end })

---------------------------------------------------------------------------
-- Lehrer: über ezMap (besucht und laut Questie, nach Entfernung) bzw. ohne ezMap die besuchten laut ezCore
---------------------------------------------------------------------------

-- Seit dem 24.11.2026 steht das in ezCore (Core.TrainerSpots, gemeinsam mit ezCraft am Berufefenster); die Namen hier
-- reichen weiter.
-- (in needs geprüft; die Datei lädt vor der Prüfung, deshalb erst beim Aufruf nachschlagen)
local TS = setmetatable({}, { __index = function(_, key) return Core.TrainerSpots and Core.TrainerSpots[key] or nil end })

function W.MapAPI() return TS.MapAPI() end
function W.Fits(t, kind) return TS.Fits(t, kind) end
function W.Read() return TS.Read() end
function W.List(kind, read) return TS.List(kind, read or W.Read()) end
function W.Nearest(kind, list) return TS.Nearest(kind, list) end
function W.TrainerName(t) return TS.Name(t) end
function W.TrainerPlace(t) return TS.Place(t) end
function W.PositionKnown() return TS.PositionKnown() end
local function SourceLabel(t) return TS.SourceLabel(t) end

---------------------------------------------------------------------------
-- Kartenmarkierung
---------------------------------------------------------------------------

-- Markierung auf genau diesen Lehrer setzen und im Chat sagen, wohin (oder warum nicht). → true, wenn gesetzt
function W.GoTo(t)
    local done, why = TS.Mark(t)
    if done then
        ns.Print(L.UPCOMING_WAY_SET:format(W.TrainerName(t), W.TrainerPlace(t)))
        return true
    end
    if why == "nomap" then
        ns.Print(L.UPCOMING_WAY_NOMAP)
    elseif why ~= "noplace" then
        ns.Print(L.UPCOMING_WAY_FAILED:format(tostring(why)))
    end
    return false
end

-- Markierung auf den nächsten Lehrer einer Art (vorher U.GoToTrainer, nur Klassenlehrer). → true, wenn gesetzt
function W.GoNearest(kind)
    kind = W.Spec(kind) and kind or "class"
    if not W.MapAPI() then
        ns.Print(L.UPCOMING_WAY_NOMAP)
        return false
    end
    local t = W.Nearest(kind, (W.List(kind)))
    if not t then
        ns.Print(W.PositionKnown() and Text(kind, "none") or L.UPCOMING_WAY_NOPOS)
        return false
    end
    return W.GoTo(t)
end

---------------------------------------------------------------------------
-- Zeilen der Ansicht
---------------------------------------------------------------------------

-- Eintrag „Zum …“ (nur mit ezMap; vorher U.WayLine, nur Klassenlehrer): der nächste auf deinem Kontinent, ein Klick
-- setzt die Markierung. list = W.List(kind), schon gelesen (sonst liest der Eintrag selbst).
function W.WayLine(kind, list)
    kind = W.Spec(kind) and kind or "class"
    if not W.MapAPI() then return nil end
    local t = W.Nearest(kind, list or (W.List(kind)))
    local sub
    if t then
        sub = L.UPCOMING_WAY_TO:format(W.TrainerName(t), W.TrainerPlace(t))
    else                                        -- wie W.GoNearest: ohne Position heißt nil nicht „keiner gemerkt“
        sub = W.PositionKnown() and Text(kind, "unknown") or L.UPCOMING_WAY_NOPOS_SHORT
    end
    -- Kurzer Name im Eintrag (Spielbefund des Nutzers vom 19.11.2026: „Lehrer auf der...“ stand abgeschnitten), der
    -- volle Text ist der Titel des Tooltips.
    local short = Text(kind, "short")
    local tip = { { Text(kind, "tip"), "highlight" } }
    -- Quelle des genannten Lehrers selbst (er steht nicht noch einmal in der Liste darunter; Leitlinie 11, Hinweis des
    -- Reviews vom 24.11.2026): „Nächster: Name – laut Questie“ bzw. „von dir besucht“
    local source = t and SourceLabel(t)
    if source then tip[#tip + 1] = { L.WHERE_WAY_NEAREST_SOURCE:format(W.TrainerName(t), source), "normal" } end
    tip[#tip + 1] = { L.UPCOMING_WAY_SOURCE_TIP, "hint" }
    return { kind = "spell", action = kind == "class" and "trainerWay" or "way", way = kind, npc = t,
        left = short, name = short, title = Text(kind, "title"),
        sub = sub, detail = L.UPCOMING_WAY_SOURCE, icon = WAY_ICON, style = "trainable", tooltip = tip }
end

-- Eintrag eines bekannten Lehrers: Name, Ort, Quelle; Tooltip mit Titel, Ort samt Koordinaten, Quelle und Klick.
function W.NpcLine(kind, t, withMap)
    local place = W.TrainerPlace(t)
    local source = SourceLabel(t)
    local tip = {}
    local coords = Core.CoordText and ns.Num(t.x) and ns.Num(t.y) and Core.CoordText(t.x, t.y, 1) or nil
    tip[#tip + 1] = coords and (place .. " " .. coords) or place
    if source then tip[#tip + 1] = { source, "hint" } end
    tip[#tip + 1] = withMap and { L.WHERE_NPC_CLICK, "highlight" } or { L.WHERE_NPC_NOMAP, "hint" }
    return { kind = "spell", action = "npc", way = kind, npc = t, left = t.name, name = t.name,
        title = W.TrainerName(t), sub = place, detail = source or "", icon = Text(kind, "icon"), tooltip = tip }
end

-- Abschnitt einer Art an lines anhängen. read = schon gelesenes W.Read() (sonst liest die Funktion selbst).
-- → lines, wartet (Questie liest noch)
-- Tooltip des Knopfs an der Überschrift: Titel, wohin, Quelle des nächsten, was der Klick tut (aus W.WayLine)
local function WayTip(way)
    local parts = { way.title, way.sub }
    for _, t in ipairs(type(way.tooltip) == "table" and way.tooltip or {}) do
        parts[#parts + 1] = type(t) == "table" and t[1] or t
    end
    local out = {}
    for _, p in ipairs(parts) do if type(p) == "string" and p ~= "" then out[#out + 1] = p end end
    return table.concat(out, "\n")
end

W.expanded = {}         -- [Art] = true: „… und n weitere“ aufgeklappt (bis /reload)

function W.SectionLines(kind, lines, read)
    lines = lines or {}
    local list, pending, withMap = W.List(kind, read)
    -- „Zum …“ als Kartenmarkierungs-Knopf direkt neben der Überschrift (Spieltest-Befund des Nutzers vom 24.11.2026:
    -- „zum lehrer button wie im bild zu sehen, direkt neben titel“); die Liste darunter zeigt auch den nächsten
    local head = { kind = "header", left = Text(kind, "head"), where = kind }
    local way = withMap and W.WayLine(kind, list) or nil
    if way then
        head.button = { icon = WAY_ICON, tip = WayTip(way) }
        head.action, head.way, head.npc, head.wayLine = way.action, kind, way.npc, way
    end
    lines[#lines + 1] = head
    local max = W.expanded[kind] and math.huge or W.MAX
    local shown, rest = 0, 0
    for _, t in ipairs(list) do
        if shown < max then
            lines[#lines + 1] = W.NpcLine(kind, t, withMap)
            shown = shown + 1
        else
            rest = rest + 1
        end
    end
    -- „… und n weitere“ aufklappbar (Befund vom 24.11.2026: „das "5weitere" AUSKLAPPBAR“), aufgeklappt „weniger“
    if rest > 0 then
        lines[#lines + 1] = { kind = "text", left = Core.More(rest), where = kind, action = "more", fold = false, tip = L.WHERE_MORE_TIP }
    elseif W.expanded[kind] and shown > W.MAX then
        lines[#lines + 1] = { kind = "text", left = L.WHERE_LESS, where = kind, action = "less", fold = true, tip = L.WHERE_LESS_TIP }
    end
    if shown == 0 then
        lines[#lines + 1] = { kind = "text", left = way and way.sub or L.WHERE_NONE, where = kind }
    end
    if W.SKILLS[kind] then W.SkillLines(kind, lines, withMap) end
    return lines, pending
end

---------------------------------------------------------------------------
-- Welche Waffen- und Rüstungsfertigkeit wo (Kopf): Daten aus ezCore (Core.Proficiency), hier nur die Form
---------------------------------------------------------------------------

-- Abschnitt » welche Fertigkeiten darunter: Art laut ezCore, Kopfzeile, Hinweise und die Regel, wer sie lehrt, solange du
-- sie noch bei keinem Lehrer gesehen hast. none = nil: ist nichts zu lernen, entfällt die Liste.
W.SKILLS = {
    weapon = { art = "weapon", head = L.WHERE_SKILLS, none = L.WHERE_SKILLS_NONE, unclear = L.WHERE_SKILLS_UNCLEAR,
        rule = L.WHERE_SKILL_SRC_RULE },
    class = { art = "armor", head = L.WHERE_ARMOR, unclear = L.WHERE_ARMOR_UNCLEAR, rule = L.WHERE_ARMOR_SRC_RULE },
}

-- Waffen- bzw. Rüstungsfertigkeiten, die du noch lernen kannst (art = "weapon" | "armor") → Liste, unklar (Client sagt
-- noch nichts Verlässliches); nil ohne ezCores Teil oder bei einem Fehler (dann fehlt die Liste, der Abschnitt bleibt)
function W.Skills(art)
    local P = Core.Proficiency
    if not (type(P) == "table" and type(P.Learnable) == "function") then return nil end
    local ok, list, unclear = pcall(P.Learnable, art or "weapon")
    if not ok then
        ns.Error(list, "Where.Skills")
        return nil
    end
    return type(list) == "table" and list or {}, unclear == true
end

-- Gesehener Lehrer mit Ort für die Kartenmarkierung (Core.Npcs: map, x, y) oder nil
local function SkillTarget(way)
    local place = type(way) == "table" and type(way.place) == "table" and way.place or nil
    local N = Core.Npcs
    local t = place and place.npc and N and type(N.Get) == "function" and N.Get(place.npc) or nil
    if t and ns.Num(t.map) and ns.Num(t.x) and ns.Num(t.y) then return t end
    -- Lehrer aus Beiträgen anderer Spieler: Ort steht am Weg selbst
    if place and ns.Num(place.map) and ns.Num(place.x) and ns.Num(place.y) then return place end
    return nil
end

-- Lehrerart ohne gesehenen Ort: der Weg sagt sie (gesehen beim Klassenlehrer bzw. Regel), sonst Waffenmeister
local function SkillTrainerKind(way)
    return type(way) == "table" and way.trainer == "class" and "class" or "weapon"
end

-- Eine Fertigkeit: Name, wo (gesehener Lehrer bzw. „beim Waffenmeister“/„beim Klassenlehrer“), ab Stufe n bzw. jetzt
-- lernbar; Tooltip mit Stufe und Quelle (Client-Tabellen), Lehrer und Quelle (gesehen bzw. Regel) und was der Klick tut.
function W.SkillLine(kind, way, level, withMap)
    local from = ns.Num(way.from) or 1
    local now = from <= level
    local place = type(way.place) == "table" and way.place or nil
    local byClass = SkillTrainerKind(way) == "class"
    local where
    if place then
        where = L.WHERE_SKILL_AT:format(place.name or "?", place.zone or "?")
    else
        where = byClass and L.WHERE_SKILL_CLASS or L.WHERE_SKILL_TRAINER
    end
    -- Quelle (Leitlinie 11, Hinweis des Reviews vom 24.11.2026): aus Beiträgen, gesehen mit Ort, gesehen ohne Ort, sonst
    -- die Regel
    local source = type(way.shared) == "string" and (way.seen and L.WHERE_SKILL_SRC_SEEN_SHIP
            or place and L.WHERE_SKILL_SRC_SHIP or L.WHERE_SKILL_SRC_SHIP_NOPLACE):format(way.shared)
        or place and L.WHERE_SKILL_SRC_SEEN or (way.seen and L.WHERE_SKILL_SRC_SEEN_NOPLACE)
        or (W.SKILLS[kind] or W.SKILLS.weapon).rule
    local tip = { L.WHERE_SKILL_TIP_LEVEL:format(from), { L.WHERE_SKILL_SRC_LEVEL, "hint" }, where, { source, "hint" } }
    if withMap then
        local click = SkillTarget(way) and L.WHERE_NPC_CLICK
            or (byClass and L.WHERE_SKILL_CLICK_CLASS) or L.WHERE_SKILL_CLICK_NEAREST
        tip[#tip + 1] = { click, "highlight" }
    else
        tip[#tip + 1] = { L.WHERE_NPC_NOMAP, "hint" }
    end
    local S = Core.Spells
    local icon = way.spell and S and type(S.Icon) == "function" and S.Icon(way.spell) or nil
    local name = way.name or "?"
    return { kind = "spell", action = "skill", skill = way, way = kind, left = name, name = name, sub = where,
        detail = now and L.UPCOMING_TRAINABLE or L.UPCOMING_LEVEL:format(from), icon = icon, spellID = way.spell,
        style = now and "trainable" or "future", readable = true, tooltip = tip }
end

-- „Waffenfertigkeiten (bzw. Rüstungsfertigkeiten), die du noch lernen kannst“ an lines anhängen (ohne ezCores Teil
-- nichts).
function W.SkillLines(kind, lines, withMap)
    local spec = W.SKILLS[kind]
    if not spec then return lines end
    local list, unclear = W.Skills(spec.art)
    if list == nil or (#list == 0 and not unclear and not spec.none) then return lines end
    lines[#lines + 1] = { kind = "text", left = spec.head, where = kind }
    local level = Core.PlayerLevel() or 1
    for _, way in ipairs(list) do
        if type(way) == "table" then lines[#lines + 1] = W.SkillLine(kind, way, level, withMap) end
    end
    if unclear then
        lines[#lines + 1] = { kind = "text", left = spec.unclear, where = kind }
    elseif #list == 0 then
        lines[#lines + 1] = { kind = "text", left = spec.none, where = kind }
    end
    return lines
end

-- Klick auf eine Fertigkeit: der gesehene Lehrer (mit Ort laut ezCore), sonst der nächste Lehrer seiner Art
-- (Klassenlehrer, wenn der Weg ihn nennt, sonst Waffenmeister) – dasselbe, was der Tooltip ansagt
function W.GoSkill(line)
    local t = SkillTarget(line.skill)
    if t then return W.GoTo(t) end
    return W.GoNearest(SkillTrainerKind(line.skill))
end

local function WhereText(e)
    local K = Core.Knowledge
    local text = K and type(K.WhereText) == "function" and K.WhereText(e) or nil
    return type(text) == "string" and text or "?"
end

-- Bis zu drei Fundorte samt Quelle an einen Tooltip hängen → erster Fundort mit Ort (für die Kartenmarkierung) oder nil
local function WhereTip(where, tip)
    local place
    for i, e in ipairs(where) do
        if not place and ns.Num(e.map) and ns.Num(e.x) and ns.Num(e.y) then place = e end
        if i <= 3 then
            tip[#tip + 1] = WhereText(e)
            if type(e.source) == "string" then tip[#tip + 1] = { e.source, "hint" } end
        end
    end
    return place
end

-- Letzte Zeile eines Tooltips: was der Klick tut bzw. warum es keinen gibt
local function ClickTip(tip, place, withMap)
    if place then
        tip[#tip + 1] = withMap and { L.WHERE_NPC_CLICK, "highlight" } or { L.WHERE_NPC_NOMAP, "hint" }
    else
        tip[#tip + 1] = { L.WHERE_RECIPE_NOPLACE, "hint" }
    end
end

---------------------------------------------------------------------------
-- Klassenquests und Bücher (Schritt d): Daten aus ezCore (Core.SpellSources), hier nur die Form
---------------------------------------------------------------------------

local function Ask(name)
    local S = Core.SpellSources
    if not (type(S) == "table" and type(S[name]) == "function") then return nil end
    local ok, res, why = pcall(S[name])
    if not ok then
        ns.Error(res, "Where." .. name)
        return nil
    end
    return res, why
end

-- Ab Stufe n bzw. jetzt: Stil des Eintrags
local function LevelStyle(level)
    return (ns.Num(level) or 0) <= (Core.PlayerLevel() or 1) and "trainable" or "future"
end

local function SpellText(spell)
    local S = Core.Spells
    local name = Core.SpellName and Core.SpellName(spell) or nil
    return type(name) == "string" and name or ("#" .. tostring(spell)),
        S and type(S.Icon) == "function" and S.Icon(spell) or nil
end

-- Eine Klassenquest. Mit bekannter Belohnung: Name = die Fähigkeit, darunter die Quest („führt dorthin“ bei einem Schritt
-- der Reihe) und wo sie beginnt; ohne: Name = die Quest. Quelle je Angabe (Questie, Client, Leitfaden); Klick: Markierung
-- auf den Geber.
function W.QuestLine(kind, q, withMap)
    local S = Core.SpellSources
    local from = S and type(S.QuestPlace) == "function" and Core.Call(S.QuestPlace, q.id) or nil
    from = type(from) == "table" and from or nil
    local place = from and ns.Num(from.map) and ns.Num(from.x) and ns.Num(from.y) and from or nil   -- für die Markierung
    local spell = q.spells and q.spells[1]
    local questName = type(q.name) == "string" and q.name or ("#" .. tostring(q.id))
    local at = from and (place and ("%s, %s"):format(from.name or "?", W.TrainerPlace(place)) or from.name) or nil
    local names, icon = {}, nil
    for i, id in ipairs(q.spells or {}) do
        local text, ic = SpellText(id)
        names[#names + 1] = text
        if i == 1 then icon = ic end
    end
    local name = spell and table.concat(names, q.either and L.WHERE_QUEST_OR or ", ") or questName
    local questText = (q.lead and L.WHERE_QUEST_LEAD or L.WHERE_QUEST):format(questName)
    local tip = {}
    if spell then tip[#tip + 1] = { questText, "highlight" } end
    if spell and q.either and #names > 1 then tip[#tip + 1] = L.WHERE_QUEST_EITHER end
    if q.steps then tip[#tip + 1] = L.WHERE_QUEST_STEPS:format(q.steps) end
    tip[#tip + 1] = at and L.WHERE_QUEST_START:format(at) or L.WHERE_QUEST_NOSTART
    if q.level then tip[#tip + 1] = L.WHERE_QUEST_LEVEL:format(q.level) end
    local source = q.from == "guide" and L.WHERE_QUEST_SRC_GUIDE or (q.from == "wiki" and L.WHERE_QUEST_SRC_WIKI) or L.WHERE_QUEST_SRC
    tip[#tip + 1] = { spell and source or (q.failed and L.WHERE_QUEST_SRC_FAILED) or L.WHERE_QUEST_SRC_OPEN, "hint" }
    if spell and q.failed then tip[#tip + 1] = { L.WHERE_QUEST_FAILED, "hint" } end    -- laut Leitfaden, aber ohne Auskunft
    if place then ClickTip(tip, place, withMap) end
    return { kind = "spell", action = place and "place" or nil, place = place, way = kind, quest = q.id,
        left = name, name = name, sub = spell and questText or at or L.WHERE_QUEST_NOSTART,
        detail = q.active and L.WHERE_QUEST_ACTIVE or (q.level and L.UPCOMING_LEVEL:format(q.level)) or "", icon = icon or "Interface\\Icons\\INV_Misc_Note_01",
        spellID = spell, style = LevelStyle(q.level), readable = true, tooltip = tip }
end

W.QUESTS_MAX = 8           -- so viele Klassenquests mit Fähigkeit, der Rest aufklappbar (nach Stufe)

-- Abschnitt „Klassenquests“ an lines (nur mit Inhalt): erst die, die zu einer Fähigkeit führen (nach Stufe, der Rest
-- aufklappbar), dann aufklappbar die mit noch unbekannter Belohnung. Liest Questie noch, fehlt es oder antwortet es nicht,
-- sagt eine Zeile das.
function W.QuestLines(lines, withMap)
    local kind = "quests"
    local res, why = Ask("Quests")
    if not res then
        local text = why == "building" and L.WHERE_QUESTS_PENDING or (why == "missing" and L.WHERE_QUESTS_MISSING)
            or (why and L.WHERE_QUESTS_FAILED)
        if text then
            lines[#lines + 1] = { kind = "header", left = L.WHERE_HEAD_quests, where = kind }
            lines[#lines + 1] = { kind = "text", left = text, where = kind }
        end
        return lines
    end
    if #res.taught == 0 and #res.open == 0 then return lines end
    lines[#lines + 1] = { kind = "header", left = L.WHERE_HEAD_quests, where = kind }
    local all = W.expanded.questsTaught == true
    for i, q in ipairs(res.taught) do
        if all or i <= W.QUESTS_MAX then lines[#lines + 1] = W.QuestLine(kind, q, withMap) end
    end
    if #res.taught > W.QUESTS_MAX then
        lines[#lines + 1] = { kind = "text", where = "questsTaught", action = all and "less" or "more", fold = all,
            left = all and L.WHERE_LESS or Core.More(#res.taught - W.QUESTS_MAX), tip = all and L.WHERE_LESS_TIP or L.WHERE_MORE_TIP }
    end
    if #res.open > 0 then
        local open = W.expanded[kind] == true
        lines[#lines + 1] = { kind = "text", where = kind, action = open and "less" or "more", fold = open,
            left = open and L.WHERE_LESS or L.WHERE_QUESTS_OPEN:format(#res.open),
            tip = open and L.WHERE_LESS_TIP or L.WHERE_QUESTS_OPEN_TIP }
        if open then
            for _, q in ipairs(res.open) do lines[#lines + 1] = W.QuestLine(kind, q, withMap) end
        end
    end
    return lines
end

-- Ein Buch: Name = die Fähigkeit, darunter der Fundort (bzw. „Fundort unbekannt“); Tooltip mit dem Gegenstand, der Stufe,
-- bis zu drei Fundorten samt Quelle und was der Klick tut.
function W.BookLine(kind, b, withMap)
    local first = b.where[1]
    local item = type(b.itemName) == "string" and b.itemName or ("#" .. tostring(b.item))
    local tip = { { L.WHERE_BOOK_ITEM:format(item), "highlight" } }
    if (ns.Num(b.level) or 0) > 0 then tip[#tip + 1] = L.WHERE_SKILL_TIP_LEVEL:format(b.level) end
    tip[#tip + 1] = { L.WHERE_BOOK_SRC, "hint" }
    local place = WhereTip(b.where, tip)
    if first then
        ClickTip(tip, place, withMap)
    else
        tip[#tip + 1] = { b.loading and L.WHERE_BOOK_LOADING or L.WHERE_BOOK_NOWHERE_TIP, "hint" }
    end
    local _, icon = SpellText(b.spell)
    local name = b.name or "?"
    if (ns.Num(b.rank) or 0) > 0 then
        name = L.WHERE_BOOK_RANK:format(name, b.rank)
    else                                    -- ohne Rang: der Zusatz des Clients („Schildkröte“), sobald er ihn kennt
        local extra = Core.Plain(Core.Call(C_Spell and C_Spell.GetSpellSubtext, b.spell))
        if type(extra) == "string" and extra ~= "" then name = ("%s (%s)"):format(name, extra) end
    end
    return { kind = "spell", action = place and "place" or nil, place = place, way = kind, item = b.item,
        left = name, name = name, sub = first and WhereText(first) or (b.loading and L.WHERE_BOOK_LOADING) or L.WHERE_BOOK_NOWHERE,
        detail = first and type(first.source) == "string" and first.source or L.UPCOMING_LEVEL:format(b.level or 0),
        icon = icon, spellID = b.spell, style = LevelStyle(b.level), readable = true, tooltip = tip }
end

-- Abschnitt „Bücher und Folianten“ an lines (nur mit Inhalt; höchstens W.MAX, der Rest aufklappbar)
function W.BookLines(lines, withMap)
    local kind = "books"
    local list = Ask("Books")
    if type(list) ~= "table" or #list == 0 then return lines end
    lines[#lines + 1] = { kind = "header", left = L.WHERE_HEAD_books, where = kind }
    local open = W.expanded[kind] == true
    for i, b in ipairs(list) do
        if open or i <= W.MAX then lines[#lines + 1] = W.BookLine(kind, b, withMap) end
    end
    if #list > W.MAX then
        lines[#lines + 1] = { kind = "text", where = kind, action = open and "less" or "more", fold = open,
            left = open and L.WHERE_LESS or Core.More(#list - W.MAX), tip = open and L.WHERE_LESS_TIP or L.WHERE_MORE_TIP }
    end
    return lines
end

-- Alle Zeilen: je Art ein Abschnitt, danach Klassenquests und Bücher; liest Questie noch, oben ein Hinweis (die Ansicht
-- zeichnet neu, sobald ezCore das Ende meldet, unten).
function W.Lines()
    local lines, waiting = {}, false
    local read = W.Read()                         -- eine Frage an ezMap für alle Abschnitte
    for _, kind in ipairs(W.Kinds()) do
        local _, pending = W.SectionLines(kind, lines, read)
        if pending then waiting = true end
    end
    W.QuestLines(lines, read.withMap)
    W.BookLines(lines, read.withMap)
    if waiting then table.insert(lines, 1, { kind = "text", left = L.WHERE_PENDING }) end
    return lines
end

-- Klick auf einen Eintrag der Ansicht (Core.NewSpellbookView: onClick).
function W.Click(line)
    if type(line) ~= "table" then return false end
    if line.action == "trainerWay" or line.action == "way" then return W.GoNearest(line.way or "class") end
    if line.action == "npc" then return W.GoTo(line.npc) end
    if line.action == "place" then return W.GoTo(line.place) end      -- Fundort eines Buchs bzw. Geber einer Quest
    if line.action == "skill" then return W.GoSkill(line) end         -- Waffen- oder Rüstungsfertigkeit
    if line.action == "more" or line.action == "less" then           -- „… und n weitere“ auf- bzw. zuklappen
        W.expanded[line.where or ""] = line.action == "more" or nil
        W.Refresh()
        return true
    end
    return false
end

-- Quelle in der Fußzeile (Leitlinie 11)
function W.Footer()
    local text = W.MapAPI() and L.WHERE_SRC_MAP or L.WHERE_SRC_CORE
    local P = Core.Proficiency
    if type(P) == "table" and type(P.Learnable) == "function" then text = text .. " " .. L.WHERE_SRC_SKILLS end
    return text
end

---------------------------------------------------------------------------
-- Ansicht im Buch (ezCore)
---------------------------------------------------------------------------

function W.Refresh() if view then view:Refresh() end end
function W.IsOpen() return view ~= nil and view:IsShown() end
function W.UpdateTab() if view then view:UpdateTab() end end
function W.Toggle() if view then view:Toggle() end end

local function Setup()
    if view then return end
    view = Core.NewSpellbookView({
        key = "ezMerchant.where",
        owner = ADDON,
        frameName = "ezMerchantWhereView",
        icon = TAB_ICON,
        order = W.ORDER,
        title = L.WHERE_TITLE,
        tip = L.WHERE_TAB_TIP,
        lines = function() return W.Lines() end,
        footer = function() return W.Footer() end,
        onClick = function(line) W.Click(line) end,
        enabled = function() return ns.Enabled("where") end,
    })
end

local RefreshSoon = ns.Throttle(function() if W.IsOpen() then W.Refresh() end end, 0.2)
Core.Listen("NPCS_CHANGED", function() RefreshSoon() end, ADDON)
Core.Listen("QUESTIE_TOWNSFOLK", function() RefreshSoon() end, ADDON)
Core.Listen("SPELLSOURCES_CHANGED", function() RefreshSoon() end, ADDON)  -- Klassenquests, Bücher
Core.Listen("PROFICIENCY_CHANGED", function() RefreshSoon() end, ADDON)   -- Fertigkeit gelernt, Lehrer gesehen
ns.OnSettingChanged(function(key) if key == "where" then W.UpdateTab() end end)

ns.OnReady(Setup)
