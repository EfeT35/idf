-- ============================================================
-- INSTANT STEAL - Minimal Self-Contained Script
-- Extracted from HAZE hub. Instant Steal is always ON.
-- Fires fireproximityprompt on the nearest steal prompt
-- within INSTANT_STEAL_RADIUS studs every Heartbeat tick.
-- ============================================================

if not game:IsLoaded() then game.Loaded:Wait() end

-- ============================================================
-- SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============================================================
-- REQUIRE GAME MODULES (async, script continues while loading)
-- ============================================================
local Synchronizer, AnimalsData, AnimalsShared, NumberUtils

task.spawn(function()
    local Packages = ReplicatedStorage:WaitForChild("Packages")
    local Datas    = ReplicatedStorage:WaitForChild("Datas")
    local Shared   = ReplicatedStorage:WaitForChild("Shared")
    local Utils    = ReplicatedStorage:WaitForChild("Utils")

    Synchronizer  = require(Packages:WaitForChild("Synchronizer"))
    AnimalsData   = require(Datas:WaitForChild("Animals"))
    AnimalsShared = require(Shared:WaitForChild("Animals"))
    NumberUtils   = require(Utils:WaitForChild("NumberUtils"))
end)

-- ============================================================
-- CACHE / STATE
-- ============================================================
local allAnimalsCache   = {}
local PromptMemoryCache  = {}
local lastAnimalData    = {}

-- Instant Steal is always enabled — no toggle.
local instantStealReady   = false
local instantStealDidInit = false

-- ============================================================
-- HELPERS
-- ============================================================
local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Returns true if this plot belongs to the local player
-- (checks PlotSign YourBase BillboardGui).
local function isMyPlot_Instant(plotName)
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(plotName)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if not sign then return false end
    local yb = sign:FindFirstChild("YourBase")
    return yb and yb:IsA("BillboardGui") and yb.Enabled
end

-- Returns true if an animal's plot is owned by the local player
-- (uses Synchronizer channel Owner field).
local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    if not Synchronizer then return false end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    local ok, channel = pcall(function() return Synchronizer:Get(plot.Name) end)
    if not ok or not channel then return false end
    local owner = channel:Get("Owner")
    if owner then
        if typeof(owner) == "Instance" and owner:IsA("Player") then
            return owner.UserId == LocalPlayer.UserId
        elseif typeof(owner) == "table" and owner.UserId then
            return owner.UserId == LocalPlayer.UserId
        elseif typeof(owner) == "Instance" then
            return owner == LocalPlayer
        end
    end
    return false
end

-- ============================================================
-- FIND NEAREST STEAL PROMPT (direct workspace scan)
-- ============================================================
local INSTANT_STEAL_RADIUS = 60

local function findNearestPrompt_Instant()
    local hrp = getHRP()
    if not hrp then return nil, math.huge, nil end
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil, math.huge, nil end

    local bestPrompt, bestDist, bestName = nil, math.huge, nil

    for _, plot in ipairs(plots:GetChildren()) do
        if isMyPlot_Instant(plot.Name) then continue end

        local plotDist = math.huge
        pcall(function() plotDist = (plot:GetPivot().Position - hrp.Position).Magnitude end)
        if plotDist > INSTANT_STEAL_RADIUS + 40 then continue end

        local podiums = plot:FindFirstChild("AnimalPodiums")
        if not podiums then continue end

        for _, pod in ipairs(podiums:GetChildren()) do
            local base  = pod:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn")
            if not spawn then continue end

            local dist = (spawn.Position - hrp.Position).Magnitude
            if dist > INSTANT_STEAL_RADIUS or dist >= bestDist then continue end

            local att = spawn:FindFirstChild("PromptAttachment")
            if not att then continue end

            local prompt = att:FindFirstChildOfClass("ProximityPrompt")
            if prompt and prompt.Parent and prompt.Enabled then
                bestPrompt = prompt
                bestDist   = dist
                bestName   = pod.Name
            end
        end
    end

    return bestPrompt, bestDist, bestName
end

-- ============================================================
-- EXECUTE INSTANT STEAL
-- ============================================================
local function executeInstantSteal(prompt)
    if not prompt or not prompt.Parent then return end
    pcall(function() fireproximityprompt(prompt, 0) end)
end

