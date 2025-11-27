--[[
    Sigma Spy Hook Module
    Handles metamethod hooking, remote interception, and function patching
    
    Optimizations:
    - Better hook management
    - Improved error handling
    - More efficient remote processing
    - Enhanced actor support
]]

export type MetaFunc = (Instance, ...any) -> ...any
export type UnkFunc = (...any) -> ...any

local Hook = {
    OriginalNamecall = nil :: MetaFunc?,
    OriginalIndex = nil :: MetaFunc?,
    PreviousFunctions = {} :: {[UnkFunc]: UnkFunc},
    DefaultConfig = {
        FunctionPatches = true
    }
}

--// Modules
local Modules
local Process
local Configuration
local Config
local Communication

--// Executor environment reference
local ExeENV = getfenv(1)

--// Localized functions for performance
local typeof = typeof
local next = next
local pcall = pcall
local newcclosure = newcclosure
local clonefunction = clonefunction
local hookfunction = hookfunction
local getrawmetatable = getrawmetatable
local setreadonly = setreadonly
local checkcaller = checkcaller
local getnamecallmethod = getnamecallmethod
local table_find = table.find
local table_insert = table.insert

--[[
    Hook middleware that handles callback execution
    @param OriginalFunc function - The original function
    @param Callback function - The callback to invoke
    @param AlwaysTable boolean? - Whether to always return a table
    @param ... any - Arguments
    @return any - The result
]]
local HookMiddle = newcclosure(function(OriginalFunc, Callback, AlwaysTable: boolean?, ...)
    --// Invoke callback and check for response
    local Success, ReturnValues = pcall(Callback, ...)
    
    if Success and ReturnValues then
        --// Return packed or unpacked based on flag
        if not AlwaysTable then
            return Process:Unpack(ReturnValues)
        end
        return ReturnValues
    end

    --// Call original function
    if AlwaysTable then
        local CallSuccess, Result = pcall(function()
            return {OriginalFunc(...)}
        end)
        return CallSuccess and Result or {}
    end

    return OriginalFunc(...)
end)

--[[
    Merges source table into base table
    @param Base table - The base table
    @param New table - The source table
]]
local function Merge(Base: {[any]: any}, New: {[any]: any})
    for Key, Value in next, New do
        Base[Key] = Value
    end
end

--[[
    Initializes the Hook module
    @param Data table - Initialization data
]]
function Hook:Init(Data: {Modules: {[string]: any}, Services: {[string]: any}})
    Modules = Data.Modules

    Process = Modules.Process
    Communication = Modules.Communication or Communication
    Config = Modules.Config or Config
    Configuration = Modules.Configuration or Configuration
end

--[[
    Safely indexes an instance property
    @param Object Instance - The instance
    @param Key string - The property name
    @return any - The property value
]]
function Hook:Index(Object: Instance, Key: string): any
    return Object[Key]
end

--[[
    Pushes configuration overwrites
    @param Overwrites table - The overwrites to apply
]]
function Hook:PushConfig(Overwrites: {[string]: any})
    Merge(self, Overwrites)
end

--[[
    Replaces a metamethod using getrawmetatable
    @param Object Instance - The object with the metatable
    @param Call string - The metamethod name
    @param Callback function - The replacement callback
    @return function - The original function
]]
function Hook:ReplaceMetaMethod(Object: Instance, Call: string, Callback: MetaFunc): MetaFunc
    local Metatable = getrawmetatable(Object)
    local OriginalFunc = clonefunction(Metatable[Call])
    
    --// Replace function
    setreadonly(Metatable, false)
    Metatable[Call] = newcclosure(function(...)
        return HookMiddle(OriginalFunc, Callback, false, ...)
    end)
    setreadonly(Metatable, true)

    return OriginalFunc
end

--[[
    Hooks a function using hookfunction
    @param Func function - The function to hook
    @param Callback function - The callback
    @return function - The original function
]]
function Hook:HookFunction(Func: UnkFunc, Callback: UnkFunc): UnkFunc
    local OriginalFunc
    local WrappedCallback = newcclosure(Callback)
    
    OriginalFunc = clonefunction(hookfunction(Func, function(...)
        return HookMiddle(OriginalFunc, WrappedCallback, false, ...)
    end))
    
    return OriginalFunc
