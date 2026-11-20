local _, ns = ...
local Core = ezCore

--[[
    Entdecker-Datenbank: Weiterleitungen der alten Leser und Schreiber (Abweichung 9 des Entwurfs
    docs/archiv/entwurf-entdecker-datenbank.md; Tabelle „Weiterleitungen: woher jedes Rückgabefeld kommt“).

    Mit Träger ezWorld (gespeichert) und nach der Übernahme eines Altspeichers (Discovery.Moved(speicher), Merker in
    ezWorldDB.meta.jobs.adopt1.done) lesen und schreiben die alten Schnittstellen nur noch die neuen Tabellen – es gibt
    nie zwei Schreiber. Name und Rückgabeform bleiben (Leitlinie 8). Ohne Träger arbeiten sie wie bisher auf ezCoreDB
    (Rückfall: nichts geht verloren, solange die Verknüpfung fehlt). Die Altspeicher bleiben liegen (Frage S6).

      Speicher   alte Schnittstelle                         neue Quelle
      npcs       Npcs.Get/List/Find/Where/Count/Forget/Learn npc (Rollen, Seite, tr, tk), spot (Art npc), text
                                                            (npc, npcTitle, where) – Discovery.NpcEntries
      trainer    Spells.Trainer/Available/Upcoming/TrainerSeen, offer[c:<Klasse> | pet:<Klasse>] – Discovery.TrainerStore
                 Spells.ScanTrainer
      vendors    Knowledge.VendorSources, ScanVendorResources vendor (Umkehr-Index Ware » Händler) – Discovery.VendorList
      recipes    Knowledge.Recipe/RecipeFor/RecipesUsing …, recipe (Arbeitskopie in alter Form im Arbeitsspeicher,
                 Rezepte im Item-Wissen                     Discovery.RecipeView; geschrieben über Discovery.SyncRecipes)
      durations  Spells.NoteAura/AuraSeconds/BuffMinutes    spellObs.dur – Text-Schlüssel aus den Rängen des Buffs,
                                                            sonst weiter aus dem Altspeicher
      stages     Knowledge.SkillStages, NoteRecipe          recipeObs.stages (Recipes.lua)
      sources    Knowledge.RecipeSource, NoteRecipe         text[Sprache].recipeSrc (Recipes.lua)
    Die Hooks stehen in Npcs.lua, Spells.lua und Recipes.lua (je eine Zeile „Discovery.Moved“).
]]

local DB = Core.DB
local Keys = DB.Keys
local Discovery = Core.Discovery
local Num, Plain = Core.Num, Core.Plain

local function G(name) return rawget(_G, name) end

---------------------------------------------------------------------------
-- NPCs (Npcs.lua)
---------------------------------------------------------------------------

local FACTION = { A = "Alliance", H = "Horde" }

local function TrainerOf(row)
    local roles = type(row.roles) == "table" and row.roles or {}
    if not roles.trainer then return nil end
    if row.tr == 1 then return "class" elseif row.tr == 2 then return "profession" end
    local kind = Keys.OfferKind(row.tk)
    return kind == "pet" and "pet" or "other"
end

-- Jüngster Ort je NPC aus spot (Art npc), einmal je Stand der Tabelle
local placeCache, placeVer
local function NpcPlaces()
    if placeCache and placeVer == DB.Version("spot") then return placeCache end
    local out = {}
    DB.Scan("spot", function(list, _, _, path)
        if path[2] == "npc" and type(list) == "table" then
            for _, el in ipairs(list) do
                if type(el) == "table" and Num(el.xy) and Num(path[1]) and path[1] > 0 then
                    local best = out[path[3]]
                    if not best or (Num(el.t) or 0) > best.t then
                        local x, y = Keys.Unpack(el.xy)
                        out[path[3]] = { map = path[1], x = x, y = y, t = Num(el.t) or 0 }
                    end
                end
            end
        end
    end)
    placeCache, placeVer = out, DB.Version("spot")
    return out
end

