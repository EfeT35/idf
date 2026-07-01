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
local TOTAL_SLOTS          = 27
local COLOR_OCCUPIED       = Color3.fromRGB(255, 50,  50)
local COLOR_EMPTY          = Color3.fromRGB(50,  220, 80)
local COLOR_OWN            = Color3.fromRGB(80,  150, 255)
local FILL_TRANSPARENCY    = 0.45
local OUTLINE_TRANSPARENCY = 0
local UPDATE_RATE          = 1.5

-- taille de la plateforme placeholder pour les slots sans géométrie
local PLACEHOLDER_SIZE = Vector3.new(5, 0.2, 5)

-- ============================================================
-- FOLDER
-- ============================================================
local espFolder = Workspace:FindFirstChild("__ESP_SLOTS")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "__ESP_SLOTS"

-- [key] = { highlight=Highlight, placeholder=Part|nil }
local slotData = {}

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

-- trouve la BasePart principale d'un podium
local function getSlotPart(pod)
    if not pod then return nil end
    local base = pod:FindFirstChild("Base")
    if base then
        local spawn = base:FindFirstChild("Spawn")
        if spawn and spawn:IsA("BasePart") then return spawn end
        local bp = base:FindFirstChildWhichIsA("BasePart")
        if bp then return bp end
        if base:IsA("BasePart") then return base end
    end
    -- fallback: premier BasePart descendant
    for _, d in ipairs(pod:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

-- crée une Part placeholder à la position donnée
local function makePlaceholder(pos)
    local part = Instance.new("Part")
    part.Anchored    = true
    part.CanCollide  = false
    part.CanTouch    = false
    part.CastShadow  = false
    part.Size        = PLACEHOLDER_SIZE
    part.CFrame      = CFrame.new(pos)
    part.Transparency = 1
    part.Parent      = espFolder
    return part
end

local function makeHighlight(adornee, color)
    local h = Instance.new("Highlight")
    h.Adornee             = adornee
    h.FillColor           = color
    h.OutlineColor        = color
    h.FillTransparency    = FILL_TRANSPARENCY
    h.OutlineTransparency = OUTLINE_TRANSPARENCY
    h.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent              = espFolder
    return h
end

local function removeSlot(key)
    local d = slotData[key]
    if not d then return end
    if d.highlight    then d.highlight:Destroy() end
    if d.placeholder  then d.placeholder:Destroy() end
    slotData[key] = nil
end

-- ============================================================
-- SCAN UN PLOT — itère tous les 27 slots
-- ============================================================
local function scanPlot(plot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    local myPlot  = isMyPlot(plot.Name)
    local seen    = {}

    for slot = 1, TOTAL_SLOTS do
        local key = plot.Name .. "_" .. tostring(slot)
        seen[key] = true

        local color = myPlot and COLOR_OWN
                   or (isOccupied(plot.Name, tostring(slot)) and COLOR_OCCUPIED or COLOR_EMPTY)

        local pod     = podiums and podiums:FindFirstChild(tostring(slot))
        local part    = pod and getSlotPart(pod)
        local existing = slotData[key]

        if part then
            -- le slot a une géométrie → on adore la vraie Part
            if existing then
                -- supprimer placeholder si on avait un avant
                if existing.placeholder then
                    existing.placeholder:Destroy()
                    existing.placeholder = nil
                    -- recréer le highlight sur la vraie part
                    if existing.highlight then existing.highlight:Destroy() end
                    existing.highlight = makeHighlight(part, color)
                else
                    existing.highlight.FillColor    = color
                    existing.highlight.OutlineColor = color
                    existing.highlight.Adornee      = part
                end
            else
                slotData[key] = {
                    highlight   = makeHighlight(part, color),
                    placeholder = nil,
                }
            end
        else
            -- pas de géométrie → placeholder invisible à la position du plot
            -- essayer de déduire la position à partir du plot lui-même
            local plotPos = Vector3.new(0, 0, 0)
            pcall(function() plotPos = plot:GetPivot().Position end)
            -- décaler légèrement selon le numéro de slot pour ne pas superposer
            local col   = (slot - 1) % 9
            local row   = math.floor((slot - 1) / 9)
            local offset = Vector3.new(col * 6 - 24, row * 4, 0)
            local pos   = plotPos + offset

            if existing then
                existing.highlight.FillColor    = color
                existing.highlight.OutlineColor = color
                if existing.placeholder then
                    existing.placeholder.CFrame = CFrame.new(pos)
                end
            else
                local ph = makePlaceholder(pos)
                slotData[key] = {
                    highlight   = makeHighlight(ph, color),
                    placeholder = ph,
                }
            end
        end
    end

    -- nettoyer les anciens slots de ce plot qui dépassent 27
    for key in pairs(slotData) do
        if key:sub(1, #plot.Name + 1) == plot.Name .. "_" and not seen[key] then
            removeSlot(key)
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
    plots.ChildAdded:Connect(function(p)
        task.wait(0.5); pcall(scanPlot, p)
    end)
    plots.ChildRemoved:Connect(function(p)
        for key in pairs(slotData) do
            if key:sub(1, #p.Name + 1) == p.Name .. "_" then
                removeSlot(key)
            end
        end
    end)
end

print("[ESP SLOTS] Actif — 27 slots par base")
