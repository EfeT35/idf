-- ============================================================
-- AUTO GRAB - Minimal Instant Steal script
-- Full TARGET CONTROLS UI (visual for all toggles,
-- only Instant Steal does real work)
-- 1.38s periodic toggle of Instant Steal
-- Heartbeat fires executeInstantSteal when enabled
-- ============================================================

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
-- MOBILE DETECTION
-- ============================================================
local IS_MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

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
-- CONFIG (only what we need)
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
-- SCALE
-- ============================================================
local mobileScale       = IS_MOBILE and 0.6 or 1
local mobileButtonScale = IS_MOBILE and 1.3 or 1

-- ============================================================
-- SHARED STATE (for mobile scale — mirrors original)
-- ============================================================
local SharedState = {
    MobileScaleObjects = {},
}

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
                            X       = target.Position.X.Scale,
                            Y       = target.Position.Y.Scale,
                            OffsetX = target.Position.X.Offset,
                            OffsetY = target.Position.Y.Offset,
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

-- ============================================================
-- HELPER: ApplyViewportUIScale  (no-op on desktop)
-- ============================================================
local function ApplyViewportUIScale(targetFrame, _w, _h, minScale, maxScale)
    if not targetFrame then return end
    if not IS_MOBILE then return end
    local existing = targetFrame:FindFirstChildOfClass("UIScale")
    if existing then existing:Destroy() end
    local sc = Instance.new("UIScale")
    sc.Scale = math.clamp(0.5, minScale or 0.45, maxScale or 1)
    sc.Parent = targetFrame
    SharedState.MobileScaleObjects[targetFrame] = sc
end

-- ============================================================
-- HELPER: AddMobileMinimize  (no-op on desktop)
-- ============================================================
local function AddMobileMinimize(frame, labelText)
    if not IS_MOBILE then return end
    if not frame or not frame.Parent then return end
    local guiParent = frame.Parent
    local header = frame:FindFirstChildWhichIsA("Frame")
    if not header then return end

    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Size = UDim2.new(0, 26, 0, 26)
    minimizeBtn.Position = UDim2.new(1, -30, 0, 6)
    minimizeBtn.BackgroundColor3 = Theme.SurfaceHighlight
    minimizeBtn.Text = "-"
    minimizeBtn.Font = Enum.Font.GothamBlack
    minimizeBtn.TextSize = 18
    minimizeBtn.TextColor3 = Theme.TextPrimary
    minimizeBtn.AutoButtonColor = false
    minimizeBtn.Parent = header
    Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 8)

    local restoreBtn = Instance.new("TextButton")
    restoreBtn.Size = UDim2.new(0, 110, 0, 34)
    restoreBtn.Position = UDim2.new(0, 10, 1, -44)
    restoreBtn.BackgroundColor3 = Theme.SurfaceHighlight
    restoreBtn.Text = labelText or "OPEN"
    restoreBtn.Font = Enum.Font.GothamBold
    restoreBtn.TextSize = 12
    restoreBtn.TextColor3 = Theme.TextPrimary
    restoreBtn.Visible = false
    restoreBtn.AutoButtonColor = false
    restoreBtn.Parent = guiParent
    Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0, 10)

    MakeDraggable(restoreBtn, restoreBtn)

    minimizeBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        restoreBtn.Visible = true
    end)
    restoreBtn.MouseButton1Click:Connect(function()
        frame.Visible = true
        restoreBtn.Visible = false
    end)
end

-- ============================================================
-- STATE VARIABLES
-- ============================================================
local instantStealEnabled  = false
local instantStealReady    = false
local instantStealDidInit  = false

-- Visual-only toggle states
local stealNearestEnabled  = false
local stealHighestEnabled  = false
local stealPriorityEnabled = false

-- Prompt cache
local PromptMemoryCache = {}
local allAnimalsCache   = {}   -- populated by background scanner

local selectedTargetIndex = 1

-- ============================================================
-- SYNCHRONIZER (best-effort require)
-- ============================================================
local Synchronizer

task.spawn(function()
    local ok, s = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Packages", 10):WaitForChild("Synchronizer", 10))
    end)
    if ok then Synchronizer = s end
end)

