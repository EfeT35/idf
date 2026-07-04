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
    if d.box and d.box.Parent then d.box:Destroy() end
    espData[player] = nil
end

local function addESP(player)
    if player == LocalPlayer then return end
    if espData[player] then return end

    local char = player.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local box = Instance.new("SelectionBox")
    box.Adornee             = char
    box.Color3              = BOX_COLOR
    box.SurfaceColor3       = BOX_COLOR
    box.SurfaceTransparency = 0.7
    box.LineThickness       = LINE_THICK
    box.Parent              = Workspace

    espData[player] = { box = box }
end

local function updateESP(player)
    local d = espData[player]
    if not d then return end
    local char = player.Character
    if not char then removeESP(player); return end
    d.box.Adornee = char
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
