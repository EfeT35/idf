if not game:IsLoaded() then game.Loaded:Wait() end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
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
local COLOR_OCCUPIED = Color3.fromRGB(255, 50,  50)   -- rouge  = occupé
local COLOR_EMPTY    = Color3.fromRGB(50,  220, 80)   -- vert   = libre
local COLOR_OWN      = Color3.fromRGB(80,  150, 255)  -- bleu   = ta base
local PLATFORM_TRANSPARENCY = 0.35
local OUTLINE_THICKNESS     = 0.12
local UPDATE_RATE           = 1.5  -- secondes entre chaque refresh

-- ============================================================
-- FOLDER pour garder les highlights propres
-- ============================================================
local espFolder = Workspace:FindFirstChild("__ESP_SLOTS")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "__ESP_SLOTS"

-- ============================================================
-- HELPERS
-- ============================================================
local highlights = {}   -- [plotName_slot] = {highlight, label, platform}

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

local function getAnimalName(plotName, slot)
    local ok, ch = pcall(function() return Synchronizer:Get(plotName) end)
    if not ok or not ch then return nil end
    local al = ch:Get("AnimalList")
    if not al then return nil end
    local ad = al[tonumber(slot)]
    if not ad or type(ad) ~= "table" then return nil end
    local aInfo = AnimalsData[ad.Index]
    return aInfo and (aInfo.DisplayName or ad.Index) or ad.Index
end

local function makeLabel(adornee, text)
    local bg = Instance.new("BillboardGui")
    bg.AlwaysOnTop  = true
    bg.Size         = UDim2.new(0, 130, 0, 28)
    bg.StudsOffset  = Vector3.new(0, 3.5, 0)
    bg.Adornee      = adornee
    bg.Parent       = espFolder

    local lbl = Instance.new("TextLabel", bg)
    lbl.Size                  = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency= 1
    lbl.Text                  = text
    lbl.Font                  = Enum.Font.GothamBold
    lbl.TextSize              = 13
    lbl.TextColor3            = Color3.fromRGB(255, 255, 255)
    lbl.TextStrokeTransparency= 0.4
    lbl.TextStrokeColor3      = Color3.fromRGB(0, 0, 0)
    lbl.TextScaled            = true
    return bg, lbl
end

local function makePlatform(base, color)
    -- plateforme colorée sous le podium
    local pad = Instance.new("SelectionBox")
    pad.Adornee          = base
    pad.Color3           = color
    pad.LineThickness    = OUTLINE_THICKNESS
    pad.SurfaceTransparency      = PLATFORM_TRANSPARENCY
    pad.SurfaceColor3   = color
    pad.Parent          = espFolder
    return pad
end

local function upsertSlot(plotName, slotKey, base, spawn)
    local key = plotName .. "_" .. slotKey
    local animalName = getAnimalName(plotName, slotKey)
    local myPlot     = isMyPlot(plotName)

    local color
    if myPlot then
        color = COLOR_OWN
    elseif animalName then
        color = COLOR_OCCUPIED
    else
        color = COLOR_EMPTY
    end

    local labelText = animalName or "[ libre ]"

    if highlights[key] then
        -- mise à jour
        local h = highlights[key]
        h.pad.Color3        = color
        h.pad.SurfaceColor3 = color
        h.lbl.Text          = labelText
        h.lbl.TextColor3    = color
    else
        -- création
        local pad           = makePlatform(base, color)
        local billGui, lbl  = makeLabel(spawn or base, labelText)
        lbl.TextColor3      = color
        highlights[key] = {pad=pad, gui=billGui, lbl=lbl}
    end
end

local function removeSlot(key)
    local h = highlights[key]
    if h then
        if h.pad and h.pad.Parent then h.pad:Destroy() end
        if h.gui and h.gui.Parent then h.gui:Destroy() end
        highlights[key] = nil
    end
end

-- ============================================================
-- SCAN UN PLOT
-- ============================================================
local function scanPlot(plot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return end

    local seen = {}
    for _, pod in ipairs(podiums:GetChildren()) do
        local base  = pod:FindFirstChild("Base")
        if not base then continue end
        local spawn = base:FindFirstChild("Spawn") or base:FindFirstChildWhichIsA("BasePart") or base
        local key   = plot.Name .. "_" .. pod.Name
        seen[key]   = true
        upsertSlot(plot.Name, pod.Name, base, spawn)
    end

    -- supprimer les slots qui n'existent plus pour ce plot
    for key in pairs(highlights) do
        if key:sub(1, #plot.Name + 1) == plot.Name .. "_" then
            if not seen[key] then removeSlot(key) end
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

-- premier scan immédiat
task.wait(1)
scanAll()

-- refresh périodique
task.spawn(function()
    while espFolder.Parent do
        task.wait(UPDATE_RATE)
        pcall(scanAll)
    end
end)

-- écouter les nouveaux plots
local plots = Workspace:WaitForChild("Plots", 8)
if plots then
    plots.ChildAdded:Connect(function(plot)
        task.wait(0.5)
        pcall(scanPlot, plot)
    end)
    plots.ChildRemoved:Connect(function(plot)
        -- nettoyer les highlights de ce plot
        for key in pairs(highlights) do
            if key:sub(1, #plot.Name + 1) == plot.Name .. "_" then
                removeSlot(key)
            end
        end
    end)
end

print("[ESP SLOTS] Actif — rouge=occupé, vert=libre, bleu=ta base")