-- ============================================================
-- PLOT SCANNING → allAnimalsCache
-- (Provides a sorted cache used by the fallback steal path)
-- ============================================================
local function getAnimalHash(al, ownerName)
    if not al then return "" end
    local h = ownerName or ""
    for slot, d in pairs(al) do
        if type(d) == "table" then
            h = h .. tostring(slot) .. tostring(d.Index) .. tostring(d.Mutation)
        end
    end
    return h
end

local function scanSinglePlot(plot)
    if not Synchronizer or not AnimalsData or not AnimalsShared or not NumberUtils then return end
    pcall(function()
        local ch = Synchronizer:Get(plot.Name)
        if not ch then return end

        local al    = ch:Get("AnimalList")
        local owner = ch:Get("Owner")

        -- Remove entries for plots with no online owner or no animals
        if not owner or not owner.Name or not Players:FindFirstChild(owner.Name) then
            lastAnimalData[plot.Name] = nil
            for i = #allAnimalsCache, 1, -1 do
                if allAnimalsCache[i].plot == plot.Name then
                    table.remove(allAnimalsCache, i)
                end
            end
            return
        end

        if not al then
            lastAnimalData[plot.Name] = nil
            for i = #allAnimalsCache, 1, -1 do
                if allAnimalsCache[i].plot == plot.Name then
                    table.remove(allAnimalsCache, i)
                end
            end
            return
        end

        local ownerName = owner.Name
        local hash = getAnimalHash(al, ownerName)
        if lastAnimalData[plot.Name] == hash then return end

        -- Remove stale entries for this plot
        for i = #allAnimalsCache, 1, -1 do
            if allAnimalsCache[i].plot == plot.Name then
                table.remove(allAnimalsCache, i)
            end
        end

        -- Insert fresh entries
        for slot, ad in pairs(al) do
            if type(ad) == "table" then
                local aName = ad.Index
                local aInfo = AnimalsData[aName]
                if aInfo then
                    local mut = ad.Mutation or "None"
                    if mut == "Yin Yang" then mut = "YinYang" end
                    local gv = AnimalsShared:GetGeneration(aName, ad.Mutation, ad.Traits, nil)
                    local gt = "$" .. NumberUtils:ToString(gv) .. "/s"
                    table.insert(allAnimalsCache, {
                        name     = aInfo.DisplayName or aName,
                        genText  = gt,
                        genValue = gv,
                        mutation = mut,
                        owner    = ownerName,
                        plot     = plot.Name,
                        slot     = tostring(slot),
                        uid      = plot.Name .. "_" .. tostring(slot),
                    })
                end
            end
        end

        lastAnimalData[plot.Name] = hash
        table.sort(allAnimalsCache, function(a, b) return a.genValue > b.genValue end)
    end)
end

local function setupPlotListener(plot)
    if not Synchronizer then return end
    local ch, retries = nil, 0
    while not ch and retries < 50 do
        local ok, r = pcall(function() return Synchronizer:Get(plot.Name) end)
        if ok and r then ch = r; break else retries = retries + 1; task.wait(0.1) end
    end
    if not ch then return end
    scanSinglePlot(plot)
    plot.DescendantAdded:Connect(function()    task.wait(0.1); scanSinglePlot(plot) end)
    plot.DescendantRemoving:Connect(function() task.wait(0.1); scanSinglePlot(plot) end)
    task.spawn(function()
        while plot.Parent do task.wait(5); scanSinglePlot(plot) end
    end)
end

