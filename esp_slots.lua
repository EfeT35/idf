if not game:IsLoaded() then game.Loaded:Wait() end

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local Packages     = ReplicatedStorage:WaitForChild("Packages")
local Datas        = ReplicatedStorage:WaitForChild("Datas")
local Synchronizer = require(Packages:WaitForChild("Synchronizer"))
local AnimalsData  = require(Datas:WaitForChild("Animals"))

-- ============================================================
-- CONFIG
-- ============================================================
local COLOR_OCCUPIED    = Color3.fromRGB(255, 50,  50)
local COLOR_EMPTY       = Color3.fromRGB(50,  220, 80)
local COLOR_OWN         = Color3.fromRGB(80,  150, 255)
local FILL_TRANSPARENCY  = 0.55
local OUTLINE_TRANSPARENCY = 0
local UPDATE_RATE       = 1.5

-- ============================================================
-- FOLDER
-- ============================================================
local espFolder = Workspace:FindFirstChild("__ESP_SLOTS")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "__ESP_SLOTS"

local highlights = {}  -- [key] = Highlight

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
    return ad ~= nil and type(ad) == "table"
end

local function makeHighlight(adornee, color)
    local h = Instance.new("Highlight")
    h.Adornee              = adornee
    h.FillColor            = color
    h.OutlineColor         = color
    h.FillTransparency     = FILL_TRANSPARENCY
    h.OutlineTransparency  = OUTLINE_TRANSPARENCY
    h.DepthMode            = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent               = espFolder
    return h
end

-- ============================================================
-- SCAN UN PLOT
-- ============================================================
local function scanPlot(plot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return end

    local myPlot = isMyPlot(plot.Name)
    local seen   = {}

    for _, pod in ipairs(podiums:GetChildren()) do
        local key = plot.Name .. "_" .. pod.Name
        seen[key] = true

        -- on adore le podium entier = tous les étages inclus
        local adornee = pod

        local color
        if myPlot then
            color = COLOR_OWN
        elseif isOccupied(plot.Name, pod.Name) then
            color = COLOR_OCCUPIED
        else
            color = COLOR_EMPTY
        end

        if highlights[key] and highlights[key].Parent then
            highlights[key].FillColor    = color
            highlights[key].OutlineColor = color
        else
            if highlights[key] then highlights[key]:Destroy() end
            highlights[key] = makeHighlight(adornee, color)
        end
    end

    -- nettoyer les slots disparus
    for key in pairs(highlights) do
        if key:sub(1, #plot.Name + 1) == plot.Name .. "_" and not seen[key] then
            if highlights[key] then highlights[key]:Destroy() end
            highlights[key] = nil
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
        for key in pairs(highlights) do
            if key:sub(1, #plot.Name + 1) == plot.Name .. "_" then
                if highlights[key] then highlights[key]:Destroy() end
                highlights[key] = nil
            end
        end
    end)
end

print("[ESP SLOTS] Actif")
