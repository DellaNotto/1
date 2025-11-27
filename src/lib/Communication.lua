--[[
    Sigma Spy Communication Module
    Handles inter-thread communication, serialization, and channel management
    
    Optimizations:
    - Improved serialization with better cycle detection
    - More efficient queue processing
    - Better memory management with weak tables
    - Reduced yielding overhead
]]

export type CommCallback = (...any) -> ...any

export type CommWrapper = {
    Queue: {{any}},
    Channel: BindableEvent,
    Event: RBXScriptSignal,
    Fire: (self: CommWrapper, ...any) -> (),
    ProcessArguments: (self: CommWrapper, Arguments: {any}) -> (),
    ProcessQueue: (self: CommWrapper) -> (),
    BeginQueueService: (self: CommWrapper) -> ()
}

local Module = {
    CommCallbacks = {} :: {[string]: CommCallback},
    DebugIdRemote = nil :: BindableFunction?,
    DebugIdInvoke = nil :: ((BindableFunction, Instance) -> string)?
}

--// Serializer cache with weak keys for memory efficiency
local SerializeCache = setmetatable({}, {__mode = "k"})
local DeserializeCache = setmetatable({}, {__mode = "k"})

--// Services
local CoreGui: CoreGui

--// Modules
local Hook
local Channel: BindableEvent | CommWrapper
local Config
local Process

--// Tick counter for yielding
local YieldTick = 0
local YIELD_THRESHOLD = 50

--// Localized functions for performance
local table_insert = table.insert
local table_remove = table.remove
local table_clear = table.clear
local typeof = typeof
local next = next
local pcall = pcall
local wait = wait
local coroutine_wrap = coroutine.wrap

--// CommWrapper metatable
local CommWrapper = {}
CommWrapper.__index = CommWrapper

--[[
    Fires data to the wrapped channel's queue
    @param ... any - Arguments to queue
]]
function CommWrapper:Fire(...)
    local Queue = self.Queue
    table_insert(Queue, {...})
end

--[[
    Processes arguments and fires them to the channel
    @param Arguments table - Arguments to process
]]
function CommWrapper:ProcessArguments(Arguments: {any})
    local ChannelObj = self.Channel
    ChannelObj:Fire(Process:Unpack(Arguments))
end

--[[
    Processes all queued items
]]
function CommWrapper:ProcessQueue()
    local Queue = self.Queue
    local QueueLength = #Queue
    
    if QueueLength == 0 then
        return
    end
    
    --// Process in reverse order for efficient removal
    for i = QueueLength, 1, -1 do
        local Arguments = Queue[i]
        Queue[i] = nil
        
        local Success, Error = pcall(function()
            self:ProcessArguments(Arguments)
        end)
        
        if not Success then
            warn("[Communication] Queue processing error:", Error)
        end
    end
end

--[[
    Begins the queue service coroutine
]]
function CommWrapper:BeginQueueService()
    coroutine_wrap(function()
        while true do
            self:ProcessQueue()
            wait()
        end
    end)()
end

--[[
    Initializes the Communication module
    @param Data table - Initialization data
]]
function Module:Init(Data)
    local Modules = Data.Modules
    local Services = Data.Services

    Hook = Modules.Hook
    Process = Modules.Process
    Config = Modules.Config or Config
    CoreGui = Services.CoreGui
end

--[[
    Creates a new communication wrapper for a channel
    @param ChannelEvent BindableEvent - The channel to wrap
    @return CommWrapper - The wrapped channel
]]
function Module:NewCommWrap(ChannelEvent: BindableEvent): CommWrapper
    local Base = {
        Queue = setmetatable({}, {__mode = "v"}),
        Channel = ChannelEvent,
        Event = ChannelEvent.Event
    }

    --// Create new wrapper class
    local Wrapped = setmetatable(Base, CommWrapper)
    Wrapped:BeginQueueService()

    return Wrapped
end

--[[
    Creates the debug ID handler for getting instance debug IDs
    @return BindableFunction - The handler function
]]
function Module:MakeDebugIdHandler(): BindableFunction
    local Remote = Instance.new("BindableFunction")
    
    function Remote.OnInvoke(Object: Instance): string
        return Object:GetDebugId()
    end

    self.DebugIdRemote = Remote
    self.DebugIdInvoke = Remote.Invoke

    return Remote
end

