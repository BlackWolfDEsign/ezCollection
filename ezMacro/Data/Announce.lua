local _, ns = ...

-- Ansagen für Anführer (Reiter „Chat“ (Ansagen)): fertige Sätze für Dungeon, Raid und PvP. Jede Ansage ist ein gewöhnliches
-- Makro – ändern, teilen, auf eine Leiste ziehen, Taste belegen. Wie der Kanal gewählt wird, steht in Announce.lua.
--   {c:warn}   wichtige Ansage: Raidwarnung als Leiter oder Assistent, sonst der Gruppenkanal
--   {c:group}  gewöhnlicher Gruppenkanal (Raid, Schlachtfeld bzw. Gruppe)
--   {p:5|Text} Pull-Ansage: Pull-Timer eines laufenden Addons („/pull 5“), sonst die Ansage als {c:warn}
--   %t         Name des Ziels, %z das Gebiet, in dem man steht – im Makrotext; Beschreibung und Nutzen zeigen dafür
--              „<Ziel>“ und „<Gebiet>“ (englisch „<target>“, „<zone>“), Texte aus Locale.lua
--   %r         Zielsymbol des Ziels (MACRO-26): beim Klick „{rt1}“ … „{rt8}“, ohne Symbol nichts; Beschreibung und
--              Nutzen zeigen „<Symbol>“ („<marker>“); im Makro mit festem Kanal fällt es weg
-- Eigene Texte, nichts aus anderen Addons übernommen. Namen höchstens 16 Zeichen; die Raid- und PvP-Fassungen
-- tragen den Vorsatz im Namen, damit sie neben den Dungeon-Ansagen in der Makroverwaltung stehen können.

local DESC = {
    warn = {
        "Schreibt „%s“ an alle – als Raidwarnung, wenn du im Raid Leiter oder Assistent bist, sonst in den Raid-, Schlachtfeld- oder Gruppenkanal. Der Kanal wählt sich selbst.",
        "Writes \"%s\" to everyone – as a raid warning if you lead or assist the raid, otherwise to raid, battleground or party chat. The channel picks itself.",
    },
    group = {
        "Schreibt „%s“ in den Kanal deiner Gruppe: Raid, Schlachtfeld bzw. Gruppe. Der Kanal wählt sich selbst.",
        "Writes \"%s\" to your group's channel: raid, battleground or party. The channel picks itself.",
    },
    pull = {
        "Kündigt den Pull an: „%s“. Läuft ein Addon mit Pull-Timer, startet das Makro stattdessen dessen Zähler (/pull).",
        "Announces the pull: \"%s\". If an addon with a pull timer is running, the macro starts its countdown (/pull) instead.",
    },
}
local WHY = { "Ein Klick sagt es allen: „%s“", "One click tells everyone: \"%s\"" }

-- Platzhalter lesbar zeigen (Spieltest 14.11.2026: in der Beschreibung stand „Unterbrechen: %t!“ roh): %t und %z
-- werden in Beschreibung und Nutzen zu „<Ziel>“ und „<Gebiet>“. index: 1 deutsch, 2 englisch.
local SHOWN = { ["%t"] = ns.TextPair("ANN_SHOW_TARGET"), ["%z"] = ns.TextPair("ANN_SHOW_ZONE"),
    ["%r"] = ns.TextPair("ANN_SHOW_MARK") }
local function Shown(text, index)
    return (text:gsub("%%[tzr]", function(mark) return SHOWN[mark][index] end))
end

-- opts.pull = Sekunden: Pull-Ansage
local function Say(id, kind, name, text, icon, opts)
    local pull = opts and opts.pull
    local line = ns.Text(text)
    local desc = DESC[pull and "pull" or kind]
    return {
        id = id, name = name, icon = icon, need = false,
        body = pull and ("{p:%d|%s}"):format(pull, line) or ("{c:%s} %s"):format(kind, line),
        say = { kind = kind, text = text },
        desc = { desc[1]:format(Shown(text[1], 1)), desc[2]:format(Shown(text[2], 2)) },
        why = { WHY[1]:format(Shown(text[1], 1)), WHY[2]:format(Shown(text[2], 2)) },
    }
end

ns.AddMacros("announce", "dungeon", {
    Say("ann_d_gather", "group", { "Sammeln", "Gather" },
        { "Sammeln bei mir!", "Gather on me!" }, "Ability_Warrior_BattleShout"),
    Say("ann_d_ready", "group", { "Bereit?", "Ready?" },
        { "Alle bereit? Mana und Buffs prüfen.", "Everyone ready? Check mana and buffs." }, "INV_Misc_PocketWatch_01"),
    Say("ann_d_pull", "warn", { "Pull in 5", "Pull in 5" },
        { "Pull in 5 Sekunden!", "Pulling in 5 seconds!" }, "Ability_Warrior_Charge", { pull = 5 }),
    Say("ann_d_kick", "group", { "Unterbrechen", "Interrupt" },
        { "Unterbrechen: %t!", "Interrupt %t!" }, "Ability_Kick"),
    Say("ann_d_dispel", "group", { "Bannen", "Dispel" },
        { "Bitte bannen!", "Dispel please!" }, "Spell_Holy_DispelMagic"),
    Say("ann_d_fire", "group", { "Raus da!", "Move out!" },
        { "Raus aus dem Feuer!", "Get out of the fire!" }, "Spell_Fire_Fire"),
    Say("ann_d_focus", "group", { "Fokus aufs Ziel", "Focus target" },
        { "Fokus auf %t!", "Focus %t!" }, "Ability_Hunter_SniperShot"),
    -- MACRO-26: mit Zielsymbol („CC auf {Mond} Gnoll“); ohne Symbol nur der Name
    Say("ann_d_cc", "group", { "CC aufs Ziel", "CC target" },
        { "CC auf %r %t – nicht angreifen!", "CC %r %t – do not attack!" }, "Spell_Nature_Polymorph"),
    Say("ann_d_wait", "group", { "Warten", "Wait" },
        { "Stopp – bitte warten!", "Stop – wait please!" }, "Spell_Nature_TimeStop"),
    Say("ann_d_wipe", "group", { "Neustart", "Reset" },
        { "Neustart – alle raus, wir sammeln neu.", "Reset – everyone out, we regroup." }, "Spell_Holy_Resurrection"),
    Say("ann_d_buffs", "group", { "Buffs bitte", "Buffs please" },
        { "Bitte buffen.", "Buffs please." }, "Spell_Holy_WordFortitude"),
    Say("ann_d_food", "group", { "Essen & Trinken", "Eat and drink" },
        { "Essen und trinken, gleich geht es weiter.", "Eat and drink, we go on in a moment." }, "INV_Misc_Food_15"),
})