-- ============================================================
-- isMyPlot_Instant
-- ============================================================
local function isMyPlot_Instant(plotName)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if not sign then return false end
    local yb = sign:FindFirstChild("YourBase")
    return yb and yb:IsA("BillboardGui") and yb.Enabled
end

-- ============================================================
-- findNearestPrompt_Instant
-- ============================================================
local INSTANT_STEAL_RADIUS = 60

local function findNearestPrompt_Instant()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, math.huge end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil, math.huge end
    local bestPrompt, bestDist = nil, math.huge
    for _, plot in ipairs(plots:GetChildren()) do
        if isMyPlot_Instant(plot.Name) then continue end
        local plotDist = math.huge
        pcall(function() plotDist = (plot:GetPivot().Position - hrp.Position).Magnitude end)
        if plotDist > INSTANT_STEAL_RADIUS + 40 then continue end
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if not podiums then continue end
        for _, pod in ipairs(podiums:GetChildren()) do
            local base  = pod:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn")
            if not spawn then continue end
            local dist = (spawn.Position - hrp.Position).Magnitude
            if dist > INSTANT_STEAL_RADIUS or dist >= bestDist then continue end
            local att    = spawn:FindFirstChild("PromptAttachment")
            if not att then continue end
            local prompt = att:FindFirstChildOfClass("ProximityPrompt")
            if prompt and prompt.Parent and prompt.Enabled then
                bestPrompt = prompt
                bestDist   = dist
            end
        end
    end
    return bestPrompt, bestDist
end

-- ============================================================
-- executeInstantSteal
-- ============================================================
local function executeInstantSteal(prompt)
    if not prompt or not prompt.Parent then return end
    pcall(function() fireproximityprompt(prompt, 0) end)
end

-- ============================================================
-- setInstantSteal (shared by button + periodic toggle)
-- ============================================================
local function setInstantSteal(state)
    instantStealEnabled = state
    if not state then
        instantStealReady   = false
        instantStealDidInit = false
    end
    Config.InstantSteal = state
    _G.NEAREST_INSTANT_MODE = (stealNearestEnabled and state)
    -- updateUI called after it's defined below
end
_G._hazeSetInstantSteal = setInstantSteal

-- ============================================================
-- PROGRESS BAR HUD
-- ============================================================
local existingHud = PlayerGui:FindFirstChild("AutoStealCurrentTargetHUD")
if existingHud then existingHud:Destroy() end

local targetHudGui = Instance.new("ScreenGui")
targetHudGui.Name           = "AutoStealCurrentTargetHUD"
targetHudGui.ResetOnSpawn   = false
targetHudGui.IgnoreGuiInset = true
targetHudGui.DisplayOrder   = 998
targetHudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
targetHudGui.Parent         = PlayerGui

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
targetHud.Name                   = "CurrentTargetHUD"
targetHud.AnchorPoint            = Vector2.new(0.5, 1)
targetHud.Size                   = UDim2.new(0, 230 * mobileScale, 0, 46 * mobileScale)
targetHud.Position               = UDim2.new(0.5, 0, 1, -220)
targetHud.BackgroundColor3       = STEALBAR.PANEL
targetHud.BackgroundTransparency = 0.02
targetHud.BorderSizePixel        = 0
targetHud.ZIndex                 = 70
Instance.new("UICorner", targetHud).CornerRadius = UDim.new(0, math.floor(12 * mobileScale))

local hudStroke = Instance.new("UIStroke", targetHud)
hudStroke.Color       = STEALBAR.STROKE
hudStroke.Thickness   = 1
hudStroke.Transparency = 0.35

local hudGlow = Instance.new("UIStroke", targetHud)
hudGlow.Color             = STEALBAR.GLOW
hudGlow.Thickness         = 3
hudGlow.Transparency      = 0.84
hudGlow.ApplyStrokeMode   = Enum.ApplyStrokeMode.Border

