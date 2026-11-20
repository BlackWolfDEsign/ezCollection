local _, ns = ...
local T = ns.RotationData.T
-- Gesundheitssteine aus ezCore (Core.Spells.CONJURED, mit Herkunft und Prüfstand; Gesamtreview 18.11.2026, T16-9 –
-- vorher stand die Liste hier in jeder Rotation)
-- (die Werkzeuge unter tools/ laden die Datei ohne ezCore – dann bleibt die Liste leer; geprüft werden die IDs in ezCore)
local CONJURED = ezCore and ezCore.Spells and ezCore.Spells.CONJURED
local HEALTHSTONES = CONJURED and CONJURED.healthstone and CONJURED.healthstone.items or nil

-- Hexenmeister (WARLOCK): Rotationen für WoW Forever im Format der Arten (kind) – Vor dem Kampf, Eröffnung,
-- Im Kampf, Mehrere Gegner, Situativ. Felder und Regeln: Kopf von RotationData.lua.
--
-- Quellen: Icy Veins, WoW Forever (Stand der Seiten: 04.11.2026, abgerufen 13.11.2026). Übernommen sind nur
-- Fakten – Rangfolge, Bedingungen, Ersetzungen –, alle Texte sind eigene Worte. Nichts stammt aus einem Addon.
-- Zauber-IDs: Rang 1 aus dem früheren Bestand (gegen nether.wowhead.com/forever geprüft) und die Forever-eigenen IDs
-- aus den Zauber-Verweisen der Seiten oben. Weitere klassische Rang-1-IDs und der Seelensplitter (6265), aus dem
-- klassischen Spiel (die Gesundheitssteine liefert ezCore, Core.Spells.CONJURED): [B] laut Client-Tabellen (wago.tools, wowf 1.60.1.70938; Item, ItemSparse, SpellName) gibt es alle; jede Zauber- und
-- Gegenstands-ID hier gleicht die wago-Prüfung in sh tools/test.sh ab (Kennung, Klasse, Rang; tools/wago_pruefung.lua –
-- Gesamtreview 18.11.2026, T14-NH6). Feuersbrunst steht mit der Grund-ID 1293817 (Rang 1, Talent; vorher 17962,
-- Rang 3 ab Stufe 40 – der Schlüssel des Schritts bleibt für gemerkte Anpassungen).
--   Gebrechen:    https://www.icy-veins.com/wow-forever/affliction-warlock-ranged-dps-pve-rotation-cooldowns-abilities
--                 https://www.icy-veins.com/wow-forever/affliction-warlock-leveling
--                 https://www.icy-veins.com/wow-forever/affliction-warlock-ranged-dps-pve-guide
--   Dämonologie:  https://www.icy-veins.com/wow-forever/demonology-warlock-ranged-dps-pve-rotation-cooldowns-abilities
--                 https://www.icy-veins.com/wow-forever/demonology-warlock-leveling
--                 https://www.icy-veins.com/wow-forever/demonology-warlock-ranged-dps-pve-guide
--   Zerstörung:   https://www.icy-veins.com/wow-forever/destruction-warlock-ranged-dps-pve-rotation-cooldowns-abilities
--                 https://www.icy-veins.com/wow-forever/destruction-warlock-leveling
--                 https://www.icy-veins.com/wow-forever/destruction-warlock-ranged-dps-pve-guide
--
-- Der Client ist die Quelle für Name, Symbol, Ränge, gelernt, Lernstufe, Kosten, Zauberzeit, Abklingzeit und Dauer.
-- Hier stehen nur Zauber-ID (Rang 1) und Logik. Zahlen sind Schwellen der Logik; wo keine Quelle eine Zahl nennt,
-- steht „Annahme“. [V] am Namens-Kommentar: ID oder Annahme nicht im Spiel bestätigt (/ez test meldet unbekannte IDs).
--
-- Sechs Rotationen: je Baum eine für die Höchststufe bzw. den fertigen Aufbau (Schlüssel wie bisher) und eine fürs
-- Leveln. „Nach Talentbaum“ wählt über pick: Gebrechen und Dämonologie nach Stufe (unter der Höchststufe die
-- Level-Fassung), Zerstörung danach, ob der Füller des Baums (412758) gelernt ist – mit ihm gilt die Folge der
-- Höchststufe, davor verbraucht 1293817 (Feuersbrunst) noch den DoT, auf dem es aufbaut.
--
-- Was ezCombat nicht sehen kann und deshalb nie rät: Lebenszeit des Ziels (603 nur gegen Elite und Bosse, sonst
-- 980; „stirbt gleich“ nur als Text), Gegnerzahl (Fläche und Zweitziel nur als Liste), Leben des Spielers im Kampf
-- (1454 nur über Mana, der Rest als Text), Absprachen (Fluch, Seelenstein), welcher Dämon geopfert wurde.
--
-- Bedarf:
--   * Familie der Opfer-Auren (IDs im Spiel ermitteln): dann need.noaura an den Schritten „Dämon rufen“ und ein
--     prüfbarer Schritt für 18788 statt des Textes.
--   * Talentrang: Ob 426316 voll geskillt ist, ist nicht abfragbar – ersatzweise gilt „412758 gelernt“.
--   * Die zwei Boni aus 426316 (Schatten von 1293817, Feuer von 17877): Aura-IDs im Spiel ermitteln; heißen beide
--     gleich, findet der Schritt 17877 den falschen Bonus.

