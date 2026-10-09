AddCSLuaFile()


local function PlayPhys(ent, key, tbl)
	-- 逐骨骼设置位置
	local physdata = tbl or {}

	if not istable(physdata[key]) then 
		return
	end
	
	for _, v in pairs(physdata[key]) do
		local phys = v.phys
		phys:SetPos(v.pos)
		phys:SetAngles(v.ang)
		phys:EnableMotion(v.moveable)
		phys:Wake()
	end
end


local function PrintSWParams(ent)
	-- 打印实体的伤口材质参数
	tbl_text = ent.sw_params == nil and 'nil' or util.TableToJSON(ent.sw_params, true)
	text = string.format('-----------------\n%s\n%s\n-----------------\n', ent:GetModel(), tbl_text)
  	LocalPlayer():ChatPrint(text)
end


local function BindPose(ent)
	-- 改变布娃娃的动作为默认姿势
	if ent:IsRagdoll() then
		local temp = ents.Create('prop_ragdoll')
		temp:SetModel(ent:GetModel())
		temp:SetPos(ent:GetPos())
		temp:Spawn()
		
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local tempPhys = temp:GetPhysicsObjectNum(i)
			local phys = ent:GetPhysicsObjectNum(i)
			if IsValid(phys) then
				phys:EnableMotion(false)
				phys:SetPos(tempPhys:GetPos())
				phys:SetAngles(tempPhys:GetAngles())
				phys:Wake()
			end
		end

		temp:Remove()
	else
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then
			phys:EnableMotion(false)
			phys:SetAngles(Angle())
			phys:Wake()
		end
	end
end

local function RecordPhys(ent, key, tbl)
	-- 逐骨骼记录位置
	local physdata = tbl or {}
	physdata[key] = {}

	if ent:IsRagdoll() then
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local phys = ent:GetPhysicsObjectNum(i)
			if IsValid(phys) then
				table.insert(
					physdata[key], 
					{
						phys = phys,
						pos = phys:GetPos(),
						ang = phys:GetAngles(),
						moveable = phys:IsMoveable(),
					}
				)
			end
		end
	else
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then
			table.insert(
				physdata[key], 
				{
					phys = phys,
					pos = phys:GetPos(),
					ang = phys:GetAngles(),
					moveable = phys:IsMoveable(),
				}
			)
		end
	end

	return physdata
end



local zerovec = Vector()
local zeroang = Angle()
local unitx = Vector(1, 0, 0)
local unity = Vector(0, 1, 0)
local unitz = Vector(0, 0, 1)


local SEGMENTS = 32
local unitCircle = {}
for i = 0, SEGMENTS do
    local theta = math.rad(i / SEGMENTS * 360)
    unitCircle[i] = Vector(math.cos(theta), math.sin(theta), 0)
end

local function DrawEllipsoidRing(transform)
    cam.PushModelMatrix(transform)
        render.SetColorMaterial()

        -- XY 平面上的单位圆（法线是局部 Z）
        local prev = nil
        for i = 0, SEGMENTS do
            local p = unitCircle[i]
            if prev then
                render.DrawLine(prev, p, Color(255, 80, 80, 255), false)
            end
            prev = p
        end

        -- XZ 平面上的单位圆（法线是局部 Y）
        prev = nil
        for i = 0, SEGMENTS do
            local p = Vector(unitCircle[i].x, 0, unitCircle[i].y)
            if prev then
                render.DrawLine(prev, p, Color(80, 255, 80, 255), false)
            end
            prev = p
        end
    cam.PopModelMatrix()
end

local function DrawEllipsoid(transform, step)
	cam.PushModelMatrix(transform)
		render.DrawSphere(zerovec, 1, step, step)    
	cam.PopModelMatrix()
end

local function DrawCoordinate(transform, size)
	size = size or 1
	cam.PushModelMatrix(transform)
		render.DrawLine(zerovec, unitx * size, Color(255, 0, 0, 255), false)
		render.DrawLine(zerovec, unity * size, Color(0, 255, 0, 255), false)
		render.DrawLine(zerovec, unitz * size, Color(0, 0, 255, 255), false)   
	cam.PopModelMatrix()
