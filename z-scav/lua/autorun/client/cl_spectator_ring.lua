
local function DrawArc(x, y, radius, thickness, start_ang, end_ang, roughness, color)
    surface.SetDrawColor(color.r, color.g, color.b, color.a)
    draw.NoTexture()
    
    local segs = roughness
    local step = (end_ang - start_ang) / segs
    
    for i = 0, segs - 1 do
        local a1 = math.rad(start_ang + i * step)
        local a2 = math.rad(start_ang + (i + 1) * step)
        
        local cos1, sin1 = math.cos(a1), math.sin(a1)
        local cos2, sin2 = math.cos(a2), math.sin(a2)
        
        local p1 = { x = x + cos1 * (radius - thickness), y = y - sin1 * (radius - thickness) }
        local p2 = { x = x + cos1 * radius, y = y - sin1 * radius }
        local p3 = { x = x + cos2 * radius, y = y - sin2 * radius }
        local p4 = { x = x + cos2 * (radius - thickness), y = y - sin2 * (radius - thickness) }
        
        surface.DrawPoly({p1, p2, p3, p4})
    end
end

local ringAlpha = 0
local lerpBrain = 0
local lerpShock = 0
local lerpConsciousness = 0
local peakShock = 40
local lastTarget = nil
local dotBeat = 0

local ekgPoints = {}
local sweepPos = 0
local lastSweepUpdate = 0
local heartPhase = 0

local SOUND_HEART = "hg_unconscious/heartthump-heavy.ogg"
local SOUND_FLATLINE = "hg_unconscious/flatline.ogg"

local lastPhaseMod = 0
local flatlineCooldownAt = 0
local wasFlatline = false
local wasUnconsciousState = false
local flatlinePlayedThisUnconscious = false
local soundGen = 0
local heartStations = {}
local heartStationsLoading = false
local heartStationNext = 1
local flatlineStation = nil
local flatlineLoading = false

local function PhaseCrossed(prev, curr, threshold)
    if prev <= curr then
        return prev < threshold and curr >= threshold
    end
    return prev < threshold or curr >= threshold
end

local function IsClassicEnabled()
    local hg_unconsciousclassic = GetConVar("hg_unconsciousclassic")
    return hg_unconsciousclassic and hg_unconsciousclassic:GetBool()
end

local function ResetRingAudio()
    soundGen = soundGen + 1
    wasUnconsciousState = false
    flatlinePlayedThisUnconscious = false

    for i = 1, #heartStations do
        local st = heartStations[i]
        if IsValid(st) then
            st:Stop()
        end
    end

    heartStations = {}
    heartStationsLoading = false
    heartStationNext = 1

    if IsValid(flatlineStation) then
        flatlineStation:Stop()
    end
    flatlineStation = nil
    flatlineLoading = false
end