local function NpcEntry(id, row, places)
    local roles = type(row.roles) == "table" and row.roles or nil
    if not (roles and (roles.trainer or roles.vendor or roles.repair)) then return nil end
    local name = DB.Text("npc", id)
    if type(name) ~= "string" or name == "" then return nil end
    local trainer = TrainerOf(row)
    local kind, who = Keys.OfferKind(row.tk)
    local seen = math.max(Num(roles.trainer) or 0, Num(roles.vendor) or 0, Num(roles.repair) or 0)
    local e = { name = name, title = DB.Text("npcTitle", id), trainer = trainer,
        vendor = (roles.vendor or roles.repair) and true or nil, repair = roles.repair and true or nil,
        class = (trainer == "class" and kind == "class") and who or nil, faction = FACTION[row.side],
        seen = seen > 0 and seen or Num(row.t) }
    local p = places[id]
    if p then e.map, e.x, e.y = p.map, p.x, p.y end
    e.zone = (e.map and Core.MapName and Core.MapName(e.map)) or DB.Text("where", id)
    return e
end

-- Einträge in der alten Form { [npcID] = { name, title, trainer, vendor, repair, class, faction, map, x, y, zone,
-- seen } } – Npcs.lua kopiert sie vor der Rückgabe. Einmal je Stand von npc, spot und text gebaut.
local entryCache, entryVer
function Discovery.NpcEntries()
    local ver = DB.Version("npc") .. ":" .. DB.Version("spot") .. ":" .. DB.Version("text")
    if entryCache and entryVer == ver then return entryCache end
    local places, out = NpcPlaces(), {}
    DB.Scan("npc", function(row, _, id)
        if Num(id) then out[id] = NpcEntry(id, row, places) end
    end)
    entryCache, entryVer = out, ver
    return out
end
Core.Listen("DB_READY", function() entryCache, placeCache = nil, nil end, "ezCore.DiscoveryLegacy")

-- Npcs.Learn: Rolle, Seite, Lehrer-Art, Ort und Namen in die Datenbank (der Ort zählt je Sitzung einmal). Eigene
-- Funktion: schreibt auch bei ausgeschaltetem Sammeln (DB.AsOwn).
local function LearnNpc(kind)
    if kind ~= "trainer" and kind ~= "vendor" then return nil end
    local id = Keys.Npc("npc")
    local name = Plain(Core.Call(G("UnitName"), "npc"))
    if not (id and type(name) == "string" and name ~= "") then return nil end
    local roles, extra = {}, {}
    if kind == "trainer" then
        roles[1] = "trainer"
        local N = Core.Npcs
        local tkind = N and N.TrainerKind and N.TrainerKind(N.Subtitle and N.Subtitle()) or "other"
        if tkind ~= "profession" and Discovery.IsPetTrainer() then tkind = "pet" end
        local who
        if tkind == "class" or tkind == "pet" then who = Core.PlayerClass() elseif tkind == "profession" then who = 0 end
        extra.tr = Discovery.TRAINER_TYPE[tkind] or 3
        extra.tk = Keys.Offer(tkind, who)
    else
        roles[1] = "vendor"
        if Core.Bool(Core.Call(G("CanMerchantRepair")), false) == true then roles[2] = "repair" end
    end
    Discovery.NoteNpc(id, roles, extra)
    Core.Fire("NPCS_CHANGED", id, kind)
    return id
end
function Discovery.LearnNpc(kind) return DB.AsOwn(LearnNpc, kind) end

local ROLES = { trainer = { "trainer" }, vendor = { "vendor", "repair" }, all = { "trainer", "vendor", "repair" } }

local function DropPlaces(id)
    for _, map in ipairs(DB.KeysOf("spot")) do
        if DB.Get("spot", map, "npc", id) then DB.Forget("spot", map, "npc", id) end
    end
end