local hudShadow = Instance.new("ImageLabel", targetHud)
hudShadow.AnchorPoint        = Vector2.new(0.5, 0.5)
hudShadow.Position           = UDim2.new(0.5, 0, 0.5, 1)
hudShadow.Size               = UDim2.new(1, 20, 1, 20)
hudShadow.BackgroundTransparency = 1
hudShadow.Image              = "rbxassetid://6014261993"
hudShadow.ImageColor3        = Color3.new(0, 0, 0)
hudShadow.ImageTransparency  = 0.72
hudShadow.ScaleType          = Enum.ScaleType.Slice
hudShadow.SliceCenter        = Rect.new(49, 49, 450, 450)
hudShadow.ZIndex             = 69

local hudName = Instance.new("TextLabel", targetHud)
hudName.Name                 = "TargetName"
hudName.Size                 = UDim2.new(1, -12, 0, 13 * mobileScale)
hudName.Position             = UDim2.fromOffset(6 * mobileScale, 3 * mobileScale)
hudName.BackgroundTransparency = 1
hudName.Font                 = Enum.Font.GothamBold
hudName.TextSize             = 11 * mobileScale
hudName.TextColor3           = STEALBAR.TEXT
hudName.TextXAlignment       = Enum.TextXAlignment.Center
hudName.TextTruncate         = Enum.TextTruncate.AtEnd
hudName.ZIndex               = 72
hudName.Text                 = "No target"

local hudProgressBg = Instance.new("Frame", targetHud)
hudProgressBg.Name            = "ProgressBg"
hudProgressBg.Size            = UDim2.new(1, -10 * mobileScale, 0, 18 * mobileScale)
hudProgressBg.Position        = UDim2.fromOffset(5 * mobileScale, 18 * mobileScale)
hudProgressBg.BackgroundColor3 = STEALBAR.TRACK
hudProgressBg.BorderSizePixel = 0
hudProgressBg.ZIndex          = 72
Instance.new("UICorner", hudProgressBg).CornerRadius = UDim.new(0, math.floor(8 * mobileScale))

local hudProgressBgStroke = Instance.new("UIStroke", hudProgressBg)
hudProgressBgStroke.Color       = STEALBAR.STROKE
hudProgressBgStroke.Thickness   = 1
hudProgressBgStroke.Transparency = 0.55

local hudInnerTrack = Instance.new("Frame", hudProgressBg)
hudInnerTrack.Name                   = "InnerTrack"
hudInnerTrack.Size                   = UDim2.new(1, -2, 1, -2)
hudInnerTrack.Position               = UDim2.fromOffset(1, 1)
hudInnerTrack.BackgroundColor3       = STEALBAR.TRACK2
hudInnerTrack.BackgroundTransparency = 0.15
hudInnerTrack.BorderSizePixel        = 0
hudInnerTrack.ZIndex                 = 72
Instance.new("UICorner", hudInnerTrack).CornerRadius = UDim.new(0, math.floor(7 * mobileScale))

local hudProgressFill = Instance.new("Frame", hudProgressBg)
hudProgressFill.Name            = "ProgressFill"
hudProgressFill.Size            = UDim2.new(0, 0, 1, 0)
hudProgressFill.BackgroundColor3 = STEALBAR.FILL1
hudProgressFill.BorderSizePixel = 0
hudProgressFill.ZIndex          = 73
Instance.new("UICorner", hudProgressFill).CornerRadius = UDim.new(0, math.floor(8 * mobileScale))

local hudProgressFillGradient = Instance.new("UIGradient", hudProgressFill)
hudProgressFillGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, STEALBAR.FILL1),
    ColorSequenceKeypoint.new(1, STEALBAR.FILL2),
})

local hudProgressFillStroke = Instance.new("UIStroke", hudProgressFill)
hudProgressFillStroke.Color       = Color3.fromRGB(220, 228, 255)
hudProgressFillStroke.Thickness   = 1
hudProgressFillStroke.Transparency = 0.45

local hudPercent = Instance.new("TextLabel", hudProgressBg)
hudPercent.Name                 = "Percent"
hudPercent.Size                 = UDim2.new(1, 0, 1, 0)
hudPercent.BackgroundTransparency = 1
hudPercent.Font                 = Enum.Font.GothamBold
hudPercent.TextSize             = 12 * mobileScale
hudPercent.TextColor3           = STEALBAR.TEXT
hudPercent.TextStrokeTransparency = 0.7
hudPercent.TextXAlignment       = Enum.TextXAlignment.Center
hudPercent.ZIndex               = 74
hudPercent.Text                 = "0%"

