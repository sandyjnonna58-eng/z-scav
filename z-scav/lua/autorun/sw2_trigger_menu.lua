AddCSLuaFile()

if CLIENT then
	hook.Add('PopulateToolMenu', 'SimpleWoundTrigger', function()
		spawnmenu.AddToolMenuOption('Utilities', language.GetPhrase('#sw2.category'), 'SimpleWoundTrigger', language.GetPhrase('#sw2.trigger_menu'), '', '', function(panel)
			panel:Clear()
			
			if not SimpleWound then
				SimpleWoundUIShowMissingModuleDialog()
				return
			end


			local items = {
				'models/flesh',
				'models/props_c17/paper01',
				'models/props_foliage/tree_deciduous_01a_trunk',
				'models/props_wasteland/wood_fence01a',
				'simple_wound/alienflesh'
			}
			panel:CheckBox(
				'#Enable', 
				'sw_trigger_enable'
			)

			panel:CheckBox(
				'#sw2.trigger_on_death',
				'sw_trigger_on_death'
			)

			panel:CheckBox(
				'#sw2.trigger_ragdoll',
				'sw_trigger_ragdoll'
			)

			panel:CheckBox(
				'#sw2.trigger_clientside_corpse',
				'sw_trigger_clientside_corpse'
			)
			
			panel:CheckBox(
				'#tool.sw2_tool.litegorec', 
				'sw_trigger_litegore_compatibility'
			)
			
			panel:NumSlider('#tool.sw2_tool.blood_scale', 'sw_trigger_blood_scale', 0, 1, 2)

			panel:Help('#tool.sw2_tool.deform_texture')
			local MatSelect = vgui.Create('MatSelect', panel)
			MatSelect:Dock(TOP)
			Derma_Hook(MatSelect.List, 'Paint', 'Paint', 'Panel')

			panel:AddItem(MatSelect)
			MatSelect:SetConVar('sw_trigger_deform_texture')

			MatSelect:SetAutoHeight(true)
			MatSelect:SetItemWidth(64)
			MatSelect:SetItemHeight(64)

			for k, material in pairs(items) do
				MatSelect:AddMaterial(material, material)
			end

			panel:Help('#tool.sw2_tool.project_texture')
			local MatSelect2 = vgui.Create('MatSelect', panel)
			MatSelect2:Dock(TOP)
			Derma_Hook(MatSelect2.List, 'Paint', 'Paint', 'Panel')

			panel:AddItem(MatSelect2)
			MatSelect2:SetConVar('sw_trigger_project_texture')

			MatSelect2:SetAutoHeight(true)
			MatSelect2:SetItemWidth(64)
			MatSelect2:SetItemHeight(64)

			for k, material in pairs(items) do
				MatSelect2:AddMaterial(material, material)
			end
		end)
	end )
end


























