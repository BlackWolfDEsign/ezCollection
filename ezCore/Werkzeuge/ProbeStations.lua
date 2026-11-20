local ADDON, ns = ...
local Core = ezCore
local L = Core.L
local Probe = Core.Probe

--[[
    Stationen der Daten-Probe (/ez probe, Probe.lua): WAS gefragt wird. Die Kennungen (A1 … N2, X2 … X4) sind die aus
    docs/datenprobe.md, Abschnitt 6 und 7, und aus „Offene Fragen an den Client“ in docs/datenkatalog-client.md.

    Jede Probe ist eine Funktion fn(run). Sie fragt über
      run:Q(kennung, "Pfad.Zur.Funktion", argumente …)   Abfrage mit Eintrag (pcall, alle Rückgaben, „fehlt“)
      run:Call("Pfad", …)                                 Abfrage ohne Eintrag (nur um den Weg zu bestimmen)
      run:Val(kennung, "Enum.ItemQuality")                globaler Wert          run:Has(kennung, "Name")   nur die Art
      run:Note(kennung, "Bezeichnung", werte …)           selbst Gezähltes
      run:Tag("Marke"), run:With({ ret, fields, text })   Marke bzw. Maskier-Regeln für die nächste Abfrage
      run:Step(fn), run:After(sekunden, fn), run:Wait(kennung, "EREIGNIS", fn)   Scheiben, Pause, Antwort des Servers
    Rückgaben sind roh und können geheim sein: vor jeder Verwendung über r:Num(i), r:Str(i), r:Tab(i), r:Field(name)
    bzw. Probe.Field(tabelle, name) lesen – die liefern nil statt eines geheimen Werts.
    Nichts hier schreibt: keine Käufe, kein Senden, kein Lernen, kein Zielwechsel, keine Filter. Ausnahmen sind die
    Sonderproben am Ende (X2, X3, X4, X6, X7, X8, F7) – Entwicklerwerkzeuge: jede nur auf eigenen Knopf mit Rückfrage
    und nur mit dem Entwicklerschalter (Core.Debug.Developer, /ez debug entwickler; Gesamtreview 18.11.2026,
    Entscheidung 1). Ohne ihn sind ihre Knöpfe ausgeblendet, Befehl und Hinweis „noch offen“ nennen sie nicht.
]]

local P = Probe.probes
local Num, Str, Tab, Field = Probe.Num, Probe.Str, Probe.Tab, Probe.Field

---------------------------------------------------------------------------
-- Helfer
---------------------------------------------------------------------------