-- update percent label every frame
RunService.Heartbeat:Connect(function()
    local pct = math.clamp(math.floor(hudProgressFill.Size.X.Scale * 100 + 0.5), 0, 100)
    hudPercent.Text = pct .. "%"
end)

-- ============================================================
-- BUILD TARGET CONTROLS UI
-- ============================================================
local existingTC = PlayerGui:FindFirstChild("AutoStealTargetControls")
if existingTC then existingTC:Destroy() end

local targetControlsGui = Instance.new("ScreenGui")
targetControlsGui.Name           = "AutoStealTargetControls"
targetControlsGui.ResetOnSpawn   = false
targetControlsGui.IgnoreGuiInset = true
targetControlsGui.DisplayOrder   = 999
targetControlsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
targetControlsGui.Parent         = PlayerGui

local targetControlsFrame = Instance.new("Frame", targetControlsGui)
targetControlsFrame.Name                   = "TargetControlsFrame"
targetControlsFrame.AutomaticSize          = Enum.AutomaticSize.Y
targetControlsFrame.Size                   = UDim2.new(0, 240 * mobileScale, 0, 0)
targetControlsFrame.Position               = UDim2.new(
    Config.Positions.TargetControls.X       or 0.26,
    Config.Positions.TargetControls.OffsetX or 15,
    Config.Positions.TargetControls.Y       or 0.35,
    Config.Positions.TargetControls.OffsetY or 0
)
targetControlsFrame.BackgroundColor3       = Color3.fromRGB(15, 15, 18)
targetControlsFrame.BackgroundTransparency = 0
targetControlsFrame.BorderSizePixel        = 0
targetControlsFrame.ClipsDescendants       = false
targetControlsFrame.ZIndex                 = 100

ApplyViewportUIScale(targetControlsFrame, 300, 250, 0.45, 0.8)
AddMobileMinimize(targetControlsFrame, "TARGET CONTROLS")

local MiniTargetColors = {
    BG          = Color3.fromRGB(15, 15, 18),
    SURF        = Color3.fromRGB(28, 28, 32),
    SURF2       = Color3.fromRGB(45, 45, 50),
    TEXT        = Color3.fromRGB(245, 245, 250),
    AQUA_STROKE = Color3.fromRGB(190, 190, 200),
    GREEN1      = Color3.fromRGB(18, 88, 58),
    GREEN2      = Color3.fromRGB(21, 120, 76),
    GREEN_STROKE= Color3.fromRGB(60, 185, 120),
    OFF_BG      = Color3.fromRGB(35, 35, 40),
    OFF_TEXT    = Color3.fromRGB(140, 140, 150),
}

local function miniRound(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = obj
    return c
end

local function miniStroke(obj, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = obj
    return s
end

local function miniTween(obj, t, props, style, dir)
    TweenService:Create(
        obj,
        TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
        props
    ):Play()
end

local function miniGradient(parent, c1, c2, rot)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, c1),
        ColorSequenceKeypoint.new(1, c2),
    })
    g.Rotation = rot or 0
    g.Parent = parent
    return g
end

miniRound(targetControlsFrame, 18)
miniStroke(targetControlsFrame, MiniTargetColors.AQUA_STROKE, 1.2, 0.40)

-- Drop shadow
local targetShadow = Instance.new("ImageLabel")
targetShadow.AnchorPoint       = Vector2.new(0.5, 0.5)
targetShadow.Position          = UDim2.new(0.5, 0, 0.5, 2)
targetShadow.Size              = UDim2.new(1, 24, 1, 24)
targetShadow.BackgroundTransparency = 1
targetShadow.Image             = "rbxassetid://6014261993"
targetShadow.ImageColor3       = Color3.new(0, 0, 0)
targetShadow.ImageTransparency = 0.72
targetShadow.ScaleType         = Enum.ScaleType.Slice
targetShadow.SliceCenter       = Rect.new(49, 49, 450, 450)
targetShadow.ZIndex            = 99
targetShadow.Parent            = targetControlsFrame

