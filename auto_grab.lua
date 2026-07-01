if not game:IsLoaded() then game.Loaded:Wait() end

-- ============================================================
-- SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- SCALE + MOBILE
-- ============================================================
local IS_MOBILE         = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local mobileScale       = IS_MOBILE and 0.6 or 1
local mobileButtonScale = IS_MOBILE and 1.3 or 1

-- ============================================================
-- THEME
-- ============================================================
local Theme = {
    Background       = Color3.fromRGB(10, 18, 14),
    Surface          = Color3.fromRGB(12, 30, 22),
    SurfaceHighlight = Color3.fromRGB(18, 50, 36),
    Accent1          = Color3.fromRGB(80, 210, 120),
    Accent2          = Color3.fromRGB(55, 160, 90),
    TextPrimary      = Color3.fromRGB(225, 255, 235),
    TextSecondary    = Color3.fromRGB(140, 200, 165),
}

-- ============================================================
-- CONFIG
-- ============================================================
local Config = {
    InstantSteal       = false,
    StealNearest       = false,
    StealHighest       = true,
    StealPriority      = false,
    AutoDestroyTurrets = false,
    AutoKickOnSteal    = false,
    AutoGrabOwnBase    = false,
    UILocked           = false,
    Positions = {
        TargetControls = {X = 0.26, Y = 0.35, OffsetX = 15, OffsetY = 0},
    },
}

-- ============================================================
-- SHARED STATE
-- ============================================================
local SharedState = {
    MobileScaleObjects = {},
    AllAnimalsCache    = {},
    ListNeedsRedraw    = false,
}

-- ============================================================
-- STATE VARIABLES
-- ============================================================
local instantStealEnabled  = false
local instantStealReady    = false
local instantStealDidInit  = false
local selectedTargetIndex  = 1
local selectedTargetUID    = nil
local activeProgressTween  = nil
local currentStealTargetUID= nil

local stealNearestEnabled  = false
local stealHighestEnabled  = false
local stealPriorityEnabled = false

local allAnimalsCache   = {}
local lastAnimalData    = {}
local PromptMemoryCache = {}
local InternalStealCache= {}

local function syncAutoStealEnabledFromModes()
    -- no-op: we only use instantSteal
end

-- ============================================================
-- GAME MODULES (async require)
-- ============================================================
local Synchronizer, AnimalsData, AnimalsShared, NumberUtils

task.spawn(function()
    local ok, pkgs = pcall(function()
        local Packages = ReplicatedStorage:WaitForChild("Packages", 15)
        local Datas    = ReplicatedStorage:WaitForChild("Datas",    15)
        local Shared   = ReplicatedStorage:WaitForChild("Shared",   15)
        local Utils    = ReplicatedStorage:WaitForChild("Utils",    15)
        return
            require(Packages:WaitForChild("Synchronizer", 10)),
            require(Datas:WaitForChild("Animals",         10)),
            require(Shared:WaitForChild("Animals",        10)),
            require(Utils:WaitForChild("NumberUtils",     10))
    end)
    if ok then
        Synchronizer, AnimalsData, AnimalsShared, NumberUtils = pkgs, select(2, pkgs)
    end
end)

-- ============================================================
-- HELPER: MakeDraggable
-- ============================================================
local function MakeDraggable(handle, target, saveKey)
    local dragging, dragInput, dragStart, startPos
    handle.InputBegan:Connect(function(input)
        if Config.UILocked then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if saveKey then
                        Config.Positions[saveKey] = {
                            X = target.Position.X.Scale, Y = target.Position.Y.Scale,
                            OffsetX = target.Position.X.Offset, OffsetY = target.Position.Y.Offset,
                        }
                    end
                end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function ApplyViewportUIScale(targetFrame, _w, _h, minScale, maxScale)
    if not targetFrame or not IS_MOBILE then return end
    local existing = targetFrame:FindFirstChildOfClass("UIScale")
    if existing then existing:Destroy() end
    local sc = Instance.new("UIScale")
    sc.Scale  = math.clamp(0.5, minScale or 0.45, maxScale or 1)
    sc.Parent = targetFrame
    SharedState.MobileScaleObjects[targetFrame] = sc
end

local function AddMobileMinimize(frame, labelText)
    if not IS_MOBILE or not frame or not frame.Parent then return end
    local guiParent = frame.Parent
    local header    = frame:FindFirstChildWhichIsA("Frame")
    if not header then return end
    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Size = UDim2.new(0,26,0,26); minimizeBtn.Position = UDim2.new(1,-30,0,6)
    minimizeBtn.BackgroundColor3 = Theme.SurfaceHighlight; minimizeBtn.Text = "-"
    minimizeBtn.Font = Enum.Font.GothamBlack; minimizeBtn.TextSize = 18
    minimizeBtn.TextColor3 = Theme.TextPrimary; minimizeBtn.AutoButtonColor = false
    minimizeBtn.Parent = header
    Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0,8)
    local restoreBtn = Instance.new("TextButton")
    restoreBtn.Size = UDim2.new(0,110,0,34); restoreBtn.Position = UDim2.new(0,10,1,-44)
    restoreBtn.BackgroundColor3 = Theme.SurfaceHighlight; restoreBtn.Text = labelText or "OPEN"
    restoreBtn.Font = Enum.Font.GothamBold; restoreBtn.TextSize = 12
    restoreBtn.TextColor3 = Theme.TextPrimary; restoreBtn.Visible = false
    restoreBtn.AutoButtonColor = false; restoreBtn.Parent = guiParent
    Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0,10)
    MakeDraggable(restoreBtn, restoreBtn)
    minimizeBtn.MouseButton1Click:Connect(function() frame.Visible=false; restoreBtn.Visible=true end)
    restoreBtn.MouseButton1Click:Connect(function() frame.Visible=true; restoreBtn.Visible=false end)
