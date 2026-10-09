local min, max, Round, halfValue2 = math.min, math.max, math.Round, util.halfValue2
--local Organism = hg.organism
hg.organism.module.pulse = {}

-- REM: пороги крови для сердца (мл; норма 5000)
hg.organism.bloodHeart = hg.organism.bloodHeart or {}
hg.organism.bloodHeart.ARRHYTHMIA      = 3500 -- ниже - аритмия
hg.organism.bloodHeart.ARREST          = 2700 -- на этом уровне и ниже - остановка сердца
hg.organism.bloodHeart.ARRHYTHMIA_MIN  = 0.35 -- сила аритмии сразу под порогом (1 - максимум у ARREST)
hg.organism.bloodHeart.ARRHYTHMIA_RISE = 6    -- за сколько секунд аритмия набирает силу
-- Z-SCAV: числа из вики Casualties: Unknown (Heart rate)
hg.organism.heartCU = hg.organism.heartCU or {
	BASE        = 70,
	ADRENALINE  = 20,    -- уд/мин за единицу адреналина гейммода
	BP_LOW      = 85,    -- ниже - сердце разгоняется, чтобы поднять давление (норма ~90 = 120/80)
	BP_HIGH     = 100,   -- выше - замедляется
	OPIATE      = 8,     -- уд/мин за единицу анальгезии
	WITHDRAWAL  = 25,    -- уд/мин за единицу ломки (0..0.5)
	FIB_BP      = 58,    -- ~88/58: ниже фибрилляция растёт
	ARREST_HR   = 20,    -- ниже - остановка сердца
	EPI_RESTART = 0.03,  -- шанс в секунду завести сердце адреналином (эпинефрином)
}
local module = hg.organism.module.pulse
local Clamp, Approach, Remap = math.Clamp, math.Approach, math.Remap
local CurTime = CurTime
local function getBloodVolume(org)
	return Clamp((org.blood - 900) / 4100, 0, 1)
end

local function getHeartEfficiency(org)
	local heart = Clamp(1 - org.heart, 0, 1)
	local ischemia = Clamp(1 - (org.myocardialOxygen or 1), 0, 1)
	local strain = Clamp(org.heartStrain or 0, 0, 1)
	return Clamp(heart - ischemia * 0.35 - strain * 0.25, 0, 1)
end

local function addArrhythmia(org, amount)
	org.arrhythmia = Clamp((org.arrhythmia or 0) + amount, 0, 1)
	org.nextArrhythmiaRoll = math.min(org.nextArrhythmiaRoll or CurTime(), CurTime() + 4)
end

function hg.organism.AddCardiacStress(org, amount)
	if not org or not isnumber(amount) or amount <= 0 then return 0 end
	addArrhythmia(org, amount)
	org.heartStrain = Clamp((org.heartStrain or 0) + amount * 0.45, 0, 1)
	return org.arrhythmia
end

function hg.organism.StartFibrillation(org)
	if not org or org.heartstop then return end
	org.fibrillation = true
	org.arrhythmia = math.max(org.arrhythmia or 0, 0.8)
	org.fibrillationStart = CurTime()
end

function hg.organism.TryRestartHeartWithCPR(org, cprMul)
	if not org or not org.alive or not org.heartstop or org.deathStateKilled then return false end
	if (org.pulse or 0) <= 15 or (org.brain or 0) >= 0.6 or (org.heart or 0) >= 1 then return false end

	cprMul = cprMul or 1
	local adrenaline = Clamp(org.adrenaline or 0, 0, 3)
	local chance = Clamp(6 * cprMul + adrenaline * 12, 6, 45)

	if math.random(100) > chance then return false end

	org.heartstop = false
	org.fibrillation = false
	org.arrhythmia = 0
	org.heartbeat = Clamp(org.heartbeat or 70, 55, 90)
	org.pulse = max(org.pulse or 0, 25)
	org.bloodPressure = max(org.bloodPressure or 0, 35)
	org.cardiacOutput = max(org.cardiacOutput or 0, 0.35)
	org.myocardialOxygen = max(org.myocardialOxygen or 0, 0.35)

	return true
end