ns.AddMacros("announce", "raid", {
    Say("ann_r_gather", "warn", { "Raid: Sammeln", "Raid: Gather" },
        { "Sammeln beim Leiter!", "Gather on the leader!" }, "Ability_Warrior_BattleShout"),
    Say("ann_r_pull", "warn", { "Raid: Pull in 10", "Raid: Pull in 10" },
        { "Pull in 10 Sekunden!", "Pulling in 10 seconds!" }, "Ability_Warrior_Charge", { pull = 10 }),
    Say("ann_r_spread", "warn", { "Raid: Verteilen", "Raid: Spread" },
        { "Verteilen!", "Spread out!" }, "Ability_Rogue_Sprint"),
    Say("ann_r_stack", "warn", { "Raid: Zusammen", "Raid: Stack" },
        { "Zusammenstehen!", "Stack up!" }, "Spell_Holy_PrayerOfHealing"),
    Say("ann_r_kick", "warn", { "Raid: Kick", "Raid: Kick" },
        { "Unterbrechen: %t!", "Interrupt %t!" }, "Ability_Kick"),
    Say("ann_r_dispel", "warn", { "Raid: Bannen", "Raid: Dispel" },
        { "Bannen!", "Dispel!" }, "Spell_Holy_DispelMagic"),
    Say("ann_r_fire", "warn", { "Raid: Raus da!", "Raid: Move out" },
        { "Raus aus dem Feuer!", "Get out of the fire!" }, "Spell_Fire_Fire"),
    Say("ann_r_stop", "warn", { "Raid: DPS-Stopp", "Raid: Stop DPS" },
        { "Schaden stoppen!", "Stop damage!" }, "Spell_Holy_SealOfProtection"),
    Say("ann_r_focus", "warn", { "Raid: Fokus", "Raid: Focus" },
        { "Fokus auf %t!", "Focus %t!" }, "Ability_Hunter_SniperShot"),
    Say("ann_r_mark", "warn", { "Raid: Symbol", "Raid: Marker" },
        { "Zuerst %r %t töten!", "Kill %r %t first!" }, "INV_Misc_Bone_HumanSkull_01"),
    Say("ann_r_wipe", "warn", { "Raid: Neustart", "Raid: Reset" },
        { "Neustart – alle raus, wir sammeln neu.", "Reset – everyone out, we regroup." }, "Spell_Holy_Resurrection"),
    Say("ann_r_buffs", "warn", { "Raid: Buffs", "Raid: Buffs" },
        { "Buffen und essen – der Pull folgt gleich.", "Buff up and eat – pull coming soon." }, "Spell_Holy_WordFortitude"),
})

ns.AddMacros("announce", "pvp", {
    Say("ann_p_attack", "group", { "PvP: Angriff", "PvP: Attack" },
        { "Angriff: %z!", "Attack: %z!" }, "Ability_Warrior_Charge"),
    Say("ann_p_defend", "group", { "PvP: Verteidigen", "PvP: Defend" },
        { "Verteidigen: %z!", "Defend: %z!" }, "Ability_Warrior_DefensiveStance"),
    Say("ann_p_help", "group", { "PvP: Hilfe", "PvP: Help" },
        { "Hilfe bei %z – Feinde kommen!", "Help at %z – enemies incoming!" }, "Ability_Warrior_Challange"),
    Say("ann_p_retreat", "group", { "PvP: Rückzug", "PvP: Fall back" },
        { "Rückzug von %z!", "Fall back from %z!" }, "Ability_Rogue_Sprint"),
    Say("ann_p_clear", "group", { "PvP: Frei", "PvP: Clear" },
        { "%z ist frei.", "%z is clear." }, "Spell_Holy_SealOfProtection"),
    Say("ann_p_gather", "group", { "PvP: Sammeln", "PvP: Gather" },
        { "Sammeln: %z!", "Gather at %z!" }, "Ability_Warrior_BattleShout"),
    Say("ann_p_focus", "group", { "PvP: Fokus", "PvP: Focus" },
        { "Fokus auf %t!", "Focus %t!" }, "Ability_Hunter_SniperShot"),
    Say("ann_p_healer", "group", { "PvP: Heiler", "PvP: Healer" },
        { "Heiler zuerst: %t!", "Healer first: %t!" }, "Spell_Holy_Heal"),
})