end

-- ============================================================
-- ANIMAL LOGIC
-- ============================================================
local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    if not Synchronizer then return false end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    local ok, channel = pcall(function() return Synchronizer:Get(plot.Name) end)
    if not ok or not channel then return false end
    local owner = channel:Get("Owner")
    if owner then
        if typeof(owner) == "Instance" and owner:IsA("Player") then return owner.UserId == LocalPlayer.UserId
        elseif typeof(owner) == "table" and owner.UserId then return owner.UserId == LocalPlayer.UserId
        elseif typeof(owner) == "Instance" then return owner == LocalPlayer end
    end
    return false
end

local function findAdorneeGlobal(animalData)
    if not animalData then return nil end
    local plots = Workspace:FindFirstChild("Plots")
    local plot  = plots and plots:FindFirstChild(animalData.plot)
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

local function get_all_pets()
    local out = {}
    for _, a in ipairs(allAnimalsCache) do
        if a.genValue >= 1 and not isMyBaseAnimal(a) then
            table.insert(out, {petName=a.name, mpsText=a.genText, mpsValue=a.genValue,
                owner=a.owner, plot=a.plot, slot=a.slot, uid=a.uid, mutation=a.mutation, animalData=a})
        end
    end
    return out
end

-- ============================================================
-- PROXIMITY PROMPT FINDER
-- ============================================================
local function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end
    local cp = PromptMemoryCache[animalData.uid]
    if cp and cp.Parent then return cp end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local plot = plots:FindFirstChild(animalData.plot); if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums"); if not podiums then return nil end

    local ch = Synchronizer and pcall(function() return Synchronizer:Get(plot.Name) end) and Synchronizer:Get(plot.Name)
    if not ch then
        local podium = podiums:FindFirstChild(animalData.slot)
        if podium then
            local spawn = podium:FindFirstChild("Base") and podium.Base:FindFirstChild("Spawn")
            if spawn then
                local attach = spawn:FindFirstChild("PromptAttachment")
                if attach then
                    for _, p in ipairs(attach:GetChildren()) do
                        if p:IsA("ProximityPrompt") then PromptMemoryCache[animalData.uid]=p; return p end
                    end
                end
            end
        end
        return nil
    end

    local al = ch:Get("AnimalList"); if not al then return nil end
    local brainrotName = animalData.name and animalData.name:lower() or ""
    local targetSlot   = animalData.slot
    local foundPodium  = nil
    for slot, ad in pairs(al) do
        if type(ad)=="table" and tostring(slot)==targetSlot then
            local aInfo = AnimalsData and AnimalsData[ad.Index]
            if aInfo and (aInfo.DisplayName or ad.Index):lower()==brainrotName then
                foundPodium = podiums:FindFirstChild(tostring(slot)); break
            end
        end
    end
    if not foundPodium then foundPodium = podiums:FindFirstChild(animalData.slot) end
    if foundPodium then
        local spawn = foundPodium:FindFirstChild("Base") and foundPodium.Base:FindFirstChild("Spawn")
        if spawn then
            local attach = spawn:FindFirstChild("PromptAttachment")
            if attach then
                for _, p in ipairs(attach:GetChildren()) do
                    if p:IsA("ProximityPrompt") and p.Enabled then
                        PromptMemoryCache[animalData.uid]=p; return p
                    end
                end
            end
            local slotX, slotZ = spawn.Position.X, spawn.Position.Z
            local nearest, minD = nil, math.huge
            for _, desc in pairs(plot:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and desc.Enabled then
                    local part = desc.Parent
                    local pos  = part and part:IsA("BasePart") and part.Position
                              or (part and part:IsA("Attachment") and part.Parent and part.Parent:IsA("BasePart") and part.Parent.Position)
                    if pos then
                        local hd = math.sqrt((pos.X-slotX)^2+(pos.Z-slotZ)^2)
                        if hd < 5 and pos.Y > spawn.Position.Y then
                            local yd = pos.Y - spawn.Position.Y
                            if yd < minD then minD=yd; nearest=desc end
                        end
                    end
                end
            end
            if nearest then PromptMemoryCache[animalData.uid]=nearest; return nearest end
        end
    end
    return nil
end

-- ============================================================
-- STEAL CALLBACKS (uses exploit getconnections)
-- ============================================================
local STEAL_DURATION = 0.4

local function buildStealCallbacks(prompt)
    if InternalStealCache[prompt] then return end
    local data = {holdCallbacks={}, triggerCallbacks={}, holdEndCallbacks={}, ready=true}
    local ok1, c1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 and type(c1)=="table" then
        for _, c in ipairs(c1) do if type(c.Function)=="function" then table.insert(data.holdCallbacks, c.Function) end end
    end
    local ok2, c2 = pcall(getconnections, prompt.Triggered)
    if ok2 and type(c2)=="table" then
        for _, c in ipairs(c2) do if type(c.Function)=="function" then table.insert(data.triggerCallbacks, c.Function) end end
    end
    local ok3, c3 = pcall(getconnections, prompt.PromptButtonHoldEnded)
    if ok3 and type(c3)=="table" then
        for _, c in ipairs(c3) do if type(c.Function)=="function" then table.insert(data.holdEndCallbacks, c.Function) end end
    end
    if #data.holdCallbacks>0 or #data.triggerCallbacks>0 or #data.holdEndCallbacks>0 then
        InternalStealCache[prompt] = data
    end
end

local function runCallbackList(list)
    for _, fn in ipairs(list) do task.spawn(fn) end
end

-- progressBarFill declared later after HUD build; forward reference via upvalue table
local barRef = {}

local function executeInternalStealAsync(prompt, animalUID)
    local data = InternalStealCache[prompt]
    if not data or not data.ready then return false end
    data.ready = false
    task.spawn(function()
        local fill = barRef[1]
        if currentStealTargetUID ~= animalUID then
            if activeProgressTween then activeProgressTween:Cancel() end
            if fill then fill.Size = UDim2.new(0,0,1,0) end
            currentStealTargetUID = animalUID
        end
        if #data.holdCallbacks > 0 then runCallbackList(data.holdCallbacks) end
        if fill then
            fill.Size = UDim2.new(0,0,1,0)
            fill.BackgroundTransparency = 0
            activeProgressTween = TweenService:Create(fill, TweenInfo.new(STEAL_DURATION, Enum.EasingStyle.Linear), {Size=UDim2.new(1,0,1,0)})
            activeProgressTween:Play()
            activeProgressTween.Completed:Wait()
        else
            task.wait(STEAL_DURATION)
        end
        if currentStealTargetUID == animalUID and #data.triggerCallbacks > 0 then
            runCallbackList(data.triggerCallbacks)
        end
        data.ready = true
    end)
    return true
end

local function attemptSteal(prompt, animalUID)
    if not prompt or not prompt.Parent then return false end
    buildStealCallbacks(prompt)
    if not InternalStealCache[prompt] then return false end
    local fill = barRef[1]
    if currentStealTargetUID ~= animalUID then
        if activeProgressTween then activeProgressTween:Cancel(); activeProgressTween=nil end
        if fill then fill.Size = UDim2.new(0,0,1,0) end
    end
    return executeInternalStealAsync(prompt, animalUID)
end

-- ============================================================
-- INSTANT STEAL
-- ============================================================
local INSTANT_STEAL_RADIUS = 60

local function isMyPlot_Instant(plotName)
    local plots = Workspace:FindFirstChild("Plots"); if not plots then return false end
    local plot  = plots:FindFirstChild(plotName);  if not plot  then return false end
    local sign  = plot:FindFirstChild("PlotSign"); if not sign  then return false end
    local yb    = sign:FindFirstChild("YourBase")
    return yb and yb:IsA("BillboardGui") and yb.Enabled
end

local function findNearestPrompt_Instant()
    local hrp   = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, math.huge, nil end
    local plots = Workspace:FindFirstChild("Plots"); if not plots then return nil, math.huge, nil end
    local bestPrompt, bestDist, bestName = nil, math.huge, nil
    for _, plot in ipairs(plots:GetChildren()) do
        if isMyPlot_Instant(plot.Name) then continue end
        local plotDist = math.huge
        pcall(function() plotDist = (plot:GetPivot().Position - hrp.Position).Magnitude end)
        if plotDist > INSTANT_STEAL_RADIUS + 40 then continue end
        local podiums = plot:FindFirstChild("AnimalPodiums"); if not podiums then continue end
        for _, pod in ipairs(podiums:GetChildren()) do
            local base  = pod:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn"); if not spawn then continue end
            local dist  = (spawn.Position - hrp.Position).Magnitude
            if dist > INSTANT_STEAL_RADIUS or dist >= bestDist then continue end
            local att    = spawn:FindFirstChild("PromptAttachment"); if not att then continue end
            local prompt = att:FindFirstChildOfClass("ProximityPrompt")
            if prompt and prompt.Parent and prompt.Enabled then
                bestPrompt=prompt; bestDist=dist; bestName=pod.Name
            end
        end
    end
    return bestPrompt, bestDist, bestName
end

local function executeInstantSteal(prompt)
    if not prompt or not prompt.Parent then return end
    pcall(function() fireproximityprompt(prompt, 0) end)
end

-- ============================================================
-- setInstantSteal
-- ============================================================
local updateUI  -- forward ref
local function setInstantSteal(state)
    instantStealEnabled = state
    if not state then instantStealReady=false; instantStealDidInit=false end
    Config.InstantSteal = state
    _G.NEAREST_INSTANT_MODE = (stealNearestEnabled and state)
    if updateUI then updateUI() end
end
_G._hazeSetInstantSteal = setInstantSteal

-- ============================================================
-- PROGRESS BAR HUD
-- ============================================================
local existingHud = PlayerGui:FindFirstChild("AutoStealCurrentTargetHUD")
if existingHud then existingHud:Destroy() end

local targetHudGui = Instance.new("ScreenGui")
targetHudGui.Name="AutoStealCurrentTargetHUD"; targetHudGui.ResetOnSpawn=false
targetHudGui.IgnoreGuiInset=true; targetHudGui.DisplayOrder=998
targetHudGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; targetHudGui.Parent=PlayerGui

local STEALBAR = {
    PANEL  = Color3.fromRGB(10, 18, 15),
    TEXT   = Color3.fromRGB(225, 255, 235),
    STROKE = Color3.fromRGB(65, 180, 105),
    GLOW   = Color3.fromRGB(140, 240, 175),
    TRACK  = Color3.fromRGB(35, 14, 25),
    TRACK2 = Color3.fromRGB(45, 18, 32),
    FILL1  = Color3.fromRGB(65, 180, 105),
    FILL2  = Color3.fromRGB(220, 100, 150),
}

local targetHud = Instance.new("Frame", targetHudGui)
targetHud.Name="CurrentTargetHUD"; targetHud.AnchorPoint=Vector2.new(0.5,1)
targetHud.Size=UDim2.new(0,230*mobileScale,0,46*mobileScale)
targetHud.Position=UDim2.new(0.5,0,1,-220)
targetHud.BackgroundColor3=STEALBAR.PANEL; targetHud.BackgroundTransparency=0.02
targetHud.BorderSizePixel=0; targetHud.ZIndex=70
Instance.new("UICorner",targetHud).CornerRadius=UDim.new(0,math.floor(12*mobileScale))

local hudStroke=Instance.new("UIStroke",targetHud); hudStroke.Color=STEALBAR.STROKE; hudStroke.Thickness=1; hudStroke.Transparency=0.35
local hudGlow=Instance.new("UIStroke",targetHud); hudGlow.Color=STEALBAR.GLOW; hudGlow.Thickness=3; hudGlow.Transparency=0.84; hudGlow.ApplyStrokeMode=Enum.ApplyStrokeMode.Border

local hudShadow=Instance.new("ImageLabel",targetHud); hudShadow.AnchorPoint=Vector2.new(0.5,0.5)
hudShadow.Position=UDim2.new(0.5,0,0.5,1); hudShadow.Size=UDim2.new(1,20,1,20)
hudShadow.BackgroundTransparency=1; hudShadow.Image="rbxassetid://6014261993"
hudShadow.ImageColor3=Color3.new(0,0,0); hudShadow.ImageTransparency=0.72
hudShadow.ScaleType=Enum.ScaleType.Slice; hudShadow.SliceCenter=Rect.new(49,49,450,450); hudShadow.ZIndex=69

local hudName=Instance.new("TextLabel",targetHud); hudName.Name="TargetName"
hudName.Size=UDim2.new(1,-12,0,13*mobileScale); hudName.Position=UDim2.fromOffset(6*mobileScale,3*mobileScale)
hudName.BackgroundTransparency=1; hudName.Font=Enum.Font.GothamBold; hudName.TextSize=11*mobileScale
hudName.TextColor3=STEALBAR.TEXT; hudName.TextXAlignment=Enum.TextXAlignment.Center
hudName.TextTruncate=Enum.TextTruncate.AtEnd; hudName.ZIndex=72; hudName.Text="No target"

local hudProgressBg=Instance.new("Frame",targetHud); hudProgressBg.Name="ProgressBg"
hudProgressBg.Size=UDim2.new(1,-10*mobileScale,0,18*mobileScale)
hudProgressBg.Position=UDim2.fromOffset(5*mobileScale,18*mobileScale)
hudProgressBg.BackgroundColor3=STEALBAR.TRACK; hudProgressBg.BorderSizePixel=0; hudProgressBg.ZIndex=72
Instance.new("UICorner",hudProgressBg).CornerRadius=UDim.new(0,math.floor(8*mobileScale))
local bgStroke=Instance.new("UIStroke",hudProgressBg); bgStroke.Color=STEALBAR.STROKE; bgStroke.Thickness=1; bgStroke.Transparency=0.55

local hudInnerTrack=Instance.new("Frame",hudProgressBg); hudInnerTrack.Name="InnerTrack"
hudInnerTrack.Size=UDim2.new(1,-2,1,-2); hudInnerTrack.Position=UDim2.fromOffset(1,1)
hudInnerTrack.BackgroundColor3=STEALBAR.TRACK2; hudInnerTrack.BackgroundTransparency=0.15
hudInnerTrack.BorderSizePixel=0; hudInnerTrack.ZIndex=72
Instance.new("UICorner",hudInnerTrack).CornerRadius=UDim.new(0,math.floor(7*mobileScale))

local hudProgressFill=Instance.new("Frame",hudProgressBg); hudProgressFill.Name="ProgressFill"
hudProgressFill.Size=UDim2.new(0,0,1,0); hudProgressFill.BackgroundColor3=STEALBAR.FILL1
hudProgressFill.BorderSizePixel=0; hudProgressFill.ZIndex=73
Instance.new("UICorner",hudProgressFill).CornerRadius=UDim.new(0,math.floor(8*mobileScale))
local fillGrad=Instance.new("UIGradient",hudProgressFill)
fillGrad.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,STEALBAR.FILL1),ColorSequenceKeypoint.new(1,STEALBAR.FILL2)})
local fillStroke=Instance.new("UIStroke",hudProgressFill); fillStroke.Color=Color3.fromRGB(220,228,255); fillStroke.Thickness=1; fillStroke.Transparency=0.45

