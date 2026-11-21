local _, ns = ...

--[[
    Berechnete Rotationen (Welle 21, docs/talent-simulation.md, Abschnitt 6). Diese Datei schreibt das Werkzeug
    tools/rotation_sim.lua – nicht von Hand ändern:
        luajit tools/rotation_sim.lua [<Messungen …>] --wago --aus=ezCombat/RotationComputed.lua --talente-aus=ezTalent/Computed.lua

    Grundlage (Leitlinie 11): Zauber und Talente aus den Client-Tabellen (tools/daten/wago/, laut wago.tools) bzw. die
    Zauber-Messung je Klasse aus dem Client (ezCombat), die Grundwerte aus der Talent-Messung (ezTalent) und das
    Rechenmodell (tools/talent_sim.lua, Sim.Evaluate; Annahmen in computed.assumptions und docs/talent-simulation.md).
    Nichts aus fremden Addons, Simulatoren oder Ratgebern (Leitlinie 10). Die Quelle je Rotation steht in computed.values.
    Form einer Rotation wie in RotationData.lua (key, tree, name, pick, how, steps) mit computed = { date, build,
    model, distribution, provisional, assumptions, values, result }; gelesen von ns.RotationData.Computed.
]]

ns.ROTATION_COMPUTED_META = { date = "2026-11-20", build = "1.60.1.70938", model = "3/1", classes = 6 }
ns.ROTATION_COMPUTED = ns.ROTATION_COMPUTED or {}

ns.ROTATION_COMPUTED.DRUID = {
    {
        key = "sim-balance-pvp",
        tree = 1,
        name = { "Gleichgewicht – PvP (vorläufig berechnet)", "Balance – PvP (provisionally computed)" },
        pick = { known = { 1223083 }, leveling = false },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Gleichgewicht – PvP (berechnet)“: von oben nach unten das Erste, das geht – {8921}, {2912}. Im Modell 158 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Balance – PvP (computed)”: top to bottom, the first that is possible – {8921}, {2912}. In the model 158 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-balance-pvp", name = { "Gleichgewicht – PvP (berechnet)", "Balance – PvP (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Natur und Arkan, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Nature and Arcane, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 10 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 10 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 158 },
        },
        steps = {
            {
                id = 8921,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 19 % des Schadens.",
                    "Missing on the target: apply – 19 % of the damage in the model.",
                },
            },
            {
                id = 2912,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 81 % des Schadens.",
                    "Otherwise always this one – 81 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-resto-pvp",
        tree = 3,
        name = { "Wiederherstellung – PvP (vorläufig berechnet)", "Restoration – PvP (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Wiederherstellung – PvP (berechnet)“: von oben nach unten das Erste, das geht – {8936}. Im Modell 1008 Heilung je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Restoration – PvP (computed)”: top to bottom, the first that is possible – {8936}. In the model 1008 healing per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-resto-pvp",
                name = { "Wiederherstellung – PvP (berechnet)", "Restoration – PvP (computed)" },
            },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 10 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 10 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 1008 },
        },
        steps = {
            {
                id = 8936,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 100 % der Heilung.",
                    "On a wounded target, by hand – 100 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-balance",
        tree = 1,
        name = { "Gleichgewicht (vorläufig berechnet)", "Balance (provisionally computed)" },
        pick = { known = { 16918 }, leveling = false },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Gleichgewicht (berechnet)“: von oben nach unten das Erste, das geht – {8921}, {2912}. Im Modell 158 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Balance (computed)”: top to bottom, the first that is possible – {8921}, {2912}. In the model 158 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-balance", name = { "Gleichgewicht (berechnet)", "Balance (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Natur und Arkan, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Nature and Arcane, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 10 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 10 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 158 },
        },
        steps = {
            {
                id = 8921,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 19 % des Schadens.",
                    "Missing on the target: apply – 19 % of the damage in the model.",
                },
            },
            {
                id = 2912,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 81 % des Schadens.",
                    "Otherwise always this one – 81 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-resto",
        tree = 3,
        name = { "Wiederherstellung (vorläufig berechnet)", "Restoration (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Wiederherstellung (berechnet)“: von oben nach unten das Erste, das geht – {8936}. Im Modell 1008 Heilung je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Restoration (computed)”: top to bottom, the first that is possible – {8936}. In the model 1008 healing per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-resto", name = { "Wiederherstellung (berechnet)", "Restoration (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 10 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 10 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 1008 },
        },
        steps = {
            {
                id = 8936,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 100 % der Heilung.",
                    "On a wounded target, by hand – 100 % of the healing in the model.",
                },
            },
        },
    },
}