local function EnsureHeartStations()
    if heartStationsLoading or (#heartStations > 0) then return end
    heartStationsLoading = true

    local gen = soundGen
    local filePath = "sound/" .. SOUND_HEART

    for i = 1, 4 do
        sound.PlayFile(filePath, "noblock noplay", function(station)
            if gen ~= soundGen then
                if IsValid(station) then station:Stop() end
                return
            end
            if IsValid(station) then
                station:SetVolume(0)
                heartStations[i] = station
            end
            if i == 4 then
                heartStationsLoading = false
            end
        end)
    end
end

local function EnsureFlatlineStation()
    if flatlineLoading or IsValid(flatlineStation) then return end
    flatlineLoading = true

    local gen = soundGen
    local filePath = "sound/" .. SOUND_FLATLINE

    sound.PlayFile(filePath, "noblock noplay", function(station)
        flatlineLoading = false
        if gen ~= soundGen then
            if IsValid(station) then station:Stop() end
            return
        end
        if IsValid(station) then
            station:SetVolume(0)
            flatlineStation = station
        end
    end)
end

local function PlayStation(station, volume)
    if not IsValid(station) then return end
    station:SetTime(0)
    station:SetVolume(math.Clamp(volume or 1, 0, 1))
    station:Play()
end

local function EmitRingSound(soundPath, volume)
    if IsClassicEnabled() then return end

    if soundPath == SOUND_HEART then
        EnsureHeartStations()

        local st = heartStations[heartStationNext]
        heartStationNext = (heartStationNext % 4) + 1

        if IsValid(st) then
            PlayStation(st, volume)
        else
            sound.PlayFile("sound/" .. soundPath, "noblock noplay", function(station)
                if IsValid(station) then
                    PlayStation(station, volume)
                end
            end)
        end
    elseif soundPath == SOUND_FLATLINE then
        EnsureFlatlineStation()

        if IsValid(flatlineStation) then
            PlayStation(flatlineStation, volume)
        else
            sound.PlayFile("sound/" .. soundPath, "noblock noplay", function(station)
                if IsValid(station) then
                    PlayStation(station, volume)
                end
            end)
        end
    else
        sound.PlayFile("sound/" .. soundPath, "noblock noplay", function(station)
            if IsValid(station) then
                PlayStation(station, volume)
            end
        end)
    end
end

local function UpdateRingAudio(pulse, ringAlpha)
    if pulse < 1 or ringAlpha <= 0 then return end

    local prev = lastPhaseMod
    local curr = (lastPhaseMod + FrameTime() * (pulse / 60)) % 1
    lastPhaseMod = curr

    local beatVolume = math.Clamp(0.35 * ringAlpha, 0, 1)
    if PhaseCrossed(prev, curr, 0.239) then
        EmitRingSound(SOUND_HEART, beatVolume)
    end
end

local function DrawEKG(centerX, centerY, width, height, pulse, color, ringAlpha)
    local time = CurTime()
    if lastSweepUpdate == 0 then lastSweepUpdate = time end
    local dt = time - lastSweepUpdate
    lastSweepUpdate = time
    
    -- Increment heart phase based on pulse
    -- pulse is BPM, so pulse/60 is beats per second
    heartPhase = heartPhase + dt * (pulse / 60)
    
    local sweepSpeed = width / 4
    local oldSweepPos = sweepPos
    sweepPos = (sweepPos + dt * sweepSpeed) % width

    -- Fills all indices between oldSweepPos and newSweepPos
    local function getH(phase)
        phase = phase % 1
        local h = 0
        
        -- P wave: small bump
        if phase > 0.05 and phase < 0.15 then
            h = h + math.sin((phase - 0.05) / 0.1 * math.pi) * 0.12
        -- QRS complex: the main spike
        elseif phase > 0.2 and phase < 0.32 then
            local p = (phase - 0.2) / 0.12
            if p < 0.15 then -- Q
                h = h - math.sin(p / 0.15 * math.pi) * 0.15
            elseif p < 0.5 then -- R
                h = h + math.sin((p - 0.15) / 0.35 * math.pi) * 1.0
            else -- S
                h = h - math.sin((p - 0.5) / 0.5 * math.pi) * 0.25
            end
        -- T wave: medium bump
        elseif phase > 0.45 and phase < 0.65 then
            h = h + math.sin((phase - 0.45) / 0.2 * math.pi) * 0.22
        end
        
        return h
    end

    local steps = math.max(1, math.floor(math.abs(sweepPos - oldSweepPos)))
    if sweepPos < oldSweepPos then steps = math.max(1, math.floor(width - oldSweepPos + sweepPos)) end

    for i = 0, steps do
        local p = (oldSweepPos + i) % width
        -- Interpolate heartPhase for this specific pixel
        local p_phase = heartPhase - (dt * (pulse / 60) * (1 - i/steps))
        ekgPoints[math.floor(p)] = getH(p_phase)
    end
    
    -- Clears a small gap ahead of the sweepPos
    local gap = 12
    for i = 1, gap do
        ekgPoints[math.floor((sweepPos + i) % width)] = nil
    end
    
    -- Draws the buffered points
    local startX = centerX - width / 2
    local lastX, lastY
    
    -- Move drawSegment outside for efficiency
    local function drawSegment(sx, sy, slastX, slastY, sthick)
        if slastX then
            local sdy = sy - slastY
            if math.abs(sdy) > 1 then
                local ssy = sdy > 0 and slastY or sy
                surface.DrawRect(sx - sthick, ssy, sthick * 2 + 1, math.abs(sdy) + 1)
            else
                surface.DrawRect(sx - sthick, sy - sthick, sthick * 2 + 1, sthick * 2 + 1)
            end
        else
            surface.DrawRect(sx - sthick, sy - sthick, sthick * 2 + 1, sthick * 2 + 1)
        end
    end

    for i = 0, width - 1 do
        local h_val = ekgPoints[i]
        if h_val == nil then 
            lastX, lastY = nil, nil
            continue 
        end
        
        local x = startX + i
        local y = centerY - (h_val * height / 2)
        
        local dist = sweepPos - i
        if dist < 0 then dist = dist + width end
        
        -- Balls too
        local alphaMult = math.exp(-dist / (width * 0.08)) -- Sharp initial drop
        alphaMult = math.max(alphaMult, math.Clamp(0.18 * (1 - dist / width), 0, 0.18)) -- Long dim tail
        
        local currentAlpha = color.a * alphaMult
        local shadowAlpha = 180 * alphaMult * ringAlpha
        
        draw.NoTexture()
        local thick = 2
        
        -- Shadow first
        surface.SetDrawColor(0, 0, 0, shadowAlpha)
        drawSegment(x, y, lastX, lastY, thick + 1)

        -- Main Line
        surface.SetDrawColor(color.r, color.g, color.b, currentAlpha)
        drawSegment(x, y, lastX, lastY, thick)
        
        lastX, lastY = x, y
    end
end

hook.Add("HUDPaint", "DrawSpectatorUnconsciousRing", function()
    local hg_unconsciousring = GetConVar("hg_unconsciousring")
    if hg_unconsciousring and not hg_unconsciousring:GetBool() then
        ringAlpha = 0
        lastPhaseMod = 0
        flatlineCooldownAt = 0
        wasFlatline = false
        ResetRingAudio()
        return
    end
    
    local hg_unconsciousclassic = GetConVar("hg_unconsciousclassic")

    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    
    local target = lp:GetNWEntity("spect")
    local viewmode = lp:GetNWInt("viewmode", 1)

    if not IsValid(target) or not target:IsPlayer() or viewmode != 1 then
        ringAlpha = 0
        lastTarget = nil
        lastPhaseMod = 0
        flatlineCooldownAt = 0
        wasFlatline = false
        ResetRingAudio()
        return
    end

    if target != lastTarget then
        peakShock = 40
        lastTarget = target
        ekgPoints = {}
        sweepPos = 0
        lastSweepUpdate = 0
        lastPhaseMod = 0
        flatlineCooldownAt = 0
        wasFlatline = false
        ResetRingAudio()
    end

    local org = target.organism
    if not org then 
        ringAlpha = 0
        lastPhaseMod = 0
        flatlineCooldownAt = 0
        wasFlatline = false
        ResetRingAudio()
        return 
    end
    
    local isUnconscious = org.otrub
    
    if isUnconscious then
        if not wasUnconsciousState then
            flatlinePlayedThisUnconscious = false
        end

        local currentShock = org.shock or 0
        if currentShock > peakShock then
            peakShock = currentShock
        end
        ringAlpha = math.Approach(ringAlpha, 1, FrameTime() * 2)
        dotBeat = math.floor(CurTime()) % 3
    else
        flatlinePlayedThisUnconscious = false
        ringAlpha = math.Approach(ringAlpha, 0, FrameTime() * 3)
        if ringAlpha <= 0 then
            peakShock = 40
            ekgPoints = {}
            sweepPos = 0
            lastSweepUpdate = 0
            lastPhaseMod = 0
            flatlineCooldownAt = 0
            wasFlatline = false
            ResetRingAudio()
        end
    end
    wasUnconsciousState = isUnconscious
    
    if ringAlpha <= 0 then return end
    
    lerpBrain = math.Approach(lerpBrain, org.brain or 0, FrameTime() * 2)
    lerpShock = math.Approach(lerpShock, org.shock or 0, FrameTime() * 50)
    lerpConsciousness = math.Approach(lerpConsciousness, org.consciousness or 0, FrameTime() * 2)
    
    local pulse = org.heartbeat or org.pulse or 70
    local brain = org.brain or 0
    local consciousness = org.consciousness or 0
    local shock = org.shock or 0
    local isCritical = (org.critical == true) or (pulse < 1 and brain >= 0.02) or (brain >= 0.34)

    local classicEnabled = hg_unconsciousclassic and hg_unconsciousclassic:GetBool()
    if classicEnabled then
        lastPhaseMod = 0
        flatlineCooldownAt = 0
        wasFlatline = false
        flatlinePlayedThisUnconscious = false
    else
        local isFlatline = pulse < 1
        if isFlatline and not flatlinePlayedThisUnconscious and ringAlpha > 0 then
            EmitRingSound(SOUND_FLATLINE, math.Clamp(0.8 * ringAlpha, 0, 1))
            flatlinePlayedThisUnconscious = true
        end
        wasFlatline = isFlatline

        UpdateRingAudio(pulse, ringAlpha)
    end
    
    local scrW, scrH = ScrW(), ScrH()
    local centerX, centerY = scrW / 2, scrH / 2
    
    surface.SetDrawColor(0, 0, 0, 253 * ringAlpha)
    surface.DrawRect(0, 0, scrW, scrH)
    
    local ringColor = isCritical and Color(200, 0, 0, 255 * ringAlpha) or Color(220, 220, 220, 255 * ringAlpha)
    local dotColor = isCritical and ringColor or Color(255, 255, 255, 255 * ringAlpha)
    
    local progress = 0
    if isCritical then
        progress = math.Clamp((0.70 - lerpBrain) / (0.70 - 0.02), 0, 1)
    else
        local shockProgress = math.Clamp((peakShock - lerpShock) / (peakShock - 0.02), 0, 1)
        local consciousnessProgress = math.Clamp(lerpConsciousness / 0.10, 0, 1)
        progress = math.min(shockProgress, consciousnessProgress)
    end
    
    local radius = 280
    local thickness = 12
    
    DrawArc(centerX, centerY, radius, thickness, 0, 360, 60, Color(40, 40, 40, 100 * ringAlpha))
    DrawArc(centerX, centerY, radius, thickness, 90, 90 - (progress * 360), 80, ringColor)
    
    if hg_unconsciousclassic and hg_unconsciousclassic:GetBool() then
        local beat = dotBeat
        local dotText = ""

        if isCritical then
            local redDots = {".!", "..!", "...!"}
            dotText = redDots[beat + 1]
        else
            local whiteDots = {".", "..", "..."}
            dotText = whiteDots[beat + 1]
        end
        
        draw.SimpleText(dotText, "UnconsciousDots", centerX, centerY, dotColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        DrawEKG(centerX, centerY, 540, 140, pulse, dotColor, ringAlpha)
    end
end)