local hudPercent=Instance.new("TextLabel",hudProgressBg); hudPercent.Name="Percent"
hudPercent.Size=UDim2.new(1,0,1,0); hudPercent.BackgroundTransparency=1
hudPercent.Font=Enum.Font.GothamBold; hudPercent.TextSize=12*mobileScale
hudPercent.TextColor3=STEALBAR.TEXT; hudPercent.TextStrokeTransparency=0.7
hudPercent.TextXAlignment=Enum.TextXAlignment.Center; hudPercent.ZIndex=74; hudPercent.Text="0%"

barRef[1] = hudProgressFill  -- connect to forward reference

-- percent label updater
RunService.Heartbeat:Connect(function()
    local pct = math.clamp(math.floor(hudProgressFill.Size.X.Scale*100+0.5), 0, 100)
    hudPercent.Text = pct.."%"
end)

-- ============================================================
-- TARGET CONTROLS UI
-- ============================================================
local existingTC = PlayerGui:FindFirstChild("AutoStealTargetControls")
if existingTC then existingTC:Destroy() end

local targetControlsGui = Instance.new("ScreenGui")
targetControlsGui.Name="AutoStealTargetControls"; targetControlsGui.ResetOnSpawn=false
targetControlsGui.IgnoreGuiInset=true; targetControlsGui.DisplayOrder=999
targetControlsGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; targetControlsGui.Parent=PlayerGui

