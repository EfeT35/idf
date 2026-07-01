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

local floorOffsets = { [0]=0, [1]=16, [2]=34 }

-- ============================================================
-- FOLDER
-- ============================================================
local espFolder = Workspace:FindFirstChild("__ESP_SLOTS")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "__ESP_SLOTS"

local highlights = {}  -- [key] = { pad, ph }

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

local function getSlotBase(pod)
    if not pod then return nil end
    return pod:FindFirstChild("Base")
end

local function getBasePart(base)
    if not base then return nil end
    if base:IsA("BasePart") then return base end
    local spawn = base:FindFirstChild("Spawn")
    if spawn and spawn:IsA("BasePart") then return spawn end
    return base:FindFirstChildWhichIsA("BasePart")
end

local function makePad(adornee, color)
    local pad = Instance.new("SelectionBox")
    pad.Adornee             = adornee
    pad.Color3              = color
    pad.SurfaceColor3       = color
    pad.SurfaceTransparency = PLATFORM_TRANSPARENCY
    pad.LineThickness       = OUTLINE_THICKNESS
    pad.Parent              = Workspace
    return pad
end

local function makePlaceholder(cf, size, color)
    local p = Instance.new("Part")
    p.Anchored     = true
    p.CanCollide   = true   -- marchable
    p.CanTouch     = true
    p.CastShadow   = false
    p.Size         = size
    p.CFrame       = cf
    p.Color        = color
    p.Transparency = PLATFORM_TRANSPARENCY
    p.Material     = Enum.Material.SmoothPlastic
    p.Parent       = espFolder
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

    -- Collecter les BaseParts réelles du rez-de-chaussée (slots 1-9)
    local floor0 = {}
    if podiums then
        for s = 1, 9 do
            local pod = podiums:FindFirstChild(tostring(s))
            local bp  = getBasePart(getSlotBase(pod))
            if bp then floor0[s] = bp end
        end
    end

    for slot = 1, TOTAL_SLOTS do
        local key       = plot.Name .. "_" .. slot
        seen[key]       = true
        local floorIdx  = math.floor((slot - 1) / 9)
        local localSlot = ((slot - 1) % 9) + 1

        local pod  = podiums and podiums:FindFirstChild(tostring(slot))
        local base = getSlotBase(pod)

        local occupied = isOccupied(plot.Name, slot)
        local color    = myPlot and COLOR_OWN
                      or (occupied and COLOR_OCCUPIED or COLOR_EMPTY)

        local existing = highlights[key]

        if base then
            -- slot avec géométrie réelle → SelectionBox sur la Base
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
            -- slot sans géométrie → Part solide marchable + SelectionBox
            local ref = floor0[localSlot]
            if not ref then continue end

            local offset  = floorOffsets[floorIdx] or 0
            local newCF   = ref.CFrame + Vector3.new(0, offset, 0)
            local newSize = Vector3.new(ref.Size.X, ref.Size.Y, ref.Size.Z)

            if existing then
                existing.pad.Color3        = color
                existing.pad.SurfaceColor3 = color
                if existing.ph then
                    existing.ph.CFrame = newCF
                    existing.ph.Color  = color
                end
            else
                local ph = makePlaceholder(newCF, newSize, color)
                highlights[key] = { pad = makePad(ph, color), ph = ph }
            end
        end
    end

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
