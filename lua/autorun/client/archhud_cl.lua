-- Arch HUD

local enabled = true

--[[
    This begins the configuration
]]--

archhud_config = archhud_config or {}

-- Label text (strings shown in the HUD)
archhud_config.IdentificationLabel = archhud_config.IdentificationLabel or "Name:"
archhud_config.OccupationLabel = archhud_config.OccupationLabel or "Job:"
archhud_config.CreditsLabel = archhud_config.CreditsLabel or "Money:"

-- Data providers: functions returning the displayed values. These can be replaced by server/provided code
-- Each function receives the local player as the first argument and should return a sensible type
if not archhud_config.GetOccupation then
    archhud_config.GetOccupation = function(ply)
        if not IsValid(ply) then return "" end
        if team and team.GetName then
            local ok, tname = pcall(function() return team.GetName(ply:Team()) end)
            if ok and type(tname) == "string" then return tname end
        end
        return ""
    end
end

if not archhud_config.GetCredits then
    -- default: zero credits
    archhud_config.GetCredits = function(ply)
        return 0
    end
end

if not archhud_config.GetStamina then
    -- default: stamina is always full; replace with your stamina system accessor
    archhud_config.GetStamina = function(ply)
        return 100
    end
end

-- Optional: allow customizing how the player's display name is resolved
if not archhud_config.GetIdentification then
    archhud_config.GetIdentification = function(ply)
        if not IsValid(ply) then return "" end
        return ply:Nick() or ""
    end
end

--[[
    This ends the configuration
]]--






















--[[
    Do Not Touch Unless You Know What You Are Doing
]]--


local function S(n)
    return math.max(1, math.Round(n * (ScrH() / 900)))
end

-- Fonts (created every load; surface.CreateFont is idempotent)
surface.CreateFont("archhud_large", {font = "Roboto", size = S(20), weight = 700, antialias = true})
surface.CreateFont("archhud_small", {font = "Roboto", size = S(14), weight = 500, antialias = true})
surface.CreateFont("archhud_ammo", {font = "Roboto", size = S(36), weight = 800, antialias = true})

local hud = {
    displayHP = 100,
    lastHP = 100,
    flash = 0,
    displayAmmo = 0,
    heartTime = 0,
    heartSpike = 0,
    armorTime = 0,
    armorSpike = 0,
    displayStamina = 100,
    crossAnim = 0,
}

