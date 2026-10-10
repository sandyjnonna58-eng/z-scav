--[[
    Z-SCAV: оптимизация сервера (FPS и пинг).

    1) Лимит трупов: тела игроков - тяжёлая физика (ragdoll) + у каждого свой "организм".
       zscav_max_corpses 14       - больше этого числа самые старые тела убираются
       zscav_corpse_lifetime 600  - тело убирается через N секунд (0 - никогда)
    2) Организм трупа (кровь, органы) обновляется раз в секунду и только первую минуту:
       zscav_corpse_think_rate 1, zscav_corpse_think_time 60   (см. organism/tier_0/sv_tier_0.lua)
    3) Сетевые настройки сервера (ставятся при старте, если zscav_perf_net 1):
       частота обновлений 33-66, без ограничения скорости отдачи. Меньше "резины" и скачков пинга.
       Организм шлётся ненадёжным пакетом (hg_unreliable_nets 1) - не забивает основной канал.
]]

local cvMax   = CreateConVar("zscav_max_corpses", "14", FCVAR_ARCHIVE, "Z-SCAV: максимум трупов на карте", 0, 200)
local cvLife  = CreateConVar("zscav_corpse_lifetime", "600", FCVAR_ARCHIVE, "Z-SCAV: через сколько секунд убирать труп (0 - никогда)", 0, 36000)
local cvRate  = CreateConVar("zscav_corpse_think_rate", "1", FCVAR_ARCHIVE, "Z-SCAV: как часто (сек) обновлять организм трупа", 0.1, 10)
local cvTime  = CreateConVar("zscav_corpse_think_time", "60", FCVAR_ARCHIVE, "Z-SCAV: сколько секунд после смерти труп ещё 'живёт' (0 - всегда)", 0, 3600)
local cvNet   = CreateConVar("zscav_perf_net", "1", FCVAR_ARCHIVE, "Z-SCAV: применять сетевые настройки при старте", 0, 1)

local function SyncGlobals()
    ZSCAV_CORPSE_THINK_RATE = cvRate:GetFloat()
    ZSCAV_CORPSE_THINK_TIME = cvTime:GetFloat()
end
SyncGlobals()
cvars.AddChangeCallback("zscav_corpse_think_rate", SyncGlobals, "zscav_perf")
cvars.AddChangeCallback("zscav_corpse_think_time", SyncGlobals, "zscav_perf")

-- ---------------------------------------------------------------------------
-- трупы
-- ---------------------------------------------------------------------------
local corpses = {} -- {ent, t}

local function Track(ent)
    if not IsValid(ent) then return end
    for _, c in ipairs(corpses) do if c[1] == ent then return end end
    corpses[#corpses + 1] = {ent, CurTime()}
end

-- тело после смерти игрока (гейммод передаёт ragdoll в этот хук)
hook.Add("PostPostPlayerDeath", "ZSCAV_PerfCorpses", function(ply, ragdoll)
    if IsValid(ragdoll) then Track(ragdoll) end
end)

local function IsLiveFake(ent)
    local owner = ent:GetNWEntity("ply")
    return IsValid(owner) and owner:IsPlayer() and owner:Alive() and owner.FakeRagdoll == ent
end

timer.Create("ZSCAV_PerfCorpses", 5, 0, function()
    local now, life, max = CurTime(), cvLife:GetFloat(), cvMax:GetInt()
    -- чистим список: удалённые и снова "живые" (человек встал из этого тела)
    for i = #corpses, 1, -1 do
        local e = corpses[i][1]
        if not IsValid(e) or IsLiveFake(e) then table.remove(corpses, i) end
    end
    -- по времени
    if life > 0 then
        for i = #corpses, 1, -1 do
            if now - corpses[i][2] > life then
                local e = corpses[i][1]
                table.remove(corpses, i)
                if IsValid(e) then e:Remove() end
            end
        end
    end
    -- по количеству: убираем самые старые
    while max > 0 and #corpses > max do
        local e = table.remove(corpses, 1)[1]
        if IsValid(e) then e:Remove() end
    end
end)

hook.Add("PostCleanupMap", "ZSCAV_PerfCorpses", function() corpses = {} end)

-- ---------------------------------------------------------------------------
-- сеть
-- ---------------------------------------------------------------------------
local NET = {
    {"sv_minrate", "100000"},
    {"sv_maxrate", "0"},
    {"sv_minupdaterate", "33"},
    {"sv_maxupdaterate", "66"},
    {"sv_mincmdrate", "33"},
    {"sv_maxcmdrate", "66"},
    {"net_maxfilesize", "64"},
    {"hg_unreliable_nets", "1"},
}
hook.Add("InitPostEntity", "ZSCAV_PerfNet", function()
    if not cvNet:GetBool() then return end
    for _, kv in ipairs(NET) do
        if ConVarExists(kv[1]) then RunConsoleCommand(kv[1], kv[2]) end
    end
    print("[Z-SCAV] сетевые настройки применены (zscav_perf_net 0 - не трогать)")
end)

concommand.Add("zscav_perf_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local n = 0
    for _ in pairs(hg and hg.organism and hg.organism.list or {}) do n = n + 1 end
    local msg = ("Трупов под контролем: %d (лимит %d), организмов всего: %d, игроков: %d"):format(#corpses, cvMax:GetInt(), n, player.GetCount())
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end)
