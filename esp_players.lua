if not game:IsLoaded() then game.Loaded:Wait() end

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Workspace   = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local BOX_COLOR     = Color3.fromRGB(255, 50, 50)
local LINE_THICK    = 0.03
local UPDATE_RATE   = 0.1

-- ============================================================
-- STATE
-- ============================================================
local espEnabled = false
local espData    = {}  -- [player] = { box = SelectionBox, ... }

-- ============================================================
-- ESP LOGIC
-- ============================================================
local function removeESP(player)
    local d = espData[player]
    if not d then return end
    if d.bg and d.bg.Parent then d.bg:Destroy() end
    espData[player] = nil
end

local function addESP(player)
    if player == LocalPlayer then return end
    if espData[player] then return end

    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    if not root then return end

    -- BillboardGui AlwaysOnTop → visible à travers les murs
    local bg = Instance.new("BillboardGui")
    bg.Adornee      = root
    bg.AlwaysOnTop  = true
    bg.Size         = UDim2.new(0, 6, 0, 80)
    bg.StudsOffset  = Vector3.new(0, 3, 0)
    bg.Parent       = Workspace

    -- bordure colorée (frame vide = juste le contour)
    local outline = Instance.new("Frame", bg)
    outline.Size                  = UDim2.fromScale(1, 1)
    outline.BackgroundTransparency = 1
    outline.BorderSizePixel        = 0

    local stroke = Instance.new("UIStroke", outline)
    stroke.Color       = BOX_COLOR
    stroke.Thickness   = 2
    stroke.Transparency = 0

    -- nom du joueur au dessus
    local nameLbl = Instance.new("TextLabel", bg)
    nameLbl.Size                  = UDim2.new(4, 0, 0, 18)
    nameLbl.Position              = UDim2.new(-1.5, 0, 0, -20)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text                  = player.Name
    nameLbl.Font                  = Enum.Font.GothamBold
    nameLbl.TextSize              = 13
    nameLbl.TextColor3            = BOX_COLOR
    nameLbl.TextStrokeTransparency = 0.4
    nameLbl.TextStrokeColor3      = Color3.fromRGB(0,0,0)
    nameLbl.TextScaled            = false

    espData[player] = { bg = bg }
end

local function updateESP(player)
    local d = espData[player]
    if not d then return end
    local char = player.Character
    if not char then removeESP(player); return end
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
    if root then d.bg.Adornee = root end
end

local function enableAll()
    for _, p in ipairs(Players:GetPlayers()) do
        addESP(p)
    end
end

local function disableAll()
    for player in pairs(espData) do
        removeESP(player)
    end
end

-- ============================================================
-- UI — bouton ON/OFF
-- ============================================================
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local sg = Instance.new("ScreenGui")
sg.Name           = "ESP_PLAYERS_UI"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true
sg.Parent         = PlayerGui

local btn = Instance.new("TextButton", sg)
btn.Size             = UDim2.new(0, 110, 0, 36)
btn.Position         = UDim2.new(1, -120, 0, 10)
btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
btn.BorderSizePixel  = 0
btn.Text             = "ESP Players : OFF"
btn.Font             = Enum.Font.GothamBold
btn.TextSize         = 13
btn.TextColor3       = Color3.fromRGB(255, 255, 255)
btn.Active           = true
btn.Draggable        = true
Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

btn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    if espEnabled then
        btn.BackgroundColor3 = Color3.fromRGB(40, 160, 60)
        btn.Text             = "ESP Players : ON"
        enableAll()
    else
        btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        btn.Text             = "ESP Players : OFF"
        disableAll()
    end
end)

-- ============================================================
-- EVENTS
-- ============================================================
Players.PlayerAdded:Connect(function(p)
    if not espEnabled then return end
    p.CharacterAdded:Connect(function()
        task.wait(0.5)
        addESP(p)
    end)
    addESP(p)
end)

Players.PlayerRemoving:Connect(function(p)
    removeESP(p)
end)

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then
        p.CharacterAdded:Connect(function()
            if not espEnabled then return end
            task.wait(0.5)
            addESP(p)
        end)
    end
end

-- ============================================================
-- LOOP UPDATE
-- ============================================================
RunService.Heartbeat:Connect(function()
    if not espEnabled then return end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if espData[p] then
                updateESP(p)
            else
                addESP(p)
            end
        end
    end
end)

print("[ESP PLAYERS] Prêt — clique le bouton pour activer")
