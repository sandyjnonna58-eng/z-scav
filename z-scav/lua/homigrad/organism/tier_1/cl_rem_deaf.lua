--[[
    Z-SCAV: глухота на клиенте - звук глохнет (DSP 35/36/37) и звенит в ушах.
]]

local tinnitus, curDSP = nil, 0

hook.Add("Think", "ZSCAV_Deaf", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local org = ply.organism
    local d = (ply:Alive() and org and tonumber(org.remDeaf)) or 0

    local dsp = 0
    if d >= 0.7 then dsp = 37 elseif d >= 0.4 then dsp = 36 elseif d >= 0.12 then dsp = 35 end
    if dsp ~= curDSP then
        if dsp > 0 or curDSP > 0 then ply:SetDSP(dsp, false) end
        curDSP = dsp
    end

    -- звон в ушах
    if d > 0.05 then
        if not IsValid(tinnitus) and not ply.zscavTinnitusLoading and file.Exists("sound/remorse/tinnitus_loop.wav", "GAME") then
            ply.zscavTinnitusLoading = true
            sound.PlayFile("sound/remorse/tinnitus_loop.wav", "noplay", function(st)
                ply.zscavTinnitusLoading = false
                if not IsValid(st) then return end
                tinnitus = st
                st:EnableLooping(true)
                st:SetVolume(0)
                st:Play()
            end)
        end
        if IsValid(tinnitus) then tinnitus:SetVolume(math.Clamp(d, 0, 1) * 0.5) end
    elseif IsValid(tinnitus) then
        tinnitus:Stop()
        tinnitus = nil
    end
end)
