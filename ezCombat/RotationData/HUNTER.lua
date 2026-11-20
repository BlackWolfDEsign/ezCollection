local _, ns = ...
local T = ns.RotationData.T

-- Jäger (HUNTER): Rotationen für WoW Forever. Format und Felder: Kopf von RotationData.lua.
-- Quellen, abgerufen am 13.11.2026 – nur Fakten (Rangfolge, Bedingungen), alle Texte in eigenen Worten:
--   Tierherrschaft:  https://www.icy-veins.com/wow-forever/beast-mastery-hunter-ranged-dps-pve-rotation-cooldowns-abilities
--                    https://www.icy-veins.com/wow-forever/beast-mastery-hunter-leveling
--                    https://www.wowhead.com/forever/guide/classes/hunter/beast-mastery/rotation-cooldowns-pve-dps
--   Treffsicherheit: https://www.icy-veins.com/wow-forever/marksmanship-hunter-ranged-dps-pve-rotation-cooldowns-abilities
--                    https://www.icy-veins.com/wow-forever/marksmanship-hunter-leveling
--                    https://www.wowhead.com/forever/guide/classes/hunter/marksmanship/rotation-cooldowns-pve-dps
--   Überleben:       https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-rotation-cooldowns-abilities
--                    https://www.icy-veins.com/wow-forever/survival-hunter-leveling
--                    https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-guide
--                    https://www.wowhead.com/forever/guide/classes/hunter/survival/rotation-cooldowns-pve-dps
-- Zauber-IDs (Rang 1) geprüft gegen nether.wowhead.com/forever. Nichts stammt aus einem Addon. Name, Symbol, Ränge,
-- gelernt, Lernstufe, Zauberzeit, Abklingzeit und Dauer liefert der Client zur Laufzeit. Aura des Volltreffers steht
-- mit der Grund-ID 1299346 (Rang 1, Talent, laut Client-Tabellen ClassSpells, wago.tools wowf 1.60.1.70938; vorher
-- 19506, Rang 3 ab Stufe 40 – Gesamtreview 18.11.2026, T14-NH1; der Schlüssel der Schritte bleibt für gemerkte
-- Anpassungen).
--
-- Bauart:
--   Reichweite   Nahkampf-Schritte und Fallen fragen die Reichweite des Nahkampfschlags 2973 (need.inrange), alle
--                Schüsse das Gegenteil (need.outrange; Mindestabstand). Liefert der Client nichts, wird übersprungen.
--   Falken       Zähler hawks: eigene erfolgreiche Zauber, je Falke eine eigene Uhr. Die Sekunden unter fallback
--                sind ein gekennzeichneter Rückfall (Talenttext), weil der Falke keine lesbare Aura hinterlässt.
--   Leveln       dieselbe Rotation, einzelne Schritte mit need.leveling (sparsamer mit Mana, DoT einmal je Gegner).
--   Überleben    zwei Spielweisen: survival (Nahkampf, sobald der Tritt 1317257 gelernt ist) und survival_ranged.
--
-- Bedarf (fehlt im Format oder in ezCore, bis dahin Text bzw. situativ):
--   need.counter.oldest.max    „der älteste Falke endet gleich“ – der Falke kommt deshalb erst, wenn einer fehlt
--   Aufspüren                  aktive Aufspür-Art gegen den Kreaturentyp des Ziels (nur Text am Schritt 1494)
--   Begleiter                  tot oder unzufrieden ist nicht prüfbar; when = "pet" sieht nur „keiner da“
--   Talent „ohne Begleiter“    Zauber-ID nicht ermittelt – der Schritt „Begleiter rufen“ ist dort optional
--   Buff nach einem Sieg mit liegendem DoT (Treffsicherheit): Aura-ID nicht ermittelt – nur Text

-- Zwei Falken gleichzeitig; jeder läuft für sich ab.
local HAWKS = { hawks = { max = 2, each = true, gain = { [1293241] = 1 }, fallback = { seconds = 18 } } }
-- Einstufungen, bei denen ein Kampf lange genug dauert.
local STRONG = { "elite", "rareelite", "worldboss" }
-- Aspekte zum Reisen: solange einer läuft, wird der Kampf-Aspekt erst mit einem Ziel verlangt.
local TRAVEL = { 5118, 13159 }

