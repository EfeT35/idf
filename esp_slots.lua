if not game:IsLoaded() then game.Loaded:Wait() end

local Workspace   = game:GetService("Workspace")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- CONFIG
-- ============================================================
local COLOR_OCCUPIED       = Color3.fromRGB(255, 50,  50)
local COLOR_EMPTY          = Color3.fromRGB(50,  220, 80)
local COLOR_OWN            = Color3.fromRGB(80,  150, 255)
local FILL_TRANSPARENCY    = 0.35
local UPDATE_RATE          = 2
local FLOOR_HEIGHT_DEFAULT = 5   -- hauteur entre étages si non détectable

-- ============================================================
-- FOLDER ESP
-- ============================================================
local espFolder = Workspace:FindFirstChild("__ESP_SLOTS")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "__ESP_SLOTS"

-- slotData[key] = { box = SelectionBox, placeholder = Part|nil }
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

local function makeBox(adornee, color)
    local h = Instance.new("SelectionBox")
    h.Adornee         = adornee
    h.Color3          = color
    h.SurfaceColor3   = color
    h.SurfaceTransparency = FILL_TRANSPARENCY
    h.LineThickness   = 0.05
    h.Parent          = Workspace
    return h
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
    local d = slotData[key]
    if not d then return end
    if d.box         then d.box:Destroy() end
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

    -- Collecter les CFrames et tailles réelles des slots du 1er étage (1-9)
    local floor0 = {}  -- slot local (1-9) → { cf=CFrame, size=Vector3 }
    if podiums then
        for slot = 1, 9 do
            local pod  = podiums:FindFirstChild(tostring(slot))
            local part = getSlotPart(pod)
            if part then
                floor0[slot] = { cf = part.CFrame, size = part.Size }
            end
        end
    end

    -- Détecter la hauteur entre étages depuis les vrais slots
    local floorHeight = FLOOR_HEIGHT_DEFAULT
    if podiums then
        -- chercher un slot d'étage 2 (10-18) pour mesurer la hauteur
        for slot = 10, 18 do
            local pod  = podiums:FindFirstChild(tostring(slot))
            local part = getSlotPart(pod)
            local ref  = floor0[slot - 9]
            if part and ref then
                floorHeight = math.abs(part.Position.Y - ref.cf.Position.Y)
                if floorHeight > 0.5 then break end
            end
        end
    end

    for slot = 1, 27 do
        local key = plot.Name .. "_" .. slot
        seen[key] = true

        local floorIdx  = math.floor((slot - 1) / 9)   -- 0, 1 ou 2
        local localSlot = ((slot - 1) % 9) + 1          -- 1-9

        local pod  = podiums and podiums:FindFirstChild(tostring(slot))
        local part = getSlotPart(pod)

        local color = myPlot and COLOR_OWN
                   or (isOccupied(pod) and COLOR_OCCUPIED or COLOR_EMPTY)

        local d = slotData[key]

        if part then
            -- slot avec géométrie réelle
            if d then
                if d.placeholder then
                    d.placeholder:Destroy()
                    d.box:Destroy()
                    slotData[key] = { box = makeBox(part, color), placeholder = nil }
                else
                    d.box.Color3        = color
                    d.box.SurfaceColor3 = color
                    d.box.Adornee       = part
                end
            else
                slotData[key] = { box = makeBox(part, color), placeholder = nil }
            end
        else
            -- slot sans géométrie : dupliquer la position du slot correspondant
            -- au rez-de-chaussée (floor0) décalée vers le haut
            local ref = floor0[localSlot]
            if ref then
                local newCF   = ref.cf + Vector3.new(0, floorHeight * floorIdx, 0)
                local newSize = ref.size

                if d then
                    d.box.Color3        = color
                    d.box.SurfaceColor3 = color
                    if d.placeholder then
                        d.placeholder.CFrame = newCF
                        d.placeholder.Size   = newSize
                    end
                else
                    local ph = makePlaceholder(newCF, newSize)
                    slotData[key] = { box = makeBox(ph, color), placeholder = ph }
                end
            end
            -- si pas de ref floor0 non plus → on skip ce slot
        end
    end

    -- nettoyer les anciens slots
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
