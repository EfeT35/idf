if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
UIS = game:GetService("UserInputService")
RunService = game:GetService("RunService")
Stats = game:GetService("Stats")
TweenService = game:GetService("TweenService")
HttpService = game:GetService("HttpService")
ReplicatedStorage = game:GetService("ReplicatedStorage")
Workspace = game:GetService("Workspace")
Lighting = game:GetService("Lighting")
TeleportService = game:GetService("TeleportService")
CoreGui = game:GetService("CoreGui")
VirtualInputManager = game:GetService("VirtualInputManager")

-- Unlimited FPS: remove Roblox's default 240 FPS cap. 0 = uncapped on most executors.
pcall(function() if setfpscap then setfpscap(9999) end end)

-- Insta-reset state captured by the FireServer hook below.
-- GUID is the first arg of the balloon payload. Defaults to a randomly-generated
-- UUID so the payload is at least syntactically valid (an empty string was
-- silently rejected by the server -- that's why the reset wasn't firing). If you
-- have a known-good GUID, set `_G.SXE_RESET_GUID` before the script runs.
local function _newGUID()
    local hex = "0123456789abcdef"
    local t = {}
    for i = 1, 32 do t[#t+1] = hex:sub(math.random(1,16), math.random(1,16)) end
    return table.concat(t, "", 1, 8) .. "-" .. table.concat(t, "", 9, 12)
        .. "-" .. table.concat(t, "", 13, 16) .. "-" .. table.concat(t, "", 17, 20)
        .. "-" .. table.concat(t, "", 21, 32)
end

local function makeOneWay(plat)
    if not plat then return end
    local rsConn
    local lastY = nil
    rsConn = game:GetService("RunService").Stepped:Connect(function()
        if not plat or not plat.Parent then
            if rsConn then rsConn:Disconnect() end
            return
        end
        local char = game.Players.LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local currentY = hrp.Position.Y
            if not lastY then lastY = currentY end
            
            local deltaY = currentY - lastY
            local isMovingUp = (hrp.AssemblyLinearVelocity.Y > 1) or (deltaY > 0.01 and deltaY < 5)
            
            if isMovingUp then
                plat.CanCollide = false
            else
                if currentY > plat.Position.Y + 0.1 then
                    plat.CanCollide = true
                else
                    plat.CanCollide = false
                end
            end
            
            lastY = currentY
        end
    end)
end

GUID = GUID or _G.SXE_RESET_GUID or _newGUID()
resetRemote = nil
instaResetCooldown = false

local old; old = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = {...}
    local arg1 = args[1]

    -- Capture the first RE/* remote the game itself fires -- that's the reset
    -- target for instareset() below.
    if not resetRemote and self.Name:sub(1, 3) == "RE/" then
        resetRemote = self
    end

    if #self.Name == 67 and arg1 and typeof(arg1) == "string" then
        if string.find(arg1, "StopTrying") then
            print("ez bypass")
            return
        end
    end
    return old(self, ...)
end)

-- LPH_NO_VIRTUALIZE: real preprocessor directive under Luraph; harmless passthrough
-- everywhere else. Declared once globally so every heavy hot-path body can wrap
-- itself without each call site re-shimming.
if not LPH_NO_VIRTUALIZE then LPH_NO_VIRTUALIZE = function(fn) return fn end end

-- =====================================================================
-- LAZY-LOAD QUEUE
-- =====================================================================
_G.__SXELazyQ = _G.__SXELazyQ or {}
local function LazyInit(name, fn)
    table.insert(_G.__SXELazyQ, { name = name, fn = LPH_NO_VIRTUALIZE(fn) })
end
task.defer(LPH_NO_VIRTUALIZE(function()
    while true do
        if #_G.__SXELazyQ > 0 then
            local item = table.remove(_G.__SXELazyQ, 1)
            local ok, err = pcall(item.fn)
            if not ok then warn("[SXE Lazy]", item.name, err) end
            task.wait(0.08)
        else
            task.wait(0.5)
        end
    end
end))

-- Persistent panel visibility store that survives script re-executes within the same Roblox session
_G._SXEPanelVis = _G._SXEPanelVis or {}

_G.lazyUIs = {}
_G.addLazyUI = function(element, targetVis, isScreenGui, panelName)
    if element then
        if isScreenGui then
            element.Enabled = false
        else
            element.Visible = false
        end
        table.insert(_G.lazyUIs, {element = element, targetVis = targetVis, isScreenGui = isScreenGui, cancelled = false, panelName = panelName})
    end
end
_G.cancelLazyUI = function(element)
    for _, item in ipairs(_G.lazyUIs) do
        if item.element == element then
            item.cancelled = true
            break
        end
    end
end
task.delay(4.0, function()
    for _, item in ipairs(_G.lazyUIs) do
        if item.element and not item.cancelled then
            local vis
            if item.panelName then
                -- Priority: _G store (survives re-exec) > Config.Visibilities > default true
                local fromG = _G._SXEPanelVis[item.panelName]
                if fromG ~= nil then
                    vis = fromG
                elseif Config and Config.Visibilities then
                    local saved = Config.Visibilities[item.panelName]
                    if saved ~= nil then vis = saved else vis = true end
                else
                    vis = item.targetVis
                end
            else
                vis = item.targetVis
            end
            if item.isScreenGui then
                pcall(function() item.element.Enabled = vis end)
            elseif item.element.Parent then
                pcall(function() item.element.Visible = vis end)
            end
        end
    end
    if _G.initRemoteSellLazy then
        pcall(_G.initRemoteSellLazy)
    end
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
pcall(function() Players.RespawnTime = 0 end)

-- GLOBAL SCALE SYSTEM (Mobile Friendly Auto-Scaling)
local GlobalUIScaleVal = 1
local scaledGuis = {}

local function getGlobalScale()
    return GlobalUIScaleVal
end

local function updateAllGuisScale(newScale)
    GlobalUIScaleVal = newScale
    for sg, master in pairs(scaledGuis) do
        pcall(function()
            if sg and sg.Parent and master and master.Parent then
                local scaleObj = master:FindFirstChild("SXE_GlobalScale")
                if scaleObj then
                    scaleObj.Scale = newScale
                end
                master.Size = UDim2.new(1 / newScale, 0, 1 / newScale, 0)
            end
        end)
    end
end

local function registerScreenGui(sg)
    local master = sg:FindFirstChild("SXE_MasterFrame")
    if not master then
        master = Instance.new("Frame")
        master.Name = "SXE_MasterFrame"
        master.BackgroundTransparency = 1
        master.BorderSizePixel = 0
        master.Parent = sg
        
        local scaleObj = Instance.new("UIScale")
        scaleObj.Name = "SXE_GlobalScale"
        scaleObj.Parent = master
    end
    scaledGuis[sg] = master
    
    pcall(function()
        local scaleObj = master:FindFirstChild("SXE_GlobalScale")
        if scaleObj then
            scaleObj.Scale = GlobalUIScaleVal
        end
        master.Size = UDim2.new(1 / GlobalUIScaleVal, 0, 1 / GlobalUIScaleVal, 0)
    end)
    return master
end

local function recalculateScale()
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local size = cam.ViewportSize
    local h = size.Y
    
    local isMobile = UIS.TouchEnabled
    local newScale = 1
    if isMobile then
        -- Mobile/Tablet scaling: aggressive down-scale to perfectly fit small landscape screens
        newScale = math.clamp(h / 1000, 0.40, 0.58)
    else
        -- PC/Console scaling: standard comfortable scaling
        newScale = math.clamp(h / 800, 0.65, 1.0)
    end
    updateAllGuisScale(newScale)
end

local cameraConn
local function setupCameraListener()
    if cameraConn then pcall(function() cameraConn:Disconnect() end) end
    local cam = Workspace.CurrentCamera
    if cam then
        cameraConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(recalculateScale)
        recalculateScale()
    end
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(setupCameraListener)
task.spawn(setupCameraListener)

local old = playerGui:FindFirstChild("SXEHub_V3"); if old then old:Destroy() end
local gui_sg = Instance.new("ScreenGui"); gui_sg.Name = "SXEHub_V3"; gui_sg.ResetOnSpawn = false; gui_sg.IgnoreGuiInset = true; gui_sg.DisplayOrder = 9999999; gui_sg.Parent = playerGui
local gui = registerScreenGui(gui_sg)

-- SAKURA PETALS (inside hub ScreenGui, donc seulement sur l'UI)
do
    -- Parent dans gui_sg pour que les pétales restent dans le hub, pas sur le jeu
    local petalContainer = Instance.new("Frame")
    petalContainer.Name = "PetalContainer"
    petalContainer.Size = UDim2.fromScale(1, 1)
    petalContainer.BackgroundTransparency = 1
    petalContainer.ZIndex = 99999
    petalContainer.Parent = gui_sg

    local PINK_TINTS = {
        Color3.fromRGB(255,182,213), Color3.fromRGB(255,160,200), Color3.fromRGB(244,114,182),
        Color3.fromRGB(249,168,212), Color3.fromRGB(252,211,227), Color3.fromRGB(255,192,220),
    }

    local NUM_PETALS = 55
    local petals = {}
    local vp = workspace.CurrentCamera.ViewportSize

    -- Pétale individuel : ovale simple arrondi
    local function makePetal()
        local w = math.random(20, 30)
        local h = math.random(13, 20)
        local f = Instance.new("Frame")
        f.BackgroundColor3 = PINK_TINTS[math.random(1, #PINK_TINTS)]
        f.BackgroundTransparency = math.random(5, 30) / 100
        f.BorderSizePixel = 0
        f.Size = UDim2.fromOffset(w, h)
        local ui = Instance.new("UICorner"); ui.CornerRadius = UDim.new(0.5, 0); ui.Parent = f
        f.ZIndex = 99999
        f.Parent = petalContainer
        return f
    end

    local function resetPetal(p)
        vp = workspace.CurrentCamera.ViewportSize
        p.frame.Position = UDim2.fromOffset(math.random(0, math.floor(vp.X)), math.random(-140, -10))
        p.speed = math.random(55, 140)
        p.sway = math.random(25, 65)
        p.swaySpeed = math.random(35, 90) / 100
        p.swayOffset = math.random(0, 628) / 100
        p.rot = math.random(0, 360)
        p.rotSpeed = math.random(-120, 120)
        p.x = p.frame.Position.X.Offset
    end

    for i = 1, NUM_PETALS do
        local f = makePetal()
        local p = {frame=f, speed=0, sway=0, swaySpeed=0, swayOffset=0, rot=0, rotSpeed=0, x=0}
        resetPetal(p)
        p.frame.Position = UDim2.fromOffset(p.x, math.random(-200, math.floor(vp.Y)))
        table.insert(petals, p)
    end

    local lastT = tick()
    game:GetService("RunService").Heartbeat:Connect(function()
        local now = tick()
        local dt = math.min(now - lastT, 0.05)
        lastT = now
        vp = workspace.CurrentCamera.ViewportSize
        for _, p in ipairs(petals) do
            local sway = math.sin(now * p.swaySpeed + p.swayOffset) * p.sway
            local nx = p.x + sway
            local ny = p.frame.Position.Y.Offset + p.speed * dt
            p.rot = p.rot + p.rotSpeed * dt
            p.frame.Position = UDim2.fromOffset(nx, ny)
            p.frame.Rotation = p.rot
            if ny > vp.Y + 30 then
                resetPetal(p)
            end
        end
    end)
end

-- SHARED TOGGLE STATE
local ToggleState = {}
local function regToggle(name, default)
    if not ToggleState[name] then ToggleState[name] = {value = default or false, listeners = {}} end
end
local function getToggle(name) return ToggleState[name] and ToggleState[name].value or false end
local function setToggle(name, val, skipNotify)
    regToggle(name)
    ToggleState[name].value = val
    if not skipNotify then
        for _, fn in ipairs(ToggleState[name].listeners) do pcall(fn, val) end
    end
end
local function onToggleChanged(name, fn)
    regToggle(name); table.insert(ToggleState[name].listeners, fn)
end

-- GLOBAL CONFIG FORWARD DECLARATIONS (to avoid undefined/shadowing issues)
local Config
local saveConfig
local loadConfig

-- THEME (SXE Pink)
Themes = {
    Light = {
        Background=Color3.fromRGB(255,255,255), MainBackground=Color3.fromRGB(255,252,255),
        Panel=Color3.fromRGB(255,249,252), Row=Color3.fromRGB(252,245,249), RowHover=Color3.fromRGB(250,238,245),
        Accent=Color3.fromRGB(232,111,177), AccentLight=Color3.fromRGB(238,98,178),
        Green=Color3.fromRGB(235,117,181), Red=Color3.fromRGB(237,150,189), Red2=Color3.fromRGB(220,104,162),
        Text=Color3.fromRGB(236,108,174), Dim=Color3.fromRGB(205,151,180), Stroke=Color3.fromRGB(248,188,219),
        SoftButton=Color3.fromRGB(249,240,245), SoftButtonHover=Color3.fromRGB(246,232,240),
        SoftAccent=Color3.fromRGB(244,223,233), SoftAccentHover=Color3.fromRGB(241,213,228),
        ToggleOff=Color3.fromRGB(255,231,243), ToggleOff2=Color3.fromRGB(255,236,245),
        InputBg=Color3.fromRGB(255,255,255), SliderBg=Color3.fromRGB(243,204,223),
        BlacklistHover=Color3.fromRGB(255,220,225), BlacklistLeave=Color3.fromRGB(255,240,248),
    },
    Dark = {
        Background=Color3.fromRGB(20,20,20), MainBackground=Color3.fromRGB(15,15,15),
        Panel=Color3.fromRGB(28,25,28), Row=Color3.fromRGB(35,30,35), RowHover=Color3.fromRGB(48,38,48),
        Accent=Color3.fromRGB(232,111,177), AccentLight=Color3.fromRGB(238,98,178),
        Green=Color3.fromRGB(235,117,181), Red=Color3.fromRGB(237,150,189), Red2=Color3.fromRGB(220,104,162),
        Text=Color3.fromRGB(255,255,255), Dim=Color3.fromRGB(200,200,200), Stroke=Color3.fromRGB(60,40,55),
        SoftButton=Color3.fromRGB(35,28,33), SoftButtonHover=Color3.fromRGB(45,35,42),
        SoftAccent=Color3.fromRGB(55,38,48), SoftAccentHover=Color3.fromRGB(65,45,58),
        ToggleOff=Color3.fromRGB(35,28,33), ToggleOff2=Color3.fromRGB(35,28,33),
        InputBg=Color3.fromRGB(30,25,30), SliderBg=Color3.fromRGB(55,40,50),
        BlacklistHover=Color3.fromRGB(80,35,45), BlacklistLeave=Color3.fromRGB(50,35,45),
    },
    Terminal = {
        Background=Color3.fromRGB(8,10,8), MainBackground=Color3.fromRGB(5,7,5),
        Panel=Color3.fromRGB(14,20,14), Row=Color3.fromRGB(18,26,18), RowHover=Color3.fromRGB(26,38,26),
        Accent=Color3.fromRGB(74,222,128), AccentLight=Color3.fromRGB(34,197,94),
        Green=Color3.fromRGB(74,222,128), Red=Color3.fromRGB(244,114,182), Red2=Color3.fromRGB(236,72,153),
        Text=Color3.fromRGB(134,239,172), Dim=Color3.fromRGB(60,110,70), Stroke=Color3.fromRGB(30,60,35),
        SoftButton=Color3.fromRGB(16,22,16), SoftButtonHover=Color3.fromRGB(22,30,22),
        SoftAccent=Color3.fromRGB(20,40,24), SoftAccentHover=Color3.fromRGB(26,50,30),
        ToggleOff=Color3.fromRGB(20,26,20), ToggleOff2=Color3.fromRGB(20,26,20),
        InputBg=Color3.fromRGB(10,14,10), SliderBg=Color3.fromRGB(20,40,24),
        BlacklistHover=Color3.fromRGB(60,20,20), BlacklistLeave=Color3.fromRGB(20,26,20),
    },
    Premium = {
        Background=Color3.fromRGB(17,17,19), MainBackground=Color3.fromRGB(13,13,15),
        Panel=Color3.fromRGB(20,20,23), Row=Color3.fromRGB(26,26,29), RowHover=Color3.fromRGB(34,34,38),
        Accent=Color3.fromRGB(34,197,94), AccentLight=Color3.fromRGB(225,225,230),
        Green=Color3.fromRGB(34,197,94), Red=Color3.fromRGB(244,114,182), Red2=Color3.fromRGB(236,72,153),
        Text=Color3.fromRGB(245,245,247), Dim=Color3.fromRGB(113,113,122), Stroke=Color3.fromRGB(38,38,43),
        SoftButton=Color3.fromRGB(26,26,29), SoftButtonHover=Color3.fromRGB(34,34,38),
        SoftAccent=Color3.fromRGB(24,32,26), SoftAccentHover=Color3.fromRGB(30,40,32),
        ToggleOff=Color3.fromRGB(35,35,39), ToggleOff2=Color3.fromRGB(35,35,39),
        InputBg=Color3.fromRGB(22,22,25), SliderBg=Color3.fromRGB(30,30,34),
        BlacklistHover=Color3.fromRGB(50,20,20), BlacklistLeave=Color3.fromRGB(26,26,29),
        OutlineTransparency=0.7,
    },
    Cyber = {
        Background=Color3.fromRGB(10,14,20), MainBackground=Color3.fromRGB(7,10,15),
        Panel=Color3.fromRGB(13,18,26), Row=Color3.fromRGB(18,24,34), RowHover=Color3.fromRGB(26,34,46),
        Accent=Color3.fromRGB(59,130,246), AccentLight=Color3.fromRGB(96,165,250),
        Green=Color3.fromRGB(59,130,246), Red=Color3.fromRGB(244,114,182), Red2=Color3.fromRGB(236,72,153),
        Text=Color3.fromRGB(240,245,255), Dim=Color3.fromRGB(100,116,139), Stroke=Color3.fromRGB(30,41,59),
        SoftButton=Color3.fromRGB(18,24,34), SoftButtonHover=Color3.fromRGB(26,34,46),
        SoftAccent=Color3.fromRGB(20,30,46), SoftAccentHover=Color3.fromRGB(26,38,56),
        ToggleOff=Color3.fromRGB(30,36,46), ToggleOff2=Color3.fromRGB(30,36,46),
        InputBg=Color3.fromRGB(14,18,26), SliderBg=Color3.fromRGB(24,32,46),
        BlacklistHover=Color3.fromRGB(60,20,20), BlacklistLeave=Color3.fromRGB(24,30,40),
        OutlineTransparency=0.25, CornerAccents=true,
    },
    -- Style inspire du panneau "Vampire Ping Bypass" (rouge/noir, pas le code, juste
    -- la palette) -- applique a TOUS les panneaux du hub via ce theme partage.
    Vampire = {
        Background=Color3.fromRGB(18,10,14), MainBackground=Color3.fromRGB(12,6,9),
        Panel=Color3.fromRGB(10,6,8), Row=Color3.fromRGB(24,14,18), RowHover=Color3.fromRGB(34,20,26),
        Accent=Color3.fromRGB(244,114,182), AccentLight=Color3.fromRGB(249,168,212),
        Green=Color3.fromRGB(140,30,30), Red=Color3.fromRGB(244,114,182), Red2=Color3.fromRGB(236,72,153),
        Text=Color3.fromRGB(245,235,238), Dim=Color3.fromRGB(150,120,128), Stroke=Color3.fromRGB(80,30,38),
        SoftButton=Color3.fromRGB(30,16,22), SoftButtonHover=Color3.fromRGB(40,22,30),
        SoftAccent=Color3.fromRGB(40,22,30), SoftAccentHover=Color3.fromRGB(50,28,36),
        ToggleOff=Color3.fromRGB(30,16,22), ToggleOff2=Color3.fromRGB(30,16,22),
        InputBg=Color3.fromRGB(10,6,8), SliderBg=Color3.fromRGB(40,22,30),
        BlacklistHover=Color3.fromRGB(80,20,20), BlacklistLeave=Color3.fromRGB(30,16,22),
        OutlineTransparency=0.3, CornerAccents=true,
    },
}
Theme = {}
for k, v in pairs(Themes.Light) do
    Theme[k] = v
end

function applyTheme(themeName)
    local fromTheme = {}
    for k, v in pairs(Theme) do
        fromTheme[k] = v
    end
    
    local toTheme = Themes[themeName] or Themes.Light
    for k, v in pairs(toTheme) do
        Theme[k] = v
    end
    local isTerminal = (themeName == "Terminal")

    -- Helper 1: Explicitly style panels to avoid color collision bugs
    local function updatePanelTheme(f, isMain)
        if not f then return end
        f.BackgroundColor3 = isMain and toTheme.MainBackground or toTheme.Background
        for _, child in ipairs(f:GetChildren()) do
            if child:IsA("UIStroke") then
                child.Color = toTheme.AccentLight
            elseif child:IsA("Frame") then
                if child.Size == UDim2.new(1,-24,0,1) then
                    child.BackgroundColor3 = toTheme.AccentLight
                elseif child.BackgroundTransparency == 1 and child.Size == UDim2.new(1,0,0,42) then
                    for _, sub in ipairs(child:GetChildren()) do
                        if sub:IsA("TextLabel") then
                            if sub.TextSize == 16 or sub.TextSize == 12 then
                                sub.TextColor3 = toTheme.Text
                                if isTerminal then sub.Font = Enum.Font.Code end
                            elseif sub.TextSize == 10 then
                                sub.TextColor3 = toTheme.Dim
                                if isTerminal then sub.Font = Enum.Font.Code end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Helper 2: Explicitly style bottom bar
    local function updateBottomBarTheme()
        if not bottomBar then return end
        bottomBar.BackgroundColor3 = toTheme.Background
        for _, child in ipairs(bottomBar:GetChildren()) do
            if child:IsA("UIStroke") then
                child.Color = toTheme.AccentLight
            elseif child:IsA("TextLabel") then
                if child.Text == "IDF HUB PRIVAT" or child.Text == "|" or child.Text == "discord.gg/idfhub" then
                    child.TextColor3 = toTheme.AccentLight
                    if isTerminal then child.Font = Enum.Font.Code end
                elseif child.Text == "By:@SE67 and @SXLVATORE" then
                    child.TextColor3 = toTheme.Dim
                    if isTerminal then child.Font = Enum.Font.Code end
                end
            elseif child:IsA("Frame") then
                if child.Size == UDim2.new(0,1,0,36) then
                    child.BackgroundColor3 = toTheme.Accent
                elseif child.Name == "BrandRow" then
                    local w = child:FindFirstChild("BrandWhite"); if w then w.TextColor3 = toTheme.Text; if isTerminal then w.Font = Enum.Font.Code end end
                    local a = child:FindFirstChild("BrandAccent"); if a then a.TextColor3 = toTheme.Accent; if isTerminal then a.Font = Enum.Font.Code end end
                end
            end
        end
    end

    -- Helper 3: Explicitly style admin panel rows
    local function updateAdminPanelTheme()
        if not apBG then return end
        apBG.BackgroundColor3 = toTheme.Background
        local idx = 0
        for uid, row in pairs(apRows) do
            if row and row.Parent then
                idx = idx + 1
                local isAlt = (idx % 2 == 0)
                local rowCol = isAlt and toTheme.Row or toTheme.Panel
                row.BackgroundColor3 = rowCol
                local plr = Players:GetPlayerByUserId(uid)
                local isBlacklisted = isPlayerBlacklisted and isPlayerBlacklisted(plr)
                for _, child in ipairs(row:GetChildren()) do
                    if child:IsA("Frame") then
                        if child.Size == UDim2.fromOffset(34,34) then
                            child.BackgroundColor3 = toTheme.InputBg
                            local stroke = child:FindFirstChildOfClass("UIStroke")
                            if stroke then stroke.Color = toTheme.Accent end
                        elseif child.ZIndex == 12 then
                            for _, btn in ipairs(child:GetChildren()) do
                                if btn:IsA("TextButton") then
                                    if btn.Name == "BlacklistBtn" then
                                        btn.BackgroundColor3 = isBlacklisted and Color3.fromRGB(255, 60, 60) or toTheme.BlacklistLeave
                                    else
                                        btn.BackgroundColor3 = toTheme.SoftButton
                                    end
                                end
                            end
                        end
                    elseif child:IsA("TextLabel") then
                        if child.TextSize == 14 then
                            child.TextColor3 = toTheme.Text
                        elseif child.TextSize == 10 then
                            child.TextColor3 = toTheme.Dim
                        elseif child.TextSize == 11 then
                            child.TextColor3 = toTheme.AccentLight
                        end
                    end
                end
            end
        end
    end

    -- Run explicit styling on all static panels
    pcall(function()
        updatePanelTheme(main, true)
        updateBottomBarTheme()
        updateAdminPanelTheme()
        for _, name in ipairs({"Invisible Steal Panel", "Admin Command Panel", "Command Cooldowns", "Actions", "Steal Panel", "Steal Target"}) do
            updatePanelTheme(panels[name], false)
        end
        updatePanelTheme(actionSettingsPanel, false)
        updatePanelTheme(tpSpeedSettingsPanel, false)
    end)
    
    -- Fallback/Recursive styling for other dynamic frames (excluding mainBody descendants!)
    local function updateInstanceColors(inst)
        local shouldStyle = true
        if inst:IsA("GuiObject") or inst:IsA("UIStroke") then
            -- AVOID COLOR COLLISION BUG: Skip styling anything inside the tab mainBody dynamically
            if mainBody and inst:IsDescendantOf(mainBody) then return end
            
            -- Avoid updating main structures explicitly styled above
            if inst == main or inst == bottomBar or inst == apBG then
                shouldStyle = false
            end
            for _, p in ipairs({"Invisible Steal Panel", "Admin Command Panel", "Command Cooldowns", "Actions", "Steal Panel", "Steal Target"}) do
                if inst == panels[p] then
                    shouldStyle = false
                end
            end
            if inst == actionSettingsPanel or inst == tpSpeedSettingsPanel then
                shouldStyle = false
            end

            if shouldStyle then
                local bgKeys = {
                    Background=true, MainBackground=true, Panel=true, Row=true, RowHover=true,
                    SoftButton=true, SoftButtonHover=true, SoftAccent=true, SoftAccentHover=true,
                    ToggleOff=true, ToggleOff2=true, InputBg=true, SliderBg=true,
                    BlacklistHover=true, BlacklistLeave=true,
                    Green=true, Red=true, Red2=true, Accent=true, AccentLight=true
                }
                local textKeys = {
                    Text=true, Dim=true, Accent=true, AccentLight=true,
                    Green=true, Red=true, Red2=true, Stroke=true
                }
                local properties = {
                    BackgroundColor3 = bgKeys,
                    TextColor3 = textKeys,
                    PlaceholderColor3 = textKeys,
                    Color = textKeys
                }
                
                for prop, allowedKeys in pairs(properties) do
                    pcall(function()
                        local current = inst[prop]
                        if typeof(current) == "Color3" then
                            -- PROTECT WHITE TEXT ON SPECIFIC BUTTONS FROM THEME CONVERSION
                            if prop == "TextColor3" and inst.Name == "WhiteTextBtn" then
                                return
                            end
                            if prop == "BackgroundColor3" and inst.Name == "WhiteSliderKnob" then
                                return
                            end
                            for k, val in pairs(fromTheme) do
                                if allowedKeys[k] then
                                    if (current.R - val.R)^2 + (current.G - val.G)^2 + (current.B - val.B)^2 < 0.0001 then
                                        inst[prop] = toTheme[k]
                                        break
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end
        for _, child in ipairs(inst:GetChildren()) do
            updateInstanceColors(child)
        end
    end
    
    pcall(function()
        local sg = playerGui:FindFirstChild("SXEHub_V3")
        if sg then updateInstanceColors(sg) end
        if _G.updateLogoImage then
            _G.updateLogoImage(themeName == "Dark")
        end
    end)
    pcall(function()
        local ExploitGui = (gethui and gethui()) or game:GetService("CoreGui")
        local sg = ExploitGui:FindFirstChild("XiPriorityAlertTest")
        if sg then updateInstanceColors(sg) end
    end)
    for _, name in ipairs({"SXE_RemoteSell", "SXE_StealProgressBar", "XiAdminPanel"}) do
        pcall(function()
            local otherSg = playerGui:FindFirstChild(name)
            if otherSg then updateInstanceColors(otherSg) end
        end)
    end
    
    -- Force specific buttons that must always have white text to keep Color3.new(1,1,1)
    local function forceWhiteText(inst)
        if inst:IsA("TextButton") then
            local txt = inst.Text
            if txt == "ON" or txt == "OFF" or txt == "ADD" or txt == "X" or txt == "▲" or txt == "▼" then
                inst.TextColor3 = Color3.new(1, 1, 1)
            elseif inst.Size == UDim2.new(0, 50, 0, 20) then -- Keybind bind button
                inst.TextColor3 = Color3.new(1, 1, 1)
            end
        elseif inst:IsA("Frame") and inst.Name == "WhiteSliderKnob" then
            inst.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        end
        for _, child in ipairs(inst:GetChildren()) do
            forceWhiteText(child)
        end
    end
    
    pcall(function()
        local sg = playerGui:FindFirstChild("SXEHub_V3")
        if sg then forceWhiteText(sg) end
    end)
    
    if Config then
        Config.DarkMode = (themeName == "Dark")
        if saveConfig then saveConfig() end
    end
    pcall(function() if rebuildActions then rebuildActions() end end)
    pcall(function() if rebuildActionSettings then rebuildActionSettings() end end)
    pcall(function() if rebuildTpSpeedSettings then rebuildTpSpeedSettings() end end)
    pcall(function() if loadTab then loadTab(UI.CurrentTab) end end)
end
_G.applyTheme = applyTheme
pcall(applyTheme, "Vampire")

local UI = {Locked=false, OpenMenuKey=Enum.KeyCode.LeftControl, CurrentTab="Auto TP"}

Keybinds = {
    Kick="Y",["Rejoin Job ID"]="J",Clone="F",["Manual TP"]="T",["Invisible Steal"]="U",
    ["Job ID"]="K",Proximity="P",["Carpet Boost"]="Q",["Open Menu"]="LeftControl",
    ["Ragdoll Self"]="R",["Drop Brainrot"]="G",Float="Z",Reset="X",["Auto Buy"]="K",
    ["Click to AP"]="NONE"
}

priorityList = {
    "Strawberry Elephant",
    "Meowl",
    "Skibidi Toilet",
    "Headless Horseman",
    "Dragon Gingerini",
    "Dragon Cannelloni",
    "Ketupat Bros",
    "Hydra Dragon Cannelloni",
    "La Supreme Combinasion",
    "Love Love Bear",
    "Ginger Gerat",
    "Cerberus",
    "Capitano Moby",
    "La Casa Boo",
    "Burguro and Fryuro",
    "Spooky and Pumpky",
    "Cooki and Milki",
    "Rosey and Teddy",
    "Popcuru and Fizzuru",
    "Reinito Sleighito",
    "Fragrama and Chocrama",
    "Garama and Madundung",
    "Ketchuru and Musturu",
    "La Secret Combinasion",
    "Tralaledon",
    "Tictac Sahur",
    "Ketupat Kepat",
    "Tang Tang Keletang",
    "Orcaledon",
    "La Ginger Sekolah",
    "Los Spaghettis",
    "Lavadorito Spinito",
    "Swaggy Bros",
    "La Taco Combinasion",
    "Los Primos",
    "Los Chillis",
    "Chillin Chili",
    "Tuff Toucan",
    "W or L",
    "Chipso and Queso",
    "Signore Carapace",
    "Arcadragon",
    "John Pork",
    "Elefanto Frigo",
    "Antonio",
    "Pancake and Syrup",
    "Griffin",
    "Kalika Bros",
    "Globa Steppa",
    "Fishino Clownino",
    "Rico Dinero",
    "Tirilikalika Tirilikalako",
    "Digi Narwhal",
    "Hydra Bunny",
    "Dug dug dug",
    "Bunny and Eggy",
    "Los Hackers",
    "Duggy Bros",
    "Guest 666",
    "Money Money Reindeer",
    "Foxini Lanternini",
    "Fragola La La La",
    "Quackini Snackini",
    "Los Sekolahs",
    "Los Tacoritas",
    "Los Amigos",
    "Fortunu and Cashuru",
    "Jolly Jolly Sahur",
    "Boppin Bunny",
    "Gym Bros",
    "Los Cupids",
    "Festive 67",
    "Celularcini Viciosini",
    "Cloverat Clapat",
    "La Food Combinasion",
    "Hopilikalika Hopilikalako",
    "Celestial Pegasus",
    "Sammyni Fattini",
    "Money Money Bros",
    "La Spooky Grande",
    "Cash or Card",
    "Swag Soda",
    "Los Planitos",
    "Lovin Rose",
    "Tacorita Bicicleta",
    "Los Jolly Combinasionas",
    "La Romantic Grande",
    "La Easter Grande",
    "Los Hotspotsitos",
    "Rosetti Tualetti",
    "Los Bros",
    "Gobblino Uniciclino",
    "Chicleteira Cupideira",
    "La Extinct Grande",
    "Las Sis",
    "Nacho Spyder",
    "Gold Gold Gold",
    "Los Mariachis",
    "Snailo Clovero",
    "La Jolly Grande",
    "Los Candies",
    "Churrito Bunnito",
    "Bananito",
    "Eviledon",
    "Los 67",
    "Los Sweethearts",
    "Noo my Heart",
    "La Lucky Grande",
    "Ventoliero Pavonero",
    "Baskito",
    "Chimnino",
    "Los Puggies",
    "Camera Ramena",
    "Los 25",
    "Spinny Hammy",
    "Money Money Puggy",
    "Cigno Fulgoro",
    "Los Spooky Combinasionas",
    "Chicleteira Noelteira",
    "Mariachi Corazoni",
    "Tacorillo Crocodillo",
    "Noo my Gold",
    "Los Mobilis",
    "Mieteteira Bicicleteira",
    "DJ Panda",
    "Los Combinasionas",
    "Nuclearo Dinossauro",
    "Bacuru and Egguru",
    "Spaghetti Tualetti",
    "La Grande Combinasion",
    "Esok Sekolah"
}

actionConfig = {
    ["Ragdoll Self (R)"]=true,["Rejoin PS"]=true,["Rejoin Job ID (J)"]=true,
    ["Kick (Y)"]=true,["Kick To Private"]=true,["Reset (X)"]=true,
    ["Anti Ragdoll"]=false,["Infinite Jump"]=false,["Float"]=false,["Carpet Speed"]=false,
}

-- CONFIG (merged)
local CONFIG_FILE = "sxe_hub_v3_config.json"
local PS_CODE_FILE = "sxe_hub_pscode.txt"
PrivateServerCode = ""

local function loadPSCode()
    pcall(function() if typeof(readfile)=="function" and typeof(isfile)=="function" and isfile(PS_CODE_FILE) then PrivateServerCode = readfile(PS_CODE_FILE) end end)
end
local function savePSCode()
    pcall(function() if typeof(writefile)=="function" then writefile(PS_CODE_FILE, PrivateServerCode or "") end end)
end
loadPSCode()

Config = {
    positions={},keybinds={},actions={},locked=false,
    DarkMode=false,
    AntiRagdoll=false,InfiniteJump=false,Float=false,
    AutoResetBalloon=false,AutoKickOnSteal=false,KickToPrivateServer=false,CleanErrorGUIs=false,
    LineToBase=false,LineToBrainrot=false,InvisStealAngle=225,SinkSliderValue=7,
    AutoRecoverLagback=true,
    WalkSpeedEnabled=false, WalkSpeedValue=16,
    AutoTPPriority=true, AutoTPHighestGen=false, AutoTPHighestValue=false, FPSBoost=false, FPSBoostUltra=false, XRay=false, FOV=70,
    BrainrotESP=true, TimerESP=false, SubspaceMineESP=false, PlayerESP=true, BaseOwnerESP=false,
    AutoBuyEnabled=false, AutoBuyRange=17, AutoGrabSpeed=17, AutoBuyKey="K",
    AutoDestroyTurrets=false, AutoUnlockOnSteal=false,
    AutoInvisDuringSteal=false,
    ClickToAP=false, ClickToAPSingleCommand=false,
    ClickToAPRadius=8,
    SpamBaseOwnerCommands={balloon=true, inverse=true, jail=true, jumpscare=true, morph=true, nightvision=true, ragdoll=true, rocket=true, tiny=true},
    SpamBaseOwnerOrder={"balloon", "inverse", "jail", "jumpscare", "morph", "nightvision", "ragdoll", "rocket", "tiny"},
    SpamBaseOwnerSingleCommand=false,
    ProximityAP=false, ShowJobJoiner=true, AntiBeeDisco=false,
    RemoteSellEnabled=false, AdminPanelUI=true,
    StealHighest=true, StealPriority=false, StealNearest=false,
    AutoStealEnabled=true,
    Unwalk=false,
    Visibilities = {
        ["Invisible Steal Panel"] = true,
        ["Admin Command Panel"] = true,
        ["Command Cooldowns"] = true,
        ["Actions"] = true,
        ["Steal Panel"] = true,
        ["Steal Target"] = true,
    },
    TpSettings = {
        Tool="Flying Carpet", TpKey="T", CloneKey="V", CarpetSpeedKey="Q",
        InfiniteJump=false, DelayVal=0.4, CloneDelayVal=0.1,
        RagdollTP=false, FPSWait=false, FlyTP=false, FlyTPSpeed=160, FlyTPCloseSpeed=75,
        GrabbleTP=false, GrabbleTPSpeed=230,
        TpOnLoad=false, MinGenForTp="", MinGenForGrab="",
        BrainrotCarpet=false,
    },
    PriorityList=priorityList,
    RemovedFromPriority={},
}

local suffixes = {
    k = 1e3,
    m = 1e6,
    b = 1e9,
    t = 1e12,
    q = 1e15,
    qi = 1e18,
    qd = 1e18,
    qn = 1e18,
    sx = 1e21,
    sp = 1e24,
    oc = 1e27,
    no = 1e30,
    dc = 1e33,
    ud = 1e36,
    dd = 1e39,
    td = 1e42,
    qad = 1e45,
    qid = 1e48,
    sxd = 1e51,
    spd = 1e54,
    ocd = 1e57,
    nod = 1e60,
    vg = 1e63,
}

local function parseMinGen(str)
    if not str or type(str) ~= "string" then return 0 end
    str = str:gsub("%s", ""):lower():gsub("/s$", "")
    if str == "" then return 0 end
    local numStr, suffix = str:match("^([%d%.]+)(%a*)$")
    if not numStr then return 0 end
    local num = tonumber(numStr)
    if not num or num < 0 then return 0 end
    if suffix ~= "" then
        local mult = suffixes[suffix]
        if mult then
            return num * mult
        end
    end
    return num
end

local function canUseFiles() return typeof(readfile)=="function" and typeof(writefile)=="function" and typeof(isfile)=="function" end
loadConfig = function()
    if not canUseFiles() then return end
    local ok,data=pcall(function() if isfile(CONFIG_FILE) then return HttpService:JSONDecode(readfile(CONFIG_FILE)) end end)
    if ok and type(data)=="table" then
        for k,v in pairs(data) do
            if k == "PriorityList" or k == "RemovedFromPriority" then
                Config[k] = v
            elseif type(v) == "table" and type(Config[k]) == "table" then
                for subk, subv in pairs(v) do
                    Config[k][subk] = subv
                end
            else
                Config[k] = v
            end
        end
        if type(Config.positions)~="table" then Config.positions={} end
        if type(Config.keybinds)~="table" then Config.keybinds={} end
        if type(Config.actions)~="table" then Config.actions={} end
        if type(Config.RemovedFromPriority)~="table" then Config.RemovedFromPriority={} end
        local removedSet = {}
        for _, rn in ipairs(Config.RemovedFromPriority) do removedSet[rn] = true end
        if type(Config.PriorityList)=="table" then
            if #Config.PriorityList == 0 then
                Config.PriorityList = priorityList
            else
                local present = {}
                for _, name in ipairs(Config.PriorityList) do
                    present[name] = true
                end
                for _, name in ipairs(priorityList) do
                    if not present[name] and not removedSet[name] then
                        table.insert(Config.PriorityList, name)
                    end
                end
                priorityList = Config.PriorityList
            end
        else
            Config.PriorityList = priorityList
        end
        -- Deduplicate priority list
        if type(Config.PriorityList) == "table" then
            local seen = {}
            local cleanList = {}
            for _, name in ipairs(Config.PriorityList) do
                if not seen[name] then
                    seen[name] = true
                    table.insert(cleanList, name)
                end
            end
            Config.PriorityList = cleanList
            priorityList = cleanList
        end
    end
end
saveConfig = function()
    if not canUseFiles() then return end
    task.spawn(function() pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(Config)) end) end)
end

-- BASE64 ENCODER/DECODER FOR CONFIG SHARING (Wrapped in do-scope to save global registers)
do
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local function base64Encode(data)
        local len = #data
        local t = {}
        for i = 1, len, 3 do
            local a = data:byte(i)
            local b = data:byte(i + 1) or 0
            local c = data:byte(i + 2) or 0
            local n = a * 65536 + b * 256 + c
            t[#t + 1] = b64chars:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
            t[#t + 1] = b64chars:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
            t[#t + 1] = (i + 1 <= len) and b64chars:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1) or "="
            t[#t + 1] = (i + 2 <= len) and b64chars:sub(n % 64 + 1, n % 64 + 1) or "="
        end
        return table.concat(t)
    end

    local function base64Decode(data)
        data = data:gsub('[^' .. b64chars .. '=]', '')
        local len = #data
        local t = {}
        local lookup = {}
        for i = 1, 64 do lookup[b64chars:sub(i, i)] = i - 1 end
        local i = 1
        while i <= len do
            local c1 = lookup[data:sub(i, i)]
            local c2 = lookup[data:sub(i + 1, i + 1)]
            local s3 = data:sub(i + 2, i + 2)
            local s4 = data:sub(i + 3, i + 3)
            local c3 = lookup[s3]
            local c4 = lookup[s4]
            if not c1 or not c2 then break end
            local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
            t[#t + 1] = string.char(math.floor(n / 65536))
            if s3 ~= "=" then
                t[#t + 1] = string.char(math.floor(n / 256) % 256)
            end
            if s4 ~= "=" then
                t[#t + 1] = string.char(n % 256)
            end
            i = i + 4
        end
        return table.concat(t)
    end

    _G.importConfig = function(str)
        if not str or str == "" then
            ShowNotification("IMPORT ERROR", "Config string is empty")
            return false
        end
        
        local success, parsed = pcall(function()
            return HttpService:JSONDecode(str)
        end)
        
        if not success or type(parsed) ~= "table" then
            local decoded
            pcall(function() decoded = base64Decode(str:gsub("%s", "")) end)
            if decoded then
                success, parsed = pcall(function() return HttpService:JSONDecode(decoded) end)
            end
        end

        if not success or type(parsed) ~= "table" then
            ShowNotification("IMPORT ERROR", "Invalid config data")
            return false
        end

        for k, v in pairs(parsed) do
            Config[k] = v
        end
        
        if type(Config.PriorityList) == "table" then priorityList = Config.PriorityList end
        
        saveConfig()

        for k, v in pairs(Config.keybinds or {}) do
            if Keybinds[k] ~= nil and type(v) == "string" then
                Keybinds[k] = v
                if k == "Open Menu" and Enum.KeyCode[v] then
                    UI.OpenMenuKey = Enum.KeyCode[v]
                end
            end
        end

        for k, v in pairs(Config.actions or {}) do
            if actionConfig[k] ~= nil then
                actionConfig[k] = v and true or false
            end
        end

        if type(Config.locked) == "boolean" then
            UI.Locked = Config.locked
        end

        initToggles()

        if setFPSBoost then pcall(setFPSBoost, Config.FPSBoost) end
        if setFPSBoostUltra then pcall(setFPSBoostUltra, Config.FPSBoostUltra) end
        if setXRay then pcall(setXRay, Config.XRay) end
        if setInfiniteJump then pcall(setInfiniteJump, Config.InfiniteJump) end
        if setFloat then pcall(setFloat, Config.Float) end
        if setCarpetSpeed then pcall(setCarpetSpeed, Config.CarpetSpeed or false) end
        -- ProximityAP always starts OFF, never loaded from config
    Config.ProximityAP = false
        if toggleAutoBuy then pcall(toggleAutoBuy, Config.AutoBuyEnabled) end
        if setStealMode then
            if Config.StealHighest then pcall(setStealMode, "Highest")
            elseif Config.StealPriority then pcall(setStealMode, "Priority")
            elseif Config.StealNearest then pcall(setStealMode, "Nearest")
            end
        end
        if updateMovementPanelLabels then pcall(updateMovementPanelLabels) end

        rebuildActions()
        rebuildActionSettings()
        loadTab(UI.CurrentTab)

        ShowNotification("CONFIG SYSTEM", "Config imported successfully!")
        return true
    end

    _G.exportConfig = function()
        local ok, str = pcall(function()
            return HttpService:JSONEncode(Config)
        end)
        if not ok or not str then
            ShowNotification("EXPORT ERROR", "Failed to encode config")
            return nil
        end
        local cbSuccess = false
        if typeof(setclipboard) == "function" then
            pcall(function() setclipboard(str); cbSuccess = true end)
        elseif typeof(toclipboard) == "function" then
            pcall(function() toclipboard(str); cbSuccess = true end)
        end
        if cbSuccess then
            ShowNotification("CONFIG SYSTEM", "Config copied to clipboard!")
        else
            ShowNotification("CONFIG SYSTEM", "Config generated! Copy from share box.")
        end
        return str
    end
end
local function serializePos(pos) return {xs=pos.X.Scale,xo=pos.X.Offset,ys=pos.Y.Scale,yo=pos.Y.Offset} end
local function rememberPosition(name, frame) if not name or not frame then return end; Config.positions[name]=serializePos(frame.Position); saveConfig() end
local function applySavedPosition(name, frame)
    if not name or not frame then return end; local d=Config.positions and Config.positions[name]
    if d then frame.Position=UDim2.new(d.xs or 0,d.xo or 0,d.ys or 0,d.yo or 0) end
end
local function initToggles()
    setToggle("Anti Ragdoll", Config.AntiRagdoll, true)
    setToggle("Auto Reset Balloon", Config.AutoResetBalloon, true)
    setToggle("Infinite Jump", Config.InfiniteJump, true)
    setToggle("Auto Kick", Config.AutoKickOnSteal, true)
        setToggle("Auto Buy", Config.AutoBuyEnabled, true)
    setToggle("Auto Steal", Config.AutoStealEnabled, true)
    setToggle("Steal Highest", Config.StealHighest, true)
    setToggle("Steal Priority", Config.StealPriority, true)
    setToggle("Steal Nearest", Config.StealNearest, true)
    setToggle("Click to AP", Config.ClickToAP, true)
    setToggle("ClickToAP", Config.ClickToAP, true)
    setToggle("Click AP Single Cmd", Config.ClickToAPSingleCommand, true)
    setToggle("ClickToAPSingle", Config.ClickToAPSingleCommand, true)
    setToggle("FPS Boost (normal)", Config.FPSBoost, true)
    setToggle("FPS Boost (normal)", Config.FPSBoost, true)
    setToggle("FPS Boost Ultra", Config.FPSBoostUltra, true)
    setToggle("FPSBoostUltra", Config.FPSBoostUltra, true)
    setToggle("XRay", Config.XRay, true)
    setToggle("X-Ray", Config.XRay, true)
    setToggle("Xray", Config.XRay, true)
    setToggle("Proximity", Config.ProximityAP, true)

    setToggle("Player ESP", Config.PlayerESP, true)
    setToggle("Brainrot ESP", Config.BrainrotESP, true)
    setToggle("Timer ESP", Config.TimerESP, true)
    setToggle("Subspace Mine ESP", Config.SubspaceMineESP, true)
    setToggle("Base Owner ESP", Config.BaseOwnerESP, true)
    setToggle("Float", Config.Float, true)
    setToggle("Anti-Bee & Anti-Disco", Config.AntiBeeDisco, true)
    setToggle("AntiBeeDisco", Config.AntiBeeDisco, true)
    setToggle("Admin Panel UI", Config.AdminPanelUI, true)
    setToggle("Auto Invis During Steal", Config.AutoInvisDuringSteal, true)
    setToggle("Auto TP Priority Mode", Config.AutoTPPriority, true)
    setToggle("Auto TP Highest Gen", Config.AutoTPHighestGen, true)
    setToggle("Auto TP Highest Value", Config.AutoTPHighestValue, true)
    setToggle("Unwalk", Config.Unwalk, true)
    setToggle("Stealing ESP", Config.StealingESP, true)
    setToggle("WalkSpeed", Config.WalkSpeedEnabled, true)
    setToggle("Dark Mode", Config.DarkMode, true)
    setToggle("DarkMode", Config.DarkMode, true)
    setToggle("Grabble TP", Config.TpSettings.GrabbleTP or false, true)
end

loadConfig()
if Config.DarkMode then
    for k, v in pairs(Themes.Dark) do
        Theme[k] = v
    end
end
for k,v in pairs(Config.keybinds or {}) do if Keybinds[k]~=nil and type(v)=="string" then Keybinds[k]=v; if k=="Open Menu" and Enum.KeyCode[v] then UI.OpenMenuKey=Enum.KeyCode[v] end end end
for k,v in pairs(Config.actions or {}) do if actionConfig[k]~=nil then actionConfig[k]=v and true or false end end
if type(Config.locked)=="boolean" then UI.Locked=Config.locked end
initToggles()

-- SYNCHRONIZER DETECTION BYPASS + STEALTH CHANNEL READER 
pcall(function()
    local getupvalue = getupvalue or debug.getupvalue

    local function getInternalTable()
        local Packages = ReplicatedStorage:FindFirstChild("Packages")
        if not Packages then return nil end
        local SynMod = Packages:FindFirstChild("Synchronizer")
        if not SynMod then return nil end
        local ok, syn = pcall(require, SynMod)
        if not ok or not syn then return nil end
        local Get = syn.Get
        if type(Get) ~= "function" then return nil end
        for i = 1, 5 do
            local s, u = pcall(getupvalue, Get, i)
            if s and type(u) == "table" then
                if u.___private or u.___channels or u.___data then return u end
                for k, v in pairs(u) do
                    if (type(k) == "string" and k:match("^Plot_")) or type(v) == "table" then
                        return u
                    end
                end
            end
        end
        local s, e = pcall(getfenv, Get)
        if s and e and e.self then return e.self end
        return nil
    end

    local SyncInt = {_cache = {}, _data = nil}
    _G.SyncInt = SyncInt

    task.spawn(function()
        for i = 1, 10 do
            SyncInt._data = getInternalTable()
            if SyncInt._data then break end
            task.wait(1)
        end
    end)

    local function myCustomGet(self, prop)
        if self[prop] then return self[prop] end
        for _, sub in ipairs({"CacheTable", "Data", "_data", "state", "values"}) do
            if type(self[sub]) == "table" and self[sub][prop] then
                return self[sub][prop]
            end
        end
        local alts = {
            Owner = {"owner", "Owner", "plotOwner", "PlotOwner"},
            AnimalList = {"animalList", "AnimalList", "animals", "Animals", "pets"},
        }
        if alts[prop] then
            for _, a in ipairs(alts[prop]) do
                if self[a] then return self[a] end
                for _, sub in ipairs({"CacheTable", "Data", "_data", "state", "values"}) do
                    if type(self[sub]) == "table" and self[sub][a] then
                        return self[sub][a]
                    end
                end
            end
        end
        return nil
    end

    function _G.stealthGet(n)
        if not n or type(n) ~= "string" then return nil end
        if SyncInt._cache[n] == false then return nil end
        local res = nil
        if SyncInt._data then
            for _, k in ipairs({n, "Plot_" .. n, "Plot" .. n, n .. "_Channel", "Channel_" .. n}) do
                if SyncInt._data[k] then
                    res = SyncInt._data[k]
                    break
                end
            end
            if not res then
                for k, v in pairs(SyncInt._data) do
                    if type(k) == "string" and (k == n or k:find(n, 1, true)) and type(v) == "table" then
                        res = v
                        break
                    end
                end
            end
        end
        if res and type(res) == "table" then
            if type(res.Get) ~= "function" then
                rawset(res, "Get", myCustomGet)
            end
            SyncInt._cache[n] = res
            return res
        end
        SyncInt._cache[n] = false
        return nil
    end

    function _G.sProp(ch, p)
        if not ch or type(ch) ~= "table" then return nil end
        if ch[p] then return ch[p] end
        for _, sub in ipairs({"CacheTable", "Data", "_data", "state", "values"}) do
            if type(ch[sub]) == "table" and ch[sub][p] then
                return ch[sub][p]
            end
        end
        if type(ch.Get) == "function" and ch.Get ~= myCustomGet then
            local ok, r = pcall(ch.Get, ch, p)
            if ok then return r end
        end
        local alts = {
            Owner = {"owner", "Owner", "plotOwner", "PlotOwner"},
            AnimalList = {"animalList", "AnimalList", "animals", "Animals", "pets"},
        }
        if alts[p] then
            for _, a in ipairs(alts[p]) do
                if ch[a] then return ch[a] end
                for _, sub in ipairs({"CacheTable", "Data", "_data", "state", "values"}) do
                    if type(ch[sub]) == "table" and ch[sub][a] then
                        return ch[sub][a]
                    end
                end
            end
        end
        return nil
    end

    -- Setup value modification bypass
    local Packages = ReplicatedStorage:FindFirstChild("Packages")
    local SynMod = Packages and Packages:FindFirstChild("Synchronizer")
    local okReq, syn = pcall(require, SynMod)
    if okReq and typeof(syn) == "table" then
        local function HasBoolUpvalue(Fn)
            local OkU, Ups = xpcall(debug.getupvalues, function() end, Fn)
            if not OkU then return false end
            for _, V in pairs(Ups) do
                if typeof(V) == "boolean" then return true end
            end
            return false
        end
        for _, Fn in pairs(syn) do
            if typeof(Fn) == "function" and not isexecutorclosure(Fn) then
                local OkU, Ups = xpcall(debug.getupvalues, function() end, Fn)
                if OkU then
                    for Idx, V in pairs(Ups) do
                        if typeof(V) == "function" and not isexecutorclosure(V) and HasBoolUpvalue(V) then
                            pcall(debug.setupvalue, Fn, Idx, newcclosure(function() end))
                        end
                    end
                end
            end
        end

        -- Hook Get method directly to route through stealthGet
        -- local oldGet = syn.Get
        -- if oldGet then
        --     syn.Get = function(self, plotName)
        --         local ch = _G.stealthGet(plotName)
        --         if ch then return ch end
        --         return oldGet(self, plotName)
        --     end
        -- end
    end
end)




-- Decrypted net
local Decrypted=setmetatable({},{__index=function(S,ez)
    local ok,Netty=pcall(function() return ReplicatedStorage.Packages.Net end); if not ok or not Netty then return nil end
    if ez:sub(1,3)~="RE/" and ez:sub(1,3)~="RF/" then return nil end
    local Remote; for i,v in ipairs(Netty:GetChildren()) do if v.Name==ez then local children=Netty:GetChildren(); Remote=children[i+1]; break end end
    if Remote and not rawget(Decrypted,ez) then rawset(Decrypted,ez,Remote) end; return rawget(Decrypted,ez)
end})

-- COOLDOWN TRACKER
ACTION_COOLDOWNS = {ragdoll=30,jail=60,rocket=120,balloon=30,inverse=30,jumpscare=30,tiny=30,morph=30,nightvision=30}
local lastActionUse = {}

-- Read real timer from the game's AdminPanel UI
local function _readRealAdminTimer(cmd)
    local realAdminGui = playerGui:FindFirstChild("AdminPanel")
    if not realAdminGui then return nil end
    local ok, contentScroll = pcall(function() return realAdminGui.AdminPanel.Content.ScrollingFrame end)
    if not ok or not contentScroll then return nil end
    local cmdBtn = contentScroll:FindFirstChild(cmd)
    if not cmdBtn then return nil end
    local timerLabel = cmdBtn:FindFirstChild("Timer")
    if not timerLabel or not timerLabel.Visible then return 0 end
    local num = tonumber(timerLabel.Text:match("%d+"))
    return num or 0
end

local function apIsOnCooldown(cmd)
    local realTime = _readRealAdminTimer(cmd)
    if realTime ~= nil then return realTime > 0 end
    local l=lastActionUse[cmd]; local cd=ACTION_COOLDOWNS[cmd] or 0; return l and cd>0 and (tick()-l)<cd
end
local function apGetRemaining(cmd)
    local realTime = _readRealAdminTimer(cmd)
    if realTime ~= nil then return realTime end
    local l=lastActionUse[cmd]; local cd=ACTION_COOLDOWNS[cmd] or 0; if not l then return 0 end; return math.max(0,cd-(tick()-l))
end
local function apStartCooldown(cmd) lastActionUse[cmd]=tick() end
AP_ALL_COMMANDS={"balloon","inverse","jail","jumpscare","morph","nightvision","ragdoll","rocket","tiny"}
AP_COMMAND_EMOJIS={balloon="🎈",inverse="🔄",jail="🔒",jumpscare="👻",morph="🎭",nightvision="🌙",ragdoll="🌀",rocket="🚀",tiny="🐜"}
if not Config.ClickToAPCommands then
    Config.ClickToAPCommands = {}
    for _, cmd in ipairs(AP_ALL_COMMANDS) do Config.ClickToAPCommands[cmd] = true end
end
if not Config.AdminPanelButtons then
    Config.AdminPanelButtons = {ragdoll=true, jail=true, rocket=true, balloon=true}
end
if not Config.ClickToAPRadius then
    Config.ClickToAPRadius = 8
end
if not Config.SpamBaseOwnerCommands then
    Config.SpamBaseOwnerCommands = {}
    for _, cmd in ipairs(AP_ALL_COMMANDS) do Config.SpamBaseOwnerCommands[cmd] = true end
end
if not Config.SpamBaseOwnerOrder then
    Config.SpamBaseOwnerOrder = {}
    for i, cmd in ipairs(AP_ALL_COMMANDS) do Config.SpamBaseOwnerOrder[i] = cmd end
end
if Config.SpamBaseOwnerSingleCommand == nil then
    Config.SpamBaseOwnerSingleCommand = false
end
setToggle("SpamBaseOwnerSingleCommand", Config.SpamBaseOwnerSingleCommand or false)

_G.apBlacklist = Config.apBlacklist or {}

local function isPlayerBlacklisted(plr)
    if not plr then return false end
    local uid = plr.UserId
    return _G.apBlacklist[uid] == true or _G.apBlacklist[tostring(uid)] == true
end

-- Cached Synchronizer module. Re-requiring + WaitForChild on every call (inside
-- per-player loops) was a major admin-panel lag source; cache it once.
do
    local cached
    function _G.__getSync()
        if cached then return cached end
        local ok, mod = pcall(function()
            local pkgs = ReplicatedStorage:FindFirstChild("Packages")
            return pkgs and require(pkgs:WaitForChild("Synchronizer", 5))
        end)
        if ok then cached = mod end
        return cached
    end
end

-- NOTE: current-base-owner detection lives below as _G.__getCurrentBaseOwnerId,
-- right after getPlayerBaseInfo (it depends on getPlotAtPosition/getPlotOwner,
-- which are declared further down). Every player here owns their own base, so a
-- "who owns ANY base" check would (correctly but uselessly) flag everyone.

local function getPlotOwner(plot)
    if not plot then return nil end
    local Synchronizer = _G.__getSync()
    if Synchronizer then
        local ch = Synchronizer:Get(plot.Name)
        if ch then
            local owner = ch:Get("Owner")
            if owner then
                if typeof(owner) == "Instance" and owner:IsA("Player") then
                    return owner
                elseif type(owner) == "table" and owner.Name then
                    return Players:FindFirstChild(owner.Name)
                elseif type(owner) == "number" then
                    return Players:GetPlayerByUserId(owner)
                end
            end
        end
    end
    local sign = plot:FindFirstChild("PlotSign")
    local textLabel = sign
        and sign:FindFirstChild("SurfaceGui")
        and sign.SurfaceGui:FindFirstChild("Frame")
        and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")
    if textLabel then
        local baseText = textLabel.Text
        local nickname = (baseText and baseText:match("^(.-)'")) or baseText
        if nickname then
            for _, p in ipairs(Players:GetPlayers()) do
                if (p.DisplayName == nickname) or (p.Name == nickname) then
                    return p
                end
            end
        end
    end
    return nil
end

local function getPlotAtPosition(pos)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local closestPlot = nil
    local minDistance = math.huge
    for _, plot in ipairs(plots:GetChildren()) do
        local plotPos
        if plot:IsA("Model") then
            plotPos = plot.PrimaryPart and plot.PrimaryPart.Position or plot:GetPivot().Position
        else
            plotPos = plot.Position
        end
        if plotPos then
            local distH = math.sqrt((pos.X - plotPos.X)^2 + (pos.Z - plotPos.Z)^2)
            if distH < minDistance then
                minDistance = distH
                closestPlot = plot
            end
        end
    end
    if closestPlot and minDistance < 72 then
        return closestPlot
    end
    return nil
end

local function getPlayerBaseInfo(plr)
    if not plr or not plr.Character then return nil, nil end
    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end
    local plot = getPlotAtPosition(hrp.Position)
    if plot then
        return plot, getPlotOwner(plot)
    end
    return nil, nil
end

-- userId of the owner of the base the LOCAL player is currently standing in
-- (nil if none). Memoized ~0.4s and shared by all admin rows, so only ONE row
-- shows "Base Owner": the owner of the base you're actually in.
do
    local cachedId, lastT = nil, 0
    function _G.__getCurrentBaseOwnerId()
        local now = os.clock()
        if (now - lastT) < 0.4 then return cachedId end
        lastT = now
        cachedId = nil
        local _, owner = getPlayerBaseInfo(LocalPlayer)
        if owner then cachedId = owner.UserId end
        return cachedId
    end
end

local function getStealingInfo(plr)
    if not plr or not plr.Character then return nil, nil end
    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end
    
    local isPlayingAnim = false
    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        pcall(function()
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local id = track.Animation and track.Animation.AnimationId
                if id and (id:find("18537363391") or id:find("steal") or id:find("grab")) then
                    isPlayingAnim = true
                    break
                end
            end
        end)
    end
    
    local plots = Workspace:FindFirstChild("Plots")
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            local owner = getPlotOwner(plot)
            if owner == plr then continue end
            
            local podiums = plot:FindFirstChild("AnimalPodiums")
            if podiums then
                for _, pod in ipairs(podiums:GetChildren()) do
                    local base = pod:FindFirstChild("Base")
                    local spawn = base and base:FindFirstChild("Spawn")
                    if spawn then
                        local dist = (hrp.Position - spawn.Position).Magnitude
                        if (isPlayingAnim and dist < 12) or (dist < 4.5) then
                            local animalName = "Brainrot"
                            pcall(function()
                                local Synchronizer = _G.__getSync()
                                if Synchronizer then
                                    local ch = Synchronizer:Get(plot.Name)
                                    if ch then
                                        local al = ch:Get("AnimalList")
                                        local ad = al and (al[pod.Name] or al[tonumber(pod.Name)])
                                        if ad and type(ad) == "table" then
                                            local ok2, Datas = pcall(function() return ReplicatedStorage:FindFirstChild("Datas") end)
                                            local okA, AnimalsData = pcall(function() return require(Datas:FindFirstChild("Animals")) end)
                                            if okA and AnimalsData and AnimalsData[ad.Index] then
                                                animalName = AnimalsData[ad.Index].DisplayName or ad.Index
                                            else
                                                animalName = ad.Index
                                            end
                                        end
                                    end
                                end
                            end)
                            return owner, animalName
                        end
                    end
                end
            end
        end
    end
    
    local attrStealing = plr:GetAttribute("Stealing")
    if attrStealing then
        return nil, plr:GetAttribute("StealingIndex") or "Brainrot"
    end
    
    return nil, nil
end

-- ADMIN COMMAND BRIDGE
local function fireClick(button)
    if not button then return false end
    local ok=pcall(function()
        if typeof(firesignal)=="function" then
            pcall(firesignal, button.MouseButton1Click)
            pcall(firesignal, button.MouseButton1Down)
            pcall(firesignal, button.MouseButton1Up)
            pcall(firesignal, button.Activated)
        else
            local x=button.AbsolutePosition.X+(button.AbsoluteSize.X/2)
            local y=button.AbsolutePosition.Y+(button.AbsoluteSize.Y/2)+58
            VirtualInputManager:SendMouseButtonEvent(x,y,0,true,game,0)
            VirtualInputManager:SendMouseButtonEvent(x,y,0,false,game,0)
        end
    end); return ok
end
_G.fireClick=fireClick

local function runAdminCommand(targetPlayer, commandName)
    if not targetPlayer or not commandName or commandName=="" then return false end
    if isPlayerBlacklisted(targetPlayer) then 
        ShowNotification("BLOCKED", targetPlayer.DisplayName .. " is blacklisted")
        return false 
    end
    local realAdminGui=playerGui:FindFirstChild("AdminPanel")
    if not realAdminGui then realAdminGui=playerGui:WaitForChild("AdminPanel",3) end
    if not realAdminGui then return false end
    local wasEnabled = realAdminGui.Enabled
    realAdminGui.Enabled = true
    local okC,contentScroll=pcall(function() return realAdminGui.AdminPanel.Content.ScrollingFrame end)
    if not okC or not contentScroll then realAdminGui.Enabled=wasEnabled; return false end
    local cmdBtn=contentScroll:FindFirstChild(commandName); if not cmdBtn then realAdminGui.Enabled=wasEnabled; return false end
    fireClick(cmdBtn)
    task.wait(0.01)
    local okP,profilesScroll=pcall(function() return realAdminGui.AdminPanel.Profiles.ScrollingFrame end)
    if not okP or not profilesScroll then realAdminGui.Enabled=wasEnabled; return false end
    local playerBtn=profilesScroll:FindFirstChild(targetPlayer.Name)
    if not playerBtn then
        task.wait(0.01)
        playerBtn=profilesScroll:FindFirstChild(targetPlayer.Name)
    end
    if not playerBtn then
        for _,child in ipairs(profilesScroll:GetChildren()) do
            if child:IsA("GuiButton") then local nl=child:FindFirstChildWhichIsA("TextLabel")
                if nl and (nl.Text==targetPlayer.Name or nl.Text==targetPlayer.DisplayName) then playerBtn=child; break end
            end
        end
    end
    if not playerBtn then realAdminGui.Enabled=wasEnabled; return false end
    fireClick(playerBtn)
    apStartCooldown(commandName)
    task.delay(0.05, function()
        if realAdminGui and realAdminGui.Parent then realAdminGui.Enabled=wasEnabled end
    end)
    return true
end
_G.runAdminCommand=runAdminCommand


local function runAutoBaseActions()
    task.spawn(function()
        task.wait(1.5)
        local char = player.Character or player.CharacterAdded:Wait()
        local hrp = char:WaitForChild("HumanoidRootPart", 10)
        if not hrp then return end
        
        local nearestPlayer = nil
        local nearestDist = math.huge
        local Plots = Workspace:FindFirstChild("Plots")
        if Plots then
            for _, plot in ipairs(Plots:GetChildren()) do
                local owner = getPlotOwner(plot)
                if owner and owner ~= player then
                    local sign = plot:FindFirstChild("PlotSign")
                    if sign then
                        local signPos = (sign:IsA("BasePart") and sign.Position) or (sign.PrimaryPart and sign.PrimaryPart.Position)
                        if signPos then
                            local dist = (hrp.Position - signPos).Magnitude
                            if dist < nearestDist then
                                nearestDist = dist
                                nearestPlayer = owner
                            end
                        end
                    end
                end
            end
        end
        
        if nearestPlayer then
            -- auto base actions removed
        end
    end)
end
_G.runAutoBaseActions = runAutoBaseActions

local function isMobyUser(p) return p and p.Character and p.Character:FindFirstChild("_moby_highlight")~=nil end
local function isKawaifuUser(p) return p and p.Character and p.Character:FindFirstChild("KaWaifu_NeonHighlight")~=nil end

local function getNextAvailableCommand()
    local priorityCmds={"ragdoll","balloon","rocket","jail"}
    for _,cmd in ipairs(priorityCmds) do if not apIsOnCooldown(cmd) then return cmd end end
    for _,cmd in ipairs(AP_ALL_COMMANDS) do if not apIsOnCooldown(cmd) then return cmd end end
    return nil
end

local function kickPlayer(stolenText)
    local isAutoKickSteal = false
    
    if stolenText and type(stolenText) == "string" then
        isAutoKickSteal = true
    end

    if Config.KickToPrivateServer and PrivateServerCode and PrivateServerCode ~= "" and isAutoKickSteal then
        task.delay(0.2, function()
            pcall(function()
                local ExperienceService = game:GetService("ExperienceService")
                ExperienceService:LaunchExperience({
                    placeId = game.PlaceId,
                    linkCode = PrivateServerCode,
                })
            end)
        end)
        return
    end
    pcall(function() game:Shutdown() end)
    pcall(function() LocalPlayer:Kick("\nIDF HUB PRIVAT") end)
end

-- SHARED STATE
SharedState = {SelectedPetData=nil, AllAnimalsCache={}, ListNeedsRedraw=true, InitialScanComplete=false, seenUIDs={}, BrainrotNames={}}

-- NOTIFICATION SYSTEM
local function ShowNotification(title, text)
    -- Disabled: all notifications removed by user request
    return
end

-- ============================================================
-- RESET
-- ============================================================
local executeReset

do
--[[
    Roblox Instant Reset & Lagback Detector (Defensive Always-Working Hook)
    Created by Antigravity (DeepMind Coding Assistant)
    
    Fixes:
    - Reverted capture-state resetting. Once TargetRemote is captured, it is kept for the entire session.
    - Fixed the reset-spam issue. Resetting state resets immediately upon character removal so you can spam resets.
--]]

-- SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

-- CONFIGURATION DEFAULT
local Config = {
    Enabled = true,
    DetectionThreshold = 6,
    HistoryDuration = 2.0,
    VelocityDotThreshold = -0.3,
    
    ResetKey = "NONE",           -- Managed via main Keybinds (default X)
    FloodCount = 50,             -- Number of junk fires to force server lagback reset
    
    ResetMethods = {
        SpamHeartbeat = true,    -- Spam captured ToolActivationController remote
        HumanoidHealth = true,   -- Fallback: Set health to 0
        BreakJoints = true,      -- Fallback: Break joints
        ChangeStateDead = true,  -- Fallback: Force dead state
        DestroyHumanoid = false, -- Fallback: Destroy humanoid
        FireRemotes = true       -- Fallback: Fire detected generic reset remotes
    },
    
    ScanInterval = 15,
    RemoteKeywords = {"reset", "kill", "die", "suicide", "respawn", "clear", "death", "damage", "reavatar"},
    BlacklistedRemotes = {"AdminReset", "StaffReset", "ModReset"},
    
    Debug = false,
    NotifyOnReset = true
}

-- STATE VARIABLES
local TargetRemote = nil -- Dynamically captured heartbeat remote
local rawFS = nil        -- Original unhooked FireServer function
local resetRemotes = {}
local positionHistory = {}
local lastPosition = nil
local lastVelocity = Vector3.new(0, 0, 0)
local isTeleporting = false
local resetting = false
local scanTimer = 0
local lastHistoryUpdate = 0

-- LOGGING UTILITY
local function log(message, isWarn)
    -- Disabled: do not print or warn anything to dev console
    return
end

-- EXPORTED TELEPORT BYPASS API
_G.NotifyLocalTeleport = function(duration)
    local delayTime = duration or 0.5
    isTeleporting = true
    task.delay(delayTime, function()
        isTeleporting = false
    end)
end
shared.NotifyLocalTeleport = _G.NotifyLocalTeleport

-- OPTIMIZED INCREMENTAL REMOTE EVENT SCANNER (For Generic Fallbacks)
local function scanForRemotes()
    table.clear(resetRemotes)
    
    task.spawn(function()
        local searchAreas = {ReplicatedStorage, Workspace}
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            table.insert(searchAreas, playerGui)
        end
        
        local count = 0
        for _, area in ipairs(searchAreas) do
            local queue = {area}
            while #queue > 0 do
                local current = table.remove(queue, 1)
                count = count + 1
                if count % 150 == 0 then
                    task.wait()
                end
                
                pcall(function()
                    for _, child in ipairs(current:GetChildren()) do
                        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                            local nameLower = child.Name:lower()
                            local isMatch = false
                            for _, keyword in ipairs(Config.RemoteKeywords) do
                                if string.find(nameLower, keyword, 1, true) then
                                    isMatch = true
                                    break
                                end
                            end
                            
                            if isMatch then
                                local isBlacklisted = false
                                for _, black in ipairs(Config.BlacklistedRemotes) do
                                    if string.find(child.Name, black, 1, true) then
                                        isBlacklisted = true
                                        break
                                    end
                                end
                                
                                if not isBlacklisted then
                                    table.insert(resetRemotes, child)
                                end
                            end
                        elseif child:IsA("Folder") or child:IsA("Configuration") or child:IsA("Model") or child:IsA("Tool") then
                            table.insert(queue, child)
                        end
                    end
                end)
            end
        end
    end)
end

-- --- DYNAMIC REMOTE INTERCEPTION (ToolActivationController Heartbeat Hook) ---
local function hookHeartbeatRemote()
    local newcc = newcclosure or function(f) return f end
    
    pcall(function()
        local seen = {}
        local capturing = true
        
        local function handleFire(self, ...)
            if not capturing then return end
            if not self:IsA("RemoteEvent") then return end
            
            local a1 = (select("#", ...) >= 1) and (select(1, ...)) or nil
            if typeof(a1) ~= "string" then return end
            
            local nm = self.Name
            if type(nm) ~= "string" or not nm:match("^RE/%x%x%x%x%x%x%x%x") then return end
            
            local callingScript = nil
            pcall(function() callingScript = getcallingscript() end)
            
            local isScriptMatch = false
            if callingScript then
                if callingScript.Name == "ToolActivationController" or string.find(callingScript.Name, "ToolActivationController") then
                    isScriptMatch = true
                end
            else
                isScriptMatch = true
            end
            
            if isScriptMatch then
                local c = (seen[self] or 0) + 1
                seen[self] = c
                if c >= 2 then
                    TargetRemote = self
                    capturing = false
                    seen = nil
                    log("ToolActivationController heartbeat remote captured: " .. self:GetFullName())
                end
            end
        end

        if hookfunction then
            local dummyFunc = function(self, ...) return self end
            rawFS = dummyFunc
            rawFS = hookfunction(Instance.new("RemoteEvent").FireServer, newcc(function(self, ...)
                pcall(handleFire, self, ...)
                return (rawFS ~= dummyFunc and rawFS or Instance.new("RemoteEvent").FireServer)(self, ...)
            end))
            log("Successfully hooked FireServer via hookfunction.")
        elseif hookmetamethod then
            local oldNamecall
            oldNamecall = hookmetamethod(game, "__namecall", newcc(function(self, ...)
                local method = getnamecallmethod()
                if (method == "FireServer" or method == "fireServer") and self:IsA("RemoteEvent") then
                    pcall(handleFire, self, ...)
                end
                return oldNamecall(self, ...)
            end))
            log("Successfully hooked __namecall via hookmetamethod.")
        else
            log("Warning: Executor does not support hookfunction or hookmetamethod.", true)
        end
    end)
end

-- INSTANT RESET (new.lua method) -- spams the captured RE/* reset remote with a
-- junk payload until the character respawns. This is the method that actually
-- works in THIS game (client Health/BreakJoints is server-authoritative and does
-- nothing). Robustness over new.lua: waits briefly for the remote to be captured
-- and time-caps the loop, so the cooldown can never get stuck = reset always fires.
local function instantReset()
    if instaResetCooldown then return end
    instaResetCooldown = true
    local lp = LocalPlayer
    local oldChar = lp.Character
    task.spawn(function()
        local t0 = os.clock()
        -- if the reset remote hasn't been captured yet, wait briefly for it
        while not resetRemote and (os.clock() - t0) < 3 do task.wait() end
        while resetRemote and lp.Character == oldChar and (os.clock() - t0) < 8 do
            pcall(function() resetRemote:FireServer("randomstring") end)
            task.wait()
        end
        instaResetCooldown = false
    end)
end

-- Native Esc -> Reset button: route it through the same working reset (remote spam)
-- instead of the game's default, so the menu reset also works instantly.
local _sxeResetBindable = Instance.new("BindableEvent")
_sxeResetBindable.Event:Connect(function() pcall(instantReset) end)
task.spawn(function()
    for _ = 1, 12 do
        local ok = pcall(function()
            game:GetService("StarterGui"):SetCore("ResetButtonCallback", _sxeResetBindable)
        end)
        if ok then break end
        task.wait(1)
    end
end)

-- KEYBIND TRIGGER (Disabled local listener to avoid collision with 'Drop Brainrot' keybind G)
-- Reset is managed by the main Keybinds setting in the GUI (defaults to key X)

_G.InstantReset = instantReset -- Global access for other scripts

-- HISTORY CACHE MANAGEMENT
local function updateHistory(pos)
    local now = tick()
    if now - lastHistoryUpdate < 0.05 then return end
    lastHistoryUpdate = now
    
    table.insert(positionHistory, {pos = pos, time = now})
    
    while #positionHistory > 0 and now - positionHistory[1].time > Config.HistoryDuration do
        table.remove(positionHistory, 1)
    end
end

-- --- MAIN MONITORING LOOP ---
local function onHeartbeat(dt)
    if resetting then return end
    
    -- Scan remotes periodically in background
    scanTimer = scanTimer + dt
    if scanTimer >= Config.ScanInterval then
        scanTimer = 0
        scanForRemotes()
    end
end

-- INITIALIZATION
scanForRemotes()
-- hookHeartbeatRemote() removed -- it stacked a second FireServer hook on top of
-- the Vanish bypass hook, which broke the chain after re-injects and stopped
-- in-game tool activation from working. The Vanish FireServer hook at the top of
-- the file is the ONLY hook this script installs now.
RunService.Heartbeat:Connect(onHeartbeat)



-- Compatibility wrapper for executeReset
local lastBalloonResetTime = 0
executeReset = function(isBalloon)
    if isBalloon then
        if tick() - lastBalloonResetTime < 20 then return end
        lastBalloonResetTime = tick()
    end
    instantReset()
end
_G.executeReset = executeReset
end

-- CLONE
local function instantClone()
    local c=player.Character; if not c then return end
    local h=c:FindFirstChildOfClass("Humanoid"); if not h then return end
    local cl=player.Backpack:FindFirstChild("Quantum Cloner") or c:FindFirstChild("Quantum Cloner"); if not cl then return end
    pcall(function() h:UnequipTools() end); task.wait()
    if cl.Parent~=c then h:EquipTool(cl); task.wait() end
    local tf=playerGui:FindFirstChild("ToolsFrames"); local qc=tf and tf:FindFirstChild("QuantumCloner")
    local tb=qc and qc:FindFirstChild("TeleportToClone"); if not tb then return end
    _G.isCloning=true; cl:Activate(); task.wait(0.05); tb.Visible=true
    pcall(function() firesignal(tb.MouseButton1Click) end)
    pcall(function() firesignal(tb.MouseButton1Up) end)
    pcall(function() firesignal(tb.Activated) end)
    task.delay(0.55, function() _G.isCloning=false end)
end

-- DROP BRAINROT
local _wfConns,_wfActive={},false
local function stopWalkFling() _wfActive=false; for _,c in ipairs(_wfConns) do if typeof(c)=="RBXScriptConnection" then c:Disconnect() end end; _wfConns={} end
local function startWalkFling()
    _wfActive=true; local ch=player.Character; if not ch then return end
    local rr=ch:FindFirstChild("HumanoidRootPart")
    for _,o in pairs(Workspace.CurrentCamera:GetChildren()) do if o.Name=="HumanoidRootPart" then rr=o; break end end
    if not rr then return end
    table.insert(_wfConns,RunService.Stepped:Connect(function() if not _wfActive then return end
        for _,p in ipairs(Players:GetPlayers()) do if p~=player and p.Character then for _,pt in ipairs(p.Character:GetChildren()) do if pt:IsA("BasePart") then pt.CanCollide=false end end end end
    end))
    local co=coroutine.create(function()
        if _G.invisibleStealEnabled then rr.CFrame=rr.CFrame*CFrame.new(0,3,0) end
        while _wfActive do RunService.Heartbeat:Wait(); if not rr or not rr.Parent then break end
            local v=rr.Velocity; rr.Velocity=v*10000+Vector3.new(0,10000,0)
            RunService.RenderStepped:Wait(); if rr then rr.Velocity=v end
            RunService.Stepped:Wait(); if rr then rr.Velocity=v+Vector3.new(0,0.1,0) end
        end
    end); coroutine.resume(co); table.insert(_wfConns,co)
end
local function runDropBrainrot() if _wfActive then return end; startWalkFling(); task.delay(0.4,stopWalkFling) end

-- ============================================================
-- INVISIBLE STEAL
-- ============================================================
do
local animPlaying = false
local tracks = {}
local clone, oldRoot, hip, connection
local folderConnections = {}
local serverGhosts = {}
local ghostEnabled = true
local lagbackCallCount = 0
local lagbackWindowStart = 0
local lastLagbackTime = 0
local errorOrbActive = false
local errorOrb = nil
local errorOrbConnection = nil

_G.invisibleStealEnabled = false
_G.InvisStealAngle = Config.InvisStealAngle or 225
_G.SinkSliderValue = Config.SinkSliderValue or 7
_G.AutoRecoverLagback = Config.AutoRecoverLagback ~= nil and Config.AutoRecoverLagback or true
_G.AutoInvisDuringSteal = Config.AutoInvisDuringSteal or false

local function clearErrorOrb()
    if errorOrb and errorOrb.Parent then errorOrb:Destroy() end
    errorOrb = nil; errorOrbActive = false
    if errorOrbConnection then errorOrbConnection:Disconnect(); errorOrbConnection = nil end
end

local function createErrorOrb()
    if errorOrbActive then return end
    errorOrbActive = true
    for _, ghost in pairs(serverGhosts) do if ghost and ghost.Parent then ghost:Destroy() end end
    serverGhosts = {}
    -- Error UI notifications disabled
end

local function createServerGhost(position)
    if not ghostEnabled or errorOrbActive then return end
    local now = tick()
    if now - lastLagbackTime < 0.05 then return end
    lastLagbackTime = now
    if now - lagbackWindowStart > 1 then lagbackCallCount = 0; lagbackWindowStart = now end
    lagbackCallCount = lagbackCallCount + 1
    if lagbackCallCount >= 7 then createErrorOrb(); return end
    for _, g in pairs(serverGhosts) do if g and g.Parent then g:Destroy() end end
    serverGhosts = {}
    local ghost = Instance.new("Part")
    ghost.Name = "LagbackGhost"; ghost.Shape = Enum.PartType.Ball
    ghost.Size = Vector3.new(3, 3, 3); ghost.Color = Color3.fromRGB(255, 0, 0)
    ghost.Material = Enum.Material.Glass; ghost.Transparency = 0.3
    ghost.CanCollide = false; ghost.Anchored = true; ghost.CastShadow = false
    ghost.Position = position + Vector3.new(0, 5, 0); ghost.Parent = Workspace.CurrentCamera
    table.insert(serverGhosts, ghost)
    -- Lagback text notifications & billboard GUIs disabled
end

local function clearAllGhosts()
    for _, ghost in pairs(serverGhosts) do pcall(function() if ghost and ghost.Parent then ghost:Destroy() end end) end
    serverGhosts = {}; clearErrorOrb(); lagbackCallCount = 0; lastLagbackTime = 0
    pcall(function()
        local pg = player:FindFirstChild("PlayerGui")
        if pg then for _, gui in pairs(pg:GetChildren()) do if gui.Name == "LagbackNotification" then gui:Destroy() end end end
    end)
    pcall(function() if Workspace.CurrentCamera then for _, c in pairs(Workspace.CurrentCamera:GetChildren()) do if c.Name == "LagbackGhost" then c:Destroy() end end end end)
    pcall(function() for _, c in pairs(Workspace:GetDescendants()) do if c.Name == "LagbackGhost" then c:Destroy() end end end)
end

local function removeFolders()
    local pf = Workspace:FindFirstChild(player.Name)
    if not pf then return end
    local dr = pf:FindFirstChild("DoubleRig")
    if dr then
        local rr = dr:FindFirstChild("HumanoidRootPart") or dr:FindFirstChildWhichIsA("BasePart")
        if rr and ghostEnabled then createServerGhost(rr.Position) end
        dr:Destroy()
    end
    local cs = pf:FindFirstChild("Constraints")
    if cs then cs:Destroy() end
    local conn = pf.ChildAdded:Connect(function(child)
        if child.Name == "DoubleRig" then
            task.defer(function()
                local rr = child:FindFirstChild("HumanoidRootPart") or child:FindFirstChildWhichIsA("BasePart")
                if rr and ghostEnabled then createServerGhost(rr.Position) end
                child:Destroy()
            end)
        elseif child.Name == "Constraints" then child:Destroy() end
    end)
    table.insert(folderConnections, conn)
end

local function doClone()
    local character = player.Character
    if character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0 then
        hip = character.Humanoid.HipHeight
        oldRoot = character:FindFirstChild("HumanoidRootPart")
        if not oldRoot or not oldRoot.Parent then return false end
        for _, c in pairs(oldRoot:GetChildren()) do
            if c:IsA("Attachment") and (c.Name:find("Beam") or c.Name:find("Attach")) then c:Destroy() end
        end
        for _, c in pairs(oldRoot:GetChildren()) do if c:IsA("Beam") then c:Destroy() end end
        local tmp = Instance.new("Model"); tmp.Parent = game
        character.Parent = tmp
        clone = oldRoot:Clone(); clone.Parent = character
        oldRoot.Parent = Workspace.CurrentCamera
        clone.CFrame = oldRoot.CFrame; character.PrimaryPart = clone
        character.Parent = Workspace
        for _, v in pairs(character:GetDescendants()) do
            if v:IsA("Weld") or v:IsA("Motor6D") then
                if v.Part0 == oldRoot then v.Part0 = clone end
                if v.Part1 == oldRoot then v.Part1 = clone end
            end
        end
        tmp:Destroy(); return true
    end
    return false
end

local function revertClone()
    local character = player.Character
    if not oldRoot or not oldRoot:IsDescendantOf(Workspace) or not character or character.Humanoid.Health <= 0 then return end
    local tmp = Instance.new("Model"); tmp.Parent = game
    character.Parent = tmp
    oldRoot.Parent = character; character.PrimaryPart = oldRoot
    character.Parent = Workspace; oldRoot.CanCollide = true
    for _, v in pairs(character:GetDescendants()) do
        if v:IsA("Weld") or v:IsA("Motor6D") then
            if v.Part0 == clone then v.Part0 = oldRoot end
            if v.Part1 == clone then v.Part1 = oldRoot end
        end
    end
    if clone then local p = clone.CFrame; clone:Destroy(); clone = nil; oldRoot.CFrame = p end
    oldRoot = nil
    if character and character.Humanoid then character.Humanoid.HipHeight = hip end
    clearAllGhosts()
end

local function animationTrickery()
    local character = player.Character
    if character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0 then
        local anim = Instance.new("Animation")
        anim.AnimationId = "http://www.roblox.com/asset/?id=18537363391"
        local humanoid = character.Humanoid
        local animator = humanoid:FindFirstChild("Animator") or Instance.new("Animator", humanoid)
        local animTrack = animator:LoadAnimation(anim)
        animTrack.Priority = Enum.AnimationPriority.Action4
        animTrack:Play(0, 1, 0); anim:Destroy()
        table.insert(tracks, animTrack)
        animTrack.Stopped:Connect(function() if animPlaying then animationTrickery() end end)
        task.delay(0, function()
            animTrack.TimePosition = 0.7
            task.delay(0.3, function() if animTrack then animTrack:AdjustSpeed(math.huge) end end)
        end)
    end
end

local _invisToggleCooldown = 0

local function invisTurnOff()
    clearAllGhosts()
    if not animPlaying then return end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    animPlaying = false; _G.invisibleStealEnabled = false
    setToggle("Invisible Steal", false)
    for _, t in pairs(tracks) do pcall(function() t:Stop(0) end) end
    tracks = {}
    if connection then connection:Disconnect(); connection = nil end
    for _, c in ipairs(folderConnections) do if c then c:Disconnect() end end
    folderConnections = {}
    revertClone(); clearAllGhosts()
    -- Force reset all animations back to default
    if humanoid then
        pcall(function()
            local animator = humanoid:FindFirstChildOfClass("Animator")
            if animator then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    if track.Priority == Enum.AnimationPriority.Action4 or track.Priority == Enum.AnimationPriority.Action3 then
                        track:Stop(0)
                    end
                end
            end
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            task.defer(function()
                if humanoid and humanoid.Parent then
                    humanoid:ChangeState(Enum.HumanoidStateType.Running)
                end
            end)
        end)
    end
    if _G.updateMovementPanelInvisVisual then pcall(_G.updateMovementPanelInvisVisual, false) end
    -- Instantly disable walkspeed when invis steal turns off
    if WalkSpeedState and WalkSpeedState.enabled and Config.WalkSpeedEnabled then
        setWalkSpeedEnabled(false)
    end
    _invisToggleCooldown = tick()
end

local function invisTurnOn()
    if animPlaying then return end
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    animPlaying = true; _G.invisibleStealEnabled = true
    setToggle("Invisible Steal", true)
    if _G.updateMovementPanelInvisVisual then pcall(_G.updateMovementPanelInvisVisual, true) end
    tracks = {}; removeFolders()
    local success = doClone()
    if success then
        task.wait(0.05); animationTrickery()
        task.defer(function()
            if _G.resetBrainrotBeam then pcall(_G.resetBrainrotBeam) end
            if _G.resetPlotBeam then pcall(_G.resetPlotBeam) end
            task.wait(0.1)
            if _G.updateBrainrotBeam then pcall(_G.updateBrainrotBeam) end
            if _G.createPlotBeam then pcall(_G.createPlotBeam) end
        end)
        -- Enable walkspeed 1 second after invis steal activates
        task.delay(1, function()
            if _G.invisibleStealEnabled and not WalkSpeedState.enabled then
                setWalkSpeedEnabled(true)
            end
        end)
        local lastSetPosition = nil; local skipFrames = 5
        connection = RunService.PreSimulation:Connect(function()
            if character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0 and oldRoot then
                local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
                if root then
                    if skipFrames > 0 then skipFrames = skipFrames - 1; lastSetPosition = nil
                    elseif lastSetPosition and ghostEnabled then
                        local currentPos = oldRoot.Position
                        local jumpDist = (currentPos - lastSetPosition).Magnitude
                        if jumpDist > 6 and not _G.RecoveryInProgress and player:GetAttribute("Stealing") then
                            lastSetPosition = nil; createServerGhost(currentPos)
                            if _G.AutoRecoverLagback and _G._forceInvisToggle then
                                _G.RecoveryInProgress = true
                                task.spawn(function()
                                    pcall(_G._forceInvisToggle); task.wait(0.6)
                                    if player:GetAttribute("Stealing") then
                                        pcall(_G._forceInvisToggle)
                                    end
                                    _G.RecoveryInProgress = false
                                end)
                            end
                        end
                    end
                    if clone then clone.CanCollide = true end
                    if oldRoot and oldRoot.Parent then
                        for _, c in pairs(oldRoot:GetChildren()) do
                            if c:IsA("Attachment") or c:IsA("Beam") then c:Destroy() end
                        end
                        local sa = (_G.SinkSliderValue or 7) * 0.5
                        local cf = root.CFrame - Vector3.new(0, sa, 0)
                        oldRoot.CFrame = cf * CFrame.Angles(math.rad(_G.InvisStealAngle or 225), 0, 0)
                        oldRoot.AssemblyLinearVelocity = root.AssemblyLinearVelocity; oldRoot.CanCollide = false
                        lastSetPosition = oldRoot.Position
                    end
                end
            end
        end)
    end
end

_G.toggleInvisibleSteal = function()
    if (tick() - _invisToggleCooldown) < 0.3 then return end
    if animPlaying then invisTurnOff() else invisTurnOn() end
end

-- Force toggle that bypasses debounce (for auto-recover and auto-invis)
_G._forceInvisToggle = function()
    if animPlaying then invisTurnOff() else invisTurnOn() end
end

player.CharacterAdded:Connect(function(newChar)
    task.wait(0.1)
    if Config then Config.ClickToAP = false end
    clearErrorOrb(); clearAllGhosts(); lagbackCallCount = 0
    pcall(function() for _, c in pairs(Workspace.CurrentCamera:GetChildren()) do if c:IsA("BasePart") and c.Name == "HumanoidRootPart" then c:Destroy() end end end)
    if oldRoot then pcall(function() oldRoot:Destroy() end); oldRoot = nil end
    if clone then pcall(function() clone:Destroy() end); clone = nil end
    animPlaying = false; _G.invisibleStealEnabled = false
    setToggle("Invisible Steal", false)
    if _G.updateMovementPanelInvisVisual then pcall(_G.updateMovementPanelInvisVisual, false) end
    task.wait(0.2)
    local camera = Workspace.CurrentCamera
    if camera and newChar then
        local h = newChar:FindFirstChildOfClass("Humanoid")
        if h then camera.CameraSubject = h; camera.CameraType = Enum.CameraType.Custom end
    end
end)

local function setupDeathListener()
    local ch = player.Character
    if ch then
        local h = ch:FindFirstChildOfClass("Humanoid")
        if h then h.Died:Connect(function() clearErrorOrb(); clearAllGhosts(); lagbackCallCount = 0 end) end
    end
end
setupDeathListener()
player.CharacterAdded:Connect(function() task.wait(0.1); setupDeathListener() end)

-- ANTI-DIE
task.spawn(function()
    _G.AntiDieDisabled = false
    local function setupAntiDie()
        if _G.AntiDieDisabled then return end
        local character = player.Character
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        if _G.AntiDieConnection then pcall(function() _G.AntiDieConnection:Disconnect() end) end
        _G.AntiDieConnection = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
            if _G.AntiDieDisabled then return end
            if humanoid.Health <= 0 then
                humanoid.Health = humanoid.MaxHealth
            end
        end)
    end
    _G.setupAntiDie = setupAntiDie
    setupAntiDie()
    player.CharacterAdded:Connect(function()
        task.wait(0.5)
        if not _G.AntiDieDisabled then
            setupAntiDie()
        end
    end)
end)

-- Automatic Invis During Steal Loop
task.spawn(function()
    local wasStealingForInvis = false
    local autoEnabledInvis = false
    task.wait(1)
    while task.wait(0.15) do
        if Config.AutoInvisDuringSteal == false then
            wasStealingForInvis = false
            autoEnabledInvis = false
        else
            local isStealing = player:GetAttribute("Stealing")
            if isStealing and not wasStealingForInvis then
                if not _G.invisibleStealEnabled and _G._forceInvisToggle then
                    task.defer(function()
                        if player:GetAttribute("Stealing") and not _G.invisibleStealEnabled then
                            pcall(_G._forceInvisToggle)
                            autoEnabledInvis = true
                        end
                    end)
                end
            end
            if not isStealing and autoEnabledInvis and _G.invisibleStealEnabled and _G._forceInvisToggle then
                task.wait(0.3)
                if not player:GetAttribute("Stealing") then
                    pcall(_G._forceInvisToggle)
                    autoEnabledInvis = false
                end
            end
            wasStealingForInvis = isStealing
        end
    end
end)

-- FLOAT
FloatState={active=false,platform=nil,followConn=nil}
local function removeFloatPlatform() if FloatState.followConn then FloatState.followConn:Disconnect(); FloatState.followConn=nil end; if FloatState.platform then FloatState.platform:Destroy(); FloatState.platform=nil end end
local function createFloatPlatform()
    removeFloatPlatform(); local c=player.Character; local hrp=c and c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local p=Instance.new("Part"); p.Size=Vector3.new(7,1,7); p.Anchored=true; p.CanCollide=true; p.CanTouch=false; p.CanQuery=false
    p.Transparency=1; p.CastShadow=false; p.CFrame=CFrame.new(hrp.Position-Vector3.new(0,3.35,0)); p.Parent=Workspace; FloatState.platform=p
    FloatState.followConn=RunService.Heartbeat:Connect(function() if not FloatState.active then return end
        local ch=player.Character; local h=ch and ch:FindFirstChild("HumanoidRootPart")
        if h and FloatState.platform then FloatState.platform.CFrame=CFrame.new(h.Position-Vector3.new(0,3.35,0)) end
    end)
end
local function setFloat(on) FloatState.active=on; Config.Float=on; saveConfig(); setToggle("Float",on); if on then createFloatPlatform() else removeFloatPlatform() end end
_G.toggleFloat=function() setFloat(not FloatState.active) end

-- WALKSPEED (CFrame Bypass)
WalkSpeedState = {enabled = false, conn = nil, speed = Config.WalkSpeedValue or 16}
local function setWalkSpeedEnabled(en)
    WalkSpeedState.enabled = en
    Config.WalkSpeedEnabled = en
    setToggle("WalkSpeed", en)
    saveConfig()
    if WalkSpeedState.conn then WalkSpeedState.conn:Disconnect(); WalkSpeedState.conn = nil end
    if not en then return end
    WalkSpeedState.conn = RunService.Heartbeat:Connect(function(dt)
        local character = player.Character
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart or humanoid.Health <= 0 then return end
        if humanoid.MoveDirection.Magnitude > 0 and WalkSpeedState.speed > humanoid.WalkSpeed then
            local extraSpeed = WalkSpeedState.speed - humanoid.WalkSpeed
            rootPart.CFrame = rootPart.CFrame + (humanoid.MoveDirection * extraSpeed * dt)
        end
    end)
end
local function setWalkSpeedValue(v)
    v = math.clamp(math.floor(v + 0.5), 15, 29)
    WalkSpeedState.speed = v
    Config.WalkSpeedValue = v
    saveConfig()
    return v
end
_G.setWalkSpeedEnabled = setWalkSpeedEnabled
_G.setWalkSpeedValue = setWalkSpeedValue

-- CARPET SPEED
CarpetState={enabled=false,conn=nil}
local function setCarpetSpeed(en) CarpetState.enabled=en; setToggle("Carpet Speed",en)
    if CarpetState.conn then CarpetState.conn:Disconnect(); CarpetState.conn=nil end; if not en then local _c=player.Character; local _h=_c and _c:FindFirstChild("Humanoid"); if _h then pcall(function() _h:UnequipTools() end) end; return end
    CarpetState.conn=RunService.Heartbeat:Connect(function() local c=player.Character; if not c then return end
        local hum=c:FindFirstChild("Humanoid"); local hrp=c:FindFirstChild("HumanoidRootPart"); if not hum or not hrp then return end
        local tn=Config.TpSettings.Tool or "Flying Carpet"; if not c:FindFirstChild(tn) then local tb=player.Backpack:FindFirstChild(tn); if tb then hum:EquipTool(tb) end end
        if c:FindFirstChild(tn) then local md=hum.MoveDirection; if md.Magnitude>0 then hrp.AssemblyLinearVelocity=Vector3.new(md.X*140,hrp.AssemblyLinearVelocity.Y,md.Z*140) else hrp.AssemblyLinearVelocity=Vector3.new(0,hrp.AssemblyLinearVelocity.Y,0) end end
    end)
end

-- INFINITE JUMP (0.1s cooldown, 55 velocity)
InfJumpState={enabled=false,conn=nil,lastJump=0}
local function setInfiniteJump(en) InfJumpState.enabled=en; Config.InfiniteJump=en; Config.TpSettings.InfiniteJump=en; setToggle("Infinite Jump",en); saveConfig()
    if InfJumpState.conn then InfJumpState.conn:Disconnect(); InfJumpState.conn=nil end; if not en then return end
    InfJumpState.conn=RunService.Heartbeat:Connect(function() if not UIS:IsKeyDown(Enum.KeyCode.Space) then return end
        local now=tick(); if now-InfJumpState.lastJump<0.1 then return end; local c=player.Character; if not c then return end
        local hrp=c:FindFirstChild("HumanoidRootPart"); local hum=c:FindFirstChild("Humanoid"); if not hrp or not hum or hum.Health<=0 then return end
        InfJumpState.lastJump=now; hrp.AssemblyLinearVelocity=Vector3.new(hrp.AssemblyLinearVelocity.X,55,hrp.AssemblyLinearVelocity.Z)
    end)
end

-- ANTI RAGDOLL
-- Anti-Ragdoll System (comprehensive with knockback suppression)
do
    local antiRagdollConnections = {}
    local antiRagdollCharacter, antiRagdollHumanoid, antiRagdollRootPart, antiRagdollAnimator
    local lastVelocity = Vector3.new(0, 0, 0)
    local velocityChangeThreshold = 40
    local velocityMagnitudeThreshold = 25
    local maxVelocity = 15

    local function isFlyingCarpetActive()
        if not antiRagdollCharacter then return false end
        local tool = antiRagdollCharacter:FindFirstChildWhichIsA("Tool")
        if not tool then return false end
        local hrp = antiRagdollCharacter:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, obj in ipairs(hrp:GetChildren()) do
                if obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                    return true
                end
            end
        end
        return false
    end

    local function isRagdolled()
        if not antiRagdollHumanoid then return false end
        local state = antiRagdollHumanoid:GetState()
        return state == Enum.HumanoidStateType.Physics
            or state == Enum.HumanoidStateType.Ragdoll
            or state == Enum.HumanoidStateType.FallingDown
            or state == Enum.HumanoidStateType.GettingUp
    end

    local function enableAntiRagdollControls()
        pcall(function()
            local PlayerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
            require(PlayerModule):GetControls():Enable()
        end)
    end

    local function cleanupRagdoll()
        if not antiRagdollCharacter then return end
        local carpetEquipped = isFlyingCarpetActive()

        local function processChildren(parent)
            for _, obj in ipairs(parent:GetChildren()) do
                if obj:IsA("BallSocketConstraint") or obj:IsA("NoCollisionConstraint") or obj:IsA("HingeConstraint")
                    or (obj:IsA("Attachment") and (obj.Name == "A" or obj.Name == "B")) then
                    obj:Destroy()
                elseif obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                    if not carpetEquipped then obj:Destroy() end
                elseif obj:IsA("Motor6D") then
                    obj.Enabled = true
                elseif obj:IsA("BasePart") then
                    for _, child in ipairs(obj:GetChildren()) do
                        if child:IsA("BallSocketConstraint") or child:IsA("NoCollisionConstraint") or child:IsA("HingeConstraint") or child:IsA("Motor6D") then
                            if child:IsA("Motor6D") then
                                child.Enabled = true
                            else
                                child:Destroy()
                            end
                        elseif child:IsA("Attachment") and (child.Name == "A" or child.Name == "B") then
                            child:Destroy()
                        end
                    end
                end
            end
        end

        pcall(function() processChildren(antiRagdollCharacter) end)

        if antiRagdollAnimator then
            for _, track in pairs(antiRagdollAnimator:GetPlayingAnimationTracks()) do
                local animName = track.Animation and track.Animation.Name:lower() or ""
                if animName:find("rag") or animName:find("fall") or animName:find("hurt") or animName:find("down") then
                    track:Stop(0)
                end
            end
        end
    end

    local function setupAntiRagdollCharacter(char)
        antiRagdollCharacter = char
        antiRagdollHumanoid = char:WaitForChild("Humanoid", 10)
        antiRagdollRootPart = char:WaitForChild("HumanoidRootPart", 10)
        antiRagdollAnimator = antiRagdollHumanoid and antiRagdollHumanoid:WaitForChild("Animator", 10)
        lastVelocity = Vector3.new(0, 0, 0)
    end

    local function clearAntiRagdollConnections()
        for _, c in pairs(antiRagdollConnections) do
            pcall(function() c:Disconnect() end)
        end
        antiRagdollConnections = {}
    end

    local function setupAntiRagdollConnections()
        clearAntiRagdollConnections()
        if not antiRagdollHumanoid or not antiRagdollRootPart then return end

        table.insert(antiRagdollConnections, antiRagdollHumanoid.StateChanged:Connect(function()
            if (_G.AntiRagdollEnabled or _G.antiKnockbackEnabled) and isRagdolled() then
                if not isFlyingCarpetActive() then
                    antiRagdollHumanoid:ChangeState(Enum.HumanoidStateType.Running)
                end
                cleanupRagdoll()
                Workspace.CurrentCamera.CameraSubject = antiRagdollHumanoid
                enableAntiRagdollControls()
            end
        end))

        pcall(function()
            local impulsePath = ReplicatedStorage:FindFirstChild("Packages")
            if impulsePath then
                impulsePath = impulsePath:FindFirstChild("Net")
                if impulsePath then
                    impulsePath = impulsePath:FindFirstChild("RE/CombatService/ApplyImpulse")
                    if impulsePath then
                        table.insert(antiRagdollConnections, impulsePath.OnClientEvent:Connect(function()
                            if (_G.AntiRagdollEnabled or _G.antiKnockbackEnabled) and isRagdolled() then
                                antiRagdollRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                            end
                        end))
                    end
                end
            end
        end)

        table.insert(antiRagdollConnections, antiRagdollCharacter.DescendantAdded:Connect(function()
            if (_G.AntiRagdollEnabled or _G.antiKnockbackEnabled) and isRagdolled() then
                cleanupRagdoll()
            end
        end))

        table.insert(antiRagdollConnections, RunService.Heartbeat:Connect(function()
            if (_G.AntiRagdollEnabled or _G.antiKnockbackEnabled) and isRagdolled() then
                cleanupRagdoll()
                local velocity = antiRagdollRootPart.AssemblyLinearVelocity
                if (velocity - lastVelocity).Magnitude > velocityChangeThreshold
                    and velocity.Magnitude > velocityMagnitudeThreshold then
                    antiRagdollRootPart.AssemblyLinearVelocity = velocity.Unit * math.min(velocity.Magnitude, maxVelocity)
                end
                lastVelocity = velocity
            end
        end))

        enableAntiRagdollControls()
        cleanupRagdoll()
    end

    function startAntiRagdoll()
        _G.AntiRagdollEnabled = true
        _G.antiKnockbackEnabled = true
        Config.AntiRagdoll = true; setToggle("Anti Ragdoll", true); saveConfig()
        if player.Character then
            setupAntiRagdollCharacter(player.Character)
            setupAntiRagdollConnections()
        end
    end

    function stopAntiRagdoll()
        _G.AntiRagdollEnabled = false
        _G.antiKnockbackEnabled = false
        Config.AntiRagdoll = false; setToggle("Anti Ragdoll", false); saveConfig()
        clearAntiRagdollConnections()
    end

    _G.toggleAntiRagdoll = function(enabled)
        if enabled then startAntiRagdoll() else stopAntiRagdoll() end
    end
    _G.enableAntiKnockback = function() startAntiRagdoll() end
    _G.disableAntiKnockback = function() stopAntiRagdoll() end

    player.CharacterAdded:Connect(function(char)
        clearAntiRagdollConnections()
        antiRagdollCharacter = nil; antiRagdollHumanoid = nil; antiRagdollRootPart = nil; antiRagdollAnimator = nil
        local humanoid = char:WaitForChild("Humanoid", 10)
        local rootPart = char:WaitForChild("HumanoidRootPart", 10)
        if not humanoid or not rootPart then return end
        task.wait(0.2)
        setupAntiRagdollCharacter(char)
        if _G.AntiRagdollEnabled or _G.antiKnockbackEnabled then
            setupAntiRagdollConnections()
        end
    end)

    if player.Character then
        setupAntiRagdollCharacter(player.Character)
        if _G.AntiRagdollEnabled or _G.antiKnockbackEnabled then
            setupAntiRagdollConnections()
        end
    end
end

local function applyUnwalk(char, on)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    local animate = char:FindFirstChild("Animate")
    if on then
        if animate then animate.Disabled = true end
        if animator then
            local ok, tracks = pcall(function() return animator:GetPlayingAnimationTracks() end)
            if ok and tracks then
                for _, t in ipairs(tracks) do pcall(function() t:Stop(0) end) end
            end
        end
    else
        if animate then animate.Disabled = false end
    end
end

local function setUnwalk(on)
    Config.Unwalk = on
    saveConfig()
    setToggle("Unwalk", on)
    if on then
        task.spawn(function()
            local char = player.Character
            for i = 1, 6 do
                if not Config.Unwalk or player.Character ~= char then break end
                applyUnwalk(char, true)
                task.wait(0.3)
            end
        end)
    else
        applyUnwalk(player.Character, false)
    end
end
_G.setUnwalk = setUnwalk

player.CharacterAdded:Connect(function(char)
    task.spawn(function()
        char:WaitForChild("Humanoid", 10)
        task.wait(0.1)
        if Config.Unwalk then
            for i = 1, 6 do
                if not Config.Unwalk or player.Character ~= char then break end
                applyUnwalk(char, true)
                task.wait(0.3)
            end
        end
    end)
end)

local function isMyPlot_Instant(plotName)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return false end

    -- Method 1: Synchronizer check 
    local syncSuccess = false
    local isOwner = false
    pcall(function()
        local Packages = ReplicatedStorage:FindFirstChild("Packages")
        local Synchronizer = Packages and require(Packages:FindFirstChild("Synchronizer"))
        if Synchronizer then
            local ch = Synchronizer:Get(plotName)
            if ch then
                local own = _G.sProp(ch, "Owner")
                if own then
                    syncSuccess = true
                    if (typeof(own) == "Instance" and own == player) or
                       (typeof(own) == "table" and own.UserId == player.UserId) or
                       (typeof(own) == "number" and own == player.UserId) or
                       (typeof(own) == "string" and (own:lower() == player.Name:lower() or own:lower() == player.DisplayName:lower())) then
                        isOwner = true
                    end
                end
            end
        end
    end)
    if syncSuccess then return isOwner end

    -- Method 2: SurfaceGui TextLabel check (Display Name or Username)
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local surfaceGui = sign:FindFirstChildWhichIsA("SurfaceGui", true)
        if surfaceGui then
            local label = surfaceGui:FindFirstChildWhichIsA("TextLabel", true)
            if label then
                local text = label.Text:lower()
                if text:find(player.DisplayName:lower(), 1, true) or text:find(player.Name:lower(), 1, true) then
                    return true
                end
            end
        end
    end

    -- Method 3: BillboardGui "YourBase" check
    if sign then
        local yb = sign:FindFirstChild("YourBase")
        if yb and yb:IsA("BillboardGui") and yb.Enabled == true then
            return true
        end
    end

    return false
end
_G.isMyPlot_Instant = isMyPlot_Instant

-- UNLOCK BASE 
local function getUnlockHRP()
    local c = LocalPlayer.Character or player.Character
    if not c then return end
    return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso")
end

local function smartInteract(number)
    local char = LocalPlayer.Character or player.Character
    local hrp = getUnlockHRP()
    if not char or not hrp then return end

    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end

    local closestPlot, minDistance = nil, 40

    for _, plot in pairs(plots:GetChildren()) do
        local plotPos
        if plot:IsA("Model") then
            plotPos = plot.PrimaryPart and plot.PrimaryPart.Position or plot:GetPivot().Position
        else
            plotPos = plot.Position
        end

        local dist = (hrp.Position - plotPos).Magnitude
        if dist < minDistance then
            closestPlot = plot
            minDistance = dist
        end
    end

    if closestPlot and closestPlot:FindFirstChild("Unlock") then
        local items = {}

        for _, item in pairs(closestPlot.Unlock:GetChildren()) do
            local pos = item:IsA("Model") and item:GetPivot().Position or item.Position
            table.insert(items, {
                Obj = item,
                Y = pos.Y
            })
        end

        table.sort(items, function(a, b)
            return a.Y < b.Y
        end)

        if items[number] then
            for _, pr in pairs(items[number].Obj:GetDescendants()) do
                if pr:IsA("ProximityPrompt") then
                    pcall(function()
                        fireproximityprompt(pr)
                    end)
                end
            end
        end
    end
end

local function getCurrentUnlockFloor()
    local hrp = getUnlockHRP()
    if not hrp then return 1 end

    local y = hrp.Position.Y
    if y < 12 then
        return 1
    else
        return 2
    end
end

-- PROXIMITY AP
ProximityAPActive=false
proxAPRing = nil

local function createProxAPRing()
    local existing = Workspace:FindFirstChild("XiProxAPRing")
    if existing then existing:Destroy() end
    local r = Instance.new("Part")
    r.Name = "XiProxAPRing"
    r.Shape = Enum.PartType.Cylinder
    r.Anchored = true
    r.CanCollide = false
    r.CanTouch = false
    r.CanQuery = false
    r.CastShadow = false
    r.Material = Enum.Material.Neon
    r.Transparency = 0.8
    r.Color = Color3.fromRGB(232, 111, 177)
    local range = Config.ProximityRange or 15
    r.Size = Vector3.new(0.2, range*2, range*2)
    r.Parent = Workspace
    proxAPRing = r
end

local function destroyProxAPRing()
    if proxAPRing then proxAPRing:Destroy(); proxAPRing = nil end
    local e = Workspace:FindFirstChild("XiProxAPRing")
    if e then e:Destroy() end
end

_proxAPRingFrame=0
RunService.Heartbeat:Connect(function()
    if not ProximityAPActive then return end
    _proxAPRingFrame = _proxAPRingFrame + 1
    if _proxAPRingFrame < 2 then return end
    _proxAPRingFrame = 0
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not proxAPRing then return end
    local range = Config.ProximityRange or 15
    proxAPRing.Size = Vector3.new(0.2, range * 2, range * 2)
    proxAPRing.CFrame = (hrp.CFrame * CFrame.Angles(0, 0, math.rad(90))) - Vector3.new(0, 2.8, 0)
end)

local function setProximityAP(on)
    ProximityAPActive = on
    -- Never save ProximityAP to config â€” always starts OFF
    Config.ProximityAP = false
    setToggle("Proximity", on)
    if on then createProxAPRing() else destroyProxAPRing() end
end

onToggleChanged("Proximity", function(on)
    ProximityAPActive = on
    -- Never save ProximityAP to config â€” always starts OFF
    Config.ProximityAP = false
    if on then createProxAPRing() else destroyProxAPRing() end
end)

task.spawn(function()
    while true do
        task.wait(0.2)
        if ProximityAPActive then
            local mc = player.Character
            local mh = mc and mc:FindFirstChild("HumanoidRootPart")
            if mh then
                for _,p in ipairs(Players:GetPlayers()) do
                    if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                        if isPlayerBlacklisted(p) then continue end
                        if (p.Character.HumanoidRootPart.Position - mh.Position).Magnitude <= (Config.ProximityRange or 15) then
                            local activeCmds = {}
                            for _,cmd in ipairs(AP_ALL_COMMANDS) do
                                if not apIsOnCooldown(cmd) then
                                    table.insert(activeCmds, cmd)
                                end
                            end
                            for i, cmd in ipairs(activeCmds) do
                                task.spawn(function()
                                    task.wait((i - 1) * 0.01)
                                    runAdminCommand(p, cmd)
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- AUTO RESET ON BALLOON / AUTO KICK ON STEAL / CLEAN ERRORS
task.spawn(function() while true do task.wait(1); if not Config.AutoResetBalloon then continue end
    for _,g in ipairs(playerGui:GetDescendants()) do local txt=(g:IsA("TextLabel") or g:IsA("TextButton")) and g.Text
        if txt and string.find(txt,'ran "balloon" on you') then executeReset(true); break end end end end)

task.spawn(function() local kw="you stole"; local hooked=setmetatable({},{__mode="k"})
    local function hookObj(obj) if hooked[obj] then return end; hooked[obj]=true
        if Config.AutoKickOnSteal and string.find(string.lower(tostring(obj.Text or "")),kw,1,true) then kickPlayer(tostring(obj.Text or "")); return end
        obj:GetPropertyChangedSignal("Text"):Connect(function() if Config.AutoKickOnSteal and string.find(string.lower(tostring(obj.Text or "")),kw,1,true) then kickPlayer(tostring(obj.Text or "")) end end)
    end
    local function watchRoot(root) for _,obj in ipairs(root:GetDescendants()) do if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then hookObj(obj) end end
        root.DescendantAdded:Connect(function(desc) if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then hookObj(desc) end end) end
    for _,g in ipairs(playerGui:GetChildren()) do watchRoot(g) end; playerGui.ChildAdded:Connect(function(g) watchRoot(g) end)
end)

task.spawn(function() local GS=pcall(function() return cloneref(game:GetService("GuiService")) end) and cloneref(game:GetService("GuiService")) or game:GetService("GuiService")
    while true do if Config.CleanErrorGUIs then pcall(function() GS:ClearError() end) end; task.wait(0.1) end end)

-- ============================================================
-- AUTO STEAL / GRAB
-- ============================================================
do
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Datas = ReplicatedStorage:WaitForChild("Datas")
local Synchronizer = require(Packages:WaitForChild("Synchronizer"))
local AnimalsData = require(Datas:WaitForChild("Animals"))

autoStealEnabled = Config.AutoStealEnabled
if autoStealEnabled == nil then autoStealEnabled = true end
instantStealEnabled = Config.InstantStealEnabled
if instantStealEnabled == nil then instantStealEnabled = true end
stealHighestEnabled = Config.StealHighest
if stealHighestEnabled == nil then stealHighestEnabled = true end
stealPriorityEnabled = Config.StealPriority
stealNearestEnabled = Config.StealNearest
selectedTargetIndex = 1
selectedTargetUID = nil
manuallySelectedUID = nil
currentStealTargetUID = nil
activeProgressTween = nil
instantStealReady = false
instantStealDidInit = false
INSTANT_STEAL_RADIUS = 60
INSTANT_STEAL_COOLDOWN = 0
lastInstantStealTime = 0
PromptMemoryCache = {}
InternalStealCacheData = {}

-- ============================================================
-- AUTO GRAB INTEGRATION 
-- ============================================================
local CONFIG = {
    AUTO_STEAL = false,
    RADIUS = 60
}

local boxes = {
    {min = Vector3.new(-337.448303, -3.898971, -122.397758), max = Vector3.new(-328.004578, -3.898971, 242.625626)},
    {min = Vector3.new(-327.257660, -3.899109, -122.228622), max = Vector3.new(-320.600891, -3.899109, 242.612259)},
    {min = Vector3.new(-319.783386, -3.898970, -122.227089), max = Vector3.new(-312.908325, -3.898970, 242.585617)},
    {min = Vector3.new(-312.445648, -3.899108, -122.389832), max = Vector3.new(-305.489899, -3.899108, 242.456818)},
    {min = Vector3.new(-305.037048, -3.898970, -122.230743), max = Vector3.new(-293.957489, -3.898970, 242.606873)},
    {min = Vector3.new(-491.448608, -3.898972, -122.253258), max = Vector3.new(-481.811737, -3.898972, 242.615005)},
    {min = Vector3.new(-498.971069, -3.898970, -122.382767), max = Vector3.new(-491.748840, -3.898970, 242.612061)},
    {min = Vector3.new(-506.436737, -3.898972, -122.411476), max = Vector3.new(-499.318542, -3.898972, 242.615982)},
    {min = Vector3.new(-513.783569, -3.898972, -122.223297), max = Vector3.new(-506.801849, -3.898972, 242.627090)},
    {min = Vector3.new(-525.236938, -3.898972, -122.409813), max = Vector3.new(-514.265015, -3.898972, 242.608932)},
}

local trackedPrompts = {}
local lastFire = {}

local SAFE_POLL_RATE = 0.05
local SAFE_POLL_OVERRIDE_UNTIL = 0

function _G.getSafePollRate()
    if os.clock() < SAFE_POLL_OVERRIDE_UNTIL then
        return 0.27
    end
    return SAFE_POLL_RATE
end

function _G.triggerSafePollBoost()
    SAFE_POLL_OVERRIDE_UNTIL = os.clock() + 3
end

local FIRE_DEBOUNCE = 0.12
local FIRE_BURST = 4
local ENABLE_BURST = 35
local ENABLE_DEBOUNCE = 0.00
local ENABLE_COOLDOWN = 0.08
local lastEnableFire = {}

local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getBoxIndex(pos)
    for i,b in ipairs(boxes) do
        if pos.X >= math.min(b.min.X,b.max.X) and pos.X <= math.max(b.min.X,b.max.X)
        and pos.Z >= math.min(b.min.Z,b.max.Z) and pos.Z <= math.max(b.min.Z,b.max.Z) then
            return i
        end
    end
end

local function getPromptPosition(prompt)
    local p = prompt.Parent
    if not p then return end
    if p:IsA("Attachment") and p.Parent then p = p.Parent end
    if p:IsA("BasePart") then return p.Position elseif p:IsA("Model") then return p:GetPivot().Position end
end

local function promptMatchesSelectedPet(prompt)
    if not SharedState then return false end
    local selected = SharedState.SelectedPetData
    if not selected then return false end
    local model = prompt:FindFirstAncestorOfClass("Model")
    if not model then return false end
    if selected.slot then
        local slotAncestor = prompt:FindFirstAncestor(selected.slot)
        if slotAncestor or model.Name == selected.slot or (model.Parent and model.Parent.Name == selected.slot) then return true end
    end
    local name = selected.name or selected.petName
    if name then
        local wantedName = string.lower(name)
        local current = model
        while current do
            if current.Name and string.lower(current.Name) == wantedName then return true end
            current = current.Parent
        end
    end
    return false
end

local function isPromptAvailable(prompt, hrpPos)
    if not autoStealEnabled or not instantStealEnabled then return false end
    if not prompt or not prompt.Parent or not prompt.Enabled then return false end
    local pos = getPromptPosition(prompt)
    if not pos then return false end
    local plot = prompt:FindFirstAncestorOfClass("Model")
    if plot then
        local plots = workspace:FindFirstChild("Plots")
        if plots then
            local parentPlot = prompt:FindFirstAncestorWhichIsA("Model")
            while parentPlot and parentPlot.Parent ~= plots do parentPlot = parentPlot.Parent end
            if parentPlot then
                local sign = parentPlot:FindFirstChild("PlotSign")
                if sign then
                    local gui = sign:FindFirstChildWhichIsA("SurfaceGui", true)
                    local label = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
                    if label then
                        local txt = label.Text:lower()
                        if txt:find(game.Players.LocalPlayer.Name:lower(), 1, true) or txt:find(game.Players.LocalPlayer.DisplayName:lower(), 1, true) then return false end
                    end
                end
            end
        end
    end
    if _G.NEAREST_INSTANT_MODE == true then
        -- Box checks removed to allow nearest to work globally based on radius
    end
    if not (_G.NEAREST_INSTANT_MODE == true) then
        if not promptMatchesSelectedPet(prompt) then return false end
    end
    local configuredRadius = Config.AutoGrabRadius or 60
    return (pos - hrpPos).Magnitude <= configuredRadius
end

local function canFire(prompt, debounce)
    local t = os.clock()
    local last = lastFire[prompt]
    if last and (t - last) < debounce then return false end
    lastFire[prompt] = t
    return true
end

local function firePrompt(prompt, burst, debounce)
    if not prompt or not prompt.Parent or not prompt.Enabled or not canFire(prompt, debounce) then return end
    for i = 1, burst do pcall(function() fireproximityprompt(prompt, 0) end) end
end

local function trackPrompt(prompt)
    if trackedPrompts[prompt] then return end
    trackedPrompts[prompt] = true
    local function tryInstantEnableFire()
        if not autoStealEnabled or not instantStealEnabled then return end
        local hrp = getHRP()
        if hrp and isPromptAvailable(prompt, hrp.Position) then
            CONFIG.AUTO_STEAL = true
            local now = os.clock()
            local le = lastEnableFire[prompt]
            if not le or (now - le) >= ENABLE_COOLDOWN then
                lastEnableFire[prompt] = now
                firePrompt(prompt, ENABLE_BURST, ENABLE_DEBOUNCE)
            end
        end
    end
    task.defer(tryInstantEnableFire)
    pcall(function() prompt:GetPropertyChangedSignal("Enabled"):Connect(function() if prompt.Enabled then tryInstantEnableFire() end end) end)
    prompt.AncestryChanged:Connect(function() if not prompt:IsDescendantOf(workspace) then trackedPrompts[prompt] = nil; lastFire[prompt] = nil; lastEnableFire[prompt] = nil end end)
end

local function scanBrainrotPrompts()
    local plots = workspace:FindFirstChild("Plots")
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            local podiums = plot:FindFirstChild("AnimalPodiums")
            if podiums then
                for _, obj in ipairs(podiums:GetDescendants()) do
                    if obj:IsA("ProximityPrompt") then trackPrompt(obj) end
                end
            end
        end
    end
end

scanBrainrotPrompts()
workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("ProximityPrompt") and obj:FindFirstAncestor("AnimalPodiums") then trackPrompt(obj) end
end)

task.spawn(function()
    while task.wait(_G.getSafePollRate()) do
        _G.NEAREST_INSTANT_MODE = (stealNearestEnabled == true)
        if autoStealEnabled and instantStealEnabled then
            local hrp = getHRP()
            if not hrp then CONFIG.AUTO_STEAL = false; continue end
            local myPos = hrp.Position
            local anyAvailable = false
            for prompt in pairs(trackedPrompts) do
                if isPromptAvailable(prompt, myPos) then
                    anyAvailable = true
                    if CONFIG.AUTO_STEAL then firePrompt(prompt, FIRE_BURST, FIRE_DEBOUNCE) end
                end
            end
            CONFIG.AUTO_STEAL = anyAvailable
        else
            CONFIG.AUTO_STEAL = false
        end
    end
end)

local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    return isMyPlot_Instant(animalData.plot)
end

function get_all_pets()
    local out = {}
    local cache = SharedState.AllAnimalsCache
    local minGenStr = Config.StealNearest and Config.TpSettings.MinGenForGrab or Config.TpSettings.MinGenForTp
    local minGen = parseMinGen(minGenStr)
    local myName = LocalPlayer.Name
    local myDisplay = LocalPlayer.DisplayName
    local prioSet = {}
    for _, p in ipairs(priorityList) do prioSet[p:lower()] = true end
    if cache and type(cache) == "table" then
        for _, a in ipairs(cache) do
            if a and (a.genValue or 0) >= 1 and a.owner ~= myName and a.owner ~= myDisplay then
                local isBrainrot = ((tonumber(a.genValue) or 0) >= 10000000)
                local isPriority = (a.name and prioSet[a.name:lower()]) or (a.index and prioSet[a.index:lower()])
                if isBrainrot and a.name then SharedState.BrainrotNames[a.name:lower()] = true end
                if minGen > 0 and (tonumber(a.genValue) or 0) < minGen then
                    if not isBrainrot and not isPriority then continue end
                end
                table.insert(out, {
                    name = a.name,
                    petName = a.name,
                    mpsText = a.genText,
                    mpsValue = a.genValue,
                    petValue = a.petValue or 0,
                    owner = a.owner,
                    plot = a.plot,
                    slot = a.slot,
                    uid = a.uid,
                    mutation = a.mutation,
                    animalData = a,
                })
            end
        end
    end
    table.sort(out, function(a, b) return (a.mpsValue or 0) > (b.mpsValue or 0) end)
    return out
end

function get_all_pets_by_value()
    local out = {}
    local cache = SharedState.AllAnimalsCache
    local minGenStr = Config.StealNearest and Config.TpSettings.MinGenForGrab or Config.TpSettings.MinGenForTp
    local minGen = parseMinGen(minGenStr)
    local myName = LocalPlayer.Name
    local myDisplay = LocalPlayer.DisplayName
    if cache and type(cache) == "table" then
        for _, a in ipairs(cache) do
            if a and (a.genValue or 0) >= 1 and a.owner ~= myName and a.owner ~= myDisplay then
                if minGen > 0 and (tonumber(a.genValue) or 0) < minGen then continue end
                table.insert(out, {
                    name = a.name,
                    petName = a.name,
                    mpsText = a.genText,
                    mpsValue = a.genValue,
                    petValue = a.petValue or 0,
                    owner = a.owner,
                    plot = a.plot,
                    slot = a.slot,
                    uid = a.uid,
                    mutation = a.mutation,
                    animalData = a,
                })
            end
        end
    end
    table.sort(out, function(a, b) return (a.petValue or 0) > (b.petValue or 0) end)
    return out
end

function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end
    local cp = PromptMemoryCache[animalData.uid]
    if cp and cp.Parent then return cp end
    local plot = Workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local ch = Synchronizer:Get(plot.Name)
    if not ch then
        local podium = podiums:FindFirstChild(animalData.slot)
        if podium then
            local base = podium:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn")
            if spawn then
                local attach = spawn:FindFirstChild("PromptAttachment")
                if attach then
                    for _, p in ipairs(attach:GetChildren()) do
                        if p:IsA("ProximityPrompt") then
                            PromptMemoryCache[animalData.uid] = p
                            return p
                        end
                    end
                end
            end
        end
        return nil
    end
    local al = ch:Get("AnimalList")
    if not al then return nil end
    local brainrotName = (animalData.name and animalData.name:lower()) or ""
    local targetSlot = animalData.slot
    local foundPodium = nil
    for slot, ad in pairs(al) do
        if (type(ad) == "table") and (tostring(slot) == targetSlot) then
            local aName, aInfo = ad.Index, AnimalsData[ad.Index]
            if aInfo and ((aInfo.DisplayName or aName):lower() == brainrotName) then
                foundPodium = podiums:FindFirstChild(tostring(slot))
                break
            end
        end
    end
    if not foundPodium then foundPodium = podiums:FindFirstChild(animalData.slot) end
    if foundPodium then
        local base = foundPodium:FindFirstChild("Base")
        local spawn = base and base:FindFirstChild("Spawn")
        if spawn then
            local attach = spawn:FindFirstChild("PromptAttachment")
            if attach then
                for _, p in ipairs(attach:GetChildren()) do
                    if p:IsA("ProximityPrompt") and p.Enabled and (p.ActionText:lower():find("steal") or p.ActionText == "") then
                        PromptMemoryCache[animalData.uid] = p
                        return p
                    end
                end
            end
            local startPos = spawn.Position
            local slotX, slotZ = startPos.X, startPos.Z
            local nearestPrompt = nil
            local minDist = math.huge
            for _, desc in pairs(plot:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and desc.Enabled and (desc.ActionText:lower():find("steal") or desc.ActionText == "") then
                    local part = desc.Parent
                    local promptPos = nil
                    if part and part:IsA("BasePart") then
                        promptPos = part.Position
                    elseif part and part:IsA("Attachment") and part.Parent and part.Parent:IsA("BasePart") then
                        promptPos = part.Parent.Position
                    end
                    if promptPos then
                        local checkStartY = startPos.Y
                        if brainrotName:find("la secret combinasion") then checkStartY = startPos.Y - 5 end
                        local horizontalDist = math.sqrt(((promptPos.X - slotX) ^ 2) + ((promptPos.Z - slotZ) ^ 2))
                        if (horizontalDist < 5) and (promptPos.Y > checkStartY) then
                            local yDist = promptPos.Y - checkStartY
                            if yDist < minDist then
                                minDist = yDist
                                nearestPrompt = desc
                            end
                        end
                    end
                end
            end
            if nearestPrompt then
                PromptMemoryCache[animalData.uid] = nearestPrompt
                return nearestPrompt
            end
        end
    end
    return nil
end

-- executeInstantSteal logic removed

function setStealMode(mode)
    manuallySelectedUID = nil
    stealHighestEnabled = (mode == "Highest")
    stealPriorityEnabled = (mode == "Priority")
    stealNearestEnabled = (mode == "Nearest")
    Config.StealHighest = stealHighestEnabled
    Config.StealPriority = stealPriorityEnabled
    Config.StealNearest = stealNearestEnabled
    Config.StealMode = mode
    saveConfig()
    setToggle("Steal Highest", stealHighestEnabled)
    setToggle("Steal Priority", stealPriorityEnabled)
    setToggle("Steal Nearest", stealNearestEnabled)
    -- Bridge to SXE Clone-TP engine
    if _G.SXEStealMode then pcall(_G.SXEStealMode, mode) end
end

-- Create the Bottom Steal HUD matching 
local hudGui = playerGui:FindFirstChild("AutoStealCurrentTargetHUD")
if hudGui then hudGui:Destroy() end
hudGui = Instance.new("ScreenGui")
hudGui.Name = "AutoStealCurrentTargetHUD"
hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = true
hudGui.DisplayOrder = 998
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.Parent = playerGui
local STEALBAR = {
    PANEL = Theme.MainBackground,
    TEXT = Theme.Text,
    STROKE = Theme.Stroke,
    GLOW = Theme.Accent,
    TRACK = Theme.SliderBg,
    TRACK2 = Theme.ToggleOff2,
    FILL1 = Theme.Accent,
    FILL2 = Theme.AccentLight,
}

local mobileScale = UIS.TouchEnabled and 0.6 or 1
local targetHud = Instance.new("Frame", hudGui)
targetHud.Name = "CurrentTargetHUD"
targetHud.AnchorPoint = Vector2.new(0.5, 1)
targetHud.Size = UDim2.new(0, 230 * mobileScale, 0, 46 * mobileScale)
targetHud.Position = UDim2.new(0.5, 0, 1, -135)
targetHud.BackgroundColor3 = STEALBAR.PANEL
targetHud.BackgroundTransparency = 0.02
targetHud.BorderSizePixel = 0
targetHud.ZIndex = 70
Instance.new("UICorner", targetHud).CornerRadius = UDim.new(0, math.floor(12 * mobileScale))

local hudStroke = Instance.new("UIStroke", targetHud)
hudStroke.Color = STEALBAR.STROKE
hudStroke.Thickness = 1
hudStroke.Transparency = 0.35

local hudGlow = Instance.new("UIStroke", targetHud)
hudGlow.Color = STEALBAR.GLOW
hudGlow.Thickness = 3
hudGlow.Transparency = 0.84
hudGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local hudShadow = Instance.new("ImageLabel", targetHud)
hudShadow.Name = "Shadow"
hudShadow.AnchorPoint = Vector2.new(0.5, 0.5)
hudShadow.Position = UDim2.new(0.5, 0, 0.5, 1)
hudShadow.Size = UDim2.new(1, 20, 1, 20)
hudShadow.BackgroundTransparency = 1
hudShadow.Image = "rbxassetid://6014261993"
hudShadow.ImageColor3 = Color3.new(0, 0, 0)
hudShadow.ImageTransparency = 0.72
hudShadow.ScaleType = Enum.ScaleType.Slice
hudShadow.SliceCenter = Rect.new(49, 49, 450, 450)
hudShadow.ZIndex = 69

local hudName = Instance.new("TextLabel", targetHud)
hudName.Name = "TargetName"
hudName.Size = UDim2.new(1, -12, 0, 13 * mobileScale)
hudName.Position = UDim2.fromOffset(6 * mobileScale, 3 * mobileScale)
hudName.BackgroundTransparency = 1
hudName.Font = Enum.Font.GothamBold
hudName.TextSize = 11 * mobileScale
hudName.TextColor3 = STEALBAR.TEXT
hudName.TextXAlignment = Enum.TextXAlignment.Center
hudName.TextTruncate = Enum.TextTruncate.AtEnd
hudName.ZIndex = 72
hudName.Text = "No target"

local hudProgressBg = Instance.new("Frame", targetHud)
hudProgressBg.Name = "ProgressBg"
hudProgressBg.Size = UDim2.new(1, -10 * mobileScale, 0, 18 * mobileScale)
hudProgressBg.Position = UDim2.fromOffset(5 * mobileScale, 18 * mobileScale)
hudProgressBg.BackgroundColor3 = STEALBAR.TRACK
hudProgressBg.BorderSizePixel = 0
hudProgressBg.ZIndex = 72
Instance.new("UICorner", hudProgressBg).CornerRadius = UDim.new(0, math.floor(8 * mobileScale))

local hudProgressBgStroke = Instance.new("UIStroke", hudProgressBg)
hudProgressBgStroke.Color = STEALBAR.STROKE
hudProgressBgStroke.Thickness = 1
hudProgressBgStroke.Transparency = 0.55

local hudInnerTrack = Instance.new("Frame", hudProgressBg)
hudInnerTrack.Name = "InnerTrack"
hudInnerTrack.Size = UDim2.new(1, -2, 1, -2)
hudInnerTrack.Position = UDim2.fromOffset(1, 1)
hudInnerTrack.BackgroundColor3 = STEALBAR.TRACK2
hudInnerTrack.BackgroundTransparency = 0.15
hudInnerTrack.BorderSizePixel = 0
hudInnerTrack.ZIndex = 72
Instance.new("UICorner", hudInnerTrack).CornerRadius = UDim.new(0, math.floor(7 * mobileScale))

local hudProgressFill = Instance.new("Frame", hudProgressBg)
hudProgressFill.Name = "ProgressFill"
hudProgressFill.Size = UDim2.new(0, 0, 1, 0)
hudProgressFill.BackgroundColor3 = STEALBAR.FILL1
hudProgressFill.BorderSizePixel = 0
hudProgressFill.ZIndex = 73
Instance.new("UICorner", hudProgressFill).CornerRadius = UDim.new(0, math.floor(8 * mobileScale))

local hudProgressFillGradient = Instance.new("UIGradient", hudProgressFill)
hudProgressFillGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, STEALBAR.FILL1),
    ColorSequenceKeypoint.new(1, STEALBAR.FILL2),
})

local hudProgressFillStroke = Instance.new("UIStroke", hudProgressFill)
hudProgressFillStroke.Color = Color3.fromRGB(255, 255, 255)
hudProgressFillStroke.Thickness = 1
hudProgressFillStroke.Transparency = 0.45

local hudPercent = Instance.new("TextLabel", hudProgressBg)
hudPercent.Name = "Percent"
hudPercent.Size = UDim2.new(1, 0, 1, 0)
hudPercent.BackgroundTransparency = 1
hudPercent.Font = Enum.Font.GothamBold
hudPercent.TextSize = 12 * mobileScale
hudPercent.TextColor3 = STEALBAR.TEXT
hudPercent.TextStrokeTransparency = 0.7
hudPercent.TextXAlignment = Enum.TextXAlignment.Center
hudPercent.ZIndex = 74
hudPercent.Text = "0%"

local function applySelection(newIndex, pets)
    if newIndex and (newIndex >= 1) and (newIndex <= #pets) then
        local newUID = pets[newIndex].uid
        if (selectedTargetIndex ~= newIndex) or (selectedTargetUID ~= newUID) or (SharedState.SelectedPetData == nil) then
            selectedTargetIndex = newIndex
            selectedTargetUID = newUID
            SharedState.SelectedPetData = pets[newIndex]
            if SharedState.SelectedPetData then SharedState.LastTargetedPetMpsValue = SharedState.SelectedPetData.mpsValue or 0 end
        end
    end
end

-- Update Selection Thread
task.spawn(function()
    while true do
        task.wait(0.1)
        if autoStealEnabled then
            local pets = get_all_pets()
            if #pets > 0 then
                if manuallySelectedUID then
                    local found = false
                    for i, p in ipairs(pets) do if p.uid == manuallySelectedUID then applySelection(i, pets); found = true; break end end
                    if not found then manuallySelectedUID = nil; selectedTargetUID = nil; SharedState.SelectedPetData = nil end
                elseif stealPriorityEnabled then
                    local foundPrioIndex = nil
                    for _, pName in ipairs(priorityList) do
                        local searchName = pName:lower()
                        for i, p in ipairs(pets) do if (p.petName and p.petName:lower() == searchName) or (p.animalData and p.animalData.index and p.animalData.index:lower() == searchName) then foundPrioIndex = i; break end end
                        if foundPrioIndex then break end
                    end
                    applySelection(foundPrioIndex, pets)
                elseif stealNearestEnabled then
                    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        local bestIndex, bestDist = nil, math.huge
                        for i, p in ipairs(pets) do
                            local targetPart = p.animalData and findAdorneeGlobal(p.animalData)
                            if targetPart and targetPart:IsA("BasePart") then
                                local d = (hrp.Position - targetPart.Position).Magnitude
                                if d < bestDist then bestDist = d; bestIndex = i end
                            end
                        end
                        if bestIndex then
                            applySelection(bestIndex, pets)
                        else
                            SharedState.SelectedPetData = nil
                        end
                    else applySelection(1, pets) end
                else applySelection(1, pets) end
            else SharedState.SelectedPetData = nil end
        else SharedState.SelectedPetData = nil end
    end
end)

-- Heartbeat loop updating bottom HUD labels & executing steals
local function _pbFmtVal(num)
    if not num or num == 0 then return "0" end
    if num >= 1e9 then return string.format("%.2fb", num / 1e9) end
    if num >= 1e6 then return string.format("%.2fm", num / 1e6) end
    if num >= 1e3 then return string.format("%.1fk", num / 1e3) end
    return tostring(math.floor(num))
end

RunService.RenderStepped:Connect(function()
    if not (Config and Config.AutoStealEnabled) then
        hudName.Text = "Disabled"
        hudProgressFill.Size = UDim2.new(0, 0, 1, 0)
        hudPercent.Text = "0%"
        return
    end

    if LocalPlayer:GetAttribute("Stealing") then
        hudProgressFill.Size = UDim2.new(1, 0, 1, 0)
        hudProgressFill.BackgroundColor3 = Theme.Green or Color3.fromRGB(80, 220, 120)
        hudPercent.Text = "100%"
        hudName.Text = "Carrying Brainrot!"
        return
    end

    local status = _G.SXE_StealStatus or {}
    if status.active then
        local p = math.clamp((tick() - (status.start or 0)) / (status.duration or 1.3), 0, 1)
        hudProgressFill.Size = UDim2.new(p, 0, 1, 0)
        hudPercent.Text = math.floor(p * 100) .. "%"
        hudProgressFill.BackgroundColor3 = (p >= 1) and (Theme.Green or Color3.fromRGB(80, 220, 120)) or (Theme.AccentLight or STEALBAR.FILL1)
        hudName.Text = "Stealing..."
    elseif status.target then
        hudProgressFill.Size = UDim2.new(0, 0, 1, 0)
        hudPercent.Text = "0%"
        hudProgressFill.BackgroundColor3 = Theme.AccentLight or STEALBAR.FILL1
        local vs = _pbFmtVal(status.target.mps or status.target.value)
        hudName.Text = (status.target.name or "Brainrot") .. ((vs ~= "0") and (" - $" .. vs) or "")
    else
        hudProgressFill.Size = UDim2.new(0, 0, 1, 0)
        hudPercent.Text = "0%"
        hudProgressFill.BackgroundColor3 = Theme.AccentLight or STEALBAR.FILL1
        hudName.Text = "Searching..."
    end
end)

end


-- ============================================================
-- PRIORITY ALERT (SXE Styled 3D Viewer with Sorting Queue)
-- ============================================================
local function ShowPriorityAlertImpl(brainrotName, genText, mutation, ownerUsername)
    local normalizedMutation = mutation and mutation:gsub("%s+", ""):lower() or ""
    
    local mutationColors = {
        ["gold"] = Color3.fromRGB(255, 222, 89),
        ["diamond"] = Color3.fromRGB(37, 196, 254),
        ["bloodrot"] = Color3.fromRGB(145, 0, 27),
        ["rainbow"] = Color3.fromRGB(255, 0, 251),
        ["candy"] = Color3.fromRGB(255, 70, 246),
        ["lava"] = Color3.fromRGB(255, 149, 0),
        ["galaxy"] = Color3.fromRGB(170, 60, 255),
        ["yinyang"] = Color3.fromRGB(255, 255, 255),
        ["radioactive"] = Color3.fromRGB(104, 245, 0),
        ["cursed"] = Color3.fromRGB(245, 56, 56),
        ["divine"] = Color3.fromRGB(255, 209, 59),
        ["cyber"] = Color3.fromRGB(121, 219, 255)
    }
    
    local ExploitGui = (gethui and gethui()) or game:GetService("CoreGui")
    local strokeColor = mutationColors[normalizedMutation] or Theme.AccentLight
    local txtColor = Theme.Text
    local subColor = mutationColors[normalizedMutation] or Theme.Dim
    
    local subText = ""
    if normalizedMutation ~= "" and normalizedMutation ~= "none" then
        subText = mutation:upper()
    else
        subText = "NORMAL"
    end
    
    local existing = ExploitGui:FindFirstChild("XiPriorityAlertTest")
    if existing then existing:Destroy() end
    
    if Config.PrioritySoundAlert and Config.PrioritySoundID and Config.PrioritySoundID ~= "" then
        pcall(function()
            local sid = Config.PrioritySoundID:match("%d+")
            if sid then
                local snd = Instance.new("Sound")
                snd.SoundId = "rbxassetid://" .. sid
                snd.Volume = 1
                snd.Parent = game:GetService("SoundService")
                snd:Play()
                game:GetService("Debris"):AddItem(snd, 5)
            end
        end)
    end
    
    local alertGui = Instance.new("ScreenGui")
    if _G.addLazyUI then _G.addLazyUI(alertGui, true, true) end
    alertGui.Name = "XiPriorityAlertTest"
    alertGui.ResetOnSpawn = false
    alertGui.DisplayOrder = 999
    alertGui.Parent = ExploitGui
    
    local alertFrame = Instance.new("Frame")
    alertFrame.Size = UDim2.new(0, 360, 0, 70)
    alertFrame.Position = UDim2.new(0.5, 0, 0, -100) -- Start off-screen top
    alertFrame.AnchorPoint = Vector2.new(0.5, 0)
    alertFrame.BackgroundColor3 = Theme.MainBackground
    alertFrame.BackgroundTransparency = 0.08
    alertFrame.BorderSizePixel = 0
    alertFrame.Parent = registerScreenGui(alertGui)
    
    local gradient = Instance.new("UIGradient", alertFrame)
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.MainBackground),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 244, 249))
    })
    gradient.Rotation = 90
    
    local corner = Instance.new("UICorner", alertFrame)
    corner.CornerRadius = UDim.new(0, 10)
    
    local stroke = Instance.new("UIStroke", alertFrame)
    stroke.Color = strokeColor
    stroke.Thickness = 1.5
    stroke.Transparency = 0.12
    
    local bottomAccent = Instance.new("Frame", alertFrame)
    bottomAccent.Size = UDim2.new(1, -24, 0, 3)
    bottomAccent.Position = UDim2.new(0.5, 0, 1, -4)
    bottomAccent.AnchorPoint = Vector2.new(0.5, 1)
    bottomAccent.BackgroundColor3 = strokeColor
    bottomAccent.BorderSizePixel = 0
    local bottomCorner = Instance.new("UICorner", bottomAccent)
    bottomCorner.CornerRadius = UDim.new(1, 0)
    
    -- 3D Model ViewportFrame on the left
    local viewportFrame = Instance.new("ViewportFrame", alertFrame)
    viewportFrame.Size = UDim2.new(0, 56, 0, 56)
    viewportFrame.Position = UDim2.new(0, 12, 0.5, -2)
    viewportFrame.AnchorPoint = Vector2.new(0, 0.5)
    viewportFrame.BackgroundTransparency = 1
    viewportFrame.BorderSizePixel = 0
    viewportFrame.Ambient = Color3.fromRGB(255, 255, 255)
    viewportFrame.LightColor = strokeColor
    
    local worldModel = Instance.new("WorldModel", viewportFrame)
    local camera = Instance.new("Camera", viewportFrame)
    viewportFrame.CurrentCamera = camera
    
    task.spawn(function()
        local modelsFolder = ReplicatedStorage:FindFirstChild("Models") and ReplicatedStorage.Models:FindFirstChild("Animals")
        local animationsFolder = ReplicatedStorage:FindFirstChild("Animations") and ReplicatedStorage.Animations:FindFirstChild("Animals")
        
        if modelsFolder and brainrotName then
            local sourceModel = modelsFolder:FindFirstChild(brainrotName)
            if not sourceModel then
                for _, child in pairs(modelsFolder:GetChildren()) do
                    if child.Name:lower() == brainrotName:lower() then
                        sourceModel = child
                        break
                    end
                end
            end
            
            if sourceModel then
                local modelClone = sourceModel:Clone()
                modelClone.Parent = worldModel
                
                local cframe, size = modelClone:GetBoundingBox()
                local maxAxis = math.max(size.X, size.Y, size.Z)
                
                if modelClone.PrimaryPart then
                    modelClone:SetPrimaryPartCFrame(CFrame.new(0, 0, 0))
                else
                    modelClone:MoveTo(Vector3.new(0, 0, 0))
                end
                
                -- Zoomed in camera offset
                local cameraOffset = Vector3.new(0, size.Y / 2, -(maxAxis * 0.85))
                camera.CFrame = CFrame.lookAt(cameraOffset, Vector3.new(0, 0, 0))
                
                if animationsFolder then
                    local animFolder = animationsFolder:FindFirstChild(sourceModel.Name)
                    local idleAnim = animFolder and animFolder:FindFirstChild("Idle")
                    if idleAnim and idleAnim:IsA("Animation") then
                        local animator = nil
                        local humanoid = modelClone:FindFirstChildOfClass("Humanoid")
                        local animController = modelClone:FindFirstChildOfClass("AnimationController")
 
                        if humanoid then
                            animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
                        elseif animController then
                            animator = animController:FindFirstChildOfClass("Animator") or Instance.new("Animator", animController)
                        else
                            animController = Instance.new("AnimationController", modelClone)
                            animator = Instance.new("Animator", animController)
                        end
 
                        local animTrack = animator:LoadAnimation(idleAnim)
                        animTrack.Looped = true
                        animTrack:Play(0)
                        task.delay(0.01, function()
                            if animTrack.IsPlaying then
                                animTrack.TimePosition = 0.2
                            end
                        end)
                    end
                end
            end
        end
    end)
    
    local titleLabel = Instance.new("TextLabel", alertFrame)
    titleLabel.Size = UDim2.new(1, -85, 0, 20)
    titleLabel.Position = UDim2.new(0, 76, 0, 12)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = brainrotName .. " • " .. genText
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.TextSize = 13
    titleLabel.TextColor3 = txtColor
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    
    local subLabel = Instance.new("TextLabel", alertFrame)
    subLabel.Size = UDim2.new(1, -85, 0, 16)
    subLabel.Position = UDim2.new(0, 76, 0, 32)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = subText .. " (Owner: " .. ownerUsername .. ")"
    subLabel.Font = Enum.Font.GothamBold
    subLabel.TextSize = 10
    subLabel.TextColor3 = subColor
    subLabel.TextXAlignment = Enum.TextXAlignment.Left

    TweenService:Create(alertFrame, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, 20)
    }):Play()
    
    task.delay(4, function()
        if alertFrame and alertFrame.Parent then
            TweenService:Create(alertFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
                Position = UDim2.new(0.5, 0, 0, -100)
            }):Play()
            task.wait(0.45)
            if alertGui and alertGui.Parent then alertGui:Destroy() end
        end
    end)
end

local highestAlertedPriorityIndex = 99999

task.spawn(function()
    while true do
        task.wait(1.5)
        pcall(function()
            local cache = SharedState.AllAnimalsCache
            if not cache or #cache == 0 then return end
            
            local bestPet = nil
            local bestPriorityIndex = 99999
            
            for _, pet in ipairs(cache) do
                local priorityIndex = nil
                for idx, pName in ipairs(priorityList) do
                    if pName:lower() == pet.name:lower() then
                        priorityIndex = idx
                        break
                    end
                end
                
                if priorityIndex then
                    if priorityIndex < bestPriorityIndex then
                        bestPriorityIndex = priorityIndex
                        bestPet = pet
                    end
                end
            end
            
            if bestPet and bestPriorityIndex < highestAlertedPriorityIndex then
                local myName = LocalPlayer.Name
                local myDisplay = LocalPlayer.DisplayName
                if bestPet.owner ~= myName and bestPet.owner ~= myDisplay then
                    highestAlertedPriorityIndex = bestPriorityIndex
                    ShowPriorityAlertImpl(bestPet.name, bestPet.genText, bestPet.mutation, bestPet.owner)
                end
            end
        end)
    end
end)

-- ============================================================
-- PRIORITY SCANNER
-- ============================================================
local PRIORITY_LIST = priorityList
task.spawn(function()
    local ok1,Packages=pcall(function() return ReplicatedStorage:WaitForChild("Packages",5) end); if not ok1 or not Packages then return end
    local ok2,Datas=pcall(function() return ReplicatedStorage:WaitForChild("Datas",5) end); if not ok2 or not Datas then return end
    local ok3,Shared=pcall(function() return ReplicatedStorage:WaitForChild("Shared",5) end); if not ok3 or not Shared then return end
    local ok4,Utils=pcall(function() return ReplicatedStorage:WaitForChild("Utils",5) end); if not ok4 or not Utils then return end
    local okS,Synchronizer=pcall(function() return require(Packages:WaitForChild("Synchronizer")) end); if not okS then return end
    local okA,AnimalsData=pcall(function() return require(Datas:WaitForChild("Animals")) end); if not okA then return end
    local okAS,AnimalsShared=pcall(function() return require(Shared:WaitForChild("Animals")) end); if not okAS then return end
    local okN,NumberUtils=pcall(function() return require(Utils:WaitForChild("NumberUtils")) end); if not okN then return end
    local allAnimalsCache={}; local lastAnimalData={}
    local function getAnimalHash(al) if not al then return "" end; local h=""; for slot,d in pairs(al) do if type(d)=="table" then h=h..tostring(slot)..tostring(d.Index)..tostring(d.Mutation) end end; return h end
    local function scanSinglePlot(plot) pcall(function()
        local ch=Synchronizer:Get(plot.Name); if not ch then return end
        local al=ch:Get("AnimalList"); local owner=ch:Get("Owner")
        if not owner or not owner.Name or not Players:FindFirstChild(owner.Name) then
            lastAnimalData[plot.Name]=nil; for i=#allAnimalsCache,1,-1 do if allAnimalsCache[i].plot==plot.Name then table.remove(allAnimalsCache,i) end end; return end
        if not al then lastAnimalData[plot.Name]=nil; for i=#allAnimalsCache,1,-1 do if allAnimalsCache[i].plot==plot.Name then table.remove(allAnimalsCache,i) end end; return end
        local ownerName=owner.Name; local hash=getAnimalHash(al)
        if lastAnimalData[plot.Name]==hash then return end
        
        for i=#allAnimalsCache,1,-1 do if allAnimalsCache[i].plot==plot.Name then table.remove(allAnimalsCache,i) end end
        for slot,ad in pairs(al) do if type(ad)=="table" then
            local aName,aInfo=ad.Index,AnimalsData[ad.Index]; if aInfo then
                local mut=ad.Mutation or "None"; if mut=="Yin Yang" then mut="YinYang" end
                local traits=(ad.Traits and #ad.Traits>0) and table.concat(ad.Traits,", ") or "None"
                local gv=AnimalsShared:GetGeneration(aName,ad.Mutation,ad.Traits,nil)
                local gt="$"..NumberUtils:ToString(gv).."/s"
                local pv=0; pcall(function() pv=AnimalsShared:GetValue(aName,ad.Mutation,ad.Traits,nil) or 0 end)
                if type(pv)~="number" then pv=0 end
                table.insert(allAnimalsCache,{name=aInfo.DisplayName or aName,index=aName,genText=gt,genValue=gv,petValue=pv,mutation=mut,traits=traits,owner=ownerName,plot=plot.Name,slot=tostring(slot),uid=plot.Name.."_"..tostring(slot)})
            end
        end end
        lastAnimalData[plot.Name]=hash
        table.sort(allAnimalsCache,function(a,b) return a.genValue>b.genValue end)
        SharedState.AllAnimalsCache=allAnimalsCache; SharedState.ListNeedsRedraw=true
    end) end
    -- Brainrot scanner (brxken model): NO DescendantAdded/DescendantRemoving
    -- listeners. Those fired thousands of times while every plot's parts streamed
    -- in at startup -> that was the freeze/lag. Each plot instead gets ONE light
    -- 0.5s periodic rescan; scanSinglePlot is hash-gated, so it's a cheap no-op
    -- whenever a plot's AnimalList hasn't changed. retries softened (40 @ 0.07s)
    -- so the channel wait doesn't spin tight during load.
    local function setupPlotListener(plot) local ch; local retries=0
        while not ch and retries<40 do local ok,r=pcall(function() return Synchronizer:Get(plot.Name) end); if ok and r then ch=r; break else retries=retries+1; task.wait(0.07) end end
        if not ch then return end; scanSinglePlot(plot)
        task.spawn(function() while plot.Parent do task.wait(0.5); scanSinglePlot(plot) end end)
    end
    local plots=Workspace:WaitForChild("Plots",8)
    if plots then
        for _,p in ipairs(plots:GetChildren()) do
            task.spawn(setupPlotListener, p)
        end
        SharedState.InitialScanComplete=true
        plots.ChildAdded:Connect(function(p) task.wait(0.5); task.spawn(setupPlotListener, p) end)
        plots.ChildRemoved:Connect(function(p) lastAnimalData[p.Name]=nil; for i=#allAnimalsCache,1,-1 do if allAnimalsCache[i].plot==p.Name then table.remove(allAnimalsCache,i) end end; SharedState.ListNeedsRedraw=true end)
    end
    task.spawn(function() while true do SharedState.AllAnimalsCache=allAnimalsCache; task.wait(0.5) end end)
end)

-- Steal attribute listeners
player:GetAttributeChangedSignal("Stealing"):Connect(function()
    local isStealing=(player:GetAttribute("Stealing")==true)
    if FloatState.active and not isStealing then setFloat(false) end
    if _G.AutoInvisDuringSteal then
        if isStealing and not _G.invisibleStealEnabled and _G._forceInvisToggle then task.defer(function() if player:GetAttribute("Stealing") and not _G.invisibleStealEnabled then pcall(_G._forceInvisToggle) end end)
        elseif not isStealing and _G.invisibleStealEnabled and _G._forceInvisToggle then task.wait(0.3); if not player:GetAttribute("Stealing") then pcall(_G._forceInvisToggle) end end
    end
    if isStealing and Config.AutoUnlockOnSteal then
        local hrp=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local floor = getCurrentUnlockFloor()
            task.spawn(function()
                task.wait(0.1)
                pcall(smartInteract, floor)
            end)
        end
    end
end)

player.CharacterAdded:Connect(function() task.wait(0.5); if FloatState.active then removeFloatPlatform(); createFloatPlatform() end end)

-- ============================================================
-- TP SYSTEM
-- ============================================================
function findAdorneeGlobal(animalData)
    if not animalData then return nil end
    local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild(animalData.plot)
    if plot then
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if podiums then
            local podium = podiums:FindFirstChild(animalData.slot)
            if podium then
                local base = podium:FindFirstChild("Base")
                if base then
                    local spawn = base:FindFirstChild("Spawn")
                    if spawn then return spawn end
                    return base:FindFirstChildWhichIsA("BasePart") or base
                end
            end
        end
    end
    return nil
end

function getClosestBaseSign(brainrotPart)
    if not brainrotPart or not brainrotPart:IsA("BasePart") then return nil end
    local closestPart = nil
    local closestDist = math.huge
    for _, label in ipairs(Workspace:GetDescendants()) do
        if label:IsA("TextLabel") then
            local txt = tostring(label.Text or "")
            if (txt ~= "") and txt:lower():find("base", 1, true) then
                local gui = label:FindFirstAncestorWhichIsA("SurfaceGui")
                if gui then
                    local part = gui.Adornee or gui.Parent
                    if part and part:IsA("BasePart") then
                        local dist = (part.Position - brainrotPart.Position).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestPart = part
                        end
                    end
                end
            end
        end
    end
    return closestPart
end

function riseToY(hrp, targetY)
    if not hrp then return end
    local MAX_TIME = 3
    local start = os.clock()
    while hrp.Parent and (hrp.Position.Y < targetY) do
        local dist = targetY - hrp.Position.Y
        local speed = math.clamp(dist * 20, 280, 310)
        hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, speed, hrp.AssemblyLinearVelocity.Z)
        if (os.clock() - start) > MAX_TIME then
            break
        end
        RunService.Heartbeat:Wait()
    end
    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
end

function equipTpToolAndWait(hum)
    if not hum then return nil end
    local char = hum.Parent
    local toolName = Config.TpSettings.Tool or "Flying Carpet"
    local tool = LocalPlayer.Backpack:FindFirstChild(toolName) or (char and char:FindFirstChild(toolName))
    if tool then
        hum:EquipTool(tool)
        task.wait(0.02)
    end
    return tool
end

function walkForward(seconds)
    local char = LocalPlayer.Character
    local hum = char:FindFirstChild("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local pm = LocalPlayer:WaitForChild("PlayerScripts")
    local Controls = require(pm:WaitForChild("PlayerModule")):GetControls()
    local lookVector = hrp.CFrame.LookVector
    Controls:Disable()
    local startTime = os.clock()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if (os.clock() - startTime) >= seconds then
            conn:Disconnect()
            hum:Move(Vector3.zero, false)
            Controls:Enable()
            return
        end
        hum:Move(lookVector, false)
    end)
end

function waitSecondsHeartbeat(sec)
    local t = 0
    while t < sec do
        t += RunService.Heartbeat:Wait()
    end
end

function waitUntilHeartbeat(predicate, timeoutSec)
    local t = 0
    while true do
        if predicate() then
            return true
        end
        local dt = RunService.Heartbeat:Wait()
        t += dt
        if timeoutSec and (t >= timeoutSec) then
            return false
        end
    end
end

-- ============================================================
-- TELEPORT SYSTEM STAGE 2
-- ============================================================
TP_V2_MED_POINTS = {
    { name = "MED1", pos = Vector3.new(-410.65, -5.68, -46.1) },
    { name = "MED2", pos = Vector3.new(-410.91, -5.68, 168.89) },
}

TP_V2_SECOND_FLOOR_POINTS = {
    { name = "TP1", pos = Vector3.new(-488.88, 15, 196.38), facing = "back" },
    { name = "TP2", pos = Vector3.new(-487.79, 15, 138.13), facing = "front" },
    { name = "TP3", pos = Vector3.new(-489.38, 15, 89.23), facing = "back" },
    { name = "TP4", pos = Vector3.new(-489.69, 15, 30.98), facing = "front" },
    { name = "TP5", pos = Vector3.new(-488.75, 15, -17.95), facing = "back" },
    { name = "TP6", pos = Vector3.new(-490, 15, -75.9), facing = "front" },
    { name = "TP7", pos = Vector3.new(-331.75, 15, -75.8), facing = "back" },
    { name = "TP8", pos = Vector3.new(-329.98, 15, -18.16), facing = "front" },
    { name = "TP9", pos = Vector3.new(-330.04, 15, 31.14), facing = "back" },
    { name = "TP10", pos = Vector3.new(-331.28, 15, 88.92), facing = "front" },
    { name = "TP11", pos = Vector3.new(-330.57, 15, 138.1), facing = "back" },
    { name = "TP12", pos = Vector3.new(-330.01, 15, 195.96), facing = "front" },
}

TP_V2_ALLOWED_BY_MED = {
    MED1 = { TP6 = true, TP7 = true, TP8 = true, TP10 = true, TP12 = true, TP5 = true, TP3 = true, TP1 = true },
    MED2 = { TP1 = true, TP2 = true, TP4 = true, TP6 = true, TP7 = true, TP9 = true, TP11 = true, TP12 = true },
}

function flatDistance(a, b)
    return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

_G._isTargetPlotUnlocked = function(plotName)
    local ok, res = pcall(function()
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then return false end
        local targetPlot = plots:FindFirstChild(plotName)
        if not targetPlot then return false end
        local unlockFolder = targetPlot:FindFirstChild("Unlock")
        if not unlockFolder then return true end
        local unlockItems = {}
        for _, item in pairs(unlockFolder:GetChildren()) do
            local pos = nil
            if item:IsA("Model") then
                pcall(function() pos = item:GetPivot().Position end)
            elseif item:IsA("BasePart") then
                pos = item.Position
            end
            if pos then
                table.insert(unlockItems, { Object = item, Height = pos.Y })
            end
        end
        table.sort(unlockItems, function(a, b) return a.Height < b.Height end)
        if #unlockItems == 0 then return true end
        local floor1Door = unlockItems[1].Object
        for _, desc in ipairs(floor1Door:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled then return false end
        end
        for _, child in ipairs(floor1Door:GetChildren()) do
            if child:IsA("ProximityPrompt") and child.Enabled then return false end
        end
        return true
    end)
    return (ok and res) or false
end

function getClosestBaseSignToPosition(worldPos)
    local closestPart = nil
    local closestDist = math.huge
    for _, label in ipairs(Workspace:GetDescendants()) do
        if label:IsA("TextLabel") then
            local txt = tostring(label.Text or "")
            if (txt ~= "") and txt:lower():find("base", 1, true) then
                local gui = label:FindFirstAncestorWhichIsA("SurfaceGui")
                if gui then
                    local part = gui.Adornee or gui.Parent
                    if part and part:IsA("BasePart") then
                        local dist = (part.Position - worldPos).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestPart = part
                        end
                    end
                end
            end
        end
    end
    return closestPart
end

function getNearestTeleportV2MedPoint(fromPos)
    local bestPoint = nil
    local bestDist = math.huge
    for _, entry in ipairs(TP_V2_MED_POINTS) do
        local dist = flatDistance(fromPos, entry.pos)
        if dist < bestDist then
            bestDist = dist
            bestPoint = entry
        end
    end
    return bestPoint, bestDist
end

function getBestTeleportV2SecondFloorPoint(medPoint, brainrotPos)
    local medPos = medPoint and medPoint.pos
    local medName = medPoint and medPoint.name
    if not medPos or not medName then return nil end
    local allowed = TP_V2_ALLOWED_BY_MED[medName]
    if not allowed then return nil end
    local bestPoint = nil
    local bestMedDist = math.huge
    local bestBrainrotDist = math.huge
    for _, entry in ipairs(TP_V2_SECOND_FLOOR_POINTS) do
        if allowed[entry.name] then
            local distToMed = flatDistance(medPos, entry.pos)
            local distToBrainrot = flatDistance(brainrotPos, entry.pos)
            if (distToBrainrot < bestBrainrotDist) or ((math.abs(distToBrainrot - bestBrainrotDist) <= 0.001) and (distToMed < bestMedDist)) then
                bestPoint = entry
                bestMedDist = distToMed
                bestBrainrotDist = distToBrainrot
            end
        end
    end
    return bestPoint, bestMedDist, bestBrainrotDist
end



local FLY_SPEED = 160
local FLY_RISE_SPEED = 200
local FLY_RAY_DIST = 20
local FLY_TIMEOUT = 15
local FLY_ARRIVE_DIST = 4
local flyRayParams = RaycastParams.new()
flyRayParams.FilterType = Enum.RaycastFilterType.Exclude

function flyForwardTo(hrp, tpPos, lookDir, targetY, customSpeed)
    if not hrp or not hrp.Parent then
        return false
    end
    local char = hrp.Parent
    local hum = char:FindFirstChildOfClass("Humanoid")
    local unwalkConn
    if hum then
        local animator = hum:FindFirstChildOfClass("Animator")
        if animator then
            unwalkConn = RunService.Heartbeat:Connect(function()
                pcall(function()
                    for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
                        tr:Stop()
                    end
                end)
            end)
        end
    end
    flyRayParams.FilterDescendantsInstances = { char }
    local startTime = os.clock()
    while hrp.Parent do
        if (os.clock() - startTime) > FLY_TIMEOUT then
            break
        end
        if LocalPlayer:GetAttribute("Stealing") then
            break
        end
        local myPos = hrp.Position
        local flatDiff = Vector3.new(tpPos.X - myPos.X, 0, tpPos.Z - myPos.Z)
        local flatDist = flatDiff.Magnitude
        if flatDist < FLY_ARRIVE_DIST then
            break
        end
        local moveDir = flatDiff.Unit
        local yVel = 0
        if tpPos.Y <= 10 then
            -- Glue the feet to the floor by offsetting the HumanoidRootPart by +3.5 studs to prevent clipping into the ground and dying
            local targetFloorY = tpPos.Y + 3.5
            if targetY then
                -- Diagonal smooth ascent starting from 60 studs away down to 20 studs away
                if flatDist <= 60 then
                    local t = math.clamp((60 - flatDist) / (60 - 20), 0, 1)
                    targetFloorY = (tpPos.Y + 3.5) + (targetY - tpPos.Y) * t
                end
            end
            -- Multi-Ray Collision Detection (Feet, Torso, and Head levels)
            local heightsToCheck = {-3, 0, 3}
            local isRealObstacle = false
            for _, heightOffset in ipairs(heightsToCheck) do
                local rayOrigin = myPos + Vector3.new(0, heightOffset, 0)
                local rayFwd = Workspace:Raycast(rayOrigin, moveDir * FLY_RAY_DIST, flyRayParams)
                if rayFwd then
                    local part = rayFwd.Instance
                    if part and part.CanCollide then
                        local topY = part.Position.Y + (part.Size.Y / 2)
                        -- Only fly over if the obstacle's top is significantly higher than flat ground (more than 5 studs)
                        if (topY - tpPos.Y) > 5 then
                            isRealObstacle = true
                            break -- Tall obstacle detected, stop checking other heights
                        end
                    end
                end
            end

            if isRealObstacle then
                -- If tall obstacle detected, rise up and fly over it
                yVel = FLY_RISE_SPEED
            else
                -- Check if there is a real tall obstacle underneath us
                local rayDown = Workspace:Raycast(myPos, Vector3.new(0, -15, 0), flyRayParams)
                local obstacleUnderneath = false
                if rayDown then
                    local hitY = rayDown.Position.Y
                    if hitY > (tpPos.Y + 4) then
                        obstacleUnderneath = true
                    end
                end

                if obstacleUnderneath then
                    -- Keep current altitude while flying over the obstacle
                    yVel = 0
                else
                    -- No real obstacle in front or underneath, instantly stick to the ground
                    hrp.CFrame = CFrame.new(hrp.Position.X, targetFloorY, hrp.Position.Z) * (hrp.CFrame - hrp.CFrame.Position)
                    yVel = 0
                end
            end
        else
            -- Normal rise/fall behavior for second floor
            local rayFwd = Workspace:Raycast(myPos, moveDir * FLY_RAY_DIST, flyRayParams)
            if rayFwd then
                yVel = FLY_RISE_SPEED
            end
            local rayDown = Workspace:Raycast(myPos, Vector3.new(0, -12, 0), flyRayParams)
            if rayDown and ((myPos.Y - rayDown.Position.Y) < 5) then
                yVel = math.max(yVel, 100)
            end
            if not rayFwd and (tpPos.Y < (myPos.Y - 3)) then
                yVel = math.clamp((tpPos.Y - myPos.Y) * 3, -120, 0)
            end
        end
        local speed = customSpeed or Config.TpSettings.FlyTPSpeed or FLY_SPEED
        hrp.AssemblyLinearVelocity = (moveDir * speed) + Vector3.new(0, yVel, 0)
        hrp.AssemblyAngularVelocity = Vector3.zero
        RunService.Heartbeat:Wait()
    end
    if unwalkConn then
        unwalkConn:Disconnect()
        unwalkConn = nil
    end
    if not hrp.Parent then
        return false
    end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    local finalY = targetY or tpPos.Y
    local finalPos = Vector3.new(tpPos.X, finalY, tpPos.Z)
    hrp.CFrame = CFrame.lookAt(finalPos, finalPos + (lookDir or hrp.CFrame.LookVector))
    hrp.AssemblyLinearVelocity = Vector3.zero
    return true
end

function prepMiniTpTool(hum, hrp)
    if not hum or not hrp then return end
end

local function getTargetPetData()
    local cache = SharedState.AllAnimalsCache
    if not cache or #cache == 0 then
        return nil
    end
    
    local pets = get_all_pets()
    
    -- 1) Manual Override First
    if manuallySelectedUID then
        for _, a in ipairs(cache) do
            if a.uid == manuallySelectedUID and a.owner ~= LocalPlayer.Name then
                return a
            end
        end
    end
    
    -- 1.5) Priority List FIRST (Always target priority pets before anything else)
    for _, pName in ipairs(priorityList) do
        local searchName = pName:lower()
        local bestPet = nil
        local bestDist = math.huge
        for _, a in ipairs(cache) do
            if a and a.name and ((a.name:lower() == searchName) or (a.index and a.index:lower() == searchName)) and (a.owner ~= LocalPlayer.Name) then
                local dist = math.huge
                local char = LocalPlayer.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local plots = Workspace:FindFirstChild("Plots")
                    local plotInst = plots and plots:FindFirstChild(a.plot)
                    if plotInst then
                        local pos = nil
                        pcall(function() pos = plotInst:GetPivot().Position end)
                        if pos then
                            dist = (hrp.Position - pos).Magnitude
                        end
                    end
                end
                
                if not bestPet then
                    bestPet = a
                    bestDist = dist
                else
                    local currentGen = a.genValue or 0
                    local bestGen = bestPet.genValue or 0
                    if currentGen > bestGen then
                        bestPet = a
                        bestDist = dist
                    elseif currentGen == bestGen then
                        if dist < bestDist then
                            bestPet = a
                            bestDist = dist
                        end
                    end
                end
            end
        end
        if bestPet then
            return bestPet
        end
    end

    -- 2) Brainrots Second (target brainrots after priority)
    -- Respect Min-Gen-for-TP here too. Without this, brainrots BELOW the configured
    -- min gen (but still over the 10M "is-a-brainrot" baseline) got teleported to
    -- even though the list/scan correctly excluded them. Priority pets above are
    -- intentionally exempt from min gen; this non-priority section is not.
    local _mgStr = (Config.StealNearest and Config.TpSettings.MinGenForGrab) or Config.TpSettings.MinGenForTp
    local _brainrotFloor = math.max(10000000, parseMinGen(_mgStr) or 0)
    local bestBrainrot = nil
    local bestBrainrotDist = math.huge
    for _, a in ipairs(cache) do
        if a and a.owner ~= LocalPlayer.Name and a.genValue and a.genValue >= _brainrotFloor then
            local dist = math.huge
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local plots = Workspace:FindFirstChild("Plots")
                local plotInst = plots and plots:FindFirstChild(a.plot)
                if plotInst then
                    local pos = nil
                    pcall(function() pos = plotInst:GetPivot().Position end)
                    if pos then dist = (hrp.Position - pos).Magnitude end
                end
            end
            if dist < bestBrainrotDist then
                bestBrainrotDist = dist
                bestBrainrot = a
            end
        end
    end
    if bestBrainrot then return bestBrainrot end

    -- 3) Auto TP Highest Gen
    if Config.AutoTPHighestGen then
        if pets and #pets > 0 then
            return pets[1].animalData
        end
    end
    
    -- 2b) Auto TP Highest Value (sorted by pet value, not gen)
    if Config.AutoTPHighestValue then
        local valuePets = get_all_pets_by_value()
        if valuePets and #valuePets > 0 then
            return valuePets[1].animalData
        end
    end
    
    -- 3b) Auto TP Priority mode fallback (only reached if no priority pet was found)
    -- If they specifically selected priority mode but no priority pet is on the server, we return the highest gen fallback
    if Config.AutoTPPriority then
        if pets and #pets > 0 then
            return pets[1].animalData
        end
        return nil
    end
    
    -- 4) General Selected Pet
    if SharedState.SelectedPetData then
        return SharedState.SelectedPetData.animalData
    end
    
    return nil
end

local doGrabbleVelocityTP
do
local UPPER = {
    B = {{coord=Vector3.new(-487.921448,16.850713,-75.768013),facing="NORTH"},{coord=Vector3.new(-332.379730,16.850722,-75.762100),facing="NORTH"},{coord=Vector3.new(-487.134918,16.850713,-18.094154),facing="SOUTH"},{coord=Vector3.new(-316.300171,16.850713,-17.845898),facing="SOUTH"}},
    C = {{coord=Vector3.new(-330.765381,16.850713,31.424425),facing="NORTH"},{coord=Vector3.new(-502.989349,16.850713,31.172430),facing="NORTH"},{coord=Vector3.new(-489.077087,16.850713,89.010147),facing="SOUTH"},{coord=Vector3.new(-330.908936,16.850713,88.930145),facing="SOUTH"}},
    D = {{coord=Vector3.new(-331.264893,16.850713,138.209167),facing="NORTH"},{coord=Vector3.new(-487.935181,16.850713,138.026321),facing="NORTH"},{coord=Vector3.new(-487.774933,16.850713,195.882538),facing="SOUTH"},{coord=Vector3.new(-330.799133,16.850575,196.022354),facing="SOUTH"}},
}
local LOWER = {
    B = {{coord=Vector3.new(-335.725586,-3.048217,-74.984589),facing="NORTH"},{coord=Vector3.new(-503.214233,-3.048217,-75.043137),facing="NORTH"},{coord=Vector3.new(-483.619385,-3.718430,-18.844337),facing="SOUTH"},{coord=Vector3.new(-316.147095,-3.048218,-18.818844),facing="SOUTH"}},
    C = {{coord=Vector3.new(-335.985413,-3.048218,32.051426),facing="NORTH"},{coord=Vector3.new(-503.277008,-3.048217,31.956175),facing="NORTH"},{coord=Vector3.new(-483.749390,-3.048218,88.147003),facing="SOUTH"},{coord=Vector3.new(-315.793823,-3.048217,88.163979),facing="SOUTH"}},
    D = {{coord=Vector3.new(-335.476654,-3.048218,139.001083),facing="NORTH"},{coord=Vector3.new(-503.710083,-3.048218,138.989883),facing="NORTH"},{coord=Vector3.new(-315.654938,-3.048218,195.302444),facing="SOUTH"},{coord=Vector3.new(-483.859253,-3.048218,195.269043),facing="SOUTH"}},
}
local UPPER_Y_THRESHOLD = 7
local TALL_PETS = { ["La Secret Combinasion"]=true, ["La Jolly Grande"]=true }
local TALL_OFFSET = 3

local CARPET_SPEED = 230
local INBASE_SPEED = 230
local function getCarpetSpeed()
    return Config.TpSettings.FlyTPSpeed or 230
end
local function getInBaseSpeed()
    return Config.TpSettings.FlyTPCloseSpeed or 230
end
local SKY_CLONE_WAIT = 0.2
local CARPET_NAMES = { "Flying Carpet", "Carpet", "Cloud", "Witch's Broom", "Cupid's Wings", "Santa's Sleigh", "Magic Carpet", "Waverider" }
local GRAPPLE_NAMES = { "Grapple Hook", "Grappling Hook", "Grapple", "Hook", "Web Slinger", "Grapple Gun", "GrappleHook" }

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local RS         = game:GetService("ReplicatedStorage")
local LP         = Players.LocalPlayer

_G.AntiDieDisabled = false
do
    local _conn, _diedConn, _hbConn
    local _harden = function(hum)
        pcall(function() hum.BreakJointsOnDeath = false end)
        pcall(function() hum.RequiresNeck = false end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false) end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false) end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false) end)
    end
    local function _revive(hum)
        pcall(function() hum.Health = hum.MaxHealth end)
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
    end
    local function _bind()
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        _harden(hum)
        if _conn then pcall(function() _conn:Disconnect() end) end
        if _diedConn then pcall(function() _diedConn:Disconnect() end) end
        if _hbConn then pcall(function() _hbConn:Disconnect() end) end
        _conn = hum:GetPropertyChangedSignal("Health"):Connect(function()
            if _G.AntiDieDisabled then return end
            if hum.Health <= 0 then _revive(hum) end
        end)
        _diedConn = hum.Died:Connect(function()
            if _G.AntiDieDisabled then return end
            _revive(hum)
        end)
        local _lastHarden = 0
        _hbConn = RunService.Heartbeat:Connect(function()
            if _G.AntiDieDisabled or not hum or not hum.Parent then return end
            local now = os.clock()
            if now - _lastHarden >= 0.5 then _lastHarden = now; _harden(hum) end
            if hum.Health <= 0 then _revive(hum) end
            local state = hum:GetState()
            if state == Enum.HumanoidStateType.Dead or state == Enum.HumanoidStateType.Ragdoll
               or state == Enum.HumanoidStateType.FallingDown then
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Running) end)
            end
        end)
    end
    _bind()
    LP.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then _harden(hum) end
        task.wait(0.1)
        _bind()
    end)
end

-- =====================================================================
-- Synchronizer detection bypass
-- =====================================================================
do
    local okReq, syn = pcall(require, RS:FindFirstChild("Packages"):FindFirstChild("Synchronizer"))
    if okReq and typeof(syn) == "table" then
        local function HasBoolUpvalue(Fn)
            local OkU, Ups = xpcall(debug.getupvalues, function() end, Fn)
            if not OkU then return false end
            for _, V in pairs(Ups) do
                if typeof(V) == "boolean" then return true end
            end
            return false
        end
        for _, Fn in pairs(syn) do
            if typeof(Fn) == "function" and not isexecutorclosure(Fn) then
                local OkU, Ups = xpcall(debug.getupvalues, function() end, Fn)
                if OkU then
                    for Idx, V in pairs(Ups) do
                        if typeof(V) == "function" and not isexecutorclosure(V) and HasBoolUpvalue(V) then
                            pcall(debug.setupvalue, Fn, Idx, newcclosure(function() end))
                        end
                    end
                end
            end
        end
    end
end



-- =====================================================================
-- Module loaders
-- =====================================================================
local Synchronizer, AnimalsData, AnimalsShared, NumberUtils

local function loadModules()
    if Synchronizer then return true end
    local ok = pcall(function()
        local Packages = RS:WaitForChild("Packages", 5)
        local Datas = RS:WaitForChild("Datas", 5)
        local Shared = RS:WaitForChild("Shared", 5)
        local Utils = RS:WaitForChild("Utils", 5)
        Synchronizer = require(Packages:WaitForChild("Synchronizer"))
        AnimalsData = require(Datas:WaitForChild("Animals"))
        AnimalsShared = require(Shared:WaitForChild("Animals"))
        NumberUtils = require(Utils:WaitForChild("NumberUtils"))
    end)
    return ok and Synchronizer ~= nil
end

local NetModule
local function loadNet()
    if NetModule then return true end
    local ok, mod = pcall(function()
        return require(RS:WaitForChild("Packages", 5):WaitForChild("Net", 5):FindFirstChildWhichIsA("ModuleScript", true))
    end)
    if not ok or type(mod) ~= "table" then return false end
    NetModule = mod
    return true
end

local function findTool(name)
    local char = LP.Character
    local bp = LP:FindFirstChild("Backpack")
    return (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
end

local function findGrapple()
    for _, n in ipairs(GRAPPLE_NAMES) do
        local t = findTool(n)
        if t and t:IsA("Tool") then return t, n end
    end
    return nil
end

local function equipCarpet()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local preferred = Config and Config.TpSettings and Config.TpSettings.Tool
    if preferred then
        local pt = findTool(preferred)
        if pt and pt:IsA("Tool") then
            if pt.Parent ~= char then pcall(function() hum:EquipTool(pt) end) end
            return preferred
        end
    end
    for _, n in ipairs(CARPET_NAMES) do
        local t = findTool(n)
        if t and t:IsA("Tool") then
            if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
            return n
        end
    end
    return nil
end

local function fireGrapple()
    if not NetModule then loadNet() end
    if not NetModule then return end
    local char = LP.Character
    if not char then return end
    if not char:FindFirstChild("Grapple Hook") then
        local bp = LP:FindFirstChild("Backpack")
        local tool = bp and bp:FindFirstChild("Grapple Hook")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if tool and hum then pcall(function() hum:EquipTool(tool) end) end
    end
    if not char:FindFirstChild("Grapple Hook") then return end
    pcall(function() NetModule:RemoteEvent("UseItem"):FireServer(2) end)
end

local function carpetEngage()
    if not NetModule then pcall(loadNet) end
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return nil end
    local g = findTool("Grapple Hook")
    if g then
        if g.Parent ~= char then 
            pcall(function() hum:EquipTool(g) end)
            task.wait(0.05) -- Let tool equip register
        end
        if NetModule then pcall(function() NetModule:RemoteEvent("UseItem"):FireServer(2) end) end
        task.wait(0.22) -- Let grapple projectile register and pull
    end
    pcall(function() hum:UnequipTools() end)
    task.wait(0.10) -- Wait before putting carpet on
    local cn = equipCarpet()
    _G.TPEngage = "carpet=" .. tostring(cn)
    return cn
end

-- =====================================================================
-- Pet priority data tables
-- =====================================================================
local PET_PRIORITY_TIERS = {
    [1] = { pets = {"Headless Horseman"}, threshold = 0 },
    [2] = { pets = {"Signore Carapace"}, threshold = 0 },
    [3] = { pets = {"John Pork"}, threshold = 0 },
    [4] = { pets = {"Strawberry Elephant"}, threshold = 0 },
    [5] = { pets = {"Arcadragon"}, threshold = 5e9 },
    [6] = { pets = {"Elefanto Frigo"}, threshold = 10e9 },
    [7] = { pets = {"Meowl"}, threshold = 5e9 },
    [8] = { pets = {"Skibidi Toilet"}, threshold = 5e9 },
    [9] = { pets = {"Love Love Bear"}, threshold = 0 },
    [10] = { pets = {"Antonio"}, threshold = 0 },
    [11] = { pets = {"Pancake and Syrup"}, threshold = 0 },
    [12] = { pets = {"Griffin"}, threshold = 0 },
    [13] = { pets = {"Globa Steppa","La Supreme Combinasion","Fishino Clownino","Dragon Gingerini","Tirilikalika Tirilikalako"}, threshold = 5e9 },
    [14] = { pets = {"Ginger Gerat","Pet"}, threshold = 10e9 },
    [15] = { pets = {"Hydra Bunny","Digi Narwhal","Kalika Bros"}, threshold = 3e9 },
    [16] = { pets = {"Hydra Dragon Cannelloni","Dragon Cannelloni","Bunny and Eggy"}, threshold = 3e9 },
    [17] = { pets = {"Ketupat Bros","Rosey and Teddy","La Casa Boo","Fragola la la"}, threshold = 3e9 },
    [18] = { pets = {"Fragola La La La","Cerberus","Guest 666","Los Hackers"}, threshold = 1e9 },
    [19] = { pets = {"Garama and Madundung","Spooky and Pumpky","Reinito Sleighito","Burguro And Fryuro","Cooki and Milki","Fragrama and Chocrama","La Food Combinasion","Los Amigos","Foxini Lanternini","Capitano Moby","Fortunu and Cashuru","Los Sekolahs","Celestial Pegasus"}, threshold = 750e6 },
    [20] = { pets = {"La Secret Combinasion","Sammyni Fattini","Cloverat Clapat","Popcuru and Fizzuru"}, threshold = 1e9 },
}

local TIER_LOOKUP = {}
for tier, data in pairs(PET_PRIORITY_TIERS) do
    for _, name in ipairs(data.pets) do TIER_LOOKUP[name] = tier end
end

local LOCKED_TIERS = { [1]=true, [2]=true, [3]=true, [4]=true }

local DIRECT_THRESHOLDS = {
    [3] = { [4] = 10e9 },
    [4] = {},
    [5] = { [6] = math.huge },
    [6] = { [9] = math.huge, [10] = math.huge, [12] = 15e9 },
    [10] = { [12] = 20e9 },
    [11] = { [12] = 10e9 },
}

local MUTATION_PRIORITY = {
    ["Galaxy"]=1,["Candy"]=1,["Yin Yang"]=1,["YinYang"]=1,["Divine"]=1,
    ["Cursed"]=1,["Lava"]=1,["Radioactive"]=1,["Cyber"]=1,["Rainbow"]=1,["Bloodrot"]=2,
}

local MUTATED_BEATS_GRIFFIN = {
    ["Fishino Clownino"]=true,["Globa Steppa"]=true,
    ["La Supreme Combinasion"]=true,["Tirilikalika Tirilikalako"]=true,
}

local function getMutPrio(m)
    if not m or m == "" or m == "None" then return 0 end
    if MUTATION_PRIORITY[m] then return MUTATION_PRIORITY[m] end
    local n = tostring(m):lower():gsub("[%s%-_]","")
    if n == "bloodrot" then return 2 end
    if n == "yinyang" or n == "galaxy" or n == "candy" or n == "divine"
        or n == "cursed" or n == "lava" or n == "radioactive" or n == "cyber"
        or n == "rainbow" then return 1 end
    return 0
end

local function getCumThreshold(hi, lo)
    if DIRECT_THRESHOLDS[hi] and DIRECT_THRESHOLDS[hi][lo] then return DIRECT_THRESHOLDS[hi][lo] end
    if LOCKED_TIERS[hi] then return math.huge end
    local total = 0
    for t = hi + 1, lo do
        local td = PET_PRIORITY_TIERS[t]
        if td and td.threshold > 0 then total = total + td.threshold end
    end
    return total
end

local function petOutranks(aName, bName, aMut, bMut, aMPS, bMPS)
    if aName == "Strawberry Elephant" and bName == "John Pork" then return true end
    if aName == "John Pork" and bName == "Strawberry Elephant" then return false end

    if MUTATED_BEATS_GRIFFIN[aName] and bName == "Griffin" and getMutPrio(aMut) >= 1 then return true end
    if aName == "Griffin" and MUTATED_BEATS_GRIFFIN[bName] and getMutPrio(bMut) >= 1 then return false end

    if aName == "Antonio" and bName == "Elefanto Frigo" and getMutPrio(aMut) >= 1 then return true end
    if aName == "Elefanto Frigo" and bName == "Antonio" and getMutPrio(bMut) >= 1 then return false end

    local tA = TIER_LOOKUP[aName] or 99
    local tB = TIER_LOOKUP[bName] or 99

    if not (TIER_LOOKUP[aName] and TIER_LOOKUP[bName]) then
        if tA == tB then return (aMPS or 0) > (bMPS or 0) end
        return tA < tB
    end

    if tA == tB then
        local pA, pB = getMutPrio(aMut), getMutPrio(bMut)
        if pA ~= pB then return pA > pB end
        return (aMPS or 0) > (bMPS or 0)
    end

    if tA == 4 and tB == 3 then return true end
    if tA == 3 and tB == 4 then return false end

    local hi = math.min(tA, tB)
    local lo = math.max(tA, tB)
    local hiMPS = tA < tB and aMPS or bMPS
    local loMPS = tA < tB and bMPS or aMPS
    local cum = getCumThreshold(hi, lo)
    if cum > 0 and cum ~= math.huge then
        if (loMPS or 0) - (hiMPS or 0) > cum then return tA > tB end
    end
    return tA < tB
end

-- =====================================================================
-- Plot / channel helpers
-- =====================================================================
local function getPlotChannel(plotName)
    if not Synchronizer then return nil end
    local channel
    pcall(function() channel = Synchronizer:Get(plotName) end)
    if not channel then pcall(function() channel = Synchronizer:Wait(plotName) end) end
    return channel
end

local function channelGet(channel, key)
    return _G.sProp(channel, key)
end

local function isMyPlot(channel)
    if not channel then return false end
    local owner = channelGet(channel, "Owner")
    if not owner then return false end
    local result = false
    pcall(function()
        if typeof(owner) == "Instance" and owner:IsA("Player") then
            result = owner.UserId == LP.UserId
        elseif type(owner) == "table" and owner.UserId then
            result = owner.UserId == LP.UserId
        elseif typeof(owner) == "Instance" then
            result = owner == LP
        elseif type(owner) == "string" then
            result = (owner:lower() == LP.Name:lower() or owner:lower() == LP.DisplayName:lower())
        elseif type(owner) == "number" then
            result = owner == LP.UserId
        end
    end)
    return result
end

local function ownerInGame(channel)
    if not channel then return false end
    local owner = channelGet(channel, "Owner")
    if not owner then return false end
    local inGame = false
    pcall(function()
        if typeof(owner) == "Instance" and owner:IsA("Player") then
            inGame = Players:FindFirstChild(owner.Name) ~= nil
        elseif type(owner) == "number" then
            inGame = Players:GetPlayerByUserId(owner) ~= nil
        elseif type(owner) == "table" and owner.Name then
            inGame = Players:FindFirstChild(tostring(owner.Name)) ~= nil
        elseif type(owner) == "string" then
            inGame = Players:FindFirstChild(owner) ~= nil
        elseif typeof(owner) == "Instance" and owner.Name then
            inGame = Players:FindFirstChild(owner.Name) ~= nil
        end
    end)
    return inGame
end

local function getStealPromptForSlot(plot, slot)
    local podiums = plot and plot:FindFirstChild("AnimalPodiums")
    local podium = podiums and podiums:FindFirstChild(tostring(slot))
    local base = podium and podium:FindFirstChild("Base")
    local spawnp = base and base:FindFirstChild("Spawn")
    local att = spawnp and spawnp:FindFirstChild("PromptAttachment")
    local prompt = att and att:FindFirstChildWhichIsA("ProximityPrompt")
    if prompt and (prompt.ActionText:lower():find("steal") or prompt.ActionText == "") then return prompt end
    return nil
end

local _BLOCKING_MACHINE_TYPES = {
    Fuse     = true,
    Duel     = true,
    Trade    = true,
    Crafting = true,
}
local function _CartisIsFusing(animalData)
    if type(animalData) ~= "table" then return false end
    local m = animalData.Machine
    if type(m) ~= "table" then return false end
    return _BLOCKING_MACHINE_TYPES[m.Type] == true
end

local function scanAllPets()
    local pets = {}
    if not loadModules() then return pets end

    local Plots = Workspace:FindFirstChild("Plots")
    if not Plots then return pets end

    for _, plot in ipairs(Plots:GetChildren()) do
        local channel = getPlotChannel(plot.Name)
        if not channel then continue end
        if isMyPlot(channel) then continue end
        -- if not ownerInGame(channel) then continue end

        local animalList = channelGet(channel, "AnimalList")
        if not animalList then continue end

        for slot, animalData in pairs(animalList) do
            if type(animalData) ~= "table" then continue end
            local animalName = animalData.Index
            if not animalName then continue end
            local animalInfo = AnimalsData and AnimalsData[animalName]
            if not animalInfo then continue end
            if _CartisIsFusing(animalData) then continue end

            local mutation = animalData.Mutation or "None"
            local genValue = 0
            pcall(function()
                genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil)
            end)

            local displayName = (animalInfo and animalInfo.DisplayName) or animalName
            local pos = getPetPosition(plot, slot)

            if pos then
                table.insert(pets, {
                    name = displayName,
                    mps = genValue,
                    mutation = mutation,
                    position = pos,
                    plot = plot.Name,
                    slot = tostring(slot),
                    prompt = getStealPromptForSlot(plot, slot),
                })
            end
        end
    end

    table.sort(pets, function(a, b)
        return petOutranks(a.name, b.name, a.mutation, b.mutation, a.mps, b.mps)
    end)

    return pets
end

local function findClosest(petPos, coordTable, fromPos)
    local all = {}
    for skyKey, coords in pairs(coordTable) do
        for _, data in ipairs(coords) do
            local c = data.coord
            local d = (petPos.X - c.X)^2 + (petPos.Z - c.Z)^2
            all[#all + 1] = { data = data, key = skyKey, petD = d }
        end
    end
    table.sort(all, function(a, b) return a.petD < b.petD end)
    if #all == 0 then return nil, nil end
    if not fromPos then return all[1].data, all[1].key end

    local cands = { all[1] }
    if all[2] and math.abs(all[2].data.coord.X - all[1].data.coord.X) < 40 then
        cands[#cands + 1] = all[2]
    end
    local best, bestKey, bestDist = all[1].data, all[1].key, math.huge
    for _, e in ipairs(cands) do
        local c = e.data.coord
        local d = (fromPos.X - c.X)^2 + (fromPos.Z - c.Z)^2
        if d < bestDist then bestDist = d; best = e.data; bestKey = e.key end
    end
    return best, bestKey
end

-- =====================================================================
-- Path visualization helpers
-- =====================================================================
local _vizParts = {}
local function clearViz()
    for _, p in ipairs(_vizParts) do if p and p.Parent then p:Destroy() end end
    table.clear(_vizParts)
end
local function vizLine(a, b, color)
    local d = b - a
    if d.Magnitude < 0.05 then return end
    local p = Instance.new("Part")
    p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
    p.Material = Enum.Material.Neon; p.Color = color
    p.Size = Vector3.new(0.4, 0.4, d.Magnitude)
    p.CFrame = CFrame.new((a + b) / 2, b)
    p.Parent = Workspace
    _vizParts[#_vizParts + 1] = p
end
local function vizDot(pos, color, sz)
    local p = Instance.new("Part")
    p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
    p.Shape = Enum.PartType.Ball; p.Material = Enum.Material.Neon; p.Color = color
    p.Size = Vector3.new(sz, sz, sz)
    p.Position = pos
    p.Parent = Workspace
    _vizParts[#_vizParts + 1] = p
end
local function vizPath(fromPos, waypoints)
    -- Pathfinder lines/dots disabled (user request: no lines).
    return
end

local isGrabbleTeleporting = false
local isTeleporting = false

local function getPlotKey(plotName)
    if not plotName then return nil end
    local first, second = plotName:match("^Plot_([B-D])([1-4])$")
    if first and second then return first end
    local first2, second2 = plotName:match("^Plot([B-D])([1-4])$")
    if first2 and second2 then return first2 end
    local first3 = plotName:match("^([B-D])[1-4]$")
    if first3 then return first3 end
    return nil
end

local SPEED = 200
local ARRIVE = 3

local function vZero(hrp)
    if hrp then hrp.AssemblyLinearVelocity = Vector3.zero; hrp.AssemblyAngularVelocity = Vector3.zero end
end

local MAX_CLIMB = 60

local function velMoveThrough(hrp, waypoints, speedOverride, allowJump, quickStart)
    if not hrp or not hrp.Parent or #waypoints == 0 then return end
    local _runSpeed = speedOverride or Config.TpSettings.GrabbleTPSpeed or (_G.SXECarpetSpeed or CARPET_SPEED or 230)
    vizPath(hrp.Position, waypoints)
    local wpIdx = 1
    local done = false
    local conn
    local function finish()
        if done then return end
        done = true
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            local _, y = hrp.CFrame:ToEulerAnglesYXZ()
            hrp.CFrame = CFrame.new(waypoints[#waypoints]) * CFrame.Angles(0, y, 0)
        end
        if conn then conn:Disconnect() end
        clearViz()
    end
    local lastDist, stall = math.huge, 0

    if quickStart then
        local _hp = RaycastParams.new()
        _hp.FilterType = Enum.RaycastFilterType.Exclude
        _hp.IgnoreWater = true
        local _skip = {}
        for _, pl in ipairs(Players:GetPlayers()) do
            if pl.Character then _skip[#_skip + 1] = pl.Character end
        end
        _hp.FilterDescendantsInstances = _skip
        for _ = 1, 3 do
            local target = waypoints[wpIdx]
            if not target then break end
            local flat = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
            local mag = flat.Magnitude
            if mag < 1 then break end
            local nextPos = hrp.Position + flat.Unit * math.min(20, mag)
            local _hit = Workspace:Raycast(hrp.Position, nextPos - hrp.Position, _hp)
            if _hit and _hit.Instance and _hit.Instance.CanCollide then break end
            hrp.CFrame = (hrp.CFrame - hrp.CFrame.Position) + nextPos
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            RunService.Heartbeat:Wait()
            if not hrp or not hrp.Parent then return end
        end
    end

    conn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent or done then
            if conn then conn:Disconnect() end
            return
        end
        equipCarpet()
        local target = waypoints[wpIdx]
        local diff = target - hrp.Position
        local mag = diff.Magnitude
        if mag < ARRIVE then
            wpIdx = wpIdx + 1
            if wpIdx > #waypoints then finish() return end
            lastDist, stall = math.huge, 0
            target = waypoints[wpIdx]
            diff = target - hrp.Position
            mag = diff.Magnitude
        end
        if mag > lastDist - 0.05 then stall = stall + 1 else stall = 0 end
        lastDist = mag
        if stall >= 18 then finish() return end
        if mag >= 0.1 then
            local dir = diff.Unit
            if allowJump and diff.Y > 5 and wpIdx < #waypoints then
                local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
                if hum then
                    local st = hum:GetState()
                    if st ~= Enum.HumanoidStateType.Jumping and st ~= Enum.HumanoidStateType.Freefall then
                        pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
                        pcall(function() hum.Jump = true end)
                    end
                end
            end
            local _sp = _runSpeed
            local _vy = dir.Y * _sp
            if _vy > MAX_CLIMB then _vy = MAX_CLIMB end
            hrp.Velocity = Vector3.new(dir.X * _sp, _vy, dir.Z * _sp)
        end
    end)
    local totalDist = 0
    local prev = hrp.Position
    for _, wp in ipairs(waypoints) do
        totalDist = totalDist + (prev - wp).Magnitude
        prev = wp
    end
    local timeout = totalDist / math.min(SPEED, _runSpeed) + 2
    local elapsed = 0
    while not done and elapsed < timeout do
        task.wait(0.05)
        elapsed = elapsed + 0.05
    end
    finish()
    vZero(hrp)
end

-- =====================================================================
-- Raycast / route-pulling helpers
-- =====================================================================
local _DIRS = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
local _STRUCT = { ["structure base home"] = true, ["Wall"] = true, ["Floor"] = true, ["Roof"] = true }
local _SKIP_NAME = { ["DeliveryHitbox"]=true, ["StealHitbox"]=true, ["LaserHitbox"]=true,
    ["AnimalTarget"]=true, ["Multiplier"]=true, ["Laser"]=true, ["Hitbox"]=true,
    ["Spawn"]=true, ["MainRoot"]=true, ["SecondFloor"]=true, ["ThirdFloor"]=true, ["Slope"]=true }

function _blocks(inst)
    if not inst then return false end
    if _SKIP_NAME[inst.Name] then return false end
    if inst.CanCollide then return true end
    if _STRUCT[inst.Name] then return true end
    local s = inst.Size
    if s and math.max(s.X * s.Y, s.X * s.Z, s.Y * s.Z) > 150 then return true end
    return false
end

function _block(origin, target)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    local skip = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then skip[#skip + 1] = pl.Character end
    end
    local o = origin
    for _ = 1, 16 do
        rp.FilterDescendantsInstances = skip
        local d = target - o
        if d.Magnitude < 0.05 then return nil end
        local res = Workspace:Raycast(o, d, rp)
        if not res then return nil end
        if _blocks(res.Instance) then return res end
        skip[#skip + 1] = res.Instance
        o = res.Position + d.Unit * 0.3
    end
    return nil
end

function _clear(a, b) return _block(a, b) == nil end

function _clearDist(origin, dir, maxD)
    local res = _block(origin, origin + dir.Unit * maxD)
    if not res then return maxD end
    return (res.Position - origin).Magnitude
end

local function _len(pts)
    local s, prev = 0, pts[1]
    for k = 2, #pts do s = s + (pts[k] - prev).Magnitude; prev = pts[k] end
    return s
end

function _pull(pts)
    if #pts <= 2 then return pts end
    local out = { pts[1] }
    local i = 1
    while i < #pts do
        local j = #pts
        while j > i + 1 and not _clear(out[#out], pts[j]) do j = j - 1 end
        out[#out + 1] = pts[j]
        i = j
    end
    return out
end

local function _stages(toPos)
    local st = {}
    for _, dr in ipairs(_DIRS) do
        local cd = _clearDist(toPos, dr, 46)
        if cd >= 12 then st[#st + 1] = toPos + dr * math.min(cd - 5, 38) end
    end
    return st
end

local function _routeClear(pts)
    for i = 1, #pts - 1 do
        if not _clear(pts[i], pts[i + 1]) then return false end
    end
    return true
end

local function _peakY(pts)
    local m = -math.huge
    for _, p in ipairs(pts) do if p.Y > m then m = p.Y end end
    return m
end

local function _starts(fromPos)
    local pts = { fromPos }
    if _block(fromPos, fromPos + Vector3.new(0, 40, 0)) then
        for _, dr in ipairs(_DIRS) do
            local cd = _clearDist(fromPos, dr, 40)
            if cd >= 12 then pts[#pts + 1] = fromPos + dr * math.min(cd - 5, 34) end
        end
    end
    return pts
end

local function _candidates(sp, stage, toPos)
    local list = {}
    local function add(mid)
        if mid then list[#list + 1] = { sp, mid, stage, toPos }
        else list[#list + 1] = { sp, stage, toPos } end
    end
    add(nil)
    add(Vector3.new(stage.X, sp.Y, stage.Z))
    add(Vector3.new(sp.X, stage.Y, sp.Z))
    local dir = Vector3.new(stage.X - sp.X, 0, stage.Z - sp.Z)
    if dir.Magnitude > 0.1 then
        dir = dir.Unit
        local perp = Vector3.new(-dir.Z, 0, dir.X)
        for _, off in ipairs({ 20, -20, 40, -40 }) do
            add(sp + perp * off)
        end
    end
    return list
end

local PathfindingService = game:GetService("PathfindingService")
local _CLEARANCE = 6

local function _clearWide(a, b)
    if not _clear(a, b) then return false end
    local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
    if d.Magnitude < 0.1 then return true end
    local p = Vector3.new(-d.Z, 0, d.X).Unit * _CLEARANCE
    return _clear(a + p, b + p) and _clear(a - p, b - p)
end

local function _pullWide(pts)
    if #pts <= 2 then return pts end
    local out = { pts[1] }
    local i = 1
    while i < #pts do
        local j = #pts
        while j > i + 1 and not _clearWide(out[#out], pts[j]) do j = j - 1 end
        out[#out + 1] = pts[j]
        i = j
    end
    return out
end

function computeRoute(fromPos, toPos, facingDir)
    if _clear(fromPos, toPos) then return { toPos } end
    local entry = facingDir and (toPos - facingDir * 14) or toPos
    local groundTo = Vector3.new(entry.X, fromPos.Y, entry.Z)
    local path = PathfindingService:CreatePath({
        AgentRadius = 8, AgentHeight = 5, AgentCanJump = true, AgentJumpHeight = 10, AgentMaxSlope = 89,
    })
    local FLOAT = 3
    local nav = { fromPos }
    local ok = pcall(function()
        path:ComputeAsync(Vector3.new(fromPos.X, fromPos.Y, fromPos.Z), groundTo)
    end)
    if ok and path.Status == Enum.PathStatus.Success then
        local last = fromPos
        for _, wp in ipairs(path:GetWaypoints()) do
            if (wp.Position - last).Magnitude >= 8 then
                nav[#nav + 1] = wp.Position + Vector3.new(0, FLOAT, 0)
                last = wp.Position
            end
        end
    end
    nav[#nav + 1] = entry + Vector3.new(0, FLOAT, 0)
    local route = _pullWide(nav)
    route[#route + 1] = toPos
    return route
end

-- =====================================================================
-- Tool & Clone Helpers
-- =====================================================================

function getPetPosition(plot, slot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(tostring(slot))
    if not podium then return nil end

    for _, desc in ipairs(podium:GetDescendants()) do
        if desc:IsA("Model") and desc.Name ~= "Claim" and desc.Name ~= "Base" and desc.Name ~= "Decorations" then
            local hasMesh = false
            for _, c in ipairs(desc:GetDescendants()) do
                if c:IsA("MeshPart") then hasMesh = true; break end
            end
            if hasMesh then
                local ok, cf = pcall(function() return desc:GetBoundingBox() end)
                if ok then return cf.Position end
            end
        end
    end

    local ok, cf = pcall(function() return podium:GetPivot() end)
    if ok then return cf.Position end
    return podium.Position
end

end

local cloneref = cloneref or function(o) return o end
local getinfo = debug.getinfo or getinfo
local lp = cloneref(game:GetService("Players")).LocalPlayer

local function Strip()
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if not getconnections or not getinfo then return end
    for _, sig in ipairs({"CFrame", "Position"}) do
        local signal = hrp:GetPropertyChangedSignal(sig)
        if signal then
            for _, c in ipairs(getconnections(signal)) do
                local f = c.Function
                if f and c.Enabled and getinfo(f) and getinfo(f).source == "=ReplicatedFirst.test" then
                    pcall(function() c:Disable() end)
                end
            end
        end
    end
end

task.spawn(function()
    while true do
        pcall(Strip)
        task.wait(0.5)
    end
end)

function runAutoSnipe()
    pcall(Strip)
    if _G._isTpMoving then
        return
    end
    if Config.TpSettings and Config.TpSettings.GrabbleTP then
        _G._isTpMoving = true
        local fn = _G.SXEStartSideTP or doGrabbleVelocityTP
        local okGrab, errGrab = pcall(fn)
        _G._isTpMoving = false
        if not okGrab then
            warn("Grabble TP error:", errGrab)
        end
        return
    end
    if CarpetState and CarpetState.enabled then
        setCarpetSpeed(false)
    end
    local targetPetData = getTargetPetData()
    if not targetPetData then
        return
    end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    if not hrp or not hum or (hum.Health <= 0) then
        return
    end
    local lastFpsCap = pcall(getfpscap) and getfpscap() or 9999
    pcall(setfpscap, 200)
    -- (Old Grabble TP branch removed - now handled by SXE Clone-TP router above.)
    _G._isTpMoving = true
    local ok, err = pcall(function()
        local targetPart = findAdorneeGlobal(targetPetData)
        if not targetPart then
            error("targetPart nil")
        end
        local targetCF
        if targetPart:IsA("Attachment") then
            targetCF = targetPart.WorldCFrame
        elseif targetPart:IsA("BasePart") then
            targetCF = targetPart.CFrame
        else
            local okPivot, pivot = pcall(function()
                return targetPart:GetPivot()
            end)
            if okPivot then
                targetCF = pivot
            end
        end
        if not targetCF then
            error("targetCF nil")
        end
        local exactPos = targetPart.Position
        local carpetName = Config.TpSettings.Tool
        local carpet = LocalPlayer.Backpack:FindFirstChild(carpetName) or char:FindFirstChild(carpetName)
        local cloner = LocalPlayer.Backpack:FindFirstChild("Quantum Cloner") or char:FindFirstChild("Quantum Cloner")
        equipTpToolAndWait(hum)
        local isSecondFloor = exactPos.Y > 10
        local isCloseBase = false
        
        local signPart = getClosestBaseSign(targetPart)
            if not signPart then
                error("signPart nil")
            end
            local signCF = signPart.CFrame
            local RIGHT = signCF.RightVector
            local LEFT = -RIGHT
            local FORWARD = signCF.LookVector
            local BACK = -signCF.LookVector
            local medPoint = getNearestTeleportV2MedPoint(hrp.Position)
            if not medPoint then
                error("normal tp MED point nil")
            end
            hrp.AssemblyLinearVelocity = Vector3.zero
            local tpPos
            if exactPos.Y <= 6.313370704650879 then
                local frontPoint = signPart.Position + (FORWARD * 20)
                local backPoint = signPart.Position + (BACK * 20)
                local myPos = hrp.Position
                local distFront = (Vector3.new(frontPoint.X, 0, frontPoint.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
                local distBack = (Vector3.new(backPoint.X, 0, backPoint.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
                local chosen = ((distFront < distBack) and frontPoint) or backPoint
                tpPos = Vector3.new(chosen.X, -4.8, chosen.Z)
            else
                local backPoint = signPart.Position + (BACK * 20)
                local frontPoint = signPart.Position + (FORWARD * 20)
                local myPos = hrp.Position
                local myFlat = Vector3.new(myPos.X, 0, myPos.Z)
                local distBack = (Vector3.new(backPoint.X, 0, backPoint.Z) - myFlat).Magnitude
                local distFront = (Vector3.new(frontPoint.X, 0, frontPoint.Z) - myFlat).Magnitude
                local chosen = ((distBack < distFront) and backPoint) or frontPoint
                -- Always ground level Y
                tpPos = Vector3.new(chosen.X, -4.8, chosen.Z)
            end
            local initialDist = (hrp.Position - tpPos).Magnitude
            isCloseBase = (initialDist <= 100) and isSecondFloor
            if Config.TpSettings.FlyTP then
                -- Fly directly to the target base position (tpPos) facing LEFT, with obstacle avoidance
                flyForwardTo(hrp, tpPos, LEFT, isSecondFloor and (signPart.Position.Y + 4) or nil, isCloseBase and (Config.TpSettings.FlyTPCloseSpeed or 75) or nil)
            else
                -- Teleport directly to the target base position (tpPos) facing LEFT
                if hum and hum.Parent then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
                task.wait(0.01)
                hrp.AssemblyLinearVelocity = Vector3.zero
                local targetCF = CFrame.lookAt(tpPos, tpPos + LEFT)
                if isCloseBase then
                    -- Smooth CFrame glide to close bases to bypass anti-cheat flags
                    local startCF = hrp.CFrame
                    local duration = 2.5
                    local start = tick()
                    while tick() - start < duration and hrp.Parent do
                        local t = (tick() - start) / duration
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        hrp.AssemblyAngularVelocity = Vector3.zero
                        hrp.CFrame = startCF:Lerp(targetCF, t)
                        RunService.Heartbeat:Wait()
                    end
                end
                hrp.CFrame = targetCF
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            waitUntilHeartbeat(function()
                return hrp and hrp.Parent and (flatDistance(hrp.Position, tpPos) <= 5)
            end, 0.5)
            task.wait(0.05)

            if isSecondFloor and hrp.Position.Y < (signPart.Position.Y + 2) then
                -- Smooth and slow fly up at a safe distance (tpPos is 15-20 studs away)
                local startY = hrp.Position.Y
                local targetY = signPart.Position.Y + 4
                local riseTime = isCloseBase and 5.0 or 1.2
                local elapsed = 0
                while elapsed < riseTime and hrp.Parent do
                    elapsed = elapsed + RunService.Heartbeat:Wait()
                    local t = math.min(elapsed / riseTime, 1)
                    local currentY = startY + (targetY - startY) * t
                    hrp.CFrame = CFrame.lookAt(Vector3.new(tpPos.X, currentY, tpPos.Z), Vector3.new(tpPos.X, currentY, tpPos.Z) + LEFT)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                end
                hrp.CFrame = CFrame.lookAt(Vector3.new(tpPos.X, targetY, tpPos.Z), Vector3.new(tpPos.X, targetY, tpPos.Z) + LEFT)
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            if isSecondFloor or not _G._isTargetPlotUnlocked(targetPetData.plot) then
                prepMiniTpTool(hum, hrp)
                waitSecondsHeartbeat(0.05)
                if isSecondFloor then
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    waitSecondsHeartbeat(0.01)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.CFrame = hrp.CFrame * CFrame.new(0, 0, -2.5)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                else
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    waitSecondsHeartbeat(0.03)
                    walkForward(0.1)
                end
                waitSecondsHeartbeat(Config.TpSettings.CloneDelayVal or 0.1)
                local miniPos = hrp.Position
                waitSecondsHeartbeat(0.01)
                local stillAtMiniPos = waitUntilHeartbeat(function()
                    return hrp and hrp.Parent and ((hrp.Position - miniPos).Magnitude <= 2)
                end, 0.75)
                if not stillAtMiniPos then
                    error("moved away from mini TP position before clone")
                end
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                local cloneSuccess = false
                for attempt = 1, 3 do
                    instantClone()
                    local moved = waitUntilHeartbeat(function()
                        return hrp and hrp.Parent and ((hrp.Position - miniPos).Magnitude >= 0.35)
                    end, 3)
                    if moved then
                        cloneSuccess = true
                        break
                    end
                    while _G.isCloning do
                        task.wait()
                    end
                    task.wait(0.1)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.CFrame = CFrame.new(miniPos)
                end
                if not cloneSuccess then
                    error("clone failed/no push")
                end
                if cloner then
                    hum:EquipTool(cloner)
                    task.wait(0.02)
                    pcall(function()
                        cloner:Activate()
                    end)
                    task.wait(0.05)
                    equipTpToolAndWait(hum)
                end
            end
            
            if _G.SXEGoToBrainrot then
                -- Merko TP got us into the base (and cloned if needed); hand off to
                -- the SXE Clone-TP engine for the final approach + steal execution.
                pcall(_G.SXEArmSteal, {plot = targetPetData.plot, slot = targetPetData.slot, name = targetPetData.name, position = targetPart.Position})
                pcall(_G.SXEGoToBrainrot, targetPart.Position)
                return
            end

            -- Keep velocity zero and CFrame glued to target animal for steal duration
            local holdEnd = tick() + math.max(0.18, Config.TpSettings.DelayVal or 0.4)
            while tick() < holdEnd do
                if not hrp.Parent then
                    break
                end
                if LocalPlayer:GetAttribute("Stealing") then
                    break
                end
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                pcall(function()
                    hrp.CFrame = CFrame.new(targetPart.Position)
                end)
                RunService.Heartbeat:Wait()
            end
            
            -- Post-steal stabilization / platform fallback
            if isSecondFloor then
                local plat = Instance.new("Part")
                plat.Name = "XiTempPlatform"
                plat.Size = Vector3.new(6, 1.5, 6)
                plat.Position = Vector3.new(hrp.Position.X, hrp.Position.Y - 5.5, hrp.Position.Z)
                plat.Color = Color3.fromRGB(232, 111, 177)
                plat.Material = Enum.Material.Neon
                plat.Anchored = true
                plat.CanCollide = false; pcall(makeOneWay, plat)
                plat.Transparency = 0.3
                plat.Parent = Workspace
                task.spawn(function()
                    local start = tick()
                    while (tick() - start) < 20 do
                        if LocalPlayer:GetAttribute("Stealing") then break end
                        task.wait(0.1)
                    end
                    plat:Destroy()
                end)
            else
                for i = 1, 5 do
                    if LocalPlayer:GetAttribute("Stealing") then break end
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    if (hrp.Position - targetPart.Position).Magnitude > 3 then
                        hrp.CFrame = CFrame.new(targetPart.Position)
                    end
                    task.wait(0.05)
                end
            end
        -- Force equip the configured TP tool (not the cloner)
        pcall(function() hum:UnequipTools() end)
        task.wait(0.05)
        equipTpToolAndWait(hum)
        -- Verify tool is equipped, retry if game re-equipped cloner
        task.defer(function()
            task.wait(0.1)
            local char2 = LocalPlayer.Character
            local hum2 = char2 and char2:FindFirstChildOfClass("Humanoid")
            if not hum2 then return end
            local toolName2 = Config.TpSettings.Tool or "Flying Carpet"
            local equipped = char2:FindFirstChild(toolName2)
            if not equipped then
                pcall(function() hum2:UnequipTools() end)
                task.wait(0.05)
                local t2 = LocalPlayer.Backpack:FindFirstChild(toolName2)
                if t2 then pcall(function() hum2:EquipTool(t2) end) end
            end
        end)
        if isCloseBase then
            task.wait(0.3) -- slightly delay starting carpet speed to brainrot for close bases to avoid anti-cheat flag
        end
        
        -- Walk to brainrot with Carpet Speed instead of direct teleport
        local targetBrainrotPos = targetPart.Position
        local distToBrainrot = (hrp.Position - targetBrainrotPos).Magnitude
        
        if distToBrainrot > 3 then
            -- Equip carpet and walk there with carpet speed
            local toolName = Config.TpSettings.Tool or "Flying Carpet"
            local tool = LocalPlayer.Backpack:FindFirstChild(toolName) or char:FindFirstChild(toolName)
            if tool and tool.Parent ~= char then hum:EquipTool(tool); task.wait(0.02) end
            
            local walkTimeout = os.clock()
            local WALK_SPEED = 190
            
            while hrp.Parent and (os.clock() - walkTimeout) < 8 do
                if LocalPlayer:GetAttribute("Stealing") then break end
                local brPos = targetPart.Position
                local diff = Vector3.new(brPos.X - hrp.Position.X, 0, brPos.Z - hrp.Position.Z)
                local flatDist = diff.Magnitude
                
                local verticalDiff = brPos.Y - hrp.Position.Y
                if flatDist < 3 and math.abs(verticalDiff) < 8 then break end
                
                local moveDir = (flatDist > 0.1) and diff.Unit or Vector3.zero
                local yVel = hrp.AssemblyLinearVelocity.Y
                
                -- Handle vertical: if brainrot is above, rise up smoothly
                if verticalDiff > 2 then
                    yVel = math.clamp(verticalDiff * 7, 30, 60)
                elseif verticalDiff < -2 then
                    yVel = math.clamp(verticalDiff * 4, -80, 0)
                end
                
                local currentWalkSpeed = WALK_SPEED
                if flatDist < 3 then currentWalkSpeed = 0 end
                
                hrp.AssemblyLinearVelocity = Vector3.new(moveDir.X * currentWalkSpeed, yVel, moveDir.Z * currentWalkSpeed)
                RunService.Heartbeat:Wait()
            end
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
        
        -- Final positioning near brainrot
        local verticalDiff = targetPart.Position.Y - hrp.Position.Y
        if verticalDiff > 2 then
            local airPos = Vector3.new(targetPart.Position.X, targetPart.Position.Y - 8, targetPart.Position.Z)
            local plat = Instance.new("Part")
            plat.Name = "XiTempPlatform"
            plat.Size = Vector3.new(6, 1.5, 6)
            plat.Position = airPos - Vector3.new(0, 3, 0)
            plat.Color = Color3.fromRGB(232, 111, 177)
            plat.Material = Enum.Material.Neon
            plat.Anchored = true
            plat.CanCollide = false; pcall(makeOneWay, plat)
            plat.Transparency = 0.3
            plat.Parent = Workspace
            
            -- Smooth CFrame Lerp to prevent anti-cheat triggers and flinging
            local startCF = hrp.CFrame
            local targetCF = CFrame.new(airPos)
            local duration = 0.6
            local start = tick()
            while tick() - start < duration and hrp.Parent do
                if LocalPlayer:GetAttribute("Stealing") then break end
                local t = (tick() - start) / duration
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = startCF:Lerp(targetCF, t)
                RunService.Heartbeat:Wait()
            end
            hrp.CFrame = targetCF
            hrp.AssemblyLinearVelocity = Vector3.zero
            task.spawn(function()
                local start = tick()
                while (tick() - start) < 20 do
                    if LocalPlayer:GetAttribute("Stealing") then break end
                    task.wait(0.1)
                end
                plat:Destroy()
            end)
        else
            for i = 1, 5 do
                if LocalPlayer:GetAttribute("Stealing") then break end
                hrp.AssemblyLinearVelocity = Vector3.zero
                if (hrp.Position - targetPart.Position).Magnitude > 3 then
                    hrp.CFrame = CFrame.new(targetPart.Position)
                end
                task.wait(0.05)
            end
        end
    end)
    _G._isTpMoving = false
    pcall(setfpscap, lastFpsCap)
    if not ok then
        warn("runAutoSnipe error:", err)
    end
end

function tpToBrainrot()
    local targetPetData = getTargetPetData()
    if not targetPetData then
        return
    end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChild("Humanoid")
    if not hrp or not hum or (hum.Health <= 0) then
        return
    end
    local targetPart = nil
    for _ = 1, 10 do
        targetPart = findAdorneeGlobal(targetPetData)
        if targetPart then
            break
        end
        task.wait(0.05)
    end
    if not targetPart then
        return
    end
    local lastFpsCap = pcall(getfpscap) and getfpscap() or 9999
    pcall(setfpscap, 200)
    local ok, err = pcall(function()
        local carpetName = Config.TpSettings.Tool
        local carpet = LocalPlayer.Backpack:FindFirstChild(carpetName) or char:FindFirstChild(carpetName)
        if carpet then
            hum:EquipTool(carpet)
        end
        local targetPos = targetPart.Position
        local verticalDiff = targetPos.Y - hrp.Position.Y
        if verticalDiff > 2 or targetPos.Y > 25 then
            local plat = Instance.new("Part")
            plat.Name = "XiTempPlatform"
            plat.Size = Vector3.new(6, 1.5, 6)
            plat.Position = Vector3.new(targetPos.X, targetPos.Y - 11, targetPos.Z)
            plat.Color = Color3.fromRGB(232, 111, 177)
            plat.Material = Enum.Material.Neon
            plat.Anchored = true
            plat.CanCollide = false; pcall(makeOneWay, plat)
            plat.Transparency = 0.3
            plat.Parent = Workspace
            
            -- Instant teleport instead of lerp
            local targetCF = CFrame.new(targetPos.X, targetPos.Y - 8, targetPos.Z)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = targetCF
            task.wait(0.05)
            hrp.AssemblyLinearVelocity = Vector3.zero
            
            task.spawn(function()
                local start = tick()
                while (tick() - start) < 20 do
                    if LocalPlayer:GetAttribute("Stealing") then
                        break
                    end
                    task.wait(0.1)
                end
                plat:Destroy()
            end)
        else
            -- Instant teleport to brainrot
            local targetCF = CFrame.new(targetPos)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = targetCF
            task.wait(0.05)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            local holdEnd = tick() + math.max(0.18, Config.TpSettings.DelayVal or 0.4)
            while tick() < holdEnd do
                if not hrp.Parent then
                    break
                end
                if LocalPlayer:GetAttribute("Stealing") then
                    break
                end
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                pcall(function() hrp.CFrame = CFrame.new(targetPos) end)
                RunService.Heartbeat:Wait()
            end
        end
    end)
    pcall(setfpscap, lastFpsCap)
    if not ok then
        warn("tpToBrainrot error:", err)
    end
end
_G.runAutoSnipe = runAutoSnipe
_G.tpToBrainrot = tpToBrainrot

-- ============================================================
-- CLICK TO AP
-- ============================================================
local ctapHighlight=Instance.new("Highlight",CoreGui)
ctapHighlight.FillColor=Color3.fromRGB(255,150,200); ctapHighlight.FillTransparency=0.3
ctapHighlight.OutlineColor=Color3.fromRGB(255,150,200); ctapHighlight.OutlineTransparency=0
ctapHighlight.Adornee=nil; ctapHighlight.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop

local function rayToCubeIntersect(rayOrigin,rayDirection,cubeCenter,cubeSize)
    local halfSize=cubeSize/2; local minB=cubeCenter-Vector3.new(halfSize,halfSize,halfSize); local maxB=cubeCenter+Vector3.new(halfSize,halfSize,halfSize)
    local rd=Vector3.new(rayDirection.X==0 and 0.0001 or rayDirection.X, rayDirection.Y==0 and 0.0001 or rayDirection.Y, rayDirection.Z==0 and 0.0001 or rayDirection.Z)
    local tmin,tmax=(minB.X-rayOrigin.X)/rd.X,(maxB.X-rayOrigin.X)/rd.X; if tmin>tmax then tmin,tmax=tmax,tmin end
    local tymin,tymax=(minB.Y-rayOrigin.Y)/rd.Y,(maxB.Y-rayOrigin.Y)/rd.Y; if tymin>tymax then tymin,tymax=tymax,tymin end
    if tmin>tymax or tymin>tmax then return false end; if tymin>tmin then tmin=tymin end; if tymax<tmax then tmax=tymax end
    local tzmin,tzmax=(minB.Z-rayOrigin.Z)/rd.Z,(maxB.Z-rayOrigin.Z)/rd.Z; if tzmin>tzmax then tzmin,tzmax=tzmax,tzmin end
    return not(tmin>tzmax or tzmin>tmax)
end

RunService.RenderStepped:Connect(function()
    if Config.ClickToAP then
        local camera=Workspace.CurrentCamera; local mousePos=UIS:GetMouseLocation()
        local ray=camera:ViewportPointToRay(mousePos.X,mousePos.Y); local bestPlayer,bestDist=nil,math.huge
        for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            if rayToCubeIntersect(ray.Origin,ray.Direction,p.Character.HumanoidRootPart.Position,Config.ClickToAPRadius or 8) then
                local dist=(ray.Origin-p.Character.HumanoidRootPart.Position).Magnitude; if dist<bestDist then bestDist=dist; bestPlayer=p end
            end
        end end
        ctapHighlight.Adornee=(bestPlayer and bestPlayer.Character) or nil
    else ctapHighlight.Adornee=nil end
end)

UIS.InputBegan:Connect(function(inp,g)
    if not g and inp.UserInputType==Enum.UserInputType.MouseButton1 and Config.ClickToAP then
        local camera=Workspace.CurrentCamera; local mousePos=UIS:GetMouseLocation()
        local ray=camera:ViewportPointToRay(mousePos.X,mousePos.Y); local bestPlayer,bestDist=nil,math.huge
        for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            if rayToCubeIntersect(ray.Origin,ray.Direction,p.Character.HumanoidRootPart.Position,Config.ClickToAPRadius or 8) then
                local dist=(ray.Origin-p.Character.HumanoidRootPart.Position).Magnitude; if dist<bestDist then bestDist=dist; bestPlayer=p end
            end
        end end
        if bestPlayer then
            if isPlayerBlacklisted(bestPlayer) then
                ShowNotification("CLICK AP", bestPlayer.DisplayName .. " is blacklisted")
                return
            end
            local cmdList = Config.ClickToAPOrder or AP_ALL_COMMANDS
            local startIndex = _G.ClickToAPIndex or 1
            if startIndex > #cmdList then startIndex = 1 end
            
            local picked = nil
            local attempts = 0
            while attempts < #cmdList do
                local idx = ((startIndex - 1 + attempts) % #cmdList) + 1
                local cmd = cmdList[idx]
                if Config.ClickToAPCommands and Config.ClickToAPCommands[cmd] and not apIsOnCooldown(cmd) then
                    picked = cmd
                    _G.ClickToAPIndex = idx + 1
                    break
                end
                attempts = attempts + 1
            end

            if not picked then
                ShowNotification("CLICK AP", "No commands enabled or all on cooldown")
                return
            end

            if runAdminCommand(bestPlayer, picked) then
                local emoji = AP_COMMAND_EMOJIS[picked] or "⚡"
                ShowNotification("CLICK AP", emoji .. " " .. picked .. " → " .. bestPlayer.DisplayName)
            end
        end
    end
end)

-- ============================================================
-- ESP
-- ============================================================
-- Player ESP
local playerESPEnabled=Config.PlayerESP; local playerBillboards={}
DANGER_TOOLS={["Boogie Bomb"]=true,["Medusa's Head"]=true,["Body Swap Potion"]=true,["Laser Cape"]=true,["Rainbowrath Sword"]=true,["Gummy Bear"]=true}
local function getHeldTool(p) local c=p.Character; if not c then return nil end; for _,o in ipairs(c:GetChildren()) do if o:IsA("Tool") then return o.Name end end; return nil end
local function makePlayerBillboard(plr)
    local bb=Instance.new("BillboardGui"); bb.Name="PlayerESP_"..tostring(plr.UserId); bb.Size=UDim2.new(0,170,0,34)
    bb.StudsOffsetWorldSpace=Vector3.new(0,2.8,0); bb.AlwaysOnTop=true; bb.LightInfluence=0; bb.ResetOnSpawn=false
    local nameLbl=Instance.new("TextLabel",bb); nameLbl.Size=UDim2.new(1,0,0,18); nameLbl.BackgroundTransparency=1
    nameLbl.Font=Enum.Font.GothamBold; nameLbl.TextSize=14; nameLbl.TextColor3=Color3.fromRGB(255,255,255)
    nameLbl.TextStrokeTransparency=0.4; nameLbl.TextStrokeColor3=Color3.fromRGB(0,0,0); nameLbl.Text=plr.Name
    local toolLbl=Instance.new("TextLabel",bb); toolLbl.Name="ToolLabel"; toolLbl.Size=UDim2.new(1,0,0,13); toolLbl.Position=UDim2.new(0,0,0,18)
    toolLbl.BackgroundTransparency=1; toolLbl.Font=Enum.Font.GothamMedium; toolLbl.TextSize=11; toolLbl.TextColor3=Color3.fromRGB(100,220,255)
    toolLbl.TextStrokeTransparency=0.4; toolLbl.TextStrokeColor3=Color3.fromRGB(0,0,0); toolLbl.Text=getHeldTool(plr) or ""
    return bb,nameLbl
end
local function createOrRefreshPlayerESP(plr)
    if plr==LocalPlayer then return end; local hrp=plr.Character and plr.Character:FindFirstChild("HumanoidRootPart"); if not hrp then return end
    local hum=plr.Character:FindFirstChild("Humanoid"); if hum then hum.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None end
    local uid=plr.UserId; local entry=playerBillboards[uid]
    if not entry or not entry.bb or not entry.bb.Parent then
        if entry and entry.bb then pcall(function() entry.bb:Destroy() end) end
        local bb,nameLbl=makePlayerBillboard(plr); bb.Adornee=hrp; bb.Parent=hrp; playerBillboards[uid]={bb=bb,nameLbl=nameLbl,player=plr}
    elseif entry.bb.Adornee~=hrp then entry.bb.Adornee=hrp; entry.bb.Parent=hrp end
end
local function clearPlayerESP()
    for uid,entry in pairs(playerBillboards) do if entry.bb then pcall(entry.bb.Destroy,entry.bb) end; playerBillboards[uid]=nil end
end
task.spawn(function() while true do task.wait(0.5)
    if playerESPEnabled then
        for _,plr in ipairs(Players:GetPlayers()) do if plr~=LocalPlayer then pcall(createOrRefreshPlayerESP,plr) end end
        for uid,entry in pairs(playerBillboards) do if entry.bb and entry.bb.Parent then
            pcall(function() local tl=entry.bb:FindFirstChild("ToolLabel"); if tl then local ht=getHeldTool(entry.player); tl.Text=ht or ""
                if entry.nameLbl then entry.nameLbl.TextColor3=ht and DANGER_TOOLS[ht] and Color3.fromRGB(255,60,60) or Color3.fromRGB(255,255,255) end
            end end)
        end end
    else clearPlayerESP() end
end end)

-- Line To Base ESP (kinqs beam style)
do
    local plotBeam = nil
    local plotBeamAttachment0 = nil
    local plotBeamAttachment1 = nil

    local function findMyPlot()
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return nil end
        for _, plot in ipairs(plots:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign")
            if sign then
                local surfaceGui = sign:FindFirstChildWhichIsA("SurfaceGui", true)
                if surfaceGui then
                    local label = surfaceGui:FindFirstChildWhichIsA("TextLabel", true)
                    if label then
                        local text = label.Text:lower()
                        if text:find(LocalPlayer.DisplayName:lower(), 1, true) or text:find(LocalPlayer.Name:lower(), 1, true) then
                            return plot
                        end
                    end
                end
            end
        end
        return nil
    end

    local function createPlotBeam()
        if not Config.LineToBase then return end
        local myPlot = findMyPlot()
        if not myPlot or not myPlot.Parent then return end
        local character = LocalPlayer.Character
        if not character or not character.Parent then return end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        if plotBeam then pcall(function() plotBeam:Destroy() end) end
        if plotBeamAttachment0 then pcall(function() plotBeamAttachment0:Destroy() end) end
        plotBeamAttachment0 = hrp:FindFirstChild("PlotBeamAttach_Player") or Instance.new("Attachment")
        plotBeamAttachment0.Name = "PlotBeamAttach_Player"
        plotBeamAttachment0.Position = Vector3.new(0, 0, 0)
        plotBeamAttachment0.Parent = hrp
        local plotPart = myPlot:FindFirstChild("MainRootPart") or myPlot:FindFirstChildWhichIsA("BasePart")
        if not plotPart or not plotPart.Parent then return end
        plotBeamAttachment1 = plotPart:FindFirstChild("PlotBeamAttach_Plot") or Instance.new("Attachment")
        plotBeamAttachment1.Name = "PlotBeamAttach_Plot"
        plotBeamAttachment1.Position = Vector3.new(0, 5, 0)
        plotBeamAttachment1.Parent = plotPart
        plotBeam = hrp:FindFirstChild("PlotBeam") or Instance.new("Beam")
        plotBeam.Name = "PlotBeam"
        plotBeam.Attachment0 = plotBeamAttachment0
        plotBeam.Attachment1 = plotBeamAttachment1
        plotBeam.FaceCamera = true
        plotBeam.LightEmission = 1
        plotBeam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
        plotBeam.Transparency = NumberSequence.new(0)
        plotBeam.Width0 = 0.3
        plotBeam.Width1 = 0.3
        plotBeam.TextureMode = Enum.TextureMode.Wrap
        plotBeam.TextureSpeed = 0
        plotBeam.Parent = hrp
    end

    local function resetPlotBeam()
        if plotBeam then pcall(function() plotBeam:Destroy() end) end
        if plotBeamAttachment0 then pcall(function() plotBeamAttachment0:Destroy() end) end
        if plotBeamAttachment1 then pcall(function() plotBeamAttachment1:Destroy() end) end
        plotBeam = nil
        plotBeamAttachment0 = nil
        plotBeamAttachment1 = nil
    end

    task.spawn(function()
        local checkCounter = 0
        RunService.Heartbeat:Connect(function()
            if not Config.LineToBase then return end
            checkCounter = checkCounter + 1
            if checkCounter >= 30 then
                checkCounter = 0
                if not plotBeam or not plotBeam.Parent or not plotBeamAttachment0 or not plotBeamAttachment0.Parent then
                    pcall(createPlotBeam)
                end
            end
        end)
    end)

    LocalPlayer.CharacterAdded:Connect(function(character)
        task.wait(0.5)
        if Config.LineToBase and character then
            pcall(createPlotBeam)
        end
    end)

    if LocalPlayer.Character then
        task.spawn(function()
            task.wait(0.2)
            if Config.LineToBase then createPlotBeam() end
        end)
    end

    _G.createPlotBeam = createPlotBeam
    _G.resetPlotBeam = resetPlotBeam
end

-- Line To Best Brainrot (kinqs beam style)
do
    local BEAM_NAME    = "BestPetBeam"
    local ATT0_NAME    = "BestPetBeamAttach_Player"
    local ATT1_NAME    = "BestPetBeamAttach_Target"
    local BEAM_COLOR   = Color3.fromRGB(255, 45, 190)   -- pink (line to best brainrot)

    local bestBeam     = nil
    local bestAtt0     = nil
    local bestAtt1     = nil
    local currentTargetPart = nil

    local function destroyBeam()
        if bestBeam then pcall(function() bestBeam:Destroy() end) end
        if bestAtt0 then pcall(function() bestAtt0:Destroy() end) end
        if bestAtt1 then pcall(function() bestAtt1:Destroy() end) end
        bestBeam, bestAtt0, bestAtt1 = nil, nil, nil
        currentTargetPart = nil
    end

    local function getBestTargetPart()
        local cache = SharedState.AllAnimalsCache
        if not cache or #cache == 0 then return nil end
        local bestData = nil
        local bestVal = 0
        -- Priority list first
        for _, pName in ipairs(priorityList) do
            local searchName = pName:lower()
            for _, a in ipairs(cache) do
                if a and a.name and a.name:lower() == searchName and a.owner ~= LocalPlayer.Name then
                    local score = (a.genValue or 0) + 1e15
                    if score > bestVal then
                        bestVal = score
                        bestData = a
                    end
                end
            end
            if bestData then break end
        end
        -- Then brainrots by value
        if not bestData then
            for _, a in ipairs(cache) do
                if a and a.owner ~= LocalPlayer.Name and a.genValue and a.genValue >= 10000000 then
                    if a.genValue > bestVal then
                        bestVal = a.genValue
                        bestData = a
                    end
                end
            end
        end
        -- Then highest gen fallback
        if not bestData then
            for _, a in ipairs(cache) do
                if a and a.owner ~= LocalPlayer.Name and (a.genValue or 0) >= 1 then
                    if (a.genValue or 0) > bestVal then
                        bestVal = a.genValue or 0
                        bestData = a
                    end
                end
            end
        end
        if not bestData then return nil end
        local adornee = findAdorneeGlobal(bestData)
        if adornee and adornee:IsA("BasePart") then return adornee end
        return nil
    end

    local function ensureBeam(hrp, targetPart)
        if not hrp or not hrp.Parent or not targetPart or not targetPart.Parent then return end
        if not bestAtt0 or not bestAtt0.Parent or bestAtt0.Parent ~= hrp then
            if bestAtt0 then pcall(function() bestAtt0:Destroy() end) end
            bestAtt0 = hrp:FindFirstChild(ATT0_NAME) or Instance.new("Attachment")
            bestAtt0.Name = ATT0_NAME
            bestAtt0.Position = Vector3.new(0, 0, 0)
            bestAtt0.Parent = hrp
        end
        if currentTargetPart ~= targetPart or not bestAtt1 or not bestAtt1.Parent then
            if bestAtt1 then pcall(function() bestAtt1:Destroy() end) end
            bestAtt1 = targetPart:FindFirstChild(ATT1_NAME) or Instance.new("Attachment")
            bestAtt1.Name = ATT1_NAME
            bestAtt1.Position = Vector3.new(0, 3, 0)
            bestAtt1.Parent = targetPart
            currentTargetPart = targetPart
            if bestBeam then
                bestBeam.Attachment1 = bestAtt1
            end
        end
        if not bestBeam or not bestBeam.Parent then
            if bestBeam then pcall(function() bestBeam:Destroy() end) end
            bestBeam = Instance.new("Beam")
            bestBeam.Name = BEAM_NAME
            bestBeam.Attachment0 = bestAtt0
            bestBeam.Attachment1 = bestAtt1
            bestBeam.FaceCamera = true
            bestBeam.LightEmission = 1
            bestBeam.Color = ColorSequence.new(BEAM_COLOR)
            bestBeam.Transparency = NumberSequence.new(0.35)
            bestBeam.Width0 = 0.45
            bestBeam.Width1 = 0.45
            bestBeam.TextureMode = Enum.TextureMode.Wrap
            bestBeam.TextureSpeed = 0
            bestBeam.Parent = hrp
        end
    end

    task.spawn(function()
        local check = 0
        RunService.Heartbeat:Connect(function()
            if not Config.LineToBrainrot then
                if bestBeam or bestAtt0 or bestAtt1 then destroyBeam() end
                return
            end
            check = check + 1
            if check < 10 then return end
            check = 0

            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then
                if bestBeam or bestAtt0 or bestAtt1 then destroyBeam() end
                return
            end

            local targetPart = getBestTargetPart()
            if not targetPart or not targetPart.Parent then
                if bestBeam or bestAtt1 then
                    if bestBeam then pcall(function() bestBeam:Destroy() end); bestBeam = nil end
                    if bestAtt1 then pcall(function() bestAtt1:Destroy() end); bestAtt1 = nil end
                    currentTargetPart = nil
                end
                return
            end

            pcall(ensureBeam, hrp, targetPart)

            -- Color coding: green when stealing, yellow when close, red default
            if bestBeam then
                local col = BEAM_COLOR
                if LocalPlayer:GetAttribute("Stealing") then
                    col = Color3.fromRGB(80, 255, 120)
                else
                    local dist = hrp and targetPart and (hrp.Position - targetPart.Position).Magnitude or math.huge
                    if dist < 30 then
                        col = Color3.fromRGB(255, 196, 72)
                    end
                end
                bestBeam.Color = ColorSequence.new(col)
            end
        end)
    end)

    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.5)
        currentTargetPart = nil
        bestAtt0 = nil
        if bestBeam then pcall(function() bestBeam:Destroy() end); bestBeam = nil end
    end)

    _G.updateBrainrotBeam = function()
        -- beam auto-updates via heartbeat, nothing to do
    end
    _G.resetBrainrotBeam = destroyBeam
    _G.resetBestPetBeam = destroyBeam
end

-- Brainrot ESP
local brainrotESPEnabled=Config.BrainrotESP; local brainrotBillboards={}
local function createBrainrotBillboard(data)
    local bb=Instance.new("BillboardGui"); bb.Name="BrainrotESP_"..data.uid; bb.Size=UDim2.new(0,160,0,38)
    bb.StudsOffset=Vector3.new(0,1.8,0); bb.AlwaysOnTop=true; bb.LightInfluence=0; bb.MaxDistance=3000
    local container=Instance.new("Frame",bb); container.Size=UDim2.new(1,0,1,0); container.BackgroundColor3=Color3.fromRGB(0,0,0)
    container.BackgroundTransparency=0.5; container.BorderSizePixel=0; Instance.new("UICorner",container).CornerRadius=UDim.new(0,4)
    local stroke=Instance.new("UIStroke",container); stroke.Color=Color3.fromRGB(175,175,175); stroke.Thickness=1.5; stroke.Transparency=0.2
    local nameLabel=Instance.new("TextLabel",container); nameLabel.Size=UDim2.new(1,-6,0,18); nameLabel.Position=UDim2.new(0,3,0,2)
    nameLabel.BackgroundTransparency=1; nameLabel.Font=Enum.Font.GothamBlack; nameLabel.TextSize=13; nameLabel.TextColor3=Color3.fromRGB(175,175,175)
    nameLabel.TextStrokeTransparency=0; nameLabel.TextStrokeColor3=Color3.fromRGB(0,0,0); nameLabel.Text=data.name or "???"; nameLabel.TextXAlignment=Enum.TextXAlignment.Center
    local genLabel=Instance.new("TextLabel",container); genLabel.Size=UDim2.new(1,-6,0,14); genLabel.Position=UDim2.new(0,3,0,20)
    genLabel.BackgroundTransparency=1; genLabel.Font=Enum.Font.GothamBold; genLabel.TextSize=11; genLabel.TextColor3=Color3.fromRGB(255,255,255)
    genLabel.TextStrokeTransparency=0; genLabel.TextStrokeColor3=Color3.fromRGB(0,0,0); genLabel.Text=data.genText or ""; genLabel.TextXAlignment=Enum.TextXAlignment.Center
    return bb
end
local function refreshBrainrotESP()
    if not brainrotESPEnabled then return end; local cache=SharedState.AllAnimalsCache; if not cache or #cache==0 then return end
    local seen={}
    for _,data in ipairs(cache) do if data.genValue>=10000000 then seen[data.uid]=true
        if not brainrotBillboards[data.uid] then
            local adornee=findAdorneeGlobal(data)
            if adornee then local bb=createBrainrotBillboard(data); bb.Adornee=adornee; bb.Parent=adornee
                local hlParent=(adornee.Parent and adornee.Parent:IsA("Model") and adornee.Parent) or adornee
                local hl=Instance.new("Highlight"); hl.Name="BrainrotHL_"..data.uid; hl.FillColor=Color3.fromRGB(175,175,175); hl.FillTransparency=0.65
                hl.OutlineColor=Color3.fromRGB(175,175,175); hl.OutlineTransparency=0.1; hl.DepthMode=Enum.HighlightDepthMode.AlwaysOnTop; hl.Adornee=hlParent; hl.Parent=hlParent
                brainrotBillboards[data.uid]={bb=bb,highlight=hl}
            end
        end
    end end
    for uid,entry in pairs(brainrotBillboards) do if not seen[uid] then
        if entry.bb then entry.bb:Destroy() end; if entry.highlight then entry.highlight:Destroy() end; brainrotBillboards[uid]=nil
    end end
end
local function clearBrainrotESP() for _,e in pairs(brainrotBillboards) do if e.bb then e.bb:Destroy() end; if e.highlight then e.highlight:Destroy() end end; brainrotBillboards={} end
task.spawn(function() while true do task.wait(0.3); if brainrotESPEnabled then pcall(refreshBrainrotESP) end end end)

-- Subspace Mine ESP
local subspaceMineESPEnabled=Config.SubspaceMineESP; local subspaceMineESPData={}
local function refreshSubspaceMineESP()
    if not subspaceMineESPEnabled then return end; local tools=Workspace:FindFirstChild("ToolsAdds"); if not tools then return end
    local currentMines={}
    for _,obj in ipairs(tools:GetChildren()) do if obj.Name:match("SubspaceTripmine") and obj:IsA("BasePart") then currentMines[obj]=true
        if not subspaceMineESPData[obj] then
            local ownerName=obj.Name:match("SubspaceTripmine(.+)") or "Unknown"
            local sel=Instance.new("SelectionBox",obj); sel.Color3=Color3.fromRGB(167,142,255); sel.LineThickness=0.05
            local bb=Instance.new("BillboardGui",obj); bb.Size=UDim2.new(0,250,0,50); bb.StudsOffset=Vector3.new(0,2.5,0); bb.AlwaysOnTop=false
            local lbl=Instance.new("TextLabel",bb); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Text=ownerName.."'s Subspace Mine"
            lbl.TextColor3=Color3.fromRGB(167,142,255); lbl.TextStrokeTransparency=0; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=16
            subspaceMineESPData[obj]={sel=sel,bb=bb}
        end
    end end
    for mineObj,data in pairs(subspaceMineESPData) do if not currentMines[mineObj] or not mineObj.Parent then
        data.sel:Destroy(); data.bb:Destroy(); subspaceMineESPData[mineObj]=nil
    end end
end
task.spawn(function() while true do if subspaceMineESPEnabled then pcall(refreshSubspaceMineESP) end; task.wait(0.5) end end)

-- Timer ESP
local timerESPEnabled=Config.TimerESP
local function clearTimerESP()
    local plots = Workspace:FindFirstChild("Plots")
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            for _, desc in ipairs(plot:GetDescendants()) do
                if desc.Name == "TimerESP" and desc:IsA("BillboardGui") then
                    pcall(function() desc:Destroy() end)
                end
            end
        end
    end
end
_G.clearTimerESP = clearTimerESP

local function refreshTimerESP()
    if not timerESPEnabled then
        clearTimerESP()
        return
    end
    local plots=Workspace:FindFirstChild("Plots"); if not plots then return end
    for _,plot in ipairs(plots:GetChildren()) do
        -- The game shows a timer per floor. User wants ONLY the first floor, so
        -- gather this plot's timer billboards and keep just the lowest-Y ones.
        local found = {}
        local minY = math.huge
        for _,g in ipairs(plot:GetDescendants()) do
            if g:IsA("BillboardGui") and g:FindFirstChild("RemainingTime") then
                local base=g.Adornee or g.Parent
                if base and base:IsA("BasePart") then
                    found[#found+1] = {g=g, base=base, y=base.Position.Y}
                    if base.Position.Y < minY then minY = base.Position.Y end
                end
            end
        end
        for _,item in ipairs(found) do
            local base, g = item.base, item.g
            local existing = base:FindFirstChild("TimerESP")
            if item.y <= minY + 4 then   -- first floor only
                local rt = g:FindFirstChild("RemainingTime")
                if rt then
                    if not existing then
                        local bb=Instance.new("BillboardGui"); bb.Name="TimerESP"; bb.Adornee=base; bb.Size=UDim2.new(0,98,0,26); bb.AlwaysOnTop=true; bb.StudsOffsetWorldSpace=Vector3.new(0,1.6,0)
                        local lbl=Instance.new("TextLabel",bb); lbl.Size=UDim2.new(1,0,1,0); lbl.BackgroundTransparency=1; lbl.Text=rt.Text
                        lbl.Font=Enum.Font.GothamBold; lbl.TextSize=15; lbl.TextColor3=Color3.fromRGB(255,255,255)
                        lbl.TextStrokeTransparency=0.35; lbl.TextStrokeColor3=Color3.fromRGB(0,0,0); bb.Parent=base
                    else existing.TextLabel.Text=rt.Text end
                end
            elseif existing then
                pcall(function() existing:Destroy() end)   -- not first floor -> remove
            end
        end
    end
end
task.spawn(function() while true do if timerESPEnabled then pcall(refreshTimerESP) else clearTimerESP() end; task.wait(0.5) end end)

-- ============================================================
-- Base Owner ESP  (red outline + "BASE OWNER" tag on the owner of the
-- base you are CURRENTLY standing in -- one player at a time, not all bases)
-- Wrapped in a do-block + exposed via _G so it adds no chunk-level locals.
-- ============================================================
do
    local enabled = Config.BaseOwnerESP
    local entries = {}   -- userId -> { hl = Highlight, bb = BillboardGui }

    local function destroyEntry(e)
        if not e then return end
        if e.hl then pcall(function() e.hl:Destroy() end) end
        if e.bb then pcall(function() e.bb:Destroy() end) end
    end
    local function clearAll()
        for uid, e in pairs(entries) do destroyEntry(e); entries[uid] = nil end
    end

    local function makeTag()
        local bb = Instance.new("BillboardGui")
        bb.Name = "BaseOwnerTag"
        bb.Size = UDim2.new(0, 160, 0, 34)
        bb.StudsOffsetWorldSpace = Vector3.new(0, 3.6, 0)
        bb.AlwaysOnTop = true
        bb.LightInfluence = 0
        local lbl = Instance.new("TextLabel", bb)
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBlack
        lbl.TextSize = 18
        lbl.TextColor3 = Color3.fromRGB(255, 60, 60)
        lbl.TextStrokeTransparency = 0
        lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        lbl.Text = "BASE OWNER"
        return bb
    end

    -- Highlight + tag ONLY the given player (owner of the base you're in).
    -- Passing nil clears everything.
    local function setTarget(plr)
        for uid, e in pairs(entries) do
            if not plr or uid ~= plr.UserId then destroyEntry(e); entries[uid] = nil end
        end
        if not plr or not plr.Character then return end
        local uid = plr.UserId
        local e = entries[uid]; if not e then e = {}; entries[uid] = e end
        if not e.hl or not e.hl.Parent then
            if e.hl then pcall(function() e.hl:Destroy() end) end
            local hl = Instance.new("Highlight")
            hl.Name = "BaseOwnerESP"
            hl.FillColor = Color3.fromRGB(255, 0, 0); hl.FillTransparency = 0.6
            hl.OutlineColor = Color3.fromRGB(255, 0, 0); hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Parent = CoreGui
            e.hl = hl
        end
        if e.hl.Adornee ~= plr.Character then e.hl.Adornee = plr.Character end
        if not e.bb or not e.bb.Parent then
            if e.bb then pcall(function() e.bb:Destroy() end) end
            e.bb = makeTag(); e.bb.Parent = CoreGui
        end
        local head = plr.Character:FindFirstChild("Head") or plr.Character:FindFirstChild("HumanoidRootPart")
        if head and e.bb.Adornee ~= head then e.bb.Adornee = head end
    end

    local function refresh()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then setTarget(nil); return end
        local plot = getPlotAtPosition(hrp.Position)
        local owner = plot and getPlotOwner(plot)
        if owner == LocalPlayer then owner = nil end   -- don't tag your own base
        setTarget(owner)
    end
    _G.setBaseOwnerESP = function(on)
        enabled = on
        Config.BaseOwnerESP = on
        saveConfig()
        setToggle("Base Owner ESP", on)
        if on then pcall(refresh) else clearAll() end
    end
    _G.clearBaseOwnerESP = clearAll
    task.spawn(function()
        while true do
            task.wait(0.5)
            if enabled then pcall(refresh) end
        end
    end)
end

-- ============================================================
-- FPS BOOST
-- ============================================================
local function IsProtected(obj)
    if not obj then return false end
    local name = obj.Name:lower()
    if name:find("laser") or name:find("door") or name:find("gate") or name:find("shield") or name:find("barrier") or name:find("fence") or name:find("forcefield") or name:find("wall") or name:find("protect") then
        return true
    end
    local parent = obj.Parent
    while parent and parent ~= Workspace do
        local pName = parent.Name:lower()
        if pName:find("laser") or pName:find("door") or pName:find("gate") or pName:find("shield") or pName:find("barrier") or pName:find("fence") or pName:find("forcefield") or pName:find("wall") or pName:find("protect") then
            return true
        end
        parent = parent.Parent
    end
    return false
end

local fpsBoostConnection = nil
local function setFPSBoost(enabled) Config.FPSBoost=enabled; saveConfig()
    setToggle("FPS Boost (normal)", enabled)
    if fpsBoostConnection then
        pcall(function() fpsBoostConnection:Disconnect() end)
        fpsBoostConnection = nil
    end
    if enabled then
        Lighting.GlobalShadows=false; Lighting.Brightness=2; Lighting.FogEnd=9e9; Lighting.FogStart=0
        Lighting.EnvironmentDiffuseScale=0; Lighting.EnvironmentSpecularScale=0
        for _,v in pairs(Lighting:GetChildren()) do
            if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("SunRaysEffect") or v:IsA("DepthOfFieldEffect") then pcall(function() v.Enabled=false end) elseif v:IsA("Atmosphere") then pcall(function() v:Destroy() end) end
        end
        for _,obj in ipairs(Workspace:GetDescendants()) do
            if not IsProtected(obj) then
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then pcall(function() obj.Enabled=false end) end
                if obj:IsA("BasePart") then pcall(function() obj.Material=Enum.Material.Plastic; obj.CastShadow=false end) end
                if obj:IsA("SurfaceAppearance") or obj:IsA("Texture") or obj:IsA("Decal") then pcall(function() obj:Destroy() end) end
            end
        end
        fpsBoostConnection = Workspace.DescendantAdded:Connect(function(obj)
            if not Config.FPSBoost then return end
            if not IsProtected(obj) then
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Smoke") then pcall(function() obj.Enabled=false end) end
                if obj:IsA("BasePart") then pcall(function() obj.Material=Enum.Material.Plastic; obj.CastShadow=false end) end
            end
        end)
    end
end

-- FPS BOOST ULTRA
local OriginalTransparency = setmetatable({}, {__mode = "k"})
local _ultraDescendantConn = nil
local _ultraLightingConn = nil
local _ultraMaterialConn = nil
local _ultraThreads = {}
local _ultraConnections = {}

local function AddUltraThread(f)
	table.insert(_ultraThreads, task.spawn(f))
end

local function AddUltraConnection(c)
	table.insert(_ultraConnections, c)
end

local function SafeDestroyUltra(obj)
	if obj.Name == "Overhead" then return end
	pcall(function() obj:Destroy() end)
end

local ClothingClasses = {
	"Shirt","Pants","ShirtGraphic",
	"Accessory","Hat","HairAccessory",
	"FaceAccessory","NeckAccessory","ShoulderAccessory",
	"FrontAccessory","BackAccessory","WaistAccessory",
}

local function IsClothing(obj)
	for _, c in ipairs(ClothingClasses) do
		if obj:IsA(c) then return true end
	end
end

local function IsCharacterPart(obj)
	local parent = obj.Parent
	while parent and parent ~= Workspace do
		if parent:IsA("Model") and Players:GetPlayerFromCharacter(parent) then
			return true
		end
		parent = parent.Parent
	end
	return false
end

local function IsOutOfRange(obj)
	if obj:IsA("BasePart") then
		local x = obj.Position.X
		return x < -560 or x > -240
	end
end

local BASE_NAMES = {
	["baseplate"] = true, ["spawnlocation"] = true, ["spawn location"] = true, ["spawn"] = true,
}

local function IsBase(obj)
	if not obj:IsA("BasePart") then return false end
	local nameLower = obj.Name:lower()
	if BASE_NAMES[nameLower] then return true end
	for n in pairs(BASE_NAMES) do
		if nameLower:find(n, 1, true) then return true end
	end
	return false
end

local function IsInBase(obj)
	local p = obj.Parent
	while p and p ~= workspace do
		if IsBase(p) then return true end
		p = p.Parent
	end
	return false
end

local function MakeTransparentUltra(obj)
	pcall(function()
		if IsBase(obj) and not IsCharacterPart(obj) then
			if OriginalTransparency[obj] == nil then
				OriginalTransparency[obj] = {trans = obj.Transparency, shadow = obj.CastShadow}
			end
			obj.Transparency = 1
			obj.CastShadow   = false
		end
	end)
end

local function StripObjectUltra(obj)
	pcall(function()
		if obj:IsA("Texture") or obj:IsA("Decal") or obj:IsA("SpecialMesh") then
			SafeDestroyUltra(obj)
		elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
			or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
			pcall(function() obj.Enabled = false end)
			SafeDestroyUltra(obj)
		elseif obj:IsA("SurfaceAppearance") then
			SafeDestroyUltra(obj)
		elseif obj:IsA("BasePart") then
			obj.CastShadow      = false
			obj.Material        = Enum.Material.Plastic
			obj.MaterialVariant = ""
			obj.Reflectance     = 0
		end
	end)
end

local function CleanObjectUltra(obj)
	pcall(function()
		if obj:IsA("SurfaceAppearance") then
			SafeDestroyUltra(obj)
		elseif obj:IsA("Decal") or obj:IsA("Texture") then
			if not (obj.Name == "face" and obj.Parent and obj.Parent.Name == "Head") then
				SafeDestroyUltra(obj)
			end
		elseif obj:IsA("SpecialMesh") then
			obj.TextureId = ""
		elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
			SafeDestroyUltra(obj)
		elseif obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
			SafeDestroyUltra(obj)
		elseif obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") or obj:IsA("Explosion") then
			SafeDestroyUltra(obj)
		elseif obj:IsA("Animation") or obj:IsA("AnimationController") then
			SafeDestroyUltra(obj)
		elseif obj:IsA("BasePart") then
			obj.CastShadow      = false
			obj.Material        = Enum.Material.Plastic
			obj.MaterialVariant = ""
			obj.Reflectance     = 0
		end
	end)
end

local function StopAnimationsUltra(animator)
	pcall(function()
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local isChar = false
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.Character and animator:IsDescendantOf(plr.Character) then
					isChar = true
					break
				end
			end
			if not isChar then
				track:Stop()
			end
		end
	end)
end

local function OptimizeCharacterUltra(char)
	if not char then return end
	task.spawn(function()
		task.wait(0.3)
		for _, obj in ipairs(char:GetDescendants()) do
			if IsClothing(obj) then
				SafeDestroyUltra(obj)
			else
				CleanObjectUltra(obj)
			end
		end
	end)
end

local function ApplyGreySkyUltra()
	pcall(function()
		for _, obj in ipairs(Lighting:GetChildren()) do
			if obj:IsA("Sky") then
				obj:Destroy()
			end
		end
		local sky        = Instance.new("Sky")
		sky.SkyboxBk     = ""
		sky.SkyboxDn     = ""
		sky.SkyboxFt     = ""
		sky.SkyboxLf     = ""
		sky.SkyboxRt     = ""
		sky.SkyboxUp     = ""
		sky.CelestialBodiesShown = false
		sky.Parent       = Lighting
	end)
end

local function OptimizeLightingUltra()
	Lighting.GlobalShadows            = false
	Lighting.FogEnd                   = 9e9
	Lighting.FogStart                 = 9e9
	Lighting.EnvironmentDiffuseScale  = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.Brightness               = 1.5
	Lighting.Ambient                  = Color3.fromRGB(60, 60, 60)

	for _, v in ipairs(Lighting:GetChildren()) do
		if v:IsA("PostEffect") then
			pcall(function() v.Enabled = false end)
		elseif v:IsA("Atmosphere") or v:IsA("Clouds") then
			v:Destroy()
		end
	end
	ApplyGreySkyUltra()
end

local function ApplyTerrainUltra()
	pcall(function()
		local T = Workspace.Terrain
		T.Decoration        = false
		T.WaterWaveSize     = 0
		T.WaterWaveSpeed    = 0
		T.WaterReflectance  = 0
		T.WaterTransparency = 1
	end)
end

local function setFPSBoostUltra(enabled)
    Config.FPSBoostUltra = enabled
    saveConfig()
    setToggle("FPS Boost Ultra", enabled)
    
    if enabled then
        pcall(function()
            settings().Rendering.QualityLevel        = Enum.QualityLevel.Level01
            settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01
            settings().Physics.AllowSleep = true
            settings().Physics.PhysicsEnvironmentalThrottle = Enum.PhysicsEnvironmentalThrottle or Enum.EnviromentalPhysicsThrottle.Skip
        end)
        pcall(setfpscap, 9999)   -- 9999 = unlimited FPS

        OptimizeLightingUltra()
        ApplyTerrainUltra()

        local allDesc = Workspace:GetDescendants()
        local BATCH_SIZE = 200
        for i = 1, #allDesc, BATCH_SIZE do
            local batchEnd = math.min(i + BATCH_SIZE - 1, #allDesc)
            for j = i, batchEnd do
                local obj = allDesc[j]
                if obj and obj.Parent then
                    if IsBase(obj) then
                        MakeTransparentUltra(obj)
                    elseif IsClothing(obj) then
                        SafeDestroyUltra(obj)
                    elseif IsInBase(obj) then
                        -- skip
                    elseif IsCharacterPart(obj) then
                        -- skip
                    elseif IsOutOfRange(obj) then
                        SafeDestroyUltra(obj)
                    else
                        CleanObjectUltra(obj)
                        StripObjectUltra(obj)
                        if obj:IsA("Animator") then
                            StopAnimationsUltra(obj)
                        end
                    end
                end
            end
            if i + BATCH_SIZE <= #allDesc then task.wait() end
        end

        AddUltraConnection(Workspace.DescendantAdded:Connect(function(obj)
            task.defer(function()
                if not Config.FPSBoostUltra then return end
                if IsBase(obj) then
                    MakeTransparentUltra(obj)
                    return
                end
                if IsClothing(obj) then
                    SafeDestroyUltra(obj)
                elseif IsInBase(obj) then
                    -- skip
                elseif IsCharacterPart(obj) then
                    -- skip
                elseif IsOutOfRange(obj) then
                    SafeDestroyUltra(obj)
                else
                    CleanObjectUltra(obj)
                    StripObjectUltra(obj)
                    if obj:IsA("Animator") then
                        StopAnimationsUltra(obj)
                    end
                end
            end)
        end))

        AddUltraConnection(Lighting.DescendantAdded:Connect(function(obj)
            if obj:IsA("PostEffect") then
                pcall(function() obj.Enabled = false end)
            elseif obj:IsA("Atmosphere") or obj:IsA("Clouds") then
                SafeDestroyUltra(obj)
            end
        end))

        local MaterialService = game:GetService("MaterialService")
        AddUltraConnection(MaterialService.DescendantAdded:Connect(function(obj)
            SafeDestroyUltra(obj)
        end))

        for _, plr in ipairs(Players:GetPlayers()) do
            OptimizeCharacterUltra(plr.Character)
            AddUltraConnection(plr.CharacterAdded:Connect(OptimizeCharacterUltra))
        end

        AddUltraConnection(Players.PlayerAdded:Connect(function(plr)
            AddUltraConnection(plr.CharacterAdded:Connect(OptimizeCharacterUltra))
        end))

        -- GC Loop
        AddUltraThread(function()
            while Config.FPSBoostUltra do
                task.wait(15)
                pcall(function() collectgarbage("collect") end)
            end
        end)
    else
        -- Clean up all connections and threads
        for _, conn in ipairs(_ultraConnections) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end
        _ultraConnections = {}
        for _, thr in ipairs(_ultraThreads) do
            pcall(function() task.cancel(thr) end)
        end
        _ultraThreads = {}

        -- Restore Baseplates opacity
        pcall(function()
            for part, data in pairs(OriginalTransparency) do
                if part and part.Parent then
                    part.Transparency = data.trans
                    part.CastShadow = data.shadow
                end
            end
        end)
        OriginalTransparency = {}

        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
            settings().Rendering.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Automatic
            Lighting.GlobalShadows = true
            Lighting.Brightness = 2
            Lighting.FogEnd = 100000
            Workspace.Terrain.WaterWaveSize = 0.15
            Workspace.Terrain.WaterWaveSpeed = 1
            Workspace.Terrain.WaterReflectance = 0.5
            Workspace.Terrain.WaterTransparency = 0.3
            Workspace.Terrain.Decoration = true
        end)
    end
end

-- ============================================================
-- X-RAY
-- ============================================================
local setXRay
do -- X-RAY SCOPE
local xrayOriginalTransparencies = setmetatable({}, {__mode = "k"})
local xrayConnections = {}
local xrayLoopId = 0

local function setXRayTargetTransparency(instance, alphaPercent, loopId)
    if not instance then return end
    if loopId and loopId ~= xrayLoopId then return end   -- X-ray already turned off

    local function apply(obj)
        if obj:IsA("BasePart") then
            if xrayOriginalTransparencies[obj] == nil then
                if obj.Transparency == alphaPercent then xrayOriginalTransparencies[obj] = 0
                else xrayOriginalTransparencies[obj] = obj.Transparency end
            end
            local orig = xrayOriginalTransparencies[obj]
            if orig < 1 then
                local target = orig + (1 - orig) * alphaPercent
                if math.abs(obj.Transparency - target) > 0.01 then obj.Transparency = target end
            end
        elseif obj:IsA("TextLabel") or obj:IsA("TextButton") then
            if xrayOriginalTransparencies[obj] == nil then
                local t, b = obj.TextTransparency, obj.BackgroundTransparency
                if t == alphaPercent then t = 0 end
                if b == alphaPercent then b = 0 end
                xrayOriginalTransparencies[obj] = {text = t, bg = b}
            end
            local orig = xrayOriginalTransparencies[obj]
            if orig.text < 1 then
                local targetText = orig.text + (1 - orig.text) * alphaPercent
                if math.abs(obj.TextTransparency - targetText) > 0.01 then obj.TextTransparency = targetText end
            end
            if orig.bg < 1 then
                local targetBg = orig.bg + (1 - orig.bg) * alphaPercent
                if math.abs(obj.BackgroundTransparency - targetBg) > 0.01 then obj.BackgroundTransparency = targetBg end
            end
        elseif obj:IsA("Frame") or obj:IsA("ScrollingFrame") then
            if xrayOriginalTransparencies[obj] == nil then
                if obj.BackgroundTransparency == alphaPercent then xrayOriginalTransparencies[obj] = 0
                else xrayOriginalTransparencies[obj] = obj.BackgroundTransparency end
            end
            local orig = xrayOriginalTransparencies[obj]
            if orig < 1 then
                local target = orig + (1 - orig) * alphaPercent
                if math.abs(obj.BackgroundTransparency - target) > 0.01 then obj.BackgroundTransparency = target end
            end
        elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
            if xrayOriginalTransparencies[obj] == nil then
                local i, b = obj.ImageTransparency, obj.BackgroundTransparency
                if i == alphaPercent then i = 0 end
                if b == alphaPercent then b = 0 end
                xrayOriginalTransparencies[obj] = {img = i, bg = b}
            end
            local orig = xrayOriginalTransparencies[obj]
            if orig.img < 1 then
                local targetImg = orig.img + (1 - orig.img) * alphaPercent
                if math.abs(obj.ImageTransparency - targetImg) > 0.01 then obj.ImageTransparency = targetImg end
            end
            if orig.bg < 1 then
                local targetBg = orig.bg + (1 - orig.bg) * alphaPercent
                if math.abs(obj.BackgroundTransparency - targetBg) > 0.01 then obj.BackgroundTransparency = targetBg end
            end
        end
    end

    apply(instance)
    local descendants = instance:GetDescendants()
    for i, child in ipairs(descendants) do
        apply(child)
        if i % 300 == 0 then
            task.wait()
            if loopId and loopId ~= xrayLoopId then return end   -- aborted: X-ray turned off mid-apply
        end
    end
end

local XRAY_FOLDERS = {"Base","PlotSign","FriendPanel","Cash","Laser","Decorations","Skin","Unlock","Purchases"}

-- X-ray a subtree once, then keep newly-streamed parts x-rayed via a cheap
-- DescendantAdded hook. Event-driven -> ZERO cost while nothing changes
-- (replaces the old 1.5s full re-walk that caused the lag).
local function trackXRaySubtree(root, alphaPercent, loopId)
    if not root then return end
    if loopId ~= xrayLoopId then return end
    setXRayTargetTransparency(root, alphaPercent, loopId)
    if loopId ~= xrayLoopId then return end   -- don't re-arm a listener after X-ray was turned off
    xrayConnections[#xrayConnections+1] = root.DescendantAdded:Connect(function(obj)
        if loopId ~= xrayLoopId then return end
        setXRayTargetTransparency(obj, alphaPercent, loopId)
    end)
end

local function processPlotXRay(plot, alphaPercent, loopId)
    if not plot then return end
    if loopId ~= xrayLoopId then return end

    for _, fname in ipairs(XRAY_FOLDERS) do
        if loopId ~= xrayLoopId then return end
        trackXRaySubtree(plot:FindFirstChild(fname), alphaPercent, loopId)
    end
    if loopId ~= xrayLoopId then return end
    -- target folders that stream in after enable
    xrayConnections[#xrayConnections+1] = plot.ChildAdded:Connect(function(child)
        if loopId ~= xrayLoopId then return end
        for _, fname in ipairs(XRAY_FOLDERS) do
            if child.Name == fname then trackXRaySubtree(child, alphaPercent, loopId); break end
        end
    end)

    local animalPodiums = plot:FindFirstChild("AnimalPodiums")
    if animalPodiums then
        local function processPodium(podium)
            for _, child in ipairs(podium:GetChildren()) do
                if child.Name == "Claim" then
                    trackXRaySubtree(child, alphaPercent, loopId)
                elseif child.Name == "Base" then
                    trackXRaySubtree(child:FindFirstChild("Decorations"), alphaPercent, loopId)
                elseif child:IsA("Model") and child.Name ~= "Decorations" then
                    trackXRaySubtree(child, alphaPercent, loopId)
                end
            end
        end
        for _, podium in ipairs(animalPodiums:GetChildren()) do processPodium(podium) end
        xrayConnections[#xrayConnections+1] = animalPodiums.ChildAdded:Connect(function(podium)
            if loopId ~= xrayLoopId then return end
            task.wait(0.1)
            if loopId ~= xrayLoopId then return end
            processPodium(podium)
        end)
    end
end

local function applyTransparencyToAllPlotsXRay(alphaPercent, loopId)
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return end

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        if loopId ~= xrayLoopId then return end
        processPlotXRay(plot, alphaPercent, loopId)
        task.wait()
    end
    -- new bases joining later
    xrayConnections[#xrayConnections+1] = plotsFolder.ChildAdded:Connect(function(plot)
        if loopId ~= xrayLoopId then return end
        task.wait(0.2)
        processPlotXRay(plot, alphaPercent, loopId)
    end)
end

function setXRay(enabled)
    Config.XRay = enabled
    saveConfig()
    setToggle("XRay", enabled)
    setToggle("X-Ray", enabled)
    setToggle("Xray", enabled)

    -- Clean up previous connections
    for _, conn in ipairs(xrayConnections) do
        if typeof(conn) == "RBXScriptConnection" then
            conn:Disconnect()
        end
    end
    xrayConnections = {}

    xrayLoopId = xrayLoopId + 1
    local currentLoopId = xrayLoopId

    if enabled then
        local alphaPercent = 0.5
        
        task.spawn(function()
            -- AÈ™teptÄƒm sÄƒ se Ã®ncarce folder-ul Plots
            while currentLoopId == xrayLoopId and not Workspace:FindFirstChild("Plots") do
                task.wait(0.5)
            end
            
            if currentLoopId ~= xrayLoopId then return end
            
            -- Initial call cu un mic delay sÄƒ dÄƒm timp primelor modele sÄƒ aparÄƒ
            if currentLoopId ~= xrayLoopId then return end
            pcall(applyTransparencyToAllPlotsXRay, alphaPercent, currentLoopId)
            
            -- Loop continuu È™i super-optimizat (fÄƒrÄƒ overlap de thread-uri)
            -- (perpetual 1.5s re-walk removed; upkeep is now event-driven)
        end)
    else
        -- Turn OFF instantly AND completely: swap the snapshot out atomically, then
        -- restore every captured original in ONE synchronous pass (no task.wait
        -- yields). This removes the old race where a restore could overlap a
        -- re-enable and leave some parts still see-through after toggling off.
        local snapshot = xrayOriginalTransparencies
        xrayOriginalTransparencies = setmetatable({}, {__mode = "k"})
        for obj, orig in pairs(snapshot) do
            pcall(function()
                if obj:IsA("BasePart") then
                    obj.Transparency = orig
                elseif obj:IsA("TextLabel") or obj:IsA("TextButton") then
                    obj.TextTransparency = orig.text
                    obj.BackgroundTransparency = orig.bg
                elseif obj:IsA("Frame") or obj:IsA("ScrollingFrame") then
                    obj.BackgroundTransparency = orig
                elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
                    obj.ImageTransparency = orig.img
                    obj.BackgroundTransparency = orig.bg
                end
            end)
        end
        -- User setting: X-ray OFF forces bases solid even when FPS Boost Ultra hid
        -- them. FPS Boost Ultra records each base's true transparency before hiding
        -- it, so re-apply those originals here -> hidden bases become visible again.
        for part, data in pairs(OriginalTransparency) do
            if part and part.Parent and typeof(data) == "table" then
                pcall(function() part.Transparency = data.trans end)
            end
        end
    end
end

_G.setXRay = setXRay
end -- END X-RAY SCOPE


-- ============================================================
-- ANTI BEE & DISCO
-- ============================================================
SharedState.ANTI_BEE_DISCO = {
    running = false,
    connections = {},
    originalMoveFunction = nil,
    controlsProtected = false,
    badLightingNames = { Blue = true, DiscoEffect = true, BeeBlur = true, ColorCorrection = true },
}
SharedState.ANTI_BEE_DISCO.nuke = function(obj)
    if not obj or not obj.Parent then return end
    if SharedState.ANTI_BEE_DISCO.badLightingNames[obj.Name] then
        pcall(function() obj:Destroy() end)
    end
end
SharedState.ANTI_BEE_DISCO.disconnectAll = function()
    for _, conn in ipairs(SharedState.ANTI_BEE_DISCO.connections) do
        if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
    end
    SharedState.ANTI_BEE_DISCO.connections = {}
end
SharedState.ANTI_BEE_DISCO.protectControls = function()
    if SharedState.ANTI_BEE_DISCO.controlsProtected then return end
    pcall(function()
        local PlayerScripts = LocalPlayer.PlayerScripts
        local PlayerModule = PlayerScripts:FindFirstChild("PlayerModule")
        if not PlayerModule then return end
        local Controls = require(PlayerModule):GetControls()
        if not Controls then return end
        local ab = SharedState.ANTI_BEE_DISCO
        if not ab.originalMoveFunction then ab.originalMoveFunction = Controls.moveFunction end
        local function protectedMoveFunction(self, moveVector, relativeToCamera)
            if ab.originalMoveFunction then ab.originalMoveFunction(self, moveVector, relativeToCamera) end
        end
        table.insert(ab.connections, RunService.Heartbeat:Connect(function()
            if not ab.running or not Config.AntiBeeDisco then return end
            if _G._isTpMoving then return end
            if Controls.moveFunction ~= protectedMoveFunction then Controls.moveFunction = protectedMoveFunction end
        end))
        Controls.moveFunction = protectedMoveFunction
        ab.controlsProtected = true
    end)
end
SharedState.ANTI_BEE_DISCO.restoreControls = function()
    if not SharedState.ANTI_BEE_DISCO.controlsProtected then return end
    pcall(function()
        local PlayerModule = LocalPlayer.PlayerScripts:FindFirstChild("PlayerModule")
        if not PlayerModule then return end
        local Controls = require(PlayerModule):GetControls()
        local ab = SharedState.ANTI_BEE_DISCO
        if Controls and ab.originalMoveFunction then
            Controls.moveFunction = ab.originalMoveFunction
            ab.controlsProtected = false
        end
    end)
end
SharedState.ANTI_BEE_DISCO.blockBuzzingSound = function()
    pcall(function()
        local beeScript = LocalPlayer.PlayerScripts:FindFirstChild("Bee", true)
        if beeScript then
            local buzzing = beeScript:FindFirstChild("Buzzing")
            if buzzing and buzzing:IsA("Sound") then
                buzzing:Stop()
                buzzing.Volume = 0
            end
        end
    end)
end
SharedState.ANTI_BEE_DISCO.Enable = function()
    local ab = SharedState.ANTI_BEE_DISCO
    if ab.running then return end
    ab.running = true
    for _, inst in ipairs(Lighting:GetDescendants()) do ab.nuke(inst) end
    table.insert(ab.connections, Lighting.DescendantAdded:Connect(function(obj)
        if not ab.running or not Config.AntiBeeDisco then return end
        ab.nuke(obj)
    end))
    ab.protectControls()
    table.insert(ab.connections, RunService.Heartbeat:Connect(function()
        if not ab.running or not Config.AntiBeeDisco then return end
        ab.blockBuzzingSound()
    end))
    ShowNotification("ANTIBEE & DISCO", "Enabled")
end
SharedState.ANTI_BEE_DISCO.Disable = function()
    local ab = SharedState.ANTI_BEE_DISCO
    if not ab.running then return end
    ab.running = false
    ab.restoreControls()
    ab.disconnectAll()
    ShowNotification("ANTI-BEE & DISCO", "Disabled")
end
_G.ANTI_BEE_DISCO = SharedState.ANTI_BEE_DISCO
if Config.AntiBeeDisco then
    task.delay(1, function()
        if SharedState.ANTI_BEE_DISCO.Enable then SharedState.ANTI_BEE_DISCO.Enable() end
    end)
end

-- ============================================================
-- AUTO BUY 
-- ============================================================
local toggleAutoBuy
do -- AUTO BUY SCOPE (NOT lazy: toggleAutoBuy must exist immediately for the UI)
local autoBuyActive = false
local autoBuyRing = nil

local function createAutoBuyRing()
    local existing = Workspace:FindFirstChild("XiAutoBuyRing")
    if existing then existing:Destroy() end
    local r = Instance.new("Part")
    r.Name = "XiAutoBuyRing"
    r.Shape = Enum.PartType.Cylinder
    r.Anchored = true
    r.CanCollide = false
    r.CanTouch = false
    r.CanQuery = false
    r.CastShadow = false
    r.Material = Enum.Material.Neon
    r.Transparency = 0.5
    r.Color = Theme.Accent
    local range = Config.AutoBuyRange or 17
    r.Size = Vector3.new(0.5, range * 2, range * 2)
    r.Parent = Workspace
    autoBuyRing = r
end

local function destroyAutoBuyRing()
    if autoBuyRing then autoBuyRing:Destroy(); autoBuyRing = nil end
    local e = Workspace:FindFirstChild("XiAutoBuyRing")
    if e then e:Destroy() end
end

local _abRingFrame = 0
RunService.Heartbeat:Connect(function()
    if not autoBuyActive then return end
    _abRingFrame = _abRingFrame + 1
    if _abRingFrame < 3 then return end
    _abRingFrame = 0
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or not autoBuyRing then return end
    local range = Config.AutoBuyRange or 17
    autoBuyRing.Size = Vector3.new(0.5, range * 2, range * 2)
    autoBuyRing.CFrame = (hrp.CFrame * CFrame.Angles(0, 0, math.rad(90))) + Vector3.new(0, -2.5, 0)
end)

-- Explicit assignment to the OUTER `local toggleAutoBuy` declared at line ~6899.
-- Was previously `function toggleAutoBuy(on)` -- syntactic sugar that some
-- contexts can mis-resolve; this form guarantees we update the outer upvalue
-- the UI closure at line 8131 captures.
toggleAutoBuy = function(on)
    if on ~= nil then
        autoBuyActive = on
    else
        autoBuyActive = not autoBuyActive
    end
    Config.AutoBuyEnabled = autoBuyActive
    pcall(saveConfig)
    pcall(setToggle, "Auto Buy", autoBuyActive)
    if autoBuyActive then createAutoBuyRing() else destroyAutoBuyRing() end
    pcall(ShowNotification, "AUTO BUY", autoBuyActive and "ENABLED" or "DISABLED")
    if _G.AutoBuyOnToggle then
        pcall(_G.AutoBuyOnToggle, autoBuyActive)
    end
end

local RARITY_WORDS = {
    common = true, uncommon = true, rare = true, epic = true,
    legendary = true, secret = true, divine = true, rainbow = true,
    cursed = true, gold = true, diamond = true,
}

local function getBrainrotName(model)
    if not model then return "Brainrot", "" end
    local nameFound, genFound = "", ""
    for _, bb in ipairs(model:GetDescendants()) do
        if bb:IsA("BillboardGui") then
            for _, lbl in ipairs(bb:GetDescendants()) do
                if lbl:IsA("TextLabel") and lbl.Text and lbl.Text ~= "" then
                    local t = lbl.Text:match("^%s*(.-)%s*$")
                    local tl = t:lower()
                    if RARITY_WORDS[tl] then continue end
                    if t:match("^%$[%d%.]+[KkMmBb]?/s$") then
                        if genFound == "" then genFound = t end
                        continue
                    end
                    if t:match("^%$[%d%.]+[KkMmBb]?$") then continue end
                    if t:match("^[%d%.]+[KkMmBb]?$") then continue end
                    if nameFound == "" and #t > 1 then nameFound = t end
                end
            end
        end
    end
    if nameFound == "" then
        pcall(function()
            local info = AnimalsData[model.Name]
            if info and info.DisplayName then
                nameFound = info.DisplayName
                local gv = AnimalsShared:GetGeneration(model.Name, nil, nil, nil)
                local gt = "$" .. NumberUtils:ToString(gv) .. "/s"
                genFound = gt
            end
        end)
    end
    if nameFound == "" then nameFound = model.Name ~= "" and model.Name or "Brainrot" end
    return nameFound, genFound
end

local function scanConveyor()
    local results = {}
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if not (obj:IsA("ProximityPrompt") and obj.Enabled) then continue end
        local txt = obj.ActionText or ""
        if not (txt == "Purchase" or txt:lower():find("purchase") or txt:lower():find("comprar")) then continue end
        local part = obj.Parent
        if not part then continue end
        local realPart = (part:IsA("Attachment") and part.Parent) or part
        if not (realPart and realPart:IsA("BasePart")) then continue end
        local model, cur = nil, realPart
        for _ = 1, 8 do
            if cur and cur:IsA("Model") then model = cur; break end
            cur = cur and cur.Parent
        end
        local name, gen = getBrainrotName(model)
        table.insert(results, {
            name = name,
            gen = gen,
            prompt = obj,
            part = realPart,
            model = model,
            source = "ESTEIRA",
            uid = "esteira_" .. tostring(obj),
        })
    end
    return results
end

SharedState.ConveyorAnimals = {}
local function refreshConveyor()
    local ok, found = pcall(scanConveyor)
    if ok and found then
        SharedState.ConveyorAnimals = found
    end
end
refreshConveyor()
_G.refreshConveyor = refreshConveyor

local purchaseRemote = nil
local function resolvePurchaseRemote()
    if purchaseRemote and purchaseRemote.Parent then return purchaseRemote end
    pcall(function()
        local net = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("Net")
        if not net then return end
        local kws = {"buy", "purchase", "animal", "shop", "acquire", "conveyor"}
        for _, v in ipairs(net:GetChildren()) do
            local nl = (v.Name or ""):lower()
            for _, kw in ipairs(kws) do
                if nl:find(kw) then
                    purchaseRemote = v
                    return
                end
            end
        end
        local paths = {"RF/ShopService/BuyAnimal", "RF/AnimalShop/Purchase", "RE/Shop/Buy", "RF/Shop/Buy"}
        for _, p in ipairs(paths) do
            local ok2, r = pcall(function() return Decrypted[p] end)
            if ok2 and r and r.Parent then
                purchaseRemote = r
                return
            end
        end
    end)
    return purchaseRemote
end

local function firePurchaseNatural(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then return end
    pcall(function()
        if fireproximityprompt then fireproximityprompt(prompt) end
    end)
    task.spawn(function()
        local remote = resolvePurchaseRemote()
        if remote then
            pcall(function()
                if remote:IsA("RemoteFunction") then
                    remote:InvokeServer(prompt.Parent)
                elseif remote:IsA("RemoteEvent") then
                    remote:FireServer(prompt.Parent)
                end
            end)
        end
    end)
end

local carpetLockConn = nil
local function startCarpetLock()
    if carpetLockConn then carpetLockConn:Disconnect(); carpetLockConn = nil end
    local function ensureCarpet()
        pcall(function()
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            local toolName = (Config.TpSettings and Config.TpSettings.Tool) or "Flying Carpet"
            if not char:FindFirstChild(toolName) then
                local tool = LocalPlayer.Backpack:FindFirstChild(toolName)
                if tool then hum:EquipTool(tool) end
            end
        end)
    end
    task.spawn(function()
        for _ = 1, 15 do
            if not autoBuyActive then break end
            ensureCarpet()
            task.wait(0.3)
            local char = LocalPlayer.Character
            local toolName = (Config.TpSettings and Config.TpSettings.Tool) or "Flying Carpet"
            if char and char:FindFirstChild(toolName) then break end
        end
    end)
    carpetLockConn = RunService.Heartbeat:Connect(function()
        if not autoBuyActive then return end
        ensureCarpet()
    end)
end

local function stopCarpetLock()
    if carpetLockConn then carpetLockConn:Disconnect(); carpetLockConn = nil end
end

local HOVER_HEIGHT = 5
local BUY_INTERVAL = 0.08
local DETECT_RADIUS = 17
local lockedTarget = nil
local lockedPart = nil
local lockedModel = nil

local function partAlive()
    return lockedPart and lockedPart.Parent and lockedModel and lockedModel.Parent
end

local function promptAlive()
    return lockedTarget and lockedTarget.prompt and lockedTarget.prompt.Parent and lockedTarget.prompt.Enabled
end

local bodyPos = nil
local function ensureBodyPos(hrp)
    if bodyPos and bodyPos.Parent == hrp then
        local speed = math.clamp(Config.AutoGrabSpeed or 17, 5, 100)
        bodyPos.P = speed * 1000
        return bodyPos
    end
    if bodyPos then bodyPos:Destroy() end
    local speed = math.clamp(Config.AutoGrabSpeed or 17, 5, 100)
    local bp = Instance.new("BodyPosition", hrp)
    bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
    bp.P = speed * 1000
    bp.D = 1000
    bp.Position = hrp.Position
    bodyPos = bp
    return bp
end

local function destroyBodyPos()
    if bodyPos then bodyPos:Destroy(); bodyPos = nil end
end

RunService.Heartbeat:Connect(function()
    if not autoBuyActive or not partAlive() then
        destroyBodyPos()
        return
    end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then destroyBodyPos(); return end
    local above = lockedPart.Position + Vector3.new(0, HOVER_HEIGHT, 0)
    local bp = ensureBodyPos(hrp)
    bp.Position = above
end)

task.spawn(function()
    while true do
        task.wait(BUY_INTERVAL)
        if not autoBuyActive then continue end
        if not partAlive() then continue end
        if promptAlive() then
            firePurchaseNatural(lockedTarget.prompt)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.25)
        if not autoBuyActive then
            lockedTarget = nil
            lockedPart = nil
            lockedModel = nil
            stopCarpetLock()
            destroyBodyPos()
            continue
        end
        if lockedPart or lockedModel then
            if not partAlive() then
                ShowNotification("AUTO BUY", "Reached base, scanning...")
                pcall(refreshConveyor)
                lockedTarget = nil
                lockedPart = nil
                lockedModel = nil
            end
            continue
        end
        pcall(refreshConveyor)
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        local radius = Config.AutoBuyRange or DETECT_RADIUS
        local best, bestDist = nil, math.huge
        for _, entry in ipairs(SharedState.ConveyorAnimals) do
            if entry.prompt and entry.prompt.Parent and entry.prompt.Enabled and entry.part and entry.part.Parent then
                local d = (hrp.Position - entry.part.Position).Magnitude
                if d <= radius and d < bestDist then
                    bestDist = d
                    best = entry
                end
            end
        end
        if best then
            lockedTarget = best
            lockedPart = best.part
            lockedModel = best.model or best.part.Parent
            ShowNotification("AUTO BUY", "Locked: " .. best.name)
            startCarpetLock()
        end
    end
end)

_G.AutoBuyOnToggle = function(active)
    if active then
        if _G.refreshConveyor then pcall(_G.refreshConveyor) end
        startCarpetLock()
    else
        stopCarpetLock()
        destroyBodyPos()
    end
end
end -- END AUTO BUY SCOPE

-- ============================================================
-- ============================================================

local function hasExclamation(target) for _,d in ipairs(target:GetDescendants()) do if d:IsA("BillboardGui") then
    local label=d:FindFirstChildWhichIsA("TextLabel",true); if label and label.Text:find("!") then return true end
end end; return false end

task.spawn(function()
    while true do task.wait(0.1)
        if Config.AutoDestroyTurrets then
            if LocalPlayer:GetAttribute("Stealing")~=true then
                local char=LocalPlayer.Character; local hrp=char and char:FindFirstChild("HumanoidRootPart"); local hum=char and char:FindFirstChildOfClass("Humanoid")
                if hrp and hum then
                    local closest,shortestDist=nil,math.huge
                    for _,inst in ipairs(Workspace:GetDescendants()) do if inst.Name:match("^Sentry_") and hasExclamation(inst) then
                        local root=inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart",true)
                        if root then
                            local dist=(hrp.Position-root.Position).Magnitude
                            if dist <= 29 and dist<shortestDist then shortestDist=dist; closest=inst end
                        end
                    end end
                    if closest then
                        -- Make turret visible and move in front of player
                        for _,d in ipairs(closest:GetDescendants()) do if d:IsA("BasePart") then d.Transparency=0.5; d.CanCollide=false end end
                        local offset=hrp.CFrame.LookVector*4; local targetCF=CFrame.new(hrp.Position+offset,hrp.Position)
                        if closest:IsA("Model") then closest:PivotTo(targetCF) elseif closest:IsA("BasePart") then closest.CFrame=targetCF end
                        local bat=player.Backpack:FindFirstChild("Bat") or char:FindFirstChild("Bat")
                        if bat then if bat.Parent~=char then hum:EquipTool(bat) end; bat:Activate() end
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- REMOTE SELLER
-- ============================================================
LazyInit("Remote Sell UI", function() -- REMOTE SELL SCOPE
local remoteSellGui=nil; local remoteSellBuilt=false
local function buildRemoteSell()
    if remoteSellBuilt then return end; remoteSellBuilt=true
    local Synchronizer_rs=nil; local AnimalsData_rs,AnimalsShared_rs,NumberUtils_rs=nil,nil,nil
    pcall(function()
        local Pkgs=ReplicatedStorage:WaitForChild("Packages",10); local Datas=ReplicatedStorage:WaitForChild("Datas",10)
        local Shared=ReplicatedStorage:WaitForChild("Shared",10); local Utils=ReplicatedStorage:WaitForChild("Utils",10)
        if Pkgs then Synchronizer_rs=require(Pkgs:WaitForChild("Synchronizer")) end
        if Datas then AnimalsData_rs=require(Datas:WaitForChild("Animals")) end
        if Shared then AnimalsShared_rs=require(Shared:WaitForChild("Animals")) end
        if Utils then NumberUtils_rs=require(Utils:WaitForChild("NumberUtils")) end
    end)

    local function findMyPlotRS()
        local plots=Workspace:FindFirstChild("Plots"); if not plots then return nil end
        for _,plot in ipairs(plots:GetChildren()) do
            if Synchronizer_rs then local ok,ch=pcall(function() return Synchronizer_rs:Get(plot.Name) end)
                if ok and ch then local owner=ch:Get("Owner")
                    if (typeof(owner)=="Instance" and owner==player) or (typeof(owner)=="table" and owner.UserId==player.UserId) then return plot end
                end
            end
            local sign=plot:FindFirstChild("PlotSign"); if sign then local sg=sign:FindFirstChildWhichIsA("SurfaceGui",true)
                if sg then local lbl=sg:FindFirstChildWhichIsA("TextLabel",true)
                    if lbl then local t=lbl.Text:lower(); if t:find(player.Name:lower(),1,true) or t:find(player.DisplayName:lower(),1,true) then return plot end end
                end
            end
        end; return nil
    end

    remoteSellGui=Instance.new("ScreenGui"); remoteSellGui.Name="SXE_RemoteSell"; remoteSellGui.ResetOnSpawn=false; remoteSellGui.Parent=playerGui
    local rsFrame=Instance.new("Frame", registerScreenGui(remoteSellGui)); rsFrame.Size=UDim2.new(0,190,0,240)
    rsFrame.Position=UDim2.new(0,350,1,-350); rsFrame.BackgroundColor3=Theme.MainBackground; rsFrame.BackgroundTransparency=0.06; rsFrame.BorderSizePixel=0
    Instance.new("UICorner",rsFrame).CornerRadius=UDim.new(0,12)
    local rsStroke=Instance.new("UIStroke",rsFrame); rsStroke.Color=Theme.AccentLight; rsStroke.Thickness=1.25; rsStroke.Transparency=0.08
    applySavedPosition("Remote Sell", rsFrame)

    local rsHeader=Instance.new("Frame",rsFrame); rsHeader.Size=UDim2.new(1,0,0,30); rsHeader.BackgroundTransparency=1; rsHeader.Active=true
    local rsTitle=Instance.new("TextLabel",rsHeader); rsTitle.Size=UDim2.new(1,-20,0,30); rsTitle.Position=UDim2.new(0,10,0,5)
    rsTitle.BackgroundTransparency=1; rsTitle.Text="Remote Sell"; rsTitle.Font=Enum.Font.GothamBlack; rsTitle.TextSize=13; rsTitle.TextColor3=Theme.Text; rsTitle.TextXAlignment=Enum.TextXAlignment.Left
    
    makeDraggable(rsFrame, rsHeader, "Remote Sell")

    local rsSellAll=Instance.new("TextButton",rsFrame); rsSellAll.Size=UDim2.new(1,-18,0,28); rsSellAll.Position=UDim2.new(0,9,0,38)
    rsSellAll.BackgroundColor3=Theme.Accent; rsSellAll.Text="Proximity sell"; rsSellAll.TextColor3=Color3.new(1,1,1); rsSellAll.Font=Enum.Font.GothamBlack; rsSellAll.TextSize=12; rsSellAll.BorderSizePixel=0
    Instance.new("UICorner",rsSellAll).CornerRadius=UDim.new(0,8)

    local rsStatus=Instance.new("TextLabel",rsFrame); rsStatus.Size=UDim2.new(1,-18,0,14); rsStatus.Position=UDim2.new(0,9,0,72)
    rsStatus.BackgroundTransparency=1; rsStatus.Text="Waiting for scan..."; rsStatus.TextColor3=Theme.Dim; rsStatus.Font=Enum.Font.Gotham; rsStatus.TextSize=10; rsStatus.TextXAlignment=Enum.TextXAlignment.Left

    local rsScroll=Instance.new("ScrollingFrame",rsFrame); rsScroll.Size=UDim2.new(1,-18,1,-102); rsScroll.Position=UDim2.new(0,9,0,92)
    rsScroll.BackgroundColor3=Theme.Panel; rsScroll.BorderSizePixel=0; rsScroll.ScrollBarThickness=3; rsScroll.ScrollBarImageColor3=Theme.Accent; rsScroll.Active=true
    Instance.new("UICorner",rsScroll).CornerRadius=UDim.new(0,8)
    local rsLayout=Instance.new("UIListLayout",rsScroll); rsLayout.Padding=UDim.new(0,4); rsLayout.SortOrder=Enum.SortOrder.LayoutOrder
    rsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() rsScroll.CanvasSize=UDim2.new(0,0,0,rsLayout.AbsoluteContentSize.Y+8) end)

    local lastScanData = {}
    local allSellRows = {}
    local sellingAll = false

    local function doScan()
        if sellingAll then return end
        local plot = findMyPlotRS()
        if not plot then
            if rsStatus.Text ~= "No base found" then
                for _, ch in ipairs(rsScroll:GetChildren()) do if not ch:IsA("UIListLayout") then ch:Destroy() end end
                allSellRows = {}
                lastScanData = {}
                rsStatus.Text = "No base found"
            end
            return
        end
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if not podiums then
            if rsStatus.Text ~= "No podiums" then
                for _, ch in ipairs(rsScroll:GetChildren()) do if not ch:IsA("UIListLayout") then ch:Destroy() end end
                allSellRows = {}
                lastScanData = {}
                rsStatus.Text = "No podiums"
            end
            return
        end

        local scanData = {}
        for _, podium in ipairs(podiums:GetChildren()) do
            local podiumNum = tonumber(podium.Name)
            if podiumNum then
                local base = podium:FindFirstChild("Base")
                local spawn_p = base and base:FindFirstChild("Spawn")
                local att = spawn_p and spawn_p:FindFirstChild("PromptAttachment")
                if att then
                    for _, pp in ipairs(att:GetChildren()) do
                        if pp:IsA("ProximityPrompt") and (pp.ActionText or ""):sub(1, 4) == "Sell" and pp.Enabled then
                            local name = "Slot " .. podiumNum
                            if Synchronizer_rs and AnimalsData_rs then
                                pcall(function()
                                    local ch = Synchronizer_rs:Get(plot.Name)
                                    if ch then
                                        local al = ch:Get("AnimalList")
                                        if al then
                                            local entry = al[podiumNum] or al[tostring(podiumNum)]
                                            if type(entry) == "table" and entry.Index then
                                                local info = AnimalsData_rs[entry.Index]
                                                name = (info and info.DisplayName) or entry.Index
                                            end
                                        end
                                    end
                                end)
                            end
                            table.insert(scanData, {
                                num = podiumNum,
                                prompt = pp,
                                name = name
                            })
                        end
                    end
                end
            end
        end
        table.sort(scanData, function(a, b) return a.num < b.num end)

        local changed = false
        if #scanData ~= #lastScanData then
            changed = true
        else
            for idx, item in ipairs(scanData) do
                local prev = lastScanData[idx]
                if prev.num ~= item.num or prev.prompt ~= item.prompt or prev.name ~= item.name then
                    changed = true
                    break
                end
            end
        end

        if changed then
            for _, ch in ipairs(rsScroll:GetChildren()) do if not ch:IsA("UIListLayout") then ch:Destroy() end end
            allSellRows = {}
            for _, item in ipairs(scanData) do
                local row = Instance.new("Frame", rsScroll)
                row.Size = UDim2.new(1, -8, 0, 30)
                row.BackgroundColor3 = Theme.Row
                row.BorderSizePixel = 0
                row.LayoutOrder = item.num
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

                local nl = Instance.new("TextLabel", row)
                nl.Size = UDim2.new(1, -60, 1, 0)
                nl.Position = UDim2.new(0, 8, 0, 0)
                nl.BackgroundTransparency = 1
                nl.Text = item.name
                nl.Font = Enum.Font.GothamBold
                nl.TextSize = 10
                nl.TextColor3 = Theme.Text
                nl.TextXAlignment = Enum.TextXAlignment.Left
                nl.TextTruncate = Enum.TextTruncate.AtEnd
                nl.Parent = row

                local sb = Instance.new("TextButton", row)
                sb.Size = UDim2.new(0, 44, 0, 22)
                sb.Position = UDim2.new(1, -50, 0.5, -11)
                sb.BackgroundColor3 = Theme.Accent
                sb.Text = "SELL"
                sb.TextColor3 = Color3.new(1, 1, 1)
                sb.Font = Enum.Font.GothamBlack
                sb.TextSize = 10
                sb.BorderSizePixel = 0
                Instance.new("UICorner", sb).CornerRadius = UDim.new(0, 6)
                sb.Parent = row

                local prompt = item.prompt
                local function doSell()
                    pcall(function() fireproximityprompt(prompt) end)
                    sb.Text = "✔"
                    sb.BackgroundColor3 = Theme.Green
                    task.delay(0.5, function()
                        if row.Parent then
                            row:Destroy()
                        end
                    end)
                end
                sb.MouseButton1Click:Connect(doSell)
                table.insert(allSellRows, { fn = doSell, prompt = prompt })
            end
            lastScanData = scanData
        end

        local found = #scanData
        rsStatus.Text = (found == 0 and "Nothing to sell") or (found .. " brainrot(s) ready")
    end

    -- scan happens automatically every 0.3 seconds
    rsSellAll.MouseButton1Click:Connect(function()
        if sellingAll then return end
        sellingAll = true
        rsSellAll.Text="Selling..."
        task.spawn(function()
            local plot = findMyPlotRS()
            if plot then
                local podiums = plot:FindFirstChild("AnimalPodiums")
                if podiums then
                    local prompts = {}
                    for _, podium in ipairs(podiums:GetChildren()) do
                        local base = podium:FindFirstChild("Base")
                        local spawn_p = base and base:FindFirstChild("Spawn")
                        local att = spawn_p and spawn_p:FindFirstChild("PromptAttachment")
                        if att then
                            for _, pp in ipairs(att:GetChildren()) do
                                if pp:IsA("ProximityPrompt") and (pp.ActionText or ""):sub(1, 4) == "Sell" and pp.Enabled then
                                    table.insert(prompts, pp)
                                end
                            end
                        end
                    end
                    for _, prompt in ipairs(prompts) do
                        if prompt and prompt.Parent then
                            pcall(function() fireproximityprompt(prompt) end)
                            task.wait(0.08)
                        end
                    end
                end
            end
            task.wait(0.3)
            rsSellAll.Text="SELL ALL"
            sellingAll = false
            pcall(doScan)
        end)
    end)

    -- Auto scan loop (every 0.3s)
    task.spawn(function()
        while remoteSellGui and remoteSellGui.Parent do
            task.wait(0.3)
            if remoteSellGui.Enabled then
                pcall(doScan)
            end
        end
    end)
end

_G.toggleRemoteSell=function(enabled) Config.RemoteSellEnabled=enabled; saveConfig()
    if enabled then buildRemoteSell(); if remoteSellGui then remoteSellGui.Enabled=true end
    else if remoteSellGui then remoteSellGui.Enabled=false end end
end
end) -- END REMOTE SELL SCOPE

-- ============================================================
-- GUI HELPERS
-- ============================================================
main,mainBody,tabBar,bottomBar,fpsText = nil,nil,nil,nil,nil
panels,panelSetters,tabButtons={},{},{}
actionSettingsPanel,actionSettingsBody,tpSpeedSettingsPanel,tpSpeedSettingsBody = nil,nil,nil,nil
BoundToggles={}

stealProgressBarGui = nil

-- Pre-declare helper functions made global to free local registers in outer scope

_G.ShowStealProgressBar = function(targetName, duration)
    local ExploitGui = (gethui and gethui()) or game:GetService("CoreGui")
    
    if stealProgressBarGui then
        pcall(function() stealProgressBarGui:Destroy() end)
    end
    
    local sg = Instance.new("ScreenGui")
    sg.Name = "SXE_StealProgressBar"
    sg.ResetOnSpawn = false
    sg.Parent = ExploitGui
    stealProgressBarGui = sg
    
    local barWidth = 270
    local barHeight = 50
    
    local container = Instance.new("Frame")
    container.Size = UDim2.fromOffset(barWidth, barHeight)
    container.Position = UDim2.new(0.5, -barWidth/2, 1, -190)
    container.BackgroundColor3 = Theme.Background
    container.BackgroundTransparency = 0.02
    container.BorderSizePixel = 0
    container.Parent = registerScreenGui(sg)
    corner(container, 12)
    addOutline(container)
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.6, -14, 0, 16)
    title.Position = UDim2.new(0, 14, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = "⚡ STEALING: " .. (targetName or "Brainrot"):upper()
    title.TextColor3 = Theme.Text
    title.Font = Enum.Font.GothamBold
    title.TextSize = 9.5
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = container
    
    local pctLabel = Instance.new("TextLabel")
    pctLabel.Size = UDim2.new(0.4, -14, 0, 16)
    pctLabel.Position = UDim2.new(0.6, 0, 0, 8)
    pctLabel.BackgroundTransparency = 1
    pctLabel.Text = "0%"
    pctLabel.TextColor3 = Theme.AccentLight
    pctLabel.Font = Enum.Font.GothamBold
    pctLabel.TextSize = 10
    pctLabel.TextXAlignment = Enum.TextXAlignment.Right
    pctLabel.Parent = container
    
    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, -28, 0, 6)
    track.Position = UDim2.new(0, 14, 0, 30)
    track.BackgroundColor3 = Theme.SliderBg
    track.BorderSizePixel = 0
    track.Parent = container
    corner(track, 3)
    stroke(track, Theme.Stroke, 1, 0.1)
    
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.BackgroundColor3 = Theme.Accent
    fill.BorderSizePixel = 0
    fill.Parent = track
    corner(fill, 3)
    
    local fillGrad = Instance.new("UIGradient", fill)
    fillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.AccentLight),
        ColorSequenceKeypoint.new(1, Theme.Accent)
    })
    
    local safeDuration = tonumber(duration) or 5
    if safeDuration <= 0.01 then safeDuration = 5 end
    local startTick = tick()
    
    task.spawn(function()
        while sg and sg.Parent do
            local elapsed = tick() - startTick
            local t = math.clamp(elapsed / safeDuration, 0, 1)
            local ratio = 1 - (1 - t)^3
            
            pcall(function()
                pctLabel.Text = math.floor(ratio * 100) .. "%"
                fill.Size = UDim2.new(ratio, 0, 1, 0)
            end)
            
            if t >= 1 then break end
            task.wait()
        end
    end)
end

_G.HideStealProgressBar = function()
    local targetGui = stealProgressBarGui
    if targetGui then
        stealProgressBarGui = nil
        pcall(function()
            local container = targetGui:FindFirstChildWhichIsA("Frame")
            if container then
                tw(container, {BackgroundTransparency = 1}, 0.15)
                for _, child in ipairs(container:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        tw(child, {TextTransparency = 1}, 0.15)
                    elseif child:IsA("Frame") then
                        tw(child, {BackgroundTransparency = 1}, 0.15)
                    elseif child:IsA("UIStroke") then
                        tw(child, {Transparency = 1}, 0.15)
                    end
                end
                task.wait(0.16)
            end
            targetGui:Destroy()
        end)
    end
end

-- Assign helper implementations to pre-declared outer local variables
corner = function(o,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=o; return c end
stroke = function(o,col,th,tr) local s=Instance.new("UIStroke"); s.Color=col or Theme.Stroke; s.Thickness=th or 1; s.Transparency=tr or 0; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=o; return s end
tw = function(o,p,t) TweenService:Create(o,TweenInfo.new(t or 0.14,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),p):Play() end
addOutline = function(f)
    local o=Instance.new("UIStroke"); o.Color=Theme.AccentLight; o.Thickness=1.25; o.Transparency=Theme.OutlineTransparency or 0.08; o.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; o.Parent=f
    if Theme.CornerAccents then
        local glow=Instance.new("UIStroke"); glow.Name="CyberGlow"; glow.Color=Theme.Accent; glow.Thickness=3; glow.Transparency=0.78; glow.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; glow.Parent=f
    end
    return o
end
addCyberCorners = function(f)
    if not Theme.CornerAccents then return end
    local L,TH,col = 20,2.5,Theme.Accent
    local function seg(pos,size)
        local s=Instance.new("Frame"); s.Name="CyberCorner"; s.BorderSizePixel=0; s.BackgroundColor3=col; s.Position=pos; s.Size=size; s.ZIndex=5; s.Parent=f; return s
    end
    seg(UDim2.new(0,0,0,0), UDim2.new(0,L,0,TH))
    seg(UDim2.new(0,0,0,0), UDim2.new(0,TH,0,L))
    seg(UDim2.new(1,-L,0,0), UDim2.new(0,L,0,TH))
    seg(UDim2.new(1,-TH,0,0), UDim2.new(0,TH,0,L))
    seg(UDim2.new(0,0,1,-TH), UDim2.new(0,L,0,TH))
    seg(UDim2.new(0,0,1,-L), UDim2.new(0,TH,0,L))
    seg(UDim2.new(1,-L,1,-TH), UDim2.new(0,L,0,TH))
    seg(UDim2.new(1,-TH,1,-L), UDim2.new(0,TH,0,L))
end
addCyberGradient = function(f)
    if not Theme.CornerAccents then return end
    local grad=Instance.new("UIGradient")
    grad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(255,255,255)),ColorSequenceKeypoint.new(1,Color3.fromRGB(150,150,165))})
    grad.Rotation=90
    grad.Parent=f
end
function clearBody(body) for _,c in ipairs(body:GetChildren()) do if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end end end

function openAnim(f) if not f then return end; local us=f:FindFirstChild("SXEScale") or Instance.new("UIScale"); us.Name="SXEScale"; us.Parent=f
    local tgt=f.Position; f.Visible=true; us.Scale=0.92; f.Position=UDim2.new(tgt.X.Scale,tgt.X.Offset,tgt.Y.Scale,tgt.Y.Offset+18); tw(us,{Scale=1},0.20); tw(f,{Position=tgt},0.20) end
function closeAnim(f) if not f then return end; f.Visible = false end

makeDraggable = function(frame,handle,saveName) local dragging,dragStart,startPos=false,nil,nil
    handle.InputBegan:Connect(function(i) if UI.Locked then return end; if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; dragStart=i.Position; startPos=frame.Position end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then if dragging and saveName then rememberPosition(saveName,frame) end; dragging=false end end)
    UIS.InputChanged:Connect(function(i) if dragging and not UI.Locked and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dragStart
        local scale = getGlobalScale()
        frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+(d.X/scale),startPos.Y.Scale,startPos.Y.Offset+(d.Y/scale))
    end end)
end

makeResizable = function(frame, minSize, panelName)
    local h = Instance.new("TextButton")
    h.Size = UDim2.new(0, 16, 0, 16)
    h.Position = UDim2.new(1, -16, 1, -16)
    h.BackgroundTransparency = 1
    h.Text = "◢"
    h.TextColor3 = Theme.AccentLight or Color3.new(1, 1, 1)
    h.TextSize = 12
    h.ZIndex = 100
    h.Parent = frame
    local dragging, dragStart, startSize = false, nil, nil
    h.InputBegan:Connect(function(i)
        if UI.Locked then return end
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = i.Position; startSize = frame.AbsoluteSize
        end
    end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if dragging then
                dragging = false
                if panelName then
                    if not Config.sizes then Config.sizes = {} end
                    Config.sizes[panelName] = {x = frame.Size.X.Offset, y = frame.Size.Y.Offset}
                    saveConfig()
                end
            end
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dragging and not UI.Locked and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - dragStart
            local scale = getGlobalScale()
            local nx = math.max(minSize.X.Offset, startSize.X + (d.X / scale))
            local ny = math.max(minSize.Y.Offset, startSize.Y + (d.Y / scale))
            frame.Size = UDim2.new(0, nx, 0, ny)
        end
    end)
end

local function makeTwoToneRow(h, str, y, size, headColor, leftOffset)
    leftOffset = leftOffset or 0
    local head, tail = str:match("^(.-)%s+(%S+)$")
    local row=Instance.new("Frame"); row.Name="TwoToneTitle"; row.BackgroundTransparency=1; row.Size=UDim2.new(1,-65-leftOffset,0,size+4); row.Position=UDim2.new(0,25+leftOffset,0,y); row.Parent=h
    local lay=Instance.new("UIListLayout"); lay.FillDirection=Enum.FillDirection.Horizontal; lay.VerticalAlignment=Enum.VerticalAlignment.Center; lay.SortOrder=Enum.SortOrder.LayoutOrder; lay.Parent=row
    if head and head ~= "" then
        local l1=Instance.new("TextLabel"); l1.LayoutOrder=1; l1.AutomaticSize=Enum.AutomaticSize.X; l1.Size=UDim2.new(0,0,1,0); l1.BackgroundTransparency=1; l1.Text=head.." "; l1.TextColor3=headColor; l1.Font=Enum.Font.GothamBlack; l1.TextSize=size; l1.TextXAlignment=Enum.TextXAlignment.Left; l1.Parent=row
        local l2=Instance.new("TextLabel"); l2.LayoutOrder=2; l2.AutomaticSize=Enum.AutomaticSize.X; l2.Size=UDim2.new(0,0,1,0); l2.BackgroundTransparency=1; l2.Text=tail; l2.TextColor3=Theme.Accent; l2.Font=Enum.Font.GothamBlack; l2.TextSize=size; l2.TextXAlignment=Enum.TextXAlignment.Left; l2.Parent=row
    else
        local l1=Instance.new("TextLabel"); l1.Size=UDim2.new(1,0,1,0); l1.BackgroundTransparency=1; l1.Text=str; l1.TextColor3=headColor; l1.Font=Enum.Font.GothamBlack; l1.TextSize=size; l1.TextXAlignment=Enum.TextXAlignment.Left; l1.Parent=row
    end
end

-- Bandeau d'image plein-hauteur sur le cote gauche du panneau, meme esprit/meme image
-- que le panneau "Vampire" de reference (photo + degrade + nom en bas). Cree une seule
-- fois par panneau (dans makeQuickPanel/makeMainPanel), pas par makeHeader puisqu'elle
-- doit couvrir toute la hauteur, pas juste la bande d'en-tete.
local ART_WIDTH = 84
local function makeArtHolder(f, label)
    local holder=Instance.new("Frame"); holder.Name="ArtHolder"; holder.Size=UDim2.new(0,ART_WIDTH-8,1,-16); holder.Position=UDim2.new(0,8,0,8); holder.BackgroundColor3=Theme.Panel; holder.ClipsDescendants=true; holder.Parent=f; corner(holder,10)
    local img=Instance.new("ImageLabel"); img.Size=UDim2.new(1,0,1,0); img.BackgroundTransparency=1; img.Image="rbxassetid://93377284283454"; img.ScaleType=Enum.ScaleType.Crop; img.Parent=holder
    local grad=Instance.new("Frame"); grad.Size=UDim2.new(1,0,0,40); grad.Position=UDim2.new(0,0,1,-40); grad.BackgroundColor3=Theme.Panel; grad.BorderSizePixel=0; grad.ZIndex=3; grad.Parent=holder
    local ug=Instance.new("UIGradient"); ug.Rotation=90; ug.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(0.15,0),NumberSequenceKeypoint.new(1,0)}); ug.Parent=grad
    local nameLbl=Instance.new("TextLabel"); nameLbl.Size=UDim2.new(1,0,0,16); nameLbl.Position=UDim2.new(0,0,1,-18); nameLbl.BackgroundTransparency=1; nameLbl.Text=(label or ""):upper(); nameLbl.TextColor3=Theme.Text; nameLbl.Font=Enum.Font.GothamBold; nameLbl.TextSize=10; nameLbl.ZIndex=4; nameLbl.Parent=holder
    return holder
end

function makeHeader(f,t,isMain,leftOffset) leftOffset = leftOffset or 0
    local h=Instance.new("Frame"); h.Size=UDim2.new(1,-leftOffset,0,42); h.Position=UDim2.new(0,leftOffset,0,0); h.BackgroundTransparency=1; h.Parent=f
    local parts={}; for s in string.gmatch(t,"([^\n]+)") do table.insert(parts,s) end
    local dot=Instance.new("Frame"); dot.Size=UDim2.new(0,7,0,7); dot.Position=UDim2.new(0,13,0,isMain and 17 or 20); dot.BackgroundColor3=Theme.Accent; dot.BorderSizePixel=0; dot.Parent=h; corner(dot,10)
    local minIcon=Instance.new("TextLabel"); minIcon.Size=UDim2.new(0,16,0,16); minIcon.Position=UDim2.new(1,-24,0,isMain and 12 or 10); minIcon.BackgroundTransparency=1; minIcon.Text="-"; minIcon.TextColor3=Theme.Dim; minIcon.Font=Enum.Font.GothamBold; minIcon.TextSize=16; minIcon.Parent=h
    if isMain then
        local lockIcon=Instance.new("Frame"); lockIcon.Size=UDim2.new(0,18,0,18); lockIcon.Position=UDim2.new(1,-58,0,11); lockIcon.BackgroundTransparency=1; lockIcon.Parent=h
        local lockBody=Instance.new("Frame"); lockBody.Size=UDim2.new(0,12,0,8); lockBody.Position=UDim2.new(0.5,-6,1,-8); lockBody.BackgroundColor3=Theme.Accent; lockBody.BorderSizePixel=0; lockBody.Parent=lockIcon; corner(lockBody,2)
        local lockShackle=Instance.new("Frame"); lockShackle.Size=UDim2.new(0,8,0,7); lockShackle.Position=UDim2.new(0.5,-4,1,-14); lockShackle.BackgroundTransparency=1; lockShackle.Parent=lockIcon
        stroke(lockShackle, Theme.Accent, 1.5, 0); local sc=Instance.new("UICorner"); sc.CornerRadius=UDim.new(1,0); sc.Parent=lockShackle
        local lockMask=Instance.new("Frame"); lockMask.Size=UDim2.new(1,0,0,4); lockMask.Position=UDim2.new(0,0,1,-4); lockMask.BackgroundColor3=Theme.MainBackground; lockMask.BorderSizePixel=0; lockMask.ZIndex=2; lockMask.Parent=lockShackle
        local closeBtn=Instance.new("TextButton"); closeBtn.Name="WhiteTextBtn"; closeBtn.Size=UDim2.new(0,20,0,20); closeBtn.Position=UDim2.new(1,-30,0,10); closeBtn.BackgroundColor3=Theme.SoftAccent; closeBtn.Text="X"; closeBtn.TextColor3=Theme.Text; closeBtn.Font=Enum.Font.GothamBold; closeBtn.TextSize=11; closeBtn.AutoButtonColor=false; closeBtn.Parent=h; corner(closeBtn,6)
        closeBtn.MouseButton1Click:Connect(function() f.Visible=false end)
        minIcon.Visible=false
        makeTwoToneRow(h, parts[1] or "IDF HUB PRIVAT", 8, 16, Theme.Text, 0)
    else
        local brand=Instance.new("TextLabel"); brand.Size=UDim2.new(1,-58,0,11); brand.Position=UDim2.new(0,25,0,4); brand.BackgroundTransparency=1; brand.Text=parts[1] or "IDF HUB PRIVAT"; brand.TextColor3=Theme.Dim; brand.Font=Enum.Font.GothamMedium; brand.TextSize=8; brand.TextXAlignment=Enum.TextXAlignment.Left; brand.Parent=h
        makeTwoToneRow(h, parts[2] or "", 15, 14, Theme.Text, 0)
    end
    local d=Instance.new("Frame"); d.Size=UDim2.new(1,-24,0,1); d.Position=UDim2.new(0,12,0,40); d.BackgroundColor3=Theme.AccentLight; d.BackgroundTransparency=isMain and 0.25 or 0.04; d.BorderSizePixel=0; d.Parent=h
    makeDraggable(f,h,t); return h end

function makeMainPanel(t,size,pos) local f=Instance.new("Frame"); f.Size=size; f.Position=pos; f.BackgroundColor3=Theme.MainBackground; f.BackgroundTransparency=0.06; f.BorderSizePixel=0; f.ClipsDescendants=true; f.Parent=gui; corner(f,12); addOutline(f); addCyberCorners(f); addCyberGradient(f)
    local mpParts={}; for s in string.gmatch(t,"([^\n]+)") do table.insert(mpParts,s) end
    makeArtHolder(f, mpParts[#mpParts] or "HUB")
    makeHeader(f,t,true,ART_WIDTH)
    local body=Instance.new("ScrollingFrame"); body.Size=UDim2.new(1,-(ART_WIDTH+18),1,-82); body.Position=UDim2.new(0,ART_WIDTH+6,0,76); body.BackgroundTransparency=1; body.BorderSizePixel=0; body.ScrollBarThickness=3; body.ScrollBarImageColor3=Theme.Accent; body.CanvasSize=UDim2.new(0,0,0,0); body.Active=true; body.Parent=f
    local lay=Instance.new("UIListLayout"); lay.Padding=UDim.new(0,6); lay.Parent=body
    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() body.CanvasSize=UDim2.new(0,0,0,lay.AbsoluteContentSize.Y+10) end);
    if Config.sizes and Config.sizes[t] then f.Size = UDim2.new(0, Config.sizes[t].x, 0, Config.sizes[t].y) end
    makeResizable(f, UDim2.new(0, 200, 0, 150), t); return f,body end

function makeQuickPanel(t,size,pos) local f=Instance.new("Frame"); f.Size=size; f.Position=pos; f.BackgroundColor3=Theme.Background; f.BackgroundTransparency=0.04; f.BorderSizePixel=0; f.ClipsDescendants=true; f.Parent=gui; corner(f,12); addOutline(f); addCyberCorners(f); addCyberGradient(f)
    local qpParts={}; for s in string.gmatch(t,"([^\n]+)") do table.insert(qpParts,s) end
    makeArtHolder(f, qpParts[#qpParts] or "HUB")
    makeHeader(f,t,false,ART_WIDTH)
    local body=Instance.new("ScrollingFrame"); body.Size=UDim2.new(1,-(ART_WIDTH+18),1,-50); body.Position=UDim2.new(0,ART_WIDTH+6,0,46); body.BackgroundTransparency=1; body.BorderSizePixel=0; body.ScrollBarThickness=3; body.ScrollBarImageColor3=Theme.Accent; body.CanvasSize=UDim2.new(0,0,0,0); body.Active=true; body.Parent=f
    local lay=Instance.new("UIListLayout"); lay.Padding=UDim.new(0,6); lay.Parent=body
    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() body.CanvasSize=UDim2.new(0,0,0,lay.AbsoluteContentSize.Y+10) end);
    if Config.sizes and Config.sizes[t] then f.Size = UDim2.new(0, Config.sizes[t].x, 0, Config.sizes[t].y) end
    if not string.find(t, "Admin Command Panel") then makeResizable(f, UDim2.new(0, 150, 0, 150), t) end; return f,body end

function makeSyncStateRow(parent,text,toggleName,callback)
    regToggle(toggleName,getToggle(toggleName))
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,34); row.BackgroundColor3=Theme.Panel; row.BackgroundTransparency=0.18; row.Parent=parent; corner(row,6)
    local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,3,0,16); bar.Position=UDim2.new(0,0,0.5,-8); bar.BackgroundColor3=Theme.Accent; bar.BorderSizePixel=0; bar.Parent=row; corner(bar,2)
    local label=Instance.new("TextLabel"); label.Size=UDim2.new(1,-62,1,0); label.Position=UDim2.new(0,14,0,0); label.BackgroundTransparency=1; label.Text="\226\150\170 "..text:upper(); label.TextColor3=Theme.Text; label.Font=Enum.Font.GothamSemibold; label.TextSize=12; label.TextXAlignment=Enum.TextXAlignment.Left; label.TextTruncate=Enum.TextTruncate.AtEnd; label.Parent=row
    local btn=Instance.new("TextButton"); btn.Name="WhiteTextBtn"; btn.Size=UDim2.new(0,38,0,21); btn.Position=UDim2.new(1,-42,0.5,-10.5); btn.Text=""; btn.AutoButtonColor=false; btn.Parent=row; corner(btn,20)
    local dot=Instance.new("Frame"); dot.Name="WhiteSliderKnob"; dot.Size=UDim2.new(0,16,0,16); dot.BackgroundColor3=Color3.new(1,1,1); dot.BorderSizePixel=0; dot.Parent=btn; corner(dot,20)
    local function refresh(val)
        tw(btn,{BackgroundColor3=val and Theme.Green or Theme.ToggleOff2},0.12)
        tw(dot,{Position=val and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)},0.12)
    end
    btn.BackgroundColor3 = getToggle(toggleName) and Theme.Green or Theme.ToggleOff2
    dot.Position = getToggle(toggleName) and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)
    onToggleChanged(toggleName,function(val) refresh(val) end)
    btn.MouseButton1Click:Connect(function() local nv=not getToggle(toggleName); setToggle(toggleName,nv); if callback then callback(nv) end end)
    return function(ns,fire) if typeof(ns)=="boolean" then setToggle(toggleName,ns); if fire~=false and callback then callback(ns) end end end, label
end

function makeSyncMainToggle(parent,text,toggleName,callback)
    regToggle(toggleName,getToggle(toggleName))
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,31); row.BackgroundColor3=Theme.Panel; row.BackgroundTransparency=0.18; row.Parent=parent; corner(row,6)
    local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,3,0,16); bar.Position=UDim2.new(0,0,0.5,-8); bar.BackgroundColor3=Theme.Accent; bar.BorderSizePixel=0; bar.Parent=row; corner(bar,2)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-62,1,0); l.Position=UDim2.new(0,14,0,0); l.BackgroundTransparency=1; l.Text="\226\150\170 "..text:upper(); l.TextColor3=Theme.Text; l.Font=Enum.Font.GothamMedium; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=row
    local toggle=Instance.new("TextButton"); toggle.Size=UDim2.new(0,38,0,21); toggle.Position=UDim2.new(1,-44,0.5,-10.5); toggle.Text=""; toggle.AutoButtonColor=false; toggle.Parent=row; corner(toggle,20)
    local dot=Instance.new("Frame"); dot.Name="WhiteSliderKnob"; dot.Size=UDim2.new(0,16,0,16); dot.BackgroundColor3=Color3.new(1,1,1); dot.BorderSizePixel=0; dot.Parent=toggle; corner(dot,20)
    local function refresh(val) tw(toggle,{BackgroundColor3=val and Theme.Green or Theme.ToggleOff},0.12); tw(dot,{Position=val and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)},0.12) end
    refresh(getToggle(toggleName)); dot.Position=getToggle(toggleName) and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)
    toggle.BackgroundColor3=getToggle(toggleName) and Theme.Green or Theme.ToggleOff
    onToggleChanged(toggleName,function(val) refresh(val) end)
    toggle.MouseButton1Click:Connect(function() local nv=not getToggle(toggleName); setToggle(toggleName,nv); if callback then callback(nv) end end)
    BoundToggles[text]=function(ns,fire) if typeof(ns)=="boolean" then setToggle(toggleName,ns); if fire~=false and callback then callback(ns) end end end
    return BoundToggles[text]
end

function makeQuickButton(parent,text,callback,bg) local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-4,0,36); b.BackgroundColor3=bg or Theme.SoftButton; b.BackgroundTransparency=0.02; b.Text=text; b.TextColor3=Theme.Text; b.Font=Enum.Font.GothamBold; b.TextSize=13; b.AutoButtonColor=false; b.Parent=parent; corner(b,6)
    b.MouseEnter:Connect(function() tw(b,{BackgroundColor3=bg or Theme.SoftButtonHover},0.12) end); b.MouseLeave:Connect(function() tw(b,{BackgroundColor3=bg or Theme.SoftButton},0.12) end)
    b.MouseButton1Click:Connect(function() if callback then callback() end end); return b end

function makeQuickSlider(parent,text,min,max,default,callback,suffix)
    local holder=Instance.new("Frame"); holder.Size=UDim2.new(1,-4,0,66); holder.BackgroundTransparency=1; holder.Parent=parent

    local labelRow=Instance.new("Frame"); labelRow.Size=UDim2.new(1,0,0,31); labelRow.BackgroundColor3=Theme.Panel; labelRow.BackgroundTransparency=0.18; labelRow.Position=UDim2.new(0,0,0,0); labelRow.Parent=holder; corner(labelRow,6)
    local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,3,0,16); bar.Position=UDim2.new(0,0,0.5,-8); bar.BackgroundColor3=Theme.Accent; bar.BorderSizePixel=0; bar.Parent=labelRow; corner(bar,2)
    local label=Instance.new("TextLabel"); label.Size=UDim2.new(1,-20,1,0); label.Position=UDim2.new(0,14,0,0); label.BackgroundTransparency=1; label.Text="\226\150\170 "..text:upper(); label.TextColor3=Theme.Text; label.Font=Enum.Font.GothamMedium; label.TextSize=10; label.TextXAlignment=Enum.TextXAlignment.Left; label.Parent=labelRow

    local stepRow=Instance.new("Frame"); stepRow.Size=UDim2.new(1,0,0,30); stepRow.Position=UDim2.new(0,0,0,36); stepRow.BackgroundColor3=Theme.InputBg; stepRow.BackgroundTransparency=0.1; stepRow.Parent=holder; corner(stepRow,6)

    local minusBtn=Instance.new("TextButton"); minusBtn.Name="WhiteTextBtn"; minusBtn.Size=UDim2.new(0,30,1,0); minusBtn.Position=UDim2.new(0,0,0,0); minusBtn.BackgroundTransparency=1; minusBtn.Text="-"; minusBtn.TextColor3=Theme.Dim; minusBtn.Font=Enum.Font.GothamBold; minusBtn.TextSize=16; minusBtn.AutoButtonColor=false; minusBtn.Parent=stepRow

    local valLabel=Instance.new("TextLabel"); valLabel.Size=UDim2.new(1,-60,1,0); valLabel.Position=UDim2.new(0,30,0,0); valLabel.BackgroundTransparency=1; valLabel.Text=tostring(default)..(suffix or ""); valLabel.TextColor3=Theme.Accent; valLabel.Font=Enum.Font.GothamBold; valLabel.TextSize=12; valLabel.TextXAlignment=Enum.TextXAlignment.Center; valLabel.Parent=stepRow

    local plusBtn=Instance.new("TextButton"); plusBtn.Name="WhiteTextBtn"; plusBtn.Size=UDim2.new(0,30,1,0); plusBtn.Position=UDim2.new(1,-30,0,0); plusBtn.BackgroundTransparency=1; plusBtn.Text="+"; plusBtn.TextColor3=Theme.Dim; plusBtn.Font=Enum.Font.GothamBold; plusBtn.TextSize=16; plusBtn.AutoButtonColor=false; plusBtn.Parent=stepRow

    local step = ((max-min) >= 100) and 5 or 1
    local current = default

    local function apply(v, silent)
        current = math.clamp(math.floor(v*10+0.5)/10, min, max)
        valLabel.Text = tostring(current)..(suffix or "")
        if callback and not silent then callback(current) end
    end

    minusBtn.MouseButton1Click:Connect(function() apply(current - step) end)
    plusBtn.MouseButton1Click:Connect(function() apply(current + step) end)

    return {Set = function(v, silent) apply(v, silent) end}
end

function makeMainSliderWithInput(parent,text,min,max,default,callback,suffix)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,-4,0,31)
    row.BackgroundColor3 = Theme.Panel
    row.BackgroundTransparency = 0.18
    row.Parent = parent
    corner(row, 6)

    local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,3,0,16); bar.Position=UDim2.new(0,0,0.5,-8); bar.BackgroundColor3=Theme.Accent; bar.BorderSizePixel=0; bar.Parent=row; corner(bar,2)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1,-100,1,0)
    label.Position = UDim2.new(0,14,0,0)
    label.BackgroundTransparency = 1
    label.Text = "\226\150\170 "..text:upper()
    label.TextColor3 = Theme.Text
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 10
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local box = Instance.new("TextBox")
    box.Size = UDim2.new(0,80,0,21)
    box.Position = UDim2.new(1,-88,0.5,-10.5)
    box.BackgroundColor3 = Theme.InputBg
    box.BorderSizePixel = 0
    box.Text = tostring(default)..(suffix or "")
    box.TextColor3 = Theme.Accent
    box.Font = Enum.Font.GothamBold
    box.TextSize = 11
    box.TextXAlignment = Enum.TextXAlignment.Center
    box.ClearTextOnFocus = false
    box.Parent = row
    corner(box,4)

    local function updateValue(val)
        val = math.clamp(val, min, max)
        val = math.floor(val * 100 + 0.5) / 100
        box.Text = tostring(val)..(suffix or "")
        if callback then callback(val) end
    end

    box.FocusLost:Connect(function()
        local raw = box.Text:gsub("[^%d%.]", "")
        local num = tonumber(raw)
        if num then
            updateValue(num)
        else
            box.Text = tostring(default)..(suffix or "")
        end
    end)
    return row
end

function makeMainButton(parent,text,callback,color) local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-4,0,30); b.BackgroundColor3=color or Theme.Row; b.BackgroundTransparency=0.16; b.Text=text; b.TextColor3=Theme.Text; b.Font=Enum.Font.GothamBold; b.TextSize=11; b.AutoButtonColor=false; b.Parent=parent; corner(b,6); stroke(b,Theme.AccentLight,1,0.28)
    b.MouseEnter:Connect(function() tw(b,{BackgroundColor3=color or Theme.RowHover},0.12) end); b.MouseLeave:Connect(function() tw(b,{BackgroundColor3=color or Theme.Row},0.12) end)
    b.MouseButton1Click:Connect(function() if callback then callback() end end); return b end

function makeSectionLabel(parent,text)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,22); row.BackgroundTransparency=1; row.Parent=parent
    local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(0,120,0,16); lbl.Position=UDim2.new(0.5,-60,0.5,-8); lbl.BackgroundTransparency=1; lbl.Text=text:upper(); lbl.TextColor3=Theme.Dim; lbl.Font=Enum.Font.GothamBold; lbl.TextSize=10; lbl.TextXAlignment=Enum.TextXAlignment.Center; lbl.ZIndex=2; lbl.Parent=row
    local leftLine=Instance.new("Frame"); leftLine.Size=UDim2.new(0.5,-64,0,1); leftLine.Position=UDim2.new(0,0,0.5,0); leftLine.BackgroundColor3=Theme.Stroke; leftLine.BorderSizePixel=0; leftLine.Parent=row
    local rightLine=Instance.new("Frame"); rightLine.Size=UDim2.new(0.5,-64,0,1); rightLine.Position=UDim2.new(0.5,64,0.5,0); rightLine.BackgroundColor3=Theme.Stroke; rightLine.BorderSizePixel=0; rightLine.Parent=row
    return row
end

function makeMainToggle(parent,text,enabled,callback)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,31); row.BackgroundColor3=Theme.Panel; row.BackgroundTransparency=0.18; row.Parent=parent; corner(row,6)
    local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,3,0,16); bar.Position=UDim2.new(0,0,0.5,-8); bar.BackgroundColor3=Theme.Accent; bar.BorderSizePixel=0; bar.Parent=row; corner(bar,2)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-62,1,0); l.Position=UDim2.new(0,14,0,0); l.BackgroundTransparency=1; l.Text="\226\150\170 "..text:upper(); l.TextColor3=Theme.Text; l.Font=Enum.Font.GothamMedium; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=row
    local toggle=Instance.new("TextButton"); toggle.Size=UDim2.new(0,38,0,21); toggle.Position=UDim2.new(1,-44,0.5,-10.5); toggle.BackgroundColor3=enabled and Theme.Green or Theme.ToggleOff; toggle.Text=""; toggle.AutoButtonColor=false; toggle.Parent=row; corner(toggle,20)
    local dot=Instance.new("Frame"); dot.Name="WhiteSliderKnob"; dot.Size=UDim2.new(0,16,0,16); dot.Position=enabled and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8); dot.BackgroundColor3=Color3.new(1,1,1); dot.BorderSizePixel=0; dot.Parent=toggle; corner(dot,20)
    local state=enabled
    local function setState(ns,fire) state=ns; tw(toggle,{BackgroundColor3=state and Theme.Green or Theme.ToggleOff},0.12); tw(dot,{Position=state and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)},0.12); if fire~=false and callback then callback(state) end end
    toggle.MouseButton1Click:Connect(function() setState(not state,true) end)
    BoundToggles[text]=function(ns,fire) if typeof(ns)=="boolean" then setState(ns,fire) else setState(not state,true) end end; return BoundToggles[text]
end

function makeMainTextBox(parent,text,default,placeholder,callback)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,31); row.BackgroundColor3=Theme.Panel; row.BackgroundTransparency=0.18; row.Parent=parent; corner(row,6)
    local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,3,0,16); bar.Position=UDim2.new(0,0,0.5,-8); bar.BackgroundColor3=Theme.Accent; bar.BorderSizePixel=0; bar.Parent=row; corner(bar,2)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-150,1,0); l.Position=UDim2.new(0,14,0,0); l.BackgroundTransparency=1; l.Text="\226\150\170 "..text:upper(); l.TextColor3=Theme.Text; l.Font=Enum.Font.GothamMedium; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=row
    local box=Instance.new("TextBox"); box.Size=UDim2.new(0,80,0,21); box.Position=UDim2.new(1,-136,0.5,-10.5); box.BackgroundColor3=Theme.InputBg; box.BorderSizePixel=0; box.Text=default or ""; box.PlaceholderText=placeholder or ""; box.TextColor3=Theme.Text; box.Font=Enum.Font.GothamMedium; box.TextSize=10; box.ClearTextOnFocus=false; box.Parent=row; corner(box,4)
    local applyBtn=Instance.new("TextButton"); applyBtn.Name="WhiteTextBtn"; applyBtn.Size=UDim2.new(0,48,0,21); applyBtn.Position=UDim2.new(1,-50,0.5,-10.5); applyBtn.BackgroundColor3=Theme.Accent; applyBtn.Text="APPLY"; applyBtn.TextColor3=Color3.new(1,1,1); applyBtn.Font=Enum.Font.GothamBold; applyBtn.TextSize=9; applyBtn.AutoButtonColor=false; applyBtn.Parent=row; corner(applyBtn,4)
    local function commit()
        local raw = box.Text:gsub("%s", "")
        if callback then callback(raw) end
    end
    box.FocusLost:Connect(commit)
    applyBtn.MouseButton1Click:Connect(commit)
    return box
end

function makeKeybindRow(parent,nameText)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,31); row.BackgroundColor3=Theme.Panel; row.BackgroundTransparency=0.18; row.Parent=parent; corner(row,6)
    local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,3,0,16); bar.Position=UDim2.new(0,0,0.5,-8); bar.BackgroundColor3=Theme.Accent; bar.BorderSizePixel=0; bar.Parent=row; corner(bar,2)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-96,1,0); l.Position=UDim2.new(0,14,0,0); l.BackgroundTransparency=1; l.Text="\226\150\170 "..nameText:upper(); l.TextColor3=Theme.Text; l.Font=Enum.Font.GothamSemibold; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
    local x=Instance.new("TextButton"); x.Name="WhiteTextBtn"; x.Size=UDim2.new(0,22,0,20); x.Position=UDim2.new(1,-74,0.5,-10); x.BackgroundColor3=Theme.Red; x.Text="X"; x.TextColor3=Color3.new(1,1,1); x.Font=Enum.Font.GothamBold; x.TextSize=10; x.Parent=row; corner(x,5)
    local key=Instance.new("TextButton"); key.Name="WhiteTextBtn"; key.Size=UDim2.new(0,50,0,20); key.Position=UDim2.new(1,-50,0.5,-10); key.BackgroundColor3=Theme.Accent; key.Text=Keybinds[nameText] or "NONE"; key.TextColor3=Color3.new(1,1,1); key.Font=Enum.Font.GothamBold; key.TextSize=9; key.Parent=row; corner(key,5)
    x.MouseButton1Click:Connect(function() Keybinds[nameText]="NONE"; Config.keybinds[nameText]="NONE"; saveConfig(); key.Text="NONE"; if updateMovementPanelLabels then updateMovementPanelLabels() end end)
    key.MouseButton1Click:Connect(function() key.Text="..."
        local con; con=UIS.InputBegan:Connect(function(input,gp) if gp then return end; if input.UserInputType==Enum.UserInputType.Keyboard then Keybinds[nameText]=input.KeyCode.Name; Config.keybinds[nameText]=input.KeyCode.Name; saveConfig(); key.Text=input.KeyCode.Name; if nameText=="Open Menu" then UI.OpenMenuKey=input.KeyCode end; con:Disconnect(); if updateMovementPanelLabels then updateMovementPanelLabels() end end end)
    end)
end

-- CREATE PANELS
main,mainBody=makeMainPanel("IDF HUB PRIVAT",UDim2.new(0,600,0,480),UDim2.new(0.5,-300,0.5,-255))
if Config.AutoCloseOnExec then main.Visible = false end
panels["Invisible Steal Panel"],panels["InvisStealBody"]=makeQuickPanel("IDF HUB PRIVAT\nInvisible Steal",UDim2.new(0,330,0,375),UDim2.new(0,80,0.5,-220))
panels["InvisStealBody"].ScrollBarThickness = 0
panels["InvisStealBody"].ScrollingEnabled = false
panels["Admin Command Panel"],panels["AdminBody"]=makeQuickPanel("IDF HUB PRIVAT\nAdmin Command Panel",UDim2.new(0,325,0,240),UDim2.new(0.5,85,1,-340))
panels["Command Cooldowns"],panels["CooldownBody"]=makeQuickPanel("IDF HUB PRIVAT\nCommand Cooldowns",UDim2.new(0,310,0,315),UDim2.new(0.5,245,1,-390))
panels["Actions"],panels["ActionsBody"]=makeQuickPanel("IDF HUB PRIVAT\nActions",UDim2.new(0,330,0,340),UDim2.new(0.5,505,1,-415))
panels["Steal Panel"],panels["StealBody"]=makeQuickPanel("IDF HUB PRIVAT\nSteal Panel",UDim2.new(0,335,0,300),UDim2.new(1,-400,1,-385))
panels["Steal Target"],panels["TargetBody"]=makeQuickPanel("IDF HUB PRIVAT\nSteal Target",UDim2.new(0,420,0,380),UDim2.new(1,-430,0,85))
actionSettingsPanel,actionSettingsBody=makeQuickPanel("IDF HUB PRIVAT\nAction Settings",UDim2.new(0,330,0,370),UDim2.new(0.5,745,1,-440))
actionSettingsPanel.Visible=false
tpSpeedSettingsPanel,tpSpeedSettingsBody=makeQuickPanel("IDF HUB PRIVAT\nTP & Clone Settings",UDim2.new(0,335,0,325),UDim2.new(0.5,745,1,-440))
tpSpeedSettingsPanel.Visible=false
for _,pair in ipairs({{"IDF HUB PRIVAT",main},{"IDF HUB PRIVAT\nInvisible Steal",panels["Invisible Steal Panel"]},
    {"IDF HUB PRIVAT\nAdmin Command Panel",panels["Admin Command Panel"]},{"IDF HUB PRIVAT\nCommand Cooldowns",panels["Command Cooldowns"]},
    {"IDF HUB PRIVAT\nActions",panels["Actions"]},{"IDF HUB PRIVAT\nSteal Panel",panels["Steal Panel"]},{"IDF HUB PRIVAT\nSteal Target",panels["Steal Target"]},
    {"IDF HUB PRIVAT\nAction Settings",actionSettingsPanel},{"IDF HUB PRIVAT\nTP & Clone Settings",tpSpeedSettingsPanel}}) do applySavedPosition(pair[1],pair[2]) end

-- LAZY UI LOADING
if _G.addLazyUI then
    _G.addLazyUI(main, not Config.AutoCloseOnExec)
    _G.addLazyUI(actionSettingsPanel, false)
    _G.addLazyUI(tpSpeedSettingsPanel, false)
end

local immediatePanels = {
    ["Steal Target"] = true,
    ["Steal Panel"] = true,
    ["Invisible Steal Panel"] = true
}

for name, panel in pairs(panels) do
    if not string.match(name, "Body$") then
        -- _G._SXEPanelVis survives re-executes; override Config if it has a value
        local fromG = _G._SXEPanelVis[name]
        local targetVis
        if fromG ~= nil then
            targetVis = fromG
            Config.Visibilities[name] = fromG  -- sync back so Config is consistent
        else
            if Config.Visibilities[name] ~= nil then targetVis = Config.Visibilities[name] else targetVis = true end
        end
        if immediatePanels[name] then
            panel.Visible = targetVis
        elseif _G.addLazyUI then
            _G.addLazyUI(panel, targetVis, false, name)
        end
    end
end

-- ACTIONS PANEL
function rebuildActions()
    clearBody(panels["ActionsBody"])
    if actionConfig["Ragdoll Self (R)"] then makeQuickButton(panels["ActionsBody"],"Ragdoll Self (R)",function() pcall(runAdminCommand,player,"ragdoll") end) end
    if actionConfig["Rejoin PS"] then makeQuickButton(panels["ActionsBody"],"Rejoin PS",function() TeleportService:Teleport(game.PlaceId,player) end) end
    if actionConfig["Rejoin Job ID (J)"] then makeQuickButton(panels["ActionsBody"],"Rejoin Job ID (J)",function()
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player) end)
    end) end
    if actionConfig["Kick (Y)"] then makeQuickButton(panels["ActionsBody"],"Kick (Y)",function() kickPlayer() end) end
    if actionConfig["Kick To Private"] then makeQuickButton(panels["ActionsBody"],"Kick To Private",function() 
        if PrivateServerCode and PrivateServerCode ~= "" then
            task.delay(0.2, function()
                pcall(function() game:GetService("ExperienceService"):LaunchExperience({placeId=game.PlaceId,linkCode=PrivateServerCode}) end)
            end)
        end
    end) end
    if actionConfig["Reset (X)"] then makeQuickButton(panels["ActionsBody"],"Reset (X)",function() executeReset() end,Theme.SoftAccentHover) end
    if actionConfig["Anti Ragdoll"] then makeSyncStateRow(panels["ActionsBody"],"Anti Ragdoll:","Anti Ragdoll",function(on) if on then startAntiRagdoll() else stopAntiRagdoll() end end) end
    if actionConfig["Infinite Jump"] then makeSyncStateRow(panels["ActionsBody"],"Infinite Jump:","Infinite Jump",function(on) setInfiniteJump(on) end) end
    if actionConfig["Float"] then makeSyncStateRow(panels["ActionsBody"],"Float:","Float",function(on) setFloat(on) end) end
    if actionConfig["Carpet Speed"] then makeSyncStateRow(panels["ActionsBody"],"Carpet Speed:","Carpet Speed",function(on) setCarpetSpeed(on) end) end
    makeQuickButton(panels["ActionsBody"],"Settings",function()
        if actionSettingsPanel.Visible then closeAnim(actionSettingsPanel) else openAnim(actionSettingsPanel) end
    end,Theme.SoftAccent)
end

function rebuildActionSettings()
    clearBody(actionSettingsBody)
    for actionName,enabled in pairs(actionConfig) do
        local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,34); row.BackgroundTransparency=1; row.Parent=actionSettingsBody
        local label=Instance.new("TextLabel"); label.Size=UDim2.new(1,-84,1,0); label.Position=UDim2.new(0,4,0,0); label.BackgroundTransparency=1; label.Text=actionName; label.TextColor3=Theme.Text; label.Font=Enum.Font.GothamSemibold; label.TextSize=11; label.TextXAlignment=Enum.TextXAlignment.Left; label.TextTruncate=Enum.TextTruncate.AtEnd; label.Parent=row
        local btn=Instance.new("TextButton"); btn.Name="WhiteTextBtn"; btn.Size=UDim2.new(0,72,0,30); btn.Position=UDim2.new(1,-74,0.5,-15); btn.BackgroundColor3=enabled and Theme.Green or Theme.ToggleOff2; btn.Text=enabled and "ON" or "OFF"; btn.TextColor3=Color3.new(1,1,1); btn.Font=Enum.Font.GothamBlack; btn.TextSize=12; btn.AutoButtonColor=false; btn.Parent=row; corner(btn,6)
        btn.MouseButton1Click:Connect(function()
            actionConfig[actionName]=not actionConfig[actionName]; Config.actions[actionName]=actionConfig[actionName]; saveConfig()
            btn.BackgroundColor3=actionConfig[actionName] and Theme.Green or Theme.ToggleOff2; btn.Text=actionConfig[actionName] and "ON" or "OFF"
            rebuildActions()
        end)
    end
    makeQuickButton(actionSettingsBody,"Close",function() closeAnim(actionSettingsPanel) end,Theme.SoftAccentHover)
end

function rebuildTpSpeedSettings()
    clearBody(tpSpeedSettingsBody)
    makeMainSliderWithInput(tpSpeedSettingsBody, "Fly TP Speed", 50, 300, Config.TpSettings.FlyTPSpeed or 160, function(v) Config.TpSettings.FlyTPSpeed=v; saveConfig() end)
    makeMainSliderWithInput(tpSpeedSettingsBody, "Grabble TP Speed", 50, 600, Config.TpSettings.GrabbleTPSpeed or 230, function(v) Config.TpSettings.GrabbleTPSpeed=v; saveConfig(); if _G.SXESetCarpetSpeed then pcall(_G.SXESetCarpetSpeed, v) end end)
    makeMainSliderWithInput(tpSpeedSettingsBody, "Walk To Brainrot Speed", 50, 300, Config.TpSettings.WalkTPSpeed or 190, function(v) Config.TpSettings.WalkTPSpeed=v; saveConfig() end)
    makeMainSliderWithInput(tpSpeedSettingsBody, "Landing Delay Before Clone", 0.15, 0.75, Config.TpSettings.CloneDelayVal or 0.4, function(v) Config.TpSettings.CloneDelayVal=v; saveConfig() end, "s")
    makeMainSliderWithInput(tpSpeedSettingsBody, "Delay Before TP", 0, 0.9, Config.TpSettings.PreTpDelayVal or 0, function(v) Config.TpSettings.PreTpDelayVal=v; saveConfig() end, "s")
    makeMainButton(tpSpeedSettingsBody, "Manual TP", function() task.spawn(runAutoSnipe) end, Theme.Accent)
    makeMainButton(tpSpeedSettingsBody, "Edit Priority", function() if _G.SXEOpenPriorityEditor then pcall(_G.SXEOpenPriorityEditor) end end, Theme.SoftAccent)
    makeQuickButton(tpSpeedSettingsBody, "Close", function() closeAnim(tpSpeedSettingsPanel) end, Theme.SoftAccentHover)
end

do
    -- INVISIBLE STEAL PANEL POPULATION
    regToggle("Auto Recover Lagback", Config.AutoRecoverLagback)
    regToggle("Auto Steal Speed", Config.AutoStealSpeed)
    regToggle("Auto Invis During Steal", Config.AutoInvisDuringSteal)

    local enabledRow = makeSyncStateRow(panels["InvisStealBody"],"Enabled:","Invisible Steal",function(on) if _G.toggleInvisibleSteal then pcall(_G.toggleInvisibleSteal) end end)

    _G.updateMovementPanelLabels = function() end
    local rotSlider = makeQuickSlider(panels["InvisStealBody"],"Rotation",0,360,Config.InvisStealAngle or 225,function(v) _G.InvisStealAngle=v; Config.InvisStealAngle=v; saveConfig() end)
    local depthSlider = makeQuickSlider(panels["InvisStealBody"],"Depth",0,18,Config.SinkSliderValue or 7,function(v) _G.SinkSliderValue=v; Config.SinkSliderValue=v; saveConfig() end)
    local recoverToggle = makeSyncStateRow(panels["InvisStealBody"],"Auto Recover:","Auto Recover Lagback",function(on) _G.AutoRecoverLagback=on; Config.AutoRecoverLagback=on; saveConfig() end)
    local autoInvisToggle = makeSyncStateRow(panels["InvisStealBody"],"Auto Invis:","Auto Invis During Steal",function(on) _G.AutoInvisDuringSteal=on; Config.AutoInvisDuringSteal=on; saveConfig() end)

    -- WALKSPEED CONTROL (CFrame Bypass, min 15 max 29)
    regToggle("WalkSpeed", Config.WalkSpeedEnabled)
    makeSyncStateRow(panels["InvisStealBody"],"WalkSpeed:","WalkSpeed",function(on) setWalkSpeedEnabled(on) end)
    makeMainSliderWithInput(panels["InvisStealBody"], "Walk Speed", 15, 29, Config.WalkSpeedValue or 16, function(v)
        local clamped = setWalkSpeedValue(v)
    end)
    if Config.WalkSpeedEnabled then
        task.defer(function() setWalkSpeedEnabled(true) end)
    end


-- ADMIN QUICK PANEL
local function spamPlayerBaseOwner(targetPlayer)
    if not targetPlayer then return 0 end
    local cmdList = Config.SpamBaseOwnerOrder or AP_ALL_COMMANDS
    
    if Config.SpamBaseOwnerSingleCommand then
        local startIndex = _G.SpamBaseOwnerIndex or 1
        if startIndex > #cmdList then startIndex = 1 end
        
        local picked = nil
        local attempts = 0
        while attempts < #cmdList do
            local idx = ((startIndex - 1 + attempts) % #cmdList) + 1
            local cmd = cmdList[idx]
            if Config.SpamBaseOwnerCommands and Config.SpamBaseOwnerCommands[cmd] and not apIsOnCooldown(cmd) then
                picked = cmd
                _G.SpamBaseOwnerIndex = idx + 1
                break
            end
            attempts = attempts + 1
        end
        
        if picked then
            runAdminCommand(targetPlayer, picked)
            return 1
        end
        return 0
    else
        local activeCmds = {}
        for _, cmd in ipairs(cmdList) do
            if Config.SpamBaseOwnerCommands and Config.SpamBaseOwnerCommands[cmd] and not apIsOnCooldown(cmd) then
                table.insert(activeCmds, cmd)
            end
        end
        for i, cmd in ipairs(activeCmds) do
            task.spawn(function()
                task.wait((i - 1) * 0.01)
                runAdminCommand(targetPlayer, cmd)
            end)
        end
        return #activeCmds
    end
end

-- ADMIN QUICK PANEL
function spamBaseOwner()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        ShowNotification("SPAM OWNER", "No character found")
        return
    end
    local nearestPlot = nil
    local nearestDist = math.huge
    local Plots = Workspace:FindFirstChild("Plots")
    if Plots then
        for _, plot in ipairs(Plots:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign")
            if sign then
                local yourBase = sign:FindFirstChild("YourBase")
                if not yourBase or not yourBase.Enabled then
                    local signPos = (sign:IsA("BasePart") and sign.Position)
                        or (sign.PrimaryPart and sign.PrimaryPart.Position)
                    if not signPos then
                        local part = sign:FindFirstChildWhichIsA("BasePart", true)
                        signPos = part and part.Position
                    end
                    if signPos then
                        local dist = (hrp.Position - signPos).Magnitude
                        if dist < nearestDist then
                            nearestDist = dist
                            nearestPlot = plot
                        end
                    end
                end
            end
        end
    end
    if not nearestPlot then
        ShowNotification("SPAM OWNER", "No nearby base found")
        return
    end
    local targetPlayer = nil
    local ok, Synchronizer = pcall(require, ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Synchronizer"))
    if ok and Synchronizer then
        local ch = Synchronizer:Get(nearestPlot.Name)
        if ch then
            local owner = ch:Get("Owner")
            if owner then
                if (typeof(owner) == "Instance") and owner:IsA("Player") then
                    targetPlayer = owner
                elseif (type(owner) == "table") and owner.Name then
                    targetPlayer = Players:FindFirstChild(owner.Name)
                end
            end
        end
    end
    if not targetPlayer then
        local sign = nearestPlot:FindFirstChild("PlotSign")
        local textLabel = sign
            and sign:FindFirstChild("SurfaceGui")
            and sign.SurfaceGui:FindFirstChild("Frame")
            and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")
        if textLabel then
            local baseText = textLabel.Text
            local nickname = (baseText and baseText:match("^(.-)'")) or baseText
            if nickname then
                for _, p in ipairs(Players:GetPlayers()) do
                    if (p.DisplayName == nickname) or (p.Name == nickname) then
                        targetPlayer = p
                        break
                    end
                end
            end
        end
    end
    if not targetPlayer or (targetPlayer == LocalPlayer) then
        ShowNotification("SPAM OWNER", "Owner not found or is you")
        return
    end
    if isPlayerBlacklisted(targetPlayer) then
        ShowNotification("SPAM OWNER", targetPlayer.DisplayName .. " is blacklisted")
        return
    end
    ShowNotification("SPAM OWNER", "Spamming " .. targetPlayer.DisplayName)
    local sentCount = spamPlayerBaseOwner(targetPlayer)
    ShowNotification("SPAM OWNER", "Sent " .. tostring(sentCount) .. " commands")
end

makeSyncStateRow(panels["AdminBody"],"Click to AP:","Click to AP",function(on) Config.ClickToAP=on; saveConfig() end)
makeSyncStateRow(panels["AdminBody"],"Proximity:","Proximity",function(on) setProximityAP(on) end)
makeQuickSlider(panels["AdminBody"],"Distance",1,50,Config.ProximityRange or 15,function(v) Config.ProximityRange=v; saveConfig() end," studs")
makeQuickButton(panels["AdminBody"],"Spam Base Owner",spamBaseOwner)

-- COOLDOWN PANEL
LazyInit("Cooldown Panel", function() -- COOLDOWN PANEL SCOPE
local cooldownLabels={}
for _,item in ipairs({"jail","rocket","inverse","ragdoll","jumpscare","tiny","balloon","morph","nightvision"}) do
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,24); row.BackgroundTransparency=1; row.Parent=panels["CooldownBody"]
    local left=Instance.new("TextLabel"); left.Size=UDim2.new(0.58,0,1,0); left.Position=UDim2.new(0,6,0,0); left.BackgroundTransparency=1; left.Text=item:sub(1,1):upper()..item:sub(2); left.TextColor3=Theme.Text; left.Font=Enum.Font.GothamBold; left.TextSize=12; left.TextXAlignment=Enum.TextXAlignment.Left; left.Parent=row
    local right=Instance.new("TextLabel"); right.Size=UDim2.new(0.36,0,1,0); right.Position=UDim2.new(0.62,0,0,0); right.BackgroundTransparency=1; right.Text="READY"; right.TextColor3=Theme.Green; right.Font=Enum.Font.GothamBlack; right.TextSize=11; right.TextXAlignment=Enum.TextXAlignment.Right; right.Parent=row
    cooldownLabels[item]=right
end
task.spawn(function() while true do task.wait(0.5); for cmd,label in pairs(cooldownLabels) do local rem=apGetRemaining(cmd); if rem>0 then label.Text=string.format("%.0fs",rem); label.TextColor3=Theme.Red else label.Text="READY"; label.TextColor3=Theme.Green end end end end)
end) -- END COOLDOWN PANEL SCOPE (LazyInit)

-- STEAL PANEL
makeSyncStateRow(panels["StealBody"],"Auto Steal:","Auto Steal",function(on)
    autoStealEnabled=on; Config.AutoStealEnabled=on; saveConfig()
    -- SXE Clone-TP engine owns the auto-steal loop unconditionally.
    if _G.SXEAutoSteal then pcall(_G.SXEAutoSteal, on) end
end)
makeSyncStateRow(panels["StealBody"],"Steal Highest:","Steal Highest",function(on) if on then setStealMode("Highest") end end)
makeSyncStateRow(panels["StealBody"],"Steal Priority:","Steal Priority",function(on) if on then setStealMode("Priority") end end)
makeSyncStateRow(panels["StealBody"],"Steal Nearest:","Steal Nearest",function(on) if on then setStealMode("Nearest") end end)
makeSyncStateRow(panels["StealBody"],"Auto Buy:","Auto Buy",function(on)
    if toggleAutoBuy then toggleAutoBuy(on)
    else warn("[SXE] Auto Buy not ready yet -- try again in a sec") end
end)
makeSyncStateRow(panels["StealBody"],"Auto Kick:","Auto Kick",function(on) Config.AutoKickOnSteal=on; saveConfig() end)



-- STEAL TARGET (0.4s refresh) -- NOT lazy: panel must populate on load
do -- STEAL TARGET SCOPE
function refreshTargetPanel()
    clearBody(panels["TargetBody"])
    local cache = get_all_pets()
    if not cache or #cache == 0 then
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1,-4,0,24)
        l.BackgroundTransparency = 1
        l.Text = "Scanning..."
        l.TextColor3 = Theme.Dim
        l.Font = Enum.Font.GothamSemibold
        l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Center
        l.Parent = panels["TargetBody"]
        return
    end

    -- Build priority lookup
    local prioSet = {}
    for _, pName in ipairs(priorityList) do prioSet[pName:lower()] = true end

    -- Split into priority and non-priority
    local prioPets, otherPets = {}, {}
    for _, pet in ipairs(cache) do
        local isBrainrot = (pet.mpsValue and pet.mpsValue >= 10000000)
        if isBrainrot or (pet.petName and prioSet[pet.petName:lower()]) then
            table.insert(prioPets, pet)
        else
            table.insert(otherPets, pet)
        end
    end

    -- Sort priority pets by priority list order, keeping Brainrots at the absolute top
    table.sort(prioPets, function(a, b)
        local ai, bi = 999, 999
        for idx, pn in ipairs(priorityList) do
            local pnL = pn:lower()
            if a.petName and a.petName:lower() == pnL then ai = idx end
            if b.petName and b.petName:lower() == pnL then bi = idx end
        end
        
        local aIsBrainrot = (a.mpsValue and a.mpsValue >= 10000000)
        local bIsBrainrot = (b.mpsValue and b.mpsValue >= 10000000)
        
        if aIsBrainrot and not bIsBrainrot then return true end
        if bIsBrainrot and not aIsBrainrot then return false end
        
        if ai == bi then return (a.mpsValue or 0) > (b.mpsValue or 0) end
        return ai < bi
    end)

    local function makeTargetRow(pet, displayIndex, isPriority)
        local isSelected = (selectedTargetUID == pet.uid)
        local isManual = (manuallySelectedUID == pet.uid)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1,-4,0,44)
        row.BackgroundColor3 = isSelected and Theme.RowHover or Theme.Panel
        row.BackgroundTransparency = isPriority and 0.18 or 0.35
        row.Parent = panels["TargetBody"]
        corner(row, 6)
        if isSelected or isManual then
            local str = Instance.new("UIStroke", row)
            str.Color = isManual and Color3.fromRGB(56, 214, 110) or Theme.Accent
            str.Thickness = isManual and 1.75 or 1.25
        elseif isPriority then
            local str = Instance.new("UIStroke", row)
            str.Color = Color3.fromRGB(255, 90, 120)
            str.Thickness = 0.75
            str.Transparency = 0.3
        end
        
        local rankBox = Instance.new("Frame")
        rankBox.Size = UDim2.new(0, 26, 0, 26)
        rankBox.Position = UDim2.new(0, 8, 0.5, -13)
        rankBox.BackgroundColor3 = Color3.fromRGB(90, 25, 45)
        rankBox.BorderSizePixel = 0
        rankBox.Parent = row
        corner(rankBox, 4)
        
        local n = Instance.new("TextLabel")
        n.Size = UDim2.new(1,0,1,0)
        n.BackgroundTransparency = 1
        n.Text = "#"..displayIndex
        n.TextColor3 = Color3.new(1,1,1)
        n.Font = Enum.Font.GothamBold
        n.TextSize = 12
        n.Parent = rankBox
        
        local nm = Instance.new("TextLabel")
        nm.Size = UDim2.new(1,-50,0,18)
        nm.Position = UDim2.new(0,44,0,5)
        nm.BackgroundTransparency = 1
        nm.Text = pet.petName or "?"
        nm.TextColor3 = isPriority and Color3.new(1,1,1) or Theme.Text
        nm.Font = isPriority and Enum.Font.GothamBold or Enum.Font.GothamSemibold
        nm.TextSize = 13
        nm.TextXAlignment = Enum.TextXAlignment.Left
        nm.TextTruncate = Enum.TextTruncate.AtEnd
        nm.Parent = row
        
        local gn = Instance.new("TextLabel")
        gn.Size = UDim2.new(1,-50,0,14)
        gn.Position = UDim2.new(0,44,0,23)
        gn.BackgroundTransparency = 1
        gn.RichText = true
        local ownerText = pet.owner and (' <font color="#999999">| @' .. tostring(pet.owner) .. '</font>') or ""
        gn.Text = '<font color="#38D66E">Gem: ' .. (pet.mpsText or "") .. '</font>' .. ownerText
        gn.TextColor3 = Color3.new(1,1,1)
        gn.Font = Enum.Font.GothamMedium
        gn.TextSize = 11
        gn.TextXAlignment = Enum.TextXAlignment.Left
        gn.TextTruncate = Enum.TextTruncate.AtEnd
        gn.Parent = row

        local overlay = Instance.new("TextButton")
        overlay.Size = UDim2.new(1,0,1,0)
        overlay.BackgroundTransparency = 1
        overlay.Text = ""
        overlay.ZIndex = 8
        overlay.Parent = row
        overlay.MouseButton1Click:Connect(function()
            if manuallySelectedUID == pet.uid then
                manuallySelectedUID = nil
                selectedTargetUID = nil
                SharedState.SelectedPetData = nil
            else
                selectedTargetUID = pet.uid
                manuallySelectedUID = pet.uid
                SharedState.SelectedPetData = pet
                if pet then SharedState.LastTargetedPetMpsValue = pet.mpsValue or 0 end
            end
            refreshTargetPanel()

            if manuallySelectedUID then
                task.spawn(function()
                    local pr = PromptMemoryCache[pet.uid] or findProximityPromptForAnimal(pet.animalData)
                    if pr then
                        if _G.SXE_ExecuteManualSteal then
                            pcall(_G.SXE_ExecuteManualSteal, pr)
                        end
                    end
                end)
            end
        end)
    end

    local idx = 0
    for _, pet in ipairs(prioPets) do idx = idx + 1; makeTargetRow(pet, idx, true) end

    if #prioPets > 0 and #otherPets > 0 then
        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1,-20,0,1)
        sep.BackgroundColor3 = Theme.AccentLight
        sep.BackgroundTransparency = 0.5
        sep.BorderSizePixel = 0
        sep.Parent = panels["TargetBody"]
    end

    for _, pet in ipairs(otherPets) do idx = idx + 1; makeTargetRow(pet, idx, false) end
end
task.spawn(function() while true do task.wait(0.4); refreshTargetPanel() end end)
end -- END STEAL TARGET SCOPE

-- ============================================================
-- ADMIN PANEL UI
-- ============================================================
LazyInit("Admin Panel UI", function() -- ADMIN PANEL UI SCOPE
    pcall(function() local e=playerGui:FindFirstChild("XiAdminPanel"); if e then e:Destroy() end end)
    apGui=Instance.new("ScreenGui"); apGui.Name="XiAdminPanel"; apGui.ResetOnSpawn=false; apGui.IgnoreGuiInset=true; apGui.DisplayOrder=9999998; apGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; apGui.Parent=playerGui
    apGui.Enabled = (Config.AdminPanelUI == true)
    apOuter=Instance.new("Frame"); apOuter.Name="Frame"; apOuter.BackgroundTransparency=1; apOuter.BorderSizePixel=0; apOuter.Size=UDim2.fromOffset(480,0); apOuter.AutomaticSize=Enum.AutomaticSize.Y; apOuter.Position=UDim2.new(0.18,0,0.57,0); apOuter.ZIndex=10; apOuter.ClipsDescendants=true; apOuter.Parent=registerScreenGui(apGui)
    apBG=Instance.new("Frame"); apBG.BackgroundColor3=Theme.Background; apBG.BackgroundTransparency=0.50; apBG.BorderSizePixel=0; apBG.Position=UDim2.fromOffset(-3,-2); apBG.Size=UDim2.new(1,6,1,4); apBG.ZIndex=0; apBG.Parent=apOuter; corner(apBG,8)
    apTop=Instance.new("Frame"); apTop.BackgroundTransparency=1; apTop.BorderSizePixel=0; apTop.Size=UDim2.new(1,0,0,16); apTop.Parent=apOuter; corner(apTop,3)

    makeDraggable(apOuter,apTop,"AdminPanel"); applySavedPosition("AdminPanel",apOuter);

    apList=Instance.new("Frame"); apList.BackgroundTransparency=1; apList.BorderSizePixel=0; apList.Position=UDim2.new(0,0,0,20); apList.Size=UDim2.new(1,0,0,0); apList.AutomaticSize=Enum.AutomaticSize.Y; apList.Parent=apOuter; corner(apList,3)
    apPad=Instance.new("UIPadding"); apPad.PaddingTop=UDim.new(0,2); apPad.PaddingBottom=UDim.new(0,2); apPad.PaddingLeft=UDim.new(0,4); apPad.PaddingRight=UDim.new(0,4); apPad.Parent=apList
    Instance.new("UIListLayout",apList).SortOrder=Enum.SortOrder.LayoutOrder; apList:FindFirstChildOfClass("UIListLayout").Padding=UDim.new(0,2)

    apRows,stealLabels={},{}; rc=0
    -- Build RP_BUTTONS dynamically from Config.AdminPanelButtons
    local function buildRPButtons()
        local btns = {}
        local order = Config.AdminPanelOrder or AP_ALL_COMMANDS
        for _, cmd in ipairs(order) do
            if Config.AdminPanelButtons and Config.AdminPanelButtons[cmd] then
                table.insert(btns, {AP_COMMAND_EMOJIS[cmd] or "⚡", cmd})
            end
        end
        if #btns == 0 then btns = {{"🌀","ragdoll"},{"🔒","jail"},{"🚀","rocket"},{"🎈","balloon"}} end
        return btns
    end
    RP_BUTTONS = buildRPButtons()

    _G.refreshAdminPanelRows = function()
        for uid, row in pairs(apRows) do
            if row then row:Destroy() end
        end
        table.clear(apRows)
        table.clear(stealLabels)
        rc = 0
        RP_BUTTONS = buildRPButtons()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= player then createAPRow(plr) end
        end
    end

    function createAPRow(plr)
        if not plr or plr==player then return end; if apRows[plr.UserId] and apRows[plr.UserId].Parent then return end
        rc=rc+1; local isAlt=(rc%2==0)
        local actW = (#RP_BUTTONS + 1) * 32 -- Buttons + Blacklist + padding
        local rowW = math.max(460, actW + 180) -- Base width 460, expand if buttons take too much space
        local row=Instance.new("Frame"); row.Name="Row_"..plr.UserId; row.BackgroundColor3=isAlt and Theme.Row or Theme.Panel; row.BackgroundTransparency=0.40; row.BorderSizePixel=0; row.Size=UDim2.new(0,rowW,0,54); row.ZIndex=5; row.ClipsDescendants=true; row.Parent=apList; corner(row,3)
        apRows[plr.UserId]=row
        row.MouseEnter:Connect(function() 
            if not isPlayerBlacklisted(plr) then
                row.BackgroundColor3 = Theme.RowHover
            else
                row.BackgroundColor3 = Theme.BlacklistHover
            end
        end)
        row.MouseLeave:Connect(function() 
            row.BackgroundColor3 = isAlt and Theme.Row or Theme.Panel
        end)

        local avatarH=Instance.new("Frame"); avatarH.BackgroundColor3=Theme.InputBg; avatarH.BorderSizePixel=0; avatarH.Size=UDim2.fromOffset(34,34); avatarH.Position=UDim2.fromOffset(8,10); avatarH.Parent=row; corner(avatarH,8)
        local avatar=Instance.new("ImageLabel"); avatar.BackgroundTransparency=1; avatar.Size=UDim2.fromScale(1,1); avatar.ZIndex=10; avatar.Parent=avatarH; corner(avatar,8)
        task.spawn(function() local ok,img=pcall(function() return Players:GetUserThumbnailAsync(plr.UserId,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size48x48) end); if ok then avatar.Image=img end end)
        local headshotStroke=Instance.new("UIStroke",avatarH); headshotStroke.Color=Theme.Accent; headshotStroke.Thickness=2; headshotStroke.Transparency=0.3

        local txtW=-(actW+60)
        local nameLabel=Instance.new("TextLabel"); nameLabel.Size=UDim2.new(1,txtW,0,20); nameLabel.Position=UDim2.fromOffset(50,6); nameLabel.BackgroundTransparency=1; nameLabel.Text=plr.DisplayName; nameLabel.Font=Enum.Font.GothamBold; nameLabel.TextSize=14; nameLabel.TextColor3=Theme.Text; nameLabel.TextXAlignment=Enum.TextXAlignment.Left; nameLabel.ZIndex=10; nameLabel.Parent=row
        local userL=Instance.new("TextLabel"); userL.BackgroundTransparency=1; userL.Position=UDim2.fromOffset(50,23); userL.Size=UDim2.new(1,txtW,0,16); userL.TextXAlignment=Enum.TextXAlignment.Left; userL.Text="@"..plr.Name; userL.Font=Enum.Font.GothamMedium; userL.TextSize=10; userL.TextColor3=Theme.Dim; userL.ZIndex=10; userL.Parent=row
        local statusL=Instance.new("TextLabel"); statusL.BackgroundTransparency=1; statusL.Position=UDim2.fromOffset(50,37); statusL.Size=UDim2.new(1,txtW,0,14); statusL.TextXAlignment=Enum.TextXAlignment.Left; statusL.Text=""; statusL.Font=Enum.Font.GothamBold; statusL.TextSize=11; statusL.TextColor3=Theme.AccentLight; statusL.ZIndex=10; statusL.Parent=row
        stealLabels[plr.UserId]=statusL

        local actions=Instance.new("Frame"); actions.BackgroundTransparency=1; actions.AnchorPoint=Vector2.new(1,0.5); actions.Position=UDim2.new(1,-8,0.5,0); actions.Size=UDim2.fromOffset(actW+10,38); actions.ZIndex=12; actions.Parent=row
        local al=Instance.new("UIListLayout"); al.FillDirection=Enum.FillDirection.Horizontal; al.SortOrder=Enum.SortOrder.LayoutOrder; al.Padding=UDim.new(0,2); al.Parent=actions

        for i,b in ipairs(RP_BUTTONS) do
            local btn=Instance.new("TextButton"); btn.Size=UDim2.fromOffset(30,30); btn.BackgroundTransparency=0; btn.AutoButtonColor=false; btn.Text=b[1]; btn.TextSize=12; btn.LayoutOrder=i; btn.Parent=actions
            btn.BackgroundColor3=Theme.SoftButton; btn.Font=Enum.Font.GothamBold; btn.ZIndex=13
            Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6)
            btn.MouseEnter:Connect(function() btn.BackgroundColor3=Theme.SoftButtonHover end)
            btn.MouseLeave:Connect(function() btn.BackgroundColor3=Theme.SoftButton end)
            btn.MouseButton1Click:Connect(function()
                if isPlayerBlacklisted(plr) then
                    ShowNotification("BLOCKED", plr.DisplayName .. " is blacklisted")
                    return
                end
                if apIsOnCooldown(b[2]) then return end; pcall(runAdminCommand,plr,b[2])
            end)
        end

        local blacklistBtn = Instance.new("TextButton")
        blacklistBtn.Name = "BlacklistBtn"
        blacklistBtn.Size = UDim2.fromOffset(30, 30)
        blacklistBtn.BackgroundTransparency = 0
        blacklistBtn.AutoButtonColor = false
        blacklistBtn.Text = "✖"
        blacklistBtn.TextSize = 12
        blacklistBtn.LayoutOrder = 5
        blacklistBtn.Parent = actions
        blacklistBtn.Font = Enum.Font.GothamBold
        blacklistBtn.ZIndex = 13
        Instance.new("UICorner", blacklistBtn).CornerRadius = UDim.new(0, 6)

        local function updateBlacklistVisuals()
            local isBlacklisted = isPlayerBlacklisted(plr)
            if isBlacklisted then
                blacklistBtn.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
                blacklistBtn.TextColor3 = Color3.new(1, 1, 1)
                
                row.BackgroundTransparency = 0.85
                avatar.ImageTransparency = 0.75
                nameLabel.TextTransparency = 0.6
                userL.TextTransparency = 0.6
                statusL.TextTransparency = 0.6
                
                for _, child in ipairs(actions:GetChildren()) do
                    if child:IsA("TextButton") and child ~= blacklistBtn then
                        child.BackgroundTransparency = 0.8
                        child.TextTransparency = 0.8
                    end
                end
            else
                blacklistBtn.BackgroundColor3 = Theme.BlacklistLeave
                blacklistBtn.TextColor3 = Color3.fromRGB(255, 60, 60)
                
                row.BackgroundTransparency = 0.40
                avatar.ImageTransparency = 0
                nameLabel.TextTransparency = 0
                userL.TextTransparency = 0
                statusL.TextTransparency = 0
                
                for _, child in ipairs(actions:GetChildren()) do
                    if child:IsA("TextButton") then
                        child.BackgroundTransparency = 0
                        child.TextTransparency = 0
                    end
                end
            end
        end

        blacklistBtn.MouseEnter:Connect(function() 
            if not isPlayerBlacklisted(plr) then
                blacklistBtn.BackgroundColor3 = Theme.BlacklistHover
            end
        end)
        blacklistBtn.MouseLeave:Connect(function() 
            if not isPlayerBlacklisted(plr) then
                blacklistBtn.BackgroundColor3 = Theme.BlacklistLeave
            end
        end)

        blacklistBtn.MouseButton1Click:Connect(function()
            local isBlacklisted = isPlayerBlacklisted(plr)
            _G.apBlacklist[tostring(plr.UserId)] = not isBlacklisted
            Config.apBlacklist = _G.apBlacklist
            saveConfig()
            updateBlacklistVisuals()
            if not isBlacklisted then
                ShowNotification("BLACKLIST", plr.DisplayName .. " blacklisted")
            else
                ShowNotification("BLACKLIST", plr.DisplayName .. " whitelisted")
            end
        end)

        updateBlacklistVisuals()

        -- Click on player row = fire ALL available admin commands at once (like Click to AP)
        row.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            -- Ignore clicks on the action buttons themselves
            local mousePos = UIS:GetMouseLocation()
            if actions and actions.AbsolutePosition and actions.AbsoluteSize then
                local ax, ay = actions.AbsolutePosition.X, actions.AbsolutePosition.Y
                local aw, ah = actions.AbsoluteSize.X, actions.AbsoluteSize.Y
                if mousePos.X >= ax and mousePos.X <= ax+aw and mousePos.Y >= ay and mousePos.Y <= ay+ah then
                    return
                end
            end
            if isPlayerBlacklisted(plr) then
                ShowNotification("BLOCKED", plr.DisplayName .. " is blacklisted")
                return
            end
            task.spawn(function()
                local activeCmds = {}
                for _,cmd in ipairs(AP_ALL_COMMANDS) do
                    if not apIsOnCooldown(cmd) then
                        table.insert(activeCmds, cmd)
                    end
                end
                if #activeCmds == 0 then
                    ShowNotification("ADMIN PANEL", "All commands on cooldown")
                    return
                end
                -- Fire ALL at once with minimal delay
                for i, cmd in ipairs(activeCmds) do
                    task.spawn(function()
                        task.wait((i - 1) * 0.01)
                        runAdminCommand(plr, cmd)
                    end)
                end
                ShowNotification("ADMIN PANEL", "Fired " .. #activeCmds .. " cmds on " .. plr.DisplayName)
            end)
        end)

        -- Steal / base-owner status. Reads the cached Synchronizer + memoized
        -- base-owner set, so every row shares one scan instead of each rescanning.
        task.spawn(function() while row.Parent do task.wait(0.5)
            if not plr or not plr.Parent then break end
            local st=stealLabels[plr.UserId]; if not st then break end

            local stealOwner, stealPet = getStealingInfo(plr)
            local curBaseOwnerId = _G.__getCurrentBaseOwnerId()

            if stealPet then
                local fromTxt = stealOwner and (" from " .. (stealOwner.DisplayName or stealOwner.Name)) or ""
                st.Text = "● Stealing " .. tostring(stealPet) .. fromTxt
                st.TextColor3 = Color3.fromRGB(255, 90, 90)
            elseif curBaseOwnerId and curBaseOwnerId == plr.UserId then
                st.Text = "● Base Owner"
                st.TextColor3 = Color3.fromRGB(90, 230, 120)
            else
                st.Text = ""
            end

            -- Danger-tool name highlight
            pcall(function() local ht=getHeldTool(plr)
                if ht and DANGER_TOOLS[ht] then nameLabel.TextColor3=Color3.fromRGB(255,60,60) else nameLabel.TextColor3=Theme.Text end
            end)
        end end)
    end

    for _,plr in ipairs(Players:GetPlayers()) do if plr~=player then createAPRow(plr) end end
    Players.PlayerAdded:Connect(function(plr) task.defer(function() createAPRow(plr) end) end)
    Players.PlayerRemoving:Connect(function(plr) local row=apRows[plr.UserId]; if row then row:Destroy(); apRows[plr.UserId]=nil end; stealLabels[plr.UserId]=nil end)
end) -- END ADMIN PANEL UI SCOPE (LazyInit)

-- ============================================================
-- TAB BAR + TABS
-- ============================================================
tabBar=Instance.new("Frame"); tabBar.Size=UDim2.new(1,-(ART_WIDTH+18),0,28); tabBar.Position=UDim2.new(0,ART_WIDTH+6,0,43); tabBar.BackgroundTransparency=1; tabBar.Parent=main
local tabDiv=Instance.new("Frame"); tabDiv.Size=UDim2.new(1,0,0,1); tabDiv.Position=UDim2.new(0,0,1,-1); tabDiv.BackgroundColor3=Theme.Stroke; tabDiv.BorderSizePixel=0; tabDiv.Parent=tabBar
tabUnderline=Instance.new("Frame"); tabUnderline.Size=UDim2.new(0,49,0,2); tabUnderline.Position=UDim2.new(0,0,1,-2); tabUnderline.BackgroundColor3=Theme.Accent; tabUnderline.BorderSizePixel=0; tabUnderline.ZIndex=2; tabUnderline.Parent=tabBar
local tabs={"Keybinds","Auto TP","ESP","UI","Misc","Priority","Performance"}
for i,name in ipairs(tabs) do local b=Instance.new("TextButton"); b.Size=UDim2.new(0,49,0,27); b.Position=UDim2.new(0,(i-1)*51,0,0); b.BackgroundTransparency=1; b.Text=name; b.TextColor3=Theme.Dim; b.Font=Enum.Font.GothamMedium; b.TextSize=8; b.AutoButtonColor=false; b.Parent=tabBar; tabButtons[name]=b end

-- Cache all animal names for autocomplete. Source per request:
-- ReplicatedStorage.Animations.Animals (animation instances are named after
-- each brainrot). Fallback: ReplicatedStorage.Models.Animals if Animations
-- isn't present in the place.
local _allAnimalNames = nil
local function getAllAnimalNames()
    if _allAnimalNames and #_allAnimalNames > 0 then return _allAnimalNames end
    _allAnimalNames = {}
    pcall(function()
        local source = ReplicatedStorage:FindFirstChild("Animations")
        source = source and source:FindFirstChild("Animals")
        if not source then
            -- fallback if Animations.Animals isn't present
            local models = ReplicatedStorage:FindFirstChild("Models")
            source = models and models:FindFirstChild("Animals")
        end
        if source then
            local seen = {}
            for _, child in ipairs(source:GetChildren()) do
                if not seen[child.Name] then
                    seen[child.Name] = true
                    table.insert(_allAnimalNames, child.Name)
                end
            end
            table.sort(_allAnimalNames, function(a, b) return a:lower() < b:lower() end)
        end
    end)
    return _allAnimalNames
end
task.spawn(getAllAnimalNames)

-- Drag state for priority reorder
local _priDragState = {active = false, fromIndex = nil, ghostFrame = nil, overlay = nil}

local function cleanupPriDrag()
    if _priDragState.ghostFrame then pcall(function() _priDragState.ghostFrame:Destroy() end); _priDragState.ghostFrame = nil end
    if _priDragState.overlay then pcall(function() _priDragState.overlay:Destroy() end); _priDragState.overlay = nil end
    _priDragState.active = false; _priDragState.fromIndex = nil
end

function makePriorityRow(index)
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,31); row.BackgroundColor3=Theme.Panel; row.BackgroundTransparency=0.18; row.Parent=mainBody; corner(row,6); row.LayoutOrder=index

    -- Number label
    local num=Instance.new("TextLabel"); num.Size=UDim2.new(0,24,1,0); num.Position=UDim2.new(0,4,0,0); num.BackgroundTransparency=1; num.Text=tostring(index).."."; num.TextColor3=Theme.Dim; num.Font=Enum.Font.GothamBold; num.TextSize=10; num.TextXAlignment=Enum.TextXAlignment.Left; num.Parent=row

    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-120,1,0); l.Position=UDim2.new(0,28,0,0); l.BackgroundTransparency=1; l.Text=priorityList[index]; l.TextColor3=Theme.Text; l.Font=Enum.Font.GothamMedium; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextTruncate=Enum.TextTruncate.AtEnd; l.Parent=row

    local up=Instance.new("TextButton"); up.Name="WhiteTextBtn"; up.Size=UDim2.new(0,26,0,22); up.Position=UDim2.new(1,-86,0.5,-11); up.BackgroundColor3=Theme.Accent; up.Text="▲"; up.TextColor3=Color3.new(1,1,1); up.Font=Enum.Font.GothamBold; up.TextSize=10; up.Parent=row; corner(up,5)
    local dn=Instance.new("TextButton"); dn.Name="WhiteTextBtn"; dn.Size=UDim2.new(0,26,0,22); dn.Position=UDim2.new(1,-56,0.5,-11); dn.BackgroundColor3=Theme.Accent; dn.Text="▼"; dn.TextColor3=Color3.new(1,1,1); dn.Font=Enum.Font.GothamBold; dn.TextSize=10; dn.Parent=row; corner(dn,5)
    local del=Instance.new("TextButton"); del.Name="WhiteTextBtn"; del.Size=UDim2.new(0,26,0,22); del.Position=UDim2.new(1,-26,0.5,-11); del.BackgroundColor3=Theme.Red; del.Text="X"; del.TextColor3=Color3.new(1,1,1); del.Font=Enum.Font.GothamBold; del.TextSize=10; del.Parent=row; corner(del,5)
    up.MouseButton1Click:Connect(function() if index>1 then priorityList[index],priorityList[index-1]=priorityList[index-1],priorityList[index]; Config.PriorityList=priorityList; saveConfig(); loadTab("Priority") end end)
    dn.MouseButton1Click:Connect(function() if index<#priorityList then priorityList[index],priorityList[index+1]=priorityList[index+1],priorityList[index]; Config.PriorityList=priorityList; saveConfig(); loadTab("Priority") end end)
    del.MouseButton1Click:Connect(function() local removedName=priorityList[index]; table.remove(priorityList,index); if not Config.RemovedFromPriority then Config.RemovedFromPriority={} end; local alreadyRemoved=false; for _,rn in ipairs(Config.RemovedFromPriority) do if rn==removedName then alreadyRemoved=true; break end end; if not alreadyRemoved then table.insert(Config.RemovedFromPriority,removedName) end; Config.PriorityList=priorityList; saveConfig(); loadTab("Priority") end)

    -- Drag & Drop
    local dragHandle = Instance.new("TextButton"); dragHandle.Size=UDim2.new(0,24,1,0); dragHandle.Position=UDim2.new(0,0,0,0); dragHandle.BackgroundTransparency=1; dragHandle.Text=""; dragHandle.ZIndex=9; dragHandle.Parent=row
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        cleanupPriDrag()
        _priDragState.active = true; _priDragState.fromIndex = index

        local ghost = Instance.new("Frame"); ghost.Size = UDim2.new(0, row.AbsoluteSize.X, 0, 31)
        ghost.BackgroundColor3 = Theme.Accent; ghost.BackgroundTransparency = 0.55; ghost.BorderSizePixel = 0; ghost.ZIndex = 100
        ghost.Parent = gui_sg; corner(ghost, 6)
        local gl = Instance.new("TextLabel"); gl.Size = UDim2.new(1,0,1,0); gl.BackgroundTransparency = 1; gl.Text = tostring(index)..". "..priorityList[index]; gl.TextColor3 = Color3.new(1,1,1); gl.Font = Enum.Font.GothamBold; gl.TextSize = 10; gl.Parent = ghost
        _priDragState.ghostFrame = ghost

        local moveConn, endConn
        moveConn = UIS.InputChanged:Connect(function(mi)
            if mi.UserInputType == Enum.UserInputType.MouseMovement or mi.UserInputType == Enum.UserInputType.Touch then
                ghost.Position = UDim2.new(0, mi.Position.X - ghost.AbsoluteSize.X/2, 0, mi.Position.Y - 15)
            end
        end)
        endConn = UIS.InputEnded:Connect(function(ei)
            if ei.UserInputType ~= Enum.UserInputType.MouseButton1 and ei.UserInputType ~= Enum.UserInputType.Touch then return end
            moveConn:Disconnect(); endConn:Disconnect()
            if not _priDragState.active then cleanupPriDrag(); return end

            -- Determine drop target index from Y position
            local dropY = ei.Position.Y
            local targetIndex = #priorityList
            for _, child in ipairs(mainBody:GetChildren()) do
                if child:IsA("Frame") and child.LayoutOrder and child.LayoutOrder >= 1 and child.LayoutOrder <= #priorityList then
                    local absY = child.AbsolutePosition.Y
                    local absH = child.AbsoluteSize.Y
                    if dropY < absY + absH / 2 then
                        targetIndex = child.LayoutOrder
                        break
                    end
                end
            end
            local fromIdx = _priDragState.fromIndex
            cleanupPriDrag()
            if fromIdx and targetIndex and fromIdx ~= targetIndex then
                local item = table.remove(priorityList, fromIdx)
                if targetIndex > fromIdx then targetIndex = targetIndex - 1 end
                targetIndex = math.clamp(targetIndex, 1, #priorityList + 1)
                table.insert(priorityList, targetIndex, item)
                Config.PriorityList = priorityList; saveConfig()
                loadTab("Priority")
            end
        end)
    end)
end

function makePriorityAddRow()
    local holder = Instance.new("Frame"); holder.Size=UDim2.new(1,-4,0,31); holder.BackgroundColor3=Theme.SoftAccent; holder.BackgroundTransparency=0.1; holder.ClipsDescendants=false; holder.Parent=mainBody; holder.ZIndex=20; corner(holder,6); holder.LayoutOrder = -2

    local box=Instance.new("TextBox"); box.Size=UDim2.new(1,-60,1,-6); box.Position=UDim2.new(0,6,0,3); box.BackgroundColor3=Theme.InputBg; box.BorderSizePixel=0; box.Text=""; box.PlaceholderText="Enter pet name..."; box.TextColor3=Theme.Text; box.PlaceholderColor3=Theme.Dim; box.Font=Enum.Font.GothamMedium; box.TextSize=10; box.ClearTextOnFocus=false; box.Parent=holder; box.ZIndex=21; corner(box,4)

    local addBtn=Instance.new("TextButton"); addBtn.Name="WhiteTextBtn"; addBtn.Size=UDim2.new(0,44,0,25); addBtn.Position=UDim2.new(1,-50,0.5,-12.5); addBtn.BackgroundColor3=Theme.Accent; addBtn.Text="ADD"; addBtn.TextColor3=Color3.new(1,1,1); addBtn.Font=Enum.Font.GothamBlack; addBtn.TextSize=10; addBtn.AutoButtonColor=false; addBtn.Parent=holder; addBtn.ZIndex=21; corner(addBtn,5)

    -- Dropdown for autocomplete
    local dropdown = Instance.new("Frame"); dropdown.Name="PriorityDropdown"; dropdown.Size=UDim2.new(1,-60,0,0); dropdown.Position=UDim2.new(0,6,1,2)
    dropdown.BackgroundColor3=Theme.Background; dropdown.BorderSizePixel=0; dropdown.ClipsDescendants=true; dropdown.Visible=false; dropdown.ZIndex=50; dropdown.Parent=holder; corner(dropdown,6)
    local ddStroke = Instance.new("UIStroke"); ddStroke.Color=Theme.AccentLight; ddStroke.Thickness=1; ddStroke.Parent=dropdown
    local ddScroll = Instance.new("ScrollingFrame"); ddScroll.Size=UDim2.new(1,0,1,0); ddScroll.BackgroundTransparency=1; ddScroll.BorderSizePixel=0; ddScroll.ScrollBarThickness=3; ddScroll.ScrollBarImageColor3=Theme.Accent; ddScroll.CanvasSize=UDim2.new(0,0,0,0); ddScroll.Active=true; ddScroll.ZIndex=51; ddScroll.Parent=dropdown
    local ddLayout = Instance.new("UIListLayout"); ddLayout.Padding=UDim.new(0,1); ddLayout.Parent=ddScroll
    ddLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() ddScroll.CanvasSize=UDim2.new(0,0,0,ddLayout.AbsoluteContentSize.Y) end)

    local function addName(name)
        local trimmed = name:match("^%s*(.-)%s*$")
        if not trimmed or trimmed == "" then return end
        local exists = false
        for _, pName in ipairs(priorityList) do if pName == trimmed then exists = true; break end end
        if not exists then
            table.insert(priorityList, trimmed)
            if Config.RemovedFromPriority then
                for i=#Config.RemovedFromPriority,1,-1 do
                    if Config.RemovedFromPriority[i] == trimmed then table.remove(Config.RemovedFromPriority, i) end
                end
            end
            Config.PriorityList=priorityList; saveConfig()
        end
        box.Text=""; dropdown.Visible=false; loadTab("Priority")
    end

    local function updateDropdown(query)
        for _, c in ipairs(ddScroll:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
        if not query or query == "" then dropdown.Visible = false; return end
        local names = getAllAnimalNames()
        local q = query:lower()
        local matches = {}
        for _, name in ipairs(names) do
            if name:lower():find(q, 1, true) then
                local exists = false
                for _, pName in ipairs(priorityList) do if pName == name then exists = true; break end end
                if not exists then table.insert(matches, name); if #matches >= 8 then break end end
            end
        end
        if #matches == 0 then dropdown.Visible = false; return end
        local itemH = 24
        dropdown.Size = UDim2.new(1,-60,0,math.min(#matches,6)*itemH)
        dropdown.Visible = true
        for _, name in ipairs(matches) do
            local btn = Instance.new("TextButton"); btn.Size=UDim2.new(1,0,0,itemH); btn.BackgroundColor3=Theme.Row; btn.BackgroundTransparency=0.1; btn.Text=name; btn.TextColor3=Theme.Text; btn.Font=Enum.Font.GothamMedium; btn.TextSize=10; btn.AutoButtonColor=false; btn.ZIndex=52; btn.Parent=ddScroll
            btn.MouseEnter:Connect(function() btn.BackgroundColor3=Theme.RowHover end)
            btn.MouseLeave:Connect(function() btn.BackgroundColor3=Theme.Row end)
            btn.MouseButton1Click:Connect(function() addName(name) end)
        end
    end

    box:GetPropertyChangedSignal("Text"):Connect(function() updateDropdown(box.Text) end)
    box.FocusLost:Connect(function() task.delay(0.15, function() dropdown.Visible = false end) end)
    box.Focused:Connect(function() if box.Text ~= "" then updateDropdown(box.Text) end end)

    addBtn.MouseButton1Click:Connect(function() addName(box.Text) end)
end

function makePriorityRestoreRow()
    if not Config.RemovedFromPriority or #Config.RemovedFromPriority == 0 then return end
    local row=Instance.new("Frame"); row.Size=UDim2.new(1,-4,0,31); row.BackgroundColor3=Theme.SoftAccent; row.BackgroundTransparency=0.1; row.Parent=mainBody; corner(row,6); row.LayoutOrder = -1
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-96,1,0); l.Position=UDim2.new(0,8,0,0); l.BackgroundTransparency=1; l.Text=tostring(#Config.RemovedFromPriority).." ignored pet(s) available"; l.TextColor3=Theme.Dim; l.Font=Enum.Font.GothamMedium; l.TextSize=10; l.TextXAlignment=Enum.TextXAlignment.Left; l.Parent=row
    local restBtn=Instance.new("TextButton"); restBtn.Name="WhiteTextBtn"; restBtn.Size=UDim2.new(0,74,0,25); restBtn.Position=UDim2.new(1,-80,0.5,-12.5); restBtn.BackgroundColor3=Theme.Green; restBtn.Text="RESTORE"; restBtn.TextColor3=Color3.new(1,1,1); restBtn.Font=Enum.Font.GothamBlack; restBtn.TextSize=10; restBtn.AutoButtonColor=false; restBtn.Parent=row; corner(restBtn,5)
    restBtn.MouseButton1Click:Connect(function()
        for _, name in ipairs(Config.RemovedFromPriority) do
            local exists = false
            for _, pName in ipairs(priorityList) do
                if pName == name then exists = true; break end
            end
            if not exists then table.insert(priorityList, name) end
        end
        Config.RemovedFromPriority = {}
        Config.PriorityList = priorityList
        saveConfig()
        loadTab("Priority")
    end)
end

function loadTab(tabName)
    UI.CurrentTab=tabName; clearBody(mainBody)
    pcall(function() mainBody:FindFirstChildOfClass("UIListLayout").SortOrder = Enum.SortOrder.LayoutOrder end)
    for name,btn in pairs(tabButtons) do
        btn.TextColor3=name==tabName and Theme.Accent or Theme.Dim
        btn.Font=name==tabName and Enum.Font.GothamBlack or Enum.Font.GothamMedium
    end
    if tabButtons[tabName] and tabUnderline then
        tw(tabUnderline, {Position=UDim2.new(0,tabButtons[tabName].Position.X.Offset,1,-2)}, 0.15)
    end

    if tabName=="Keybinds" then
        makeSectionLabel(mainBody,"Keybinds")
        -- NO Steal Speed keybind, NO Unwalk
        for _,name in ipairs({"Kick","Rejoin Job ID","Clone","Manual TP","Invisible Steal","Job ID","Proximity","Carpet Boost","Open Menu","Ragdoll Self","Drop Brainrot","Float","Reset","Auto Buy","Click to AP"}) do makeKeybindRow(mainBody,name) end

    elseif tabName=="Auto TP" then
        makeSectionLabel(mainBody,"Targeting Mode")
        makeMainToggle(mainBody,"Auto TP Priority Mode",Config.AutoTPPriority,function(on)
            Config.AutoTPPriority=on
            if on then
                if BoundToggles["Auto TP Highest Gen"] then BoundToggles["Auto TP Highest Gen"](false, false) end
                if BoundToggles["Auto TP Highest Value"] then BoundToggles["Auto TP Highest Value"](false, false) end
                Config.AutoTPHighestGen = false
                Config.AutoTPHighestValue = false
            end
            saveConfig()
        end)
        makeMainToggle(mainBody,"Auto TP Highest Gen",Config.AutoTPHighestGen,function(on)
            Config.AutoTPHighestGen=on
            if on then
                if BoundToggles["Auto TP Priority Mode"] then BoundToggles["Auto TP Priority Mode"](false, false) end
                if BoundToggles["Auto TP Highest Value"] then BoundToggles["Auto TP Highest Value"](false, false) end
                Config.AutoTPPriority = false
                Config.AutoTPHighestValue = false
            end
            saveConfig()
        end)
        makeMainToggle(mainBody,"Auto TP Highest Value",Config.AutoTPHighestValue,function(on)
            Config.AutoTPHighestValue=on
            if on then
                if BoundToggles["Auto TP Priority Mode"] then BoundToggles["Auto TP Priority Mode"](false, false) end
                if BoundToggles["Auto TP Highest Gen"] then BoundToggles["Auto TP Highest Gen"](false, false) end
                Config.AutoTPPriority = false
                Config.AutoTPHighestGen = false
            end
            saveConfig()
        end)
        makeSectionLabel(mainBody,"TP Options")
        makeMainToggle(mainBody,"TP on Load",Config.TpSettings.TpOnLoad,function(on) Config.TpSettings.TpOnLoad=on; saveConfig() end)
        makeSectionLabel(mainBody,"Tool")
        -- TP Tool selection (radio button style)
        local toolOptions={"Flying Carpet","Cupid's Wings","Santa's Sleigh","Witch's Broom","Waverider"}
        local toolToggles={}
        for _,tn in ipairs(toolOptions) do
            toolToggles[tn]=makeMainToggle(mainBody,tn,Config.TpSettings.Tool==tn,function(on)
                if on then
                    Config.TpSettings.Tool=tn; saveConfig(); ShowNotification("TP TOOL",tn)
                    for otn,otf in pairs(toolToggles) do if otn~=tn then otf(false,false) end end
                end
            end)
        end
        makeSectionLabel(mainBody,"TP Method")
        -- TP Version
        makeMainToggle(mainBody,"Fly TP",Config.TpSettings.FlyTP,function(on)
            Config.TpSettings.FlyTP=on
            if on then
                Config.TpSettings.GrabbleTP = false
                if BoundToggles["Grabble TP"] then BoundToggles["Grabble TP"](false, false) end
            end
            saveConfig()
        end)
        makeMainToggle(mainBody,"Grabble TP",Config.TpSettings.GrabbleTP,function(on)
            Config.TpSettings.GrabbleTP=on
            if on then
                Config.TpSettings.FlyTP = false
                if BoundToggles["Fly TP"] then BoundToggles["Fly TP"](false, false) end
            end
            saveConfig()
            -- Grabble TP IS the SXE Clone-TP engine. Sync auto-steal loop state.
            if _G.SXEAutoSteal then
                pcall(_G.SXEAutoSteal, on and (Config.AutoStealEnabled or false))
            end
        end)
        makeMainToggle(mainBody,"Carpet to Brainrot",Config.TpSettings.BrainrotCarpet,function(on) Config.TpSettings.BrainrotCarpet=on; saveConfig() end)

        makeSectionLabel(mainBody,"Advanced")
        makeMainButton(mainBody, "Tp Speed", function()
            if tpSpeedSettingsPanel.Visible then closeAnim(tpSpeedSettingsPanel) else openAnim(tpSpeedSettingsPanel) end
        end, Theme.Panel)
        makeMainTextBox(mainBody,"Min Gen for Auto TP",Config.TpSettings.MinGenForTp,"e.g. 50k, 1m, 10b",function(v)
            Config.TpSettings.MinGenForTp = v
            saveConfig()
            ShowNotification("MIN GEN TP", v == "" and "No minimum" or "Min: " .. v)
        end)

    elseif tabName=="ESP" then

        makeSectionLabel(mainBody,"ESP")
        makeMainToggle(mainBody,"Player ESP",playerESPEnabled,function(on) playerESPEnabled=on; Config.PlayerESP=on; saveConfig(); if on then task.spawn(function() for _,pl in ipairs(Players:GetPlayers()) do if pl~=LocalPlayer then pcall(createOrRefreshPlayerESP,pl) end end end) else clearPlayerESP() end end)
        makeMainToggle(mainBody,"Brainrot ESP",brainrotESPEnabled,function(on) brainrotESPEnabled=on; Config.BrainrotESP=on; saveConfig(); if on then task.spawn(function() pcall(refreshBrainrotESP) end) else clearBrainrotESP() end end)
        makeSyncMainToggle(mainBody,"Timer ESP","Timer ESP",function(on)
            timerESPEnabled=on
            Config.TimerESP=on
            saveConfig()
            if on then task.spawn(function() pcall(refreshTimerESP) end) else clearTimerESP() end
        end)
        makeMainToggle(mainBody,"Subspace Mine ESP",subspaceMineESPEnabled,function(on) subspaceMineESPEnabled=on; Config.SubspaceMineESP=on; saveConfig() end)
        makeMainToggle(mainBody,"Base Owner ESP",Config.BaseOwnerESP,function(on) if _G.setBaseOwnerESP then _G.setBaseOwnerESP(on) end end)
        makeSectionLabel(mainBody,"Beams")
        makeMainToggle(mainBody,"Line To Base",Config.LineToBase,function(on)
            Config.LineToBase=on; saveConfig()
            if on then if _G.createPlotBeam then pcall(_G.createPlotBeam) end
            else if _G.resetPlotBeam then pcall(_G.resetPlotBeam) end end
        end)
        makeMainToggle(mainBody,"Line To Best Brainrot",Config.LineToBrainrot or false,function(on)
            Config.LineToBrainrot=on; saveConfig()
            if on then -- beam auto-creates via heartbeat
            else if _G.resetBrainrotBeam then pcall(_G.resetBrainrotBeam) end end
        end)

    elseif tabName=="UI" then
        makeSectionLabel(mainBody,"Panels")
        for _,name in ipairs({"Invisible Steal Panel","Admin Command Panel","Command Cooldowns","Actions","Steal Panel","Steal Target"}) do
            makeMainToggle(mainBody,name,panels[name].Visible,function(on)
                Config.Visibilities[name]=on
                saveConfig()
                if on then openAnim(panels[name]) else closeAnim(panels[name]) end
            end)
        end
        makeSectionLabel(mainBody,"Interface")
        makeMainToggle(mainBody,"Remote Sell Panel",Config.RemoteSellEnabled,function(on) if _G.toggleRemoteSell then _G.toggleRemoteSell(on) end end)
        makeMainToggle(mainBody,"Clear Error Popups",Config.CleanErrorGUIs,function(on) Config.CleanErrorGUIs=on; saveConfig() end)
        makeMainToggle(mainBody,"Auto Close Main UI on Execute",Config.AutoCloseOnExec,function(on) Config.AutoCloseOnExec=on; saveConfig() end)
        makeMainToggle(mainBody,"Admin Panel UI",Config.AdminPanelUI ~= nil and Config.AdminPanelUI or true,function(on)
            Config.AdminPanelUI = on
            saveConfig()
            if apGui then apGui.Enabled = on end
        end)
        makeSectionLabel(mainBody,"Config")
        local shareRow = Instance.new("Frame")
        shareRow.Size = UDim2.new(1, -4, 0, 31)
        shareRow.BackgroundColor3 = Theme.Panel
        shareRow.BackgroundTransparency = 0.18
        shareRow.Parent = mainBody
        corner(shareRow, 6)
        
        local shareBox = Instance.new("TextBox")
        shareBox.Size = UDim2.new(1, -12, 1, -6)
        shareBox.Position = UDim2.new(0, 6, 0, 3)
        shareBox.BackgroundColor3 = Theme.InputBg
        shareBox.BorderSizePixel = 0
        shareBox.Text = ""
        shareBox.PlaceholderText = "Paste config here to import, or click Export..."
        shareBox.TextColor3 = Theme.Text
        shareBox.Font = Enum.Font.GothamMedium
        shareBox.TextSize = 9
        shareBox.ClearTextOnFocus = false
        shareBox.Parent = shareRow
        corner(shareBox, 4)

        local btnRow = Instance.new("Frame")
        btnRow.Size = UDim2.new(1, -4, 0, 30)
        btnRow.BackgroundTransparency = 1
        btnRow.Parent = mainBody
        
        local expBtn = Instance.new("TextButton")
        expBtn.Size = UDim2.new(0.5, -3, 1, 0)
        expBtn.Position = UDim2.new(0, 0, 0, 0)
        expBtn.BackgroundColor3 = Theme.Row
        expBtn.BackgroundTransparency = 0.16
        expBtn.Text = "Export Config"
        expBtn.TextColor3 = Theme.Text
        expBtn.Font = Enum.Font.GothamBold
        expBtn.TextSize = 11
        expBtn.AutoButtonColor = false
        expBtn.Parent = btnRow
        corner(expBtn, 6)
        stroke(expBtn, Theme.AccentLight, 1, 0.28)
        expBtn.MouseEnter:Connect(function() tw(expBtn, {BackgroundColor3 = Theme.RowHover}, 0.12) end)
        expBtn.MouseLeave:Connect(function() tw(expBtn, {BackgroundColor3 = Theme.Row}, 0.12) end)
        expBtn.MouseButton1Click:Connect(function()
            local str = _G.exportConfig()
            if str then
                shareBox.Text = str
            end
        end)
        
        local impBtn = Instance.new("TextButton")
        impBtn.Size = UDim2.new(0.5, -3, 1, 0)
        impBtn.Position = UDim2.new(0.5, 3, 0, 0)
        impBtn.BackgroundColor3 = Theme.Row
        impBtn.BackgroundTransparency = 0.16
        impBtn.Text = "Import Config"
        impBtn.TextColor3 = Theme.Text
        impBtn.Font = Enum.Font.GothamBold
        impBtn.TextSize = 11
        impBtn.AutoButtonColor = false
        impBtn.Parent = btnRow
        corner(impBtn, 6)
        stroke(impBtn, Theme.AccentLight, 1, 0.28)
        impBtn.MouseEnter:Connect(function() tw(impBtn, {BackgroundColor3 = Theme.RowHover}, 0.12) end)
        impBtn.MouseLeave:Connect(function() tw(impBtn, {BackgroundColor3 = Theme.Row}, 0.12) end)
        impBtn.MouseButton1Click:Connect(function()
            _G.importConfig(shareBox.Text)
        end)

        -- White Mode / Dark Mode buttons removed â€” dark mode only
        -- (Theme is always dark)

        makeSectionLabel(mainBody,"Layout")
        local rb=makeMainButton(mainBody,"Reset UI",function()
            main.Position=UDim2.new(0.5,-300,0.5,-255); panels["Invisible Steal Panel"].Position=UDim2.new(0,80,0.5,-220)
            panels["Admin Command Panel"].Position=UDim2.new(0.5,85,1,-340); panels["Command Cooldowns"].Position=UDim2.new(0.5,245,1,-390)
            panels["Actions"].Position=UDim2.new(0.5,505,1,-415); panels["Steal Panel"].Position=UDim2.new(1,-400,1,-385)
            panels["Steal Target"].Position=UDim2.new(1,-430,0,85); actionSettingsPanel.Position=UDim2.new(0.5,745,1,-440)
            bottomBar.Position=UDim2.new(0.5,-287,1,-125); Config.positions={}; saveConfig()
        end)
        local lockBtn; lockBtn=makeMainButton(mainBody,UI.Locked and "Locked" or "Unlocked",function() UI.Locked=not UI.Locked; Config.locked=UI.Locked; saveConfig(); lockBtn.Text=UI.Locked and "Locked" or "Unlocked" end,Theme.SoftButton)
        
        makeSectionLabel(mainBody,"Alerts")
        makeMainToggle(mainBody,"Priority Sound Alert",Config.PrioritySoundAlert,function(on) Config.PrioritySoundAlert=on; saveConfig() end)
        makeMainTextBox(mainBody,"Custom Sound ID",Config.PrioritySoundID or "e.g. 123456789","e.g. 123456789",function(v) Config.PrioritySoundID=v; saveConfig() end)

    elseif tabName=="Misc" then
        -- NO Unwalk, NO Steal Speed, NO FPS Boost (moved to Performance)
        makeSectionLabel(mainBody,"General")
        makeMainToggle(mainBody,"Instant Clone",true)
        -- Desync removed
        makeSectionLabel(mainBody,"Steal")
        makeMainToggle(mainBody,"Auto Invisible During Steal",Config.AutoInvisDuringSteal,function(on) _G.AutoInvisDuringSteal=on; Config.AutoInvisDuringSteal=on; saveConfig() end)
        makeMainToggle(mainBody,"Auto Unlock During Steal",Config.AutoUnlockOnSteal,function(on) Config.AutoUnlockOnSteal=on; saveConfig() end)
        makeSyncMainToggle(mainBody,"Anti Ragdoll","Anti Ragdoll",function(on) if on then startAntiRagdoll() else stopAntiRagdoll() end end)
        makeSyncMainToggle(mainBody,"Auto Reset Balloon","Auto Reset Balloon",function(on) Config.AutoResetBalloon=on; saveConfig() end)
        makeSyncMainToggle(mainBody,"Infinite Jump","Infinite Jump",function(on) setInfiniteJump(on) end)
        makeSyncMainToggle(mainBody,"Auto Kick On Steal","Auto Kick",function(on) Config.AutoKickOnSteal=on; saveConfig() end)
        makeSectionLabel(mainBody,"Server")
        makeMainToggle(mainBody,"Kick to Private Server",Config.KickToPrivateServer,function(on) Config.KickToPrivateServer=on; saveConfig() end)
        makeMainTextBox(mainBody,"Private Server Code",PrivateServerCode,"e.g. ABC123XYZ...",function(v) PrivateServerCode=v; savePSCode() end)
        makeSectionLabel(mainBody,"Movement")
        makeSyncMainToggle(mainBody,"Unwalk","Unwalk",function(on) if _G.setUnwalk then _G.setUnwalk(on) end end)
        makeSyncMainToggle(mainBody,"Invisible Steal","Invisible Steal",function(on) if _G.toggleInvisibleSteal then pcall(_G.toggleInvisibleSteal) end end)
        makeSyncMainToggle(mainBody,"Float","Float",function(on) setFloat(on) end)
        makeSyncMainToggle(mainBody,"Carpet Speed","Carpet Speed",function(on) setCarpetSpeed(on) end)
        makeSectionLabel(mainBody,"Admin")
        makeSyncMainToggle(mainBody,"Click to AP","ClickToAP",function(on) Config.ClickToAP=on; saveConfig() end)

        -- Helper: create a config panel with toggles + ordering for AP commands
        local function makeAPConfigPanel(panelKey, titleText, configTable, orderKey, onToggleCb)
            if panels[panelKey] then
                panels[panelKey].Visible = not panels[panelKey].Visible
                return
            end

            -- Initialize order from config or default
            if not Config[orderKey] then
                Config[orderKey] = {}
                for i, cmd in ipairs(AP_ALL_COMMANDS) do Config[orderKey][i] = cmd end
            end
            local cmdOrder = Config[orderKey]

            local cfgPanel = Instance.new("Frame")
            cfgPanel.Name = panelKey
            cfgPanel.Size = UDim2.fromOffset(240, 0)
            cfgPanel.AutomaticSize = Enum.AutomaticSize.Y
            cfgPanel.Position = panelKey == "AdminPanelCmds" and UDim2.new(0.5, 200, 0.5, -200) or UDim2.new(0.5, 200, 0.5, -50)
            cfgPanel.BackgroundColor3 = Theme.Background
            cfgPanel.BackgroundTransparency = 0.04
            cfgPanel.BorderSizePixel = 0
            cfgPanel.ZIndex = 100 -- High ZIndex to stay on top
            cfgPanel.Parent = gui_sg -- Parent to ScreenGui to act as a floating popup
            panels[panelKey] = cfgPanel
            corner(cfgPanel, 10)
            stroke(cfgPanel, Theme.Accent, 1.5, 0.3)
            makeDraggable(cfgPanel, cfgPanel)

            local cfgTitleLbl = Instance.new("TextLabel")
            cfgTitleLbl.Size = UDim2.new(1, 0, 0, 28)
            cfgTitleLbl.BackgroundColor3 = Theme.Panel
            cfgTitleLbl.BackgroundTransparency = 0.3
            cfgTitleLbl.Text = titleText
            cfgTitleLbl.TextColor3 = Theme.Text
            cfgTitleLbl.Font = Enum.Font.GothamBold
            cfgTitleLbl.TextSize = 12
            cfgTitleLbl.ZIndex = 101 -- Fix: Render on top of panel
            cfgTitleLbl.Parent = cfgPanel
            corner(cfgTitleLbl, 8)

            local cfgBody = Instance.new("Frame")
            cfgBody.Size = UDim2.new(1, -8, 0, 0)
            cfgBody.AutomaticSize = Enum.AutomaticSize.Y
            cfgBody.Position = UDim2.fromOffset(4, 32)
            cfgBody.BackgroundTransparency = 1
            cfgBody.ZIndex = 101 -- Fix: Render on top of panel
            cfgBody.Parent = cfgPanel
            Instance.new("UIListLayout", cfgBody).SortOrder = Enum.SortOrder.LayoutOrder
            cfgBody:FindFirstChildOfClass("UIListLayout").Padding = UDim.new(0, 2)

            local rowMap = {} -- cmd -> row frame
            local numMap = {} -- cmd -> number label

            local function refreshNumbers()
                for i, cmd in ipairs(cmdOrder) do
                    if rowMap[cmd] then rowMap[cmd].LayoutOrder = i end
                    if numMap[cmd] then numMap[cmd].Text = tostring(i) end
                end
            end

            local function swapOrder(idx1, idx2)
                if idx1 < 1 or idx2 < 1 or idx1 > #cmdOrder or idx2 > #cmdOrder then return end
                cmdOrder[idx1], cmdOrder[idx2] = cmdOrder[idx2], cmdOrder[idx1]
                Config[orderKey] = cmdOrder
                saveConfig()
                refreshNumbers()
            end

            for idx, cmd in ipairs(cmdOrder) do
                local emoji = AP_COMMAND_EMOJIS[cmd] or "⚡"
                local isOn = configTable[cmd] == true
                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, 0, 0, 28)
                row.BackgroundColor3 = Theme.Panel
                row.BackgroundTransparency = 0.4
                row.LayoutOrder = idx
                row.ZIndex = 102 -- Fix: Render on top of body
                row.Parent = cfgBody
                corner(row, 5)
                rowMap[cmd] = row

                -- Number label
                local numLbl = Instance.new("TextLabel")
                numLbl.Size = UDim2.fromOffset(16, 28)
                numLbl.Position = UDim2.fromOffset(2, 0)
                numLbl.BackgroundTransparency = 1
                numLbl.Text = tostring(idx)
                numLbl.TextColor3 = Theme.Dim
                numLbl.Font = Enum.Font.GothamBold
                numLbl.TextSize = 10
                numLbl.ZIndex = 103
                numLbl.Parent = row
                numMap[cmd] = numLbl

                -- Up arrow
                local upBtn = Instance.new("TextButton")
                upBtn.Size = UDim2.fromOffset(16, 13)
                upBtn.Position = UDim2.fromOffset(18, 1)
                upBtn.BackgroundTransparency = 1
                upBtn.Text = "▲"
                upBtn.TextColor3 = Theme.AccentLight
                upBtn.Font = Enum.Font.GothamBold
                upBtn.TextSize = 8
                upBtn.AutoButtonColor = false
                upBtn.ZIndex = 103
                upBtn.Parent = row

                -- Down arrow
                local dnBtn = Instance.new("TextButton")
                dnBtn.Size = UDim2.fromOffset(16, 13)
                dnBtn.Position = UDim2.fromOffset(18, 14)
                dnBtn.BackgroundTransparency = 1
                dnBtn.Text = "▼"
                dnBtn.TextColor3 = Theme.AccentLight
                dnBtn.Font = Enum.Font.GothamBold
                dnBtn.TextSize = 8
                dnBtn.AutoButtonColor = false
                dnBtn.ZIndex = 103
                dnBtn.Parent = row

                upBtn.MouseButton1Click:Connect(function()
                    local curIdx
                    for i, c in ipairs(cmdOrder) do if c == cmd then curIdx = i; break end end
                    if curIdx and curIdx > 1 then swapOrder(curIdx, curIdx - 1) end
                end)
                dnBtn.MouseButton1Click:Connect(function()
                    local curIdx
                    for i, c in ipairs(cmdOrder) do if c == cmd then curIdx = i; break end end
                    if curIdx and curIdx < #cmdOrder then swapOrder(curIdx, curIdx + 1) end
                end)

                -- Command label
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, -90, 1, 0)
                lbl.Position = UDim2.fromOffset(36, 0)
                lbl.BackgroundTransparency = 1
                lbl.Text = emoji .. " " .. cmd
                lbl.TextColor3 = Theme.Text
                lbl.Font = Enum.Font.GothamMedium
                lbl.TextSize = 11
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.ZIndex = 103
                lbl.Parent = row

                -- Toggle button
                local btn = Instance.new("TextButton")
                btn.Size = UDim2.fromOffset(36, 18)
                btn.Position = UDim2.new(1, -42, 0.5, -9)
                btn.BackgroundColor3 = isOn and Theme.Green or Theme.ToggleOff
                btn.Text = isOn and "ON" or "OFF"
                btn.TextColor3 = Color3.new(1, 1, 1)
                btn.Font = Enum.Font.GothamBold
                btn.TextSize = 9
                btn.AutoButtonColor = false
                btn.ZIndex = 103
                btn.Parent = row
                corner(btn, 5)

                btn.MouseButton1Click:Connect(function()
                    isOn = not isOn
                    configTable[cmd] = isOn
                    saveConfig()
                    btn.BackgroundColor3 = isOn and Theme.Green or Theme.ToggleOff
                    btn.Text = isOn and "ON" or "OFF"
                    if onToggleCb then onToggleCb(cmd, isOn) end
                end)
            end

            if panelKey == "ClickToAPCmds" then
                local function setZIndex(inst)
                    if inst:IsA("GuiObject") then
                        inst.ZIndex = 103
                    end
                    for _, child in ipairs(inst:GetChildren()) do
                        setZIndex(child)
                    end
                end

                local sep = Instance.new("Frame")
                sep.Size = UDim2.new(1, -8, 0, 1)
                sep.Position = UDim2.new(0, 4, 0, 0)
                sep.BackgroundColor3 = Theme.Stroke
                sep.BackgroundTransparency = 0.2
                sep.LayoutOrder = 1000
                sep.ZIndex = 103
                sep.Parent = cfgBody

                local subHeader = Instance.new("TextLabel")
                subHeader.Size = UDim2.new(1, 0, 0, 24)
                subHeader.BackgroundTransparency = 1
                subHeader.Text = "Settings"
                subHeader.TextColor3 = Theme.Accent
                subHeader.Font = Enum.Font.GothamBold
                subHeader.TextSize = 10
                subHeader.LayoutOrder = 1001
                subHeader.ZIndex = 103
                subHeader.Parent = cfgBody

                local sliderWrapper = Instance.new("Frame")
                sliderWrapper.Size = UDim2.new(1, 0, 0, 50)
                sliderWrapper.BackgroundTransparency = 1
                sliderWrapper.LayoutOrder = 1002
                sliderWrapper.Parent = cfgBody

                local sliderObj = makeQuickSlider(sliderWrapper, "Click Radius", 1, 50, Config.ClickToAPRadius or 8, function(v)
                    Config.ClickToAPRadius = v
                    saveConfig()
                end, " studs")
                setZIndex(sliderWrapper)
            end

            if panelKey == "SpamBaseOwnerCmds" then
                local function setZIndex(inst)
                    if inst:IsA("GuiObject") then
                        inst.ZIndex = 103
                    end
                    for _, child in ipairs(inst:GetChildren()) do
                        setZIndex(child)
                    end
                end

                local sep = Instance.new("Frame")
                sep.Size = UDim2.new(1, -8, 0, 1)
                sep.Position = UDim2.new(0, 4, 0, 0)
                sep.BackgroundColor3 = Theme.Stroke
                sep.BackgroundTransparency = 0.2
                sep.LayoutOrder = 1000
                sep.ZIndex = 103
                sep.Parent = cfgBody

                local subHeader = Instance.new("TextLabel")
                subHeader.Size = UDim2.new(1, 0, 0, 24)
                subHeader.BackgroundTransparency = 1
                subHeader.Text = "Settings"
                subHeader.TextColor3 = Theme.Accent
                subHeader.Font = Enum.Font.GothamBold
                subHeader.TextSize = 10
                subHeader.LayoutOrder = 1001
                subHeader.ZIndex = 103
                subHeader.Parent = cfgBody

                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, 0, 0, 34)
                row.BackgroundTransparency = 1
                row.LayoutOrder = 1002
                row.Parent = cfgBody

                local toggleFunc = makeSyncStateRow(row, "Single Command:", "SpamBaseOwnerSingleCommand", function(on)
                    Config.SpamBaseOwnerSingleCommand = on
                    saveConfig()
                end)
                setZIndex(row)
            end

            local pad = Instance.new("Frame")
            pad.Size = UDim2.new(1, 0, 0, 6)
            pad.BackgroundTransparency = 1
            pad.LayoutOrder = 1004
            pad.Parent = cfgBody
        end

        -- Admin Panel Commands button (controls which buttons show per player in admin panel)
        makeMainButton(mainBody, "Admin Panel Commands", function()
            makeAPConfigPanel("AdminPanelCmds", "Admin Panel Commands", Config.AdminPanelButtons, "AdminPanelOrder", function()
                if _G.refreshAdminPanelRows then _G.refreshAdminPanelRows() end
            end)
        end)

        -- Click to AP Commands button (controls which commands fire when you click a player)
        makeMainButton(mainBody, "Click to AP Commands", function()
            makeAPConfigPanel("ClickToAPCmds", "Click to AP Commands", Config.ClickToAPCommands, "ClickToAPOrder")
        end)

        -- Spam Base Owner Commands button
        makeMainButton(mainBody, "Spam Base Owner Commands", function()
            makeAPConfigPanel("SpamBaseOwnerCmds", "Spam Base Owner Commands", Config.SpamBaseOwnerCommands, "SpamBaseOwnerOrder")
        end)
        makeSyncMainToggle(mainBody,"Anti-Bee & Anti-Disco","AntiBeeDisco",function(on)
            Config.AntiBeeDisco = on
            saveConfig()
            if on then
                if _G.ANTI_BEE_DISCO and _G.ANTI_BEE_DISCO.Enable then
                    _G.ANTI_BEE_DISCO.Enable()
                end
            else
                if _G.ANTI_BEE_DISCO and _G.ANTI_BEE_DISCO.Disable then
                    _G.ANTI_BEE_DISCO.Disable()
                end
            end
        end)
        makeMainTextBox(mainBody,"Min Gen for Nearest Grab",Config.TpSettings.MinGenForGrab,"e.g. 10k, 500k, 1m",function(v)
            Config.TpSettings.MinGenForGrab = v
            saveConfig()
            ShowNotification("MIN GEN GRAB", v == "" and "No minimum" or "Min: " .. v)
        end)

    elseif tabName=="Priority" then
        makeSectionLabel(mainBody,"Priority List")
        makePriorityAddRow(); makePriorityRestoreRow(); for i=1,#priorityList do makePriorityRow(i) end

    elseif tabName=="Performance" then
        makeSectionLabel(mainBody,"Performance")
        makeSyncMainToggle(mainBody,"FPS Boost (normal)","FPS Boost (normal)",function(on) setFPSBoost(on) end)
        makeSyncMainToggle(mainBody,"FPS Boost Ultra","FPSBoostUltra",function(on) setFPSBoostUltra(on) end)
        makeSyncMainToggle(mainBody,"Xray","XRay",function(on) setXRay(on) end)
        makeQuickSlider(mainBody,"FOV",50,120,Config.FOV or 70,function(v) Config.FOV=v; saveConfig(); pcall(function() Workspace.CurrentCamera.FieldOfView=v end) end)

        makeSectionLabel(mainBody,"Phone")
        makeMainButton(mainBody,"Open Phone",function()
            if _G.SXEPhoneFrame then _G.SXEPhoneFrame.Visible = not _G.SXEPhoneFrame.Visible end
        end)
    end

    local idx = 0
    for _, child in ipairs(mainBody:GetChildren()) do
        if child:IsA("GuiObject") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            idx = idx + 1
            child.LayoutOrder = idx
        end
    end
end

for tabName,btn in pairs(tabButtons) do btn.MouseButton1Click:Connect(function() loadTab(tabName) end) end

-- BOTTOM BAR
bottomBar=Instance.new("Frame"); bottomBar.Size=UDim2.new(0,575,0,50); bottomBar.Position=UDim2.new(0.5,-287,1,-125); bottomBar.BackgroundColor3=Theme.Background; bottomBar.BackgroundTransparency=0.02; bottomBar.BorderSizePixel=0; bottomBar.Parent=gui; corner(bottomBar,12); addOutline(bottomBar); addCyberCorners(bottomBar)
local iw=Instance.new("Frame"); iw.Size=UDim2.new(0,34,0,34); iw.Position=UDim2.new(0,12,0.5,-17); iw.BackgroundColor3=Color3.fromRGB(18,4,4); iw.BorderSizePixel=0; iw.ClipsDescendants=true; iw.Parent=bottomBar; corner(iw,8)
local iwGrad=Instance.new("UIGradient"); iwGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(90,14,14)),ColorSequenceKeypoint.new(1,Color3.fromRGB(10,2,2))}); iwGrad.Rotation=50; iwGrad.Parent=iw
local iwStroke=Instance.new("UIStroke"); iwStroke.Color=Color3.fromRGB(220,45,45); iwStroke.Thickness=1.2; iwStroke.Transparency=0.3; iwStroke.Parent=iw

local ic=Instance.new("TextLabel"); ic.Name="LogoIDF"; ic.Size=UDim2.new(1,0,1,0); ic.BackgroundTransparency=1; ic.Text="IDF"; ic.TextColor3=Color3.fromRGB(255,255,255); ic.Font=Enum.Font.GothamBlack; ic.TextSize=13; ic.TextXAlignment=Enum.TextXAlignment.Center; ic.TextYAlignment=Enum.TextYAlignment.Center; ic.ZIndex=3; ic.Parent=iw
local icStroke=Instance.new("UIStroke"); icStroke.Color=Color3.fromRGB(8,2,2); icStroke.Thickness=1; icStroke.Transparency=0.35; icStroke.Parent=ic

local boltA=Instance.new("Frame"); boltA.Name="LogoBoltA"; boltA.Size=UDim2.new(0,3,0,15); boltA.Position=UDim2.new(0,23,0,2); boltA.Rotation=25; boltA.BackgroundColor3=Color3.fromRGB(255,255,255); boltA.BorderSizePixel=0; boltA.ZIndex=2; boltA.Parent=iw; corner(boltA,1)
local boltAGlow=Instance.new("UIStroke"); boltAGlow.Color=Color3.fromRGB(255,255,255); boltAGlow.Thickness=1; boltAGlow.Transparency=0.5; boltAGlow.Parent=boltA
local boltB=Instance.new("Frame"); boltB.Name="LogoBoltB"; boltB.Size=UDim2.new(0,3,0,15); boltB.Position=UDim2.new(0,17,0,14); boltB.Rotation=-25; boltB.BackgroundColor3=Color3.fromRGB(255,255,255); boltB.BorderSizePixel=0; boltB.ZIndex=2; boltB.Parent=iw; corner(boltB,1)
local boltBGlow=Instance.new("UIStroke"); boltBGlow.Color=Color3.fromRGB(255,255,255); boltBGlow.Thickness=1; boltBGlow.Transparency=0.5; boltBGlow.Parent=boltB

_G.updateLogoImage = function(isDark)
    iwStroke.Color = isDark and Color3.fromRGB(220,45,45) or Color3.fromRGB(190,35,35)
    ic.TextColor3 = Color3.fromRGB(255,255,255)
end
_G.updateLogoImage(Config and Config.DarkMode or false)
local lgRow=Instance.new("Frame"); lgRow.Name="BrandRow"; lgRow.Size=UDim2.new(0,200,0,26); lgRow.Position=UDim2.new(0,54,0,5); lgRow.BackgroundTransparency=1; lgRow.Parent=bottomBar
local lgLay=Instance.new("UIListLayout"); lgLay.FillDirection=Enum.FillDirection.Horizontal; lgLay.VerticalAlignment=Enum.VerticalAlignment.Center; lgLay.SortOrder=Enum.SortOrder.LayoutOrder; lgLay.Parent=lgRow
local lg=Instance.new("TextLabel"); lg.Name="BrandAccent"; lg.LayoutOrder=1; lg.AutomaticSize=Enum.AutomaticSize.X; lg.Size=UDim2.new(0,0,1,0); lg.BackgroundTransparency=1; lg.Text="IDF "; lg.TextColor3=Theme.Accent; lg.Font=Enum.Font.GothamBlack; lg.TextSize=19; lg.TextXAlignment=Enum.TextXAlignment.Left; lg.Parent=lgRow
local lg2=Instance.new("TextLabel"); lg2.Name="BrandWhite"; lg2.LayoutOrder=2; lg2.AutomaticSize=Enum.AutomaticSize.X; lg2.Size=UDim2.new(0,0,1,0); lg2.BackgroundTransparency=1; lg2.Text="HUB PRIVAT"; lg2.TextColor3=Theme.Text; lg2.Font=Enum.Font.GothamBlack; lg2.TextSize=19; lg2.TextXAlignment=Enum.TextXAlignment.Left; lg2.Parent=lgRow
local dd=Instance.new("TextLabel"); dd.Size=UDim2.new(0,20,0,26); dd.Position=UDim2.new(0,210,0,5); dd.BackgroundTransparency=1; dd.Text="|"; dd.TextColor3=Theme.AccentLight; dd.Font=Enum.Font.GothamBlack; dd.TextSize=18; dd.Parent=bottomBar
local dc=Instance.new("TextLabel"); dc.Size=UDim2.new(0,210,0,26); dc.Position=UDim2.new(0,230,0,5); dc.BackgroundTransparency=1; dc.Text="discord.gg/idfhub"; dc.TextColor3=Theme.AccentLight; dc.Font=Enum.Font.GothamBold; dc.TextSize=16; dc.TextXAlignment=Enum.TextXAlignment.Left; dc.Parent=bottomBar
local sb=Instance.new("TextLabel"); sb.Size=UDim2.new(0,290,0,14); sb.Position=UDim2.new(0,55,0,30); sb.BackgroundTransparency=1; sb.Text="By:@SE67 and @SXLVATORE"; sb.TextColor3=Theme.Dim; sb.Font=Enum.Font.GothamSemibold; sb.TextSize=8; sb.TextXAlignment=Enum.TextXAlignment.Left; sb.Parent=bottomBar
local rightDiv=Instance.new("Frame"); rightDiv.Size=UDim2.new(0,1,0,36); rightDiv.Position=UDim2.new(1,-138,0.5,-18); rightDiv.BackgroundColor3=Theme.Accent; rightDiv.BackgroundTransparency=0.35; rightDiv.BorderSizePixel=0; rightDiv.Parent=bottomBar
fpsText=Instance.new("TextLabel"); fpsText.Size=UDim2.new(0,126,1,0); fpsText.Position=UDim2.new(1,-128,0,0); fpsText.BackgroundTransparency=1; fpsText.Text="FPS: --\nPING: --ms"; fpsText.TextColor3=Theme.Green; fpsText.Font=Enum.Font.GothamBold; fpsText.TextSize=10; fpsText.TextXAlignment=Enum.TextXAlignment.Left; fpsText.Parent=bottomBar
if _G.addLazyUI then _G.addLazyUI(bottomBar, true) end

task.defer(function()
    loadTab("Auto TP")
    rebuildActions(); rebuildActionSettings(); rebuildTpSpeedSettings()
end)

-- FPS/PING COUNTER
local frames,lastT=0,tick()
_G.currentFPS = 60
RunService.RenderStepped:Connect(function() frames=frames+1; local now=tick(); if now-lastT>=1 then local fps=frames; _G.currentFPS=fps; frames=0; lastT=now; local ping=0; pcall(function() ping=math.floor(LocalPlayer:GetNetworkPing() * 1000) end); fpsText.Text="FPS: "..fps.."\nPING: "..ping.."ms" end end)

-- INPUT HANDLER (NO Steal Speed, NO Unwalk keybinds)
UIS.InputBegan:Connect(function(input,gp) if gp then return end; if input.UserInputType~=Enum.UserInputType.Keyboard then return end
    if input.KeyCode==UI.OpenMenuKey then
        if main.Visible then
            closeAnim(main)
            if tpSpeedSettingsPanel and tpSpeedSettingsPanel.Visible then closeAnim(tpSpeedSettingsPanel) end
            if actionSettingsPanel and actionSettingsPanel.Visible then closeAnim(actionSettingsPanel) end
            local apCmds = gui_sg and gui_sg:FindFirstChild("AdminPanelCmds")
            if apCmds and apCmds.Visible then apCmds.Visible = false end
            local clickCmds = gui_sg and gui_sg:FindFirstChild("ClickToAPCmds")
            if clickCmds and clickCmds.Visible then clickCmds.Visible = false end
            local sbOwnerCmds = gui_sg and gui_sg:FindFirstChild("SpamBaseOwnerCmds")
            if sbOwnerCmds and sbOwnerCmds.Visible then sbOwnerCmds.Visible = false end
        else openAnim(main) end
    return end
    local kn=input.KeyCode.Name
    local actions={
        ["Drop Brainrot"]=runDropBrainrot, ["Clone"]=instantClone,
        ["Float"]=function() setFloat(not FloatState.active) end,
        ["Carpet Boost"]=function() setCarpetSpeed(not CarpetState.enabled) end,
        ["Reset"]=executeReset, ["Kick"]=kickPlayer,
        ["Proximity"]=function() ProximityAPActive=not ProximityAPActive; setToggle("Proximity",ProximityAPActive) end,
        ["Ragdoll Self"]=function() pcall(runAdminCommand,player,"ragdoll") end,
        ["Invisible Steal"]=function() if _G.toggleInvisibleSteal then pcall(_G.toggleInvisibleSteal) end end,
        ["Rejoin Job ID"]=function() pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, player) end) end,
        ["Manual TP"]=function() task.spawn(runAutoSnipe) end,
        ["Auto Buy"]=function() toggleAutoBuy() end,
        ["Click to AP"]=function()
            Config.ClickToAP = not Config.ClickToAP
            saveConfig()
            setToggle("Click to AP", Config.ClickToAP)
            setToggle("ClickToAP", Config.ClickToAP)
            ShowNotification("CLICK TO AP", Config.ClickToAP and "Enabled" or "Disabled")
        end,
    }
    for actionName,keyBind in pairs(Keybinds) do if keyBind==kn and actions[actionName] then actions[actionName](); return end end
end)


-- AUTO-EXECUTE FROM CONFIG (Robust Retry Loop)
if Config.TpSettings.TpOnLoad then task.spawn(function()
    local char = player.Character or player.CharacterAdded:Wait()
    char:WaitForChild("HumanoidRootPart", 20)
    char:WaitForChild("Humanoid", 20)
    
    local t = 0
    while (not SharedState.InitialScanComplete or #SharedState.AllAnimalsCache == 0) and t < 150 do
        task.wait(0.1)
        t = t + 1
    end
    task.wait(0.15) -- Extreme optimized network sync wait
    
    local minGen = parseMinGen(Config.TpSettings.MinGenForTp)
    local success = false
    local attempts = 0
    while not success and attempts < 30 do
        attempts = attempts + 1
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
            local targetPetData = getTargetPetData()
            
            if targetPetData then
                local targetPart = findAdorneeGlobal(targetPetData)
                if targetPart then
                    task.spawn(runAutoSnipe)
                    success = true
                    break
                end
            end
        end
        task.wait(0.5)
    end
end) end

task.spawn(function() task.wait(0.5)
    -- Desync removed from startup
    if Config.ClickToAP then Config.ClickToAP = false end
    if Config.AntiRagdoll then startAntiRagdoll() end
    if Config.InfiniteJump then setInfiniteJump(true) end
    if Config.Float then setFloat(true) end
    if Config.Unwalk then setUnwalk(true) end

    if Config.AutoCloseOnExec then if main then main.Visible = false end end
    if Config.FPSBoost then setFPSBoost(true) end
    if Config.FPSBoostUltra then setFPSBoostUltra(true) end
    if Config.XRay then setXRay(true) end
    pcall(function() Workspace.CurrentCamera.FieldOfView = Config.FOV or 70 end)
    if Config.PlayerESP then playerESPEnabled=true end
    if Config.TimerESP then timerESPEnabled=true end
    if Config.SubspaceMineESP then subspaceMineESPEnabled=true end
    -- RemoteSell is initialized inside the lazy UI thread (at the top of the file)
    _G.initRemoteSellLazy = function()
        if Config.RemoteSellEnabled and _G.toggleRemoteSell then
            _G.toggleRemoteSell(true)
        end
    end
    if Config.ProximityAP then setProximityAP(true) end
    if Config.AutoBuyEnabled then toggleAutoBuy(true) end
    if Config.StealHighest then setStealMode("Highest")
    elseif Config.StealPriority then setStealMode("Priority")
    elseif Config.StealNearest then setStealMode("Nearest")
    else setStealMode("Highest") end
    if updateMovementPanelLabels then updateMovementPanelLabels() end
end)

_G.InvisStealAngle=Config.InvisStealAngle or 225; _G.SinkSliderValue=Config.SinkSliderValue or 7
_G.AutoRecoverLagback=true; _G.AutoInvisDuringSteal=Config.AutoInvisDuringSteal or false

print("IDF HUB PRIVAT loaded ")


task.spawn(function()
    while true do
        task.wait(15)
        pcall(collectgarbage, "collect")
    end
end)



RunService.RenderStepped:Connect(function()
    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam and Config.FOV and cam.FieldOfView ~= Config.FOV then
            cam.FieldOfView = Config.FOV
        end
    end)
end)

local function doTP()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    pcall(function()
        if sethiddenproperty then
            local cf = hrp.CFrame
            sethiddenproperty(hrp, "CFrame", CFrame.new(cf.Position.X + 500, cf.Position.Y, cf.Position.Z + 500) * (cf - cf.Position))
            task.wait(0.23)
            sethiddenproperty(hrp, "CFrame", cf)
        end
    end)
end

-- No Player Collision Logic
local lastNoclipUpdate = 0
RunService.Stepped:Connect(function()
    local now = tick()
    if now - lastNoclipUpdate < 0.1 then return end
    lastNoclipUpdate = now
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            for _, part in ipairs(p.Character:GetDescendants()) do
                if part:IsA("BasePart") then 
                    part.CanCollide = false 
                end
            end
        end
    end
end)
local SXE_AC = {} 
end 
   end

task.spawn(function()
    task.wait(0.15)
    pcall(applyTheme, "Vampire")
end)


-- ============================================================
-- SXE AUTO-STEAL + CLONE-TP ENGINE (integrated) -- xentp.lua 1:1 port
-- Speed: Config.TpSettings.GrabbleTPSpeed | Clone Delay: Config.TpSettings.CloneDelayVal
-- ============================================================
do
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UIS        = game:GetService("UserInputService")
    local RS         = game:GetService("ReplicatedStorage")
    local LP = Players.LocalPlayer

    -- ===== Modules =====
    local Synchronizer, AnimalsData, AnimalsShared, NumberUtils
    local function loadModules()
        if Synchronizer then return true end
        local ok = pcall(function()
            local Packages = RS:WaitForChild("Packages", 5)
            local Datas = RS:WaitForChild("Datas", 5)
            local Shared = RS:WaitForChild("Shared", 5)
            local Utils = RS:WaitForChild("Utils", 5)
            Synchronizer = require(Packages:WaitForChild("Synchronizer"))
            AnimalsData = require(Datas:WaitForChild("Animals"))
            AnimalsShared = require(Shared:WaitForChild("Animals"))
            NumberUtils = require(Utils:WaitForChild("NumberUtils"))
        end)
        return ok and Synchronizer ~= nil
    end

    local NetModule
    local function loadNet()
        if NetModule then return true end
        local ok, mod = pcall(function()
            return require(RS:WaitForChild("Packages", 5):WaitForChild("Net", 5):FindFirstChildWhichIsA("ModuleScript", true))
        end)
        if not ok or type(mod) ~= "table" then return false end
        NetModule = mod
        return true
    end

    local function fireGrapple()
        if not NetModule then loadNet() end
        if not NetModule then return end
        local char = LP.Character
        if not char then return end
        if not char:FindFirstChild("Grapple Hook") then
            local bp = LP:FindFirstChild("Backpack")
            local tool = bp and bp:FindFirstChild("Grapple Hook")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if tool and hum then pcall(function() hum:EquipTool(tool) end) end
        end
        if not char:FindFirstChild("Grapple Hook") then return end
        pcall(function() NetModule:RemoteEvent("UseItem"):FireServer(2) end)
    end
    _G.SXEFireGrapple = fireGrapple

    -- ===== Speed config (live-settable) =====
    local SXESpeed = { CARPET = 400, INBASE = 250 }
    _G.SXESetCarpetSpeed = function(v) v = tonumber(v); if v and v > 0 then SXESpeed.CARPET = v end end
    _G.SXESetInbaseSpeed = function(v) v = tonumber(v); if v and v > 0 then SXESpeed.INBASE = v end end
    _G.SXEGetCarpetSpeed = function() return SXESpeed.CARPET end
    if Config and Config.TpSettings then
        if tonumber(Config.TpSettings.GrabbleTPSpeed) then SXESpeed.CARPET = tonumber(Config.TpSettings.GrabbleTPSpeed) end
    end

    -- ===== Tools =====
    local CARPET_NAMES = { "Flying Carpet", "Carpet", "Cloud", "Witch's Broom", "Cupid's Wings", "Santa's Sleigh", "Magic Carpet" }
    local GRAPPLE_NAMES = { "Grapple Hook", "Grappling Hook", "Grapple", "Hook", "Web Slinger", "Grapple Gun", "GrappleHook" }
    local function findTool(name)
        local char = LP.Character
        local bp = LP:FindFirstChild("Backpack")
        return (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
    end
    local function findGrapple()
        for _, n in ipairs(GRAPPLE_NAMES) do
            local t = findTool(n); if t then return t end
        end
        return nil
    end
    local function equipCarpet()
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return nil end
        local preferred = Config and Config.TpSettings and Config.TpSettings.Tool
        if preferred then
            local pt = findTool(preferred)
            if pt and pt:IsA("Tool") then
                if pt.Parent ~= char then pcall(function() hum:EquipTool(pt) end) end
                return preferred
            end
        end
        for _, n in ipairs(CARPET_NAMES) do
            local t = findTool(n)
            if t and t:IsA("Tool") then
                if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
                return n
            end
        end
        return nil
    end
    local function carpetEngage()
        if not NetModule then pcall(loadNet) end
        local _t0 = os.clock()
        while not findTool("Grapple Hook") and os.clock() - _t0 < 5 do
            if not NetModule then pcall(loadNet) end
            RunService.Heartbeat:Wait()
        end
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not hum then return nil end
        if not char:FindFirstChild("Grapple Hook") then
            local g = findTool("Grapple Hook")
            if g then pcall(function() hum:EquipTool(g) end) end
        end
        task.wait(0.08)
        if NetModule and LP.Character and LP.Character:FindFirstChild("Grapple Hook") then
            pcall(function() NetModule:RemoteEvent("UseItem"):FireServer(2) end)
        end
        task.wait(0.15)
        local h = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if h then pcall(function() h:UnequipTools() end) end
        task.wait(0.15)
        local cn
        local _tc = os.clock()
        repeat
            cn = equipCarpet()
            local c = LP.Character
            if cn and c and c:FindFirstChild(cn) then break end
            RunService.Heartbeat:Wait()
        until os.clock() - _tc > 1
        return cn
    end

    -- ===== Priority system =====
    local PET_PRIORITY_TIERS = {
        [1]  = { pets = {"Headless Horseman"}, threshold = 0 },
        [2]  = { pets = {"Signore Carapace"}, threshold = 0 },
        [3]  = { pets = {"Strawberry Elephant"}, threshold = 0 },
        [4]  = { pets = {"Arcadragon"}, threshold = 0 },
        [5]  = { pets = {"Elefanto Frigo"}, threshold = 5e9 },
        [6]  = { pets = {"John Pork"}, threshold = 10e9 },
        [7]  = { pets = {"Meowl"}, threshold = 5e9 },
        [8]  = { pets = {"Skibidi Toilet"}, threshold = 5e9 },
        [9]  = { pets = {"Love Love Bear"}, threshold = 0 },
        [10] = { pets = {"Antonio"}, threshold = 0 },
        [11] = { pets = {"Pancake and Syrup"}, threshold = 0 },
        [12] = { pets = {"Griffin"}, threshold = 0 },
        [13] = { pets = {"La Supreme Combinasion","Fishino Clownino","Dragon Gingerini","Tirilikalika Tirilikalako"}, threshold = 5e9 },
        [14] = { pets = {"Ginger Gerat","Pet"}, threshold = 10e9 },
        [15] = { pets = {"Hydra Bunny","Digi Narwhal","Kalika Bros"}, threshold = 3e9 },
        [16] = { pets = {"Hydra Dragon Cannelloni","Dragon Cannelloni","Bunny and Eggy"}, threshold = 3e9 },
        [17] = { pets = {"Globa Steppa","Ketupat Bros","Rosey and Teddy","La Casa Boo","Fragola la la"}, threshold = 3e9 },
        [18] = { pets = {"Fragola La La La","Cerberus","Guest 666","Los Hackers"}, threshold = 1e9 },
        [19] = { pets = {"Garama and Madundung","Spooky and Pumpky","Reinito Sleighito","Burguro And Fryuro","Cooki and Milki","Fragrama and Chocrama","La Food Combinasion","Los Amigos","Foxini Lanternini","Capitano Moby","Fortunu and Cashuru","Los Sekolahs","Celestial Pegasus"}, threshold = 750e6 },
        [20] = { pets = {"La Secret Combinasion","Sammyni Fattini","Cloverat Clapat","Popcuru and Fizzuru"}, threshold = 1e9 },
    }
    local TIER_LOOKUP = {}
    for tier, data in pairs(PET_PRIORITY_TIERS) do
        for _, name in ipairs(data.pets) do TIER_LOOKUP[name] = tier end
    end
    local LOCKED_TIERS = { [1]=true,[2]=true,[3]=true,[4]=true }
    local DIRECT_THRESHOLDS = {
        [3] = { [4] = 10e9 },
        [4] = {},
        [5] = { [6] = math.huge },
        [6] = { [9] = math.huge, [10] = math.huge, [12] = 15e9 },
        [10] = { [12] = 20e9 },
        [11] = { [12] = 10e9 },
    }
    local MUTATION_PRIORITY = {
        ["Galaxy"]=1,["Candy"]=1,["Yin Yang"]=1,["YinYang"]=1,["Divine"]=1,
        ["Cursed"]=1,["Lava"]=1,["Radioactive"]=1,["Cyber"]=1,["Rainbow"]=1,["Bloodrot"]=2,
    }
    local MUTATED_BEATS_GRIFFIN = {
        ["Fishino Clownino"]=true,["Globa Steppa"]=true,
        ["La Supreme Combinasion"]=true,["Tirilikalika Tirilikalako"]=true,
    }
    local function getMutPrio(m)
        if not m or m == "" or m == "None" then return 0 end
        if MUTATION_PRIORITY[m] then return MUTATION_PRIORITY[m] end
        local n = tostring(m):lower():gsub("[%s%-_]","")
        if n == "bloodrot" then return 2 end
        if n == "yinyang" or n == "galaxy" or n == "candy" or n == "divine"
            or n == "cursed" or n == "lava" or n == "radioactive" or n == "cyber"
            or n == "rainbow" then return 1 end
        return 0
    end
    local function getCumThreshold(hi, lo)
        if DIRECT_THRESHOLDS[hi] and DIRECT_THRESHOLDS[hi][lo] then return DIRECT_THRESHOLDS[hi][lo] end
        if LOCKED_TIERS[hi] then return math.huge end
        local total = 0
        for t = hi + 1, lo do
            local td = PET_PRIORITY_TIERS[t]
            if td and td.threshold > 0 then total = total + td.threshold end
        end
        return total
    end
    local function petOutranks(aName, bName, aMut, bMut, aMPS, bMPS)
        if aName == "Strawberry Elephant" and bName == "John Pork" then return true end
        if aName == "John Pork" and bName == "Strawberry Elephant" then return false end
        if MUTATED_BEATS_GRIFFIN[aName] and bName == "Griffin" and getMutPrio(aMut) >= 1 then return true end
        if aName == "Griffin" and MUTATED_BEATS_GRIFFIN[bName] and getMutPrio(bMut) >= 1 then return false end
        if aName == "Antonio" and bName == "Elefanto Frigo" and getMutPrio(aMut) >= 1 then return true end
        if aName == "Elefanto Frigo" and bName == "Antonio" and getMutPrio(bMut) >= 1 then return false end
        local tA = TIER_LOOKUP[aName] or 99
        local tB = TIER_LOOKUP[bName] or 99
        if not (TIER_LOOKUP[aName] and TIER_LOOKUP[bName]) then
            if tA == tB then return (aMPS or 0) > (bMPS or 0) end
            return tA < tB
        end
        if tA == tB then
            local pA, pB = getMutPrio(aMut), getMutPrio(bMut)
            if pA ~= pB then return pA > pB end
            return (aMPS or 0) > (bMPS or 0)
        end
        if tA == 4 and tB == 3 then return true end
        if tA == 3 and tB == 4 then return false end
        local hi = math.min(tA, tB)
        local lo = math.max(tA, tB)
        local hiMPS = tA < tB and aMPS or bMPS
        local loMPS = tA < tB and bMPS or aMPS
        local cum = getCumThreshold(hi, lo)
        if cum > 0 and cum ~= math.huge then
            if (loMPS or 0) - (hiMPS or 0) > cum then return tA > tB end
        end
        return tA < tB
    end

    -- ===== Plot/Channel helpers =====
    local function getPlotChannel(plotName)
        if not Synchronizer then return nil end
        local channel
        pcall(function() channel = Synchronizer:Get(plotName) end)
        if not channel then pcall(function() channel = Synchronizer:Wait(plotName) end) end
        return channel
    end
    local function channelGet(channel, key)
        if not channel then return nil end
        local v
        pcall(function() if type(channel.Get) == "function" then v = channel:Get(key) end end)
        if v == nil then pcall(function() v = channel.CacheTable and channel.CacheTable[key] end) end
        return v
    end
    local function isMyPlot(channel)
        if not channel then return false end
        local owner = channelGet(channel, "Owner")
        if not owner then return false end
        local result = false
        pcall(function()
            if typeof(owner) == "Instance" and owner:IsA("Player") then
                result = owner.UserId == LP.UserId
            elseif type(owner) == "table" and owner.UserId then
                result = owner.UserId == LP.UserId
            elseif typeof(owner) == "Instance" then
                result = owner == LP
            end
        end)
        return result
    end
    local function ownerInGame(channel)
        if not channel then return false end
        local owner = channelGet(channel, "Owner")
        if not owner then return false end
        local inGame = false
        pcall(function()
            if typeof(owner) == "Instance" and owner:IsA("Player") then
                inGame = Players:FindFirstChild(owner.Name) ~= nil
            elseif type(owner) == "number" then
                inGame = Players:GetPlayerByUserId(owner) ~= nil
            elseif type(owner) == "table" and owner.Name then
                inGame = Players:FindFirstChild(tostring(owner.Name)) ~= nil
            elseif typeof(owner) == "Instance" and owner.Name then
                inGame = Players:FindFirstChild(owner.Name) ~= nil
            end
        end)
        return inGame
    end
    local function isPlotUnlocked(plotName)
        local ok, res = pcall(function()
            local channel = getPlotChannel(plotName)
            if not channel then return false end
            return channelGet(channel, "BlockEndTimeFirstFloor") == nil
        end)
        return ok and (res == true)
    end

    -- ===== Pet position =====
    local function getPetPosition(plot, slot)
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if not podiums then return nil end
        local podium = podiums:FindFirstChild(tostring(slot))
        if not podium then return nil end
        for _, desc in ipairs(podium:GetDescendants()) do
            if desc:IsA("Model") and desc.Name ~= "Claim" and desc.Name ~= "Base" and desc.Name ~= "Decorations" then
                local hasMesh = false
                for _, c in ipairs(desc:GetDescendants()) do
                    if c:IsA("MeshPart") then hasMesh = true; break end
                end
                if hasMesh then
                    local ok, cf = pcall(function() return desc:GetBoundingBox() end)
                    if ok then return cf.Position end
                end
            end
        end
        local ok, cf = pcall(function() return podium:GetPivot() end)
        if ok then return cf.Position end
        return podium.Position
    end

    -- ===== Fusing check =====
    local _BLOCKING_MACHINE_TYPES = { Fuse=true, Duel=true, Trade=true, Crafting=true }
    local function _SXEIsFusing(animalData)
        if type(animalData) ~= "table" then return false end
        local m = animalData.Machine
        if type(m) ~= "table" then return false end
        return _BLOCKING_MACHINE_TYPES[m.Type] == true and m.Active == true
    end

    -- ===== Scanner =====
    local function scanAllPets()
        local pets = {}
        if not loadModules() then return pets end
        local Plots = workspace:FindFirstChild("Plots")
        if not Plots then return pets end
        for _, plot in ipairs(Plots:GetChildren()) do
            local channel = getPlotChannel(plot.Name)
            if not channel then continue end
            if isMyPlot(channel) then continue end
            if not ownerInGame(channel) then continue end
            local animalList = channelGet(channel, "AnimalList")
            if not animalList then continue end
            for slot, animalData in pairs(animalList) do
                if type(animalData) ~= "table" then continue end
                local animalName = animalData.Index
                if not animalName then continue end
                local animalInfo = AnimalsData and AnimalsData[animalName]
                if not animalInfo then continue end
                if _SXEIsFusing(animalData) then continue end
                local mutation = animalData.Mutation or "None"
                local genValue = 0
                pcall(function()
                    genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil)
                end)
                local displayName = (animalInfo and animalInfo.DisplayName) or animalName
                local pos = getPetPosition(plot, slot)
                if pos then
                    table.insert(pets, {
                        name = displayName, index = animalName, mps = genValue,
                        mutation = mutation, position = pos, plot = plot.Name, slot = tostring(slot),
                    })
                end
            end
        end
        local conveyorFolder = workspace:FindFirstChild("RenderedMovingAnimals")
        if conveyorFolder then
            for _, model in ipairs(conveyorFolder:GetChildren()) do
                pcall(function()
                    if not model:IsA("Model") then return end
                    local animalInfo = AnimalsData and AnimalsData[model.Name]
                    if not animalInfo then return end
                    local mutation = model:GetAttribute("Mutation") or "None"
                    local genValue = 0
                    pcall(function()
                        genValue = AnimalsShared:GetGeneration(model.Name, model:GetAttribute("Mutation"), nil, nil) or 0
                    end)
                    if genValue <= 0 then return end
                    local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                    if not part then return end
                    table.insert(pets, {
                        name = animalInfo.DisplayName or model.Name, index = model.Name,
                        mps = genValue, mutation = mutation, position = part.Position,
                        plot = nil, slot = nil, conveyor = true, model = model,
                    })
                end)
            end
        end
        table.sort(pets, function(a, b)
            return petOutranks(a.name, b.name, a.mutation, b.mutation, a.mps, b.mps)
        end)
        return pets
    end

    -- ===== Sky coordinates =====
    local UPPER = {
        B = {{coord=Vector3.new(-487.921448,16.850713,-75.768013),facing="NORTH"},{coord=Vector3.new(-332.379730,16.850722,-75.762100),facing="NORTH"},{coord=Vector3.new(-487.134918,16.850713,-18.094154),facing="SOUTH"},{coord=Vector3.new(-316.300171,16.850713,-17.845898),facing="SOUTH"}},
        C = {{coord=Vector3.new(-330.765381,16.850713,31.424425),facing="NORTH"},{coord=Vector3.new(-502.989349,16.850713,31.172430),facing="NORTH"},{coord=Vector3.new(-489.077087,16.850713,89.010147),facing="SOUTH"},{coord=Vector3.new(-330.908936,16.850713,88.930145),facing="SOUTH"}},
        D = {{coord=Vector3.new(-331.264893,16.850713,138.209167),facing="NORTH"},{coord=Vector3.new(-487.935181,16.850713,138.026321),facing="NORTH"},{coord=Vector3.new(-487.774933,16.850713,195.882538),facing="SOUTH"},{coord=Vector3.new(-330.799133,16.850575,196.022354),facing="SOUTH"}},
    }
    local LOWER = {
        B = {{coord=Vector3.new(-335.725586,-3.048217,-74.984589),facing="NORTH"},{coord=Vector3.new(-503.214233,-3.048217,-75.043137),facing="NORTH"},{coord=Vector3.new(-483.619385,-3.718430,-18.844337),facing="SOUTH"},{coord=Vector3.new(-316.147095,-3.048218,-18.818844),facing="SOUTH"}},
        C = {{coord=Vector3.new(-335.985413,-3.048218,32.051426),facing="NORTH"},{coord=Vector3.new(-503.277008,-3.048217,31.956175),facing="NORTH"},{coord=Vector3.new(-483.749390,-3.048218,88.147003),facing="SOUTH"},{coord=Vector3.new(-315.793823,-3.048217,88.163979),facing="SOUTH"}},
        D = {{coord=Vector3.new(-335.476654,-3.048218,139.001083),facing="NORTH"},{coord=Vector3.new(-503.710083,-3.048218,138.989883),facing="NORTH"},{coord=Vector3.new(-315.654938,-3.048218,195.302444),facing="SOUTH"},{coord=Vector3.new(-483.859253,-3.048218,195.269043),facing="SOUTH"}},
    }
    local UPPER_Y_THRESHOLD = 7
    local TALL_PETS = { ["La Secret Combinasion"]=true, ["La Jolly Grande"]=true }
    local TALL_OFFSET = 3
    local BASES_LOW = {
        [1]=Vector3.new(-476.52,-2,220.94),[2]=Vector3.new(-476.52,-2,113.77),
        [3]=Vector3.new(-476.52,-2,6.18),[4]=Vector3.new(-476.52,-2,-101.07),
        [5]=Vector3.new(-342.66,-2,221.45),[6]=Vector3.new(-342.66,-2,113.41),
        [7]=Vector3.new(-342.66,-2,6.25),[8]=Vector3.new(-342.66,-2,-99.73),
    }
    local BASES_HIGH = {
        [1]=Vector3.new(-479.51,18,220.94),[2]=Vector3.new(-479.51,18,113.77),
        [3]=Vector3.new(-479.51,18,6.18),[4]=Vector3.new(-479.51,18,-101.07),
        [5]=Vector3.new(-339.48,18,221.45),[6]=Vector3.new(-339.48,18,113.41),
        [7]=Vector3.new(-339.48,18,6.25),[8]=Vector3.new(-339.48,18,-99.73),
    }
    local FRONT_Y_LOW = -3.048217
    local FRONT_Y_HIGH = 16.850713
    local COLUMN_SPLIT_X = -410
    local FRONT_Z_CLAMP = 18
    local SIDE_NEAR_Z = 45

    local function getClosestBaseIdx(pos)
        local closest, dist = 1, math.huge
        for i = 1, 8 do
            local b = BASES_LOW[i]
            local d = (pos.X - b.X)^2 + (pos.Z - b.Z)^2
            if d < dist then dist = d; closest = i end
        end
        return closest
    end
    local function buildFrontCandidate(idx, isUpper, playerZ)
        local base = isUpper and BASES_HIGH[idx] or BASES_LOW[idx]
        local frontY = isUpper and FRONT_Y_HIGH or FRONT_Y_LOW
        local frontZ = math.clamp(playerZ - base.Z, -FRONT_Z_CLAMP, FRONT_Z_CLAMP) + base.Z
        local coord = Vector3.new(base.X, frontY, frontZ)
        local faceDir = (idx <= 4) and Vector3.new(-1, 0, 0) or Vector3.new(1, 0, 0)
        return coord, faceDir
    end
    local function plotSides(coordTable, idx)
        local base = BASES_LOW[idx]
        local isWest = idx <= 4
        local out = {}
        for _, coords in pairs(coordTable) do
            for _, data in ipairs(coords) do
                if ((data.coord.X < COLUMN_SPLIT_X) == isWest)
                   and math.abs(data.coord.Z - base.Z) < SIDE_NEAR_Z then
                    out[#out + 1] = data
                end
            end
        end
        return out
    end
    local function findClosest(petPos, coordTable)
        local best, bestKey, bestDist = nil, nil, math.huge
        for skyKey, coords in pairs(coordTable) do
            for _, data in ipairs(coords) do
                local c = data.coord
                local d = math.sqrt((petPos.X - c.X)^2 + (petPos.Z - c.Z)^2)
                if d < bestDist then bestDist = d; best = data; bestKey = skyKey end
            end
        end
        return best, bestKey
    end

    -- ===== Viz =====
    local _vizParts = {}
    local function clearViz()
        for _, p in ipairs(_vizParts) do if p and p.Parent then p:Destroy() end end
        table.clear(_vizParts)
    end
    local function vizPath(fromPos, waypoints)
        -- Pathfinder lines/dots disabled (user request: no lines).
        return
    end

    -- ===== Movement =====
    local SPEED = 200
    local ARRIVE = 3
    local MAX_CLIMB = 60

    local function vZero(hrp)
        if hrp then hrp.AssemblyLinearVelocity = Vector3.zero; hrp.AssemblyAngularVelocity = Vector3.zero end
    end

    local function velMoveThrough(hrp, waypoints, speedOverride, allowJump, quickStart)
        if not hrp or not hrp.Parent or #waypoints == 0 then return end
        -- L'autorite reseau est deja securisee au debut de doVelocityTP (une seule
        -- fois par personnage) -- pas la peine de la re-verifier ici a chaque appel,
        -- ca ajoutait un delai perceptible au demarrage de chaque TP.
        local _runSpeed = speedOverride or SXESpeed.CARPET
        vizPath(hrp.Position, waypoints)
        local wpIdx = 1
        local done = false
        local conn
        local _tpHum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
        local _tpPlatformStandOn = false
        local function finish()
            if done then return end
            done = true
            if hrp and hrp.Parent then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                local _, y = hrp.CFrame:ToEulerAnglesYXZ()
                hrp.CFrame = CFrame.new(waypoints[#waypoints]) * CFrame.Angles(0, y, 0)
            end
            if _tpPlatformStandOn and _tpHum then
                _tpPlatformStandOn = false
                pcall(function() _tpHum.PlatformStand = false end)
            end
            if conn then conn:Disconnect() end
            clearViz()
        end
        local lastDist, stall = math.huge, 0
        if quickStart then
            local _hp = RaycastParams.new()
            _hp.FilterType = Enum.RaycastFilterType.Exclude
            _hp.IgnoreWater = true
            local _skip = {}
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl.Character then _skip[#_skip + 1] = pl.Character end
            end
            _hp.FilterDescendantsInstances = _skip
            for _ = 1, 3 do
                local target = waypoints[wpIdx]
                if not target then break end
                local flat = Vector3.new(target.X - hrp.Position.X, 0, target.Z - hrp.Position.Z)
                local mag = flat.Magnitude
                if mag < 1 then break end
                local nextPos = hrp.Position + flat.Unit * math.min(20, mag)
                local _hit = workspace:Raycast(hrp.Position, nextPos - hrp.Position, _hp)
                if _hit and _hit.Instance and _hit.Instance.CanCollide then break end
                hrp.CFrame = (hrp.CFrame - hrp.CFrame.Position) + nextPos
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                RunService.Heartbeat:Wait()
                if not hrp or not hrp.Parent then return end
            end
        end
        -- N'active PlatformStand qu'a partir d'ici (boucle de velocite continue) --
        -- pas pendant le placement initial "quickStart" (CFrame instantane), sinon
        -- le corps peut traverser le sol juste apres le clone/placement.
        if _tpHum then
            _tpPlatformStandOn = true
            pcall(function() _tpHum.PlatformStand = true end)
            pcall(function() hrp:SetNetworkOwner(LP) end)
        end
        local _lastTick = os.clock()
        conn = RunService.Heartbeat:Connect(function()
            if not hrp or not hrp.Parent or done then
                if conn then conn:Disconnect() end; return
            end
            local _now = os.clock()
            local dt = math.min(_now - _lastTick, 0.1)
            _lastTick = _now
            equipCarpet()
            local target = waypoints[wpIdx]
            local diff = target - hrp.Position
            local mag = diff.Magnitude
            if mag < ARRIVE then
                wpIdx = wpIdx + 1
                if wpIdx > #waypoints then finish(); return end
                lastDist, stall = math.huge, 0
                target = waypoints[wpIdx]
                diff = target - hrp.Position
                mag = diff.Magnitude
            end
            if mag > lastDist - 0.05 then stall = stall + 1 else stall = 0 end
            lastDist = mag
            if stall >= 18 then finish(); return end
            if mag >= 0.1 then
                local dir = diff.Unit
                if allowJump and diff.Y > 5 and wpIdx < #waypoints then
                    local hum = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Humanoid")
                    if hum then
                        local st = hum:GetState()
                        if st ~= Enum.HumanoidStateType.Jumping and st ~= Enum.HumanoidStateType.Freefall then
                            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
                            pcall(function() hum.Jump = true end)
                        end
                    end
                end
                local _vy = dir.Y * _runSpeed
                if _vy > MAX_CLIMB then _vy = MAX_CLIMB end
                -- Deplacement par pas de CFrame (pas par Velocity) : rien (controleur
                -- Humanoid, script de l'outil equipe, etc.) ne peut "annuler" une position
                -- qu'on reecrit nous-meme chaque frame, contrairement a une velocite qui
                -- peut etre amortie/ecrasee par un autre systeme -- c'est ca qui causait
                -- le tremblement meme avec PlatformStand actif.
                local _step = Vector3.new(dir.X * _runSpeed, _vy, dir.Z * _runSpeed) * dt
                if _step.Magnitude > mag then _step = diff end
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.CFrame = (hrp.CFrame - hrp.CFrame.Position) + (hrp.Position + _step)
            end
        end)
        local totalDist = 0
        local prev = hrp.Position
        for _, wp in ipairs(waypoints) do totalDist = totalDist + (prev - wp).Magnitude; prev = wp end
        local timeout = totalDist / math.min(SPEED, _runSpeed) + 2
        local elapsed = 0
        while not done and elapsed < timeout do task.wait(0.05); elapsed = elapsed + 0.05 end
        finish()
        vZero(hrp)
    end

    -- ===== Routing =====
    local _DIRS = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
    local _STRUCT = { ["structure base home"]=true, ["Wall"]=true, ["Floor"]=true, ["Roof"]=true }
    local _SKIP_NAME = { ["DeliveryHitbox"]=true, ["StealHitbox"]=true, ["LaserHitbox"]=true,
        ["AnimalTarget"]=true, ["Multiplier"]=true, ["Laser"]=true, ["Hitbox"]=true,
        ["Spawn"]=true, ["MainRoot"]=true, ["SecondFloor"]=true, ["ThirdFloor"]=true, ["Slope"]=true }
    local function _blocks(inst)
        if not inst then return false end
        if _SKIP_NAME[inst.Name] then return false end
        if inst.CanCollide then return true end
        if _STRUCT[inst.Name] then return true end
        local s = inst.Size
        if s and math.max(s.X * s.Y, s.X * s.Z, s.Y * s.Z) > 150 then return true end
        return false
    end
    local function _blocksWide(inst)
        if not inst then return false end
        if _SKIP_NAME[inst.Name] then return false end
        if inst.CanCollide then return true end
        if _STRUCT[inst.Name] then return true end
        local s = inst.Size
        if s and math.max(s.X * s.Y, s.X * s.Z, s.Y * s.Z) > 30 then return true end
        return false
    end
    local function _block(origin, target, blockFn)
        blockFn = blockFn or _blocks
        local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.IgnoreWater = true
        local skip = {}
        for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then skip[#skip + 1] = pl.Character end end
        local o = origin
        for _ = 1, 16 do
            rp.FilterDescendantsInstances = skip
            local d = target - o; if d.Magnitude < 0.05 then return nil end
            local res = workspace:Raycast(o, d, rp)
            if not res then return nil end
            if blockFn(res.Instance) then return res end
            skip[#skip + 1] = res.Instance; o = res.Position + d.Unit * 0.3
        end
        return nil
    end
    local function _clear(a, b) return _block(a, b) == nil end
    local function _clearDist(origin, dir, maxD)
        local res = _block(origin, origin + dir.Unit * maxD)
        if not res then return maxD end
        return (res.Position - origin).Magnitude
    end
    local function _pull(pts)
        if #pts <= 2 then return pts end
        local out = { pts[1] }; local i = 1
        while i < #pts do
            local j = #pts
            while j > i + 1 and not _clear(out[#out], pts[j]) do j = j - 1 end
            out[#out + 1] = pts[j]; i = j
        end
        return out
    end
    local function _clearWideRay(a, b) return _block(a, b, _blocksWide) == nil end
    local function _clearWide(a, b)
        if not _clear(a, b) then return false end
        local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
        if d.Magnitude < 0.1 then return true end
        local _CLEARANCE = 10
        local perp = Vector3.new(-d.Z, 0, d.X).Unit * _CLEARANCE
        local up = Vector3.new(0, _CLEARANCE, 0)
        return _clearWideRay(a + perp, b + perp) and _clearWideRay(a - perp, b - perp)
            and _clearWideRay(a + up, b + up) and _clearWideRay(a - up, b - up)
    end
    local function _pullWide(pts)
        if #pts <= 2 then return pts end
        local out = { pts[1] }; local i = 1
        while i < #pts do
            local j = #pts
            while j > i + 1 and not _clearWide(out[#out], pts[j]) do j = j - 1 end
            out[#out + 1] = pts[j]; i = j
        end
        return out
    end
    local function _pushOffWalls(pts)
        if #pts <= 2 then return pts end
        local MARGIN = 10; local MAX_PUSH = 14
        local out = { pts[1] }
        for i = 2, #pts - 1 do
            local p = pts[i]; local shift = Vector3.zero
            for _, dr in ipairs(_DIRS) do
                local res = _block(p, p + dr * MARGIN, _blocks)
                if res then
                    local dist = (res.Position - p).Magnitude
                    if dist < MARGIN then shift = shift - dr * (MARGIN - dist) end
                end
            end
            if shift.Magnitude > 0.1 then
                if shift.Magnitude > MAX_PUSH then shift = shift.Unit * MAX_PUSH end
                local moved = p + shift
                if _clear(out[#out], moved) then out[#out + 1] = moved else out[#out + 1] = p end
            else
                out[#out + 1] = p
            end
        end
        out[#out + 1] = pts[#pts]
        return out
    end
    local PathfindingService = game:GetService("PathfindingService")
    local function computeRoute(fromPos, toPos, facingDir)
        if _clear(fromPos, toPos) then return { toPos } end
        local entry = facingDir and (toPos - facingDir * 14) or toPos
        local groundTo = Vector3.new(entry.X, fromPos.Y, entry.Z)
        local path = PathfindingService:CreatePath({
            AgentRadius = 12, AgentHeight = 5, AgentCanJump = true, AgentJumpHeight = 10, AgentMaxSlope = 89,
        })
        local FLOAT = 3
        local nav = { fromPos }
        local ok = pcall(function()
            path:ComputeAsync(Vector3.new(fromPos.X, fromPos.Y, fromPos.Z), groundTo)
        end)
        if ok and path.Status == Enum.PathStatus.Success then
            local last = fromPos
            for _, wp in ipairs(path:GetWaypoints()) do
                if (wp.Position - last).Magnitude >= 8 then
                    nav[#nav + 1] = wp.Position + Vector3.new(0, FLOAT, 0); last = wp.Position
                end
            end
        end
        nav[#nav + 1] = entry + Vector3.new(0, FLOAT, 0)
        nav = _pushOffWalls(nav)
        local route = _pullWide(nav)
        route[#route + 1] = toPos
        return route
    end

    -- ===== Clone / goToBrainrot =====
    local function doClone()
        if not NetModule then pcall(loadNet) end
        local char = LP.Character or LP.CharacterAdded:Wait()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not hum then return false end
        local cloner = (LP:FindFirstChild("Backpack") and LP.Backpack:FindFirstChild("Quantum Cloner"))
                    or char:FindFirstChild("Quantum Cloner")
        if not cloner then return false end
        if cloner.Parent ~= char then
            pcall(function() hum:EquipTool(cloner) end)
            task.wait()
        end
        if not NetModule then return false end
        local useOk = pcall(function() NetModule:RemoteEvent("UseItem"):FireServer() end)
        task.wait(0.05)
        local telOk = pcall(function() NetModule:RemoteEvent("QuantumCloner/OnTeleport"):FireServer() end)
        return useOk and telOk
    end

    -- CARPET GLIDE: fly straight to the pet on the equipped carpet at FULL 3D speed
    -- (same pace as velMoveThrough -- WalkTPSpeed in the actual direction, vertical
    -- included). The carpet is already equipped by goToBrainrot, so no extra equip
    -- wait. Used as the FINAL approach after the clone/grabble TP.
    local function carpetGlideTo(targetPos)
        if not targetPos then return end
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        pcall(function() hrp.Anchored = false end)
        pcall(equipCarpet)
        local SPEED = (Config.TpSettings and (tonumber(Config.TpSettings.WalkTPSpeed) or tonumber(Config.TpSettings.GrabbleTPSpeed))) or 190
        local FLOAT_OFFSET = (targetPos.Y > 20) and -4 or 0
        local goal = Vector3.new(targetPos.X, targetPos.Y + FLOAT_OFFSET, targetPos.Z)
        local t0 = os.clock()
        local lastDist, stall = math.huge, 0
        while hrp.Parent and (os.clock() - t0) < 8 do
            if LP:GetAttribute("Stealing") then break end
            equipCarpet()
            local diff = goal - hrp.Position
            local mag = diff.Magnitude          -- full 3D distance (so it doesn't stop short on upper floors)
            if mag < 3 then break end
            if mag > lastDist - 0.05 then stall = stall + 1 else stall = 0 end
            lastDist = mag
            if stall >= 30 then break end       -- stuck on a wall -> give up
            hrp.AssemblyLinearVelocity = diff.Unit * SPEED   -- full speed straight at the pet
            RunService.Heartbeat:Wait()
        end
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end

    local function goToBrainrot(petPos)
        if not petPos then return end
        local char, hrp, hum
        local _t0 = os.clock()
        repeat
            char = LP.Character
            hrp = char and char:FindFirstChild("HumanoidRootPart")
            hum = char and char:FindFirstChildOfClass("Humanoid")
            if hrp and hum then break end
            RunService.Heartbeat:Wait()
        until os.clock() - _t0 > 3
        if not hrp or not hum then return end
        pcall(function() hrp.Anchored = false end)
        local _equipped = false
        do
            local _e0 = os.clock()
            repeat
                char = LP.Character
                for _, _cn in ipairs(CARPET_NAMES) do
                    if char and char:FindFirstChild(_cn) then _equipped = true; break end
                end
                if _equipped then break end
                equipCarpet()
                RunService.Heartbeat:Wait()
            until _equipped or os.clock() - _e0 > 1.5
            if _equipped then task.wait(0.2) end
        end
        char = LP.Character
        hrp = char and char:FindFirstChild("HumanoidRootPart")
        hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp then return end
        pcall(function() hrp.Anchored = false end)
        local _plotRad = (petPos.Y <= 8.9) and 26 or 25
        do
            local _t0b = os.clock()
            repeat
                local p = hrp.Position
                local inRad = false
                local plotsFolder = workspace:FindFirstChild("Plots")
                if plotsFolder then
                    for _, plot in ipairs(plotsFolder:GetChildren()) do
                        pcall(function()
                            local pp = plot:GetPivot().Position
                            if math.abs(p.X - pp.X) < _plotRad and math.abs(p.Z - pp.Z) < _plotRad then inRad = true end
                        end)
                        if inRad then break end
                    end
                end
                if inRad then break end
                RunService.Heartbeat:Wait()
            until os.clock() - _t0b > 1.5
        end
        local h = petPos.Y
        local targetY = hrp.Position.Y
        if h > 23.15 then targetY = 21
        elseif h >= 11 and h <= 23.15 then targetY = 14.5
        elseif h >= -6.9 and h <= 8.9 then targetY = -4 end
        local _to = Vector3.new(petPos.X, targetY, petPos.Z)
        if Config.TpSettings and Config.TpSettings.BrainrotCarpet then
            -- Carpet to Brainrot: after the clone/grabble TP into the base, glide on
            -- the carpet straight to the pet (uses live Walk To Brainrot Speed).
            carpetGlideTo(petPos)
        else
            local _route = computeRoute(hrp.Position, _to, nil)
            if not _route or #_route == 0 then _route = { _to } end
            velMoveThrough(hrp, _route, (Config and Config.TpSettings and (tonumber(Config.TpSettings.WalkTPSpeed) or tonumber(Config.TpSettings.GrabbleTPSpeed))) or SXESpeed.INBASE, true, true)
        end
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        do
            local _platPos = (hrp and hrp.Parent and hrp.Position) or _to
            local _feetY = _platPos.Y - 3
            local _plat = Instance.new("Part")
            _plat.Name = "SXETempPlatform"; _plat.Size = Vector3.new(8, 1, 8)
            _plat.Position = Vector3.new(petPos.X, _feetY - 1.5, petPos.Z)
            _plat.Anchored = true; _plat.CanCollide = false; pcall(makeOneWay, _plat); _plat.Transparency = 1
            _plat.Material = Enum.Material.SmoothPlastic; _plat.Parent = workspace
            task.spawn(function()
                local _s = tick()
                while tick() - _s < 20 do
                    if LP:GetAttribute("Stealing") then break end
                    task.wait(0.1)
                end
                if _plat and _plat.Parent then _plat:Destroy() end
            end)
        end
    end

    -- ===== Steal engine =====
    local InternalStealCache = {}
    local STEAL_HOLD_DURATION = 1.3
    local _stealHoldStart = 0
    local _stealHoldActive = false

    local function buildStealCallbacks(prompt)
        if InternalStealCache[prompt] then return end
        if not prompt or not prompt.Parent then return end
        local data = { holdCallbacks = {}, triggerCallbacks = {}, holdEndCallbacks = {}, ready = true }
        local function grab(sig, into)
            local ok, conns = pcall(getconnections, sig)
            if ok and type(conns) == "table" then
                for _, c in ipairs(conns) do
                    if type(c.Function) == "function" then table.insert(into, c.Function) end
                end
            end
        end
        grab(prompt.PromptButtonHoldBegan, data.holdCallbacks)
        grab(prompt.Triggered, data.triggerCallbacks)
        grab(prompt.PromptButtonHoldEnded, data.holdEndCallbacks)
        if #data.holdCallbacks > 0 or #data.triggerCallbacks > 0 or #data.holdEndCallbacks > 0 then
            InternalStealCache[prompt] = data
        end
    end

    local function executeStealAsync(prompt)
        local data = InternalStealCache[prompt]
        if not data or not data.ready then return false end
        data.ready = false
        _stealHoldStart = tick()
        _stealHoldActive = true
        _G.SXE_StealStatus = _G.SXE_StealStatus or {}
        _G.SXE_StealStatus.active = true
        _G.SXE_StealStatus.start = _stealHoldStart
        _G.SXE_StealStatus.duration = STEAL_HOLD_DURATION

        task.spawn(function()
            for _, fn in ipairs(data.holdCallbacks) do task.spawn(fn) end
            pcall(function()
                local _st = prompt:GetAttribute("State")
                if _st ~= nil and _st ~= "Steal" then
                    if not _G._xenStealRemote then
                        local _net = _G.XenNet or require(game:GetService("ReplicatedStorage"):WaitForChild("Packages"):WaitForChild("Net"):FindFirstChildWhichIsA("ModuleScript", true))
                        _G._xenStealRemote = _net and _net:RemoteEvent("f40f7d9e-2f0d-4167-b250-899273f46874")
                    end
                    local r = _G._xenStealRemote
                    if r then
                        local _t = workspace:GetServerTimeNow() + 124
                        r:FireServer(_t, "68c86eb7-eb7e-4b4d-96ae-cf7cd847c5b0")
                        r:FireServer(_t, "07b9cc25-2a1f-4a26-a0ec-f2fab578d8bd")
                    end
                end
            end)
            local remain = STEAL_HOLD_DURATION - (tick() - _stealHoldStart)
            if remain > 0 then task.wait(remain) end
            if prompt and prompt.Parent then
                for _, fn in ipairs(data.triggerCallbacks) do task.spawn(fn) end
            end
            for _, fn in ipairs(data.holdEndCallbacks) do task.spawn(fn) end
            _stealHoldActive = false
            if _G.SXE_StealStatus then _G.SXE_StealStatus.active = false end
            task.wait(0.05)
            data.ready = true
        end)
        return true
    end

    local function findStealPrompt(pet)
        if pet.plot and pet.slot then
            local plots = workspace:FindFirstChild("Plots")
            local plot = plots and plots:FindFirstChild(pet.plot)
            local podiums = plot and plot:FindFirstChild("AnimalPodiums")
            local podium = podiums and podiums:FindFirstChild(tostring(pet.slot))
            if podium then
                local base = podium:FindFirstChild("Base")
                local spawn = base and base:FindFirstChild("Spawn")
                local attach = spawn and spawn:FindFirstChild("PromptAttachment")
                if attach then
                    for _, p in ipairs(attach:GetChildren()) do
                        if p:IsA("ProximityPrompt") then return p end
                    end
                end
                for _, d in ipairs(podium:GetDescendants()) do
                    if d:IsA("ProximityPrompt") then return d end
                end
            end
        end
        if pet.model and pet.model.Parent then
            for _, d in ipairs(pet.model:GetDescendants()) do
                if d:IsA("ProximityPrompt") then return d end
            end
        end
        return nil
    end

    local STEAL_PROXIMITY = 60
    local STEAL_ARM_TIMEOUT = 25
    local _stealTarget = nil
    local _stealArmedAt = 0

    local function timeUntilCanSteal()
        if LP:GetAttribute("Stealing") or LP:GetAttribute("IsTrading")
            or LP:GetAttribute("IsDuelSelecting") or LP:GetAttribute("Web") then
            return -1
        end
        return 0
    end

    local function _petKey(pet)
        if not pet then return nil end
        if pet.plot and pet.slot then return tostring(pet.plot) .. "|" .. tostring(pet.slot) end
        return "idx|" .. tostring(pet.index or pet.name)
    end
    local function _petStillExists(sel, pets)
        if not sel or not pets then return nil end
        local k = _petKey(sel)
        for _, p in ipairs(pets) do if _petKey(p) == k then return p end end
        return nil
    end
    local function _pickByMode(pets)
        if not pets or #pets == 0 then return nil end
        local C = Config or {}
        -- PRIORITY FIRST: honored when EITHER the Auto-TP "Priority Mode" OR the
        -- Steal "Priority" mode is on (the two tabs are now synced here). Follow
        -- the user's priorityList order (1 -> 2 -> 3 ...), match by DisplayName OR
        -- Index, and ALWAYS take the TOPMOST priority entry present on the server,
        -- regardless of distance/gen. So with Headless Horseman at #1, any Headless
        -- on the server is taken and everything else is ignored.
        local priorityMode = C.AutoTPPriority or (C.StealMode == "Priority")
        if priorityMode and priorityList and #priorityList > 0 then
            for _, pName in ipairs(priorityList) do
                local searchName = pName:lower()
                for _, p in ipairs(pets) do
                    if (p.name and p.name:lower() == searchName) or (p.index and p.index:lower() == searchName) then
                        return p
                    end
                end
            end
        end
        -- HIGHEST gen/value: Auto-TP Highest Gen/Value OR Steal "Highest".
        if C.AutoTPHighestGen or C.AutoTPHighestValue or (C.StealMode == "Highest") then
            local best, bv
            for _, p in ipairs(pets) do
                local v = p.mps or 0
                if not bv or v > bv then bv, best = v, p end
            end
            return best
        end
        return pets[1]
    end
    local function _samePet(a, b)
        if not a or not b then return false end
        return a.plot == b.plot and tostring(a.slot) == tostring(b.slot)
    end

    local _stealTarget2 = nil
    local function armSteal(pet)
        if not pet then return end
        _stealTarget = pet; _stealArmedAt = os.clock()
        _stealTarget2 = pet
        _G.SXE_StealStatus = _G.SXE_StealStatus or {}
        _G.SXE_StealStatus.target = pet
    end
    local function disarmSteal()
        _stealTarget = nil
        _G.SXE_StealStatus = _G.SXE_StealStatus or {}
        _G.SXE_StealStatus.target = nil
        _G.SXE_StealStatus.active = false
    end
    _G.SXEArmSteal = armSteal
    _G.SXEDisarmSteal = disarmSteal

    local AUTO_STEAL = (Config and Config.AutoStealEnabled) and true or false
    _G.SXEAutoSteal = function(on) AUTO_STEAL = on ~= false end

    local _stealLastScan = 0
    local _autoLastScan = 0
    local isTeleporting = false
    local _tpStartedAt = 0
    local _cloneTP = false
    local _cloneFired = false
    local _started = false
    local _lastOwnedHRP = nil

    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if AUTO_STEAL and _started and not LP:GetAttribute("Stealing")
            and not (isTeleporting and _cloneTP)
            and (now - _autoLastScan) >= 0.1 then
            _autoLastScan = now
            local char = LP.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local ok, pets = pcall(scanAllPets)
                if ok and pets then
                    local best
                    -- Manual selection from SXEHub
                    if manuallySelectedUID then
                        for _, pet in ipairs(pets) do
                            if not pet.conveyor and pet.plot and pet.slot then
                                local uid = pet.plot .. "_" .. tostring(pet.slot)
                                if uid == manuallySelectedUID then best = pet; break end
                            end
                        end
                    end
                    if not best then
                        local STEAL_MODE = (Config and Config.StealMode) or "Priority"
                        if STEAL_MODE == "Nearest" then
                            local bd
                            for _, pet in ipairs(pets) do
                                if not pet.conveyor then
                                    local prompt = findStealPrompt(pet)
                                    if prompt and prompt.Parent then
                                        local pp = prompt.Parent
                                        local ppPos = (pp:IsA("BasePart") and pp.Position)
                                            or (pp.Parent and pp.Parent:IsA("BasePart") and pp.Parent.Position)
                                        if ppPos then
                                            local d = (hrp.Position - ppPos).Magnitude
                                            if (not bd or d < bd) then bd, best = d, pet end
                                        end
                                    end
                                end
                            end
                        else
                            local nc = {}
                            for _, p in ipairs(pets) do if not p.conveyor then nc[#nc + 1] = p end end
                            best = _pickByMode(nc)
                        end
                    end
                    if best then
                        if not _samePet(best, _stealTarget) then armSteal(best) end
                    elseif _stealTarget and not _stealHoldActive then
                        disarmSteal()
                    end
                end
            end
        end

        local pet = _stealTarget
        if not pet then return end
        local STEAL_MODE = (Config and Config.StealMode) or "Priority"
        if STEAL_MODE == "Nearest" and now - _stealArmedAt > STEAL_ARM_TIMEOUT then
            disarmSteal(); return
        end
        if now - _stealLastScan < 0.067 then return end
        _stealLastScan = now
        local t = timeUntilCanSteal()
        if t == -1 then
            if LP:GetAttribute("Stealing") then disarmSteal() end
            return
        end
        if t > 0 and t > STEAL_HOLD_DURATION then return end
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local prompt = findStealPrompt(pet)
        if not prompt or not prompt.Parent then return end
        local pp = prompt.Parent
        local ppPos = (pp and pp:IsA("BasePart") and pp.Position)
            or (pp and pp.Parent and pp.Parent:IsA("BasePart") and pp.Parent.Position)
        local _inCloneTP = isTeleporting and _cloneTP and _cloneFired
        if not _inCloneTP and ppPos and (hrp.Position - ppPos).Magnitude > STEAL_PROXIMITY then return end
        local oldMax
        pcall(function() oldMax = prompt.MaxActivationDistance end)
        pcall(function() prompt.MaxActivationDistance = math.huge end)
        buildStealCallbacks(prompt)
        if InternalStealCache[prompt] then executeStealAsync(prompt) end
        pcall(function() if oldMax ~= nil then prompt.MaxActivationDistance = oldMax end end)
    end)

    -- ===== Main TP function (1:1 xentp.lua doVelocityTP) =====
    local function doVelocityTP()
        if isTeleporting and (os.clock() - _tpStartedAt) < 30 then return end
        local _preDelay = tonumber(Config and Config.TpSettings and Config.TpSettings.PreTpDelayVal) or 0
        if _preDelay > 0 then task.wait(_preDelay) end
        isTeleporting = true
        _tpStartedAt = os.clock()
        _cloneTP = false
        _cloneFired = false
        clearViz()
        if not NetModule then pcall(loadNet) end

        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then isTeleporting = false; return end

        -- Securise l'autorite reseau du personnage AVANT le tout premier deplacement
        -- de ce TP (clone/teleport initial inclus). Fait une seule fois par
        -- personnage (via _lastOwnedHRP) -- sinon ce petit blocage se repetait a
        -- chaque TP et ajoutait un delai perceptible au demarrage a chaque fois.
        if _lastOwnedHRP ~= hrp then
            pcall(function() hrp:SetNetworkOwnershipAuto(false) end)
            local _ownT0 = os.clock()
            while hrp and hrp.Parent and os.clock() - _ownT0 < 0.3 do
                local _owner
                pcall(function() _owner = hrp:GetNetworkOwner() end)
                if _owner == LP then break end
                pcall(function() hrp:SetNetworkOwner(LP) end)
                RunService.Heartbeat:Wait()
            end
            _lastOwnedHRP = hrp
        end

        local allPets = scanAllPets()
        if #allPets == 0 then
            local _t0 = os.clock()
            while #allPets == 0 and os.clock() - _t0 < 4 do
                task.wait(0.15)
                allPets = scanAllPets()
            end
        end
        if #allPets == 0 then isTeleporting = false; return end

        -- Respect SXEHub manual selection, then fall back to priority/mode
        local pet
        if manuallySelectedUID then
            for _, p in ipairs(allPets) do
                if p.plot and p.slot and (p.plot .. "_" .. tostring(p.slot)) == manuallySelectedUID then pet = p; break end
            end
        end
        if not pet then pet = _pickByMode(allPets) or allPets[1] end

        local _tpSpd = (Config and Config.TpSettings and Config.TpSettings.GrabbleTPSpeed) or 230
        local _cloneDelay = (Config and Config.TpSettings and Config.TpSettings.CloneDelayVal) or 0.35

        local petPos = pet.position
        local petName = pet.name

        local adjY = petPos.Y
        if TALL_PETS[petName] then adjY = petPos.Y - TALL_OFFSET end
        local coordTable = adjY > UPPER_Y_THRESHOLD and UPPER or LOWER

        -- CONVEYOR
        if pet.conveyor then
            local model = pet.model
            local maxHP = hum.MaxHealth
            hum.Health = maxHP
            local healConn = RunService.Heartbeat:Connect(function()
                if hum and hum.Parent then hum.Health = maxHP end
            end)
            carpetEngage()
            vZero(hrp)
            local function livePos()
                if not model or not model.Parent then return nil end
                local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                return part and part.Position or nil
            end
            local _t0 = os.clock()
            while os.clock() - _t0 < 8 do
                if not hrp or not hrp.Parent then break end
                local lp = livePos()
                if not lp then break end
                local diff = lp - hrp.Position
                if diff.Magnitude <= 6 then break end
                equipCarpet()
                hrp.AssemblyLinearVelocity = diff.Unit * _tpSpd
                RunService.Heartbeat:Wait()
            end
            if hrp and hrp.Parent then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end
            healConn:Disconnect()
            isTeleporting = false
            return
        end

        -- FIRST FLOOR
        if petPos.Y <= 8.9 and isPlotUnlocked(pet.plot) then
            local maxHP = hum.MaxHealth
            hum.Health = maxHP
            local healConn = RunService.Heartbeat:Connect(function()
                if hum and hum.Parent then hum.Health = maxHP end
            end)
            carpetEngage()
            vZero(hrp)
            local _to = Vector3.new(petPos.X, -4, petPos.Z)
            local _faceDir
            do
                local idx = getClosestBaseIdx(petPos)
                local _, frontFace = buildFrontCandidate(idx, false, hrp.Position.Z)
                _faceDir = frontFace
            end
            local route = computeRoute(hrp.Position, _to, _faceDir)
            if not route or #route == 0 then route = { _to } end
            velMoveThrough(hrp, route, _tpSpd, true, true)
            if hrp and hrp.Parent then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end
            healConn:Disconnect()
            isTeleporting = false
            return
        end

        -- SKY CLONE-TP
        _cloneTP = true
        disarmSteal()

        local closestData, skyKey = findClosest(petPos, coordTable)
        if not closestData or not skyKey then isTeleporting = false; return end

        local destPos = closestData.coord
        local maxHP = hum.MaxHealth
        hum.Health = maxHP
        local healConn = RunService.Heartbeat:Connect(function()
            if hum and hum.Parent then hum.Health = maxHP end
        end)

        carpetEngage()
        vZero(hrp)

        local facingDir = closestData.facing == "NORTH" and Vector3.new(0, 0, -1) or Vector3.new(0, 0, 1)
        do
            local isUpper = (coordTable == UPPER)
            local idx = getClosestBaseIdx(petPos)
            local frontCoord, frontFace = buildFrontCandidate(idx, isUpper, hrp.Position.Z)
            local bestCoord, bestFace = frontCoord, frontFace
            local bestDist = (hrp.Position - frontCoord).Magnitude
            for _, d in ipairs(plotSides(coordTable, idx)) do
                local dd = (hrp.Position - d.coord).Magnitude
                if dd < bestDist then
                    bestDist = dd
                    bestCoord = d.coord
                    bestFace = d.facing == "NORTH" and Vector3.new(0, 0, -1) or Vector3.new(0, 0, 1)
                end
            end
            destPos = bestCoord
            facingDir = bestFace
        end

        if hrp and hrp.Parent then
            hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + facingDir)
            hrp.AssemblyAngularVelocity = Vector3.zero
        end

        local _route = computeRoute(hrp.Position, destPos, facingDir)
        local _stepped = {}
        do
            local startY = hrp.Position.Y
            local destY = destPos.Y
            local prev = hrp.Position
            local totalFlat = 0
            for _, wp in ipairs(_route) do
                totalFlat = totalFlat + (Vector3.new(wp.X, 0, wp.Z) - Vector3.new(prev.X, 0, prev.Z)).Magnitude
                prev = wp
            end
            if totalFlat < 0.01 then totalFlat = 0.01 end
            local SEG = 30
            prev = hrp.Position
            local travelled = 0
            for _, wp in ipairs(_route) do
                local flatVec = Vector3.new(wp.X, 0, wp.Z) - Vector3.new(prev.X, 0, prev.Z)
                local legFlat = flatVec.Magnitude
                if legFlat >= 0.01 then
                    local subs = math.max(1, math.ceil(legFlat / SEG))
                    for s = 1, subs do
                        local f = s / subs
                        local px = prev.X + (wp.X - prev.X) * f
                        local pz = prev.Z + (wp.Z - prev.Z) * f
                        local along = travelled + legFlat * f
                        local rampY = startY + (destY - startY) * (along / totalFlat)
                        _stepped[#_stepped + 1] = Vector3.new(px, rampY, pz)
                    end
                else
                    _stepped[#_stepped + 1] = wp
                end
                travelled = travelled + legFlat
                prev = wp
            end
            if #_stepped > 0 then _stepped[#_stepped] = _route[#_route] end
        end
        velMoveThrough(hrp, _stepped, _tpSpd, true, true)

        hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
        vZero(hrp)

        local syncFrames = 14
        local syncConn
        syncConn = RunService.Heartbeat:Connect(function()
            if not hrp or not hrp.Parent then syncConn:Disconnect(); return end
            syncFrames = syncFrames - 1
            hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            if syncFrames <= 0 then syncConn:Disconnect() end
        end)

        for _ = 1, 20 do
            task.wait(0.05)
            if hum.FloorMaterial ~= Enum.Material.Air then break end
        end

        healConn:Disconnect()
        armSteal(pet)
        _cloneFired = true

        local _ahrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local _clonePos = (_ahrp and _ahrp.Parent and _ahrp.Position) or destPos

        local _clonePlat = Instance.new("Part")
        _clonePlat.Name = "SXEClonePlatform"
        _clonePlat.Size = Vector3.new(12, 1, 12)
        _clonePlat.Position = Vector3.new(_clonePos.X, _clonePos.Y - 3, _clonePos.Z)
        _clonePlat.Anchored = true; _clonePlat.CanCollide = false; pcall(makeOneWay, _clonePlat); _clonePlat.Transparency = 1
        _clonePlat.Material = Enum.Material.SmoothPlastic; _clonePlat.Parent = workspace

        if _ahrp and _ahrp.Parent then
            _ahrp.AssemblyLinearVelocity = Vector3.zero
            _ahrp.AssemblyAngularVelocity = Vector3.zero
            pcall(function() _ahrp.Anchored = true end)
            task.delay(1, function()
                if _ahrp and _ahrp.Parent then pcall(function() _ahrp.Anchored = false end) end
            end)
        end

        local _charAdded = false
        local _caConn = LP.CharacterAdded:Connect(function() _charAdded = true end)

        task.wait(_cloneDelay)
        local _cloneOk = doClone()

        if _clonePlat then pcall(function() _clonePlat:Destroy() end); _clonePlat = nil end
        if _cloneOk then
            task.wait(0.3)
            local _cloneSucceeded = false
            do
                local _c = LP.Character
                local _h = _c and _c:FindFirstChild("HumanoidRootPart")
                local plotsFolder = workspace:FindFirstChild("Plots")
                if _h and plotsFolder then
                    local _rad = (petPos.Y <= 8.9) and 26 or 25
                    local p = _h.Position
                    for _, plot in ipairs(plotsFolder:GetChildren()) do
                        pcall(function()
                            local pp = plot:GetPivot().Position
                            if math.abs(p.X - pp.X) < _rad and math.abs(p.Z - pp.Z) < _rad then
                                _cloneSucceeded = true
                            end
                        end)
                        if _cloneSucceeded then break end
                    end
                end
            end
            if _caConn then _caConn:Disconnect() end
            if _cloneSucceeded then goToBrainrot(petPos) end
        else
            if _caConn then _caConn:Disconnect() end
        end
        isTeleporting = false
    end

    doGrabbleVelocityTP = doVelocityTP
    _G.SXEStartSideTP = doVelocityTP
    _G.SXEGoToBrainrot = goToBrainrot

    _G.SXE_ExecuteManualTP = function()
        task.spawn(function() pcall(doVelocityTP) end)
    end

    UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.T then
            task.spawn(function() pcall(doVelocityTP) end)
        end
    end)

    -- Boot
    task.spawn(function() pcall(loadModules) pcall(loadNet) end)
    task.spawn(function()
        local char = LP.Character or LP.CharacterAdded:Wait()
        char:WaitForChild("HumanoidRootPart", 10)
        char:WaitForChild("Humanoid", 10)
        pcall(loadModules); pcall(loadNet)
        local _t0 = os.clock()
        repeat
            local ok, pets = pcall(scanAllPets)
            if ok and pets and #pets > 0 then break end
            task.wait(0.3)
        until os.clock() - _t0 > 12
        _started = true
    end)
end

do
_G.VanishStartSideTP = doGrabbleVelocityTP
_G.TPVelocity = math.clamp(tonumber(_G.TPVelocity) or 400, 200, 500)
_G.LandingDelay = math.clamp(tonumber(_G.LandingDelay) or 0.4, 0.15, 0.75)
_G._stp_tpDelay = _G._stp_tpDelay or 0
local _SAVE_FILE = "chopper_HUB.json"
local _HttpService = game:GetService("HttpService")
local _TeleportService = game:GetService("TeleportService")
local function _stp_readRoot()
	if not (readfile and isfile) then return {} end
	local ok, root = pcall(function()
		if isfile(_SAVE_FILE) then
			return _HttpService:JSONDecode(readfile(_SAVE_FILE))
		end
	end)
	return (ok and type(root) == "table") and root or {}
end
local function _stp_loadSaved()
	local data = nil

	pcall(function()
		local td = _TeleportService:GetLocalPlayerTeleportData()
		if td and td.SideTP then data = td.SideTP end
	end)

	if not data then
		local root = _stp_readRoot()
		if type(root.sideTP) == "table" then data = root.sideTP end
	else
		-- toujours merger depuis le fichier pour les positions UI (pas dans les données TP)
		local root = _stp_readRoot()
		if type(root.sideTP) == "table" then
			if type(root.sideTP.panelX) == "number" then data.panelX = root.sideTP.panelX end
			if type(root.sideTP.panelY) == "number" then data.panelY = root.sideTP.panelY end
		end
	end
	return data or {}
end
local function _stp_saveCurrent()
	if not writefile then return end
	local payload = {
		tpDelay = _G._stp_tpDelay or 0,
		tpVelocity = _G.TPVelocity or 400,
		landingDelay = _G.LandingDelay or 0.4,
		tpKey = _G._stp_tpKeyName or "T",
		priorityList = _G.SHARED_PRIORITY_ITEMS,
		priorityListVersion = _G._priorityListVersion or 0,
		panelX = _G._stp_panelX,
		panelY = _G._stp_panelY,
	}
	local root = _stp_readRoot()
	root.sideTP = payload
	pcall(function() writefile(_SAVE_FILE, _HttpService:JSONEncode(root)) end)
end
_G._stp_saveCurrent = _stp_saveCurrent
do
	local s = _stp_loadSaved()
	if type(s.tpDelay) == "number" then _G._stp_tpDelay = s.tpDelay end
	if type(s.tpVelocity) == "number" then _G.TPVelocity = math.clamp(s.tpVelocity, 200, 500) end
	if type(s.landingDelay) == "number" then _G.LandingDelay = math.clamp(s.landingDelay, 0.15, 0.75) end
	if type(s.tpKey) == "string" then _G._stp_tpKeyName = s.tpKey end
	if type(s.priorityList) == "table" and #s.priorityList > 0 then
		_G.SHARED_PRIORITY_ITEMS = s.priorityList
	end
	if type(s.panelX) == "number" then _G._stp_panelX = s.panelX end
	if type(s.panelY) == "number" then _G._stp_panelY = s.panelY end

	local savedVersion = tonumber(s.priorityListVersion) or 0
	if savedVersion < 2 then
		_G.SHARED_PRIORITY_ITEMS = {
			"signore carapace","headless horseman","strawberry elephant","john pork","arcadragon",
			"elefanto frigo","meowl","skibidi toilet","griffin","love love bear",
			"antonio","dragon gingerini","dragon aquanini","pancake and syrup","fishino clownino",
			"la supreme combinasion","ginger gerat","rico dinero","kalika bros","tirilikalika tirilikalako",
			"digi narwhal","hydra bunny","bunny and eggy","dragon cannelloni","hydra dragon cannelloni",
			"globa steppa","dug dug dug","los hackers","lazy ducky","duggy bros",
			"pineaplino","ketupat bros","la casa boo","cerberus","rosey and teddy",
			"foxini lanternini","spooky and pumpky","john doe","fragola la la la","guest 666",
			"cooki and milki","quackini snackini","reinito sleighito","popcuru and fizzuru","gym bros",
			"capitano moby","burguro and fryuro","garama and madundung","fragrama and chocrama",
		}
		_G._priorityListVersion = 2
		if _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end
	else
		_G._priorityListVersion = savedVersion
	end
end

if type(_G.SHARED_PRIORITY_ITEMS) ~= "table" or #_G.SHARED_PRIORITY_ITEMS == 0 then
	_G.SHARED_PRIORITY_ITEMS = {
		"headless horseman","strawberry elephant","signore carapace","meowl","skibidi toilet",
		"griffin","dragon gingerini","la supreme combinasion","dragon cannelloni",
		"hydra dragon cannelloni","love love bear","elefanto frigo","ginger gerat","antonio",
		"ketupat bros","tirilikalika tirilikalako","dug dug dug","fishino clownino",
		"foxini lanternini","cerberus","la casa boo","hydra bunny",
		"boppin bunny","capitano moby","fortunu and cashuru","celestial pegasus",
		"rosey and teddy","burguro and fryuro","spooky and pumpky","cooki and milki",
		"los amigos","popcuru and fizzuru","reinito sleighito","fragrama and chocrama",
		"festive 67","garama and madundung","ketchuru and musturu","la secret combinasion",
		"tralaledon","tictac sahur","ketupat kepat","tang tang keletang","orcaledon",
		"la ginger sekolah","los spaghettis","lavadorito spinito","swaggy bros",
		"la taco combinasion","los primos","chillin chili","tuff toucan","w or l",
		"chipso and queso",
		"money money bros","cash or card","la spooky grande","los bros","los candies",
		"los sekolahs","nacho spyder","la easter grande","quackini snackini","los chillis",
		"la anniversary grande","las sis","spaghetti tualetti","ventoliero pavonero","los tacoritas",
		"rosetti tualetti","eviledon","la lucky grande","la extinct grande","john doe",
		"la romantic grande","los hackers","los planitos","los puggies","la jolly grande",
		"gym bros","swag soda","sammyni fattini","los hotspotsitos","celularcini viciosini",
		"bunny and eggy","guest 666","digi narwhal","duggy bros","globa steppa",
		"jelly moby","kalika bros","arcadragon","pancake and syrup","rico dinero",
		"john pork"
	}
end

do
	local NEW_PRIORITY_ITEMS = {
		"money money bros","cash or card","la spooky grande","los bros","los candies",
		"los sekolahs","nacho spyder","la easter grande","quackini snackini","los chillis",
		"la anniversary grande","las sis","spaghetti tualetti","ventoliero pavonero","los tacoritas",
		"rosetti tualetti","eviledon","la lucky grande","la extinct grande","john doe",
		"la romantic grande","los hackers","los planitos","los puggies","la jolly grande",
		"gym bros","swag soda","sammyni fattini","los hotspotsitos","celularcini viciosini",
		"bunny and eggy","guest 666","digi narwhal","duggy bros","globa steppa",
		"jelly moby","kalika bros","arcadragon","pancake and syrup","rico dinero",
		"john pork"
	}
	local existing = {}
	for _, name in ipairs(_G.SHARED_PRIORITY_ITEMS) do
		existing[tostring(name):lower()] = true
	end
	local changed = false
	for _, name in ipairs(NEW_PRIORITY_ITEMS) do
		if not existing[name] then
			table.insert(_G.SHARED_PRIORITY_ITEMS, name)
			existing[name] = true
			changed = true
		end
	end
	if changed and _G._stp_saveCurrent then pcall(_G._stp_saveCurrent) end
end
end

task.spawn(function()
	local _UIS = game:GetService("UserInputService")
	local TweenService = game:GetService("TweenService")
	local Players = game:GetService("Players")
	local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() or Players.LocalPlayer
	if not LocalPlayer then return end
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

	local TP_KEY = Enum.KeyCode.T
	pcall(function()
		local n = _G._stp_tpKeyName
		if type(n) == "string" and Enum.KeyCode[n] then TP_KEY = Enum.KeyCode[n] end
	end)
	local C_BG = Color3.fromRGB(255, 252, 255)
	local C_SURFACE = Color3.fromRGB(252, 245, 249)
	local C_SELECTED = Color3.fromRGB(252, 225, 240)
	local C_BORDER = Color3.fromRGB(238, 188, 219)
	local C_TEXT = Color3.fromRGB(40, 15, 30)
	local C_TEXT_DIM = Color3.fromRGB(140, 80, 115)
	local C_GREEN = Color3.fromRGB(232, 111, 177)
	local C_ACCENT = Color3.fromRGB(232, 111, 177)

	local sg = Instance.new("ScreenGui")
	sg.Name = "XenSideTPPanel"
	sg.ResetOnSpawn = false
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local _cloneref = cloneref or function(x) return x end
	pcall(function() sg.Parent = _cloneref(game:GetService("CoreGui")) end)
	if not sg.Parent then sg.Parent = PlayerGui end

	local mf = Instance.new("Frame")
	mf.Size = UDim2.new(0, 260, 0, 280)
	mf.Position = UDim2.new(0, _G._stp_panelX or 20, 0, _G._stp_panelY or 300)
	mf.BackgroundColor3 = C_BG
	mf.BackgroundTransparency = 0.02
	mf.BorderSizePixel = 0
	mf.Parent = sg
	Instance.new("UICorner", mf).CornerRadius = UDim.new(0, 12)
	local mfStroke = Instance.new("UIStroke", mf)
	mfStroke.Color = C_BORDER; mfStroke.Thickness = 1; mfStroke.Transparency = 0.3

	local titleLabel = Instance.new("TextLabel", mf)
	titleLabel.Size = UDim2.new(1, 0, 0, 32)
	titleLabel.Position = UDim2.new(0, 0, 0, 6)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Meerko TP"
	titleLabel.TextColor3 = Color3.fromRGB(232, 111, 177)
	titleLabel.TextSize = 18
	titleLabel.Font = Enum.Font.GothamBlack

	local div = Instance.new("Frame", mf)
	div.Size = UDim2.new(1, -20, 0, 1)
	div.Position = UDim2.new(0, 10, 0, 42)
	div.BackgroundColor3 = C_BORDER
	div.BackgroundTransparency = 0.5
	div.BorderSizePixel = 0

	local dg, ds, sp = false, nil, nil
	titleLabel.Active = true
	titleLabel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dg = true
			ds = input.Position
			sp = UDim2.new(0, mf.AbsolutePosition.X, 0, mf.AbsolutePosition.Y)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dg = false
					_G._stp_panelX = mf.Position.X.Offset
					_G._stp_panelY = mf.Position.Y.Offset
					if _G._stp_saveCurrent then _G._stp_saveCurrent() end
				end
			end)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if dg and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - ds
			local newX = sp.X.Offset + d.X
			local newY = sp.Y.Offset + d.Y
			local viewportSize = workspace.CurrentCamera.ViewportSize
			newX = math.clamp(newX, 0, viewportSize.X - mf.AbsoluteSize.X)
			newY = math.clamp(newY, 0, viewportSize.Y - mf.AbsoluteSize.Y)
			mf.Position = UDim2.new(0, newX, 0, newY)
		end
	end)

	local buttonArea = Instance.new("Frame", mf)
	buttonArea.Size = UDim2.new(1, -24, 0, 246)
	buttonArea.Position = UDim2.new(0, 12, 0, 48)
	buttonArea.BackgroundTransparency = 1
	local btnLayout = Instance.new("UIListLayout", buttonArea)
	btnLayout.Padding = UDim.new(0, 10)
	btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local tpBtn = Instance.new("TextButton", buttonArea)
	tpBtn.Size = UDim2.new(1, 0, 0, 34)
	tpBtn.BackgroundColor3 = C_SURFACE
	tpBtn.Text = "Manual TP"
	tpBtn.TextColor3 = C_TEXT_DIM
	tpBtn.TextSize = 13
	tpBtn.Font = Enum.Font.GothamBold
	tpBtn.AutoButtonColor = false
	tpBtn.LayoutOrder = 0
	tpBtn.BorderSizePixel = 0
	Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 8)
	local tpStroke = Instance.new("UIStroke", tpBtn)
	tpStroke.Color = C_BORDER; tpStroke.Thickness = 1; tpStroke.Transparency = 0.5
	tpBtn.MouseEnter:Connect(function()
		TweenService:Create(tpBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(50,56,72), TextColor3 = C_TEXT}):Play()
	end)
	tpBtn.MouseLeave:Connect(function()
		TweenService:Create(tpBtn, TweenInfo.new(0.1), {BackgroundColor3 = C_SURFACE, TextColor3 = C_TEXT_DIM}):Play()
	end)
	tpBtn.MouseButton1Click:Connect(function()
		task.spawn(function() if _G.VanishStartSideTP then _G.VanishStartSideTP() end end)
	end)

	local tpBindBtn = Instance.new("TextButton", tpBtn)
	tpBindBtn.Size = UDim2.new(0, 30, 0, 16)
	tpBindBtn.Position = UDim2.new(1, -36, 0.5, -8)
	tpBindBtn.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
	tpBindBtn.Text = TP_KEY.Name
	tpBindBtn.TextColor3 = C_ACCENT
	tpBindBtn.TextSize = 9
	tpBindBtn.Font = Enum.Font.GothamBold
	tpBindBtn.AutoButtonColor = false
	tpBindBtn.BorderSizePixel = 0
	tpBindBtn.ZIndex = 2
	Instance.new("UICorner", tpBindBtn).CornerRadius = UDim.new(0, 4)
	local tpBindStroke = Instance.new("UIStroke", tpBindBtn)
	tpBindStroke.Color = C_BORDER; tpBindStroke.Thickness = 1; tpBindStroke.Transparency = 0.5

	local listeningForTPBind = false
	tpBindBtn.MouseButton1Click:Connect(function()
		if listeningForTPBind then return end
		listeningForTPBind = true
		tpBindBtn.Text = "..."
		tpBindBtn.TextColor3 = C_TEXT_DIM
		local conn
		conn = _UIS.InputBegan:Connect(function(input, processed)
			if processed then return end
			if input.UserInputType == Enum.UserInputType.Keyboard then
				local name = input.KeyCode.Name
				if name and name ~= "Unknown" then
					TP_KEY = input.KeyCode
					tpBindBtn.Text = name
					tpBindBtn.TextColor3 = C_ACCENT
					_G._stp_tpKeyName = name
					if _G._stp_saveCurrent then _G._stp_saveCurrent() end
				end
			end
			listeningForTPBind = false
			if conn then conn:Disconnect() end
		end)
		task.delay(5, function()
			if listeningForTPBind then
				listeningForTPBind = false
				if conn then conn:Disconnect() end
				tpBindBtn.Text = TP_KEY.Name
				tpBindBtn.TextColor3 = C_ACCENT
			end
		end)
	end)

	_G._stp_tpDelay = _G._stp_tpDelay or 0
	local _tpDelay = _G._stp_tpDelay
	local DELAY_MIN = 0
	local DELAY_MAX = 0.9
	local delayFrame = Instance.new("Frame", buttonArea)
	delayFrame.Size = UDim2.new(1, 0, 0, 38)
	delayFrame.BackgroundTransparency = 1
	delayFrame.LayoutOrder = 3

	local delayLabel = Instance.new("TextLabel", delayFrame)
	delayLabel.Size = UDim2.new(1, -60, 0, 16)
	delayLabel.Position = UDim2.new(0, 0, 0, 0)
	delayLabel.BackgroundTransparency = 1
	delayLabel.Text = "Delay Before TP (ms):"
	delayLabel.TextColor3 = C_TEXT_DIM
	delayLabel.TextSize = 12
	delayLabel.Font = Enum.Font.GothamBold
	delayLabel.TextXAlignment = Enum.TextXAlignment.Left

	local delayValueLabel = Instance.new("TextLabel", delayFrame)
	delayValueLabel.Size = UDim2.new(0, 60, 0, 16)
	delayValueLabel.Position = UDim2.new(1, -60, 0, 0)
	delayValueLabel.BackgroundTransparency = 1
	delayValueLabel.Text = "0ms"
	delayValueLabel.TextColor3 = C_TEXT
	delayValueLabel.TextSize = 12
	delayValueLabel.Font = Enum.Font.GothamBold
	delayValueLabel.TextXAlignment = Enum.TextXAlignment.Right

	local delayTrack = Instance.new("Frame", delayFrame)
	delayTrack.Size = UDim2.new(1, 0, 0, 8)
	delayTrack.Position = UDim2.new(0, 0, 0, 24)
	delayTrack.BackgroundColor3 = C_SURFACE
	delayTrack.BorderSizePixel = 0
	Instance.new("UICorner", delayTrack).CornerRadius = UDim.new(1, 0)

	local delayFill = Instance.new("Frame", delayTrack)
	delayFill.Size = UDim2.new(0, 0, 1, 0)
	delayFill.BackgroundColor3 = C_ACCENT
	delayFill.BorderSizePixel = 0
	Instance.new("UICorner", delayFill).CornerRadius = UDim.new(1, 0)

	local delayKnob = Instance.new("Frame", delayTrack)
	delayKnob.Size = UDim2.new(0, 14, 0, 14)
	delayKnob.Position = UDim2.new(0, -7, 0.5, -7)
	delayKnob.BackgroundColor3 = C_TEXT
	delayKnob.BorderSizePixel = 0
	delayKnob.ZIndex = 3
	Instance.new("UICorner", delayKnob).CornerRadius = UDim.new(1, 0)

	local function updateDelayVisual()
		local frac = (_tpDelay - DELAY_MIN) / (DELAY_MAX - DELAY_MIN)
		delayFill.Size = UDim2.new(frac, 0, 1, 0)
		delayKnob.Position = UDim2.new(frac, -7, 0.5, -7)
		delayValueLabel.Text = string.format("%dms", math.floor(_tpDelay * 1000 + 0.5))
	end
	updateDelayVisual()

	local delayDragging = false
	local delaySliderBtn = Instance.new("TextButton", delayTrack)
	delaySliderBtn.Size = UDim2.new(1, 0, 1, 10)
	delaySliderBtn.Position = UDim2.new(0, 0, 0, -5)
	delaySliderBtn.BackgroundTransparency = 1
	delaySliderBtn.Text = ""
	delaySliderBtn.ZIndex = 2
	local function handleDelayInput(xPos)
		local tx = delayTrack.AbsolutePosition.X
		local tw = delayTrack.AbsoluteSize.X
		local frac = math.clamp((xPos - tx) / tw, 0, 1)

		local raw = DELAY_MIN + frac * (DELAY_MAX - DELAY_MIN)
		_tpDelay = math.floor(raw * 100 + 0.5) / 100
		_tpDelay = math.clamp(_tpDelay, DELAY_MIN, DELAY_MAX)
		_G._stp_tpDelay = _tpDelay
		updateDelayVisual()
	end
	delaySliderBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			delayDragging = true
			handleDelayInput(input.Position.X)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if delayDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			handleDelayInput(input.Position.X)
		end
	end)
	_UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if delayDragging then
				delayDragging = false
				if _G._stp_saveCurrent then _G._stp_saveCurrent() end
			end
		end
	end)

	_G.LandingDelay = math.clamp(tonumber(_G.LandingDelay) or 0.4, 0.15, 0.75)
	local _landingDelay = _G.LandingDelay
	local LD_MIN = 0.15
	local LD_MAX = 0.75
	local ldFrame = Instance.new("Frame", buttonArea)
	ldFrame.Size = UDim2.new(1, 0, 0, 38)
	ldFrame.BackgroundTransparency = 1
	ldFrame.LayoutOrder = 4

	local ldLabel = Instance.new("TextLabel", ldFrame)
	ldLabel.Size = UDim2.new(1, -60, 0, 16)
	ldLabel.Position = UDim2.new(0, 0, 0, 0)
	ldLabel.BackgroundTransparency = 1
	ldLabel.Text = "Landing Delay Before Clone:"
	ldLabel.TextColor3 = C_TEXT_DIM
	ldLabel.TextSize = 12
	ldLabel.Font = Enum.Font.GothamBold
	ldLabel.TextXAlignment = Enum.TextXAlignment.Left

	local ldValueLabel = Instance.new("TextLabel", ldFrame)
	ldValueLabel.Size = UDim2.new(0, 60, 0, 16)
	ldValueLabel.Position = UDim2.new(1, -60, 0, 0)
	ldValueLabel.BackgroundTransparency = 1
	ldValueLabel.Text = string.format("%.2fs", _landingDelay)
	ldValueLabel.TextColor3 = C_TEXT
	ldValueLabel.TextSize = 12
	ldValueLabel.Font = Enum.Font.GothamBold
	ldValueLabel.TextXAlignment = Enum.TextXAlignment.Right

	local ldTrack = Instance.new("Frame", ldFrame)
	ldTrack.Size = UDim2.new(1, 0, 0, 8)
	ldTrack.Position = UDim2.new(0, 0, 0, 24)
	ldTrack.BackgroundColor3 = C_SURFACE
	ldTrack.BorderSizePixel = 0
	Instance.new("UICorner", ldTrack).CornerRadius = UDim.new(1, 0)

	local ldFill = Instance.new("Frame", ldTrack)
	ldFill.Size = UDim2.new(0, 0, 1, 0)
	ldFill.BackgroundColor3 = C_ACCENT
	ldFill.BorderSizePixel = 0
	Instance.new("UICorner", ldFill).CornerRadius = UDim.new(1, 0)

	local ldKnob = Instance.new("Frame", ldTrack)
	ldKnob.Size = UDim2.new(0, 14, 0, 14)
	ldKnob.Position = UDim2.new(0, -7, 0.5, -7)
	ldKnob.BackgroundColor3 = C_TEXT
	ldKnob.BorderSizePixel = 0
	ldKnob.ZIndex = 3
	Instance.new("UICorner", ldKnob).CornerRadius = UDim.new(1, 0)

	local function updateLdVisual()
		local frac = (_landingDelay - LD_MIN) / (LD_MAX - LD_MIN)
		ldFill.Size = UDim2.new(frac, 0, 1, 0)
		ldKnob.Position = UDim2.new(frac, -7, 0.5, -7)
		ldValueLabel.Text = string.format("%.2fs", _landingDelay)
	end
	updateLdVisual()

	local ldDragging = false
	local ldSliderBtn = Instance.new("TextButton", ldTrack)
	ldSliderBtn.Size = UDim2.new(1, 0, 1, 10)
	ldSliderBtn.Position = UDim2.new(0, 0, 0, -5)
	ldSliderBtn.BackgroundTransparency = 1
	ldSliderBtn.Text = ""
	ldSliderBtn.ZIndex = 2
	local function handleLdInput(xPos)
		local tx = ldTrack.AbsolutePosition.X
		local tw = ldTrack.AbsoluteSize.X
		local frac = math.clamp((xPos - tx) / tw, 0, 1)

		local raw = LD_MIN + frac * (LD_MAX - LD_MIN)
		_landingDelay = math.floor(raw * 100 + 0.5) / 100
		_landingDelay = math.clamp(_landingDelay, LD_MIN, LD_MAX)
		_G.LandingDelay = _landingDelay
		updateLdVisual()
	end
	ldSliderBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			ldDragging = true
			handleLdInput(input.Position.X)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if ldDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			handleLdInput(input.Position.X)
		end
	end)
	_UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if ldDragging then
				ldDragging = false
				if _G._stp_saveCurrent then _G._stp_saveCurrent() end
			end
		end
	end)

	local VEL_MIN = 200
	local VEL_MAX = 500
	_G.TPVelocity = math.clamp(tonumber(_G.TPVelocity) or 400, VEL_MIN, VEL_MAX)
	local velFrame = Instance.new("Frame", buttonArea)
	velFrame.Size = UDim2.new(1, 0, 0, 38)
	velFrame.BackgroundTransparency = 1
	velFrame.LayoutOrder = 5

	local velLabel = Instance.new("TextLabel", velFrame)
	velLabel.Size = UDim2.new(1, -70, 0, 16)
	velLabel.Position = UDim2.new(0, 0, 0, 0)
	velLabel.BackgroundTransparency = 1
	velLabel.Text = "TP Velocity:"
	velLabel.TextColor3 = C_TEXT_DIM
	velLabel.TextSize = 12
	velLabel.Font = Enum.Font.GothamBold
	velLabel.TextXAlignment = Enum.TextXAlignment.Left

	local velValueLabel = Instance.new("TextLabel", velFrame)
	velValueLabel.Size = UDim2.new(0, 70, 0, 16)
	velValueLabel.Position = UDim2.new(1, -70, 0, 0)
	velValueLabel.BackgroundTransparency = 1
	velValueLabel.Text = tostring(_G.TPVelocity)
	velValueLabel.TextColor3 = C_TEXT
	velValueLabel.TextSize = 12
	velValueLabel.Font = Enum.Font.GothamBold
	velValueLabel.TextXAlignment = Enum.TextXAlignment.Right

	local velTrack = Instance.new("Frame", velFrame)
	velTrack.Size = UDim2.new(1, 0, 0, 8)
	velTrack.Position = UDim2.new(0, 0, 0, 24)
	velTrack.BackgroundColor3 = C_SURFACE
	velTrack.BorderSizePixel = 0
	Instance.new("UICorner", velTrack).CornerRadius = UDim.new(1, 0)

	local velFill = Instance.new("Frame", velTrack)
	velFill.Size = UDim2.new(0, 0, 1, 0)
	velFill.BackgroundColor3 = C_ACCENT
	velFill.BorderSizePixel = 0
	Instance.new("UICorner", velFill).CornerRadius = UDim.new(1, 0)

	local velKnob = Instance.new("Frame", velTrack)
	velKnob.Size = UDim2.new(0, 14, 0, 14)
	velKnob.Position = UDim2.new(0, -7, 0.5, -7)
	velKnob.BackgroundColor3 = C_TEXT
	velKnob.BorderSizePixel = 0
	velKnob.ZIndex = 3
	Instance.new("UICorner", velKnob).CornerRadius = UDim.new(1, 0)

	local function updateVelVisual()
		local frac = (_G.TPVelocity - VEL_MIN) / (VEL_MAX - VEL_MIN)
		velFill.Size = UDim2.new(frac, 0, 1, 0)
		velKnob.Position = UDim2.new(frac, -7, 0.5, -7)
		velValueLabel.Text = tostring(_G.TPVelocity)
	end
	updateVelVisual()

	local velDragging = false
	local velSliderBtn = Instance.new("TextButton", velTrack)
	velSliderBtn.Size = UDim2.new(1, 0, 1, 10)
	velSliderBtn.Position = UDim2.new(0, 0, 0, -5)
	velSliderBtn.BackgroundTransparency = 1
	velSliderBtn.Text = ""
	velSliderBtn.ZIndex = 2
	local function handleVelInput(xPos)
		local tx = velTrack.AbsolutePosition.X
		local tw = velTrack.AbsoluteSize.X
		local frac = math.clamp((xPos - tx) / tw, 0, 1)
		local raw = VEL_MIN + frac * (VEL_MAX - VEL_MIN)

		_G.TPVelocity = math.floor(raw / 10 + 0.5) * 10
		_G.TPVelocity = math.clamp(_G.TPVelocity, VEL_MIN, VEL_MAX)
		updateVelVisual()
	end
	velSliderBtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			velDragging = true
			handleVelInput(input.Position.X)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if velDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			handleVelInput(input.Position.X)
		end
	end)
	_UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if velDragging then
				velDragging = false
				if _G._stp_saveCurrent then _G._stp_saveCurrent() end
			end
		end
	end)

	local customizeBtn = Instance.new("TextButton", buttonArea)
	customizeBtn.Size = UDim2.new(1, 0, 0, 34)
	customizeBtn.BackgroundColor3 = C_ACCENT
	customizeBtn.Text = "Edit Priority"
	customizeBtn.TextColor3 = C_TEXT
	customizeBtn.TextSize = 13
	customizeBtn.Font = Enum.Font.GothamBold
	customizeBtn.AutoButtonColor = false
	customizeBtn.LayoutOrder = 1
	customizeBtn.BorderSizePixel = 0
	Instance.new("UICorner", customizeBtn).CornerRadius = UDim.new(0, 8)
	customizeBtn.MouseEnter:Connect(function()
		TweenService:Create(customizeBtn, TweenInfo.new(0.1), {BackgroundColor3 = Color3.fromRGB(100, 140, 190)}):Play()
	end)
	customizeBtn.MouseLeave:Connect(function()
		TweenService:Create(customizeBtn, TweenInfo.new(0.1), {BackgroundColor3 = C_ACCENT}):Play()
	end)

	local priorityPopup = Instance.new("Frame", sg)
	_G.SXEOpenPriorityEditor = function() priorityPopup.Visible = true end
	priorityPopup.Size = UDim2.new(0, 400, 0, 560)
	priorityPopup.Position = UDim2.new(0.5, -200, 0.5, -280)
	priorityPopup.BackgroundColor3 = C_BG
	priorityPopup.BackgroundTransparency = 0.02
	priorityPopup.BorderSizePixel = 0
	priorityPopup.Visible = false
	priorityPopup.ZIndex = 50
	Instance.new("UICorner", priorityPopup).CornerRadius = UDim.new(0, 12)
	local popStroke = Instance.new("UIStroke", priorityPopup)
	popStroke.Color = Color3.fromRGB(255, 255, 255); popStroke.Thickness = 1; popStroke.Transparency = 0.96

	local popTitle = Instance.new("TextLabel", priorityPopup)
	popTitle.Size = UDim2.new(1, -40, 0, 40)
	popTitle.Position = UDim2.new(0, 10, 0, 2)
	popTitle.BackgroundTransparency = 1
	popTitle.Text = "Priority List"
	popTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	popTitle.TextSize = 18
	popTitle.Font = Enum.Font.BuilderSans
	popTitle.TextXAlignment = Enum.TextXAlignment.Center
	popTitle.ZIndex = 51

	local popClose = Instance.new("TextButton", priorityPopup)
	popClose.Size = UDim2.new(0, 28, 0, 28)
	popClose.Position = UDim2.new(1, -34, 0, 8)
	popClose.BackgroundTransparency = 1
	popClose.Text = "x"
	popClose.TextColor3 = C_TEXT_DIM
	popClose.TextSize = 16
	popClose.Font = Enum.Font.BuilderSans
	popClose.AutoButtonColor = false
	popClose.ZIndex = 52
	popClose.MouseEnter:Connect(function() popClose.TextColor3 = C_TEXT end)
	popClose.MouseLeave:Connect(function() popClose.TextColor3 = C_TEXT_DIM end)

	local popDiv = Instance.new("Frame", priorityPopup)
	popDiv.Size = UDim2.new(1, -20, 0, 1)
	popDiv.Position = UDim2.new(0, 10, 0, 42)
	popDiv.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	popDiv.BackgroundTransparency = 0.92
	popDiv.BorderSizePixel = 0
	popDiv.ZIndex = 51

	local searchRow = Instance.new("Frame", priorityPopup)
	searchRow.Size = UDim2.new(1, -20, 0, 32)
	searchRow.Position = UDim2.new(0, 10, 0, 48)
	searchRow.BackgroundTransparency = 1
	searchRow.ZIndex = 51

	local searchInput = Instance.new("TextBox", searchRow)
	searchInput.Size = UDim2.new(1, 0, 1, 0)
	searchInput.BackgroundColor3 = C_SURFACE
	searchInput.Text = ""
	searchInput.PlaceholderText = "Search..."
	searchInput.PlaceholderColor3 = C_TEXT_DIM
	searchInput.TextColor3 = C_TEXT
	searchInput.TextSize = 12
	searchInput.Font = Enum.Font.BuilderSans
	searchInput.ClearTextOnFocus = false
	searchInput.TextXAlignment = Enum.TextXAlignment.Left
	searchInput.BorderSizePixel = 0
	searchInput.ZIndex = 52
	Instance.new("UICorner", searchInput).CornerRadius = UDim.new(0, 6)
	Instance.new("UIPadding", searchInput).PaddingLeft = UDim.new(0, 8)
	local searchStroke = Instance.new("UIStroke", searchInput)
	searchStroke.Color = Color3.fromRGB(255, 255, 255); searchStroke.Thickness = 1; searchStroke.Transparency = 0.96

	local popScroll = Instance.new("ScrollingFrame", priorityPopup)
	popScroll.Size = UDim2.new(1, -20, 1, -130)
	popScroll.Position = UDim2.new(0, 10, 0, 86)
	popScroll.BackgroundTransparency = 1
	popScroll.ScrollBarThickness = 4
	popScroll.ScrollBarImageColor3 = C_ACCENT
	popScroll.ScrollBarImageTransparency = 0.4
	popScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	popScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	popScroll.BorderSizePixel = 0
	popScroll.ZIndex = 51
	local popLayout = Instance.new("UIListLayout", popScroll)
	popLayout.Padding = UDim.new(0, 3)
	popLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local addDiv = Instance.new("Frame", priorityPopup)
	addDiv.Size = UDim2.new(1, -20, 0, 1)
	addDiv.Position = UDim2.new(0, 10, 1, -40)
	addDiv.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	addDiv.BackgroundTransparency = 0.92
	addDiv.BorderSizePixel = 0
	addDiv.ZIndex = 51

	local addRow = Instance.new("Frame", priorityPopup)
	addRow.Size = UDim2.new(1, -20, 0, 32)
	addRow.Position = UDim2.new(0, 10, 1, -36)
	addRow.BackgroundTransparency = 1
	addRow.ZIndex = 51

	local addInput = Instance.new("TextBox", addRow)
	addInput.Size = UDim2.new(1, -58, 1, 0)
	addInput.BackgroundColor3 = C_SURFACE
	addInput.Text = ""
	addInput.PlaceholderText = "Add brainrot name..."
	addInput.PlaceholderColor3 = C_TEXT_DIM
	addInput.TextColor3 = C_TEXT
	addInput.TextSize = 12
	addInput.Font = Enum.Font.BuilderSans
	addInput.ClearTextOnFocus = false
	addInput.TextXAlignment = Enum.TextXAlignment.Left
	addInput.BorderSizePixel = 0
	addInput.ZIndex = 52
	Instance.new("UICorner", addInput).CornerRadius = UDim.new(0, 6)
	Instance.new("UIPadding", addInput).PaddingLeft = UDim.new(0, 8)
	local addInputStroke = Instance.new("UIStroke", addInput)
	addInputStroke.Color = Color3.fromRGB(255, 255, 255); addInputStroke.Thickness = 1; addInputStroke.Transparency = 0.96

	local addBtn = Instance.new("TextButton", addRow)
	addBtn.Size = UDim2.new(0, 52, 1, 0)
	addBtn.Position = UDim2.new(1, -52, 0, 0)
	addBtn.BackgroundColor3 = C_ACCENT
	addBtn.Text = "Add"
	addBtn.TextColor3 = C_TEXT
	addBtn.TextSize = 12
	addBtn.Font = Enum.Font.BuilderSans
	addBtn.AutoButtonColor = false
	addBtn.BorderSizePixel = 0
	addBtn.ZIndex = 52
	Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 6)

	local function getPriorityList()
		if type(_G.SHARED_PRIORITY_ITEMS) ~= "table" then _G.SHARED_PRIORITY_ITEMS = {} end
		return _G.SHARED_PRIORITY_ITEMS
	end

	-- ----- Drag-to-reorder for the priority list -----
	local ROW_H, ROW_GAP = 30, 3
	local ROW_STEP = ROW_H + ROW_GAP
	local _dragState = nil -- { idx = <index in list>, row = <Frame>, grabOffsetY = <number> }
	local GuiService = game:GetService("GuiService")
	local function getMouseYInGuiSpace()
		return _UIS:GetMouseLocation().Y - GuiService:GetGuiInset().Y
	end

	-- Thin highlight bar showing where the dragged row will land.
	local dropIndicator = Instance.new("Frame", priorityPopup)
	dropIndicator.Name = "PriorityDropIndicator"
	dropIndicator.BackgroundColor3 = Color3.fromRGB(120, 180, 255)
	dropIndicator.BorderSizePixel = 0
	dropIndicator.ZIndex = 59
	dropIndicator.Visible = false
	Instance.new("UICorner", dropIndicator).CornerRadius = UDim.new(1, 0)

	local rebuildPriorityList
	rebuildPriorityList = function()
		_dragState = nil
		dropIndicator.Visible = false
		local leftover = priorityPopup:FindFirstChild("DraggingPriorityRow")
		if leftover then leftover:Destroy() end

		for _, child in ipairs(popScroll:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		local query = (searchInput.Text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
		local firstMatchRow = nil
		local list = getPriorityList()
		for idx, name in ipairs(list) do
			local displayName = name:gsub("(%a)([%w_']*)", function(a, b) return a:upper() .. b end)
			local isMatch = query ~= "" and name:find(query, 1, true)
			local row = Instance.new("Frame", popScroll)
			row.Size = UDim2.new(1, 0, 0, 30)
			row.BackgroundColor3 = isMatch and C_SELECTED or C_SURFACE
			row.BackgroundTransparency = 0.12
			if isMatch and not firstMatchRow then firstMatchRow = row end
			row.LayoutOrder = idx
			row.ZIndex = 52
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
			local _rowStroke = Instance.new("UIStroke", row)
			_rowStroke.Color = Color3.fromRGB(255, 255, 255); _rowStroke.Thickness = 1; _rowStroke.Transparency = 0.96

			local numLabel = Instance.new("TextLabel", row)
			numLabel.Size = UDim2.new(0, 26, 1, 0)
			numLabel.Position = UDim2.new(0, 6, 0, 0)
			numLabel.BackgroundTransparency = 1
			numLabel.Text = tostring(idx)
			numLabel.TextColor3 = C_TEXT_DIM
			numLabel.TextSize = 11
			numLabel.Font = Enum.Font.BuilderSans
			numLabel.ZIndex = 53

			local nameLabel = Instance.new("TextLabel", row)
			nameLabel.Size = UDim2.new(1, -58, 1, 0)
			nameLabel.Position = UDim2.new(0, 32, 0, 0)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = displayName
			nameLabel.TextColor3 = isMatch and C_GREEN or C_TEXT
			nameLabel.TextSize = 12
			nameLabel.Font = Enum.Font.BuilderSans
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.ZIndex = 53

			local dragBtn = Instance.new("TextButton", row)
			dragBtn.Size = UDim2.new(0, 20, 0, 20)
			dragBtn.Position = UDim2.new(1, -46, 0.5, -10)
			dragBtn.BackgroundTransparency = 1
			dragBtn.Text = "☰"
			dragBtn.TextColor3 = C_TEXT_DIM
			dragBtn.TextSize = 14
			dragBtn.Font = Enum.Font.BuilderSans
			dragBtn.AutoButtonColor = false
			dragBtn.ZIndex = 54
			dragBtn.Active = true
			dragBtn.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				if _dragState then return end
				local relX = popScroll.AbsolutePosition.X - priorityPopup.AbsolutePosition.X
				local relY = (row.AbsolutePosition.Y - priorityPopup.AbsolutePosition.Y)
				_dragState = {
					idx = idx,
					row = row,
					grabOffsetY = getMouseYInGuiSpace() - row.AbsolutePosition.Y,
				}
				row.Name = "DraggingPriorityRow"
				row.ZIndex = 60
				row.BackgroundColor3 = C_SELECTED
				row.BackgroundTransparency = 0
				row.Size = UDim2.new(0, popScroll.AbsoluteSize.X, 0, ROW_H)
				row.Position = UDim2.new(0, relX, 0, relY)
				row.Parent = priorityPopup
			end)

			local delBtn = Instance.new("TextButton", row)
			delBtn.Size = UDim2.new(0, 20, 0, 20)
			delBtn.Position = UDim2.new(1, -22, 0.5, -10)
			delBtn.BackgroundTransparency = 1
			delBtn.Text = "x"
			delBtn.TextColor3 = Color3.fromRGB(224, 122, 130)
			delBtn.TextSize = 12
			delBtn.Font = Enum.Font.BuilderSans
			delBtn.AutoButtonColor = false
			delBtn.ZIndex = 54
			delBtn.MouseButton1Click:Connect(function()
				table.remove(list, idx)
				if _G._stp_saveCurrent then _G._stp_saveCurrent() end
				rebuildPriorityList()
			end)
		end
		if firstMatchRow then
			task.defer(function()
				local yPos = firstMatchRow.AbsolutePosition.Y - popScroll.AbsolutePosition.Y + popScroll.CanvasPosition.Y
				popScroll.CanvasPosition = Vector2.new(0, math.max(0, yPos - 10))
			end)
		end
	end

	local function computeTargetIdx(row, listLen)
		local relY = (row.AbsolutePosition.Y - popScroll.AbsolutePosition.Y) + popScroll.CanvasPosition.Y
		return math.clamp(math.floor(relY / ROW_STEP + 0.5) + 1, 1, listLen)
	end

	-- Follow the mouse while a row is being dragged, and show a drop indicator
	-- bar at the slot it would land in if released right now.
	RunService.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
		if not _dragState then return end
		local row = _dragState.row
		if not row or not row.Parent then _dragState = nil; dropIndicator.Visible = false; return end
		local mouseY = getMouseYInGuiSpace()
		local minY = popScroll.AbsolutePosition.Y
		local maxY = popScroll.AbsolutePosition.Y + popScroll.AbsoluteSize.Y - row.AbsoluteSize.Y
		local newY = math.clamp(mouseY - _dragState.grabOffsetY, minY, math.max(minY, maxY))
		local relX = popScroll.AbsolutePosition.X - priorityPopup.AbsolutePosition.X
		local relY = newY - priorityPopup.AbsolutePosition.Y
		row.Position = UDim2.new(0, relX, 0, relY)

		local list = getPriorityList()
		local targetIdx = computeTargetIdx(row, #list)
		local indicatorScreenY = popScroll.AbsolutePosition.Y + (targetIdx - 1) * ROW_STEP - popScroll.CanvasPosition.Y
		if indicatorScreenY >= popScroll.AbsolutePosition.Y - 2
			and indicatorScreenY <= popScroll.AbsolutePosition.Y + popScroll.AbsoluteSize.Y + 2 then
			dropIndicator.Size = UDim2.new(0, popScroll.AbsoluteSize.X, 0, 3)
			dropIndicator.Position = UDim2.new(0, relX, 0, (indicatorScreenY - priorityPopup.AbsolutePosition.Y) - 1)
			dropIndicator.Visible = true
		else
			dropIndicator.Visible = false
		end
	end))

	-- Drop the dragged row: convert its Y position back into a list index and reorder.
	_UIS.InputEnded:Connect(function(input)
		if not _dragState then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local row, idx = _dragState.row, _dragState.idx
		_dragState = nil
		dropIndicator.Visible = false
		local list = getPriorityList()
		local targetIdx = computeTargetIdx(row, #list)
		row:Destroy()
		if targetIdx ~= idx and list[idx] then
			local name = table.remove(list, idx)
			table.insert(list, targetIdx, name)
			if _G._stp_saveCurrent then _G._stp_saveCurrent() end
		end
		rebuildPriorityList()
	end)

	addBtn.MouseButton1Click:Connect(function()
		local name = addInput.Text:match("^%s*(.-)%s*$"):lower()
		if name == "" then return end
		local list = getPriorityList()
		for _, existing in ipairs(list) do
			if existing == name then addInput.Text = ""; return end
		end
		table.insert(list, name)
		addInput.Text = ""
		if _G._stp_saveCurrent then _G._stp_saveCurrent() end
		rebuildPriorityList()
	end)

	searchInput:GetPropertyChangedSignal("Text"):Connect(function()
		rebuildPriorityList()
	end)

	local popupOpen = false
	customizeBtn.MouseButton1Click:Connect(function()
		popupOpen = not popupOpen
		if popupOpen then
			rebuildPriorityList()
			priorityPopup.Visible = true
			local px = mf.AbsolutePosition.X + mf.AbsoluteSize.X + 8
			local py = mf.AbsolutePosition.Y
			local cam = workspace.CurrentCamera
			if cam then
				local vp = cam.ViewportSize
				if px + 400 > vp.X - 10 then px = mf.AbsolutePosition.X - 408 end
				py = math.clamp(py, 10, vp.Y - 570)
			end
			priorityPopup.Position = UDim2.new(0, px, 0, py)
		else
			priorityPopup.Visible = false
		end
	end)

	-- Opened from the "Auto Teleport" module in the Features panel.
	_G._stp_openPriority = function()
		popupOpen = true
		rebuildPriorityList()
		priorityPopup.Visible = true
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		priorityPopup.Position = UDim2.new(0, math.floor(vp.X / 2 - 200), 0, math.floor(vp.Y / 2 - 280))
	end

	mf.Visible = false

	popClose.MouseButton1Click:Connect(function()
		popupOpen = false
		priorityPopup.Visible = false
	end)

	priorityPopup.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if searchInput:IsFocused() then searchInput:ReleaseFocus() end
			if addInput:IsFocused() then addInput:ReleaseFocus() end
		end
	end)

	local popDg, popDs, popSp = false, nil, nil
	popTitle.Active = true
	popTitle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			popDg = true
			popDs = input.Position
			popSp = UDim2.new(0, priorityPopup.AbsolutePosition.X, 0, priorityPopup.AbsolutePosition.Y)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then popDg = false end
			end)
		end
	end)
	_UIS.InputChanged:Connect(function(input)
		if popDg and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - popDs
			local newX = popSp.X.Offset + d.X
			local newY = popSp.Y.Offset + d.Y
			local viewportSize = workspace.CurrentCamera.ViewportSize
			newX = math.clamp(newX, 0, viewportSize.X - priorityPopup.AbsoluteSize.X)
			newY = math.clamp(newY, 0, viewportSize.Y - priorityPopup.AbsoluteSize.Y)
			priorityPopup.Position = UDim2.new(0, newX, 0, newY)
		end
	end)

	_UIS.InputBegan:Connect(function(input, processed)
		if processed then return end
		if _UIS:GetFocusedTextBox() then return end
		local name = _G._stp_tpKeyName
		if type(name) ~= "string" then name = "T" end
		if name == "" then return end
		if Enum.KeyCode[name] and input.KeyCode == Enum.KeyCode[name] then
			task.spawn(function() if _G.VanishStartSideTP then _G.VanishStartSideTP() end end)
		end
	end)

-- ============================================================
-- PHONE (mini-games: Flappy Bird, Snake, Dino Runner) -- integrated,
-- toggled from the Performance tab instead of its own floating button.
-- ============================================================
do
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local existingPhoneGui = PlayerGui:FindFirstChild("PhoneGui")
if existingPhoneGui then
    existingPhoneGui:Destroy()
end

local WINDOW_WIDTH, TITLEBAR_HEIGHT = 320, 36
local MENU_HEIGHT = 520
local PHONE_CONTENT_HEIGHT = 640 -- hauteur fixe de l'ecran du telephone (comme un vrai telephone, ne change jamais)

local connections = {}
local function track(conn)
    table.insert(connections, conn)
    return conn
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius or UDim.new(0, 12)
    c.Parent = parent
    return c
end

--============ Sons ============--
local SOUNDS = {
    click = "rbxassetid://138567614125924",
    flap = "rbxassetid://139887585493497",
    jump = "rbxassetid://140606674696399",
    eat = "rbxassetid://115878657073501",
    score = "rbxassetid://135483737426662",
    hit = "rbxassetid://133155550104188",
}

local soundTemplates = {}
for name, id in pairs(SOUNDS) do
    local s = Instance.new("Sound")
    s.Name = name
    s.SoundId = id
    s.Volume = 0.6
    s.Parent = SoundService
    soundTemplates[name] = s
end

if _G.SXEPhoneSoundEnabled == nil then
    _G.SXEPhoneSoundEnabled = true
end

local function playSound(name)
    if not _G.SXEPhoneSoundEnabled then
        return
    end
    local template = soundTemplates[name]
    if not template or template.SoundId == "" or template.SoundId == "rbxassetid://0" then
        return
    end
    local s = template:Clone()
    s.Parent = SoundService
    s:Play()
    s.Ended:Connect(function()
        s:Destroy()
    end)
end

local currentGameHeight = MENU_HEIGHT
local currentCamera = nil
local currentController = nil
local currentGameFrame = nil
local currentGameId = nil
local openGame, showMenu, resizeWindow

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PhoneGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Parent = PlayerGui

track(screenGui.Destroying:Connect(function()
    if currentController then
        currentController.Stop()
        currentController = nil
    end
    for _, conn in ipairs(connections) do
        if conn.Connected then
            conn:Disconnect()
        end
    end
    for _, s in pairs(soundTemplates) do
        s:Destroy()
    end
end))

local appWindow = Instance.new("Frame")
appWindow.Name = "AppWindow"
appWindow.AnchorPoint = Vector2.new(0.5, 0.5)
appWindow.Position = UDim2.new(0.5, 0, 0.5, 0)
appWindow.Size = UDim2.new(0, WINDOW_WIDTH, 0, TITLEBAR_HEIGHT + PHONE_CONTENT_HEIGHT)
appWindow.BackgroundColor3 = Color3.fromRGB(9, 9, 11)
appWindow.BorderSizePixel = 0
appWindow.ClipsDescendants = true
appWindow.Visible = false
appWindow.Active = true
appWindow.Parent = screenGui
corner(appWindow, UDim.new(0, 38))
local bodyStroke = Instance.new("UIStroke")
bodyStroke.Color = Color3.fromRGB(55, 55, 62)
bodyStroke.Thickness = 2
bodyStroke.Parent = appWindow
_G.SXEPhoneFrame = appWindow

local sideButtonL1 = Instance.new("Frame")
sideButtonL1.Size = UDim2.new(0, 3, 0, 30)
sideButtonL1.Position = UDim2.new(0, -3, 0, 70)
sideButtonL1.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
sideButtonL1.BorderSizePixel = 0
sideButtonL1.Parent = appWindow
local sideButtonL2 = sideButtonL1:Clone()
sideButtonL2.Position = UDim2.new(0, -3, 0, 108)
sideButtonL2.Parent = appWindow
local sideButtonR = Instance.new("Frame")
sideButtonR.Size = UDim2.new(0, 3, 0, 46)
sideButtonR.Position = UDim2.new(1, 0, 0, 90)
sideButtonR.BackgroundColor3 = Color3.fromRGB(30, 30, 34)
sideButtonR.BorderSizePixel = 0
sideButtonR.Parent = appWindow

local uiScale = Instance.new("UIScale")
uiScale.Parent = appWindow

local function updateScale(camera)
    if not camera then return end
    local viewport = camera.ViewportSize
    local windowHeight = TITLEBAR_HEIGHT + PHONE_CONTENT_HEIGHT
    uiScale.Scale = math.clamp(math.min((viewport.Y * 0.92) / windowHeight, (viewport.X * 0.92) / WINDOW_WIDTH), 0.5, 1.6)
end

local viewportConn
local function bindCamera(camera)
    if viewportConn then
        viewportConn:Disconnect()
        viewportConn = nil
    end
    currentCamera = camera
    if camera then
        updateScale(camera)
        viewportConn = track(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            updateScale(camera)
        end))
    end
end

bindCamera(workspace.CurrentCamera)
track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    bindCamera(workspace.CurrentCamera)
end))

resizeWindow = function(height)
    -- Le telephone garde toujours la meme taille (comme un vrai telephone) ;
    -- chaque appli occupe juste la portion d'ecran dont elle a besoin en haut.
end

--============ Barre de statut (style telephone) ============--

local statusBar = Instance.new("Frame")
statusBar.Name = "StatusBar"
statusBar.Size = UDim2.new(1, 0, 0, TITLEBAR_HEIGHT)
statusBar.BackgroundTransparency = 1
statusBar.Active = true
statusBar.ZIndex = 4
statusBar.Parent = appWindow

local function safeClockText()
    local ok, result = pcall(function() return os.date("%H:%M") end)
    if ok then return result end
    return "--:--"
end

local clockLabel = Instance.new("TextLabel")
clockLabel.BackgroundTransparency = 1
clockLabel.Position = UDim2.new(0, 16, 0, 0)
clockLabel.Size = UDim2.new(0, 70, 1, 0)
clockLabel.Font = Enum.Font.GothamBold
clockLabel.TextSize = 13
clockLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
clockLabel.TextXAlignment = Enum.TextXAlignment.Left
clockLabel.Text = safeClockText()
clockLabel.Parent = statusBar

local StatsService = game:GetService("Stats")

local signalHolder = Instance.new("Frame")
signalHolder.Size = UDim2.new(0, 22, 0, 11)
signalHolder.Position = UDim2.new(1, -166, 0.5, -5)
signalHolder.BackgroundTransparency = 1
signalHolder.Parent = statusBar

local signalBars = {}
for i = 1, 4 do
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 3, 0, 3 + i * 2)
    bar.AnchorPoint = Vector2.new(0, 1)
    bar.Position = UDim2.new(0, (i - 1) * 6, 1, 0)
    bar.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
    bar.BackgroundTransparency = 0.55
    bar.BorderSizePixel = 0
    bar.Parent = signalHolder
    corner(bar, UDim.new(0, 1))
    signalBars[i] = bar
end

local function updateSignal()
    local activeCount = 4
    local okPing, ping = pcall(function()
        return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if okPing and type(ping) == "number" then
        if ping > 250 then
            activeCount = 1
        elseif ping > 150 then
            activeCount = 2
        elseif ping > 80 then
            activeCount = 3
        else
            activeCount = 4
        end
    end
    for i, bar in ipairs(signalBars) do
        bar.BackgroundTransparency = (i <= activeCount) and 0.05 or 0.75
    end
end

local batteryPercentLabel = Instance.new("TextLabel")
batteryPercentLabel.BackgroundTransparency = 1
batteryPercentLabel.Position = UDim2.new(1, -136, 0, 0)
batteryPercentLabel.Size = UDim2.new(0, 30, 1, 0)
batteryPercentLabel.Font = Enum.Font.GothamBold
batteryPercentLabel.TextSize = 11
batteryPercentLabel.TextColor3 = Color3.fromRGB(220, 220, 228)
batteryPercentLabel.TextXAlignment = Enum.TextXAlignment.Right
batteryPercentLabel.Text = "100%"
batteryPercentLabel.Parent = statusBar

local BATTERY_W, BATTERY_H = 20, 10

local batteryHolder = Instance.new("Frame")
batteryHolder.Size = UDim2.new(0, BATTERY_W + 4, 0, BATTERY_H + 2)
batteryHolder.Position = UDim2.new(1, -100, 0.5, -(BATTERY_H + 2) / 2)
batteryHolder.BackgroundTransparency = 1
batteryHolder.Parent = statusBar

local batteryOutline = Instance.new("Frame")
batteryOutline.Size = UDim2.new(0, BATTERY_W, 0, BATTERY_H)
batteryOutline.AnchorPoint = Vector2.new(0, 0.5)
batteryOutline.Position = UDim2.new(0, 0, 0.5, 0)
batteryOutline.BackgroundTransparency = 1
batteryOutline.Parent = batteryHolder
corner(batteryOutline, UDim.new(0, 3))
local batteryStroke = Instance.new("UIStroke", batteryOutline)
batteryStroke.Color = Color3.fromRGB(240, 240, 245)
batteryStroke.Thickness = 1.2
batteryStroke.Transparency = 0.1

local batteryNub = Instance.new("Frame")
batteryNub.Size = UDim2.new(0, 2, 0, 5)
batteryNub.AnchorPoint = Vector2.new(0, 0.5)
batteryNub.Position = UDim2.new(0, BATTERY_W + 1, 0.5, 0)
batteryNub.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
batteryNub.BackgroundTransparency = 0.1
batteryNub.BorderSizePixel = 0
batteryNub.Parent = batteryHolder

local batteryFill = Instance.new("Frame")
batteryFill.Position = UDim2.new(0, 2, 0, 2)
batteryFill.Size = UDim2.new(0, BATTERY_W - 4, 0, BATTERY_H - 4)
batteryFill.BackgroundColor3 = Color3.fromRGB(90, 210, 120)
batteryFill.BorderSizePixel = 0
batteryFill.Parent = batteryOutline
corner(batteryFill, UDim.new(0, 1))

_G.SXEPhoneBatteryLevel = _G.SXEPhoneBatteryLevel or 100

local function updateBattery()
    local level = math.clamp(_G.SXEPhoneBatteryLevel or 100, 0, 100)
    local ratio = level / 100
    batteryFill.Size = UDim2.new(0, math.max(1, (BATTERY_W - 4) * ratio), 0, BATTERY_H - 4)
    if level <= 20 then
        batteryFill.BackgroundColor3 = Color3.fromRGB(230, 90, 90)
    elseif level <= 40 then
        batteryFill.BackgroundColor3 = Color3.fromRGB(235, 190, 60)
    else
        batteryFill.BackgroundColor3 = Color3.fromRGB(90, 210, 120)
    end
    batteryPercentLabel.Text = tostring(math.floor(level)) .. "%"
end
updateBattery()

task.spawn(function()
    while screenGui.Parent do
        clockLabel.Text = safeClockText()
        updateSignal()
        task.wait(15)
    end
end)

task.spawn(function()
    while screenGui.Parent do
        task.wait(50)
        _G.SXEPhoneBatteryLevel = (_G.SXEPhoneBatteryLevel or 100) - 1
        if _G.SXEPhoneBatteryLevel <= 0 then
            _G.SXEPhoneBatteryLevel = 100
        end
        updateBattery()
    end
end)

local notch = Instance.new("Frame")
notch.Size = UDim2.new(0, 90, 0, 20)
notch.Position = UDim2.new(0.5, -45, 0, -2)
notch.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
notch.ZIndex = 6
notch.Parent = appWindow
corner(notch, UDim.new(1, 0))

local function titlebarButton(text, xOffset)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 24, 0, 24)
    btn.Position = UDim2.new(1, xOffset, 0.5, -12)
    btn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    btn.AutoButtonColor = true
    btn.Text = text
    btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold
    btn.TextColor3 = Color3.fromRGB(230, 230, 230)
    btn.ZIndex = 5
    btn.Parent = statusBar
    corner(btn, UDim.new(1, 0))
    return btn
end

local PAUSE_ICON, PLAY_ICON = "| |", "\226\150\182"

local closeBtn = titlebarButton("\226\156\149", -28)
closeBtn.TextColor3 = Color3.fromRGB(240, 90, 90)
local pauseBtn = titlebarButton(PAUSE_ICON, -58)
pauseBtn.Visible = false

track(closeBtn.MouseButton1Click:Connect(function()
    playSound("click")
    appWindow.Visible = false
end))
track(pauseBtn.MouseButton1Click:Connect(function()
    playSound("click")
    if currentController then
        currentController.TogglePause()
    end
end))

local homeIndicatorBacking = Instance.new("Frame")
homeIndicatorBacking.Name = "HomeIndicatorBacking"
homeIndicatorBacking.AnchorPoint = Vector2.new(0.5, 1)
homeIndicatorBacking.Position = UDim2.new(0.5, 0, 1, 0)
homeIndicatorBacking.Size = UDim2.new(0, 160, 0, 26)
homeIndicatorBacking.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
homeIndicatorBacking.BackgroundTransparency = 0.45
homeIndicatorBacking.Visible = false
homeIndicatorBacking.ZIndex = 9
homeIndicatorBacking.Parent = appWindow
corner(homeIndicatorBacking, UDim.new(1, 0))

local homeIndicator = Instance.new("TextButton")
homeIndicator.Name = "HomeIndicator"
homeIndicator.AnchorPoint = Vector2.new(0.5, 1)
homeIndicator.Position = UDim2.new(0.5, 0, 1, -6)
homeIndicator.Size = UDim2.new(0, 120, 0, 5)
homeIndicator.BackgroundColor3 = Color3.fromRGB(240, 240, 245)
homeIndicator.BackgroundTransparency = 0
homeIndicator.Text = ""
homeIndicator.AutoButtonColor = false
homeIndicator.Visible = false
homeIndicator.ZIndex = 10
homeIndicator.Parent = appWindow
corner(homeIndicator, UDim.new(1, 0))
local homeIndicatorStroke = Instance.new("UIStroke", homeIndicator)
homeIndicatorStroke.Color = Color3.fromRGB(20, 20, 24)
homeIndicatorStroke.Thickness = 1
homeIndicatorStroke.Transparency = 0.3

track(homeIndicator.MouseButton1Click:Connect(function()
    playSound("click")
    showMenu()
end))

-- glisser la fenêtre par la barre de statut
do
    local dragging, dragStart, startPos = false, nil, nil
    track(statusBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = appWindow.Position
        end
    end))
    track(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    track(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            appWindow.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end

--============ Zone de contenu (menu ou jeu actif) ============--

local contentArea = Instance.new("Frame")
contentArea.Name = "ContentArea"
contentArea.Position = UDim2.new(0, 0, 0, TITLEBAR_HEIGHT)
contentArea.Size = UDim2.new(1, 0, 1, -TITLEBAR_HEIGHT)
contentArea.BackgroundTransparency = 1
contentArea.ClipsDescendants = true
contentArea.BorderSizePixel = 0
contentArea.Parent = appWindow

local buildOk, buildErr = pcall(function()

--============ Helpers partagés par les jeux (overlays / cartes) ============--

local function createOverlay(parent, bgTransparency)
    local overlay = Instance.new("Frame")
    overlay.Size = UDim2.new(1, 0, 1, 0)
    overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    overlay.BackgroundTransparency = bgTransparency or 0.35
    overlay.BorderSizePixel = 0
    overlay.ZIndex = 30
    overlay.Parent = parent

    local card = Instance.new("Frame")
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.new(0.5, 0, 0.5, 0)
    card.Size = UDim2.new(0, 260, 0, 220)
    card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    card.BorderSizePixel = 0
    card.ZIndex = 31
    card.Parent = overlay
    corner(card, UDim.new(0, 16))

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.Padding = UDim.new(0, 10)
    layout.Parent = card

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 20)
    padding.PaddingBottom = UDim.new(0, 20)
    padding.Parent = card

    return overlay, card
end

local function addTitle(card, text, order)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, -20, 0, 36)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 26
    label.TextColor3 = Color3.fromRGB(30, 30, 30)
    label.Text = text
    label.LayoutOrder = order
    label.ZIndex = 32
    label.Parent = card
    return label
end

local function addButton(card, text, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 160, 0, 44)
    btn.BackgroundColor3 = Color3.fromRGB(94, 201, 98)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 18
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Text = text
    btn.LayoutOrder = order
    btn.ZIndex = 32
    btn.Parent = card
    corner(btn, UDim.new(0, 12))
    return btn
end

local function scoreStat(row, caption)
    local holder = Instance.new("Frame")
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.new(0, 90, 1, 0)
    holder.ZIndex = 32
    holder.Parent = row
    local capLabel = Instance.new("TextLabel")
    capLabel.BackgroundTransparency = 1
    capLabel.Size = UDim2.new(1, 0, 0, 16)
    capLabel.Font = Enum.Font.Gotham
    capLabel.TextSize = 12
    capLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
    capLabel.Text = caption
    capLabel.ZIndex = 32
    capLabel.Parent = holder
    local valLabel = Instance.new("TextLabel")
    valLabel.BackgroundTransparency = 1
    valLabel.Position = UDim2.new(0, 0, 0, 16)
    valLabel.Size = UDim2.new(1, 0, 0, 30)
    valLabel.Font = Enum.Font.GothamBold
    valLabel.TextSize = 24
    valLabel.TextColor3 = Color3.fromRGB(30, 30, 30)
    valLabel.Text = "0"
    valLabel.ZIndex = 32
    valLabel.Parent = holder
    return valLabel
end

--============ Ecran d'accueil (grille d'apps) ============--

local homeBackdrop = Instance.new("Frame")
homeBackdrop.Name = "HomeBackdrop"
homeBackdrop.Size = UDim2.new(1, 0, 1, 0)
homeBackdrop.BackgroundColor3 = Color3.fromRGB(24, 22, 34)
homeBackdrop.BorderSizePixel = 0
homeBackdrop.Parent = contentArea
corner(homeBackdrop, UDim.new(0, 38))

local wallpaperImage = Instance.new("ImageLabel")
wallpaperImage.Name = "WallpaperImage"
wallpaperImage.Size = UDim2.new(1, 0, 1, 0)
wallpaperImage.BackgroundTransparency = 1
wallpaperImage.Image = "rbxassetid://93377284283454"
wallpaperImage.ScaleType = Enum.ScaleType.Crop
wallpaperImage.ZIndex = 0
wallpaperImage.Parent = homeBackdrop

local wallpaperDarken = Instance.new("Frame")
wallpaperDarken.Name = "WallpaperDarken"
wallpaperDarken.Size = UDim2.new(1, 0, 1, 0)
wallpaperDarken.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
wallpaperDarken.BackgroundTransparency = 0.45
wallpaperDarken.BorderSizePixel = 0
wallpaperDarken.ZIndex = 0
wallpaperDarken.Parent = homeBackdrop

local wallpaperGradient = Instance.new("UIGradient")
wallpaperGradient.Rotation = 60
wallpaperGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(42, 32, 74)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 28)),
})
wallpaperGradient.Parent = homeBackdrop

local menuFrame = Instance.new("ScrollingFrame")
menuFrame.Name = "HomeScreen"
menuFrame.Size = UDim2.new(1, 0, 1, 0)
menuFrame.BackgroundTransparency = 1
menuFrame.BorderSizePixel = 0
menuFrame.ScrollingDirection = Enum.ScrollingDirection.Y
menuFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
menuFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
menuFrame.ScrollBarThickness = 4
menuFrame.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 100)
menuFrame.Parent = contentArea
corner(menuFrame, UDim.new(0, 38))

local function setCustomWallpaper(source)
    if not source or source == "" then
        wallpaperImage.Image = ""
        return
    end
    local value = source:match("^%s*(.-)%s*$")
    if value:match("^%d+$") then
        wallpaperImage.Image = "rbxassetid://" .. value
    elseif value:match("^rbxassetid://") or value:match("^rbxthumb://") or value:match("^https?://") then
        wallpaperImage.Image = value
    else
        wallpaperImage.Image = ""
    end
end

local menuList = Instance.new("UIGridLayout")
menuList.CellSize = UDim2.new(0, 84, 0, 104)
menuList.CellPadding = UDim2.new(0, 12, 0, 10)
menuList.SortOrder = Enum.SortOrder.LayoutOrder
menuList.HorizontalAlignment = Enum.HorizontalAlignment.Center
menuList.Parent = menuFrame

local menuPadding = Instance.new("UIPadding")
menuPadding.PaddingTop = UDim.new(0, 22)
menuPadding.PaddingBottom = UDim.new(0, 24)
menuPadding.PaddingLeft = UDim.new(0, 14)
menuPadding.PaddingRight = UDim.new(0, 14)
menuPadding.Parent = menuFrame

local function createAppIcon(icon, title, order, accent)
    local wrapper = Instance.new("Frame")
    wrapper.BackgroundTransparency = 1
    wrapper.LayoutOrder = order
    wrapper.Parent = menuFrame

    local iconBtn = Instance.new("TextButton")
    iconBtn.Size = UDim2.new(0, 64, 0, 64)
    iconBtn.Position = UDim2.new(0.5, -32, 0, 0)
    iconBtn.BackgroundColor3 = accent
    iconBtn.AutoButtonColor = true
    iconBtn.Text = icon
    iconBtn.TextSize = 30
    iconBtn.Font = Enum.Font.GothamBold
    iconBtn.Parent = wrapper
    corner(iconBtn, UDim.new(0, 18))
    local iconStroke = Instance.new("UIStroke", iconBtn)
    iconStroke.Color = Color3.fromRGB(255, 255, 255)
    iconStroke.Transparency = 0.85
    iconStroke.Thickness = 1

    local badge = Instance.new("TextLabel")
    badge.Size = UDim2.new(0, 22, 0, 22)
    badge.Position = UDim2.new(1, -14, 0, -6)
    badge.BackgroundColor3 = Color3.fromRGB(235, 70, 70)
    badge.Text = "0"
    badge.TextColor3 = Color3.fromRGB(255, 255, 255)
    badge.Font = Enum.Font.GothamBold
    badge.TextSize = 11
    badge.Visible = false
    badge.ZIndex = 2
    badge.Parent = iconBtn
    corner(badge, UDim.new(1, 0))
    local badgeStroke = Instance.new("UIStroke", badge)
    badgeStroke.Color = Color3.fromRGB(24, 22, 34)
    badgeStroke.Thickness = 2

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, -10, 0, 68)
    label.Size = UDim2.new(1, 20, 0, 32)
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(235, 235, 240)
    label.TextWrapped = true
    label.Text = title
    label.Parent = wrapper

    return iconBtn, badge
end

local flappyCard, flappyBest = createAppIcon("\240\159\144\166", "Flappy Bird", 1, Color3.fromRGB(80, 170, 235))
local snakeCard, snakeBest = createAppIcon("\240\159\144\141", "Snake", 2, Color3.fromRGB(70, 190, 110))
local dinoCard, dinoBest = createAppIcon("\240\159\166\150", "Dino Runner", 3, Color3.fromRGB(210, 150, 60))
local pongCard, pongBest = createAppIcon("\240\159\143\147", "Pong", 4, Color3.fromRGB(90, 90, 100))
local tennisCard, tennisBest = createAppIcon("\240\159\142\190", "Tennis", 5, Color3.fromRGB(190, 210, 60))
local calcCard = createAppIcon("\240\159\148\162", "Calculatrice", 6, Color3.fromRGB(60, 60, 68))
local notesCard = createAppIcon("\240\159\147\157", "Notes", 7, Color3.fromRGB(240, 210, 90))
local musicCard = createAppIcon("\240\159\142\181", "Musique", 8, Color3.fromRGB(30, 215, 96))
local settingsCard = createAppIcon("\226\154\153", "Reglages", 9, Color3.fromRGB(90, 90, 100))
local chronoCard = createAppIcon("\226\143\177", "Chrono", 10, Color3.fromRGB(60, 180, 200))
local playersCard = createAppIcon("\240\159\145\165", "Joueurs", 11, Color3.fromRGB(80, 150, 230))

local bestScores = { FlappyBird = 0, Snake = 0, DinoRunner = 0, Pong = 0, Tennis = 0 }
local bestLabels = { FlappyBird = flappyBest, Snake = snakeBest, DinoRunner = dinoBest, Pong = pongBest, Tennis = tennisBest }

local function reportBest(id, score)
    if score > bestScores[id] then
        bestScores[id] = score
        bestLabels[id].Text = tostring(score)
        bestLabels[id].Visible = true
    end
end

--============ Jeu 1 : Flappy Bird ============--

local function BuildFlappyBird(gameArea, deps)
    local GAME_HEIGHT, GROUND_HEIGHT = 640, 90
    local PLAYABLE_HEIGHT = GAME_HEIGHT - GROUND_HEIGHT

    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(78, 192, 220)

    local function createCloud(x, y, scale)
        local container = Instance.new("Frame")
        container.BackgroundTransparency = 1
        container.Size = UDim2.new(0, 90 * scale, 0, 40 * scale)
        container.Position = UDim2.new(0, x, 0, y)
        container.ZIndex = 1
        container.Parent = gameArea

        local puffs = { { 0, 10, 45, 30 }, { 25, 0, 45, 40 }, { 45, 12, 40, 28 } }
        for _, p in ipairs(puffs) do
            local puff = Instance.new("Frame")
            puff.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            puff.BackgroundTransparency = 0.15
            puff.BorderSizePixel = 0
            puff.ZIndex = 1
            puff.Size = UDim2.new(0, p[3] * scale, 0, p[4] * scale)
            puff.Position = UDim2.new(0, p[1] * scale, 0, p[2] * scale)
            puff.Parent = container
            corner(puff, UDim.new(1, 0))
        end
        return container
    end

    local clouds = {
        { frame = createCloud(20, 50, 1), x = 20, y = 50, speed = 8 },
        { frame = createCloud(220, 90, 0.8), x = 220, y = 90, speed = 6 },
        { frame = createCloud(120, 160, 0.6), x = 120, y = 160, speed = 10 },
    }

    local ground = Instance.new("Frame")
    ground.Size = UDim2.new(1, 0, 0, GROUND_HEIGHT)
    ground.Position = UDim2.new(0, 0, 1, -GROUND_HEIGHT)
    ground.BackgroundColor3 = Color3.fromRGB(222, 184, 111)
    ground.BorderSizePixel = 0
    ground.ZIndex = 5
    ground.Parent = gameArea

    local grassStrip = Instance.new("Frame")
    grassStrip.Size = UDim2.new(1, 0, 0, 10)
    grassStrip.BackgroundColor3 = Color3.fromRGB(94, 201, 98)
    grassStrip.BorderSizePixel = 0
    grassStrip.ZIndex = 5
    grassStrip.Parent = ground

    for i = 1, 8 do
        local dash = Instance.new("Frame")
        dash.Size = UDim2.new(0, 20, 0, 4)
        dash.Position = UDim2.new(0, (i - 1) * 46, 0, 30 + (i % 2) * 20)
        dash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        dash.BackgroundTransparency = 0.5
        dash.BorderSizePixel = 0
        dash.ZIndex = 6
        dash.Parent = ground
    end

    local BIRD_X, BIRD_RADIUS = 90, 17
    local bird = Instance.new("Frame")
    bird.Size = UDim2.new(0, BIRD_RADIUS * 2, 0, BIRD_RADIUS * 2)
    bird.AnchorPoint = Vector2.new(0.5, 0.5)
    bird.BackgroundColor3 = Color3.fromRGB(247, 202, 24)
    bird.BorderSizePixel = 0
    bird.ZIndex = 10
    bird.Parent = gameArea
    corner(bird, UDim.new(1, 0))

    local eyeWhite = Instance.new("Frame")
    eyeWhite.Size = UDim2.new(0, 10, 0, 10)
    eyeWhite.Position = UDim2.new(1, -16, 0, 4)
    eyeWhite.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    eyeWhite.BorderSizePixel = 0
    eyeWhite.ZIndex = 11
    eyeWhite.Parent = bird
    corner(eyeWhite, UDim.new(1, 0))

    local pupil = Instance.new("Frame")
    pupil.Size = UDim2.new(0, 5, 0, 5)
    pupil.Position = UDim2.new(0, 3, 0, 3)
    pupil.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    pupil.BorderSizePixel = 0
    pupil.ZIndex = 12
    pupil.Parent = eyeWhite
    corner(pupil, UDim.new(1, 0))

    local beak = Instance.new("Frame")
    beak.Size = UDim2.new(0, 14, 0, 8)
    beak.Position = UDim2.new(1, -6, 0.5, -4)
    beak.BackgroundColor3 = Color3.fromRGB(235, 140, 52)
    beak.BorderSizePixel = 0
    beak.ZIndex = 11
    beak.Parent = bird
    corner(beak, UDim.new(0, 3))

    local wing = Instance.new("Frame")
    wing.Size = UDim2.new(0, 16, 0, 12)
    wing.Position = UDim2.new(0, 4, 0.5, -2)
    wing.BackgroundColor3 = Color3.fromRGB(230, 170, 20)
    wing.BorderSizePixel = 0
    wing.ZIndex = 11
    wing.Parent = bird
    corner(wing, UDim.new(1, 0))

    local scoreLabel = Instance.new("TextLabel")
    scoreLabel.BackgroundTransparency = 1
    scoreLabel.Position = UDim2.new(0.5, -60, 0, 16)
    scoreLabel.Size = UDim2.new(0, 120, 0, 50)
    scoreLabel.Font = Enum.Font.GothamBold
    scoreLabel.TextSize = 40
    scoreLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    scoreLabel.TextStrokeTransparency = 0
    scoreLabel.TextStrokeColor3 = Color3.fromRGB(40, 40, 40)
    scoreLabel.Text = "0"
    scoreLabel.ZIndex = 20
    scoreLabel.Parent = gameArea

    local bestBadge = Instance.new("TextLabel")
    bestBadge.BackgroundTransparency = 1
    bestBadge.Position = UDim2.new(0.5, -80, 0, 66)
    bestBadge.Size = UDim2.new(0, 160, 0, 20)
    bestBadge.Font = Enum.Font.GothamBold
    bestBadge.TextSize = 14
    bestBadge.TextColor3 = Color3.fromRGB(255, 215, 0)
    bestBadge.TextStrokeTransparency = 0.4
    bestBadge.Text = "Meilleur : " .. tostring(deps.bestScore)
    bestBadge.ZIndex = 20
    bestBadge.Parent = gameArea

    local startScreen, startCard = createOverlay(gameArea, 0.15)
    addTitle(startCard, "FLAPPY BIRD", 1)
    local startSubtitle = Instance.new("TextLabel")
    startSubtitle.BackgroundTransparency = 1
    startSubtitle.Size = UDim2.new(1, -30, 0, 50)
    startSubtitle.Font = Enum.Font.Gotham
    startSubtitle.TextSize = 14
    startSubtitle.TextWrapped = true
    startSubtitle.TextColor3 = Color3.fromRGB(90, 90, 90)
    startSubtitle.Text = "Touche l'écran, clique ou appuie sur Espace\npour faire voler l'oiseau"
    startSubtitle.LayoutOrder = 2
    startSubtitle.ZIndex = 32
    startSubtitle.Parent = startCard
    local startBtn = addButton(startCard, "Jouer", 3)

    local gameOverScreen, gameOverCard = createOverlay(gameArea, 0.15)
    gameOverScreen.Visible = false
    addTitle(gameOverCard, "Perdu !", 1)
    local scoreRow = Instance.new("Frame")
    scoreRow.BackgroundTransparency = 1
    scoreRow.Size = UDim2.new(1, -20, 0, 50)
    scoreRow.LayoutOrder = 2
    scoreRow.ZIndex = 32
    scoreRow.Parent = gameOverCard
    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    rowLayout.Padding = UDim.new(0, 30)
    rowLayout.Parent = scoreRow

    local finalScoreLabel = scoreStat(scoreRow, "Score")
    local bestScoreLabel = scoreStat(scoreRow, "Meilleur")
    local restartBtn = addButton(gameOverCard, "Rejouer", 3)

    local pauseScreen, pauseCard = createOverlay(gameArea, 0.35)
    pauseScreen.Visible = false
    addTitle(pauseCard, "Pause", 1)
    local resumeBtn = addButton(pauseCard, "Reprendre", 2)

    local GRAVITY = 900
    local FLAP_IMPULSE = -300
    local PIPE_WIDTH = 60
    local PIPE_GAP = 160
    local PIPE_SPEED = 140
    local PIPE_SPACING = 220

    local gameState = "start" -- start | playing | paused | gameover
    local birdY, birdVel = PLAYABLE_HEIGHT / 2, 0
    local score, bestScore = 0, deps.bestScore
    local pipes = {}
    local idleTween

    local function clearPipes()
        for _, p in ipairs(pipes) do
            p.top:Destroy()
            p.bottom:Destroy()
        end
        pipes = {}
    end

    local function configurePipe(p, x)
        local gapCenter = math.random(120, PLAYABLE_HEIGHT - 120)
        local topHeight = gapCenter - PIPE_GAP / 2
        local bottomY = gapCenter + PIPE_GAP / 2
        local bottomHeight = PLAYABLE_HEIGHT - bottomY

        p.x = x
        p.topHeight = topHeight
        p.bottomY = bottomY
        p.passed = false

        p.top.Size = UDim2.new(0, PIPE_WIDTH, 0, topHeight)
        p.top.Position = UDim2.new(0, x, 0, 0)
        p.bottom.Size = UDim2.new(0, PIPE_WIDTH, 0, bottomHeight)
        p.bottom.Position = UDim2.new(0, x, 0, bottomY)
    end

    local function createPipeFrames()
        local top = Instance.new("Frame")
        top.BackgroundColor3 = Color3.fromRGB(94, 201, 98)
        top.BorderSizePixel = 0
        top.ZIndex = 4
        top.Parent = gameArea
        local topCap = Instance.new("Frame")
        topCap.AnchorPoint = Vector2.new(0.5, 0)
        topCap.Position = UDim2.new(0.5, 0, 1, 0)
        topCap.Size = UDim2.new(1, 10, 0, 20)
        topCap.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
        topCap.BorderSizePixel = 0
        topCap.ZIndex = 5
        topCap.Parent = top
        corner(topCap, UDim.new(0, 4))

        local bottom = Instance.new("Frame")
        bottom.BackgroundColor3 = Color3.fromRGB(94, 201, 98)
        bottom.BorderSizePixel = 0
        bottom.ZIndex = 4
        bottom.Parent = gameArea
        local bottomCap = Instance.new("Frame")
        bottomCap.AnchorPoint = Vector2.new(0.5, 1)
        bottomCap.Position = UDim2.new(0.5, 0, 0, 0)
        bottomCap.Size = UDim2.new(1, 10, 0, 20)
        bottomCap.BackgroundColor3 = Color3.fromRGB(76, 175, 80)
        bottomCap.BorderSizePixel = 0
        bottomCap.ZIndex = 5
        bottomCap.Parent = bottom
        corner(bottomCap, UDim.new(0, 4))

        return top, bottom
    end

    local function spawnInitialPipes()
        for i = 1, 3 do
            local top, bottom = createPipeFrames()
            local p = { top = top, bottom = bottom }
            configurePipe(p, WINDOW_WIDTH + 100 + (i - 1) * PIPE_SPACING)
            table.insert(pipes, p)
        end
    end

    local function resetGame()
        clearPipes()
        birdY = PLAYABLE_HEIGHT / 2
        birdVel = 0
        score = 0
        scoreLabel.Text = "0"
        bird.Position = UDim2.new(0, BIRD_X, 0, birdY)
        bird.Rotation = 0
        spawnInitialPipes()
    end

    local function startGame()
        if idleTween then idleTween:Cancel() end
        startScreen.Visible = false
        gameOverScreen.Visible = false
        pauseScreen.Visible = false
        resetGame()
        gameState = "playing"
    end

    local function endGame()
        if gameState ~= "playing" then return end
        gameState = "gameover"
        playSound("hit")
        if score > bestScore then
            bestScore = score
            bestBadge.Text = "Meilleur : " .. tostring(bestScore)
            deps.reportBest(bestScore)
        end
        finalScoreLabel.Text = tostring(score)
        bestScoreLabel.Text = tostring(bestScore)
        gameOverScreen.Visible = true
    end

    local function setPaused(paused)
        if paused and gameState == "playing" then
            gameState = "paused"
            pauseScreen.Visible = true
            deps.onPauseChanged(true)
        elseif not paused and gameState == "paused" then
            gameState = "playing"
            pauseScreen.Visible = false
            deps.onPauseChanged(false)
        end
    end

    local function togglePause()
        setPaused(gameState ~= "paused")
    end

    local function flap()
        if gameState == "playing" then
            birdVel = FLAP_IMPULSE
            playSound("flap")
        end
    end

    bird.Position = UDim2.new(0, BIRD_X, 0, birdY)
    idleTween = TweenService:Create(bird, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.new(0, BIRD_X, 0, birdY - 20) })
    idleTween:Play()

    ltrack(startBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(restartBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(resumeBtn.MouseButton1Click:Connect(function()
        playSound("click")
        togglePause()
    end))

    ltrack(UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        local isPrimary = input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
            or input.KeyCode == Enum.KeyCode.Space
        if isPrimary then
            if gameState == "gameover" then
                startGame()
            else
                flap()
            end
        elseif input.KeyCode == Enum.KeyCode.Escape then
            togglePause()
        end
    end))

    ltrack(RunService.Heartbeat:Connect(function(dt)
        for _, cloud in ipairs(clouds) do
            cloud.x -= cloud.speed * dt
            if cloud.x < -120 then
                cloud.x = WINDOW_WIDTH + math.random(0, 100)
            end
            cloud.frame.Position = UDim2.new(0, cloud.x, 0, cloud.y)
        end

        if gameState ~= "playing" then return end

        birdVel += GRAVITY * dt
        birdY += birdVel * dt
        if birdY - BIRD_RADIUS < 0 then
            birdY = BIRD_RADIUS
            birdVel = 0
        end
        bird.Position = UDim2.new(0, BIRD_X, 0, birdY)
        bird.Rotation = math.clamp(birdVel / 12, -25, 70)

        local rightmostX = 0
        for _, p in ipairs(pipes) do
            p.x -= PIPE_SPEED * dt
            p.top.Position = UDim2.new(0, p.x, 0, 0)
            p.bottom.Position = UDim2.new(0, p.x, 0, p.bottomY)
            rightmostX = math.max(rightmostX, p.x)

            if not p.passed and p.x + PIPE_WIDTH < BIRD_X then
                p.passed = true
                score += 1
                scoreLabel.Text = tostring(score)
                playSound("score")
            end

            if BIRD_X + BIRD_RADIUS > p.x and BIRD_X - BIRD_RADIUS < p.x + PIPE_WIDTH then
                if birdY - BIRD_RADIUS < p.topHeight or birdY + BIRD_RADIUS > p.bottomY then
                    endGame()
                    return
                end
            end
        end

        for _, p in ipairs(pipes) do
            if p.x + PIPE_WIDTH < -20 then
                configurePipe(p, rightmostX + PIPE_SPACING)
            end
        end

        if birdY + BIRD_RADIUS >= PLAYABLE_HEIGHT then
            endGame()
        end
    end))

    return {
        TogglePause = function() togglePause() end,
        Stop = function()
            if idleTween then idleTween:Cancel() end
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Jeu 2 : Snake ============--

local function BuildSnake(gameArea, deps)
    local GRID, CELL = 16, 18
    local BOARD_MARGIN = 16
    local BOARD_SIZE = GRID * CELL

    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(30, 34, 30)

    local board = Instance.new("Frame")
    board.Name = "Board"
    board.Position = UDim2.new(0, BOARD_MARGIN, 0, BOARD_MARGIN)
    board.Size = UDim2.new(0, BOARD_SIZE, 0, BOARD_SIZE)
    board.BackgroundColor3 = Color3.fromRGB(48, 54, 48)
    board.BorderSizePixel = 0
    board.ClipsDescendants = true
    board.ZIndex = 2
    board.Parent = gameArea
    corner(board, UDim.new(0, 10))

    local scoreLabel = Instance.new("TextLabel")
    scoreLabel.BackgroundTransparency = 1
    scoreLabel.Position = UDim2.new(0.5, -60, 0, -6)
    scoreLabel.Size = UDim2.new(0, 120, 0, 40)
    scoreLabel.Font = Enum.Font.GothamBold
    scoreLabel.TextSize = 28
    scoreLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    scoreLabel.TextStrokeTransparency = 0
    scoreLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
    scoreLabel.Text = "0"
    scoreLabel.ZIndex = 20
    scoreLabel.Parent = gameArea

    local bestBadge = Instance.new("TextLabel")
    bestBadge.BackgroundTransparency = 1
    bestBadge.Position = UDim2.new(0.5, -80, 0, 28)
    bestBadge.Size = UDim2.new(0, 160, 0, 18)
    bestBadge.Font = Enum.Font.GothamBold
    bestBadge.TextSize = 13
    bestBadge.TextColor3 = Color3.fromRGB(255, 215, 0)
    bestBadge.TextStrokeTransparency = 0.4
    bestBadge.Text = "Meilleur : " .. tostring(deps.bestScore)
    bestBadge.ZIndex = 20
    bestBadge.Parent = gameArea

    local startScreen, startCard = createOverlay(gameArea, 0.15)
    addTitle(startCard, "SNAKE", 1)
    local startSubtitle = Instance.new("TextLabel")
    startSubtitle.BackgroundTransparency = 1
    startSubtitle.Size = UDim2.new(1, -30, 0, 50)
    startSubtitle.Font = Enum.Font.Gotham
    startSubtitle.TextSize = 14
    startSubtitle.TextWrapped = true
    startSubtitle.TextColor3 = Color3.fromRGB(90, 90, 90)
    startSubtitle.Text = "Flèches / ZQSD ou glisse au doigt\npour diriger le serpent"
    startSubtitle.LayoutOrder = 2
    startSubtitle.ZIndex = 32
    startSubtitle.Parent = startCard
    local startBtn = addButton(startCard, "Jouer", 3)

    local gameOverScreen, gameOverCard = createOverlay(gameArea, 0.15)
    gameOverScreen.Visible = false
    addTitle(gameOverCard, "Perdu !", 1)
    local scoreRow = Instance.new("Frame")
    scoreRow.BackgroundTransparency = 1
    scoreRow.Size = UDim2.new(1, -20, 0, 50)
    scoreRow.LayoutOrder = 2
    scoreRow.ZIndex = 32
    scoreRow.Parent = gameOverCard
    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    rowLayout.Padding = UDim.new(0, 30)
    rowLayout.Parent = scoreRow

    local finalScoreLabel = scoreStat(scoreRow, "Score")
    local bestScoreLabel = scoreStat(scoreRow, "Meilleur")
    local restartBtn = addButton(gameOverCard, "Rejouer", 3)

    local pauseScreen, pauseCard = createOverlay(gameArea, 0.35)
    pauseScreen.Visible = false
    addTitle(pauseCard, "Pause", 1)
    local resumeBtn = addButton(pauseCard, "Reprendre", 2)

    local BASE_INTERVAL, MIN_INTERVAL, SPEED_STEP = 0.14, 0.07, 0.004
    local HEAD_COLOR = Color3.fromRGB(120, 220, 130)
    local BODY_COLOR = Color3.fromRGB(80, 180, 95)
    local FOOD_COLOR = Color3.fromRGB(230, 80, 80)

    local gameState = "start" -- start | playing | paused | gameover
    local segments = {}
    local segmentFrames = {}
    local dir, queuedDir = Vector2.new(1, 0), Vector2.new(1, 0)
    local moveInterval, moveTimer = BASE_INTERVAL, 0
    local score, bestScore = 0, deps.bestScore
    local food = { x = 0, y = 0 }

    local foodFrame = Instance.new("Frame")
    foodFrame.BackgroundColor3 = FOOD_COLOR
    foodFrame.BorderSizePixel = 0
    foodFrame.Size = UDim2.new(0, CELL - 4, 0, CELL - 4)
    foodFrame.ZIndex = 9
    foodFrame.Parent = board
    corner(foodFrame, UDim.new(1, 0))

    local function isOnSnake(x, y, limit)
        for i = 1, limit or #segments do
            local seg = segments[i]
            if seg.x == x and seg.y == y then
                return true
            end
        end
        return false
    end

    local function spawnFood()
        local fx, fy
        repeat
            fx = math.random(0, GRID - 1)
            fy = math.random(0, GRID - 1)
        until not isOnSnake(fx, fy)
        food.x, food.y = fx, fy
        foodFrame.Position = UDim2.new(0, fx * CELL + 2, 0, fy * CELL + 2)
    end

    local function ensureFrame(i)
        local f = segmentFrames[i]
        if not f then
            f = Instance.new("Frame")
            f.BorderSizePixel = 0
            f.ZIndex = 10
            f.Parent = board
            corner(f, UDim.new(0, 5))
            segmentFrames[i] = f
        end
        return f
    end

    local function render()
        for i, seg in ipairs(segments) do
            local f = ensureFrame(i)
            f.Visible = true
            f.BackgroundColor3 = (i == 1) and HEAD_COLOR or BODY_COLOR
            f.Size = UDim2.new(0, CELL - 2, 0, CELL - 2)
            f.Position = UDim2.new(0, seg.x * CELL + 1, 0, seg.y * CELL + 1)
        end
        for i = #segments + 1, #segmentFrames do
            segmentFrames[i].Visible = false
        end
    end

    local function resetGame()
        segments = {
            { x = 4, y = 8 },
            { x = 3, y = 8 },
            { x = 2, y = 8 },
        }
        dir = Vector2.new(1, 0)
        queuedDir = dir
        moveInterval = BASE_INTERVAL
        moveTimer = 0
        score = 0
        scoreLabel.Text = "0"
        spawnFood()
        render()
    end

    local function startGame()
        startScreen.Visible = false
        gameOverScreen.Visible = false
        pauseScreen.Visible = false
        resetGame()
        gameState = "playing"
    end

    local function endGame()
        if gameState ~= "playing" then return end
        gameState = "gameover"
        playSound("hit")
        if score > bestScore then
            bestScore = score
            bestBadge.Text = "Meilleur : " .. tostring(bestScore)
            deps.reportBest(bestScore)
        end
        finalScoreLabel.Text = tostring(score)
        bestScoreLabel.Text = tostring(bestScore)
        gameOverScreen.Visible = true
    end

    local function setPaused(paused)
        if paused and gameState == "playing" then
            gameState = "paused"
            pauseScreen.Visible = true
            deps.onPauseChanged(true)
        elseif not paused and gameState == "paused" then
            gameState = "playing"
            pauseScreen.Visible = false
            deps.onPauseChanged(false)
        end
    end

    local function togglePause()
        setPaused(gameState ~= "paused")
    end

    local function requestDirection(nx, ny)
        if gameState ~= "playing" then return end
        if nx == -dir.X and ny == -dir.Y then return end -- pas de demi-tour direct
        queuedDir = Vector2.new(nx, ny)
    end

    local function step()
        dir = queuedDir
        local head = segments[1]
        local newHead = { x = head.x + dir.X, y = head.y + dir.Y }

        if newHead.x < 0 or newHead.x >= GRID or newHead.y < 0 or newHead.y >= GRID then
            endGame()
            return
        end

        local eating = newHead.x == food.x and newHead.y == food.y
        local selfLimit = eating and #segments or (#segments - 1)
        if isOnSnake(newHead.x, newHead.y, selfLimit) then
            endGame()
            return
        end

        table.insert(segments, 1, newHead)
        if eating then
            score += 1
            scoreLabel.Text = tostring(score)
            moveInterval = math.max(MIN_INTERVAL, moveInterval - SPEED_STEP)
            spawnFood()
            playSound("eat")
        else
            table.remove(segments)
        end

        render()
    end

    ltrack(startBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(restartBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(resumeBtn.MouseButton1Click:Connect(function()
        playSound("click")
        togglePause()
    end))

    ltrack(UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        local key = input.KeyCode
        if key == Enum.KeyCode.Up or key == Enum.KeyCode.W then
            requestDirection(0, -1)
        elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S then
            requestDirection(0, 1)
        elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.A then
            requestDirection(-1, 0)
        elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.D then
            requestDirection(1, 0)
        elseif key == Enum.KeyCode.Space then
            if gameState == "gameover" then
                startGame()
            end
        elseif key == Enum.KeyCode.Escape then
            togglePause()
        end
    end))

    ltrack(UIS.TouchSwipe:Connect(function(swipeDirection, gameProcessed)
        if gameProcessed then return end
        if swipeDirection == Enum.SwipeDirection.Up then
            requestDirection(0, -1)
        elseif swipeDirection == Enum.SwipeDirection.Down then
            requestDirection(0, 1)
        elseif swipeDirection == Enum.SwipeDirection.Left then
            requestDirection(-1, 0)
        elseif swipeDirection == Enum.SwipeDirection.Right then
            requestDirection(1, 0)
        end
    end))

    ltrack(RunService.Heartbeat:Connect(function(dt)
        if gameState ~= "playing" then return end
        moveTimer += dt
        while moveTimer >= moveInterval do
            moveTimer -= moveInterval
            step()
            if gameState ~= "playing" then break end
        end
    end))

    return {
        TogglePause = function() togglePause() end,
        Stop = function()
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Jeu 3 : Dino Runner ============--

local function BuildDinoRunner(gameArea, deps)
    local GAME_HEIGHT, GROUND_HEIGHT = 640, 60
    local PLAYABLE_HEIGHT = GAME_HEIGHT - GROUND_HEIGHT

    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(247, 247, 250)

    local ground = Instance.new("Frame")
    ground.Size = UDim2.new(1, 0, 0, GROUND_HEIGHT)
    ground.Position = UDim2.new(0, 0, 1, -GROUND_HEIGHT)
    ground.BackgroundColor3 = Color3.fromRGB(226, 226, 232)
    ground.BorderSizePixel = 0
    ground.ZIndex = 5
    ground.Parent = gameArea

    local groundLine = Instance.new("Frame")
    groundLine.Size = UDim2.new(1, 0, 0, 3)
    groundLine.BackgroundColor3 = Color3.fromRGB(120, 120, 130)
    groundLine.BorderSizePixel = 0
    groundLine.ZIndex = 5
    groundLine.Parent = ground

    for i = 1, 10 do
        local dash = Instance.new("Frame")
        dash.Size = UDim2.new(0, 18, 0, 3)
        dash.Position = UDim2.new(0, (i - 1) * 42, 0, 20)
        dash.BackgroundColor3 = Color3.fromRGB(190, 190, 200)
        dash.BorderSizePixel = 0
        dash.ZIndex = 6
        dash.Parent = ground
    end

    local DINO_X, DINO_W, DINO_H = 50, 30, 34
    local dino = Instance.new("Frame")
    dino.AnchorPoint = Vector2.new(0, 1)
    dino.Size = UDim2.new(0, DINO_W, 0, DINO_H)
    dino.Position = UDim2.new(0, DINO_X, 0, PLAYABLE_HEIGHT)
    dino.BackgroundColor3 = Color3.fromRGB(80, 190, 120)
    dino.BorderSizePixel = 0
    dino.ZIndex = 10
    dino.Parent = gameArea
    corner(dino, UDim.new(0, 8))

    local dinoHead = Instance.new("Frame")
    dinoHead.Size = UDim2.new(0, 16, 0, 16)
    dinoHead.Position = UDim2.new(1, -14, 0, -10)
    dinoHead.BackgroundColor3 = Color3.fromRGB(80, 190, 120)
    dinoHead.BorderSizePixel = 0
    dinoHead.ZIndex = 10
    dinoHead.Parent = dino
    corner(dinoHead, UDim.new(0, 6))

    local dinoEye = Instance.new("Frame")
    dinoEye.Size = UDim2.new(0, 5, 0, 5)
    dinoEye.Position = UDim2.new(1, -9, 0, 4)
    dinoEye.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    dinoEye.BorderSizePixel = 0
    dinoEye.ZIndex = 11
    dinoEye.Parent = dinoHead
    corner(dinoEye, UDim.new(1, 0))

    local scoreLabel = Instance.new("TextLabel")
    scoreLabel.BackgroundTransparency = 1
    scoreLabel.Position = UDim2.new(1, -110, 0, 8)
    scoreLabel.Size = UDim2.new(0, 100, 0, 34)
    scoreLabel.Font = Enum.Font.GothamBold
    scoreLabel.TextSize = 22
    scoreLabel.TextColor3 = Color3.fromRGB(70, 70, 80)
    scoreLabel.TextXAlignment = Enum.TextXAlignment.Right
    scoreLabel.Text = "0"
    scoreLabel.ZIndex = 20
    scoreLabel.Parent = gameArea

    local bestBadge = Instance.new("TextLabel")
    bestBadge.BackgroundTransparency = 1
    bestBadge.Position = UDim2.new(1, -160, 0, 40)
    bestBadge.Size = UDim2.new(0, 150, 0, 18)
    bestBadge.Font = Enum.Font.GothamBold
    bestBadge.TextSize = 13
    bestBadge.TextColor3 = Color3.fromRGB(220, 160, 20)
    bestBadge.TextXAlignment = Enum.TextXAlignment.Right
    bestBadge.Text = "Meilleur : " .. tostring(deps.bestScore)
    bestBadge.ZIndex = 20
    bestBadge.Parent = gameArea

    local startScreen, startCard = createOverlay(gameArea, 0.1)
    addTitle(startCard, "DINO RUNNER", 1)
    local startSubtitle = Instance.new("TextLabel")
    startSubtitle.BackgroundTransparency = 1
    startSubtitle.Size = UDim2.new(1, -30, 0, 44)
    startSubtitle.Font = Enum.Font.Gotham
    startSubtitle.TextSize = 14
    startSubtitle.TextWrapped = true
    startSubtitle.TextColor3 = Color3.fromRGB(90, 90, 90)
    startSubtitle.Text = "Touche l'écran, clique ou appuie sur Espace\npour sauter par-dessus les cactus"
    startSubtitle.LayoutOrder = 2
    startSubtitle.ZIndex = 32
    startSubtitle.Parent = startCard
    local startBtn = addButton(startCard, "Jouer", 3)

    local gameOverScreen, gameOverCard = createOverlay(gameArea, 0.1)
    gameOverScreen.Visible = false
    addTitle(gameOverCard, "Perdu !", 1)
    local scoreRow = Instance.new("Frame")
    scoreRow.BackgroundTransparency = 1
    scoreRow.Size = UDim2.new(1, -20, 0, 50)
    scoreRow.LayoutOrder = 2
    scoreRow.ZIndex = 32
    scoreRow.Parent = gameOverCard
    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    rowLayout.Padding = UDim.new(0, 30)
    rowLayout.Parent = scoreRow

    local finalScoreLabel = scoreStat(scoreRow, "Score")
    local bestScoreLabel = scoreStat(scoreRow, "Meilleur")
    local restartBtn = addButton(gameOverCard, "Rejouer", 3)

    local pauseScreen, pauseCard = createOverlay(gameArea, 0.3)
    pauseScreen.Visible = false
    addTitle(pauseCard, "Pause", 1)
    local resumeBtn = addButton(pauseCard, "Reprendre", 2)

    local GRAVITY = 1100
    local JUMP_IMPULSE = 420
    local BASE_SPEED, MAX_SPEED, SPEED_RAMP = 220, 420, 4
    local OBSTACLE_MIN_GAP, OBSTACLE_MAX_GAP = 160, 300
    local OBSTACLE_COLOR = Color3.fromRGB(60, 140, 90)

    local gameState = "start" -- start | playing | paused | gameover
    local dinoHeight, dinoVelY, grounded = 0, 0, true
    local obstacleSpeed = BASE_SPEED
    local scoreAccum, score, bestScore = 0, 0, deps.bestScore
    local obstacles = {}

    local function clearObstacles()
        for _, o in ipairs(obstacles) do
            o.frame:Destroy()
        end
        obstacles = {}
    end

    local function spawnObstacle(x)
        local width = math.random(16, 26)
        local height = math.random(28, 48)
        local frame = Instance.new("Frame")
        frame.BackgroundColor3 = OBSTACLE_COLOR
        frame.BorderSizePixel = 0
        frame.AnchorPoint = Vector2.new(0, 1)
        frame.Size = UDim2.new(0, width, 0, height)
        frame.Position = UDim2.new(0, x, 0, PLAYABLE_HEIGHT)
        frame.ZIndex = 8
        frame.Parent = gameArea
        corner(frame, UDim.new(0, 4))
        table.insert(obstacles, { frame = frame, x = x, width = width, height = height })
    end

    local function spawnInitialObstacles()
        local x = WINDOW_WIDTH + 120
        for _ = 1, 4 do
            spawnObstacle(x)
            x += math.random(OBSTACLE_MIN_GAP, OBSTACLE_MAX_GAP)
        end
    end

    local function resetGame()
        clearObstacles()
        dinoHeight = 0
        dinoVelY = 0
        grounded = true
        obstacleSpeed = BASE_SPEED
        scoreAccum = 0
        score = 0
        scoreLabel.Text = "0"
        dino.Position = UDim2.new(0, DINO_X, 0, PLAYABLE_HEIGHT)
        dino.Rotation = 0
        spawnInitialObstacles()
    end

    local function startGame()
        startScreen.Visible = false
        gameOverScreen.Visible = false
        pauseScreen.Visible = false
        resetGame()
        gameState = "playing"
    end

    local function endGame()
        if gameState ~= "playing" then return end
        gameState = "gameover"
        playSound("hit")
        if score > bestScore then
            bestScore = score
            bestBadge.Text = "Meilleur : " .. tostring(bestScore)
            deps.reportBest(bestScore)
        end
        finalScoreLabel.Text = tostring(score)
        bestScoreLabel.Text = tostring(bestScore)
        gameOverScreen.Visible = true
    end

    local function setPaused(paused)
        if paused and gameState == "playing" then
            gameState = "paused"
            pauseScreen.Visible = true
            deps.onPauseChanged(true)
        elseif not paused and gameState == "paused" then
            gameState = "playing"
            pauseScreen.Visible = false
            deps.onPauseChanged(false)
        end
    end

    local function togglePause()
        setPaused(gameState ~= "paused")
    end

    local function jump()
        if gameState == "playing" and grounded then
            dinoVelY = JUMP_IMPULSE
            grounded = false
            playSound("jump")
        end
    end

    ltrack(startBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(restartBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(resumeBtn.MouseButton1Click:Connect(function()
        playSound("click")
        togglePause()
    end))

    ltrack(UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        local isPrimary = input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
            or input.KeyCode == Enum.KeyCode.Space
        if isPrimary then
            if gameState == "gameover" then
                startGame()
            else
                jump()
            end
        elseif input.KeyCode == Enum.KeyCode.Escape then
            togglePause()
        end
    end))

    ltrack(RunService.Heartbeat:Connect(function(dt)
        if gameState ~= "playing" then return end

        if not grounded then
            dinoVelY -= GRAVITY * dt
            dinoHeight += dinoVelY * dt
            if dinoHeight <= 0 then
                dinoHeight = 0
                dinoVelY = 0
                grounded = true
            end
        end
        dino.Position = UDim2.new(0, DINO_X, 0, PLAYABLE_HEIGHT - dinoHeight)
        dino.Rotation = grounded and 0 or math.clamp(-dinoVelY / 14, -18, 25)

        scoreAccum += dt * 10
        obstacleSpeed = math.min(MAX_SPEED, BASE_SPEED + scoreAccum * SPEED_RAMP * 0.01)
        local newScore = math.floor(scoreAccum)
        if newScore ~= score then
            score = newScore
            scoreLabel.Text = tostring(score)
        end

        local dinoBottom = PLAYABLE_HEIGHT - dinoHeight
        local rightmostX = 0

        for _, o in ipairs(obstacles) do
            o.x -= obstacleSpeed * dt
            o.frame.Position = UDim2.new(0, o.x, 0, PLAYABLE_HEIGHT)
            rightmostX = math.max(rightmostX, o.x)

            local obstacleTop = PLAYABLE_HEIGHT - o.height
            local overlapsX = DINO_X + DINO_W > o.x and DINO_X < o.x + o.width
            local overlapsY = dinoBottom > obstacleTop
            if overlapsX and overlapsY then
                endGame()
                return
            end
        end

        for _, o in ipairs(obstacles) do
            if o.x + o.width < -20 then
                o.x = rightmostX + math.random(OBSTACLE_MIN_GAP, OBSTACLE_MAX_GAP)
                o.width = math.random(16, 26)
                o.height = math.random(28, 48)
                o.frame.Size = UDim2.new(0, o.width, 0, o.height)
                o.frame.Position = UDim2.new(0, o.x, 0, PLAYABLE_HEIGHT)
            end
        end
    end))

    return {
        TogglePause = function() togglePause() end,
        Stop = function()
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Jeu 4 : Pong (vs IA) ============--

local function BuildPong(gameArea, deps)
    local GAME_HEIGHT = 640
    local PADDLE_W, PADDLE_H = 70, 10
    local BALL_R = 7
    local AI_Y, PLAYER_Y = 22, GAME_HEIGHT - 22
    local AI_SPEED = 190
    local BASE_BALL_SPEED, MAX_BALL_SPEED, SPEED_STEP = 220, 480, 12

    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
    gameArea.Active = true

    local midLine = Instance.new("Frame")
    midLine.Size = UDim2.new(1, 0, 0, 2)
    midLine.Position = UDim2.new(0, 0, 0.5, -1)
    midLine.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    midLine.BackgroundTransparency = 0.4
    midLine.BorderSizePixel = 0
    midLine.ZIndex = 1
    midLine.Parent = gameArea

    local aiPaddle = Instance.new("Frame")
    aiPaddle.Size = UDim2.new(0, PADDLE_W, 0, PADDLE_H)
    aiPaddle.AnchorPoint = Vector2.new(0.5, 0.5)
    aiPaddle.Position = UDim2.new(0, WINDOW_WIDTH / 2, 0, AI_Y)
    aiPaddle.BackgroundColor3 = Color3.fromRGB(230, 90, 90)
    aiPaddle.BorderSizePixel = 0
    aiPaddle.ZIndex = 5
    aiPaddle.Parent = gameArea
    corner(aiPaddle, UDim.new(1, 0))

    local playerPaddle = Instance.new("Frame")
    playerPaddle.Size = UDim2.new(0, PADDLE_W, 0, PADDLE_H)
    playerPaddle.AnchorPoint = Vector2.new(0.5, 0.5)
    playerPaddle.Position = UDim2.new(0, WINDOW_WIDTH / 2, 0, PLAYER_Y)
    playerPaddle.BackgroundColor3 = Color3.fromRGB(90, 200, 230)
    playerPaddle.BorderSizePixel = 0
    playerPaddle.ZIndex = 5
    playerPaddle.Parent = gameArea
    corner(playerPaddle, UDim.new(1, 0))

    local ball = Instance.new("Frame")
    ball.Size = UDim2.new(0, BALL_R * 2, 0, BALL_R * 2)
    ball.AnchorPoint = Vector2.new(0.5, 0.5)
    ball.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ball.BorderSizePixel = 0
    ball.ZIndex = 6
    ball.Parent = gameArea
    corner(ball, UDim.new(1, 0))

    local scoreLabel = Instance.new("TextLabel")
    scoreLabel.BackgroundTransparency = 1
    scoreLabel.Position = UDim2.new(0.5, -60, 0, 16)
    scoreLabel.Size = UDim2.new(0, 120, 0, 50)
    scoreLabel.Font = Enum.Font.GothamBold
    scoreLabel.TextSize = 36
    scoreLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    scoreLabel.TextStrokeTransparency = 0
    scoreLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
    scoreLabel.Text = "0"
    scoreLabel.ZIndex = 20
    scoreLabel.Parent = gameArea

    local bestBadge = Instance.new("TextLabel")
    bestBadge.BackgroundTransparency = 1
    bestBadge.Position = UDim2.new(0.5, -80, 0, 62)
    bestBadge.Size = UDim2.new(0, 160, 0, 20)
    bestBadge.Font = Enum.Font.GothamBold
    bestBadge.TextSize = 14
    bestBadge.TextColor3 = Color3.fromRGB(255, 215, 0)
    bestBadge.TextStrokeTransparency = 0.4
    bestBadge.Text = "Meilleur : " .. tostring(deps.bestScore)
    bestBadge.ZIndex = 20
    bestBadge.Parent = gameArea

    local startScreen, startCard = createOverlay(gameArea, 0.15)
    addTitle(startCard, "PONG", 1)
    local startSubtitle = Instance.new("TextLabel")
    startSubtitle.BackgroundTransparency = 1
    startSubtitle.Size = UDim2.new(1, -30, 0, 50)
    startSubtitle.Font = Enum.Font.Gotham
    startSubtitle.TextSize = 14
    startSubtitle.TextWrapped = true
    startSubtitle.TextColor3 = Color3.fromRGB(90, 90, 90)
    startSubtitle.Text = "Glisse le doigt ou fleches Gauche/Droite\npour renvoyer la balle face a l'IA"
    startSubtitle.LayoutOrder = 2
    startSubtitle.ZIndex = 32
    startSubtitle.Parent = startCard
    local startBtn = addButton(startCard, "Jouer", 3)

    local gameOverScreen, gameOverCard = createOverlay(gameArea, 0.15)
    gameOverScreen.Visible = false
    addTitle(gameOverCard, "Perdu !", 1)
    local scoreRow = Instance.new("Frame")
    scoreRow.BackgroundTransparency = 1
    scoreRow.Size = UDim2.new(1, -20, 0, 50)
    scoreRow.LayoutOrder = 2
    scoreRow.ZIndex = 32
    scoreRow.Parent = gameOverCard
    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    rowLayout.Padding = UDim.new(0, 30)
    rowLayout.Parent = scoreRow

    local finalScoreLabel = scoreStat(scoreRow, "Score")
    local bestScoreLabel = scoreStat(scoreRow, "Meilleur")
    local restartBtn = addButton(gameOverCard, "Rejouer", 3)

    local pauseScreen, pauseCard = createOverlay(gameArea, 0.35)
    pauseScreen.Visible = false
    addTitle(pauseCard, "Pause", 1)
    local resumeBtn = addButton(pauseCard, "Reprendre", 2)

    local gameState = "start" -- start | playing | paused | gameover
    local paddleX = WINDOW_WIDTH / 2
    local ballX, ballY = WINDOW_WIDTH / 2, GAME_HEIGHT / 2
    local ballVX, ballVY = 0, 0
    local score, bestScore = 0, deps.bestScore
    local ballSpeed = BASE_BALL_SPEED

    local function clampPaddle(x)
        return math.clamp(x, PADDLE_W / 2, WINDOW_WIDTH - PADDLE_W / 2)
    end

    local function launchBall()
        ballX, ballY = WINDOW_WIDTH / 2, GAME_HEIGHT / 2
        ballSpeed = BASE_BALL_SPEED
        local angle = math.rad(math.random(-40, 40))
        local dirY = (math.random(0, 1) == 0) and -1 or 1
        ballVX = math.sin(angle) * ballSpeed
        ballVY = math.cos(angle) * ballSpeed * dirY
    end

    local function resetGame()
        paddleX = WINDOW_WIDTH / 2
        playerPaddle.Position = UDim2.new(0, paddleX, 0, PLAYER_Y)
        aiPaddle.Position = UDim2.new(0, WINDOW_WIDTH / 2, 0, AI_Y)
        score = 0
        scoreLabel.Text = "0"
        launchBall()
    end

    local function startGame()
        startScreen.Visible = false
        gameOverScreen.Visible = false
        pauseScreen.Visible = false
        resetGame()
        gameState = "playing"
    end

    local function endGame()
        if gameState ~= "playing" then return end
        gameState = "gameover"
        playSound("hit")
        if score > bestScore then
            bestScore = score
            bestBadge.Text = "Meilleur : " .. tostring(bestScore)
            deps.reportBest(bestScore)
        end
        finalScoreLabel.Text = tostring(score)
        bestScoreLabel.Text = tostring(bestScore)
        gameOverScreen.Visible = true
    end

    local function setPaused(paused)
        if paused and gameState == "playing" then
            gameState = "paused"
            pauseScreen.Visible = true
            deps.onPauseChanged(true)
        elseif not paused and gameState == "paused" then
            gameState = "playing"
            pauseScreen.Visible = false
            deps.onPauseChanged(false)
        end
    end

    local function togglePause()
        setPaused(gameState ~= "paused")
    end

    local function setPaddleTarget(x)
        if gameState ~= "playing" then return end
        paddleX = clampPaddle(x)
    end

    local function toLocalX(absoluteX)
        local width = gameArea.AbsoluteSize.X
        if width <= 0 then return paddleX end
        local scale = width / WINDOW_WIDTH
        return (absoluteX - gameArea.AbsolutePosition.X) / scale
    end

    ltrack(startBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(restartBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(resumeBtn.MouseButton1Click:Connect(function()
        playSound("click")
        togglePause()
    end))

    local dragging = false
    ltrack(gameArea.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setPaddleTarget(toLocalX(input.Position.X))
        end
    end))
    ltrack(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end))
    ltrack(UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setPaddleTarget(toLocalX(input.Position.X))
        end
    end))

    local heldLeft, heldRight = false, false
    ltrack(UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
            heldLeft = true
        elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
            heldRight = true
        elseif input.KeyCode == Enum.KeyCode.Space then
            if gameState == "gameover" then startGame() end
        elseif input.KeyCode == Enum.KeyCode.Escape then
            togglePause()
        end
    end))
    ltrack(UIS.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
            heldLeft = false
        elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
            heldRight = false
        end
    end))

    ltrack(RunService.Heartbeat:Connect(function(dt)
        if gameState ~= "playing" then return end

        if heldLeft then paddleX = clampPaddle(paddleX - 260 * dt) end
        if heldRight then paddleX = clampPaddle(paddleX + 260 * dt) end
        playerPaddle.Position = UDim2.new(0, paddleX, 0, PLAYER_Y)

        local aiTargetX = clampPaddle(ballX)
        local aiCurrentX = aiPaddle.Position.X.Offset
        local aiStep = math.clamp(aiTargetX - aiCurrentX, -AI_SPEED * dt, AI_SPEED * dt)
        aiPaddle.Position = UDim2.new(0, aiCurrentX + aiStep, 0, AI_Y)

        ballX += ballVX * dt
        ballY += ballVY * dt

        if ballX - BALL_R < 0 then
            ballX = BALL_R
            ballVX = -ballVX
        elseif ballX + BALL_R > WINDOW_WIDTH then
            ballX = WINDOW_WIDTH - BALL_R
            ballVX = -ballVX
        end

        if ballVY < 0 and ballY - BALL_R <= AI_Y + PADDLE_H / 2 then
            ballY = AI_Y + PADDLE_H / 2 + BALL_R
            ballVY = -ballVY
        end

        if ballVY > 0 and ballY + BALL_R >= PLAYER_Y - PADDLE_H / 2 and ballY - BALL_R < PLAYER_Y + PADDLE_H then
            if math.abs(ballX - paddleX) <= PADDLE_W / 2 + BALL_R then
                ballY = PLAYER_Y - PADDLE_H / 2 - BALL_R
                ballSpeed = math.min(MAX_BALL_SPEED, ballSpeed + SPEED_STEP)
                local offset = math.clamp((ballX - paddleX) / (PADDLE_W / 2), -1, 1)
                local angle = math.rad(offset * 50)
                ballVX = math.sin(angle) * ballSpeed
                ballVY = -math.cos(angle) * ballSpeed
                score += 1
                scoreLabel.Text = tostring(score)
                playSound("score")
            end
        end

        if ballY - BALL_R > GAME_HEIGHT then
            endGame()
            return
        end

        ball.Position = UDim2.new(0, ballX, 0, ballY)
    end))

    return {
        TogglePause = function() togglePause() end,
        Stop = function()
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Appli : Calculatrice ============--

local function BuildCalculator(gameArea, deps)
    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(18, 18, 22)

    local display = Instance.new("TextLabel")
    display.Size = UDim2.new(1, -24, 0, 90)
    display.Position = UDim2.new(0, 12, 0, 16)
    display.BackgroundTransparency = 1
    display.Font = Enum.Font.GothamBold
    display.TextSize = 40
    display.TextColor3 = Color3.fromRGB(255, 255, 255)
    display.TextXAlignment = Enum.TextXAlignment.Right
    display.TextYAlignment = Enum.TextYAlignment.Bottom
    display.Text = "0"
    display.Parent = gameArea

    local state = {
        display = "0",
        firstValue = nil,
        pendingOp = nil,
        waitingForSecond = false,
    }

    local function refresh()
        display.Text = state.display
    end

    local function pressDigit(d)
        if state.waitingForSecond then
            state.display = d
            state.waitingForSecond = false
        elseif state.display == "0" then
            state.display = d
        elseif #state.display < 14 then
            state.display = state.display .. d
        end
        refresh()
    end

    local function pressDot()
        if state.waitingForSecond then
            state.display = "0."
            state.waitingForSecond = false
            refresh()
            return
        end
        if not state.display:find("%.") then
            state.display = state.display .. "."
            refresh()
        end
    end

    local function compute(a, op, b)
        if op == "+" then
            return a + b
        elseif op == "-" then
            return a - b
        elseif op == "\195\151" then
            return a * b
        elseif op == "\195\183" then
            return (b ~= 0) and (a / b) or 0
        end
        return b
    end

    local function pressOp(op)
        local current = tonumber(state.display) or 0
        if state.pendingOp and not state.waitingForSecond then
            state.firstValue = compute(state.firstValue or 0, state.pendingOp, current)
            state.display = tostring(state.firstValue)
        else
            state.firstValue = current
        end
        state.pendingOp = op
        state.waitingForSecond = true
        refresh()
    end

    local function pressEquals()
        if not state.pendingOp then return end
        local current = tonumber(state.display) or 0
        local result = compute(state.firstValue or 0, state.pendingOp, current)
        state.display = tostring(result)
        state.firstValue = nil
        state.pendingOp = nil
        state.waitingForSecond = true
        refresh()
    end

    local function pressClear()
        state.display = "0"
        state.firstValue = nil
        state.pendingOp = nil
        state.waitingForSecond = false
        refresh()
    end

    local function pressBackspace()
        if state.waitingForSecond then return end
        if #state.display > 1 then
            state.display = state.display:sub(1, -2)
        else
            state.display = "0"
        end
        refresh()
    end

    local function pressPercent()
        local current = tonumber(state.display) or 0
        state.display = tostring(current / 100)
        refresh()
    end

    local BUTTONS = {
        { "C", "op", pressClear },
        { "\226\140\171", "op", pressBackspace },
        { "%", "op", pressPercent },
        { "\195\183", "op", function() pressOp("\195\183") end },
        { "7", "num" },
        { "8", "num" },
        { "9", "num" },
        { "\195\151", "op", function() pressOp("\195\151") end },
        { "4", "num" },
        { "5", "num" },
        { "6", "num" },
        { "-", "op", function() pressOp("-") end },
        { "1", "num" },
        { "2", "num" },
        { "3", "num" },
        { "+", "op", function() pressOp("+") end },
        { "0", "num" },
        { ".", "dot" },
        { "=", "eq" },
    }

    local grid = Instance.new("Frame")
    grid.Size = UDim2.new(1, -24, 0, 5 * 62 + 4 * 10)
    grid.Position = UDim2.new(0, 12, 0, 118)
    grid.BackgroundTransparency = 1
    grid.Parent = gameArea

    local gridLayout = Instance.new("UIGridLayout")
    gridLayout.CellSize = UDim2.new(0, 62, 0, 62)
    gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
    gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
    gridLayout.Parent = grid

    for i, spec in ipairs(BUTTONS) do
        local text, kind, fn = spec[1], spec[2], spec[3]
        local btn = Instance.new("TextButton")
        btn.LayoutOrder = i
        btn.Text = text
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 22
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.AutoButtonColor = true
        if kind == "op" or kind == "eq" then
            btn.BackgroundColor3 = Color3.fromRGB(255, 149, 30)
        else
            btn.BackgroundColor3 = Color3.fromRGB(50, 50, 56)
        end
        btn.Parent = grid
        corner(btn, UDim.new(1, 0))

        if kind == "num" then
            ltrack(btn.MouseButton1Click:Connect(function()
                playSound("click")
                pressDigit(text)
            end))
        elseif kind == "dot" then
            ltrack(btn.MouseButton1Click:Connect(function()
                playSound("click")
                pressDot()
            end))
        elseif kind == "eq" then
            ltrack(btn.MouseButton1Click:Connect(function()
                playSound("click")
                pressEquals()
            end))
        elseif kind == "op" and fn then
            ltrack(btn.MouseButton1Click:Connect(function()
                playSound("click")
                fn()
            end))
        end
    end

    return {
        TogglePause = function() end,
        Stop = function()
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Appli : Notes ============--

local function BuildNotes(gameArea, deps)
    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    local NOTES_FILE = "sxe_phone_notes.txt"
    local function canUseFiles()
        return typeof(readfile) == "function" and typeof(writefile) == "function" and typeof(isfile) == "function"
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(250, 248, 240)

    local toolbar = Instance.new("Frame")
    toolbar.Size = UDim2.new(1, 0, 0, 40)
    toolbar.BackgroundColor3 = Color3.fromRGB(235, 232, 220)
    toolbar.BorderSizePixel = 0
    toolbar.Parent = gameArea

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -140, 1, 0)
    statusLabel.Position = UDim2.new(0, 12, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 12
    statusLabel.TextColor3 = Color3.fromRGB(130, 125, 110)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Text = canUseFiles() and "" or "(pas de sauvegarde ici)"
    statusLabel.Parent = toolbar

    local clearBtn = Instance.new("TextButton")
    clearBtn.Size = UDim2.new(0, 60, 0, 28)
    clearBtn.Position = UDim2.new(1, -132, 0, 6)
    clearBtn.BackgroundColor3 = Color3.fromRGB(220, 90, 90)
    clearBtn.Font = Enum.Font.GothamBold
    clearBtn.TextSize = 13
    clearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    clearBtn.Text = "Effacer"
    clearBtn.Parent = toolbar
    corner(clearBtn, UDim.new(0, 8))

    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(0, 60, 0, 28)
    saveBtn.Position = UDim2.new(1, -66, 0, 6)
    saveBtn.BackgroundColor3 = Color3.fromRGB(80, 170, 100)
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.TextSize = 13
    saveBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    saveBtn.Text = "Sauver"
    saveBtn.Parent = toolbar
    corner(saveBtn, UDim.new(0, 8))

    local scrollArea = Instance.new("ScrollingFrame")
    scrollArea.Size = UDim2.new(1, 0, 1, -40)
    scrollArea.Position = UDim2.new(0, 0, 0, 40)
    scrollArea.BackgroundTransparency = 1
    scrollArea.BorderSizePixel = 0
    scrollArea.ScrollingDirection = Enum.ScrollingDirection.Y
    scrollArea.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollArea.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollArea.ScrollBarThickness = 4
    scrollArea.Parent = gameArea

    local textBox = Instance.new("TextBox")
    textBox.Size = UDim2.new(1, -24, 0, 600)
    textBox.Position = UDim2.new(0, 12, 0, 10)
    textBox.BackgroundTransparency = 1
    textBox.Font = Enum.Font.Gotham
    textBox.TextSize = 15
    textBox.TextColor3 = Color3.fromRGB(40, 38, 30)
    textBox.TextXAlignment = Enum.TextXAlignment.Left
    textBox.TextYAlignment = Enum.TextYAlignment.Top
    textBox.TextWrapped = true
    textBox.MultiLine = true
    textBox.ClearTextOnFocus = false
    textBox.PlaceholderText = "Ecris ta note ici..."
    textBox.Text = ""
    textBox.Parent = scrollArea

    if canUseFiles() then
        local okFile, exists = pcall(isfile, NOTES_FILE)
        if okFile and exists then
            local okRead, data = pcall(readfile, NOTES_FILE)
            if okRead and data then
                textBox.Text = data
            end
        end
    end

    local function doSave()
        if not canUseFiles() then return end
        pcall(writefile, NOTES_FILE, textBox.Text)
        statusLabel.Text = "Enregistre !"
        task.delay(1.5, function()
            if statusLabel and statusLabel.Parent then
                statusLabel.Text = ""
            end
        end)
    end

    ltrack(saveBtn.MouseButton1Click:Connect(function()
        playSound("click")
        doSave()
    end))
    ltrack(clearBtn.MouseButton1Click:Connect(function()
        playSound("click")
        textBox.Text = ""
    end))

    return {
        TogglePause = function() end,
        Stop = function()
            doSave()
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Appli : Musique ============--
-- Remplace les "rbxassetid://0" ci-dessous par tes propres IDs de musique
-- (Toolbox > Audio dans Studio, ou un ID que tu possedes deja). Tant qu'un
-- ID n'est pas valide, la piste affiche juste "Ajoute un ID valide".

-- Style inspire de Spotify (vert, pas le vrai logo -- juste la palette et l'icone
-- ronde) applique aux boutons/accents du lecteur.
local MUSIC_GREEN = Color3.fromRGB(30, 215, 96)
local MUSIC_GREEN_DARK = Color3.fromRGB(18, 130, 58)

local MUSIC_PLAYLIST_FILE = "sxe_phone_music_playlist.json"

local function musicCanUseFiles()
    return typeof(readfile) == "function" and typeof(writefile) == "function" and typeof(isfile) == "function"
end

local function loadMusicPlaylist()
    if not musicCanUseFiles() then return {} end
    local ok, data = pcall(function()
        if isfile(MUSIC_PLAYLIST_FILE) then return HttpService:JSONDecode(readfile(MUSIC_PLAYLIST_FILE)) end
    end)
    if ok and type(data) == "table" then return data end
    return {}
end

local function saveMusicPlaylist(list)
    if not musicCanUseFiles() then return end
    pcall(function() writefile(MUSIC_PLAYLIST_FILE, HttpService:JSONEncode(list)) end)
end

-- Recherche en direct dans le catalogue audio Roblox (meme API que la Toolbox de
-- Roblox Studio). Roblox ne peut pas lire un lien YouTube directement : le moteur
-- audio n'accepte que des sons uploades sur Roblox (rbxassetid://). Le nom exact du
-- parametre de recherche n'est pas documente publiquement donc on essaie plusieurs
-- variantes et on garde la premiere qui renvoie vraiment des resultats.
--
-- L'API de Roblox est protegee par un jeton XSRF (comme la plupart de ses endpoints
-- POST) : le premier essai renvoie une erreur "XSRF token invalid" + le vrai jeton
-- dans l'en-tete de la reponse -- il faut relancer la meme requete avec ce jeton.

local function musicDoRequest(url, method, headers, body)
    if typeof(request) == "function" then
        local ok, res = pcall(request, { Url = url, Method = method, Headers = headers, Body = body })
        if ok and res then return res, nil end
    end
    if syn and syn.request then
        local ok, res = pcall(syn.request, { Url = url, Method = method, Headers = headers, Body = body })
        if ok and res then return res, nil end
    end
    local ok, res = pcall(function()
        return HttpService:RequestAsync({ Url = url, Method = method, Headers = headers, Body = body })
    end)
    if ok and res then return res, nil end
    return nil, tostring(res)
end

local function findHeader(headersTable, name)
    if type(headersTable) ~= "table" then return nil end
    local lname = name:lower()
    for k, v in pairs(headersTable) do
        if tostring(k):lower() == lname then return v end
    end
    return nil
end

-- Le filtrage par mot-cle semble ignore quand la requete est anonyme (Roblox renvoie
-- toujours filteredKeyword=''), mais fonctionne probablement avec la session du joueur
-- (comme le fait Roblox Studio quand tu es connecte). On authentifie donc la requete
-- avec le cookie .ROBLOSECURITY du joueur via getcookie() -- fourni par l'executor,
-- envoye UNIQUEMENT vers apis.roblox.com, jamais ailleurs.
local function getRobloxCookie()
    if typeof(getcookie) == "function" then
        local ok, cookie = pcall(getcookie)
        if ok and type(cookie) == "string" and cookie ~= "" then return cookie end
    end
    if typeof(get_cookie) == "function" then
        local ok, cookie = pcall(get_cookie)
        if ok and type(cookie) == "string" and cookie ~= "" then return cookie end
    end
    return nil
end

-- GET avec le mot-cle dans l'URL (comme le vrai exemple de la Toolbox de Studio) --
-- pas POST avec un JSON body comme la doc Open Cloud le laissait penser.
local function musicHttpGet(url)
    local headers = { ["Content-Type"] = "application/json" }
    local cookie = getRobloxCookie()
    if cookie then headers["Cookie"] = cookie end

    local res, err = musicDoRequest(url, "GET", headers, nil)
    if not res then
        return nil, "aucune methode HTTP disponible: " .. tostring(err)
    end

    if res.Body and res.Body:find("XSRF token invalid", 1, true) then
        local token = findHeader(res.Headers, "x-csrf-token")
        if token then
            headers["X-CSRF-TOKEN"] = token
            local res2 = musicDoRequest(url, "GET", headers, nil)
            if res2 and res2.Body then return res2.Body, nil end
            return nil, "echec apres jeton XSRF"
        end
        return nil, "XSRF token invalid mais pas de jeton dans la reponse"
    end

    if res.Body then return res.Body, nil end
    return nil, "reponse sans corps (statut " .. tostring(res.StatusCode) .. ")"
end

local MUSIC_SEARCH_URL = "https://apis.roblox.com/toolbox-service/v2/assets:search"
local MUSIC_PARAM_VARIANTS = { "keyword", "query", "searchQuery", "text", "q", "Keyword", "SearchTerm", "searchTerm" }

local function searchMusicCatalog(queryText)
    local lastHttpErr = nil
    local lastParseErr = nil
    local encoded = HttpService:UrlEncode(queryText)
    local cookieTag = getRobloxCookie() and "cookie:oui" or "cookie:non"

    for _, paramName in ipairs(MUSIC_PARAM_VARIANTS) do
        local url = MUSIC_SEARCH_URL
            .. "?searchCategoryType=Audio&limit=20&"
            .. paramName .. "=" .. encoded
        local body, httpErr = musicHttpGet(url)
        if httpErr then lastHttpErr = httpErr end
        if body then
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if not ok then
                lastParseErr = "[" .. paramName .. "] JSON invalide: " .. tostring(body):sub(1, 80)
            elseif type(data) ~= "table" then
                lastParseErr = "[" .. paramName .. "] reponse pas une table"
            elseif type(data.creatorStoreAssets) ~= "table" then
                local okDump, dump = pcall(function() return HttpService:JSONEncode(data) end)
                lastParseErr = "[" .. paramName .. "] " .. (okDump and dump:sub(1, 200) or "reponse: " .. tostring(body):sub(1, 200))
            elseif #data.creatorStoreAssets == 0 then
                lastParseErr = "[" .. paramName .. "] creatorStoreAssets vide (filteredKeyword="
                    .. tostring(data.filteredKeyword) .. ")"
            else
                local fk = tostring(data.filteredKeyword or ""):lower()
                local wanted = queryText:lower()
                if fk == "" or not (fk:find(wanted, 1, true) or wanted:find(fk, 1, true)) then
                    lastParseErr = "[" .. paramName .. "] resultats non filtres (filteredKeyword='"
                        .. tostring(data.filteredKeyword) .. "', voulu='" .. queryText .. "')"
                else
                    local results = {}
                    for _, entry in ipairs(data.creatorStoreAssets) do
                        local a = entry.asset
                        if a and a.id then
                            table.insert(results, {
                                id = a.id,
                                name = a.title or a.name or ("Audio " .. tostring(a.id)),
                                artist = a.artist or (entry.creator and entry.creator.name) or "",
                                duration = a.durationSeconds or 0,
                            })
                        end
                    end
                    if #results > 0 then return results, nil end
                    lastParseErr = "[" .. paramName .. "] assets presents mais aucun .asset.id lisible"
                end
            end
        end
    end
    if lastParseErr then
        return nil, "Echec parsing (" .. cookieTag .. "): " .. lastParseErr
    end
    return nil, "Echec reseau (" .. cookieTag .. "): " .. tostring(lastHttpErr or "raison inconnue")
end

local function musicNormalizeId(raw)
    raw = tostring(raw or ""):match("^%s*(.-)%s*$")
    if raw:match("^%d+$") then return "rbxassetid://" .. raw end
    return raw
end

-- Lecteur persistant : la musique continue de jouer meme quand le telephone est
-- ferme ou qu'on change d'appli. Le Sound et l'etat de lecture vivent ICI, hors de
-- BuildMusic, et ne sont jamais detruits a la fermeture de l'appli -- seule l'UI
-- (les connexions locales) est nettoyee dans Stop().
local persistentMusicSound = Instance.new("Sound")
persistentMusicSound.Name = "MusicPlayerSound"
persistentMusicSound.Volume = 0.5
persistentMusicSound.Looped = false
persistentMusicSound.Parent = SoundService

local persistentMusicPlaylist = loadMusicPlaylist()
local persistentMusicIndex = nil
local persistentMusicPlaying = false
local persistentMusicNowPlayingName = nil
local musicUIHooks = nil

local function musicPlayIndexCore(index)
    local track = persistentMusicPlaylist[index]
    if not track then return end
    persistentMusicIndex = index
    persistentMusicSound:Stop()
    persistentMusicSound.SoundId = musicNormalizeId(track.id)
    persistentMusicSound:Play()
    persistentMusicPlaying = true
    persistentMusicNowPlayingName = track.name
    if musicUIHooks then musicUIHooks.onTrackChanged() end
end

persistentMusicSound.Ended:Connect(function()
    if #persistentMusicPlaylist == 0 then return end
    local newIndex = (persistentMusicIndex or 0) + 1
    if newIndex > #persistentMusicPlaylist then newIndex = 1 end
    musicPlayIndexCore(newIndex)
end)

local function BuildMusic(gameArea, deps)
    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(16, 20, 18)

    local sound = persistentMusicSound
    local playlist = persistentMusicPlaylist

    local artHolder = Instance.new("Frame")
    artHolder.Size = UDim2.new(0, 80, 0, 80)
    artHolder.Position = UDim2.new(0.5, -40, 0, 10)
    artHolder.BackgroundColor3 = MUSIC_GREEN
    artHolder.Parent = gameArea
    corner(artHolder, UDim.new(1, 0))

    local noteLabel = Instance.new("TextLabel")
    noteLabel.Size = UDim2.fromScale(1, 1)
    noteLabel.BackgroundTransparency = 1
    noteLabel.Font = Enum.Font.GothamBold
    noteLabel.TextSize = 34
    noteLabel.TextColor3 = Color3.fromRGB(15, 15, 15)
    noteLabel.Text = "\240\159\142\181"
    noteLabel.Parent = artHolder

    local trackNameLabel = Instance.new("TextLabel")
    trackNameLabel.Size = UDim2.new(1, -24, 0, 20)
    trackNameLabel.Position = UDim2.new(0, 12, 0, 94)
    trackNameLabel.BackgroundTransparency = 1
    trackNameLabel.Font = Enum.Font.GothamBold
    trackNameLabel.TextSize = 14
    trackNameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    trackNameLabel.TextXAlignment = Enum.TextXAlignment.Center
    trackNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    trackNameLabel.Text = "Aucune lecture"
    trackNameLabel.Parent = gameArea

    local timeLabel = Instance.new("TextLabel")
    timeLabel.Size = UDim2.new(1, -24, 0, 14)
    timeLabel.Position = UDim2.new(0, 12, 0, 116)
    timeLabel.BackgroundTransparency = 1
    timeLabel.Font = Enum.Font.Gotham
    timeLabel.TextSize = 11
    timeLabel.TextColor3 = Color3.fromRGB(170, 165, 180)
    timeLabel.TextXAlignment = Enum.TextXAlignment.Center
    timeLabel.Text = "0:00 / 0:00"
    timeLabel.Parent = gameArea

    local progressBack = Instance.new("Frame")
    progressBack.Size = UDim2.new(1, -24, 0, 4)
    progressBack.Position = UDim2.new(0, 12, 0, 134)
    progressBack.BackgroundColor3 = Color3.fromRGB(60, 55, 70)
    progressBack.BorderSizePixel = 0
    progressBack.Parent = gameArea
    corner(progressBack, UDim.new(1, 0))

    local progressFill = Instance.new("Frame")
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    progressFill.BackgroundColor3 = MUSIC_GREEN
    progressFill.BorderSizePixel = 0
    progressFill.Parent = progressBack
    corner(progressFill, UDim.new(1, 0))

    local function controlButton(txt, x)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 40, 0, 40)
        btn.Position = UDim2.new(0.5, x, 0, 148)
        btn.BackgroundColor3 = Color3.fromRGB(45, 38, 60)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 16
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Text = txt
        btn.Parent = gameArea
        corner(btn, UDim.new(1, 0))
        return btn
    end

    local prevBtn = controlButton("\226\143\174", -76)
    local playBtn = controlButton("\226\150\182", -22)
    playBtn.Size = UDim2.new(0, 48, 0, 48)
    playBtn.Position = UDim2.new(0.5, -24, 0, 144)
    playBtn.BackgroundColor3 = MUSIC_GREEN
    local nextBtn = controlButton("\226\143\173", 32)

    local volBack = Instance.new("Frame")
    volBack.Size = UDim2.new(1, -60, 0, 4)
    volBack.Position = UDim2.new(0, 40, 0, 204)
    volBack.BackgroundColor3 = Color3.fromRGB(60, 55, 70)
    volBack.BorderSizePixel = 0
    volBack.Active = true
    volBack.Parent = gameArea
    corner(volBack, UDim.new(1, 0))

    local volFill = Instance.new("Frame")
    volFill.Size = UDim2.new(0.5, 0, 1, 0)
    volFill.BackgroundColor3 = MUSIC_GREEN
    volFill.BorderSizePixel = 0
    volFill.Parent = volBack
    corner(volFill, UDim.new(1, 0))

    local volIcon = Instance.new("TextLabel")
    volIcon.Size = UDim2.new(0, 24, 0, 16)
    volIcon.Position = UDim2.new(0, 12, 0, 198)
    volIcon.BackgroundTransparency = 1
    volIcon.Font = Enum.Font.Gotham
    volIcon.TextSize = 11
    volIcon.TextColor3 = Color3.fromRGB(170, 165, 180)
    volIcon.Text = "\240\159\148\138"
    volIcon.Parent = gameArea

    local searchInput = Instance.new("TextBox")
    searchInput.Size = UDim2.new(1, -100, 0, 28)
    searchInput.Position = UDim2.new(0, 12, 0, 220)
    searchInput.BackgroundColor3 = Color3.fromRGB(38, 32, 50)
    searchInput.PlaceholderText = "Nom de l'artiste / chanson..."
    searchInput.Text = ""
    searchInput.TextColor3 = Color3.fromRGB(230, 225, 235)
    searchInput.Font = Enum.Font.Gotham
    searchInput.TextSize = 12
    searchInput.ClearTextOnFocus = false
    searchInput.Parent = gameArea
    corner(searchInput, UDim.new(0, 8))
    do
        local p = Instance.new("UIPadding")
        p.PaddingLeft = UDim.new(0, 10)
        p.Parent = searchInput
    end

    local searchGoBtn = Instance.new("TextButton")
    searchGoBtn.Size = UDim2.new(0, 76, 0, 28)
    searchGoBtn.Position = UDim2.new(1, -88, 0, 220)
    searchGoBtn.BackgroundColor3 = MUSIC_GREEN
    searchGoBtn.Text = "\240\159\148\141 Chercher"
    searchGoBtn.TextSize = 11
    searchGoBtn.TextWrapped = true
    searchGoBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    searchGoBtn.Font = Enum.Font.GothamBold
    searchGoBtn.Parent = gameArea
    corner(searchGoBtn, UDim.new(0, 8))

    local tabsRow = Instance.new("Frame")
    tabsRow.Size = UDim2.new(1, -24, 0, 24)
    tabsRow.Position = UDim2.new(0, 12, 0, 254)
    tabsRow.BackgroundTransparency = 1
    tabsRow.Parent = gameArea

    local playlistTabBtn = Instance.new("TextButton")
    playlistTabBtn.Size = UDim2.new(0.333, -4, 1, 0)
    playlistTabBtn.BackgroundColor3 = MUSIC_GREEN
    playlistTabBtn.Text = "Playlist"
    playlistTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    playlistTabBtn.Font = Enum.Font.GothamBold
    playlistTabBtn.TextSize = 11
    playlistTabBtn.Parent = tabsRow
    corner(playlistTabBtn, UDim.new(0, 6))

    local searchTabBtn = Instance.new("TextButton")
    searchTabBtn.Size = UDim2.new(0.333, -4, 1, 0)
    searchTabBtn.Position = UDim2.new(0.333, 4, 0, 0)
    searchTabBtn.BackgroundColor3 = Color3.fromRGB(38, 32, 50)
    searchTabBtn.Text = "Resultats"
    searchTabBtn.TextColor3 = Color3.fromRGB(200, 195, 210)
    searchTabBtn.Font = Enum.Font.GothamBold
    searchTabBtn.TextSize = 11
    searchTabBtn.Parent = tabsRow
    corner(searchTabBtn, UDim.new(0, 6))

    local localTabBtn = Instance.new("TextButton")
    localTabBtn.Size = UDim2.new(0.334, -4, 1, 0)
    localTabBtn.Position = UDim2.new(0.666, 0, 0, 0)
    localTabBtn.BackgroundColor3 = Color3.fromRGB(38, 32, 50)
    localTabBtn.Text = "Locale"
    localTabBtn.TextColor3 = Color3.fromRGB(200, 195, 210)
    localTabBtn.Font = Enum.Font.GothamBold
    localTabBtn.TextSize = 11
    localTabBtn.Parent = tabsRow
    corner(localTabBtn, UDim.new(0, 6))

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1, -24, 0, 200)
    listFrame.Position = UDim2.new(0, 12, 0, 284)
    listFrame.BackgroundTransparency = 1
    listFrame.BorderSizePixel = 0
    listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    listFrame.ScrollBarThickness = 3
    listFrame.Parent = gameArea

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 6)
    listLayout.Parent = listFrame

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -24, 0, 74)
    statusLabel.Position = UDim2.new(0, 12, 0, 490)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 10
    statusLabel.TextColor3 = Color3.fromRGB(170, 165, 180)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.TextWrapped = true
    statusLabel.Text = ""
    statusLabel.Parent = gameArea

    local addNameInput = Instance.new("TextBox")
    addNameInput.Size = UDim2.new(1, -24, 0, 24)
    addNameInput.Position = UDim2.new(0, 12, 0, 566)
    addNameInput.BackgroundColor3 = Color3.fromRGB(38, 32, 50)
    addNameInput.PlaceholderText = "Nom (ajout manuel si pas trouve)"
    addNameInput.Text = ""
    addNameInput.TextColor3 = Color3.fromRGB(230, 225, 235)
    addNameInput.Font = Enum.Font.Gotham
    addNameInput.TextSize = 11
    addNameInput.ClearTextOnFocus = false
    addNameInput.Parent = gameArea
    corner(addNameInput, UDim.new(0, 6))
    do
        local p = Instance.new("UIPadding")
        p.PaddingLeft = UDim.new(0, 8)
        p.Parent = addNameInput
    end

    local addIdInput = Instance.new("TextBox")
    addIdInput.Size = UDim2.new(0.62, -18, 0, 24)
    addIdInput.Position = UDim2.new(0, 12, 0, 594)
    addIdInput.BackgroundColor3 = Color3.fromRGB(38, 32, 50)
    addIdInput.PlaceholderText = "ID audio Roblox"
    addIdInput.Text = ""
    addIdInput.TextColor3 = Color3.fromRGB(230, 225, 235)
    addIdInput.Font = Enum.Font.Gotham
    addIdInput.TextSize = 11
    addIdInput.ClearTextOnFocus = false
    addIdInput.Parent = gameArea
    corner(addIdInput, UDim.new(0, 6))
    do
        local p = Instance.new("UIPadding")
        p.PaddingLeft = UDim.new(0, 8)
        p.Parent = addIdInput
    end

    local addBtn = Instance.new("TextButton")
    addBtn.Size = UDim2.new(0.38, -14, 0, 24)
    addBtn.Position = UDim2.new(0.62, 0, 0, 594)
    addBtn.BackgroundColor3 = Color3.fromRGB(90, 180, 120)
    addBtn.Text = "+ Ajouter"
    addBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    addBtn.Font = Enum.Font.GothamBold
    addBtn.TextSize = 11
    addBtn.Parent = gameArea
    corner(addBtn, UDim.new(0, 6))

    local function formatTime(t)
        t = math.max(0, t or 0)
        local m = math.floor(t / 60)
        local s = math.floor(t % 60)
        return string.format("%d:%02d", m, s)
    end

    local playTrack, updatePlayIcon

    updatePlayIcon = function()
        playBtn.Text = persistentMusicPlaying and "\226\143\184" or "\226\150\182"
    end

    musicUIHooks = {
        onTrackChanged = function()
            trackNameLabel.Text = persistentMusicNowPlayingName or "Aucune lecture"
            updatePlayIcon()
        end,
    }
    musicUIHooks.onTrackChanged()

    playTrack = function(index)
        musicPlayIndexCore(index)
    end

    local function playTrackNow(track)
        table.insert(playlist, track)
        saveMusicPlaylist(playlist)
        playTrack(#playlist)
    end

    ltrack(playBtn.MouseButton1Click:Connect(function()
        playSound("click")
        if sound.SoundId == "" then
            if #playlist > 0 then playTrack(1) end
            return
        end
        if persistentMusicPlaying then
            sound:Pause()
            persistentMusicPlaying = false
        else
            sound:Resume()
            persistentMusicPlaying = true
        end
        updatePlayIcon()
    end))

    ltrack(prevBtn.MouseButton1Click:Connect(function()
        playSound("click")
        if #playlist == 0 then return end
        local newIndex = (persistentMusicIndex or 1) - 1
        if newIndex < 1 then newIndex = #playlist end
        playTrack(newIndex)
    end))

    ltrack(nextBtn.MouseButton1Click:Connect(function()
        playSound("click")
        if #playlist == 0 then return end
        local newIndex = (persistentMusicIndex or 0) + 1
        if newIndex > #playlist then newIndex = 1 end
        playTrack(newIndex)
    end))

    local draggingVol = false
    local function setVolumeFromX(x)
        local rel = math.clamp((x - volBack.AbsolutePosition.X) / math.max(1, volBack.AbsoluteSize.X), 0, 1)
        sound.Volume = rel
        volFill.Size = UDim2.new(rel, 0, 1, 0)
    end
    ltrack(volBack.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingVol = true
            setVolumeFromX(input.Position.X)
        end
    end))
    ltrack(UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingVol = false
        end
    end))
    ltrack(UIS.InputChanged:Connect(function(input)
        if draggingVol and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setVolumeFromX(input.Position.X)
        end
    end))
    volFill.Size = UDim2.new(sound.Volume, 0, 1, 0)

    ltrack(RunService.Heartbeat:Connect(function()
        if sound.TimeLength > 0 then
            local ratio = math.clamp(sound.TimePosition / sound.TimeLength, 0, 1)
            progressFill.Size = UDim2.new(ratio, 0, 1, 0)
            timeLabel.Text = formatTime(sound.TimePosition) .. " / " .. formatTime(sound.TimeLength)
        end
    end))

    -- ===== Vue Playlist / Resultats recherche =====
    local viewMode = "playlist"
    local lastSearchResults = {}

    local function setActiveTab(mode)
        viewMode = mode
        local tabs = {
            playlist = playlistTabBtn,
            search = searchTabBtn,
            localfiles = localTabBtn,
        }
        for name, btn in pairs(tabs) do
            if name == mode then
                btn.BackgroundColor3 = MUSIC_GREEN
                btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            else
                btn.BackgroundColor3 = Color3.fromRGB(38, 32, 50)
                btn.TextColor3 = Color3.fromRGB(200, 195, 210)
            end
        end
    end

    local function clearList()
        for _, c in ipairs(listFrame:GetChildren()) do
            if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end
        end
    end

    local function makeMusicRow(mainText, subText, order)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, subText and 40 or 34)
        row.BackgroundColor3 = Color3.fromRGB(38, 32, 50)
        row.LayoutOrder = order
        row.Parent = listFrame
        corner(row, UDim.new(0, 8))

        local mainBtn = Instance.new("TextButton")
        mainBtn.Size = UDim2.new(1, -30, 0, subText and 20 or 34)
        mainBtn.BackgroundTransparency = 1
        mainBtn.Text = mainText
        mainBtn.TextColor3 = Color3.fromRGB(230, 225, 235)
        mainBtn.Font = Enum.Font.Gotham
        mainBtn.TextSize = 13
        mainBtn.TextXAlignment = Enum.TextXAlignment.Left
        mainBtn.TextTruncate = Enum.TextTruncate.AtEnd
        mainBtn.Parent = row
        do
            local p = Instance.new("UIPadding")
            p.PaddingLeft = UDim.new(0, 12)
            p.Parent = mainBtn
        end

        if subText then
            local subLbl = Instance.new("TextLabel")
            subLbl.Size = UDim2.new(1, -30, 0, 16)
            subLbl.Position = UDim2.new(0, 0, 0, 20)
            subLbl.BackgroundTransparency = 1
            subLbl.Text = subText
            subLbl.TextColor3 = Color3.fromRGB(160, 155, 170)
            subLbl.Font = Enum.Font.Gotham
            subLbl.TextSize = 10
            subLbl.TextXAlignment = Enum.TextXAlignment.Left
            subLbl.TextTruncate = Enum.TextTruncate.AtEnd
            subLbl.Parent = row
            do
                local p = Instance.new("UIPadding")
                p.PaddingLeft = UDim.new(0, 12)
                p.Parent = subLbl
            end
        end

        return row, mainBtn
    end

    local function refreshPlaylistView()
        clearList()
        for i, mtrack in ipairs(playlist) do
            local row, mainBtn = makeMusicRow(i .. ". " .. mtrack.name, nil, i)
            row.BackgroundColor3 = (i == persistentMusicIndex) and MUSIC_GREEN_DARK or Color3.fromRGB(38, 32, 50)

            local delBtn = Instance.new("TextButton")
            delBtn.Size = UDim2.new(0, 26, 1, 0)
            delBtn.Position = UDim2.new(1, -26, 0, 0)
            delBtn.BackgroundTransparency = 1
            delBtn.Text = "x"
            delBtn.TextColor3 = Color3.fromRGB(200, 90, 90)
            delBtn.Font = Enum.Font.GothamBold
            delBtn.TextSize = 13
            delBtn.Parent = row

            ltrack(mainBtn.MouseButton1Click:Connect(function()
                playSound("click")
                playTrack(i)
                refreshPlaylistView()
            end))
            ltrack(delBtn.MouseButton1Click:Connect(function()
                playSound("click")
                table.remove(playlist, i)
                saveMusicPlaylist(playlist)
                if persistentMusicIndex == i then
                    sound:Stop()
                    persistentMusicPlaying = false
                    persistentMusicIndex = nil
                    persistentMusicNowPlayingName = nil
                    trackNameLabel.Text = "Aucune lecture"
                    updatePlayIcon()
                elseif persistentMusicIndex and persistentMusicIndex > i then
                    persistentMusicIndex = persistentMusicIndex - 1
                end
                refreshPlaylistView()
            end))
        end
    end

    local function renderSearchResults()
        clearList()
        if #lastSearchResults == 0 then
            makeMusicRow(statusLabel.Text ~= "" and statusLabel.Text or "Aucun resultat.", nil, 1)
            return
        end
        for i, res in ipairs(lastSearchResults) do
            local sub = (res.artist ~= "" and res.artist or "Inconnu") .. "  -  " .. formatTime(res.duration)
            local row, mainBtn = makeMusicRow(res.name, sub, i)
            ltrack(mainBtn.MouseButton1Click:Connect(function()
                playSound("score")
                playTrackNow({ name = res.name, id = tostring(res.id) })
                setActiveTab("playlist")
                refreshPlaylistView()
            end))
        end
    end

    -- ===== Musique locale (getcustomasset) =====
    -- Roblox ne peut pas lire un lien YouTube ni un fichier hors de son catalogue --
    -- SAUF si l'executor expose getcustomasset(), une fonction UNC standard qui
    -- transforme un fichier local en identifiant jouable (rbxasset://) sans passer
    -- par l'upload/la moderation Roblox. Tu telecharges toi-meme une chanson
    -- (n'importe quelle source, dans ton navigateur) en .mp3/.ogg/.wav, tu la mets
    -- dans le dossier ci-dessous, et elle apparait ici, jouable directement.
    local MUSIC_LOCAL_FOLDER = "SXEPhone/Musics"
    local MUSIC_LOCAL_EXTENSIONS = { mp3 = true, ogg = true, wav = true }

    local function localFilesSupported()
        return typeof(isfolder) == "function"
            and typeof(makefolder) == "function"
            and typeof(listfiles) == "function"
            and typeof(getcustomasset) == "function"
    end

    local function ensureMusicLocalFolder()
        if not localFilesSupported() then return end
        pcall(function()
            if not isfolder("SXEPhone") then makefolder("SXEPhone") end
            if not isfolder(MUSIC_LOCAL_FOLDER) then makefolder(MUSIC_LOCAL_FOLDER) end
        end)
    end

    -- Si le fichier est nomme avec un ID video YouTube (ex: 60ItHLz5WEA.mp3), on va
    -- chercher le vrai titre via l'API publique officielle oEmbed de YouTube (aucune
    -- cle requise, pas de scraping) pour l'afficher a la place du nom de fichier brut.
    local YT_TITLE_CACHE_FILE = "sxe_phone_yt_titles.json"
    local function loadYtTitleCache()
        if not musicCanUseFiles() then return {} end
        local ok, data = pcall(function()
            if isfile(YT_TITLE_CACHE_FILE) then return HttpService:JSONDecode(readfile(YT_TITLE_CACHE_FILE)) end
        end)
        if ok and type(data) == "table" then return data end
        return {}
    end
    local function saveYtTitleCache(cache)
        if not musicCanUseFiles() then return end
        pcall(function() writefile(YT_TITLE_CACHE_FILE, HttpService:JSONEncode(cache)) end)
    end
    local ytTitleCache = loadYtTitleCache()

    local function youtubeIdFromFilename(fname)
        return fname:match("^([%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-][%w_%-])%.%w+$")
    end

    local function fetchYoutubeTitle(videoId)
        if ytTitleCache[videoId] then return ytTitleCache[videoId] end
        local url = "https://www.youtube.com/oembed?format=json&url="
            .. HttpService:UrlEncode("https://www.youtube.com/watch?v=" .. videoId)
        local res, _ = musicDoRequest(url, "GET", {}, nil)
        if not res or not res.Body then return nil end
        local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
        if ok and type(data) == "table" and data.title then
            ytTitleCache[videoId] = data.title
            saveYtTitleCache(ytTitleCache)
            return data.title
        end
        return nil
    end

    local function listLocalMusicFiles()
        if not localFilesSupported() then return {}, "getcustomasset/listfiles indisponibles sur cet executor" end
        local folderOk = isfolder(MUSIC_LOCAL_FOLDER)
        local ok, files = pcall(listfiles, MUSIC_LOCAL_FOLDER)
        if not ok then
            return {}, "listfiles() a plante: " .. tostring(files) .. " (isfolder=" .. tostring(folderOk) .. ")"
        end
        if type(files) ~= "table" then
            return {}, "listfiles() a renvoye un " .. typeof(files) .. " au lieu d'une table (isfolder=" .. tostring(folderOk) .. ")"
        end
        local found = {}
        local rawCount = #files
        for _, path in ipairs(files) do
            local ext = tostring(path):match("%.([%a%d]+)$")
            if ext and MUSIC_LOCAL_EXTENSIONS[ext:lower()] then
                local fname = tostring(path):match("[^/\\]+$") or path
                local ytId = youtubeIdFromFilename(fname)
                table.insert(found, { name = fname, path = path, youtubeId = ytId })
            end
        end
        table.sort(found, function(a, b) return a.name < b.name end)
        if #found == 0 then
            local sample = files[1] and tostring(files[1]) or "(aucune entree)"
            return found, "isfolder=" .. tostring(folderOk) .. ", listfiles a trouve " .. rawCount
                .. " entree(s) brute(s), 0 apres filtre extension. Exemple brut: " .. sample
        end
        return found, nil
    end

    local function playLocalFile(path)
        local ok, assetId = pcall(getcustomasset, path)
        if not ok or not assetId then
            statusLabel.Text = "Impossible de charger ce fichier local."
            return
        end
        sound:Stop()
        persistentMusicIndex = nil
        sound.SoundId = assetId
        sound:Play()
        persistentMusicPlaying = true
        persistentMusicNowPlayingName = path:match("[^/\\]+$") or path
        trackNameLabel.Text = persistentMusicNowPlayingName
        updatePlayIcon()
    end

    local localFilesRenderToken = 0

    local function drawLocalFilesList(files)
        clearList()
        for i, f in ipairs(files) do
            local title = f.youtubeId and ytTitleCache[f.youtubeId]
            local mainText = title or f.name
            local subText = title and f.name or nil
            local row, mainBtn = makeMusicRow(mainText, subText, i)
            ltrack(mainBtn.MouseButton1Click:Connect(function()
                playSound("score")
                playLocalFile(f.path)
            end))
        end
    end

    local function renderLocalFiles()
        clearList()
        if not localFilesSupported() then
            makeMusicRow("Ton executor ne supporte pas getcustomasset -- fichiers locaux indisponibles.", nil, 1)
            return
        end
        ensureMusicLocalFolder()
        local files, dbg = listLocalMusicFiles()
        if #files == 0 then
            makeMusicRow(dbg or ("Dossier vide. Mets tes .mp3/.ogg/.wav dans: " .. MUSIC_LOCAL_FOLDER), nil, 1)
            return
        end

        -- On recupere TOUS les titres avant d'afficher quoi que ce soit, pour que
        -- les vrais noms apparaissent directement au lieu des ID.
        local toFetch = {}
        for _, f in ipairs(files) do
            if f.youtubeId and not ytTitleCache[f.youtubeId] then
                table.insert(toFetch, f.youtubeId)
            end
        end

        if #toFetch == 0 then
            drawLocalFilesList(files)
            return
        end

        localFilesRenderToken = localFilesRenderToken + 1
        local myToken = localFilesRenderToken
        makeMusicRow("Chargement des titres... (0/" .. #toFetch .. ")", nil, 1)

        local remaining = #toFetch
        local done = 0
        for _, ytId in ipairs(toFetch) do
            task.spawn(function()
                pcall(fetchYoutubeTitle, ytId)
                done = done + 1
                if myToken == localFilesRenderToken then
                    if done >= remaining then
                        drawLocalFilesList(files)
                    else
                        clearList()
                        makeMusicRow("Chargement des titres... (" .. done .. "/" .. remaining .. ")", nil, 1)
                    end
                end
            end)
        end
    end

    local function refreshList()
        if viewMode == "playlist" then
            refreshPlaylistView()
        elseif viewMode == "search" then
            renderSearchResults()
        else
            renderLocalFiles()
        end
    end
    refreshList()

    ltrack(playlistTabBtn.MouseButton1Click:Connect(function()
        playSound("click")
        setActiveTab("playlist")
        refreshList()
    end))
    ltrack(searchTabBtn.MouseButton1Click:Connect(function()
        playSound("click")
        setActiveTab("search")
        refreshList()
    end))
    ltrack(localTabBtn.MouseButton1Click:Connect(function()
        playSound("click")
        setActiveTab("localfiles")
        refreshList()
    end))

    ltrack(searchGoBtn.MouseButton1Click:Connect(function()
        playSound("click")
        local q = searchInput.Text:match("^%s*(.-)%s*$")
        if q == "" then
            statusLabel.Text = "Tape un nom d'artiste ou de chanson d'abord."
            return
        end
        statusLabel.Text = "Recherche en cours..."
        searchGoBtn.Text = "..."
        setActiveTab("search")

        task.spawn(function()
            local results, err = searchMusicCatalog(q)
            searchGoBtn.Text = "\240\159\148\141 Chercher"
            if results then
                lastSearchResults = results
                statusLabel.Text = #results .. " resultat(s) pour \"" .. q .. "\"."
            else
                lastSearchResults = {}
                statusLabel.Text = err or "Aucun resultat."
            end
            refreshList()
        end)
    end))

    ltrack(addBtn.MouseButton1Click:Connect(function()
        playSound("click")
        local name = addNameInput.Text:match("^%s*(.-)%s*$")
        local id = addIdInput.Text:match("^%s*(.-)%s*$")
        if name == "" or id == "" then return end
        table.insert(playlist, { name = name, id = id })
        saveMusicPlaylist(playlist)
        addNameInput.Text = ""
        addIdInput.Text = ""
        if viewMode == "playlist" then refreshPlaylistView() end
    end))

    return {
        TogglePause = function()
            if persistentMusicPlaying then
                sound:Pause()
                persistentMusicPlaying = false
            else
                sound:Resume()
                persistentMusicPlaying = true
            end
            updatePlayIcon()
        end,
        -- La musique continue en arriere-plan : on ne touche jamais au Sound ici,
        -- seulement l'UI de l'appli qui se ferme.
        Stop = function()
            musicUIHooks = nil
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Appli : Reglages ============--

local WALLPAPER_PRESETS = {
    { Color3.fromRGB(42, 32, 74), Color3.fromRGB(18, 18, 28) },
    { Color3.fromRGB(20, 60, 70), Color3.fromRGB(10, 20, 26) },
    { Color3.fromRGB(80, 30, 40), Color3.fromRGB(20, 12, 16) },
    { Color3.fromRGB(30, 70, 40), Color3.fromRGB(12, 22, 14) },
}

local function BuildSettings(gameArea, deps)
    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(20, 20, 26)

    local scrollArea = Instance.new("ScrollingFrame")
    scrollArea.Size = UDim2.new(1, 0, 1, 0)
    scrollArea.BackgroundTransparency = 1
    scrollArea.BorderSizePixel = 0
    scrollArea.ScrollingDirection = Enum.ScrollingDirection.Y
    scrollArea.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollArea.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollArea.ScrollBarThickness = 4
    scrollArea.Parent = gameArea

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 14)
    listLayout.Parent = scrollArea

    local listPadding = Instance.new("UIPadding")
    listPadding.PaddingTop = UDim.new(0, 16)
    listPadding.PaddingLeft = UDim.new(0, 14)
    listPadding.PaddingRight = UDim.new(0, 14)
    listPadding.PaddingBottom = UDim.new(0, 24)
    listPadding.Parent = scrollArea

    local function sectionTitle(text, order)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 13
        lbl.TextColor3 = Color3.fromRGB(160, 155, 170)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = text
        lbl.LayoutOrder = order
        lbl.Parent = scrollArea
        return lbl
    end

    local function toggleRow(label, initial, order, onChange)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 46)
        row.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
        row.LayoutOrder = order
        row.Parent = scrollArea
        corner(row, UDim.new(0, 12))

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -70, 1, 0)
        lbl.Position = UDim2.new(0, 14, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 14
        lbl.TextColor3 = Color3.fromRGB(230, 230, 235)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = label
        lbl.Parent = row

        local switchBg = Instance.new("TextButton")
        switchBg.Size = UDim2.new(0, 46, 0, 26)
        switchBg.Position = UDim2.new(1, -58, 0.5, -13)
        switchBg.BackgroundColor3 = initial and Color3.fromRGB(90, 200, 120) or Color3.fromRGB(60, 60, 68)
        switchBg.Text = ""
        switchBg.AutoButtonColor = false
        switchBg.Parent = row
        corner(switchBg, UDim.new(1, 0))

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 20, 0, 20)
        knob.Position = initial and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.Parent = switchBg
        corner(knob, UDim.new(1, 0))

        local state = initial
        ltrack(switchBg.MouseButton1Click:Connect(function()
            state = not state
            switchBg.BackgroundColor3 = state and Color3.fromRGB(90, 200, 120) or Color3.fromRGB(60, 60, 68)
            TweenService:Create(knob, TweenInfo.new(0.15), {
                Position = state and UDim2.new(1, -23, 0.5, -10) or UDim2.new(0, 3, 0.5, -10),
            }):Play()
            onChange(state)
        end))

        return row
    end

    sectionTitle("Son", 1)
    toggleRow("Sons de l'interface", _G.SXEPhoneSoundEnabled, 2, function(state)
        _G.SXEPhoneSoundEnabled = state
    end)

    sectionTitle("Fond d'ecran", 3)
    local wallpaperRow = Instance.new("Frame")
    wallpaperRow.Size = UDim2.new(1, 0, 0, 50)
    wallpaperRow.BackgroundTransparency = 1
    wallpaperRow.LayoutOrder = 4
    wallpaperRow.Parent = scrollArea

    local wallpaperLayout = Instance.new("UIListLayout")
    wallpaperLayout.FillDirection = Enum.FillDirection.Horizontal
    wallpaperLayout.Padding = UDim.new(0, 10)
    wallpaperLayout.Parent = wallpaperRow

    for i, preset in ipairs(WALLPAPER_PRESETS) do
        local swatch = Instance.new("TextButton")
        swatch.Size = UDim2.new(0, 46, 0, 46)
        swatch.BackgroundColor3 = preset[1]
        swatch.Text = ""
        swatch.LayoutOrder = i
        swatch.Parent = wallpaperRow
        corner(swatch, UDim.new(0, 12))
        local swStroke = Instance.new("UIStroke", swatch)
        swStroke.Color = preset[2]
        swStroke.Thickness = 3

        ltrack(swatch.MouseButton1Click:Connect(function()
            playSound("click")
            setCustomWallpaper("")
            wallpaperGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, preset[1]),
                ColorSequenceKeypoint.new(1, preset[2]),
            })
        end))
    end

    sectionTitle("Image personnalisee (URL ou ID Roblox)", 5)
    local wallpaperInputRow = Instance.new("Frame")
    wallpaperInputRow.Size = UDim2.new(1, 0, 0, 60)
    wallpaperInputRow.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
    wallpaperInputRow.LayoutOrder = 6
    wallpaperInputRow.Parent = scrollArea
    corner(wallpaperInputRow, UDim.new(0, 12))

    local wallpaperInput = Instance.new("TextBox")
    wallpaperInput.Size = UDim2.new(1, -84, 0, 36)
    wallpaperInput.Position = UDim2.new(0, 10, 0.5, -18)
    wallpaperInput.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    wallpaperInput.Font = Enum.Font.Gotham
    wallpaperInput.TextSize = 13
    wallpaperInput.TextColor3 = Color3.fromRGB(230, 230, 235)
    wallpaperInput.PlaceholderText = "Ex: 123456789 ou https://..."
    wallpaperInput.ClearTextOnFocus = false
    wallpaperInput.Text = ""
    wallpaperInput.Parent = wallpaperInputRow
    corner(wallpaperInput, UDim.new(0, 8))

    local wallpaperButtonsRow = Instance.new("Frame")
    wallpaperButtonsRow.Size = UDim2.new(1, 0, 0, 40)
    wallpaperButtonsRow.BackgroundTransparency = 1
    wallpaperButtonsRow.LayoutOrder = 7
    wallpaperButtonsRow.Parent = scrollArea

    local wallpaperButtonsLayout = Instance.new("UIListLayout")
    wallpaperButtonsLayout.FillDirection = Enum.FillDirection.Horizontal
    wallpaperButtonsLayout.Padding = UDim.new(0, 10)
    wallpaperButtonsLayout.Parent = wallpaperButtonsRow

    local applyWallpaperBtn = Instance.new("TextButton")
    applyWallpaperBtn.Size = UDim2.new(0, 90, 1, 0)
    applyWallpaperBtn.BackgroundColor3 = Color3.fromRGB(130, 97, 224)
    applyWallpaperBtn.Font = Enum.Font.GothamBold
    applyWallpaperBtn.TextSize = 13
    applyWallpaperBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    applyWallpaperBtn.Text = "Appliquer"
    applyWallpaperBtn.LayoutOrder = 1
    applyWallpaperBtn.Parent = wallpaperButtonsRow
    corner(applyWallpaperBtn, UDim.new(0, 10))

    local removeWallpaperBtn = Instance.new("TextButton")
    removeWallpaperBtn.Size = UDim2.new(0, 90, 1, 0)
    removeWallpaperBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
    removeWallpaperBtn.Font = Enum.Font.GothamBold
    removeWallpaperBtn.TextSize = 13
    removeWallpaperBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    removeWallpaperBtn.Text = "Retirer l'image"
    removeWallpaperBtn.LayoutOrder = 2
    removeWallpaperBtn.Parent = wallpaperButtonsRow
    corner(removeWallpaperBtn, UDim.new(0, 10))

    local testAvatarBtn = Instance.new("TextButton")
    testAvatarBtn.Size = UDim2.new(0, 95, 1, 0)
    testAvatarBtn.BackgroundColor3 = Color3.fromRGB(60, 130, 200)
    testAvatarBtn.Font = Enum.Font.GothamBold
    testAvatarBtn.TextSize = 12
    testAvatarBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    testAvatarBtn.Text = "Test: mon avatar"
    testAvatarBtn.LayoutOrder = 3
    testAvatarBtn.Parent = wallpaperButtonsRow
    corner(testAvatarBtn, UDim.new(0, 10))

    ltrack(testAvatarBtn.MouseButton1Click:Connect(function()
        playSound("click")
        local thumb = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150"
        wallpaperInput.Text = thumb
        wallpaperImage.Image = thumb
        wallpaperPreview.Image = thumb
        wallpaperStatus.TextColor3 = Color3.fromRGB(210, 200, 140)
        wallpaperStatus.Text = "Test avec ta photo de profil (garantie valide)"
    end))

    local testColorBtn = Instance.new("TextButton")
    testColorBtn.Size = UDim2.new(1, 0, 0, 40)
    testColorBtn.BackgroundColor3 = Color3.fromRGB(255, 30, 30)
    testColorBtn.Font = Enum.Font.GothamBold
    testColorBtn.TextSize = 13
    testColorBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    testColorBtn.Text = "TEST: fond rouge vif (sans degrade)"
    testColorBtn.LayoutOrder = 8
    testColorBtn.Parent = scrollArea
    corner(testColorBtn, UDim.new(0, 10))

    ltrack(testColorBtn.MouseButton1Click:Connect(function()
        playSound("click")
        wallpaperImage.Image = ""
        wallpaperGradient.Color = ColorSequence.new(Color3.fromRGB(255, 30, 30))
        homeBackdrop.BackgroundColor3 = Color3.fromRGB(255, 30, 30)
        homeBackdrop.BackgroundTransparency = 0
        wallpaperStatus.TextColor3 = Color3.fromRGB(255, 200, 100)
        wallpaperStatus.Text = "Fond mis en rouge vif -- va voir l'ecran d'accueil MAINTENANT"
    end))

    local wallpaperNote = Instance.new("TextLabel")
    wallpaperNote.Size = UDim2.new(1, 0, 0, 30)
    wallpaperNote.BackgroundTransparency = 1
    wallpaperNote.Font = Enum.Font.Gotham
    wallpaperNote.TextSize = 11
    wallpaperNote.TextColor3 = Color3.fromRGB(140, 135, 150)
    wallpaperNote.TextWrapped = true
    wallpaperNote.TextXAlignment = Enum.TextXAlignment.Left
    wallpaperNote.LayoutOrder = 9
    wallpaperNote.Text = "Marche avec un ID Roblox (Decal/Image) ou une URL directe si ton executor le permet."
    wallpaperNote.Parent = scrollArea

    local wallpaperStatus = Instance.new("TextLabel")
    wallpaperStatus.Size = UDim2.new(1, 0, 0, 20)
    wallpaperStatus.BackgroundTransparency = 1
    wallpaperStatus.Font = Enum.Font.GothamBold
    wallpaperStatus.TextSize = 12
    wallpaperStatus.TextColor3 = Color3.fromRGB(200, 200, 210)
    wallpaperStatus.TextXAlignment = Enum.TextXAlignment.Left
    wallpaperStatus.LayoutOrder = 10
    wallpaperStatus.Text = ""
    wallpaperStatus.Parent = scrollArea

    local wallpaperPreview = Instance.new("ImageLabel")
    wallpaperPreview.Size = UDim2.new(0, 44, 0, 44)
    wallpaperPreview.Position = UDim2.new(1, -54, 0.5, -22)
    wallpaperPreview.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    wallpaperPreview.Image = ""
    wallpaperPreview.ScaleType = Enum.ScaleType.Crop
    wallpaperPreview.Parent = wallpaperInputRow
    corner(wallpaperPreview, UDim.new(0, 8))
    local wallpaperPreviewStroke = Instance.new("UIStroke", wallpaperPreview)
    wallpaperPreviewStroke.Color = Color3.fromRGB(90, 90, 100)
    wallpaperPreviewStroke.Thickness = 1

    local InsertServiceForWallpaper = game:GetService("InsertService")

    ltrack(applyWallpaperBtn.MouseButton1Click:Connect(function()
        playSound("click")
        local raw = wallpaperInput.Text:match("^%s*(.-)%s*$")
        if raw == "" then
            wallpaperStatus.TextColor3 = Color3.fromRGB(230, 90, 90)
            wallpaperStatus.Text = "Champ vide"
            return
        end

        wallpaperStatus.TextColor3 = Color3.fromRGB(210, 200, 140)
        wallpaperStatus.Text = "Chargement..."

        task.spawn(function()
            local finalImage = ""
            if raw:match("^%d+$") then
                local resolved
                pcall(function()
                    local model = InsertServiceForWallpaper:LoadAsset(tonumber(raw))
                    local found = model:FindFirstChildWhichIsA("Decal", true)
                        or model:FindFirstChildWhichIsA("Texture", true)
                    if found and found.Texture and found.Texture ~= "" then
                        resolved = found.Texture
                    end
                    model:Destroy()
                end)
                finalImage = resolved or ("rbxassetid://" .. raw)
            elseif raw:match("^rbxassetid://") or raw:match("^rbxthumb://") or raw:match("^https?://") then
                finalImage = raw
            end

            if finalImage == "" then
                wallpaperStatus.TextColor3 = Color3.fromRGB(230, 90, 90)
                wallpaperStatus.Text = "Format non reconnu (mets juste le nombre, ex: 8508980536)"
                return
            end

            wallpaperImage.Image = finalImage
            wallpaperPreview.Image = finalImage
            wallpaperStatus.TextColor3 = Color3.fromRGB(120, 220, 140)
            wallpaperStatus.Text = "Applique. Regarde l'apercu a droite du champ, ou l'ecran d'accueil."
        end)
    end))
    ltrack(removeWallpaperBtn.MouseButton1Click:Connect(function()
        playSound("click")
        wallpaperInput.Text = ""
        setCustomWallpaper("")
        wallpaperPreview.Image = ""
        wallpaperStatus.Text = ""
    end))

    sectionTitle("Scores", 11)
    local resetBtn = Instance.new("TextButton")
    resetBtn.Size = UDim2.new(1, 0, 0, 44)
    resetBtn.BackgroundColor3 = Color3.fromRGB(220, 90, 90)
    resetBtn.Font = Enum.Font.GothamBold
    resetBtn.TextSize = 14
    resetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    resetBtn.Text = "Reinitialiser les meilleurs scores"
    resetBtn.LayoutOrder = 12
    resetBtn.Parent = scrollArea
    corner(resetBtn, UDim.new(0, 12))

    ltrack(resetBtn.MouseButton1Click:Connect(function()
        playSound("click")
        for id, _ in pairs(bestScores) do
            bestScores[id] = 0
            if bestLabels[id] then
                bestLabels[id].Text = "0"
                bestLabels[id].Visible = false
            end
        end
    end))

    return {
        TogglePause = function() end,
        Stop = function()
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Appli : Chrono / Minuteur ============--

local function BuildChrono(gameArea, deps)
    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(20, 20, 26)

    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -24, 0, 40)
    tabBar.Position = UDim2.new(0, 12, 0, 16)
    tabBar.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
    tabBar.Parent = gameArea
    corner(tabBar, UDim.new(0, 12))

    local chronoTabBtn = Instance.new("TextButton")
    chronoTabBtn.Size = UDim2.new(0.5, 0, 1, 0)
    chronoTabBtn.BackgroundColor3 = Color3.fromRGB(130, 97, 224)
    chronoTabBtn.Font = Enum.Font.GothamBold
    chronoTabBtn.TextSize = 13
    chronoTabBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    chronoTabBtn.Text = "Chrono"
    chronoTabBtn.Parent = tabBar
    corner(chronoTabBtn, UDim.new(0, 12))

    local timerTabBtn = Instance.new("TextButton")
    timerTabBtn.Size = UDim2.new(0.5, 0, 1, 0)
    timerTabBtn.Position = UDim2.new(0.5, 0, 0, 0)
    timerTabBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
    timerTabBtn.Font = Enum.Font.GothamBold
    timerTabBtn.TextSize = 13
    timerTabBtn.TextColor3 = Color3.fromRGB(200, 200, 210)
    timerTabBtn.Text = "Minuteur"
    timerTabBtn.Parent = tabBar
    corner(timerTabBtn, UDim.new(0, 12))

    local chronoPanel = Instance.new("Frame")
    chronoPanel.Size = UDim2.new(1, -24, 1, -80)
    chronoPanel.Position = UDim2.new(0, 12, 0, 68)
    chronoPanel.BackgroundTransparency = 1
    chronoPanel.Parent = gameArea

    local timerPanel = Instance.new("Frame")
    timerPanel.Size = UDim2.new(1, -24, 1, -80)
    timerPanel.Position = UDim2.new(0, 12, 0, 68)
    timerPanel.BackgroundTransparency = 1
    timerPanel.Visible = false
    timerPanel.Parent = gameArea

    local function switchTab(showChrono)
        chronoPanel.Visible = showChrono
        timerPanel.Visible = not showChrono
        chronoTabBtn.BackgroundColor3 = showChrono and Color3.fromRGB(130, 97, 224) or Color3.fromRGB(32, 32, 40)
        chronoTabBtn.TextColor3 = showChrono and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 210)
        timerTabBtn.BackgroundColor3 = (not showChrono) and Color3.fromRGB(130, 97, 224) or Color3.fromRGB(32, 32, 40)
        timerTabBtn.TextColor3 = (not showChrono) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 200, 210)
    end

    ltrack(chronoTabBtn.MouseButton1Click:Connect(function()
        playSound("click")
        switchTab(true)
    end))
    ltrack(timerTabBtn.MouseButton1Click:Connect(function()
        playSound("click")
        switchTab(false)
    end))

    -- Chronometre
    local chronoDisplay = Instance.new("TextLabel")
    chronoDisplay.Size = UDim2.new(1, 0, 0, 70)
    chronoDisplay.Position = UDim2.new(0, 0, 0, 30)
    chronoDisplay.BackgroundTransparency = 1
    chronoDisplay.Font = Enum.Font.GothamBold
    chronoDisplay.TextSize = 44
    chronoDisplay.TextColor3 = Color3.fromRGB(255, 255, 255)
    chronoDisplay.Text = "00:00.0"
    chronoDisplay.Parent = chronoPanel

    local chronoRunning = false
    local chronoStart = 0
    local chronoElapsed = 0

    local function formatChrono(t)
        local m = math.floor(t / 60)
        local s = t % 60
        return string.format("%02d:%04.1f", m, s)
    end

    local chronoStartBtn = Instance.new("TextButton")
    chronoStartBtn.Size = UDim2.new(0, 120, 0, 44)
    chronoStartBtn.Position = UDim2.new(0.5, -126, 0, 120)
    chronoStartBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
    chronoStartBtn.Font = Enum.Font.GothamBold
    chronoStartBtn.TextSize = 15
    chronoStartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    chronoStartBtn.Text = "Demarrer"
    chronoStartBtn.Parent = chronoPanel
    corner(chronoStartBtn, UDim.new(0, 12))

    local chronoResetBtn = Instance.new("TextButton")
    chronoResetBtn.Size = UDim2.new(0, 120, 0, 44)
    chronoResetBtn.Position = UDim2.new(0.5, 6, 0, 120)
    chronoResetBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
    chronoResetBtn.Font = Enum.Font.GothamBold
    chronoResetBtn.TextSize = 15
    chronoResetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    chronoResetBtn.Text = "Reinitialiser"
    chronoResetBtn.Parent = chronoPanel
    corner(chronoResetBtn, UDim.new(0, 12))

    ltrack(chronoStartBtn.MouseButton1Click:Connect(function()
        playSound("click")
        chronoRunning = not chronoRunning
        if chronoRunning then
            chronoStart = os.clock() - chronoElapsed
            chronoStartBtn.Text = "Pause"
            chronoStartBtn.BackgroundColor3 = Color3.fromRGB(230, 150, 60)
        else
            chronoElapsed = os.clock() - chronoStart
            chronoStartBtn.Text = "Demarrer"
            chronoStartBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
        end
    end))

    ltrack(chronoResetBtn.MouseButton1Click:Connect(function()
        playSound("click")
        chronoRunning = false
        chronoElapsed = 0
        chronoStartBtn.Text = "Demarrer"
        chronoStartBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
        chronoDisplay.Text = "00:00.0"
    end))

    ltrack(RunService.Heartbeat:Connect(function()
        if chronoRunning then
            chronoElapsed = os.clock() - chronoStart
            chronoDisplay.Text = formatChrono(chronoElapsed)
        end
    end))

    -- Minuteur
    local timerDisplay = Instance.new("TextLabel")
    timerDisplay.Size = UDim2.new(1, 0, 0, 70)
    timerDisplay.Position = UDim2.new(0, 0, 0, 30)
    timerDisplay.BackgroundTransparency = 1
    timerDisplay.Font = Enum.Font.GothamBold
    timerDisplay.TextSize = 44
    timerDisplay.TextColor3 = Color3.fromRGB(255, 255, 255)
    timerDisplay.Text = "05:00"
    timerDisplay.Parent = timerPanel

    local timerMinutes = 5
    local timerRemaining = timerMinutes * 60
    local timerRunning = false

    local function formatTimer(t)
        t = math.max(0, math.ceil(t))
        return string.format("%02d:%02d", math.floor(t / 60), t % 60)
    end

    local minusBtn = Instance.new("TextButton")
    minusBtn.Size = UDim2.new(0, 44, 0, 44)
    minusBtn.Position = UDim2.new(0.5, -100, 0, 108)
    minusBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
    minusBtn.Font = Enum.Font.GothamBold
    minusBtn.TextSize = 20
    minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minusBtn.Text = "-"
    minusBtn.Parent = timerPanel
    corner(minusBtn, UDim.new(1, 0))

    local plusBtn = Instance.new("TextButton")
    plusBtn.Size = UDim2.new(0, 44, 0, 44)
    plusBtn.Position = UDim2.new(0.5, 56, 0, 108)
    plusBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 68)
    plusBtn.Font = Enum.Font.GothamBold
    plusBtn.TextSize = 20
    plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    plusBtn.Text = "+"
    plusBtn.Parent = timerPanel
    corner(plusBtn, UDim.new(1, 0))

    local timerStartBtn = Instance.new("TextButton")
    timerStartBtn.Size = UDim2.new(0, 140, 0, 44)
    timerStartBtn.Position = UDim2.new(0.5, -70, 0, 168)
    timerStartBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
    timerStartBtn.Font = Enum.Font.GothamBold
    timerStartBtn.TextSize = 15
    timerStartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    timerStartBtn.Text = "Demarrer"
    timerStartBtn.Parent = timerPanel
    corner(timerStartBtn, UDim.new(0, 12))

    local function refreshTimerDisplay()
        if not timerRunning then
            timerRemaining = timerMinutes * 60
        end
        timerDisplay.Text = formatTimer(timerRemaining)
    end
    refreshTimerDisplay()

    ltrack(minusBtn.MouseButton1Click:Connect(function()
        if timerRunning then return end
        playSound("click")
        timerMinutes = math.max(1, timerMinutes - 1)
        refreshTimerDisplay()
    end))
    ltrack(plusBtn.MouseButton1Click:Connect(function()
        if timerRunning then return end
        playSound("click")
        timerMinutes = math.min(90, timerMinutes + 1)
        refreshTimerDisplay()
    end))

    ltrack(timerStartBtn.MouseButton1Click:Connect(function()
        playSound("click")
        if timerRunning then
            timerRunning = false
            timerStartBtn.Text = "Demarrer"
            timerStartBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
        else
            if timerRemaining <= 0 then
                timerRemaining = timerMinutes * 60
            end
            timerRunning = true
            timerStartBtn.Text = "Pause"
            timerStartBtn.BackgroundColor3 = Color3.fromRGB(230, 150, 60)
        end
    end))

    ltrack(RunService.Heartbeat:Connect(function(dt)
        if timerRunning then
            timerRemaining = timerRemaining - dt
            if timerRemaining <= 0 then
                timerRemaining = 0
                timerRunning = false
                timerStartBtn.Text = "Demarrer"
                timerStartBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
                playSound("score")
            end
            timerDisplay.Text = formatTimer(timerRemaining)
        end
    end))

    return {
        TogglePause = function() end,
        Stop = function()
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Appli : Joueurs ============--

local function BuildPlayers(gameArea, deps)
    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(20, 20, 26)

    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, -24, 0, 30)
    header.Position = UDim2.new(0, 12, 0, 14)
    header.BackgroundTransparency = 1
    header.Font = Enum.Font.GothamBold
    header.TextSize = 16
    header.TextColor3 = Color3.fromRGB(255, 255, 255)
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Text = "Joueurs dans le serveur"
    header.Parent = gameArea

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1, -24, 1, -60)
    listFrame.Position = UDim2.new(0, 12, 0, 50)
    listFrame.BackgroundTransparency = 1
    listFrame.BorderSizePixel = 0
    listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    listFrame.ScrollBarThickness = 4
    listFrame.Parent = gameArea

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 8)
    listLayout.Parent = listFrame

    local rows = {}

    local function clearRows()
        for _, row in ipairs(rows) do
            row:Destroy()
        end
        rows = {}
    end

    local function refresh()
        clearRows()
        local plrs = Players:GetPlayers()
        for i, plr in ipairs(plrs) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 46)
            row.BackgroundColor3 = Color3.fromRGB(32, 32, 40)
            row.LayoutOrder = i
            row.Parent = listFrame
            corner(row, UDim.new(0, 10))
            table.insert(rows, row)

            local nameLabel = Instance.new("TextLabel")
            nameLabel.Size = UDim2.new(1, -20, 0, 20)
            nameLabel.Position = UDim2.new(0, 12, 0, 4)
            nameLabel.BackgroundTransparency = 1
            nameLabel.Font = Enum.Font.GothamBold
            nameLabel.TextSize = 13
            nameLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
            nameLabel.TextXAlignment = Enum.TextXAlignment.Left
            nameLabel.Text = plr.DisplayName .. (plr == LocalPlayer and "  (Toi)" or "")
            nameLabel.Parent = row

            local userLabel = Instance.new("TextLabel")
            userLabel.Size = UDim2.new(1, -20, 0, 16)
            userLabel.Position = UDim2.new(0, 12, 0, 24)
            userLabel.BackgroundTransparency = 1
            userLabel.Font = Enum.Font.Gotham
            userLabel.TextSize = 11
            userLabel.TextColor3 = Color3.fromRGB(160, 160, 170)
            userLabel.TextXAlignment = Enum.TextXAlignment.Left
            userLabel.Text = "@" .. plr.Name
            userLabel.Parent = row
        end
    end

    refresh()

    ltrack(Players.PlayerAdded:Connect(refresh))
    ltrack(Players.PlayerRemoving:Connect(function()
        task.defer(refresh)
    end))

    return {
        TogglePause = function() end,
        Stop = function()
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

--============ Navigation du hub ============--

--============ Jeu 5 : Tennis (1v1 vs IA) ============--

local function BuildTennis(gameArea, deps)
    local FIELD_W, FIELD_H = WINDOW_WIDTH, 640
    local NET_Y = FIELD_H / 2
    local PLAYER_BASELINE_Y, AI_BASELINE_Y = FIELD_H - 20, 20
    local PLAYER_R, AI_R, BALL_R = 14, 14, 7
    local MOVE_SPEED, AI_SPEED = 170, 148
    local HIT_RADIUS = PLAYER_R + BALL_R + 12
    local SHOT_SPEED = 320
    local AI_MISS_CHANCE = 0.14

    local localConnections = {}
    local function ltrack(conn)
        table.insert(localConnections, conn)
        return conn
    end

    gameArea.BackgroundTransparency = 0
    gameArea.BackgroundColor3 = Color3.fromRGB(32, 96, 148)

    local NET_HEIGHT = 18

    local netBand = Instance.new("Frame")
    netBand.Size = UDim2.new(1, 0, 0, NET_HEIGHT)
    netBand.Position = UDim2.new(0, 0, 0, NET_Y - NET_HEIGHT / 2)
    netBand.BackgroundColor3 = Color3.fromRGB(12, 16, 20)
    netBand.BackgroundTransparency = 0.5
    netBand.BorderSizePixel = 0
    netBand.ClipsDescendants = true
    netBand.ZIndex = 1
    netBand.Parent = gameArea

    local netTape = Instance.new("Frame")
    netTape.Size = UDim2.new(1, 0, 0, 3)
    netTape.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    netTape.BorderSizePixel = 0
    netTape.ZIndex = 2
    netTape.Parent = netBand

    for x = 0, FIELD_W, 9 do
        local mesh = Instance.new("Frame")
        mesh.Size = UDim2.new(0, 1, 1, -3)
        mesh.Position = UDim2.new(0, x, 0, 3)
        mesh.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        mesh.BackgroundTransparency = 0.35
        mesh.BorderSizePixel = 0
        mesh.ZIndex = 2
        mesh.Parent = netBand
    end

    local meshRow = Instance.new("Frame")
    meshRow.Size = UDim2.new(1, 0, 0, 1)
    meshRow.Position = UDim2.new(0, 0, 1, -7)
    meshRow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    meshRow.BackgroundTransparency = 0.45
    meshRow.BorderSizePixel = 0
    meshRow.ZIndex = 2
    meshRow.Parent = netBand

    local function netPost(x)
        local post = Instance.new("Frame")
        post.Size = UDim2.new(0, 4, 0, NET_HEIGHT + 10)
        post.AnchorPoint = Vector2.new(0.5, 0.5)
        post.Position = UDim2.new(0, x, 0, NET_Y)
        post.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
        post.BorderSizePixel = 0
        post.ZIndex = 3
        post.Parent = gameArea
    end
    netPost(6)
    netPost(FIELD_W - 6)

    local function baseline(y)
        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, -20, 0, 2)
        line.Position = UDim2.new(0, 10, 0, y)
        line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        line.BackgroundTransparency = 0.4
        line.BorderSizePixel = 0
        line.ZIndex = 1
        line.Parent = gameArea
    end
    baseline(PLAYER_BASELINE_Y)
    baseline(AI_BASELINE_Y)

    local function buildRacket(color)
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0, 22, 0, 34)
        container.AnchorPoint = Vector2.new(0.5, 0.5)
        container.BackgroundTransparency = 1
        container.ZIndex = 5

        local head = Instance.new("Frame")
        head.Size = UDim2.new(0, 22, 0, 22)
        head.Position = UDim2.new(0.5, -11, 0, 0)
        head.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
        head.BackgroundTransparency = 0.2
        head.BorderSizePixel = 0
        head.ZIndex = 5
        head.Parent = container
        corner(head, UDim.new(1, 0))
        local headStroke = Instance.new("UIStroke", head)
        headStroke.Color = color
        headStroke.Thickness = 3
        headStroke.Transparency = 0

        local throat = Instance.new("Frame")
        throat.Size = UDim2.new(0, 4, 0, 6)
        throat.Position = UDim2.new(0.5, -2, 0, 20)
        throat.BackgroundColor3 = color
        throat.BorderSizePixel = 0
        throat.ZIndex = 5
        throat.Parent = container

        local handle = Instance.new("Frame")
        handle.Size = UDim2.new(0, 6, 0, 12)
        handle.Position = UDim2.new(0.5, -3, 0, 25)
        handle.BackgroundColor3 = color
        handle.BorderSizePixel = 0
        handle.ZIndex = 5
        handle.Parent = container
        corner(handle, UDim.new(0, 2))

        return container
    end

    local aiChar = buildRacket(Color3.fromRGB(230, 90, 90))
    aiChar.Parent = gameArea

    local playerChar = buildRacket(Color3.fromRGB(90, 200, 230))
    playerChar.Parent = gameArea

    local ball = Instance.new("Frame")
    ball.Size = UDim2.new(0, BALL_R * 2, 0, BALL_R * 2)
    ball.AnchorPoint = Vector2.new(0.5, 0.5)
    ball.BackgroundColor3 = Color3.fromRGB(220, 255, 90)
    ball.BorderSizePixel = 0
    ball.ZIndex = 6
    ball.Parent = gameArea
    corner(ball, UDim.new(1, 0))

    local scoreLabel = Instance.new("TextLabel")
    scoreLabel.BackgroundTransparency = 1
    scoreLabel.Position = UDim2.new(0.5, -90, 0, 12)
    scoreLabel.Size = UDim2.new(0, 180, 0, 40)
    scoreLabel.Font = Enum.Font.GothamBold
    scoreLabel.TextSize = 22
    scoreLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    scoreLabel.TextStrokeTransparency = 0
    scoreLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
    scoreLabel.Text = "0 - 0"
    scoreLabel.ZIndex = 20
    scoreLabel.Parent = gameArea

    local bestBadge = Instance.new("TextLabel")
    bestBadge.BackgroundTransparency = 1
    bestBadge.Position = UDim2.new(0.5, -80, 0, 44)
    bestBadge.Size = UDim2.new(0, 160, 0, 20)
    bestBadge.Font = Enum.Font.GothamBold
    bestBadge.TextSize = 13
    bestBadge.TextColor3 = Color3.fromRGB(255, 215, 0)
    bestBadge.TextStrokeTransparency = 0.4
    bestBadge.Text = "Meilleur : " .. tostring(deps.bestScore)
    bestBadge.ZIndex = 20
    bestBadge.Parent = gameArea

    local startScreen, startCard = createOverlay(gameArea, 0.15)
    addTitle(startCard, "TENNIS", 1)
    local startSubtitle = Instance.new("TextLabel")
    startSubtitle.BackgroundTransparency = 1
    startSubtitle.Size = UDim2.new(1, -30, 0, 66)
    startSubtitle.Font = Enum.Font.Gotham
    startSubtitle.TextSize = 13
    startSubtitle.TextWrapped = true
    startSubtitle.TextColor3 = Color3.fromRGB(90, 90, 90)
    startSubtitle.Text = "Fleches/ZQSD pour bouger\nLa balle repart toute seule\nquand elle touche ta raquette"
    startSubtitle.LayoutOrder = 2
    startSubtitle.ZIndex = 32
    startSubtitle.Parent = startCard
    local startBtn = addButton(startCard, "Jouer", 3)

    local gameOverScreen, gameOverCard = createOverlay(gameArea, 0.15)
    gameOverScreen.Visible = false
    local resultTitle = addTitle(gameOverCard, "Resultat", 1)
    local scoreRow = Instance.new("Frame")
    scoreRow.BackgroundTransparency = 1
    scoreRow.Size = UDim2.new(1, -20, 0, 50)
    scoreRow.LayoutOrder = 2
    scoreRow.ZIndex = 32
    scoreRow.Parent = gameOverCard
    local rowLayout = Instance.new("UIListLayout")
    rowLayout.FillDirection = Enum.FillDirection.Horizontal
    rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    rowLayout.Padding = UDim.new(0, 30)
    rowLayout.Parent = scoreRow

    local finalScoreLabel = scoreStat(scoreRow, "Points")
    local bestScoreLabel = scoreStat(scoreRow, "Meilleur")
    local restartBtn = addButton(gameOverCard, "Rejouer", 3)

    local pauseScreen, pauseCard = createOverlay(gameArea, 0.35)
    pauseScreen.Visible = false
    addTitle(pauseCard, "Pause", 1)
    local resumeBtn = addButton(pauseCard, "Reprendre", 2)

    local gameState = "start" -- start | playing | paused | gameover
    local playerX, playerY = FIELD_W / 2, FIELD_H - 80
    local aiX, aiY = FIELD_W / 2, 80
    local ballX, ballY = FIELD_W / 2, FIELD_H - 80
    local ballVX, ballVY = 0, 0
    local facingX, facingY = 0, -1
    local ballOwner = "player" -- "player" | "ai" | "dead" (already responded, waiting to cross a baseline)
    local playerPoints, aiPoints = 0, 0
    local bestScore = deps.bestScore

    local function clampPlayer(x, y)
        return math.clamp(x, PLAYER_R, FIELD_W - PLAYER_R), math.clamp(y, NET_Y + PLAYER_R, FIELD_H - PLAYER_R)
    end

    local function clampAI(x, y)
        return math.clamp(x, AI_R, FIELD_W - AI_R), math.clamp(y, AI_R, NET_Y - AI_R)
    end

    local function scoreText()
        if playerPoints >= 3 and aiPoints >= 3 then
            if playerPoints == aiPoints then
                return "Egalite"
            elseif playerPoints > aiPoints then
                return "Avantage Toi"
            else
                return "Avantage IA"
            end
        end
        local labels = { [0] = "0", [1] = "15", [2] = "30", [3] = "40" }
        return (labels[math.min(playerPoints, 3)] or "40") .. " - " .. (labels[math.min(aiPoints, 3)] or "40")
    end

    local function resetRally()
        playerX, playerY = FIELD_W / 2, FIELD_H - 80
        aiX, aiY = FIELD_W / 2, 80
        ballX, ballY = playerX, playerY - 20
        ballVX, ballVY = math.random(-60, 60), -SHOT_SPEED * 0.85
        ballOwner = "ai"
    end

    local function startGame()
        startScreen.Visible = false
        gameOverScreen.Visible = false
        pauseScreen.Visible = false
        playerPoints, aiPoints = 0, 0
        scoreLabel.Text = scoreText()
        resetRally()
        gameState = "playing"
    end

    local function endMatch(playerWon)
        if gameState ~= "playing" then return end
        gameState = "gameover"
        playSound("hit")
        if playerPoints > bestScore then
            bestScore = playerPoints
            bestBadge.Text = "Meilleur : " .. tostring(bestScore)
            deps.reportBest(bestScore)
        end
        resultTitle.Text = playerWon and "Victoire !" or "Defaite"
        finalScoreLabel.Text = playerPoints .. " - " .. aiPoints
        bestScoreLabel.Text = tostring(bestScore)
        gameOverScreen.Visible = true
    end

    local function checkGameWon()
        if playerPoints >= 4 and playerPoints - aiPoints >= 2 then
            endMatch(true)
        elseif aiPoints >= 4 and aiPoints - playerPoints >= 2 then
            endMatch(false)
        end
    end

    local function awardPoint(who)
        if gameState ~= "playing" then return end
        if who == "player" then
            playerPoints += 1
            playSound("score")
        else
            aiPoints += 1
            playSound("hit")
        end
        scoreLabel.Text = scoreText()
        checkGameWon()
        if gameState == "playing" then
            resetRally()
        end
    end

    local function setPaused(paused)
        if paused and gameState == "playing" then
            gameState = "paused"
            pauseScreen.Visible = true
            deps.onPauseChanged(true)
        elseif not paused and gameState == "paused" then
            gameState = "playing"
            pauseScreen.Visible = false
            deps.onPauseChanged(false)
        end
    end

    local function togglePause()
        setPaused(gameState ~= "paused")
    end

    ltrack(startBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(restartBtn.MouseButton1Click:Connect(function()
        playSound("click")
        startGame()
    end))
    ltrack(resumeBtn.MouseButton1Click:Connect(function()
        playSound("click")
        togglePause()
    end))

    local heldUp, heldDown, heldLeft, heldRight = false, false, false, false
    ltrack(UIS.InputBegan:Connect(function(input, processed)
        if processed then return end
        local key = input.KeyCode
        if key == Enum.KeyCode.Up or key == Enum.KeyCode.W then
            heldUp = true
        elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S then
            heldDown = true
        elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.A then
            heldLeft = true
        elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.D then
            heldRight = true
        elseif key == Enum.KeyCode.Space then
            if gameState == "gameover" then
                startGame()
            end
        elseif key == Enum.KeyCode.Escape then
            togglePause()
        end
    end))
    ltrack(UIS.InputEnded:Connect(function(input)
        local key = input.KeyCode
        if key == Enum.KeyCode.Up or key == Enum.KeyCode.W then
            heldUp = false
        elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S then
            heldDown = false
        elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.A then
            heldLeft = false
        elseif key == Enum.KeyCode.Right or key == Enum.KeyCode.D then
            heldRight = false
        end
    end))

    ltrack(RunService.Heartbeat:Connect(function(dt)
        if gameState ~= "playing" then return end

        local moveX = (heldRight and 1 or 0) - (heldLeft and 1 or 0)
        local moveY = (heldDown and 1 or 0) - (heldUp and 1 or 0)
        if moveX ~= 0 or moveY ~= 0 then
            local len = math.sqrt(moveX * moveX + moveY * moveY)
            moveX, moveY = moveX / len, moveY / len
            facingX, facingY = moveX, moveY
            playerX = playerX + moveX * MOVE_SPEED * dt
            playerY = playerY + moveY * MOVE_SPEED * dt
            playerX, playerY = clampPlayer(playerX, playerY)
        end
        playerChar.Position = UDim2.new(0, playerX, 0, playerY)

        local aiTargetX = math.clamp(ballX, AI_R, FIELD_W - AI_R)
        local aiTargetY
        if ballY < NET_Y then
            aiTargetY = math.clamp(ballY, AI_R, NET_Y - AI_R)
        else
            aiTargetY = AI_BASELINE_Y + 50
        end
        local adx, ady = aiTargetX - aiX, aiTargetY - aiY
        local alen = math.sqrt(adx * adx + ady * ady)
        if alen > 2 then
            aiX = aiX + (adx / alen) * AI_SPEED * dt
            aiY = aiY + (ady / alen) * AI_SPEED * dt
            aiX, aiY = clampAI(aiX, aiY)
        end
        aiChar.Position = UDim2.new(0, aiX, 0, aiY)

        ballX = ballX + ballVX * dt
        ballY = ballY + ballVY * dt

        if ballX - BALL_R < 0 then
            ballX = BALL_R
            ballVX = -ballVX
        elseif ballX + BALL_R > FIELD_W then
            ballX = FIELD_W - BALL_R
            ballVX = -ballVX
        end

        if ballOwner == "ai" then
            local dx, dy = ballX - aiX, ballY - aiY
            if math.sqrt(dx * dx + dy * dy) <= HIT_RADIUS then
                if math.random() < AI_MISS_CHANCE then
                    ballOwner = "dead"
                else
                    local targetX = FIELD_W / 2 + math.random(-70, 70)
                    local ddx, ddy = targetX - ballX, (PLAYER_BASELINE_Y - 30) - ballY
                    local len = math.sqrt(ddx * ddx + ddy * ddy)
                    if len < 1 then len = 1 end
                    ballVX, ballVY = (ddx / len) * SHOT_SPEED, (ddy / len) * SHOT_SPEED
                    ballOwner = "player"
                    playSound("flap")
                end
            end
        elseif ballOwner == "player" then
            local dx, dy = ballX - playerX, ballY - playerY
            if math.sqrt(dx * dx + dy * dy) <= HIT_RADIUS then
                local dirX, dirY = facingX, facingY
                if dirY > -0.2 then
                    dirY = -0.7
                    local len = math.sqrt(dirX * dirX + dirY * dirY)
                    dirX, dirY = dirX / len, dirY / len
                end
                ballVX, ballVY = dirX * SHOT_SPEED, dirY * SHOT_SPEED
                ballOwner = "ai"
                playSound("flap")
            end
        end

        if ballY + BALL_R < AI_BASELINE_Y then
            awardPoint("player")
        elseif ballY - BALL_R > PLAYER_BASELINE_Y then
            awardPoint("ai")
        end

        if gameState == "playing" then
            ball.Position = UDim2.new(0, ballX, 0, ballY)
        end
    end))

    return {
        TogglePause = function() togglePause() end,
        Stop = function()
            for _, c in ipairs(localConnections) do
                if c.Connected then c:Disconnect() end
            end
        end,
    }
end

local GAMES = {
    FlappyBird = { Name = "FLAPPY BIRD", Height = 640, Build = BuildFlappyBird },
    Snake = { Name = "SNAKE", Height = 360, Build = BuildSnake },
    DinoRunner = { Name = "DINO RUNNER", Height = 640, Build = BuildDinoRunner },
    Pong = { Name = "PONG", Height = 640, Build = BuildPong },
    Tennis = { Name = "TENNIS", Height = 640, Build = BuildTennis },
    Calculator = { Name = "CALCULATRICE", Height = 500, Build = BuildCalculator, HasPause = false },
    Notes = { Name = "NOTES", Height = 520, Build = BuildNotes, HasPause = false },
    Music = { Name = "MUSIQUE", Height = 640, Build = BuildMusic },
    Settings = { Name = "REGLAGES", Height = 640, Build = BuildSettings, HasPause = false },
    Chrono = { Name = "CHRONO", Height = 640, Build = BuildChrono, HasPause = false },
    Players = { Name = "JOUEURS", Height = 640, Build = BuildPlayers, HasPause = false },
}

openGame = function(id)
    if currentController then
        currentController.Stop()
        currentController = nil
    end
    if currentGameFrame then
        currentGameFrame:Destroy()
        currentGameFrame = nil
    end

    local info = GAMES[id]
    menuFrame.Visible = false
    homeIndicator.Visible = true
    homeIndicatorBacking.Visible = true
    pauseBtn.Visible = info.HasPause ~= false
    pauseBtn.Text = PAUSE_ICON

    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    frame.Size = UDim2.new(0, WINDOW_WIDTH, 0, PHONE_CONTENT_HEIGHT)
    frame.Position = UDim2.new(0, 0, 0, 0)
    frame.Parent = contentArea
    corner(frame, UDim.new(0, 38))
    currentGameFrame = frame
    currentGameId = id

    resizeWindow(info.Height)

    local deps = {
        bestScore = bestScores[id],
        reportBest = function(score) reportBest(id, score) end,
        onPauseChanged = function(isPaused)
            pauseBtn.Text = isPaused and PLAY_ICON or PAUSE_ICON
        end,
    }
    currentController = info.Build(frame, deps)
end

showMenu = function()
    if currentController then
        currentController.Stop()
        currentController = nil
    end
    if currentGameFrame then
        currentGameFrame:Destroy()
        currentGameFrame = nil
    end
    currentGameId = nil

    homeIndicator.Visible = false
    homeIndicatorBacking.Visible = false
    pauseBtn.Visible = false
    menuFrame.Visible = true

    resizeWindow(MENU_HEIGHT)
end

track(flappyCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("FlappyBird")
end))
track(snakeCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("Snake")
end))
track(dinoCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("DinoRunner")
end))
track(pongCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("Pong")
end))
track(tennisCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("Tennis")
end))
track(calcCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("Calculator")
end))
track(notesCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("Notes")
end))
track(musicCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("Music")
end))
track(settingsCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("Settings")
end))
track(chronoCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("Chrono")
end))
track(playersCard.MouseButton1Click:Connect(function()
    playSound("click")
    openGame("Players")
end))

showMenu()

end)

if not buildOk then
    warn("[Phone] Erreur au chargement: " .. tostring(buildErr))
end
end
end)
