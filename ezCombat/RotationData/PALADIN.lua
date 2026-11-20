local _, ns = ...
local T = ns.RotationData.T

-- Paladin (PALADIN): Rotationen je Talentbaum und Spielweise für WoW Forever.
-- Format und Regeln: Kopf von RotationData.lua bzw. die Spezifikation (Arten, need, pick). Hier stehen nur
-- Zauber-ID und Logik; Name, Symbol, Ränge, gelernt, Lernstufe, Kosten, Zauberzeit, Abklingzeit und Dauer liefert
-- der Client zur Laufzeit. Zahlen sind ausschließlich Schwellen der Logik (Mana in Prozent, Stapel, Restzeit).
--
-- Quellen (abgerufen am 13.11.2026, Stand der Seiten: 4.11.2026) – nur Fakten (Rangfolge, Bedingungen), alle Texte
-- in eigenen Worten; nichts stammt aus einem Addon:
--   Vergeltung:  https://www.icy-veins.com/wow-forever/retribution-paladin-melee-dps-pve-rotation-cooldowns-abilities
--                https://www.icy-veins.com/wow-forever/retribution-paladin-leveling
--                https://www.wowhead.com/forever/guide/classes/paladin/retribution/rotation-cooldowns-pve-dps
--   Schutz:      https://www.icy-veins.com/wow-forever/protection-paladin-tank-pve-rotation-cooldowns-abilities
--                https://www.icy-veins.com/wow-forever/protection-paladin-leveling
--                https://www.wowhead.com/forever/guide/classes/paladin/protection/rotation-cooldowns-pve-tank
--   Heilig:      https://www.icy-veins.com/wow-forever/holy-paladin-healer-pve-rotation-cooldowns-abilities
--                https://www.icy-veins.com/wow-forever/holy-paladin-leveling
--                https://www.wowhead.com/forever/guide/classes/paladin/holy/healer-leveling-tips
-- Zauber-IDs (Rang 1) geprüft gegen nether.wowhead.com/forever und ezCore/SpellData.lua.
-- Widersprechen sich die Quellen, gilt Icy Veins als Hauptquelle (Entscheidung des Nutzers 13.11.2026, „Alle nach
-- Empfehlung“); die Abweichung von Wowhead nennt der Hinweis (note) der Rotation. Schutz: der Zauber gegen Untote
-- und Dämonen steht deshalb vor dem Schlag (Wowhead: danach).
--
-- [V] = Annahme, die erst das Spiel bestätigt (/ez test meldet unbekannte IDs):
--   21183        ist der Debuff, den das Richten mit dem Kreuzfahrer-Siegel aufs Ziel legt (jeder Rang heißt gleich)
--   1311703/04   sind die Echo-Auren auf dem Spieler und tragen die Stapel
--   20216        ist auch in Forever der gelernte Talent-Zauber
-- Annahme: an einer Schwelle heißt, dass keine Quelle eine Zahl nennt.
--
-- Was ezCombat nicht sehen kann und deshalb nicht rät: Waffentempo (welches Siegel das Hauptsiegel ist),
-- Gegnerzahl, Lebenszeit des Ziels (Ersatz: Elite und Boss), ob man Haupt- oder Zweittank ist, Heilbedarf,
-- Absprachen über Siegel, Segen und Auren. Darum gilt: Jedes aktive Siegel, jeder Segen und jede Aura zählt als
-- „liegt“; Vorschläge kommen nur, wenn gar nichts liegt.
--
-- Segen: ein Schritt je Rotation für die Wahlgruppe (buff = "blessing"); welcher Segen, entscheidet ezCore
--   (Spells.ChooseBuff: gemerkte Wahl aus ezBuff, sonst Könige, solange die fehlen Macht). Bis zum 15.11.2026 waren es
--   zwei Schritte (Könige mit need.known, Macht mit need.unknown) – beide zeigten im Reiter denselben gewählten Segen,
--   untereinander (Spieltest des Nutzers vom 15.11.2026: „beim paladin 2x hintereinander der selbe segen“).
-- Auren: ezCore.Spells.FAMILIES.aura kennt alle sieben Auren des Paladins (seit Welle 8 auch Feuer-, Frost- und
--   Schattenwiderstand und die Aura der Heiligkeit, CB-34); need.noaura nennt deshalb nur die Familie (ANY_AURA).
-- Bedarf: Zwei Aura-Bedingungen in einem Schritt (Siegel auf dem Spieler UND Debuff auf dem Ziel) gehen nur als
--   when = "proc" plus need.aura; ein zweites need.aura bzw. need.noaura gibt es nicht.

