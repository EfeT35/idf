if not game:IsLoaded() then game.Loaded:Wait() end

local Players          = game:GetService("Players")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- MODULES
-- ============================================================
local Packages    = ReplicatedStorage:WaitForChild("Packages")
local Datas       = ReplicatedStorage:WaitForChild("Datas")

local Synchronizer = require(Packages:WaitForChild("Synchronizer"))
local AnimalsData  = require(Datas:WaitForChild("Animals"))

-- ============================================================
-- CONFIG
-- ============================================================
local COLOR_OCCUPIED        = Color3.fromRGB(255, 50,  50)
local COLOR_EMPTY           = Color3.fromRGB(50,  220, 80)
local COLOR_OWN             = Color3.fromRGB(80,  150, 255)
local PLATFORM_TRANSPARENCY = 0.35
local OUTLINE_THICKNESS     = 0.12
local UPDATE_RATE           = 1.5
local TOTAL_SLOTS           = 27

-- hauteurs modifiables via l'UI
local floorOffsets = { [0]=0, [1]=16, [2]=34 }

-- ============================================================
-- UI — réglage des hauteurs d'étage
-- ============================================================
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "ESP_FLOOR_UI"
screenGui.ResetOnSpawn    = false
screenGui.IgnoreGuiInset  = true
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.Parent          = PlayerGui

local frame = Instance.new("Frame", screenGui)
frame.Size            = UDim2.new(0, 220, 0, 110)
frame.Position        = UDim2.new(0, 10, 0.5, -55)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
frame.BackgroundTransparency = 0.3
frame.BorderSizePixel = 0
frame.Active          = true
frame.Draggable       = true

local corner = Instance.new("UICorner", frame)
corner.CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel", frame)
title.Size               = UDim2.new(1, 0, 0, 24)
title.Position           = UDim2.new(0, 0, 0, 0)
title.BackgroundTransparency = 1
title.Text               = "ESP — hauteur des étages"
title.Font               = Enum.Font.GothamBold
title.TextSize           = 13
title.TextColor3         = Color3.fromRGB(220, 220, 220)

local function makeRow(label, floorIdx, yPos)
    local row = Instance.new("Frame", frame)
    row.Size                  = UDim2.new(1, -10, 0, 26)
    row.Position              = UDim2.new(0, 5, 0, yPos)
    row.BackgroundTransparency = 1

    local lbl = Instance.new("TextLabel", row)
    lbl.Size             = UDim2.new(0, 90, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text             = label
    lbl.Font             = Enum.Font.Gotham
    lbl.TextSize         = 12
    lbl.TextColor3       = Color3.fromRGB(200, 200, 200)
    lbl.TextXAlignment   = Enum.TextXAlignment.Left

    local valLbl = Instance.new("TextLabel", row)
    valLbl.Size            = UDim2.new(0, 40, 1, 0)
    valLbl.Position        = UDim2.new(0, 90, 0, 0)
    valLbl.BackgroundTransparency = 1
    valLbl.Text            = tostring(floorOffsets[floorIdx])
    valLbl.Font            = Enum.Font.GothamBold
    valLbl.TextSize        = 13
    valLbl.TextColor3      = Color3.fromRGB(255, 220, 80)
    valLbl.TextXAlignment  = Enum.TextXAlignment.Center

    local function makeBtn(sign, xOff)
        local btn = Instance.new("TextButton", row)
        btn.Size              = UDim2.new(0, 28, 0, 22)
        btn.Position          = UDim2.new(0, xOff, 0.5, -11)
        btn.BackgroundColor3  = Color3.fromRGB(50, 50, 50)
        btn.BorderSizePixel   = 0
        btn.Text              = sign
        btn.Font              = Enum.Font.GothamBold
        btn.TextSize          = 14
        btn.TextColor3        = Color3.fromRGB(255, 255, 255)
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
        return btn
    end

    local minus = makeBtn("-", 136)
    local plus  = makeBtn("+", 168)

    minus.MouseButton1Click:Connect(function()
        floorOffsets[floorIdx] = floorOffsets[floorIdx] - 1
        valLbl.Text = tostring(floorOffsets[floorIdx])
    end)
    plus.MouseButton1Click:Connect(function()
        floorOffsets[floorIdx] = floorOffsets[floorIdx] + 1
        valLbl.Text = tostring(floorOffsets[floorIdx])
    end)
end

makeRow("Étage 1 (slots 10-18)", 1, 28)
makeRow("Étage 2 (slots 19-27)", 2, 58)

local applyBtn = Instance.new("TextButton", frame)
applyBtn.Size             = UDim2.new(1, -10, 0, 22)
applyBtn.Position         = UDim2.new(0, 5, 0, 86)
applyBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 60)
applyBtn.BorderSizePixel  = 0
applyBtn.Text             = "Appliquer"
applyBtn.Font             = Enum.Font.GothamBold
applyBtn.TextSize         = 13
applyBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 4)

-- ============================================================
-- FOLDER
-- ============================================================
local espFolder = Workspace:FindFirstChild("__ESP_SLOTS")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "__ESP_SLOTS"

-- ============================================================
-- HELPERS
-- ============================================================
local highlights = {}  -- [key] = { pad, ph }

local function isMyPlot(plotName)
    local ok, ch = pcall(function() return Synchronizer:Get(plotName) end)
    if not ok or not ch then return false end
    local owner = ch:Get("Owner")
    if not owner then return false end
    if typeof(owner) == "Instance" and owner:IsA("Player") then
        return owner.UserId == LocalPlayer.UserId
    elseif typeof(owner) == "table" and owner.UserId then
        return owner.UserId == LocalPlayer.UserId
    end
    return false
end

