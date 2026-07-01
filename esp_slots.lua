if not game:IsLoaded() then game.Loaded:Wait() end

local Workspace = game:GetService("Workspace")

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

local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- FOLDER ESP
-- ============================================================
local espFolder = Workspace:FindFirstChild("__ESP_SLOTS")
if espFolder then espFolder:Destroy() end
espFolder = Instance.new("Folder", Workspace)
espFolder.Name = "__ESP_SLOTS"

local slotHighlights = {}  -- key -> Highlight

-- ============================================================
-- HELPERS
-- ============================================================
local function getOwner(plot)
    -- cherche un StringValue ou ObjectValue "Owner" n'importe où dans le plot
    local v = plot:FindFirstChild("Owner", true)
    if v then
        if v:IsA("ObjectValue") and v.Value and v.Value:IsA("Player") then
            return v.Value
        elseif v:IsA("StringValue") then
            return v.Value
        end
    end
    return nil
end

local function isMyPlot(plot)
    local owner = getOwner(plot)
    if not owner then return false end
    if typeof(owner) == "Instance" and owner:IsA("Player") then
        return owner.UserId == LocalPlayer.UserId
    elseif type(owner) == "string" then
        return owner == LocalPlayer.Name or owner == tostring(LocalPlayer.UserId)
    end
    return false
end

-- trouve le premier BasePart dans un podium
local function getSlotPart(pod)
    if not pod then return nil end
    -- cherche Base/Spawn en priorité
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

local function makePlaceholderPart(pos)
    local p = Instance.new("Part")
    p.Anchored    = true
    p.CanCollide  = false
    p.CanTouch    = false
    p.CastShadow  = false
    p.Size        = Vector3.new(5, 0.2, 5)
    p.CFrame      = CFrame.new(pos)
    p.Transparency = 1
    p.Parent      = espFolder
    return p
end

-- ============================================================
-- SCAN
-- ============================================================
local function scanAll()
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end

    local seen = {}

    for _, plot in ipairs(plots:GetChildren()) do
        local ok = pcall(function()
            local myPlot  = isMyPlot(plot)
            local podiums = plot:FindFirstChild("AnimalPodiums")

            -- position de base du plot pour les placeholders
            local plotPos = Vector3.new(0, 0, 0)
            pcall(function() plotPos = plot:GetPivot().Position end)

            for slot = 1, TOTAL_SLOTS do
                local key = plot.Name .. "_" .. slot
                seen[key] = true

                -- déterminer la couleur
                local occupied = false
                if not myPlot and podiums then
                    local pod = podiums:FindFirstChild(tostring(slot))
                    if pod then
                        -- considéré occupé si le podium a des descendants (animal présent)
                        local animalFolder = pod:FindFirstChild("Animal") or pod:FindFirstChild("AnimalModel")
                        if animalFolder and #animalFolder:GetChildren() > 0 then
                            occupied = true
                        elseif pod:FindFirstChildWhichIsA("Model") then
                            occupied = true
                        end
                    end
                end

                local color = myPlot and COLOR_OWN or (occupied and COLOR_OCCUPIED or COLOR_EMPTY)

                -- trouver la géométrie
                local pod  = podiums and podiums:FindFirstChild(tostring(slot))
                local part = getSlotPart(pod)

                local existing = slotHighlights[key]

                if part then
                    if existing then
                        -- mettre à jour couleur
                        if existing._placeholder then
                            existing._placeholder:Destroy()
                            existing._placeholder = nil
                            existing:Destroy()
                            existing = makeHighlight(part, color)
                            slotHighlights[key] = existing
                        else
                            existing.FillColor    = color
                            existing.OutlineColor = color
                            existing.Adornee      = part
                        end
                    else
                        local h = makeHighlight(part, color)
                        slotHighlights[key] = h
                    end
                else
                    -- pas de géométrie → placeholder
                    local col    = (slot - 1) % 9
                    local row    = math.floor((slot - 1) / 9)
                    local offset = Vector3.new(col * 6 - 24, 0.1 + row * 4, 0)
                    local pos    = plotPos + offset

                    if existing then
                        existing.FillColor    = color
                        existing.OutlineColor = color
                        if existing._placeholder then
                            existing._placeholder.CFrame = CFrame.new(pos)
                        end
                    else
                        local ph = makePlaceholderPart(pos)
                        local h  = makeHighlight(ph, color)
                        h._placeholder = ph
                        slotHighlights[key] = h
                    end
                end
            end
        end)
        if not ok then end
    end

    -- supprimer les highlights d'anciens plots
    for key, h in pairs(slotHighlights) do
        if not seen[key] then
            if h._placeholder then h._placeholder:Destroy() end
            h:Destroy()
            slotHighlights[key] = nil
        end
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

print("[ESP SLOTS] actif")