end

local function DrawBox(transform, size)
	size = size or 1
	cam.PushModelMatrix(transform)
		render.DrawBox(zerovec, zeroang, Vector(-size, -size, -size), Vector(size, size, size))
	cam.PopModelMatrix()
end



if CLIENT then
	TOOL.Category = 'spawnmenu.tools.posing'
	TOOL.Name = '#tool.sw2_tool.name'

	TOOL.ClientConVar['shader'] = 'VertexDeformationVertexLit'
	TOOL.ClientConVar['scale_x'] = '10'
	TOOL.ClientConVar['scale_y'] = '5'
	TOOL.ClientConVar['scale_z'] = '5'

	TOOL.ClientConVar['blood_scale'] = '0.5'

	TOOL.ClientConVar['project_texture'] = 'models/flesh'
	TOOL.ClientConVar['deform_texture'] = 'models/flesh'

	TOOL.ClientConVar['litegorec'] = '0'

	function TOOL.BuildCPanel(panel)
		if not SimpleWound then
			SimpleWoundUIShowMissingModuleDialog()
			return
		end



		local ctrl = vgui.Create('ControlPresets', panel)
		ctrl:SetPreset('sw2_tool')
		local default =	{
			sw2_tool_shader = 'VertexDeformationVertexLit',
			sw2_tool_scale_x = '10.0',
			sw2_tool_scale_y = '5',
			sw2_tool_scale_z = '5',
			sw2_tool_blood_scale = '0.5',
			sw2_tool_project_texture = 'models/flesh',
			sw2_tool_deform_texture = 'models/flesh',
			sw2_tool_litegorec = '0',
		}
		ctrl:AddOption('#preset.default', default)
		for k, v in pairs(default) do ctrl:AddConVar(k) end
		panel:AddPanel(ctrl)

		local shaderComboBox = panel:ComboBox('#tool.sw2_tool.shader', 'sw2_tool_shader')
		shaderComboBox:AddChoice('#sw2.shader.VertexDeformation', 'VertexDeformation')
		shaderComboBox:AddChoice('#sw2.shader.VertexDeformationVertexLit', 'VertexDeformationVertexLit')
		shaderComboBox:AddChoice('#sw2.shader.EllipsoidClip', 'EllipsoidClip')
		shaderComboBox:AddChoice('#sw2.shader.EllipsoidClipVertexLit', 'EllipsoidClipVertexLit')

		panel:NumSlider(
			'#tool.sw2_tool.scale_x', 
			'sw2_tool_scale_x', 
			1, 
			50, 
			3
		)

		panel:NumSlider(
			'#tool.sw2_tool.scale_y', 
			'sw2_tool_scale_y', 
			1, 
			50, 
			3
		)

		panel:NumSlider(
			'#tool.sw2_tool.scale_z', 
			'sw2_tool_scale_z', 
			1, 
			50, 
			3
		)

		panel:NumSlider(
			'#tool.sw2_tool.blood_scale', 
			'sw2_tool_blood_scale', 
			0, 
			2, 
			3
		)

		panel:Help('')

		local items = {
			'models/flesh',
			'models/props_c17/paper01',
			'models/props_foliage/tree_deciduous_01a_trunk',
			'models/props_wasteland/wood_fence01a',
			'simple_wound/alienflesh'
		}

		panel:Help('#tool.sw2_tool.deform_texture')
		local MatSelect2 = vgui.Create('MatSelect', panel)
		MatSelect2:Dock(TOP)
		Derma_Hook(MatSelect2.List, 'Paint', 'Paint', 'Panel')

		panel:AddItem(MatSelect2)
		MatSelect2:SetConVar('sw2_tool_deform_texture')

		MatSelect2:SetAutoHeight(true)
		MatSelect2:SetItemWidth(64)
		MatSelect2:SetItemHeight(64)

		for k, material in pairs(items) do
			MatSelect2:AddMaterial(material, material)
		end


		panel:Help('#tool.sw2_tool.project_texture')
		local MatSelect = vgui.Create('MatSelect', panel)
		MatSelect:Dock(TOP)
		Derma_Hook(MatSelect.List, 'Paint', 'Paint', 'Panel')

		panel:AddItem(MatSelect)
		MatSelect:SetConVar('sw2_tool_project_texture')

		MatSelect:SetAutoHeight(true)
		MatSelect:SetItemWidth(64)
		MatSelect:SetItemHeight(64)

		for k, material in pairs(items) do
			MatSelect:AddMaterial(material, material)
		end

		panel:CheckBox(
			'#tool.sw2_tool.litegorec', 
			'sw2_tool_litegorec'
		)

	end

	TOOL.Information = {
		{name = 'apply', icon = 'gui/lmb.png'},
		{name = 'bind_pose', icon = 'gui/rmb.png'},
		{name = 'reset', icon = 'gui/r.png'},
		{name = 'print', icon = 'gui/e.png'}
	}

