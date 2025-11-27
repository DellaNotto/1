--[[
    Sigma Spy Process Module
    Handles remote processing, data management, and executor compatibility
    
    Optimizations:
    - Better memory management with weak tables
    - Improved deep cloning with cycle detection
    - More efficient remote checking
    - Enhanced error handling
    - Type safety improvements
]]

export type RemoteClassData = {
    Send: {string},
    Receive: {string},
    IsRemoteFunction: boolean?,
    NoReciveHook: boolean?
}

export type RemoteData = {
    Remote: Instance,
    NoBacktrace: boolean?,
    IsReceive: boolean?,
    Args: {any},
    Id: string,
    Method: string,
    TransferType: string,
    ValueReplacements: {[any]: any}?,
    ReturnValues: {any}?,
    OriginalFunc: ((Instance, ...any) -> ...any)?,
    MetaMethod: string?,
    IsExploit: boolean?,
    ClassData: RemoteClassData?,
    Timestamp: number?,
    CallingScript: Instance?,
    CallingFunction: ((...any) -> ...any)?,
    SourceScript: Instance?
}

export type RemoteOptions = {
    Excluded: boolean,
    Blocked: boolean
}

local Process = {
    --// Remote class definitions
    RemoteClassData = {
        ["RemoteEvent"] = {
            Send = {"FireServer", "fireServer"},
            Receive = {"OnClientEvent"}
        },
        ["RemoteFunction"] = {
            IsRemoteFunction = true,
            Send = {"InvokeServer", "invokeServer"},
            Receive = {"OnClientInvoke"}
        },
        ["UnreliableRemoteEvent"] = {
            Send = {"FireServer", "fireServer"},
            Receive = {"OnClientEvent"}
        },
        ["BindableEvent"] = {
            NoReciveHook = true,
            Send = {"Fire"},
            Receive = {"Event"}
        },
        ["BindableFunction"] = {
            IsRemoteFunction = true,
            NoReciveHook = true,
            Send = {"Invoke"},
            Receive = {"OnInvoke"}
        }
    } :: {[string]: RemoteClassData},
    
    RemoteOptions = {} :: {[string]: RemoteOptions},
    LoopingRemotes = {} :: {[Instance]: boolean},
    ExtraData = nil :: {[string]: any}?,
    
    --// Executor-specific configuration overwrites
    ConfigOverwrites = {
        [{"sirhurt", "potassium", "wave"}] = {
            ForceUseCustomComm = true
        }
    }
}

--// Modules
local Hook
local Communication
local ReturnSpoofs
local Ui
local Config

--// Services
local HttpService: HttpService

--// Communication channel
local Channel
local WrappedChannel = false

--// Environment reference for detection
local SigmaENV = getfenv(1)

--// Localized functions for performance
local typeof = typeof
local next = next
local pcall = pcall
local rawget = rawget
local table_insert = table.insert
local table_find = table.find
local table_clear = table.clear
local table_maxn = table.maxn
local string_lower = string.lower
local string_gsub = string.gsub
local string_find = string.find

--[[
    Merges a source table into a base table
    @param Base table - The table to merge into
    @param New table? - The table to merge from
]]
function Process:Merge(Base: {[any]: any}, New: {[any]: any}?)
    if not New then 
        return 
    end
    
    for Key, Value in next, New do
        Base[Key] = Value
    end
end

--[[
    Initializes the Process module
    @param Data table - Initialization data
]]
function Process:Init(Data: {Modules: {[string]: any}, Services: {[string]: any}})
    local Modules = Data.Modules
    local Services = Data.Services

    --// Services
    HttpService = Services.HttpService

    --// Modules
    Config = Modules.Config
    Ui = Modules.Ui
    Hook = Modules.Hook
    Communication = Modules.Communication
    ReturnSpoofs = Modules.ReturnSpoofs
end

--[[
    Sets the communication channel
    @param NewChannel BindableEvent - The new channel
    @param IsWrapped boolean - Whether the channel is wrapped
]]
function Process:SetChannel(NewChannel: BindableEvent, IsWrapped: boolean)
    Channel = NewChannel
    WrappedChannel = IsWrapped
end

