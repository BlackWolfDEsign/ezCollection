local Core = ezCore

--[[
    Welche Klassenquest bringt welche Fähigkeit: Core.QuestSpells – Faktenliste (Nutzer am 24.11.2026, wörtlich: „zauberbuch
    --> keine Dämonenausbilder und Klassenquests aus Drittquellen(Questie, wago und co) verfügbar?“). Der Client nennt die
    Belohnung nur zu Quests, deren Daten er hat; Tabellen dazu führt er nicht (Quest-Belohnungen liegen beim Server), und
    QuestieDB kennt die Quests, aber nicht ihre Fähigkeit.

    Quellen (Leitlinien 10 bis 12; nur Fakten, in eigener Form):
      * Zuordnung Quest » Fähigkeit: Leitfäden zu WoW Forever – Conquest Capped, „WoW Forever Class Quests Guide“ (Stand
        29.10.2026, https://conquestcapped.com/guides/wow-forever/wow-forever-class-quests/) und games.gg, „How to get the
        Voidwalker in WoW Forever“ (16.11.2026); die Schritte der Reihen (chain) und die mit wiki = true gekennzeichneten
        Einträge laut Warcraft Wiki (warcraft.wiki.gg, „<Klasse> quests“; dort Classic-Stand). Gelesen am 24.11.2026.
      * Zauber: Client-Tabellen dieses Builds (1.60.1.71037) – jede Kennung ist laut Wissen/Client/ClassSpells.lua ein Zauber
        der Klasse (die Prüfung sieht nach). Ausnahmen tragen extra = true, weil der Client sie nicht als Klassenzauber mit
        Lernstufe führt: Reittiere (23161 in SkillLine 777 ohne Klassenmaske; 13819, 23214), Gifte (2842), Untote spüren
        (5502); ihr Volk kennt nur Questie. Die Lehrzauber des Clients (SpellEffect, gelesen am 24.11.2026) bestätigen die
        Gruppen: „Path of Defense“ (8121) lehrt 71, 355 und 7386, „Path of the Berserker“ (8616) 2458 und 20252, „Tame
        Beast“ (1579) 1515, 883 und 2641, „Beast Training“ (5300) 5149, 982 und 6991, „Bear Form“ (5488) 5487, 6807 und
        6795. Bei Widersprüchen zwischen den Leitfäden gilt der Client: Volk der Priester-Zauber laut RaceMask
        (SpellSources.lua fragt ClientData.RaceAllows), Stufe laut SpellLevels (Berserkerhaltung 30, nicht 40). Priester-
        Zauber: Rang 1 statt des im Leitfaden genannten höchsten Rangs. Prüfung: ezCore/Tests/klassenquests_test.lua.
      * Ob es die Quest für deine Klasse und dein Volk gibt, wo sie beginnt und ab welcher Stufe: QuestieDB zur Laufzeit
        (Core.Sources.Questie.ClassQuests). Abgeglichen wird der englische Grundname der Quest, bei mehreren gleichen Namen
        (Reihen „The Binding“) dazu die Stufe. Passt nichts, bleibt die Quest „Belohnung noch unbekannt“ – nie geraten.
    Der Client geht immer vor: Nennt er die Belohnung (Questlog, Questfenster), gilt seine Angabe (SpellSources.lua).

    Nicht aufgenommen, weil die Quelle keinen Questnamen nennt: Wichtel, Teufelsross, Katzengestalt; Schamane und Magier
    haben laut Conquest Capped keine Quest, die einen Zauber lehrt (Totems sind Gegenstände).

      QuestSpells.Find(klasse, name, stufe) → { spells = { zauber … }, lead, either, wiki, extra } | nil
            lead    Anfang oder Zwischenschritt einer Reihe, die zu diesen Fähigkeiten führt; auch dort, wo die Quelle nicht
                    sagt, welcher Schritt sie bringt (die vorsichtige Wahl: Jäger, Krieger „Vejrek“, Paladin „Valor“)
            either  nur eine davon (Sukkubus oder Inkubus): ist eine gelernt, gilt der Eintrag als erledigt
            extra   der Client führt den Zauber nicht als Klassenzauber (siehe oben)
      QuestSpells.Key(name)                 → Vergleichsform des Namens (Kleinbuchstaben ohne Satzzeichen)
]]

local QuestSpells = {}
Core.QuestSpells = QuestSpells

-- Eintrag: q = englische Namen, s = Zauber, level = nur diese Stufe (gleichnamige Quests), lead = führt dorthin
QuestSpells.LIST = {
    WARLOCK = {
        { q = { "The Binding" }, level = 10, s = { 697 } },
        { q = { "Gakin's Summons", "Surena Caledon", "The Slaughtered Lamb", "Gan'rul's Summons", "Creature of the Void",
            "Halgar's Summons" }, level = 10, s = { 697 }, lead = true },
        { q = { "The Binding" }, level = 20, s = { 712, 713 }, either = true },
        { q = { "Gakin's Summons" }, level = 20, s = { 712, 713 }, either = true, lead = true },
        { q = { "Devourer of Souls", "Heartswood" }, s = { 712 }, lead = true, wiki = true },
        { q = { "What Is Love?", "Hearts of the Lovers", "Love Hurts", "Wish You Were Here" }, s = { 713 }, lead = true },
        { q = { "The Binding" }, level = 30, s = { 691 }, wiki = true },
        { q = { "Seeking Strahad", "Tome of the Cabal" }, s = { 691 }, lead = true, wiki = true },
        { q = { "Kroshius' Infernal Core" }, s = { 1122 }, wiki = true },
        { q = { "What Niby Commands", "Flawless Fel Essence" }, s = { 1122 }, lead = true, wiki = true },
        { q = { "Suppression" }, s = { 18540 }, wiki = true },
        { q = { "The Prison's Bindings", "The Prison's Casing" }, s = { 18540 }, lead = true, wiki = true },
        { q = { "Dreadsteed of Xoroth" }, s = { 23161 }, wiki = true, extra = true },
    },
    WARRIOR = {
        { q = { "Bartleby's Mug", "Vorlus Vilehoof", "Path of Defense", "Ulag the Cleaver", "The Skybreaker Bulwark" },
            s = { 71, 355, 7386 } },
        { q = { "A Warrior's Training", "Bartleby the Drunk", "Beat Bartleby", "Elanaria", "Veteran Uzzek",
            "Speak with Dillinger" }, s = { 71, 355, 7386 }, lead = true },
        { q = { "Muren Stormpike", "Vejrek" }, s = { 71, 355, 7386 }, lead = true, wiki = true },
        { q = { "The Affray" }, s = { 2458, 20252 } },
        { q = { "The Islander" }, s = { 2458, 20252 }, lead = true },
    },
    PALADIN = {
        { q = { "A Lesson in Divinity" }, s = { 7328 } },
        { q = { "The Tome of Divinity" }, s = { 7328 }, lead = true },      -- mehrere Schritte gleichen Namens
        { q = { "The Tome of Valor" }, s = { 5502 }, lead = true, wiki = true, extra = true },
        { q = { "The Tome of Nobility" }, s = { 13819 }, extra = true },
        { q = { "Judgment and Redemption" }, s = { 23214 }, wiki = true, extra = true },
        { q = { "Summoning the Charger" }, s = { 23214 }, lead = true, extra = true },
    },
    HUNTER = {
        { q = { "Taming the Beast" }, s = { 1515 }, lead = true },
        { q = { "Training the Beast" }, s = { 5149 }, lead = true },
    },
    ROGUE = {
        { q = { "Klaven's Tower", "Hinott's Assistance" }, s = { 2842 }, extra = true },
        { q = { "Mathias and the Defias", "The Shattered Salute", "Deep Cover", "Mission: Possible But Not Probable" },
            s = { 2842 }, lead = true, extra = true },
    },
    PRIEST = {
        { q = { "Divine Grace" }, s = { 1277370 } },
        { q = { "Desperate Prayer" }, s = { 13908 } },
        { q = { "Stars of Elune" }, s = { 10797 } },
        { q = { "Hex of Weakness" }, s = { 9035 } },
        { q = { "Touch of Weakness" }, s = { 2652 } },
        { q = { "Confounding Flash" }, s = { 1277455 } },
        { q = { "Arcane Feedback" }, s = { 13896 } },
        { q = { "Chastise" }, s = { 1277331 } },
        { q = { "Elune's Grace" }, s = { 2651 } },
        { q = { "Shadowguard" }, s = { 18137 } },
        { q = { "Dark Sacrifice" }, s = { 1277324 } },
        { q = { "Contingency Plan" }, s = { 1277462 } },
    },
    DRUID = {
        { q = { "Body and Heart" }, s = { 5487 }, wiki = true },
        { q = { "Heeding the Call", "Moonglade", "Great Bear Spirit", "Back to Darnassus", "Back to Thunder Bluff" },
            s = { 5487 }, lead = true },
        { q = { "Aquatic Form" }, s = { 1066 } },
        { q = { "A Lesson to Learn", "Trial of the Lake", "Trial of the Sea Lion" }, s = { 1066 }, lead = true, wiki = true },
        { q = { "Power over Poison" }, s = { 8946 } },
        { q = { "Lessons Anew", "The Principal Source", "Gathering the Cure", "Curing the Sick" }, s = { 8946 }, lead = true,
            wiki = true },
    },
}

function QuestSpells.Key(name)
    if type(name) ~= "string" or Core.IsSecret(name) then return nil end
    local key = name:lower():gsub("%b()", ""):gsub("[^%w]", "")
    return key ~= "" and key or nil
end

local index

local function Index()
    if index then return index end
    index = {}
    for class, list in pairs(QuestSpells.LIST) do
        local by = {}
        for _, e in ipairs(list) do
            for _, name in ipairs(e.q) do
                local key = QuestSpells.Key(name)
                by[key] = by[key] or {}
                by[key][#by[key] + 1] = e
            end
        end
        index[class] = by
    end
    return index
end

function QuestSpells.Find(class, name, level)
    local by, key = Index()[class or ""], QuestSpells.Key(name)
    local hits = by and key and by[key]
    if not hits then return nil end
    for _, e in ipairs(hits) do
        if not e.level or (Core.Num(level) and math.abs(level - e.level) <= 2) then
            return { spells = e.s, lead = e.lead, either = e.either, wiki = e.wiki, extra = e.extra }
        end
    end
    return nil
end
