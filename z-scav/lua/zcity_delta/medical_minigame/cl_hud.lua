if SERVER then return end

local PANEL = {}

local circleMat = Material("vgui/circle")

local function IsBruiceKitActive()
    local lp = LocalPlayer()
    if not IsValid(lp) then return false end
    local wep = lp:GetActiveWeapon()
    if not IsValid(wep) then return false end
    return wep:GetClass() == "weapon_bruicekit"
end

local function LoadHudMaterial(path, fallbackPath)
    local paths = {path}
    if fallbackPath then
        paths[#paths + 1] = fallbackPath
    end

    for _, materialPath in ipairs(paths) do
        local mat = Material(materialPath, "smooth noclamp")
        if type(mat) == "IMaterial" and not mat:IsError() then
            return mat
        end
    end

    return nil
end

local function SetHudMaterial(mat)
    if type(mat) ~= "IMaterial" or mat:IsError() then return false end
    surface.SetMaterial(mat)
    return true
end

local handMat = LoadHudMaterial("homigrad/hand.png", "homigrad/hand")
local handStatusFrameDuration = 0.8
local handStatusStepDuration = 0.1
local handFrameSequence = {1, 2, 3}
local handStatusSequence = {0, 2, 3}
local handFrames = {
    [0] = {},
    [2] = {},
    [3] = {},
}
local handPlaybackFrames = {}

for _, status in ipairs(handStatusSequence) do
    for _, frame in ipairs(handFrameSequence) do
        local mat = LoadHudMaterial(
            "homigrad/handanim/" .. frame .. "_" .. status .. ".png",
            "homigrad/handanim/" .. frame .. "_" .. status
        )

        if mat then
            handFrames[status][#handFrames[status] + 1] = mat
        end
    end
end

for _, status in ipairs(handStatusSequence) do
    local frames = handFrames[status]
    local playback = {}

    if frames and #frames > 0 then
        for i = 1, #frames do
            playback[#playback + 1] = frames[i]
        end

        for i = #frames - 1, 1, -1 do
            playback[#playback + 1] = frames[i]
        end
    end

    handPlaybackFrames[status] = playback
end

local bleedFrames = {}
local bleedFrameCount = 6

for i = 1, bleedFrameCount do
    bleedFrames[i] = LoadHudMaterial("homigrad/bleedanim/" .. i .. ".png", "homigrad/bleedanim/" .. i)
end

local syringeBaseMat = LoadHudMaterial("homigrad/syringe/s2.png", "homigrad/syringe/s2")
local syringePlungerFrames = {}
local syringePlungerFrameDuration = 0.09
local amputationVisualStateCache = {}
local dislocationLimbLabels = {
    larm = "LEFT ARM",
    rarm = "RIGHT ARM",
    lleg = "LEFT LEG",
    rleg = "RIGHT LEG",
    jaw = "JAW"
}

local function GetAmputationVisualStateKey(target, limb)
    local targetId = "self"
    if IsValid(target) then
        targetId = "ent:" .. target:EntIndex()
    end

    return targetId .. ":" .. tostring(limb or "unknown")
end

local function GetAmputationVisualState(target, limb)
    return amputationVisualStateCache[GetAmputationVisualStateKey(target, limb)]
end

local function SetAmputationVisualState(target, limb, state)
    amputationVisualStateCache[GetAmputationVisualStateKey(target, limb)] = state
end

local function ClearAmputationVisualState(target, limb)
    amputationVisualStateCache[GetAmputationVisualStateKey(target, limb)] = nil
end

local function ClearAllAmputationVisualState()
    amputationVisualStateCache = {}

    if hg and hg.MedicalMinigame then
        hg.MedicalMinigame.NextTarget = nil
        hg.MedicalMinigame.NextLimb = nil
        hg.MedicalMinigame.NextProgress = 0
    end
end

local function IsLocalPlayerUnconscious()
    local lp = LocalPlayer()
    return IsValid(lp) and lp.organism and lp.organism.otrub
end

for i = 1, 3 do
    syringePlungerFrames[i] = LoadHudMaterial("homigrad/syringe/s1_" .. i .. ".png", "homigrad/syringe/s1_" .. i)
end

local medicalMusicPath = "sound/homigrad/medical_minigame_trade.mp3"

local function NormalizeAngleDiff(diff)
    if diff > math.pi then diff = diff - 2 * math.pi end
    if diff < -math.pi then diff = diff + 2 * math.pi end
    return diff
end

local function AppendBandageTrail(points, fromAngle, toAngle, step)
    if not isnumber(fromAngle) or not isnumber(toAngle) then return end

    step = math.max(step or math.rad(2), 0.0001)

    if #points == 0 then
        points[1] = { angle = fromAngle }
    else
        local lastAngle = points[#points].angle
        if math.abs(NormalizeAngleDiff(lastAngle - fromAngle)) > 0.0005 then
            points[#points + 1] = { angle = fromAngle }
        end
    end

    local diff = NormalizeAngleDiff(toAngle - fromAngle)
    local distance = math.abs(diff)

    if distance <= step then
        points[#points + 1] = { angle = toAngle }
        return
    end

    local steps = math.max(math.ceil(distance / step), 1)
    for i = 1, steps do
        local t = i / steps
        points[#points + 1] = {
            angle = fromAngle + diff * t
        }
    end
end

local function DrawBandageTrail(panel, points, radius, alpha, thickness, col)
    if #points <= 1 then return end

    thickness = thickness or 15
    local c = col or color_white
    surface.SetDrawColor(c.r, c.g, c.b, alpha or 180)
    
    for i = 1, #points - 1 do
        local p1 = points[i]
        local p2 = points[i + 1]
        
        local a1, a2 = p1.angle, p2.angle
        
        -- Calculate the four polygon points for a thick line segment
        local r1 = radius
        local r2 = radius + thickness
        
        local cos1, sin1 = math.cos(a1), math.sin(a1)
        local cos2, sin2 = math.cos(a2), math.sin(a2)
        
        local p1x, p1y = panel.CenterX + cos1 * r1, panel.CenterY + sin1 * r1
        local p2x, p2y = panel.CenterX + cos2 * r1, panel.CenterY + sin2 * r1
        local p3x, p3y = panel.CenterX + cos2 * r2, panel.CenterY + sin2 * r2
        local p4x, p4y = panel.CenterX + cos1 * r2, panel.CenterY + sin1 * r2
        
        draw.NoTexture()
        surface.DrawPoly({
            { x = p1x, y = p1y },
            { x = p2x, y = p2y },
            { x = p3x, y = p3y },
            { x = p4x, y = p4y }
        })
    end
end

local function DrawBandageRing(panel, radius, alpha, thickness, col)
    thickness = thickness or 15
    local segments = 96
    local innerRadius = radius
    local outerRadius = radius + thickness

    local c = col or color_white
    surface.SetDrawColor(c.r, c.g, c.b, alpha or 180)

    for i = 0, segments - 1 do
        local a1 = math.rad((i / segments) * 360)
        local a2 = math.rad(((i + 1) / segments) * 360)
        local cos1, sin1 = math.cos(a1), math.sin(a1)
        local cos2, sin2 = math.cos(a2), math.sin(a2)

        draw.NoTexture()
        surface.DrawPoly({
            {x = panel.CenterX + cos1 * innerRadius, y = panel.CenterY + sin1 * innerRadius},
            {x = panel.CenterX + cos2 * innerRadius, y = panel.CenterY + sin2 * innerRadius},
            {x = panel.CenterX + cos2 * outerRadius, y = panel.CenterY + sin2 * outerRadius},
            {x = panel.CenterX + cos1 * outerRadius, y = panel.CenterY + sin1 * outerRadius}
        })
    end
end

local function DrawFallbackHand(x, y, angle)
    local rad = math.rad(angle or 0)
    local cosA, sinA = math.cos(rad), math.sin(rad)
    local points = {
        {x = -105, y = 150},
        {x = -70, y = -120},
        {x = -25, y = -155},
        {x = 5, y = -55},
        {x = 45, y = -175},
        {x = 85, y = -165},
        {x = 55, y = -35},
        {x = 105, y = -160},
        {x = 145, y = -130},
        {x = 95, y = -10},
        {x = 160, y = -80},
        {x = 200, y = -40},
        {x = 120, y = 95},
        {x = 70, y = 65},
        {x = 25, y = 175},
        {x = -45, y = 185}
    }

    local poly = {}
    for _, point in ipairs(points) do
        poly[#poly + 1] = {
            x = x + (point.x * cosA - point.y * sinA),
            y = y + (point.x * sinA + point.y * cosA)
        }
    end

    draw.NoTexture()
    surface.SetDrawColor(30, 30, 30, 120)
    surface.DrawPoly(poly)

    for _, point in ipairs(poly) do
        point.x = x + ((point.x - x) * 0.94)
        point.y = y + ((point.y - y) * 0.94)
    end

    surface.SetDrawColor(255, 255, 255, 245)
    surface.DrawPoly(poly)
end

local function DrawRotatedBar(x, y, width, height, angleDeg, color)
    local halfW = width * 0.5
    local halfH = height * 0.5
    local rad = math.rad(angleDeg or 0)
    local cosA, sinA = math.cos(rad), math.sin(rad)
    local corners = {
        {-halfW, -halfH},
        {halfW, -halfH},
        {halfW, halfH},
        {-halfW, halfH}
    }
    local poly = {}

    for i = 1, 4 do
        local corner = corners[i]
        poly[i] = {
            x = x + corner[1] * cosA - corner[2] * sinA,
            y = y + corner[1] * sinA + corner[2] * cosA
        }
    end

    draw.NoTexture()
    surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
    surface.DrawPoly(poly)
end

local function DrawFilledCircle(x, y, radius, color, segments)
    segments = segments or 48

    local poly = {}
    for i = 0, segments do
        local a = math.rad((i / segments) * 360)
        poly[#poly + 1] = {
            x = x + math.cos(a) * radius,
            y = y + math.sin(a) * radius
        }
    end

    draw.NoTexture()
    surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
    surface.DrawPoly(poly)
end

local function DrawOutlinedBone(x, y, width, height, angleDeg, outlineColor, innerColor)
    outlineColor = outlineColor or Color(255, 255, 255, 255)
    innerColor = innerColor or Color(0, 0, 0, 255)

    local endOffset = (width * 0.5) - (height * 0.3)
    local rad = math.rad(angleDeg or 0)
    local cosA, sinA = math.cos(rad), math.sin(rad)
    local function RotateOffset(localX, localY)
        return x + localX * cosA - localY * sinA, y + localX * sinA + localY * cosA
    end

    DrawRotatedBar(x, y, width, height * 0.46, angleDeg, outlineColor)

    local lx, ly = RotateOffset(-endOffset, 0)
    local rx, ry = RotateOffset(endOffset, 0)
    DrawFilledCircle(lx, ly - height * 0.22, height * 0.26, outlineColor, 24)
    DrawFilledCircle(lx, ly + height * 0.22, height * 0.26, outlineColor, 24)
    DrawFilledCircle(rx, ry - height * 0.22, height * 0.26, outlineColor, 24)
    DrawFilledCircle(rx, ry + height * 0.22, height * 0.26, outlineColor, 24)

    DrawRotatedBar(x, y, width - 10, math.max(height * 0.3, 8), angleDeg, innerColor)
    DrawFilledCircle(lx, ly - height * 0.22, height * 0.16, innerColor, 20)
    DrawFilledCircle(lx, ly + height * 0.22, height * 0.16, innerColor, 20)
    DrawFilledCircle(rx, ry - height * 0.22, height * 0.16, innerColor, 20)
    DrawFilledCircle(rx, ry + height * 0.22, height * 0.16, innerColor, 20)
end

local function DrawAmputationBlade(x, y, width, height, angleDeg)
    local rad = math.rad(angleDeg or 0)
    local cosA, sinA = math.cos(rad), math.sin(rad)
    local bladePoly = {
        {-width * 0.44, -height * 0.12},
        {width * 0.24, -height * 0.2},
        {width * 0.5, -height * 0.02},
        {width * 0.26, height * 0.17},
        {-width * 0.48, height * 0.1}
    }
    local drawPoly = {}

    for i, point in ipairs(bladePoly) do
        drawPoly[i] = {
            x = x + point[1] * cosA - point[2] * sinA,
            y = y + point[1] * sinA + point[2] * cosA
        }
    end

    DrawRotatedBar(x - width * 0.31 * cosA, y - width * 0.31 * sinA, width * 0.22, height * 0.24, angleDeg, Color(65, 28, 18, 255))
    DrawRotatedBar(x - width * 0.42 * cosA, y - width * 0.42 * sinA, width * 0.05, height * 0.28, angleDeg, Color(220, 210, 200, 255))

    draw.NoTexture()
    surface.SetDrawColor(240, 165, 170, 185)
    surface.DrawPoly(drawPoly)

    local shinePoly = {}
    for i, point in ipairs(bladePoly) do
        shinePoly[i] = {
            x = x + (point[1] * 0.88) * cosA - (point[2] * 0.72) * sinA,
            y = y + (point[1] * 0.88) * sinA + (point[2] * 0.72) * cosA
        }
    end

    surface.SetDrawColor(255, 215, 220, 105)
    surface.DrawPoly(shinePoly)
end

local function GetHandDrawPosition(x, y, angleDeg)
    -- Cursor hotspot sits between the fingers, not at the texture center.
    local hotspotOffsetX = -115
    local hotspotOffsetY = -120
    local rad = math.rad(angleDeg or 0)
    local cosA, sinA = math.cos(rad), math.sin(rad)
    local rotatedX = hotspotOffsetX * cosA - hotspotOffsetY * sinA
    local rotatedY = hotspotOffsetX * sinA + hotspotOffsetY * cosA

    return x - rotatedX, y - rotatedY
end

local function GetAnimatedHandMaterial(panel)
    local status = 0
    if panel.HandSqueezeStartTime then
        local elapsed = CurTime() - panel.HandSqueezeStartTime
        local statusStep = math.min(math.floor(elapsed / handStatusStepDuration), 2)
        status = handStatusSequence[statusStep + 1] or 3
    end

    local frames = handPlaybackFrames[status]
    if frames and #frames > 0 then
        local frameIndex = (math.floor(CurTime() / handStatusFrameDuration) % #frames) + 1
        return frames[frameIndex] or frames[1]
    end

    return handMat
end

local function GetAnimatedSyringePlungerMaterial(panel)
    if #syringePlungerFrames <= 0 then return nil end
    if not panel or panel.GameType ~= "syringe" then
        return syringePlungerFrames[1]
    end

    if panel.Dragging and panel.SyringeGrabbed and panel.HandSqueezeStartTime then
        local elapsed = CurTime() - panel.HandSqueezeStartTime
        local frameIndex = (math.floor(elapsed / syringePlungerFrameDuration) % #syringePlungerFrames) + 1
        return syringePlungerFrames[frameIndex] or syringePlungerFrames[1]
    end

    local progressFrame = math.Clamp(math.floor(panel.Progress * #syringePlungerFrames) + 1, 1, #syringePlungerFrames)
    return syringePlungerFrames[progressFrame] or syringePlungerFrames[1]
end

function PANEL:Init()
    self:SetSize(ScrW(), ScrH())
    self:Center()
    self:MakePopup()
    self:SetTitle("")
    self:ShowCloseButton(false)
    self:SetDraggable(false)
    
    -- Hide the default cursor
    self:SetCursor("none")

    self.Progress = 0
    self.Turns = 0
    self.LastAngle = nil
    self.AccumulatedAngle = 0
    self.WrapAngle = 0
    self.GameType = (hg and hg.MedicalMinigame and hg.MedicalMinigame.NextType) or "bandage"
    self.TargetTurns = hg.MedicalMinigame.RequiredTurns or 6
    
    self.CenterX = ScrW() / 2
    self.CenterY = ScrH() / 2
    self.Radius = 150
    self.MaxBandageDistance = 99999
    self.BandageFollowSpeed = 2.2
    self.WrapSpeedMultiplier = 2.3
    self.VisualWrapThicknessStep = 1.5
    
    self.LastProgressSent = 0
    self.FluidVisualProgress = 0
    
    self.CurrentAngleObj = Angle(0, 0, 0)
    self.TargetAngleObj = Angle(0, 0, 0)
    
    self.TrailPoints = {}
    self.CompletedWraps = 0

    self.TourniquetStage = 1
    self.TourniquetStrapProgress = 0
    self.TourniquetStrapGrabbed = false
    self.TourniquetTubeAccumulatedAngle = 0
    self.TourniquetTubeRotation = 0
    self.TourniquetTubeRequiredTurns = 2.25
    self.TourniquetLastTubeAngle = nil
    self.TourniquetStageSwitchUntil = 0

    self.SyringeGrabbed = false
    self.SyringeGrabOffsetY = 0

    -- Parameters for smooth hand movement
    self.HandX, self.HandY = self:CursorPos()
    self.HandAngle = 0
    self.LastMX, self.LastMY = self.HandX, self.HandY
    self.ShakeX = 0
    self.ShakeY = 0

    if self.GameType == "syringe" then
        local currentAmount, totalAmount = self:GetSyringeAmounts()
        self.SyringeTotalAmount = totalAmount
        self.SyringeStartAmount = currentAmount
        self.SyringeStartRemainingFraction = totalAmount > 0 and math.Clamp(currentAmount / totalAmount, 0, 1) or 0
        self.SyringeStartUsedFraction = 1 - self.SyringeStartRemainingFraction
        self.FluidVisualProgress = self.SyringeStartUsedFraction
    elseif self.GameType == "dislocation" then
        self.DislocationTarget = hg and hg.MedicalMinigame and hg.MedicalMinigame.NextTarget or LocalPlayer()
        self.DislocationLimb = hg and hg.MedicalMinigame and hg.MedicalMinigame.NextLimb or "larm"
        self.DislocationSide = (hg and hg.MedicalMinigame and hg.MedicalMinigame.NextDislocationSide) or 1
        self.Progress = math.Clamp((hg and hg.MedicalMinigame and hg.MedicalMinigame.NextProgress) or 0, 0, 1)
        self.LastProgressSent = self.Progress
        local sign = self.DislocationSide >= 0 and 1 or -1
        self.DislocationFixedBoneWidth = 230
        self.DislocationFixedBoneHeight = 90
        self.DislocationMoveBoneWidth = 220
        self.DislocationMoveBoneHeight = 84
        self.DislocationMoveAngle = -18 * sign
        self.DislocationFixedBoneX = self.CenterX - (260 * sign)
        self.DislocationFixedBoneY = self.CenterY + 140
        local fixedEndOffset = (self.DislocationFixedBoneWidth * 0.5) - (self.DislocationFixedBoneHeight * 0.3)
        local fixedEndX = self.DislocationFixedBoneX + fixedEndOffset * sign
        local fixedEndY = self.DislocationFixedBoneY
        self.DislocationMoveX = fixedEndX + (265 * sign)
        self.DislocationMoveY = fixedEndY - 220
        self.DislocationMoveStartX = self.DislocationMoveX
        self.DislocationMoveStartY = self.DislocationMoveY
        self.DislocationVelX = 0
        self.DislocationVelY = 0
        self.DislocationDrag = 2.6
        self.DislocationMaxSpeed = 120  
        self.DislocationMaxTravel = 300
        self.DislocationAimMaxLen = 50
        self.DislocationImpulseScale = 4.0
        self.DislocationImpulseCap = 950
        self.DislocationSnapWindow = 18
        self.DislocationStableSpeed = 260
        self.DislocationAppliedForce = 0
    elseif self.GameType == "amputation" then
        self.AmputationTarget = hg and hg.MedicalMinigame and hg.MedicalMinigame.NextTarget or LocalPlayer()
        self.AmputationLimb = hg and hg.MedicalMinigame and hg.MedicalMinigame.NextLimb or "larm"
        self.Progress = math.Clamp((hg and hg.MedicalMinigame and hg.MedicalMinigame.NextProgress) or 0, 0, 1)
        self.LastProgressSent = self.Progress
        self.AmputationRequiredTravel = 8000
        self.AmputationSawRange = 190
        self.AmputationZoneHalfHeight = 115
        self.AmputationCutY = self.CenterY + 28
        local savedState = GetAmputationVisualState(self.AmputationTarget, self.AmputationLimb)
        self.AmputationKnifeOffsetX = math.Clamp(savedState and savedState.offsetX or 0, -self.AmputationSawRange, self.AmputationSawRange)
        self.AmputationKnifeAngle = savedState and savedState.angle or 0
        self.AmputationKnifeBaseY = self.AmputationCutY - 130
        self.AmputationKnifeSink = 220
        self.AmputationKnifeSwayX = savedState and savedState.swayX or 0
        self.AmputationVisualProgress = math.max(self.Progress, savedState and savedState.visualProgress or 0)
        self.AmputationMaxSwipeSpeed = 0
        self.AmputationSmoothedMoveX = 0
        self.AmputationFillSpeedCap = 520
    end

end

function PANEL:StartMusic()
    self:StopMusic()
end

function PANEL:StopMusic()
    local channel = self.MusicChannel or (hg and hg.MedicalMinigame and hg.MedicalMinigame.SoundChannel)
    self.MusicChannel = nil

    if hg and hg.MedicalMinigame and hg.MedicalMinigame.SoundChannel == channel then
        hg.MedicalMinigame.SoundChannel = nil
    end

    if not channel or not channel.Stop then return end

    if not channel.SetVolume then
        channel:Stop()
        return
    end

    local fadeTime = 0.45
    local fadeSteps = 9
    local fadeId = "hg_medical_music_fade_" .. math.floor(SysTime() * 1000000)

    for step = 1, fadeSteps do
        timer.Create(fadeId .. "_" .. step, (fadeTime / fadeSteps) * step, 1, function()
            if not channel or not channel.Stop then return end

            local volume = math.max(1 - (step / fadeSteps), 0)
            if channel.SetVolume then
                channel:SetVolume(volume)
            end

            if step == fadeSteps and channel.Stop then
                channel:Stop()
            end
        end)
    end
end

function PANEL:OnMousePressed(code)
    if code == MOUSE_LEFT then
        self.Dragging = true
        self.HandSqueezeStartTime = CurTime()
        local mx, my = self:CursorPos()
        if self.GameType == "dislocation" then
            local boneX = self.DislocationMoveX or 0
            local boneY = self.DislocationMoveY or 0
            local dx = mx - boneX
            local dy = my - boneY
            local grabRadius = 115
            self.DislocationAiming = (dx * dx + dy * dy) <= (grabRadius * grabRadius)
            if self.DislocationAiming then
                self.DislocationAimStartX = mx
                self.DislocationAimStartY = my
                self.DislocationAimX = mx
                self.DislocationAimY = my
                self.DislocationAimStartTime = SysTime()
                self.DislocationVelX = 0
                self.DislocationVelY = 0
                self.DislocationAppliedForce = 0
            end
            return
        end

        if self.GameType == "amputation" then
            self.AmputationLastMouseX = mx
            return
        end

        if self.GameType == "syringe" then
            local layout = self:GetSyringeLayout()
            self.SyringeGrabbed = self:IsNearSyringePlunger(mx, my, layout)
            if self.SyringeGrabbed then
                self.SyringeGrabOffsetY = my - layout.handleY
            else
                self.SyringeGrabOffsetY = 0
            end
            return
        end

        local ang = math.deg(math.atan2(my - self.CenterY, mx - self.CenterX))
        self.TargetAngleObj.y = ang
        
        if not self.Started then
            self.CurrentAngleObj.y = ang
            self.Started = true
        end
    elseif code == MOUSE_RIGHT then
        self:Remove()
    end
end

function PANEL:OnMouseReleased(code)
    if code == MOUSE_LEFT then
        local shouldFinishSyringe = self.GameType == "syringe" and self.Progress > 0
        if self.GameType == "dislocation" and self.DislocationAiming then
            local mx, my = self:CursorPos()
            local startX = self.DislocationAimStartX or mx
            local startY = self.DislocationAimStartY or my
            local aimX = (self.DislocationAimX or mx) - startX
            local aimY = (self.DislocationAimY or my) - startY
            local len = math.sqrt((aimX * aimX) + (aimY * aimY))
            local maxLen = self.DislocationAimMaxLen or 150
            local clampedLen = math.min(len, maxLen)

            if clampedLen > 0.001 then
                local dirX = aimX / len
                local dirY = aimY / len
                local impulse = math.Clamp(clampedLen * (self.DislocationImpulseScale or 4.0), 0, self.DislocationImpulseCap or 780)
                self.DislocationVelX = (self.DislocationVelX or 0) + dirX * impulse
                self.DislocationVelY = (self.DislocationVelY or 0) + dirY * impulse
                self.DislocationAppliedForce = math.Clamp(clampedLen / maxLen, 0, 1.6)

                net.Start("hg_medical_minigame_progress")
                net.WriteFloat(0)
                net.WriteFloat(math.Clamp(math.abs(self.DislocationAppliedForce or 0), 0, 1.6))
                net.SendToServer()
            else
                self.DislocationAppliedForce = 0
            end

            self.DislocationAiming = false
            self.DislocationAimStartX = nil
            self.DislocationAimStartY = nil
            self.DislocationAimX = nil
            self.DislocationAimY = nil
            self.DislocationAimStartTime = nil
        end
        self.Dragging = false
        self.LastAngle = nil
        self.HandSqueezeStartTime = nil
        self.TourniquetStrapGrabbed = false
        self.TourniquetLastTubeAngle = nil
        self.SyringeGrabbed = false
        self.SyringeGrabOffsetY = 0

        if shouldFinishSyringe then
            self:Finish()
        end
    end
end

function PANEL:GetRemainingBandage()
    local ply = LocalPlayer()
    if not IsValid(ply) then return 0 end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return 0 end

    local modeValues = wep.GetNetVar and wep:GetNetVar("modeValues", wep.modeValues or {}) or wep.modeValues or {}
    if self.GameType == "tourniquet" then
        if wep:GetClass() == "weapon_medkit_sh" then
            return tonumber(modeValues[4]) or 0
        end

        return tonumber(modeValues[1]) or 0
    end

    if self.GameType == "syringe" then
        if wep:GetClass() == "weapon_medkit_sh" then
            return tonumber(modeValues[3]) or 0
        end

        return tonumber(modeValues[1]) or 0
    end

    return tonumber(modeValues[1]) or 0
end

function PANEL:GetDisplayProgress()
    if self.GameType == "tourniquet" then
        local tubeProgress = math.Clamp(self.TourniquetTubeAccumulatedAngle / (2 * math.pi * self.TourniquetTubeRequiredTurns), 0, 1)
        if self.TourniquetStage <= 1 then
            return self.TourniquetStrapProgress
        end

        return tubeProgress
    end

    return self.Progress
end

function PANEL:GetSyringeAmounts()
    local ply = LocalPlayer()
    if not IsValid(ply) then return 0, 1 end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return 0, 1 end

    local modeValueIndex = (wep:GetClass() == "weapon_medkit_sh") and 3 or 1
    local modeValues = wep.GetNetVar and wep:GetNetVar("modeValues", wep.modeValues or {}) or wep.modeValues or {}
    local currentAmount = math.max(tonumber(modeValues[modeValueIndex]) or 0, 0)
    local configuredValue = wep.modeValuesdef and wep.modeValuesdef[modeValueIndex]
    local totalAmount = math.max(tonumber(istable(configuredValue) and configuredValue[1] or configuredValue) or currentAmount or 1, 0.0001)

    return currentAmount, totalAmount
end

function PANEL:GetSyringeDisplayUsedFraction()
    local startRemainingFraction = math.Clamp(self.SyringeStartRemainingFraction or 1, 0, 1)
    local startUsedFraction = math.Clamp(self.SyringeStartUsedFraction or 0, 0, 1)
    return math.Clamp(startUsedFraction + (self.Progress * startRemainingFraction), 0, 1)
end

function PANEL:BeginTourniquetTubeStage()
    self.TourniquetStage = 2
    self.TourniquetStrapGrabbed = false
    self.TourniquetLastTubeAngle = nil
    self.TourniquetTubeAccumulatedAngle = 0
    self.TourniquetTubeRotation = 0
    self.TourniquetStageSwitchUntil = CurTime() + 0.25
end

function PANEL:ResetWrapProgress()
    self.Progress = 0
    self.AccumulatedAngle = 0
    self.WrapAngle = 0
    self.LastProgressSent = 0
    self.LastAngle = nil
    self.TrailPoints = {}
end

function PANEL:CommitVisualWrap()
    self.CompletedWraps = self.CompletedWraps + 1
    self.WrapAngle = math.max(self.WrapAngle - (2 * math.pi), 0)
end

function PANEL:CompleteWrap()
    if self.Progress > self.LastProgressSent then
        net.Start("hg_medical_minigame_progress")
        net.WriteFloat(self.Progress - self.LastProgressSent)
        net.SendToServer()
    end

    if self:GetRemainingBandage() <= 0 then
        self:Finish()
        return
    end

    self:CommitVisualWrap()

    self:ResetWrapProgress()
end

function PANEL:ThinkTourniquet(mx, my)
    local limbRadius = 92
    local strapAnchorX = self.CenterX + limbRadius - 4
    local strapAnchorY = self.CenterY - limbRadius + 2
    local strapStartX = strapAnchorX + 18
    local strapEndX = self.CenterX + 320
    local strapY = strapAnchorY
    local knobX = self.CenterX
    local knobY = self.CenterY + 10

    if self.TourniquetStage == 1 then
        local nearStrap = math.abs(my - strapY) <= 80
        local normalized = math.Clamp((mx - strapStartX) / (strapEndX - strapStartX), 0, 1)

        if not self.TourniquetStrapGrabbed and nearStrap and normalized <= 0.18 then
            self.TourniquetStrapGrabbed = true
        end

        if self.TourniquetStrapGrabbed and nearStrap then
            self.TourniquetStrapProgress = math.max(self.TourniquetStrapProgress, normalized)
        end

        if self.TourniquetStrapProgress >= 1 then
            self:BeginTourniquetTubeStage()
        end
    elseif self.TourniquetStage == 2 then
        if self.TourniquetStageSwitchUntil > CurTime() then
            self.TourniquetLastTubeAngle = nil
            return
        end

        local distToKnob = math.Distance(mx, my, knobX, knobY)
        if distToKnob <= 155 then
            local angle = math.atan2(my - knobY, mx - knobX)

            if self.TourniquetLastTubeAngle then
                local diff = NormalizeAngleDiff(angle - self.TourniquetLastTubeAngle)
                self.TourniquetTubeAccumulatedAngle = self.TourniquetTubeAccumulatedAngle + math.abs(diff)
                self.TourniquetTubeRotation = self.TourniquetTubeRotation + math.deg(diff)

                if self.TourniquetTubeAccumulatedAngle >= (2 * math.pi * self.TourniquetTubeRequiredTurns) then
                    self:Finish()
                    return
                end
            end

            self.TourniquetLastTubeAngle = angle
        else
            self.TourniquetLastTubeAngle = nil
        end
    end
end

function PANEL:GetSyringeLayout()
    local sourceWidth = 700
    local sourceHeight = 1300
    local baseSpriteHeight = 940
    local plungerSpriteHeight = 940
    local baseSpriteWidth = math.floor(baseSpriteHeight * (sourceWidth / sourceHeight))
    local plungerSpriteWidth = math.floor(plungerSpriteHeight * (sourceWidth / sourceHeight))
    local barrelCenterX = 342
    local barrelCenterY = 581
    local plungerCenterX = barrelCenterX
    local handleSourceY = 210
    local plungerTravelSource = 130
    local barrelScreenCenterX = self.CenterX + 0
    local baseCenterX = barrelScreenCenterX - 8.5
    local baseCenterY = self.CenterY + 135
    local plungerCenterY = self.CenterY + 20
    local baseX = baseCenterX - (baseSpriteWidth * (barrelCenterX / sourceWidth))
    local baseY = baseCenterY - (baseSpriteHeight * (barrelCenterY / sourceHeight))
    local plungerBaseY = plungerCenterY - (plungerSpriteHeight * (barrelCenterY / sourceHeight)) - 220
    local fullPlungerTravel = plungerSpriteHeight * (plungerTravelSource / sourceHeight)
    local startUsedFraction = math.Clamp(self.SyringeStartUsedFraction or 0, 0, 1)
    local startRemainingFraction = math.Clamp(self.SyringeStartRemainingFraction or 1, 0, 1)
    local displayUsedFraction = self:GetSyringeDisplayUsedFraction()
    local plungerY = plungerBaseY + (displayUsedFraction * fullPlungerTravel)

    return {
        baseX = baseX,
        baseY = baseY,
        baseWidth = baseSpriteWidth,
        baseHeight = baseSpriteHeight,
        plungerX = barrelScreenCenterX - (plungerSpriteWidth * (plungerCenterX / sourceWidth)),
        plungerY = plungerY,
        plungerWidth = plungerSpriteWidth,
        plungerHeight = plungerSpriteHeight,
        plungerTravel = fullPlungerTravel,
        sessionTravel = math.max(fullPlungerTravel * startRemainingFraction, 1),
        handleX = barrelScreenCenterX,
        handleY = plungerY + (plungerSpriteHeight * (handleSourceY / sourceHeight)),
        handleBaseY = plungerBaseY + (startUsedFraction * fullPlungerTravel) + (plungerSpriteHeight * (handleSourceY / sourceHeight)),
        handleRadius = plungerSpriteWidth * 0.18,
        sourceWidth = sourceWidth,
        sourceHeight = sourceHeight
    }
end

function PANEL:IsNearSyringePlunger(mx, my, layout)
    layout = layout or self:GetSyringeLayout()
    return math.Distance(mx, my, layout.handleX, layout.handleY) <= layout.handleRadius
end

function PANEL:ThinkSyringe(mx, my)
    local layout = self:GetSyringeLayout()
    if not self.SyringeGrabbed then
        return
    end

    local handleTargetY = my - (self.SyringeGrabOffsetY or 0)
    local normalized = math.Clamp((handleTargetY - layout.handleBaseY) / layout.sessionTravel, 0, 1)
    local newProgress = math.max(self.Progress, normalized)
    if newProgress <= self.Progress then return end

    self.Progress = newProgress

    if self.Progress - self.LastProgressSent >= 0.02 then
        net.Start("hg_medical_minigame_progress")
        net.WriteFloat(self.Progress - self.LastProgressSent)
        net.SendToServer()
        self.LastProgressSent = self.Progress
    end

    if self.Progress >= 1 then
        self:Finish()
    end
end

function PANEL:ThinkAmputation(mx, my)
    local sawRange = self.AmputationSawRange or 175
    local clampedX = math.Clamp(mx, self.CenterX - sawRange, self.CenterX + sawRange)
    local targetOffsetX = clampedX - self.CenterX
    local sideTilt = (targetOffsetX / sawRange) * 34
    local moveX = (mx - (self.AmputationLastMouseX or mx))
    self.AmputationSmoothedMoveX = Lerp(FrameTime() * 7, self.AmputationSmoothedMoveX or moveX, moveX)
    local smoothMoveX = self.AmputationSmoothedMoveX or moveX
    local movementSwayX = math.Clamp(smoothMoveX * 1.15, -14, 14)
    local movementSwayAngle = math.Clamp(smoothMoveX * 0.11, -1.8, 1.8)
    local targetAngle = sideTilt + movementSwayAngle

    self.AmputationKnifeSwayX = Lerp(FrameTime() * 2.1, self.AmputationKnifeSwayX or movementSwayX, movementSwayX)
    self.AmputationKnifeOffsetX = Lerp(FrameTime() * 1.0, self.AmputationKnifeOffsetX or targetOffsetX, targetOffsetX)
    self.AmputationKnifeAngle = Lerp(FrameTime() * 1.35, self.AmputationKnifeAngle or targetAngle, targetAngle)
    local visualProgressTarget = math.max(self.Progress, self.AmputationVisualProgress or self.Progress)
    self.AmputationVisualProgress = Lerp(FrameTime() * 0.95, self.AmputationVisualProgress or visualProgressTarget, visualProgressTarget)
    SetAmputationVisualState(self.AmputationTarget, self.AmputationLimb, {
        offsetX = self.AmputationKnifeOffsetX or 0,
        angle = self.AmputationKnifeAngle or 0,
        swayX = self.AmputationKnifeSwayX or 0,
        visualProgress = self.AmputationVisualProgress or self.Progress
    })

    if not self.Dragging or not input.IsMouseDown(MOUSE_LEFT) then
        self.AmputationLastMouseX = mx
        return
    end

    if math.abs(my - (self.AmputationCutY or self.CenterY)) > (self.AmputationZoneHalfHeight or 115) then
        self.AmputationLastMouseX = mx
        return
    end

    local moveDistance = math.abs(moveX)
    local swipeSpeed = moveDistance / math.max(FrameTime(), 0.001)
    local cappedSwipeSpeed = math.min(swipeSpeed, self.AmputationFillSpeedCap or 520)
    local effectiveMoveDistance = cappedSwipeSpeed * FrameTime()
    local delta = math.min(effectiveMoveDistance / math.max(self.AmputationRequiredTravel or 5600, 1), 1 - self.Progress)

    if delta > 0 then
        self.Progress = math.min(self.Progress + delta, 1)
        self.AmputationMaxSwipeSpeed = math.max(self.AmputationMaxSwipeSpeed or 0, swipeSpeed)

        if self.Progress - self.LastProgressSent >= 0.01 then
            net.Start("hg_medical_minigame_progress")
            net.WriteFloat(self.Progress - self.LastProgressSent)
            net.WriteFloat(self.AmputationMaxSwipeSpeed or swipeSpeed)
            net.SendToServer()

            self.LastProgressSent = self.Progress
            self.AmputationMaxSwipeSpeed = 0
            surface.PlaySound("physics/flesh/flesh_squishy_impact_hard2.wav")
        end
    end

    if self.Progress >= 1 then
        self:Finish()
    end

    self.AmputationLastMouseX = mx
end

function PANEL:GetDislocationLabel()
    return dislocationLimbLabels[self.DislocationLimb] or "JOINT"
end

function PANEL:ThinkDislocation(mx, my)
    local dt = FrameTime()
    local now = SysTime()
    local aiming = self.DislocationAiming == true and self.Dragging and input.IsMouseDown(MOUSE_LEFT)
    if aiming then
        self.DislocationAimX = mx
        self.DislocationAimY = my
        local startX = self.DislocationAimStartX or mx
        local startY = self.DislocationAimStartY or my
        local aimX = mx - startX
        local aimY = my - startY
        local len = math.sqrt((aimX * aimX) + (aimY * aimY))
        local maxLen = self.DislocationAimMaxLen or 150
        self.DislocationAppliedForce = math.Clamp(len / maxLen, 0, 1.6)
        self.DislocationVelX = 0
        self.DislocationVelY = 0
    else
        local drag = math.exp(-dt * (self.DislocationDrag or 2.6))
        self.DislocationVelX = (self.DislocationVelX or 0) * drag
        self.DislocationVelY = (self.DislocationVelY or 0) * drag

        local maxSpeed = self.DislocationMaxSpeed or 820
        local speed = math.sqrt((self.DislocationVelX or 0) ^ 2 + (self.DislocationVelY or 0) ^ 2)
        if speed > maxSpeed and speed > 0.001 then
            local scale = maxSpeed / speed
            self.DislocationVelX = (self.DislocationVelX or 0) * scale
            self.DislocationVelY = (self.DislocationVelY or 0) * scale
        end

        self.DislocationMoveX = (self.DislocationMoveX or 0) + (self.DislocationVelX or 0) * dt
        self.DislocationMoveY = (self.DislocationMoveY or 0) + (self.DislocationVelY or 0) * dt

        local startX = self.DislocationMoveStartX or self.DislocationMoveX or 0
        local startY = self.DislocationMoveStartY or self.DislocationMoveY or 0
        local dx = (self.DislocationMoveX or 0) - startX
        local dy = (self.DislocationMoveY or 0) - startY
        local dist = math.sqrt((dx * dx) + (dy * dy))
        local maxTravel = self.DislocationMaxTravel or 330
        if dist > maxTravel and dist > 0.001 then
            local scale = maxTravel / dist
            self.DislocationMoveX = startX + dx * scale
            self.DislocationMoveY = startY + dy * scale
            self.DislocationVelX = (self.DislocationVelX or 0) * 0.35
            self.DislocationVelY = (self.DislocationVelY or 0) * 0.35
        end

        local speed2 = math.sqrt((self.DislocationVelX or 0) ^ 2 + (self.DislocationVelY or 0) ^ 2)
        self.DislocationAppliedForce = math.Clamp(speed2 / 900, 0, 1.6)
    end

    local fixedX = self.DislocationFixedBoneX or self.CenterX
    local fixedY = self.DislocationFixedBoneY or self.CenterY
    local fixedW = self.DislocationFixedBoneWidth or 230
    local fixedH = self.DislocationFixedBoneHeight or 90
    local fixedSign = (self.DislocationSide or 1) >= 0 and 1 or -1
    local fixedEndOffset = (fixedW * 0.5) - (fixedH * 0.3)
    local fixedEndX = fixedX + fixedEndOffset * fixedSign
    local fixedEndY = fixedY

    local moveX = self.DislocationMoveX or self.CenterX
    local moveY = self.DislocationMoveY or self.CenterY
    local moveW = self.DislocationMoveBoneWidth or 220
    local moveH = self.DislocationMoveBoneHeight or 84
    local moveAng = self.DislocationMoveAngle or (-18 * fixedSign)
    local moveEndOffset = (moveW * 0.5) - (moveH * 0.3)
    local moveContactSign = -fixedSign
    local moveRad = math.rad(moveAng)
    local moveCos, moveSin = math.cos(moveRad), math.sin(moveRad)
    local moveEndX = moveX + (moveEndOffset * moveContactSign) * moveCos
    local moveEndY = moveY + (moveEndOffset * moveContactSign) * moveSin

    local diffX = moveEndX - fixedEndX
    local diffY = moveEndY - fixedEndY
    local distanceToSocket = math.sqrt((diffX * diffX) + (diffY * diffY))
    local speed = math.sqrt((self.DislocationVelX or 0) ^ 2 + (self.DislocationVelY or 0) ^ 2)
    local withinSnap = distanceToSocket <= (self.DislocationSnapWindow or 30)
    local stableForce = math.abs(self.DislocationAppliedForce or 0) <= 1.45

    if withinSnap and stableForce then
        local distanceFactor = 1 - math.Clamp(distanceToSocket / math.max(self.DislocationSnapWindow or 24, 1), 0, 1)
        local speedFactor = 1 - math.Clamp(speed / math.max(self.DislocationStableSpeed or 120, 1), 0, 1)
        local gain = math.max(distanceFactor * speedFactor, 0) * dt * 0.9
        local newProgress = math.min(self.Progress + gain, 1)

        if newProgress > self.Progress then
            self.Progress = newProgress
            if self.Progress - self.LastProgressSent >= 0.01 then
                net.Start("hg_medical_minigame_progress")
                net.WriteFloat(self.Progress - self.LastProgressSent)
                net.WriteFloat(math.Clamp(math.abs(self.DislocationAppliedForce or 0), 0, 1.6))
                net.SendToServer()
                self.LastProgressSent = self.Progress
            end
        end
    end

    if self.Progress >= 1 then
        self:Finish()
    end
end

function PANEL:GetSyringeFluidColor()
    local ply = LocalPlayer()
    if not IsValid(ply) then return Color(160, 70, 180, 175) end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return Color(160, 70, 180, 175) end

    local class = wep:GetClass()
    if class == "weapon_fentanyl" then
        return Color(175, 55, 55, 180)
    end

    if class == "weapon_medkit_sh" and wep.mode == 3 then
        return Color(90, 175, 120, 180)
    end

    return Color(160, 70, 180, 175)
end

function PANEL:Think()
    local mx, my = self:CursorPos()
    if self.GameType == "bandage" then
        local currentBandageRad = math.rad(self.CurrentAngleObj.y)
        local bandageX = self.CenterX + math.cos(currentBandageRad) * self.Radius
        local bandageY = self.CenterY + math.sin(currentBandageRad) * self.Radius
        local distFromBandage = math.Distance(mx, my, bandageX, bandageY)
        self.CursorTooFar = distFromBandage > self.MaxBandageDistance
    else
        self.CursorTooFar = false
    end
    
    -- Smoothly follow the cursor with the hand
    local lerpSpeed = FrameTime() * 10
    self.HandX = Lerp(lerpSpeed, self.HandX, mx)
    self.HandY = Lerp(lerpSpeed, self.HandY, my)

    -- Calculate hand tilt based on movement
    local dx = mx - self.LastMX
    local targetTilt = math.Clamp(dx * 2, -15, 15) -- Tilt up to 15 degrees
    self.HandAngle = Lerp(FrameTime() * 5, self.HandAngle, targetTilt)
    
    self.LastMX, self.LastMY = mx, my

    if self.GameType == "dislocation" then
        self:ThinkDislocation(mx, my)
    elseif self.GameType == "amputation" then
        self:ThinkAmputation(mx, my)
    elseif self.Dragging and input.IsMouseDown(MOUSE_LEFT) then
        if self.GameType == "tourniquet" then
            self:ThinkTourniquet(mx, my)
        elseif self.GameType == "syringe" then
            self:ThinkSyringe(mx, my)
        elseif self.CursorTooFar then
            self.LastAngle = nil
        else
            local ang = math.deg(math.atan2(my - self.CenterY, mx - self.CenterX))
            local targetRad = math.rad(ang)
            local currentTargetRad = math.rad(self.TargetAngleObj.y)
            local aimDiff = NormalizeAngleDiff(targetRad - currentTargetRad)

            if aimDiff <= 0 then
                self.TargetAngleObj.y = ang
            end

            local bandageLerpSpeed = FrameTime() * self.BandageFollowSpeed
            self.CurrentAngleObj = LerpAngle(bandageLerpSpeed, self.CurrentAngleObj, self.TargetAngleObj)
            
            local currentRad = math.rad(self.CurrentAngleObj.y)
            
            if self.LastAngle then
                local diff = NormalizeAngleDiff(currentRad - self.LastAngle)

                -- Only count wrapping progress when rotating to the left.
                local leftDiff = math.max(-diff, 0) * self.WrapSpeedMultiplier

                self.AccumulatedAngle = self.AccumulatedAngle + leftDiff
                self.WrapAngle = self.WrapAngle + leftDiff
                
                if leftDiff > 0.001 then
                    AppendBandageTrail(
                        self.TrailPoints,
                        self.LastAngle,
                        currentRad,
                        math.rad(1.5)
                    )
                end

                while self.WrapAngle >= (2 * math.pi) do
                    self:CommitVisualWrap()
                end

                self.Progress = math.min(self.AccumulatedAngle / (2 * math.pi * self.TargetTurns), 1)
                
                if self.Progress - self.LastProgressSent >= 0.05 then
                    net.Start("hg_medical_minigame_progress")
                    net.WriteFloat(self.Progress - self.LastProgressSent)
                    net.SendToServer()
                    self.LastProgressSent = self.Progress
                end
                
                if self.Progress >= 1 then
                    self:CompleteWrap()
                end
            end
            
            self.LastAngle = currentRad
        end
    else
        self.Dragging = false
        self.LastAngle = nil
        self.HandSqueezeStartTime = nil
    end

    local lp = LocalPlayer()
    if not IsValid(lp) or not lp:Alive() or IsLocalPlayerUnconscious() then
        if not IsValid(lp) or not lp:Alive() then
            ClearAllAmputationVisualState()
        end

        self:Remove()
        return
    end
    if self.GameType ~= "amputation" and self.GameType ~= "dislocation" and self:GetRemainingBandage() <= 0 then
        self:Finish()
        return
    end
end

function PANEL:Finish()
    if self.Finished then return end
    self.Finished = true
    self:StopMusic()
    
    if (self.GameType == "bandage" or self.GameType == "syringe" or self.GameType == "amputation" or self.GameType == "dislocation") and self.Progress > self.LastProgressSent then
        net.Start("hg_medical_minigame_progress")
        net.WriteFloat(self.Progress - self.LastProgressSent)
        if self.GameType == "amputation" then
            net.WriteFloat(0)
        elseif self.GameType == "dislocation" then
            net.WriteFloat(math.abs(self.DislocationAppliedForce or 0))
        end
        net.SendToServer()
    end

    net.Start("hg_medical_minigame_finish")
    net.WriteString(self.GameType or "")
    net.WriteFloat(math.Clamp(self.Progress or 0, 0, 1))
    net.SendToServer()

    if self.GameType == "amputation" then
        ClearAmputationVisualState(self.AmputationTarget, self.AmputationLimb)
    end
    
    if self.GameType == "syringe" then
        surface.PlaySound("snd_jack_hmcd_needleprick.wav")
    elseif self.GameType == "dislocation" then
        surface.PlaySound("physics/flesh/flesh_impact_hard6.wav")
    elseif self.GameType == "amputation" then
        surface.PlaySound("physics/body/body_medium_break3.wav")
    else
        surface.PlaySound("snd_jack_hmcd_bandage.wav")
    end
    
    self:AlphaTo(0, 0.2, 0, function()
        self:Remove()
    end)
end

function PANEL:OnRemove()
    self:StopMusic()

    if not self.Finished and self.GameType == "amputation" and self.Progress > self.LastProgressSent then
        net.Start("hg_medical_minigame_progress")
        net.WriteFloat(self.Progress - self.LastProgressSent)
        net.WriteFloat(self.AmputationMaxSwipeSpeed or 0)
        net.SendToServer()
    end

    if not self.Finished and self.GameType == "dislocation" and self.Progress > self.LastProgressSent then
        net.Start("hg_medical_minigame_progress")
        net.WriteFloat(self.Progress - self.LastProgressSent)
        net.WriteFloat(math.abs(self.DislocationAppliedForce or 0))
        net.SendToServer()
    end

    if hg and hg.MedicalMinigame and hg.MedicalMinigame.Panel == self then
        hg.MedicalMinigame.Panel = nil
    end
end

function PANEL:DrawCommonOverlays(progress, showBleedIndicator)
    local lp = LocalPlayer()
    local shakeX, shakeY = 0, 0
    if showBleedIndicator == nil then
        showBleedIndicator = true
    end

    if IsValid(lp) then
        local pain = lp:GetNWFloat("pain", 0)
        if lp.organism and lp.organism.pain then pain = lp.organism.pain end
        if pain > 10 then
            local intensity = math.min(pain / 20, 15)
            local t = CurTime()
            shakeX = math.sin(t * 9.5) * intensity
            shakeY = math.cos(t * 12.0) * intensity * 0.7
        end
    end

    if showBleedIndicator and IsValid(lp) then
        local bleed = 0
        if lp.organism and lp.organism.bleed then
            bleed = lp.organism.bleed
        else
            bleed = lp:GetNWFloat("bleed", 0)
        end

        local woundSeverity = 0
        local wounds = lp.GetNetVar and lp:GetNetVar("wounds", nil)
        if istable(wounds) then
            for _, wound in ipairs(wounds) do
                if istable(wound) then
                    woundSeverity = woundSeverity + math.max(tonumber(wound[1]) or 0, 0)
                end
            end
        end

        local arterialSeverity = 0
        local arterialWounds = lp.GetNetVar and lp:GetNetVar("arterialwounds", nil)
        if istable(arterialWounds) then
            arterialSeverity = #arterialWounds * 12
        end

        local bleedVisualStrength = math.max(bleed, woundSeverity * 0.18, arterialSeverity)
        local targetIndicatorSize = math.Clamp(48 + (bleedVisualStrength * 20), 62, 165)
        self.BleedIndicatorSize = Lerp(FrameTime() * 8, self.BleedIndicatorSize or targetIndicatorSize, targetIndicatorSize)
        local indicatorSize = self.BleedIndicatorSize
        if bleed > 0.01 then
            local frameSpeed = math.Clamp(0.18 - (bleed * 0.01), 0.06, 0.18)
            local frameIndex = (math.floor(CurTime() / frameSpeed) % math.max(bleedFrameCount, 1)) + 1
            local frameMat = bleedFrames[frameIndex] or bleedFrames[1]
            local glowRadius = (indicatorSize + 24) * 0.5

            draw.NoTexture()
            local glowPoly = {}
            for i = 0, 32 do
                local a = math.rad((i / 32) * 360)
                glowPoly[#glowPoly + 1] = {
                    x = self.CenterX + math.cos(a) * glowRadius,
                    y = self.CenterY + math.sin(a) * glowRadius
                }
            end

            if SetHudMaterial(frameMat) then
                surface.SetDrawColor(255, 255, 255, 35)
                surface.DrawPoly(glowPoly)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(self.CenterX - indicatorSize / 2, self.CenterY - indicatorSize / 2, indicatorSize, indicatorSize)
            else
                surface.SetDrawColor(120, 0, 0, 80)
                surface.DrawPoly(glowPoly)
                surface.SetDrawColor(170, 20, 20, 220)
                draw.NoTexture()
                local bloodPoly = {}
                local dropRadius = indicatorSize * 0.32
                local topY = self.CenterY - indicatorSize * 0.16

                bloodPoly[#bloodPoly + 1] = {x = self.CenterX, y = topY - dropRadius * 1.2}
                for i = 0, 20 do
                    local a = math.rad((i / 20) * 360)
                    bloodPoly[#bloodPoly + 1] = {
                        x = self.CenterX + math.cos(a) * dropRadius,
                        y = topY + math.sin(a) * dropRadius
                    }
                end
                bloodPoly[#bloodPoly + 1] = {x = self.CenterX, y = self.CenterY + indicatorSize * 0.36}
                surface.DrawPoly(bloodPoly)
            end
        end
    end

    local progressSegments = 64
    local startAngle = -math.pi / 2
    local endAngle = startAngle + (progress * 2 * math.pi)
    
    if progress > 0 then
        local ringCol = (self.GameType == "bandage" and IsBruiceKitActive()) and Color(120, 255, 120) or Color(255, 255, 255)
        surface.SetDrawColor(ringCol.r, ringCol.g, ringCol.b, 40)
        for i = 0, progressSegments * progress do
            local a1 = startAngle + (i / progressSegments) * 2 * math.pi
            local a2 = startAngle + ((i + 1) / progressSegments) * 2 * math.pi
            if a2 > endAngle then a2 = endAngle end
            local r1 = self.Radius + 40
            local r2 = self.Radius + 45
            local p1x, p1y = self.CenterX + math.cos(a1) * r1, self.CenterY + math.sin(a1) * r1
            local p2x, p2y = self.CenterX + math.cos(a2) * r1, self.CenterY + math.sin(a2) * r1
            local p3x, p3y = self.CenterX + math.cos(a2) * r2, self.CenterY + math.sin(a2) * r2
            local p4x, p4y = self.CenterX + math.cos(a1) * r2, self.CenterY + math.sin(a1) * r2
            surface.DrawPoly({
                {x = p1x, y = p1y},
                {x = p2x, y = p2y},
                {x = p3x, y = p3y},
                {x = p4x, y = p4y}
            })
        end
    end

    if self.GameType ~= "syringe" then
        local handDrawX, handDrawY = GetHandDrawPosition(self.HandX + shakeX, self.HandY + shakeY, self.HandAngle)
        local currentHandMat = GetAnimatedHandMaterial(self)
        if SetHudMaterial(currentHandMat) then
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawTexturedRectRotated(handDrawX, handDrawY, 650, 500, self.HandAngle)
        else
            DrawFallbackHand(handDrawX, handDrawY, self.HandAngle)
        end
    end
end

function PANEL:PaintTourniquet(w, h)
    surface.SetDrawColor(0, 0, 0, 240)
    surface.DrawRect(0, 0, w, h)

    local stage = self.TourniquetStage
    local limbRadius = 92
    local strapAnchorX = self.CenterX + limbRadius - 2
    local strapAnchorY = self.CenterY - limbRadius + 18
    local strapStartX = strapAnchorX + 18
    local strapEndX = self.CenterX + 320
    local strapY = strapAnchorY
    local buckleX = self.CenterX + limbRadius - 34
    local knobX = self.CenterX
    local knobY = self.CenterY + 10
    local strapProgressX = Lerp(self.TourniquetStrapProgress, strapStartX, strapEndX)

    surface.SetDrawColor(40, 30, 25, 255)
    draw.NoTexture()
    local limbPoly = {}
    for i = 0, 64 do
        local a = math.rad((i / 64) * 360)
        limbPoly[#limbPoly + 1] = {
            x = self.CenterX + math.cos(a) * limbRadius,
            y = self.CenterY + math.sin(a) * limbRadius
        }
    end
    surface.DrawPoly(limbPoly)

    if stage == 1 then
        draw.NoTexture()
        surface.SetDrawColor(185, 35, 35, 255)
        surface.DrawPoly({
            {x = self.CenterX - limbRadius - 10, y = self.CenterY - 30},
            {x = self.CenterX + limbRadius - 10, y = self.CenterY - 30},
            {x = self.CenterX + limbRadius + 10, y = self.CenterY + 30},
            {x = self.CenterX - limbRadius + 10, y = self.CenterY + 30}
        })

        surface.SetDrawColor(190, 45, 45, 255)
        surface.DrawLine(self.CenterX + 6, self.CenterY - limbRadius - 4, strapAnchorX, strapAnchorY)
        surface.DrawLine(self.CenterX + 14, self.CenterY - limbRadius + 4, strapAnchorX, strapAnchorY)
        surface.DrawLine(self.CenterX + 22, self.CenterY - limbRadius + 12, strapAnchorX, strapAnchorY)

        draw.RoundedBox(6, strapAnchorX - 8, strapAnchorY - 8, 16, 16, Color(220, 55, 55, 255))
        surface.SetDrawColor(190, 70, 70, 95)
        surface.DrawLine(strapStartX, strapY, strapEndX, strapY)

        local strapWidth = math.max((strapProgressX - strapAnchorX) + 18, 28)
        draw.RoundedBox(4, strapAnchorX, strapY - 11, strapWidth, 22, Color(190, 40, 40, 255))
        draw.RoundedBox(4, strapProgressX - 11, strapY - 11, 22, 22, Color(235, 80, 80, 255))

        surface.SetDrawColor(255, 160, 160, 170)
        surface.DrawRect(strapStartX - 5, strapY - 5, 10, 10)
        surface.DrawRect(strapEndX - 5, strapY - 5, 10, 10)
    else
        draw.NoTexture()
        surface.SetDrawColor(245, 245, 245, 255)
        surface.DrawPoly({
            {x = self.CenterX - limbRadius - 8, y = self.CenterY - 26},
            {x = self.CenterX + limbRadius - 8, y = self.CenterY - 26},
            {x = self.CenterX + limbRadius + 8, y = self.CenterY + 26},
            {x = self.CenterX - limbRadius + 8, y = self.CenterY + 26}
        })

        draw.RoundedBox(5, buckleX - 10, strapY - 26, 20, 52, Color(150, 150, 150, 255))
        draw.RoundedBox(4, buckleX, strapY - 13, math.max((strapEndX - buckleX) + 18, 20), 26, Color(240, 240, 240, 255))

        draw.RoundedBox(8, knobX - 72, knobY - 72, 144, 144, Color(30, 30, 30, 245))
        draw.RoundedBox(6, knobX - 28, knobY - 28, 56, 56, Color(175, 175, 175, 255))
        DrawRotatedBar(knobX, knobY, 116, 18, self.TourniquetTubeRotation, Color(245, 245, 245, 255))
        DrawRotatedBar(knobX, knobY, 18, 116, self.TourniquetTubeRotation, Color(245, 245, 245, 255))

        if self.TourniquetStageSwitchUntil > CurTime() then
            local alpha = math.Clamp((self.TourniquetStageSwitchUntil - CurTime()) / 0.25, 0, 1) * 180
            surface.SetDrawColor(0, 0, 0, alpha)
            surface.DrawRect(0, 0, w, h)
        end
    end

    self:DrawCommonOverlays(self:GetDisplayProgress(), false)
end

function PANEL:PaintSyringe(w, h)
    surface.SetDrawColor(0, 0, 0, 240)
    surface.DrawRect(0, 0, w, h)

    local layout = self:GetSyringeLayout()
    local fluidColor = self:GetSyringeFluidColor()
    local fluidSourceLeft = 311
    local fluidSourceTop = 600
    local fluidSourceWidth = 72
    local fluidSourceHeight = 170
    local fluidX = layout.baseX + (layout.baseWidth * (fluidSourceLeft / layout.sourceWidth))
    local fluidWidth = layout.baseWidth * (fluidSourceWidth / layout.sourceWidth)
    local fluidTopY = layout.baseY + (layout.baseHeight * (fluidSourceTop / layout.sourceHeight))
    local fluidHeight = layout.baseHeight * (fluidSourceHeight / layout.sourceHeight)
    local fluidBottomY = fluidTopY + fluidHeight
    local barrelTopY = layout.baseY + (layout.baseHeight * (390 / layout.sourceHeight))
    local barrelBottomY = layout.baseY + (layout.baseHeight * (955 / layout.sourceHeight))
    self.FluidVisualProgress = self:GetSyringeDisplayUsedFraction()
    local remainingFluidHeight = math.max(fluidHeight * (1 - self.FluidVisualProgress), 0)
    local fluidY = fluidBottomY - remainingFluidHeight
    local plungerMat = GetAnimatedSyringePlungerMaterial(self)

    surface.SetDrawColor(fluidColor.r, fluidColor.g, fluidColor.b, 45)
    surface.DrawRect(fluidX - 6, fluidTopY - 6, fluidWidth + 12, fluidHeight + 12)

    surface.SetDrawColor(fluidColor.r, fluidColor.g, fluidColor.b, fluidColor.a or 180)
    if remainingFluidHeight > 0 then
        surface.DrawRect(fluidX, fluidY, fluidWidth, remainingFluidHeight)
    end

    if plungerMat and SetHudMaterial(plungerMat) then
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(layout.plungerX, layout.plungerY, layout.plungerWidth, layout.plungerHeight)
    end

    if SetHudMaterial(syringeBaseMat) then
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(layout.baseX, layout.baseY, layout.baseWidth, layout.baseHeight)
    else
        draw.RoundedBox(12, layout.baseX + layout.baseWidth * 0.42, layout.baseY + layout.baseHeight * 0.3, layout.baseWidth * 0.16, layout.baseHeight * 0.43, Color(25, 25, 25, 210))
        draw.RoundedBox(6, fluidX, fluidTopY, fluidWidth, fluidHeight, Color(55, 55, 55, 120))
        draw.RoundedBox(4, layout.baseX + layout.baseWidth * 0.455, layout.baseY + layout.baseHeight * 0.69, layout.baseWidth * 0.09, layout.baseHeight * 0.05, Color(30, 30, 30, 240))
    end

    self:DrawCommonOverlays(self.Progress, false)
end

function PANEL:PaintAmputation(w, h)
    surface.SetDrawColor(0, 0, 0, 240)
    surface.DrawRect(0, 0, w, h)

    local stumpRadius = 132
    local cutY = self.AmputationCutY or (self.CenterY + 28)
    local knifeX = self.CenterX + (self.AmputationKnifeOffsetX or 0) + (self.AmputationKnifeSwayX or 0)
    local knifeY = (self.AmputationKnifeBaseY or (cutY - 150)) + ((self.AmputationKnifeSink or 110) * (self.AmputationVisualProgress or self.Progress))

    DrawFilledCircle(self.CenterX, self.CenterY + 54, stumpRadius + 10, Color(245, 245, 245, 255), 64)
    DrawFilledCircle(self.CenterX, self.CenterY + 54, stumpRadius, Color(112, 72, 12, 255), 64)
    DrawFilledCircle(self.CenterX, self.CenterY + 54, stumpRadius * 0.25, Color(245, 245, 245, 255), 42)
    DrawFilledCircle(self.CenterX, self.CenterY + 54, stumpRadius * 0.09, Color(180, 180, 180, 255), 24)

    DrawAmputationBlade(knifeX, knifeY, 455, 150, self.AmputationKnifeAngle or -14)

    draw.SimpleText("The faster you move the knife, the stronger the pain.", "Trebuchet24", self.CenterX, self.CenterY + 255, Color(235, 235, 235, 210), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function PANEL:PaintDislocation(w, h)
    surface.SetDrawColor(0, 0, 0, 240)
    surface.DrawRect(0, 0, w, h)

    local fixedX = self.DislocationFixedBoneX or (self.CenterX - 200)
    local fixedY = self.DislocationFixedBoneY or (self.CenterY + 120)
    local fixedW = self.DislocationFixedBoneWidth or 230
    local fixedH = self.DislocationFixedBoneHeight or 90
    local moveX = self.DislocationMoveX or (self.CenterX + 160)
    local moveY = self.DislocationMoveY or (self.CenterY - 80)
    local moveW = self.DislocationMoveBoneWidth or 220
    local moveH = self.DislocationMoveBoneHeight or 84
    local moveAng = self.DislocationMoveAngle or -18
    local fixedSign = (self.DislocationSide or 1) >= 0 and 1 or -1
    local fixedEndOffset = (fixedW * 0.5) - (fixedH * 0.3)
    local fixedEndX = fixedX + fixedEndOffset * fixedSign
    local fixedEndY = fixedY
    local moveEndOffset = (moveW * 0.5) - (moveH * 0.3)
    local moveContactSign = -fixedSign
    local moveRad = math.rad(moveAng)
    local moveCos, moveSin = math.cos(moveRad), math.sin(moveRad)
    local moveEndX = moveX + (moveEndOffset * moveContactSign) * moveCos
    local moveEndY = moveY + (moveEndOffset * moveContactSign) * moveSin
    local forceFill = math.Clamp(math.abs(self.DislocationAppliedForce or 0), 0, 1)
    local diffX = moveEndX - fixedEndX
    local diffY = moveEndY - fixedEndY
    local aligned = math.sqrt((diffX * diffX) + (diffY * diffY)) <= (self.DislocationSnapWindow or 30)

    DrawOutlinedBone(fixedX, fixedY, fixedW, fixedH, 0, Color(255, 255, 255, 255), Color(0, 0, 0, 255))
    DrawOutlinedBone(moveX, moveY, moveW, moveH, moveAng, Color(255, 255, 255, 255), Color(0, 0, 0, 255))

    DrawFilledCircle(fixedEndX, fixedEndY, 12, aligned and Color(205, 255, 205, 190) or Color(255, 255, 255, 120), 22)
    DrawFilledCircle(moveEndX, moveEndY, 10, aligned and Color(205, 255, 205, 190) or Color(255, 255, 255, 60), 22)

    if self.DislocationAiming then
        local startX = self.DislocationAimStartX or self.CenterX
        local startY = self.DislocationAimStartY or self.CenterY
        local aimX = (self.DislocationAimX or startX) - startX
        local aimY = (self.DislocationAimY or startY) - startY
        local len = math.sqrt((aimX * aimX) + (aimY * aimY))
        if len > 0.001 then
            local maxLen = 260
            local clamped = math.min(len, maxLen)
            local dirX = aimX / len
            local dirY = aimY / len
            local ax2 = moveX + dirX * clamped
            local ay2 = moveY + dirY * clamped
            surface.SetDrawColor(255, 255, 255, 170)
            surface.DrawLine(moveX, moveY, ax2, ay2)
        end
    end

    local meterWidth = 240
    local meterX = self.CenterX - meterWidth * 0.5
    local meterY = self.CenterY + 155
    draw.RoundedBox(6, meterX, meterY, meterWidth, 18, Color(50, 50, 50, 220))
    draw.RoundedBox(6, meterX + 3, meterY + 3, math.max((meterWidth - 6) * forceFill, 0), 12, Color(200, 200, 200, 245))

    draw.SimpleText("Push the dislocated bone back into the other bone.", "Trebuchet24", self.CenterX, self.CenterY - 170, Color(245, 245, 245, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(self:GetDislocationLabel(), "DermaLarge", self.CenterX, self.CenterY - 128, Color(255, 230, 180, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("Hold the bone, pull the mouse, and release to shove it that way.", "Trebuchet18", self.CenterX, self.CenterY + 205, Color(220, 220, 220, 205), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    self:DrawCommonOverlays(self.Progress, false)
end

function PANEL:Paint(w, h)
    if self.GameType == "tourniquet" then
        self:PaintTourniquet(w, h)
        return
    end

    if self.GameType == "syringe" then
        self:PaintSyringe(w, h)
        return
    end

    if self.GameType == "amputation" then
        self:PaintAmputation(w, h)
        return
    end

    if self.GameType == "dislocation" then
        self:PaintDislocation(w, h)
        return
    end

    surface.SetDrawColor(0, 0, 0, 240)
    surface.DrawRect(0, 0, w, h)
    
    -- Central part of the limb
    surface.SetDrawColor(40, 30, 25, 255)
    draw.NoTexture()
    local segments = 64
    local limbRadius = 80
    local poly = {}
    for i = 0, segments do
        local a = math.rad((i / segments) * 360)
        table.insert(poly, { x = self.CenterX + math.cos(a) * limbRadius, y = self.CenterY + math.sin(a) * limbRadius })
    end
    surface.DrawPoly(poly)
    
    -- The bandage no longer stacks in layers and instead thickens outward from the circle
    local baseWrapThickness = 8
    local wrapThicknessStep = self.VisualWrapThicknessStep or 1.5
    local currentWrapProgress = math.Clamp(self.WrapAngle / (2 * math.pi), 0, 1)
    local completedBandThickness = baseWrapThickness + (self.CompletedWraps * wrapThicknessStep)
    local activeBandThickness = baseWrapThickness + ((self.CompletedWraps + currentWrapProgress) * wrapThicknessStep)

    local wrapCol = IsBruiceKitActive() and Color(120, 255, 120) or Color(255, 255, 255)
    if self.CompletedWraps > 0 then
        DrawBandageRing(self, limbRadius, 215, completedBandThickness, wrapCol)
    end

    DrawBandageTrail(self, self.TrailPoints, limbRadius, 255, activeBandThickness, wrapCol)

    -- Coordinates of the current delayed bandage position
    local drawAngleRad = math.rad(self.CurrentAngleObj.y)
    local bx = self.CenterX + math.cos(drawAngleRad) * self.Radius
    local by = self.CenterY + math.sin(drawAngleRad) * self.Radius
    
    -- Draw the white bandage circle under the hand
    local circleRadius = 55 -- Increased from 35
    surface.SetDrawColor(wrapCol.r, wrapCol.g, wrapCol.b, 255)
    draw.NoTexture()
    local circlePoly = {}
    for i = 0, 32 do
        local a = math.rad((i / 32) * 360)
        table.insert(circlePoly, { x = bx + math.cos(a) * circleRadius, y = by + math.sin(a) * circleRadius })
    end
    surface.DrawPoly(circlePoly)

    self:DrawCommonOverlays(self.Progress, true)
end

vgui.Register("hg_medical_minigame", PANEL, "DFrame")

hook.Add("HG_OnOtrub", "hg_medical_minigame_close_on_otrub", function(ply)
    if ply ~= LocalPlayer() then return end
    if not hg or not hg.MedicalMinigame then return end

    local panel = hg.MedicalMinigame.Panel
    if IsValid(panel) then
        panel:Remove()
    end
end)

hook.Add("Think", "hg_medical_minigame_clear_amputation_on_death", function()
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:Alive() then return end

    ClearAllAmputationVisualState()
end)

net.Receive("hg_medical_minigame_start", function()
    if IsValid(hg.MedicalMinigame.Panel) then return end
    if IsLocalPlayerUnconscious() then return end
    hg.MedicalMinigame.NextType = net.ReadString()
    hg.MedicalMinigame.NextTarget = nil
    hg.MedicalMinigame.NextLimb = nil
    hg.MedicalMinigame.NextDislocationSide = nil

    if hg.MedicalMinigame.NextType == "amputation" then
        hg.MedicalMinigame.NextTarget = net.ReadEntity()
        hg.MedicalMinigame.NextLimb = net.ReadString()
        hg.MedicalMinigame.NextProgress = net.ReadFloat()
    elseif hg.MedicalMinigame.NextType == "dislocation" then
        hg.MedicalMinigame.NextTarget = net.ReadEntity()
        hg.MedicalMinigame.NextLimb = net.ReadString()
        hg.MedicalMinigame.NextProgress = net.ReadFloat()
        hg.MedicalMinigame.NextDislocationSide = net.ReadInt(3)
    end

    hg.MedicalMinigame.Panel = vgui.Create("hg_medical_minigame")
end)

local function ClampStat(v)
    v = tonumber(v) or 0
    return math.Clamp(math.floor(v + 0.5), 0, 100)
end

local function ClampMood(v)
    v = tonumber(v) or 0
    return math.Clamp(math.floor(v + 0.5), -100, 100)
end

local function GetMental(ent)
    if not IsValid(ent) then return 0, 0 end
    return ClampMood(ent:GetNWInt("zcity_delta_mood", 0)), ClampStat(ent:GetNWInt("zcity_delta_stress", 10))
end

local cvMentalHudShow = nil
local cvMentalHudMigrated = nil
local cvMoodlesShow = nil
local cvAddonMusicEnabled = nil
if CreateClientConVar then
    cvMentalHudShow = CreateClientConVar("zcity_delta_mental_hud_show", "0", true, false)
    cvMentalHudMigrated = CreateClientConVar("zcity_delta_mental_hud_migrated", "0", true, true)
    cvMoodlesShow = CreateClientConVar("zcity_delta_moodles_show", "1", true, false)
    cvAddonMusicEnabled = CreateClientConVar("zcity_delta_music_enabled", "0", true, false) -- Z-SCAV: своя музыка
end

local function IsAddonMusicEnabled()
    return not cvAddonMusicEnabled or not cvAddonMusicEnabled.GetBool or cvAddonMusicEnabled:GetBool()
end

timer.Simple(0, function()
    if not cvMentalHudShow or not cvMentalHudShow.GetBool then return end
    if not cvMentalHudMigrated or not cvMentalHudMigrated.GetBool then return end
    if cvMentalHudMigrated:GetBool() then return end
    RunConsoleCommand("zcity_delta_mental_hud_show", "0")
    RunConsoleCommand("zcity_delta_mental_hud_migrated", "1")
end)

if concommand and concommand.Add then
    concommand.Add("zcity_delta_mental_hud", function(_, _, args)
        if not cvMentalHudShow or not cvMentalHudShow.GetBool then return end
        local a = tostring(args and args[1] or "")
        if a == "" then
            RunConsoleCommand("zcity_delta_mental_hud_show", cvMentalHudShow:GetBool() and "0" or "1")
            return
        end
        if a == "0" or a == "1" then
            RunConsoleCommand("zcity_delta_mental_hud_show", a)
        end
    end)

    concommand.Add("zcity_delta_moodles", function(_, _, args)
        if not cvMoodlesShow or not cvMoodlesShow.GetBool then return end
        local a = tostring(args and args[1] or "")
        if a == "" then
            RunConsoleCommand("zcity_delta_moodles_show", cvMoodlesShow:GetBool() and "0" or "1")
            return
        end
        if a == "0" or a == "1" then
            RunConsoleCommand("zcity_delta_moodles_show", a)
        end
    end)

    concommand.Add("zcity_delta_music", function(_, _, args)
        if not cvAddonMusicEnabled or not cvAddonMusicEnabled.GetBool then return end
        local a = tostring(args and args[1] or "")
        if a == "" then
            RunConsoleCommand("zcity_delta_music_enabled", cvAddonMusicEnabled:GetBool() and "0" or "1")
            return
        end
        if a == "0" or a == "1" then
            RunConsoleCommand("zcity_delta_music_enabled", a)
        end
    end)
end

hook.Add("Think", "zcity_delta_music_master_stop", function()
    if IsAddonMusicEnabled() then return end

    local chan = hg and hg.MedicalMinigame and hg.MedicalMinigame.SoundChannel or nil
    if chan and chan.Stop then
        chan:Stop()
    end
    if hg and hg.MedicalMinigame then
        hg.MedicalMinigame.SoundChannel = nil
    end
end)

local zcityDeltaTraitDefs = {
    { id = "trained", side = "pos", cost = 5, name = "Trained", desc = "Calmer under pressure and more dangerous up close.", icon = "Trained.png" },
    { id = "brawler", side = "pos", cost = 4, name = "Brawler", desc = "Violence comes naturally to you.", icon = "brawler.png" },
    { id = "grunt", side = "pos", cost = 2, name = "Grunt", desc = "Harder to shake with grim sights around you.", icon = "grunt.png" },
    { id = "in_shape", side = "pos", cost = 5, name = "In Shape", desc = "Better endurance and recovery.", icon = "in shape.png" },
    { id = "lucky", side = "pos", cost = 3, name = "Lucky", desc = "Things tend to go your way when it matters.", icon = "lucky.png" },
    { id = "medic", side = "pos", cost = 5, name = "Medic", desc = "Your treatment tends to work better than most.", icon = "medic.png" },
    { id = "optimist", side = "pos", cost = 3, name = "Optimist", desc = "You hold onto the bright side a little longer.", icon = "optimist.png" },
    { id = "maniac", side = "pos", cost = 4, name = "Maniac", desc = "Disturbing scenes affect you in unusual ways.", icon = "maniac.png" },

    { id = "ptsd", side = "neg", cost = -4, name = "PTSD", desc = "Loud violence leaves a deeper mark on you.", icon = "PTSD.png" },
    { id = "depressed", side = "neg", cost = -5, name = "Depressed", desc = "It is harder to stay motivated and steady.", icon = "depressed.png" },
    { id = "schizophrenia", side = "neg", cost = -2, name = "Schizophrenia", desc = "Something keeps talking to you from the edge of your vision.", icon = "schizophrenia.png" },
    { id = "gemophobia", side = "neg", cost = -3, name = "Hemophobia", desc = "Open wounds and injury are especially unsettling to you.", icon = "gemophobia.png" },
    { id = "unlucky", side = "neg", cost = -2, name = "Unlucky", desc = "Fortune rarely picks your side.", icon = "unlucky.png" },
}

local function TraitsFromArray(arr)
    local out = {}
    if istable(arr) then
        for i = 1, #arr do
            local id = tostring(arr[i] or "")
            if id ~= "" then out[id] = true end
        end
    end
    return out
end

hg = hg or {}
hg.__zcity_delta_traits = hg.__zcity_delta_traits or {}

if net and net.Receive then
    net.Receive("zcity_delta_traits_sync", function()
        local raw = net.ReadString() or "[]"
        local data = util.JSONToTable(raw)
        hg.__zcity_delta_traits = TraitsFromArray(data)
    end)
end

local function OpenTraitsMenu()
    if not vgui or not vgui.Create then return end
    if IsValid(hg.__zcity_delta_traits_frame) then
        hg.__zcity_delta_traits_frame:Remove()
    end

    local selected = {}
    for id, v in pairs(hg.__zcity_delta_traits or {}) do
        if v then selected[id] = true end
    end

    local function CalcTotalCost()
        local total = 0
        for i = 1, #zcityDeltaTraitDefs do
            local t = zcityDeltaTraitDefs[i]
            if selected[t.id] then
                total = total + (tonumber(t.cost) or 0)
            end
        end
        return total
    end

    local function ApplyMutualExclusives()
        if selected.lucky and selected.unlucky then
            selected.unlucky = nil
        end
        if selected.ptsd and selected.depressed then
            selected.depressed = nil
        end
    end

    local fr = vgui.Create("DFrame")
    fr:SetTitle("Traits")
    fr:SetSize(860, 520)
    fr:Center()
    fr:MakePopup()
    hg.__zcity_delta_traits_frame = fr

    local top = vgui.Create("DPanel", fr)
    top:Dock(TOP)
    top:SetTall(42)

    local pointsLbl = vgui.Create("DLabel", top)
    pointsLbl:Dock(LEFT)
    pointsLbl:DockMargin(12, 8, 0, 8)
    pointsLbl:SetText("")
    pointsLbl:SetFont("DermaDefaultBold")
    pointsLbl:SizeToContents()

    local applyBtn = vgui.Create("DButton", top)
    applyBtn:Dock(RIGHT)
    applyBtn:DockMargin(0, 8, 12, 8)
    applyBtn:SetWide(160)
    applyBtn:SetText("Применить")

    local resetBtn = vgui.Create("DButton", top)
    resetBtn:Dock(RIGHT)
    resetBtn:DockMargin(0, 8, 8, 8)
    resetBtn:SetWide(160)
    resetBtn:SetText("Сбросить")

    local body = vgui.Create("DPanel", fr)
    body:Dock(FILL)
    body:DockMargin(12, 10, 12, 12)

    local left = vgui.Create("DPanel", body)
    left:Dock(LEFT)
    left:SetWide(410)
    left:DockMargin(0, 0, 10, 0)

    local right = vgui.Create("DPanel", body)
    right:Dock(FILL)

    local leftTitle = vgui.Create("DLabel", left)
    leftTitle:Dock(TOP)
    leftTitle:DockMargin(8, 8, 8, 4)
    leftTitle:SetFont("DermaDefaultBold")
    leftTitle:SetText("Положительные")
    leftTitle:SizeToContents()

    local rightTitle = vgui.Create("DLabel", right)
    rightTitle:Dock(TOP)
    rightTitle:DockMargin(8, 8, 8, 4)
    rightTitle:SetFont("DermaDefaultBold")
    rightTitle:SetText("Негативные")
    rightTitle:SizeToContents()

    local leftScroll = vgui.Create("DScrollPanel", left)
    leftScroll:Dock(FILL)
    leftScroll:DockMargin(6, 0, 6, 6)

    local rightScroll = vgui.Create("DScrollPanel", right)
    rightScroll:Dock(FILL)
    rightScroll:DockMargin(6, 0, 6, 6)

    local function AddTraitRow(parent, t)
        local row = vgui.Create("DPanel", parent)
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, 6)
        row:SetTall(54)

        local cb = vgui.Create("DCheckBoxLabel", row)
        cb:SetText("")
        cb:SetValue(selected[t.id] and 1 or 0)
        cb:Dock(LEFT)
        cb:DockMargin(8, 18, 0, 0)
        cb:SetWide(18)

        local icon = vgui.Create("DImage", row)
        icon:Dock(LEFT)
        icon:DockMargin(6, 10, 8, 10)
        icon:SetWide(34)
        local iconPath = tostring(t.icon or "")
        if iconPath ~= "" then
            icon:SetImage("traits/" .. iconPath)
        end

        local nameLbl = vgui.Create("DLabel", row)
        nameLbl:Dock(TOP)
        nameLbl:DockMargin(0, 6, 10, 0)
        nameLbl:SetFont("DermaDefaultBold")
        nameLbl:SetText(string.format("%s (%d)", t.name, tonumber(t.cost) or 0))
        nameLbl:SetWrap(false)
        nameLbl:SetAutoStretchVertical(false)

        local descLbl = vgui.Create("DLabel", row)
        descLbl:Dock(FILL)
        descLbl:DockMargin(0, 0, 10, 6)
        descLbl:SetFont("DermaDefault")
        descLbl:SetText(t.desc or "")
        descLbl:SetWrap(true)
        descLbl:SetAutoStretchVertical(true)

        local function Toggle()
            selected[t.id] = not selected[t.id]
            ApplyMutualExclusives()
            cb:SetValue(selected[t.id] and 1 or 0)
            if fr and fr.UpdateUI then fr:UpdateUI() end
        end

        cb.OnChange = function(_, val)
            selected[t.id] = val and true or false
            ApplyMutualExclusives()
            if fr and fr.UpdateUI then fr:UpdateUI() end
        end
        row.OnMousePressed = function()
            Toggle()
        end
    end

    for i = 1, #zcityDeltaTraitDefs do
        local t = zcityDeltaTraitDefs[i]
        if t.side == "pos" then
            AddTraitRow(leftScroll, t)
        else
            AddTraitRow(rightScroll, t)
        end
    end

    function fr:UpdateUI()
        local total = CalcTotalCost()
        local points = -total
        pointsLbl:SetText(string.format("Очки: %d", points))
        pointsLbl:SizeToContents()
        applyBtn:SetEnabled(total <= 0)
    end

    resetBtn.DoClick = function()
        selected = {}
        fr:Remove()
        timer.Simple(0, OpenTraitsMenu)
    end

    applyBtn.DoClick = function()
        local arr = {}
        for id, v in pairs(selected) do
            if v then arr[#arr + 1] = id end
        end
        table.sort(arr)
        if net and net.Start then
            net.Start("zcity_delta_traits_set")
            net.WriteString(util.TableToJSON(arr) or "[]")
            net.SendToServer()
        end
        fr:Remove()
    end

    fr:UpdateUI()
end

if concommand and concommand.Add then
    concommand.Add("zcity_delta_traits", function()
        local cv = GetConVar and GetConVar("zcity_delta_traits_enabled") or nil
        if cv and not cv:GetBool() then return end
        OpenTraitsMenu()
    end)
end

local function DrawMentalBars(x, y, w, h, mood, stress)
    draw.RoundedBox(6, x, y, w, h, Color(15, 15, 15, 200))

    local pad = 6
    local lineH = math.floor((h - pad * 2) / 2)
    local barW = w - pad * 2 - 62
    local barX = x + pad + 62
    local labelX = x + pad

    local function Row(i, label, val, col)
        local ry = y + pad + (i - 1) * lineH
        draw.SimpleText(label, "DermaDefault", labelX, ry + 2, Color(230, 230, 230, 255), TEXT_ALIGN_LEFT)
        draw.RoundedBox(4, barX, ry + 4, barW, lineH - 8, Color(45, 45, 50, 220))
        draw.RoundedBox(4, barX, ry + 4, math.floor(barW * (val / 100)), lineH - 8, col)
        draw.SimpleText(tostring(val), "DermaDefault", x + w - pad, ry + 2, Color(230, 230, 230, 255), TEXT_ALIGN_RIGHT)
    end

    local function MoodRow(i, label, val)
        local ry = y + pad + (i - 1) * lineH
        draw.SimpleText(label, "DermaDefault", labelX, ry + 2, Color(230, 230, 230, 255), TEXT_ALIGN_LEFT)
        draw.RoundedBox(4, barX, ry + 4, barW, lineH - 8, Color(45, 45, 50, 220))

        local mid = barX + math.floor(barW * 0.5)
        surface.SetDrawColor(220, 220, 220, 45)
        surface.DrawRect(mid, ry + 4, 1, lineH - 8)

        local t = math.Clamp(math.abs(val) / 100, 0, 1)
        local fill = math.floor((barW * 0.5) * t)
        if val >= 0 then
            draw.RoundedBox(4, mid, ry + 4, fill, lineH - 8, Color(90, 170, 220, 220))
        else
            draw.RoundedBox(4, mid - fill, ry + 4, fill, lineH - 8, Color(210, 90, 90, 220))
        end

        draw.SimpleText(tostring(val), "DermaDefault", x + w - pad, ry + 2, Color(230, 230, 230, 255), TEXT_ALIGN_RIGHT)
    end

    MoodRow(1, "Mood", mood)
    Row(2, "Stress", stress, Color(220, 170, 90, 220))
end

hook.Add("HUDPaint", "zcity_delta_mental_hud", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local cv = GetConVar("zcity_delta_mental_enabled")
    if cv and not cv:GetBool() then return end
    if cvMentalHudShow and cvMentalHudShow.GetBool and not cvMentalHudShow:GetBool() then return end

    local mood, stress = GetMental(lp)
    local sw, sh = ScrW(), ScrH()
    DrawMentalBars(20, sh - 130, 240, 75, mood, stress)

    local wep = lp:GetActiveWeapon()
    local isMedicTool = IsValid(wep) and wep:GetClass() == "weapon_bruicekit"
    if not isMedicTool then return end

    local tr = (hg and hg.eyeTrace and hg.eyeTrace(lp)) or lp:GetEyeTrace()
    local ent = tr and tr.Entity or nil
    if IsValid(ent) and ent:IsRagdoll() and hg and hg.RagdollOwner then
        ent = hg.RagdollOwner(ent) or ent
    end
    if not IsValid(ent) or not ent:IsPlayer() then return end
    if lp:GetPos():DistToSqr(ent:GetPos()) > 10000 then return end

    local tm, ts = GetMental(ent)
    DrawMentalBars(sw * 0.5 - 120, sh * 0.5 + 80, 240, 75, tm, ts)
end)

local miserable = {
    chan = nil,
    pending = false,
    nextTryAt = 0,
    targetVol = 0.12,
    curVol = 0,
}

local function StopMiserable()
    if miserable.chan and miserable.chan.IsValid and miserable.chan:IsValid() then
        miserable.chan:Stop()
    end
    miserable.chan = nil
    miserable.pending = false
    miserable.curVol = 0
end

hook.Add("Think", "zcity_delta_miserable_music", function()
    if not IsAddonMusicEnabled() then
        StopMiserable()
        return
    end

    local cv = GetConVar("zcity_delta_mental_enabled")
    if cv and not cv:GetBool() then
        StopMiserable()
        return
    end

    local lp = LocalPlayer()
    if not IsValid(lp) then
        StopMiserable()
        return
    end

    local mood = ClampMood(lp:GetNWInt("zcity_delta_mood", 0))
    if mood > -100 then
        StopMiserable()
        return
    end

    if miserable.chan and miserable.chan.IsValid and miserable.chan:IsValid() then
        if miserable.chan.SetVolume then
            local rate = 0.35
            miserable.curVol = math.min(miserable.targetVol, miserable.curVol + FrameTime() * rate)
            miserable.chan:SetVolume(miserable.curVol)
        end
        return
    end

    if miserable.pending then return end
    if CurTime() < (miserable.nextTryAt or 0) then return end
    miserable.nextTryAt = CurTime() + 3
    miserable.pending = true

    sound.PlayFile("sound/zcity_delta/miserable.mp3", "noplay", function(chan)
        miserable.pending = false
        local lp2 = LocalPlayer()
        local mood2 = IsValid(lp2) and ClampMood(lp2:GetNWInt("zcity_delta_mood", 0)) or 0
        if mood2 > -100 then
            if chan and chan.IsValid and chan:IsValid() then chan:Stop() end
            return
        end
        if not chan or not chan.IsValid or not chan:IsValid() then return end

        miserable.chan = chan
        if chan.EnableLooping then
            chan:EnableLooping(true)
        end
        if chan.SetVolume then
            miserable.curVol = 0
            chan:SetVolume(0)
        end
        chan:Play()
    end)
end)

hook.Add("RenderScreenspaceEffects", "zcity_delta_depression_greyscale", function()
    local cv = GetConVar("zcity_delta_mental_enabled")
    if cv and not cv:GetBool() then return end

    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    local mood = ClampMood(lp:GetNWInt("zcity_delta_mood", 0))
    if mood >= 0 then return end

    local t = math.Clamp((-mood) / 100, 0, 1)
    if t <= 0 then return end

    local contrast = 1 - 0.12 * t
    local colour = 1 - 0.9 * t
    local brightness = -0.02 * t

    DrawColorModify({
        ["$pp_colour_addr"] = 0,
        ["$pp_colour_addg"] = 0,
        ["$pp_colour_addb"] = 0,
        ["$pp_colour_brightness"] = brightness,
        ["$pp_colour_contrast"] = contrast,
        ["$pp_colour_colour"] = colour,
        ["$pp_colour_mulr"] = 0,
        ["$pp_colour_mulg"] = 0,
        ["$pp_colour_mulb"] = 0,
    })
end)

local mentalAim = {
    last = Angle(0, 0, 0),
    recoil = Angle(0, 0, 0),
    lastWep = nil,
    lastNextPrimary = 0,
}

local function ResetAimMod(cmd)
    if not cmd then return end
    if mentalAim.last.p ~= 0 or mentalAim.last.y ~= 0 or mentalAim.last.r ~= 0 then
        local ang = cmd:GetViewAngles()
        ang.p = ang.p - mentalAim.last.p
        ang.y = ang.y - mentalAim.last.y
        ang.r = ang.r - mentalAim.last.r
        cmd:SetViewAngles(ang)
    end
    mentalAim.last = Angle(0, 0, 0)
    mentalAim.recoil = Angle(0, 0, 0)
    mentalAim.lastWep = nil
    mentalAim.lastNextPrimary = 0
end

hook.Add("CreateMove", "zcity_delta_aim_effects", function(cmd)
    local cv = GetConVar("zcity_delta_mental_enabled")
    if cv and not cv:GetBool() then
        ResetAimMod(cmd)
        return
    end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        ResetAimMod(cmd)
        return
    end
    if ply:InVehicle() then return end
    if ply:GetMoveType() == MOVETYPE_NOCLIP then return end
    if ply.organism and ply.organism.otrub then return end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then
        ResetAimMod(cmd)
        return
    end
    local class = wep:GetClass()
    if class == "weapon_hands_sh" or class == "weapon_bruicekit" then
        ResetAimMod(cmd)
        return
    end

    local ang = cmd:GetViewAngles()
    ang.p = ang.p - mentalAim.last.p
    ang.y = ang.y - mentalAim.last.y
    ang.r = ang.r - mentalAim.last.r

    local stress = ClampStat(ply:GetNWInt("zcity_delta_stress", 0))
    local stressScale = math.Clamp(stress / 100, 0, 1)

    local mood = ClampMood(ply:GetNWInt("zcity_delta_mood", 0))
    local depScale = math.Clamp((-math.min(mood, 0)) / 100, 0, 1)

    if mentalAim.lastWep ~= wep then
        mentalAim.lastWep = wep
        mentalAim.lastNextPrimary = wep.GetNextPrimaryFire and (wep:GetNextPrimaryFire() or 0) or 0
        mentalAim.recoil = Angle(0, 0, 0)
    end

    if mentalAim.recoil.p ~= 0 or mentalAim.recoil.y ~= 0 or mentalAim.recoil.r ~= 0 then
        local decay = math.Clamp(FrameTime() * 10, 0, 1)
        mentalAim.recoil.p = mentalAim.recoil.p * (1 - decay)
        mentalAim.recoil.y = mentalAim.recoil.y * (1 - decay)
        mentalAim.recoil.r = mentalAim.recoil.r * (1 - decay)
        if math.abs(mentalAim.recoil.p) < 0.0003 then mentalAim.recoil.p = 0 end
        if math.abs(mentalAim.recoil.y) < 0.0003 then mentalAim.recoil.y = 0 end
        if math.abs(mentalAim.recoil.r) < 0.0003 then mentalAim.recoil.r = 0 end
    end

    if depScale > 0 and wep.GetNextPrimaryFire then
        local npf = wep:GetNextPrimaryFire() or 0
        if npf ~= mentalAim.lastNextPrimary then
            mentalAim.lastNextPrimary = npf
            if cmd:KeyDown(IN_ATTACK) and npf > CurTime() then
                local pow = depScale ^ 1.35
                local kick = 0.12 + 1.45 * pow
                if ply:KeyDown(IN_ATTACK2) then
                    kick = kick * 1.1
                end
                mentalAim.recoil.p = mentalAim.recoil.p - kick
                mentalAim.recoil.y = mentalAim.recoil.y + math.Rand(-kick * 0.35, kick * 0.35)
                mentalAim.recoil.r = mentalAim.recoil.r + math.Rand(-kick * 0.1, kick * 0.1)
            end
        end
    end

    local shakeOff = Angle(0, 0, 0)
    if stressScale >= 0.08 then
        local t = CurTime()
        local seed = ply:EntIndex() * 0.173
        local pow = stressScale ^ 1.35
        local base = 0.05 + 1.25 * pow
        if ply:KeyDown(IN_ATTACK2) then
            base = base * 1.15
        end

        local p = math.sin((t + seed) * 6.2) + 0.55 * math.sin((t + seed) * 12.9) + 0.25 * math.sin((t + seed) * 21.7)
        local y = math.cos((t + seed) * 5.8) + 0.55 * math.cos((t + seed) * 11.6) + 0.25 * math.cos((t + seed) * 19.8)
        local r = 0.35 * math.sin((t + seed) * 9.4) + 0.15 * math.sin((t + seed) * 17.3)

        shakeOff = Angle(p * base * 0.55, y * base * 0.55, r * base * 0.35)
    end

    local newOff = Angle(
        shakeOff.p + mentalAim.recoil.p,
        shakeOff.y + mentalAim.recoil.y,
        shakeOff.r + mentalAim.recoil.r
    )

    ang.p = ang.p + newOff.p
    ang.y = ang.y + newOff.y
    ang.r = ang.r + newOff.r

    cmd:SetViewAngles(ang)
    mentalAim.last = newOff
end)

local function UrlEncodePath(s)
    s = tostring(s or "")
    return (s:gsub("([^%w%-%_%.%/:%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function HtmlEscape(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub("\"", "&quot;")
    s = s:gsub("\n", "&#10;")
    return s
end

local function TooltipHtmlFromTitle(title)
    title = tostring(title or "")
    local first, rest = title:match("^(.-)&#10;(.*)$")
    if not first then
        first = title
        rest = ""
    end
    rest = tostring(rest or ""):gsub("&#10;", "<br>")
    return string.format('<div class="tt">%s</div><div class="td">%s</div>', first, rest)
end

local function TooltipPlainFromTitle(title)
    title = tostring(title or "")
    title = title:gsub("&#10;", "\n")
    title = title:gsub("&amp;", "&")
    title = title:gsub("&lt;", "<")
    title = title:gsub("&gt;", ">")
    title = title:gsub("&quot;", "\"")
    return title
end

local function TryExtractFileNameFromUrl(url)
    url = tostring(url or "")
    local name = url:match("/([^/%?]+)$")
    if not name then return nil end
    name = name:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16) or 32)
    end)
    return name
end

local moodlesLocalBase = "asset://garrysmod/materials/zcity_delta_moodles/"
local function ResolveMoodleFileName(name)
    name = tostring(name or "")
    if name == "" then return "" end

    local baseName = name:gsub("%.[^%.]+$", "")
    local ext = string.match(name, "%.([^%.]+)$")
    local preferred = {}
    local seen = {}

    local function push(candidate)
        candidate = tostring(candidate or "")
        if candidate == "" or seen[candidate] then return end
        seen[candidate] = true
        preferred[#preferred + 1] = candidate
    end

    push(name)
    if ext then
        ext = string.lower(ext)
        if ext ~= "png" then
            push(baseName .. ".png")
        end
        if ext ~= "jpg" then
            push(baseName .. ".jpg")
        end
        if ext ~= "jpeg" then
            push(baseName .. ".jpeg")
        end
        if ext ~= "gif" then
            push(baseName .. ".gif")
        end
        if ext ~= "webp" then
            push(baseName .. ".webp")
        end
    else
        push(baseName .. ".png")
        push(baseName .. ".jpg")
        push(baseName .. ".jpeg")
        push(baseName .. ".gif")
        push(baseName .. ".webp")
    end

    if file and file.Exists then
        for i = 1, #preferred do
            local candidate = preferred[i]
            if file.Exists("materials/zcity_delta_moodles/" .. candidate, "GAME") then
                return candidate
            end
        end
    end

    return preferred[1] or name
end

local function LocalMoodleFile(name)
    local resolved = ResolveMoodleFileName(name)
    if resolved == "" then return "" end
    return UrlEncodePath(moodlesLocalBase .. resolved)
end

local moodlesPnl = nil
local moodlesState = nil
local moodlesNextUpdate = 0
local moodlesCleanupNext = 0
local moodlesW = 260
local moodlesH = 72
local moodlesShown = nil
local moodlesLastMentalEnabled = nil
local moodlesPopStart = 0
local moodlesPopDur = 0.28
local moodlesPopOffset = 18
local moodlesPrevActiveBySrc = {}
local GetMoodleMatFromFileName

local function EaseOutBack(t)
    t = math.Clamp(tonumber(t) or 0, 0, 1)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

local moodlesExtra = {
    satiety = 0,
    internalBleed = 0,
    hungry = 0,
}

local function KillStrayMoodlesPanels(keepPanel)
    if vgui and vgui.GetWorldPanel then
        local wp = vgui.GetWorldPanel()
        if IsValid(wp) then
            local children = wp:GetChildren()
            for i = 1, #children do
                local ch = children[i]
                if IsValid(ch) then
                    local name = (ch.GetName and ch:GetName()) or ""
                    if name == "zcity_delta_moodles_pnl" then
                        if ch ~= keepPanel then
                            ch:Remove()
                        end
                    else
                        local isDhtml = (ch.GetClassName and ch:GetClassName() == "DHTML") or (ch.ClassName == "DHTML")
                        if isDhtml and ch.IsMouseInputEnabled and ch.IsKeyboardInputEnabled then
                            if not ch:IsMouseInputEnabled() and not ch:IsKeyboardInputEnabled() then
                                local x, y = ch:GetPos()
                                local w, h = ch:GetSize()
                                if x <= 40 and y >= (ScrH() - 420) and w <= 900 and h <= 200 then
                                    if ch ~= keepPanel then
                                        ch:Remove()
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    hg = hg or {}
    if IsValid(hg.__zcity_delta_moodles_pnl) then
        if hg.__zcity_delta_moodles_pnl ~= keepPanel then
            hg.__zcity_delta_moodles_pnl:Remove()
        end
    end
    if hg.__zcity_delta_moodles_pnl ~= keepPanel then
        hg.__zcity_delta_moodles_pnl = nil
    end
end

local function ResetMoodlesClientCache()
    moodlesExtra.satiety = 0
    moodlesExtra.internalBleed = 0
    moodlesExtra.hungry = 0

    hg = hg or {}
    hg.__zcity_delta_virus_stage = 0
    hg.__zcity_delta_laststand_until = 0
end

KillStrayMoodlesPanels()

local function PatchAphobasolName()
    if not weapons or not weapons.GetStored then return end
    local swep = weapons.GetStored("weapon_betablock")
    if not swep or swep.__zcity_delta_aphobasol_named then return end
    swep.__zcity_delta_aphobasol_named = true
    swep.PrintName = "Aphobasol"
    if istable(swep.modeNames) then
        swep.modeNames[1] = "aphobasol"
    end
end

timer.Simple(0, PatchAphobasolName)
timer.Create("zcity_delta_patch_aphobasol_name", 5, 0, PatchAphobasolName)

if net and net.Receive then
    net.Receive("zcity_delta_moodles_extra", function()
        moodlesExtra.satiety = net.ReadFloat() or 0
        moodlesExtra.internalBleed = net.ReadFloat() or 0
        moodlesExtra.hungry = net.ReadFloat() or 0
    end)

    net.Receive("VirusStageUpdate", function()
        hg = hg or {}
        hg.__zcity_delta_virus_stage = net.ReadInt(8) or 0
    end)
end

local function GetMoodlesPos()
    local x = 20
    local h = moodlesH
    if moodlesPnl and IsValid(moodlesPnl) then
        h = moodlesPnl:GetTall()
    end
    local y = ScrH() - h - 20
    if y < 10 then y = 10 end
    return x, y
end

local function StopMoodles()
    if moodlesPnl and IsValid(moodlesPnl) then
        moodlesPnl:Remove()
    end
    moodlesPnl = nil
    moodlesState = nil
    ResetMoodlesClientCache()
    KillStrayMoodlesPanels()
end

local function EnsureMoodlesPanel()
    if moodlesPnl and IsValid(moodlesPnl) then return moodlesPnl end
    if not vgui or not vgui.Create then return nil end

    hg = hg or {}
    if IsValid(hg.__zcity_delta_moodles_pnl) then
        moodlesPnl = hg.__zcity_delta_moodles_pnl
        return moodlesPnl
    end

    KillStrayMoodlesPanels()

    local pnl = vgui.Create("DPanel")
    pnl:SetName("zcity_delta_moodles_pnl")
    pnl:SetSize(moodlesW, moodlesH)
    local x, y = GetMoodlesPos()
    pnl:SetPos(x, y)
    pnl.Paint = function(self, w, h)
        local items = self.__zcity_delta_items
        if not istable(items) or #items <= 0 then return end

        local iconOuter = 52
        local pad = 1
        local baseImg = 44

        for i = 1, #items do
            local item = items[i]
            local x0 = pad + (i - 1) * (iconOuter + 2)
            local y0 = pad
            local alpha = math.Clamp(math.floor(255 * (tonumber(item.opacity) or 1)), 0, 255)

            surface.SetDrawColor(10, 10, 10, math.max(35, math.floor(alpha * 0.22)))
            surface.DrawRect(x0, y0, iconOuter, iconOuter)
            surface.SetDrawColor(255, 255, 255, math.max(20, math.floor(alpha * 0.12)))
            surface.DrawOutlinedRect(x0, y0, iconOuter, iconOuter, 1)

            local mat = GetMoodleMatFromFileName(item.fileName)
            if mat then
                local imgPx = tonumber(item.imgPx) or baseImg
                local drawX = x0 + (iconOuter - imgPx) * 0.5
                local drawY = y0 + (iconOuter - imgPx) * 0.5
                local shake = tonumber(item.shake) or 0
                if shake > 0 then
                    local mul = math.min(shake, 4) * 0.35
                    drawX = drawX + math.sin(RealTime() * (9 + shake * 2) + i * 1.7) * mul
                    drawY = drawY + math.cos(RealTime() * (8 + shake * 2) + i * 1.3) * mul
                end
                surface.SetDrawColor(255, 255, 255, alpha)
                surface.SetMaterial(mat)
                surface.DrawTexturedRect(drawX, drawY, imgPx, imgPx)
            end
        end
    end
    pnl:SetMouseInputEnabled(false)
    pnl:SetKeyboardInputEnabled(false)

    moodlesPnl = pnl
    hg.__zcity_delta_moodles_pnl = pnl
    return pnl
end

local moodleMatCache = {}
GetMoodleMatFromFileName = function(fileName)
    fileName = ResolveMoodleFileName(fileName)
    if fileName == "" then return nil end

    local cacheKey = fileName
    local cached = moodleMatCache[cacheKey]
    if cached ~= nil then return cached end

    local mat = Material("zcity_delta_moodles/" .. fileName, "smooth noclamp")
    if type(mat) == "IMaterial" and not mat:IsError() then
        moodleMatCache[cacheKey] = mat
        return mat
    end

    moodleMatCache[cacheKey] = false
    return nil
end

local moodlesTooltipFrameMat = nil
local function GetMoodlesTooltipFrameMat()
    if moodlesTooltipFrameMat ~= nil then return moodlesTooltipFrameMat end
    local mat = Material("zcity_delta/other/desc1.png", "smooth noclamp")
    if type(mat) == "IMaterial" and not mat:IsError() then
        moodlesTooltipFrameMat = mat
        return mat
    end
    moodlesTooltipFrameMat = false
    return nil
end

local moodlesTooltipIconFrameMat = nil
local function GetMoodlesTooltipIconFrameMat()
    if moodlesTooltipIconFrameMat ~= nil then return moodlesTooltipIconFrameMat end
    local mat = Material("zcity_delta/other/desc2.png", "smooth noclamp")
    if type(mat) == "IMaterial" and not mat:IsError() then
        moodlesTooltipIconFrameMat = mat
        return mat
    end
    moodlesTooltipIconFrameMat = false
    return nil
end

local moodlesTooltipFontsReady = false
local function EnsureMoodlesTooltipFonts()
    if moodlesTooltipFontsReady then return end
    moodlesTooltipFontsReady = true
    if not surface or not surface.CreateFont then return end
    surface.CreateFont("zcity_delta_moodles_tip_title", {
        font = "Pixel Operator",
        size = 16,
        weight = 800,
        antialias = false,
        additive = false,
    })
    surface.CreateFont("zcity_delta_moodles_tip_desc", {
        font = "Pixel Operator",
        size = 12,
        weight = 600,
        antialias = false,
        additive = false,
    })
end

local function HasDislocation(org)
    if not org then return false end
    return org.larmdislocation or org.rarmdislocation or org.llegdislocation or org.rlegdislocation
end

local function HasJawDislocation(org)
    if not org then return false end
    return org.jawdislocation == true
end

local function HasBrokenBone(org)
    if not org then return false end
    return org.larm == 1 or org.rarm == 1 or org.lleg == 1 or org.rleg == 1 or org.jaw == 1 or org.spine1 == 1 or org.spine2 == 1 or org.spine3 == 1
end

local function HasBleeding(org)
    if not org then return false end
    local bleed = tonumber(org.bleed) or 0
    local internalBleed = tonumber(org.internalBleed)
    if internalBleed == nil then internalBleed = tonumber(moodlesExtra.internalBleed) or 0 end
    return bleed > 0.01 or internalBleed > 0.05
end

local function GetBleedingStage(org)
    if not org then return 0 end
    local bleed = tonumber(org.bleed) or 0
    if bleed <= 0 then return 0 end
    if bleed > 0.45 then return 4 end
    if bleed > 0.225 then return 3 end
    if bleed > 0.09 then return 2 end
    return 1
end

local function GetInternalBleedingStage(org)
    if not org then return 0 end
    local v = tonumber(org.internalBleed)
    if v == nil then v = tonumber(moodlesExtra.internalBleed) or 0 end
    if v <= 0.04275 then return 0 end
    if v > 0.6498 then return 4 end
    if v > 0.43605 then return 3 end
    if v > 0.2223 then return 2 end
    return 1
end

local function GetAdrenalineStage(org)
    if not org then return 0 end
    local a = tonumber(org.adrenaline) or 0
    local pct = (a / 5) * 100
    if pct > 65 then return 2 end
    if pct > 20 then return 1 end
    return 0
end

local function GetPainStage(org)
    if not org then return 0 end
    local p = tonumber(org.pain) or 0
    if p <= 1 then p = p * 100 end
    if p > 55 then return 3 end
    if p > 30 then return 2 end
    if p > 10 then return 1 end
    return 0
end

local function HasAgony(org)
    if not org then return false end
    local p = tonumber(org.pain) or 0
    if p <= 1 then p = p * 100 end
    if p >= 80 then return true end
    if p >= 55 then
        local s = tonumber(org.shock) or 0
        if s <= 1 then s = s * 100 end
        if s > 30 then return true end
        local c = tonumber(org.consciousness)
        if c and c < 0.35 then return true end
    end
    return false
end

local function GetShockStage(org)
    if not org then return 0 end
    local s = tonumber(org.shock) or 0
    if s <= 1 then s = s * 100 end
    if s > 30 then return 1 end
    return 0
end

local function GetOxygenStage(org)
    if not org or not istable(org.o2) then return 0 end
    local cur = tonumber(org.o2[1])
    local maxV = tonumber(org.o2.range)
    if not cur or not maxV or maxV <= 0 then return 0 end
    local pct = math.Clamp((cur / maxV) * 100, 0, 100)
    if pct < 45 then return 4 end
    if pct < 60 then return 3 end
    if pct < 75 then return 2 end
    if pct < 90 then return 1 end
    return 0
end

local function GetTempColdStage(org)
    if not org then return 0 end
    local t = tonumber(org.temperature)
    if not t then return 0 end
    if t < 28 then return 4 end
    if t < 32.5 then return 3 end
    if t < 34 then return 2 end
    if t < 35.5 then return 1 end
    return 0
end

local function GetTempHeatStage(org)
    if not org then return 0 end
    local t = tonumber(org.temperature)
    if not t then return 0 end
    if t > 41.5 then return 4 end
    if t > 40.25 then return 3 end
    if t > 39 then return 2 end
    if t > 38 then return 1 end
    return 0
end

local function GetConsciousnessStage(org)
    if not org then return 0 end
    local c = tonumber(org.consciousness)
    if c == nil then return 0 end
    local pct = c <= 1 and (c * 100) or c
    if pct < 20 then return 5 end
    if pct < 30 then return 4 end
    if pct < 55 then return 3 end
    if pct < 72 then return 2 end
    if pct < 90 then return 1 end
    return 0
end

local function GetBrainDamageStage(org)
    if not org then return 0 end
    local d = tonumber(org.brain)
    if d == nil then return 0 end
    local healthPct = math.Clamp((1 - d) * 100, 0, 100)
    if healthPct < 30 then return 4 end
    if healthPct < 60 then return 3 end
    if healthPct < 80 then return 2 end
    if healthPct < 95 then return 1 end
    return 0
end

local function GetResolvedHeartRate(org)
    if not org then return 0, 0, 0 end
    local pulse = tonumber(org.pulse) or 0
    local heartbeat = tonumber(org.heartbeat) or 0
    local hr = math.max(pulse, heartbeat, 0)
    return hr, pulse, heartbeat
end

local function GetTachycardiaStage(org)
    if not org then return 0 end
    local hr = GetResolvedHeartRate(org)
    if hr > 200 then return 3 end
    if hr > 160 then return 2 end
    if hr > 110 then return 1 end
    return 0
end

local function GetBradycardiaStage(org)
    if not org then return 0 end
    local hr = GetResolvedHeartRate(org)
    if hr > 0 and hr < 40 then return 2 end
    if hr > 0 and hr < 60 then return 1 end
    return 0
end

local function IsCardiacArrest(org)
    if not org then return false end
    if org.alive == false then return true end
    local _, p, hb = GetResolvedHeartRate(org)
    return hb <= 0 and p <= 0
end

local function IsAmputated(org)
    if not org then return false end
    return org.llegamputated or org.rlegamputated or org.larmamputated or org.rarmamputated or org.headamputated
end

local function GetMoodStage(ply)
    if not IsValid(ply) then return 0 end
    local m = tonumber(ply:GetNWInt("zcity_delta_mood", 0)) or 0
    if m > 75 then return 7 end
    if m > 50 then return 6 end
    if m > 30 then return 5 end
    if m > 10 then return 4 end
    if m < -75 then return 3 end
    if m < -30 then return 2 end
    if m < -10 then return 1 end
    return 0
end

local function GetHungerStage(org)
    if not org then return 0 end
    local satiety = tonumber(org.satiety)
    if satiety == nil then satiety = tonumber(moodlesExtra.satiety) or 0 end
    if satiety <= 15 then return 4 end
    if satiety < 35 then return 3 end
    if satiety < 50 then return 2 end
    if satiety < 75 then return 1 end
    return 0
end

local function GetVirusStage()
    if not hg then return 0 end
    local v = tonumber(hg.__zcity_delta_virus_stage) or 0
    if v < 0 then v = 0 end
    return v
end

local function GetBloodPressureStage(org)
    if not org then return 0, 0 end
    local bp = tonumber(org.pulse)
    if bp == nil then return 0, 0 end

    local hypo = 0
    if bp > 0 and bp < 30 then
        hypo = 3
    elseif bp > 0 and bp < 45 then
        hypo = 2
    elseif bp > 0 and bp < 60 then
        hypo = 1
    end

    local hyper = 0
    if bp > 140 then
        hyper = 3
    elseif bp > 110 then
        hyper = 2
    elseif bp > 90 then
        hyper = 1
    end

    return hyper, hypo
end

local function GetOpiateStage(org)
    if not org then return 0 end
    local a = tonumber(org.analgesia)
    if a == nil or a <= 0.2 then return 0 end
    if a > 3.2 then return 4 end
    if a > 2.0 then return 3 end
    if a > 0.8 then return 2 end
    return 1
end

local function GetStaminaPercent(org)
    if not org or not istable(org.stamina) then return nil end
    local cur = tonumber(org.stamina[1])
    local maxV = tonumber(org.stamina.max)
    if not cur or not maxV or maxV <= 0 then return nil end
    return math.Clamp((cur / maxV) * 100, 0, 100)
end

local function GetExertionStage(org)
    local pct = GetStaminaPercent(org)
    if pct == nil then return 0 end
    if pct < 15 then return 4 end
    if pct < 35 then return 3 end
    if pct < 50 then return 2 end
    if pct < 70 then return 1 end
    return 0
end

local function IsLastStandActive()
    if not hg then return false end
    local untilTime = tonumber(hg.__zcity_delta_laststand_until or 0) or 0
    return untilTime > CurTime()
end

local function SetMoodlesHtml(pnl, st)
    local fallbackBleed = LocalMoodleFile("48px-Moodle_bleeding_1.webp")
    local fallbackBroken = UrlEncodePath("asset://garrysmod/materials/zcity_delta/unitmenu/status/fracture.png")
    local fallbackDisloc = UrlEncodePath("asset://garrysmod/materials/zcity_delta/unitmenu/status/dislocation.png")

    local activeAlpha = 1.0
    local inactiveAlpha = 0.22

    local bleedStage = tonumber(st.bleedingStage) or 0
    local internalBleedStage = tonumber(st.internalBleedingStage) or 0
    local adrenStage = tonumber(st.adrenalineStage) or 0
    local bleedImgPx = 44
    if bleedStage == 4 then
        bleedImgPx = 52
    elseif bleedStage == 3 then
        bleedImgPx = 52
    end

    local bleedLabel = "Minor bleeding"
    local bleedDesc = "Blood is oozing out of a relatively small wound. There is no immediate danger."
    local bleedSrc = LocalMoodleFile("48px-Moodle_smallbleeding_0.webp")
    if bleedStage == 2 then
        bleedLabel = "Bleeding"
        bleedDesc = "Blood is flowing out of a decently sized wound. Unlikely to be fatal if you're healthy. Treatment recommended."
        bleedSrc = LocalMoodleFile("48px-Moodle_bleeding_1.webp")
    elseif bleedStage == 3 then
        bleedLabel = "Heavy bleeding"
        bleedDesc = "A large volume of blood is haemorrhaging out of your body. Likely lethal if untreated. Treatment needed."
        bleedSrc = LocalMoodleFile("48px-Moodle_heavybleeding_2_critical.png")
    elseif bleedStage == 4 then
        bleedLabel = "Catastrophic bleeding"
        bleedDesc = "_As your life gushes out behind you, you remember that you are mortal._"
        bleedSrc = LocalMoodleFile("64px-Moodle_maxbleeding_3_critical.png")
    end

    local fracturedLabel = "Fractured bone"
    local fracturedDesc = "You broke something. Try not to use the affected limb, and rest as much as possible. Treatment highly recommended."
    local fracturedSrc = LocalMoodleFile("48px-Moodle_brokenbone_anim.webp")

    local dislocLabel = "Dislocated joint"
    local dislocDesc = "You dislocated something. Try not to use the affected limb, and find a way to fix it. Treatment recommended."
    local dislocSrc = LocalMoodleFile("48px-Moodle_dislocation_anim.webp")

    local jawDislocLabel = "Dislocated jaw"
    local jawDislocDesc = "Your jaw is dislocated, impairing your speech and making eating anything extremely painful."
    local jawDislocSrc = LocalMoodleFile("48px-Moodle_dislocatedjaw_anim.webp")

    local unconsciousLabel = "Unconscious"
    local unconsciousDesc = "Not responding to any external stimuli. Lights out."
    local unconsciousSrc = LocalMoodleFile("48px-Unconscious_Moodle.webp")

    local brainStage = tonumber(st.brainDamageStage) or 0
    local brainLabel = "Cognitive impairment"
    local brainDesc = "Mentally impaired from damage to the brain. You feel weirdly confused..."
    local brainSrc = LocalMoodleFile("48px-Braindamage_Moodle_1.webp")
    if brainStage == 2 then
        brainLabel = "Neurological damage"
        brainDesc = "Strong mental deficit. Ability to think intelligently and self-sustain is limited. Serious brain damage present."
        brainSrc = LocalMoodleFile("48px-Braindamage_Moodle_2.webp")
    elseif brainStage == 3 then
        brainLabel = "Severe neurophysiological deterioration"
        brainDesc = "reality .. stops making sense"
        brainSrc = LocalMoodleFile("48px-Braindamage_Moodle_3.webp")
    elseif brainStage == 4 then
        brainLabel = "Comatose"
        brainDesc = "..."
        brainSrc = LocalMoodleFile("48px-Braindamage_Moodle_4_Crit.png")
    end

    local oxyStage = tonumber(st.oxygenStage) or 0
    local oxyLabel = "Mild hypoxemia"
    local oxyDesc = "SpO2 below 90%. While not dangerous, it could be a sign of an underlying condition."
    local oxySrc = LocalMoodleFile("48px-Oxygen_Moodle_1.webp")
    if oxyStage == 2 then
        oxyLabel = "Hypoxemia"
        oxyDesc = "SpO2 below 75%, causing tachycardia and slowly depriving the brain of oxygen. While not lethal, it does point at an underlying condition."
        oxySrc = LocalMoodleFile("48px-Oxygen_Moodle_2.webp")
    elseif oxyStage == 3 then
        oxyLabel = "Severe hypoxemia"
        oxyDesc = "SpO2 below 60%, depriving tissues of oxygen and likely causing heart arrhythmia. Lethal if left to progress."
        oxySrc = LocalMoodleFile("48px-Oxygen_Moodle_3.webp")
    elseif oxyStage == 4 then
        oxyLabel = "Critical hypoxemia"
        oxyDesc = "SpO2 below 45%. Something in your body has gone horribly, horribly wrong. Lethal if left to progress."
        oxySrc = LocalMoodleFile("48px-Oxygen_Moodle_4.webp")
    end

    local painStage = tonumber(st.painStage) or 0
    local painLabel = "Discomfort"
    local painDesc = "Feeling mild pain."
    local painSrc = LocalMoodleFile("48px-Pain_1.webp")
    if painStage == 2 then
        painLabel = "Pain"
        painDesc = "Hurting a decent bit. Unhappiness rising slowly."
        painSrc = LocalMoodleFile("48px-Pain_2.webp")
    elseif painStage == 3 then
        painLabel = "Severe pain"
        painDesc = "Half-conscious, mind fogged by intense pain. Unhappiness rising."
        painSrc = LocalMoodleFile("48px-Moodle_pain_3_critical.png")
    end

    local agonyActive = st.agony == true
    local agonyLabel = "Agony"
    local agonyDesc = "Unbearable pain."
    local agonySrc = LocalMoodleFile("48px-Moodle_pain_3_critical.png")

    local shockActive = (tonumber(st.shockStage) or 0) > 0
    local shockLabel = "Shock"
    local shockDesc = "Going into shock from agony."
    local shockSrc = LocalMoodleFile("48px-Shock.webp")

    local coldStage = tonumber(st.coldStage) or 0
    local heatStage = tonumber(st.heatStage) or 0
    local tempLabel = "Chilly"
    local tempDesc = "A little cold for comfort."
    local tempSrc = LocalMoodleFile("48px-Cold_1.webp")
    local tempIsCold = coldStage > 0 and heatStage == 0
    if tempIsCold then
        if coldStage == 2 then
            tempLabel = "Cold"
            tempDesc = "Unpleasantly cold. Your body is slowing down."
            tempSrc = LocalMoodleFile("48px-Cold_2.webp")
        elseif coldStage == 3 then
            tempLabel = "Hypothermia"
            tempDesc = "Dangerously low temperature, body and mind taken by the cold. Your entire body is slowly shutting down."
            tempSrc = LocalMoodleFile("48px-Cold_3.webp")
        elseif coldStage == 4 then
            tempLabel = "Freezing to death"
            tempDesc = "You feel like you're burning up, but you're so tired and confused. You could go for a long nap..."
            tempSrc = LocalMoodleFile("48px-Cold_4.webp")
        end
    else
        if heatStage == 1 then
            tempLabel = "Warm"
            tempDesc = "A little warm for comfort."
            tempSrc = LocalMoodleFile("48px-Heat_1.webp")
        elseif heatStage == 2 then
            tempLabel = "Hot"
            tempDesc = "Unpleasantly hot. Thirst increased."
            tempSrc = LocalMoodleFile("48px-Heat_2.webp")
        elseif heatStage == 3 then
            tempLabel = "Hyperthermia"
            tempDesc = "Dangerously hot. You're struggling to go on in the heat... Thirst highly increased."
            tempSrc = LocalMoodleFile("48px-Heat_3.webp")
        elseif heatStage == 4 then
            tempLabel = "Heatstroke"
            tempDesc = "Cells are starting to die from the intense heat. Irreversible organ damage imminent."
            tempSrc = LocalMoodleFile("48px-Heat_4.png")
        end
    end

    local concStage = tonumber(st.consciousnessStage) or 0
    local concLabel = "Confused"
    local concDesc = "Feeling disoriented and slightly dizzy."
    local concSrc = LocalMoodleFile("48px-Faint_1.webp")
    if concStage == 2 then
        concLabel = "Very confused"
        concDesc = "Confused and dizzy, struggling to keep up with the world around you."
        concSrc = LocalMoodleFile("48px-Faint_2.webp")
    elseif concStage == 3 then
        concLabel = "Fainting"
        concDesc = "Barely conscious, feeling like you could collapse at any moment."
        concSrc = LocalMoodleFile("48px-Faint_3.webp")
    elseif concStage == 4 then
        concLabel = "Incapacitated"
        concDesc = "Can't stand or think. You barely feel anything."
        concSrc = LocalMoodleFile("48px-Faint_4.webp")
    elseif concStage == 5 then
        concLabel = "Unconscious"
        concDesc = "Not responding to any external stimuli. Lights out."
        concSrc = LocalMoodleFile("48px-Unconscious_Moodle.webp")
    end

    local tachyStage = tonumber(st.tachyStage) or 0
    local bradyStage = tonumber(st.bradyStage) or 0
    local tachyLabel = "Tachycardia"
    local tachyDesc = "Your heart rate feels abnormally high."
    local tachySrc = LocalMoodleFile("48px-Moodle_tachycardia_anim.webp")
    local bradyLabel = "Bradycardia"
    local bradyDesc = "Your heart rate feels abnormally low."
    local bradySrc = LocalMoodleFile("48px-Bradycardia_Moodle_Animated.gif")

    local arrestLabel = "Cardiac arrest"
    local arrestDesc = "Asystole. If you're somehow conscious, this has a low chance of being treated via defibrillation. Otherwise, cerebral hypoxia and death is soon to follow."
    local arrestSrc = LocalMoodleFile("48px-Cardiacarrest_Moodle_New.png")

    local amputationLabel = "Amputation"
    local amputationDesc = "You've lost a limb. Blood loss and shock are likely. Treatment needed."
    local amputationSrc = LocalMoodleFile("48px-Amputation_Moodle.webp")

    local adrenLabel = "Adrenaline"
    local adrenDesc = "Pain numbed. You're on high alert."
    local adrenSrc = LocalMoodleFile("48px-FightOrFlight_Moodle.gif")
    if adrenStage > 0 then
        adrenLabel = adrenLabel .. " (" .. tostring(adrenStage) .. ")"
    end

    local hungerStage = tonumber(st.hungerStage) or 0
    local hungerLabel = "Peckish"
    local hungerDesc = "Could do with a bite to eat."
    local hungerSrc = LocalMoodleFile("48px-Moodle_hunger_0.webp")
    if hungerStage == 2 then
        hungerLabel = "Hungry"
        hungerDesc = "Uncomfortably hungry. Slightly weaker than usual."
        hungerSrc = LocalMoodleFile("48px-Moodle_hunger_1.webp")
    elseif hungerStage == 3 then
        hungerLabel = "Very hungry"
        hungerDesc = "Extremely hungry, desperate for satiation. Weaker than usual."
        hungerSrc = LocalMoodleFile("48px-Moodle_hunger_2.webp")
    elseif hungerStage == 4 then
        hungerLabel = "Starving"
        hungerDesc = "Your entire body, just wasting away... Total organ failure imminent."
        hungerSrc = LocalMoodleFile("48px-Moodle_hunger_3_anim.webp")
    end

    local exertStage = tonumber(st.exertionStage) or 0
    local exertLabel = "Slightly exerted"
    local exertDesc = "Mildly physically strained."
    local exertSrc = LocalMoodleFile("48px-Endurance_1.webp")
    if exertStage == 2 then
        exertLabel = "Exerted"
        exertDesc = "Uncomfortably exerted, struggling to move and work."
        exertSrc = LocalMoodleFile("48px-Endurance_2.webp")
    elseif exertStage == 3 then
        exertLabel = "Highly exerted"
        exertDesc = "Barely able to move, highly physically exerted."
        exertSrc = LocalMoodleFile("48px-Endurance_3.webp")
    elseif exertStage == 4 then
        exertLabel = "Totally exhausted"
        exertDesc = "Barely able to breathe."
        exertSrc = LocalMoodleFile("48px-Endurance_4.png")
    end

    local lastStandLabel = "Last stand"
    local lastStandDesc = "You're not going down that easily. Something deep inside you compels you to push through."
    local lastStandSrc = LocalMoodleFile("48px-Moodlast.webp")

    -- Z-SCAV: значок радости (солнце) берётся из НАШЕГО настроения и виден только в плюсе.
    -- В минусе солнце пропадает - вместо него значки грусти/уныния/депрессии/отчаяния (zscav_mood).
    local moodStage = 0
    do
        local lp = LocalPlayer()
        local morg = IsValid(lp) and lp.organism
        local m = (morg and tonumber(morg.mood)) or 0
        -- CU: >10 Satisfied, >30 Excited, >50 Happy, >80 Gleeful
        if m > 0.8 then moodStage = 7
        elseif m > 0.5 then moodStage = 6
        elseif m > 0.3 then moodStage = 5
        elseif m > 0.1 then moodStage = 4 end
    end
    local moodLabel = "Satisfied"
    local moodDesc = "Content with your current predicament."
    local moodSrc = LocalMoodleFile("48px-Happy_1.webp")
    local moodImgPx = 44
    if moodStage == 5 then
        moodLabel = "Excited"
        moodDesc = "Looking forward to what's around the corner."
        moodSrc = LocalMoodleFile("48px-Happy_2.webp")
    elseif moodStage == 6 then
        moodLabel = "Happy"
        moodDesc = "You've found peace in this strange land."
        moodSrc = LocalMoodleFile("48px-Happy_3.webp")
    elseif moodStage == 7 then
        moodLabel = "Gleeful"
        moodDesc = "You're at the top of the world, shaping the way forward at your will. Nothing can stop you!"
        moodSrc = LocalMoodleFile("48px-Happy_4.webp")
    elseif moodStage == 1 then
        moodLabel = "Feeling down"
        moodDesc = "Starting to realize the gravity of your situation. Try to distract yourself."
        moodSrc = LocalMoodleFile("48px-Moodle_sad_0.webp")
    elseif moodStage == 2 then
        moodLabel = "Gloomy"
        moodDesc = "Lacking the motivation to go on, struggling with emotions. Things really aren't looking up. Find a way to distract yourself."
        moodSrc = LocalMoodleFile("48px-Moodle_depression_2_anim.webp")
    elseif moodStage == 3 then
        moodLabel = "Miserable"
        moodDesc = "_How does it feel, knowing you're not coming back up..?_"
        moodSrc = LocalMoodleFile("68px-Moodle_miserable_3_anim.webp")
        moodImgPx = 52
    end

    local internalBleedStage = tonumber(st.internalBleedingStage) or 0
    local internalBleedLabel = "Internal bleeding"
    local internalBleedDesc = "Bleeding inside the body. Often hard to detect and potentially lethal. Treatment needed."
    local internalBleedSrc = LocalMoodleFile("48px-Moodle_internalbleed_anim.webp")

    local virusStage = tonumber(st.virusStage) or 0
    local virusLabel = "Infected"
    local virusDesc = "You're infected. Symptoms will worsen over time."
    local virusSrc = LocalMoodleFile("48px-Infection_1.webp")
    if virusStage >= 4 then
        virusLabel = "Severe infection"
        virusDesc = "Systemic infection. You're in serious danger."
        virusSrc = LocalMoodleFile("48px-Infection_4.webp")
    elseif virusStage == 3 then
        virusLabel = "Worsening infection"
        virusDesc = "Feverish and weakening. Breathing issues may start."
        virusSrc = LocalMoodleFile("48px-Infection_3.webp")
    elseif virusStage == 2 then
        virusLabel = "Infection"
        virusDesc = "You're sick. Pain and weakness increasing."
        virusSrc = LocalMoodleFile("48px-Infection_2.webp")
    end

    local hyperStage = tonumber(st.hyperStage) or 0
    local hypoStage = tonumber(st.hypoStage) or 0
    local bpLabel = "Hypertension"
    local bpDesc = "Elevated blood pressure."
    local bpSrc = LocalMoodleFile("48px-Moodle_hypertension_0.webp")
    local bpActive = false
    if hypoStage > 0 then
        bpActive = true
        bpLabel = "Hypotension"
        bpDesc = "Low blood pressure, dizziness and fainting risk."
        bpSrc = LocalMoodleFile("48px-Moodle_hypotension_0.webp")
        if hypoStage == 2 then
            bpDesc = "Very low blood pressure. Dangerously reduced perfusion."
            bpSrc = LocalMoodleFile("48px-Moodle_hypotension_2_anim.webp")
        elseif hypoStage == 3 then
            bpDesc = "Critical hypotension. Imminent collapse."
            bpSrc = LocalMoodleFile("48px-Moodle_hypotension_3_critical.png")
        elseif hypoStage == 1 then
            bpSrc = LocalMoodleFile("48px-Moodle_hypotension_1.webp")
        end
    elseif hyperStage > 0 then
        bpActive = true
        if hyperStage == 2 then
            bpDesc = "High blood pressure. Strain on the heart."
            bpSrc = LocalMoodleFile("48px-Moodle_hypertension_2.webp")
        elseif hyperStage == 3 then
            bpDesc = "Critical hypertension. Risk of organ damage."
            bpSrc = LocalMoodleFile("48px-Moodle_hypertension_3_critical.png")
        elseif hyperStage == 1 then
            bpSrc = LocalMoodleFile("48px-Moodle_hypertension_1.webp")
        end
    end

    local opiatedStage = tonumber(st.opiatedStage) or 0
    local opiatedLabel = "Opiated"
    local opiatedDesc = "Relaxed and calm. Your body feels numb."
    local opiatedSrc = LocalMoodleFile("48px-Overdose_Moodle_1.png")
    if opiatedStage == 2 then
        opiatedLabel = "Drugged"
        opiatedDesc = "Very relaxed and calm, but your lungs feel heavy. A little more tired than usual. This feels pretty good, for now..."
        opiatedSrc = LocalMoodleFile("48px-Overdose_Moodle_2.png")
    elseif opiatedStage == 3 then
        opiatedLabel = "Highly drugged"
        opiatedDesc = "Breathing is difficult, but your mind is in euphoria. This definitely isn't healthy. If only it could last forever..."
        opiatedSrc = LocalMoodleFile("48px-Overdose_Moodle_3.png")
    elseif opiatedStage >= 4 then
        opiatedLabel = "Opioid overdose"
        opiatedDesc = "Respiratory failure. You are experiencing a drug-filled euphoria. Asphyxiation imminent."
        opiatedSrc = LocalMoodleFile("48px-Overdose_Moodle_4.png")
    end

    local items = {
        {
            key = "bleeding",
            active = (bleedStage > 0),
            opacity = (bleedStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(bleedLabel .. "\n" .. bleedDesc),
            src = bleedSrc,
            fallback = fallbackBleed,
            imgPx = bleedImgPx,
            shake = bleedStage,
        },
        {
            key = "internal_bleeding",
            active = (internalBleedStage > 0),
            opacity = (internalBleedStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(internalBleedLabel .. "\n" .. internalBleedDesc),
            src = internalBleedSrc,
            fallback = fallbackBleed,
            shake = math.max(internalBleedStage - 1, 0),
        },
        {
            key = "oxygen",
            active = (oxyStage > 0),
            opacity = (oxyStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(oxyLabel .. "\n" .. oxyDesc),
            src = oxySrc,
            fallback = fallbackBleed,
            shake = oxyStage,
        },
        {
            key = "fractured",
            active = st.broken,
            opacity = st.broken and activeAlpha or inactiveAlpha,
            title = HtmlEscape(fracturedLabel .. "\n" .. fracturedDesc),
            src = fracturedSrc,
            fallback = fallbackBroken,
        },
        {
            key = "dislocated",
            active = st.dislocated,
            opacity = st.dislocated and activeAlpha or inactiveAlpha,
            title = HtmlEscape(dislocLabel .. "\n" .. dislocDesc),
            src = dislocSrc,
            fallback = fallbackDisloc,
        },
        {
            key = "dislocated_jaw",
            active = st.jawDislocated,
            opacity = st.jawDislocated and activeAlpha or inactiveAlpha,
            title = HtmlEscape(jawDislocLabel .. "\n" .. jawDislocDesc),
            src = jawDislocSrc,
            fallback = fallbackDisloc,
        },
        {
            key = "amputation",
            active = st.amputated,
            opacity = st.amputated and activeAlpha or inactiveAlpha,
            title = HtmlEscape(amputationLabel .. "\n" .. amputationDesc),
            src = amputationSrc,
            fallback = fallbackBroken,
        },
        {
            key = "agony",
            active = agonyActive,
            opacity = agonyActive and activeAlpha or inactiveAlpha,
            title = HtmlEscape(agonyLabel .. "\n" .. agonyDesc),
            src = agonySrc,
            fallback = fallbackBleed,
            imgPx = 44,
            shake = agonyActive and 3 or 0,
        },
        {
            key = "pain",
            active = (painStage > 0),
            opacity = (painStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(painLabel .. "\n" .. painDesc),
            src = painSrc,
            fallback = fallbackBleed,
            shake = painStage,
        },
        {
            key = "shock",
            active = shockActive,
            opacity = shockActive and activeAlpha or inactiveAlpha,
            title = HtmlEscape(shockLabel .. "\n" .. shockDesc),
            src = shockSrc,
            fallback = fallbackBleed,
            shake = shockActive and 1 or 0,
        },
        {
            key = "infection",
            active = (virusStage > 0),
            opacity = (virusStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(virusLabel .. "\n" .. virusDesc),
            src = virusSrc,
            fallback = fallbackBleed,
        },
        {
            key = "blood_pressure",
            active = bpActive,
            opacity = bpActive and activeAlpha or inactiveAlpha,
            title = HtmlEscape(bpLabel .. "\n" .. bpDesc),
            src = bpSrc,
            fallback = fallbackBleed,
        },
        -- Z-SCAV: настроение (org.mood -1..1): -10 грусть, -30 уныние, -50 депрессия, -75 отчаяние
        (function()
            local ply = LocalPlayer()
            local org = IsValid(ply) and ply.organism
            local mood = (org and tonumber(org.mood)) or 0
            local e = {key = "zscav_mood", fallback = fallbackBleed, active = false, src = "", title = ""}
            local label, desc, file, shake
            if mood < -0.75 then
                label, desc, file, shake = "Miserable", "Everything feels hopeless. Only opiates can be used from the health panel.", "102px-Moodle_miserable_3_anim.png", 2
            elseif mood < -0.5 then
                label, desc, file, shake = "Depressed", "A heavy, grey weight on everything. You often can't bring yourself to act.", "72px-Moodle_depression_2_anim.png", 1
            elseif mood < -0.3 then
                label, desc, file = "Gloomy", "Feeling really down. You won't find the strength for a last stand.", "72px-Moodle_gloomy_1.png"
            elseif mood < -0.1 then
                label, desc, file = "Feeling down", "Starting to realize the gravity of your situation. Try to distract yourself.", "72px-Moodle_sad_0.png"
            end
            if label then
                e.active = true
                e.src = LocalMoodleFile(file)
                e.title = HtmlEscape(label .. "\n" .. desc)
                e.shake = shake
            end
            e.opacity = e.active and activeAlpha or inactiveAlpha
            return e
        end)(),
        {
            key = "opiated",
            active = (opiatedStage > 0),
            opacity = (opiatedStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(opiatedLabel .. "\n" .. opiatedDesc),
            src = opiatedSrc,
            fallback = fallbackBleed,
            shake = math.max(opiatedStage - 1, 0),
        },
        {
            key = "temperature",
            active = ((coldStage > 0) or (heatStage > 0)),
            opacity = ((coldStage > 0) or (heatStage > 0)) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(tempLabel .. "\n" .. tempDesc),
            src = tempSrc,
            fallback = fallbackBleed,
            shake = math.max(coldStage, heatStage),
        },
        {
            key = "consciousness",
            active = (concStage > 0),
            opacity = (concStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(concLabel .. "\n" .. concDesc),
            src = concSrc,
            fallback = fallbackBleed,
            shake = math.min(concStage, 4),
        },
        {
            key = "brain_damage",
            active = (brainStage > 0),
            opacity = (brainStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(brainLabel .. "\n" .. brainDesc),
            src = brainSrc,
            fallback = fallbackBleed,
            shake = brainStage,
        },
        {
            key = "unconscious",
            active = st.unconscious,
            opacity = st.unconscious and activeAlpha or inactiveAlpha,
            title = HtmlEscape(unconsciousLabel .. "\n" .. unconsciousDesc),
            src = unconsciousSrc,
            fallback = fallbackBleed,
        },
        {
            key = "tachycardia",
            active = (tachyStage > 0),
            opacity = (tachyStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(tachyLabel .. "\n" .. tachyDesc),
            src = tachySrc,
            fallback = fallbackBleed,
            shake = tachyStage,
        },
        {
            key = "bradycardia",
            active = (bradyStage > 0),
            opacity = (bradyStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(bradyLabel .. "\n" .. bradyDesc),
            src = bradySrc,
            fallback = fallbackBleed,
            shake = bradyStage,
        },
        {
            key = "cardiac_arrest",
            active = st.cardiacArrest,
            opacity = st.cardiacArrest and activeAlpha or inactiveAlpha,
            title = HtmlEscape(arrestLabel .. "\n" .. arrestDesc),
            src = arrestSrc,
            fallback = fallbackBleed,
            shake = st.cardiacArrest and 4 or 0,
        },
        {
            key = "adrenaline",
            active = (adrenStage > 0),
            opacity = (adrenStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(adrenLabel .. "\n" .. adrenDesc),
            src = adrenSrc,
            fallback = fallbackBleed,
            shake = adrenStage,
        },
        {
            key = "hunger",
            active = (hungerStage > 0),
            opacity = (hungerStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(hungerLabel .. "\n" .. hungerDesc),
            src = hungerSrc,
            fallback = fallbackBleed,
            shake = hungerStage,
        },
        {
            key = "exertion",
            active = (exertStage > 0),
            opacity = (exertStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(exertLabel .. "\n" .. exertDesc),
            src = exertSrc,
            fallback = fallbackBleed,
            shake = exertStage,
        },
        {
            key = "mood",
            active = (moodStage > 0),
            opacity = (moodStage > 0) and activeAlpha or inactiveAlpha,
            title = HtmlEscape(moodLabel .. "\n" .. moodDesc),
            src = moodSrc,
            fallback = fallbackBleed,
            imgPx = moodImgPx,
            shake = (moodStage >= 3) and 2 or (moodStage > 0 and 1 or 0),
        },
        {
            key = "last_stand",
            active = st.lastStand,
            opacity = st.lastStand and activeAlpha or inactiveAlpha,
            title = HtmlEscape(lastStandLabel .. "\n" .. lastStandDesc),
            src = lastStandSrc,
            fallback = fallbackBleed,
            shake = st.lastStand and 1 or 0,
        },
    }

    -- Z-SCAV: аритмия, инфекция, сепсис, гемоторакс, ломка, глухота
    do
        local ply = LocalPlayer()
        local org = IsValid(ply) and ply.organism or {}
        local function N(v) return tonumber(v) or 0 end
        local maxInf = 0
        local skin = IsValid(ply) and ply.GetNetVar and ply:GetNetVar("remSkin", nil)
        if istable(skin) then
            for _, v in pairs(skin) do
                if istable(v) then maxInf = math.max(maxInf, N(v[2])) end
            end
        end
        local defs = {
            {"zscav_arrhythmia", N(org.arrhythmia) > 0.15 or org.fibrillation == true,
                N(org.arrhythmia) > 0.75 and "48px-moodle_arrythmia_2_critical.png" or (N(org.arrhythmia) > 0.5 and "48px-arrhythmia_3.png" or "72px-Arrhythmia_1.png"),
                N(org.arrhythmia) > 0.75 and "Ventricular fibrillation" or (N(org.arrhythmia) > 0.5 and "Ventricular tachycardia" or "Arrhythmia"),
                N(org.arrhythmia) > 0.75 and "Your heart is quivering instead of pumping. Defibrillate now or it will stop."
                    or (N(org.arrhythmia) > 0.5 and "Your heart is racing out of rhythm. Untreated, it will turn into fibrillation." or "Your heart is beating irregularly. Can be defibrillated."),
                N(org.arrhythmia) > 0.75 and 2 or (N(org.arrhythmia) > 0.5 and 1 or nil)},
            {"zscav_palpitations", (N(org.arrhythmia) > 0.5 or N(org.heartbeat) > 200) and not org.heartstop, "48px-palpitations.png", "Palpitations",
                "You can feel your heart pounding in your chest.", 1},
            {"zscav_infection", maxInf > 0.5, "72px-Infection_3.png", "Infection", "A wound is infected. It hurts and burns.", nil},
            {"zscav_sepsis", N(org.remSepsis) > 0.01, "72px-Sepsis_2.png", "Sepsis", "The infection has spread into the blood. Fever, weakness.", N(org.remSepsis) > 0.5 and 2 or 1},
            {"zscav_hemothorax", N(org.pneumothorax) > 0, "72px-Moodle_hemothorax_1_anim.png", "Hemothorax", "Blood or air in the chest. Hard to breathe.", 1},
            {"zscav_withdrawal", N(org.remComedown) > 0.05, "72px-Withdrawal_3.png", "Withdrawal", "The drugs are wearing off. You feel awful.", nil},
            {"zscav_deaf", N(org.remDeaf) > 0.12, "72px-Deaf_2.png", "Deafened", "Your ears are ringing. You can barely hear.", nil},
            {"zscav_concussion", N(org.brain) >= 0.05 or (N(org.disorientation) > 0.4 and (N(org.skull) > 0 or N(org.brainHemorrhage) > 0)),
                "72px-Concussion_moodle.png", "Concussion", "Your head is spinning. Hard to think straight.", N(org.brain) >= 0.3 and 1 or nil},
            {"zscav_nausea", org.vomitInThroat == true or N(org.stomach) >= 0.3 or N(org.CO) > 0.15 or N(org.remSepsis) > 0.3 or org.remToxic == true or N(org.satiety) > 115,
                "72px-Nausea_2.png", "Nausea", "You feel sick to your stomach.", org.vomitInThroat == true and 1 or nil},
            {"zscav_sleepy", not org.remSleep and N(org.remEnergy or 100) <= 35,
                N(org.remEnergy or 100) <= 15 and "48px-sleep_3.png" or (N(org.remEnergy or 100) <= 25 and "48px-sleep_2.png" or "48px-sleep_1.png"),
                N(org.remEnergy or 100) <= 7 and "Half-asleep" or (N(org.remEnergy or 100) <= 15 and "Very tired" or (N(org.remEnergy or 100) <= 25 and "Tired" or "Drowsy")),
                "You need sleep. Open the health menu and press SLEEP.", N(org.remEnergy or 100) <= 7 and 1 or nil},
            {"zscav_asleep", org.remSleep == true, N(org.remSleepQuality) <= 1 and "48px-badsleep_moodle.png" or "48px-asleep_moodle.png",
                "Asleep", "You are sleeping and regaining energy.", nil},
            {"zscav_energized", not org.remSleep and N(org.remEnergized) > CurTime(), "48px-energized.png", "Energized", "You feel awake. Energy drains slower.", nil},
            -- CU: перепил и переел
            {"zscav_water", N(org.thirst) < 0,
                N(org.thirst) <= -74 and "overhydrated.png" or (N(org.thirst) < -25 and "overhydrated.png" or "slaked.png"),
                N(org.thirst) <= -74 and "Water-intoxicated" or (N(org.thirst) < -25 and "Overhydrated" or "Slaked"),
                N(org.thirst) <= -74 and "Way too much water. Your blood pressure is dangerously high."
                    or (N(org.thirst) < -25 and "Bloated with water. Moving is a bit harder." or "Fully hydrated. Thirst wears off faster for now."),
                N(org.thirst) <= -74 and 2 or nil},
            {"zscav_satiated", N(org.satiety) > 100, N(org.satiety) > 120 and "48px-moodle_hunger_5.png" or "48px-moodle_hunger_4.png",
                N(org.satiety) > 120 and "Full" or "Satiated",
                N(org.satiety) > 120 and "Stuffed. Moving around is harder, and you might throw up." or "Pleasantly full. A little slower.", nil},
            {"zscav_toxicosis", org.remToxic == true, "72px-Toxicosis_3.png", "Toxicosis", "Something poisonous is in your body.", 1},
        }
        for _, d in ipairs(defs) do
            local on = d[2] and true or false
            items[#items + 1] = {
                key = d[1],
                active = on,
                opacity = on and activeAlpha or inactiveAlpha,
                title = on and HtmlEscape(d[4] .. "\n" .. d[5]) or "",
                src = on and LocalMoodleFile(d[3]) or "",
                fallback = fallbackBleed,
                shake = d[6],
            }
        end
    end

    local shake = tonumber(st.shake) or 0
    local html = [[
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
html, body { margin: 0; padding: 0; width: 100%%; height: 100%%; overflow: hidden; background: transparent; }
.wrap { width: 100%%; height: 100%%; display: flex; flex-flow: row nowrap; gap: 2px; justify-content: flex-start; align-items: center; padding: 1px; box-sizing: border-box; }
.m { width: 52px; height: 52px; border-radius: 999px; background: transparent; border: 0; display: flex; align-items: center; justify-content: center; }
.m img { width: 44px; height: 44px; object-fit: contain; will-change: transform; }
.m.new img { animation: popImg 0.34s ease-out both; }
.m.more { background: transparent; border: 0; }
.m.more .t { font-family: Arial, Helvetica, sans-serif; font-size: 18px; font-weight: 800; color: rgba(255,255,255,0.92); text-shadow: 0 0 3px rgba(255,255,255,0.65); }
.tipdata { display: none; }
.tip { position: fixed; left: 0; top: 0; display: none; z-index: 999999; pointer-events: none; }
.tip .box { background: rgba(0,0,0,0.82); color: rgba(255,255,255,0.96); padding: 10px 12px; border-radius: 4px; max-width: 520px; box-shadow: 0 8px 22px rgba(0,0,0,0.35); }
.tip .bar { height: 2px; background: rgba(210, 25, 25, 0.92); margin: -10px -12px 8px -12px; }
.tip .tt { font-family: Arial, Helvetica, sans-serif; font-size: 18px; font-weight: 800; margin: 0 0 4px 0; }
.tip .td { font-family: Arial, Helvetica, sans-serif; font-size: 14px; line-height: 1.15; opacity: 0.92; }
.tip .row { display: flex; flex-flow: row nowrap; align-items: center; gap: 10px; }
.tip .icon { width: 74px; height: 74px; border-radius: 999px; border: 3px solid rgba(255,255,255,0.92); background: rgba(0,0,0,0.10); display: flex; align-items: center; justify-content: center; }
.tip .icon img { width: 58px; height: 58px; object-fit: contain; }
.s1 { animation: s1 0.16s infinite; }
.s2 { animation: s2 0.14s infinite; }
.s3 { animation: s3 0.12s infinite; }
.s4 { animation: s4 0.10s infinite; }
@keyframes popImg { 0%%{transform:translateY(12px) scale(0.96)} 65%%{transform:translateY(-4px) scale(1.04)} 100%%{transform:translateY(0) scale(1)} }
@keyframes s1 { 0%%{transform:translate(0,0)} 25%%{transform:translate(0.35px,-0.25px)} 50%%{transform:translate(-0.3px,0.3px)} 75%%{transform:translate(0.25px,0.2px)} 100%%{transform:translate(0,0)} }
@keyframes s2 { 0%%{transform:translate(0,0)} 25%%{transform:translate(0.6px,-0.4px)} 50%%{transform:translate(-0.55px,0.5px)} 75%%{transform:translate(0.45px,0.35px)} 100%%{transform:translate(0,0)} }
@keyframes s3 { 0%%{transform:translate(0,0)} 25%%{transform:translate(0.85px,-0.55px)} 50%%{transform:translate(-0.75px,0.75px)} 75%%{transform:translate(0.65px,0.55px)} 100%%{transform:translate(0,0)} }
@keyframes s4 { 0%%{transform:translate(0,0)} 25%%{transform:translate(1.1px,-0.7px)} 50%%{transform:translate(-1px,1px)} 75%%{transform:translate(0.8px,0.7px)} 100%%{transform:translate(0,0)} }
</style>
</head>
<body>
  <div class="wrap">
    %s
  </div>
  <div id="tip" class="tip">
    <div class="row">
      <div class="box">
        <div class="bar"></div>
        <div id="tipt" class="tt"></div>
        <div id="tipd" class="td"></div>
      </div>
      <div id="tipiconwrap" class="icon"><img id="tipi"></div>
    </div>
  </div>
  <script>
  (function(){
    var tip = document.getElementById('tip');
    var tipTitle = document.getElementById('tipt');
    var tipDesc = document.getElementById('tipd');
    var tipIcon = document.getElementById('tipi');
    var tipIconWrap = document.getElementById('tipiconwrap');
    var current = null;

    function pickMoodle(el){
      while(el && el !== document.body){
        if(el.classList && el.classList.contains('m')) return el;
        el = el.parentElement;
      }
      return null;
    }

    function placeTip(e){
      if(!tip || tip.style.display === 'none') return;
      var x = (e.clientX || 0) + 12;
      var y = (e.clientY || 0) + 12;
      var r = tip.getBoundingClientRect();
      var w = r.width || (tip.offsetWidth || 0);
      var h = r.height || (tip.offsetHeight || 0);
      var maxX = (window.innerWidth || 0) - w - 10;
      var maxY = (window.innerHeight || 0) - h - 10;
      if(x > maxX) x = maxX;
      if(y > maxY) y = maxY;
      if(x < 10) x = 10;
      if(y < 10) y = 10;
      tip.style.left = x + 'px';
      tip.style.top = y + 'px';
    }

    document.addEventListener('mouseover', function(e){
      var m = pickMoodle(e.target);
      if(!m) return;
      var data = m.querySelector('.tipdata');
      if(!data) return;
      current = m;
      var t = data.querySelector('.tt');
      var d = data.querySelector('.td');
      if (tipTitle) tipTitle.innerHTML = (t && t.innerHTML) ? t.innerHTML : '';
      if (tipDesc) tipDesc.innerHTML = (d && d.innerHTML) ? d.innerHTML : '';
      var src = m.getAttribute('data-src') || '';
      var fb = m.getAttribute('data-fb') || '';
      if (tipIcon && tipIconWrap) {
        if (src === '' && fb === '') {
          tipIconWrap.style.display = 'none';
        } else {
          tipIconWrap.style.display = 'flex';
          tipIcon.onerror = function(){ this.onerror = null; if (fb) this.src = fb; };
          tipIcon.src = src || fb;
        }
      }
      tip.style.display = 'block';
      placeTip(e);
    }, true);

    document.addEventListener('mousemove', function(e){
      if(!current) return;
      placeTip(e);
    }, true);

    document.addEventListener('mouseout', function(e){
      var m = pickMoodle(e.target);
      if(!m || m !== current) return;
      var rel = e.relatedTarget;
      if(rel && m.contains(rel)) return;
      current = null;
      tip.style.display = 'none';
    }, true);
  })();
  </script>
</body>
</html>
]]

    local activeItemsBySrc = {}
    local activeItems = {}
    for i = 1, #items do
        local it = items[i]
        if it and it.active then
            local srcKey = tostring(it.src or "") .. "|" .. tostring(it.fallback or "")
            local existing = activeItemsBySrc[srcKey]
            if existing then
                local t1 = tostring(existing.title or "")
                local t2 = tostring(it.title or "")
                if t2 ~= "" then
                    if t1 ~= "" then
                        existing.title = t1 .. "&#10;&#10;" .. t2
                    else
                        existing.title = t2
                    end
                end
                existing.imgPx = math.max(tonumber(existing.imgPx) or 44, tonumber(it.imgPx) or 44)
            else
                it.__zcity_delta_srcKey = srcKey
                activeItemsBySrc[srcKey] = it
                activeItems[#activeItems + 1] = it
            end
        end
    end

    local limit = 9999
    local shown = 0
    local shownItems = {}
    local anyNew = false
    local nextActive = {}

    for i = 1, #activeItems do
        if shown >= limit then break end
        local it = activeItems[i]
        shown = shown + 1
        local imgPx = tonumber(it.imgPx) or 44
        local srcKey = tostring(it.__zcity_delta_srcKey or (tostring(it.src or "") .. "|" .. tostring(it.fallback or "")))
        nextActive[srcKey] = true
        local isNew = not moodlesPrevActiveBySrc[srcKey]
        if isNew then anyNew = true end

        shownItems[#shownItems + 1] = {
            title = TooltipPlainFromTitle(it.title),
            fileName = TryExtractFileNameFromUrl(it.src) or TryExtractFileNameFromUrl(it.fallback),
            opacity = tonumber(it.opacity) or activeAlpha,
            imgPx = imgPx,
            shake = tonumber(it.shake) or 0,
        }
    end

    local remaining = 0

    local visibleCount = shown
    local gap = 2
    local pad = 1
    local iconOuter = 52
    local width = (pad * 2) + (visibleCount * iconOuter) + (math.max(visibleCount - 1, 0) * gap)
    local height = (pad * 2) + iconOuter
    pnl:SetSize(width, height)
    pnl.__zcity_delta_items = shownItems
    moodlesShown = shownItems
    moodlesPrevActiveBySrc = nextActive
    if anyNew then
        moodlesPopStart = CurTime()
    else
        moodlesPopStart = 0
    end
end

hook.Add("HUDPaint", "zcity_delta_moodles_tooltip_draw", function()
    if cvMoodlesShow and cvMoodlesShow.GetBool and not cvMoodlesShow:GetBool() then return end
    if not moodlesPnl or not IsValid(moodlesPnl) then return end
    if not istable(moodlesShown) or #moodlesShown <= 0 then return end
    EnsureMoodlesTooltipFonts()

    if not hg then hg = {} end
    hg.__zcity_delta_moodles_tip_hover_idx = hg.__zcity_delta_moodles_tip_hover_idx or 0
    hg.__zcity_delta_moodles_tip_hover_start = hg.__zcity_delta_moodles_tip_hover_start or 0
    hg.__zcity_delta_moodles_tip_anim_dur = 0.22
    hg.__zcity_delta_moodles_tip_slide = 28

    local mx, my
    if vgui and vgui.CursorVisible and vgui.CursorVisible() then
        mx, my = gui.MousePos()
    else
        mx, my = ScrW() * 0.5, ScrH() * 0.5
    end
    if not mx or not my or mx <= 0 or my <= 0 then return end

    local px, py = moodlesPnl:GetPos()
    local pw, ph = moodlesPnl:GetSize()
    if mx < px or mx > (px + pw) or my < py or my > (py + ph) then
        hg.__zcity_delta_moodles_tip_hover_idx = 0
        return
    end

    local gap = 2
    local pad = 1
    local iconOuter = 52
    local relX = mx - (px + pad)
    local idx = math.floor(relX / (iconOuter + gap)) + 1
    if idx < 1 or idx > #moodlesShown then
        hg.__zcity_delta_moodles_tip_hover_idx = 0
        return
    end
    local item = moodlesShown[idx]
    if not item then
        hg.__zcity_delta_moodles_tip_hover_idx = 0
        return
    end

    local title = tostring(item.title or "")
    if title == "" then
        hg.__zcity_delta_moodles_tip_hover_idx = 0
        return
    end

    if hg.__zcity_delta_moodles_tip_hover_idx ~= idx then
        hg.__zcity_delta_moodles_tip_hover_idx = idx
        hg.__zcity_delta_moodles_tip_hover_start = CurTime()
    end
    local tAnim = (CurTime() - (hg.__zcity_delta_moodles_tip_hover_start or 0)) / (hg.__zcity_delta_moodles_tip_anim_dur or 0.22)
    tAnim = math.Clamp(tAnim, 0, 1)
    local ease = EaseOutBack(tAnim)
    local alpha = math.floor(255 * tAnim)

    local firstLine, rest = title:match("^(.-)\n(.*)$")
    if not firstLine then
        firstLine = title
        rest = ""
    end

    local function WrapText(text, font, maxWidth)
        text = tostring(text or "")
        if text == "" then return {} end
        surface.SetFont(font)
        local out = {}
        for rawLine in string.gmatch(text, "([^\n]+)") do
            local line = ""
            for word in string.gmatch(rawLine, "%S+") do
                local candidate = (line == "") and word or (line .. " " .. word)
                local w = select(1, surface.GetTextSize(candidate))
                if w <= maxWidth then
                    line = candidate
                else
                    if line ~= "" then
                        out[#out + 1] = line
                    end
                    line = word
                end
            end
            if line ~= "" then
                out[#out + 1] = line
            end
        end
        return out
    end

    local bgMat = GetMoodlesTooltipFrameMat()
    local iconFrameMat = GetMoodlesTooltipIconFrameMat()

    local textPadX = 12
    local textPadY = 10
    local iconPad = 12
    local minTextW = 160
    local maxTextW = 760

    local titleFont = "zcity_delta_moodles_tip_title"
    local descFont = "zcity_delta_moodles_tip_desc"
    local titleLineH = 18
    local descLineH = 14

    surface.SetFont(titleFont)
    local wTitle = select(1, surface.GetTextSize(firstLine))
    surface.SetFont(descFont)
    local wDesc = select(1, surface.GetTextSize(rest))

    local wantedTextW = math.Clamp(math.max(wTitle, wDesc), minTextW, maxTextW)
    local titleLines = WrapText(firstLine, titleFont, wantedTextW)
    if #titleLines <= 0 then titleLines = { firstLine } end
    local descLines = WrapText(rest, descFont, wantedTextW)

    local function MaxLineW(lines, font)
        surface.SetFont(font)
        local mx = 0
        for i = 1, #lines do
            local w = select(1, surface.GetTextSize(lines[i]))
            if w > mx then mx = w end
        end
        return mx
    end

    local maxLineW = math.max(MaxLineW(titleLines, titleFont), MaxLineW(descLines, descFont))
    local textW = math.Clamp(maxLineW, minTextW, maxTextW)

    local titleH = #titleLines * titleLineH
    local descH = (#descLines > 0) and (#descLines * descLineH + 4) or 0
    local neededTextH = titleH + descH
    local boxH = math.Clamp(neededTextH + textPadY * 2, 64, 200)
    local iconSize = boxH
    local boxW = math.Clamp(textW + textPadX * 2 + iconPad + iconSize, 320, 1024)
    local totalW = boxW
    local totalH = boxH

    local tx = px
    local ty = py - totalH - 8
    if ty < 10 then
        ty = py + ph + 8
    end
    if tx + totalW > ScrW() - 10 then
        tx = ScrW() - totalW - 10
    end
    if tx < 10 then tx = 10 end
    tx = tx - (1 - ease) * (hg.__zcity_delta_moodles_tip_slide or 28)

    if bgMat then
        surface.SetDrawColor(255, 255, 255, alpha)
        surface.SetMaterial(bgMat)
        surface.DrawTexturedRect(tx, ty, totalW, totalH)
    else
        draw.RoundedBox(0, tx, ty, totalW, totalH, Color(0, 0, 0, math.floor(210 * (alpha / 255))))
    end

    local textX = tx + textPadX
    local textY = ty + textPadY
    local bottomLimit = ty + totalH - 8

    surface.SetTextColor(0, 255, 0, alpha)
    surface.SetFont(titleFont)
    for i = 1, #titleLines do
        surface.SetTextPos(textX, textY)
        surface.DrawText(titleLines[i])
        textY = textY + titleLineH
    end

    if #descLines > 0 then
        textY = textY + 2
        surface.SetTextColor(0, 255, 0, math.floor(235 * (alpha / 255)))
        surface.SetFont(descFont)
        for i = 1, #descLines do
            if textY + descLineH > bottomLimit then break end
            surface.SetTextPos(textX, textY)
            surface.DrawText(descLines[i])
            textY = textY + descLineH
        end
    end

    local iconX = tx + (totalW - iconSize)
    local iconY = ty

    if iconFrameMat then
        surface.SetDrawColor(255, 255, 255, alpha)
        surface.SetMaterial(iconFrameMat)
        surface.DrawTexturedRect(iconX, iconY, iconSize, iconSize)
    end

    local mat = GetMoodleMatFromFileName(item.fileName)
    if mat then
        surface.SetDrawColor(255, 255, 255, alpha)
        surface.SetMaterial(mat)
        local isz = math.floor(iconSize * 0.72)
        surface.DrawTexturedRect(iconX + (iconSize - isz) * 0.5, iconY + (iconSize - isz) * 0.5, isz, isz)
    end
end)

hook.Add("Think", "zcity_delta_moodles", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then
        StopMoodles()
        ResetMoodlesClientCache()
        return
    end

    if CurTime() >= moodlesCleanupNext then
        moodlesCleanupNext = CurTime() + 1
        KillStrayMoodlesPanels(moodlesPnl)
    end

    if not lp:Alive() then
        StopMoodles()
        ResetMoodlesClientCache()
        return
    end

    if cvMoodlesShow and cvMoodlesShow.GetBool and not cvMoodlesShow:GetBool() then
        StopMoodles()
        return
    end

    local cvMental = GetConVar and GetConVar("zcity_delta_mental_enabled") or nil
    local mentalEnabled = not cvMental or cvMental:GetBool()
    if moodlesLastMentalEnabled == nil then
        moodlesLastMentalEnabled = mentalEnabled
    elseif moodlesLastMentalEnabled ~= mentalEnabled then
        moodlesLastMentalEnabled = mentalEnabled
        moodlesState = nil
        moodlesShown = nil
        moodlesPrevActiveBySrc = {}
    end

    if CurTime() < moodlesNextUpdate then return end
    moodlesNextUpdate = CurTime() + 0.25

    local org = lp.organism
    local hyperStage, hypoStage = GetBloodPressureStage(org)
    local opiatedStage = GetOpiateStage(org)
    local agonyActive = HasAgony(org)
    local hungerEnabled = true
    do
        -- Z-SCAV: голод включается zscav_hunger (или старым hg_hungersystem)
        local hgHunger = GetConVar and GetConVar("hg_hungersystem") or nil
        local zsHunger = GetConVar and GetConVar("zscav_hunger") or nil
        local on = (hgHunger and hgHunger:GetBool()) or (zsHunger and zsHunger:GetBool())
        if (hgHunger or zsHunger) and not on then
            hungerEnabled = false
        end
    end
    local st = {
        bleedingStage = GetBleedingStage(org),
        internalBleedingStage = GetInternalBleedingStage(org),
        broken = HasBrokenBone(org),
        dislocated = HasDislocation(org),
        jawDislocated = HasJawDislocation(org),
        unconscious = org and org.otrub == true,
        adrenalineStage = GetAdrenalineStage(org),
        agony = agonyActive,
        painStage = agonyActive and 0 or GetPainStage(org),
        shockStage = GetShockStage(org),
        oxygenStage = GetOxygenStage(org),
        coldStage = GetTempColdStage(org),
        heatStage = GetTempHeatStage(org),
        consciousnessStage = GetConsciousnessStage(org),
        brainDamageStage = GetBrainDamageStage(org),
        tachyStage = GetTachycardiaStage(org),
        bradyStage = GetBradycardiaStage(org),
        cardiacArrest = IsCardiacArrest(org),
        amputated = IsAmputated(org),
        hungerStage = hungerEnabled and GetHungerStage(org) or 0,
        exertionStage = GetExertionStage(org),
        lastStand = IsLastStandActive(),
        moodStage = mentalEnabled and GetMoodStage(lp) or 0,
        virusStage = GetVirusStage(),
        hyperStage = hyperStage,
        hypoStage = hypoStage,
        opiatedStage = opiatedStage,
    }

    local shake = 0
    shake = math.max(shake, tonumber(st.bleedingStage) or 0)
    shake = math.max(shake, tonumber(st.internalBleedingStage) or 0)
    shake = math.max(shake, tonumber(st.painStage) or 0)
    shake = math.max(shake, st.agony and 3 or 0)
    shake = math.max(shake, tonumber(st.oxygenStage) or 0)
    shake = math.max(shake, tonumber(st.coldStage) or 0)
    shake = math.max(shake, tonumber(st.heatStage) or 0)
    shake = math.max(shake, tonumber(st.consciousnessStage) or 0)
    shake = math.max(shake, tonumber(st.brainDamageStage) or 0)
    shake = math.max(shake, tonumber(st.exertionStage) or 0)
    shake = math.max(shake, tonumber(st.hungerStage) or 0)
    shake = math.max(shake, tonumber(st.opiatedStage) or 0)
    shake = math.Clamp(math.floor(shake), 0, 4)
    st.shake = shake

    if moodlesState
        and moodlesState.bleedingStage == st.bleedingStage
        and moodlesState.internalBleedingStage == st.internalBleedingStage
        and moodlesState.broken == st.broken
        and moodlesState.dislocated == st.dislocated
        and moodlesState.jawDislocated == st.jawDislocated
        and moodlesState.unconscious == st.unconscious
        and moodlesState.adrenalineStage == st.adrenalineStage
        and moodlesState.agony == st.agony
        and moodlesState.painStage == st.painStage
        and moodlesState.shockStage == st.shockStage
        and moodlesState.oxygenStage == st.oxygenStage
        and moodlesState.coldStage == st.coldStage
        and moodlesState.heatStage == st.heatStage
        and moodlesState.consciousnessStage == st.consciousnessStage
        and moodlesState.brainDamageStage == st.brainDamageStage
        and moodlesState.tachyStage == st.tachyStage
        and moodlesState.bradyStage == st.bradyStage
        and moodlesState.cardiacArrest == st.cardiacArrest
        and moodlesState.amputated == st.amputated
        and moodlesState.hungerStage == st.hungerStage
        and moodlesState.exertionStage == st.exertionStage
        and moodlesState.lastStand == st.lastStand
        and moodlesState.moodStage == st.moodStage
        and moodlesState.virusStage == st.virusStage
        and moodlesState.hyperStage == st.hyperStage
        and moodlesState.hypoStage == st.hypoStage
        and moodlesState.opiatedStage == st.opiatedStage then
        local pnl = moodlesPnl
        if pnl and IsValid(pnl) then
            local x, y = GetMoodlesPos()
            local y2 = y
            local dt = (CurTime() - (moodlesPopStart or 0)) / (moodlesPopDur or 0.28)
            if dt >= 0 and dt < 1 then
                local e = EaseOutBack(dt)
                y2 = y + (1 - e) * (moodlesPopOffset or 18)
            end
            pnl:SetPos(x, y2)
            pnl:SetMouseInputEnabled(vgui.CursorVisible())
        end
        return
    end

    local pnl = EnsureMoodlesPanel()
    if not pnl then return end
    local x, y = GetMoodlesPos()
    local y2 = y
    local dt = (CurTime() - (moodlesPopStart or 0)) / (moodlesPopDur or 0.28)
    if dt >= 0 and dt < 1 then
        local e = EaseOutBack(dt)
        y2 = y + (1 - e) * (moodlesPopOffset or 18)
    end
    pnl:SetPos(x, y2)
    pnl:SetMouseInputEnabled(vgui.CursorVisible())
    moodlesState = st
    SetMoodlesHtml(pnl, st)
end)

hook.Add("ShutDown", "zcity_delta_moodles_cleanup", function()
    StopMoodles()
end)

do
    local schizoFontsReady = false
    local function EnsureSchizoFonts()
        if schizoFontsReady then return end
        schizoFontsReady = true
        if not surface or not surface.CreateFont then return end
        surface.CreateFont("zcity_delta_schizo_text", {
            font = "Pixel Operator",
            size = 16,
            weight = 700,
            antialias = false,
            additive = false,
        })
    end

    local goodPhrases = {
        "you are doing great",
        "everything is fine",
        "smile :)",
        "trust me",
        "keep going",
        "nice weather today",
        "dont look back",
        "you are safe",
        "take a deep breath",
        "it will pass",
        "you will be okay",
        "calm down",
        "focus on the mission",
        "look at the sky",
        "no one can hurt you",
        "its just a game",
        "you are stronger than them",
        "they cant see you",
        "dont panic",
        "i am proud of you",
        "everything will work out",
        "you did the right thing",
        "keep smiling",
        "relax your shoulders",
        "count to ten",
        "stay quiet",
        "stay sharp",
        "you are in control",
        "keep breathing",
    }
    local evilPhrases = {
        "i hope you will die",
        "they laugh at you",
        "you are worthless",
        "its all your fault",
        "run while you can",
        "they are watching",
        "you will lose",
        "you are already dead",
        "you cant trust anyone",
        "they want you gone",
        "you will fail again",
        "everyone hates you",
        "you are a mistake",
        "they know what you did",
        "dont turn around",
        "you are not safe",
        "you will never escape",
        "they will find you",
        "stop pretending",
        "you deserve it",
        "you should give up",
        "its hopeless",
        "you cant win",
        "no one will help you",
        "they are right behind you",
        "you are weak",
        "you should disappear",
        "your hands are shaking",
        "you will be punished",
    }

    local smileyMat = Material("smiley/smiley.png", "smooth noclamp")
    local smileyTalkingMat = Material("smiley/smiley_talking.png", "smooth noclamp")
    local crazyMat = Material("smiley/crazy_smiley.png", "smooth noclamp")
    local crazyTalkingMat = Material("smiley/crazy_smiley_talking.png", "smooth noclamp")

    local schizoPhrase = ""
    local schizoMode = "good"
    local schizoTyping = false
    local schizoStartAt = 0
    local schizoHoldUntil = 0
    local schizoNextAt = 0
    local schizoAudio = nil
    local schizoAudioMode = nil

    local function StopSchizoAudio()
        if schizoAudio and schizoAudio.Stop then
            schizoAudio:Stop()
        end
        schizoAudio = nil
        schizoAudioMode = nil
    end

    local function StartSchizoAudio(mode)
        StopSchizoAudio()
        local path = mode == "evil" and "sound/zcity_delta/0604_1.mp3" or "sound/zcity_delta/0604.mp3"
        sound.PlayFile(path, "noplay", function(chan)
            if not chan then return end
            schizoAudio = chan
            schizoAudioMode = mode
            if chan.SetVolume then chan:SetVolume(0.8) end
            if chan.EnableLooping then chan:EnableLooping(true) end
            if chan.Play then chan:Play() end
        end)
    end

    local function PickPhrase(mode)
        if mode == "evil" then
            return evilPhrases[math.random(1, #evilPhrases)]
        end
        return goodPhrases[math.random(1, #goodPhrases)]
    end

    local function BeginTyping(mode)
        schizoMode = mode
        schizoPhrase = PickPhrase(mode) or ""
        schizoTyping = schizoPhrase ~= ""
        schizoStartAt = CurTime()
        schizoHoldUntil = 0
        schizoNextAt = 0
        if schizoTyping then
            StartSchizoAudio(mode)
        else
            StopSchizoAudio()
        end
    end

    hook.Add("HUDPaint", "zcity_delta_schizophrenia_smiley", function()
        EnsureSchizoFonts()
        local cv = GetConVar and GetConVar("zcity_delta_traits_enabled") or nil
        if cv and not cv:GetBool() then
            StopSchizoAudio()
            schizoTyping = false
            return
        end

        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:Alive() then
            StopSchizoAudio()
            schizoTyping = false
            return
        end

        hg = hg or {}
        local tr = hg.__zcity_delta_traits or {}
        if not tr.schizophrenia then
            StopSchizoAudio()
            schizoTyping = false
            return
        end

        local mood = tonumber(lp:GetNWInt("zcity_delta_mood", 0)) or 0
        local mode = mood < -10 and "evil" or "good"

        if schizoTyping and schizoMode ~= mode then
            schizoTyping = false
            StopSchizoAudio()
            schizoNextAt = CurTime() + 0.2
        end

        if not schizoTyping and CurTime() >= (schizoNextAt or 0) then
            BeginTyping(mode)
        end

        local cps = 26
        local shown = 0
        local text = ""
        if schizoTyping then
            shown = math.floor(math.max(0, CurTime() - schizoStartAt) * cps + 0.5)
            if shown >= #schizoPhrase then
                shown = #schizoPhrase
                schizoTyping = false
                schizoHoldUntil = CurTime() + math.Rand(2.0, 4.0)
                schizoNextAt = schizoHoldUntil + math.Rand(12.0, 24.0)
                StopSchizoAudio()
            end
            text = schizoPhrase:sub(1, shown)
        else
            if (schizoHoldUntil or 0) > CurTime() then
                text = schizoPhrase
            else
                text = ""
            end
        end

        if schizoAudio and schizoAudio.Play and schizoAudioMode == mode then
            if schizoAudio.GetState and schizoAudio:GetState() == GMOD_CHANNEL_STOPPED then
                schizoAudio:Play()
            end
        end

        local mx, my = GetMoodlesPos()
        local size = 100
        local stretch = 1
        if schizoTyping then
            local p = math.Clamp((CurTime() - schizoStartAt) / 0.55, 0, 1)
            local hump = math.sin(math.pi * p) + 0.28 * math.sin(math.pi * 3 * p)
            hump = math.max(0, hump)
            stretch = 1 + 0.22 * hump
        end
        local w = size
        local h = size * stretch
        local x = ScrW() - 20 - w
        local y = ScrH() - 20 - h
        if y < 10 then y = 10 end

        local mat = smileyMat
        if mode == "evil" then
            mat = schizoTyping and crazyTalkingMat or crazyMat
        else
            mat = schizoTyping and smileyTalkingMat or smileyMat
        end

        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(mat)
        surface.DrawTexturedRect(x, y, w, h)

        if text ~= "" then
            local col = mode == "evil" and Color(255, 80, 80, 255) or Color(255, 230, 80, 255)
            draw.SimpleTextOutlined(text, "zcity_delta_schizo_text", x + w, y - 8, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 220))
        end
    end)
end