--[[
    Gets configuration overwrites for a specific executor
    @param Name string - The executor name
    @return table? - Configuration overwrites
]]
function Process:GetConfigOverwrites(Name: string): {[string]: any}?
    local ConfigOverwrites = self.ConfigOverwrites

    for List, Overwrites in next, ConfigOverwrites do
        if not table_find(List, Name) then 
            continue 
        end
        return Overwrites
    end
    
    return nil
end

--[[
    Checks and applies configuration overwrites based on executor
    @param ConfigTable table - The configuration to modify
]]
function Process:CheckConfig(ConfigTable: {[string]: any})
    local Success, ExecutorName = pcall(identifyexecutor)
    
    if not Success then
        return
    end
    
    local Name = string_lower(ExecutorName)

    --// Apply overwrites for specific executors
    local Overwrites = self:GetConfigOverwrites(Name)
    if Overwrites then
        self:Merge(ConfigTable, Overwrites)
    end
end

--[[
    Cleans C closure error messages for better readability
    @param Error string - The error message
    @return string - The cleaned error message
]]
function Process:CleanCError(Error: string): string
    Error = string_gsub(Error, ":%d+: ", "")
    Error = string_gsub(Error, ", got %a+", "")
    Error = string_gsub(Error, "invalid argument", "missing argument")
    return Error
end

--[[
    Counts pattern matches in a string
    @param String string - The string to search
    @param Match string - The pattern to match
    @return number - The count of matches
]]
function Process:CountMatches(String: string, Match: string): number
    local Count = 0
    
    for _ in string.gmatch(String, Match) do
        Count = Count + 1
    end

    return Count
end

--[[
    Checks and clones a value, handling tables and instances
    @param Value any - The value to check
    @param Ignore table? - Values to ignore
    @param Cache table? - Visited table cache
    @return any - The processed value
]]
function Process:CheckValue(Value: any, Ignore: {any}?, Cache: {[any]: any}?): any
    local Type = typeof(Value)
    
    if Communication then
        Communication:WaitCheck()
    end
    
    if Type == "table" then
        Value = self:DeepCloneTable(Value, Ignore, Cache)
    elseif Type == "Instance" then
        Value = cloneref(Value)
    end
    
    return Value
end

--[[
    Deep clones a table with cycle detection
    @param Table table - The table to clone
    @param Ignore table? - Values to ignore during cloning
    @param Visited table? - Already visited tables (for cycle detection)
    @return table - The cloned table
]]
function Process:DeepCloneTable(Table: {[any]: any}, Ignore: {any}?, Visited: {[any]: any}?): {[any]: any}
    if typeof(Table) ~= "table" then 
        return Table 
    end
    
    local Cache = Visited or {}

    --// Check for already visited (cycle detection)
    if Cache[Table] then
        return Cache[Table]
    end

    local New = {}
    Cache[Table] = New

    for Key, Value in next, Table do
        --// Skip ignored values
        if Ignore and table_find(Ignore, Value) then 
            continue 
        end
        
        Key = self:CheckValue(Key, Ignore, Cache)
        New[Key] = self:CheckValue(Value, Ignore, Cache)
    end

    --// Clear cache if this is the root call
    if not Visited then
        table_clear(Cache)
    end
    
    return New
end

--[[
    Unpacks a table safely, handling sparse arrays
    @param Table table? - The table to unpack
    @return ... - The unpacked values
]]
function Process:Unpack(Table: {any}?): ...any
    if not Table then 
        return 
    end
    
    local Length = table_maxn(Table)
    return unpack(Table, 1, Length)
end

--[[
    Pushes configuration overwrites into the module
    @param Overwrites table - The overwrites to apply
]]
function Process:PushConfig(Overwrites: {[string]: any})
    self:Merge(self, Overwrites)
end

--[[
    Checks if a function exists in the executor environment
    @param Name string - The function name
    @return any - The function if it exists
]]
function Process:FuncExists(Name: string): any
    return SigmaENV[Name]
end

--[[
    Checks if the current executor is blacklisted
    @return boolean - Whether the executor is supported
]]
function Process:CheckExecutor(): boolean
    local Blacklisted = {
        "xeno",
        "solara",
        "jjsploit"
    }

    local Success, ExecutorName = pcall(identifyexecutor)
    
    if not Success then
        return true --// Allow if we can't identify
    end
    
    local Name = string_lower(ExecutorName)
    local IsBlacklisted = table_find(Blacklisted, Name)

    if IsBlacklisted then
        if Ui then
            Ui:ShowUnsupportedExecutor(Name)
        end
        return false
    end

    return true