-- Header / drag handle
local targetControlsHeader = Instance.new("Frame", targetControlsFrame)
targetControlsHeader.Size               = UDim2.new(1, 0, 0, 44)
targetControlsHeader.BackgroundTransparency = 1
targetControlsHeader.ZIndex             = 101
MakeDraggable(targetControlsHeader, targetControlsFrame, "TargetControls")

local targetControlsTitle = Instance.new("TextLabel", targetControlsHeader)
targetControlsTitle.Size               = UDim2.new(1, -28, 0, 24)
targetControlsTitle.Position           = UDim2.new(0, 14, 0, 10)
targetControlsTitle.ZIndex             = 102
targetControlsTitle.BackgroundTransparency = 1
targetControlsTitle.Text               = "TARGET CONTROLS"
targetControlsTitle.Font               = Enum.Font.GothamBlack
targetControlsTitle.TextSize           = 18
targetControlsTitle.TextColor3         = MiniTargetColors.TEXT
targetControlsTitle.TextXAlignment     = Enum.TextXAlignment.Center

local titleLine = Instance.new("Frame", targetControlsFrame)
titleLine.AnchorPoint            = Vector2.new(0.5, 0)
titleLine.Position               = UDim2.new(0.5, 0, 0, 38)
titleLine.Size                   = UDim2.new(0, 124, 0, 1)
titleLine.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
titleLine.BackgroundTransparency = 0.15
titleLine.BorderSizePixel        = 0
titleLine.ZIndex                 = 101

-- Content area
local targetControlsContent = Instance.new("Frame", targetControlsFrame)
targetControlsContent.AutomaticSize    = Enum.AutomaticSize.Y
targetControlsContent.Size             = UDim2.new(1, -20, 0, 0)
targetControlsContent.Position         = UDim2.fromOffset(10, 48)
targetControlsContent.BackgroundColor3 = MiniTargetColors.SURF
targetControlsContent.BorderSizePixel  = 0
targetControlsContent.ZIndex           = 101
miniRound(targetControlsContent, 16)
miniStroke(targetControlsContent, MiniTargetColors.AQUA_STROKE, 1, 0.48)

-- Row container
local toggleBtnContainer = Instance.new("Frame", targetControlsContent)
toggleBtnContainer.AutomaticSize          = Enum.AutomaticSize.Y
toggleBtnContainer.Size                   = UDim2.new(1, -10, 0, 0)
toggleBtnContainer.Position               = UDim2.fromOffset(5, 5)
toggleBtnContainer.BackgroundTransparency = 1
toggleBtnContainer.ZIndex                 = 102

local toggleLayout = Instance.new("UIListLayout")
toggleLayout.Padding   = UDim.new(0, 8)
toggleLayout.SortOrder = Enum.SortOrder.LayoutOrder
toggleLayout.Parent    = toggleBtnContainer

-- Bottom padding
local bottomPad = Instance.new("UIPadding", toggleBtnContainer)
bottomPad.PaddingBottom = UDim.new(0, 6)