local function isOccupied(plotName, slot)
    local ok, ch = pcall(function() return Synchronizer:Get(plotName) end)
    if not ok or not ch then return false end
    local al = ch:Get("AnimalList")
    if not al then return false end
    local ad = al[tonumber(slot)]
    return ad ~= nil and type(ad) == "table"
end

local function getSlotBase(pod)
    if not pod then return nil end
    return pod:FindFirstChild("Base")
end

local function makePad(adornee, color)
    local pad = Instance.new("SelectionBox")
    pad.Adornee           = adornee
    pad.Color3            = color
    pad.SurfaceColor3     = color
    pad.SurfaceTransparency = PLATFORM_TRANSPARENCY
    pad.LineThickness     = OUTLINE_THICKNESS
    pad.Parent            = Workspace
    return pad
end

local function makePlaceholder(cf, size)
    local p = Instance.new("Part")
    p.Anchored    = true
    p.CanCollide  = false
    p.CanTouch    = false
    p.CastShadow  = false
    p.Size        = size
    p.CFrame      = cf
    p.Transparency = 1
    p.Parent      = espFolder
    return p
end

local function removeSlot(key)
    local h = highlights[key]
    if not h then return end
    if h.pad and h.pad.Parent then h.pad:Destroy() end
    if h.ph  and h.ph.Parent  then h.ph:Destroy()  end
    highlights[key] = nil
end

-- ============================================================
-- SCAN UN PLOT
-- ============================================================
local function scanPlot(plot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    local myPlot  = isMyPlot(plot.Name)
    local seen    = {}

    -- helper : récupère la BasePart principale d'une Base Model
    local function getBasePart(base)
        if not base then return nil end
        if base:IsA("BasePart") then return base end
        local spawn = base:FindFirstChild("Spawn")
        if spawn and spawn:IsA("BasePart") then return spawn end
        return base:FindFirstChildWhichIsA("BasePart")
    end

    -- 1. Collecter les BaseParts réelles du rez-de-chaussée (slots 1-9)
    local floor0 = {}  -- localSlot(1-9) → BasePart
    if podiums then
        for s = 1, 9 do
            local pod  = podiums:FindFirstChild(tostring(s))
            local base = getSlotBase(pod)
            local bp   = getBasePart(base)
            if bp then floor0[s] = bp end
        end
    end

    -- floorOffsets est la table globale modifiée par l'UI

    -- 3. Itérer les 27 slots
    for slot = 1, TOTAL_SLOTS do
        local key       = plot.Name .. "_" .. slot
        seen[key]       = true
        local floorIdx  = math.floor((slot - 1) / 9)   -- 0, 1, 2
        local localSlot = ((slot - 1) % 9) + 1          -- 1-9

        local pod  = podiums and podiums:FindFirstChild(tostring(slot))
        local base = getSlotBase(pod)

        local occupied = isOccupied(plot.Name, slot)
        local color    = myPlot and COLOR_OWN
                      or (occupied and COLOR_OCCUPIED or COLOR_EMPTY)

        local existing = highlights[key]

        if base then
            -- slot avec géométrie réelle
            if existing then
                if existing.ph then
                    existing.ph:Destroy()
                    existing.pad:Destroy()
                    highlights[key] = { pad = makePad(base, color), ph = nil }
                else
                    existing.pad.Color3        = color
                    existing.pad.SurfaceColor3 = color
                    existing.pad.Adornee       = base
                end
            else
                highlights[key] = { pad = makePad(base, color), ph = nil }
            end
        else
            -- slot sans géométrie : dupliquer le slot du rez-de-chaussée décalé vers le haut
            local ref = floor0[localSlot]
            if not ref then continue end  -- pas de référence → skip

            local offset  = floorOffsets[floorIdx] or (floorIdx * FLOOR_1_OFFSET)
            local newCF   = ref.CFrame + Vector3.new(0, offset, 0)
            local newSize = Vector3.new(ref.Size.X, 0.2, ref.Size.Z)  -- plat

            if existing then
                existing.pad.Color3        = color
                existing.pad.SurfaceColor3 = color
                if existing.ph then
                    existing.ph.CFrame = newCF
                    existing.ph.Size   = newSize
                end
            else
                local ph = makePlaceholder(newCF, newSize)
                highlights[key] = { pad = makePad(ph, color), ph = ph }
            end
        end
    end

    -- 4. Nettoyer les anciens slots de ce plot
    for key in pairs(highlights) do
        local prefix = plot.Name .. "_"
        if key:sub(1, #prefix) == prefix and not seen[key] then
            removeSlot(key)
        end
    end
end

-- ============================================================
-- SCAN TOUS LES PLOTS
-- ============================================================
local function scanAll()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end
    for _, plot in ipairs(plots:GetChildren()) do
        pcall(scanPlot, plot)
    end
end

applyBtn.MouseButton1Click:Connect(function()
    -- vider tous les placeholders et rescanner avec les nouvelles hauteurs
    for key, h in pairs(highlights) do
        if h.ph then
            h.pad:Destroy()
            h.ph:Destroy()
            highlights[key] = nil
        end
    end
    pcall(scanAll)
end)

task.wait(1)
pcall(scanAll)

task.spawn(function()
    while espFolder.Parent do
        task.wait(UPDATE_RATE)
        pcall(scanAll)
    end
end)

local plots = Workspace:WaitForChild("Plots", 8)
if plots then
    plots.ChildAdded:Connect(function(plot)
        task.wait(0.5)
        pcall(scanPlot, plot)
    end)
    plots.ChildRemoved:Connect(function(plot)
        for key in pairs(highlights) do
            if key:sub(1, #plot.Name + 1) == plot.Name .. "_" then
                removeSlot(key)
            end
        end
    end)
end

print("[ESP SLOTS] Actif — rouge=occupé, vert=libre, bleu=ta base")