--[[
    Gets the debug ID of an instance
    @param Object Instance - The instance to get the ID for
    @return string - The debug ID
]]
function Module:GetDebugId(Object: Instance): string
    local Invoke = self.DebugIdInvoke
    local Remote = self.DebugIdRemote
    
    if not Invoke or not Remote then
        return tostring(Object)
    end
    
    local Success, Result = pcall(Invoke, Remote, Object)
    
    if Success then
        return Result
    end
    
    return tostring(Object)
end

--[[
    Gets the hidden parent for UI elements
    @return Instance - The hidden parent
]]
function Module:GetHiddenParent(): Instance
    --// Use gethui if available
    if gethui then 
        return gethui() 
    end
    return CoreGui
end

--[[
    Creates a new communication channel
    @return number - The channel ID
    @return BindableEvent - The channel event
]]
function Module:CreateCommChannel(): (number, BindableEvent)
    --// Use native function if available
    local Force = Config and Config.ForceUseCustomComm
    
    if create_comm_channel and not Force then
        return create_comm_channel()
    end

    local Parent = self:GetHiddenParent()
    local ChannelId = math.random(1, 10000000)

    --// Create BindableEvent
    local ChannelEvent = Instance.new("BindableEvent")
    ChannelEvent.Name = tostring(ChannelId)
    ChannelEvent.Parent = Parent

    return ChannelId, ChannelEvent
end

--[[
    Gets an existing communication channel by ID
    @param ChannelId number - The channel ID to find
    @return BindableEvent | CommWrapper - The channel
    @return boolean - Whether the channel is wrapped
]]
function Module:GetCommChannel(ChannelId: number): (BindableEvent | CommWrapper, boolean)
    --// Use native function if available
    local Force = Config and Config.ForceUseCustomComm
    
    if get_comm_channel and not Force then
        local ChannelEvent = get_comm_channel(ChannelId)
        return ChannelEvent, false
    end

    local Parent = self:GetHiddenParent()
    local ChannelEvent = Parent:FindFirstChild(tostring(ChannelId))

    --// Wrap the channel (Prevents thread permission errors)
    local Wrapped = self:NewCommWrap(ChannelEvent)
    return Wrapped, true
end

--[[
    Checks and potentially serializes a value
    @param Value any - The value to check
    @param Inbound boolean? - Whether this is inbound data (deserialize)
    @return any - The processed value
]]
function Module:CheckValue(Value: any, Inbound: boolean?): any
    --// No serializing needed for non-tables
    if typeof(Value) ~= "table" then 
        return Value 
    end
   
    --// Deserialize or serialize based on direction
    if Inbound then
        return self:DeserializeTable(Value)
    end

    return self:SerializeTable(Value)
end

--[[
    Checks if yielding is needed and yields if necessary
]]
function Module:WaitCheck()
    YieldTick = YieldTick + 1
    
    if YieldTick >= YIELD_THRESHOLD then
        YieldTick = 0
        wait()
    end
end

--[[
    Creates a serialized packet from an index and value
    @param Index any - The index
    @param Value any - The value
    @return table - The packet
]]
function Module:MakePacket(Index: any, Value: any): {Index: any, Value: any}
    self:WaitCheck()
    
    return {
        Index = self:CheckValue(Index), 
        Value = self:CheckValue(Value)
    }
end

--[[
    Reads a packet and returns the deserialized index and value
    @param Packet table - The packet to read
    @return any - The index
    @return any - The value
]]
function Module:ReadPacket(Packet: {Index: any, Value: any}): (any, any)
    if typeof(Packet) ~= "table" then 
        return Packet, nil
    end
    
    local Key = self:CheckValue(Packet.Index, true)
    local Value = self:CheckValue(Packet.Value, true)
    self:WaitCheck()

    return Key, Value
end

--[[
    Serializes a table for cross-thread communication
    @param Table table - The table to serialize
    @return table - The serialized table
]]
function Module:SerializeTable(Table: {[any]: any}): {{Index: any, Value: any}}
    --// Check cache for existing serialization
    local Cached = SerializeCache[Table]
    if Cached then 
        return Cached 
    end

    local Serialized = {}
    SerializeCache[Table] = Serialized

    for Index, Value in next, Table do
        local Packet = self:MakePacket(Index, Value)
        table_insert(Serialized, Packet)
    end

    return Serialized
end