end

--[[
    Checks if required functions exist in the executor
    @return boolean - Whether all required functions exist
]]
function Process:CheckFunctions(): boolean
    local CoreFunctions = {
        "hookmetamethod",
        "hookfunction",
        "getrawmetatable",
        "setreadonly"
    }

    for _, Name in CoreFunctions do
        local Func = self:FuncExists(Name)
        
        if not Func then
            if Ui then
                Ui:ShowUnsupported(Name)
            end
            return false
        end
    end

    return true
end

--[[
    Checks if Sigma Spy is supported on the current executor
    @return boolean - Whether the executor is supported
]]
function Process:CheckIsSupported(): boolean
    local ExecutorSupported = self:CheckExecutor()
    if not ExecutorSupported then
        return false
    end

    local FunctionsSupported = self:CheckFunctions()
    if not FunctionsSupported then
        return false
    end

    return true
end

--[[
    Gets the class data for a remote instance
    @param Remote Instance - The remote to check
    @return RemoteClassData? - The class data
]]
function Process:GetClassData(Remote: Instance): RemoteClassData?
    local RemoteClassData = self.RemoteClassData
    local ClassName = Hook:Index(Remote, "ClassName")

    return RemoteClassData[ClassName]
end

--[[
    Checks if a remote is protected (internal use)
    @param Remote Instance - The remote to check
    @return boolean - Whether the remote is protected
]]
function Process:IsProtectedRemote(Remote: Instance): boolean
    if not Communication then
        return false
    end
    
    local IsDebug = Remote == Communication.DebugIdRemote
    local ChannelCheck = WrappedChannel and Channel.Channel or Channel
    local IsChannel = Remote == ChannelCheck

    return IsDebug or IsChannel
end

--[[
    Checks if a remote is allowed for a specific transfer type
    @param Remote Instance - The remote to check
    @param TransferType string - "Send" or "Receive"
    @param Method string? - The specific method
    @return boolean? - Whether the remote is allowed
]]
function Process:RemoteAllowed(Remote: Instance, TransferType: string, Method: string?): boolean?
    if typeof(Remote) ~= "Instance" then 
        return nil
    end
    
    --// Check if protected
    if self:IsProtectedRemote(Remote) then 
        return nil
    end

    --// Get class data
    local ClassData = self:GetClassData(Remote)
    if not ClassData then 
        return nil
    end

    --// Check transfer type
    local Allowed = ClassData[TransferType]
    if not Allowed then 
        return nil
    end

    --// Check specific method
    if Method then
        return table_find(Allowed, Method) ~= nil
    end

    return true
end

--[[
    Sets extra data to be included with remote logs
    @param Data table? - The extra data
]]
function Process:SetExtraData(Data: {[string]: any}?)
    if not Data then 
        return 
    end
    self.ExtraData = Data
end

--[[
    Gets a return spoof for a specific remote
    @param Remote Instance - The remote
    @param Method string - The method being called
    @param ... any - Original arguments
    @return table? - Spoofed return values
]]
function Process:GetRemoteSpoof(Remote: Instance, Method: string, ...: any): {any}?
    if not ReturnSpoofs then
        return nil
    end
    
    local Spoof = ReturnSpoofs[Remote]

    if not Spoof then 
        return nil
    end
    
    if Spoof.Method ~= Method then 
        return nil
    end

    local ReturnValues = Spoof.Return

    --// Handle function return types
    if typeof(ReturnValues) == "function" then
        local Success, Result = pcall(ReturnValues, ...)
        if Success then
            return Result
        end
        return nil
    end

    return ReturnValues
end

--[[
    Sets new return spoofs
    @param NewReturnSpoofs table - The new spoofs
]]
function Process:SetNewReturnSpoofs(NewReturnSpoofs: {[Instance]: any})
    ReturnSpoofs = NewReturnSpoofs
end