end

--[[
    Hooks a metamethod call
    @param Object Instance - The object
    @param Call string - The metamethod name
    @param Callback function - The callback
    @return function - The original function
]]
function Hook:HookMetaCall(Object: Instance, Call: string, Callback: MetaFunc): MetaFunc
    local Metatable = getrawmetatable(Object)
    local Unhooked
    
    Unhooked = self:HookFunction(Metatable[Call], function(...)
        return HookMiddle(Unhooked, Callback, true, ...)
    end)
    
    return Unhooked
end

--[[
    Hooks a metamethod with automatic method selection
    @param Object Instance - The object
    @param Call string - The metamethod name
    @param Callback function - The callback
    @return function - The original function
]]
function Hook:HookMetaMethod(Object: Instance, Call: string, Callback: MetaFunc): MetaFunc
    local Func = newcclosure(Callback)
    
    --// Use getrawmetatable method if configured
    if Config and Config.ReplaceMetaCallFunc then
        return self:ReplaceMetaMethod(Object, Call, Func)
    end
    
    --// Use hookmetamethod
    return self:HookMetaCall(Object, Call, Func)
end

--[[
    Patches functions to prevent common detections
]]
function Hook:PatchFunctions()
    --// Check if patching is disabled
    if Config and Config.NoFunctionPatching then 
        return 
    end

    local Patches = {
        --// Error detection patch for hookfunction
        [pcall] = function(OldFunc, Func, ...)
            local Response = {OldFunc(Func, ...)}
            local Success, Error = Response[1], Response[2]
            local IsC = iscclosure(Func)

            --// Patch c-closure error detection
            if Success == false and IsC then
                local NewError = Process:CleanCError(Error)
                Response[2] = NewError
            end

            --// Stack-overflow detection patch
            if Success == false and not IsC and Error:find("C stack overflow") then
                local Tracetable = Error:split(":")
                local Caller, Line = Tracetable[1], Tracetable[2]
                local Count = Process:CountMatches(Error, Caller)

                if Count == 196 then
                    Communication:ConsolePrint(string.format("C stack overflow patched, count was %d", Count))
                    Response[2] = Error:gsub(string.format("%s:%s: ", Caller, Line), Caller, 1)
                end
            end

            return Response
        end,
        
        --// Environment escape patch
        [getfenv] = function(OldFunc, Level: number?, ...)
            Level = Level or 1

            --// Prevent capture of executor's environment
            if type(Level) == "number" then
                Level = Level + 2
            end

            local Response = {OldFunc(Level, ...)}
            local ENV = Response[1]

            --// Patch __tostring ENV detection
            if not checkcaller() and ENV == ExeENV then
                Communication:ConsolePrint("ENV escape patched")
                return OldFunc(999999, ...)
            end

            return Response
        end
    }

    --// Hook each function
    for Func, Callback in next, Patches do
        local Wrapped = newcclosure(Callback)
        local OldFunc
        
        OldFunc = self:HookFunction(Func, function(...)
            return Wrapped(OldFunc, ...)
        end)

        --// Cache original function
        self.PreviousFunctions[Func] = OldFunc
    end
end

--[[
    Gets the original unhooked function
    @param Func function - The function
    @return function - The original function
]]
function Hook:GetOriginalFunc(Func: UnkFunc): UnkFunc
    return self.PreviousFunctions[Func] or Func
end

--[[
    Runs code on all actors
    @param Code string - The code to run
    @param ChannelId number - The channel ID
]]
function Hook:RunOnActors(Code: string, ChannelId: number)
    if not getactors or not run_on_actor then 
        return 
    end
    
    local Actors = getactors()
    if not Actors then 
        return 
    end
    
    for _, Actor in Actors do 
        pcall(run_on_actor, Actor, Code, ChannelId)
    end
end