local targetControlsFrame = Instance.new("Frame", targetControlsGui)
targetControlsFrame.Name="TargetControlsFrame"; targetControlsFrame.AutomaticSize=Enum.AutomaticSize.Y
targetControlsFrame.Size=UDim2.new(0,240*mobileScale,0,0)
targetControlsFrame.Position=UDim2.new(
    Config.Positions.TargetControls.X or 0.26, Config.Positions.TargetControls.OffsetX or 15,
    Config.Positions.TargetControls.Y or 0.35, Config.Positions.TargetControls.OffsetY or 0)
targetControlsFrame.BackgroundColor3=Color3.fromRGB(15,15,18); targetControlsFrame.BackgroundTransparency=0
targetControlsFrame.BorderSizePixel=0; targetControlsFrame.ClipsDescendants=false; targetControlsFrame.ZIndex=100

ApplyViewportUIScale(targetControlsFrame,300,250,0.45,0.8)
AddMobileMinimize(targetControlsFrame,"TARGET CONTROLS")

local MTC = {
    BG=Color3.fromRGB(15,15,18), SURF=Color3.fromRGB(28,28,32), SURF2=Color3.fromRGB(45,45,50),
    TEXT=Color3.fromRGB(245,245,250), GREEN1=Color3.fromRGB(18,88,58), GREEN2=Color3.fromRGB(21,120,76),
    GREEN_STROKE=Color3.fromRGB(60,185,120), OFF_BG=Color3.fromRGB(35,35,40),
    OFF_TEXT=Color3.fromRGB(140,140,150), AQUA_STROKE=Color3.fromRGB(190,190,200),
}