module[1] = function(org)
	org.heart = 0
	org.heartstop = false
	org.pulse = 70 -- that's the blood pressure
	org.heartbeat = 70
	org.bloodPressure = 90
	org.systolic = 120
	org.diastolic = 80
	org.cardiacOutput = 1
	org.arrhythmia = 0
	org.fibrillation = false
	org.fibrillationStart = 0
	org.myocardialOxygen = 1
	org.heartStrain = 0
	org.hypertension = 0
	org.hypotension = 0
	org.nextArrhythmiaRoll = 0
	org.lastCardiacPain = 0

	org.tempchanging = 0
	org.heatbuff = 30 -- seconds of heat supply
	org.needed_temp = 36.7
end

function hg.organism.should_gain_fear(org)
	return ((org.pain > 30) or (org.blood < 3000) or (org.bleed > 1))// + (org.just_damaged_bone and ((org.just_damaged_bone + 10 - CurTime()) >= 10) and 10 or 0)
end

module[2] = function(owner, org, timeValue)
	if not org.heartstop and not org.fibrillation and (org.arrhythmia or 0) < 0.25 and (org.myocardialOxygen or 1) > 0.55 then
		org.heartStrain = Approach(org.heartStrain or 0, 0, timeValue / 45)
	end

	local heart = getHeartEfficiency(org)
	local brain = math.Clamp(1 - org.brain * 1.5,0,1)
	local o2 = org.o2
	local o2 = halfValue2(o2[1], o2.range, o2.k)

	//if org.isPly and not org.otrub and (heart == 0) then org.owner:Notify("Грудь болит.",true,"heart",6) end
	//if org.isPly and not org.otrub and org.heartstop then org.owner:Notify("",true,"heartstop",6) end

	local stamina = org.stamina
	
	local bloodVolume = getBloodVolume(org)
	local oxygenation = Clamp(o2, 0, 1)
	local vascularTone = Clamp(1 + min(org.adrenaline, 3) * 0.12 + max(org.fear, 0) * 0.08 + Clamp(org.shock, 0, 45) / 360, 0.65, 1.55)
	local overhyd = Clamp(-(org.thirst or 0) / 75, 0, 1) -- Z-SCAV (CU): перепил поднимает давление
	local pressureBase = 92 * (1 + overhyd * 0.12 + (overhyd >= 0.98 and 0.15 or 0)) * bloodVolume * heart * vascularTone * Clamp(Remap(org.temperature, 28, 36.7, 0.55, 1), 0.45, 1.1)
	local rhythmMul = org.fibrillation and 0.18 or Clamp(1 - (org.arrhythmia or 0) * 0.22, 0.5, 1)
	local defibGrace = (org.defibDeathGrace or 0) > CurTime()
	local arrestPressure = defibGrace and 45 or 0
	local pressure = org.alive and (org.heartstop and arrestPressure or pressureBase * rhythmMul) or 0
	local pressureFallSpeed = defibGrace and 4 or 18
	org.bloodPressure = Approach(org.bloodPressure or pressure, pressure, pressure > (org.bloodPressure or 0) and timeValue * 12 or timeValue * pressureFallSpeed)
	org.pulse = Approach(org.pulse, org.bloodPressure, heart == 0 and timeValue * 10 or timeValue * 5)
	org.systolic = Round(Clamp(org.bloodPressure * 1.38 + (org.heartbeat or 70) * 0.12, 0, 240))
	org.diastolic = Round(Clamp(org.bloodPressure * 0.88, 0, 160))
	org.cardiacOutput = org.heartstop and (defibGrace and Clamp((org.pulse or org.bloodPressure) / 70 * 0.35, 0, 0.45) or 0) or Clamp((org.bloodPressure / 90) * heart * rhythmMul, 0, 1.5)
	if not org.heartstop and not org.fibrillation and (org.arrhythmia or 0) < 0.25 and (org.myocardialOxygen or 1) > 0.65 and org.bloodPressure > 55 then
		org.cardiacOutput = Approach(org.cardiacOutput, Clamp(getBloodVolume(org) * heart, 0, 1), timeValue / 20)
	end
	local myocardialTarget = Clamp(oxygenation * bloodVolume * Clamp(org.bloodPressure / 70, 0, 1.2), 0, 1)
	if org.heartstop and defibGrace then myocardialTarget = math.max(myocardialTarget, 0.25) end
	org.myocardialOxygen = Approach(org.myocardialOxygen or 1, myocardialTarget, timeValue / 8)
	org.hypotension = Approach(org.hypotension or 0, Clamp(Remap(org.bloodPressure, 55, 20, 0, 1), 0, 1), timeValue / 8)
	org.hypertension = Approach(org.hypertension or 0, Clamp(Remap(org.bloodPressure, 115, 155, 0, 1), 0, 1), timeValue / 20)

	org.fearadd = math.Clamp(org.fearadd, 0, 3)

	-- =====================================================================
	-- Z-SCAV: частота сердца по механике Heart rate из Casualties: Unknown
	--   база 70 уд/мин
	--   + адреналин (0.55 за единицу CU ~ 20 за единицу гейммода)
	--   + давление: тянет до +80 при низком и до -30 при высоком, у нормы эффект 0
	--   + фибрилляция: +1 за каждый %, +4 выше 75%, +30 выше 95%
	--   - опиаты (-0.2 за единицу), + ломка (+0.125 за единицу)
	--   + выносливость: +0.6 за каждый пункт ниже 100 (до +60 при нуле)
	--   +-0.5 за каждый градус выше/ниже 37
	--   + боль: +1 за единицу
	-- =====================================================================
	local CU = hg.organism.heartCU
	local st = org.stamina
	local stF = (istable(st) and isnumber(st[1]) and isnumber(st.max) and st.max > 0) and Clamp(st[1] / st.max, 0, 1) or 1
	local bp = org.bloodPressure or 90
	local fibPct = Clamp(org.arrhythmia or 0, 0, 1) * 100

	local heartbeat = CU.BASE
	heartbeat = heartbeat + CU.ADRENALINE * math.min(org.adrenaline or 0, 5)
	if bp < CU.BP_LOW then
		heartbeat = heartbeat + 80 * Clamp((CU.BP_LOW - bp) / 45, 0, 1)
	elseif bp > CU.BP_HIGH then
		heartbeat = heartbeat - 30 * Clamp((bp - CU.BP_HIGH) / 40, 0, 1)
	end
	heartbeat = heartbeat + fibPct + (fibPct > 75 and 4 or 0) + (fibPct > 95 and 30 or 0)
	heartbeat = heartbeat - CU.OPIATE * Clamp(org.analgesia or 0, 0, 3)
	heartbeat = heartbeat + CU.WITHDRAWAL * (org.remComedown or 0)
	heartbeat = heartbeat + 60 * (1 - stF)
	heartbeat = heartbeat + 0.5 * ((org.temperature or 37) - 37)
	heartbeat = heartbeat + math.max(org.pain or 0, 0)
	heartbeat = heartbeat + (org.remDisHR or 0) -- Z-SCAV: тахикардия от болезней (бешенство)
	-- немного от гейммода: страх и попытка самоубийства (старое)
	heartbeat = heartbeat + 15 * Clamp(org.fear or 0, 0, 1)
	-- нерегулярный ритм заметен на ЭКГ
	if fibPct > 15 and not org.fibrillation then heartbeat = heartbeat + math.Rand(-25, 35) * fibPct / 100 end
	if org.fibrillation then heartbeat = heartbeat + math.Rand(-40, 60) end
	heartbeat = math.max(heartbeat, 0)

	org.heartbeat = math.Approach(org.heartbeat, heartbeat, heartbeat > org.heartbeat and timeValue * 8 or timeValue * 4)

	local ischemia = Clamp(1 - (org.myocardialOxygen or 1), 0, 1)
	local stress = Clamp((org.heart or 0) * 0.9 + ischemia * 0.8 + (org.hypertension or 0) * 0.35 + (org.hypotension or 0) * 0.3 + Clamp(org.shock, 0, 80) / 180 + max(org.pain - 60, 0) / 220, 0, 2)

	-- ---------------------------------------------------------------------
	-- фибрилляция (org.arrhythmia 0..1 = 0..100%), как в CU:
	--   растёт 1%/с, пока есть причина (свыше 280 уд/мин - 4%/с), иначе падает 0.75%/с
	--   >15% аритмия, >50% желудочковая тахикардия (сама прогрессирует),
	--   >75% фибрилляция желудочков, 100% - сердце останавливается
	-- ---------------------------------------------------------------------
	local o2frac = (istable(org.o2) and org.o2.range and org.o2.range > 0) and Clamp(org.o2[1] / org.o2.range, 0, 1) or 1
	local bloodCfg = hg.organism.bloodHeart
	local floor = 0
	if org.blood < bloodCfg.ARRHYTHMIA then
		floor = Clamp(Remap(org.blood, bloodCfg.ARRHYTHMIA, bloodCfg.ARREST, bloodCfg.ARRHYTHMIA_MIN, 1), bloodCfg.ARRHYTHMIA_MIN, 1)
	end
	floor = math.max(floor, Clamp(stress * 0.42, 0, 0.6)) -- повреждённое/перегруженное сердце

	local rising = (org.heartbeat > 200)
		or bp < CU.FIB_BP
		or (org.temperature or 37) < 28.5
		or o2frac < 0.6
		or (org.thirst or 0) <= -74 and math.Rand(0, 1) < 0.0166 * timeValue -- водная интоксикация
		or (org.remComedown or 0) * 200 > 34                                  -- CU: смертельная ломка
		or (org.arrhythmia or 0) > 0.5 -- желудочковая тахикардия прогрессирует сама
	local arr = org.arrhythmia or 0
	if not org.heartstop then
		if rising then
			local otherCause = org.heartbeat > 200 or bp < CU.FIB_BP or (org.temperature or 37) < 28.5 or o2frac < 0.6
			local rate = 0.01                                          -- 1%/с
			if org.heartbeat > 280 then rate = 0.04                    -- 4%/с
			elseif arr > 0.5 and arr <= 0.75 and not otherCause then rate = 0.005 end -- тахикардия сама переходит в фибрилляцию медленнее
			arr = arr + timeValue * rate
		elseif arr > floor then
			arr = math.max(floor, arr - timeValue * 0.0075)
		end
		if arr < floor then arr = Approach(arr, floor, timeValue / bloodCfg.ARRHYTHMIA_RISE) end
		org.arrhythmia = Clamp(arr, 0, 1)

		if org.arrhythmia > 0.75 and not org.fibrillation then
			org.fibrillation = true
			org.fibrillationStart = CurTime()
		elseif org.arrhythmia <= 0.75 and org.fibrillation then
			org.fibrillation = false
		end
		-- 100% или пульс ниже 20 - остановка сердца
		if org.arrhythmia >= 0.999 or (org.alive and org.heartbeat < CU.ARREST_HR and heartbeat < CU.ARREST_HR) then
			org.heartstop = true
		end
	end

	if org.fibrillation then
		org.consciousness = math.min(org.consciousness, Clamp(org.bloodPressure / 55, 0, 1))
		org.o2[1] = max(org.o2[1] - timeValue * 1.8, 0)
		if org.bloodPressure < 8 then org.heartstop = true end
	end
	if org.hypertension > 0.35 then org.heartStrain = Clamp((org.heartStrain or 0) + timeValue * org.hypertension / 360, 0, 1) end
	if ischemia > 0.35 then org.heartStrain = Clamp((org.heartStrain or 0) + timeValue * ischemia / 260, 0, 1) end
	if ischemia > 0.45 and org.isPly and not org.otrub and (org.lastCardiacPain or 0) < CurTime() then
		org.lastCardiacPain = CurTime() + math.Rand(14, 24)
		org.painadd = org.painadd + math.Rand(4, 9) * ischemia
		org.shock = math.max(org.shock, 10 + ischemia * 22)
	end
	if org.hypotension > 0.2 then org.consciousness = math.min(org.consciousness, Clamp(Remap(org.bloodPressure, 20, 65, 0, 1), 0, 1)) end

	-- CU: адреналин (эпинефрин) в крови может сам завести сердце, но с фибрилляцией 50%
	if org.heartstop and org.alive and (org.adrenaline or 0) > 1 and (org.brain or 0) < 0.75 and (org.heart or 0) < 1
		and org.blood > hg.organism.bloodHeart.ARREST and math.Rand(0, 1) < hg.organism.heartCU.EPI_RESTART * timeValue then
		org.heartstop = false
		org.arrhythmia = 0.5
		org.heartbeat = 60
		org.pulse = math.max(org.pulse or 0, 30)
		org.bloodPressure = math.max(org.bloodPressure or 0, 40)
	end

	if org.heartstop then
		org.heartbeat = 0
		local arrestFallSpeed = defibGrace and 4 or 35
		org.bloodPressure = Approach(org.bloodPressure or 0, arrestPressure, timeValue * arrestFallSpeed)
		org.pulse = Approach(org.pulse or 0, arrestPressure, timeValue * arrestFallSpeed)
		org.fibrillation = false
		org.arrhythmia = 0
	end

	org.fear = math.Approach(org.fear, (org.otrub and 0 or (org.fearadd > 0 and 1 or -1)), org.otrub and timeValue * 0.5 or (org.fearadd > 0 and (org.fear < 0 and timeValue * 5 * org.fearadd or timeValue / 5 * org.fearadd) or (org.fear <= 0 and timeValue / 240 or timeValue / 50)))
	-- less time to start fearing, more time to become calm again
	-- if no fear, in 3 minutes become slightly talkative, so would say random phrases to calm themselves in a current situation
	local gainfear = hg.organism.should_gain_fear(org)
	org.fearadd = math.Approach(org.fearadd, 0, gainfear and timeValue or timeValue / 4.9) -- 15 seconds to stop fearing something and start to calm down
	org.fearadd = math.Approach(org.fearadd, 1, gainfear and timeValue / 5 or 0)
	
	if org.pulse < 10 or org.brain >= 0.75 then org.heartstop = true end -- Z-SCAV: мозг 75% (было 60%)
	-- REM: критическая кровопотеря - остановка сердца
	if org.alive and org.blood <= hg.organism.bloodHeart.ARREST then org.heartstop = true end
	if org.temperature < 28 or org.temperature > 42 then org.heartstop = true end
	if org.heartstop then
		org.fibrillation = false
		org.arrhythmia = 0
	end

	if org.temperature < 34 or org.temperature > 38 or org.blood < 4000 or org.pain > 20 then
		org.fear = math.max(org.fear, 0)
	end

	-- temperature
	local needed_temp = math.min(math.max(37 * (org.pulse / 45), 35), 36.7)
	local changeRate = timeValue / 60
	changeRate = changeRate * (org.temperature < needed_temp and math.Clamp(org.heatbuff / 60, 1, 2) or 1)
	if math.abs(org.tempchanging) < changeRate then
		org.temperature = math.Approach(org.temperature, needed_temp, changeRate)
	else
		org.needed_temp = needed_temp
	end
	
	if not org.heartstop then
		org.last_heartbeat = CurTime()
	end

	if org.heartstop then
		org.heartstoptime = org.heartstoptime or CurTime()
		if org.isPly then
			//org.owner:Notify("Голова кружится...", true, "heartstop", 10)
		end
	else
		if org.isPly then
			//org.owner:ResetNotification("heartstop")
		end
		org.heartstoptime = nil
	end

	if org.alive and org.heartstoptime and org.heartstoptime + 30 < CurTime() and (org.lastsoundtime or 0) < CurTime() and org.otrub then
		org.owner:EmitSound("breathing/agonalbreathing_"..math.random(13)..".wav", 60)
		--org.owner:EmitSound("breathing/agonalbreathing_"..math.random(13)..".wav", 50)
		
		org.lastsoundtime = CurTime() + math.random(25,35)
	end
end

--if org.heartstop then org.needotrub = true end --не совсем...
util.AddNetworkString("pulse")
function hg.organism.Pulse(owner, org, timeValue)
	local stamina = org.stamina
	if org.o2[1] > 1 and org.alive and org.heart < 1 and org.brain < 0.6 then
		--org.brain = max(org.brain - timeValue / 30, 0) --regen
	end--brain damage is usually permanent

	if owner:IsPlayer() and owner:Alive() then
		net.Start("pulse")
		net.Send(owner)
	end
end