hook.Add("HUDPaint", "archhud_draw", function()
    if not enabled then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local ft = FrameTime()
    local scrH = ScrH()
    local boxW, boxH = S(460), S(110)
    local x, y = S(18), scrH - boxH - S(36)

    -- Player raw stats
    local hp = math.max(0, math.floor(ply:Health() or 0))
    local armor = math.max(0, math.floor(ply:Armor() or 0))
    local ammoClip, ammoTotal = nil, 0
    local wep = ply:GetActiveWeapon()
    if IsValid(wep) then
        local ok, clip = pcall(function() return wep:Clip1() end)
        if ok and type(clip) == "number" then ammoClip = clip end
        local ok2, atype = pcall(function() return wep:GetPrimaryAmmoType() end)
        if ok2 and type(atype) == "number" then
            ammoTotal = ply:GetAmmoCount(atype) or 0
        end
    end

    -- Weapon display name (compute early so we can draw ammo panel later)
    local wname = ""
    if IsValid(wep) then
        if wep.GetPrintName and type(wep.GetPrintName) == "function" then
            pcall(function() wname = wep:GetPrintName() end)
        end
        if wname == "" then wname = wep:GetClass() or "weapon" end
    end

    -- Smooth values
    hud.displayHP = Lerp(math.min(12 * ft, 1), hud.displayHP, hp)
    hud.displayAmmo = Lerp(math.min(18 * ft, 1), hud.displayAmmo, ammoClip or 0)
    -- smooth armor for animation
    hud.displayArmor = Lerp(math.min(10 * ft, 1), hud.displayArmor or armor, armor)

    -- Damage flash and heartbeat spike when HP drops
    if hud.lastHP and hp < hud.lastHP then
        local delta = hud.lastHP - hp
        hud.flash = 140
        local spike = math.Clamp(delta / math.max(1, hud.lastHP), 0, 1)
        hud.heartSpike = math.min(1.6, hud.heartSpike + spike * 1.6)
    end
    hud.flash = math.max(0, hud.flash - 200 * ft)
    hud.lastHP = hp

    -- Armor spike on armor loss (replaces jitter)
    hud.lastArmor = hud.lastArmor or armor
    if armor < hud.lastArmor then
        local adot = hud.lastArmor - armor
        local j = math.Clamp(adot / math.max(1, hud.lastArmor), 0, 1)
        -- scale spike by armor lost; cap to avoid extreme values
        hud.armorSpike = math.min(2.2, (hud.armorSpike or 0) + j * 2.0)
    end
    -- decay spike faster than heartbeat
    hud.armorSpike = math.max(0, (hud.armorSpike or 0) - FrameTime() * 2.2)
    hud.lastArmor = armor

    -- Colors and accents
    local innerCol = Color(24,24,24,220)

    -- determine player's max HP once and reuse (avoid shadowing later)
    local maxhp = 100
    if ply.GetMaxHealth then
        local ok, val = pcall(function() return ply:GetMaxHealth() end)
        if ok and type(val) == "number" then maxhp = val end
    end

    -- Main container
    draw.RoundedBox(10, x, y, boxW, boxH, Color(0,0,0,150))
    draw.RoundedBox(10, x + S(6), y + S(6), boxW - S(12), boxH - S(12), innerCol)

    -- HEALTH MONITOR (left) -- vertical monitor that shortens with HP and shows heartbeat waveform
    local mX = x + S(8)
    local mY = y + S(8)
    local mW = S(44)
    local mH = boxH - S(16)
    draw.RoundedBox(6, mX, mY, mW, mH, Color(12,12,12,220))
    draw.RoundedBox(4, mX + S(4), mY + S(4), mW - S(8), mH - S(8), Color(20,20,20,220))

    -- health fill (from bottom)
    local hpPct = math.Clamp(hud.displayHP / math.max(1, maxhp), 0, 1)
    local innerX = mX + S(6)
    local innerY = mY + S(6)
    local innerW = mW - S(12)
    local innerH = mH - S(12)
    local fillH = math.max(4, math.floor(innerH * hpPct))
    draw.RoundedBox(4, innerX, innerY + (innerH - fillH), innerW, fillH, HSVToColor(math.Clamp(hpPct * 120, 0, 120), 1, 0.9))

    -- heartbeat waveform: spike on damage
    hud.heartTime = hud.heartTime + (FrameTime() * (1 + hud.heartSpike * 3))
    hud.heartSpike = math.max(0, hud.heartSpike - FrameTime() * 1.2)
    local samples = 18
    surface.SetDrawColor(180, 230, 255, 200)
    local prevX, prevY
    for i = 0, samples do
        local t = i / samples
        local px = innerX + t * innerW
        local phase = hud.heartTime * 8 + t * 10
        local amp = innerH * 0.12 * (1 + hud.heartSpike)
        local py = innerY + innerH / 2 - math.sin(phase) * amp
        if prevX then surface.DrawLine(prevX, prevY, px, py) end
        prevX, prevY = px, py
    end
    surface.SetDrawColor(255,255,255,255)

    -- small heart-rate readout removed; waveform remains

    -- ARMOR MONITOR (wavy vertical bar) to the right of the health monitor
    local aX = mX + mW + S(6)
    -- match armor bar vertically to health monitor
    local aY = mY
    local aW = S(20)
    local aH = mH
    draw.RoundedBox(4, aX, aY, aW, aH, Color(12,12,12,200))
    -- inner clipping area
    local iaX = aX + S(4)
    local iaY = aY + S(4)
    local iaW = aW - S(8)
    local iaH = aH - S(8)
    -- compute armor percentage
    -- assume max armor 100 for percentage
    local armorPct = math.Clamp((hud.displayArmor or 0) / 100, 0, 1)
    -- animate wave speed/time
    hud.armorTime = (hud.armorTime or 0) + FrameTime() * (1 + armorPct * 2)
    -- amplitude scales with armor percentage
    local amp = iaW * 0.5 * armorPct
    -- color: red when no armor, cyan otherwise
    local coreR, coreG, coreB = 120,200,255
    if (hud.displayArmor or 0) <= 1 then coreR, coreG, coreB = 220,80,80 end
    local steps = 40
    local prevAX, prevAY
    local sharpness = 2.6 -- >1 makes peaks pointier

    -- Outer glow pass (soft)
    surface.SetDrawColor(coreR, coreG, coreB, 140)
    for i = 0, steps do
        local t = i / steps
        local py = iaY + t * iaH
        local phase = hud.armorTime * 6 + t * 10
        local s = math.sin(phase)
        local sgn = s >= 0 and 1 or -1
        -- textured spike: mix of sin and low-freq modulation
        local textured = (math.abs(s) ^ (sharpness * 0.85)) * (1 + 0.45 * math.sin(phase * 2 + hud.armorTime * 1.3))
        local baseX = iaX + iaW / 2 + sgn * textured * amp * (0.8 + 0.2 * armorPct)
        local aspike = (hud.armorSpike or 0)
        if aspike > 0 then
            baseX = baseX + sgn * iaW * 0.45 * aspike * (0.5 + 0.5 * armorPct)
        end
        if prevAX then surface.DrawLine(prevAX, prevAY, baseX, py) end
        prevAX, prevAY = baseX, py
    end

    -- Core pass (sharp)
    surface.SetDrawColor(coreR, coreG, coreB, 255)
    prevAX, prevAY = nil, nil
    for i = 0, steps do
        local t = i / steps
        local py = iaY + t * iaH
        local phase = hud.armorTime * 6 + t * 10
        local s = math.sin(phase)
        local sgn = s >= 0 and 1 or -1
        local spike = sgn * (math.abs(s) ^ sharpness)
        local baseX = iaX + iaW / 2 + spike * amp * (0.6 + 0.4 * armorPct)
        local aspike = (hud.armorSpike or 0)
        if aspike > 0 then
            baseX = baseX + sgn * iaW * 0.4 * aspike * (0.6 + 0.4 * armorPct)
        end
        if prevAX then surface.DrawLine(prevAX, prevAY, baseX, py) end
        prevAX, prevAY = baseX, py
    end

    -- Player name and team to the right of the health & armor monitors
    local textX = aX + aW + S(8)
    local textY = mY + S(6)
    -- draw bold 'Identification:' label in the health-wave blur color, then the nickname
    local label = (archhud_config and archhud_config.IdentificationLabel) or "Identification:"
    local blurCol = Color(180,230,255,255)
    surface.SetFont("archhud_large")
    local lw = surface.GetTextSize(label .. " ")
    draw.SimpleText(label, "archhud_large", textX, textY, blurCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    local idText = (archhud_config and archhud_config.GetIdentification and archhud_config.GetIdentification(ply)) or ply:Nick()
    draw.SimpleText(idText, "archhud_large", textX + lw + S(4), textY, Color(245,245,245), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    local teamColor = Color(200,200,200)
    local teamName = ""
    if team and team.GetName and team.GetColor then
        local ok, tname = pcall(function() return team.GetName(ply:Team()) end)
        if ok and type(tname) == "string" then teamName = tname end
        local okc, tcol = pcall(function() return team.GetColor(ply:Team()) end)
        if okc and type(tcol) == "table" then teamColor = tcol end
    end
    local tlabel = (archhud_config and archhud_config.OccupationLabel) or "Occupation:"
    surface.SetFont("archhud_small")
    local tlw = surface.GetTextSize(tlabel .. " ")
    draw.SimpleText(tlabel, "archhud_small", textX, textY + S(28), blurCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    local occText = (archhud_config and archhud_config.GetOccupation and tostring(archhud_config.GetOccupation(ply))) or teamName
    draw.SimpleText(occText, "archhud_small", textX + tlw + S(4), textY + S(28), teamColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    -- Credits label/value below Occupation
    local clabel = (archhud_config and archhud_config.CreditsLabel) or "Credits:"
    local cval = ((archhud_config and archhud_config.GetCredits) and archhud_config.GetCredits(ply)) or 0
    surface.SetFont("archhud_small")
    local clw = surface.GetTextSize(clabel .. " ")
    draw.SimpleText(clabel, "archhud_small", textX, textY + S(28) + S(20), blurCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(tostring(cval), "archhud_small", textX + clw + S(4), textY + S(28) + S(20), Color(245,245,245), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    -- (ammo panel moved below so it's rendered above minimap)
    -- Stamina bar (bottom of HUD) - orange, full by default; configurable later
    -- Stamina: track previous value so we can color on increase/decrease
    local prevSt = hud.displayStamina or 100
    local targetSt = (archhud_config and archhud_config.GetStamina and archhud_config.GetStamina(ply)) or 100 -- use config-provided stamina getter
    hud.displayStamina = Lerp(math.min(10 * ft, 1), prevSt, targetSt)
    local deltaSt = hud.displayStamina - (hud.lastStamina or prevSt)
    hud.lastStamina = hud.displayStamina

    local padding = S(8)
    local stH = S(10)
    -- position stamina to the right of the monitors/text to avoid clipping
    local stX = textX or (x + padding + S(60))
    -- clamp width to remaining inner area and shorten a bit on the right
    local stW = math.max(S(100), (x + boxW - padding) - stX - S(12))
    -- move it slightly up (more top spacing) so it fits better
    local stY = y + boxH - stH - S(12) -- inside the main box near bottom with extra top spacing
    draw.RoundedBox(6, stX, stY, stW, stH, Color(30,20,10,200))
    local sPct = math.Clamp((hud.displayStamina or 100) / 100, 0, 1)
    -- color based on change: green when increasing, red when decreasing, orange otherwise
    local fillCol = Color(255,165,0)
    if deltaSt > 0.01 then
        fillCol = Color(120,255,120)
    elseif deltaSt < -0.01 then
        fillCol = Color(255,100,100)
    end
    draw.RoundedBox(6, stX, stY, math.max(4, math.floor(stW * sPct)), stH, fillCol)

    -- Damage flash overlay
    if hud.flash > 0 then
        draw.RoundedBox(0, 0, 0, ScrW(), ScrH(), Color(255,50,50, math.min(200, hud.flash)))
    end

    -- Radar (modern)
    local radarSize = S(140)
    local rx = ScrW() - radarSize - S(16)
    -- move radar (and its ammo panel) up to avoid going off-screen
    local verticalShift = S(60)
    local ry = ScrH() - radarSize - S(16) - verticalShift
    ry = math.max(S(8), ry)
    -- Circular Radar (modern)
    local cx = rx + radarSize / 2
    local cy = ry + radarSize / 2
    local outerR = (radarSize - S(6)) / 2
    local innerR = outerR - S(6)
    local segs = 64
    draw.NoTexture()
    -- outer shadow/background
    surface.SetDrawColor(10,10,10,200)
    local poly = {}
    for i = 0, segs - 1 do
        local a = math.rad((i / segs) * 360)
        poly[#poly + 1] = { x = cx + math.cos(a) * outerR, y = cy + math.sin(a) * outerR }
    end
    surface.DrawPoly(poly)
    -- inner circle
    surface.SetDrawColor(30,30,30,220)
    poly = {}
    for i = 0, segs - 1 do
        local a = math.rad((i / segs) * 360)
        poly[#poly + 1] = { x = cx + math.cos(a) * innerR, y = cy + math.sin(a) * innerR }
    end
    surface.DrawPoly(poly)

    -- Radar circular grid: concentric rings and radial lines
    surface.SetDrawColor(120,120,120,35)
    for ring = 1, 2 do
        local r = innerR * (ring / 3)
        local px, py
        for i = 0, segs do
            local a = math.rad((i / segs) * 360)
            local x1 = cx + math.cos(a) * r
            local y1 = cy + math.sin(a) * r
            if px then surface.DrawLine(px, py, x1, y1) end
            px, py = x1, y1
        end
    end
    -- radial lines (N, NE, E, SE, S, SW, W, NW)
    for i = 0, 7 do
        local a = math.rad(i * 45)
        local x1 = cx + math.cos(a) * (innerR * 0.02)
        local y1 = cy + math.sin(a) * (innerR * 0.02)
        local x2 = cx + math.cos(a) * innerR
        local y2 = cy + math.sin(a) * innerR
        surface.DrawLine(x1, y1, x2, y2)
    end
    surface.SetDrawColor(255,255,255,255)

    -- Ammo / Weapon panel below the minimap
    local ammoW, ammoH = S(140), S(56)
    local ax = rx + (radarSize / 2) - (ammoW / 2)
    local ay = ry + radarSize + S(8)
    -- ensure ammo panel doesn't go below screen
    if ay + ammoH > ScrH() - S(8) then
        ay = ScrH() - ammoH - S(8)
    end
    draw.RoundedBox(6, ax, ay, ammoW, ammoH, Color(10,10,10,200))
    draw.RoundedBox(4, ax + S(4), ay + S(4), ammoW - S(8), ammoH - S(8), Color(30,30,30,220))
    draw.SimpleText(tostring(math.floor(hud.displayAmmo + 0.5)), "archhud_ammo", ax + S(10), ay + ammoH / 2, Color(245,245,245), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText((ammoTotal and ammoTotal > 0) and ("/ " .. tostring(ammoTotal)) or "", "archhud_small", ax + ammoW - S(10), ay + S(10), Color(200,200,200), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    draw.SimpleText(wname, "archhud_small", ax + ammoW - S(10), ay + ammoH - S(8), Color(150,150,150), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

    -- Radar grid
    do
        local gridDiv = 3
        local radarInnerX = rx + S(6)
        local radarInnerY = ry + S(6)
        local innerSize = radarSize - S(12)
        local gridColor = Color(120,120,120,35)
        surface.SetDrawColor(gridColor.r, gridColor.g, gridColor.b, gridColor.a)
        for i = 1, gridDiv - 1 do
            local t = i / gridDiv
            local gx = radarInnerX + (innerSize * t)
            local gy = radarInnerY + (innerSize * t)
            surface.DrawLine(gx, radarInnerY, gx, radarInnerY + innerSize)
            surface.DrawLine(radarInnerX, gy, radarInnerX + innerSize, gy)
        end
        surface.SetDrawColor(255,255,255,255)
    end

    local centerX = cx
    local centerY = cy
    local rawYaw = math.NormalizeAngle(ply:EyeAngles().y or 0)
    if rawYaw < 0 then rawYaw = rawYaw + 360 end
    local yaw = (360 - rawYaw) % 360
    local deg = math.floor(yaw)
    local function compassDir(a)
        local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
        local sector = math.floor(((a + 22.5) % 360) / 45) + 1
        return dirs[sector]
    end
    local cdir = compassDir(yaw)
    draw.SimpleText(string.format("%s %d°", cdir, deg), "archhud_small", centerX, ry + S(6), Color(200,200,200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    local maxRange = 2000
    local scale = (radarSize / 2) / maxRange

    -- Teammates
    for _, pl in ipairs(player.GetAll()) do
        if IsValid(pl) and pl ~= ply and pl:Alive() and pl:Team() == ply:Team() then
            local wpos = pl:GetPos()
            local localPos = WorldToLocal(wpos, Angle(0,0,0), ply:GetPos(), Angle(0, ply:EyeAngles().y, 0))
            local dotX = centerX - (localPos.y * scale)
            local dotY = centerY - (localPos.x * scale)
            -- clamp to circle boundary
            local dx, dy = dotX - centerX, dotY - centerY
            local dist = math.sqrt(dx * dx + dy * dy)
            local maxR = innerR
            local relX, relY
            if dist > maxR then
                local ratio = maxR / dist
                relX = centerX + dx * ratio
                relY = centerY + dy * ratio
            else
                relX = dotX
                relY = dotY
            end
            local col = (team and team.GetColor) and team.GetColor(pl:Team()) or Color(100,200,100)
            draw.RoundedBox(4, relX - S(3), relY - S(3), S(6), S(6), col)
        end
    end

    -- NPCs
    for _, ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent:IsNPC() and ent:Health() > 0 then
            local dist = ent:GetPos():DistToSqr(ply:GetPos())
            if dist <= (maxRange * maxRange) then
                local wpos = ent:GetPos()
                local localPos = WorldToLocal(wpos, Angle(0,0,0), ply:GetPos(), Angle(0, ply:EyeAngles().y, 0))
                local dotX = centerX - (localPos.y * scale)
                local dotY = centerY - (localPos.x * scale)
                local dx, dy = dotX - centerX, dotY - centerY
                local dist2 = math.sqrt(dx * dx + dy * dy)
                local maxR = innerR
                local relX, relY
                if dist2 > maxR then
                    local ratio = maxR / dist2
                    relX = centerX + dx * ratio
                    relY = centerY + dy * ratio
                else
                    relX = dotX
                    relY = dotY
                end
                draw.RoundedBox(4, relX - S(3), relY - S(3), S(6), S(6), Color(220,80,80))
            end
        end
    end

    -- Crosshair: animated morph from square -> normal crosshair; larger by default
    do
        local chX, chY = ScrW() * 0.5, ScrH() * 0.5
        local tr = ply:GetEyeTrace()
        local ent = tr and tr.Entity
        local aimed = IsValid(ent) and (ent:IsPlayer() or ent:IsNPC())

        -- animate (0 = square, 1 = crosshair)
        hud.crossAnim = hud.crossAnim or 0
        local target = aimed and 1 or 0
        -- speed tuned for snappy but smooth transition
        hud.crossAnim = Lerp(math.min(10 * ft, 1), hud.crossAnim, target)

        -- sizes (bigger as requested)
        local squareHalfBase = S(18) -- base half-size for square
        local lineGapBase = S(10)
        local lineLenBase = S(22)

        -- compute interpolated sizes
        local t = hud.crossAnim
        -- square shrinks slightly as it morphs away
        local squareHalf = math.max(1, math.floor(squareHalfBase * (1 - 0.6 * t)))
        -- crosshair lines grow from zero to full length
        local gap = math.max(1, math.floor(lineGapBase * (1 - 0.2 * (1 - t))))
        local len = math.max(1, math.floor(lineLenBase * t))

        -- draw square with alpha fading out
        local sqAlpha = math.floor(255 * (1 - t))
        if sqAlpha > 0 then
            surface.SetDrawColor(245,245,245, sqAlpha)
            surface.DrawOutlinedRect(chX - squareHalf, chY - squareHalf, squareHalf * 2, squareHalf * 2)
        end

        -- draw crosshair with alpha fading in
        local chAlpha = math.floor(255 * t)
        if chAlpha > 0 then
            surface.SetDrawColor(245,245,245, chAlpha)
            -- left
            surface.DrawLine(chX - gap - len, chY, chX - gap, chY)
            -- right
            surface.DrawLine(chX + gap, chY, chX + gap + len, chY)
            -- up
            surface.DrawLine(chX, chY - gap - len, chX, chY - gap)
            -- down
            surface.DrawLine(chX, chY + gap, chX, chY + gap + len)
        end
    end
end)

concommand.Add("archhud_toggle", function()
    enabled = not enabled
end)

hook.Add("HUDShouldDraw", "archhud_hide_default", function(name)
    if not enabled then return end
    local blocked = {
        "CHudHealth",
        "CHudBattery",
        "CHudAmmo",
        "CHudSecondaryAmmo",
        "CHudWeapon",
        "CHudCrosshair",
        "CHudDamageIndicator",
        "CHudSuitPower",
    }
    for _, v in ipairs(blocked) do
        if name == v then return false end
    end
end)
