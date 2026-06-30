local __HAZE_WATERMARK = "HAZE_WM_daf3ce73bf93696fbb5e"
    -- ================= KICK =================
    local Players = game:GetService("Players")
    local player = Players.LocalPlayer

if not game:IsLoaded() then game.Loaded:Wait() end
pcall(function() game:GetService("Players").RespawnTime = 0 end)
local privateBuild = false


-- ============================================================
-- ESTADO GENERAL DEL SCRIPT
-- ============================================================
local SharedState = {
    SelectedPetData = nil,
    AllAnimalsCache = nil,
    DisableStealSpeed = nil,
    ListNeedsRedraw = true,
    AdminButtonCache = {},
    StealSpeedToggleFunc = nil,
    _ssUpdateBtn = nil,
    AdminProxBtn = nil,
    BalloonedPlayers = {},
    MobileScaleObjects = {},
    RefreshMobileScale = nil,
    MobileActionButtons = {},
    RefreshMobileActionButtons = nil,
}

do
-- SOURCE: :contentReference[oaicite:0]{index=0}
-- ITSB HUB v5 - TRUE INSTANT STEAL (BRAINROT DETECTOR + BOX FILTER)
-- MOD: SOLO ROBA PROMPTS QUE ESTÉN EN EL MISMO CUADRO (BOX) QUE EL JUGADOR
-- VERSION SIN UI

local CONFIG = {
    AUTO_STEAL = false,
    RADIUS = 12
}

local boxes = {
    {min = Vector3.new(-337.448303, -3.898971, -122.397758), max = Vector3.new(-328.004578, -3.898971, 242.625626)},
    {min = Vector3.new(-327.257660, -3.899109, -122.228622), max = Vector3.new(-320.600891, -3.899109, 242.612259)},
    {min = Vector3.new(-319.783386, -3.898970, -122.227089), max = Vector3.new(-312.908325, -3.898970, 242.585617)},
    {min = Vector3.new(-312.445648, -3.899108, -122.389832), max = Vector3.new(-305.489899, -3.899108, 242.456818)},
    {min = Vector3.new(-305.037048, -3.898970, -122.230743), max = Vector3.new(-293.957489, -3.898970, 242.606873)},
    {min = Vector3.new(-491.448608, -3.898972, -122.253258), max = Vector3.new(-481.811737, -3.898972, 242.615005)},
    {min = Vector3.new(-498.971069, -3.898970, -122.382767), max = Vector3.new(-491.748840, -3.898970, 242.612061)},
    {min = Vector3.new(-506.436737, -3.898972, -122.411476), max = Vector3.new(-499.318542, -3.898972, 242.615982)},
    {min = Vector3.new(-513.783569, -3.898972, -122.223297), max = Vector3.new(-506.801849, -3.898972, 242.627090)},
    {min = Vector3.new(-525.236938, -3.898972, -122.409813), max = Vector3.new(-514.265015, -3.898972, 242.608932)},
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local trackedPrompts = {}
local lastFire = {}

local SAFE_POLL_RATE = 0.10
local SAFE_POLL_OVERRIDE_UNTIL = 0

function _G.getSafePollRate()
    if os.clock() < SAFE_POLL_OVERRIDE_UNTIL then
        return 0.27
    end
    return SAFE_POLL_RATE
end

function _G.triggerSafePollBoost()
    SAFE_POLL_OVERRIDE_UNTIL = os.clock() + 3
end

local FIRE_DEBOUNCE = 0.08
local FIRE_BURST = 2

local ENABLE_BURST = 25
local ENABLE_DEBOUNCE = 0.00
local ENABLE_COOLDOWN = 0.08

local lastEnableFire = {}

------------------------------------------------
-- CHARACTER
------------------------------------------------
local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------
-- BOX DETECTION
------------------------------------------------
local function getBoxIndex(pos)
    for i,b in ipairs(boxes) do
        if pos.X >= math.min(b.min.X,b.max.X) and pos.X <= math.max(b.min.X,b.max.X)
        and pos.Z >= math.min(b.min.Z,b.max.Z) and pos.Z <= math.max(b.min.Z,b.max.Z) then
            return i
        end
    end
end

------------------------------------------------
-- SAFE POSITION GET
------------------------------------------------
local function getPromptPosition(prompt)
    local p = prompt.Parent
    if not p then return end

    if p:IsA("Attachment") and p.Parent then
        p = p.Parent
    end

    if p:IsA("BasePart") then
        return p.Position
    elseif p:IsA("Model") then
        return p:GetPivot().Position
    end
end

------------------------------------------------
-- AVAILABLE CHECK
------------------------------------------------
local function promptMatchesSelectedPet(prompt)
    if not SharedState then return false end

    local selected = SharedState.SelectedPetData
    if not selected then return false end

    local model = prompt:FindFirstAncestorOfClass("Model")
    if not model then return false end

    if selected.slot then
        local slotAncestor = prompt:FindFirstAncestor(selected.slot)
        if slotAncestor then
            return true
        end

        if model.Name == selected.slot then
            return true
        end

        if model.Parent and model.Parent.Name == selected.slot then
            return true
        end
    end

    if selected.name then
        local wantedName = string.lower(selected.name)
        local current = model

        while current do
            if current.Name and string.lower(current.Name) == wantedName then
                return true
            end
            current = current.Parent
        end
    end

    return false
end

local function isPromptAvailable(prompt, hrpPos)
    if not prompt or not prompt.Parent then return false end
    if not prompt.Enabled then return false end

    local pos = getPromptPosition(prompt)
    if not pos then return false end

-- NO ROBAR PROMPTS DE MI PROPIO PLOT
local plot = prompt:FindFirstAncestorOfClass("Model")
if plot then
    local plots = workspace:FindFirstChild("Plots")
    if plots then
        local parentPlot = prompt:FindFirstAncestorWhichIsA("Model")
        while parentPlot and parentPlot.Parent ~= plots do
            parentPlot = parentPlot.Parent
        end

        if parentPlot then
            local sign = parentPlot:FindFirstChild("PlotSign")
            if sign then
                local gui = sign:FindFirstChildWhichIsA("SurfaceGui", true)
                local label = gui and gui:FindFirstChildWhichIsA("TextLabel", true)

                if label then
                    local txt = label.Text:lower()
                    if txt:find(game.Players.LocalPlayer.Name:lower(), 1, true)
                    or txt:find(game.Players.LocalPlayer.DisplayName:lower(), 1, true) then
                        return false
                    end
                end
            end
        end
    end
end

-- SOLO NEAREST RESPETA BOXES
if _G.NEAREST_INSTANT_MODE == true then
    local playerBox = getBoxIndex(hrpPos)
    local promptBox = getBoxIndex(pos)

    if not playerBox or playerBox ~= promptBox then
        return false
    end
end

-- SI ESTA EN NEAREST + INSTANT STEAL NO USAR TABLA
if not (_G.NEAREST_INSTANT_MODE == true) then
    if not promptMatchesSelectedPet(prompt) then
        return false
    end
end

    local maxDist = (typeof(prompt.MaxActivationDistance) == "number" and prompt.MaxActivationDistance > 0)
        and prompt.MaxActivationDistance
        or CONFIG.RADIUS

    local effective = math.min(CONFIG.RADIUS, maxDist)

    return (pos - hrpPos).Magnitude <= effective
end

------------------------------------------------
-- FIRE
------------------------------------------------
local function canFire(prompt, debounce)
    local t = os.clock()
    local last = lastFire[prompt]
    if last and (t - last) < debounce then
        return false
    end
    lastFire[prompt] = t
    return true
end

local function firePrompt(prompt, burst, debounce)
    if not prompt or not prompt.Parent then return end
    if not prompt.Enabled then return end
    if not canFire(prompt, debounce) then return end

    for i = 1, burst do
        pcall(function()
            fireproximityprompt(prompt, 0)
        end)
    end
end

------------------------------------------------
-- PROMPT TRACK
------------------------------------------------
local function trackPrompt(prompt)
    if trackedPrompts[prompt] then return end
    trackedPrompts[prompt] = true

    local function tryInstantEnableFire()
        local hrp = getHRP()
        if not hrp then return end
        local myPos = hrp.Position

        if isPromptAvailable(prompt, myPos) then
            CONFIG.AUTO_STEAL = true

            local now = os.clock()
            local le = lastEnableFire[prompt]

            if not le or (now - le) >= ENABLE_COOLDOWN then
                lastEnableFire[prompt] = now
                firePrompt(prompt, ENABLE_BURST, ENABLE_DEBOUNCE)
            end
        end
    end

    task.defer(function()
        tryInstantEnableFire()
    end)

    pcall(function()
        prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
            if prompt.Enabled then
                tryInstantEnableFire()
            end
        end)
    end)

    prompt.AncestryChanged:Connect(function()
        if not prompt:IsDescendantOf(workspace) then
            trackedPrompts[prompt] = nil
            lastFire[prompt] = nil
            lastEnableFire[prompt] = nil
        end
    end)
end

------------------------------------------------
-- SCAN
------------------------------------------------
local function scanBrainrotPrompts()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    for _, plot in ipairs(plots:GetChildren()) do
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if podiums then
            for _, obj in ipairs(podiums:GetDescendants()) do
                if obj:IsA("ProximityPrompt") then
                    trackPrompt(obj)
                end
            end
        end
    end
end

scanBrainrotPrompts()

workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("ProximityPrompt") and obj:FindFirstAncestor("AnimalPodiums") then
        trackPrompt(obj)
    end
end)

------------------------------------------------
-- BACKUP LOOP
------------------------------------------------
task.spawn(function()
    while task.wait(_G.getSafePollRate()) do

        local hrp = getHRP()

        if not hrp then
            CONFIG.AUTO_STEAL = false
            continue
        end

        local myPos = hrp.Position
        local anyAvailable = false

        for prompt in pairs(trackedPrompts) do
            if isPromptAvailable(prompt, myPos) then
                anyAvailable = true

                if CONFIG.AUTO_STEAL then
                    firePrompt(prompt, FIRE_BURST, FIRE_DEBOUNCE)
                end
            end
        end

        CONFIG.AUTO_STEAL = anyAvailable
    end
end)

end

-- ============================================================
-- SYNC
-- ============================================================
do

    local Sync = require(game.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Synchronizer"))
    local patched = 0

    for name, fn in pairs(Sync) do
        if typeof(fn) ~= "function" then continue end
        if isexecutorclosure(fn) then continue end

        local ok, ups = pcall(debug.getupvalues, fn)
        if not ok then continue end

        for idx, val in pairs(ups) do
            if typeof(val) == "function" and not isexecutorclosure(val) then
                local ok2, innerUps = pcall(debug.getupvalues, val)
                if ok2 then
                    local hasBoolean = false
                    for _, v in pairs(innerUps) do
                        if typeof(v) == "boolean" then
                            hasBoolean = true
                            break
                        end
                    end
                    if hasBoolean then
                        debug.setupvalue(fn, idx, newcclosure(function() end))
                        patched += 1
                    end
                end
            end
        end
    end
    print("MOGGED BY HAZE")
end

-- ============================================================
-- SERVICIOS DE ROBLOX
-- ============================================================
local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    UserInputService = game:GetService("UserInputService"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    TweenService = game:GetService("TweenService"),
    HttpService = game:GetService("HttpService"),
    Workspace = game:GetService("Workspace"),
    Lighting = game:GetService("Lighting"),
    VirtualInputManager = game:GetService("VirtualInputManager"),
    GuiService = game:GetService("GuiService"),
    TeleportService = game:GetService("TeleportService"),
}
local Players = Services.Players
local RunService = Services.RunService
local UserInputService = Services.UserInputService
local ReplicatedStorage = Services.ReplicatedStorage
local TweenService = Services.TweenService
local HttpService = Services.HttpService
local Workspace = Services.Workspace
local Lighting = Services.Lighting
local VirtualInputManager = Services.VirtualInputManager
local GuiService = Services.GuiService
local TeleportService = Services.TeleportService
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")


-- ======================================================
-- FLASH TP (logique portee depuis IDF)
-- ======================================================
do
local LP             = LocalPlayer
local RS             = ReplicatedStorage
local PathfindingService = game:GetService("PathfindingService")

-- =====================================================================
-- FlashExtra config
-- =====================================================================
local FlashExtra = {
    tpPriorityEnabled = false,
    tpHighestEnabled  = false,
    tpMinMPS          = 0,
    floor2AsFloor1    = false,
    tpFpsGate         = 0,
    skyCloneWait      = 0.28,
    cloneDelay        = 0.15,
    wallAnchorWait    = 0.10,
    tpSpeed           = 400,
    brainrotSnapSpeed = 300,
    walkDuration      = 0.05,
    walkSettle        = 0.05,
    walkDuration2     = 0,
    walkSettle2       = 0,
    tpTool            = "",
    priorityList      = {
        "Headless Horseman","Signore Carapace","Elefanto Frigo","Arcadragon",
        "Strawberry Elephant","Antonio","John Pork","Meowl","Love Love Bear",
        "Skibidi Toilet","Ginger Gerat","Griffin","Dragon Gingerini",
        "Fishino Clownino","La Supreme Combinasion","Digi Narwhal",
        "Dragon Cannelloni","Hydra Dragon Cannelloni","Ketupat Bros",
        "La Casa Boo","Hydra Bunny","Duggy Bros","Bunny and Eggy","Cerberus",
        "Celestial Pegasus","Rosey and Teddy","Reinito Sleighito",
        "Capitano Moby","Los Sekolahs","Fragrama and Chocrama",
        "Spooky and Pumpky","Cooki and Milki","La Food Combinasion",
        "Los Amigos","Burguro And Fryuro","Popcuru and Fizzuru",
        "Garama and Madundung","La Secret Combinasion","La Romantic Grande",
        "La Taco Combinasion","Los Spaghettis","Swaggy Bros","Sammyni Fattini",
        "Festive 67","Ketchuru and Musturu","Tang Tang Keletang","Ketupat Kepat",
        "Tictac Sahur","Tralaledon","W or L","Eviledon","Lavadorito Spinito",
        "Spaghetti Tualetti","Foxini Lanternini",
    },
}
_G.FlashExtra = FlashExtra

-- =====================================================================
-- Fusing helper
-- =====================================================================
local _BLOCKING_MACHINE_TYPES = { Fuse=true, Duel=true, Trade=true, Crafting=true }
local function _VanishIsFusing(animalData)
    if type(animalData) ~= "table" then return false end
    local m = animalData.Machine
    if type(m) ~= "table" then return false end
    return _BLOCKING_MACHINE_TYPES[m.Type] == true
end

-- =====================================================================
-- Pet priority tiers
-- =====================================================================
local PET_PRIORITY_TIERS = {
    [1]  = { pets = {"Headless Horseman"},                            threshold = 0 },
    [2]  = { pets = {"Signore Carapace"},                             threshold = 0 },
    [3]  = { pets = {"John Pork"},                                    threshold = 0 },
    [4]  = { pets = {"Strawberry Elephant"},                          threshold = 0 },
    [5]  = { pets = {"Arcadragon"},                                   threshold = 5e9 },
    [6]  = { pets = {"Elefanto Frigo"},                               threshold = 10e9 },
    [7]  = { pets = {"Meowl"},                                        threshold = 5e9 },
    [8]  = { pets = {"Skibidi Toilet"},                               threshold = 5e9 },
    [9]  = { pets = {"Love Love Bear"},                               threshold = 0 },
    [10] = { pets = {"Antonio"},                                      threshold = 0 },
    [11] = { pets = {"Pancake and Syrup"},                            threshold = 0 },
    [12] = { pets = {"Griffin"},                                      threshold = 0 },
    [13] = { pets = {"Globa Steppa","La Supreme Combinasion","Fishino Clownino","Dragon Gingerini","Tirilikalika Tirilikalako"}, threshold = 5e9 },
    [14] = { pets = {"Ginger Gerat","Pet"},                          threshold = 10e9 },
    [15] = { pets = {"Hydra Bunny","Digi Narwhal","Kalika Bros"},     threshold = 3e9 },
    [16] = { pets = {"Hydra Dragon Cannelloni","Dragon Cannelloni","Bunny and Eggy"}, threshold = 3e9 },
    [17] = { pets = {"Ketupat Bros","Rosey and Teddy","La Casa Boo","Fragola la la"}, threshold = 3e9 },
    [18] = { pets = {"Fragola La La La","Cerberus","Guest 666","Los Hackers"}, threshold = 1e9 },
    [19] = { pets = {"Garama and Madundung","Spooky and Pumpky","Reinito Sleighito","Burguro And Fryuro","Cooki and Milki","Fragrama and Chocrama","La Food Combinasion","Los Amigos","Foxini Lanternini","Capitano Moby","Fortunu and Cashuru","Los Sekolahs","Celestial Pegasus"}, threshold = 750e6 },
    [20] = { pets = {"La Secret Combinasion","Sammyni Fattini","Cloverat Clapat","Popcuru and Fizzuru"}, threshold = 1e9 },
}
local TIER_LOOKUP = {}
for tier, data in pairs(PET_PRIORITY_TIERS) do
    for _, name in ipairs(data.pets) do TIER_LOOKUP[name] = tier end
end
local LOCKED_TIERS = { [1]=true, [2]=true, [3]=true, [4]=true }
local DIRECT_THRESHOLDS = {
    [3]  = { [4] = 10e9 },
    [4]  = {},
    [5]  = { [6] = math.huge },
    [6]  = { [9] = math.huge, [10] = math.huge, [12] = 15e9 },
    [10] = { [12] = 20e9 },
    [11] = { [12] = 10e9 },
}
local MUTATION_PRIORITY = {
    ["Galaxy"]=1,["Candy"]=1,["Yin Yang"]=1,["YinYang"]=1,["Divine"]=1,
    ["Cursed"]=1,["Lava"]=1,["Radioactive"]=1,["Cyber"]=1,["Rainbow"]=1,["Bloodrot"]=2,
}
local MUTATED_BEATS_GRIFFIN = {
    ["Fishino Clownino"]=true,["Globa Steppa"]=true,
    ["La Supreme Combinasion"]=true,["Tirilikalika Tirilikalako"]=true,
}

local function getMutPrio(m)
    if not m or m == "" or m == "None" then return 0 end
    if MUTATION_PRIORITY[m] then return MUTATION_PRIORITY[m] end
    local n = tostring(m):lower():gsub("[%s%-_]","")
    if n == "bloodrot" then return 2 end
    if n == "yinyang" or n == "galaxy" or n == "candy" or n == "divine"
        or n == "cursed" or n == "lava" or n == "radioactive" or n == "cyber"
        or n == "rainbow" then return 1 end
    return 0
end

local function getCumThreshold(hi, lo)
    if DIRECT_THRESHOLDS[hi] and DIRECT_THRESHOLDS[hi][lo] then return DIRECT_THRESHOLDS[hi][lo] end
    if LOCKED_TIERS[hi] then return math.huge end
    local total = 0
    for t = hi + 1, lo do
        local td = PET_PRIORITY_TIERS[t]
        if td and td.threshold > 0 then total = total + td.threshold end
    end
    return total
end

local function petOutranks(aName, bName, aMut, bMut, aMPS, bMPS)
    if aName == "Strawberry Elephant" and bName == "John Pork" then return true end
    if aName == "John Pork" and bName == "Strawberry Elephant" then return false end
    if MUTATED_BEATS_GRIFFIN[aName] and bName == "Griffin" and getMutPrio(aMut) >= 1 then return true end
    if aName == "Griffin" and MUTATED_BEATS_GRIFFIN[bName] and getMutPrio(bMut) >= 1 then return false end
    if aName == "Antonio" and bName == "Elefanto Frigo" and getMutPrio(aMut) >= 1 then return true end
    if aName == "Elefanto Frigo" and bName == "Antonio" and getMutPrio(bMut) >= 1 then return false end
    local tA = TIER_LOOKUP[aName] or 99
    local tB = TIER_LOOKUP[bName] or 99
    if not (TIER_LOOKUP[aName] and TIER_LOOKUP[bName]) then
        if tA == tB then return (aMPS or 0) > (bMPS or 0) end
        return tA < tB
    end
    if tA == tB then
        local pA, pB = getMutPrio(aMut), getMutPrio(bMut)
        if pA ~= pB then return pA > pB end
        return (aMPS or 0) > (bMPS or 0)
    end
    if tA == 4 and tB == 3 then return true end
    if tA == 3 and tB == 4 then return false end
    local hi = math.min(tA, tB)
    local lo = math.max(tA, tB)
    local hiMPS = tA < tB and aMPS or bMPS
    local loMPS = tA < tB and bMPS or aMPS
    local cum = getCumThreshold(hi, lo)
    if cum > 0 and cum ~= math.huge then
        if (loMPS or 0) - (hiMPS or 0) > cum then return tA > tB end
    end
    return tA < tB
end

-- =====================================================================
-- Module loaders (AnimalsData, AnimalsShared, NumberUtils)
-- =====================================================================
local FTP_Synchronizer, FTP_AnimalsData, FTP_AnimalsShared, FTP_NumberUtils
local _ftpModulesPackagesRef

local function ftpLoadModules()
    if FTP_Synchronizer and _ftpModulesPackagesRef and _ftpModulesPackagesRef:IsDescendantOf(game) then
        return true
    end
    FTP_Synchronizer, FTP_AnimalsData, FTP_AnimalsShared, FTP_NumberUtils = nil, nil, nil, nil
    local ok = pcall(function()
        local Packages = RS:WaitForChild("Packages", 5)
        local Datas    = RS:WaitForChild("Datas", 5)
        local Shared   = RS:WaitForChild("Shared", 5)
        local Utils    = RS:WaitForChild("Utils", 5)
        FTP_Synchronizer  = require(Packages:WaitForChild("Synchronizer"))
        FTP_AnimalsData   = require(Datas:WaitForChild("Animals"))
        FTP_AnimalsShared = require(Shared:WaitForChild("Animals"))
        FTP_NumberUtils   = require(Utils:WaitForChild("NumberUtils"))
        _ftpModulesPackagesRef = Packages
    end)
    return ok and FTP_Synchronizer ~= nil
end

-- =====================================================================
-- Carpet helpers
-- =====================================================================
local FTP_CARPET_NAMES = { "Flying Carpet", "Cupid's Wings", "Santa's Sleigh", "Witch's Broom", "Magic Carpet" }
_G.CARPET_TOOLS = FTP_CARPET_NAMES

local function ftpFindTool(name)
    local char = LP.Character
    local bp   = LP:FindFirstChild("Backpack")
    return (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
end

local function ftpEquipCarpet()
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local selected = _G.FlashExtra and _G.FlashExtra.tpTool
    if selected and selected ~= "" then
        local t = ftpFindTool(selected)
        if t and t:IsA("Tool") then
            if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
            return selected
        end
    end
    for _, n in ipairs(FTP_CARPET_NAMES) do
        local t = ftpFindTool(n)
        if t and t:IsA("Tool") then
            if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
            return n
        end
    end
    return nil
end

local function ftpCarpetEngage()
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return nil end
    local cn
    local _tc = os.clock()
    repeat
        cn = ftpEquipCarpet()
        local c = LP.Character
        if cn and c and c:FindFirstChild(cn) then break end
        RunService.Heartbeat:Wait()
    until os.clock() - _tc > 1
    return cn
end

-- =====================================================================
-- Plot / channel helpers
-- =====================================================================
local function ftpGetPlotChannel(plotName)
    if not FTP_Synchronizer then return nil end
    local ch
    pcall(function() ch = FTP_Synchronizer:Get(plotName) end)
    if not ch then pcall(function() ch = FTP_Synchronizer:Wait(plotName) end) end
    return ch
end

local function ftpChannelGet(ch, key)
    if not ch then return nil end
    local v
    pcall(function() if type(ch.Get) == "function" then v = ch:Get(key) end end)
    if v == nil then pcall(function() v = ch.CacheTable and ch.CacheTable[key] end) end
    return v
end

local function ftpIsMyPlot(ch)
    if not ch then return false end
    local owner = ftpChannelGet(ch, "Owner")
    if not owner then return false end
    local result = false
    pcall(function()
        if typeof(owner) == "Instance" and owner:IsA("Player") then
            result = owner.UserId == LP.UserId
        elseif type(owner) == "table" and owner.UserId then
            result = owner.UserId == LP.UserId
        elseif typeof(owner) == "Instance" then
            result = owner == LP
        end
    end)
    return result
end

local function ftpOwnerInGame(ch)
    if not ch then return false end
    local owner = ftpChannelGet(ch, "Owner")
    if not owner then return false end
    local inGame = false
    pcall(function()
        if typeof(owner) == "Instance" and owner:IsA("Player") then
            inGame = Players:FindFirstChild(owner.Name) ~= nil
        elseif type(owner) == "number" then
            inGame = Players:GetPlayerByUserId(owner) ~= nil
        elseif type(owner) == "table" and owner.Name then
            inGame = Players:FindFirstChild(tostring(owner.Name)) ~= nil
        elseif typeof(owner) == "Instance" and owner.Name then
            inGame = Players:FindFirstChild(owner.Name) ~= nil
        end
    end)
    return inGame
end

local function ftpGetPetPosition(plot, slot)
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(tostring(slot))
    if not podium then return nil end
    for _, desc in ipairs(podium:GetDescendants()) do
        if desc:IsA("Model") and desc.Name ~= "Claim" and desc.Name ~= "Base" and desc.Name ~= "Decorations" then
            local hasMesh = false
            for _, c in ipairs(desc:GetDescendants()) do
                if c:IsA("MeshPart") then hasMesh = true; break end
            end
            if hasMesh then
                local ok, cf = pcall(function() return desc:GetBoundingBox() end)
                if ok then return cf.Position end
            end
        end
    end
    local ok, cf = pcall(function() return podium:GetPivot() end)
    if ok then return cf.Position end
    local sp = podium:FindFirstChild("Spawn") or podium:FindFirstChildWhichIsA("BasePart")
    return sp and sp.Position or nil
end

-- =====================================================================
-- scanAllPets
-- =====================================================================
local function scanAllPets()
    local pets = {}
    if not ftpLoadModules() then return pets end
    local Plots = workspace:FindFirstChild("Plots")
    if not Plots then return pets end
    for _, plot in ipairs(Plots:GetChildren()) do
        local channel = ftpGetPlotChannel(plot.Name)
        if not channel then continue end
        if ftpIsMyPlot(channel) then continue end
        if not ftpOwnerInGame(channel) then continue end
        local animalList = ftpChannelGet(channel, "AnimalList")
        if not animalList then continue end
        for slot, animalData in pairs(animalList) do
            if type(animalData) ~= "table" then continue end
            local animalName = animalData.Index
            if not animalName then continue end
            local animalInfo = FTP_AnimalsData and FTP_AnimalsData[animalName]
            if not animalInfo then continue end
            if _VanishIsFusing(animalData) then continue end
            local genValue = 0
            pcall(function()
                genValue = FTP_AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil)
            end)
            local displayName = (animalInfo and animalInfo.DisplayName) or animalName
            local pos = ftpGetPetPosition(plot, slot)
            if pos then
                table.insert(pets, {
                    name     = displayName,
                    mps      = genValue,
                    mutation = animalData.Mutation or "None",
                    position = pos,
                    plot     = plot.Name,
                    slot     = tostring(slot),
                })
            end
        end
    end
    table.sort(pets, function(a, b)
        return petOutranks(a.name, b.name, a.mutation, b.mutation, a.mps, b.mps)
    end)
    return pets
end

-- =====================================================================
-- Sky platform coordinate tables
-- =====================================================================
local UPPER = {
    B = {{coord=Vector3.new(-476,16.850713,-100),facing="EAST"},{coord=Vector3.new(-342,16.850713,-100),facing="WEST"},{coord=Vector3.new(-476,16.850713,7),facing="EAST"},{coord=Vector3.new(-342,16.850713,6),facing="WEST"}},
    C = {{coord=Vector3.new(-476,16.850713,7),facing="EAST"},{coord=Vector3.new(-342,16.850713,6),facing="WEST"},{coord=Vector3.new(-476,16.850713,114),facing="EAST"},{coord=Vector3.new(-342,16.850713,114),facing="WEST"}},
    D = {{coord=Vector3.new(-476,16.850713,114),facing="EAST"},{coord=Vector3.new(-342,16.850713,114),facing="WEST"},{coord=Vector3.new(-476,16.850713,221),facing="EAST"},{coord=Vector3.new(-342,16.850713,220),facing="WEST"}},
}
local LOWER = {
    B = {{coord=Vector3.new(-476,-3.048217,-100),facing="EAST"},{coord=Vector3.new(-342,-3.048217,-100),facing="WEST"},{coord=Vector3.new(-476,-3.048217,7),facing="EAST"},{coord=Vector3.new(-342,-3.048217,6),facing="WEST"}},
    C = {{coord=Vector3.new(-476,-3.048217,7),facing="EAST"},{coord=Vector3.new(-342,-3.048217,6),facing="WEST"},{coord=Vector3.new(-476,-3.048217,114),facing="EAST"},{coord=Vector3.new(-342,-3.048217,114),facing="WEST"}},
    D = {{coord=Vector3.new(-476,-3.048217,114),facing="EAST"},{coord=Vector3.new(-342,-3.048217,114),facing="WEST"},{coord=Vector3.new(-476,-3.048217,221),facing="EAST"},{coord=Vector3.new(-342,-3.048217,220),facing="WEST"}},
}
local UPPER_Y_THRESHOLD = 7
local TALL_PETS = { ["La Secret Combinasion"]=true, ["La Jolly Grande"]=true }
local TALL_OFFSET = 3

local function findClosest(petPos, coordTable)
    local petClosest, bestRowKey, bestPetDist = nil, nil, math.huge
    for skyKey, coords in pairs(coordTable) do
        for _, data in ipairs(coords) do
            local c = data.coord
            local d = math.sqrt((petPos.X - c.X)^2 + (petPos.Z - c.Z)^2)
            if d < bestPetDist then bestPetDist = d; petClosest = data; bestRowKey = skyKey end
        end
    end
    return petClosest, bestRowKey
end

-- =====================================================================
-- Path viz helpers
-- =====================================================================
local _vizParts = {}
local function clearViz()
    for _, p in ipairs(_vizParts) do if p and p.Parent then p:Destroy() end end
    table.clear(_vizParts)
end

-- =====================================================================
-- Raycast helpers
-- =====================================================================
local _DIRS = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
local _SKIP_NAME = { ["DeliveryHitbox"]=true,["StealHitbox"]=true,["LaserHitbox"]=true,
    ["AnimalTarget"]=true,["Multiplier"]=true,["Laser"]=true,["Hitbox"]=true,
    ["Spawn"]=true,["MainRoot"]=true,["SecondFloor"]=true,["ThirdFloor"]=true,["Slope"]=true }
local function _blocks(inst)
    if not inst then return false end
    if _SKIP_NAME[inst.Name] then return false end
    if inst.CanCollide then return true end
    local s = inst.Size
    if s and math.max(s.X * s.Y, s.X * s.Z, s.Y * s.Z) > 150 then return true end
    return false
end
local function _block(origin, target)
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.IgnoreWater = true
    local skip = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then skip[#skip + 1] = pl.Character end
    end
    local o = origin
    for _ = 1, 16 do
        rp.FilterDescendantsInstances = skip
        local d = target - o
        if d.Magnitude < 0.05 then return nil end
        local res = workspace:Raycast(o, d, rp)
        if not res then return nil end
        if _blocks(res.Instance) then return res end
        skip[#skip + 1] = res.Instance
        o = res.Position + d.Unit * 0.3
    end
    return nil
end
local function _clear(a, b) return _block(a, b) == nil end
local function _clearDist(origin, dir, maxD)
    local res = _block(origin, origin + dir.Unit * maxD)
    if not res then return maxD end
    return (res.Position - origin).Magnitude
end
local _CLEARANCE = 6
local function _clearWide(a, b)
    if not _clear(a, b) then return false end
    local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
    if d.Magnitude < 0.1 then return true end
    local p = Vector3.new(-d.Z, 0, d.X).Unit * _CLEARANCE
    return _clear(a + p, b + p) and _clear(a - p, b - p)
end
local function _pullWide(pts)
    if #pts <= 2 then return pts end
    local out = { pts[1] }
    local i = 1
    while i < #pts do
        local j = #pts
        while j > i + 1 and not _clearWide(out[#out], pts[j]) do j = j - 1 end
        out[#out + 1] = pts[j]
        i = j
    end
    return out
end
local _LIFT_HEIGHTS = { 6, 12, 20, 30 }
local function _simpleLiftRoute(fromPos, toPos)
    for _, lift in ipairs(_LIFT_HEIGHTS) do
        local mid = (fromPos + toPos) / 2 + Vector3.new(0, lift, 0)
        local pts = { fromPos, mid, toPos }
        local ok = true
        for k = 1, #pts - 1 do if not _clear(pts[k], pts[k+1]) then ok = false; break end end
        if ok and _clearWide(fromPos, mid) and _clearWide(mid, toPos) then return pts end
    end
    for _, lift in ipairs(_LIFT_HEIGHTS) do
        local up   = fromPos + Vector3.new(0, lift, 0)
        local over = Vector3.new(toPos.X, up.Y, toPos.Z)
        local pts  = { fromPos, up, over, toPos }
        local ok = true
        for k = 1, #pts - 1 do if not _clear(pts[k], pts[k+1]) then ok = false; break end end
        if ok and _clearWide(up, over) then return pts end
    end
    return nil
end

local function computeRoute(fromPos, toPos, facingDir)
    if _clear(fromPos, toPos) then return { toPos } end
    local isFloor1Route = fromPos.Y <= 12 and toPos.Y <= 12
    if not isFloor1Route then
        local simple = _simpleLiftRoute(fromPos, toPos)
        if simple then return simple end
    end
    local entry = facingDir and (toPos - facingDir * 14) or toPos
    local groundTo = Vector3.new(entry.X, fromPos.Y, entry.Z)
    local path = PathfindingService:CreatePath({
        AgentRadius = 8, AgentHeight = 5, AgentCanJump = true, AgentJumpHeight = 10, AgentMaxSlope = 89,
    })
    local FLOAT = isFloor1Route and 0 or 3
    local nav = { fromPos }
    local ok = pcall(function()
        path:ComputeAsync(Vector3.new(fromPos.X, fromPos.Y, fromPos.Z), groundTo)
    end)
    if ok and path.Status == Enum.PathStatus.Success then
        local last = fromPos
        for _, wp in ipairs(path:GetWaypoints()) do
            if (wp.Position - last).Magnitude >= 8 then
                local wpY = isFloor1Route and fromPos.Y or (wp.Position.Y + FLOAT)
                nav[#nav + 1] = Vector3.new(wp.Position.X, wpY, wp.Position.Z)
                last = wp.Position
            end
        end
    end
    local entryY = isFloor1Route and fromPos.Y or (entry.Y + FLOAT)
    nav[#nav + 1] = Vector3.new(entry.X, entryY, entry.Z)
    local route = _pullWide(nav)
    route[#route + 1] = toPos
    return route
end

-- =====================================================================
-- Velocity mover
-- =====================================================================
local ARRIVE = 3
local function vZero(hrp)
    if not hrp then return end
    local vy = hrp.AssemblyLinearVelocity.Y
    hrp.AssemblyLinearVelocity = Vector3.new(0, vy, 0)
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function velMoveThrough(hrp, waypoints)
    if not hrp or not hrp.Parent or #waypoints == 0 then return end
    local wpIdx = 1
    local done = false
    local conn
    local function finish()
        if done then return end
        done = true
        if hrp and hrp.Parent then
            local vy = hrp.AssemblyLinearVelocity.Y
            hrp.AssemblyLinearVelocity = Vector3.new(0, vy, 0)
            hrp.AssemblyAngularVelocity = Vector3.zero
            local _, y = hrp.CFrame:ToEulerAnglesYXZ()
            hrp.CFrame = CFrame.new(waypoints[#waypoints]) * CFrame.Angles(0, y, 0)
        end
        if conn then conn:Disconnect() end
    end
    local lastDist, stall = math.huge, 0
    conn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent or done then
            if conn then conn:Disconnect() end
            return
        end
        ftpEquipCarpet()
        local target = waypoints[wpIdx]
        local diff   = target - hrp.Position
        local mag    = diff.Magnitude
        if mag < ARRIVE then
            wpIdx = wpIdx + 1
            if wpIdx > #waypoints then finish() return end
            lastDist, stall = math.huge, 0
            target = waypoints[wpIdx]
            diff   = target - hrp.Position
            mag    = diff.Magnitude
        end
        if mag > lastDist - 0.05 then stall = stall + 1 else stall = 0 end
        lastDist = mag
        if stall >= 18 then finish() return end
        if mag >= 0.1 then
            local dir   = diff.Unit
            local speed = (_G.FlashExtra and _G.FlashExtra.tpSpeed) or 400
            local isFloor1Movement = hrp.Position.Y <= 12 and waypoints[#waypoints].Y <= 12
            local velY  = isFloor1Movement and 0 or (dir.Y * speed)
            hrp.AssemblyLinearVelocity = Vector3.new(dir.X * speed, velY, dir.Z * speed)
        end
    end)
    local totalDist = 0
    local prev = hrp.Position
    for _, wp in ipairs(waypoints) do totalDist = totalDist + (prev - wp).Magnitude; prev = wp end
    local speed   = (_G.FlashExtra and _G.FlashExtra.tpSpeed) or 400
    local timeout = totalDist / speed + 2
    local elapsed = 0
    while not done and elapsed < timeout do task.wait(0.05); elapsed = elapsed + 0.05 end
    finish()
    vZero(hrp)
end

-- =====================================================================
-- Clone swap
-- =====================================================================
local _cloneActive = false

local function _doCloneImpl()
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return false end
    local cloner
    for _ = 1, 60 do
        cloner = char:FindFirstChild("Quantum Cloner") or (LP:FindFirstChild("Backpack") and LP.Backpack:FindFirstChild("Quantum Cloner"))
        if cloner then break end
        task.wait(0.05)
    end
    if not cloner then return false end
    if cloner.Parent ~= char then hum:EquipTool(cloner); task.wait(0.02) end
    cloner:Activate()
    local cloneName = tostring(LP.UserId) .. "_Clone"
    local clone = workspace:FindFirstChild(cloneName) or workspace:WaitForChild(cloneName, 6)
    if not clone then return false end
    task.wait(0.03)
    local tpButton
    for _ = 1, 160 do
        local tf = LP.PlayerGui:FindFirstChild("ToolsFrames")
        local qc = tf and tf:FindFirstChild("QuantumCloner")
        tpButton = qc and qc:FindFirstChild("TeleportToClone")
        if tpButton then break end
        task.wait(0.05)
    end
    if not tpButton then return false end
    tpButton.Visible = true
    task.wait()
    local function fire()
        local vim = game:GetService("VirtualInputManager")
        local inset = game:GetService("GuiService"):GetGuiInset()
        local p = tpButton.AbsolutePosition + (tpButton.AbsoluteSize / 2) + inset
        vim:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 1)
        task.wait()
        vim:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 1)
    end
    local hrp      = char:FindFirstChild("HumanoidRootPart")
    local start    = hrp and hrp.Position
    local charAdded = false
    local caConn   = LP.CharacterAdded:Connect(function() charAdded = true end)
    local refired  = false
    local rebuilt  = false
    fire()
    for i = 1, 300 do
        RunService.Heartbeat:Wait()
        local _c = LP.Character
        local _h = _c and _c:FindFirstChild("HumanoidRootPart")
        local cloneGone = not workspace:FindFirstChild(cloneName)
        if charAdded then
            if caConn then caConn:Disconnect() end
            RunService.Heartbeat:Wait()
            return true
        end
        if _c ~= char then rebuilt = true end
        if not _h or not _h.Parent then
            rebuilt = true
        else
            local moved = start and (_h.Position - start).Magnitude > 1
            if rebuilt or cloneGone or moved then
                if caConn then caConn:Disconnect() end
                RunService.Heartbeat:Wait()
                return true
            end
        end
        if not refired and i >= 4 then
            refired = true
            fire()
        end
    end
    if caConn then caConn:Disconnect() end
    return rebuilt or charAdded or (not workspace:FindFirstChild(cloneName))
end

local function doClone()
    _cloneActive     = true
    _G.TPCloneActive = true
    local ok, res    = pcall(_doCloneImpl)
    _cloneActive     = false
    _G.TPCloneActive = false
    if not ok then warn("[FlashTP] doClone error: " .. tostring(res)); return false end
    return res == true
end

-- =====================================================================
-- Anti-die system
-- =====================================================================
local _antiDieConn     = nil
local _antiDieDisabled = false

local function _setupAntiDie()
    if _antiDieDisabled then return end
    local char = LP.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if _antiDieConn then pcall(function() _antiDieConn:Disconnect() end) end
    local deathConfirmed = false
    local zeroSince      = nil
    _antiDieConn = hum:GetPropertyChangedSignal("Health"):Connect(function()
        if _antiDieDisabled or deathConfirmed then return end
        if hum.Health <= 0 then
            zeroSince = zeroSince or os.clock()
            hum.Health = hum.MaxHealth
        else
            zeroSince = nil
        end
    end)
    task.spawn(function()
        while _antiDieConn and not _antiDieDisabled and not deathConfirmed do
            local ok = pcall(function()
                if hum.Parent == nil then deathConfirmed = true; return end
                local dead = false
                pcall(function() dead = hum:GetState() == Enum.HumanoidStateType.Dead end)
                if dead or (zeroSince and (os.clock() - zeroSince) >= 3.0) then
                    deathConfirmed = true
                end
            end)
            if not ok then break end
            RunService.Heartbeat:Wait()
        end
    end)
end

local function _disableAntiDie()
    _antiDieDisabled = true
    if _antiDieConn then pcall(function() _antiDieConn:Disconnect() end); _antiDieConn = nil end
end

local function _enableAntiDie()
    _antiDieDisabled = false
    _setupAntiDie()
end

LP.CharacterAdded:Connect(function()
    task.wait(0.3)
    _setupAntiDie()
end)

-- =====================================================================
-- findAdorneeGlobal
-- =====================================================================
local function findAdorneeGlobal(a)
    if not a then return nil end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local plot = plots:FindFirstChild(a.plot); if not plot then return nil end
    local pods  = plot:FindFirstChild("AnimalPodiums"); if not pods then return nil end
    local pod   = pods:FindFirstChild(a.slot); if not pod then return nil end
    local base  = pod:FindFirstChild("Base"); if not base then return nil end
    local sp    = base:FindFirstChild("Spawn")
    return sp or base:FindFirstChildWhichIsA("BasePart")
end

-- =====================================================================
-- goToBrainrot
-- =====================================================================
local function goToBrainrot(petData)
    do
        local _ct0 = os.clock()
        while (_cloneActive or _G.TPCloneActive) and (os.clock() - _ct0) < 5 do
            task.wait(0.05)
        end
    end
    local char, hrp, hum
    local deadline = os.clock() + 5
    repeat
        task.wait(0.05)
        char = LP.Character
        hrp  = char and char:FindFirstChild("HumanoidRootPart")
        hum  = char and char:FindFirstChildOfClass("Humanoid")
    until (hrp and hrp.Parent and hum and hum.Health > 0) or os.clock() > deadline
    if not hrp or not hrp.Parent then return end

    local _tw = os.clock()
    repeat
        task.wait(0.05)
        local hasCarpet = false
        for _, n in ipairs(FTP_CARPET_NAMES) do if ftpFindTool(n) then hasCarpet = true; break end end
        if hasCarpet then break end
    until os.clock() - _tw > 0.5

    _enableAntiDie()
    ftpEquipCarpet()
    if not hrp or not hrp.Parent then return end

    local snapPart = findAdorneeGlobal(petData)
    if not snapPart then return end

    local exactPos   = snapPart.Position
    local isThirdFloor  = exactPos.Y > 22
    local isSecondFloor = exactPos.Y > UPPER_Y_THRESHOLD and exactPos.Y <= 22
    local _f2mode = (_G.FlashExtra and _G.FlashExtra.floor2AsFloor1) and isSecondFloor
    local snapY
    if isThirdFloor then
        snapY = exactPos.Y - 8
    elseif _f2mode then
        snapY = exactPos.Y - 12
    else
        snapY = exactPos.Y + 3.5
    end
    local snapPos = Vector3.new(exactPos.X, snapY, exactPos.Z)

    -- Auto float for elevated brainrots
    if exactPos.Y > 22 and _G.setFloatEnabled then
        pcall(_G.setFloatEnabled, true)
        _G._autoFloatPending = true
    end

    task.spawn(function()
        local _deadline = tick() + 10
        repeat task.wait(0.1) until (not LP:GetAttribute("Stealing")) or tick() > _deadline
        task.wait(0.3)
        if _G._autoFloatPending then
            _G._autoFloatPending = false
            if _G.setFloatEnabled then pcall(_G.setFloatEnabled, false) end
        end
    end)

    local _healDone = false
    local _healConn = RunService.Heartbeat:Connect(function()
        if _healDone then return end
        local _c = LP.Character
        local _h = _c and _c:FindFirstChildOfClass("Humanoid")
        if _h and _h.Parent then _h.Health = _h.MaxHealth end
    end)

    local function fireTween()
        char = LP.Character
        hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        local dist      = (hrp.Position - snapPos).Magnitude
        local _snapSpeed = (_G.FlashExtra and _G.FlashExtra.brainrotSnapSpeed) or 300
        local tweenTime = math.clamp(dist / math.max(1, _snapSpeed), 0.20, 3.0)
        local tw = TweenService:Create(hrp, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = CFrame.new(snapPos)})
        tw:Play(); tw.Completed:Wait()
        char = LP.Character
        hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
    end

    fireTween()
    task.wait(0.05)
    char = LP.Character; hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and (hrp.Position - snapPos).Magnitude > 3 then fireTween() end

    char = LP.Character; hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        pcall(function() hrp.CFrame = CFrame.new(snapPos) end)
        local _anchorWait = (_G.FlashExtra and _G.FlashExtra.wallAnchorWait) or 0.10
        if _anchorWait and _anchorWait > 0 then
            hrp.Anchored = true
            task.wait(_anchorWait)
            char = LP.Character; hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.Parent then
                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.Anchored = false
            end
        end
    end

    _healDone = true
    _healConn:Disconnect()

    -- Temp platform
    task.spawn(function()
        pcall(function()
            local _c   = LP.Character
            local _hrp = _c and _c:FindFirstChild("HumanoidRootPart")
            if not _hrp then return end
            local _p = Instance.new("Part")
            _p.Name = "_StealPlatform"
            _p.Size = Vector3.new(8, 0.5, 8)
            _p.CFrame = CFrame.new(_hrp.Position.X, _hrp.Position.Y - 3, _hrp.Position.Z)
            _p.Anchored = true; _p.CanCollide = true; _p.CanTouch = false
            _p.CanQuery = false; _p.Transparency = 1; _p.CastShadow = false
            _p.Parent = workspace
            task.wait(3)
            pcall(function() _p:Destroy() end)
        end)
    end)

    pcall(function()
        local _c   = LP.Character
        local _hum = _c and _c:FindFirstChildOfClass("Humanoid")
        local _hrp = _c and _c:FindFirstChild("HumanoidRootPart")
        if _hum and not _G._floatActive then _hum:UnequipTools() end
        if _hrp then
            _hrp.AssemblyLinearVelocity  = Vector3.zero
            _hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    task.spawn(function()
        local _t0 = os.clock()
        while (LP:GetAttribute("Stealing") or os.clock() - _t0 < 3) do
            local _c = LP.Character
            local _h = _c and _c:FindFirstChildOfClass("Humanoid")
            if _h and _h.Parent and _h.Health < _h.MaxHealth then _h.Health = _h.MaxHealth end
            task.wait(0.05)
        end
        task.wait(0.5)
        _disableAntiDie()
    end)
end

-- =====================================================================
-- FPS tracker
-- =====================================================================
_G._FlashCurrentFPS = 60
do
    local _fpsSamples, _fpsIdx = {}, 0
    RunService.Heartbeat:Connect(function(dt)
        _fpsIdx = (_fpsIdx % 20) + 1
        _fpsSamples[_fpsIdx] = 1 / math.max(dt, 0.001)
        local sum, n = 0, 0
        for _, v in ipairs(_fpsSamples) do sum = sum + v; n = n + 1 end
        _G._FlashCurrentFPS = n > 0 and (sum / n) or 60
    end)
end

-- =====================================================================
-- doVelocityTP (main entry)
-- =====================================================================
local isTeleporting = false

local function doVelocityTP()
    if isTeleporting then return end
    isTeleporting = true
    local ok, err = pcall(function()
        clearViz()
        _G.TPStatus = "start"
        local char = LP.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local hum  = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then _G.TPStatus = "no_char"; return end

        local allPets = scanAllPets()
        if #allPets == 0 then
            local _t0 = os.clock()
            while #allPets == 0 and os.clock() - _t0 < 4 do
                task.wait(0.15); allPets = scanAllPets()
            end
        end
        if #allPets == 0 then _G.TPStatus = "no_brainrot_found"; isTeleporting = false; return end

        local fe = _G.FlashExtra
        if not fe then _G.TPStatus = "no_FlashExtra"; return end

        if (fe.tpFpsGate or 0) > 0 then
            local _gateT0 = os.clock()
            while (_G._FlashCurrentFPS or 999) < fe.tpFpsGate and os.clock() - _gateT0 < 10 do
                _G.TPStatus = "waiting_fps"; task.wait(0.1)
            end
        end

        local minMPS = ((fe.tpMinMPS or 0) * 1e6)
        local pet

        if fe.tpPriorityEnabled and not fe.tpHighestEnabled and fe.priorityList and #fe.priorityList > 0 then
            local bestRank, bestMPS = math.huge, -math.huge
            for _, candidate in ipairs(allPets) do
                if minMPS <= 0 or (candidate.mps or 0) >= minMPS then
                    local rank = math.huge
                    local cLow = candidate.name and candidate.name:lower()
                    for i, pName in ipairs(fe.priorityList) do
                        if pName:lower() == cLow then rank = i; break end
                    end
                    if rank ~= math.huge and (rank < bestRank or (rank == bestRank and (candidate.mps or 0) > bestMPS)) then
                        bestRank = rank; bestMPS = candidate.mps or 0; pet = candidate
                    end
                end
            end
            if not pet then
                _G.TPStatus = "no_priority_found"
                warn("[FlashTP] Aucun brainrot prioritaire trouve — desactive TP Priority ou ajoute un nom.")
                return
            end
        else
            local bestMPS = -math.huge
            for _, candidate in ipairs(allPets) do
                if minMPS <= 0 or (candidate.mps or 0) >= minMPS then
                    if (candidate.mps or 0) > bestMPS then
                        bestMPS = candidate.mps or 0; pet = candidate
                    end
                end
            end
        end

        if not pet then _G.TPStatus = "no_target_after_filters"; return end

        local petPos  = pet.position
        local petName = pet.name
        _G.TPStatus   = "target=" .. tostring(petName)

        local adjY = petPos.Y
        if TALL_PETS[petName] then adjY = petPos.Y - TALL_OFFSET end
        local _floor2Mode = (fe.floor2AsFloor1) and (adjY > UPPER_Y_THRESHOLD and adjY <= 22)
        local coordTable  = (not _floor2Mode) and (adjY > UPPER_Y_THRESHOLD and UPPER or LOWER) or LOWER

        local closestData, skyKey = findClosest(petPos, coordTable)
        if not closestData or not skyKey then _G.TPStatus = "no_sky_platform"; return end

        local destPos = closestData.coord

        if coordTable == UPPER and not _floor2Mode then
            local FLOOR2_BASES = {
                { L=Vector3.new(-478.0322,13.9682,  25.2552), R=Vector3.new(-478.9711,13.9682, -11.5476) },
                { L=Vector3.new(-479.4897,14.0340, -81.4871), R=Vector3.new(-478.7449,14.0340,-118.3792) },
                { L=Vector3.new(-340.5145,14.0340,-119.2653), R=Vector3.new(-340.2055,14.0340, -82.6786) },
                { L=Vector3.new(-339.6728,14.5682, -11.6249), R=Vector3.new(-339.6895,14.5682,  23.9712) },
                { L=Vector3.new(-339.6208,14.5682,  95.4651), R=Vector3.new(-339.8099,13.9682, 130.8262) },
                { L=Vector3.new(-479.2108,14.0340, 131.9893), R=Vector3.new(-478.3889,14.0340,  96.0183) },
                { L=Vector3.new(-479.5883,14.5682, 203.1649), R=Vector3.new(-479.6722,14.3680, 240.1458) },
                { L=Vector3.new(-339.7557,14.0338, 238.5831), R=Vector3.new(-339.1931,14.0338, 201.7895) },
            }
            local bestBase, bestDist = nil, math.huge
            for _, base in ipairs(FLOOR2_BASES) do
                local mid = (base.L + base.R) / 2
                local d = (Vector3.new(destPos.X,0,destPos.Z) - Vector3.new(mid.X,0,mid.Z)).Magnitude
                if d < bestDist then bestDist = d; bestBase = base end
            end
            if bestBase then
                local dL = (Vector3.new(hrp.Position.X,0,hrp.Position.Z) - Vector3.new(bestBase.L.X,0,bestBase.L.Z)).Magnitude
                local dR = (Vector3.new(hrp.Position.X,0,hrp.Position.Z) - Vector3.new(bestBase.R.X,0,bestBase.R.Z)).Magnitude
                destPos = dL < dR and bestBase.L or bestBase.R
            end
        end

        local maxHP   = hum.MaxHealth
        hum.Health    = maxHP
        local healConn = RunService.Heartbeat:Connect(function()
            if hum and hum.Parent then hum.Health = maxHP end
        end)

        local _carpet = ftpCarpetEngage()
        vZero(hrp)

        local facingDir
        if closestData.facing == "EAST"  then facingDir = Vector3.new(-1,0,0)
        elseif closestData.facing == "WEST"  then facingDir = Vector3.new(1,0,0)
        elseif closestData.facing == "NORTH" then facingDir = Vector3.new(0,0,-1)
        elseif closestData.facing == "SOUTH" then facingDir = Vector3.new(0,0,1)
        else facingDir = Vector3.new(0,0,-1) end

        destPos = destPos - facingDir * 0.05

        _enableAntiDie()
        hrp.Anchored = true
        local _route = computeRoute(hrp.Position, destPos, facingDir)
        if hrp and hrp.Parent then hrp.Anchored = false end
        velMoveThrough(hrp, _route)

        hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
        vZero(hrp)

        local syncFrames = 5
        local syncConn
        syncConn = RunService.Heartbeat:Connect(function()
            if not hrp or not hrp.Parent then syncConn:Disconnect(); return end
            syncFrames = syncFrames - 1
            hrp.CFrame = CFrame.new(destPos, destPos + facingDir)
            local vy = hrp.AssemblyLinearVelocity.Y
            hrp.AssemblyLinearVelocity = Vector3.new(0, vy, 0)
            hrp.AssemblyAngularVelocity = Vector3.zero
            if syncFrames <= 0 then syncConn:Disconnect() end
        end)

        do
            local _hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
            for _ = 1, 5 do
                task.wait(0.05)
                if _hum and _hum.FloorMaterial ~= Enum.Material.Air then break end
            end
        end
        do
            local stable = 0
            for _ = 1, 10 do
                local _hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if not _hrp or not _hrp.Parent then break end
                local flat = (Vector3.new(_hrp.Position.X,0,_hrp.Position.Z) - Vector3.new(destPos.X,0,destPos.Z)).Magnitude
                if flat <= 3.5 and math.abs(_hrp.Position.Y - destPos.Y) <= 4 then
                    stable = stable + 1
                    if stable >= 4 then break end
                else
                    stable = 0
                    pcall(function() _hrp.CFrame = CFrame.new(destPos, destPos + facingDir) end)
                    _hrp.AssemblyLinearVelocity = Vector3.zero
                    _hrp.AssemblyAngularVelocity = Vector3.zero
                end
                RunService.Heartbeat:Wait()
            end
        end

        do
            local _whrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if _whrp and _whrp.Parent then
                local _t0 = os.clock()
                while os.clock() - _t0 < 0.05 do
                    _whrp.AssemblyLinearVelocity  = facingDir * 16
                    _whrp.AssemblyAngularVelocity = Vector3.zero
                    RunService.Heartbeat:Wait()
                end
                _whrp.AssemblyLinearVelocity  = Vector3.zero
                _whrp.AssemblyAngularVelocity = Vector3.zero
                destPos = _whrp.Position
            end
        end

        do
            local _phrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if _phrp and _phrp.Parent then
                _phrp.AssemblyLinearVelocity  = Vector3.zero
                _phrp.AssemblyAngularVelocity = Vector3.zero
                pcall(function() _phrp.CFrame = CFrame.new(destPos, destPos + facingDir) end)
                pcall(function() _phrp.Anchored = true end)
                local _anchorWait = petPos.Y <= 20 and 0.05 or (fe.skyCloneWait or 0.28)
                task.wait(_anchorWait)
                pcall(function() _phrp.Anchored = false end)
                task.wait(0.02)
            end
        end

        local _cloneLockCF   = CFrame.new(destPos, destPos + facingDir)
        local _cloneLockChar = LP.Character
        local _cloneLockConn
        _cloneLockConn = RunService.Heartbeat:Connect(function()
            if LP.Character ~= _cloneLockChar then return end
            local _h = _cloneLockChar and _cloneLockChar:FindFirstChild("HumanoidRootPart")
            if _h and _h.Parent then
                _h.AssemblyLinearVelocity  = Vector3.zero
                _h.AssemblyAngularVelocity = Vector3.zero
                _h.CFrame = _cloneLockCF
            end
        end)

        local cloneOk = doClone()
        if _cloneLockConn then _cloneLockConn:Disconnect() end
        healConn:Disconnect()

        if cloneOk then
            _G.TPStatus = "clone_ok"
            local _t0 = os.clock()
            repeat task.wait(0.05)
            until (LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") and LP.Character.Parent) or os.clock() - _t0 > 5
            pcall(goToBrainrot, pet)
        else
            _G.TPStatus = "clone_FAILED"
        end

        task.spawn(function() task.wait(3); clearViz() end)
    end)

    pcall(function()
        local _c   = LP.Character
        local _hum = _c and _c:FindFirstChildOfClass("Humanoid")
        local _h   = _c and _c:FindFirstChild("HumanoidRootPart")
        if _h and _h.Parent then
            _h.Anchored = false
            _h.AssemblyLinearVelocity  = Vector3.zero
            _h.AssemblyAngularVelocity = Vector3.zero
        end
        if _hum then pcall(function() _hum:UnequipTools() end) end
    end)

    isTeleporting = false
    warn("[FlashTP] status = " .. tostring(_G.TPStatus))
end

_G.FlashStartTP = doVelocityTP

task.spawn(function() pcall(ftpLoadModules) end)

end -- end FlashTP do block
-- ======================================================
-- END FLASH TP
-- ======================================================



-- ============================================================
-- CONFIGURACION / SETTINGS
-- ============================================================
local FileName = "HazeHub.json" 
local DefaultConfig = {
    Positions = {
        AdminPanel = {X = 0.1859375, Y = 0.5767123526556385, OffsetX = 0, OffsetY = 0}, 
        StealSpeed = {X = 0.02, Y = 0.18}, 
        Settings = {X = 0.834375, Y = 0.43590998043052839}, 
        InvisPanel = {X = 0.8578125, Y = 0.17260276361454258, OffsetX = 0, OffsetY = 0}, 
        AutoSteal = {X = 0.02, Y = 0.35, OffsetX = 0, OffsetY = 0}, 
        MobileControls = {X = 0.9, Y = 0.4},
        MobileBtn_TP = {X = 0.5, Y = 0.4},
        MobileBtn_CL = {X = 0.5, Y = 0.4},
        MobileBtn_SP = {X = 0.5, Y = 0.4},
        MobileBtn_IV = {X = 0.5, Y = 0.4},
        MobileBtn_UI = {X = 0.5, Y = 0.4},
        MobileBtn_KICK = {X = 0.5, Y = 0.4},
        JobJoiner = {X = 0.5, Y = 0.85},
        TargetControls = {X = 0.26, Y = 0.35, OffsetX = 0, OffsetY = 0},
    }, 
    TpSettings = {
        Tool           = "Flying Carpet",
        Speed          = 2, 
        TpKey          = "T",
        CloneKey       = "V",
        TpOnLoad       = false,
        MinGenForTp    = "",
        CarpetSpeedKey = "Q",
        InfiniteJump   = false,
        TeleportV2     = false,
        TeleportV3     = false,
        Floor1WalkTime = 0.45,
        Floor2WaitTime = 0.07,
        TpSpeed        = 0.10,
    },
    StealSpeed   = 20,
    ShowStealSpeedPanel = true,
    MenuKey      = "LeftControl",
    MobileGuiScale = 0.5,
    XrayEnabled  = false,
    AntiRagdoll  = 0,
    AntiRagdollV2 = false,
    PlayerESP    = true,
    FPSBoost     = true,
    FPSBoostV2   = false,
    TracerEnabled = true,
    BrainrotESP = true,
    TimerESP = false,
    Float = false,
    FloatKeybind = "Z",
    LineToBase = false,
    StealNearest = false,
    StealHighest = true,
    StealPriority = false,
    DefaultToNearest = false,
    DefaultToHighest = false,
    DefaultToPriority = false,
    UILocked     = false,
    HideAdminPanel = false,
    HideAutoSteal = false,
    CompactAutoSteal = false,
    AutoKickOnSteal = false,
    InstantSteal = false,
    InvisStealAngle = 233,
    SinkSliderValue = 5,
    AutoRecoverLagback = true,
    AutoInvisDuringSteal = false,
    InvisToggleKey = "I",
    ClickToAP = false,
    ClickToAPKeybind = "L",
    DisableClickToAPOnMoby = false,
    ProximityAP = false,
    ProximityAPKeybind = "P",
    ProximityRange = 15,
    StealSpeedKey = "C",
    ShowInvisPanel = true,
    ResetKey = "X",
    AutoResetOnBalloon = false,
    AntiBeeDisco = false,
    AutoDestroyTurrets = false,
    FOV = 70,
    SubspaceMineESP = false,
    AutoUnlockOnSteal = false,
    ShowUnlockButtonsHUD = false,
    AutoTPOnFailedSteal = false,
    AutoKickOnSteal = false,
    AutoTPPriority = true,
    KickKey = "",
    CleanErrorGUIs = false,
    ClickToAPSingleCommand = false,
    RagdollSelfKey = "",
    AlertsEnabled = true,
    AlertSoundID = "rbxassetid://6518811702",
    DisableProximitySpamOnMoby = false,
    CancelAPPanelOnMoby = true,
    DisableClickToAPOnKawaifu = false,
    DisableProximitySpamOnKawaifu = false,
    CancelAPPanelOnKawaifu = true,
    AutoStealSpeed = false,
    AutoGrabOwnBase = false,
    ShowJobJoiner = true,
    ShowMobileActionButtons = true,
    JobJoinerKey = "J",
    GriefDetectorEnabled = true,

    PriorityList = {
       "Strawberry Elephant",
       "Meowl",
       "Skibidi Toilet",
       "Headless Horseman",
       "Dragon Gingerini",
       "Dragon Cannelloni",
       "Ketupat Bros",
       "Hydra Dragon Cannelloni",
       "La Supreme Combinasion",
       "Love Love Bear",
       "Ginger Gerat",
       "Cerberus",
       "Capitano Moby",
       "La Casa Boo",
       "Burguro and Fryuro",
       "Spooky and Pumpky",
       "Cooki and Milki",
       "Rosey and Teddy",
       "Popcuru and Fizzuru",
       "Reinito Sleighito",
       "Fragrama and Chocrama",
       "Garama and Madundung",
       "Ketchuru and Musturu",
       "La Secret Combinasion",
       "Tralaledon",
       "Tictac Sahur",
       "Ketupat Kepat",
       "Tang Tang Keletang",
       "Orcaledon",
       "La Ginger Sekolah",
       "Los Spaghettis",
       "Lavadorito Spinito",
       "Swaggy Bros",
       "La Taco Combinasion",
       "Los Primos",
       "Chillin Chili",
       "Tuff Toucan",
       "W or L",
       "Chillin Chili",
       "Chipso and Queso"
    },

}


function DeepCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local out = {}
    for k, v in pairs(tbl) do
        out[k] = DeepCopy(v)
    end
    return out
end

function MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = DeepCopy(v)
            else
                MergeDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local Config = DeepCopy(DefaultConfig)

function NormalizeKeyName(keyName, fallback)
    if type(keyName) ~= "string" or keyName == "" then
        return fallback
    end

    local aliases = {
        ALT = "LeftAlt",
        LALT = "LeftAlt",
        RALT = "RightAlt",
        CTRL = "LeftControl",
        CONTROL = "LeftControl",
        LCTRL = "LeftControl",
        RCTRL = "RightControl",
        SHIFT = "LeftShift",
        LSHIFT = "LeftShift",
        RSHIFT = "RightShift",
        WIN = "LeftSuper",
        CMD = "LeftSuper",
        META = "LeftSuper",
    }

    local upper = string.upper(keyName)
    local normalized = aliases[upper] or keyName
    return Enum.KeyCode[normalized] and normalized or fallback
end

function PrettyKeyName(keyName)
    local map = {
        LeftAlt = "ALT",
        RightAlt = "RALT",
        LeftControl = "CTRL",
        RightControl = "RCTRL",
        LeftShift = "SHIFT",
        RightShift = "RSHIFT",
        LeftSuper = "WIN",
        RightSuper = "RWIN",
    }
    return map[keyName] or tostring(keyName or "")
end

if isfile and isfile(FileName) then
    pcall(function()
        local raw = readfile(FileName)
        if not raw or raw == "" then return end
        local decoded = HttpService:JSONDecode(raw)
        if type(decoded) ~= "table" then return end
        local savedPriorityList = nil
        if type(decoded.PriorityList) == "table" then
            savedPriorityList = DeepCopy(decoded.PriorityList)
        end
        MergeDefaults(decoded, DefaultConfig)
        if savedPriorityList ~= nil then
            decoded.PriorityList = savedPriorityList
        end
        Config = decoded
    end)
end
Config.ProximityAP = false
if type(Config.CancelAPPanelOnMoby) ~= "boolean" then
    Config.CancelAPPanelOnMoby = true
end
if type(Config.CancelAPPanelOnKawaifu) ~= "boolean" then
    Config.CancelAPPanelOnKawaifu = true
end

function EnsureSavedKeybinds()
    Config.SavedKeybinds = Config.SavedKeybinds or {}
    Config.SavedKeybinds.MenuKey = NormalizeKeyName(Config.SavedKeybinds.MenuKey or Config.MenuKey, DefaultConfig.MenuKey or "LeftControl")
    Config.SavedKeybinds.ClickToAPKeybind = NormalizeKeyName(Config.SavedKeybinds.ClickToAPKeybind or Config.ClickToAPKeybind, DefaultConfig.ClickToAPKeybind or "L")
    Config.SavedKeybinds.ProximityAPKeybind = NormalizeKeyName(Config.SavedKeybinds.ProximityAPKeybind or Config.ProximityAPKeybind, DefaultConfig.ProximityAPKeybind or "P")
    Config.SavedKeybinds.StealSpeedKey = NormalizeKeyName(Config.SavedKeybinds.StealSpeedKey or Config.StealSpeedKey, DefaultConfig.StealSpeedKey or "C")
    Config.SavedKeybinds.FloatKeybind = NormalizeKeyName(Config.SavedKeybinds.FloatKeybind or Config.FloatKeybind, DefaultConfig.FloatKeybind or "Z")
    Config.SavedKeybinds.ResetKey = NormalizeKeyName(Config.SavedKeybinds.ResetKey or Config.ResetKey, DefaultConfig.ResetKey or "X")
    Config.SavedKeybinds.JobJoinerKey = NormalizeKeyName(Config.SavedKeybinds.JobJoinerKey or Config.JobJoinerKey, DefaultConfig.JobJoinerKey or "J")
    Config.SavedKeybinds.InvisToggleKey = NormalizeKeyName(Config.SavedKeybinds.InvisToggleKey or Config.InvisToggleKey, DefaultConfig.InvisToggleKey or "I")
    Config.SavedKeybinds.KickKey = NormalizeKeyName(Config.SavedKeybinds.KickKey or Config.KickKey, "")
    Config.SavedKeybinds.RagdollSelfKey = NormalizeKeyName(Config.SavedKeybinds.RagdollSelfKey or Config.RagdollSelfKey, "")
    Config.SavedKeybinds.TpKey = NormalizeKeyName(Config.SavedKeybinds.TpKey or Config.TpSettings.TpKey, DefaultConfig.TpSettings.TpKey or "T")
    Config.SavedKeybinds.CloneKey = NormalizeKeyName(Config.SavedKeybinds.CloneKey or Config.TpSettings.CloneKey, DefaultConfig.TpSettings.CloneKey or "V")
    Config.SavedKeybinds.CarpetSpeedKey = NormalizeKeyName(Config.SavedKeybinds.CarpetSpeedKey or Config.TpSettings.CarpetSpeedKey, DefaultConfig.TpSettings.CarpetSpeedKey or "Q")
end

function ApplySavedKeybindsToConfig()
    EnsureSavedKeybinds()
    Config.MenuKey = Config.SavedKeybinds.MenuKey
    Config.ClickToAPKeybind = Config.SavedKeybinds.ClickToAPKeybind
    Config.ProximityAPKeybind = Config.SavedKeybinds.ProximityAPKeybind
    Config.StealSpeedKey = Config.SavedKeybinds.StealSpeedKey
    Config.FloatKeybind = Config.SavedKeybinds.FloatKeybind
    Config.ResetKey = Config.SavedKeybinds.ResetKey
    Config.JobJoinerKey = Config.SavedKeybinds.JobJoinerKey
    Config.InvisToggleKey = Config.SavedKeybinds.InvisToggleKey
    Config.KickKey = Config.SavedKeybinds.KickKey
    Config.RagdollSelfKey = Config.SavedKeybinds.RagdollSelfKey
    Config.TpSettings.TpKey = Config.SavedKeybinds.TpKey
    Config.TpSettings.CloneKey = Config.SavedKeybinds.CloneKey
    Config.TpSettings.CarpetSpeedKey = Config.SavedKeybinds.CarpetSpeedKey
end

local function getAutoSnipeDelayFromOption(option)
    local map = {
        [1] = 0.10,
        [2] = 0.20,
        [3] = 0.30,
        [4] = 0.40,
    }
    return map[tonumber(option)] or 0.10
end

function NormalizeAllKeybinds()
    EnsureSavedKeybinds()
    ApplySavedKeybindsToConfig()
end

NormalizeAllKeybinds()

-- ============================================================
-- GUARDADO DE CONFIG
-- ============================================================
local function SaveConfig()
    if writefile then
        pcall(function()
            NormalizeAllKeybinds()
            local toSave = DeepCopy(Config)
            toSave.ProximityAP = false
            toSave.MenuKey = Config.SavedKeybinds.MenuKey
            toSave.ClickToAPKeybind = Config.SavedKeybinds.ClickToAPKeybind
            toSave.ProximityAPKeybind = Config.SavedKeybinds.ProximityAPKeybind
            toSave.StealSpeedKey = Config.SavedKeybinds.StealSpeedKey
            toSave.FloatKeybind = Config.SavedKeybinds.FloatKeybind
            toSave.ResetKey = Config.SavedKeybinds.ResetKey
            toSave.JobJoinerKey = Config.SavedKeybinds.JobJoinerKey
            toSave.InvisToggleKey = Config.SavedKeybinds.InvisToggleKey
            toSave.KickKey = Config.SavedKeybinds.KickKey
            toSave.RagdollSelfKey = Config.SavedKeybinds.RagdollSelfKey
            toSave.TpSettings.TpKey = Config.SavedKeybinds.TpKey
            toSave.TpSettings.CloneKey = Config.SavedKeybinds.CloneKey
            toSave.TpSettings.CarpetSpeedKey = Config.SavedKeybinds.CarpetSpeedKey
            writefile(FileName, HttpService:JSONEncode(toSave))
        end)
    end
end

local function isMobyUser(player)
    if not player or not player.Character then return false end
    return player.Character:FindFirstChild("_moby_highlight") ~= nil
end

local HighlightName = "KaWaifu_NeonHighlight"
local function isKawaifuUser(player)
    if not player or not player.Character then return false end
    return player.Character:FindFirstChild(HighlightName) ~= nil
end

_G.InvisStealAngle = Config.InvisStealAngle
_G.SinkSliderValue = Config.SinkSliderValue
_G.AutoRecoverLagback = Config.AutoRecoverLagback
_G.AutoInvisDuringSteal = Config.AutoInvisDuringSteal
    _G.INVISIBLE_STEAL_KEY = Enum.KeyCode[Config.InvisToggleKey] or Enum.KeyCode.I
_G.invisibleStealEnabled = false
_G.RecoveryInProgress = false

local function getControls()
	local playerScripts = LocalPlayer:WaitForChild("PlayerScripts")
	local playerModule = require(playerScripts:WaitForChild("PlayerModule"))
	return playerModule:GetControls()
end

local Controls = getControls()

local function kickPlayer()
    local ok = pcall(function()
        game:Shutdown()
    end)
    if ok then return end
    pcall(function()
        LocalPlayer:Kick("")
    end)
end

local function walkForward(seconds)
    local char = LocalPlayer.Character
    local hum = char:FindFirstChild("Humanoid")
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local Controls = getControls()
    local lookVector = hrp.CFrame.LookVector
    Controls:Disable()
    local startTime = os.clock()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        if os.clock() - startTime >= seconds then
            conn:Disconnect()
            hum:Move(Vector3.zero, false)
            Controls:Enable()
            return
        end
        hum:Move(lookVector, false)
    end)
end


-- ============================================================
-- CLONE SYSTEM
-- ============================================================
local function instantClone()
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then return end
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    local cloner = LocalPlayer.Backpack:FindFirstChild("Quantum Cloner")
        or character:FindFirstChild("Quantum Cloner")
    if not cloner then return end

    if cloner.Parent ~= character then
        humanoid:EquipTool(cloner)
        task.wait()
    end

    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
    local toolsFrames = PlayerGui:FindFirstChild("ToolsFrames")
    local qcFrame = toolsFrames and toolsFrames:FindFirstChild("QuantumCloner")
    local tpButton = qcFrame and qcFrame:FindFirstChild("TeleportToClone")
    if not tpButton then return end

    cloner:Activate()

    -- 0.03s delay then fire regardless
    task.wait(0.05)

    tpButton.Visible = true
    if typeof(firesignal) == "function" then
        firesignal(tpButton.MouseButton1Up)
if _G.triggerSafePollBoost then
    _G.triggerSafePollBoost()
end

    end
end


local function waitSecondsHeartbeat(sec)
    local t = 0
    while t < sec do
        t += RunService.Heartbeat:Wait()
    end
end

local function waitUntilHeartbeat(predicate, timeoutSec)
    local t = 0
    while true do
        if predicate() then return true end
        local dt = RunService.Heartbeat:Wait()
        t += dt
        if timeoutSec and t >= timeoutSec then
            return false
        end
    end
end


local function getClosestBaseSign(brainrotPart)
    if not brainrotPart or not brainrotPart:IsA("BasePart") then return nil end

    local closestPart = nil
    local closestDist = math.huge

    for _, label in ipairs(Workspace:GetDescendants()) do
        if label:IsA("TextLabel") then
            local txt = tostring(label.Text or "")
            if txt ~= "" and txt:lower():find("base", 1, true) then
                local gui = label:FindFirstAncestorWhichIsA("SurfaceGui")
                if gui then
                    local part = gui.Adornee or gui.Parent
                    if part and part:IsA("BasePart") then
                        local dist = (part.Position - brainrotPart.Position).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestPart = part
                        end
                    end
                end
            end
        end
    end

    return closestPart
end

local function riseToY(hrp, targetY)
    if not hrp then return end
    local MAX_TIME = 3.0
    local start = os.clock()

    while hrp.Parent and hrp.Position.Y < targetY do
        local dist = targetY - hrp.Position.Y
        local speed = math.clamp(dist * 20, 280, 310)
        hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, speed, hrp.AssemblyLinearVelocity.Z)
        if os.clock() - start > MAX_TIME then
            break
        end
        RunService.Heartbeat:Wait()
    end

    hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
end

local function equipTpToolAndWait(hum)
    if not hum then return nil end

    local char = hum.Parent
    local toolName = Config.TpSettings.Tool or "Flying Carpet"
    local tool = LocalPlayer.Backpack:FindFirstChild(toolName) or (char and char:FindFirstChild(toolName))

    if tool then
        if tool.Parent ~= char then
            hum:EquipTool(tool)
        else
            hum:EquipTool(tool)
        end
        task.wait(0.02)
    end

    return tool
end

local function prepMiniTpTool(hum, hrp)
    if not hum or not hrp then return end

    local char = hum.Parent
    local toolName = Config.TpSettings.Tool or "Flying Carpet"
    local tool = LocalPlayer.Backpack:FindFirstChild(toolName) or (char and char:FindFirstChild(toolName))
    if not tool then return end

    -- En este punto ya debio venir equipado desde antes del TP general.
    -- Aqui no reequipamos ni esperamos 0.02 para no tocar el tramo de airpos/mini tp.
end

local UserInputService = game:GetService("UserInputService")

local TP_V2_MED_POINTS = {
    {name = "MED1", pos = Vector3.new(-410.65, -5.68, -46.10)},
    {name = "MED2", pos = Vector3.new(-410.91, -5.68, 168.89)},
}

local TP_V2_SECOND_FLOOR_POINTS = {
    {name = "TP1",  pos = Vector3.new(-488.88, 15, 196.38), facing = "back"},
    {name = "TP2",  pos = Vector3.new(-487.79, 15, 138.13), facing = "front"},
    {name = "TP3",  pos = Vector3.new(-489.38, 15, 89.23),  facing = "back"},
    {name = "TP4",  pos = Vector3.new(-489.69, 15, 30.98),  facing = "front"},
    {name = "TP5",  pos = Vector3.new(-488.75, 15, -17.95), facing = "back"},
    {name = "TP6",  pos = Vector3.new(-490, 15, -75.90), facing = "front"},
    {name = "TP7",  pos = Vector3.new(-331.75, 15, -75.80), facing = "back"},
    {name = "TP8",  pos = Vector3.new(-329.98, 15, -18.16), facing = "front"},
    {name = "TP9",  pos = Vector3.new(-330.04, 15, 31.14),  facing = "back"},
    {name = "TP10", pos = Vector3.new(-331.28, 15, 88.92),  facing = "front"},
    {name = "TP11", pos = Vector3.new(-330.57, 15, 138.10), facing = "back"},
    {name = "TP12", pos = Vector3.new(-330.01, 15, 195.96), facing = "front"},
}

local function flatDistance(a, b)
    return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function getClosestBaseSignToPosition(worldPos)
    local closestPart = nil
    local closestDist = math.huge

    for _, label in ipairs(Workspace:GetDescendants()) do
        if label:IsA("TextLabel") then
            local txt = tostring(label.Text or "")
            if txt ~= "" and txt:lower():find("base", 1, true) then
                local gui = label:FindFirstAncestorWhichIsA("SurfaceGui")
                if gui then
                    local part = gui.Adornee or gui.Parent
                    if part and part:IsA("BasePart") then
                        local dist = (part.Position - worldPos).Magnitude
                        if dist < closestDist then
                            closestDist = dist
                            closestPart = part
                        end
                    end
                end
            end
        end
    end

    return closestPart
end

local function getNearestTeleportV2MedPoint(fromPos)
    local bestPoint = nil
    local bestDist = math.huge

    for _, entry in ipairs(TP_V2_MED_POINTS) do
        local dist = flatDistance(fromPos, entry.pos)
        if dist < bestDist then
            bestDist = dist
            bestPoint = entry
        end
    end

    return bestPoint, bestDist
end

local TP_V2_ALLOWED_BY_MED = {
    MED1 = {
        TP6 = true, TP7 = true, TP8 = true, TP10 = true,
        TP12 = true, TP5 = true, TP3 = true, TP1 = true,
    },
    MED2 = {
        TP1 = true, TP2 = true, TP4 = true, TP6 = true,
        TP7 = true, TP9 = true, TP11 = true, TP12 = true,
    },
}

local function getBestTeleportV2SecondFloorPoint(brainrotPos)
    local bestPoint = nil
    local bestBrainrotDist = math.huge

    for _, entry in ipairs(TP_V2_SECOND_FLOOR_POINTS) do
        local distToBrainrot = flatDistance(brainrotPos, entry.pos)
        if distToBrainrot < bestBrainrotDist then
            bestPoint = entry
            bestBrainrotDist = distToBrainrot
        end
    end

    return bestPoint
end

local function getBestMedForPoint(tpPoint)
    local bestMed = nil
    local bestDist = math.huge
    for _, med in ipairs(TP_V2_MED_POINTS) do
        local allowed = TP_V2_ALLOWED_BY_MED[med.name]
        if allowed and allowed[tpPoint.name] then
            local d = flatDistance(med.pos, tpPoint.pos)
            if d < bestDist then
                bestDist = d
                bestMed = med
            end
        end
    end
    -- fallback: nearest MED regardless of allowed table
    if not bestMed then
        bestMed = getNearestTeleportV2MedPoint(tpPoint.pos)
    end
    return bestMed
end

local function runTeleportV2SecondFloor(targetPart, hum, hrp)
    if not targetPart or not hum or not hrp then return false, "missing target/hum/hrp" end

    local initialPlayerPos = hrp.Position
    local initialBrainrotPos = targetPart.Position

    local currentBrainrotPos = targetPart.Position
    local chosenPoint = getBestTeleportV2SecondFloorPoint(currentBrainrotPos)
    if not chosenPoint then
        return false, "no TP1-TP12 point found"
    end

    local medPoint = getBestMedForPoint(chosenPoint)
    if not medPoint then
        return false, "no MED point found"
    end

    local isFirstFloorBrainrot = currentBrainrotPos.Y <= 6.313370704650879
    local chosenTargetPos = isFirstFloorBrainrot
        and Vector3.new(chosenPoint.pos.X, 1, chosenPoint.pos.Z)
        or chosenPoint.pos

    -- GIRO V2 INICIAL ESTILO BRUH:
    -- usa la misma direccion que ya usaba este V2 para mirar al llegar a TP1-TP12,
    -- pero ahora se aplica antes de empezar todo el TP y se bloquea la camara hasta terminar.
    local signPart = getClosestBaseSignToPosition(chosenTargetPos) or getClosestBaseSign(targetPart)
    local faceVector = nil
    if signPart then
        faceVector = chosenPoint.facing == "front" and signPart.CFrame.LookVector or -signPart.CFrame.LookVector
        if faceVector.Magnitude <= 0 then
            faceVector = nil
        end
    end

    local camera = Workspace.CurrentCamera
    local prevCameraType = camera and camera.CameraType
    local prevFov = camera and camera.FieldOfView
    local camConn = nil

    if faceVector then
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + faceVector)
        hrp.AssemblyLinearVelocity = Vector3.zero
    end

    if camera then
        camera.CameraType = Enum.CameraType.Scriptable
        camera.FieldOfView = 95
        camConn = RunService.RenderStepped:Connect(function()
            local cHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if cHrp and camera then
                camera.CFrame = cHrp.CFrame * CFrame.new(0, 2, 10) * CFrame.Angles(math.rad(-5), 0, 0)
            end
        end)
    end

    local function stopCameraLock()
        if camConn then
            camConn:Disconnect()
            camConn = nil
        end
        if camera then
            if prevCameraType then camera.CameraType = prevCameraType end
            if prevFov then camera.FieldOfView = prevFov end
        end
    end

    local function finish(ok, msg)
        stopCameraLock()
        return ok, msg
    end

    hrp.AssemblyLinearVelocity = Vector3.zero

    -- Flujo V2 corregido:
    -- 1) arranca salto
    -- 2) TP a MED1/MED2 usando SOLO X/Z del MED y la Y actual del personaje
    -- 3) sigue con riseToY
    -- 4) luego TP al punto TP1-TP12 permitido
    -- 5) si el brainrot está en primer piso, usa esas mismas coordenadas TP1-TP12 pero con altura fija -3.28
    local riseTargetY = 45

    if hum and hum.Parent then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
    task.wait(0.01)

    if not hrp or not hrp.Parent then
        return finish(false, "hrp lost during jump start")
    end

    local medFlatPos = Vector3.new(medPoint.pos.X, hrp.Position.Y, medPoint.pos.Z)
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = faceVector and CFrame.new(medFlatPos, medFlatPos + faceVector) or CFrame.new(medFlatPos)
    hrp.AssemblyLinearVelocity = Vector3.zero
    task.wait(Config.TpSettings.TpSpeed or 0.1)

    if not hrp or not hrp.Parent then
        return finish(false, "hrp lost after MED reposition")
    end

    local reachedMedPoint = waitUntilHeartbeat(function()
        return hrp and hrp.Parent and flatDistance(hrp.Position, medPoint.pos) <= 2.5
    end, 1.5)

    if not reachedMedPoint then
        return finish(false, "failed to reach MED point")
    end

    riseToY(hrp, riseTargetY)

    hrp.AssemblyLinearVelocity = Vector3.zero
    -- Ya se giro al inicio; aqui solo conserva esa misma orientacion durante el TP a TP1-TP12.
    hrp.CFrame = faceVector and CFrame.new(chosenTargetPos, chosenTargetPos + faceVector) or CFrame.new(chosenTargetPos)
    hrp.AssemblyLinearVelocity = Vector3.zero

    local reachedChosenPoint = waitUntilHeartbeat(function()
        return hrp and hrp.Parent and (hrp.Position - chosenTargetPos).Magnitude <= 2.5
    end, 3.0)

    if not reachedChosenPoint then
        return finish(false, "failed to reach TP1-TP12")
    end

waitSecondsHeartbeat(Config.TpSettings.Floor2WaitTime or 0.25)

    -- Giro posterior eliminado: ahora el V2 gira antes de todo y mantiene camara bloqueada estilo BRUH.
    waitSecondsHeartbeat(0.05)

    -- VERIFICACION FUERTE ANTES DEL CLON:
    -- ya habia confirmado que llego a TP1-TP12, pero ahora confirma otra vez
    -- que SIGUE en esas coordenadas justo antes de activar Quantum Cloner.
    local stillAtChosenPoint = waitUntilHeartbeat(function()
        return hrp and hrp.Parent and (hrp.Position - chosenTargetPos).Magnitude <= 2.5
    end, 0.75)

    if not stillAtChosenPoint then
        return finish(false, "moved away from TP1-TP12 before clone")
    end

    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    -- Active instant steal au moment du clone
    local wasInstantSteal = Config.InstantSteal == true
    if _G._hazeSetInstantSteal and not wasInstantSteal then
        _G._hazeSetInstantSteal(true)
    end

    local cloneStartPos = hrp.Position
    instantClone()
    waitUntilHeartbeat(function()
        return hrp and hrp.Parent and ((hrp.Position - cloneStartPos).Magnitude >= 0.35)
    end, 4.0)
    while _G.isCloning do task.wait() end
    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * 0.35
    end

    return finish(true, chosenPoint.name)
end

-- ============================================================
-- TELEPORT V3 - SLIDE AVEC CARPET
-- ============================================================
local function runTeleportV3(targetPart, targetPetData, hum, hrp, exactPos)
    if not targetPart or not hum or not hrp then return false, "missing args" end

    -- Désactiver les animations de marche
    local char = LocalPlayer.Character
    local animScript = char and char:FindFirstChild("Animate")
    if animScript then animScript.Disabled = true end
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if animator then
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
            track:Stop(0)
        end
    end

    -- Annuler la gravité pendant les slides (pas de ricochet)
    local _antiGravActive = true
    local antiGravConn = RunService.Heartbeat:Connect(function()
        if not _antiGravActive then return end
        if hrp and hrp.Parent then
            local vy = hrp.AssemblyLinearVelocity.Y
            if vy < 0 then
                hrp.AssemblyLinearVelocity = Vector3.new(
                    hrp.AssemblyLinearVelocity.X,
                    0,
                    hrp.AssemblyLinearVelocity.Z
                )
            end
        end
    end)
    local function removePlatform()
        _antiGravActive = false
        antiGravConn:Disconnect()
    end
    local function cleanPlatform()
        removePlatform()
        if animScript then animScript.Disabled = false end
    end

    local function slideToward(target, speed, timeout, stopThresh)
        speed = speed or 150
        timeout = timeout or 6
        stopThresh = stopThresh or 2
        local deadline = tick() + timeout
        while tick() < deadline do
            if not hrp or not hrp.Parent then return false end
            local diff = target - hrp.Position
            local flat = Vector3.new(diff.X, 0, diff.Z)
            if flat.Magnitude <= stopThresh then break end
            local dir = flat.Unit
            hrp.AssemblyLinearVelocity = Vector3.new(dir.X * speed, hrp.AssemblyLinearVelocity.Y, dir.Z * speed)
            RunService.Heartbeat:Wait()
        end
        hrp.AssemblyLinearVelocity = Vector3.zero
        return true
    end

    local signPart = getClosestBaseSign(targetPart)
    if not signPart then cleanPlatform(); return false, "signPart nil" end

    local signCF = signPart.CFrame
    local LEFT    = -signCF.RightVector
    local FORWARD = signCF.LookVector
    local BACK    = -FORWARD

    local tpPos
    if exactPos.Y <= 6.313370704650879 then
        local frontPoint = signPart.Position + (FORWARD * 20)
        local backPoint  = signPart.Position + (BACK * 20)
        local myPos = hrp.Position
        local distFront = (Vector3.new(frontPoint.X,0,frontPoint.Z) - Vector3.new(myPos.X,0,myPos.Z)).Magnitude
        local distBack  = (Vector3.new(backPoint.X, 0,backPoint.Z)  - Vector3.new(myPos.X,0,myPos.Z)).Magnitude
        local chosen = (distFront < distBack) and frontPoint or backPoint
        tpPos = Vector3.new(chosen.X, -4.8, chosen.Z)
    else
        local backPoint  = signPart.Position + (BACK * 15)
        local frontPoint = signPart.Position + (FORWARD * 15)
        local myPos = hrp.Position
        local distBack  = (Vector3.new(backPoint.X, 0,backPoint.Z)  - Vector3.new(myPos.X,0,myPos.Z)).Magnitude
        local distFront = (Vector3.new(frontPoint.X,0,frontPoint.Z) - Vector3.new(myPos.X,0,myPos.Z)).Magnitude
        local chosen = (distBack < distFront) and backPoint or frontPoint
        tpPos = Vector3.new(chosen.X, signPart.Position.Y + 4, chosen.Z)
    end

    hrp.AssemblyLinearVelocity = Vector3.zero
    if hum and hum.Parent then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    task.wait(0.01)
    if not hrp or not hrp.Parent then cleanPlatform(); return false, "hrp lost" end

    -- 1) Slide vers la zone d'approche X=-409
    slideToward(Vector3.new(-409, hrp.Position.Y, hrp.Position.Z), 145, 5, 3)

    -- 2) Monter à Y=25 (sauté si déjà en hauteur depuis le spawn)
    if hrp.Position.Y < 22 then
        riseToY(hrp, 25)
    end

    -- 3) Slide horizontal vers tpPos
    slideToward(Vector3.new(tpPos.X, hrp.Position.Y, tpPos.Z), 145, 5, 2)

    -- 4) Orienter vers LEFT puis descendre au sol
    hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + LEFT)
    _antiGravActive = false
    hrp.AssemblyLinearVelocity = Vector3.new(0, -100, 0)
    waitUntilHeartbeat(function()
        return hrp and hrp.Parent and hrp.Position.Y <= (tpPos.Y + 3)
    end, 2.0)
    hrp.AssemblyLinearVelocity = Vector3.zero
    _antiGravActive = true

    -- 5) Base ouverte ?
    local isFloor2 = exactPos.Y > 6.313370704650879
    local baseOpen = false
    if not isFloor2 and targetPetData.plot and _G._isTargetPlotUnlocked then
        pcall(function() baseOpen = _G._isTargetPlotUnlocked(targetPetData.plot) end)
    end

    -- 6) Enlever la plateforme puis avancer vers l'entrée
    removePlatform()
    if not baseOpen then
        local f1t = Config.TpSettings.Floor1WalkTime or 0.45
        walkForward(f1t)
        waitSecondsHeartbeat(f1t + 0.02)
    end

    -- 7) Clone pour entrer
    local miniPos = hrp.Position
    local stillAt = waitUntilHeartbeat(function()
        return hrp and hrp.Parent and (hrp.Position - miniPos).Magnitude <= 2.0
    end, 0.75)
    if not stillAt then cleanPlatform(); return false, "moved before clone" end

    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    instantClone()
    waitUntilHeartbeat(function()
        return hrp and hrp.Parent and ((hrp.Position - miniPos).Magnitude >= 0.35)
    end, 4.0)
    while _G.isCloning do task.wait() end
    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * 0.35
    end

    -- Slide vers le brainrot après le clone
    task.wait(0.15)
    if hrp and hrp.Parent and targetPart and targetPart.Parent then
        local isThirdFloor = exactPos.Y >= 28
        local goalPos = isThirdFloor
            and Vector3.new(targetPart.Position.X, targetPart.Position.Y - 8, targetPart.Position.Z)
            or targetPart.Position
        slideToward(goalPos, 145, 3, 1.5)
        hrp.AssemblyLinearVelocity = Vector3.zero
        local deadline = tick() + 1.5
        while tick() < deadline do
            if LocalPlayer:GetAttribute("Stealing") then break end
            RunService.Heartbeat:Wait()
            if hrp and (hrp.Position - goalPos).Magnitude > 2 then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.CFrame = CFrame.new(goalPos)
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
        end
    end

    cleanPlatform()
    return true
end

-- ============================================================
-- AUTO UNLOCK / PROXIMITY PROMPT
-- ============================================================
local function triggerClosestUnlock(yLevel, maxY)
    local character = LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local playerY = yLevel or hrp.Position.Y
    local Y_THRESHOLD = 5

    local bestPromptSameLevel = nil
    local shortestDistSameLevel = math.huge

    local bestPromptFallback = nil
    local shortestDistFallback = math.huge
    
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end

    for _, obj in ipairs(plots:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local part = obj.Parent
            if part and part:IsA("BasePart") then
                if maxY and part.Position.Y > maxY then
                else
                    local distance = (hrp.Position - part.Position).Magnitude
                    local yDifference = math.abs(playerY - part.Position.Y)

                    if distance < shortestDistFallback then
                        shortestDistFallback = distance
                        bestPromptFallback = obj
                    end

                    if yDifference <= Y_THRESHOLD then
                        if distance < shortestDistSameLevel then
                            shortestDistSameLevel = distance
                            bestPromptSameLevel = obj
                        end
                    end
                end
            end
        end
    end

    local targetPrompt = bestPromptSameLevel or bestPromptFallback

    if targetPrompt then
        if fireproximityprompt then
            fireproximityprompt(targetPrompt)
        else
            targetPrompt:InputBegan(Enum.UserInputType.MouseButton1)
            task.wait(0.05)
            targetPrompt:InputEnded(Enum.UserInputType.MouseButton1)
        end
    end

end

-- ============================================================
-- UNLOCK BASE FLOATING HUD
-- ============================================================
local CoreGui = game:GetService("CoreGui")

local unlockBaseGui = nil
local unlockBaseFrame = nil
local unlockBaseRoot = nil
local unlockBaseLockButton = nil
local unlockBaseButtonsBar = nil

local UNLOCK_UI_SAVE_FILE = "HazeButtonsClean2_Pos.json"

local function saveUnlockUIData(pos, locked)
    pcall(function()
        if writefile then
            writefile(UNLOCK_UI_SAVE_FILE, HttpService:JSONEncode({
                xScale = pos.X.Scale,
                xOffset = pos.X.Offset,
                yScale = pos.Y.Scale,
                yOffset = pos.Y.Offset,
                locked = locked
            }))
        end
    end)
end

local function loadUnlockUIData()
    local defaultPos = UDim2.new(0.5, -108, 0.5, -21)
    local defaultLocked = false

    local ok, data = pcall(function()
        if readfile and isfile and isfile(UNLOCK_UI_SAVE_FILE) then
            return HttpService:JSONDecode(readfile(UNLOCK_UI_SAVE_FILE))
        end
    end)

    if ok and data then
        return UDim2.new(
            data.xScale or 0.5,
            data.xOffset or -108,
            data.yScale or 0.5,
            data.yOffset or -21
        ), data.locked == true
    end

    return defaultPos, defaultLocked
end

local function getUnlockHRP()
    local c = LocalPlayer.Character
    if not c then return end
    return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso")
end

local function smartInteract(number)
    local char = LocalPlayer.Character
    local hrp = getUnlockHRP()
    if not char or not hrp then return end

    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return end

    local closestPlot, minDistance = nil, 40

    for _, plot in pairs(plots:GetChildren()) do
        local plotPos
        if plot:IsA("Model") then
            plotPos = plot.PrimaryPart and plot.PrimaryPart.Position or plot:GetPivot().Position
        else
            plotPos = plot.Position
        end

        local dist = (hrp.Position - plotPos).Magnitude
        if dist < minDistance then
            closestPlot = plot
            minDistance = dist
        end
    end

    if closestPlot and closestPlot:FindFirstChild("Unlock") then
        local items = {}

        for _, item in pairs(closestPlot.Unlock:GetChildren()) do
            local pos = item:IsA("Model") and item:GetPivot().Position or item.Position
            table.insert(items, {
                Obj = item,
                Y = pos.Y
            })
        end

        table.sort(items, function(a, b)
            return a.Y < b.Y
        end)

        if items[number] then
            for _, pr in pairs(items[number].Obj:GetDescendants()) do
                if pr:IsA("ProximityPrompt") then
                    pcall(function()
                        fireproximityprompt(pr)
                    end)
                end
            end
        end
    end
end

local function getCurrentUnlockFloor()
    local hrp = getUnlockHRP()
    if not hrp then return 1 end

    local y = hrp.Position.Y
    if y < 12 then
        return 1
    elseif y < 30 then
        return 2
    else
        return 3
    end
end

local function autoUnlockCurrentFloor()
    local floor = getCurrentUnlockFloor()
    smartInteract(floor)
    ShowNotification("AUTO UNLOCK", "Level " .. tostring(floor))
end

local function destroyUnlockBaseMenu()
    if unlockBaseGui then
        pcall(function()
            unlockBaseGui:Destroy()
        end)
    end
    unlockBaseGui = nil
    unlockBaseFrame = nil
    unlockBaseRoot = nil
    unlockBaseLockButton = nil
    unlockBaseButtonsBar = nil
end

function toggleUnlockBaseMenu(state)
    if not state then
        destroyUnlockBaseMenu()
        return
    end

    destroyUnlockBaseMenu()

    local startPos, dragLocked = loadUnlockUIData()

    local function round(obj, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius)
        c.Parent = obj
        return c
    end

    local function stroke(obj, color, thickness, transparency)
        local s = Instance.new("UIStroke")
        s.Color = color
        s.Thickness = thickness or 1
        s.Transparency = transparency or 0
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = obj
        return s
    end

    local function tween(obj, t, props, style, dir)
        TweenService:Create(
            obj,
            TweenInfo.new(t or 0.16, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
            props
        ):Play()
    end

    local function makeGradient(parent, c1, c2, rot)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, c1),
            ColorSequenceKeypoint.new(1, c2),
        })
        g.Rotation = rot or 0
        g.Parent = parent
        return g
    end

    local UIC = {
        BG = Color3.fromRGB(8, 15, 12),
        SURF = Color3.fromRGB(10, 25, 18),
        TEXT = Color3.fromRGB(225, 255, 235),
        AQUA_STROKE = Color3.fromRGB(65, 180, 105),
        ACTIVE1 = Color3.fromRGB(80, 210, 120),
        ACTIVE2 = Color3.fromRGB(55, 160, 90),
        LOCK_RED_1 = Color3.fromRGB(200, 40, 40),
        LOCK_RED_2 = Color3.fromRGB(160, 20, 20),
        LOCK_GREEN_1 = Color3.fromRGB(70, 160, 115),
        LOCK_GREEN_2 = Color3.fromRGB(55, 135, 95),
    }

    local sg = Instance.new("ScreenGui")
    sg.Name = "UnlockBaseGUI"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.Parent = CoreGui

    unlockBaseGui = sg

    local root = Instance.new("Frame")
    root.Name = "UnlockRoot"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromOffset(204, 42)
    root.Position = startPos
    root.Parent = sg
    unlockBaseRoot = root

    local lockFrame = Instance.new("TextButton")
    lockFrame.Name = "LockFrame"
    lockFrame.AutoButtonColor = false
    lockFrame.Text = ""
    lockFrame.Size = UDim2.fromOffset(32, 32)
    lockFrame.Position = UDim2.fromOffset(0, 5)
    lockFrame.BackgroundColor3 = UIC.LOCK_RED_1
    lockFrame.BorderSizePixel = 0
    lockFrame.Parent = root
    unlockBaseLockButton = lockFrame
    round(lockFrame, 10)

    local lockFill = Instance.new("Frame")
    lockFill.Name = "Fill"
    lockFill.BackgroundColor3 = UIC.LOCK_RED_1
    lockFill.BorderSizePixel = 0
    lockFill.Size = UDim2.fromScale(1, 1)
    lockFill.Position = UDim2.fromScale(0, 0)
    lockFill.Parent = lockFrame
    round(lockFill, 10)

    local lockGrad = makeGradient(lockFill, UIC.LOCK_RED_1, UIC.LOCK_RED_2, 90)

    local function refreshLock()
        if dragLocked then
            lockFrame.BackgroundColor3 = UIC.LOCK_RED_1
            lockFill.BackgroundColor3 = UIC.LOCK_RED_1
            lockGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, UIC.LOCK_RED_1),
                ColorSequenceKeypoint.new(1, UIC.LOCK_RED_2),
            })
        else
            lockFrame.BackgroundColor3 = UIC.LOCK_GREEN_1
            lockFill.BackgroundColor3 = UIC.LOCK_GREEN_1
            lockGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, UIC.LOCK_GREEN_1),
                ColorSequenceKeypoint.new(1, UIC.LOCK_GREEN_2),
            })
        end
    end

    refreshLock()

    lockFrame.MouseButton1Click:Connect(function()
        dragLocked = not dragLocked
        refreshLock()
        saveUnlockUIData(root.Position, dragLocked)
    end)

    local frame = Instance.new("Frame")
    frame.Name = "UnlockButtonsBar"
    frame.Size = UDim2.fromOffset(168, 42)
    frame.Position = UDim2.fromOffset(36, 0)
    frame.BackgroundColor3 = UIC.BG
    frame.BorderSizePixel = 0
    frame.Parent = root
    unlockBaseFrame = frame
    unlockBaseButtonsBar = frame
    round(frame, 11)
    stroke(frame, UIC.AQUA_STROKE, 1.2, 0.30)

    local frameInner = Instance.new("Frame")
    frameInner.Name = "Inner"
    frameInner.BackgroundColor3 = UIC.SURF
    frameInner.BorderSizePixel = 0
    frameInner.Size = UDim2.new(1, 0, 1, 0)
    frameInner.Parent = frame
    round(frameInner, 11)

    local padding = Instance.new("UIPadding")
    padding.Parent = frameInner
    padding.PaddingLeft = UDim.new(0, 5)
    padding.PaddingRight = UDim.new(0, 5)
    padding.PaddingTop = UDim.new(0, 5)
    padding.PaddingBottom = UDim.new(0, 5)

    local layout = Instance.new("UIListLayout")
    layout.Parent = frameInner
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 4)

    local function makeBtn(txt)
        local b = Instance.new("TextButton")
        b.Name = "Unlock" .. tostring(txt)
        b.AutoButtonColor = false
        b.Text = ""
        b.Size = UDim2.fromOffset(50, 30)
        b.BackgroundColor3 = UIC.ACTIVE1
        b.BorderSizePixel = 0
        b.Parent = frameInner
        round(b, 8)

        local btnStroke = stroke(b, UIC.AQUA_STROKE, 1, 0.12)

        local fill = Instance.new("Frame")
        fill.BackgroundTransparency = 0
        fill.BorderSizePixel = 0
        fill.Size = UDim2.fromScale(1, 1)
        fill.Parent = b
        round(fill, 8)
        makeGradient(fill, UIC.ACTIVE1, UIC.ACTIVE2, 90)

        local txtLabel = Instance.new("TextLabel")
        txtLabel.BackgroundTransparency = 1
        txtLabel.Size = UDim2.fromScale(1, 1)
        txtLabel.Font = Enum.Font.GothamBold
        txtLabel.Text = tostring(txt)
        txtLabel.TextSize = 13
        txtLabel.TextColor3 = UIC.TEXT
        txtLabel.Parent = b

        b.MouseEnter:Connect(function()
            tween(btnStroke, 0.12, {Transparency = 0.02})
        end)

        b.MouseLeave:Connect(function()
            tween(btnStroke, 0.12, {Transparency = 0.12})
        end)

        b.MouseButton1Down:Connect(function()
            b.Size = UDim2.fromOffset(48, 28)
        end)

        b.MouseButton1Up:Connect(function()
            b.Size = UDim2.fromOffset(50, 30)
        end)

        return b
    end

    local b1 = makeBtn("1")
    local b2 = makeBtn("2")
    local b3 = makeBtn("3")

    b1.MouseButton1Click:Connect(function()
        smartInteract(1)
        ShowNotification("UNLOCK", "Level 1")
    end)

    b2.MouseButton1Click:Connect(function()
        smartInteract(2)
        ShowNotification("UNLOCK", "Level 2")
    end)

    b3.MouseButton1Click:Connect(function()
        smartInteract(3)
        ShowNotification("UNLOCK", "Level 3")
    end)

    local dragging = false
    local dragStart
    local startRootPos

    root.InputBegan:Connect(function(input)
        if dragLocked then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startRootPos = root.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    saveUnlockUIData(root.Position, dragLocked)
                end
            end)
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragLocked then return end
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            root.Position = UDim2.new(
                startRootPos.X.Scale,
                startRootPos.X.Offset + delta.X,
                startRootPos.Y.Scale,
                startRootPos.Y.Offset + delta.Y
            )
        end
    end)
end

local Theme = {
    Background      = Color3.fromRGB(10, 18, 14),
    Surface         = Color3.fromRGB(12, 30, 22),
    SurfaceHighlight= Color3.fromRGB(18, 50, 36),
    Accent1         = Color3.fromRGB(80, 210, 120),
    Accent2         = Color3.fromRGB(55, 160, 90),
    TextPrimary     = Color3.fromRGB(225, 255, 235),
    TextSecondary   = Color3.fromRGB(140, 200, 165),
    Success         = Color3.fromRGB(80, 210, 120),
    Error           = Color3.fromRGB(200, 60, 80),
}

local PRIORITY_LIST = {}

local function LoadPriorityListFromConfig()
    for i = #PRIORITY_LIST, 1, -1 do
        PRIORITY_LIST[i] = nil
    end
    for i, v in ipairs(Config.PriorityList or {}) do
        PRIORITY_LIST[i] = v
    end
end

local function SavePriorityListToConfig()
    Config.PriorityList = {}
    for i, v in ipairs(PRIORITY_LIST) do
        Config.PriorityList[i] = v
    end
end

LoadPriorityListFromConfig()


local function findAdorneeGlobal(animalData)
    if not animalData then return nil end
    local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild(animalData.plot)
    if plot then
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if podiums then
            local podium = podiums:FindFirstChild(animalData.slot)
            if podium then
                local base = podium:FindFirstChild("Base")
                if base then
                    local spawn = base:FindFirstChild("Spawn")
                    if spawn then return spawn end
                    return base:FindFirstChildWhichIsA("BasePart") or base
                end
            end
        end
    end
    return nil
end

local function CreateGradient(parent)
    local g = Instance.new("UIGradient", parent)
    g.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Theme.Accent2),
        ColorSequenceKeypoint.new(1, Theme.Accent2)
    }
    g.Rotation = 45
    return g
end

local function ApplyViewportUIScale(targetFrame, designWidth, designHeight, minScale, maxScale)
    if not targetFrame then return end
    if not IS_MOBILE then return end
    local existing = targetFrame:FindFirstChildOfClass("UIScale")
    if existing then existing:Destroy() end
    local sc = Instance.new("UIScale")
    sc.Parent = targetFrame
    SharedState.MobileScaleObjects[targetFrame] = sc
    if SharedState.RefreshMobileScale then
        SharedState.RefreshMobileScale()
    else
        sc.Scale = math.clamp(tonumber(Config.MobileGuiScale) or 0.5, 0, 1)
    end
end

SharedState.RefreshMobileScale = function()
    local s = math.clamp(tonumber(Config.MobileGuiScale) or 0.5, 0, 1)
    for frame, sc in pairs(SharedState.MobileScaleObjects) do
        if frame and frame.Parent and sc and sc.Parent == frame then
            sc.Scale = s
        else
            SharedState.MobileScaleObjects[frame] = nil
        end
    end
end

local function AddMobileMinimize(frame, labelText)
    if not IS_MOBILE then return end
    if not frame or not frame.Parent then return end
    local guiParent = frame.Parent
    local header = frame:FindFirstChildWhichIsA("Frame")
    if not header then return end

    local minimizeBtn = Instance.new("TextButton")
    minimizeBtn.Size = UDim2.new(0, 26, 0, 26)
    minimizeBtn.Position = UDim2.new(1, -30, 0, 6)
    minimizeBtn.BackgroundColor3 = Theme.SurfaceHighlight
    minimizeBtn.Text = "-"
    minimizeBtn.Font = Enum.Font.GothamBlack
    minimizeBtn.TextSize = 18
    minimizeBtn.TextColor3 = Theme.TextPrimary
    minimizeBtn.AutoButtonColor = false
    minimizeBtn.Parent = header
    Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0, 8)

    local restoreBtn = Instance.new("TextButton")
    restoreBtn.Size = UDim2.new(0, 110, 0, 34)
    restoreBtn.Position = UDim2.new(0, 10, 1, -44)
    restoreBtn.BackgroundColor3 = Theme.SurfaceHighlight
    restoreBtn.Text = labelText or "OPEN"
    restoreBtn.Font = Enum.Font.GothamBold
    restoreBtn.TextSize = 12
    restoreBtn.TextColor3 = Theme.TextPrimary
    restoreBtn.Visible = false
    restoreBtn.AutoButtonColor = false
    restoreBtn.Parent = guiParent
    Instance.new("UICorner", restoreBtn).CornerRadius = UDim.new(0, 10)

    MakeDraggable(restoreBtn, restoreBtn)

    minimizeBtn.MouseButton1Click:Connect(function()
        frame.Visible = false
        restoreBtn.Visible = true
    end)

    restoreBtn.MouseButton1Click:Connect(function()
        frame.Visible = true
        restoreBtn.Visible = false
    end)
end

local function MakeDraggable(handle, target, saveKey)
    local dragging, dragInput, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if Config.UILocked then return end
        if _G.ADMIN_PANEL_SLIDER_DRAG then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = target.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if saveKey then
Config.Positions[saveKey] = {
    X = target.Position.X.Scale,
    Y = target.Position.Y.Scale,
    OffsetX = target.Position.X.Offset,
    OffsetY = target.Position.Y.Offset,
}
                        SaveConfig()
                    end
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if _G.ADMIN_PANEL_SLIDER_DRAG then return end
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function ShowNotification(title, text)
    local existing = PlayerGui:FindFirstChild("XiNotif")
    if existing then existing:Destroy() end

    local sg = Instance.new("ScreenGui", PlayerGui)
    sg.Name = "XiNotif"; sg.ResetOnSpawn = false

    local f = Instance.new("Frame", sg)
    f.Size = UDim2.new(0, 290, 0, 54)
    f.Position = UDim2.new(0.5, -145, 0, 80)
    f.BackgroundColor3 = Color3.fromRGB(6, 6, 12)
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 9)

    local stroke = Instance.new("UIStroke", f)
    stroke.Thickness = 1; stroke.Color = Theme.Accent2; stroke.Transparency = 1

    local bar = Instance.new("Frame", f)
    bar.Size = UDim2.new(0, 3, 1, -12); bar.Position = UDim2.new(0, 5, 0, 6)
    bar.BackgroundColor3 = Theme.Accent1; bar.BorderSizePixel = 0
    bar.BackgroundTransparency = 1
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    local t1 = Instance.new("TextLabel", f)
    t1.Size = UDim2.new(1, -22, 0, 18); t1.Position = UDim2.new(0, 16, 0, 7)
    t1.BackgroundTransparency = 1; t1.Text = title:upper()
    t1.Font = Enum.Font.GothamBlack; t1.TextSize = 11
    t1.TextColor3 = Theme.Accent1; t1.TextXAlignment = Enum.TextXAlignment.Left
    t1.TextTransparency = 1

    local t2 = Instance.new("TextLabel", f)
    t2.Size = UDim2.new(1, -22, 0, 15); t2.Position = UDim2.new(0, 16, 0, 27)
    t2.BackgroundTransparency = 1; t2.Text = text
    t2.Font = Enum.Font.GothamMedium; t2.TextSize = 10
    t2.TextColor3 = Theme.TextSecondary; t2.TextXAlignment = Enum.TextXAlignment.Left
    t2.TextTransparency = 1

    local fadeIn = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(f,      fadeIn, {BackgroundTransparency = 0.08}):Play()
    TweenService:Create(stroke, fadeIn, {Transparency = 0.3}):Play()
    TweenService:Create(bar,    fadeIn, {BackgroundTransparency = 0}):Play()
    TweenService:Create(t1,     fadeIn, {TextTransparency = 0}):Play()
    TweenService:Create(t2,     fadeIn, {TextTransparency = 0}):Play()

    task.delay(2, function()
        if not sg.Parent then return end
        local fadeOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(f,      fadeOut, {BackgroundTransparency = 1}):Play()
        TweenService:Create(stroke, fadeOut, {Transparency = 1}):Play()
        TweenService:Create(bar,    fadeOut, {BackgroundTransparency = 1}):Play()
        TweenService:Create(t1,     fadeOut, {TextTransparency = 1}):Play()
        local last = TweenService:Create(t2, fadeOut, {TextTransparency = 1})
        last:Play(); last.Completed:Wait()
        if sg.Parent then sg:Destroy() end
    end)
end

local function isPlayerCharacter(model)
    return Players:GetPlayerFromCharacter(model) ~= nil
end

local function handleAnimator(animator)
    local model = animator:FindFirstAncestorOfClass("Model")
    if model and isPlayerCharacter(model) then return end
    for _, track in pairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
    animator.AnimationPlayed:Connect(function(track) track:Stop(0) end)
end

local FPSBOOST_DESC_ADDED_CONN = nil

local function stripVisuals(obj)
    local model = obj:FindFirstAncestorOfClass("Model")
    local isPlayer = model and isPlayerCharacter(model)

    if obj:IsA("Animator") then handleAnimator(obj) end

    if obj:IsA("Accessory") or obj:IsA("Clothing") then
        if obj:FindFirstAncestorOfClass("Model") then
            obj:Destroy()
        end
    end

    if not isPlayer then
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or
           obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") or
           obj:IsA("Highlight") then
            obj.Enabled = false
        end

        if obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
            obj.Enabled = false
            obj.Brightness = 0
            obj.Range = 0
            task.defer(function()
                pcall(function() obj:Destroy() end)
            end)
        end

        if obj:IsA("Explosion") then
            obj:Destroy()
        end

        if obj:IsA("MeshPart") then
            obj.TextureID = ""
        end
    end

    if obj:IsA("BasePart") then
        obj.Material = Enum.Material.Plastic
        obj.Reflectance = 0
        obj.CastShadow = false

        pcall(function()
            if obj.Material == Enum.Material.Glass or obj.Material == Enum.Material.Neon then
                obj.Material = Enum.Material.Plastic
            end
        end)
    end

    if obj:IsA("SurfaceAppearance") or obj:IsA("Texture") or obj:IsA("Decal") then
        obj:Destroy()
    end
end

-- ============================================================
-- FPS BOOST / OPTIMIZACION
-- ============================================================
local Lighting = game:GetService("Lighting")

-- DAYLOCK (EXECUTOR - CLIENT SIDE)
getgenv().DayLock = getgenv().DayLock or {
    Enabled = false,
    Hour = 7,
    Refresh = 0.1
}

if getgenv().DayLock.Enabled == nil then
    getgenv().DayLock.Enabled = false
end
if type(getgenv().DayLock.Hour) ~= "number" then
    getgenv().DayLock.Hour = 7
end
if type(getgenv().DayLock.Refresh) ~= "number" then
    getgenv().DayLock.Refresh = 0.1
end

task.spawn(function()
    while true do
        local dl = getgenv().DayLock
        if dl and dl.Enabled then
            Lighting.ClockTime = dl.Hour
            Lighting.TimeOfDay = string.format("%02d:00:00", dl.Hour)
        end
        task.wait((dl and dl.Refresh) or 0.1)
    end
end)

local function setFPSBoost(enabled)
    Config.FPSBoost = enabled
    SaveConfig()

    if FPSBOOST_DESC_ADDED_CONN then
        FPSBOOST_DESC_ADDED_CONN:Disconnect()
        FPSBOOST_DESC_ADDED_CONN = nil
    end

    getgenv().DayLock = getgenv().DayLock or {}
    getgenv().DayLock.Hour = 7
    getgenv().DayLock.Refresh = 0.1
    getgenv().DayLock.Enabled = enabled and true or false

    if enabled then
        Lighting.ClockTime = getgenv().DayLock.Hour
        Lighting.TimeOfDay = string.format("%02d:00:00", getgenv().DayLock.Hour)
        task.spawn(function()
            local objs = Workspace:GetDescendants()
            local batchSize = 30 -- cantidad por frame

            for i = 1, #objs do
                stripVisuals(objs[i])

                if i % batchSize == 0 then
                    task.wait() -- deja respirar al frame
                end
            end
        end)

        FPSBOOST_DESC_ADDED_CONN = Workspace.DescendantAdded:Connect(function(obj)
            if not Config.FPSBoost then return end

            task.defer(function()
                stripVisuals(obj)
            end)
        end)

        -- FPS BOOST + BAJAR ILUMINACION
        local Terrain = Workspace:FindFirstChildOfClass("Terrain")

        pcall(function()
            Lighting.Brightness = 2
            Lighting.GlobalShadows = false
            Lighting.OutdoorAmbient = Color3.fromRGB(165,165,165)
            Lighting.Ambient = Color3.fromRGB(20,20,20)

            Lighting.FogEnd = 9e9
            Lighting.FogStart = 0
            Lighting.EnvironmentDiffuseScale = 0
            Lighting.EnvironmentSpecularScale = 0

            for _,v in pairs(Lighting:GetChildren()) do
                if v:IsA("BlurEffect")
                or v:IsA("SunRaysEffect")
                or v:IsA("BloomEffect")
                or v:IsA("ColorCorrectionEffect")
                or v:IsA("DepthOfFieldEffect") then
                    v:Destroy()
                end
            end

            if Terrain then
                Terrain.WaterWaveSize = 0
                Terrain.WaterWaveSpeed = 0
                Terrain.WaterReflectance = 0
                Terrain.WaterTransparency = 1
            end
        end)
    end
end
if Config.FPSBoost then setFPSBoost(true) end

local FPSBOOST_V2_DESC_ADDED_CONN = nil

local function stripVisualsV2(obj, removeLights)
    local model = obj:FindFirstAncestorOfClass("Model")
    local isPlayer = model and isPlayerCharacter(model)

    if obj:IsA("Animator") then handleAnimator(obj) end

    if obj:IsA("Accessory") or obj:IsA("Clothing") then
        if obj:FindFirstAncestorOfClass("Model") then
            obj:Destroy()
        end
    end

    if not isPlayer then
        if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or
           obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") or
           obj:IsA("Highlight") then
            obj.Enabled = false
        end
        if obj:IsA("Explosion") then
            obj:Destroy()
        end
        if obj:IsA("MeshPart") then
            obj.TextureID = ""
        end
        if removeLights and (obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight")) then
            pcall(function()
                if obj.Parent ~= Lighting then
                    obj.Enabled = false
                    obj.Brightness = 0
                    obj.Range = 0
                    obj.Shadows = false
                    obj:Destroy()
                end
            end)
        end
    end

    if obj:IsA("BasePart") then
        obj.Material = Enum.Material.Plastic
        obj.Reflectance = 0
        obj.CastShadow = false
    end

    if obj:IsA("SurfaceAppearance") or obj:IsA("Texture") or obj:IsA("Decal") then
        obj:Destroy()
    end
end

local function setFPSBoostV2(enabled)
    Config.FPSBoostV2 = enabled
    SaveConfig()

    if FPSBOOST_V2_DESC_ADDED_CONN then
        FPSBOOST_V2_DESC_ADDED_CONN:Disconnect()
        FPSBOOST_V2_DESC_ADDED_CONN = nil
    end

    if enabled then
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 0
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0.1

        for _, v in pairs(Lighting:GetChildren()) do
            if v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("ColorCorrectionEffect") or
               v:IsA("SunRaysEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("Atmosphere") then
                v:Destroy()
            end
        end

        task.spawn(function()
            local objs = Workspace:GetDescendants()
            local batchSize = 30

            for i = 1, #objs do
                stripVisualsV2(objs[i], true)

                if i % batchSize == 0 then
                    task.wait()
                end
            end
        end)

        FPSBOOST_V2_DESC_ADDED_CONN = Workspace.DescendantAdded:Connect(function(obj)
            if not Config.FPSBoostV2 then return end

            task.defer(function()
                stripVisualsV2(obj, false)
            end)
        end)
    end
end
if Config.FPSBoostV2 then task.spawn(function() task.wait(0.1); setFPSBoostV2(true) end) end

local State = {
    ProximityAPActive = false,
    carpetSpeedEnabled = false,
    infiniteJumpEnabled = Config.TpSettings.InfiniteJump,
    xrayEnabled = false,
    antiRagdollMode = Config.AntiRagdoll or 0,
    floatActive = Config.Float == true,
    isTpMoving = false,
}
local Connections = {
    carpetSpeedConnection = nil,
    infiniteJumpConnection = nil,
    xrayDescConn = nil,
    antiRagdollConn = nil,
    antiRagdollV2Task = nil,
}
local UI = {
    carpetStatusLabel = nil,
    settingsGui = nil,
}
local carpetSpeedEnabled = State.carpetSpeedEnabled
local carpetSpeedConnection = Connections.carpetSpeedConnection
local _carpetStatusLabel = UI.carpetStatusLabel

-- ============================================================
-- FLOAT
-- ============================================================
local FLOAT_PLATFORM_NAME = "HAZE_FLOAT_PLATFORM"
local FLOAT_PLATFORM_SIZE = Vector3.new(7, 1, 7)
local FLOAT_OFFSET_BELOW = 3.35
local FLOAT_MOVE_EPSILON = 0.05

local FloatData = {
    platform = nil,
    followConnection = nil,
    sawStealingDuringThisFloat = false,
}

local floatToggleRef = {}

local function getFloatCharacterParts()
    local char = LocalPlayer.Character
    if not char then return nil, nil, nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, hrp, hum
end

local function removeFloatPlatform()
    if FloatData.followConnection then
        FloatData.followConnection:Disconnect()
        FloatData.followConnection = nil
    end

    if FloatData.platform then
        FloatData.platform:Destroy()
        FloatData.platform = nil
    end
end

local function updateFloatPlatformPosition()
    local _, hrp, hum = getFloatCharacterParts()
    if not hrp or not hum or not FloatData.platform then return end
    if hum.Health <= 0 then return end

    local targetPos = hrp.Position - Vector3.new(0, FLOAT_OFFSET_BELOW, 0)
    if (FloatData.platform.Position - targetPos).Magnitude > FLOAT_MOVE_EPSILON then
        FloatData.platform.CFrame = CFrame.new(targetPos)
    end
end

local function createFloatPlatform()
    removeFloatPlatform()

    local _, hrp, hum = getFloatCharacterParts()
    if not hrp or not hum then return end

    local part = Instance.new("Part")
    part.Name = FLOAT_PLATFORM_NAME
    part.Size = FLOAT_PLATFORM_SIZE
    part.Anchored = true
    part.CanCollide = true
    part.CanTouch = false
    part.CanQuery = false
    part.Transparency = 1
    part.CastShadow = false
    part.Material = Enum.Material.SmoothPlastic
    part.Color = Color3.new(1, 1, 1)
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Locked = true
    part.Massless = true
    part.CFrame = CFrame.new(hrp.Position - Vector3.new(0, FLOAT_OFFSET_BELOW, 0))
    part.Parent = Workspace

    FloatData.platform = part
    FloatData.followConnection = RunService.Heartbeat:Connect(function()
        if not State.floatActive then
            return
        end

        local charNow, hrpNow, humNow = getFloatCharacterParts()
        if not charNow or not hrpNow or not humNow or humNow.Health <= 0 then
            return
        end

        updateFloatPlatformPosition()
    end)

    updateFloatPlatformPosition()
end

local function refreshFloatStealStateFromCurrentAttribute()
    if not State.floatActive then
        FloatData.sawStealingDuringThisFloat = false
        return
    end

    FloatData.sawStealingDuringThisFloat = (LocalPlayer:GetAttribute("Stealing") == true)
end

local function setFloatEnabled(on, silent)
    on = not not on
    State.floatActive = on
    Config.Float = on

    if on then
        refreshFloatStealStateFromCurrentAttribute()
        createFloatPlatform()
    else
        removeFloatPlatform()
        FloatData.sawStealingDuringThisFloat = false
    end

    SaveConfig()

    if floatToggleRef and floatToggleRef.setFn then
        pcall(floatToggleRef.setFn, on)
    end

    if not silent and type(ShowNotification) == "function" then
        ShowNotification("FLOAT", on and "ENABLED" or "DISABLED")
    end
end

local function toggleFloat(silent)
    setFloatEnabled(not State.floatActive, silent)
end

_G.setFloatEnabled = setFloatEnabled
_G.toggleFloat = toggleFloat

LocalPlayer:GetAttributeChangedSignal("Stealing"):Connect(function()
    local isStealing = (LocalPlayer:GetAttribute("Stealing") == true)

    if not State.floatActive then
        return
    end

    if isStealing then
        FloatData.sawStealingDuringThisFloat = true
        return
    end

    if FloatData.sawStealingDuringThisFloat then
        setFloatEnabled(false, false)
        if type(ShowNotification) == "function" then
            ShowNotification("FLOAT", "Disabled")
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.1)
    removeFloatPlatform()
    if State.floatActive then
        refreshFloatStealStateFromCurrentAttribute()
        createFloatPlatform()
    end
end)

task.spawn(function()
    task.wait(0.1)
    if State.floatActive then
        refreshFloatStealStateFromCurrentAttribute()
        createFloatPlatform()
    end
end)

-- ============================================================
-- TP / CARPET SPEED
-- ============================================================
local function isHoldingBrainrot()
    local char = LocalPlayer.Character
    if not char then return false end
    for _, part in ipairs(workspace:GetChildren()) do
        if part:IsA("BasePart") then
            for _, weld in ipairs(part:GetChildren()) do
                if weld:IsA("WeldConstraint") or weld:IsA("Weld") then
                    local p0 = weld:IsA("WeldConstraint") and weld.Part0 or weld.Part0
                    local p1 = weld:IsA("WeldConstraint") and weld.Part1 or weld.Part1
                    if (p0 and p0:IsDescendantOf(char)) or (p1 and p1:IsDescendantOf(char)) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function setCarpetSpeed(enabled)
    if enabled and isHoldingBrainrot() then
        if ShowNotification then ShowNotification("CARPET SPEED", "Unequip pet first!") end
        return
    end
    State.carpetSpeedEnabled = enabled
    carpetSpeedEnabled = State.carpetSpeedEnabled
    if Connections.carpetSpeedConnection then Connections.carpetSpeedConnection:Disconnect(); Connections.carpetSpeedConnection = nil end
    carpetSpeedConnection = Connections.carpetSpeedConnection
    if not enabled then return end

    if SharedState.DisableStealSpeed then SharedState.DisableStealSpeed() end

    Connections.carpetSpeedConnection = RunService.Heartbeat:Connect(function()
    carpetSpeedConnection = Connections.carpetSpeedConnection
        local c = LocalPlayer.Character
        if not c then return end
        local hum = c:FindFirstChild("Humanoid")
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end

        local toolName = Config.TpSettings.Tool
        local hasTool = c:FindFirstChild(toolName)
        
        if not hasTool then
            local tb = LocalPlayer.Backpack:FindFirstChild(toolName)
            if tb then hum:EquipTool(tb) end
        end

        if hasTool then
            local md = hum.MoveDirection
            if md.Magnitude > 0 then
                hrp.AssemblyLinearVelocity = Vector3.new(
                    md.X * 140, 
                    hrp.AssemblyLinearVelocity.Y, 
                    md.Z * 140
                )
            else
                hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
            end
        end
    end)
end

local JumpData = {lastJumpTime = 0}
local infiniteJumpEnabled = State.infiniteJumpEnabled
local infiniteJumpConnection = Connections.infiniteJumpConnection

-- ============================================================
-- INFINITE JUMP
-- ============================================================
local function setInfiniteJump(enabled)
    State.infiniteJumpEnabled = enabled
    infiniteJumpEnabled = State.infiniteJumpEnabled
    Config.TpSettings.InfiniteJump = enabled
    SaveConfig()
    if Connections.infiniteJumpConnection then Connections.infiniteJumpConnection:Disconnect(); Connections.infiniteJumpConnection = nil end
    infiniteJumpConnection = Connections.infiniteJumpConnection
    if not enabled then return end

    Connections.infiniteJumpConnection = RunService.Heartbeat:Connect(function()
    infiniteJumpConnection = Connections.infiniteJumpConnection
        if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end
        local now = tick()
        if now - JumpData.lastJumpTime < 0.1 then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end
        JumpData.lastJumpTime = now
        hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 55, hrp.AssemblyLinearVelocity.Z)
    end)
end
if infiniteJumpEnabled then setInfiniteJump(true) end

local XrayState = {
    originalTransparency = {},
    xrayEnabled = false,
}
local originalTransparency = XrayState.originalTransparency
local xrayEnabled = XrayState.xrayEnabled
local xrayDescConn = Connections.xrayDescConn

local function isBaseWall(obj)
    if not (obj:IsA("BasePart") or obj:IsA("MeshPart") or obj:IsA("UnionOperation")) then
        return false
    end

    local name = obj.Name:lower()
    local parentName = (obj.Parent and obj.Parent.Name:lower()) or ""

    return name:find("base") or name:find("claim") or parentName:find("base") or parentName:find("claim")
end

local function applyBaseWallhack(obj)
    if not XrayState.xrayEnabled then return end
    if isBaseWall(obj) then
        if XrayState.originalTransparency[obj] == nil then
            XrayState.originalTransparency[obj] = obj.LocalTransparencyModifier
            originalTransparency[obj] = XrayState.originalTransparency[obj]
        end
        obj.LocalTransparencyModifier = 0.7
    end
end

-- ============================================================
-- XRAY SYSTEM (replaced with wallhack bases + invisicam fix)
-- ============================================================
local function enableXray()
    XrayState.xrayEnabled = true
    xrayEnabled = XrayState.xrayEnabled

    if Connections.xrayDescConn then
        Connections.xrayDescConn:Disconnect()
        Connections.xrayDescConn = nil
    end

    local descendants = Workspace:GetDescendants()
    for i = 1, #descendants do
        applyBaseWallhack(descendants[i])
    end

    Connections.xrayDescConn = Workspace.DescendantAdded:Connect(function(obj)
        applyBaseWallhack(obj)
    end)
    xrayDescConn = Connections.xrayDescConn

    LocalPlayer.DevEnableMouseLock = true
    LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
end

local function disableXray()
    XrayState.xrayEnabled = false
    xrayEnabled = XrayState.xrayEnabled

    if Connections.xrayDescConn then
        Connections.xrayDescConn:Disconnect()
        Connections.xrayDescConn = nil
    end
    xrayDescConn = Connections.xrayDescConn

    for part, val in pairs(XrayState.originalTransparency) do
        if part and part.Parent then
            part.LocalTransparencyModifier = val
        end
    end
    XrayState.originalTransparency = {}
    originalTransparency = XrayState.originalTransparency
end

-- XRay disabled

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.1)
    if XrayState.xrayEnabled then
        local descendants = Workspace:GetDescendants()
        for i = 1, #descendants do
            applyBaseWallhack(descendants[i])
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if not XrayState.xrayEnabled then return end
    local cam = Workspace.CurrentCamera
    if cam and cam.CameraSubject and cam.CameraType == Enum.CameraType.Custom then
        cam.CFrame = cam.CFrame
    end
end)

local antiRagdollMode = State.antiRagdollMode
local antiRagdollConn = Connections.antiRagdollConn

local function isRagdolled()
    local char = LocalPlayer.Character; if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return false end
    local state = hum:GetState()
    local ragStates = {
        [Enum.HumanoidStateType.Physics]     = true,
        [Enum.HumanoidStateType.Ragdoll]     = true,
        [Enum.HumanoidStateType.FallingDown] = true,
    }
    if ragStates[state] then return true end
    local endTime = LocalPlayer:GetAttribute("RagdollEndTime")
    if endTime and (endTime - Workspace:GetServerTimeNow()) > 0 then return true end
    return false
end

local function stopAntiRagdoll()
    if Connections.antiRagdollConn then Connections.antiRagdollConn:Disconnect(); Connections.antiRagdollConn = nil end
    antiRagdollConn = Connections.antiRagdollConn
end


-- ============================================================
-- ANTI RAGDOLL
-- ============================================================
local function startAntiRagdoll(mode)
    stopAntiRagdoll()
    if Config.AntiRagdollV2 then
        stopAntiRagdollV2()
    end
    if mode == 0 then return end

    Connections.antiRagdollConn = RunService.Heartbeat:Connect(function()
    antiRagdollConn = Connections.antiRagdollConn
        local char = LocalPlayer.Character; if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end

        if isRagdolled() then
            pcall(function() LocalPlayer:SetAttribute("RagdollEndTime", Workspace:GetServerTimeNow()) end)
            hum:ChangeState(Enum.HumanoidStateType.Running)
            hrp.AssemblyLinearVelocity = Vector3.zero
            if Workspace.CurrentCamera.CameraSubject ~= hum then
                Workspace.CurrentCamera.CameraSubject = hum
            end
            for _, obj in ipairs(char:GetDescendants()) do
                if obj:IsA("BallSocketConstraint") or obj.Name:find("RagdollAttachment") then
                    pcall(function() obj:Destroy() end)
                end
            end
        end
    end)
end

local AntiRagdollV2Data = {
    antiRagdollConns = {},
}
local antiRagdollConns = AntiRagdollV2Data.antiRagdollConns

local cleanRagdollV2Scheduled = false
local function cleanRagdollV2(char)
    if not char then return end
    local carpetEquipped = false
    pcall(function()
        local toolName = Config.TpSettings.Tool or "Flying Carpet"
        local tool = char:FindFirstChild(toolName)
        if tool then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then
                for _, obj in ipairs(hrp:GetChildren()) do
                    if obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                        carpetEquipped = true
                        break
                    end
                end
            end
            if not carpetEquipped then
                for _, obj in ipairs(tool:GetChildren()) do
                    if obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                        carpetEquipped = true
                        break
                    end
                end
            end
        end
    end)
    local descendants = char:GetDescendants()
    for _, d in ipairs(descendants) do
        if d:IsA("BallSocketConstraint") or d:IsA("NoCollisionConstraint")
            or d:IsA("HingeConstraint")
            or (d:IsA("Attachment") and (d.Name == "A" or d.Name == "B")) then
            d:Destroy()
        elseif (d:IsA("BodyVelocity") or d:IsA("BodyPosition") or d:IsA("BodyGyro")) and not carpetEquipped then
            d:Destroy()
        end
    end
    for _, d in ipairs(descendants) do
        if d:IsA("Motor6D") then d.Enabled = true end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        local animator = hum:FindFirstChild("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                local n = track.Animation and track.Animation.Name:lower() or ""
                if n:find("rag") or n:find("fall") or n:find("hurt") or n:find("down") then
                    track:Stop(0)
                end
            end
        end
    end
    task.defer(function()
        pcall(function()
            local pm = LocalPlayer:FindFirstChild("PlayerScripts")
            if pm then pm = pm:FindFirstChild("PlayerModule") end
            if pm then require(pm):GetControls():Enable() end
        end)
    end)
end
local function cleanRagdollV2Debounced(char)
    if cleanRagdollV2Scheduled then return end
    cleanRagdollV2Scheduled = true
    task.defer(function()
        cleanRagdollV2Scheduled = false
        if char and char.Parent then cleanRagdollV2(char) end
    end)
end
local function isRagdollRelatedDescendant(obj)
    if obj:IsA("BallSocketConstraint") or obj:IsA("NoCollisionConstraint") or obj:IsA("HingeConstraint") then return true end
    if obj:IsA("Attachment") and (obj.Name == "A" or obj.Name == "B") then return true end
    if obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then return true end
    return false
end

local function hookAntiRagV2(char)
    for _, c in ipairs(antiRagdollConns) do pcall(function() c:Disconnect() end) end
    AntiRagdollV2Data.antiRagdollConns = {}
    antiRagdollConns = AntiRagdollV2Data.antiRagdollConns

    local hum = char:WaitForChild("Humanoid", 10)
    local hrp = char:WaitForChild("HumanoidRootPart", 10)
    if not hum or not hrp then return end

    local lastVel = Vector3.new(0, 0, 0)

    local c1 = hum.StateChanged:Connect(function()
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll
            or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.GettingUp then
            local carpetActive = false
            pcall(function()
                local toolName = Config.TpSettings.Tool or "Flying Carpet"
                local tool = char:FindFirstChild(toolName)
                if tool and hrp then
                    for _, obj in ipairs(hrp:GetChildren()) do
                        if obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                            carpetActive = true
                        end
                    end
                end
            end)
            if not carpetActive then
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
            cleanRagdollV2(char)
            pcall(function() Workspace.CurrentCamera.CameraSubject = hum end)
            pcall(function()
                local pm = LocalPlayer:FindFirstChild("PlayerScripts")
                if pm then pm = pm:FindFirstChild("PlayerModule") end
                if pm then require(pm):GetControls():Enable() end
            end)
        end
    end)
    table.insert(antiRagdollConns, c1)

    local c2 = char.DescendantAdded:Connect(function(desc)
        if isRagdollRelatedDescendant(desc) then
            cleanRagdollV2Debounced(char)
        end
    end)
    table.insert(antiRagdollConns, c2)

    pcall(function()
        local pkg = ReplicatedStorage:FindFirstChild("Packages")
        if pkg then
            local net = pkg:FindFirstChild("Net")
            if net then
                local applyImp = net:FindFirstChild("RE/CombatService/ApplyImpulse")
                if applyImp and applyImp:IsA("RemoteEvent") then
                    local c3 = applyImp.OnClientEvent:Connect(function()
                        local st = hum:GetState()
                        if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll
                            or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.GettingUp then
                            pcall(function() hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
                        end
                    end)
                    table.insert(antiRagdollConns, c3)
                end
            end
        end
    end)

    local c4 = RunService.Heartbeat:Connect(function()
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll
            or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.GettingUp then
            cleanRagdollV2(char)
            local vel = hrp.AssemblyLinearVelocity
            if (vel - lastVel).Magnitude > 40 and vel.Magnitude > 25 then
                hrp.AssemblyLinearVelocity = vel.Unit * math.min(vel.Magnitude, 15)
            end
        end
        lastVel = hrp.AssemblyLinearVelocity
    end)
    table.insert(antiRagdollConns, c4)

    cleanRagdollV2(char)
end

local function stopAntiRagdollV2()
    cleanRagdollV2Scheduled = false
    for _, c in ipairs(antiRagdollConns) do pcall(function() c:Disconnect() end) end
    AntiRagdollV2Data.antiRagdollConns = {}
    antiRagdollConns = AntiRagdollV2Data.antiRagdollConns
end

local function startAntiRagdollV2(enabled)
    stopAntiRagdoll()
    stopAntiRagdollV2()
    if not enabled then
        return
    end

    local char = LocalPlayer.Character
    if char then task.spawn(function() hookAntiRagV2(char) end) end
    LocalPlayer.CharacterAdded:Connect(function(c)
        task.spawn(function() hookAntiRagV2(c) end)
    end)
end

if antiRagdollMode > 0 then startAntiRagdoll(antiRagdollMode) end
if Config.AntiRagdollV2 then startAntiRagdollV2(true) end

-- ============================================================
-- LINE TO BASE
-- ============================================================
do
    local plotBeam = nil
    local plotBeamAttachment0 = nil
    local plotBeamAttachment1 = nil

    local function findMyPlot()
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return nil end
        for _, plot in ipairs(plots:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign")
            if sign then
                local surfaceGui = sign:FindFirstChildWhichIsA("SurfaceGui", true)
                if surfaceGui then
                    local label = surfaceGui:FindFirstChildWhichIsA("TextLabel", true)
                    if label then
                        local text = label.Text:lower()
                        if text:find(LocalPlayer.DisplayName:lower(), 1, true) or text:find(LocalPlayer.Name:lower(), 1, true) then
                            return plot
                        end
                    end
                end
            end
        end
        return nil
    end

    local function createPlotBeam()
        if not Config.LineToBase then return end
        local myPlot = findMyPlot()
        if not myPlot or not myPlot.Parent then return end
        local character = LocalPlayer.Character
        if not character or not character.Parent then return end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        if plotBeam then pcall(function() plotBeam:Destroy() end) end
        if plotBeamAttachment0 then pcall(function() plotBeamAttachment0:Destroy() end) end
        plotBeamAttachment0 = hrp:FindFirstChild("PlotBeamAttach_Player") or Instance.new("Attachment")
        plotBeamAttachment0.Name = "PlotBeamAttach_Player"
        plotBeamAttachment0.Position = Vector3.new(0, 0, 0)
        plotBeamAttachment0.Parent = hrp
        local plotPart = myPlot:FindFirstChild("MainRootPart") or myPlot:FindFirstChildWhichIsA("BasePart")
        if not plotPart or not plotPart.Parent then return end
        plotBeamAttachment1 = plotPart:FindFirstChild("PlotBeamAttach_Plot") or Instance.new("Attachment")
        plotBeamAttachment1.Name = "PlotBeamAttach_Plot"
        plotBeamAttachment1.Position = Vector3.new(0, 5, 0)
        plotBeamAttachment1.Parent = plotPart
        plotBeam = hrp:FindFirstChild("PlotBeam") or Instance.new("Beam")
        plotBeam.Name = "PlotBeam"
        plotBeam.Attachment0 = plotBeamAttachment0
        plotBeam.Attachment1 = plotBeamAttachment1
        plotBeam.FaceCamera = true
        plotBeam.LightEmission = 0.5
        plotBeam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
        plotBeam.Transparency = NumberSequence.new(0)
        plotBeam.Width0 = 0.7
        plotBeam.Width1 = 0.7
        plotBeam.TextureMode = Enum.TextureMode.Wrap
        plotBeam.TextureSpeed = 0
        plotBeam.Parent = hrp
    end

    local function resetPlotBeam()
        if plotBeam then pcall(function() plotBeam:Destroy() end) end
        if plotBeamAttachment0 then pcall(function() plotBeamAttachment0:Destroy() end) end
        if plotBeamAttachment1 then pcall(function() plotBeamAttachment1:Destroy() end) end
        plotBeam = nil
        plotBeamAttachment0 = nil
        plotBeamAttachment1 = nil
    end

    task.spawn(function()
        local checkCounter = 0
        RunService.Heartbeat:Connect(function()
            if not Config.LineToBase then return end
            checkCounter = checkCounter + 1
            if checkCounter >= 30 then
                checkCounter = 0
                if not plotBeam or not plotBeam.Parent or not plotBeamAttachment0 or not plotBeamAttachment0.Parent then
                    pcall(createPlotBeam)
                end
            end
        end)
    end)

    LocalPlayer.CharacterAdded:Connect(function(character)
        task.wait(0.05)
        if Config.LineToBase and character then
            pcall(createPlotBeam)
        end
    end)

    if LocalPlayer.Character then
        task.spawn(function()
            task.wait(0.05)
            if Config.LineToBase then createPlotBeam() end
        end)
    end

    _G.createPlotBeam = createPlotBeam
    _G.resetPlotBeam = resetPlotBeam
end

local function getPriorityTargetFromCache()
    local cache = SharedState and SharedState.AllAnimalsCache
    if not cache or #cache == 0 then
        return nil
    end

    for i = 1, #PRIORITY_LIST do
        local wanted = PRIORITY_LIST[i]:lower()

        for _, pet in ipairs(cache) do
            if pet
                and pet.name
                and pet.uid
                and (Config.AutoGrabOwnBase or pet.owner ~= LocalPlayer.Name)
                and pet.name:lower() == wanted then
                return pet
            end
        end
    end

    return nil
end

local function getFallbackTargetFromCache()
    local cache = SharedState and SharedState.AllAnimalsCache
    if not cache or #cache == 0 then
        return nil
    end

    for _, pet in ipairs(cache) do
        if pet
            and pet.name
            and pet.uid
            and (Config.AutoGrabOwnBase or pet.owner ~= LocalPlayer.Name) then
            return pet
        end
    end

    return nil
end



-- ============================================================
-- AUTO STEAL / SCANNER / TARGET LIST
-- ============================================================
task.spawn(function()
    local Packages = ReplicatedStorage:WaitForChild("Packages")
    local Datas    = ReplicatedStorage:WaitForChild("Datas")
    local Shared   = ReplicatedStorage:WaitForChild("Shared")
    local Utils    = ReplicatedStorage:WaitForChild("Utils")

    local Synchronizer  = require(Packages:WaitForChild("Synchronizer"))
    local AnimalsData   = require(Datas:WaitForChild("Animals"))
    local AnimalsShared = require(Shared:WaitForChild("Animals"))
    local NumberUtils   = require(Utils:WaitForChild("NumberUtils"))

    local autoStealEnabled   = true
    
    
    if Config.DefaultToPriority and Config.DefaultToHighest then
        Config.DefaultToHighest = false
    end
    if Config.DefaultToPriority and Config.DefaultToNearest then
        Config.DefaultToNearest = false
    end
    if Config.DefaultToHighest and Config.DefaultToNearest then
        Config.DefaultToNearest = false
    end
    
    if not Config.DefaultToPriority and not Config.DefaultToHighest and not Config.DefaultToNearest then
        Config.DefaultToHighest = true
    end
    
    local stealNearestEnabled = false
    local stealHighestEnabled = false
    local stealPriorityEnabled = false
    
    if Config.DefaultToNearest then
        stealNearestEnabled = true
        Config.StealNearest = true
        Config.StealHighest = false
        Config.StealPriority = false
        
        Config.AutoTPPriority = true
    elseif Config.DefaultToHighest then
        stealHighestEnabled = true
        Config.StealHighest = true
        Config.StealNearest = false
        Config.StealPriority = false
        
        Config.AutoTPPriority = false
    elseif Config.DefaultToPriority then
        stealPriorityEnabled = true
        Config.StealPriority = true
        Config.StealNearest = false
        Config.StealHighest = false
        
        Config.AutoTPPriority = true
    else
        stealNearestEnabled = Config.StealNearest
        stealHighestEnabled = Config.StealHighest
        stealPriorityEnabled = Config.StealPriority
        
        if Config.InstantSteal == nil then Config.InstantSteal = false end
        if Config.StealPriority then
            Config.AutoTPPriority = true
        elseif Config.StealNearest then
            Config.AutoTPPriority = true
        elseif Config.StealHighest then
            Config.AutoTPPriority = false
        end
    end
    
local instantStealEnabled = false
Config.InstantSteal = false
_G.NEAREST_INSTANT_MODE = (Config.StealNearest == true and Config.InstantSteal == true)
    local instantStealReady = false
    local instantStealDidInit = false
    local selectedTargetIndex = 1
    local selectedTargetUID   = nil 
    local manualSelectedTargetUID = nil
    local allAnimalsCache    = {}

    local manualTargetMode = false
    local function syncAutoStealEnabledFromModes()
        autoStealEnabled = (stealNearestEnabled == true) or (stealHighestEnabled == true) or (stealPriorityEnabled == true) or (Config.AutoGrabOwnBase == true) or (manualTargetMode == true)
        SharedState.ManualTargetMode = manualTargetMode
    end

    syncAutoStealEnabledFromModes()
    local InternalStealCache = {}
    local PromptMemoryCache  = {}
    local activeProgressTween = nil
    local currentStealTargetUID = nil
    local petButtons         = {}
    
    local function isMyBaseAnimal(animalData)
        if not animalData or not animalData.plot then return false end
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then return false end
        local plot = plots:FindFirstChild(animalData.plot)
        if not plot then return false end
        local channel = Synchronizer:Get(plot.Name)
        if channel then
            local owner = channel:Get("Owner")
            if owner then
                if typeof(owner) == "Instance" and owner:IsA("Player") then return owner.UserId == LocalPlayer.UserId
                elseif typeof(owner) == "table" and owner.UserId then return owner.UserId == LocalPlayer.UserId
                elseif typeof(owner) == "Instance" then return owner == LocalPlayer end
            end
        end
        return false
    end
    
    local function formatMutationText(mutationName)
        if not mutationName or mutationName == "None" then return "" end
        local f = ""
        if mutationName == "Cursed" then f = "<font color='rgb(200,0,0)'>Cur</font><font color='rgb(0,0,0)'>sed</font>"
        elseif mutationName == "Gold" then f = "<font color='rgb(255,215,0)'>Gold</font>"
        elseif mutationName == "Diamond" then f = "<font color='rgb(0,255,255)'>Diamond</font>"
        elseif mutationName == "YinYang" then f = "<font color='rgb(255,255,255)'>Yin</font><font color='rgb(0,0,0)'>Yang</font>"
        elseif mutationName == "Candy" then f = "<font color='rgb(255,105,180)'>Candy</font>"
        elseif mutationName == "Divine" then f = "<font color='rgb(255,255,255)'>Divine</font>"
        elseif mutationName == "Rainbow" then
            local cols = {"rgb(255,0,0)","rgb(255,127,0)","rgb(255,255,0)","rgb(0,255,0)","rgb(0,0,255)","rgb(75,0,130)","rgb(148,0,211)"}
            for i = 1, #mutationName do f = f.."<font color='"..cols[(i-1)%#cols+1].."'>"..mutationName:sub(i,i).."</font>" end
        elseif mutationName == "Radioactive" then f = "<font color='rgb(132,255,0)'>Radioactive</font>"
        elseif mutationName == "Galaxy" then f = "<font color='rgb(170,85,255)'>Galaxy</font>"
        else f = mutationName end
        return "<font weight='800'>"..f.." </font>"
    end

    local function getMutationAccentColor(mutationName)
        if mutationName == "Gold" then
            return Color3.fromRGB(255, 215, 0)
        elseif mutationName == "Diamond" then
            return Color3.fromRGB(0, 255, 255)
        elseif mutationName == "Cursed" then
            return Color3.fromRGB(200, 0, 0)
        elseif mutationName == "YinYang" then
            return Color3.fromRGB(255, 255, 255)
        elseif mutationName == "Candy" then
            return Color3.fromRGB(255, 105, 180)
        elseif mutationName == "Divine" then
            return Color3.fromRGB(255, 255, 255)
        elseif mutationName == "Rainbow" then
            return Color3.fromRGB(148, 0, 211)
        elseif mutationName == "Radioactive" then
            return Color3.fromRGB(132, 255, 0)
        elseif mutationName == "Galaxy" then
            return Color3.fromRGB(170, 85, 255)
        end
        return Color3.fromRGB(255, 70, 120)
    end

    local function getPetPrimaryLineText(petData)
        local petName = (petData and petData.petName) or "Unknown"
        return petName
    end

    local function getPetMutationLineText(petData)
        local mutation = petData and petData.mutation
        if mutation and mutation ~= "None" and mutation ~= "" then
            return formatMutationText(mutation), true
        end
        return "", false
    end

    local function get_all_pets()
        local out = {}
        for _, a in ipairs(allAnimalsCache) do
            if a.genValue >= 1 and (Config.AutoGrabOwnBase == true or not isMyBaseAnimal(a)) then
                table.insert(out, {petName=a.name, mpsText=a.genText, mpsValue=a.genValue,
                    owner=a.owner, plot=a.plot, slot=a.slot, uid=a.uid, mutation=a.mutation, animalData=a})
            end
        end
        return out
    end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoStealUI"; screenGui.ResetOnSpawn = false; screenGui.Parent = PlayerGui

    local frame = Instance.new("Frame")
    local mobileScale = IS_MOBILE and 0.6 or 1
    local AutoStealColors = {
        BG = Color3.fromRGB(8, 15, 12),
        SURF = Color3.fromRGB(10, 25, 18),
        SURF2 = Color3.fromRGB(16, 42, 30),
        TEXT = Color3.fromRGB(225, 255, 235),
        DIM = Color3.fromRGB(140, 200, 165),
        AQUA = Color3.fromRGB(80, 210, 120),
        AQUA2 = Color3.fromRGB(55, 160, 90),
        AQUA_STROKE = Color3.fromRGB(65, 180, 105),
    }

    frame.Size = UDim2.new(0, 300 * mobileScale, 0, 335 * mobileScale)
    frame.Position = UDim2.new(
        Config.Positions.AutoSteal.X,
        Config.Positions.AutoSteal.OffsetX or 0,
        Config.Positions.AutoSteal.Y,
        Config.Positions.AutoSteal.OffsetY or 0
    )
    frame.BackgroundColor3 = AutoStealColors.BG
    frame.BackgroundTransparency = 0
    frame.BorderSizePixel = 0
    frame.ClipsDescendants = true
    frame.Parent = screenGui

    ApplyViewportUIScale(frame, 300, 335, 0.45, 0.8)
    AddMobileMinimize(frame, "AUTO STEAL")

    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
    local mainStroke = Instance.new("UIStroke", frame)
    mainStroke.Color = AutoStealColors.AQUA_STROKE
    mainStroke.Thickness = 1.3
    mainStroke.Transparency = 0.25

    local header = Instance.new("Frame", frame)
    header.Size = UDim2.new(1, 0, 0, 48)
    header.BackgroundTransparency = 1
    MakeDraggable(header, frame, "AutoSteal")

    local titleLabel = Instance.new("TextLabel", header)
    titleLabel.Size = UDim2.new(1, -32, 0, 24)
    titleLabel.Position = UDim2.new(0, 16, 0, 10)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = "STEAL TARGET"
    titleLabel.Font = Enum.Font.GothamBlack
    titleLabel.TextSize = 20
    titleLabel.TextColor3 = AutoStealColors.TEXT
    titleLabel.TextXAlignment = Enum.TextXAlignment.Center

    local titleLine = Instance.new("Frame", frame)
    titleLine.AnchorPoint = Vector2.new(0.5, 0)
    titleLine.Position = UDim2.new(0.5, 0, 0, 38)
    titleLine.Size = UDim2.new(0, 120, 0, 1)
    titleLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    titleLine.BackgroundTransparency = 0.15
    titleLine.BorderSizePixel = 0

    local ROW_HEIGHT = 38
    local ROW_PADDING = 5
    local MAX_VISIBLE_ROWS = 6
    local ROW_BORDER_PAD_X = 0
    local ROW_BORDER_PAD_Y = 0
    local ROW_INSET_X = 0
    local VISIBLE_ROWS_HEIGHT = (MAX_VISIBLE_ROWS * ROW_HEIGHT) + ((MAX_VISIBLE_ROWS - 1) * ROW_PADDING)

    local listFrame = Instance.new("ScrollingFrame", frame)
    listFrame.Size = UDim2.new(1, -24, 0, VISIBLE_ROWS_HEIGHT)
    listFrame.Position = UDim2.new(0, 12, 0, 56)
    listFrame.BackgroundTransparency = 1
    listFrame.BorderSizePixel = 0
    listFrame.ClipsDescendants = true
    listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
    listFrame.ScrollBarImageTransparency = 1
    listFrame.ScrollBarThickness = 0
    listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)

    local listHolder = Instance.new("Frame", listFrame)
    listHolder.Name = "Holder"
    listHolder.BackgroundTransparency = 1
    listHolder.BorderSizePixel = 0
    listHolder.Position = UDim2.new(0, 0, 0, 0)
    listHolder.Size = UDim2.new(1, 0, 0, 0)
    listHolder.ClipsDescendants = false

    local uiListLayout = Instance.new("UIListLayout", listHolder)
    uiListLayout.Padding = UDim.new(0, ROW_PADDING)
    uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local existingTargetHud = PlayerGui:FindFirstChild("AutoStealCurrentTargetHUD")
    if existingTargetHud then
        existingTargetHud:Destroy()
    end

    local targetHudGui = Instance.new("ScreenGui")
    targetHudGui.Name = "AutoStealCurrentTargetHUD"
    targetHudGui.ResetOnSpawn = false
    targetHudGui.IgnoreGuiInset = true
    targetHudGui.DisplayOrder = 998
    targetHudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    targetHudGui.Parent = PlayerGui

    local STEALBAR = {
        PANEL = Color3.fromRGB(10, 18, 15),
        PANEL2 = Color3.fromRGB(12, 30, 22),
        TEXT = Color3.fromRGB(225, 255, 235),
        STROKE = Color3.fromRGB(65, 180, 105),
        GLOW = Color3.fromRGB(140, 240, 175),
        TRACK = Color3.fromRGB(35, 14, 25),
        TRACK2 = Color3.fromRGB(45, 18, 32),
        FILL1 = Color3.fromRGB(65, 180, 105),
        FILL2 = Color3.fromRGB(220, 100, 150),
    }

    local targetHud = Instance.new("Frame", targetHudGui)
    targetHud.Name = "CurrentTargetHUD"
    targetHud.AnchorPoint = Vector2.new(0.5, 1)
    targetHud.Size = UDim2.new(0, 230 * mobileScale, 0, 46 * mobileScale)
    targetHud.Position = UDim2.new(0.5, 0, 1, -220)
    targetHud.BackgroundColor3 = STEALBAR.PANEL
    targetHud.BackgroundTransparency = 0.02
    targetHud.BorderSizePixel = 0
    targetHud.ZIndex = 70
    Instance.new("UICorner", targetHud).CornerRadius = UDim.new(0, math.floor(12 * mobileScale))

    local hudStroke = Instance.new("UIStroke", targetHud)
    hudStroke.Color = STEALBAR.STROKE
    hudStroke.Thickness = 1
    hudStroke.Transparency = 0.35

    local hudGlow = Instance.new("UIStroke", targetHud)
    hudGlow.Color = STEALBAR.GLOW
    hudGlow.Thickness = 3
    hudGlow.Transparency = 0.84
    hudGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local hudShadow = Instance.new("ImageLabel", targetHud)
    hudShadow.Name = "Shadow"
    hudShadow.AnchorPoint = Vector2.new(0.5, 0.5)
    hudShadow.Position = UDim2.new(0.5, 0, 0.5, 1)
    hudShadow.Size = UDim2.new(1, 20, 1, 20)
    hudShadow.BackgroundTransparency = 1
    hudShadow.Image = "rbxassetid://6014261993"
    hudShadow.ImageColor3 = Color3.new(0, 0, 0)
    hudShadow.ImageTransparency = 0.72
    hudShadow.ScaleType = Enum.ScaleType.Slice
    hudShadow.SliceCenter = Rect.new(49, 49, 450, 450)
    hudShadow.ZIndex = 69

    local hudName = Instance.new("TextLabel", targetHud)
    hudName.Name = "TargetName"
    hudName.Size = UDim2.new(1, -12, 0, 13 * mobileScale)
    hudName.Position = UDim2.fromOffset(6 * mobileScale, 3 * mobileScale)
    hudName.BackgroundTransparency = 1
    hudName.Font = Enum.Font.GothamBold
    hudName.TextSize = 11 * mobileScale
    hudName.TextColor3 = STEALBAR.TEXT
    hudName.TextXAlignment = Enum.TextXAlignment.Center
    hudName.TextTruncate = Enum.TextTruncate.AtEnd
    hudName.ZIndex = 72
    hudName.Text = "No target"

    local hudProgressBg = Instance.new("Frame", targetHud)
    hudProgressBg.Name = "ProgressBg"
    hudProgressBg.Size = UDim2.new(1, -10 * mobileScale, 0, 18 * mobileScale)
    hudProgressBg.Position = UDim2.fromOffset(5 * mobileScale, 18 * mobileScale)
    hudProgressBg.BackgroundColor3 = STEALBAR.TRACK
    hudProgressBg.BorderSizePixel = 0
    hudProgressBg.ZIndex = 72
    Instance.new("UICorner", hudProgressBg).CornerRadius = UDim.new(0, math.floor(8 * mobileScale))

    local hudProgressBgStroke = Instance.new("UIStroke", hudProgressBg)
    hudProgressBgStroke.Color = STEALBAR.STROKE
    hudProgressBgStroke.Thickness = 1
    hudProgressBgStroke.Transparency = 0.55

    local hudInnerTrack = Instance.new("Frame", hudProgressBg)
    hudInnerTrack.Name = "InnerTrack"
    hudInnerTrack.Size = UDim2.new(1, -2, 1, -2)
    hudInnerTrack.Position = UDim2.fromOffset(1, 1)
    hudInnerTrack.BackgroundColor3 = STEALBAR.TRACK2
    hudInnerTrack.BackgroundTransparency = 0.15
    hudInnerTrack.BorderSizePixel = 0
    hudInnerTrack.ZIndex = 72
    Instance.new("UICorner", hudInnerTrack).CornerRadius = UDim.new(0, math.floor(7 * mobileScale))

    local hudProgressFill = Instance.new("Frame", hudProgressBg)
    hudProgressFill.Name = "ProgressFill"
    hudProgressFill.Size = UDim2.new(0, 0, 1, 0)
    hudProgressFill.BackgroundColor3 = STEALBAR.FILL1
    hudProgressFill.BorderSizePixel = 0
    hudProgressFill.ZIndex = 73
    Instance.new("UICorner", hudProgressFill).CornerRadius = UDim.new(0, math.floor(8 * mobileScale))

    local hudProgressFillGradient = Instance.new("UIGradient", hudProgressFill)
    hudProgressFillGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, STEALBAR.FILL1),
        ColorSequenceKeypoint.new(1, STEALBAR.FILL2),
    })

    local hudProgressFillStroke = Instance.new("UIStroke", hudProgressFill)
    hudProgressFillStroke.Color = Color3.fromRGB(220, 228, 255)
    hudProgressFillStroke.Thickness = 1
    hudProgressFillStroke.Transparency = 0.45

    local hudPercent = Instance.new("TextLabel", hudProgressBg)
    hudPercent.Name = "Percent"
    hudPercent.Size = UDim2.new(1, 0, 1, 0)
    hudPercent.BackgroundTransparency = 1
    hudPercent.Font = Enum.Font.GothamBold
    hudPercent.TextSize = 12 * mobileScale
    hudPercent.TextColor3 = STEALBAR.TEXT
    hudPercent.TextStrokeTransparency = 0.7
    hudPercent.TextXAlignment = Enum.TextXAlignment.Center
    hudPercent.ZIndex = 74
    hudPercent.Text = "0%"

    local progressBarFill = hudProgressFill
    local targetLabel = hudName

    local existingTargetControls = PlayerGui:FindFirstChild("AutoStealTargetControls")
    if existingTargetControls then
        existingTargetControls:Destroy()
    end

    local targetControlsGui = Instance.new("ScreenGui")
    targetControlsGui.Name = "AutoStealTargetControls"
    targetControlsGui.ResetOnSpawn = false
    targetControlsGui.IgnoreGuiInset = true
    targetControlsGui.DisplayOrder = 999
    targetControlsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    targetControlsGui.Parent = PlayerGui

    local targetControlsFrame = Instance.new("Frame", targetControlsGui)
    targetControlsFrame.Name = "TargetControlsFrame"
    targetControlsFrame.AutomaticSize = Enum.AutomaticSize.Y
    targetControlsFrame.Size = UDim2.new(0, 240*mobileScale, 0, 0)

local targetX = Config.Positions.TargetControls and Config.Positions.TargetControls.X
local targetY = Config.Positions.TargetControls and Config.Positions.TargetControls.Y
local targetOffsetX = Config.Positions.TargetControls and Config.Positions.TargetControls.OffsetX
local targetOffsetY = Config.Positions.TargetControls and Config.Positions.TargetControls.OffsetY

    if targetX == nil or targetY == nil then
        targetX = Config.Positions.AutoSteal.X + 0.24
        targetY = Config.Positions.AutoSteal.Y
        if targetX > 0.76 then
            targetX = math.max(0.02, Config.Positions.AutoSteal.X - 0.24)
        end
        if targetY > 0.72 then
            targetY = 0.72
        end
        Config.Positions.TargetControls = {X = targetX, Y = targetY}
    end

    targetControlsFrame.Position = UDim2.new(
    targetX or 0.26,
    targetOffsetX or 15,
    targetY or 0.35,
    targetOffsetY or 0
)
    targetControlsFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
    targetControlsFrame.BackgroundTransparency = 0
    targetControlsFrame.BorderSizePixel = 0
    targetControlsFrame.ClipsDescendants = false
    targetControlsFrame.ZIndex = 100
    ApplyViewportUIScale(targetControlsFrame, 300, 250, 0.45, 0.8)
    AddMobileMinimize(targetControlsFrame, "TARGET CONTROLS")

    local MiniTargetColors = {
        BG = Color3.fromRGB(15, 15, 18),
        SURF = Color3.fromRGB(28, 28, 32),
        SURF2 = Color3.fromRGB(45, 45, 50),
        TEXT = Color3.fromRGB(245, 245, 250),
        DIM = Color3.fromRGB(180, 180, 190),
        AQUA = Color3.fromRGB(220, 220, 230),
        AQUA2 = Color3.fromRGB(160, 160, 170),
        AQUA_STROKE = Color3.fromRGB(190, 190, 200),
        GREEN1 = Color3.fromRGB(18, 88, 58),
        GREEN2 = Color3.fromRGB(21, 120, 76),
        GREEN_STROKE = Color3.fromRGB(60, 185, 120),
        OFF_BG = Color3.fromRGB(35, 35, 40),
        OFF_TEXT = Color3.fromRGB(140, 140, 150),
    }

    local function miniRound(obj, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius)
        c.Parent = obj
        return c
    end

    local function miniStroke(obj, color, thickness, transparency)
        local s = Instance.new("UIStroke")
        s.Color = color
        s.Thickness = thickness or 1
        s.Transparency = transparency or 0
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = obj
        return s
    end

    local function miniTween(obj, t, props, style, dir)
        TweenService:Create(
            obj,
            TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
            props
        ):Play()
    end

    local function miniGradient(parent, c1, c2, rot)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, c1),
            ColorSequenceKeypoint.new(1, c2),
        })
        g.Rotation = rot or 0
        g.Parent = parent
        return g
    end

    miniRound(targetControlsFrame, 18)
    miniStroke(targetControlsFrame, MiniTargetColors.AQUA_STROKE, 1.2, 0.40)

    local targetShadow = Instance.new("ImageLabel")
    targetShadow.Name = "Shadow"
    targetShadow.AnchorPoint = Vector2.new(0.5, 0.5)
    targetShadow.Position = UDim2.new(0.5, 0, 0.5, 2)
    targetShadow.Size = UDim2.new(1, 24, 1, 24)
    targetShadow.BackgroundTransparency = 1
    targetShadow.Image = "rbxassetid://6014261993"
    targetShadow.ImageColor3 = Color3.new(0, 0, 0)
    targetShadow.ImageTransparency = 0.72
    targetShadow.ScaleType = Enum.ScaleType.Slice
    targetShadow.SliceCenter = Rect.new(49, 49, 450, 450)
    targetShadow.ZIndex = 99
    targetShadow.Parent = targetControlsFrame

local targetControlsHeader = Instance.new("Frame", targetControlsFrame)
targetControlsHeader.Size = UDim2.new(1, 0, 0, 44)
targetControlsHeader.BackgroundTransparency = 1
targetControlsHeader.ZIndex = 101
MakeDraggable(targetControlsHeader, targetControlsFrame, "TargetControls")

local targetControlsTitle = Instance.new("TextLabel", targetControlsHeader)
targetControlsTitle.Size = UDim2.new(1, -28, 0, 24)
targetControlsTitle.Position = UDim2.new(0, 14, 0, 10)
targetControlsTitle.ZIndex = 102
targetControlsTitle.BackgroundTransparency = 1
targetControlsTitle.Text = "TARGET CONTROLS"
targetControlsTitle.Font = Enum.Font.GothamBlack
targetControlsTitle.TextSize = 18
targetControlsTitle.TextColor3 = MiniTargetColors.TEXT
targetControlsTitle.TextXAlignment = Enum.TextXAlignment.Center

local targetControlsTitleLine = Instance.new("Frame", targetControlsFrame)
targetControlsTitleLine.AnchorPoint = Vector2.new(0.5, 0)
targetControlsTitleLine.Position = UDim2.new(0.5, 0, 0, 38)
targetControlsTitleLine.Size = UDim2.new(0, 124, 0, 1)
targetControlsTitleLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
targetControlsTitleLine.BackgroundTransparency = 0.15
targetControlsTitleLine.BorderSizePixel = 0
targetControlsTitleLine.ZIndex = 101

local targetControlsContent = Instance.new("Frame", targetControlsFrame)
targetControlsContent.AutomaticSize = Enum.AutomaticSize.Y
targetControlsContent.Size = UDim2.new(1, -20, 0, 0)
targetControlsContent.Position = UDim2.fromOffset(10, 48)
targetControlsContent.BackgroundColor3 = MiniTargetColors.SURF
targetControlsContent.BorderSizePixel = 0
targetControlsContent.ZIndex = 101
miniRound(targetControlsContent, 16)
miniStroke(targetControlsContent, MiniTargetColors.AQUA_STROKE, 1, 0.48)

local toggleBtnContainer = Instance.new("Frame", targetControlsContent)
toggleBtnContainer.AutomaticSize = Enum.AutomaticSize.Y
toggleBtnContainer.Size = UDim2.new(1, -10, 0, 0)
toggleBtnContainer.Position = UDim2.fromOffset(5, 5)
toggleBtnContainer.BackgroundTransparency = 1
toggleBtnContainer.ZIndex = 102

    local toggleLayout = Instance.new("UIListLayout")
    toggleLayout.Padding = UDim.new(0, 8)
    toggleLayout.SortOrder = Enum.SortOrder.LayoutOrder
    toggleLayout.Parent = toggleBtnContainer

    local mobileButtonScale = IS_MOBILE and 1.3 or 1

    local function createToggleRow(parent, text, y)
        local row = Instance.new("Frame", parent)
        row.Name = text:gsub("%s+", "") .. "Row"
        row.Size = UDim2.new(1, 0, 0, math.floor(36 * mobileButtonScale))
        row.BackgroundColor3 = MiniTargetColors.SURF2
        row.BackgroundTransparency = 0.02
        row.BorderSizePixel = 0
        row.LayoutOrder = math.floor((y or 0) / math.max(1, (36 * mobileButtonScale))) + 1
        row.ZIndex = 103
        miniRound(row, 11)
        local rowStroke = miniStroke(row, MiniTargetColors.AQUA_STROKE, 1, 0.52)

        local label = Instance.new("TextLabel", row)
        label.BackgroundTransparency = 1
        label.Position = UDim2.fromOffset(12, 0)
        label.Size = UDim2.new(1, -100, 1, 0)
        label.Font = Enum.Font.GothamBold
        label.Text = text
        label.TextColor3 = MiniTargetColors.TEXT
        label.TextSize = 12 * mobileButtonScale
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 104

        local stateBox = Instance.new("TextButton", row)
        stateBox.Name = text:gsub("%s+", "") .. "Toggle"
        stateBox.AutoButtonColor = false
        stateBox.Size = UDim2.fromOffset(math.floor(72 * mobileButtonScale), math.floor(22 * mobileButtonScale))
        stateBox.Position = UDim2.new(1, -math.floor(82 * mobileButtonScale), 0.5, -math.floor(11 * mobileButtonScale))
        stateBox.BackgroundColor3 = MiniTargetColors.OFF_BG
        stateBox.BorderSizePixel = 0
        stateBox.Text = ""
        stateBox.ZIndex = 104
        miniRound(stateBox, 7)
        local stateStroke = miniStroke(stateBox, MiniTargetColors.AQUA_STROKE, 1, 0.55)

        local stateFill = Instance.new("Frame", stateBox)
        stateFill.Size = UDim2.new(1, 0, 1, 0)
        stateFill.BackgroundTransparency = 1
        stateFill.BorderSizePixel = 0
        stateFill.ZIndex = 104
        miniRound(stateFill, 7)
        miniGradient(stateFill, MiniTargetColors.GREEN1, MiniTargetColors.GREEN2, 0)

        local stateText = Instance.new("TextLabel", stateBox)
        stateText.BackgroundTransparency = 1
        stateText.Size = UDim2.fromScale(1, 1)
        stateText.Font = Enum.Font.GothamBold
        stateText.TextSize = 11 * mobileButtonScale
        stateText.Text = "OFF"
        stateText.TextColor3 = MiniTargetColors.OFF_TEXT
        stateText.ZIndex = 105

        row.MouseEnter:Connect(function()
            miniTween(row, 0.14, {BackgroundColor3 = Color3.fromRGB(34, 39, 58)})
            miniTween(rowStroke, 0.14, {Transparency = 0.38})
        end)

        row.MouseLeave:Connect(function()
            miniTween(row, 0.14, {BackgroundColor3 = MiniTargetColors.SURF2})
            miniTween(rowStroke, 0.14, {Transparency = 0.52})
        end)

        return {
            row = row,
            label = label,
            button = stateBox,
            knob = stateFill,
            stateLabel = stateText,
            stroke = stateStroke,
            rowStroke = rowStroke,
        }
    end

    local nearestBtn = createToggleRow(toggleBtnContainer, "Nearest", 0)
    local highestBtn = createToggleRow(toggleBtnContainer, "Highest", 36*mobileButtonScale)
    local priorityBtn = createToggleRow(toggleBtnContainer, "Priority", 72*mobileButtonScale)
    local autoTurretBtn = createToggleRow(toggleBtnContainer, "Auto Turret", 108*mobileButtonScale)
    local autoKickBtn = createToggleRow(toggleBtnContainer, "Auto Kick", 144*mobileButtonScale)
    local instantStealBtn
    local ownBaseBtn

    local function updateUI(enabled, allPets)
        syncAutoStealEnabledFromModes()
        local function paintToggle(ref, isOn, accentColor)
            local accent = accentColor or MiniTargetColors.AQUA
            if isOn then
                ref.button.BackgroundColor3 = MiniTargetColors.GREEN1
                ref.knob.BackgroundTransparency = 0
                ref.stateLabel.Text = "ON"
                ref.stateLabel.TextColor3 = Color3.fromRGB(232, 255, 240)
                ref.stroke.Color = MiniTargetColors.GREEN_STROKE
                ref.stroke.Transparency = 0.22
            else
                ref.button.BackgroundColor3 = MiniTargetColors.OFF_BG
                ref.knob.BackgroundTransparency = 1
                ref.stateLabel.Text = "OFF"
                ref.stateLabel.TextColor3 = MiniTargetColors.OFF_TEXT
                ref.stroke.Color = MiniTargetColors.AQUA_STROKE
                ref.stroke.Transparency = 0.55
            end
            if ref.rowStroke then
                ref.rowStroke.Transparency = isOn and 0.38 or 0.52
            end
            if ref.label then
                ref.label.TextColor3 = isOn and MiniTargetColors.TEXT or MiniTargetColors.TEXT
            end
        end

        paintToggle(nearestBtn, stealNearestEnabled, Theme.Accent1)
        paintToggle(highestBtn, stealHighestEnabled, Theme.Accent1)
        paintToggle(priorityBtn, stealPriorityEnabled, Theme.Accent2)
        paintToggle(autoTurretBtn, Config.AutoDestroyTurrets, Theme.Accent1)
        paintToggle(autoKickBtn, Config.AutoKickOnSteal, Theme.Accent1)
        paintToggle(ownBaseBtn, Config.AutoGrabOwnBase, Theme.Accent1)

        if instantStealBtn then
            if instantStealEnabled then
                instantStealBtn.stateLabel.Text = "ON"
                instantStealBtn.stateLabel.TextColor3 = Color3.fromRGB(232, 255, 240)
                instantStealBtn.button.BackgroundColor3 = MiniTargetColors.GREEN1
                instantStealBtn.knob.BackgroundTransparency = 0
                instantStealBtn.stroke.Color = MiniTargetColors.GREEN_STROKE
                instantStealBtn.stroke.Transparency = 0.22
            else
                instantStealBtn.stateLabel.Text = "OFF"
                instantStealBtn.stateLabel.TextColor3 = MiniTargetColors.OFF_TEXT
                instantStealBtn.button.BackgroundColor3 = MiniTargetColors.OFF_BG
                instantStealBtn.knob.BackgroundTransparency = 1
                instantStealBtn.stroke.Color = MiniTargetColors.AQUA_STROKE
                instantStealBtn.stroke.Transparency = 0.55
            end
            if instantStealBtn.rowStroke then
                instantStealBtn.rowStroke.Transparency = instantStealEnabled and 0.38 or 0.52
            end
        end

        if selectedTargetUID and allPets then
            local found = false
            for i, p in ipairs(allPets) do
                if p.uid == selectedTargetUID then
                    selectedTargetIndex = i
                    found = true
                    break
                end
            end
        end

        if SharedState.ListNeedsRedraw then
            for _, c in ipairs(listHolder:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
            petButtons = {}
            if allPets and #allPets > 0 then
                for i = 1, #allPets do
                    local petData = allPets[i]
                    local btn = Instance.new("TextButton")
                    btn.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
                    btn.BackgroundColor3 = AutoStealColors.SURF2
                    btn.BorderSizePixel = 0
                    btn.Text = ""
                    btn.AutoButtonColor = false
                    btn.Parent = listHolder
                    btn.Position = UDim2.new(0, 0, 0, 0)
                    btn.ClipsDescendants = true
                    btn.ZIndex = 1
                    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 9)

                    local selectedOverlay = Instance.new("Frame", btn)
                    selectedOverlay.Name = "SelectedOverlay"
                    selectedOverlay.Size = UDim2.new(1, 0, 1, 0)
                    selectedOverlay.Position = UDim2.new(0, 0, 0, 0)
                    selectedOverlay.BackgroundColor3 = Color3.fromRGB(8, 10, 12)
                    selectedOverlay.BackgroundTransparency = 0.82
                    selectedOverlay.BorderSizePixel = 0
                    selectedOverlay.Visible = false
                    selectedOverlay.ZIndex = 2
                    Instance.new("UICorner", selectedOverlay).CornerRadius = UDim.new(0, 9)

                    local selectedOverlayGradient = Instance.new("UIGradient", selectedOverlay)
                    selectedOverlayGradient.Rotation = 90
                    selectedOverlayGradient.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(0, 0, 0)),
                        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(18, 22, 18)),
                        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(0, 0, 0)),
                    })
                    selectedOverlayGradient.Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0.00, 0.12),
                        NumberSequenceKeypoint.new(0.18, 0.30),
                        NumberSequenceKeypoint.new(0.55, 0.52),
                        NumberSequenceKeypoint.new(1.00, 0.18),
                    })

                    local rankBox = Instance.new("Frame", btn)
                    rankBox.Size = UDim2.fromOffset(22, 22)
                    rankBox.Position = UDim2.fromOffset(8, 8)
                    rankBox.BackgroundColor3 = AutoStealColors.SURF
                    rankBox.ZIndex = 3
                    rankBox.BorderSizePixel = 0
                    Instance.new("UICorner", rankBox).CornerRadius = UDim.new(0, 5)

                    local rankBoxStroke = Instance.new("UIStroke", rankBox)
                    rankBoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                    rankBoxStroke.Color = AutoStealColors.AQUA_STROKE
                    rankBoxStroke.Thickness = 1
                    rankBoxStroke.Transparency = 0.45

                    local rankLabel = Instance.new("TextLabel", rankBox)
                    rankLabel.Size = UDim2.new(1, 0, 1, 0)
                    rankLabel.BackgroundTransparency = 1
                    rankLabel.Text = "#" .. i
                    rankLabel.Font = Enum.Font.GothamBold
                    rankLabel.TextSize = 11
                    rankLabel.TextColor3 = AutoStealColors.TEXT
                    rankLabel.TextXAlignment = Enum.TextXAlignment.Center
                    rankLabel.ZIndex = 4

                    local petName = (petData and petData.petName) or "Unknown"
                    local mpsText = (petData and petData.mpsText) or "$0/s"

                    local infoLabel = Instance.new("TextLabel", btn)
                    infoLabel.Size = UDim2.new(1, -108, 0, 16)
                    infoLabel.Position = UDim2.fromOffset(38, 4)
                    infoLabel.BackgroundTransparency = 1
                    infoLabel.RichText = false
                    infoLabel.Text = petName
                    infoLabel.Font = Enum.Font.GothamBold
                    infoLabel.TextSize = 12
                    infoLabel.TextColor3 = AutoStealColors.TEXT
                    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
                    infoLabel.TextTruncate = Enum.TextTruncate.None
                    infoLabel.ClipsDescendants = false
                    infoLabel.ZIndex = 4

                    local infoScale = Instance.new("UITextSizeConstraint", infoLabel)
                    infoScale.MinTextSize = 8
                    infoScale.MaxTextSize = 12

                    local rateLabel = Instance.new("TextLabel", btn)
                    rateLabel.Size = UDim2.new(0, 88, 0, 16)
                    rateLabel.Position = UDim2.new(1, -96, 0, 4)
                    rateLabel.BackgroundTransparency = 1
                    rateLabel.RichText = false
                    rateLabel.Text = mpsText
                    rateLabel.Font = Enum.Font.GothamBold
                    rateLabel.TextSize = 12
                    rateLabel.TextColor3 = Color3.fromRGB(56, 214, 110)
                    rateLabel.TextXAlignment = Enum.TextXAlignment.Right
                    rateLabel.TextTruncate = Enum.TextTruncate.AtEnd
                    rateLabel.ZIndex = 4

                    local mutationLabel = Instance.new("TextLabel", btn)
                    mutationLabel.Size = UDim2.new(1, -108, 0, 16)
                    mutationLabel.Position = UDim2.fromOffset(38, 18)
                    mutationLabel.BackgroundTransparency = 1
                    local mutationText, mutationRich = getPetMutationLineText(petData)
                    mutationLabel.RichText = mutationRich
                    mutationLabel.Text = mutationText
                    mutationLabel.Font = Enum.Font.GothamBold
                    mutationLabel.TextSize = 12
                    mutationLabel.TextColor3 = getMutationAccentColor(petData.mutation)
                    mutationLabel.TextXAlignment = Enum.TextXAlignment.Left
                    mutationLabel.TextTruncate = Enum.TextTruncate.None
                    mutationLabel.ClipsDescendants = false
                    mutationLabel.ZIndex = 4

                    local mutationScale = Instance.new("UITextSizeConstraint", mutationLabel)
                    mutationScale.MinTextSize = 8
                    mutationScale.MaxTextSize = 12
                    mutationLabel.Visible = mutationText ~= ""

                    petButtons[i] = {button=btn, selectedOverlay=selectedOverlay, rankBox=rankBox, rankBoxStroke=rankBoxStroke, rank=rankLabel, info=infoLabel, rate=rateLabel, mutation=mutationLabel, petData=petData}

btn.MouseButton1Click:Connect(function()
    selectedTargetIndex = i
    selectedTargetUID = petData.uid
    manualSelectedTargetUID = petData.uid
    manualTargetMode = true
    SharedState.ManualTargetMode = true
    SharedState.ManualTPTarget = petData.animalData
    stealNearestEnabled = false
    stealHighestEnabled = false
    stealPriorityEnabled = false
    Config.StealNearest = false
    Config.StealHighest = false
    Config.StealPriority = false
    syncAutoStealEnabledFromModes()
    _G.NEAREST_INSTANT_MODE = false
    SaveConfig()
    SharedState.ListNeedsRedraw = false
    updateUI(autoStealEnabled, get_all_pets())
end)
                end
            end
            SharedState.ListNeedsRedraw = false
            local visibleRows = #petButtons
            local contentHeight = 0
            if visibleRows > 0 then
                contentHeight = (visibleRows * ROW_HEIGHT) + ((visibleRows - 1) * ROW_PADDING)
            end
            listHolder.Size = UDim2.new(1, -(ROW_BORDER_PAD_X * 2), 0, contentHeight)
            listFrame.CanvasSize = UDim2.new(0, 0, 0, contentHeight + (ROW_BORDER_PAD_Y * 2))
        end
        
for i, pb in ipairs(petButtons) do

    local isSelected =
        pb.petData and manualSelectedTargetUID
        and pb.petData.uid == manualSelectedTargetUID

    pb.button.ZIndex = 1
    pb.button.BackgroundTransparency = 0
    pb.button.BackgroundColor3 = isSelected
        and Color3.fromRGB(44, 128, 79)
        or AutoStealColors.SURF2

    if pb.selectedOverlay then
        pb.selectedOverlay.Visible = isSelected
        pb.selectedOverlay.ZIndex = 2
        pb.selectedOverlay.BackgroundColor3 = Color3.fromRGB(8, 10, 12)
        pb.selectedOverlay.BackgroundTransparency = isSelected and 0.90 or 1
    end

    if pb.rankBox then
        pb.rankBox.BackgroundColor3 = isSelected
            and Color3.fromRGB(33, 97, 60)
            or AutoStealColors.SURF
        pb.rankBox.ZIndex = 3
    end

    if pb.rankBoxStroke then
        pb.rankBoxStroke.Color = isSelected and Color3.fromRGB(33, 97, 60) or AutoStealColors.AQUA_STROKE
        pb.rankBoxStroke.Thickness = 1
        pb.rankBoxStroke.Transparency = isSelected and 1 or 0.45
    end

    if pb.rank then
        pb.rank.ZIndex = 4
        pb.rank.TextColor3 = isSelected
            and Color3.fromRGB(240, 255, 240)
            or AutoStealColors.TEXT
    end

    if pb.info then
        pb.info.ZIndex = 4
        pb.info.RichText = false
        if pb.petData then
            pb.info.Text = getPetPrimaryLineText(pb.petData)
        end
        pb.info.TextColor3 = isSelected
            and Color3.fromRGB(0, 0, 0)
            or AutoStealColors.TEXT
    end

    if pb.mutation then
        pb.mutation.ZIndex = 4
        if pb.petData then
            local mutationText, mutationRich = getPetMutationLineText(pb.petData)
            pb.mutation.RichText = mutationRich
            pb.mutation.Text = mutationText
            pb.mutation.Visible = mutationText ~= ""
        end
        pb.mutation.TextColor3 = isSelected
            and Color3.fromRGB(0, 0, 0)
            or getMutationAccentColor(pb.petData and pb.petData.mutation)
    end

    if pb.rate then
        pb.rate.ZIndex = 4
        if pb.petData and pb.petData.mpsText then
            pb.rate.Text = pb.petData.mpsText
        end
        pb.rate.TextColor3 = isSelected
            and Color3.fromRGB(0, 0, 0)
            or Color3.fromRGB(56, 214, 110)
    end

end
        local ct = allPets and allPets[selectedTargetIndex]
        SharedState.SelectedPetData = ct

        if enabled then
            if ct then
                hudName.Text = string.format("%s - %s", ct.petName or "Unknown", ct.mpsText or "")
            else
                hudName.Text = "Searching..."
            end
        else
            hudName.Text = "Disabled"
            if activeProgressTween then
                activeProgressTween:Cancel()
                activeProgressTween = nil
            end
            hudProgressFill.Size = UDim2.new(0, 0, 1, 0)
        end

        hudPercent.Text = string.format("%d%%", math.clamp(math.floor((hudProgressFill.Size.X.Scale * 100) + 0.5), 0, 100))
        listHolder.Size = UDim2.new(1, -(ROW_BORDER_PAD_X * 2), 0, math.max(0, uiListLayout.AbsoluteContentSize.Y))
        listFrame.CanvasSize = UDim2.new(0,0,0, math.max(0, uiListLayout.AbsoluteContentSize.Y) + (ROW_BORDER_PAD_Y * 2))
    end
    
    uiListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        listHolder.Size = UDim2.new(1, -(ROW_BORDER_PAD_X * 2), 0, math.max(0, uiListLayout.AbsoluteContentSize.Y))
        listFrame.CanvasSize = UDim2.new(0,0,0, math.max(0, uiListLayout.AbsoluteContentSize.Y) + (ROW_BORDER_PAD_Y * 2))
    end)
    
    SharedState.UpdateAutoStealUI = function()
        updateUI(autoStealEnabled, get_all_pets())
    end

    task.spawn(function()
        local lastPct = -1
        while hudProgressFill and hudProgressFill.Parent do
            task.wait(0.05)
            local pct = math.clamp(math.floor((hudProgressFill.Size.X.Scale * 100) + 0.5), 0, 100)
            if pct ~= lastPct then
                hudPercent.Text = tostring(pct) .. "%"
                lastPct = pct
            end
        end
    end)
    
nearestBtn.button.MouseButton1Click:Connect(function()
    stealNearestEnabled = not stealNearestEnabled
    if stealNearestEnabled then
        stealHighestEnabled = false
        stealPriorityEnabled = false
        manualSelectedTargetUID = nil
    end
    Config.StealNearest = stealNearestEnabled; Config.StealHighest = stealHighestEnabled; Config.StealPriority = stealPriorityEnabled
    syncAutoStealEnabledFromModes()
    _G.NEAREST_INSTANT_MODE = (stealNearestEnabled and instantStealEnabled)
    SaveConfig()
    SharedState.ListNeedsRedraw = false; updateUI(autoStealEnabled, get_all_pets())
end)

highestBtn.button.MouseButton1Click:Connect(function()
    stealHighestEnabled = not stealHighestEnabled
    if stealHighestEnabled then
        stealNearestEnabled = false
        stealPriorityEnabled = false
        manualSelectedTargetUID = nil
    end
    Config.StealNearest = stealNearestEnabled; Config.StealHighest = stealHighestEnabled; Config.StealPriority = stealPriorityEnabled
    syncAutoStealEnabledFromModes()
    _G.NEAREST_INSTANT_MODE = (stealNearestEnabled and instantStealEnabled)
    SaveConfig()
    SharedState.ListNeedsRedraw = false; updateUI(autoStealEnabled, get_all_pets())
end)

priorityBtn.button.MouseButton1Click:Connect(function()
    stealPriorityEnabled = not stealPriorityEnabled
    if stealPriorityEnabled then
        stealNearestEnabled = false
        stealHighestEnabled = false
        manualSelectedTargetUID = nil
    end
    Config.StealNearest = stealNearestEnabled; Config.StealHighest = stealHighestEnabled; Config.StealPriority = stealPriorityEnabled
    syncAutoStealEnabledFromModes()
    _G.NEAREST_INSTANT_MODE = (stealNearestEnabled and instantStealEnabled)
    SaveConfig()
    SharedState.ListNeedsRedraw = false; updateUI(autoStealEnabled, get_all_pets())
end)


autoTurretBtn.button.MouseButton1Click:Connect(function()
    Config.AutoDestroyTurrets = not Config.AutoDestroyTurrets
    SaveConfig()
    SharedState.ListNeedsRedraw = false; updateUI(autoStealEnabled, get_all_pets())
end)

autoKickBtn.button.MouseButton1Click:Connect(function()
    Config.AutoKickOnSteal = not Config.AutoKickOnSteal
    SaveConfig()
    SharedState.ListNeedsRedraw = false; updateUI(autoStealEnabled, get_all_pets())
end)

    local customizePriorityBtn = Instance.new("TextButton", toggleBtnContainer)
    customizePriorityBtn.Name = "CustomizePriorityButton"
    customizePriorityBtn.Size = UDim2.new(1, 0, 0, math.floor(38 * mobileButtonScale))
    customizePriorityBtn.BackgroundColor3 = MiniTargetColors.AQUA2
    customizePriorityBtn.BackgroundTransparency = 0.02
    customizePriorityBtn.Text = "CUSTOMIZE PRIORITY"
    customizePriorityBtn.Font = Enum.Font.GothamBold
    customizePriorityBtn.TextSize = 12 * mobileButtonScale
    customizePriorityBtn.TextColor3 = MiniTargetColors.TEXT
    customizePriorityBtn.BorderSizePixel = 0
    customizePriorityBtn.AutoButtonColor = false
    customizePriorityBtn.LayoutOrder = 7
    customizePriorityBtn.ZIndex = 103
    miniRound(customizePriorityBtn, 11)
    miniStroke(customizePriorityBtn, MiniTargetColors.AQUA_STROKE, 1, 0.20)
    miniGradient(customizePriorityBtn, MiniTargetColors.AQUA, MiniTargetColors.AQUA2, 0)
    customizePriorityBtn.Visible = false

    customizePriorityBtn.MouseEnter:Connect(function()
        miniTween(customizePriorityBtn, 0.14, {BackgroundColor3 = Color3.fromRGB(126, 136, 188)})
    end)

    customizePriorityBtn.MouseLeave:Connect(function()
        miniTween(customizePriorityBtn, 0.14, {BackgroundColor3 = MiniTargetColors.AQUA2})
    end)
    
    customizePriorityBtn.MouseButton1Click:Connect(function()
        settingsGui.Enabled = true
        _G.SetHazeUIPage("Priority")
    end)

    instantStealBtn = createToggleRow(toggleBtnContainer, "Instant Steal", 180*mobileButtonScale)
    ownBaseBtn = createToggleRow(toggleBtnContainer, "Own Base", 216*mobileButtonScale)

instantStealBtn.button.MouseButton1Click:Connect(function()
    instantStealEnabled = not instantStealEnabled
    if not instantStealEnabled then
        instantStealReady = false
        instantStealDidInit = false
    end
    Config.InstantSteal = instantStealEnabled
    _G.NEAREST_INSTANT_MODE = (stealNearestEnabled and instantStealEnabled)
    SaveConfig()
    SharedState.ListNeedsRedraw = false; updateUI(autoStealEnabled, get_all_pets())
end)

ownBaseBtn.button.MouseButton1Click:Connect(function()
    Config.AutoGrabOwnBase = not Config.AutoGrabOwnBase
    syncAutoStealEnabledFromModes()
    SaveConfig()
    SharedState.ListNeedsRedraw = true
    updateUI(autoStealEnabled, get_all_pets())
end)

task.spawn(function()
    local autoInstantActive = false
    local ragdollCooldownUntil = 0

    local function setInstantSteal(state)
        instantStealEnabled = state
        if not state then
            instantStealReady = false
            instantStealDidInit = false
        end
        Config.InstantSteal = state
        _G.NEAREST_INSTANT_MODE = (stealNearestEnabled and state)
        SaveConfig()
        SharedState.ListNeedsRedraw = false
        updateUI(autoStealEnabled, get_all_pets())
    end
    _G._hazeSetInstantSteal = setInstantSteal

    -- Auto-activer Instant Steal quand le joueur rejoint la partie
    task.spawn(function()
        task.wait(2) -- attendre que l'UI et les configs soient prêtes
        if not instantStealEnabled then
            autoInstantActive = true
            setInstantSteal(true)
        end
    end)

    local function isNearStealPrompt()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return false end
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then return false end
        local p = hrp.Position

        -- Détermine l'étage du brainrot cible pour ajuster la zone Y
        local targetPart = nil
        do
            local td = SharedState.ManualTPTarget
                or (SharedState.SelectedPetData and SharedState.SelectedPetData.animalData)
            if td then pcall(function() targetPart = findAdorneeGlobal(td) end) end
        end
        local brainrotY = targetPart and targetPart.Position.Y or p.Y
        local floor = brainrotY <= 6.313 and 1 or (brainrotY < 30 and 2 or 3)

        -- Zone 1 : brainrot au 1er étage → joueur au sol
        -- Zone 2/3 : brainrot au 2ème ou 3ème → joueur en hauteur (zone unique)
        local yMin, yMax
        if floor == 1 then
            yMin = -8;  yMax = 12      -- rez-de-chaussée
        else
            yMin = 8;   yMax = 65      -- 2ème et 3ème étages combinés
        end

        if p.Y < yMin or p.Y > yMax then return false end

        for _, plot in ipairs(plots:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign")
            if sign then
                local gui = sign:FindFirstChildWhichIsA("SurfaceGui", true)
                local lbl = gui and gui:FindFirstChildWhichIsA("TextLabel", true)
                if lbl then
                    local txt = (lbl.Text or ""):lower()
                    if txt:find(LocalPlayer.Name:lower(), 1, true) or txt:find(LocalPlayer.DisplayName:lower(), 1, true) then
                        continue
                    end
                end
            end

            local podiums = plot:FindFirstChild("AnimalPodiums")
            if not podiums then continue end
            local hasPrompt = false
            for _, desc in ipairs(podiums:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and desc.Enabled then
                    hasPrompt = true; break
                end
            end
            if not hasPrompt then continue end

            local ok, cf, sz = pcall(function() return plot:GetBoundingBox() end)
            if ok and cf and sz then
                local center = cf.Position
                local margin = floor == 1 and 7 or 8
                local halfX = sz.X / 2 + margin
                local halfZ = sz.Z / 2 + margin
                if math.abs(p.X - center.X) <= halfX and math.abs(p.Z - center.Z) <= halfZ then
                    return true
                end
            end
        end
        return false
    end

    local wasStealingLast = false
    local ragdollingNow = false

    local function hookHitDetect(char)
        local hum = char:WaitForChild("Humanoid", 8)
        if not hum then return end

        local function onRagdoll()
            ragdollingNow = true
            task.delay(3.5, function() ragdollingNow = false end)
            wasStealingLast = false
            autoInstantActive = true
            setInstantSteal(true)
        end

        -- Bougie / body swap uniquement (pas ragdoll physique, géré par le loop)
        LocalPlayer:GetAttributeChangedSignal("RagdollEndTime"):Connect(function()
            local t = LocalPlayer:GetAttribute("RagdollEndTime")
            if t and (t - Workspace:GetServerTimeNow()) > 0 then
                onRagdoll()
            end
        end)
    end

    local char0 = LocalPlayer.Character
    if char0 then task.spawn(hookHitDetect, char0) end
    LocalPlayer.CharacterAdded:Connect(function(c) task.spawn(hookHitDetect, c) end)

    -- Quand un autre joueur perd le brainrot → fire les prompts immédiatement
    local function watchPlayerStealing(plr)
        if plr == LocalPlayer then return end
        local wasThiefStealing = false
        plr:GetAttributeChangedSignal("Stealing"):Connect(function()
            local nowStealing = plr:GetAttribute("Stealing") == true
            if wasThiefStealing and not nowStealing and autoStealEnabled then
                task.delay(0.08, function()
                    -- Fire tous les prompts du cache qui sont maintenant disponibles
                    for _, prompt in pairs(PromptMemoryCache) do
                        if prompt and prompt.Parent and prompt.Enabled then
                            pcall(function() fireproximityprompt(prompt, 0) end)
                        end
                    end
                    -- Toggle instant steal pour que le Heartbeat refasse feu
                    if instantStealEnabled then
                        setInstantSteal(false)
                        task.delay(0.03, function()
                            autoInstantActive = true
                            setInstantSteal(true)
                        end)
                    end
                end)
            end
            wasThiefStealing = nowStealing
        end)
    end
    for _, plr in ipairs(Players:GetPlayers()) do watchPlayerStealing(plr) end
    Players.PlayerAdded:Connect(watchPlayerStealing)

    local nearSince = 0
    local lastStuckToggle = 0
    local wasPhysicalRagdoll = false
    local ragdollStartTime = 0
    local lastPhysicalHitTime = 0

    local rdGui = Instance.new("ScreenGui")
    rdGui.Name = "RagdollCounterUI"
    rdGui.ResetOnSpawn = false
    rdGui.IgnoreGuiInset = true
    rdGui.Parent = PlayerGui
    local rdFrame = Instance.new("Frame", rdGui)
    rdFrame.Size = UDim2.new(0, 100, 0, 100)
    rdFrame.Position = UDim2.new(0.5, -50, 0.5, -50)
    rdFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    rdFrame.BackgroundTransparency = 0.2
    rdFrame.BorderSizePixel = 0
    rdFrame.Visible = false
    Instance.new("UICorner", rdFrame).CornerRadius = UDim.new(1, 0)
    local rdStroke = Instance.new("UIStroke", rdFrame)
    rdStroke.Color = Color3.fromRGB(0, 225, 255)
    rdStroke.Thickness = 2
    local rdLabel = Instance.new("TextLabel", rdFrame)
    rdLabel.Size = UDim2.new(1, 0, 0.6, 0)
    rdLabel.Position = UDim2.new(0, 0, 0.1, 0)
    rdLabel.BackgroundTransparency = 1
    rdLabel.Text = "3"
    rdLabel.TextColor3 = Color3.fromRGB(0, 225, 255)
    rdLabel.Font = Enum.Font.GothamBold
    rdLabel.TextSize = 42
    local rdSub = Instance.new("TextLabel", rdFrame)
    rdSub.Size = UDim2.new(1, 0, 0.3, 0)
    rdSub.Position = UDim2.new(0, 0, 0.68, 0)
    rdSub.BackgroundTransparency = 1
    rdSub.Text = "RAGDOLL"
    rdSub.TextColor3 = Color3.fromRGB(140, 140, 150)
    rdSub.Font = Enum.Font.GothamBold
    rdSub.TextSize = 10

    while true do
        task.wait(0.15)
        local isStealing = LocalPlayer:GetAttribute("Stealing") == true
        local near = isNearStealPrompt()

        -- Détection ragdoll via RagdollEndTime (couvre physique + tout)
        local rbEnd = LocalPlayer:GetAttribute("RagdollEndTime")
        local rbRemaining = rbEnd and (rbEnd - Workspace:GetServerTimeNow()) or 0
        local isAnyRagdoll = rbRemaining > 0

        -- Ragdoll long (>1.5s restant) = physique → compteur + désactive
        local isHeavyRagdoll = rbRemaining > 1.5

        local inRagdollWindow = ragdollStartTime > 0 and (os.clock() - ragdollStartTime) < 2.5

        -- Début ragdoll physique long → mémorise le moment du coup
        if isHeavyRagdoll and not wasPhysicalRagdoll then
            wasStealingLast = false
            lastPhysicalHitTime = os.clock()
            ragdollStartTime = os.clock()
            rdFrame.Visible = true
            if instantStealEnabled then
                autoInstantActive = false
                setInstantSteal(false)
            end
        -- Timer expiré → réactive + cache compteur
        elseif ragdollStartTime > 0 and not inRagdollWindow then
            ragdollStartTime = 0
            rdFrame.Visible = false
            if not instantStealEnabled then
                autoInstantActive = true
                setInstantSteal(true)
            end
        elseif wasStealingLast and not isStealing then
            local recentHit = (os.clock() - lastPhysicalHitTime) < 4.0
            local delay = recentHit and 5.0 or 2.5
            setInstantSteal(false)
            task.delay(delay, function()
                if not instantStealEnabled then
                    autoInstantActive = true
                    setInstantSteal(true)
                end
            end)
        end
        wasPhysicalRagdoll = isHeavyRagdoll
        wasStealingLast = isStealing

        if inRagdollWindow then
            local remaining = math.max(0, 2.5 - (os.clock() - ragdollStartTime))
            rdLabel.Text = tostring(math.ceil(remaining))
        end

        if not isAnyRagdoll then
            if autoInstantActive and isStealing then
                autoInstantActive = false
                setInstantSteal(false)
            elseif autoInstantActive and not near then
                autoInstantActive = false
                setInstantSteal(false)
            end
        end

        if not instantStealEnabled and near and os.clock() >= ragdollCooldownUntil then
            autoInstantActive = true
            -- OFF puis ON pour forcer une ré-initialisation propre
            setInstantSteal(false)
            task.defer(function()
                if near then setInstantSteal(true) end
            end)
        end

        -- Si près d'un brainrot avec instant ON mais pas en train de voler → toggle
        -- (désactivé pendant la TP)
        if instantStealEnabled and near and not isStealing and not State.isTpMoving then
            if nearSince == 0 then nearSince = os.clock() end
            local stuck = os.clock() - nearSince > 0.6
                and os.clock() - lastStuckToggle > 4.0
            if stuck then
                lastStuckToggle = os.clock()
                nearSince = 0
                instantStealEnabled = false
                Config.InstantSteal = false
                task.delay(0.5, function()
                    autoInstantActive = true
                    setInstantSteal(true)
                end)
            end
        else
            nearSince = 0
        end
    end
end)

-- ===== INSTANT STEAL TOGGLE PÉRIODIQUE (1.38s) =====
task.spawn(function()
    -- Activation initiale
    if _G._hazeSetInstantSteal then _G._hazeSetInstantSteal(true) end

    while true do
        task.wait(1.38)
        if _G._hazeSetInstantSteal then
            -- 1) DÉSACTIVER
            _G._hazeSetInstantSteal(false)
            -- 2) Laisser 50ms pour que le passage à OFF soit traité
            task.wait(0.05)
            -- 3) RÉACTIVER
            _G._hazeSetInstantSteal(true)
        end
    end
end)

    local function findProximityPromptForAnimal(animalData)
        if not animalData then return nil end
        local cp = PromptMemoryCache[animalData.uid]
        if cp and cp.Parent then return cp end
        local plot = Workspace.Plots:FindFirstChild(animalData.plot); if not plot then return nil end
        local podiums = plot:FindFirstChild("AnimalPodiums"); if not podiums then return nil end
        
        
        local ch = Synchronizer:Get(plot.Name)
        if not ch then
            
            local podium = podiums:FindFirstChild(animalData.slot)
            if podium then
                local base = podium:FindFirstChild("Base")
                local spawn = base and base:FindFirstChild("Spawn")
                if spawn then
                    local attach = spawn:FindFirstChild("PromptAttachment")
                    if attach then
                        for _, p in ipairs(attach:GetChildren()) do
                            if p:IsA("ProximityPrompt") then
                                PromptMemoryCache[animalData.uid] = p
                                return p
                            end
                        end
                    end
                end
            end
            return nil
        end
        
        local al = ch:Get("AnimalList")
        if not al then return nil end
        
        local brainrotName = animalData.name and animalData.name:lower() or ""
        local targetSlot = animalData.slot
        
        
        local foundPodium = nil
        for slot, ad in pairs(al) do
            if type(ad) == "table" and tostring(slot) == targetSlot then
                local aName, aInfo = ad.Index, AnimalsData[ad.Index]
                if aInfo and (aInfo.DisplayName or aName):lower() == brainrotName then
                    foundPodium = podiums:FindFirstChild(tostring(slot))
                    break
                end
            end
        end
        
        
        if not foundPodium then
            foundPodium = podiums:FindFirstChild(animalData.slot)
        end
        
        if foundPodium then
            local base = foundPodium:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn")
            if spawn then
                
                local attach = spawn:FindFirstChild("PromptAttachment")
                if attach then
                    for _, p in ipairs(attach:GetChildren()) do
                        if p:IsA("ProximityPrompt") and p.Enabled then
                            PromptMemoryCache[animalData.uid] = p
                            return p
                        end
                    end
                end

                local startPos = spawn.Position
                local slotX, slotZ = startPos.X, startPos.Z
                local nearestPrompt = nil
                local minDist = math.huge

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
                            local checkStartY = startPos.Y
                            if brainrotName:find("la secret combinasion") then
                                checkStartY = startPos.Y - 5
                            end
                            local horizontalDist = math.sqrt((promptPos.X - slotX)^2 + (promptPos.Z - slotZ)^2)
                            if horizontalDist < 5 and promptPos.Y > checkStartY then
                                local yDist = promptPos.Y - checkStartY
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
            end
        end
        
        return nil
    end

    local STEAL_DURATION = 0.4

    local function buildStealCallbacks(prompt)
        if InternalStealCache[prompt] then return end
        local data = {holdCallbacks = {}, triggerCallbacks = {}, holdEndCallbacks = {}, ready = true}
        local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
        if ok1 and type(conns1) == "table" then
            for _, conn in ipairs(conns1) do
                if type(conn.Function) == "function" then
                    table.insert(data.holdCallbacks, conn.Function)
                end
            end
        end
        local ok2, conns2 = pcall(getconnections, prompt.Triggered)
        if ok2 and type(conns2) == "table" then
            for _, conn in ipairs(conns2) do
                if type(conn.Function) == "function" then
                    table.insert(data.triggerCallbacks, conn.Function)
                end
            end
        end
        local ok3, conns3 = pcall(getconnections, prompt.PromptButtonHoldEnded)
        if ok3 and type(conns3) == "table" then
            for _, conn in ipairs(conns3) do
                if type(conn.Function) == "function" then
                    table.insert(data.holdEndCallbacks, conn.Function)
                end
            end
        end
        if (#data.holdCallbacks > 0) or (#data.triggerCallbacks > 0) or (#data.holdEndCallbacks > 0) then
            InternalStealCache[prompt] = data
        end
    end

    local function runCallbackList(list)
        for _, fn in ipairs(list) do
            task.spawn(fn)
        end
    end

    local INSTANT_STEAL_RADIUS = 60
    local INSTANT_STEAL_COOLDOWN = 0.04
    local lastInstantStealTime = 0
    local function isMyPlot_Instant(plotName)
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return false end
        local plot = plots:FindFirstChild(plotName)
        if not plot then return false end
        local sign = plot:FindFirstChild("PlotSign")
        if not sign then return false end
        local yb = sign:FindFirstChild("YourBase")
        return yb and yb:IsA("BillboardGui") and yb.Enabled
    end
    local function findNearestPrompt_Instant()
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return nil, math.huge, nil end
        local plots = workspace:FindFirstChild("Plots")
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
                local base = pod:FindFirstChild("Base")
                local spawn = base and base:FindFirstChild("Spawn")
                if not spawn then continue end
                local dist = (spawn.Position - hrp.Position).Magnitude
                if dist > INSTANT_STEAL_RADIUS or dist >= bestDist then continue end
                local att = spawn:FindFirstChild("PromptAttachment")
                if not att then continue end
                local prompt = att:FindFirstChildOfClass("ProximityPrompt")
                if prompt and prompt.Parent and prompt.Enabled then
                    bestPrompt = prompt
                    bestDist = dist
                    bestName = pod.Name
                end
            end
        end
        return bestPrompt, bestDist, bestName
    end

local function executeInstantSteal(prompt)
    if not prompt or not prompt.Parent then return end
    pcall(function() fireproximityprompt(prompt, 0) end)
end

    local function executeInternalStealAsync(prompt, animalUID)
        local data = InternalStealCache[prompt]
        if not data or not data.ready then return false end
        data.ready = false

        task.spawn(function()
            if currentStealTargetUID ~= animalUID then
                if activeProgressTween then activeProgressTween:Cancel() end
                progressBarFill.Size = UDim2.new(0, 0, 1, 0)
                currentStealTargetUID = animalUID
            end

            if #data.holdCallbacks > 0 then
                runCallbackList(data.holdCallbacks)
            end

            progressBarFill.Size = UDim2.new(0, 0, 1, 0)
            progressBarFill.BackgroundTransparency = 0
            activeProgressTween = TweenService:Create(progressBarFill, TweenInfo.new(STEAL_DURATION, Enum.EasingStyle.Linear), {Size = UDim2.new(1, 0, 1, 0)})
            activeProgressTween:Play()
            activeProgressTween.Completed:Wait()

            if currentStealTargetUID == animalUID and #data.triggerCallbacks > 0 then
                runCallbackList(data.triggerCallbacks)
            end

            data.ready = true
        end)

        return true
    end

    local function getNearestOwnBasePetIndex(pets)
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp or not pets then return nil end
        local bestIndex = nil
        local bestDist = math.huge
        for i, p in ipairs(pets) do
            if p and p.animalData and isMyBaseAnimal(p.animalData) then
                local targetPart = findAdorneeGlobal(p.animalData)
                if targetPart and targetPart:IsA("BasePart") then
                    local d = (hrp.Position - targetPart.Position).Magnitude
                    if d < bestDist then bestDist = d; bestIndex = i end
                end
            end
        end
        return bestIndex
    end

    local lastOwnBaseGrabTime = 0
    local function triggerOwnBaseGrab(prompt, animalUID)
        if not prompt or not prompt.Parent then return false end
        local now = os.clock()
        if now - lastOwnBaseGrabTime < 0.35 then return false end
        lastOwnBaseGrabTime = now
        if currentStealTargetUID ~= animalUID then
            if activeProgressTween then activeProgressTween:Cancel() end
            progressBarFill.Size = UDim2.new(0, 0, 1, 0)
            currentStealTargetUID = animalUID
        end
        progressBarFill.BackgroundTransparency = 0
        progressBarFill.Size = UDim2.new(1, 0, 1, 0)
        pcall(function()
            if fireproximityprompt then
                fireproximityprompt(prompt, math.max(0.1, tonumber(prompt.HoldDuration) or 0))
            elseif prompt.InputHoldBegin and prompt.InputHoldEnd then
                prompt:InputHoldBegin()
                task.wait(math.max(0.1, tonumber(prompt.HoldDuration) or 0.08))
                prompt:InputHoldEnd()
            end
        end)
        return true
    end

    local function attemptSteal(prompt, animalUID)
        if not prompt or not prompt.Parent then return false end
        buildStealCallbacks(prompt)
        if not InternalStealCache[prompt] then return false end

        if currentStealTargetUID ~= animalUID then
            if activeProgressTween then
                activeProgressTween:Cancel()
                activeProgressTween = nil
            end
            progressBarFill.Size = UDim2.new(0, 0, 1, 0)
        end

        return executeInternalStealAsync(prompt, animalUID)
    end

    local function prebuildStealCallbacks()
        for _, prompt in pairs(PromptMemoryCache) do
            if prompt and prompt.Parent then
                buildStealCallbacks(prompt)
            end
        end
    end

    task.spawn(function()
        while task.wait(2) do
            if autoStealEnabled then
                prebuildStealCallbacks()
            end
        end
    end)

    local lastAnimalData = {}
    local function getAnimalHash(al)
        if not al then return "" end; local h=""
        for slot, d in pairs(al) do if type(d)=="table" then h=h..tostring(slot)..tostring(d.Index)..tostring(d.Mutation) end end
        return h
    end

local function scanSinglePlot(plot)
    local changed = false

    pcall(function()
        local ch = Synchronizer:Get(plot.Name)
        if not ch then return end

        local al = ch:Get("AnimalList")
        local owner = ch:Get("Owner")

        if not owner or not owner.Name or not Players:FindFirstChild(owner.Name) then
            lastAnimalData[plot.Name] = nil

            for i = #allAnimalsCache, 1, -1 do
                if allAnimalsCache[i].plot == plot.Name then
                    table.remove(allAnimalsCache, i)
                    changed = true
                end
            end

            return
        end

        if not al then
            lastAnimalData[plot.Name] = nil

            for i = #allAnimalsCache, 1, -1 do
                if allAnimalsCache[i].plot == plot.Name then
                    table.remove(allAnimalsCache, i)
                    changed = true
                end
            end

            return
        end

        local ownerName = owner.Name
        local hash = getAnimalHash(al, ownerName)

        if lastAnimalData[plot.Name] == hash then
            return
        end

        for i = #allAnimalsCache, 1, -1 do
            if allAnimalsCache[i].plot == plot.Name then
                table.remove(allAnimalsCache, i)
            end
        end

        for slot, ad in pairs(al) do
            if type(ad) == "table" then
                local aName, aInfo = ad.Index, AnimalsData[ad.Index]
                if aInfo then
                    local mut = ad.Mutation or "None"
                    if mut == "Yin Yang" then mut = "YinYang" end
                    local traits = (ad.Traits and #ad.Traits > 0) and table.concat(ad.Traits, ", ") or "None"
                    local gv = AnimalsShared:GetGeneration(aName, ad.Mutation, ad.Traits, nil)
                    local gt = "$" .. NumberUtils:ToString(gv) .. "/s"

                    table.insert(allAnimalsCache, {
                        name = aInfo.DisplayName or aName,
                        genText = gt,
                        genValue = gv,
                        mutation = mut,
                        traits = traits,
                        owner = ownerName,
                        plot = plot.Name,
                        slot = tostring(slot),
                        uid = plot.Name .. "_" .. tostring(slot)
                    })
                end
            end
        end

        lastAnimalData[plot.Name] = hash
        changed = true
    end)

    if changed then
        table.sort(allAnimalsCache, function(a, b)
            return a.genValue > b.genValue
        end)

        SharedState.AllAnimalsCache = allAnimalsCache
        SharedState.ListNeedsRedraw = true

        if SharedState.UpdateAutoStealUI then
            SharedState.UpdateAutoStealUI()
        end

        if not hasShownPriorityAlert and Config.AlertsEnabled then
            task.spawn(function()
                local foundPriorityPet = nil
                for i = 1, #PRIORITY_LIST do
                    local priorityName = PRIORITY_LIST[i]
                    local searchName = priorityName:lower()

                    for _, pet in ipairs(allAnimalsCache) do
                        if pet.name and pet.name:lower() == searchName then
                            foundPriorityPet = pet
                            break
                        end
                    end

                    if foundPriorityPet then
                        break
                    end
                end

                if foundPriorityPet then
                    local ownerUsername = foundPriorityPet.owner
                    local ownerPlayer = nil

                    local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild(foundPriorityPet.plot)
                    if plot then
                        local sync = Synchronizer
                        if not sync then
                            local Packages = ReplicatedStorage:FindFirstChild("Packages")
                            if Packages then
                                local ok, syncModule = pcall(function()
                                    return require(Packages:WaitForChild("Synchronizer"))
                                end)
                                if ok then sync = syncModule end
                            end
                        end

                        if sync then
                            local ok, ch = pcall(function() return sync:Get(plot.Name) end)
                            if ok and ch then
                                local owner = ch:Get("Owner")
                                if owner then
                                    if typeof(owner) == "Instance" and owner:IsA("Player") then
                                        ownerPlayer = owner
                                        ownerUsername = owner.Name
                                    elseif type(owner) == "table" and owner.Name then
                                        ownerUsername = owner.Name
                                        ownerPlayer = Players:FindFirstChild(owner.Name)
                                    end
                                end
                            end
                        end
                    end

                    if not ownerPlayer and ownerUsername then
                        ownerPlayer = Players:FindFirstChild(ownerUsername)
                    end

                    ShowPriorityAlert(foundPriorityPet.name, foundPriorityPet.genText, foundPriorityPet.mutation, ownerUsername)
                end
            end)
        end
    end
end

    local function setupPlotListener(plot)
        local ch, retries = nil, 0
        while not ch and retries<50 do
            local ok, r = pcall(function() return Synchronizer:Get(plot.Name) end)
            if ok and r then ch=r; break else retries=retries+1; task.wait(0.1) end
        end
        if not ch then return end
        scanSinglePlot(plot)
        plot.DescendantAdded:Connect(function() task.wait(0.1); scanSinglePlot(plot) end)
        plot.DescendantRemoving:Connect(function() task.wait(0.1); scanSinglePlot(plot) end)
        task.spawn(function() while plot.Parent do task.wait(5); scanSinglePlot(plot) end end)
    end

    local plots = Workspace:WaitForChild("Plots", 8)
    if plots then
        for _, p in ipairs(plots:GetChildren()) do setupPlotListener(p) end
        plots.ChildAdded:Connect(function(p) task.wait(0.5); setupPlotListener(p) end)
        plots.ChildRemoved:Connect(function(p)
            lastAnimalData[p.Name]=nil
            for i=#allAnimalsCache,1,-1 do if allAnimalsCache[i].plot==p.Name then table.remove(allAnimalsCache,i) end end
            SharedState.ListNeedsRedraw=true
        end)
    end

    


    local hasShownPriorityAlert = false
    
    local function ShowPriorityAlert(brainrotName, genText, mutation, ownerUsername)
        if not Config.AlertsEnabled then return end
        if hasShownPriorityAlert then return end
        
        local ownerPlayer = ownerUsername and Players:FindFirstChild(ownerUsername) or nil
        local isInDuel = ownerPlayer and ownerPlayer:GetAttribute("__duels_block_steal") == true or false
        local duelStatusText = isInDuel and "IN DUEL" or "NOT IN DUEL"
        local duelStatusColor = isInDuel and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 255, 0)
        
        local mutationColors = {
            ["rainbow"] = Color3.fromRGB(255, 0, 255),
            ["bloodrot"] = Color3.fromRGB(139, 0, 0),
            ["candy"] = Color3.fromRGB(255, 105, 180),
            ["radioactive"] = Color3.fromRGB(0, 255, 0),
            ["cursed"] = Color3.fromRGB(255, 50, 50),
            ["gold"] = Color3.fromRGB(255, 215, 0),
            ["diamond"] = Color3.fromRGB(0, 255, 255),
            ["yinyang"] = Color3.fromRGB(255, 255, 255),
            ["lava"] = Color3.fromRGB(255, 100, 20)
        }
        
        local normalizedMutation = mutation and mutation:gsub("%s+", ""):lower() or ""
        local color = mutationColors[normalizedMutation] or Color3.fromRGB(255, 255, 255)
        
        local existing = PlayerGui:FindFirstChild("XiPriorityAlert")
        if existing then existing:Destroy() end
        
        local alertGui = Instance.new("ScreenGui")
        alertGui.Name = "XiPriorityAlert"
        alertGui.ResetOnSpawn = false
        alertGui.DisplayOrder = 999
        alertGui.Parent = PlayerGui
        
        hasShownPriorityAlert = true
        
        local alertFrame = Instance.new("Frame")
        alertFrame.Size = UDim2.new(0, 410, 0, 62)
        alertFrame.Position = UDim2.new(0.5, 0, 0, -76)
        alertFrame.AnchorPoint = Vector2.new(0.5, 0)
        alertFrame.BackgroundColor3 = Color3.fromRGB(8, 15, 12)
        alertFrame.BackgroundTransparency = 0.02
        alertFrame.BorderSizePixel = 0
        alertFrame.Parent = alertGui

        Instance.new("UICorner", alertFrame).CornerRadius = UDim.new(1, 0)

        local innerFrame = Instance.new("Frame", alertFrame)
        innerFrame.Name = "InnerFrame"
        innerFrame.Size = UDim2.new(1, -4, 1, -4)
        innerFrame.Position = UDim2.new(0, 2, 0, 2)
        innerFrame.BackgroundColor3 = Color3.fromRGB(10, 25, 18)
        innerFrame.BackgroundTransparency = 0.08
        innerFrame.BorderSizePixel = 0
        innerFrame.ZIndex = 0
        Instance.new("UICorner", innerFrame).CornerRadius = UDim.new(1, 0)
        
        local glowStroke = Instance.new("UIStroke", alertFrame)
        glowStroke.Name = "GlowStroke"
        glowStroke.Thickness = 2.5
        glowStroke.Color = color
        glowStroke.Transparency = 1
        
        local innerGlow = Instance.new("Frame", alertFrame)
        innerGlow.Name = "InnerGlow"
        innerGlow.Size = UDim2.new(1, 6, 1, 6)
        innerGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
        innerGlow.AnchorPoint = Vector2.new(0.5, 0.5)
        innerGlow.BackgroundColor3 = color
        innerGlow.BackgroundTransparency = 1
        innerGlow.ZIndex = 0
        Instance.new("UICorner", innerGlow).CornerRadius = UDim.new(1, 0)
        
        local nameLabel = Instance.new("TextLabel", alertFrame)
        nameLabel.Size = UDim2.new(1, -30, 0, 24)
        nameLabel.Position = UDim2.new(0, 15, 0, 10)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = brainrotName .. " - " .. genText
        nameLabel.Font = Enum.Font.GothamBlack
        nameLabel.TextSize = 18
        nameLabel.TextColor3 = color
        nameLabel.TextXAlignment = Enum.TextXAlignment.Center
        nameLabel.TextStrokeTransparency = 0
        nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        
        local genLabel = Instance.new("TextLabel", alertFrame)
        genLabel.Size = UDim2.new(1, -30, 0, 14)
        genLabel.Position = UDim2.new(0, 15, 0, 38)
        genLabel.BackgroundTransparency = 1
        genLabel.Text = duelStatusText
        genLabel.Font = Enum.Font.GothamBold
        genLabel.TextSize = 17
        genLabel.TextColor3 = duelStatusColor
        genLabel.TextXAlignment = Enum.TextXAlignment.Center
        genLabel.TextStrokeColor3 = color
        
        TweenService:Create(alertFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Position = UDim2.new(0.5, 0, 0, 22)
        }):Play()
        
        if Config.AlertSoundID and Config.AlertSoundID ~= "" then
            local sound = Instance.new("Sound")
            sound.SoundId = Config.AlertSoundID
            sound.Volume = 0.5
            sound.Parent = alertFrame
            sound:Play()
            
            TweenService:Create(glowStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = 0
            }):Play()
            TweenService:Create(innerGlow, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundTransparency = 0.85
            }):Play()
            
            task.delay(0.4, function()
                TweenService:Create(glowStroke, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    Transparency = 0.6
                }):Play()
                TweenService:Create(innerGlow, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    BackgroundTransparency = 1
                }):Play()
            end)
            
            sound.Ended:Connect(function() sound:Destroy() end)
        end
        
        task.delay(4, function()
            TweenService:Create(alertFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = UDim2.new(0.5, 0, 0, -76)
            }):Play()
            task.wait(0.35)
            alertGui:Destroy()
        end)
    end
    
    
    task.spawn(function()
        task.wait(0.5)  
        while true do
            task.wait(0.5)  
            if not hasShownPriorityAlert and Config.AlertsEnabled and #allAnimalsCache > 0 then
                
                local foundPriorityPet = nil
                for i = 1, #PRIORITY_LIST do
                    local priorityName = PRIORITY_LIST[i]
                    local searchName = priorityName:lower()
                    
                    
                    for _, pet in ipairs(allAnimalsCache) do
                        if pet.name and pet.name:lower() == searchName then
                            foundPriorityPet = pet
                            break
                        end
                    end
                    
                    
                    if foundPriorityPet then
                        break
                    end
                end
                
                if foundPriorityPet then
                    
                    local ownerUsername = foundPriorityPet.owner
                    local ownerPlayer = nil
                    
                    local plot = Workspace:FindFirstChild("Plots") and Workspace.Plots:FindFirstChild(foundPriorityPet.plot)
                    if plot then
                        
                        local sync = Synchronizer
                        if not sync then
                            local Packages = ReplicatedStorage:FindFirstChild("Packages")
                            if Packages then
                                local ok, syncModule = pcall(function() return require(Packages:WaitForChild("Synchronizer")) end)
                                if ok then sync = syncModule end
                            end
                        end
                        
                        if sync then
                            local ok, ch = pcall(function() return sync:Get(plot.Name) end)
                            if ok and ch then
                                local owner = ch:Get("Owner")
                                if owner then
                                    if typeof(owner) == "Instance" and owner:IsA("Player") then
                                        ownerPlayer = owner
                                        ownerUsername = owner.Name
                                    elseif type(owner) == "table" and owner.Name then
                                        ownerUsername = owner.Name
                                        ownerPlayer = Players:FindFirstChild(owner.Name)
                                    end
                                end
                            end
                        end
                    end
                    
                    
                    if not ownerPlayer and ownerUsername then
                        ownerPlayer = Players:FindFirstChild(ownerUsername)
                    end
                    
                    ShowPriorityAlert(foundPriorityPet.name, foundPriorityPet.genText, foundPriorityPet.mutation, ownerUsername)
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.5)
            if autoStealEnabled then
                local pets = get_all_pets()
                if #pets > 0 then
                    local function applySelection(newIndex)
                        if newIndex and newIndex >= 1 and newIndex <= #pets and selectedTargetIndex ~= newIndex then
                            selectedTargetIndex = newIndex
                            selectedTargetUID = pets[newIndex].uid
                            SharedState.ListNeedsRedraw = false
                            updateUI(autoStealEnabled, pets)
                        end
                    end

if Config.AutoGrabOwnBase == true then
    local ownBaseIndex = getNearestOwnBasePetIndex(pets)
    if ownBaseIndex then applySelection(ownBaseIndex) end
elseif stealPriorityEnabled then
    local foundPrioIndex = nil
    for _, pName in ipairs(PRIORITY_LIST) do
        local searchName = pName:lower()
        for i, p in ipairs(pets) do
            if p.petName and p.petName:lower() == searchName then
                foundPrioIndex = i
                break
            end
        end
        if foundPrioIndex then break end
    end
    if foundPrioIndex then
        applySelection(foundPrioIndex)
    else
        applySelection(1)
    end

elseif stealNearestEnabled then
    -- SI NEAREST + INSTANT STEAL ESTA ACTIVO, NO TOCAR TABLA NI SelectedPetData
    if not instantStealEnabled then
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local bestIndex = nil
            local bestDist = math.huge
            for i, p in ipairs(pets) do
                local targetPart = p.animalData and findAdorneeGlobal(p.animalData)
                if targetPart and targetPart:IsA("BasePart") then
                    local d = (hrp.Position - targetPart.Position).Magnitude
                    if d < bestDist then
                        bestDist = d
                        bestIndex = i
                    end
                end
            end
            if bestIndex then
                applySelection(bestIndex)
            else
                applySelection(1)
            end
        else
            applySelection(1)
        end
    end

elseif stealHighestEnabled then
    applySelection(1)
end
                end
            end
        end
    end)

    local lastInstantTick = 0
    RunService.Heartbeat:Connect(function()
        if not autoStealEnabled then return end
        if Config.AutoGrabOwnBase == true then
            local pets = get_all_pets()
            if #pets == 0 then return end
            local ownBaseIndex = getNearestOwnBasePetIndex(pets)
            if ownBaseIndex then
                selectedTargetIndex = ownBaseIndex
                selectedTargetUID = pets[ownBaseIndex].uid
            end
            if selectedTargetIndex > #pets then selectedTargetIndex = #pets end
            if selectedTargetIndex < 1 then selectedTargetIndex = 1 end
            local tp = pets[selectedTargetIndex]
            if not tp or not isMyBaseAnimal(tp.animalData) then return end
            local pr = PromptMemoryCache[tp.uid]
            if not pr or not pr.Parent then
                pr = findProximityPromptForAnimal(tp.animalData)
            end
            if pr then triggerOwnBaseGrab(pr, tp.uid) end
            return
        end
        if instantStealEnabled then
            local now = os.clock()
            if now - lastInstantTick < 0.05 then return end
            lastInstantTick = now
            if activeProgressTween then activeProgressTween:Cancel() activeProgressTween = nil end
            progressBarFill.Size = UDim2.new(1, 0, 1, 0)
            progressBarFill.BackgroundTransparency = 0
            if not instantStealDidInit then
                instantStealDidInit = true
                task.spawn(function()
                    if not game:IsLoaded() then game.Loaded:Wait() end
                    task.wait(0.5)
                    instantStealReady = true
                end)
            end
            if instantStealReady then
                if stealNearestEnabled then
                    local prompt, dist, name = findNearestPrompt_Instant()
                    if prompt and dist <= INSTANT_STEAL_RADIUS then
                        executeInstantSteal(prompt)
                    end
                else
                    local pets = get_all_pets()
                    if #pets > 0 then
                        if selectedTargetIndex > #pets then selectedTargetIndex = #pets end
                        if selectedTargetIndex < 1 then selectedTargetIndex = 1 end
                        local tp = pets[selectedTargetIndex]
                        if tp and (Config.AutoGrabOwnBase or not isMyBaseAnimal(tp.animalData)) then
                            local pr = PromptMemoryCache[tp.uid]
                            if not pr or not pr.Parent then
                                pr = findProximityPromptForAnimal(tp.animalData)
                            end
                            if pr then
                                executeInstantSteal(pr)
                            end
                        end
                    end
                end
            end
            return
        end
        local pets = get_all_pets()
        if #pets == 0 then return end
        if selectedTargetIndex > #pets then selectedTargetIndex = #pets end
        if selectedTargetIndex < 1 then selectedTargetIndex = 1 end
        local tp = pets[selectedTargetIndex]
        if not tp or (not Config.AutoGrabOwnBase and isMyBaseAnimal(tp.animalData)) then return end
        local pr = PromptMemoryCache[tp.uid]
        if not pr or not pr.Parent then
            pr = findProximityPromptForAnimal(tp.animalData)
        end
        if pr then
            attemptSteal(pr, tp.uid)
        end
    end)

    task.spawn(function() while task.wait(0.5) do updateUI(autoStealEnabled, get_all_pets()) end end)
    task.delay(1, function() SharedState.ListNeedsRedraw=true; updateUI(autoStealEnabled, get_all_pets()) end)
    task.spawn(function() while true do SharedState.AllAnimalsCache=allAnimalsCache; task.wait(0.5) end end)

    local beamFolder = Instance.new("Folder", Workspace)
    beamFolder.Name = "XiTracers"
    local currentBeam = nil
    local currentAtt0 = nil
    local currentAtt1 = nil

    local function updateTracer()
        if not autoStealEnabled or not Config.TracerEnabled or Config.StealNearest then
            if currentBeam then currentBeam:Destroy() currentBeam=nil end
            if currentAtt0 then currentAtt0:Destroy() currentAtt0=nil end
            if currentAtt1 then currentAtt1:Destroy() currentAtt1=nil end
            return
        end

        local pets = get_all_pets()
        if #pets == 0 then
            if currentBeam then currentBeam.Enabled = false end
            return
        end
        if selectedTargetIndex > #pets then selectedTargetIndex = #pets end
        if selectedTargetIndex < 1 then selectedTargetIndex = 1 end

        local best = pets[selectedTargetIndex] or pets[1]
        local targetPart = findAdorneeGlobal(best.animalData)
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        if hrp and targetPart then
            if not currentAtt0 or currentAtt0.Parent ~= hrp then
                if currentAtt0 then currentAtt0:Destroy() end
                currentAtt0 = Instance.new("Attachment", hrp)
            end
            if not currentAtt1 or currentAtt1.Parent ~= targetPart then
                if currentAtt1 then currentAtt1:Destroy() end
                currentAtt1 = Instance.new("Attachment", targetPart)
            end

            if not currentBeam then
                currentBeam = Instance.new("Beam", beamFolder)
                currentBeam.FaceCamera = true
                currentBeam.Width0 = 0.8
                currentBeam.Width1 = 0.8
                currentBeam.TextureMode = Enum.TextureMode.Static
                currentBeam.TextureSpeed = 3
            end

            currentBeam.Attachment0 = currentAtt0
            currentBeam.Attachment1 = currentAtt1
            currentBeam.Enabled = true

            local MUT_COLORS_TRACE = {
                Cursed=Color3.fromRGB(200,0,0), Gold=Color3.fromRGB(255,215,0),
                Diamond=Color3.fromRGB(0,255,255), YinYang=Color3.fromRGB(220,220,220),
                Rainbow=Color3.fromRGB(255,100,200), Lava=Color3.fromRGB(255,100,20),
                Candy=Color3.fromRGB(255,105,180), Divine=Color3.fromRGB(255,255,255)
            }
            local col = (best and best.mutation and MUT_COLORS_TRACE[best.mutation]) or Theme.Accent1
            currentBeam.Color = ColorSequence.new(col)
        else
            if currentBeam then currentBeam.Enabled = false end
        end
    end

    RunService.Heartbeat:Connect(updateTracer)
end)

-- Legacy XiAdminPanel block removed; keeping only literal replacement admin panel.

local BASES_LOW = {
    [1] = Vector3.new(-460, -6, 219), [5] = Vector3.new(-355, -6, 217),
    [2] = Vector3.new(-460, -6, 111), [6] = Vector3.new(-355, -6, 113),
    [3] = Vector3.new(-460, -6, 5),   [7] = Vector3.new(-355, -6, 5),
    [4] = Vector3.new(-460, -6, -100),[8] = Vector3.new(-355, -6, -100) 
}

local BASES_HIGH = {
    [1] = Vector3.new(-476.474853515625, 20.732906341552734, 220.94090270996094), [5] = Vector3.new(-342.5367126464844, 17.69801902770996, 221.44737243652344),
    [2] = Vector3.new(-476.5684814453125, 20.70664405822754, 113.77315521240234), [6] = Vector3.new(-342.8604736328125, 17.669641494750977, 113.41409301757812),
    [3] = Vector3.new(-476.8675842285156, 20.74148178100586, 6.178487777709961),  [7] = Vector3.new(-342.42108154296875, 17.687667846679688, 6.249461650848389),
    [4] = Vector3.new(-476.6324768066406, 20.744949340820312, -101.07275390625), [8] = Vector3.new(-342.7937927246094, 17.748071670532227, -99.73458862304688)
}

local CLONE_POSITIONS_FLOOR = {
    Vector3.new(-476, -4, 221), Vector3.new(-476, -4, 114),
    Vector3.new(-476, -4, 7),   Vector3.new(-476, -4, -100),
    Vector3.new(-342, -4, -100),Vector3.new(-342, -4, 6),
    Vector3.new(-342, -4, 114), Vector3.new(-342, -4, 220)
}

local FACE_TARGETS = {
    Vector3.new(-519, -3, 221), Vector3.new(-519, -3, 114),
    Vector3.new(-518, -3, 7),   Vector3.new(-519, -3, -100),
    Vector3.new(-301, -3, -100),Vector3.new(-301, -3, 7),
    Vector3.new(-302, -3, 114), Vector3.new(-300, -3, 220)
}

local TeleportData = {
    bodyController = nil,
}
local bodyController = TeleportData.bodyController
local floatActive = State.floatActive

RunService.Heartbeat:Connect(function()
    if State.floatActive and TeleportData.bodyController and LocalPlayer.Character then
        local hrp = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hrp then TeleportData.bodyController.Position = Vector3.new(hrp.Position.X, TeleportData.bodyController.Position.Y, TeleportData.bodyController.Position.Z) end
    end
end)

local function getClosestBaseIdx(pos)
    local closest, dist = 1, math.huge
    for i, basePos in pairs(BASES_LOW) do
        local d = (Vector2.new(pos.X, pos.Z) - Vector2.new(basePos.X, basePos.Z)).Magnitude
        if d < dist then dist = d; closest = i end
    end
    return closest
end

local isTpMoving = State.isTpMoving

_G._isTargetPlotUnlocked = function(plotName)
    local ok, res = pcall(function()
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then return false end
        local targetPlot = plots:FindFirstChild(plotName)
        if not targetPlot then return false end
        local unlockFolder = targetPlot:FindFirstChild("Unlock")
        if not unlockFolder then return true end
        local unlockItems = {}
        for _, item in pairs(unlockFolder:GetChildren()) do
            local pos = nil
            if item:IsA("Model") then pcall(function() pos = item:GetPivot().Position end)
            elseif item:IsA("BasePart") then pos = item.Position end
            if pos then table.insert(unlockItems, {Object = item, Height = pos.Y}) end
        end
        table.sort(unlockItems, function(a, b) return a.Height < b.Height end)
        if #unlockItems == 0 then return true end
        local floor1Door = unlockItems[1].Object
        for _, desc in ipairs(floor1Door:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled then return false end
        end
        for _, child in ipairs(floor1Door:GetChildren()) do
            if child:IsA("ProximityPrompt") and child.Enabled then return false end
        end
        return true
    end)
    return ok and res or false
end

local function runAutoSnipe()
    if State.isTpMoving then return end

    if State.carpetSpeedEnabled then
        setCarpetSpeed(false)
        if _carpetStatusLabel then
            _carpetStatusLabel.Text = "OFF"
            _carpetStatusLabel.TextColor3 = Theme.Error
        end
    end

    local function selectTarget()
        local minGen = 0
        do
            local str = Config.TpSettings.MinGenForTp
            if str and str ~= "" then
                local num, suf = tostring(str):lower():match("^([%d%.]+)([kmb]?)$")
                num = tonumber(num) or 0
                if suf == "k" then minGen = num * 1e3
                elseif suf == "m" then minGen = num * 1e6
                elseif suf == "b" then minGen = num * 1e9
                else minGen = num end
            end
        end
        local function allowed(a)
            if not a then return false end
            if not (Config.AutoGrabOwnBase or a.owner ~= LocalPlayer.Name) then return false end
            if minGen > 0 and (a.genValue or 0) < minGen then return false end
            return true
        end

        if SharedState.ManualTPTarget and not Config.AutoTPPriority then
            return SharedState.ManualTPTarget
        elseif Config.AutoTPPriority then
            local cache = SharedState.AllAnimalsCache
            if cache and type(cache) == "table" then
                local prioritySet = {}
                for _, pName in ipairs(PRIORITY_LIST) do prioritySet[pName:lower()] = true end
                if #PRIORITY_LIST > 0 then
                    local bestGen, best = -1, nil
                    for _, a in ipairs(cache) do
                        if a and a.name and prioritySet[a.name:lower()] and allowed(a) then
                            local gen = a.genValue or 0
                            if gen > bestGen then bestGen = gen; best = a end
                        end
                    end
                    if best then return best end
                end
                for _, a in ipairs(cache) do
                    if allowed(a) then return a end
                end
            end
        end
        if SharedState.SelectedPetData then return SharedState.SelectedPetData.animalData end
        return nil
    end

    local targetPetData = selectTarget()
    if not targetPetData then ShowNotification("ERROR","No target selected!"); return end

    local char = LocalPlayer.Character
    if not char then
        char = LocalPlayer.CharacterAdded:Wait()
    end
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    if _G.runAdminCommand and not Config.TpSettings.TeleportV3 then
        pcall(_G.runAdminCommand, LocalPlayer, "ragdoll")
        task.wait(0.2)
    end

State.isTpMoving = true
isTpMoving = State.isTpMoving

local ok, err = pcall(function()

    -- Re-sélection au dernier moment pour avoir le cache le plus à jour
    local fresh = selectTarget()
    local targetPetData = fresh or targetPetData

    local targetPart = findAdorneeGlobal(targetPetData)
    if not targetPart then
        error("targetPart nil")
    end

    local targetCF

    if targetPart:IsA("Attachment") then
        targetCF = targetPart.WorldCFrame
    elseif targetPart:IsA("BasePart") then
        targetCF = targetPart.CFrame
    else
        local okPivot, pivot = pcall(function()
            return targetPart:GetPivot()
        end)
        if okPivot then
            targetCF = pivot
        end
    end

    if not targetCF then
        error("targetCF nil")
    end

    local exactPos = targetPart.Position
    local carpetName = Config.TpSettings.Tool
    local carpet = LocalPlayer.Backpack:FindFirstChild(carpetName) or char:FindFirstChild(carpetName)
    local cloner = LocalPlayer.Backpack:FindFirstChild("Quantum Cloner") or char:FindFirstChild("Quantum Cloner")

    local isSecondFloor = exactPos.Y > 10
    local usedV2 = false
    local usedV3 = false

    equipTpToolAndWait(hum)

    if Config.TpSettings.TeleportV2 and isSecondFloor then
        local okV2, errV2 = runTeleportV2SecondFloor(targetPart, hum, hrp)
        if not okV2 then
            error("Teleport V2 failed: " .. tostring(errV2))
        end
        usedV2 = true
    elseif Config.TpSettings.TeleportV3 then
        local okV3, errV3 = runTeleportV3(targetPart, targetPetData, hum, hrp, exactPos)
        if not okV3 then
            error("Teleport V3 failed: " .. tostring(errV3))
        end
        usedV3 = true
    else
        local signPart = getClosestBaseSign(targetPart)
        if not signPart then
            error("signPart nil")
        end

        local signCF = signPart.CFrame
        local RIGHT = signCF.RightVector
        local LEFT = -RIGHT
        local FORWARD = signCF.LookVector
        local BACK = -signCF.LookVector

        local medPoint = getNearestTeleportV2MedPoint(hrp.Position)
        if not medPoint then
            error("normal tp MED point nil")
        end

        hrp.AssemblyLinearVelocity = Vector3.zero

        if hum and hum.Parent then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
        task.wait(0.01)

        if not hrp or not hrp.Parent then
            error("hrp lost during normal jump start")
        end

        hrp.CFrame = CFrame.new(-409, hrp.Position.Y, hrp.Position.Z)
        task.wait(Config.TpSettings.TpSpeed or 0.1)

        if not hrp or not hrp.Parent then
            error("hrp lost after normal jump reposition")
        end

        riseToY(hrp, 35)

        local tpPos
        if exactPos.Y <= 6.313370704650879 then
            local frontPoint = signPart.Position + (FORWARD * 20)
            local backPoint = signPart.Position + (BACK * 20)

            local myPos = hrp.Position
            local distFront = (Vector3.new(frontPoint.X, 0, frontPoint.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude
            local distBack = (Vector3.new(backPoint.X, 0, backPoint.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude

            local chosen = (distFront < distBack) and frontPoint or backPoint
            tpPos = Vector3.new(chosen.X, -4.8, chosen.Z)
        else
            local backPoint = signPart.Position + (BACK * 15)
            local frontPoint = signPart.Position + (FORWARD * 15)

            local myPos = hrp.Position
            local myFlat = Vector3.new(myPos.X, 0, myPos.Z)
            local distBack = (Vector3.new(backPoint.X, 0, backPoint.Z) - myFlat).Magnitude
            local distFront = (Vector3.new(frontPoint.X, 0, frontPoint.Z) - myFlat).Magnitude

            local chosen = (distBack < distFront) and backPoint or frontPoint
            tpPos = Vector3.new(chosen.X, signPart.Position.Y + 4, chosen.Z)
        end

        hrp.AssemblyLinearVelocity = Vector3.zero
        -- MOD GIRO: llegar al cartel ya mirando hacia LEFT, como TP V1 SUPER RAPIDO
        hrp.CFrame = CFrame.lookAt(tpPos, tpPos + LEFT)
        hrp.AssemblyLinearVelocity = Vector3.zero

        if isSecondFloor then
            waitUntilHeartbeat(function()
                return hrp and hrp.Parent
                    and (hrp.Position - tpPos).Magnitude <= 2
                    and hum
                    and hum.FloorMaterial ~= Enum.Material.Air
            end, 3.0)
        else
            waitUntilHeartbeat(function()
                return hrp and hrp.Parent
                    and (hrp.Position - tpPos).Magnitude <= 2
            end, 0.3)
        end

        prepMiniTpTool(hum, hrp)

        local baseOpen = false
        if not isSecondFloor and targetPetData.plot and _G._isTargetPlotUnlocked then
            pcall(function() baseOpen = _G._isTargetPlotUnlocked(targetPetData.plot) end)
        end

        if isSecondFloor then
            waitSecondsHeartbeat(0.02)
            hrp.AssemblyLinearVelocity = Vector3.zero
            waitSecondsHeartbeat(0.01)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = hrp.CFrame * CFrame.new(0, 0, -2.5)
            hrp.AssemblyLinearVelocity = Vector3.zero
            waitSecondsHeartbeat(Config.TpSettings.Floor2WaitTime or 0.07)
        elseif not baseOpen then
            hrp.AssemblyLinearVelocity = Vector3.zero
            local f1t = Config.TpSettings.Floor1WalkTime or 0.45
            walkForward(f1t)
            waitSecondsHeartbeat(f1t + 0.02)
        end

        if not (not isSecondFloor and baseOpen) then
            do
                local miniPos = hrp.Position
                local stillAtMiniPos = waitUntilHeartbeat(function()
                    return hrp and hrp.Parent and (hrp.Position - miniPos).Magnitude <= 2.0
                end, 0.75)

                if not stillAtMiniPos then
                    error("moved away from mini TP position before clone")
                end

                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero

                instantClone()
                waitUntilHeartbeat(function()
                    return hrp and hrp.Parent and ((hrp.Position - miniPos).Magnitude >= 0.35)
                end, 4.0)
                while _G.isCloning do task.wait() end
                if hrp and hrp.Parent then
                    hrp.AssemblyLinearVelocity = hrp.AssemblyLinearVelocity * 0.35
                end
            end
        end
    end

    task.wait(0.15)

    equipTpToolAndWait(hum)

    local verticalDiff = targetPart.Position.Y - hrp.Position.Y

    local isThirdFloor = exactPos.Y >= 28
    local needsPlatform = isThirdFloor or (not usedV2 and verticalDiff > 2)

    if needsPlatform then
        local airPos = Vector3.new(targetPart.Position.X, targetPart.Position.Y - 8, targetPart.Position.Z)

        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.CFrame = CFrame.new(airPos)
        hrp.AssemblyLinearVelocity = Vector3.zero

        local function isHolding()
            local c = LocalPlayer.Character
            if not c then return false end
            for _, part in ipairs(workspace:GetChildren()) do
                if part:IsA("BasePart") then
                    for _, weld in ipairs(part:GetChildren()) do
                        if (weld:IsA("WeldConstraint") or weld:IsA("Weld")) and
                           ((weld.Part0 and weld.Part0:IsDescendantOf(c)) or
                            (weld.Part1 and weld.Part1:IsDescendantOf(c))) then
                            return true
                        end
                    end
                end
            end
            return false
        end

        -- Maintien pendant 1s : re-TP si déviation > 1.5 studs, stop si brainrot pris
        local holdDeadline = tick() + 1.0
        local grabbed = false
        while tick() < holdDeadline do
            RunService.Heartbeat:Wait()
            if isHolding() then grabbed = true; break end
            if (hrp.Position - airPos).Magnitude > 1.5 then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.CFrame = CFrame.new(airPos)
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
        end

    elseif not usedV2 and not usedV3 then
        -- TP direct au brainrot puis maintien jusqu'au steal (V1 seulement)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.CFrame = CFrame.new(targetPart.Position)
        hrp.AssemblyLinearVelocity = Vector3.zero
        local deadline = tick() + 1.5
        while tick() < deadline do
            if LocalPlayer:GetAttribute("Stealing") then break end
            RunService.Heartbeat:Wait()
            if (hrp.Position - targetPart.Position).Magnitude > 2 then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.CFrame = CFrame.new(targetPart.Position)
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
        end
    end
end)

State.isTpMoving = false
isTpMoving = State.isTpMoving

if not ok then
    warn("runAutoSnipe error:", err)
end
end

-- TP direct dès que HRP existe (spawn/rejoin)
local function doSpawnTp(hrp)
    task.spawn(function()
        local targetPetData = SharedState.ManualTPTarget
            or (SharedState.SelectedPetData and SharedState.SelectedPetData.animalData)
        if not targetPetData then
            local cache = SharedState.AllAnimalsCache
            if cache then
                for _, pName in ipairs(PRIORITY_LIST or {}) do
                    for _, a in ipairs(cache) do
                        if a and a.name and a.name:lower() == pName:lower() then
                            targetPetData = a; break
                        end
                    end
                    if targetPetData then break end
                end
                if not targetPetData then targetPetData = cache[1] end
            end
        end
        if not targetPetData then return end
        local targetPart = findAdorneeGlobal(targetPetData)
        if not targetPart then return end
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.CFrame = CFrame.new(targetPart.Position.X, targetPart.Position.Y + 3, targetPart.Position.Z)
        hrp.AssemblyLinearVelocity = Vector3.zero
        if not State.isTpMoving then
            task.spawn(runAutoSnipe)
        end
    end)
end

local _skipNextSpawnTp = false

LocalPlayer.CharacterAdded:Connect(function(newChar)
    if _skipNextSpawnTp then
        _skipNextSpawnTp = false
        return
    end
    local hrp = newChar:FindFirstChild("HumanoidRootPart")
    if hrp then
        doSpawnTp(hrp)
    else
        local conn
        conn = newChar.ChildAdded:Connect(function(child)
            if child.Name == "HumanoidRootPart" then
                conn:Disconnect()
                doSpawnTp(child)
            end
        end)
    end
end)

-- Glisser à Y=25 au spawn quand V3 est actif
LocalPlayer.CharacterAdded:Connect(function(newChar)
    if not Config.TpSettings.TeleportV3 then return end
    local hrp = newChar:WaitForChild("HumanoidRootPart", 10)
    local hum = newChar:WaitForChild("Humanoid", 10)
    if not hrp or not hum then return end
    -- Attendre que le perso soit bien posé au sol
    local waitDeadline = tick() + 3
    repeat RunService.Heartbeat:Wait()
    until (hrp.Position.Y < 10 and hum.FloorMaterial ~= Enum.Material.Air) or tick() > waitDeadline
    -- Équiper le carpet
    local toolName = Config.TpSettings.Tool or "Flying Carpet"
    local tool = LocalPlayer.Backpack:FindFirstChild(toolName) or newChar:FindFirstChild(toolName)
    if not tool then
        task.wait(1)
        tool = LocalPlayer.Backpack:FindFirstChild(toolName) or newChar:FindFirstChild(toolName)
    end
    if tool then hum:EquipTool(tool) end
    -- Glisser vers Y=25
    local deadline = tick() + 5
    while tick() < deadline do
        if not hrp or not hrp.Parent then break end
        if hrp.Position.Y >= 24.5 then
            hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z)
            break
        end
        hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 145, hrp.AssemblyLinearVelocity.Z)
        RunService.Heartbeat:Wait()
    end
end)

local _GResetting = false

local function resetMoveAllToolsToBackpack(char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() hum:UnequipTools() end)
    end
    for _, ch in ipairs(char:GetChildren()) do
        if ch:IsA("Tool") then
            pcall(function() ch.Parent = LocalPlayer.Backpack end)
        end
    end
end

local function executeReset()
    if _GResetting then return end
    _GResetting = true
    _skipNextSpawnTp = true

    local character = LocalPlayer.Character
    if not character then
        pcall(function() LocalPlayer:LoadCharacter() end)
        _GResetting = false
        return
    end

    pcall(function()
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not (rootPart and humanoid) then return end

        resetMoveAllToolsToBackpack(character)

        rootPart.CFrame = CFrame.new(0, 15000, 0)
        RunService.Heartbeat:Wait()
        resetMoveAllToolsToBackpack(character)
        RunService.Heartbeat:Wait()

        humanoid = character:FindFirstChildOfClass("Humanoid")
        rootPart = character:FindFirstChild("HumanoidRootPart")
        if not (humanoid and rootPart) then return end

        pcall(function() humanoid.Health = 0 end)
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.Dead) end)

        if humanoid.Health > 0 then
            pcall(function() humanoid:TakeDamage(humanoid.MaxHealth * 99) end)
        end

        if humanoid.Health > 0 then
            pcall(function() character:BreakJoints() end)
        end

        humanoid = character:FindFirstChildOfClass("Humanoid")
        rootPart = character:FindFirstChild("HumanoidRootPart")
        if humanoid and rootPart and humanoid.Health > 0 then
            pcall(function()
                rootPart.AssemblyLinearVelocity = Vector3.zero
                rootPart.CFrame = CFrame.new(rootPart.Position.X, workspace.FallenPartsDestroyHeight - 500, rootPart.Position.Z)
            end)
        end
    end)

    task.defer(function()
        pcall(function() LocalPlayer:LoadCharacter() end)
        _GResetting = false
    end)

    task.delay(3, function()
        _GResetting = false
    end)
end

local function keyCodeFromConfigKeyName(name, fallback)
    local ok, res = pcall(function()
        if type(name) ~= "string" or name == "" then return fallback end
        local k = Enum.KeyCode[name]
        if k then return k end
        if #name == 1 then
            local u = string.upper(name)
            k = Enum.KeyCode[u]
            if k then return k end
        end
        return fallback
    end)
    return (ok and res) or fallback
end

local lastResetHotkeyTime = 0
local RESET_HOTKEY_DEBOUNCE = 0.45

task.spawn(function()
    local balloonPhrase = 'ran "balloon" on you'
    local lastBalloonAutoReset = 0
    local BALLOON_RESET_COOLDOWN = 8
    local balloonResetInProgress = false
    while true do
        task.wait(1)
        if not Config.AutoResetOnBalloon then continue end
        if balloonResetInProgress then continue end
        if tick() - lastBalloonAutoReset < BALLOON_RESET_COOLDOWN then continue end
        for _, gui in ipairs(PlayerGui:GetDescendants()) do
            local txt = (gui:IsA("TextLabel") or gui:IsA("TextButton")) and gui.Text
            if txt and string.find(txt, balloonPhrase) then
                lastBalloonAutoReset = tick()
                balloonResetInProgress = true
                task.delay(25, function()
                    balloonResetInProgress = false
                end)
                executeReset()
                break
            end
        end
    end
end)

task.spawn(function()
    local keyword = "you stole"
    local hooked = setmetatable({}, { __mode = "k" })

    local function hasKeyword(textValue)
        if typeof(textValue) ~= "string" then return false end
        return string.find(string.lower(textValue), keyword, 1, true) ~= nil
    end

    local function hookTextObject(obj)
        if hooked[obj] then return end
        hooked[obj] = true

        if Config.AutoKickOnSteal and hasKeyword(obj.Text) then
            kickPlayer()
            return
        end

        obj:GetPropertyChangedSignal("Text"):Connect(function()
            if Config.AutoKickOnSteal and hasKeyword(obj.Text) then
                kickPlayer()
            end
        end)
    end

    local function scanDescendants(root)
        for _, obj in ipairs(root:GetDescendants()) do
            if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
                hookTextObject(obj)
            end
        end
    end

    local function watchRoot(root)
        scanDescendants(root)
        root.DescendantAdded:Connect(function(desc)
            if desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox") then
                hookTextObject(desc)
            end
        end)
    end

    for _, gui in ipairs(PlayerGui:GetChildren()) do
        watchRoot(gui)
    end

    PlayerGui.ChildAdded:Connect(function(gui)
        watchRoot(gui)
    end)

    scanDescendants(PlayerGui)
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local resetK = keyCodeFromConfigKeyName(Config.ResetKey, Enum.KeyCode.H)
        if input.KeyCode == resetK then
            if UserInputService:GetFocusedTextBox() == nil then
                local now = tick()
                if now - lastResetHotkeyTime >= RESET_HOTKEY_DEBOUNCE then
                    lastResetHotkeyTime = now
                    executeReset()
                end
            end
            return
        end
    end

    if processed then return end

    local tpKey = Enum.KeyCode[NormalizeKeyName(Config.TpSettings.TpKey, "T")] or Enum.KeyCode.T
    local cloneKey = Enum.KeyCode[NormalizeKeyName(Config.TpSettings.CloneKey, "V")] or Enum.KeyCode.V

    if input.KeyCode == tpKey then
        runAutoSnipe()
    end

    if input.KeyCode == cloneKey then
        instantClone()
    end

    if input.KeyCode == (Enum.KeyCode[NormalizeKeyName(Config.TpSettings.CarpetSpeedKey, "Q")] or Enum.KeyCode.Q) then
        carpetSpeedEnabled = not carpetSpeedEnabled
        setCarpetSpeed(carpetSpeedEnabled)
        if _carpetStatusLabel then
            _carpetStatusLabel.Text = carpetSpeedEnabled and "ON" or "OFF"
            _carpetStatusLabel.TextColor3 = carpetSpeedEnabled and Theme.Success or Theme.Error
        end
        ShowNotification("CARPET SPEED", carpetSpeedEnabled and ("ON  |  "..Config.TpSettings.Tool.."  |  140") or "OFF")
    end

    if input.KeyCode == (Enum.KeyCode[NormalizeKeyName(Config.StealSpeedKey, "C")] or Enum.KeyCode.C) then
        if SharedState.StealSpeedToggleFunc then
            SharedState.StealSpeedToggleFunc()
        end
    end

    if input.KeyCode == (Enum.KeyCode[NormalizeKeyName(Config.FloatKeybind, "Z")] or Enum.KeyCode.Z) then
        toggleFloat(false)
    end

    if input.KeyCode == (Enum.KeyCode[NormalizeKeyName(Config.RagdollSelfKey, "")] or Enum.KeyCode.Unknown) then
        task.spawn(function()
            if _G.runAdminCommand then
                if _G.runAdminCommand(LocalPlayer, "ragdoll") then
                    ShowNotification("RAGDOLL SELF", "Triggered")
                else
                    ShowNotification("RAGDOLL SELF", "Failed")
                end
            else
                ShowNotification("RAGDOLL SELF", "Function not available")
            end
        end)
    end

end)

local settingsGui
local sFrame
local sList
local sLayout
local PageCards = {}

local function BuildSettingsAndMobileUI()
    settingsGui = UI.settingsGui

    if IS_MOBILE then
        local mobileGui = Instance.new("ScreenGui")
        mobileGui.Name = "XiMobileControls"
        mobileGui.ResetOnSpawn = false
        mobileGui.Parent = PlayerGui

        local controlsFrame = Instance.new("Frame")
        controlsFrame.Size = UDim2.new(0, 50, 0, 260)
        controlsFrame.Position = UDim2.new(1, -60, 0.5, -130)
        controlsFrame.BackgroundColor3 = Theme.Background
        controlsFrame.BackgroundTransparency = 0.2
        controlsFrame.BorderSizePixel = 0
        controlsFrame.Parent = mobileGui

        ApplyViewportUIScale(controlsFrame, 50, 260, 0.6, 1)

        Instance.new("UICorner", controlsFrame).CornerRadius = UDim.new(0, 10)
        local cStroke = Instance.new("UIStroke", controlsFrame)
        cStroke.Color = Theme.Accent1
        cStroke.Thickness = 1.5
        cStroke.Transparency = 0.4

        MakeDraggable(controlsFrame, controlsFrame, "MobileControls")

        local layout = Instance.new("UIListLayout", controlsFrame)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 8)
        layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        layout.VerticalAlignment = Enum.VerticalAlignment.Center

        local function createMobBtn(text, color, layoutOrder, callback)
            local btn = Instance.new("TextButton")
            btn.Name = "MobileAction_" .. tostring(text)
            btn.Size = UDim2.new(0, 38, 0, 38)
            btn.BackgroundColor3 = Theme.SurfaceHighlight
            btn.BackgroundTransparency = 0.08
            btn.Text = text
            btn.TextColor3 = Theme.TextPrimary
            btn.Font = Enum.Font.GothamBlack
            btn.TextSize = (text == "KICK") and 10 or 13
            btn.LayoutOrder = layoutOrder
            btn.AutoButtonColor = false
            btn.Visible = Config.ShowMobileActionButtons ~= false
            btn.Parent = mobileGui 
            
            local posKey = "MobileBtn_" .. text
            if Config.Positions[posKey] then
                btn.Position = UDim2.new(Config.Positions[posKey].X, Config.Positions[posKey].OffsetX or 0, Config.Positions[posKey].Y, Config.Positions[posKey].OffsetY or 0)
            else
                local angle = (layoutOrder - 1) * (math.pi * 2 / 6) - math.pi/2
                local radius = 64
                btn.Position = UDim2.new(0.5, math.cos(angle) * radius - 19, 0.5, math.sin(angle) * radius - 19)
            end

            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
            local stroke = Instance.new("UIStroke", btn)
            stroke.Color = color
            stroke.Thickness = 1.4
            stroke.Transparency = 0.28

            table.insert(SharedState.MobileActionButtons, btn)
            MakeDraggable(btn, btn, "MobileBtn_" .. text)

            btn.MouseButton1Click:Connect(function()
                local oldColor = btn.BackgroundColor3
                btn.BackgroundColor3 = color
                task.delay(0.1, function()
                    if btn and btn.Parent then
                        btn.BackgroundColor3 = oldColor
                    end
                end)
                callback(btn)
            end)
            return btn
        end

        SharedState.RefreshMobileActionButtons = function()
            local visible = Config.ShowMobileActionButtons ~= false
            for _, btn in ipairs(SharedState.MobileActionButtons) do
                if btn and btn.Parent then
                    btn.Visible = visible
                end
            end
        end

        createMobBtn("TP", Theme.Accent1, 1, function()
            
            if SharedState.ForcePrioritySelection then
                SharedState.ForcePrioritySelection()
                task.wait(0.1) 
            end
            runAutoSnipe()
            ShowNotification("MOBILE", "Teleporting...")
        end)

        createMobBtn("CL", Theme.Accent2, 2, function()
            instantClone()
            ShowNotification("MOBILE", "Cloning...")
        end)

        createMobBtn("SP", Theme.Success, 3, function(self)
            carpetSpeedEnabled = not carpetSpeedEnabled
            setCarpetSpeed(carpetSpeedEnabled)
            self.TextColor3 = carpetSpeedEnabled and Theme.Success or Theme.TextPrimary
            ShowNotification("MOBILE", carpetSpeedEnabled and "Speed ON" or "Speed OFF")
        end)

        createMobBtn("IV", Color3.fromRGB(255, 50, 50), 4, function(self)
            if _G.toggleInvisibleSteal then
                _G.toggleInvisibleSteal()
                task.delay(0.1, function()
                    local isOn = _G.invisibleStealEnabled
                    self.TextColor3 = isOn and Color3.fromRGB(255, 0, 0) or Theme.TextPrimary
                    ShowNotification("MOBILE", isOn and "Invis ON" or "Invis OFF")
                end)
            end
        end)

        createMobBtn("UI", Color3.fromRGB(255, 255, 255), 5, function()
            if settingsGui then
                settingsGui.Enabled = not settingsGui.Enabled
                ShowNotification("MOBILE", settingsGui.Enabled and "Menu opened" or "Menu closed")
            end
            if SharedState.RefreshMobileScale then
                SharedState.RefreshMobileScale()
            end
        end)

        createMobBtn("KICK", Theme.Error, 6, function()
            ShowNotification("MOBILE", "Kicking...")
            kickPlayer()
        end)

        if SharedState.RefreshMobileActionButtons then
            SharedState.RefreshMobileActionButtons()
        end

        local resetBtn = Instance.new("TextButton")
        resetBtn.Name = "MobileResetButton"
        resetBtn.Size = UDim2.new(0, 42, 0, 42)
        resetBtn.Position = UDim2.new(1, -58, 1, -105)
        resetBtn.BackgroundColor3 = Color3.fromRGB(255, 150, 50)
        resetBtn.AutoButtonColor = false
        resetBtn.Text = "🔧"
        resetBtn.Font = Enum.Font.GothamBlack
        resetBtn.TextSize = 20
        resetBtn.TextColor3 = Color3.new(0, 0, 0)
        resetBtn.Parent = mobileGui
        Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(1, 0)
        local resetStroke = Instance.new("UIStroke", resetBtn)
        resetStroke.Color = Color3.fromRGB(255, 100, 0)
        resetStroke.Thickness = 1.5
        resetStroke.Transparency = 0.25

        MakeDraggable(resetBtn, resetBtn)

        resetBtn.MouseButton1Click:Connect(function()
            Config.Positions = {
                AdminPanel = {X = 0.1859375, Y = 0.5767123526556385, OffsetX = 0, OffsetY = 0}, 
                StealSpeed = {X = 0.02, Y = 0.18}, 
                Settings = {X = 0.834375, Y = 0.43590998043052839}, 
                InvisPanel = {X = 0.8578125, Y = 0.17260276361454258, OffsetX = 0, OffsetY = 0}, 
                AutoSteal = {X = 0.02, Y = 0.35, OffsetX = 0, OffsetY = 0}, 
                MobileControls = {X = 0.9, Y = 0.4},
                MobileBtn_TP = {X = 0.5, Y = 0.4},
                MobileBtn_CL = {X = 0.5, Y = 0.4},
                MobileBtn_SP = {X = 0.5, Y = 0.4},
                MobileBtn_IV = {X = 0.5, Y = 0.4},
                MobileBtn_UI = {X = 0.5, Y = 0.4},
                MobileBtn_KICK = {X = 0.5, Y = 0.4},
            }
            Config.ShowMobileActionButtons = true
            Config.MobileGuiScale = 0.5
            SaveConfig()
            
            if SharedState.RefreshMobileScale then SharedState.RefreshMobileScale() end
            
            if mobileGui then
                mobileGui.Position = UDim2.new(Config.Positions.MobileControls.X, 0, Config.Positions.MobileControls.Y, 0)
            end
            
            ShowNotification("RESET", "All GUI positions and scale reset")
        end)

        local openBtn = Instance.new("TextButton")
        openBtn.Name = "MobileSettingsButton"
        openBtn.Size = UDim2.new(0, 42, 0, 42)
        openBtn.Position = UDim2.new(1, -58, 1, -58)
        openBtn.BackgroundColor3 = Theme.Accent1
        openBtn.AutoButtonColor = false
        openBtn.Text = "⚙"
        openBtn.Font = Enum.Font.GothamBlack
        openBtn.TextSize = 20
        openBtn.TextColor3 = Color3.new(0, 0, 0)
        openBtn.Parent = mobileGui
        Instance.new("UICorner", openBtn).CornerRadius = UDim.new(1, 0)
        local openStroke = Instance.new("UIStroke", openBtn)
        openStroke.Color = Theme.Accent2
        openStroke.Thickness = 1.5
        openStroke.Transparency = 0.25

        MakeDraggable(openBtn, openBtn)

        openBtn.MouseButton1Click:Connect(function()
            if settingsGui then
                settingsGui.Enabled = not settingsGui.Enabled
            end
            if SharedState.RefreshMobileScale then
                SharedState.RefreshMobileScale()
            end
        end)
    end

    Theme.Background = Color3.fromRGB(8, 15, 12)
    Theme.Surface = Color3.fromRGB(10, 25, 18)
    Theme.SurfaceHighlight = Color3.fromRGB(16, 42, 30)
    Theme.Accent1 = Color3.fromRGB(80, 210, 120)
    Theme.Accent2 = Color3.fromRGB(55, 160, 90)
    Theme.TextPrimary = Color3.fromRGB(225, 255, 235)
    Theme.TextSecondary = Color3.fromRGB(140, 200, 165)
    Theme.Success = Color3.fromRGB(80, 210, 120)

    local HAZE = {
        BG = Color3.fromRGB(8, 15, 12),
        SURF = Color3.fromRGB(10, 25, 18),
        SURF2 = Color3.fromRGB(16, 42, 30),
        TEXT = Color3.fromRGB(225, 255, 235),
        DIM = Color3.fromRGB(140, 200, 165),
        TOP = Color3.fromRGB(80, 210, 120),
        MID = Color3.fromRGB(55, 160, 90),
        BOT = Color3.fromRGB(16, 45, 32),
        ACCENT = Color3.fromRGB(80, 210, 120),
        ACCENT2 = Color3.fromRGB(55, 160, 90),
        STROKE = Color3.fromRGB(65, 180, 105),
        GLOW = Color3.fromRGB(140, 240, 175),
    }

    local function HazeCorner(parent, r)
        local u = Instance.new("UICorner")
        u.CornerRadius = UDim.new(0, r)
        u.Parent = parent
        return u
    end

    local function HazeStroke(parent, thickness, color, transparency)
        local s = Instance.new("UIStroke")
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Thickness = thickness or 1
        s.Color = color or HAZE.STROKE
        s.Transparency = transparency or 0.5
        s.Parent = parent
        return s
    end

    local function HazeGradient(parent, rotation)
        local g = Instance.new("UIGradient")
        g.Rotation = rotation or 90
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, HAZE.TOP),
            ColorSequenceKeypoint.new(0.50, HAZE.MID),
            ColorSequenceKeypoint.new(1.00, HAZE.BOT),
        })
        g.Parent = parent
        return g
    end

    local function HazeAccentGradient(parent)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, HAZE.ACCENT),
            ColorSequenceKeypoint.new(1.00, HAZE.ACCENT2),
        })
        g.Parent = parent
        return g
    end

    local function HazeTween(obj, ti, props, style, dir)
        TweenService:Create(obj, TweenInfo.new(ti or 0.2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props):Play()
    end



    settingsGui = Instance.new("ScreenGui")
    settingsGui.Name = "SettingsUI"
    settingsGui.ResetOnSpawn = false
    settingsGui.IgnoreGuiInset = true
    settingsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    settingsGui.Parent = PlayerGui
    settingsGui.Enabled = false

    local UI_SCALE = 1
    local function s(n) return math.floor(n * UI_SCALE + 0.5) end

    local BASE_MAIN_W = 808
    local MAIN_H = 456
    local HEADER_H = 52
    local SIDE_W = 163
    local RIGHT_REDUCE = 0.15
    local RIGHT_AVAILABLE = BASE_MAIN_W - SIDE_W - 20
    local RIGHT_W = math.floor(RIGHT_AVAILABLE * (1 - RIGHT_REDUCE))
    local CUT = RIGHT_AVAILABLE - RIGHT_W
    local MAIN_W = BASE_MAIN_W - CUT

    HAZE.BG = Color3.fromRGB(8, 15, 12)
    HAZE.SURF = Color3.fromRGB(10, 25, 18)
    HAZE.SURF2 = Color3.fromRGB(16, 42, 30)
    HAZE.SIDE = Color3.fromRGB(12, 28, 20)
    HAZE.SIDE2 = Color3.fromRGB(18, 50, 36)
    HAZE.TEXT = Color3.fromRGB(225, 255, 235)
    HAZE.DIM = Color3.fromRGB(140, 200, 165)
    HAZE.TOP = Color3.fromRGB(80, 210, 120)
    HAZE.MID = Color3.fromRGB(55, 160, 90)
    HAZE.BOT = Color3.fromRGB(16, 45, 32)
    HAZE.ACCENT = Color3.fromRGB(80, 210, 120)
    HAZE.ACCENT2 = Color3.fromRGB(55, 160, 90)
    HAZE.STROKE = Color3.fromRGB(65, 180, 105)
    HAZE.GLOW = Color3.fromRGB(140, 240, 175)
    Theme.Background = HAZE.BG
    Theme.Surface = HAZE.SURF
    Theme.SurfaceHighlight = HAZE.SURF2
    Theme.Accent1 = HAZE.ACCENT
    Theme.Accent2 = HAZE.ACCENT2
    Theme.TextPrimary = HAZE.TEXT
    Theme.TextSecondary = HAZE.DIM
    Theme.Success = HAZE.ACCENT2
    Theme.Error = HAZE.ACCENT2

    local function HazePad(parent, l, t, r, b)
        local p = Instance.new("UIPadding")
        p.PaddingLeft = UDim.new(0, l or 0)
        p.PaddingTop = UDim.new(0, t or 0)
        p.PaddingRight = UDim.new(0, r or 0)
        p.PaddingBottom = UDim.new(0, b or 0)
        p.Parent = parent
        return p
    end

    local function HazeBgTriGradient(parent)
        local g = Instance.new("UIGradient")
        g.Rotation = 90
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, HAZE.TOP),
            ColorSequenceKeypoint.new(0.50, HAZE.MID),
            ColorSequenceKeypoint.new(1.00, HAZE.BOT),
        })
        g.Parent = parent
        return g
    end

    local function HazeAccentGradient(parent)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, HAZE.ACCENT),
            ColorSequenceKeypoint.new(1.00, HAZE.ACCENT2),
        })
        g.Parent = parent
        return g
    end

    local function HazeKnobGradient(parent)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(200, 130, 160)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(225, 255, 235)),
        })
        g.Parent = parent
        return g
    end

    local function HazeRgbGradient(parent)
        local g = Instance.new("UIGradient")
        g.Rotation = 0
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(0.50, Color3.fromRGB(210, 215, 235)),
            ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 255, 255)),
        })
        g.Parent = parent
        return g
    end

    sFrame = Instance.new("Frame")
    sFrame.Name = "sFrame"
    sFrame.Size = UDim2.fromOffset(MAIN_W, MAIN_H)
    sFrame.Position = UDim2.new(Config.Positions.Settings.X, Config.Positions.Settings.OffsetX or 0, Config.Positions.Settings.Y, Config.Positions.Settings.OffsetY or 0)
    sFrame.BackgroundColor3 = HAZE.BG
    sFrame.BackgroundTransparency = 0.03
    sFrame.BorderSizePixel = 0
    sFrame.Parent = settingsGui
    HazeCorner(sFrame, 18)

    local outline = HazeStroke(sFrame, 2, Color3.fromRGB(65, 180, 105), 0)
    outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local glow = Instance.new("UIStroke")
    glow.Color = Color3.fromRGB(140, 240, 175)
    glow.Thickness = 4
    glow.Transparency = 0.75
    glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    glow.Parent = sFrame

    local shadow = Instance.new("ImageLabel")
    shadow.Name = "Shadow"
    shadow.AnchorPoint = Vector2.new(0.5, 0.5)
    shadow.Position = UDim2.new(0.5, 0, 0.5, 2)
    shadow.Size = UDim2.new(1, 30, 1, 30)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://6014261993"
    shadow.ImageColor3 = Color3.new(0, 0, 0)
    shadow.ImageTransparency = 0.60
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(49, 49, 450, 450)
    shadow.ZIndex = 0
    shadow.Parent = sFrame

    ApplyViewportUIScale(sFrame, MAIN_W, MAIN_H, 0.45, 0.85)


    local sidebar = Instance.new("Frame")
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.fromOffset(SIDE_W, MAIN_H)
    sidebar.BackgroundColor3 = HAZE.SURF
    sidebar.BackgroundTransparency = 0
    sidebar.BorderSizePixel = 0
    sidebar.Parent = sFrame
    HazeCorner(sidebar, 18)
    HazeStroke(sidebar, 1, HAZE.STROKE, 0.50)

    local brand = Instance.new("Frame")
    brand.Name = "Brand"
    brand.Size = UDim2.new(1, -16, 0, 60)
    brand.Position = UDim2.fromOffset(8, 8)
    brand.BackgroundColor3 = HAZE.SURF2
    brand.BackgroundTransparency = 0
    brand.BorderSizePixel = 0
    brand.Parent = sidebar
    HazeCorner(brand, 14)
    HazeStroke(brand, 1, HAZE.STROKE, 0.45)

    local vp = Instance.new("ViewportFrame")
    vp.Name = "CubeViewport"
    vp.Size = UDim2.fromOffset(38, 38)
    vp.AnchorPoint = Vector2.new(0.5, 0.5)
    vp.Position = UDim2.new(0.5, 0, 0.5, 0)
    vp.BackgroundColor3 = HAZE.SURF2
    vp.BackgroundTransparency = 0
    vp.BorderSizePixel = 0
    vp.LightDirection = Vector3.new(-1, -2, -1)
    vp.Ambient = Color3.fromRGB(60, 180, 100)
    vp.Parent = brand
    HazeCorner(vp, 12)
    HazeStroke(vp, 1, HAZE.GLOW, 0.45)

    local wm = Instance.new("WorldModel", vp)

    local cube = Instance.new("Part")
    cube.Size = Vector3.new(1.4, 1.4, 1.4)
    cube.CFrame = CFrame.new(0, 0, 0)
    cube.Anchored = true
    cube.CanCollide = false
    cube.CastShadow = false
    cube.Material = Enum.Material.Neon
    cube.Color = Color3.fromRGB(220, 30, 30)
    cube.Parent = wm

    local cam = Instance.new("Camera")
    cam.CFrame = CFrame.new(Vector3.new(3, 2.2, 3), Vector3.new(0, 0, 0))
    cam.FieldOfView = 40
    cam.Parent = vp
    vp.CurrentCamera = cam

    task.spawn(function()
        local t = 0
        while vp.Parent do
            t += RunService.Heartbeat:Wait()
            cube.CFrame = CFrame.Angles(t * 0.6, t * 0.9, t * 0.3)
        end
    end)

    local tabHolder = Instance.new("Frame")
    tabHolder.Name = "TabHolder"
    tabHolder.BackgroundTransparency = 1
    tabHolder.Position = UDim2.fromOffset(8, 76)
    tabHolder.Size = UDim2.new(1, -16, 0, 312)
    tabHolder.Parent = sidebar

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.Padding = UDim.new(0, 6)
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Parent = tabHolder

    local footer = Instance.new("Frame")
    footer.Name = "Footer"
    footer.Size = UDim2.new(1, -16, 0, 42)
    footer.Position = UDim2.new(0, 8, 1, -50)
    footer.BackgroundColor3 = HAZE.SURF2
    footer.BackgroundTransparency = 0
    footer.BorderSizePixel = 0
    footer.Parent = sidebar
    HazeCorner(footer, 12)
    HazeStroke(footer, 1, HAZE.STROKE, 0.48)

    local footerText = Instance.new("TextLabel")
    footerText.BackgroundTransparency = 1
    footerText.Size = UDim2.new(1, -14, 1, 0)
    footerText.Position = UDim2.fromOffset(7, 0)
    footerText.Font = Enum.Font.GothamMedium
    footerText.Text = "V 1.0"
    footerText.TextSize = 11
    footerText.TextColor3 = HAZE.DIM
    footerText.TextXAlignment = Enum.TextXAlignment.Left
    footerText.Parent = footer

    local right = Instance.new("Frame")
    right.Name = "Right"
    right.BackgroundTransparency = 1
    right.Position = UDim2.fromOffset(SIDE_W + 10, 10)
    right.Size = UDim2.new(0, RIGHT_W, 1, -20)
    right.Parent = sFrame

    local sHeader = Instance.new("Frame")
    sHeader.Name = "Header"
    sHeader.Size = UDim2.new(1, 0, 0, HEADER_H)
    sHeader.BackgroundColor3 = HAZE.SURF
    sHeader.BackgroundTransparency = 0
    sHeader.BorderSizePixel = 0
    sHeader.Parent = right
    HazeCorner(sHeader, 16)
    HazeStroke(sHeader, 1, HAZE.STROKE, 0.42)

    local sTitle = Instance.new("TextLabel")
    sTitle.BackgroundTransparency = 1
    sTitle.Position = UDim2.fromOffset(16, 0)
    sTitle.Size = UDim2.new(1, -72, 1, 0)
    sTitle.Font = Enum.Font.GothamBold
    sTitle.Text = "cn private"
    sTitle.TextColor3 = HAZE.TEXT
    sTitle.TextSize = 21
    sTitle.TextXAlignment = Enum.TextXAlignment.Left
    sTitle.Parent = sHeader

    do
        local titleGradient = HazeRgbGradient(sTitle)
        titleGradient.Offset = Vector2.new(-1, 0)
        task.spawn(function()
            while sTitle.Parent do
                titleGradient.Offset = Vector2.new(-1, 0)
                TweenService:Create(
                    titleGradient,
                    TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
                    {Offset = Vector2.new(1, 0)}
                ):Play()
                task.wait(2.5)
            end
        end)
    end

    local sClose = Instance.new("TextButton")
    sClose.AutoButtonColor = false
    sClose.Size = UDim2.fromOffset(30, 30)
    sClose.Position = UDim2.new(1, -40, 0.5, -15)
    sClose.BackgroundColor3 = HAZE.SURF2
    sClose.BackgroundTransparency = 0
    sClose.BorderSizePixel = 0
    sClose.Text = "X"
    sClose.Font = Enum.Font.GothamBold
    sClose.TextSize = 13
    sClose.TextColor3 = HAZE.TEXT
    sClose.Parent = sHeader
    HazeCorner(sClose, 10)
    HazeStroke(sClose, 1, HAZE.STROKE, 0.36)

    sClose.MouseEnter:Connect(function()
        HazeTween(sClose, 0.16, {BackgroundTransparency = 0.00, BackgroundColor3 = Color3.fromRGB(64, 74, 108)})
    end)
    sClose.MouseLeave:Connect(function()
        HazeTween(sClose, 0.16, {BackgroundTransparency = 0.00, BackgroundColor3 = HAZE.SURF2})
    end)
    sClose.MouseButton1Click:Connect(function()
        settingsGui.Enabled = false
    end)

    MakeDraggable(sHeader, sFrame, "Settings")

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.BackgroundTransparency = 1
    content.Position = UDim2.fromOffset(0, HEADER_H + 10)
    content.Size = UDim2.new(1, 0, 1, -(HEADER_H + 10))
    content.Parent = right

    local function makePage(name)
        local page = Instance.new("Frame")
        page.Name = name
        page.BackgroundTransparency = 1
        page.Size = UDim2.fromScale(1, 1)
        page.Visible = false
        page.Parent = content

        local card = Instance.new("Frame")
        card.Name = "Card"
        card.BackgroundColor3 = HAZE.SURF
        card.BackgroundTransparency = 0
        card.BorderSizePixel = 0
        card.Size = UDim2.fromScale(1, 1)
        card.Parent = page
        HazeCorner(card, 16)
        HazeStroke(card, 1, HAZE.STROKE, 0.48)

        local sc = Instance.new("ScrollingFrame")
        sc.Name = "Scroll"
        sc.Size = UDim2.new(1, -12, 1, -12)
        sc.Position = UDim2.fromOffset(6, 6)
        sc.BackgroundTransparency = 1
        sc.BorderSizePixel = 0
        sc.ScrollBarThickness = 4
        sc.ScrollBarImageColor3 = HAZE.ACCENT2
        sc.CanvasSize = UDim2.new(0, 0, 0, 0)
        sc.Parent = card

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 6)
        pad.PaddingRight = UDim.new(0, 6)
        pad.PaddingTop = UDim.new(0, 6)
        pad.PaddingBottom = UDim.new(0, 10)
        pad.Parent = sc

        local lay = Instance.new("UIListLayout")
        lay.Padding = UDim.new(0, 8)
        lay.SortOrder = Enum.SortOrder.LayoutOrder
        lay.Parent = sc

        lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            sc.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 18)
        end)

        do
            local row = Instance.new("Frame")
            row.Name = "PageTitleRow"
            row.Size = UDim2.new(1, 0, 0, s(30))
            row.BackgroundTransparency = 1
            row.Parent = sc

            local accent = Instance.new("Frame")
            accent.Size = UDim2.new(0, s(4), 0, s(18))
            accent.Position = UDim2.new(0, s(4), 0.5, -s(9))
            accent.BackgroundColor3 = HAZE.ACCENT
            accent.BorderSizePixel = 0
            accent.Parent = row
            HazeCorner(accent, 3)
            HazeAccentGradient(accent)

            local lbl = Instance.new("TextLabel")
            lbl.BackgroundTransparency = 1
            lbl.Size = UDim2.new(0, 150, 1, 0)
            lbl.Position = UDim2.new(0, s(16), 0, 0)
            lbl.Text = tostring(name)
            lbl.TextColor3 = HAZE.TEXT
            lbl.TextSize = s(15)
            lbl.Font = Enum.Font.GothamBold
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = row

            local line = Instance.new("Frame")
            line.Size = UDim2.new(1, -s(160), 0, 1)
            line.Position = UDim2.new(0, s(158), 0.5, 0)
            line.AnchorPoint = Vector2.new(0, 0.5)
            line.BackgroundColor3 = HAZE.ACCENT2
            line.BackgroundTransparency = 0.35
            line.BorderSizePixel = 0
            line.Parent = row
            HazeCorner(line, 999)
        end

        return page, card, sc, lay
    end

    local Pages = {}
    PageCards = {}
    local settingsPage, settingsCard; settingsPage, settingsCard, sList, sLayout = makePage("Settings")
    Pages.Settings = settingsPage
    PageCards.Settings = settingsCard
    _G.HazePageScrolls = _G.HazePageScrolls or {}
    _G.HazePageScrolls.Settings = sList
    _G.HazeActiveScroll = sList

    do
        local page, card, sc = makePage("Main")
        Pages.Main = page
        PageCards.Main = card
        _G.HazePageScrolls.Main = sc
    end
    do
        local page, card, sc = makePage("Misc")
        Pages.Misc = page
        PageCards.Misc = card
        _G.HazePageScrolls.Misc = sc
    end
    do
        local page, card, sc = makePage("Player")
        Pages.Player = page
        PageCards.Player = card
        _G.HazePageScrolls.Player = sc
    end
    do
        local page, card, sc = makePage("Priority")
        Pages.Priority = page
        PageCards.Priority = card
        _G.HazePageScrolls.Priority = sc
    end
    do
        local page, card, sc = makePage("Keybinds")
        Pages.Keybinds = page
        PageCards.Keybinds = card
        _G.HazePageScrolls.Keybinds = sc
    do
        local page, card, sc = makePage("Teleport")
        Pages.Teleport = page
        PageCards.Teleport = card
        _G.HazePageScrolls.Teleport = sc
    end
    end
    do
        local page, card, sc = makePage("Credits")
        Pages.Credits = page
        PageCards.Credits = card
        _G.HazePageScrolls.Credits = sc
    end

    local TABS = {
        { key = "Main",     label = "Main"     },
        { key = "Misc",     label = "Misc"     },
        { key = "Player",   label = "Player"   },
        { key = "Priority", label = "Priority" },
        { key = "Keybinds", label = "Keybinds" },
        { key = "Settings", label = "Settings" },
        { key = "Credits",  label = "Credits"  },
        { key = "Teleport", label = "Flash TP" },
    }

    local tabButtons = {}
    local currentKey = nil

    local showTab

    local function makeSideTab(def, order)
        local btn = Instance.new("TextButton")
        btn.Name = def.key .. "Tab"
        btn.AutoButtonColor = false
        btn.Size = UDim2.new(1, 0, 0, 40)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.LayoutOrder = order
        btn.Parent = tabHolder

        local bg = Instance.new("Frame")
        bg.Size = UDim2.fromScale(1, 1)
        bg.BackgroundColor3 = HAZE.SIDE2
        bg.BackgroundTransparency = 0.32
        bg.BorderSizePixel = 0
        bg.Parent = btn
        HazeCorner(bg, 11)

        local bgStroke = HazeStroke(bg, 1, HAZE.STROKE, 0.52)

        local bar = Instance.new("Frame")
        bar.Size = UDim2.fromOffset(4, 10)
        bar.Position = UDim2.new(0, 7, 0.5, 0)
        bar.AnchorPoint = Vector2.new(0, 0.5)
        bar.BackgroundColor3 = HAZE.ACCENT
        bar.BorderSizePixel = 0
        bar.Parent = bg
        HazeCorner(bar, 999)
        HazeAccentGradient(bar)

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Position = UDim2.fromOffset(22, 0)
        label.Size = UDim2.new(1, -32, 1, 0)
        label.Font = Enum.Font.GothamBold
        label.Text = def.label
        label.TextColor3 = HAZE.DIM
        label.TextSize = 13
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = bg

        local bottomLine = Instance.new("Frame")
        bottomLine.Size = UDim2.new(0.35, 0, 0, 1)
        bottomLine.Position = UDim2.new(0, 22, 1, -5)
        bottomLine.BackgroundColor3 = HAZE.ACCENT
        bottomLine.BorderSizePixel = 0
        bottomLine.Parent = bg
        HazeAccentGradient(bottomLine)

        btn.MouseEnter:Connect(function()
            if currentKey ~= def.key then
                HazeTween(bg, 0.16, {BackgroundTransparency = 0.09, BackgroundColor3 = Color3.fromRGB(55, 22, 40)})
                HazeTween(label, 0.16, {TextColor3 = HAZE.TEXT})
                HazeTween(bottomLine, 0.16, {Size = UDim2.new(0.50, 0, 0, 1)})
            end
        end)

        btn.MouseLeave:Connect(function()
            if currentKey ~= def.key then
                HazeTween(bg, 0.16, {BackgroundTransparency = 0.32, BackgroundColor3 = HAZE.SIDE2})
                HazeTween(label, 0.16, {TextColor3 = HAZE.DIM})
                HazeTween(bottomLine, 0.16, {Size = UDim2.new(0.35, 0, 0, 1)})
            end
        end)

        btn.MouseButton1Click:Connect(function()
            showTab(def.key)
        end)

        tabButtons[def.key] = {
            ButtonBack = bg,
            Stroke = bgStroke,
            Bar = bar,
            Label = label,
            BottomLine = bottomLine,
        }
    end

    showTab = function(key)
        currentKey = key

        for name, page in pairs(Pages) do
            page.Visible = (name == key)
        end

        for name, refs in pairs(tabButtons) do
            local selected = (name == key)
            HazeTween(refs.ButtonBack, 0.20, {
                BackgroundTransparency = selected and 0.03 or 0.18,
                BackgroundColor3 = selected and Color3.fromRGB(58, 22, 42) or HAZE.SIDE2
            })
            HazeTween(refs.Stroke, 0.20, {
                Transparency = selected and 0.18 or 0.52
            })
            HazeTween(refs.Bar, 0.20, {
                Size = selected and UDim2.fromOffset(4, 24) or UDim2.fromOffset(4, 10)
            })
            HazeTween(refs.Label, 0.20, {
                TextColor3 = selected and HAZE.TEXT or HAZE.DIM,
                Position = selected and UDim2.fromOffset(24, 0) or UDim2.fromOffset(22, 0)
            })
            HazeTween(refs.BottomLine, 0.20, {
                Size = selected and UDim2.new(1, -26, 0, 1) or UDim2.new(0.35, 0, 0, 1)
            })
        end

        local pages = _G.HazePageScrolls
        if pages and pages[key] then
            _G.HazeActiveScroll = pages[key]
        else
            _G.HazeActiveScroll = sList
        end

        if key == "Priority" and _G.ReloadEmbeddedPriorityUi then
            _G.ReloadEmbeddedPriorityUi()
        end
    end

    for i, def in ipairs(TABS) do
        makeSideTab(def, i)
    end

    task.defer(function()
        task.wait()
        showTab("Main")
    end)

    function _G.SetHazeUIPage(name)
        local pages = _G.HazePageScrolls
        if pages and pages[name] then
            _G.HazeActiveScroll = pages[name]
            showTab(name)
        else
            _G.HazeActiveScroll = sList
        end
    end

    local function CreateToggleSwitch(parent, initialState, callback)
        local sw = Instance.new("Frame")
        sw.Size = UDim2.new(0, 62, 0, 24)
        sw.Position = UDim2.new(1, -74, 0.5, -12)
        sw.BackgroundColor3 = Color3.fromRGB(38, 18, 30)
        sw.BackgroundTransparency = 0.02
        sw.BorderSizePixel = 0
        sw.Parent = parent
        HazeCorner(sw, 7)

        local stBase = HazeStroke(sw, 1, HAZE.STROKE, 0.60)

        local stGlow = Instance.new("UIStroke")
        stGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stGlow.Thickness = 2
        stGlow.Color = HAZE.GLOW
        stGlow.Transparency = 1
        stGlow.Parent = sw

        local fill = Instance.new("Frame")
        fill.Size = initialState and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = HAZE.ACCENT2
        fill.BackgroundTransparency = initialState and 0.18 or 0.60
        fill.BorderSizePixel = 0
        fill.Parent = sw
        HazeCorner(fill, 7)
        HazeAccentGradient(fill)

        local dot = Instance.new("Frame")
        dot.Size = UDim2.fromOffset(22, 22)
        dot.Position = initialState and UDim2.new(1, -23, 0.5, -11) or UDim2.new(0, 1, 0.5, -11)
        dot.BackgroundColor3 = Color3.fromRGB(225, 255, 235)
        dot.BorderSizePixel = 0
        dot.Parent = sw
        HazeCorner(dot, 7)
        HazeKnobGradient(dot)
        local knobStroke = HazeStroke(dot, 1, HAZE.STROKE, 0.65)

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.Parent = sw

        local pulseId = 0
        local isOn = initialState == true

        local function startPulse()
            pulseId += 1
            local myId = pulseId
            task.spawn(function()
                while sw.Parent and isOn and pulseId == myId do
                    HazeTween(stGlow, 0.85, {Transparency = 0.08}, Enum.EasingStyle.Sine)
                    task.wait(0.9)
                    if not (sw.Parent and isOn and pulseId == myId) then break end
                    HazeTween(stGlow, 0.85, {Transparency = 0.20}, Enum.EasingStyle.Sine)
                    task.wait(0.9)
                end
            end)
        end

        local function SetState(state)
            isOn = state == true
            if isOn then
                fill.Size = UDim2.new(1, 0, 1, 0)
                fill.BackgroundTransparency = 0.32
                dot.Position = UDim2.new(1, -23, 0.5, -11)
                stGlow.Transparency = 0.10
                stBase.Transparency = 0.85
                knobStroke.Transparency = 0.35
                sw.BackgroundTransparency = 0.00
                startPulse()
            else
                pulseId += 1
                fill.Size = UDim2.new(0, 0, 1, 0)
                fill.BackgroundTransparency = 0.60
                dot.Position = UDim2.new(0, 1, 0.5, -11)
                stGlow.Transparency = 1
                stBase.Transparency = 0.60
                knobStroke.Transparency = 0.65
                sw.BackgroundTransparency = 0.02
            end
        end

        if isOn then
            fill.Size = UDim2.new(1, 0, 1, 0)
            fill.BackgroundTransparency = 0.32
            dot.Position = UDim2.new(1, -23, 0.5, -11)
            stGlow.Transparency = 0.10
            stBase.Transparency = 0.85
            knobStroke.Transparency = 0.35
            sw.BackgroundTransparency = 0.00
            startPulse()
        else
            SetState(false)
        end

        btn.MouseButton1Click:Connect(function()
            callback(not isOn, function(state)
                HazeTween(fill, 0.22, {
                    Size = state and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 1, 0),
                    BackgroundTransparency = state and 0.18 or 0.60
                })
                HazeTween(dot, 0.22, {
                    Position = state and UDim2.new(1, -23, 0.5, -11) or UDim2.new(0, 1, 0.5, -11)
                })
                HazeTween(stBase, 0.22, {Transparency = state and 0.85 or 0.60})
                HazeTween(knobStroke, 0.22, {Transparency = state and 0.35 or 0.65})
                HazeTween(sw, 0.22, {BackgroundTransparency = state and 0.00 or 0.02})
                if state then
                    isOn = true
                    startPulse()
                    HazeTween(stGlow, 0.22, {Transparency = 0.10})
                else
                    isOn = false
                    pulseId += 1
                    HazeTween(stGlow, 0.12, {Transparency = 1}, Enum.EasingStyle.Sine)
                end
            end)
        end)

        return {Set = SetState, Container = sw}
    end

    local function CreateRow(text, height)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, height or s(46))
        row.BackgroundColor3 = HAZE.SURF2
        row.BackgroundTransparency = 0.12
        row.BorderSizePixel = 0
        row.Parent = (_G.HazeActiveScroll or sList)
        HazeCorner(row, s(10))
        HazeStroke(row, 1, HAZE.STROKE, 0.55)
        HazePad(row, s(12), s(8), s(12), s(8))

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(1, -(s(67) + s(14)), 1, 0)
        lbl.Text = text
        lbl.Font = Enum.Font.GothamMedium
        lbl.TextSize = s(14)
        lbl.TextColor3 = HAZE.TEXT
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        return row
    end

    local function CreatePageHeader(text)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, s(30))
        row.BackgroundTransparency = 1
        row.Parent = (_G.HazeActiveScroll or sList)

        local accent = Instance.new("Frame")
        accent.Size = UDim2.new(0, s(4), 0, s(18))
        accent.Position = UDim2.new(0, s(4), 0.5, -s(9))
        accent.BackgroundColor3 = HAZE.ACCENT
        accent.BorderSizePixel = 0
        accent.Parent = row
        HazeCorner(accent, 3)
        HazeAccentGradient(accent)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -s(24), 1, 0)
        lbl.Position = UDim2.new(0, s(16), 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = HAZE.TEXT
        lbl.TextSize = s(12)
        lbl.Font = Enum.Font.GothamBlack
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local line = Instance.new("Frame")
        line.Size = UDim2.new(1, -s(90), 0, 1)
        line.Position = UDim2.new(0, s(82), 0.5, 0)
        line.BackgroundColor3 = HAZE.ACCENT
        line.BackgroundTransparency = 0.7
        line.BorderSizePixel = 0
        line.Parent = row

        return row
    end

    local function CreateSectionHeader(text)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, s(22))
        row.BackgroundTransparency = 1
        row.Parent = (_G.HazeActiveScroll or sList)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -s(8), 1, 0)
        lbl.Position = UDim2.new(0, s(2), 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = HAZE.ACCENT
        lbl.TextSize = s(12)
        lbl.Font = Enum.Font.GothamBlack
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        return row
    end

    local function CreateSubHeader(text)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, s(18))
        row.BackgroundTransparency = 1
        row.Parent = (_G.HazeActiveScroll or sList)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -s(14), 1, 0)
        lbl.Position = UDim2.new(0, s(10), 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = Theme.TextSecondary
        lbl.TextSize = s(11)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        return row
    end
    do
    _G.SetHazeUIPage("Main")
    _G.HazeLastAutoTpLoadRow = CreateRow("Auto TP on Script Load")
    CreateToggleSwitch(_G.HazeLastAutoTpLoadRow, Config.TpSettings.TpOnLoad, function(ns, set)
        set(ns); Config.TpSettings.TpOnLoad = ns; SaveConfig()
        ShowNotification("AUTO TP ON LOAD", ns and "ENABLED" or "DISABLED")
    end)

    local rMinGen = CreateRow("Min Gen for Auto TP")
    local minGenBox = Instance.new("TextBox", rMinGen)
    minGenBox.Size = UDim2.new(0, 100, 0, 24)
    minGenBox.Position = UDim2.new(1, -110, 0.5, -12)
    minGenBox.BackgroundColor3 = Theme.SurfaceHighlight
    minGenBox.Text = tostring(Config.TpSettings.MinGenForTp or "")
    minGenBox.Font = Enum.Font.Gotham
    minGenBox.TextSize = 11
    minGenBox.TextColor3 = Theme.TextPrimary
    minGenBox.PlaceholderText = "e.g. 5k, 1m, 1b"
    Instance.new("UICorner", minGenBox).CornerRadius = UDim.new(0, 4)
    minGenBox.FocusLost:Connect(function()
        local raw = minGenBox.Text:gsub("%s", "")
        Config.TpSettings.MinGenForTp = (raw == "" and "" or raw)
        SaveConfig()
        ShowNotification("MIN GEN FOR TP", Config.TpSettings.MinGenForTp == "" and "No minimum" or "Min: " .. (Config.TpSettings.MinGenForTp or ""))
    end)

    _G.SetHazeUIPage("Misc")
    local rFPS = CreateRow("FPS Boost V1")
    CreateToggleSwitch(rFPS, Config.FPSBoost, function(ns, set)
        set(ns); setFPSBoost(ns)
        ShowNotification("FPS BOOST", ns and "ENABLED" or "DISABLED")
    end)

    local rFPSV2 = CreateRow("FPS Boost V2")
    CreateToggleSwitch(rFPSV2, Config.FPSBoostV2, function(ns, set)
        set(ns); setFPSBoostV2(ns)
        ShowNotification("FPS BOOST V2", ns and "ENABLED" or "DISABLED")
    end)

    local rTrace = CreateRow("Tracer Best Brainrot")
    CreateToggleSwitch(rTrace, Config.TracerEnabled, function(ns, set)
        set(ns); Config.TracerEnabled = ns; SaveConfig()
        ShowNotification("TRACER", ns and "ENABLED" or "DISABLED")
    end)

    local rLineToBase = CreateRow("Line to base")
    CreateToggleSwitch(rLineToBase, Config.LineToBase, function(ns, set)
        set(ns); Config.LineToBase = ns; SaveConfig()
        if not ns and _G.resetPlotBeam then pcall(_G.resetPlotBeam) end
        ShowNotification("LINE TO BASE", ns and "ENABLED" or "DISABLED")
    end)

    local rGrief = CreateRow("Grief Detector")
    CreateToggleSwitch(rGrief, Config.GriefDetectorEnabled, function(ns, set)
        set(ns); Config.GriefDetectorEnabled = ns; SaveConfig()
        if _G.GriefDetectorSetEnabled then _G.GriefDetectorSetEnabled(ns) end
        ShowNotification("GRIEF DETECTOR", ns and "ENABLED" or "DISABLED")
    end)

    end
    autoTPPriorityToggleRef = autoTPPriorityToggleRef or {setFn = nil}
    do
    _G.SetHazeUIPage("Main")
    CreateSectionHeader("Teleport")
    local rTeleportV2 = CreateRow("Teleport V2")
    CreateToggleSwitch(rTeleportV2, Config.TpSettings.TeleportV2 == true, function(ns, set)
        set(ns)
        Config.TpSettings.TeleportV2 = ns
        SaveConfig()
        ShowNotification("TELEPORT V2", ns and "ENABLED" or "DISABLED")
    end)

    local rTeleportV3 = CreateRow("Teleport V3")
    CreateToggleSwitch(rTeleportV3, Config.TpSettings.TeleportV3 == true, function(ns, set)
        set(ns)
        Config.TpSettings.TeleportV3 = ns
        SaveConfig()
        ShowNotification("TELEPORT V3", ns and "ENABLED" or "DISABLED")
    end)

    local toolOptions = {"Flying Carpet", "Cupid's Wings", "Santa's Sleigh", "Witch's Broom"}
    local toolSwitches = {}
    for _, toolName in ipairs(toolOptions) do
        local r = CreateRow(toolName)
        local ts = CreateToggleSwitch(r, Config.TpSettings.Tool==toolName, function(rs, set)
            if rs then
                Config.TpSettings.Tool=toolName; SaveConfig(); set(true)
                for n, sw in pairs(toolSwitches) do if n~=toolName then sw.Set(false) end end
                ShowNotification("TP TOOL", toolName)
            else
                set(Config.TpSettings.Tool==toolName)
            end
        end)
        toolSwitches[toolName] = ts
    end

    
    local rSpeed = CreateRow("Auto Snipe Delay")
    local speedCont = Instance.new("Frame", rSpeed)
    speedCont.Size = UDim2.new(0,100,0,24); speedCont.Position = UDim2.new(1,-110,0.5,-12); speedCont.BackgroundTransparency=1
    local speedBtns = {}
    local selectedDelayOption = math.clamp(tonumber(Config.TpSettings.Speed) or 1, 1, 4)
    Config.TpSettings.Speed = selectedDelayOption
    for i = 1, 4 do
        local b = Instance.new("TextButton", speedCont)
        b.Size = UDim2.new(0.22,0,1,0); b.Position = UDim2.new((i-1)*0.26,0,0,0)
        local act = selectedDelayOption == i
        b.BackgroundColor3 = act and Theme.Accent1 or Theme.SurfaceHighlight
        b.Text = tostring(i); b.TextColor3 = act and Color3.new(0,0,0) or Theme.TextPrimary
        b.Font = Enum.Font.GothamBold; b.TextSize = 12
        Instance.new("UICorner",b).CornerRadius = UDim.new(0,4)
        b.MouseButton1Click:Connect(function()
            Config.TpSettings.Speed = i
            SaveConfig()
            for idx, btn in ipairs(speedBtns) do
                local a = (idx == i)
                btn.BackgroundColor3 = a and Theme.Accent1 or Theme.SurfaceHighlight
                btn.TextColor3 = a and Color3.new(0,0,0) or Theme.TextPrimary
            end
            ShowNotification("AUTO SNIPE DELAY", string.format("%.2fs", getAutoSnipeDelayFromOption(i)))
        end)
        table.insert(speedBtns,b)
    end

    -- TP Floor precision inputs
    local function makeFloorInput(labelText, configKey, defaultVal, step)
        step = step or 0.01
        local row = CreateRow(labelText)

        local function clamp(v)
            v = tonumber(v)
            if not v then return Config.TpSettings[configKey] or defaultVal end
            return math.max(0.01, math.min(2.0, math.floor(v * 1000 + 0.5) / 1000))
        end

        local box = Instance.new("TextBox", row)
        box.Size = UDim2.new(0, 58, 0, 24)
        box.Position = UDim2.new(1, -120, 0.5, -12)
        box.BackgroundColor3 = Theme.SurfaceHighlight
        box.TextColor3 = Theme.TextPrimary
        box.Font = Enum.Font.GothamBold
        box.TextSize = 12
        box.Text = string.format("%.3f", Config.TpSettings[configKey] or defaultVal)
        box.ClearTextOnFocus = false
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)

        local bMinus = Instance.new("TextButton", row)
        bMinus.Size = UDim2.new(0, 26, 0, 24)
        bMinus.Position = UDim2.new(1, -180, 0.5, -12)
        bMinus.BackgroundColor3 = Theme.SurfaceHighlight
        bMinus.Text = "-"; bMinus.TextColor3 = Theme.TextPrimary
        bMinus.Font = Enum.Font.GothamBold; bMinus.TextSize = 14
        Instance.new("UICorner", bMinus).CornerRadius = UDim.new(0, 4)

        local bPlus = Instance.new("TextButton", row)
        bPlus.Size = UDim2.new(0, 26, 0, 24)
        bPlus.Position = UDim2.new(1, -56, 0.5, -12)
        bPlus.BackgroundColor3 = Theme.SurfaceHighlight
        bPlus.Text = "+"; bPlus.TextColor3 = Theme.TextPrimary
        bPlus.Font = Enum.Font.GothamBold; bPlus.TextSize = 14
        Instance.new("UICorner", bPlus).CornerRadius = UDim.new(0, 4)

        local function apply(newVal)
            newVal = clamp(newVal)
            Config.TpSettings[configKey] = newVal
            box.Text = string.format("%.3f", newVal)
            SaveConfig()
        end

        box.FocusLost:Connect(function()
            apply(tonumber(box.Text) or (Config.TpSettings[configKey] or defaultVal))
        end)
        bMinus.MouseButton1Click:Connect(function() apply((Config.TpSettings[configKey] or defaultVal) - step) end)
        bPlus.MouseButton1Click:Connect(function() apply((Config.TpSettings[configKey] or defaultVal) + step) end)
    end

    makeFloorInput("Floor 1 Walk Time", "Floor1WalkTime", 0.45)
    makeFloorInput("Floor 2 Wait Time", "Floor2WaitTime", 0.07)
    makeFloorInput("TP Speed", "TpSpeed", 0.10)

    _G.SetHazeUIPage("Keybinds")
    CreateSectionHeader("Teleport")
    local rBind = CreateRow("TP Keybind")
    local bBind = Instance.new("TextButton", rBind)
    bBind.Size=UDim2.new(0,60,0,24); bBind.Position=UDim2.new(1,-70,0.5,-12)
    bBind.BackgroundColor3=Theme.SurfaceHighlight; bBind.Text=PrettyKeyName(Config.TpSettings.TpKey)
    bBind.Font=Enum.Font.GothamBold; bBind.TextColor3=Theme.TextPrimary; bBind.TextSize=12
    Instance.new("UICorner",bBind).CornerRadius=UDim.new(0,4)
    bBind.MouseButton1Click:Connect(function()
        bBind.Text="..."; bBind.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.TpSettings.TpKey=NormalizeKeyName(inp.KeyCode.Name, Config.TpSettings.TpKey or "T"); Config.SavedKeybinds.TpKey = Config.TpSettings.TpKey; bBind.Text=PrettyKeyName(Config.TpSettings.TpKey)
                bBind.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("TP KEYBIND", PrettyKeyName(Config.TpSettings.TpKey))
            end
        end)
    end)

    local rBindClone = CreateRow("Auto Clone Keybind")
    local bBindClone = Instance.new("TextButton", rBindClone)
    bBindClone.Size=UDim2.new(0,60,0,24); bBindClone.Position=UDim2.new(1,-70,0.5,-12)
    bBindClone.BackgroundColor3=Theme.SurfaceHighlight; bBindClone.Text=PrettyKeyName(Config.TpSettings.CloneKey)
    bBindClone.Font=Enum.Font.GothamBold; bBindClone.TextColor3=Theme.TextPrimary; bBindClone.TextSize=12
    Instance.new("UICorner",bBindClone).CornerRadius=UDim.new(0,4)
    bBindClone.MouseButton1Click:Connect(function()
        bBindClone.Text="..."; bBindClone.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.TpSettings.CloneKey=NormalizeKeyName(inp.KeyCode.Name, Config.TpSettings.CloneKey or "V"); Config.SavedKeybinds.CloneKey = Config.TpSettings.CloneKey; bBindClone.Text=PrettyKeyName(Config.TpSettings.CloneKey)
                bBindClone.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("CLONE KEYBIND", PrettyKeyName(Config.TpSettings.CloneKey))
            end
        end)
    end)

    end
    do
    _G.SetHazeUIPage("Keybinds")
    CreateSectionHeader("Carpet Speed")
    local rCarpetBind = CreateRow("Carpet Speed Keybind")
    local bCarpet = Instance.new("TextButton", rCarpetBind)
    bCarpet.Size=UDim2.new(0,60,0,24); bCarpet.Position=UDim2.new(1,-70,0.5,-12)
    bCarpet.BackgroundColor3=Theme.SurfaceHighlight; bCarpet.Text=PrettyKeyName(Config.TpSettings.CarpetSpeedKey)
    bCarpet.Font=Enum.Font.GothamBold; bCarpet.TextColor3=Theme.TextPrimary; bCarpet.TextSize=12
    Instance.new("UICorner",bCarpet).CornerRadius=UDim.new(0,4)
    bCarpet.MouseButton1Click:Connect(function()
        bCarpet.Text="..."; bCarpet.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.TpSettings.CarpetSpeedKey=NormalizeKeyName(inp.KeyCode.Name, Config.TpSettings.CarpetSpeedKey or "Q"); Config.SavedKeybinds.CarpetSpeedKey = Config.TpSettings.CarpetSpeedKey; bCarpet.Text=PrettyKeyName(Config.TpSettings.CarpetSpeedKey)
                bCarpet.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("CARPET SPEED KEYBIND", PrettyKeyName(Config.TpSettings.CarpetSpeedKey))
            end
        end)
    end)

    local rRagdollSelf = CreateRow("Ragdoll Self Keybind")
    local bRagdollSelf = Instance.new("TextButton", rRagdollSelf)
    bRagdollSelf.Size=UDim2.new(0,60,0,24); bRagdollSelf.Position=UDim2.new(1,-70,0.5,-12)
    bRagdollSelf.BackgroundColor3=Theme.SurfaceHighlight; bRagdollSelf.Text=Config.RagdollSelfKey ~= "" and PrettyKeyName(Config.RagdollSelfKey) or "NONE"
    bRagdollSelf.Font=Enum.Font.GothamBold; bRagdollSelf.TextColor3=Theme.TextPrimary; bRagdollSelf.TextSize=12
    Instance.new("UICorner",bRagdollSelf).CornerRadius=UDim.new(0,4)
    bRagdollSelf.MouseButton1Click:Connect(function()
        bRagdollSelf.Text="..."; bRagdollSelf.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.RagdollSelfKey=NormalizeKeyName(inp.KeyCode.Name, ""); Config.SavedKeybinds.RagdollSelfKey = Config.RagdollSelfKey; bRagdollSelf.Text=Config.RagdollSelfKey ~= "" and PrettyKeyName(Config.RagdollSelfKey) or "NONE"
                bRagdollSelf.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("RAGDOLL SELF KEYBIND", Config.RagdollSelfKey ~= "" and PrettyKeyName(Config.RagdollSelfKey) or "NONE")
            end
        end)
    end)

    local rCarpetStatus = CreateRow("Carpet Speed Status")
    local carpetStatusLbl = Instance.new("TextLabel", rCarpetStatus)
    carpetStatusLbl.Size=UDim2.new(0,50,0,20); carpetStatusLbl.Position=UDim2.new(1,-60,0.5,-10)
    carpetStatusLbl.BackgroundTransparency=1
    carpetStatusLbl.Text=carpetSpeedEnabled and "ON" or "OFF"
    carpetStatusLbl.TextColor3=carpetSpeedEnabled and Theme.Success or Theme.Error
    carpetStatusLbl.Font=Enum.Font.GothamBlack; carpetStatusLbl.TextSize=13
    carpetStatusLbl.TextXAlignment=Enum.TextXAlignment.Right
    _carpetStatusLabel = carpetStatusLbl

    end
    do
    _G.SetHazeUIPage("Player")
    CreateSectionHeader("Movement")
    local rInfJump = CreateRow("Infinite Jump")
    CreateToggleSwitch(rInfJump, infiniteJumpEnabled, function(ns, set)
        set(ns); setInfiniteJump(ns)
        ShowNotification("INFINITE JUMP", ns and "ENABLED" or "DISABLED")
    end)
    local rAutoStealSpeed = CreateRow("Auto Steal Speed")
    CreateToggleSwitch(rAutoStealSpeed, Config.AutoStealSpeed, function(ns, set)
        set(ns); Config.AutoStealSpeed = ns; SaveConfig()
        ShowNotification("AUTO STEAL SPEED", ns and "ENABLED" or "DISABLED")
    end)
    local rFloat = CreateRow("Float")
    local floatToggleSwitch = CreateToggleSwitch(rFloat, State.floatActive, function(ns, set)
        set(ns)
        setFloatEnabled(ns, true)
        ShowNotification("FLOAT", ns and "ENABLED" or "DISABLED")
    end)
    floatToggleRef.setFn = function(enabled)
        if floatToggleSwitch and floatToggleSwitch.Set then
            floatToggleSwitch.Set(enabled, true, true)
        end
    end
    local rAutoResetBalloon = CreateRow("Auto reset on balloon")
    CreateToggleSwitch(rAutoResetBalloon, Config.AutoResetOnBalloon, function(ns, set)
        set(ns); Config.AutoResetOnBalloon = ns; SaveConfig()
        ShowNotification("AUTO RESET ON BALLOON", ns and "ENABLED" or "DISABLED")
    end)

    _G.SetHazeUIPage("Keybinds")
    CreateSectionHeader("Movement")
    local rStealSpeedKey = CreateRow("Steal Speed Keybind")
    local bStealSpeedKey = Instance.new("TextButton", rStealSpeedKey)
    bStealSpeedKey.Size=UDim2.new(0,60,0,24); bStealSpeedKey.Position=UDim2.new(1,-70,0.5,-12)
    bStealSpeedKey.BackgroundColor3=Theme.SurfaceHighlight; bStealSpeedKey.Text=PrettyKeyName(Config.StealSpeedKey)
    bStealSpeedKey.Font=Enum.Font.GothamBold; bStealSpeedKey.TextColor3=Theme.TextPrimary; bStealSpeedKey.TextSize=12
    Instance.new("UICorner",bStealSpeedKey).CornerRadius=UDim.new(0,4)
    bStealSpeedKey.MouseButton1Click:Connect(function()
        bStealSpeedKey.Text="..."; bStealSpeedKey.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.StealSpeedKey=NormalizeKeyName(inp.KeyCode.Name, Config.StealSpeedKey or "C"); Config.SavedKeybinds.StealSpeedKey = Config.StealSpeedKey; bStealSpeedKey.Text=PrettyKeyName(Config.StealSpeedKey)
                bStealSpeedKey.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("STEAL SPEED KEYBIND", PrettyKeyName(Config.StealSpeedKey))
            end
        end)
    end)

    local rFloatKeybind = CreateRow("Float Keybind")
    local bFloatKeybind = Instance.new("TextButton", rFloatKeybind)
    bFloatKeybind.Size=UDim2.new(0,60,0,24); bFloatKeybind.Position=UDim2.new(1,-70,0.5,-12)
    bFloatKeybind.BackgroundColor3=Theme.SurfaceHighlight; bFloatKeybind.Text=PrettyKeyName(Config.FloatKeybind or "Z")
    bFloatKeybind.Font=Enum.Font.GothamBold; bFloatKeybind.TextColor3=Theme.TextPrimary; bFloatKeybind.TextSize=12
    Instance.new("UICorner",bFloatKeybind).CornerRadius=UDim.new(0,4)
    bFloatKeybind.MouseButton1Click:Connect(function()
        bFloatKeybind.Text="..."; bFloatKeybind.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.FloatKeybind=NormalizeKeyName(inp.KeyCode.Name, Config.FloatKeybind or "Z"); Config.SavedKeybinds.FloatKeybind = Config.FloatKeybind; bFloatKeybind.Text=PrettyKeyName(Config.FloatKeybind)
                bFloatKeybind.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("FLOAT KEYBIND", PrettyKeyName(Config.FloatKeybind))
            end
        end)
    end)

    end
    do
    _G.SetHazeUIPage("Main")
    CreateSectionHeader("AUTO UNLOCK")
    local rAutoUnlock = CreateRow("Auto Unlock on Steal")
    CreateToggleSwitch(rAutoUnlock, Config.AutoUnlockOnSteal, function(ns, set)
        set(ns); Config.AutoUnlockOnSteal = ns; SaveConfig()
        ShowNotification("AUTO UNLOCK", ns and "ENABLED" or "DISABLED")
    end)

    _G.SetHazeUIPage("Misc")
    local rShowUnlockHUD = CreateRow("Show Unlock Buttons HUD")
    CreateToggleSwitch(rShowUnlockHUD, Config.ShowUnlockButtonsHUD, function(ns, set)
        set(ns); Config.ShowUnlockButtonsHUD = ns; SaveConfig()
        toggleUnlockBaseMenu(ns)
        ShowNotification("UNLOCK BUTTONS", ns and "VISIBLE" or "HIDDEN")
    end)

    local rShowMobileActions = CreateRow("Show Mobile Buttons")
    CreateToggleSwitch(rShowMobileActions, Config.ShowMobileActionButtons ~= false, function(ns, set)
        set(ns); Config.ShowMobileActionButtons = ns; SaveConfig()
        if SharedState.RefreshMobileActionButtons then
            SharedState.RefreshMobileActionButtons()
        end
        ShowNotification("MOBILE BUTTONS", ns and "VISIBLE" or "HIDDEN")
    end)
    end
    do
    _G.SetHazeUIPage("Player")
    CreateSectionHeader("ANTI-RAGDOLL")
    local arV1SetRef, arV2SetRef = {}, {}
    local rAr = CreateRow("V1")
    CreateToggleSwitch(rAr, Config.AntiRagdoll > 0, function(ns, set)
        arV1SetRef.fn = set
        if ns and Config.AntiRagdollV2 then
            set(false)
            ShowNotification("ANTI-RAGDOLL", "DISABLE V2 FIRST")
            return
        end
        set(ns)
        local mode = ns and 1 or 0
        Config.AntiRagdoll = mode
        if ns then
            Config.AntiRagdollV2 = false
            if arV2SetRef.fn then arV2SetRef.fn(false) end
        end
        SaveConfig()
        startAntiRagdoll(mode)
        if ns then startAntiRagdollV2(false) end
        ShowNotification("ANTI-RAGDOLL V1", ns and "ENABLED" or "DISABLED")
    end)
    local rArV2 = CreateRow("V2")
    CreateToggleSwitch(rArV2, Config.AntiRagdollV2, function(ns, set)
        arV2SetRef.fn = set
        if ns and Config.AntiRagdoll > 0 then
            set(false)
            ShowNotification("ANTI-RAGDOLL", "DISABLE V1 FIRST")
            return
        end
        set(ns)
        Config.AntiRagdollV2 = ns
        if ns then
            Config.AntiRagdoll = 0
            SaveConfig()
            if arV1SetRef.fn then arV1SetRef.fn(false) end
            startAntiRagdoll(0)
            startAntiRagdollV2(true)
        else
            SaveConfig()
            startAntiRagdollV2(false)
        end
        ShowNotification("ANTI-RAGDOLL V2", ns and "ENABLED" or "DISABLED")
    end)













    end

    -- Shared toggle refs for ESP systems

    do
    _G.SetHazeUIPage("Player")
    CreateSectionHeader("ESP")

    _G.SetHazeUIPage("Settings")
    playerESPToggleRef = playerESPToggleRef or {setFn=nil}
    _G.SetHazeUIPage("Player")
    local rPlayerEsp = CreateRow("Player ESP (Hides Names)")
    CreateToggleSwitch(rPlayerEsp, Config.PlayerESP, function(ns, set)
        set(ns); Config.PlayerESP = ns; SaveConfig()
        if playerESPToggleRef.setFn then playerESPToggleRef.setFn(ns) end
        ShowNotification("PLAYER ESP", ns and "ENABLED" or "DISABLED")
    end)

    espToggleRef = espToggleRef or {enabled=true, setFn=nil}
    local rEsp = CreateRow("Brainrot ESP")
    local espSettingsSwitch = CreateToggleSwitch(rEsp, Config.BrainrotESP, function(ns, set)
        set(ns); Config.BrainrotESP = ns; SaveConfig()
        if espToggleRef.setFn then espToggleRef.setFn(ns) end
        ShowNotification("BRAINROT ESP", ns and "ENABLED" or "DISABLED")
    end)
    timerESPToggleRef = timerESPToggleRef or {setFn=nil}
    local rTimerEsp = CreateRow("Timer ESP")
    CreateToggleSwitch(rTimerEsp, Config.TimerESP, function(ns, set)
        set(ns); Config.TimerESP = ns; SaveConfig()
        if timerESPToggleRef.setFn then timerESPToggleRef.setFn(ns) end
        ShowNotification("TIMER ESP", ns and "ENABLED" or "DISABLED")
    end)
    subspaceMineESPToggleRef = subspaceMineESPToggleRef or {setFn=nil}
    local rSubspaceMineEsp = CreateRow("Subspace Mine Esp")
    CreateToggleSwitch(rSubspaceMineEsp, Config.SubspaceMineESP, function(ns, set)
        set(ns); Config.SubspaceMineESP = ns; SaveConfig()
        if subspaceMineESPToggleRef.setFn then subspaceMineESPToggleRef.setFn(ns) end
        ShowNotification("SUBSPACE MINE ESP", ns and "ENABLED" or "DISABLED")
    end)

    end
    do
    _G.SetHazeUIPage("Main")
    CreateSectionHeader("AUTO STEAL DEFAULTS")
    local nearestToggleRef = {}
    local highestToggleRef = {}
    local priorityToggleRef = {}
    autoTPPriorityToggleRef = autoTPPriorityToggleRef or {setFn = nil}

    local rDefaultNearest = CreateRow("Default To Nearest")
    local nearestToggleSwitch = CreateToggleSwitch(rDefaultNearest, Config.DefaultToNearest, function(ns, set)
        if ns then
            Config.DefaultToNearest = true
            Config.DefaultToHighest = false
            Config.DefaultToPriority = false
            set(true)
            if highestToggleRef.setFn then highestToggleRef.setFn(false) end
            if priorityToggleRef.setFn then priorityToggleRef.setFn(false) end
            
            Config.AutoTPPriority = true
            if autoTPPriorityToggleRef and autoTPPriorityToggleRef.setFn then
                autoTPPriorityToggleRef.setFn(true)
            end
        else
            local otherDefaults = Config.DefaultToHighest or Config.DefaultToPriority
            if not otherDefaults then
                set(true)
                ShowNotification("DEFAULT MODE", "At least one default must be enabled")
                return
            end
            Config.DefaultToNearest = false
            set(false)
        end
        SaveConfig()
        ShowNotification("DEFAULT TO NEAREST", ns and "ENABLED" or "DISABLED")
    end)
    nearestToggleRef.setFn = nearestToggleSwitch.Set

    local rDefaultHighest = CreateRow("Default To Highest")
    local highestToggleSwitch = CreateToggleSwitch(rDefaultHighest, Config.DefaultToHighest, function(ns, set)
        if ns then
            Config.DefaultToNearest = false
            Config.DefaultToHighest = true
            Config.DefaultToPriority = false
            set(true)
            if nearestToggleRef.setFn then nearestToggleRef.setFn(false) end
            if priorityToggleRef.setFn then priorityToggleRef.setFn(false) end
            
            Config.AutoTPPriority = false
            if autoTPPriorityToggleRef and autoTPPriorityToggleRef.setFn then
                autoTPPriorityToggleRef.setFn(false)
            end
        else
            local otherDefaults = Config.DefaultToNearest or Config.DefaultToPriority
            if not otherDefaults then
                set(true)
                ShowNotification("DEFAULT MODE", "At least one default must be enabled")
                return
            end
            Config.DefaultToHighest = false
            set(false)
        end
        SaveConfig()
        ShowNotification("DEFAULT TO HIGHEST", ns and "ENABLED" or "DISABLED")
    end)
    highestToggleRef.setFn = highestToggleSwitch.Set

    local rDefaultPriority = CreateRow("Default To Priority")
    local priorityToggleSwitch = CreateToggleSwitch(rDefaultPriority, Config.DefaultToPriority, function(ns, set)
        if ns then
            Config.DefaultToNearest = false
            Config.DefaultToHighest = false
            Config.DefaultToPriority = true
            set(true)
            if nearestToggleRef.setFn then nearestToggleRef.setFn(false) end
            if highestToggleRef.setFn then highestToggleRef.setFn(false) end
            
            Config.AutoTPPriority = true
            if autoTPPriorityToggleRef and autoTPPriorityToggleRef.setFn then
                autoTPPriorityToggleRef.setFn(true)
            end
        else
            local otherDefaults = Config.DefaultToNearest or Config.DefaultToHighest
            if not otherDefaults then
                set(true)
                ShowNotification("DEFAULT MODE", "At least one default must be enabled")
                return
            end
            Config.DefaultToPriority = false
            set(false)
        end
        SaveConfig()
        ShowNotification("DEFAULT TO PRIORITY", ns and "ENABLED" or "DISABLED")
    end)
    priorityToggleRef.setFn = priorityToggleSwitch.Set

    end
    do
    _G.SetHazeUIPage("Main")
    CreateSectionHeader("AUTOMATION")
    local rAutoInvis = CreateRow("Auto Invis During Steal")
    local autoInvisDuringStealToggleSwitch = CreateToggleSwitch(rAutoInvis, Config.AutoInvisDuringSteal, function(ns, set)
        set(ns)
        Config.AutoInvisDuringSteal = ns
        _G.AutoInvisDuringSteal = ns
        if _G.syncMiniInvisAutoStealToggle then
            pcall(_G.syncMiniInvisAutoStealToggle, ns)
        end
        SaveConfig()
        ShowNotification("AUTO INVIS", ns and "ENABLED" or "DISABLED")
    end)
    _G.syncMainAutoInvisToggle = autoInvisDuringStealToggleSwitch.Set
    _G.SetHazeUIPage("Main")
    local rAutoTpFail = CreateRow("Auto TP on Failed Steal")
    CreateToggleSwitch(rAutoTpFail, Config.AutoTpOnFailedSteal, function(ns, set)
        set(ns); Config.AutoTpOnFailedSteal = ns; SaveConfig()
        ShowNotification("AUTO TP ON FAILED STEAL", ns and "ENABLED" or "DISABLED")
    end)
    local rAutoTpPriority = CreateRow("Auto TP Priority Mode")
    local autoTPPriorityToggleSwitch = CreateToggleSwitch(rAutoTpPriority, Config.AutoTPPriority, function(ns, set)
        set(ns); Config.AutoTPPriority = ns; SaveConfig()
        ShowNotification("AUTO TP PRIORITY", ns and "PRIORITY" or "HIGHEST")
    end)
    autoTPPriorityToggleRef.setFn = autoTPPriorityToggleSwitch.Set
    local rAutoKick = CreateRow("Auto-Kick on Steal")
    CreateToggleSwitch(rAutoKick, Config.AutoKickOnSteal, function(ns, set)
        set(ns); Config.AutoKickOnSteal = ns; SaveConfig()
        ShowNotification("AUTO-KICK ON STEAL", ns and "ENABLED" or "DISABLED")
    end)

    end
    do
    _G.SetHazeUIPage("Misc")
    CreateSectionHeader("Hide GUIs")
    local rHideAdminPanel = CreateRow("Hide Admin Panel GUI")
    CreateToggleSwitch(rHideAdminPanel, Config.HideAdminPanel, function(ns, set)
        set(ns); Config.HideAdminPanel = ns; SaveConfig()
        local adUI = PlayerGui:FindFirstChild("XiAdminPanel")
        if adUI then adUI.Enabled = not ns end
        ShowNotification("HIDE ADMIN PANEL", ns and "ENABLED" or "DISABLED")
    end)
    local rHideAutoSteal = CreateRow("Hide Auto Steal GUI")
    CreateToggleSwitch(rHideAutoSteal, Config.HideAutoSteal, function(ns, set)
        set(ns); Config.HideAutoSteal = ns; SaveConfig()
        local asUI = PlayerGui:FindFirstChild("AutoStealUI")
        if asUI then asUI.Enabled = not ns end
        ShowNotification("HIDE AUTO STEAL", ns and "ENABLED" or "DISABLED")
    end)
    local rCompactAutoSteal = CreateRow("Compact Auto Steal GUI")
    CreateToggleSwitch(rCompactAutoSteal, Config.CompactAutoSteal, function(ns, set)
        set(ns); Config.CompactAutoSteal = ns; SaveConfig()
        local asUI = PlayerGui:FindFirstChild("AutoStealUI")
        if asUI and asUI:FindFirstChild("Frame") then
            local frame = asUI.Frame
            local mobileScale = IS_MOBILE and 0.6 or 1
            local targetHeight = ns and (5 * 44 + 135) or (630 * mobileScale)
            
            local tween = TweenService:Create(
                frame,
                TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
                {Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, targetHeight)}
            )
            tween:Play()
            
            tween.Completed:Connect(function()
                SharedState.ListNeedsRedraw = true
                if SharedState.UpdateAutoStealUI then
                    SharedState.UpdateAutoStealUI()
                end
            end)
        end
        ShowNotification("COMPACT AUTO STEAL", ns and "ENABLED" or "DISABLED")
    end)

    end
    do
    _G.SetHazeUIPage("Settings")
    CreateSectionHeader("EXTRAS")   

    _G.SetHazeUIPage("Keybinds")
    local rResetKey = CreateRow("Reset")
    local bResetKey = Instance.new("TextButton", rResetKey)
    bResetKey.Size=UDim2.new(0,60,0,24); bResetKey.Position=UDim2.new(1,-70,0.5,-12)
    bResetKey.BackgroundColor3=Theme.SurfaceHighlight; bResetKey.Text=PrettyKeyName(Config.ResetKey)
    bResetKey.Font=Enum.Font.GothamBold; bResetKey.TextColor3=Theme.TextPrimary; bResetKey.TextSize=12
    Instance.new("UICorner",bResetKey).CornerRadius=UDim.new(0,4)
    bResetKey.MouseButton1Click:Connect(function()
        bResetKey.Text="..."; bResetKey.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.ResetKey=NormalizeKeyName(inp.KeyCode.Name, Config.ResetKey or "X"); Config.SavedKeybinds.ResetKey = Config.ResetKey; bResetKey.Text=PrettyKeyName(Config.ResetKey)
                bResetKey.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("RESET KEYBIND", PrettyKeyName(Config.ResetKey))
            end
        end)
    end)

    _G.SetHazeUIPage("Keybinds")
    CreateSectionHeader("Extras")
    local rKickKey = CreateRow("Kick")
    local bKickKey = Instance.new("TextButton", rKickKey)
    bKickKey.Size=UDim2.new(0,60,0,24); bKickKey.Position=UDim2.new(1,-70,0.5,-12)
    bKickKey.BackgroundColor3=Theme.SurfaceHighlight; bKickKey.Text=Config.KickKey ~= "" and PrettyKeyName(Config.KickKey) or "NONE"
    bKickKey.Font=Enum.Font.GothamBold; bKickKey.TextColor3=Theme.TextPrimary; bKickKey.TextSize=12
    Instance.new("UICorner",bKickKey).CornerRadius=UDim.new(0,4)
    bKickKey.MouseButton1Click:Connect(function()
        bKickKey.Text="..."; bKickKey.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.KickKey=NormalizeKeyName(inp.KeyCode.Name, ""); Config.SavedKeybinds.KickKey = Config.KickKey; bKickKey.Text=Config.KickKey ~= "" and PrettyKeyName(Config.KickKey) or "NONE"
                bKickKey.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("KICK KEYBIND", Config.KickKey ~= "" and PrettyKeyName(Config.KickKey) or "NONE")
            end
        end)
    end)

    _G.SetHazeUIPage("Misc")
    local rCleanErrors = CreateRow("Clean Error GUIs")
    CreateToggleSwitch(rCleanErrors, Config.CleanErrorGUIs, function(ns, set)
        set(ns); Config.CleanErrorGUIs = ns; SaveConfig()
        ShowNotification("CLEAN ERROR GUIS", ns and "ENABLED" or "DISABLED")
    end)


    end
    do
    _G.SetHazeUIPage("Misc")
    CreateSectionHeader("Admin Panel")
    local rClickToAP = CreateRow("Click To Admin Panel")
    CreateToggleSwitch(rClickToAP, Config.ClickToAP, function(ns, set)
        set(ns); Config.ClickToAP = ns; SaveConfig()
        ShowNotification("CLICK TO AP", ns and "ENABLED" or "DISABLED")
    end)
    local rClickToAPSingle = CreateRow("Click To AP Single Command")
    CreateToggleSwitch(rClickToAPSingle, Config.ClickToAPSingleCommand, function(ns, set)
        set(ns); Config.ClickToAPSingleCommand = ns; SaveConfig()
        ShowNotification("CLICK TO AP SINGLE", ns and "ENABLED" or "DISABLED")
    end)

    CreateSubHeader("Moby")
    local rDisableClickToAPOnMoby = CreateRow("Disable Click To AP On Moby")
    CreateToggleSwitch(rDisableClickToAPOnMoby, Config.DisableClickToAPOnMoby, function(ns, set)
        set(ns); Config.DisableClickToAPOnMoby = ns; SaveConfig()
        ShowNotification("DISABLE CLICK TO AP ON MOBY", ns and "ENABLED" or "DISABLED")
    end)
    local rDisableProximitySpamOnMoby = CreateRow("Disable Proximity AP On Moby")
    CreateToggleSwitch(rDisableProximitySpamOnMoby, Config.DisableProximitySpamOnMoby, function(ns, set)
        set(ns); Config.DisableProximitySpamOnMoby = ns; SaveConfig()
        ShowNotification("DISABLE PROXIMITY AP ON MOBY", ns and "ENABLED" or "DISABLED")
    end)
    local rCancelAPPanelOnMoby = CreateRow("Cancel AP Panel on Moby")
    CreateToggleSwitch(rCancelAPPanelOnMoby, Config.CancelAPPanelOnMoby, function(ns, set)
        set(ns); Config.CancelAPPanelOnMoby = ns; SaveConfig()
        ShowNotification("CANCEL AP PANEL ON MOBY", ns and "ENABLED" or "DISABLED")
    end)

    CreateSubHeader("Kawaifu")
    local rDisableClickToAPOnKawaifu = CreateRow("Disable Click To AP On Kawaifu")
    CreateToggleSwitch(rDisableClickToAPOnKawaifu, Config.DisableClickToAPOnKawaifu, function(ns, set)
        set(ns); Config.DisableClickToAPOnKawaifu = ns; SaveConfig()
        ShowNotification("DISABLE CLICK TO AP ON KAWAIFU", ns and "ENABLED" or "DISABLED")
    end)
    local rDisableProximitySpamOnKawaifu = CreateRow("Disable Proximity AP On Kawaifu")
    CreateToggleSwitch(rDisableProximitySpamOnKawaifu, Config.DisableProximitySpamOnKawaifu, function(ns, set)
        set(ns); Config.DisableProximitySpamOnKawaifu = ns; SaveConfig()
        ShowNotification("DISABLE PROXIMITY AP ON KAWAIFU", ns and "ENABLED" or "DISABLED")
    end)
    local rCancelAPPanelOnKawaifu = CreateRow("Cancel AP Panel on Kawaifu")
    CreateToggleSwitch(rCancelAPPanelOnKawaifu, Config.CancelAPPanelOnKawaifu, function(ns, set)
        set(ns); Config.CancelAPPanelOnKawaifu = ns; SaveConfig()
        ShowNotification("CANCEL AP PANEL ON KAWAIFU", ns and "ENABLED" or "DISABLED")
    end)
    _G.SetHazeUIPage("Keybinds")
    CreateSectionHeader("Admin Panel")
    local rClickToAPKeybind = CreateRow("Click To AP Keybind")
    local bClickToAPKeybind = Instance.new("TextButton", rClickToAPKeybind)
    bClickToAPKeybind.Size=UDim2.new(0,60,0,24); bClickToAPKeybind.Position=UDim2.new(1,-65,0.5,-12)
    bClickToAPKeybind.BackgroundColor3=Theme.SurfaceHighlight; bClickToAPKeybind.Text=PrettyKeyName(Config.ClickToAPKeybind or "L")
    bClickToAPKeybind.Font=Enum.Font.GothamBold; bClickToAPKeybind.TextColor3=Theme.TextPrimary; bClickToAPKeybind.TextSize=12
    Instance.new("UICorner",bClickToAPKeybind).CornerRadius=UDim.new(0,4)
    bClickToAPKeybind.MouseButton1Click:Connect(function()
        bClickToAPKeybind.Text="..."; bClickToAPKeybind.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.ClickToAPKeybind=NormalizeKeyName(inp.KeyCode.Name, Config.ClickToAPKeybind or "L"); Config.SavedKeybinds.ClickToAPKeybind = Config.ClickToAPKeybind; bClickToAPKeybind.Text=PrettyKeyName(Config.ClickToAPKeybind)
                bClickToAPKeybind.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("CLICK TO AP KEYBIND", PrettyKeyName(Config.ClickToAPKeybind))
            end
        end)
    end)
    local rProximityAPKeybind = CreateRow("Proximity AP Keybind")
    local bProximityAPKeybind = Instance.new("TextButton", rProximityAPKeybind)
    bProximityAPKeybind.Size=UDim2.new(0,60,0,24); bProximityAPKeybind.Position=UDim2.new(1,-70,0.5,-12)
    bProximityAPKeybind.BackgroundColor3=Theme.SurfaceHighlight; bProximityAPKeybind.Text=PrettyKeyName(Config.ProximityAPKeybind or "P")
    bProximityAPKeybind.Font=Enum.Font.GothamBold; bProximityAPKeybind.TextColor3=Theme.TextPrimary; bProximityAPKeybind.TextSize=12
    Instance.new("UICorner",bProximityAPKeybind).CornerRadius=UDim.new(0,4)
    bProximityAPKeybind.MouseButton1Click:Connect(function()
        bProximityAPKeybind.Text="..."; bProximityAPKeybind.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.ProximityAPKeybind=NormalizeKeyName(inp.KeyCode.Name, Config.ProximityAPKeybind or "P"); Config.SavedKeybinds.ProximityAPKeybind = Config.ProximityAPKeybind; bProximityAPKeybind.Text=PrettyKeyName(Config.ProximityAPKeybind)
                bProximityAPKeybind.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("PROXIMITY AP KEYBIND", PrettyKeyName(Config.ProximityAPKeybind))
            end
        end)
    end)

    end
    do
    _G.SetHazeUIPage("Settings")
    CreateSectionHeader("ALERTS")
    local rAlertsEnabled = CreateRow("Enable Alerts")
    CreateToggleSwitch(rAlertsEnabled, Config.AlertsEnabled, function(ns, set)
        set(ns); Config.AlertsEnabled = ns; SaveConfig()
        ShowNotification("PRIORITY ALERTS", ns and "ENABLED" or "DISABLED")
    end)
    local rAlertSound = CreateRow("Alert Sound ID")
    local soundBox = Instance.new("TextBox", rAlertSound)
    soundBox.Size = UDim2.new(0, 180, 0, 24)
    soundBox.Position = UDim2.new(1, -185, 0.5, -12)
    soundBox.BackgroundColor3 = Theme.SurfaceHighlight
    soundBox.Text = Config.AlertSoundID or "rbxassetid://6518811702"
    soundBox.Font = Enum.Font.Gotham
    soundBox.TextSize = 10
    soundBox.TextColor3 = Theme.TextPrimary
    soundBox.PlaceholderText = "Sound ID"
    Instance.new("UICorner", soundBox).CornerRadius = UDim.new(0, 4)
    soundBox.FocusLost:Connect(function()
        Config.AlertSoundID = soundBox.Text
        SaveConfig()
        ShowNotification("ALERT SOUND", "Updated")
    end)

    end
    do
    _G.SetHazeUIPage("Settings")
    CreateSectionHeader("JOB JOINER")
    local rJoinerRow = CreateRow("Job ID Joiner")
    CreateToggleSwitch(rJoinerRow, Config.ShowJobJoiner, function(ns, set)
        set(ns); Config.ShowJobJoiner = ns; SaveConfig()
        local gui = PlayerGui:FindFirstChild("XiJobJoiner")
        if gui then gui.Enabled = Config.ShowJobJoiner end
        ShowNotification("JOB ID JOINER", ns and "ENABLED" or "DISABLED")
    end)
    _G.SetHazeUIPage("Keybinds")
    CreateSectionHeader("Job Joiner")
    local rJoinerKey = CreateRow("Job Joiner Keybind")
    local bJoinerKey = Instance.new("TextButton", rJoinerKey)
    bJoinerKey.Size=UDim2.new(0,60,0,24); bJoinerKey.Position=UDim2.new(1,-70,0.5,-12)
    bJoinerKey.BackgroundColor3=Theme.SurfaceHighlight; bJoinerKey.Text=PrettyKeyName(Config.JobJoinerKey or "J")
    bJoinerKey.Font=Enum.Font.GothamBold; bJoinerKey.TextColor3=Theme.TextPrimary; bJoinerKey.TextSize=12
    Instance.new("UICorner",bJoinerKey).CornerRadius=UDim.new(0,4)
    bJoinerKey.MouseButton1Click:Connect(function()
        bJoinerKey.Text="..."; bJoinerKey.TextColor3=Theme.Accent1
        local con; con=UserInputService.InputBegan:Connect(function(inp)
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                Config.JobJoinerKey=NormalizeKeyName(inp.KeyCode.Name, Config.JobJoinerKey or "J"); Config.SavedKeybinds.JobJoinerKey = Config.JobJoinerKey; bJoinerKey.Text=PrettyKeyName(Config.JobJoinerKey)
                bJoinerKey.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                ShowNotification("JOB JOINER KEYBIND", PrettyKeyName(Config.JobJoinerKey))
            end
        end)
    end)

    end
    do
    _G.SetHazeUIPage("Player")
    CreateSectionHeader("Protection")
    local rAntiBeeDisco = CreateRow("Anti-Bee & Anti-Disco")
    CreateToggleSwitch(rAntiBeeDisco, Config.AntiBeeDisco, function(ns, set)
        set(ns); Config.AntiBeeDisco = ns; SaveConfig()
        if ns then
            if _G.ANTI_BEE_DISCO and _G.ANTI_BEE_DISCO.Enable then
                _G.ANTI_BEE_DISCO.Enable()
            end
        else
            if _G.ANTI_BEE_DISCO and _G.ANTI_BEE_DISCO.Disable then
                _G.ANTI_BEE_DISCO.Disable()
            end
        end
        ShowNotification("ANTI-BEE & DISCO", ns and "ENABLED" or "DISABLED")
    end)

    local rAutoDestroyTurrets = CreateRow("Auto-Destroy Turrets")
    CreateToggleSwitch(rAutoDestroyTurrets, Config.AutoDestroyTurrets, function(ns, set)
        set(ns); Config.AutoDestroyTurrets = ns; SaveConfig()
        ShowNotification("AUTO-DESTROY TURRETS", ns and "ENABLED" or "DISABLED")
    end)

    end
    do
    _G.SetHazeUIPage("Settings")
    CreateSectionHeader("CAMERA")
    local rFOV = CreateRow("FOV")
    local fovSliderBg = Instance.new("Frame", rFOV)
    fovSliderBg.Size = UDim2.new(0, 140, 0, 5)
    fovSliderBg.Position = UDim2.new(1, -200, 0.5, -2.5)
    fovSliderBg.BackgroundColor3 = Color3.fromRGB(30, 32, 38)
    Instance.new("UICorner", fovSliderBg).CornerRadius = UDim.new(1, 0)
    local fovFill = Instance.new("Frame", fovSliderBg)
    fovFill.BackgroundColor3 = Theme.Accent1
    fovFill.Size = UDim2.new(0, 0, 1, 0)
    Instance.new("UICorner", fovFill).CornerRadius = UDim.new(1, 0)
    local fovKnob = Instance.new("Frame", fovSliderBg)
    fovKnob.Size = UDim2.new(0, 12, 0, 12)
    fovKnob.BackgroundColor3 = Theme.TextPrimary
    fovKnob.AnchorPoint = Vector2.new(0.5, 0.5)
    fovKnob.Position = UDim2.new(0, 0, 0.5, 0)
    Instance.new("UICorner", fovKnob).CornerRadius = UDim.new(1, 0)
    local fovKnobStroke = Instance.new("UIStroke", fovKnob)
    fovKnobStroke.Color = Theme.Accent1
    fovKnobStroke.Thickness = 1.5
    fovKnobStroke.Transparency = 0.2
    local fovValLbl = Instance.new("TextLabel", rFOV)
    fovValLbl.Size = UDim2.new(0, 40, 0, 20)
    fovValLbl.Position = UDim2.new(1, -50, 0.5, -10)
    fovValLbl.BackgroundTransparency = 1
    fovValLbl.Text = string.format("%.1f", Config.FOV)
    fovValLbl.TextColor3 = Theme.TextPrimary
    fovValLbl.Font = Enum.Font.GothamBold
    fovValLbl.TextSize = 13

    local function updateFOVSlider(val)
        val = math.clamp(val, 30, 180)
        Config.FOV = val
        SaveConfig()
        fovValLbl.Text = string.format("%.1f", val)
        local pct = (val - 30) / 150
        fovFill.Size = UDim2.new(pct, 0, 1, 0)
        fovKnob.Position = UDim2.new(pct, 0, 0.5, 0)
        if Workspace.CurrentCamera then
            Workspace.CurrentCamera.FieldOfView = val
        end
        ShowNotification("FIELD OF VIEW", string.format("%.1f", val))
    end
    updateFOVSlider(Config.FOV)

    local fovDragging = false
    fovSliderBg.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then fovDragging = true end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then fovDragging = false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if fovDragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local x = i.Position.X
            local r = fovSliderBg.AbsolutePosition.X
            local w = fovSliderBg.AbsoluteSize.X
            local p = (x - r) / w
            updateFOVSlider(30 + (p * 150))
        end
    end)

    local rFOVReset = CreateRow("Reset FOV")
    local bFOVReset = Instance.new("TextButton", rFOVReset)
    bFOVReset.Size = UDim2.new(0, 60, 0, 24)
    bFOVReset.Position = UDim2.new(1, -70, 0.5, -12)
    bFOVReset.BackgroundColor3 = Theme.SurfaceHighlight
    bFOVReset.Text = "Reset"
    bFOVReset.Font = Enum.Font.GothamBold
    bFOVReset.TextColor3 = Theme.TextPrimary
    bFOVReset.TextSize = 12
    Instance.new("UICorner", bFOVReset).CornerRadius = UDim.new(0, 4)
    bFOVReset.MouseButton1Click:Connect(function()
        updateFOVSlider(70)
        ShowNotification("FIELD OF VIEW", "Reset to 70")
    end)

    end
    do
    _G.SetHazeUIPage("Keybinds")
    CreateSectionHeader("Menu")
    Config.MenuKey = NormalizeKeyName((Config.SavedKeybinds and Config.SavedKeybinds.MenuKey) or Config.MenuKey, "LeftControl")
    if not IS_MOBILE then
        local rMenu = CreateRow("Menu Toggle Key")
        local bMenu = Instance.new("TextButton", rMenu)
        bMenu.Size=UDim2.new(0,80,0,24); bMenu.Position=UDim2.new(1,-90,0.5,-12)
        bMenu.BackgroundColor3=Theme.SurfaceHighlight; bMenu.Text=PrettyKeyName(Config.MenuKey or "LeftControl")
        bMenu.Font=Enum.Font.GothamBold; bMenu.TextColor3=Theme.TextPrimary; bMenu.TextSize=12
        Instance.new("UICorner",bMenu).CornerRadius=UDim.new(0,4)
        bMenu.MouseButton1Click:Connect(function()
            bMenu.Text="..."; bMenu.TextColor3=Theme.Accent1
            local con; con=UserInputService.InputBegan:Connect(function(inp)
                if inp.UserInputType==Enum.UserInputType.Keyboard then
                    Config.MenuKey=NormalizeKeyName(inp.KeyCode.Name, Config.MenuKey or "LeftControl"); Config.SavedKeybinds.MenuKey = Config.MenuKey; bMenu.Text=PrettyKeyName(Config.MenuKey)
                    bMenu.TextColor3=Theme.TextPrimary; SaveConfig(); con:Disconnect()
                    ShowNotification("MENU KEYBIND", PrettyKeyName(Config.MenuKey))
                end
            end)
        end)
    else
        _G.SetHazeUIPage("Settings")
    CreatePageHeader("Settings")
        CreateRow("Menu Toggle: Touch Icon")
    end

    end
    do
    _G.SetHazeUIPage("Settings")
    CreateSectionHeader("UI CONTROLS")
    local rLock = CreateRow("Lock UI Dragging")
    CreateToggleSwitch(rLock, Config.UILocked, function(ns, set)
        set(ns); Config.UILocked = ns; SaveConfig()
        ShowNotification("UI LOCK", ns and "ENABLED" or "DISABLED")
    end)

    if IS_MOBILE then
        local scaleUI = {}
        scaleUI.row = CreateRow("Mobile GUI Scale")
        scaleUI.bg = Instance.new("Frame", scaleUI.row)
        scaleUI.bg.Size = UDim2.new(0, 140, 0, 5)
        scaleUI.bg.Position = UDim2.new(1, -200, 0.5, -2.5)
        scaleUI.bg.BackgroundColor3 = Color3.fromRGB(30, 32, 38)
        Instance.new("UICorner", scaleUI.bg).CornerRadius = UDim.new(1, 0)
        scaleUI.fill = Instance.new("Frame", scaleUI.bg)
        scaleUI.fill.BackgroundColor3 = Theme.Accent1
        scaleUI.fill.BorderSizePixel = 0
        scaleUI.fill.Size = UDim2.new(0, 0, 1, 0)
        Instance.new("UICorner", scaleUI.fill).CornerRadius = UDim.new(1, 0)
        scaleUI.knob = Instance.new("Frame", scaleUI.bg)
        scaleUI.knob.Size = UDim2.new(0, 14, 0, 14)
        scaleUI.knob.AnchorPoint = Vector2.new(0.5, 0.5)
        scaleUI.knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        scaleUI.knob.BorderSizePixel = 0
        Instance.new("UICorner", scaleUI.knob).CornerRadius = UDim.new(1, 0)
        scaleUI.stroke = Instance.new("UIStroke", scaleUI.knob)
        scaleUI.stroke.Color = Theme.Accent1
        scaleUI.stroke.Thickness = 2
        scaleUI.readout = Instance.new("TextLabel", scaleUI.row)
        scaleUI.readout.Size = UDim2.new(0, 50, 0, 20)
        scaleUI.readout.Position = UDim2.new(1, -145, 0.5, -10)
        scaleUI.readout.BackgroundTransparency = 1
        scaleUI.readout.Text = string.format("%.1f", Config.MobileGuiScale or 0.5)
        scaleUI.readout.Font = Enum.Font.GothamBold
        scaleUI.readout.TextSize = 11
        scaleUI.readout.TextColor3 = Theme.Accent1
        scaleUI.readout.TextXAlignment = Enum.TextXAlignment.Right
        scaleUI.dragging = false
        scaleUI.min = 0.1
        scaleUI.max = 1.0
        scaleUI.scaleToT = function(s)
            return math.clamp((s - scaleUI.min) / (scaleUI.max - scaleUI.min), 0, 1)
        end
        scaleUI.updateScaleSlider = function(val)
            local c = math.clamp(val, scaleUI.min, scaleUI.max)
            Config.MobileGuiScale = c
            SaveConfig()
            scaleUI.fill.Size = UDim2.new(scaleUI.scaleToT(c), 0, 1, 0)
            scaleUI.knob.Position = UDim2.new(0, scaleUI.scaleToT(c) * scaleUI.bg.AbsoluteSize.X, 0.5, 0)
            scaleUI.readout.Text = string.format("%.2f", c)
            if SharedState.RefreshMobileScale then SharedState.RefreshMobileScale() end
        end
        task.defer(function() scaleUI.updateScaleSlider(Config.MobileGuiScale or 0.5) end)
        scaleUI.onScaleInput = function(pos)
            scaleUI.updateScaleSlider(scaleUI.min + math.clamp((pos.X - scaleUI.bg.AbsolutePosition.X) / scaleUI.bg.AbsoluteSize.X, 0, 1) * (scaleUI.max - scaleUI.min))
        end
        scaleUI.bg.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                scaleUI.dragging = true
                scaleUI.onScaleInput(inp.Position)
            end
        end)
        scaleUI.knob.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                scaleUI.dragging = true
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                scaleUI.dragging = false
            end
        end)
        UserInputService.InputChanged:Connect(function(inp)
            if scaleUI.dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                scaleUI.onScaleInput(inp.Position)
            end
        end)
    end

    local rReset = CreateRow("Reset UI Positions")
    local bReset = Instance.new("TextButton", rReset)
    bReset.Size=UDim2.new(0,80,0,24); bReset.Position=UDim2.new(1,-90,0.5,-12)
    bReset.BackgroundColor3=Theme.Error; bReset.Text="RESET"
    bReset.Font=Enum.Font.GothamBold; bReset.TextColor3=Theme.TextPrimary; bReset.TextSize=12
    Instance.new("UICorner",bReset).CornerRadius=UDim.new(0,4)
    bReset.MouseButton1Click:Connect(function()
        Config.Positions = DeepCopy(DefaultConfig.Positions)
        SaveConfig()
        ShowNotification("UI RESET", "Positions restored")
        sFrame.Position = UDim2.new(
            DefaultConfig.Positions.Settings.X,
            DefaultConfig.Positions.Settings.OffsetX or 0,
            DefaultConfig.Positions.Settings.Y,
            DefaultConfig.Positions.Settings.OffsetY or 0
        )
        if PlayerGui:FindFirstChild("AutoStealUI") and PlayerGui.AutoStealUI:FindFirstChild("Frame") then
            PlayerGui.AutoStealUI.Frame.Position = UDim2.new(
                DefaultConfig.Positions.AutoSteal.X,
                DefaultConfig.Positions.AutoSteal.OffsetX or 0,
                DefaultConfig.Positions.AutoSteal.Y,
                DefaultConfig.Positions.AutoSteal.OffsetY or 0
            )
        end
        if PlayerGui:FindFirstChild("XiAdminPanel") and PlayerGui.XiAdminPanel:FindFirstChild("Frame") then
            PlayerGui.XiAdminPanel.Frame.Position = UDim2.new(
                DefaultConfig.Positions.AdminPanel.X,
                DefaultConfig.Positions.AdminPanel.OffsetX or 0,
                DefaultConfig.Positions.AdminPanel.Y,
                DefaultConfig.Positions.AdminPanel.OffsetY or 0
            )
        end
        if PlayerGui:FindFirstChild("XiInvisPanel") and PlayerGui.XiInvisPanel:FindFirstChild("Frame") then
            PlayerGui.XiInvisPanel.Frame.Position = UDim2.new(
                DefaultConfig.Positions.InvisPanel.X,
                DefaultConfig.Positions.InvisPanel.OffsetX or 0,
                DefaultConfig.Positions.InvisPanel.Y,
                DefaultConfig.Positions.InvisPanel.OffsetY or 0
            )
        end
        if PlayerGui:FindFirstChild("AutoStealTargetControls") and PlayerGui.AutoStealTargetControls:FindFirstChild("TargetControlsFrame") then
            PlayerGui.AutoStealTargetControls.TargetControlsFrame.Position = UDim2.new(
                DefaultConfig.Positions.TargetControls.X,
                DefaultConfig.Positions.TargetControls.OffsetX or 0,
                DefaultConfig.Positions.TargetControls.Y,
                DefaultConfig.Positions.TargetControls.OffsetY or 0
            )
        end
        ShowNotification("UI RESET", "Positions restored to default")
    end)

    do
    _G.SetHazeUIPage("Teleport")

    local function makeNumInput(parent, label, getVal, setVal, minVal, maxVal, step, fmt)
        fmt  = fmt  or "%.0f"
        step = step or 1
        local row = CreateRow(label)
        local box = Instance.new("TextBox", row)
        box.Size = UDim2.new(0, 72, 0, 24)
        box.Position = UDim2.new(1, -130, 0.5, -12)
        box.BackgroundColor3 = Theme.SurfaceHighlight
        box.TextColor3 = Theme.TextPrimary
        box.Font = Enum.Font.GothamBold
        box.TextSize = 12
        box.Text = string.format(fmt, getVal())
        box.ClearTextOnFocus = false
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)

        local bMinus = Instance.new("TextButton", row)
        bMinus.Size = UDim2.new(0, 26, 0, 24)
        bMinus.Position = UDim2.new(1, -188, 0.5, -12)
        bMinus.BackgroundColor3 = Theme.SurfaceHighlight
        bMinus.Text = "-"; bMinus.TextColor3 = Theme.TextPrimary
        bMinus.Font = Enum.Font.GothamBold; bMinus.TextSize = 14
        Instance.new("UICorner", bMinus).CornerRadius = UDim.new(0, 4)

        local bPlus = Instance.new("TextButton", row)
        bPlus.Size = UDim2.new(0, 26, 0, 24)
        bPlus.Position = UDim2.new(1, -56, 0.5, -12)
        bPlus.BackgroundColor3 = Theme.SurfaceHighlight
        bPlus.Text = "+"; bPlus.TextColor3 = Theme.TextPrimary
        bPlus.Font = Enum.Font.GothamBold; bPlus.TextSize = 14
        Instance.new("UICorner", bPlus).CornerRadius = UDim.new(0, 4)

        local function apply(v)
            v = math.clamp(tonumber(v) or getVal(), minVal, maxVal)
            setVal(v)
            box.Text = string.format(fmt, v)
        end
        box.FocusLost:Connect(function() apply(tonumber(box.Text) or getVal()) end)
        bMinus.MouseButton1Click:Connect(function() apply(getVal() - step) end)
        bPlus.MouseButton1Click:Connect(function() apply(getVal() + step) end)
        return box
    end

    local fe = _G.FlashExtra
    if fe then
        CreateSectionHeader("Flash TP")

        local rTPBtn = CreateRow("Demarrer Flash TP")
        local tpStartBtn = Instance.new("TextButton", rTPBtn)
        tpStartBtn.Size = UDim2.new(0, 120, 0, 26)
        tpStartBtn.Position = UDim2.new(1, -130, 0.5, -13)
        tpStartBtn.BackgroundColor3 = HAZE.ACCENT2
        tpStartBtn.Text = "TP MAINTENANT"
        tpStartBtn.TextColor3 = Color3.new(0,0,0)
        tpStartBtn.Font = Enum.Font.GothamBlack
        tpStartBtn.TextSize = 11
        Instance.new("UICorner", tpStartBtn).CornerRadius = UDim.new(0, 6)
        tpStartBtn.MouseButton1Click:Connect(function()
            task.spawn(function()
                if type(_G.FlashStartTP) == "function" then
                    _G.FlashStartTP()
                else
                    ShowNotification("FLASH TP", "Modules pas encore charges")
                end
            end)
        end)

        CreateSectionHeader("Mode de cible")

        local rPriority = CreateRow("TP Priority (liste)")
        CreateToggleSwitch(rPriority, fe.tpPriorityEnabled, function(ns, set)
            set(ns); fe.tpPriorityEnabled = ns
            ShowNotification("TP PRIORITY", ns and "ACTIVE" or "DESACTIVE")
        end)

        local rHighest = CreateRow("TP Highest (gen max)")
        CreateToggleSwitch(rHighest, fe.tpHighestEnabled, function(ns, set)
            set(ns); fe.tpHighestEnabled = ns
            ShowNotification("TP HIGHEST", ns and "ACTIVE" or "DESACTIVE")
        end)

        local rF2F1 = CreateRow("Floor2 comme Floor1")
        CreateToggleSwitch(rF2F1, fe.floor2AsFloor1, function(ns, set)
            set(ns); fe.floor2AsFloor1 = ns
            ShowNotification("FLOOR2 AS FLOOR1", ns and "ACTIVE" or "DESACTIVE")
        end)

        CreateSectionHeader("Vitesses")

        makeNumInput(nil, "Vitesse TP (studs/s)",
            function() return fe.tpSpeed or 400 end,
            function(v) fe.tpSpeed = v end,
            50, 2000, 50, "%.0f"
        )

        makeNumInput(nil, "Vitesse Brainrot (studs/s)",
            function() return fe.brainrotSnapSpeed or 300 end,
            function(v) fe.brainrotSnapSpeed = v end,
            50, 2000, 50, "%.0f"
        )

        CreateSectionHeader("Timings")

        makeNumInput(nil, "Sky Clone Wait (s)",
            function() return fe.skyCloneWait or 0.28 end,
            function(v) fe.skyCloneWait = v end,
            0, 2, 0.01, "%.2f"
        )

        makeNumInput(nil, "Clone Delay (s)",
            function() return fe.cloneDelay or 0.15 end,
            function(v) fe.cloneDelay = v end,
            0, 2, 0.01, "%.2f"
        )

        makeNumInput(nil, "Wall Anchor Wait (s)",
            function() return fe.wallAnchorWait or 0.10 end,
            function(v) fe.wallAnchorWait = v end,
            0, 2, 0.01, "%.2f"
        )

        CreateSectionHeader("Filtres")

        makeNumInput(nil, "Min Gen (millions)",
            function() return fe.tpMinMPS or 0 end,
            function(v) fe.tpMinMPS = v end,
            0, 100000, 1, "%.0f"
        )

        makeNumInput(nil, "FPS Gate (0=desactive)",
            function() return fe.tpFpsGate or 0 end,
            function(v) fe.tpFpsGate = v end,
            0, 300, 5, "%.0f"
        )

        CreateSectionHeader("Outil carpet")
        local carpetOptions = { "Flying Carpet", "Cupid's Wings", "Santa's Sleigh", "Witch's Broom", "Magic Carpet" }
        local carpetSwitches = {}
        for _, toolName in ipairs(carpetOptions) do
            local r = CreateRow(toolName)
            local ts = CreateToggleSwitch(r, (fe.tpTool or "") == toolName, function(rs, set)
                if rs then
                    fe.tpTool = toolName; set(true)
                    for n, sw in pairs(carpetSwitches) do if n ~= toolName then sw.Set(false) end end
                    ShowNotification("CARPET TP", toolName)
                else
                    set((fe.tpTool or "") == toolName)
                end
            end)
            carpetSwitches[toolName] = ts
        end

        CreateSectionHeader("Statut")
        local rStatus = CreateRow("Statut Flash TP")
        local statusLbl = Instance.new("TextLabel", rStatus)
        statusLbl.Size = UDim2.new(0, 140, 0, 20)
        statusLbl.Position = UDim2.new(1, -148, 0.5, -10)
        statusLbl.BackgroundTransparency = 1
        statusLbl.Font = Enum.Font.GothamBold
        statusLbl.TextSize = 11
        statusLbl.TextColor3 = HAZE.DIM
        statusLbl.TextXAlignment = Enum.TextXAlignment.Right
        statusLbl.Text = "idle"
        task.spawn(function()
            while statusLbl.Parent do
                statusLbl.Text = tostring(_G.TPStatus or "idle")
                task.wait(0.3)
            end
        end)
    else
        CreateRow("Flash TP non charge")
    end
    end
    end
end

BuildSettingsAndMobileUI()

local function updateSettingsCanvasSize()
    local contentHeight = sLayout.AbsoluteContentSize.Y
    sList.CanvasSize = UDim2.new(0, 0, 0, math.max(contentHeight + 20, sList.AbsoluteSize.Y))
end

sLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSettingsCanvasSize)
task.defer(updateSettingsCanvasSize)

if IS_MOBILE then
    sList.ScrollBarThickness = 6
    sList.ScrollingEnabled = true
    sList.ElasticBehavior = Enum.ElasticBehavior.Always
end

if not IS_MOBILE then
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == (Enum.KeyCode[NormalizeKeyName(Config.MenuKey, "LeftControl")] or Enum.KeyCode.LeftControl) then
            settingsGui.Enabled = not settingsGui.Enabled
            if SharedState.RefreshMobileScale then
                SharedState.RefreshMobileScale()
            end
        end
        if NormalizeKeyName(Config.KickKey, "") ~= "" and input.KeyCode == Enum.KeyCode[NormalizeKeyName(Config.KickKey, "")] then
            kickPlayer()
        end
        if NormalizeKeyName(Config.RagdollSelfKey, "") ~= "" and input.KeyCode == Enum.KeyCode[NormalizeKeyName(Config.RagdollSelfKey, "")] then
            local ragdollOnCooldown = false
            if type(isOnCooldown) == "function" then
                local okCooldown, resultCooldown = pcall(isOnCooldown, "ragdoll")
                if okCooldown then
                    ragdollOnCooldown = resultCooldown and true or false
                end
            end

            if not ragdollOnCooldown then
                local didRun = false
                if type(runAdminCommand) == "function" then
                    local okRun, resultRun = pcall(runAdminCommand, LocalPlayer, "ragdoll")
                    didRun = okRun and resultRun and true or false
                end

                if didRun then
                    if type(activeCooldowns) == "table" then
                        activeCooldowns["ragdoll"] = tick()
                    end
                    if type(setGlobalVisualCooldown) == "function" then
                        pcall(setGlobalVisualCooldown, "ragdoll")
                    end
                    if type(ShowNotification) == "function" then
                        pcall(ShowNotification, "RAGDOLL SELF", "Ragdolled " .. LocalPlayer.Name)
                    end
                else
                    if type(ShowNotification) == "function" then
                        pcall(ShowNotification, "RAGDOLL SELF", "Failed to ragdoll " .. LocalPlayer.Name)
                    end
                end
            else
                if type(ShowNotification) == "function" then
                    pcall(ShowNotification, "RAGDOLL SELF", "Ragdoll on cooldown")
                end
            end
        end
        if NormalizeKeyName(Config.ProximityAPKeybind, "P") and input.KeyCode == Enum.KeyCode[NormalizeKeyName(Config.ProximityAPKeybind, "P")] then
            ProximityAPActive = not ProximityAPActive
            if SharedState.ProximityAPButton then
                updateProxButton()
            end
            ShowNotification("PROXIMITY AP", ProximityAPActive and "ENABLED" or "DISABLED")
        end
        if input.KeyCode == (Enum.KeyCode[NormalizeKeyName(Config.ClickToAPKeybind, "L")] or Enum.KeyCode.L) then
            Config.ClickToAP = not Config.ClickToAP
            SaveConfig()
            ShowNotification("CLICK TO AP", Config.ClickToAP and "ENABLED" or "DISABLED")
        end
        if NormalizeKeyName(Config.JobJoinerKey, "J") and input.KeyCode == Enum.KeyCode[NormalizeKeyName(Config.JobJoinerKey, "J")] then
            local joinerGui = PlayerGui:FindFirstChild("XiJobJoiner")
            if joinerGui then
                Config.ShowJobJoiner = not Config.ShowJobJoiner
                joinerGui.Enabled = Config.ShowJobJoiner
                SaveConfig()
                ShowNotification("JOB ID JOINER", Config.ShowJobJoiner and "OPENED" or "CLOSED")
            end
        end
    end)
end


task.spawn(function()
    task.wait(0.1)
    if Config.HideAdminPanel then
        local adUI = PlayerGui:FindFirstChild("XiAdminPanel")
        if adUI then adUI.Enabled = false end
    end
    if Config.HideAutoSteal then
        local asUI = PlayerGui:FindFirstChild("AutoStealUI")
        if asUI then asUI.Enabled = false end
    end
    if Config.CompactAutoSteal then
        local asUI = PlayerGui:FindFirstChild("AutoStealUI")
        if asUI and asUI:FindFirstChild("Frame") then
            local frame = asUI.Frame
            local mobileScale = IS_MOBILE and 0.6 or 1
            frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, 5 * 44 + 135)
        end
    end
end)

local function parseMinGen(str)
    if not str or type(str) ~= "string" then return 0 end
    str = str:gsub("%s", ""):lower()
    if str == "" then return 0 end
    local num, suffix = str:match("^([%d%.]+)([kmb]?)$")
    if not num then return 0 end
    num = tonumber(num)
    if not num or num < 0 then return 0 end
    if suffix == "k" then return num * 1e3
    elseif suffix == "m" then return num * 1e6
    elseif suffix == "b" then return num * 1e9
    end
    return num
end

if Config.TpSettings.TpOnLoad then
    task.spawn(function()
        local minGen = parseMinGen(Config.TpSettings.MinGenForTp)
        local minLabel = tostring(Config.TpSettings.MinGenForTp or "")

        -- FIX AUTO TP ON LOAD + MIN GEN:
        -- Antes elegia el primer target que aparecia en cache y si estaba debajo del minimo hacia return.
        -- Eso hacia que, si el cache todavia estaba incompleto, nunca volviera a intentar aunque despues apareciera uno bueno.
        -- Ahora el selector SOLO devuelve targets que cumplen el minimo y reintenta mientras el cache se termina de llenar.
        local function isEligibleAutoLoadTarget(pet)
            if not pet then return false end
            if not pet.name or not pet.uid then return false end
            if pet.owner == LocalPlayer.Name then return false end
            if minGen > 0 and (tonumber(pet.genValue) or 0) < minGen then
                return false
            end
            return true
        end

        local function getPriorityTargetFromCache_MinGen()
            local cache = SharedState and SharedState.AllAnimalsCache
            if not cache or #cache == 0 then
                return nil
            end

            for i = 1, #PRIORITY_LIST do
                local wanted = PRIORITY_LIST[i]:lower()

                for _, pet in ipairs(cache) do
                    if isEligibleAutoLoadTarget(pet)
                        and pet.name:lower() == wanted then
                        return pet
                    end
                end
            end

            return nil
        end

        local function getFallbackTargetFromCache_MinGen()
            local cache = SharedState and SharedState.AllAnimalsCache
            if not cache or #cache == 0 then
                return nil
            end

            for _, pet in ipairs(cache) do
                if isEligibleAutoLoadTarget(pet) then
                    return pet
                end
            end

            return nil
        end

        local function chooseAutoLoadTarget()
            return getPriorityTargetFromCache_MinGen() or getFallbackTargetFromCache_MinGen()
        end

        local chosen = nil
        local sawAnyCache = false
        local deadline = os.clock() + 6.0

        repeat
            local cache = SharedState and SharedState.AllAnimalsCache
            if cache and #cache > 0 then
                sawAnyCache = true
            end

            chosen = chooseAutoLoadTarget()
            if chosen then
                break
            end

            RunService.Heartbeat:Wait()
        until os.clock() >= deadline

        if not chosen then
            if minGen > 0 then
                ShowNotification("MIN GEN", "No target >= " .. minLabel .. " after cache refresh.")
            elseif sawAnyCache then
                ShowNotification("TIMEOUT", "No valid target found.")
            else
                ShowNotification("TIMEOUT", "No target cache found.")
            end
            return
        end

        SharedState.SelectedPetData = {
            petName = chosen.name,
            name = chosen.name,
            mpsText = chosen.genText,
            mpsValue = chosen.genValue,
            genText = chosen.genText,
            genValue = chosen.genValue,
            owner = chosen.owner,
            plot = chosen.plot,
            slot = chosen.slot,
            uid = chosen.uid,
            mutation = chosen.mutation,
            animalData = chosen
        }

        if _G.tpToBestBrainrot then
            pcall(_G.tpToBestBrainrot)
        else
            waitSecondsHeartbeat(0.10)
            runAutoSnipe()
        end
    end)
end



LocalPlayer:GetAttributeChangedSignal("Stealing"):Connect(function()
    local isStealing = LocalPlayer:GetAttribute("Stealing")
    local wasStealing = not isStealing 

    if isStealing then
        if Config.AutoInvisDuringSteal and _G.toggleInvisibleSteal and not _G.invisibleStealEnabled then
            _G.toggleInvisibleSteal()
        end
        if Config.AutoUnlockOnSteal then
            autoUnlockCurrentFloor()
        end
    elseif wasStealing then
        if Config.AutoInvisDuringSteal and _G.toggleInvisibleSteal and _G.invisibleStealEnabled then
            _G.toggleInvisibleSteal()
        end
    end
end)

task.spawn(function()
    local stealSpeedEnabled = false
    local STEAL_SPEED = Config.StealSpeed or 25.5
    local stealConn = nil

    local function doDisable()
        stealSpeedEnabled = false
        if stealConn then stealConn:Disconnect(); stealConn=nil end
    end

    SharedState.GetStealSpeed = function()
        return STEAL_SPEED
    end

    SharedState.SetStealSpeed = function(v, silent)
        local n = tonumber(v)
        if not n then return STEAL_SPEED end
        STEAL_SPEED = math.clamp(n, 5, 100)
        Config.StealSpeed = STEAL_SPEED
        if not silent then
            SaveConfig()
        end
        if SharedState._ssUpdateBtn then
            SharedState._ssUpdateBtn()
        end
        return STEAL_SPEED
    end

    SharedState.DisableStealSpeed = function()
        doDisable()
        if SharedState._ssUpdateBtn then SharedState._ssUpdateBtn() end
    end

    local function doEnable()
        stealSpeedEnabled = true
        if stealConn then stealConn:Disconnect(); stealConn=nil end
        stealConn = RunService.Heartbeat:Connect(function()
            local char = LocalPlayer.Character; if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp then return end
            local md = hum.MoveDirection
            if md.Magnitude > 0 then
                hrp.AssemblyLinearVelocity = Vector3.new(
                    md.X * STEAL_SPEED, hrp.AssemblyLinearVelocity.Y, md.Z * STEAL_SPEED)
            end
        end)
    end

    SharedState._ssUpdateBtn = function() end

    SharedState.StealSpeedToggleFunc = function()
        if stealSpeedEnabled then doDisable() else doEnable() end
        if SharedState._ssUpdateBtn then SharedState._ssUpdateBtn() end
    end

    task.spawn(function()
        local lastHadSteal = nil
        while true do
            task.wait(0.3)
            if not Config.AutoStealSpeed then lastHadSteal = nil; continue end
            local hasSteal = (LocalPlayer:GetAttribute("Stealing") == true)
            if lastHadSteal == hasSteal then continue end
            lastHadSteal = hasSteal
            if hasSteal and not stealSpeedEnabled then
                doEnable(); if SharedState._ssUpdateBtn then SharedState._ssUpdateBtn() end
            elseif not hasSteal and stealSpeedEnabled then
                doDisable(); if SharedState._ssUpdateBtn then SharedState._ssUpdateBtn() end
            end
        end
    end)
end)

task.spawn(function()
    local brainrotESPEnabled = Config.BrainrotESP

    local function cleanupLegacyBrainrotESP()
        for _, inst in ipairs(Workspace:GetChildren()) do
            if inst.Name == "XiBrainrotESP" then
                pcall(function() inst:Destroy() end)
            end
        end
        for _, inst in ipairs(game:GetService("CoreGui"):GetChildren()) do
            if inst:IsA("Highlight") and inst.Name == "XiBrainrotESP_Highlight" then
                pcall(function() inst:Destroy() end)
            end
        end
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("BillboardGui") and string.sub(inst.Name, 1, 12) == "BrainrotESP_" then
                pcall(function() inst:Destroy() end)
            end
        end
    end

    cleanupLegacyBrainrotESP()

    local brainrotESPFolder = Instance.new("Folder")
    brainrotESPFolder.Name = "XiBrainrotESP"
    brainrotESPFolder.Parent = Workspace
    local brainrotBillboards = {}
    local hiddenOverheads = {}
    local CoreGui = game:GetService("CoreGui")
    local UID_ATTR = "_BR_UID"
    local uidCounter = 0
    local myPlot = nil
    local myPlotBounds = nil
    local myDisplayName = LocalPlayer.DisplayName
    local SCAN_INTERVAL = 0.35
    local PLOT_PADDING = 6
    local MIN_M_PER_SEC = 35

    local MUT_COLORS = {
        Cursed = Color3.fromRGB(255, 50, 50),
        Gold = Color3.fromRGB(255, 215, 0),
        Diamond = Color3.fromRGB(0, 255, 255),
        YinYang = Color3.fromRGB(220, 220, 220),
        Rainbow = Color3.fromRGB(255, 100, 200),
        Lava = Color3.fromRGB(255, 100, 20),
        Candy = Color3.fromRGB(255, 105, 180),
        Bloodrot = Color3.fromRGB(139, 0, 0),
        Radioactive = Color3.fromRGB(0, 255, 0),
        Divine = Color3.fromRGB(255, 255, 255)
    }

    local function getStableUid(part)
        if not part then return nil end
        local existing = part:GetAttribute(UID_ATTR)
        if existing then
            return tostring(existing)
        end
        uidCounter += 1
        local newId = "br_" .. tostring(uidCounter)
        part:SetAttribute(UID_ATTR, newId)
        return newId
    end

    local function parseGenToM(genText)
        genText = tostring(genText or "")
        if genText == "" then return nil end
        genText = genText:gsub("%s+", "")

        local num, suf = genText:match("%$?([%d%.]+)([KkMmBb]?)/s")
        if not num then return nil end

        local n = tonumber(num)
        if not n then return nil end

        suf = (suf or ""):upper()

        if suf == "B" then
            return n * 1000, true
        elseif suf == "M" then
            return n, false
        elseif suf == "K" then
            return n / 1000, false
        else
            return n / 1000000, false
        end
    end

    local function formatGenText(valueM)
        local m = valueM or 0
        if m >= 1000 then
            local bVal = m / 1000
            if math.floor(bVal) == bVal then
                return string.format("$%dB/s", bVal)
            else
                return string.format("$%.1fB/s", bVal)
            end
        elseif m >= 1 then
            if math.floor(m) == m then
                return string.format("$%dM/s", m)
            else
                return string.format("$%.1fM/s", m)
            end
        elseif m >= 0.001 then
            local kVal = m * 1000
            if math.floor(kVal) == kVal then
                return string.format("$%dK/s", kVal)
            else
                return string.format("$%.1fK/s", kVal)
            end
        else
            local normalVal = math.floor(m * 1000000 + 0.5)
            return string.format("$%d/s", normalVal)
        end
    end

    local function findMyPlot()
        local plotsFolder = Workspace:FindFirstChild("Plots")
        if not plotsFolder then return nil end

        for _, plot in ipairs(plotsFolder:GetChildren()) do
            local plotSign = plot:FindFirstChild("PlotSign")
            if plotSign then
                local surfaceGui = plotSign:FindFirstChild("SurfaceGui")
                if surfaceGui then
                    local frame = surfaceGui:FindFirstChild("Frame")
                    if frame then
                        local textLabel = frame:FindFirstChild("TextLabel")
                        if textLabel and textLabel:IsA("TextLabel") then
                            local txt = tostring(textLabel.Text or "")
                            if txt:find(myDisplayName, 1, true) and txt:find("'s Base", 1, true) then
                                return plot
                            end
                        end
                    end
                end
            end
        end

        return nil
    end

    local function computePlotBounds(plot)
        if not plot then return nil end

        local minX, minY, minZ = math.huge, math.huge, math.huge
        local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
        local found = false

        for _, obj in ipairs(plot:GetDescendants()) do
            if obj:IsA("BasePart") then
                found = true
                local pos = obj.Position
                local half = obj.Size / 2

                local x1, x2 = pos.X - half.X, pos.X + half.X
                local y1, y2 = pos.Y - half.Y, pos.Y + half.Y
                local z1, z2 = pos.Z - half.Z, pos.Z + half.Z

                if x1 < minX then minX = x1 end
                if y1 < minY then minY = y1 end
                if z1 < minZ then minZ = z1 end

                if x2 > maxX then maxX = x2 end
                if y2 > maxY then maxY = y2 end
                if z2 > maxZ then maxZ = z2 end
            end
        end

        if not found then return nil end

        return {
            minX = minX, maxX = maxX,
            minY = minY, maxY = maxY,
            minZ = minZ, maxZ = maxZ
        }
    end

    local function pointInsideBounds(pos, bounds, padding)
        if not bounds then return false end
        padding = padding or 0

        return pos.X >= (bounds.minX - padding) and pos.X <= (bounds.maxX + padding)
            and pos.Y >= (bounds.minY - padding) and pos.Y <= (bounds.maxY + padding)
            and pos.Z >= (bounds.minZ - padding) and pos.Z <= (bounds.maxZ + padding)
    end

    local function refreshMyPlot()
        myPlot = findMyPlot()
        myPlotBounds = computePlotBounds(myPlot)
    end

    local function isInsideMyPlotPosition(pos)
        if not myPlotBounds then return false end
        return pointInsideBounds(pos, myPlotBounds, PLOT_PADDING)
    end

    local function isDescendantOfMyPlot(obj)
        return (myPlot and obj and obj:IsDescendantOf(myPlot)) or false
    end

    local function inMapRect(pos)
        if pos.X < -535.882996 or pos.X > -285.808075 then return false end
        if pos.Z < -140.226715 or pos.Z > 258.971161 then return false end
        return true
    end

    local function readOverheadLabels(overheadGui)
        local displayName, generation

        for _, d in ipairs(overheadGui:GetDescendants()) do
            if d:IsA("TextLabel") then
                if d.Name == "DisplayName" then
                    local t = d.Text
                    if t and t ~= "" then
                        displayName = t
                    end
                elseif d.Name == "Generation" then
                    local t = d.Text
                    if t and t ~= "" then
                        generation = t
                    end
                end

                if displayName and generation then
                    break
                end
            end
        end

        return displayName, generation
    end

    local function getMutationColor(mut)
        return (mut and mut ~= "None" and mut ~= "N/A" and MUT_COLORS[mut]) or Color3.fromRGB(0, 255, 150)
    end

    local function createBrainrotBillboard(data)
        if data and data.kind == "CONVEYOR" then
            local bb = Instance.new("BillboardGui")
            bb.Name = "BrainrotESP_" .. tostring(data.uid)
            bb.Size = UDim2.new(0, 148, 0, 54)
            bb.StudsOffset = Vector3.new(0, 3, 0)
            bb.AlwaysOnTop = true
            bb.LightInfluence = 0
            bb.MaxDistance = 100000
            bb.ResetOnSpawn = false

            local f = Instance.new("Frame")
            f.Name = "Container"
            f.Parent = bb
            f.Size = UDim2.new(1, 0, 1, 0)
            f.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
            f.BackgroundTransparency = 0.25
            f.BorderSizePixel = 0
            Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)

            local st = Instance.new("UIStroke")
            st.Name = "Stroke"
            st.Parent = f
            st.Color = Color3.fromRGB(60, 60, 60)
            st.Thickness = 1.2

            local tg = Instance.new("TextLabel")
            tg.Name = "Tag"
            tg.Parent = f
            tg.Size = UDim2.new(1, -6, 0, 12)
            tg.Position = UDim2.new(0, 3, 0, 2)
            tg.BackgroundTransparency = 1
            tg.Text = "[CARPET]"
            tg.TextColor3 = Color3.fromRGB(0, 255, 150)
            tg.Font = Enum.Font.GothamBold
            tg.TextSize = 9
            tg.TextXAlignment = Enum.TextXAlignment.Left

            local nl = Instance.new("TextLabel")
            nl.Name = "Name"
            nl.Parent = f
            nl.Size = UDim2.new(1, -6, 0, 13)
            nl.Position = UDim2.new(0, 3, 0, 13)
            nl.BackgroundTransparency = 1
            nl.Text = tostring(data.name or data.petName or "Brainrot")
            nl.TextColor3 = Color3.fromRGB(255, 255, 255)
            nl.Font = Enum.Font.GothamBold
            nl.TextSize = 11
            nl.TextXAlignment = Enum.TextXAlignment.Left
            nl.TextTruncate = Enum.TextTruncate.AtEnd

            local gl = Instance.new("TextLabel")
            gl.Name = "Gen"
            gl.Parent = f
            gl.Size = UDim2.new(1, -6, 0, 14)
            gl.Position = UDim2.new(0, 3, 0, 25)
            gl.BackgroundTransparency = 1
            gl.Text = tostring(data.genText or "")
            gl.TextColor3 = Color3.fromRGB(180, 255, 180)
            gl.Font = Enum.Font.GothamBold
            gl.TextSize = 14
            gl.TextXAlignment = Enum.TextXAlignment.Left
            gl.TextTruncate = Enum.TextTruncate.AtEnd

            local dl = Instance.new("TextLabel")
            dl.Name = "Info"
            dl.Parent = f
            dl.Size = UDim2.new(1, -6, 0, 10)
            dl.Position = UDim2.new(0, 3, 1, -12)
            dl.BackgroundTransparency = 1
            dl.Text = ""
            dl.TextColor3 = Color3.fromRGB(210, 210, 210)
            dl.Font = Enum.Font.Gotham
            dl.TextSize = 9
            dl.TextXAlignment = Enum.TextXAlignment.Right

            return bb
        end

        local bb = Instance.new("BillboardGui")
        bb.Name = "BrainrotESP_" .. tostring(data.uid)
        bb.Size = UDim2.new(0, 128, 0, 56)
        bb.StudsOffset = Vector3.new(0, 1, 0)
        bb.AlwaysOnTop = true
        bb.LightInfluence = 0
        bb.MaxDistance = 2500
        bb.ResetOnSpawn = false

        local container = Instance.new("Frame")
        container.Name = "Container"
        container.Parent = bb
        container.Size = UDim2.new(1, 0, 1, 0)
        container.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
        container.BackgroundTransparency = 0.45
        container.BorderSizePixel = 0
        Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)

        local strokeColor = Color3.fromRGB(60, 60, 60)

        local stroke = Instance.new("UIStroke")
        stroke.Name = "Stroke"
        stroke.Parent = container
        stroke.Thickness = 1.2
        stroke.Color = strokeColor

        local tagLabel = Instance.new("TextLabel")
        tagLabel.Name = "Tag"
        tagLabel.Parent = container
        tagLabel.Size = UDim2.new(1, -6, 0, 10)
        tagLabel.Position = UDim2.new(0, 3, 0, 2)
        tagLabel.BackgroundTransparency = 1
        tagLabel.Font = Enum.Font.GothamBold
        tagLabel.TextSize = 10
        tagLabel.TextXAlignment = Enum.TextXAlignment.Left
        tagLabel.TextColor3 = strokeColor
        tagLabel.Text = ""

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Name = "Name"
        nameLabel.Parent = container
        nameLabel.Size = UDim2.new(1, -6, 0, 12)
        nameLabel.Position = UDim2.new(0, 3, 0, 10)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 11
        nameLabel.TextWrapped = true
        nameLabel.TextYAlignment = Enum.TextYAlignment.Top
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.TextTruncate = Enum.TextTruncate.None
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.TextStrokeTransparency = 1
        nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        nameLabel.Text = tostring(data.name or data.petName or "Brainrot")

        local genLabel = Instance.new("TextLabel")
        genLabel.Name = "Gen"
        genLabel.Parent = container
        genLabel.Size = UDim2.new(1, -6, 0, 14)
        genLabel.Position = UDim2.new(0, 3, 0, 25)
        genLabel.BackgroundTransparency = 1
        genLabel.Font = Enum.Font.ArialBold
        genLabel.TextSize = 16
        genLabel.TextXAlignment = Enum.TextXAlignment.Left
        genLabel.TextTruncate = Enum.TextTruncate.AtEnd
        genLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
        genLabel.TextStrokeTransparency = 0.82
        genLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        genLabel.Text = tostring(data.genText or "")

        local infoLabel = Instance.new("TextLabel")
        infoLabel.Name = "Info"
        infoLabel.Parent = container
        infoLabel.Size = UDim2.new(1, -6, 0, 10)
        infoLabel.Position = UDim2.new(0, 3, 1, -12)
        infoLabel.BackgroundTransparency = 1
        infoLabel.Font = Enum.Font.Gotham
        infoLabel.TextSize = 9
        infoLabel.TextXAlignment = Enum.TextXAlignment.Right
        infoLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
        infoLabel.Text = ""

        return bb
    end

    local function updateBrainrotBillboard(bb, data, hrp)
        if not bb or not bb.Parent then return end
        local container = bb:FindFirstChild("Container")
        if not container then return end

        local stroke = container:FindFirstChild("Stroke")
        local tagLabel = container:FindFirstChild("Tag")
        local nameLabel = container:FindFirstChild("Name")
        local genLabel = container:FindFirstChild("Gen")
        local infoLabel = container:FindFirstChild("Info")

        if data and data.kind == "CONVEYOR" then
            if stroke then
                stroke.Color = hasMutation and color or Color3.fromRGB(60, 60, 60)
            end

            if tagLabel then
                tagLabel.Visible = true
                tagLabel.Text = "[CARPET]"
                tagLabel.TextColor3 = Color3.fromRGB(0, 255, 150)
            end

            if nameLabel then
                nameLabel.Text = tostring(data.name or data.petName or "Brainrot")
            end

            if genLabel then
                genLabel.Text = tostring(data.genText or "")
            end

            if infoLabel then
                if hrp and data.adornee and data.adornee.Parent then
                    local dist = math.floor((hrp.Position - data.adornee.Position).Magnitude)
                    infoLabel.Text = tostring(dist) .. " studs"
                else
                    infoLabel.Text = ""
                end
            end

            bb.Adornee = data.adornee
            return
        end

        local mutationName = data.mutation
        local hasMutation = mutationName and mutationName ~= "" and mutationName ~= "None" and mutationName ~= "N/A"
        local color = getMutationColor(mutationName)
        if stroke then stroke.Color = hasMutation and color or Color3.fromRGB(60, 60, 60) end

        if tagLabel then
            tagLabel.Visible = hasMutation
            tagLabel.Text = hasMutation and string.upper(tostring(mutationName)) or ""
            tagLabel.TextColor3 = color
        end

        if nameLabel then
            nameLabel.Text = tostring(data.name or data.petName or "Brainrot")
            nameLabel.TextWrapped = true
            nameLabel.TextTruncate = Enum.TextTruncate.None
            nameLabel.TextYAlignment = Enum.TextYAlignment.Top
            nameLabel.Position = hasMutation and UDim2.new(0, 3, 0, 12) or UDim2.new(0, 3, 0, 8)
            nameLabel.Size = UDim2.new(1, -6, 0, 24)
        end

        if genLabel then
            genLabel.Text = tostring(data.genText or "")
            genLabel.Position = hasMutation and UDim2.new(0, 3, 0, 39) or UDim2.new(0, 3, 0, 36)
        end

        if infoLabel then
            if hrp and data.adornee and data.adornee.Parent then
                local dist = math.floor((hrp.Position - data.adornee.Position).Magnitude)
                infoLabel.Text = tostring(dist) .. " studs"
            else
                infoLabel.Text = ""
            end
        end

        bb.Adornee = data.adornee
    end

    local function clearBrainrotESP()
        for uid, entry in pairs(brainrotBillboards) do
            if entry.bb then
                pcall(function() entry.bb:Destroy() end)
            end
            brainrotBillboards[uid] = nil
        end

        if brainrotESPFolder and brainrotESPFolder.Parent then
            for _, child in ipairs(brainrotESPFolder:GetChildren()) do
                pcall(function() child:Destroy() end)
            end
        end

        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("BillboardGui") and string.sub(inst.Name, 1, 12) == "BrainrotESP_" then
                pcall(function() inst:Destroy() end)
            end
        end
    end

    local BL = {
        STOLEN=true, STEAL=true, PURCHASE=true, COMPRAR=true, BUY=true,
        COLLECT=true, COLETAR=true, CASH=true, VALUE=true, BASE=true,
        EMPTY=true, GENERATION=true, COMMON=true, UNCOMMON=true, RARE=true,
        EPIC=true, LEGENDARY=true, DIVINE=true, RAINBOW=true, CURSED=true,
        GOLD=true, DIAMOND=true, CANDY=true, MUTATION=true
    }

    local function cvOk(t)
        if not t or t == "" then return false end
        local c = (t:gsub("<[^>]+>", "")):match("^%s*(.-)%s*$") or ""
        if #c <= 1 then return false end
        local u = c:upper()
        if u:find("^%$") or u:find("/S$") or u:find("^[%d%.]+") then
            return false
        end
        return not BL[u]
    end

    local function pgvAbs(t)
        if type(t) ~= "string" then return nil end
        local u = t:gsub("<[^>]+>", ""):upper()
        if not u:find("%$") or not u:find("/S") then return nil end

        local c = u:gsub("%$", ""):gsub("/S", ""):gsub("%s+", "")
        local n = tonumber(c:match("[%d%.]+"))
        if not n then return nil end

        if c:find("B") then
            return n * 1e9
        elseif c:find("M") then
            return n * 1e6
        elseif c:find("K") then
            return n * 1e3
        else
            return n
        end
    end

    local function exM(model)
        if not model then return nil, nil, 0 end

        local bestName, bestGen, bestValue = nil, nil, 0

        for _, bb in ipairs(model:GetDescendants()) do
            if bb:IsA("BillboardGui") or bb:IsA("SurfaceGui") then
                for _, d in ipairs(bb:GetDescendants()) do
                    if d:IsA("TextLabel") and d.Text then
                        local value = pgvAbs(d.Text)
                        if value and value > bestValue then
                            bestValue = value
                            bestGen = d.Text:gsub("<[^>]+>", "")

                            local container = d.Parent
                            if container then
                                local found = nil

                                for _, s in ipairs(container:GetChildren()) do
                                    if s:IsA("TextLabel") and s.Name == "DisplayName" then
                                        local cleaned = (s.Text or ""):gsub("<[^>]+>", ""):match("^%s*(.-)%s*$")
                                        if cvOk(cleaned) then
                                            found = cleaned
                                            break
                                        end
                                    end
                                end

                                if not found then
                                    local bestText, bestLen = nil, 0
                                    for _, s in ipairs(container:GetChildren()) do
                                        if s:IsA("TextLabel") then
                                            local cleaned = (s.Text or ""):gsub("<[^>]+>", ""):match("^%s*(.-)%s*$") or ""
                                            if cvOk(cleaned) and #cleaned > bestLen then
                                                bestText, bestLen = cleaned, #cleaned
                                            end
                                        end
                                    end
                                    if bestText then
                                        found = bestText
                                    end
                                end

                                if found then
                                    bestName = found
                                end
                            end
                        end
                    end
                end
            end
        end

        return bestName, bestGen, bestValue
    end

    local trackedPurchasePrompts = setmetatable({}, {__mode = "k"})
    local cachedConveyorEntries = {}
    local CONVEYOR_SCAN_INTERVAL = 1.2
    local VISUAL_UPDATE_INTERVAL = 0.20
    local MIN_CONVEYOR_GV = 10e6
    local MAX_CONVEYOR_SHOW = 3

    local function isPurchasePrompt(prompt)
        if not prompt or not prompt:IsA("ProximityPrompt") then return false end
        local tx = string.lower(tostring(prompt.ActionText or ""))
        return tx:find("purchase", 1, true) or tx:find("comprar", 1, true) or tx:find("buy", 1, true)
    end

    local function registerPurchasePrompt(prompt)
        if isPurchasePrompt(prompt) then
            trackedPurchasePrompts[prompt] = true
        end
    end

    do
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                registerPurchasePrompt(obj)
            end
        end
    end

    Workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("ProximityPrompt") then
            registerPurchasePrompt(obj)
        end
    end)

    local function buildDebrisVisibleModels()
        local vis = {}
        local deb = Workspace:FindFirstChild("Debris") or Workspace

        for _, c in ipairs(deb:GetChildren()) do
            if c:IsA("Model") or c:IsA("BasePart") then
                local n, g, gv = exM(c)
                if gv and gv >= MIN_CONVEYOR_GV then
                    local p = c:IsA("BasePart") and c or (c:IsA("Model") and c.PrimaryPart)
                    if not p and c:IsA("Model") then
                        for _, ch in ipairs(c:GetChildren()) do
                            if ch:IsA("BasePart") then
                                p = ch
                                break
                            end
                        end
                    end
                    if p then
                        table.insert(vis, {
                            name = n,
                            gen = g,
                            gv = gv,
                            part = p,
                            model = c
                        })
                    end
                end
            end
        end

        return vis
    end

    local function scanConveyorEntries()
        local visible = buildDebrisVisibleModels()
        local out = {}
        local seen = {}

        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") and obj.Enabled then
                local tx = string.lower(tostring(obj.ActionText or ""))
                if tx:find("purchase", 1, true) or tx:find("comprar", 1, true) or tx:find("buy", 1, true) then
                    local parentPart = obj.Parent
                    if parentPart and parentPart:IsA("Attachment") then
                        parentPart = parentPart.Parent
                    end

                    if parentPart and parentPart:IsA("BasePart") then
                        local foundName, foundGen, foundGV, foundModel = "Brainrot", "", 0, nil
                        local matchDist, matchTarget = 15, nil

                        for _, v in ipairs(visible) do
                            if v.part and v.part.Parent then
                                local dist = (v.part.Position - parentPart.Position).Magnitude
                                if dist < matchDist then
                                    matchDist = dist
                                    matchTarget = v
                                end
                            end
                        end

                        if matchTarget then
                            foundName = matchTarget.name or "Brainrot"
                            foundGen = matchTarget.gen or ""
                            foundGV = matchTarget.gv or 0
                            foundModel = matchTarget.model
                        else
                            local searchRoot = parentPart
                            local current = parentPart
                            while current and current.Parent and current.Parent ~= Workspace do
                                searchRoot = current
                                current = current.Parent
                            end

                            local n, g, gv = exM(searchRoot)
                            if gv and gv >= MIN_CONVEYOR_GV then
                                foundName = n or foundName
                                foundGen = g or foundGen
                                foundGV = gv
                                foundModel = searchRoot
                            end
                        end

                        if foundGV >= MIN_CONVEYOR_GV then
                            local uidBase = getStableUid(parentPart) or tostring(obj)
                            local uid = "conv_" .. tostring(uidBase)

                            if not seen[uid] then
                                seen[uid] = true
                                table.insert(out, {
                                    uid = uid,
                                    kind = "CONVEYOR",
                                    name = foundName,
                                    petName = foundName,
                                    genText = foundGen,
                                    genValue = foundGV,
                                    mutation = "None",
                                    adornee = parentPart,
                                    model = foundModel,
                                })
                            end
                        end
                    end
                end
            end
        end

        table.sort(out, function(a, b)
            return (tonumber(a.genValue) or 0) > (tonumber(b.genValue) or 0)
        end)

        local limited = {}
        for i = 1, math.min(MAX_CONVEYOR_SHOW, #out) do
            limited[i] = out[i]
        end
        return limited
    end

    local function scanPlotEntries()
        local out = {}
        local sharedCache = SharedState and SharedState.AllAnimalsCache

        if type(sharedCache) ~= "table" then
            return out
        end

        for _, cached in ipairs(sharedCache) do
            if cached and cached.uid and cached.plot and cached.slot then
                if not myPlot or tostring(cached.plot) ~= tostring(myPlot.Name) then
                    local adornee = findAdorneeGlobal(cached)
                    if adornee and adornee:IsA("BasePart") and adornee.Parent then
                        local valueM = select(1, parseGenToM(cached.genText or ""))
                        local genValue = tonumber(cached.genValue) or ((valueM or 0) * 1e6)

                        if (valueM and valueM >= MIN_M_PER_SEC) or genValue >= (MIN_M_PER_SEC * 1e6) then
                            table.insert(out, {
                                uid = "plot_" .. tostring(cached.uid),
                                kind = "PLOT",
                                name = cached.name,
                                petName = cached.name,
                                genText = cached.genText or formatGenText((genValue or 0) / 1e6),
                                genValue = genValue,
                                mutation = cached.mutation or "None",
                                adornee = adornee,
                                owner = cached.owner,
                                plot = cached.plot,
                                slot = cached.slot,
                            })
                        end
                    end
                end
            end
        end

        table.sort(out, function(a, b)
            return (tonumber(a.genValue) or 0) > (tonumber(b.genValue) or 0)
        end)

        return out
    end

    local function syncBrainrotESPEntries(entries)
        local seen = {}
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        for _, data in ipairs(entries) do
            if data and data.uid and data.adornee and data.adornee.Parent then
                seen[data.uid] = true

                local entry = brainrotBillboards[data.uid]
                local needsNew = false

                if not entry or not entry.bb or not entry.bb.Parent then
                    needsNew = true
                elseif entry.adornee ~= data.adornee then
                    needsNew = true
                end

                if needsNew then
                    if entry and entry.bb then
                        pcall(function() entry.bb:Destroy() end)
                    end

                    local bb = createBrainrotBillboard(data)
                    bb.Adornee = data.adornee
                    bb.Parent = brainrotESPFolder

                    brainrotBillboards[data.uid] = {
                        bb = bb,
                        adornee = data.adornee,
                        kind = data.kind
                    }
                    entry = brainrotBillboards[data.uid]
                else
                    entry.adornee = data.adornee
                    entry.kind = data.kind
                end

                updateBrainrotBillboard(entry.bb, data, hrp)
            end
        end

        for uid, entry in pairs(brainrotBillboards) do
            if not seen[uid] then
                if entry.bb then
                    pcall(function() entry.bb:Destroy() end)
                end
                brainrotBillboards[uid] = nil
            end
        end
    end

    local function refreshBrainrotESP()
        if not brainrotESPEnabled then return end

        local entries = {}
        local plotEntries = scanPlotEntries()

        for i = 1, #plotEntries do
            entries[#entries + 1] = plotEntries[i]
        end

        for i = 1, #cachedConveyorEntries do
            entries[#entries + 1] = cachedConveyorEntries[i]
        end

        table.sort(entries, function(a, b)
            return (tonumber(a.genValue) or 0) > (tonumber(b.genValue) or 0)
        end)

        syncBrainrotESPEntries(entries)
    end

    task.spawn(function()
        while true do
            refreshMyPlot()
            task.wait(2)
        end
    end)

    if not espToggleRef then espToggleRef = {enabled=true, setFn=nil} end
    espToggleRef.setFn = function(enabled)
        brainrotESPEnabled = enabled
        Config.BrainrotESP = enabled
        if enabled then
            task.spawn(function()
                refreshMyPlot()
                pcall(function()
                    cachedConveyorEntries = scanConveyorEntries()
                end)
                pcall(refreshBrainrotESP)
            end)
        else
            clearBrainrotESP()
        end
    end

    task.spawn(function()
        while true do
            task.wait(CONVEYOR_SCAN_INTERVAL)
            if brainrotESPEnabled then
                pcall(function()
                    cachedConveyorEntries = scanConveyorEntries()
                end)
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(VISUAL_UPDATE_INTERVAL)
            if brainrotESPEnabled then
                pcall(refreshBrainrotESP)
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(2)
            if brainrotESPEnabled and next(brainrotBillboards) == nil then
                pcall(function()
                    cachedConveyorEntries = scanConveyorEntries()
                end)
                pcall(refreshBrainrotESP)
            end
        end
    end)
end)

task.spawn(function()
	local animPlaying = false
	local tracks = {}
	local clone, oldRoot, hip, connection
	local folderConnections = {}
	local SINK_AMOUNT = 5
	local serverGhosts = {}
	local ghostEnabled = true
	local lagbackCallCount = 0
	local lagbackWindowStart = 0
	local lastLagbackTime = 0
	local errorOrbActive = false
	local errorOrb = nil
	local errorOrbConnection = nil

	local function clearErrorOrb()
		if errorOrb and errorOrb.Parent then errorOrb:Destroy() end
		errorOrb = nil; errorOrbActive = false
		if errorOrbConnection then errorOrbConnection:Disconnect(); errorOrbConnection = nil end
	end

	local function createErrorOrb()
		if errorOrbActive then return end
		errorOrbActive = true
		for _, ghost in pairs(serverGhosts) do if ghost and ghost.Parent then ghost:Destroy() end end
		serverGhosts = {}
		local sg = Instance.new("ScreenGui")
		sg.Name = "ErrorOrbGui"; sg.ResetOnSpawn = false
		sg.Parent = LocalPlayer:WaitForChild("PlayerGui")
		local fr = Instance.new("Frame")
		fr.Size = UDim2.new(0, 500, 0, 60)
		fr.Position = UDim2.new(0.5, -250, 0.3, 0)
		fr.BackgroundTransparency = 1; fr.BorderSizePixel = 0; fr.Parent = sg
		local l1 = Instance.new("TextLabel")
		l1.Size = UDim2.new(1, 0, 0.5, 0); l1.BackgroundTransparency = 1
		l1.Text = "ERROR CAUSED BY PLAYER DEATH"
		l1.TextColor3 = Color3.fromRGB(255, 0, 0)
		l1.TextStrokeTransparency = 0; l1.TextStrokeColor3 = Color3.new(0, 0, 0)
		l1.Font = Enum.Font.SourceSansBold; l1.TextScaled = true; l1.Parent = fr
		local l2 = Instance.new("TextLabel")
		l2.Size = UDim2.new(1, 0, 0.5, 0); l2.Position = UDim2.new(0, 0, 0.5, 0)
		l2.BackgroundTransparency = 1; l2.Text = "MUST RESET TO FIX ERROR"
		l2.TextColor3 = Color3.fromRGB(255, 0, 0)
		l2.TextStrokeTransparency = 0; l2.TextStrokeColor3 = Color3.new(0, 0, 0)
		l2.Font = Enum.Font.SourceSansBold; l2.TextScaled = true; l2.Parent = fr
		errorOrb = sg
	end

	local function createServerGhost(position)
		if not ghostEnabled or errorOrbActive then return end
		local now = tick()
		if now - lastLagbackTime < 0.05 then return end
		lastLagbackTime = now
		if now - lagbackWindowStart > 1 then lagbackCallCount = 0; lagbackWindowStart = now end
		lagbackCallCount = lagbackCallCount + 1
		if lagbackCallCount >= 7 then createErrorOrb(); return end
		for _, g in pairs(serverGhosts) do if g and g.Parent then g:Destroy() end end
		serverGhosts = {}
		local sg = Instance.new("ScreenGui")
		sg.Name = "LagbackNotification"; sg.ResetOnSpawn = false
		sg.Parent = LocalPlayer:WaitForChild("PlayerGui")
		local sl = Instance.new("TextLabel")
		sl.Size = UDim2.new(0, 500, 0, 30); sl.Position = UDim2.new(0.5, -250, 0.15, 0)
		sl.BackgroundTransparency = 1; sl.Text = "LAGBACK DETECTED"
		sl.TextColor3 = Color3.fromRGB(255, 0, 0)
		sl.TextStrokeTransparency = 0; sl.TextStrokeColor3 = Color3.new(0, 0, 0)
		sl.Font = Enum.Font.SourceSansBold; sl.TextScaled = true; sl.Parent = sg
		local sw = Instance.new("TextLabel")
		sw.Size = UDim2.new(0, 650, 0, 25); sw.Position = UDim2.new(0.5, -325, 0.15, 32)
		sw.BackgroundTransparency = 1
		sw.Text = "DISABLE INVISIBLE STEAL NOW OR YOU WILL BE KILLED BY ANTICHEAT"
		sw.TextColor3 = Color3.fromRGB(200, 200, 200)
		sw.TextStrokeTransparency = 0; sw.TextStrokeColor3 = Color3.new(0, 0, 0)
		sw.Font = Enum.Font.SourceSansBold; sw.TextScaled = true; sw.Parent = sg
		task.delay(1.5, function() if sg and sg.Parent then sg:Destroy() end end)
		local ghost = Instance.new("Part")
		ghost.Name = "LagbackGhost"; ghost.Shape = Enum.PartType.Ball
		ghost.Size = Vector3.new(3, 3, 3); ghost.Color = Color3.fromRGB(255, 0, 0)
		ghost.Material = Enum.Material.Glass; ghost.Transparency = 0.3
		ghost.CanCollide = false; ghost.Anchored = true; ghost.CastShadow = false
		ghost.Position = position + Vector3.new(0, 5, 0); ghost.Parent = Workspace.CurrentCamera
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 400, 0, 60); bb.StudsOffset = Vector3.new(0, 4, 0)
		bb.AlwaysOnTop = true; bb.Parent = ghost
		local bl = Instance.new("TextLabel")
		bl.Size = UDim2.new(1, 0, 0, 25); bl.BackgroundTransparency = 1
		bl.Text = "LAGBACK DETECTED"; bl.TextColor3 = Color3.fromRGB(255, 0, 0)
		bl.TextStrokeTransparency = 0; bl.TextStrokeColor3 = Color3.new(0, 0, 0)
		bl.Font = Enum.Font.SourceSansBold; bl.TextScaled = true; bl.Parent = bb
		local bw = Instance.new("TextLabel")
		bw.Size = UDim2.new(1, 0, 0, 25); bw.Position = UDim2.new(0, 0, 0, 25)
		bw.BackgroundTransparency = 1
		bw.Text = "DISABLE INVISIBLE STEAL NOW OR YOU WILL BE KILLED BY ANTICHEAT"
		bw.TextColor3 = Color3.fromRGB(200, 200, 200)
		bw.TextStrokeTransparency = 0; bw.TextStrokeColor3 = Color3.new(0, 0, 0)
		bw.Font = Enum.Font.SourceSansBold; bw.TextScaled = true; bw.Parent = bb
		table.insert(serverGhosts, ghost)
	end

	local function clearAllGhosts()
		for _, ghost in pairs(serverGhosts) do pcall(function() if ghost and ghost.Parent then ghost:Destroy() end end) end
		serverGhosts = {}; clearErrorOrb(); lagbackCallCount = 0; lastLagbackTime = 0
		pcall(function()
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			if pg then for _, gui in pairs(pg:GetChildren()) do if gui.Name == "LagbackNotification" then gui:Destroy() end end end
		end)
		pcall(function() if Workspace.CurrentCamera then for _, c in pairs(Workspace.CurrentCamera:GetChildren()) do if c.Name == "LagbackGhost" then c:Destroy() end end end end)
		pcall(function() for _, c in pairs(Workspace:GetDescendants()) do if c.Name == "LagbackGhost" then c:Destroy() end end end)
	end

	local function removeFolders()
		local pf = Workspace:FindFirstChild(LocalPlayer.Name)
		if not pf then return end
		local dr = pf:FindFirstChild("DoubleRig")
		if dr then
			local rr = dr:FindFirstChild("HumanoidRootPart") or dr:FindFirstChildWhichIsA("BasePart")
			if rr and ghostEnabled then createServerGhost(rr.Position) end
			dr:Destroy()
		end
		local cs = pf:FindFirstChild("Constraints")
		if cs then cs:Destroy() end
		local conn = pf.ChildAdded:Connect(function(child)
			if child.Name == "DoubleRig" then
				task.defer(function()
					local rr = child:FindFirstChild("HumanoidRootPart") or child:FindFirstChildWhichIsA("BasePart")
					if rr and ghostEnabled then createServerGhost(rr.Position) end
					child:Destroy()
				end)
			elseif child.Name == "Constraints" then child:Destroy() end
		end)
		table.insert(folderConnections, conn)
	end

	local function doClone()
		local character = LocalPlayer.Character
		if character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0 then
			hip = character.Humanoid.HipHeight
			oldRoot = character:FindFirstChild("HumanoidRootPart")
			if not oldRoot or not oldRoot.Parent then return false end
			for _, c in pairs(oldRoot:GetChildren()) do
				if c:IsA("Attachment") and (c.Name:find("Beam") or c.Name:find("Attach")) then c:Destroy() end
			end
			for _, c in pairs(oldRoot:GetChildren()) do if c:IsA("Beam") then c:Destroy() end end
			local tmp = Instance.new("Model"); tmp.Parent = game
			character.Parent = tmp
			clone = oldRoot:Clone(); clone.Parent = character
			oldRoot.Parent = Workspace.CurrentCamera
			clone.CFrame = oldRoot.CFrame; character.PrimaryPart = clone
			character.Parent = Workspace
			for _, v in pairs(character:GetDescendants()) do
				if v:IsA("Weld") or v:IsA("Motor6D") then
					if v.Part0 == oldRoot then v.Part0 = clone end
					if v.Part1 == oldRoot then v.Part1 = clone end
				end
			end
			tmp:Destroy(); return true
		end
		return false
	end

	local function revertClone()
		local character = LocalPlayer.Character
		if not oldRoot or not oldRoot:IsDescendantOf(Workspace) or not character or character.Humanoid.Health <= 0 then return end
		local tmp = Instance.new("Model"); tmp.Parent = game
		character.Parent = tmp
		oldRoot.Parent = character; character.PrimaryPart = oldRoot
		character.Parent = Workspace; oldRoot.CanCollide = true
		for _, v in pairs(character:GetDescendants()) do
			if v:IsA("Weld") or v:IsA("Motor6D") then
				if v.Part0 == clone then v.Part0 = oldRoot end
				if v.Part1 == clone then v.Part1 = oldRoot end
			end
		end
		if clone then local p = clone.CFrame; clone:Destroy(); clone = nil; oldRoot.CFrame = p end
		oldRoot = nil
		if character and character.Humanoid then character.Humanoid.HipHeight = hip end
		clearAllGhosts()
	end

	local function animationTrickery()
		local character = LocalPlayer.Character
		if character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0 then
			local anim = Instance.new("Animation")
			anim.AnimationId = "http://www.roblox.com/asset/?id=18537363391"
			local humanoid = character.Humanoid
			local animator = humanoid:FindFirstChild("Animator") or Instance.new("Animator", humanoid)
			local animTrack = animator:LoadAnimation(anim)
			animTrack.Priority = Enum.AnimationPriority.Action4
			animTrack:Play(0, 1, 0); anim:Destroy()
			table.insert(tracks, animTrack)
			animTrack.Stopped:Connect(function() if animPlaying then animationTrickery() end end)
			task.delay(0, function()
				animTrack.TimePosition = 0.7
				task.delay(0.3, function() if animTrack then animTrack:AdjustSpeed(math.huge) end end)
			end)
		end
	end

	local function turnOff()
		clearAllGhosts()
		if not animPlaying then return end
		local character = LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		animPlaying = false; _G.invisibleStealEnabled = false
		for _, t in pairs(tracks) do pcall(function() t:Stop() end) end
		tracks = {}
		if connection then connection:Disconnect(); connection = nil end
		for _, c in ipairs(folderConnections) do if c then c:Disconnect() end end
		folderConnections = {}
		revertClone(); clearAllGhosts()
		if humanoid then pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end) end
		if _G.updateMovementPanelInvisVisual then pcall(_G.updateMovementPanelInvisVisual, false) end
		if updateVisualState then updateVisualState(false) end
	end

	local function turnOn()
		if animPlaying then return end
		local character = LocalPlayer.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		animPlaying = true; _G.invisibleStealEnabled = true
		if _G.updateMovementPanelInvisVisual then pcall(_G.updateMovementPanelInvisVisual, true) end
		if updateVisualState then updateVisualState(true) end
		tracks = {}; removeFolders()
		local success = doClone()
		if success then
			task.wait(0.05); animationTrickery()
			task.defer(function()
				if _G.resetBrainrotBeam then pcall(_G.resetBrainrotBeam) end
				if _G.resetPlotBeam then pcall(_G.resetPlotBeam) end
				task.wait(0.1)
				if _G.updateBrainrotBeam then pcall(_G.updateBrainrotBeam) end
				if _G.createPlotBeam then pcall(_G.createPlotBeam) end
			end)
			local lastSetPosition = nil; local skipFrames = 5
			connection = RunService.PreSimulation:Connect(function()
				if character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0 and oldRoot then
					local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
					if root then
						if skipFrames > 0 then skipFrames = skipFrames - 1; lastSetPosition = nil
						elseif lastSetPosition and ghostEnabled then
							local currentPos = oldRoot.Position
							local jumpDist = (currentPos - lastSetPosition).Magnitude
							if jumpDist > 3 and not _G.RecoveryInProgress then
								lastSetPosition = nil; createServerGhost(currentPos)
								if _G.AutoRecoverLagback and _G.toggleInvisibleSteal then
									_G.RecoveryInProgress = true
									task.spawn(function()
										pcall(_G.toggleInvisibleSteal); task.wait(0.5)
										pcall(_G.toggleInvisibleSteal); _G.RecoveryInProgress = false
									end)
								end
							end
						end
						if clone then clone.CanCollide = false end
						for _, c in pairs(oldRoot:GetChildren()) do
							if c:IsA("Attachment") or c:IsA("Beam") then c:Destroy() end
						end
						local rotAngle = _G.InvisStealAngle or 180
						local sa = (_G.SinkSliderValue or 5) * 0.5
						local cf = root.CFrame - Vector3.new(0, sa, 0)
						oldRoot.CFrame = cf * CFrame.Angles(math.rad(rotAngle), 0, 0)
						oldRoot.AssemblyLinearVelocity = root.AssemblyLinearVelocity; oldRoot.CanCollide = false
						lastSetPosition = oldRoot.Position
					end
				end
			end)
		end
	end

    local invisGui = Instance.new("ScreenGui")
    invisGui.Name = "XiInvisPanel"
    invisGui.ResetOnSpawn = false
    invisGui.Parent = PlayerGui
    invisGui.Enabled = Config.ShowInvisPanel

    local INVIS_UI = {
        BG = Color3.fromRGB(8, 15, 12),
        SURF = Color3.fromRGB(10, 25, 18),
        SURF2 = Color3.fromRGB(16, 42, 30),
        TEXT = Color3.fromRGB(225, 255, 235),
        DIM = Color3.fromRGB(140, 200, 165),
        AQUA_STROKE = Color3.fromRGB(65, 180, 105),
        GREEN1 = Color3.fromRGB(18, 88, 58),
        GREEN2 = Color3.fromRGB(21, 120, 76),
        GREEN_STROKE = Color3.fromRGB(60, 185, 120),
        OFF_BG = Color3.fromRGB(35, 14, 25),
        OFF_TEXT = Color3.fromRGB(100, 170, 130),
        SLIDER_BG = Color3.fromRGB(35, 14, 25),
        SLIDER_FILL1 = Color3.fromRGB(80, 210, 120),
        SLIDER_FILL2 = Color3.fromRGB(55, 160, 90),
    }

    local function InvisRound(obj, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius)
        c.Parent = obj
        return c
    end

    local function InvisStroke(obj, color, thickness, transparency)
        local s = Instance.new("UIStroke")
        s.Color = color
        s.Thickness = thickness or 1
        s.Transparency = transparency or 0
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Parent = obj
        return s
    end

    local function InvisTween(obj, t, props, style, dir)
        TweenService:Create(
            obj,
            TweenInfo.new(t or 0.2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
            props
        ):Play()
    end

    local function InvisGradient(parent, c1, c2, rot)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, c1),
            ColorSequenceKeypoint.new(1, c2),
        })
        g.Rotation = rot or 0
        g.Parent = parent
        return g
    end

    local iFrame = Instance.new("Frame", invisGui)
    iFrame.Size = UDim2.new(0, 250, 0, 418)
    iFrame.Position = UDim2.new(
        Config.Positions.InvisPanel.X,
        Config.Positions.InvisPanel.OffsetX or 0,
        Config.Positions.InvisPanel.Y,
        Config.Positions.InvisPanel.OffsetY or 0
    )
    iFrame.BackgroundColor3 = INVIS_UI.BG
    iFrame.BackgroundTransparency = 0
    iFrame.BorderSizePixel = 0
    iFrame.ClipsDescendants = true
    InvisRound(iFrame, 18)
    InvisStroke(iFrame, INVIS_UI.AQUA_STROKE, 1.2, 0.28)

    local iHeader = Instance.new("Frame", iFrame)
    iHeader.Size = UDim2.new(1, 0, 0, 44)
    iHeader.BackgroundTransparency = 1
    MakeDraggable(iHeader, iFrame, "InvisPanel")

    local iTitle = Instance.new("TextLabel", iHeader)
    iTitle.Size = UDim2.new(1, -28, 0, 24)
    iTitle.Position = UDim2.new(0, 14, 0, 10)
    iTitle.BackgroundTransparency = 1
    iTitle.Text = "INVISIBLE STEAL"
    iTitle.Font = Enum.Font.GothamBlack
    iTitle.TextSize = 18
    iTitle.TextColor3 = INVIS_UI.TEXT
    iTitle.TextXAlignment = Enum.TextXAlignment.Center

    local titleLine = Instance.new("Frame", iFrame)
    titleLine.AnchorPoint = Vector2.new(0.5, 0)
    titleLine.Position = UDim2.new(0.5, 0, 0, 38)
    titleLine.Size = UDim2.new(0, 108, 0, 1)
    titleLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    titleLine.BackgroundTransparency = 0.15
    titleLine.BorderSizePixel = 0

    local contentBox = Instance.new("Frame", iFrame)
    contentBox.Name = "ContentBox"
    contentBox.Position = UDim2.fromOffset(10, 48)
    contentBox.Size = UDim2.new(1, -20, 1, -60)
    contentBox.BackgroundColor3 = INVIS_UI.SURF
    contentBox.BorderSizePixel = 0
    InvisRound(contentBox, 16)
    InvisStroke(contentBox, INVIS_UI.AQUA_STROKE, 1, 0.48)

    local iContainer = Instance.new("Frame", contentBox)
    iContainer.BackgroundTransparency = 1
    iContainer.Size = UDim2.new(1, -10, 1, -10)
    iContainer.Position = UDim2.fromOffset(5, 5)

    local iLayout = Instance.new("UIListLayout", iContainer)
    iLayout.Padding = UDim.new(0, 8)
    iLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local activeSlider = nil

    local function addStateRow(parent, text, defaultState, onToggle)
        local row = Instance.new("TextButton")
        row.AutoButtonColor = false
        row.Size = UDim2.new(1, 0, 0, 36)
        row.BackgroundColor3 = INVIS_UI.SURF2
        row.BackgroundTransparency = 0.02
        row.BorderSizePixel = 0
        row.Text = ""
        row.Parent = parent
        InvisRound(row, 11)
        local rowStroke = InvisStroke(row, INVIS_UI.AQUA_STROKE, 1, 0.52)

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Position = UDim2.fromOffset(10, 0)
        label.Size = UDim2.new(1, -82, 1, 0)
        label.Font = Enum.Font.GothamBold
        label.Text = text
        label.TextColor3 = INVIS_UI.TEXT
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = row

        local stateBox = Instance.new("Frame")
        stateBox.Size = UDim2.fromOffset(58, 22)
        stateBox.Position = UDim2.new(1, -68, 0.5, -11)
        stateBox.BackgroundColor3 = INVIS_UI.OFF_BG
        stateBox.BorderSizePixel = 0
        stateBox.Parent = row
        InvisRound(stateBox, 7)
        local stateStroke = InvisStroke(stateBox, INVIS_UI.AQUA_STROKE, 1, 0.55)

        local stateFill = Instance.new("Frame")
        stateFill.Size = UDim2.new(1, 0, 1, 0)
        stateFill.BackgroundTransparency = 1
        stateFill.BorderSizePixel = 0
        stateFill.Parent = stateBox
        InvisRound(stateFill, 7)
        InvisGradient(stateFill, INVIS_UI.GREEN1, INVIS_UI.GREEN2, 0)

        local stateText = Instance.new("TextLabel")
        stateText.BackgroundTransparency = 1
        stateText.Size = UDim2.fromScale(1, 1)
        stateText.Font = Enum.Font.GothamBold
        stateText.TextSize = 10
        stateText.Parent = stateBox

        local state = defaultState
        local lockCallback = false

        local function refresh(instant)
            if state then
                if instant then
                    stateBox.BackgroundColor3 = INVIS_UI.GREEN1
                    stateFill.BackgroundTransparency = 0
                    stateText.Text = "ON"
                    stateText.TextColor3 = Color3.fromRGB(232, 255, 240)
                    stateStroke.Color = INVIS_UI.GREEN_STROKE
                    stateStroke.Transparency = 0.22
                else
                    InvisTween(stateBox, 0.18, {BackgroundColor3 = INVIS_UI.GREEN1})
                    InvisTween(stateFill, 0.18, {BackgroundTransparency = 0})
                    stateText.Text = "ON"
                    InvisTween(stateText, 0.12, {TextColor3 = Color3.fromRGB(232, 255, 240)})
                    InvisTween(stateStroke, 0.18, {Transparency = 0.22, Color = INVIS_UI.GREEN_STROKE})
                end
            else
                if instant then
                    stateBox.BackgroundColor3 = INVIS_UI.OFF_BG
                    stateFill.BackgroundTransparency = 1
                    stateText.Text = "OFF"
                    stateText.TextColor3 = INVIS_UI.OFF_TEXT
                    stateStroke.Color = INVIS_UI.AQUA_STROKE
                    stateStroke.Transparency = 0.55
                else
                    InvisTween(stateBox, 0.18, {BackgroundColor3 = INVIS_UI.OFF_BG})
                    InvisTween(stateFill, 0.18, {BackgroundTransparency = 1})
                    stateText.Text = "OFF"
                    InvisTween(stateText, 0.12, {TextColor3 = INVIS_UI.OFF_TEXT})
                    InvisTween(stateStroke, 0.18, {Transparency = 0.55, Color = INVIS_UI.AQUA_STROKE})
                end
            end
        end

        local function setState(newState, instant, silent)
            state = newState and true or false
            refresh(instant)
            if onToggle and not lockCallback and not silent then
                onToggle(state)
            end
        end

        refresh(true)

        row.MouseEnter:Connect(function()
            InvisTween(row, 0.14, {BackgroundColor3 = Color3.fromRGB(34, 39, 58)})
            InvisTween(rowStroke, 0.14, {Transparency = 0.38})
        end)

        row.MouseLeave:Connect(function()
            InvisTween(row, 0.14, {BackgroundColor3 = INVIS_UI.SURF2})
            InvisTween(rowStroke, 0.14, {Transparency = 0.52})
        end)

        row.MouseButton1Click:Connect(function()
            setState(not state, false, false)
        end)

        return {
            Set = function(newState, instant, silent)
                lockCallback = true
                setState(newState, instant, silent)
                lockCallback = false
            end,
            Get = function()
                return state
            end,
        }
    end

    local function addKeybindRow(parent, text, value, onChange)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 36)
        row.BackgroundColor3 = INVIS_UI.SURF2
        row.BackgroundTransparency = 0.02
        row.BorderSizePixel = 0
        row.Parent = parent
        InvisRound(row, 11)
        local rowStroke = InvisStroke(row, INVIS_UI.AQUA_STROKE, 1, 0.52)

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Position = UDim2.fromOffset(10, 0)
        label.Size = UDim2.new(1, -76, 1, 0)
        label.Font = Enum.Font.GothamBold
        label.Text = text
        label.TextColor3 = INVIS_UI.TEXT
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = row

        local valueBtn = Instance.new("TextButton")
        valueBtn.AutoButtonColor = false
        valueBtn.Size = UDim2.fromOffset(46, 22)
        valueBtn.Position = UDim2.new(1, -56, 0.5, -11)
        valueBtn.BackgroundColor3 = INVIS_UI.OFF_BG
        valueBtn.BorderSizePixel = 0
        valueBtn.Text = tostring(value)
        valueBtn.Font = Enum.Font.GothamBold
        valueBtn.TextColor3 = INVIS_UI.TEXT
        valueBtn.TextSize = 10
        valueBtn.Parent = row
        InvisRound(valueBtn, 7)
        InvisStroke(valueBtn, INVIS_UI.AQUA_STROKE, 1, 0.55)

        row.MouseEnter:Connect(function()
            InvisTween(row, 0.14, {BackgroundColor3 = Color3.fromRGB(34, 39, 58)})
            InvisTween(rowStroke, 0.14, {Transparency = 0.38})
        end)

        row.MouseLeave:Connect(function()
            InvisTween(row, 0.14, {BackgroundColor3 = INVIS_UI.SURF2})
            InvisTween(rowStroke, 0.14, {Transparency = 0.52})
        end)

        valueBtn.MouseButton1Click:Connect(function()
            valueBtn.Text = "..."
            local conn
            conn = UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Keyboard then
                    local newKey = input.KeyCode.Name
                    if onChange then
                        onChange(newKey, input.KeyCode)
                    end
                    valueBtn.Text = newKey
                    if conn then
                        conn:Disconnect()
                    end
                end
            end)
        end)

        return {
            Set = function(newValue)
                valueBtn.Text = tostring(newValue)
            end
        }
    end

    local function addSliderRow(parent, text, minValue, maxValue, initialValue, step, onChange)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 46)
        row.BackgroundColor3 = INVIS_UI.SURF2
        row.BackgroundTransparency = 0.02
        row.BorderSizePixel = 0
        row.Parent = parent
        InvisRound(row, 11)
        local rowStroke = InvisStroke(row, INVIS_UI.AQUA_STROKE, 1, 0.52)

        local label = Instance.new("TextLabel")
        label.BackgroundTransparency = 1
        label.Position = UDim2.fromOffset(10, 3)
        label.Size = UDim2.new(1, -56, 0, 16)
        label.Font = Enum.Font.GothamBold
        label.Text = text
        label.TextColor3 = INVIS_UI.TEXT
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = row

        local number = Instance.new("TextLabel")
        number.BackgroundTransparency = 1
        number.Position = UDim2.new(1, -34, 0, 3)
        number.Size = UDim2.fromOffset(24, 16)
        number.Font = Enum.Font.GothamBold
        number.TextColor3 = INVIS_UI.TEXT
        number.TextSize = 10
        number.TextXAlignment = Enum.TextXAlignment.Right
        number.Parent = row

        local barButton = Instance.new("TextButton")
        barButton.AutoButtonColor = false
        barButton.Text = ""
        barButton.Size = UDim2.new(1, -20, 0, 10)
        barButton.Position = UDim2.fromOffset(10, 26)
        barButton.BackgroundColor3 = INVIS_UI.SLIDER_BG
        barButton.BorderSizePixel = 0
        barButton.Parent = row
        InvisRound(barButton, 999)
        InvisStroke(barButton, INVIS_UI.AQUA_STROKE, 1, 0.65)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = INVIS_UI.SLIDER_FILL1
        fill.BorderSizePixel = 0
        fill.Parent = barButton
        InvisRound(fill, 999)
        InvisGradient(fill, INVIS_UI.SLIDER_FILL1, INVIS_UI.SLIDER_FILL2, 0)

        local knob = Instance.new("Frame")
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.new(0, 0, 0.5, 0)
        knob.Size = UDim2.fromOffset(12, 12)
        knob.BackgroundColor3 = INVIS_UI.TEXT
        knob.BorderSizePixel = 0
        knob.Parent = barButton
        InvisRound(knob, 999)
        InvisStroke(knob, INVIS_UI.AQUA_STROKE, 1, 0.30)

        local value = initialValue

        local function formatValue(v)
            if step and step < 1 then
                return string.format("%.2f", v)
            end
            if math.abs(v - math.floor(v)) < 0.001 then
                return tostring(math.floor(v + 0.5))
            end
            return string.format("%.1f", v)
        end

        local function applyValue(v, silent)
            value = math.clamp(v, minValue, maxValue)
            if step and step > 0 then
                value = math.floor((value / step) + 0.5) * step
                value = math.clamp(value, minValue, maxValue)
            end
            local alpha = (value - minValue) / (maxValue - minValue)
            fill.Size = UDim2.new(alpha, 0, 1, 0)
            knob.Position = UDim2.new(alpha, 0, 0.5, 0)
            number.Text = formatValue(value)
            if onChange and not silent then
                onChange(value)
            end
        end

        local function setFromInput(input)
            local absPos = barButton.AbsolutePosition.X
            local absSize = barButton.AbsoluteSize.X
            local alpha = math.clamp((input.Position.X - absPos) / absSize, 0, 1)
            local v = minValue + ((maxValue - minValue) * alpha)
            applyValue(v, false)
        end

        applyValue(initialValue, true)

        barButton.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                activeSlider = {setFromInput = setFromInput}
                setFromInput(input)
            end
        end)

        row.MouseEnter:Connect(function()
            if not activeSlider then
                InvisTween(row, 0.14, {BackgroundColor3 = Color3.fromRGB(34, 39, 58)})
                InvisTween(rowStroke, 0.14, {Transparency = 0.38})
            end
        end)

        row.MouseLeave:Connect(function()
            if not activeSlider then
                InvisTween(row, 0.14, {BackgroundColor3 = INVIS_UI.SURF2})
                InvisTween(rowStroke, 0.14, {Transparency = 0.52})
            end
        end)

        return {
            Set = function(newValue, silent)
                applyValue(newValue, silent)
            end,
            Get = function()
                return value
            end,
        }
    end

    local function addStealSpeedRow(parent)
        local row = Instance.new("Frame")
        row.Name = "StealSpeedEmbedded"
        row.Size = UDim2.new(1, 0, 0, 64)
        row.BackgroundColor3 = INVIS_UI.SURF2
        row.BackgroundTransparency = 0.02
        row.BorderSizePixel = 0
        row.Parent = parent
        InvisRound(row, 11)
        local rowStroke = InvisStroke(row, INVIS_UI.AQUA_STROKE, 1, 0.52)

        local speedLabel = Instance.new("TextLabel")
        speedLabel.BackgroundTransparency = 1
        speedLabel.Position = UDim2.fromOffset(10, 6)
        speedLabel.Size = UDim2.new(1, -82, 0, 16)
        speedLabel.Font = Enum.Font.GothamBold
        speedLabel.Text = "Speed"
        speedLabel.TextColor3 = INVIS_UI.TEXT
        speedLabel.TextSize = 11
        speedLabel.TextXAlignment = Enum.TextXAlignment.Left
        speedLabel.Parent = row

        local valueBox = Instance.new("Frame")
        valueBox.Size = UDim2.fromOffset(58, 22)
        valueBox.Position = UDim2.new(1, -68, 0, 5)
        valueBox.BackgroundColor3 = INVIS_UI.OFF_BG
        valueBox.BorderSizePixel = 0
        valueBox.Parent = row
        InvisRound(valueBox, 7)
        InvisStroke(valueBox, INVIS_UI.AQUA_STROKE, 1, 0.55)

        local valueText = Instance.new("TextLabel")
        valueText.BackgroundTransparency = 1
        valueText.Size = UDim2.fromScale(1, 1)
        valueText.Font = Enum.Font.GothamBold
        valueText.TextColor3 = INVIS_UI.TEXT
        valueText.TextSize = 10
        valueText.Parent = valueBox

        local barButton = Instance.new("TextButton")
        barButton.AutoButtonColor = false
        barButton.Text = ""
        barButton.Size = UDim2.new(1, -20, 0, 10)
        barButton.Position = UDim2.fromOffset(10, 36)
        barButton.BackgroundColor3 = INVIS_UI.SLIDER_BG
        barButton.BorderSizePixel = 0
        barButton.Parent = row
        InvisRound(barButton, 999)
        InvisStroke(barButton, INVIS_UI.AQUA_STROKE, 1, 0.65)

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, 0)
        fill.BackgroundColor3 = INVIS_UI.SLIDER_FILL1
        fill.BorderSizePixel = 0
        fill.Parent = barButton
        InvisRound(fill, 999)
        InvisGradient(fill, INVIS_UI.SLIDER_FILL1, INVIS_UI.SLIDER_FILL2, 0)

        local knob = Instance.new("Frame")
        knob.AnchorPoint = Vector2.new(0.5, 0.5)
        knob.Position = UDim2.new(0, 0, 0.5, 0)
        knob.Size = UDim2.fromOffset(12, 12)
        knob.BackgroundColor3 = INVIS_UI.TEXT
        knob.BorderSizePixel = 0
        knob.Parent = barButton
        InvisRound(knob, 999)
        InvisStroke(knob, INVIS_UI.AQUA_STROKE, 1, 0.30)

        local MIN_SPEED, MAX_SPEED = 5, 40
        local value = math.clamp(tonumber((SharedState.GetStealSpeed and SharedState.GetStealSpeed()) or Config.StealSpeed or 25.5) or 25.5, MIN_SPEED, MAX_SPEED)

        local function formatValue(v)
            return string.format("%.1f", v)
        end

        local function renderValue(v)
            value = math.clamp(tonumber(v) or value, MIN_SPEED, MAX_SPEED)
            local alpha = (value - MIN_SPEED) / (MAX_SPEED - MIN_SPEED)
            fill.Size = UDim2.new(alpha, 0, 1, 0)
            knob.Position = UDim2.new(alpha, 0, 0.5, 0)
            valueText.Text = formatValue(value)
        end

        local function applyValue(v, silent)
            local clamped = math.clamp(tonumber(v) or value, MIN_SPEED, MAX_SPEED)
            renderValue(clamped)
            if SharedState.SetStealSpeed then
                SharedState.SetStealSpeed(clamped, silent)
            else
                Config.StealSpeed = clamped
                if not silent then
                    SaveConfig()
                end
            end
        end

        local function setFromInput(input)
            local absPos = barButton.AbsolutePosition.X
            local absSize = barButton.AbsoluteSize.X
            if absSize <= 0 then
                return
            end
            local alpha = math.clamp((input.Position.X - absPos) / absSize, 0, 1)
            local v = MIN_SPEED + ((MAX_SPEED - MIN_SPEED) * alpha)
            applyValue(v, false)
        end

        renderValue(value)

        barButton.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                activeSlider = {setFromInput = setFromInput}
                setFromInput(input)
            end
        end)

        row.MouseEnter:Connect(function()
            if not activeSlider then
                InvisTween(row, 0.14, {BackgroundColor3 = Color3.fromRGB(34, 39, 58)})
                InvisTween(rowStroke, 0.14, {Transparency = 0.38})
            end
        end)

        row.MouseLeave:Connect(function()
            if not activeSlider then
                InvisTween(row, 0.14, {BackgroundColor3 = INVIS_UI.SURF2})
                InvisTween(rowStroke, 0.14, {Transparency = 0.52})
            end
        end)

        local api = {
            Set = function(newValue, silent)
                if silent then
                    renderValue(newValue)
                else
                    applyValue(newValue, false)
                end
            end,
            Get = function()
                return value
            end,
        }

        SharedState._ssUpdateBtn = function()
            if api then
                api.Set((SharedState.GetStealSpeed and SharedState.GetStealSpeed()) or Config.StealSpeed or value, true)
            end
        end

        return api
    end

    local enabledRow

    local function updateVisualState(on)
        if enabledRow then
            enabledRow.Set(on, false, true)
        end
        if _G.updateMovementPanelInvisVisual then
            pcall(_G.updateMovementPanelInvisVisual, on)
        end
    end

    enabledRow = addStateRow(iContainer, "Enabled", _G.invisibleStealEnabled or false, function()
        if _G.toggleInvisibleSteal then
            pcall(_G.toggleInvisibleSteal)
            updateVisualState(_G.invisibleStealEnabled or false)
        end
    end)

    local keybindRow = addKeybindRow(iContainer, "Keybind", Config.InvisToggleKey, function(newKeyName, keyCode)
        Config.InvisToggleKey = newKeyName
        _G.INVISIBLE_STEAL_KEY = keyCode
        SaveConfig()
    end)

    local rotationSlider = addSliderRow(iContainer, "Rotation", 0, 360, Config.InvisStealAngle, 1, function(v)
        Config.InvisStealAngle = v
        _G.InvisStealAngle = v
        SaveConfig()
    end)

    local depthSlider = addSliderRow(iContainer, "Depth", 0, 18, Config.SinkSliderValue, 1, function(v)
        Config.SinkSliderValue = v
        _G.SinkSliderValue = v
        SaveConfig()
    end)

    local autoRecoverRow = addStateRow(iContainer, "Auto Recover Lagback", _G.AutoRecoverLagback, function(state)
        _G.AutoRecoverLagback = state
        Config.AutoRecoverLagback = state
        SaveConfig()
    end)

    local autoInvisStealRow = addStateRow(iContainer, "Auto Invis On Steal", Config.AutoInvisDuringSteal, function(state)
        Config.AutoInvisDuringSteal = state
        _G.AutoInvisDuringSteal = state
        if _G.syncMainAutoInvisToggle then
            pcall(_G.syncMainAutoInvisToggle, state)
        end
        SaveConfig()
        ShowNotification("AUTO INVIS", state and "ENABLED" or "DISABLED")
    end)

    local stealSpeedSliderRow = addStealSpeedRow(iContainer)

    _G.syncMiniInvisAutoStealToggle = function(state)
        if autoInvisStealRow then
            autoInvisStealRow.Set(state, false, true)
        end
    end

    updateVisualState(_G.invisibleStealEnabled or false)
    if keybindRow then
        keybindRow.Set(Config.InvisToggleKey)
    end
    if rotationSlider then
        rotationSlider.Set(Config.InvisStealAngle, true)
    end
    if depthSlider then
        depthSlider.Set(Config.SinkSliderValue, true)
    end
    if autoRecoverRow then
        autoRecoverRow.Set(_G.AutoRecoverLagback, true, true)
    end
    if stealSpeedSliderRow then
        stealSpeedSliderRow.Set(Config.StealSpeed or STEAL_SPEED, true)
    end
    if autoInvisStealRow then
        autoInvisStealRow.Set(Config.AutoInvisDuringSteal, true, true)
    end

    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement and activeSlider then
            activeSlider.setFromInput(input)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeSlider = nil
        end
    end)

	_G.toggleInvisibleSteal = function()
		if animPlaying then turnOff() else turnOn() end
	end

	UserInputService.InputBegan:Connect(function(input)
		if UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == (_G.INVISIBLE_STEAL_KEY or Enum.KeyCode.V) then
			pcall(_G.toggleInvisibleSteal)
			if _G.updateMovementPanelInvisVisual then pcall(_G.updateMovementPanelInvisVisual, _G.invisibleStealEnabled or false) end
			if updateVisualState then updateVisualState(_G.invisibleStealEnabled or false) end
		end
	end)

	local function onCharacterAdded(newChar)
		clearErrorOrb(); clearAllGhosts(); lagbackCallCount = 0
		pcall(function() for _, c in pairs(Workspace.CurrentCamera:GetChildren()) do if c:IsA("BasePart") and c.Name == "HumanoidRootPart" then c:Destroy() end end end)
		if oldRoot then pcall(function() oldRoot:Destroy() end); oldRoot = nil end
		if clone then pcall(function() clone:Destroy() end); clone = nil end
		animPlaying = false; _G.invisibleStealEnabled = false
		if _G.updateMovementPanelInvisVisual then pcall(_G.updateMovementPanelInvisVisual, false) end
		task.wait(0.05)
		local camera = Workspace.CurrentCamera
		if camera and newChar then
			local h = newChar:FindFirstChildOfClass("Humanoid")
			if h then camera.CameraSubject = h; camera.CameraType = Enum.CameraType.Custom end
		end
	end
    LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

    local function setupDeathListener()
        local ch = LocalPlayer.Character
        if ch then
            local h = ch:FindFirstChildOfClass("Humanoid")
            if h then h.Died:Connect(function() clearErrorOrb(); clearAllGhosts(); lagbackCallCount = 0 end) end
        end
    end
    setupDeathListener()
    LocalPlayer.CharacterAdded:Connect(function() task.wait(0.1); setupDeathListener() end)

    task.spawn(function()
        local currentConnection = nil
        _G.AntiDieConnection = nil
        _G.AntiDieDisabled = false
        local function setupAntiDie()
            if _G.AntiDieDisabled then return end
            local character = LocalPlayer.Character
            if not character then return end
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            if not humanoid then return end
            if currentConnection then pcall(function() currentConnection:Disconnect() end) end
            currentConnection = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
                if _G.AntiDieDisabled then return end
                if humanoid.Health <= 0 then
                    humanoid.Health = humanoid.MaxHealth
                end
            end)
            _G.AntiDieConnection = currentConnection
        end
        _G.setupAntiDie = setupAntiDie
        setupAntiDie()
        LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.05)
            if not _G.AntiDieDisabled then
                setupAntiDie()
            end
        end)
    end)
end)

task.spawn(function()
    local wasStealingForInvis = false
    local invisWasEnabledBefore = false
    local autoEnabledInvis = false
    task.wait(0.1)
    while task.wait(0.1) do
        if _G.AutoInvisDuringSteal == false then
            wasStealingForInvis = false
            autoEnabledInvis = false
        else
            local isStealing = LocalPlayer:GetAttribute("Stealing")
            if isStealing and not wasStealingForInvis then
                invisWasEnabledBefore = _G.invisibleStealEnabled or false
                if not _G.invisibleStealEnabled and _G.toggleInvisibleSteal then
                    task.delay(0.25, function()
                        if LocalPlayer:GetAttribute("Stealing") and not _G.invisibleStealEnabled then
                            pcall(_G.toggleInvisibleSteal)
                            autoEnabledInvis = true
                        end
                    end)
                end
            end
            if not isStealing and autoEnabledInvis and _G.invisibleStealEnabled and _G.toggleInvisibleSteal then
                pcall(_G.toggleInvisibleSteal)
                autoEnabledInvis = false
            end
            wasStealingForInvis = isStealing
        end
    end
end)

task.spawn(function()
    local function getChar()
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local hrp = char:WaitForChild("HumanoidRootPart")
        local hum = char:WaitForChild("Humanoid")
        return char, hrp, hum
    end

    local function hasExclamation(target)
        for _, d in ipairs(target:GetDescendants()) do
            if d:IsA("BillboardGui") then
                local label = d:FindFirstChildWhichIsA("TextLabel", true)
                if label and label.Text:find("!") then
                    return true
                end
            end
        end
        return false
    end

    local function applyVisuals(target)
        for _, d in ipairs(target:GetDescendants()) do
            if d:IsA("BasePart") and d ~= target then
                d.Transparency = 0.5
                d.CanCollide = false
                d.CanTouch = false
                d.CanQuery = false
            elseif d:IsA("BillboardGui") and d.Name ~= "SentryLabel" then
                d:Destroy()
            elseif d:IsA("Decal") or d:IsA("Texture") then
                d.Transparency = 0.5
            end
        end
        if target:IsA("BasePart") and target.Name ~= "ProxyVisual" then
            target.Transparency = 1
            target.CanCollide = false
        end
    end

    local function getClosestSentry()
        local _, hrp = getChar()
        local closest, shortestDist = nil, math.huge
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst.Name:match("^Sentry_") then
                if hasExclamation(inst) then
                    local root = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
                    if root then
                        local dist = (hrp.Position - root.Position).Magnitude
                        if dist < shortestDist then
                            shortestDist = dist
                            closest = inst
                        end
                    end
                end
            end
        end
        return closest
    end

    while true do
        if Config.AutoDestroyTurrets then
            if LocalPlayer:GetAttribute("Stealing") == true then
                task.wait(0.5)
            else
                local targetSentry = getClosestSentry()
                if targetSentry then
                    while targetSentry and targetSentry.Parent and (LocalPlayer:GetAttribute("Stealing") ~= true) do
                        local char, hrp, hum = getChar()
                        local bat = LocalPlayer.Backpack:FindFirstChild("Bat") or char:FindFirstChild("Bat")
                        applyVisuals(targetSentry)
                        local offset = hrp.CFrame.LookVector * 4
                        local targetCF = CFrame.new(hrp.Position + offset, hrp.Position)
                        if targetSentry:IsA("Model") then
                            targetSentry:PivotTo(targetCF)
                        elseif targetSentry:IsA("BasePart") then
                            targetSentry.CFrame = targetCF
                        end
                        if bat then
                            if bat.Parent ~= char then hum:EquipTool(bat) end
                            bat:Activate()
                        end
                        task.wait(0.1)
                        if not hasExclamation(targetSentry) then break end
                    end
                end
            end
        end
        task.wait(0.1)
    end
end)

SharedState.FOV_MANAGER = {
    activeCount = 0,
    conn = nil,
    forcedFOV = 70,
}
function SharedState.FOV_MANAGER:Start()
    if self.conn then return end
    self.forcedFOV = Config.FOV or 70
    self.conn = RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        if cam then
            local targetFOV = Config.FOV or self.forcedFOV
            if cam.FieldOfView ~= targetFOV then
                cam.FieldOfView = targetFOV
            end
        end
    end)
end
function SharedState.FOV_MANAGER:Stop()
    if self.conn then
        self.conn:Disconnect()
        self.conn = nil
    end
end
function SharedState.FOV_MANAGER:Push()
    self.activeCount = self.activeCount + 1
    self:Start()
end
function SharedState.FOV_MANAGER:Pop()
    if self.activeCount > 0 then
        self.activeCount = self.activeCount - 1
    end
    if self.activeCount == 0 then
        self:Stop()
    end
end

SharedState.ANTI_BEE_DISCO = {
    running = false,
    connections = {},
    originalMoveFunction = nil,
    controlsProtected = false,
    badLightingNames = { Blue = true, DiscoEffect = true, BeeBlur = true, ColorCorrection = true },
}
function SharedState.ANTI_BEE_DISCO.nuke(obj)
    if not obj or not obj.Parent then return end
    if SharedState.ANTI_BEE_DISCO.badLightingNames[obj.Name] then
        pcall(function() obj:Destroy() end)
    end
end
function SharedState.ANTI_BEE_DISCO.disconnectAll()
    for _, conn in ipairs(SharedState.ANTI_BEE_DISCO.connections) do
        if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
    end
    SharedState.ANTI_BEE_DISCO.connections = {}
end
function SharedState.ANTI_BEE_DISCO.protectControls()
    if SharedState.ANTI_BEE_DISCO.controlsProtected then return end
    pcall(function()
        local PlayerScripts = LocalPlayer.PlayerScripts
        local PlayerModule = PlayerScripts:FindFirstChild("PlayerModule")
        if not PlayerModule then return end
        local Controls = require(PlayerModule):GetControls()
        if not Controls then return end
        local ab = SharedState.ANTI_BEE_DISCO
        if not ab.originalMoveFunction then ab.originalMoveFunction = Controls.moveFunction end
        local function protectedMoveFunction(self, moveVector, relativeToCamera)
            if ab.originalMoveFunction then ab.originalMoveFunction(self, moveVector, relativeToCamera) end
        end
        table.insert(ab.connections, RunService.Heartbeat:Connect(function()
            if not ab.running or not Config.AntiBeeDisco then return end
            if Controls.moveFunction ~= protectedMoveFunction then Controls.moveFunction = protectedMoveFunction end
        end))
        Controls.moveFunction = protectedMoveFunction
        ab.controlsProtected = true
    end)
end
function SharedState.ANTI_BEE_DISCO.restoreControls()
    if not SharedState.ANTI_BEE_DISCO.controlsProtected then return end
    pcall(function()
        local PlayerModule = LocalPlayer.PlayerScripts:FindFirstChild("PlayerModule")
        if not PlayerModule then return end
        local Controls = require(PlayerModule):GetControls()
        local ab = SharedState.ANTI_BEE_DISCO
        if Controls and ab.originalMoveFunction then
            Controls.moveFunction = ab.originalMoveFunction
            ab.controlsProtected = false
        end
    end)
end
function SharedState.ANTI_BEE_DISCO.blockBuzzingSound()
    pcall(function()
        local beeScript = LocalPlayer.PlayerScripts:FindFirstChild("Bee", true)
        if beeScript then
            local buzzing = beeScript:FindFirstChild("Buzzing")
            if buzzing and buzzing:IsA("Sound") then buzzing:Stop(); buzzing.Volume = 0 end
        end
    end)
end
function SharedState.ANTI_BEE_DISCO.Enable()
    local ab = SharedState.ANTI_BEE_DISCO
    if ab.running then return end
    ab.running = true
    for _, inst in ipairs(Lighting:GetDescendants()) do ab.nuke(inst) end
    table.insert(ab.connections, Lighting.DescendantAdded:Connect(function(obj)
        if not ab.running or not Config.AntiBeeDisco then return end
        ab.nuke(obj)
    end))
    ab.protectControls()
    table.insert(ab.connections, RunService.Heartbeat:Connect(function()
        if not ab.running or not Config.AntiBeeDisco then return end
        ab.blockBuzzingSound()
    end))
    SharedState.FOV_MANAGER:Push()
    ShowNotification("ANTI-BEE & DISCO", "Enabled")
end
function SharedState.ANTI_BEE_DISCO.Disable()
    local ab = SharedState.ANTI_BEE_DISCO
    if not ab.running then return end
    ab.running = false
    ab.restoreControls()
    ab.disconnectAll()
    SharedState.FOV_MANAGER:Pop()
    ShowNotification("ANTI-BEE & DISCO", "Disabled")
end

_G.ANTI_BEE_DISCO = SharedState.ANTI_BEE_DISCO

if Config.AntiBeeDisco then
    task.delay(1, function()
        if SharedState.ANTI_BEE_DISCO.Enable then SharedState.ANTI_BEE_DISCO.Enable() end
    end)
end

task.spawn(function()
    while true do
        if Workspace.CurrentCamera then
            if Config.FOV and Config.FOV ~= Workspace.CurrentCamera.FieldOfView then
                Workspace.CurrentCamera.FieldOfView = Config.FOV
            end
        end
        task.wait(0.1)
    end
end)

task.spawn(function()
    if IS_MOBILE then return end
    if PlayerGui:FindFirstChild("XiStatusHUD") then PlayerGui.XiStatusHUD:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "XiStatusHUD"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = PlayerGui

    local function new(className, props)
        local obj = Instance.new(className)
        for k, v in pairs(props or {}) do
            obj[k] = v
        end
        return obj
    end

    local outer = new("Frame", {
        Name = "Outer",
        AnchorPoint = Vector2.new(0.5, 1),
        Size = UDim2.new(0, 480, 0, 42),
        Position = UDim2.new(0.5, 0, 1, -80),
        BackgroundColor3 = Color3.fromRGB(8, 4, 8),
        BackgroundTransparency = 0.08,
        BorderSizePixel = 0,
        Parent = gui,
    })

    local hudScale = Instance.new("UIScale")
    hudScale.Name = "ResponsiveScale"
    hudScale.Parent = outer

    local function refreshXiStatusHUD()
        local viewport = Camera and Camera.ViewportSize or Vector2.new(1920, 1080)
        local minScale = math.min(viewport.X / 1920, viewport.Y / 1080)
        hudScale.Scale = math.clamp(minScale, 0.72, 1)
    end

    refreshXiStatusHUD()
    if Camera then
        Camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshXiStatusHUD)
    end

    new("UICorner", { CornerRadius = UDim.new(0, 18), Parent = outer })
    new("UIStroke", {
        Color = Color3.fromRGB(200, 30, 30),
        Thickness = 1.2,
        Transparency = 0.3,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = outer,
    })

    -- Ligne d'accent rouge en haut
    local accentLine = new("Frame", {
        Size = UDim2.new(0.6, 0, 0, 2),
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(220, 30, 30),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ZIndex = 4,
        Parent = outer,
    })
    new("UICorner", { CornerRadius = UDim.new(0, 2), Parent = accentLine })
    do
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(0,0,0)),
            ColorSequenceKeypoint.new(0.3, Color3.fromRGB(220,30,30)),
            ColorSequenceKeypoint.new(0.7, Color3.fromRGB(220,30,30)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0,0,0)),
        })
        g.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.2, 0),
            NumberSequenceKeypoint.new(0.8, 0),
            NumberSequenceKeypoint.new(1, 1),
        })
        g.Parent = accentLine
    end

    -- Titre
    local title = new("TextLabel", {
        Name = "Title",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 16, 0, 0),
        Size = UDim2.new(0, 130, 1, 0),
        Font = Enum.Font.GothamBlack,
        Text = "cn private",
        TextSize = 13,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 2,
        Parent = outer,
    })
    title.AutoLocalize = false

    -- Séparateur vertical
    local function makeSep(xOff)
        new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, xOff, 0.5, 0),
            Size = UDim2.new(0, 1, 0, 18),
            BackgroundColor3 = Color3.fromRGB(200, 30, 30),
            BackgroundTransparency = 0.6,
            BorderSizePixel = 0,
            ZIndex = 2,
            Parent = outer,
        })
    end
    makeSep(160)
    makeSep(238)
    makeSep(318)

    -- Horloge
    local clockLabel = new("TextLabel", {
        Name = "Clock",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 167, 0, 0),
        Size = UDim2.new(0, 64, 1, 0),
        Font = Enum.Font.GothamBold,
        Text = "00:00",
        TextSize = 13,
        TextColor3 = Color3.fromRGB(200, 200, 210),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 2,
        Parent = outer,
    })
    clockLabel.AutoLocalize = false

    -- Signal bars
    local signalWrap = new("Frame", {
        Name = "SignalWrap",
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 246, 0.5, -9),
        Size = UDim2.new(0, 22, 0, 18),
        ZIndex = 2,
        Parent = outer,
    })
    local function makeBar(x, h)
        local bar = new("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, x, 1, 0),
            Size = UDim2.new(0, 3, 0, h),
            BackgroundColor3 = Color3.fromRGB(220, 30, 30),
            BorderSizePixel = 0,
            ZIndex = 2,
            Parent = signalWrap,
        })
        new("UICorner", { CornerRadius = UDim.new(0, 1), Parent = bar })
    end
    makeBar(0, 5); makeBar(6, 8); makeBar(12, 12); makeBar(18, 16)

    -- Conteneur FPS
    local fpsPill = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 326, 0.5, 0),
        Size = UDim2.new(0, 66, 0, 30),
        BackgroundColor3 = Color3.fromRGB(20, 6, 10),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = outer,
    })
    new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = fpsPill })
    local fpsTitle = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 6, 0, 2),
        Size = UDim2.new(1, -6, 0, 10),
        Font = Enum.Font.GothamBold,
        Text = "FPS",
        TextSize = 8,
        TextColor3 = Color3.fromRGB(220, 30, 30),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
        Parent = fpsPill,
    })
    fpsTitle.AutoLocalize = false
    local fpsValue = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 6, 0, 12),
        Size = UDim2.new(1, -6, 0, 14),
        Font = Enum.Font.GothamBlack,
        Text = "0",
        TextSize = 13,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
        Parent = fpsPill,
    })
    fpsValue.AutoLocalize = false

    -- Conteneur PING
    local pingPill = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 400, 0.5, 0),
        Size = UDim2.new(0, 68, 0, 30),
        BackgroundColor3 = Color3.fromRGB(20, 6, 10),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = outer,
    })
    new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = pingPill })
    local pingTitle = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 6, 0, 2),
        Size = UDim2.new(1, -6, 0, 10),
        Font = Enum.Font.GothamBold,
        Text = "PING",
        TextSize = 8,
        TextColor3 = Color3.fromRGB(220, 30, 30),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
        Parent = pingPill,
    })
    pingTitle.AutoLocalize = false
    local pingValue = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 6, 0, 12),
        Size = UDim2.new(1, -6, 0, 14),
        Font = Enum.Font.GothamBlack,
        Text = "0ms",
        TextSize = 13,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 3,
        Parent = pingPill,
    })
    pingValue.AutoLocalize = false

    local fps = 0
    local last = tick()

    RunService.Heartbeat:Connect(function()
        fps += 1
        local now = tick()

        if now - last >= 1 then
            fpsValue.Text = tostring(fps)
            fps = 0
            last = now
        end
    end)

    task.spawn(function()
        while outer and outer.Parent do
            local ping = math.floor(LocalPlayer:GetNetworkPing() * 1000)
            pingValue.Text = tostring(ping) .. "ms"
            task.wait(0.25)
        end
    end)

    task.spawn(function()
        while outer and outer.Parent do
            local t = os.date("*t")
            clockLabel.Text = string.format("%02d:%02d", t.hour, t.min)
            task.wait(1)
        end
    end)
    -- Haze Hub HUD dragging disabled


    if Config.ShowUnlockButtonsHUD then
        task.defer(function()
            toggleUnlockBaseMenu(true)
        end)
    end
end)



task.spawn(function()
    local playerESPEnabled = Config.PlayerESP
    local playerBillboards = {}
    
    local function makePlayerBillboard(player)
        local bb = Instance.new("BillboardGui")
        bb.Name = "PlayerESP_"..tostring(player.UserId)
        bb.Size = UDim2.new(0, 100, 0, 20)
        bb.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
        bb.AlwaysOnTop = true; bb.LightInfluence = 0; bb.ResetOnSpawn = false
        local nameLbl = Instance.new("TextLabel", bb)
        nameLbl.Size = UDim2.new(1,0,1,0)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Font = Enum.Font.GothamBlack; nameLbl.TextSize = 13
        nameLbl.TextColor3 = Theme.Accent1
        nameLbl.TextXAlignment = Enum.TextXAlignment.Center
        nameLbl.TextStrokeTransparency = 0.4
        nameLbl.TextStrokeColor3 = Color3.fromRGB(0,0,0)
        nameLbl.Text = player.DisplayName
        return bb, nameLbl
    end

    local function getHRP(player)
        local char = player.Character; if not char then return nil end
        return char:FindFirstChild("HumanoidRootPart")
    end

    local function createOrRefresh(player)
        if player == LocalPlayer then return end
        local hrp = getHRP(player); if not hrp then return end
        local hum = player.Character:FindFirstChild("Humanoid")
        
        if hum then
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end

        local uid = player.UserId
        local entry = playerBillboards[uid]
        if not entry or not entry.bb or not entry.bb.Parent then
            if entry and entry.bb then pcall(function() entry.bb:Destroy() end) end
            local bb, nameLbl = makePlayerBillboard(player)
            bb.Adornee = hrp; bb.Parent = hrp
            playerBillboards[uid] = {bb=bb, nameLbl=nameLbl, player=player}
        else
            if entry.bb.Adornee ~= hrp then entry.bb.Adornee = hrp; entry.bb.Parent = hrp end
        end
    end

    local function clearAll()
        for uid, entry in pairs(playerBillboards) do
            if entry.bb and entry.bb.Parent then pcall(function() entry.bb:Destroy() end) end
            local p = Players:GetPlayerByUserId(uid)
            if p and p.Character then
                local h = p.Character:FindFirstChild("Humanoid")
                if h then h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer end
            end
            playerBillboards[uid] = nil
        end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                for _, d in ipairs(plr.Character:GetDescendants()) do
                    if d:IsA("BillboardGui") and string.sub(d.Name, 1, 10) == "PlayerESP_" then
                        pcall(function() d:Destroy() end)
                    end
                end
                local hum = plr.Character:FindFirstChild("Humanoid")
                if hum then
                    hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
                end
            end
        end
    end

    if not playerESPToggleRef then playerESPToggleRef = {setFn=nil} end
    playerESPToggleRef.setFn = function(enabled)
        playerESPEnabled = enabled
        Config.PlayerESP = enabled
        if enabled then
            clearAll()
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    pcall(createOrRefresh, player)
                end
            end
        else
            clearAll()
        end
    end

    task.spawn(function()
        while true do
            task.wait(0.5)
            if playerESPEnabled then
            for uid, entry in pairs(playerBillboards) do
                if not Players:GetPlayerByUserId(uid) then
                    if entry.bb and entry.bb.Parent then pcall(function() entry.bb:Destroy() end) end
                    playerBillboards[uid] = nil
                end
            end
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    pcall(createOrRefresh, player)
                end
            end
            end
        end
    end)

    Players.PlayerAdded:Connect(function(p)
        p.CharacterAdded:Connect(function()
            task.wait(0.5)
            if playerESPEnabled then pcall(createOrRefresh, p) end
        end)
    end)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            p.CharacterAdded:Connect(function()
                task.wait(0.5)
                if playerESPEnabled then pcall(createOrRefresh, p) end
            end)
        end
    end
end)


task.spawn(function()
    local timerESPEnabled = Config.TimerESP
    local RS = RunService
    local TweenService = TweenService
    local ROOT = Workspace:FindFirstChild("Plots")

    local COLORS = {
        Text        = Color3.fromRGB(235,240,255),
        SilverA     = Color3.fromRGB(220,228,245),
        SilverB     = Color3.fromRGB(160,170,210),
        SteelA      = Color3.fromRGB(120,130,185),
        Stroke      = Color3.fromRGB(150,160,210),
        UnlockA     = Color3.fromRGB(235,240,255),
        UnlockB     = Color3.fromRGB(185,195,225),
    }

    local estadoPorBase = {}
    local FREEZE_THRESHOLD = 1
    local ALTURA_MAX = 7
    local timerConnection = nil

    local function tween(el, info, props)
        TweenService:Create(el, info, props):Play()
    end

    local function applyTextStyle(el)
        el.TextStrokeColor3 = Color3.fromRGB(0,0,0)
        el.TextStrokeTransparency = 0
    end

    local function addTextGradient(el)
        local old = el:FindFirstChildOfClass("UIGradient")
        if old then old:Destroy() end

        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, COLORS.SilverA),
            ColorSequenceKeypoint.new(0.5, COLORS.SilverB),
            ColorSequenceKeypoint.new(1, COLORS.SteelA),
        })
        g.Rotation = 0
        g.Parent = el

        task.spawn(function()
            while g.Parent do
                for i = 0, 360, 1 do
                    if not g.Parent then return end
                    g.Rotation = i
                    task.wait(0.05)
                end
            end
        end)
    end

    local function makeGlow(el)
        if el:GetAttribute("Glow") then return end
        el:SetAttribute("Glow", true)

        task.spawn(function()
            while el.Parent do
                tween(el, TweenInfo.new(1.2, Enum.EasingStyle.Sine), {
                    TextColor3 = COLORS.SilverA
                })
                task.wait(1.2)

                tween(el, TweenInfo.new(1.2, Enum.EasingStyle.Sine), {
                    TextColor3 = COLORS.SteelA
                })
                task.wait(1.2)
            end
        end)
    end

    local function addOutline(el)
        if el:FindFirstChild("StrokeBlack") then return end

        local black = Instance.new("UIStroke")
        black.Name = "StrokeBlack"
        black.Color = Color3.fromRGB(0,0,0)
        black.Thickness = 1
        black.Transparency = 0
        black.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        black.Parent = el

        local silver = Instance.new("UIStroke")
        silver.Name = "StrokeSilver"
        silver.Color = COLORS.Stroke
        silver.Thickness = 1.1
        silver.Transparency = 0.15
        silver.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
        silver.Parent = el
    end

    local function findBasePart(obj)
        while obj and not obj:IsA("BasePart") do
            obj = obj.Parent
        end
        return obj
    end

    local function crearESP(base)
        if not base or not base.Parent then return nil end

        local existing = base:FindFirstChild("TimerESP")
        if existing and existing:FindFirstChild("Label") then
            return existing.Label
        end

        local gui = Instance.new("BillboardGui")
        gui.Name = "TimerESP"
        gui.Adornee = base
        gui.Size = UDim2.new(0, 140, 0, 34)
        gui.StudsOffset = Vector3.new(0, 4.5, 0)
        gui.AlwaysOnTop = true
        gui.MaxDistance = 500

        local label = Instance.new("TextLabel")
        label.Name = "Label"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBlack
        label.Text = "Detectando..."
        label.TextColor3 = COLORS.Text
        label.TextScaled = false
        label.TextSize = 13

        applyTextStyle(label)
        addTextGradient(label)
        makeGlow(label)
        addOutline(label)

        label.Parent = gui
        gui.Parent = base
        return label
    end

    local function clearTimerESP()
        table.clear(estadoPorBase)
        local plots = Workspace:FindFirstChild("Plots")
        if plots then
            for _, inst in ipairs(plots:GetDescendants()) do
                if inst:IsA("BillboardGui") and inst.Name == "TimerESP" then
                    pcall(function() inst:Destroy() end)
                end
            end
        end
    end

    local function refreshTimerESP()
        local plots = ROOT or Workspace:FindFirstChild("Plots")
        if not plots then return end

        local seenBases = {}

        for _, plot in ipairs(plots:GetChildren()) do
            for _, gui in ipairs(plot:GetDescendants()) do
                if not gui:IsA("BillboardGui") then continue end

                local rem = gui:FindFirstChild("RemainingTime")
                if not rem then continue end

                local base = findBasePart(gui)
                if not base or base.Position.Y > ALTURA_MAX then continue end
                seenBases[base] = true

                local esp = crearESP(base)
                if not esp then continue end

                local raw = rem.Text or ""
                local n = tonumber(raw:match("(%d+)%s*s"))

                local st = estadoPorBase[base]
                if not st then
                    st = {estado = "locked", ultimoN = nil, freeze = nil}
                    estadoPorBase[base] = st
                end

                if not n or n <= 0 then
                    st.estado = "unlock"
                    st.freeze = nil
                else
                    if st.ultimoN == n then
                        st.freeze = st.freeze or tick()
                        if tick() - st.freeze >= FREEZE_THRESHOLD then
                            st.estado = "unlock"
                        end
                    else
                        st.freeze = nil
                        st.estado = "locked"
                    end
                    st.ultimoN = n
                end

                if st.estado == "unlock" then
                    esp.Text = "UNLOCK"
                    esp.TextSize = 14
                    esp.TextColor3 = COLORS.UnlockA
                    applyTextStyle(esp)

                    local g = esp:FindFirstChildOfClass("UIGradient")
                    if g then
                        g.Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, COLORS.UnlockA),
                            ColorSequenceKeypoint.new(1, COLORS.UnlockB),
                        })
                    end
                else
                    esp.Text = raw ~= "" and raw or "..."
                    esp.TextSize = 24
                    esp.TextColor3 = COLORS.Text
                    applyTextStyle(esp)

                    local g = esp:FindFirstChildOfClass("UIGradient")
                    if g then
                        g.Color = ColorSequence.new({
                            ColorSequenceKeypoint.new(0, COLORS.SilverA),
                            ColorSequenceKeypoint.new(0.5, COLORS.SilverB),
                            ColorSequenceKeypoint.new(1, COLORS.SteelA),
                        })
                    end
                end
            end
        end

        for base, _ in pairs(estadoPorBase) do
            if (not base) or (not base.Parent) or (not seenBases[base]) then
                estadoPorBase[base] = nil
                if base and base.Parent then
                    local timerGui = base:FindFirstChild("TimerESP")
                    if timerGui then
                        pcall(function() timerGui:Destroy() end)
                    end
                end
            end
        end
    end

    local function setTimerESPEnabled(enabled)
        timerESPEnabled = enabled
        Config.TimerESP = enabled

        if timerConnection then
            timerConnection:Disconnect()
            timerConnection = nil
        end

        if enabled then
            clearTimerESP()
            timerConnection = RS.Heartbeat:Connect(function()
                pcall(refreshTimerESP)
            end)
            pcall(refreshTimerESP)
        else
            clearTimerESP()
        end
    end

    timerESPToggleRef = timerESPToggleRef or {setFn=nil}
    timerESPToggleRef.setFn = setTimerESPEnabled

    if timerESPEnabled then
        setTimerESPEnabled(true)
    end
end)


task.spawn(function()

    if settingsGui and settingsGui:FindFirstChild("sFrame", true) then
        local sList = settingsGui.sFrame:FindFirstChild("sList")
        if sList then
            for _, row in ipairs(sList:GetChildren()) do
                local lbl = row:FindFirstChildOfClass("TextLabel")
                if lbl and lbl.Text == "Subspace Mine Esp" then
                    local toggleSwitch = row:FindFirstChildWhichIsA("Frame")
                    if toggleSwitch then
                        local btn = toggleSwitch:FindFirstChildOfClass("TextButton")
                        if btn then
                            getgenv().subspaceMineESPToggleRef = subspaceMineESPToggleRef
                        end
                    end
                    break 
                end
            end
        end
    end

    local subspaceMineESPData = {}
    local FolderName = "ToolsAdds" 

    local function getMineOwner(mineName)
        local ownerName = mineName:match("SubspaceTripmine(.+)")
        
        if not ownerName then return "Unknown" end 

        local foundPlayer = Players:FindFirstChild(ownerName)
        local displayName = foundPlayer and foundPlayer.DisplayName or ownerName
        
        return displayName
    end

    local function createMineESP(mine)
        local ownerName = getMineOwner(mine.Name)

        local selectionBox = Instance.new("SelectionBox")
        selectionBox.Name = "ESP_Hitbox"
        selectionBox.Adornee = mine 
        selectionBox.Color3 = Color3.fromRGB(167, 142, 255)
        selectionBox.LineThickness = 0.05
        selectionBox.Parent = mine 

        local billboardGui = Instance.new("BillboardGui")
        billboardGui.Name = "ESP_Label"
        billboardGui.Adornee = mine
        billboardGui.Size = UDim2.new(0, 250, 0, 50)
        billboardGui.StudsOffset = Vector3.new(0, 2.5, 0)
        billboardGui.AlwaysOnTop = false 
        billboardGui.Parent = mine

        local textLabel = Instance.new("TextLabel", billboardGui)
        textLabel.Size = UDim2.new(1, 0, 1, 0) 
        textLabel.BackgroundTransparency = 1
        textLabel.Text = ownerName .. "'s Subspace Mine"
        textLabel.TextColor3 = Color3.fromRGB(167, 142, 255)
        textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        textLabel.TextStrokeTransparency = 0 
        textLabel.Font = Enum.Font.GothamBold 
        textLabel.TextSize = 16

        return { selectionBox = selectionBox, billboardGui = billboardGui, mine = mine }
    end

    local function refreshSubspaceMineESP()
        if not Config.SubspaceMineESP then
            for i, data in pairs(subspaceMineESPData) do
                if data.selectionBox and data.selectionBox.Parent then data.selectionBox:Destroy() end
                if data.billboardGui and data.billboardGui.Parent then data.billboardGui:Destroy() end
                subspaceMineESPData[i] = nil
            end
            return
        end

        local toolsFolder = Workspace:FindFirstChild(FolderName)
        if not toolsFolder then return end

        local currentMines = {}

        for _, obj in pairs(toolsFolder:GetChildren()) do
            if obj.Name:match("^SubspaceTripmine") and obj:IsA("BasePart") then
                currentMines[obj] = true

                if not subspaceMineESPData[obj] then
                    subspaceMineESPData[obj] = createMineESP(obj)
                end
            end
        end

        for mineObj, data in pairs(subspaceMineESPData) do
            if not currentMines[mineObj] or not mineObj.Parent then
                if data.selectionBox and data.selectionBox.Parent then data.selectionBox:Destroy() end
                if data.billboardGui and data.billboardGui.Parent then data.billboardGui:Destroy() end
                subspaceMineESPData[mineObj] = nil
            end
        end
    end

    if subspaceMineESPToggleRef then
        subspaceMineESPToggleRef.setFn = function(enabled)
            Config.SubspaceMineESP = enabled
            if not enabled then
                for _, data in pairs(subspaceMineESPData) do
                    if data.selectionBox and data.selectionBox.Parent then data.selectionBox:Destroy() end
                    if data.billboardGui and data.billboardGui.Parent then data.billboardGui:Destroy() end
                end
                table.clear(subspaceMineESPData)
            end
        end
    end

    while true do
        task.wait(0.5) 
        
        local success, errorMessage = pcall(refreshSubspaceMineESP)
    end
end)


task.spawn(function()
    local Datas = ReplicatedStorage:WaitForChild("Datas")
    local AnimalsData = require(Datas:WaitForChild("Animals"))

    local OG_PRIORITY_NAMES = {
        "Strawberry Elephant",
        "Meowl",
        "Skibidi Toilet",
        "Headless Horseman",
    }

    local OG_LOOKUP = {}
    for _, name in ipairs(OG_PRIORITY_NAMES) do
        OG_LOOKUP[string.lower(name)] = true
    end

    local function round(obj, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius)
        c.Parent = obj
        return c
    end

    local function pad(parent, l, r, t, b)
        local p = Instance.new("UIPadding")
        p.PaddingLeft = UDim.new(0, l or 0)
        p.PaddingRight = UDim.new(0, r or 0)
        p.PaddingTop = UDim.new(0, t or 0)
        p.PaddingBottom = UDim.new(0, b or 0)
        p.Parent = parent
        return p
    end

    local function buildAllAnimalNames()
        local seen = {}
        local ogs = {}
        local secrets = {}

        for _, name in ipairs(OG_PRIORITY_NAMES) do
            table.insert(ogs, name)
            seen[string.lower(name)] = true
        end

        for petName, data in pairs(AnimalsData) do
            if type(petName) == "string" and petName ~= "" and type(data) == "table" then
                local lower = string.lower(petName)
                local rarity = tostring(data.Rarity or "")
                if rarity == "Secret" and not seen[lower] and not string.find(petName, "Lucky Block", 1, true) then
                    seen[lower] = true
                    table.insert(secrets, petName)
                end
            end
        end

        table.sort(secrets, function(a, b)
            return string.lower(a) < string.lower(b)
        end)

        return ogs, secrets, seen
    end

    local ogCategoryNames, secretCategoryNames, knownNamesLookup = buildAllAnimalNames()

    local priorityGui = Instance.new("ScreenGui")
    priorityGui.Name = "PriorityListGUI"
    priorityGui.ResetOnSpawn = false
    priorityGui.IgnoreGuiInset = true
    priorityGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    priorityGui.Parent = PlayerGui
    priorityGui.Enabled = false

    local reloadEvent = Instance.new("BindableEvent")
    reloadEvent.Name = "ReloadPriorityList"
    reloadEvent.Parent = priorityGui

    local function persistPriorityRealtime(selectedOrder)
        for i = #PRIORITY_LIST, 1, -1 do
            PRIORITY_LIST[i] = nil
        end
        for i, name in ipairs(selectedOrder) do
            PRIORITY_LIST[i] = name
        end
        SavePriorityListToConfig()
        SaveConfig()
    end

    local C = {
        BG = Color3.fromRGB(10, 6, 10),
        PANEL = Color3.fromRGB(12, 30, 22),
        ROW = Color3.fromRGB(35, 14, 26),
        ROW2 = Color3.fromRGB(12, 30, 22),
        SELECT_FILL = Color3.fromRGB(70, 25, 52),
        CHIP = Color3.fromRGB(50, 20, 40),
        CHIP_HOVER = Color3.fromRGB(55, 22, 42),
        TEXT = Color3.fromRGB(225, 255, 235),
        DIM = Color3.fromRGB(140, 200, 165),
        DIM2 = Color3.fromRGB(100, 170, 130),
        LINE = Color3.fromRGB(80, 200, 130),
        LINE_SOFT = Color3.fromRGB(60, 160, 100),
        SEARCH = Color3.fromRGB(10, 18, 15),
    }

    local categories = {
        {"OGs", ogCategoryNames},
        {"Secrets", secretCategoryNames},
    }

    for _, cat in ipairs(categories) do
        cat.open = true
    end

    local selectedOrder = {}
    local selectedSet = {}

    local function rebuildSelectionsFromPriorityList()
        table.clear(selectedOrder)
        table.clear(selectedSet)

        local seen = {}
        for _, name in ipairs(PRIORITY_LIST) do
            if type(name) == "string" and name ~= "" then
                local lower = string.lower(name)
                if not seen[lower] then
                    seen[lower] = true
                    selectedSet[name] = true
                    table.insert(selectedOrder, name)
                    if not knownNamesLookup[lower] and not OG_LOOKUP[lower] then
                        knownNamesLookup[lower] = true
                        table.insert(secretCategoryNames, name)
                    end
                end
            end
        end

        table.sort(secretCategoryNames, function(a, b)
            return string.lower(a) < string.lower(b)
        end)
    end

    local function isSelected(name)
        return selectedSet[name] == true
    end

    local function addSelected(name)
        if selectedSet[name] then return end
        selectedSet[name] = true
        table.insert(selectedOrder, name)
        persistPriorityRealtime(selectedOrder)
    end

    local function removeSelected(name)
        if not selectedSet[name] then return end
        selectedSet[name] = nil
        for i, v in ipairs(selectedOrder) do
            if v == name then
                table.remove(selectedOrder, i)
                break
            end
        end
        persistPriorityRealtime(selectedOrder)
    end

    local priorityCard = nil
    repeat
        task.wait()
        priorityCard = PageCards and PageCards.Priority
    until priorityCard and priorityCard.Parent

    local oldScroll = priorityCard:FindFirstChild("Scroll")
    if oldScroll then
        oldScroll:Destroy()
    end

    local root = priorityCard:FindFirstChild("EmbeddedPriorityManager")
    if root then
        root:Destroy()
    end

    root = Instance.new("Frame")
    root.Name = "EmbeddedPriorityManager"
    root.BackgroundColor3 = C.BG
    root.BorderSizePixel = 0
    root.Size = UDim2.new(1, -12, 1, -12)
    root.Position = UDim2.fromOffset(6, 6)
    root.Parent = priorityCard
    round(root, 16)

    local body = Instance.new("Frame")
    body.BackgroundTransparency = 1
    body.Size = UDim2.new(1, -16, 1, -16)
    body.Position = UDim2.fromOffset(8, 8)
    body.Parent = root

    local leftPanel = Instance.new("Frame")
    leftPanel.Size = UDim2.new(0.5, -4, 1, 0)
    leftPanel.BackgroundColor3 = C.PANEL
    leftPanel.BorderSizePixel = 0
    leftPanel.Parent = body
    round(leftPanel, 16)

    local rightPanel = Instance.new("Frame")
    rightPanel.Position = UDim2.new(0.5, 4, 0, 0)
    rightPanel.Size = UDim2.new(0.5, -4, 1, 0)
    rightPanel.BackgroundColor3 = C.PANEL
    rightPanel.BorderSizePixel = 0
    rightPanel.Parent = body
    round(rightPanel, 16)

    local leftHeader = Instance.new("TextLabel")
    leftHeader.BackgroundTransparency = 1
    leftHeader.Size = UDim2.new(1, -20, 0, 16)
    leftHeader.Position = UDim2.fromOffset(10, 8)
    leftHeader.Font = Enum.Font.GothamBold
    leftHeader.Text = "All Animals"
    leftHeader.TextSize = 11
    leftHeader.TextColor3 = C.TEXT
    leftHeader.TextXAlignment = Enum.TextXAlignment.Left
    leftHeader.Parent = leftPanel

    local search = Instance.new("TextBox")
    search.ClearTextOnFocus = false
    search.Text = ""
    search.PlaceholderText = "Search brainrot..."
    search.Font = Enum.Font.Gotham
    search.TextSize = 11
    search.TextColor3 = C.TEXT
    search.PlaceholderColor3 = C.DIM2
    search.TextXAlignment = Enum.TextXAlignment.Left
    search.Size = UDim2.new(1, -20, 0, 26)
    search.Position = UDim2.fromOffset(10, 28)
    search.BackgroundColor3 = C.SEARCH
    search.BorderSizePixel = 0
    search.Parent = leftPanel
    round(search, 9)
    pad(search, 10, 10, 0, 0)

    local leftScroll = Instance.new("ScrollingFrame")
    leftScroll.BackgroundTransparency = 1
    leftScroll.BorderSizePixel = 0
    leftScroll.Position = UDim2.fromOffset(10, 60)
    leftScroll.Size = UDim2.new(1, -20, 1, -70)
    leftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    leftScroll.CanvasSize = UDim2.new()
    leftScroll.ScrollBarThickness = 2
    leftScroll.ScrollBarImageColor3 = C.LINE
    leftScroll.Parent = leftPanel

    local leftHolder = Instance.new("Frame")
    leftHolder.BackgroundTransparency = 1
    leftHolder.Size = UDim2.new(1, -6, 0, 0)
    leftHolder.AutomaticSize = Enum.AutomaticSize.Y
    leftHolder.Position = UDim2.fromOffset(3, 0)
    leftHolder.Parent = leftScroll

    local leftLayout = Instance.new("UIListLayout")
    leftLayout.Padding = UDim.new(0, 5)
    leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
    leftLayout.Parent = leftHolder

    local rightHeader = Instance.new("TextLabel")
    rightHeader.BackgroundTransparency = 1
    rightHeader.Size = UDim2.new(1, -20, 0, 16)
    rightHeader.Position = UDim2.fromOffset(10, 8)
    rightHeader.Font = Enum.Font.GothamBold
    rightHeader.Text = "My Order"
    rightHeader.TextSize = 11
    rightHeader.TextColor3 = C.TEXT
    rightHeader.TextXAlignment = Enum.TextXAlignment.Left
    rightHeader.Parent = rightPanel

    local rightCount = Instance.new("TextLabel")
    rightCount.BackgroundTransparency = 1
    rightCount.Size = UDim2.fromOffset(42, 16)
    rightCount.Position = UDim2.new(1, -48, 0, 8)
    rightCount.Font = Enum.Font.GothamBold
    rightCount.Text = "#0"
    rightCount.TextSize = 11
    rightCount.TextColor3 = C.DIM
    rightCount.Parent = rightPanel

    local rightScroll = Instance.new("ScrollingFrame")
    rightScroll.BackgroundTransparency = 1
    rightScroll.BorderSizePixel = 0
    rightScroll.Position = UDim2.fromOffset(10, 30)
    rightScroll.Size = UDim2.new(1, -20, 1, -40)
    rightScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    rightScroll.CanvasSize = UDim2.new()
    rightScroll.ScrollBarThickness = 2
    rightScroll.ScrollBarImageColor3 = C.LINE
    rightScroll.Parent = rightPanel

    local rightHolder = Instance.new("Frame")
    rightHolder.BackgroundTransparency = 1
    rightHolder.Size = UDim2.new(1, -6, 0, 0)
    rightHolder.AutomaticSize = Enum.AutomaticSize.Y
    rightHolder.Position = UDim2.fromOffset(3, 0)
    rightHolder.Parent = rightScroll

    local rightLayout = Instance.new("UIListLayout")
    rightLayout.Padding = UDim.new(0, 4)
    rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
    rightLayout.Parent = rightHolder

    local function makeCheck(parent)
        local box = Instance.new("Frame")
        box.Size = UDim2.fromOffset(18, 18)
        box.BackgroundColor3 = C.SEARCH
        box.BorderSizePixel = 0
        box.Parent = parent
        round(box, 6)

        local boxStroke = Instance.new("UIStroke")
        boxStroke.Thickness = 1
        boxStroke.Color = C.LINE_SOFT
        boxStroke.Transparency = 0.35
        boxStroke.Parent = box

        local tick = Instance.new("TextLabel")
        tick.BackgroundTransparency = 1
        tick.Size = UDim2.fromScale(1, 1)
        tick.Font = Enum.Font.GothamBold
        tick.Text = "✓"
        tick.TextSize = 12
        tick.TextColor3 = C.TEXT
        tick.Visible = false
        tick.Parent = box

        local function setOn(on)
            if on then
                box.BackgroundColor3 = C.CHIP
                boxStroke.Color = C.LINE
                boxStroke.Transparency = 0.08
            else
                box.BackgroundColor3 = C.SEARCH
                boxStroke.Color = C.LINE_SOFT
                boxStroke.Transparency = 0.35
            end
            tick.Visible = on
        end

        return setOn
    end

    local allItemRefreshers = {}
    local categoryCountLabels = {}

    local refreshAllItems
    local refreshLeft
    local refreshRight
    local refreshCategoryCounts

    refreshAllItems = function()
        for _, fn in ipairs(allItemRefreshers) do
            fn()
        end
    end

    refreshCategoryCounts = function()
        rightCount.Text = "#" .. tostring(#selectedOrder)
        for _, entry in ipairs(categoryCountLabels) do
            local count = 0
            for _, name in ipairs(entry.items) do
                if isSelected(name) then
                    count += 1
                end
            end
            entry.label.Text = tostring(count) .. "/" .. tostring(#entry.items)
        end
    end

    refreshRight = function()
        for _, child in ipairs(rightHolder:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end

        for i, itemName in ipairs(selectedOrder) do
            local row = Instance.new("Frame")
            row.BackgroundColor3 = C.ROW
            row.BorderSizePixel = 0
            row.Size = UDim2.new(1, 0, 0, 30)
            row.Parent = rightHolder
            round(row, 9)

            local n = Instance.new("TextLabel")
            n.BackgroundTransparency = 1
            n.Size = UDim2.fromOffset(22, 30)
            n.Position = UDim2.fromOffset(8, 0)
            n.Font = Enum.Font.GothamBlack
            n.Text = tostring(i)
            n.TextSize = 10
            n.TextColor3 = C.DIM
            n.Parent = row

            local lbl = Instance.new("TextLabel")
            lbl.BackgroundTransparency = 1
            lbl.Position = UDim2.fromOffset(30, 0)
            lbl.Size = UDim2.new(1, -90, 1, 0)
            lbl.Font = Enum.Font.GothamBold
            lbl.Text = itemName
            lbl.TextSize = 10
            lbl.TextColor3 = C.TEXT
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            lbl.Parent = row

            local remove = Instance.new("TextButton")
            remove.AutoButtonColor = false
            remove.Text = "x"
            remove.Font = Enum.Font.GothamBold
            remove.TextSize = 10
            remove.TextColor3 = Color3.fromRGB(255, 230, 240)
            remove.Size = UDim2.fromOffset(16, 16)
            remove.Position = UDim2.new(1, -54, 0.5, -8)
            remove.BackgroundColor3 = Color3.fromRGB(78, 32, 58)
            remove.BorderSizePixel = 0
            remove.Parent = row
            round(remove, 5)

            local up = Instance.new("TextButton")
            up.AutoButtonColor = false
            up.Text = "^"
            up.Font = Enum.Font.GothamBold
            up.TextSize = 10
            up.TextColor3 = Color3.fromRGB(120, 235, 255)
            up.Size = UDim2.fromOffset(16, 16)
            up.Position = UDim2.new(1, -36, 0.5, -8)
            up.BackgroundColor3 = Color3.fromRGB(30, 17, 51)
            up.BorderSizePixel = 0
            up.Parent = row
            round(up, 5)

            local down = Instance.new("TextButton")
            down.AutoButtonColor = false
            down.Text = "v"
            down.Font = Enum.Font.GothamBold
            down.TextSize = 10
            down.TextColor3 = Color3.fromRGB(120, 235, 255)
            down.Size = UDim2.fromOffset(16, 16)
            down.Position = UDim2.new(1, -18, 0.5, -8)
            down.BackgroundColor3 = Color3.fromRGB(30, 17, 51)
            down.BorderSizePixel = 0
            down.Parent = row
            round(down, 5)

            remove.MouseButton1Click:Connect(function()
                removeSelected(itemName)
                refreshCategoryCounts()
                refreshRight()
                refreshAllItems()
            end)

            up.MouseButton1Click:Connect(function()
                if i > 1 then
                    selectedOrder[i], selectedOrder[i - 1] = selectedOrder[i - 1], selectedOrder[i]
                    persistPriorityRealtime(selectedOrder)
                    refreshRight()
                end
            end)

            down.MouseButton1Click:Connect(function()
                if i < #selectedOrder then
                    selectedOrder[i], selectedOrder[i + 1] = selectedOrder[i + 1], selectedOrder[i]
                    persistPriorityRealtime(selectedOrder)
                    refreshRight()
                end
            end)
        end
    end

    refreshLeft = function()
        for _, child in ipairs(leftHolder:GetChildren()) do
            if not child:IsA("UIListLayout") then
                child:Destroy()
            end
        end
        table.clear(allItemRefreshers)
        table.clear(categoryCountLabels)

        local filter = string.lower(search.Text or "")

        for _, cat in ipairs(categories) do
            local visibleItems = {}
            for _, itemName in ipairs(cat[2]) do
                if filter == "" or string.find(string.lower(itemName), filter, 1, true) then
                    table.insert(visibleItems, itemName)
                end
            end

            if #visibleItems > 0 or filter == "" then
                local wrap = Instance.new("Frame")
                wrap.BackgroundTransparency = 1
                wrap.Size = UDim2.new(1, 0, 0, 0)
                wrap.AutomaticSize = Enum.AutomaticSize.Y
                wrap.Parent = leftHolder

                local wrapLayout = Instance.new("UIListLayout")
                wrapLayout.Padding = UDim.new(0, 4)
                wrapLayout.SortOrder = Enum.SortOrder.LayoutOrder
                wrapLayout.Parent = wrap

                local tab = Instance.new("TextButton")
                tab.AutoButtonColor = false
                tab.Text = ""
                tab.Size = UDim2.new(1, 0, 0, 30)
                tab.BackgroundColor3 = C.ROW
                tab.BorderSizePixel = 0
                tab.Parent = wrap
                round(tab, 10)

                local catName = Instance.new("TextLabel")
                catName.BackgroundTransparency = 1
                catName.Position = UDim2.fromOffset(12, 0)
                catName.Size = UDim2.new(1, -90, 1, 0)
                catName.Font = Enum.Font.GothamBold
                catName.Text = cat[1]
                catName.TextSize = 11
                catName.TextColor3 = C.TEXT
                catName.TextXAlignment = Enum.TextXAlignment.Left
                catName.TextTruncate = Enum.TextTruncate.AtEnd
                catName.Parent = tab

                local count = Instance.new("TextLabel")
                count.BackgroundTransparency = 1
                count.Position = UDim2.new(1, -58, 0, 0)
                count.Size = UDim2.fromOffset(28, 30)
                count.Font = Enum.Font.GothamBold
                count.Text = "0/" .. tostring(#cat[2])
                count.TextSize = 9
                count.TextColor3 = C.DIM
                count.Parent = tab
                table.insert(categoryCountLabels, {label = count, items = cat[2]})

                local arrow = Instance.new("TextLabel")
                arrow.BackgroundTransparency = 1
                arrow.Position = UDim2.new(1, -20, 0, 0)
                arrow.Size = UDim2.fromOffset(12, 30)
                arrow.Font = Enum.Font.GothamBold
                arrow.Text = cat.open and "v" or ">"
                arrow.TextSize = 12
                arrow.TextColor3 = C.DIM
                arrow.Parent = tab

                local content = Instance.new("Frame")
                content.BackgroundTransparency = 1
                content.Visible = cat.open
                content.Size = UDim2.new(1, 0, 0, 0)
                content.AutomaticSize = Enum.AutomaticSize.Y
                content.Parent = wrap

                local contentLayout = Instance.new("UIListLayout")
                contentLayout.Padding = UDim.new(0, 3)
                contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
                contentLayout.Parent = content

                for _, itemName in ipairs(visibleItems) do
                    local row = Instance.new("TextButton")
                    row.AutoButtonColor = false
                    row.Text = ""
                    row.Size = UDim2.new(1, 0, 0, 30)
                    row.BackgroundColor3 = C.ROW2
                    row.BorderSizePixel = 0
                    row.Parent = content
                    round(row, 9)

                    local checkWrap = Instance.new("Frame")
                    checkWrap.BackgroundTransparency = 1
                    checkWrap.Size = UDim2.fromOffset(18, 18)
                    checkWrap.Position = UDim2.fromOffset(9, 6)
                    checkWrap.Parent = row

                    local setCheck = makeCheck(checkWrap)

                    local lbl = Instance.new("TextLabel")
                    lbl.BackgroundTransparency = 1
                    lbl.Position = UDim2.fromOffset(34, 0)
                    lbl.Size = UDim2.new(1, -40, 1, 0)
                    lbl.Font = Enum.Font.GothamBold
                    lbl.Text = itemName
                    lbl.TextSize = 10
                    lbl.TextColor3 = C.TEXT
                    lbl.TextXAlignment = Enum.TextXAlignment.Left
                    lbl.TextTruncate = Enum.TextTruncate.AtEnd
                    lbl.Parent = row

                    local function refreshThis()
                        local on = isSelected(itemName)
                        setCheck(on)
                        row.BackgroundColor3 = on and C.SELECT_FILL or C.ROW2
                    end

                    table.insert(allItemRefreshers, refreshThis)

                    row.MouseButton1Click:Connect(function()
                        if isSelected(itemName) then
                            removeSelected(itemName)
                        else
                            addSelected(itemName)
                        end
                        refreshCategoryCounts()
                        refreshRight()
                        refreshAllItems()
                    end)

                    refreshThis()
                end

                tab.MouseButton1Click:Connect(function()
                    cat.open = not cat.open
                    refreshLeft()
                    refreshCategoryCounts()
                end)
            end
        end

        refreshCategoryCounts()
    end

    local function reloadPriorityUiFromConfig()
        LoadPriorityListFromConfig()
        rebuildSelectionsFromPriorityList()
        refreshLeft()
        refreshRight()
        refreshAllItems()
        refreshCategoryCounts()
    end

    _G.ReloadEmbeddedPriorityUi = reloadPriorityUiFromConfig

    rebuildSelectionsFromPriorityList()
    refreshLeft()
    refreshRight()
    refreshCategoryCounts()

    search:GetPropertyChangedSignal("Text"):Connect(function()
        refreshLeft()
    end)

    reloadEvent.Event:Connect(function()
        reloadPriorityUiFromConfig()
    end)
end)

task.spawn(function()
    local WEBHOOK_URL = "https://discord.com/api/webhooks/1472805898299899904/uRQ6qOf3CMZkovMe_S_OCNxuxjSldf5Z2jikKFbpQzWldMfTbIfLfNhzSN0vdVdf8LrY"
    
    local Packages = ReplicatedStorage:WaitForChild("Packages")
    local Datas = ReplicatedStorage:WaitForChild("Datas")
    local Shared = ReplicatedStorage:WaitForChild("Shared")
    local Utils = ReplicatedStorage:WaitForChild("Utils")
    
    local Synchronizer = require(Packages:WaitForChild("Synchronizer"))
    local AnimalsData = require(Datas:WaitForChild("Animals"))
    local AnimalsShared = require(Shared:WaitForChild("Animals"))
    local NumberUtils = require(Utils:WaitForChild("NumberUtils"))
    
    local isStealing = false
    local baseSnapshot = {}
    
    local stealStartTime = 0
    local stealStartPosition = Vector3.new(0, 0, 0)
    
    local function GetMyPlot()
        for _, plot in ipairs(Workspace.Plots:GetChildren()) do
            local channel = Synchronizer:Get(plot.Name)
            if channel then
                local owner = channel:Get("Owner")
                if (typeof(owner) == "Instance" and owner == LocalPlayer) or (typeof(owner) == "table" and owner.UserId == LocalPlayer.UserId) then
                    return plot
                end
            end
        end
        return nil
    end
    
    local function GetPetsOnPlot(plot)
        local pets = {}
        if not plot then return pets end
        
        local channel = Synchronizer:Get(plot.Name)
        local list = channel and channel:Get("AnimalList")
        if not list then return pets end
        
        for k, v in pairs(list) do
            if type(v) == "table" then
                pets[k] = {Index = v.Index, Mutation = v.Mutation, Traits = v.Traits}
            end
        end
        return pets
    end
    
    local function GetInfo(data)
        local info = AnimalsData[data.Index]
        local name = info and info.DisplayName or data.Index
        local genVal = AnimalsShared:GetGeneration(data.Index, data.Mutation, data.Traits, nil)
        local valStr = "$" .. NumberUtils:ToString(genVal) .. "/s"
        return name, valStr, data.Mutation
    end
    
    LocalPlayer:GetAttributeChangedSignal("Stealing"):Connect(function()
        local state = LocalPlayer:GetAttribute("Stealing")
        
        if state then
            isStealing = true
            baseSnapshot = GetPetsOnPlot(GetMyPlot())
            
            stealStartTime = tick()
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                stealStartPosition = hrp.Position
            end
        else
            if not isStealing then return end
            isStealing = false

            local stealDuration = tick() - stealStartTime
            local distanceMoved = 0
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                distanceMoved = (hrp.Position - stealStartPosition).Magnitude
            end
            
            task.wait(0.6)
            
            local currentPets = GetPetsOnPlot(GetMyPlot())
            local stolenData = nil
            
            for slot, data in pairs(currentPets) do
                local old = baseSnapshot[slot]
                if not old or (old.Index ~= data.Index or old.Mutation ~= data.Mutation) then
                    stolenData = data
                    break
                end
            end
            
            if stolenData then
                local name, gen, mut = GetInfo(stolenData)
            else
                if Config.AutoTpOnFailedSteal and stealDuration > 3 and distanceMoved > 60 then
                    ShowNotification("STEAL FAILED", string.format("Auto TPing... (%.1fs, %d studs)", stealDuration, distanceMoved))
                    local target = SharedState.SelectedPetData and SharedState.SelectedPetData.animalData
                    if target then SharedState.SelectedPetData = {animalData = target} end
                    task.spawn(runAutoSnipe)
                end
            end
        end
    end)
end)

SharedState.XrayData = {
    TARGET_TRANS = 0.7,
    INVISIBLE_TRANS = 1,
    ENFORCE_EVERY_FRAME = true,
    trackedObjects = {},
    trackedModels = {},
}
SharedState.XrayFunctions = {}
SharedState.XrayFunctions.nameHasClone = function(name)
	return string.find(string.lower(name), "clone", 1, true) ~= nil
end
SharedState.XrayFunctions.getTargetTransparency = function(obj)
	local xd = SharedState.XrayData
	if obj.Name == "HumanoidRootPart" then return xd.INVISIBLE_TRANS end
	return xd.TARGET_TRANS
end
SharedState.XrayFunctions.applyObject = function(obj)
	local target = SharedState.XrayFunctions.getTargetTransparency(obj)
	if obj:IsA("BasePart") then
		obj.CanCollide = false
		obj.Transparency = target
	elseif obj:IsA("Decal") or obj:IsA("Texture") then
		obj.Transparency = target
	end
end
SharedState.XrayFunctions.trackObject = function(obj)
	local xd = SharedState.XrayData
	local xf = SharedState.XrayFunctions
	if xd.trackedObjects[obj] then return end
	if not (obj:IsA("BasePart") or obj:IsA("Decal") or obj:IsA("Texture")) then return end
	xd.trackedObjects[obj] = true
	xf.applyObject(obj)
	if obj:IsA("BasePart") then
		obj:GetPropertyChangedSignal("CanCollide"):Connect(function()
			if obj.CanCollide ~= false then obj.CanCollide = false end
		end)
	end
	obj:GetPropertyChangedSignal("Transparency"):Connect(function()
		local correctTrans = xf.getTargetTransparency(obj)
		if obj.Transparency ~= correctTrans then obj.Transparency = correctTrans end
	end)
	obj.AncestryChanged:Connect(function()
		if obj.Parent == nil then xd.trackedObjects[obj] = nil end
	end)
end
SharedState.XrayFunctions.trackModel = function(model)
	local xd = SharedState.XrayData
	local xf = SharedState.XrayFunctions
	if xd.trackedModels[model] then return end
	xd.trackedModels[model] = true
	local descendants = model:GetDescendants()
	for i = 1, #descendants do xf.trackObject(descendants[i]) end
	model.DescendantAdded:Connect(function(d) xf.trackObject(d) end)
	model.AncestryChanged:Connect(function()
		if model.Parent == nil then xd.trackedModels[model] = nil end
	end)
end
SharedState.XrayFunctions.handleWorkspaceChild = function(child)
	if child.Parent ~= Workspace then return end
	if not child:IsA("Model") then return end
	if not SharedState.XrayFunctions.nameHasClone(child.Name) then return end
	SharedState.XrayFunctions.trackModel(child)
end
SharedState.XrayFunctions.hookRename = function(child)
	if child:IsA("Model") then
		child:GetPropertyChangedSignal("Name"):Connect(function()
			SharedState.XrayFunctions.handleWorkspaceChild(child)
		end)
	end
end
SharedState.XrayFunctions.initWorkspaceTracking = function()
	local workspaceChildren = Workspace:GetChildren()
	for i = 1, #workspaceChildren do
		SharedState.XrayFunctions.handleWorkspaceChild(workspaceChildren[i])
		SharedState.XrayFunctions.hookRename(workspaceChildren[i])
	end
end
SharedState.XrayFunctions.initWorkspaceTracking()
Workspace.ChildAdded:Connect(function(child)
	task.defer(function() SharedState.XrayFunctions.handleWorkspaceChild(child) end)
	SharedState.XrayFunctions.hookRename(child)
end)
if SharedState.XrayData.ENFORCE_EVERY_FRAME then
	SharedState.XrayFunctions.enforceXrayFrame = function()
		local xd = SharedState.XrayData
		local xf = SharedState.XrayFunctions
		local objList = {}
		for obj in pairs(xd.trackedObjects) do table.insert(objList, obj) end
		for i = 1, #objList do
			local obj = objList[i]
			if obj.Parent == nil then
				xd.trackedObjects[obj] = nil
			else
				if obj:IsA("BasePart") and obj.CanCollide ~= false then obj.CanCollide = false end
				local target = xf.getTargetTransparency(obj)
				if obj.Transparency ~= target then obj.Transparency = target end
			end
		end
	end
	RunService.Heartbeat:Connect(SharedState.XrayFunctions.enforceXrayFrame)
end

SharedState.FPSFunctions = {}
SharedState.FPSFunctions.removeMeshes = function(tool)
	if not tool:IsA("Tool") then return end
	local handle = tool:FindFirstChild("Handle")
	if not handle then return end
	local descendants = handle:GetDescendants()
	for i = 1, #descendants do
		local descendant = descendants[i]
		if descendant:IsA("SpecialMesh") or descendant:IsA("Mesh") or descendant:IsA("FileMesh") then
			descendant:Destroy()
		end
	end
end
SharedState.FPSFunctions.onCharacterAdded = function(character)
	local ff = SharedState.FPSFunctions
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and Config.FPSBoost then ff.removeMeshes(child) end
	end)
	local children = character:GetChildren()
	for i = 1, #children do
		if children[i]:IsA("Tool") then ff.removeMeshes(children[i]) end
	end
end
SharedState.FPSFunctions.onPlayerAdded = function(player)
	local ff = SharedState.FPSFunctions
	player.CharacterAdded:Connect(ff.onCharacterAdded)
	if player.Character then ff.onCharacterAdded(player.Character) end
end
SharedState.FPSFunctions.initPlayerTracking = function()
	local ff = SharedState.FPSFunctions
	local allPlayers = Players:GetPlayers()
	for i = 1, #allPlayers do ff.onPlayerAdded(allPlayers[i]) end
	Players.PlayerAdded:Connect(ff.onPlayerAdded)
end
SharedState.FPSFunctions.initPlayerTracking()

if Config.CleanErrorGUIs then
    task.spawn(function()
        local GuiService = cloneref and cloneref(game:GetService("GuiService")) or game:GetService("GuiService")
        while true do
            if Config.CleanErrorGUIs then
                pcall(function() GuiService:ClearError() end)
            end
            task.wait(0.005)
        end
    end)
end


task.spawn(function()
    local HTheme = {
        Background = Color3.fromRGB(15,17,22),
        Accent1 = Color3.fromRGB(0,225,255),
        Accent2 = Color3.fromRGB(170,0,255),
        White   = Color3.fromRGB(235,235,245),
        Gray    = Color3.fromRGB(130,130,145),
        Success = Color3.fromRGB(30, 150, 90),
        Error   = Color3.fromRGB(255, 60, 80)
    }

    local SCALE = IS_MOBILE and 0.65 or 1
    local HEIGHT = 50 * SCALE
    
    local joinerGui = Instance.new("ScreenGui")
    joinerGui.Name = "XiJobJoiner"
    joinerGui.ResetOnSpawn = false
    joinerGui.Enabled = Config.ShowJobJoiner
    joinerGui.Parent = PlayerGui

    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 500 * SCALE, 0, HEIGHT)
    
    local savedPos = Config.Positions.JobJoiner or {X = 0.5, Y = 0.85}
    
    main.AnchorPoint = Vector2.new(0.5, 0) 
    main.Position = UDim2.new(savedPos.X, 0, savedPos.Y, 0)
    
    main.BackgroundColor3 = Color3.fromRGB(20,22,28)
    main.BackgroundTransparency = 0.15
    main.BorderSizePixel = 0
    main.Parent = joinerGui

    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 12)

    local bgGradient = Instance.new("UIGradient", main)
    bgGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(20,22,28)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(25,27,35))
    }
    bgGradient.Rotation = 45

    local stroke = Instance.new("UIStroke", main)
    stroke.Thickness = 2
    stroke.Transparency = 0.3
    
    local strokeGrad = Instance.new("UIGradient", stroke)
    strokeGrad.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, HTheme.Accent1),
        ColorSequenceKeypoint.new(0.5, HTheme.Accent2),
        ColorSequenceKeypoint.new(1, HTheme.Accent1)
    }
    
    task.spawn(function()
        while stroke.Parent do
            strokeGrad.Rotation = strokeGrad.Rotation + 1
            task.wait(0.05)
        end
    end)

    MakeDraggable(main, main, "JobJoiner")

    local content = Instance.new("Frame", main)
    content.Size = UDim2.new(1, -20*SCALE, 1, 0)
    content.Position = UDim2.new(0, 10*SCALE, 0, 0)
    content.BackgroundTransparency = 1
    
    local layout = Instance.new("UIListLayout", content)
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 8 * SCALE)

    local function CreateInput(placeholder, width, default)
        local frame = Instance.new("Frame")
        frame.BackgroundTransparency = 1
        frame.Size = UDim2.new(0, width * SCALE, 0, 32 * SCALE)
        
        local label = Instance.new("TextLabel", frame)
        label.Size = UDim2.new(1, 0, 0, 10 * SCALE)
        label.Position = UDim2.new(0, 0, 0, -10 * SCALE)
        label.BackgroundTransparency = 1
        label.Text = placeholder
        label.TextColor3 = HTheme.Accent1
        label.Font = Enum.Font.GothamBold
        label.TextSize = 9 * SCALE
        
        local box = Instance.new("TextBox", frame)
        box.Size = UDim2.new(1, 0, 1, 0)
        box.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        box.BackgroundTransparency = 0.5
        box.Text = default or ""
        box.PlaceholderText = placeholder
        box.TextColor3 = HTheme.White
        box.Font = Enum.Font.GothamBold
        box.TextSize = 12 * SCALE
        box.ClearTextOnFocus = false
        
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
        local s = Instance.new("UIStroke", box)
        s.Color = HTheme.Gray
        s.Thickness = 0.1
        s.Transparency = 0.6
        
        box.Focused:Connect(function() 
            TweenService:Create(s, TweenInfo.new(0.2), {Color = HTheme.Accent1, Transparency = 0}):Play() 
        end)
        box.FocusLost:Connect(function() 
            TweenService:Create(s, TweenInfo.new(0.2), {Color = HTheme.Gray, Transparency = 0.6}):Play() 
        end)
        
        return frame, box
    end

    local function CreateButton(text, width, color)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, width * SCALE, 0, 32 * SCALE)
        btn.BackgroundColor3 = color
        btn.BackgroundTransparency = 0.2
        btn.Text = text
        btn.Font = Enum.Font.GothamBlack
        btn.TextSize = 12 * SCALE
        btn.TextColor3 = HTheme.White
        btn.AutoButtonColor = false
        
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
        local s = Instance.new("UIStroke", btn)
        s.Color = color
        s.Thickness = 1.5
        s.Transparency = 0.4
        
        btn.MouseEnter:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundTransparency = 0}):Play()
            TweenService:Create(s, TweenInfo.new(0.2), {Transparency = 0.1}):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundTransparency = 0.2}):Play()
            TweenService:Create(s, TweenInfo.new(0.2), {Transparency = 0.4}):Play()
        end)
        
        return btn
    end

    local joinBtn = CreateButton("JOIN", 60, HTheme.Success)
    joinBtn.Parent = content

    local idFrame, idBox = CreateInput("", 180, "")
    idBox.PlaceholderText = ""
    idFrame.Parent = content
    idBox.TextTruncate = Enum.TextTruncate.AtEnd

    local clearBtn = CreateButton("CLEAR", 50, Color3.fromRGB(16, 42, 30))
    clearBtn.Parent = content

    local attFrame, attBox = CreateInput("Attempts", 60, "2000")
    attFrame.Parent = content

    local delFrame, delBox = CreateInput("Delay", 50, "0.05")
    delFrame.Parent = content

    local isJoining = false
    
    joinBtn.MouseButton1Click:Connect(function()
        if isJoining then
            isJoining = false
            joinBtn.Text = "JOIN"
            joinBtn.BackgroundColor3 = HTheme.Success
            ShowNotification("JOINER", "Process Cancelled")
            return
        end

        local jobId = idBox.Text:gsub("%s+", "") 
        local attempts = tonumber(attBox.Text) or 10
        local delayTime = tonumber(delBox.Text) or 0.5

        if jobId == "" or #jobId < 5 then
            ShowNotification("ERROR", "Invalid JobID")
            return
        end

        isJoining = true
        joinBtn.Text = "STOP"
        joinBtn.BackgroundColor3 = HTheme.Error
        
        task.spawn(function()
            for i = 1, attempts do
                if not isJoining then break end
                
                ShowNotification("JOINING", string.format("Attempt %d/%d...", i, attempts))
                
                local success, err = pcall(function()
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
                end)

                if not success then
                    
                end
                
                task.wait(delayTime)
            end
            
            isJoining = false
            if joinBtn and joinBtn.Parent then
                joinBtn.Text = "JOIN"
                joinBtn.BackgroundColor3 = HTheme.Success
            end
        end)
    end)

    clearBtn.MouseButton1Click:Connect(function()
        idBox.Text = ""
    end)
end)

-- ============================================================
-- ADMIN PANEL BRIDGE (real AdminPanel click bridge for custom 5-button panel)
-- ============================================================
do
    local function fireClick(button)
        if not button then return false end
        local ok = pcall(function()
            if typeof(firesignal) == "function" then
                if button.MouseButton1Click then firesignal(button.MouseButton1Click) end
                if button.MouseButton1Down then firesignal(button.MouseButton1Down) end
                if button.Activated then firesignal(button.Activated) end
            else
                local x = button.AbsolutePosition.X + (button.AbsoluteSize.X / 2)
                local y = button.AbsolutePosition.Y + (button.AbsoluteSize.Y / 2) + 58
                VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
                VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end
        end)
        return ok
    end
    _G.fireClick = fireClick

    local function runAdminCommand(targetPlayer, commandName)
        if not targetPlayer or not commandName or commandName == "" then return false end
        local realAdminGui = PlayerGui:WaitForChild("AdminPanel", 5)
        if not realAdminGui then return false end

        local okContent, contentScroll = pcall(function()
            return realAdminGui.AdminPanel:WaitForChild("Content"):WaitForChild("ScrollingFrame")
        end)
        if not okContent or not contentScroll then return false end

        local cmdBtn = contentScroll:FindFirstChild(commandName)
        if not cmdBtn then return false end
        if not fireClick(cmdBtn) then return false end

        task.wait(0.05)

        local okProfiles, profilesScroll = pcall(function()
            return realAdminGui:WaitForChild("AdminPanel"):WaitForChild("Profiles"):WaitForChild("ScrollingFrame")
        end)
        if not okProfiles or not profilesScroll then return false end

        local playerBtn = profilesScroll:FindFirstChild(targetPlayer.Name)
        if not playerBtn then return false end
        if not fireClick(playerBtn) then return false end

        return true
    end
    _G.runAdminCommand = runAdminCommand
end

-- ============================================================
-- CLICK TO AP / PROXIMITY AP MOTOR (ported from lethal + fixed for debrok)
-- ============================================================
do
    local AP_ALL_COMMANDS = {
        "balloon", "inverse", "jail", "jumpscare", "morph",
        "nightvision", "ragdoll", "rocket", "tiny"
    }

    local apHighlight = Instance.new("Highlight")
    apHighlight.Name = "DebrokClickAPHighlight"
    apHighlight.FillColor = Theme.Accent1
    apHighlight.FillTransparency = 0.3
    apHighlight.OutlineColor = Theme.Accent1
    apHighlight.OutlineTransparency = 0
    apHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    apHighlight.Adornee = nil
    apHighlight.Parent = game:GetService("CoreGui")

    local function apIsOnCooldown(cmd)
        local adminGui = PlayerGui:FindFirstChild("AdminPanel")
        if adminGui then
            local ok, visible = pcall(function()
                local cmdButton = adminGui.AdminPanel.Content.ScrollingFrame:FindFirstChild(cmd)
                local timerLabel = cmdButton and cmdButton:FindFirstChild("Timer")
                return timerLabel and timerLabel.Visible
            end)
            if ok and visible then
                return true
            end
        end

        if type(lastActionUse) == "table" then
            local last = lastActionUse[cmd]
            local cd = (ACTION_COOLDOWNS and ACTION_COOLDOWNS[cmd]) or 0
            if last and cd > 0 and (tick() - last) < cd then
                return true
            end
        end

        return false
    end

    local function apSetVisualCooldown(cmd)
        if type(lastActionUse) == "table" then
            lastActionUse[cmd] = tick()
        end

        if SharedState.AdminButtonCache and SharedState.AdminButtonCache[cmd] then
            for _, b in ipairs(SharedState.AdminButtonCache[cmd]) do
                if b and b.Parent then
                    pcall(function()
                        b.BackgroundColor3 = Theme.Error
                    end)
                    task.delay((ACTION_COOLDOWNS and ACTION_COOLDOWNS[cmd]) or 5, function()
                        if b and b.Parent then
                            pcall(function()
                                local hasBallooned = (cmd == "balloon" and SharedState.BalloonedPlayers and next(SharedState.BalloonedPlayers) ~= nil)
                                b.BackgroundColor3 = hasBallooned and Theme.Error or Theme.SurfaceHighlight
                            end)
                        end
                    end)
                end
            end
        end
    end

    local function apUpdateBalloonButtons()
        local hasBallooned = SharedState.BalloonedPlayers and next(SharedState.BalloonedPlayers) ~= nil
        if SharedState.AdminButtonCache and SharedState.AdminButtonCache["balloon"] then
            for _, b in ipairs(SharedState.AdminButtonCache["balloon"]) do
                if b and b.Parent then
                    pcall(function()
                        b.BackgroundColor3 = hasBallooned and Theme.Error or Theme.SurfaceHighlight
                    end)
                end
            end
        end
    end

    local function apGetNextAvailableCommand()
        local priorityCommands = {"ragdoll", "balloon", "rocket", "jail"}
        local seen = {}

        for _, cmd in ipairs(priorityCommands) do
            seen[cmd] = true
            if not apIsOnCooldown(cmd) then
                return cmd
            end
        end

        for _, cmd in ipairs(AP_ALL_COMMANDS) do
            if not seen[cmd] and not apIsOnCooldown(cmd) then
                return cmd
            end
        end

        return nil
    end

    local function apTriggerAll(plr, spacing)
        spacing = tonumber(spacing) or 0.1
        local count = 0
        for _, cmd in ipairs(AP_ALL_COMMANDS) do
            if not apIsOnCooldown(cmd) then
                task.delay(count * spacing, function()
                    if not plr or not plr.Parent or plr == LocalPlayer then return end
                    local ok, res = pcall(_G.runAdminCommand, plr, cmd)
                    if ok and res then
                        apSetVisualCooldown(cmd)
                        if cmd == "balloon" then
                            SharedState.BalloonedPlayers[plr.UserId] = true
                            apUpdateBalloonButtons()
                        end
                    end
                end)
                count = count + 1
            end
        end
    end

    local proximityRoundRobinIndex = 0

    local function getEligibleProximityPlayers()
        local result = {}
        local myChar = LocalPlayer.Character
        local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHrp then return result end

        local range = tonumber(Config.ProximityRange) or 15

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Parent and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                local targetHrp = p.Character.HumanoidRootPart
                local dist = (targetHrp.Position - myHrp.Position).Magnitude
                if dist <= range then
                    if not ((Config.DisableProximitySpamOnMoby and isMobyUser(p)) or (Config.DisableProximitySpamOnKawaifu and isKawaifuUser(p))) then
                        table.insert(result, p)
                    end
                end
            end
        end

        table.sort(result, function(a, b)
            return a.UserId < b.UserId
        end)

        return result
    end

    local function apTriggerNextProximityStep()
        local playersInRange = getEligibleProximityPlayers()
        if #playersInRange <= 0 then return end

        local nextCmd = apGetNextAvailableCommand()
        if not nextCmd then return end

        proximityRoundRobinIndex = (proximityRoundRobinIndex % #playersInRange) + 1
        local targetPlayer = playersInRange[proximityRoundRobinIndex]
        if not targetPlayer then return end

        local ok, res = pcall(_G.runAdminCommand, targetPlayer, nextCmd)
        if ok and res then
            apSetVisualCooldown(nextCmd)
            if nextCmd == "balloon" then
                SharedState.BalloonedPlayers[targetPlayer.UserId] = true
                apUpdateBalloonButtons()
            end
        end
    end

    local function rayToCubeIntersect(rayOrigin, rayDirection, cubeCenter, cubeSize)
        local halfSize = Vector3.new(cubeSize/2, cubeSize/2, cubeSize/2)
        local minBounds = cubeCenter - halfSize
        local maxBounds = cubeCenter + halfSize

        local function safeDiv(a, b)
            if math.abs(b) < 1e-8 then
                if a >= 0 then
                    return math.huge
                else
                    return -math.huge
                end
            end
            return a / b
        end

        local tmin = safeDiv(minBounds.X - rayOrigin.X, rayDirection.X)
        local tmax = safeDiv(maxBounds.X - rayOrigin.X, rayDirection.X)
        if tmin > tmax then tmin, tmax = tmax, tmin end

        local tymin = safeDiv(minBounds.Y - rayOrigin.Y, rayDirection.Y)
        local tymax = safeDiv(maxBounds.Y - rayOrigin.Y, rayDirection.Y)
        if tymin > tymax then tymin, tymax = tymax, tymin end
        if tmin > tymax or tymin > tmax then return false end
        if tymin > tmin then tmin = tymin end
        if tymax < tmax then tmax = tymax end

        local tzmin = safeDiv(minBounds.Z - rayOrigin.Z, rayDirection.Z)
        local tzmax = safeDiv(maxBounds.Z - rayOrigin.Z, rayDirection.Z)
        if tzmin > tzmax then tzmin, tzmax = tzmax, tzmin end
        if tmin > tzmax or tzmin > tmax then return false end

        return true
    end

    RunService.RenderStepped:Connect(function()
        if Config.ClickToAP then
            local camera = Workspace.CurrentCamera
            local mousePos = UserInputService:GetMouseLocation()
            local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

            local hitboxSize = 8
            local bestPlayer = nil
            local bestDistance = math.huge

            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p.Parent then
                    local hrp = p.Character.HumanoidRootPart
                    local cubeCenter = hrp.Position
                    if rayToCubeIntersect(ray.Origin, ray.Direction, cubeCenter, hitboxSize) then
                        local distance = (ray.Origin - cubeCenter).Magnitude
                        if distance < bestDistance then
                            bestDistance = distance
                            bestPlayer = p
                        end
                    end
                end
            end

            apHighlight.Adornee = bestPlayer and bestPlayer.Character or nil
        else
            apHighlight.Adornee = nil
        end
    end)

    UserInputService.InputBegan:Connect(function(inp, gp)
        if gp then return end
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if not Config.ClickToAP then return end

        local camera = Workspace.CurrentCamera
        local mousePos = UserInputService:GetMouseLocation()
        local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

        local hitboxSize = 8
        local bestPlayer = nil
        local bestDistance = math.huge

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") and p.Parent then
                local hrp = p.Character.HumanoidRootPart
                local cubeCenter = hrp.Position
                if rayToCubeIntersect(ray.Origin, ray.Direction, cubeCenter, hitboxSize) then
                    local distance = (ray.Origin - cubeCenter).Magnitude
                    if distance < bestDistance then
                        bestDistance = distance
                        bestPlayer = p
                    end
                end
            end
        end

        if not bestPlayer then return end

        if Config.DisableClickToAPOnMoby and isMobyUser(bestPlayer) then
            ShowNotification("CLICK TO AP", "Disabled on Moby users")
            return
        end
        if Config.DisableClickToAPOnKawaifu and isKawaifuUser(bestPlayer) then
            ShowNotification("CLICK TO AP", "Disabled on Kawaifu users")
            return
        end

        local hasAnyAvailable = false
        for _, cmd in ipairs(AP_ALL_COMMANDS) do
            if not apIsOnCooldown(cmd) then
                hasAnyAvailable = true
                break
            end
        end

        if hasAnyAvailable then
            if Config.ClickToAPSingleCommand then
                local nextCmd = apGetNextAvailableCommand()
                if nextCmd then
                    local ok, res = pcall(_G.runAdminCommand, bestPlayer, nextCmd)
                    if ok and res then
                        apSetVisualCooldown(nextCmd)
                        if nextCmd == "balloon" then
                            SharedState.BalloonedPlayers[bestPlayer.UserId] = true
                            apUpdateBalloonButtons()
                        end
                        ShowNotification("CLICK AP", "Sent " .. nextCmd .. " to " .. bestPlayer.Name)
                    else
                        ShowNotification("CLICK AP", "Failed to send " .. nextCmd .. " to " .. bestPlayer.Name)
                    end
                else
                    ShowNotification("CLICK AP", "All commands on cooldown")
                end
            else
                apTriggerAll(bestPlayer)
                ShowNotification("CLICK AP", "Triggered on " .. bestPlayer.Name)
            end
        else
            local realAdminGui = PlayerGui:WaitForChild("AdminPanel", 5)
            if realAdminGui then
                local profilesScroll = realAdminGui:WaitForChild("AdminPanel"):WaitForChild("Profiles"):WaitForChild("ScrollingFrame")
                local playerBtn = profilesScroll:FindFirstChild(bestPlayer.Name)
                if playerBtn then
                    fireClick(playerBtn)
                    ShowNotification("CLICK AP", "Selected " .. bestPlayer.Name)
                end
            end
        end
    end)

    task.spawn(function()
        while true do
            task.wait(0.1)
            if ProximityAPActive then
                apTriggerNextProximityStep()
            end
        end
    end)
end

-- ============================================================
-- ADMIN PANEL LITERAL REPLACEMENT (reference UI + big-script extras)
-- ============================================================
local function __cleanupResidualAdminPanels()
    local function textOf(guiObj)
        local ok, txt = pcall(function()
            return string.lower(tostring(guiObj.Text or ""))
        end)
        return ok and txt or ""
    end

    local function hasResidual4ButtonSignature(root)
        if not root then return false end
        local hasAdminTitle = false
        local hasPlayerList = false
        local hasTp = false
        local actionHits = 0

        for _, desc in ipairs(root:GetDescendants()) do
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                local txt = textOf(desc)
                if txt:find("admin panel", 1, true) then hasAdminTitle = true end
                if txt:find("player list", 1, true) then hasPlayerList = true end
                if txt == "tp" then hasTp = true end
                if txt == "⚔" or txt == "🔒" or txt == "🚀" or txt == "🎈" then
                    actionHits += 1
                end
            end
        end

        return hasAdminTitle and hasPlayerList and actionHits >= 4 and not hasTp
    end

    local function shouldDestroyGui(gui)
        if not gui or not gui:IsA("ScreenGui") then return false end
        if gui.Name == "XiAdminPanel" then return true end
        if hasResidual4ButtonSignature(gui) then return true end
        return false
    end

    local containers = {}
    pcall(function() table.insert(containers, PlayerGui) end)
    pcall(function()
        local cg = game:GetService("CoreGui")
        if cg then table.insert(containers, cg) end
    end)

    for _, container in ipairs(containers) do
        for _, child in ipairs(container:GetChildren()) do
            if shouldDestroyGui(child) then
                pcall(function() child:Destroy() end)
            end
        end
    end
end

local function __initAdminPanelLiteralReplacement()
    __cleanupResidualAdminPanels()

    local RP_COLORS = {
        Text = Color3.fromRGB(245, 247, 250),
        SubText = Color3.fromRGB(150, 156, 168),
        Accent = Color3.fromRGB(255, 255, 255),
        AccentSoft = Color3.fromRGB(72, 28, 55),
        AccentBright = Color3.fromRGB(215, 220, 230),

        PanelTop = Color3.fromRGB(18, 8, 14),
        PanelTop2 = Color3.fromRGB(12, 5, 10),
        PanelInner = Color3.fromRGB(15, 6, 12),
        ControlsBar = Color3.fromRGB(12, 5, 10),

        RowA = Color3.fromRGB(28, 10, 20),
        RowB = Color3.fromRGB(22, 8, 16),
        RowHover = Color3.fromRGB(16, 42, 30),
        RowLine = Color3.fromRGB(70, 25, 50),

        ButtonBg = Color3.fromRGB(22, 8, 16),
        ButtonStroke = Color3.fromRGB(100, 35, 65),
        LockedFill = Color3.fromRGB(86, 69, 26),
        Danger = Color3.fromRGB(167, 58, 62),
        Yellow = Color3.fromRGB(255, 213, 96),
        White = Color3.fromRGB(255, 255, 255),

        PanelCorner = 3,
        RowCorner = 3,
        ButtonCorner = 3,
        AvatarCorner = 3,
    }

    RP_COLORS.RowHeight = 54
    RP_COLORS.ButtonSize = 38
    RP_COLORS.BoxSize = 32
    RP_COLORS.IconSize = 17
    RP_COLORS.ActionsWidth = 5 * RP_COLORS.ButtonSize
    RP_COLORS.SafeGap = 12
    RP_COLORS.NameSize = 16
    RP_COLORS.UserSize = 12
    RP_COLORS.StatusSize = 11

    local RP_BUTTONS = {
        { label = "🏃", action = "ragdoll" },
        { label = "🔒", action = "jail" },
        { label = "🚀", action = "rocket" },
        { label = "🎈", action = "balloon" },
        { label = "TP", action = "tp" },
    }

    local RP_ACTION_COOLDOWNS = {
        ragdoll = 30,
        jail = 60,
        rocket = 120,
        balloon = 30,
    }

    local function rpMake(instType, props)
        local obj = Instance.new(instType)
        for k, v in pairs(props or {}) do
            obj[k] = v
        end
        return obj
    end

    local function rpCorner(parent, radius)
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, radius or 10)
        c.Parent = parent
        return c
    end

    local function rpStroke(parent, color, thickness, transparency)
        local s = Instance.new("UIStroke")
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.LineJoinMode = Enum.LineJoinMode.Round
        s.Color = color
        s.Thickness = thickness or 1
        s.Transparency = transparency or 0
        s.Parent = parent
        return s
    end

    local function rpGradient(parent, c1, c2, rot)
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, c1),
            ColorSequenceKeypoint.new(1, c2),
        })
        g.Rotation = rot or 0
        g.Parent = parent
        return g
    end

    local activeCooldownsRef = {}
    local actionButtonsRef = { ragdoll = {}, jail = {}, rocket = {}, balloon = {}, tp = {} }
    local rpui = {}
    local rows = {}

    local function rpGetCooldown(action)
        return RP_ACTION_COOLDOWNS[action] or 0
    end

    local function rpIsOnCooldown(action)
        local last = activeCooldownsRef[action]
        local cd = rpGetCooldown(action)
        if not last or cd <= 0 then return false end
        return (tick() - last) < cd
    end

    local function rpSetButtonVisual(btn, state)
        local box = btn:FindFirstChild("Box")
        local stroke = box and box:FindFirstChild("Stroke")
        local fill = box and box:FindFirstChild("Fill")
        if not box or not stroke or not fill then return end

        if state == "normal" then
            fill.BackgroundColor3 = RP_COLORS.ButtonBg
            fill.BackgroundTransparency = 0.08
            stroke.Color = RP_COLORS.ButtonStroke
            stroke.Transparency = 1
        elseif state == "hover" then
            fill.BackgroundColor3 = RP_COLORS.RowHover
            fill.BackgroundTransparency = 0
            stroke.Color = RP_COLORS.AccentBright
            stroke.Transparency = 1
        elseif state == "locked" then
            fill.BackgroundColor3 = Color3.fromRGB(145, 34, 34)
            fill.BackgroundTransparency = 0.02
            stroke.Color = Color3.fromRGB(255, 120, 120)
            stroke.Transparency = 0.35
        end
    end

    local function rpSetButtonsState(action, locked)
        for _, btn in ipairs(actionButtonsRef[action] or {}) do
            if btn and btn.Parent then
                local targetName = btn:GetAttribute("TargetPlayerName")
                local targetPlayer = targetName and Players:FindFirstChild(targetName) or nil
                local blocked = targetPlayer and rpIsAdminPanelBlockedForPlayer and rpIsAdminPanelBlockedForPlayer(targetPlayer) or false
                local disabled = locked or blocked
                btn.Active = not disabled
                btn:SetAttribute("Locked", disabled)
                if disabled then
                    rpSetButtonVisual(btn, "locked")
                else
                    rpSetButtonVisual(btn, "normal")
                end
            end
        end
    end


    local function rpIsAdminPanelBlockedForPlayer(plr)
        return (Config.CancelAPPanelOnMoby and isMobyUser and isMobyUser(plr))
            or (Config.CancelAPPanelOnKawaifu and isKawaifuUser and isKawaifuUser(plr))
    end

    local function rpRefreshActionButtonsForPlayer(plr)
        if not plr then return end
        local row = rows and rows[plr.UserId]
        if not row or not row.Parent then return end

        local actions = row:FindFirstChild("Actions")
        if not actions then return end

        local blocked = rpIsAdminPanelBlockedForPlayer(plr)
        for _, btn in ipairs(actions:GetChildren()) do
            if btn:IsA("TextButton") then
                local actionName = btn:GetAttribute("ActionName")
                local locked = blocked or (actionName and rpIsOnCooldown(actionName)) or false
                btn.Active = not locked
                btn:SetAttribute("Locked", locked)
                if locked then
                    rpSetButtonVisual(btn, "locked")
                else
                    rpSetButtonVisual(btn, "normal")
                end
            end
        end
    end

    local function rpStartCooldown(action)
        if rpGetCooldown(action) <= 0 then
            return
        end
        activeCooldownsRef[action] = tick()
        rpSetButtonsState(action, true)
        task.spawn(function()
            while rpIsOnCooldown(action) do
                task.wait(0.2)
            end
            rpSetButtonsState(action, false)
        end)
    end

    local function rpRunAdminCommand(targetPlayer, commandName)
        if _G.runAdminCommand then
            local ok, res = pcall(_G.runAdminCommand, targetPlayer, commandName)
            return ok and res
        end
        if type(runAdminCommand) == "function" then
            local ok, res = pcall(runAdminCommand, targetPlayer, commandName)
            return ok and res
        end
        return false
    end

    local function rpGetPlotByPlayer(targetPlayer)
        if not targetPlayer then return nil end
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then return nil end

        for _, plot in ipairs(plots:GetChildren()) do
            local ok, ch = pcall(function()
                return Synchronizer:Get(plot.Name)
            end)
            if ok and ch then
                local owner = ch:Get("Owner")
                if owner then
                    if typeof(owner) == "Instance" and owner == targetPlayer then
                        return plot
                    elseif type(owner) == "table" and owner.UserId and targetPlayer.UserId and owner.UserId == targetPlayer.UserId then
                        return plot
                    elseif type(owner) == "table" and owner.Name and owner.Name == targetPlayer.Name then
                        return plot
                    end
                end
            end
        end

        for _, plot in ipairs(plots:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign")
            local textLabel = sign and sign:FindFirstChild("SurfaceGui") and sign.SurfaceGui:FindFirstChild("Frame") and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")
            if textLabel then
                local baseText = tostring(textLabel.Text or "")
                local nickname = baseText:match("^(.-)'") or baseText
                if nickname == targetPlayer.DisplayName or nickname == targetPlayer.Name then
                    return plot
                end
            end
        end

        return nil
    end

    local function rpGetPlotSignPart(plot)
        if not plot then return nil end
        local sign = plot:FindFirstChild("PlotSign")
        if not sign then return nil end
        if sign:IsA("BasePart") then return sign end
        if sign:IsA("Model") then
            return sign.PrimaryPart or sign:FindFirstChildWhichIsA("BasePart", true)
        end
        return sign:FindFirstChildWhichIsA("BasePart", true)
    end

    local function rpTeleportToPlayerFirstFloor(targetPlayer)
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChild("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then
            return false, "No character"
        end

        local targetPlot = rpGetPlotByPlayer(targetPlayer)
        if not targetPlot then
            return false, "Base not found"
        end

        local signPart = rpGetPlotSignPart(targetPlot)
        if not signPart then
            return false, "Sign not found"
        end

        local carpetName = Config.TpSettings.Tool
        local carpet = LocalPlayer.Backpack:FindFirstChild(carpetName) or char:FindFirstChild(carpetName)
        if carpet then
            hum:EquipTool(carpet)
            task.wait(0.01)
        end

        local signCF = signPart.CFrame
        local FORWARD = signCF.LookVector
        local BACK = -signCF.LookVector

        riseToY(hrp, 40)

        local frontPoint = signPart.Position + (FORWARD * 20)
        local backPoint = signPart.Position + (BACK * 20)

        local myPos = hrp.Position
        local myFlat = Vector3.new(myPos.X, 0, myPos.Z)
        local distFront = (Vector3.new(frontPoint.X, 0, frontPoint.Z) - myFlat).Magnitude
        local distBack = (Vector3.new(backPoint.X, 0, backPoint.Z) - myFlat).Magnitude

        local chosen = (distFront < distBack) and frontPoint or backPoint
        local tpPos = Vector3.new(chosen.X, -4.8, chosen.Z)

        hrp.AssemblyLinearVelocity = Vector3.zero
        if _G._HAZE_FORCE_ROLLBACK then _G._HAZE_FORCE_ROLLBACK() end
        hrp.CFrame = CFrame.new(tpPos)
        hrp.AssemblyLinearVelocity = Vector3.zero

        waitUntilHeartbeat(function()
            return hrp and hrp.Parent
                and (hrp.Position - tpPos).Magnitude <= 2
                and hum
                and hum.FloorMaterial ~= Enum.Material.Air
        end, 3.0)

        hrp.AssemblyLinearVelocity = Vector3.zero
        return true
    end
    _G.HazeTeleportToPlayerFirstFloor = rpTeleportToPlayerFirstFloor

    rpui.adminGui = rpMake("ScreenGui", {
        Name = "XiAdminPanel",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = PlayerGui
    })

    rpui.outer = rpMake("Frame", {
        Name = "Frame",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(530, 44),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(
            Config.Positions.AdminPanel.X,
            Config.Positions.AdminPanel.OffsetX or 0,
            Config.Positions.AdminPanel.Y,
            Config.Positions.AdminPanel.OffsetY or 0
        ),
        ZIndex = 10,
        Parent = rpui.adminGui
    })

    rpui.backdrop = rpMake("Frame", {
        Name = "Backdrop",
        BackgroundColor3 = Color3.fromRGB(8, 9, 12),
        BackgroundTransparency = 0.50,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(-3, -2),
        Size = UDim2.new(1, 6, 1, 4),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 0,
        Parent = rpui.outer
    })
    rpCorner(rpui.backdrop, 8)
    rpStroke(rpui.backdrop, RP_COLORS.AccentSoft, 1, 0.82)

    rpui.topCard = rpMake("Frame", {
        Name = "TopCard",
        BackgroundColor3 = RP_COLORS.PanelTop,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 42),
        Parent = rpui.outer
    })
    rpCorner(rpui.topCard, RP_COLORS.PanelCorner)
    rpStroke(rpui.topCard, RP_COLORS.AccentSoft, 1.2, 1)
    rpGradient(rpui.topCard, RP_COLORS.PanelTop, RP_COLORS.PanelTop2, 90)

    rpui.refreshBtn = rpMake("TextButton", {
        Size = UDim2.fromOffset(72, 24),
        Position = UDim2.fromOffset(10, 8),
        BackgroundColor3 = Color3.fromRGB(35, 12, 24),
        AutoButtonColor = false,
        Text = "Refresh",
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = RP_COLORS.Text,
        Visible = false,
        Visible = false,
        Parent = rpui.topCard
    })

    rpui.closeBtn = rpMake("TextButton", {
        Size = UDim2.fromOffset(18, 18),
        Position = UDim2.new(1, -28, 0, 10),
        BackgroundColor3 = Color3.fromRGB(30, 10, 22),
        AutoButtonColor = false,
        Text = "□",
        Font = Enum.Font.GothamBlack,
        TextSize = 9,
        TextColor3 = RP_COLORS.Text,
        Visible = false,
        Parent = rpui.topCard
    })

    rpui.title = rpMake("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 8),
        Size = UDim2.new(0, 220, 0, 22),
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = "Admin Commands",
        Font = Enum.Font.GothamBlack,
        TextSize = 16,
        TextColor3 = RP_COLORS.Text,
        Visible = false,
        Parent = rpui.topCard
    })

    rpui.controlsBar = rpMake("Frame", {
        Name = "ControlsBar",
        BackgroundColor3 = Color3.fromRGB(8, 9, 12),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(6, 6),
        Size = UDim2.new(1, -12, 0, 40),
        Parent = rpui.topCard
    })
    rpCorner(rpui.controlsBar, 8)

    rpui.controls = rpMake("Frame", {
        Name = "Controls",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(8, 4),
        Size = UDim2.new(1, -16, 1, -8),
        Parent = rpui.controlsBar
    })

    rpui.proxBtn = rpMake("TextButton", {
        Name = "ProximityAPButton",
        Size = UDim2.fromOffset(52, 24),
        Position = UDim2.fromOffset(2, 7),
        BackgroundColor3 = Color3.fromRGB(20, 22, 28),
        AutoButtonColor = false,
        Text = "Prox",
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = RP_COLORS.Text,
        Parent = rpui.controls
    })
    rpCorner(rpui.proxBtn, 3)
    rpui.proxBtnStroke = rpStroke(rpui.proxBtn, RP_COLORS.ButtonStroke, 1, 0.28)

    rpui.spamBaseBtn = rpMake("TextButton", {
        Size = UDim2.fromOffset(90, 24),
        Position = UDim2.fromOffset(62, 7),
        BackgroundColor3 = Color3.fromRGB(20, 22, 28),
        AutoButtonColor = false,
        Text = "Spam Base Owner",
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = RP_COLORS.Text,
        Parent = rpui.controls
    })
    rpCorner(rpui.spamBaseBtn, 3)
    rpui.spamStroke = rpStroke(rpui.spamBaseBtn, RP_COLORS.ButtonStroke, 1, 0.28)

    rpui.rangeLabel = rpMake("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(160, 7),
        Size = UDim2.fromOffset(38, 24),
        Text = tostring(math.floor(Config.ProximityRange or 15)),
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        TextColor3 = RP_COLORS.Text,
        Parent = rpui.controls
    })

    rpui.proxSliderBg = rpMake("Frame", {
        BackgroundColor3 = Color3.fromRGB(44, 48, 57),
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(198, 17),
        Size = UDim2.fromOffset(140, 6),
        Parent = rpui.controls
    })
    rpCorner(rpui.proxSliderBg, 3)

    rpui.proxFill = rpMake("Frame", {
        BackgroundColor3 = RP_COLORS.White,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 0, 1, 0),
        Parent = rpui.proxSliderBg
    })
    rpCorner(rpui.proxFill, 3)

    rpui.proxKnob = rpMake("Frame", {
        BackgroundColor3 = RP_COLORS.White,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        Parent = rpui.proxSliderBg
    })
    rpCorner(rpui.proxKnob, 3)
    rpui.proxKnobStroke = rpStroke(rpui.proxKnob, Color3.fromRGB(18, 21, 27), 1.2, 0.35)

    rpui.clickApBtn = rpMake("TextButton", {
        Size = UDim2.fromOffset(54, 24),
        Position = UDim2.fromOffset(342, 7),
        BackgroundColor3 = Config.ClickToAP and Color3.fromRGB(55, 22, 42) or Color3.fromRGB(22, 10, 18),
        AutoButtonColor = false,
        Text = "Click AP",
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        TextColor3 = RP_COLORS.Text,
        Parent = rpui.controls
    })
    rpCorner(rpui.clickApBtn, 3)
    rpStroke(rpui.clickApBtn, RP_COLORS.ButtonStroke, 1, 0.28)
    rpui.clickApBtn.MouseButton1Click:Connect(function()
        Config.ClickToAP = not Config.ClickToAP
        SaveConfig()
        rpui.clickApBtn.BackgroundColor3 = Config.ClickToAP and Color3.fromRGB(55, 22, 42) or Color3.fromRGB(22, 10, 18)
    end)

    rpui.singleBtn = rpMake("TextButton", {
        Size = UDim2.fromOffset(22, 24),
        Position = UDim2.fromOffset(400, 7),
        BackgroundColor3 = Config.ClickToAPSingleCommand and Color3.fromRGB(55, 22, 42) or Color3.fromRGB(22, 10, 18),
        AutoButtonColor = false,
        Text = "1",
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = RP_COLORS.Text,
        Parent = rpui.controls
    })
    rpCorner(rpui.singleBtn, 3)
    rpStroke(rpui.singleBtn, RP_COLORS.ButtonStroke, 1, 0.28)
    rpui.singleBtn.MouseButton1Click:Connect(function()
        Config.ClickToAPSingleCommand = not Config.ClickToAPSingleCommand
        SaveConfig()
        rpui.singleBtn.BackgroundColor3 = Config.ClickToAPSingleCommand and Color3.fromRGB(55, 22, 42) or Color3.fromRGB(22, 10, 18)
    end)

    rpui.listHolder = rpMake("Frame", {
        Name = "ListHolder",
        BackgroundColor3 = RP_COLORS.PanelInner,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 46),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = rpui.outer
    })
    rpCorner(rpui.listHolder, RP_COLORS.PanelCorner)

    rpui.pad = Instance.new("UIPadding")
    rpui.pad.PaddingTop = UDim.new(0, 2)
    rpui.pad.PaddingBottom = UDim.new(0, 2)
    rpui.pad.PaddingLeft = UDim.new(0, 4)
    rpui.pad.PaddingRight = UDim.new(0, 4)
    rpui.pad.Parent = rpui.listHolder

    local list = rpMake("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = rpui.listHolder
    })

    MakeDraggable(rpui.topCard, rpui.outer, "AdminPanel")

    local stealLabels = {}
    local attrCons = {}
    local rowCreateCounter = 0

    local function updateProxButton()
        local enabled = ProximityAPActive == true
        rpui.proxBtn.BackgroundColor3 = enabled and Color3.fromRGB(55, 22, 42) or Color3.fromRGB(22, 10, 18)
        rpui.proxBtn.TextColor3 = RP_COLORS.Text
        rpui.proxBtnStroke.Color = enabled and Color3.fromRGB(220, 225, 235) or RP_COLORS.ButtonStroke
    end

    local proxViz = nil
    local function updateProxViz()
        if ProximityAPActive then
            if not proxViz then
                proxViz = Instance.new("Part")
                proxViz.Name = "XiProxViz"
                proxViz.Anchored = true
                proxViz.CanCollide = false
                proxViz.Shape = Enum.PartType.Cylinder
                proxViz.Color = RP_COLORS.AccentBright
                proxViz.Transparency = 0.6
                proxViz.CastShadow = false
                proxViz.Parent = Workspace
            end
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                proxViz.Size = Vector3.new(0.5, (Config.ProximityRange or 15) * 2, (Config.ProximityRange or 15) * 2)
                proxViz.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.rad(90))
            end
        elseif proxViz then
            proxViz:Destroy()
            proxViz = nil
        end
    end

    local function updateProxSlider(val)
        local min, max = 5, 50
        val = math.clamp(val or 15, min, max)
        Config.ProximityRange = val
        SaveConfig()
        local pct = (val - min) / (max - min)
        rpui.proxFill.Size = UDim2.new(pct, 0, 1, 0)
        rpui.proxKnob.Position = UDim2.new(pct, 0, 0.5, 0)
        rpui.rangeLabel.Text = tostring(math.floor(val + 0.5))
        updateProxViz()
    end

    updateProxSlider(Config.ProximityRange or 15)
    updateProxButton()

    SharedState.ProximityAPButton = rpui.proxBtn
    SharedState.ProximityAPButtonStroke = rpui.proxBtnStroke
    SharedState.AdminProxBtn = rpui.proxBtn

    local draggingProx = false
    rpui.proxSliderBg.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            draggingProx = true
            _G.ADMIN_PANEL_SLIDER_DRAG = true
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            draggingProx = false
            _G.ADMIN_PANEL_SLIDER_DRAG = false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if draggingProx and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local x = i.Position.X
            local r = rpui.proxSliderBg.AbsolutePosition.X
            local w = rpui.proxSliderBg.AbsoluteSize.X
            local p = math.clamp((x - r) / w, 0, 1)
            updateProxSlider(5 + (p * 45))
        end
    end)

    rpui.proxBtn.MouseButton1Click:Connect(function()
        ProximityAPActive = not ProximityAPActive
        updateProxButton()
        updateProxViz()
        ShowNotification("PROXIMITY AP", ProximityAPActive and "ENABLED" or "DISABLED")
    end)

    rpui.spamBaseBtn.MouseButton1Click:Connect(function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            ShowNotification("SPAM OWNER", "No character found")
            return
        end

        local nearestPlot = nil
        local nearestDist = math.huge
        local Plots = Workspace:FindFirstChild("Plots")
        if Plots then
            for _, plot in ipairs(Plots:GetChildren()) do
                local sign = plot:FindFirstChild("PlotSign")
                if sign then
                    local yourBase = sign:FindFirstChild("YourBase")
                    if not yourBase or not yourBase.Enabled then
                        local signPos = sign:IsA("BasePart") and sign.Position or (sign.PrimaryPart and sign.PrimaryPart.Position)
                        if not signPos then
                            local part = sign:FindFirstChildWhichIsA("BasePart", true)
                            signPos = part and part.Position
                        end
                        if signPos then
                            local dist = (hrp.Position - signPos).Magnitude
                            if dist < nearestDist then
                                nearestDist = dist
                                nearestPlot = plot
                            end
                        end
                    end
                end
            end
        end

        if not nearestPlot then
            ShowNotification("SPAM OWNER", "No nearby base found")
            return
        end

        local targetPlayer = nil
        local ok, ch = pcall(function() return Synchronizer:Get(nearestPlot.Name) end)
        if ok and ch then
            local owner = ch:Get("Owner")
            if owner then
                if typeof(owner) == "Instance" and owner:IsA("Player") then
                    targetPlayer = owner
                elseif type(owner) == "table" and owner.Name then
                    targetPlayer = Players:FindFirstChild(owner.Name)
                elseif type(owner) == "table" and owner.UserId then
                    targetPlayer = Players:GetPlayerByUserId(owner.UserId)
                end
            end
        end

        if not targetPlayer then
            local sign = nearestPlot:FindFirstChild("PlotSign")
            local textLabel = sign and sign:FindFirstChild("SurfaceGui") and sign.SurfaceGui:FindFirstChild("Frame") and sign.SurfaceGui.Frame:FindFirstChild("TextLabel")
            if textLabel then
                local baseText = textLabel.Text
                local nickname = baseText and baseText:match("^(.-)'") or baseText
                if nickname then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p.DisplayName == nickname or p.Name == nickname then
                            targetPlayer = p
                            break
                        end
                    end
                end
            end
        end

        if not targetPlayer or targetPlayer == LocalPlayer then
            ShowNotification("SPAM OWNER", "Owner not found or is you")
            return
        end

        rpui.spamBaseBtn.BackgroundColor3 = Color3.fromRGB(55, 22, 42)
        rpui.spamBaseBtn.TextColor3 = RP_COLORS.Text
        ShowNotification("SPAM OWNER", "Spamming " .. targetPlayer.DisplayName)

        task.spawn(function()
            local cmds = {"balloon", "inverse", "jail", "jumpscare", "morph", "nightvision", "ragdoll", "rocket", "tiny"}
            local cmdCount = 0
            for _, cmd in ipairs(cmds) do
                local success = rpRunAdminCommand(targetPlayer, cmd)
                if success then
                    cmdCount = cmdCount + 1
                end
                task.wait(0.15)
            end

            task.wait(0.2)
            rpui.spamBaseBtn.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
            rpui.spamBaseBtn.TextColor3 = RP_COLORS.Text
            ShowNotification("SPAM OWNER", "Sent " .. cmdCount .. " commands to " .. targetPlayer.DisplayName)
        end)
    end)

    local function sortRows()
        local entries = {}
        for _, row in ipairs(rpui.listHolder:GetChildren()) do
            if row:IsA("Frame") and row.Name:match("^Row_") then
                local createIndex = tonumber(row:GetAttribute("CreateIndex")) or math.huge
                local playerName = row:GetAttribute("PlayerName") or ""
                table.insert(entries, { row = row, createIndex = createIndex, playerName = playerName })
            end
        end
        table.sort(entries, function(a, b)
            if a.createIndex ~= b.createIndex then
                return a.createIndex < b.createIndex
            end
            return a.playerName < b.playerName
        end)
        for i, entry in ipairs(entries) do
            entry.row.LayoutOrder = i
        end
    end

    local function updateStatus(plr)
        local status = stealLabels[plr.UserId]
        if not status or not status.Parent then return end
        local stealing = plr:GetAttribute("Stealing")
        local brainrotName = plr:GetAttribute("StealingIndex")
        if stealing then
            local display = tostring(brainrotName or "Unknown")
            status.Text = "STEALING • " .. display
            status.TextColor3 = RP_COLORS.Yellow
        else
            status.Text = ""
        end
    end

    local function createUserTag(parent, kind, xOffset)
        local labelText = kind == "kawaifu" and "KAWAIFU" or "MOBY"
        local bgColor = kind == "kawaifu" and Color3.fromRGB(228, 91, 176) or Color3.fromRGB(68, 136, 255)
        local width = kind == "kawaifu" and 58 or 38

        local existing = parent:FindFirstChild("UserTag_MOBY") or parent:FindFirstChild("UserTag_KAWAIFU")
        if existing then
            existing:Destroy()
        end

        local tag = rpMake("TextLabel", {
            Name = "UserTag_" .. labelText,
            BackgroundColor3 = bgColor,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(xOffset, 8),
            Size = UDim2.fromOffset(width, 16),
            Text = labelText,
            Font = Enum.Font.GothamBold,
            TextSize = 9,
            TextColor3 = Color3.fromRGB(255, 255, 255),
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = 11,
            Parent = parent
        })
        rpCorner(tag, 5)
        return tag
    end

    local function getUserTagKind(plr)
        if isKawaifuUser and isKawaifuUser(plr) then
            return "kawaifu"
        end
        if isMobyUser and isMobyUser(plr) then
            return "moby"
        end
        return nil
    end

        local function updateUserTag(plr)
        local row = rows[plr.UserId]
        if not row or not row.Parent then return end
        rpRefreshActionButtonsForPlayer(plr)

        local existing = row:FindFirstChild("UserTag_MOBY") or row:FindFirstChild("UserTag_KAWAIFU")
        local kind = getUserTagKind(plr)

        if not kind then
            if existing then
                existing:Destroy()
            end
            return
        end

        local function computeTagOffset(targetRow)
            local nameLabel = targetRow and targetRow:FindFirstChild("DisplayNameLabel")
            local textWidthPx = 90
            if nameLabel and nameLabel:IsA("TextLabel") then
                local boundsX = nameLabel.TextBounds.X
                if boundsX and boundsX > 0 then
                    textWidthPx = boundsX
                end
            end
            return 50 + textWidthPx + 8
        end

        local wantedName = kind == "kawaifu" and "UserTag_KAWAIFU" or "UserTag_MOBY"
        local tagOffset = computeTagOffset(row)

        if existing and existing.Name == wantedName then
            existing.Position = UDim2.fromOffset(tagOffset, 8)
        else
            if existing then
                existing:Destroy()
            end
            createUserTag(row, kind, tagOffset)
        end

        task.defer(function()
            local liveRow = rows[plr.UserId]
            if not liveRow or not liveRow.Parent then return end

            local liveKind = getUserTagKind(plr)
            local liveExisting = liveRow:FindFirstChild("UserTag_MOBY") or liveRow:FindFirstChild("UserTag_KAWAIFU")

            if not liveKind then
                if liveExisting then
                    liveExisting:Destroy()
                end
                return
            end

            local liveWantedName = liveKind == "kawaifu" and "UserTag_KAWAIFU" or "UserTag_MOBY"
            local liveOffset = computeTagOffset(liveRow)

            if liveExisting and liveExisting.Name == liveWantedName then
                liveExisting.Position = UDim2.fromOffset(liveOffset, 8)
            else
                if liveExisting then
                    liveExisting:Destroy()
                end
                createUserTag(liveRow, liveKind, liveOffset)
            end
        end)
    end

    local function createActionButton(parent, info, order, targetPlr)
        local btn = rpMake("TextButton", {
            Size = UDim2.fromOffset(RP_COLORS.ButtonSize, RP_COLORS.ButtonSize),
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "",
            LayoutOrder = order,
            Parent = parent
        })

        local box = rpMake("Frame", {
            Name = "Box",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.fromOffset(RP_COLORS.BoxSize, RP_COLORS.BoxSize),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = btn
        })
        rpCorner(box, 6)

        local fill = rpMake("Frame", {
            Name = "Fill",
            BackgroundColor3 = RP_COLORS.ButtonBg,
            BackgroundTransparency = 0.08,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Parent = box
        })
        rpCorner(fill, 6)

        local stroke = rpStroke(box, RP_COLORS.ButtonStroke, 1.1, 1)
        stroke.Name = "Stroke"

        rpMake("TextLabel", {
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.fromOffset(RP_COLORS.BoxSize, RP_COLORS.BoxSize),
            Text = info.label,
            Font = Enum.Font.GothamBold,
            TextSize = RP_COLORS.IconSize,
            TextColor3 = RP_COLORS.Text,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            Parent = btn
        })

        btn:SetAttribute("Locked", false)
        btn:SetAttribute("ActionName", info.action)
        btn:SetAttribute("TargetPlayerName", targetPlr and targetPlr.Name or "")
        rpSetButtonVisual(btn, "normal")

        btn.MouseEnter:Connect(function()
            if btn:GetAttribute("Locked") then return end
            rpSetButtonVisual(btn, "hover")
        end)

        btn.MouseLeave:Connect(function()
            if btn:GetAttribute("Locked") then return end
            rpSetButtonVisual(btn, "normal")
        end)

        table.insert(actionButtonsRef[info.action], btn)

        local locked = rpIsOnCooldown(info.action)
        local blocked = rpIsAdminPanelBlockedForPlayer(targetPlr)
        local disabled = locked or blocked
        btn.Active = not disabled
        btn:SetAttribute("Locked", disabled)
        if disabled then
            rpSetButtonVisual(btn, "locked")
        end

        btn.MouseButton1Click:Connect(function()
            if rpIsAdminPanelBlockedForPlayer(targetPlr) then
                ShowNotification("ADMIN", "AP Panel blocked on Moby users")
                rpRefreshActionButtonsForPlayer(targetPlr)
                return
            end

            if info.action == "tp" then
                local ok, err = rpTeleportToPlayerFirstFloor(targetPlr)
                if not ok then
                    ShowNotification("ADMIN", "Failed TP: " .. tostring(err or ((targetPlr and targetPlr.Name) or "target")))
                    return
                end

                ShowNotification("ADMIN", "TP'd to first floor of " .. ((targetPlr and targetPlr.Name) or "target"))
                return
            end

            if rpIsOnCooldown(info.action) then
                return
            end

            local targetName = (targetPlr and targetPlr.Name) or "target"
            ShowNotification("ADMIN", "Attempting " .. info.action .. " on " .. targetName)

            rpStartCooldown(info.action)
            local ok = rpRunAdminCommand(targetPlr, info.action)

            if ok == false then
                ShowNotification("ADMIN", "Failed to send " .. info.action .. " to " .. targetName)
            else
                ShowNotification("ADMIN", "Sent " .. info.action .. " to " .. targetName)
            end
        end)

        return btn
    end

    local function createPlayerRow(plr)
        if not plr or plr == LocalPlayer then return end
        if rows[plr.UserId] and rows[plr.UserId].Parent then return end

        local count = 0
        for _, child in ipairs(rpui.listHolder:GetChildren()) do
            if child:IsA("Frame") and child.Name:match("^Row_") then
                count = count + 1
            end
        end
        local isAlt = (count % 2 == 0)
        local rowColor = isAlt and RP_COLORS.RowA or RP_COLORS.RowB

        local row = rpMake("Frame", {
            Name = ("Row_%d"):format(plr.UserId),
            BackgroundColor3 = rowColor,
            BackgroundTransparency = 0.40,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, RP_COLORS.RowHeight),
            ZIndex = 5,
            Parent = rpui.listHolder
        })
        rowCreateCounter = rowCreateCounter + 1
        row:SetAttribute("CreateIndex", rowCreateCounter)
        row:SetAttribute("PlayerName", plr.Name)
        rpCorner(row, RP_COLORS.RowCorner)
        rpStroke(row, RP_COLORS.AccentSoft, 1, 0.98)
        row.ClipsDescendants = true
        rows[plr.UserId] = row

        row.MouseEnter:Connect(function()
            row.BackgroundColor3 = RP_COLORS.RowHover
        end)
        row.MouseLeave:Connect(function()
            row.BackgroundColor3 = rowColor
        end)

        local avatarHolder = rpMake("Frame", {
            BackgroundColor3 = Color3.fromRGB(9, 10, 14),
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(34, 34),
            Position = UDim2.fromOffset(8, 10),
            Parent = row
        })
        rpCorner(avatarHolder, 8)
        rpStroke(avatarHolder, RP_COLORS.AccentSoft, 1, 0.72)

        local avatar = rpMake("ImageLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.fromOffset(0, 0),
            Image = "rbxthumb://type=AvatarHeadShot&id=" .. plr.UserId .. "&w=150&h=150",
            ZIndex = 10,
            Parent = avatarHolder
        })
        rpCorner(avatar, 8)

        local textWidth = -(RP_COLORS.ActionsWidth + RP_COLORS.SafeGap)

        local nameLabel = rpMake("TextLabel", {
            Name = "DisplayNameLabel",
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(50, 6),
            Size = UDim2.new(1, textWidth, 0, 20),
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = plr.DisplayName,
            Font = Enum.Font.GothamBold,
            TextSize = RP_COLORS.NameSize,
            TextColor3 = RP_COLORS.Text,
            ZIndex = 10,
            Parent = row
        })

        updateUserTag(plr)

        rpMake("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(50, 23),
            Size = UDim2.new(1, textWidth, 0, 16),
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = "@" .. plr.Name,
            Font = Enum.Font.GothamMedium,
            TextSize = RP_COLORS.UserSize,
            TextColor3 = RP_COLORS.SubText,
            ZIndex = 10,
            Parent = row
        })

        local status = rpMake("TextLabel", {
            Name = "Status",
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(50, 37),
            Size = UDim2.new(1, textWidth, 0, 14),
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = "",
            Font = Enum.Font.GothamBold,
            TextSize = RP_COLORS.StatusSize,
            TextColor3 = RP_COLORS.Yellow,
            ZIndex = 10,
            Parent = row
        })
        stealLabels[plr.UserId] = status

        local actions = rpMake("Frame", {
            Name = "Actions",
            BackgroundTransparency = 1,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -8, 0.5, 0),
            Size = UDim2.fromOffset(RP_COLORS.ActionsWidth, RP_COLORS.ButtonSize),
            ZIndex = 12,
            Parent = row
        })

        local actionList = Instance.new("UIListLayout")
        actionList.FillDirection = Enum.FillDirection.Horizontal
        actionList.SortOrder = Enum.SortOrder.LayoutOrder
        actionList.HorizontalAlignment = Enum.HorizontalAlignment.Left
        actionList.VerticalAlignment = Enum.VerticalAlignment.Center
        actionList.Padding = UDim.new(0, 0)
        actionList.Parent = actions

        for i, b in ipairs(RP_BUTTONS) do
            createActionButton(actions, b, i, plr)
        end

        local bottomLine = rpMake("Frame", {
            Name = "Line",
            BackgroundColor3 = RP_COLORS.RowLine,
            BackgroundTransparency = 0.93,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 16, 1, -1),
            Size = UDim2.new(1, -32, 0, 1),
            Parent = row
        })

        row.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if rpIsAdminPanelBlockedForPlayer(plr) then
                ShowNotification("ADMIN", "AP Panel blocked on Moby users")
                rpRefreshActionButtonsForPlayer(plr)
                return
            end

            local orderedActions = {"ragdoll", "jail", "rocket", "balloon", "jumpscare", "inverse", "tiny", "morph"}
            local hasAnyAvailable = false
            for _, action in ipairs(orderedActions) do
                if not rpIsOnCooldown(action) then
                    hasAnyAvailable = true
                    break
                end
            end

            if hasAnyAvailable then
                local sentAny = false
                for _, action in ipairs(orderedActions) do
                    if rpIsOnCooldown(action) then
                        continue
                    end
                    rpStartCooldown(action)
                    if rpIsAdminPanelBlockedForPlayer(plr) then
                        ShowNotification("ADMIN", "AP Panel blocked on Moby users")
                        rpRefreshActionButtonsForPlayer(plr)
                        break
                    end
                    rpRunAdminCommand(plr, action)
                    sentAny = true
                    task.wait(0.01)
                end
                if sentAny then
                    ShowNotification("ADMIN", "Triggered ALL on " .. plr.Name)
                end
            end
        end)

        local cons = {}
        table.insert(cons, plr:GetAttributeChangedSignal("Stealing"):Connect(function()
            updateStatus(plr)
        end))
        table.insert(cons, plr:GetAttributeChangedSignal("StealingIndex"):Connect(function()
            updateStatus(plr)
        end))
        table.insert(cons, plr.CharacterAdded:Connect(function(char)
            task.defer(function()
                updateUserTag(plr)
                local ok = pcall(function()
                    char.DescendantAdded:Connect(function()
                        task.defer(function()
                            updateUserTag(plr)
                        end)
                    end)
                    char.DescendantRemoving:Connect(function()
                        task.defer(function()
                            updateUserTag(plr)
                        end)
                    end)
                end)
            end)
        end))
        if plr.Character then
            table.insert(cons, plr.Character.DescendantAdded:Connect(function()
                task.defer(function()
                    updateUserTag(plr)
                end)
            end))
            table.insert(cons, plr.Character.DescendantRemoving:Connect(function()
                task.defer(function()
                    updateUserTag(plr)
                end)
            end))
        end
        attrCons[plr.UserId] = cons

        updateStatus(plr)
        updateUserTag(plr)
        rpRefreshActionButtonsForPlayer(plr)
        sortRows()
    end

    local function removePlayerRow(plr)
        local row = rows[plr.UserId]
        if row then
            row:Destroy()
            rows[plr.UserId] = nil
        end
        stealLabels[plr.UserId] = nil
        local cons = attrCons[plr.UserId]
        if cons then
            for _, c in ipairs(cons) do
                pcall(function()
                    c:Disconnect()
                end)
            end
            attrCons[plr.UserId] = nil
        end
    end

    rpui.refreshBtn.MouseButton1Click:Connect(function()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                createPlayerRow(plr)
                updateStatus(plr)
            end
        end
        sortRows()
        ShowNotification("ADMIN PANEL", "Player list refreshed")
    end)


    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            createPlayerRow(plr)
        end
    end

    Players.PlayerAdded:Connect(function(plr)
        task.defer(function()
            createPlayerRow(plr)
        end)
    end)
    Players.PlayerRemoving:Connect(removePlayerRow)

    task.spawn(function()
        while rpui.adminGui.Parent do
            updateProxViz()
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    updateUserTag(plr)
                end
            end
            task.wait(0.25)
        end
    end)

    if Config.HideAdminPanel then
        rpui.adminGui.Enabled = false
    end
end

__initAdminPanelLiteralReplacement()



    -- ===== BEGIN GRIEF DETECTOR (ported from CNK) =====
    task.spawn(function()
        local ok, err = pcall(function()
    local GriefActive = false
        local GriefConnections = {}
        local GriefScreenGui = nil
        local GriefCleanupFns = {}

        local function GriefConnect(Signal, Callback)
            local Conn = Signal:Connect(Callback)
            table.insert(GriefConnections, Conn)
            return Conn
        end

        local function StartGriefDetector()
            if GriefActive then return end
            GriefActive = true

            local Players = game:GetService("Players")
            local RunService = game:GetService("RunService")
            local ReplicatedStorage = game:GetService("ReplicatedStorage")
            local HttpService = game:GetService("HttpService")
            local LocalPlayer = Players.LocalPlayer
            local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

            local function safeRequire(parent, ...)
                local path = {...}
                local current = parent
                for _, name in ipairs(path) do
                    local child = current:FindFirstChild(name)
                    if not child then
                        local ok2, c = pcall(function() return current:WaitForChild(name, 5) end)
                        if ok2 then child = c end
                    end
                    if not child then return nil, "missing: "..table.concat(path, ".") end
                    current = child
                end
                local ok2, mod = pcall(require, current)
                if not ok2 then return nil, tostring(mod) end
                return mod
            end

            local Synchronizer, err1 = safeRequire(ReplicatedStorage, "Packages", "Synchronizer")
            local AnimalsData, err2 = safeRequire(ReplicatedStorage, "Datas", "Animals")
            local AnimalsShared, err3 = safeRequire(ReplicatedStorage, "Shared", "Animals")
            local MutationsData, err4 = safeRequire(ReplicatedStorage, "Datas", "Mutations")
            local TraitsData, err5 = safeRequire(ReplicatedStorage, "Datas", "Traits")
            local NumberUtils, err6 = safeRequire(ReplicatedStorage, "Utils", "NumberUtils")

            if not (Synchronizer and AnimalsData and AnimalsShared and MutationsData and TraitsData and NumberUtils) then
                GriefActive = false
                local firstErr = err1 or err2 or err3 or err4 or err5 or err6 or "unknown"
                ShowNotification("GRIEF DETECTOR", "Load failed: "..firstErr)
                warn("[Grief Detector] Failed to load. Errors:", err1, err2, err3, err4, err5, err6)
                return
            end

            ShowNotification("GRIEF DETECTOR", "Enabled - watching for griefers")

            local Debug = { Enabled = false }
            local WebhookURL = ""

            local MUTATION_EMOJIS = {
                ["Gold"]="<:Gold:1487969958347411718>",["Diamond"]="<:Diamond:1487969901816840252>",
                ["Rainbow"]="<:Rainbow:1487970016736317531>",["Galaxy"]="<:Galaxy:1487969940743913595>",
                ["Radioactive"]="<:Radioactive:1487969993269182494>",["Bloodrot"]="<:Bloodrot:1487969793876168716>",
                ["Candy"]="<:Candy:1487969850109333574>",["Divine"]="<:Divine:1487969919537647626>",
                ["Lava"]="<:Lava:1487969974659186708>",["Cursed"]="<:Cursed:1487969875359174738>",
                ["YinYang"]="<:Yinyang:1487970035912806491>",
            }

            local TRAIT_EMOJIS = {
                ["10B"]="<:10B:1487970137020694538>",["26"]="<:26:1487970139042480218>",
                [":3"]="<:3_:1487970134818553987>",["Blue Balloon"]="<:BlueBalloon:1487970147661512795>",
                ["Brazil"]="<:Brazil:1487970149238837319>",["Bubblegum"]="<:Bubblegum:1487970150509449406>",
                ["Bunny Ears"]="<:BunnyEars:1487970151776391290>",["Chocolate"]="<:Chocolate:1487970153118564363>",
                ["Claws"]="<:Claws:1487970154578055300>",["Cometstruck"]="<:Cometstruck:1487970156352241845>",
                ["Disco"]="<:Disco:1487970158663434270>",["Explosive"]="<:Explosive:1487970160139829298>",
                ["Fire"]="<:Fire:1487970161737863280>",["Galactic"]="<:Galactic:1487970165965590588>",
                ["Glitched"]="<:Glitched:1487970168956125304>",["Green Balloon"]="<:GreenBalloon:1487970173658075246>",
                ["Halo"]="<:Halo:1487970180817485965>",["Indonesia"]="<:Indonesia:1487970183330136064>",
                ["Jackolantern Pet"]="<:JackolanternPet:1487970184978370670>",["Lightning"]="<:Lightning:1487970186840772809>",
                ["Lucky"]="<:Lucky:1487970198756786236>",["Matteo Hat"]="<:MatteoHat:1487970201466306603>",
                ["Meowl"]="<:Meowl:1487970203194233065>",["Nyan"]="<:Nyan:1487970207422087218>",
                ["Orange Balloon"]="<:OrangeBalloon:1487970208860606604>",["Paint"]="<:Paint:1487970210203041813>",
                ["Pink Balloon"]="<:PinkBalloon:1487970212249866331>",["Red Balloon"]="<:RedBalloon:1487970215470829678>",
                ["Reindeer Pet"]="<:ReindeerPet:1487970218407104522>",["RIP Gravestone"]="<:RipGravestone:1487970222232047616>",
                ["Rose"]="<:Rose:1487970228678819970>",["Santa Hat"]="<:SantaHat:1487970230197031003>",
                ["Shark Fin"]="<:SharkFin:1487970231543660655>",["Skibidi"]="<:Skibidi:1487970236077572257>",
                ["Sleepy"]="<:Sleepy:1487970240439517184>",["Snowy"]="<:Snowy:1487985035855401091>",
                ["Spider"]="<:Spider:1487970247356055602>",["Strawberry"]="<:Strawberry:1487970249960587426>",
                ["Taco"]="<:Taco:1487970253425082448>",["UFO"]="<:Ufo:1487970259146117223>",
                ["Wet"]="<:Wet:1487970260823965788>",["Witch Hat"]="<:WitchHat:1487970263474901223>",
                ["Zombie"]="<:Zombie:1487970267690172517>",["Granny"]="<:Granny:1487985023645651005>",
                ["Skeleton"]="<:Skeleton:1487985077383073872>",["Sombrero"]="<:Sombrero:1487985034706157798>",
                ["Fireworks"]="<:Fireworks:1487985025382223882>",["Tie"]="<:Tie:1487985091522334760>",
                ["Rainbow Balloon"]="<:RainbowBalloon:1487985035855401091>",
            }

            local PendingNotifications = {}
            local CurrentStealInfo = nil
            local StealingEndedAt = 0

            GriefScreenGui = Instance.new("ScreenGui")
            GriefScreenGui.Name = "GriefDetector_Xi"
            GriefScreenGui.ResetOnSpawn = false
            GriefScreenGui.Parent = PlayerGui

            local ListFrame = Instance.new("Frame")
            ListFrame.Size = UDim2.new(0, 320, 0, 600)
            ListFrame.Position = UDim2.new(0.5, -160, 0, 10)
            ListFrame.BackgroundTransparency = 1
            ListFrame.Parent = GriefScreenGui

            local Layout = Instance.new("UIListLayout")
            Layout.SortOrder = Enum.SortOrder.LayoutOrder
            Layout.Padding = UDim.new(0, 8)
            Layout.Parent = ListFrame

            local function getAnimalImageUrl(animalName)
                local info = AnimalsData[animalName]
                local displayName = (info and info.DisplayName) or animalName
                local slug = displayName:lower():gsub(" ", "-"):gsub("[^%a%d%-]", "")
                local RequestFn = request or http_request
                if not RequestFn then return nil end
                local ok2, response = pcall(function()
                    return RequestFn({Url="https://www.mobynotifier.com/brainrots/"..slug,Method="GET",AllowRedirect=false})
                end)
                if not ok2 or not response then return nil end
                local headers = response.Headers or {}
                local location = headers["Location"] or headers["location"]
                if not location or location == "" or location == "https://practicaltyping.com/wp-content/uploads/2020/07/gardenwallgreg.jpg" then
                    return nil
                end
                return location
            end

            local function getStealInfo()
                local stealingIndex = LocalPlayer:GetAttribute("StealingIndex")
                if not stealingIndex then return nil end
                local bestMatch = nil
                local highestGenValue = -1
                for _, channel in pairs(Synchronizer:GetAllChannels()) do
                    local ok2, data = pcall(function() return channel:GetTable() end)
                    if not ok2 or type(data) ~= "table" or type(data.AnimalList) ~= "table" then continue end
                    for _, entry in pairs(data.AnimalList) do
                        if type(entry) ~= "table" or tostring(entry.Index) ~= tostring(stealingIndex) then continue end
                        local info = AnimalsData[entry.Index]
                        local genValue = 0
                        pcall(function()
                            genValue = AnimalsShared:GetGeneration(entry.Index, entry.Mutation, entry.Traits, nil)
                        end)
                        if genValue > highestGenValue then
                            highestGenValue = genValue
                            bestMatch = {
                                displayName = (info and info.DisplayName) or entry.Index,
                                rawName = entry.Index,
                                mutation = entry.Mutation or "None",
                                traits = (entry.Traits and #entry.Traits > 0) and entry.Traits or {},
                                genValue = genValue,
                                genText = "$"..NumberUtils:ToString(genValue).."/s",
                            }
                        end
                    end
                end
                return bestMatch
            end

            local function getUserId(name)
                local ok2, id = pcall(function() return Players:GetUserIdFromNameAsync(name) end)
                if ok2 and id then return id end
                local p = Players:FindFirstChild(name)
                return p and p.UserId or 1
            end

            local function getItemIcon(name)
                local ItemsFolder = ReplicatedStorage:FindFirstChild("Items")
                if not ItemsFolder then return "" end
                local Item = ItemsFolder:FindFirstChild(name)
                if not Item then return "" end
                if Item:IsA("Tool") then return Item.TextureId end
                if Item:FindFirstChild("Handle") and Item.Handle:IsA("MeshPart") then return Item.Handle.TextureID end
                return ""
            end

            local function Notify(Griefer, Victim, Item, Autojoiner, StealInfo)
                if typeof(Item) == "string" and (Item == "#92FF67" or Item:sub(1,1) == "#") then return end
                local ModelZoom = 1.2

                local ItemIcon = getItemIcon(Item)
                local animalMutation = "Normal"
                if StealInfo and StealInfo.mutation then
                    animalMutation = StealInfo.mutation:sub(1,1):upper() .. StealInfo.mutation:sub(2):lower()
                end
                local isRainbow = (animalMutation == "Rainbow")
                local mutData = MutationsData[animalMutation]
                local traitColor = mutData and mutData.MainColor or Color3.fromRGB(180,180,180)
                local goldData = MutationsData and MutationsData["Gold"]
                local goldColor = goldData and goldData.MainColor or Color3.fromRGB(255,222,89)

                local function getRainbow(speed)
                    local t = tick() * (speed or 0.2)
                    local kp = {}
                    for i=0,10 do kp[i+1] = ColorSequenceKeypoint.new(i/10, Color3.fromHSV((i/10 - t) % 1, 1, 1)) end
                    return ColorSequence.new(kp)
                end

                local animalName = (StealInfo and StealInfo.displayName) or "Player Griefed!"
                if #animalName > 20 then animalName = animalName:sub(1,18).."..." end
                local genText = StealInfo and StealInfo.genText or ""

                local Card = Instance.new("CanvasGroup")
                Card.BackgroundColor3 = Color3.fromRGB(20,20,20)
                Card.GroupTransparency = 1
                Card.Position = UDim2.new(1.2,0,0,0)
                Card.Visible = false
                Card.AutomaticSize = Enum.AutomaticSize.XY
                Card.Size = UDim2.new(0,0,0,95)
                Card.Parent = ListFrame

                Instance.new("UICorner", Card).CornerRadius = UDim.new(0, 0)

                local CardGradient = Instance.new("UIGradient")
                CardGradient.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(35,35,35)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(15,15,15))
                })
                CardGradient.Rotation = 90
                CardGradient.Parent = Card

                local CardStroke = Instance.new("UIStroke")
                CardStroke.Color = Color3.new(1,1,1)
                CardStroke.Thickness = 2
                CardStroke.Transparency = 0.1
                CardStroke.Parent = Card

                local StrokeGradient = Instance.new("UIGradient")
                if isRainbow then
                    StrokeGradient.Color = getRainbow(0.3)
                else
                    StrokeGradient.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, traitColor),
                        ColorSequenceKeypoint.new(1, traitColor:Lerp(Color3.new(0,0,0), 0.4))
                    })
                end
                StrokeGradient.Rotation = 90
                StrokeGradient.Parent = CardStroke

                local CardPadding = Instance.new("UIPadding")
                CardPadding.PaddingTop = UDim.new(0,4)
                CardPadding.PaddingBottom = UDim.new(0,4)
                CardPadding.PaddingLeft = UDim.new(0,4)
                CardPadding.PaddingRight = UDim.new(0,8)
                CardPadding.Parent = Card

                local MainLayout = Instance.new("UIListLayout")
                MainLayout.FillDirection = Enum.FillDirection.Horizontal
                MainLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                MainLayout.Padding = UDim.new(0,6)
                MainLayout.SortOrder = Enum.SortOrder.LayoutOrder
                MainLayout.Parent = Card

                local Viewport = Instance.new("ViewportFrame")
                Viewport.Size = UDim2.new(0,95,0,95)
                Viewport.BackgroundTransparency = 1
                Viewport.LayoutOrder = 1
                Viewport.Parent = Card

                local WorldModel = Instance.new("WorldModel")
                WorldModel.Parent = Viewport

                local Cam = Instance.new("Camera")
                Cam.FieldOfView = 15
                Cam.Parent = Viewport
                Viewport.CurrentCamera = Cam

                local InfoCol = Instance.new("Frame")
                InfoCol.AutomaticSize = Enum.AutomaticSize.XY
                InfoCol.BackgroundTransparency = 1
                InfoCol.LayoutOrder = 2
                InfoCol.Parent = Card

                local InfoLayout = Instance.new("UIListLayout")
                InfoLayout.Padding = UDim.new(0,0)
                InfoLayout.SortOrder = Enum.SortOrder.LayoutOrder
                InfoLayout.Parent = InfoCol

                local HeaderRow = Instance.new("Frame")
                HeaderRow.AutomaticSize = Enum.AutomaticSize.XY
                HeaderRow.BackgroundTransparency = 1
                HeaderRow.LayoutOrder = 1
                HeaderRow.Parent = InfoCol

                local HeaderLayout = Instance.new("UIListLayout")
                HeaderLayout.FillDirection = Enum.FillDirection.Horizontal
                HeaderLayout.Padding = UDim.new(0,4)
                HeaderLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                HeaderLayout.Parent = HeaderRow

                local NameLabel = Instance.new("TextLabel")
                NameLabel.AutomaticSize = Enum.AutomaticSize.XY
                NameLabel.BackgroundTransparency = 1
                NameLabel.TextColor3 = isRainbow and Color3.new(1,1,1) or traitColor
                NameLabel.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)
                NameLabel.TextSize = 17
                NameLabel.RichText = true
                NameLabel.Text = "<b>"..animalName.."</b>"
                NameLabel.Parent = HeaderRow

                local NameStroke = Instance.new("UIStroke")
                NameStroke.Thickness = 1.8
                NameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
                NameStroke.Color = Color3.new(0,0,0)
                NameStroke.Parent = NameLabel

                local NameGradient = Instance.new("UIGradient")
                if isRainbow then
                    NameGradient.Color = getRainbow(0.5)
                else
                    NameGradient.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, traitColor),
                        ColorSequenceKeypoint.new(0.45, Color3.new(1,1,1)),
                        ColorSequenceKeypoint.new(0.55, Color3.new(1,1,1)),
                        ColorSequenceKeypoint.new(1, traitColor)
                    })
                end
                NameGradient.Rotation = 0
                NameGradient.Parent = NameLabel

                local GenLabel = Instance.new("TextLabel")
                GenLabel.AutomaticSize = Enum.AutomaticSize.XY
                GenLabel.BackgroundTransparency = 1
                GenLabel.TextColor3 = goldColor:Lerp(Color3.new(0,0,0), 0.1)
                GenLabel.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)
                GenLabel.TextSize = 17
                GenLabel.RichText = true
                GenLabel.Text = "<b>"..genText.."</b>"
                GenLabel.Parent = HeaderRow

                local GenStroke = Instance.new("UIStroke")
                GenStroke.Thickness = 1.8
                GenStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
                GenStroke.Parent = GenLabel

                local function addRow(label, value, icon, order)
                    local row = Instance.new("Frame")
                    row.AutomaticSize = Enum.AutomaticSize.XY
                    row.BackgroundTransparency = 1
                    row.LayoutOrder = order
                    row.Parent = InfoCol
                    local rowLayout = Instance.new("UIListLayout")
                    rowLayout.FillDirection = Enum.FillDirection.Horizontal
                    rowLayout.Padding = UDim.new(0,4)
                    rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
                    rowLayout.Parent = row
                    local imgHolder = Instance.new("Frame")
                    imgHolder.Size = UDim2.new(0,16,0,16)
                    imgHolder.BackgroundColor3 = Color3.fromRGB(50,50,50)
                    imgHolder.BackgroundTransparency = 0.7
                    imgHolder.BorderSizePixel = 0
                    imgHolder.Parent = row
                    Instance.new("UICorner", imgHolder).CornerRadius = UDim.new(1,0)
                    local img = Instance.new("ImageLabel")
                    img.Size = UDim2.new(1,0,1,0)
                    img.BackgroundTransparency = 1
                    img.Image = icon or ("rbxthumb://type=AvatarHeadShot&id="..getUserId(value).."&w=60&h=60")
                    img.Parent = imgHolder
                    Instance.new("UICorner", img).CornerRadius = UDim.new(1,0)
                    local txt = Instance.new("TextLabel")
                    txt.AutomaticSize = Enum.AutomaticSize.XY
                    txt.BackgroundTransparency = 1
                    txt.TextColor3 = Color3.fromRGB(220,220,220)
                    txt.FontFace = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.SemiBold)
                    txt.TextSize = 13
                    txt.RichText = true
                    txt.Text = "<b><font color=\"rgb(255,255,255)\">"..label..":</font></b> <font color=\"rgb(220,220,220)\"><b>"..value.."</b></font>"
                    txt.Parent = row
                end

                addRow("Gros Fdp", Griefer, nil, 2)
                addRow("La Salope", Victim, nil, 3)
                addRow("Arme du Crime", Item, (ItemIcon ~= "" and ItemIcon or "rbxassetid://16302324017"), 4)
                if Autojoiner and Autojoiner ~= "None" then
                    addRow("Autojoiner", Autojoiner, "rbxassetid://16302324017", 5)
                end

                local TraitsCol = Instance.new("Frame")
                TraitsCol.AutomaticSize = Enum.AutomaticSize.XY
                TraitsCol.Size = UDim2.new(1,0,0,18)
                TraitsCol.BackgroundTransparency = 1
                TraitsCol.LayoutOrder = 10
                TraitsCol.Parent = InfoCol

                local TraitsGrid = Instance.new("UIGridLayout")
                TraitsGrid.CellSize = UDim2.new(0,16,0,16)
                TraitsGrid.CellPadding = UDim2.new(0,2,0,2)
                TraitsGrid.Parent = TraitsCol

                if StealInfo and typeof(StealInfo.traits) == "table" then
                    for _, tName in ipairs(StealInfo.traits) do
                        local tData = TraitsData[tName]
                        local tIcon = tData and tData.Icon or "rbxassetid://16302324017"
                        local tImg = Instance.new("ImageLabel")
                        tImg.BackgroundTransparency = 1
                        tImg.Image = tIcon
                        tImg.Size = UDim2.new(0,16,0,16)
                        tImg.Parent = TraitsCol
                    end
                end

                task.spawn(function()
                    local ModelsFolder = ReplicatedStorage:FindFirstChild("Models") and ReplicatedStorage.Models:FindFirstChild("Animals")
                    local function findModel(name)
                        if not ModelsFolder then return nil end
                        local search = name:lower():gsub("[%s%-_]", "")
                        for _, child in ipairs(ModelsFolder:GetChildren()) do
                            if child.Name:lower():gsub("[%s%-_]", "") == search then return child end
                        end
                    end

                    local OriginalModel = StealInfo and (findModel(StealInfo.rawName) or findModel(StealInfo.displayName))
                    if OriginalModel then
                        local ModelClone = OriginalModel:Clone()
                        ModelClone:PivotTo(CFrame.new(0,0,0))
                        ModelClone.Parent = WorldModel

                        local templateName = OriginalModel.Name
                        local traits = StealInfo and StealInfo.traits
                        if typeof(traits) == "string" then
                            pcall(function() traits = HttpService:JSONDecode(traits) end)
                        end

                        if AnimalsShared then
                            pcall(function()
                                if animalMutation ~= "Normal" then
                                    AnimalsShared:ApplyMutation(ModelClone, templateName, animalMutation)
                                end
                                if typeof(traits) == "table" then
                                    AnimalsShared:ApplyTraits(ModelClone, templateName, traits)
                                end
                            end)
                        end

                        task.wait(0.1)
                        for _, p in ipairs(ModelClone:GetDescendants()) do
                            if p:IsA("BasePart") then
                                p.LocalTransparencyModifier = 0
                                p.Anchored = true
                                p.CanCollide = false
                            end
                        end

                        local animPath = ReplicatedStorage.Animations.Animals:FindFirstChild(templateName)
                        local idle = animPath and animPath:FindFirstChild("Idle")
                        if idle then
                            local ac = ModelClone:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController", ModelClone)
                            local an = ac:FindFirstChildOfClass("Animator") or Instance.new("Animator", ac)
                            local track = an:LoadAnimation(idle)
                            track.Looped = true
                            track:Play()
                        end

                        local _, size = ModelClone:GetBoundingBox()
                        local fov = Cam.FieldOfView
                        local maxSize = math.max(size.X, size.Y, size.Z)
                        local distance = (maxSize / 2) / math.tan(math.rad(fov / 2))
                        distance = distance * ModelZoom

                        local lookAt = Vector3.new(0,0,0)
                        if ModelClone:FindFirstChild("HumanoidRootPart") then
                            lookAt = ModelClone.HumanoidRootPart.Position
                        elseif ModelClone.PrimaryPart then
                            lookAt = ModelClone.PrimaryPart.Position
                        end

                        Cam.CFrame = CFrame.new(lookAt + Vector3.new(distance*0.8, distance*0.4, distance*0.8), lookAt)

                        local rot = 0
                        local strokeRot = 0
                        GriefConnect(RunService.Heartbeat, function(dt)
                            if not Card.Parent then return end
                            rot += dt * 0.7
                            strokeRot = (strokeRot + dt * 20) % 360
                            ModelClone:PivotTo(CFrame.new(0,0,0) * CFrame.Angles(0, rot, 0))
                            if isRainbow then
                                local rb = getRainbow(0.4)
                                NameGradient.Color = rb
                                StrokeGradient.Color = rb
                                NameGradient.Offset = Vector2.new(0,0)
                            else
                                NameGradient.Offset = Vector2.new(-1.2 + (tick() * 1.2 % 2.4), 0)
                            end
                            StrokeGradient.Rotation = strokeRot
                        end)

                        Card.Visible = true
                        game:GetService("TweenService"):Create(Card, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                            GroupTransparency = 0,
                            Position = UDim2.new(0,0,0,0)
                        }):Play()
                    else
                        Card.Visible = true
                        game:GetService("TweenService"):Create(Card, TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                            GroupTransparency = 0,
                            Position = UDim2.new(0,0,0,0)
                        }):Play()
                    end
                end)

                task.delay(15, function()
                    if not Card.Parent then return end
                    local ExitTween = game:GetService("TweenService"):Create(Card, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
                        GroupTransparency = 1,
                        Position = UDim2.new(-1.2,0,0,0)
                    })
                    ExitTween:Play()
                    ExitTween.Completed:Connect(function() Card:Destroy() end)
                end)
            end

            local function SendWebhook(Entries, Victim, StealInfo)
                if WebhookURL == "" or Debug.Enabled then return end
                local env = (getgenv and getgenv()) or _G
                local discordId = env.LRM_LinkedDiscordID or _G.LRM_LinkedDiscordID
                local lrm_send_webhook = env.LRM_SEND_WEBHOOK or _G.LRM_SEND_WEBHOOK
                local discordPing = discordId and ("<@"..tostring(discordId)..">") or "Not Linked"

                local firstTime = Entries[1] and Entries[1].Time or os.time()
                local timeText = string.format("<t:%d:D> <t:%d:T>", firstTime, firstTime)

                local embed = {
                    title = (StealInfo and StealInfo.displayName) or "Player Griefed!",
                    color = 0xff4444,
                    fields = {},
                    footer = { text = "hi" }
                }

                local desc = timeText.."\n**Victim:** "..Victim.."\n"
                for i, entry in ipairs(Entries) do
                    desc = desc.."**Griefer:** "..entry.Griefer.."\n"
                    desc = desc.."**Item used:** "..entry.Item.."\n"
                    if entry.Autojoiner and entry.Autojoiner ~= "None" then
                        desc = desc.."**Autojoiner:** "..entry.Autojoiner.."\n"
                    end
                    if i < #Entries then desc = desc.."---\n" end
                end
                desc = desc.."**Victim's Discord:** "..discordPing
                embed.description = desc

                if StealInfo then
                    local mutationText = MUTATION_EMOJIS[StealInfo.mutation] or StealInfo.mutation
                    local traitParts = {}
                    for _, trait in ipairs(StealInfo.traits) do
                        table.insert(traitParts, TRAIT_EMOJIS[trait] or trait)
                    end
                    local traitsText = #traitParts > 0 and table.concat(traitParts, " ") or "None"
                    table.insert(embed.fields, {name="Generation", value=StealInfo.genText, inline=true})
                    table.insert(embed.fields, {name="Mutation", value=mutationText, inline=true})
                    table.insert(embed.fields, {name="Traits", value=traitsText, inline=false})
                    local imageUrl = getAnimalImageUrl(StealInfo.rawName)
                    if imageUrl then embed.thumbnail = {url=imageUrl} end
                end

                local payload = {embeds = {embed}}
                if lrm_send_webhook then
                    pcall(function() lrm_send_webhook(WebhookURL, payload) end)
                else
                    local RequestFn = request or http_request
                    if RequestFn then
                        pcall(function()
                            RequestFn({
                                Url = WebhookURL, Method = "POST",
                                Headers = {["Content-Type"]="application/json"},
                                Body = HttpService:JSONEncode(payload)
                            })
                        end)
                    end
                end
            end

            local CoreGui = game:GetService("CoreGui")
            local function GetAutojoiner(PlayerName)
                local Player = Players:FindFirstChild(PlayerName)
                if not Player then return nil end
                local Char = Player.Character
                if not Char then return nil end
                if Char:FindFirstChild("BananaUserESP") then return "Gingerini"
                elseif Char:FindFirstChild("_moby_highlight") then return "Moby"
                elseif Char:FindFirstChild("KaWaifu_NeonHighlight") then return "Kawaifu" end
                local MorangueteESP = CoreGui:FindFirstChild("BillboardGui") and CoreGui.BillboardGui:FindFirstChild("MorangueteESP_"..tostring(Player.UserId))
                if MorangueteESP and MorangueteESP:FindFirstChild("ESP_Highlight_"..tostring(Player.UserId)) then return "Moranguete" end
                local AtlasFolder = workspace:FindFirstChild("AtlasESPFolder")
                if AtlasFolder then
                    local PlayerEspFolder = AtlasFolder:FindFirstChild(PlayerName.."_ESP")
                    if PlayerEspFolder then
                        local Highlight = PlayerEspFolder:FindFirstChildWhichIsA("Highlight")
                        if Highlight and Highlight.FillColor == Color3.fromRGB(255,215,0) then return "Atlas" end
                    end
                end
                return nil
            end

            local function QueueGriefNotification(Text, Griefer, Item)
                if typeof(Item) == "string" and (Item == "#92FF67" or Item:sub(1,1) == "#") then return end
                local isStealing = LocalPlayer:GetAttribute("Stealing") == true
                local inGracePeriod = (tick() - StealingEndedAt) < 0.5
                if not isStealing and not inGracePeriod then return end
                if isStealing and not CurrentStealInfo then
                    CurrentStealInfo = getStealInfo()
                end
                local autojoiner = GetAutojoiner(Griefer)
                for _, entry in ipairs(PendingNotifications) do
                    if entry.Griefer == Griefer and entry.Item == Item then return end
                end
                table.insert(PendingNotifications, {Griefer=Griefer, Item=Item, Autojoiner=autojoiner, Time=os.time()})
            end

            local function FlushNotifications()
                if #PendingNotifications == 0 then return end
                for _, entry in ipairs(PendingNotifications) do
                    Notify(entry.Griefer, LocalPlayer.Name, entry.Item, entry.Autojoiner, CurrentStealInfo)
                end
                SendWebhook(PendingNotifications, LocalPlayer.Name, CurrentStealInfo)
                PendingNotifications = {}
                CurrentStealInfo = nil
            end

            GriefConnect(LocalPlayer:GetAttributeChangedSignal("Stealing"), function()
                local val = LocalPlayer:GetAttribute("Stealing")
                if val == true then
                    CurrentStealInfo = getStealInfo()
                elseif val == nil or val == false then
                    StealingEndedAt = tick()
                    task.delay(0.5, function() FlushNotifications() end)
                end
            end)

            local function GetHolder(GearName)
                for _, Player in ipairs(Players:GetPlayers()) do
                    if Player ~= LocalPlayer and Player.Character and Player.Character:FindFirstChild(GearName) then
                        return Player
                    end
                end
            end

            local function GetHRP()
                local Char = LocalPlayer.Character
                return Char and Char:FindFirstChild("HumanoidRootPart")
            end

            local function WatchPart(Part, OnHit)
                GriefConnect(Part.Touched, function(Hit)
                    local Char = LocalPlayer.Character
                    if Char and Hit:IsDescendantOf(Char) then OnHit() end
                end)
                GriefConnect(RunService.Heartbeat, function()
                    if not Part.Parent then return end
                    local HRP = GetHRP()
                    if HRP and (Part.Position - HRP.Position).Magnitude <= 5 then OnHit() end
                end)
            end

            local HitBullets = {}
            local SentryOwners = {}
            local function TrackBullet(Obj)
                if not Obj.Name:find("SentryBullet") or HitBullets[Obj] then return end
                local Part = Obj:IsA("BasePart") and Obj or Obj:FindFirstChildWhichIsA("BasePart")
                if not Part then return end
                WatchPart(Part, function()
                    if HitBullets[Obj] then return end
                    HitBullets[Obj] = true
                    local owner = next(SentryOwners) or "Unknown"
                    QueueGriefNotification(owner.." used All Seeing Sentry on you!", owner, "All Seeing Sentry")
                    Obj.AncestryChanged:Connect(function() if not Obj.Parent then HitBullets[Obj] = nil end end)
                end)
            end

            local BoogieDetected = {}
            local function TrackHandle(Handle)
                if not Handle:IsA("BasePart") or Handle.Parent ~= workspace then return end
                local Mesh = Handle:FindFirstChildWhichIsA("SpecialMesh") or Handle:FindFirstChildWhichIsA("FileMesh")
                if not Mesh then Handle.ChildAdded:Wait() Mesh = Handle:FindFirstChildWhichIsA("SpecialMesh") or Handle:FindFirstChildWhichIsA("FileMesh") end
                if not Mesh or not Mesh.TextureId:find("65514619") or BoogieDetected[Handle] then return end
                local Owner = GetHolder("Boogie Bomb")
                if not Owner then return end
                WatchPart(Handle, function()
                    if BoogieDetected[Handle] then return end
                    BoogieDetected[Handle] = true
                    QueueGriefNotification(Owner.Name.." used Boogie Bomb on you!", Owner.Name, "Boogie Bomb")
                end)
            end

            local HitMissiles = {}
            local function TrackMissile(Child)
                local Username = Child.Name:match("Missle_(.+)")
                if not Username or Username == LocalPlayer.Name then return end
                if not Child:IsA("BasePart") then return end
                local function OnHit()
                    if HitMissiles[Child] then return end
                    HitMissiles[Child] = true
                    QueueGriefNotification(Username.." used Heatseeker on you!", Username, "Heatseeker")
                    GriefConnect(Child.AncestryChanged, function() if not Child.Parent then HitMissiles[Child] = nil end end)
                end
                GriefConnect(Child.Touched, function(Hit)
                    local Char = LocalPlayer.Character
                    if Char and Hit:IsDescendantOf(Char) then OnHit() end
                end)
                GriefConnect(RunService.Heartbeat, function()
                    if HitMissiles[Child] or not Child.Parent then return end
                    local HRP = GetHRP()
                    if HRP and (Child.Position - HRP.Position).Magnitude <= 15 then OnHit() end
                end)
            end

            local DogeLastHit = 0
            local WatchedDoges = {}
            local function WatchDoge(Child)
                local Username = Child.Name:match("^PlayerName_(.+)_Doge$")
                if not Username or Username == LocalPlayer.Name or WatchedDoges[Child] then return end
                WatchedDoges[Child] = true
                local Parts = Child:IsA("BasePart") and {Child} or Child:GetDescendants()
                for _, Part in ipairs(Parts) do
                    if not Part:IsA("BasePart") then continue end
                    GriefConnect(Part.Touched, function(Hit)
                        local Char = LocalPlayer.Character
                        if not Char or not Hit:IsDescendantOf(Char) then return end
                        if tick() - DogeLastHit < 2 then return end
                        DogeLastHit = tick()
                        QueueGriefNotification(Username.." used Attack Doge on you!", Username, "Attack Doge")
                    end)
                end
            end

            local PaintballLastHit = 0
            local LaserDetected = {}
            local LaserLastHit = 0
            local function OnLaserHit()
                if tick() - LaserLastHit < 2 then return end
                local Holder = GetHolder("Laser Cape")
                if not Holder then return end
                LaserLastHit = tick()
                QueueGriefNotification(Holder.Name.." used Laser Cape on you!", Holder.Name, "Laser Cape")
            end

            local MedusaLastHit = 0
            local MedusaRadius = (33.986812591552734 + 33.986873626708984) / 2 / 2 * math.pi
            local BodyPartSet = {
                LeftFoot=true,RightFoot=true,LeftLowerLeg=true,RightLowerLeg=true,
                LeftUpperLeg=true,RightUpperLeg=true,LeftHand=true,RightHand=true,
                LeftLowerArm=true,RightLowerArm=true,LeftUpperArm=true,RightUpperArm=true,
                UpperTorso=true,LowerTorso=true,Head=true
            }

            local HitCooldowns = {}
            local LocalJustFired = false
            local PrevHolderPos, PrevLocalPos = nil, nil
            local function HookLocalPotion()
                local Char = LocalPlayer.Character
                if not Char then return end
                local function HookPotion(Potion)
                    Potion.Activated:Connect(function()
                        LocalJustFired = true
                        task.delay(1, function() LocalJustFired = false end)
                    end)
                end
                local Potion = Char:FindFirstChild("Body Swap Potion")
                if Potion then HookPotion(Potion) end
                GriefConnect(Char.ChildAdded, function(Child)
                    if Child.Name == "Body Swap Potion" then HookPotion(Child) end
                end)
            end
            GriefConnect(LocalPlayer.CharacterAdded, HookLocalPotion)
            HookLocalPotion()

            GriefConnect(workspace.ChildAdded, function(Child)
                local SentryId = Child.Name:match("Sentry_(%d+)")
                if SentryId then
                    local Ok2, Name = pcall(Players.GetNameFromUserIdAsync, Players, tonumber(SentryId))
                    SentryOwners[Ok2 and Name or "Unknown"] = true
                end
                TrackBullet(Child)
                if Child:IsA("Model") or Child:IsA("Folder") then GriefConnect(Child.DescendantAdded, TrackBullet) end
                if Child.Name == "Handle" then TrackHandle(Child) end
                TrackMissile(Child)
                WatchDoge(Child)

                if Child:IsA("BasePart") and math.abs(Child.Size.X-1) <= 0.1 and math.abs(Child.Size.Y-1) <= 0.1 and math.abs(Child.Size.Z-0.1) <= 0.1 then
                    local Holder = GetHolder("Paintball Gun")
                    if Holder then
                        local TouchConn, HeartbeatConn
                        local function OnHit()
                            if tick() - PaintballLastHit < 2 then return end
                            PaintballLastHit = tick()
                            QueueGriefNotification(Holder.Name.." used Paintball Gun on you!", Holder.Name, "Paintball Gun")
                            TouchConn:Disconnect()
                            HeartbeatConn:Disconnect()
                        end
                        TouchConn = GriefConnect(Child.Touched, function(Hit)
                            local Char = LocalPlayer.Character
                            if Char and Hit:IsDescendantOf(Char) then OnHit() end
                        end)
                        HeartbeatConn = GriefConnect(RunService.Heartbeat, function()
                            if not Child.Parent then TouchConn:Disconnect() HeartbeatConn:Disconnect() return end
                            local HRP = GetHRP()
                            if HRP and (Child.Position - HRP.Position).Magnitude <= 3 then OnHit() end
                        end)
                    end
                end

                if Child:IsA("BasePart") and Child:FindFirstChildWhichIsA("Attachment")
                    and math.abs(Child.Size.X-0.2) <= 0.01 and math.abs(Child.Size.Y-0.2) <= 0.01 and math.abs(Child.Size.Z-0.2) <= 0.01
                    and not LaserDetected[Child] then
                    local Holder = GetHolder("Laser Cape")
                    if Holder then
                        local Char = LocalPlayer.Character
                        local HRP = GetHRP()
                        local MyHead = Char and Char:FindFirstChild("Head")
                        if HRP and (Child.Position - HRP.Position).Magnitude <= 8 then
                            local HolderHead = Holder.Character and Holder.Character:FindFirstChild("Head")
                            if HolderHead and HolderHead:FindFirstChildWhichIsA("Attachment") then
                                if MyHead and MyHead:FindFirstChildWhichIsA("Attachment") then
                                    local HeadAtt = MyHead:FindFirstChildWhichIsA("Attachment")
                                    local PartAtt = Child:FindFirstChildWhichIsA("Attachment")
                                    if HeadAtt.WorldPosition == PartAtt.WorldPosition then return end
                                end
                                LaserDetected[Child] = true
                                OnLaserHit()
                            end
                        end
                    end
                end

                if Child:IsA("MeshPart") and BodyPartSet[Child.Name] and tick() - MedusaLastHit >= 3 then
                    local Holder = GetHolder("Medusa's Head")
                    if Holder then
                        local HolderHRP = Holder.Character and Holder.Character:FindFirstChild("HumanoidRootPart")
                        if HolderHRP then
                            local Start = tick()
                            local Conn
                            Conn = GriefConnect(RunService.Heartbeat, function()
                                if tick() - MedusaLastHit < 3 or tick() - Start > 1 then Conn:Disconnect() return end
                                local Char = LocalPlayer.Character
                                local HRP = GetHRP()
                                if not HRP then return end
                                local D = HolderHRP.Position - HRP.Position
                                if math.sqrt(D.X^2 + D.Z^2) > MedusaRadius then return end
                                local LocalPart = Char:FindFirstChild(Child.Name)
                                if LocalPart and (Child.Position - LocalPart.Position).Magnitude <= 2 then
                                    MedusaLastHit = tick()
                                    Conn:Disconnect()
                                    QueueGriefNotification(Holder.Name.." used Medusa's Head on you!", Holder.Name, "Medusa's Head")
                                end
                            end)
                        end
                    end
                end

                if Child.Name == "WebRope" and Child:IsA("RopeConstraint") then
                    local Holder = GetHolder("Web Slinger")
                    if Holder then
                        local Conn
                        Conn = GriefConnect(RunService.Heartbeat, function()
                            if not Child.Parent then Conn:Disconnect() return end
                            local Char = LocalPlayer.Character
                            if not Char then return end
                            if (Child.Attachment0 and Child.Attachment0:IsDescendantOf(Char)) or (Child.Attachment1 and Child.Attachment1:IsDescendantOf(Char)) then
                                QueueGriefNotification(Holder.Name.." used Web Slinger on you!", Holder.Name, "Web Slinger")
                                Conn:Disconnect()
                            end
                        end)
                    end
                end
            end)

            GriefConnect(RunService.Heartbeat, function()
                local HRP = GetHRP()
                if HRP then
                    for _, Child in ipairs(workspace:GetChildren()) do
                        local Username = Child.Name:match("^PlayerName_(.+)_Doge$")
                        if not Username or Username == LocalPlayer.Name then continue end
                        local Part = Child:IsA("BasePart") and Child or Child:FindFirstChildWhichIsA("BasePart", true)
                        if not Part or (Part.Position - HRP.Position).Magnitude > 5 then continue end
                        if tick() - DogeLastHit < 2 then continue end
                        DogeLastHit = tick()
                        QueueGriefNotification(Username.." used Attack Doge on you!", Username, "Attack Doge")
                    end
                end

                local Holder = GetHolder("Body Swap Potion")
                if not Holder then PrevHolderPos = nil PrevLocalPos = nil return end
                local Cooldown = HitCooldowns[Holder.Name]
                if Cooldown and tick() - Cooldown < 30 then return end
                local HolderHRP = Holder.Character and Holder.Character:FindFirstChild("HumanoidRootPart")
                local LocalHRP = GetHRP()
                if not HolderHRP or not LocalHRP then return end
                local CurrHolder, CurrLocal = HolderHRP.Position, LocalHRP.Position
                if PrevHolderPos and PrevLocalPos then
                    if (CurrHolder - PrevLocalPos).Magnitude <= 12 and (CurrLocal - PrevHolderPos).Magnitude <= 12 and not LocalJustFired then
                        HitCooldowns[Holder.Name] = tick()
                        QueueGriefNotification(Holder.Name.." used Body Swap Potion on you!", Holder.Name, "Body Swap Potion")
                    end
                end
                PrevHolderPos = CurrHolder
                PrevLocalPos = CurrLocal
            end)

            pcall(function()
                local NotificationFolder = LocalPlayer.PlayerGui:WaitForChild("Notification", 5) and LocalPlayer.PlayerGui.Notification:WaitForChild("Notification", 5)
                if NotificationFolder then
                    GriefConnect(NotificationFolder.ChildAdded, function(Child)
                        if not Child:IsA("TextLabel") then return end
                        local Text = Child.Text
                        if not (Text:find("ragdoll") or Text:find("balloon") or Text:find("rocket")) then return end
                        for _, Player in ipairs(Players:GetPlayers()) do
                            if Player == LocalPlayer then continue end
                            if Text:find(Player.Name, 1, true) then
                                local Command = Text:match('"([^"]+)"')
                                if Command then
                                    local CommandName = Command:sub(1,1):upper()..Command:sub(2)
                                    QueueGriefNotification(Player.Name.." used "..CommandName.." on you!", Player.Name, CommandName)
                                end
                                return
                            end
                        end
                    end)
                end
            end)

            for _, C in ipairs(workspace:GetChildren()) do
                local SentryId = C.Name:match("Sentry_(%d+)")
                if SentryId then
                    local Ok2, Name = pcall(Players.GetNameFromUserIdAsync, Players, tonumber(SentryId))
                    SentryOwners[Ok2 and Name or "Unknown"] = true
                end
                TrackBullet(C)
                if C.Name == "Handle" then TrackHandle(C) end
                WatchDoge(C)
                TrackMissile(C)
            end

            local Ok2, Net = pcall(function() return ReplicatedStorage.Packages.Net end)
            if Ok2 and Net then
                for _, v in ipairs(Net:GetChildren()) do
                    if v.Name == "Ragdoll" and v:IsA("RemoteEvent") then
                        GriefConnect(v.OnClientEvent, OnLaserHit)
                    end
                    if v.Name:sub(1,3) ~= "RE/" then continue end
                    local Children = Net:GetChildren()
                    local Remote = Children[table.find(Children, v) + 1]
                    if not Remote or not Remote:IsA("RemoteEvent") then continue end
                    GriefConnect(Remote.OnClientEvent, function(...)
                        local Args = {...}
                        if #Args < 1 or typeof(Args[1]) ~= "Instance" or Args[1].Name ~= "Hit" then return end
                        local Hit = Args[1]
                        local rawGear = Args[2]
                        local Gear = (typeof(rawGear) == "string" and rawGear ~= "" and not rawGear:match("^#%x+$") and not tonumber(rawGear)) and rawGear or (Hit.Parent and Hit.Parent.Name or "Unknown")
                        local Char = Hit.Parent and Hit.Parent.Parent
                        if not Char then return end
                        local Plr = Players:GetPlayerFromCharacter(Char)
                        local Attacker = Plr and Plr.Name or Char.Name
                        if Attacker ~= "Unknown" and Attacker ~= LocalPlayer.Name then
                            QueueGriefNotification(Attacker.." used "..Gear.." on you!", Attacker, Gear)
                        end
                    end)
                end
            end

            _G.GriefDetectorTest = function()
                local fakeSteal = {
                    displayName = "Dragon Cannelloni",
                    rawName = "dragon-cannelloni",
                    mutation = "Gold",
                    traits = {},
                    genValue = 250000000,
                    genText = "$250m/s",
                }
                Notify("TestGriefer", LocalPlayer.Name, "Boogie Bomb", "Atlas", fakeSteal)
            end
        end

        local function StopGriefDetector()
            if not GriefActive then return end
            GriefActive = false
            for _, conn in ipairs(GriefConnections) do
                if typeof(conn) == "RBXScriptConnection" then
                    pcall(function() conn:Disconnect() end)
                end
            end
            GriefConnections = {}
            if GriefScreenGui then
                pcall(function() GriefScreenGui:Destroy() end)
                GriefScreenGui = nil
            end
            _G.GriefDetectorTest = nil
        end

        _G.GriefDetectorSetEnabled = function(enabled)
            if enabled then
                StartGriefDetector()
            else
                StopGriefDetector()
            end
        end

        if Config.GriefDetectorEnabled == nil then Config.GriefDetectorEnabled = true end
        if Config.GriefDetectorEnabled then
            task.spawn(function()
                task.wait(3)
                if Config.GriefDetectorEnabled then
                    StartGriefDetector()
                end
            end)
        end
        end)
        if not ok then
            warn("[Haze] GRIEF DETECTOR failed: " .. tostring(err))
            if type(ShowNotification) == "function" then pcall(ShowNotification, "GRIEF DETECTOR", "Load failed") end
        end
    end)
    -- ===== END GRIEF DETECTOR =====

    -- ===== BEGIN AUTO BUY (ported from CNK) =====
    task.spawn(function()
        local ok, err = pcall(function()
    local autoBuyActive = false
        _G.AutoBuyEsteira = false

        Config.Positions = Config.Positions or {}
        Config.Positions.AutoBuy = Config.Positions.AutoBuy or {X = 0.72, Y = 0.34, OffsetX = 0, OffsetY = 0}
        if not Config.AutoBuyKey   then Config.AutoBuyKey   = "K"  end
        if not Config.AutoBuyRange then Config.AutoBuyRange = 17   end
        if not Config.AutoBuyColor then Config.AutoBuyColor = {R=180,G=180,B=180} end

        local oldAB = PlayerGui:FindFirstChild("XiAutoBuyUI")
        if oldAB then oldAB:Destroy() end

        local abGui = Instance.new("ScreenGui")
        abGui.Name         = "XiAutoBuyUI"
        abGui.ResetOnSpawn = false
        abGui.DisplayOrder = 30
        abGui.Parent       = PlayerGui

        local abPanel = Instance.new("Frame", abGui)
        abPanel.Name             = "ABPanel"
        abPanel.Size             = UDim2.new(0, 280, 0, 302)
        abPanel.Position         = UDim2.new(Config.Positions.AutoBuy.X, Config.Positions.AutoBuy.OffsetX or 0, Config.Positions.AutoBuy.Y, Config.Positions.AutoBuy.OffsetY or 0)
        abPanel.BackgroundColor3 = Theme.Background
        abPanel.BackgroundTransparency = 0.08
        abPanel.BorderSizePixel  = 0
        Instance.new("UICorner", abPanel).CornerRadius = UDim.new(0, 0)
        local abStroke = Instance.new("UIStroke", abPanel)
        abStroke.Color = Theme.Accent1; abStroke.Thickness = 1.8; abStroke.Transparency = 0.35

        local abHdr = Instance.new("Frame", abPanel)
        abHdr.Size               = UDim2.new(1, 0, 0, 36)
        abHdr.BackgroundTransparency = 1
        MakeDraggable(abHdr, abPanel, "AutoBuy")

        local abTitle = Instance.new("TextLabel", abHdr)
        abTitle.Size             = UDim2.new(1, -12, 1, 0)
        abTitle.Position         = UDim2.new(0, 12, 0, 0)
        abTitle.BackgroundTransparency = 1
        abTitle.Text             = "AUTO BUY"
        abTitle.Font             = Enum.Font.GothamBlack
        abTitle.TextSize         = 15
        abTitle.TextColor3       = Theme.Accent1
        abTitle.TextXAlignment   = Enum.TextXAlignment.Left

        local abDiv = Instance.new("Frame", abPanel)
        abDiv.Size             = UDim2.new(1, -20, 0, 1)
        abDiv.Position         = UDim2.new(0, 10, 0, 36)
        abDiv.BackgroundColor3 = Theme.Accent1
        abDiv.BackgroundTransparency = 0.6
        abDiv.BorderSizePixel  = 0

        local abContent = Instance.new("Frame", abPanel)
        abContent.Size             = UDim2.new(1, -16, 1, -46)
        abContent.Position         = UDim2.new(0, 8, 0, 44)
        abContent.BackgroundTransparency = 1
        local abLayout = Instance.new("UIListLayout", abContent)
        abLayout.Padding   = UDim.new(0, 6)
        abLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local function makeAbRow(h, order)
            local r = Instance.new("Frame", abContent)
            r.Size             = UDim2.new(1, 0, 0, h)
            r.BackgroundColor3 = Theme.Surface
            r.BackgroundTransparency = 0.05
            r.BorderSizePixel  = 0
            r.LayoutOrder      = order
            Instance.new("UICorner", r).CornerRadius = UDim.new(0, 0)
            return r
        end

        -- 1) Toggle
        local abToggleRow = makeAbRow(38, 1)
        local abToggleBtn = Instance.new("TextButton", abToggleRow)
        abToggleBtn.Size             = UDim2.new(1, 0, 1, 0)
        abToggleBtn.BackgroundColor3 = Theme.Surface
        abToggleBtn.BackgroundTransparency = 0
        abToggleBtn.Text             = "AUTO BUY: OFF"
        abToggleBtn.Font             = Enum.Font.GothamBlack
        abToggleBtn.TextSize         = 13
        abToggleBtn.TextColor3       = Theme.TextSecondary
        abToggleBtn.BorderSizePixel  = 0
        abToggleBtn.AutoButtonColor  = false
        Instance.new("UICorner", abToggleBtn).CornerRadius = UDim.new(1, 0)
        local abToggleStroke = Instance.new("UIStroke", abToggleBtn)
        abToggleStroke.Color = Theme.Accent1; abToggleStroke.Thickness = 1.5; abToggleStroke.Transparency = 0.5

        -- 2) Keybind
        local abKeyRow = makeAbRow(34, 2)
        local abKeyLbl = Instance.new("TextLabel", abKeyRow)
        abKeyLbl.Size             = UDim2.new(1, -70, 1, 0)
        abKeyLbl.Position         = UDim2.new(0, 10, 0, 0)
        abKeyLbl.BackgroundTransparency = 1
        abKeyLbl.Text             = "Keybind"
        abKeyLbl.Font             = Enum.Font.GothamBold
        abKeyLbl.TextSize         = 12
        abKeyLbl.TextColor3       = Theme.TextPrimary
        abKeyLbl.TextXAlignment   = Enum.TextXAlignment.Left
        local abKeyBtn = Instance.new("TextButton", abKeyRow)
        abKeyBtn.Size             = UDim2.new(0, 56, 0, 24)
        abKeyBtn.Position         = UDim2.new(1, -62, 0.5, -12)
        abKeyBtn.BackgroundColor3 = Theme.SurfaceHighlight
        abKeyBtn.Text             = Config.AutoBuyKey or "K"
        abKeyBtn.Font             = Enum.Font.GothamBold
        abKeyBtn.TextSize         = 11
        abKeyBtn.TextColor3       = Theme.Accent1
        abKeyBtn.AutoButtonColor  = false
        abKeyBtn.BorderSizePixel  = 0
        Instance.new("UICorner", abKeyBtn).CornerRadius = UDim.new(1, 0)
        abKeyBtn.MouseButton1Click:Connect(function()
            abKeyBtn.Text = "..."; abKeyBtn.TextColor3 = Theme.TextSecondary
            local c; c = game:GetService("UserInputService").InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.Keyboard then
                    Config.AutoBuyKey = inp.KeyCode.Name
                    abKeyBtn.Text = inp.KeyCode.Name
                    abKeyBtn.TextColor3 = Theme.Accent1
                    SaveConfig(); c:Disconnect()
                end
            end)
        end)

        -- 3) Range slider
        local abRangeRow = makeAbRow(42, 3)
        local abRangeLbl = Instance.new("TextLabel", abRangeRow)
        abRangeLbl.Size           = UDim2.new(1, -10, 0, 16)
        abRangeLbl.Position       = UDim2.new(0, 10, 0, 4)
        abRangeLbl.BackgroundTransparency = 1
        abRangeLbl.Text           = "Range: " .. (Config.AutoBuyRange or 17) .. " studs"
        abRangeLbl.Font           = Enum.Font.GothamBold
        abRangeLbl.TextSize       = 11
        abRangeLbl.TextColor3     = Theme.TextPrimary
        abRangeLbl.TextXAlignment = Enum.TextXAlignment.Left
        local abSlBg = Instance.new("Frame", abRangeRow)
        abSlBg.Size             = UDim2.new(1, -20, 0, 6)
        abSlBg.Position         = UDim2.new(0, 10, 0, 28)
        abSlBg.BackgroundColor3 = Theme.SurfaceHighlight
        abSlBg.BorderSizePixel  = 0
        Instance.new("UICorner", abSlBg).CornerRadius = UDim.new(1, 0)
        local abSlFill = Instance.new("Frame", abSlBg)
        abSlFill.BackgroundColor3 = Theme.Accent1
        abSlFill.BorderSizePixel  = 0
        Instance.new("UICorner", abSlFill).CornerRadius = UDim.new(1, 0)
        local abSlKnob = Instance.new("Frame", abSlBg)
        abSlKnob.Size         = UDim2.new(0, 13, 0, 13)
        abSlKnob.AnchorPoint  = Vector2.new(0.5, 0.5)
        abSlKnob.BackgroundColor3 = Color3.new(1, 1, 1)
        abSlKnob.BorderSizePixel  = 0
        Instance.new("UICorner", abSlKnob).CornerRadius = UDim.new(1, 0)
        local abSlKS = Instance.new("UIStroke", abSlKnob)
        abSlKS.Color = Theme.Accent1; abSlKS.Thickness = 1.5
        local AB_MIN, AB_MAX = 5, 40
        local function updateAbSlider(v)
            v = math.clamp(math.floor(v), AB_MIN, AB_MAX)
            Config.AutoBuyRange = v; SaveConfig()
            abRangeLbl.Text = "Range: " .. v .. " studs"
            local pct = (v - AB_MIN) / (AB_MAX - AB_MIN)
            abSlFill.Size     = UDim2.new(pct, 0, 1, 0)
            abSlKnob.Position = UDim2.new(pct, 0, 0.5, 0)
            local ring = workspace:FindFirstChild("XiAutoBuyRing")
            if ring then ring.Size = Vector3.new(0.5, v*2, v*2) end
        end
        updateAbSlider(Config.AutoBuyRange or 17)
        local abDrag = false
        abSlBg.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
                abDrag=true
                updateAbSlider(AB_MIN+((i.Position.X-abSlBg.AbsolutePosition.X)/abSlBg.AbsoluteSize.X)*(AB_MAX-AB_MIN))
            end
        end)
        game:GetService("UserInputService").InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then abDrag=false end
        end)
        game:GetService("UserInputService").InputChanged:Connect(function(i)
            if abDrag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
                updateAbSlider(AB_MIN+((i.Position.X-abSlBg.AbsolutePosition.X)/abSlBg.AbsoluteSize.X)*(AB_MAX-AB_MIN))
            end
        end)

        -- 4) Circle color swatches
        local abCircleRow = makeAbRow(60, 4)
        local abCircleLbl = Instance.new("TextLabel", abCircleRow)
        abCircleLbl.Size             = UDim2.new(1, 0, 0, 18)
        abCircleLbl.Position         = UDim2.new(0, 10, 0, 4)
        abCircleLbl.BackgroundTransparency = 1
        abCircleLbl.Text             = "Circle Color"
        abCircleLbl.Font             = Enum.Font.GothamBold
        abCircleLbl.TextSize         = 11
        abCircleLbl.TextColor3       = Theme.TextPrimary
        abCircleLbl.TextXAlignment   = Enum.TextXAlignment.Left
        local THEME_SWATCHES = {
            Color3.fromRGB(255,120,200), Color3.fromRGB(0,220,255), Color3.fromRGB(255,215,0),
            Color3.fromRGB(210,215,235), Color3.fromRGB(200,200,210), Color3.fromRGB(180,80,255),
            Color3.fromRGB(0,220,80), Color3.fromRGB(180,80,255),
        }
        local abSwatchFrame = Instance.new("Frame", abCircleRow)
        abSwatchFrame.Size             = UDim2.new(1, -16, 0, 36)
        abSwatchFrame.Position         = UDim2.new(0, 8, 0, 22)
        abSwatchFrame.BackgroundTransparency = 1
        local swatchGrid = Instance.new("UIGridLayout", abSwatchFrame)
        swatchGrid.CellSize      = UDim2.new(0, 24, 0, 16)
        swatchGrid.CellPadding   = UDim2.new(0, 4, 0, 4)
        swatchGrid.SortOrder     = Enum.SortOrder.LayoutOrder
        swatchGrid.FillDirection = Enum.FillDirection.Horizontal
        local function buildCirclePresets()
            for _, ch in ipairs(abSwatchFrame:GetChildren()) do
                if ch:IsA("TextButton") then ch:Destroy() end
            end
            for i, col in ipairs(THEME_SWATCHES) do
                local cb = Instance.new("TextButton", abSwatchFrame)
                cb.LayoutOrder      = i
                cb.Size             = UDim2.new(0, 24, 0, 16)
                cb.BackgroundColor3 = col
                cb.Text             = ""
                cb.BorderSizePixel  = 0
                cb.AutoButtonColor  = false
                Instance.new("UICorner", cb).CornerRadius = UDim.new(0, 0)
                local selStroke = Instance.new("UIStroke", cb)
                selStroke.Thickness = 1.5
                local cur = Config.AutoBuyColor
                local match = cur and math.abs(cur.R - math.floor(col.R*255)) < 2
                                  and math.abs(cur.G - math.floor(col.G*255)) < 2
                                  and math.abs(cur.B - math.floor(col.B*255)) < 2
                selStroke.Color        = Color3.new(1,1,1)
                selStroke.Transparency = match and 0 or 1
                cb.MouseButton1Click:Connect(function()
                    Config.AutoBuyColor = {
                        R = math.floor(col.R*255),
                        G = math.floor(col.G*255),
                        B = math.floor(col.B*255),
                    }
                    SaveConfig()
                    local ring = workspace:FindFirstChild("XiAutoBuyRing")
                    if ring then ring.Color = col end
                    buildCirclePresets()
                end)
            end
        end
        buildCirclePresets()

        -- 5) Rejoin Server button
        local abRejoinRow = makeAbRow(34, 5)
        local abRejoinBtn = Instance.new("TextButton", abRejoinRow)
        abRejoinBtn.Size             = UDim2.new(1, -16, 0, 24)
        abRejoinBtn.Position         = UDim2.new(0, 8, 0.5, -12)
        abRejoinBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
        abRejoinBtn.Text             = "REJOIN SERVER"
        abRejoinBtn.Font             = Enum.Font.GothamBlack
        abRejoinBtn.TextSize         = 12
        abRejoinBtn.TextColor3       = Color3.new(1, 1, 1)
        abRejoinBtn.BorderSizePixel  = 0
        abRejoinBtn.AutoButtonColor  = false
        Instance.new("UICorner", abRejoinBtn).CornerRadius = UDim.new(1, 0)
        local rejoinStroke = Instance.new("UIStroke", abRejoinBtn)
        rejoinStroke.Color = Color3.fromRGB(255, 100, 100)
        rejoinStroke.Thickness = 1.5
        rejoinStroke.Transparency = 0.4
        abRejoinBtn.MouseEnter:Connect(function() abRejoinBtn.BackgroundTransparency = 0.15 end)
        abRejoinBtn.MouseLeave:Connect(function() abRejoinBtn.BackgroundTransparency = 0 end)
        abRejoinBtn.MouseButton1Click:Connect(function()
            abRejoinBtn.Text = "Rejoining..."
            abRejoinBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
            task.wait(0.3)
            pcall(function()
                game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end)
        end)

        -- Ring indicator
        local abRing = nil
        local function getCircleColor()
            if Config.AutoBuyColor then
                local c = Config.AutoBuyColor
                return Color3.fromRGB(c.R, c.G, c.B)
            end
            return Theme.Accent1
        end
        local function createRing()
            local existing = workspace:FindFirstChild("XiAutoBuyRing")
            if existing then existing:Destroy() end
            local r = Instance.new("Part")
            r.Name         = "XiAutoBuyRing"
            r.Shape        = Enum.PartType.Cylinder
            r.Anchored     = true
            r.CanCollide   = false
            r.CanTouch     = false
            r.CanQuery     = false
            r.CastShadow   = false
            r.Material     = Enum.Material.Neon
            r.Transparency = 0.5
            r.Color        = getCircleColor()
            local range    = Config.AutoBuyRange or 17
            r.Size         = Vector3.new(0.5, range*2, range*2)
            r.Parent       = workspace
            abRing = r
        end
        local function destroyRing()
            if abRing then abRing:Destroy(); abRing = nil end
            local existing = workspace:FindFirstChild("XiAutoBuyRing")
            if existing then existing:Destroy() end
        end

        local _abRingFrame = 0
        game:GetService("RunService").Heartbeat:Connect(function()
            if not autoBuyActive then return end
            _abRingFrame = _abRingFrame + 1
            if _abRingFrame < 3 then return end
            _abRingFrame = 0
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp or not abRing or not abRing.Parent then return end
            local range = Config.AutoBuyRange or 17
            abRing.Size  = Vector3.new(0.5, range*2, range*2)
            abRing.CFrame = hrp.CFrame * CFrame.Angles(0, 0, math.rad(90)) + Vector3.new(0, -2.5, 0)
        end)

        local function toggleAutoBuy()
            autoBuyActive = not autoBuyActive
            _G.AutoBuyEsteira = autoBuyActive
            if autoBuyActive then
                abToggleBtn.Text             = "AUTO BUY: ON"
                abToggleBtn.BackgroundColor3 = Theme.Accent1
                abToggleBtn.TextColor3       = Color3.new(0, 0, 0)
                abToggleStroke.Transparency  = 1
                createRing()
            else
                abToggleBtn.Text             = "AUTO BUY: OFF"
                abToggleBtn.BackgroundColor3 = Theme.Surface
                abToggleBtn.TextColor3       = Theme.TextSecondary
                abToggleStroke.Transparency  = 0.5
                destroyRing()
            end
            if _G.AutoBuyOnToggle then _G.AutoBuyOnToggle(autoBuyActive) end
            ShowNotification("AUTO BUY", autoBuyActive and "ENABLED" or "DISABLED")
        end

        abToggleBtn.MouseButton1Click:Connect(toggleAutoBuy)

        game:GetService("UserInputService").InputBegan:Connect(function(inp, gp)
            if gp then return end
            local ok2, kc = pcall(function() return Enum.KeyCode[Config.AutoBuyKey or "K"] end)
            if ok2 and kc and inp.KeyCode == kc then toggleAutoBuy() end
        end)

        LocalPlayer.CharacterAdded:Connect(function()
            task.wait(0.05)
            if autoBuyActive then createRing() end
        end)

        -- Backend scanner
        task.spawn(function()
            local Packages2  = ReplicatedStorage:WaitForChild("Packages")
            local Datas2     = ReplicatedStorage:WaitForChild("Datas")
            local Shared2    = ReplicatedStorage:WaitForChild("Shared")
            local Utils2     = ReplicatedStorage:WaitForChild("Utils")
            local AnimData   = require(Datas2:WaitForChild("Animals"))
            local AnimShared = require(Shared2:WaitForChild("Animals"))
            local NumUtils   = require(Utils2:WaitForChild("NumberUtils"))

            local RARITY_WORDS = {
                ["common"]=true,["uncommon"]=true,["rare"]=true,["epic"]=true,
                ["legendary"]=true,["secret"]=true,["divine"]=true,["rainbow"]=true,
                ["cursed"]=true,["gold"]=true,["diamond"]=true,
            }

            local function getBrainrotName(model)
                if not model then return "Brainrot","" end
                local nameFound, genFound = "",""
                for _, bb in ipairs(model:GetDescendants()) do
                    if bb:IsA("BillboardGui") then
                        for _, lbl in ipairs(bb:GetDescendants()) do
                            if lbl:IsA("TextLabel") and lbl.Text and lbl.Text ~= "" then
                                local t = lbl.Text:match("^%s*(.-)%s*$")
                                local tl = t:lower()
                                if RARITY_WORDS[tl] then continue end
                                if t:match("^%$[%d%.]+[KkMmBb]?/s$") then
                                    if genFound=="" then genFound=t end; continue
                                end
                                if t:match("^%$[%d%.]+[KkMmBb]?$") then continue end
                                if t:match("^[%d%.]+[KkMmBb]?$") then continue end
                                if nameFound=="" and #t>1 then nameFound=t end
                            end
                        end
                    end
                end
                if nameFound=="" then
                    pcall(function()
                        local info = AnimData[model.Name]
                        if info and info.DisplayName then
                            nameFound = info.DisplayName
                            local gv = AnimShared:GetGeneration(model.Name,nil,nil,nil)
                            genFound = "$"..NumUtils:ToString(gv).."/s"
                        end
                    end)
                end
                if nameFound=="" then nameFound = model.Name~="" and model.Name or "Brainrot" end
                return nameFound, genFound
            end

            local function scanConveyor()
                local results = {}
                for _, obj in ipairs(workspace:GetDescendants()) do
                    if not (obj:IsA("ProximityPrompt") and obj.Enabled) then continue end
                    local txt = obj.ActionText or ""
                    if not (txt=="Purchase" or txt:lower():find("purchase") or txt:lower():find("comprar")) then continue end
                    local part = obj.Parent
                    if not part then continue end
                    local realPart = part:IsA("Attachment") and part.Parent or part
                    if not (realPart and realPart:IsA("BasePart")) then continue end
                    local model, cur = nil, realPart
                    for _ = 1, 8 do
                        if cur and cur:IsA("Model") then model=cur; break end
                        cur = cur and cur.Parent
                    end
                    local name, gen = getBrainrotName(model)
                    table.insert(results, {
                        name=name, gen=gen, prompt=obj, part=realPart,
                        model=model, source="ESTEIRA", uid="esteira_"..tostring(obj),
                    })
                end
                return results
            end

            SharedState.ConveyorAnimals = {}
            local function refreshConveyor()
                local ok2, found = pcall(scanConveyor)
                if ok2 and found then SharedState.ConveyorAnimals = found end
            end
            refreshConveyor()
            _G.refreshConveyor = refreshConveyor

            local carpetLockConn = nil
            local function startCarpetLock()
                if carpetLockConn then carpetLockConn:Disconnect(); carpetLockConn = nil end
                task.spawn(function()
                    for _ = 1, 15 do
                        if not autoBuyActive then break end
                        pcall(function()
                            local char = LocalPlayer.Character
                            local hum  = char and char:FindFirstChildOfClass("Humanoid")
                            if not hum then return end
                            local toolName = Config.TpSettings and Config.TpSettings.Tool or "Flying Carpet"
                            if not char:FindFirstChild(toolName) then
                                local tool = LocalPlayer.Backpack:FindFirstChild(toolName)
                                if tool then hum:EquipTool(tool) end
                            end
                        end)
                        task.wait(0.3)
                        local char = LocalPlayer.Character
                        local toolName = Config.TpSettings and Config.TpSettings.Tool or "Flying Carpet"
                        if char and char:FindFirstChild(toolName) then break end
                    end
                end)
                carpetLockConn = game:GetService("RunService").Heartbeat:Connect(function()
                    if not autoBuyActive then return end
                    pcall(function()
                        local char = LocalPlayer.Character
                        local hum  = char and char:FindFirstChildOfClass("Humanoid")
                        if not hum then return end
                        local toolName = Config.TpSettings and Config.TpSettings.Tool or "Flying Carpet"
                        if not char:FindFirstChild(toolName) then
                            local tool = LocalPlayer.Backpack:FindFirstChild(toolName)
                            if tool then hum:EquipTool(tool) end
                        end
                    end)
                end)
            end
            local function stopCarpetLock()
                if carpetLockConn then carpetLockConn:Disconnect(); carpetLockConn = nil end
            end

            local HOVER_HEIGHT  = 5
            local BUY_INTERVAL  = 0.08
            local lockedTarget  = nil
            local lockedPart    = nil
            local lockedModel   = nil

            local function partAlive()
                return lockedPart  and lockedPart.Parent
                    and lockedModel and lockedModel.Parent
            end
            local function promptAlive()
                return lockedTarget and lockedTarget.prompt
                    and lockedTarget.prompt.Parent and lockedTarget.prompt.Enabled
            end

            game:GetService("RunService").Heartbeat:Connect(function()
                if not autoBuyActive or not partAlive() then return end
                local char = LocalPlayer.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                if not hrp then return end
                hrp.CFrame = CFrame.new(lockedPart.Position + Vector3.new(0, HOVER_HEIGHT, 0))
            end)

            task.spawn(function()
                while true do
                    task.wait(BUY_INTERVAL)
                    if not autoBuyActive then continue end
                    if not partAlive()   then continue end
                    if promptAlive() then
                        pcall(function()
                            if fireproximityprompt then fireproximityprompt(lockedTarget.prompt) end
                        end)
                    end
                end
            end)

            task.spawn(function()
                while true do
                    task.wait(0.25)
                    if not autoBuyActive then
                        lockedTarget=nil; lockedPart=nil; lockedModel=nil
                        stopCarpetLock()
                        continue
                    end
                    if lockedPart or lockedModel then
                        if not partAlive() then
                            ShowNotification("AUTO BUY", "Reached base, scanning...")
                            lockedTarget=nil; lockedPart=nil; lockedModel=nil
                        end
                        continue
                    end
                    local char = LocalPlayer.Character
                    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                    if not hrp then continue end
                    local best, bestDist = nil, math.huge
                    for _, entry in ipairs(SharedState.ConveyorAnimals or {}) do
                        if entry.prompt and entry.prompt.Parent and entry.prompt.Enabled
                        and entry.part  and entry.part.Parent then
                            local d = (hrp.Position - entry.part.Position).Magnitude
                            if d < bestDist then bestDist=d; best=entry end
                        end
                    end
                    if best then
                        lockedTarget = best
                        lockedPart   = best.part
                        lockedModel  = best.model or best.part.Parent
                        ShowNotification("AUTO BUY", "Locked: " .. best.name)
                        startCarpetLock()
                    end
                end
            end)

            _G.AutoBuyOnToggle = function(active)
                if active then
                    if _G.refreshConveyor then _G.refreshConveyor() end
                    startCarpetLock()
                else
                    stopCarpetLock()
                end
            end
        end)
        end)
        if not ok then
            warn("[Haze] AUTO BUY failed: " .. tostring(err))
            if type(ShowNotification) == "function" then pcall(ShowNotification, "AUTO BUY", "Load failed") end
        end
    end)
    -- ===== END AUTO BUY =====

    -- ===== BEGIN STEAL ESP (ported from CNK) =====
    task.spawn(function()
        local espGui = Instance.new("ScreenGui")
        espGui.Name = "StealESP"
        espGui.ResetOnSpawn = false
        espGui.Parent = PlayerGui

        local byUser = {}
        local slotIndicators = {}

        local function espFindPlotForPlayer(plr)
            if not plr then return nil end
            local plots = Workspace:FindFirstChild("Plots")
            if not plots then return nil end
            local pkg = ReplicatedStorage:FindFirstChild("Packages")
            local syncMod = pkg and pkg:FindFirstChild("Synchronizer")
            if syncMod then
                local ok, Sync = pcall(require, syncMod)
                if ok and Sync then
                    for _, plot in ipairs(plots:GetChildren()) do
                        local okCh, ch = pcall(function() return Sync:Get(plot.Name) end)
                        if okCh and ch then
                            local owner = ch:Get("Owner")
                            if owner then
                                if typeof(owner) == "Instance" and owner:IsA("Player") and owner == plr then return plot end
                                if type(owner) == "table" then
                                    if owner.UserId == plr.UserId or owner.Name == plr.Name then return plot end
                                end
                            end
                        end
                    end
                end
            end
            local dn = (plr.DisplayName or ""):lower()
            local un = (plr.Name or ""):lower()
            for _, plot in ipairs(plots:GetChildren()) do
                local sign = plot:FindFirstChild("PlotSign")
                if sign then
                    for _, obj in ipairs(sign:GetDescendants()) do
                        if obj:IsA("TextLabel") then
                            local text = (obj.Text or ""):lower()
                            if (dn ~= "" and text:find(dn, 1, true)) or (un ~= "" and text:find(un, 1, true)) then
                                return plot
                            end
                        end
                    end
                end
            end
            for _, plot in ipairs(plots:GetChildren()) do
                local ownerAttr = plot:GetAttribute("Owner")
                if ownerAttr and (ownerAttr == plr.Name or ownerAttr == plr.DisplayName or ownerAttr == tostring(plr.UserId)) then
                    return plot
                end
            end
            return nil
        end

        local function espGetAdorneePart(plot)
            if not plot then return nil end
            local sign = plot:FindFirstChild("PlotSign")
            if not sign then return nil end
            if sign:IsA("BasePart") then return sign end
            local part = sign:FindFirstChildWhichIsA("BasePart")
            if part then return part end
            if sign:IsA("Model") then
                part = sign.PrimaryPart or sign:FindFirstChildWhichIsA("BasePart", true)
                if part then return part end
            end
            part = sign:FindFirstChildWhichIsA("BasePart", true)
            if part then return part end
            local base = plot:FindFirstChild("Base")
            if base then
                local spawn = base:FindFirstChild("Spawn")
                if spawn and spawn:IsA("BasePart") then return spawn end
                part = base:FindFirstChildWhichIsA("BasePart")
                if part then return part end
            end
            if plot:IsA("Model") and plot.PrimaryPart then return plot.PrimaryPart end
            return plot:FindFirstChildWhichIsA("BasePart", true)
        end

        local espAnimalsData = nil
        local function espGetAnimalsData()
            if not espAnimalsData then
                pcall(function()
                    espAnimalsData = require(ReplicatedStorage:WaitForChild("Datas"):WaitForChild("Animals"))
                end)
            end
            return espAnimalsData
        end
        local function espResolvePetName(idx)
            local AD = espGetAnimalsData()
            if AD and AD[idx] and AD[idx].DisplayName then return AD[idx].DisplayName end
            return tostring(idx)
        end

        local function espGetAnimatorFrom(obj)
            if not obj then return nil end
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum then return hum:FindFirstChildWhichIsA("Animator", true) end
            local ac = obj:FindFirstChildOfClass("AnimationController")
            if ac then return ac:FindFirstChildWhichIsA("Animator", true) end
            return obj:FindFirstChildWhichIsA("Animator", true)
        end

        local function espFindModelInPlot(plot, petNameLower)
            if not plot then return nil end
            local best, bestScore = nil, -math.huge
            for _, d in ipairs(plot:GetDescendants()) do
                if d:IsA("Model") and d ~= plot and d.Name ~= "Base" then
                    local nl = d.Name:lower()
                    if not nl:find("podium") and not nl:find("plotsign") then
                        local pp = d.PrimaryPart or d:FindFirstChildWhichIsA("BasePart")
                        if pp then
                            local score = 0
                            if nl == petNameLower then score = 300
                            elseif nl:find(petNameLower, 1, true) or petNameLower:find(nl, 1, true) then score = 200 end
                            if score > bestScore then bestScore = score; best = d end
                        end
                    end
                end
            end
            return best
        end

        local function espAttach3DPreview(holder, petName, plotName, slot)
            local vp = Instance.new("ViewportFrame", holder)
            vp.Size = UDim2.new(1, 0, 1, 0)
            vp.BackgroundTransparency = 1
            vp.Ambient = Color3.fromRGB(245, 245, 245)
            vp.LightColor = Color3.new(1, 1, 1)
            vp.LightDirection = Vector3.new(-0.45, -0.9, -0.35)
            local cam = Instance.new("Camera")
            cam.Parent = vp
            vp.CurrentCamera = cam
            cam.FieldOfView = 34
            local petNameLower = petName:lower():gsub("%s+", "")
            local previewObj, srcModel = nil, nil
            local modelsFolder = ReplicatedStorage:FindFirstChild("Models")
            local animalsFolder = modelsFolder and modelsFolder:FindFirstChild("Animals")
            if animalsFolder then
                local tmpl = animalsFolder:FindFirstChild(petName) or animalsFolder:FindFirstChild(petNameLower)
                if not tmpl then
                    for _, ch in ipairs(animalsFolder:GetChildren()) do
                        if ch:IsA("Model") then
                            local nl = ch.Name:lower()
                            if nl == petNameLower or nl:find(petNameLower, 1, true) or petNameLower:find(nl, 1, true) then tmpl = ch; break end
                        end
                    end
                end
                if tmpl and tmpl.Archivable then
                    local ok, cloned = pcall(function() return tmpl:Clone() end)
                    if ok then previewObj = cloned end
                end
            end
            if not previewObj then
                local plots = Workspace:FindFirstChild("Plots")
                if plots and plotName then
                    srcModel = espFindModelInPlot(plots:FindFirstChild(plotName), petNameLower)
                end
                if not srcModel and plots then
                    for _, plot in ipairs(plots:GetChildren()) do
                        srcModel = espFindModelInPlot(plot, petNameLower)
                        if srcModel then break end
                    end
                end
                if srcModel and srcModel.Archivable then
                    local ok, cloned = pcall(function() return srcModel:Clone() end)
                    if ok then previewObj = cloned end
                end
            end
            if not previewObj then
                local lbl = Instance.new("TextLabel", holder)
                lbl.Size = UDim2.new(1, 0, 1, 0)
                lbl.BackgroundTransparency = 1
                lbl.Text = petName
                lbl.Font = Enum.Font.GothamBold
                lbl.TextSize = 10
                lbl.TextColor3 = Theme.TextSecondary
                lbl.TextScaled = true
                return
            end
            local worldModel = Instance.new("WorldModel", vp)
            previewObj.Parent = worldModel
            for _, d in ipairs(previewObj:GetDescendants()) do
                if d:IsA("BasePart") then d.Massless = true; d.CanCollide = false; d.Anchored = false end
            end
            pcall(function()
                local cf = previewObj:GetBoundingBox()
                if cf then previewObj:PivotTo(CFrame.new(-cf.Position.X, -cf.Position.Y, -cf.Position.Z) * cf.Rotation * CFrame.Angles(0, math.rad(205), 0)) end
            end)
            local function refreshCam()
                if not previewObj.Parent then return end
                local ok, cf = pcall(function() return previewObj:GetBoundingBox() end)
                local ok2, sz = pcall(function() return previewObj:GetExtentsSize() end)
                if not ok or not ok2 then return end
                local center = cf.Position
                local maxDim = math.max(sz.X, sz.Y, sz.Z)
                local halfFov = math.rad(cam.FieldOfView * 0.5)
                local dist = math.max((maxDim * 0.62) / math.tan(halfFov), maxDim * 1.15)
                cam.CFrame = CFrame.new(center + Vector3.new(dist * 0.58, maxDim * 0.08, dist * 0.58), center)
            end
            refreshCam()
            if srcModel then
                local srcAnimator = espGetAnimatorFrom(srcModel)
                if srcAnimator then
                    local dstAC = previewObj:FindFirstChildOfClass("AnimationController")
                    if not dstAC then dstAC = Instance.new("AnimationController"); dstAC.Name = "PreviewAC"; dstAC.Parent = previewObj end
                    local dstAnimator = dstAC:FindFirstChildOfClass("Animator")
                    if not dstAnimator then dstAnimator = Instance.new("Animator"); dstAnimator.Parent = dstAC end
                    local dstTracks = {}
                    local conn = game:GetService("RunService").Heartbeat:Connect(function()
                        if not holder.Parent then return end
                        local srcTracks = srcAnimator:GetPlayingAnimationTracks()
                        local activeIds = {}
                        for _, st in ipairs(srcTracks) do
                            local anim = st.Animation
                            local id = anim and anim.AnimationId
                            if id and id ~= "" then
                                activeIds[id] = true
                                if not dstTracks[id] then
                                    local ok2, loaded = pcall(function() return dstAnimator:LoadAnimation(anim) end)
                                    if ok2 and loaded then
                                        dstTracks[id] = loaded
                                        pcall(function() loaded:Play(0.1, st.WeightCurrent, math.max(st.Speed, 0.01)) end)
                                    end
                                else
                                    pcall(function() dstTracks[id]:AdjustSpeed(math.max(st.Speed, 0.01)); dstTracks[id].TimePosition = st.TimePosition end)
                                end
                            end
                        end
                        for id, dt in pairs(dstTracks) do
                            if not activeIds[id] then pcall(function() dt:Stop(0.1) end); dstTracks[id] = nil end
                        end
                        refreshCam()
                    end)
                    holder.Destroying:Connect(function() conn:Disconnect() end)
                else
                    for _, d in ipairs(previewObj:GetDescendants()) do
                        if d:IsA("Animation") and d.AnimationId ~= "" then
                            local ac = previewObj:FindFirstChildOfClass("AnimationController")
                            if not ac then ac = Instance.new("AnimationController", previewObj) end
                            local anim2 = ac:FindFirstChildOfClass("Animator")
                            if not anim2 then anim2 = Instance.new("Animator", ac) end
                            pcall(function() local t = anim2:LoadAnimation(d); t.Looped = true; t:Play() end)
                            break
                        end
                    end
                end
            end
        end

        local function espIsPodiumOccupied(podium)
            local base = podium:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn")
            local attach = spawn and spawn:FindFirstChild("PromptAttachment")
            if attach then
                for _, p in ipairs(attach:GetChildren()) do
                    if p:IsA("ProximityPrompt") then
                        local at = (p.ActionText or ""):lower()
                        if at:find("steal") or at:find("sell") then return true end
                    end
                end
            end
            return false
        end

        local function espGetNearestFreeSlot(plot)
            local podiums = plot:FindFirstChild("AnimalPodiums")
            if not podiums then return nil end
            local bestPodium, bestN = nil, math.huge
            for _, podium in ipairs(podiums:GetChildren()) do
                local n = tonumber(podium.Name)
                if n and n < bestN then
                    local ok, occ = pcall(espIsPodiumOccupied, podium)
                    if ok and not occ then bestN = n; bestPodium = podium end
                end
            end
            return bestPodium
        end

        local function clearSlotIndicator(uid)
            if slotIndicators[uid] and slotIndicators[uid].Parent then slotIndicators[uid]:Destroy() end
            slotIndicators[uid] = nil
        end

        local function showSlotIndicator(uid, podium)
            clearSlotIndicator(uid)
            local base = podium:FindFirstChild("Base") or podium
            local bb = Instance.new("BillboardGui")
            bb.Name = "SlotIndicator_" .. uid
            bb.Size = UDim2.fromOffset(70, 70)
            bb.StudsOffset = Vector3.new(0, 5, 0)
            bb.AlwaysOnTop = true
            bb.Adornee = base
            bb.Parent = base
            local ring = Instance.new("Frame", bb)
            ring.AnchorPoint = Vector2.new(0.5, 0.5)
            ring.Position = UDim2.fromScale(0.5, 0.5)
            ring.Size = UDim2.fromOffset(54, 54)
            ring.BackgroundColor3 = Color3.fromRGB(60, 180, 110)
            ring.BackgroundTransparency = 0.35
            ring.BorderSizePixel = 0
            Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
            local stroke = Instance.new("UIStroke", ring)
            stroke.Color = Color3.fromRGB(220, 100, 155)
            stroke.Thickness = 3
            local arrow = Instance.new("TextLabel", ring)
            arrow.Size = UDim2.fromScale(1, 1)
            arrow.BackgroundTransparency = 1
            arrow.Text = "↓"
            arrow.TextColor3 = Color3.new(1, 1, 1)
            arrow.Font = Enum.Font.GothamBlack
            arrow.TextSize = 24
            slotIndicators[uid] = bb
            task.spawn(function()
                while bb and bb.Parent do
                    local pulse = math.abs(math.sin(tick() * 3.5))
                    ring.BackgroundTransparency = 0.1 + 0.65 * (1 - pulse)
                    ring.Size = UDim2.fromOffset(44 + 18 * pulse, 44 + 18 * pulse)
                    stroke.Color = Color3.fromRGB(math.floor(180 + 50 * pulse), math.floor(60 + 50 * pulse), math.floor(100 + 40 * pulse))
                    task.wait(0.05)
                end
            end)
        end

        local function clearRow(uid)
            local r = byUser[uid]
            if not r then return end
            if r.bill and r.bill.Parent then r.bill:Destroy() end
            clearSlotIndicator(uid)
            byUser[uid] = nil
        end

        Players.PlayerRemoving:Connect(function(plr) clearRow(plr.UserId) end)

        while true do
            task.wait(0.15)
            local active = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer and plr:GetAttribute("Stealing") then
                    local idx = plr:GetAttribute("StealingIndex")
                    if idx ~= nil and idx ~= "" then
                        local plot = espFindPlotForPlayer(plr)
                        local part = espGetAdorneePart(plot)

                        if plot then
                            local freePodium = espGetNearestFreeSlot(plot)
                            if freePodium then
                                local key = tostring(plr.UserId).."_"..tostring(freePodium.Name)
                                local existing = slotIndicators[plr.UserId]
                                local existingKey = existing and existing:GetAttribute("SlotKey")
                                if not existing or not existing.Parent or existingKey ~= key then
                                    showSlotIndicator(plr.UserId, freePodium)
                                    slotIndicators[plr.UserId]:SetAttribute("SlotKey", key)
                                end
                            else
                                clearSlotIndicator(plr.UserId)
                            end
                        end

                        if part and part:IsDescendantOf(Workspace) then
                            active[plr.UserId] = true
                            local petName = espResolvePetName(idx)
                            local stealKey = tostring(idx) .. "|" .. part:GetFullName()
                            local row = byUser[plr.UserId]

                            if row and (row.stealKey ~= stealKey or row.adornee ~= part) then
                                clearRow(plr.UserId); row = nil
                            end

                            if not byUser[plr.UserId] then
                                local bb = Instance.new("BillboardGui")
                                bb.Name = "StealESP_" .. plr.Name
                                bb.Adornee = part
                                bb.AlwaysOnTop = true
                                bb.Size = UDim2.new(0, 210, 0, 158)
                                bb.StudsOffset = Vector3.new(0, 7, 0)
                                bb.MaxDistance = 650
                                bb.LightInfluence = 0
                                bb.Active = true
                                bb.Parent = espGui

                                local root = Instance.new("Frame")
                                root.Name = "Root"
                                root.Size = UDim2.new(1, 0, 1, 0)
                                root.BackgroundColor3 = Theme.Background
                                root.BackgroundTransparency = 0.12
                                root.BorderSizePixel = 0
                                root.Active = true
                                root.Parent = bb
                                Instance.new("UICorner", root).CornerRadius = UDim.new(0, 0)
                                local stroke = Instance.new("UIStroke", root)
                                stroke.Color = Color3.fromRGB(220, 40, 40)
                                stroke.Thickness = 1.5
                                stroke.Transparency = 0.4

                                local title = Instance.new("TextLabel")
                                title.Name = "Title"
                                title.Size = UDim2.new(1, -10, 0, 22)
                                title.Position = UDim2.new(0, 5, 0, 4)
                                title.BackgroundTransparency = 1
                                title.Font = Enum.Font.GothamBlack
                                title.TextSize = 11
                                title.TextColor3 = Theme.TextPrimary
                                title.TextXAlignment = Enum.TextXAlignment.Left
                                title.TextTruncate = Enum.TextTruncate.AtEnd
                                title.Text = plr.DisplayName .. " → " .. petName
                                title.Parent = root

                                local sub = Instance.new("TextLabel")
                                sub.Name = "Sub"
                                sub.Size = UDim2.new(1, -10, 0, 14)
                                sub.Position = UDim2.new(0, 5, 0, 26)
                                sub.BackgroundTransparency = 1
                                sub.Font = Enum.Font.GothamMedium
                                sub.TextSize = 9
                                sub.TextColor3 = Color3.fromRGB(220, 130, 130)
                                sub.TextXAlignment = Enum.TextXAlignment.Left
                                sub.Text = "Stealing"
                                sub.Parent = root

                                local previewHost = Instance.new("Frame")
                                previewHost.Name = "PreviewHost"
                                previewHost.Size = UDim2.new(1, -10, 0, 80)
                                previewHost.Position = UDim2.new(0, 5, 0, 42)
                                previewHost.BackgroundTransparency = 1
                                previewHost.BorderSizePixel = 0
                                previewHost.Parent = root

                                local plotName = plot and plot.Name or nil
                                task.defer(function()
                                    if previewHost.Parent then
                                        espAttach3DPreview(previewHost, petName, plotName, tostring(idx))
                                    end
                                end)

                                local tpBtn = Instance.new("TextButton")
                                tpBtn.Name = "TPButton"
                                tpBtn.Size = UDim2.new(0, 86, 0, 32)
                                tpBtn.Position = UDim2.new(0.5, -43, 0, 122)
                                tpBtn.BackgroundColor3 = Color3.fromRGB(22, 10, 18)
                                tpBtn.BackgroundTransparency = 0.05
                                tpBtn.BorderSizePixel = 0
                                tpBtn.Active = true
                                tpBtn.Selectable = true
                                tpBtn.AutoButtonColor = false
                                tpBtn.Font = Enum.Font.GothamBlack
                                tpBtn.Text = "TP"
                                tpBtn.TextSize = 18
                                tpBtn.TextColor3 = Theme.TextPrimary
                                tpBtn.Parent = root
                                Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(1, 0)
                                local tpStroke = Instance.new("UIStroke", tpBtn)
                                tpStroke.Color = Color3.fromRGB(65, 180, 105)
                                tpStroke.Thickness = 1
                                tpStroke.Transparency = 0.35

                                tpBtn.MouseEnter:Connect(function() tpBtn.BackgroundColor3 = Color3.fromRGB(55, 20, 42) end)
                                tpBtn.MouseLeave:Connect(function() tpBtn.BackgroundColor3 = Color3.fromRGB(22, 10, 18) end)
                                tpBtn.MouseButton1Click:Connect(function()
                                    local tpFn = _G.HazeTeleportToPlayerFirstFloor
                                    if typeof(tpFn) ~= "function" then
                                        if ShowNotification then ShowNotification("ESP", "TP unavailable") end
                                        return
                                    end
                                    local ok, err = tpFn(plr)
                                    if not ok then
                                        if ShowNotification then ShowNotification("ESP", "Failed: " .. tostring(err or plr.Name)) end
                                    else
                                        if ShowNotification then ShowNotification("ESP", "TP → " .. plr.Name) end
                                    end
                                end)

                                byUser[plr.UserId] = { bill = bb, adornee = part, stealKey = stealKey }
                            else
                                row = byUser[plr.UserId]
                                if row and row.bill and row.bill.Parent then
                                    local rootFrame = row.bill:FindFirstChild("Root")
                                    if rootFrame then
                                        local t = rootFrame:FindFirstChild("Title")
                                        if t then t.Text = plr.DisplayName .. " → " .. petName end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            local stale = {}
            for uid in pairs(byUser) do if not active[uid] then table.insert(stale, uid) end end
            for _, uid in ipairs(stale) do clearRow(uid) end
            for uid in pairs(slotIndicators) do if not active[uid] then clearSlotIndicator(uid) end end
        end
    end)
    -- ===== END STEAL ESP =====

    -- ================= FINAL =================
    task.spawn(function()
        task.wait(2 + (nonce % 2))

        if not alive then return end

        if not ctx[1] or not ctx[2] then
            alive = false
            kickNow()
            return
        end
    end)