AddCSLuaFile()


local function AngleToRadians(angle)
	if isangle(angle) then
		return Vector(math.rad(angle.p), math.rad(angle.y), math.rad(angle.r))
	end

	return Vector(angle)
end

SWParams = {}
SWParams.__index = SWParams

SWEasyParams = {}
SWEasyParams.__index = SWEasyParams

SWEllipsoid = {}
SWEllipsoid.__index = SWEllipsoid

local SW_DISABLED_CENTER = Vector(499, 499, 499)
local SW_DISABLED_ANGLE = Angle()
local SW_DISABLED_SCALE = Vector(0.025, 0.025, 0.025)


local OFFSET_Z90 = Matrix()
OFFSET_Z90:SetAngles(Angle(0, 90, 0))
local OFFSET_Z90_INVERT = OFFSET_Z90:GetInverse()

function SWParams.new(
	shader,
	ellipsoids,
	deform_texture, project_texture, blood_range, litegore_compatibility
)
	local self = {}

	-- string
	self.shader = shader or 'VertexDeformationVertexLit'

	-- Array<SWEllipsoid>
	self.ellipsoids = ellipsoids or {}

	-- float
	self.blood_range = blood_range or 0.5

	-- string
	self.deform_texture = deform_texture or 'models/flesh'
	self.project_texture = project_texture or 'models/flesh'

	-- Bool
	self.litegore_compatibility = litegore_compatibility

	return self
end

function SWEasyParams.new(
	shader,
	ellipsoid,
	deform_texture, project_texture, blood_range, litegore_compatibility,
	boneid, slot
)
	local self = {}

	self.shader = shader
	self.ellipsoid = ellipsoid or {}
	self.deform_texture = deform_texture
	self.project_texture = project_texture
	self.blood_range = blood_range
	self.litegore_compatibility = litegore_compatibility
	self.boneid = boneid
	self.slot = slot

	return self
end

function SWEllipsoid.new(center, angle, scale)
	local self = {}

	-- Vector
	self.center = center or SW_DISABLED_CENTER
	self.scale = scale or SW_DISABLED_SCALE

	-- Angle
	self.angle = angle or SW_DISABLED_ANGLE

	return self
end

local SW_DISABLED_ELLIPSOID = SWEllipsoid.new(SW_DISABLED_CENTER, SW_DISABLED_ANGLE, SW_DISABLED_SCALE)