local function miniRound(obj,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r); c.Parent=obj; return c end
local function miniStroke(obj,col,th,tr) local s=Instance.new("UIStroke"); s.Color=col; s.Thickness=th or 1; s.Transparency=tr or 0; s.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; s.Parent=obj; return s end
local function miniTween(obj,t,props) TweenService:Create(obj,TweenInfo.new(t or 0.2,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),props):Play() end
local function miniGradient(parent,c1,c2,rot) local g=Instance.new("UIGradient"); g.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,c1),ColorSequenceKeypoint.new(1,c2)}); g.Rotation=rot or 0; g.Parent=parent; return g end

miniRound(targetControlsFrame,18); miniStroke(targetControlsFrame,MTC.AQUA_STROKE,1.2,0.40)

local shadow=Instance.new("ImageLabel"); shadow.AnchorPoint=Vector2.new(0.5,0.5)
shadow.Position=UDim2.new(0.5,0,0.5,2); shadow.Size=UDim2.new(1,24,1,24)
shadow.BackgroundTransparency=1; shadow.Image="rbxassetid://6014261993"; shadow.ImageColor3=Color3.new(0,0,0)
shadow.ImageTransparency=0.72; shadow.ScaleType=Enum.ScaleType.Slice; shadow.SliceCenter=Rect.new(49,49,450,450)
shadow.ZIndex=99; shadow.Parent=targetControlsFrame