-- ============================================================
-- createToggleRow
-- ============================================================
local function createToggleRow(parent, text, layoutOrder)
    local row = Instance.new("Frame", parent)
    row.Name                   = text:gsub("%s+", "") .. "Row"
    row.Size                   = UDim2.new(1, 0, 0, math.floor(36 * mobileButtonScale))
    row.BackgroundColor3       = MiniTargetColors.SURF2
    row.BackgroundTransparency = 0.02
    row.BorderSizePixel        = 0
    row.LayoutOrder            = layoutOrder or 1
    row.ZIndex                 = 103
    miniRound(row, 11)
    local rowStroke = miniStroke(row, MiniTargetColors.AQUA_STROKE, 1, 0.52)

    local label = Instance.new("TextLabel", row)
    label.BackgroundTransparency = 1
    label.Position               = UDim2.fromOffset(12, 0)
    label.Size                   = UDim2.new(1, -100, 1, 0)
    label.Font                   = Enum.Font.GothamBold
    label.Text                   = text
    label.TextColor3             = MiniTargetColors.TEXT
    label.TextSize               = 12 * mobileButtonScale
    label.TextXAlignment         = Enum.TextXAlignment.Left
    label.ZIndex                 = 104

    local stateBox = Instance.new("TextButton", row)
    stateBox.AutoButtonColor  = false
    stateBox.Size             = UDim2.fromOffset(math.floor(72*mobileButtonScale), math.floor(22*mobileButtonScale))
    stateBox.Position         = UDim2.new(1, -math.floor(82*mobileButtonScale), 0.5, -math.floor(11*mobileButtonScale))
    stateBox.BackgroundColor3 = MiniTargetColors.OFF_BG
    stateBox.BorderSizePixel  = 0
    stateBox.Text             = ""
    stateBox.ZIndex           = 104
    miniRound(stateBox, 7)
    local stateStroke = miniStroke(stateBox, MiniTargetColors.AQUA_STROKE, 1, 0.55)

    local stateFill = Instance.new("Frame", stateBox)
    stateFill.Size                   = UDim2.new(1, 0, 1, 0)
    stateFill.BackgroundTransparency = 1
    stateFill.BorderSizePixel        = 0
    stateFill.ZIndex                 = 104
    miniRound(stateFill, 7)
    miniGradient(stateFill, MiniTargetColors.GREEN1, MiniTargetColors.GREEN2, 0)

    local stateText = Instance.new("TextLabel", stateBox)
    stateText.BackgroundTransparency = 1
    stateText.Size                   = UDim2.fromScale(1, 1)
    stateText.Font                   = Enum.Font.GothamBold
    stateText.TextSize               = 11 * mobileButtonScale
    stateText.Text                   = "OFF"
    stateText.TextColor3             = MiniTargetColors.OFF_TEXT
    stateText.ZIndex                 = 105

    row.MouseEnter:Connect(function()
        miniTween(row, 0.14, {BackgroundColor3 = Color3.fromRGB(34, 39, 58)})
        miniTween(rowStroke, 0.14, {Transparency = 0.38})
    end)
    row.MouseLeave:Connect(function()
        miniTween(row, 0.14, {BackgroundColor3 = MiniTargetColors.SURF2})
        miniTween(rowStroke, 0.14, {Transparency = 0.52})
    end)

    return {
        row        = row,
        label      = label,
        button     = stateBox,
        knob       = stateFill,
        stateLabel = stateText,
        stroke     = stateStroke,
        rowStroke  = rowStroke,
    }
end

-- ============================================================
-- Create the 7 toggle rows
-- ============================================================
local nearestBtn    = createToggleRow(toggleBtnContainer, "Nearest",      1)
local highestBtn    = createToggleRow(toggleBtnContainer, "Highest",      2)
local priorityBtn   = createToggleRow(toggleBtnContainer, "Priority",     3)
local autoTurretBtn = createToggleRow(toggleBtnContainer, "Auto Turret",  4)
local autoKickBtn   = createToggleRow(toggleBtnContainer, "Auto Kick",    5)
local instantStealBtn = createToggleRow(toggleBtnContainer, "Instant Steal", 6)
local ownBaseBtn    = createToggleRow(toggleBtnContainer, "Own Base",     7)

-- ============================================================
-- paintToggle + updateUI
-- ============================================================
local function paintToggle(ref, isOn)
    if isOn then
        ref.button.BackgroundColor3      = MiniTargetColors.GREEN1
        ref.knob.BackgroundTransparency  = 0
        ref.stateLabel.Text              = "ON"
        ref.stateLabel.TextColor3        = Color3.fromRGB(232, 255, 240)
        ref.stroke.Color                 = MiniTargetColors.GREEN_STROKE
        ref.stroke.Transparency          = 0.22
    else
        ref.button.BackgroundColor3      = MiniTargetColors.OFF_BG
        ref.knob.BackgroundTransparency  = 1
        ref.stateLabel.Text              = "OFF"
        ref.stateLabel.TextColor3        = MiniTargetColors.OFF_TEXT
        ref.stroke.Color                 = MiniTargetColors.AQUA_STROKE
        ref.stroke.Transparency          = 0.55
    end
    if ref.rowStroke then
        ref.rowStroke.Transparency = isOn and 0.38 or 0.52
    end
end