-- ============================================================
-- FIND PROXIMITY PROMPT VIA SLOT (PromptMemoryCache fallback)
-- ============================================================
local function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end
    local cp = PromptMemoryCache[animalData.uid]
    if cp and cp.Parent then return cp end

    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    local plot = plotsFolder:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end

    -- Direct slot lookup
    local foundPodium = podiums:FindFirstChild(animalData.slot)

    -- Synchronizer-based slot cross-reference (in case slot key drifted)
    if not foundPodium and Synchronizer then
        pcall(function()
            local ch = Synchronizer:Get(plot.Name)
            if not ch then return end
            local al = ch:Get("AnimalList")
            if not al then return end
            local brainrotName = animalData.name and animalData.name:lower() or ""
            for slot, ad in pairs(al) do
                if type(ad) == "table" and tostring(slot) == animalData.slot then
                    local aName = ad.Index
                    local aInfo = AnimalsData and AnimalsData[aName]
                    if aInfo and (aInfo.DisplayName or aName):lower() == brainrotName then
                        foundPodium = podiums:FindFirstChild(tostring(slot))
                        break
                    end
                end
            end
        end)
    end

    if not foundPodium then return nil end

    local base  = foundPodium:FindFirstChild("Base")
    local spawn = base and base:FindFirstChild("Spawn")
    if not spawn then return nil end

    -- Try PromptAttachment first
    local attach = spawn:FindFirstChild("PromptAttachment")
    if attach then
        for _, p in ipairs(attach:GetChildren()) do
            if p:IsA("ProximityPrompt") and p.Enabled then
                PromptMemoryCache[animalData.uid] = p
                return p
            end
        end
    end

    -- Spatial fallback: find nearest enabled ProximityPrompt above spawn.Y
    local startPos = spawn.Position
    local nearestPrompt, minDist = nil, math.huge
    for _, desc in pairs(plot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Enabled then
            local part = desc.Parent
            local promptPos = nil
            if part and part:IsA("BasePart") then
                promptPos = part.Position
            elseif part and part:IsA("Attachment") and part.Parent and part.Parent:IsA("BasePart") then
                promptPos = part.Parent.Position
            end
            if promptPos then
                local hDist = math.sqrt((promptPos.X - startPos.X)^2 + (promptPos.Z - startPos.Z)^2)
                if hDist < 5 and promptPos.Y > startPos.Y then
                    local yDist = promptPos.Y - startPos.Y
                    if yDist < minDist then
                        minDist = yDist
                        nearestPrompt = desc
                    end
                end
            end
        end
    end

    if nearestPrompt then
        PromptMemoryCache[animalData.uid] = nearestPrompt
        return nearestPrompt
    end

    return nil
end

-- ============================================================
-- FILTERED PET LIST (excludes own base, sorted by gen value)
-- ============================================================
local function get_all_pets()
    local out = {}
    for _, a in ipairs(allAnimalsCache) do
        if a.genValue >= 1 and not isMyBaseAnimal(a) then
            table.insert(out, {
                petName    = a.name,
                mpsText    = a.genText,
                mpsValue   = a.genValue,
                owner      = a.owner,
                plot       = a.plot,
                slot       = a.slot,
                uid        = a.uid,
                mutation   = a.mutation,
                animalData = a,
            })
        end
    end
    return out
end

-- ============================================================
-- STARTUP: wait for modules, then wire up plot scanning
-- ============================================================
task.spawn(function()
    local timeout = os.clock() + 20
    while not Synchronizer or not AnimalsData or not AnimalsShared or not NumberUtils do
        if os.clock() > timeout then
            warn("[InstantSteal] Timed out waiting for game modules — plot cache disabled.")
            return
        end
        task.wait(0.2)
    end

    local plots = Workspace:WaitForChild("Plots", 10)
    if not plots then
        warn("[InstantSteal] Could not find Plots folder.")
        return
    end

    for _, p in ipairs(plots:GetChildren()) do
        task.spawn(setupPlotListener, p)
    end

    plots.ChildAdded:Connect(function(p)
        task.wait(0.5)
        task.spawn(setupPlotListener, p)
    end)

    plots.ChildRemoved:Connect(function(p)
        lastAnimalData[p.Name] = nil
        for i = #allAnimalsCache, 1, -1 do
            if allAnimalsCache[i].plot == p.Name then
                table.remove(allAnimalsCache, i)
            end
        end
    end)
end)

-- ============================================================
-- HEARTBEAT: Instant Steal loop (always active, no toggle)
-- ============================================================
local lastInstantTick = 0

RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastInstantTick < 0.05 then return end
    lastInstantTick = now

    -- One-time delayed init: give game a moment before first steal
    if not instantStealDidInit then
        instantStealDidInit = true
        task.spawn(function()
            if not game:IsLoaded() then game.Loaded:Wait() end
            task.wait(0.5)
            instantStealReady = true
        end)
    end

    if not instantStealReady then return end

    -- Primary: fire nearest prompt found by direct workspace scan
    local prompt, dist, _ = findNearestPrompt_Instant()
    if prompt and dist <= INSTANT_STEAL_RADIUS then
        executeInstantSteal(prompt)
        return
    end

    -- Fallback: use allAnimalsCache + PromptMemoryCache (highest gen-value pet)
    local pets = get_all_pets()
    if #pets == 0 then return end
    local tp = pets[1]
    if not tp then return end

    local pr = PromptMemoryCache[tp.uid]
    if not pr or not pr.Parent then
        pr = findProximityPromptForAnimal(tp.animalData)
    end
    if pr then
        executeInstantSteal(pr)
    end
end)