local header=Instance.new("Frame",targetControlsFrame); header.Size=UDim2.new(1,0,0,44)
header.BackgroundTransparency=1; header.ZIndex=101
MakeDraggable(header,targetControlsFrame,"TargetControls")

local title=Instance.new("TextLabel",header); title.Size=UDim2.new(1,-28,0,24); title.Position=UDim2.new(0,14,0,10)
title.ZIndex=102; title.BackgroundTransparency=1; title.Text="TARGET CONTROLS"
title.Font=Enum.Font.GothamBlack; title.TextSize=18; title.TextColor3=MTC.TEXT; title.TextXAlignment=Enum.TextXAlignment.Center

local titleLine=Instance.new("Frame",targetControlsFrame); titleLine.AnchorPoint=Vector2.new(0.5,0)
titleLine.Position=UDim2.new(0.5,0,0,38); titleLine.Size=UDim2.new(0,124,0,1)
titleLine.BackgroundColor3=Color3.fromRGB(255,255,255); titleLine.BackgroundTransparency=0.15
titleLine.BorderSizePixel=0; titleLine.ZIndex=101

local content=Instance.new("Frame",targetControlsFrame); content.AutomaticSize=Enum.AutomaticSize.Y
content.Size=UDim2.new(1,-20,0,0); content.Position=UDim2.fromOffset(10,48)
content.BackgroundColor3=MTC.SURF; content.BorderSizePixel=0; content.ZIndex=101
miniRound(content,16); miniStroke(content,MTC.AQUA_STROKE,1,0.48)

local btnContainer=Instance.new("Frame",content); btnContainer.AutomaticSize=Enum.AutomaticSize.Y
btnContainer.Size=UDim2.new(1,-10,0,0); btnContainer.Position=UDim2.fromOffset(5,5)
btnContainer.BackgroundTransparency=1; btnContainer.ZIndex=102
local layout=Instance.new("UIListLayout",btnContainer); layout.Padding=UDim.new(0,8); layout.SortOrder=Enum.SortOrder.LayoutOrder

local function createToggleRow(parent, text)
    local row=Instance.new("Frame",parent); row.Name=text:gsub("%s+","").."Row"
    row.Size=UDim2.new(1,0,0,math.floor(36*mobileButtonScale)); row.BackgroundColor3=MTC.SURF2
    row.BackgroundTransparency=0.02; row.BorderSizePixel=0; row.ZIndex=103
    miniRound(row,11); local rowStroke=miniStroke(row,MTC.AQUA_STROKE,1,0.52)
    local label=Instance.new("TextLabel",row); label.BackgroundTransparency=1
    label.Position=UDim2.fromOffset(12,0); label.Size=UDim2.new(1,-100,1,0)
    label.Font=Enum.Font.GothamBold; label.Text=text; label.TextColor3=MTC.TEXT
    label.TextSize=12*mobileButtonScale; label.TextXAlignment=Enum.TextXAlignment.Left; label.ZIndex=104
    local stateBox=Instance.new("TextButton",row); stateBox.Name=text:gsub("%s+","").."Toggle"
    stateBox.AutoButtonColor=false
    stateBox.Size=UDim2.fromOffset(math.floor(72*mobileButtonScale),math.floor(22*mobileButtonScale))
    stateBox.Position=UDim2.new(1,-math.floor(82*mobileButtonScale),0.5,-math.floor(11*mobileButtonScale))
    stateBox.BackgroundColor3=MTC.OFF_BG; stateBox.BorderSizePixel=0; stateBox.Text=""; stateBox.ZIndex=104
    miniRound(stateBox,7); local stateStroke=miniStroke(stateBox,MTC.AQUA_STROKE,1,0.55)
    local stateFill=Instance.new("Frame",stateBox); stateFill.Size=UDim2.new(1,0,1,0)
    stateFill.BackgroundTransparency=1; stateFill.BorderSizePixel=0; stateFill.ZIndex=104
    miniRound(stateFill,7); miniGradient(stateFill,MTC.GREEN1,MTC.GREEN2,0)
    local stateText=Instance.new("TextLabel",stateBox); stateText.BackgroundTransparency=1
    stateText.Size=UDim2.fromScale(1,1); stateText.Font=Enum.Font.GothamBold
    stateText.TextSize=11*mobileButtonScale; stateText.Text="OFF"; stateText.TextColor3=MTC.OFF_TEXT; stateText.ZIndex=105
    row.MouseEnter:Connect(function() miniTween(row,0.14,{BackgroundColor3=Color3.fromRGB(34,39,58)}); miniTween(rowStroke,0.14,{Transparency=0.38}) end)
    row.MouseLeave:Connect(function() miniTween(row,0.14,{BackgroundColor3=MTC.SURF2}); miniTween(rowStroke,0.14,{Transparency=0.52}) end)
    return {row=row,label=label,button=stateBox,knob=stateFill,stateLabel=stateText,stroke=stateStroke,rowStroke=rowStroke}
