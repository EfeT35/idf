if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(0.5)

-- ═══ Synchronizer detection-bypass patch ═══
-- DISABLED: this top-level patch and the Synchronizer bypass embedded in the
-- Flash TP block below both mutate Synchronizer.Get's upvalues. Running both
-- can collide and corrupt the internal data table that getInternalTable()/
-- _G.stealthGet() rely on. The standalone Flash TP never had this top-level
-- patch and works fine with only the embedded one.
-- local function PatchSynchronizer()
--     local Synchronizer = require(game.ReplicatedStorage.Packages.Synchronizer)
--     for i, v in pairs(getupvalues(Synchronizer.Get)) do
--         if type(v) == "function" then
--             local info = debug.getinfo(v)
--             if info and info.numparams == 0 then
--                 setupvalue(Synchronizer.Get, i, function() end)
--                 break
--             end
--         end
--     end
-- end
-- if setupvalue and getupvalues then
--     pcall(PatchSynchronizer)
-- end

-- ═══ AnimalPodiums layout shim ═══
-- Some game versions place podiums at plot.Base.Decorations.AnimalPodiums.
-- All readers in this script (ESP, scanner, Steal Target, Stealing Players GUI,
-- Steal Destination Line, TP podium resolution) look for plot.AnimalPodiums
-- directly. Walk every plot once on load and again whenever a new plot appears,
-- and surface the AnimalPodiums folder up to plot.AnimalPodiums.
task.spawn(function()
    pcall(function()
        local Workspace = game:GetService("Workspace")
        local function normalize(plot)
            if not plot or plot:FindFirstChild("AnimalPodiums") then return end
            local base = plot:FindFirstChild("Base")
            local decorations = base and base:FindFirstChild("Decorations")
            local nested = decorations and decorations:FindFirstChild("AnimalPodiums")
            if nested then pcall(function() nested.Parent = plot end) end
            -- Some versions deeper-nest under Base directly
            local altNested = base and base:FindFirstChild("AnimalPodiums")
            if altNested and not plot:FindFirstChild("AnimalPodiums") then
                pcall(function() altNested.Parent = plot end)
            end
        end
        local plots = Workspace:WaitForChild("Plots", 10)
        if not plots then return end
        for _, plot in ipairs(plots:GetChildren()) do normalize(plot) end
        plots.ChildAdded:Connect(function(p) task.wait(0.5); normalize(p) end)
    end)
end)


-- Suppress CoreScriptsProfiler error
pcall(function()
    local cp = game:GetService("CorePackages")
    if cp then
        local profiler = cp:FindFirstChild("Workspace") and cp.Workspace:FindFirstChild("Packages") and cp.Workspace.Packages:FindFirstChild("_Workspace")
        if profiler then
            local csp = profiler:FindFirstChild("CoreScriptsProfiler")
            if csp then
                local parser = csp:FindFirstChild("CoreScriptsProfiler") and csp.CoreScriptsProfiler:FindFirstChild("ProfilerDataParser")
                if parser and parser:IsA("ModuleScript") then
                    pcall(function() parser.Disabled = true end)
                end
            end
        end
    end
end)

-- Startup sound
pcall(function()
    local sound_service = game:GetService("SoundService")
    local sound = Instance.new("Sound")
    sound.SoundId = getcustomasset("trimmed_robot_rock.mp3")
    sound.Volume = 5
    sound.Looped = false
    sound_service:PlayLocalSound(sound)
end)

-- ═══ GUI Drag + Position Save Utility ═══
-- Shared helper used by every panel below.
-- makeDraggable(frame, key, titleHandle)
--   frame       : the Frame to drag
--   key         : unique string used as the save-file key (e.g. "StealTarget")
--   titleHandle : optional sub-element to restrict drag start to (defaults to frame itself)
--
-- Positions are saved to "gui_positions.json" via writefile/readfile.
-- Each frame reads its saved position on creation and restores it.

local _guiPosFile = "gui_positions.json"
local _guiPosData = {}
-- Tracks which panels the user has manually dragged (suppresses auto-repositioning)
local _guiUserMoved = {}

local function _gpLoad()
    if not readfile then return end
    pcall(function()
        local raw = readfile(_guiPosFile)
        if not raw or #raw < 3 then return end
        for k, x, y in raw:gmatch('"([^"]+)"%s*:%s*{[^}]*"x"%s*:%s*(%-?[%d%.]+)[^}]*"y"%s*:%s*(%-?[%d%.]+)') do
            _guiPosData[k] = { x = tonumber(x), y = tonumber(y) }
        end
    end)
end

local function _gpSave()
    if not writefile then return end
    pcall(function()
        local parts = {"{"}
        local first = true
        for k, v in pairs(_guiPosData) do
            if not first then table.insert(parts, ",") end
            first = false
            table.insert(parts, '"' .. k .. '":{"x":' .. tostring(v.x) .. ',"y":' .. tostring(v.y) .. '}')
        end
        table.insert(parts, "}")
        writefile(_guiPosFile, table.concat(parts))
    end)
end

_gpLoad()

local function makeDraggable(frame, key, titleHandle)
    -- Restore saved position if available
    local saved = _guiPosData[key]
    if saved then
        frame.Position = UDim2.new(0, saved.x, 0, saved.y)
        -- Ensure AnchorPoint is zeroed so offsets are absolute
        frame.AnchorPoint = Vector2.new(0, 0)
    end

    local handle = titleHandle or frame
    local dragging = false
    local dragStart, frameStart

    local UIS = game:GetService("UserInputService")

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging = true
        dragStart = input.Position
        -- Capture current absolute position as the drag origin
        local abs = frame.AbsolutePosition
        frameStart = Vector2.new(abs.X, abs.Y)
    end)

    local inputChangedConn = UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - dragStart
        local newX = frameStart.X + delta.X
        local newY = frameStart.Y + delta.Y
        -- Clamp inside viewport
        local vp = game:GetService("Workspace").CurrentCamera.ViewportSize
        local sz = frame.AbsoluteSize
        newX = math.clamp(newX, 0, vp.X - sz.X)
        newY = math.clamp(newY, 0, vp.Y - sz.Y)
        frame.Position = UDim2.new(0, newX, 0, newY)
        frame.AnchorPoint = Vector2.new(0, 0)
    end)

    local inputEndedConn = UIS.InputEnded:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
        if dragging then
            dragging = false
            local abs = frame.AbsolutePosition
            _guiPosData[key] = { x = math.floor(abs.X), y = math.floor(abs.Y) }
            _guiUserMoved[key] = true  -- suppress auto-repositioning after a manual drag
            _gpSave()
        end
    end)

    -- Clean up connections if frame is destroyed
    frame.AncestryChanged:Connect(function()
        if not frame.Parent then
            pcall(function() inputChangedConn:Disconnect() end)
            pcall(function() inputEndedConn:Disconnect() end)
        end
    end)
end

local function makeResizable(frame, minW, minH)
    local UIS = game:GetService("UserInputService")
    local handle = Instance.new("TextButton")
    handle.Size     = UDim2.new(0, 14, 0, 14)
    handle.Position = UDim2.new(1, -14, 1, -14)
    handle.BackgroundColor3     = Color3.fromRGB(255, 40, 160)
    handle.BackgroundTransparency = 0.3
    handle.BorderSizePixel = 0
    handle.Text = "◢"
    handle.TextColor3 = Color3.fromRGB(255, 255, 255)
    handle.TextSize = 9
    handle.Font = Enum.Font.GothamBold
    handle.AutoButtonColor = false
    handle.ZIndex = 25
    handle.Parent = frame
    Instance.new("UICorner", handle).CornerRadius = UDim.new(0, 3)

    local resizing = false
    local resizeStart, startSize

    handle.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        resizing = true
        resizeStart = Vector2.new(input.Position.X, input.Position.Y)
        startSize   = frame.AbsoluteSize
    end)

    local rChangedConn = UIS.InputChanged:Connect(function(input)
        if not resizing then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - resizeStart
        local newW  = math.max(minW or 120, startSize.X + delta.X)
        local newH  = math.max(minH or 50,  startSize.Y + delta.Y)
        frame.Size  = UDim2.new(0, newW, 0, newH)
    end)

    local rEndedConn = UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            resizing = false
        end
    end)

    frame.AncestryChanged:Connect(function()
        if not frame.Parent then
            pcall(function() rChangedConn:Disconnect() end)
            pcall(function() rEndedConn:Disconnect() end)
        end
    end)
end

-- ═══════════════════════════════════════
-- ═══ Glowing Purple Border Utility ═══
_G._glowGradients = {}

local function addGlowBorder(frame)
    if not frame or not frame:IsA("GuiObject") then return end
    -- Only remove our own glow stroke, not other strokes that may be needed
    for _, child in ipairs(frame:GetChildren()) do
        if child:IsA("UIStroke") and child.Name == "_GlowStroke" then
            child:Destroy()
        end
    end
    local stroke = Instance.new("UIStroke")
    stroke.Name = "_GlowStroke"
    stroke.Thickness = 2.5
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(180, 130, 0)),
        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 40, 160)),
        ColorSequenceKeypoint.new(0.66, Color3.fromRGB(180, 130, 0)),
        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255, 40, 160)),
    })
    stroke.Transparency = 0.3
    stroke.Parent = frame

    local grad = Instance.new("UIGradient")
    grad.Name = "_GlowGradient"
    grad.Rotation = 0
    grad.Offset = Vector2.new(0, 0)
    grad.Parent = stroke
    table.insert(_G._glowGradients, grad)
end

task.spawn(function()
    local RunService = game:GetService("RunService")
    local speed = 0.3
    local offset = 0
    RunService.Heartbeat:Connect(function()
        offset = (offset + speed * 0.01) % 1
        for _, grad in ipairs(_G._glowGradients) do
            pcall(function()
                if grad and grad.Parent then
                    grad.Offset = Vector2.new(-offset, 0)
                end
            end)
        end
        for i = #_G._glowGradients, 1, -1 do
            if not _G._glowGradients[i] or not _G._glowGradients[i].Parent then
                table.remove(_G._glowGradients, i)
            end
        end
    end)
end)
-- ═══ Error Clearer ═══
task.spawn(function()
    local _errGS = cloneref(game:GetService("GuiService"))
    local _errRS = cloneref(game:GetService("RunService"))
    local _errF = 0
    _errRS.Heartbeat:Connect(function()
        _errF = _errF + 1; if _errF < 3 then return end; _errF = 0
        pcall(function() _errGS:ClearError() end)
    end)
end)

-- ═══ GuiService Error Suppressor ═══
task.spawn(function()
    local _GuiService = (typeof(cloneref) == "function" and cloneref(game:GetService("GuiService"))) or game:GetService("GuiService")
    pcall(function()
        local mt = getrawmetatable(_GuiService)
        local oldIndex = mt.__index
        setreadonly(mt, false)
        mt.__index = newcclosure(function(self, key)
            if key == "SetErrorMessage" or key == "GetErrorMessage" then
                return newcclosure(function() return "" end)
            end
            return oldIndex(self, key)
        end)
        setreadonly(mt, true)
    end)
    -- Only target top-level error containers (not their children which could share names with game UI)
    local ERROR_ROOTS = {ErrorPrompt=true, RobloxPromptGui=true, PromptOverlay=true}
    local function instantHide(desc)
        pcall(function()
            if desc:IsA("GuiObject") then
                desc.Visible = false
            elseif desc:IsA("ScreenGui") then
                desc.Enabled = false
            end
            task.delay(2, function() pcall(function() desc:Destroy() end) end)
        end)
    end
    pcall(function()
        local cg = game:GetService("CoreGui")
        cg.DescendantAdded:Connect(function(desc)
            if ERROR_ROOTS[desc.Name] then instantHide(desc) end
        end)
    end)
    pcall(function()
        local pg = LocalPlayer:WaitForChild("PlayerGui", 5)
        if pg then
            pg.DescendantAdded:Connect(function(desc)
                if ERROR_ROOTS[desc.Name] then instantHide(desc) end
            end)
        end
    end)
    while true do
        pcall(function() _GuiService:ClearError() end)
        task.wait(0.1)
    end
end)

-- ═══ Camera Lock (prevents admin items from moving camera) ═══
task.spawn(function()
    pcall(function()
        local cam = Workspace.CurrentCamera
        local function lockCam()
            local ch = LocalPlayer.Character
            local hum = ch and ch:FindFirstChildOfClass("Humanoid")
            if hum then cam.CameraSubject = hum; cam.CameraType = Enum.CameraType.Custom end
        end
        local _camF = 0
        RunService.Heartbeat:Connect(function()
            _camF = _camF + 1; if _camF < 5 then return end; _camF = 0
            if cam.CameraType ~= Enum.CameraType.Custom then lockCam() end
        end)
        cam:GetPropertyChangedSignal("CameraSubject"):Connect(function()
            task.defer(function()
                local ch = LocalPlayer.Character
                local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                if hum and cam.CameraSubject ~= hum then lockCam() end
            end)
        end)
    end)
end)

-- ═══ FOV Lock (follows the FOV slider, _G.SavedFOV) ═══
task.spawn(function()
    pcall(function()
        local cam = Workspace.CurrentCamera
        cam.FieldOfView = _G.SavedFOV or 100
        cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
            local target = _G.SavedFOV or 100
            if cam.FieldOfView ~= target then cam.FieldOfView = target end
        end)
    end)
    -- Also enforce on character spawn
    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.3)
        pcall(function() Workspace.CurrentCamera.FieldOfView = _G.SavedFOV or 100 end)
    end)
end)





-- ═══ Flash TP (velocity-based) ═══
task.spawn(function()
    pcall(function()
-- flash_tp.lua
-- Flash TP (velocity-based auto-teleport-to-best-brainrot).
-- Extracted from Vanish hub. Self-contained: scan -> tp to sky platform -> clone -> go to brainrot.
-- Bind: press T to run. Also exposed as _G.FlashStartTP.

if not game:IsLoaded() then game.Loaded:Wait() end

-- Workspace label so the script shows as "Flash TP" in Explorer
do
    local _lbl = Instance.new("StringValue")
    _lbl.Name  = "Ryxflash TP"
    _lbl.Value = "Ryxflash TP"
    _lbl.Parent = workspace
end


-- LPH macro fallbacks (no-ops when not running under Luraph obfuscation)
if LPH_OBFUSCATED == nil then
    local env = getfenv()
    env["LPH_NO_" .. "VIRTUALIZE"] = function(...) return ... end
    env["LPH_JIT_" .. "MAX"]       = function(...) return ... end
end

-- =====================================================================
-- Services
-- =====================================================================
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UIS                 = game:GetService("UserInputService")
local RS                  = game:GetService("ReplicatedStorage")
local TweenService        = game:GetService("TweenService")
local VirtualInputManager = (cloneref and cloneref(game:GetService("VirtualInputManager"))) or game:GetService("VirtualInputManager")
local GuiService          = (cloneref and cloneref(game:GetService("GuiService")))          or game:GetService("GuiService")

local LP = Players.LocalPlayer

-- ═══ Anti-Ragdoll (from vanish_hub) ═══
do
    local LocalPlayer = LP
    local Workspace   = game:GetService("Workspace")

    local function isRagdolled()
        local char = LocalPlayer.Character; if not char then return false end
        local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return false end
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.Ragdoll
           or state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.GettingUp then
            return true
        end
        local endTime = LocalPlayer:GetAttribute("RagdollEndTime")
        if endTime and (endTime - Workspace:GetServerTimeNow()) > 0 then return true end
        return false
    end

    local antiRagdollConnections = {}
    local antiRagdollCharacter, antiRagdollHumanoid, antiRagdollRootPart, antiRagdollAnimator
    local lastVelocity = Vector3.new(0, 0, 0)
    local velocityChangeThreshold = 40
    local velocityMagnitudeThreshold = 25
    local maxVelocity = 15

    local function isRagdolledLocal()
        if not antiRagdollHumanoid then return false end
        local state = antiRagdollHumanoid:GetState()
        if state ~= Enum.HumanoidStateType.Physics
           and state ~= Enum.HumanoidStateType.Ragdoll
           and state ~= Enum.HumanoidStateType.FallingDown
           and state ~= Enum.HumanoidStateType.GettingUp then
            return false
        end
        return true
    end

    local function enableAntiRagdollControls()
        pcall(function()
            local PlayerModule = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
            require(PlayerModule):GetControls():Enable()
        end)
    end

    local function cleanupRagdoll()
        if not antiRagdollCharacter then return end
        local function processChildren(parent)
            for _, obj in ipairs(parent:GetChildren()) do
                if obj:IsA("BallSocketConstraint") or obj:IsA("NoCollisionConstraint")
                   or obj:IsA("HingeConstraint")
                   or (obj:IsA("Attachment") and (obj.Name == "A" or obj.Name == "B")) then
                    obj:Destroy()
                elseif obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                    obj:Destroy()
                elseif obj:IsA("Motor6D") then
                    obj.Enabled = true
                elseif obj:IsA("BasePart") then
                    for _, child in ipairs(obj:GetChildren()) do
                        if child:IsA("BallSocketConstraint") or child:IsA("NoCollisionConstraint")
                           or child:IsA("HingeConstraint") or child:IsA("Motor6D") then
                            if child:IsA("Motor6D") then child.Enabled = true else child:Destroy() end
                        elseif child:IsA("Attachment") and (child.Name == "A" or child.Name == "B") then
                            child:Destroy()
                        end
                    end
                end
            end
        end
        pcall(function() processChildren(antiRagdollCharacter) end)
        if antiRagdollAnimator then
            for _, track in pairs(antiRagdollAnimator:GetPlayingAnimationTracks()) do
                local animName = track.Animation and track.Animation.Name:lower() or ""
                if animName:find("rag") or animName:find("fall") or animName:find("hurt") or animName:find("down") then
                    track:Stop(0)
                end
            end
        end
    end

    local function setupAntiRagdollCharacter(char)
        antiRagdollCharacter = char
        antiRagdollHumanoid  = char:WaitForChild("Humanoid", 10)
        antiRagdollRootPart  = char:WaitForChild("HumanoidRootPart", 10)
        antiRagdollAnimator  = antiRagdollHumanoid:WaitForChild("Animator", 10)
        lastVelocity = Vector3.new(0, 0, 0)
    end

    local function clearAntiRagdollConnections()
        for _, connection in pairs(antiRagdollConnections) do
            pcall(function() connection:Disconnect() end)
        end
        antiRagdollConnections = {}
    end

    local function setupAntiRagdollConnections()
        clearAntiRagdollConnections()
        table.insert(antiRagdollConnections, antiRagdollHumanoid.StateChanged:Connect(function()
            if isRagdolledLocal() then
                antiRagdollHumanoid:ChangeState(Enum.HumanoidStateType.Running)
                cleanupRagdoll()
                workspace.CurrentCamera.CameraSubject = antiRagdollHumanoid
                enableAntiRagdollControls()
            end
        end))
        table.insert(antiRagdollConnections, antiRagdollCharacter.DescendantAdded:Connect(function()
            if isRagdolledLocal() then cleanupRagdoll() end
        end))
        table.insert(antiRagdollConnections, RunService.Heartbeat:Connect(function()
            if isRagdolledLocal() then
                cleanupRagdoll()
                local v = antiRagdollRootPart.AssemblyLinearVelocity
                if (v - lastVelocity).Magnitude > velocityChangeThreshold
                   and v.Magnitude > velocityMagnitudeThreshold then
                    antiRagdollRootPart.AssemblyLinearVelocity = v.Unit * math.min(v.Magnitude, maxVelocity)
                end
                lastVelocity = v
            end
        end))
        enableAntiRagdollControls()
        cleanupRagdoll()
    end

    local function activateForCharacter(char)
        setupAntiRagdollCharacter(char)
        setupAntiRagdollConnections()
    end

    if LocalPlayer.Character then
        activateForCharacter(LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(function(char)
        activateForCharacter(char)
    end)
end

-- =====================================================================
-- Fusing / machine-block helper (used by scanAllPets)
-- =====================================================================
local _BLOCKING_MACHINE_TYPES = {
    Fuse     = true,
    Duel     = true,
    Trade    = true,
    Crafting = true,
}
local function _VanishIsFusing(animalData)
    if type(animalData) ~= "table" then return false end
    local m = animalData.Machine
    if type(m) ~= "table" then return false end
    return _BLOCKING_MACHINE_TYPES[m.Type] == true
end

-- =====================================================================
-- Synchronizer detection bypass + stealth channel reader
-- =====================================================================
do
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local getupvalue = getupvalue or debug.getupvalue

    local function getInternalTable()
        local Packages = ReplicatedStorage:FindFirstChild("Packages")
        if not Packages then return nil end
        local SynMod = Packages:FindFirstChild("Synchronizer")
        if not SynMod then return nil end
        local ok, syn = pcall(require, SynMod)
        if not ok or not syn then return nil end
        local Get = syn.Get
        if type(Get) ~= "function" then return nil end
        for i = 1, 5 do
            local s, u = pcall(getupvalue, Get, i)
            if s and type(u) == "table" then
                if u.___private or u.___channels or u.___data then return u end
                for k, v in pairs(u) do
                    if (type(k) == "string" and k:match("^Plot_")) or type(v) == "table" then
                        return u
                    end
                end
            end
        end
        local s, e = pcall(getfenv, Get)
        if s and e and e.self then return e.self end
        return nil
    end

    local SyncInt = {_cache = {}, _data = nil}
    _G.SyncInt = SyncInt

    task.spawn(function()
        for i = 1, 10 do
            SyncInt._data = getInternalTable()
            if SyncInt._data then break end
            task.wait(1)
        end
    end)

    function _G.stealthGet(n)
        if not n or type(n) ~= "string" then return nil end
        if SyncInt._cache[n] == false then return nil end
        if SyncInt._data then
            for _, k in ipairs({n, "Plot_" .. n, "Plot" .. n, n .. "_Channel", "Channel_" .. n}) do
                if SyncInt._data[k] then
                    SyncInt._cache[n] = SyncInt._data[k]
                    return SyncInt._data[k]
                end
            end
            for k, v in pairs(SyncInt._data) do
                if type(k) == "string" and (k == n or k:find(n, 1, true)) and type(v) == "table" then
                    SyncInt._cache[n] = v
                    return v
                end
            end
        end
        SyncInt._cache[n] = false
        return nil
    end

    function _G.sProp(ch, p)
        if not ch or type(ch) ~= "table" then return nil end
        if ch[p] then return ch[p] end
        if type(ch.Get) == "function" then
            local ok, r = pcall(ch.Get, ch, p)
            if ok then return r end
        end
        local alts = {
            Owner = {"owner", "Owner", "plotOwner", "PlotOwner"},
            AnimalList = {"animalList", "AnimalList", "animals", "Animals", "pets"},
        }
        if alts[p] then
            for _, a in ipairs(alts[p]) do
                if ch[a] then return ch[a] end
            end
        end
        return nil
    end

    local Packages = ReplicatedStorage:FindFirstChild("Packages")
    local SynMod = Packages and Packages:FindFirstChild("Synchronizer")
    local okReq, syn = pcall(require, SynMod)
    if okReq and typeof(syn) == "table" then
        local function HasBoolUpvalue(Fn)
            local OkU, Ups = xpcall(debug.getupvalues, function() end, Fn)
            if not OkU then return false end
            for _, V in pairs(Ups) do
                if typeof(V) == "boolean" then return true end
            end
            return false
        end
        for _, Fn in pairs(syn) do
            if typeof(Fn) == "function" and not isexecutorclosure(Fn) then
                local OkU, Ups = xpcall(debug.getupvalues, function() end, Fn)
                if OkU then
                    for Idx, V in pairs(Ups) do
                        if typeof(V) == "function" and not isexecutorclosure(V) and HasBoolUpvalue(V) then
                            pcall(debug.setupvalue, Fn, Idx, newcclosure(function() end))
                        end
                    end
                end
            end
        end
    end
end


-- =====================================================================
-- Sync data fetch helper
-- =====================================================================
_G.FlashGetSyncData = _G.FlashGetSyncData or function(plot)
    local plotName = type(plot) == "string" and plot or (plot and plot.Name)
    if not plotName then return nil end
    local Pkgs = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
    local Sync = Pkgs and Pkgs:FindFirstChild("Synchronizer")
    if not Sync then return nil end
    local okMod, mod = pcall(require, Sync)
    if not okMod or type(mod) ~= "table" then return nil end

    local okT, data = pcall(function() return mod:GetTableFromChannel(plotName) end)
    if okT and type(data) == "table" then return data end

    local okC, ch = pcall(function() return mod:Get(plotName) end)
    if okC and ch then
        local synth = { __channel = ch }
        pcall(function() synth.AnimalList = ch:Get("AnimalList") end)
        pcall(function() synth.Owner      = ch:Get("Owner") end)
        return synth
    end
    return nil
end

-- =====================================================================
-- Module loaders
-- =====================================================================
local Synchronizer, AnimalsData, AnimalsShared, NumberUtils
local _modulesPackagesRef -- the Packages folder Synchronizer was loaded from, used to detect staleness

local function loadModules()
    -- If we already loaded modules, make sure the Packages folder we loaded
    -- them from is still alive in the current game tree. After a rejoin
    -- (RejoinBtn -> TeleportToPlaceInstance) or a server hop, the old
    -- ReplicatedStorage instances can be torn down while our cached
    -- Synchronizer/AnimalsData/AnimalsShared upvalues still point at the
    -- dead module results -> Synchronizer:Get() silently fails/pcalls out,
    -- scanAllPets() finds 0 channels, and TP reports no_brainrot_found even
    -- though the standalone (fresh inject every run) never hits this.
    if Synchronizer and _modulesPackagesRef and _modulesPackagesRef:IsDescendantOf(game) then
        return true
    end
    Synchronizer, AnimalsData, AnimalsShared, NumberUtils = nil, nil, nil, nil
    local ok = pcall(function()
        local Packages = RS:WaitForChild("Packages", 5)
        local Datas = RS:WaitForChild("Datas", 5)
        local Shared = RS:WaitForChild("Shared", 5)
        local Utils = RS:WaitForChild("Utils", 5)
        Synchronizer = require(Packages:WaitForChild("Synchronizer"))
        AnimalsData = require(Datas:WaitForChild("Animals"))
        AnimalsShared = require(Shared:WaitForChild("Animals"))
        NumberUtils = require(Utils:WaitForChild("NumberUtils"))
        _modulesPackagesRef = Packages
    end)
    return ok and Synchronizer ~= nil
end

local NetModule
local function loadNet()
    if NetModule then return true end
    local ok, mod = pcall(function()
        return require(RS:WaitForChild("Packages", 5):WaitForChild("Net", 5):FindFirstChildWhichIsA("ModuleScript", true))
    end)
    if not ok or type(mod) ~= "table" then return false end
    NetModule = mod
    return true
end

-- ===== fast carpet mover =====
local INBASE_SPEED = 190
local SKY_CLONE_WAIT = 0.28
local BRAINROT_SNAP_SPEED = 300   -- studs/s for the final go-to-brainrot tween
-- Expose the list globally so the UI can use it too
_G.CARPET_TOOLS = { "Flying Carpet", "Cupid's Wings", "Santa's Sleigh", "Witch's Broom", "Magic Carpet" }
local CARPET_NAMES = _G.CARPET_TOOLS  -- keep backward compatibility
local function findTool(name)
    local char = LP.Character
    local bp = LP:FindFirstChild("Backpack")
    return (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
end
local function listTools()
    local out, char, bp = {}, LP.Character, LP:FindFirstChild("Backpack")
    if char then for _, t in ipairs(char:GetChildren()) do if t:IsA("Tool") then out[#out + 1] = t.Name end end end
    if bp then for _, t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then out[#out + 1] = t.Name end end end
    return table.concat(out, ", ")
end
local function equipCarpet()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end

    -- 1) Try the user‑selected tool (if any)
    local selected = _G.FlashExtra and _G.FlashExtra.tpTool
    if selected and selected ~= "" then
        local t = findTool(selected)
        if t and t:IsA("Tool") then
            if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
            return selected
        end
    end

    -- 2) Fallback: try the default list
    for _, n in ipairs(CARPET_NAMES) do
        local t = findTool(n)
        if t and t:IsA("Tool") then
            if t.Parent ~= char then pcall(function() hum:EquipTool(t) end) end
            return n
        end
    end
    return nil
end
local function carpetEngage()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum then return nil end
    local cn
    local _tc = os.clock()
    repeat
        cn = equipCarpet()
        local c = LP.Character
        if cn and c and c:FindFirstChild(cn) then break end
        RunService.Heartbeat:Wait()
    until os.clock() - _tc > 1
    _G.TPEngage = "carpet=" .. tostring(cn)
    return cn
end

-- =====================================================================
-- GRAPPLE TP — billboard-aim + VirtualInputManager click fire
-- findGrappleTool   : searches char + backpack by name then keyword
-- findOwnBaseSignPart : locates the PlotSign BasePart for our own base
-- simulateClickAt   : moves mouse to worldPos screen projection + clicks
-- fireGrappleV2     : full equip → aim → click → unequip sequence
-- _G.FlashGrappleEnabled controls whether grapple fires before each TP
-- =====================================================================
local GRAPPLE_NAMES = {
    "Grapple Hook", "Grappling Hook", "Grapple", "Hook",
    "Web Slinger", "Grapple Gun", "GrappleHook",
}
local GRAPPLE_KEYWORDS = { "grapple", "hook", "slinger", "web", "lasso", "harpoon" }

-- Delays (seconds) – can be overridden via _G.FlashGrappleDelays table
local _GrappleDelays = {
    equipDelay    = 0.02,  -- PATCH: reduit (etait 0.10)
    fireDelay     = 0.02,  -- PATCH: reduit (etait 0.10)
    postFireDelay = 0.02,  -- PATCH: reduit (etait 0.10)
}
_G.FlashGrappleDelays = _GrappleDelays

-- Whether grapple fires before every TP move. Default off; toggle via _G.FlashGrappleEnabled = true
_G.FlashGrappleEnabled = _G.FlashGrappleEnabled or true

-- Tracks whether the FIRST fire of this TP run should aim at own base sign.
-- Reset to true at the start of every new auto-TP sequence.
local _grappleFirstShotPending = true

local function findGrappleTool()
    local char = LP.Character
    local bp   = LP:FindFirstChild("Backpack")
    -- Pass 1: exact name match
    for _, n in ipairs(GRAPPLE_NAMES) do
        local t = (char and char:FindFirstChild(n)) or (bp and bp:FindFirstChild(n))
        if t and t:IsA("Tool") then return t end
    end
    -- Pass 2: keyword scan
    local function scanContainer(c)
        if not c then return nil end
        for _, obj in ipairs(c:GetChildren()) do
            if obj:IsA("Tool") then
                local lower = obj.Name:lower()
                for _, kw in ipairs(GRAPPLE_KEYWORDS) do
                    if lower:find(kw, 1, true) then return obj end
                end
            end
        end
        return nil
    end
    return scanContainer(char) or scanContainer(bp)
end

-- Cache the own-base PlotSign BasePart to avoid re-scanning every fire
local _ownBaseSignCache = nil
local function findOwnBaseSignPart()
    if _ownBaseSignCache and _ownBaseSignCache.Parent then
        return _ownBaseSignCache
    end
    _ownBaseSignCache = nil
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local nameLower    = LP.Name:lower()
    local displayLower = LP.DisplayName:lower()
    for _, plot in ipairs(plots:GetChildren()) do
        local sign = plot:FindFirstChild("PlotSign")
        if sign then
            -- Method 1: YourBase BillboardGui enabled flag
            local yb = sign:FindFirstChild("YourBase")
            if yb and yb:IsA("BillboardGui") and yb.Enabled then
                local part = sign:IsA("BasePart") and sign
                    or sign.PrimaryPart
                    or sign:FindFirstChildWhichIsA("BasePart", true)
                if part then _ownBaseSignCache = part; return part end
            end
            -- Method 2: text label contains our name
            for _, d in ipairs(sign:GetDescendants()) do
                if d:IsA("TextLabel") then
                    local t = d.Text:lower()
                    if t:find(nameLower, 1, true) or t:find(displayLower, 1, true) then
                        local part = sign:IsA("BasePart") and sign
                            or sign.PrimaryPart
                            or sign:FindFirstChildWhichIsA("BasePart", true)
                        if part then _ownBaseSignCache = part; return part end
                    end
                end
            end
        end
    end
    return nil
end

-- Simulate a mouse move + left-click at the given world position.
-- Returns false if the point is off-screen.
local function simulateClickAt(worldPos)
    local cam = workspace.CurrentCamera
    local screenPos, onScreen = cam:WorldToScreenPoint(worldPos)
    if not onScreen then return false end
    local inset = GuiService:GetGuiInset()
    local sx = screenPos.X - inset.X
    local sy = screenPos.Y - inset.Y
    pcall(function() VirtualInputManager:SendMouseMoveEvent(sx, sy, game) end)
    task.wait()
    pcall(function() VirtualInputManager:SendMouseButtonEvent(sx, sy, 0, true,  game, 1) end)
    task.wait()
    pcall(function() VirtualInputManager:SendMouseButtonEvent(sx, sy, 0, false, game, 1) end)
    return true
end

-- Full grapple fire sequence.
-- Automatically aims at the own base PlotSign if within 30 studs of it,
-- otherwise fires 10 studs ahead with the camera angled DOWN so the hook grabs
-- the ground/floor in front (works anywhere, not just on walls/anchored parts).
local function fireGrappleV2(fireAtOwnBase)
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local hum = char:FindFirstChildOfClass("Humanoid")

    -- STEP 1: find and equip grapple tool
    local grappleTool = findGrappleTool()
    if not grappleTool then return end
    if grappleTool.Parent ~= char then
        if hum then pcall(function() hum:EquipTool(grappleTool) end) end
        local equipDelay = _GrappleDelays.equipDelay
        local equipStart = os.clock()
        repeat
            task.wait(0.02)
            grappleTool = findGrappleTool()
        until (grappleTool and grappleTool.Parent == char)
            or (os.clock() - equipStart >= math.max(equipDelay, 0.30))
        grappleTool = findGrappleTool()
    end
    if not grappleTool or grappleTool.Parent ~= char then return end

    -- Anchor HRP so we don't drift while aiming
    local wasAnchored = hrp.Anchored
    hrp.Anchored = true

    -- Save camera state
    local cam        = workspace.CurrentCamera
    local oldCamCF   = cam.CFrame
    local oldCamType = cam.CameraType
    local didLockCam = false

    -- STEP 2: determine aim target
    -- If we are within 15 studs of our own base sign, aim at the sign so the
    -- hook latches onto the base wall.  If we are further away (or the sign
    -- cannot be found), aim 6 studs straight ahead on the flat plane — this
    -- lets the grapple work anywhere on the map, not just at our base.
    local aimTarget = nil
    local signPart = findOwnBaseSignPart()
    if signPart then
        local distToBase = (hrp.Position - signPart.Position).Magnitude
        if distToBase <= 30 then
            -- Within 30 studs of our base sign: aim at the sign so the hook
            -- latches onto the base wall. Cap how far ABOVE us the aim point can
            -- sit so the camera tilts up gently instead of craning straight up.
            local sp = signPart.Position
            local AIM_MAX_RISE = 6   -- max studs above the HRP the aim may climb
            local aimY = math.min(sp.Y, hrp.Position.Y + AIM_MAX_RISE)
            aimTarget = Vector3.new(sp.X, aimY, sp.Z)
        end
    end
    if not aimTarget then
        -- Not within 30 studs of base (or sign not found): fire 10 studs ahead and
        -- angle the aim/camera DOWN so the hook grabs the ground/floor in front of
        -- us instead of needing a wall or anchored part — works anywhere on the
        -- map. (Safe for the start-up auto-TP grapple: at spawn you're within 30
        -- studs of your base, so that takes the look-up branch above, not this one.)
        local lookDir  = hrp.CFrame.LookVector
        local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
        if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
        local AIM_DOWN = 8   -- studs below us the aim point sits (steeper = larger)
        aimTarget = hrp.Position + flatLook.Unit * 10 - Vector3.new(0, AIM_DOWN, 0)
    end

    -- STEP 3: face target and lock camera
    local toTarget = aimTarget - hrp.Position
    if toTarget.Magnitude > 0.1 then
        hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + toTarget.Unit)
    end
    pcall(function()
        cam.CameraType = Enum.CameraType.Scriptable
        local eyeOffset = hrp.CFrame.LookVector * -5 + Vector3.new(0, 1.5, 0)
        cam.CFrame  = CFrame.new(hrp.Position + eyeOffset, aimTarget)
        didLockCam  = true
    end)
    task.wait(0.05) -- flush camera for one frame

    -- STEP 4: fire — try VIM click, fall back to centre-screen, always also :Activate()
    local fireDelay = _GrappleDelays.fireDelay
    for attempt = 1, 3 do
        local clickOk = pcall(function()
            if not simulateClickAt(aimTarget) then
                -- target off-screen: click screen centre
                local cx = cam.ViewportSize.X / 2
                local cy = cam.ViewportSize.Y / 2
                pcall(function() VirtualInputManager:SendMouseMoveEvent(cx, cy, game) end)
                task.wait()
                pcall(function() VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, true,  game, 1) end)
                task.wait()
                pcall(function() VirtualInputManager:SendMouseButtonEvent(cx, cy, 0, false, game, 1) end)
            end
        end)
        pcall(function() grappleTool:Activate() end) -- belt-and-suspenders
        if clickOk then break end
        task.wait(0.04)
    end
    task.wait(fireDelay)

    -- STEP 5: restore camera and anchor
    if didLockCam then
        pcall(function()
            cam.CameraType = oldCamType
            cam.CFrame      = oldCamCF
        end)
    end
    hrp.Anchored = wasAnchored

    -- STEP 6: booster la vitesse de traction + cacher le fil
    -- Appliquer une velocity vers la cible pendant 0.3s pour accelerer le grapin
    task.spawn(function()
        local _t0 = os.clock()
        while os.clock() - _t0 < 0.3 do
            local _c = LP.Character
            local _hrp = _c and _c:FindFirstChild("HumanoidRootPart")
            if _hrp and _hrp.Parent then
                local toTarget = aimTarget - _hrp.Position
                local dist = toTarget.Magnitude
                if dist > 2 then
                    local dir = toTarget.Unit
                    -- Vitesse proportionnelle a la distance, max 120 studs/s
                    local spd = 120
                    _hrp.AssemblyLinearVelocity = Vector3.new(dir.X * spd, dir.Y * spd, dir.Z * spd)
                end
            end
            task.wait(0.016)
        end
    end)
    task.wait(0.05)
    if hum then pcall(function() hum:UnequipTools() end) end
end
_G.FlashFireGrapple = fireGrappleV2

-- ═══ Grapple rope/beam hider ═══
-- Cache le fil du grapin des qu'il apparait (Beam, RopeConstraint, Trail)
-- en le rendant totalement transparent. Surveille le character en continu.
task.spawn(function()
    local function hideGrappleVisuals(obj)
        pcall(function()
            if obj:IsA("Beam") then
                obj.Transparency = NumberSequence.new(1)
                obj.Enabled = false
            elseif obj:IsA("RopeConstraint") then
                obj.Visible = false
            elseif obj:IsA("Trail") then
                obj.Enabled = false
            end
        end)
    end

    local function watchCharacter(char)
        if not char then return end
        -- Cacher les visuels existants
        for _, obj in ipairs(char:GetDescendants()) do
            hideGrappleVisuals(obj)
        end
        -- Cacher les nouveaux
        char.DescendantAdded:Connect(function(obj)
            task.wait() -- laisser le temps de s'initialiser
            hideGrappleVisuals(obj)
        end)
    end

    -- Character actuel
    local char = LP.Character
    if char then watchCharacter(char) end
    -- Futurs characters (respawn)
    LP.CharacterAdded:Connect(function(newChar)
        task.wait(0.1)
        watchCharacter(newChar)
    end)
end)

-- =====================================================================
-- Flash TP extra config (persisted alongside main cfg)
-- =====================================================================
local FlashExtra = {
    tpPriorityEnabled = false,
    tpHighestEnabled  = false,
    tpMinMPS          = 0,
    tpFpsGate         = 0,
    skyCloneWait      = 0.28,
    cloneDelay        = 0.15,
    wallAnchorWait    = 0.10,
    tpSpeed           = 5000,   -- velocity-TP travel speed (TP Speed slider)
    brainrotSnapSpeed = 300,    -- final go-to-brainrot tween speed (Brainrot Speed slider)
    -- legacy kept for import compat but not used by GUI
    walkDuration      = 0.05,
    walkSettle        = 0.05,
    walkDuration2     = 0,
    walkSettle2       = 0,
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
-- Pet priority data tables
-- =====================================================================
local PET_PRIORITY_TIERS = {
    [1] = { pets = {"Headless Horseman"}, threshold = 0 },
    [2] = { pets = {"Signore Carapace"}, threshold = 0 },
    [3] = { pets = {"John Pork"}, threshold = 0 },
    [4] = { pets = {"Strawberry Elephant"}, threshold = 0 },
    [5] = { pets = {"Arcadragon"}, threshold = 5e9 },
    [6] = { pets = {"Elefanto Frigo"}, threshold = 10e9 },
    [7] = { pets = {"Meowl"}, threshold = 5e9 },
    [8] = { pets = {"Skibidi Toilet"}, threshold = 5e9 },
    [9] = { pets = {"Love Love Bear"}, threshold = 0 },
    [10] = { pets = {"Antonio"}, threshold = 0 },
    [11] = { pets = {"Pancake and Syrup"}, threshold = 0 },
    [12] = { pets = {"Griffin"}, threshold = 0 },
    [13] = { pets = {"Globa Steppa","La Supreme Combinasion","Fishino Clownino","Dragon Gingerini","Tirilikalika Tirilikalako"}, threshold = 5e9 },
    [14] = { pets = {"Ginger Gerat","Pet"}, threshold = 10e9 },
    [15] = { pets = {"Hydra Bunny","Digi Narwhal","Kalika Bros"}, threshold = 3e9 },
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
    [3] = { [4] = 10e9 },
    [4] = {},
    [5] = { [6] = math.huge },
    [6] = { [9] = math.huge, [10] = math.huge, [12] = 15e9 },
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
-- Plot / channel helpers
-- =====================================================================
local function getPlotChannel(plotName)
    if not Synchronizer then return nil end
    local channel
    pcall(function() channel = Synchronizer:Get(plotName) end)
    if not channel then pcall(function() channel = Synchronizer:Wait(plotName) end) end
    return channel
end

local function channelGet(channel, key)
    if not channel then return nil end
    local v
    pcall(function() if type(channel.Get) == "function" then v = channel:Get(key) end end)
    if v == nil then pcall(function() v = channel.CacheTable and channel.CacheTable[key] end) end
    return v
end

local function isMyPlot(channel)
    if not channel then return false end
    local owner = channelGet(channel, "Owner")
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

local function ownerInGame(channel)
    if not channel then return false end
    local owner = channelGet(channel, "Owner")
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

local function getPetPosition(plot, slot)
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
    return podium.Position
end

local function scanAllPets()
    local pets = {}
    local dbg = { loadModulesOk = false, plotsFound = false, plotCount = 0,
                   channelsFound = 0, ownerOk = 0, animalListFound = 0,
                   animalsConsidered = 0, animalsMatchedData = 0, animalsWithPos = 0 }
    _G.TPScanDebug = dbg

    if not loadModules() then return pets end
    dbg.loadModulesOk = true

    local Plots = workspace:FindFirstChild("Plots")
    if not Plots then return pets end
    dbg.plotsFound = true

    for _, plot in ipairs(Plots:GetChildren()) do
        dbg.plotCount = dbg.plotCount + 1
        local channel = getPlotChannel(plot.Name)
        if not channel then continue end
        dbg.channelsFound = dbg.channelsFound + 1
        if isMyPlot(channel) then continue end
        if not ownerInGame(channel) then continue end
        dbg.ownerOk = dbg.ownerOk + 1

        local ownerName = ""
        pcall(function()
            local owner = channelGet(channel, "Owner")
            if typeof(owner) == "Instance" and owner:IsA("Player") then
                ownerName = owner.Name
            elseif type(owner) == "table" and owner.Name then
                ownerName = tostring(owner.Name)
            elseif typeof(owner) == "Instance" and owner.Name then
                ownerName = owner.Name
            elseif type(owner) == "number" then
                local p = Players:GetPlayerByUserId(owner)
                if p then ownerName = p.Name end
            end
        end)

        local animalList = channelGet(channel, "AnimalList")
        if not animalList then continue end
        dbg.animalListFound = dbg.animalListFound + 1

        for slot, animalData in pairs(animalList) do
            if type(animalData) ~= "table" then continue end
            dbg.animalsConsidered = dbg.animalsConsidered + 1
            local animalName = animalData.Index
            if not animalName then continue end
            local animalInfo = AnimalsData and AnimalsData[animalName]
            if not animalInfo then continue end
            if _VanishIsFusing(animalData) then continue end
            dbg.animalsMatchedData = dbg.animalsMatchedData + 1

            local mutation = animalData.Mutation or "None"
            local genValue = 0
            pcall(function()
                genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil)
            end)

            local displayName = (animalInfo and animalInfo.DisplayName) or animalName
            local pos = getPetPosition(plot, slot)

            if pos then
                dbg.animalsWithPos = dbg.animalsWithPos + 1
                table.insert(pets, {
                    name = displayName,
                    ownerName = ownerName,
                    mps = genValue,
                    mutation = mutation,
                    position = pos,
                    plot = plot.Name,
                    slot = tostring(slot),
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
-- Sky platform coordinate tables + constants
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
    if not petClosest then return nil, nil end
    return petClosest, bestRowKey
end

-- =====================================================================
-- Path visualization helpers
-- =====================================================================
local _vizParts = {}
local function clearViz()
    for _, p in ipairs(_vizParts) do if p and p.Parent then p:Destroy() end end
    table.clear(_vizParts)
end
local function vizLine(a, b, color)
    local d = b - a
    if d.Magnitude < 0.05 then return end
    local p = Instance.new("Part")
    p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
    p.Material = Enum.Material.Neon; p.Color = color
    p.Size = Vector3.new(0.4, 0.4, d.Magnitude)
    p.CFrame = CFrame.new((a + b) / 2, b)
    p.Parent = workspace
    _vizParts[#_vizParts + 1] = p
end
local function vizDot(pos, color, sz)
    local p = Instance.new("Part")
    p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
    p.Shape = Enum.PartType.Ball; p.Material = Enum.Material.Neon; p.Color = color
    p.Size = Vector3.new(sz, sz, sz)
    p.Position = pos
    p.Parent = workspace
    _vizParts[#_vizParts + 1] = p
end
local function vizPath(fromPos, waypoints)
    if #waypoints == 0 then return end
    vizDot(fromPos, Color3.fromRGB(255, 79, 200), 1.8)
    local prev = fromPos
    for _, wp in ipairs(waypoints) do
        vizLine(prev, wp, Color3.fromRGB(255, 40, 160))
        vizDot(wp, Color3.fromRGB(255, 79, 200), 1.6)
        prev = wp
    end
end

-- =====================================================================
-- Velocity mover
-- =====================================================================
local ARRIVE = 20

local function vZero(hrp)
    if not hrp then return end
    local vy = hrp.AssemblyLinearVelocity.Y
    hrp.AssemblyLinearVelocity = Vector3.new(0, vy, 0)
    hrp.AssemblyAngularVelocity = Vector3.zero
end

local function velMoveThrough(hrp, waypoints)
    if not hrp or not hrp.Parent or #waypoints == 0 then return end
    vizPath(hrp.Position, waypoints)
    local wpIdx = 1
    local done = false
    local conn
    local function finish()
        if done then return end
        done = true
        if hrp and hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            local _, y = hrp.CFrame:ToEulerAnglesYXZ()
            hrp.CFrame = CFrame.new(waypoints[#waypoints]) * CFrame.Angles(0, y, 0)
        end
        if conn then conn:Disconnect() end
        -- Boucle de soin post-arrivee pendant 0.6s pour absorber les degats de chute delayed
        task.spawn(function()
            local char = LP.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not hum then return end
            local t = 0
            while t < 0.6 do
                if not hum or not hum.Parent then break end
                pcall(function() hum.Health = hum.MaxHealth end)
                task.wait(0.05)
                t = t + 0.05
            end
        end)
    end
    local lastDist, stall = math.huge, 0
    conn = RunService.Heartbeat:Connect(function()
        if not hrp or not hrp.Parent or done then
            if conn then conn:Disconnect() end
            return
        end
        local _mHum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if _mHum and _mHum.Health < _mHum.MaxHealth then
            pcall(function() _mHum.Health = _mHum.MaxHealth end)
        end
        equipCarpet()
        local target = waypoints[wpIdx]
        local diff = target - hrp.Position
        local mag = diff.Magnitude
        if mag < ARRIVE then
            wpIdx = wpIdx + 1
            if wpIdx > #waypoints then finish() return end
            lastDist, stall = math.huge, 0
            target = waypoints[wpIdx]
            diff = target - hrp.Position
            mag = diff.Magnitude
        end

        if mag > lastDist - 0.05 then stall = stall + 1 else stall = 0 end
        lastDist = mag
        if stall >= 18 then finish() return end
        if mag >= 0.1 then
            local dir = diff.Unit
local speed = (_G.FlashExtra and _G.FlashExtra.tpSpeed) or 400
-- Autoriser le mouvement vertical si le waypoint courant est en hauteur (arc de saut)
local isGroundSegment = hrp.Position.Y <= 14 and target.Y <= 14
local rawVelY = isGroundSegment and 0 or (dir.Y * speed)
-- Limiter la vitesse de descente pour eviter les degats de chute
local velY = (rawVelY < 0) and math.max(rawVelY, -60) or rawVelY
hrp.AssemblyLinearVelocity = Vector3.new(dir.X * speed, velY, dir.Z * speed)
        end
    end)
    local totalDist = 0
    local prev = hrp.Position
    for _, wp in ipairs(waypoints) do
        totalDist = totalDist + (prev - wp).Magnitude
        prev = wp
    end
    local speed = (_G.FlashExtra and _G.FlashExtra.tpSpeed) or 400
local timeout = totalDist / speed + 2
    local elapsed = 0
    while not done and elapsed < timeout do
        task.wait(0.05)
        elapsed = elapsed + 0.05
    end
    finish()
    vZero(hrp)
end

-- =====================================================================
-- Raycast / route-pulling helpers
-- =====================================================================
local _DIRS = { Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1), Vector3.new(0,0,-1) }
local _STRUCT = { ["structure base home"] = true, ["Wall"] = true, ["Floor"] = true, ["Roof"] = true }
local _SKIP_NAME = { ["DeliveryHitbox"]=true, ["StealHitbox"]=true, ["LaserHitbox"]=true,
    ["AnimalTarget"]=true, ["Multiplier"]=true, ["Laser"]=true, ["Hitbox"]=true,
    ["Spawn"]=true, ["MainRoot"]=true, ["SecondFloor"]=true, ["ThirdFloor"]=true, ["Slope"]=true }
local function _blocks(inst)
    if not inst then return false end
    if _SKIP_NAME[inst.Name] then return false end
    if inst.CanCollide then return true end
    if _STRUCT[inst.Name] then return true end
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
local function _len(pts)
    local s, prev = 0, pts[1]
    for k = 2, #pts do s = s + (pts[k] - prev).Magnitude; prev = pts[k] end
    return s
end
local function _pull(pts)
    if #pts <= 2 then return pts end
    local out = { pts[1] }
    local i = 1
    while i < #pts do
        local j = #pts
        while j > i + 1 and not _clear(out[#out], pts[j]) do j = j - 1 end
        out[#out + 1] = pts[j]
        i = j
    end
    return out
end
local function _stages(toPos)
    local st = {}
    for _, dr in ipairs(_DIRS) do
        local cd = _clearDist(toPos, dr, 46)
        if cd >= 12 then st[#st + 1] = toPos + dr * math.min(cd - 5, 38) end
    end
    return st
end
local function _routeClear(pts)
    for i = 1, #pts - 1 do
        if not _clear(pts[i], pts[i + 1]) then return false end
    end
    return true
end
local function _peakY(pts)
    local m = -math.huge
    for _, p in ipairs(pts) do if p.Y > m then m = p.Y end end
    return m
end
local function _starts(fromPos)
    local pts = { fromPos }
    if _block(fromPos, fromPos + Vector3.new(0, 40, 0)) then
        for _, dr in ipairs(_DIRS) do
            local cd = _clearDist(fromPos, dr, 40)
            if cd >= 12 then pts[#pts + 1] = fromPos + dr * math.min(cd - 5, 34) end
        end
    end
    return pts
end

local function _candidates(sp, stage, toPos)
    local list = {}
    local function add(mid)
        if mid then list[#list + 1] = { sp, mid, stage, toPos }
        else list[#list + 1] = { sp, stage, toPos } end
    end
    add(nil)
    add(Vector3.new(stage.X, sp.Y, stage.Z))
    add(Vector3.new(sp.X, stage.Y, sp.Z))
    local dir = Vector3.new(stage.X - sp.X, 0, stage.Z - sp.Z)
    if dir.Magnitude > 0.1 then
        dir = dir.Unit
        local perp = Vector3.new(-dir.Z, 0, dir.X)
        for _, off in ipairs({ 20, -20, 40, -40 }) do
            add(sp + perp * off)
        end
    end
    return list
end

local PathfindingService = game:GetService("PathfindingService")
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

local _LIFT_HEIGHTS = { 6, 12, 20, 30, 45, 60 }
local _LAUNCH_PEAK_Y = 21  -- hauteur du saut pour survoler boutiques et camions

-- Arc de saut haut : monte droit, survole, descend sur la dest
local function _launchRoute(fromPos, toPos)
    local peakY = math.max(fromPos.Y, toPos.Y) + _LAUNCH_PEAK_Y
    local up1   = Vector3.new(fromPos.X, peakY, fromPos.Z)
    local over  = Vector3.new(toPos.X,   peakY, toPos.Z)
    return { fromPos, up1, over, toPos }
end
local function _simpleLiftRoute(fromPos, toPos)
    for _, lift in ipairs(_LIFT_HEIGHTS) do
        local mid = (fromPos + toPos) / 2 + Vector3.new(0, lift, 0)
        local pts = { fromPos, mid, toPos }
        if _routeClear(pts) and _clearWide(fromPos, mid) and _clearWide(mid, toPos) then
            return pts
        end
    end
    for _, lift in ipairs(_LIFT_HEIGHTS) do
        local up   = fromPos + Vector3.new(0, lift, 0)
        local over = Vector3.new(toPos.X, up.Y, toPos.Z)
        local pts  = { fromPos, up, over, toPos }
        if _routeClear(pts) and _clearWide(up, over) then
            return pts
        end
    end
    return nil
end

local function computeRoute(fromPos, toPos, facingDir)
    if _clear(fromPos, toPos) then return { toPos } end

    -- Chemin tres court : pas besoin de monter, aller tout droit
    local horizDist = Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z).Magnitude
    if horizDist < 50 then return { toPos } end

    if _G._tpV2Enabled then
        -- TP V2 : saut haut pour survoler boutiques et camions (floor 1 et floor 2)
        return _launchRoute(fromPos, toPos)
    end

    -- TP V1 : ancien TP original (source)
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
-- Tool helpers
-- =====================================================================
local function equipTool(name)
    local char = LP.Character
    if not char or char:FindFirstChild(name) then return char ~= nil end
    local bp = LP:FindFirstChild("Backpack")
    if not bp then return false end
    local tool = bp:FindFirstChild(name)
    if tool and tool:IsA("Tool") then tool.Parent = char; return true end
    return false
end

local function unequipAll()
    local char, bp = LP.Character, LP.Backpack
    if not char or not bp then return end
    for _, t in pairs(char:GetChildren()) do
        if t:IsA("Tool") then t.Parent = bp end
    end
end

-- =====================================================================
-- Clone swap
-- =====================================================================
local _cloneActive = false   -- true for the entire lifetime of a doClone() call
local function _doCloneImpl()
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
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
        if firesignal then
            pcall(firesignal, tpButton.MouseButton1Down)
            task.wait()
            pcall(firesignal, tpButton.MouseButton1Up)
        else
            local vim = Instance.new("VirtualInputManager")
            local inset = cloneref(game:GetService("GuiService")):GetGuiInset()
            local p = tpButton.AbsolutePosition + (tpButton.AbsoluteSize / 2) + inset
            vim:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 1)
            task.wait()
            vim:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 1)
        end
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    local start = hrp and hrp.Position
    local cloneName2 = tostring(LP.UserId) .. "_Clone"

    local charAdded = false
    local caConn = LP.CharacterAdded:Connect(function() charAdded = true end)

    local refired = false
    local rebuilt = false
    fire()
    for i = 1, 300 do
        RunService.Heartbeat:Wait()
        local _c = LP.Character
        local _h = _c and _c:FindFirstChild("HumanoidRootPart")
        local cloneGone = not workspace:FindFirstChild(cloneName2)
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
    return rebuilt or charAdded or (not workspace:FindFirstChild(cloneName2))
end

-- Public doClone wrapper: holds the _cloneActive flag for the ENTIRE clone
-- operation (every return path, even on error) so goToBrainrot can verify the
-- clone has fully ended before it starts the go-to-brainrot movement.
local function doClone()
    _cloneActive     = true
    _G.TPCloneActive = true
    local ok, res = pcall(_doCloneImpl)
    _cloneActive     = false
    _G.TPCloneActive = false
    if not ok then
        warn("[TP] doClone error: " .. tostring(res))
        return false
    end
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
                if dead or (zeroSince and (os.clock() - zeroSince) >= 3.0) then  -- PATCH: 0.5->3s
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
    _G._tpInProgress = true  -- block steal engine during the whole goto phase
    -- Verify the clone function has fully ended before applying the go-to-brainrot
    -- movement. If a clone swap is still running, wait for it (up to 5 s) so we
    -- never race an in-progress clone.
    do
        local _ct0 = os.clock()
        while (_cloneActive or _G.TPCloneActive) and (os.clock() - _ct0) < 5 do
            _G.TPStatus = "goto_brainrot_waiting_clone"
            task.wait(0.05)
        end
    end

    _G.TPStatus = "goto_brainrot_waiting_char"

    local char, hrp, hum
    local deadline = os.clock() + 5
    repeat
        task.wait(0.05)
        char = LP.Character
        hrp  = char and char:FindFirstChild("HumanoidRootPart")
        hum  = char and char:FindFirstChildOfClass("Humanoid")
    until (hrp and hrp.Parent and hum and hum.Health > 0) or os.clock() > deadline

    if not hrp or not hrp.Parent then
        _G.TPStatus = "goto_brainrot_no_char"
        warn("[TP] goToBrainrot: character not ready after clone swap")
        return
    end

    local _tw = os.clock()
    repeat
        task.wait(0.05)
        char = LP.Character
        local hasCarpet = false
        for _, n in ipairs(CARPET_NAMES) do if findTool(n) then hasCarpet = true; break end end
        if hasCarpet then break end
    until os.clock() - _tw > 0.5

    local snapPart = findAdorneeGlobal(petData)

    _enableAntiDie()

    equipCarpet()
    if not hrp or not hrp.Parent then _G.TPStatus = "goto_brainrot_lost_char"; return end

    if not snapPart then
        _G.TPStatus = "goto_brainrot_no_part"
        warn("[TP] goToBrainrot: could not resolve spawn part")
        return
    end

    local exactPos = snapPart.Position
    local isThirdFloor  = exactPos.Y > 22
    local isSecondFloor = exactPos.Y > 10 and not isThirdFloor
    local snapY
    if isThirdFloor then
        snapY = exactPos.Y - 8
    elseif isSecondFloor then
        snapY = -4
    else
        snapY = exactPos.Y + 3.5
    end
    -- Land exactly on the spawn position on all floors.
    local snapPos = Vector3.new(exactPos.X, snapY, exactPos.Z)

    local _healDone = false
    local _localHealConn = RunService.Heartbeat:Connect(function()
        if _healDone then return end
        local _c = LP.Character
        local _h = _c and _c:FindFirstChildOfClass("Humanoid")
        if _h and _h.Parent then
            -- PATCH: healer et aussi empecher les etats de mort
            _h.Health = _h.MaxHealth
            pcall(function()
                if _h:GetState() == Enum.HumanoidStateType.Dead then
                    _h:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end)
        end
    end)

    local function fireTween()
        char = LP.Character
        hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp or not hrp.Parent then return end
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        local dist = (hrp.Position - snapPos).Magnitude
        local _snapSpeed = (_G.FlashExtra and _G.FlashExtra.brainrotSnapSpeed) or BRAINROT_SNAP_SPEED
        local tweenTime = math.clamp(dist / math.max(1, _snapSpeed), 0.20, 3.0)
        local tw = TweenService:Create(
            hrp,
            TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {CFrame = CFrame.new(snapPos)}
        )
        tw:Play()
        tw.Completed:Wait()
        char = LP.Character
        hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
    end

    -- Utilise le hold démarré AVANT le clone (si dispo), sinon démarre maintenant
    local _preHoldPrompt = _G._earlyPreHoldPrompt
    local _preHoldAt     = _G._earlyPreHoldAt or 0
    _G._earlyPreHoldPrompt = nil
    _G._earlyPreHoldAt     = nil
    -- Afficher la barre maintenant qu'on est dans la base
    _G._FH_HideAutoGrabBar = false
    if not _preHoldPrompt then
        pcall(function()
            if _G._stealTPPreHold and _stealEnabled then
                _preHoldPrompt, _preHoldAt = _G._stealTPPreHold(petData)
            end
        end)
    end

    fireTween()
    task.wait(0.05)
    char = LP.Character
    hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and (hrp.Position - snapPos).Magnitude > 3 then
        fireTween()
    end

    -- PLAQUE: créer sous les pieds du joueur après l'arrivée
    task.spawn(function()
        pcall(function()
            task.wait(0.15)
            local _c = LP.Character
            local _hrp = _c and _c:FindFirstChild("HumanoidRootPart")
            local _hum = _c and _c:FindFirstChildOfClass("Humanoid")
            if not _hrp then return end
            local _hipH = (_hum and _hum.HipHeight) or 2.0
            local _feetY = _hrp.Position.Y - _hipH - 1.0
            local _plaqueInst = Instance.new("Part")
            _plaqueInst.Name          = "HubBrainrotPlaque"
            _plaqueInst.Size          = Vector3.new(8, 0.2, 8)
            _plaqueInst.Anchored      = true
            _plaqueInst.CanCollide    = true
            _plaqueInst.Transparency  = 0.5
            _plaqueInst.Material      = Enum.Material.SmoothPlastic
            _plaqueInst.Color         = Color3.fromRGB(255, 40, 160)
            _plaqueInst.CastShadow    = false
            _plaqueInst.CFrame        = CFrame.new(_hrp.Position.X, _feetY, _hrp.Position.Z)
            _plaqueInst.Parent        = workspace
            -- Supprimer après 3s fixes
            task.wait(3)
            pcall(function() if _plaqueInst and _plaqueInst.Parent then _plaqueInst:Destroy() end end)
        end)
    end)

    -- Arrival anchor: pin the HRP exactly on the spawn point for a moment so we
    -- don't drift, slide, or get knocked off right after landing. Duration is
    -- the "Wall Anchor Wait" setting (was previously stored but never applied).
    char = LP.Character
    hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.Parent then
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        pcall(function() hrp.CFrame = CFrame.new(snapPos) end)
        local _anchorWait = (_G.FlashExtra and _G.FlashExtra.wallAnchorWait) or 0.10
        if _anchorWait and _anchorWait > 0 then
            hrp.Anchored = true
            task.wait(_anchorWait)
            -- re-fetch in case the character respawned during the wait
            char = LP.Character
            hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.Parent then
                hrp.AssemblyLinearVelocity  = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                hrp.Anchored = false
            end
        end
    end

    _healDone = true
    _localHealConn:Disconnect()
    -- PATCH: garder antiDie actif pendant le steal

    -- PATCH: desequiper le tapis et stopper velocity SEULEMENT si float pas actif
    pcall(function()
        local _c = LP.Character
        local _hum = _c and _c:FindFirstChildOfClass("Humanoid")
        local _hrp = _c and _c:FindFirstChild("HumanoidRootPart")
        -- Ne pas desequiper si le float auto est actif (evite la chute)
        if _hum then _hum:UnequipTools() end
        if _hrp then
            _hrp.AssemblyLinearVelocity  = Vector3.zero
            _hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end)

    -- PATCH: heal continu + garder antiDie pendant le steal
    task.spawn(function()
        local _t0 = os.clock()
        while (LP:GetAttribute("Stealing") or os.clock() - _t0 < 3) do
            local _c = LP.Character
            local _h = _c and _c:FindFirstChildOfClass("Humanoid")
            if _h and _h.Parent and _h.Health < _h.MaxHealth then
                _h.Health = _h.MaxHealth
            end
            task.wait(0.05)
        end
        task.wait(0.5)
        _disableAntiDie()
    end)
    _G._tpInProgress = false  -- release steal engine — player is now in position
    -- Fire trigger immediately (hold was already running during the tween)
    task.spawn(function()
        pcall(function()
            if _preHoldPrompt and _G._stealTPFire then
                _G._stealTPFire(_preHoldPrompt, _preHoldAt)
            else
                -- No prompt (TP-only steal): still auto-equip after server delay
                if _G._autoEquipAfterSteal then _G._autoEquipAfterSteal() end
            end
        end)
    end)
    _G.TPStatus = "at_brainrot"
end

-- =====================================================================
-- Main entry: doVelocityTP
-- =====================================================================
local isTeleporting = false

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

local function doVelocityTP()
    if isTeleporting then return end

    -- Vérifier si le grapin est utilisable avant de TP
    local _gTool = findGrappleTool()
    if _gTool then
        local _enabled = _gTool:GetAttribute("Enabled")
        if _enabled == false then
            _G.TPStatus = "grapple_on_cooldown"
            return
        end
        local _cdVal = _gTool:FindFirstChild("Cooldown") or _gTool:FindFirstChild("Debounce") or _gTool:FindFirstChild("Active")
        if _cdVal and _cdVal:IsA("BoolValue") and _cdVal.Value == true then
            _G.TPStatus = "grapple_on_cooldown"
            return
        end
        local _GRAPPLE_CD = _G.GrappleCooldown or 7
        local _lastArrival = _G._lastGrappleFiredAt
        if _lastArrival and (os.clock() - _lastArrival) < _GRAPPLE_CD then
            _G.TPStatus = "grapple_on_cooldown"
            return
        end
    end

    isTeleporting = true
    _G._tpInProgress = true
    -- Use pcall to catch any errors and always reset isTeleporting
    local success, err = pcall(function()
        clearViz()
        _G.TPStatus = "start"
        if not NetModule then pcall(loadNet) end

        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then _G.TPStatus = "no_char"; return end

        -- PATCH: verifier qu'il y a des brainrots AVANT de commencer
        local _quickScan = scanAllPets()
        if #_quickScan == 0 then
            _G.TPStatus = "no_brainrot_found"
            isTeleporting = false
            return
        end

        -- PATCH: adapter la vitesse du TP selon le ping
        pcall(function()
            local ping = LP:GetNetworkPing() * 1000  -- en ms
            local fe = _G.FlashExtra
            if fe then
                if ping > 100 then
                    local factor = math.clamp(1 - (ping - 100) / 400, 0.4, 0.85)
                    fe.tpSpeed           = math.floor(5000 * factor)
                    fe.brainrotSnapSpeed = math.floor(300 * factor)
                else
                    fe.tpSpeed           = 5000
                    fe.brainrotSnapSpeed = 300
                end
            end
        end)

        -- PATCH: activer antiDie immediatement au debut du TP
        _enableAntiDie()
        hrp.Anchored = true
        hrp.AssemblyLinearVelocity  = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero

        -- ── Grapple pre‑fire ──────────────────────────────────────────
        if _G.FlashGrappleEnabled and type(fireGrappleV2) == "function" then
            pcall(fireGrappleV2, true)
            task.wait(0.25)
            local char2 = LP.Character
            local hrp2 = char2 and char2:FindFirstChild("HumanoidRootPart")
            if hrp2 then hrp2.Anchored = true end
        end

        local allPets = scanAllPets()
        if #allPets == 0 then
            local _t0 = os.clock()
            while #allPets == 0 and os.clock() - _t0 < 4 do
                task.wait(0.15)
                allPets = scanAllPets()
            end
        end
        if #allPets == 0 then
            _G.TPStatus = "no_brainrot_found"
            -- PATCH: reset isTeleporting immediatement pour ne pas bloquer le prochain appui
            isTeleporting = false
            return
        end

        local fe = _G.FlashExtra
        if not fe then _G.TPStatus = "no_FlashExtra"; return end
        if (fe.tpFpsGate or 0) > 0 then
            local _gateT0 = os.clock()
            while (_G._FlashCurrentFPS or 999) < fe.tpFpsGate and os.clock() - _gateT0 < 10 do
                _G.TPStatus = "waiting_fps_" .. tostring(math.floor(_G._FlashCurrentFPS or 0))
                task.wait(0.1)
            end
        end

        local minMPS = ((fe.tpMinMPS or 0) * 1e6)

        local pet

        -- If a specific Steal Target is selected (manual UID from the Steal Target
        -- list), go to THAT brainrot — this overrides the priority/highest pick.
        -- The steal cache uid is "<plot>_<slot>", which we can rebuild from the
        -- scanAllPets entries (they carry .plot and .slot).
        local _selUID = (_G.StealGetManualUID and _G.StealGetManualUID()) or nil
        if _selUID then
            for _, candidate in ipairs(allPets) do
                if (tostring(candidate.plot) .. "_" .. tostring(candidate.slot)) == _selUID then
                    pet = candidate
                    break
                end
            end
            if pet then
                _G.TPStatus = "steal_target=" .. tostring(pet.name)
            else
                warn("[TP] selected Steal Target not found in scan — falling back to priority/highest")
            end
        end

        if not pet then
        do
            if fe.tpPriorityEnabled and not fe.tpHighestEnabled and fe.priorityList and #fe.priorityList > 0 then
                local bestRank, bestMPS = math.huge, -math.huge
                for _, candidate in ipairs(allPets) do
                    if minMPS <= 0 or (candidate.mps or 0) >= minMPS then
                        local rank = math.huge
                        local cLow = candidate.name and candidate.name:lower()
                        local oLow = candidate.ownerName and candidate.ownerName:lower() or ""
                        for i, pName in ipairs(fe.priorityList) do
                            local pLow = pName:lower()
                            local pStripped = pLow:match("^@(.+)$") or pLow
                            local isAt = pName:sub(1,1) == "@"
                            if isAt then
                                if oLow == pStripped then rank = i; break end
                            else
                                if pLow == cLow then rank = i; break end
                            end
                        end
                        if rank ~= math.huge and (rank < bestRank or (rank == bestRank and (candidate.mps or 0) > bestMPS)) then
                            bestRank = rank
                            bestMPS  = candidate.mps or 0
                            pet      = candidate
                        end
                    end
                end
                if not pet then
                    _G.TPStatus = "no_priority_found"
                    warn("[TP] No priority brainrot found in current plots — add one to your priority list or disable TP Priority.")
                    return
                end
            else
                local bestMPS = -math.huge
                for _, candidate in ipairs(allPets) do
                    if minMPS <= 0 or (candidate.mps or 0) >= minMPS then
                        if (candidate.mps or 0) > bestMPS then
                            bestMPS = candidate.mps or 0
                            pet     = candidate
                        end
                    end
                end
            end
        end
        end -- if not pet (Steal Target override)

        if not pet then _G.TPStatus = "no_target_after_filters"; return end

        local petPos = pet.position
        local petName = pet.name
        _G.TPStatus = "target=" .. tostring(petName)

        local adjY = petPos.Y
        if TALL_PETS[petName] then adjY = petPos.Y - TALL_OFFSET end
        -- Détection 2ème étage : cherche le Spawn du podium (méthode fiable)
        local _podiumY = adjY
        local _spawnPos = nil
        pcall(function()
            local _plotsWS = workspace:FindFirstChild("Plots")
            local _pl = _plotsWS and _plotsWS:FindFirstChild(pet.plot)
            local _pods = _pl and _pl:FindFirstChild("AnimalPodiums")
            local _pod = _pods and _pods:FindFirstChild(pet.slot)
            if _pod then
                local _sp = _pod:FindFirstChild("Spawn", true)
                if not _sp then
                    local _base = _pod:FindFirstChild("Base")
                    _sp = _base and _base:FindFirstChild("Spawn")
                end
                if _sp then
                    _podiumY = _sp.Position.Y
                    _spawnPos = _sp.Position
                else
                    local ok, pv = pcall(function() return _pod:GetPivot().Position end)
                    if ok then _podiumY = pv.Y end
                end
            end
        end)
        local isSecondFloor = _podiumY > UPPER_Y_THRESHOLD and _podiumY <= 24
        local coordTable = (adjY > UPPER_Y_THRESHOLD and not isSecondFloor) and UPPER or LOWER

        local closestData, skyKey = findClosest(petPos, coordTable)
        if not closestData or not skyKey then _G.TPStatus = "no_sky_platform"; warn("[TP] no_sky_platform"); return end

        local destPos = closestData.coord

        if coordTable == UPPER then
            local FLOOR2_BASES = {
                { L=Vector3.new(-478.0322,13.9682,  25.2552),  R=Vector3.new(-478.9711,13.9682, -11.5476) },
                { L=Vector3.new(-479.4897,14.0340, -81.4871),  R=Vector3.new(-478.7449,14.0340,-118.3792) },
                { L=Vector3.new(-340.5145,14.0340,-119.2653),  R=Vector3.new(-340.2055,14.0340, -82.6786) },
                { L=Vector3.new(-339.6728,14.5682, -11.6249),  R=Vector3.new(-339.6895,14.5682,  23.9712) },
                { L=Vector3.new(-339.6208,14.5682,  95.4651),  R=Vector3.new(-339.8099,13.9682, 130.8262) },
                { L=Vector3.new(-479.2108,14.0340, 131.9893),  R=Vector3.new(-478.3889,14.0340,  96.0183) },
                { L=Vector3.new(-479.5883,14.5682, 203.1649),  R=Vector3.new(-479.6722,14.3680, 240.1458) },
                { L=Vector3.new(-339.7557,14.0338, 238.5831),  R=Vector3.new(-339.1931,14.0338, 201.7895) },
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
        -- 2eme etage : continuer le TP via le chemin du bas; goToBrainrot placera au 1er etage juste sous le brainrot.
        local _floor2Part = nil

        local maxHP = hum.MaxHealth
        hum.Health = maxHP
        local healConn = RunService.Heartbeat:Connect(function()
            if hum and hum.Parent then hum.Health = maxHP end
        end)

        local _carpet = carpetEngage()
        _G.TPStatus = _carpet and ("carpet:" .. _carpet) or "NO_carpet"
        if not _carpet then warn("[TP] NO CARPET FOUND — tell me your carpet gear's exact name") end
        vZero(hrp)

        local facingDir
        if closestData.facing == "NORTH" then
            facingDir = Vector3.new(0, 0, -1)
        elseif closestData.facing == "SOUTH" then
            facingDir = Vector3.new(0, 0, 1)
        elseif closestData.facing == "EAST" then
            facingDir = Vector3.new(-1, 0, 0)
        elseif closestData.facing == "WEST" then
            facingDir = Vector3.new(1, 0, 0)
        else
            facingDir = Vector3.new(0, 0, -1)
        end

        -- Back the clone spot off the base/wall by 0.05 studs.
        -- (Negative = back off the wall; positive would push toward the front.)
        destPos = destPos - facingDir * 0.05

        local _route = computeRoute(hrp.Position, destPos, facingDir)
        if hrp and hrp.Parent then
            hrp.Anchored = false
            hrp.AssemblyLinearVelocity  = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
        _G._lastGrappleFiredAt = os.clock()  -- cooldown part depuis le passage de la barrière
        velMoveThrough(hrp, _route)

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
            for _ = 1, 5 do  -- PATCH: reduit de 20 a 5
                task.wait(0.05)
                if _hum and _hum.FloorMaterial ~= Enum.Material.Air then break end
            end
        end

        do
            local stable = 0
            for _ = 1, 10 do  -- PATCH: reduit de 50 a 10
                local _hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
                if not _hrp or not _hrp.Parent then break end
                local flat = (Vector3.new(_hrp.Position.X, 0, _hrp.Position.Z) - Vector3.new(destPos.X, 0, destPos.Z)).Magnitude
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

        -- Walk forward into the base front for a moment: push with velocity so the
        -- Humanoid's collision stops us flush against the wall at its natural
        -- standing distance — a consistent, non-clipping spot — then clone from
        -- exactly there. Makes the clone land good every time regardless of the
        -- exact arrival position. (facingDir is horizontal, so this never lifts us.)
        do
            local _whrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if _whrp and _whrp.Parent then
                local _t0 = os.clock()
                while os.clock() - _t0 < 0.05 do  -- PATCH: reduit de 0.15 a 0.05
                    _whrp.AssemblyLinearVelocity  = facingDir * 16
                    _whrp.AssemblyAngularVelocity = Vector3.zero
                    RunService.Heartbeat:Wait()
                end
                _whrp.AssemblyLinearVelocity  = Vector3.zero
                _whrp.AssemblyAngularVelocity = Vector3.zero
                destPos = _whrp.Position   -- clone from where the walk settled
            end
        end

        _G.TPStatus = "at_sky_before_clone"

do
    local _phrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if _phrp and _phrp.Parent then
        _phrp.AssemblyLinearVelocity  = Vector3.zero
        _phrp.AssemblyAngularVelocity = Vector3.zero
        pcall(function() _phrp.CFrame = CFrame.new(destPos, destPos + facingDir) end)
        pcall(function() _phrp.Anchored = true end)

        local _anchorWait
        if petPos.Y <= 20 then
            _anchorWait = 0.05  -- PATCH: reduit de 0.15
        else
            _anchorWait = (_G.FlashExtra and _G.FlashExtra.skyCloneWait) or SKY_CLONE_WAIT
        end
        task.wait(_anchorWait)

        pcall(function() _phrp.Anchored = false end)
        task.wait(0.02)  -- PATCH: reduit
    end
end

-- Position lock DURING the clone: pin the HRP at the clone spot every frame until
-- the clone teleport rebuilds the character, so residual movement / physics (or the
-- go-to-brainrot motion starting early) can't drift it into the wall — which is
-- what spawns the clone in a broken position.
local _cloneLockCF   = CFrame.new(destPos, destPos + facingDir)
local _cloneLockChar = LP.Character
local _cloneLockConn
_cloneLockConn = RunService.Heartbeat:Connect(function()
    if LP.Character ~= _cloneLockChar then return end   -- swap happened: stop forcing
    local _h = _cloneLockChar and _cloneLockChar:FindFirstChild("HumanoidRootPart")
    if _h and _h.Parent then
        _h.AssemblyLinearVelocity  = Vector3.zero
        _h.AssemblyAngularVelocity = Vector3.zero
        _h.CFrame = _cloneLockCF
    end
end)

-- Démarrer le hold AVANT le clone pour gagner du temps pendant le swap
-- Masquer la barre pendant le clone (elle s'affichera une fois dans la base)
_G._earlyPreHoldPrompt = nil
_G._earlyPreHoldAt     = 0
_G._FH_HideAutoGrabBar = true
pcall(function()
    if _G._stealTPPreHold then
        _G._earlyPreHoldPrompt, _G._earlyPreHoldAt = _G._stealTPPreHold(pet)
    end
end)

local cloneOk = doClone()

if _cloneLockConn then _cloneLockConn:Disconnect() end

-- Always disconnect the heal connection — whether clone succeeded or
-- failed, or goToBrainrot errors out.
healConn:Disconnect()

if cloneOk then
    _G.TPStatus = "clone_ok"
    -- Wait for the character to be fully present after the clone swap.
    -- CharacterAdded fires a new character; give it up to 5 s.
    local _t0 = os.clock()
    repeat
        task.wait(0.05)
    until (LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") and LP.Character.Parent) or os.clock() - _t0 > 5
    _G._tpInProgress = false
    pcall(goToBrainrot, pet)
    _G._FH_HideAutoGrabBar = false  -- sécurité : toujours remettre visible après goToBrainrot
    pcall(function()
        local vim = Instance.new("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.C, false, game)
        task.wait(0.05)
        vim:SendKeyEvent(false, Enum.KeyCode.C, false, game)
    end)
else
    _G.TPStatus = "clone_FAILED"
    _G._FH_HideAutoGrabBar = false  -- clone raté : remettre la barre visible
end

clearViz()
    end) -- end of pcall

    -- Garantie absolue : toujours remettre la barre visible après un TP (même si erreur)
    _G._FH_HideAutoGrabBar = false

    -- PATCH: toujours deanchorer le HRP, stopper velocity et desequiper carpet, meme si erreur
    pcall(function()
        local _c = LP.Character
        local _hum = _c and _c:FindFirstChildOfClass("Humanoid")
        local _h = _c and _c:FindFirstChild("HumanoidRootPart")
        if _h and _h.Parent then
            _h.Anchored = false
            _h.AssemblyLinearVelocity  = Vector3.zero
            _h.AssemblyAngularVelocity = Vector3.zero
        end
        if _hum then pcall(function() _hum:UnequipTools() end) end
    end)
    pcall(function()
        if _stealBarTween then _stealBarTween:Cancel() end
        if _stealBarFill  then _stealBarFill.Size  = UDim2.new(0, 0, 1, 0) end
        if _stealBarLabel then _stealBarLabel.Text  = "STEAL 0%" end
        _stealIsBusy = false
        _G.PriorityStealActive = false
    end)

    -- Always reset the flag, even if an error occurred
    isTeleporting = false
    _G._tpInProgress = false
    warn("[TP] final status = " .. tostring(_G.TPStatus))
end
-- =====================================================================
-- Exposure + keybind trigger
-- =====================================================================
_G.FlashStartTP = doVelocityTP

task.spawn(function() pcall(loadModules) pcall(loadNet) end)

-- Pre-load saved extra config so priority/highest settings are correct before the startup TP fires
pcall(function()
    local HttpSvc2 = game:GetService("HttpService")
    local raw = readfile("FlashTP_extra.json")
    local t = HttpSvc2:JSONDecode(raw)
    local fe2 = _G.FlashExtra
    if fe2 then
        if type(t.tpPriorityEnabled) == "boolean" then fe2.tpPriorityEnabled = t.tpPriorityEnabled end
        if type(t.tpHighestEnabled)  == "boolean" then fe2.tpHighestEnabled  = t.tpHighestEnabled  end
        if type(t.tpMinMPS)          == "number"  then fe2.tpMinMPS          = t.tpMinMPS          end
        if type(t.tpFpsGate)         == "number"  then fe2.tpFpsGate         = t.tpFpsGate         end
        if type(t.priorityList)      == "table"   then fe2.priorityList      = t.priorityList      end
        if type(t.skyCloneWait)      == "number"  then fe2.skyCloneWait      = t.skyCloneWait      end
        if type(t.skyCloneWait2)     == "number"  then fe2.skyCloneWait2     = t.skyCloneWait2     end
        if type(t.cloneDelay)        == "number"  then fe2.cloneDelay        = t.cloneDelay        end
        if type(t.wallAnchorWait)    == "number"  then fe2.wallAnchorWait    = t.wallAnchorWait    end
        if type(t.walkDuration)      == "number"  then fe2.walkDuration      = t.walkDuration      end
        if type(t.walkSettle)        == "number"  then fe2.walkSettle        = t.walkSettle        end
        if type(t.walkDuration2)     == "number"  then fe2.walkDuration2     = t.walkDuration2     end
        if type(t.walkSettle2)       == "number"  then fe2.walkSettle2       = t.walkSettle2       end
        if type(t.tpSpeed)           == "number"  then fe2.tpSpeed           = t.tpSpeed           end
        if type(t.brainrotSnapSpeed) == "number"  then fe2.brainrotSnapSpeed = t.brainrotSnapSpeed end
        if type(t.tpTool)            == "string"  then fe2.tpTool            = t.tpTool            end
    end
    -- Apply saved speed
    if fe2 and fe2.tpSpeed and _G._FlashSetSpeed then
        _G._FlashSetSpeed(fe2.tpSpeed)
    end
end)

task.spawn(function()
    local char = LP.Character or LP.CharacterAdded:Wait()
    char:WaitForChild("HumanoidRootPart", 10)
    char:WaitForChild("Humanoid", 10)
    pcall(loadModules); pcall(loadNet)
    if _G._autoTPOnJoin == false then return end
    -- PATCH: ne pas re-TP si c'est un reset manuel (executeReset met ce flag)
    if _G._manualResetActive then _G._manualResetActive = false; return end
    local _t0 = os.clock()
    repeat
        local ok, pets = pcall(scanAllPets)
        if ok and pets and #pets > 0 then break end
        task.wait(0.3)
    until os.clock() - _t0 > 12
    task.wait(0.5)
    if _G._autoTPOnJoin == false then return end
    if _G._manualResetActive then _G._manualResetActive = false; return end
    -- Attendre que le perso soit pose au sol avant de TP (evite mort par chute au spawn)
    local _joinChar = LP.Character
    local _joinHum = _joinChar and _joinChar:FindFirstChildOfClass("Humanoid")
    if _joinHum then
        local _landedT = os.clock()
        repeat task.wait(0.05) until
            _joinHum.FloorMaterial ~= Enum.Material.Air
            or os.clock() - _landedT > 3
        task.wait(0.1)
    end
    -- Protection sante pendant le TP de join
    task.spawn(function()
        local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
        if not hum then return end
        for _ = 1, 30 do
            if not hum or not hum.Parent then break end
            pcall(function() hum.Health = hum.MaxHealth end)
            task.wait(0.05)
        end
    end)
    pcall(doVelocityTP)
end)

    end)
end)

-- Speed setter for the hub TP Settings tab
_G._FlashSetSpeed = function(v)
    if _G.FlashExtra then
        _G.FlashExtra.tpSpeed = v
        -- Save to file (the save function is defined in the TP Settings tab)
        if _saveExtraFromHub then pcall(_saveExtraFromHub) end
    end
end

-- Bridge isTeleporting → _G._autoTPEnabled so the XTC header status bar works
task.spawn(function()
    while true do
        _G._autoTPEnabled = isTeleporting
        task.wait(0.25)
    end
end)

-- Wire hub TPKeybind → Flash TP
task.spawn(function()
    local UIS2 = game:GetService("UserInputService")
    UIS2.InputBegan:Connect(function(input, gp)
        if UserInputService:GetFocusedTextBox() then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local wantKey = _G.TPKeybind or "V"
        if Enum.KeyCode[wantKey] and input.KeyCode == Enum.KeyCode[wantKey] then
            if _G.FlashStartTP then
                task.spawn(function() pcall(_G.FlashStartTP) end)
            end
        end
    end)
end)

-- ═══ Brainrot ESP ═══
task.spawn(function() pcall(function()

repeat task.wait() until game:IsLoaded()
task.wait(1)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local Packages = ReplicatedStorage:WaitForChild("Packages", 10)
local Datas = ReplicatedStorage:WaitForChild("Datas", 10)
local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
local Utils = ReplicatedStorage:WaitForChild("Utils", 10)
if not Packages or not Datas or not Shared or not Utils then return end

local Synchronizer = require(Packages:WaitForChild("Synchronizer"))
local AnimalsData = require(Datas:WaitForChild("Animals"))
local AnimalsShared = require(Shared:WaitForChild("Animals"))
local NumberUtils = require(Utils:WaitForChild("NumberUtils"))

-- Internal ESP state
local ESP_INSTANCES = {}
local ESP_BEST_UID = nil
local CARPET_ESP = {}
local espAnimalsCache = {}
local plotChannels = {}
local lastAnimalData = {}
local lastRefreshTime = 0
local refreshInterval = 0.6
local rainbowGradients = {}
local bestRedGradients = {}

-- Priority lookup for the Brainrot ESP. Uses the hub's own Flash TP priority
-- list (_G.FlashExtra.priorityList) as the source of truth: rank = index in
-- that list (lower = higher priority). Previously this referenced
-- _G.FULL_PRIORITY_PUBLIC / _G._lookupPriority which nothing in this hub ever
-- sets, so isTargetBrainrot always returned false and the ESP showed nothing.
local TARGET_DISPLAY_NAMES = {}     -- [name or lower(name)] = rank (number)
local function rebuildTargetDisplayNames()
    for k in pairs(TARGET_DISPLAY_NAMES) do TARGET_DISPLAY_NAMES[k] = nil end
    local list = (_G.FlashExtra and _G.FlashExtra.priorityList) or {}
    for rank, name in ipairs(list) do
        if TARGET_DISPLAY_NAMES[name] == nil then TARGET_DISPLAY_NAMES[name] = rank end
        local lname = name:lower()
        if TARGET_DISPLAY_NAMES[lname] == nil then TARGET_DISPLAY_NAMES[lname] = rank end
        -- Also map the raw AnimalsData index name <-> DisplayName both ways
        local info = AnimalsData[name]
        if info and info.DisplayName then
            if TARGET_DISPLAY_NAMES[info.DisplayName] == nil then TARGET_DISPLAY_NAMES[info.DisplayName] = rank end
            if TARGET_DISPLAY_NAMES[info.DisplayName:lower()] == nil then TARGET_DISPLAY_NAMES[info.DisplayName:lower()] = rank end
        end
    end
end

-- Returns true if this brainrot should be shown on the ESP at all.
local function isTargetBrainrot(animalName)
    if not animalName then return false end
    -- If priority list is empty or highest mode is on, show everything
    local fe2 = _G.FlashExtra
    local list = fe2 and fe2.priorityList
    if not list or #list == 0 or (fe2 and fe2.tpHighestEnabled == true) then return true end
    if TARGET_DISPLAY_NAMES[animalName] then return true end
    if TARGET_DISPLAY_NAMES[animalName:lower()] then return true end
    return false
end

-- Returns the priority rank (lower = better) or nil if not in the list.
local function getBrainrotRank(animalName)
    if not animalName then return nil end
    return TARGET_DISPLAY_NAMES[animalName] or TARGET_DISPLAY_NAMES[animalName:lower()]
end

local MUTATION_COLORS = {
    -- Match Steal Target's mutation coloring exactly
    Diamond = Color3.fromRGB(135, 206, 235),
    Candy = Color3.fromRGB(255, 182, 193),
    Gold = Color3.fromRGB(255, 223, 0),
    Bloodrot = Color3.fromRGB(255, 0, 0),
    Radioactive = Color3.fromRGB(0, 255, 0),
    Lava = Color3.fromRGB(255, 140, 0),
    Galaxy = Color3.fromRGB(138, 43, 226),
    Divine = Color3.fromRGB(255, 253, 208),
    Cyber = Color3.fromRGB(0, 255, 255),
    Normal = Color3.fromRGB(200, 200, 200),
    -- ESP-only (Steal Target doesn't list these): keep as gradient strings/colors
    Rainbow = "rainbow",
    Cursed = Color3.fromRGB(100, 0, 0),
    ["Yin Yang"] = "yin_yang",
    ["YinYang"] = "yin_yang",
    ["Yinyang"] = "yin_yang",
}

local rainbowSequence = ColorSequence.new{
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 165, 0)),
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.50, Color3.fromRGB(0, 255, 0)),
    ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
    ColorSequenceKeypoint.new(0.83, Color3.fromRGB(75, 0, 130)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(238, 130, 238))
}

local BEST_RED_WAVE = ColorSequence.new{
    -- Darker red base with a bright shimmer streak in the middle that scrolls
    -- left-to-right via Heartbeat (see bestRedGradients animation loop).
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(140, 0, 30)),
    ColorSequenceKeypoint.new(0.40, Color3.fromRGB(160, 10, 35)),
    ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 90, 110)),  -- bright shimmer
    ColorSequenceKeypoint.new(0.60, Color3.fromRGB(160, 10, 35)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(140, 0, 30)),
}

local WHITE_GRADIENT = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
})

local BB_WIDTH = 340
local BB_HEIGHT_NO_MUT = 56
local BB_HEIGHT_MUT = 80
local BB_IMG_SIZE = 44   -- extra width reserved on the left for the brainrot image

-- Looks up an icon/thumbnail image id for a brainrot from AnimalsData.
local function getBrainrotImage(animalIndexOrName)
    if not animalIndexOrName then return nil end
    local info = AnimalsData[animalIndexOrName]
    if not info then
        -- animalIndexOrName might be a DisplayName; find the matching index
        for idx, d in pairs(AnimalsData) do
            if type(d) == "table" and d.DisplayName == animalIndexOrName then
                info = d
                break
            end
        end
    end
    if not info then return nil end
    for _, f in ipairs({"Image", "Thumbnail", "Icon"}) do
        if info[f] and type(info[f]) == "string" and info[f] ~= "" then return info[f] end
    end
    return nil
end

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
            if typeof(owner) == "Instance" and owner:IsA("Player") then
                return owner.UserId == LocalPlayer.UserId
            elseif typeof(owner) == "table" and owner.UserId then
                return owner.UserId == LocalPlayer.UserId
            elseif typeof(owner) == "Instance" then
                return owner == LocalPlayer
            end
        end
    end
    return false
end

local function getPodiumWorldPart(animal)
    if not animal.plot or not animal.slot then return nil end
    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    local plot = plotsFolder:FindFirstChild(animal.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animal.slot)
    if not podium then return nil end
    local base = podium:FindFirstChild("Base")
    if not base then return podium end
    local spawn = base:FindFirstChild("Spawn")
    return spawn or base or podium
end

local function getAdorneePart(obj)
    if typeof(obj) ~= "Instance" or not obj.Parent then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        local primary = obj.PrimaryPart
        if primary and primary.Parent then return primary end
    end
    -- Handles Frames, Folders, Models, and any other container returned by
    -- getPodiumWorldPart (e.g. when Base is a non-BasePart folder).
    local part = obj:FindFirstChildWhichIsA("BasePart", true)
    if part then return part end
    return nil
end

local function clearESPForUID(uid)
    local rec = ESP_INSTANCES[uid]
    if not rec then return end
    if rec.highlight then pcall(function() rec.highlight:Destroy() end) end
    if rec.billboard then pcall(function() rec.billboard:Destroy() end) end
    if rec.mutationGradient then
        rainbowGradients[rec.mutationGradient] = nil
        pcall(function() rec.mutationGradient:Destroy() end)
    end
    if rec.nameGradient then bestRedGradients[rec.nameGradient] = nil end
    if rec.genGradient then bestRedGradients[rec.genGradient] = nil end
    ESP_INSTANCES[uid] = nil
end

local function clearCarpetESP(key)
    local rec = CARPET_ESP[key]
    if not rec then return end
    if rec.highlight then pcall(function() rec.highlight:Destroy() end) end
    if rec.billboard then pcall(function() rec.billboard:Destroy() end) end
    if rec.mutationGradient then
        rainbowGradients[rec.mutationGradient] = nil
        pcall(function() rec.mutationGradient:Destroy() end)
    end
    if rec.nameGradient then bestRedGradients[rec.nameGradient] = nil end
    if rec.genGradient then bestRedGradients[rec.genGradient] = nil end
    CARPET_ESP[key] = nil
end

local function setupMutationLabel(rec, label, mutation)
    local existingGrad = label:FindFirstChild("UIGradient")
    if existingGrad then
        rainbowGradients[existingGrad] = nil
        existingGrad:Destroy()
    end
    -- Reset to plain text mode by default
    label.RichText = false
    label.TextColor3 = Color3.fromRGB(255, 255, 255)

    local mutConfig = MUTATION_COLORS[mutation]
    if not mutConfig then return end
    if typeof(mutConfig) == "Color3" then
        label.TextColor3 = mutConfig
    elseif mutConfig == "rainbow" then
        -- Per-letter solid colors via RichText (no shimmer animation).
        -- R=red A=orange I=yellow N=green B=blue O=indigo W=violet
        label.RichText = true
        label.Text = '<font color="#FF4444">R</font><font color="#FF9933">a</font><font color="#FFDD33">i</font><font color="#44DD44">n</font><font color="#4488FF">b</font><font color="#AA55FF">o</font><font color="#FF66AA">w</font>'
    elseif mutConfig == "yin_yang" then
        local grad = Instance.new("UIGradient")
        grad.Color = ColorSequence.new(Color3.new(0,0,0), Color3.new(1,1,1))
        grad.Parent = label
        rec.mutationGradient = grad
    end
end

local function buildESPBillboard(adornee, isBest, hasMutation, nameText, genText, mutation, imageId, ownerName)
    local rec = { part = adornee, isBest = isBest, hasMutation = hasMutation }
    local bbHeight = hasMutation and BB_HEIGHT_MUT or BB_HEIGHT_NO_MUT
    bbHeight = bbHeight + 16  -- extra room for the owner row

    local highlight = Instance.new("Highlight")
    highlight:SetAttribute("_KeepVisual", true)
    highlight.Adornee = adornee
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.4
    highlight.FillColor = Color3.fromRGB(255, 100, 255)
    highlight.OutlineTransparency = 0
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.Parent = adornee
    rec.highlight = highlight

    local bb = Instance.new("BillboardGui")
    bb:SetAttribute("_KeepVisual", true)
    bb.Name = "BrainrotESP"
    bb.Size = UDim2.new(0, BB_WIDTH, 0, bbHeight)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = 3000
    bb.Adornee = adornee
    bb.Parent = adornee
    rec.billboard = bb

    local container = Instance.new("Frame")
    container.Name = "Container"
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.Parent = bb

    -- Brainrot image on the left side, spanning the name/gen/mutation rows
    local hasImage = imageId ~= nil and imageId ~= ""
    local textLeftPad = hasImage and (BB_IMG_SIZE + 8) or 6
    local textWidth   = hasImage and (BB_IMG_SIZE + 8) or 12

    local mainRowsHeight = hasMutation and BB_HEIGHT_MUT or BB_HEIGHT_NO_MUT

    if hasImage then
        local img = Instance.new("ImageLabel")
        img.Name = "BrainrotIcon"
        img.Size = UDim2.new(0, BB_IMG_SIZE, 0, BB_IMG_SIZE)
        img.Position = UDim2.new(0, 4, 0, math.max(0, (mainRowsHeight - BB_IMG_SIZE) / 2))
        img.BackgroundTransparency = 1
        img.Image = imageId
        img.ScaleType = Enum.ScaleType.Fit
        img.Parent = container
        rec.imageLabel = img
    end

    local yOffset = 3
    local rowHeight = hasMutation and math.floor((mainRowsHeight - 6) / 3) or math.floor((mainRowsHeight - 6) / 2)

    if hasMutation then
        local mutationLabel = Instance.new("TextLabel")
        mutationLabel.Size = UDim2.new(1, -12 - textWidth, 0, rowHeight)
        mutationLabel.Position = UDim2.new(0, 6 + textLeftPad, 0, yOffset)
        mutationLabel.BackgroundTransparency = 1
        mutationLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        mutationLabel.Font = Enum.Font.GothamBold
        mutationLabel.TextSize = 19
        mutationLabel.TextStrokeTransparency = 0
        mutationLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        mutationLabel.TextXAlignment = Enum.TextXAlignment.Center
        mutationLabel.Parent = container
        rec.labelMutation = mutationLabel
        yOffset = yOffset + rowHeight
    end

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -12 - textWidth, 0, rowHeight)
    nameLabel.Position = UDim2.new(0, 6 + textLeftPad, 0, yOffset)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 26
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Parent = container
    yOffset = yOffset + rowHeight

    local nameGradient = Instance.new("UIGradient")
    nameGradient.Parent = nameLabel
    rec.nameGradient = nameGradient
    if isBest then
        -- Darker red shimmer: gradient registered in bestRedGradients so the
        -- Heartbeat animation loop scrolls the bright streak left-to-right.
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)  -- gradient applies on top
        nameGradient.Color = BEST_RED_WAVE
        bestRedGradients[nameGradient] = true
    else
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameGradient.Color = WHITE_GRADIENT
    end

    local genLabel = Instance.new("TextLabel")
    genLabel.Size = UDim2.new(1, -12 - textWidth, 0, rowHeight)
    genLabel.Position = UDim2.new(0, 6 + textLeftPad, 0, yOffset)
    genLabel.BackgroundTransparency = 1
    genLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
    genLabel.Font = Enum.Font.GothamBold
    genLabel.TextSize = 21
    genLabel.TextStrokeTransparency = 0
    genLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    genLabel.TextXAlignment = Enum.TextXAlignment.Center
    genLabel.Parent = container
    rec.labelName = nameLabel
    rec.labelGen = genLabel

    if isBest then
        -- Same darker-red shimmer on the gen line
        genLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        local genGradient = Instance.new("UIGradient")
        genGradient.Color = BEST_RED_WAVE
        genGradient.Parent = genLabel
        bestRedGradients[genGradient] = true
        rec.genGradient = genGradient
    end

    -- Owner row, spans full width along the bottom
    local ownerLabel = Instance.new("TextLabel")
    ownerLabel.Name = "OwnerLabel"
    ownerLabel.Size = UDim2.new(1, -12, 0, 14)
    ownerLabel.Position = UDim2.new(0, 6, 0, mainRowsHeight + 2)
    ownerLabel.BackgroundTransparency = 1
    ownerLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
    ownerLabel.Font = Enum.Font.GothamBold
    ownerLabel.TextSize = 13
    ownerLabel.TextStrokeTransparency = 0.4
    ownerLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    ownerLabel.TextXAlignment = Enum.TextXAlignment.Center
    ownerLabel.Text = "@" .. tostring(ownerName or "Unknown")
    ownerLabel.Parent = container
    rec.labelOwner = ownerLabel

    rec.labelName.Text = nameText
    rec.labelGen.Text = genText
    if hasMutation and rec.labelMutation then
        rec.labelMutation.Text = mutation
        setupMutationLabel(rec, rec.labelMutation, mutation)
    end
    return rec
end

local function refreshAllESP()
    local activeUIDs = {}
    local bestAnimal = nil
    local bestRank = math.huge
    local minGenValue = 50000000

    -- Pick the best brainrot to mark as "best" (shown with red wave highlight).
    -- If TP Priority is enabled: pick lowest rank in priority list.
    -- If TP Highest mode (or priority disabled): pick highest MPS.
    local fe = _G.FlashExtra
    local usePriority = fe and fe.tpPriorityEnabled == true and not fe.tpHighestEnabled
    if usePriority then
        for _, animalData in ipairs(espAnimalsCache) do
            if not isMyBaseAnimal(animalData) and isTargetBrainrot(animalData.name) then
                local rank = getBrainrotRank(animalData.name) or 9999
                if rank < bestRank then
                    bestRank = rank
                    bestAnimal = animalData
                end
            end
        end
    else
        -- Highest MPS mode: best = highest genValue in cache (sorted descending)
        local bestMPS = -1
        for _, animalData in ipairs(espAnimalsCache) do
            if not isMyBaseAnimal(animalData) then
                local mps = animalData.genValue or 0
                if mps > bestMPS then bestMPS = mps; bestAnimal = animalData end
            end
        end
    end
    ESP_BEST_UID = bestAnimal and bestAnimal.uid or nil
    -- Publish best UID for any consumers (line-to-brainrot, etc.)
    _G._espBestUID = ESP_BEST_UID
    _G._espInstances = ESP_INSTANCES

    for _, animalData in ipairs(espAnimalsCache) do
        if isMyBaseAnimal(animalData) then continue end
        if not isTargetBrainrot(animalData.name) then continue end

        if (animalData.uid == ESP_BEST_UID) or ((animalData.genValue or 0) >= minGenValue) then
            local uid = animalData.uid
            activeUIDs[uid] = true

            local rec = ESP_INSTANCES[uid]
            local model = getPodiumWorldPart(animalData)

            if not model then
                if rec then clearESPForUID(uid) end
            else
                local adornee = getAdorneePart(model)
                if not adornee then
                    if rec then clearESPForUID(uid) end
                else
                    local isBest = (uid == ESP_BEST_UID)
                    local hasMutation = animalData.mutation and animalData.mutation ~= "None" and animalData.mutation ~= ""

                    if not rec or rec.part ~= adornee or rec.isBest ~= isBest then
                        if rec then clearESPForUID(uid) end
                        local imgId = getBrainrotImage(animalData.name)
                        rec = buildESPBillboard(adornee, isBest, hasMutation,
                            animalData.name, animalData.genText, animalData.mutation,
                            imgId, animalData.owner)
                        ESP_INSTANCES[uid] = rec
                    else
                        rec.labelName.Text = animalData.name
                        rec.labelGen.Text = animalData.genText
                        if rec.labelOwner then
                            rec.labelOwner.Text = "@" .. tostring(animalData.owner or "Unknown")
                        end
                        if hasMutation and rec.labelMutation then
                            rec.labelMutation.Text = animalData.mutation
                            setupMutationLabel(rec, rec.labelMutation, animalData.mutation)
                        end
                    end
                end
            end
        end
    end

    for uid in pairs(ESP_INSTANCES) do
        if not activeUIDs[uid] then clearESPForUID(uid) end
    end
end

local function getAnimalHash(animalList)
    if not animalList then return "" end
    local hash = ""
    for slot, data in pairs(animalList) do
        if type(data) == "table" then
            hash = hash .. tostring(slot) .. tostring(data.Index) .. tostring(data.Mutation)
        end
    end
    return hash
end

local function scanSinglePlot(plot)
    pcall(function()
        local plotUID = plot.Name
        local channel = Synchronizer:Get(plotUID)
        if not channel then return end

        local animalList = channel:Get("AnimalList")
        local currentHash = getAnimalHash(animalList)
        if lastAnimalData[plotUID] == currentHash then return end
        lastAnimalData[plotUID] = currentHash

        for i = #espAnimalsCache, 1, -1 do
            if espAnimalsCache[i].plot == plot.Name then
                table.remove(espAnimalsCache, i)
            end
        end

        local owner = channel:Get("Owner")
        if not owner or (owner.Name and not Players:FindFirstChild(owner.Name)) then
            refreshAllESP()
            return
        end

        local ownerName = owner and owner.Name or "Unknown"
        if not animalList then return end

        for slot, animalData in pairs(animalList) do
            if type(animalData) == "table" then
                local animalName = animalData.Index
                local animalInfo = AnimalsData[animalName]
                if not animalInfo then continue end

                local displayName = animalInfo.DisplayName or animalName

                local mutation = animalData.Mutation or "None"
                local genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil) or 0

                -- Cache every brainrot above a small floor (filters out
                -- placeholder/worthless entries). The priority-list filter
                -- used to be applied here too, but that left the cache
                -- (and therefore the ESP) empty whenever nothing currently
                -- on enemy plots happened to be in the priority list.
                -- refreshAllESP() now decides which one to actually show.
                if genValue < 1 then continue end

                local genText
                do
                    local v = genValue
                    if v >= 1e9 then       genText = string.format("$%.2fB/s", v / 1e9)
                    elseif v >= 1e6 then   genText = string.format("$%.2fM/s", v / 1e6)
                    elseif v >= 1e3 then   genText = string.format("$%.2fK/s", v / 1e3)
                    else                   genText = string.format("$%d/s", math.floor(v)) end
                end

                table.insert(espAnimalsCache, {
                    name = displayName,
                    genText = genText,
                    genValue = genValue,
                    mutation = mutation,
                    owner = ownerName,
                    plot = plot.Name,
                    slot = tostring(slot),
                    uid = plot.Name .. "_" .. tostring(slot),
                })
            end
        end

        table.sort(espAnimalsCache, function(a, b)
            return (a.genValue or 0) > (b.genValue or 0)
        end)
        refreshAllESP()
    end)
end

local function setupPlotListener(plot)
    if plotChannels[plot.Name] then return end
    local channel
    local retries = 0
    while not channel and retries < 10 do
        local ok, result = pcall(function() return Synchronizer:Get(plot.Name) end)
        if ok and result then channel = result; break
        else retries = retries + 1; if retries < 10 then task.wait(0.5) end end
    end
    if not channel then return end
    plotChannels[plot.Name] = true
    scanSinglePlot(plot)
    plot.DescendantAdded:Connect(function() task.wait(0.1); scanSinglePlot(plot) end)
    plot.DescendantRemoving:Connect(function() task.wait(0.1); scanSinglePlot(plot) end)
    task.spawn(function()
        while plot.Parent and plotChannels[plot.Name] do
            task.wait(5); scanSinglePlot(plot)
        end
    end)
end

local function initializePlotScanner()
    local plots = Workspace:WaitForChild("Plots", 8)
    if not plots then return end
    for _, plot in ipairs(plots:GetChildren()) do setupPlotListener(plot) end
    plots.ChildAdded:Connect(function(plot) task.wait(0.5); setupPlotListener(plot) end)
    plots.ChildRemoved:Connect(function(plot)
        plotChannels[plot.Name] = nil
        lastAnimalData[plot.Name] = nil
        for i = #espAnimalsCache, 1, -1 do
            if espAnimalsCache[i].plot == plot.Name then
                table.remove(espAnimalsCache, i)
            end
        end
        refreshAllESP()
    end)
end

-- Heartbeat: gradient animation + periodic refresh
RunService.Heartbeat:Connect(function()
    local t = tick() % 1
    for grad in pairs(rainbowGradients) do
        if grad and grad.Parent then grad.Offset = Vector2.new(-t, 0)
        else rainbowGradients[grad] = nil end
    end
    local redT = (tick() * 0.3) % 1
    for grad in pairs(bestRedGradients) do
        if grad and grad.Parent then grad.Offset = Vector2.new(-redT, 0)
        else bestRedGradients[grad] = nil end
    end
    if _G._brainrotEspEnabled == false then
        -- Clear all active brainrot ESP instances when disabled
        for uid in pairs(ESP_INSTANCES) do
            pcall(clearESPForUID, uid)
        end
        return
    end
    if tick() - lastRefreshTime >= refreshInterval then
        rebuildTargetDisplayNames()
        pcall(refreshAllESP)
        lastRefreshTime = tick()
    end
end)

rebuildTargetDisplayNames()
initializePlotScanner()

end) end)


-- ═══ Steal Target (New Engine) ═══
task.spawn(function() pcall(function()

-- ============================================================
-- BRAINROT PRIORITY PET LIST
-- ============================================================
local ALL_PETS_PRIO = {
    "Strawberry Elephant", "Meowl", "Headless Horseman", "John Pork", "Skibidi Toilet", "Griffin",
    "Hydra Dragon Cannelloni", "Dragon Gingerini", "Dragon Cannelloni", "Love Love Bear", "Digi Narwhal",
    "La Supreme Combinasion", "Hydra Bunny", "Celestial Pegasus", "Cerberus", "Popcuru and Fizzuru",
    "Bunny and Eggy", "Rosey and Teddy", "Capitano Moby", "Cooki and Milki", "Burguro and Fryuro",
    "Ketupat Bros", "Reinito Sleighito", "Los Amigos", "Fortunu and Cashuru", "La Secret Combinasion",
    "Foxini Lanternini", "Kalika Bros", "Los Sekolahs", "Signore Carapace", "La Casa Boo",
    "Fragrama and Chocrama", "Cash or Card", "Duggy Bros", "La Food Combinasion", "Boppin Bunny",
    "Spooky and Pumpky", "Lavadorito Spinito", "Rubrikiko", "Los Spaghettis", "Sammyni Fattini",
    "Hokka Horloge", "Los Hackers", "Los Chillis", "Ginger Gerat", "La Ginger Sekolah", "Festive 67",
    "Guest 666", "Ventoliero Pavonero", "Quackini Snackini", "Cloverat Clapat", "Spaghetti Tualetti",
    "Elefanto Frigo", "Antonio", "Hopilikalika Hopilikalako", "Nacho Spyder", "Rosetti Tualetti",
    "Garama and Madundung", "Money Money Bros", "Jolly Jolly Sahur", "Gold Gold Gold", "Gym Bros",
    "Rico Dinero", "Ketchuru and Musturu", "Swaggy Bros", "La Romantic Grande", "Orcaledon",
    "Tictac Sahur", "Ketupat Kepat", "La Taco Combinasion", "Dug Dug Dug", "Tang Tang Keletang",
    "Lovin Rose", "Abyssaloco", "Los Tacoritas", "Eviledon", "Los Primos", "Los Cupids", "Los Puggies",
    "W or L", "Esok Sekolah", "La Jolly Grande", "Globba Steppa", "Tralaledon", "Gobblino Uniciclino",
    "Tuff Toucan", "Los Bros", "Money Money Puggy", "Churrito Bunnito", "Los Mobilis",
    "Celularcini Viciosini", "Los 67", "Chillin Chili", "Chipso and Queso", "Los Candies",
    "La Spooky Grande", "Los Planitos", "Snailo Clovero", "DJ Panda", "Las Sis",
    "Chicleteira Cupideira", "Fishino Clownino", "Baskito", "Los Sweethearts", "Tacorita Bicicleta",
    "Camera Ramena", "Spinny Hammy", "Cigno Fulgoro", "Los Spooky Combinasionas", "Los Hotspotsitos",
    "Los Jolly Combinasionas", "Mariachi Corazoni", "Noo my Heart", "Swag Soda", "Noo my Gold",
    "Chimnino", "Bananito", "Chicleteira Noelteira", "Los Combinasionas", "Tacorillo Crocodillo",
    "Los 25", "Los Burritos", "Donkeyturbo Express", "John Doe", "Steal a Brainrot 6767", "Noo my Eggs",
    "Los Chicleteiras", "Strawberrita", "Los Mi Gatitos", "Flipa Sandala", "Noo my Present",
    "Rang Ring Bus", "Serafinna Medusella", "Los Nooo My Hotspotsitos", "Arcadopus", "Noo my candy",
    "Los Quesadillas", "Futbolini Skatini", "Granny", "Chicleteirina Bicicleteirina", "Burrito Bandito",
    "Chill Puppy", "Los Bunitos", "Luck Luck Luck Sahur", "Cupid Hotspot", "Eid Eid Eid Sahur",
    "Chicleteira Bicicleteira", "Brunito Marsito", "Quesadillo Vampiro", "Mi Gatito", "Ho Ho Ho Sahur",
    "Cupid Cupid Sahur", "Pot Pumpkin", "Naughty Naughty", "Quesadilla Crocodila", "Buho de Volto",
    "Horegini Boom", "Santa Hotspot", "Pirulitoita Bicicleteira", "25", "Pot Hotspot", "Glaciator",
    "Bunny Bunny Bunny Sahur", "To to to Sahur"
}

-- ============================================================
-- CONFIG (steal mode + priority list, persisted to file)
-- ============================================================
local StealConfig = {
    StealNearest  = false,
    StealHighest  = true,
    StealPriority = false,
    PriorityList  = {},
    MinGenValue   = 0,
}
local STEAL_CONFIG_FILE = "steal_target_config.json"

local function saveStealConfig()
    if not writefile then return end
    pcall(function()
        local HttpService = game:GetService("HttpService")
        writefile(STEAL_CONFIG_FILE, HttpService:JSONEncode(StealConfig))
    end)
end

local function loadStealConfig()
    if not isfile or not readfile then return end
    pcall(function()
        local HttpService = game:GetService("HttpService")
        local raw = readfile(STEAL_CONFIG_FILE)
        if not raw or raw == "" then return end
        local ok, d = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok and type(d) == "table" then
            for k, v in pairs(d) do
                if StealConfig[k] ~= nil then StealConfig[k] = v end
            end
        end
    end)
end
loadStealConfig()

-- Expose config to hub GUI (mode buttons and priority list panel)
_G.StealConfig       = StealConfig
_G.saveStealConfig   = saveStealConfig
_G.ALL_PETS_PRIO     = ALL_PETS_PRIO

_G.StealParseMinGenText = function(txt)
    txt = tostring(txt or ""):lower():gsub("%s+", ""):gsub("%$", ""):gsub("/s", "")
    if txt == "" then return 0 end
    local mult = 1
    local suffix = txt:sub(-1)
    if suffix == "k" then mult = 1e3; txt = txt:sub(1, -2)
    elseif suffix == "m" then mult = 1e6; txt = txt:sub(1, -2)
    elseif suffix == "b" then mult = 1e9; txt = txt:sub(1, -2)
    elseif suffix == "t" then mult = 1e12; txt = txt:sub(1, -2)
    end
    return math.max(0, (tonumber(txt) or 0) * mult)
end

_G.StealFormatMinGenValue = function(v)
    v = tonumber(v) or 0
    if v <= 0 then return "" end
    if v >= 1e12 then return string.format("%.1ft", v / 1e12):gsub("%.0", "")
    elseif v >= 1e9 then return string.format("%.1fb", v / 1e9):gsub("%.0", "")
    elseif v >= 1e6 then return string.format("%.1fm", v / 1e6):gsub("%.0", "")
    elseif v >= 1e3 then return string.format("%.1fk", v / 1e3):gsub("%.0", "")
    end
    return tostring(math.floor(v))
end

_G.StealSetMinGenValue = function(value)
    StealConfig.MinGenValue = math.max(0, tonumber(value) or 0)
    saveStealConfig()
    local txt = _G.StealFormatMinGenValue(StealConfig.MinGenValue)
    pcall(function() if _G._StealTargetMinBox then _G._StealTargetMinBox.Text = txt end end)
    pcall(function() if _G._MainStealMinBox then _G._MainStealMinBox.Text = txt end end)
end

-- ============================================================
-- MODULES
-- ============================================================
local _stealServices = {
    Players           = game:GetService("Players"),
    RunService        = game:GetService("RunService"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    TweenService      = game:GetService("TweenService"),
}
local _stealLocalPlayer = _stealServices.Players.LocalPlayer

local _Sync, _AnimalsData, _AnimalsShared, _NumberUtils
local function _loadStealModules()
    local Packages = _stealServices.ReplicatedStorage:WaitForChild("Packages", 10)
    local Datas    = _stealServices.ReplicatedStorage:WaitForChild("Datas",    10)
    local Shared   = _stealServices.ReplicatedStorage:WaitForChild("Shared",   10)
    local Utils    = _stealServices.ReplicatedStorage:WaitForChild("Utils",    10)
    if not (Packages and Datas and Shared and Utils) then return false end
    local function tryReq(parent, name)
        local child = parent:WaitForChild(name, 5)
        if not child then return nil end
        local ok, res = pcall(require, child)
        return ok and res or nil
    end
    _Sync         = tryReq(Packages, "Synchronizer")
    _AnimalsData  = tryReq(Datas,    "Animals")
    _AnimalsShared = tryReq(Shared,  "Animals")
    _NumberUtils  = tryReq(Utils,    "NumberUtils")
    return (_Sync and _AnimalsData and _AnimalsShared and _NumberUtils)
end

-- ============================================================
-- ANIMAL CACHE (scan all plots, skip own)
-- ============================================================
local _stealMyPlotName   = nil
local _stealAnimalsCache = {}   -- exposed via _G for TP / ESP sections
local _stealLastHash     = {}
local _stealListDirty    = true

_G._stealAnimalsCache = _stealAnimalsCache  -- shared reference

local function _stealDetectMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end
    for _, plot in ipairs(plots:GetChildren()) do
        if _Sync then
            local ok, ch = pcall(_Sync.Get, _Sync, plot.Name)
            if ok and ch then
                local owner = ch:Get("Owner")
                if owner then
                    local isMe = (typeof(owner) == "Instance" and owner == _stealLocalPlayer)
                             or (type(owner) == "table" and owner.UserId == _stealLocalPlayer.UserId)
                    if isMe then _stealMyPlotName = plot.Name; return end
                end
            end
        end
        local sign = plot:FindFirstChild("PlotSign")
        if sign and sign:FindFirstChild("YourBase") and sign.YourBase:IsA("BillboardGui") and sign.YourBase.Enabled then
            _stealMyPlotName = plot.Name; return
        end
    end
end

local function _stealIsMyPlot(name) return name == _stealMyPlotName end

local function _stealGetHash(al)
    if not al then return "" end
    local parts = {}
    for slot, d in pairs(al) do
        if type(d) == "table" then
            parts[#parts+1] = tostring(slot).."|"..tostring(d.Index).."|"..tostring(d.Mutation)
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function _stealClearPlot(plotName)
    for i = #_stealAnimalsCache, 1, -1 do
        if _stealAnimalsCache[i].plot == plotName then
            table.remove(_stealAnimalsCache, i); _stealListDirty = true
        end
    end
    _stealLastHash[plotName] = nil
end

local function _stealScanPlot(plot)
    if not _Sync or _stealIsMyPlot(plot.Name) then return end
    pcall(function()
        local ch = _Sync:Get(plot.Name)
        if not ch then _stealClearPlot(plot.Name); return end
        local owner = ch:Get("Owner")
        if not owner then _stealClearPlot(plot.Name); return end
        local ownerName = (typeof(owner) == "Instance" and owner.Name)
                       or (type(owner) == "table" and owner.Name) or nil
        if not ownerName or ownerName == _stealLocalPlayer.Name
           or not _stealServices.Players:FindFirstChild(ownerName) then
            _stealClearPlot(plot.Name); return
        end
        local al   = ch:Get("AnimalList")
        local hash = _stealGetHash(al)
        if _stealLastHash[plot.Name] == hash then return end
        _stealLastHash[plot.Name] = hash
        -- Remove stale entries for this plot
        for i = #_stealAnimalsCache, 1, -1 do
            if _stealAnimalsCache[i].plot == plot.Name then table.remove(_stealAnimalsCache, i) end
        end
        if al then
            for slot, ad in pairs(al) do
                if type(ad) == "table" and ad.Index then
                    local aInfo = _AnimalsData[ad.Index]
                    if aInfo then
                        local mut = ad.Mutation or "None"
                        if mut == "Yin Yang" then mut = "YinYang" end
                        local gv = 0
                        pcall(function()
                            gv = _AnimalsShared:GetGeneration(ad.Index, ad.Mutation, ad.Traits, nil)
                        end)
                        if gv >= 1 then
                            _stealAnimalsCache[#_stealAnimalsCache+1] = {
                                name     = aInfo.DisplayName or ad.Index,
                                genText  = "$"..(_NumberUtils:ToString(gv)).."/s",
                                genValue = gv,
                                mutation = mut,
                                owner    = ownerName,
                                plot     = plot.Name,
                                slot     = tostring(slot),
                                uid      = plot.Name.."_"..tostring(slot),
                            }
                        end
                    end
                end
            end
        end
        table.sort(_stealAnimalsCache, function(a, b) return a.genValue > b.genValue end)
        _stealListDirty = true
    end)
end

_stealServices.Players.PlayerRemoving:Connect(function(p)
    if p == _stealLocalPlayer then return end
    for i = #_stealAnimalsCache, 1, -1 do
        if _stealAnimalsCache[i].owner == p.Name then
            table.remove(_stealAnimalsCache, i); _stealListDirty = true
        end
    end
end)

-- ============================================================
-- STEAL ENGINE
-- ============================================================
local _stealManualUID  = nil
local _stealEnabled    = false   -- master on/off (toggled by hub Auto Steal button)
local _stealIsBusy       = false
local _stealCooldownUntil = 0
local _stealDataCache  = {}
local STEAL_RADIUS        = 19   -- rayon normal
local STEAL_RADIUS_LAST   = 19   -- rayon réduit pour le dernier slot (fond droite)
local STEAL_LAST_SLOT     = "5"  -- nom du dernier podium
local STEAL_DURATION   = 1.4

local function _stealGetHRP()
    local c = _stealLocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function _stealPassesMin(p)
    if not StealConfig.StealNearest then return true end
    local minVal = tonumber(StealConfig.MinGenValue) or 0
    return minVal <= 0 or ((p and p.genValue) or 0) >= minVal
end

local function _stealGetFilteredPets()
    if StealConfig.StealPriority then
        local plist = StealConfig.PriorityList
        if plist and #plist > 0 then
            local lookup = {}
            for _, pname in ipairs(plist) do lookup[pname:lower()] = true end
            local filtered = {}
            for _, p in ipairs(_stealAnimalsCache) do
                if lookup[p.name:lower()] then filtered[#filtered+1] = p end
            end
            return filtered
        end
        return _stealAnimalsCache
    end
    if not StealConfig.StealNearest then return _stealAnimalsCache end
    local minVal = tonumber(StealConfig.MinGenValue) or 0
    if minVal <= 0 then return _stealAnimalsCache end
    local filtered = {}
    for _, p in ipairs(_stealAnimalsCache) do
        if _stealPassesMin(p) then filtered[#filtered+1] = p end
    end
    return filtered
end

local function _stealFindCacheEntry(plotName, slotName)
    for _, p in ipairs(_stealAnimalsCache) do
        if p.plot == plotName and p.slot == tostring(slotName) then return p end
    end
    return nil
end

local function _stealGetPriorityTarget(pets)
    for _, pname in ipairs(StealConfig.PriorityList) do
        local low = pname:lower()
        for _, p in ipairs(pets) do
            if p.name:lower() == low then return p end
        end
    end
    return nil
end

local function _stealGetActiveTarget()
    local pets = _stealGetFilteredPets()
    if #pets == 0 then return nil end
    if _stealManualUID then
        for _, p in ipairs(pets) do if p.uid == _stealManualUID then return p end end
        _stealManualUID = nil; _stealListDirty = true; return nil
    end
    if StealConfig.StealPriority then
        local prioTarget = _stealGetPriorityTarget(pets)
        return prioTarget or pets[1]
    elseif StealConfig.StealHighest then
        return pets[1]
    elseif StealConfig.StealNearest then
        local hrp = _stealGetHRP()
        if not hrp then return pets[1] end
        local plotsWS = workspace:FindFirstChild("Plots")
        local best, bestDist = nil, math.huge
        for _, p in ipairs(pets) do
            local plot = plotsWS and plotsWS:FindFirstChild(p.plot)
            if plot then
                local podiums = plot:FindFirstChild("AnimalPodiums")
                local podium  = podiums and podiums:FindFirstChild(p.slot)
                local base    = podium and podium:FindFirstChild("Base")
                local spawn   = base and base:FindFirstChild("Spawn")
                if spawn then
                    local d = (hrp.Position - spawn.Position).Magnitude
                    if d < bestDist then bestDist = d; best = p end
                end
            end
        end
        return best or pets[1]
    end
    return pets[1]
end

local function _stealFindPrompt(target)
    if not target then return nil end
    local hrp = _stealGetHRP()
    if not hrp then return nil end
    local plotsWS = workspace:FindFirstChild("Plots")
    if not plotsWS then return nil end
    local plot = plotsWS:FindFirstChild(target.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(target.slot)
    if not podium then return nil end
    local base  = podium:FindFirstChild("Base")
    local spawn = base and base:FindFirstChild("Spawn")
    if not spawn then return nil end
    local _sr = (target.slot == STEAL_LAST_SLOT) and STEAL_RADIUS_LAST or STEAL_RADIUS
    if not _G._stealSkipRadius and (spawn.Position - hrp.Position).Magnitude > _sr then return nil end
    -- Check PromptAttachment first
    local att = spawn:FindFirstChild("PromptAttachment")
    if att then
        for _, p in ipairs(att:GetChildren()) do
            if p:IsA("ProximityPrompt") and p.ActionText:find("Steal") then
                return p
            end
        end
    end
    -- Fallback: scan plot descendants for closest steal prompt
    local slotX, slotZ = spawn.Position.X, spawn.Position.Z
    local best, bestD = nil, math.huge
    for _, desc in ipairs(plot:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.ActionText:find("Steal") then
            local part = desc.Parent
            local pos  = nil
            if part and part:IsA("BasePart") then
                pos = part.Position
            elseif part and part:IsA("Attachment") and part.Parent and part.Parent:IsA("BasePart") then
                pos = part.Parent.Position
            end
            if pos then
                local hd = math.sqrt((pos.X - slotX)^2 + (pos.Z - slotZ)^2)
                if hd < 6 and hd < bestD then bestD = hd; best = desc end
            end
        end
    end
    return best
end

local function _stealFindNearest()
    local hrp = _stealGetHRP()
    if not hrp then return nil end
    local plotsWS = workspace:FindFirstChild("Plots")
    if not plotsWS then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, plot in ipairs(plotsWS:GetChildren()) do
        if _stealIsMyPlot(plot.Name) then continue end
        local pods = plot:FindFirstChild("AnimalPodiums")
        if not pods then continue end
        for _, pod in ipairs(pods:GetChildren()) do
            local base  = pod:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn")
            if spawn then
                local d = (spawn.Position - hrp.Position).Magnitude
                local _sr2 = (pod.Name == STEAL_LAST_SLOT) and STEAL_RADIUS_LAST or STEAL_RADIUS
                if d <= _sr2 and d < nearestDist then
                    local cacheEntry = _stealFindCacheEntry(plot.Name, pod.Name)
                    if not _stealPassesMin(cacheEntry) then continue end
                    local att = spawn:FindFirstChild("PromptAttachment")
                    if att then
                        for _, p in ipairs(att:GetChildren()) do
                            if p:IsA("ProximityPrompt") and p.ActionText:find("Steal") then
                                nearest, nearestDist = p, d
                            end
                        end
                    end
                end
            end
        end
    end
    return nearest
end

-- ── HUB PVP Auto Grab Bar state ─────────────────────────────────────────
local v1Progress    = 0
local v1HasTarget   = false
local v1TargetName  = ""
local v1TargetRate  = ""

local function _stealResetBar()
    v1Progress   = 0
    v1HasTarget  = false
    v1TargetName = ""
    v1TargetRate = ""
end

-- Auto-equip the brainrot tool that lands in backpack after a steal
-- Takes a pre-trigger snapshot synchronously, then watches async for the new tool.
-- Call _snapBeforeSteal() BEFORE firing the trigger, then pass the snapshot to
-- _watchAndEquip() which runs in the background.
local function _snapBeforeSteal()
    local lp   = _stealLocalPlayer
    local snap = {}
    if not lp then return snap end
    local char = lp.Character
    local bp   = lp:FindFirstChild("Backpack")
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then snap[t] = true end
        end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then snap[t] = true end
        end
    end
    return snap
end

local function _watchAndEquip(before)
    task.spawn(function()
        local lp = _stealLocalPlayer
        if not lp then return end
        local deadline = tick() + 6
        local newTool  = nil
        while tick() < deadline do
            -- Chercher dans backpack ET dans character (le jeu peut équiper direct)
            local freshBp   = lp:FindFirstChild("Backpack")
            local freshChar = lp.Character
            if freshBp then
                for _, t in ipairs(freshBp:GetChildren()) do
                    if t:IsA("Tool") and not before[t] then newTool = t; break end
                end
            end
            if not newTool and freshChar then
                for _, t in ipairs(freshChar:GetChildren()) do
                    if t:IsA("Tool") and not before[t] then newTool = t; break end
                end
            end
            if newTool then break end
            task.wait(0.05)
        end
        if newTool then
            for _ = 1, 5 do
                local c = lp.Character
                local h = c and c:FindFirstChildOfClass("Humanoid")
                if h then
                    -- Si le tool est déjà dans character, il est déjà équipé
                    if newTool.Parent == c then break end
                    pcall(function() h:EquipTool(newTool) end)
                    break
                end
                task.wait(0.1)
            end
        end
    end)
end

-- Legacy wrapper (called from goToBrainrot else-branch)
local function _autoEquipAfterSteal()
    local snap = _snapBeforeSteal()
    _watchAndEquip(snap)
end
_G._autoEquipAfterSteal = _autoEquipAfterSteal

local function _stealStartBar() end  -- progress driven by _stealExecute via v1Progress

-- ── Proximity grab constants ──────────────────────────────────────────────
local AG_PRIME_RANGE = 40
local AG_STEAL_RANGE = 10
local AG_HOLD_MIN    = 1.3
local AG_HOLD_MAX    = 6.0
local AG_ENTRY_DELAY = 0.1

local function _stealGetPromptDist(prompt)
    local hrp  = _stealGetHRP()
    if not hrp or not prompt or not prompt.Parent then return math.huge end
    local part = prompt.Parent
    if part:IsA("Attachment") then part = part.Parent end
    if not part or not part:IsA("BasePart") then return math.huge end
    return (hrp.Position - part.Position).Magnitude
end

local function _stealExecute(prompt)
    if _stealIsBusy then return end
    if not _stealDataCache[prompt] then
        local entry = { hold = {}, trigger = {}, ready = true }
        if getconnections then
            pcall(function()
                for _, c in ipairs(getconnections(prompt.PromptButtonHoldBegan)) do
                    if c.Function then entry.hold[#entry.hold+1] = c.Function end
                end
                for _, c in ipairs(getconnections(prompt.Triggered)) do
                    if c.Function then entry.trigger[#entry.trigger+1] = c.Function end
                end
            end)
        end
        _stealDataCache[prompt] = entry
    end
    local data = _stealDataCache[prompt]
    if not data.ready then return end
    if math.random(1, 50) == 1 then
        for k in pairs(_stealDataCache) do
            local ok, hp = pcall(function() return k.Parent ~= nil end)
            if not ok or not hp then _stealDataCache[k] = nil end
        end
    end
    data.ready   = false
    _stealIsBusy = true
    _G.PriorityStealActive = true
    do
        local target = _stealGetActiveTarget()
        if target then
            v1HasTarget  = true
            v1TargetName = tostring(target.name or "")
            local rate   = tostring(target.genText or "")
            if rate:sub(1, 1) == "$" then rate = rate:sub(2) end
            v1TargetRate = rate
        end
    end
    v1Progress = 0
    task.spawn(function()
        for _, f in ipairs(data.hold) do task.spawn(function() pcall(f) end) end
        local startT = tick()
        while tick() - startT < AG_HOLD_MIN do
            v1Progress = math.min((tick() - startT) / STEAL_DURATION, 0.99)
            _stealServices.RunService.Heartbeat:Wait()
        end
        local alreadyClose = _stealGetPromptDist(prompt) <= AG_STEAL_RANGE
        while tick() - startT < AG_HOLD_MAX do
            if not prompt.Parent then break end
            if _stealGetPromptDist(prompt) <= AG_STEAL_RANGE then
                if not alreadyClose then task.wait(AG_ENTRY_DELAY) end
                for _, f in ipairs(data.trigger) do task.spawn(function() pcall(f) end) end
                break
            end
            v1Progress = math.min((tick() - startT) / STEAL_DURATION, 0.99)
            _stealServices.RunService.Heartbeat:Wait()
        end
        v1Progress = 1
        local _snap = _snapBeforeSteal()
        task.wait(0.05)
        data.ready          = true
        _stealIsBusy        = false
        _stealCooldownUntil = tick() + 1.0
        _G.PriorityStealActive = false
        _stealResetBar()
        _watchAndEquip(_snap)
    end)
end

_stealServices.RunService.Heartbeat:Connect(function()
    if not _stealEnabled then return end
    if _stealIsBusy then return end
    if tick() < _stealCooldownUntil then return end
    if _G._tpInProgress then return end
    local prompt
    if StealConfig.StealNearest and not _stealManualUID then
        local hrp = _stealGetHRP()
        if not hrp then return end
        local plotsWS = workspace:FindFirstChild("Plots")
        if not plotsWS then return end
        local best, bestDist = nil, math.huge
        for _, plot in ipairs(plotsWS:GetChildren()) do
            if _stealIsMyPlot(plot.Name) then continue end
            local pods = plot:FindFirstChild("AnimalPodiums")
            if not pods then continue end
            for _, pod in ipairs(pods:GetChildren()) do
                local base  = pod:FindFirstChild("Base")
                local spawn = base and base:FindFirstChild("Spawn")
                if spawn then
                    local d = (spawn.Position - hrp.Position).Magnitude
                    if d <= AG_PRIME_RANGE and d < bestDist then
                        local cacheEntry = _stealFindCacheEntry(plot.Name, pod.Name)
                        if not _stealPassesMin(cacheEntry) then continue end
                        local att = spawn:FindFirstChild("PromptAttachment")
                        if att then
                            for _, p in ipairs(att:GetChildren()) do
                                if p:IsA("ProximityPrompt") and p.ActionText:find("Steal") then
                                    best, bestDist = p, d
                                end
                            end
                        end
                    end
                end
            end
        end
        prompt = best
    else
        local target = _stealGetActiveTarget()
        if target then
            _G._stealSkipRadius = true
            prompt = _stealFindPrompt(target)
            _G._stealSkipRadius = false
            if prompt and _stealGetPromptDist(prompt) > AG_PRIME_RANGE then
                prompt = nil
            end
        end
    end
    if prompt then _stealExecute(prompt) end
end)

_G._stealTPPreHold = function(petData)
    if not _stealEnabled or _stealIsBusy then return nil, 0 end
    _G._stealSkipRadius = true
    local prompt = _stealFindPrompt(petData)
    _G._stealSkipRadius = false
    if not prompt then return nil, 0 end
    if not _stealDataCache[prompt] then
        local entry = { hold = {}, trigger = {}, ready = true }
        if getconnections then
            pcall(function()
                for _, c in ipairs(getconnections(prompt.PromptButtonHoldBegan)) do
                    if c.Function then entry.hold[#entry.hold+1] = c.Function end
                end
                for _, c in ipairs(getconnections(prompt.Triggered)) do
                    if c.Function then entry.trigger[#entry.trigger+1] = c.Function end
                end
            end)
        end
        _stealDataCache[prompt] = entry
    end
    local data = _stealDataCache[prompt]
    if not data or not data.ready then return nil, 0 end
    data.ready   = false
    _stealIsBusy = true
    _G.PriorityStealActive = true
    -- Mettre les infos de cible pour que la barre affiche le bon nom dès le début
    v1Progress   = 0
    v1HasTarget  = true
    v1TargetName = tostring(petData and petData.name or "")
    do
        local _r = tostring(petData and petData.genText or "")
        if _r:sub(1,1) == "$" then _r = _r:sub(2) end
        v1TargetRate = _r
    end
    _stealStartBar()
    for _, f in ipairs(data.hold) do pcall(f) end
    return prompt, tick()
end

_G._stealTPFire = function(prompt, holdStartAt)
    if not prompt then return end
    local data = _stealDataCache[prompt]
    if not data then return end
    local holdTime = STEAL_DURATION
    pcall(function()
        if prompt.HoldDuration and prompt.HoldDuration > 0 then
            holdTime = prompt.HoldDuration
        end
    end)
    local ping      = _stealLocalPlayer:GetNetworkPing()
    local adjusted  = holdTime - math.clamp(ping * 0.75, 0, 0.10)
    local remaining = math.max(0, adjusted - (tick() - holdStartAt))
    if remaining > 0 then
        local t0 = tick()
        repeat
            v1Progress = math.clamp((tick() - holdStartAt) / adjusted, 0, 0.99)
            _stealServices.RunService.Heartbeat:Wait()
        until tick() - t0 >= remaining
    end
    v1Progress = 1
    local _snap = _snapBeforeSteal()

    -- Fire immédiatement dès l'arrivée (pas d'attente de distance)
    for _, f in ipairs(data.trigger) do pcall(f) end
    if fireproximityprompt and prompt and prompt.Parent then
        pcall(function() fireproximityprompt(prompt) end)
    end

    -- Burst fire sur les 4 frames suivantes : une va passer dès que le serveur
    -- accepte la position (battre les autres joueurs qui arrivent au même moment)
    task.spawn(function()
        for _ = 1, 4 do
            _stealServices.RunService.Heartbeat:Wait()
            if not prompt or not prompt.Parent then break end
            pcall(function() fireproximityprompt(prompt) end)
        end
    end)

    data.ready          = true
    _stealIsBusy        = false
    _stealCooldownUntil = tick() + 1.5
    _G.PriorityStealActive = false
    _stealResetBar()
    _watchAndEquip(_snap)
end

-- ── Nearest brainrot helper for bar title (uses hub animal cache) ─────────
local function _FH_AG_GetNearestBrainrot()
    local hrp = _stealGetHRP()
    if not hrp then return nil, math.huge end
    local best, bestDist = nil, math.huge
    for _, a in ipairs(_stealAnimalsCache) do
        local plotsWS = workspace:FindFirstChild("Plots")
        local plot    = plotsWS and plotsWS:FindFirstChild(a.plot)
        local pods    = plot and plot:FindFirstChild("AnimalPodiums")
        local pod     = pods and pods:FindFirstChild(a.slot)
        local base    = pod and pod:FindFirstChild("Base")
        local spwn    = base and base:FindFirstChild("Spawn")
        if spwn then
            local d = (spwn.Position - hrp.Position).Magnitude
            if d < bestDist then
                bestDist = d
                best = { displayName = a.name, genText = a.genText }
            end
        end
    end
    return best, bestDist
end

-- ── HUB PVP FH_AutoGrabProgress bar (exact from HUB PVP) ─────────────────
local TweenService = _stealServices.TweenService
local RunService   = _stealServices.RunService
local UIS          = game:GetService("UserInputService")
task.defer(function()
    local gui = Instance.new("ScreenGui")
    gui.Name           = "FH_AutoGrabProgress"
    gui.ResetOnSpawn   = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = 9999
    local guiOk = pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not guiOk or not gui.Parent then
        pcall(function() if gethui then gui.Parent = gethui() end end)
    end
    if not gui.Parent then gui.Parent = _stealLocalPlayer:WaitForChild("PlayerGui") end
    if protect_gui then pcall(function() protect_gui(gui) end) end

    local frame = Instance.new("Frame")
    frame.Name                   = "AutoGrabBar"
    frame.Size                   = UDim2.new(0, 200, 0, 50)
    frame.AnchorPoint            = Vector2.new(0.5, 0)
    do
        local vp = workspace.CurrentCamera.ViewportSize
        frame.Position = UDim2.new(0, math.floor(vp.X / 2), 0, math.floor(vp.Y * 0.82))
    end
    frame.BackgroundColor3       = Color3.fromRGB(18, 18, 22)
    frame.BackgroundTransparency = 0.05
    frame.BorderSizePixel        = 0
    frame.ClipsDescendants       = false
    frame.Visible                = false
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local fs = Instance.new("UIStroke", frame)
    fs.Color        = Color3.fromRGB(255, 255, 255)
    fs.Transparency = 0.55
    fs.Thickness    = 1
    frame.Parent = gui

    -- draggable
    local dragging, dragStart, startPos = false, nil, nil
    frame.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = inp.Position
            startPos  = frame.Position
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    local title = Instance.new("TextLabel", frame)
    title.Name                   = "Title"
    title.Size                   = UDim2.new(1, -8, 0, 20)
    title.Position               = UDim2.new(0, 4, 0, 1)
    title.BackgroundTransparency = 1
    title.Text                   = "Auto Grab (searching)"
    title.TextSize               = 11
    title.Font                   = Enum.Font.GothamBold
    title.TextColor3             = Color3.fromRGB(235, 235, 235)
    title.TextXAlignment         = Enum.TextXAlignment.Left
    title.TextTruncate           = Enum.TextTruncate.AtEnd
    title.ZIndex                 = 2

    local div = Instance.new("Frame", frame)
    div.Name                   = "Divider"
    div.Size                   = UDim2.new(1, -8, 0, 1)
    div.Position               = UDim2.new(0, 4, 0, 21)
    div.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
    div.BackgroundTransparency = 0.85
    div.BorderSizePixel        = 0
    div.ZIndex                 = 2

    local track = Instance.new("Frame", frame)
    track.Name                   = "Track"
    track.Size                   = UDim2.new(1, -8, 0, 18)
    track.Position               = UDim2.new(0, 4, 1, -22)
    track.AnchorPoint            = Vector2.new(0, 0)
    track.BackgroundColor3       = Color3.fromRGB(35, 35, 40)
    track.BackgroundTransparency = 0
    track.BorderSizePixel        = 0
    track.ClipsDescendants       = true
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 6)
    local ts = Instance.new("UIStroke", track)
    ts.Color        = Color3.fromRGB(255, 255, 255)
    ts.Transparency = 0.75
    ts.Thickness    = 1

    local fill = Instance.new("Frame", track)
    fill.Name                   = "Fill"
    fill.Size                   = UDim2.new(0, 0, 1, 0)
    fill.AnchorPoint            = Vector2.new(0, 0.5)
    fill.Position               = UDim2.new(0, 0, 0.5, 0)
    fill.BackgroundColor3       = Color3.fromRGB(60, 210, 100)
    fill.BorderSizePixel        = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 8)
    local grad = Instance.new("UIGradient", fill)
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200,200,200))
    })
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(1, 0.35)
    })

    local pctLbl = Instance.new("TextLabel", track)
    pctLbl.Name                   = "PctLabel"
    pctLbl.AnchorPoint            = Vector2.new(0, 0)
    pctLbl.Position               = UDim2.new(0, 4, 0, 0)
    pctLbl.Size                   = UDim2.new(1, -8, 1, 0)
    pctLbl.BackgroundTransparency = 1
    pctLbl.Text                   = "0%"
    pctLbl.TextSize               = 10
    pctLbl.Font                   = Enum.Font.GothamBold
    pctLbl.TextColor3             = Color3.fromRGB(245, 245, 245)
    pctLbl.TextStrokeTransparency = 0.5
    pctLbl.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
    pctLbl.ZIndex                 = 3

    _G._FH_HideAutoGrabBar = _G._FH_HideAutoGrabBar or false
    local fillTween  = nil
    local lastTweenP = -1
    local _agBarTimer = 0
    RunService.Heartbeat:Connect(function(dt)
        _agBarTimer = _agBarTimer + dt
        if _agBarTimer < 0.033 then return end
        _agBarTimer = 0
        local on = _stealEnabled and not _G._FH_HideAutoGrabBar
        frame.Visible = on
        if not on then return end
        local p = math.clamp(v1Progress or 0, 0, 1)
        if math.abs(p - lastTweenP) > 0.005 then
            lastTweenP = p
            if fillTween then pcall(function() fillTween:Cancel() end) end
            fillTween = TweenService:Create(
                fill,
                TweenInfo.new(0.12, Enum.EasingStyle.Linear),
                { Size = UDim2.new(p, 0, 1, 0) }
            )
            fillTween:Play()
        end
        if p >= 0.5 then
            fill.BackgroundColor3 = Color3.fromRGB(60, 230, 100)
        else
            fill.BackgroundColor3 = Color3.fromRGB(230, 70, 70)
        end
        pctLbl.Text = string.format("%d%%", math.floor(p * 100 + 0.5))
        if p >= 0.55 then
            pctLbl.TextColor3             = Color3.fromRGB(20, 20, 20)
            pctLbl.TextStrokeTransparency = 0.85
        else
            pctLbl.TextColor3             = Color3.fromRGB(245, 245, 245)
            pctLbl.TextStrokeTransparency = 0.5
        end
        if v1HasTarget and v1TargetName ~= "" then
            if v1TargetRate ~= "" then
                title.Text = v1TargetName .. " - " .. v1TargetRate
            else
                title.Text = v1TargetName
            end
        else
            local nearest, nearestDist = _FH_AG_GetNearestBrainrot()
            if nearest then
                local nm   = tostring(nearest.displayName or "")
                if nm == "" then nm = "Brainrot" end
                local rate = tostring(nearest.genText or "")
                if rate:sub(1, 1) == "$" then rate = rate:sub(2) end
                if rate ~= "" then
                    title.Text = string.format("Nearest: %s (%dm) - %s", nm, math.floor(nearestDist or 0 + 0.5), rate)
                else
                    title.Text = string.format("Nearest: %s (%dm)", nm, math.floor(nearestDist or 0 + 0.5))
                end
            else
                title.Text = "NO ANIMALS NEARBY"
            end
        end
    end)
end)


-- ============================================================
-- STEAL TARGET GUI (PanelViewUI – pet list + mode buttons)
-- ============================================================
pcall(function()
    local TextService = game:GetService("TextService")

    local _stGui = Instance.new("ScreenGui")
    _stGui.Name           = "PanelViewUI"
    _stGui.ResetOnSpawn   = false
    _stGui.DisplayOrder   = 999999
    _stGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local _stGuiOk = pcall(function() _stGui.Parent = game:GetService("CoreGui") end)
    _G.UIHide_StealTarget = _stGui
    if not _stGuiOk or not _stGui.Parent then
        pcall(function() if gethui then _stGui.Parent = gethui() end end)
    end
    if not _stGui.Parent then _stGui.Parent = _stealLocalPlayer:WaitForChild("PlayerGui") end
    if protect_gui then pcall(function() protect_gui(_stGui) end) end

    local MAX_ROWS   = 14
    local ROW_H      = 26
    local ROW_GAP    = 3
    local PAD        = 8
    local MODE_BAR_H = 26
    local HEADER_H   = 52
    local FRAME_W    = 340
    local SEP        = 1
    local FRAME_H    = PAD + HEADER_H + SEP + MODE_BAR_H + PAD/2 + MAX_ROWS * (ROW_H + ROW_GAP) + PAD

    -- ── Main container (single rounded rectangle) ──────────────────────────
    local _stFrame = Instance.new("Frame")
    _stFrame.Size                   = UDim2.new(0, FRAME_W, 0, FRAME_H)
    _stFrame.Position               = UDim2.new(0, 5, 0, 95)
    _stFrame.BackgroundColor3       = Color3.fromRGB(10, 12, 20)
    _stFrame.BackgroundTransparency = 0.75
    _stFrame.BorderSizePixel        = 0
    _stFrame.ZIndex                 = 50
    _stFrame.Parent                 = _stGui
    if not _G._hubPanelFrames then _G._hubPanelFrames={} end; table.insert(_G._hubPanelFrames, _stFrame)

    do
        local _sdSTF={{0.92,0.234,3,0.0036},{0.437,0.134,3,0.0048},{0.395,0.831,3,0.0037},{0.816,0.173,2,0.0036},{0.737,0.703,3,0.0057},{0.687,0.094,2,0.0037},{0.533,0.268,2,0.005},{0.097,0.37,2,0.006},{0.497,0.756,2,0.0043},{0.149,0.564,2,0.0056},{0.532,0.656,2,0.0055},{0.535,0.106,3,0.0052},{0.322,0.159,2,0.0038},{0.587,0.621,3,0.0037},{0.889,0.829,2,0.0049},{0.695,0.452,2,0.0037},{0.663,0.106,2,0.0039},{0.483,0.081,3,0.0057},{0.089,0.109,2,0.006},{0.962,0.144,3,0.0064},{0.72,0.242,2,0.0047},{0.046,0.218,3,0.0049},{0.351,0.077,2,0.0064},{0.708,0.581,3,0.0063},{0.114,0.093,2,0.0061},{0.646,0.461,3,0.0053},{0.271,0.48,2,0.0055},{0.832,0.258,2,0.0038},{0.331,0.454,2,0.0052},{0.183,0.416,3,0.006}}
        local _sfSTF,_soSTF={},{}
        for i,sp in ipairs(_sdSTF) do
            local s=Instance.new("Frame",_stFrame)
            s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
            s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.3
            s.BorderSizePixel=0;s.ZIndex=51
            Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
            _sfSTF[i]=s;_soSTF[i]=sp[1]
            if not _G._hubStars then _G._hubStars={} end
            table.insert(_G._hubStars, s)
        end
        game:GetService("RunService").Heartbeat:Connect(function(dt)
            for i,s in ipairs(_sfSTF) do
                if not s or not s.Parent then continue end
                _soSTF[i]=(_soSTF[i]-_sdSTF[i][4]*dt)%1
                s.Position=UDim2.new(_soSTF[i],0,_sdSTF[i][2],0)
                s.BackgroundTransparency=0.3+math.abs(math.sin(tick()*0.8+i*0.7))*0.5
            end
        end)
    end
    Instance.new("UICorner", _stFrame).CornerRadius = UDim.new(0, 10)
    local _stMainStroke = Instance.new("UIStroke", _stFrame)
    if not _G._hubPanelStrokes then _G._hubPanelStrokes = {} end
    table.insert(_G._hubPanelStrokes, _stMainStroke)
    _stMainStroke.Color = Color3.fromRGB(255, 0, 220); _stMainStroke.Thickness = 2
    makeDraggable(_stFrame, "StealTargetPanel", _stFrame)
    -- makeResizable(_stFrame, 180, 80)
    _G._stFrame = _stFrame
    pcall(addGlowBorder, _stFrame)

    -- ── Header row ─────────────────────────────────────────────────────────
    local _stHeader = Instance.new("Frame", _stFrame)
    _stHeader.Size                   = UDim2.new(1, 0, 0, HEADER_H)
    _stHeader.Position               = UDim2.new(0, 0, 0, PAD/2)
    _stHeader.BackgroundTransparency = 1
    _stHeader.ZIndex                 = 51

    local _stTitleMain = Instance.new("TextLabel", _stHeader)
    _stTitleMain.Size                   = UDim2.new(1, -16, 0, 28)
    _stTitleMain.Position               = UDim2.new(0, 8, 0, 4)
    _stTitleMain.BackgroundTransparency = 1
    _stTitleMain.Text                   = "IDF HUB"
    _stTitleMain.Font                   = Enum.Font.GothamBlack
    _stTitleMain.TextColor3             = Color3.fromRGB(255, 255, 255)
    _stTitleMain.TextSize               = 18
    _stTitleMain.TextXAlignment         = Enum.TextXAlignment.Center
    _stTitleMain.ZIndex                 = 52
    local _stTitle = Instance.new("TextLabel", _stHeader)
    _stTitle.Size                   = UDim2.new(1, -16, 0, 16)
    _stTitle.Position               = UDim2.new(0, 8, 0, 32)
    _stTitle.BackgroundTransparency = 1
    _stTitle.Text                   = "Steal Target"
    _stTitle.Font                   = Enum.Font.Gotham
    _stTitle.TextColor3             = Color3.fromRGB(180, 180, 180)
    _stTitle.TextSize               = 11
    _stTitle.TextXAlignment         = Enum.TextXAlignment.Center
    _stTitle.ZIndex                 = 52
    local _stSepLine = Instance.new("Frame", _stHeader)
    _stSepLine.Size = UDim2.new(1, -20, 0, 1); _stSepLine.Position = UDim2.new(0, 10, 1, -1)
    _stSepLine.BackgroundColor3 = Color3.fromRGB(255,255,255); _stSepLine.BackgroundTransparency = 0.7
    _stSepLine.BorderSizePixel = 0; _stSepLine.ZIndex = 53
    local _stTitleStroke = {ApplyStrokeMode=0}  -- dummy

do
    local _sdST={{0.408,0.211,2,0.0051},{0.956,0.142,1,0.011},{0.745,0.446,2,0.0129},{0.881,0.651,1,0.0102},{0.803,0.624,1,0.0074},{0.116,0.775,2,0.0124},{0.736,0.56,1,0.0114},{0.168,0.763,1,0.0106},{0.256,0.633,2,0.0059},{0.397,0.481,1,0.0069},{0.227,0.77,1,0.0063},{0.054,0.867,1,0.0104},{0.753,0.874,3,0.0107},{0.595,0.492,2,0.0098}}
    local _sfST,_soST={},{}
    for i,sp in ipairs(_sdST) do
        local s=Instance.new("Frame",_stTitle)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.2
        s.BorderSizePixel=0;s.ZIndex=53
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfST[i]=s;_soST[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfST) do
            if not s or not s.Parent then continue end
            _soST[i]=(_soST[i]-_sdST[i][4]*dt)%1
            s.Position=UDim2.new(_soST[i],0,_sdST[i][2],0)
            s.BackgroundTransparency=0.3+math.abs(math.sin(tick()*0.8+i*0.7))*0.5
        end
    end)
end

    local _stMinimized = false
    local _stMinBtn = Instance.new("TextButton", _stHeader)
    _stMinBtn.Size                   = UDim2.new(0, 44, 0, 20)
    _stMinBtn.Position               = UDim2.new(0, PAD + 4, 0.5, -10)
    _stMinBtn.BackgroundColor3       = Color3.fromRGB(14, 14, 22)
    _stMinBtn.BackgroundTransparency = 0
    _stMinBtn.BorderSizePixel        = 0
    _stMinBtn.Text                   = "min"
    _stMinBtn.Font                   = Enum.Font.GothamBold
    _stMinBtn.TextColor3             = Color3.fromRGB(255, 40, 160)
    _stMinBtn.TextSize               = 10
    _stMinBtn.AutoButtonColor        = false
    _stMinBtn.ZIndex                 = 54
    _stMinBtn.Visible = false
    Instance.new("UICorner", _stMinBtn).CornerRadius = UDim.new(1, 0)
    local _minStroke = Instance.new("UIStroke", _stMinBtn)
    _minStroke.Color = Color3.fromRGB(255, 40, 160); _minStroke.Thickness = 1

    local _stUntargetFrame = Instance.new("Frame", _stHeader)
    _stUntargetFrame.Size             = UDim2.new(0, 80, 0, 24)
    _stUntargetFrame.Visible          = false
    _stUntargetFrame.Position         = UDim2.new(1, -PAD - 80, 0.5, -12)
    _stUntargetFrame.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
    _stUntargetFrame.BorderSizePixel  = 0
    _stUntargetFrame.ZIndex           = 52
    Instance.new("UICorner", _stUntargetFrame).CornerRadius = UDim.new(1, 0)
    local _utStroke = Instance.new("UIStroke", _stUntargetFrame)
    _utStroke.Color = Color3.fromRGB(255, 40, 160); _utStroke.Thickness = 1

    local _stUntargetBtn = Instance.new("TextButton", _stUntargetFrame)
    _stUntargetBtn.Size                   = UDim2.new(1, 0, 1, 0)
    _stUntargetBtn.BackgroundTransparency = 1
    _stUntargetBtn.Text                   = "Untarget"
    _stUntargetBtn.Font                   = Enum.Font.GothamBold
    _stUntargetBtn.TextColor3             = Color3.fromRGB(255, 40, 160)
    _stUntargetBtn.TextSize               = 11
    _stUntargetBtn.AutoButtonColor        = false
    _stUntargetBtn.ZIndex                 = 53

    -- Separator line under header
    local _stSep = Instance.new("Frame", _stFrame)
    _stSep.Size                   = UDim2.new(1, -PAD*2, 0, 1)
    _stSep.Position               = UDim2.new(0, PAD, 0, PAD/2 + HEADER_H)
    _stSep.BackgroundColor3       = Color3.fromRGB(30, 35, 60)
    _stSep.BorderSizePixel        = 0
    _stSep.ZIndex                 = 51

    -- ── Mode buttons bar ───────────────────────────────────────────────────
    local MODE_BTN_GAP = 5
    local _modeBar = Instance.new("Frame", _stFrame)
    _modeBar.Size                   = UDim2.new(1, -PAD*2, 0, MODE_BAR_H)
    _modeBar.Position               = UDim2.new(0, PAD, 0, PAD/2 + HEADER_H + SEP + 4)
    _modeBar.BackgroundTransparency = 1
    _modeBar.ZIndex                 = 51
    local _modeLayout = Instance.new("UIListLayout", _modeBar)
    _modeLayout.FillDirection       = Enum.FillDirection.Horizontal
    _modeLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    _modeLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
    _modeLayout.SortOrder           = Enum.SortOrder.LayoutOrder
    _modeLayout.Padding             = UDim.new(0, MODE_BTN_GAP)

    local function makeModeBtn(text, order)
        local btn = Instance.new("TextButton", _modeBar)
        btn.Size                   = UDim2.new(1/3, -(MODE_BTN_GAP*2/3+1), 1, 0)
        btn.BackgroundColor3       = Color3.fromRGB(14, 14, 22)
        btn.BackgroundTransparency = 0
        btn.BorderSizePixel        = 0
        btn.Text                   = text
        btn.Font                   = Enum.Font.GothamBold
        btn.TextSize               = 10
        btn.TextColor3             = Color3.fromRGB(255, 255, 255)
        btn.AutoButtonColor        = false
        btn.LayoutOrder            = order
        btn.ZIndex                 = 52
        Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
        local stroke = Instance.new("UIStroke", btn)
        stroke.Color = Color3.fromRGB(30, 35, 60); stroke.Thickness = 1
        return btn, stroke
    end

    local _btnNearest,  _strokeNearest  = makeModeBtn("NEAREST",  1)
    local _btnHighest,  _strokeHighest  = makeModeBtn("HIGHEST",  2)
    local _btnPriority, _strokePriority = makeModeBtn("PRIORITY", 3)

    local ACTIVE_BG    = Color3.fromRGB(255, 40, 160)
    local INACTIVE_BG  = Color3.fromRGB(14, 14, 22)
    local ACTIVE_TEXT  = Color3.fromRGB(8, 10, 18)
    local INACTIVE_TEXT = Color3.fromRGB(255, 255, 255)
    local ACTIVE_STROKE = Color3.fromRGB(235, 185, 20)
    local INACTIVE_STROKE = Color3.fromRGB(30, 35, 60)

    local function paintModeBtn(btn, stroke, active)
        btn.BackgroundColor3 = active and (_G._hubThemeColor or ACTIVE_BG) or INACTIVE_BG
        btn.TextColor3       = active and ACTIVE_TEXT or INACTIVE_TEXT
        stroke.Color         = active and ACTIVE_STROKE or INACTIVE_STROKE
    end

    local function refreshModeBtns()
        paintModeBtn(_btnNearest,  _strokeNearest,  StealConfig.StealNearest)
        paintModeBtn(_btnHighest,  _strokeHighest,  StealConfig.StealHighest)
        paintModeBtn(_btnPriority, _strokePriority, StealConfig.StealPriority)
    end

    _btnNearest.MouseButton1Click:Connect(function()
        _G.StealSetMode(true, false, false)
        refreshModeBtns()
    end)
    _btnHighest.MouseButton1Click:Connect(function()
        _G.StealSetMode(false, true, false)
        refreshModeBtns()
    end)
    _btnPriority.MouseButton1Click:Connect(function()
        _G.StealSetMode(false, false, true)
        refreshModeBtns()
    end)
    refreshModeBtns()

    -- ── Pet list rows ──────────────────────────────────────────────────────
    local INDIGO_PURPLE = Color3.fromRGB(60, 30, 160)
    local SAPPHIRE_BLUE = Color3.fromRGB(10, 55, 140)
    local PRIORITY_BRAINROT_COLORS = {
        ["Strawberry Elephant"] = INDIGO_PURPLE,
        ["Meowl"]               = INDIGO_PURPLE,
        ["Headless Horseman"]   = INDIGO_PURPLE,
        ["Skibidi Toilet"]      = INDIGO_PURPLE,
        ["Signore Caraprace"]   = INDIGO_PURPLE,
        ["Signore Carapace"]    = INDIGO_PURPLE,
    }
    local SAPPHIRE_BRAINROT_COLORS = {
        ["Dragon Gingerini"]        = SAPPHIRE_BLUE,
        ["Griffin"]                 = SAPPHIRE_BLUE,
        ["Dragon Cannelloni"]       = SAPPHIRE_BLUE,
        ["Love Love Bear"]          = SAPPHIRE_BLUE,
        ["La Supreme Combinasion"]  = SAPPHIRE_BLUE,
        ["Antonio"]                 = SAPPHIRE_BLUE,
        ["Ginger Gerat"]            = SAPPHIRE_BLUE,
        ["Elefanto Frigo"]          = SAPPHIRE_BLUE,
        ["Ketupat Bros"]            = SAPPHIRE_BLUE,
        ["Dug Dug Dug"]             = SAPPHIRE_BLUE,
        ["Dug dug dug"]             = SAPPHIRE_BLUE,
        ["Hydra Dragon Cannelloni"] = SAPPHIRE_BLUE,
        ["Hydra Bunny"]             = SAPPHIRE_BLUE,
    }
    local ST_MUTATION_COLORS = {
        ["Diamond"]     = Color3.fromRGB(135, 206, 235),
        ["Candy"]       = Color3.fromRGB(255, 182, 193),
        ["Gold"]        = Color3.fromRGB(255, 223, 0),
        ["Bloodrot"]    = Color3.fromRGB(255, 0,   0),
        ["Radioactive"] = Color3.fromRGB(0,   255, 0),
        ["Lava"]        = Color3.fromRGB(255, 140, 0),
        ["Galaxy"]      = Color3.fromRGB(138, 43,  226),
        ["Divine"]      = Color3.fromRGB(255, 253, 208),
        ["Cyber"]       = Color3.fromRGB(0,   255, 255),
        ["Normal"]      = Color3.fromRGB(200, 200, 200),
    }

    local function isPriorityBrainrot(name) return PRIORITY_BRAINROT_COLORS[name] ~= nil end
    local function isSapphireBrainrot(name) return SAPPHIRE_BRAINROT_COLORS[name] ~= nil end

    local function colorToHex(c)
        return string.format("#%02X%02X%02X", math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255))
    end

    local function formatMutationText(mutation)
        if not mutation or mutation == "Normal" or mutation == "None" then return "" end
        if mutation == "Cursed" then
            return '<font color="#FF2020">C</font><font color="#DD1010">u</font><font color="#BB0808">r</font><font color="#880000">s</font><font color="#550000">e</font><font color="#330000">d</font>  '
        elseif mutation == "YinYang" then
            return '<font color="#FFFFFF">Y</font><font color="#DDDDDD">i</font><font color="#BBBBBB">n</font><font color="#444444">Y</font><font color="#222222">a</font><font color="#111111">n</font><font color="#000000">g</font>  '
        elseif mutation == "Rainbow" then
            return '<font color="#FF3030">R</font><font color="#FF8822">a</font><font color="#FFD700">i</font><font color="#22DD22">n</font><font color="#3388FF">b</font><font color="#9944FF">o</font><font color="#FF44AA">w</font>  '
        elseif mutation == "Galaxy" then
            return '<font color="#6B1FCC">G</font><font color="#7B33DD">a</font><font color="#9955EE">l</font><font color="#BB77FF">a</font><font color="#9955EE">x</font><font color="#7B33DD">y</font>  '
        elseif mutation == "Lava" then
            return '<font color="#FF4400">L</font><font color="#FF6600">a</font><font color="#FF8800">v</font><font color="#FFAA00">a</font>  '
        elseif mutation == "Gold" then
            return '<font color="#FFD700">G</font><font color="#FFCC00">o</font><font color="#FFB800">l</font><font color="#FFA500">d</font>  '
        elseif mutation == "Diamond" then
            return '<font color="#00CCFF">D</font><font color="#22DDFF">i</font><font color="#44EEFF">a</font><font color="#66F5FF">m</font><font color="#44EEFF">o</font><font color="#22DDFF">n</font><font color="#00BBFF">d</font>  '
        elseif mutation == "Radioactive" then
            return '<font color="#00FF00">R</font><font color="#22FF22">a</font><font color="#00DD00">d</font><font color="#00BB00">i</font><font color="#00FF00">o</font><font color="#33FF33">a</font><font color="#00DD00">c</font><font color="#00BB00">t</font><font color="#00FF00">i</font><font color="#22FF22">v</font><font color="#00DD00">e</font>  '
        elseif mutation == "Candy" then
            return '<font color="#FF69B4">C</font><font color="#FF88CC">a</font><font color="#FF55AA">n</font><font color="#FF3399">d</font><font color="#FF69B4">y</font>  '
        elseif mutation == "Bloodrot" then
            return '<font color="#FF0000">B</font><font color="#DD0000">l</font><font color="#FF2222">o</font><font color="#CC0000">o</font><font color="#FF0000">d</font><font color="#BB0000">r</font><font color="#DD0000">o</font><font color="#FF1111">t</font>  '
        elseif mutation == "Divine" then
            return '<font color="#FFFACD">D</font><font color="#FFF8B0">i</font><font color="#FFF5A0">v</font><font color="#FFF8B0">i</font><font color="#FFFACD">n</font><font color="#FFFDE0">e</font>  '
        else
            local col = ST_MUTATION_COLORS[mutation]
            if col then return '<font color="'..colorToHex(col)..'">'..mutation..'</font>  ' end
            return '<font color="#CCCCCC">'..mutation..'</font>  '
        end
    end

    -- Glisten shimmer
    local _stGlistenGrads = {}
    local function stCreateGlisten(parent, baseColor)
        local ex = parent:FindFirstChild("_BoxShine")
        if ex then
            ex.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0,    baseColor),
                ColorSequenceKeypoint.new(0.42, baseColor),
                ColorSequenceKeypoint.new(0.48, Color3.new(1,1,1)),
                ColorSequenceKeypoint.new(0.52, Color3.new(1,1,1)),
                ColorSequenceKeypoint.new(0.58, baseColor),
                ColorSequenceKeypoint.new(1,    baseColor),
            })
            return ex
        end
        local g = Instance.new("UIGradient")
        g.Name  = "_BoxShine"
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,    baseColor),
            ColorSequenceKeypoint.new(0.42, baseColor),
            ColorSequenceKeypoint.new(0.48, Color3.new(1,1,1)),
            ColorSequenceKeypoint.new(0.52, Color3.new(1,1,1)),
            ColorSequenceKeypoint.new(0.58, baseColor),
            ColorSequenceKeypoint.new(1,    baseColor),
        })
        g.Parent = parent
        _stGlistenGrads[g] = true
        return g
    end
    local function stRemoveGlisten(parent)
        local ex = parent:FindFirstChild("_BoxShine")
        if ex then _stGlistenGrads[ex] = nil; ex:Destroy() end
    end

    do local _glF = 0
    _stealServices.RunService.Heartbeat:Connect(function()
        _glF = _glF + 1; if _glF < 2 then return end; _glF = 0
        local offset = Vector2.new(-1.2 + (tick() * 1.2 % 2.4), 0)
        for grad in pairs(_stGlistenGrads) do
            if grad and grad.Parent then grad.Offset = offset
            else _stGlistenGrads[grad] = nil end
        end
    end) end

    local _numberGrey = colorToHex(Color3.fromRGB(128, 128, 128))
    local _nameWhite  = colorToHex(Color3.fromRGB(255, 255, 255))
    local _moneyGreen = colorToHex(Color3.fromRGB(100, 255, 100))

    local _stButtons   = {}
    local _stRichLbls  = {}
    local _stOwnerLbls = {}

    local LIST_START_Y = PAD/2 + HEADER_H + SEP + 4 + MODE_BAR_H + PAD/2

    for i = 1, MAX_ROWS do
        local b = Instance.new("TextButton", _stFrame)
        b.Size                   = UDim2.new(0, FRAME_W - PAD*2, 0, ROW_H)
        b.Position               = UDim2.new(0, PAD, 0, LIST_START_Y + (i-1) * (ROW_H + ROW_GAP))
        b.Text                   = ""
        b.Font                   = Enum.Font.GothamBold
        b.TextSize               = 10
        b.BackgroundColor3       = Color3.fromRGB(10, 12, 20)
        b.BackgroundTransparency = 0.15
        b.BorderSizePixel        = 0
        b.TextColor3             = Color3.fromRGB(220, 200, 140)
        b.AutoButtonColor        = false
        b.TextXAlignment         = Enum.TextXAlignment.Left
        b.TextTruncate           = Enum.TextTruncate.AtEnd
        b.ZIndex                 = 51
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        local _bStroke = Instance.new("UIStroke", b)
        _bStroke.Color = Color3.fromRGB(255, 0, 220); _bStroke.Thickness = 0.5; _bStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

        local rl = Instance.new("TextLabel", b)
        rl.Size                   = UDim2.new(0.6, 0, 1, 0)
        rl.Position               = UDim2.new(0, 5, 0, 0)
        rl.BackgroundTransparency = 1
        rl.Font                   = Enum.Font.GothamBold
        rl.TextSize               = 10
        rl.TextColor3             = Color3.fromRGB(200, 200, 200)
        rl.TextXAlignment         = Enum.TextXAlignment.Left
        rl.TextTruncate           = Enum.TextTruncate.AtEnd
        rl.RichText               = true
        rl.Text                   = ""
        rl.ZIndex                 = 52

        local ol = Instance.new("TextLabel", b)
        ol.Size                   = UDim2.new(0.38, -4, 1, 0)
        ol.Position               = UDim2.new(0.62, 0, 0, 0)
        ol.BackgroundTransparency = 1
        ol.Font                   = Enum.Font.Gotham
        ol.TextSize               = 9
        ol.TextColor3             = Color3.fromRGB(255, 40, 160)
        ol.TextXAlignment         = Enum.TextXAlignment.Right
        ol.TextTruncate           = Enum.TextTruncate.AtEnd
        ol.Text                   = ""
        ol.ZIndex                 = 52
        ol.Visible = false

        local capturedI = i
        b.MouseButton1Click:Connect(function()
            local pets = _stealGetFilteredPets()
            local pet  = pets[capturedI]
            if pet then
                _stealManualUID = pet.uid
                StealConfig.StealNearest  = false
                StealConfig.StealHighest  = false
                StealConfig.StealPriority = false
                saveStealConfig()
                refreshModeBtns()
            end
        end)

        _stButtons[i]   = b
        _stRichLbls[i]  = rl
        _stOwnerLbls[i] = ol
    end

    local MIN_FRAME_H = PAD + HEADER_H + PAD/2
    local function applyStealMinimized()
        _stSep.Visible = not _stMinimized
        _modeBar.Visible = not _stMinimized
        for i = 1, MAX_ROWS do
            _stButtons[i].Visible = not _stMinimized
        end
        _stMinBtn.Text = _stMinimized and "max" or "min"
        _stFrame.Size = UDim2.new(0, _stFrame.AbsoluteSize.X, 0, _stMinimized and MIN_FRAME_H or FRAME_H)
    end

    _stMinBtn.MouseButton1Click:Connect(function()
        _stMinimized = not _stMinimized
        applyStealMinimized()
    end)

    -- ── Untarget logic ─────────────────────────────────────────────────────
    _stUntargetBtn.MouseButton1Click:Connect(function()
        _stealManualUID = nil
        -- Default back to Highest mode
        _G.StealSetMode(false, true, false)
        refreshModeBtns()
    end)

    -- ── UI update loop ─────────────────────────────────────────────────────
    local lastUIUpdate     = 0
    local UI_UPDATE_INTERVAL = 0.08

    _stealServices.RunService.Heartbeat:Connect(function()
        local now = os.clock()
        if now - lastUIUpdate < UI_UPDATE_INTERVAL then return end
        lastUIUpdate = now

        local pets      = _stealGetFilteredPets()
        local activeUID = _stealManualUID
        if not activeUID and #pets > 0 then
            -- reflect what engine would pick
            local t = _stealGetActiveTarget()
            if t then activeUID = t.uid end
        end

        -- Resize frame width to fit longest entry
        local maxNeededWidth = 280
        for i = 1, MAX_ROWS do
            local pet = pets[i]
            if pet then
                local mutPlain = (pet.mutation ~= "Normal" and pet.mutation ~= "None" and pet.mutation ~= "")
                                 and (pet.mutation .. " ") or ""
                local plain = "#"..i..": "..mutPlain..pet.name.." "..pet.genText
                local sz    = TextService:GetTextSize(plain, 11, Enum.Font.GothamBold, Vector2.new(9999, 30))
                local needed = sz.X + 35
                if needed > maxNeededWidth then maxNeededWidth = needed end
            end
        end
        local newW = math.min(math.max(maxNeededWidth, 280), 400)
        _stFrame.Size = UDim2.new(0, newW, 0, _stMinimized and MIN_FRAME_H or FRAME_H)
        for i = 1, MAX_ROWS do
            _stButtons[i].Size = UDim2.new(0, newW - 20, 0, ROW_H)
        end

        for i = 1, MAX_ROWS do
            local pet = pets[i]
            if pet then
                local mutText = formatMutationText(pet.mutation)
                _stRichLbls[i].Text =
                    '<font color="'..  _numberGrey ..'">#'.. i ..':</font> '
                    .. mutText
                    .. '<font color="'.. _nameWhite  ..'">'.. pet.name    ..'</font>  '
                    .. '<font color="'.. _moneyGreen ..'">'.. pet.genText ..'</font>'
                _stOwnerLbls[i].Text = "@" .. (pet.owner or "?")
            else
                _stRichLbls[i].Text  = ""
                _stOwnerLbls[i].Text = ""
            end

            local sel = pet and activeUID and pet.uid == activeUID
            if sel then
                _stButtons[i].BackgroundColor3       = Color3.fromRGB(0, 100, 0)
                _stButtons[i].BackgroundTransparency = 0.3
                stRemoveGlisten(_stButtons[i])
            elseif pet and isPriorityBrainrot(pet.name) then
                _stButtons[i].BackgroundColor3       = INDIGO_PURPLE
                _stButtons[i].BackgroundTransparency = 0.3
                stCreateGlisten(_stButtons[i], INDIGO_PURPLE)
            elseif pet and isSapphireBrainrot(pet.name) then
                _stButtons[i].BackgroundColor3       = SAPPHIRE_BLUE
                _stButtons[i].BackgroundTransparency = 0.3
                stCreateGlisten(_stButtons[i], SAPPHIRE_BLUE)
            else
                _stButtons[i].BackgroundColor3       = Color3.fromRGB(0, 0, 0)
                _stButtons[i].BackgroundTransparency = 0.5
                stRemoveGlisten(_stButtons[i])
            end
        end
    end)
end)

-- ============================================================
-- SCANNER INIT (deferred, same as new file)
-- ============================================================
task.defer(function()
    if not _loadStealModules() then return end
    _stealDetectMyPlot()
    local plots = workspace:WaitForChild("Plots", 10)
    if not plots then return end
    local function setupPlot(plot)
        _stealScanPlot(plot)
        plot.DescendantAdded:Connect(function()   task.wait(0.1); _stealScanPlot(plot) end)
        plot.DescendantRemoving:Connect(function() task.wait(0.1); _stealScanPlot(plot) end)
    end
    for _, p in ipairs(plots:GetChildren()) do task.spawn(setupPlot, p) end
    plots.ChildAdded:Connect(function(p)   task.wait(0.3); setupPlot(p) end)
    plots.ChildRemoved:Connect(function(p) _stealClearPlot(p.Name) end)
    task.spawn(function()
        while true do
            task.wait(2)
            if not _stealMyPlotName then _stealDetectMyPlot() end
            for _, p in ipairs(plots:GetChildren()) do _stealScanPlot(p) end
        end
    end)
    -- Auto-enable steal if hub toggle is on
    if _G._autoStealSettingOn ~= false then
        _stealEnabled = true
    end
    _G._StealTargetScanReady = true
end)

-- ============================================================
-- GLOBAL API (hub toggle + TP section compatibility)
-- ============================================================
_G.AutoStealDisable = function()
    _stealEnabled = false
    _G.PriorityStealActive = false
end

_G.AutoStealEnable = function()
    _stealEnabled = true
end

_G.AutoStealGetSelectedTarget = function()
    return _stealGetActiveTarget()
end

-- Mode setters for hub panel (mode buttons if kept, or future use)
_G.StealSetMode = function(nearest, highest, priority)
    StealConfig.StealNearest  = nearest
    StealConfig.StealHighest  = highest
    StealConfig.StealPriority = priority
    _stealManualUID = nil
    saveStealConfig()
end

_G.StealSetManualUID = function(uid)
    _stealManualUID = uid
end

_G.StealGetManualUID = function()
    return _stealManualUID
end

_G._stealEnabled = function() return _stealEnabled end

end) end)

-- ═══ Optimizer ═══

-- ═══ Click AP ═══
task.spawn(function()
    pcall(function()
-- -360 made ts

repeat task.wait() until game:IsLoaded()
task.wait(2)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local clickAPEnabled = false
local currentTargetPlayer = nil
local highlightObject = nil
local commandMode = "all"
local lastCommandMode = "all"
local threeCommandIndex = 0
local lastUpdateTime = 0
local UPDATE_INTERVAL = 0.05

local CommandCooldowns = {}
local Commands = {}
local LastCommandUse = {}
_G.ClickAP_Cooldowns = CommandCooldowns
_G.ClickAP_LastUse = LastCommandUse

local AdminCmdsData = require(ReplicatedStorage.Datas.AdminCommands)
for name, info in pairs(AdminCmdsData) do
    if name ~= "control" then
        CommandCooldowns[name] = info.cooldown
        table.insert(Commands, name)
    end
end

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local AdminPanelFolder = PlayerGui:WaitForChild("AdminPanel", 10)
if not AdminPanelFolder then return end
local adminPath = AdminPanelFolder:WaitForChild("AdminPanel", 5)
if not adminPath then return end

local function adminpanel(player, command)
    local realAdminGui = PlayerGui:FindFirstChild("AdminPanel")
    if not realAdminGui then return false end
    local ap = realAdminGui:FindFirstChild("AdminPanel")
    if not ap then return false end
    -- Click COMMAND first, then PLAYER (correct order)
    local cf = ap:FindFirstChild("Content")
    if not cf then return false end
    local cs = cf:FindFirstChild("ScrollingFrame")
    if not cs then return false end
    local command_ui = cs:FindFirstChild(command)
    if not command_ui then return false end
    if firesignal then
        firesignal(command_ui.MouseButton1Click)
        firesignal(command_ui.MouseButton1Down)
        firesignal(command_ui.Activated)
    end
    task.wait(0.05)
    local ps = ap:FindFirstChild("Profiles")
    if not ps then return false end
    local sc = ps:FindFirstChild("ScrollingFrame")
    if not sc then return false end
    local player_ui = sc:FindFirstChild(player.Name)
    if not player_ui then return false end
    if firesignal then
        firesignal(player_ui.MouseButton1Click)
        firesignal(player_ui.MouseButton1Down)
        firesignal(player_ui.Activated)
    end
    return true
end
_G._adminpanel = adminpanel

-- ═══ ADMIN COMMAND (firesignal method only - safer) ═══
local function fireAdmin(targetPlayer, commandName)
    if not _G._adminpanel then return false end
    local ok = pcall(_G._adminpanel, targetPlayer, commandName)
    if not ok then task.wait(0.15); ok = pcall(_G._adminpanel, targetPlayer, commandName) end
    return ok
end
_G._fireAdmin = fireAdmin

local function isOnCooldown(cmd)
    return LastCommandUse[cmd] and (tick() - LastCommandUse[cmd]) < (CommandCooldowns[cmd] or 0)
end

local function getRemainingCooldown(cmd)
    if not LastCommandUse[cmd] then return 0 end
    local remaining = (CommandCooldowns[cmd] or 0) - (tick() - LastCommandUse[cmd])
    return math.max(0, remaining)
end

local function executeCommand(targetPlayer, command)
    if isOnCooldown(command) then return false end
    if fireAdmin(targetPlayer, command) then
        LastCommandUse[command] = tick()
        if _G.ClickAP_LastUse then _G.ClickAP_LastUse[command] = tick() end
    end
    pcall(function()
        if _G.ShowOutgoingCmd and targetPlayer then
            _G.ShowOutgoingCmd(targetPlayer.Name, command)
        end
    end)
    return true
end

local function runCommands(targetPlayer)
    if not targetPlayer then return end
    task.spawn(function()
        local cmdsToRun = {}
        if commandMode == "all" then
            for _, cmd in ipairs(Commands) do
                if not isOnCooldown(cmd) then table.insert(cmdsToRun, cmd) end
            end
        elseif commandMode == "three" then
            local THREE_GROUPS = {
                {"ragdoll", "inverse", "morph"},
                {"balloon", "jumpscare", "tiny"},
                {"rocket",  "jail",     "nightvision"},
            }
            local group = THREE_GROUPS[(threeCommandIndex % #THREE_GROUPS) + 1]
            for _, cmd in ipairs(group) do
                if not isOnCooldown(cmd) then table.insert(cmdsToRun, cmd) end
            end
            threeCommandIndex = threeCommandIndex + 1
        end

        local count = 0
        for _, cmd in ipairs(cmdsToRun) do
            task.delay(count * 0.1, function()
                if fireAdmin(targetPlayer, cmd) then
                    LastCommandUse[cmd] = tick()
                    if _G.ClickAP_LastUse then _G.ClickAP_LastUse[cmd] = tick() end
                    pcall(function()
                        if _G.ShowOutgoingCmd and targetPlayer then
                            _G.ShowOutgoingCmd(targetPlayer.Name, cmd)
                        end
                    end)
                end
            end)
            count = count + 1
        end
    end)
end

local function getAvatarRigType(character)
    if not character then return "unknown" end
    if character:FindFirstChild("UpperTorso") and character:FindFirstChild("LowerTorso") then return "R15" end
    if character:FindFirstChild("Torso") and not character:FindFirstChild("UpperTorso") then return "R6" end
    if character:FindFirstChildOfClass("Humanoid") then return "custom" end
    return "unknown"
end

local function createHighlight(character)
    if highlightObject then highlightObject:Destroy() highlightObject = nil end
    if not character then return end
    pcall(function()

        highlightObject = Instance.new("Highlight")
        highlightObject.Name = "HL_" .. tostring(math.random(1000, 9999))
        highlightObject.Adornee = character
        highlightObject.FillColor = Color3.fromRGB(80, 200, 120)
        highlightObject.OutlineColor = Color3.fromRGB(144, 238, 144)
        highlightObject.FillTransparency = 0.15
        highlightObject.OutlineTransparency = 0
        highlightObject.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlightObject.Parent = character

        local rigType = getAvatarRigType(character)
        if rigType == "R6" or rigType == "R15" then
            local function createLine(part1, part2, parent)
                if not part1 or not part2 then return end
                local a0 = Instance.new("Attachment") a0.Parent = part1
                local a1 = Instance.new("Attachment") a1.Parent = part2
                local beam = Instance.new("Beam")
                beam.Attachment0 = a0 beam.Attachment1 = a1
                beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
                beam.FaceCamera = true beam.LightEmission = 1
                beam.Transparency = NumberSequence.new(0.3)
                beam.Width0 = 0.15 beam.Width1 = 0.15
                beam.Parent = parent
            end
            if rigType == "R15" then
                local h = character:FindFirstChild("Head")
                local ut = character:FindFirstChild("UpperTorso")
                local lt = character:FindFirstChild("LowerTorso")
                local lua = character:FindFirstChild("LeftUpperArm")
                local lla = character:FindFirstChild("LeftLowerArm")
                local lh = character:FindFirstChild("LeftHand")
                local rua = character:FindFirstChild("RightUpperArm")
                local rla = character:FindFirstChild("RightLowerArm")
                local rh = character:FindFirstChild("RightHand")
                local lul = character:FindFirstChild("LeftUpperLeg")
                local lll = character:FindFirstChild("LeftLowerLeg")
                local lf = character:FindFirstChild("LeftFoot")
                local rul = character:FindFirstChild("RightUpperLeg")
                local rll = character:FindFirstChild("RightLowerLeg")
                local rf = character:FindFirstChild("RightFoot")
                createLine(h, ut, character) createLine(ut, lt, character)
                createLine(ut, lua, character) createLine(lua, lla, character) createLine(lla, lh, character)
                createLine(ut, rua, character) createLine(rua, rla, character) createLine(rla, rh, character)
                createLine(lt, lul, character) createLine(lul, lll, character) createLine(lll, lf, character)
                createLine(lt, rul, character) createLine(rul, rll, character) createLine(rll, rf, character)
            elseif rigType == "R6" then
                local h = character:FindFirstChild("Head")
                local t = character:FindFirstChild("Torso")
                local la = character:FindFirstChild("Left Arm")
                local ra = character:FindFirstChild("Right Arm")
                local ll = character:FindFirstChild("Left Leg")
                local rl = character:FindFirstChild("Right Leg")
                createLine(h, t, character) createLine(t, la, character)
                createLine(t, ra, character) createLine(t, ll, character) createLine(t, rl, character)
            end
        end
    end)
end

local function clearHighlight()
    if highlightObject then highlightObject:Destroy() highlightObject = nil end
    if currentTargetPlayer and currentTargetPlayer.Character then
        for _, child in ipairs(currentTargetPlayer.Character:GetDescendants()) do
            if (child:IsA("Beam") or child:IsA("Highlight")) and not child.Name:find("_360s") then
                pcall(function() child:Destroy() end)
            end
            if child:IsA("Attachment") and child.Name == "Attachment" then
                pcall(function() child:Destroy() end)
            end
        end
    end
end

local function overridePlayerESP(character)
    if not character then return end
    task.spawn(function()
        while highlightObject and highlightObject.Parent do
            pcall(function()
                for _, hl in ipairs(character:GetChildren()) do
                    if hl:IsA("Highlight") and hl ~= highlightObject then hl:Destroy() end
                end
            end)
            task.wait(0.2)
        end
    end)
end

local cachedPlayers = {}
local lastPlayerCacheTime = 0

local function getClosestPlayerToMouse()
    local closestPlayer = nil
    local shortestDistance = math.huge
    local mousePos = UserInputService:GetMouseLocation()
    local currentTime = tick()
    if currentTime - lastPlayerCacheTime > 0.5 then
        cachedPlayers = Players:GetPlayers()
        lastPlayerCacheTime = currentTime
    end
    for _, player in ipairs(cachedPlayers) do
        if player ~= LocalPlayer and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local distance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if distance < shortestDistance and distance < 200 then
                        shortestDistance = distance
                        closestPlayer = player
                    end
                end
            end
        end
    end
    return closestPlayer
end

local function updateTargetHighlight()
    if not clickAPEnabled then
        if currentTargetPlayer then clearHighlight() currentTargetPlayer = nil end
        return
    end
    local closestPlayer = getClosestPlayerToMouse()
    if closestPlayer ~= currentTargetPlayer then
        if currentTargetPlayer then clearHighlight() end
        currentTargetPlayer = closestPlayer
        if currentTargetPlayer and currentTargetPlayer.Character then
            createHighlight(currentTargetPlayer.Character)
            overridePlayerESP(currentTargetPlayer.Character)
        end
    end
end

local function onRightClick()
    if not clickAPEnabled or not currentTargetPlayer then return end
    runCommands(currentTargetPlayer)
end

local DISPLAY_NAMES = {
    ["rocket"] = "Rocket:",
    ["ragdoll"] = "Ragdoll:",
    ["balloon"] = "Balloon:",
    ["inverse"] = "Inverse:",
    ["jail"] = "Jail:",
    ["nightvision"] = "NightVis:",
    ["tiny"] = "Tiny:",
    ["morph"] = "Morph:",
    ["jumpscare"] = "Jumpscare:",
}

local gui = Instance.new("ScreenGui")
gui.Name = tostring(math.random(100000, 999999))
local guiSuccess = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not guiSuccess then gui.Parent = gethui() end
gui.ResetOnSpawn = false
_G.UIHide_ClickCommands = gui
gui.IgnoreGuiInset = true
if protect_gui then protect_gui(gui) end

local CORNER_RADIUS = 8
local GUI_Y_POSITION = 68  -- below FPS/Ping HUD (Y=32, H=28, +8px gap)
local LEFT_WIDTH = 145
local RIGHT_WIDTH = 170
local DIVIDER_WIDTH = 1
local TOTAL_WIDTH = LEFT_WIDTH + DIVIDER_WIDTH + RIGHT_WIDTH
local ROW_HEIGHT = 17
local ROW_SPACING = 1
local PANEL_HEIGHT = 30 + (ROW_HEIGHT + ROW_SPACING) * #Commands + 10

local mainFrame = Instance.new("Frame", gui)
mainFrame.Size = UDim2.new(0, TOTAL_WIDTH, 0, PANEL_HEIGHT)
mainFrame.Position = UDim2.new(0, 5, 0, GUI_Y_POSITION)
_G._clickAPFrame = mainFrame  -- publish so notifications can track our position
mainFrame.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
mainFrame.BackgroundTransparency = 0.75
if not _G._hubPanelFrames then _G._hubPanelFrames={} end; table.insert(_G._hubPanelFrames, mainFrame)
mainFrame.BorderSizePixel = 0
mainFrame.ZIndex = 50

local mainCorner = Instance.new("UICorner", mainFrame)
mainCorner.CornerRadius = UDim.new(0, CORNER_RADIUS)
local _apStroke = Instance.new("UIStroke", mainFrame)
_apStroke.Color = Color3.fromRGB(255, 40, 160); _apStroke.Thickness = 1


local divider = Instance.new("Frame", mainFrame)
divider.Size = UDim2.new(0, 1, 1, -16)
divider.Position = UDim2.new(0, LEFT_WIDTH, 0, 8)
divider.BackgroundColor3 = Color3.fromRGB(255, 40, 160)
divider.BackgroundTransparency = 0
divider.BorderSizePixel = 0
divider.ZIndex = 51

local leftTitle = Instance.new("TextLabel", mainFrame)
leftTitle.Size = UDim2.new(0, LEFT_WIDTH, 0, 20)
leftTitle.Position = UDim2.new(0, 0, 0, 6)
leftTitle.BackgroundTransparency = 1
leftTitle.Text = "IDF HUB"
leftTitle.Font = Enum.Font.GothamBold
leftTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
leftTitle.TextSize = 12
leftTitle.TextXAlignment = Enum.TextXAlignment.Center
leftTitle.ZIndex = 51

local BOX_PADDING_X = 8
local BOX_WIDTH = LEFT_WIDTH - (BOX_PADDING_X * 2)
local BOX_HEIGHT = 36
local BOX_SPACING = 6
local BOX_START_Y = 30
local BOX_CORNER = 5

local function createCommandBox(parent, titleText, subText, yPos)
    local boxFrame = Instance.new("Frame", parent)
    boxFrame.Size = UDim2.new(0, BOX_WIDTH, 0, BOX_HEIGHT)
    boxFrame.Position = UDim2.new(0, BOX_PADDING_X, 0, yPos)
    boxFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    boxFrame.BackgroundTransparency = 0
    boxFrame.BorderSizePixel = 0
    boxFrame.ZIndex = 51

    local boxCorner = Instance.new("UICorner", boxFrame)
    boxCorner.CornerRadius = UDim.new(0, BOX_CORNER)

    local boxStroke = Instance.new("UIStroke", boxFrame)
    boxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    boxStroke.Thickness = 1
    boxStroke.Color = Color3.fromRGB(50, 50, 60)
    boxStroke.Transparency = 0.3

    local titleLabel = Instance.new("TextLabel", boxFrame)
    titleLabel.Size = UDim2.new(1, -10, 0, 16)
    titleLabel.Position = UDim2.new(0, 5, 0, 3)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = titleText
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 11
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.ZIndex = 52

    local subLabel = Instance.new("TextLabel", boxFrame)
    subLabel.Size = UDim2.new(1, -10, 0, 14)
    subLabel.Position = UDim2.new(0, 5, 0, 19)
    subLabel.BackgroundTransparency = 1
    subLabel.Text = subText
    subLabel.Font = Enum.Font.Gotham
    subLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    subLabel.TextSize = 9
    subLabel.TextXAlignment = Enum.TextXAlignment.Left
    subLabel.ZIndex = 52

    local button = Instance.new("TextButton", boxFrame)
    button.Size = UDim2.new(1, 0, 1, 0)
    button.BackgroundTransparency = 1
    button.Text = ""
    button.AutoButtonColor = false
    button.ZIndex = 53

    return button, boxFrame, titleLabel, subLabel
end

local rightClickButton, rightClickBox, rightClickTitle, rightClickSub = createCommandBox(
    mainFrame, "Right Click", "Runs Commands", BOX_START_Y
)

local allCmdsButton, allCmdsBox, allCmdsTitle, allCmdsSub = createCommandBox(
    mainFrame, "All Cmds", "Runs all commands", BOX_START_Y + BOX_HEIGHT + BOX_SPACING
)

local threeCmdsButton, threeCmdsBox, threeCmdsTitle, threeCmdsSub = createCommandBox(
    mainFrame, "3 Commands", "Runs 3 commands in order", BOX_START_Y + (BOX_HEIGHT + BOX_SPACING) * 2
)

local infoStartY = BOX_START_Y + (BOX_HEIGHT + BOX_SPACING) * 3 + 4




local rightStartX = LEFT_WIDTH + DIVIDER_WIDTH

local rightTitle = Instance.new("TextLabel", mainFrame)
rightTitle.Size = UDim2.new(0, RIGHT_WIDTH, 0, 20)
rightTitle.Position = UDim2.new(0, rightStartX, 0, 6)
rightTitle.BackgroundTransparency = 1
rightTitle.Text = "Cooldowns"
rightTitle.Font = Enum.Font.GothamBold
rightTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
rightTitle.TextSize = 12
rightTitle.TextXAlignment = Enum.TextXAlignment.Center
rightTitle.ZIndex = 51

local commandLabels = {}
local COOLDOWN_ROW_START = 28

for i, commandName in ipairs(Commands) do
    local yPos = COOLDOWN_ROW_START + (i - 1) * (ROW_HEIGHT + ROW_SPACING)

    local nameLabel = Instance.new("TextLabel", mainFrame)
    nameLabel.Size = UDim2.new(0, 85, 0, ROW_HEIGHT)
    nameLabel.Position = UDim2.new(0, rightStartX + 10, 0, yPos)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = DISPLAY_NAMES[commandName] or (commandName .. ":")
    nameLabel.Font = Enum.Font.Gotham
    nameLabel.TextSize = 11
    nameLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.ZIndex = 51

    local statusLabel = Instance.new("TextLabel", mainFrame)
    statusLabel.Size = UDim2.new(0, 55, 0, ROW_HEIGHT)
    statusLabel.Position = UDim2.new(0, rightStartX + RIGHT_WIDTH - 65, 0, yPos)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Ready"
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 11
    statusLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Right
    statusLabel.ZIndex = 51

    commandLabels[commandName] = statusLabel
end

local function updateModeVisuals()
    if clickAPEnabled then
        rightClickBox.BackgroundColor3 = Color3.fromRGB(25, 35, 25)
        rightClickTitle.TextColor3 = Color3.fromRGB(60, 255, 60)
        if commandMode == "all" then
            allCmdsBox.BackgroundColor3 = Color3.fromRGB(25, 35, 25)
            allCmdsTitle.TextColor3 = Color3.fromRGB(60, 255, 60)
            allCmdsSub.TextColor3 = Color3.fromRGB(180, 255, 180)
            threeCmdsBox.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
            threeCmdsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
            threeCmdsSub.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            allCmdsBox.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
            allCmdsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
            allCmdsSub.TextColor3 = Color3.fromRGB(255, 255, 255)
            threeCmdsBox.BackgroundColor3 = Color3.fromRGB(25, 35, 25)
            threeCmdsTitle.TextColor3 = Color3.fromRGB(60, 255, 60)
            threeCmdsSub.TextColor3 = Color3.fromRGB(180, 255, 180)
        end
    else
        rightClickBox.BackgroundColor3 = Color3.fromRGB(35, 25, 25)
        rightClickTitle.TextColor3 = Color3.fromRGB(255, 60, 60)
        allCmdsBox.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        allCmdsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        allCmdsSub.TextColor3 = Color3.fromRGB(255, 255, 255)
        threeCmdsBox.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
        threeCmdsTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
        threeCmdsSub.TextColor3 = Color3.fromRGB(255, 255, 255)
    end
end

local function toggleClickAP()
    clickAPEnabled = not clickAPEnabled
    if clickAPEnabled then
        commandMode = lastCommandMode
    else
        lastCommandMode = commandMode
        clearHighlight()
        currentTargetPlayer = nil
    end
    updateModeVisuals()
end

local function selectAllCommands()
    if not clickAPEnabled then return end
    commandMode = "all"
    lastCommandMode = "all"
    threeCommandIndex = 0
    updateModeVisuals()
end

local function selectThreeCommands()
    if not clickAPEnabled then return end
    commandMode = "three"
    lastCommandMode = "three"
    threeCommandIndex = 0
    updateModeVisuals()
end

rightClickButton.MouseButton1Click:Connect(toggleClickAP)
allCmdsButton.MouseButton1Click:Connect(selectAllCommands)
threeCmdsButton.MouseButton1Click:Connect(selectThreeCommands)
updateModeVisuals()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if UserInputService:GetFocusedTextBox() then return end
    if Enum.KeyCode[_G.ClickAPKeybind or "F"] and input.KeyCode == Enum.KeyCode[_G.ClickAPKeybind or "F"] then toggleClickAP() end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then onRightClick() end
end)

task.spawn(function()
    while true do
        for command, label in pairs(commandLabels) do
            if isOnCooldown(command) then
                label.Text = math.ceil(getRemainingCooldown(command)) .. "s"
                label.TextColor3 = Color3.fromRGB(255, 255, 255)
            else
                label.Text = "Ready"
                label.TextColor3 = Color3.fromRGB(0, 255, 0)
            end
        end
        task.wait(0.1)
    end
end)

RunService.Heartbeat:Connect(function()
    local currentTime = tick()
    if currentTime - lastUpdateTime >= UPDATE_INTERVAL then
        lastUpdateTime = currentTime
        pcall(updateTargetHighlight)
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    clearHighlight()
    currentTargetPlayer = nil
end)


-- Make Click AP panel draggable via its title bar
makeDraggable(mainFrame, "ClickAPFrame", leftTitle)
gui.Enabled = false
pcall(addGlowBorder, _stFrame)

-- -bluebands
    end)
end)

-- ═══ Speed GUI ═══
task.spawn(function()
    pcall(function()
repeat task.wait() until game:IsLoaded()
task.wait(0.3)
pcall(function() game:GetService("Players").RespawnTime = 0 end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Stats = game:GetService("Stats")

local LocalPlayer
repeat
	LocalPlayer = Players.LocalPlayer
	if not LocalPlayer then task.wait(0.5) end
until LocalPlayer

local playerGui = LocalPlayer:WaitForChild("PlayerGui", 15)
if not playerGui then return end

local Camera = Workspace.CurrentCamera
pcall(function() Camera.FieldOfView = 90 end)

if not ReplicatedStorage:FindFirstChild("juisdfj0i32i0eidsuf0iok") then
	local d = Instance.new("Decal")
	d.Name = "juisdfj0i32i0eidsuf0iok"
	d.Parent = ReplicatedStorage
end

local _realSettingsObj = ReplicatedStorage:FindFirstChild("juisdfj0i32i0eidsuf0iok")

-- ═══════════════════════════════════════
-- ═══════════════════════════════════════
local SETTINGS_FILE = "goated_settings.json"
local _savedSettings = {}

local _jsonService = game:GetService("HttpService")

local function _loadSettingsFile()
	if not readfile then return end
	pcall(function()
		local raw = readfile(SETTINGS_FILE)
		if not raw or #raw < 3 then return end
		local decoded = _jsonService:JSONDecode(raw)
		if type(decoded) ~= "table" then return end
		for k, v in pairs(decoded) do
			if type(v) == "boolean" or type(v) == "number" or type(v) == "string" then
				_savedSettings[k] = v
			end
		end
	end)
end

local function _saveSettingsFile()
	if not writefile then return end
	pcall(function()
		writefile(SETTINGS_FILE, _jsonService:JSONEncode(_savedSettings))
	end)
end

_loadSettingsFile()
pcall(function()
	for k, v in pairs(_savedSettings) do
		_realSettingsObj:SetAttribute(k, v)
	end
end)

local SettingsObj = setmetatable({}, {
	__index = function(_, key)
		if key == "GetAttribute" then
			return function(_, attr)
				local fileVal = _savedSettings[attr]
				if fileVal ~= nil then return fileVal end
				return _realSettingsObj:GetAttribute(attr)
			end
		elseif key == "SetAttribute" then
			return function(_, attr, val)
				_savedSettings[attr] = val
				pcall(function() _realSettingsObj:SetAttribute(attr, val) end)
				_saveSettingsFile()
			end
		end
		return _realSettingsObj[key]
	end
})

-- Synchronizer patch: handled by initial patch

local BRICK_RED    = Color3.fromRGB(180, 180, 180)
local TOGGLE_GREEN = Color3.fromRGB(85, 200, 85)
local WHITE        = Color3.fromRGB(255, 255, 255)
local APPLY_GREEN  = Color3.fromRGB(85, 255, 85)
local BG_COLOR     = Color3.fromRGB(8, 10, 18)
local BTN_COLOR    = Color3.fromRGB(14, 14, 22)
local BORDER_COLOR = Color3.fromRGB(255, 40, 160)

local SLIDER_C1 = Color3.fromRGB(255, 0, 220)
local SLIDER_C2 = Color3.fromRGB(30, 5, 30)
local BALL_DARK = Color3.fromRGB(255, 0, 220)


local autoKickEnabled   = false
local autoTurretEnabled = false

_G.SinkSliderValue       = 5.3
_G.SavedFOV              = 100
_G.AutoRecoverLagback    = true
_G.RecoveryInProgress    = false
_G.TPKeybind             = "V"
_G.InstantResetKeybind   = "X"
_G.CloneKeybind          = "B"
_G.RJKeybind             = "R"
_G.KickKeybind           = "Z"
_G.ClickAPKeybind        = "F"
_G.APKeybind             = "G"
_G.RagdollSelfKeybind    = "H"
_G.AutoTurretKeybind     = "C"
_G.CarpetSpeedKeybind    = "Q"
_G.FloatKeybind          = "U"
_G.KeybindPanelKeybind   = "G"



do local _old = playerGui:FindFirstChild("SettingsPanel") or game:GetService("CoreGui"):FindFirstChild("SettingsPanel"); if _old then _old:Destroy() end end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SettingsPanel"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
do
	local _ok = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
	if not _ok or not ScreenGui.Parent then
		pcall(function() if gethui then ScreenGui.Parent = gethui() end end)
	end
	if not ScreenGui.Parent then ScreenGui.Parent = playerGui end
end
if protect_gui then pcall(function() protect_gui(ScreenGui) end) end

-- ═══════════════════════════════════════
-- MERGED TOP HUB + BASE BUTTONS (fixed)
-- ═══════════════════════════════════════
task.spawn(function()
    pcall(function()
        local Players = game:GetService("Players")
        local RunService = game:GetService("RunService")
        local Stats = game:GetService("Stats")
        local Workspace = game:GetService("Workspace")
        local Camera = Workspace.CurrentCamera
        local LocalPlayer = Players.LocalPlayer
        local playerGui = LocalPlayer:WaitForChild("PlayerGui")

        -- ── Helper functions ──────────────────────────────────────
        local function getClosestPlot()
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return nil end
            local plots = Workspace:FindFirstChild("Plots")
            if not plots then return nil end
            local bestPlot, bestDist = nil, math.huge
            for _, plot in ipairs(plots:GetChildren()) do
                local ref = plot:FindFirstChild("Spawn")
                local pos = ref and ref:IsA("BasePart") and ref.Position or nil
                if not pos then pcall(function() pos = plot:GetPivot().Position end) end
                if pos then
                    local d = (hrp.Position - pos).Magnitude
                    if d < bestDist then bestDist = d; bestPlot = plot end
                end
            end
            return bestPlot
        end

        local function triggerClosestUnlock(floor)
            local character = LocalPlayer.Character
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            if not hrp then return end
            local UNLOCK_Y_LEVELS = {[1] = -2, [2] = 15, [3] = 32}
            local playerY = UNLOCK_Y_LEVELS[floor] or hrp.Position.Y
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
            local targetPrompt = bestPromptSameLevel or bestPromptFallback
            if targetPrompt then
                if fireproximityprompt then fireproximityprompt(targetPrompt)
                else
                    targetPrompt:InputBegan(Enum.UserInputType.MouseButton1)
                    task.wait(0.05)
                    targetPrompt:InputEnded(Enum.UserInputType.MouseButton1)
                end
            end
        end

        -- ── Compact constants ────────────────────────────────────
        local BG_COLOR     = Color3.fromRGB(8, 10, 18)
        local BTN_COLOR    = Color3.fromRGB(14, 14, 22)
        local BORDER_COLOR = Color3.fromRGB(255, 40, 160)
        local WHITE        = Color3.fromRGB(255, 255, 255)
        local TOGGLE_GREEN = Color3.fromRGB(85, 200, 85)

        -- ── ScreenGui ──────────────────────────────────────────────
        local TwayveGui = Instance.new("ScreenGui")
        TwayveGui.Name = "TwayveHub"
        TwayveGui.ResetOnSpawn = false
        TwayveGui.IgnoreGuiInset = true
        TwayveGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        local ok = pcall(function() TwayveGui.Parent = game:GetService("CoreGui") end)
        if not ok or not TwayveGui.Parent then
            pcall(function() if gethui then TwayveGui.Parent = gethui() end end)
        end
        if not TwayveGui.Parent then TwayveGui.Parent = playerGui end
        if protect_gui then pcall(function() protect_gui(TwayveGui) end) end

        -- ── Wide top bar ─────────────────────────────────────────
        local BAR_W = 660
        local BAR_H = 58

        local mainFrame = Instance.new("Frame")
        mainFrame.Name = "TopBar"
        mainFrame.Size = UDim2.new(0, BAR_W, 0, BAR_H)
        mainFrame.AnchorPoint = Vector2.new(0.5, 0)
        mainFrame.Position = UDim2.new(0.5, 0, 0, 16)
        mainFrame.BackgroundColor3 = BG_COLOR
        mainFrame.BackgroundTransparency = 0.75
        mainFrame.BorderSizePixel = 0
        mainFrame.Parent = TwayveGui
        if not _G._hubPanelFrames then _G._hubPanelFrames={} end; table.insert(_G._hubPanelFrames, mainFrame)
        Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 14)
        local _tbStroke = Instance.new("UIStroke", mainFrame)
        _tbStroke.Color = Color3.fromRGB(255, 0, 220); _tbStroke.Thickness = 2
        _tbStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        if not _G._hubPanelStrokes then _G._hubPanelStrokes = {} end
        table.insert(_G._hubPanelStrokes, _tbStroke)
do
    local _sdTB={{0.03,0.25,3,0.007},{0.08,0.7,2,0.009},{0.13,0.35,3,0.006},{0.19,0.8,2,0.008},{0.24,0.15,3,0.01},{0.3,0.6,2,0.007},{0.36,0.85,3,0.009},{0.42,0.2,2,0.006},{0.47,0.65,3,0.008},{0.53,0.4,2,0.01},{0.58,0.8,3,0.007},{0.64,0.2,2,0.009},{0.69,0.55,3,0.006},{0.75,0.85,2,0.008},{0.8,0.3,3,0.007},{0.86,0.7,2,0.009},{0.91,0.15,3,0.006},{0.96,0.5,2,0.008},{0.11,0.5,3,0.007},{0.33,0.35,2,0.009},{0.55,0.1,3,0.006},{0.77,0.45,2,0.008},{0.88,0.85,3,0.007},{0.05,0.9,2,0.01},{0.44,0.75,3,0.009},{0.66,0.1,2,0.007},{0.82,0.6,3,0.008},{0.97,0.3,2,0.006}}
    local _sfTB,_soTB={},{}
    for i,sp in ipairs(_sdTB) do
        local s=Instance.new("Frame",mainFrame)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=1
        s.BorderSizePixel=0;s.ZIndex=4
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfTB[i]=s;_soTB[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfTB) do
            if not s or not s.Parent then continue end
            _soTB[i]=(_soTB[i]-_sdTB[i][4]*dt)%1
            s.Position=UDim2.new(_soTB[i],0,_sdTB[i][2],0)
            s.BackgroundTransparency=math.abs(math.sin(tick()*1.5+i*0.6))*0.5
        end
    end)
end

        -- ── Left: image + hub name + owner ──────────────────────
        local hubImg = Instance.new("ImageLabel")
        hubImg.Size = UDim2.new(0, 38, 0, 38)
        hubImg.Position = UDim2.new(0, 8, 0.5, -19)
        hubImg.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
        hubImg.BackgroundTransparency = 0
        hubImg.BorderSizePixel = 0
        hubImg.Image = "rbxassetid://79669651456657"
        hubImg.ScaleType = Enum.ScaleType.Fit
        task.spawn(function()
            pcall(function() game:GetService("ContentProvider"):PreloadAsync({hubImg}) end)
        end)
        hubImg.ZIndex = 3
        hubImg.Parent = mainFrame
        Instance.new("UICorner", hubImg).CornerRadius = UDim.new(0, 6)
        local hubImgStroke = Instance.new("UIStroke", hubImg)
        hubImgStroke.Color = Color3.fromRGB(255, 0, 220); hubImgStroke.Thickness = 1.5

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0, 160, 1, 0)
        nameLabel.Position = UDim2.new(0, 54, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = "IDF HUB"
        nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        nameLabel.Font = Enum.Font.GothamBlack
        nameLabel.TextSize = 22
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = mainFrame

        local subLabel = Instance.new("TextLabel")
        subLabel.Size = UDim2.new(0, 160, 0, 14)
        subLabel.Position = UDim2.new(0, 56, 1, -16)
        subLabel.BackgroundTransparency = 1
        subLabel.Text = "By:@IDF"
        subLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        subLabel.Font = Enum.Font.Gotham
        subLabel.TextSize = 11
        subLabel.TextXAlignment = Enum.TextXAlignment.Left
        subLabel.Parent = mainFrame

        -- ── Left divider ──────────────────────────────────────────
        local divL = Instance.new("Frame")
        divL.Size = UDim2.new(0, 1, 0, 28)
        divL.Position = UDim2.new(0, 210, 0.5, -14)
        divL.BackgroundColor3 = Color3.fromRGB(255, 0, 220)
        divL.BackgroundTransparency = 0.2
        divL.BorderSizePixel = 0
        divL.Parent = mainFrame

        -- ── Center label ──────────────────────────────────────────
        local centerLabel = Instance.new("TextLabel")
        centerLabel.Size = UDim2.new(0, 240, 1, 0)
        centerLabel.Position = UDim2.new(0.5, -120, 0, 0)
        centerLabel.BackgroundTransparency = 1
        centerLabel.Text = "discord.gg/idfhub"
        centerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        centerLabel.Font = Enum.Font.GothamBold
        centerLabel.TextSize = 13
        centerLabel.TextXAlignment = Enum.TextXAlignment.Center
        centerLabel.Parent = mainFrame

        -- ── Right divider ─────────────────────────────────────────
        local divR = Instance.new("Frame")
        divR.Size = UDim2.new(0, 1, 0, 28)
        divR.Position = UDim2.new(1, -175, 0.5, -14)
        divR.BackgroundColor3 = Color3.fromRGB(255, 0, 220)
        divR.BackgroundTransparency = 0.2
        divR.BorderSizePixel = 0
        divR.Parent = mainFrame

        -- ── Right: FPS / PING stacked ─────────────────────────────
        local fpsLabel = Instance.new("TextLabel")
        fpsLabel.Size = UDim2.new(0, 168, 0, 22)
        fpsLabel.Position = UDim2.new(1, -173, 0, 6)
        fpsLabel.BackgroundTransparency = 1
        fpsLabel.Text = "FPS:  --"
        fpsLabel.TextColor3 = WHITE
        fpsLabel.Font = Enum.Font.GothamBold
        fpsLabel.TextSize = 14
        fpsLabel.TextXAlignment = Enum.TextXAlignment.Left
        fpsLabel.Parent = mainFrame

        local pingLabel = Instance.new("TextLabel")
        pingLabel.Size = UDim2.new(0, 168, 0, 22)
        pingLabel.Position = UDim2.new(1, -173, 0, 28)
        pingLabel.BackgroundTransparency = 1
        pingLabel.Text = "PING:  --ms"
        pingLabel.TextColor3 = WHITE
        pingLabel.Font = Enum.Font.GothamBold
        pingLabel.TextSize = 14
        pingLabel.TextXAlignment = Enum.TextXAlignment.Left
        pingLabel.Parent = mainFrame

        -- ── Update FPS + Ping ─────────────────────────────────────
        task.spawn(function()
            local _fc = 0; local _ft = tick()
            RunService.RenderStepped:Connect(function()
                _fc = _fc + 1
                local now = tick()
                if now - _ft >= 1 then
                    local fps = math.floor(_fc / (now - _ft))
                    fpsLabel.Text = "FPS:  " .. fps
                    fpsLabel.TextColor3 = fps >= 55 and Color3.fromRGB(85,220,85) or (fps >= 30 and Color3.fromRGB(255,200,50) or Color3.fromRGB(220,60,60))
                    _fc = 0; _ft = now
                    pcall(function()
                        local ms = math.floor(LocalPlayer:GetNetworkPing() * 1000)
                        pingLabel.Text = "PING:  " .. ms .. "ms"
                        pingLabel.TextColor3 = ms <= 80 and Color3.fromRGB(85,220,85) or (ms <= 180 and Color3.fromRGB(255,200,50) or Color3.fromRGB(220,60,60))
                    end)
                end
            end)
        end)

        _G.TwayveHubFrame = mainFrame
    end)
end)

-- ═══ Admin Notification Feed ═══
task.spawn(function() pcall(function()
    repeat task.wait() until game:IsLoaded()
    task.wait(2)

    local Players    = game:GetService("Players")
    local TweenService = game:GetService("TweenService")
    local RunService = game:GetService("RunService")
    local LocalPlayer = Players.LocalPlayer
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
    if not PlayerGui then return end

    -- ── GUI container ──────────────────────────────────────────────
    local feedGui = Instance.new("ScreenGui")
    feedGui.Name = "AdminNotifFeed"
    feedGui.ResetOnSpawn = false
    feedGui.IgnoreGuiInset = true
    feedGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local ok = pcall(function() feedGui.Parent = game:GetService("CoreGui") end)
    if not ok or not feedGui.Parent then
        pcall(function() if gethui then feedGui.Parent = gethui() end end)
    end
    if not feedGui.Parent then feedGui.Parent = PlayerGui end
    if protect_gui then pcall(function() protect_gui(feedGui) end) end

    -- List frame: centered at top of screen, below IDF HUB bar
    local listFrame = Instance.new("Frame")
    listFrame.Name = "NotifList"
    listFrame.Size = UDim2.new(0, 320, 0, 300)
    listFrame.AnchorPoint = Vector2.new(0.5, 0)
    listFrame.Position = UDim2.new(0.5, 0, 0, 80)
    listFrame.BackgroundTransparency = 1
    listFrame.BorderSizePixel = 0
    listFrame.Parent = feedGui

    local uil = Instance.new("UIListLayout", listFrame)
    uil.FillDirection = Enum.FillDirection.Vertical
    uil.SortOrder = Enum.SortOrder.LayoutOrder
    uil.Padding = UDim.new(0, 4)

    local notifQueue = {}
    local MAX_NOTIFS = 6

    local CMD_COLOR = {
        ragdoll    = Color3.fromRGB(255, 80,  80),
        jail       = Color3.fromRGB(255, 165,  0),
        balloon    = Color3.fromRGB(80,  160, 255),
        rocket     = Color3.fromRGB(255, 220,  50),
        jumpscare  = Color3.fromRGB(200,  50, 200),
        morph      = Color3.fromRGB(50,  210, 180),
        nightvision= Color3.fromRGB(100, 220,  80),
        tiny       = Color3.fromRGB(180, 100, 255),
        inverse    = Color3.fromRGB(255, 120,  40),
    }

    local function showNotif(sender, cmd)
        -- cap at MAX_NOTIFS: remove oldest
        if #notifQueue >= MAX_NOTIFS then
            local oldest = table.remove(notifQueue, 1)
            pcall(function() oldest:Destroy() end)
        end

        local row = Instance.new("Frame")
        row.Name = "Notif"
        row.Size = UDim2.new(0, 300, 0, 28)
        row.BackgroundColor3 = Color3.fromRGB(8, 8, 16)
        row.BackgroundTransparency = 0.25
        row.BorderSizePixel = 0
        row.LayoutOrder = #notifQueue + 1
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
        local stroke = Instance.new("UIStroke", row)
        stroke.Color = CMD_COLOR[cmd] or Color3.fromRGB(200, 200, 200)
        stroke.Thickness = 1
        stroke.Transparency = 0.3

        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(1, -12, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.RichText = true
        local cmdColor = CMD_COLOR[cmd] or Color3.fromRGB(220, 220, 220)
        local hexC = string.format("rgb(%d,%d,%d)", math.floor(cmdColor.R*255), math.floor(cmdColor.G*255), math.floor(cmdColor.B*255))
        local senderPart = sender ~= "" and ('<font color="rgb(255,255,255)">@' .. sender .. '</font> ') or ""
        lbl.Text = senderPart .. 'ran <font color="' .. hexC .. '">' .. cmd .. '</font> on you'
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 11
        lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row
        row.Parent = listFrame
        table.insert(notifQueue, row)

        -- fade out after 5s
        task.delay(5, function()
            pcall(function()
                TweenService:Create(row, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
                TweenService:Create(lbl, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
                TweenService:Create(stroke, TweenInfo.new(0.4), {Transparency = 1}):Play()
                task.wait(0.45)
                local idx = table.find(notifQueue, row)
                if idx then table.remove(notifQueue, idx) end
                row:Destroy()
            end)
        end)
    end

    _G._notifyAdminOnMe = showNotif

    -- ── Detection: RagdollEndTime attribute ────────────────────────
    local lastRagdollTime = 0
    LocalPlayer:GetAttributeChangedSignal("RagdollEndTime"):Connect(function()
        local t = LocalPlayer:GetAttribute("RagdollEndTime")
        if t and t ~= lastRagdollTime then
            lastRagdollTime = t
            showNotif("", "ragdoll")
        end
    end)

    -- ── Detection: watch AdminPanel RemoteEvents ──────────────────
    local watched = {}
    local KNOWN_CMDS = {"ragdoll","jail","balloon","rocket","jumpscare","morph","nightvision","tiny","inverse"}

    local function tryWatchRemote(re)
        if watched[re] then return end
        watched[re] = true
        re.OnClientEvent:Connect(function(...)
            local args = {...}
            -- look for a command name in the args
            local foundCmd = nil
            local foundSender = ""
            for _, v in ipairs(args) do
                if type(v) == "string" then
                    local low = v:lower()
                    for _, cmd in ipairs(KNOWN_CMDS) do
                        if low == cmd or low:find(cmd) then foundCmd = cmd; break end
                    end
                elseif typeof(v) == "Instance" and v:IsA("Player") and v ~= LocalPlayer then
                    foundSender = v.Name
                end
                if foundCmd then break end
            end
            if foundCmd then showNotif(foundSender, foundCmd) end
        end)
    end

    task.spawn(function()
        local apf = PlayerGui:FindFirstChild("AdminPanel") or PlayerGui:WaitForChild("AdminPanel", 15)
        if not apf then return end
        for _, v in ipairs(apf:GetDescendants()) do
            if v:IsA("RemoteEvent") then tryWatchRemote(v) end
        end
        apf.DescendantAdded:Connect(function(v)
            if v:IsA("RemoteEvent") then tryWatchRemote(v) end
        end)
    end)

    -- Also watch game-wide remotes (admin effects often fired from top-level)
    task.spawn(function()
        for _, v in ipairs(game:GetDescendants()) do
            if v:IsA("RemoteEvent") and v.Name:lower():find("admin") then
                pcall(tryWatchRemote, v)
            end
        end
    end)
end) end)

-- ═══════════════════════════════════════

local PAD     = 5
local ROW_H   = 50
local GAP     = 5
local GUI_W   = 260
local FULL_W  = GUI_W - PAD * 2
local LEFT_W  = math.floor((FULL_W - GAP) * 0.55)
local RIGHT_W = FULL_W - LEFT_W - GAP
local COL_W   = math.floor((GUI_W - PAD*2 - GAP*2) / 3)
local col1X   = PAD
local col2X   = PAD + COL_W + GAP
local col3X   = PAD + 2*(COL_W + GAP)

local function createBtn(parent, size, pos, text, textColor, fontSize, noOutline)
	local btn = Instance.new("TextButton")
	btn.Size = size; btn.Position = pos
	btn.BackgroundColor3 = BTN_COLOR; btn.BorderSizePixel = 0
	btn.Text = text; btn.TextColor3 = textColor or WHITE
	btn.Font = Enum.Font.GothamBold; btn.TextSize = fontSize or 12
	btn.AutoButtonColor = false; btn.Active = true; btn.Parent = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)
	if not noOutline then
		local s = Instance.new("UIStroke", btn); s.Color = BORDER_COLOR; s.Thickness = 1
	end
	return btn
end

local function createToggleBtn(parent, size, pos, text, fontSize)
	local btn = Instance.new("TextButton")
	btn.Size = size; btn.Position = pos
	btn.BackgroundColor3 = BTN_COLOR; btn.BorderSizePixel = 0
	btn.Text = text; btn.TextColor3 = BRICK_RED
	btn.Font = Enum.Font.GothamBold; btn.TextSize = fontSize or 11
	btn.AutoButtonColor = false; btn.Active = true; btn.Parent = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	return btn
end

local function setToggleBtnState(btn, on, onText, offText)
	btn.Text = on and onText or offText
	btn.TextColor3 = on and TOGGLE_GREEN or BRICK_RED
end

local function flashBtnRed(btn, txt)
	local orig = btn.Text; btn.TextColor3 = Color3.fromRGB(255, 70, 70)
	if txt then btn.Text = txt end
	task.delay(1, function() btn.TextColor3 = WHITE; btn.Text = orig end)
end
local function flashBtnGreen(btn)
	btn.TextColor3 = APPLY_GREEN
	task.delay(1.0, function()
		if btn and btn.Parent then btn.TextColor3 = WHITE end
	end)
end

-- ═══════════════════════════════════════
-- SLIDER SYSTEM
-- ═══════════════════════════════════════
local activeSliders  = {}
local draggingSlider = nil


local function createSlider(parent, labelText, minVal, maxVal, defaultVal, attributeKey, isInteger, suffix, yPos, showReset, stepSize, labelWidthOverride, textSizeOverride, textXOffsetOverride, numberSizeOverride, rXOffsetOverride)
	local ballSize   = 14
	local lineHeight = 4
	local step       = stepSize or (isInteger and 1 or 0.01)
	local labelWidth    = labelWidthOverride or 55
	local resetBoxSize  = 18
	local valueWidth    = 30
	local gapTextToLine = 2
	local gapLineToVal  = 10
	local gapValToReset = 2
	local xStartOffset = textXOffsetOverride or 0
	local rLeftOffset  = rXOffsetOverride or 0
	local fixedElementsWidth = (PAD * 2) + labelWidth + gapTextToLine + valueWidth + gapLineToVal
	if showReset then fixedElementsWidth = fixedElementsWidth + resetBoxSize + gapValToReset end
	local sliderW = GUI_W - fixedElementsWidth
	local sliderX = PAD + labelWidth + gapTextToLine + xStartOffset
	local valX    = sliderX + sliderW + gapLineToVal + xStartOffset
	local resetX  = valX + valueWidth + gapValToReset + xStartOffset - rLeftOffset
	local rowCenterY = yPos + 8

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, labelWidth, 0, 16)
	lbl.Position = UDim2.new(0, PAD + xStartOffset, 0, rowCenterY - 8)
	lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = WHITE
	lbl.Font = Enum.Font.GothamBold; lbl.TextSize = textSizeOverride or 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Parent = parent

	local line = Instance.new("Frame")
	line.Size = UDim2.new(0, sliderW, 0, lineHeight)
	line.Position = UDim2.new(0, sliderX, 0, rowCenterY - (lineHeight / 2))
	line.BackgroundColor3 = SLIDER_C1; line.BorderSizePixel = 0; line.Parent = parent
	Instance.new("UICorner", line).CornerRadius = UDim.new(0, 2)
	local gradient = Instance.new("UIGradient", line)
	gradient.Color = ColorSequence.new(SLIDER_C1, SLIDER_C2)

	local valLbl = Instance.new("TextLabel")
	valLbl.Size = UDim2.new(0, valueWidth, 0, 16)
	valLbl.Position = UDim2.new(0, valX, 0, rowCenterY - 8)
	valLbl.BackgroundTransparency = 1; valLbl.TextColor3 = WHITE
	valLbl.Font = Enum.Font.GothamBold; valLbl.TextSize = numberSizeOverride or 12
	valLbl.TextXAlignment = Enum.TextXAlignment.Left; valLbl.Parent = parent

	local resetBtn
	if showReset then
		resetBtn = Instance.new("TextButton")
		resetBtn.Size = UDim2.new(0, resetBoxSize, 0, resetBoxSize)
		resetBtn.Position = UDim2.new(0, resetX, 0, rowCenterY - (resetBoxSize / 2))
		resetBtn.BackgroundColor3 = BTN_COLOR; resetBtn.BorderSizePixel = 0
		resetBtn.Text = "R"; resetBtn.TextColor3 = WHITE
		resetBtn.Font = Enum.Font.GothamBold; resetBtn.TextSize = 10
		resetBtn.AutoButtonColor = false; resetBtn.Parent = parent
		Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(0, 3)
		local stroke = Instance.new("UIStroke", resetBtn); stroke.Color = BORDER_COLOR; stroke.Thickness = 1
	end

	local ball = Instance.new("TextButton")
	ball.Size = UDim2.new(0, ballSize, 0, ballSize)
	ball.BackgroundColor3 = BALL_DARK; ball.BorderSizePixel = 0; ball.Text = ""
	ball.AutoButtonColor = false; ball.ZIndex = 2; ball.Parent = parent
	Instance.new("UICorner", ball).CornerRadius = UDim.new(1, 0)
	local ballGrad = Instance.new("UIGradient", ball)
	ballGrad.Color = ColorSequence.new(SLIDER_C1, BALL_DARK)

	local function valToTxt(v)
		local snapped = math.floor(v / step + 0.5) * step
		if isInteger then return tostring(math.floor(snapped)) .. suffix end
		if step == 0.1 then return string.format("%.1f", snapped) .. suffix end
		return string.format("%.2f", snapped) .. suffix
	end
	local function valToPos(v)
		return sliderX + ((v - minVal) / (maxVal - minVal)) * sliderW - (ballSize / 2)
	end

	local savedVal = SettingsObj:GetAttribute(attributeKey)
	if savedVal == nil then savedVal = defaultVal end
	savedVal = math.floor(savedVal / step + 0.5) * step
	local currentVal = savedVal

	ball.Position = UDim2.new(0, valToPos(currentVal), 0, rowCenterY - (ballSize / 2))
	valLbl.Text = valToTxt(currentVal)

	local function applyGlobal(v)
		if attributeKey == "SavedRotation" then _G.InvisStealAngle = v end
		if attributeKey == "SavedDepth" then _G.SinkSliderValue = v end
		if attributeKey == "SavedFOV" then _G.SavedFOV = v; Camera.FieldOfView = v end
		if attributeKey == "SavedWalkSpeed" and _G._applyWalkSpeed then _G._applyWalkSpeed(v) end
	end

	local sliderObj = {
		ball = ball, line = line,
		update = function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
			local mouseX = input.Position.X
			local frameAbsX = parent.AbsolutePosition.X
			local localX = mouseX - frameAbsX
			local t = math.clamp((localX - sliderX) / sliderW, 0, 1)
			local v = minVal + t * (maxVal - minVal)
			local snapped = math.floor(v / step + 0.5) * step
			currentVal = math.clamp(snapped, minVal, maxVal)
			ball.Position = UDim2.new(0, valToPos(currentVal), 0, rowCenterY - (ballSize / 2))
			valLbl.Text = valToTxt(currentVal)
			SettingsObj:SetAttribute(attributeKey, currentVal)
			applyGlobal(currentVal)
		end,
		finish = function()
			SettingsObj:SetAttribute(attributeKey, currentVal)
			applyGlobal(currentVal)
		end
	}
	sliderObj.setValue = function(v)
		currentVal = math.clamp(math.floor(v / step + 0.5) * step, minVal, maxVal)
		ball.Position = UDim2.new(0, valToPos(currentVal), 0, rowCenterY - (ballSize / 2))
		valLbl.Text = valToTxt(currentVal)
		SettingsObj:SetAttribute(attributeKey, currentVal)
		applyGlobal(currentVal)
	end

	ball.MouseButton1Down:Connect(function() draggingSlider = sliderObj end)
	if resetBtn then
		resetBtn.MouseButton1Click:Connect(function()
			sliderObj.setValue(defaultVal)
			resetBtn.TextColor3 = TOGGLE_GREEN
			task.delay(0.7, function() if resetBtn and resetBtn.Parent then resetBtn.TextColor3 = WHITE end end)
		end)
	end
	table.insert(activeSliders, sliderObj)
	applyGlobal(currentVal)
end

-- ═══════════════════════════════════════
-- MAIN FRAME
-- ═══════════════════════════════════════
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"; MainFrame.BackgroundColor3 = BG_COLOR
MainFrame.BackgroundTransparency = 0.75; MainFrame.BorderSizePixel = 0
MainFrame.Active = true; MainFrame.Parent = ScreenGui
MainFrame.ClipsDescendants = true
_G.UIHide_Tools = MainFrame
if not _G._hubPanelFrames then _G._hubPanelFrames={} end; table.insert(_G._hubPanelFrames, MainFrame)

do
    local _sdTOOLS={{0.106,0.906,2,0.0065},{0.308,0.122,2,0.0044},{0.354,0.7,3,0.0051},{0.389,0.415,3,0.0065},{0.754,0.087,3,0.0036},{0.239,0.685,2,0.0049},{0.233,0.391,2,0.005},{0.73,0.226,2,0.0047},{0.31,0.797,2,0.006},{0.41,0.342,2,0.0041},{0.465,0.808,2,0.0044},{0.174,0.238,2,0.006},{0.703,0.793,2,0.0053},{0.122,0.786,2,0.0043},{0.795,0.679,3,0.0044},{0.139,0.59,3,0.005},{0.085,0.286,3,0.0039},{0.233,0.553,3,0.0053},{0.624,0.101,2,0.0059},{0.711,0.37,3,0.0045},{0.356,0.862,2,0.0036},{0.697,0.23,3,0.0049},{0.297,0.526,3,0.0054},{0.218,0.896,2,0.0041},{0.218,0.943,3,0.0048},{0.635,0.059,2,0.0052},{0.585,0.279,3,0.0041},{0.655,0.906,3,0.0041},{0.85,0.235,2,0.0036},{0.614,0.473,2,0.0049}}
    local _sfTOOLS,_soTOOLS={},{}
    for i,sp in ipairs(_sdTOOLS) do
        local s=Instance.new("Frame",MainFrame)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.3
        s.BorderSizePixel=0;s.ZIndex=10
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfTOOLS[i]=s;_soTOOLS[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfTOOLS) do
            if not s or not s.Parent then continue end
            _soTOOLS[i]=(_soTOOLS[i]-_sdTOOLS[i][4]*dt)%1
            s.Position=UDim2.new(_soTOOLS[i],0,_sdTOOLS[i][2],0)
            s.BackgroundTransparency=0.3+math.abs(math.sin(tick()*0.8+i*0.7))*0.5
        end
    end)
end
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)
local mfStroke = Instance.new("UIStroke", MainFrame)
mfStroke.Color = Color3.fromRGB(255, 40, 160); mfStroke.Thickness = 2
if not _G._hubPanelStrokes then _G._hubPanelStrokes = {} end
table.insert(_G._hubPanelStrokes, mfStroke)

local y = PAD; local leftX = PAD; local rightX = PAD + LEFT_W + GAP

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -16, 0, 22); TitleLabel.Position = UDim2.new(0, 8, 0, PAD)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "IDF HUB"; TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.Font = Enum.Font.GothamBold; TitleLabel.TextSize = 14
TitleLabel.TextXAlignment = Enum.TextXAlignment.Center; TitleLabel.Parent = MainFrame; TitleLabel.ZIndex = 2
local _subTitleLabel = Instance.new("TextLabel")
_subTitleLabel.Size = UDim2.new(1, -16, 0, 14); _subTitleLabel.Position = UDim2.new(0, 8, 0, PAD + 22)
_subTitleLabel.BackgroundTransparency = 1
_subTitleLabel.Text = "tools"; _subTitleLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
_subTitleLabel.Font = Enum.Font.Gotham; _subTitleLabel.TextSize = 11
_subTitleLabel.TextXAlignment = Enum.TextXAlignment.Center; _subTitleLabel.Parent = MainFrame; _subTitleLabel.ZIndex = 2
local _toolsSep = Instance.new("Frame", MainFrame)
_toolsSep.Size = UDim2.new(1, -20, 0, 1); _toolsSep.Position = UDim2.new(0, 10, 0, PAD + 40)
_toolsSep.BackgroundColor3 = Color3.fromRGB(255, 255, 255); _toolsSep.BackgroundTransparency = 0.7
_toolsSep.BorderSizePixel = 0; _toolsSep.ZIndex = 2
y = y + 50
local _toolsTitleStroke = {ApplyStrokeMode=0}  -- dummy

do
    local _sdTL={{0.781,0.361,1,0.0065},{0.913,0.334,3,0.013},{0.254,0.545,3,0.005},{0.293,0.768,2,0.0064},{0.795,0.506,2,0.0065},{0.332,0.17,2,0.0093},{0.223,0.253,1,0.0118},{0.685,0.821,3,0.0106},{0.102,0.772,1,0.0109},{0.829,0.176,2,0.0116},{0.892,0.727,1,0.0072},{0.619,0.836,1,0.0078},{0.528,0.763,2,0.011},{0.919,0.525,1,0.0096}}
    local _sfTL,_soTL={},{}
    for i,sp in ipairs(_sdTL) do
        local s=Instance.new("Frame",TitleLabel)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.2
        s.BorderSizePixel=0;s.ZIndex=3
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfTL[i]=s;_soTL[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfTL) do
            if not s or not s.Parent then continue end
            _soTL[i]=(_soTL[i]-_sdTL[i][4]*dt)%1
            s.Position=UDim2.new(_soTL[i],0,_sdTL[i][2],0)
            s.BackgroundTransparency=0.1+math.abs(math.sin(tick()*1.2+i))*0.7
        end
    end)
end

y = y + 22 + GAP; local rowY = y

local AutoKickBtn = createToggleBtn(MainFrame, UDim2.new(0, FULL_W, 0, ROW_H), UDim2.new(0, PAD, 0, rowY), "Auto Kick ON", 11)
AutoKickBtn.TextColor3 = TOGGLE_GREEN
local AutoTurretBtn = createToggleBtn(MainFrame, UDim2.new(0, FULL_W, 0, ROW_H), UDim2.new(0, PAD, 0, rowY + ROW_H + GAP), "Anti Turret OFF", 11)
local AutoBuyBtn = createToggleBtn(MainFrame, UDim2.new(0, FULL_W, 0, ROW_H), UDim2.new(0, PAD, 0, rowY + 2*(ROW_H + GAP)), "Auto Buy OFF", 11)

local SMALL_SQ = 28; local SQ_GAP = 3; local smallRowY = y
local RejoinBtn = createBtn(MainFrame, UDim2.new(0, SMALL_SQ, 0, SMALL_SQ), UDim2.new(0, rightX + 8, 0, smallRowY), "RJ", WHITE, 10); RejoinBtn.Visible = false
local RejoinPSBtn = createBtn(MainFrame, UDim2.new(0, SMALL_SQ + 6, 0, SMALL_SQ), UDim2.new(0, rightX + 8 + SMALL_SQ + SQ_GAP, 0, smallRowY), "RJ PS", WHITE, 9); RejoinPSBtn.Visible = false
local SellBtn = createBtn(MainFrame, UDim2.new(0, SMALL_SQ, 0, SMALL_SQ), UDim2.new(0, rightX + 8 + 2*(SMALL_SQ + SQ_GAP) + 6, 0, smallRowY), "S", Color3.fromRGB(40, 200, 90), 12); SellBtn.Visible = false
-- Stay moved to the same row, after S
local StayBtn = createBtn(MainFrame, UDim2.new(0, SMALL_SQ, 0, SMALL_SQ), UDim2.new(0, rightX + 8 + 3*(SMALL_SQ + SQ_GAP) + 6, 0, smallRowY), "Stay", BRICK_RED, 10); StayBtn.Visible = false
-- Right column Y position after the small row
local rightY = smallRowY + SMALL_SQ + SQ_GAP

-- Drop Brainrot button (fills the width of RagdollSelfBtn)
local DropBtn = createBtn(
    MainFrame,
    UDim2.new(0, RIGHT_W, 0, ROW_H),
    UDim2.new(0, rightX, 0, smallRowY + SMALL_SQ + SQ_GAP),
    "DROP",
    Color3.fromRGB(255, 80, 80),
    11
)
DropBtn.Visible = false

-- ===== DROP BRAINROT LOGIC =====
_G._dropConnections = _G._dropConnections or {}
_G._dropFeatureStates = _G._dropFeatureStates or { FreezePlayer = false }

local function walkfling(enabled)
    local function cleanup()
        _G._dropFeatureStates.FreezePlayer = false
        for _, conn in ipairs(_G._dropConnections) do
            if typeof(conn) == "RBXScriptConnection" then
                pcall(function() conn:Disconnect() end)
            elseif typeof(conn) == "thread" then
                pcall(task.cancel, conn)
            end
        end
        _G._dropConnections = {}
    end

    if not enabled then
        cleanup()
        return
    end

    cleanup()
    _G._dropFeatureStates.FreezePlayer = true

    -- Disable collisions for other players
    local colConn = RunService.Stepped:Connect(function()
        local character = LocalPlayer.Character
        if not character then return end
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                for _, part in ipairs(player.Character:GetChildren()) do
                    if part:IsA("BasePart") then
                        pcall(function() part.CanCollide = false end)
                    end
                end
            end
        end
    end)
    table.insert(_G._dropConnections, colConn)

    -- Fling thread
    local flingThread = task.spawn(function()
        local root = nil
        local vel = Vector3.new(0, 0, 0)
        local movel = 0.1
        while _G._dropFeatureStates.FreezePlayer do
            local char = LocalPlayer.Character
            root = char and char:FindFirstChild("HumanoidRootPart")
            if root then
                vel = root.Velocity
                root.Velocity = (vel * 10000) + Vector3.new(0, 10000, 0)
                RunService.RenderStepped:Wait()
                if root and root.Parent then
                    root.Velocity = vel + Vector3.new(0, movel, 0)
                    movel = movel * -1
                end
            end
            RunService.Heartbeat:Wait()
        end
    end)
    table.insert(_G._dropConnections, flingThread)

    -- Cleanup on character death
    local function setupDeathListener(char)
        local hum = char:WaitForChild("Humanoid", 5)
        if hum then
            local deathConn = hum.Died:Connect(function() cleanup() end)
            table.insert(_G._dropConnections, deathConn)
        end
    end
    if LocalPlayer.Character then setupDeathListener(LocalPlayer.Character) end
    local addedConn = LocalPlayer.CharacterAdded:Connect(setupDeathListener)
    table.insert(_G._dropConnections, addedConn)
end

local dropDebounce = false
DropBtn.MouseButton1Click:Connect(function()
    if dropDebounce then return end
    dropDebounce = true
    DropBtn.Text = "DROPPING..."
    DropBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    walkfling(true)
    task.wait(0.2)
    walkfling(false)
    DropBtn.Text = "DROP"
    DropBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
    dropDebounce = false
end)

local arrowXOffset = rightX + 8 + SMALL_SQ + SQ_GAP + (SMALL_SQ + 6) + SQ_GAP
-- Stud counter removed


local RagdollSelfBtn = createBtn(
    MainFrame,
    UDim2.new(0, RIGHT_W, 0, ROW_H),
    UDim2.new(0, rightX, 0, rightY + ROW_H + GAP),   -- moved up one row
    "Ragdoll Slf",
    WHITE,
    11
)
RagdollSelfBtn.Visible = false

local sliderRowY = rowY + 3*(ROW_H + GAP)
local _savedGUI_W = GUI_W
GUI_W = FULL_W
local fovCell = Instance.new("Frame", MainFrame)
fovCell.Size = UDim2.new(0, FULL_W, 0, ROW_H)
fovCell.Position = UDim2.new(0, PAD, 0, sliderRowY)
fovCell.BackgroundTransparency = 1
fovCell.BorderSizePixel = 0
createSlider(fovCell, "FOV", 30, 120, 100, "SavedFOV", true, "°", 0, true, nil, 32)

local wsCell = Instance.new("Frame", MainFrame)
wsCell.Size = UDim2.new(0, FULL_W, 0, ROW_H)
wsCell.Position = UDim2.new(0, PAD, 0, sliderRowY + ROW_H + GAP)
wsCell.BackgroundTransparency = 1
wsCell.BorderSizePixel = 0
do
    local _wsRS = game:GetService("RunService")
    local _wsLP = game:GetService("Players").LocalPlayer
    local _wsBoostConn = nil
    local _wsBoostEnabled = false
    local function applyWalkSpeed(v)
        if _wsBoostConn then _wsBoostConn:Disconnect(); _wsBoostConn = nil end
        if v <= 0 then _wsBoostEnabled = false; return end
        _wsBoostEnabled = true
        local c = _wsLP.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = v end
        _wsBoostConn = _wsRS.Heartbeat:Connect(function()
            if not _wsBoostEnabled then return end
            local c2 = _wsLP.Character
            local hum2 = c2 and c2:FindFirstChildOfClass("Humanoid")
            if hum2 and hum2.WalkSpeed ~= v then hum2.WalkSpeed = v end
        end)
    end
    _G._applyWalkSpeed = applyWalkSpeed
    createSlider(wsCell, "Walk Spd", 0, 32, 0, "SavedWalkSpeed", true, "", 0, true, nil, 40)
    SettingsObj:GetAttributeChangedSignal("SavedWalkSpeed"):Connect(function()
        applyWalkSpeed(SettingsObj:GetAttribute("SavedWalkSpeed") or 0)
    end)
    _wsLP.CharacterAdded:Connect(function(char)
        local v = SettingsObj:GetAttribute("SavedWalkSpeed") or 0
        if v <= 0 then return end
        task.wait(0.5)
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = v end
    end)
    task.defer(function()
        applyWalkSpeed(SettingsObj:GetAttribute("SavedWalkSpeed") or 0)
    end)
end
GUI_W = _savedGUI_W

local stealMinRowY = sliderRowY + 2 * (ROW_H + GAP)
do
    local row = Instance.new("Frame", MainFrame)
    row.Size = UDim2.new(0, GUI_W - PAD * 2, 0, ROW_H)
    row.Position = UDim2.new(0, PAD, 0, stealMinRowY)
    row.BackgroundTransparency = 1
    row.BorderSizePixel = 0

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0, 150, 1, 0)
    lbl.Position = UDim2.new(0, 0, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "Steal Nearest Min"
    lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local box = Instance.new("TextBox", row)
    box.Size = UDim2.new(0, 82, 0, 20)
    box.Position = UDim2.new(0, 120, 0.5, -10)
    box.BackgroundColor3 = Color3.fromRGB(18, 13, 3)
    box.BorderSizePixel = 0
    box.PlaceholderText = "Min"
    box.Text = _G.StealFormatMinGenValue and _G.StealFormatMinGenValue((_G.StealConfig and _G.StealConfig.MinGenValue) or 0) or ""
    box.TextColor3 = Color3.fromRGB(185, 95, 255)
    box.PlaceholderColor3 = Color3.fromRGB(120, 95, 35)
    box.Font = Enum.Font.GothamBold
    box.TextSize = 11
    box.ClearTextOnFocus = false
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    local boxStroke = Instance.new("UIStroke", box)
    boxStroke.Color = BORDER_COLOR; boxStroke.Thickness = 1
    _G._MainStealMinBox = box

    box.FocusLost:Connect(function()
        local v = (_G.StealParseMinGenText and _G.StealParseMinGenText(box.Text)) or 0
        if _G.StealSetMinGenValue then
            _G.StealSetMinGenValue(v)
        elseif _G.StealConfig then
            _G.StealConfig.MinGenValue = v
            if _G.saveStealConfig then pcall(_G.saveStealConfig) end
            box.Text = _G.StealFormatMinGenValue and _G.StealFormatMinGenValue(v) or tostring(v)
        end
    end)
end

local infoRowY = stealMinRowY + ROW_H + GAP

local MAIN_H = infoRowY + 14 + PAD
MainFrame.Size = UDim2.new(0, GUI_W, 0, MAIN_H)
_G._mainFrame = MainFrame
pcall(addGlowBorder, MainFrame)

-- ═══════════════════════════════════════
-- ═══════════════════════════════════════
local function loadSavedKeybinds()
	local function loadKey(attrName, gKey, default)
		local saved = SettingsObj:GetAttribute(attrName)
		_G[gKey] = (saved and Enum.KeyCode[saved]) and saved or default
	end
	loadKey("SavedTPKey",         "TPKeybind",          "V")
	loadKey("SavedInstantResetKey","InstantResetKeybind","X")
	loadKey("SavedCloneKey",      "CloneKeybind",       "B")
	loadKey("SavedRJKey",         "RJKeybind",          "R")
	loadKey("SavedKickKey",       "KickKeybind",        "Z")
	loadKey("SavedClickAPKey",    "ClickAPKeybind",     "F")
	loadKey("SavedAPKey",         "APKeybind",          "G")
	loadKey("SavedRagdollSelfKey","RagdollSelfKeybind", "H")
	loadKey("SavedAutoTurretKey", "AutoTurretKeybind",  "C")
	loadKey("SavedCarpetSpeedKey","CarpetSpeedKeybind", "Q")
	loadKey("SavedFloatKey",      "FloatKeybind",       "U")
	loadKey("SavedKBPanelKey",    "KeybindPanelKeybind","G")
end
loadSavedKeybinds()

-- KB panel: pre-declared so they're accessible outside the setup do-block
local KBFrame, KBClose, KBTitle, KBHint
local keybindPanelVisible = false
local listeningSlot = nil
local _kbRows = {}
local KB_W, KB_H
local _kbTabContents = {}
local kbSwitchTab

-- ═══════════════════════════════════════
-- KEYBIND SETTINGS GUI
-- Toggle with G key
-- ═══════════════════════════════════════
do -- KB setup: reduces register pressure
local KeybindGui = Instance.new("ScreenGui")
KeybindGui.Name = "KeybindPanel"
KeybindGui.ResetOnSpawn = false
KeybindGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
do
	local _ok = pcall(function() KeybindGui.Parent = game:GetService("CoreGui") end)
	if not _ok or not KeybindGui.Parent then
		pcall(function() if gethui then KeybindGui.Parent = gethui() end end)
	end
	if not KeybindGui.Parent then KeybindGui.Parent = playerGui end
end
if protect_gui then pcall(function() protect_gui(KeybindGui) end) end

-- ── Layout constants ──────────────────────────────────────────────────────────
local SIDEBAR_W  = 180        -- sidebar navigation width
KB_W             = 466        -- content area width
local PANEL_W    = 660        -- total panel width (180 sidebar + 466 content + 14 pad)
local HEADER_H   = 40
local TAB_BAR_H  = 0
local KB_PAD     = 12
local KB_ROW     = 36
local KB_GAP     = 6
local KB_TAB_H   = 30
local KB_TITLE_H = 26
local KB_CONTENT_Y = HEADER_H

-- ── Outer frame ───────────────────────────────────────────────────────────────
KBFrame = Instance.new("Frame")
KBFrame.Name                 = "KBFrame"
KBFrame.BackgroundColor3     = Color3.fromRGB(20, 20, 38)
KBFrame.BackgroundTransparency = 0.75
KBFrame.BorderSizePixel      = 0
KBFrame.Active               = true
KBFrame.Visible              = false
KBFrame.Parent               = KeybindGui
if not _G._hubPanelFrames then _G._hubPanelFrames={} end; table.insert(_G._hubPanelFrames, KBFrame)

do
    local _sdKBF={{0.908,0.753,2,0.0042},{0.037,0.64,2,0.0047},{0.72,0.105,2,0.0042},{0.543,0.38,2,0.0065},{0.332,0.111,2,0.0046},{0.937,0.509,2,0.0042},{0.945,0.331,3,0.0063},{0.4,0.13,2,0.0056},{0.617,0.739,3,0.006},{0.347,0.336,2,0.0044},{0.112,0.518,3,0.0044},{0.721,0.729,3,0.0044},{0.419,0.831,2,0.0065},{0.747,0.822,3,0.0049},{0.629,0.085,3,0.0038},{0.506,0.634,3,0.0064},{0.674,0.346,2,0.0057},{0.843,0.2,3,0.0044},{0.346,0.226,3,0.0046},{0.517,0.842,2,0.0058},{0.89,0.419,3,0.005},{0.877,0.693,3,0.0064},{0.87,0.77,3,0.0046},{0.424,0.59,3,0.0059},{0.596,0.718,2,0.0055},{0.226,0.445,3,0.006},{0.45,0.481,2,0.0037},{0.241,0.382,2,0.0053},{0.094,0.281,2,0.0057},{0.953,0.517,2,0.0039}}
    local _sfKBF,_soKBF={},{}
    for i,sp in ipairs(_sdKBF) do
        local s=Instance.new("Frame",KBFrame)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.3
        s.BorderSizePixel=0;s.ZIndex=10
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfKBF[i]=s;_soKBF[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfKBF) do
            if not s or not s.Parent then continue end
            _soKBF[i]=(_soKBF[i]-_sdKBF[i][4]*dt)%1
            s.Position=UDim2.new(_soKBF[i],0,_sdKBF[i][2],0)
            s.BackgroundTransparency=0.3+math.abs(math.sin(tick()*0.8+i*0.7))*0.5
        end
    end)
end
Instance.new("UICorner", KBFrame).CornerRadius = UDim.new(0, 14)
local _kbStroke = Instance.new("UIStroke", KBFrame)
_kbStroke.Color = BORDER_COLOR; _kbStroke.Thickness = 1.5
if not _G._hubPanelStrokes then _G._hubPanelStrokes = {} end
table.insert(_G._hubPanelStrokes, _kbStroke)

-- ── Header bar ────────────────────────────────────────────────────────────────
local kbHeader = Instance.new("Frame")
kbHeader.Size               = UDim2.new(1, 0, 0, HEADER_H)
kbHeader.BackgroundColor3   = Color3.fromRGB(22, 22, 42)
kbHeader.BorderSizePixel    = 0
kbHeader.Parent             = KBFrame
Instance.new("UICorner", kbHeader).CornerRadius = UDim.new(0, 14)
local _hFill = Instance.new("Frame", kbHeader)
_hFill.Size               = UDim2.new(1, 0, 0, 14)
_hFill.Position           = UDim2.new(0, 0, 1, -14)
_hFill.BackgroundColor3   = Color3.fromRGB(22, 22, 42)
_hFill.BorderSizePixel    = 0
local _hLine = Instance.new("Frame", kbHeader)
_hLine.Size               = UDim2.new(1, 0, 0, 1)
_hLine.Position           = UDim2.new(0, 0, 1, -1)
_hLine.BackgroundColor3   = BORDER_COLOR
_hLine.BorderSizePixel    = 0

-- Title
KBTitle = Instance.new("TextLabel")
KBTitle.Size                = UDim2.new(1, -16, 0, 30)
KBTitle.Position            = UDim2.new(0, 8, 0.5, -15)
KBTitle.BackgroundTransparency = 1
KBTitle.Text                = "IDF HUB  —  settings"
KBTitle.TextColor3          = WHITE
KBTitle.Font                = Enum.Font.GothamBold
KBTitle.TextSize            = 14
KBTitle.TextXAlignment      = Enum.TextXAlignment.Center
KBTitle.Parent              = kbHeader
local _kbSepLine = Instance.new("Frame", kbHeader)
_kbSepLine.Size = UDim2.new(1,-20,0,1); _kbSepLine.Position = UDim2.new(0,10,1,-1)
_kbSepLine.BackgroundColor3 = Color3.fromRGB(255,255,255); _kbSepLine.BackgroundTransparency = 0.7
_kbSepLine.BorderSizePixel = 0; _kbSepLine.ZIndex = 3
local _kbTitleStroke = {ApplyStrokeMode=0}  -- dummy

do
    local _sdKB={{0.03,0.2,3,0.007},{0.1,0.7,2,0.009},{0.18,0.3,3,0.006},{0.25,0.8,2,0.008},{0.32,0.15,3,0.01},{0.4,0.6,2,0.007},{0.47,0.85,3,0.009},{0.54,0.25,2,0.006},{0.61,0.7,3,0.008},{0.68,0.4,2,0.01},{0.75,0.8,3,0.007},{0.82,0.2,2,0.009},{0.89,0.6,3,0.006},{0.95,0.35,2,0.008},{0.14,0.5,3,0.007},{0.35,0.4,2,0.009},{0.56,0.55,3,0.006},{0.72,0.15,2,0.008},{0.85,0.75,3,0.007},{0.06,0.9,2,0.01},{0.28,0.65,3,0.009},{0.5,0.1,2,0.007},{0.78,0.5,3,0.008},{0.92,0.85,2,0.006},{0.44,0.75,3,0.009}}
    local _sfKB,_soKB={},{}
    for i,sp in ipairs(_sdKB) do
        local s=Instance.new("Frame",KBTitle)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0
        s.BorderSizePixel=0;s.ZIndex=4
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfKB[i]=s;_soKB[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfKB) do
            if not s or not s.Parent then continue end
            _soKB[i]=(_soKB[i]-_sdKB[i][4]*dt)%1
            s.Position=UDim2.new(_soKB[i],0,_sdKB[i][2],0)
            s.BackgroundTransparency=math.abs(math.sin(tick()*1.5+i*0.6))*0.5
        end
    end)
end

-- ── Close button ──────────────────────────────────────────────────────────────
KBClose = Instance.new("TextButton")
KBClose.Size                = UDim2.new(0, 26, 0, 26)
KBClose.Position            = UDim2.new(1, -36, 0.5, -13)
KBClose.BackgroundColor3    = Color3.fromRGB(80, 22, 22)
KBClose.BorderSizePixel     = 0
KBClose.Text                = "×"
KBClose.TextColor3          = WHITE
KBClose.Font                = Enum.Font.GothamBold
KBClose.TextSize            = 18
KBClose.AutoButtonColor     = false
KBClose.Parent              = kbHeader
Instance.new("UICorner", KBClose).CornerRadius = UDim.new(1, 0)
local _kcStr = Instance.new("UIStroke", KBClose)
_kcStr.Color = Color3.fromRGB(160, 50, 50); _kcStr.Thickness = 1

-- ── Content frames ────────────────────────────────────────────────────────────
local _kbActiveTab = nil
_kbTabContents   = {}

local TAB_DEFS = { "Main", "Keybinds", "TP Settings", "ESP", "UI/Hides", "Colors" }

for _, tabName in ipairs(TAB_DEFS) do
    local tabKey = tabName:lower()
    local contentFrame
    if tabKey == "keybinds" or tabKey == "tp settings" or tabKey == "esp" then
        contentFrame = Instance.new("ScrollingFrame")
        contentFrame.ScrollBarThickness     = 3
        contentFrame.ScrollBarImageColor3   = BORDER_COLOR
        contentFrame.CanvasSize             = UDim2.new(0, 0, 0, 0)
        contentFrame.AutomaticCanvasSize    = Enum.AutomaticSize.Y
        contentFrame.ScrollingDirection     = Enum.ScrollingDirection.Y
        contentFrame.ElasticBehavior        = Enum.ElasticBehavior.Never
    else
        contentFrame = Instance.new("Frame")
    end
    contentFrame.Name               = "Tab_" .. tabName
    contentFrame.BackgroundTransparency = 1
    contentFrame.BorderSizePixel    = 0
    contentFrame.Visible            = false
    contentFrame.Parent             = KBFrame
    _kbTabContents[tabKey]          = contentFrame
end

-- ── Left sidebar ──────────────────────────────────────────────────────────────
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -HEADER_H)
sidebar.Position = UDim2.new(0, 0, 0, HEADER_H)
sidebar.BackgroundColor3 = Color3.fromRGB(16, 16, 32)
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 12
sidebar.Parent = KBFrame

local _sbDiv = Instance.new("Frame", sidebar)
_sbDiv.Size = UDim2.new(0, 1, 1, 0)
_sbDiv.Position = UDim2.new(1, -1, 0, 0)
_sbDiv.BackgroundColor3 = Color3.fromRGB(42, 42, 68)
_sbDiv.BorderSizePixel = 0
_sbDiv.ZIndex = 12

local avCircle = Instance.new("Frame")
avCircle.Size = UDim2.new(0, 56, 0, 56)
avCircle.Position = UDim2.new(0.5, -28, 0, 14)
avCircle.BackgroundColor3 = Color3.fromRGB(32, 32, 52)
avCircle.BorderSizePixel = 0
avCircle.ZIndex = 13
avCircle.Parent = sidebar
Instance.new("UICorner", avCircle).CornerRadius = UDim.new(1, 0)
local _avStr = Instance.new("UIStroke", avCircle)
_avStr.Color = Color3.fromRGB(55, 55, 85); _avStr.Thickness = 1.5
pcall(function()
    local img = Instance.new("ImageLabel")
    img.Size = UDim2.new(1, 0, 1, 0)
    img.BackgroundTransparency = 1
    img.ZIndex = 14
    img.Image = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=60&h=60"
    img.Parent = avCircle
    Instance.new("UICorner", img).CornerRadius = UDim.new(1, 0)
end)

local NAV_DEFS = {
    { label = "Player",   key = "main"        },
    { label = "Keybinds", key = "keybinds"    },
    { label = "Teleport", key = "tp settings" },
    { label = "ESP",      key = "esp"         },
    { label = "Display",  key = "ui/hides"    },
    { label = "Colors",   key = "colors"      },
}
local _navItems = {}
local _NAV_START_Y = 82

for ni, nd in ipairs(NAV_DEFS) do
    local iy = _NAV_START_Y + (ni - 1) * 42

    local ind = Instance.new("Frame", sidebar)
    ind.Size = UDim2.new(0, 3, 0, 20)
    ind.Position = UDim2.new(0, 0, 0, iy + 9)
    ind.BackgroundColor3 = BORDER_COLOR
    ind.BorderSizePixel = 0
    ind.Visible = false
    ind.ZIndex = 14
    Instance.new("UICorner", ind).CornerRadius = UDim.new(0, 2)

    local nb = Instance.new("TextButton", sidebar)
    nb.Size = UDim2.new(1, -12, 0, 38)
    nb.Position = UDim2.new(0, 6, 0, iy)
    nb.BackgroundColor3 = Color3.fromRGB(35, 35, 58)
    nb.BackgroundTransparency = 1
    nb.BorderSizePixel = 0
    nb.Text = "  " .. nd.label
    nb.TextColor3 = Color3.fromRGB(115, 115, 150)
    nb.Font = Enum.Font.GothamBold
    nb.TextSize = 13
    nb.TextXAlignment = Enum.TextXAlignment.Left
    nb.AutoButtonColor = false
    nb.ZIndex = 13
    Instance.new("UICorner", nb).CornerRadius = UDim.new(0, 8)

    _navItems[nd.key] = { btn = nb, ind = ind }
end

kbSwitchTab = function(tabKey)
    _kbActiveTab = tabKey
    for k, t in pairs(_navItems) do
        if k == tabKey then
            t.btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            t.btn.BackgroundTransparency = 0.75
            t.btn.BackgroundColor3 = Color3.fromRGB(35, 35, 58)
            t.ind.Visible = true
        else
            t.btn.TextColor3 = Color3.fromRGB(115, 115, 150)
            t.btn.BackgroundTransparency = 1
            t.ind.Visible = false
        end
    end
    for k, frame in pairs(_kbTabContents) do
        frame.Visible = (k == tabKey)
    end
end

for _, nd in ipairs(NAV_DEFS) do
    _navItems[nd.key].btn.MouseButton1Click:Connect(function()
        kbSwitchTab(nd.key)
    end)
end

-- ── MAIN TAB content ─────────────────────────────────────────────────────────
local mainContent = _kbTabContents["main"]

local _MT_ROW    = 52   -- Haze Hub style row height
local _MT_GAP    = 8    -- gap between rows
local _MT_PAD    = KB_PAD
local _MT_START  = 28   -- y offset (leaves room for section header)

do
    local secLbl = Instance.new("TextLabel")
    secLbl.Size = UDim2.new(0, KB_W - _MT_PAD * 2, 0, 14)
    secLbl.Position = UDim2.new(0, _MT_PAD, 0, 8)
    secLbl.BackgroundTransparency = 1
    secLbl.Text = "PLAYER"
    secLbl.TextColor3 = Color3.fromRGB(100, 100, 135)
    secLbl.Font = Enum.Font.GothamBold
    secLbl.TextSize = 10
    secLbl.TextXAlignment = Enum.TextXAlignment.Left
    secLbl.Parent = mainContent
    local secLine = Instance.new("Frame", mainContent)
    secLine.Size = UDim2.new(0, KB_W - _MT_PAD * 2 - 58, 0, 1)
    secLine.Position = UDim2.new(0, _MT_PAD + 58, 0, 15)
    secLine.BackgroundColor3 = Color3.fromRGB(48, 48, 72)
    secLine.BorderSizePixel = 0
end

local _MT_DESCS = {
    ["Auto Steal"]       = "Automatically steal brainrots",
    ["Anti-Bee & Disco"] = "Prevents bee effects and disco lighting",
    ["Auto TP on Join"]  = "Auto-teleport to brainrot on join",
    ["Ragdoll"]          = "Prevents ragdoll effects (V2 - Aggressive)",
    ["Anti Body Swap"]        = "Prevents body swap attacks",
    ["Auto Reset on Balloon"] = "Auto-reset character when landing on a balloon",
    ["Infinite Jump"]         = "Jump infinitely in the air",
    ["Admin Control"]    = "Enables admin control panel",
}

local function makeMainToggle(labelText, yPos, initState)
    local rowW = KB_W - _MT_PAD * 2
    local descText = _MT_DESCS[labelText] or ""

    local row = Instance.new("Frame")
    row.Size               = UDim2.new(0, rowW, 0, _MT_ROW)
    row.Position           = UDim2.new(0, _MT_PAD, 0, yPos)
    row.BackgroundColor3   = Color3.fromRGB(28, 28, 48)
    row.BackgroundTransparency = 0.25
    row.BorderSizePixel    = 0
    row.Parent             = mainContent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)

    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(0, rowW - 82, 0, 22)
    lbl.Position           = UDim2.new(0, 14, 0, 6)
    lbl.BackgroundTransparency = 1
    lbl.Text               = labelText
    lbl.TextColor3         = Color3.fromRGB(240, 240, 250)
    lbl.Font               = Enum.Font.GothamBold
    lbl.TextSize           = 13
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.Parent             = row

    local descLbl = Instance.new("TextLabel")
    descLbl.Size           = UDim2.new(0, rowW - 82, 0, 16)
    descLbl.Position       = UDim2.new(0, 14, 0, 28)
    descLbl.BackgroundTransparency = 1
    descLbl.Text           = descText
    descLbl.TextColor3     = Color3.fromRGB(120, 120, 158)
    descLbl.Font           = Enum.Font.Gotham
    descLbl.TextSize       = 11
    descLbl.TextXAlignment = Enum.TextXAlignment.Left
    descLbl.Parent         = row

    local pill = Instance.new("Frame")
    pill.Size              = UDim2.new(0, 44, 0, 24)
    pill.Position          = UDim2.new(1, -56, 0.5, -12)
    pill.BackgroundColor3  = initState and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
    pill.BorderSizePixel   = 0
    pill.Parent            = row
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local dot = Instance.new("Frame")
    dot.Size               = UDim2.new(0, 18, 0, 18)
    dot.Position           = initState and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    dot.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
    dot.BorderSizePixel    = 0
    dot.Parent             = pill
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    local btn = Instance.new("TextButton")
    btn.Size               = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text               = ""
    btn.AutoButtonColor    = false
    btn.Parent             = row

    local function setBtn(on)
        pill.BackgroundColor3 = on and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
        dot.Position          = on and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    end

    return btn, setBtn
end

-- ── 1. AUTO STEAL ─────────────────────────────────────────────────────────────
-- Controls whether the Steal Target panel's auto-steal is active.
-- Uses the existing _G.AutoStealEnable / _G.AutoStealDisable API.
local _autoStealSettingOn = true   -- default: on (matches script startup behaviour)
_G._autoStealSettingOn = _autoStealSettingOn

local asBtn, asSet = makeMainToggle("Auto Steal", _MT_START, _autoStealSettingOn)
asBtn.MouseButton1Click:Connect(function()
    _autoStealSettingOn = not _autoStealSettingOn
    _G._autoStealSettingOn = _autoStealSettingOn
    asSet(_autoStealSettingOn)
    if _autoStealSettingOn then
        if _G.AutoStealEnable then pcall(_G.AutoStealEnable) end
    else
        if _G.AutoStealDisable then pcall(_G.AutoStealDisable) end
    end
    pcall(function() SettingsObj:SetAttribute("SavedAutoSteal", _autoStealSettingOn) end)
end)
-- Restore saved state
pcall(function()
    local saved = SettingsObj:GetAttribute("SavedAutoSteal")
    if saved ~= nil then
        _autoStealSettingOn = saved
        _G._autoStealSettingOn = saved
        asSet(saved)
        if not saved and _G.AutoStealDisable then pcall(_G.AutoStealDisable) end
    end
end)


-- ── 3. AUTO TP ON JOIN ────────────────────────────────────────────────────────
-- When enabled: the TP module's first-character auto-snipe fires on join.
-- When disabled: the join snipe is suppressed (flag read by onCharacterSpawn).
-- Anti-Bee & Anti-Disco
local AntiBeeDisco = {
    running = false,
    connections = {},
    originalMoveFunction = nil,
    controlsProtected = false,
    badLightingNames = { Blue = true, DiscoEffect = true, BeeBlur = true, ColorCorrection = true },
}

function AntiBeeDisco:nuke(obj)
    if not obj or not obj.Parent then return end
    if self.badLightingNames[obj.Name] then
        pcall(function() obj:Destroy() end)
    end
end

function AntiBeeDisco:disconnectAll()
    for _, conn in ipairs(self.connections) do
        if typeof(conn) == "RBXScriptConnection" then
            pcall(function() conn:Disconnect() end)
        end
    end
    self.connections = {}
end

function AntiBeeDisco:protectControls()
    if self.controlsProtected then return end
    pcall(function()
        local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local PlayerModule = PlayerScripts and PlayerScripts:FindFirstChild("PlayerModule")
        if not PlayerModule then return end
        local Controls = require(PlayerModule):GetControls()
        if not Controls then return end

        if not self.originalMoveFunction then
            self.originalMoveFunction = Controls.moveFunction
        end

        local function protectedMoveFunction(ctrlSelf, moveVector, relativeToCamera)
            if self.originalMoveFunction then
                self.originalMoveFunction(ctrlSelf, moveVector, relativeToCamera)
            end
        end

        table.insert(self.connections, RunService.Heartbeat:Connect(function()
            if not self.running then return end
            if Controls.moveFunction ~= protectedMoveFunction then
                Controls.moveFunction = protectedMoveFunction
            end
        end))

        Controls.moveFunction = protectedMoveFunction
        self.controlsProtected = true
    end)
end

function AntiBeeDisco:restoreControls()
    if not self.controlsProtected then return end
    pcall(function()
        local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local PlayerModule = PlayerScripts and PlayerScripts:FindFirstChild("PlayerModule")
        if not PlayerModule then return end
        local Controls = require(PlayerModule):GetControls()
        if Controls and self.originalMoveFunction then
            Controls.moveFunction = self.originalMoveFunction
            self.controlsProtected = false
        end
    end)
end

function AntiBeeDisco:blockBuzzingSound()
    pcall(function()
        local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local beeScript = playerScripts and playerScripts:FindFirstChild("Bee", true)
        if beeScript then
            local buzzing = beeScript:FindFirstChild("Buzzing")
            if buzzing and buzzing:IsA("Sound") then
                buzzing:Stop()
                buzzing.Volume = 0
            end
        end
    end)
end

function AntiBeeDisco:Enable()
    if self.running then return end
    self.running = true

    for _, inst in ipairs(Lighting:GetDescendants()) do
        self:nuke(inst)
    end

    table.insert(self.connections, Lighting.DescendantAdded:Connect(function(obj)
        if not self.running then return end
        self:nuke(obj)
    end))

    self:protectControls()

    table.insert(self.connections, RunService.Heartbeat:Connect(function()
        if not self.running then return end
        self:blockBuzzingSound()
    end))
end

function AntiBeeDisco:Disable()
    if not self.running then return end
    self.running = false
    self:restoreControls()
    self:disconnectAll()
end

_G.ANTI_BEE_DISCO = AntiBeeDisco

local _antiBeeDiscoOn = false
local abdBtn, abdSet = makeMainToggle("Anti-Bee & Disco", _MT_START + (_MT_ROW + _MT_GAP), _antiBeeDiscoOn)
abdBtn.MouseButton1Click:Connect(function()
    _antiBeeDiscoOn = not _antiBeeDiscoOn
    abdSet(_antiBeeDiscoOn)
    if _antiBeeDiscoOn then
        AntiBeeDisco:Enable()
    else
        AntiBeeDisco:Disable()
    end
    pcall(function() SettingsObj:SetAttribute("SavedAntiBeeDisco", _antiBeeDiscoOn) end)
end)

pcall(function()
    local saved = SettingsObj:GetAttribute("SavedAntiBeeDisco")
    if saved == true then
        _antiBeeDiscoOn = true
        abdSet(true)
        AntiBeeDisco:Enable()
    end
end)

local _autoTPOnJoinOn = true   -- default: on (matches original behaviour)
_G._autoTPOnJoin = _autoTPOnJoinOn

local atpBtn, atpSet = makeMainToggle("Auto TP on Join", _MT_START + (_MT_ROW + _MT_GAP) * 2, _autoTPOnJoinOn)
atpBtn.MouseButton1Click:Connect(function()
    _autoTPOnJoinOn = not _autoTPOnJoinOn
    _G._autoTPOnJoin = _autoTPOnJoinOn
    atpSet(_autoTPOnJoinOn)
    pcall(function() SettingsObj:SetAttribute("SavedAutoTPOnJoin", _autoTPOnJoinOn) end)
end)
-- Restore saved state
pcall(function()
    local saved = SettingsObj:GetAttribute("SavedAutoTPOnJoin")
    if saved ~= nil then
        _autoTPOnJoinOn = saved
        _G._autoTPOnJoin = saved
        atpSet(saved)
    end
end)

-- ── ANTI BODY SWAP (ported from dtc.txt) ────────────────────────────────────
-- Detects another player swapping into your body with a Body Swap Potion and
-- automatically swaps back. Always wired; gate on/off via _G.AntiBodySwapEnabled.
if _G.AntiBodySwapEnabled == nil then _G.AntiBodySwapEnabled = true end
task.spawn(function()
    local _abs_POTION_NAME     = "Body Swap Potion"
    local _abs_HOLDER_JUMP_MIN = 3
    local _abs_SWAP_RADIUS     = 5
    local _abs_LOCAL_MOVED_MIN = 3
    local _abs_PER_PLAYER_CD   = 30

    local Players     = game:GetService("Players")
    local RunService  = game:GetService("RunService")
    local LocalPlayer = Players.LocalPlayer

    local hitCooldowns   = {}
    local localJustFired = false
    local prevHolderPos  = nil
    local prevLocalPos   = nil

    local function getLocalHRP()
        local char = LocalPlayer.Character
        return char and char:FindFirstChild("HumanoidRootPart")
    end

    local function getHolder()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer
               and plr.Character
               and plr.Character:FindFirstChild(_abs_POTION_NAME) then
                return plr
            end
        end
        return nil
    end

    local function hookLocalPotion()
        local char = LocalPlayer.Character
        if not char then return end
        local function hook(potion)
            potion.Activated:Connect(function()
                localJustFired = true
                task.delay(1, function() localJustFired = false end)
            end)
        end
        local existing = char:FindFirstChild(_abs_POTION_NAME)
        if existing then hook(existing) end
        char.ChildAdded:Connect(function(child)
            if child.Name == _abs_POTION_NAME then hook(child) end
        end)
    end
    LocalPlayer.CharacterAdded:Connect(function()
        task.wait(0.1)
        hookLocalPotion()
    end)
    hookLocalPotion()

    local function swapBack(targetPlayer)
        pcall(function()
            local char = LocalPlayer.Character
            if not char then return end
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hum then return end

            local potion = char:FindFirstChild(_abs_POTION_NAME)
                        or (LocalPlayer:FindFirstChild("Backpack") and LocalPlayer.Backpack:FindFirstChild(_abs_POTION_NAME))
            if not potion then return end

            hum:EquipTool(potion)
            task.wait(0.05)

            local targetChar = targetPlayer.Character
            local targetHRP  = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
            local localHRP   = getLocalHRP()
            if targetHRP and localHRP then
                localHRP.CFrame = CFrame.lookAt(
                    targetHRP.Position,
                    targetHRP.Position + targetHRP.CFrame.LookVector
                )
            end

            if LocalPlayer:GetAttribute("Stealing") then
                while LocalPlayer:GetAttribute("Stealing") do task.wait() end
                task.wait(0.2)
                hum:EquipTool(potion)
                task.wait(0.05)
                if targetPlayer.Character then
                    local tHRP = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
                    local lHRP = getLocalHRP()
                    if tHRP and lHRP then
                        lHRP.CFrame = CFrame.lookAt(
                            tHRP.Position,
                            tHRP.Position + tHRP.CFrame.LookVector
                        )
                    end
                end
            end

            potion = char:FindFirstChild(_abs_POTION_NAME)
            if potion then potion:Activate() end
        end)
    end

    RunService.Heartbeat:Connect(function()
        if not _G.AntiBodySwapEnabled then
            prevHolderPos = nil
            prevLocalPos  = nil
            return
        end

        local holder = getHolder()
        if not holder then
            prevHolderPos = nil
            prevLocalPos  = nil
            return
        end

        local cd = hitCooldowns[holder.Name]
        if cd and tick() - cd < _abs_PER_PLAYER_CD then return end

        local holderHRP = holder.Character and holder.Character:FindFirstChild("HumanoidRootPart")
        local localHRP  = getLocalHRP()
        if not holderHRP or not localHRP then return end

        local currHolder = holderHRP.Position
        local currLocal  = localHRP.Position

        if prevHolderPos and prevLocalPos then
            local holderJumped        = (currHolder - prevHolderPos).Magnitude
            local holderNowAtMyOldPos = (currHolder - prevLocalPos).Magnitude < _abs_SWAP_RADIUS
            local iMoved              = (currLocal  - prevLocalPos).Magnitude > _abs_LOCAL_MOVED_MIN

            if holderJumped > _abs_HOLDER_JUMP_MIN
               and holderNowAtMyOldPos
               and iMoved
               and not localJustFired then
                hitCooldowns[holder.Name] = tick()
                task.spawn(function() swapBack(holder) end)
            end
        end

        prevHolderPos = currHolder
        prevLocalPos  = currLocal
    end)
end)

-- ── ANTI-RAGDOLL V2 ──────────────────────────────────────────────────────────
local _arv_RunService = game:GetService("RunService")
local _arv_LP         = Players.LocalPlayer

local AntiRagdollV2Data   = { antiRagdollConns = {} }
local antiRagdollConns    = AntiRagdollV2Data.antiRagdollConns
local cleanRagV2Scheduled = false

local function stopAntiRagdollV2()
    cleanRagV2Scheduled = false
    for _, c in ipairs(antiRagdollConns) do pcall(function() c:Disconnect() end) end
    AntiRagdollV2Data.antiRagdollConns = {}
    antiRagdollConns = AntiRagdollV2Data.antiRagdollConns
end

local function cleanRagdollV2(char)
    if not char then return end
    local carpetEquipped = false
    pcall(function()
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, obj in ipairs(hrp:GetChildren()) do
                if obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                    carpetEquipped = true; break
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
            local pm = _arv_LP:FindFirstChild("PlayerScripts")
            if pm then pm = pm:FindFirstChild("PlayerModule") end
            if pm then require(pm):GetControls():Enable() end
        end)
    end)
end

local function cleanRagdollV2Debounced(char)
    if cleanRagV2Scheduled then return end
    cleanRagV2Scheduled = true
    task.defer(function()
        cleanRagV2Scheduled = false
        if char and char.Parent then cleanRagdollV2(char) end
    end)
end

local function isRagdollRelated(obj)
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
                for _, obj in ipairs(hrp:GetChildren()) do
                    if obj:IsA("BodyVelocity") or obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then
                        carpetActive = true; break
                    end
                end
            end)
            if not carpetActive then
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
            cleanRagdollV2(char)
            pcall(function() Workspace.CurrentCamera.CameraSubject = hum end)
            pcall(function()
                local pm = _arv_LP:FindFirstChild("PlayerScripts")
                if pm then pm = pm:FindFirstChild("PlayerModule") end
                if pm then require(pm):GetControls():Enable() end
            end)
        end
    end)
    table.insert(antiRagdollConns, c1)

    local c2 = char.DescendantAdded:Connect(function(desc)
        if isRagdollRelated(desc) then cleanRagdollV2Debounced(char) end
    end)
    table.insert(antiRagdollConns, c2)

    pcall(function()
        local pkg = game:GetService("ReplicatedStorage"):FindFirstChild("Packages")
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

    local c4 = _arv_RunService.Heartbeat:Connect(function()
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

local _arv2CharAddedConn

local function startAntiRagdollV2()
    local char = _arv_LP.Character
    if char then task.spawn(function() hookAntiRagV2(char) end) end
    if not _arv2CharAddedConn then
        _arv2CharAddedConn = _arv_LP.CharacterAdded:Connect(function(c)
            task.spawn(function() hookAntiRagV2(c) end)
        end)
    end
end

-- ── Toggle: Ragdoll (Anti-Ragdoll V2) ────────────────────────────────────────
local _arV2On = false
_G._antiRagdollV2On = _arV2On

local arv2Btn, arv2Set = makeMainToggle("Ragdoll", _MT_START + (_MT_ROW + _MT_GAP) * 3, _arV2On)
arv2Btn.MouseButton1Click:Connect(function()
    _arV2On = not _arV2On
    _G._antiRagdollV2On = _arV2On
    arv2Set(_arV2On)
    if _arV2On then
        startAntiRagdollV2()
    else
        stopAntiRagdollV2()
    end
    pcall(function() SettingsObj:SetAttribute("SavedAntiRagdollV2", _arV2On) end)
end)

-- ── Restore saved state ───────────────────────────────────────────────────────
pcall(function()
    local savedV2 = SettingsObj:GetAttribute("SavedAntiRagdollV2")
    if savedV2 == true then
        _arV2On = true; _G._antiRagdollV2On = true; arv2Set(true)
        startAntiRagdollV2()
    end
end)

-- ── Toggle: Anti Body Swap ────────────────────────────────────────────────────
local _absOn = _G.AntiBodySwapEnabled ~= false
_G.AntiBodySwapEnabled = _absOn
local absBtn, absSet = makeMainToggle("Anti Body Swap", _MT_START + (_MT_ROW + _MT_GAP) * 4, _absOn)
absBtn.MouseButton1Click:Connect(function()
    _absOn = not _absOn
    _G.AntiBodySwapEnabled = _absOn
    absSet(_absOn)
    pcall(function() SettingsObj:SetAttribute("SavedAntiBodySwap", _absOn) end)
end)
pcall(function()
    local saved = SettingsObj:GetAttribute("SavedAntiBodySwap")
    if saved ~= nil then
        _absOn = saved == true
        _G.AntiBodySwapEnabled = _absOn
        absSet(_absOn)
    end
end)

-- ── Toggle: Auto Reset on Balloon ────────────────────────────────────────────
local _autoResetBalloonOn    = false
local _autoResetBalloonConn  = nil
local _autoResetBalloonConns = {}
local _arbLastReset          = 0
local _arbJumpedAt           = 0

local function _arbDoReset()
    if tick() - _arbLastReset < 2 then return end
    _arbLastReset = tick()
    pcall(function() LocalPlayer:LoadCharacter() end)
    -- fallback: kill the humanoid if LoadCharacter doesn't fire
    task.delay(0.15, function()
        if tick() - _arbLastReset < 0.5 then
            pcall(function()
                local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if h and h.Health > 0 then h.Health = 0 end
            end)
        end
    end)
end

local function _arbWatchChar(char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        local sc = hum.StateChanged:Connect(function(_, new)
            if new == Enum.HumanoidStateType.Jumping then _arbJumpedAt = tick() end
        end)
        _autoResetBalloonConns[#_autoResetBalloonConns + 1] = sc
    end
end

-- connect to a single RemoteEvent and check velocity the frame after it fires
local function _arbTryConnect(v)
    if not v:IsA("RemoteEvent") then return end
    local c = v.OnClientEvent:Connect(function()
        if not _autoResetBalloonOn then return end
        if tick() - _arbJumpedAt < 0.5 then return end  -- ignore post-jump window
        -- defer: let the remote handler run first, then check effect
        task.defer(function()
            local char = LocalPlayer.Character
            local hrp  = char and char:FindFirstChild("HumanoidRootPart")
            if hrp and hrp.AssemblyLinearVelocity.Y > 25 then
                _arbDoReset()
            end
        end)
    end)
    _autoResetBalloonConns[#_autoResetBalloonConns + 1] = c
end

local function _setAutoResetBalloon(enabled)
    _autoResetBalloonOn = enabled
    if _autoResetBalloonConn then _autoResetBalloonConn:Disconnect(); _autoResetBalloonConn = nil end
    for _, c in ipairs(_autoResetBalloonConns) do pcall(function() c:Disconnect() end) end
    _autoResetBalloonConns = {}
    if not enabled then return end

    -- track jumps + char changes
    local cc = LocalPlayer.CharacterAdded:Connect(_arbWatchChar)
    _autoResetBalloonConns[#_autoResetBalloonConns + 1] = cc
    pcall(function() _arbWatchChar(LocalPlayer.Character) end)

    -- hook ALL RemoteEvents — balloon remote name is unknown so we cover everything
    pcall(function()
        for _, v in ipairs(game:GetDescendants()) do pcall(_arbTryConnect, v) end
    end)
    pcall(function()
        local c = game.DescendantAdded:Connect(function(v)
            if _autoResetBalloonOn then pcall(_arbTryConnect, v) end
        end)
        _autoResetBalloonConns[#_autoResetBalloonConns + 1] = c
    end)

    -- heartbeat: velocity spike fallback + physical contact
    local _prevVY = 0
    local _rp     = RaycastParams.new()
    _rp.FilterType = Enum.RaycastFilterType.Exclude
    _autoResetBalloonConn = RunService.Heartbeat:Connect(function()
        local char = LocalPlayer.Character
        if not char then _prevVY = 0; return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then _prevVY = 0; return end
        local vy = hrp.AssemblyLinearVelocity.Y
        if vy > 45 and _prevVY < 10 and tick() - _arbJumpedAt > 0.5 then
            _arbDoReset()
        end
        _prevVY = vy
        if hum.FloorMaterial ~= Enum.Material.Air then
            _rp.FilterDescendantsInstances = {char}
            local hit = workspace:Raycast(hrp.Position, Vector3.new(0, -4, 0), _rp)
            if hit and hit.Instance then
                local hn  = hit.Instance.Name:lower()
                local phn = (hit.Instance.Parent and hit.Instance.Parent.Name:lower()) or ""
                if hn:find("balloon") or phn:find("balloon") then _arbDoReset() end
            end
        end
    end)
end

local arbBtn, arbSet = makeMainToggle("Auto Reset on Balloon", _MT_START + (_MT_ROW + _MT_GAP) * 5, _autoResetBalloonOn)
arbBtn.MouseButton1Click:Connect(function()
    _autoResetBalloonOn = not _autoResetBalloonOn
    arbSet(_autoResetBalloonOn)
    _setAutoResetBalloon(_autoResetBalloonOn)
    pcall(function() SettingsObj:SetAttribute("SavedAutoResetBalloon", _autoResetBalloonOn) end)
end)
pcall(function()
    local saved = SettingsObj:GetAttribute("SavedAutoResetBalloon")
    if saved ~= nil then
        _autoResetBalloonOn = saved == true
        arbSet(_autoResetBalloonOn)
        _setAutoResetBalloon(_autoResetBalloonOn)
    end
end)

-- ── Toggle: Infinite Jump ─────────────────────────────────────────────────────
local _infJumpOn = false
local _infJumpConn = nil
local _ijInputBegan = nil
local _ijInputEnded = nil

local function _setInfiniteJump(enabled)
    _infJumpOn = enabled
    _G._infJumpEnabled = enabled
    if _infJumpConn  then _infJumpConn:Disconnect();  _infJumpConn  = nil end
    if _ijInputBegan then _ijInputBegan:Disconnect(); _ijInputBegan = nil end
    if _ijInputEnded then _ijInputEnded:Disconnect(); _ijInputEnded = nil end
    if not enabled then return end
    local isSpaceHeld = false
    _ijInputBegan = UserInputService.InputBegan:Connect(function(input, gp)
        if UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.Space then isSpaceHeld = true end
    end)
    _ijInputEnded = UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Space then isSpaceHeld = false end
    end)
    _infJumpConn = RunService.RenderStepped:Connect(function()
        if not isSpaceHeld then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end
        hrp.AssemblyLinearVelocity = Vector3.new(
            hrp.AssemblyLinearVelocity.X, 50, hrp.AssemblyLinearVelocity.Z)
    end)
end

local infJumpBtn, infJumpSet = makeMainToggle("Infinite Jump", _MT_START + (_MT_ROW + _MT_GAP) * 6, _infJumpOn)
infJumpBtn.MouseButton1Click:Connect(function()
    _infJumpOn = not _infJumpOn
    infJumpSet(_infJumpOn)
    _setInfiniteJump(_infJumpOn)
    pcall(function() SettingsObj:SetAttribute("SavedInfJump", _infJumpOn) end)
end)
-- Restore saved state
pcall(function()
    local saved = SettingsObj:GetAttribute("SavedInfJump")
    if saved == true then
        _infJumpOn = true
        infJumpSet(true)
        _setInfiniteJump(true)
    end
end)

-- ── Toggle: Admin Control ─────────────────────────────────────────────────────
local _adminControlOn = false  -- PATCH: desactive par defaut
_G._adminControlOn = false
local adminCtrlBtn, adminCtrlSet = makeMainToggle("Admin Control", _MT_START + (_MT_ROW + _MT_GAP) * 7, _adminControlOn)
adminCtrlBtn.MouseButton1Click:Connect(function()
    _adminControlOn = not _adminControlOn
    _G._adminControlOn = _adminControlOn
    adminCtrlSet(_adminControlOn)
    if _G._adminControlGui then
        _G._adminControlGui.Enabled = _adminControlOn
    end
    pcall(function() SettingsObj:SetAttribute("SavedAdminControl", _adminControlOn) end)
end)
-- Appliquer l'etat sauvegarde (ou le defaut false)
task.defer(function()
    local saved = false
    pcall(function()
        local v = SettingsObj:GetAttribute("SavedAdminControl")
        if type(v) == "boolean" then saved = v end
    end)
    _adminControlOn = saved
    adminCtrlSet(saved)
    if _G._adminControlGui then _G._adminControlGui.Enabled = saved end
end)

-- ── Toggle: Carpet Speed ────────────────────────────────────────────────────
do
    local _csOn = false
    local _csConn = nil
    local function _setCarpetSpeed(enabled)
        _csOn = enabled
        if _csConn then _csConn:Disconnect(); _csConn = nil end
        if not enabled then return end
        _csConn = RunService.Heartbeat:Connect(function()
            if not _csOn then return end
            local c = LocalPlayer.Character
            if not c then return end
            local hum = c:FindFirstChildOfClass("Humanoid")
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if not hum or not hrp then return end
            local toolNames = { "Flying Carpet", "Cupid's Wings", "Santa's Sleigh", "Witch's Broom", "Magic Carpet" }
            for _, n in ipairs(toolNames) do
                local t = c:FindFirstChild(n) or (LocalPlayer:FindFirstChild("Backpack") and LocalPlayer.Backpack:FindFirstChild(n))
                if t then
                    local hum2 = c:FindFirstChildOfClass("Humanoid")
                    if hum2 then pcall(function() hum2:EquipTool(t) end) end
                    break
                end
            end
            local md = hum.MoveDirection
            local keepY = hrp.AssemblyLinearVelocity.Y
            if md.Magnitude > 0 then
                hrp.AssemblyLinearVelocity = Vector3.new(md.X * 140, keepY, md.Z * 140)
            else
                hrp.AssemblyLinearVelocity = Vector3.new(0, keepY, 0)
            end
        end)
    end
    _G._setCarpetSpeed = _setCarpetSpeed

    local csBtn, csSet = makeMainToggle("Carpet Speed", _MT_START + (_MT_ROW + _MT_GAP) * 8, false)
    csBtn.MouseButton1Click:Connect(function()
        _csOn = not _csOn
        _setCarpetSpeed(_csOn)
        csSet(_csOn)
        pcall(function() SettingsObj:SetAttribute("SavedCarpetSpeed", _csOn) end)
    end)
    task.defer(function()
        local saved = false
        pcall(function()
            local v = SettingsObj:GetAttribute("SavedCarpetSpeed")
            if type(v) == "boolean" then saved = v end
        end)
        if saved then _csOn = true; _setCarpetSpeed(true); csSet(true) end
    end)

    -- Keybind (Q par défaut, configurable)
    task.spawn(function()
        game:GetService("UserInputService").InputBegan:Connect(function(input, gp)
            if UserInputService:GetFocusedTextBox() then return end
            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            local wantKey = _G.CarpetSpeedKey or "Q"
            if Enum.KeyCode[wantKey] and input.KeyCode == Enum.KeyCode[wantKey] then
                _csOn = not _csOn
                _setCarpetSpeed(_csOn)
                csSet(_csOn)
                pcall(function() SettingsObj:SetAttribute("SavedCarpetSpeed", _csOn) end)
            end
        end)
    end)
end

-- ── Toggle: Float ────────────────────────────────────────────────────────────
-- Float supprimé du main
_G._floatActive = false
_G._autoFloatPending = false
_G._targetFloatY = nil
_G.FloatToggle = function() end  -- stub no-op pour compatibilité

-- Auto Clone on High Steal supprimé du main
local _autoCloneOnHighSteal = false
_G._autoCloneOnHighSteal = false

-- ── Instant Reset: always on, triggered only by keybind (default X) ──────────
-- Not a toggle; always active. Press the keybind to execute a reset.
_G._instantResetEnabled = true

-- ── KEYBINDS TAB content ─────────────────────────────────────────────────────
local keybindsContent = _kbTabContents["keybinds"]

-- Hint label inside keybinds tab
KBHint = Instance.new("TextLabel")
KBHint.Size = UDim2.new(1, -KB_PAD*2, 0, 16)
KBHint.Position = UDim2.new(0, KB_PAD, 0, 4)
KBHint.BackgroundTransparency = 1
KBHint.Text = "Click a button then press any key to remap"
KBHint.TextColor3 = Color3.fromRGB(140, 140, 140)
KBHint.Font = Enum.Font.Gotham
KBHint.TextSize = 11
KBHint.TextXAlignment = Enum.TextXAlignment.Left
KBHint.TextWrapped = true
KBHint.Parent = keybindsContent

-- Separator under hint
local KBHintSep = Instance.new("Frame")
KBHintSep.Size = UDim2.new(1, 0, 0, 1)
KBHintSep.Position = UDim2.new(0, 0, 0, 24)
KBHintSep.BackgroundColor3 = Color3.fromRGB(42, 42, 68)
KBHintSep.BorderSizePixel = 0
KBHintSep.Parent = keybindsContent

-- Row builder offset (relative to keybindsContent)
local _kbRowsStartY = 30
_kbRows = {}

local KEYBIND_DEFS = {
	{ label = "Teleport",       gKey = "TPKeybind",            attrKey = "SavedTPKey",           default = "V" },
	{ label = "Instant Reset",  gKey = "InstantResetKeybind",  attrKey = "SavedInstantResetKey",  default = "X" },
	{ label = "Clone",          gKey = "CloneKeybind",         attrKey = "SavedCloneKey",         default = "B" },
	{ label = "Rejoin",         gKey = "RJKeybind",            attrKey = "SavedRJKey",            default = "R" },
	{ label = "Kick/Exit",      gKey = "KickKeybind",          attrKey = "SavedKickKey",          default = "Z" },
	{ label = "Click AP",       gKey = "ClickAPKeybind",       attrKey = "SavedClickAPKey",       default = "F" },
	{ label = "AP Toggle",      gKey = "APKeybind",             attrKey = "SavedAPKey",            default = "G" },
	{ label = "Ragdoll Self",   gKey = "RagdollSelfKeybind",    attrKey = "SavedRagdollSelfKey",   default = "H" },
	{ label = "Anti Turret",    gKey = "AutoTurretKeybind",    attrKey = "SavedAutoTurretKey",    default = "C" },
	{ label = "Carpet Speed",   gKey = "CarpetSpeedKeybind",   attrKey = "SavedCarpetSpeedKey",   default = "Q" },
	{ label = "KB Panel",       gKey = "KeybindPanelKeybind",  attrKey = "SavedKBPanelKey",       default = "G" },
}

local function makeKbRow(def, rowIndex)
	local yPos = _kbRowsStartY + (rowIndex - 1) * (KB_ROW + KB_GAP)
	local ROW_W = KB_W - KB_PAD * 2
	local IPAD  = 10
	local labelW = 100
	local resetW = 24

	-- ── Row container ──────────────────────────────────────────
	local rowFrame = Instance.new("TextButton")
	rowFrame.Size                   = UDim2.new(0, ROW_W, 0, KB_ROW)
	rowFrame.Position               = UDim2.new(0, KB_PAD, 0, yPos)
	rowFrame.BackgroundColor3       = Color3.fromRGB(28, 28, 48)
	rowFrame.BackgroundTransparency = 0.25
	rowFrame.BorderSizePixel        = 0
	rowFrame.Text                   = ""
	rowFrame.AutoButtonColor        = false
	rowFrame.Parent                 = keybindsContent
	Instance.new("UICorner", rowFrame).CornerRadius = UDim.new(0, 10)
	local rowStroke = Instance.new("UIStroke", rowFrame)
	rowStroke.Color = Color3.fromRGB(42, 42, 68); rowStroke.Thickness = 1
	rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	-- Action label (left)
	local lbl = Instance.new("TextLabel", rowFrame)
	lbl.Size               = UDim2.new(0, labelW, 1, 0)
	lbl.Position           = UDim2.new(0, IPAD, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text               = def.label
	lbl.TextColor3         = Color3.fromRGB(240, 240, 250)
	lbl.Font               = Enum.Font.GothamBold
	lbl.TextSize           = 12
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
	lbl.TextTruncate       = Enum.TextTruncate.AtEnd

	-- Key display (center)
	local btn = Instance.new("TextLabel", rowFrame)
	btn.Size               = UDim2.new(1, -(IPAD + labelW + KB_GAP + KB_GAP + resetW + IPAD), 0, KB_ROW - 10)
	btn.Position           = UDim2.new(0, IPAD + labelW + KB_GAP, 0.5, -(KB_ROW - 10)/2)
	btn.BackgroundColor3   = Color3.fromRGB(32, 32, 55)
	btn.BackgroundTransparency = 0
	btn.BorderSizePixel    = 0
	btn.Text               = _G[def.gKey] or def.default
	btn.TextColor3         = Color3.fromRGB(255, 255, 255)
	btn.Font               = Enum.Font.GothamBold
	btn.TextSize           = 13
	btn.TextXAlignment     = Enum.TextXAlignment.Center
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
	local _btnStroke = Instance.new("UIStroke", btn)
	_btnStroke.Color = Color3.fromRGB(55, 55, 85); _btnStroke.Thickness = 1
	_btnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	-- Reset button (right, small circle)
	local resetBtn = Instance.new("TextButton", rowFrame)
	resetBtn.Size               = UDim2.new(0, resetW, 0, resetW)
	resetBtn.Position           = UDim2.new(1, -(IPAD + resetW), 0.5, -resetW/2)
	resetBtn.BackgroundColor3   = BORDER_COLOR
	resetBtn.BackgroundTransparency = 0
	resetBtn.BorderSizePixel    = 0
	resetBtn.Text               = "R"
	resetBtn.TextColor3         = Color3.fromRGB(8, 10, 18)
	resetBtn.Font               = Enum.Font.GothamBold
	resetBtn.TextSize           = 12
	resetBtn.AutoButtonColor    = false
	Instance.new("UICorner", resetBtn).CornerRadius = UDim.new(1, 0)

	local rowData = { def = def, btn = btn, resetBtn = resetBtn, listening = false }
	table.insert(_kbRows, rowData)

	local function setListening(on)
		rowData.listening = on
		if on then
			listeningSlot = rowData
			btn.Text = "..."
			btn.TextColor3 = Color3.fromRGB(255, 220, 60)
			btn.BackgroundColor3 = Color3.fromRGB(45, 38, 12)
			_btnStroke.Color = Color3.fromRGB(255, 220, 60)
			rowStroke.Color = Color3.fromRGB(255, 220, 60)
			rowFrame.BackgroundTransparency = 0.1
			KBHint.Text = "Press any key to set " .. def.label
		else
			if listeningSlot == rowData then listeningSlot = nil end
			btn.Text = _G[def.gKey] or def.default
			btn.TextColor3 = Color3.fromRGB(255, 255, 255)
			btn.BackgroundColor3 = Color3.fromRGB(32, 32, 55)
			_btnStroke.Color = Color3.fromRGB(55, 55, 85)
			rowStroke.Color = Color3.fromRGB(42, 42, 68)
			rowFrame.BackgroundTransparency = 0.25
			KBHint.Text = "Click a button then press any key to remap"
		end
	end

	rowFrame.MouseButton1Click:Connect(function()
		for _, r in ipairs(_kbRows) do
			if r ~= rowData then
				r.listening = false
				r.btn.Text = _G[r.def.gKey] or r.def.default
				r.btn.TextColor3 = Color3.fromRGB(255, 255, 255)
				r.btn.BackgroundColor3 = Color3.fromRGB(32, 32, 55)
				local ks = r.btn:FindFirstChildOfClass("UIStroke")
				if ks then ks.Color = Color3.fromRGB(55, 55, 85) end
				r.btn.Parent.BackgroundTransparency = 0.25
			end
		end
		if listeningSlot and listeningSlot ~= rowData then listeningSlot = nil end
		setListening(not rowData.listening)
	end)

	resetBtn.MouseButton1Click:Connect(function()
		if rowData.listening then setListening(false) end
		_G[def.gKey] = def.default
		SettingsObj:SetAttribute(def.attrKey, def.default)
		btn.Text = def.default
		resetBtn.TextColor3 = TOGGLE_GREEN
		task.delay(0.7, function() if resetBtn and resetBtn.Parent then resetBtn.TextColor3 = BORDER_COLOR end end)
	end)
end

for i, def in ipairs(KEYBIND_DEFS) do
	makeKbRow(def, i)
end


-- ── TP SETTINGS TAB content ──────────────────────────────────────────────────
do
    local tpContent = _kbTabContents["tp settings"]
    local _TP_PAD = KB_PAD
    local _TP_ROW = 30
    local _TP_GAP = 6
    local _TP_Y   = 8
    local rowW = KB_W - _TP_PAD * 2

    -- helper: section label
    local function makeSectionLabel(text, yPos)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, rowW, 0, 18)
        lbl.Position = UDim2.new(0, _TP_PAD, 0, yPos)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = Color3.fromRGB(130, 130, 130)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = tpContent
    end

    -- helper: toggle row — returns (btn, setFn)
    local function makeTpToggle(labelText, yPos, initState)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(0, rowW, 0, _TP_ROW)
        row.Position = UDim2.new(0, _TP_PAD, 0, yPos)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
        row.BackgroundTransparency = 0.25
        row.BorderSizePixel = 0
        row.Parent = tpContent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, rowW - 68, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(240, 240, 250)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row
        local pill = Instance.new("Frame")
        pill.Size = UDim2.new(0, 40, 0, 20)
        pill.Position = UDim2.new(1, -50, 0.5, -10)
        pill.BackgroundColor3 = initState and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
        pill.BorderSizePixel = 0
        pill.Parent = row
        Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 14, 0, 14)
        dot.Position = initState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        dot.BorderSizePixel = 0
        dot.Parent = pill
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.Parent = row
        local function setBtn(on)
            pill.BackgroundColor3 = on and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
            dot.Position = on and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        end
        return btn, setBtn
    end

    -- helper: number input row (label + TextBox)
    local function makeTpNumInput(labelText, yPos, initVal, suffix)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(0, rowW, 0, _TP_ROW)
        row.Position = UDim2.new(0, _TP_PAD, 0, yPos)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
        row.BackgroundTransparency = 0.25
        row.BorderSizePixel = 0
        row.Parent = tpContent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, rowW - 90, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(240, 240, 250)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0, 72, 0, 22)
        box.Position = UDim2.new(1, -80, 0.5, -11)
        box.BackgroundColor3 = Color3.fromRGB(32, 32, 55)
        box.BorderSizePixel = 0
        box.Text = tostring(initVal)
        box.TextColor3 = WHITE
        box.Font = Enum.Font.GothamBold
        box.TextSize = 11
        box.ClearTextOnFocus = false
        box.Parent = row
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
        local bStroke = Instance.new("UIStroke", box)
        bStroke.Color = Color3.fromRGB(55, 55, 85); bStroke.Thickness = 1
        if suffix then
            local sfx = Instance.new("TextLabel")
            sfx.Size = UDim2.new(0, 16, 0, 22)
            sfx.Position = UDim2.new(1, -80 + 72 + 2, 0.5, -11)
            sfx.BackgroundTransparency = 1
            sfx.Text = suffix
            sfx.TextColor3 = Color3.fromRGB(130, 130, 130)
            sfx.Font = Enum.Font.Gotham
            sfx.TextSize = 10
            sfx.Parent = row
        end
        return box
    end

    local y = _TP_Y

    -- ── Mode section ──────────────────────────────────────────────────────
    makeSectionLabel("TP MODE", y); y = y + 20

    local fe = _G.FlashExtra or {}

    local _tpHighBtn, _tpHighSet = makeTpToggle("TP Highest (ignore priority)", y, fe.tpHighestEnabled == true)
    y = y + _TP_ROW + _TP_GAP
    local _tpPrioBtn, _tpPrioSet = makeTpToggle("TP Priority list", y, fe.tpPriorityEnabled ~= false)
    y = y + _TP_ROW + _TP_GAP

    -- ── TP V1 / V2 (mutuellement exclusifs) ─────────────────────────────────
    do  -- scope isole pour eviter la limite de 200 locals Lua
        local _isV1 = false
        pcall(function()
            local v = SettingsObj:GetAttribute("SavedTPV1")
            if v == true then _isV1 = true end
        end)
        -- V2 prend priorite si V1 n'est pas sauvegarde explicitement
        if not _isV1 then
            pcall(function()
                local v = SettingsObj:GetAttribute("SavedTPV2")
                if v == false then _isV1 = true end
            end)
        end
        _G._tpV2Enabled = not _isV1

        local _tpV1Btn, _tpV1Set = makeTpToggle("TP V1  (TP classique)", y, _isV1)
        y = y + _TP_ROW + _TP_GAP
        local _tpV2Btn, _tpV2Set = makeTpToggle("TP V2  (saut haut, evite obstacles)", y, not _isV1)
        y = y + _TP_ROW + _TP_GAP

        _tpV1Btn.MouseButton1Click:Connect(function()
            _isV1 = true
            _G._tpV2Enabled = false
            _tpV1Set(true)
            _tpV2Set(false)
            pcall(function() SettingsObj:SetAttribute("SavedTPV1", true) end)
            pcall(function() SettingsObj:SetAttribute("SavedTPV2", false) end)
        end)

        _tpV2Btn.MouseButton1Click:Connect(function()
            _isV1 = false
            _G._tpV2Enabled = true
            _tpV1Set(false)
            _tpV2Set(true)
            pcall(function() SettingsObj:SetAttribute("SavedTPV1", false) end)
            pcall(function() SettingsObj:SetAttribute("SavedTPV2", true) end)
        end)
    end  -- fin scope TP V1/V2

    _tpHighBtn.MouseButton1Click:Connect(function()
        local fe2 = _G.FlashExtra
        if not fe2 then return end
        fe2.tpHighestEnabled  = not fe2.tpHighestEnabled
        fe2.tpPriorityEnabled = not fe2.tpHighestEnabled
        _tpHighSet(fe2.tpHighestEnabled)
        _tpPrioSet(fe2.tpPriorityEnabled)
        pcall(function() SettingsObj:SetAttribute("SavedTPHighest",  fe2.tpHighestEnabled) end)
        pcall(function() SettingsObj:SetAttribute("SavedTPPriority", fe2.tpPriorityEnabled) end)
    end)
    _tpPrioBtn.MouseButton1Click:Connect(function()
        local fe2 = _G.FlashExtra
        if not fe2 then return end
        fe2.tpPriorityEnabled = not fe2.tpPriorityEnabled
        fe2.tpHighestEnabled  = not fe2.tpPriorityEnabled
        _tpPrioSet(fe2.tpPriorityEnabled)
        _tpHighSet(fe2.tpHighestEnabled)
        pcall(function() SettingsObj:SetAttribute("SavedTPPriority", fe2.tpPriorityEnabled) end)
        pcall(function() SettingsObj:SetAttribute("SavedTPHighest",  fe2.tpHighestEnabled) end)
    end)

    pcall(function()
        local svHigh = SettingsObj:GetAttribute("SavedTPHighest")
        local svPrio = SettingsObj:GetAttribute("SavedTPPriority")
        local fe2 = _G.FlashExtra
        if fe2 then
            if svHigh ~= nil then fe2.tpHighestEnabled  = svHigh; _tpHighSet(svHigh) end
            if svPrio ~= nil then fe2.tpPriorityEnabled = svPrio; _tpPrioSet(svPrio) end
        end
    end)

    -- ── saveExtra helper (writes FlashTP_extra.json from live FlashExtra) ──
    local function _saveExtraFromHub()
        pcall(function()
            local _fe2 = _G.FlashExtra
            if not _fe2 then return end
            local HttpSvcH = game:GetService("HttpService")
            writefile("FlashTP_extra.json", HttpSvcH:JSONEncode({
                tpPriorityEnabled = _fe2.tpPriorityEnabled,
                tpHighestEnabled  = _fe2.tpHighestEnabled,
                tpMinMPS          = _fe2.tpMinMPS,
                tpFpsGate         = _fe2.tpFpsGate,
                priorityList      = _fe2.priorityList,
                skyCloneWait      = _fe2.skyCloneWait,
                cloneDelay        = _fe2.cloneDelay,
                wallAnchorWait    = _fe2.wallAnchorWait,
                walkDuration      = _fe2.walkDuration,
                walkSettle        = _fe2.walkSettle,
                walkDuration2     = _fe2.walkDuration2,
                walkSettle2       = _fe2.walkSettle2,
                preRise           = _fe2.preRise,
                riseHeight        = _fe2.riseHeight,
                tpSpeed           = _fe2.tpSpeed,
                brainrotSnapSpeed = _fe2.brainrotSnapSpeed,
                tpTool            = _fe2.tpTool or "",
            }))
        end)
    end
    _G._saveExtraFromHub = _saveExtraFromHub   -- <-- ADD THIS LINE

    -- Wire save into toggle handlers that are already declared above
    _tpHighBtn.MouseButton1Click:Connect(function() _saveExtraFromHub() end)
    _tpPrioBtn.MouseButton1Click:Connect(function() _saveExtraFromHub() end)

    -- ── Open Priority List button ─────────────────────────────────────────
    do
        local _prioBtn = Instance.new("TextButton")
        _prioBtn.Size = UDim2.new(0, rowW, 0, _TP_ROW)
        _prioBtn.Position = UDim2.new(0, _TP_PAD, 0, y)
        _prioBtn.BackgroundColor3 = BTN_COLOR
        _prioBtn.BorderSizePixel = 0
        _prioBtn.Text = "Open Priority List"
        _prioBtn.TextColor3 = WHITE
        _prioBtn.Font = Enum.Font.GothamBold
        _prioBtn.TextSize = 12
        _prioBtn.AutoButtonColor = false
        _prioBtn.Parent = tpContent
        Instance.new("UICorner", _prioBtn).CornerRadius = UDim.new(0, 6)
        local _pStroke = Instance.new("UIStroke", _prioBtn)
        _pStroke.Color = BORDER_COLOR; _pStroke.Thickness = 1
        y = y + _TP_ROW + _TP_GAP

        -- Priority list popup window (hub-themed)
        local _sg = Instance.new("ScreenGui")
        _sg.Name = "HubPriorityListGui"
        _sg.ResetOnSpawn = false
        _sg.IgnoreGuiInset = true
        pcall(function() _sg.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
        if not _sg.Parent then _sg.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui") end

        local _prioWin = Instance.new("Frame")
        _prioWin.Size = UDim2.new(0, 370, 0, 490)
        _prioWin.Position = UDim2.new(0, 200, 0.5, -245)
        _prioWin.BackgroundColor3 = Color3.fromRGB(20, 20, 38)
        _prioWin.BorderSizePixel = 0
        _prioWin.Visible = false
        _prioWin.Active = true
        _prioWin.ClipsDescendants = true
        _prioWin.Parent = _sg
        Instance.new("UICorner", _prioWin).CornerRadius = UDim.new(0, 14)
        local _pwStroke = Instance.new("UIStroke", _prioWin)
        _pwStroke.Color = Color3.fromRGB(42, 42, 68); _pwStroke.Thickness = 1.5

        makeDraggable(_prioWin, "HubPrioList", nil)

        -- Title bar
        local _pwTitle = Instance.new("Frame")
        _pwTitle.Size = UDim2.new(1, 0, 0, 44)
        _pwTitle.BackgroundColor3 = Color3.fromRGB(22, 22, 42)
        _pwTitle.BorderSizePixel = 0
        _pwTitle.ZIndex = 5
        _pwTitle.Parent = _prioWin
        Instance.new("UICorner", _pwTitle).CornerRadius = UDim.new(0, 14)
        local _pwTitleFill = Instance.new("Frame")
        _pwTitleFill.Size = UDim2.new(1, 0, 0, 14)
        _pwTitleFill.Position = UDim2.new(0, 0, 1, -14)
        _pwTitleFill.BackgroundColor3 = Color3.fromRGB(22, 22, 42)
        _pwTitleFill.BorderSizePixel = 0
        _pwTitleFill.ZIndex = 5
        _pwTitleFill.Parent = _pwTitle
        local _pwTitleSep = Instance.new("Frame", _pwTitle)
        _pwTitleSep.Size = UDim2.new(1, -24, 0, 1)
        _pwTitleSep.Position = UDim2.new(0, 12, 1, -1)
        _pwTitleSep.BackgroundColor3 = Color3.fromRGB(42, 42, 68)
        _pwTitleSep.BorderSizePixel = 0
        _pwTitleSep.ZIndex = 5
        local _pwTitleLbl = Instance.new("TextLabel")
        _pwTitleLbl.Size = UDim2.new(1, -60, 1, 0)
        _pwTitleLbl.Position = UDim2.new(0, 14, 0, 0)
        _pwTitleLbl.BackgroundTransparency = 1
        _pwTitleLbl.Text = "TP PRIORITY LIST"
        _pwTitleLbl.TextColor3 = WHITE
        _pwTitleLbl.Font = Enum.Font.GothamBold
        _pwTitleLbl.TextSize = 14
        _pwTitleLbl.TextXAlignment = Enum.TextXAlignment.Left
        _pwTitleLbl.ZIndex = 6
        _pwTitleLbl.Parent = _pwTitle
        local _pwClose = Instance.new("TextButton")
        _pwClose.Size = UDim2.new(0, 26, 0, 26)
        _pwClose.Position = UDim2.new(1, -36, 0.5, -13)
        _pwClose.BackgroundColor3 = Color3.fromRGB(60, 18, 18)
        _pwClose.BorderSizePixel = 0
        _pwClose.Text = "×"
        _pwClose.TextColor3 = Color3.fromRGB(220, 80, 80)
        _pwClose.Font = Enum.Font.GothamBold
        _pwClose.TextSize = 14
        _pwClose.ZIndex = 7
        _pwClose.Parent = _pwTitle
        Instance.new("UICorner", _pwClose).CornerRadius = UDim.new(1, 0)
        _pwClose.MouseButton1Click:Connect(function() _prioWin.Visible = false end)

        -- Hint label
        local _pwHint = Instance.new("TextLabel")
        _pwHint.Size = UDim2.new(1, -20, 0, 22)
        _pwHint.Position = UDim2.new(0, 10, 0, 48)
        _pwHint.BackgroundTransparency = 1
        _pwHint.Text = "#1 = highest priority. Use @username to target a player, or brainrot name. TP Priority must be ON."
        _pwHint.TextColor3 = Color3.fromRGB(115, 115, 150)
        _pwHint.Font = Enum.Font.Gotham
        _pwHint.TextSize = 10
        _pwHint.TextXAlignment = Enum.TextXAlignment.Left
        _pwHint.TextWrapped = true
        _pwHint.Parent = _prioWin

        -- Add entry row
        local _pwAddBox = Instance.new("TextBox")
        _pwAddBox.Size = UDim2.new(1, -100, 0, 34)
        _pwAddBox.Position = UDim2.new(0, 10, 0, 74)
        _pwAddBox.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
        _pwAddBox.BackgroundTransparency = 0.2
        _pwAddBox.BorderSizePixel = 0
        _pwAddBox.Text = ""
        _pwAddBox.PlaceholderText = "Brainrot name or @username..."
        _pwAddBox.TextColor3 = WHITE
        _pwAddBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 130)
        _pwAddBox.Font = Enum.Font.Gotham
        _pwAddBox.TextSize = 12
        _pwAddBox.ClearTextOnFocus = false
        _pwAddBox.Parent = _prioWin
        Instance.new("UICorner", _pwAddBox).CornerRadius = UDim.new(0, 9)
        local _pwAddBoxStroke = Instance.new("UIStroke", _pwAddBox)
        _pwAddBoxStroke.Color = Color3.fromRGB(42, 42, 68); _pwAddBoxStroke.Thickness = 1

        local _pwAddBtn = Instance.new("TextButton")
        _pwAddBtn.Size = UDim2.new(0, 78, 0, 34)
        _pwAddBtn.Position = UDim2.new(1, -90, 0, 74)
        _pwAddBtn.BackgroundColor3 = Color3.fromRGB(65, 195, 90)
        _pwAddBtn.BorderSizePixel = 0
        _pwAddBtn.Text = "+ ADD"
        _pwAddBtn.TextColor3 = Color3.fromRGB(18, 18, 30)
        _pwAddBtn.Font = Enum.Font.GothamBold
        _pwAddBtn.TextSize = 12
        _pwAddBtn.Parent = _prioWin
        Instance.new("UICorner", _pwAddBtn).CornerRadius = UDim.new(0, 9)

        -- Scrollable list
        local _pwList = Instance.new("ScrollingFrame")
        _pwList.Size = UDim2.new(1, -20, 1, -118)
        _pwList.Position = UDim2.new(0, 10, 0, 114)
        _pwList.BackgroundColor3 = Color3.fromRGB(16, 16, 32)
        _pwList.BackgroundTransparency = 0.3
        _pwList.BorderSizePixel = 0
        _pwList.ScrollBarThickness = 3
        _pwList.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 90)
        _pwList.CanvasSize = UDim2.new(0, 0, 0, 0)
        _pwList.AutomaticCanvasSize = Enum.AutomaticSize.Y
        _pwList.Parent = _prioWin
        Instance.new("UICorner", _pwList).CornerRadius = UDim.new(0, 10)
        local _pwListLayout = Instance.new("UIListLayout", _pwList)
        _pwListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        _pwListLayout.Padding = UDim.new(0, 4)
        local _pwListPad = Instance.new("UIPadding", _pwList)
        _pwListPad.PaddingTop    = UDim.new(0, 6)
        _pwListPad.PaddingBottom = UDim.new(0, 6)
        _pwListPad.PaddingLeft   = UDim.new(0, 6)
        _pwListPad.PaddingRight  = UDim.new(0, 6)

        local function rebuildPrioList()
            for _, ch in ipairs(_pwList:GetChildren()) do
                if ch:IsA("Frame") then ch:Destroy() end
            end
            local fe2 = _G.FlashExtra
            if not fe2 or not fe2.priorityList then return end
            for i, name in ipairs(fe2.priorityList) do
                local isPlayer = name:sub(1,1) == "@"
                local uname = isPlayer and name:sub(2) or nil
                local rowH = isPlayer and 46 or 36

                local row = Instance.new("Frame")
                row.Size = UDim2.new(1, 0, 0, rowH)
                row.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
                row.BackgroundTransparency = 0.2
                row.BorderSizePixel = 0
                row.LayoutOrder = i
                row.Parent = _pwList
                Instance.new("UICorner", row).CornerRadius = UDim.new(0, 9)

                local numLbl = Instance.new("TextLabel")
                numLbl.Size = UDim2.new(0, 28, 1, 0)
                numLbl.Position = UDim2.new(0, 4, 0, 0)
                numLbl.BackgroundTransparency = 1
                numLbl.Text = tostring(i)
                numLbl.TextColor3 = Color3.fromRGB(115, 115, 160)
                numLbl.Font = Enum.Font.GothamBold
                numLbl.TextSize = 11
                numLbl.TextXAlignment = Enum.TextXAlignment.Center
                numLbl.Parent = row

                if isPlayer then
                    local topLbl = Instance.new("TextLabel")
                    topLbl.Size = UDim2.new(1, -126, 0, 24)
                    topLbl.Position = UDim2.new(0, 32, 0, 4)
                    topLbl.BackgroundTransparency = 1
                    topLbl.Text = uname
                    topLbl.TextColor3 = Color3.fromRGB(240, 240, 250)
                    topLbl.Font = Enum.Font.GothamBold
                    topLbl.TextSize = 12
                    topLbl.TextXAlignment = Enum.TextXAlignment.Left
                    topLbl.TextTruncate = Enum.TextTruncate.AtEnd
                    topLbl.Parent = row

                    local botLbl = Instance.new("TextLabel")
                    botLbl.Size = UDim2.new(1, -126, 0, 16)
                    botLbl.Position = UDim2.new(0, 32, 0, 27)
                    botLbl.BackgroundTransparency = 1
                    botLbl.Text = "@" .. uname
                    botLbl.TextColor3 = Color3.fromRGB(110, 110, 155)
                    botLbl.Font = Enum.Font.Gotham
                    botLbl.TextSize = 10
                    botLbl.TextXAlignment = Enum.TextXAlignment.Left
                    botLbl.TextTruncate = Enum.TextTruncate.AtEnd
                    botLbl.Parent = row

                    task.spawn(function()
                        local dn = uname
                        -- joueur en jeu : instantané
                        pcall(function()
                            for _, p in ipairs(Players:GetPlayers()) do
                                if p.Name:lower() == uname:lower() then
                                    dn = p.DisplayName; return
                                end
                            end
                        end)
                        -- si pas trouvé en jeu, appel API Roblox
                        if dn == uname then
                            pcall(function()
                                local uid
                                pcall(function() uid = Players:GetUserIdFromNameAsync(uname) end)
                                if uid then
                                    local raw = game:HttpGet("https://users.roblox.com/v1/users/" .. uid)
                                    local d = raw:match('"displayName":"([^"]+)"')
                                    if d and d ~= "" then dn = d end
                                end
                            end)
                        end
                        if topLbl and topLbl.Parent then
                            topLbl.Text = dn
                        end
                    end)
                else
                    local nameLbl = Instance.new("TextLabel")
                    nameLbl.Size = UDim2.new(1, -126, 1, 0)
                    nameLbl.Position = UDim2.new(0, 32, 0, 0)
                    nameLbl.BackgroundTransparency = 1
                    nameLbl.Text = name
                    nameLbl.TextColor3 = Color3.fromRGB(240, 240, 250)
                    nameLbl.Font = Enum.Font.GothamBold
                    nameLbl.TextSize = 12
                    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
                    nameLbl.Parent = row
                end

                local upB = Instance.new("TextButton")
                upB.Size = UDim2.new(0, 28, 0, 24)
                upB.Position = UDim2.new(1, -94, 0.5, -12)
                upB.BackgroundColor3 = Color3.fromRGB(35, 35, 60)
                upB.BorderSizePixel = 0
                upB.Text = "▲"
                upB.TextColor3 = Color3.fromRGB(180, 180, 210)
                upB.Font = Enum.Font.GothamBold
                upB.TextSize = 9
                upB.Parent = row
                Instance.new("UICorner", upB).CornerRadius = UDim.new(0, 6)
                upB.MouseButton1Click:Connect(function()
                    local _fe2 = _G.FlashExtra
                    if not _fe2 or i <= 1 then return end
                    _fe2.priorityList[i], _fe2.priorityList[i-1] = _fe2.priorityList[i-1], _fe2.priorityList[i]
                    _saveExtraFromHub()
                    rebuildPrioList()
                end)

                local dnB = Instance.new("TextButton")
                dnB.Size = UDim2.new(0, 28, 0, 24)
                dnB.Position = UDim2.new(1, -62, 0.5, -12)
                dnB.BackgroundColor3 = Color3.fromRGB(35, 35, 60)
                dnB.BorderSizePixel = 0
                dnB.Text = "▼"
                dnB.TextColor3 = Color3.fromRGB(180, 180, 210)
                dnB.Font = Enum.Font.GothamBold
                dnB.TextSize = 9
                dnB.Parent = row
                Instance.new("UICorner", dnB).CornerRadius = UDim.new(0, 6)
                dnB.MouseButton1Click:Connect(function()
                    local _fe2 = _G.FlashExtra
                    if not _fe2 or i >= #_fe2.priorityList then return end
                    _fe2.priorityList[i], _fe2.priorityList[i+1] = _fe2.priorityList[i+1], _fe2.priorityList[i]
                    _saveExtraFromHub()
                    rebuildPrioList()
                end)

                local delB = Instance.new("TextButton")
                delB.Size = UDim2.new(0, 28, 0, 24)
                delB.Position = UDim2.new(1, -30, 0.5, -12)
                delB.BackgroundColor3 = Color3.fromRGB(55, 18, 18)
                delB.BorderSizePixel = 0
                delB.Text = "✕"
                delB.TextColor3 = Color3.fromRGB(220, 80, 80)
                delB.Font = Enum.Font.GothamBold
                delB.TextSize = 11
                delB.Parent = row
                Instance.new("UICorner", delB).CornerRadius = UDim.new(0, 6)
                delB.MouseButton1Click:Connect(function()
                    local _fe2 = _G.FlashExtra
                    if not _fe2 then return end
                    table.remove(_fe2.priorityList, i)
                    _saveExtraFromHub()
                    rebuildPrioList()
                end)
            end
        end

        _pwAddBtn.MouseButton1Click:Connect(function()
            local v = _pwAddBox.Text:match("^%s*(.-)%s*$")
            if v and v ~= "" then
                local _fe2 = _G.FlashExtra
                if _fe2 and _fe2.priorityList then
                    table.insert(_fe2.priorityList, 1, v)
                    _pwAddBox.Text = ""
                    _saveExtraFromHub()
                    rebuildPrioList()
                end
            end
        end)

        -- Open/close button handler
        _prioBtn.MouseButton1Click:Connect(function()
            _prioWin.Visible = not _prioWin.Visible
            if _prioWin.Visible then
                rebuildPrioList()
            end
        end)
        _prioBtn.MouseEnter:Connect(function()
            _prioBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 32)
        end)
        _prioBtn.MouseLeave:Connect(function()
            _prioBtn.BackgroundColor3 = BTN_COLOR
        end)
    end

    -- ── Filters section ───────────────────────────────────────────────────
    makeSectionLabel("FILTERS", y); y = y + 20

    -- Min Gen to TP (in millions, e.g. "500" = 500M)
    local _minGenBox = makeTpNumInput("Min Gen to TP (M)", y, (fe.tpMinMPS or 0))
    y = y + _TP_ROW + _TP_GAP
    _minGenBox.FocusLost:Connect(function()
        local v = tonumber(_minGenBox.Text)
        if v then
            local fe2 = _G.FlashExtra
            if fe2 then
                fe2.tpMinMPS = v
                _minGenBox.TextColor3 = TOGGLE_GREEN
                task.delay(0.8, function() if _minGenBox and _minGenBox.Parent then _minGenBox.TextColor3 = WHITE end end)
                _saveExtraFromHub()
            end
        else
            _minGenBox.Text = tostring((_G.FlashExtra and _G.FlashExtra.tpMinMPS) or 0)
        end
    end)

    -- FPS Gate
    local _fpsGateBox = makeTpNumInput("FPS Gate (0 = off)", y, (fe.tpFpsGate or 0))
    y = y + _TP_ROW + _TP_GAP
    _fpsGateBox.FocusLost:Connect(function()
        local v = tonumber(_fpsGateBox.Text)
        if v then
            local fe2 = _G.FlashExtra
            if fe2 then
                fe2.tpFpsGate = v
                _saveExtraFromHub()
            end
        else
            _fpsGateBox.Text = tostring((_G.FlashExtra and _G.FlashExtra.tpFpsGate) or 0)
        end
    end)

    -- ── Movement section ─────────────────────────────────────────────────
    makeSectionLabel("MOVEMENT", y); y = y + 20

    local _preRiseBtn, _preRiseSet = makeTpToggle("Pre-rise before move", y, fe.preRise == true)
    y = y + _TP_ROW + _TP_GAP
    _preRiseBtn.MouseButton1Click:Connect(function()
        local fe2 = _G.FlashExtra
        if not fe2 then return end
        fe2.preRise = not fe2.preRise
        _preRiseSet(fe2.preRise)
        _saveExtraFromHub()
    end)

    -- ── Rise Height slider (5–20 studs) ──────────────────────────────────
    local rFill, rThumb, rValLbl  -- hoisted for task.defer sync
    do
        local sliderRow = Instance.new("Frame")
        sliderRow.Size = UDim2.new(0, rowW, 0, _TP_ROW + 10)
        sliderRow.Position = UDim2.new(0, _TP_PAD, 0, y)
        sliderRow.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
        sliderRow.BackgroundTransparency = 0.25
        sliderRow.BorderSizePixel = 0
        sliderRow.Parent = tpContent
        Instance.new("UICorner", sliderRow).CornerRadius = UDim.new(0, 12)

        local rLbl = Instance.new("TextLabel")
        rLbl.Size = UDim2.new(0, rowW - 90, 0, 18)
        rLbl.Position = UDim2.new(0, 10, 0, 4)
        rLbl.BackgroundTransparency = 1
        rLbl.Text = "Rise Height (studs)"
        rLbl.TextColor3 = Color3.fromRGB(240, 240, 250)
        rLbl.Font = Enum.Font.GothamBold
        rLbl.TextSize = 11
        rLbl.TextXAlignment = Enum.TextXAlignment.Left
        rLbl.Parent = sliderRow

        local _initRH = (_G.FlashExtra and _G.FlashExtra.riseHeight) or 14
        rValLbl = Instance.new("TextLabel")
        rValLbl.Size = UDim2.new(0, 50, 0, 18)
        rValLbl.Position = UDim2.new(1, -58, 0, 4)
        rValLbl.BackgroundTransparency = 1
        rValLbl.Text = tostring(_initRH) .. " st"
        rValLbl.TextColor3 = TOGGLE_GREEN
        rValLbl.Font = Enum.Font.GothamBold
        rValLbl.TextSize = 11
        rValLbl.TextXAlignment = Enum.TextXAlignment.Right
        rValLbl.Parent = sliderRow

        -- Track bar
        local rTrack = Instance.new("Frame")
        rTrack.Size = UDim2.new(1, -20, 0, 6)
        rTrack.Position = UDim2.new(0, 10, 0, 26)
        rTrack.BackgroundColor3 = Color3.fromRGB(38, 38, 62)
        rTrack.BorderSizePixel = 0
        rTrack.Parent = sliderRow
        Instance.new("UICorner", rTrack).CornerRadius = UDim.new(1, 0)

        local _rInitRel = math.clamp((_initRH - 5) / 15, 0, 1)
        rFill = Instance.new("Frame")
        rFill.Size = UDim2.new(_rInitRel, 0, 1, 0)
        rFill.BackgroundColor3 = TOGGLE_GREEN
        rFill.BorderSizePixel = 0
        rFill.Parent = rTrack
        Instance.new("UICorner", rFill).CornerRadius = UDim.new(1, 0)

        -- Invisible button over track for click/drag
        local rSliderBtn = Instance.new("TextButton")
        rSliderBtn.Size = UDim2.new(1, 0, 0, 18)
        rSliderBtn.Position = UDim2.new(0, 0, 0, 18)
        rSliderBtn.BackgroundTransparency = 1
        rSliderBtn.Text = ""
        rSliderBtn.BorderSizePixel = 0
        rSliderBtn.ZIndex = 5
        rSliderBtn.Parent = sliderRow

        rThumb = Instance.new("Frame")
        rThumb.Size = UDim2.new(0, 14, 0, 14)
        rThumb.Position = UDim2.new(_rInitRel, -7, 0, 22)
        rThumb.BackgroundColor3 = WHITE
        rThumb.BorderSizePixel = 0
        rThumb.ZIndex = 6
        rThumb.Parent = sliderRow
        Instance.new("UICorner", rThumb).CornerRadius = UDim.new(1, 0)
        local rThumbStroke = Instance.new("UIStroke", rThumb)
        rThumbStroke.Color = Color3.fromRGB(200, 200, 215); rThumbStroke.Thickness = 1.5

        local function updateRiseSlider(mx)
            local abs = rSliderBtn.AbsolutePosition
            local sz  = rSliderBtn.AbsoluteSize
            local rel = math.clamp((mx - abs.X) / sz.X, 0, 1)
            local val = math.clamp(math.floor(rel * 15 + 0.5) + 5, 5, 20)
            local fe2 = _G.FlashExtra
            if fe2 then fe2.riseHeight = val end
            rFill.Size        = UDim2.new(rel, 0, 1, 0)
            rThumb.Position   = UDim2.new(rel, -7, 0, 22)
            rValLbl.Text      = tostring(val) .. " st"
            _saveExtraFromHub()
        end

        local _rDrag = false
        local _UIS2 = game:GetService("UserInputService")
        rSliderBtn.MouseButton1Down:Connect(function(x) _rDrag = true; updateRiseSlider(x) end)
        _UIS2.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then _rDrag = false end
        end)
        _UIS2.InputChanged:Connect(function(i)
            if _rDrag and i.UserInputType == Enum.UserInputType.MouseMovement then
                updateRiseSlider(i.Position.X)
            end
        end)

        y = y + _TP_ROW + 16 + _TP_GAP
    end

    -- ── Shared timing-slider factory ──────────────────────────────────────
    local function makeTpTimingSlider(labelText, yPos, feKey, minVal, maxVal, decimals, suffix)
        local _suffix = suffix or "s"
        local sliderRow = Instance.new("Frame")
        sliderRow.Size = UDim2.new(0, rowW, 0, _TP_ROW + 10)
        sliderRow.Position = UDim2.new(0, _TP_PAD, 0, yPos)
        sliderRow.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
        sliderRow.BackgroundTransparency = 0.25
        sliderRow.BorderSizePixel = 0
        sliderRow.Parent = tpContent
        Instance.new("UICorner", sliderRow).CornerRadius = UDim.new(0, 10)

        local _sLbl = Instance.new("TextLabel")
        _sLbl.Size = UDim2.new(0, rowW - 90, 0, 18)
        _sLbl.Position = UDim2.new(0, 12, 0, 4)
        _sLbl.BackgroundTransparency = 1
        _sLbl.Text = labelText
        _sLbl.TextColor3 = Color3.fromRGB(240, 240, 250)
        _sLbl.Font = Enum.Font.GothamBold
        _sLbl.TextSize = 11
        _sLbl.TextXAlignment = Enum.TextXAlignment.Left
        _sLbl.Parent = sliderRow

        local _initVal = (_G.FlashExtra and _G.FlashExtra[feKey]) or minVal
        local _sValLbl = Instance.new("TextLabel")
        _sValLbl.Size = UDim2.new(0, 55, 0, 18)
        _sValLbl.Position = UDim2.new(1, -60, 0, 4)
        _sValLbl.BackgroundTransparency = 1
        _sValLbl.Text = tostring(_initVal) .. _suffix
        _sValLbl.TextColor3 = TOGGLE_GREEN
        _sValLbl.Font = Enum.Font.GothamBold
        _sValLbl.TextSize = 11
        _sValLbl.TextXAlignment = Enum.TextXAlignment.Right
        _sValLbl.Parent = sliderRow

        local _sTrack = Instance.new("Frame")
        _sTrack.Size = UDim2.new(1, -20, 0, 6)
        _sTrack.Position = UDim2.new(0, 10, 0, 26)
        _sTrack.BackgroundColor3 = Color3.fromRGB(38, 38, 62)
        _sTrack.BorderSizePixel = 0
        _sTrack.Parent = sliderRow
        Instance.new("UICorner", _sTrack).CornerRadius = UDim.new(1, 0)

        local _initRel = math.clamp((_initVal - minVal) / (maxVal - minVal), 0, 1)
        local _sFill = Instance.new("Frame")
        _sFill.Size = UDim2.new(_initRel, 0, 1, 0)
        _sFill.BackgroundColor3 = TOGGLE_GREEN
        _sFill.BorderSizePixel = 0
        _sFill.Parent = _sTrack
        Instance.new("UICorner", _sFill).CornerRadius = UDim.new(1, 0)

        local _sSliderBtn = Instance.new("TextButton")
        _sSliderBtn.Size = UDim2.new(1, 0, 0, 18)
        _sSliderBtn.Position = UDim2.new(0, 0, 0, 18)
        _sSliderBtn.BackgroundTransparency = 1
        _sSliderBtn.Text = ""
        _sSliderBtn.BorderSizePixel = 0
        _sSliderBtn.ZIndex = 5
        _sSliderBtn.Parent = sliderRow

        local _sThumb = Instance.new("Frame")
        _sThumb.Size = UDim2.new(0, 14, 0, 14)
        _sThumb.Position = UDim2.new(_initRel, -7, 0, 22)
        _sThumb.BackgroundColor3 = WHITE
        _sThumb.BorderSizePixel = 0
        _sThumb.ZIndex = 6
        _sThumb.Parent = sliderRow
        Instance.new("UICorner", _sThumb).CornerRadius = UDim.new(1, 0)
        local _sThumbStroke = Instance.new("UIStroke", _sThumb)
        _sThumbStroke.Color = Color3.fromRGB(200, 200, 215); _sThumbStroke.Thickness = 1.5

        local function _sUpdate(mx)
            local abs = _sSliderBtn.AbsolutePosition
            local sz  = _sSliderBtn.AbsoluteSize
            local rel = math.clamp((mx - abs.X) / sz.X, 0, 1)
            local mult = 10 ^ decimals
            local val = math.floor(rel * (maxVal - minVal) * mult + 0.5) / mult + minVal
            val = math.clamp(val, minVal, maxVal)
            local fe2 = _G.FlashExtra
            if fe2 then fe2[feKey] = val end
            _sFill.Size   = UDim2.new(rel, 0, 1, 0)
            _sThumb.Position = UDim2.new(rel, -7, 0, 22)
            _sValLbl.Text = tostring(val) .. _suffix
            _saveExtraFromHub()
        end

        local _sDrag = false
        local _UIST = game:GetService("UserInputService")
        _sSliderBtn.MouseButton1Down:Connect(function(x) _sDrag = true; _sUpdate(x) end)
        _UIST.InputEnded:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 then _sDrag = false end
        end)
        _UIST.InputChanged:Connect(function(i)
            if _sDrag and i.UserInputType == Enum.UserInputType.MouseMovement then
                _sUpdate(i.Position.X)
            end
        end)

        return _sValLbl, _sFill, _sThumb, _initRel
    end

    -- ── Clone Delay slider (0.05 – 0.5 s) ────────────────────────────────
    local _cdValLbl, _cdFill, _cdThumb, _cdInitRel = makeTpTimingSlider("Clone Delay (s)", y, "cloneDelay", 0.05, 0.5, 2)
    y = y + _TP_ROW + 16 + _TP_GAP

-- ── Wall Anchor Wait slider (0.05 – 2.0 s) ───────────────────────────
local _waValLbl, _waFill, _waThumb, _waInitRel = makeTpTimingSlider("Wall Anchor Wait (s)", y, "wallAnchorWait", 0.05, 2.0, 2)
y = y + _TP_ROW + 16 + _TP_GAP

-- ── TP Delay slider (0.05–0.8 s) ─────────────────────────────────
local tdValLbl, tdFill, tdThumb, tdInitRel = makeTpTimingSlider("TP Delay (s)", y, "skyCloneWait", 0.05, 0.8, 2)
y = y + _TP_ROW + 16 + _TP_GAP

-- ── Brainrot Speed slider (final go-to-brainrot tween, 60–1500 st/s) ─────────
-- Higher = faster/snappier arrival at the brainrot. Read live by goToBrainrot.
-- Return handles intentionally not captured (no extra main-chunk locals): the
-- slider self-wires and shows its initial value from config at build time.
makeTpTimingSlider("Brainrot Speed (st/s)", y, "brainrotSnapSpeed", 60, 1500, 0, " st/s")
y = y + _TP_ROW + 16 + _TP_GAP

-- ── TP Speed slider (50–1000, step 10) ──────────────────────────────────────
local speedFill, speedThumb, speedValLbl
local function _buildSpeedSlider()
    local sliderRow = Instance.new("Frame")
    sliderRow.Size = UDim2.new(0, rowW, 0, _TP_ROW + 10)
    sliderRow.Position = UDim2.new(0, _TP_PAD, 0, y)
    sliderRow.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
    sliderRow.BackgroundTransparency = 0.25
    sliderRow.BorderSizePixel = 0
    sliderRow.Parent = tpContent
    Instance.new("UICorner", sliderRow).CornerRadius = UDim.new(0, 12)

    local sLbl = Instance.new("TextLabel")
    sLbl.Size = UDim2.new(0, rowW - 90, 0, 18)
    sLbl.Position = UDim2.new(0, 10, 0, 4)
    sLbl.BackgroundTransparency = 1
    sLbl.Text = "TP Speed (studs/s)"
    sLbl.TextColor3 = Color3.fromRGB(210, 210, 210)
    sLbl.Font = Enum.Font.GothamBold
    sLbl.TextSize = 11
    sLbl.TextXAlignment = Enum.TextXAlignment.Left
    sLbl.Parent = sliderRow

    local _initSpeed = (_G.FlashExtra and _G.FlashExtra.tpSpeed) or 400
    speedValLbl = Instance.new("TextLabel")
    speedValLbl.Size = UDim2.new(0, 50, 0, 18)
    speedValLbl.Position = UDim2.new(1, -58, 0, 4)
    speedValLbl.BackgroundTransparency = 1
    speedValLbl.Text = tostring(_initSpeed) .. " st/s"
    speedValLbl.TextColor3 = TOGGLE_GREEN
    speedValLbl.Font = Enum.Font.GothamBold
    speedValLbl.TextSize = 11
    speedValLbl.TextXAlignment = Enum.TextXAlignment.Right
    speedValLbl.Parent = sliderRow

    local speedTrack = Instance.new("Frame")
    speedTrack.Size = UDim2.new(1, -20, 0, 6)
    speedTrack.Position = UDim2.new(0, 10, 0, 26)
    speedTrack.BackgroundColor3 = Color3.fromRGB(38, 38, 62)
    speedTrack.BorderSizePixel = 0
    speedTrack.Parent = sliderRow
    Instance.new("UICorner", speedTrack).CornerRadius = UDim.new(1, 0)

    local speedMin, speedMax = 50, 1000
    local speedRel = math.clamp((_initSpeed - speedMin) / (speedMax - speedMin), 0, 1)
    speedFill = Instance.new("Frame")
    speedFill.Size = UDim2.new(speedRel, 0, 1, 0)
    speedFill.BackgroundColor3 = TOGGLE_GREEN
    speedFill.BorderSizePixel = 0
    speedFill.Parent = speedTrack
    Instance.new("UICorner", speedFill).CornerRadius = UDim.new(1, 0)

    local speedSliderBtn = Instance.new("TextButton")
    speedSliderBtn.Size = UDim2.new(1, 0, 0, 18)
    speedSliderBtn.Position = UDim2.new(0, 0, 0, 18)
    speedSliderBtn.BackgroundTransparency = 1
    speedSliderBtn.Text = ""
    speedSliderBtn.BorderSizePixel = 0
    speedSliderBtn.ZIndex = 5
    speedSliderBtn.Parent = sliderRow

    speedThumb = Instance.new("Frame")
    speedThumb.Size = UDim2.new(0, 14, 0, 14)
    speedThumb.Position = UDim2.new(speedRel, -7, 0, 22)
    speedThumb.BackgroundColor3 = WHITE
    speedThumb.BorderSizePixel = 0
    speedThumb.ZIndex = 6
    speedThumb.Parent = sliderRow
    Instance.new("UICorner", speedThumb).CornerRadius = UDim.new(1, 0)
    local speedThumbStroke = Instance.new("UIStroke", speedThumb)
    speedThumbStroke.Color = Color3.fromRGB(200, 200, 215); speedThumbStroke.Thickness = 1.5

    local function updateSpeedSlider(mx)
        local abs = speedSliderBtn.AbsolutePosition
        local sz  = speedSliderBtn.AbsoluteSize
        local rel = math.clamp((mx - abs.X) / sz.X, 0, 1)
        local val = math.clamp(math.floor(rel * (speedMax - speedMin) / 10 + 0.5) * 10 + speedMin, speedMin, speedMax)
        local fe2 = _G.FlashExtra
        if fe2 then fe2.tpSpeed = val end
        speedFill.Size        = UDim2.new(rel, 0, 1, 0)
        speedThumb.Position   = UDim2.new(rel, -7, 0, 22)
        speedValLbl.Text      = tostring(val) .. " st/s"
        if _G._FlashSetSpeed then _G._FlashSetSpeed(val) end
        _saveExtraFromHub()
    end

    local speedDrag = false
    local UISTemp = game:GetService("UserInputService")
    speedSliderBtn.MouseButton1Down:Connect(function(x) speedDrag = true; updateSpeedSlider(x) end)
    UISTemp.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then speedDrag = false end
    end)
    UISTemp.InputChanged:Connect(function(i)
        if speedDrag and i.UserInputType == Enum.UserInputType.MouseMovement then
            updateSpeedSlider(i.Position.X)
        end
    end)

    y = y + _TP_ROW + 16 + _TP_GAP
end
_buildSpeedSlider()

    -- Expose speed setter so the box above can reach the upvalue
    -- (set once Flash TP task.spawn runs; the box is a no-op until then)
    task.defer(function()
        -- Wait for FlashExtra to be populated then expose setter
        for _ = 1, 100 do
            if _G.FlashExtra then break end
            task.wait(0.1)
        end
        -- Sync displayed values with loaded config
        local fe2 = _G.FlashExtra
        if fe2 then
            _minGenBox.Text  = tostring(fe2.tpMinMPS  or 0)
            _fpsGateBox.Text = tostring(fe2.tpFpsGate or 0)
            -- Sync TP Speed slider
do
    local val = fe2.tpSpeed or 400
    local rel = math.clamp((val - 50) / (1000 - 50), 0, 1)
    speedFill.Size      = UDim2.new(rel, 0, 1, 0)
    speedThumb.Position = UDim2.new(rel, -7, 0, 22)
    speedValLbl.Text    = tostring(val) .. " st/s"
end
            _tpHighSet(fe2.tpHighestEnabled  == true)
            _tpPrioSet(fe2.tpPriorityEnabled ~= false)
            _preRiseSet(fe2.preRise == true)
            -- Sync Rise Height slider
            do
                local _rh = fe2.riseHeight or 5
                local _rel = math.clamp((_rh - 5) / 15, 0, 1)
                rFill.Size      = UDim2.new(_rel, 0, 1, 0)
                rThumb.Position = UDim2.new(_rel, -7, 0, 22)
                rValLbl.Text    = tostring(_rh) .. " st"
            end
            -- Sync Clone Delay slider
            do
                local _cd = fe2.cloneDelay or 0.15
                local _rel = math.clamp((_cd - 0.05) / 0.45, 0, 1)
                _cdFill.Size      = UDim2.new(_rel, 0, 1, 0)
                _cdThumb.Position = UDim2.new(_rel, -7, 0, 22)
                _cdValLbl.Text    = tostring(_cd) .. "s"
            end
            -- Sync TP Delay slider
            do
                local _td = fe2.skyCloneWait or 0.28
                local _rel = math.clamp((_td - 0.05) / 0.75, 0, 1)
                tdFill.Size      = UDim2.new(_rel, 0, 1, 0)
                tdThumb.Position = UDim2.new(_rel, -7, 0, 22)
                tdValLbl.Text    = tostring(_td) .. "s"
            end
            -- Sync Wall Anchor Wait slider
            do
                local _wa = fe2.wallAnchorWait or 0.10
                local _rel = math.clamp((_wa - 0.05) / 1.95, 0, 1)
                _waFill.Size      = UDim2.new(_rel, 0, 1, 0)
                _waThumb.Position = UDim2.new(_rel, -7, 0, 22)
                _waValLbl.Text    = tostring(_wa) .. "s"
            end
        end
    end)
end -- TP Settings tab do

-- ── ESP TAB content ──────────────────────────────────────────────────────────
do
    local espContent = _kbTabContents["esp"]
    local _EP_PAD  = KB_PAD
    local _EP_ROW  = 52
    local _EP_GAP  = 8
    local _EP_Y    = 8
    local epRowW   = KB_W - _EP_PAD * 2

    local _EP_DESCS = {
        ["Player ESP"]            = "Shows ESP boxes above all players",
        ["Brainrot ESP (highest)"] = "Highlights the highest priority brainrot",
        ["Conveyor ESP"]          = "Shows ESP on conveyor belts",
        ["Line to Best Brainrot"] = "Draws a line to the best brainrot",
        ["Line to Base"]          = "Draws a line to your base/plot",
        ["Blacklist ESP"]         = "Highlights blacklisted players",
        ["Subspace Mine ESP"]     = "Shows ESP on subspace mines",
        ["Stealing HUD"]          = "Displays active steal status on screen",
        ["FPS Boost"]             = "Disables effects to improve FPS",
    }

    -- Helper: full-width toggle row. Returns (btn, setFn)
    local function makeEspToggle(labelText, yPos, initState)
        local descText = _EP_DESCS[labelText] or ""

        local row = Instance.new("Frame")
        row.Size               = UDim2.new(0, epRowW, 0, _EP_ROW)
        row.Position           = UDim2.new(0, _EP_PAD, 0, yPos)
        row.BackgroundColor3   = Color3.fromRGB(28, 28, 48)
        row.BackgroundTransparency = 0.25
        row.BorderSizePixel    = 0
        row.Parent             = espContent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)

        local lbl = Instance.new("TextLabel")
        lbl.Size               = UDim2.new(0, epRowW - 82, 0, 22)
        lbl.Position           = UDim2.new(0, 14, 0, 6)
        lbl.BackgroundTransparency = 1
        lbl.Text               = labelText
        lbl.TextColor3         = Color3.fromRGB(240, 240, 250)
        lbl.Font               = Enum.Font.GothamBold
        lbl.TextSize           = 13
        lbl.TextXAlignment     = Enum.TextXAlignment.Left
        lbl.Parent             = row

        local descLbl = Instance.new("TextLabel")
        descLbl.Size           = UDim2.new(0, epRowW - 82, 0, 16)
        descLbl.Position       = UDim2.new(0, 14, 0, 28)
        descLbl.BackgroundTransparency = 1
        descLbl.Text           = descText
        descLbl.TextColor3     = Color3.fromRGB(120, 120, 158)
        descLbl.Font           = Enum.Font.Gotham
        descLbl.TextSize       = 11
        descLbl.TextXAlignment = Enum.TextXAlignment.Left
        descLbl.Parent         = row

        local pill = Instance.new("Frame")
        pill.Size              = UDim2.new(0, 44, 0, 24)
        pill.Position          = UDim2.new(1, -56, 0.5, -12)
        pill.BackgroundColor3  = initState and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
        pill.BorderSizePixel   = 0
        pill.Parent            = row
        Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

        local dot = Instance.new("Frame")
        dot.Size               = UDim2.new(0, 18, 0, 18)
        dot.Position           = initState and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        dot.BackgroundColor3   = Color3.fromRGB(255, 255, 255)
        dot.BorderSizePixel    = 0
        dot.Parent             = pill
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        local btn = Instance.new("TextButton")
        btn.Size               = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text               = ""
        btn.AutoButtonColor    = false
        btn.Parent             = row

        local function setFn(on)
            pill.BackgroundColor3 = on and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
            dot.Position          = on and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
        end
        return btn, setFn
    end

    local _epY = _EP_Y

    -- ── 1. Player ESP ─────────────────────────────────────────────────────────
    local _playerEspOn = true
    _G._playerEspEnabled = _playerEspOn
    local pEspBtn, pEspSet = makeEspToggle("Player ESP", _epY, _playerEspOn)
    _epY = _epY + _EP_ROW + _EP_GAP
    pEspBtn.MouseButton1Click:Connect(function()
        _playerEspOn = not _playerEspOn
        _G._playerEspEnabled = _playerEspOn
        pEspSet(_playerEspOn)
        pcall(function() SettingsObj:SetAttribute("SavedPlayerEsp", _playerEspOn) end)
    end)
    pcall(function()
        local sv = SettingsObj:GetAttribute("SavedPlayerEsp")
        if sv ~= nil then _playerEspOn = sv; _G._playerEspEnabled = sv; pEspSet(sv) end
    end)

    -- ── 2. Brainrot ESP ───────────────────────────────────────────────────────
    -- Shows only the highest-priority brainrot (hub already does this via isBest logic;
    -- this toggle gates whether any brainrot ESP renders at all)
    local _brainrotEspOn = true
    _G._brainrotEspEnabled = _brainrotEspOn
    local brEspBtn, brEspSet = makeEspToggle("Brainrot ESP (highest)", _epY, _brainrotEspOn)
    _epY = _epY + _EP_ROW + _EP_GAP
    brEspBtn.MouseButton1Click:Connect(function()
        _brainrotEspOn = not _brainrotEspOn
        _G._brainrotEspEnabled = _brainrotEspOn
        brEspSet(_brainrotEspOn)
        pcall(function() SettingsObj:SetAttribute("SavedBrainrotEsp", _brainrotEspOn) end)
    end)
    pcall(function()
        local sv = SettingsObj:GetAttribute("SavedBrainrotEsp")
        if sv ~= nil then _brainrotEspOn = sv; _G._brainrotEspEnabled = sv; brEspSet(sv) end
    end)

    -- ── 3. Conveyor ESP ───────────────────────────────────────────────────────
    local _conveyorEspOn = false
    _G._conveyorEspEnabled = _conveyorEspOn
    local cvEspBtn, cvEspSet = makeEspToggle("Conveyor ESP", _epY, _conveyorEspOn)
    _epY = _epY + _EP_ROW + _EP_GAP
    cvEspBtn.MouseButton1Click:Connect(function()
        _conveyorEspOn = not _conveyorEspOn
        _G._conveyorEspEnabled = _conveyorEspOn
        cvEspSet(_conveyorEspOn)
        pcall(function() SettingsObj:SetAttribute("SavedConveyorEsp", _conveyorEspOn) end)
    end)
    pcall(function()
        local sv = SettingsObj:GetAttribute("SavedConveyorEsp")
        if sv ~= nil then _conveyorEspOn = sv; _G._conveyorEspEnabled = sv; cvEspSet(sv) end
    end)

    -- ── 4. Line to Best Brainrot ─────────────────────────────────────
    local _lineToBrainrotOn = false
    _G._lineToBrainrotEnabled = _lineToBrainrotOn
    local trBtn, trSet = makeEspToggle("Line to Best Brainrot", _epY, _lineToBrainrotOn)
    _epY = _epY + _EP_ROW + _EP_GAP
    trBtn.MouseButton1Click:Connect(function()
        _lineToBrainrotOn = not _lineToBrainrotOn
        _G._lineToBrainrotEnabled = _lineToBrainrotOn
        trSet(_lineToBrainrotOn)
        pcall(function() SettingsObj:SetAttribute("SavedLineToBrainrot", _lineToBrainrotOn) end)
    end)
    pcall(function()
        local sv = SettingsObj:GetAttribute("SavedLineToBrainrot")
        if sv ~= nil then _lineToBrainrotOn = sv; _G._lineToBrainrotEnabled = sv; trSet(sv) end
    end)

    -- ── 4b. Line to Base ──────────────────────────────────────────────────────
    -- Draws a second thick black/grey line from screen centre to the player's
    -- own base/plot sign, through walls, same as the brainrot tracer.
    local _lineToBaseOn = false
    _G._lineToBaseEnabled = _lineToBaseOn
    local ltbBtn, ltbSet = makeEspToggle("Line to Base", _epY, _lineToBaseOn)
    _epY = _epY + _EP_ROW + _EP_GAP
    ltbBtn.MouseButton1Click:Connect(function()
        _lineToBaseOn = not _lineToBaseOn
        _G._lineToBaseEnabled = _lineToBaseOn
        ltbSet(_lineToBaseOn)
        pcall(function() SettingsObj:SetAttribute("SavedLineToBase", _lineToBaseOn) end)
    end)
    pcall(function()
        local sv = SettingsObj:GetAttribute("SavedLineToBase")
        if sv ~= nil then _lineToBaseOn = sv; _G._lineToBaseEnabled = sv; ltbSet(sv) end
    end)

    -- ── 5. Blacklist ESP ──────────────────────────────────────────────────────
    local _blacklistEspOn = false
    _G._blacklistEspEnabled = _blacklistEspOn
    local blEspBtn, blEspSet = makeEspToggle("Blacklist ESP", _epY, _blacklistEspOn)
    _epY = _epY + _EP_ROW + _EP_GAP
    blEspBtn.MouseButton1Click:Connect(function()
        _blacklistEspOn = not _blacklistEspOn
        _G._blacklistEspEnabled = _blacklistEspOn
        blEspSet(_blacklistEspOn)
        pcall(function() SettingsObj:SetAttribute("SavedBlacklistEsp", _blacklistEspOn) end)
    end)
    pcall(function()
        local sv = SettingsObj:GetAttribute("SavedBlacklistEsp")
        if sv ~= nil then _blacklistEspOn = sv; _G._blacklistEspEnabled = sv; blEspSet(sv) end
    end)

    -- ── 6. Subspace Mine ESP ──────────────────────────────────────────────────
    local _subspaceEspOn = true
    _G._subspaceEspEnabled = _subspaceEspOn
    local ssEspBtn, ssEspSet = makeEspToggle("Subspace Mine ESP", _epY, _subspaceEspOn)
    _epY = _epY + _EP_ROW + _EP_GAP
    ssEspBtn.MouseButton1Click:Connect(function()
        _subspaceEspOn = not _subspaceEspOn
        _G._subspaceEspEnabled = _subspaceEspOn
        ssEspSet(_subspaceEspOn)
        pcall(function() SettingsObj:SetAttribute("SavedSubspaceEsp", _subspaceEspOn) end)
    end)
    pcall(function()
        local sv = SettingsObj:GetAttribute("SavedSubspaceEsp")
        if sv ~= nil then _subspaceEspOn = sv; _G._subspaceEspEnabled = sv; ssEspSet(sv) end
    end)

    -- ── 7. Stealing HUD ───────────────────────────────────────────────────────
    local _stealingHudOn = true
    _G._stealingHudEnabled = _stealingHudOn
    local shBtn, shSet = makeEspToggle("Stealing HUD", _epY, _stealingHudOn)
    _epY = _epY + _EP_ROW + _EP_GAP
    shBtn.MouseButton1Click:Connect(function()
        _stealingHudOn = not _stealingHudOn
        _G._stealingHudEnabled = _stealingHudOn
        shSet(_stealingHudOn)
        pcall(function() SettingsObj:SetAttribute("SavedStealingHud", _stealingHudOn) end)
    end)
    pcall(function()
        local sv = SettingsObj:GetAttribute("SavedStealingHud")
        if sv ~= nil then _stealingHudOn = sv; _G._stealingHudEnabled = sv; shSet(sv) end
    end)
    -- ── FPS Boost ─────────────────────────────────────────────────────────────
    local _fpsBoostOn = false
    _G._fpsBoostEnabled = false

    local fpsBtn, fpsSet = makeEspToggle("FPS Boost", _epY, _fpsBoostOn)
    _epY = _epY + _EP_ROW + _EP_GAP

    local function enableFpsBoost()
        -- Desactiver seulement les ombres et post-process (safe, pas de loop)
        pcall(function()
            local Lighting = game:GetService("Lighting")
            Lighting.GlobalShadows = false
            for _, obj in ipairs(Lighting:GetChildren()) do
                if obj:IsA("PostEffect") then
                    pcall(function() obj.Enabled = false end)
                end
            end
        end)
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
    end

    local function disableFpsBoost()
        pcall(function()
            local Lighting = game:GetService("Lighting")
            Lighting.GlobalShadows = true
            for _, obj in ipairs(Lighting:GetChildren()) do
                if obj:IsA("PostEffect") then
                    pcall(function() obj.Enabled = true end)
                end
            end
        end)
        pcall(function()
            settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        end)
    end

    fpsBtn.MouseButton1Click:Connect(function()
        _fpsBoostOn = not _fpsBoostOn
        _G._fpsBoostEnabled = _fpsBoostOn
        fpsSet(_fpsBoostOn)
        pcall(function() SettingsObj:SetAttribute("SavedFpsBoost", _fpsBoostOn) end)
        if _fpsBoostOn then enableFpsBoost() else disableFpsBoost() end
    end)
    pcall(function()
        local sv = SettingsObj:GetAttribute("SavedFpsBoost")
        if sv == true then
            _fpsBoostOn = true; _G._fpsBoostEnabled = true
            fpsSet(true); enableFpsBoost()
        end
    end)

end -- ESP tab do

-- ── UI/HIDES TAB content ──────────────────────────────────────────────────────
do
    local hidesContent = _kbTabContents["ui/hides"]
    local _UH_ROW = 30
    local _UH_GAP = 6
    local _UH_START = 8
    local rowW = KB_W - KB_PAD * 2

    -- Helper for section headers (used by the new TP Tool section)
    local function makeSectionLabel(parent, text, yPos)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, rowW, 0, 18)
        lbl.Position = UDim2.new(0, KB_PAD, 0, yPos)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = Color3.fromRGB(130, 130, 130)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = parent
    end

    -- ===== Existing HIDE toggles =====
    local HIDE_DEFS = {
        { label = "Steal Target GUI",   key = "UIHide_StealTarget"  },
        { label = "Click Commands GUI", key = "UIHide_ClickCommands"},
        { label = "Tools GUI",          key = "UIHide_Tools"        },
        { label = "Stealers GUI",       key = "UIHide_Stealers"     },
        { label = "Admin Panel GUI",    key = "UIHide_AdminPanel"   },
    }

    -- Returns whether the target instance is currently visible.
    local function getVisible(inst)
        if inst:IsA("ScreenGui") then return inst.Enabled
        else return inst.Visible end
    end
    local function setVisible(inst, on)
        if inst:IsA("ScreenGui") then inst.Enabled = on
        else inst.Visible = on end
    end

    for i, def in ipairs(HIDE_DEFS) do
        local yPos = _UH_START + (i - 1) * (_UH_ROW + _UH_GAP)

        local row = Instance.new("Frame")
        row.Size = UDim2.new(0, rowW, 0, _UH_ROW)
        row.Position = UDim2.new(0, KB_PAD, 0, yPos)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
        row.BackgroundTransparency = 0.25
        row.BorderSizePixel = 0
        row.Parent = hidesContent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, rowW - 68, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = def.label
        lbl.TextColor3 = Color3.fromRGB(240, 240, 250)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local pill = Instance.new("Frame")
        pill.Size = UDim2.new(0, 40, 0, 20)
        pill.Position = UDim2.new(1, -50, 0.5, -10)
        pill.BackgroundColor3 = Color3.fromRGB(55, 55, 80)
        pill.BorderSizePixel = 0
        pill.Parent = row
        Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 14, 0, 14)
        dot.Position = UDim2.new(0, 3, 0.5, -7)
        dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        dot.BorderSizePixel = 0
        dot.Parent = pill
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.Parent = row

        local function refresh()
            local inst = _G[def.key]
            if not inst then
                pill.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
                dot.Position = UDim2.new(0, 3, 0.5, -7)
                return
            end
            local shown = getVisible(inst)
            pill.BackgroundColor3 = shown and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
            dot.Position = shown and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        end

        btn.MouseButton1Click:Connect(function()
            local inst = _G[def.key]
            if not inst then return end
            local newState = not getVisible(inst)
            setVisible(inst, newState)
            refresh()
            pcall(function() SettingsObj:SetAttribute("SavedUIHide_" .. def.key, newState) end)
        end)

        refresh()

        task.spawn(function()
            local savedApplied = false
            local savedState
            pcall(function() savedState = SettingsObj:GetAttribute("SavedUIHide_" .. def.key) end)
            while hidesContent and hidesContent.Parent do
                local inst = _G[def.key]
                if inst and not savedApplied and savedState ~= nil then
                    setVisible(inst, savedState)
                    savedApplied = true
                end
                refresh()
                task.wait(0.5)
            end
        end)
    end

    -- ===== NEW: TP Tool Selection =====
    local _tpToolY = _UH_START + (#HIDE_DEFS) * (_UH_ROW + _UH_GAP) + 2
    makeSectionLabel(hidesContent, "TP TOOL", _tpToolY)
    _tpToolY = _tpToolY + 20

    local TOOL_LIST = { "Flying Carpet", "Cupid's Wings", "Santa's Sleigh", "Witch's Broom" }
    local toolButtons = {}

    for _, toolName in ipairs(TOOL_LIST) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(0, rowW, 0, _UH_ROW)
        row.Position = UDim2.new(0, KB_PAD, 0, _tpToolY)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
        row.BackgroundTransparency = 0.25
        row.BorderSizePixel = 0
        row.Parent = hidesContent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, rowW - 68, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = toolName
        lbl.TextColor3 = Color3.fromRGB(240, 240, 250)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local tpill = Instance.new("Frame")
        tpill.Size = UDim2.new(0, 40, 0, 20)
        tpill.Position = UDim2.new(1, -50, 0.5, -10)
        tpill.BackgroundColor3 = Color3.fromRGB(55, 55, 80)
        tpill.BorderSizePixel = 0
        tpill.Parent = row
        Instance.new("UICorner", tpill).CornerRadius = UDim.new(1, 0)
        local tdot = Instance.new("Frame")
        tdot.Size = UDim2.new(0, 14, 0, 14)
        tdot.Position = UDim2.new(0, 3, 0.5, -7)
        tdot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        tdot.BorderSizePixel = 0
        tdot.Parent = tpill
        Instance.new("UICorner", tdot).CornerRadius = UDim.new(1, 0)

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.Parent = row

        local function refresh()
            local selected = (_G.FlashExtra and _G.FlashExtra.tpTool) or ""
            local isSelected = (selected == toolName)
            tpill.BackgroundColor3 = isSelected and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
            tdot.Position = isSelected and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        end
        refresh()

        btn.MouseButton1Click:Connect(function()
            if _G.FlashExtra then
                _G.FlashExtra.tpTool = toolName
                _G._saveExtraFromHub()
                for _, tb in pairs(toolButtons) do
                    tb()
                end
            end
        end)

        toolButtons[toolName] = refresh
        _tpToolY = _tpToolY + _UH_ROW + _UH_GAP
    end

    -- ===== Carpet Speed Toggle =====
    makeSectionLabel(hidesContent, "CARPET SPEED", _tpToolY)
    _tpToolY = _tpToolY + 20

    local function makeSimpleToggle(labelText, yPos, getState, toggleFn)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(0, rowW, 0, _UH_ROW)
        row.Position = UDim2.new(0, KB_PAD, 0, yPos)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 48)
        row.BackgroundTransparency = 0.25
        row.BorderSizePixel = 0
        row.Parent = hidesContent
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, rowW - 68, 1, 0)
        lbl.Position = UDim2.new(0, 12, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(240, 240, 250)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        local pill = Instance.new("Frame")
        pill.Size = UDim2.new(0, 40, 0, 20)
        pill.Position = UDim2.new(1, -50, 0.5, -10)
        pill.BackgroundColor3 = Color3.fromRGB(55, 55, 80)
        pill.BorderSizePixel = 0
        pill.Parent = row
        Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
        local dot = Instance.new("Frame")
        dot.Size = UDim2.new(0, 14, 0, 14)
        dot.Position = UDim2.new(0, 3, 0.5, -7)
        dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        dot.BorderSizePixel = 0
        dot.Parent = pill
        Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.AutoButtonColor = false
        btn.Parent = row

        local function refresh()
            local on = getState()
            pill.BackgroundColor3 = on and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
            dot.Position = on and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        end
        refresh()

        btn.MouseButton1Click:Connect(function()
            toggleFn()
            refresh()
        end)

        return refresh
    end

    makeSimpleToggle("Enable Carpet Speed", _tpToolY,
        function() return _carpetSpeedEnabled or false end,
        function() toggleCarpetSpeed() end
    )

end -- UI/Hides tab do


-- ── Size the content frames & outer frame ─────────────────────────────────────
-- Each tab has a different amount of content, so each gets its own height.
-- ScrollingFrames (Keybinds, TP Settings, ESP) use a fixed visible-viewport height;
-- AutomaticCanvasSize=Y handles the scrollable canvas internally.
-- The Main tab (plain Frame) is sized to exactly fit its toggle rows.

local KB_TOTAL_ROWS = #KEYBIND_DEFS
-- Keybinds tab: exact content height (also used as the visible viewport height)
local KB_CONTENT_H = _kbRowsStartY + KB_TOTAL_ROWS * (KB_ROW + KB_GAP) + KB_PAD

-- Main tab: 8 toggle rows
local _MAIN_ROWS = 9
local _MAIN_CONTENT_H = _MT_START + _MAIN_ROWS * (_MT_ROW + _MT_GAP) + KB_PAD

-- TP Settings tab: visible viewport height (cap to avoid going off-screen).
-- Content is taller than this; the ScrollingFrame's AutomaticCanvasSize handles it.
local _TP_VIEWPORT_H = math.max(KB_CONTENT_H, 380)

-- ESP tab: 9 toggles × (52+8) + 8 top pad + bottom pad
local _ESP_ROWS = 9  -- +1 pour FPS Boost
local _ESP_VIEWPORT_H = 8 + _ESP_ROWS * (52 + 8) + KB_PAD

-- UI/Hides tab: 5 toggle rows
local _UH_ROWS = 5
local _UI_HIDES_CONTENT_H = 8 + _UH_ROWS * (30 + 6) + KB_PAD

-- The overall panel height is driven by whichever tab content is tallest (visible).
local _COLORS_H = 130
local _TALLEST_CONTENT_H = math.max(KB_CONTENT_H, _MAIN_CONTENT_H, _TP_VIEWPORT_H, _ESP_VIEWPORT_H, _UI_HIDES_CONTENT_H, _COLORS_H)

-- Position and size each content frame individually
local _frameSizes = {
	["main"]        = _MAIN_CONTENT_H,
	["keybinds"]    = KB_CONTENT_H,
	["tp settings"] = _TP_VIEWPORT_H,
	["esp"]         = _ESP_VIEWPORT_H,
	["ui/hides"]    = _UI_HIDES_CONTENT_H,
	["colors"]      = _COLORS_H,
}
for key, frame in pairs(_kbTabContents) do
	local h = _frameSizes[key] or KB_CONTENT_H
	frame.Size     = UDim2.new(0, KB_W, 0, h)
	frame.Position = UDim2.new(0, SIDEBAR_W, 0, KB_CONTENT_Y)
end

KB_H = KB_CONTENT_Y + _TALLEST_CONTENT_H + KB_PAD
KBFrame.Size = UDim2.new(0, PANEL_W, 0, KB_H)

-- Default to Keybinds tab
kbSwitchTab("keybinds")

-- ─── Colors tab ────────────────────────────────────────────────────────────
do
    local colorsContent = _kbTabContents["colors"]
    if colorsContent then
        local _savedTheme = "gold"

        local function setTheme(themeOrColor)
            local ac, themeName
            if typeof(themeOrColor) == "Color3" then
                ac = themeOrColor; themeName = "custom"
                local r,g,b = math.floor(ac.R*255), math.floor(ac.G*255), math.floor(ac.B*255)
                pcall(function()
                    SettingsObj:SetAttribute("SavedHubTheme",   "custom")
                    SettingsObj:SetAttribute("SavedHubColorR",  r)
                    SettingsObj:SetAttribute("SavedHubColorG",  g)
                    SettingsObj:SetAttribute("SavedHubColorB",  b)
                end)
            elseif themeOrColor == "purple" then
                ac = Color3.fromRGB(160, 80, 255); themeName = "purple"
                pcall(function() SettingsObj:SetAttribute("SavedHubTheme", themeName) end)
            elseif themeOrColor == "bw" then
                ac = Color3.fromRGB(255, 255, 255); themeName = "bw"
                pcall(function() SettingsObj:SetAttribute("SavedHubTheme", themeName) end)
            elseif themeOrColor == "gold" then
                ac = Color3.fromRGB(255, 0, 220); themeName = "gold"
                pcall(function() SettingsObj:SetAttribute("SavedHubTheme", themeName) end)
            else
                ac = Color3.fromRGB(50, 130, 255); themeName = "blue"
                pcall(function() SettingsObj:SetAttribute("SavedHubTheme", themeName) end)
            end
            _savedTheme = themeName
            -- Sauvegarder l'ancienne couleur avant de la remplacer
            local prevAc = _G._hubThemeColor or Color3.fromRGB(255, 40, 160)
            BORDER_COLOR = ac
            _G._hubThemeColor = ac
            -- Mettre a jour tous les strokes des panels
            if _G._hubPanelStrokes then
                for _,st in ipairs(_G._hubPanelStrokes) do
                    pcall(function() st.Color = ac end)
                end
            end
            -- Recolorer les etoiles selon le theme (toujours blanches)
            local starColor = Color3.fromRGB(255,255,255)
            if _G._hubStars then
                for _,s in ipairs(_G._hubStars) do
                    pcall(function() s.BackgroundColor3 = starColor end)
                end
            end
            -- Appliquer la couleur choisie sur les backgrounds des panels
            if _G._hubPanelFrames then
                for _,f in ipairs(_G._hubPanelFrames) do
                    pcall(function()
                        f.BackgroundColor3 = ac
                        f.BackgroundTransparency = 0.7
                    end)
                end
            end
            -- Appliquer directement sur le admin panel via ses references pre-enregistrees
            if _G._recolorAdminPanel then
                pcall(function() _G._recolorAdminPanel(ac) end)
            end

            -- Couleurs or connues (R, G, B entre 0-255)
            local GOLD_COLORS = {
                {255, 220, 0},
                {245, 158, 11},
                {215, 165, 0},
                {180, 130, 0},
                {255, 223, 0},
                {130, 105, 50},
            }
            local BLUE_COLORS = {
                {50, 130, 255},
                {80, 160, 255},
                {30, 90, 200},
            }
            local PURPLE_COLORS = {
                {160, 80, 255},
                {140, 80, 220},
                {93, 63, 211},
            }
            local WHITE_COLORS = {
                {255, 255, 255},
            }
            local BLACK_COLORS = {
                {0, 0, 0},
                {15, 12, 5},
                {38, 28, 8},
                {12, 9, 3},
            }

            local function matchColor(c, list, tol)
                tol = tol or 40
                for _, rgb in ipairs(list) do
                    if math.abs(c.R*255 - rgb[1]) < tol
                    and math.abs(c.G*255 - rgb[2]) < tol
                    and math.abs(c.B*255 - rgb[3]) < tol then
                        return true
                    end
                end
                return false
            end

            -- Couleurs accent connues (rose par defaut + ancienne couleur du theme)
            local ACCENT_COLORS = {
                {255, 40, 160},  -- rose par defaut du hub
                {255, 0, 220},   -- variante rose/violet du hub (strokes des rangees)
            }
            -- Ajouter l'ancienne couleur theme pour qu'elle soit remplacee aussi
            if prevAc then
                table.insert(ACCENT_COLORS, {math.floor(prevAc.R*255), math.floor(prevAc.G*255), math.floor(prevAc.B*255)})
            end

            local function isThemeColor(c)
                return matchColor(c, GOLD_COLORS) or matchColor(c, BLUE_COLORS) or matchColor(c, PURPLE_COLORS) or matchColor(c, ACCENT_COLORS, 25)
            end

            local function recolorGui(sg)
                if not sg then return end
                pcall(function()
                    for _, obj in ipairs(sg:GetDescendants()) do
                        pcall(function()
                            if obj:IsA("UIStroke") and isThemeColor(obj.Color) then
                                obj.Color = ac
                            end
                            if obj:IsA("GuiObject") and isThemeColor(obj.BackgroundColor3) then
                                obj.BackgroundColor3 = ac
                            end
                            -- text color stays white
                            if (obj:IsA("ImageLabel") or obj:IsA("ImageButton")) and isThemeColor(obj.ImageColor3) then
                                obj.ImageColor3 = ac
                            end
                        end)
                    end
                end)
            end
            -- Recolorer tous les GUIs du hub via leurs references _G
            pcall(function()
                recolorGui(ScreenGui)
                recolorGui(KeybindGui)
                recolorGui(_G.UIHide_StealTarget)
                recolorGui(_G.UIHide_ClickCommands)
                recolorGui(_G.UIHide_Tools)
                recolorGui(_G.UIHide_Stealers)
                recolorGui(_G.UIHide_AdminPanel)
                recolorGui(_G._adminControlGui)
                -- Admin panel : recolorer + rebuild pour appliquer la nouvelle couleur
                if _G._recolorAdminPanel then
                    pcall(function() _G._recolorAdminPanel(ac) end)
                end
                -- Rebuild complet pour les rows (couleurs hardcodees dans buildRow)
                if _G._refreshAdminPanel then
                    task.defer(function() pcall(_G._refreshAdminPanel) end)
                end
                -- StealBarGui et StatusDisplay par nom
                local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
                local cg = game:GetService("CoreGui")
                local NAMES = {StealBarGui=true, PanelViewUI=true, TwayveHub=true, StatusDisplay=true, KeybindPanel=true, SettingsPanel=true, ActivityFeed=true, HubAdminControl=true, HubAdminPanel=true, InvisStealPanel=true}
                for _, parent in ipairs({pg, cg}) do
                    if parent then
                        for _, sg in ipairs(parent:GetChildren()) do
                            if NAMES[sg.Name] then recolorGui(sg) end
                        end
                    end
                end
            end)
        end
        _G._setHubTheme = setTheme

        -- HSV Color Picker
        local _hue, _sat, _val = 0, 1, 1
        local sH, sS, sV, preview, hexLbl, applyBtn

        -- Titre
        local lbl = Instance.new("TextLabel", colorsContent)
        lbl.Size = UDim2.new(1, -90, 0, 22)
        lbl.Position = UDim2.new(0, 10, 0, 8)
        lbl.BackgroundTransparency = 1
        lbl.Text = "COULEUR DU HUB"
        lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left

        -- Preview swatch (haut droite)
        preview = Instance.new("Frame", colorsContent)
        preview.Size = UDim2.new(0, 62, 0, 62)
        preview.Position = UDim2.new(1, -72, 0, 6)
        preview.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        preview.BorderSizePixel = 0
        Instance.new("UICorner", preview).CornerRadius = UDim.new(0, 12)
        local prevStroke = Instance.new("UIStroke", preview)
        prevStroke.Color = Color3.fromRGB(80, 80, 120); prevStroke.Thickness = 1.5

        local function getColor() return Color3.fromHSV(_hue, _sat, _val) end

        local function refreshAll()
            local c = getColor()
            preview.BackgroundColor3 = c
            prevStroke.Color = c
            local r,g,b = math.floor(c.R*255), math.floor(c.G*255), math.floor(c.B*255)
            if hexLbl then hexLbl.Text = string.format("#%02X%02X%02X", r, g, b) end
            if sS and sS.grad then
                sS.grad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(_hue, 0, _val)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(_hue, 1, _val)),
                })
            end
            if sV and sV.grad then
                sV.grad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(_hue, _sat, 0)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(_hue, _sat, 1)),
                })
            end
        end

        local UIS = game:GetService("UserInputService")
        local function makeSlider(yPos, label, getGrad, onValue, initPct)
            local TRACK_H = 14; local KNOB_SZ = 18
            local row = Instance.new("Frame", colorsContent)
            row.Size = UDim2.new(1, -20, 0, 32)
            row.Position = UDim2.new(0, 10, 0, yPos)
            row.BackgroundTransparency = 1

            local lbL = Instance.new("TextLabel", row)
            lbL.Size = UDim2.new(0, 14, 1, 0)
            lbL.BackgroundTransparency = 1
            lbL.Text = label
            lbL.TextColor3 = Color3.fromRGB(160, 160, 200)
            lbL.Font = Enum.Font.GothamBold
            lbL.TextSize = 11
            lbL.TextXAlignment = Enum.TextXAlignment.Left

            local track = Instance.new("Frame", row)
            track.Size = UDim2.new(1, -20, 0, TRACK_H)
            track.Position = UDim2.new(0, 18, 0.5, -TRACK_H/2)
            track.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
            track.BorderSizePixel = 0
            Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
            local grad = Instance.new("UIGradient", track)
            grad.Color = getGrad()

            local knob = Instance.new("Frame", track)
            knob.Size = UDim2.new(0, KNOB_SZ, 0, KNOB_SZ)
            knob.AnchorPoint = Vector2.new(0.5, 0.5)
            knob.Position = UDim2.new(initPct, 0, 0.5, 0)
            knob.BackgroundColor3 = Color3.fromRGB(240, 240, 255)
            knob.BorderSizePixel = 0
            knob.ZIndex = 10
            Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
            local ks = Instance.new("UIStroke", knob)
            ks.Color = Color3.fromRGB(100, 100, 140); ks.Thickness = 1.5

            local dragging = false
            local function drag(inputX)
                local ax = track.AbsolutePosition.X
                local aw = track.AbsoluteSize.X
                local pct = math.clamp((inputX - ax) / aw, 0, 1)
                knob.Position = UDim2.new(pct, 0, 0.5, 0)
                onValue(pct)
                refreshAll()
            end
            track.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true; drag(inp.Position.X)
                end
            end)
            knob.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
            end)
            UIS.InputChanged:Connect(function(inp)
                if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
                    drag(inp.Position.X)
                end
            end)
            UIS.InputEnded:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
            end)

            local function setKnob(pct) knob.Position = UDim2.new(math.clamp(pct,0,1), 0, 0.5, 0) end
            return {grad=grad, setKnob=setKnob}
        end

        sH = makeSlider(80, "H",
            function()
                return ColorSequence.new({
                    ColorSequenceKeypoint.new(0,    Color3.fromHSV(0,   1, 1)),
                    ColorSequenceKeypoint.new(1/6,  Color3.fromHSV(1/6, 1, 1)),
                    ColorSequenceKeypoint.new(2/6,  Color3.fromHSV(2/6, 1, 1)),
                    ColorSequenceKeypoint.new(3/6,  Color3.fromHSV(3/6, 1, 1)),
                    ColorSequenceKeypoint.new(4/6,  Color3.fromHSV(4/6, 1, 1)),
                    ColorSequenceKeypoint.new(5/6,  Color3.fromHSV(5/6, 1, 1)),
                    ColorSequenceKeypoint.new(1,    Color3.fromHSV(1,   1, 1)),
                })
            end,
            function(pct) _hue = pct end, 0)

        sS = makeSlider(120, "S",
            function()
                return ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(_hue, 0, _val)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(_hue, 1, _val)),
                })
            end,
            function(pct) _sat = pct end, 1)

        sV = makeSlider(160, "V",
            function()
                return ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromHSV(_hue, _sat, 0)),
                    ColorSequenceKeypoint.new(1, Color3.fromHSV(_hue, _sat, 1)),
                })
            end,
            function(pct) _val = pct end, 1)

        hexLbl = Instance.new("TextLabel", colorsContent)
        hexLbl.Size = UDim2.new(1, -90, 0, 18)
        hexLbl.Position = UDim2.new(0, 10, 0, 198)
        hexLbl.BackgroundTransparency = 1
        hexLbl.Text = "#FF0000"
        hexLbl.TextColor3 = Color3.fromRGB(140, 140, 180)
        hexLbl.Font = Enum.Font.GothamBold
        hexLbl.TextSize = 11
        hexLbl.TextXAlignment = Enum.TextXAlignment.Left

        applyBtn = Instance.new("TextButton", colorsContent)
        applyBtn.Size = UDim2.new(1, -20, 0, 36)
        applyBtn.Position = UDim2.new(0, 10, 0, 222)
        applyBtn.BackgroundColor3 = Color3.fromRGB(255, 40, 160)
        applyBtn.BorderSizePixel = 0
        applyBtn.Text = "APPLIQUER"
        applyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        applyBtn.Font = Enum.Font.GothamBold
        applyBtn.TextSize = 13
        applyBtn.AutoButtonColor = false
        Instance.new("UICorner", applyBtn).CornerRadius = UDim.new(0, 10)

        applyBtn.MouseButton1Click:Connect(function()
            local c = getColor()
            setTheme(c)
            applyBtn.BackgroundColor3 = c
        end)

        -- Charger la couleur sauvegardee
        task.defer(function()
            local function applyInit(c)
                local h,s,v = c:ToHSV()
                _hue, _sat, _val = h, s, v
                sH.setKnob(h); sS.setKnob(s); sV.setKnob(v)
                refreshAll()
                applyBtn.BackgroundColor3 = c
                setTheme(c)
            end
            local saved = nil
            pcall(function() saved = SettingsObj:GetAttribute("SavedHubTheme") end)
            if saved == "custom" then
                local r, g, b
                pcall(function()
                    r = SettingsObj:GetAttribute("SavedHubColorR")
                    g = SettingsObj:GetAttribute("SavedHubColorG")
                    b = SettingsObj:GetAttribute("SavedHubColorB")
                end)
                if r and g and b then applyInit(Color3.fromRGB(r, g, b))
                else                  applyInit(Color3.fromRGB(255, 40, 160)) end
            elseif saved == "blue"   then applyInit(Color3.fromRGB(50,  130, 255))
            elseif saved == "gold"   then applyInit(Color3.fromRGB(255, 0,   220))
            elseif saved == "purple" then applyInit(Color3.fromRGB(160, 80,  255))
            elseif saved == "bw"     then applyInit(Color3.fromRGB(255, 255, 255))
            else                          applyInit(Color3.fromRGB(255, 40,  160))
            end
        end)
    end
end -- Colors tab

end -- KB setup do

-- ── Position: left of MainFrame ───────────────────────────────────────────────
local function positionKBFrame()
	if _guiUserMoved["KBFrame"] then return end
	local vpx = Camera.ViewportSize.X
	local mainX = vpx / 2 + 245 + 80 + 15
	KBFrame.Position = UDim2.new(0, mainX - KB_W - 8, 1, -KB_H - 10)
end
positionKBFrame()
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(positionKBFrame)

-- ── Key capture for remapping ─────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(input, gp)
	if not listeningSlot then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local keyName = input.KeyCode.Name
	if keyName == "Unknown" or keyName == "Escape" then
		local slot = listeningSlot
		slot.listening = false
		slot.btn.Text = _G[slot.def.gKey] or slot.def.default
		slot.btn.TextColor3 = WHITE
		local s = slot.btn:FindFirstChildOfClass("UIStroke")
		if s then s.Color = BORDER_COLOR end
		listeningSlot = nil
		KBHint.Text = "Click a button then press any key to remap"
		return
	end
	local slot = listeningSlot
	_G[slot.def.gKey] = keyName
	SettingsObj:SetAttribute(slot.def.attrKey, keyName)
	slot.listening = false
	slot.btn.Text = keyName
	slot.btn.TextColor3 = WHITE
	local s = slot.btn:FindFirstChildOfClass("UIStroke")
	if s then s.Color = BORDER_COLOR end
	listeningSlot = nil
	KBHint.Text = "Click a button then press any key to remap"
	slot.btn.TextColor3 = TOGGLE_GREEN
	task.delay(0.8, function() if slot.btn and slot.btn.Parent then slot.btn.TextColor3 = WHITE end end)
end)

-- ── Close button ─────────────────────────────────────────────────────────────
KBClose.MouseButton1Click:Connect(function()
	keybindPanelVisible = false
	KBFrame.Visible = false
	if listeningSlot then
		listeningSlot.listening = false
		listeningSlot.btn.Text = _G[listeningSlot.def.gKey] or listeningSlot.def.default
		listeningSlot.btn.TextColor3 = WHITE
		listeningSlot = nil
	end
end)

-- ── Dragging ─────────────────────────────────────────────────────────────────
makeDraggable(KBFrame, "KBFrame", KBTitle)
-- makeResizable(KBFrame, 320, 160)
_G._kbFrame = KBFrame
pcall(addGlowBorder, KBFrame)

local function toggleKeybindPanel()
	keybindPanelVisible = not keybindPanelVisible
	KBFrame.Visible = keybindPanelVisible
	if not keybindPanelVisible and listeningSlot then
		listeningSlot.listening = false
		listeningSlot.btn.Text = _G[listeningSlot.def.gKey] or listeningSlot.def.default
		listeningSlot.btn.TextColor3 = WHITE
		listeningSlot = nil
	end
	if keybindPanelVisible then
		for _, row in ipairs(_kbRows) do
			row.btn.Text = _G[row.def.gKey] or row.def.default
		end
	end
end
_G._toggleKeybindPanel = toggleKeybindPanel

local function getKeybind(attrName, default)
	local saved = SettingsObj:GetAttribute(attrName)
	if saved and Enum.KeyCode[saved] then return Enum.KeyCode[saved] end
	return Enum.KeyCode[default]
end

local function positionGuis()
	if _guiUserMoved["MainFrame"] then return end
	local vpx = Camera.ViewportSize.X
	local guiX = vpx / 2 + 245 + 80 + 15
	MainFrame.Position = UDim2.new(0, guiX, 1, -MAIN_H - 10)
end
positionGuis()
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(positionGuis)
makeDraggable(MainFrame, "MainFrame", TitleLabel)
-- makeResizable(MainFrame, 200, 60) -- hidden

-- ═══════════════════════════════════════
-- SLIDER INPUT
-- ═══════════════════════════════════════
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if draggingSlider then draggingSlider.finish(); draggingSlider = nil end
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if draggingSlider then draggingSlider.update(input) end
end)

-- ═══════════════════════════════════════
-- ═══════════════════════════════════════
local function findMyBase()
	local plots = Workspace:FindFirstChild("Plots")
	if not plots then return nil end
	local n = LocalPlayer.Name:lower(); local d = LocalPlayer.DisplayName:lower()
	for _, p in ipairs(plots:GetChildren()) do
		local s = p:FindFirstChild("PlotSign")
		local l = s and s:FindFirstChildWhichIsA("TextLabel", true)
		if l and (l.Text:lower():find(n) or l.Text:lower():find(d)) then return p end
	end
	return nil
end



-- ═══════════════════════════════════════
-- SPEED
-- ═══════════════════════════════════════




-- Auto Buy toggle
_G.AutoBuyEnabled = false
_G._AutoBuyTarget = nil
_G._AutoBuyConns = {}
_G._AutoBuyBodyPos = nil

local function stopAutoBuy()
	_G.AutoBuyEnabled = false
	for _, c in ipairs(_G._AutoBuyConns or {}) do pcall(function() c:Disconnect() end) end
	_G._AutoBuyConns = {}
	if _G._AutoBuyBodyPos then pcall(function() _G._AutoBuyBodyPos:Destroy() end); _G._AutoBuyBodyPos = nil end
	_G._AutoBuyTarget = nil
end

local function startAutoBuy()
	stopAutoBuy()
	_G.AutoBuyEnabled = true

	local HOVER_HEIGHT = 5

	local Datas2 = ReplicatedStorage:FindFirstChild("Datas")
	local Shared2 = ReplicatedStorage:FindFirstChild("Shared")
	local Utils2 = ReplicatedStorage:FindFirstChild("Utils")
	if not Datas2 or not Shared2 or not Utils2 then return end
	local AnimalsData2 = require(Datas2:FindFirstChild("Animals"))
	local AnimalsShared2 = require(Shared2:FindFirstChild("Animals"))
	local NumberUtils2 = require(Utils2:FindFirstChild("NumberUtils"))
	local KN = {}; local KNL = {}
	for n, inf in pairs(AnimalsData2) do KN[n]=n; KNL[n:lower()]=n; if inf.DisplayName then KN[inf.DisplayName]=n; KNL[inf.DisplayName:lower()]=n end end

	local function _abRoot(m) return m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head") or m:FindFirstChildWhichIsA("BasePart",true) end
	local function _abInt(m) if KN[m.Name] then return KN[m.Name] end; if KNL[m.Name:lower()] then return KNL[m.Name:lower()] end; local i=m:GetAttribute("Index") or m:GetAttribute("AnimalIndex"); if i then if KN[i] then return KN[i] end; if KNL[i:lower()] then return KNL[i:lower()] end end; return nil end

	local function _abScan()
		local r={}
		local plots=Workspace:FindFirstChild("Plots")
		local function tr(m)
			if not m:IsA("Model") then return end
			-- Skip player characters
			for _,plr in ipairs(Players:GetPlayers()) do if plr.Character and m:IsDescendantOf(plr.Character) then return end end
			-- Skip brainrots owned/placed on plots
			if plots and m:IsDescendantOf(plots) then return end
			local int=_abInt(m); if not int then return end
			local rt=_abRoot(m); if not rt then return end
			local mut=m:GetAttribute("Mutation") or "None"; if mut=="" then mut="None" end
			local traits={}; local ta=m:GetAttribute("Traits"); if ta and type(ta)=="table" then traits=ta end
			local ok,g=pcall(function() return AnimalsShared2:GetGeneration(int,mut,traits,nil) end); g=(ok and g) or 0
			local inf=AnimalsData2[int]; local displayName=(inf and inf.DisplayName) or m.Name
			table.insert(r,{model=m,root=rt,name=displayName,gen=g,genText="$"..NumberUtils2:ToString(g).."/s"})
		end
		-- Scan named carpet folders first
		for _,fn in ipairs({"Animals","SpawnedAnimals","WildAnimals","Carpet"}) do
			local f=Workspace:FindFirstChild(fn); if f then for _,c in ipairs(f:GetChildren()) do pcall(tr,c) end end
		end
		-- Also scan top-level workspace models (carpet brainrots spawn here)
		for _,c in ipairs(Workspace:GetChildren()) do
			if c:IsA("Model") and c.Name~="Plots" and c.Name~="Map" and c.Name~="Terrain" and c.Name~="Camera" then pcall(tr,c) end
		end
		-- Sort by NEAREST to the local player (was: by highest gen)
		local _myHrp
		do
			local _ch = LocalPlayer.Character
			_myHrp = _ch and _ch:FindFirstChild("HumanoidRootPart")
		end
		local _myPos = _myHrp and _myHrp.Position or Vector3.new(0,0,0)
		for _, e in ipairs(r) do
			e.dist = (e.root.Position - _myPos).Magnitude
		end
		table.sort(r, function(a, b) return a.dist < b.dist end); return r
	end

	-- BodyPosition hover (Bully's approach - physics-driven, not CFrame teleport)
	local function ensureBodyPos(hrp)
		if _G._AutoBuyBodyPos and _G._AutoBuyBodyPos.Parent == hrp then return _G._AutoBuyBodyPos end
		if _G._AutoBuyBodyPos then pcall(function() _G._AutoBuyBodyPos:Destroy() end) end
		local bp = Instance.new("BodyPosition", hrp)
		bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bp.P = 20000; bp.D = 1000; bp.Position = hrp.Position
		_G._AutoBuyBodyPos = bp
		return bp
	end

	local function destroyBodyPos()
		if _G._AutoBuyBodyPos then pcall(function() _G._AutoBuyBodyPos:Destroy() end); _G._AutoBuyBodyPos = nil end
	end

	local function getTargetPart()
		if not _G._AutoBuyTarget or not _G._AutoBuyTarget.model or not _G._AutoBuyTarget.model.Parent then return nil end
		local r = _abRoot(_G._AutoBuyTarget.model)
		return (r and r.Parent) and r or nil
	end

	local function getTargetPrompt()
		if not _G._AutoBuyTarget or not _G._AutoBuyTarget.model or not _G._AutoBuyTarget.model.Parent then return nil end
		for _, d in ipairs(_G._AutoBuyTarget.model:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Enabled then return d end
		end
		return nil
	end

	-- Equip carpet
	pcall(function()
		local ch = LocalPlayer.Character; local hm = ch and ch:FindFirstChildOfClass("Humanoid")
		if hm then
			local carp = LocalPlayer.Backpack:FindFirstChild("Flying Carpet") or ch:FindFirstChild("Flying Carpet")
			if carp then hm:EquipTool(carp) end
		end
	end)

	-- Initial target lock
	local list = _abScan()
	if #list > 0 then
		_G._AutoBuyTarget = list[1]
	end

	-- Hover loop: BodyPosition moves player smoothly (no teleport detection)
	table.insert(_G._AutoBuyConns, RunService.Heartbeat:Connect(function()
		if not _G.AutoBuyEnabled then destroyBodyPos(); return end
		local tp = getTargetPart()
		if not tp then destroyBodyPos(); return end
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then destroyBodyPos(); return end
		local bp = ensureBodyPos(hrp)
		bp.Position = tp.Position + Vector3.new(0, HOVER_HEIGHT, 0)
	end))

	-- Carpet lock: keep carpet equipped (throttled)
	do local _clF = 0; table.insert(_G._AutoBuyConns, RunService.Heartbeat:Connect(function()
		if not _G.AutoBuyEnabled then return end
		_clF = _clF + 1; if _clF < 10 then return end; _clF = 0
		pcall(function()
			local char = LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not hum then return end
			if not char:FindFirstChild("Flying Carpet") then
				local tool = LocalPlayer.Backpack:FindFirstChild("Flying Carpet")
				if tool then hum:EquipTool(tool) end
			end
		end)
	end)) end

	-- Purchase loop: fires every 6 frames (~10/s), single prompt fire to keep ping stable
	do local _buyF = 0; table.insert(_G._AutoBuyConns, RunService.Heartbeat:Connect(function()
		if not _G.AutoBuyEnabled then return end
		_buyF = _buyF + 1; if _buyF < 6 then return end; _buyF = 0
		local prompt = getTargetPrompt()
		if not prompt then return end
		pcall(function()
			local oldHold = prompt.HoldDuration
			local oldDist = prompt.MaxActivationDistance
			local oldLOS = prompt.RequiresLineOfSight
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 9999
			prompt.RequiresLineOfSight = false
			if fireproximityprompt then fireproximityprompt(prompt) end
			prompt.HoldDuration = oldHold
			prompt.MaxActivationDistance = oldDist
			prompt.RequiresLineOfSight = oldLOS
		end)
	end)) end

	-- Retarget helper: picks NEAREST from scan result and switches if warranted
	local function _abRetarget(l)
		if #l > 0 then
			local best = l[1]
			local current = _G._AutoBuyTarget
			if not current or not current.model or not current.model.Parent then
				_G._AutoBuyTarget = best
			elseif not getTargetPrompt() then
				-- Current has no prompt (bought/gone), grab nearest
				_G._AutoBuyTarget = best
			else
				-- Switch only if the new nearest is meaningfully closer
				-- (avoids thrashing between two near-equidistant targets)
				local _ch = LocalPlayer.Character
				local _hrp = _ch and _ch:FindFirstChild("HumanoidRootPart")
				if _hrp and current.model and current.model.Parent and best.model ~= current.model then
					local curRoot = _abRoot(current.model)
					if curRoot then
						local curDist  = (curRoot.Position - _hrp.Position).Magnitude
						local bestDist = (best.dist) or ((best.root.Position - _hrp.Position).Magnitude)
						if bestDist < curDist - 4 then
							_G._AutoBuyTarget = best
						end
					end
				end
			end
		else
			_G._AutoBuyTarget = nil
		end
	end

	-- Event-driven rescan: fires the instant a new model lands in any spawn folder
	-- This catches a newly spawned high-gen brainrot without waiting for the poll
	local _abSpawnFolders = {"Animals", "SpawnedAnimals", "WildAnimals", "Carpet"}
	for _, fn in ipairs(_abSpawnFolders) do
		local folder = Workspace:FindFirstChild(fn)
		if folder then
			table.insert(_G._AutoBuyConns, folder.ChildAdded:Connect(function(child)
				if not _G.AutoBuyEnabled then return end
				-- Small defer so the new model's attributes (Index, Mutation, etc.) are replicated
				task.defer(function()
					if not _G.AutoBuyEnabled then return end
					_abRetarget(_abScan())
				end)
			end))
			table.insert(_G._AutoBuyConns, folder.ChildRemoved:Connect(function()
				if not _G.AutoBuyEnabled then return end
				task.defer(function()
					if not _G.AutoBuyEnabled then return end
					_abRetarget(_abScan())
				end)
			end))
		end
	end
	-- Also watch top-level workspace for carpet brainrots that spawn there directly
	table.insert(_G._AutoBuyConns, Workspace.ChildAdded:Connect(function(child)
		if not _G.AutoBuyEnabled then return end
		if not child:IsA("Model") then return end
		task.defer(function()
			if not _G.AutoBuyEnabled then return end
			_abRetarget(_abScan())
		end)
	end))

	-- Safety poll loop (0.5s): catches anything the events miss (late attribute sets, etc.)
	task.spawn(function()
		while _G.AutoBuyEnabled do
			task.wait(0.5)
			if not _G.AutoBuyEnabled then break end
			_abRetarget(_abScan())
		end
	end)
end

local autoBuyEnabled = false
local function _toggleAutoBuy()
	autoBuyEnabled = not autoBuyEnabled
	AutoBuyBtn.Text = autoBuyEnabled and "Auto Buy ON" or "Auto Buy OFF"
	AutoBuyBtn.TextColor3 = autoBuyEnabled and TOGGLE_GREEN or BRICK_RED
	if autoBuyEnabled then
		-- Mutual exclusion: Auto Buy ON => Stay OFF
		if _G.StayEnabled and _G._stopStay then _G._stopStay() end
		task.spawn(startAutoBuy)
	else
		task.spawn(stopAutoBuy)
	end
end
AutoBuyBtn.MouseButton1Click:Connect(_toggleAutoBuy)

-- "K" keybind to toggle auto-buy on/off
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.K then _toggleAutoBuy() end
end)

-- ═══════════════════════════════════════
-- STAY (locks onto whatever Auto Buy was targeting)
-- Mutually exclusive with Auto Buy.
-- ═══════════════════════════════════════
_G.StayEnabled  = false
_G._StayTarget  = nil
_G._StayConns   = {}
_G._StayBodyPos = nil

local function _stayRoot(m)
	return m.PrimaryPart
		or m:FindFirstChild("HumanoidRootPart")
		or m:FindFirstChild("Head")
		or m:FindFirstChildWhichIsA("BasePart", true)
end

local function stopStay()
	_G.StayEnabled = false
	for _, c in ipairs(_G._StayConns or {}) do pcall(function() c:Disconnect() end) end
	_G._StayConns = {}
	if _G._StayBodyPos then pcall(function() _G._StayBodyPos:Destroy() end); _G._StayBodyPos = nil end
	_G._StayTarget = nil
	if StayBtn and StayBtn.Parent then
		StayBtn.Text = "Stay"
		StayBtn.TextColor3 = BRICK_RED
	end
end
_G._stopStay = stopStay

local function startStay(target)
	stopStay()
	if not target or not target.model or not target.model.Parent then return false end
	_G.StayEnabled = true
	_G._StayTarget = target
	StayBtn.TextColor3 = TOGGLE_GREEN

	-- Equip carpet so we can hover (matches Auto Buy behavior)
	pcall(function()
		local ch = LocalPlayer.Character; local hm = ch and ch:FindFirstChildOfClass("Humanoid")
		if hm then
			local carp = LocalPlayer.Backpack:FindFirstChild("Flying Carpet") or ch:FindFirstChild("Flying Carpet")
			if carp then hm:EquipTool(carp) end
		end
	end)

	-- Hover loop: park on the brainrot's root (the spot where the prompt sits)
	table.insert(_G._StayConns, RunService.Heartbeat:Connect(function()
		if not _G.StayEnabled then return end
		local t = _G._StayTarget
		if not t or not t.model or not t.model.Parent then stopStay(); return end
		local rt = _stayRoot(t.model); if not rt then return end
		local char = LocalPlayer.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart"); if not hrp then return end
		if not _G._StayBodyPos or _G._StayBodyPos.Parent ~= hrp then
			if _G._StayBodyPos then pcall(function() _G._StayBodyPos:Destroy() end) end
			local bp = Instance.new("BodyPosition", hrp)
			bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			bp.P = 20000; bp.D = 1000
			_G._StayBodyPos = bp
		end
		_G._StayBodyPos.Position = rt.Position  -- middle of the brainrot
	end))

	-- Carpet keep-equipped (throttled, mirrors Auto Buy)
	do local _f = 0; table.insert(_G._StayConns, RunService.Heartbeat:Connect(function()
		if not _G.StayEnabled then return end
		_f = _f + 1; if _f < 10 then return end; _f = 0
		pcall(function()
			local char = LocalPlayer.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid"); if not hum then return end
			if not char:FindFirstChild("Flying Carpet") then
				local tool = LocalPlayer.Backpack:FindFirstChild("Flying Carpet")
				if tool then hum:EquipTool(tool) end
			end
		end)
	end)) end

	return true
end

StayBtn.MouseButton1Click:Connect(function()
	if _G.StayEnabled then
		stopStay()
		return
	end

	-- Capture what Auto Buy is currently buying BEFORE we shut it off
	local target = _G._AutoBuyTarget

	-- Mutual exclusion: Stay ON => Auto Buy OFF
	if autoBuyEnabled then
		autoBuyEnabled = false
		AutoBuyBtn.Text = "Auto Buy OFF"
		AutoBuyBtn.TextColor3 = BRICK_RED
		task.spawn(stopAutoBuy)
	end

	if not target or not target.model or not target.model.Parent then
		flashBtnRed(StayBtn, "Stay")  -- nothing to lock onto
		return
	end
	startStay(target)
end)

-- ═══════════════════════════════════════
-- AUTO KICK
-- ═══════════════════════════════════════
local STEAL_KEYWORD = "you stole"; local kickDetectorConns = {}
local STEAL_KEYWORDS = {"you stole", "vole", "volé", "gestohlen", "robado", "rubato"}
local function hasStealKeyword(text)
    if typeof(text) ~= "string" then return false end
    local low = string.lower(text)
    for _, kw in ipairs(STEAL_KEYWORDS) do
        if low:find(kw, 1, true) then return true end
    end
    return false
end
local function kickPlayer()
    _G.YouStoleFlag = true  -- signal TP module: local player just stole successfully
    task.delay(2.5, function() _G.YouStoleFlag = false end)
    pcall(function() game:Shutdown() end)
end
local function scanGuiObjects(parent)
	for _, obj in ipairs(parent:GetDescendants()) do
		if obj.ClassName == "TextLabel" or obj.ClassName == "TextButton" or obj.ClassName == "TextBox" then
			if hasStealKeyword(obj.Text) then
				_G.YouStoleFlag = true; task.delay(2.5, function() _G.YouStoleFlag = false end)
				if autoKickEnabled then kickPlayer() end; return true
			end
			table.insert(kickDetectorConns, obj:GetPropertyChangedSignal("Text"):Connect(function()
				if hasStealKeyword(obj.Text) then
					_G.YouStoleFlag = true; task.delay(2.5, function() _G.YouStoleFlag = false end)
					if autoKickEnabled then kickPlayer() end
				end
			end))
		end
	end; return false
end
local function setupGuiWatcher(gui)
	table.insert(kickDetectorConns, gui.DescendantAdded:Connect(function(desc)
		if desc.ClassName == "TextLabel" or desc.ClassName == "TextButton" or desc.ClassName == "TextBox" then
			if hasStealKeyword(desc.Text) then
				_G.YouStoleFlag = true; task.delay(2.5, function() _G.YouStoleFlag = false end)
				if autoKickEnabled then kickPlayer() end
			end
			table.insert(kickDetectorConns, desc:GetPropertyChangedSignal("Text"):Connect(function()
				if hasStealKeyword(desc.Text) then
					_G.YouStoleFlag = true; task.delay(2.5, function() _G.YouStoleFlag = false end)
					if autoKickEnabled then kickPlayer() end
				end
			end))
		end
	end))
end
function enableAutoKick()
	if autoKickEnabled then return end; autoKickEnabled = true
	for _, gui in ipairs(playerGui:GetChildren()) do if gui ~= ScreenGui then setupGuiWatcher(gui); scanGuiObjects(gui) end end
	table.insert(kickDetectorConns, playerGui.ChildAdded:Connect(function(gui) if not autoKickEnabled then return end; if gui ~= ScreenGui then setupGuiWatcher(gui); scanGuiObjects(gui) end end))
end
function disableAutoKick()
	if not autoKickEnabled then return end; autoKickEnabled = false
	for _, conn in ipairs(kickDetectorConns) do if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end end; kickDetectorConns = {}
end
AutoKickBtn.MouseButton1Click:Connect(function()
	if autoKickEnabled then disableAutoKick() else enableAutoKick() end
	setToggleBtnState(AutoKickBtn, autoKickEnabled, "Auto Kick ON", "Auto Kick OFF")
	pcall(function() SettingsObj:SetAttribute("SavedAutoKick", autoKickEnabled) end)
end)

-- ═══════════════════════════════════════
-- AUTO TURRET (Q)
-- ═══════════════════════════════════════
local originalBatSize = nil; local mySentries = {}; local lastSentryPlaceTime = 0; local lastSentryPlacePosition = nil; local turretConnection = nil; local turretSetupDone = false
local function forceBatEquip()
	local char = LocalPlayer.Character; if not char then return nil, nil end
	local backpack = LocalPlayer:FindFirstChild("Backpack"); if not backpack then return nil, nil end
	local bat = backpack:FindFirstChild("Bat") or char:FindFirstChild("Bat"); if not bat then return nil, nil end
	bat.Parent = char; task.wait(0.05)
	local handle = bat:FindFirstChild("Handle"); if handle and not originalBatSize then originalBatSize = handle.Size end; return bat, handle
end
local function restoreBat(bat, handle)
	if bat and handle and originalBatSize then handle.Size = originalBatSize; handle.CanCollide = true; handle.Transparency = 0 end
	if bat and LocalPlayer:FindFirstChild("Backpack") then bat.Parent = LocalPlayer.Backpack end
end
local function getSentryTimer(turret) for _, child in pairs(turret:GetDescendants()) do if child:IsA("TextLabel") or child:IsA("TextBox") then local n = child.Text:match("(%d+)s!"); if n then return tonumber(n) end end end; return nil end
local function isMySentry(s) return mySentries[s] == true end
local function markAsMySentry(sentry)
	if mySentries[sentry] then return end; mySentries[sentry] = true
	local hl = Instance.new("Highlight"); hl.Name = "OL_" .. tostring(math.random(1000,9999))
	hl.FillColor = Color3.fromRGB(0, 150, 255); hl.OutlineColor = Color3.fromRGB(0, 255, 255)
	hl.FillTransparency = 0.7; hl.OutlineTransparency = 0; hl.Parent = sentry
	sentry.AncestryChanged:Connect(function(_, parent) if not parent then mySentries[sentry] = nil end end)
	-- Timer text visible for our sentries only
end
local function stripSentryTimer(sentry)
	pcall(function()
		for _, desc in ipairs(sentry:GetDescendants()) do
			if desc:IsA("BillboardGui") then desc.Enabled = false end
		end
	end)
end
local function attackSentry(sentry)
	if not autoTurretEnabled or isMySentry(sentry) then return end
	stripSentryTimer(sentry)
	task.spawn(function()
		local bat, handle = forceBatEquip(); if not bat or not handle then return end
		handle.Size = Vector3.new(9999, 1002, 190); handle.CanCollide = false; handle.Transparency = 1
		local char = LocalPlayer.Character; if not char then restoreBat(bat, handle); return end
		local equipPhase = true
		while sentry and sentry.Parent and autoTurretEnabled and not isMySentry(sentry) do
			local timer = getSentryTimer(sentry); if not timer then task.wait(0.02); continue end
			if equipPhase then bat.Parent = char else local bp = LocalPlayer:FindFirstChild("Backpack"); if bp then bat.Parent = bp end end
			equipPhase = not equipPhase
			if bat.Parent ~= char then bat.Parent = char; task.wait(0.01) end
			pcall(function() bat:Activate() end)
			for _, remote in pairs(bat:GetDescendants()) do if remote:IsA("RemoteEvent") then pcall(function() remote:FireServer() end) end end
			task.wait(0.02)
		end; restoreBat(bat, handle)
	end)
end
local function setupSentryToolWatcher()
	if turretSetupDone then return end; turretSetupDone = true
	local function watchTool(tool)
		if tool.Name == "All Seeing Sentry" then tool.Activated:Connect(function()
			local char = LocalPlayer.Character; if char and char:FindFirstChild("HumanoidRootPart") then lastSentryPlaceTime = tick(); lastSentryPlacePosition = char.HumanoidRootPart.Position end
		end) end
	end
	task.spawn(function()
		local backpack = LocalPlayer:WaitForChild("Backpack", 10); if not backpack then return end
		for _, tool in pairs(backpack:GetChildren()) do watchTool(tool) end; backpack.ChildAdded:Connect(function(tool) watchTool(tool) end)
	end)
	if LocalPlayer.Character then for _, tool in pairs(LocalPlayer.Character:GetChildren()) do watchTool(tool) end end
	LocalPlayer.CharacterAdded:Connect(function(char) task.wait(0.5); for _, tool in pairs(char:GetChildren()) do watchTool(tool) end; char.ChildAdded:Connect(function(tool) watchTool(tool) end) end)
end
local function onSentrySpawned(obj)
	if not obj.Name:match("^Sentry_%d+$") or not autoTurretEnabled then return end
	local timeSincePlaced = tick() - lastSentryPlaceTime
	if timeSincePlaced < 2 and lastSentryPlacePosition then
		local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
		if pp and (pp.Position - lastSentryPlacePosition).Magnitude < 20 then markAsMySentry(obj); lastSentryPlaceTime = 0; lastSentryPlacePosition = nil; return end
	end
	task.delay(0.1, function() if not isMySentry(obj) then attackSentry(obj) end end)
end
local function enableAutoTurret()
	if turretConnection then return end; autoTurretEnabled = true
	task.spawn(function() setupSentryToolWatcher(); turretConnection = Workspace.ChildAdded:Connect(onSentrySpawned)
		for _, obj in pairs(Workspace:GetChildren()) do if obj.Name:match("^Sentry_%d+$") then stripSentryTimer(obj); if not isMySentry(obj) then attackSentry(obj) end end end end)
end
local function disableAutoTurret() autoTurretEnabled = false; if turretConnection then turretConnection:Disconnect(); turretConnection = nil end end
local function toggleAutoTurret() if autoTurretEnabled then disableAutoTurret() else enableAutoTurret() end; setToggleBtnState(AutoTurretBtn, autoTurretEnabled, "Anti Turret ON", "Anti Turret OFF") end
AutoTurretBtn.MouseButton1Click:Connect(toggleAutoTurret)

-- ═══════════════════════════════════════
-- ═══════════════════════════════════════
RejoinPSBtn.MouseButton1Click:Connect(function() flashBtnGreen(RejoinPSBtn); task.spawn(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end); pcall(function() LocalPlayer:Kick("Rejoining PS!") end) end)

-- Sell button: sells a random brainrot from local player's base
do
    local function _sellFindMyPlots()
        local plots = Workspace:FindFirstChild("Plots"); local mine = {}
        if not plots then return mine end
        for _, plot in ipairs(plots:GetChildren()) do
            local sign = plot:FindFirstChild("PlotSign")
            if sign then
                local yb = sign:FindFirstChild("YourBase")
                if yb and yb:IsA("BillboardGui") and yb.Enabled then table.insert(mine, plot); continue end
                for _, d in ipairs(sign:GetDescendants()) do
                    if d:IsA("TextLabel") then
                        local t = d.Text:lower()
                        if t:find(LocalPlayer.Name:lower(),1,true) or t:find(LocalPlayer.DisplayName:lower(),1,true) then
                            table.insert(mine, plot); break
                        end
                    end
                end
            end
        end
        return mine
    end
    local function _sellFindRandomPrompt()
        local myPlots = _sellFindMyPlots(); if #myPlots == 0 then return nil end
        local valid = {}
        for _, plot in ipairs(myPlots) do
            local podiums = plot:FindFirstChild("AnimalPodiums")
            if podiums then
                for _, podium in ipairs(podiums:GetChildren()) do
                    local hasAnimal = false
                    for _, d in ipairs(podium:GetDescendants()) do
                        if d:IsA("ProximityPrompt") and d.Enabled then hasAnimal = true; break end
                    end
                    if hasAnimal then
                        for _, d in ipairs(podium:GetDescendants()) do
                            if d:IsA("ProximityPrompt") and d.Enabled then
                                local at = (d.ActionText or ""):lower()
                                if at:find("sell") or at:find("collect") or at == "" then table.insert(valid, d); break end
                            end
                        end
                    end
                end
            end
        end
        if #valid == 0 then return nil end
        return valid[math.random(1, #valid)]
    end
    local _selling = false
    local function _doSell()
        if _selling then return end
        _selling = true
        local prompt = _sellFindRandomPrompt()
        if prompt then pcall(function() if fireproximityprompt then fireproximityprompt(prompt) end end) end
        _selling = false
    end
    _G._doSell = _doSell
    SellBtn.MouseButton1Click:Connect(_doSell)

    -- "E" keybind to trigger the sell action
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.E then _doSell() end
    end)
end
RejoinBtn.MouseButton1Click:Connect(function() flashBtnGreen(RejoinBtn); task.spawn(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end) end)

-- ── Balloon instant-reset (ported from dtc.txt) ─────────────────────────────
-- Captures the game's RE/* reset RemoteEvent and fires it for an instant reset
-- that bypasses normal reset cooldowns. executeReset() tries this first, then
-- falls back to the kill+respawn path below if the remote isn't captured yet.
local BALLOON_RESET_GUID = "f888ee6e-c86d-46e1-93d7-0639d6635d42"
_G._balloonResetRemote   = _G._balloonResetRemote or nil
_G._balloonResetCooldown = _G._balloonResetCooldown or false

if not _G._balloonResetHookInstalled and hookfunction and newcclosure then
	_G._balloonResetHookInstalled = true
	pcall(function()
		local orig
		orig = hookfunction(Instance.new("RemoteEvent").FireServer, newcclosure(function(self, ...)
			if not _G._balloonResetRemote and typeof(self) == "Instance" and self:IsA("RemoteEvent") and self.Name:sub(1, 3) == "RE/" then
				_G._balloonResetRemote = self
			end
			return orig(self, ...)
		end))
	end)
end

local function balloonInstaReset()
	if _G._balloonResetCooldown then return false end
	local remote = _G._balloonResetRemote
	if not remote then return false end
	_G._balloonResetCooldown = true
	local oldChar = LocalPlayer.Character
	task.spawn(function()
		-- PATCH: spam plus agressif, timeout raccourci a 1s
		local deadline = tick() + 1
		while LocalPlayer.Character == oldChar and tick() < deadline do
			for _=1,3 do
				pcall(function() remote:FireServer(BALLOON_RESET_GUID, LocalPlayer, "balloon") end)
			end
			task.wait(0.033) -- ~30fps
		end
		_G._balloonResetCooldown = false
	end)
	return true
end

local resetting = false

local function executeReset()
	if resetting then return end
	resetting = true

	-- PATCH: signaler que c'est un reset manuel pour bloquer le re-TP auto
	_G._manualResetActive = true
	local prevAntiDie = _G.AntiDieDisabled
	_G.AntiDieDisabled = true

	if _G.AntiDieConnection then
		pcall(function() _G.AntiDieConnection:Disconnect() end)
		_G.AntiDieConnection = nil
	end

	-- PATCH: mettre RespawnTime = 0 AVANT tout le reste
	pcall(function() Players.RespawnTime = 0 end)
	pcall(function() game:GetService("Players").RespawnTime = 0 end)

	local char = LocalPlayer.Character
	if not char then
		pcall(function() LocalPlayer:LoadCharacter() end)
		_G.AntiDieDisabled = prevAntiDie
		resetting = false
		return
	end

	-- Restore anti-die once new character spawns
	local _respawnConn
	_respawnConn = LocalPlayer.CharacterAdded:Connect(function(newChar)
		if _respawnConn then _respawnConn:Disconnect(); _respawnConn = nil end
		resetting = false
		task.defer(function()
			pcall(function() newChar:WaitForChild("Humanoid", 10) end)
			RunService.Heartbeat:Wait()
			_G.AntiDieDisabled = prevAntiDie
			if not prevAntiDie and _G.setupAntiDie then
				pcall(_G.setupAntiDie)
			end
			pcall(_enableAntiDie)
		end)
		-- Safety: clear manualResetActive after auto-TP handler has time to read it
		task.delay(3, function()
			if _G._manualResetActive then _G._manualResetActive = false end
		end)
	end)

	local hum  = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")

	task.spawn(function() balloonInstaReset() end)

	if hum and root then
		pcall(function() hum.Health = 0 end)
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Dead) end)
		pcall(function() hum:TakeDamage(hum.MaxHealth * 999) end)
		pcall(function() char:BreakJoints() end)
		task.spawn(function()
			pcall(function() LocalPlayer:LoadCharacter() end)
		end)
	end

	task.spawn(function()
		local origChar = char
		task.wait(0.05)
		local i = 0
		while LocalPlayer.Character == origChar and i < 20 do
			pcall(function() LocalPlayer:LoadCharacter() end)
			task.wait(0.033)
			i = i + 1
		end
		-- Cleanup if CharacterAdded never fired
		if _respawnConn then
			_respawnConn:Disconnect(); _respawnConn = nil
			_G.AntiDieDisabled = prevAntiDie
		end
		if _G._manualResetActive then _G._manualResetActive = false end
		resetting = false
	end)
end
_G._executeReset = executeReset
_G.executeReset   = executeReset

-- ═══ Gameplay Paused screen suppressor ═══
-- Detruit le menu "Gameplay Paused" / "please wait while the game content loads"
-- qui apparait pendant le respawn. Surveille CoreGui et PlayerGui en continu.
task.spawn(function()
	local _cg = game:GetService("CoreGui")
	local _pg = LocalPlayer:WaitForChild("PlayerGui", 10)
	local PAUSE_NAMES = {
		GameplayPausedGui = true,
		GameplayPaused    = true,
		LoadingGui        = true,
		RobloxLoadingGui  = true,
		RobloxGamepadGui  = true,
	}
	local function _killPause(obj)
		pcall(function()
			if not obj or not obj.Parent then return end
			if PAUSE_NAMES[obj.Name] then
				obj:Destroy(); return
			end
			-- Cherche le texte "Gameplay Paused" ou "game content loads" dans les enfants
			if obj:IsA("ScreenGui") or obj:IsA("Frame") then
				for _, child in ipairs(obj:GetDescendants()) do
					if (child:IsA("TextLabel") or child:IsA("TextButton")) then
						local t = child.Text or ""
						if t:find("Gameplay") or t:find("game content") or t:find("Paused") then
							-- Remonter au ScreenGui parent et le tuer
							local sg = child
							while sg and not sg:IsA("ScreenGui") do sg = sg.Parent end
							if sg and sg.Parent then sg:Destroy() end
							return
						end
					end
				end
			end
		end)
	end
	-- Surveiller CoreGui
	pcall(function()
		for _, obj in ipairs(_cg:GetChildren()) do _killPause(obj) end
		_cg.ChildAdded:Connect(function(obj)
			task.wait() -- laisser le temps au GUI de se construire
			_killPause(obj)
			task.wait(0.1)
			_killPause(obj) -- double check
		end)
	end)
	-- Surveiller PlayerGui
	pcall(function()
		if not _pg then return end
		for _, obj in ipairs(_pg:GetChildren()) do _killPause(obj) end
		_pg.ChildAdded:Connect(function(obj)
			task.wait()
			_killPause(obj)
			task.wait(0.1)
			_killPause(obj)
		end)
	end)
end)

local function runAdminOnSelf(command)
	-- Use the working ClickAP admin function (try twice)
	if _G._adminpanel then
		local ok = pcall(_G._adminpanel, LocalPlayer, command)
		if not ok then task.wait(0.15); pcall(_G._adminpanel, LocalPlayer, command) end
	else
		-- Fallback
		pcall(function()
			local pg = LocalPlayer:FindFirstChild("PlayerGui")
			local af = pg and pg:FindFirstChild("AdminPanel"); local ap = af and af:FindFirstChild("AdminPanel"); if not ap then return end
			local ps = ap:FindFirstChild("Profiles"); local sc = ps and ps:FindFirstChild("ScrollingFrame")
			local pu = sc and sc:FindFirstChild(LocalPlayer.Name); if not pu then return end; firesignal(pu.Activated); task.wait(0.1)
			local cf = ap:FindFirstChild("Content"); local cs = cf and cf:FindFirstChild("ScrollingFrame")
			local cu = cs and cs:FindFirstChild(command); if not cu then return end; firesignal(cu.Activated)
		end)
	end
end
RagdollSelfBtn.MouseButton1Click:Connect(function()
	local cooldownLen = (_G.ClickAP_Cooldowns and _G.ClickAP_Cooldowns["ragdoll"]) or 30
	local lastUse = _G.ClickAP_LastUse and _G.ClickAP_LastUse["ragdoll"]
	if lastUse and (tick() - lastUse) < cooldownLen then
		local remaining = math.ceil(cooldownLen - (tick() - lastUse))
		flashBtnRed(RagdollSelfBtn, remaining .. "s CD")
		return
	end
	flashBtnGreen(RagdollSelfBtn)
	task.spawn(function() runAdminOnSelf("ragdoll") end)
	if _G.ClickAP_LastUse then _G.ClickAP_LastUse["ragdoll"] = tick() end
	task.spawn(function()
		while true do
			task.wait(0.25)
			local lu = _G.ClickAP_LastUse and _G.ClickAP_LastUse["ragdoll"]
			local cd = (_G.ClickAP_Cooldowns and _G.ClickAP_Cooldowns["ragdoll"]) or 30
			if not lu then RagdollSelfBtn.Text = "Ragdoll Slf"; RagdollSelfBtn.TextColor3 = WHITE; break end
			local rem = cd - (tick() - lu)
			if rem <= 0 then RagdollSelfBtn.Text = "Ragdoll Slf"; RagdollSelfBtn.TextColor3 = WHITE; break end
			RagdollSelfBtn.Text = math.ceil(rem) .. "s"; RagdollSelfBtn.TextColor3 = BRICK_RED
		end
	end)
end)


-- ═══════════════════════════════════════
-- ═══════════════════════════════════════

-- Auto Clone function (same as TP's instantClone)
local function autoClone()
	-- Force-reset stuck isCloning (safety)
	if isCloning and _G._cloneStartTime and (os.clock() - _G._cloneStartTime) > 5 then
		isCloning = false
	end
	if isCloning then return end
	if isTpMoving then return end
	isCloning = true
	_G._cloneStartTime = os.clock()
	_G._manualCloneActive = true
	local savedCF = nil
	pcall(function()
		local char = LocalPlayer.Character
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hum or not hrp then return end
		local cloner = LocalPlayer.Backpack:FindFirstChild("Quantum Cloner") or char:FindFirstChild("Quantum Cloner")
		if not cloner then return end

		savedCF = hrp.CFrame

		-- Destroy existing clone
		local c1 = tostring(LocalPlayer.UserId) .. "Clone"
		local c2 = tostring(LocalPlayer.UserId) .. "_Clone"
		pcall(function() local x = Workspace:FindFirstChild(c1); if x then x:Destroy() end end)
		pcall(function() local x = Workspace:FindFirstChild(c2); if x then x:Destroy() end end)
		task.wait(0.1)

		-- Equip and activate
		hum:EquipTool(cloner)
		task.wait(0.05)
		cloner:Activate()
		task.wait(0.05)

		-- Wait for clone
		local cloneName = c1
		for _ = 1, 60 do
			if Workspace:FindFirstChild(c1) or Workspace:FindFirstChild(c2) then
				cloneName = Workspace:FindFirstChild(c1) and c1 or c2
				break
			end
			task.wait(0.05)
		end

		if not Workspace:FindFirstChild(cloneName) then return end

		-- Find swap button
		local toolsFrames = LocalPlayer.PlayerGui:FindFirstChild("ToolsFrames")
		local qcFrame = toolsFrames and toolsFrames:FindFirstChild("QuantumCloner")
		local tpButton = qcFrame and qcFrame:FindFirstChild("TeleportToClone")
		if not tpButton then tpButton = LocalPlayer.PlayerGui:FindFirstChild("TeleportToClone", true) end

		-- Retry finding button
		if not tpButton then
			for _ = 1, 8 do
				task.wait(0.1)
				toolsFrames = LocalPlayer.PlayerGui:FindFirstChild("ToolsFrames")
				qcFrame = toolsFrames and toolsFrames:FindFirstChild("QuantumCloner")
				tpButton = qcFrame and qcFrame:FindFirstChild("TeleportToClone")
				if not tpButton then tpButton = LocalPlayer.PlayerGui:FindFirstChild("TeleportToClone", true) end
				if tpButton then break end
			end
		end
		if not tpButton then return end

		tpButton.Visible = true
		if firesignal then
			firesignal(tpButton.MouseButton1Up)
			firesignal(tpButton.MouseButton1Click)
			firesignal(tpButton.Activated)
		else
			local vim = game:GetService("VirtualInputManager")
			local inset = game:GetService("GuiService"):GetGuiInset()
			local pos = tpButton.AbsolutePosition + (tpButton.AbsoluteSize / 2) + inset
			vim:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
			task.wait()
			vim:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
		end
	end)
	-- Restore position after swap
	if savedCF then
		task.wait(0.1)
		pcall(function()
			local newHRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if newHRP then newHRP.CFrame = savedCF; newHRP.AssemblyLinearVelocity = Vector3.zero end
		end)
	end
	isCloning = false
	_G._manualCloneActive = false
	_G._cloneStartTime = nil
end

-- ═══ Carpet Speed (Q toggle, 140 speed) ═══
local _carpetSpeedConn = nil
local function toggleCarpetSpeed()
    _carpetSpeedEnabled = not _carpetSpeedEnabled
    if _carpetSpeedConn then _carpetSpeedConn:Disconnect(); _carpetSpeedConn = nil end
    if not _carpetSpeedEnabled then return end

    -- Helper: find a tool in character or backpack by name
    local function findTool(name)
        if not name or name == "" then return nil end
        local char = LocalPlayer.Character
        local bp = LocalPlayer:FindFirstChild("Backpack")
        return (char and char:FindFirstChild(name)) or (bp and bp:FindFirstChild(name))
    end

    _carpetSpeedConn = RunService.Heartbeat:Connect(function()
        if not _carpetSpeedEnabled then return end
        local c = LocalPlayer.Character
        if not c then return end
        local hum = c:FindFirstChild("Humanoid")
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end

        -- Determine which tool to use for speed boost
        local toolName = _G.FlashExtra and _G.FlashExtra.tpTool
        local tool = nil

        -- 1) Try the user‑selected tool
        if toolName and toolName ~= "" then
            tool = findTool(toolName)
        end

        -- 2) Fallback to default list if selected tool not found
        if not tool then
            local defaultTools = {"Flying Carpet", "Cupid's Wings", "Santa's Sleigh", "Witch's Broom"}
            for _, name in ipairs(defaultTools) do
                tool = findTool(name)
                if tool then
                    toolName = name
                    break
                end
            end
        end

        -- If we have a tool, ensure it's equipped and apply speed
        if tool then
            if tool.Parent ~= c then
                pcall(function() hum:EquipTool(tool) end)
            end
            local md = hum.MoveDirection
            local vy = hrp.AssemblyLinearVelocity.Y
            if md.Magnitude > 0 then
                hrp.AssemblyLinearVelocity = Vector3.new(md.X * 140, vy, md.Z * 140)
            else
                hrp.AssemblyLinearVelocity = Vector3.new(0, vy, 0)
            end
        end
    end)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if UserInputService:GetFocusedTextBox() then return end
	if UserInputService:GetFocusedTextBox() then return end
	if Enum.KeyCode[_G.KeybindPanelKeybind or "G"] and input.KeyCode == Enum.KeyCode[_G.KeybindPanelKeybind or "G"] then
		if _G._toggleKeybindPanel then _G._toggleKeybindPanel() end
	end
	if Enum.KeyCode[_G.APKeybind or "G"] and input.KeyCode == Enum.KeyCode[_G.APKeybind or "G"] then
		if toggleClickAP then toggleClickAP() end
	end
	if Enum.KeyCode[_G.RagdollSelfKeybind or "H"] and input.KeyCode == Enum.KeyCode[_G.RagdollSelfKeybind or "H"] then
		task.spawn(function()
			local cooldownLen = (_G.ClickAP_Cooldowns and _G.ClickAP_Cooldowns["ragdoll"]) or 30
			local lastUse = _G.ClickAP_LastUse and _G.ClickAP_LastUse["ragdoll"]
			if lastUse and (tick() - lastUse) < cooldownLen then return end
			task.spawn(function() runAdminOnSelf("ragdoll") end)
			if _G.ClickAP_LastUse then _G.ClickAP_LastUse["ragdoll"] = tick() end
		end)
	end
	if Enum.KeyCode[_G.AutoTurretKeybind or "C"] and input.KeyCode == Enum.KeyCode[_G.AutoTurretKeybind or "C"] then toggleAutoTurret() end
	if Enum.KeyCode[_G.CarpetSpeedKeybind or "Q"] and input.KeyCode == Enum.KeyCode[_G.CarpetSpeedKeybind or "Q"] then toggleCarpetSpeed() end
	if Enum.KeyCode[_G.RJKeybind or "R"] and input.KeyCode == Enum.KeyCode[_G.RJKeybind or "R"] then
		task.spawn(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer) end)
	end
	if Enum.KeyCode[_G.CloneKeybind or "B"] and input.KeyCode == Enum.KeyCode[_G.CloneKeybind or "B"] then
		task.spawn(autoClone)
	end
	if Enum.KeyCode[_G.KickKeybind or "Z"] and input.KeyCode == Enum.KeyCode[_G.KickKeybind or "Z"] then
		_G.YouStoleFlag = true
		task.delay(2.5, function() _G.YouStoleFlag = false end)
		pcall(function() game:Shutdown() end)
	end
	if Enum.KeyCode[_G.InstantResetKeybind or "X"] and input.KeyCode == Enum.KeyCode[_G.InstantResetKeybind or "X"] then
		task.spawn(function() if _G._executeReset then pcall(_G._executeReset) end end)
	end
end)

-- ═══════════════════════════════════════
-- BETTER CMD NOTIFICATIONS
-- ═══════════════════════════════════════
local betterCmdEnabled = false; local cmdWatcherConns = {}; local hiddenCmdLabels = {}
local NOTIF_DURATION = 3; local RED_NAME = Color3.fromRGB(255, 70, 70)
local GREEN_NAME = Color3.fromRGB(85, 255, 85); local NOTIF_WHITE = Color3.fromRGB(255, 255, 255)

local function isCmdText(label)
	if not (label:IsA("TextLabel") or label:IsA("TextButton")) then return false end; local txt = label.Text
	if not txt or #txt < 8 then return false end
	if txt:find(" ran ") and (txt:find(" on you") or txt:find(" on ")) then return true end
	if txt:find("You executed") and txt:find(" on ") then return true end
	if txt:find("Successfully executed") and txt:find(" on ") then return true end
	return false
end
local function parseCmdText(txt)
	local cleaned = txt:gsub("on you[!%.,].*$", "on you"):gsub("on you%s*$", "on you")
	local attacker, cmd = cleaned:match('^(.+) ran "(.+)" on you')
	if attacker and cmd then return "incoming", attacker, cmd end
	attacker, cmd = cleaned:match("^(.+) ran '(.+)' on you")
	if attacker and cmd then return "incoming", attacker, cmd end
	attacker, cmd = cleaned:match("^(.+) ran (.+) on you")
	if attacker and cmd then return "incoming", attacker:gsub("%s+$", ""), cmd:gsub("%s+$", "") end
	local cmd2, target = txt:match('You ran "(.+)" on (.+)')
	if cmd2 and target then return "outgoing", target:gsub("[!%.%s]+$", ""), cmd2 end
	cmd2, target = txt:match("You ran '(.+)' on (.+)")
	if cmd2 and target then return "outgoing", target:gsub("[!%.%s]+$", ""), cmd2 end
	cmd2, target = txt:match("You ran (.+) on (.+)")
	if cmd2 and target then return "outgoing", target:gsub("[!%.%s]+$", ""), cmd2:gsub("%s+$", "") end
	cmd2, target = txt:match('You executed "(.+)" on (.+)')
	if cmd2 and target then return "outgoing", target:gsub("[!%.%s]+$", ""), cmd2 end
	cmd2, target = txt:match("You executed '(.+)' on (.+)")
	if cmd2 and target then return "outgoing", target:gsub("[!%.%s]+$", ""), cmd2 end
	cmd2, target = txt:match("You executed (.+) on (.+)")
	if cmd2 and target then return "outgoing", target:gsub("[!%.%s]+$", ""), cmd2:gsub("%s+$", "") end
	cmd2, target = txt:match('Successfully executed "(.+)" on (.+)')
	if cmd2 and target then return "outgoing", target:gsub("[!%.%s]+$", ""), cmd2 end
	cmd2, target = txt:match("Successfully executed '(.+)' on (.+)")
	if cmd2 and target then return "outgoing", target:gsub("[!%.%s]+$", ""), cmd2 end
	cmd2, target = txt:match("Successfully executed (.+) on (.+)")
	if cmd2 and target then return "outgoing", target:gsub("[!%.%s]+$", ""), cmd2:gsub("%s+$", "") end
	return nil, nil, nil
end

local activeNotifs = {}
local function repositionNotifs()
	local clickAPFrame = nil
	pcall(function() for _, sg in pairs(CoreGui:GetChildren()) do if sg:IsA("ScreenGui") then for _, child in pairs(sg:GetChildren()) do if child:IsA("Frame") and child.AbsolutePosition.X < 20 and child.AbsolutePosition.Y >= 520 and child.AbsolutePosition.Y <= 680 then clickAPFrame = child end end end end end)
	if not clickAPFrame then pcall(function() local hui = gethui and gethui(); if hui then for _, sg in pairs(hui:GetChildren()) do if sg:IsA("ScreenGui") then for _, child in pairs(sg:GetChildren()) do if child:IsA("Frame") and child.AbsolutePosition.X < 20 and child.AbsolutePosition.Y >= 520 and child.AbsolutePosition.Y <= 680 then clickAPFrame = child end end end end end end) end
	local guiInset = GuiService:GetGuiInset(); local insetY = guiInset and guiInset.Y or 36
	if clickAPFrame then
		local baseX = 8; local baseY = clickAPFrame.AbsolutePosition.Y + clickAPFrame.AbsoluteSize.Y + 4 - insetY
		for i, nf in ipairs(activeNotifs) do if nf and nf.Parent then nf.Position = UDim2.new(0, baseX, 0, baseY + (i - 1) * 28) end end
	else
		local baseY = 545 + 200 + 4 - insetY
		for i, nf in ipairs(activeNotifs) do if nf and nf.Parent then nf.Position = UDim2.new(0, 8, 0, baseY + (i - 1) * 28) end end
	end
end

local function showCmdNotification(direction, username, command)
	local notifFrame = Instance.new("Frame"); notifFrame.BackgroundColor3 = BG_COLOR; notifFrame.BackgroundTransparency = 0.15
	notifFrame.BorderSizePixel = 0; notifFrame.Size = UDim2.new(0, 0, 0, 24); notifFrame.AutomaticSize = Enum.AutomaticSize.X; notifFrame.Parent = ScreenGui
	Instance.new("UICorner", notifFrame).CornerRadius = UDim.new(0, 6)
	local pad = Instance.new("UIPadding", notifFrame); pad.PaddingLeft = UDim.new(0, 8); pad.PaddingRight = UDim.new(0, 8)
	local layout = Instance.new("UIListLayout", notifFrame); layout.FillDirection = Enum.FillDirection.Horizontal; layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.VerticalAlignment = Enum.VerticalAlignment.Center; layout.Padding = UDim.new(0, 0)
	if direction == "incoming" then
		local a = Instance.new("TextLabel", notifFrame); a.Size = UDim2.new(0,0,0,20); a.AutomaticSize = Enum.AutomaticSize.X; a.BackgroundTransparency = 1; a.LayoutOrder = 1; a.Text = "@"; a.TextColor3 = RED_NAME; a.Font = Enum.Font.GothamBold; a.TextSize = 11
		local n = Instance.new("TextLabel", notifFrame); n.Size = UDim2.new(0,0,0,20); n.AutomaticSize = Enum.AutomaticSize.X; n.BackgroundTransparency = 1; n.LayoutOrder = 2; n.Text = username; n.TextColor3 = RED_NAME; n.Font = Enum.Font.GothamBold; n.TextSize = 11
		local r = Instance.new("TextLabel", notifFrame); r.Size = UDim2.new(0,0,0,20); r.AutomaticSize = Enum.AutomaticSize.X; r.BackgroundTransparency = 1; r.LayoutOrder = 3; r.Text = " ran " .. command .. " on you"; r.TextColor3 = NOTIF_WHITE; r.Font = Enum.Font.GothamBold; r.TextSize = 11
	else
		local y = Instance.new("TextLabel", notifFrame); y.Size = UDim2.new(0,0,0,20); y.AutomaticSize = Enum.AutomaticSize.X; y.BackgroundTransparency = 1; y.LayoutOrder = 1; y.Text = "@You"; y.TextColor3 = GREEN_NAME; y.Font = Enum.Font.GothamBold; y.TextSize = 11
		local m = Instance.new("TextLabel", notifFrame); m.Size = UDim2.new(0,0,0,20); m.AutomaticSize = Enum.AutomaticSize.X; m.BackgroundTransparency = 1; m.LayoutOrder = 2; m.Text = " ran " .. command .. " on "; m.TextColor3 = NOTIF_WHITE; m.Font = Enum.Font.GothamBold; m.TextSize = 11
		local a = Instance.new("TextLabel", notifFrame); a.Size = UDim2.new(0,0,0,20); a.AutomaticSize = Enum.AutomaticSize.X; a.BackgroundTransparency = 1; a.LayoutOrder = 3; a.Text = "@"; a.TextColor3 = RED_NAME; a.Font = Enum.Font.GothamBold; a.TextSize = 11
		local n = Instance.new("TextLabel", notifFrame); n.Size = UDim2.new(0,0,0,20); n.AutomaticSize = Enum.AutomaticSize.X; n.BackgroundTransparency = 1; n.LayoutOrder = 4; n.Text = username; n.TextColor3 = RED_NAME; n.Font = Enum.Font.GothamBold; n.TextSize = 11
	end
	table.insert(activeNotifs, notifFrame); repositionNotifs()
	task.delay(NOTIF_DURATION, function()
		if notifFrame and notifFrame.Parent then
			TweenService:Create(notifFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
			for _, child in pairs(notifFrame:GetDescendants()) do if child:IsA("TextLabel") then TweenService:Create(child, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1}):Play() end end
			task.delay(0.6, function() local idx = table.find(activeNotifs, notifFrame); if idx then table.remove(activeNotifs, idx) end; notifFrame:Destroy(); repositionNotifs() end)
		end
	end)
end

	local _outgoingLastFired = {}
	_G.ShowOutgoingCmd = function(targetName, command)
		if not betterCmdEnabled then return end
		local key = targetName .. "|" .. command
		local now = tick()
		if _outgoingLastFired[key] and (now - _outgoingLastFired[key]) < 3 then return end
		_outgoingLastFired[key] = now
		showCmdNotification("outgoing", targetName, command)
	end

	local labelLastFired = {}; local REFIRE_COOLDOWN = 1.5
local function handleCmdLabel(label)
	if not betterCmdEnabled then return end; if not isCmdText(label) then return end
	local now = tick(); local key = tostring(label) .. "|" .. label.Text
	local lastFired = labelLastFired[key]; if lastFired and (now - lastFired) < REFIRE_COOLDOWN then return end; labelLastFired[key] = now
	task.delay(REFIRE_COOLDOWN + 1, function() labelLastFired[key] = nil end)
	local direction, username, command = parseCmdText(label.Text)
	if direction and username and command then
		local cleanUser = username:gsub("<[^>]+>", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("^%s+", ""):gsub("%s+$", "")
		local cleanCmd  = command:gsub("<[^>]+>", ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("^%s+", ""):gsub("%s+$", "")
		if direction == "outgoing" then
			if not hiddenCmdLabels[label] then hiddenCmdLabels[label] = label.Visible end
			label.Visible = false
		else
			if not hiddenCmdLabels[label] then hiddenCmdLabels[label] = label.Visible end
			label.Visible = false
			showCmdNotification(direction, cleanUser, cleanCmd)
		end
	end
end

local function startCmdWatcher()
	for _, conn in pairs(cmdWatcherConns) do pcall(function() conn:Disconnect() end) end; cmdWatcherConns = {}; hiddenCmdLabels = {}; labelLastFired = {}
	local function checkYouStole(desc)
		if not (desc:IsA("TextLabel") or desc:IsA("TextButton") or desc:IsA("TextBox")) then return end
		local txt = desc.Text
		if type(txt) == "string" and txt:lower():find("you stole", 1, true) then
			_G.YouStoleFlag = true
			task.delay(2.5, function() _G.YouStoleFlag = false end)
		end
	end
	local function watchLabel(desc)
		if not (desc:IsA("TextLabel") or desc:IsA("TextButton")) then return end
		checkYouStole(desc)
		task.defer(function() handleCmdLabel(desc) end)
		task.delay(0.15, function() if desc and desc.Parent then handleCmdLabel(desc) end end)
		table.insert(cmdWatcherConns, desc:GetPropertyChangedSignal("Text"):Connect(function()
			if not betterCmdEnabled then return end
			checkYouStole(desc)
			task.defer(function() handleCmdLabel(desc) end)
		end))
		table.insert(cmdWatcherConns, desc:GetPropertyChangedSignal("Visible"):Connect(function() if not betterCmdEnabled then return end; if desc.Visible then task.defer(function() handleCmdLabel(desc) end) end end))
	end
	for _, gui in pairs(playerGui:GetChildren()) do if gui:IsA("ScreenGui") and gui.Name ~= "SettingsPanel" then for _, desc in pairs(gui:GetDescendants()) do watchLabel(desc) end end end
	table.insert(cmdWatcherConns, playerGui.DescendantAdded:Connect(function(desc) if not betterCmdEnabled then return end; watchLabel(desc) end))
	pcall(function()
		local cg = game:GetService("CoreGui")
		for _, gui in pairs(cg:GetChildren()) do if gui:IsA("ScreenGui") then for _, desc in pairs(gui:GetDescendants()) do watchLabel(desc) end end end
		table.insert(cmdWatcherConns, cg.DescendantAdded:Connect(function(desc) if not betterCmdEnabled then return end; watchLabel(desc) end))
	end)
end
local function stopCmdWatcher()
	for _, conn in pairs(cmdWatcherConns) do pcall(function() conn:Disconnect() end) end; cmdWatcherConns = {}
	for label, vis in pairs(hiddenCmdLabels) do pcall(function() label.Visible = vis end) end; hiddenCmdLabels = {}; labelLastFired = {}
	for _, nf in pairs(activeNotifs) do pcall(function() nf:Destroy() end) end; activeNotifs = {}
end

-- ═══════════════════════════════════════
-- INITIAL STATE
-- ═══════════════════════════════════════

enableAutoKick()
setToggleBtnState(AutoKickBtn, autoKickEnabled, "Auto Kick ON", "Auto Kick OFF")
betterCmdEnabled = true
task.defer(startCmdWatcher)
    end)
end)

-- ═══ Player ESP ═══
task.spawn(function()
    pcall(function()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local MAX_ESP_DISTANCE = 2000
local SKELETON_THICKNESS = 1
local BOX_THICKNESS = 1
local HEALTH_BAR_WIDTH = 2
local HEALTH_BAR_OFFSET = 4

local COLOR_DEFAULT = Color3.fromRGB(255, 255, 255)
local COLOR_CLOSEST = Color3.fromRGB(93, 63, 211)  -- indigo, same font/size as normal
local COLOR_HEALTH_HIGH = Color3.fromRGB(0, 255, 0)
local COLOR_HEALTH_MID = Color3.fromRGB(255, 255, 0)
local COLOR_HEALTH_LOW = Color3.fromRGB(255, 0, 0)
local COLOR_HEALTH_BG = Color3.fromRGB(40, 40, 40)
local COLOR_OWNER = Color3.fromRGB(255, 50, 50)

local ESPObjects = {}
local closestPlayerUserId = nil
local currentBaseOwnerUserId = nil

local function createDrawing(drawingType, properties)
    local drawing = Drawing.new(drawingType)
    for property, value in pairs(properties) do
        pcall(function() drawing[property] = value end)
    end
    return drawing
end

local function worldToScreen(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    return Vector2.new(screenPos.X, screenPos.Y), onScreen, screenPos.Z
end

local function getCharacterComponents(character)
    if not character then return nil end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    local head = character:FindFirstChild("Head")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoidRootPart or not head or not humanoid then return nil end
    return { Root = humanoidRootPart, Head = head, Humanoid = humanoid }
end

local function getEquippedTool(character)
    if not character then return nil end
    for _, item in ipairs(character:GetChildren()) do
        if item:IsA("Tool") then return item.Name end
    end
    return nil
end

local function getESPDistance(position)
    if not LocalPlayer.Character then return 0 end
    local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return 0 end
    return math.floor((position - root.Position).Magnitude)
end

local function getSkeletonLimbs(character)
    if not character then return nil end
    local limbs = {}
    limbs.Head = character:FindFirstChild("Head")
    limbs.UpperTorso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
    limbs.LowerTorso = character:FindFirstChild("LowerTorso")
    limbs.HumanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    limbs.LeftUpperArm = character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")
    limbs.LeftLowerArm = character:FindFirstChild("LeftLowerArm")
    limbs.LeftHand = character:FindFirstChild("LeftHand")
    limbs.RightUpperArm = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")
    limbs.RightLowerArm = character:FindFirstChild("RightLowerArm")
    limbs.RightHand = character:FindFirstChild("RightHand")
    limbs.LeftUpperLeg = character:FindFirstChild("LeftUpperLeg") or character:FindFirstChild("Left Leg")
    limbs.LeftLowerLeg = character:FindFirstChild("LeftLowerLeg")
    limbs.LeftFoot = character:FindFirstChild("LeftFoot")
    limbs.RightUpperLeg = character:FindFirstChild("RightUpperLeg") or character:FindFirstChild("Right Leg")
    limbs.RightLowerLeg = character:FindFirstChild("RightLowerLeg")
    limbs.RightFoot = character:FindFirstChild("RightFoot")
    return limbs
end

local function getClosestPlot()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end

    local closestPlot = nil
    local closestDistance = math.huge

    for _, plot in pairs(plots:GetChildren()) do
        if plot:IsA("Model") then
            local ok, pos = pcall(function() return plot:GetPivot().Position end)
            if ok then
                local distance = (hrp.Position - pos).Magnitude
                if distance < closestDistance then
                    closestDistance = distance
                    closestPlot = plot
                end
            end
        end
    end

    if closestDistance < 50 then return closestPlot end
    return nil
end

local function getCurrentBaseOwner()
    local targetPlot = getClosestPlot()
    if not targetPlot then return nil end
    local sign = targetPlot:FindFirstChild("PlotSign")
    if not sign then return nil end
    local label = sign:FindFirstChildWhichIsA("TextLabel", true)
    if not label or label.Text == "" then return nil end
    local ownerText = label.Text:gsub("'s Base", ""):gsub("'s Plot", "")
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name == ownerText or player.DisplayName == ownerText then
            return player
        end
    end
    return nil
end

local function getHealthColor(healthPercent)
    if healthPercent > 0.5 then
        local t = (healthPercent - 0.5) / 0.5
        return Color3.new(
            COLOR_HEALTH_MID.R + (COLOR_HEALTH_HIGH.R - COLOR_HEALTH_MID.R) * t,
            COLOR_HEALTH_MID.G + (COLOR_HEALTH_HIGH.G - COLOR_HEALTH_MID.G) * t,
            COLOR_HEALTH_MID.B + (COLOR_HEALTH_HIGH.B - COLOR_HEALTH_MID.B) * t
        )
    else
        local t = healthPercent / 0.5
        return Color3.new(
            COLOR_HEALTH_LOW.R + (COLOR_HEALTH_MID.R - COLOR_HEALTH_LOW.R) * t,
            COLOR_HEALTH_LOW.G + (COLOR_HEALTH_MID.G - COLOR_HEALTH_LOW.G) * t,
            COLOR_HEALTH_LOW.B + (COLOR_HEALTH_MID.B - COLOR_HEALTH_LOW.B) * t
        )
    end
end

local function calculateBoxFromCharacter(character, components)
    if not character or not components then return nil end

    local head = components.Head
    local root = components.Root

    local topWorld = head.Position + Vector3.new(0, head.Size.Y / 2 + 0.3, 0)
    local bottomWorld = root.Position - Vector3.new(0, 3, 0)

    local topScreen, topOn = worldToScreen(topWorld)
    local bottomScreen, bottomOn = worldToScreen(bottomWorld)

    if not topOn and not bottomOn then return nil end

    local height = math.abs(bottomScreen.Y - topScreen.Y)
    local width = height * 0.55

    local centerX = (topScreen.X + bottomScreen.X) / 2
    local centerY = (topScreen.Y + bottomScreen.Y) / 2

    return {
        topLeft = Vector2.new(centerX - width / 2, centerY - height / 2),
        topRight = Vector2.new(centerX + width / 2, centerY - height / 2),
        bottomLeft = Vector2.new(centerX - width / 2, centerY + height / 2),
        bottomRight = Vector2.new(centerX + width / 2, centerY + height / 2),
        width = width,
        height = height,
        centerX = centerX
    }
end

local function createPlayerESP(player)
    local esp = {
        Player = player,
        Character = nil,
        Components = nil,
        Limbs = nil,
        Box = {},
        Skeleton = {},

        OwnerText = createDrawing("Text", {
            Size = 14,
            Color = COLOR_OWNER,
            Center = true,
            Outline = true,
            OutlineColor = Color3.fromRGB(0, 0, 0),
            Font = 2,
            Visible = false
        }),

        NameText = createDrawing("Text", {
            Size = 13,
            Color = COLOR_DEFAULT,
            Center = true,
            Outline = true,
            OutlineColor = Color3.fromRGB(0, 0, 0),
            Font = 2,
            Visible = false
        }),

        ToolText = createDrawing("Text", {
            Size = 12,
            Color = COLOR_DEFAULT,
            Center = true,
            Outline = true,
            OutlineColor = Color3.fromRGB(0, 0, 0),
            Font = 2,
            Visible = false
        }),

        DistanceText = createDrawing("Text", {
            Size = 12,
            Color = COLOR_DEFAULT,
            Center = true,
            Outline = true,
            OutlineColor = Color3.fromRGB(0, 0, 0),
            Font = 2,
            Visible = false
        }),

        HealthBarBG = createDrawing("Line", {
            Thickness = HEALTH_BAR_WIDTH + 2,
            Color = COLOR_HEALTH_BG,
            Visible = false
        }),

        HealthBarFill = createDrawing("Line", {
            Thickness = HEALTH_BAR_WIDTH,
            Color = COLOR_HEALTH_HIGH,
            Visible = false
        })
    }

    for i = 1, 4 do
        esp.Box[i] = createDrawing("Line", {
            Thickness = BOX_THICKNESS,
            Color = COLOR_DEFAULT,
            Visible = false
        })
    end

    for i = 1, 15 do
        esp.Skeleton[i] = createDrawing("Line", {
            Thickness = SKELETON_THICKNESS,
            Color = COLOR_DEFAULT,
            Visible = false
        })
    end

    return esp
end

local function hideAll(esp)
    for _, line in ipairs(esp.Box) do line.Visible = false end
    for _, line in ipairs(esp.Skeleton) do line.Visible = false end
    esp.NameText.Visible = false
    esp.OwnerText.Visible = false
    esp.ToolText.Visible = false
    esp.DistanceText.Visible = false
    esp.HealthBarBG.Visible = false
    esp.HealthBarFill.Visible = false
end

local function updatePlayerCharacter(esp, character)
    if not character then return end
    esp.Character = character
    esp.Components = getCharacterComponents(character)
    esp.Limbs = getSkeletonLimbs(character)
end

local function removePlayerESP(esp)
    if not esp then return end
    for _, line in ipairs(esp.Box) do pcall(function() line:Remove() end) end
    for _, line in ipairs(esp.Skeleton) do pcall(function() line:Remove() end) end
    pcall(function() esp.NameText:Remove() end)
    pcall(function() esp.OwnerText:Remove() end)
    pcall(function() esp.ToolText:Remove() end)
    pcall(function() esp.DistanceText:Remove() end)
    pcall(function() esp.HealthBarBG:Remove() end)
    pcall(function() esp.HealthBarFill:Remove() end)
end

local function updatePlayerESP(esp)
    if not esp.Character or not esp.Components then
        hideAll(esp)
        return
    end

    local components = esp.Components
    if not components.Root or not components.Root.Parent or not components.Humanoid or not components.Head then
        esp.Components = nil
        hideAll(esp)
        return
    end

    local distance = getESPDistance(components.Root.Position)
    if distance > MAX_ESP_DISTANCE then
        hideAll(esp)
        return
    end

    local _, rootOnScreen = worldToScreen(components.Root.Position)
    if not rootOnScreen then
        hideAll(esp)
        return
    end

    local isClosest = (closestPlayerUserId == esp.Player.UserId)
    local espColor = isClosest and COLOR_CLOSEST or COLOR_DEFAULT

    local box = calculateBoxFromCharacter(esp.Character, components)
    if not box then
        hideAll(esp)
        return
    end

    pcall(function()
        esp.Box[1].From = box.topLeft; esp.Box[1].To = box.topRight
        esp.Box[1].Color = espColor; esp.Box[1].Visible = true

        esp.Box[2].From = box.topRight; esp.Box[2].To = box.bottomRight
        esp.Box[2].Color = espColor; esp.Box[2].Visible = true

        esp.Box[3].From = box.bottomRight; esp.Box[3].To = box.bottomLeft
        esp.Box[3].Color = espColor; esp.Box[3].Visible = true

        esp.Box[4].From = box.bottomLeft; esp.Box[4].To = box.topLeft
        esp.Box[4].Color = espColor; esp.Box[4].Visible = true
    end)

    pcall(function()
        local healthPercent = math.clamp(components.Humanoid.Health / components.Humanoid.MaxHealth, 0, 1)
        local barX = box.topLeft.X - HEALTH_BAR_OFFSET
        local barTop = box.topLeft.Y
        local barBottom = box.bottomLeft.Y
        local barHeight = barBottom - barTop
        local fillBottom = barBottom
        local fillTop = barBottom - (barHeight * healthPercent)

        esp.HealthBarBG.From = Vector2.new(barX, barTop)
        esp.HealthBarBG.To = Vector2.new(barX, barBottom)
        esp.HealthBarBG.Visible = true

        esp.HealthBarFill.From = Vector2.new(barX, fillTop)
        esp.HealthBarFill.To = Vector2.new(barX, fillBottom)
        esp.HealthBarFill.Color = getHealthColor(healthPercent)
        esp.HealthBarFill.Visible = healthPercent > 0
    end)

    pcall(function()
        if not esp.Limbs then return end
        local limbs = esp.Limbs
        local skeletonIndex = 1

        local function drawLimb(limbA, limbB)
            if limbA and limbB and skeletonIndex <= #esp.Skeleton then
                local posA, onA = worldToScreen(limbA.Position)
                local posB, onB = worldToScreen(limbB.Position)
                if onA and onB then
                    esp.Skeleton[skeletonIndex].From = posA
                    esp.Skeleton[skeletonIndex].To = posB
                    esp.Skeleton[skeletonIndex].Color = espColor
                    esp.Skeleton[skeletonIndex].Visible = true
                    skeletonIndex = skeletonIndex + 1
                end
            end
        end

        drawLimb(limbs.Head, limbs.UpperTorso)

        if limbs.LowerTorso then
            drawLimb(limbs.UpperTorso, limbs.LowerTorso)
        end

        drawLimb(limbs.UpperTorso, limbs.LeftUpperArm)
        if limbs.LeftLowerArm then
            drawLimb(limbs.LeftUpperArm, limbs.LeftLowerArm)
            drawLimb(limbs.LeftLowerArm, limbs.LeftHand)
        end

        drawLimb(limbs.UpperTorso, limbs.RightUpperArm)
        if limbs.RightLowerArm then
            drawLimb(limbs.RightUpperArm, limbs.RightLowerArm)
            drawLimb(limbs.RightLowerArm, limbs.RightHand)
        end

        local hipPart = limbs.LowerTorso or limbs.UpperTorso
        drawLimb(hipPart, limbs.LeftUpperLeg)
        if limbs.LeftLowerLeg then
            drawLimb(limbs.LeftUpperLeg, limbs.LeftLowerLeg)
            drawLimb(limbs.LeftLowerLeg, limbs.LeftFoot)
        end

        drawLimb(hipPart, limbs.RightUpperLeg)
        if limbs.RightLowerLeg then
            drawLimb(limbs.RightUpperLeg, limbs.RightLowerLeg)
            drawLimb(limbs.RightLowerLeg, limbs.RightFoot)
        end

        for i = skeletonIndex, #esp.Skeleton do
            esp.Skeleton[i].Visible = false
        end
    end)

    local isOwner = (currentBaseOwnerUserId == esp.Player.UserId)
    local nameY = box.topLeft.Y - 16

    pcall(function()
        if isOwner then
            esp.OwnerText.Position = Vector2.new(box.centerX, nameY - 14)
            esp.OwnerText.Text = "Owner"
            esp.OwnerText.Visible = true
        else
            esp.OwnerText.Visible = false
        end
    end)

    pcall(function()
        local rawName = esp.Player.DisplayName or esp.Player.Name or ""
        local safeName = rawName:gsub("[<>]", "")
        esp.NameText.Position = Vector2.new(box.centerX, nameY)
        esp.NameText.Text = safeName
        esp.NameText.Color = espColor  -- indigo for closest, white for others
        esp.NameText.Size = 13
        esp.NameText.Visible = true
    end)

    pcall(function()
        local tool = getEquippedTool(esp.Character)
        if tool then
            esp.ToolText.Position = Vector2.new(box.centerX, box.bottomLeft.Y + 3)
            esp.ToolText.Text = "[" .. tool .. "]"
            esp.ToolText.Color = COLOR_DEFAULT  -- same for all players
            esp.ToolText.Visible = true
        else
            esp.ToolText.Visible = false
        end
    end)

    pcall(function()
        local yOffset = 3
        if getEquippedTool(esp.Character) then yOffset = 14 end
        esp.DistanceText.Position = Vector2.new(box.centerX, box.bottomLeft.Y + yOffset)
        esp.DistanceText.Text = string.format("%d studs", math.floor(distance))
        esp.DistanceText.Color = COLOR_DEFAULT  -- same for all players
        esp.DistanceText.Visible = true
    end)
end

local function cleanupPlayerESP(player)
    local esp = ESPObjects[player.UserId]
    if esp then
        removePlayerESP(esp)
        ESPObjects[player.UserId] = nil
    end
end

local function updateClosestPlayer()
    if not LocalPlayer.Character then
        closestPlayerUserId = nil
        return
    end
    local myRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then
        closestPlayerUserId = nil
        return
    end

    local closestDistance = math.huge
    local closestUserId = nil

    for userId, esp in pairs(ESPObjects) do
        if esp.Components and esp.Components.Root and esp.Components.Root.Parent then
            local d = (myRoot.Position - esp.Components.Root.Position).Magnitude
            if d < closestDistance then
                closestDistance = d
                closestUserId = userId
            end
        end
    end

    closestPlayerUserId = closestUserId
end

local function updateBaseOwner()
    local owner = getCurrentBaseOwner()
    if owner then
        currentBaseOwnerUserId = owner.UserId
    else
        currentBaseOwnerUserId = nil
    end
end

local function setupPlayerESP(player)
    if not player or player == LocalPlayer then return end
    if ESPObjects[player.UserId] then return end

    local esp = createPlayerESP(player)
    ESPObjects[player.UserId] = esp

    local function onCharacter(character)
        task.wait(0.1)
        updatePlayerCharacter(esp, character)

        pcall(function()
            local hum = character:FindFirstChildOfClass("Humanoid")
            if hum then
                -- DisplayDistanceType removed (detectable)
            end
        end)

        character.AncestryChanged:Connect(function(_, parent)
            if not parent then
                esp.Components = nil
                esp.Limbs = nil
                hideAll(esp)
            end
        end)
    end

    if player.Character then
        onCharacter(player.Character)
    end

    player.CharacterAdded:Connect(onCharacter)
end

for _, player in ipairs(Players:GetPlayers()) do
    setupPlayerESP(player)
end

Players.PlayerAdded:Connect(function(player)
    task.wait(0.05)
    setupPlayerESP(player)
    updateBaseOwner()
end)

Players.PlayerRemoving:Connect(cleanupPlayerESP)

task.spawn(function()
    while true do
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local esp = ESPObjects[player.UserId]
                if not esp then
                    setupPlayerESP(player)
                elseif esp and not esp.Components and player.Character then
                    cleanupPlayerESP(player)
                    setupPlayerESP(player)
                end
                pcall(function()
                    local char = player.Character
                    if char then
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        -- DisplayDistanceType removed (detectable)
                    end
                end)
            end
        end
        task.wait(1.5)
    end
end)

local closestUpdateCount = 0
local ownerUpdateCount = 0

RunService.RenderStepped:Connect(function()
    closestUpdateCount = closestUpdateCount + 1
    ownerUpdateCount = ownerUpdateCount + 1

    if closestUpdateCount >= 30 then
        closestUpdateCount = 0
        updateClosestPlayer()
    end

    if ownerUpdateCount >= 60 then
        ownerUpdateCount = 0
        updateBaseOwner()
    end

    if _G._playerEspEnabled then
        for _, esp in pairs(ESPObjects) do
            pcall(updatePlayerESP, esp)
        end
    else
        for _, esp in pairs(ESPObjects) do
            pcall(hideAll, esp)
        end
    end
end)

    end)
end)

-- ═══ Stealing Players GUI ═══
task.spawn(function()
    pcall(function()
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then repeat LocalPlayer = Players.LocalPlayer; task.wait(0.1) until LocalPlayer end

local playerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
if not playerGui then return end

local Camera = Workspace.CurrentCamera

task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end
	task.wait(1)
	-- Synchronizer patch: handled by initial patch
end)

local COMMANDS = {"ragdoll", "balloon", "jail", "rocket"}
local COOLDOWNS = {["ragdoll"] = 31, ["balloon"] = 31, ["jail"] = 31, ["rocket"] = 121}
local DISPLAY = {["ragdoll"] = "Ragdoll", ["balloon"] = "Balloon", ["jail"] = "Jail", ["rocket"] = "Rocket"}
local LastUse = {}

local adminPath = nil

task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end
	task.wait(1)
	local apf = playerGui:FindFirstChild("AdminPanel") or playerGui:WaitForChild("AdminPanel", 10)
	if apf then adminPath = apf:FindFirstChild("AdminPanel") or apf:WaitForChild("AdminPanel", 5) end
end)

local function adminpanel(player, command)
	if not adminPath then return end
	local p = adminPath:FindFirstChild("Profiles")
	if not p then return end
	local s = p:FindFirstChild("ScrollingFrame")
	if not s then return end
	local pu = s:FindFirstChild(player.Name)
	if not pu then return end
	firesignal(pu.Activated)
	task.wait(0.1)
	local c = adminPath:FindFirstChild("Content")
	if not c then return end
	local cs = c:FindFirstChild("ScrollingFrame")
	if not cs then return end
	local cu = cs:FindFirstChild(command)
	if not cu then return end
	firesignal(cu.Activated)
end

local function isOnCooldown(cmd)
	return LastUse[cmd] and (tick() - LastUse[cmd]) < (COOLDOWNS[cmd] or 0)
end

local function executeCommand(target, cmd)
	if isOnCooldown(cmd) then return end
	if _G._fireAdmin then _G._fireAdmin(target, cmd) end
	LastUse[cmd] = tick()
	if _G.ClickAP_LastUse then _G.ClickAP_LastUse[cmd] = tick() end
	pcall(function()
		if _G.ShowOutgoingCmd and target then
			_G.ShowOutgoingCmd(target.Name, cmd)
		end
	end)
end

local function getAvailable()
	local a = {}
	for _, cmd in ipairs(COMMANDS) do
		if not isOnCooldown(cmd) then table.insert(a, cmd) end
	end
	return a
end

local WHITE        = Color3.fromRGB(255, 255, 255)
local BG_COLOR     = Color3.fromRGB(8, 10, 18)
local BOX_COLOR    = Color3.fromRGB(10, 12, 20)
local BOX_RUBY = Color3.fromRGB(50,12,15)
local BOX_YELLOW = Color3.fromRGB(50,45,12)
local BOX_INDIGO = Color3.fromRGB(25,18,55)
local BOX_SAPPHIRE = Color3.fromRGB(12,30,55)
local RUBY_OUTLINE = Color3.fromRGB(180,40,50)
local SAPPHIRE_OUTLINE = Color3.fromRGB(10,60,150)
local YELLOW_OUTLINE = Color3.fromRGB(200,180,50)
local INDIGO_OUTLINE_S = Color3.fromRGB(93,63,211)
local BORDER_BLACK = Color3.fromRGB(0, 0, 0)
local GREY_TEXT    = Color3.fromRGB(140, 140, 140)
local GREEN_TEXT   = Color3.fromRGB(85, 255, 85)
local HOVER_WHITE  = Color3.fromRGB(255, 255, 255)
local SEPARATOR_W  = Color3.fromRGB(255, 255, 255)

local GUI_W   = 275
local PAD     = 5
local TITLE_H = 24
local SEP_H   = 1
local BOX_H   = 36
local BOX_GAP = 4
local HEADER_H = TITLE_H + SEP_H + PAD
local EMPTY_H = 36

if playerGui:FindFirstChild("ActivityFeed") then
	playerGui.ActivityFeed:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ActivityFeed"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = playerGui
ScreenGui.Enabled = false
_G.UIHide_Stealers = ScreenGui
local STFrame = Instance.new("Frame")
STFrame.Name = "StealersFrame"
STFrame.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
STFrame.BackgroundTransparency = 0.25
STFrame.BorderSizePixel = 0
STFrame.ClipsDescendants = false
STFrame.Parent = ScreenGui

do
    local _sdSTFR={{0.957,0.725,3,0.0055},{0.217,0.412,3,0.0038},{0.577,0.273,3,0.0052},{0.322,0.267,2,0.0045},{0.182,0.924,3,0.0051},{0.211,0.623,2,0.0054},{0.41,0.394,3,0.0043},{0.862,0.723,3,0.0064},{0.677,0.148,3,0.0053},{0.488,0.079,3,0.0048},{0.39,0.529,2,0.0051},{0.208,0.723,3,0.006},{0.265,0.051,2,0.0052},{0.167,0.299,2,0.0038},{0.394,0.242,2,0.0048},{0.888,0.826,2,0.0058},{0.061,0.301,2,0.0059},{0.958,0.478,3,0.0038},{0.752,0.26,3,0.0038},{0.114,0.366,2,0.0042},{0.098,0.236,2,0.0036},{0.794,0.738,2,0.0037},{0.94,0.938,2,0.0056},{0.211,0.808,2,0.005},{0.592,0.214,3,0.0045},{0.897,0.483,3,0.0059},{0.927,0.171,2,0.0047},{0.45,0.691,2,0.0036},{0.751,0.554,2,0.0051},{0.966,0.786,2,0.0062}}
    local _sfSTFR,_soSTFR={},{}
    for i,sp in ipairs(_sdSTFR) do
        local s=Instance.new("Frame",STFrame)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.3
        s.BorderSizePixel=0;s.ZIndex=10
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfSTFR[i]=s;_soSTFR[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfSTFR) do
            if not s or not s.Parent then continue end
            _soSTFR[i]=(_soSTFR[i]-_sdSTFR[i][4]*dt)%1
            s.Position=UDim2.new(_soSTFR[i],0,_sdSTFR[i][2],0)
            s.BackgroundTransparency=0.3+math.abs(math.sin(tick()*0.8+i*0.7))*0.5
        end
    end)
end
Instance.new("UICorner", STFrame).CornerRadius = UDim.new(0, 8)
local stStroke = Instance.new("UIStroke", STFrame)
if not _G._hubPanelStrokes then _G._hubPanelStrokes = {} end
table.insert(_G._hubPanelStrokes, stStroke)
stStroke.Color = Color3.fromRGB(255, 40, 160); stStroke.Thickness = 1.5

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -PAD * 2, 0, 22)
TitleLabel.Position = UDim2.new(0, PAD, 0, math.max(0, math.floor((TITLE_H - 22) / 2)))
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Stealers"
TitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 12
TitleLabel.TextXAlignment = Enum.TextXAlignment.Center
TitleLabel.TextYAlignment = Enum.TextYAlignment.Center
TitleLabel.Parent = STFrame
local _stealersSepLine = Instance.new("Frame", STFrame)
_stealersSepLine.Size = UDim2.new(1,-20,0,1); _stealersSepLine.Position = UDim2.new(0,10,0,TITLE_H-1)
_stealersSepLine.BackgroundColor3 = Color3.fromRGB(255,255,255); _stealersSepLine.BackgroundTransparency = 0.7
_stealersSepLine.BorderSizePixel = 0; _stealersSepLine.ZIndex = 2
local _stealersTitleStroke = {ApplyStrokeMode=0}  -- dummy

do
    local _sdST2={{0.164,0.594,2,0.0076},{0.522,0.261,1,0.0101},{0.446,0.536,1,0.0078},{0.683,0.838,1,0.0109},{0.705,0.723,1,0.0099},{0.414,0.177,1,0.0074},{0.962,0.428,1,0.012},{0.33,0.499,1,0.0118},{0.14,0.758,1,0.0104},{0.501,0.109,1,0.0077},{0.384,0.369,2,0.0081},{0.795,0.527,1,0.012},{0.898,0.677,2,0.0112},{0.246,0.783,1,0.0102}}
    local _sfST2,_soST2={},{}
    for i,sp in ipairs(_sdST2) do
        local s=Instance.new("Frame",TitleLabel)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.2
        s.BorderSizePixel=0;s.ZIndex=3
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfST2[i]=s;_soST2[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfST2) do
            if not s or not s.Parent then continue end
            _soST2[i]=(_soST2[i]-_sdST2[i][4]*dt)%1
            s.Position=UDim2.new(_soST2[i],0,_sdST2[i][2],0)
            s.BackgroundTransparency=0.1+math.abs(math.sin(tick()*1.2+i))*0.7
        end
    end)
end

-- No separator line

local BoxContainer = Instance.new("Frame")
BoxContainer.Name = "BoxContainer"
BoxContainer.Size = UDim2.new(1, 0, 1, -TITLE_H)
BoxContainer.Position = UDim2.new(0, 0, 0, TITLE_H)
BoxContainer.BackgroundTransparency = 1
BoxContainer.ClipsDescendants = true
BoxContainer.Parent = STFrame

local stealingEntries = {}

-- ═══════════════════════════════════════
-- ═══════════════════════════════════════

local function findInfoFrame()
	local speedGui = playerGui:FindFirstChild("SettingsPanel")
	if speedGui then
		local info = speedGui:FindFirstChild("InfoFrame")
		if info then return info end
	end
	return nil
end

local function getBoxCount()
	local c = 0
	for _ in pairs(stealingEntries) do c = c + 1 end
	return c
end

local function positionGui()
	if _guiUserMoved["STFrame"] then return end
	local mf = _G._mainFrame
	if mf and mf.Parent then
		local guiInset = game:GetService("GuiService"):GetGuiInset()
		local insetY = guiInset and guiInset.Y or 36
		-- Use Size.Y.Offset for reliable height (AbsoluteSize may not be ready)
		local mfH = mf.Size.Y.Offset
		if mfH < 10 then mfH = mf.AbsoluteSize.Y end
		if mfH < 10 then mfH = 232 end -- fallback
		STFrame.Size = UDim2.new(0, GUI_W, 0, mfH)
		STFrame.Position = UDim2.new(0, mf.AbsolutePosition.X + mf.AbsoluteSize.X + 5, 0, mf.AbsolutePosition.Y - insetY + 58)
	else
		local vpx = Camera.ViewportSize.X
		local myX = vpx / 2 + 245 + 80 + 290 + 16
		STFrame.Size = UDim2.new(0, GUI_W, 0, EMPTY_H)
		STFrame.Position = UDim2.new(0, myX, 1, -232 - 10)
	end
end

positionGui()
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(positionGui)
makeDraggable(STFrame, "STFrame", TitleLabel)
_G._stealersFrame = STFrame
pcall(addGlowBorder, STFrame)

task.spawn(function()
	while task.wait(1) do
		positionGui()
		-- Gate visibility behind the hub toggle
		STFrame.Visible = (_G._stealingHudEnabled ~= false)
	end
end)

local function findMyBase()
	local plots = Workspace:FindFirstChild("Plots")
	if not plots then return nil end
	local n = LocalPlayer.Name:lower()
	local d = LocalPlayer.DisplayName:lower()
	for _, p in ipairs(plots:GetChildren()) do
		local ok, result = pcall(function()
			local s = p:FindFirstChild("PlotSign")
			local l = s and s:FindFirstChildWhichIsA("TextLabel", true)
			if l and (l.Text:lower():find(n) or l.Text:lower():find(d)) then return p end
			return nil
		end)
		if ok and result then return result end
	end
	return nil
end

local function getPlayerPosition(player)
	local ok, pos = pcall(function()
		return player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position
	end)
	return ok and pos or nil
end

local function isStealingFromMe(player)
	local myBase = findMyBase()
	if not myBase then return false end
	local pos = getPlayerPosition(player)
	if not pos then return false end
	local ok, basePos = pcall(function() return myBase:GetPivot().Position end)
	if not ok then return false end
	return (pos - basePos).Magnitude < 30
end

local function getBrainrotName(player)
	local ok, idx = pcall(function() return player:GetAttribute("StealingIndex") end)
	if ok and idx and idx ~= "" then return tostring(idx) end
	return "Unknown"
end

local STEALERS_SUPER = {["Strawberry Elephant"]=true,["Meowl"]=true,["Headless Horseman"]=true,["Skibidi Toilet"]=true,["Signore Caraprace"]=true,["Signore Carapace"]=true}
local STEALERS_MUT_HEX = {Lava="#FFA500",Bloodrot="#FF0000",Candy="#FF69B4",Gold="#FFD700",Diamond="#00BFFF",Radioactive="#00FF00",Galaxy="#B47BFF",Divine="#FFFAD0"}

local function formatMutForStealers(mut)
	if not mut or mut == "None" or mut == "" then return "" end
	if mut == "Rainbow" then return '<font color="#FF3030">R</font><font color="#FF8822">a</font><font color="#FFD700">i</font><font color="#22DD22">n</font><font color="#3388FF">b</font><font color="#9944FF">o</font><font color="#FF44AA">w</font> ' end
	if mut == "Cursed" then return '<font color="#FF2020">C</font><font color="#DD1010">u</font><font color="#BB0808">r</font><font color="#880000">s</font><font color="#550000">e</font><font color="#330000">d</font> ' end
	if mut == "YinYang" then return '<font color="#FFFFFF">Y</font><font color="#DDDDDD">i</font><font color="#BBBBBB">n</font><font color="#444444">Y</font><font color="#222222">a</font><font color="#111111">n</font><font color="#000000">g</font> ' end
	if mut == "Galaxy" then return '<font color="#6B1FCC">G</font><font color="#7B33DD">a</font><font color="#9955EE">l</font><font color="#BB77FF">a</font><font color="#9955EE">x</font><font color="#7B33DD">y</font> ' end
	if mut == "Lava" then return '<font color="#FF4400">L</font><font color="#FF6600">a</font><font color="#FF8800">v</font><font color="#FFAA00">a</font> ' end
	if mut == "Gold" then return '<font color="#FFD700">G</font><font color="#FFCC00">o</font><font color="#FFB800">l</font><font color="#FFA500">d</font> ' end
	if mut == "Diamond" then return '<font color="#00CCFF">D</font><font color="#22DDFF">i</font><font color="#44EEFF">a</font><font color="#66F5FF">m</font><font color="#44EEFF">o</font><font color="#22DDFF">n</font><font color="#00BBFF">d</font> ' end
	if mut == "Radioactive" then return '<font color="#00FF00">R</font><font color="#22FF22">a</font><font color="#00DD00">d</font><font color="#00BB00">i</font><font color="#00FF00">o</font><font color="#33FF33">a</font><font color="#00DD00">c</font><font color="#00BB00">t</font><font color="#00FF00">i</font><font color="#22FF22">v</font><font color="#00DD00">e</font> ' end
	if mut == "Candy" then return '<font color="#FF69B4">C</font><font color="#FF88CC">a</font><font color="#FF55AA">n</font><font color="#FF3399">d</font><font color="#FF69B4">y</font> ' end
	if mut == "Bloodrot" then return '<font color="#FF0000">B</font><font color="#DD0000">l</font><font color="#FF2222">o</font><font color="#CC0000">o</font><font color="#FF0000">d</font><font color="#BB0000">r</font><font color="#DD0000">o</font><font color="#FF1111">t</font> ' end
	if mut == "Divine" then return '<font color="#FFFACD">D</font><font color="#FFF8B0">i</font><font color="#FFF5A0">v</font><font color="#FFF8B0">i</font><font color="#FFFACD">n</font><font color="#FFFDE0">e</font> ' end
	local hex = STEALERS_MUT_HEX[mut] or "#C8C8C8"
	return '<font color="' .. hex .. '">' .. mut .. '</font> '
end

local function getBrainrotRichLabel(indexName)
	local dispName = indexName
	local mutText = ""
	local genText = ""
	pcall(function()
		local _ad = require(game.ReplicatedStorage.Datas.Animals)
		local _info = _ad and _ad[indexName]
		if _info and _info.DisplayName then dispName = _info.DisplayName end
	end)
	pcall(function()
		local plots = Workspace:FindFirstChild("Plots"); if not plots then return end
		for _, plot in ipairs(plots:GetChildren()) do
			local ch = Synchronizer:Get(plot.Name); if not ch then continue end
			local al = ch:Get("AnimalList"); if not al then continue end
			for slot, data in pairs(al) do
				if type(data) == "table" and data.Index == indexName then
					local mut = data.Mutation or "None"
					mutText = formatMutForStealers(mut)
					local gv = AnimalsShared:GetGeneration(indexName, data.Mutation, data.Traits, nil)
					genText = " <font color=\"#66FF66\">$" .. NumberUtils:ToString(gv) .. "/s</font>"
					return
				end
			end
		end
	end)
	-- Purple name for super brainrots
	local nameHex = STEALERS_SUPER[dispName] and "#5D3FD3" or "#FFFFFF"
	return mutText .. '<font color="' .. nameHex .. '">' .. dispName .. '</font>' .. genText
end

local STEAL_GUI_SUPER = {["Strawberry Elephant"]=true,["Meowl"]=true,["Headless Horseman"]=true,["Skibidi Toilet"]=true,["Signore Caraprace"]=true,["Signore Carapace"]=true}
local STEAL_LOW = 23
local STEAL_P = {["Headless Horseman"]=1,["Strawberry Elephant"]=2,["Meowl"]=3,["Signore Caraprace"]=4,["Signore Carapace"]=4,["Skibidi Toilet"]=5,["Skibidi toilet"]=5,["Dragon Gingerini"]=6,["Griffin"]=7,["Dragon Cannelloni"]=8,["Love Love Bear"]=9,["La Supreme Combinasion"]=10,["Antonio"]=11,["Ginger Gerat"]=12,["Elefanto Frigo"]=13,["Ketupat Bros"]=14,["Hydra Dragon Cannelloni"]=15,["Bunny and Eggy"]=16,["Hydra Bunny"]=17,["Dug Dug Dug"]=18,["Dug dug dug"]=18,["Fishino Clownino"]=19,["Cerberus"]=20,["La Casa Boo"]=21,["Popcuru and Fizzuru"]=22,["Reinito Sleighito"]=23,["Burguro And Fryuro"]=24,["Burguro and Fryuro"]=24,["Foxini Laternini"]=25,["Foxini Lanternini"]=25,["Boppin Bunny"]=26,["Cash or Card"]=27,["Quackini Snackin"]=28,["Fragola La La La"]=29,["Tirilikalika Tirilikalako"]=30,["La Food Combinasion"]=31,["Capitano Moby"]=32,["Los Sekolahs"]=33,["Los Amigos"]=34,["Rosey and Teddy"]=35,["Spooky and Pumpky"]=36,["Cooki and Milki"]=37,["Celestial Pegasus"]=38,["Garama and Madundung"]=39,["Sammyni Fattini"]=40,["Sammyni Fattyin"]=40,["Fortunu and Cashuru"]=41,["La Secret Combinasion"]=42,["Ketchuru and Musturu"]=43,["Tralaledon"]=44,["Tictac Sahur"]=45,["Ketupat Kepat"]=46,["Tang Tang Keletang"]=47,["Orcaledon"]=48,["La Ginger Sekolah"]=49,["Lavadorito Spinito"]=50,["La Taco Combinasion"]=51,["Los Primos"]=52,["Los Bros"]=53,["Las Sis"]=54,["Chillin Chili"]=55,["W or L"]=56,["Chipso and Queso"]=57}
local STEAL_SAPPHIRE = {["Dragon Gingerini"]=true,["Griffin"]=true,["Dragon Cannelloni"]=true,["Love Love Bear"]=true,["La Supreme Combinasion"]=true,["Antonio"]=true,["Ginger Gerat"]=true,["Elefanto Frigo"]=true,["Ketupat Bros"]=true,["Dug Dug Dug"]=true,["Dug dug dug"]=true,["Hydra Dragon Cannelloni"]=true,["Hydra Bunny"]=true}
local function getStealTier(n)
	if not n or n=="" or n=="Unknown" then return "d" end
	if STEAL_GUI_SUPER[n] then return "s" end
	if STEAL_SAPPHIRE[n] then return "m" end
	local r=STEAL_P[n]; if r then return "l" end
	return "d"
end
local function getBoxBg(t)
	if t=="s" then return BOX_INDIGO end; if t=="m" then return BOX_SAPPHIRE end; if t=="l" then return BOX_YELLOW end; return BOX_COLOR
end

local function updateOutlines()
	for _,data in pairs(stealingEntries) do
		local stroke=data.stroke; if not stroke then continue end
		local t=getStealTier(data.brainrotName); data.box.BackgroundColor3=getBoxBg(t)
		if t=="s" then stroke.Color=INDIGO_OUTLINE_S; stroke.Transparency=0
		elseif t=="m" then stroke.Color=SAPPHIRE_OUTLINE; stroke.Transparency=0
		elseif t=="l" then stroke.Color=YELLOW_OUTLINE; stroke.Transparency=0
		else stroke.Color=data.hovered and HOVER_WHITE or BORDER_BLACK; stroke.Transparency=0 end
		-- Glisten ONLY for purple and blue boxes (not yellow)
		local existGrad = data.box:FindFirstChild("_BoxShine")
		if t == "s" or t == "m" then
			local baseCol = (t == "s") and INDIGO_OUTLINE_S or SAPPHIRE_OUTLINE
			if _G._createGlisten then pcall(_G._createGlisten, data.box, baseCol) end
		else
			if existGrad then
				if _G._glistenGradients then _G._glistenGradients[existGrad] = nil end
				existGrad:Destroy()
			end
		end
	end
end

local BOX_H_SUPER = 72

local function relayoutBoxes()
	local yOff = PAD / 2
	for _, data in pairs(stealingEntries) do
		local isSuper = STEAL_GUI_SUPER[data.brainrotName]
		local h = isSuper and BOX_H_SUPER or BOX_H
		data.box.Position = UDim2.new(0, PAD, 0, yOff)
		data.box.Size = UDim2.new(1, -PAD * 2, 0, h)
		if isSuper then
			data.stealerLabel.TextSize = 13
			data.stealerLabel.Size = UDim2.new(1, -10, 0, 20)
			data.brainrotLabel.TextSize = 13
			data.brainrotLabel.Size = UDim2.new(1, -10, 0, 20)
			data.brainrotLabel.Position = UDim2.new(0, 6, 0, 24)
		else
			data.stealerLabel.TextSize = 11
			data.stealerLabel.Size = UDim2.new(1, -10, 0, 14)
			data.brainrotLabel.TextSize = 10
			data.brainrotLabel.Size = UDim2.new(1, -10, 0, 12)
			data.brainrotLabel.Position = UDim2.new(0, 6, 0, 18)
		end
		yOff = yOff + h + BOX_GAP
	end
	positionGui()
	updateOutlines()
end

local function buildCmdText()
	local available = getAvailable()
	if #available == 0 then return "" end
	local names = {}
	for _, cmd in ipairs(available) do
		table.insert(names, DISPLAY[cmd] or cmd)
	end
	return "Click to run: " .. table.concat(names, ", ")
end

local function refreshAllCmdLabels() end

local function createPlayerBox(player, brainrotName, fromMe)
	local initTier = getStealTier(brainrotName)
	local box = Instance.new("Frame")
	box.Name = "SB_" .. player.Name
	box.BackgroundColor3 = getBoxBg(initTier)
	box.BorderSizePixel = 0
	box.ZIndex = 2
	box.Parent = BoxContainer
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)

	local stroke = Instance.new("UIStroke", box)
	stroke.Color = BORDER_BLACK; stroke.Thickness = 1.5; stroke.Transparency = 0

	local hoverBtn = Instance.new("TextButton")
	hoverBtn.Size = UDim2.new(1, 0, 1, 0)
	hoverBtn.BackgroundTransparency = 1
	hoverBtn.Text = ""; hoverBtn.ZIndex = 10
	hoverBtn.Parent = box

	local displayName = player.DisplayName or player.Name

	local stealerLabel = Instance.new("TextLabel")
	stealerLabel.Name = "SL"
	stealerLabel.Size = UDim2.new(1, -10, 0, 14)
	stealerLabel.Position = UDim2.new(0, 6, 0, 3)
	stealerLabel.BackgroundTransparency = 1
	stealerLabel.Text = "Stealer: @" .. displayName
	stealerLabel.TextColor3 = WHITE
	stealerLabel.Font = Enum.Font.GothamBold
	stealerLabel.TextSize = 11
	stealerLabel.TextXAlignment = Enum.TextXAlignment.Left
	stealerLabel.TextTruncate = Enum.TextTruncate.AtEnd
	stealerLabel.ZIndex = 3
	stealerLabel.Parent = box

	local brainrotLabel = Instance.new("TextLabel")
	brainrotLabel.Name = "BL"
	brainrotLabel.Size = UDim2.new(1, -10, 0, 12)
	brainrotLabel.Position = UDim2.new(0, 6, 0, 18)
	brainrotLabel.BackgroundTransparency = 1
	brainrotLabel.RichText = true
	-- Super brainrots get indigo purple name (same size)
	local isSuper = STEAL_GUI_SUPER[brainrotName]
	if isSuper then
		local hex = string.format("#%02X%02X%02X", 120, 60, 220)
		local richLabel = pcall(getBrainrotRichLabel, brainrotName) and getBrainrotRichLabel(brainrotName) or brainrotName
		brainrotLabel.Text = '<font color="' .. hex .. '"><b>' .. richLabel .. '</b></font>'
		brainrotLabel.TextSize = 10
		-- Add glisten shine over brainrot name
		local nameGrad = Instance.new("UIGradient", brainrotLabel)
		nameGrad.Name = "_NameShine"
		nameGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 130, 0)),
			ColorSequenceKeypoint.new(0.42, Color3.fromRGB(180, 130, 0)),
			ColorSequenceKeypoint.new(0.48, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.52, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.58, Color3.fromRGB(180, 130, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 130, 0)),
		})
		if _glistenGradients then _glistenGradients[nameGrad] = true end
	else
		brainrotLabel.Text = pcall(getBrainrotRichLabel, brainrotName) and getBrainrotRichLabel(brainrotName) or ('<font color="#FFFFFF">' .. brainrotName .. '</font>')
		brainrotLabel.TextSize = 10
	end
	brainrotLabel.TextColor3 = WHITE
	brainrotLabel.Font = Enum.Font.GothamBold
	brainrotLabel.TextXAlignment = Enum.TextXAlignment.Left
	brainrotLabel.TextTruncate = Enum.TextTruncate.AtEnd
	brainrotLabel.ZIndex = 3
	brainrotLabel.Parent = box

	-- Add glisten shimmer for super and sapphire brainrot names (not yellow)
	if isSuper and _G._createGlisten then
		pcall(function() _G._createGlisten(box, Color3.fromRGB(180, 130, 0)) end)
	elseif STEAL_SAPPHIRE and STEAL_SAPPHIRE[brainrotName] and _G._createGlisten then
		pcall(function() _G._createGlisten(box, SAPPHIRE_OUTLINE) end)
	end



	local entryData = {
		box = box, brainrotName = brainrotName,
		stealerLabel = stealerLabel, brainrotLabel = brainrotLabel,
		stroke = stroke,
		hovered = false, stealingFromMe = fromMe, player = player,
	}

	hoverBtn.MouseEnter:Connect(function()
		entryData.hovered = true
		if true then
			stroke.Color = HOVER_WHITE; stroke.Transparency = 0
		end
	end)

	hoverBtn.MouseLeave:Connect(function()
		entryData.hovered = false
		updateOutlines()
	end)

	hoverBtn.MouseButton1Click:Connect(function()
		local available = getAvailable()
		if #available == 0 then return end
		executeCommand(player, available[1])
		refreshAllCmdLabels()
	end)

	return entryData
end

local function removePlayerBox(player)
	local data = stealingEntries[player]
	if data then
		data.box:Destroy()
		stealingEntries[player] = nil
		relayoutBoxes()
	end
end

task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end
	task.wait(1)

	while task.wait(0.8) do
		local currentStealers = {}

		pcall(function()
			for _, player in ipairs(Players:GetPlayers()) do
				if player == LocalPlayer then continue end

				local stealOk, isStealing = pcall(function()
					return player:GetAttribute("Stealing") == true
				end)

				if stealOk and isStealing then
					currentStealers[player] = true
					local brainrotName = getBrainrotName(player)
					local fromMe = isStealingFromMe(player)
					local displayName = player.DisplayName or player.Name

					if stealingEntries[player] then
						local data = stealingEntries[player]
						data.brainrotName = brainrotName
						data.stealingFromMe = fromMe
						data.stealerLabel.Text = "Stealer: @" .. displayName
						local _rl = ""; pcall(function() _rl = getBrainrotRichLabel(brainrotName) end)
						data.brainrotLabel.Text = #_rl > 0 and _rl or ('<font color="#FFFFFF">' .. brainrotName .. '</font>')
						updateOutlines()
					else
						local data = createPlayerBox(player, brainrotName, fromMe)
						stealingEntries[player] = data
						relayoutBoxes()
					end
				end
			end
		end)

		for player, _ in pairs(stealingEntries) do
			if not currentStealers[player] then
				removePlayerBox(player)
			end
		end

		refreshAllCmdLabels()
		updateOutlines()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if stealingEntries[player] then
		removePlayerBox(player)
	end
end)
-- -360 ahhh
    end)
end)

-- ═══ Steal Destination Line ═══
task.spawn(function()
    pcall(function()
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Workspace = game:GetService("Workspace")
    local LocalPlayer = Players.LocalPlayer

    local Synchronizer = require(ReplicatedStorage.Packages.Synchronizer)
    local AnimalsData = require(ReplicatedStorage.Datas.Animals)
    local AnimalsShared = require(ReplicatedStorage.Shared.Animals)
    local NumberUtils = require(ReplicatedStorage.Utils.NumberUtils)

    -- Priority list (lower = higher priority)
    local DEST_PRIORITY = {["Headless Horseman"]=1,["Strawberry Elephant"]=2,["Meowl"]=3,["Signore Caraprace"]=4,["Signore Carapace"]=4,["Skibidi Toilet"]=5,["Dragon Gingerini"]=6,["Griffin"]=7,["Dragon Cannelloni"]=8,["Love Love Bear"]=9,["La Supreme Combinasion"]=10,["Antonio"]=11,["Ginger Gerat"]=12,["Elefanto Frigo"]=13,["Ketupat Bros"]=14,["Hydra Bunny"]=15,["Dug Dug Dug"]=16,["Dug dug dug"]=16,["Hydra Dragon Cannelloni"]=17,["Fishino Clownino"]=18,["Tirilikalika Tirilikalako"]=19,["Cerberus"]=20,["La Casa Boo"]=21,["Fragola La La La"]=22,["La Food Combinasion"]=23,["Capitano Moby"]=24,["Los Sekolahs"]=25,["Los Amigos"]=26,["Rosey and Teddy"]=27,["Reinito Sleighito"]=28,["Burguro And Fryuro"]=29,["Foxini Laternini"]=30,["Foxini Lanternini"]=30,["Spooky and Pumpky"]=31,["Cooki and Milki"]=32,["Celestial Pegasus"]=33,["Garama and Madundung"]=34,["Sammyni Fattini"]=35,["Sammyni Fattyin"]=35,["Fortunu and Cashuru"]=36,["La Secret Combinasion"]=37,["Ketchuru and Musturu"]=38,["Tralaledon"]=39,["Tictac Sahur"]=40,["Ketupat Kepat"]=41,["Tang Tang Keletang"]=42,["Orcaledon"]=43,["La Ginger Sekolah"]=44,["Lavadorito Spinito"]=45,["La Taco Combinasion"]=46,["Los Primos"]=47,["Los Bros"]=48,["Las Sis"]=49,["Chillin Chili"]=50,["W or L"]=51,["Chipso and Queso"]=52}

    local _sdBeam, _sdA0, _sdA1, _sdTargetPart = nil, nil, nil, nil
    local _sdHighlight = nil
    local _sdNameGui = nil
    local _sdLastStealer = nil
    local _sdLastSlot = nil

    local function findPlayerBase(player)
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then return nil end
        for _, plot in ipairs(plots:GetChildren()) do
            local ok, result = pcall(function()
                local ch = Synchronizer:Get(plot.Name)
                if not ch then return nil end
                local owner = ch:Get("Owner")
                if not owner then return nil end
                if typeof(owner) == "Instance" and owner:IsA("Player") and owner == player then return plot end
                if type(owner) == "table" and owner.UserId and owner.UserId == player.UserId then return plot end
                return nil
            end)
            if ok and result then return result end
        end
        -- Fallback: check sign text
        local n = player.Name:lower()
        local d = (player.DisplayName or player.Name):lower()
        for _, plot in ipairs(plots:GetChildren()) do
            local s = plot:FindFirstChild("PlotSign")
            local l = s and s:FindFirstChildWhichIsA("TextLabel", true)
            if l and (l.Text:lower():find(n, 1, true) or l.Text:lower():find(d, 1, true)) then return plot end
        end
        return nil
    end

    local function countFilledSlots(plot)
        local filled = 0
        local ok = pcall(function()
            local ch = Synchronizer:Get(plot.Name)
            if not ch then return end
            local al = ch:Get("AnimalList")
            if not al then return end
            for _, data in pairs(al) do
                if type(data) == "table" and data.Index then
                    filled = filled + 1
                end
            end
        end)
        return filled
    end

    local function getNextSlotPart(plot)
        local filled = countFilledSlots(plot)
        local nextSlot = tostring(filled + 1)
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if not podiums then return nil end
        local podium = podiums:FindFirstChild(nextSlot)
        if not podium then
            -- Try finding any empty slot
            for i = 1, 16 do
                local p = podiums:FindFirstChild(tostring(i))
                if p then
                    local hasAnimal = false
                    pcall(function()
                        local ch = Synchronizer:Get(plot.Name)
                        if ch then
                            local al = ch:Get("AnimalList")
                            if al and al[i] and type(al[i]) == "table" and al[i].Index then hasAnimal = true end
                            if al and al[tostring(i)] and type(al[tostring(i)]) == "table" and al[tostring(i)].Index then hasAnimal = true end
                        end
                    end)
                    if not hasAnimal then podium = p; break end
                end
            end
        end
        if not podium then return nil end
        local base = podium:FindFirstChild("Base")
        if base then
            local spawn = base:FindFirstChild("Spawn")
            if spawn and spawn:IsA("BasePart") then return spawn end
            local bp = base:FindFirstChildWhichIsA("BasePart")
            if bp then return bp end
        end
        local bp = podium:FindFirstChildWhichIsA("BasePart", true)
        return bp
    end

    local function destroyDestLine()
        if _sdBeam then pcall(function() _sdBeam:Destroy() end); _sdBeam = nil end
        if _sdA0 then pcall(function() _sdA0:Destroy() end); _sdA0 = nil end
        if _sdA1 then pcall(function() _sdA1:Destroy() end); _sdA1 = nil end
        if _sdTargetPart then pcall(function() _sdTargetPart:Destroy() end); _sdTargetPart = nil end
        if _sdHighlight then pcall(function() _sdHighlight:Destroy() end); _sdHighlight = nil end
        if _sdNameGui then pcall(function() _sdNameGui:Destroy() end); _sdNameGui = nil end
        _sdLastStealer = nil; _sdLastSlot = nil
    end

    local function createDestLine(hrp, slotPart, stealer, stealerPlot, brainrotName, mutation, genText, brainrotImage)
        destroyDestLine()
        if not hrp or not slotPart then return end

        -- White beam from player to slot
        _sdTargetPart = Instance.new("Part")
        _sdTargetPart.Name = "StealDestTarget"; _sdTargetPart.Size = Vector3.new(1,1,1)
        _sdTargetPart.Anchored = true; _sdTargetPart.CanCollide = false; _sdTargetPart.Transparency = 1
        _sdTargetPart.Parent = Workspace
        _sdTargetPart.Position = slotPart.Position

        _sdA0 = Instance.new("Attachment"); _sdA0.Parent = hrp
        _sdA1 = Instance.new("Attachment"); _sdA1.Parent = _sdTargetPart

        _sdBeam = Instance.new("Beam")
        _sdBeam.Attachment0 = _sdA0; _sdBeam.Attachment1 = _sdA1
        _sdBeam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
        _sdBeam.FaceCamera = true; _sdBeam.LightEmission = 0.8
        _sdBeam.Transparency = NumberSequence.new(0.5)
        _sdBeam.Width0 = 0.15; _sdBeam.Width1 = 0.08
        _sdBeam.Parent = hrp

        -- White glowing outline on slot (through walls)
        _sdHighlight = Instance.new("Highlight")
        _sdHighlight.Name = "StealDestHL"
        _sdHighlight.FillColor = Color3.fromRGB(255, 255, 255)
        _sdHighlight.FillTransparency = 0.7
        _sdHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        _sdHighlight.OutlineTransparency = 0
        _sdHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        _sdHighlight.Adornee = slotPart.Parent or slotPart
        _sdHighlight.Parent = slotPart

        -- Compact notification-style display above stealer's base
        if stealerPlot then
            local sign = stealerPlot:FindFirstChild("PlotSign")
            local signPart = sign and sign:FindFirstChildWhichIsA("BasePart") or sign
            if not signPart and sign then signPart = sign end
            local adorneePart = nil
            if signPart and signPart:IsA("BasePart") then adorneePart = signPart
            elseif signPart and signPart:IsA("Model") then adorneePart = signPart:FindFirstChildWhichIsA("BasePart", true) end
            if not adorneePart then adorneePart = stealerPlot:FindFirstChildWhichIsA("BasePart", true) end
            if adorneePart then
                local INDIGO_SUPER = {["Strawberry Elephant"]=true,["Meowl"]=true,["Headless Horseman"]=true,["Skibidi Toilet"]=true,["Signore Caraprace"]=true}
                local INDIGO_COL = Color3.fromRGB(93, 63, 211)
                local MUT_COLS = {Lava=Color3.fromRGB(255,165,0),Bloodrot=Color3.fromRGB(255,0,0),Candy=Color3.fromRGB(255,105,180),Gold=Color3.fromRGB(255,215,0),Diamond=Color3.fromRGB(0,191,255),Radioactive=Color3.fromRGB(0,255,0),Galaxy=Color3.fromRGB(180,120,255),Divine=Color3.fromRGB(255,250,200),Cyber=Color3.fromRGB(0,255,255)}
                local hasImage = brainrotImage ~= nil
                local hasMut = mutation and mutation ~= "None" and mutation ~= ""

                -- Build rich text line: [MUTATION] Name $X/s
                local richParts = {}
                if hasMut then
                    local mc = MUT_COLS[mutation] or Color3.fromRGB(200, 200, 200)
                    local hex = string.format("#%02X%02X%02X", math.floor(mc.R*255), math.floor(mc.G*255), math.floor(mc.B*255))
                    table.insert(richParts, '<font color="' .. hex .. '">' .. string.upper(mutation) .. '</font>  ')
                end
                local nameCol = INDIGO_SUPER[brainrotName] and "#5D3FD3" or "#FFFFFF"
                table.insert(richParts, '<font color="' .. nameCol .. '">' .. (brainrotName or "Unknown") .. '</font>')
                if genText and genText ~= "" then
                    table.insert(richParts, '  <font color="#55FF55">' .. genText .. '</font>')
                end

                _sdNameGui = Instance.new("BillboardGui")
                _sdNameGui.Name = "StealDestName"
                _sdNameGui.Size = UDim2.new(0, 220, 0, hasImage and 44 or 28)
                _sdNameGui.StudsOffset = Vector3.new(0, 4.5, 0)
                _sdNameGui.AlwaysOnTop = true
                _sdNameGui.Adornee = adorneePart
                _sdNameGui.Parent = adorneePart

                local bg = Instance.new("Frame")
                bg.Size = UDim2.new(1, 0, 1, 0)
                bg.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
                bg.BackgroundTransparency = 0.25
                bg.BorderSizePixel = 0
                bg.Parent = _sdNameGui
                Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 8)
                local stroke = Instance.new("UIStroke", bg)
                stroke.Color = Color3.fromRGB(255, 40, 160); stroke.Thickness = 1

                local imgW = hasImage and 30 or 0
                local textX = hasImage and 34 or 6

                if hasImage then
                    local img = Instance.new("ImageLabel")
                    img.Size = UDim2.new(0, 26, 0, 26)
                    img.Position = UDim2.new(0, 5, 0.5, -13)
                    img.BackgroundTransparency = 1; img.Image = brainrotImage
                    img.ScaleType = Enum.ScaleType.Fit; img.Parent = bg
                end

                -- Username line
                local userLabel = Instance.new("TextLabel")
                userLabel.Size = UDim2.new(1, -textX - 4, 0, 13)
                userLabel.Position = UDim2.new(0, textX, 0, 3)
                userLabel.BackgroundTransparency = 1; userLabel.RichText = true
                userLabel.Font = Enum.Font.GothamBold; userLabel.TextSize = 9
                userLabel.TextXAlignment = Enum.TextXAlignment.Left
                userLabel.Text = '<font color="#FF4646">@' .. (stealer.DisplayName or stealer.Name) .. '</font>'
                userLabel.Parent = bg

                -- Brainrot info line
                local infoLabel = Instance.new("TextLabel")
                infoLabel.Size = UDim2.new(1, -textX - 4, 0, 13)
                infoLabel.Position = UDim2.new(0, textX, 0, hasImage and 18 or 16)
                infoLabel.BackgroundTransparency = 1; infoLabel.RichText = true
                infoLabel.Font = Enum.Font.GothamBold; infoLabel.TextSize = 10
                infoLabel.TextXAlignment = Enum.TextXAlignment.Left
                infoLabel.TextStrokeTransparency = 0.5; infoLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                infoLabel.Text = table.concat(richParts)
                infoLabel.Parent = bg
            end
        end

        _sdLastStealer = stealer
    end

    task.wait(3)

    local _sdFrame = 0
    RunService.Heartbeat:Connect(function()
        _sdFrame = _sdFrame + 1
        if _sdFrame < 30 then return end
        _sdFrame = 0

        pcall(function()
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then destroyDestLine(); return end

            -- Find player stealing highest priority brainrot
            local bestStealer, bestPriority, bestBrainrot, bestStealIdx = nil, math.huge, nil, nil
            for _, player in ipairs(Players:GetPlayers()) do
                if player == LocalPlayer then continue end
                local ok, isStealing = pcall(function() return player:GetAttribute("Stealing") == true end)
                if not (ok and isStealing) then continue end
                local ok2, stealIdx = pcall(function() return player:GetAttribute("StealingIndex") end)
                if not ok2 or not stealIdx or stealIdx == "" then continue end
                local displayName = stealIdx
                pcall(function()
                    local info = AnimalsData[stealIdx]
                    if info and info.DisplayName then displayName = info.DisplayName end
                end)
                local rank = DEST_PRIORITY[displayName]
                if rank and rank < bestPriority then
                    bestPriority = rank
                    bestStealer = player
                    bestBrainrot = displayName
                    bestStealIdx = stealIdx
                end
            end

            if not bestStealer then
                destroyDestLine()
                return
            end

            -- Gather brainrot details (mutation, gen, image)
            local brainrotMutation, brainrotGen, brainrotImage = "None", "", nil
            pcall(function()
                local plots = Workspace:FindFirstChild("Plots"); if not plots then return end
                for _, plot in ipairs(plots:GetChildren()) do
                    local ch = Synchronizer:Get(plot.Name); if not ch then continue end
                    local al = ch:Get("AnimalList"); if not al then continue end
                    for slot, data in pairs(al) do
                        if type(data) == "table" and data.Index == bestStealIdx then
                            brainrotMutation = data.Mutation or "None"
                            local gv = AnimalsShared:GetGeneration(bestStealIdx, data.Mutation, data.Traits, nil)
                            brainrotGen = "$" .. NumberUtils:ToString(gv) .. "/s"
                            return
                        end
                    end
                end
            end)
            pcall(function()
                local info = AnimalsData[bestStealIdx]
                if info then
                    for _, f in ipairs({"Image","Thumbnail","Icon"}) do
                        if info[f] and type(info[f]) == "string" and info[f] ~= "" then brainrotImage = info[f]; break end
                    end
                end
            end)

            -- Find stealer's base and next slot
            local stealerPlot = findPlayerBase(bestStealer)
            if not stealerPlot then destroyDestLine(); return end

            local slotPart = getNextSlotPart(stealerPlot)
            if not slotPart then destroyDestLine(); return end

            -- Check if we need to update
            local slotId = slotPart:GetFullName()
            if _sdLastStealer == bestStealer and _sdLastSlot == slotId then
                -- Just update target position
                if _sdTargetPart and _sdTargetPart.Parent then
                    _sdTargetPart.Position = slotPart.Position
                end
                return
            end

            _sdLastSlot = slotId
            createDestLine(hrp, slotPart, bestStealer, stealerPlot, bestBrainrot, brainrotMutation, brainrotGen, brainrotImage)
        end)
    end)

    LocalPlayer.CharacterAdded:Connect(function()
        destroyDestLine()
    end)

    end)
end)


-- ═══ Subspace Tripmine ESP ═══
task.spawn(function()
    pcall(function()
-- ═══════════════════════════════════════
-- SubspaceTripmine ESP
-- Ignores local player's tripmines
-- ═══════════════════════════════════════
repeat task.wait() until game:IsLoaded()
task.wait(2)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local DARK_INDIGO = Color3.fromRGB(60, 20, 140)
local LIGHT_PURPLE = Color3.fromRGB(140, 80, 220)

local tripmineESP = {}
local myTripmines = {}
local lastPlaceTime = 0
local lastPlacePos = nil

-- Track when local player uses tripmine tool
local function watchTripmineTool(tool)
	if not tool.Name:lower():find("tripmine") and tool.Name ~= "SubspaceTripmine" then return end
	tool.Activated:Connect(function()
		local char = LocalPlayer.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			lastPlaceTime = tick()
			lastPlacePos = char.HumanoidRootPart.Position
		end
	end)
end

local function setupToolWatcher()
	local bp = LocalPlayer:FindFirstChild("Backpack")
	if bp then
		for _, t in pairs(bp:GetChildren()) do watchTripmineTool(t) end
		bp.ChildAdded:Connect(watchTripmineTool)
	end
	if LocalPlayer.Character then
		for _, t in pairs(LocalPlayer.Character:GetChildren()) do watchTripmineTool(t) end
	end
	LocalPlayer.CharacterAdded:Connect(function(char)
		task.wait(0.5)
		for _, t in pairs(char:GetChildren()) do watchTripmineTool(t) end
		char.ChildAdded:Connect(watchTripmineTool)
	end)
end
setupToolWatcher()

local function getPosition(obj)
	if obj:IsA("Model") then
		local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
		if pp then return pp.Position end
	elseif obj:IsA("BasePart") then
		return obj.Position
	end
	return nil
end

local function createTripmineESP(mine, displayName)
	local hl = Instance.new("Highlight")
	hl.Name = "OL_" .. tostring(math.random(1000,9999))
	hl.Adornee = mine
	hl.FillColor = LIGHT_PURPLE
	hl.FillTransparency = 0.45
	hl.OutlineColor = DARK_INDIGO
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = mine

	local selBox = Instance.new("SelectionBox")
	selBox.Name = "SB_" .. tostring(math.random(1000,9999))
	selBox.Adornee = mine
	selBox.Color3 = DARK_INDIGO
	selBox.LineThickness = 0.03
	selBox.SurfaceTransparency = 0.85
	selBox.SurfaceColor3 = LIGHT_PURPLE
	selBox.Parent = mine

	local bb = Instance.new("BillboardGui")
	bb.Name = "DT_" .. tostring(math.random(1000,9999))
	bb.Adornee = mine
	bb.Size = UDim2.new(0, 100, 0, 38)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.Parent = mine

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName or "Tripmine"
	nameLabel.TextColor3 = LIGHT_PURPLE
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 11
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.Parent = bb

	local distLabel = Instance.new("TextLabel")
	distLabel.Size = UDim2.new(1, 0, 0, 16)
	distLabel.Position = UDim2.new(0, 0, 0, 16)
	distLabel.BackgroundTransparency = 1
	distLabel.Text = "? studs"
	distLabel.TextColor3 = LIGHT_PURPLE
	distLabel.Font = Enum.Font.GothamBold
	distLabel.TextSize = 13
	distLabel.TextStrokeTransparency = 0.3
	distLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	distLabel.Parent = bb

	tripmineESP[mine] = { highlight = hl, selBox = selBox, billboard = bb, distLabel = distLabel }
end

local function removeTripmineESP(mine)
	local data = tripmineESP[mine]
	if data then
		pcall(function() data.highlight:Destroy() end)
		pcall(function() data.selBox:Destroy() end)
		pcall(function() data.billboard:Destroy() end)
		tripmineESP[mine] = nil
	end
	myTripmines[mine] = nil
end

local function isMyTripmine(mine)
	return myTripmines[mine] == true
end

local function isDetectable(obj)
	local n = obj.Name
	if n == "SubspaceTripmine" or n:lower():find("tripmine") then return "Tripmine" end
	if n == "BeeHive" or n:lower():find("beehive") then
		local plots = Workspace:FindFirstChild("Plots")
		if plots and obj:IsDescendantOf(plots) then return "Bee Hive" end
		return nil
	end
	return nil
end

local function onTripmineAdded(obj)
	local label = isDetectable(obj)
	if not label then return end
	task.wait(0.15)

	local timeSince = tick() - lastPlaceTime
	if timeSince < 2.5 and lastPlacePos then
		local pos = getPosition(obj)
		if pos and (pos - lastPlacePos).Magnitude < 25 then
			myTripmines[obj] = true
			lastPlaceTime = 0
			lastPlacePos = nil
			return
		end
	end

	if not isMyTripmine(obj) then
		createTripmineESP(obj, label)
	end
end

-- Distance update loop
local _tmF=0; RunService.RenderStepped:Connect(function()
	_tmF=_tmF+1; if _tmF<3 then return end; _tmF=0
	if _G._subspaceEspEnabled == false then
		-- Hide all tripmine ESP when disabled
		for mine, data in pairs(tripmineESP) do
			pcall(function() data.highlight.Enabled = false end)
			pcall(function() data.selBox.Visible = false end)
			pcall(function() data.billboard.Enabled = false end)
		end
		return
	end
	-- Re-show when re-enabled
	for mine, data in pairs(tripmineESP) do
		pcall(function() data.highlight.Enabled = true end)
		pcall(function() data.selBox.Visible = true end)
		pcall(function() data.billboard.Enabled = true end)
	end
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	for mine, data in pairs(tripmineESP) do
		if not mine or not mine.Parent then
			removeTripmineESP(mine)
		else
			local pos = getPosition(mine)
			if pos then
				local dist = math.floor((hrp.Position - pos).Magnitude + 0.5)
				data.distLabel.Text = dist .. " studs"
			end
		end
	end
end)

local function deepScan(parent)
	for _, obj in pairs(parent:GetDescendants()) do
		if isDetectable(obj) then
			task.spawn(function() onTripmineAdded(obj) end)
		end
	end
end

deepScan(Workspace)

-- Watch all descendants for new tripmines
Workspace.DescendantAdded:Connect(function(desc)
	if isDetectable(desc) then
		task.spawn(function() onTripmineAdded(desc) end)
	end
end)

Workspace.DescendantRemoving:Connect(function(desc)
	if tripmineESP[desc] then removeTripmineESP(desc) end
end)
-- -360 ahhh
    end)
end)

-- ═══ Conveyor Brainrot ESP ═══
task.spawn(function()
    pcall(function()
-- Highlights the highest-value brainrot that is currently riding a
-- conveyor/carpet machine (the red conveyor belts visible in plots, see
-- screenshot). Previous version tried to detect this by part-name/colour
-- heuristics on the podium geometry, which never matched real plot models —
-- so nothing was ever highlighted. Instead, this reads each animal's
-- `Machine` table directly from the Synchronizer (same data source the rest
-- of the hub uses), which is the authoritative source for "this brainrot is
-- currently on a conveyor".
-- Gated by _G._conveyorEspEnabled.
repeat task.wait() until game:IsLoaded()
task.wait(3)

local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local Players    = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Machine.Type values that represent a conveyor/transport belt. Brainrots
-- placed on these are walking along the red conveyor path shown in the
-- screenshot. Matched case-insensitively and by substring so naming
-- variants ("Conveyor", "ConveyorBelt", "Transport") all match.
local CONVEYOR_TYPE_KEYWORDS = {
    "conveyor", "belt", "transport", "carpet", "treadmill", "track", "roller",
}

local function isConveyorMachine(machine)
    if type(machine) ~= "table" then return false end
    local t = machine.Type
    if type(t) ~= "string" then return false end
    local tl = t:lower()
    for _, kw in ipairs(CONVEYOR_TYPE_KEYWORDS) do
        if tl:find(kw, 1, true) then return true end
    end
    return false
end

local _conveyorHL = nil
local _conveyorBB = nil
local _conveyorTargetUID = nil

local function clearConveyorESP()
    if _conveyorHL then pcall(function() _conveyorHL:Destroy() end); _conveyorHL = nil end
    if _conveyorBB then pcall(function() _conveyorBB:Destroy() end); _conveyorBB = nil end
    _conveyorTargetUID = nil
end

local function buildConveyorESP(adornee, name, genText, ownerName)
    clearConveyorESP()
    if not adornee then return end

    local hl = Instance.new("Highlight")
    hl.Name                = "ConveyorBrainrotHL"
    hl.Adornee             = adornee
    hl.FillColor           = Color3.fromRGB(255, 80, 0)
    hl.FillTransparency    = 0.25
    hl.OutlineColor        = Color3.fromRGB(255, 200, 0)
    hl.OutlineTransparency = 0
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled             = true
    hl.Parent              = adornee
    _conveyorHL = hl

    local bb = Instance.new("BillboardGui")
    bb.Name = "ConveyorBrainrotESP"
    bb.Size = UDim2.new(0, 220, 0, 48)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.AlwaysOnTop = true
    bb.LightInfluence = 0
    bb.MaxDistance = 3000
    bb.Adornee = adornee
    bb.Parent = adornee
    _conveyorBB = bb

    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 1, 0)
    container.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
    container.BackgroundTransparency = 0.3
    container.BorderSizePixel = 0
    container.Parent = bb
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", container)
    stroke.Color = Color3.fromRGB(255, 150, 0); stroke.Thickness = 1

    local tagLabel = Instance.new("TextLabel")
    tagLabel.Size = UDim2.new(1, -8, 0, 14)
    tagLabel.Position = UDim2.new(0, 4, 0, 2)
    tagLabel.BackgroundTransparency = 1
    tagLabel.Font = Enum.Font.GothamBold
    tagLabel.TextSize = 11
    tagLabel.TextColor3 = Color3.fromRGB(255, 165, 0)
    tagLabel.Text = "ON CONVEYOR"
    tagLabel.TextXAlignment = Enum.TextXAlignment.Center
    tagLabel.Parent = container

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -8, 0, 18)
    nameLabel.Position = UDim2.new(0, 4, 0, 15)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 16
    nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.Text = (name or "Unknown") .. "  " .. (genText or "")
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Parent = container

    local ownerLabel = Instance.new("TextLabel")
    ownerLabel.Size = UDim2.new(1, -8, 0, 13)
    ownerLabel.Position = UDim2.new(0, 4, 0, 33)
    ownerLabel.BackgroundTransparency = 1
    ownerLabel.Font = Enum.Font.GothamBold
    ownerLabel.TextSize = 11
    ownerLabel.TextColor3 = Color3.fromRGB(180, 180, 255)
    ownerLabel.Text = "@" .. tostring(ownerName or "Unknown")
    ownerLabel.TextXAlignment = Enum.TextXAlignment.Center
    ownerLabel.Parent = container
end

-- Scans all plots, finds animals whose Machine is a conveyor, and picks the
-- highest-generation one. Runs every ~0.5s.
local _convF = 0
RunService.Heartbeat:Connect(function()
    _convF = _convF + 1
    if _convF < 30 then return end
    _convF = 0

    if _G._conveyorEspEnabled ~= true then
        if _conveyorHL or _conveyorBB then clearConveyorESP() end
        return
    end

    local best, bestGen, bestUID = nil, -math.huge, nil
    pcall(function()
        local plots = Workspace:FindFirstChild("Plots")
        if not plots then return end
        for _, plot in ipairs(plots:GetChildren()) do
            local ok, channel = pcall(Synchronizer.Get, Synchronizer, plot.Name)
            if not ok or not channel then continue end

            -- Skip our own base
            local owner
            pcall(function() owner = channel:Get("Owner") end)
            local isMine = false
            if owner then
                if typeof(owner) == "Instance" and owner:IsA("Player") then
                    isMine = owner.UserId == LocalPlayer.UserId
                elseif type(owner) == "table" and owner.UserId then
                    isMine = owner.UserId == LocalPlayer.UserId
                end
            end
            if isMine then continue end

            local ownerName
            if typeof(owner) == "Instance" then ownerName = owner.Name
            elseif type(owner) == "table" then ownerName = owner.Name end

            local animalList
            pcall(function() animalList = channel:Get("AnimalList") end)
            if not animalList then continue end

            for slot, animalData in pairs(animalList) do
                if type(animalData) == "table" and isConveyorMachine(animalData.Machine) then
                    local animalName = animalData.Index
                    local info = AnimalsData and AnimalsData[animalName]
                    if info then
                        local genValue = 0
                        pcall(function()
                            genValue = AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil) or 0
                        end)
                        if genValue > bestGen then
                            bestGen = genValue
                            best = {
                                plot = plot.Name,
                                slot = tostring(slot),
                                name = (info.DisplayName or animalName),
                                genValue = genValue,
                                owner = ownerName,
                            }
                            bestUID = plot.Name .. "_" .. tostring(slot)
                        end
                    end
                end
            end
        end
    end)

    if not best then
        if _conveyorHL or _conveyorBB then clearConveyorESP() end
        return
    end

    if bestUID ~= _conveyorTargetUID then
        local plotsFolder = Workspace:FindFirstChild("Plots")
        local plot = plotsFolder and plotsFolder:FindFirstChild(best.plot)
        local podiums = plot and plot:FindFirstChild("AnimalPodiums")
        local podium = podiums and podiums:FindFirstChild(best.slot)
        local adornee = nil
        if podium then
            local base = podium:FindFirstChild("Base")
            local spawn = base and base:FindFirstChild("Spawn")
            adornee = spawn or (base and base:FindFirstChildWhichIsA("BasePart")) or podium:FindFirstChildWhichIsA("BasePart", true)
        end
        if adornee then
            local genText = ""
            pcall(function() genText = "$" .. NumberUtils:ToString(best.genValue) .. "/s" end)
            buildConveyorESP(adornee, best.name, genText, best.owner)
            _conveyorTargetUID = bestUID
        else
            clearConveyorESP()
        end
    end
end)
    end)
end)

-- ═══ Line to Best Brainrot (3D Beam) ═══
-- Uses the same Beam approach as Line to Base, but targets the highest-value
-- brainrot from _G._stealAnimalsCache (the Steal Target tracker, already
-- sorted by genValue descending). No independent scanner needed.
task.spawn(function()
    pcall(function()
repeat task.wait() until game:IsLoaded()

local brainrotBeam           = nil
local brainrotBeamAttach0    = nil  -- on player HRP
local brainrotBeamAttach1    = nil  -- on target podium part
local _brainrotBeamLastUID   = nil  -- tracks which slot the beam is aimed at

-- Resolve the world BasePart for a steal-cache entry {plot, slot}
local function _lbb_resolvePart(entry)
    local part = nil
    pcall(function()
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return end
        local pl = plots:FindFirstChild(entry.plot)
        if not pl then return end
        local pods = pl:FindFirstChild("AnimalPodiums")
        if not pods then return end
        local pod = pods:FindFirstChild(entry.slot)
        if not pod then return end
        local base = pod:FindFirstChild("Base")
        if base then
            local sp = base:FindFirstChild("Spawn")
            if sp and sp:IsA("BasePart") then part = sp; return end
            if base:IsA("BasePart") then part = base; return end
        end
        part = pod:FindFirstChildWhichIsA("BasePart", true)
    end)
    return part
end

-- Tear down beam + attachments
local function _lbb_reset()
    if brainrotBeam          then pcall(function() brainrotBeam:Destroy()        end) end
    if brainrotBeamAttach0   then pcall(function() brainrotBeamAttach0:Destroy() end) end
    if brainrotBeamAttach1   then pcall(function() brainrotBeamAttach1:Destroy() end) end
    brainrotBeam         = nil
    brainrotBeamAttach0  = nil
    brainrotBeamAttach1  = nil
    _brainrotBeamLastUID = nil
end

-- Build or redirect the beam to targetPart
local function _lbb_create(targetPart)
    if not targetPart or not targetPart.Parent then _lbb_reset(); return end
    local character = game.Players.LocalPlayer.Character
    if not character then _lbb_reset(); return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then _lbb_reset(); return end

    -- Clean old beam
    _lbb_reset()

    -- Attachment on player HRP
    brainrotBeamAttach0 = Instance.new("Attachment")
    brainrotBeamAttach0.Name     = "BrainrotBeamAttach_Player"
    brainrotBeamAttach0.Position = Vector3.new(0, 0, 0)
    brainrotBeamAttach0.Parent   = hrp

    -- Attachment on target podium part
    brainrotBeamAttach1 = Instance.new("Attachment")
    brainrotBeamAttach1.Name     = "BrainrotBeamAttach_Target"
    brainrotBeamAttach1.Position = Vector3.new(0, 2, 0)
    brainrotBeamAttach1.Parent   = targetPart

    -- Create the beam (cyan, same visual language as the old line colour)
    brainrotBeam = Instance.new("Beam")
    brainrotBeam.Name          = "BrainrotBeam"
    brainrotBeam.Attachment0   = brainrotBeamAttach0
    brainrotBeam.Attachment1   = brainrotBeamAttach1
    brainrotBeam.FaceCamera    = true
    brainrotBeam.LightEmission = 1
    brainrotBeam.Color         = ColorSequence.new(Color3.fromRGB(255, 79, 200))
    brainrotBeam.Transparency  = NumberSequence.new(0)
    brainrotBeam.Width0        = 0.7
    brainrotBeam.Width1        = 0.7
    brainrotBeam.TextureMode   = Enum.TextureMode.Wrap
    brainrotBeam.TextureSpeed  = 0
    brainrotBeam.Parent        = hrp
end

-- Periodic update: reads steal tracker's #1 entry, recreates beam when target changes
task.spawn(function()
    local checkCounter = 0
    game:GetService("RunService").Heartbeat:Connect(function()
        checkCounter = checkCounter + 1
        if checkCounter < 30 then return end
        checkCounter = 0

        if _G._lineToBrainrotEnabled ~= true then
            if brainrotBeam or brainrotBeamAttach0 or brainrotBeamAttach1 then
                _lbb_reset()
            end
            return
        end

        -- Use the steal tracker's already-sorted cache (#1 = highest genValue)
        local cache = _G._stealAnimalsCache
        local top   = cache and cache[1]
        if not top then
            _lbb_reset(); return
        end

        local uid = top.uid
        -- Only rebuild beam when the top target changes or beam was destroyed
        if uid ~= _brainrotBeamLastUID
           or not brainrotBeam or not brainrotBeam.Parent
           or not brainrotBeamAttach0 or not brainrotBeamAttach0.Parent
           or not brainrotBeamAttach1 or not brainrotBeamAttach1.Parent then
            local part = _lbb_resolvePart(top)
            if part then
                pcall(_lbb_create, part)
                _brainrotBeamLastUID = uid
            else
                _lbb_reset()
            end
        end
    end)
end)

-- Rebuild on respawn
game.Players.LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    _brainrotBeamLastUID = nil  -- force rebuild
    if _G._lineToBrainrotEnabled == true then
        local cache = _G._stealAnimalsCache
        local top   = cache and cache[1]
        if top then
            local part = _lbb_resolvePart(top)
            if part then pcall(_lbb_create, part); _brainrotBeamLastUID = top.uid end
        end
    end
end)

-- Expose for external reset/update hooks (mirrors Line to Base pattern)
_G.resetBrainrotBeam  = _lbb_reset
_G.updateBrainrotBeam = function()
    _brainrotBeamLastUID = nil  -- force rebuild on next tick
end

    end)
end)

-- ═══ Line to Base (3D Beam) ═══
-- Draws a world-space Beam (through-walls via LightEmission) from the
-- player's HumanoidRootPart to their own plot, gated by the existing
-- "Line to Base" toggle (_G._lineToBaseEnabled).
task.spawn(function()
    pcall(function()
repeat task.wait() until game:IsLoaded()

local plotBeam = nil
local plotBeamAttachment0 = nil
local plotBeamAttachment1 = nil

-- Finds the plot owned by the LocalPlayer
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
                    if text:find(game.Players.LocalPlayer.DisplayName:lower(), 1, true) or
                       text:find(game.Players.LocalPlayer.Name:lower(), 1, true) then
                        return plot
                    end
                end
            end
        end
    end
    -- Fallback: check Synchronizer owner
    for _, plot in ipairs(plots:GetChildren()) do
        local ok, ch = pcall(function()
            return require(game.ReplicatedStorage.Packages.Synchronizer):Get(plot.Name)
        end)
        if ok and ch then
            local owner = ch:Get("Owner")
            local localPlayer = game.Players.LocalPlayer
            if type(owner) == "Instance" and owner:IsA("Player") then
                if owner == localPlayer then return plot end
            elseif type(owner) == "table" and owner.UserId == localPlayer.UserId then
                return plot
            end
        end
    end
    return nil
end

-- Creates the beam from player to base
local function createPlotBeam()
    if _G._lineToBaseEnabled ~= true then return end
    local myPlot = findMyPlot()
    if not myPlot or not myPlot.Parent then return end
    local character = game.Players.LocalPlayer.Character
    if not character or not character.Parent then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp or not hrp.Parent then return end

    -- Clean up old beam
    if plotBeam then pcall(function() plotBeam:Destroy() end) end
    if plotBeamAttachment0 then pcall(function() plotBeamAttachment0:Destroy() end) end

    -- Attachment on player
    plotBeamAttachment0 = hrp:FindFirstChild("PlotBeamAttach_Player") or Instance.new("Attachment")
    plotBeamAttachment0.Name = "PlotBeamAttach_Player"
    plotBeamAttachment0.Position = Vector3.new(0, 0, 0)
    plotBeamAttachment0.Parent = hrp

    -- Attachment on plot (find a BasePart to attach to)
    local plotPart = myPlot:FindFirstChild("MainRootPart") or myPlot:FindFirstChildWhichIsA("BasePart")
    if not plotPart or not plotPart.Parent then return end
    plotBeamAttachment1 = plotPart:FindFirstChild("PlotBeamAttach_Plot") or Instance.new("Attachment")
    plotBeamAttachment1.Name = "PlotBeamAttach_Plot"
    plotBeamAttachment1.Position = Vector3.new(0, 5, 0)
    plotBeamAttachment1.Parent = plotPart

    -- Create the beam
    plotBeam = hrp:FindFirstChild("PlotBeam") or Instance.new("Beam")
    plotBeam.Name = "PlotBeam"
    plotBeam.Attachment0 = plotBeamAttachment0
    plotBeam.Attachment1 = plotBeamAttachment1
    plotBeam.FaceCamera = true
    plotBeam.LightEmission = 1
    plotBeam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
    plotBeam.Transparency = NumberSequence.new(0)
    plotBeam.Width0 = 0.7
    plotBeam.Width1 = 0.7
    plotBeam.TextureMode = Enum.TextureMode.Wrap
    plotBeam.TextureSpeed = 0
    plotBeam.Parent = hrp
end

-- Removes the beam and attachments
local function resetPlotBeam()
    if plotBeam then pcall(function() plotBeam:Destroy() end) end
    if plotBeamAttachment0 then pcall(function() plotBeamAttachment0:Destroy() end) end
    if plotBeamAttachment1 then pcall(function() plotBeamAttachment1:Destroy() end) end
    plotBeam = nil
    plotBeamAttachment0 = nil
    plotBeamAttachment1 = nil
end

-- Auto-update: recreate beam periodically (every 30 frames), respecting toggle
task.spawn(function()
    local checkCounter = 0
    game:GetService("RunService").Heartbeat:Connect(function()
        checkCounter = checkCounter + 1
        if checkCounter >= 30 then
            checkCounter = 0
            if _G._lineToBaseEnabled ~= true then
                if plotBeam or plotBeamAttachment0 or plotBeamAttachment1 then
                    resetPlotBeam()
                end
                return
            end
            if not plotBeam or not plotBeam.Parent or not plotBeamAttachment0 or not plotBeamAttachment0.Parent then
                pcall(createPlotBeam)
            end
        end
    end)
end)

-- Recreate beam when character respawns
game.Players.LocalPlayer.CharacterAdded:Connect(function(character)
    task.wait(0.5)
    if _G._lineToBaseEnabled == true then pcall(createPlotBeam) end
end)

-- Initial creation if character already exists
if game.Players.LocalPlayer.Character then
    task.spawn(function()
        task.wait(0.2)
        if _G._lineToBaseEnabled == true then pcall(createPlotBeam) end
    end)
end

-- Expose globally
_G.createPlotBeam = createPlotBeam
_G.resetPlotBeam = resetPlotBeam
    end)
end)

-- ═══ Blacklist ESP ═══
task.spawn(function()
    pcall(function()
-- Highlights players on the hub's blacklist with a bright red glow.
-- Reads _G._blacklistedPlayers (set by Auto Kick blacklist) or _G._kickList.
-- Gated by _G._blacklistEspEnabled.
repeat task.wait() until game:IsLoaded()
task.wait(2)

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local Workspace   = game:GetService("Workspace")

local BL_FILL     = Color3.fromRGB(220, 20, 20)
local BL_OUTLINE  = Color3.fromRGB(255, 80, 80)

local _blHighlights = {}   -- [player.UserId] = {highlight, player}

local function getBlacklist()
    return _G._blacklistedPlayers or _G._kickList or {}
end

local function isBlacklisted(player)
    local bl = getBlacklist()
    if bl[player.Name] or bl[player.UserId] then return true end
    for _, v in pairs(bl) do
        if v == player.Name or v == player.UserId then return true end
    end
    return false
end

local function addBLHighlight(player)
    if _blHighlights[player.UserId] then return end
    local char = player.Character
    if not char then return end
    local hl = Instance.new("Highlight")
    hl.Adornee            = char
    hl.FillColor          = BL_FILL
    hl.FillTransparency   = 0.3
    hl.OutlineColor       = BL_OUTLINE
    hl.OutlineTransparency = 0
    hl.DepthMode          = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Enabled            = true
    hl.Parent             = char
    _blHighlights[player.UserId] = { highlight = hl, player = player }
end

local function removeBLHighlight(userId)
    local entry = _blHighlights[userId]
    if entry then
        pcall(function() entry.highlight:Destroy() end)
        _blHighlights[userId] = nil
    end
end

local function refreshBLHighlights()
    local enabled = _G._blacklistEspEnabled == true
    if not enabled then
        for userId in pairs(_blHighlights) do removeBLHighlight(userId) end
        return
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Players.LocalPlayer then
            if isBlacklisted(player) then
                if player.Character then
                    addBLHighlight(player)
                end
            else
                removeBLHighlight(player.UserId)
            end
        end
    end
    -- Clean up stale entries
    for userId, entry in pairs(_blHighlights) do
        if not entry.player or not entry.player.Parent then
            removeBLHighlight(userId)
        end
    end
end

Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function() task.wait(0.5); refreshBLHighlights() end)
end)
Players.PlayerRemoving:Connect(function(p) removeBLHighlight(p.UserId) end)

local _blF = 0
RunService.Heartbeat:Connect(function()
    _blF = _blF + 1; if _blF < 90 then return end; _blF = 0
    pcall(refreshBLHighlights)
end)
    end)
end)

-- ═══ Sentry ESP ═══
task.spawn(function()
    pcall(function()
-- ═══════════════════════════════════════
-- Ignores local player's sentries
-- ═══════════════════════════════════════
repeat task.wait() until game:IsLoaded()
task.wait(2)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local RUBY_RED = Color3.fromRGB(190, 20, 40)
local DARK_RED = Color3.fromRGB(120, 10, 20)

local sentryESP = {}
local mySentries = {}
local lastPlaceTime = 0
local lastPlacePos = nil

-- Track when local player uses sentry tool
local function watchSentryTool(tool)
	if tool.Name ~= "All Seeing Sentry" then return end
	tool.Activated:Connect(function()
		local char = LocalPlayer.Character
		if char and char:FindFirstChild("HumanoidRootPart") then
			lastPlaceTime = tick()
			lastPlacePos = char.HumanoidRootPart.Position
		end
	end)
end

local function setupToolWatcher()
	local bp = LocalPlayer:FindFirstChild("Backpack")
	if bp then
		for _, t in pairs(bp:GetChildren()) do watchSentryTool(t) end
		bp.ChildAdded:Connect(watchSentryTool)
	end
	if LocalPlayer.Character then
		for _, t in pairs(LocalPlayer.Character:GetChildren()) do watchSentryTool(t) end
	end
	LocalPlayer.CharacterAdded:Connect(function(char)
		task.wait(0.5)
		for _, t in pairs(char:GetChildren()) do watchSentryTool(t) end
		char.ChildAdded:Connect(watchSentryTool)
	end)
end
setupToolWatcher()

local function getPosition(obj)
	if obj:IsA("Model") then
		local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
		if pp then return pp.Position end
	elseif obj:IsA("BasePart") then
		return obj.Position
	end
	return nil
end

local function createSentryESP(sentry)
	local hl = Instance.new("Highlight")
	hl.Name = "OL_" .. tostring(math.random(1000,9999))
	hl.Adornee = sentry
	hl.FillColor = RUBY_RED
	hl.FillTransparency = 0.35
	hl.OutlineColor = DARK_RED
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = sentry

	local bb = Instance.new("BillboardGui")
	bb.Name = "DT_" .. tostring(math.random(1000,9999))
	bb.Adornee = sentry
	bb.Size = UDim2.new(0, 100, 0, 38)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.Parent = sentry

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "Turret"
	nameLabel.TextColor3 = RUBY_RED
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.Parent = bb

	local distLabel = Instance.new("TextLabel")
	distLabel.Size = UDim2.new(1, 0, 0, 16)
	distLabel.Position = UDim2.new(0, 0, 0, 16)
	distLabel.BackgroundTransparency = 1
	distLabel.Text = "? studs"
	distLabel.TextColor3 = RUBY_RED
	distLabel.Font = Enum.Font.GothamBold
	distLabel.TextSize = 14
	distLabel.TextStrokeTransparency = 0.3
	distLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	distLabel.Parent = bb

	sentryESP[sentry] = { highlight = hl, billboard = bb, distLabel = distLabel }
end

local function removeSentryESP(sentry)
	local data = sentryESP[sentry]
	if data then
		pcall(function() data.highlight:Destroy() end)
		pcall(function() data.billboard:Destroy() end)
		sentryESP[sentry] = nil
	end
	mySentries[sentry] = nil
end

local function isMySentry(sentry)
	return mySentries[sentry] == true
end

local function onSentryAdded(obj)
	if not obj.Name:match("^Sentry_%d+$") then return end
	task.wait(0.15)

	local timeSince = tick() - lastPlaceTime
	if timeSince < 2.5 and lastPlacePos then
		local pos = getPosition(obj)
		if pos and (pos - lastPlacePos).Magnitude < 25 then
			mySentries[obj] = true
			lastPlaceTime = 0
			lastPlacePos = nil
			return
		end
	end

	if not isMySentry(obj) then
		createSentryESP(obj)
	end
end

-- Distance update loop
local _snF=0; RunService.RenderStepped:Connect(function()
	_snF=_snF+1; if _snF<3 then return end; _snF=0
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	for sentry, data in pairs(sentryESP) do
		if not sentry or not sentry.Parent then
			removeSentryESP(sentry)
		else
			local pos = getPosition(sentry)
			if pos then
				local dist = math.floor((hrp.Position - pos).Magnitude + 0.5)
				data.distLabel.Text = dist .. " studs"
			end
		end
	end
end)

-- Scan existing
for _, obj in pairs(Workspace:GetChildren()) do
	task.spawn(function() onSentryAdded(obj) end)
end

-- Watch new
Workspace.ChildAdded:Connect(function(obj)
	task.spawn(function() onSentryAdded(obj) end)
end)

-- Cleanup removed
Workspace.ChildRemoved:Connect(function(obj)
	if sentryESP[obj] then removeSentryESP(obj) end
end)
-- -360 ahhh
    end)
end)

-- ═══ Base Timer ESP ═══
task.spawn(function()
    pcall(function()
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local WHITE = Color3.fromRGB(255, 255, 255)
local GREEN = Color3.fromRGB(85, 255, 85)
local TEXT_SIZE = 28

local ESPElements = {}

local function getTimerLabel(base)
    local purchases = base:FindFirstChild("Purchases")
    if purchases then
        for _, child in ipairs(purchases:GetChildren()) do
            if child.Name:match("PlotBlock") then
                local main = child:FindFirstChild("Main")
                if main then
                    local bb = main:FindFirstChild("BillboardGui")
                    if bb then
                        local t = bb:FindFirstChild("RemainingTime")
                        if t then return t end
                    end
                end
            end
        end
    end
    for _, child in ipairs(base:GetDescendants()) do
        if child:IsA("TextLabel") and child.Name == "RemainingTime" then
            return child
        end
    end
    return nil
end

local function createBaseESP(base)
    if not base:IsA("Model") then return end
    for _, e in ipairs(ESPElements) do if e.base == base then return end end

    local timerLabel = getTimerLabel(base)
    if not timerLabel then return end

    local mainPart = nil
    local friendPanel = base:FindFirstChild("FriendPanel")
    if friendPanel then mainPart = friendPanel:FindFirstChild("Main") end
    if not mainPart then
        for _, desc in ipairs(base:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Name == "Main" then mainPart = desc; break end
        end
    end
    if not mainPart or not mainPart:IsA("BasePart") then return end

    local bb = Instance.new("BillboardGui")
    bb.Name = "F_" .. tostring(math.random(100000,999999))
    bb.Adornee = mainPart
    bb.Size = UDim2.new(0, 220, 0, 55)
    bb.StudsOffset = Vector3.new(0, 5, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = math.huge
    bb.Parent = mainPart

    local textLabel = Instance.new("TextLabel")
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.BackgroundTransparency = 1
    textLabel.Font = Enum.Font.GothamBold
    textLabel.TextSize = TEXT_SIZE
    textLabel.TextColor3 = WHITE
    textLabel.TextStrokeTransparency = 0.3
    textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    textLabel.Text = ""
    textLabel.Parent = bb

    table.insert(ESPElements, {
        base = base, timerLabel = timerLabel,
        textLabel = textLabel, mainPart = mainPart, billboard = bb,
    })
end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
if playerGui:FindFirstChild("ClosestBaseTimerGUI") then playerGui.ClosestBaseTimerGUI:Destroy() end

local timerGui = Instance.new("ScreenGui")
timerGui.Name = "StatusDisplay"
timerGui.ResetOnSpawn = false
timerGui.IgnoreGuiInset = true
timerGui.Parent = playerGui

local timerDisplay = Instance.new("TextLabel")
timerDisplay.Name = "TimerDisplay"
timerDisplay.Size = UDim2.new(0, 280, 0, 40)
timerDisplay.BackgroundTransparency = 1
timerDisplay.Font = Enum.Font.GothamBold
timerDisplay.TextSize = 28
timerDisplay.TextColor3 = WHITE
timerDisplay.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
timerDisplay.TextStrokeTransparency = 0.3
timerDisplay.Text = ""
timerDisplay.AnchorPoint = Vector2.new(0.5, 0)
timerDisplay.Parent = timerGui

local function positionTimerDisplay()
    local screenHeight = Camera.ViewportSize.Y
    local hotbarOffset = 70
    if screenHeight <= 720 then hotbarOffset = 50
    elseif screenHeight >= 1440 then hotbarOffset = 90 end
    timerDisplay.Position = UDim2.new(0.5, 0, 1, -(hotbarOffset + 42))
end
positionTimerDisplay()
Camera:GetPropertyChangedSignal("ViewportSize"):Connect(positionTimerDisplay)

local btFrameCount = 0
RunService.RenderStepped:Connect(function()
    btFrameCount = btFrameCount + 1
    if btFrameCount < 5 then return end
    btFrameCount = 0

    for _, espData in ipairs(ESPElements) do
        if espData.timerLabel and espData.textLabel and espData.mainPart and espData.mainPart.Parent then
            local timerText = espData.timerLabel.Text
            local seconds = tonumber(timerText:match("(%d+)"))
            if (seconds and seconds <= 1) or timerText == "" then
                espData.textLabel.Text = "Unlocked"
                espData.textLabel.TextColor3 = GREEN
            else
                espData.textLabel.Text = timerText
                espData.textLabel.TextColor3 = WHITE
            end
        end
    end

    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then timerDisplay.Text = ""; return end

    local bestDist, bestData = math.huge, nil
    for _, data in ipairs(ESPElements) do
        if data.mainPart and data.mainPart.Parent and data.timerLabel then
            local d = (hrp.Position - data.mainPart.Position).Magnitude
            if d < bestDist then bestDist = d; bestData = data end
        end
    end

    if bestData and bestData.timerLabel then
        local timerText = bestData.timerLabel.Text
        local seconds = tonumber(timerText:match("(%d+)"))
        if (seconds and seconds <= 1) or timerText == "" then
            timerDisplay.Text = "Unlocked"
            timerDisplay.TextColor3 = GREEN
        else
            timerDisplay.Text = timerText
            timerDisplay.TextColor3 = WHITE
        end
    else
        timerDisplay.Text = ""
    end
end)

local function getPlots()
    return Workspace:FindFirstChild("Plots")
end

-- Initial scan
local baseWatchers = {}

local function scanAllBases()
    local p = getPlots()
    if not p then return end
    for _, base in ipairs(p:GetChildren()) do
        pcall(createBaseESP, base)
        if not baseWatchers[base] then
            baseWatchers[base] = true
            pcall(function()
                base.DescendantAdded:Connect(function(desc)
                    if desc.Name == "RemainingTime" or desc.Name == "BillboardGui" or desc.Name == "PlotBlock" then
                        task.wait(0.5)
                        pcall(createBaseESP, base)
                    end
                end)
            end)
        end
    end
end

scanAllBases()

task.spawn(function()
    local p = Workspace:WaitForChild("Plots", 15)
    if not p then return end
    scanAllBases()

    p.ChildAdded:Connect(function(base)
        task.wait(1)
        pcall(createBaseESP, base)
        if not baseWatchers[base] then
            baseWatchers[base] = true
            pcall(function()
                base.DescendantAdded:Connect(function(desc)
                    if desc.Name == "RemainingTime" or desc.Name == "BillboardGui" or desc.Name == "PlotBlock" then
                        task.wait(0.5)
                        pcall(createBaseESP, base)
                    end
                end)
            end)
        end
    end)

    -- Watch all descendants for RemainingTime labels appearing
    p.DescendantAdded:Connect(function(desc)
        if desc.Name == "RemainingTime" then
            task.wait(0.3)
            local ancestor = desc.Parent
            while ancestor and ancestor.Parent ~= p do
                ancestor = ancestor.Parent
            end
            if ancestor then pcall(createBaseESP, ancestor) end
        end
    end)
end)

task.spawn(function()
    while true do
        task.wait(5)
        scanAllBases()
    end
end)

Players.PlayerAdded:Connect(function()
    task.wait(1)
    scanAllBases()
end)

    end)
end)


-- ═══ LASER HITBOX: color laser parts red ═══
task.spawn(function()
    local LASER_COLOR = Color3.fromRGB(220, 60, 60)

    local function styleLaser(desc)
        if not desc:IsA("BasePart") then return end
        local nm = desc.Name:lower()
        if not nm:find("laser") or nm:find("cape") then return end
        desc.Color = LASER_COLOR
        desc.Material = Enum.Material.Neon
        desc.Transparency = 0.15
    end

    local function colorLasers()
        local plots = game.Workspace:FindFirstChild("Plots"); if not plots then return end
        for _, plot in ipairs(plots:GetChildren()) do
            for _, desc in ipairs(plot:GetDescendants()) do
                pcall(styleLaser, desc)
            end
        end
    end

    task.wait(2); colorLasers()

    local plots = game.Workspace:FindFirstChild("Plots")
    if plots then
        plots.DescendantAdded:Connect(function(d)
            task.defer(function() pcall(styleLaser, d) end)
        end)
    end

    while true do task.wait(10); pcall(colorLasers) end
end)



-- ═══ XTC Header ═══
task.spawn(function()
    pcall(function()
        local Players        = game:GetService("Players")
        local RunService     = game:GetService("RunService")
        local TweenService   = game:GetService("TweenService")
        local LocalPlayer    = Players.LocalPlayer
        local playerGui      = LocalPlayer:WaitForChild("PlayerGui")
        local Camera         = game:GetService("Workspace").CurrentCamera

        -- Theme constants (match every other panel in the hub)
        local BG_COLOR     = Color3.fromRGB(8, 10, 18)
        local BORDER_COLOR = Color3.fromRGB(255, 40, 160)
        local BTN_COLOR    = Color3.fromRGB(14, 14, 22)
        local WHITE        = Color3.fromRGB(255, 255, 255)
        local TOGGLE_GREEN = Color3.fromRGB(85, 200, 85)
        local BRICK_RED    = Color3.fromRGB(180, 180, 180)

        -- ── ScreenGui ────────────────────────────────────────────────────────
        local old = playerGui:FindFirstChild("XTCHeader")
            or pcall(function() return game:GetService("CoreGui"):FindFirstChild("XTCHeader") end)
        if old and old.Parent then old:Destroy() end

        local XTCGui = Instance.new("ScreenGui")
        XTCGui.Name            = "XTCHeader"
        XTCGui.ResetOnSpawn    = false
        XTCGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
        XTCGui.IgnoreGuiInset  = true
        XTCGui.DisplayOrder    = 999998
        do
            local _ok = pcall(function() XTCGui.Parent = game:GetService("CoreGui") end)
            if not _ok or not XTCGui.Parent then
                pcall(function() if gethui then XTCGui.Parent = gethui() end end)
            end
            if not XTCGui.Parent then XTCGui.Parent = playerGui end
        end
        if protect_gui then pcall(function() protect_gui(XTCGui) end) end

        -- ── Sizing ───────────────────────────────────────────────────────────
        local H        = 28      -- bar height (matches TopHudFrame)
        local PAD_X    = 14      -- left/right inner padding
        local PAD_Y    = 8       -- pixels from top of viewport
        local ITEM_GAP = 8       -- gap between pills

        -- ── Outer bar frame ──────────────────────────────────────────────────
        local XTCFrame = Instance.new("Frame")
        XTCFrame.Name                 = "XTCFrame"
        XTCFrame.BackgroundColor3     = BG_COLOR
        XTCFrame.BackgroundTransparency = 0.18
        XTCFrame.BorderSizePixel      = 0
        XTCFrame.AnchorPoint          = Vector2.new(0.5, 0)
        XTCFrame.AutomaticSize        = Enum.AutomaticSize.X
        XTCFrame.Size                 = UDim2.new(0, 10, 0, H)
        XTCFrame.Position             = UDim2.new(0.5, 0, 0, PAD_Y)
        XTCFrame.Parent               = XTCGui
        Instance.new("UICorner", XTCFrame).CornerRadius = UDim.new(0, 7)
        local _xStroke = Instance.new("UIStroke", XTCFrame)
        _xStroke.Color = BORDER_COLOR; _xStroke.Thickness = 1

        -- Horizontal list layout (same as TopHudFrame)
        local _xLayout = Instance.new("UIListLayout", XTCFrame)
        _xLayout.FillDirection      = Enum.FillDirection.Horizontal
        _xLayout.VerticalAlignment  = Enum.VerticalAlignment.Center
        _xLayout.SortOrder          = Enum.SortOrder.LayoutOrder
        _xLayout.Padding            = UDim.new(0, ITEM_GAP)

        local _xPad = Instance.new("UIPadding", XTCFrame)
        _xPad.PaddingLeft   = UDim.new(0, PAD_X)
        _xPad.PaddingRight  = UDim.new(0, PAD_X)
        _xPad.PaddingTop    = UDim.new(0, 0)
        _xPad.PaddingBottom = UDim.new(0, 0)

        -- ── Helper: thin divider between sections ────────────────────────────
        local _divOrder = 0
        local function makeDiv(layoutOrder)
            local d = Instance.new("Frame")
            d.BackgroundColor3 = BORDER_COLOR
            d.BackgroundTransparency = 0
            d.BorderSizePixel = 0
            d.Size = UDim2.new(0, 1, 0, 14)
            d.LayoutOrder = layoutOrder
            d.Parent = XTCFrame
        end

        -- ── Helper: branded title pill ("xtc") ──────────────────────────────
        local function makeTitlePill(layoutOrder)
            local pill = Instance.new("Frame")
            pill.BackgroundColor3   = BTN_COLOR
            pill.BackgroundTransparency = 0
            pill.BorderSizePixel    = 0
            pill.AutomaticSize      = Enum.AutomaticSize.X
            pill.Size               = UDim2.new(0, 0, 0, 20)
            pill.LayoutOrder        = layoutOrder
            pill.Parent             = XTCFrame
            Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 5)
            local ps = Instance.new("UIStroke", pill)
            ps.Color = BORDER_COLOR; ps.Thickness = 1

            local pLayout = Instance.new("UIListLayout", pill)
            pLayout.FillDirection     = Enum.FillDirection.Horizontal
            pLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            pLayout.SortOrder         = Enum.SortOrder.LayoutOrder
            pLayout.Padding           = UDim.new(0, 0)

            local pPad = Instance.new("UIPadding", pill)
            pPad.PaddingLeft  = UDim.new(0, 7)
            pPad.PaddingRight = UDim.new(0, 7)

            -- Gradient "xtc" label using RichText colours
            local lbl = Instance.new("TextLabel")
            lbl.BackgroundTransparency = 1
            lbl.AutomaticSize          = Enum.AutomaticSize.X
            lbl.Size                   = UDim2.new(0, 0, 1, 0)
            lbl.RichText               = true
            lbl.Text                   = '<font color="#FF4FC8">x</font><font color="#CC44FF">t</font><font color="#6644FF">c</font>'
            lbl.Font                   = Enum.Font.GothamBold
            lbl.TextSize               = 13
            lbl.LayoutOrder            = 1
            lbl.Parent                 = pill
            return pill, lbl
        end

        -- ── Helper: stat pill (matches TopHudFrame makeHudStat) ──────────────
        local function makeStatPill(labelText, layoutOrder)
            local pill = Instance.new("Frame")
            pill.BackgroundColor3   = BTN_COLOR
            pill.BackgroundTransparency = 0
            pill.BorderSizePixel    = 0
            pill.AutomaticSize      = Enum.AutomaticSize.X
            pill.Size               = UDim2.new(0, 0, 0, 20)
            pill.LayoutOrder        = layoutOrder
            pill.Parent             = XTCFrame
            Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 5)
            local ps = Instance.new("UIStroke", pill)
            ps.Color = BORDER_COLOR; ps.Thickness = 1

            local pLayout = Instance.new("UIListLayout", pill)
            pLayout.FillDirection     = Enum.FillDirection.Horizontal
            pLayout.VerticalAlignment = Enum.VerticalAlignment.Center
            pLayout.SortOrder         = Enum.SortOrder.LayoutOrder
            pLayout.Padding           = UDim.new(0, 3)

            local pPad = Instance.new("UIPadding", pill)
            pPad.PaddingLeft  = UDim.new(0, 7)
            pPad.PaddingRight = UDim.new(0, 7)

            local keyLbl = Instance.new("TextLabel")
            keyLbl.BackgroundTransparency = 1
            keyLbl.AutomaticSize          = Enum.AutomaticSize.X
            keyLbl.Size                   = UDim2.new(0, 0, 1, 0)
            keyLbl.Text                   = labelText
            keyLbl.TextColor3             = Color3.fromRGB(160, 160, 160)
            keyLbl.Font                   = Enum.Font.GothamBold
            keyLbl.TextSize               = 11
            keyLbl.LayoutOrder            = 1
            keyLbl.Parent                 = pill

            local valLbl = Instance.new("TextLabel")
            valLbl.BackgroundTransparency = 1
            valLbl.AutomaticSize          = Enum.AutomaticSize.X
            valLbl.Size                   = UDim2.new(0, 0, 1, 0)
            valLbl.Text                   = "--"
            valLbl.TextColor3             = WHITE
            valLbl.Font                   = Enum.Font.GothamBold
            valLbl.TextSize               = 11
            valLbl.LayoutOrder            = 2
            valLbl.Parent                 = pill
            return valLbl
        end

        -- ── Build the bar ─────────────────────────────────────────────────────
        --  [ xtc ] | [ AUTO STEAL: ON/OFF ] | [ ESP: ON/OFF ]
        local _titlePill, _titleLbl = makeTitlePill(1)
        makeDiv(2)
        local AutoStealVal = makeStatPill("AUTO STEAL", 3)
        makeDiv(4)
        local EspVal       = makeStatPill("ESP",        5)
        makeDiv(6)
        local TpVal        = makeStatPill("AUTO TP",    7)

        -- ── Live status update loop ───────────────────────────────────────────
        -- Reads the same _G flags that the main hub toggles use, so the header
        -- always reflects the true current state of each feature.
        task.spawn(function()
            local function boolState(v)
                if v then
                    return "ON", TOGGLE_GREEN
                else
                    return "OFF", BRICK_RED
                end
            end

            while XTCFrame and XTCFrame.Parent do
                pcall(function()
                    -- Auto Steal: reflects whether the engine is enabled
                    local stealOn = (_G._autoStealSettingOn == true)
                    local stealTxt, stealCol = boolState(stealOn)
                    AutoStealVal.Text = stealTxt
                    AutoStealVal.TextColor3 = stealCol

                    -- ESP (uses the hub's unified toggle flag)
                    local espOn = (_G._playerEspEnabled == true)
                    local espTxt, espCol = boolState(espOn)
                    EspVal.Text = espTxt
                    EspVal.TextColor3 = espCol

                    -- Auto TP
                    local tpOn = (_G._autoTPEnabled == true or _G.autoTPEnabled == true)
                    local tpTxt, tpCol = boolState(tpOn)
                    TpVal.Text = tpTxt
                    TpVal.TextColor3 = tpCol
                end)
                task.wait(0.25)
            end
        end)

        -- ── Re-anchor if viewport resizes ────────────────────────────────────
        -- (position is already relative 0.5 so nothing extra needed for X,
        --  but we keep the Y pinned in case IgnoreGuiInset shifts things)
        Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
            if XTCFrame and XTCFrame.Parent then
                XTCFrame.Position = UDim2.new(0.5, 0, 0, PAD_Y)
            end
        end)
    end)
end)


-- ═══ Admin Panel (Player List) ═══
task.spawn(function()
    pcall(function()

repeat task.wait() until game:IsLoaded()
task.wait(1.5)

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local LocalPlayer       = Players.LocalPlayer
local PlayerGui         = LocalPlayer:WaitForChild("PlayerGui")

-- ── Hub theme colors (matches the rest of the hub) ───────────────────────────
local BG_COLOR     = Color3.fromRGB(10, 12, 20)
local BTN_COLOR    = Color3.fromRGB(14, 14, 22)
local ROW_COLOR    = Color3.fromRGB(10, 12, 20)
-- PATCH: lire le BORDER_COLOR global pour le theme (defini plus haut dans le hub)
local BORDER_COLOR = (typeof(BORDER_COLOR) == "Color3" and BORDER_COLOR) or (_G._hubThemeColor or Color3.fromRGB(255, 40, 160))
local WHITE        = Color3.fromRGB(255, 255, 255)
local BRICK_RED    = Color3.fromRGB(180, 180, 180)
local DIM_TEXT     = Color3.fromRGB(180, 180, 180)

-- ── Admin command cooldown table (shared with Click AP, _G.ClickAP_*) ────────
local Cooldowns = _G.ClickAP_Cooldowns
local LastUse   = _G.ClickAP_LastUse
if not Cooldowns or not LastUse then
    Cooldowns, LastUse = {}, {}
    local ok, AdminCmdsData = pcall(function()
        return require(ReplicatedStorage:WaitForChild("Datas"):WaitForChild("AdminCommands"))
    end)
    if ok and type(AdminCmdsData) == "table" then
        for name, info in pairs(AdminCmdsData) do
            if name ~= "control" then Cooldowns[name] = info.cooldown end
        end
    end
    _G.ClickAP_Cooldowns = Cooldowns
    _G.ClickAP_LastUse   = LastUse
end

local function isOnCooldown(cmd)
    return LastUse[cmd] and (tick() - LastUse[cmd]) < (Cooldowns[cmd] or 0)
end

-- Wait for the Click AP module's admin-firing helper (real AdminPanel clicker)
local function fireAdmin(targetPlayer, cmd)
    local f = _G._fireAdmin
    if not f then
        local t0 = os.clock()
        while not _G._fireAdmin and os.clock() - t0 < 5 do task.wait(0.1) end
        f = _G._fireAdmin
    end
    if not f then return false end
    local ok = f(targetPlayer, cmd)
    if ok then LastUse[cmd] = tick() end
    return ok
end

-- ── Blacklist (persisted) ─────────────────────────────────────────────────────
local BL_FILE = "admin_panel_blacklist.json"
local Blacklist = {}
local function loadBlacklist()
    if not readfile then return end
    pcall(function()
        local raw = readfile(BL_FILE)
        if raw and #raw > 1 then
            local d = HttpService:JSONDecode(raw)
            if type(d) == "table" then
                for _, n in ipairs(d) do Blacklist[n] = true end
            end
        end
    end)
end
local function saveBlacklist()
    if not writefile then return end
    pcall(function()
        local list = {}
        for n in pairs(Blacklist) do list[#list + 1] = n end
        writefile(BL_FILE, HttpService:JSONEncode(list))
    end)
end
loadBlacklist()
local function isBlacklisted(name) return Blacklist[name] == true end

-- ── GUI shell ──────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name = "HubAdminPanel"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local guiOk = pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not guiOk or not gui.Parent then
    pcall(function() if gethui then gui.Parent = gethui() end end)
end
if not gui.Parent then gui.Parent = PlayerGui end
-- Exposer une fonction de recoloriage
_G._adminPanelStrokes = {}  -- sera rempli au fur et a mesure
_G._recolorAdminPanel = function(color)
    for _, ref in ipairs(_G._adminPanelStrokes) do
        pcall(function()
            if ref.obj and ref.obj.Parent then
                ref.obj[ref.prop] = color
            end
        end)
    end
end
-- NOTE: protect_gui applique APRES la creation de tous les objets (voir bas du fichier)
_G.UIHide_AdminPanel = gui

local PANEL_W  = 500
local HEADER_H = 50
local ROW_H    = 62
local ROW_GAP  = 5
local LIST_H   = 450

local frame = Instance.new("Frame")
frame.Name = "AdminPanelFrame"
frame.Size = UDim2.new(0, PANEL_W, 0, HEADER_H + LIST_H + 12)
frame.Position = UDim2.new(1, -PANEL_W - 5, 0.5, -((HEADER_H + LIST_H + 12) / 2))
frame.BackgroundColor3 = Color3.fromRGB(10, 12, 24)
frame.BackgroundTransparency = 0.75
frame.BorderSizePixel = 0
frame.Active = true
frame.ZIndex = 50
frame.Parent = gui
if not _G._hubPanelFrames then _G._hubPanelFrames={} end; table.insert(_G._hubPanelFrames, frame)
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
local frameStroke = Instance.new("UIStroke", frame)
frameStroke.Color = (_G._hubThemeColor or Color3.fromRGB(255, 40, 160)); frameStroke.Thickness = 1.5
table.insert(_G._adminPanelStrokes, {obj=frameStroke, prop="Color"})
do
    local _sdAPF={{0.03,0.1,3,0.004},{0.08,0.45,2,0.005},{0.14,0.75,3,0.004},{0.2,0.25,2,0.006},{0.26,0.88,3,0.005},{0.32,0.15,2,0.004},{0.38,0.55,3,0.005},{0.44,0.82,2,0.004},{0.5,0.35,3,0.006},{0.56,0.65,2,0.005},{0.62,0.18,3,0.004},{0.68,0.78,2,0.005},{0.74,0.42,3,0.004},{0.8,0.9,2,0.006},{0.86,0.28,3,0.005},{0.92,0.6,2,0.004},{0.97,0.12,3,0.005},{0.1,0.92,2,0.004},{0.22,0.5,3,0.006},{0.35,0.72,2,0.005},{0.47,0.08,3,0.004},{0.59,0.48,2,0.005},{0.71,0.85,3,0.004},{0.83,0.32,2,0.006},{0.95,0.68,3,0.005},{0.16,0.38,2,0.004},{0.42,0.95,3,0.005},{0.65,0.22,2,0.004},{0.78,0.58,3,0.006},{0.9,0.82,2,0.005}}
    local _sfAPF,_soAPF={},{}
    for i,sp in ipairs(_sdAPF) do
        local s=Instance.new("Frame",frame)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.3
        s.BorderSizePixel=0;s.ZIndex=10
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfAPF[i]=s;_soAPF[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfAPF) do
            if not s or not s.Parent then continue end
            _soAPF[i]=(_soAPF[i]-_sdAPF[i][4]*dt)%1
            s.Position=UDim2.new(_soAPF[i],0,_sdAPF[i][2],0)
            s.BackgroundTransparency=0.3+math.abs(math.sin(tick()*0.8+i*0.7))*0.55
        end
    end)
end

-- ── Header ───────────────────────────────────────────────────────────────────
local header = Instance.new("Frame", frame)
header.Size = UDim2.new(1, 0, 0, HEADER_H)
header.Position = UDim2.new(0, 0, 0, 0)
header.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
header.BackgroundTransparency = 0
header.BorderSizePixel = 0
header.ZIndex = 51
local _hdrCorner = Instance.new("UICorner", header)
_hdrCorner.CornerRadius = UDim.new(0, 14)
local _hdrFill = Instance.new("Frame", header)
_hdrFill.Size = UDim2.new(1, 0, 0, 14)
_hdrFill.Position = UDim2.new(0, 0, 1, -14)
_hdrFill.BackgroundColor3 = Color3.fromRGB(14, 16, 30)
_hdrFill.BorderSizePixel = 0; _hdrFill.ZIndex = 51
local title = Instance.new("TextLabel", header)
title.Size = UDim2.new(1, 0, 0, 24)
title.Position = UDim2.new(0, 0, 0, 5)
title.BackgroundTransparency = 1
title.Text = "IDF HUB"
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextTransparency = 0
title.TextXAlignment = Enum.TextXAlignment.Center
title.ZIndex = 52
local apSubTitle = Instance.new("TextLabel", header)
apSubTitle.Size = UDim2.new(1, 0, 0, 14)
apSubTitle.Position = UDim2.new(0, 0, 0, 29)
apSubTitle.BackgroundTransparency = 1
apSubTitle.Text = "Admin Panel"
apSubTitle.Font = Enum.Font.Gotham
apSubTitle.TextSize = 11
apSubTitle.TextColor3 = Color3.fromRGB(160, 160, 200)
apSubTitle.TextTransparency = 0
apSubTitle.TextXAlignment = Enum.TextXAlignment.Center
apSubTitle.ZIndex = 52
local _apSepLine = Instance.new("Frame", header)
_apSepLine.Size = UDim2.new(1,-24,0,1); _apSepLine.Position = UDim2.new(0,12,1,-1)
_apSepLine.BackgroundColor3 = Color3.fromRGB(60,60,100); _apSepLine.BackgroundTransparency = 0
_apSepLine.BorderSizePixel = 0; _apSepLine.ZIndex = 53

local refreshBtn = Instance.new("TextButton", header)
refreshBtn.Size = UDim2.new(0, 70, 0, 20)
refreshBtn.Position = UDim2.new(1, -78, 0.5, -10)
refreshBtn.BackgroundColor3 = Color3.fromRGB(0,0,0)
refreshBtn.BackgroundTransparency = 1
refreshBtn.BorderSizePixel = 0
refreshBtn.Text = ""
refreshBtn.Visible = false
refreshBtn.Font = Enum.Font.GothamBold
refreshBtn.TextSize = 10
refreshBtn.TextColor3 = WHITE
refreshBtn.AutoButtonColor = false
refreshBtn.ZIndex = 52
Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 5)
local refreshStroke = Instance.new("UIStroke", refreshBtn)
refreshStroke.Color = BORDER_COLOR; refreshStroke.Thickness = 1
table.insert(_G._adminPanelStrokes, {obj=refreshStroke, prop="Color"})


do
    local _sdAP={{0.862,0.477,2,0.0074},{0.29,0.463,1,0.0051},{0.487,0.129,1,0.0051},{0.649,0.187,1,0.0104},{0.762,0.232,2,0.0073},{0.855,0.526,2,0.0066},{0.809,0.442,2,0.0073},{0.875,0.169,3,0.0076},{0.889,0.721,2,0.011},{0.97,0.482,3,0.0082},{0.532,0.875,2,0.008},{0.732,0.549,2,0.0124}}
    local _sfAP,_soAP={},{}
    for i,sp in ipairs(_sdAP) do
        local s=Instance.new("Frame",header)
        s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
        s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.3
        s.BorderSizePixel=0;s.ZIndex=52
        Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
        _sfAP[i]=s;_soAP[i]=sp[1]
        if not _G._hubStars then _G._hubStars={} end
        table.insert(_G._hubStars, s)
    end
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        for i,s in ipairs(_sfAP) do
            if not s or not s.Parent then continue end
            _soAP[i]=(_soAP[i]-_sdAP[i][4]*dt)%1
            s.Position=UDim2.new(_soAP[i],0,_sdAP[i][2],0)
            s.BackgroundTransparency=0.1+math.abs(math.sin(tick()*1.2+i))*0.7
        end
    end)
end
makeDraggable(frame, "AdminPanelGui", header)
_G._adminPanelFrame = frame

-- ── Player list ────────────────────────────────────────────────────────────────
local list = Instance.new("ScrollingFrame", frame)
list.Size = UDim2.new(1, -10, 1, -(HEADER_H + 14))
list.Position = UDim2.new(0, 5, 0, HEADER_H + 14)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.ScrollBarImageColor3 = BORDER_COLOR
table.insert(_G._adminPanelStrokes, {obj=list, prop="ScrollBarImageColor3"})
list.CanvasSize = UDim2.new(0, 0, 0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.ZIndex = 51
local listLayout = Instance.new("UIListLayout", list)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, ROW_GAP)
local listPad = Instance.new("UIPadding", list)
listPad.PaddingTop = UDim.new(0, 3)
listPad.PaddingBottom = UDim.new(0, 3)
listPad.PaddingLeft = UDim.new(0, 3)
listPad.PaddingRight = UDim.new(0, 3)

local BTN_DEFS = {
    {icon = "JAI", cmd = "jail",    color = Color3.fromRGB(200, 100, 30)},
    {icon = "RAG", cmd = "ragdoll", color = Color3.fromRGB(180, 50,  50)},
    {icon = "RKT", cmd = "rocket",  color = Color3.fromRGB(40,  140, 180)},
    {icon = "BUI", cmd = "balloon", color = Color3.fromRGB(40,  180, 80)},
}

local rows = {} -- [Player] = { frame, buttons, refreshBl }

local ICON_W   = 52   -- pill width
local ICON_H   = 24   -- pill height
local ICON_SZ  = 24   -- X button size
local ICON_GAP = 5
local AVA_SZ   = 44
local ROW_W    = PANEL_W - 22

local BTN_ICONS = {
    {icon = "🔒", cmd = "jail",    color = Color3.fromRGB(200, 100, 30)},
    {icon = "💀", cmd = "ragdoll", color = Color3.fromRGB(180, 50,  50)},
    {icon = "🚀", cmd = "rocket",  color = Color3.fromRGB(40,  140, 180)},
    {icon = "🎈", cmd = "balloon", color = Color3.fromRGB(40,  180, 80)},
}

local _apTS = game:GetService("TweenService")
local function buildRow(plr)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, -8, 0, ROW_H)
    row.BackgroundColor3 = Color3.fromRGB(20, 22, 40)
    row.BackgroundTransparency = 0.75
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.ZIndex = 51
    row.Parent = list
    row.MouseButton1Click:Connect(function()
        if isBlacklisted(plr.Name) then return end
        task.spawn(function()
            local delayT = 0
            for cmd in pairs(Cooldowns) do
                if not isOnCooldown(cmd) then
                    task.delay(delayT, function() fireAdmin(plr, cmd) end)
                    delayT = delayT + 0.1
                end
            end
        end)
    end)
    row.MouseEnter:Connect(function()
        if not isBlacklisted(plr.Name) then
            _apTS:Create(row, TweenInfo.new(0.12), {BackgroundTransparency = 0.4}):Play()
        end
    end)
    row.MouseLeave:Connect(function()
        _apTS:Create(row, TweenInfo.new(0.12), {BackgroundTransparency = isBlacklisted(plr.Name) and 0.55 or 0.75}):Play()
    end)
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 10)
    local rowS = Instance.new("UIStroke", row)
    rowS.Color = (_G._hubThemeColor or Color3.fromRGB(255, 40, 160)); rowS.Thickness = 1
    table.insert(_G._adminPanelStrokes, {obj=rowS, prop="Color"})
    rowS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    rowS.Transparency = 0.6

    -- Left accent bar
    local accent = Instance.new("Frame", row)
    accent.Size = UDim2.new(0, 3, 1, -14)
    accent.Position = UDim2.new(0, 0, 0, 7)
    accent.BackgroundColor3 = (_G._hubThemeColor or Color3.fromRGB(255, 40, 160))
    accent.BorderSizePixel = 0
    accent.ZIndex = 53
    Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)
    table.insert(_G._adminPanelStrokes, {obj=accent, prop="BackgroundColor3"})

    -- Avatar (circular)
    local ava = Instance.new("ImageLabel", row)
    ava.Size = UDim2.new(0, AVA_SZ, 0, AVA_SZ)
    ava.Position = UDim2.new(0, 10, 0.5, -AVA_SZ/2)
    ava.BackgroundColor3 = Color3.fromRGB(14, 14, 28)
    ava.BorderSizePixel = 0
    ava.ZIndex = 52
    ava.Image = ""
    Instance.new("UICorner", ava).CornerRadius = UDim.new(1, 0)
    local avaS = Instance.new("UIStroke", ava)
    avaS.Color = (_G._hubThemeColor or Color3.fromRGB(255, 40, 160)); avaS.Thickness = 2.5
    table.insert(_G._adminPanelStrokes, {obj=avaS, prop="Color"})
    task.spawn(function()
        local ok, img = pcall(function()
            return game:GetService("Players"):GetUserThumbnailAsync(plr.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
        end)
        if ok and ava and ava.Parent then ava.Image = img end
    end)

    -- Name + @username
    local nameX = AVA_SZ + 18
    local allBtnsW = #BTN_ICONS * ICON_W + (#BTN_ICONS - 1) * ICON_GAP + ICON_GAP + ICON_SZ
    local btnsX = ROW_W - allBtnsW - 10
    local nameW = btnsX - nameX - 8

    local nameLbl = Instance.new("TextLabel", row)
    nameLbl.Size = UDim2.new(0, nameW, 0, 17)
    nameLbl.Position = UDim2.new(0, nameX, 0, 8)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = plr.Name
    nameLbl.TextColor3 = WHITE
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextSize = 12
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.ZIndex = 52

    local userLbl = Instance.new("TextLabel", row)
    userLbl.Size = UDim2.new(0, nameW, 0, 13)
    userLbl.Position = UDim2.new(0, nameX, 0, 26)
    userLbl.BackgroundTransparency = 1
    userLbl.Text = "@" .. plr.Name
    userLbl.TextColor3 = Color3.fromRGB(130, 130, 165)
    userLbl.Font = Enum.Font.Gotham
    userLbl.TextSize = 10
    userLbl.TextXAlignment = Enum.TextXAlignment.Left
    userLbl.TextTruncate = Enum.TextTruncate.AtEnd
    userLbl.ZIndex = 52

    local brainrotLbl = Instance.new("TextLabel", row)
    brainrotLbl.Size = UDim2.new(0, nameW, 0, 13)
    brainrotLbl.Position = UDim2.new(0, nameX, 0, 42)
    brainrotLbl.BackgroundTransparency = 1
    brainrotLbl.Text = ""
    brainrotLbl.TextColor3 = Color3.fromRGB(80, 220, 120)
    brainrotLbl.Font = Enum.Font.GothamBold
    brainrotLbl.TextSize = 10
    brainrotLbl.TextXAlignment = Enum.TextXAlignment.Left
    brainrotLbl.TextTruncate = Enum.TextTruncate.AtEnd
    brainrotLbl.ZIndex = 52

    -- Command pill buttons (right side)
    local buttons = {}
    local _dimC = function(c) return Color3.fromRGB(math.floor(c.R*255*0.2), math.floor(c.G*255*0.2), math.floor(c.B*255*0.2)) end

    for i, def in ipairs(BTN_ICONS) do
        local b = Instance.new("TextButton", row)
        b.Size = UDim2.new(0, ICON_W, 0, ICON_H)
        b.Position = UDim2.new(0, btnsX + (i-1)*(ICON_W+ICON_GAP), 0.5, -ICON_H/2)
        b.BackgroundColor3 = _dimC(def.color)
        b.BackgroundTransparency = 1
        b.BorderSizePixel = 0
        b.Text = def.icon
        b.Font = Enum.Font.GothamBold
        b.TextSize = 18
        b.TextColor3 = WHITE
        b.AutoButtonColor = false
        b.ZIndex = 53
        Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
        local bs = Instance.new("UIStroke", b)
        bs.Color = def.color; bs.Thickness = 1.5; bs.Transparency = 0.2
        b.MouseEnter:Connect(function() b.BackgroundColor3 = def.color; b.BackgroundTransparency = 0.5 end)
        b.MouseLeave:Connect(function() b.BackgroundTransparency = 1 end)
        b.MouseButton1Click:Connect(function()
            if isBlacklisted(plr.Name) then return end
            fireAdmin(plr, def.cmd)
        end)
        buttons[def.cmd] = b
    end

    -- Blacklist button (pill, red)
    local blBtn = Instance.new("TextButton", row)
    blBtn.Size = UDim2.new(0, ICON_SZ, 0, ICON_H)
    blBtn.Position = UDim2.new(0, btnsX + #BTN_ICONS*(ICON_W+ICON_GAP), 0.5, -ICON_H/2)
    blBtn.BorderSizePixel = 0
    blBtn.Text = "❌"
    blBtn.Font = Enum.Font.GothamBold
    blBtn.TextSize = 14
    blBtn.AutoButtonColor = false
    blBtn.ZIndex = 53
    Instance.new("UICorner", blBtn).CornerRadius = UDim.new(1, 0)

    local function refreshBl()
        local bl = isBlacklisted(plr.Name)
        blBtn.BackgroundColor3 = bl and Color3.fromRGB(160, 30, 30) or Color3.fromRGB(38, 14, 14)
        blBtn.BackgroundTransparency = bl and 0.5 or 1
        blBtn.TextColor3       = bl and WHITE or Color3.fromRGB(220, 60, 60)
        local blS = blBtn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", blBtn)
        blS.Color = Color3.fromRGB(200, 50, 50); blS.Thickness = 1.5
        row.BackgroundTransparency = bl and 0.55 or 0.75
        nameLbl.TextColor3 = bl and Color3.fromRGB(90, 90, 110) or WHITE
        userLbl.TextColor3 = bl and Color3.fromRGB(70, 70, 90) or Color3.fromRGB(130, 130, 165)
        for _, b in pairs(buttons) do b.Active = not bl end
        accent.BackgroundTransparency = bl and 0.6 or 0
    end
    refreshBl()
    blBtn.MouseButton1Click:Connect(function()
        if isBlacklisted(plr.Name) then Blacklist[plr.Name] = nil else Blacklist[plr.Name] = true end
        saveBlacklist(); refreshBl()
    end)

    return { frame = row, buttons = buttons, refreshBl = refreshBl, brainrotLbl = brainrotLbl }
end

local function addPlayer(plr)
    if plr == LocalPlayer or rows[plr] then return end
    rows[plr] = buildRow(plr)
end
local function removePlayer(plr)
    local r = rows[plr]
    if r then pcall(function() r.frame:Destroy() end); rows[plr] = nil end
end

for _, plr in ipairs(Players:GetPlayers()) do addPlayer(plr) end
Players.PlayerAdded:Connect(addPlayer)
Players.PlayerRemoving:Connect(removePlayer)

local function doRefreshAdminPanel()
    for _, r in pairs(rows) do pcall(function() r.frame:Destroy() end) end
    rows = {}
    -- Reinit les references de strokes
    _G._adminPanelStrokes = {}
    -- Re-enregistrer les strokes statiques
    table.insert(_G._adminPanelStrokes, {obj=frameStroke, prop="Color"})
    table.insert(_G._adminPanelStrokes, {obj=hdrStroke,   prop="Color"})
    table.insert(_G._adminPanelStrokes, {obj=refreshStroke, prop="Color"})
    for _, plr in ipairs(Players:GetPlayers()) do addPlayer(plr) end
    -- Appliquer le theme courant apres rebuild
    if _G._hubThemeColor and _G._recolorAdminPanel then
        task.defer(function() pcall(function() _G._recolorAdminPanel(_G._hubThemeColor) end) end)
    end
end
_G._refreshAdminPanel = doRefreshAdminPanel
refreshBtn.MouseButton1Click:Connect(doRefreshAdminPanel)
-- PATCH: appliquer protect_gui ici, apres que tous les objets sont crees
if protect_gui then pcall(function() protect_gui(gui) end) end

-- ── Cooldown visual loop ──────────────────────────────────────────────────────
task.spawn(function()
    while gui and gui.Parent do
        local cache = _G._stealAnimalsCache or {}
        local bestOwner = cache[1] and cache[1].owner or nil
        for plr, r in pairs(rows) do
            for cmd, b in pairs(r.buttons) do
                if isOnCooldown(cmd) then
                    b.BackgroundColor3 = BRICK_RED
                else
                    for _, def in ipairs(BTN_ICONS) do
                        if def.cmd == cmd then b.BackgroundColor3 = def.color; break end
                    end
                end
            end
            if r.brainrotLbl then
                -- Verifier si ce joueur est en train de steal
                local stealText = ""
                local stealColor = Color3.fromRGB(160, 80, 255)
                pcall(function()
                    if plr:GetAttribute("Stealing") then
                        -- Trouver quel plot le joueur est sur (par proximite)
                        local plrChar = plr.Character
                        local plrHrp  = plrChar and plrChar:FindFirstChild("HumanoidRootPart")
                        local bestName = nil
                        if plrHrp then
                            -- Chercher le plot le plus proche
                            local plots = game:GetService("Workspace"):FindFirstChild("Plots")
                            local closestPlot = nil
                            local closestDist = math.huge
                            if plots then
                                for _, plot in ipairs(plots:GetChildren()) do
                                    local base = plot:FindFirstChild("Base") or plot:FindFirstChildWhichIsA("BasePart")
                                    if base then
                                        local d = (plrHrp.Position - base.Position).Magnitude
                                        if d < closestDist then
                                            closestDist = d
                                            closestPlot = plot
                                        end
                                    end
                                end
                            end
                            -- Chercher le brainrot de ce plot dans le cache
                            if closestPlot then
                                local cache = _G._stealAnimalsCache or {}
                                local bestMPS = -math.huge
                                for _, pet in ipairs(cache) do
                                    if pet.plot == closestPlot.Name and (pet.genValue or 0) > bestMPS then
                                        bestMPS  = pet.genValue or 0
                                        bestName = pet.name
                                    end
                                end
                            end
                        end
                        if bestName then
                            stealText  = "STEAL: " .. bestName
                        else
                            stealText  = "STEALER"
                        end
                        stealColor = Color3.fromRGB(255, 80, 80)
                    elseif bestOwner and plr.Name == bestOwner then
                        stealText  = "owner"
                        stealColor = Color3.fromRGB(160, 80, 255)
                    end
                end)
                r.brainrotLbl.Text      = stealText
                r.brainrotLbl.TextColor3 = stealColor
            end
        end
        task.wait(0.2)
    end
end)

    end)
end)

print("discord.gg/twayvehub")
-- ═══════════════════════════════════════════════════════════════
-- ═══ ADMIN CONTROL GUI (intégré depuis HauntedWithYou) ════════
-- ═══════════════════════════════════════════════════════════════
task.spawn(function()
    local Players          = game:GetService("Players")
    local RunService       = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local TweenService     = game:GetService("TweenService")
    local Workspace        = game:GetService("Workspace")
    local ReplicatedStorage= game:GetService("ReplicatedStorage")
    local HttpService      = game:GetService("HttpService")
    local LocalPlayer      = Players.LocalPlayer
    local PlayerGui        = LocalPlayer:WaitForChild("PlayerGui")
    local Heartbeat        = RunService.Heartbeat

    local _UI_POS_FILE = "arabic_hub_ui_pos.json"
    local function _loadUIPos()
        local ok, raw = pcall(readfile, _UI_POS_FILE)
        if ok and raw and raw ~= "" then
            local ok2, data = pcall(function() return HttpService:JSONDecode(raw) end)
            if ok2 and type(data) == "table" then return data end
        end
        return {}
    end
    local function _saveUIPos(positions)
        pcall(function() writefile(_UI_POS_FILE, HttpService:JSONEncode(positions)) end)
    end
    local _savedUIPos = _loadUIPos()

    local MOBILE_SCALE = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled) and 0.75 or 1

    local Theme = {
        Background       = Color3.fromRGB(8, 10, 18),
        Surface          = Color3.fromRGB(14, 14, 22),
        SurfaceHighlight = Color3.fromRGB(10, 12, 20),
        Accent1          = Color3.fromRGB(85, 200, 85),
        Accent2          = Color3.fromRGB(85, 200, 85),
        TextPrimary      = Color3.fromRGB(255, 255, 255),
        Success          = Color3.fromRGB(85, 200, 85),
    }

    local Config = {
        ProximityRange = _G.AdminCP_ProxRange or 15,
        ClickToAP      = _G.AdminCP_ClickToAP or false,
        UILocked       = false,
        Positions      = { AdminControl = _savedUIPos.AdminControl or _G.AdminCP_Position },
    }
    local function SaveConfig()
        _G.AdminCP_ProxRange = Config.ProximityRange
        _G.AdminCP_ClickToAP = Config.ClickToAP
        _G.AdminCP_Position  = Config.Positions.AdminControl
        _saveUIPos(Config.Positions)
    end

    -- ─── addNeonBorder ───────────────────────────────────────
    local function addNeonBorder(frame)
        local border = Instance.new("UIStroke", frame)
        border.Thickness = 1.5
        border.Transparency = 0.25
        border.Color = Color3.fromRGB(255, 40, 160)
    end

    -- ─── MakeDraggable ───────────────────────────────────────
    local function MakeDraggable(dragBar, targetFrame, posKey)
        local dragging = false
        local dragStart, startPos
        local dragConn, endConn
        local saved = Config.Positions[posKey]
        if saved then
            targetFrame.Position = UDim2.new(0, saved.x or 0, 0, saved.y or 0)
            targetFrame.AnchorPoint = Vector2.new(0, 0)
        end
        dragBar.InputBegan:Connect(function(input)
            if Config.UILocked then return end
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
            dragging = true
            dragStart = input.Position
            startPos  = targetFrame.Position
            dragConn = UserInputService.InputChanged:Connect(function(inp)
                if not dragging then return end
                if inp.UserInputType ~= Enum.UserInputType.MouseMovement
                and inp.UserInputType ~= Enum.UserInputType.Touch then return end
                local delta = inp.Position - dragStart
                targetFrame.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end)
            endConn = UserInputService.InputEnded:Connect(function(inp)
                if inp.UserInputType ~= Enum.UserInputType.MouseButton1
                and inp.UserInputType ~= Enum.UserInputType.Touch then return end
                if dragging then
                    dragging = false
                    if dragConn then dragConn:Disconnect(); dragConn = nil end
                    if endConn  then endConn:Disconnect();  endConn  = nil end
                    local abs = targetFrame.AbsolutePosition
                    Config.Positions[posKey] = {x = math.floor(abs.X), y = math.floor(abs.Y)}
                    SaveConfig()
                end
            end)
        end)
    end

    -- ════════════════════════════════════════════════════════
    -- ═══ ADMIN CONTROL GUI ══════════════════════════════════
    -- ════════════════════════════════════════════════════════
    local ProximityAPActive = false
    local PROXIMITY_RANGE   = Config.ProximityRange or 15
    local PROX_COMMANDS     = {"balloon","inverse","jail","jumpscare","morph","nightvision","ragdoll","rocket","tiny"}
    local proxCmdIndex      = 1
    local proxCmdBag        = {}
    local function pickRandomCmd()
        if #proxCmdBag == 0 then
            for _, cmd in ipairs(PROX_COMMANDS) do table.insert(proxCmdBag, cmd) end
        end
        local i = math.random(#proxCmdBag)
        local cmd = proxCmdBag[i]
        table.remove(proxCmdBag, i)
        return cmd
    end

    local proxViz = nil
    local function updateProxRing()
        if ProximityAPActive then
            if not proxViz or not proxViz.Parent then
                proxViz = Instance.new("Part")
                proxViz.Name        = "HubAdminProxRing"
                proxViz.Anchored    = true
                proxViz.CanCollide  = false
                proxViz.Shape       = Enum.PartType.Cylinder
                proxViz.Color       = Color3.fromRGB(85, 200, 85)
                proxViz.Transparency= 0.65
                proxViz.CastShadow  = false
                proxViz.Material    = Enum.Material.Neon
                proxViz.Parent      = Workspace
                local glowRing = Instance.new("Part")
                glowRing.Name        = "HubAdminProxRingGlow"
                glowRing.Anchored    = true
                glowRing.CanCollide  = false
                glowRing.Shape       = Enum.PartType.Cylinder
                glowRing.Color       = Color3.fromRGB(120, 240, 120)
                glowRing.Transparency= 0.8
                glowRing.CastShadow  = false
                glowRing.Material    = Enum.Material.Neon
                glowRing.Parent      = proxViz
            end
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local hrp     = char.HumanoidRootPart
                local diameter= PROXIMITY_RANGE * 2
                proxViz.Size  = Vector3.new(0.1, diameter, diameter)
                proxViz.CFrame= (hrp.CFrame * CFrame.new(0,-3.2,0)) * CFrame.Angles(0,0,math.rad(90))
                proxViz.Transparency = 0.55
                local glow = proxViz:FindFirstChild("HubAdminProxRingGlow")
                if glow then
                    glow.Size   = Vector3.new(0.05, diameter+0.8, diameter+0.8)
                    glow.CFrame = proxViz.CFrame
                    glow.Transparency = 0.75
                end
                local pulse = (math.sin(tick()*4)+1)/2
                local c1 = Color3.fromRGB(60,180,60); local c2 = Color3.fromRGB(120,240,120)
                proxViz.Color = c1:Lerp(c2, pulse)
                if glow then glow.Color = c2:Lerp(c1, pulse) end
            end
        else
            if proxViz and proxViz.Parent then proxViz:Destroy(); proxViz = nil end
        end
    end

    RunService.RenderStepped:Connect(function() updateProxRing() end)

    local function CreateAdminControlGUI()
        -- Destroy any previous instance so re-injection sees the new style
        if _G._adminControlGui then
            pcall(function() _G._adminControlGui:Destroy() end)
            _G._adminControlGui = nil
        end
        for _, g in pairs(PlayerGui:GetChildren()) do
            if g.Name == "HubAdminControl" then pcall(function() g:Destroy() end) end
        end

        local adminControlGui = Instance.new("ScreenGui")
        adminControlGui.Name          = "HubAdminControl"
        adminControlGui.ResetOnSpawn  = false
        adminControlGui.Parent        = PlayerGui
        _G._adminControlGui           = adminControlGui

        local mainFrame = Instance.new("Frame")
        mainFrame.Size                = UDim2.new(0, 280 * MOBILE_SCALE, 0, 0)
        mainFrame.Position            = UDim2.new(
            Config.Positions.AdminControl and Config.Positions.AdminControl.X or 0.02, 0,
            Config.Positions.AdminControl and Config.Positions.AdminControl.Y or 0.5,  0)
        mainFrame.BackgroundColor3    = Color3.fromRGB(20, 20, 38)
        mainFrame.BackgroundTransparency = 0.75
        mainFrame.BorderSizePixel     = 0
        mainFrame.ClipsDescendants    = true
        mainFrame.Parent              = adminControlGui
        if not _G._hubPanelFrames then _G._hubPanelFrames={} end; table.insert(_G._hubPanelFrames, mainFrame)
        Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 14 * MOBILE_SCALE)
        local _mfStroke = Instance.new("UIStroke", mainFrame)
        _mfStroke.Color = Color3.fromRGB(42, 42, 68)
        _mfStroke.Thickness = 1.5
        _mfStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        if not _G._hubPanelStrokes then _G._hubPanelStrokes = {} end
        table.insert(_G._hubPanelStrokes, _mfStroke)

        do
            local _sdACF={{0.432,0.659,3,0.0056},{0.1,0.494,3,0.0048},{0.118,0.756,3,0.0038},{0.795,0.84,3,0.0057},{0.689,0.176,2,0.0061},{0.356,0.53,2,0.0054},{0.174,0.435,3,0.0044},{0.119,0.852,2,0.0041},{0.023,0.434,2,0.004},{0.467,0.055,3,0.005},{0.824,0.282,2,0.0045},{0.376,0.068,3,0.0039},{0.412,0.847,2,0.0047},{0.701,0.464,2,0.005},{0.79,0.873,2,0.0058},{0.467,0.231,3,0.0051},{0.684,0.523,2,0.0038},{0.814,0.342,2,0.0059},{0.563,0.538,2,0.0055},{0.704,0.233,3,0.0041},{0.471,0.419,3,0.0062},{0.221,0.564,3,0.0063},{0.814,0.634,2,0.0041},{0.304,0.353,2,0.0041},{0.268,0.763,3,0.0053},{0.857,0.681,2,0.0039},{0.383,0.146,2,0.0036},{0.204,0.819,3,0.0038},{0.23,0.912,2,0.0055},{0.649,0.203,3,0.0059}}
            local _sfACF,_soACF={},{}
            for i,sp in ipairs(_sdACF) do
                local s=Instance.new("Frame",mainFrame)
                s.Size=UDim2.new(0,sp[3],0,sp[3]);s.Position=UDim2.new(sp[1],0,sp[2],0)
                s.BackgroundColor3=Color3.fromRGB(255,255,255);s.BackgroundTransparency=0.3
                s.BorderSizePixel=0;s.ZIndex=10
                Instance.new("UICorner",s).CornerRadius=UDim.new(1,0)
                _sfACF[i]=s;_soACF[i]=sp[1]
                if not _G._hubStars then _G._hubStars={} end
                table.insert(_G._hubStars, s)
            end
            game:GetService("RunService").Heartbeat:Connect(function(dt)
                for i,s in ipairs(_sfACF) do
                    if not s or not s.Parent then continue end
                    _soACF[i]=(_soACF[i]-_sdACF[i][4]*dt)%1
                    s.Position=UDim2.new(_soACF[i],0,_sdACF[i][2],0)
                    s.BackgroundTransparency=0.3+math.abs(math.sin(tick()*0.8+i*0.7))*0.5
                end
            end)
        end

        local header = Instance.new("Frame", mainFrame)
        header.Size             = UDim2.new(1, 0, 0, 54 * MOBILE_SCALE)
        header.BackgroundColor3 = Color3.fromRGB(22, 22, 42)
        header.BackgroundTransparency = 0.75
        header.BorderSizePixel  = 0
        header.ZIndex           = 2
        Instance.new("UICorner", header).CornerRadius = UDim.new(0, 14 * MOBILE_SCALE)
        local _hFill = Instance.new("Frame", header)
        _hFill.Size = UDim2.new(1, 0, 0, 14 * MOBILE_SCALE)
        _hFill.Position = UDim2.new(0, 0, 1, -14 * MOBILE_SCALE)
        _hFill.BackgroundColor3 = Color3.fromRGB(22, 22, 42)
        _hFill.BackgroundTransparency = 0.75
        _hFill.BorderSizePixel = 0; _hFill.ZIndex = 2
        local _hSep = Instance.new("Frame", header)
        _hSep.Size = UDim2.new(1, -24 * MOBILE_SCALE, 0, 1)
        _hSep.Position = UDim2.new(0, 12 * MOBILE_SCALE, 1, -1)
        _hSep.BackgroundColor3 = Color3.fromRGB(42, 42, 68)
        _hSep.BorderSizePixel = 0; _hSep.ZIndex = 3
        MakeDraggable(header, mainFrame, "AdminControl")

        local titleMain = Instance.new("TextLabel", header)
        titleMain.Size                  = UDim2.new(1, -20 * MOBILE_SCALE, 0, 22 * MOBILE_SCALE)
        titleMain.Position              = UDim2.new(0, 10 * MOBILE_SCALE, 0, 6 * MOBILE_SCALE)
        titleMain.BackgroundTransparency = 1
        titleMain.Text                  = "IDF HUB"
        titleMain.Font                  = Enum.Font.GothamBold
        titleMain.TextSize              = 14 * MOBILE_SCALE
        titleMain.TextColor3            = Color3.fromRGB(255, 255, 255)
        titleMain.TextXAlignment        = Enum.TextXAlignment.Center
        titleMain.ZIndex                = 3
        local titleSub = Instance.new("TextLabel", header)
        titleSub.Size                  = UDim2.new(1, -20 * MOBILE_SCALE, 0, 14 * MOBILE_SCALE)
        titleSub.Position              = UDim2.new(0, 10 * MOBILE_SCALE, 0, 28 * MOBILE_SCALE)
        titleSub.BackgroundTransparency = 1
        titleSub.Text                  = "Admin Command Panel"
        titleSub.Font                  = Enum.Font.Gotham
        titleSub.TextSize              = 11 * MOBILE_SCALE
        titleSub.TextColor3            = Color3.fromRGB(130, 130, 165)
        titleSub.TextXAlignment        = Enum.TextXAlignment.Center
        titleSub.ZIndex                = 3
        local _acTitleStroke = {ApplyStrokeMode=0}  -- dummy

        local content = Instance.new("Frame", mainFrame)
        content.Size     = UDim2.new(1, -20 * MOBILE_SCALE, 1, -62 * MOBILE_SCALE)
        content.Position = UDim2.new(0, 10 * MOBILE_SCALE, 0, 58 * MOBILE_SCALE)
        content.BackgroundTransparency = 1

        local layout = Instance.new("UIListLayout", content)
        layout.Padding    = UDim.new(0, 6 * MOBILE_SCALE)
        layout.SortOrder  = Enum.SortOrder.LayoutOrder

        -- ─── createToggleRow (iOS pill style) ───────────────────────
        local function createToggleRow(labelText, defaultValue, callback)
            local ROW_H = 44 * MOBILE_SCALE
            local row = Instance.new("Frame", content)
            row.Size = UDim2.new(1, 0, 0, ROW_H)
            row.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
            row.BackgroundTransparency = 0
            row.BorderSizePixel = 0
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

            local lbl = Instance.new("TextLabel", row)
            lbl.Size = UDim2.new(1, -70 * MOBILE_SCALE, 1, 0)
            lbl.Position = UDim2.new(0, 14 * MOBILE_SCALE, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = labelText
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 12 * MOBILE_SCALE
            lbl.TextColor3 = Color3.fromRGB(235, 235, 245)
            lbl.TextXAlignment = Enum.TextXAlignment.Left

            local isOn = defaultValue or false
            local PILL_W = 40 * MOBILE_SCALE; local PILL_H = 22 * MOBILE_SCALE
            local DOT_SZ = 16 * MOBILE_SCALE
            local pill = Instance.new("Frame", row)
            pill.Size = UDim2.new(0, PILL_W, 0, PILL_H)
            pill.Position = UDim2.new(1, -(PILL_W + 12 * MOBILE_SCALE), 0.5, -PILL_H/2)
            pill.BackgroundColor3 = isOn and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
            pill.BorderSizePixel = 0
            pill.ClipsDescendants = true
            Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
            local dot = Instance.new("Frame", pill)
            dot.Size = UDim2.new(0, DOT_SZ, 0, DOT_SZ)
            dot.AnchorPoint = Vector2.new(0.5, 0.5)
            dot.Position = isOn and UDim2.new(1, -PILL_H/2, 0.5, 0) or UDim2.new(0, PILL_H/2, 0.5, 0)
            dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            dot.BorderSizePixel = 0
            Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
            local dotStroke = Instance.new("UIStroke", dot)
            dotStroke.Color = Color3.fromRGB(200, 200, 215); dotStroke.Thickness = 1

            local btn = Instance.new("TextButton", row)
            btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1
            btn.Text = ""; btn.ZIndex = 5
            btn.MouseButton1Click:Connect(function()
                isOn = not isOn
                TweenService:Create(pill, TweenInfo.new(0.18), {
                    BackgroundColor3 = isOn and Color3.fromRGB(65, 195, 90) or Color3.fromRGB(55, 55, 80)
                }):Play()
                TweenService:Create(dot, TweenInfo.new(0.18), {
                    Position = isOn and UDim2.new(1, -PILL_H/2, 0.5, 0) or UDim2.new(0, PILL_H/2, 0.5, 0)
                }):Play()
                callback(isOn)
            end)
            return row
        end

        -- ─── createButtonRow ─────────────────────────────────
        local function createButtonRow(text, buttonColor, callback)
            local rowBtn = Instance.new("TextButton", content)
            rowBtn.Size               = UDim2.new(1, 0, 0, 38 * MOBILE_SCALE)
            rowBtn.BackgroundColor3   = Color3.fromRGB(14, 14, 22)
            rowBtn.BackgroundTransparency = 0
            rowBtn.BorderSizePixel    = 0
            rowBtn.Text               = text
            rowBtn.Font               = Enum.Font.GothamBold
            rowBtn.TextSize           = 12 * MOBILE_SCALE
            rowBtn.TextColor3         = Color3.fromRGB(235, 235, 245)
            rowBtn.AutoButtonColor    = false
            Instance.new("UICorner", rowBtn).CornerRadius = UDim.new(0, 8)
            local _brStroke = Instance.new("UIStroke", rowBtn)
            _brStroke.Color = Color3.fromRGB(52, 52, 80); _brStroke.Thickness = 1
            _brStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            rowBtn.MouseButton1Click:Connect(function()
                TweenService:Create(rowBtn, TweenInfo.new(0.08), {BackgroundColor3 = Color3.fromRGB(30, 30, 45)}):Play()
                task.wait(0.15)
                TweenService:Create(rowBtn, TweenInfo.new(0.08), {BackgroundColor3 = Color3.fromRGB(14, 14, 22)}):Play()
                callback()
            end)
            rowBtn.MouseEnter:Connect(function() rowBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 32) end)
            rowBtn.MouseLeave:Connect(function() rowBtn.BackgroundColor3 = Color3.fromRGB(14, 14, 22) end)
            return rowBtn
        end

        -- ─── createCompactSliderRow ──────────────────────────
        local function createCompactSliderRow(text, min, max, default, suffix, callback)
            local row = Instance.new("Frame", content)
            row.Size               = UDim2.new(1, 0, 0, 50 * MOBILE_SCALE)
            row.BackgroundColor3   = Color3.fromRGB(14, 14, 22)
            row.BackgroundTransparency = 0
            row.BorderSizePixel    = 0
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

            local lbl = Instance.new("TextLabel", row)
            lbl.Size     = UDim2.new(0.6, 0, 0, 20 * MOBILE_SCALE)
            lbl.Position = UDim2.new(0, 12 * MOBILE_SCALE, 0, 7 * MOBILE_SCALE)
            lbl.BackgroundTransparency = 1
            lbl.Text     = text
            lbl.Font     = Enum.Font.GothamBold
            lbl.TextSize = 12 * MOBILE_SCALE
            lbl.TextColor3           = Color3.fromRGB(235, 235, 245)
            lbl.TextXAlignment       = Enum.TextXAlignment.Left

            local value = default or min
            local valLbl = Instance.new("TextLabel", row)
            valLbl.Size     = UDim2.new(0, 50 * MOBILE_SCALE, 0, 20 * MOBILE_SCALE)
            valLbl.Position = UDim2.new(1, -58 * MOBILE_SCALE, 0, 7 * MOBILE_SCALE)
            valLbl.BackgroundTransparency = 1
            valLbl.Text     = tostring(value) .. (suffix or "")
            valLbl.Font     = Enum.Font.GothamBold
            valLbl.TextSize = 12 * MOBILE_SCALE
            valLbl.TextColor3           = Color3.fromRGB(200, 200, 215)
            valLbl.TextXAlignment       = Enum.TextXAlignment.Right

            local sliderBg = Instance.new("Frame", row)
            sliderBg.Size     = UDim2.new(1, -24 * MOBILE_SCALE, 0, 4 * MOBILE_SCALE)
            sliderBg.Position = UDim2.new(0, 12 * MOBILE_SCALE, 0, 34 * MOBILE_SCALE)
            sliderBg.BackgroundColor3 = Color3.fromRGB(38, 38, 62)
            Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(1, 0)

            local fill = Instance.new("Frame", sliderBg)
            fill.BackgroundColor3 = Color3.fromRGB(65, 195, 90)
            fill.Size = UDim2.new((value-min)/(max-min), 0, 1, 0)
            Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

            local knob = Instance.new("Frame", sliderBg)
            knob.Size         = UDim2.new(0, 13 * MOBILE_SCALE, 0, 13 * MOBILE_SCALE)
            knob.BackgroundColor3 = Color3.fromRGB(240, 240, 255)
            knob.AnchorPoint  = Vector2.new(0.5, 0.5)
            knob.Position     = UDim2.new((value-min)/(max-min), 0, 0.5, 0)
            Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
            local _knobStroke = Instance.new("UIStroke", knob)
            _knobStroke.Color = Color3.fromRGB(200, 200, 215); _knobStroke.Thickness = 1

            local dragging = false
            local function updateSlider(inputX)
                local pos  = sliderBg.AbsolutePosition.X
                local size = sliderBg.AbsoluteSize.X
                local pct  = math.clamp((inputX - pos) / size, 0, 1)
                value = min + pct * (max - min)
                value = math.abs(value - math.floor(value)) < 0.01 and math.floor(value) or math.floor(value*10)/10
                fill.Size     = UDim2.new(pct, 0, 1, 0)
                knob.Position = UDim2.new(pct, 0, 0.5, 0)
                valLbl.Text   = tostring(value) .. (suffix or "")
                if callback then callback(value) end
            end
            sliderBg.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; updateSlider(i.Position.X) end end)
            knob.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end end)
            UserInputService.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
            UserInputService.InputChanged:Connect(function(i) if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then updateSlider(i.Position.X) end end)
            return row
        end

        -- ─── Click to AP Highlight ───────────────────────────
        local clickToAPHighlight = nil
        local function createClickToAPHighlight()
            if clickToAPHighlight then return end
            clickToAPHighlight = Instance.new("Highlight")
            clickToAPHighlight.Name               = "HubClickToAPHighlight"
            clickToAPHighlight.FillColor          = Theme.Accent1
            clickToAPHighlight.FillTransparency   = 0.5
            clickToAPHighlight.OutlineColor       = Theme.Accent2
            clickToAPHighlight.OutlineTransparency= 0.2
            clickToAPHighlight.DepthMode          = Enum.HighlightDepthMode.AlwaysOnTop
            clickToAPHighlight.Parent             = game:GetService("CoreGui")
        end

        local function rayToCubeIntersect(rayOrigin, rayDirection, cubeCenter, cubeSize)
            local halfSize = cubeSize / 2
            local minB = cubeCenter - Vector3.new(halfSize, halfSize, halfSize)
            local maxB = cubeCenter + Vector3.new(halfSize, halfSize, halfSize)
            if rayDirection.X == 0 then rayDirection = Vector3.new(0.0001, rayDirection.Y, rayDirection.Z) end
            if rayDirection.Y == 0 then rayDirection = Vector3.new(rayDirection.X, 0.0001, rayDirection.Z) end
            if rayDirection.Z == 0 then rayDirection = Vector3.new(rayDirection.X, rayDirection.Y, 0.0001) end
            local tmin = (minB.X-rayOrigin.X)/rayDirection.X; local tmax = (maxB.X-rayOrigin.X)/rayDirection.X
            if tmin > tmax then tmin,tmax = tmax,tmin end
            local tymin= (minB.Y-rayOrigin.Y)/rayDirection.Y; local tymax= (maxB.Y-rayOrigin.Y)/rayDirection.Y
            if tymin > tymax then tymin,tymax = tymax,tymin end
            if tmin > tymax or tymin > tmax then return false end
            if tymin > tmin then tmin = tymin end; if tymax < tmax then tmax = tymax end
            local tzmin= (minB.Z-rayOrigin.Z)/rayDirection.Z; local tzmax= (maxB.Z-rayOrigin.Z)/rayDirection.Z
            if tzmin > tzmax then tzmin,tzmax = tzmax,tzmin end
            if tmin > tzmax or tzmin > tmax then return false end
            return true
        end

        local function getPlayerHitboxPart(player)
            local char = player.Character
            if not char then return nil end
            return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
        end

        task.spawn(function()
            createClickToAPHighlight()
            local lastHoveredPlayer = nil
            Heartbeat:Connect(function()
                if Config.ClickToAP then
                    local camera   = Workspace.CurrentCamera
                    local mousePos = UserInputService:GetMouseLocation()
                    local ray      = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
                    local bestPlayer, bestDist = nil, math.huge
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= LocalPlayer then
                            local part = getPlayerHitboxPart(p)
                            if part and rayToCubeIntersect(ray.Origin, ray.Direction, part.Position, 6) then
                                local dist = (ray.Origin - part.Position).Magnitude
                                if dist < bestDist then bestDist = dist; bestPlayer = p end
                            end
                        end
                    end
                    if bestPlayer ~= lastHoveredPlayer then
                        clickToAPHighlight.Adornee = bestPlayer and bestPlayer.Character or nil
                        lastHoveredPlayer = bestPlayer
                    end
                elseif clickToAPHighlight then
                    clickToAPHighlight.Adornee = nil
                end
            end)
        end)

        UserInputService.InputBegan:Connect(function(input, gameProcessed)
            if UserInputService:GetFocusedTextBox() then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 and Config.ClickToAP then
                local camera   = Workspace.CurrentCamera
                local mousePos = UserInputService:GetMouseLocation()
                local ray      = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
                local bestPlayer, bestDist = nil, math.huge
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer then
                        local part = getPlayerHitboxPart(p)
                        if part and rayToCubeIntersect(ray.Origin, ray.Direction, part.Position, 6) then
                            local dist = (ray.Origin - part.Position).Magnitude
                            if dist < bestDist then bestDist = dist; bestPlayer = p end
                        end
                    end
                end
                if bestPlayer then
                    if _G._fireAdmin then _G._fireAdmin(bestPlayer, pickRandomCmd()) end
                end
            end
        end)

        -- ─── Rows ────────────────────────────────────────────
        createToggleRow("Proximity AP", false, function(on)
            ProximityAPActive = on
            updateProxRing()
        end)

        createCompactSliderRow("Proximity Range", 5, 50, PROXIMITY_RANGE, "s", function(val)
            PROXIMITY_RANGE        = val
            Config.ProximityRange  = val
            SaveConfig()
            updateProxRing()
        end)

        createToggleRow("Click to AP", Config.ClickToAP, function(on)
            Config.ClickToAP = on
            SaveConfig()
        end)

        -- Spam Owner
        createButtonRow("Spam Base Owner", Theme.Accent1, function()
            local cache = _G._stealAnimalsCache
            if not cache or #cache == 0 then return end
            local ownerName = cache[1].owner
            if not ownerName then return end
            local targetPlayer = Players:FindFirstChild(ownerName)
            if not targetPlayer or targetPlayer == LocalPlayer then return end
            local cmds = {"balloon","inverse","jail","jumpscare","morph","nightvision","ragdoll","rocket","tiny"}
            for _, cmd in ipairs(cmds) do
                if _G._fireAdmin then _G._fireAdmin(targetPlayer, cmd) end
            end
        end)

        -- ─── Proximity AP loop ───────────────────────────────
        local proxAPCooldown = 0
        local PROX_AP_INTERVAL = 0.5
        local COMMAND_DELAY    = 0.08
        Heartbeat:Connect(function(dt)
            if not ProximityAPActive then return end
            proxAPCooldown = proxAPCooldown + dt
            if proxAPCooldown < PROX_AP_INTERVAL then return end
            proxAPCooldown = 0
            local myChar = LocalPlayer.Character
            if not myChar then return end
            local myHrp = myChar:FindFirstChild("HumanoidRootPart")
            if not myHrp then return end
            local playersInRange = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
                    if (p.Character.HumanoidRootPart.Position - myHrp.Position).Magnitude <= PROXIMITY_RANGE then
                        table.insert(playersInRange, p)
                    end
                end
            end
            if #playersInRange == 0 then return end
            local target = playersInRange[1]
            if _G._fireAdmin then
                for _, cmd in ipairs(PROX_COMMANDS) do
                    _G._fireAdmin(target, cmd)
                end
            end
        end)

        -- ─── Auto-resize ─────────────────────────────────────
        local function updateFrameHeight()
            mainFrame.Size = UDim2.new(0, 280 * MOBILE_SCALE, 0, layout.AbsoluteContentSize.Y + 78 * MOBILE_SCALE)
        end
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateFrameHeight)
        task.defer(updateFrameHeight)
    end

    CreateAdminControlGUI()
    -- Appliquer l'etat du toggle des la creation
    task.defer(function()
        if _G._adminControlGui then
            _G._adminControlGui.Enabled = (_G._adminControlOn ~= false)
        end
    end)
end)
-- ================================================
-- CNK INVISIBLE STEAL — Standalone
-- Execute dans la console Roblox (F9)
-- ================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Attendre que le jeu soit complètement chargé (auto-execute)
if not game:IsLoaded() then game.Loaded:Wait() end

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 30)

-- Attendre le personnage
if not LocalPlayer.Character then
    LocalPlayer.CharacterAdded:Wait()
end
task.wait(1)

-- Nettoyer les anciennes instances
local oldGui = PlayerGui:FindFirstChild("XiInvisPanel")
if oldGui then oldGui:Destroy() end

-- ================================================
-- CONFIG (modifiable)
-- ================================================
local Config = {
    InvisStealAngle   = 233,
    SinkSliderValue   = 5,
    AutoInvisDuringSteal = false,
    AutoRecoverLagback   = true,
    InvisToggleKey    = "I",
    ShowInvisPanel    = true,
    StealSpeed        = 1,
    GuiScale          = 1.0,
    Positions = {
        InvisPanel = {X = 0.8578125, OffsetX = 0, Y = 0.17260276361454258, OffsetY = 0}
    },
}

-- ================================================
-- THEME
-- ================================================
local Theme = {
    Accent1       = Color3.fromRGB(180, 80, 255),
    Accent2       = Color3.fromRGB(120, 40, 200),
    TextPrimary   = Color3.fromRGB(240, 225, 255),
    TextSecondary = Color3.fromRGB(185, 150, 230),
    SurfaceHighlight = Color3.fromRGB(36, 20, 62),
}

-- ================================================
-- FONCTIONS UTILITAIRES
-- ================================================
local function ShowNotification(title, text)
    local existing = PlayerGui:FindFirstChild("XiNotif")
    if existing then existing:Destroy() end
    local sg = Instance.new("ScreenGui", PlayerGui)
    sg.Name = "XiNotif"; sg.ResetOnSpawn = false
    local f = Instance.new("Frame", sg)
    f.Size = UDim2.new(0, 290, 0, 54)
    f.Position = UDim2.new(0.5, -145, 0, 80)
    f.BackgroundColor3 = Color3.fromRGB(6, 6, 12)
    f.BackgroundTransparency = 1; f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 0)
    local stroke = Instance.new("UIStroke", f)
    stroke.Thickness = 1; stroke.Color = Theme.Accent2; stroke.Transparency = 1
    local bar = Instance.new("Frame", f)
    bar.Size = UDim2.new(0, 3, 1, -12); bar.Position = UDim2.new(0, 5, 0, 6)
    bar.BackgroundColor3 = Theme.Accent1; bar.BorderSizePixel = 0; bar.BackgroundTransparency = 1
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)
    local t1 = Instance.new("TextLabel", f)
    t1.Size = UDim2.new(1, -22, 0, 18); t1.Position = UDim2.new(0, 16, 0, 7)
    t1.BackgroundTransparency = 1; t1.Text = title:upper()
    t1.Font = Enum.Font.GothamBlack; t1.TextSize = 11
    t1.TextColor3 = Theme.Accent1; t1.TextXAlignment = Enum.TextXAlignment.Left; t1.TextTransparency = 1
    local t2 = Instance.new("TextLabel", f)
    t2.Size = UDim2.new(1, -22, 0, 15); t2.Position = UDim2.new(0, 16, 0, 27)
    t2.BackgroundTransparency = 1; t2.Text = text
    t2.Font = Enum.Font.GothamMedium; t2.TextSize = 10
    t2.TextColor3 = Theme.TextSecondary; t2.TextXAlignment = Enum.TextXAlignment.Left; t2.TextTransparency = 1
    local fi = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    TweenService:Create(f, fi, {BackgroundTransparency = 0.08}):Play()
    TweenService:Create(stroke, fi, {Transparency = 0.3}):Play()
    TweenService:Create(bar, fi, {BackgroundTransparency = 0}):Play()
    TweenService:Create(t1, fi, {TextTransparency = 0}):Play()
    TweenService:Create(t2, fi, {TextTransparency = 0}):Play()
    task.delay(2, function()
        if not sg.Parent then return end
        local fo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
        TweenService:Create(f, fo, {BackgroundTransparency = 1}):Play()
        TweenService:Create(stroke, fo, {Transparency = 1}):Play()
        TweenService:Create(bar, fo, {BackgroundTransparency = 1}):Play()
        TweenService:Create(t1, fo, {TextTransparency = 1}):Play()
        local last = TweenService:Create(t2, fo, {TextTransparency = 1})
        last:Play(); last.Completed:Wait()
        if sg.Parent then sg:Destroy() end
    end)
end

local function RegisterGuiScale(frame)
    if not frame then return end
    local existing = frame:FindFirstChildOfClass("UIScale")
    if not existing then
        existing = Instance.new("UIScale")
        existing.Parent = frame
    end
    existing.Scale = math.clamp(tonumber(Config.GuiScale) or 1.0, 0.5, 2.0)
end

local SAVE_FILE = "CNK_InvisConfig.json"

local function SaveConfig()
    pcall(function()
        local data = {
            InvisStealAngle      = Config.InvisStealAngle,
            SinkSliderValue      = Config.SinkSliderValue,
            AutoInvisDuringSteal = Config.AutoInvisDuringSteal,
            AutoRecoverLagback   = Config.AutoRecoverLagback,
            InvisToggleKey       = Config.InvisToggleKey,
            ShowInvisPanel       = Config.ShowInvisPanel,
            StealSpeed           = Config.StealSpeed,
            Positions            = Config.Positions,
        }
        writefile(SAVE_FILE, game:GetService("HttpService"):JSONEncode(data))
    end)
end

local function LoadConfig()
    pcall(function()
        if not isfile(SAVE_FILE) then return end
        local raw = readfile(SAVE_FILE)
        local ok, decoded = pcall(function()
            return game:GetService("HttpService"):JSONDecode(raw)
        end)
        if not ok or type(decoded) ~= "table" then return end
        if decoded.InvisStealAngle      ~= nil then Config.InvisStealAngle      = decoded.InvisStealAngle end
        if decoded.SinkSliderValue      ~= nil then Config.SinkSliderValue      = decoded.SinkSliderValue end
        if decoded.AutoInvisDuringSteal ~= nil then Config.AutoInvisDuringSteal = decoded.AutoInvisDuringSteal end
        if decoded.AutoRecoverLagback   ~= nil then Config.AutoRecoverLagback   = decoded.AutoRecoverLagback end
        if decoded.InvisToggleKey       ~= nil then Config.InvisToggleKey       = decoded.InvisToggleKey end
        if decoded.ShowInvisPanel       ~= nil then Config.ShowInvisPanel       = decoded.ShowInvisPanel end
        if decoded.StealSpeed           ~= nil then Config.StealSpeed           = decoded.StealSpeed end
        if decoded.Positions and type(decoded.Positions) == "table" then
            for k, v in pairs(decoded.Positions) do
                Config.Positions[k] = v
            end
        end
        -- Sync _G
        _G.InvisStealAngle    = Config.InvisStealAngle
        _G.SinkSliderValue    = Config.SinkSliderValue
        _G.AutoInvisDuringSteal = Config.AutoInvisDuringSteal
        _G.AutoRecoverLagback = Config.AutoRecoverLagback
        _G.INVISIBLE_STEAL_KEY = Enum.KeyCode[Config.InvisToggleKey] or Enum.KeyCode.I
    end)
end


local function MakeDraggable(handle, target, saveKey)
    local dragging, dragInput, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
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
                    end
                end
            end)
        end
    end)

    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

local function instantClone()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local cloner = LocalPlayer.Backpack:FindFirstChild("Quantum Cloner")
        or character:FindFirstChild("Quantum Cloner")
    if not cloner then return end
    if cloner.Parent ~= character then humanoid:EquipTool(cloner); task.wait() end
    local toolsFrames = PlayerGui:FindFirstChild("ToolsFrames")
    local qcFrame = toolsFrames and toolsFrames:FindFirstChild("QuantumCloner")
    local tpButton = qcFrame and qcFrame:FindFirstChild("TeleportToClone")
    if not tpButton then return end
    cloner:Activate()
    task.wait(0.055)
    tpButton.Visible = true
    if typeof(firesignal) == "function" then
        firesignal(tpButton.MouseButton1Up)
    end
end

-- ================================================
-- GLOBALS utilisés par le bloc invis
-- ================================================
_G.InvisStealAngle     = Config.InvisStealAngle
_G.SinkSliderValue     = Config.SinkSliderValue
_G.AutoInvisDuringSteal = Config.AutoInvisDuringSteal
_G.AutoRecoverLagback  = Config.AutoRecoverLagback
_G.INVISIBLE_STEAL_KEY = Enum.KeyCode[Config.InvisToggleKey] or Enum.KeyCode.I
_G.invisibleStealEnabled = false
_G.isCloning = false
_G.RecoveryInProgress = false
_G.AntiDieDisabled = false
_G.AntiDieConnection = nil
-- Stubs pour fonctions optionnelles (beam/panel sync)
_G.createPlotBeam = nil
_G.resetBrainrotBeam = nil
_G.resetPlotBeam = nil
_G.updateBrainrotBeam = nil
_G.updateMovementPanelInvisVisual = nil
_G.syncMainAutoInvisToggle = nil
_G.syncMiniInvisAutoStealToggle = nil

-- Charger la config sauvegardée (APRES les _G pour que le sync fonctionne)
LoadConfig()

-- SharedState stub (fonctions du script principal)
local SharedState = {
    GetStealSpeed = function() return Config.StealSpeed or 25.5 end,
    SetStealSpeed = function(v) Config.StealSpeed = v end,
    GuiScaleObjects = {},
}

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
						if clone then clone.CanCollide = true end
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


    -- ═══════════════════════════════════════════════════
    -- PANEL INVISIBLE STEAL — style hub (étoiles/orange/vert)
    -- ═══════════════════════════════════════════════════
    local IS_BG     = Color3.fromRGB(8, 10, 18)
    local IS_BTN    = Color3.fromRGB(14, 14, 22)
    local IS_BORDER = Color3.fromRGB(255, 0, 220)
    local IS_GREEN1 = Color3.fromRGB(85, 200, 85)
    local IS_GREEN2 = Color3.fromRGB(5, 30, 5)
    local IS_BALL   = Color3.fromRGB(120, 240, 120)
    local IS_WHITE  = Color3.fromRGB(255, 255, 255)
    local IS_RED    = Color3.fromRGB(220, 60, 60)
    local IS_W      = 260
    local IS_PAD    = 5

    local isGui = Instance.new("ScreenGui")
    isGui.Name = "InvisStealPanel"; isGui.ResetOnSpawn = false
    isGui.IgnoreGuiInset = true; isGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local _isOk = pcall(function() isGui.Parent = game:GetService("CoreGui") end)
    if not _isOk or not isGui.Parent then
        pcall(function() if gethui then isGui.Parent = gethui() end end)
    end
    if not isGui.Parent then isGui.Parent = PlayerGui end
    if protect_gui then pcall(function() protect_gui(isGui) end) end

    local panel = Instance.new("Frame")
    panel.Name = "InvisFrame"; panel.BackgroundColor3 = IS_BG
    panel.BackgroundTransparency = 0.1; panel.BorderSizePixel = 0
    panel.Position = UDim2.new(0, 820, 0, 180)
    panel.ClipsDescendants = true; panel.Parent = isGui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
    local _isPStroke = Instance.new("UIStroke", panel)
    _isPStroke.Color = IS_BORDER; _isPStroke.Thickness = 3
    local _isAccentStrokes = {}
    local _isAccentTextEls = {}
    local _isSliderGrads = {}  -- {grad, endColor} pour les gradients des sliders
    if not _G._hubPanelStrokes then _G._hubPanelStrokes = {} end
    if not _G._hubStars then _G._hubStars = {} end
    table.insert(_G._hubPanelStrokes, _isPStroke)

    -- Étoiles flottantes panneau
    do
        local _sdIS = {
            {0.06,0.82,2,0.007},{0.17,0.14,2,0.005},{0.29,0.63,3,0.006},
            {0.41,0.36,2,0.008},{0.52,0.87,2,0.005},{0.64,0.17,3,0.007},
            {0.73,0.71,2,0.006},{0.84,0.44,2,0.009},{0.93,0.09,3,0.005},
            {0.12,0.52,2,0.006},{0.35,0.27,3,0.008},{0.58,0.76,2,0.007},
            {0.79,0.91,2,0.005},{0.22,0.48,3,0.009},{0.47,0.33,2,0.006},
            {0.68,0.59,2,0.007},{0.88,0.22,3,0.005},{0.04,0.66,2,0.008},
        }
        local _sfIS, _soIS = {}, {}
        for i, sp in ipairs(_sdIS) do
            local s = Instance.new("Frame", panel)
            s.Size = UDim2.new(0,sp[3],0,sp[3]); s.Position = UDim2.new(sp[1],0,sp[2],0)
            s.BackgroundColor3 = Color3.fromRGB(255,255,255); s.BackgroundTransparency = 0.3
            s.BorderSizePixel = 0; s.ZIndex = 10
            Instance.new("UICorner",s).CornerRadius = UDim.new(1,0)
            _sfIS[i] = s; _soIS[i] = sp[1]
            table.insert(_G._hubStars, s)
        end
        RunService.Heartbeat:Connect(function(dt)
            for i, s in ipairs(_sfIS) do
                if not s or not s.Parent then continue end
                _soIS[i] = (_soIS[i] - _sdIS[i][4]*dt) % 1
                s.Position = UDim2.new(_soIS[i], 0, _sdIS[i][2], 0)
                s.BackgroundTransparency = 0.3 + math.abs(math.sin(tick()*0.9 + i*0.6)) * 0.5
            end
        end)
    end

    -- Titre
    local isTitleLbl = Instance.new("TextLabel")
    isTitleLbl.Size = UDim2.new(1,-16,0,20); isTitleLbl.Position = UDim2.new(0,8,0,IS_PAD)
    isTitleLbl.BackgroundTransparency = 1; isTitleLbl.Text = "IDF HUB"
    isTitleLbl.TextColor3 = IS_WHITE; isTitleLbl.Font = Enum.Font.GothamBold
    isTitleLbl.TextSize = 16; isTitleLbl.TextXAlignment = Enum.TextXAlignment.Center
    isTitleLbl.ZIndex = 2; isTitleLbl.Parent = panel
    local isSubLbl = Instance.new("TextLabel")
    isSubLbl.Size = UDim2.new(1,-16,0,14); isSubLbl.Position = UDim2.new(0,8,0,IS_PAD+20)
    isSubLbl.BackgroundTransparency = 1; isSubLbl.Text = "Invisible Steal"
    isSubLbl.TextColor3 = Color3.fromRGB(200,200,200); isSubLbl.Font = Enum.Font.Gotham
    isSubLbl.TextSize = 11; isSubLbl.TextXAlignment = Enum.TextXAlignment.Center
    isSubLbl.ZIndex = 2; isSubLbl.Parent = panel
    makeDraggable(panel, "InvisStealPanel", isTitleLbl)

    -- Étoiles dans le titre
    do
        local _sdTIS = {
            {0.78,0.35,1,0.009},{0.91,0.6,2,0.011},{0.15,0.5,1,0.007},
            {0.32,0.2,2,0.008},{0.55,0.7,1,0.010},{0.70,0.45,2,0.012},
        }
        local _sfTIS, _soTIS = {}, {}
        for i, sp in ipairs(_sdTIS) do
            local s = Instance.new("Frame", isTitleLbl)
            s.Size = UDim2.new(0,sp[3],0,sp[3]); s.Position = UDim2.new(sp[1],0,sp[2],0)
            s.BackgroundColor3 = Color3.fromRGB(255,255,255); s.BackgroundTransparency = 0.2
            s.BorderSizePixel = 0; s.ZIndex = 3
            Instance.new("UICorner",s).CornerRadius = UDim.new(1,0)
            _sfTIS[i] = s; _soTIS[i] = sp[1]
            table.insert(_G._hubStars, s)
        end
        RunService.Heartbeat:Connect(function(dt)
            for i, s in ipairs(_sfTIS) do
                if not s or not s.Parent then continue end
                _soTIS[i] = (_soTIS[i] - _sdTIS[i][4]*dt) % 1
                s.Position = UDim2.new(_soTIS[i], 0, _sdTIS[i][2], 0)
                s.BackgroundTransparency = 0.1 + math.abs(math.sin(tick()*1.2 + i)) * 0.7
            end
        end)
    end

    -- Séparateur
    local isSep = Instance.new("Frame", panel)
    isSep.Size = UDim2.new(1,-20,0,1); isSep.Position = UDim2.new(0,10,0,IS_PAD+42)
    isSep.BackgroundColor3 = IS_WHITE; isSep.BackgroundTransparency = 0.7
    isSep.BorderSizePixel = 0; isSep.ZIndex = 2

    local curY     = IS_PAD + 60
    local ROW_H_IS = 48
    local ROW_GAP  = 10

    -- Toggle style SXE HUB
    local function makeISToggle(labelText, startOn, onToggle)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1,-10,0,ROW_H_IS); btn.Position = UDim2.new(0,5,0,curY)
        btn.BackgroundColor3 = IS_BTN; btn.BackgroundTransparency = 0.1
        btn.BorderSizePixel = 0; btn.Text = ""; btn.AutoButtonColor = false
        btn.ZIndex = 2; btn.Parent = panel
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
        local bStroke = Instance.new("UIStroke", btn)
        bStroke.Color = IS_BORDER; bStroke.Thickness = 1
        table.insert(_isAccentStrokes, bStroke)

        local lbl = Instance.new("TextLabel", btn)
        lbl.Size = UDim2.new(0.55,0,1,0); lbl.Position = UDim2.new(0,10,0,0)
        lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = IS_WHITE
        lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 3

        local stateLbl = Instance.new("TextLabel", btn)
        stateLbl.Size = UDim2.new(0,80,0,22); stateLbl.Position = UDim2.new(1,-86,0.5,-11)
        stateLbl.BackgroundColor3 = startOn and IS_BORDER or Color3.fromRGB(20,20,30)
        stateLbl.BackgroundTransparency = startOn and 0 or 0
        stateLbl.BorderSizePixel = 0
        stateLbl.Text = startOn and "ACTIVE" or "DESACTIVE"
        stateLbl.TextColor3 = startOn and IS_WHITE or Color3.fromRGB(180,180,180)
        stateLbl.Font = Enum.Font.GothamBold; stateLbl.TextSize = 10; stateLbl.ZIndex = 3
        Instance.new("UICorner", stateLbl).CornerRadius = UDim.new(0, 6)
        local _sslBorder = Instance.new("UIStroke", stateLbl)
        _sslBorder.Color = startOn and IS_BORDER or Color3.fromRGB(80,80,90); _sslBorder.Thickness = 1

        local state = startOn
        local function refresh()
            local ac = _G._hubThemeColor or IS_BORDER
            stateLbl.Text = state and "ACTIVE" or "DESACTIVE"
            stateLbl.BackgroundColor3 = state and ac or Color3.fromRGB(20,20,30)
            stateLbl.TextColor3 = state and IS_WHITE or Color3.fromRGB(180,180,180)
            _sslBorder.Color = state and ac or Color3.fromRGB(80,80,90)
        end
        btn.MouseButton1Click:Connect(function()
            state = not state; refresh()
            if onToggle then onToggle(state) end
        end)
        curY = curY + ROW_H_IS + ROW_GAP
        return { SetState = function(v) state = v; refresh() end, GetState = function() return state end }
    end

    -- Slider
    local activeSlider = nil
    local function makeISSlider(labelText, minVal, maxVal, defVal, isInt, onChange)
        local BALL_SZ = 14; local LABEL_W = 52; local VAL_W = 40; local RESET_W = 18
        local sliderX = IS_PAD + LABEL_W + 2
        local sliderW = IS_W - sliderX - VAL_W - RESET_W - IS_PAD*2 - 2
        local valX    = sliderX + sliderW + 4
        local resetX  = valX + VAL_W + 2
        local centerY = curY + 8

        local lbl = Instance.new("TextLabel", panel)
        lbl.Size = UDim2.new(0,LABEL_W,0,16); lbl.Position = UDim2.new(0,IS_PAD,0,centerY-8)
        lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = IS_WHITE
        lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 2

        local track = Instance.new("Frame", panel)
        track.Size = UDim2.new(0,sliderW,0,4); track.Position = UDim2.new(0,sliderX,0,centerY-2)
        track.BackgroundColor3 = IS_BORDER; track.BorderSizePixel = 0; track.ZIndex = 2
        Instance.new("UICorner", track).CornerRadius = UDim.new(0, 2)
        local tg = Instance.new("UIGradient", track)
        tg.Color = ColorSequence.new(IS_BORDER, Color3.fromRGB(140,10,80))
        table.insert(_isSliderGrads, {grad=tg, endColor=Color3.fromRGB(140,10,80)})

        local valLbl = Instance.new("TextLabel", panel)
        valLbl.Size = UDim2.new(0,VAL_W,0,16); valLbl.Position = UDim2.new(0,valX,0,centerY-8)
        valLbl.BackgroundTransparency = 1; valLbl.TextColor3 = IS_WHITE
        valLbl.Font = Enum.Font.GothamBold; valLbl.TextSize = 11
        valLbl.TextXAlignment = Enum.TextXAlignment.Left; valLbl.ZIndex = 2

        local resetBtn = Instance.new("TextButton", panel)
        resetBtn.Size = UDim2.new(0,0,0,0)
        resetBtn.Position = UDim2.new(0,resetX,0,centerY-RESET_W/2)
        resetBtn.BackgroundTransparency = 1; resetBtn.BorderSizePixel = 0
        resetBtn.Text = ""; resetBtn.AutoButtonColor = false
        resetBtn.ZIndex = 2; resetBtn.Visible = false

        local ball = Instance.new("TextButton", panel)
        ball.Size = UDim2.new(0,BALL_SZ,0,BALL_SZ); ball.BackgroundColor3 = IS_BORDER
        ball.BorderSizePixel = 0; ball.Text = ""; ball.AutoButtonColor = false; ball.ZIndex = 3
        Instance.new("UICorner", ball).CornerRadius = UDim.new(1, 0)
        local bg2 = Instance.new("UIGradient", ball)
        bg2.Color = ColorSequence.new(IS_BORDER, Color3.fromRGB(200,20,120))
        table.insert(_isSliderGrads, {grad=bg2, endColor=Color3.fromRGB(200,20,120)})

        local curVal = math.clamp(defVal, minVal, maxVal)
        local function valToStr(v)
            if isInt then return tostring(math.floor(v+0.5)) end
            return string.format("%.2f", v)
        end
        local function applyVal(v, silent)
            curVal = math.clamp(v, minVal, maxVal)
            local alpha = (curVal-minVal)/(maxVal-minVal)
            ball.Position = UDim2.new(0, sliderX+alpha*sliderW-BALL_SZ/2, 0, centerY-BALL_SZ/2)
            valLbl.Text = valToStr(curVal)
            if not silent and onChange then onChange(curVal) end
        end
        local function fromMouse(input)
            local ax = track.AbsolutePosition.X; local aw = track.AbsoluteSize.X
            if aw <= 0 then return end
            local alpha = math.clamp((input.Position.X - ax) / aw, 0, 1)
            applyVal(minVal + alpha*(maxVal-minVal), false)
        end
        applyVal(curVal, true)

        ball.MouseButton1Down:Connect(function() activeSlider = {setFromInput = fromMouse} end)
        track.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 then
                activeSlider = {setFromInput = fromMouse}; fromMouse(inp)
            end
        end)
        resetBtn.MouseButton1Click:Connect(function()
            applyVal(defVal, false); resetBtn.TextColor3 = IS_GREEN1
            task.delay(0.6, function() if resetBtn and resetBtn.Parent then resetBtn.TextColor3 = _G._hubThemeColor or IS_BORDER end end)
        end)
        curY = curY + 26 + ROW_GAP
        return {
            Set = function(v, silent) applyVal(v, silent) end,
            Get = function() return curVal end
        }
    end

    -- Keybind
    local function makeISKeybind()
        local row = Instance.new("Frame", panel)
        row.Size = UDim2.new(1,-10,0,ROW_H_IS); row.Position = UDim2.new(0,5,0,curY)
        row.BackgroundColor3 = IS_BTN; row.BackgroundTransparency = 0.1
        row.BorderSizePixel = 0; row.ZIndex = 2
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 12)
        local _rws = Instance.new("UIStroke", row); _rws.Color = IS_BORDER
        table.insert(_isAccentStrokes, _rws)

        local lbl = Instance.new("TextLabel", row)
        lbl.Size = UDim2.new(1,-65,1,0); lbl.Position = UDim2.new(0,10,0,0)
        lbl.BackgroundTransparency = 1; lbl.Text = "Keybind"
        lbl.TextColor3 = IS_WHITE; lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 3

        local kbBtn = Instance.new("TextButton", row)
        kbBtn.Size = UDim2.new(0,46,0,22); kbBtn.Position = UDim2.new(1,-54,0.5,-11)
        kbBtn.BackgroundColor3 = IS_BTN; kbBtn.BorderSizePixel = 0
        kbBtn.Text = tostring(Config.InvisToggleKey or "I")
        kbBtn.TextColor3 = Color3.fromRGB(255, 255, 255); kbBtn.Font = Enum.Font.GothamBold
        kbBtn.TextSize = 11; kbBtn.AutoButtonColor = false; kbBtn.ZIndex = 3
        Instance.new("UICorner", kbBtn).CornerRadius = UDim.new(0, 6)
        local _kbs = Instance.new("UIStroke", kbBtn); _kbs.Color = IS_BORDER
        table.insert(_isAccentStrokes, _kbs)

        kbBtn.MouseButton1Click:Connect(function()
            kbBtn.Text = "..."
            local conn
            conn = UserInputService.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Keyboard then
                    Config.InvisToggleKey = input.KeyCode.Name
                    _G.INVISIBLE_STEAL_KEY = input.KeyCode
                    kbBtn.Text = input.KeyCode.Name
                    SaveConfig()
                    if conn then conn:Disconnect() end
                end
            end)
        end)
        curY = curY + ROW_H_IS + ROW_GAP
    end

    -- Construction
    local enableToggle = makeISToggle("Invis Steal", _G.invisibleStealEnabled or false, function(on)
        if _G.toggleInvisibleSteal then
            pcall(_G.toggleInvisibleSteal)
        end
    end)
    local autoRecoverToggle = makeISToggle("Auto Recover", _G.AutoRecoverLagback ~= false, function(on)
        _G.AutoRecoverLagback = on; Config.AutoRecoverLagback = on; SaveConfig()
    end)
    local autoInvisToggle = makeISToggle("Auto Invis On Steal", Config.AutoInvisDuringSteal or false, function(on)
        Config.AutoInvisDuringSteal = on; _G.AutoInvisDuringSteal = on
        if _G.syncMainAutoInvisToggle then pcall(_G.syncMainAutoInvisToggle, on) end
        SaveConfig()
    end)

    curY = curY + 4

    local rotSlider = makeISSlider("Rot", 0, 360, Config.InvisStealAngle or 233, true, function(v)
        Config.InvisStealAngle = v; _G.InvisStealAngle = v; SaveConfig()
    end)
    local depSlider = makeISSlider("Dep", 0, 18, Config.SinkSliderValue or 5, false, function(v)
        Config.SinkSliderValue = v; _G.SinkSliderValue = v; SaveConfig()
    end)
    local spdSlider = makeISSlider("Spd", 5, 40, Config.StealSpeed or SharedState.GetStealSpeed(), false, function(v)
        Config.StealSpeed = v; SharedState.SetStealSpeed(v); SaveConfig()
    end)
    local wsISSlider = makeISSlider("Walk Spd", 0, 32, 0, true, function(v)
        if _G._applyWalkSpeed then _G._applyWalkSpeed(v) end
    end)

    makeISKeybind()
    panel.Size = UDim2.new(0, IS_W, 0, curY + 8)

    -- Enregistrer tous les strokes accent dans le système de thème du hub
    for _, st in ipairs(_isAccentStrokes) do
        table.insert(_G._hubPanelStrokes, st)
    end

    -- Hooker setHubTheme pour recolorer les textes accent (resetBtn ★, kbBtn)
    task.spawn(function()
        while not _G._setHubTheme do task.wait(0.2) end
        local _origIS = _G._setHubTheme
        _G._setHubTheme = function(theme)
            _origIS(theme)
            local ac = _G._hubThemeColor
            if ac then
                for _, el in ipairs(_isAccentTextEls) do
                    pcall(function() el.TextColor3 = ac end)
                end
                -- Mettre a jour les gradients des sliders
                for _, entry in ipairs(_isSliderGrads) do
                    pcall(function()
                        if entry.grad and entry.grad.Parent then
                            entry.grad.Color = ColorSequence.new(ac, entry.endColor)
                        end
                    end)
                end
            end
        end
        -- Appliquer couleur actuelle immédiatement
        if _G._hubThemeColor then
            for _, el in ipairs(_isAccentTextEls) do
                pcall(function() el.TextColor3 = _G._hubThemeColor end)
            end
        end
    end)

    -- Sync visuel
    local function updateVisualState(on)
        enableToggle.SetState(on)
        if _G.updateMovementPanelInvisVisual then
            pcall(_G.updateMovementPanelInvisVisual, on)
        end
    end

    _G.syncMiniInvisAutoStealToggle = function(state)
        autoInvisToggle.SetState(state)
    end

    -- Init valeurs
    updateVisualState(_G.invisibleStealEnabled or false)
    rotSlider.Set(Config.InvisStealAngle, true)
    depSlider.Set(Config.SinkSliderValue, true)
    spdSlider.Set(Config.StealSpeed or SharedState.GetStealSpeed(), true)
    autoRecoverToggle.SetState(_G.AutoRecoverLagback ~= false)
    autoInvisToggle.SetState(Config.AutoInvisDuringSteal or false)

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
		task.wait(0.2)
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
            task.wait(0.5)
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
    task.wait(1)
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

-- ================================================
-- KEYBIND TOUCHE I (standalone)
-- ================================================
UserInputService.InputBegan:Connect(function(input, gpe)
    if UserInputService:GetFocusedTextBox() then return end
    local key = Enum.KeyCode[Config.InvisToggleKey] or Enum.KeyCode.I
    if input.KeyCode == key then
        if _G.toggleInvisibleSteal then
            _G.toggleInvisibleSteal()
        end
    end
end)

print("[CNK INVIS] Chargé ! Touche " .. Config.InvisToggleKey .. " = toggle invis")