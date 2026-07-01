if not game:IsLoaded() then game.Loaded:Wait() end

local Workspace   = game:GetService("Workspace")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local TOTAL_SLOTS          = 27
local COLOR_OCCUPIED       = Color3.fromRGB(255, 50,  50)
local COLOR_EMPTY          = Color3.fromRGB(50,  220, 80)
local COLOR_OWN            = Color3.fromRGB(80,  150, 255)
local FILL_TRANSPARENCY    = 0.35
local OUTLINE_TRANSPARENCY = 0
local UPDATE_RATE          = 2

-- ============================================================
-- FOLDER ESP
-- ============================================================
local espFolder = Workspace:FindFirstChild("__ESP_SLOTS")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "__ESP_SLOTS"

-- slotData[key] = { highlight = Highlight, placeholder = Part|nil }
local slotData = {}

-- ============================================================
-- HELPERS
-- ============================================================
local function isMyPlot(plot)
    local v = plot:FindFirstChild("Owner", true)
    if not v then return false end
    if v:IsA("ObjectValue") and v.Value and v.Value:IsA("Player") then
        return v.Value.UserId == LocalPlayer.UserId
    elseif v:IsA("StringValue") then
        return v.Value == LocalPlayer.Name or v.Value == tostring(LocalPlayer.UserId)
    end
    return false
end

local function isOccupied(pod)
    if not pod then return false end
    -- un slot est occupé s'il contient un Model (l'animal)
    for _, c in ipairs(pod:GetChildren()) do
        if c:IsA("Model") then return true end
    end
    return false
end

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
    for _, d in ipairs(pod:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function makeHighlight(adornee, color)
    local h = Instance.new("SelectionBox")
    h.Adornee        = adornee
    h.Color3         = color
    h.SurfaceColor3  = color
    h.SurfaceTransparency = FILL_TRANSPARENCY
    h.LineThickness  = 0.05
    h.Parent         = Workspace
    return h
end

local function makePlaceholder(pos)
    local p = Instance.new("Part")
    p.Anchored   = true
    p.CanCollide = false
    p.CanTouch   = false
    p.CastShadow = false
    p.Size       = Vector3.new(5, 0.2, 5)
    p.CFrame     = CFrame.new(pos)
    p.Transparency = 1
    p.Parent     = espFolder
    return p
end

local function removeSlot(key)
    local d = slotData[key]
    if not d then return end
    if d.highlight   then d.highlight:Destroy() end
    if d.placeholder then d.placeholder:Destroy() end
    slotData[key] = nil
end

-- ============================================================
-- SCAN
-- ============================================================
local function scanPlot(plot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    local myPlot  = isMyPlot(plot)
    local seen    = {}

    -- Collecter les positions réelles des slots existants par étage (0,1,2)
    -- pour pouvoir extrapoler les slots manquants au bon endroit
    local floorPositions = {}  -- floor index → liste de positions Y
    local floorBases     = {}  -- floor index → position XZ de référence
    if podiums then
        for _, pod in ipairs(podiums:GetChildren()) do
            local slotNum = tonumber(pod.Name)
            if slotNum then
                local floorIdx = math.floor((slotNum - 1) / 9)
                local part = getSlotPart(pod)
                if part then
                    local pos = part.Position
                    if not floorPositions[floorIdx] then
                        floorPositions[floorIdx] = {}
                        floorBases[floorIdx] = pos
                    end
                    table.insert(floorPositions[floorIdx], pos)
                end
            end
        end
    end

    -- hauteur moyenne par étage
    local floorY = {}
    for fi, positions in pairs(floorPositions) do
        local sum = 0
        for _, p in ipairs(positions) do sum = sum + p.Y end
        floorY[fi] = sum / #positions
    end

    -- si l'étage 0 existe, on peut extrapoler les autres
    local baseY   = floorY[0] or 0
    local floorH  = (floorY[1] and floorY[0]) and (floorY[1] - floorY[0]) or 4
    -- position XZ de référence (étage 0 ou pivot du plot)
    local refPos  = Vector3.new(0, 0, 0)
    pcall(function() refPos = plot:GetPivot().Position end)
    if floorBases[0] then
        refPos = Vector3.new(floorBases[0].X, refPos.Y, floorBases[0].Z)
    end

    for slot = 1, TOTAL_SLOTS do
        local key = plot.Name .. "_" .. slot
        seen[key] = true

        local pod  = podiums and podiums:FindFirstChild(tostring(slot))
        local part = getSlotPart(pod)

        local color = myPlot and COLOR_OWN
                   or (isOccupied(pod) and COLOR_OCCUPIED or COLOR_EMPTY)

        local d = slotData[key]

        if part then
            if d then
                if d.placeholder then
                    d.placeholder:Destroy()
                    d.highlight:Destroy()
                    slotData[key] = { highlight = makeHighlight(part, color), placeholder = nil }
                else
                    d.highlight.Color3        = color
                    d.highlight.SurfaceColor3 = color
                    d.highlight.Adornee       = part
                end
            else
                slotData[key] = { highlight = makeHighlight(part, color), placeholder = nil }
            end
        else
            -- placeholder : position calculée sur la grille 9×3
            local col     = (slot - 1) % 9
            local floorIdx = math.floor((slot - 1) / 9)
            local y       = (floorY[floorIdx] or (baseY + floorIdx * floorH))
            local pos     = Vector3.new(
                refPos.X + (col - 4) * 6,
                y,
                refPos.Z
            )

            if d then
                d.highlight.Color3        = color
                d.highlight.SurfaceColor3 = color
                if d.placeholder then
                    d.placeholder.CFrame = CFrame.new(pos)
                end
            else
                local ph = makePlaceholder(pos)
                slotData[key] = { highlight = makeHighlight(ph, color), placeholder = ph }
            end
        end
    end

    -- nettoyer les slots de ce plot qui ne sont plus dans seen
    for key in pairs(slotData) do
        local prefix = plot.Name .. "_"
        if key:sub(1, #prefix) == prefix and not seen[key] then
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
task.wait(2)
pcall(scanAll)

task.spawn(function()
    while espFolder.Parent do
        task.wait(UPDATE_RATE)
        pcall(scanAll)
    end
end)

local plots = Workspace:WaitForChild("Plots", 10)
if plots then
    plots.ChildAdded:Connect(function(p)
        task.wait(0.5)
        pcall(scanPlot, p)
    end)
    plots.ChildRemoved:Connect(function(p)
        local prefix = p.Name .. "_"
        for key in pairs(slotData) do
            if key:sub(1, #prefix) == prefix then
                removeSlot(key)
            end
        end
    end)
end

print("[ESP SLOTS] actif")