end
--------------------------------------------------------------
function TOOL:RightClick(tr)
	local ent = tr.Entity
	if not IsValid(ent) then
		return
	end

	if SERVER then
		if istable(ent.physdata) then
			PlayPhys(ent, 'origin', ent.physdata)
			ent.physdata = nil
		else
			ent.physdata = RecordPhys(ent, 'origin')
			BindPose(ent)
		end
	end

	return true
end

function TOOL:LeftClick(tr)
	local ent = tr.Entity
	self.WoundSlot = (self.WoundSlot or 1)

	if SERVER and IsValid(ent) then
		tr.HitPos = tr.HitPos - tr.Normal * 5
		local woundWorldTransform = Matrix()
		woundWorldTransform:SetTranslation(tr.HitPos)
		woundWorldTransform:SetAngles(tr.HitNormal:Angle())
		woundWorldTransform:SetScale(
			Vector(
				self:GetClientNumber('scale_x'), 
				self:GetClientNumber('scale_y'), 
				self:GetClientNumber('scale_z')
			)
		)

		local shader = self:GetClientInfo('shader')
		local blood_range = self:GetClientNumber('blood_scale')
		local deform_texture = self:GetClientInfo('deform_texture')
		local project_texture = self:GetClientInfo('project_texture')
		local boneid = ent:TranslatePhysBoneToBone(tr.PhysicsBone)

		local litegore_compatibility = self:GetClientNumber('litegorec')
		local woundLocalTransform =
			SimpleWound.GetBoneMatrixSafe(ent, boneid):GetInverse() * woundWorldTransform
		local ellipsoid_center = woundLocalTransform:GetTranslation()
		local ellipsoid_angle = woundLocalTransform:GetAngles()
		local ellipsoid_scale = woundLocalTransform:GetScale()

		local easyparams = SWEasyParams.new(
			shader,
			SWEllipsoid.new(ellipsoid_center, ellipsoid_angle, ellipsoid_scale),
			deform_texture, project_texture,
			blood_range, litegore_compatibility,
			boneid, self.WoundSlot
		)
		easyparams.persistent = true

		SimpleWound.ApplyWoundEasy(ent, easyparams)
	end

	self.WoundSlot = ((self.WoundSlot or 1) % SimpleWound.MaxWounds) + 1

	if SERVER then
		local ply = self:GetOwner()
		ply:SetNW2Int("sw2_tool_wound_slot", self.WoundSlot)
	end

	return true
end

function TOOL:Reload(tr)
	self.WoundSlot = 1
	local ent = tr.Entity
	if IsValid(ent) then
		SimpleWound.Reset(ent)
	end

	if SERVER then
		local ply = self:GetOwner()
		ply:SetNW2Int("sw2_tool_wound_slot", self.WoundSlot)
	end


	return true
end