-- Npcs.Forget: ein NPC (ID) fällt ganz weg; "trainer" bzw. "vendor" nimmt nur diese Rolle, nil alle Rollen. Bleibt
-- einem NPC keine Rolle, fallen auch seine Orte in spot (Art npc). → Anzahl betroffener NPCs
function Discovery.ForgetNpc(what)
    local n = 0
    if type(what) == "number" then
        if DB.Get("npc", what) then
            DB.Forget("npc", what)
            DropPlaces(what)
            n = 1
        end
    else
        local strip = ROLES[what or "all"]
        if not strip then return 0 end
        for _, id in ipairs(DB.KeysOf("npc")) do
            local row = DB.Get("npc", id)
            local roles = row and type(row.roles) == "table" and row.roles
            local hit = false
            for _, role in ipairs(strip) do if roles and roles[role] then hit = true end end
            if hit then
                local left = false
                DB.Change("npc", { id }, function(r)
                    local rr = type(r.roles) == "table" and r.roles or {}
                    for _, role in ipairs(strip) do rr[role] = nil end
                    if rr.trainer == nil then r.tr, r.tk = nil, nil end
                    left = next(rr) ~= nil
                    r.roles = left and rr or nil
                end)
                if not left then DropPlaces(id) end
                n = n + 1
            end
        end
    end
    if n > 0 then
        Core.Fire("NPCS_CHANGED", type(what) == "number" and what or nil, type(what) == "string" and what or nil)
    end
    return n
end

-- Npcs.SortPetTrainers: Lehrer der Art „other“ mit dem Titel eines Tierausbilders (Sprache des Clients) werden
-- Tierausbilder der Jäger (tk = pet:HUNTER, wie bei der Übernahme). → Zahl umsortierter NPCs
function Discovery.SortPetTrainers()
    local N, n = Core.Npcs, 0
    local other, pet = Keys.Offer("other"), Keys.Offer("pet", "HUNTER")
    for _, id in ipairs(DB.KeysOf("npc")) do
        local row = DB.Get("npc", id)
        if row and row.tk == other and N and N.IsPetTrainerTitle and N.IsPetTrainerTitle(DB.Text("npcTitle", id))
            and DB.Change("npc", { id }, function(r) r.tk = pet end) then
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Lehrer (Spells.lua): Sicht in der alten Form { list = { ["Name#Rang"] = { n, r, l, c, i, t } }, seen }
---------------------------------------------------------------------------

-- art der alten Speicher-Form: "MAGE" (Klassenlehrer) bzw. "HUNTER:PET" (Tierausbilder). Die alte Form stempelte
-- mit der PC-Uhr (time()), die Datenbank mit der Serveruhr (DB.Stamp): seen und t kommen darum auf die PC-Uhr
-- umgerechnet zurück (Core.Time.FromServer; Gesamtreview 18.11.2026, Gegenprüfung zu T16-NZ1) – sonst nannte der
-- Lehrer-Stand in ezMerchant bei falsch gehender PC-Uhr gleich nach dem Besuch „vor 2 Std.“.
function Discovery.TrainerStore(kind)
    if type(kind) ~= "string" then return nil end
    local class, suffix = kind:match("^(%u+)(.*)$")
    if not class or (suffix ~= "" and suffix ~= ":PET") then return nil end
    local art = Keys.Offer(suffix == ":PET" and "pet" or "class", class)
    local row = art and DB.Get("offer", art)
    if not row then return nil end
    local locale, list = Keys.Locale(), {}
    for key, s in pairs(type(row.svc) == "table" and row.svc or {}) do
        local name, rank
        if Num(key) then
            name, rank = Core.SpellName and Core.SpellName(key), Num(s.rank) or 0
        else
            local loc, n, r = Keys.OfferName(key)
            if loc == locale then name, rank = n, r end   -- Notschlüssel anderer Sprache: nicht in dieser Liste
        end
        if type(name) == "string" and name ~= "" and type(s) == "table" then
            local id = name .. "#" .. rank
            local have = list[id]
            if not have or (Core.Time.FromServer(Num(s.t)) or 0) >= (have.t or 0) then
                list[id] = { n = name, r = rank, l = Num(s.lvl) or 1, c = Num(s.pr) or 0, i = s.ic,
                    t = Core.Time.FromServer(Num(s.t)) }
            end
        end
    end
    return { list = list, seen = Core.Time.FromServer(Num(row.t)) }