ns.RotationData.Add("HUNTER", {
    -----------------------------------------------------------------------------------------------------------
    -- Tierherrschaft
    -----------------------------------------------------------------------------------------------------------
    { key = "beastmastery", tree = 1, name = T("Tierherrschaft", "Beast Mastery"),
      source = "https://www.icy-veins.com/wow-forever/beast-mastery-hunter-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/beast-mastery-hunter-leveling",
          "https://www.wowhead.com/forever/guide/classes/hunter/beast-mastery/rotation-cooldowns-pve-dps" },
      how = T("Bleib stehen und lass den automatischen Schuss laufen; Pausen zwischen den Tasten sind gewollt. Der Begleiter greift zuerst an. Halte {1978} auf dem Ziel und mit {1293241} stets zwei Falken, dazu {19434}, sooft es geht. {3044} teilt sich die Abklingzeit mit {1293241} und kommt nur, wenn beide Falken noch eine Weile bleiben. Steht der Gegner bei dir, leg eine Falle.",
              "Stand still and keep auto-shooting; gaps between key presses are intended. Your pet attacks first. Keep {1978} on the target and two hawks out with {1293241}, plus {19434} whenever you can. {3044} shares its cooldown with {1293241} and only fits while both hawks will stay a while. If the enemy stands next to you, drop a trap."),
      note = T("Die Falken zählt ezCombat aus deinen eigenen Zaubern (Einstellung „Mitzählen“). Gegnerzahl, Bedrohung und ob der Begleiter schon getroffen hat, sieht es nicht. Bei den Fallen widersprechen sich die Quellen: Die Seiten zu Tierherrschaft und Treffsicherheit nennen eine Falle gleichzeitig, die Überleben-Seite und die Tooltips zwei.",
               "ezCombat counts hawks from your own casts (the “Count” setting). It can't see enemy count, threat or whether your pet has hit yet. The sources disagree on traps: the Beast Mastery and Marksmanship pages allow one at a time, the Survival page and the tooltips two."),
      counters = HAWKS,
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------
        { id = 13165, kind = "longbuff", when = "buff", need = { noaura = { id = TRAVEL } },
          text = T("Vor dem Kampf einschalten; bleibt bis zum Wechsel.", "Switch on before combat; stays until you swap.") },    -- Aspekt des Falken / Aspect of the Hawk
        { id = 13165, key = "prepare:aspect", kind = "prepare", when = "buff", need = { target = true, aura = { id = TRAVEL } },
          text = T("Du reist noch: vor dem Angriff umschalten.", "Still travelling: swap before you attack.") },    -- Aspekt des Falken / Aspect of the Hawk
        { id = 883, kind = "prepare", when = "pet",
          text = T("Kein Begleiter da: rufen (ist er tot: {982}).", "No pet out: call it (if dead: {982}).") },    -- Tier rufen / Call Pet
        { id = 1130, kind = "prepare", when = "dot", mine = false, refresh = "missing", need = { target = true },
          text = T("Vor dem Angriff aufs Ziel; dann den Begleiter schicken.", "On the target before you attack; then send your pet.") },    -- Mal des Jägers / Hunter's Mark
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------
        { id = 1130, key = "maintain:mark", kind = "maintain", when = "dot", mine = false, refresh = "missing",
          need = { enemy = { rank = STRONG } },
          text = T("Fehlt es in einem langen Kampf: neu setzen.", "Missing in a long fight: apply it again.") },    -- Mal des Jägers / Hunter's Mark
        { id = 1978, kind = "maintain", when = "dot", refresh = "missing", need = { leveling = false, outrange = 2973 },
          text = T("Auf dem Ziel halten; erst nach Ablauf erneuern.", "Keep it on the target; renew only after it ends.") },    -- Schlangenbiss / Serpent Sting
        { id = 1978, key = "level:sting", kind = "maintain", when = "dot", refresh = "missing", once = "target",
          need = { leveling = true, outrange = 2973 },
          text = T("Beim Leveln einmal je Gegner, sobald der Begleiter dran ist.", "Levelling: once per enemy, after your pet engages.") },    -- Schlangenbiss / Serpent Sting
        { id = 19574, kind = "cooldown", burst = true, when = "ready", need = { pet = true },
          text = T("Sobald bereit; beim Leveln für starke Gegner aufsparen.", "Whenever ready; save it for tough enemies while levelling.") },    -- Zorn des Wildtiers / Bestial Wrath
        { id = 3045, kind = "cooldown", burst = true, when = "ready",
          text = T("Zusammen mit Schmuck und Volksfähigkeit zünden.", "Fire it together with trinkets and your racial.") },    -- Schnellfeuer / Rapid Fire
        { id = 1293241, kind = "priority", when = "ready", need = { counter = { name = "hawks", max = 1 } },
          text = T("Sobald weniger als zwei Falken fliegen.", "Whenever fewer than two hawks are out.") },    -- Falke beschwören / Summon Hawk
        { id = 2643, kind = "aoe", when = "ready", need = { outrange = 2973 },
          text = T("Bei mehreren Gegnern statt {19434}.", "With several enemies instead of {19434}.") },    -- Mehrfachschuss / Multi-Shot
        { id = 19434, kind = "priority", when = "ready", need = { moving = false, outrange = 2973 },
          text = T("Sobald bereit; dafür stehen bleiben.", "Whenever ready; stand still for it.") },    -- Gezielter Schuss / Aimed Shot
        { id = 13813, kind = "aoe", when = "ready", need = { inrange = 2973 },
          text = T("Mehrere Gegner bei dir: statt {13795} legen.", "Several enemies next to you: place it instead of {13795}.") },    -- Sprengfalle / Explosive Trap
        -- 5: Annahme – etwas unter der geteilten Abklingzeit, damit Reaktionszeit bleibt (Quelle: „länger als die Abklingzeit“)
        { id = 3044, kind = "priority", when = "ready",
          need = { leveling = false, known = 1293241, outrange = 2973,
              counter = { name = "hawks", min = 2, oldest = { min = 5 } } },
          text = T("Nur wenn beide Falken noch eine Weile bleiben.", "Only while both hawks will stay a while.") },    -- Arkaner Schuss / Arcane Shot
        -- 90: Annahme für „Mana voll“ (die Quelle nennt keine Zahl)
        { id = 3044, key = "level:arcane", kind = "priority", when = "ready",
          need = { leveling = true, known = 1293241, mana = { min = 90 }, outrange = 2973,
              counter = { name = "hawks", min = 2, oldest = { min = 5 } } },
          text = T("Leveln: nur mit zwei Falken und vollem Mana.", "Levelling: only with two hawks and full mana.") },    -- Arkaner Schuss / Arcane Shot
        -- 50: Annahme für „Mana übrig“ (die Quelle nennt keine Zahl)
        { id = 3044, key = "early:arcane", kind = "priority", when = "ready", need = { unknown = 1293241, mana = { min = 50 }, outrange = 2973 },
          text = T("Solange {1293241} fehlt: wenn Mana übrig ist.", "Until you learn {1293241}: when you have mana to spare.") },    -- Arkaner Schuss / Arcane Shot
        { id = 13795, kind = "maintain", when = "ready", need = { inrange = 2973, aoe = false },
          text = T("Gegner bei dir und nichts Wichtigeres: legen.", "Enemy next to you and nothing better to do: place it.") },    -- Feuerbrandfalle / Immolation Trap
        { id = 1510, kind = "aoe", when = "ready", hold = true, need = { moving = false, outrange = 2973 },
          text = T("Lückenfüller bei vielen Gegnern; bis zum Ende kanalisieren.", "Gap filler on many enemies; let the channel finish.") },    -- Salve / Volley
        { id = 2973, kind = "phase", when = "ready", side = true, need = { inrange = 2973, queued = false },
          text = T("Nur wenn der Gegner an dir steht.", "Only when the enemy is on top of you.") },    -- Raptorstoß / Raptor Strike
        { id = 75, kind = "filler", when = "autorepeat", need = { outrange = 2973 },
          text = T("Läuft er nicht: einschalten und stehen bleiben.", "Not running: start it and stand still.") },    -- Automatischer Schuss / Auto Shot
        -- Situativ -------------------------------------------------------------------------------------------
        { id = 19577, kind = "situational", when = "manual",
          text = T("Betäubt über den Begleiter und hilft ihm, das Ziel zu halten.", "Stuns through your pet and helps it hold the target.") },    -- Einschüchterung / Intimidation
        { id = 136, kind = "situational", when = "manual",
          text = T("Wenn der Begleiter viel Leben verliert.", "When your pet is losing a lot of health.") },    -- Tier heilen / Mend Pet
        { id = 781, kind = "situational", when = "manual",
          text = T("Der Gegner hängt an dir statt am Begleiter.", "The enemy is on you instead of your pet.") },    -- Rückzug / Disengage
        { id = 5384, kind = "situational", when = "manual",
          text = T("Notfall: Bedrohung loswerden.", "Emergency: drop your threat.") },    -- Totstellen / Feign Death
        { id = 5118, kind = "situational", when = "manual",
          text = T("Nur zum Laufen, wenn kein Schaden droht.", "For running only, when no damage is coming.") },    -- Aspekt des Geparden / Aspect of the Cheetah
      } },

    -----------------------------------------------------------------------------------------------------------
    -- Treffsicherheit
    -----------------------------------------------------------------------------------------------------------
    { key = "marksmanship", tree = 2, name = T("Treffsicherheit", "Marksmanship"),
      source = "https://www.icy-veins.com/wow-forever/marksmanship-hunter-ranged-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/marksmanship-hunter-leveling",
          "https://www.wowhead.com/forever/guide/classes/hunter/marksmanship/rotation-cooldowns-pve-dps" },
      how = T("Bleib stehen und lass den automatischen Schuss laufen. Die Rangfolge ist streng: {1310687}, dann {19434}, dann {1978} halten, zuletzt {3044}. Beim Leveln soll {1978} liegen, wenn der Gegner fällt – das stärkt den nächsten Schuss, also eröffne den nächsten Kampf mit dem dicksten Schuss. Bei mehreren Gegnern den Flächenmodus einschalten.",
              "Stand still and keep auto-shooting. The order is strict: {1310687}, then {19434}, then keep {1978} up, {3044} last. While levelling {1978} should be on the enemy when it dies – that empowers your next shot, so open the next fight with your biggest shot. Switch on AoE mode for several enemies."),
      note = T("Wann das Ziel stirbt und wie viele Gegner da sind, sieht ezCombat nicht. Der Begleiter ist hier Geschmackssache (ein Talent belohnt den Kampf ohne ihn) – der Schritt ist deshalb in der Vorlage aus.",
               "ezCombat can't see when the target will die or how many enemies there are. A pet is a matter of taste here (one talent rewards fighting without it) – so that step is off in the template."),
      counters = HAWKS,
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------
        { id = 13165, kind = "longbuff", when = "buff", need = { noaura = { id = TRAVEL } },
          text = T("Vor dem Kampf einschalten; bleibt bis zum Wechsel.", "Switch on before combat; stays until you swap.") },    -- Aspekt des Falken / Aspect of the Hawk
        { id = 13165, key = "prepare:aspect", kind = "prepare", when = "buff", need = { target = true, aura = { id = TRAVEL } },
          text = T("Du reist noch: vor dem Angriff umschalten.", "Still travelling: swap before you attack.") },    -- Aspekt des Falken / Aspect of the Hawk
        { id = 1299346, key = "longbuff:19506", kind = "longbuff", when = "buff",
          text = T("Vor dem Kampf auffrischen, sobald sie fehlt oder ausläuft.", "Refresh before combat when missing or about to end.") },    -- Aura des Volltreffers / Trueshot Aura
        { id = 883, kind = "prepare", when = "pet", optional = true,
          text = T("Kein Begleiter da: rufen – außer du kämpfst bewusst ohne.", "No pet out: call it – unless you fight without one on purpose.") },    -- Tier rufen / Call Pet
        { id = 1130, kind = "prepare", when = "dot", mine = false, refresh = "missing", need = { target = true },
          text = T("Vor dem Angriff aufs Ziel.", "On the target before you attack.") },    -- Mal des Jägers / Hunter's Mark
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------
        { id = 1130, key = "maintain:mark", kind = "maintain", when = "dot", mine = false, refresh = "missing",
          need = { enemy = { rank = STRONG } },
          text = T("Fehlt es in einem langen Kampf: neu setzen.", "Missing in a long fight: apply it again.") },    -- Mal des Jägers / Hunter's Mark
        { id = 3045, kind = "cooldown", burst = true, when = "ready",
          text = T("Mit Schmuck und Volksfähigkeit; Leveln: starke Gegner.", "With trinkets and racial; levelling: tough enemies.") },    -- Schnellfeuer / Rapid Fire
        { id = 2643, kind = "aoe", when = "ready", need = { outrange = 2973 },
          text = T("Bei mehreren Gegnern zuerst, statt {19434}.", "First on several enemies, instead of {19434}.") },    -- Mehrfachschuss / Multi-Shot
        { id = 13813, kind = "aoe", when = "ready", need = { inrange = 2973 },
          text = T("Mehrere Gegner bei dir: legen, sobald bereit.", "Several enemies next to you: place it whenever ready.") },    -- Sprengfalle / Explosive Trap
        { id = 1310687, kind = "priority", when = "ready", need = { moving = false, outrange = 2973 },
          text = T("Zuerst, sobald bereit; lange Zauberzeit, also stehen.", "First whenever ready; long cast, so stand still.") },    -- Heckenschützenschuss / Sniper Shot
        { id = 19434, kind = "priority", when = "ready", need = { moving = false, outrange = 2973 },
          text = T("Direkt danach, sobald bereit; stehen bleiben.", "Right after it whenever ready; stand still.") },    -- Gezielter Schuss / Aimed Shot
        { id = 1978, kind = "maintain", when = "dot", refresh = "missing", need = { outrange = 2973 },
          text = T("Halten; beim Leveln muss er liegen, wenn der Gegner fällt.", "Keep it up; levelling: it must be on when the enemy dies.") },    -- Schlangenbiss / Serpent Sting
        { id = 1293241, kind = "priority", when = "ready", need = { counter = { name = "hawks", max = 1 } },
          text = T("Falls geskillt: sobald weniger als zwei Falken fliegen.", "If talented: whenever fewer than two hawks are out.") },    -- Falke beschwören / Summon Hawk
        { id = 3044, kind = "priority", when = "ready", need = { leveling = false, unknown = 1293241, outrange = 2973 },
          text = T("Zuletzt, sobald bereit.", "Last, whenever it is ready.") },    -- Arkaner Schuss / Arcane Shot
        -- 90: Annahme für „Mana voll“ (die Quelle nennt keine Zahl)
        { id = 3044, key = "level:arcane", kind = "priority", when = "ready",
          need = { leveling = true, unknown = 1293241, mana = { min = 90 }, outrange = 2973 },
          text = T("Beim Leveln nur mit vollem Mana.", "While levelling only at full mana.") },    -- Arkaner Schuss / Arcane Shot
        -- 5 und 90: Annahmen wie bei der Tierherrschaft; die Mana-Schwelle gilt nur beim Leveln
        { id = 3044, key = "hawk:arcane", kind = "priority", when = "ready",
          need = { leveling = false, known = 1293241, outrange = 2973,
              counter = { name = "hawks", min = 2, oldest = { min = 5 } } },
          text = T("Mit Falken: nur wenn beide noch eine Weile bleiben.", "With hawks: only while both will stay a while.") },    -- Arkaner Schuss / Arcane Shot
        { id = 3044, key = "level:hawk:arcane", kind = "priority", when = "ready",
          need = { leveling = true, known = 1293241, mana = { min = 90 }, outrange = 2973,
              counter = { name = "hawks", min = 2, oldest = { min = 5 } } },
          text = T("Leveln mit Falken: nur wenn beide bleiben und das Mana voll ist.", "Levelling with hawks: only while both stay and mana is full.") },    -- Arkaner Schuss / Arcane Shot
        { id = 13795, kind = "maintain", when = "ready", need = { inrange = 2973, aoe = false },
          text = T("Gegner bei dir und nichts Wichtigeres: legen.", "Enemy next to you and nothing better to do: place it.") },    -- Feuerbrandfalle / Immolation Trap
        { id = 1510, kind = "aoe", when = "ready", hold = true, need = { moving = false, outrange = 2973 },
          text = T("Lückenfüller bei vielen Gegnern; bis zum Ende kanalisieren.", "Gap filler on many enemies; let the channel finish.") },    -- Salve / Volley
        { id = 2973, kind = "phase", when = "ready", side = true, need = { inrange = 2973, queued = false },
          text = T("Nur wenn der Gegner an dir steht.", "Only when the enemy is on top of you.") },    -- Raptorstoß / Raptor Strike
        { id = 75, kind = "filler", when = "autorepeat", need = { outrange = 2973 },
          text = T("Läuft er nicht: einschalten und stehen bleiben.", "Not running: start it and stand still.") },    -- Automatischer Schuss / Auto Shot
        -- Situativ -------------------------------------------------------------------------------------------
        { id = 781, kind = "situational", when = "manual",
          text = T("Der Gegner hängt an dir: Bedrohung senken.", "The enemy is on you: lower your threat.") },    -- Rückzug / Disengage
        { id = 5384, kind = "situational", when = "manual",
          text = T("Notfall: Bedrohung loswerden.", "Emergency: drop your threat.") },    -- Totstellen / Feign Death
        { id = 19801, kind = "situational", when = "manual",
          text = T("Nimmt einem Gegner die Raserei.", "Removes an enemy's frenzy.") },    -- Einlullender Schuss / Tranquilizing Shot
        { id = 1499, kind = "situational", when = "manual",
          text = T("Kontrolle: einen Gegner aus dem Kampf nehmen.", "Control: take one enemy out of the fight.") },    -- Eiskältefalle / Freezing Trap
      } },

    -----------------------------------------------------------------------------------------------------------
    -- Überleben: Nahkampf (der bisherige Schlüssel) und Fernkampf
    -----------------------------------------------------------------------------------------------------------
    { key = "survival", tree = 3, name = T("Überleben (Nahkampf)", "Survival (melee)"),
      source = "https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-guide",
          "https://www.icy-veins.com/wow-forever/survival-hunter-leveling",
          "https://www.wowhead.com/forever/guide/classes/hunter/survival/rotation-cooldowns-pve-dps" },
      pick = { known = 1317257 },     -- „Nach Talentbaum“: mit dem Tritt der Nahkampf, sonst survival_ranged
      how = T("Setz {1130}, zaubere {19434} vor und leg {1978} im Heranlaufen. Am Gegner sofort eine Falle und sie immer neu legen, sobald sie bereit ist. Dann {2973}, {1495} und {1317257}, wann immer sie bereit sind; mit dem passenden Talent auch zwei Falken. {1495} braucht einen Auslöser – eigenes Ausweichen oder ein markiertes Ziel –, deshalb ist {1130} hier Pflicht.",
              "Apply {1130}, pre-cast {19434} and put {1978} up while running in. At the enemy drop a trap at once and replace it whenever it is ready. Then {2973}, {1495} and {1317257} whenever they are ready; with the right talent keep two hawks as well. {1495} needs a trigger – your own dodge or a marked target – which is why {1130} is mandatory here."),
      note = T("{2973} trifft mit dem nächsten Schlag und leuchtet deshalb nur nebenher. Ob du die passende Aufspür-Art aktiv hast, kann ezCombat nicht prüfen. Der Wowhead-Guide führt den Wechsel zwischen Fern- und Nahkampf noch als unfertig.",
               "{2973} lands with your next swing, so it only glows on the side. ezCombat can't check whether the matching tracking is active. The Wowhead guide still lists ranged/melee weaving as unfinished."),
      counters = HAWKS,
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------
        { id = 13161, kind = "longbuff", when = "buff", need = { noaura = { id = TRAVEL } },
          text = T("Für den Nahkampf vor dem Kampf einschalten.", "Switch on before combat for melee.") },    -- Aspekt des Wildtiers / Aspect of the Beast
        { id = 13161, key = "prepare:aspect", kind = "prepare", when = "buff", need = { target = true, aura = { id = TRAVEL } },
          text = T("Du reist noch: vor dem Angriff umschalten.", "Still travelling: swap before you attack.") },    -- Aspekt des Wildtiers / Aspect of the Beast
        { id = 13165, kind = "longbuff", when = "buff", need = { unknown = 13161, noaura = { id = TRAVEL } },
          text = T("Solange {13161} fehlt: dieser Aspekt.", "Until you learn {13161}: this aspect.") },    -- Aspekt des Falken / Aspect of the Hawk
        { id = 1299346, key = "longbuff:19506", kind = "longbuff", when = "buff",
          text = T("Falls gelernt: vor dem Kampf auffrischen.", "If learned: refresh before combat.") },    -- Aura des Volltreffers / Trueshot Aura
        { id = 883, kind = "prepare", when = "pet",
          text = T("Kein Begleiter da: rufen (ist er tot: {982}).", "No pet out: call it (if dead: {982}).") },    -- Tier rufen / Call Pet
        { id = 1130, kind = "prepare", when = "dot", mine = false, refresh = "missing", need = { target = true },
          text = T("Vor dem Angriff aufs Ziel; es löst auch {1495} aus.", "On the target before you attack; it also triggers {1495}.") },    -- Mal des Jägers / Hunter's Mark
        -- Im Kampf (Reihenfolge = Rang). Das Mal steht vor der Eröffnung: erst markieren, dann vorzaubern. ----
        { id = 1130, key = "maintain:mark", kind = "maintain", when = "dot", mine = false, refresh = "missing",
          text = T("Fehlt es auf dem Ziel: setzen.", "Missing on the target: apply it.") },    -- Mal des Jägers / Hunter's Mark
        -- Eröffnung ------------------------------------------------------------------------------------------
        { id = 19434, kind = "opener", when = "ready", once = "target", need = { combat = false, moving = false, outrange = 2973 },
          text = T("Aus der Ferne vorzaubern, dann hineinlaufen.", "Pre-cast from range, then run in.") },    -- Gezielter Schuss / Aimed Shot
        -- Im Kampf, weiter -----------------------------------------------------------------------------------
        { id = 1978, kind = "maintain", when = "dot", refresh = "missing", need = { outrange = 2973 },
          text = T("Im Heranlaufen; erst nach Ablauf erneuern.", "While running in; renew only after it ends.") },    -- Schlangenbiss / Serpent Sting
        { id = 3045, kind = "cooldown", burst = true, when = "ready",
          text = T("Mit allen anderen Abklingzeiten; beschleunigt auch Schläge.", "With all other cooldowns; speeds up melee swings too.") },    -- Schnellfeuer / Rapid Fire
        { id = 13813, kind = "aoe", when = "ready", need = { inrange = 2973 },
          text = T("Mehrere Gegner bei dir: statt {13795} legen.", "Several enemies next to you: place it instead of {13795}.") },    -- Sprengfalle / Explosive Trap
        { id = 13795, kind = "maintain", when = "ready", need = { inrange = 2973, aoe = false },
          text = T("Am Gegner sofort legen und immer wieder erneuern.", "Place it at the enemy at once and keep replacing it.") },    -- Feuerbrandfalle / Immolation Trap
        { id = 1293241, kind = "priority", when = "ready", need = { counter = { name = "hawks", max = 1 } },
          text = T("Falls geskillt: sobald weniger als zwei Falken fliegen.", "If talented: whenever fewer than two hawks are out.") },    -- Falke beschwören / Summon Hawk
        { id = 2973, kind = "priority", when = "ready", side = true, need = { inrange = 2973, queued = false },
          text = T("Immer für den nächsten Schlag vormerken.", "Always queue it for your next swing.") },    -- Raptorstoß / Raptor Strike
        { id = 1495, kind = "priority", when = "reactive", need = { inrange = 2973 },
          text = T("Sobald ausgelöst (Ausweichen oder markiertes Ziel).", "Whenever it is triggered (dodge or marked target).") },    -- Mungobiss / Mongoose Bite
        { id = 1317257, kind = "priority", when = "ready", need = { inrange = 2973 },
          text = T("Sobald bereit.", "Whenever it is ready.") },    -- Streichertritt / Strider Kick
        -- Situativ -------------------------------------------------------------------------------------------
        { id = 1494, kind = "situational", when = "manual",
          text = T("Mit dem Talent: die zum Zieltyp passende Art aufspüren.", "With the talent: track the kind that matches your target.") },    -- Wildtiere aufspüren / Track Beasts
        { id = 19306, kind = "situational", when = "manual",
          text = T("Nachdem du pariert hast.", "After you parry.") },    -- Gegenangriff / Counterattack
        { id = 2974, kind = "situational", when = "manual",
          text = T("Verlangsamt, wenn der Gegner weglaufen will.", "Slows an enemy that tries to get away.") },    -- Zurechtstutzen / Wing Clip
        { id = 5384, kind = "situational", when = "manual",
          text = T("Notfall: Bedrohung loswerden.", "Emergency: drop your threat.") },    -- Totstellen / Feign Death
      } },
    { key = "survival_ranged", tree = 3, name = T("Überleben (Fernkampf)", "Survival (ranged)"),
      source = "https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-rotation-cooldowns-abilities",
      sources = { "https://www.icy-veins.com/wow-forever/survival-hunter-leveling",
          "https://www.icy-veins.com/wow-forever/survival-hunter-melee-dps-pve-guide" },
      how = T("Die Spielweise aus der Ferne, auch zum Leveln, bis der Nahkampf-Ausbau steht: {1978} halten und erst nach Ablauf erneuern, {19434} und {3044}, sobald sie bereit sind. Kommt der Gegner an dich heran, schlag mit {2973}, {1495} und {1317257} zu und geh danach wieder auf Abstand. Beim Leveln {3044} nur mit Mana übrig.",
              "The ranged playstyle, also for levelling until your melee build is complete: keep {1978} up and renew it only after it ends, {19434} and {3044} whenever they are ready. When the enemy reaches you, strike with {2973}, {1495} and {1317257}, then get back to range. While levelling use {3044} only with mana to spare."),
      note = T("Icy Veins widerspricht sich bei {19434} beim Leveln (einmal „immer nutzen“, einmal „oft weglassen“). Wie lange der Gegner noch lebt, sieht ezCombat nicht: Bei fast toten Gegnern lohnt {1978} nicht mehr.",
               "Icy Veins contradicts itself on {19434} while levelling (“always use” versus “often skipped”). ezCombat can't see how long the enemy will live: {1978} isn't worth it on nearly dead enemies."),
      steps = {
        -- Vor dem Kampf --------------------------------------------------------------------------------------
        { id = 13165, kind = "longbuff", when = "buff", need = { noaura = { id = TRAVEL } },
          text = T("Vor dem Kampf einschalten; bleibt bis zum Wechsel.", "Switch on before combat; stays until you swap.") },    -- Aspekt des Falken / Aspect of the Hawk
        { id = 13165, key = "prepare:aspect", kind = "prepare", when = "buff", need = { target = true, aura = { id = TRAVEL } },
          text = T("Du reist noch: vor dem Angriff umschalten.", "Still travelling: swap before you attack.") },    -- Aspekt des Falken / Aspect of the Hawk
        { id = 1299346, key = "longbuff:19506", kind = "longbuff", when = "buff",
          text = T("Falls gelernt: vor dem Kampf auffrischen.", "If learned: refresh before combat.") },    -- Aura des Volltreffers / Trueshot Aura
        { id = 883, kind = "prepare", when = "pet",
          text = T("Kein Begleiter da: rufen (ist er tot: {982}).", "No pet out: call it (if dead: {982}).") },    -- Tier rufen / Call Pet
        { id = 1130, kind = "prepare", when = "dot", mine = false, refresh = "missing", need = { target = true },
          text = T("Vor dem Angriff aufs Ziel.", "On the target before you attack.") },    -- Mal des Jägers / Hunter's Mark
        -- Im Kampf (Reihenfolge = Rang) ----------------------------------------------------------------------
        { id = 1130, key = "maintain:mark", kind = "maintain", when = "dot", mine = false, refresh = "missing",
          text = T("Fehlt es auf dem Ziel: setzen.", "Missing on the target: apply it.") },    -- Mal des Jägers / Hunter's Mark
        { id = 3045, kind = "cooldown", burst = true, when = "ready",
          text = T("Mit Schmuck und Volksfähigkeit zusammen zünden.", "Fire it together with trinkets and your racial.") },    -- Schnellfeuer / Rapid Fire
        { id = 1495, kind = "priority", when = "reactive", need = { inrange = 2973 },
          text = T("Gegner an dir und ausgelöst: sofort.", "Enemy on you and triggered: at once.") },    -- Mungobiss / Mongoose Bite
        { id = 1317257, kind = "priority", when = "ready", need = { inrange = 2973 },
          text = T("Gegner an dir: treten und mit dem Tempo auf Abstand.", "Enemy on you: kick, then use the speed to get to range.") },    -- Streichertritt / Strider Kick
        { id = 13813, kind = "aoe", when = "ready", need = { inrange = 2973 },
          text = T("Mehrere Gegner bei dir: legen, sobald bereit.", "Several enemies next to you: place it whenever ready.") },    -- Sprengfalle / Explosive Trap
        { id = 2973, kind = "phase", when = "ready", side = true, need = { inrange = 2973, queued = false },
          text = T("Vormerken, wenn der Gegner an dir steht.", "Queue it when the enemy is on top of you.") },    -- Raptorstoß / Raptor Strike
        { id = 1978, kind = "maintain", when = "dot", refresh = "missing", need = { outrange = 2973 },
          text = T("Halten; erst nach Ablauf erneuern.", "Keep it up; renew only after it ends.") },    -- Schlangenbiss / Serpent Sting
        { id = 2643, kind = "aoe", when = "ready", need = { outrange = 2973 },
          text = T("Bei mehreren Gegnern statt {19434}.", "With several enemies instead of {19434}.") },    -- Mehrfachschuss / Multi-Shot
        { id = 19434, kind = "priority", when = "ready", need = { moving = false, outrange = 2973 },
          text = T("Sobald bereit; dafür stehen bleiben.", "Whenever ready; stand still for it.") },    -- Gezielter Schuss / Aimed Shot
        { id = 3044, kind = "priority", when = "ready", need = { leveling = false, outrange = 2973 },
          text = T("Sobald bereit.", "Whenever it is ready.") },    -- Arkaner Schuss / Arcane Shot
        -- 50: Annahme für „Mana übrig“ (die Quelle nennt keine Zahl)
        { id = 3044, key = "level:arcane", kind = "priority", when = "ready", need = { leveling = true, mana = { min = 50 }, outrange = 2973 },
          text = T("Beim Leveln nur, wenn Mana übrig ist.", "While levelling only with mana to spare.") },    -- Arkaner Schuss / Arcane Shot
        { id = 1510, kind = "aoe", when = "ready", hold = true, need = { moving = false, outrange = 2973 },
          text = T("Lückenfüller bei vielen Gegnern; bis zum Ende kanalisieren.", "Gap filler on many enemies; let the channel finish.") },    -- Salve / Volley
        { id = 75, kind = "filler", when = "autorepeat", need = { outrange = 2973 },
          text = T("Läuft er nicht: einschalten und stehen bleiben.", "Not running: start it and stand still.") },    -- Automatischer Schuss / Auto Shot
        -- Situativ -------------------------------------------------------------------------------------------
        { id = 1494, kind = "situational", when = "manual",
          text = T("Mit dem Talent: die zum Zieltyp passende Art aufspüren.", "With the talent: track the kind that matches your target.") },    -- Wildtiere aufspüren / Track Beasts
        { id = 2974, kind = "situational", when = "manual",
          text = T("Verschafft dir Abstand vom Gegner.", "Buys you distance from the enemy.") },    -- Zurechtstutzen / Wing Clip
        { id = 13809, kind = "situational", when = "manual",
          text = T("Verlangsamt alles, was dir nachläuft.", "Slows everything that chases you.") },    -- Frostfalle / Frost Trap
        { id = 5384, kind = "situational", when = "manual",
          text = T("Notfall: Bedrohung loswerden.", "Emergency: drop your threat.") },    -- Totstellen / Feign Death
      } },
})
