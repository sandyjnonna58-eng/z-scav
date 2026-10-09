--[[
    Z-SCAV: русский текст в интерфейсе.
    Шрифты в Garry's Mod показывают кириллицу только с флагом extended = true.
    Здесь он включается для ВСЕХ шрифтов, которые создают мод и аддоны, если автор его не указал.
]]
if not surface or not surface.CreateFont or surface.ZSCAVCyrillicPatched then return end
surface.ZSCAVCyrillicPatched = true
local orig = surface.CreateFont
function surface.CreateFont(name, data)
    if istable(data) and data.extended == nil then data.extended = true end
    return orig(name, data)
end