if CLIENT then
	local wireframe = Material('models/wireframe')
	local vol_light001 = Material('models/effects/vol_light001')

	local ghostent = ClientsideModel('models/hunter/blocks/cube025x025x025.mdl')
	ghostent:SetNoDraw(true)

	function TOOL:Think()
		local tr = LocalPlayer():GetEyeTrace()
		local ent = tr.Entity
		local hitpos = tr.HitPos - tr.Normal * 5
		-- 处理幽灵实体
		if not IsValid(ghostent) then
			ghostent = ClientsideModel()
			ghostent:SetNoDraw(true)
		end

		if IsValid(ent) then
			if ghostent:GetModel() ~= ent:GetModel() then
				ghostent:SetModel(ent:GetModel())
				ghostent:SetupBones()
			end

			if ent:IsRagdoll() then
				if ghostent:GetParent() ~= ent then
					ghostent:SetPos(ent:GetPos())
					ghostent:SetAngles(ent:GetAngles())
					ghostent:SetParent(ent)
					ghostent:AddEffects(EF_BONEMERGE)
					ghostent:SetupBones()
				end
			else
				ghostent:SetPos(ent:GetPos())
				ghostent:SetAngles(ent:GetAngles())
			end
		end

		-- 计算相关信息
		self.info = self.info or {}
		if IsValid(ent) then
			local boneid = ent:TranslatePhysBoneToBone(tr.PhysicsBone)
			local bonematrix = ent:GetBoneMatrix(boneid)
			
			if bonematrix then
				self.info.bone = string.format('%d, %s', boneid, ent:GetBoneName(boneid))

				self.DrawInfoFlag = true
			else
				self.DrawInfoFlag = false
			end
		else
			self.DrawInfoFlag = false
		end

		-- 计算标记作用范围
		self.mark = self.mark or {}
		if IsValid(ent) then
			local woundEllip = Matrix()
			woundEllip:SetTranslation(hitpos)
			woundEllip:SetAngles(tr.HitNormal:Angle())

			local bloodTexEllip = Matrix() 
			bloodTexEllip:SetTranslation(hitpos)
			bloodTexEllip:SetAngles(tr.HitNormal:Angle())

			woundEllip:SetScale(
				Vector(
					self:GetClientNumber('scale_x'), 
					self:GetClientNumber('scale_y'), 
					self:GetClientNumber('scale_z')
				)
			)

			bloodTexEllip:SetScale(
				Vector(
					self:GetClientNumber('scale_x'), 
					self:GetClientNumber('scale_y'), 
					self:GetClientNumber('scale_z')
				) * (1 + self:GetClientNumber('blood_scale'))
			)	

			self.mark.WoundEllip = woundEllip
			self.mark.BloodTexEllip = bloodTexEllip
			self.DrawMarkFlag = true
		else
			self.DrawMarkFlag = false
		end

		self.PrintFlag = input.IsKeyDown(KEY_E) and !self.KeyE
		if self.PrintFlag then
			PrintSWParams(ent)
		end

		self.KeyE = input.IsKeyDown(KEY_E)
	end

	function TOOL:DrawMark()
		-- 标记作用范围
		local woundEllip = self.mark.WoundEllip
		local bloodTexEllip = self.mark.BloodTexEllip

		cam.Start3D(EyePos(), EyeAngles())
			render.ClearStencil()
			render.SetStencilEnable(true)
				render.SetStencilWriteMask(1)
				render.SetStencilTestMask(1)
				render.SetStencilReferenceValue(0)
				render.SetStencilCompareFunction(STENCIL_ALWAYS)
				render.SetStencilPassOperation(STENCIL_REPLACE)
				render.SetStencilFailOperation(STENCIL_REPLACE)
				render.SetStencilZFailOperation(STENCIL_REPLACE)

				if IsValid(ghostent) then
					render.OverrideColorWriteEnable(true, false)
					render.OverrideDepthEnable(true, true)
						ghostent:DrawModel()
					render.OverrideDepthEnable(false)
					render.OverrideColorWriteEnable(false)
				end


				render.SetStencilCompareFunction(STENCIL_ALWAYS)
				render.SetStencilPassOperation(STENCIL_KEEP)
				render.SetStencilFailOperation(STENCIL_KEEP)
				render.SetStencilZFailOperation(STENCIL_INCR)

				render.SetMaterial(vol_light001)
				DrawEllipsoid(woundEllip, 8)
	
				

				render.SetStencilReferenceValue(1)
				render.SetStencilCompareFunction(STENCIL_EQUAL)
				render.SetStencilPassOperation(STENCIL_KEEP)
				render.SetStencilFailOperation(STENCIL_KEEP)
				render.SetStencilZFailOperation(STENCIL_KEEP)

				if IsValid(ghostent) then
					render.MaterialOverride(wireframe)
						ghostent:DrawModel()
					render.MaterialOverride()
				end

				cam.Start2D()
					surface.SetDrawColor(0, 255, 255, 50)
					surface.DrawRect(0, 0, ScrW(), ScrH())
				cam.End2D()




				render.SetStencilCompareFunction(STENCIL_ALWAYS)
				render.SetStencilPassOperation(STENCIL_KEEP)
				render.SetStencilFailOperation(STENCIL_KEEP)
				render.SetStencilZFailOperation(STENCIL_INCR)

				render.SetMaterial(vol_light001)
				DrawEllipsoid(bloodTexEllip, 8)

				render.SetStencilReferenceValue(1)
				render.SetStencilCompareFunction(STENCIL_EQUAL)
				render.SetStencilPassOperation(STENCIL_KEEP)
				render.SetStencilFailOperation(STENCIL_KEEP)
				render.SetStencilZFailOperation(STENCIL_KEEP)

				cam.Start2D()
					surface.SetDrawColor(255, 0, 255, 50)
					surface.DrawRect(0, 0, ScrW(), ScrH())
				cam.End2D()

			render.SetStencilEnable(false)

			
			DrawCoordinate(woundEllip)
			DrawEllipsoidRing(woundEllip)

			if IsValid(ghostent) then
				DrawCoordinate(ghostent:GetWorldTransformMatrix(), 30)
			end
		cam.End3D()
	end

	local colorwhite = Color(255, 255, 255)
	local label_bone = language.GetPhrase('#tool.sw2_tool.label.bone')
	function TOOL:DrawInfo()
		local startY = ScrH() * 0.5
		surface.SetDrawColor(0, 0, 0, 100)
		draw.RoundedBox(10, 0, startY, 400, 50, Color(0, 0, 0, 100))
		draw.DrawText(label_bone .. ':' .. self.info.bone, 'CloseCaption_Bold', 
			10, startY + 10, colorwhite, TEXT_ALIGN_LEFT)
	end


	function TOOL:DrawHUD()
		if self.DrawMarkFlag and SimpleWound then
			-- 安全调用
			local success, err = pcall(self.DrawMark, self)
			if not success then
				ErrorNoHalt(string.format('[Simple Wound]: %s\n', err))
				render.OverrideColorWriteEnable(false)
				render.OverrideDepthEnable(false)
				return
			end
		end

		if self.DrawInfoFlag then
			self:DrawInfo()
		end
	end

	local errmsg = language.GetPhrase('#sw2.missing_module')
	local msg = language.GetPhrase('sw2.version_hint') .. (SimpleWound and SimpleWound.Version or '?')
	local msg_wound_slot = language.GetPhrase('sw2.wound_slot')
	function TOOL:DrawToolScreen(width, height)
		-- 错误提示
		if not SimpleWound then
			surface.SetDrawColor(0, 0, 0, 255)
			surface.DrawRect(0, 0, width, height)

			draw.SimpleText(
				errmsg, 
				'DermaLarge', 
				0, 
				0, 
				Color(255, 0, 0, 255), 
				TEXT_ALIGN_LEFT, 
				TEXT_ALIGN_TOP 
			)
		else
			local WoundSlot = self:GetOwner():GetNW2Int("sw2_tool_wound_slot", 1)

			surface.SetDrawColor(0, 0, 0, 255)
			surface.DrawRect(0, 0, width, height)

			draw.SimpleText(
				msg, 
				'DermaLarge', 
				0, 
				0, 
				Color(0, 255, 0, 255), 
				TEXT_ALIGN_LEFT, 
				TEXT_ALIGN_TOP 
			)

			draw.SimpleText(
				msg_wound_slot .. (WoundSlot or 1), 
				'DermaLarge', 
				0, 
				40, 
				Color(0, 255, 0, 255), 
				TEXT_ALIGN_LEFT, 
				TEXT_ALIGN_TOP 
			)
		end
	end
end 