--[[
    Processes a remote call
    @param OriginalFunc function - The original function
    @param MetaMethod string - The metamethod used
    @param self Instance - The remote instance
    @param Method string - The method name
    @param ... any - Arguments
    @return any - Return values
]]
local function ProcessRemote(OriginalFunc, MetaMethod: string, self, Method: string, ...)
    return Process:ProcessRemote({
        Method = Method,
        OriginalFunc = OriginalFunc,
        MetaMethod = MetaMethod,
        TransferType = "Send",
        IsExploit = checkcaller()
    }, self, ...)
end

--[[
    Hooks a specific remote type's method via __index
    @param ClassName string - The class name
    @param FuncName string - The function name to hook
]]
function Hook:HookRemoteTypeIndex(ClassName: string, FuncName: string)
    local Remote = Instance.new(ClassName)
    local Func = Remote[FuncName]
    local OriginalFunc

    OriginalFunc = self:HookFunction(Func, function(self, ...)
        --// Check if remote is allowed
        if not Process:RemoteAllowed(self, "Send", FuncName) then 
            return nil
        end

        --// Process the remote data
        return ProcessRemote(OriginalFunc, "__index", self, FuncName, ...)
    end)
    
    --// Clean up temporary instance
    Remote:Destroy()
end

--[[
    Hooks all remote type __index methods
]]
function Hook:HookRemoteIndexes()
    local RemoteClassData = Process.RemoteClassData
    
    for ClassName, Data in next, RemoteClassData do
        local FuncName = Data.Send[1]
        self:HookRemoteTypeIndex(ClassName, FuncName)
    end
end

--[[
    Begins all metamethod hooks
]]
function Hook:BeginHooks()
    --// Hook remote functions
    self:HookRemoteIndexes()

    --// Namecall hook
    local OriginalNameCall
    
    OriginalNameCall = self:HookMetaMethod(game, "__namecall", function(self, ...)
        local Method = getnamecallmethod()
        return ProcessRemote(OriginalNameCall, "__namecall", self, Method, ...)
    end)

    Merge(self, {
        OriginalNamecall = OriginalNameCall
    })
end

--[[
    Hooks the client invoke callback for RemoteFunctions
    @param Remote Instance - The remote function
    @param Method string - The callback method name
    @param Callback function - The hook callback
]]
function Hook:HookClientInvoke(Remote: Instance, Method: string, Callback: MetaFunc)
    local Success, Function = pcall(function()
        return getcallbackvalue(Remote, Method)
    end)

    --// Handle executors that throw on nil callback
    if not Success or not Function then 
        return 
    end
    
    --// Try hookfunction first
    local HookSuccess = pcall(function()
        self:HookFunction(Function, Callback)
    end)
    
    if HookSuccess then 
        return 
    end

    --// Fall back to replacing callback
    Remote[Method] = function(...)
        return HookMiddle(Function, Callback, false, ...)
    end
end

--[[
    Connects multiple remotes for receive hooks
    @param Remotes table - Array of remotes
]]
function Hook:MultiConnect(Remotes: {Instance})
    for _, Remote in next, Remotes do
        self:ConnectClientRecive(Remote)
    end
end

--[[
    Connects a remote for client receive hooking
    @param Remote Instance - The remote to connect
]]
function Hook:ConnectClientRecive(Remote: Instance)
    --// Check if remote class is allowed
    local Allowed = Process:RemoteAllowed(Remote, "Receive")
    if not Allowed then 
        return 
    end

    --// Get class data
    local ClassData = Process:GetClassData(Remote)
    local IsRemoteFunction = ClassData.IsRemoteFunction
    local NoReciveHook = ClassData.NoReciveHook
    local Method = ClassData.Receive[1]

    --// Skip if receive hooks disabled for this class
    if NoReciveHook then 
        return 
    end

    --// Create callback function
    local function Callback(...)
        return Process:ProcessRemote({
            Method = Method,
            IsReceive = true,
            MetaMethod = "Connect",
            IsExploit = checkcaller()
        }, Remote, ...)
    end

    --// Connect based on remote type
    if not IsRemoteFunction then
        local Signal = Remote[Method]
        if Signal and Signal.Connect then
            Signal:Connect(Callback)
        end
    else
        self:HookClientInvoke(Remote, Method, Callback)
    end
end