ns.RotationData.Add("WARLOCK", {
    -----------------------------------------------------------------------------------------------------------------
    -- Gebrechen (Höchststufe)
    -----------------------------------------------------------------------------------------------------------------
    { key = "affliction", tree = 1, name = T("Gebrechen", "Affliction"),
      source = "https://www.icy-veins.com/wow-forever/affliction-warlock-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/affliction-warlock-ranged-dps-pve-guide",
                  "https://www.icy-veins.com/wow-forever/affliction-warlock-leveling" },
      pick = { leveling = false },
      how = T("Vor dem Kampf stehen Rüstung, Dämon und Waffenstein. Im Kampf hältst du ein Omen und deine DoTs auf dem Ziel und erneuerst sie erst, wenn sie abgelaufen sind – {348} so, dass er beim Ablauf landet. {17941} macht den nächsten {686} sofort wirkbar: gleich nutzen. Dazwischen füllt {1316697}; der Kanal darf für einen fälligen DoT abbrechen. Mana holst du mit {1454}, am besten im Laufen.",
              "Before combat: armor, demon and weapon stone. In combat keep one bane and your DoTs on the target and renew them only once they have ended – cast {348} so it lands as the old one ends. {17941} makes your next {686} instant: use it at once. {1316697} fills the gaps; you may clip the channel for a DoT that is due. Get mana back with {1454}, ideally while moving."),
      note = T("Lebenszeit des Ziels und Gegnerzahl sieht ezCombat nicht: {603} nur gegen Elite und Bosse, Fläche und DoTs auf einem zweiten Ziel nur als Liste. Die Quelle nennt {1316697} und {686} beide als Füller, je nach Aufbau.",
               "ezCombat can't see time to live or enemy count: {603} on elites and bosses only, AoE and DoTs on a second target are list only. The source names both {1316697} and {686} as filler, depending on the build."),
      steps = {
        -- Vor dem Kampf (eigene Auswertung, im Kampf nie) ----------------------------------------------------------
        { id = 706, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf wirken; es zählt die beste gelernte Rüstung.", "Cast before combat; your best learned armor counts.") },    -- Dämonenrüstung / Demon Armor
        { id = 712, kind = "prepare", when = "pet", need = { unknown = 18788 },
          text = T("Kein Dämon da: den Schadens-Dämon rufen.", "No demon out: summon your damage demon.") },    -- Sukkubus beschwören / Summon Succubus [V]
        { id = 2362, kind = "prepare", when = "enchant", hand = "main",
          text = T("Stein auf die Waffe, sobald sie keinen trägt.", "Put a stone on your weapon when it has none.") },    -- Zauberstein herstellen / Create Spellstone
        { id = 6366, kind = "prepare", when = "enchant", hand = "main", need = { unknown = 2362 },
          text = T("Solange {2362} fehlt: dieser Stein auf die Waffe.", "Until you learn {2362}: this stone on your weapon.") },    -- Feuerstein herstellen / Create Firestone [V]
        { id = 6201, kind = "prepare", when = "item", optional = true,
          item = HEALTHSTONES,
          text = T("Einen Stein für den Notfall herstellen.", "Create a stone for emergencies.") },    -- Gesundheitsstein herstellen / Create Healthstone
        { id = 693, kind = "prepare", when = "manual",
          text = T("In der Gruppe: auf den abgesprochenen Spieler legen.", "In a group: put it on the agreed player.") },    -- Seelenstein herstellen / Create Soulstone [V]
        -- Eröffnung -------------------------------------------------------------------------------------------------
        { id = 348, key = "opener:348", kind = "opener", when = "dot", refresh = "missing", need = { combat = false },
          text = T("Aus der Ferne vorzaubern, danach die sofortigen Dauerschaden-Zauber.", "Pre-cast from range, then your instant damage-over-time spells.") },    -- Feuerbrand / Immolate
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 603, kind = "maintain", when = "dot", group = "bane", refresh = "missing",
          need = { enemy = { rank = { "elite", "rareelite", "worldboss" } } },
          text = T("Nur in langen Kämpfen (Elite, Boss); nie überschreiben.", "Long fights only (elite, boss); never overwrite it.") },    -- Omen der Verdammnis / Bane of Doom [V]
        { id = 18288, kind = "priority", when = "ready", need = { noaura = { id = "bane", unit = "target" } },
          text = T("Direkt vor einem neuen {980}; nie vor {603}.", "Right before a new {980}; never before {603}.") },    -- Fluch verstärken / Amplify Curse
        { id = 980, kind = "maintain", when = "dot", group = "bane", refresh = "missing",
          text = T("Kein Omen auf dem Ziel: setzen. Erst nach Ablauf erneuern.", "No bane on the target: apply. Renew only after it ends.") },    -- Omen der Pein / Bane of Agony
        { id = 440892, kind = "maintain", when = "dot", group = "curse", refresh = "missing", optional = true,
          text = T("Dein zugeteilter Fluch (ohne Absprache: dieser).", "Your assigned curse (without a call: this one).") },    -- Fluch der Elemente / Curse of the Elements [V]
        { id = 172, kind = "maintain", when = "dot", refresh = "cast",
          text = T("Fehlt: setzen. Nicht vorzeitig erneuern.", "Missing: apply. Don't renew early.") },    -- Verderbnis / Corruption
        { id = 18265, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Fehlt: setzen. Erst nach Ablauf erneuern.", "Missing: apply. Renew only after it ends.") },    -- Lebensentzug / Siphon Life
        { id = 348, kind = "maintain", when = "dot", refresh = "cast",
          text = T("So wirken, dass er beim Ablauf des alten landet.", "Cast so it lands as the old one ends.") },    -- Feuerbrand / Immolate
        { id = 686, key = "proc:686", kind = "priority", when = "proc", aura = 17941,
          text = T("Bei {17941}: sofort.", "On {17941}: at once.") },    -- Schattenblitz / Shadow Bolt
        { id = 1454, key = "tap:move", kind = "resource", when = "lowmana", max = 60, need = { moving = true },    -- Annahme: die Quelle bevorzugt das Laufen, nennt aber keine Zahl
          text = T("Im Laufen schon früher auffüllen; achte auf dein Leben.", "While moving, top up earlier; mind your health.") },    -- Aderlass / Life Tap
        { id = 1454, kind = "resource", when = "lowmana", max = 30,    -- Annahme: keine Quelle nennt eine Zahl
          text = T("Bei wenig Mana, bevor es ganz leer ist; achte auf dein Leben.", "On low mana, before it runs dry; mind your health.") },    -- Aderlass / Life Tap
        { id = 1316697, kind = "filler", when = "filler",
          text = T("Lückenfüller, solange aller Dauerschaden läuft; Abbrechen ist erlaubt.", "Gap filler while all damage over time runs; you may cut it short.") },    -- Zermürben / Wrack
        { id = 686, kind = "filler", when = "filler", need = { unknown = 1316697 },
          text = T("Lückenfüller, solange {1316697} fehlt.", "Gap filler until you learn {1316697}.") },    -- Schattenblitz / Shadow Bolt
        -- Mehrere Gegner (nur Liste) ----------------------------------------------------------------------------------
        { id = 1949, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern um dich; achte auf dein Leben.", "Three or more enemies around you; mind your health.") },    -- Höllenfeuer / Hellfire [V]
        { id = 5740, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, wenn der Nahkampf zu gefährlich ist.", "Three or more enemies when melee range is unsafe.") },    -- Feuerregen / Rain of Fire [V]
        -- Situativ ----------------------------------------------------------------------------------------------------
        { id = 689, kind = "situational", when = "manual",
          text = T("Statt des Lückenfüllers, wenn du Heilung brauchst.", "Instead of your gap filler when you need healing.") },    -- Blutsauger / Drain Life [V]
        { id = 1120, kind = "situational", when = "manual",
          text = T("Nur, um Seelensplitter aufzufüllen.", "Only to refill Soul Shards.") },    -- Seelendieb / Drain Soul [V]
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Dämonologie (Höchststufe)
    -----------------------------------------------------------------------------------------------------------------
    { key = "demonology", tree = 2, name = T("Dämonologie", "Demonology"),
      source = "https://www.icy-veins.com/wow-forever/demonology-warlock-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/demonology-warlock-ranged-dps-pve-guide",
                  "https://www.icy-veins.com/wow-forever/demonology-warlock-leveling" },
      pick = { leveling = false },
      how = T("Dein Dämon macht einen großen Teil des Schadens. {5676} legt {1293695} auf das Ziel, das der Dämon angreift; erneuert wird erst, wenn es weg ist. Dazu kommen ein Omen, {348} und {172}, beide so gewirkt, dass sie beim Ablauf landen. {686} füllt, {1454} versorgt dich und mit dem passenden Talent auch den Dämon. Vor dem Kampf: Opfer-Bonus holen, Schadens-Dämon rufen, {19028} aktivieren.",
              "Your demon deals a large share of the damage. {5676} puts {1293695} on the target your demon attacks; renew it only once it is gone. Add a bane, {348} and {172}, both cast so they land as the old one ends. {686} is the filler, {1454} feeds you and, with the right talent, your demon too. Before combat: get the sacrifice bonus, summon your damage demon, switch on {19028}."),
      note = T("Ob {1293695} gelernt ist, fragt ezCombat beim Spiel ab; ohne das Talent wird {5676} nie vorgeschlagen. Hat dein Dämon kein Ziel, wartet {5676}. Die Opfer-Folge steht nur als Text, weil ezCombat den Bonus nicht zuordnen kann. Fläche nur als Liste.",
               "ezCombat asks the game whether {1293695} is learned; without the talent {5676} is never suggested. If your demon has no target, {5676} waits. The sacrifice sequence is text only because ezCombat can't identify the bonus. AoE is list only."),
      steps = {
        -- Vor dem Kampf -------------------------------------------------------------------------------------------
        { id = 706, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf wirken; es zählt die beste gelernte Rüstung.", "Cast before combat; your best learned armor counts.") },    -- Dämonenrüstung / Demon Armor
        { id = 18788, kind = "prepare", when = "manual",
          text = T("Mit {425464}: {688}, opfern, dann den Schadens-Dämon.", "With {425464}: {688}, sacrifice, then your damage demon.") },    -- Dämonische Opferung / Demonic Sacrifice
        { id = 712, kind = "prepare", when = "pet",
          text = T("Kein Dämon da: den Schadens-Dämon rufen.", "No demon out: summon your damage demon.") },    -- Sukkubus beschwören / Summon Succubus [V]
        { id = 19028, kind = "longbuff", when = "buff", need = { pet = true },
          text = T("Mit Dämon immer aktiv; nach jedem Dämonenwechsel neu.", "Always on with a demon; recast after every demon swap.") },    -- Seelenverbindung / Soul Link
        { id = 2362, kind = "prepare", when = "enchant", hand = "main",
          text = T("Stein auf die Waffe, sobald sie keinen trägt.", "Put a stone on your weapon when it has none.") },    -- Zauberstein herstellen / Create Spellstone
        { id = 6366, kind = "prepare", when = "enchant", hand = "main", need = { unknown = 2362 },
          text = T("Solange {2362} fehlt: dieser Stein auf die Waffe.", "Until you learn {2362}: this stone on your weapon.") },    -- Feuerstein herstellen / Create Firestone [V]
        { id = 6201, kind = "prepare", when = "item", optional = true,
          item = HEALTHSTONES,
          text = T("Einen Stein für den Notfall herstellen.", "Create a stone for emergencies.") },    -- Gesundheitsstein herstellen / Create Healthstone
        { id = 693, kind = "prepare", when = "manual",
          text = T("In der Gruppe: auf den abgesprochenen Spieler legen.", "In a group: put it on the agreed player.") },    -- Seelenstein herstellen / Create Soulstone [V]
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 603, kind = "maintain", when = "dot", group = "bane", refresh = "missing",
          need = { enemy = { rank = { "elite", "rareelite", "worldboss" } } },
          text = T("Nur in langen Kämpfen (Elite, Boss); nie überschreiben.", "Long fights only (elite, boss); never overwrite it.") },    -- Omen der Verdammnis / Bane of Doom [V]
        { id = 18288, kind = "priority", when = "ready", need = { noaura = { id = "bane", unit = "target" } },
          text = T("Direkt vor einem neuen {980}; nie vor {603}.", "Right before a new {980}; never before {603}.") },    -- Fluch verstärken / Amplify Curse
        { id = 980, kind = "maintain", when = "dot", group = "bane", refresh = "missing",
          text = T("Kein Omen auf dem Ziel: setzen. Erst nach Ablauf erneuern.", "No bane on the target: apply. Renew only after it ends.") },    -- Omen der Pein / Bane of Agony
        { id = 440892, kind = "maintain", when = "dot", group = "curse", refresh = "missing", optional = true,
          text = T("Dein zugeteilter Fluch (ohne Absprache: dieser).", "Your assigned curse (without a call: this one).") },    -- Fluch der Elemente / Curse of the Elements [V]
        -- ohne Ziel des Dämons nicht fällig (der Motor prüft „pettarget“)
        { id = 5676, kind = "maintain", when = "dot", aura = 1293695, unit = "pettarget", refresh = "missing",
          need = { known = 1293695, pet = true },
          text = T("Fehlt {1293695} am Ziel deines Dämons: wirken. Ohne Ziel des Dämons nicht.",
                   "{1293695} missing on your demon's target: cast. Not while your demon has no target.") },    -- Sengender Schmerz / Searing Pain [V Talent abfragbar]
        { id = 348, kind = "maintain", when = "dot", refresh = "cast",
          text = T("So wirken, dass er beim Ablauf des alten landet.", "Cast so it lands as the old one ends.") },    -- Feuerbrand / Immolate
        { id = 172, kind = "maintain", when = "dot", refresh = "cast",
          text = T("Hat hier Zauberzeit: so wirken, dass sie beim Ablauf landet.", "Has a cast time here: cast so it lands as the old one ends.") },    -- Verderbnis / Corruption
        { id = 686, key = "proc:686", kind = "priority", when = "proc", aura = 17941,
          text = T("Bei {17941}: sofort.", "On {17941}: at once.") },    -- Schattenblitz / Shadow Bolt
        { id = 1454, key = "tap:move", kind = "resource", when = "lowmana", max = 60, need = { moving = true },    -- Annahme: die Quelle bevorzugt das Laufen, nennt aber keine Zahl
          text = T("Im Laufen schon früher auffüllen; achte auf dein Leben.", "While moving, top up earlier; mind your health.") },    -- Aderlass / Life Tap
        { id = 1454, kind = "resource", when = "lowmana", max = 30,    -- Annahme: keine Quelle nennt eine Zahl
          text = T("Bei wenig Mana; dein Leben muss einen Treffer aushalten.", "On low mana; your health must survive a hit.") },    -- Aderlass / Life Tap
        { id = 686, kind = "filler", when = "filler",
          text = T("Lückenfüller, wenn nichts Höheres ansteht.", "Gap filler when nothing higher is due.") },    -- Schattenblitz / Shadow Bolt
        -- Mehrere Gegner (nur Liste) ----------------------------------------------------------------------------------
        { id = 1949, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern um dich; im Anlaufen vorher {980}.", "Three or more enemies around you; {980} first on the way in.") },    -- Höllenfeuer / Hellfire
        { id = 5740, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, wenn der Nahkampf zu gefährlich ist.", "Three or more enemies when melee range is unsafe.") },    -- Feuerregen / Rain of Fire [V]
        -- Situativ ----------------------------------------------------------------------------------------------------
        { id = 755, kind = "situational", when = "manual",
          text = T("Heilt deinen Dämon, wenn er zu fallen droht.", "Heals your demon when it is about to die.") },    -- Lebenslinie / Health Funnel [V]
        { id = 1120, kind = "situational", when = "manual",
          text = T("Nur, um Seelensplitter aufzufüllen.", "Only to refill Soul Shards.") },    -- Seelendieb / Drain Soul [V]
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Zerstörung (mit dem Füller des Baums, also mit fertigem Aufbau)
    -----------------------------------------------------------------------------------------------------------------
    { key = "destruction", tree = 3, name = T("Zerstörung", "Destruction"),
      source = "https://www.icy-veins.com/wow-forever/destruction-warlock-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/destruction-warlock-ranged-dps-pve-guide",
                  "https://www.icy-veins.com/wow-forever/destruction-warlock-leveling" },
      pick = { known = 412758 },
      how = T("Die meiste Zeit wirkst du {412758} und hältst dafür {348} auf dem Ziel. {1293817} kommt, sobald es bereit ist und {348} liegt; {17877} nur, wenn sein Feuer-Bonus fehlt oder gleich endet, und nur mit einem Seelensplitter im Gepäck. Darüber stehen Omen, {348} und {172}. {1454} nutzt du rechtzeitig, aber nie auf Kosten deiner Sicherheit. Vor dem Kampf: Dämon opfern, Waffenstein, Rüstung.",
              "Most of the time you cast {412758} and keep {348} on the target for it. Use {1293817} whenever it is ready and {348} is up; {17877} only when its fire bonus is missing or about to end, and only with a Soul Shard in your bags. Above them: bane, {348} and {172}. Use {1454} in good time, but never at the cost of your safety. Before combat: sacrifice your demon, weapon stone, armor."),
      note = T("Die Regeln für {1293817} und {17877} gelten erst mit voll geskilltem {426316}; den Rang kann ezCombat nicht lesen und nimmt ihn an, sobald {412758} gelernt ist. Lebenszeit und Gegnerzahl sieht es nicht: {603} nur gegen Elite und Bosse, {1225228} und Fläche nur als Liste.",
               "The rules for {1293817} and {17877} apply only with {426316} fully talented; ezCombat can't read the rank and assumes it once {412758} is learned. It can't see time to live or enemy count: {603} on elites and bosses only, {1225228} and AoE are list only."),
      steps = {
        -- Vor dem Kampf -------------------------------------------------------------------------------------------
        { id = 706, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf wirken; es zählt die beste gelernte Rüstung.", "Cast before combat; your best learned armor counts.") },    -- Dämonenrüstung / Demon Armor
        { id = 18788, kind = "prepare", when = "manual",
          text = T("Sobald gelernt: rufen ({712}), opfern; ein neuer Dämon löscht es.", "Once learned: summon ({712}), sacrifice; a new demon ends it.") },    -- Dämonische Opferung / Demonic Sacrifice
        { id = 712, kind = "prepare", when = "pet", need = { unknown = 18788 },
          text = T("Kein Dämon da: den Schadens-Dämon rufen.", "No demon out: summon your damage demon.") },    -- Sukkubus beschwören / Summon Succubus [V]
        { id = 6366, kind = "prepare", when = "enchant", hand = "main",
          text = T("Dieser Stein gehört auf die Waffe; erneuern, wenn er fehlt.", "This stone belongs on your weapon; renew it when it is gone.") },    -- Feuerstein herstellen / Create Firestone [V]
        { id = 6201, kind = "prepare", when = "item", optional = true,
          item = HEALTHSTONES,
          text = T("Einen Stein für den Notfall herstellen.", "Create a stone for emergencies.") },    -- Gesundheitsstein herstellen / Create Healthstone
        { id = 1120, kind = "prepare", when = "item", item = 6265, optional = true,
          text = T("Mindestens einen Seelensplitter für {17877} bereithalten.", "Keep at least one Soul Shard ready for {17877}.") },    -- Seelendieb / Drain Soul [V Gegenstands-ID]
        { id = 693, kind = "prepare", when = "manual",
          text = T("In der Gruppe: auf den abgesprochenen Spieler legen.", "In a group: put it on the agreed player.") },    -- Seelenstein herstellen / Create Soulstone [V]
        -- Eröffnung -------------------------------------------------------------------------------------------------
        { id = 348, key = "opener:348", kind = "opener", when = "dot", refresh = "missing", need = { combat = false },
          text = T("Vorzaubern, damit der Lückenfüller von Anfang an verstärkt ist.", "Pre-cast so your gap filler is boosted from the start.") },    -- Feuerbrand / Immolate
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 603, kind = "maintain", when = "dot", group = "bane", refresh = "missing",
          need = { enemy = { rank = { "elite", "rareelite", "worldboss" } } },
          text = T("Nur in langen Kämpfen (Elite, Boss); nie überschreiben.", "Long fights only (elite, boss); never overwrite it.") },    -- Omen der Verdammnis / Bane of Doom [V]
        { id = 980, kind = "maintain", when = "dot", group = "bane", refresh = "missing",
          text = T("Kein Omen auf dem Ziel: setzen. Erst nach Ablauf erneuern.", "No bane on the target: apply. Renew only after it ends.") },    -- Omen der Pein / Bane of Agony
        { id = 440892, kind = "maintain", when = "dot", group = "curse", refresh = "missing", optional = true,
          text = T("Dein zugeteilter Fluch (ohne Absprache: dieser).", "Your assigned curse (without a call: this one).") },    -- Fluch der Elemente / Curse of the Elements [V]
        { id = 348, kind = "maintain", when = "dot", refresh = "cast",
          text = T("So wirken, dass er beim Ablauf landet – nicht früher, nicht später.", "Cast so it lands as the old one ends – not earlier, not later.") },    -- Feuerbrand / Immolate
        { id = 172, kind = "maintain", when = "dot", refresh = "cast",
          text = T("Fehlt: setzen. Nicht vorzeitig erneuern.", "Missing: apply. Don't renew early.") },    -- Verderbnis / Corruption
        { id = 1293817, key = "priority:17962", kind = "priority", when = "ready", need = { known = 412758, aura = { id = 348, unit = "target" } },
          text = T("Sofort, wenn bereit und dein {348} auf dem Ziel brennt.", "Fire it once it is off cooldown and your {348} is burning on the target.") },    -- Feuersbrunst / Conflagrate
        { id = 17877, kind = "priority", when = "buff", aura = 426316, refresh = 3,    -- 3: Schwelle aus der Quelle (Rest des Bonus)
          need = { known = 412758, item = { id = 6265, min = 1 } },
          text = T("Nur wenn sein Feuer-Bonus fehlt oder gleich endet.", "Only when its fire bonus is missing or about to end.") },    -- Schattenbrand / Shadowburn [V Aura-ID, Gegenstands-ID]
        { id = 1454, key = "tap:move", kind = "resource", when = "lowmana", max = 60, need = { moving = true },    -- Annahme: die Quelle bevorzugt das Laufen, nennt aber keine Zahl
          text = T("Im Laufen schon früher auffüllen; achte auf dein Leben.", "While moving, top up earlier; mind your health.") },    -- Aderlass / Life Tap
        { id = 1454, kind = "resource", when = "lowmana", max = 30,    -- Annahme: keine Quelle nennt eine Zahl
          text = T("Bevor das Mana leer ist – nie so tief, dass ein Treffer tötet.", "Before you run dry – never so low that one hit kills you.") },    -- Aderlass / Life Tap
        { id = 412758, kind = "filler", when = "filler",
          text = T("Lückenfüller, wenn nichts Höheres ansteht.", "Gap filler when nothing higher is due.") },    -- Verbrennen / Incinerate
        { id = 686, kind = "filler", when = "filler", need = { unknown = 412758 },
          text = T("Lückenfüller, solange {412758} fehlt.", "Gap filler until you learn {412758}.") },    -- Schattenblitz / Shadow Bolt
        -- Mehrere Gegner (nur Liste) ----------------------------------------------------------------------------------
        { id = 1225228, kind = "aoe", when = "aoe",
          text = T("Bei genau zwei Gegnern aufs Zweitziel; dort kein anderes Omen.", "With exactly two enemies on the second; no other bane there.") },    -- Omen der Verwüstung / Bane of Havoc [V]
        { id = 1949, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, solange du sicher mitten im Pulk stehst.", "Three or more enemies while you can safely stand among them.") },    -- Höllenfeuer / Hellfire [V]
        { id = 5740, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, wenn der Nahkampf zu gefährlich ist.", "Three or more enemies when melee range is unsafe.") },    -- Feuerregen / Rain of Fire [V]
        -- Situativ ----------------------------------------------------------------------------------------------------
        { id = 6789, kind = "situational", when = "manual",
          text = T("Als letzter Sofortzauber, wenn kein Lückenfüller mehr landet.", "As a last instant when no gap filler would land any more.") },    -- Todesmantel / Death Coil [V]
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Gebrechen (Leveln)
    -----------------------------------------------------------------------------------------------------------------
    { key = "affliction_level", tree = 1, name = T("Gebrechen (Leveln)", "Affliction (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/affliction-warlock-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/affliction-warlock-ranged-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Beim Leveln schickst du den Dämon vor, zauberst {348} aus der Ferne vor und setzt dann die Sofort-DoTs – nur auf Gegner, die lange genug leben. Danach spart der Zauberstab Mana, bis der Gegner fällt; ohne Stab füllt {686}. {17941} nutzt du sofort, {689} heilt dich bei Bedarf. Später ersetzt {1316697} den Stab, und mit {18788} kämpfst du ohne Dämon.",
              "While levelling, send your demon in, pre-cast {348} from range and then apply your instant DoTs – only on enemies that live long enough. After that your wand saves mana until the enemy dies; without a wand {686} fills. Use {17941} at once, and {689} heals you when needed. Later {1316697} replaces the wand, and with {18788} you fight without a demon."),
      note = T("Ob ein Gegner lange genug lebt, sieht ezCombat nicht: Die DoTs werden immer vorgeschlagen, du lässt sie bei kurzlebigen Gegnern weg.",
               "ezCombat can't see whether an enemy lives long enough: the DoTs are always suggested, skip them on short-lived enemies."),
      steps = {
        -- Vor dem Kampf -------------------------------------------------------------------------------------------
        { id = 706, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf wirken; es zählt die beste gelernte Rüstung.", "Cast before combat; your best learned armor counts.") },    -- Dämonenrüstung / Demon Armor
        { id = 18788, kind = "prepare", when = "manual",
          text = T("Sobald gelernt: rufen ({691}), opfern; danach keinen Dämon mehr.", "Once learned: summon ({691}), sacrifice; no demon afterwards.") },    -- Dämonische Opferung / Demonic Sacrifice
        { id = 712, kind = "prepare", when = "pet", need = { unknown = 18788 },
          text = T("Kein Dämon da: den Schadens-Dämon rufen.", "No demon out: summon your damage demon.") },    -- Sukkubus beschwören / Summon Succubus [V]
        { id = 697, kind = "prepare", when = "pet", need = { unknown = { 712, 18788 } },
          text = T("Früh: dieser Dämon hält die Gegner bei sich.", "Early on: this demon keeps the enemies on itself.") },    -- Leerwandler beschwören / Summon Voidwalker [V]
        { id = 688, kind = "prepare", when = "pet", need = { unknown = { 697, 712, 18788 } },
          text = T("Dein erster Dämon, bis du einen besseren rufen kannst.", "Your first demon until you can summon a better one.") },    -- Wichtel beschwören / Summon Imp [V]
        { id = 2362, kind = "prepare", when = "enchant", hand = "main",
          text = T("Stein auf die Waffe, sobald sie keinen trägt.", "Put a stone on your weapon when it has none.") },    -- Zauberstein herstellen / Create Spellstone
        { id = 6366, kind = "prepare", when = "enchant", hand = "main", need = { unknown = 2362 },
          text = T("Solange {2362} fehlt: dieser Stein auf die Waffe.", "Until you learn {2362}: this stone on your weapon.") },    -- Feuerstein herstellen / Create Firestone [V]
        { id = 6201, kind = "prepare", when = "item", optional = true,
          item = HEALTHSTONES,
          text = T("Einen Stein für den Notfall herstellen.", "Create a stone for emergencies.") },    -- Gesundheitsstein herstellen / Create Healthstone
        -- Eröffnung -------------------------------------------------------------------------------------------------
        { id = 348, key = "opener:348", kind = "opener", when = "dot", refresh = "missing", need = { combat = false },
          text = T("Dämon vorschicken, aus der Ferne vorzaubern, dann die Dauerschaden-Zauber.", "Send your demon, pre-cast from range, then your damage-over-time spells.") },    -- Feuerbrand / Immolate
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 18288, kind = "priority", when = "ready", need = { noaura = { id = "bane", unit = "target" } },
          text = T("Direkt vor einem neuen {980}.", "Right before a new {980}.") },    -- Fluch verstärken / Amplify Curse
        { id = 980, kind = "maintain", when = "dot", group = "bane", refresh = "missing",
          text = T("Nur auf Gegner, die lange genug leben; nie vorzeitig.", "Only on enemies that live long enough; never early.") },    -- Omen der Pein / Bane of Agony
        { id = 172, kind = "maintain", when = "dot", refresh = "cast",
          text = T("Fehlt: setzen. Nicht vorzeitig erneuern.", "Missing: apply. Don't renew early.") },    -- Verderbnis / Corruption
        { id = 18265, kind = "maintain", when = "dot", refresh = "missing",
          text = T("Nur auf Gegner, die lange genug leben.", "Only on enemies that live long enough.") },    -- Lebensentzug / Siphon Life
        -- Feuerbrand auch im Kampf: Die Eröffnung oben gilt nur vor dem Kampf; ohne diesen Schritt fehlte er auf jedem
        -- Ziel, das erst im Kampf dazukommt (Spieltest 16.11.2026, Tests/rotation_zielwechsel.lua).
        { id = 348, kind = "maintain", when = "dot", refresh = "cast",
          text = T("Auf jedem Ziel nach den Sofort-DoTs; erneuern, wenn der alte endet.", "On every target after your instant DoTs; renew as the old one ends.") },    -- Feuerbrand / Immolate
        { id = 686, key = "proc:686", kind = "priority", when = "proc", aura = 17941,
          text = T("Bei {17941}: sofort.", "On {17941}: at once.") },    -- Schattenblitz / Shadow Bolt
        { id = 1454, key = "tap:move", kind = "resource", when = "lowmana", max = 60, need = { moving = true },    -- Annahme: die Quelle bevorzugt das Laufen, nennt aber keine Zahl
          text = T("Im Laufen schon früher auffüllen; achte auf dein Leben.", "While moving, top up earlier; mind your health.") },    -- Aderlass / Life Tap
        { id = 1454, kind = "resource", when = "lowmana", max = 30,    -- Annahme: keine Quelle nennt eine Zahl
          text = T("Bei wenig Mana, bevor es ganz leer ist; achte auf dein Leben.", "On low mana, before it runs dry; mind your health.") },    -- Aderlass / Life Tap
        { id = 1316697, kind = "filler", when = "filler",
          text = T("Lückenfüller, sobald gelernt; für Dauerschaden darfst du abbrechen.", "Gap filler once learned; you may cut it short for damage over time.") },    -- Zermürben / Wrack
        { id = 5019, kind = "filler", when = "autorepeat",
          text = T("Lückenfüller beim Leveln: spart Mana, bis der Gegner fällt.", "Levelling gap filler: saves mana until the enemy dies.") },    -- Schießen / Shoot [V]
        { id = 686, kind = "filler", when = "filler", need = { unusable = 5019 },
          text = T("Lückenfüller, solange du keinen Zauberstab hast.", "Gap filler as long as you have no wand.") },    -- Schattenblitz / Shadow Bolt
        -- Mehrere Gegner (nur Liste) ----------------------------------------------------------------------------------
        { id = 1949, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern um dich; achte auf dein Leben.", "Three or more enemies around you; mind your health.") },    -- Höllenfeuer / Hellfire [V]
        { id = 5740, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, wenn der Nahkampf zu gefährlich ist.", "Three or more enemies when melee range is unsafe.") },    -- Feuerregen / Rain of Fire [V]
        -- Situativ ----------------------------------------------------------------------------------------------------
        { id = 689, kind = "situational", when = "manual",
          text = T("Statt des Lückenfüllers, wenn du Heilung brauchst.", "Instead of your gap filler when you need healing.") },    -- Blutsauger / Drain Life [V]
        { id = 1120, kind = "situational", when = "manual",
          text = T("Nur, um Seelensplitter aufzufüllen.", "Only to refill Soul Shards.") },    -- Seelendieb / Drain Soul [V]
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Dämonologie (Leveln)
    -----------------------------------------------------------------------------------------------------------------
    { key = "demonology_level", tree = 2, name = T("Dämonologie (Leveln)", "Demonology (levelling)"),
      source = "https://www.icy-veins.com/wow-forever/demonology-warlock-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/demonology-warlock-ranged-dps-pve-rotation-cooldowns-abilities" },
      pick = { leveling = true },
      how = T("Allein hält dein Dämon die Gegner bei sich: erst vorschicken, währenddessen {348} vorzaubern. Mit dem Talent {1293695} folgt {5676}, dann {980} und {172} auf Gegner, die lange genug leben. Den Rest erledigt der Zauberstab – das spart Mana für den nächsten Gegner; ohne Stab füllt {686}. {18788} lohnt erst mit {425464}, vorher behältst du den Dämon.",
              "Solo, your demon keeps the enemies on itself: send it in first and pre-cast {348} meanwhile. With the {1293695} talent {5676} follows, then {980} and {172} on enemies that live long enough. Your wand does the rest – that saves mana for the next enemy; without a wand {686} fills. {18788} only pays off with {425464}; keep your demon until then."),
      note = T("Ob ein Gegner lange genug lebt, sieht ezCombat nicht: Die DoTs werden immer vorgeschlagen, du lässt sie bei kurzlebigen Gegnern weg. Ohne das Talent {1293695} wird {5676} nie vorgeschlagen, ohne Ziel deines Dämons ebenfalls nicht.",
               "ezCombat can't see whether an enemy lives long enough: the DoTs are always suggested, skip them on short-lived enemies. Without the {1293695} talent {5676} is never suggested, nor while your demon has no target."),
      steps = {
        -- Vor dem Kampf -------------------------------------------------------------------------------------------
        { id = 706, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf wirken; es zählt die beste gelernte Rüstung.", "Cast before combat; your best learned armor counts.") },    -- Dämonenrüstung / Demon Armor
        { id = 697, kind = "prepare", when = "pet",
          text = T("Kein Dämon da: allein hält dieser die Gegner bei sich.", "No demon out: solo, this one keeps the enemies on itself.") },    -- Leerwandler beschwören / Summon Voidwalker [V]
        { id = 688, kind = "prepare", when = "pet", need = { unknown = 697 },
          text = T("Dein erster Dämon, bis du einen besseren rufen kannst.", "Your first demon until you can summon a better one.") },    -- Wichtel beschwören / Summon Imp [V]
        { id = 19028, kind = "longbuff", when = "buff", need = { pet = true },
          text = T("Mit Dämon immer aktiv; nach jedem Dämonenwechsel neu.", "Always on with a demon; recast after every demon swap.") },    -- Seelenverbindung / Soul Link
        { id = 18788, kind = "prepare", when = "manual",
          text = T("Erst mit {425464} nutzen; vorher den Dämon behalten.", "Use only with {425464}; keep your demon until then.") },    -- Dämonische Opferung / Demonic Sacrifice
        { id = 2362, kind = "prepare", when = "enchant", hand = "main",
          text = T("Stein auf die Waffe, sobald sie keinen trägt.", "Put a stone on your weapon when it has none.") },    -- Zauberstein herstellen / Create Spellstone
        { id = 6366, kind = "prepare", when = "enchant", hand = "main", need = { unknown = 2362 },
          text = T("Solange {2362} fehlt: dieser Stein auf die Waffe.", "Until you learn {2362}: this stone on your weapon.") },    -- Feuerstein herstellen / Create Firestone [V]
        { id = 6201, kind = "prepare", when = "item", optional = true,
          item = HEALTHSTONES,
          text = T("Einen Stein für den Notfall herstellen.", "Create a stone for emergencies.") },    -- Gesundheitsstein herstellen / Create Healthstone
        -- Eröffnung -------------------------------------------------------------------------------------------------
        { id = 348, key = "opener:348", kind = "opener", when = "dot", refresh = "missing", need = { combat = false },
          text = T("Dämon vorschicken; währenddessen aus der Ferne vorzaubern.", "Send your demon in; pre-cast from range meanwhile.") },    -- Feuerbrand / Immolate
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        -- ohne Ziel des Dämons nicht fällig (der Motor prüft „pettarget“)
        { id = 5676, kind = "maintain", when = "dot", aura = 1293695, unit = "pettarget", refresh = "missing",
          need = { known = 1293695, pet = true },
          text = T("Fehlt {1293695} am Ziel deines Dämons: wirken. Ohne Ziel des Dämons nicht.",
                   "{1293695} missing on your demon's target: cast. Not while your demon has no target.") },    -- Sengender Schmerz / Searing Pain [V Talent abfragbar]
        { id = 18288, kind = "priority", when = "ready", need = { noaura = { id = "bane", unit = "target" } },
          text = T("Ab dem Talent: direkt vor einem neuen {980}.", "Once talented: right before a new {980}.") },    -- Fluch verstärken / Amplify Curse
        { id = 980, kind = "maintain", when = "dot", group = "bane", refresh = "missing",
          text = T("Nur auf Gegner, die lange genug leben; nie vorzeitig.", "Only on enemies that live long enough; never early.") },    -- Omen der Pein / Bane of Agony
        { id = 172, kind = "maintain", when = "dot", refresh = "cast",
          text = T("Nur auf Gegner, die lange genug leben; nie vorzeitig.", "Only on enemies that live long enough; never early.") },    -- Verderbnis / Corruption
        -- Feuerbrand auch im Kampf (wie bei „Gebrechen (Leveln)“: die Eröffnung gilt nur vor dem Kampf)
        { id = 348, kind = "maintain", when = "dot", refresh = "cast",
          text = T("Auf jedem Ziel nach den Sofort-DoTs; erneuern, wenn der alte endet.", "On every target after your instant DoTs; renew as the old one ends.") },    -- Feuerbrand / Immolate
        { id = 686, key = "proc:686", kind = "priority", when = "proc", aura = 17941,
          text = T("Bei {17941}: sofort.", "On {17941}: at once.") },    -- Schattenblitz / Shadow Bolt
        { id = 1454, key = "tap:move", kind = "resource", when = "lowmana", max = 60, need = { moving = true },    -- Annahme: die Quelle bevorzugt das Laufen, nennt aber keine Zahl
          text = T("Im Laufen schon früher auffüllen; achte auf dein Leben.", "While moving, top up earlier; mind your health.") },    -- Aderlass / Life Tap
        { id = 1454, kind = "resource", when = "lowmana", max = 30,    -- Annahme: keine Quelle nennt eine Zahl
          text = T("Bei wenig Mana; dein Leben muss einen Treffer aushalten.", "On low mana; your health must survive a hit.") },    -- Aderlass / Life Tap
        { id = 5019, kind = "filler", when = "autorepeat",
          text = T("Lückenfüller beim Leveln: spart Mana, bis der Gegner fällt.", "Levelling gap filler: saves mana until the enemy dies.") },    -- Schießen / Shoot [V]
        { id = 686, kind = "filler", when = "filler", need = { unusable = 5019 },
          text = T("Lückenfüller, solange du keinen Zauberstab hast.", "Gap filler as long as you have no wand.") },    -- Schattenblitz / Shadow Bolt
        -- Mehrere Gegner (nur Liste) ----------------------------------------------------------------------------------
        { id = 1949, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern um dich; im Anlaufen vorher {980}.", "Three or more enemies around you; {980} first on the way in.") },    -- Höllenfeuer / Hellfire
        { id = 5740, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, wenn der Nahkampf zu gefährlich ist.", "Three or more enemies when melee range is unsafe.") },    -- Feuerregen / Rain of Fire [V]
        -- Situativ ----------------------------------------------------------------------------------------------------
        { id = 755, kind = "situational", when = "manual",
          text = T("Heilt deinen Dämon, wenn er zu fallen droht.", "Heals your demon when it is about to die.") },    -- Lebenslinie / Health Funnel [V]
        { id = 689, kind = "situational", when = "manual",
          text = T("Statt des Lückenfüllers, wenn du Heilung brauchst.", "Instead of your gap filler when you need healing.") },    -- Blutsauger / Drain Life [V]
      } },

    -----------------------------------------------------------------------------------------------------------------
    -- Zerstörung (Leveln, bevor der Füller des Baums gelernt ist)
    -----------------------------------------------------------------------------------------------------------------
    { key = "destruction_level", tree = 3, name = T("Zerstörung (frühes Leveln)", "Destruction (early levelling)"),
      source = "https://www.icy-veins.com/wow-forever/destruction-warlock-leveling",
      sources = { "https://www.icy-veins.com/wow-forever/destruction-warlock-ranged-dps-pve-rotation-cooldowns-abilities" },
      pick = { unknown = 412758 },
      how = T("Bevor du {412758} hast, eröffnest du mit {686} aus größter Entfernung und wirkst sofort {348} hinterher. Danach kommt {980} auf langlebige Gegner, und {686} füllt. {1293817} verbraucht hier noch {348} und gehört deshalb an dessen Ende oder zum Abschluss; {17877} nur als Abschluss, damit der Splitter zurückkommt. Die Quelle rät, so früh eher mit einem anderen Baum zu leveln.",
              "Before you have {412758}, open with {686} from maximum range and follow with {348} at once. Then {980} on long-lived enemies, and {686} fills. {1293817} still consumes {348} here, so it belongs at its end or as a finisher; {17877} is a finisher only, so the shard comes back. The source advises levelling with another tree this early."),
      note = T("Ob ein Gegner gleich fällt, sieht ezCombat nicht: {1293817} und {17877} stehen hier nur als Text. Sobald {412758} gelernt ist, wechselt „Nach Talentbaum“ zur anderen Fassung.",
               "ezCombat can't see whether an enemy is about to die: {1293817} and {17877} are text only here. Once {412758} is learned, \"By talent tree\" switches to the other version."),
      steps = {
        -- Vor dem Kampf -------------------------------------------------------------------------------------------
        { id = 706, kind = "longbuff", buff = "armor", when = "buff",
          text = T("Vor dem Kampf wirken; es zählt die beste gelernte Rüstung.", "Cast before combat; your best learned armor counts.") },    -- Dämonenrüstung / Demon Armor
        { id = 712, kind = "prepare", when = "pet", need = { unknown = 18788 },
          text = T("Kein Dämon da: den Schadens-Dämon rufen.", "No demon out: summon your damage demon.") },    -- Sukkubus beschwören / Summon Succubus [V]
        { id = 697, kind = "prepare", when = "pet", need = { unknown = { 712, 18788 } },
          text = T("Früh: dieser Dämon hält die Gegner bei sich.", "Early on: this demon keeps the enemies on itself.") },    -- Leerwandler beschwören / Summon Voidwalker [V]
        { id = 688, kind = "prepare", when = "pet", need = { unknown = { 697, 712, 18788 } },
          text = T("Dein erster Dämon, bis du einen besseren rufen kannst.", "Your first demon until you can summon a better one.") },    -- Wichtel beschwören / Summon Imp [V]
        { id = 6366, kind = "prepare", when = "enchant", hand = "main",
          text = T("Dieser Stein gehört auf die Waffe; erneuern, wenn er fehlt.", "This stone belongs on your weapon; renew it when it is gone.") },    -- Feuerstein herstellen / Create Firestone [V]
        { id = 6201, kind = "prepare", when = "item", optional = true,
          item = HEALTHSTONES,
          text = T("Einen Stein für den Notfall herstellen.", "Create a stone for emergencies.") },    -- Gesundheitsstein herstellen / Create Healthstone
        -- Eröffnung: feste Folge je Gegner (geschlossener Block) -------------------------------------------------------
        { id = 686, key = "opener:686", kind = "opener", when = "ready", once = "target", need = { combat = false },
          text = T("Aus größter Entfernung eröffnen, sofort {348} hinterher.", "Open from maximum range and follow with {348} at once.") },    -- Schattenblitz / Shadow Bolt
        { id = 348, key = "opener:348", kind = "opener", when = "dot", refresh = "missing",
          text = T("Direkt nach dem Eröffnungszauber, solange der noch fliegt.", "Right after the opening cast, while it is still in flight.") },    -- Feuerbrand / Immolate
        -- Im Kampf (Reihenfolge = Rang) -----------------------------------------------------------------------------
        { id = 980, kind = "maintain", when = "dot", group = "bane", refresh = "missing",
          text = T("Nur auf Gegner, die lange genug leben; nie vorzeitig.", "Only on enemies that live long enough; never early.") },    -- Omen der Pein / Bane of Agony
        { id = 348, kind = "maintain", when = "dot", refresh = "cast",
          text = T("So wirken, dass er beim Ablauf des alten landet.", "Cast so it lands as the old one ends.") },    -- Feuerbrand / Immolate
        { id = 172, kind = "maintain", when = "dot", refresh = "cast",
          text = T("Nur auf Gegner, die lange genug leben; nie vorzeitig.", "Only on enemies that live long enough; never early.") },    -- Verderbnis / Corruption
        { id = 1454, key = "tap:move", kind = "resource", when = "lowmana", max = 60, need = { moving = true },    -- Annahme: die Quelle bevorzugt das Laufen, nennt aber keine Zahl
          text = T("Im Laufen schon früher auffüllen; achte auf dein Leben.", "While moving, top up earlier; mind your health.") },    -- Aderlass / Life Tap
        { id = 1454, kind = "resource", when = "lowmana", max = 30,    -- Annahme: keine Quelle nennt eine Zahl
          text = T("Bevor das Mana leer ist – nie so tief, dass ein Treffer tötet.", "Before you run dry – never so low that one hit kills you.") },    -- Aderlass / Life Tap
        { id = 686, kind = "filler", when = "filler",
          text = T("Lückenfüller, bis du den Lückenfüller des Baums gelernt hast.", "Gap filler until you learn the gap filler of this tree.") },    -- Schattenblitz / Shadow Bolt
        -- Mehrere Gegner (nur Liste) ----------------------------------------------------------------------------------
        { id = 1225228, kind = "aoe", when = "aoe",
          text = T("Bei genau zwei Gegnern aufs Zweitziel; dort kein anderes Omen.", "With exactly two enemies on the second; no other bane there.") },    -- Omen der Verwüstung / Bane of Havoc [V]
        { id = 1949, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, solange du sicher mitten im Pulk stehst.", "Three or more enemies while you can safely stand among them.") },    -- Höllenfeuer / Hellfire [V]
        { id = 5740, kind = "aoe", when = "aoe",
          text = T("Ab drei Gegnern, wenn der Nahkampf zu gefährlich ist.", "Three or more enemies when melee range is unsafe.") },    -- Feuerregen / Rain of Fire [V]
        -- Situativ ----------------------------------------------------------------------------------------------------
        { id = 1293817, key = "situational:17962", kind = "situational", when = "manual",
          text = T("Verbraucht hier {348}: nur an dessen Ende oder zum Abschluss.", "Consumes {348} here: only at its end or as a finisher.") },    -- Feuersbrunst / Conflagrate
        { id = 17877, kind = "situational", when = "manual",
          text = T("Nur zum Abschluss: Fällt der Gegner, kommt der Splitter zurück.", "Finisher only: if the enemy dies, you get the shard back.") },    -- Schattenbrand / Shadowburn
        { id = 5676, kind = "situational", when = "manual",
          text = T("Schneller Abschluss, wenn der Gegner fast am Ende ist.", "Quick finisher when the enemy is almost dead.") },    -- Sengender Schmerz / Searing Pain
        { id = 5019, kind = "situational", when = "manual",
          text = T("Gegner fast am Ende: mit dem Zauberstab Mana sparen.", "Enemy almost dead: save mana with your wand.") },    -- Schießen / Shoot [V]
      } },
})