ns.ROTATION_COMPUTED.MAGE = {
    {
        key = "sim-arcane-leveling",
        tree = 1,
        name = { "Arkan – Leveln (vorläufig berechnet)", "Arcane – leveling (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Arkan – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {400574}. Im Modell 179 Schaden je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Arcane – leveling (computed)”: top to bottom, the first that is possible – {2136}, {400574}. In the model 179 damage per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-arcane-leveling", name = { "Arkan – Leveln (berechnet)", "Arcane – leveling (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Arkan, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Arcane, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 179 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 32 % des Schadens.",
                    "When ready – before every step below – 32 % of the damage in the model.",
                },
            },
            {
                id = 400574,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 68 % des Schadens.",
                    "Otherwise always this one – 68 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-arcane-pvp",
        tree = 1,
        name = { "Arkan – PvP (vorläufig berechnet)", "Arcane – PvP (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Arkan – PvP (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {400574}. Im Modell 174 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Arcane – PvP (computed)”: top to bottom, the first that is possible – {2136}, {400574}. In the model 174 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-arcane-pvp", name = { "Arkan – PvP (berechnet)", "Arcane – PvP (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Arkan, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Arcane, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 174 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 28 % des Schadens.",
                    "When ready – before every step below – 28 % of the damage in the model.",
                },
            },
            {
                id = 400574,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 72 % des Schadens.",
                    "Otherwise always this one – 72 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-arcane-survival",
        tree = 1,
        name = { "Arkan – Überleben (vorläufig berechnet)", "Arcane – survival (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Arkan – Überleben (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {400574}. Im Modell 174 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Arcane – survival (computed)”: top to bottom, the first that is possible – {2136}, {400574}. In the model 174 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-arcane-survival",
                name = { "Arkan – Überleben (berechnet)", "Arcane – survival (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Arkan, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Arcane, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 174 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 28 % des Schadens.",
                    "When ready – before every step below – 28 % of the damage in the model.",
                },
            },
            {
                id = 400574,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 72 % des Schadens.",
                    "Otherwise always this one – 72 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-fire-leveling",
        tree = 2,
        name = { "Feuer – Leveln (vorläufig berechnet)", "Fire – leveling (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Feuer – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {133}. Im Modell 180 Schaden je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Fire – leveling (computed)”: top to bottom, the first that is possible – {2136}, {133}. In the model 180 damage per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-fire-leveling", name = { "Feuer – Leveln (berechnet)", "Fire – leveling (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Feuer, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Fire, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 180 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 32 % des Schadens.",
                    "When ready – before every step below – 32 % of the damage in the model.",
                },
            },
            {
                id = 133,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 68 % des Schadens.",
                    "Otherwise always this one – 68 % of the damage in the model.",
                },
            },
            {
                id = 11113,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-fire-pvp",
        tree = 2,
        name = { "Feuer – PvP (vorläufig berechnet)", "Fire – PvP (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Feuer – PvP (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {133}. Im Modell 175 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Fire – PvP (computed)”: top to bottom, the first that is possible – {2136}, {133}. In the model 175 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-fire-pvp", name = { "Feuer – PvP (berechnet)", "Fire – PvP (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Feuer, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Fire, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 175 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 30 % des Schadens.",
                    "When ready – before every step below – 30 % of the damage in the model.",
                },
            },
            {
                id = 133,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 70 % des Schadens.",
                    "Otherwise always this one – 70 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 11113,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-fire-survival",
        tree = 2,
        name = { "Feuer – Überleben (vorläufig berechnet)", "Fire – survival (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Feuer – Überleben (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {133}. Im Modell 175 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Fire – survival (computed)”: top to bottom, the first that is possible – {2136}, {133}. In the model 175 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-fire-survival", name = { "Feuer – Überleben (berechnet)", "Fire – survival (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Feuer, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Fire, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 175 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 30 % des Schadens.",
                    "When ready – before every step below – 30 % of the damage in the model.",
                },
            },
            {
                id = 133,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 70 % des Schadens.",
                    "Otherwise always this one – 70 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 11113,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-frost-leveling",
        tree = 3,
        name = { "Frost – Leveln (vorläufig berechnet)", "Frost – leveling (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Frost – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {116}. Im Modell 180 Schaden je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Frost – leveling (computed)”: top to bottom, the first that is possible – {2136}, {116}. In the model 180 damage per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-frost-leveling", name = { "Frost – Leveln (berechnet)", "Frost – leveling (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Frost, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Frost, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 180 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 24 % des Schadens.",
                    "When ready – before every step below – 24 % of the damage in the model.",
                },
            },
            {
                id = 116,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 76 % des Schadens.",
                    "Otherwise always this one – 76 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-frost-pvp",
        tree = 3,
        name = { "Frost – PvP (vorläufig berechnet)", "Frost – PvP (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Frost – PvP (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {116}. Im Modell 173 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Frost – PvP (computed)”: top to bottom, the first that is possible – {2136}, {116}. In the model 173 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-frost-pvp", name = { "Frost – PvP (berechnet)", "Frost – PvP (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Frost, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Frost, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 173 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 25 % des Schadens.",
                    "When ready – before every step below – 25 % of the damage in the model.",
                },
            },
            {
                id = 116,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 75 % des Schadens.",
                    "Otherwise always this one – 75 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-frost-survival",
        tree = 3,
        name = { "Frost – Überleben (vorläufig berechnet)", "Frost – survival (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Frost – Überleben (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {116}. Im Modell 173 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Frost – survival (computed)”: top to bottom, the first that is possible – {2136}, {116}. In the model 173 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-frost-survival", name = { "Frost – Überleben (berechnet)", "Frost – survival (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Frost, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Frost, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 173 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 25 % des Schadens.",
                    "When ready – before every step below – 25 % of the damage in the model.",
                },
            },
            {
                id = 116,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 75 % des Schadens.",
                    "Otherwise always this one – 75 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-arcane",
        tree = 1,
        name = { "Arkan (vorläufig berechnet)", "Arcane (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Arkan (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {400574}. Im Modell 174 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Arcane (computed)”: top to bottom, the first that is possible – {2136}, {400574}. In the model 174 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-arcane", name = { "Arkan (berechnet)", "Arcane (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Arkan, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Arcane, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 174 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 28 % des Schadens.",
                    "When ready – before every step below – 28 % of the damage in the model.",
                },
            },
            {
                id = 400574,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 72 % des Schadens.",
                    "Otherwise always this one – 72 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-fire",
        tree = 2,
        name = { "Feuer (vorläufig berechnet)", "Fire (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Feuer (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {133}. Im Modell 175 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Fire (computed)”: top to bottom, the first that is possible – {2136}, {133}. In the model 175 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-fire", name = { "Feuer (berechnet)", "Fire (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Feuer, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Fire, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 175 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 30 % des Schadens.",
                    "When ready – before every step below – 30 % of the damage in the model.",
                },
            },
            {
                id = 133,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 70 % des Schadens.",
                    "Otherwise always this one – 70 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 11113,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-frost",
        tree = 3,
        name = { "Frost (vorläufig berechnet)", "Frost (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Frost (berechnet)“: von oben nach unten das Erste, das geht – {2136}, {116}. Im Modell 173 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Frost (computed)”: top to bottom, the first that is possible – {2136}, {116}. In the model 173 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-frost", name = { "Frost (berechnet)", "Frost (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Frost, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Frost, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 9 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 9 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 173 },
        },
        steps = {
            {
                id = 2136,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 25 % des Schadens.",
                    "When ready – before every step below – 25 % of the damage in the model.",
                },
            },
            {
                id = 116,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 75 % des Schadens.",
                    "Otherwise always this one – 75 % of the damage in the model.",
                },
            },
            {
                id = 120,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
            {
                id = 1449,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
}

ns.ROTATION_COMPUTED.PALADIN = {
    {
        key = "sim-holy-leveling",
        tree = 1,
        name = { "Heilig – Leveln (vorläufig berechnet)", "Holy – leveling (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Heilig – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {635}. Im Modell 632 Heilung je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Holy – leveling (computed)”: top to bottom, the first that is possible – {635}. In the model 632 healing per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-holy-leveling", name = { "Heilig – Leveln (berechnet)", "Holy – leveling (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 6 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 6 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 632 },
        },
        steps = {
            {
                id = 635,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 100 % der Heilung.",
                    "On a wounded target, by hand – 100 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-holy-pvp",
        tree = 1,
        name = { "Heilig – PvP (vorläufig berechnet)", "Holy – PvP (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Heilig – PvP (berechnet)“: von oben nach unten das Erste, das geht – {635}. Im Modell 632 Heilung je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Holy – PvP (computed)”: top to bottom, the first that is possible – {635}. In the model 632 healing per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-holy-pvp", name = { "Heilig – PvP (berechnet)", "Holy – PvP (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 6 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 6 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 632 },
        },
        steps = {
            {
                id = 635,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 100 % der Heilung.",
                    "On a wounded target, by hand – 100 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-holy",
        tree = 1,
        name = { "Heilig (vorläufig berechnet)", "Holy (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Heilig (berechnet)“: von oben nach unten das Erste, das geht – {635}. Im Modell 632 Heilung je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Holy (computed)”: top to bottom, the first that is possible – {635}. In the model 632 healing per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-holy", name = { "Heilig (berechnet)", "Holy (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 6 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 6 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 632 },
        },
        steps = {
            {
                id = 635,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 100 % der Heilung.",
                    "On a wounded target, by hand – 100 % of the healing in the model.",
                },
            },
        },
    },
}

ns.ROTATION_COMPUTED.PRIEST = {
    {
        key = "sim-disc-leveling",
        tree = 1,
        name = { "Disziplin – Leveln (vorläufig berechnet)", "Discipline – leveling (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Disziplin – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {1277370}, {2060}. Im Modell 700 Heilung je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Discipline – leveling (computed)”: top to bottom, the first that is possible – {1277370}, {2060}. In the model 700 healing per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-disc-leveling",
                name = { "Disziplin – Leveln (berechnet)", "Discipline – leveling (computed)" },
            },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 700 },
        },
        steps = {
            {
                id = 1277370,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 7 % der Heilung.",
                    "On a wounded target, by hand – 7 % of the healing in the model.",
                },
            },
            {
                id = 2060,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 93 % der Heilung.",
                    "On a wounded target, by hand – 93 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-disc-pvp",
        tree = 1,
        name = { "Disziplin – PvP (vorläufig berechnet)", "Discipline – PvP (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Disziplin – PvP (berechnet)“: von oben nach unten das Erste, das geht – {1277370}, {2060}. Im Modell 661 Heilung je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Discipline – PvP (computed)”: top to bottom, the first that is possible – {1277370}, {2060}. In the model 661 healing per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-disc-pvp", name = { "Disziplin – PvP (berechnet)", "Discipline – PvP (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 661 },
        },
        steps = {
            {
                id = 1277370,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 1 % der Heilung.",
                    "On a wounded target, by hand – 1 % of the healing in the model.",
                },
            },
            {
                id = 2060,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 99 % der Heilung.",
                    "On a wounded target, by hand – 99 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-holy-leveling",
        tree = 2,
        name = { "Heilig – Leveln (vorläufig berechnet)", "Holy – leveling (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Heilig – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {1277370}, {2060}. Im Modell 700 Heilung je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Holy – leveling (computed)”: top to bottom, the first that is possible – {1277370}, {2060}. In the model 700 healing per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-holy-leveling", name = { "Heilig – Leveln (berechnet)", "Holy – leveling (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 700 },
        },
        steps = {
            {
                id = 1277370,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 7 % der Heilung.",
                    "On a wounded target, by hand – 7 % of the healing in the model.",
                },
            },
            {
                id = 2060,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 93 % der Heilung.",
                    "On a wounded target, by hand – 93 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-holy-pvp",
        tree = 2,
        name = { "Heilig – PvP (vorläufig berechnet)", "Holy – PvP (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Heilig – PvP (berechnet)“: von oben nach unten das Erste, das geht – {1277370}, {2060}. Im Modell 661 Heilung je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Holy – PvP (computed)”: top to bottom, the first that is possible – {1277370}, {2060}. In the model 661 healing per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-holy-pvp", name = { "Heilig – PvP (berechnet)", "Holy – PvP (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 661 },
        },
        steps = {
            {
                id = 1277370,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 1 % der Heilung.",
                    "On a wounded target, by hand – 1 % of the healing in the model.",
                },
            },
            {
                id = 2060,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 99 % der Heilung.",
                    "On a wounded target, by hand – 99 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-shadow-leveling",
        tree = 3,
        name = { "Schatten – Leveln (vorläufig berechnet)", "Shadow – leveling (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Schatten – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {8092}, {10797}, {589}, {1277331}, {15407}. Im Modell 241 Schaden je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Shadow – leveling (computed)”: top to bottom, the first that is possible – {8092}, {10797}, {589}, {1277331}, {15407}. In the model 241 damage per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-shadow-leveling",
                name = { "Schatten – Leveln (berechnet)", "Shadow – leveling (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 241 },
        },
        steps = {
            {
                id = 8092,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 26 % des Schadens.",
                    "When ready – before every step below – 26 % of the damage in the model.",
                },
            },
            {
                id = 10797,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 24 % des Schadens.",
                    "When ready – before every step below – 24 % of the damage in the model.",
                },
            },
            {
                id = 589,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 20 % des Schadens.",
                    "Missing on the target: apply – 20 % of the damage in the model.",
                },
            },
            {
                id = 1277331,
                kind = "cooldown",
                when = "ready",
                text = {
                    "Sobald bereit – im Modell 4 % des Schadens.",
                    "As soon as it is ready – 4 % of the damage in the model.",
                },
            },
            {
                id = 15407,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 26 % des Schadens.",
                    "Otherwise always this one – 26 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-shadow-pvp",
        tree = 3,
        name = { "Schatten – PvP (vorläufig berechnet)", "Shadow – PvP (provisionally computed)" },
        pick = { known = { 15275, 1326159 }, leveling = false },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Schatten – PvP (berechnet)“: von oben nach unten das Erste, das geht – {589}, {8092}, {10797}, {1277331}, {15407}. Im Modell 217 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Shadow – PvP (computed)”: top to bottom, the first that is possible – {589}, {8092}, {10797}, {1277331}, {15407}. In the model 217 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-shadow-pvp", name = { "Schatten – PvP (berechnet)", "Shadow – PvP (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 217 },
        },
        steps = {
            {
                id = 589,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 19 % des Schadens.",
                    "Missing on the target: apply – 19 % of the damage in the model.",
                },
            },
            {
                id = 8092,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 22 % des Schadens.",
                    "When ready – before every step below – 22 % of the damage in the model.",
                },
            },
            {
                id = 10797,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 27 % des Schadens.",
                    "When ready – before every step below – 27 % of the damage in the model.",
                },
            },
            {
                id = 1277331,
                kind = "cooldown",
                when = "ready",
                text = {
                    "Sobald bereit – im Modell 1 % des Schadens.",
                    "As soon as it is ready – 1 % of the damage in the model.",
                },
            },
            {
                id = 15407,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 32 % des Schadens.",
                    "Otherwise always this one – 32 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-shadow-survival",
        tree = 3,
        name = { "Schatten – Überleben (vorläufig berechnet)", "Shadow – survival (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Schatten – Überleben (berechnet)“: von oben nach unten das Erste, das geht – {589}, {8092}, {10797}, {1277331}, {15407}. Im Modell 217 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Shadow – survival (computed)”: top to bottom, the first that is possible – {589}, {8092}, {10797}, {1277331}, {15407}. In the model 217 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-shadow-survival",
                name = { "Schatten – Überleben (berechnet)", "Shadow – survival (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 217 },
        },
        steps = {
            {
                id = 589,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 19 % des Schadens.",
                    "Missing on the target: apply – 19 % of the damage in the model.",
                },
            },
            {
                id = 8092,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 22 % des Schadens.",
                    "When ready – before every step below – 22 % of the damage in the model.",
                },
            },
            {
                id = 10797,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 27 % des Schadens.",
                    "When ready – before every step below – 27 % of the damage in the model.",
                },
            },
            {
                id = 1277331,
                kind = "cooldown",
                when = "ready",
                text = {
                    "Sobald bereit – im Modell 1 % des Schadens.",
                    "As soon as it is ready – 1 % of the damage in the model.",
                },
            },
            {
                id = 15407,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 32 % des Schadens.",
                    "Otherwise always this one – 32 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-disc",
        tree = 1,
        name = { "Disziplin (vorläufig berechnet)", "Discipline (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Disziplin (berechnet)“: von oben nach unten das Erste, das geht – {1277370}, {2060}. Im Modell 661 Heilung je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Discipline (computed)”: top to bottom, the first that is possible – {1277370}, {2060}. In the model 661 healing per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-disc", name = { "Disziplin (berechnet)", "Discipline (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 661 },
        },
        steps = {
            {
                id = 1277370,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 1 % der Heilung.",
                    "On a wounded target, by hand – 1 % of the healing in the model.",
                },
            },
            {
                id = 2060,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 99 % der Heilung.",
                    "On a wounded target, by hand – 99 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-holy",
        tree = 2,
        name = { "Heilig (vorläufig berechnet)", "Holy (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Heilig (berechnet)“: von oben nach unten das Erste, das geht – {1277370}, {2060}. Im Modell 661 Heilung je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Holy (computed)”: top to bottom, the first that is possible – {1277370}, {2060}. In the model 661 healing per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-holy", name = { "Heilig (berechnet)", "Holy (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 661 },
        },
        steps = {
            {
                id = 1277370,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 1 % der Heilung.",
                    "On a wounded target, by hand – 1 % of the healing in the model.",
                },
            },
            {
                id = 2060,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 99 % der Heilung.",
                    "On a wounded target, by hand – 99 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-shadow",
        tree = 3,
        name = { "Schatten (vorläufig berechnet)", "Shadow (provisionally computed)" },
        pick = { known = { 14524, 1225132 }, leveling = false },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Schatten (berechnet)“: von oben nach unten das Erste, das geht – {589}, {8092}, {10797}, {1277331}, {15407}. Im Modell 217 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Shadow (computed)”: top to bottom, the first that is possible – {589}, {8092}, {10797}, {1277331}, {15407}. In the model 217 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-shadow", name = { "Schatten (berechnet)", "Shadow (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 16 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 16 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 217 },
        },
        steps = {
            {
                id = 589,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 19 % des Schadens.",
                    "Missing on the target: apply – 19 % of the damage in the model.",
                },
            },
            {
                id = 8092,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 22 % des Schadens.",
                    "When ready – before every step below – 22 % of the damage in the model.",
                },
            },
            {
                id = 10797,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 27 % des Schadens.",
                    "When ready – before every step below – 27 % of the damage in the model.",
                },
            },
            {
                id = 1277331,
                kind = "cooldown",
                when = "ready",
                text = {
                    "Sobald bereit – im Modell 1 % des Schadens.",
                    "As soon as it is ready – 1 % of the damage in the model.",
                },
            },
            {
                id = 15407,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 32 % des Schadens.",
                    "Otherwise always this one – 32 % of the damage in the model.",
                },
            },
        },
    },
}

ns.ROTATION_COMPUTED.SHAMAN = {
    {
        key = "sim-ele-leveling",
        tree = 1,
        name = { "Elementar – Leveln (vorläufig berechnet)", "Elemental – leveling (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Elementar – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {8050}, {8042}, {403}. Im Modell 219 Schaden je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Elemental – leveling (computed)”: top to bottom, the first that is possible – {8050}, {8042}, {403}. In the model 219 damage per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-ele-leveling",
                name = { "Elementar – Leveln (berechnet)", "Elemental – leveling (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Natur, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Nature, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 219 },
        },
        steps = {
            {
                id = 8050,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 27 % des Schadens.",
                    "Missing on the target: apply – 27 % of the damage in the model.",
                },
            },
            {
                id = 8042,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 31 % des Schadens. Teilt die Abklingzeit mit {8050}.",
                    "When ready – before every step below – 31 % of the damage in the model. Shares its cooldown with {8050}.",
                },
            },
            {
                id = 403,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 42 % des Schadens.",
                    "Otherwise always this one – 42 % of the damage in the model.",
                },
            },
            {
                id = 421,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-ele-pvp",
        tree = 1,
        name = { "Elementar – PvP (vorläufig berechnet)", "Elemental – PvP (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Elementar – PvP (berechnet)“: von oben nach unten das Erste, das geht – {8050}, {8042}, {403}. Im Modell 212 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Elemental – PvP (computed)”: top to bottom, the first that is possible – {8050}, {8042}, {403}. In the model 212 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-ele-pvp", name = { "Elementar – PvP (berechnet)", "Elemental – PvP (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Natur, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Nature, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 212 },
        },
        steps = {
            {
                id = 8050,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 23 % des Schadens.",
                    "Missing on the target: apply – 23 % of the damage in the model.",
                },
            },
            {
                id = 8042,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 33 % des Schadens. Teilt die Abklingzeit mit {8050}.",
                    "When ready – before every step below – 33 % of the damage in the model. Shares its cooldown with {8050}.",
                },
            },
            {
                id = 403,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 44 % des Schadens.",
                    "Otherwise always this one – 44 % of the damage in the model.",
                },
            },
            {
                id = 421,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-ele-survival",
        tree = 1,
        name = { "Elementar – Überleben (vorläufig berechnet)", "Elemental – survival (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Elementar – Überleben (berechnet)“: von oben nach unten das Erste, das geht – {8050}, {8042}, {403}. Im Modell 212 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Elemental – survival (computed)”: top to bottom, the first that is possible – {8050}, {8042}, {403}. In the model 212 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-ele-survival",
                name = { "Elementar – Überleben (berechnet)", "Elemental – survival (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Natur, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Nature, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 212 },
        },
        steps = {
            {
                id = 8050,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 23 % des Schadens.",
                    "Missing on the target: apply – 23 % of the damage in the model.",
                },
            },
            {
                id = 8042,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 33 % des Schadens. Teilt die Abklingzeit mit {8050}.",
                    "When ready – before every step below – 33 % of the damage in the model. Shares its cooldown with {8050}.",
                },
            },
            {
                id = 403,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 44 % des Schadens.",
                    "Otherwise always this one – 44 % of the damage in the model.",
                },
            },
            {
                id = 421,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-resto-leveling",
        tree = 3,
        name = { "Wiederherstellung – Leveln (vorläufig berechnet)", "Restoration – leveling (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Wiederherstellung – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {8004}. Im Modell 547 Heilung je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Restoration – leveling (computed)”: top to bottom, the first that is possible – {8004}. In the model 547 healing per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-resto-leveling",
                name = { "Wiederherstellung – Leveln (berechnet)", "Restoration – leveling (computed)" },
            },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 547 },
        },
        steps = {
            {
                id = 8004,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 100 % der Heilung.",
                    "On a wounded target, by hand – 100 % of the healing in the model.",
                },
            },
        },
    },
    {
        key = "sim-ele",
        tree = 1,
        name = { "Elementar (vorläufig berechnet)", "Elemental (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Elementar (berechnet)“: von oben nach unten das Erste, das geht – {8050}, {8042}, {403}. Im Modell 212 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Elemental (computed)”: top to bottom, the first that is possible – {8050}, {8042}, {403}. In the model 212 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-ele", name = { "Elementar (berechnet)", "Elemental (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Natur, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; geteilte Abklingzeiten laut Client-Tabellen (Zauber-Kategorien): von zwei Zaubern einer Kategorie nur einer in der Rangfolge, außer einer wirkt über Zeit – dann rechnet das Modell beide getrennt (etwas zu hoch); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Nature, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; shared cooldowns according to the client tables (spell categories): of two spells in one category only one in the priority unless one works over time – then the model counts both separately (slightly too high); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 212 },
        },
        steps = {
            {
                id = 8050,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 23 % des Schadens.",
                    "Missing on the target: apply – 23 % of the damage in the model.",
                },
            },
            {
                id = 8042,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 33 % des Schadens. Teilt die Abklingzeit mit {8050}.",
                    "When ready – before every step below – 33 % of the damage in the model. Shares its cooldown with {8050}.",
                },
            },
            {
                id = 403,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 44 % des Schadens.",
                    "Otherwise always this one – 44 % of the damage in the model.",
                },
            },
            {
                id = 421,
                kind = "aoe",
                when = "ready",
                text = { "Bei mehreren Gegnern, sobald bereit.", "Against several enemies, as soon as it is ready." },
            },
        },
    },
    {
        key = "sim-resto",
        tree = 3,
        name = { "Wiederherstellung (vorläufig berechnet)", "Restoration (provisionally computed)" },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Wiederherstellung (berechnet)“: von oben nach unten das Erste, das geht – {8004}. Im Modell 547 Heilung je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Restoration (computed)”: top to bottom, the first that is possible – {8004}. In the model 547 healing per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-resto", name = { "Wiederherstellung (berechnet)", "Restoration (computed)" } },
            provisional = true,
            healer = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Heilung: Heilzauber nur von Hand (ezCombat schlägt im Kampf nur gegen Gegner vor und sieht HoTs nur auf dir); vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; Healing: heals by hand only (in combat ezCombat suggests only against enemies and sees HoTs only on you); provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { hps = 547 },
        },
        steps = {
            {
                id = 8004,
                kind = "situational",
                when = "manual",
                text = {
                    "Auf ein verletztes Ziel, von Hand – im Modell 100 % der Heilung.",
                    "On a wounded target, by hand – 100 % of the healing in the model.",
                },
            },
        },
    },
}

ns.ROTATION_COMPUTED.WARLOCK = {
    {
        key = "sim-aff-leveling",
        tree = 1,
        name = {
            "Gebrechen – Teufelsjäger – Leveln (vorläufig berechnet)",
            "Affliction – Felhunter – leveling (provisionally computed)",
        },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Gebrechen – Teufelsjäger – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {348}, {172}, {980}, {603}, {686}. Im Modell 198 Schaden je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Affliction – Felhunter – leveling (computed)”: top to bottom, the first that is possible – {348}, {172}, {980}, {603}, {686}. In the model 198 damage per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-aff-leveling",
                name = { "Gebrechen – Teufelsjäger – Leveln (berechnet)", "Affliction – Felhunter – leveling (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 198 },
        },
        steps = {
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 14 % des Schadens.",
                    "Missing on the target: apply – 14 % of the damage in the model.",
                },
            },
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 14 % des Schadens.",
                    "Missing on the target: apply – 14 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 18 % des Schadens.",
                    "Missing on the target: apply – 18 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 28 % des Schadens.",
                    "Missing on the target: apply – 28 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 26 % des Schadens.",
                    "Otherwise always this one – 26 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-aff-pvp",
        tree = 1,
        name = {
            "Gebrechen – Teufelsjäger – PvP (vorläufig berechnet)",
            "Affliction – Felhunter – PvP (provisionally computed)",
        },
        pick = { known = { 1225220 }, leveling = false },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Gebrechen – Teufelsjäger – PvP (berechnet)“: von oben nach unten das Erste, das geht – {172}, {980}, {348}, {603}, {686}. Im Modell 159 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Affliction – Felhunter – PvP (computed)”: top to bottom, the first that is possible – {172}, {980}, {348}, {603}, {686}. In the model 159 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-aff-pvp",
                name = { "Gebrechen – Teufelsjäger – PvP (berechnet)", "Affliction – Felhunter – PvP (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 159 },
        },
        steps = {
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 18 % des Schadens.",
                    "Missing on the target: apply – 18 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 37 % des Schadens.",
                    "Otherwise always this one – 37 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-aff-survival",
        tree = 1,
        name = {
            "Gebrechen – Teufelsjäger – Überleben (vorläufig berechnet)",
            "Affliction – Felhunter – survival (provisionally computed)",
        },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Gebrechen – Teufelsjäger – Überleben (berechnet)“: von oben nach unten das Erste, das geht – {172}, {980}, {348}, {603}, {686}. Im Modell 159 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Affliction – Felhunter – survival (computed)”: top to bottom, the first that is possible – {172}, {980}, {348}, {603}, {686}. In the model 159 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-aff-survival",
                name = {
                    "Gebrechen – Teufelsjäger – Überleben (berechnet)",
                    "Affliction – Felhunter – survival (computed)",
                },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 159 },
        },
        steps = {
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 18 % des Schadens.",
                    "Missing on the target: apply – 18 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 37 % des Schadens.",
                    "Otherwise always this one – 37 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-demo-leveling",
        tree = 2,
        name = {
            "Dämonologie – Sukkubus – Leveln (vorläufig berechnet)",
            "Demonology – Succubus – leveling (provisionally computed)",
        },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Dämonologie – Sukkubus – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {348}, {172}, {980}, {603}, {686}. Im Modell 198 Schaden je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Demonology – Succubus – leveling (computed)”: top to bottom, the first that is possible – {348}, {172}, {980}, {603}, {686}. In the model 198 damage per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-demo-leveling",
                name = { "Dämonologie – Sukkubus – Leveln (berechnet)", "Demonology – Succubus – leveling (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 198 },
        },
        steps = {
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 14 % des Schadens.",
                    "Missing on the target: apply – 14 % of the damage in the model.",
                },
            },
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 14 % des Schadens.",
                    "Missing on the target: apply – 14 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 18 % des Schadens.",
                    "Missing on the target: apply – 18 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 28 % des Schadens.",
                    "Missing on the target: apply – 28 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 26 % des Schadens.",
                    "Otherwise always this one – 26 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-demo-pvp",
        tree = 2,
        name = {
            "Dämonologie – Sukkubus – PvP (vorläufig berechnet)",
            "Demonology – Succubus – PvP (provisionally computed)",
        },
        pick = { known = { 17927 }, leveling = false },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Dämonologie – Sukkubus – PvP (berechnet)“: von oben nach unten das Erste, das geht – {172}, {980}, {348}, {603}, {686}. Im Modell 159 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Demonology – Succubus – PvP (computed)”: top to bottom, the first that is possible – {172}, {980}, {348}, {603}, {686}. In the model 159 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-demo-pvp",
                name = { "Dämonologie – Sukkubus – PvP (berechnet)", "Demonology – Succubus – PvP (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 159 },
        },
        steps = {
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 18 % des Schadens.",
                    "Missing on the target: apply – 18 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 37 % des Schadens.",
                    "Otherwise always this one – 37 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-demo-survival",
        tree = 2,
        name = {
            "Dämonologie – Sukkubus – Überleben (vorläufig berechnet)",
            "Demonology – Succubus – survival (provisionally computed)",
        },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Dämonologie – Sukkubus – Überleben (berechnet)“: von oben nach unten das Erste, das geht – {172}, {980}, {348}, {603}, {686}. Im Modell 159 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Demonology – Succubus – survival (computed)”: top to bottom, the first that is possible – {172}, {980}, {348}, {603}, {686}. In the model 159 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-demo-survival",
                name = { "Dämonologie – Sukkubus – Überleben (berechnet)", "Demonology – Succubus – survival (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 159 },
        },
        steps = {
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 18 % des Schadens.",
                    "Missing on the target: apply – 18 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 37 % des Schadens.",
                    "Otherwise always this one – 37 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-destro-leveling",
        tree = 3,
        name = {
            "Zerstörung – Wichtel als Opfer – Leveln (vorläufig berechnet)",
            "Destruction – Imp sacrificed – leveling (provisionally computed)",
        },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Zerstörung – Wichtel als Opfer – Leveln (berechnet)“: von oben nach unten das Erste, das geht – {348}, {172}, {980}, {17877}, {1293817}, {603}, {686}. Im Modell 217 Schaden je Sekunde über 30 Sek.",
            "Computed from the client tables for the talent build “Destruction – Imp sacrificed – leveling (computed)”: top to bottom, the first that is possible – {348}, {172}, {980}, {17877}, {1293817}, {603}, {686}. In the model 217 damage per second over 30 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-destro-leveling",
                name = {
                    "Zerstörung – Wichtel als Opfer – Leveln (berechnet)",
                    "Destruction – Imp sacrificed – leveling (computed)",
                },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 30 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Feuer und Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 30 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Fire and Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 217 },
        },
        steps = {
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 13 % des Schadens.",
                    "Missing on the target: apply – 13 % of the damage in the model.",
                },
            },
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 13 % des Schadens.",
                    "Missing on the target: apply – 13 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 17877,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 8 % des Schadens.",
                    "When ready – before every step below – 8 % of the damage in the model.",
                },
            },
            {
                id = 1293817,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 8 % des Schadens.",
                    "When ready – before every step below – 8 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 26 % des Schadens.",
                    "Missing on the target: apply – 26 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 16 % des Schadens.",
                    "Otherwise always this one – 16 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-destro-pvp",
        tree = 3,
        name = {
            "Zerstörung – Wichtel als Opfer – PvP (vorläufig berechnet)",
            "Destruction – Imp sacrificed – PvP (provisionally computed)",
        },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Zerstörung – Wichtel als Opfer – PvP (berechnet)“: von oben nach unten das Erste, das geht – {172}, {1293817}, {17877}, {980}, {348}, {603}, {686}. Im Modell 177 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Destruction – Imp sacrificed – PvP (computed)”: top to bottom, the first that is possible – {172}, {1293817}, {17877}, {980}, {348}, {603}, {686}. In the model 177 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-destro-pvp",
                name = {
                    "Zerstörung – Wichtel als Opfer – PvP (berechnet)",
                    "Destruction – Imp sacrificed – PvP (computed)",
                },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Feuer und Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Fire and Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 177 },
        },
        steps = {
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 13 % des Schadens.",
                    "Missing on the target: apply – 13 % of the damage in the model.",
                },
            },
            {
                id = 1293817,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 14 % des Schadens.",
                    "When ready – before every step below – 14 % of the damage in the model.",
                },
            },
            {
                id = 17877,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 9 % des Schadens.",
                    "When ready – before every step below – 9 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 12 % des Schadens.",
                    "Missing on the target: apply – 12 % of the damage in the model.",
                },
            },
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 13 % des Schadens.",
                    "Missing on the target: apply – 13 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 23 % des Schadens.",
                    "Otherwise always this one – 23 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-destro-survival",
        tree = 3,
        name = {
            "Zerstörung – Wichtel als Opfer – Überleben (vorläufig berechnet)",
            "Destruction – Imp sacrificed – survival (provisionally computed)",
        },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Zerstörung – Wichtel als Opfer – Überleben (berechnet)“: von oben nach unten das Erste, das geht – {172}, {1293817}, {17877}, {980}, {348}, {603}, {686}. Im Modell 177 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Destruction – Imp sacrificed – survival (computed)”: top to bottom, the first that is possible – {172}, {1293817}, {17877}, {980}, {348}, {603}, {686}. In the model 177 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-destro-survival",
                name = {
                    "Zerstörung – Wichtel als Opfer – Überleben (berechnet)",
                    "Destruction – Imp sacrificed – survival (computed)",
                },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Feuer und Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Fire and Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 177 },
        },
        steps = {
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 13 % des Schadens.",
                    "Missing on the target: apply – 13 % of the damage in the model.",
                },
            },
            {
                id = 1293817,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 14 % des Schadens.",
                    "When ready – before every step below – 14 % of the damage in the model.",
                },
            },
            {
                id = 17877,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 9 % des Schadens.",
                    "When ready – before every step below – 9 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 12 % des Schadens.",
                    "Missing on the target: apply – 12 % of the damage in the model.",
                },
            },
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 13 % des Schadens.",
                    "Missing on the target: apply – 13 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 23 % des Schadens.",
                    "Otherwise always this one – 23 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-aff",
        tree = 1,
        name = { "Gebrechen – Teufelsjäger (vorläufig berechnet)", "Affliction – Felhunter (provisionally computed)" },
        pick = { known = { 18731 }, leveling = false },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Gebrechen – Teufelsjäger (berechnet)“: von oben nach unten das Erste, das geht – {172}, {980}, {348}, {603}, {686}. Im Modell 159 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Affliction – Felhunter (computed)”: top to bottom, the first that is possible – {172}, {980}, {348}, {603}, {686}. In the model 159 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-aff",
                name = { "Gebrechen – Teufelsjäger (berechnet)", "Affliction – Felhunter (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 159 },
        },
        steps = {
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 18 % des Schadens.",
                    "Missing on the target: apply – 18 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 37 % des Schadens.",
                    "Otherwise always this one – 37 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-demo",
        tree = 2,
        name = { "Dämonologie – Sukkubus (vorläufig berechnet)", "Demonology – Succubus (provisionally computed)" },
        pick = { known = { 18731, 18754 }, leveling = false },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Dämonologie – Sukkubus (berechnet)“: von oben nach unten das Erste, das geht – {172}, {980}, {348}, {603}, {686}. Im Modell 159 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Demonology – Succubus (computed)”: top to bottom, the first that is possible – {172}, {980}, {348}, {603}, {686}. In the model 159 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = { key = "sim-demo", name = { "Dämonologie – Sukkubus (berechnet)", "Demonology – Succubus (computed)" } },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 159 },
        },
        steps = {
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 15 % des Schadens.",
                    "Missing on the target: apply – 15 % of the damage in the model.",
                },
            },
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 18 % des Schadens.",
                    "Missing on the target: apply – 18 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 37 % des Schadens.",
                    "Otherwise always this one – 37 % of the damage in the model.",
                },
            },
        },
    },
    {
        key = "sim-destro",
        tree = 3,
        name = {
            "Zerstörung – Wichtel als Opfer (vorläufig berechnet)",
            "Destruction – Imp sacrificed (provisionally computed)",
        },
        how = {
            "Berechnet aus den Client-Tabellen für die Talentverteilung „Zerstörung – Wichtel als Opfer (berechnet)“: von oben nach unten das Erste, das geht – {172}, {1293817}, {17877}, {980}, {348}, {603}, {686}. Im Modell 177 Schaden je Sekunde über 180 Sek.",
            "Computed from the client tables for the talent build “Destruction – Imp sacrificed (computed)”: top to bottom, the first that is possible – {172}, {1293817}, {17877}, {980}, {348}, {603}, {686}. In the model 177 damage per second over 180 sec.",
        },
        computed = {
            date = "2026-11-20",
            build = "1.60.1.70938",
            model = "3/1",
            distribution = {
                key = "sim-destro",
                name = { "Zerstörung – Wichtel als Opfer (berechnet)", "Destruction – Imp sacrificed (computed)" },
            },
            provisional = true,
            assumptions = {
                "Kampf gegen einen Gegner gleicher Stufe, 180 Sek.; Erwartungswerte ohne Würfel; globale Abklingzeit 1,5 Sek., 5 % Verfehlen, 4 % Widerstehen; Wirkung aus den Client-Tabellen (Schaden, Heilung, über Zeit); Stärkungen, Schwächungen und Combo-Punkte ohne Schadenszahl zählen nicht; Füller aus der Schule des Hauptbaums (Feuer und Schatten, erkannt an seinen Talenten); was überwiegend über Zeit wirkt, nur als „Fehlt auf dem Ziel: setzen“; vorläufig, Grundwerte geschätzt: Zauberwerte und Talente aus den Client-Tabellen (wago.tools), noch ohne Messung der Grundwerte (%s werte ohne Ausrüstung, jede Stufe zählt, zwei Stufen je Klasse ergeben die Kurve) – Zaubermacht 0, Krit 0 %, Mana ohne Grenze; Talentwirkungen nicht eingerechnet – die Verteilung bestimmt nur, welche Talent-Zauber es gibt; Koeffizienten und Streuung aus den Client-Tabellen",
                "Fight against one enemy of the same level, 180 sec.; Expected values without dice; global cooldown 1.5 sec., 5 % miss, 4 % resist; Effect from the client tables (damage, healing, over time); buffs, debuffs and combo points without a damage number count as zero; filler from the school of the main tree (Fire and Shadow, recognised by its talents); anything mostly over time only as “Missing on the target: apply”; provisional, base stats estimated: spell values and talents from the client tables (wago.tools), base stats not yet measured (%s values without gear, every level counts, two levels per class give the curve) – spell power 0, crit 0 %, unlimited mana; talent effects not included – the build only decides which talent spells exist; coefficients and variance from the client tables",
            },
            values = {
                "Client-Tabellen laut wago.tools (wowf 1.60.1.70938): Wirkungen, Koeffizienten, Kosten, Zauberzeit, Abklingzeit und Lernstufe je Rang bis Stufe 60, 8 Zauber mit Schaden oder Heilung; Talente aus den Client-Tabellen; Grundwerte geschätzt (keine Messung)",
                "Client tables according to wago.tools (wowf 1.60.1.70938): effects, coefficients, cost, cast time, cooldown and level per rank up to level 60, 8 spells with damage or healing; talents from the client tables; base stats estimated (no measurement)",
            },
            result = { dps = 177 },
        },
        steps = {
            {
                id = 172,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 13 % des Schadens.",
                    "Missing on the target: apply – 13 % of the damage in the model.",
                },
            },
            {
                id = 1293817,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 14 % des Schadens.",
                    "When ready – before every step below – 14 % of the damage in the model.",
                },
            },
            {
                id = 17877,
                kind = "priority",
                when = "ready",
                text = {
                    "Wenn bereit – vor allen Schritten darunter – im Modell 9 % des Schadens.",
                    "When ready – before every step below – 9 % of the damage in the model.",
                },
            },
            {
                id = 980,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 12 % des Schadens.",
                    "Missing on the target: apply – 12 % of the damage in the model.",
                },
            },
            {
                id = 348,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 13 % des Schadens.",
                    "Missing on the target: apply – 13 % of the damage in the model.",
                },
            },
            {
                id = 603,
                kind = "maintain",
                when = "dot",
                refresh = "missing",
                text = {
                    "Fehlt auf dem Ziel: setzen – im Modell 16 % des Schadens.",
                    "Missing on the target: apply – 16 % of the damage in the model.",
                },
            },
            {
                id = 686,
                kind = "filler",
                when = "filler",
                text = {
                    "Sonst immer dieser – im Modell 23 % des Schadens.",
                    "Otherwise always this one – 23 % of the damage in the model.",
                },
            },
        },
    },
}