--[[
    Begins the hook service with libraries
    @param Libraries table - The libraries
    @param ExtraData table? - Extra data to include
    @param ChannelId number - The channel ID
    @param ... any - Additional arguments
]]
function Hook:BeginService(Libraries: {[string]: any}, ExtraData: {[string]: any}?, ChannelId: number, ...: any)
    --// Libraries
    local ReturnSpoofs = Libraries.ReturnSpoofs
    local ProcessLib = Libraries.Process
    local CommunicationLib = Libraries.Communication
    local Generation = Libraries.Generation
    local ConfigLib = Libraries.Config

    --// Check for configuration overwrites
    ProcessLib:CheckConfig(ConfigLib)

    --// Build init data
    local InitData = {
        Modules = {
            ReturnSpoofs = ReturnSpoofs,
            Generation = Generation,
            Communication = CommunicationLib,
            Process = ProcessLib,
            Config = ConfigLib,
            Hook = self
        },
        Services = setmetatable({}, {
            __index = function(_, Name: string): Instance
                local Service = game:GetService(Name)
                return cloneref(Service)
            end,
        })
    }

    --// Initialize libraries
    CommunicationLib:Init(InitData)
    ProcessLib:Init(InitData)

    --// Setup communication channel
    local Channel, IsWrapped = CommunicationLib:GetCommChannel(ChannelId)
    CommunicationLib:SetChannel(Channel)
    
    CommunicationLib:AddTypeCallbacks({
        ["RemoteData"] = function(Id: string, RemoteData)
            ProcessLib:SetRemoteData(Id, RemoteData)
        end,
        ["AllRemoteData"] = function(Key: string, Value)
            ProcessLib:SetAllRemoteData(Key, Value)
        end,
        ["UpdateSpoofs"] = function(Content: string)
            local LoadSuccess, Spoofs = pcall(loadstring(Content))
            if LoadSuccess and Spoofs then
                ProcessLib:SetNewReturnSpoofs(Spoofs)
            end
        end,
        ["BeginHooks"] = function(HookConfig)
            if HookConfig.PatchFunctions then
                self:PatchFunctions()
            end
            self:BeginHooks()
            CommunicationLib:ConsolePrint("Hooks loaded")
        end
    })
    
    --// Configure process module
    ProcessLib:SetChannel(Channel, IsWrapped)
    ProcessLib:SetExtraData(ExtraData)

    --// Initialize hook module
    self:Init(InitData)

    if ExtraData and ExtraData.IsActor then
        CommunicationLib:ConsolePrint("Actor connected!")
    end
end

--[[
    Loads metamethod hooks (main thread and actors)
    @param ActorCode string - Code to run on actors
    @param ChannelId number - The channel ID
]]
function Hook:LoadMetaHooks(ActorCode: string, ChannelId: number)
    --// Hook actors if not disabled
    if Configuration and not Configuration.NoActors then
        self:RunOnActors(ActorCode, ChannelId)
    end

    --// Hook current thread
    self:BeginService(Modules, nil, ChannelId)
end

--[[
    Loads receive hooks for all remotes
]]
function Hook:LoadReceiveHooks()
    if not Config then
        return
    end
    
    local NoReceiveHooking = Config.NoReceiveHooking
    local BlackListedServices = Config.BlackListedServices

    if NoReceiveHooking then 
        return 
    end

    --// Connect new remotes
    game.DescendantAdded:Connect(function(Remote)
        self:ConnectClientRecive(Remote)
    end)

    --// Connect nil instances
    if getnilinstances then
        self:MultiConnect(getnilinstances())
    end

    --// Search existing remotes
    for _, Service in next, game:GetChildren() do
        if table_find(BlackListedServices, Service.ClassName) then 
            continue 
        end
        
        self:MultiConnect(Service:GetDescendants())
    end
end

--[[
    Loads all hooks
    @param ActorCode string - Code for actors
    @param ChannelId number - The channel ID
]]
function Hook:LoadHooks(ActorCode: string, ChannelId: number)
    self:LoadMetaHooks(ActorCode, ChannelId)
    self:LoadReceiveHooks()
end

return Hook
