TUNING.DEBUG_MODE = GetModConfigData("enable_debug_mode")
TUNING.DPS_PLAYERS_ONLY = GetModConfigData("dps_players_only")
TUNING.DUMMY_DPS = GetModConfigData("dummy_dps")
TUNING.IS_DPS_SAY = GetModConfigData("dps_offset") ~= "no"
TUNING.DPS_SAY_POSITION = GetModConfigData("dps_offset")

function table_print(tt, indent, done)
    done = done or {}
    indent = indent or 0
    local spacer = string.rep("  ", indent)

    if type(tt) == "table" then
        if done[tt] then
            return "table (circular reference)"
        end
        done[tt] = true

        local sb = {"{\n"}
        for key, value in pairs(tt) do
            table.insert(sb, spacer .. "  ")
            if type(key) == "number" then
                table.insert(sb, string.format("[%d] = ", key))
            else
                table.insert(sb, string.format("%s = ", tostring(key)))
            end

            -- Expand 1 level deep, show type for deeper tables
            if type(value) == "table" then
                if indent < 1 then -- Only expand up to 1 level deep
                    table.insert(sb, table_print(value, indent + 1, done))
                else
                    table.insert(sb, tostring(value) .. " (table)")
                end
            else
                table.insert(sb, tostring(value) .. " (" .. type(value) .. ")")
            end
            table.insert(sb, ",\n")
        end
        table.insert(sb, spacer .. "}")
        done[tt] = nil -- Allow reuse of this table in other branches
        return table.concat(sb)
    else
        return tostring(tt) .. " (" .. type(tt) .. ")"
    end
end

function to_string(tbl)
    if tbl == nil then
        return "nil"
    end
    if type(tbl) == "table" then
        return table_print(tbl, 0, {})
    elseif "string" == type(tbl) then
        return tbl
    end
    return tostring(tbl) .. " (" .. type(tbl) .. ")"
end

local DebugPrint = TUNING.DEBUG_MODE and function(...)
        local msg = "[DPSInfo]"
        for i = 1, arg.n do
            msg = msg .. " " .. to_string(arg[i])
        end
        if arg.n > 1 then
            msg = msg .. "\n"
        end

        if #msg > 3900 then
            local chunks = {}
            local remaining = msg
            while #remaining > 3900 do
                local chunk = remaining:sub(1, 3900)
                local last_newline = chunk:find("\n[^\n]*$")
                if last_newline then
                    table.insert(chunks, chunk:sub(1, last_newline - 1))
                    remaining = remaining:sub(last_newline)
                else
                    table.insert(chunks, chunk)
                    remaining = remaining:sub(3901)
                end
            end
            table.insert(chunks, remaining)
            for _, chunk in ipairs(chunks) do
                print(chunk)
            end
        else
            print(msg)
        end
    end or function()
    end

GLOBAL.setmetatable(
    env,
    {
        __index = function(t, k)
            return GLOBAL.rawget(GLOBAL, k)
        end
    }
)

function GetOwner(inst, forceGetOwner)
    if forceGetOwner or not GetModConfigData("separate_follower_dmg") then
        if inst.owner then
            inst = inst.owner
        elseif inst.components.follower and inst.components.follower.leader then
            inst = inst.components.follower.leader
        elseif inst._playerlink then
            inst = inst._playerlink
        end
    end
    return inst
end

function GetDisplayName(inst)
    local displayName = inst:GetDisplayName()
    if inst:HasTag("player") then
        -- Don't return the prefab of the player who's named "MISSING NAME"
        return displayName
    end
    if not displayName or displayName == "MISSING NAME" then
        displayName = inst.prefab
    end
    return displayName
end

if GetModConfigData("func_open") ~= "open" then
    return
end

local TOP_DPS_MAX_ENTRY = 4

local SAY = function(guid, name, label)
    local ent = Ents[guid]
    DebugPrint("rpc say ", tostring(ent), "\n", name, label)
    GLOBAL.Networking_Say(guid, -1, name, ent, label, {0.196, 0.804, 0.196, 1}, false, "none")
end
AddClientModRPCHandler("DPSINFO", "SAY", SAY)

local SHOW_DUMMY_DPS_INFO = function(ent, label)
    -- local ent = Ents[guid]
    DebugPrint("rpc SHOW_DUMMY_DPS_INFO ", tostring(ent), "\n", label)
    ent.components.talker:Say(label, 5)
end
AddClientModRPCHandler("DPSINFO", "SHOW_DUMMY_DPS_INFO", SHOW_DUMMY_DPS_INFO)

