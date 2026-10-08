if SERVER then return end

hg = hg or {}

local function UrlEncodePath(s)
    s = tostring(s or "")
    return (s:gsub("([^%w%-%_%.%/:%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function StopLastStandVideo()
    if timer.Exists("zcity_delta_laststand_video_timeout") then
        timer.Remove("zcity_delta_laststand_video_timeout")
    end
    if hg.__zcity_delta_laststand_video and IsValid(hg.__zcity_delta_laststand_video) then
        hg.__zcity_delta_laststand_video:Remove()
    end
    hg.__zcity_delta_laststand_video = nil
    hg.__zcity_delta_laststand_until = nil
end

local function StartLastStandVideo(untilTime)
    StopLastStandVideo()
    hg.__zcity_delta_laststand_until = tonumber(untilTime) or nil
    local delay = 210
    if hg.__zcity_delta_laststand_until and hg.__zcity_delta_laststand_until > 0 then
        delay = math.max(0, hg.__zcity_delta_laststand_until - CurTime())
    end
    timer.Create("zcity_delta_laststand_video_timeout", delay, 1, function()
        StopLastStandVideo()
    end)

    local rawPath = "asset://garrysmod/addons/videos/Last stand _ OST.webm"
    local src = UrlEncodePath(rawPath)

    local html = string.format([[
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
html, body { margin: 0; padding: 0; width: 100%%; height: 100%%; overflow: hidden; background: transparent; }
video { width: 100vw; height: 100vh; object-fit: cover; opacity: 0; }
</style>
</head>
<body>
<video id="v" autoplay playsinline>
  <source src="%s" type="video/webm">
</video>
<script>
  const v = document.getElementById('v');
  let started = false;
  v.volume = 1.0;
  v.addEventListener('playing', () => { started = true; v.style.opacity = '1'; });
  v.addEventListener('error', () => { v.style.opacity = '0'; });
  v.addEventListener('ended', () => { started = true; v.style.opacity = '0'; v.pause(); });
  const tryPlay = () => {
    if (started) return;
    v.play().catch(() => {});
    setTimeout(tryPlay, 500);
  };
  tryPlay();
</script>
</body>
</html>
]], src)

    local pnl = vgui.Create("DHTML")
    pnl:SetSize(ScrW(), ScrH())
    pnl:SetPos(0, 0)
    if pnl.SetPaintBackground then
        pnl:SetPaintBackground(false)
    else
        pnl.Paint = nil
    end
    pnl:SetMouseInputEnabled(false)
    pnl:SetKeyboardInputEnabled(false)
    pnl:SetAllowLua(false)
    pnl:SetHTML(html)

    hg.__zcity_delta_laststand_video = pnl
end

local function RegisterDeltaCommands()
    local tbl = concommand.GetTable and concommand.GetTable() or {}

    if not tbl["hg_menu"] then
        concommand.Add("hg_menu", function()
            if not hg or not hg.CreateRadialMenu then return end
            hg.CreateRadialMenu()
        end)
    end
end

hook.Add("Initialize", "zcity_delta_register_commands", RegisterDeltaCommands)
hook.Add("InitPostEntity", "zcity_delta_register_commands", RegisterDeltaCommands)

timer.Simple(0, function()
    RegisterDeltaCommands()
end)

net.Receive("zcity_delta_laststand", function()
    local active = net.ReadBool()
    local untilTime = net.ReadFloat()

    if active then
        StartLastStandVideo(untilTime)
    else
        StopLastStandVideo()
    end
end)

hook.Add("ShutDown", "zcity_delta_laststand_video_cleanup", function()
    StopLastStandVideo()
end)

hook.Add("Think", "zcity_delta_laststand_video_timeout", function()
    local untilTime = hg.__zcity_delta_laststand_until
    if not untilTime then return end
    if CurTime() < untilTime then return end
    StopLastStandVideo()
end)