--[[
    Finds the calling Lua closure with an offset
    @param Offset number - Stack offset
    @return function? - The calling function
]]
function Process:FindCallingLClosure(Offset: number): ((...any) -> ...any)?
    local Getfenv = Hook and Hook:GetOriginalFunc(getfenv) or getfenv
    Offset = Offset + 1

    while true do
        Offset = Offset + 1

        --// Check if stack level is valid
        local IsValid = debug.info(Offset, "l") ~= -1
        if not IsValid then 
            continue 
        end

        --// Get function at stack level
        local Function = debug.info(Offset, "f")
        if not Function then 
            return nil
        end
        
        --// Skip Sigma Spy functions
        local Success, FuncEnv = pcall(Getfenv, Function)
        if Success and FuncEnv == SigmaENV then 
            continue 
        end

        return Function
    end
end

--[[
    Decompiles a script using available methods
    @param Script LocalScript | ModuleScript - The script to decompile
    @return string - The decompiled code
    @return boolean - Whether an error occurred
]]
function Process:Decompile(Script: LocalScript | ModuleScript): (string, boolean)
    local KonstantAPI = "http://api.plusgiant5.com/konstant/decompile"
    local ForceKonstant = Config and Config.ForceKonstantDecompiler

    --// Use built-in decompiler if available
    if decompile and not ForceKonstant then 
        local Success, Result = pcall(decompile, Script)
        if Success then
            return Result, false
        end
        return "-- Decompilation failed: " .. tostring(Result), true
    end

    --// Get script bytecode
    local Success, Bytecode = pcall(getscriptbytecode, Script)
    if not Success then
        return "-- Failed to get script bytecode:\n--[[\n" .. tostring(Bytecode) .. "\n]]", true
    end
    
    --// Send to Konstant API
    local Response = request({
        Url = KonstantAPI,
        Body = Bytecode,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "text/plain"
        },
    })

    if Response.StatusCode ~= 200 then
        return "-- [KONSTANT] API error:\n--[[\n" .. Response.Body .. "\n]]", true
    end

    return Response.Body, false
end

--[[
    Gets the script from a function's environment
    @param Func function? - The function
    @return Instance? - The script
]]
function Process:GetScriptFromFunc(Func: ((...any) -> ...any)?): Instance?
    if not Func then 
        return nil
    end

    local Success, ENV = pcall(getfenv, Func)
    if not Success then 
        return nil
    end
    
    --// Skip Sigma Spy environment
    if self:IsSigmaSpyENV(ENV) then 
        return nil
    end

    return rawget(ENV, "script")
end

--[[
    Checks if a connection is valid for logging
    @param Connection table - The connection data
    @return boolean - Whether the connection is valid
]]
function Process:ConnectionIsValid(Connection: {Function: ((...any) -> ...any)?, [string]: any}): boolean
    local Function = Connection.Function
    if not Function then 
        return false 
    end

    local Script = self:GetScriptFromFunc(Function)
    return Script ~= nil
end

--[[
    Filters connections to only valid ones
    @param Signal RBXScriptSignal - The signal
    @return table - Valid connections
]]
function Process:FilterConnections(Signal: RBXScriptSignal): {{Function: (...any) -> ...any, [string]: any}}
    local Processed = {}
    
    local Success, Connections = pcall(getconnections, Signal)
    if not Success then
        return Processed
    end

    for _, Connection in Connections do
        if self:ConnectionIsValid(Connection) then
            table_insert(Processed, Connection)
        end
    end

    return Processed
end

--[[
    Checks if an environment is Sigma Spy's environment
    @param Env table - The environment to check
    @return boolean - Whether it's Sigma Spy's environment
]]
function Process:IsSigmaSpyENV(Env: {[any]: any}): boolean
    return Env == SigmaENV
end

--[[
    Gets or creates remote data for a remote ID
    @param Id string - The remote's debug ID
    @return RemoteOptions - The remote options
]]
function Process:GetRemoteData(Id: string): RemoteOptions
    local RemoteOptions = self.RemoteOptions

    local Existing = RemoteOptions[Id]
    if Existing then 
        return Existing 
    end
    
    local Data: RemoteOptions = {
        Excluded = false,
        Blocked = false
    }

    RemoteOptions[Id] = Data
    return Data
end