local function GenerateDamageReport(inst, playerName)
    if not playerName then
        -- Boss damage statistics
        inst.sortedSourceDamage = {}
        local current_time = GetTime()

        -- Sort sources by damage
        for sourceName, damage in pairs(inst.damageSources) do
            table.insert(
                inst.sortedSourceDamage,
                {
                    name = sourceName,
                    damage = damage,
                    dps = damage / math.max(1, current_time - inst.startDamagingTime[sourceName])
                }
            )
        end
        table.sort(
            inst.sortedSourceDamage,
            function(a, b)
                return a.damage > b.damage
            end
        )

        -- Create base label text
        local labelText = string.format("------ Total: %d dmg ------", inst.totalDamage)

        -- Generate sources damage text
        local sourcesDamageText = {}
        for i = 1, math.min(TOP_DPS_MAX_ENTRY, #inst.sortedSourceDamage) do
            table.insert(
                sourcesDamageText,
                string.format(
                    "%d. %-10s:  %5d dmg (%.2f%%)  %7.2f dps",
                    i,
                    inst.sortedSourceDamage[i].name,
                    inst.sortedSourceDamage[i].damage,
                    inst.sortedSourceDamage[i].damage / inst.totalDamage * 100,
                    inst.sortedSourceDamage[i].dps
                )
            )
        end

        if #sourcesDamageText ~= 0 then
            labelText = string.format("%s\n%s", labelText, table.concat(sourcesDamageText, "\n"))
        end
        if inst.unknownDamage ~= 0 then
            labelText =
                string.format(
                "%s\nOther sources:  %5d dmg (%.2f%%)",
                labelText,
                inst.unknownDamage,
                inst.unknownDamage / inst.totalDamage * 100
            )
        end

        return labelText
    else
        -- Dummy dps
        local sortedSourceDamage = {}
        local current_time = GetTime()

        -- Sort sources by damage
        for sourceName, info in pairs(inst.damageSources[playerName]) do
            table.insert(
                sortedSourceDamage,
                {
                    name = sourceName,
                    damage = info.damage,
                    dps = info.damage / math.max(1, current_time - info.startDamagingTime)
                }
            )
        end
        table.sort(
            sortedSourceDamage,
            function(a, b)
                return a.damage > b.damage
            end
        )

        -- Create base label text
        local totalDamage = inst.totalDamage[playerName]
        local totalDps = totalDamage / math.max(1, current_time - inst.startDamagingTime[playerName])
        local labelText = string.format("【  Total:  %4d dmg  %6.2f dps  】", totalDamage, totalDps)

        if #sortedSourceDamage > 1 then
            -- Generate sources damage text
            local sourcesDamageText = {}
            for i = 1, #sortedSourceDamage do
                table.insert(
                    sourcesDamageText,
                    string.format(
                        "%d. %s:  %4d dmg (%.2f%%)  %6.2f dps",
                        i,
                        sortedSourceDamage[i].name,
                        sortedSourceDamage[i].damage,
                        sortedSourceDamage[i].damage / totalDamage * 100,
                        sortedSourceDamage[i].dps
                    )
                )
            end

            labelText = string.format("%s\n%s", labelText, table.concat(sourcesDamageText, "\n"))
        end

        return labelText
    end
end

local function SplitTextIntoChunks(text, removeFirstLine)
    local chunks = {}
    local maxLength = 150

    -- Split into lines and remove the first one
    local labelLines = text:split("\n")

    if removeFirstLine then
        -- Remove the Total dmg line when generating Boss damage statistics
        table.remove(labelLines, 1)
    end

    -- First split by newlines
    for _, line in ipairs(labelLines) do
        -- then split lines that are still too long
        local start = 1
        while start <= #line do
            local chunk = line:sub(start, start + maxLength - 1)
            table.insert(chunks, chunk)
            start = start + maxLength
        end
    end

    return chunks
end

local function OnDeathSay(inst, data)
    -- print("OnDeathSay", tostring(inst) .. " dead")
    if inst:HasTag("epic") then
        DebugPrint("OnDeathSay", tostring(inst))

        local bossName = "---------------------\n【 " .. GetDisplayName(inst) .. " 】"

        local killer
        if data.afflicter then
            killer = GetDisplayName(data.afflicter)
            killerOwner = GetDisplayName(GetOwner(data.afflicter, true))
            if killer ~= killerOwner then
                killer = killer .. " of " .. killerOwner
            end
        else
            killer = CapitalizeFirstChar(data.cause)
        end
        if inst.stillAlive then
            bossName = bossName .. " has been defeated by 【 " .. killer .. " 】"
        else
            bossName = bossName .. " has been killed by 【 " .. killer .. " 】"
        end

        bossName = bossName .. "\n---------------------"

        -- Update damage display logic
        local labelText = GenerateDamageReport(inst)
        local chunks = SplitTextIntoChunks(labelText, true)

        -- print(labelText)
        -- GLOBAL.Networking_Say(inst.GUID, -1, inst:GetDisplayName(), inst, labelText, {0.196, 0.804, 0.196, 1}, GetModConfigData("dps_end") == "near", "none")

        local near = GetModConfigData("dps_end") == "near"
        local x, y, z = inst.Transform:GetWorldPosition()
        local rpc = GetClientModRPC("DPSINFO", "SAY")
        for index, player in ipairs(AllPlayers) do
            if player and player:IsValid() and player.userid then
                -- print("check", tostring(player))
                local playerName = GetDisplayName(player)
                if not near or player:GetDistanceSqToPoint(x, y, z) < 3600 or inst.damageSources[playerName] ~= nil then
                    -- print("send", tostring(player), player:GetDistanceSqToPoint(x, y, z))

                    SendModRPCToClient(rpc, player.userid, inst.GUID, bossName, "")
                    for _, chunk in ipairs(chunks) do
                        SendModRPCToClient(rpc, player.userid, inst.GUID, " ", chunk)
                    end
                    -- Add dps info for players who wasn't in the top
                    if inst.damageSources[playerName] then
                        for i = 1, #inst.sortedSourceDamage do
                            if inst.sortedSourceDamage[i].name == playerName then
                                if i > TOP_DPS_MAX_ENTRY then
                                    SendModRPCToClient(
                                        rpc,
                                        player.userid,
                                        inst.GUID,
                                        " ",
                                        string.format(
                                            "(top %d) %s:   %6d dmg (%.2f%%)   %6.2f dps",
                                            i,
                                            playerName,
                                            inst.sortedSourceDamage[i].damage,
                                            inst.sortedSourceDamage[i].damage / inst.totalDamage * 100,
                                            inst.sortedSourceDamage[i].dps
                                        )
                                    )
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

local function OnBossAttacked(inst, data)
    DebugPrint("OnBossAttacked:", tostring(inst), "attacker:", tostring(data.attacker))
    -- print("OnAttacked")
    if not data.damage or data.damage == 0 then
        return
    end

    local damageAmount = data.damage

    if TUNING.DPS_PLAYERS_ONLY and data.attacker:HasTag("player") or not TUNING.DPS_PLAYERS_ONLY then
        local before = data.attacker.name
        local dmgSourceName = GetDisplayName(GetOwner(data.attacker))
        inst.damageSources[dmgSourceName] = (inst.damageSources[dmgSourceName] or 0) + damageAmount
        inst.startDamagingTime[dmgSourceName] = inst.startDamagingTime[dmgSourceName] or GetTime()
    else
        inst.unknownDamage = inst.unknownDamage + damageAmount
    end
    -- Add to total damage
    inst.totalDamage = inst.totalDamage + damageAmount

    -- Update damage display logic
    local labelText = GenerateDamageReport(inst)

    if TUNING.IS_DPS_SAY and inst.components.talker then
        inst.components.talker:Say(labelText, 60)
    end

    if inst.deadMsg then
        OnDeathSay(inst, inst.deadMsg)
        inst.deadMsg = nil
    end
end

local function ResetDpsTracker(inst)
    DebugPrint("Reset dps tracker")
    inst.totalDamage = {}
    inst.damageSources = {}
    inst.startDamagingTime = {}
end

local function OnDummyAttacked(inst, data)
    DebugPrint("Dummy Dps data:", data)
    if not data.damage or data.damage == 0 then
        return
    end

    local dmgSourceOwner = GetOwner(data.attacker, true)
    if dmgSourceOwner:HasTag("player") then
        local dmgSourceOwnerName = GetDisplayName(dmgSourceOwner)
        local dmgSourceName = GetDisplayName(data.attacker)
        local damageAmount = data.damage
        local current_time = GetTime()
        local damageSourcesOfThePlayer = inst.damageSources[dmgSourceOwnerName] or {}

        if inst.ResetDps[dmgSourceOwnerName] then
            -- DebugPrint("Cancel reset DPS tracker")
            inst.ResetDps[dmgSourceOwnerName]:Cancel()
            inst.ResetDps[dmgSourceOwnerName] = nil
        end

        -- The time when (the player or their followers) start damaging
        inst.startDamagingTime[dmgSourceOwnerName] = inst.startDamagingTime[dmgSourceOwnerName] or current_time

        -- Total damage of the player and their follower(s)
        inst.totalDamage[dmgSourceOwnerName] = (inst.totalDamage[dmgSourceOwnerName] or 0) + damageAmount

        -- Init damageSourcesOfThePlayer[dmgSourceName] as a table if it wasn't exist
        damageSourcesOfThePlayer[dmgSourceName] =
            damageSourcesOfThePlayer[dmgSourceName] or {damage = 0, startDamagingTime = current_time}

        -- Update the total damage of this damage source
        damageSourcesOfThePlayer[dmgSourceName].damage = damageSourcesOfThePlayer[dmgSourceName].damage + damageAmount

        inst.damageSources[dmgSourceOwnerName] = damageSourcesOfThePlayer

        local labelText = GenerateDamageReport(inst, dmgSourceOwnerName)

        -- local chunks = SplitTextIntoChunks(labelText)
        local rpc = GetClientModRPC("DPSINFO", "SHOW_DUMMY_DPS_INFO")
        SendModRPCToClient(rpc, dmgSourceOwner.userid, inst, labelText)

        inst.ResetDps[dmgSourceOwnerName] =
            inst:DoTaskInTime(
            5,
            function(inst)
                ResetDpsTracker(inst)
            end
        )
    end
end

function CapitalizeFirstChar(str)
    if not str or str == "" then
        return "Unknown"
    end -- Handle empty strings
    return str:sub(1, 1):upper() .. str:sub(2)
end

local function OnHealthDelta(inst, data)
    if inst:HasTag("epic") and data.cause and not data.afflicter then
        DebugPrint("OnHealthDelta:", tostring(inst), "cause:", data.cause, data.amount)
        if not data.amount or data.amount == 0 then
            return
        end
        -- local damageAmount = math.abs(data.amount)
        local damageAmount = data.amount

        if TUNING.DPS_PLAYERS_ONLY and damageAmount < 0 then
            inst.unknownDamage = inst.unknownDamage - damageAmount
        else
            local dmgSourceName = CapitalizeFirstChar(data.cause)
            -- Exclude regen
            -- If the fire heal the boss (?), then decrease its damage
            if inst.damageSources[dmgSourceName] or damageAmount < 0 then
                inst.damageSources[dmgSourceName] = (inst.damageSources[dmgSourceName] or 0) - damageAmount
                inst.startDamagingTime[dmgSourceName] = inst.startDamagingTime[dmgSourceName] or GetTime()
            else
                return
            end
        end

        -- Add to total damage
        inst.totalDamage = inst.totalDamage - damageAmount

        -- Update damage display logic
        local labelText = GenerateDamageReport(inst)

        if TUNING.IS_DPS_SAY and inst.components.talker then
            inst.components.talker:Say(labelText, 60)
        end
        if inst.deadMsg then
            OnDeathSay(inst, inst.deadMsg)
            inst.deadMsg = nil
        end
    end
end

local function OnDeath(inst, data)
    if inst:HasTag("epic") then
        DebugPrint("OnDeath", tostring(inst))
        inst.deadMsg = data
        inst:RemoveEventCallback("death", OnDeath)
    end
end

local function OnMinHealth(inst, data)
    if inst:HasTag("epic") and inst.components.health.minhealth > 0 and (inst.defeated == nil or inst.defeated) then
        DebugPrint("OnMinHealth", tostring(inst))
        inst.deadMsg = data
        inst.stillAlive = true
        inst:RemoveEventCallback("minhealth", OnMinHealth)
    end
end

local tbList = {
    head = Vector3(0, -1000, 0),
    left_right = Vector3(900, -700, 0),
    under = Vector3(0, 400, 0)
}

AddPrefabPostInitAny(
    function(inst)
        if inst:HasTag("epic") then
            if TUNING.IS_DPS_SAY and not inst.components.talker then
                inst:AddComponent("talker")
                inst.components.talker.offset = tbList[TUNING.DPS_SAY_POSITION]
                inst.components.talker.fontsize = 35
            end

            if not TheWorld.ismastersim then
                return
            end

            -- print("AddPrefabPostInitAny")

            inst.totalDamage = 0
            inst.damageSources = inst.damageSources or {}
            inst.startDamagingTime = inst.startDamagingTime or {}
            inst.unknownDamage = 0

            inst:ListenForEvent("attacked", OnBossAttacked)
            inst:ListenForEvent("healthdelta", OnHealthDelta)
            if GetModConfigData("dps_end") ~= "no" then
                -- print("listen death")
                inst:ListenForEvent("death", OnDeath)
                inst:ListenForEvent("minhealth", OnMinHealth)
            end
        elseif
            TUNING.DUMMY_DPS and
                table.contains({"punchingbag", "punchingbag_lunar", "punchingbag_shadow", "dummytarget"}, inst.prefab)
         then
            if not inst.components.talker then
                inst:AddComponent("talker")
                inst.components.talker.offset = Vector3(0, 200, 0) -- under the dummy
                inst.components.talker.fontsize = 35
            end

            if not TheWorld.ismastersim then
                return
            end
            inst.ResetDps = {}
            inst.totalDamage = {}
            inst.damageSources = inst.damageSources or {}
            inst.startDamagingTime = inst.startDamagingTime or {}
            inst:ListenForEvent("attacked", OnDummyAttacked)
        end
    end
)
