-- Server helper for Arch HUD: send attacker position to victim so client can show damage direction on minimap

if SERVER then
    util.AddNetworkString("archhud_damage_dir")

    -- Minimum interval between sends to the same player (avoid spam from multi-hit sources)
    local MIN_SEND_INTERVAL = 0.05

    hook.Add("EntityTakeDamage", "archhud_damage_dir_server", function(target, dmginfo)
        if not IsValid(target) or not target:IsPlayer() then return end

        -- Prefer explicit attacker; fall back to inflictor
        local attacker = dmginfo:GetAttacker()
        if not IsValid(attacker) then
            local inf = dmginfo:GetInflictor()
            if IsValid(inf) then attacker = inf end
        end

        if not IsValid(attacker) then return end
        if attacker == target then return end -- ignore self-damage

        local last = target.archhud_last_damage_sent or 0
        if CurTime() - last < MIN_SEND_INTERVAL then return end
        target.archhud_last_damage_sent = CurTime()

        -- Try to pick a sensible position for the attacker
        local pos = nil
        if attacker:IsPlayer() or attacker:IsNPC() or attacker:IsNextBot() then
            pos = attacker:GetPos()
        else
            -- some inflictors (projectiles) might be entities with positions
            if attacker.GetPos then
                pos = attacker:GetPos()
            end
        end

        if not pos then return end

        net.Start("archhud_damage_dir")
        net.WriteVector(pos)
        net.Send(target)
    end)
end