end

local nearestBtn    = createToggleRow(btnContainer,"Nearest")
local highestBtn    = createToggleRow(btnContainer,"Highest")
local priorityBtn   = createToggleRow(btnContainer,"Priority")
local autoTurretBtn = createToggleRow(btnContainer,"Auto Turret")
local autoKickBtn   = createToggleRow(btnContainer,"Auto Kick")
local instantStealBtn = createToggleRow(btnContainer,"Instant Steal")
local ownBaseBtn    = createToggleRow(btnContainer,"Own Base")

local function paintToggle(ref, isOn)
    if isOn then
        ref.button.BackgroundColor3=MTC.GREEN1; ref.knob.BackgroundTransparency=0
        ref.stateLabel.Text="ON"; ref.stateLabel.TextColor3=Color3.fromRGB(232,255,240)
        ref.stroke.Color=MTC.GREEN_STROKE; ref.stroke.Transparency=0.22
    else
        ref.button.BackgroundColor3=MTC.OFF_BG; ref.knob.BackgroundTransparency=1
        ref.stateLabel.Text="OFF"; ref.stateLabel.TextColor3=MTC.OFF_TEXT
        ref.stroke.Color=MTC.AQUA_STROKE; ref.stroke.Transparency=0.55
    end
    if ref.rowStroke then ref.rowStroke.Transparency=isOn and 0.38 or 0.52 end
end

updateUI = function()
    paintToggle(nearestBtn,    stealNearestEnabled)
    paintToggle(highestBtn,    stealHighestEnabled)
    paintToggle(priorityBtn,   stealPriorityEnabled)
    paintToggle(autoTurretBtn, Config.AutoDestroyTurrets)
    paintToggle(autoKickBtn,   Config.AutoKickOnSteal)
    paintToggle(instantStealBtn, instantStealEnabled)
    paintToggle(ownBaseBtn,    Config.AutoGrabOwnBase)
end

-- visual-only toggles
nearestBtn.button.MouseButton1Click:Connect(function()    stealNearestEnabled=not stealNearestEnabled;    updateUI() end)
highestBtn.button.MouseButton1Click:Connect(function()    stealHighestEnabled=not stealHighestEnabled;    updateUI() end)
priorityBtn.button.MouseButton1Click:Connect(function()   stealPriorityEnabled=not stealPriorityEnabled;  updateUI() end)
autoTurretBtn.button.MouseButton1Click:Connect(function() Config.AutoDestroyTurrets=not Config.AutoDestroyTurrets; updateUI() end)
autoKickBtn.button.MouseButton1Click:Connect(function()   Config.AutoKickOnSteal=not Config.AutoKickOnSteal; updateUI() end)
ownBaseBtn.button.MouseButton1Click:Connect(function()    Config.AutoGrabOwnBase=not Config.AutoGrabOwnBase; updateUI() end)

-- real toggle
instantStealBtn.button.MouseButton1Click:Connect(function()
    setInstantSteal(not instantStealEnabled)
end)

updateUI()

-- ============================================================
-- PLOT SCAN (brainrot cache)
-- ============================================================
local function getAnimalHash(al)
    if not al then return "" end
    local h = ""
    for slot, d in pairs(al) do
        if type(d)=="table" then h=h..tostring(slot)..tostring(d.Index)..tostring(d.Mutation) end
    end
    return h
end