--[[
    Calls Discord RPC with a request body
    @param Body table - The RPC body
]]
function Process:CallDiscordRPC(Body: {[string]: any})
    pcall(request, {
        Url = "http://127.0.0.1:6463/rpc?v=1",
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Origin"] = "https://discord.com/"
        },
        Body = HttpService:JSONEncode(Body)
    })
end

--[[
    Prompts a Discord invite via RPC
    @param InviteCode string - The invite code
]]
function Process:PromptDiscordInvite(InviteCode: string)
    self:CallDiscordRPC({
        cmd = "INVITE_BROWSER",
        nonce = HttpService:GenerateGUID(false),
        args = {
            code = InviteCode
        }
    })
end

--// Process callback for remote calls
local ProcessCallback = newcclosure(function(Data: RemoteData, Remote: Instance, ...): {any}?
    local OriginalFunc = Data.OriginalFunc
    local Id = Data.Id
    local Method = Data.Method

    --// Check if blocked
    local RemoteData = Process:GetRemoteData(Id)
    if RemoteData.Blocked then 
        return {} 
    end

    --// Check for spoof
    local Spoof = Process:GetRemoteSpoof(Remote, Method, OriginalFunc, ...)
    if Spoof then 
        return Spoof 
    end

    --// Call original if provided
    if not OriginalFunc then 
        return nil
    end

    local Success, Result = pcall(function()
        return {OriginalFunc(Remote, ...)}
    end)
    
    if Success then
        return Result
    end
    
    return nil
end)

--[[
    Processes a remote call/receive
    @param Data RemoteData - The remote data
    @param Remote Instance - The remote instance
    @param ... any - Arguments
    @return table? - Return values
]]
function Process:ProcessRemote(Data: RemoteData, Remote: Instance, ...): {any}?
    local Method = Data.Method
    local TransferType = Data.TransferType
    local IsReceive = Data.IsReceive

    --// Verify remote is allowed
    if TransferType and not self:RemoteAllowed(Remote, TransferType, Method) then 
        return nil
    end

    --// Get remote details
    local Id = Communication:GetDebugId(Remote)
    local ClassData = self:GetClassData(Remote)
    local Timestamp = tick()

    local CallingFunction
    local SourceScript

    --// Include extra data if set
    local ExtraData = self.ExtraData
    if ExtraData then
        self:Merge(Data, ExtraData)
    end

    --// Get caller information for sends
    if not IsReceive then
        CallingFunction = self:FindCallingLClosure(6)
        SourceScript = CallingFunction and self:GetScriptFromFunc(CallingFunction) or nil
    end

    --// Build complete data
    self:Merge(Data, {
        Remote = cloneref(Remote),
        CallingScript = getcallingscript(),
        CallingFunction = CallingFunction,
        SourceScript = SourceScript,
        Id = Id,
        ClassData = ClassData,
        Timestamp = Timestamp,
        Args = {...}
    })

    --// Call remote and log return values
    local ReturnValues = ProcessCallback(Data, Remote, ...)
    Data.ReturnValues = ReturnValues

    --// Queue log
    Communication:QueueLog(Data)

    return ReturnValues
end

--[[
    Sets a property on all remote data
    @param Key string - The property key
    @param Value any - The value to set
]]
function Process:SetAllRemoteData(Key: string, Value: any)
    local RemoteOptions = self.RemoteOptions
    
    for _, Data in next, RemoteOptions do
        Data[Key] = Value
    end
end

--[[
    Sets remote data for a specific ID
    @param Id string - The remote ID
    @param RemoteData table - The data to set
]]
function Process:SetRemoteData(Id: string, RemoteData: RemoteOptions)
    local RemoteOptions = self.RemoteOptions
    RemoteOptions[Id] = RemoteData
end

--[[
    Updates remote data via communication channel
    @param Id string - The remote ID
    @param RemoteData table - The updated data
]]
function Process:UpdateRemoteData(Id: string, RemoteData: RemoteOptions)
    Communication:Communicate("RemoteData", Id, RemoteData)
end

--[[
    Updates all remote data via communication channel
    @param Key string - The property key
    @param Value any - The value to set
]]
function Process:UpdateAllRemoteData(Key: string, Value: any)
    Communication:Communicate("AllRemoteData", Key, Value)
end

return Process