end

---------------------------------------------------------------------------
-- Händler (Recipes.lua: Knowledge.VendorSources)
---------------------------------------------------------------------------

-- → { { npc, name, zone, price, stack, limited, seen, map, x, y } … } günstigste zuerst (alte Form)
function Discovery.VendorList(itemID)
    itemID = Num(itemID)
    local list = {}
    if not itemID then return list end
    local npcs = Core.Npcs
    for _, path in ipairs(DB.Index("vendor", "item", itemID)) do
        local key = path[1]
        local row = DB.Get("vendor", key)
        local w = row and type(row.w) == "table" and row.w[itemID]
        if type(w) == "table" and Num(w.pr) and w.pr > 0 then
            local npc = Num(key)
            local e = npc and npcs and npcs.Get and npcs.Get(npc) or nil
            list[#list + 1] = { npc = npc, name = DB.Text("npc", key) or (e and e.name), zone = (e and e.zone) or DB.Text("where", key),
                price = w.pr, stack = Num(w.per) or 1, limited = Num(w.lim) and true or nil, seen = Num(w.t),
                map = e and e.map or nil, x = e and e.x or nil, y = e and e.y or nil }
        end
    end
    table.sort(list, function(a, b) return (a.price or 0) / math.max(1, a.stack) < (b.price or 0) / math.max(1, b.stack) end)
    return list
end

---------------------------------------------------------------------------
-- Gemessene Dauern (Spells.lua: NoteAura, AuraSeconds)
---------------------------------------------------------------------------

local durNoted, durCache, durVer = {}, {}, nil

function Discovery.DurationOf(key)
    if DB.Version("spellObs") ~= durVer then durCache, durVer = {}, DB.Version("spellObs") end
    local c = durCache[key]
    if c ~= nil then return c or nil end
    local v
    if type(key) == "number" then
        local row = DB.Get("spellObs", key)
        local d = row and type(row.dur) == "table" and row.dur
        if d and Num(d.cnt) and d.cnt > 0 and Num(d.sum) then v = math.floor(d.sum / d.cnt + 0.5) end
    elseif type(key) == "string" then
        -- Buff-Kürzel: die Dauer eines seiner Ränge (wie früher nur bei Klassen-Buffs), sonst der Altspeicher
        local S = Core.Spells
        local b = S and S.BUFFS and S.BUFFS[key]
        if b and b.class then
            for _, id in ipairs(b.spells or {}) do v = v or Discovery.DurationOf(id) end
        end
        if not v then
            local old = Core.db and Core.db.spells and Core.db.spells.durations
            v = type(old) == "table" and Num(old[key]) or nil
        end
    end
    durCache[key] = v or false
    return v
end

-- Lese-Sicht für Spells.AuraSeconds: store[id oder Kürzel] → Sekunden (nur lesen)
local durView = setmetatable({}, { __index = function(_, key) return Discovery.DurationOf(key) end,
    __newindex = function() end })
function Discovery.DurationStore()
    if not Discovery.Moved("durations") then return nil end
    return durView
end

-- Spells.NoteAura: je Sitzung, Zauber und Dauer einmal als Beobachtung (nie aus dem Kampf; Entwurf, Abschnitt 11)
function Discovery.NoteDuration(id, seconds)
    if not Discovery.Moved("durations") then return false end
    if Core.InCombat() or not (Num(id) and Num(seconds)) then return true end
    if durNoted[id] == seconds then return true end
    durNoted[id] = seconds
    DB.AsOwn(DB.Observe, "spellObs", id, { dur = { sum = seconds, cnt = 1 } })
    return true
end

