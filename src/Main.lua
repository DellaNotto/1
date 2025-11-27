--[[
    Sigma Spy - Main Entry Point
    A comprehensive Roblox remote spy with advanced features
    
    Features:
    - Remote call/receive logging
    - Script generation
    - Return value spoofing
    - Connection viewing
    - Script decompilation
    
    Original Author: depso
    Optimized version with improved performance and stability
    
    Github: https://github.com/depthso/Sigma-Spy
    Discord: https://discord.gg/bkUkm2vSbv
]]

--// Base Configuration
local Configuration = {
    UseWorkspace = false,
    NoActors = false,
    FolderName = "Sigma Spy",
    RepoUrl = "https://raw.githubusercontent.com/depthso/Sigma-Spy/refs/heads/main",
    ParserUrl = "https://raw.githubusercontent.com/depthso/Roblox-parser/refs/heads/main/dist/Main.luau"
}

--// Load configuration overwrites from parameters
local Parameters = {...}
local Overwrites = Parameters[1]

if typeof(Overwrites) == "table" then
    for Key, Value in next, Overwrites do
        Configuration[Key] = Value
    end
end

--// Service handler with automatic cloning
local Services = setmetatable({}, {
    __index = function(self, Name: string): Instance
        local Success, Service = pcall(game.GetService, game, Name)
        
        if not Success then
            error(string.format("[Sigma Spy] Failed to get service: %s", Name))
        end
        
        --// Clone reference if available
        if cloneref then
            return cloneref(Service)
        end
        
        return Service
    end,
})

--// Files module (embedded for single-file distribution)
local Files = (function()
    --INSERT: @lib/Files.lua
end)()

--// Initialize Files module
Files:PushConfig(Configuration)
Files:Init({
    Services = Services
})

--// Script definitions
local Folder = Files.FolderName
local Scripts = {
    --// User configurations (loaded from local files with fallback to templates)
    Config = Files:GetModule(string.format("%s/Config", Folder), "Config"),
    ReturnSpoofs = Files:GetModule(string.format("%s/Return spoofs", Folder), "Return Spoofs"),
    Configuration = Configuration,
    Files = Files,

    --// Core libraries (embedded as base64 for distribution)
    Process = {"base64", "COMPILE: @lib/Process.lua"},
    Hook = {"base64", "COMPILE: @lib/Hook.lua"},
    Flags = {"base64", "COMPILE: @lib/Flags.lua"},
    Ui = {"base64", "COMPILE: @lib/Ui.lua"},
    Generation = {"base64", "COMPILE: @lib/Generation.lua"},
    Communication = {"base64", "COMPILE: @lib/Communication.lua"}
}

--// Services
local Players: Players = Services.Players

--// Load and compile all modules
local Modules = Files:LoadLibraries(Scripts)

--// Extract commonly used modules
local Process = Modules.Process
local Hook = Modules.Hook
local Ui = Modules.Ui
local Generation = Modules.Generation
local Communication = Modules.Communication
local Config = Modules.Config

--// Custom font loading (optional enhancement)
local FontContent = Files:GetAsset("ProggyClean.ttf", true)
local FontJsonFile = Files:CreateFont("ProggyClean", FontContent)

if FontJsonFile then
    Ui:SetFontFile(FontJsonFile)
end

--// Apply executor-specific configuration fixes
Process:CheckConfig(Config)

--// Initialize all modules
Files:LoadModules(Modules, {
    Modules = Modules,
    Services = Services
})

--// Create main UI window
local Window = Ui:CreateMainWindow()

--// Verify executor support
local Supported = Process:CheckIsSupported()

if not Supported then 
    Window:Close()
    return
end

--// Create communication channel for inter-thread messaging
local ChannelId, Event = Communication:CreateChannel()

--// Register communication callbacks
Communication:AddCommCallback("QueueLog", function(...)
    Ui:QueueLog(...)
end)

Communication:AddCommCallback("Print", function(...)
    Ui:ConsoleLog(...)
end)

--// Configure parser value swaps for better code generation
local LocalPlayer = Players.LocalPlayer

Generation:SetSwapsCallback(function(self)
    --// Swap LocalPlayer reference
    self:AddSwap(LocalPlayer, {
        String = "LocalPlayer",
    })
    
    --// Swap Character reference
    if LocalPlayer then
        self:AddSwap(LocalPlayer.Character, {
            String = "Character",
            NextParent = LocalPlayer
        })
    end
end)

--// Create main window content
Ui:CreateWindowContent(Window)

--// Set up communication channel for UI
Ui:SetCommChannel(Event)

--// Start log processing service
Ui:BeginLogService()

--// Generate actor code for parallel thread support
local ActorCode = Files:MakeActorScript(Scripts, ChannelId)

--// Load metamethod and receive hooks
Hook:LoadHooks(ActorCode, ChannelId)

--// Prompt user about function patches
local EnablePatches = Ui:AskUser({
    Title = "Enable function patches?",
    Content = {
        "Function patches can prevent common detections on some executors.",
        "",
        "Enabling this MAY trigger hook detections in some games.",
        "If issues occur, rejoin and select 'No'.",
        "",
        "This does not affect game functionality.",
        "",
        "Recommended: Yes (for most executors)"
    },
    Options = {"Yes", "No"}
}) == "Yes"

--// Begin hooks with user-selected configuration
Event:Fire("BeginHooks", {
    PatchFunctions = EnablePatches
})

--// Log successful initialization
Communication:ConsolePrint("Sigma Spy loaded successfully!")
Communication:ConsolePrint(string.format("Channel ID: %d", ChannelId))

if EnablePatches then
    Communication:ConsolePrint("Function patches enabled")
end
