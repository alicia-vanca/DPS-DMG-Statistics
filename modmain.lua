GLOBAL.setmetatable(env, { __index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end })

if GetModConfigData("func_open") ~= "open" then return end

local dps_say_open = GetModConfigData("dps_offset") ~= "no"

local SAY = function(guid, name, label)
    -- print("rpc say ", guid, name, label)
    local ent = Ents[guid]
    GLOBAL.Networking_Say(guid, -1, name, ent, label, {0.196, 0.804, 0.196, 1}, false, "none")
end
AddClientModRPCHandler("DPSINFO", "SAY", SAY)

local function OnDeathSay(inst, data)
    -- print(tostring(inst) .. " dead")
    if inst:HasTag("epic") then
        -- 更新伤害显示逻辑
        local sortedPlayerDamage = {}
        for playerName, damage in pairs(inst.playerDamage) do
            table.insert(sortedPlayerDamage, {name = playerName, damage = damage})
        end
        table.sort(sortedPlayerDamage, function(a, b) return a.damage > b.damage end)

        local playerDamageText = {}
        for i = 1, math.min(5, #sortedPlayerDamage) do
            table.insert(playerDamageText, string.format("%d. %s: %d  %.2f%%", i, sortedPlayerDamage[i].name, sortedPlayerDamage[i].damage,
                sortedPlayerDamage[i].damage / inst.totalDamage * 100))
        end

        local labelText = string.format("总伤害: %d\n%s\n其他总伤害: %d",
                                        inst.totalDamage, table.concat(playerDamageText, "\n"), inst.unknownDamage)

        if data.afflicter and data.afflicter.HasTag then
            labelText = "击杀者:" .. data.afflicter:GetDisplayName() .. "\n" .. labelText
        end

        labelText = "---------------------\n" .. labelText .. "\n---------------------"

        -- print(labelText)
        -- GLOBAL.Networking_Say(inst.GUID, -1, inst:GetDisplayName(), inst, labelText, {0.196, 0.804, 0.196, 1}, GetModConfigData("dps_end") == "near", "none")

        local near = GetModConfigData("dps_end") == "near"
        local x, y, z = inst.Transform:GetWorldPosition()
        local rpc = GetClientModRPC("DPSINFO", "SAY")
        for index, player in ipairs(AllPlayers) do
            if player and player:IsValid() and player.userid then
                -- print("check", tostring(player))
                if not near or player:GetDistanceSqToPoint(x, y, z) < 3600 then
                    -- print("send", tostring(player), player:GetDistanceSqToPoint(x, y, z))
                    SendModRPCToClient(rpc, player.userid, inst.GUID, inst:GetDisplayName(), labelText)
                end
            end
        end
    end
end

local function OnAttacked(inst, data)
    if inst:HasTag("epic") then
        -- print("OnAttacked")
        if not data.damage or data.damage == 0 then return end
        local damageAmount = data.damage

        if data.attacker and data.attacker.HasTag and data.attacker:HasTag("player") then
            local playerName = data.attacker:GetDisplayName()
            inst.playerDamage[playerName] = (inst.playerDamage[playerName] or 0) + damageAmount
        else
            inst.unknownDamage = inst.unknownDamage + damageAmount
        end
        -- 累加到总伤害
        inst.totalDamage = inst.totalDamage + damageAmount

        -- 更新伤害显示逻辑
        local sortedPlayerDamage = {}
        for playerName, damage in pairs(inst.playerDamage) do
            table.insert(sortedPlayerDamage, {name = playerName, damage = damage})
        end
        table.sort(sortedPlayerDamage, function(a, b) return a.damage > b.damage end)

        local playerDamageText = {}
        for i = 1, math.min(5, #sortedPlayerDamage) do
            table.insert(playerDamageText, string.format("%d. %s: %d  %.2f%%", i, sortedPlayerDamage[i].name, sortedPlayerDamage[i].damage,
                sortedPlayerDamage[i].damage / inst.totalDamage * 100))
        end

        local labelText = string.format("总伤害: %d\n%s\n其他总伤害: %d",
                                        inst.totalDamage, table.concat(playerDamageText, "\n"), inst.unknownDamage)

        if dps_say_open and inst.components.talker then
            inst.components.talker:Say(labelText,60)
        end

        if inst.deadMsg then
            OnDeathSay(inst, inst.deadMsg)
            inst.deadMsg = nil
        end
    end
end

local function OnHealthDelta(inst, data)
    if inst:HasTag("epic") and data.afflicter == "fire" then
        -- print("OnHealthDelta")
        if not data.amount or data.amount == 0 then return end
        local damageAmount = math.abs(data.amount)
        inst.unknownDamage = inst.unknownDamage + damageAmount
        -- 累加到总伤害
        inst.totalDamage = inst.totalDamage + damageAmount

        -- 更新伤害显示逻辑
        local sortedPlayerDamage = {}
        for playerName, damage in pairs(inst.playerDamage) do
            table.insert(sortedPlayerDamage, {name = playerName, damage = damage})
        end
        table.sort(sortedPlayerDamage, function(a, b) return a.damage > b.damage end)

        local playerDamageText = {}
        for i = 1, math.min(5, #sortedPlayerDamage) do
            table.insert(playerDamageText, string.format("%d. %s: %d  %.2f%%", i, sortedPlayerDamage[i].name, sortedPlayerDamage[i].damage,
                sortedPlayerDamage[i].damage / inst.totalDamage * 100))
        end

        local labelText = string.format("总伤害: %d\n%s\n其他总伤害: %d",
                                        inst.totalDamage, table.concat(playerDamageText, "\n"), inst.unknownDamage)

        if inst.components.talker then
            inst.components.talker:Say(labelText,60)
        end
        if inst.deadMsg then
            OnDeathSay(inst, inst.deadMsg)
        end
    end
end

local function OnDeath(inst, data)
    if inst:HasTag("epic") then
        -- print("OnDeath")
        inst.deadMsg = data
    end
end

local tbList = {
    middle = Vector3(0, -700, 0),
    right = Vector3(650, -700, 0),
    up = Vector3(0, 700, 0),
}

AddPrefabPostInitAny(function(inst)
    if inst:HasTag("epic") then
        if dps_say_open and not inst.components.talker then
            inst:AddComponent("talker")
            inst.components.talker.offset = tbList[GetModConfigData("dps_offset")]
            inst.components.talker.fontsize = 35
        end

        if not TheWorld.ismastersim then return end

        -- print("AddPrefabPostInitAny")

        inst.totalDamage = 0
        inst.playerDamage = inst.playerDamage or {}
        inst.unknownDamage = 0

        inst:ListenForEvent("attacked", OnAttacked)
        inst:ListenForEvent("healthdelta", OnHealthDelta)
        if GetModConfigData("dps_end") ~= "no" then
            -- print("listen death")
            inst:ListenForEvent("death", OnDeath)
        end
    end
end)