--[[
    Deserializes a serialized table
    @param Serialized table - The serialized data
    @return table - The deserialized table
]]
function Module:DeserializeTable(Serialized: {{Index: any, Value: any}}): {[any]: any}
    --// Check cache for existing deserialization
    local Cached = DeserializeCache[Serialized]
    if Cached then 
        return Cached 
    end

    local Table = {}
    DeserializeCache[Serialized] = Table
    
    for _, Packet in next, Serialized do
        local Index, Value = self:ReadPacket(Packet)
        
        if Index == nil then 
            continue 
        end

        Table[Index] = Value
    end

    return Table
end

--[[
    Sets the active communication channel
    @param NewChannel BindableEvent | CommWrapper - The new channel
]]
function Module:SetChannel(NewChannel: BindableEvent | CommWrapper)
    Channel = NewChannel
end

--[[
    Prints a message to the console via communication channel
    @param ... any - Messages to print
]]
function Module:ConsolePrint(...)
    self:Communicate("Print", ...)
end

--[[
    Queues a log entry for processing
    @param Data table - The log data
]]
function Module:QueueLog(Data: {Args: {any}, [string]: any})
    task.spawn(function()
        local SerializedArgs = self:SerializeTable(Data.Args)
        Data.Args = SerializedArgs

        self:Communicate("QueueLog", Data)
    end)
end

--[[
    Adds a communication callback for a specific type
    @param Type string - The callback type
    @param Callback function - The callback function
]]
function Module:AddCommCallback(Type: string, Callback: CommCallback)
    local CommCallbacks = self.CommCallbacks
    CommCallbacks[Type] = Callback
end

--[[
    Gets a communication callback by type
    @param Type string - The callback type
    @return function? - The callback function
]]
function Module:GetCommCallback(Type: string): CommCallback?
    local CommCallbacks = self.CommCallbacks
    return CommCallbacks[Type]
end

--[[
    Indexes a property on a channel (handles both Instance and wrapped types)
    @param ChannelObj any - The channel object
    @param Property string - The property to index
    @return any - The property value
]]
function Module:ChannelIndex(ChannelObj: any, Property: string): any
    if typeof(ChannelObj) == "Instance" then
        return Hook:Index(ChannelObj, Property)
    end

    --// Handle UserData type from some executors
    return ChannelObj[Property]
end

--[[
    Sends data through the communication channel
    @param ... any - Data to communicate
]]
function Module:Communicate(...)
    if not Channel then
        warn("[Communication] No channel set!")
        return
    end
    
    local Fire = self:ChannelIndex(Channel, "Fire")
    Fire(Channel, ...)
end

--[[
    Adds a connection to the communication channel
    @param Callback function - The callback for events
    @return RBXScriptConnection - The connection
]]
function Module:AddConnection(Callback: (...any) -> ()): RBXScriptConnection
    local Event = self:ChannelIndex(Channel, "Event")
    return Event:Connect(Callback)
end

--[[
    Adds a callback for a specific message type
    @param Type string - The message type
    @param Callback function - The callback function
    @return RBXScriptConnection - The connection
]]
function Module:AddTypeCallback(Type: string, Callback: (...any) -> ()): RBXScriptConnection
    local Event = self:ChannelIndex(Channel, "Event")
    
    return Event:Connect(function(ReceivedType: string, ...)
        if ReceivedType ~= Type then 
            return 
        end
        Callback(...)
    end)
end

--[[
    Adds multiple type callbacks at once
    @param Types table - Dictionary of types to callbacks
]]
function Module:AddTypeCallbacks(Types: {[string]: (...any) -> ()})
    for Type, Callback in next, Types do
        self:AddTypeCallback(Type, Callback)
    end
end

--[[
    Creates a new communication channel with default callback handling
    @return number - The channel ID
    @return BindableEvent - The channel event
]]
function Module:CreateChannel(): (number, BindableEvent)
    local ChannelID, Event = self:CreateCommChannel()

    --// Connect GetCommCallback function
    Event.Event:Connect(function(Type: string, ...)
        local Callback = self:GetCommCallback(Type)
        if Callback then
            local Success, Error = pcall(Callback, ...)
            if not Success then
                warn("[Communication] Callback error for", Type, ":", Error)
            end
        end
    end)

    return ChannelID, Event
end

--[[
    Clears the serialization caches
]]
function Module:ClearCaches()
    table_clear(SerializeCache)
    table_clear(DeserializeCache)
end

--// Initialize debug ID handler on module load
Module:MakeDebugIdHandler()

return Module
