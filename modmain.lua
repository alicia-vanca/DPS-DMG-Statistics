TUNING.DEBUG_MODE = GetModConfigData("enable_debug_mode")
TUNING.DPS_PLAYERS_ONLY = GetModConfigData("dps_players_only")

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
        print(msg)
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

if GetModConfigData("func_open") ~= "open" then
    return
end

local TOP_DPS_MAX_ENTRY = 4

local dps_say_open = GetModConfigData("dps_offset") ~= "no"

local SAY = function(guid, name, label)
    print("rpc say ", guid, "\n", name, label)
    local ent = Ents[guid]
    GLOBAL.Networking_Say(guid, -1, name, ent, label, {0.196, 0.804, 0.196, 1}, false, "none")
end
AddClientModRPCHandler("DPSINFO", "SAY", SAY)

local function GenerateDamageReport(inst)
    inst.sortedPlayerDamage = {}
    local current_time = GetTime()

    -- Sort players by damage
    for playerName, damage in pairs(inst.playerDamage) do
        table.insert(
            inst.sortedPlayerDamage,
            {
                name = playerName,
                damage = damage,
                dps = damage / math.max(1, current_time - inst.playerStartTime[playerName])
            }
        )
    end
    table.sort(
        inst.sortedPlayerDamage,
        function(a, b)
            return a.damage > b.damage
        end
    )

    -- Generate player damage text
    local playerDamageText = {}
    for i = 1, math.min(TOP_DPS_MAX_ENTRY, #inst.sortedPlayerDamage) do
        table.insert(
            playerDamageText,
            string.format(
                "%d. %-10s:   %6d dmg (%.2f%%)   %6.2f dps",
                i,
                inst.sortedPlayerDamage[i].name,
                inst.sortedPlayerDamage[i].damage,
                inst.sortedPlayerDamage[i].damage / inst.totalDamage * 100,
                inst.sortedPlayerDamage[i].dps
            )
        )
    end

    -- Create base label text
    local labelText = string.format("------ Total: %d dmg ------", inst.totalDamage)

    if #playerDamageText ~= 0 then
        labelText = string.format("%s\n%s", labelText, table.concat(playerDamageText, "\n"))
    end
    if inst.unknownDamage ~= 0 then
        labelText =
            string.format(
            "%s\nOther sources:   %6d dmg (%.2f%%)",
            labelText,
            inst.unknownDamage,
            inst.unknownDamage / inst.totalDamage * 100
        )
    end

    return labelText
end

local function SplitTextIntoChunks(text)
    local chunks = {}
    local maxLength = 150

    -- Split into lines and remove the first one
    local labelLines = text:split("\n")
    table.remove(labelLines, 1) -- Remove first line

    -- First split by newlines
    for _, line in ipairs(labelLines) do
        -- Then split lines that are still too long
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

        local bossName = "---------------------\n【 " .. inst:GetDisplayName() .. " 】"

        local killer
        if data.afflicter then
            killer = data.afflicter:GetDisplayName()
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
        local chunks = SplitTextIntoChunks(labelText)

        -- print(labelText)
        -- GLOBAL.Networking_Say(inst.GUID, -1, inst:GetDisplayName(), inst, labelText, {0.196, 0.804, 0.196, 1}, GetModConfigData("dps_end") == "near", "none")

        local near = GetModConfigData("dps_end") == "near"
        local x, y, z = inst.Transform:GetWorldPosition()
        local rpc = GetClientModRPC("DPSINFO", "SAY")
        for index, player in ipairs(AllPlayers) do
            if player and player:IsValid() and player.userid then
                -- print("check", tostring(player))
                local playerName = player:GetDisplayName()
                if not near or player:GetDistanceSqToPoint(x, y, z) < 3600 or inst.playerDamage[playerName] ~= nil then
                    -- print("send", tostring(player), player:GetDistanceSqToPoint(x, y, z))

                    SendModRPCToClient(rpc, player.userid, inst.GUID, bossName, "")
                    for _, chunk in ipairs(chunks) do
                        SendModRPCToClient(rpc, player.userid, inst.GUID, " ", chunk)
                    end
                    -- Add dps info for players who wasn't in the top
                    if inst.playerDamage[playerName] then
                        for i = 1, #inst.sortedPlayerDamage do
                            if inst.sortedPlayerDamage[i].name == playerName then
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
                                            inst.sortedPlayerDamage[i].damage,
                                            inst.sortedPlayerDamage[i].damage / inst.totalDamage * 100,
                                            inst.sortedPlayerDamage[i].dps
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

local function OnAttacked(inst, data)
    if inst:HasTag("epic") then
        DebugPrint("OnAttacked", tostring(inst))
        -- print("OnAttacked")
        if not data.damage or data.damage == 0 then
            return
        end

        local damageAmount = data.damage

        if TUNING.DPS_PLAYERS_ONLY and data.attacker:HasTag("player") or not TUNING.DPS_PLAYERS_ONLY then
            local playerName = data.attacker:GetDisplayName()
            inst.playerDamage[playerName] = (inst.playerDamage[playerName] or 0) + damageAmount
            inst.playerStartTime[playerName] = inst.playerStartTime[playerName] or GetTime()
        else
            inst.unknownDamage = inst.unknownDamage + damageAmount
        end
        -- Add to total damage
        inst.totalDamage = inst.totalDamage + damageAmount

        -- Update damage display logic
        local labelText = GenerateDamageReport(inst)

        if dps_say_open and inst.components.talker then
            inst.components.talker:Say(labelText, 60)
        end

        if inst.deadMsg then
            OnDeathSay(inst, inst.deadMsg)
            inst.deadMsg = nil
        end
    end
end

function CapitalizeFirstChar(str)
    if str == "" then
        return str
    end -- Handle empty strings
    return str:sub(1, 1):upper() .. str:sub(2)
end

local function OnHealthDelta(inst, data)
    if inst:HasTag("epic") and not data.afflicter then
        DebugPrint("OnHealthDelta", tostring(inst))
        if not data.amount or data.amount == 0 then
            return
        end
        -- local damageAmount = math.abs(data.amount)
        local damageAmount = data.amount

        if TUNING.DPS_PLAYERS_ONLY and damageAmount < 0 then
            inst.unknownDamage = inst.unknownDamage - damageAmount
        else
            local sourceName = CapitalizeFirstChar(data.cause)
            -- Exclude regen
            -- If the fire heal the boss (?), then decrease its damage
            if inst.playerDamage[sourceName] or damageAmount < 0 then
                inst.playerDamage[sourceName] = (inst.playerDamage[sourceName] or 0) - damageAmount
                inst.playerStartTime[sourceName] = inst.playerStartTime[sourceName] or GetTime()
            else
                return
            end
        end

        -- Add to total damage
        inst.totalDamage = inst.totalDamage - damageAmount

        -- Update damage display logic
        local labelText = GenerateDamageReport(inst)

        if dps_say_open and inst.components.talker then
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
    if inst:HasTag("epic") and inst.components.health.minhealth > 0 then
        DebugPrint("OnMinHealth", tostring(inst))
        inst.deadMsg = data
        inst.stillAlive = true
        inst:RemoveEventCallback("minhealth", OnMinHealth)
    end
end

local tbList = {
    head = Vector3(0, -1000, 0),
    left_right = Vector3(900, -700, 0),
    under = Vector3(0, 700, 0)
}

AddPrefabPostInitAny(
    function(inst)
        if inst:HasTag("epic") then
            if dps_say_open and not inst.components.talker then
                inst:AddComponent("talker")
                inst.components.talker.offset = tbList[GetModConfigData("dps_offset")]
                inst.components.talker.fontsize = 35
            end

            if not TheWorld.ismastersim then
                return
            end

            -- print("AddPrefabPostInitAny")

            inst.totalDamage = 0
            inst.playerDamage = inst.playerDamage or {}
            inst.playerStartTime = inst.playerStartTime or {}
            inst.unknownDamage = 0

            inst:ListenForEvent("attacked", OnAttacked)
            inst:ListenForEvent("healthdelta", OnHealthDelta)
            if GetModConfigData("dps_end") ~= "no" then
                -- print("listen death")
                inst:ListenForEvent("death", OnDeath)
                inst:ListenForEvent("minhealth", OnMinHealth)
            end
        end
    end
)