-- Liste von Abfragen: "Pfad" oder { "Pfad", argumente … }
local function Many(run, id, list)
    for _, call in ipairs(list) do
        if type(call) == "string" then
            run:Q(id, call)
        else
            run:Q(id, call[1], unpack(call, 2, #call))
        end
    end
end

local function EnumValue(name, key) return Probe.Resolve("Enum." .. name .. "." .. key) end

local function MapID(run) return run:Call("C_Map.GetBestMapForUnit", "player"):Num() end

-- Belegte Taschenplätze (nicht festgehalten): { { bag, slot, id } … }
local function BagItems(run, max)
    local list = {}
    for bag = 0, 5 do
        local slots = run:Call("C_Container.GetContainerNumSlots", bag):Num() or 0
        for slot = 1, slots do
            local id = run:Call("C_Container.GetContainerItemID", bag, slot):Num()
            if id then
                list[#list + 1] = { bag = bag, slot = slot, id = id }
                if #list >= max then return list end
            end
        end
    end
    return list
end

-- Angelegte Stücke: { { slot, id, link } … }
local function Equipped(run, max)
    local list = {}
    for slot = 1, 19 do
        local id = run:Call("GetInventoryItemID", "player", slot):Num()
        if id then
            list[#list + 1] = { slot = slot, id = id, link = run:Call("GetInventoryItemLink", "player", slot):Str() }
            if #list >= (max or 19) then break end
        end
    end
    return list
end

-- Zahl der Felder im Gegenstands-Link („item:1:2:…“)
local function LinkFields(link)
    local body = type(link) == "string" and link:match("|H(item:[^|]*)|h") or nil
    if not body then return nil end
    local n = 1
    for _ in body:gmatch(":") do n = n + 1 end
    return n, body
end

-- Zauberbuch einmal je Lauf zählen: gelernter und künftiger Zauber, Zahlen je Art
local function OwnSpells(run)
    if run.spells then return run.spells end
    local FUTURE = EnumValue("SpellBookItemType", "FutureSpell") or 2
    local SPELL = EnumValue("SpellBookItemType", "Spell") or 1
    local bank = EnumValue("SpellBookSpellBank", "Player") or 0
    local lines = run:Call("C_SpellBook.GetNumSpellBookSkillLines"):Num() or 0
    local s = { lines = lines, items = 0, future = 0, spells = 0, offSpec = 0, other = 0, bank = bank, ids = {} }
    for line = 1, math.min(lines, 12) do
        local info = run:Call("C_SpellBook.GetSpellBookSkillLineInfo", line):Tab()
        local offset, count = Num(Field(info, "itemIndexOffset")) or 0, Num(Field(info, "numSpellBookItems")) or 0
        for i = offset + 1, offset + math.min(count, 300) do
            local item = run:Call("C_SpellBook.GetSpellBookItemInfo", i, bank):Tab()
            local kind = Field(item, "itemType")
            local id = Num(Field(item, "actionID")) or Num(Field(item, "spellID"))
            s.items = s.items + 1
            if Field(item, "isOffSpec") == true then s.offSpec = s.offSpec + 1 end
            if kind == FUTURE then
                s.future = s.future + 1
                s.futureID, s.futureIndex = s.futureID or id, s.futureIndex or i
            elseif kind == SPELL then
                s.spells = s.spells + 1
                if Field(item, "isPassive") ~= true then
                    s.learnedID, s.learnedIndex = s.learnedID or id, s.learnedIndex or i
                    if id and #s.ids < 120 then s.ids[#s.ids + 1] = id end
                end
            else
                s.other = s.other + 1
            end
        end
    end
    run.spells = s
    return s
end

-- Wie privat ist die Einheit? "player" (Spieler), "pet" (Begleiter: der eigene, von einem Spieler gesteuert, oder
-- nicht entscheidbar, weil die Antwort gesperrt ist), nil (NPC oder niemand).
local function UnitPrivacy(run, unit)
    local isPlayer = run:Call("UnitIsPlayer", unit)
    if isPlayer:True() then return "player" end
    if unit == "pet" or run:Call("UnitPlayerControlled", unit):True() or run:Call("UnitIsOtherPlayersPet", unit):True() then
        return "pet"
    end
    if isPlayer.ok and Core.IsSecret(isPlayer[1]) then return "pet" end
    return nil
end

-- Gehört der Tooltip einem Spieler oder dessen Begleiter? Die GUID im Kopf nennt die Art; eine Zeile „Begleiter von …“
-- (UnitOwner) nennt den Besitzer. → privat, nachweislich NPC oder Objekt
local function TooltipPrivacy(data, lines)
    local guid = Str(Field(data, "guid"))
    local kind = guid and guid:match("^([^%-]+)") or nil
    if kind == "Player" or kind == "Pet" then return true, false end
    local owner = EnumValue("TooltipDataLineType", "UnitOwner")
    if owner ~= nil and lines then
        for i = 1, #lines do
            if Num(Field(Tab(lines[i]), "type")) == owner then return true, false end
        end
    end
    return false, kind ~= nil and Probe.NPC_GUID[kind] == true
end

-- Tooltip als Daten: Kopf (ohne Zeilen) und je Zeilenart EINE Zeile mit allen Feldern, dazu wie oft die Art vorkam.
-- opts: Maskier-Regeln. Bei Spielern und ihren Begleitern bleibt kein Text lesbar (opts.text = true) – das entscheidet
-- der Tooltip auch selbst (TooltipPrivacy). opts.cursor: Tooltip unter der Maus – dort kann alles stehen (fremder
-- Spieler samt Gilde, Begleiter samt Besitzer, Leichnam eines Spielers): Text bleibt nur, wenn der Tooltip nachweislich
-- einem Objekt (Erzader, Kraut, Truhe) oder einem NPC gehört.
local function Tooltip(run, id, opts, path, ...)
    local n = select("#", ...)
    local arg = Probe.ArgText(n, { ... })
    local r = run:Call(path, ...)
    local data = r:Tab()
    if not data then
        if opts and opts.cursor then opts = { text = true } end
        run:With(opts):Record(id, path, arg, r)
        return nil
    end
    local head, lines = {}, nil
    for k, v in pairs(data) do
        if k == "lines" then lines = v else head[k] = v end
    end
    lines = Tab(lines)
    local private, npc = TooltipPrivacy(data, lines)
    if opts and opts.cursor then
        local kind = Num(Field(data, "type"))
        local object, unit = EnumValue("TooltipDataType", "Object"), EnumValue("TooltipDataType", "Unit")
        local safe = not private and UnitPrivacy(run, "mouseover") == nil
            and ((object ~= nil and kind == object) or (unit ~= nil and kind == unit and npc))
        opts = not safe and { text = true } or nil
    elseif private and not (opts and opts.text) then
        opts = { text = true }
    end
    run:With(opts):Tag(arg):Note(id, path .. " Kopf", head)
    if not lines then return data end
    local first, order, count = {}, {}, {}
    for i = 1, #lines do
        local line = Tab(lines[i])
        local key = line and (Num(Field(line, "type")) or "?") or "secret"
        count[key] = (count[key] or 0) + 1
        if first[key] == nil then
            first[key] = line or false
            order[#order + 1] = key
        end
    end
    for _, key in ipairs(order) do
        local line = first[key]
        if line then
            run:With(opts):Tag(("line.type=%s x%d"):format(tostring(key), count[key])):Note(id, path .. " Zeile", line)
        else
            run:Tag(("x%d"):format(count[key])):Note(id, path .. " Zeile geheim", nil)
        end
    end
    return data
end

-- Regel für den Namen einer Einheit: Spieler als Pseudonym (samt Realm), Begleiter nur als Länge (der Name ist vom
-- Spieler vergeben), NPC im Klartext. Die Regel hängt an der Abfrage – nicht daran, ob der Name schon angemeldet ist.
local function NameRule(run, unit)
    local privacy = UnitPrivacy(run, unit)
    if privacy == "player" then return { ret = { [1] = "player", [2] = "realm" } } end
    if privacy == "pet" then return { ret = { [1] = true } } end
    return nil
end

-- Wer ist die Einheit? (F1, G2, M2, B1, C1) – eine geheime GUID wird nie weitergereicht.
local function UnitIdentity(run, id, unit)
    run:Q(id, "UnitExists", unit)
    run:Q(id, "C_Secrets.ShouldUnitIdentityBeSecret", unit)
    local rule = NameRule(run, unit)
    local guid = run:Q(id, "UnitGUID", unit):Str()
    if guid then
        local parts = 0
        for _ in guid:gmatch("[^%-]+") do parts = parts + 1 end
        run:Note(id, "GUID-Aufbau " .. unit, guid:match("^([^%-]+)"), parts)
        run:Q(id, "C_CreatureInfo.GetCreatureID", guid)
        run:Q(id, "ezCore.NpcID", guid)
        run:With(rule):Q(id, "UnitNameFromGUID", guid)
    end
    run:Q(id, "UnitCreatureID", unit)
    run:With(rule):Q(id, "UnitName", unit)
    Many(run, id, { { "UnitIsPlayer", unit }, { "UnitIsPlayerControlledOrGroupMember", unit } })
    return guid
end

local function UnitKind(run, id, unit)
    Many(run, id, { { "UnitLevel", unit }, { "UnitEffectiveLevel", unit }, { "UnitClassification", unit },
        { "UnitCreatureType", unit }, { "UnitCreatureFamily", unit }, { "UnitIsBossMob", unit }, { "UnitIsQuestBoss", unit },
        { "UnitIsTrivial", unit }, { "UnitIsMinion", unit }, { "UnitIsOtherPlayersPet", unit }, { "UnitPlayerControlled", unit },
        { "UnitIsGameObject", unit }, { "UnitSex", unit }, { "UnitSexBase", unit },
        { "UnitFactionGroup", unit }, { "UnitReaction", unit, "player" }, { "UnitReaction", "player", unit },
        { "UnitSelectionType", unit }, { "UnitCanAttack", "player", unit }, { "UnitIsFriend", "player", unit } })
end

-- Tooltip einer Einheit: bei Spielern und Begleitern von Spielern bleibt kein Text lesbar.
local function UnitTooltip(run, id, unit)
    return Tooltip(run, id, UnitPrivacy(run, unit) and { text = true } or nil, "C_TooltipInfo.GetUnit", unit)
end

local function NpcProbe(run, id, unit)
    UnitIdentity(run, id, unit)
    Many(run, id, { { "UnitLevel", unit }, { "UnitClassification", unit }, { "UnitCreatureType", unit },
        { "UnitFactionGroup", unit }, { "UnitReaction", unit, "player" } })
    UnitTooltip(run, id, unit)
    local map = MapID(run)
    if map then run:Q(id, "C_Map.GetPlayerMapPosition", map, "player") end
end

local function Restrictions(run, id)
    for i = 0, 5 do run:Q(id, "C_RestrictedActions.GetAddOnRestrictionState", i) end
    Many(run, id, { "InCombatLockdown", "C_Secrets.HasSecretRestrictions", { "C_Secrets.ShouldAurasBeSecret" },
        { "C_Secrets.ShouldUnitStatsBeSecret", "player" }, "C_Secrets.ShouldCooldownsBeSecret" })
end

---------------------------------------------------------------------------
-- A – allein, ohne offenes Fenster
---------------------------------------------------------------------------

P.A1 = function(run)
    Many(run, "A1", { "GetBuildInfo", "GetLocale", "GetCurrentRegion", "GetCurrentRegionName", "GetRealmName",
        "GetNormalizedRealmName", "GetRealmID", "GetNativeRealmID", "GetExpansionLevel", "GetServerExpansionLevel",
        "GetClassicExpansionLevel", "C_GameRules.GetActiveGameMode", "C_GameRules.GetCurrentGameModeRecordID",
        "C_GameRules.IsHardcoreActive", "C_GameRules.IsSelfFoundAllowed", "C_GameRules.IsStandard",
        "C_GameRules.GetForeverExperiencePreset", "AreDangerousScriptsAllowed", "GetServerTime", "time", "GetTime",
        "GetGameTime", "C_DateAndTime.GetCurrentCalendarTime", "C_DateAndTime.GetSecondsUntilDailyReset",
        "C_DateAndTime.GetSecondsUntilWeeklyReset", "C_DateAndTime.GetServerTimeLocal", "C_DateAndTime.GetWeeklyResetStartTime",
        "C_DateAndTime.IsDayTime", "C_Weather.GetCurrentWeather", "C_Secrets.HasSecretRestrictions", "InCombatLockdown",
        "C_CombatLog.IsCombatLogRestricted", "C_ChatInfo.InChatMessagingLockdown",
        "C_ChatInfo.AreOutgoingAddonChatMessagesRestricted", "GetScriptBucketThrottleLimits" })
    run:Val("A1", "WOW_PROJECT_ID")
    run:Val("A1", "WOW_PROJECT_CAMELOT")
    for _, rule in ipairs({ "UserScriptsDisabled", "IngameCalendarDisabled", "IngameFriendsListDisabled", "MerchantFilterDisabled",
        "AchievementsPanelDisabled", "WorldMapTrackingPinDisabled" }) do
        local value = run:Val("A1", "Enum.GameRule." .. rule)
        if value ~= nil then run:Tag(rule):Q("A1", "C_GameRules.IsGameRuleActive", value) end
    end
    for i = 0, 5 do run:Q("A1", "C_RestrictedActions.GetAddOnRestrictionState", i) end
    for _, cvar in ipairs({ "loadDeprecationFallbacks", "showDungeonEntrancesOnMap", "ShowAllSpellRanks",
        "onlyShowCollectedItemsInJournal" }) do
        run:Q("A1", "C_CVar.GetCVarInfo", cvar)
    end
    -- Hin- und Rückweg der eingebauten Serialisierung mit einer kleinen Tabelle
    -- Nachprobe: je Rückweg festgehalten, ob das Ergebnis dem Ausgang GLEICHT (vorher nur „antwortet ohne Fehler“)
    local cbor = run:Q("A1", "C_EncodingUtil.SerializeCBOR", { a = 1, b = "x", c = { 1, 2 } }):Str()
    if cbor then
        local back = run:Q("A1", "C_EncodingUtil.DeserializeCBOR", cbor):Tab()
        local list = back and Tab(Field(back, "c"))
        run:Note("A1", "CBOR: Rückweg gleich dem Ausgang", back ~= nil and Field(back, "a") == 1 and Field(back, "b") == "x"
            and list ~= nil and Field(list, 1) == 1 and Field(list, 2) == 2)
        local packed = run:Q("A1", "C_EncodingUtil.CompressString", cbor):Str()
        if packed then
            local unpacked = run:Q("A1", "C_EncodingUtil.DecompressString", packed):Str()
            run:Note("A1", "Deflate: entpackt gleich dem Ausgang; Längen vorher, gepackt", unpacked == cbor, #cbor, #packed)
            local text = run:Q("A1", "C_EncodingUtil.EncodeBase64", packed):Str()
            if text then
                local decoded = run:Q("A1", "C_EncodingUtil.DecodeBase64", text):Str()
                run:Note("A1", "Base64: dekodiert gleich dem Ausgang; Länge des Texts", decoded == packed, #text)
            end
        end
    end
    Many(run, "A1", { { "C_AddOns.GetAddOnInfo", ADDON }, { "C_AddOns.IsAddOnLoadOnDemand", ADDON },
        { "C_AddOns.GetAddOnInterfaceVersion", ADDON } })
end

P.A2 = function(run)
    for _, name in ipairs({ "GetItemInfo", "GetItemInfoInstant", "GetItemStats", "GetItemSpell", "GetItemCount",
        "GetContainerItemInfo", "GetMerchantItemInfo", "QueryAuctionItems", "GetAuctionItemInfo", "GetNumTradeSkills",
        "GetTradeSkillInfo", "GetCraftInfo", "GetNumSkillLines", "IsPlayerSpell", "IsSpellKnown", "GetSpellInfo",
        "GetSpellBaseCooldown", "GetTalentInfo", "GetNumTalentTabs", "GetNumSpecGroups", "GetSpecializationSystem",
        "GetMacroSpell", "HasAction", "GetActionText", "GetActionCooldown", "SendChatMessage", "GetAddOnMetadata",
        "GetWeaponEnchantInfo", "GetInventorySlotInfo", "GetGuildRosterInfo", "GetNumGuildMembers", "GetChannelList",
        "GetLootSourceInfo", "GetLootRollItemLink", "GetInboxItemLink", "GetTrainerServiceDescription",
        "GetTrainerServiceItemLink", "GetTrainerServiceLevelReq", "GetTrainerGreetingText", "EJ_GetNumTiers",
        "EJ_GetInstanceByIndex", "EJ_GetInstanceInfo", "UnitCreatureID", "C_CreatureInfo.GetCreatureID", "CanLootUnit",
        "C_TradeSkillUI.GetAllRecipeIDs", "C_PetJournal.GetPetInfoByItemID", "C_PetJournal.GetNumCollectedInfo",
        "C_ToyBox.GetNumToys", "C_WowTokenPublic", "NameUtil", "C_AutoLoot", "C_AssistedCombat", "C_AuctionHouse",
        "C_DamageMeter", "C_EncodingUtil", "C_QuestLine", "C_SkillInfo", "C_Trainer", "APIDocumentation",
        -- die feine Uhr des Takts (Probe.Takt): ohne sie greift nur die Grenze der Abfragen je Bild
        "debugprofilestop", "GetTimePreciseSec" }) do
        run:Has("A2", name)
    end
end

P.A3 = function(run)
    for _, name in ipairs({ "ItemQuality", "ItemBind", "ItemClass", "InventoryType", "ItemDiscoverySource", "BagIndex",
        "BankType", "LootSlotType", "TooltipDataType", "TooltipDataLineType", "TooltipDataItemBinding",
        "TooltipDataUsageRequirementType", "QuestObjectiveType", "PlayerInteractionType", "TraitConfigType", "UIMapType",
        "PowerType", "AddOnRestrictionType", "AddOnRestrictionState", "CurrencyDestroyReason", "GameRule", "TrainerType",
        "FlightPathState", "DamageMeterType", "DamageMeterSessionType" }) do
        run:With({ maxFields = 250 }):Val("A3", "Enum." .. name)
    end
    for _, name in ipairs({ "InventoryConstants", "LegacyConsts", "CharacterNameSeparatorConsts" }) do
        run:With({ maxFields = 250 }):Val("A3", "Constants." .. name)
    end
    for i = 1, 10 do run:Val("A3", "TRANSMOG_SOURCE_" .. i) end
    for i = 1, 12 do run:Val("A3", "BATTLE_PET_SOURCE_" .. i) end
    run:Val("A3", "LOOT_ITEM_SELF")
    run:Val("A3", "LOOT_ITEM_SELF_MULTIPLE")
end

local ITEM_CALLS = { "C_Item.GetItemInfo", "C_Item.GetItemInfoInstant", "C_Item.GetItemNameByID", "C_Item.GetItemQualityByID",
    "C_Item.GetItemInventoryTypeByID", "C_Item.GetItemMaxStackSizeByID", "C_Item.DoesItemExistByID",
    "C_Item.IsItemDataCachedByID", "C_Item.GetItemFamily", "C_Item.GetItemSpell", "C_Item.GetItemUniquenessByID",
    "C_Item.IsEquippableItem", "C_Item.IsConsumableItem", "C_Item.IsItemBindToAccount" }

P.A4 = function(run)
    local ids = { 6948 }
    for _, item in ipairs(BagItems(run, 3)) do ids[#ids + 1] = item.id end
    for _, id in ipairs(ids) do
        run:Step(function(r)
            for _, path in ipairs(ITEM_CALLS) do r:Q("A4", path, id) end
            local instant = r:Call("C_Item.GetItemInfoInstant", id)
            local class, sub = instant:Num(6), instant:Num(7)
            if class then
                r:Q("A4", "C_Item.GetItemClassInfo", class)
                if sub then r:Q("A4", "C_Item.GetItemSubClassInfo", class, sub) end
            end
        end)
    end
    -- Auflösen über den Namen: in der Sprache des Clients und in der anderen
    run:Step(function(r)
        local name = r:Call("C_Item.GetItemNameByID", 6948):Str()
        if name then r:Q("A4", "C_Item.GetItemInfoInstant", name) end
        r:Q("A4", "C_Item.GetItemInfoInstant", "Hearthstone")
        r:Q("A4", "C_Item.GetItemInfoInstant", "Ruhestein")
    end)
end

P.A5 = function(run)
    -- ein sicher nie gesehener Gegenstand und eine Nummer, die es nicht gibt
    for _, id in ipairs({ 19019, 999999 }) do
        Many(run, "A5", { { "C_Item.DoesItemExistByID", id }, { "C_Item.IsItemDataCachedByID", id },
            { "C_Item.GetItemInfoInstant", id }, { "C_Item.GetItemNameByID", id }, { "C_Item.GetItemInfo", id } })
    end
    -- Rückruf von Item:ContinueOnItemLoad: wie viele Werte kommen an?
    local mixin = Tab(rawget(_G, "Item"))
    local create = Field(mixin, "CreateFromItemID")
    if type(create) == "function" then
        local okItem, item = pcall(create, mixin, 19019)
        local continue = okItem and Field(item, "ContinueOnItemLoad") or nil
        if type(continue) == "function" then
            local release = run:Hold("A5", "Item:ContinueOnItemLoad(19019)", Probe.WAIT)
            local ok, err = pcall(continue, item, function(...) release(...) end)
            if not ok then run:Note("A5", "Item:ContinueOnItemLoad Fehler", tostring(err)) end
        else
            run:Has("A5", "Item.ContinueOnItemLoad")
        end
    else
        run:Has("A5", "Item.CreateFromItemID")
    end
    -- Anfrage an den Server (einmal je Lauf), danach dieselben Abfragen erneut. Nur die Antwort für 19019 zählt –
    -- die Abfragen oben (999999, Taschenstücke) lösen dasselbe Ereignis für andere Nummern aus.
    run:Wait("A5", "ITEM_DATA_LOAD_RESULT", function(r)
        Many(r, "A5", { { "C_Item.IsItemDataCachedByID", 19019 }, { "C_Item.GetItemInfo", 19019 } })
        Tooltip(r, "A5", nil, "C_TooltipInfo.GetItemByID", 19019)
    end, nil, function(itemID) return Num(itemID) == 19019 end)
    run:Q("A5", "C_Item.RequestLoadItemDataByID", 19019)
end

P.A6 = function(run)
    local occupied, shown = {}, 0
    for bag = -3, 23 do
        local slots = run:Q("A6", "C_Container.GetContainerNumSlots", bag):Num() or 0
        if slots > 0 then
            run:Q("A6", "C_Container.GetBagName", bag)
            run:Q("A6", "C_Container.GetContainerNumFreeSlots", bag)
            for slot = 1, slots do
                if run:Call("C_Container.GetContainerItemID", bag, slot):Num() then
                    occupied[#occupied + 1] = { bag = bag, slot = slot }
                end
            end
        end
    end
    run:Note("A6", "belegte Plätze", #occupied)
    -- je belegtem Platz (höchstens 40) alle Felder und der Link im Rohtext, in Scheiben zu zehn
    for start = 1, math.min(#occupied, 40), 10 do
        run:Step(function(r)
            for i = start, math.min(start + 9, #occupied, 40) do
                local at = occupied[i]
                local info = r:Q("A6", "C_Container.GetContainerItemInfo", at.bag, at.slot)
                local fields, body = LinkFields(info:Field("hyperlink"))
                if fields then r:Tag(("%d:%d"):format(at.bag, at.slot)):Note("A6", "Link-Felder", fields, body) end
                shown = shown + 1
                if shown <= 5 then
                    r:Q("A6", "C_Container.GetContainerItemQuestInfo", at.bag, at.slot)
                    r:Q("A6", "C_Container.GetContainerItemDurability", at.bag, at.slot)
                    local mixin = Tab(rawget(_G, "ItemLocation"))
                    local create = Field(mixin, "CreateFromBagAndSlot")
                    local ok, loc = pcall(function() return create(mixin, at.bag, at.slot) end)
                    if ok and Tab(loc) then
                        for _, path in ipairs({ "C_Item.DoesItemExist", "C_Item.GetItemGUID", "C_Item.GetItemID",
                            "C_Item.GetCurrentItemLevel", "C_Item.IsBound", "C_Item.GetStackCount" }) do
                            r:Tag(("ItemLocation %d:%d"):format(at.bag, at.slot)):Q("A6", path, loc)
                        end
                    end
                    local id = Num(info:Field("itemID"))
                    if id then
                        r:Q("A6", "C_Item.GetItemCount", id)
                        r:Q("A6", "C_Item.GetItemCount", id, true)
                    end
                end
            end
        end)
    end
end

P.A7 = function(run)
    local empty = 0
    for slot = 0, 30 do
        local id = run:Call("GetInventoryItemID", "player", slot):Num()
        if id then
            Many(run, "A7", { { "GetInventoryItemID", "player", slot }, { "GetInventoryItemLink", "player", slot },
                { "GetInventoryItemQuality", "player", slot }, { "GetInventoryItemDurability", slot } })
        else
            empty = empty + 1
        end
    end
    run:Note("A7", "leere Plätze 0-30", empty)
    run:Val("A7", "INVSLOT_FIRST_EQUIPPED")
    run:Val("A7", "INVSLOT_LAST_EQUIPPED")
    Many(run, "A7", { "C_PaperDollInfo.IsRangedSlotShown", "C_PaperDollInfo.AmmoNeeded", { "GetInventorySlotInfo", "RANGEDSLOT" },
        { "GetInventorySlotInfo", "AMMOSLOT" }, "GetAverageItemLevel" })
    run:Step(function(r)
        local list = Equipped(r, 6)
        for _, item in ipairs(list) do
            if item.link then
                r:Tag("slot " .. item.slot):Q("A7", "C_Item.GetItemStats", item.link)
                r:Tag("slot " .. item.slot):Q("A7", "C_Item.GetDetailedItemLevelInfo", item.link)
                r:Tag("slot " .. item.slot):Q("A7", "C_Item.GetItemUpgradeInfo", item.link)
            end
        end
        -- Variantentest: derselbe Gegenstand mit zwei verschiedenen Link-Stufen (Feld 9)
        local first = list[1]
        if first then
            for _, level in ipairs({ 10, 60 }) do
                local link = ("item:%d::::::::%d"):format(first.id, level)
                r:Q("A7", "C_Item.GetItemStats", link)
                r:Q("A7", "C_Item.GetDetailedItemLevelInfo", link)
            end
        end
    end)
end

P.A8 = function(run)
    for _, item in ipairs(Equipped(run, 19)) do
        run:Step(function(r) Tooltip(r, "A8", nil, "C_TooltipInfo.GetInventoryItem", "player", item.slot) end)
    end
    run:Step(function(r)
        for _, item in ipairs(BagItems(r, 10)) do Tooltip(r, "A8", nil, "C_TooltipInfo.GetBagItem", item.bag, item.slot) end
        local spell = OwnSpells(r).learnedID
        if spell then Tooltip(r, "A8", nil, "C_TooltipInfo.GetHyperlink", "spell:" .. spell) end
    end)
end

P.A9 = function(run)
    local withSet = 0
    for _, item in ipairs(Equipped(run, 19)) do
        local setID = item.link and run:Call("C_Item.GetItemInfo", item.link):Num(16)
        if setID then
            withSet = withSet + 1
            if withSet == 1 then
                run:Q("A9", "C_Item.GetItemSetInfo", setID)
                run:Q("A9", "C_LootJournal.GetItemSetItems", setID)
            end
        end
    end
    run:Note("A9", "angelegte Stücke mit setID", withSet)
    Many(run, "A9", { "C_LootJournal.GetItemSets", "C_EquipmentSet.CanUseEquipmentSets" })
    local sets = run:Q("A9", "C_EquipmentSet.GetEquipmentSetIDs"):Tab()
    for i = 1, math.min(sets and #sets or 0, 2) do
        local setID = Num(sets[i])
        if setID then
            -- der Name eines Sets ist vom Spieler vergeben: nur die Länge
            run:With({ ret = { [1] = true } }):Q("A9", "C_EquipmentSet.GetEquipmentSetInfo", setID)
            run:Q("A9", "C_EquipmentSet.GetItemIDs", setID)
            run:Q("A9", "C_EquipmentSet.GetItemLocations", setID)
        end
    end
    local size = run:Q("A9", "C_CurrencyInfo.GetCurrencyListSize"):Num() or 0
    for i = 1, math.min(size, 30) do run:Q("A9", "C_CurrencyInfo.GetCurrencyListInfo", i) end
    run:Q("A9", "GetMoney")
end

P.A10 = function(run)
    local s = OwnSpells(run)
    run:Note("A10", "Zauberbuch", { lines = s.lines, items = s.items, spells = s.spells, future = s.future, offSpec = s.offSpec,
        other = s.other })
    for line = 1, math.min(s.lines, 12) do run:Q("A10", "C_SpellBook.GetSpellBookSkillLineInfo", line) end
    if s.learnedIndex then
        run:Q("A10", "C_SpellBook.GetSpellBookItemInfo", s.learnedIndex, s.bank)
        run:Q("A10", "C_SpellBook.GetSpellBookItemLevelLearned", s.learnedIndex, s.bank)
    end
    if s.futureIndex then run:Q("A10", "C_SpellBook.GetSpellBookItemInfo", s.futureIndex, s.bank) end
    -- ein gelernter, ein künftiger und ein klassenfremder Zauber (Feuerball 133, für Magier Göttliche Pein 585)
    local class = run:Call("UnitClass", "player"):Str(2)
    local spells = { { "gelernt", s.learnedID }, { "künftig", s.futureID }, { "klassenfremd", class == "MAGE" and 585 or 133 } }
    for _, entry in ipairs(spells) do
        local label, id = entry[1], entry[2]
        if id then
            run:Step(function(r)
                for _, path in ipairs({ "C_Spell.GetSpellInfo", "C_Spell.GetSpellSubtext", "C_Spell.GetSpellDescription",
                    "C_Spell.IsSpellDataCached", "C_Spell.GetSpellPowerCost", "C_Spell.GetSpellLevelLearned", "C_Spell.GetSpellLink",
                    "C_Spell.IsSpellPassive", "C_Spell.IsSpellHarmful", "C_Spell.GetBaseSpell", "C_Spell.GetOverrideSpell",
                    "C_ActionBar.IsHighestSpellRank" }) do
                    r:Tag(label):Q("A10", path, id)
                end
            end)
        end
    end
    -- Beschreibung noch einmal nach zwei Sekunden (lädt sie nach?)
    run:After(2, function(r)
        for _, entry in ipairs(spells) do
            if entry[2] then r:Tag(entry[1] .. ", nach 2 s"):Q("A10", "C_Spell.GetSpellDescription", entry[2]) end
        end
    end)
    run:Step(function(r)
        local level = r:Call("UnitLevel", "player"):Num() or 1
        r:Q("A10", "C_SpellBook.GetCurrentLevelSpells", level + 1)
        r:Q("A10", "C_SpellBook.GetCurrentLevelSpells", level + 2)
        r:Q("A10", "C_CooldownViewer.GetGroupBuffItems")
        for category = 0, 3 do r:Q("A10", "C_CooldownViewer.GetCooldownViewerCategorySet", category, true) end
        r:Q("A10", "C_Flyout.GetNumFlyouts")
        r:Q("A10", "GetNumFlyouts")
    end)
end

P.A11 = function(run)
    local class = run:Call("UnitClass", "player"):Num(3)
    Many(run, "A11", { "GetSpecializationSystem", "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetActiveSpecGroup",
        "GetNumSpecGroups", { "C_SpecializationInfo.GetCombatConfigIDForSpecGroup", 1 },
        { "C_SpecializationInfo.GetCombatConfigIDForSpecGroup", 2 },
        { "C_SpecializationInfo.GetNumSpecializationsForClassID", class or 1 } })
    local config = run:Q("A11", "C_ClassTalents.GetActiveConfigID"):Num()
    local camelot = EnumValue("TraitConfigType", "CamelotCombat")
    if camelot ~= nil then run:Tag("CamelotCombat"):Q("A11", "C_Traits.GetConfigsByType", camelot) end
    run:Step(function(r)
        if not config then return end
        local info = r:Q("A11", "C_Traits.GetConfigInfo", config)
        local trees = Tab(info:Field("treeIDs"))
        local tree = trees and Num(trees[1])
        if not tree then return end
        local nodes = r:Q("A11", "C_Traits.GetTreeNodes", tree):Tab()
        -- erster sichtbarer Knoten mit Eintrag
        for i = 1, math.min(nodes and #nodes or 0, 80) do
            local nodeID = Num(nodes[i])
            local node = nodeID and r:Call("C_Traits.GetNodeInfo", config, nodeID)
            local entries = node and Tab(node:Field("entryIDs"))
            local entryID = entries and Num(entries[1])
            if entryID and node:Field("isVisible") == true then
                r:Q("A11", "C_Traits.GetNodeInfo", config, nodeID)
                local definition = r:Q("A11", "C_Traits.GetEntryInfo", config, entryID):Field("definitionID")
                if Num(definition) then r:Q("A11", "C_Traits.GetDefinitionInfo", definition) end
                r:Q("A11", "C_Traits.GetTraitDescription", entryID, 1)
                r:Q("A11", "C_Traits.GetTraitDescription", entryID, 2)
                break
            end
        end
        Many(r, "A11", { { "C_Traits.GetGroupDisplayInfoByTreeID", tree }, { "C_Traits.GetTreeCurrencyInfo", config, tree, false },
            { "C_Traits.GetTreeHash", tree }, { "C_Traits.GenerateImportString", config } })
    end)
    run:Step(function(r)
        -- Baum einer fremden Klasse (Spezialisierung 62 Arkan bzw. 71 Waffen), alte Talent-Abfrage
        r:Q("A11", "C_ClassTalents.GetTraitTreeForSpec", class == 8 and 71 or 62)
        r:Q("A11", "C_SpecializationInfo.GetTalentInfo", { tier = 1, column = 1 })
        -- Vermächtnis: je Konto oder je Charakter? (auf zwei Charakteren vergleichen)
        for _, tree in ipairs({ 1187, 1188, 1189 }) do
            local legacy = r:Q("A11", "C_Traits.GetConfigIDByTreeID", tree):Num()
            r:Q("A11", "C_Traits.GetTreeNodes", tree)
            if legacy then r:Q("A11", "C_Traits.GetTreeCurrencyInfo", legacy, tree, false) end
        end
        r:Q("A11", "C_MajorFactions.GetCurrentRenownLevel", 2802)
    end)
end

P.A12 = function(run)
    for i = 1, 10 do run:Q("A12", "GetPetActionInfo", i) end
    Many(run, "A12", { "C_PetInfo.GetPetHappiness", "C_PetInfo.GetPetLoyalty", "C_PetInfo.GetPetTrainingPoints",
        "C_PetInfo.GetPetFoodTypes", { "UnitCreatureFamily", "pet" }, "C_CreatureInfo.GetCreatureFamilyIDs",
        "C_StableInfo.GetNumStableSlots" })
    -- Begleiter tragen vom Spieler vergebene Namen: nur die Länge
    run:With({ fields = { name = true } }):Q("A12", "C_StableInfo.GetActivePetList")
    run:Step(function(r)
        local kinds, first = {}, {}
        for slot = 1, 120 do
            local kind = r:Call("GetActionInfo", slot):Str()
            if kind then
                kinds[kind] = (kinds[kind] or 0) + 1
                first[kind] = first[kind] or slot
            end
        end
        r:Note("A12", "Aktionsplätze je Art", kinds)
        for _, slot in pairs(first) do r:Q("A12", "GetActionInfo", slot) end
        local macros = r:Q("A12", "GetNumMacros"):Num() or 0
        -- Makros: Name und Text nur als Länge
        if macros > 0 then r:With({ ret = { [1] = true, [3] = true } }):Q("A12", "GetMacroInfo", 1) end
        r:Q("A12", "GetNumShapeshiftForms")
        r:Q("A12", "GetShapeshiftFormInfo", 1)
    end)
end

P.A13 = function(run)
    local profs = run:Q("A13", "GetProfessions")
    local lines = {}
    for i = 1, profs.n or 0 do
        local index = profs:Num(i)
        if index then
            local info = run:Q("A13", "GetProfessionInfo", index)
            lines[#lines + 1] = info:Num(7)
        end
    end
    local count = run:Q("A13", "C_SkillInfo.GetNumSkillLines"):Num() or 0
    for i = 1, math.min(count, 40) do run:Q("A13", "C_SkillInfo.GetSkillLineInfo", i) end
    for _, line in ipairs(lines) do run:Q("A13", "C_TradeSkillUI.GetProfessionInfoBySkillLineID", line) end
    run:Q("A13", "C_TradeSkillUI.GetAllProfessionTradeSkillLines")
    run:Step(function(r)
        -- ein Rezept ohne offenes Fenster (2330: Schwacher Heiltrank)
        Many(r, "A13", { { "C_TradeSkillUI.GetRecipeInfo", 2330 }, { "C_TradeSkillUI.GetRecipeSchematic", 2330, false },
            { "C_TradeSkillUI.GetRecipeOutputItemData", 2330 }, { "C_TradeSkillUI.GetTradeSkillLineForRecipe", 2330 },
            { "C_TradeSkillUI.IsRecipeProfessionLearned", 2330 }, { "C_TradeSkillUI.GetGatheringOperationInfo", 2330 } })
        -- Nachprobe: ein Rezept des EIGENEN Berufs bei geschlossenem Fenster (Nummer aus einem früheren Lauf am
        -- Berufefenster, J2) – trennt „ohne Fenster“ von „ohne den Beruf“; GetSalvagableItemIDs verlangt eine recipeID
        -- (vorher ohne gefragt: ein Fehler der Probe)
        local hint = Probe.Hint()
        local own, salvage = Num(hint.recipe), Num(hint.salvage)
        if own then
            r:Tag("eigenes Rezept, Fenster zu")
            Many(r, "A13", { { "C_TradeSkillUI.GetRecipeInfo", own }, { "C_TradeSkillUI.GetRecipeSchematic", own, false },
                { "C_TradeSkillUI.GetTradeSkillLineForRecipe", own }, { "C_TradeSkillUI.IsRecipeProfessionLearned", own } })
        else
            r:Note("A13", "eigenes Rezept: noch keine Nummer (erst nach einem Lauf am Berufefenster)", nil)
        end
        if salvage then
            r:Q("A13", "C_TradeSkillUI.GetSalvagableItemIDs", salvage)
        else
            r:Note("A13", "GetSalvagableItemIDs: noch keine Nummer eines Zerlege-Rezepts", nil)
        end
    end)
end

P.A14 = function(run)
    local map = MapID(run)
    local entries = run:Q("A14", "C_QuestLog.GetNumQuestLogEntries"):Num() or 0
    local quests = {}
    for i = 1, math.min(entries, 60) do
        local info = run:Call("C_QuestLog.GetInfo", i)
        local id = Num(info:Field("questID"))
        if id and id > 0 and info:Field("isHeader") ~= true and #quests < 10 then quests[#quests + 1] = { index = i, id = id } end
    end
    run:Note("A14", "Quests im Log (ohne Überschriften, höchstens 10)", #quests)
    for n, quest in ipairs(quests) do
        run:Step(function(r)
            local i, id = quest.index, quest.id
            Many(r, "A14", { { "C_QuestLog.GetInfo", i }, { "C_QuestLog.GetQuestObjectives", id },
                { "C_QuestLog.GetQuestTagInfo", id }, { "GetQuestLink", id }, { "GetQuestFactionGroup", id },
                { "GetNumQuestLogRewards", id }, { "GetQuestLogRewardInfo", 1, id }, { "GetNumQuestLogChoices", id, true },
                { "GetQuestLogChoiceInfo", 1, id }, { "GetQuestLogRewardMoney", id }, { "GetQuestLogRewardXP", id },
                { "C_QuestLog.GetNextWaypoint", id } })
            -- Quest- und Abschlusstext: nur die Längen
            r:With({ text = true }):Q("A14", "GetQuestLogQuestText", i)
            r:With({ text = true }):Q("A14", "GetQuestLogCompletionText", i)
            if n == 1 then
                local factions = r:Call("C_Reputation.GetNumFactions"):Num() or 0
                local asked = 0
                for f = 1, math.min(factions, 60) do
                    local faction = Num(r:Call("C_Reputation.GetFactionDataByIndex", f):Field("factionID"))
                    if faction and faction > 0 and asked < 5 then
                        asked = asked + 1
                        r:Q("A14", "C_QuestLog.DoesQuestAwardReputationWithFaction", id, faction)
                    end
                end
            end
        end)
    end
    run:Step(function(r)
        if map then
            r:Q("A14", "C_QuestLog.GetQuestsOnMap", map)
            r:Q("A14", "C_TaskQuest.GetQuestsOnMap", map)
        end
        Many(r, "A14", { "C_QuestLog.GetAllCompletedQuestIDs", "C_CampaignInfo.GetAvailableCampaigns" })
        -- Quest außerhalb des Logs (783) – Anfrage an den Server, einmal je Lauf
        r:Wait("A14", "QUEST_DATA_LOAD_RESULT", function(rr)
            Many(rr, "A14", { { "C_QuestLog.GetTitleForQuestID", 783 }, { "C_QuestLog.GetQuestObjectives", 783 } })
        end)
        r:Q("A14", "C_QuestLog.RequestLoadQuestByID", 783)
        -- annehmbare Quests der Karte mit Ort – Anfrage an den Server, einmal je Lauf
        if map then
            r:Wait("A14", "QUESTLINE_UPDATE", function(rr)
                rr:With({ samples = 5 }):Q("A14", "C_QuestLine.GetAvailableQuestLines", map)
            end)
            r:Q("A14", "C_QuestLine.RequestQuestLinesForMap", map)
        end
    end)
end

P.A15 = function(run)
    local count = run:Q("A15", "C_Reputation.GetNumFactions"):Num() or 0
    local headers, collapsed, shown, collapsedID, firstID = 0, 0, 0, nil, nil
    for i = 1, math.min(count, 120) do
        local data = run:Call("C_Reputation.GetFactionDataByIndex", i)
        local id = Num(data:Field("factionID"))
        if data:Field("isHeader") == true then headers = headers + 1 end
        if data:Field("isCollapsed") == true then
            collapsed = collapsed + 1
            collapsedID = collapsedID or id
        end
        if id and id > 0 then firstID = firstID or id end
        if shown < 5 and id then
            shown = shown + 1
            run:Q("A15", "C_Reputation.GetFactionDataByIndex", i)
        end
    end
    run:Note("A15", "Ruf-Zeilen", { rows = count, headers = headers, collapsed = collapsed })
    local faction = collapsedID or firstID
    if faction then
        run:Q("A15", "C_Reputation.GetFactionDataByID", faction)
        run:Q("A15", "C_GossipInfo.GetFriendshipReputation", faction)
    end
    Many(run, "A15", { { "C_MajorFactions.GetMajorFactionData", 2802 }, { "C_MajorFactions.GetMajorFactionProgressionInfo", 2802 },
        { "C_MajorFactions.GetRenownLevels", 2802 }, { "C_MajorFactions.GetRenownRewardsForLevel", 2802, 1 } })
    run:Step(function(r)
        local categories = r:Q("A15", "GetCategoryList"):Tab()
        for i = 1, math.min(categories and #categories or 0, 3) do
            local category = Num(categories[i])
            if category then
                r:Q("A15", "GetCategoryInfo", category)
                local n = r:Q("A15", "GetCategoryNumAchievements", category):Num() or 0
                if n > 0 then
                    local id = r:Q("A15", "GetAchievementInfo", category, 1):Num()
                    if id then
                        Many(r, "A15", { { "GetAchievementNumCriteria", id }, { "GetAchievementCriteriaInfo", id, 1 },
                            { "C_Traits.GetTraitCurrencyForAchievement", 4225, id }, { "C_AchievementInfo.GetRewardItemID", id } })
                    end
                end
            end
        end
        local stats = r:Q("A15", "GetStatisticsCategoryList"):Tab()
        local stat = stats and Num(stats[1])
        if stat then
            local id = r:Q("A15", "GetAchievementInfo", stat, 1):Num()
            if id then r:Q("A15", "GetStatistic", id) end
        end
        Many(r, "A15", { "GetNumTitles", { "GetTitleName", 1 }, "GetCurrentTitle" })
    end)
end

P.A16 = function(run)
    local mounts = run:Q("A16", "C_MountJournal.GetMountIDs"):Tab()
    local collected, bySource, first = 0, {}, nil
    for i = 1, math.min(mounts and #mounts or 0, 2000) do
        local id = Num(mounts[i])
        if id then
            first = first or id
            local info = run:Call("C_MountJournal.GetMountInfoByID", id)
            if info:True(11) then collected = collected + 1 end
            local source = info:Num(6)
            if source then bySource[source] = (bySource[source] or 0) + 1 end
        end
    end
    run:Note("A16", "Reittiere: gesammelt, je sourceType", collected, bySource)
    if first then
        run:Q("A16", "C_MountJournal.GetMountInfoByID", first)
        run:Q("A16", "C_MountJournal.GetMountInfoExtraByID", first)
    end
    run:Step(function(r)
        Many(r, "A16", { "C_ToyBox.GetNumFilteredToys", "C_ToyBox.GetNumTotalDisplayedToys", "C_ToyBox.GetNumLearnedDisplayedToys" })
        local toy = r:Q("A16", "C_ToyBox.GetToyFromIndex", 1):Num()
        if toy and toy > 0 then r:Q("A16", "C_ToyBox.GetToyInfo", toy) end
        Many(r, "A16", { "C_PetJournal.GetNumPets", "C_PetJournal.GetOwnedPetIDs" })
        -- Rückgabe 4 ist der vom Spieler vergebene Name: nur die Länge
        r:With({ ret = { [4] = true } }):Q("A16", "C_PetJournal.GetPetInfoByIndex", 1)
        local chest = r:Call("GetInventoryItemLink", "player", 5):Str()
        if chest then
            local source = r:Tag("Brust"):Q("A16", "C_TransmogCollection.GetItemInfo", chest):Num(2)
            if source then
                Many(r, "A16", { { "C_TransmogCollection.GetSourceInfo", source }, { "C_TransmogCollection.GetAppearanceSourceInfo", source },
                    { "C_TransmogCollection.GetAppearanceInfoBySource", source }, { "C_TransmogCollection.GetAppearanceSourceDrops", source } })
            end
        end
        Many(r, "A16", { { "C_TransmogCollection.GetCategoryCollectedCount", 1 }, { "C_TransmogCollection.GetCategoryTotal", 1 },
            "C_HeirloomInfo.HeirloomsAvailable", "C_Heirloom.GetNumHeirlooms", "C_ContentTracking.GetCollectableSourceTrackingEnabled" })
    end)
end

-- Kartenbaum abtasten: IDs in Scheiben, nur gezählt; die ersten Beispiele festgehalten.
local function ScanMaps(run, id, from, to, acc)
    for map = from, to do
        local info = run:Call("C_Map.GetMapInfo", map):Tab()
        if info then
            local kind = Num(Field(info, "mapType")) or -1
            acc.total = acc.total + 1
            acc.byType[kind] = (acc.byType[kind] or 0) + 1
            if kind == 2 or kind == 3 then
                local levels = run:Call("C_Map.GetMapLevels", map)
                if (levels:Num(1) or 0) > 0 or (levels:Num(2) or 0) > 0 then
                    acc.levels = acc.levels + 1
                    if acc.levels <= 3 then run:Q(id, "C_Map.GetMapLevels", map) end
                end
                local entrances = run:Call("C_EncounterJournal.GetDungeonEntrancesForMap", map):Tab()
                if entrances and #entrances > 0 then
                    acc.entranceMaps, acc.entrances = acc.entranceMaps + 1, acc.entrances + #entrances
                    if acc.entranceMaps <= 2 then run:Q(id, "C_EncounterJournal.GetDungeonEntrancesForMap", map) end
                end
                local pois = run:Call("C_AreaPoiInfo.GetAreaPOIForMap", map):Tab()
                if pois and #pois > 0 then
                    acc.poiMaps, acc.pois = acc.poiMaps + 1, acc.pois + #pois
                    if acc.poiMaps <= 2 then
                        run:Q(id, "C_AreaPoiInfo.GetAreaPOIForMap", map)
                        local poi = Num(pois[1])
                        if poi then run:Q(id, "C_AreaPoiInfo.GetAreaPOIInfo", map, poi) end
                    end
                end
            end
        end
    end
end

P.A17 = function(run)
    local map = MapID(run)
    run:Note("A17", "Karte", map)
    -- Elternkette mit Typ, Flags, Gruppe, Art
    local chain, at, top = 0, map, map
    while at and at > 0 and chain < 8 do
        chain = chain + 1
        top = at
        local info = run:Q("A17", "C_Map.GetMapInfo", at)
        run:Q("A17", "C_Map.GetMapGroupID", at)
        run:Q("A17", "C_Map.GetMapArtID", at)
        at = Num(info:Field("parentMapID"))
    end
    if top then
        local children = run:Call("C_Map.GetMapChildrenInfo", top, nil, true):Tab()
        local byType = {}
        for i = 1, children and #children or 0 do
            local kind = Num(Field(Tab(children[i]), "mapType")) or -1
            byType[kind] = (byType[kind] or 0) + 1
        end
        run:Tag("unter Karte " .. top):Note("A17", "Kartenbaum: Anzahl je mapType", children and #children or nil, byType)
    end
    if map then
        local pos = run:Q("A17", "C_Map.GetPlayerMapPosition", map, "player"):Tab()
        Many(run, "A17", { { "UnitPosition", "player" }, { "C_Map.GetMapWorldSize", map }, { "C_Map.GetMapLevels", map },
            { "C_EncounterJournal.GetDungeonEntrancesForMap", map }, { "C_AreaPoiInfo.GetAreaPOIForMap", map },
            { "C_MapExplorationInfo.GetExploredMapTextures", map }, { "C_TaxiMap.GetTaxiNodesForMap", map },
            { "C_DeathInfo.GetGraveyardsForMap", map }, { "C_Map.GetMapLinksForMap", map } })
        if pos then
            run:Tag("Karte, eigene Position"):Q("A17", "C_Map.GetWorldPosFromMapPos", map, pos)
            run:Tag("Karte, eigene Position"):Q("A17", "C_MapExplorationInfo.GetExploredAreaIDsAtPosition", map, pos)
        end
    end
    run:Step(function(r)
        Many(r, "A17", { { "C_EncounterJournal.GetInstanceForGameMap", 36 }, "C_PvP.GetZonePVPInfo", "IsIndoors", "IsOutdoors",
            "IsResting", "GetBindLocation", "GetZoneText", "GetSubZoneText", "GetMinimapZoneText" })
        local kinds = r:Q("A17", "C_Minimap.GetNumTrackingTypes"):Num() or 0
        for i = 1, math.min(kinds, 25) do r:Q("A17", "C_Minimap.GetTrackingInfo", i) end
        local list = r:Q("A17", "C_VignetteInfo.GetVignettes"):Tab()
        local guid = list and Str(list[1])
        if guid then
            r:Q("A17", "C_VignetteInfo.GetVignetteInfo", guid)
            if map then r:Q("A17", "C_VignetteInfo.GetVignettePosition", guid, map) end
        end
    end)
    -- alle Karten 1 … 3000 abtasten (nur zählen), 200 je Schritt
    local acc = { total = 0, byType = {}, levels = 0, entranceMaps = 0, entrances = 0, poiMaps = 0, pois = 0 }
    for from = 1, 3000, 200 do
        run:Step(function(r) ScanMaps(r, "A17", from, from + 199, acc) end)
    end
    run:Step(function(r)
        r:Note("A17", "Karten 1-3000", { maps = acc.total, mitStufen = acc.levels, kartenMitEingang = acc.entranceMaps,
            eingaenge = acc.entrances, kartenMitPOI = acc.poiMaps, pois = acc.pois }, acc.byType)
    end)
end

P.A18 = function(run)
    local guid = run:Q("A18", "UnitGUID", "player"):Str()
    if guid then
        local lengths = {}
        for part in guid:gmatch("[^%-]+") do lengths[#lengths + 1] = #part end
        run:Note("A18", "GUID-Aufbau player", guid:match("^([^%-]+)"), lengths)
        run:With({ ret = { [6] = "player", [7] = "realm" } }):Q("A18", "GetPlayerInfoByGUID", guid)
        run:Q("A18", "C_AccountInfo.IsGUIDRelatedToLocalAccount", guid)
    end
    Many(run, "A18", { { "UnitName", "player" }, { "UnitFullName", "player" }, { "UnitNameUnmodified", "player" },
        "RegionalUniqueNamesEnabled", { "UnitClass", "player" }, { "UnitRace", "player" }, { "UnitSex", "player" },
        { "UnitSexBase", "player" }, { "UnitFactionGroup", "player" }, { "UnitXP", "player" }, { "UnitXPMax", "player" },
        "GetXPExhaustion", "GetRestState", { "C_Secrets.ShouldUnitStatsBeSecret", "player" } })
    for i = 1, 5 do run:Q("A18", "UnitStat", "player", i) end
    Many(run, "A18", { { "UnitArmor", "player" }, { "GetCombatRating", 1 }, "GetCritChance", { "UnitHealth", "player" },
        { "UnitHealthMax", "player" }, { "UnitPower", "player" }, { "UnitPowerMax", "player" } })
end

P.A19 = function(run)
    Many(run, "A19", { "IsInGuild", "C_Club.GetGuildClubId", "C_FriendList.IsLegacyFriendSystemEnabled",
        "C_FriendList.GetNumFriends", "C_SocialUI.IsSystemEnabled", "C_BattleNet.AreTitleFriendsEnabled", "BNGetNumFriends",
        "C_RecentAllies.IsSystemSupported", "C_RecentAllies.IsSystemEnabled", "C_ChatInfo.GetNumActiveChannels" })
    run:With({ ret = { [1] = "guild", [2] = "rank", [4] = "realm" } }):Q("A19", "GetGuildInfo", "player")
    run:With({ fields = { name = "friend" } }):Q("A19", "C_FriendList.GetFriendInfoByIndex", 1)
    run:With({ fields = { name = "friend" } }):Q("A19", "C_BattleNet.GetFriendAccountInfo", 1)
    for i = 1, 5 do
        -- Kanalnamen können vom Spieler vergeben sein: nur die Länge
        run:With({ ret = { [2] = true } }):Q("A19", "GetChannelName", i)
    end
    run:With({ fields = { name = true } }):Q("A19", "C_ChatInfo.GetChannelInfoFromIdentifier", "1")
    -- Gilde: Anfrage an den Server (einmal je Lauf), dann Zahl und Aufbau eines Mitglieds
    run:Step(function(r)
        if not r:Call("IsInGuild"):True() then return end
        r:Wait("A19", "GUILD_ROSTER_UPDATE", function(rr)
            rr:Q("A19", "GetNumGuildMembers")
            rr:With({ ret = { [1] = "player", [2] = "rank", [7] = true, [8] = true } }):Q("A19", "GetGuildRosterInfo", 1)
            local club = rr:Call("C_Club.GetGuildClubId"):Str()
            local members = club and rr:Q("A19", "C_Club.GetClubMembers", club):Tab()
            local member = members and Num(members[1])
            if member then rr:With({ fields = { name = "player" } }):Q("A19", "C_Club.GetMemberInfo", club, member) end
        end)
        r:Q("A19", "C_GuildInfo.GuildRoster")
    end)
    -- Kalender: Anfrage (einmal je Lauf); der gewählte Monat bleibt, wie er ist
    run:Step(function(r)
        r:Wait("A19", "CALENDAR_UPDATE_EVENT_LIST", function(rr)
            local month = rr:Q("A19", "C_Calendar.GetMonthInfo", 0)
            local today = rr:Q("A19", "C_DateAndTime.GetCurrentCalendarTime")
            local day, days = Num(today:Field("monthDay")) or 1, Num(month:Field("numDays")) or 30
            local events, holidays, shown = 0, 0, 0
            for d = day, days do
                local n = rr:Call("C_Calendar.GetNumDayEvents", 0, d):Num() or 0
                events = events + n
                for e = 1, math.min(n, 10) do
                    local event = rr:Call("C_Calendar.GetDayEvent", 0, d, e)
                    local kind = Str(event:Field("calendarType"))
                    if kind == "HOLIDAY" then
                        holidays = holidays + 1
                        if shown < 2 then
                            shown = shown + 1
                            rr:Q("A19", "C_Calendar.GetDayEvent", 0, d, e)
                            rr:Q("A19", "C_Calendar.GetHolidayInfo", 0, d, e)
                        end
                    elseif kind and shown < 3 then
                        -- Termine von Spielern und Gilde: Aufbau ja, Texte nein
                        shown = shown + 1
                        rr:With({ text = true }):Tag(kind):Q("A19", "C_Calendar.GetDayEvent", 0, d, e)
                    end
                end
            end
            rr:Note("A19", "Kalender ab heute bis Monatsende: Termine, davon Feiertage", events, holidays)
        end)
        r:Q("A19", "C_Calendar.OpenCalendar")
    end)
    -- Instanz-Sperren: Anfrage (einmal je Lauf)
    run:Step(function(r)
        r:Wait("A19", "UPDATE_INSTANCE_INFO", function(rr)
            local n = rr:Q("A19", "GetNumSavedInstances"):Num() or 0
            if n > 0 then rr:Q("A19", "GetSavedInstanceInfo", 1) end
            rr:Q("A19", "GetInstanceInfo")
        end)
        r:Q("A19", "RequestRaidInfo")
    end)
end

---------------------------------------------------------------------------
-- B – Händler, C – Lehrer, D – Briefkasten, E – Auktionshaus
---------------------------------------------------------------------------

P.B1 = function(run)
    NpcProbe(run, "B1", "npc")
end

local function MerchantItems(run, tag)
    local n = run:Tag(tag):Q("B2", "GetMerchantNumItems"):Num() or 0
    for i = 1, math.min(n, 12) do
        Many(run, "B2", { { "GetMerchantItemID", i }, { "GetMerchantItemLink", i }, { "C_MerchantFrame.GetItemInfo", i },
            { "GetMerchantItemMaxStack", i } })
    end
    -- Waren mit begrenztem Vorrat oder Zusatzkosten hinter den ersten zwölf (Probe 15.11.2026: Der Händler zählte als
    -- „begrenzter Vorrat“, die Ware stand aber an Platz 13 bis 22 und fehlte im Bericht) – höchstens sechs (Frage 16).
    -- Zuerst die mit begrenztem Vorrat, mit dem Rest des Platzes die mit Zusatzkosten: Bei einem Ruf- oder
    -- Markenhändler verdrängten sonst sechs Waren mit Zusatzkosten die eine mit Vorrat weiter hinten.
    local stocked, costly = {}, {}
    for i = 13, math.min(n, 60) do
        local info = run:Call("C_MerchantFrame.GetItemInfo", i):Tab()
        local stock = info and Num(Field(info, "numAvailable"))
        if stock and stock >= 0 then
            stocked[#stocked + 1] = i
        elseif info and Field(info, "hasExtendedCost") == true then
            costly[#costly + 1] = i
        end
    end
    for j = 1, #costly do stocked[#stocked + 1] = costly[j] end
    for j = 1, math.min(#stocked, 6) do
        local i = stocked[j]
        Many(run, "B2", { { "GetMerchantItemID", i }, { "GetMerchantItemLink", i }, { "C_MerchantFrame.GetItemInfo", i },
            { "GetMerchantItemMaxStack", i } })
    end
    return n
end

P.B2 = function(run)
    run:Q("B2", "GetMerchantFilter")
    local n = MerchantItems(run, "sofort")
    -- laden Namen nach? Dieselben Abfragen zwei Sekunden später
    run:After(2, function(r) MerchantItems(r, "nach 2 s") end)
    run.merchantItems = n
end

P.B3 = function(run)
    local n = run.merchantItems or run:Call("GetMerchantNumItems"):Num() or 0
    local shown = 0
    run:Val("B3", "MAX_ITEM_COST")
    for i = 1, math.min(n, 60) do
        local info = run:Call("C_MerchantFrame.GetItemInfo", i)
        if info:Field("hasExtendedCost") == true and shown < 5 then
            shown = shown + 1
            local kinds = run:Q("B3", "GetMerchantItemCostInfo", i):Num() or 0
            for c = 1, math.min(kinds, 3) do run:Q("B3", "GetMerchantItemCostItem", i, c) end
        end
    end
    run:Note("B3", "Waren mit Zusatzkosten (gezeigt)", shown)
    Many(run, "B3", { "C_MerchantFrame.GetMerchantCurrencies", "GetMerchantCurrencies" })
end

P.B4 = function(run)
    Many(run, "B4", { "CanMerchantRepair", "GetRepairAllCost", "GetNumBuybackItems", { "GetBuybackItemInfo", 1 },
        { "C_MerchantFrame.GetBuybackItemID", 1 }, "C_MerchantFrame.GetNumJunkItems", "C_MerchantFrame.IsSellAllJunkEnabled" })
end

P.B5 = function(run)
    local n = run.merchantItems or run:Call("GetMerchantNumItems"):Num() or 0
    for i = 1, math.min(n, 5) do Tooltip(run, "B5", nil, "C_TooltipInfo.GetMerchantItem", i) end
    -- ein eben gekauftes Stück (rückgebbar) in der Tasche
    for _, item in ipairs(BagItems(run, 60)) do
        local info = run:Call("C_Container.GetContainerItemPurchaseInfo", item.bag, item.slot, false)
        if info:Tab() then
            Many(run, "B5", { { "C_Container.GetContainerItemPurchaseInfo", item.bag, item.slot, false },
                { "C_Container.GetContainerItemPurchaseItem", item.bag, item.slot, 1, false },
                { "C_Container.GetContainerItemPurchaseCurrency", item.bag, item.slot, 1, false } })
            break
        end
    end
end

P.C1 = function(run)
    NpcProbe(run, "C1", "npc")
    UnitIdentity(run, "C1", "pet")
    Many(run, "C1", { "C_Trainer.GetTrainerType", "C_Trainer.GetCategorizeTrainerUI", "IsTradeskillTrainer",
        { "GetTrainerServiceTypeFilter", "available" }, { "GetTrainerServiceTypeFilter", "unavailable" },
        { "GetTrainerServiceTypeFilter", "used" }, "GetTrainerServiceStepIndex", "GetNumTrainerServices" })
end

P.C2 = function(run)
    local n = run:Call("GetNumTrainerServices"):Num() or 0
    for start = 1, math.min(n, 30), 10 do
        run:Step(function(r)
            for i = start, math.min(start + 9, n, 30) do
                Many(r, "C2", { { "GetTrainerServiceInfo", i }, { "GetTrainerServiceCost", i }, { "GetTrainerServiceSkillReq", i },
                    { "GetTrainerServiceNumAbilityReq", i }, { "GetTrainerServiceAbilityReq", i, 1 },
                    { "GetTrainerServiceSkillLine", i } })
            end
        end)
    end
end

P.C3 = function(run)
    local n = run:Call("GetNumTrainerServices"):Num() or 0
    for i = 1, math.min(n, 10) do Tooltip(run, "C3", nil, "C_TooltipInfo.GetTrainerService", i) end
end

P.C4 = function(run)
    run:Q("C4", "GetTrainerTradeskillRankValues")
end

P.D1 = function(run)
    local n = run:Q("D1", "GetInboxNumItems"):Num() or 0
    run:Q("D1", "C_Mail.CanCheckInbox")
    for i = 1, math.min(n, 5) do
        -- Absender als Pseudonym, Betreff nur als Länge; der Brieftext wird nie gelesen
        run:With({ ret = { [3] = "player", [4] = true } }):Q("D1", "GetInboxHeaderInfo", i)
        Many(run, "D1", { { "HasInboxItem", i, 1 }, { "GetInboxItem", i, 1 }, { "GetInboxItemLink", i, 1 },
            { "C_Mail.HasInboxMoney", i } })
        run:With({ ret = { [3] = "player" } }):Q("D1", "GetInboxInvoiceInfo", i)
    end
end

P.D2 = function(run)
    Many(run, "D2", { { "GetSendMailItem", 1 }, { "GetSendMailItemLink", 1 }, "GetSendMailPrice", "GetSendMailMoney" })
end

P.E1 = function(run)
    Many(run, "E1", { "C_AuctionHouse.SupportsCopperValues", "C_AuctionHouse.FavoritesAreAvailable",
        "C_AuctionHouse.IsThrottledMessageSystemReady", "C_WowTokenUI.ShouldDisplayInAuctionHouse" })
    for band = 0, 3 do run:Q("E1", "C_AuctionHouse.GetTimeLeftBandInfo", band) end
    UnitIdentity(run, "E1", "npc")
end

P.E2 = function(run)
    local results = run:Call("C_AuctionHouse.GetBrowseResults"):Tab()
    run:Note("E2", "#GetBrowseResults", results and #results or nil)
    run:With({ samples = 3 }):Q("E2", "C_AuctionHouse.GetBrowseResults")
    run.browse = results
end

P.E3 = function(run)
    local key = run:Q("E3", "C_AuctionHouse.MakeItemKey", 2589):Tab()
    if key then
        Many(run, "E3", { { "C_AuctionHouse.GetItemKeyInfo", key }, { "C_AuctionHouse.GetItemKeyRequiredLevel", key },
            { "C_AuctionHouse.GetExtraBrowseInfo", key }, { "C_AuctionHouse.GetItemKeySampleLink", key } })
    end
    -- Schlüssel eines Taschenstücks (ideal: ein grünes Stück „des …“)
    local mixin = Tab(rawget(_G, "ItemLocation"))
    local create = Field(mixin, "CreateFromBagAndSlot")
    for _, item in ipairs(BagItems(run, 80)) do
        local quality = run:Call("C_Item.GetItemQualityByID", item.id):Num()
        local equip = run:Call("C_Item.IsEquippableItem", item.id):True()
        if equip and quality and quality >= 2 then
            local ok, loc = pcall(function() return create(mixin, item.bag, item.slot) end)
            if ok and Tab(loc) then run:Tag(("ItemLocation %d:%d"):format(item.bag, item.slot)):Q("E3", "C_AuctionHouse.GetItemKeyFromItem", loc) end
            break
        end
    end
end

-- Einzelergebnisse gibt es nur für die angeklickte Zeile – und die Reihenfolge der Zeilen bestimmt das Auktionshaus.
-- Deshalb die ersten zehn Zeilen durchsehen und die erste mit Ergebnissen festhalten (sonst die erste Zeile: die Nullen
-- sind dann die Antwort).
P.E4 = function(run)
    local results = run.browse or run:Call("C_AuctionHouse.GetBrowseResults"):Tab()
    local rows = math.min(results and #results or 0, 10)
    local row = rows > 0 and 1 or nil
    for i = 1, rows do
        local key = Tab(Field(Tab(results[i]), "itemKey"))
        local id = Num(Field(key, "itemID"))
        local commodities = id and run:Call("C_AuctionHouse.GetNumCommoditySearchResults", id):Num() or 0
        local items = key and run:Call("C_AuctionHouse.GetNumItemSearchResults", key):Num() or 0
        if commodities > 0 or items > 0 then
            row = i
            break
        end
    end
    run:Note("E4", "Zeile mit Einzelergebnissen (von den ersten " .. rows .. ")", row)
    local key = row and Tab(Field(Tab(results[row]), "itemKey"))
    local id = Num(Field(key, "itemID"))
    local tag = "Zeile " .. tostring(row)
    if id then
        local commodities = run:Tag(tag):Q("E4", "C_AuctionHouse.GetNumCommoditySearchResults", id):Num() or 0
        if commodities > 0 then run:Tag(tag):Q("E4", "C_AuctionHouse.GetCommoditySearchResultInfo", id, 1) end
    end
    if key then
        local items = run:Tag(tag):Q("E4", "C_AuctionHouse.GetNumItemSearchResults", key):Num() or 0
        if items > 0 then run:Tag(tag):Q("E4", "C_AuctionHouse.GetItemSearchResultInfo", key, 1) end
    end
end

P.E5 = function(run)
    Many(run, "E5", { "C_AuctionHouse.GetNumOwnedAuctions", "C_AuctionHouse.GetOwnedAuctions", "C_AuctionHouse.GetNumBids",
        "C_AuctionHouse.GetBids" })
    for duration = 1, 3 do run:Q("E5", "C_AuctionHouse.CalculateCommodityDeposit", 2589, duration, 20) end
end

---------------------------------------------------------------------------
-- F – mit Ziel
---------------------------------------------------------------------------

P.F1 = function(run) run.targetGUID = UnitIdentity(run, "F1", "target") end
P.F2 = function(run) UnitKind(run, "F2", "target") end

P.F4 = function(run)
    Many(run, "F4", { { "UnitPosition", "target" }, { "UnitDistanceSquared", "target" } })
    local id = run:Call("UnitCreatureID", "target"):Num()
    if id then run:Q("F4", "ClosestUnitPosition", id) end
end

P.F5 = function(run)
    UnitTooltip(run, "F5", "target")
    Many(run, "F5", { { "UnitIsQuestBoss", "target" }, { "C_QuestLog.UnitIsRelatedToActiveQuest", "target" } })
end

P.F6 = function(run)
    Many(run, "F6", { { "UnitIsDead", "target" }, { "UnitIsCorpse", "target" }, { "UnitHasLootInteraction", "target" },
        { "UnitIsTapDenied", "target" }, { "CanInspect", "target" } })
    if run.targetGUID then run:Q("F6", "CanLootUnit", run.targetGUID) end
end

-- Tooltip unter der Maus (Erzader, Kraut, Truhe, NPC) und die Markierungen der Karte. Läuft mit „ziel“ und „allein“.
P.F8 = function(run)
    Tooltip(run, "F8", { cursor = true }, "C_TooltipInfo.GetWorldCursor")
    local map = MapID(run)
    local list = run:Q("F8", "C_VignetteInfo.GetVignettes"):Tab()
    for i = 1, math.min(list and #list or 0, 3) do
        local guid = Str(list[i])
        if guid then
            run:Q("F8", "C_VignetteInfo.GetVignetteInfo", guid)
            if map then run:Q("F8", "C_VignetteInfo.GetVignettePosition", guid, map) end
        end
    end
end

-- Plakette erschienen (nur bei laufendem Mitschnitt, höchstens zehn je Mitschnitt)
P.F8P = function(run)
    for i = 1, 5 do
        local unit = "nameplate" .. i
        if run:Call("UnitExists", unit):True() then
            Many(run, "F8", { { "UnitCreatureID", unit }, { "UnitLevel", unit }, { "UnitClassification", unit } })
        end
    end
end

---------------------------------------------------------------------------
-- G – im Kampf, danach, Beutefenster
---------------------------------------------------------------------------

P.G1 = function(run) Restrictions(run, "G1") end
P.G2 = function(run) UnitIdentity(run, "G2", "target") end

P.G3 = function(run)
    for _, unit in ipairs({ "player", "target" }) do
        Many(run, "G3", { { "UnitHealth", unit }, { "UnitHealthMax", unit }, { "UnitPower", unit }, { "UnitPowerMax", unit },
            { "UnitHealthPercent", unit } })
    end
    for power = 0, 4 do run:Q("G3", "C_Secrets.GetPowerTypeSecrecy", power) end
end

P.G4 = function(run)
    Many(run, "G4", { { "C_Container.GetContainerItemInfo", 0, 1 }, { "C_Item.GetItemCount", 6948 },
        { "C_Container.GetItemCooldown", 6948 }, { "GetInventoryItemID", "player", 16 }, "GetMoney" })
end

P.G5 = function(run)
    for i = 1, 5 do run:Q("G5", "UnitStat", "player", i) end
    Many(run, "G5", { { "UnitArmor", "player" }, { "GetCombatRating", 1 }, "GetCritChance" })
end

P.G6 = function(run)
    local spell = OwnSpells(run).learnedID
    if not spell then return run:Note("G6", "kein eigener Zauber gefunden", nil) end
    Many(run, "G6", { { "C_Spell.GetSpellCooldown", spell }, { "C_Spell.GetSpellCharges", spell }, { "C_Spell.IsSpellUsable", spell },
        { "C_Spell.IsSpellInRange", spell, "target" } })
    -- Nachprobe: ein Zauber, dessen Abklingzeit gerade LÄUFT (isActive ist auch im Kampf lesbar; außerhalb hilft die
    -- Dauer, die globale Abklingzeit von 1,5 s ausgenommen) – bisher nur am Auto-Angriff ohne Abklingzeit gemessen
    local running
    for _, id in ipairs(OwnSpells(run).ids) do
        if id ~= spell then
            local cd = run:Call("C_Spell.GetSpellCooldown", id):Tab()
            if cd and (Field(cd, "isActive") == true or (Num(Field(cd, "duration")) or 0) > 1.5) then
                running = id
                break
            end
        end
    end
    if running then
        run:Tag("Abklingzeit läuft")
        Many(run, "G6", { { "C_Spell.GetSpellCooldown", running }, { "C_Spell.GetSpellCharges", running },
            { "C_Spell.IsSpellUsable", running } })
    else
        run:Note("G6", "kein eigener Zauber mit laufender Abklingzeit", nil)
    end
end

-- Nachprobe: ALLE Aura-Abfragen, jede für sich (run:Q fängt den Fehler je Funktion ab) – im Kampf warf
-- GetUnitAuraInstanceIDs einen Fehler („Auras cannot be accessed when secret while tainted“), und danach fragte die
-- Probe nichts mehr. Jetzt hängt keine Abfrage an einer anderen; die Nummer der ersten Aura kommt notfalls aus
-- GetAuraDataByIndex.
local function Auras(run, id, unit, filter)
    Many(run, id, { "C_Secrets.ShouldAurasBeSecret", { "C_UnitAuras.GetAuraDataByIndex", unit, 1, filter },
        { "C_UnitAuras.GetBuffDataByIndex", unit, 1 }, { "C_UnitAuras.GetDebuffDataByIndex", unit, 1 },
        { "C_UnitAuras.GetUnitAuras", unit, filter } })
    local slots = run:Q(id, "C_UnitAuras.GetAuraSlots", unit, filter)
    local slot = slots:Num(2)   -- 1: Fortsetzungsmarke, danach die Plätze
    if slot then run:Q(id, "C_UnitAuras.GetAuraDataBySlot", unit, slot) end
    local list = run:Q(id, "C_UnitAuras.GetUnitAuraInstanceIDs", unit, filter):Tab()
    local aura = list and Num(list[1])
    if not aura then aura = Num(Field(run:Call("C_UnitAuras.GetAuraDataByIndex", unit, 1, filter):Tab(), "auraInstanceID")) end
    if not aura then return end
    local data = run:Q(id, "C_UnitAuras.GetAuraDataByAuraInstanceID", unit, aura):Tab()
    run:Q(id, "C_UnitAuras.IsAuraFilteredOutByInstanceID", unit, aura, filter)
    local spellID = Num(Field(data, "spellId"))
    if unit == "player" and spellID then run:Q(id, "C_UnitAuras.GetPlayerAuraBySpellID", spellID) end
    run:Q(id, "C_UnitAuras.GetAuraBaseDuration", unit, aura)
    local duration = run:Q(id, "C_UnitAuras.GetAuraDuration", unit, aura):Tab()
    local has = Field(duration, "HasSecretValues")
    if type(has) == "function" then
        run:Record(id, "AuraDuration:HasSecretValues", nil, run:Call(function() return has(duration) end))
    end
end

P.G7 = function(run)
    Auras(run, "G7", "player", "HELPFUL")
    Auras(run, "G7", "target", "HARMFUL|PLAYER")
end

P.G8 = function(run)
    Many(run, "G8", { { "C_Secrets.ShouldUnitSpellCastingBeSecret", "target" }, { "UnitCastingInfo", "target" },
        { "UnitChannelInfo", "target" }, { "UnitThreatSituation", "player", "target" },
        { "UnitDetailedThreatSituation", "player", "target" } })
end

P.G9 = function(run)
    Many(run, "G9", { "C_DamageMeter.IsDamageMeterAvailable", "C_DamageMeter.GetAvailableCombatSessions" })
    local session = EnumValue("DamageMeterSessionType", "Current")
    local taken, enemy = EnumValue("DamageMeterType", "DamageTaken"), EnumValue("DamageMeterType", "EnemyDamageTaken")
    if session == nil then return end
    -- Quellen sind Spieler (Gruppenmitglieder) oder Gegner: der Name bleibt nur, wenn die GUID daneben einem NPC gehört
    local function Rules() return { samples = 3, fields = { name = "unit" } } end
    if enemy ~= nil then run:Tag("Current, EnemyDamageTaken"):With(Rules()):Q("G9", "C_DamageMeter.GetCombatSessionFromType", session, enemy) end
    if taken ~= nil then
        run:Tag("Current, DamageTaken"):With(Rules()):Q("G9", "C_DamageMeter.GetCombatSessionFromType", session, taken)
        local guid = run:Call("UnitGUID", "player"):Str()
        if guid then
            run:Tag("Current, DamageTaken, eigene GUID"):With(Rules()):Q("G9", "C_DamageMeter.GetCombatSessionSourceFromType", session, taken, guid)
        end
    end
end

P.G10 = function(run)
    local n = run:Q("G10", "GetNumLootItems"):Num() or 0
    run:Q("G10", "IsFishingLoot")
    for slot = 1, math.min(n, 16) do
        Many(run, "G10", { { "GetLootSlotType", slot }, { "GetLootSlotInfo", slot }, { "GetLootSlotLink", slot } })
        local source = run:Q("G10", "GetLootSourceInfo", slot)
        -- Paare (GUID, Menge): Art jeder GUID, Zahl der Paare
        local kinds, firstGuid = {}, nil
        for i = 1, source.n or 0, 2 do
            local guid = source:Str(i)
            if guid then
                kinds[#kinds + 1] = guid:match("^([^%-]+)") or "?"
                firstGuid = firstGuid or guid
            else
                kinds[#kinds + 1] = "?"
            end
        end
        if source.ok then run:Tag("Platz " .. slot):Note("G10", "Beutequellen: Rückgaben, Arten", source.n, kinds) end
        if firstGuid and slot <= 3 then
            run:Q("G10", "C_CreatureInfo.GetCreatureID", firstGuid)
            run:Q("G10", "ezCore.NpcID", firstGuid)
            if firstGuid:find("^Item") then
                run:Q("G10", "C_Item.GetItemIDByGUID", firstGuid)
                run:Q("G10", "C_Item.GetItemLinkByGUID", firstGuid)
            end
        end
    end
    if n > 0 then Tooltip(run, "G10", nil, "C_TooltipInfo.GetLootItem", 1) end
    Many(run, "G10", { { "UnitGUID", "target" }, { "UnitIsDead", "target" }, { "UnitHasLootInteraction", "target" } })
end

-- LOOT_OPENED nach LOOT_READY: nur noch, ob sich Zahl und erster Platz geändert haben (der volle Durchgang lief schon)
P.G10O = function(run)
    local n = run:Q("G10", "GetNumLootItems"):Num() or 0
    if n > 0 then Many(run, "G10", { { "GetLootSlotInfo", 1 }, { "GetLootSourceInfo", 1 } }) end
end

---------------------------------------------------------------------------
-- H – Gruppe, I – Bank
---------------------------------------------------------------------------

P.H1 = function(run)
    Many(run, "H1", { "IsInGroup", "IsInRaid", "GetNumGroupMembers", "GetNumSubgroupMembers",
        { "UnitGroupRolesAssigned", "player" }, { "UnitGroupRolesAssigned", "party1" } })
    run:With({ ret = { [1] = "player" } }):Q("H1", "GetRaidRosterInfo", 1)
end

P.H2 = function(run)
    Many(run, "H2", { "C_PartyInfo.GetLootMethod", "GetLootThreshold", "GetActiveLootRollIDs" })
    local rolls = run:Call("GetActiveLootRollIDs"):Tab()
    local roll = rolls and Num(rolls[1])
    if roll then
        run:Q("H2", "GetLootRollItemInfo", roll)
        run:Q("H2", "GetLootRollItemLink", roll)
        run:Q("H2", "C_Loot.GetLootRollDuration", roll)
    end
end

P.H3 = function(run)
    Many(run, "H3", { { "C_Secrets.ShouldUnitIdentityBeSecret", "party1" } })
    local guid = run:Q("H3", "UnitGUID", "party1"):Str()
    -- Name und Realm des Mitglieds immer als Pseudonym – auch wenn es eben erst dazugekommen ist
    run:With({ ret = { [1] = "player", [2] = "realm" } }):Q("H3", "UnitName", "party1")
    Many(run, "H3", { { "UnitClass", "party1" }, { "UnitIsConnected", "party1" },
        { "UnitPosition", "party1" }, { "UnitDistanceSquared", "party1" } })
    if guid then run:With({ ret = { [6] = "player", [7] = "realm" } }):Q("H3", "GetPlayerInfoByGUID", guid) end
end

-- H3 im Kampf (Teil der Kampf-Station): Sind Name, GUID und Klasse eines Gruppenmitglieds im Kampf gesperrt?
P.H3G = function(run)
    if run:Call("IsInGroup"):True() then P.H3(run) end
end

P.H4 = function(run)
    local infos = run:Q("H4", "C_LootHistory.GetAllEncounterInfos"):Tab()
    local encounter = Num(Field(Tab(infos and infos[1]), "encounterID"))
    if encounter then run:Q("H4", "C_LootHistory.GetSortedDropsForEncounter", encounter) end
end

P.I1 = function(run)
    Many(run, "I1", { "C_Bank.FetchViewableBankTypes", { "C_Bank.CanViewBank", 0 }, { "C_Bank.CanViewBank", 2 },
        { "C_Bank.FetchNumPurchasedBankTabs", 0 }, { "C_Bank.FetchMaxNumBankTabs", 0 },
        { "C_Bank.FetchPurchasedBankTabData", 0 }, { "C_Bank.FetchPurchasedBankTabData", 2 },
        { "C_Bank.FetchDepositedMoney", 2 }, "C_Bank.ShouldUsePlayerBagsInBank",
        { "C_Container.GetContainerNumSlots", -2 }, { "C_Container.GetContainerItemID", -2, 1 } })
    for bag = 6, 23 do
        local slots = run:Q("I1", "C_Container.GetContainerNumSlots", bag):Num() or 0
        if slots > 0 then run:Q("I1", "C_Container.GetContainerItemInfo", bag, 1) end
    end
end

---------------------------------------------------------------------------
-- J – Berufe
---------------------------------------------------------------------------

P.J1 = function(run)
    Many(run, "J1", { "C_TradeSkillUI.IsTradeSkillReady", "C_TradeSkillUI.IsTradeSkillLinked", "C_TradeSkillUI.IsNPCCrafting",
        "C_TradeSkillUI.GetBaseProfessionInfo", "C_TradeSkillUI.GetChildProfessionInfo", "C_TradeSkillUI.GetProfessionChildSkillLineID",
        "C_TradeSkillUI.GetAllRecipeIDs", "C_TradeSkillUI.GetFilteredRecipeIDs", "C_TradeSkillUI.GetShowLearned",
        "C_TradeSkillUI.GetShowUnlearned", "C_TradeSkillUI.GetOnlyShowMakeableRecipes", "C_TradeSkillUI.GetOnlyShowSkillUpRecipes",
        "C_TradeSkillUI.GetRecipeItemNameFilter", "C_TradeSkillUI.AreAnyInventorySlotsFiltered" })
end

local function RecipeIDs(run)
    return run:Call("C_TradeSkillUI.GetAllRecipeIDs"):Tab() or run:Call("C_TradeSkillUI.GetFilteredRecipeIDs"):Tab() or {}
end

-- gelernt/ungelernt, je Linie, mit Vorgänger; drei Beispiele: mit Werkzeug, Verzauberung, Abklingzeit
P.J2 = function(run)
    local ids = RecipeIDs(run)
    local acc = { recipes = #ids, learned = 0, unlearned = 0, previous = 0, byLine = {} }
    run.recipePick = {}
    for start = 1, math.min(#ids, 1500), 150 do
        run:Step(function(r)
            for i = start, math.min(start + 149, #ids, 1500) do
                local id = Num(ids[i])
                local info = id and r:Call("C_TradeSkillUI.GetRecipeInfo", id) or nil
                if info and info:Tab() then
                    if info:Field("learned") == true then acc.learned = acc.learned + 1 else acc.unlearned = acc.unlearned + 1 end
                    if Num(info:Field("previousRecipeID")) then acc.previous = acc.previous + 1 end
                    local line = r:Call("C_TradeSkillUI.GetTradeSkillLineForRecipe", id):Num()
                    if line then acc.byLine[line] = (acc.byLine[line] or 0) + 1 end
                    local pick = r.recipePick
                    pick.any = pick.any or id
                    if info:Field("isEnchantingRecipe") == true then pick.enchant = pick.enchant or id end
                    if info:Field("isSalvageRecipe") == true then pick.salvage = pick.salvage or id end
                    if info:Field("learned") == true then pick.learned = pick.learned or id end
                    if not pick.cooldown and r:Call("C_TradeSkillUI.GetRecipeCooldown", id):Num() then pick.cooldown = id end
                end
            end
        end)
    end
    run:Step(function(r)
        r:Note("J2", "Rezepte", { recipes = acc.recipes, learned = acc.learned, unlearned = acc.unlearned, mitVorgaenger = acc.previous },
            acc.byLine)
        local any = r.recipePick.any
        if any then r:Tag("ist die recipeID eine spellID?"):Q("J2", "C_Spell.GetSpellName", any) end
        -- für A13 (eigenes Rezept bei geschlossenem Fenster, Zerlegen mit recipeID): nur die Nummern
        if r.recipePick.learned then Probe.Hint("recipe", r.recipePick.learned) end
        if r.recipePick.salvage then Probe.Hint("salvage", r.recipePick.salvage) end
    end)
end

P.J3 = function(run)
    local pick = run.recipePick or {}
    local seen = {}
    for _, id in ipairs({ pick.any or false, pick.enchant or false, pick.cooldown or false }) do
        if id and not seen[id] then
            seen[id] = true
            run:Step(function(r)
                r:With({ maxFields = 80 }):Q("J3", "C_TradeSkillUI.GetRecipeInfo", id)
                Many(r, "J3", { { "C_TradeSkillUI.GetRecipeSchematic", id, false }, { "C_TradeSkillUI.GetRecipeOutputItemData", id },
                    { "C_TradeSkillUI.GetRecipeCooldown", id }, { "C_TradeSkillUI.GetRecipeSourceText", id },
                    { "C_TradeSkillUI.GetRecipeRequirements", id }, { "C_TradeSkillUI.GetRecipeLink", id },
                    { "C_TradeSkillUI.GetRecipeItemLink", id } })
            end)
        end
    end
    run:Step(function(r)
        -- Nachprobe: ein Rezept eines anderen Berufs (2330, Alchimie) bei OFFENEM Berufefenster – Gegenstück zu A13
        r:Tag("Rezept 2330 bei offenem Fenster")
        Many(r, "J3", { { "C_TradeSkillUI.GetRecipeInfo", 2330 }, { "C_TradeSkillUI.GetRecipeSchematic", 2330, false },
            { "C_TradeSkillUI.IsRecipeProfessionLearned", 2330 } })
    end)
    run:Step(function(r)
        -- der Link des eigenen Berufs nennt den Charakter: maskiert der Filter
        r:Q("J3", "C_TradeSkillUI.GetTradeSkillListLink")
        local categories = r:Q("J3", "C_TradeSkillUI.GetCategories")
        local category = categories:Num(1)
        if category then r:Q("J3", "C_TradeSkillUI.GetCategoryInfo", category) end
        for source = 1, 12 do r:Q("J3", "C_TradeSkillUI.IsAnyRecipeFromSource", source) end
    end)
end

-- Rezept-Gegenstand in der Tasche (Klasse 9)
P.J6 = function(run)
    for _, item in ipairs(BagItems(run, 120)) do
        local instant = run:Call("C_Item.GetItemInfoInstant", item.id)
        if instant:Num(6) == 9 then
            run:Q("J6", "C_Item.GetItemSpell", item.id)
            run:Q("J6", "C_Item.GetItemInfoInstant", item.id)
            Tooltip(run, "J6", nil, "C_TooltipInfo.GetBagItem", item.bag, item.slot)
            return
        end
    end
    run:Note("J6", "kein Rezept in der Tasche", nil)
end

---------------------------------------------------------------------------
-- K – Quests und Gespräche
---------------------------------------------------------------------------

-- Von Hand (ohne Ereignis) nur, wenn das passende Fenster offen ist
local function WindowOpen(run, ...)
    if run.ev then return true end
    local open = Probe.OpenWindows()
    for i = 1, select("#", ...) do
        if open[(select(i, ...))] then return true end
    end
    return false
end

P.K1 = function(run)
    if not WindowOpen(run, "quest") then return end
    local quest = run:Q("K1", "GetQuestID"):Num()
    -- Texte der Quest: nur die Längen
    for _, path in ipairs({ "GetTitleText", "GetQuestText", "GetObjectiveText", "GetProgressText", "GetRewardText" }) do
        run:With({ text = true }):Q("K1", path)
    end
    Many(run, "K1", { { "UnitGUID", "questnpc" }, { "UnitGUID", "npc" }, { "UnitIsGameObject", "npc" }, { "UnitCreatureID", "npc" },
        "QuestGetAutoAccept", "QuestIsFromAreaTrigger", "GetQuestPortraitGiver", "GetNumQuestRewards", "GetNumQuestChoices",
        { "GetQuestItemInfo", "reward", 1 }, { "GetQuestItemInfo", "choice", 1 }, { "GetQuestItemLink", "reward", 1 },
        { "GetQuestItemLink", "choice", 1 }, "GetRewardMoney", "GetRewardXP" })
    if quest and quest > 0 then run:Q("K1", "C_QuestInfoSystem.GetQuestRewardSpells", quest) end
end

P.K2 = function(run)
    if not WindowOpen(run, "quest") then return end
    Many(run, "K2", { "GetQuestID", "GetNumQuestItems", { "GetQuestItemInfo", "required", 1 }, { "GetQuestItemLink", "required", 1 },
        "GetQuestMoneyToGet", "IsQuestCompletable" })
end

P.K3 = function(run)
    if not WindowOpen(run, "gossip", "quest") then return end
    Many(run, "K3", { "C_GossipInfo.GetOptions", "C_GossipInfo.GetAvailableQuests", "C_GossipInfo.GetActiveQuests",
        "GetNumAvailableQuests", "GetNumActiveQuests", { "GetAvailableQuestInfo", 1 },
        { "GetActiveQuestID", 1 }, { "UnitGUID", "npc" }, { "UnitCreatureID", "npc" } })
    run:With({ text = true }):Q("K3", "C_GossipInfo.GetText")
end

-- Art des Fensters samt NPC (bei PLAYER_INTERACTION_MANAGER_FRAME_SHOW)
P.K4 = function(run)
    Many(run, "K4", { { "UnitGUID", "npc" }, { "UnitCreatureID", "npc" }, { "UnitIsGameObject", "npc" } })
end

P.K5 = function(run)
    local map = MapID(run)
    if not map then return end
    local poi = run:Q("K5", "C_GossipInfo.GetPoiForUiMapID", map):Num()
    if poi then run:Q("K5", "C_GossipInfo.GetPoiInfo", map, poi) end
end

---------------------------------------------------------------------------
-- L – Flug, M – Dungeon, N – Tod
---------------------------------------------------------------------------

P.L1 = function(run)
    local shown = {}
    for _, name in ipairs({ "TaxiFrame", "FlightMapFrame" }) do
        local frame = rawget(_G, name)
        local isShown = Core.Peek(frame, "IsShown")
        local ok, yes = pcall(function() return isShown(frame) end)
        shown[name] = ok and yes == true
    end
    run:Note("L1", "Fenster zu sehen", shown)
    local map = run:Q("L1", "GetTaxiMapID"):Num()
    if map then run:With({ samples = 3 }):Q("L1", "C_TaxiMap.GetAllTaxiNodes", map) end
    local n = run:Q("L1", "NumTaxiNodes"):Num() or 0
    for start = 1, math.min(n, 40), 10 do
        run:Step(function(r)
            for i = start, math.min(start + 9, n, 40) do
                Many(r, "L1", { { "TaxiNodeName", i }, { "TaxiNodeGetType", i }, { "TaxiNodePosition", i }, { "TaxiNodeCost", i } })
                local routes = r:Q("L1", "GetNumRoutes", i):Num() or 0
                if routes > 0 and routes < 20 then
                    r:Q("L1", "TaxiIsDirectFlight", i)
                    r:Q("L1", "TaxiGetNodeSlot", i, 1, true)
                    r:Q("L1", "TaxiGetNodeSlot", i, 1, false)
                end
            end
        end)
    end
    run:Q("L1", "UnitGUID", "npc")
    run:Q("L1", "UnitCreatureID", "npc")
end

-- Nachprobe: Flugknoten für JEDEN Kontinent und die oberste Karte – Anzahl und alle Nummern (vorher nur die ersten
-- zwei Listenelemente der eigenen Zone und ihres Kontinents). Nur aufzählen: ob der Charakter einen Knoten kennt,
-- sagt die Liste nicht (isUndiscovered taugt dafür nicht).
local function TaxiContinents(run, map)
    local top = map
    for _ = 1, 10 do
        local parent = Num(run:Call("C_Map.GetMapInfo", top):Field("parentMapID"))
        if not parent or parent == 0 then break end
        top = parent
    end
    local continent = EnumValue("UIMapType", "Continent") or 2
    local children = run:Call("C_Map.GetMapChildrenInfo", top, continent, true):Tab() or {}
    local maps = { top }
    for i = 1, math.min(#children, 8) do
        local id = Num(Field(Tab(children[i]), "mapID"))
        if id and id ~= top then maps[#maps + 1] = id end
    end
    for _, id in ipairs(maps) do
        local nodes = run:Call("C_TaxiMap.GetTaxiNodesForMap", id):Tab()
        local ids = {}
        for i = 1, math.min(nodes and #nodes or 0, 400) do
            local node = Num(Field(Tab(nodes[i]), "nodeID"))
            if node then ids[#ids + 1] = node end
        end
        table.sort(ids)
        run:Tag(("Karte %d%s"):format(id, id == top and " (oberste)" or "")):With({ samples = 400 })
            :Note("L2", "Flugknoten je Kontinent: Anzahl, Nummern", nodes and #nodes or nil, ids)
    end
end

P.L2 = function(run)
    local map = MapID(run)
    if not map then return end
    run:With({ samples = 3 }):Q("L2", "C_TaxiMap.GetTaxiNodesForMap", map)
    run:Q("L2", "C_TaxiMap.ShouldMapShowTaxiNodes", map)
    local parent = Num(run:Call("C_Map.GetMapInfo", map):Field("parentMapID"))
    if parent and parent > 0 then run:Tag("Kontinent"):With({ samples = 3 }):Q("L2", "C_TaxiMap.GetTaxiNodesForMap", parent) end
    Many(run, "L2", { { "UnitOnTaxi", "player" } })
    run:Step(function(r) TaxiContinents(r, map) end)
end

P.M1 = function(run)
    Many(run, "M1", { "GetInstanceInfo", "IsInInstance", { "C_Map.GetBestMapForUnit", "player" }, { "UnitPosition", "player" } })
    local map = MapID(run)
    if map then
        run:Q("M1", "C_Map.GetMapInfo", map)
        run:Q("M1", "C_Map.GetPlayerMapPosition", map, "player")
    end
    Restrictions(run, "M1")
end

P.M3 = function(run)
    Many(run, "M3", { "C_EncounterEvents.GetEventList", "C_InstanceEncounter.IsEncounterInProgress", "IsEncounterInProgress" })
end

P.M5 = function(run)
    run:Q("M5", "C_CVar.GetCVar", "showDungeonEntrancesOnMap")
    local map = MapID(run)
    local entrances = map and run:Q("M5", "C_EncounterJournal.GetDungeonEntrancesForMap", map):Tab()
    local journal = Num(Field(Tab(entrances and entrances[1]), "journalInstanceID"))
    if journal then run:Q("M5", "EJ_GetInstanceInfo", journal) end
    -- Pins der Eingänge auf Blizzards Weltkarte (nur gezählt)
    -- (kein eigener Rahmen aus dieser Vorlage, deshalb steht sie nicht in Core.SELFTEST: der Name ist hier zusammengesetzt)
    local frame = Tab(rawget(_G, "WorldMapFrame"))
    local pinName = "DungeonEntrancePin" .. "Template"
    local enumerate = Field(frame, "EnumeratePinsBy" .. "Template")
    if type(enumerate) == "function" then
        local ok, count = pcall(function()
            local n = 0
            for _ in enumerate(frame, pinName) do n = n + 1 end
            return n
        end)
        run:Note("M5", "Pins " .. pinName, ok and count or nil)
    end
    local saved = run:Q("M5", "GetNumSavedInstances"):Num() or 0
    if saved > 0 then run:Q("M5", "GetSavedInstanceInfo", 1) end
    run:Q("M5", "GetInstanceInfo")
end

P.N1 = function(run)
    local map = MapID(run)
    Many(run, "N1", { { "UnitIsDeadOrGhost", "player" }, { "UnitIsGhost", "player" }, "C_DeathInfo.GetSelfResurrectOptions",
        "GetReleaseTimeRemaining", "C_DeathRecap.HasRecapEvents", "C_DeathRecap.GetRecapEvents" })
    if map then
        run:Q("N1", "C_DeathInfo.GetCorpseMapPosition", map)
        run:Q("N1", "C_DeathInfo.GetDeathReleasePosition", map)
    end
end

P.N2 = function(run)
    local map = MapID(run)
    Many(run, "N2", { "GetCorpseRecoveryDelay", "C_SuperTrack.IsSuperTrackingCorpse", { "UnitPosition", "player" } })
    if map then
        run:Q("N2", "C_DeathInfo.GetGraveyardsForMap", map)
        run:Q("N2", "C_Map.GetPlayerMapPosition", map, "player")
    end
end

---------------------------------------------------------------------------
-- Stationen: Wörter für /ez probe <Wort>, Proben, wann sie passt
---------------------------------------------------------------------------

local function Exists(unit) return Probe.RunClass.Call(nil, "UnitExists", unit):True() end
local function Yes(path, ...) return Probe.RunClass.Call(nil, path, ...):True() end

-- Zielart einer Einheit für die Zählung der Automatik (Probe.Auto.KINDS): "F:player" (Spieler), "F:pet" (Begleiter eines
-- Spielers), "F:corpse" (tot), "F:elite" (Elite, selten, Weltboss), "F:enemy" (angreifbar), "F:npc" (freundlich);
-- nil, wenn es die Einheit nicht gibt oder der Client verschweigt, ob sie ein Spieler ist. Gesperrte Antworten gelten
-- als „nein“ (Result:True), verglichen wird nur Lesbares.
local ELITE = { elite = true, rareelite = true, rare = true, worldboss = true }
function Probe.TargetKind(unit)
    unit = unit or "target"
    if not Exists(unit) then return nil end
    local isPlayer = Probe.RunClass.Call(nil, "UnitIsPlayer", unit)
    if isPlayer.ok and Core.IsSecret(isPlayer[1]) then return nil end
    local privacy = UnitPrivacy(Probe.RunClass, unit)
    if privacy == "player" then return "F:player" end
    if privacy == "pet" then return "F:pet" end
    if Yes("UnitIsDead", unit) then return "F:corpse" end
    if ELITE[Probe.RunClass.Call(nil, "UnitClassification", unit):Str() or ""] then return "F:elite" end
    if Yes("UnitCanAttack", "player", unit) then return "F:enemy" end
    return "F:npc"
end

---------------------------------------------------------------------------
-- Nachträge vom 14.11.2026 (AH-07, SAM-29): was für die Ablösung von Auctionator und GatherMate noch fehlte.
-- E7, A20, A21 und G13 lesen nur; X6, X7 und X8 sind Sonderproben mit Rückfrage (unten bei den übrigen).
---------------------------------------------------------------------------

-- E7 – Auktionshaus: Gibt es die Sammelabfrage, und wie trennt der Client Waren von Einzelstücken?
P.E7 = function(run)
    for _, name in ipairs({ "SearchForItemKeys", "SearchForFavorites", "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery",
        "RequestMoreBrowseResults", "HasFullBrowseResults", "GetItemCommodityStatus", "StartCommoditiesPurchase",
        "ConfirmCommoditiesPurchase", "PostCommodity", "PostItem" }) do
        run:Has("E7", "C_AuctionHouse." .. name)
    end
    run:Val("E7", "Constants.AuctionConstants")
    run:Val("E7", "Enum.ItemCommodityStatus")
    run:Q("E7", "C_AuctionHouse.HasFullBrowseResults")
    -- Zeilen der Übersicht: Ware oder Einzelstück (GetItemKeyInfo.isCommodity)
    local results = run.browse or run:Call("C_AuctionHouse.GetBrowseResults"):Tab()
    local rows = math.min(results and #results or 0, 50)
    local commodity, single, unknown = 0, 0, 0
    for i = 1, rows do
        local key = Tab(Field(Tab(results[i]), "itemKey"))
        local flag
        if key then flag = run:Call("C_AuctionHouse.GetItemKeyInfo", key):Field("isCommodity") end
        if flag == true then
            commodity = commodity + 1
        elseif flag == false then
            single = single + 1
        else
            unknown = unknown + 1
        end
    end
    run:Note("E7", "Übersicht: Zeilen, Waren, Einzelstücke, unbekannt", rows, commodity, single, unknown)
    -- Taschenstücke: Ware oder Einzelstück, bevor etwas eingestellt wird (GetItemCommodityStatus)
    local mixin = Tab(rawget(_G, "ItemLocation"))
    local create = Field(mixin, "CreateFromBagAndSlot")
    local byStatus, asked = {}, 0
    for _, item in ipairs(BagItems(run, 40)) do
        local ok, loc = pcall(function() return create(mixin, item.bag, item.slot) end)
        if ok and Tab(loc) then
            asked = asked + 1
            local status
            if asked <= 3 then
                status = run:Tag(("ItemLocation %d:%d"):format(item.bag, item.slot)):Q("E7", "C_AuctionHouse.GetItemCommodityStatus", loc):Num()
            else
                status = run:Call("C_AuctionHouse.GetItemCommodityStatus", loc):Num()
            end
            byStatus[status or -1] = (byStatus[status or -1] or 0) + 1
        end
    end
    run:Note("E7", "Taschenstücke: gefragt, Anzahl je ItemCommodityStatus (-1 = keine Antwort)", asked, byStatus)
end

-- A20 – Minikarte: Sichtradius bei der jetzigen Zoomstufe (liest nur; je Zoomstufe: Sonderprobe X8)
P.A20 = function(run)
    Many(run, "A20", { "C_Minimap.GetViewRadius", "GetMinimapShape", "IsIndoors", "GetPlayerFacing", { "C_CVar.GetCVar", "rotateMinimap" } })
    local map = Tab(rawget(_G, "Minimap"))
    for _, method in ipairs({ "GetZoom", "GetZoomLevels", "GetWidth", "GetHeight", "GetEffectiveScale" }) do
        local fn = Field(map, method)
        if type(fn) == "function" then run:Tag("Minimap:" .. method):Q("A20", fn, map) else run:Note("A20", "Minimap:" .. method .. " fehlt", nil) end
    end
end

-- A21 – Weltkarte: Erscheint Blizzards Filterknopf (und die Legende)? Hält je Aufsatz der Karte fest, ob er zu sehen
-- ist und welche benannten Teile er hat (Blizzards eigene Schlüssel – daran erkennt man den Filterknopf), dazu die
-- Spielregeln, an denen sein Erscheinen hängen kann. Nur bei offener Weltkarte aussagekräftig.
P.A21 = function(run)
    local frame = Tab(rawget(_G, "WorldMapFrame"))
    local shown = Field(frame, "IsShown")
    run:Note("A21", "Weltkarte offen", type(shown) == "function" and run:Call(shown, frame):True() or false)
    local overlays = Tab(Field(frame, "overlayFrames"))
    run:Note("A21", "Aufsätze der Weltkarte (overlayFrames)", overlays and #overlays or nil)
    for i = 1, math.min(overlays and #overlays or 0, 12) do
        local overlay = Tab(overlays[i])
        local parts = {}
        if overlay then
            local ok = pcall(function()
                for key, value in pairs(overlay) do
                    if type(key) == "string" and key:match("^%u") and type(value) == "table" then parts[#parts + 1] = key end
                end
            end)
            if not ok then parts = { "?" } end
            table.sort(parts)
        end
        local isShown, objType = Field(overlay, "IsShown"), Field(overlay, "GetObjectType")
        run:Tag("Aufsatz " .. i):Note("A21", "Aufsatz: sichtbar, Art, benannte Teile",
            type(isShown) == "function" and run:Call(isShown, overlay):True() or false,
            type(objType) == "function" and run:Call(objType, overlay):Str() or nil, parts)
    end
    -- Spielregeln rund um die Weltkarte: welche es gibt und ob sie gelten
    local rules = Tab(Probe.Resolve("Enum.GameRule"))
    local found = 0
    if rules then
        local names = {}
        pcall(function()
            for name in pairs(rules) do
                if type(name) == "string" and (name:find("Map") or name:find("Tracking") or name:find("Legend")) then names[#names + 1] = name end
            end
        end)
        table.sort(names)
        for i = 1, math.min(#names, 20) do
            found = found + 1
            run:Tag("Enum.GameRule." .. names[i]):Q("A21", "C_GameRules.IsGameRuleActive", rules[names[i]])
        end
    end
    run:Note("A21", "Spielregeln mit Map, Tracking oder Legend im Namen", found)
    Many(run, "A21", { "C_Minimap.CanTrackBattlePets", { "C_CVar.GetCVar", "showDungeonEntrancesOnMap" }, { "C_CVar.GetCVar", "questPOI" } })
end

-- G13 – Beutefenster beim Angeln: Woher kommt die Beute – vom Schwimmer oder vom Fischschwarm? Je Platz die Art der
-- Quelle und die Nummer des Objekts (Feld 6 der GUID „GameObject-0-…-<Nummer>-…“, kein Charakterbezug).
P.G13 = function(run)
    if not run:Q("G13", "IsFishingLoot"):True() then return end
    local n = run:Call("GetNumLootItems"):Num() or 0
    local kinds, objects = {}, {}
    for slot = 1, math.min(n, 16) do
        local source = run:Call("GetLootSourceInfo", slot)
        for i = 1, source.n or 0, 2 do
            local guid = source:Str(i)
            local kind = guid and guid:match("^([^%-]+)") or "?"
            kinds[kind] = (kinds[kind] or 0) + 1
            local entry = guid and tonumber(guid:match("^GameObject%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
            if entry then objects[entry] = (objects[entry] or 0) + 1 end
        end
    end
    run:Tag("Angeln"):Note("G13", "Beutequellen: Plätze, Anzahl je Art, Anzahl je Objekt-Nummer", n, kinds, objects)
    Many(run, "G13", { { "UnitChannelInfo", "player" }, "GetSubZoneText" })
    Tooltip(run, "G13", { cursor = true }, "C_TooltipInfo.GetWorldCursor")
end

---------------------------------------------------------------------------
-- Nachprobe vom 14.11.2026 (docs/archiv/probe-ergebnis-2026-11-14.md, Abschnitt 9): was der erste Lauf nicht beantwortet hat.
-- C5 und F9 lesen nur; Probe.KindOf erkennt die Spielarten für die Automatik (Probe.Auto.KINDS) – auch die lesen nur.
---------------------------------------------------------------------------

-- C5 – Stand nach TRAINER_UPDATE (die Liste lädt nach; am ersten Lehrer war sie bei TRAINER_SHOW leer): Zahl der
-- Angebote, die drei Filter, die ersten Angebote; dazu die Linie des Berufs zur spellID aus dem Tooltip eines Angebots
P.C5 = function(run)
    if not WindowOpen(run, "trainer") then return end
    Many(run, "C5", { "GetNumTrainerServices", { "GetTrainerServiceTypeFilter", "available" },
        { "GetTrainerServiceTypeFilter", "unavailable" }, { "GetTrainerServiceTypeFilter", "used" } })
    local n = run:Call("GetNumTrainerServices"):Num() or 0
    for i = 1, math.min(n, 3) do run:Q("C5", "GetTrainerServiceInfo", i) end
    for i = 1, math.min(n, 10) do
        local spell = Num(Field(run:Call("C_TooltipInfo.GetTrainerService", i):Tab(), "id"))
        if spell then
            run:Tag("Angebot " .. i):Q("C5", "C_TradeSkillUI.GetTradeSkillLineForRecipe", spell)
            break
        end
    end
end

-- F9 – Spielobjekt in Reichweite (weiches Ziel „softinteract“: Erzader, Kraut, Truhe, Briefkasten): wer ist es?
P.F9 = function(run)
    UnitIdentity(run, "F9", "softinteract")
    Many(run, "F9", { { "UnitIsGameObject", "softinteract" }, { "C_Secrets.ShouldUnitIdentityBeSecret", "softinteract" } })
end

local function Call(path, ...) return Probe.RunClass.Call(nil, path, ...) end

-- Spielobjekt als weiches Ziel oder unter der Maus? Vignetten in der Nähe?
function Probe.ObjectNear()
    local guid = Call("UnitGUID", "softinteract"):Str()
    if guid and guid:find("^GameObject%-") then return true end
    local tip = Call("C_TooltipInfo.GetWorldCursor"):Tab()
    local object = EnumValue("TooltipDataType", "Object")
    return tip ~= nil and object ~= nil and Num(Field(tip, "type")) == object
end
function Probe.VignettesNear()
    local list = Call("C_VignetteInfo.GetVignettes"):Tab()
    return list ~= nil and #list > 0
end

-- Spielarten je Station (Probe.Auto.KINDS ohne req): Was gilt für den jetzigen Anlass? → Liste der Arten
Probe.KindOf.F = function() return Probe.TargetKind("target") end
Probe.KindOf.B = function()
    local list, limited, cost = {}, false, false
    local n = Call("GetMerchantNumItems"):Num() or 0
    for i = 1, math.min(n, 60) do
        local info = Call("C_MerchantFrame.GetItemInfo", i):Tab()
        if info then
            local stock = Num(Field(info, "numAvailable"))
            if stock and stock >= 0 then limited = true end
            if Field(info, "hasExtendedCost") == true then cost = true end
        end
        if limited and cost then break end
    end
    if limited then list[#list + 1] = "B:limited" end
    if cost then list[#list + 1] = "B:cost" end
    return list
end
local TRAINER_KIND = { profession = "C:prof", class = "C:class", pet = "C:pet" }
Probe.KindOf.C = function()
    local list = {}
    local tip = Call("C_TooltipInfo.GetUnit", "npc"):Tab()
    local line = Tab(Field(Tab(Field(tip, "lines")), 2))
    local npcs = Core.Npcs
    local kind = npcs and type(npcs.TrainerKind) == "function" and npcs.TrainerKind(line and Str(Field(line, "leftText"))) or nil
    if TRAINER_KIND[kind] then list[#list + 1] = TRAINER_KIND[kind] end
    local all = true
    for _, filter in ipairs({ "available", "unavailable", "used" }) do
        if not Call("GetTrainerServiceTypeFilter", filter):True() then all = false end
    end
    if all then list[#list + 1] = "C:all" end
    return list
end
Probe.KindOf.E = function()
    local results = Call("C_AuctionHouse.GetBrowseResults"):Tab()
    if not results or #results == 0 then return {} end
    local list = { "E:browse" }
    for i = 1, math.min(#results, 10) do
        local key = Tab(Field(Tab(results[i]), "itemKey"))
        local id = Num(Field(key, "itemID"))
        if (id and (Call("C_AuctionHouse.GetNumCommoditySearchResults", id):Num() or 0) > 0)
            or (key and (Call("C_AuctionHouse.GetNumItemSearchResults", key):Num() or 0) > 0) then
            list[#list + 1] = "E:result"
            break
        end
    end
    return list
end
Probe.KindOf.J = function()
    return Call("C_TradeSkillUI.GetShowUnlearned"):True() and { "J:unlearned" } or {}
end
Probe.KindOf.G10 = function()
    if Call("IsFishingLoot"):True() then return { "G10:fish" } end
    local n = Call("GetNumLootItems"):Num() or 0
    for slot = 1, math.min(n, 4) do
        local guid = Call("GetLootSourceInfo", slot):Str(1)
        local kind = guid and guid:match("^([^%-]+)")
        if kind == "GameObject" then return { "G10:object" } end
        if kind == "Item" then return { "G10:item" } end
        if kind then return {} end
    end
    return {}
end
Probe.KindOf.O = function()
    local list = {}
    if Probe.ObjectNear() then list[#list + 1] = "O:object" end
    if Probe.VignettesNear() then list[#list + 1] = "O:vignette" end
    return list
end

Probe.AddStation("A", { words = { "allein", "alone", "basis" },
    probes = { "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10", "A11", "A12", "A13", "A14", "A15", "A16", "A17",
        "A18", "A19", "A20", "L2", "F8", "G7" } })
Probe.AddStation("B", { words = { "händler", "haendler", "merchant", "vendor" }, probes = { "B1", "B2", "B3", "B4", "B5" },
    when = function(open) return open.merchant end })
Probe.AddStation("C", { words = { "lehrer", "trainer" }, probes = { "C1", "C2", "C3", "C4" },
    when = function(open) return open.trainer end })
Probe.AddStation("D", { words = { "post", "briefkasten", "mail" }, probes = { "D1", "D2" },
    when = function(open) return open.mail end })
Probe.AddStation("E", { words = { "auktion", "auktionshaus", "auction", "ah" }, probes = { "E1", "E2", "E3", "E4", "E5", "E7" },
    when = function(open) return open.auction end })
Probe.AddStation("F", { words = { "ziel", "target" }, probes = { "F1", "F2", "F4", "F5", "F6", "F8" },
    when = function() return Exists("target") end })
Probe.AddStation("G", { words = { "kampf", "combat" }, probes = { "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "H3G" }, combat = true,
    -- der Schadensmesser gibt erst nach dem Kampf Auskunft
    after = function()
        Core.AfterCombat(function()
            Probe.RunProbes("G", { "G9" }, { quiet = true, ev = "PLAYER_REGEN_ENABLED", title = Probe.StationTitle("G") })
        end, "ezCore.probe.G9", ADDON)
    end })
Probe.AddStation("G10", { st = "G", words = { "beute", "loot" }, probes = { "G10", "G13" }, combat = true,
    when = function(open) return open.loot or (Probe.RunClass.Call(nil, "GetNumLootItems"):Num() or 0) > 0 end })
Probe.AddStation("H", { words = { "gruppe", "group", "party" }, probes = { "H1", "H2", "H3", "H4" },
    when = function() return Yes("IsInGroup") end })
Probe.AddStation("I", { words = { "bank" }, probes = { "I1" }, when = function(open) return open.bank end })
Probe.AddStation("J", { words = { "beruf", "berufe", "profession", "tradeskill" }, probes = { "J1", "J2", "J3", "J6" },
    when = function(open) return open.profession end })
Probe.AddStation("K", { words = { "quest", "gespräch", "gespraech", "gossip" }, probes = { "K1", "K2", "K3", "K4", "K5" },
    when = function(open) return open.quest or open.gossip end })
Probe.AddStation("L", { words = { "flug", "flugmeister", "taxi", "flight" }, probes = { "L1", "L2" },
    when = function(open) return open.taxi end })
Probe.AddStation("M", { words = { "dungeon", "instanz", "instance" }, probes = { "M1", "M3", "M5", "H4" },
    when = function() return Yes("IsInInstance") end })
Probe.AddStation("N", { words = { "tod", "death" }, probes = { "N1", "N2" },
    when = function() return Yes("UnitIsDeadOrGhost", "player") end })
Probe.AddStation("W", { st = "A", words = { "karte", "map" }, probes = { "A17", "A20", "A21", "L2", "M5" },
    when = function(open) return open.map end })
-- Nachprobe: Spielobjekt in Reichweite oder unter der Maus (Erz, Kraut, Truhe), Vignette in der Nähe – von Hand mit
-- /ez probe objekt (Maus auf das Objekt, Makro drücken), von selbst mit der Automatik. extra: verdrängt „allein“ nicht.
Probe.AddStation("O", { words = { "objekt", "object", "vignette" }, probes = { "F8", "F9" }, extra = true,
    when = function() return Probe.ObjectNear() or Probe.VignettesNear() end })

-- Abfragen an einem Ereignis, solange der Mitschnitt läuft (das Fenster ist danach gleich wieder zu)
Probe.autoProbes.LOOT_READY = { station = "G10", ids = { "G10", "G13" }, combat = true, max = 30 }
Probe.autoProbes.LOOT_OPENED = { station = "G10", ids = { "G10O" }, combat = true, max = 30 }
Probe.autoProbes.PLAYER_REGEN_ENABLED = { station = "G", ids = { "G9" } }
Probe.autoProbes.QUEST_DETAIL = { station = "K", ids = { "K1" } }
Probe.autoProbes.QUEST_PROGRESS = { station = "K", ids = { "K2" } }
Probe.autoProbes.QUEST_COMPLETE = { station = "K", ids = { "K1", "K2" } }
Probe.autoProbes.GOSSIP_SHOW = { station = "K", ids = { "K3" } }
Probe.autoProbes.QUEST_GREETING = { station = "K", ids = { "K3" } }
Probe.autoProbes.PLAYER_INTERACTION_MANAGER_FRAME_SHOW = { station = "K", ids = { "K4" }, max = 20 }
Probe.autoProbes.DYNAMIC_GOSSIP_POI_UPDATED = { station = "K", ids = { "K5" } }
Probe.autoProbes.TAXIMAP_OPENED = { station = "L", ids = { "L1" } }
Probe.autoProbes.START_LOOT_ROLL = { station = "H", ids = { "H2" }, combat = true }
Probe.autoProbes.ENCOUNTER_END = { station = "M", ids = { "M3", "H4" }, combat = true }
Probe.autoProbes.PLAYER_MAP_CHANGED = { station = "M", ids = { "M1" }, max = 10 }
Probe.autoProbes.NAME_PLATE_UNIT_ADDED = { station = "F", ids = { "F8P" }, combat = true, max = 10 }
Probe.autoProbes.PLAYER_DEAD = { station = "N", ids = { "N1" }, combat = true }
Probe.autoProbes.TRAINER_UPDATE = { station = "C", ids = { "C5" }, max = 5 }

---------------------------------------------------------------------------
-- Sonderproben mit Nebenwirkung (docs/datenprobe.md, Abschnitt 7): nie von selbst, jede mit eigenem Knopf und
-- Rückfrage, nur mit dem Entwicklerschalter (Probe.SpecialsAllowed). X1 (Größengrenze, eigenes Wegwerf-Addon) und X5
-- (Addon-Nachrichten) sind bewusst nicht gebaut.
---------------------------------------------------------------------------

-- X2 – Komplett-Scan des Auktionshauses (löst vermutlich eine Sperrfrist aus)
P.X2 = function(run)
    run:Wait("X2", "REPLICATE_ITEM_LIST_UPDATE", function(r, answered)
        if not answered then return end
        local n = r:Q("X2", "C_AuctionHouse.GetNumReplicateItems"):Num() or 0
        -- Rückgaben 12 bis 15: Höchstbietender und Besitzer (kurzer und voller Name) – nie im Klartext
        r:With({ ret = { [12] = "player", [13] = "player", [14] = "player", [15] = "player" } })
            :Q("X2", "C_AuctionHouse.GetReplicateItemInfo", 0)
        Many(r, "X2", { { "C_AuctionHouse.GetReplicateItemLink", 0 }, { "C_AuctionHouse.GetReplicateItemTimeLeft", 0 } })
        local all = 0
        for i = 0, math.min(n, 300) - 1 do
            if r:Call("C_AuctionHouse.GetReplicateItemInfo", i):True(18) then all = all + 1 end
        end
        r:Note("X2", "hasAllInfo unter den ersten 300", all, math.min(n, 300))
        -- zweiter Aufruf direkt danach: bleibt das Ereignis aus, ist das die Antwort (Sperrfrist)
        r:Wait("X2", "REPLICATE_ITEM_LIST_UPDATE", nil, Probe.WAIT)
        r:Tag("zweiter Aufruf"):Q("X2", "C_AuctionHouse.ReplicateItems")
    end, 30)
    run:Q("X2", "C_AuctionHouse.ReplicateItems")
end

-- X3 – Wegpunkt setzen, lesen, wiederherstellen
P.X3 = function(run)
    local map = MapID(run)
    local pos = map and run:Call("C_Map.GetPlayerMapPosition", map, "player"):Tab()
    local old = run:Q("X3", "C_Map.GetUserWaypoint"):Tab()
    local tracked = run:Q("X3", "C_SuperTrack.IsSuperTrackingUserWaypoint")
    local can = map and run:Q("X3", "C_Map.CanSetUserWaypointOnMap", map):True()
    if not (can and pos) then return run:Note("X3", "kein Wegpunkt auf dieser Karte möglich", nil) end
    local x, y = Num(Field(pos, "x")), Num(Field(pos, "y"))
    local maker = Field(Tab(rawget(_G, "UiMapPoint")), "CreateFromCoordinates")
    local okPoint, point = pcall(function() return maker(map, x, y) end)
    if not (okPoint and Tab(point)) then return run:Note("X3", "UiMapPoint.CreateFromCoordinates fehlt", nil) end
    -- setzen, lesen und wiederherstellen in einem Stück (run:Atomic): keine Pause dazwischen, also weder ein Kampfbeginn
    -- noch die volle Ablage – der fremde Wegpunkt steht nie länger als dieses eine Bild
    run:Atomic(function(r)
        r:Tag("eigene Position"):Q("X3", "C_Map.SetUserWaypoint", point)
        Many(r, "X3", { "C_Map.HasUserWaypoint", "C_Map.GetUserWaypoint", "C_Map.GetUserWaypointHyperlink" })
        r:Q("X3", "C_SuperTrack.SetSuperTrackedUserWaypoint", true)
        r:Q("X3", "C_Navigation.GetDistance")
    end, function(r)
        -- wiederherstellen: alter Wegpunkt bzw. keiner, Zielverfolgung wie vorher
        if old then
            r:Tag("alter Wegpunkt zurück"):Q("X3", "C_Map.SetUserWaypoint", old)
        else
            r:Q("X3", "C_Map.ClearUserWaypoint")
        end
        r:Tag("Zielverfolgung wie vorher"):Q("X3", "C_SuperTrack.SetSuperTrackedUserWaypoint", tracked:True())
    end)
end

-- X4 – sendet der Server ungelernte Rezepte? (stellt Blizzards Filter um und im selben Bild zurück)
P.X4 = function(run)
    local before = run:Q("X4", "C_TradeSkillUI.GetShowUnlearned")
    if not before.ok or Core.IsSecret(before[1]) then return end
    local function Count(tag)
        local ids = run:Tag(tag):Q("X4", "C_TradeSkillUI.GetFilteredRecipeIDs"):Tab() or {}
        local learned, unlearned = 0, 0
        for i = 1, math.min(#ids, 2000) do
            local id = Num(ids[i])
            if id and run:Call("C_TradeSkillUI.GetRecipeInfo", id):Field("learned") == true then learned = learned + 1 else unlearned = unlearned + 1 end
        end
        run:Tag(tag):Note("X4", "Rezepte: Anzahl, gelernt, ungelernt", #ids, learned, unlearned)
    end
    Count("vorher")
    -- umstellen, zählen und zurückstellen in einem Stück (run:Atomic): Die Zählung „mit ungelernten“ gilt nur im selben
    -- Bild (Blizzard stellt den Filter beim nächsten Listenaufbau selbst zurück), und der Filter bleibt nie umgestellt –
    -- weder bei Kampfbeginn noch bei voller Ablage noch nach einem Fehler beim Zählen
    run:Atomic(function(r)
        r:Q("X4", "C_TradeSkillUI.SetShowUnlearned", true)
        Count("mit ungelernten")
    end, function(r)
        r:Tag("zurück"):Q("X4", "C_TradeSkillUI.SetShowUnlearned", before[1] == true)
    end)
end

-- F7 – Betrachten (NotifyInspect ist eine Anfrage an den Server)
P.F7 = function(run)
    if not run:Q("F7", "CanInspect", "target"):True() then return end
    run:Wait("F7", "INSPECT_READY", function(r, answered)
        if not answered then return end
        Many(r, "F7", { { "GetInventoryItemLink", "target", 16 }, { "C_PaperDollInfo.GetInspectItemLevel", "target" },
            "C_Traits.HasValidInspectData" })
        local trees = Tab(r:Q("F7", "C_Traits.GetConfigInfo", -1):Field("treeIDs"))
        local tree = trees and Num(trees[1])
        local nodes = tree and r:Q("F7", "C_Traits.GetTreeNodes", tree):Tab()
        local node = nodes and Num(nodes[1])
        if node then r:Q("F7", "C_Traits.GetNodeInfo", -1, node) end
        -- aufräumen wie Blizzards Fenster beim Schließen – außer es ist gerade offen
        if not Probe.OpenWindows().inspect then r:Q("F7", "ClearInspectPlayer") end
    end)
    run:Q("F7", "NotifyInspect", "target")
end

-- X6 – Sammelabfrage SearchForItemKeys (AH-07): Bedient der Server sie, und mit wie vielen Schlüsseln je Abfrage?
-- Nebenwirkung: gedrosselte Anfragen an den Server; die Übersicht im Auktionshaus zeigt danach das Ergebnis.
-- Schlüssel: die Gegenstände aus den Taschen (nur ihre Nummern), in Stufen von 1 bis höchstens 100.
P.X6 = function(run)
    if type(Probe.Resolve("C_AuctionHouse.SearchForItemKeys")) ~= "function" then
        run:Has("X6", "C_AuctionHouse.SearchForItemKeys")
        return
    end
    local keys, seen = {}, {}
    for _, item in ipairs(BagItems(run, 200)) do
        if not seen[item.id] and #keys < 100 then
            seen[item.id] = true
            local key = run:Call("C_AuctionHouse.MakeItemKey", item.id):Tab()
            if key then keys[#keys + 1] = key end
        end
    end
    run:Note("X6", "Schlüssel aus den Taschen", #keys)
    if #keys == 0 then return end
    local sizes = {}
    for _, size in ipairs({ 1, 10, 40, 100 }) do
        if size <= #keys then sizes[#sizes + 1] = size end
    end
    if sizes[#sizes] ~= #keys and #keys < 100 then sizes[#sizes + 1] = #keys end
    local order = EnumValue("AuctionHouseSortOrder", "Price")
    local sorts = order and { { sortOrder = order, reverseSort = false } } or {}
    local function Search(r, index)
        local size = sizes[index]
        if not size then return end
        local part = {}
        for i = 1, size do part[i] = keys[i] end
        r:Wait("X6", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function(r2, answered)
            local results = r2:Call("C_AuctionHouse.GetBrowseResults"):Tab()
            r2:Tag(size .. " Schlüssel"):Note("X6", "Antwort, Zeilen der Übersicht", answered, results and #results or nil)
            r2:Tag(size .. " Schlüssel"):Q("X6", "C_AuctionHouse.HasFullBrowseResults")
            -- Abstand zur nächsten Anfrage (die Suche ist gedrosselt)
            r2:After(1.5, function(r3) Search(r3, index + 1) end)
        end, Probe.WAIT * 2)
        r:Tag(size .. " Schlüssel"):Q("X6", "C_AuctionHouse.SearchForItemKeys", part, sorts)
    end
    Search(run, 1)
end

-- Blizzards Mengenfeld im Warenkauf (AuctionHouseFrame.CommoditiesBuyFrame.BuyDisplay.QuantityInput), nur gelesen.
local function CommodityQuantityInput()
    local input = Field(Tab(Field(Tab(Field(Tab(rawget(_G, "AuctionHouseFrame")), "CommoditiesBuyFrame")), "BuyDisplay")), "QuantityInput")
    input = Tab(input)
    local shown = Field(input, "IsVisible")
    if type(shown) ~= "function" then return nil end
    local ok, visible = pcall(shown, input)
    if ok and not Core.IsSecret(visible) and visible then return input end
    return nil
end

-- X7 – Tor T1 (AH-41): Setzt einmal die Menge im Warenkauf über Blizzards eigenes SetQuantity des Mengenfelds. Danach
-- klickt der Nutzer selbst Blizzards „Kaufen“ (das Angebot erscheint; bestätigen muss er nicht) – geht der geschützte
-- Klick durch, kommt COMMODITY_PRICE_UPDATED, sonst meldet das Spiel ADDON_ACTION_FORBIDDEN bzw. _BLOCKED.
-- Die Probe kauft nichts und klickt nichts.
P.X7 = function(run)
    local input = CommodityQuantityInput()
    if not input then return run:Note("X7", "Mengenfeld des Warenkaufs nicht sichtbar", nil) end
    local get, set = Field(input, "GetQuantity"), Field(input, "SetQuantity")
    if type(get) ~= "function" or type(set) ~= "function" then
        return run:Note("X7", "Mengenfeld ohne GetQuantity/SetQuantity", type(get), type(set))
    end
    local before = run:Tag("Menge vorher"):Q("X7", get, input):Num() or 1
    local wanted = before + 1
    run:Tag("SetQuantity(" .. wanted .. ")"):Q("X7", set, input, wanted)
    run:Tag("Menge danach"):Q("X7", get, input)
    ns.Print(L.PROBE_QUANTITY_SET:format(wanted))
    -- eine Minute lang festhalten, was der Klick des Nutzers auslöst
    run:Wait("X7", "COMMODITY_PRICE_UPDATED", nil, 60)
    run:Wait("X7", "ADDON_ACTION_FORBIDDEN", nil, 60)
    run:Wait("X7", "ADDON_ACTION_BLOCKED", nil, 60)
end

-- X8 – Minikarte (SAM-29): Sichtradius je Zoomstufe. Stellt den Zoom der Minikarte kurz um und danach zurück.
P.X8 = function(run)
    local map = Tab(rawget(_G, "Minimap"))
    local getZoom, setZoom, getLevels = Field(map, "GetZoom"), Field(map, "SetZoom"), Field(map, "GetZoomLevels")
    if type(getZoom) ~= "function" or type(setZoom) ~= "function" or type(getLevels) ~= "function" then
        return run:Note("X8", "Minimap ohne GetZoom/SetZoom/GetZoomLevels", nil)
    end
    run:Has("X8", "C_Minimap.GetViewRadius")
    local before = run:Tag("Zoom vorher"):Q("X8", getZoom, map):Num()
    local levels = run:Tag("Zoomstufen"):Q("X8", getLevels, map):Num() or 0
    Many(run, "X8", { "IsIndoors", "GetMinimapShape" })
    if not before or levels <= 0 then return end
    local function Level(r, zoom)
        if zoom >= math.min(levels, 8) then
            r:Tag("Zoom zurück auf " .. before):Q("X8", setZoom, map, before)
            return
        end
        r:Tag("SetZoom(" .. zoom .. ")"):Q("X8", setZoom, map, zoom)
        -- einen Augenblick warten: der Radius folgt dem Zoom womöglich erst im nächsten Bild
        r:After(0.2, function(r2)
            r2:Tag("Zoom " .. zoom):Q("X8", "C_Minimap.GetViewRadius")
            Level(r2, zoom + 1)
        end)
    end
    Level(run, 0)
end

-- Reihenfolge = Reihenfolge im Hinweis „noch offen“ (die Chatzeile nennt nur Auto.OPEN_SHOWN): F7 zuerst, es braucht
-- nur einen Spieler im Ziel, und an ihm entstand der Hinweis (Auftrag Welle 11)
local SPECIALS = {
    { key = "Inspect", id = "F7", words = { "f7", "betrachten", "inspect" },
        ready = function() return Exists("target") and Yes("UnitIsPlayer", "target") end, need = "PROBE_NEED_PLAYER" },
    { key = "Auction", id = "X2", words = { "x2", "komplettscan", "replicate" },
        ready = function() return Probe.OpenWindows().auction end, need = "PROBE_NEED_AUCTION" },
    { key = "Keys", id = "X6", words = { "x6", "schlüssel", "schluessel", "keys" },
        ready = function() return Probe.OpenWindows().auction end, need = "PROBE_NEED_AUCTION" },
    { key = "Quantity", id = "X7", words = { "x7", "menge", "quantity" },
        ready = function() return CommodityQuantityInput() ~= nil end, need = "PROBE_NEED_COMMODITY" },
    { key = "Minimap", id = "X8", words = { "x8", "minikarte", "minimap" } },
    { key = "Waypoint", id = "X3", words = { "x3", "wegpunkt", "waypoint" } },
    { key = "Recipes", id = "X4", words = { "x4", "rezepte", "recipes" },
        ready = function() return Probe.OpenWindows().profession end, need = "PROBE_NEED_PROFESSION" },
}

-- Sonderproben sind Entwicklerwerkzeuge (Gesamtreview 18.11.2026, Entscheidung 1, T1-5/T11-4): nur mit dem
-- Entwicklerschalter aus Diagnose.lua. → true | false
function Probe.SpecialsAllowed()
    local debug = Core.Debug
    return type(debug) == "table" and type(debug.Developer) == "function" and debug.Developer() == true
end

-- Sonderprobe starten: nur mit Entwicklerschalter, nicht im Kampf, Voraussetzung prüfen, Rückfrage mit der
-- Nebenwirkung. → true, wenn gefragt wurde
function Probe.Special(key)
    local special
    for _, entry in ipairs(SPECIALS) do
        if entry.key == key then special = entry end
    end
    if not special then return false end
    if not Probe.SpecialsAllowed() then
        ns.Print(L.PROBE_SPECIAL_DEV)
        return false
    end
    if Core.InCombat() then
        ns.Print(L.PROBE_SPECIAL_COMBAT)
        return false
    end
    if special.ready and not special.ready() then
        ns.Print(L[special.need])
        return false
    end
    Core.Confirm(L["PROBE_ASK_" .. key], function()
        -- der Schalter kann zwischen Rückfrage und „Ja“ ausgehen
        if not Probe.SpecialsAllowed() then return ns.Print(L.PROBE_SPECIAL_DEV) end
        if Core.InCombat() then return ns.Print(L.PROBE_SPECIAL_COMBAT) end
        Probe.RunProbes(special.id, { special.id }, { title = L["OPT_probe" .. key], key = special.id })
    end, { alert = true })
    return true
end

for _, special in ipairs(SPECIALS) do
    local key = special.key
    Probe.AddSpecial(special.words, function() Probe.Special(key) end)
end

-- Sonderproben, die noch nie liefen, mit ihrem Befehl (die Automatik startet sie nie; ihr Hinweis „noch offen“ nennt
-- sie, damit ein Helfer weiß, dass sie nur auf Befehl laufen – Auftrag Welle 11). Ohne Entwicklerschalter leer: Spieler
-- bekommen keine Entwicklerwerkzeuge angeboten. → { { id = "F7", cmd = "/ez probe betrachten" } … }
function Probe.OpenSpecials()
    if not Probe.SpecialsAllowed() then return {} end
    local p = Probe.Data()
    local done = type(p) == "table" and type(p.done) == "table" and p.done or {}
    local list = {}
    for _, special in ipairs(SPECIALS) do
        if (Core.Num(done[special.id]) or 0) == 0 then
            -- deutsch das zweite Wort, englisch das letzte (X6 führt dazwischen die Umschrift „schluessel“)
            local word = Core.IsGerman() and special.words[2] or special.words[#special.words]
            list[#list + 1] = { id = special.id, cmd = "/ez probe " .. tostring(word) }
        end
    end
    return list
end

-- Knöpfe „Sonderprobe: …“ unter „Erweitert“: nur zu sehen, solange der Entwicklerschalter an ist (Blizzards Liste
-- wertet opts.shown nach jedem Umschalten eines Schalters neu aus).
function Probe.AddSpecialButtons(page)
    local opts = { shown = Probe.SpecialsAllowed }
    page:Button(L.OPT_probeAuction, L.PROBE_SPECIAL_BUTTON, function() Probe.Special("Auction") end, L.OPT_probeAuction_TIP, opts)
    page:Button(L.OPT_probeWaypoint, L.PROBE_SPECIAL_BUTTON, function() Probe.Special("Waypoint") end, L.OPT_probeWaypoint_TIP, opts)
    page:Button(L.OPT_probeRecipes, L.PROBE_SPECIAL_BUTTON, function() Probe.Special("Recipes") end, L.OPT_probeRecipes_TIP, opts)
    page:Button(L.OPT_probeInspect, L.PROBE_SPECIAL_BUTTON, function() Probe.Special("Inspect") end, L.OPT_probeInspect_TIP, opts)
    page:Button(L.OPT_probeKeys, L.PROBE_SPECIAL_BUTTON, function() Probe.Special("Keys") end, L.OPT_probeKeys_TIP, opts)
    page:Button(L.OPT_probeQuantity, L.PROBE_SPECIAL_BUTTON, function() Probe.Special("Quantity") end, L.OPT_probeQuantity_TIP, opts)
    page:Button(L.OPT_probeMinimap, L.PROBE_SPECIAL_BUTTON, function() Probe.Special("Minimap") end, L.OPT_probeMinimap_TIP, opts)
end