local function scanSinglePlot(plot)
    if not Synchronizer then return end
    pcall(function()
        local ch = Synchronizer:Get(plot.Name); if not ch then return end
        local al    = ch:Get("AnimalList")
        local owner = ch:Get("Owner")
        if not owner or not owner.Name or not Players:FindFirstChild(owner.Name) then
            lastAnimalData[plot.Name]=nil
            for i=#allAnimalsCache,1,-1 do if allAnimalsCache[i].plot==plot.Name then table.remove(allAnimalsCache,i) end end
            return
        end
        if not al then
            lastAnimalData[plot.Name]=nil
            for i=#allAnimalsCache,1,-1 do if allAnimalsCache[i].plot==plot.Name then table.remove(allAnimalsCache,i) end end
            return
        end
        local hash = getAnimalHash(al)
        if lastAnimalData[plot.Name]==hash then return end
        for i=#allAnimalsCache,1,-1 do if allAnimalsCache[i].plot==plot.Name then table.remove(allAnimalsCache,i) end end
        for slot, ad in pairs(al) do
            if type(ad)=="table" then
                local aName = ad.Index
                local aInfo = AnimalsData and AnimalsData[aName]
                if aInfo then
                    local mut = ad.Mutation or "None"
                    if mut=="Yin Yang" then mut="YinYang" end
                    local traits = (ad.Traits and #ad.Traits>0) and table.concat(ad.Traits,", ") or "None"
                    local gv = AnimalsShared and AnimalsShared:GetGeneration(aName, ad.Mutation, ad.Traits, nil) or 0
                    local gt = "$"..(NumberUtils and NumberUtils:ToString(gv) or tostring(gv)).."/s"
                    table.insert(allAnimalsCache,{
                        name=aInfo.DisplayName or aName, genText=gt, genValue=gv,
                        mutation=mut, traits=traits, owner=owner.Name,
                        plot=plot.Name, slot=tostring(slot), uid=plot.Name.."_"..tostring(slot)
                    })
                end
            end
        end
        lastAnimalData[plot.Name]=hash
        table.sort(allAnimalsCache,function(a,b) return a.genValue>b.genValue end)
        SharedState.AllAnimalsCache=allAnimalsCache
    end)
end

local function setupPlotListener(plot)
    local retries=0
    while retries<50 do
        if Synchronizer then
            local ok,r=pcall(function() return Synchronizer:Get(plot.Name) end)
            if ok and r then break end
        end
        retries=retries+1; task.wait(0.2)
    end
    scanSinglePlot(plot)
    plot.DescendantAdded:Connect(function() task.wait(0.1); scanSinglePlot(plot) end)
    plot.DescendantRemoving:Connect(function() task.wait(0.1); scanSinglePlot(plot) end)
    task.spawn(function() while plot.Parent do task.wait(5); scanSinglePlot(plot) end end)
end

task.spawn(function()
    local plots = Workspace:WaitForChild("Plots",8)
    if not plots then return end
    for _, p in ipairs(plots:GetChildren()) do task.spawn(setupPlotListener,p) end
    plots.ChildAdded:Connect(function(p) task.wait(0.5); task.spawn(setupPlotListener,p) end)
    plots.ChildRemoved:Connect(function(p)
        lastAnimalData[p.Name]=nil
        for i=#allAnimalsCache,1,-1 do if allAnimalsCache[i].plot==p.Name then table.remove(allAnimalsCache,i) end end
    end)
end)

-- ============================================================
-- 1.38s PERIODIC TOGGLE
-- ============================================================
task.spawn(function()
    if _G._hazeSetInstantSteal then _G._hazeSetInstantSteal(true) end
    while true do
        task.wait(1.38)
        if _G._hazeSetInstantSteal then
            _G._hazeSetInstantSteal(false)
            task.wait(0.05)
            _G._hazeSetInstantSteal(true)
        end
    end
end)

-- ============================================================
-- HEARTBEAT — Instant Steal with brainrot cache targeting
-- ============================================================
local lastInstantTick = 0

RunService.Heartbeat:Connect(function()
    if not instantStealEnabled then return end
    local now = os.clock()
    if now - lastInstantTick < 0.05 then return end
    lastInstantTick = now

    -- progress bar full while active
    hudProgressFill.Size = UDim2.new(1,0,1,0)
    hudProgressFill.BackgroundTransparency = 0

    if not instantStealDidInit then
        instantStealDidInit = true
        task.spawn(function()
            if not game:IsLoaded() then game.Loaded:Wait() end
            task.wait(0.5); instantStealReady = true
        end)
    end
    if not instantStealReady then return end

    -- try cache-based targeting first (highest gen brainrot)
    local pets = get_all_pets()
    if #pets > 0 then
        if selectedTargetIndex > #pets then selectedTargetIndex = #pets end
        if selectedTargetIndex < 1    then selectedTargetIndex = 1 end
        local tp = pets[selectedTargetIndex]
        if tp then
            hudName.Text = tp.petName or "Target"
            local pr = PromptMemoryCache[tp.uid]
            if not pr or not pr.Parent then pr = findProximityPromptForAnimal(tp.animalData) end
            if pr then executeInstantSteal(pr); return end
        end
    end

    -- fallback: nearest raw prompt scan
    local prompt, dist, name = findNearestPrompt_Instant()
    if prompt and dist <= INSTANT_STEAL_RADIUS then
        hudName.Text = name or "Target"
        executeInstantSteal(prompt)
    else
        hudName.Text = "No target"
        hudProgressFill.Size = UDim2.new(0,0,1,0)
    end
end)

print("[AUTO_GRAB] Loaded. Instant Steal + progress bar + brainrot scan active.")