-- Einstufungen, die für „das Ziel lebt lange genug“ stehen (die Lebenszeit selbst ist nicht sichtbar).
local LONG_FIGHT = { rank = { "elite", "rareelite", "worldboss" } }
-- Kreaturentypen, gegen die die Zauber gegen Untote und Dämonen wirken.
local UNHOLY = { type = { "Undead", "Demon" } }
-- Der Kreuzfahrer-Debuff auf dem Ziel; der eines anderen Paladins zählt mit (er stapelt nicht).
local CRUSADED = { id = 21183, unit = "target", mine = false }    -- [V]
-- Irgendeine Aura des Paladins liegt (Familie aus ezCore, mit den Widerstands-Auren).
local ANY_AURA = { id = "aura" }
-- Irgendein Siegel ist aktiv (Familie aus ezCore).
local ANY_SEAL = { id = "seal" }

ns.RotationData.Add("PALADIN", {
    ---------------------------------------------------------------------------------------------------------------
    -- Heilig: Heilen ist keine Rotation – Vorbereitung und die Schadensfolge fürs Alleinspielen
    ---------------------------------------------------------------------------------------------------------------
    { key = "holy", tree = 1, name = T("Heilig", "Holy"),
      source = "https://www.icy-veins.com/wow-forever/holy-paladin-healer-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/holy-paladin-leveling",
          "https://www.wowhead.com/forever/guide/classes/paladin/holy/healer-leveling-tips" },
      how = T("Heilen ist keine feste Folge – dafür schlägt ezCombat nichts vor. Es hält fest, was immer liegen soll: Segen und Aura vor dem Kampf. Mit einem Gegner im Ziel zeigt es die Schadensfolge fürs Alleinspielen: ein Siegel halten, {20271} und {679} nach Abklingzeit, {26573} solange das Mana reicht, {879} gegen Untote und Dämonen. Die Heilzauber stehen als Liste unter Situativ.",
              "Healing is not a fixed sequence – ezCombat suggests nothing for it. It tracks what should always be up: blessing and aura before combat. With an enemy targeted it shows the solo damage priority: keep a seal up, {20271} and {679} on cooldown, {26573} while mana allows, {879} on Undead and Demons. Your healing spells are listed under Situational."),
      note = T("Ob jemand Heilung braucht, wer tankt und welches Siegel andere Paladine richten, sieht ezCombat nicht: Jedes Siegel, das du trägst, gilt. Nur Wowhead führt {1311606} als Schaden; Icy Veins stuft ihn als teuer ein – darum erst mit viel Mana.",
               "ezCombat can't see who needs healing, who tanks or which seals other paladins judge: any seal you wear counts. Only Wowhead lists {1311606} as damage; Icy Veins rates it expensive – hence only at high mana."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 20217, kind = "longbuff", buff = "blessing", when = "buff",
          text = T("{20217} oder deine gemerkte Wahl (solange {20217} fehlt: {19740}); jeder Segen gilt.", "{20217} or your remembered choice ({19740} until you learn it); any blessing counts.") },    -- Segen der Könige / Blessing of Kings
        { id = 7294, kind = "prepare", when = "buff", group = "aura", refresh = "missing",
          need = { leveling = true, noaura = ANY_AURA },
          text = T("Beim Leveln diese Aura; jede aktive Aura gilt.", "This aura while levelling; any active aura counts.") },    -- Aura der Vergeltung / Retribution Aura
        { id = 465, kind = "prepare", when = "buff", group = "aura", refresh = "missing",
          need = { leveling = false, noaura = ANY_AURA },
          text = T("Ohne Absprache diese Aura; jede aktive Aura gilt.", "Without a call this aura; any active aura counts.") },    -- Aura der Hingabe / Devotion Aura
        { id = 465, key = "prepare:465:early", kind = "prepare", when = "buff", group = "aura", refresh = "missing",
          need = { leveling = true, unknown = 7294, noaura = ANY_AURA },
          text = T("Solange {7294} fehlt: diese Aura.", "Until you learn {7294}: this aura.") },    -- Aura der Hingabe / Devotion Aura
        -- Im Kampf: Schaden ohne Heilbedarf (Reihenfolge = Rang) -------------------------------------------------
        { id = 20154, kind = "maintain", when = "buff", group = "seal",
          text = T("Für Schaden; trägst du bewusst ein anderes Siegel, gilt das.", "For damage; a different seal you wear on purpose counts.") },    -- Siegel der Rechtschaffenheit / Seal of Righteousness
        { id = 20271, kind = "priority", when = "ready", need = { aura = ANY_SEAL },
          text = T("Sobald bereit, solange ein Siegel aktiv ist.", "Whenever ready while a seal is active.") },    -- Richturteil / Judgement
        { id = 679, kind = "priority", when = "ready",
          text = T("Sobald bereit.", "Whenever it is ready.") },    -- Heiliger Stoß / Holy Strike
        { id = 26573, kind = "priority", when = "ready", need = { mana = { min = 50 } },    -- Annahme: „soweit bezahlbar“
          text = T("Aktiv halten, solange dein Mana für Heilung reicht.", "Keep it down while you have mana to spare for healing.") },    -- Weihe / Consecration
        { id = 879, kind = "priority", when = "ready", need = { enemy = UNHOLY },
          text = T("Nur gegen Untote und Dämonen, sobald bereit.", "Only on Undead or Demons, whenever ready.") },    -- Exorzismus / Exorcism
        { id = 1311606, kind = "priority", when = "ready", need = { mana = { min = 60 } },    -- Annahme: nur mit viel Mana
          text = T("Als Schaden teuer: nur mit viel Mana (Talent).", "Costly as damage: only at high mana (talent).") },    -- Heiliger Schock / Holy Shock
        -- Situativ: Heilen nach Lage (nie vorgeschlagen) ---------------------------------------------------------
        { id = 1328548, kind = "situational", when = "manual",
          text = T("In der Gruppe immer auf dem Tank halten (Talent).", "In a group keep it on the tank at all times (talent).") },    -- Eid des Lichts / Oath of Light
        { id = 19750, kind = "situational", when = "manual",
          text = T("Deine Standardheilung: am meisten Heilung je Mana.", "Your standard heal: most healing per mana.") },    -- Lichtblitz / Flash of Light
        { id = 635, kind = "situational", when = "manual",
          text = T("Bei schwerem Schaden und nach einem kritischen Heilzauber.", "On heavy damage and after a critical heal.") },    -- Heiliges Licht / Holy Light
        { id = 1310911, kind = "situational", when = "manual",
          text = T("Vor Gruppenschaden auf ein Ziel, danach {1311606} auf dasselbe.", "Before group damage on one target, then {1311606} on the same.") },    -- Lichtwacht / Light's Vigil
        { id = 20165, kind = "situational", when = "manual",
          text = T("Zum Heilen, wenn kein anderer Paladin es richtet.", "For healing when no other paladin judges it.") },    -- Siegel des Lichts / Seal of Light
        { id = 20166, kind = "situational", when = "manual",
          text = T("Zum Heilen, wenn {20165} schon vergeben ist.", "For healing when {20165} is already covered.") },    -- Siegel der Weisheit / Seal of Wisdom
        { id = 633, kind = "situational", when = "manual",
          text = T("Nur im Notfall: verbraucht dein ganzes Mana.", "Emergency only: it drains all your mana.") },    -- Handauflegung / Lay on Hands
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Schutz: wenige Knöpfe, das Mana entscheidet
    ---------------------------------------------------------------------------------------------------------------
    { key = "protection", tree = 2, name = T("Schutz", "Protection"),
      source = "https://www.icy-veins.com/wow-forever/protection-paladin-tank-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/protection-paladin-leveling",
          "https://www.wowhead.com/forever/guide/classes/paladin/protection/rotation-cooldowns-pve-tank" },
      how = T("Vor dem Kampf {25780}, Segen und Aura. Im Kampf zählen wenige Knöpfe und dein Mana: {1311649} halten, {26573} legen, solange das Mana reicht, dazu {20271}, {20925} und {679} nach Abklingzeit; {879} nur gegen Untote und Dämonen. {20271} mit {1311649} spottet – als Zweittank trägst du ein anderes Siegel, und jedes aktive Siegel gilt.",
              "Before combat: {25780}, blessing and aura. In combat few buttons and your mana matter: keep {1311649} up, drop {26573} while mana allows, plus {20271}, {20925} and {679} on cooldown; {879} only on Undead and Demons. {20271} with {1311649} taunts – as off-tank you wear another seal, and any active seal counts."),
      note = T("Ob du Haupt- oder Zweittank bist, wie viele Gegner da sind und ob du gerade Schläge kassierst, sieht ezCombat nicht: Zauber mit Zauberzeit und die Eröffnung mit einem zugeteilten Siegel stehen unter Situativ. Nur Wowhead führt {1311606}. Die Reihenfolge folgt Icy Veins: {879} kommt vor {679}; Wowhead nennt ihn danach.",
               "ezCombat can't see whether you main- or off-tank, how many enemies there are or whether you are being hit: spells with a cast time and the opener with an assigned seal are listed under Situational. Only Wowhead lists {1311606}. The order follows Icy Veins: {879} comes before {679}; Wowhead lists it after."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 25780, kind = "longbuff", when = "buff",
          text = T("Vor dem Kampf wirken und nie auslaufen lassen (Bedrohung).", "Cast before combat and never let it drop (threat).") },    -- Zorn der Gerechtigkeit / Righteous Fury
        { id = 20217, kind = "longbuff", buff = "blessing", when = "buff",
          text = T("{20217} oder deine gemerkte Wahl (solange {20217} fehlt: {19740}); jeder Segen gilt.", "{20217} or your remembered choice ({19740} until you learn it); any blessing counts.") },    -- Segen der Könige / Blessing of Kings
        { id = 7294, kind = "prepare", when = "buff", group = "aura", refresh = "missing",
          need = { leveling = true, noaura = ANY_AURA },
          text = T("Beim Leveln diese Aura; jede aktive Aura gilt.", "This aura while levelling; any active aura counts.") },    -- Aura der Vergeltung / Retribution Aura
        { id = 465, kind = "prepare", when = "buff", group = "aura", refresh = "missing",
          need = { leveling = false, noaura = ANY_AURA },
          text = T("Ohne Absprache diese Aura; jede aktive Aura gilt.", "Without a call this aura; any active aura counts.") },    -- Aura der Hingabe / Devotion Aura
        { id = 465, key = "prepare:465:early", kind = "prepare", when = "buff", group = "aura", refresh = "missing",
          need = { leveling = true, unknown = 7294, noaura = ANY_AURA },
          text = T("Solange {7294} fehlt: diese Aura.", "Until you learn {7294}: this aura.") },    -- Aura der Hingabe / Devotion Aura
        -- Im Kampf (Reihenfolge = Rang) ---------------------------------------------------------------------------
        { id = 1311649, kind = "maintain", when = "buff", group = "seal",
          text = T("Beim Tanken halten; als zweiter Tank gilt dein anderes Siegel.", "Keep up while tanking; as second tank your other seal counts.") },    -- Siegel des Furors / Seal of Fury
        { id = 20154, kind = "maintain", when = "buff", group = "seal", need = { unknown = 1311649 },
          text = T("Solange {1311649} fehlt: dieses Siegel.", "Until you learn {1311649}: this seal.") },    -- Siegel der Rechtschaffenheit / Seal of Righteousness
        { id = 26573, kind = "priority", when = "ready", need = { mana = { min = 30 } },    -- Annahme: „soweit das Mana reicht“
          text = T("Sobald bereit, solange das Mana reicht; in der Gruppe Pflicht.", "Whenever ready while mana allows; a must on packs.") },    -- Weihe / Consecration
        { id = 20271, kind = "priority", when = "ready", need = { aura = ANY_SEAL },
          text = T("Sobald bereit; mit {1311649} spottet es – nicht als zweiter Tank.", "Whenever ready; with {1311649} it taunts – not as second tank.") },    -- Richturteil / Judgement
        { id = 1311606, kind = "priority", when = "ready",
          text = T("Sobald bereit (nur mit dem Talent aus dem Heilig-Baum).", "Whenever ready (only with the Holy tree talent).") },    -- Heiliger Schock / Holy Shock
        { id = 20925, kind = "priority", when = "ready",
          text = T("Sobald bereit (Talent).", "Whenever ready (talent).") },    -- Heiliger Schild / Holy Shield
        -- Icy Veins führt den Zauber gegen Untote und Dämonen vor dem Schlag, Wowhead danach (Hauptquelle: Icy Veins).
        { id = 879, kind = "priority", when = "ready", need = { enemy = UNHOLY },
          text = T("Nur gegen Untote und Dämonen; dort vor {679}.", "Only on Undead or Demons; there before {679}.") },    -- Exorzismus / Exorcism
        { id = 679, kind = "priority", when = "ready",
          text = T("Sobald bereit; möglichst zweimal je {20925}.", "Whenever ready; ideally twice per {20925}.") },    -- Heiliger Stoß / Holy Strike
        -- Situativ (nie vorgeschlagen) ------------------------------------------------------------------------------
        { id = 21082, kind = "situational", when = "manual",
          text = T("Lange Kämpfe: zuerst dein zugeteiltes Siegel richten, dann {1311649}.", "Long fights: judge your assigned seal first, then {1311649}.") },    -- Siegel des Kreuzfahrers / Seal of the Crusader
        { id = 1310994, kind = "situational", when = "manual",
          text = T("Zweites {20271}: Bedrohung zu Beginn oder Ersatz-Spott.", "A second {20271}: opening threat or a backup taunt.") },    -- Schnelles Richturteil / Swift Judgement
        { id = 24275, kind = "situational", when = "manual",
          text = T("Ziel unter 20 %, nur wenn du gerade nicht getroffen wirst.", "Target below 20 %, only while you are not being hit.") },    -- Hammer des Zorns / Hammer of Wrath
        { id = 2812, kind = "situational", when = "manual",
          text = T("Untote und Dämonen, nur wenn du gerade nicht tankst.", "Undead and Demons, only while you are not tanking.") },    -- Heiliger Zorn / Holy Wrath
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Vergeltung: Siegelführung mit dem Befehls-Siegel (auch beim Leveln; „Nach Talentbaum“ ohne das Schock-Talent)
    ---------------------------------------------------------------------------------------------------------------
    { key = "retribution", tree = 3, name = T("Vergeltung", "Retribution"),
      source = "https://www.icy-veins.com/wow-forever/retribution-paladin-melee-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/retribution-paladin-leveling",
          "https://www.wowhead.com/forever/guide/classes/paladin/retribution/rotation-cooldowns-pve-dps" },
      pick = { unknown = 1311606 },
      how = T("Vor dem Kampf Segen und Aura. Gegen Elite und Bosse zuerst {21082} wirken und mit {20271} richten, dann sofort aufs Schadenssiegel wechseln – deine Treffer halten den Debuff. Sonst das Siegel halten und nach Abklingzeit spielen: {24275} unter 20 %, {26573} solange das Mana reicht, {20271}, {679}, {879} nur gegen Untote und Dämonen. Wird das Mana knapp, zuerst {26573} weglassen.",
              "Before combat: blessing and aura. On elites and bosses cast {21082} first and judge it with {20271}, then swap to your damage seal at once – your hits keep the debuff up. Otherwise keep the seal up and play by cooldown: {24275} below 20 %, {26573} while mana allows, {20271}, {679}, {879} only on Undead and Demons. When mana runs low, drop {26573} first."),
      note = T("Das Hauptsiegel hängt vom Waffentempo ab (langsam: {20375}, schnell: {20154}) – das sieht ezCombat nicht, jedes aktive Siegel gilt. Der Echo-Wechsel ist für langsame Waffen als abschaltbarer Schritt eingetragen; mit schneller Waffe läuft er umgekehrt. Wowhead führt {26573} gegen ein Ziel nur als Option, Icy Veins nach Abklingzeit.",
               "Your main seal depends on weapon speed (slow: {20375}, fast: {20154}) – ezCombat can't see it, any active seal counts. The echo swap is listed as a switchable step for slow weapons; with a fast weapon it runs the other way round. Wowhead lists {26573} on one target as optional, Icy Veins on cooldown."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 20217, kind = "longbuff", buff = "blessing", when = "buff",
          text = T("{20217} oder deine gemerkte Wahl (solange {20217} fehlt: {19740}); jeder Segen gilt.", "{20217} or your remembered choice ({19740} until you learn it); any blessing counts.") },    -- Segen der Könige / Blessing of Kings
        { id = 7294, kind = "prepare", when = "buff", group = "aura", refresh = "missing", need = { noaura = ANY_AURA },
          text = T("Ohne Absprache diese Aura; jede aktive Aura gilt.", "Without a call this aura; any active aura counts.") },    -- Aura der Vergeltung / Retribution Aura
        { id = 465, kind = "prepare", when = "buff", group = "aura", refresh = "missing",
          need = { unknown = 7294, noaura = ANY_AURA },
          text = T("Solange {7294} fehlt: diese Aura.", "Until you learn {7294}: this aura.") },    -- Aura der Hingabe / Devotion Aura
        -- Eröffnung: fester Block gegen langlebige Ziele ----------------------------------------------------------
        { id = 21082, kind = "opener", when = "buff", refresh = "missing", need = { enemy = LONG_FIGHT, noaura = CRUSADED },
          text = T("Elite und Boss ohne die Schwächung: zuerst dieses Siegel.", "Elite or boss without the weakening: this seal first.") },    -- Siegel des Kreuzfahrers / Seal of the Crusader
        { id = 20271, key = "opener:judge", kind = "opener", when = "ready", need = { aura = { id = 21082 }, noaura = CRUSADED },
          text = T("Mit {21082} richten: setzt die Schwächung für mehr Heiligschaden.", "Judge with {21082}: applies the weakening for more Holy damage.") },    -- Richturteil / Judgement
        -- Im Kampf (Reihenfolge = Rang) ---------------------------------------------------------------------------
        { id = 20375, key = "maintain:swap", kind = "maintain", when = "proc", aura = 21082, need = { aura = CRUSADED },
          text = T("Die Schwächung liegt: sofort zurück aufs Schadenssiegel.", "The weakening is up: back to your damage seal at once.") },    -- Siegel des Befehls / Seal of Command
        { id = 20154, key = "maintain:swap:early", kind = "maintain", when = "proc", aura = 21082,
          need = { unknown = 20375, aura = CRUSADED },
          text = T("Die Schwächung liegt: zurück aufs Schadenssiegel.", "The weakening is up: back to your damage seal.") },    -- Siegel der Rechtschaffenheit / Seal of Righteousness
        { id = 20166, kind = "resource", when = "buff", refresh = 5, optional = true,
          need = { enemy = LONG_FIGHT, mana = { max = 15 } },    -- Annahme: keine Quelle nennt eine Zahl
          text = T("Lange Kämpfe mit wenig Mana: vorübergehend dieses Siegel.", "Long fights at low mana: this seal for a while.") },    -- Siegel der Weisheit / Seal of Wisdom
        { id = 20154, key = "priority:echo", kind = "priority", when = "proc", aura = 1311703, stacks = 3, optional = true,
          need = { aura = { id = 20375 } },
          text = T("Langsame Waffe: bei 3 Echos für einen Treffer hierher wechseln.", "Slow weapon: at 3 echoes swap here for one hit.") },    -- Siegel der Rechtschaffenheit / Seal of Righteousness [V]
        { id = 20375, key = "priority:echo:back", kind = "priority", when = "proc", aura = 1311704, optional = true,
          need = { aura = { id = 20154 } },
          text = T("Nach dem Treffer mit dem Wechselsiegel wieder zurück.", "After the hit with the swap seal, swap back.") },    -- Siegel des Befehls / Seal of Command [V]
        { id = 20375, kind = "maintain", when = "buff", group = "seal",
          text = T("Halten und erst kurz vor Ablauf erneuern (Talent).", "Keep up and renew only shortly before it ends (talent).") },    -- Siegel des Befehls / Seal of Command
        { id = 20154, kind = "maintain", when = "buff", group = "seal", need = { unknown = 20375 },
          text = T("Solange {20375} fehlt: dein Schadenssiegel.", "Until you learn {20375}: your damage seal.") },    -- Siegel der Rechtschaffenheit / Seal of Righteousness
        { id = 24275, kind = "phase", when = "reactive",
          text = T("Ziel unter 20 %: sobald bereit, am besten gleich nach deinem Schlag.", "Target below 20 %: whenever ready, ideally right after your swing.") },    -- Hammer des Zorns / Hammer of Wrath
        { id = 26573, kind = "priority", when = "ready", need = { leveling = false, mana = { min = 40 } },    -- Annahme: „bei Manaknappheit zuerst weglassen“
          text = T("Sobald bereit; bei knappem Mana als Erstes weglassen.", "Whenever ready; the first thing to drop when mana is low.") },    -- Weihe / Consecration
        { id = 26573, key = "priority:26573:level", kind = "priority", when = "ready",
          need = { leveling = true, moving = false, mana = { min = 70 } },    -- Annahme: „nur mit viel Mana“
          text = T("Beim Leveln nur mit viel Mana und wenn du stehen bleibst.", "While levelling only at high mana and if you stand still.") },    -- Weihe / Consecration
        { id = 20271, kind = "priority", when = "ready", need = { aura = ANY_SEAL },
          text = T("Sobald bereit, solange ein Siegel aktiv ist.", "Whenever ready while a seal is active.") },    -- Richturteil / Judgement
        { id = 679, kind = "priority", when = "ready",
          text = T("Sobald bereit; frischt deine Urteile auf dem Ziel auf.", "Whenever ready; refreshes your judgements on the target.") },    -- Heiliger Stoß / Holy Strike
        { id = 879, kind = "priority", when = "ready", need = { enemy = UNHOLY },
          text = T("Nur gegen Untote und Dämonen; auch zum Anlocken aus der Ferne.", "Only on Undead or Demons; also to lure enemies from range.") },    -- Exorzismus / Exorcism
        -- Mehrere Gegner (nur im Flächenmodus) --------------------------------------------------------------------
        { id = 26573, key = "aoe:26573", kind = "aoe", when = "ready",
          text = T("Mehrere Gegner: sobald bereit, auch bei weniger Mana.", "Several enemies: whenever ready, even at lower mana.") },    -- Weihe / Consecration
        { id = 2812, kind = "aoe", when = "ready", need = { enemy = UNHOLY },
          text = T("Mehrere Untote oder Dämonen: sobald bereit.", "Several Undead or Demons: whenever ready.") },    -- Heiliger Zorn / Holy Wrath
        -- Situativ (nie vorgeschlagen) ------------------------------------------------------------------------------
        { id = 853, kind = "situational", when = "manual",
          text = T("Betäubung; mit {20375} trifft {20271} betäubte Ziele doppelt.", "Stun; with {20375}, {20271} hits stunned targets twice.") },    -- Hammer der Gerechtigkeit / Hammer of Justice
        { id = 20066, kind = "situational", when = "manual",
          text = T("Kontrolle; direkt danach {20271} mit {20375} (Talent).", "Control; follow up with {20271} under {20375} (talent).") },    -- Buße / Repentance
      } },

    ---------------------------------------------------------------------------------------------------------------
    -- Vergeltung mit dem Schock-Talent aus dem Heilig-Baum: ein Siegel, reine Liste nach Abklingzeit
    ---------------------------------------------------------------------------------------------------------------
    { key = "retribution_shock", tree = 3, name = T("Vergeltung (Shockadin)", "Retribution (Shockadin)"),
      source = "https://www.icy-veins.com/wow-forever/retribution-paladin-melee-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.wowhead.com/forever/guide/classes/paladin/retribution/rotation-cooldowns-pve-dps" },
      pick = { known = 1311606 },
      how = T("Wie Vergeltung, aber nur mit {20154}: gegen Elite und Bosse erst {21082} richten, dann zurückwechseln. Danach nach Abklingzeit: {24275} unter 20 %, {26573}, {20271}, {679}, {1311606}, {879} gegen Untote und Dämonen. {20216} vor dem Pull und danach, sobald bereit. Das Siegel erneuerst du erst kurz vor Ablauf, wenn sonst nichts bereit ist.",
              "Like Retribution, but with {20154} only: on elites and bosses judge {21082} first, then swap back. After that by cooldown: {24275} below 20 %, {26573}, {20271}, {679}, {1311606}, {879} on Undead and Demons. {20216} before the pull and whenever ready afterwards. Renew the seal only shortly before it ends, when nothing else is ready."),
      note = T("Gegnerzahl und Lebenszeit des Ziels sieht ezCombat nicht: die Eröffnung gilt nur für Elite und Bosse, Flächenzauber nur im Flächenmodus. Wowhead führt {26573} gegen ein Ziel nur als Option.",
               "ezCombat can't see enemy count or time to live: the opener applies to elites and bosses only, AoE spells only in AoE mode. Wowhead lists {26573} on one target as optional."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------------
        { id = 20217, kind = "longbuff", buff = "blessing", when = "buff",
          text = T("{20217} oder deine gemerkte Wahl (solange {20217} fehlt: {19740}); jeder Segen gilt.", "{20217} or your remembered choice ({19740} until you learn it); any blessing counts.") },    -- Segen der Könige / Blessing of Kings
        { id = 7294, kind = "prepare", when = "buff", group = "aura", refresh = "missing", need = { noaura = ANY_AURA },
          text = T("Ohne Absprache diese Aura; jede aktive Aura gilt.", "Without a call this aura; any active aura counts.") },    -- Aura der Vergeltung / Retribution Aura
        { id = 465, kind = "prepare", when = "buff", group = "aura", refresh = "missing",
          need = { unknown = 7294, noaura = ANY_AURA },
          text = T("Solange {7294} fehlt: diese Aura.", "Until you learn {7294}: this aura.") },    -- Aura der Hingabe / Devotion Aura
        -- Eröffnung: fester Block gegen langlebige Ziele ----------------------------------------------------------
        { id = 21082, kind = "opener", when = "buff", refresh = "missing", need = { enemy = LONG_FIGHT, noaura = CRUSADED },
          text = T("Elite und Boss ohne die Schwächung: zuerst dieses Siegel.", "Elite or boss without the weakening: this seal first.") },    -- Siegel des Kreuzfahrers / Seal of the Crusader
        { id = 20271, key = "opener:judge", kind = "opener", when = "ready", need = { aura = { id = 21082 }, noaura = CRUSADED },
          text = T("Mit {21082} richten: setzt die Schwächung für mehr Heiligschaden.", "Judge with {21082}: applies the weakening for more Holy damage.") },    -- Richturteil / Judgement
        -- Im Kampf (Reihenfolge = Rang) ---------------------------------------------------------------------------
        { id = 20154, key = "maintain:swap", kind = "maintain", when = "proc", aura = 21082, need = { aura = CRUSADED },
          text = T("Die Schwächung liegt: sofort zurück aufs Schadenssiegel.", "The weakening is up: back to your damage seal at once.") },    -- Siegel der Rechtschaffenheit / Seal of Righteousness
        { id = 20154, kind = "maintain", when = "buff", group = "seal", refresh = "missing",
          text = T("Kein Siegel aktiv: dieses, dein einziges Schadenssiegel.", "No seal active: this one, your only damage seal.") },    -- Siegel der Rechtschaffenheit / Seal of Righteousness
        -- Abklingzeit (Rang: vor der Liste nach Abklingzeit) -------------------------------------------------------
        { id = 20216, kind = "cooldown", when = "ready",
          text = T("Vor dem Angriff und sobald bereit; der nächste {1311606} trifft kritisch.", "Before you attack and whenever ready; your next {1311606} crits.") },    -- Göttliche Gunst / Divine Favor [V]
        { id = 24275, kind = "phase", when = "reactive",
          text = T("Ziel unter 20 %: sobald bereit, am besten gleich nach deinem Schlag.", "Target below 20 %: whenever ready, ideally right after your swing.") },    -- Hammer des Zorns / Hammer of Wrath
        { id = 26573, kind = "priority", when = "ready", need = { mana = { min = 40 } },    -- Annahme: „bei Manaknappheit zuerst weglassen“
          text = T("Sobald bereit; bei knappem Mana als Erstes weglassen.", "Whenever ready; the first thing to drop when mana is low.") },    -- Weihe / Consecration
        { id = 20271, kind = "priority", when = "ready", need = { aura = ANY_SEAL },
          text = T("Sobald bereit, solange ein Siegel aktiv ist.", "Whenever ready while a seal is active.") },    -- Richturteil / Judgement
        { id = 679, kind = "priority", when = "ready",
          text = T("Sobald bereit; frischt deine Urteile auf dem Ziel auf.", "Whenever ready; refreshes your judgements on the target.") },    -- Heiliger Stoß / Holy Strike
        { id = 1311606, kind = "priority", when = "ready",
          text = T("Sobald bereit (Talent aus dem Heilig-Baum).", "Whenever ready (Holy tree talent).") },    -- Heiliger Schock / Holy Shock
        { id = 879, kind = "priority", when = "ready", need = { enemy = UNHOLY },
          text = T("Nur gegen Untote und Dämonen; auch zum Anlocken aus der Ferne.", "Only on Undead or Demons; also to lure enemies from range.") },    -- Exorzismus / Exorcism
        { id = 20154, key = "maintain:20154:late", kind = "maintain", when = "buff", group = "seal", refresh = 10,
          text = T("Erst erneuern, wenn es bald ausläuft und nichts bereit ist.", "Renew only when it is about to end and nothing is ready.") },    -- Siegel der Rechtschaffenheit / Seal of Righteousness
        -- Mehrere Gegner (nur im Flächenmodus) --------------------------------------------------------------------
        { id = 26573, key = "aoe:26573", kind = "aoe", when = "ready",
          text = T("Mehrere Gegner: sobald bereit, auch bei weniger Mana.", "Several enemies: whenever ready, even at lower mana.") },    -- Weihe / Consecration
        { id = 2812, kind = "aoe", when = "ready", need = { enemy = UNHOLY },
          text = T("Mehrere Untote oder Dämonen: sobald bereit.", "Several Undead or Demons: whenever ready.") },    -- Heiliger Zorn / Holy Wrath
        -- Situativ (nie vorgeschlagen) ------------------------------------------------------------------------------
        { id = 853, kind = "situational", when = "manual",
          text = T("Betäubung für gefährliche Gegner oder zum Unterbrechen.", "A stun for dangerous enemies or to interrupt.") },    -- Hammer der Gerechtigkeit / Hammer of Justice
      } },
})
