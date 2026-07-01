if not game:IsLoaded() then game.Loaded:Wait() end

local RunService   = game:GetService("RunService")
local Workspace    = game:GetService("Workspace")
local Players      = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

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
local OUTLINE        = 0.10
local SURFACE_TRANSP = 0.3
local UPDATE_RATE    = 1.5

-- ============================================================
-- DOSSIER ESP
-- ============================================================
local espFolder = Workspace:FindFirstChild("__ESP_SLOTS")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "__ESP_SLOTS"

local boxes = {}  -- [plotName_slot] = SelectionBox

-- ============================================================
-- HELPERS
-- ============================================================
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
    return ad and type(ad) == "table"
end

local function makeBox(adornee, color)
    local box = Instance.new("SelectionBox")
    box.Adornee             = adornee
    box.Color3              = color
    box.LineThickness        = OUTLINE
    box.SurfaceColor3       = color
    box.SurfaceTransparency  = SURFACE_TRANSP
    box.Parent              = espFolder
    return box
end

-- ============================================================
-- SCAN
-- ============================================================
local function scanPlot(plot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return end

    local myPlot = isMyPlot(plot.Name)
    local seen   = {}

    for _, pod in ipairs(podiums:GetChildren()) do
        -- cherche la base même si vide
        local base = pod:FindFirstChild("Base")
        if not base then
            -- fallback : premier BasePart dans le podium
            base = pod:FindFirstChildWhichIsA("BasePart")
            if not base then
                for _, d in ipairs(pod:GetDescendants()) do
                    if d:IsA("BasePart") then base = d; break end
                end
            end
        end
        if not base then continue end

        local adornee = base:FindFirstChild("Spawn") or base

        local key = plot.Name .. "_" .. pod.Name
        seen[key] = true

        local color
        if myPlot then
            color = COLOR_OWN
        elseif isOccupied(plot.Name, pod.Name) then
            color = COLOR_OCCUPIED
        else
            color = COLOR_EMPTY
        end

        if boxes[key] and boxes[key].Parent then
            boxes[key].Color3        = color
            boxes[key].SurfaceColor3 = color
        else
            if boxes[key] then boxes[key]:Destroy() end
            boxes[key] = makeBox(adornee, color)
        end
    end

    -- nettoyer les slots disparus
    for key in pairs(boxes) do
        if key:sub(1, #plot.Name + 1) == plot.Name .. "_" and not seen[key] then
            if boxes[key] then boxes[key]:Destroy() end
            boxes[key] = nil
        end
    end
end

local function scanAll()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end
    for _, plot in ipairs(plots:GetChildren()) do
        pcall(scanPlot, plot)
    end
end

-- ============================================================
-- LANCEMENT
-- ============================================================
task.wait(1)
scanAll()

task.spawn(function()
    while espFolder.Parent do
        task.wait(UPDATE_RATE)
        pcall(scanAll)
    end
end)

local plots = Workspace:WaitForChild("Plots", 8)
if plots then
    plots.ChildAdded:Connect(function(plot)
        task.wait(0.5); pcall(scanPlot, plot)
    end)
    plots.ChildRemoved:Connect(function(plot)
        for key in pairs(boxes) do
            if key:sub(1, #plot.Name + 1) == plot.Name .. "_" then
                if boxes[key] then boxes[key]:Destroy() end
                boxes[key] = nil
            end
        end
    end)
end

print("[ESP SLOTS] Actif")