local function updateUI()
    paintToggle(nearestBtn,     stealNearestEnabled)
    paintToggle(highestBtn,     stealHighestEnabled)
    paintToggle(priorityBtn,    stealPriorityEnabled)
    paintToggle(autoTurretBtn,  Config.AutoDestroyTurrets)
    paintToggle(autoKickBtn,    Config.AutoKickOnSteal)
    paintToggle(ownBaseBtn,     Config.AutoGrabOwnBase)
    paintToggle(instantStealBtn, instantStealEnabled)
end

-- Now that updateUI is defined, wire it into setInstantSteal
local _origSetInstantSteal = setInstantSteal
setInstantSteal = function(state)
    _origSetInstantSteal(state)
    updateUI()
end
_G._hazeSetInstantSteal = setInstantSteal

-- Initial paint
updateUI()

-- ============================================================
-- BUTTON HANDLERS
-- Nearest / Highest / Priority / Auto Turret / Auto Kick / Own Base:
--   visual-only — they toggle their flag and repaint, nothing else
-- Instant Steal: calls setInstantSteal (real work)
-- ============================================================

nearestBtn.button.MouseButton1Click:Connect(function()
    stealNearestEnabled = not stealNearestEnabled
    if stealNearestEnabled then
        stealHighestEnabled  = false
        stealPriorityEnabled = false
    end
    updateUI()
end)

highestBtn.button.MouseButton1Click:Connect(function()
    stealHighestEnabled = not stealHighestEnabled
    if stealHighestEnabled then
        stealNearestEnabled  = false
        stealPriorityEnabled = false
    end
    updateUI()
end)

priorityBtn.button.MouseButton1Click:Connect(function()
    stealPriorityEnabled = not stealPriorityEnabled
    if stealPriorityEnabled then
        stealNearestEnabled = false
        stealHighestEnabled = false
    end
    updateUI()
end)

autoTurretBtn.button.MouseButton1Click:Connect(function()
    Config.AutoDestroyTurrets = not Config.AutoDestroyTurrets
    updateUI()
end)

autoKickBtn.button.MouseButton1Click:Connect(function()
    Config.AutoKickOnSteal = not Config.AutoKickOnSteal
    updateUI()
end)

ownBaseBtn.button.MouseButton1Click:Connect(function()
    Config.AutoGrabOwnBase = not Config.AutoGrabOwnBase
    updateUI()
end)

instantStealBtn.button.MouseButton1Click:Connect(function()
    setInstantSteal(not instantStealEnabled)
end)

-- ============================================================
-- 1.38s PERIODIC TOGGLE  (keeps Instant Steal cycling ON/OFF/ON)
-- ============================================================
task.spawn(function()
    -- Activate immediately on load
    if _G._hazeSetInstantSteal then _G._hazeSetInstantSteal(true) end

    while true do
        task.wait(1.38)
        if _G._hazeSetInstantSteal then
            _G._hazeSetInstantSteal(false)   -- OFF
            task.wait(0.05)                  -- brief pause
            _G._hazeSetInstantSteal(true)    -- ON
        end
    end
end)

-- ============================================================
-- HEARTBEAT — fires executeInstantSteal when enabled
-- ============================================================
local lastInstantTick = 0

RunService.Heartbeat:Connect(function()
    if not instantStealEnabled then return end

    local now = os.clock()
    if now - lastInstantTick < 0.05 then return end
    lastInstantTick = now

    -- One-time init: wait 0.5s before first fire to let prompts load
    if not instantStealDidInit then
        instantStealDidInit = true
        task.spawn(function()
            if not game:IsLoaded() then game.Loaded:Wait() end
            task.wait(0.5)
            instantStealReady = true
        end)
    end

    if not instantStealReady then return end

    -- Always use nearest-prompt strategy (fastest)
    local prompt, dist = findNearestPrompt_Instant()
    if prompt and dist <= INSTANT_STEAL_RADIUS then
        -- Fill bar to 100% instantly when firing
        hudProgressFill.Size = UDim2.new(1, 0, 1, 0)
        executeInstantSteal(prompt)
    else
        -- No target: drain bar back to 0
        hudProgressFill.Size = UDim2.new(0, 0, 1, 0)
        hudName.Text = "No target"
    end
end)

print("[AUTO_GRAB] Loaded. Target Controls UI ready. Instant Steal cycling every 1.38s.")