if CLIENT then
	local missingModuleDialog


	function SimpleWoundUIShowMissingModuleDialog()
		if IsValid(missingModuleDialog) then
			missingModuleDialog:Center()
			missingModuleDialog:MakePopup()
			return
		end

		local releaseURL = 'https://github.com/2016killer/gmod-simple-wound-v2/releases/latest'
		local frame = vgui.Create('DFrame')
		missingModuleDialog = frame

		frame:SetTitle(language.GetPhrase('#sw2.missing_module'))
		frame:SetSize(520, 190)
		frame:Center()
		frame:MakePopup()
		frame.OnRemove = function()
			missingModuleDialog = nil
		end

		local help = vgui.Create('DLabel', frame)
		help:Dock(TOP)
		help:DockMargin(12, 12, 12, 0)
		help:SetWrap(true)
		help:SetAutoStretchVertical(true)
		help:SetText(string.format(language.GetPhrase('sw2.missing_module_help'), releaseURL))

		local openRelease = vgui.Create('DButton', frame)
		openRelease:Dock(BOTTOM)
		openRelease:DockMargin(12, 8, 12, 12)
		openRelease:SetTall(32)
		openRelease:SetText(language.GetPhrase('sw2.open_release'))
		openRelease.DoClick = function()
			gui.OpenURL(releaseURL)
		end
	end

	local modulename_main = 'simple_wound'
	local modulename_x86_x64 = 'simple_wound_x86_x64'

	local hasMain = util.IsBinaryModuleInstalled(modulename_main)
	local hasX64 = util.IsBinaryModuleInstalled(modulename_x86_x64)
    if not hasMain and not hasX64 then
        ErrorNoHalt(string.format('[Simple Wound]: %s\n', language.GetPhrase('sw2.missing_module')))
        return
    end

	local toLoad = hasMain and modulename_main or modulename_x86_x64
	local success, err = pcall(function() require(toLoad) end)
	if not success and toLoad ~= modulename_x86_x64 and hasX64 then
		toLoad = modulename_x86_x64
		success, err = pcall(function() require(toLoad) end)
	end
	if not success then
		ErrorNoHalt(string.format('[Simple Wound]: %s\n', err))
		print('Only supported on:\n-- main branch 32-bit\n-- x86_x64 branch 32-bit\n-- x86_x64 branch 64-bit')
		return
	end
	print('[Simple Wound]: ' .. (toLoad == modulename_main and 'main' or 'x86_x64') .. ' module installed')

    SimpleWound = SimpleWound or {}
	SimpleWound.MaxWounds = 3
    SimpleWound.Version = '2.0.1'
    print('[Simple Wound]: LUA VERSION ' .. SimpleWound.Version)

    SimpleWound.MaterialsCache = {}


	SimpleWound.Shaders = {
		['VertexDeformation'] = {},
		['VertexDeformationVertexLit'] = {},
		['EllipsoidClip'] = {},
		['EllipsoidClipVertexLit'] = {}
	}

	local fleshMat = Material("models/flesh")
	local cv_fw, cv_fwe, cv_fdist
	local SW_KEY_CENTER, SW_KEY_ANGLE, SW_KEY_SCALE = {}, {}, {}
	for i = 1, 16 do
		SW_KEY_CENTER[i] = '$ellipsoid_center_' .. i
		SW_KEY_ANGLE[i] = '$ellipsoid_angle_' .. i
		SW_KEY_SCALE[i] = '$ellipsoid_scale_' .. i
	end
	local SW_DISABLED_ANGLE_RAD = AngleToRadians(SW_DISABLED_ANGLE)
	local fleshSphere
	local function GetFleshSphere()
		if fleshSphere then return fleshSphere end
		local verts = {}
		local stacks, slices = 10, 16
		local function vtx(phi, theta)
			local sp = math.sin(phi)
			local n = Vector(sp * math.cos(theta), sp * math.sin(theta), math.cos(phi))
			return {pos = n, normal = Vector(-n.x, -n.y, -n.z), u = theta / (2 * math.pi), v = phi / math.pi}
		end
		for i = 0, stacks - 1 do
			for j = 0, slices - 1 do
				local p0 = i / stacks * math.pi
				local p1 = (i + 1) / stacks * math.pi
				local t0 = j / slices * 2 * math.pi
				local t1 = (j + 1) / slices * 2 * math.pi
				local a, b, c, d = vtx(p0, t0), vtx(p0, t1), vtx(p1, t0), vtx(p1, t1)
				verts[#verts + 1] = a
				verts[#verts + 1] = c
				verts[#verts + 1] = b
				verts[#verts + 1] = b
				verts[#verts + 1] = c
				verts[#verts + 1] = d
			end
		end
		local m = Mesh()
		mesh.Begin(m, MATERIAL_TRIANGLES, #verts / 3)
		for i = 1, #verts do
			mesh.Position(verts[i].pos)
			mesh.Normal(verts[i].normal)
			mesh.TexCoord(0, verts[i].u, verts[i].v)
			mesh.AdvanceVertex()
		end
		mesh.End()
		fleshSphere = m
		return fleshSphere
	end
	hook.Add("Think", "SW2_FleshSphereWarmup", function()
		hook.Remove("Think", "SW2_FleshSphereWarmup")
		pcall(GetFleshSphere)
	end)
	local BuildOverrideMaterial
	local function SkipFaceMaterial(matpath)
		local filename = string.lower(string.GetFileFromFilename(matpath) or matpath)
		return string.find(filename, 'eye', 1, true) ~= nil
			or string.find(filename, 'teeth', 1, true) ~= nil
			or string.find(filename, 'mouth', 1, true) ~= nil
	end
	local function WoundRender(self)
		if self:GetNoDraw() then return end
		if self:GetRenderMode() ~= RENDERMODE_NORMAL and self:GetColor().a <= 0 then return end
		local materials = self.sw_materials
		local params = self.sw_params
		local matlist = self.sw_matlist
		if not matlist then
			matlist = self:GetMaterials()
			self.sw_matlist = matlist
		end
		local subs = self.sw_submat_cache
		if not subs then
			subs = {}
			self.sw_submat_cache = subs
			for i, _ in pairs(matlist) do
				subs[i] = self:GetSubMaterial(i - 1) or ''
			end
		end
		local now = CurTime()
		local nextscan = self.sw_submat_scan
		if not nextscan or now >= nextscan then
			self.sw_submat_scan = now + 0.25
			for i, matpath in pairs(matlist) do
				local cur = self:GetSubMaterial(i - 1) or ''
				if subs[i] ~= cur then
					subs[i] = cur
					local used = cur ~= '' and cur or matpath
					if SkipFaceMaterial(used) then
						materials[i] = nil
					else
						materials[i] = BuildOverrideMaterial(used, params)
					end
				end
			end
		end

		local hi = math.min(math.max(params.maxSlot or 0, SimpleWound.MaxWounds or 3), 16)
		local ells = params.ellipsoids
		local kc, ka, ks = SW_KEY_CENTER, SW_KEY_ANGLE, SW_KEY_SCALE
		for j, matvar in pairs(materials) do
			for slot = 1, hi do
				local e = ells[slot]
				if not e then
					matvar:SetVector(kc[slot], SW_DISABLED_CENTER)
					matvar:SetVector(ka[slot], SW_DISABLED_ANGLE_RAD)
					matvar:SetVector(ks[slot], SW_DISABLED_SCALE)
				else
					if not e.rad then e.rad = AngleToRadians(e.angle) end
					matvar:SetVector(kc[slot], e.center)
					matvar:SetVector(ka[slot], e.rad)
					matvar:SetVector(ks[slot], e.scale)
				end
			end
			matvar:SetFloat('$blood_range', params.blood_range)
			render.MaterialOverrideByIndex(j - 1, matvar)
		end
			self:DrawModel()
		for j, _ in pairs(materials) do
			render.MaterialOverrideByIndex(j - 1)
		end
		local fleshNear = true
		if not cv_fdist then cv_fdist = GetConVar("gib_l4d2_swcut_fleshmaxdist") end
		if cv_fdist then
			local fd = cv_fdist:GetFloat()
			if fd > 0 then
				fleshNear = EyePos():DistToSqr(self:GetPos()) <= fd * fd
			end
		end
		if not cv_fw then cv_fw = GetConVar("gib_l4d2_swcut_fleshwalls") end
		if fleshNear and (not cv_fw or cv_fw:GetBool()) and params.ellipsoids and next(params.ellipsoids) then
			render.ModelMaterialOverride(fleshMat)
			render.CullMode(MATERIAL_CULLMODE_CW)
			self:DrawModel()
			render.CullMode(MATERIAL_CULLMODE_CCW)
			render.ModelMaterialOverride()
		end
		if not cv_fwe then cv_fwe = GetConVar("gib_l4d2_swcut_fleshellipsoid") end
		if fleshNear and cv_fwe and cv_fwe:GetBool() and params.ellipsoids and next(params.ellipsoids) then
			local multi = self.sw_multi
			if multi == nil then
				multi = self:GetBoneCount() > 1
				self.sw_multi = multi
			end
			local ZI = SimpleWound.OFFSET_Z90
			local bindEnt = self.sw_bindent
			if bindEnt == nil then
				bindEnt = (SimpleWound.GetClientModel and SimpleWound.GetClientModel(self:GetModel())) or false
				self.sw_bindent = bindEnt
			end
			local W = self:GetWorldTransformMatrix()
			local sphere = GetFleshSphere()
			local cutBones = self.sw_cut_bones
			local fb = self.sw_fleshbones
			if not fb then
				fb = {}
				self.sw_fleshbones = fb
			end
			for slot, e in pairs(params.ellipsoids) do
				if e.center and e.scale and not e.nosphere then
					local Mm = Matrix()
					Mm:SetTranslation(e.center)
					Mm:SetAngles(e.angle or Angle())
					Mm:SetScale(e.scale)
					if multi and ZI then
						Mm = ZI * Mm
					end
					local boneName = cutBones and cutBones[slot]
					local rec = fb[slot]
					if not rec or rec.name ~= boneName then
						rec = {name = boneName, idx = false}
						if boneName then
							local b = self:LookupBone(boneName)
							if b and b >= 0 then rec.idx = b end
						end
						if not rec.idx and bindEnt then
							local c = Mm:GetTranslation()
							local bestD
							for b = 0, self:GetBoneCount() - 1 do
								local bm = SimpleWound.GetBoneMatrixSafe(bindEnt, b)
								if bm then
									local d = bm:GetTranslation():DistToSqr(c)
									if not bestD or d < bestD then
										bestD = d
										rec.idx = b
									end
								end
							end
						end
						fb[slot] = rec
					end
					local boneIdx = rec.idx
					local world
					if boneIdx and bindEnt then
						local cur = self:GetBoneMatrix(boneIdx)
						local bindinv = rec.bindinv
						if bindinv == nil then
							local bm = SimpleWound.GetBoneMatrixSafe(bindEnt, boneIdx)
							bindinv = bm and bm:GetInverse() or false
							rec.bindinv = bindinv
						end
						if cur and bindinv then
							world = W * (cur * bindinv) * Mm
						end
					end
					if not world then
						world = W * Mm
					end
					render.SetMaterial(fleshMat)
					render.CullMode(MATERIAL_CULLMODE_CW)
					cam.PushModelMatrix(world)
					sphere:Draw()
					cam.PopModelMatrix()
					render.CullMode(MATERIAL_CULLMODE_CCW)
				end
			end
		end
	end


	local function WoundRender_Compatible_LiteGore(ent)
		if ent:GetNoDraw() then return end
		if ent:GetRenderMode() ~= RENDERMODE_NORMAL and ent:GetColor().a <= 0 then return end

		if not IsValid(ent.goreModel) then
			WoundRender(ent)
			return
		end

		if not ent.LiteGibWounds then
			WoundRender(ent)
			return
		end

		if halo.RenderedEntity() == ent then
			WoundRender(ent)
			return
		end

		if #ent.LiteGibWounds == 0 then
			WoundRender(ent)
			return
		end

		--start off by clearing stencil
		render.SetStencilWriteMask(0xFF)
		render.SetStencilTestMask(0xFF)
		render.SetStencilReferenceValue(0)
		render.SetStencilCompareFunction(STENCIL_ALWAYS)
		render.SetStencilPassOperation(STENCIL_KEEP)
		render.SetStencilFailOperation(STENCIL_KEEP)
		render.SetStencilZFailOperation(STENCIL_KEEP)
		render.ClearStencil()
		--first we write the entity to the stencil buffer with value 1
		--writing to the depth buffer but not color allows us to clip the wound with the model
		render.SetStencilEnable(true)
		render.SetStencilReferenceValue(1)
		render.SetStencilCompareFunction(STENCIL_ALWAYS)
		render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
		render.SetStencilFailOperation(STENCILOPERATION_REPLACE)
		render.SetStencilZFailOperation(STENCIL_KEEP)
		render.CullMode(MATERIAL_CULLMODE_CCW)
		render.OverrideColorWriteEnable(true, false)
		ent:DrawModel()
		render.OverrideColorWriteEnable(false, false)
		--now we write the wound model, which increments the see-through areas to stencil value 2
		render.SetStencilCompareFunction(STENCIL_EQUAL)
		render.SetStencilPassOperation(STENCIL_INCR)
		render.SetStencilFailOperation(STENCIL_KEEP)
		render.SetStencilZFailOperation(STENCIL_KEEP)
		render.SetBlend(0)
		render.OverrideDepthEnable(true, false)

		for _, v in ipairs(ent.LiteGibWounds) do
			if IsValid(v.model) and v.bone and v.pos and v.ang then
				local mat = ent:GetBoneMatrix(v.bone)

				if mat then
					local bpos, bang
					bpos = mat:GetTranslation()
					bang = mat:GetAngles()
					local pos, ang = LocalToWorld(v.pos, v.ang, bpos, bang)
					v.model:SetupBones()
					v.model:SetRenderOrigin(pos)
					v.model:SetRenderAngles(ang)
					v.model:DrawModel()
				end
			end
		end

		render.OverrideDepthEnable(false, false)
		render.SetBlend(1)
		--now we clear the depth of the wound area
		render.SetStencilPassOperation(STENCIL_KEEP)
		render.SetStencilFailOperation(STENCIL_KEEP)
		render.SetStencilZFailOperation(STENCIL_KEEP)
		render.SetStencilReferenceValue(0)
		render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
		render.OverrideColorWriteEnable(true, false)
		render.ClearBuffersObeyStencil(0, 0, 0, 0, true)
		render.OverrideColorWriteEnable(false, false)
		--now we write, in order, the fleshy interior of the model, and the wound model
		render.SetStencilReferenceValue(2)
		render.SetStencilCompareFunction(STENCIL_EQUAL)
		render.ModelMaterialOverride(fleshMat)
		render.CullMode(MATERIAL_CULLMODE_CW)
		ent:DrawModel()
		render.OverrideDepthEnable(true, false)
		render.CullMode(MATERIAL_CULLMODE_CCW)
		ent.goreModel:SetupBones()
		ent.goreModel:DrawModel()
		render.OverrideDepthEnable(false, false)
		render.ModelMaterialOverride()
		render.SetStencilReferenceValue(2)
		render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
		WoundRender(ent)
		render.ClearStencil()
		render.SetStencilEnable(false)
	end


	local function IsVertexLitMaterial(material)
		local shader = string.lower(material:GetShader() or '')
		return string.find(shader, 'vertexlit', 1, true) == 1
	end

	local function IsRemovedMaterialParameter(key)
		local lowerKey = string.lower(key)
		return string.find(lowerKey, 'envmap', 1, true) ~= nil or
			string.sub(lowerKey, 1, 6) == '$flags'
	end

	local SerializeMaterialTable
	local function SerializeMaterialValue(value)
		local valueType = type(value)

		if valueType == 'table' then
			return SerializeMaterialTable(value)
		end

		if valueType == 'userdata' then
			local ok, valueTable = pcall(function()
				return value:ToTable()
			end)
			if ok and type(valueTable) == 'table' then
				return SerializeMaterialTable(valueTable)
			end
		end

		return valueType .. ':' .. tostring(value)
	end

	SerializeMaterialTable = function(tbl)
		local keys = {}
		for key in pairs(tbl) do
			keys[#keys + 1] = key
		end

		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)

		local parts = {}
		for _, key in ipairs(keys) do
			parts[#parts + 1] = string.format(
				'%s=%s',
				tostring(key),
				SerializeMaterialValue(tbl[key])
			)
		end

		return '{' .. table.concat(parts, ';') .. '}'
	end

	BuildOverrideMaterial = function(matpathUsed, swparams)
		local sourceMaterial = Material(matpathUsed)
		if not IsVertexLitMaterial(sourceMaterial) then return nil end
		local baseTexture = sourceMaterial:GetTexture('$basetexture')
		if not baseTexture then return nil end
		local deform_texture = swparams.deform_texture or 'models/flesh'
		local project_texture = swparams.project_texture or 'models/flesh'
		local materialParameters = {}
		local matrixParameters = {}
		local sourceKeyValues = sourceMaterial:GetKeyValues() or {}
		for key, value in pairs(sourceKeyValues) do
			if type(value) ~= 'table' and not IsRemovedMaterialParameter(key) then
				materialParameters[key] = value
			end
		end
		local proxies = sourceKeyValues['Proxies'] or sourceKeyValues['proxies']
		if type(proxies) == 'table' then
			materialParameters['Proxies'] = proxies
		end
		for _, key in ipairs({'$basetexture', '$bumpmap', '$phongexponenttexture'}) do
			if sourceKeyValues[key] ~= nil then
				local texture = sourceMaterial:GetTexture(key)
				if texture then
					materialParameters[key] = texture:GetName()
				end
			end
		end
		for _, key in ipairs({'$basetexturetransform', '$bumptransform'}) do
			local ok, matrix = pcall(sourceMaterial.GetMatrix, sourceMaterial, key)
			if ok and matrix then
				matrixParameters[key] = matrix
			end
		end
		materialParameters['$deform_texture'] = deform_texture
		materialParameters['$project_texture'] = project_texture
		local cacheParameters = {
			shader = swparams.shader,
			material = materialParameters,
			matrix = matrixParameters
		}
		local matname = string.format('sw2_wound_%08x', util.CRC(SerializeMaterialTable(cacheParameters)))
		local matcache = SimpleWound.MaterialsCache[matname]
		if matcache then return matcache end
		local matvar = CreateMaterial(matname, swparams.shader, materialParameters)
		for key, matrix in pairs(matrixParameters) do
			pcall(matvar.SetMatrix, matvar, key, matrix)
		end
		SimpleWound.MaterialsCache[matname] = matvar
		return matvar
	end

	SimpleWound.ApplyWound = function(ent, swparams)
		if not SimpleWound.Shaders[swparams.shader] then
			ErrorNoHalt(string.format('[Simple Wound]: Unknown shader "%s"\n', swparams.shader))
			return
		end

        ent.sw_params = swparams
		ent.sw_materials = {}
		for i, matpath in pairs(ent:GetMaterials()) do
			local idx = i - 1
			local subMaterial = ent:GetSubMaterial(idx)
			local matpathUsed = subMaterial == '' and matpath or subMaterial
			if not SkipFaceMaterial(matpathUsed) then
				local matvar = BuildOverrideMaterial(matpathUsed, swparams)
				if matvar then
					ent.sw_materials[i] = matvar
				end
			end
		end

		-- Z-SCAV: игроков и рэгдоллы рисует Homigrad (hg.renderOverride: одежда, аксессуары, броня).
		-- Им свой RenderOverride не ставим - раны рисуются изнутри hg.renderOverride
		-- через SimpleWound.DrawWithParams, чтобы не пропадала внешность.
		if SimpleWound.HomigradManaged(ent) then return end

		local litegore_compatibility = swparams.litegore_compatibility or 0
		ent.RenderOverride =
			litegore_compatibility == 1 and WoundRender_Compatible_LiteGore or WoundRender
    end

	-- Z-SCAV: интеграция с Homigrad / Z-City
	function SimpleWound.HomigradManaged(ent)
		if not hg or not hg.renderOverride or not IsValid(ent) then return false end
		return ent:IsPlayer() or ent:GetClass() == "prop_ragdoll"
	end

	-- нарисовать ent с ранами из params (params могут принадлежать игроку, а рисуется его рэгдолл)
	function SimpleWound.DrawWithParams(ent, params)
		if not params or not params.ellipsoids or not next(params.ellipsoids) then
			ent:DrawModel()
			return
		end
		if ent.sw_params ~= params or not ent.sw_materials then
			ent.sw_params = params
			ent.sw_materials = {}
			ent.sw_matlist = nil
			ent.sw_submat_cache = nil
			ent.sw_submat_scan = nil
			ent.sw_fleshbones = nil
			for i, matpath in pairs(ent:GetMaterials()) do
				local sub = ent:GetSubMaterial(i - 1)
				local used = (sub == nil or sub == '') and matpath or sub
				if not SkipFaceMaterial(used) then
					local matvar = BuildOverrideMaterial(used, params)
					if matvar then ent.sw_materials[i] = matvar end
				end
			end
		end
		local ok, err = pcall(WoundRender, ent)
		if not ok then
			ErrorNoHalt('[Simple Wound]: ' .. tostring(err) .. '\n')
			ent:DrawModel()
		end
	end

	SimpleWound.ApplyWoundEasyEx = function(ent, easyparams)
		if not IsValid(ent) then return false end
		local s = math.floor(tonumber(easyparams.slot) or 0)
		local p = ent.sw_params
		if s < 1 or (p and p.ellipsoids and p.ellipsoids[s]) then
			s = SimpleWound.AllocWoundSlot(ent)
		end
		easyparams.slot = s
		ent.sw_cut_bones = ent.sw_cut_bones or {}
		ent.sw_cut_bones[s] = easyparams.boneid and ent:GetBoneName(easyparams.boneid) or nil
		if ent.sw_fleshbones then ent.sw_fleshbones[s] = nil end
		SimpleWound.ApplyWoundEasy(ent, easyparams, easyparams.coordinate)
		return true
	end

	net.Receive('sw_apply_ex', function()
		local easyparams = net.ReadTable()
		local ent = net.ReadEntity()
		if IsValid(ent) then
			SimpleWound.ApplyWoundEasyEx(ent, easyparams)
		end
	end)

	net.Receive('sw_clear_slot', function()
		local ent = net.ReadEntity()
		local slot = net.ReadUInt(16)
		if not IsValid(ent) then return end
		if ent.sw_params and ent.sw_params.ellipsoids then
			ent.sw_params.ellipsoids[slot] = nil
		end
		if ent.sw_cut_bones then ent.sw_cut_bones[slot] = nil end
		if ent.sw_cut_models then ent.sw_cut_models[slot] = nil end
		if ent.sw_fleshbones then ent.sw_fleshbones[slot] = nil end
	end)

	net.Receive('sw_apply', function()
		local swparams = net.ReadTable()
		local ent = net.ReadEntity()

		if IsValid(ent) then
			SimpleWound.ApplyWound(ent, swparams)
		end
    end)

	SimpleWound.ApplyWoundEasy = function(ent, easyparams, coordinate)
		if not IsValid(ent) then
			return
		end

		local shader = easyparams.shader
		local ellipsoid = easyparams.ellipsoid
		local deform_texture = easyparams.deform_texture
		local project_texture = easyparams.project_texture
		local blood_range = easyparams.blood_range
		local litegore_compatibility = easyparams.litegore_compatibility
		local boneid = easyparams.boneid
		local slot = easyparams.slot

		local modelent = SimpleWound.GetClientModel(ent:GetModel())
		local bindBoneMatrix = SimpleWound.GetBoneMatrixSafe(modelent, boneid)

		local boneLocalTransform = Matrix()

		boneLocalTransform:SetTranslation(ellipsoid.center)
		boneLocalTransform:SetAngles(ellipsoid.angle)
		boneLocalTransform:SetScale(ellipsoid.scale)

		-- Convert the hit bone's local space back to bind-pose model space.
		local is_z90
		if coordinate == nil then
			is_z90 = ent:GetBoneCount() > 1
		elseif coordinate == 'z90' then
			is_z90 = true
		elseif coordinate == 'norm' then
			is_z90 = false
		else
			print('UNKNOWN COORDINATE', coordinate)
		end

		local modelSpaceTransform = is_z90 and (OFFSET_Z90_INVERT * bindBoneMatrix * boneLocalTransform) or (bindBoneMatrix * boneLocalTransform)
		local modelSpaceCenter = modelSpaceTransform:GetTranslation()
		local modelSpaceAngle = modelSpaceTransform:GetAngles()
		local modelSpaceScale = modelSpaceTransform:GetScale()

		shader = shader or 'VertexDeformationVertexLit'
		slot = math.floor(tonumber(slot) or 1)
		slot = ((slot - 1) % SimpleWound.MaxWounds) + 1

		local swparams = ent.sw_params
		if not swparams then
			swparams = SWParams.new(
				shader,
				{},
				deform_texture, project_texture, blood_range, litegore_compatibility
			)
		end

		swparams.shader = shader
		swparams.deform_texture = deform_texture
		swparams.project_texture = project_texture
		swparams.blood_range = blood_range or 0.5
		swparams.litegore_compatibility = litegore_compatibility
		swparams.maxSlot = math.max(swparams.maxSlot or 0, slot)
		swparams.ellipsoids[slot] = SWEllipsoid.new(modelSpaceCenter, modelSpaceAngle, modelSpaceScale)
		if ellipsoid.nosphere then
			swparams.ellipsoids[slot].nosphere = true
		end

		SimpleWound.ApplyWound(ent, swparams)
	end


	net.Receive('sw_apply_easy', function()
		local easyparams = net.ReadTable()
		local ent = net.ReadEntity()

		if IsValid(ent) then
			SimpleWound.ApplyWoundEasy(ent, easyparams)
		end
    end)

	concommand.Add('cl_sw2_breentest', function(ply, cmd, args)
		local entities = ents.FindInSphere(ply:GetPos(), 2000)

		for _, ent in pairs(entities) do
			if ent:GetModel() == 'models/breen.mdl' then

			local ellipsoid = Matrix()
			ellipsoid:SetTranslation(Vector(0, -12, 50 + math.random(-10, 10)))
			ellipsoid:SetScale(Vector(math.random(5, 10), 15, math.random(5, 10)))

			SimpleWound.ApplyWound(
				ent, 
				SWParams.new(
					'VertexDeformationVertexLit',
					{
						SWEllipsoid.new(Vector(0, -12, 70 + math.random(-10, 10)), Angle(), Vector(math.random(5, 10), 15, math.random(5, 10))),
						SWEllipsoid.new(Vector(0, -12, 50 + math.random(-10, 10)), Angle(), Vector(math.random(5, 10), 15, math.random(5, 10))),
						SWEllipsoid.new(Vector(0, -12, 30 + math.random(-10, 10)), Angle(), Vector(math.random(5, 10), 15, math.random(5, 10)))
					},
					'models/flesh', 'models/flesh', 0.5, false
				)
			)
			end
		end
    end)

	SimpleWound.ClientModels = {}

	local ClientModels = SimpleWound.ClientModels

	SimpleWound.GetClientModel = function(model)
		local modelent = ClientModels[model]
		if not IsValid(modelent) then
			modelent = ClientsideModel(model)
			modelent:SetNoDraw(true)
			ClientModels[model] = modelent
		end
		return modelent
	end

	SimpleWound.GetFreeWoundSlot = function(ent)
		return SimpleWound.AllocWoundSlot(ent)
	end

	SimpleWound.Reset = function(ent)
		ent.RenderOverride = nil
		ent.sw_params = nil
		ent.sw_materials = nil
		ent.sw_cut_bones = nil
		ent.sw_cut_models = nil
		ent.sw_fleshbones = nil
		ent.sw_matlist = nil
		ent.sw_submat_cache = nil
	end

	net.Receive('sw_reset', function()
		local ent = net.ReadEntity()
		if IsValid(ent) then
			SimpleWound.Reset(ent)
		end
	end)
end


if SERVER then
	util.AddNetworkString('sw_apply_easy')
	util.AddNetworkString('sw_apply')
	util.AddNetworkString('sw_apply_ex')
	util.AddNetworkString('sw_clear_slot')
	util.AddNetworkString('sw_reset')

    SimpleWound = SimpleWound or {}
	SimpleWound.MaxWounds = 3
    SimpleWound.Version = '2.0.1'

	SimpleWound.ApplyWound = function(ent, swparams)
		ent.sw_params = swparams

		net.Start('sw_apply')
			net.WriteTable(swparams)
			net.WriteEntity(ent)
		net.Broadcast()
    end

	local COPY_MODIFIER = 'SimpleWound2'
	local SerializeToolWounds

	-- ent.sw_tool_wounds = {
	--   shader, deform_texture, project_texture, blood_range,
	--   litegore_compatibility, coordinate,
	--   slots = {
	--     [slot] = { boneid, center = Vector(), angle = Angle(), scale = Vector() }
	--   }
	-- }
	SimpleWound.ApplyWoundEasy = function(ent, easyparams)
		if not IsValid(ent) then
			return
		end

		easyparams.slot = math.floor(tonumber(easyparams.slot) or 1)
		easyparams.slot = ((easyparams.slot - 1) % SimpleWound.MaxWounds) + 1
		easyparams.shader = easyparams.shader or 'VertexDeformationVertexLit'

		if easyparams.persistent then
			local toolWounds = ent.sw_tool_wounds
			if not istable(toolWounds) or not istable(toolWounds.slots) then
				toolWounds = { slots = {} }
				ent.sw_tool_wounds = toolWounds
			end

			toolWounds.shader = easyparams.shader
			toolWounds.deform_texture = easyparams.deform_texture
			toolWounds.project_texture = easyparams.project_texture
			toolWounds.blood_range = easyparams.blood_range
			toolWounds.litegore_compatibility = easyparams.litegore_compatibility
			toolWounds.coordinate = easyparams.coordinate
			toolWounds.slots[easyparams.slot] = {
				boneid = easyparams.boneid,
				center = easyparams.ellipsoid.center,
				angle = easyparams.ellipsoid.angle,
				scale = easyparams.ellipsoid.scale
			}

			duplicator.StoreEntityModifier(ent, COPY_MODIFIER, SerializeToolWounds(ent))
		end

		net.Start('sw_apply_easy')
			net.WriteTable(easyparams)
			net.WriteEntity(ent)
		net.Broadcast()
	end

	SimpleWound.ApplyWoundEasyEx = function(ent, easyparams)
		if not IsValid(ent) then return false end
		easyparams.slot = SimpleWound.AllocWoundSlot(ent)
		easyparams.persistent = nil
		ent.sw_runtime = ent.sw_runtime or {}
		ent.sw_runtime[easyparams.slot] = table.Copy(easyparams)
		net.Start('sw_apply_ex')
			net.WriteTable(easyparams)
			net.WriteEntity(ent)
		net.Broadcast()
		return true
	end

	SimpleWound.ClearWoundSlot = function(ent, slot)
		if not IsValid(ent) then return end
		slot = math.floor(tonumber(slot) or 0)
		if slot < 1 then return end
		if ent.sw_runtime then ent.sw_runtime[slot] = nil end
		net.Start('sw_clear_slot')
			net.WriteEntity(ent)
			net.WriteUInt(slot, 16)
		net.Broadcast()
	end

	SimpleWound.TransferWoundsRuntime = function(from, to)
		if not IsValid(from) or not IsValid(to) or from == to then return end
		if not istable(from.sw_runtime) then return end
		local params = from.sw_runtime
		from.sw_runtime = nil
		for slot, ep in pairs(params) do
			SimpleWound.ApplyWoundEasyEx(to, table.Copy(ep))
		end
	end

	SimpleWound.Reset = function(ent)
		ent.sw_params = nil
		ent.sw_tool_wounds = nil
		ent.sw_runtime = nil
		duplicator.StoreEntityModifier(ent, COPY_MODIFIER, { slots = {} })

		net.Start('sw_reset')
			net.WriteEntity(ent)
		net.Broadcast()
	end

	SerializeToolWounds = function(ent)
		local toolWounds = ent.sw_tool_wounds
		if not istable(toolWounds) or not istable(toolWounds.slots) then
			return
		end

		local slots = {}
		for slot = 1, SimpleWound.MaxWounds do
			local wound = toolWounds.slots[slot]
			if wound then
				local center = wound.center or Vector()
				local angle = wound.angle or Angle()
				local scale = wound.scale or Vector()

				slots[#slots + 1] = {
					slot = slot,
					boneid = wound.boneid,
					center = { center.x, center.y, center.z },
					angle = { angle.p, angle.y, angle.r },
					scale = { scale.x, scale.y, scale.z }
				}
			end
		end

		if #slots == 0 then
			return
		end

		return {
			shader = toolWounds.shader,
			deform_texture = toolWounds.deform_texture,
			project_texture = toolWounds.project_texture,
			blood_range = toolWounds.blood_range,
			litegore_compatibility = toolWounds.litegore_compatibility,
			coordinate = toolWounds.coordinate,
			slots = slots
		}
	end

	local function RestoreToolWounds(ent, data)
		if not IsValid(ent) or not istable(data) or not istable(data.slots) then
			return
		end

		for _, slotData in ipairs(data.slots) do
			local center = slotData.center or {}
			local angle = slotData.angle or {}
			local scale = slotData.scale or {}

			local easyparams = SWEasyParams.new(
				data.shader,
				SWEllipsoid.new(
					Vector(center[1] or 0, center[2] or 0, center[3] or 0),
					Angle(angle[1] or 0, angle[2] or 0, angle[3] or 0),
					Vector(scale[1] or 0, scale[2] or 0, scale[3] or 0)
				),
				data.deform_texture,
				data.project_texture,
				data.blood_range,
				data.litegore_compatibility,
				slotData.boneid,
				slotData.slot
			)
			easyparams.persistent = true
			easyparams.coordinate = data.coordinate

			SimpleWound.ApplyWoundEasy(ent, easyparams)
		end
	end

	hook.Add('PostEntityCopy', 'SimpleWound2', function(ent)
		local copyData = SerializeToolWounds(ent)
		if copyData then
			duplicator.StoreEntityModifier(ent, COPY_MODIFIER, copyData)
		end
	end)

	duplicator.RegisterEntityModifier(COPY_MODIFIER, function(ply, ent, data)
		if IsValid(ent) then
			RestoreToolWounds(ent, data)
		end
	end)
end


SimpleWound.DISABLED_CENTER = SW_DISABLED_CENTER
SimpleWound.DISABLED_ANGLE = SW_DISABLED_ANGLE
SimpleWound.DISABLED_SCALE = SW_DISABLED_SCALE
SimpleWound.OFFSET_Z90 = OFFSET_Z90
SimpleWound.OFFSET_Z90_INVERT = OFFSET_Z90_INVERT
SimpleWound.DISABLED_ELLIPSOID = SW_DISABLED_ELLIPSOID


function SimpleWound.AllocWoundSlot(ent)
	local max = SimpleWound.MaxWounds or 3
	for i = 1, max do
		local taken = false
		local p = ent.sw_params
		if p and p.ellipsoids and p.ellipsoids[i] then taken = true end
		local rt = ent.sw_runtime
		if not taken and rt and rt[i] then taken = true end
		if not taken and ent.sw_cut_slots and ent.sw_cut_slots[i] then taken = true end
		if not taken then return i end
	end
	ent.sw_alloc_n = (ent.sw_alloc_n or 0) + 1
	return ((ent.sw_alloc_n - 1) % max) + 1
end

SimpleWound.GetBoneMatrixSafe = function(ent, boneid)
	if boneid == -1 then
		return ent:GetWorldTransformMatrix()
	else

		if CLIENT then 
			ent:SetupBones()
		end

		local bonematrix = ent:GetBoneMatrix(boneid)

		if bonematrix then
			return bonematrix
		else
			local modelname = isfunction(ent.GetModel) and ent:GetModel() or 'unknown model'
			local bonename = isfunction(ent.GetBoneName) and ent:GetBoneName(boneid) or 'unknown bone'

			print(
				string.format(
					'%s: %s, %s, %s',
					language.GetPhrase('sw2.err.unknowboneid'),
					boneid,
					modelname,
					bonename
				)
			)

			return ent:GetWorldTransformMatrix()
		end
	end
end