---------------------------------------------------------------------------
-- Rezepte (Knowledge.lua, Recipes.lua): Arbeitskopie in alter Form
---------------------------------------------------------------------------
-- Das Item-Wissen arbeitet auf { recipes, reagents, created } in ezCoreDB.knowledge. Nach dem Umzug bekommt es eine
-- Sicht: recipes/reagents/created im Arbeitsspeicher (aus held.recipe gebaut), alles andere (names, items, charProfs;
-- known, stages und sources nur noch als Altspeicher – Recipes.lua) liest und schreibt sie weiter in ezCoreDB.knowledge. Neue oder geänderte Rezepte gehen nach
-- jedem Lesen des Berufefensters über DB.Put nach held.recipe (Discovery.SyncRecipes) – ezCoreDB.knowledge.recipes
-- wird nicht mehr geschrieben und bleibt als Sicherung liegen.

local view, synced, viewVer, viewReal
local usingView = false

local function BuildView(real)
    local v = setmetatable({ recipes = {}, reagents = {}, created = {} }, { __index = real, __newindex = real })
    synced = {}
    DB.Scan("recipe", function(row, _, key)
        local rec = Discovery.RecipeOld(row, key)
        if rec then
            v.recipes[key], synced[key] = rec, rec
            for id in pairs(rec.r) do
                v.reagents[id] = v.reagents[id] or {}
                v.reagents[id][key] = true
            end
            if rec.o then v.created[rec.o] = key end
        end
    end)
    view, viewVer, viewReal = v, DB.Version("recipe"), real
    -- das Item-Wissen arbeitet auf der neuen Sicht (Knowledge.Init baut die Fakten neu)
    local K = Core.Knowledge
    if K and K.Init then
        usingView = true
        K.Init(v)
    end
    return v
end

function Discovery.RecipeView()
    local real = Core.db and Core.db.knowledge
    if type(real) ~= "table" or not Discovery.Moved("recipes") then return nil end
    if view and viewReal == real and viewVer == DB.Version("recipe") then return view end
    return BuildView(real)
end

function Discovery.SyncRecipes()
    if not (view and usingView and Discovery.Moved("recipes")) then return 0 end
    local n = 0
    for key, rec in pairs(view.recipes) do
        if synced[key] ~= rec and type(rec) == "table" then
            local k = Keys.Recipe(key)
            local row = k and Discovery.RecipeRow(rec)
            -- als erledigt gemerkt nur, was die Datenbank angenommen hat (sonst beim nächsten Lesen wieder)
            if row and DB.AsOwn(DB.Put, "recipe", k, row) then
                if type(rec.n) == "string" and rec.n ~= "" then DB.AsOwn(DB.SetText, "recipe", k, rec.n) end
                n = n + 1
                synced[key] = rec
            elseif not row then
                synced[key] = rec
            end
        end
    end
    viewVer = DB.Version("recipe")
    return n
end

-- Das Item-Wissen auf die passende Ablage stellen: nach DB_READY, beim Anmelden (nach Knowledge.lua) und nach der
-- Übernahme der Rezepte. Ohne Umzug bleibt es, wie es ist; fällt der Träger weg, zurück auf ezCoreDB.knowledge.
local function UseRecipeStore()
    if Discovery.RecipeView() then return end
    if usingView then
        usingView, view = false, nil
        local K = Core.Knowledge
        local real = Core.db and Core.db.knowledge
        if K and K.Init and type(real) == "table" then K.Init(real) end
    end
end
Discovery.UseRecipeStore = UseRecipeStore

local K = Core.Knowledge
if K and K.LearnFromTradeSkill then
    local learn = K.LearnFromTradeSkill
    function K.LearnFromTradeSkill(...)
        local n = learn(...)
        Core.Try(nil, "Discovery.SyncRecipes", Discovery.SyncRecipes)
        return n
    end
end

Core.Listen("DB_READY", function() view = nil; UseRecipeStore() end, "ezCore.DiscoveryLegacy")
Core.Listen("DB_JOB_DONE", function(job) if job == "adopt1:recipes" then UseRecipeStore() end end, "ezCore.DiscoveryLegacy")
ns.On("PLAYER_LOGIN", function() Core.Try(nil, "Discovery.UseRecipeStore", UseRecipeStore) end)
